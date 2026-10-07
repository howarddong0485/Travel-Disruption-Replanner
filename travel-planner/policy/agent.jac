"""PolicyAgent: turn a booking's terms text into an evidenced RefundPolicy.

The LLM (or the rule-based fallback) only proposes a PolicyDraft. Code then checks it
against the source text:

- every excerpt must appear in the source (ignoring case, spacing and quote style);
  evidence records store the source's own wording, never the draft's;
- a partial refund percentage, a fee amount, and a deadline's day or hour count must
  appear in that tier's excerpt, and a fee must be in the booking's currency;
- a field that fails becomes unknown; an unverifiable tier, deadline or tier order,
  a stated ambiguity, or instruction-like text in the terms sends the whole policy
  to review, which reports it as unknown rather than guessing.
"""
import re;
import from schema.common { Evidence, Origin, valid_local, parse_amount_minor }
import from schema.itinerary { ItineraryNode }
import from schema.policy { RefundPolicy, CancellationTier, RefundForm }
import from policy.draft { PolicyDraft, DraftTier }
import from policy.extract_llm { draft_policy_with_llm, llm_configured }
import from policy.extract_rules { extract_terms_rules }

enum ExtractionMethod: str { LLM = "llm", RULES = "rules" }

glob MAX_TERMS_CHARS: int = 20000;
glob INJECTION_PATTERNS: list[str] = [
    r"ignore (?:all |any )?(?:previous|prior|above) instructions",
    r"system prompt", r"you are (?:an? )?(?:ai|assistant|language model)",
    r"disregard (?:the|these|all) (?:rules|terms|instructions)"
];

obj PolicyRequest {
    has policy_id: str;
    has booking: ItineraryNode;
    has terms_text: str;
    has source_ref: str;
    has retrieved_at: str;
    has scope: str = "";
    has tz: str = "";
    has origin: Origin = Origin.MOCK;
}

obj PolicyExtraction {
    has policy: RefundPolicy;
    has evidence: list[Evidence];
    has method: ExtractionMethod;
    has needs_review: bool;
    has notes: list[str] = [];
}

"""Find `excerpt` in `source` ignoring case, whitespace runs and quote style; return the source's own text."""
def locate_excerpt(source: str, excerpt: str) -> str | None {
    words = excerpt.strip().split();
    if not words { return None; }
    quotes = "['‘’\"“”]";
    parts = [re.sub(quotes, quotes, re.escape(w).replace("\\'", "'").replace('\\"', '"')) for w in words];
    found = re.search(r"\s+".join(parts), source, re.IGNORECASE);
    return found.group(0) if found is not None else None;
}

def _numbers(text: str) -> list[str] { return re.findall(r"\d[\d,]*(?:\.\d+)?", text); }

def _integers(text: str) -> list[int] {
    return [int(n.replace(",", "").split(".")[0]) for n in _numbers(text)];
}

def _percent_supported(percent: int, excerpt: str) -> bool {
    if percent in [0, 100] { return True; }
    return re.search(rf"\b{percent}\s*(?:%|percent)", excerpt, re.IGNORECASE) is not None;
}

obj _Review {
    has reasons: list[str] = [];
}

def _check_tier(t: DraftTier, req: PolicyRequest, currency: str, evidence_id: str,
    found: str, notes: list[str], review: _Review) -> CancellationTier {
    tier = CancellationTier(evidence_id=evidence_id);
    if t.refund_percent is not None {
        if 0 <= t.refund_percent <= 100 and _percent_supported(t.refund_percent, found) {
            tier.refund_percent = t.refund_percent;
        } else { notes.append(f"refund percentage {t.refund_percent} not supported by: {found}"); }
    }
    if t.fee_amount.strip() {
        fee = parse_amount_minor(t.fee_amount, currency);
        stated = [parse_amount_minor(n, currency) for n in _numbers(found)];
        if fee is None { notes.append(f"unreadable fee '{t.fee_amount}'"); }
        elif t.fee_currency and t.fee_currency.upper() != currency {
            notes.append(f"fee is in {t.fee_currency}, booking is in {currency}; no conversion is made");
        } elif fee != 0 and fee not in stated { notes.append(f"fee {t.fee_amount} does not appear in: {found}"); }
        else { tier.fee_minor = fee; }
    }
    try { tier.refund_form = RefundForm(t.refund_form.lower()); }
    except ValueError { notes.append(f"unknown refund form '{t.refund_form}'"); }
    if t.deadline_local and t.hours_before_start is not None {
        review.reasons.append(f"tier states both an absolute and a relative deadline: {found}");
    } elif t.deadline_local {
        if not valid_local(t.deadline_local) {
            review.reasons.append(f"unreadable deadline '{t.deadline_local}'");
        } elif int(t.deadline_local[8:10]) not in _integers(found) {
            review.reasons.append(f"deadline day {t.deadline_local[:10]} does not appear in: {found}");
        } else { tier.deadline_local = t.deadline_local; }
    } elif t.hours_before_start is not None {
        h = t.hours_before_start;
        stated_ints = _integers(found);
        if h < 0 or (h not in stated_ints and not (h % 24 == 0 and h // 24 in stated_ints)) {
            review.reasons.append(f"{h} hours before start does not appear in: {found}");
        } else { tier.hours_before_start = h; }
    }
    return tier;
}

"""Check a draft against the request's source text and build the policy and its evidence."""
def verify_draft(draft: PolicyDraft, req: PolicyRequest) -> PolicyExtraction {
    source = req.terms_text;
    currency = req.booking.currency;
    tz = req.tz or req.booking.tz;
    notes: list[str] = [];
    review = _Review();
    evidence: list[Evidence] = [];

    def cite(text: str) -> str {
        for e in evidence { if e.excerpt == text { return e.id; } }
        eid = f"{req.policy_id}-ev{len(evidence) + 1}";
        evidence.append(Evidence(id=eid, source_ref=req.source_ref, excerpt=text,
            retrieved_at=req.retrieved_at, origin=req.origin));
        return eid;
    }

    for pattern in INJECTION_PATTERNS {
        if re.search(pattern, source, re.IGNORECASE) {
            review.reasons.append("terms contain instruction-like text; extraction cannot be trusted");
            break;
        }
    }
    for a in draft.ambiguities { review.reasons.append(f"ambiguous: {a}"); }

    tiers: list[CancellationTier] = [];
    for t in draft.tiers {
        found = locate_excerpt(source, t.excerpt);
        if found is None {
            review.reasons.append(f"excerpt not found in the terms: {t.excerpt}");
            continue;
        }
        tiers.append(_check_tier(t, req, currency, cite(found), found, notes, review));
    }
    open_ended = [i for (i, t) in enumerate(tiers) if not t.deadline_local and t.hours_before_start is None];
    if len(open_ended) > 1 or (open_ended and open_ended[0] != len(tiers) - 1) {
        review.reasons.append("only the last tier may run until the service starts");
    }

    no_show: int | None = None;
    no_show_ev = "";
    if draft.no_show_refund_percent is not None {
        found = locate_excerpt(source, draft.no_show_excerpt) if draft.no_show_excerpt else None;
        if found is None { notes.append("no-show terms have no verifiable excerpt"); }
        elif not (0 <= draft.no_show_refund_percent <= 100 and _percent_supported(draft.no_show_refund_percent, found)) {
            notes.append(f"no-show refund {draft.no_show_refund_percent}% not supported by: {found}");
        } else {
            no_show = draft.no_show_refund_percent;
            no_show_ev = cite(found);
        }
    }

    unknowns = list(dict.fromkeys(draft.unknowns));
    extracted = sum(1 for t in draft.tiers for v in [t.refund_percent, t.fee_amount or None,
        t.deadline_local or t.hours_before_start] if v is not None);
    kept = sum(1 for t in tiers for v in [t.refund_percent, t.fee_minor,
        t.deadline_local or t.hours_before_start] if v is not None);
    confidence = round(kept / extracted, 2) if extracted else 0.0;

    if review.reasons {
        whole = cite(source[:500].strip());
        tiers = [CancellationTier(evidence_id=whole)];
        no_show = None;
        no_show_ev = "";
        confidence = 0.0;
        unknowns = list(dict.fromkeys(unknowns + ["refund percentage", "cancellation terms need review"]));
        evidence = [e for e in evidence if e.id == whole];
    }
    policy = RefundPolicy(id=req.policy_id, booking_node_id=req.booking.id, scope=req.scope,
        tz=tz, currency=currency, retrieved_at=req.retrieved_at, tiers=tiers,
        no_show_refund_percent=no_show, no_show_evidence_id=no_show_ev,
        extraction_confidence=confidence, origin=req.origin, source_text=source, unknowns=unknowns);
    return PolicyExtraction(policy=policy, evidence=evidence, method=ExtractionMethod.RULES,
        needs_review=bool(review.reasons), notes=review.reasons + notes);
}

"""Extract an evidenced RefundPolicy. use_llm=None uses the LLM only when a model is configured."""
def extract_policy(req: PolicyRequest, use_llm: bool | None = None) -> PolicyExtraction {
    want_llm = llm_configured() if use_llm is None else use_llm;
    notes: list[str] = [];
    terms = req.terms_text;
    if len(terms) > MAX_TERMS_CHARS {
        notes.append(f"terms truncated to {MAX_TERMS_CHARS} characters for extraction");
        terms = terms[:MAX_TERMS_CHARS];
    }
    draft: PolicyDraft | None = None;
    method = ExtractionMethod.RULES;
    if want_llm {
        try {
            draft = draft_policy_with_llm(terms, req.booking.title, req.booking.kind.value,
                req.booking.start_local, req.tz or req.booking.tz, req.booking.currency);
            method = ExtractionMethod.LLM;
        } except Exception as e {
            notes.append(f"LLM extraction failed ({type(e).__name__}); used the rule-based extractor");
        }
    }
    result = verify_draft(draft if draft is not None else extract_terms_rules(terms), req);
    result.method = method;
    result.notes = notes + result.notes;
    return result;
}

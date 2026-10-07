"""Rule-based PolicyDraft extraction, used when no LLM is configured or the LLM call fails.

Deliberately narrow: it recognizes a few common phrasings sentence by sentence and
leaves everything else unknown. Its drafts go through the same verification as the LLM's.
"""
import re;
import from datetime { datetime }
import from policy.draft { PolicyDraft, DraftTier }

glob MONTHS: str = "january|february|march|april|may|june|july|august|september|october|november|december";
glob TIME_PATTERN: str = r"(?P<time>\d{1,2}(?::\d{2})?\s*[ap]\.?\s?m\.?)";
glob DATE_PATTERN: str = r"(?P<date>(?:" + MONTHS + r")\s+\d{1,2},\s*\d{4})";
glob RELATIVE_PATTERN: str = r"(?P<count>\d+)\s*(?P<unit>hours?|days?)\s+(?:before|prior to)";
glob AMOUNT_PATTERN: str = r"(?P<symbol>[$€£¥])\s?(?P<amount>\d[\d,]*(?:\.\d{1,2})?)";
glob SYMBOL_CURRENCY: dict[str, str] = {"$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY"};
glob DISCRETIONARY: list[str] = ["discretion", "may be considered", "subject to approval", "case-by-case", "case by case"];

def split_sentences(text: str) -> list[str] {
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+", text.strip()) if s.strip()];
}

def _parse_time(text: str) -> str | None {
    cleaned = re.sub(r"\s+", "", text.lower()).replace(".", "").upper();
    for fmt in ["%I:%M%p", "%I%p"] {
        try { return datetime.strptime(cleaned, fmt).strftime("%H:%M"); }
        except ValueError {}
    }
    return None;
}

def _absolute_deadline(sentence: str, ambiguities: list[str]) -> str {
    found = re.search(DATE_PATTERN, sentence, re.IGNORECASE);
    if found is None { return ""; }
    day = datetime.strptime(re.sub(r"\s+", " ", found.group("date")).title(), "%B %d, %Y");
    clock = re.search(TIME_PATTERN, sentence, re.IGNORECASE);
    hhmm = _parse_time(clock.group("time")) if clock is not None else None;
    if hhmm is None {
        ambiguities.append(f"deadline time not stated: {sentence}");
        return "";
    }
    return day.strftime("%Y-%m-%d") + "T" + hhmm;
}

def _relative_hours(sentence: str) -> int | None {
    found = re.search(RELATIVE_PATTERN, sentence, re.IGNORECASE);
    if found is None { return None; }
    count = int(found.group("count"));
    return count * 24 if found.group("unit").lower().startswith("day") else count;
}

def _form(sentence: str) -> str {
    lowered = sentence.lower();
    if "original payment" in lowered or "original form of payment" in lowered { return "cash"; }
    if "credit" in lowered or "voucher" in lowered { return "credit"; }
    return "unknown";
}

def extract_terms_rules(terms: str) -> PolicyDraft {
    draft = PolicyDraft();
    for sentence in split_sentences(terms) {
        lowered = sentence.lower();
        if `any(word in lowered for word in DISCRETIONARY) {
            draft.ambiguities.append(sentence);
            continue;
        }
        if re.search(r"no[- ]shows?", lowered) {
            if re.search(r"charged (?:for )?the (?:full|entire)", lowered) or "non-refundable" in lowered {
                draft.no_show_refund_percent = 0;
                draft.no_show_excerpt = sentence;
            }
            continue;
        }
        if re.search(r"non-?refundable|no refunds", lowered) {
            draft.tiers.append(DraftTier(excerpt=sentence, refund_percent=0, fee_amount="0", refund_form="none"));
            continue;
        }
        if re.search(r"(?:free cancellation|full refund|cancel free of charge)", lowered) {
            tier = DraftTier(excerpt=sentence, refund_percent=100, fee_amount="0", refund_form=_form(sentence));
            tier.hours_before_start = _relative_hours(sentence);
            if tier.hours_before_start is None {
                tier.deadline_local = _absolute_deadline(sentence, draft.ambiguities);
            }
            draft.tiers.append(tier);
            continue;
        }
        if re.search(r"(?:after|later than) (?:that|this|the) (?:time|deadline|date)", lowered) and "charged" in lowered {
            tier = DraftTier(excerpt=sentence, refund_form=_form(sentence));
            amount = re.search(AMOUNT_PATTERN, sentence);
            if amount is not None {
                tier.fee_amount = amount.group("amount");
                tier.fee_currency = SYMBOL_CURRENCY[amount.group("symbol")];
            }
            if re.search(r"remainder (?:is|will be) refunded|rest (?:is|will be) refunded", lowered) {
                tier.refund_percent = 100;
            }
            draft.tiers.append(tier);
        }
    }
    if not draft.tiers and not draft.ambiguities { draft.unknowns.append("cancellation terms"); }
    if draft.no_show_refund_percent is None { draft.unknowns.append("no-show terms"); }
    return draft;
}

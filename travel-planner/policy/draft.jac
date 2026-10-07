"""Unverified policy drafts, produced by the LLM or the rule-based extractor.

A draft is a proposal: nothing in it is trusted until policy/agent.jac checks
each field against the source text. The `sem` strings are the LLM's instructions
for each field.
"""

obj DraftTier {
    has excerpt: str;
    has deadline_local: str = "";
    has hours_before_start: int | None = None;
    has refund_percent: int | None = None;
    has fee_amount: str = "";
    has fee_currency: str = "";
    has refund_form: str = "unknown";
}
sem DraftTier = "Terms for cancelling before one deadline, or after the last deadline until the service starts.";
sem DraftTier.excerpt = "The exact sentence or clause from the terms that states this tier, copied character for character.";
sem DraftTier.deadline_local = "Absolute deadline as YYYY-MM-DDTHH:MM in the booking's local time, only if the terms state a date. Empty otherwise.";
sem DraftTier.hours_before_start = "Deadline stated relative to the service start, in hours (2 days = 48). None if not stated that way.";
sem DraftTier.refund_percent = "Percentage of the amount paid that is refunded before this deadline: 100 for free or full refund, 0 for non-refundable. None if the terms do not say.";
sem DraftTier.fee_amount = "Cancellation fee exactly as written as a number, e.g. 260.00. Use 0 when the terms say free or no fee. Empty when no amount is stated.";
sem DraftTier.fee_currency = "ISO currency code of the fee if stated or clearly implied by a symbol, e.g. USD for $. Empty otherwise.";
sem DraftTier.refund_form = "How the refund is returned: cash (original payment method), credit (voucher or travel credit), none, or unknown.";

obj PolicyDraft {
    has tiers: list[DraftTier] = [];
    has no_show_refund_percent: int | None = None;
    has no_show_excerpt: str = "";
    has unknowns: list[str] = [];
    has ambiguities: list[str] = [];
}
sem PolicyDraft = "Cancellation and refund terms extracted from one booking's terms text, ordered from the earliest deadline to the last.";
sem PolicyDraft.tiers = "One entry per distinct deadline or period. Empty if the text states no cancellation terms.";
sem PolicyDraft.no_show_refund_percent = "Percentage refunded if the traveler does not show up. None if not stated.";
sem PolicyDraft.no_show_excerpt = "The exact clause stating the no-show terms. Empty if none.";
sem PolicyDraft.unknowns = "Short names of terms the text does not state, such as 'cancellation fee' or 'refund form'.";
sem PolicyDraft.ambiguities = "Clauses that are vague, conditional, discretionary or contradictory, quoted briefly. Empty if the terms are clear.";

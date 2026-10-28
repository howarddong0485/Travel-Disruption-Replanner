"""Person 1 draft contract for the budget ledger; not a shared schema.

All money is in whole cents of the trip's single currency. A trip with no
budget has budget_cents = None, never 0, so it is never reported as having
money left or as being over budget.
"""

glob LEDGER_CONTRACT_VERSION: str = "person1.budget-ledger.v1";

# A booking in one of these categories is committed once it is confirmed, even before it is paid.
glob COMMITTED_BOOKING_CATEGORIES: list[str] = ["transport", "stay"];

"""One item that has a cost, and how the ledger counted it."""
obj LedgerLine {
    has item_id: str;
    has title: str;
    has category: str;
    has cost_cents: int;
    has paid: bool;
    has committed: bool;     # paid, or a confirmed transport/stay booking
}

"""Budget totals for one trip. Each item's cost is counted exactly once."""
obj BudgetLedger {
    has contract_version: str;
    has trip_id: str;
    has currency: str;
    has budget_cents: int | None;      # None = no budget set
    has planned_cents: int;            # every item's cost
    has paid_cents: int;
    has unpaid_cents: int;             # planned minus paid ("Still to pay" in Roam)
    has committed_cents: int;
    has estimated_cents: int;          # planned minus committed
    has contingency_cents: int;        # money set aside for surprises
    has remaining_cents: int | None;   # budget minus planned minus contingency; None = no budget
    has over_budget_cents: int;        # 0 unless planned plus contingency exceeds the budget
    has lines: list[LedgerLine];       # items with a cost, in input order
}

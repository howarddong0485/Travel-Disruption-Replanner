"""Synthetic inputs for a reproducible, storage-free backup demo."""
def demo_trip -> dict[str, any] {
    return {"id": "demo-trip", "destination": "Boston", "currency": "USD", "budget_cents": 200000};
}
def demo_items -> list[dict[str, any]] {
    return [
        {"id": "outdoor-walk", "category": "activity", "title": "Demo outdoor walk", "date": "2026-11-02", "done": False},
        {"id": "dinner", "category": "food", "title": "Demo dinner", "date": "2026-11-02", "done": False}
    ];
}

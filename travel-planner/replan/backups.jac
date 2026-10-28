"""Small synthetic inventory. Prices use Roam's existing two-decimal convention.
These are flexible mock alternatives, not verified provider availability.
"""
glob CATALOG = {
        "transport": [
            ("shuttle", "Mock shuttle", 2500, 45, 0),
            ("taxi", "Mock taxi", 5500, 25, 0),
            ("transfer", "Mock later transfer", 1500, 60, 30)
        ],
        "stay": [
            ("hotel", "Mock flexible check-in hotel", 12000, 30, 0),
            ("guesthouse", "Mock guesthouse", 8000, 30, 30),
            ("central-hotel", "Mock central hotel", 16000, 20, 0)
        ],
        "food": [
            ("cafe", "Mock late-hours cafe", 1800, 45, 0),
            ("dinner", "Mock later dinner", 3500, 60, 30),
            ("takeaway", "Mock takeaway", 1200, 20, 0)
        ],
        "activity": [
            ("museum", "Mock indoor museum", 1800, 60, 0),
            ("gallery", "Mock indoor gallery", 1000, 45, 30),
            ("walk", "Mock self-guided walk", 0, 30, 0)
        ]
};
def backups_for(item: dict[str, any]) -> list[dict[str, any]] {
    return [
        {
            "id": (item["id"] + ":" + key),
            "item_id": item["id"],
            "title": title,
            "cost_cents": cost,
            "duration_minutes": duration,
            "offset_minutes": offset,
            "source": "mock inventory"
        } for (key, title, cost, duration, offset) in CATALOG.get(item["category"], [])
    ];
}

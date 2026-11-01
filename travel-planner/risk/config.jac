"""Tunable risk thresholds. Defaults are placeholders until the team agrees on values (docs/ROADMAP.md)."""

obj RiskConfig {
    has min_transfer_minutes: int = 30;
    has flight_arrival_buffer_minutes: int = 60;
    has long_drive_minutes: int = 240;
    has rain_probability_pct: int = 50;
    has high_rain_probability_pct: int = 80;
    has closing_buffer_minutes: int = 30;
    has deadline_soon_hours: int = 48;
    has outdoor_keywords: list[str] = [
        "hike", "trail", "park", "beach", "garden", "zoo", "kayak", "canoe",
        "picnic", "outdoor", "walking tour", "bike", "boat", "amphitheatre", "lookout"
    ];
}

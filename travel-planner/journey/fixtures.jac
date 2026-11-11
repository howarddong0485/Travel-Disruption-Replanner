"""Synthetic dates, schedules and prices for journey regressions, never live inventory."""
def route -> dict[str, any] {
    return {"version": 1,
        "origin": {"city": "Detroit", "zone": "America/Detroit", "lat": None, "lon": None},
        "return_to": {"city": "Detroit", "zone": "America/Detroit", "lat": None, "lon": None},
        "stops": [
            {"id": "tokyo", "city": "Tokyo", "zone": "Asia/Tokyo", "lat": None, "lon": None, "arrival_date": "2027-01-02", "departure_date": "2027-01-04"},
            {"id": "kyoto", "city": "Kyoto", "zone": "Asia/Tokyo", "lat": None, "lon": None, "arrival_date": "2027-01-04", "departure_date": "2027-01-06"},
            {"id": "osaka", "city": "Osaka", "zone": "Asia/Tokyo", "lat": None, "lon": None, "arrival_date": "2027-01-06", "departure_date": "2027-01-07"}],
        "legs": [{"from_id": a, "to_id": b, "mode": mode, "before_minutes": 60, "after_minutes": 60}
            for (a,b,mode) in [("origin","tokyo","flight"),("tokyo","kyoto","train"),("kyoto","osaka","train"),("osaka","return","flight")]]};
}

def plan -> dict[str, any] {
    rows = [
        ("Outbound", "transport", "2027-01-01", "12:00", 840, "", "origin:tokyo", "2027-01-02", "16:00", 100000),
        ("Tokyo hotel check-in", "stay", "2027-01-02", "18:00", 30, "tokyo", "", "", "", 40000),
        ("Tokyo museum", "activity", "2027-01-03", "10:00", 120, "tokyo", "", "", "", 3000),
        ("Tokyo to Kyoto", "transport", "2027-01-04", "10:00", 150, "", "tokyo:kyoto", "2027-01-04", "12:30", 12000),
        ("Kyoto walk", "activity", "2027-01-04", "14:00", 120, "kyoto", "", "", "", 0),
        ("Kyoto to Osaka", "transport", "2027-01-06", "10:00", 60, "", "kyoto:osaka", "2027-01-06", "11:00", 2000),
        ("Osaka lunch", "food", "2027-01-06", "12:30", 60, "osaka", "", "", "", 2500),
        ("Return", "transport", "2027-01-07", "16:00", 720, "", "osaka:return", "2027-01-07", "14:00", 100000)];
    return {"title": "Three cities from Detroit", "summary": "Synthetic cross-zone schedule for validation.", "journey": route(), "trip_changes": {},
        "changes": [{"item_id": "", "title": title, "category": category, "date": day, "time": time,
            "duration_minutes": duration, "location": stop or leg, "cost_cents": cost, "notes": "Synthetic planning estimate.",
            "stop_id": stop, "leg_id": leg, "arrival_date": arrival_date, "arrival_time": arrival_time}
            for (title,category,day,time,duration,stop,leg,arrival_date,arrival_time,cost) in rows]};
}

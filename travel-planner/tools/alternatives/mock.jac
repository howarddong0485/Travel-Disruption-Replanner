"""Synthetic Boston inventory. Search/refresh never queries or books a provider."""
import datetime;
import from backup.models { BackupCandidate }

def search(destination: str, category: str, now: datetime.datetime) -> list[BackupCandidate] {
    if destination.strip().lower() not in ["boston", "boston, ma", "boston, usa"] {
        return [];
    }
    checked = now.isoformat();
    expires = (now + datetime.timedelta(minutes=15)).isoformat();
    rows = [
        ("indoor-gallery", "Demo indoor gallery", "activity", 1800, "available"),
        ("science-hall", "Demo science hall", "activity", 2400, "available"),
        ("sold-out-exhibit", "Demo sold-out exhibit", "activity", 1200, "unavailable"),
        ("unconfirmed-tour", "Demo unconfirmed tour", "activity", 900, "unknown"),
        ("late-bistro", "Demo late-opening bistro", "food", 2600, "available"),
        ("evening-cafe", "Demo evening cafe", "food", 1900, "available")
    ];
    return [BackupCandidate(id=row[0], title=row[1], category=row[2], destination="Boston",
        currency="USD", estimated_cost_minor=row[3], availability=row[4],
        source_ref="mock://boston-v1/" + row[0], checked_at=checked, expires_at=expires)
        for row in rows if row[2] == category];
}

def refresh(candidate_id: str, now: datetime.datetime) -> BackupCandidate | None {
    for category in ["activity", "food"] {
        for candidate in search("Boston", category, now) {
            if candidate.id == candidate_id { return candidate; }
        }
    }
    return None;
}

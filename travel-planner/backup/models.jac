"""Gehao Dong week-one draft contracts; not the shared AlternativePlan schema."""
obj BackupCandidate {
    has id: str, title: str, category: str, destination: str, currency: str,
        estimated_cost_minor: int, availability: str, source_ref: str,
        checked_at: str, expires_at: str;
}

obj BackupOption {
    has id: str, label: str, replaced_item_id: str, candidate: BackupCandidate,
        activation_condition: str, validation_status: str, validation_notes: list[str];
}

obj BackupPreview {
    has contract_version: str, mode: str, trip_id: str, item_id: str,
        base_snapshot: str, trigger: str, status: str, message: str,
        options: list[BackupOption], exclusions: list[str];
}

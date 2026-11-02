"""Saved-trip entry into the shared backup search/check/refresh/history UI."""
import from server.main { TripView, ItemView }
import from backup.validation_frontend { ValidationLab }
import from planning.frontend { PlanningPanel }

def:pub BackupPanel(trip: TripView, items: list[ItemView], initial_target: str = "",
    initial_trigger: str = "rain", onGenerated: any = None, diagnostics: bool = False, onApplied: any = None) -> JsxElement {
    # Recreate the panel whenever the parent reloads a changed itinerary. The
    # backend also checks the saved snapshot before and after generating results.
    contextKey = JSON.stringify({"trip": trip, "items": items});
    return <section className="backup-panel" aria-label="Saved trip backups"><PlanningPanel key={contextKey} trip_id={trip.id} items={items} onGenerated={onGenerated} onApplied={onApplied}/>
        {(<ValidationLab trip_id={trip.id} initial_target={initial_target} initial_trigger={initial_trigger} diagnostics={True}/>) if diagnostics else None}</section>;
}

def:pub LegacyBackupPanel(trip: TripView, items: list[ItemView], initial_target: str = "", initial_trigger: str = "rain", onGenerated: any = None) -> JsxElement {
    return <ValidationLab trip_id={trip.id} initial_target={initial_target} initial_trigger={initial_trigger} onGenerated={onGenerated}/>;
}

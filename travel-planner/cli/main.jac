"""Terminal access to the same Roam travel service as the web app."""
import argparse;
import asyncio;
import sys;
import from jaclang.server.bridge { BridgeError, BridgeUnavailable }
import from server.main { TripView, ItemView, list_trips, save_trip, list_items,
    save_item, set_item_state, delete_item, delete_trip }

def parser -> argparse.ArgumentParser {
    p = argparse.ArgumentParser(prog="roam", description="Roam: manage travel plans from your terminal.");
    commands = p.add_subparsers(dest="command", required=True);
    commands.add_parser("trips", help="List all trips and their IDs");
    trip = commands.add_parser("new", help="Create a trip");
    trip.add_argument("title"); trip.add_argument("destination");
    trip.add_argument("--start", required=True); trip.add_argument("--end", required=True);
    trip.add_argument("--currency", `default="USD"); trip.add_argument("--budget", `default="0");
    trip.add_argument("--notes", `default="");
    show = commands.add_parser("show", help="Show a trip's items and budget"); show.add_argument("trip_id");
    add = commands.add_parser("add", help="Add an itinerary, booking, packing, or cost item");
    add.add_argument("trip_id"); add.add_argument("title");
    add.add_argument("--category", choices=["activity", "transport", "stay", "food", "packing", "expense"], `default="activity");
    add.add_argument("--date", `default=""); add.add_argument("--time", `default="");
    add.add_argument("--location", `default=""); add.add_argument("--reference", `default="");
    add.add_argument("--notes", `default=""); add.add_argument("--cost", `default="0");
    for name in ["done", "reopen", "paid", "unpaid", "delete-item"] {
        command = commands.add_parser(name, help="Change an item; IDs may be unique prefixes");
        command.add_argument("trip_id"); command.add_argument("item_id");
    }
    remove = commands.add_parser("delete-trip", help="Delete a trip and all its records");
    remove.add_argument("trip_id");
    remove.add_argument("--yes", action="store_true", help="Confirm deletion of the trip and all its items");
    return p;
}

def resolve(prefix: str, ids: list[str], label: str) -> str {
    matches = [value for value in ids if prefix and value.startswith(prefix)];
    if len(matches) != 1 { raise ValueError("Use a unique " + label + " ID or prefix. Run trips/show to see IDs."); }
    return matches[0];
}
def money(cents: int, unit: str) -> str { return f"{unit} {cents / 100:.2f}"; }
def print_item(item: ItemView, unit: str) -> None {
    state = "done" if item.done else "open";
    cost = " | " + money(item.cost_cents, unit) + (" paid" if item.paid else " unpaid") if item.cost_cents else "";
    print(f"{item.id} | {item.category} | {item.title} | {state} | " + (item.date or "Undated") + (" " + item.time if item.time else "") + cost);
    if item.location { print("  Location: " + item.location); }
    if item.reference { print("  Booking ref: " + item.reference); }
    if item.notes { print("  Notes: " + item.notes); }
}

async def dispatch(args: argparse.Namespace) -> int {
    if args.command == "new" {
        trip = await save_trip(title=args.title, destination=args.destination, start_date=args.start,
            end_date=args.end, currency=args.currency, budget=args.budget, notes=args.notes);
        print("Created " + trip.title + " | " + trip.id); return 0;
    }
    trips = await list_trips();
    if args.command == "trips" {
        if not trips { print("No trips yet. Use new to create one."); }
        for trip in trips {
            print(f"{trip.id} | {trip.title} | {trip.destination} | {trip.start_date} — {trip.end_date} | " + money(trip.budget_cents, trip.currency));
        }
        return 0;
    }
    trip_id = resolve(args.trip_id, [trip.id for trip in trips], "trip");
    trip = next(trip for trip in trips if trip.id == trip_id);
    if args.command == "delete-trip" {
        if not args.yes { raise ValueError("Add --yes to confirm deleting the trip and all its records."); }
        await delete_trip(trip_id=trip_id); print("Deleted trip " + trip.title); return 0;
    }
    if args.command == "add" {
        item = await save_item(trip_id=trip_id, title=args.title, category=args.category,
            date=args.date, time=args.time, location=args.location, reference=args.reference,
            notes=args.notes, cost=args.cost);
        print_item(item, trip.currency); return 0;
    }
    items = await list_items(trip_id=trip_id);
    if args.command == "show" {
        print(trip.title + " — " + trip.destination + f" ({trip.start_date} to {trip.end_date})");
        if trip.notes { print("Notes: " + trip.notes); }
        for item in items { print_item(item, trip.currency); }
        total = sum(item.cost_cents for item in items);
        paid = sum(item.cost_cents for item in items if item.paid);
        print("Budget: " + (money(trip.budget_cents, trip.currency) if trip.budget_cents else "Not set"));
        print("Planned: " + money(total, trip.currency) + " | Paid: " + money(paid, trip.currency) + " | Still to pay: " + money(total - paid, trip.currency));
        return 0;
    }
    item_id = resolve(args.item_id, [item.id for item in items], "item");
    item = next(item for item in items if item.id == item_id);
    if args.command == "delete-item" {
        await delete_item(trip_id=trip_id, item_id=item_id); print("Deleted " + item.title); return 0;
    }
    updated = await set_item_state(trip_id=trip_id, item_id=item_id,
        done=True if args.command == "done" else False if args.command == "reopen" else item.done,
        paid=True if args.command == "paid" else False if args.command == "unpaid" else item.paid);
    print_item(updated, trip.currency); return 0;
}

async def main -> int {
    args = parser().parse_args();
    try { return await dispatch(args); }
    except BridgeUnavailable {
        print("Start jac run --dev travel, then set JAC_APP_SERVER_URL to the printed API URL plus /api/server.", file=sys.stderr);
        return 3;
    } except BridgeError as exc {
        print("Travel service: " + (exc.detail or str(exc)), file=sys.stderr); return 1;
    } except ValueError as exc { print(str(exc), file=sys.stderr); return 2; }
}
with entry:__main__ { sys.`exit(asyncio.run(main())); }

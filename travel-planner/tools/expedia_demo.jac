"""Read-only Rapid hotel search; requires server-side environment credentials."""
import argparse;
import json;
import from tools.alternatives.expedia { search_hotels }

with entry:__main__ {
    parser = argparse.ArgumentParser(description="Search an Expedia hotel shortlist for one room");
    parser.add_argument("checkin"); parser.add_argument("checkout");
    parser.add_argument("property_ids", help="Comma-separated numeric Expedia property IDs");
    parser.add_argument("--occupancy", `default="2");
    parser.add_argument("--currency", `default="USD");
    parser.add_argument("--country", `default="US");
    args = parser.parse_args();
    try {
        result = search_hotels(args.checkin, args.checkout,
            [p.strip() for p in args.property_ids.split(",") if p.strip()],
            args.occupancy, args.currency.upper(), args.country.upper());
        print(json.dumps(result, indent=2));
    } except (ValueError, RuntimeError) as error { parser.exit(1, str(error) + "\n"); }
}

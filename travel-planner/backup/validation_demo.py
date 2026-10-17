"""Run from travel-planner: python3 -m backup.validation_demo --scenario rain."""
import argparse
import json
from datetime import datetime
from backup.validation_fixtures import PROFILES, SCENARIOS, run_fixture


def main():
    parser = argparse.ArgumentParser(description="Read-only standalone backup validation fixtures")
    parser.add_argument("--scenario", choices=SCENARIOS, default="rain")
    parser.add_argument("--profile", choices=PROFILES, default="family")
    parser.add_argument("--budget", default="600", help="USD total budget; empty means unknown")
    parser.add_argument("--now", default="2026-10-13T12:00:00+00:00", help="ISO aware clock for reproducibility")
    args = parser.parse_args()
    try:
        result = run_fixture(args.scenario, args.profile, args.budget, datetime.fromisoformat(args.now))
    except ValueError as exc:
        parser.error(str(exc))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

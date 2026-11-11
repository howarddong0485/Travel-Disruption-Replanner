"""jac run tools/wikipedia_demo.jac -- Boston --interest museum"""
import argparse;
import json;
import from tools.wikipedia { destination_summary, search_attractions }

with entry:__main__ {
    parser = argparse.ArgumentParser(description="Fetch destination information and attraction candidates from Wikipedia");
    parser.add_argument("destination", nargs="?", `default="Boston");
    parser.add_argument("--interest", `default="museum");
    parser.add_argument("--limit", type=int, `default=5);
    args = parser.parse_args();
    try {
        print(json.dumps({"destination": destination_summary(args.destination),
            "attractions": search_attractions(args.destination, args.interest, args.limit)},
            ensure_ascii=False, indent=2));
    } except (RuntimeError, ValueError) as error {
        parser.exit(1, str(error) + "\n");
    }
}

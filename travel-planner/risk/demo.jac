"""Print the risk report for a trip fixture.

    jac run risk/demo.jac                      # demo fixture at its fixture clock
    jac run risk/demo.jac -- --json            # same report as JSON
    jac run risk/demo.jac -- PATH [NOW] [--json]
"""
import os;
import sys;
import json;
import from schema.common { to_plain }
import from schema.bundle { load_bundle }
import from risk.analyzer { analyze_trip }

glob DEMO_FIXTURE: str = os.path.join(os.path.dirname(__file__), "..", "fixtures", "demo-trip.json");

with entry:__main__ {
    args = [a for a in sys.argv[1:] if a != "--json"];
    path = args[0] if args else DEMO_FIXTURE;
    with open(path, encoding="utf-8") as handle { now = args[1] if len(args) > 1 else json.load(handle)["fixture_clock"]; }
    flags = analyze_trip(load_bundle(path), now);
    if "--json" in sys.argv {
        print(json.dumps(to_plain(flags), indent=2));
    } else {
        print(f"Risk report as of {now}: {len(flags)} flag(s), mock data\n");
        for f in flags {
            marker = "?" if f.status.value == "unresolved" else "!";
            print(f"[{f.severity.value.upper():6}] {marker} {f.category.value}: {f.summary}");
            print(f"           -> {f.mitigation}");
            if f.evidence_ids { print(f"           evidence: {', '.join(f.evidence_ids)}"); }
        }
    }
}

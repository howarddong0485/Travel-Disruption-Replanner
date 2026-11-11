"""Typed model choice is optional and cannot introduce an unvalidated plan."""
import from datetime { datetime, timezone }
import from unittest.mock { patch }
import from jaclang.byllm.lib { MockLLM }
import from planning.agent { BackupSelection }
import from planning.context { build_context }
import from planning.fixtures { sample_state }
import from planning.engine { generate_plans }

test "BackupAgent selects supplied plans through the actual typed model boundary" {
    now = datetime(2026, 10, 30, 12, tzinfo=timezone.utc);
    (state, facts) = sample_state(now); context = build_context(state, facts, now);
    expected = generate_plans(context, now)["plans"][1]["id"];
    model = MockLLM(outputs=[BackupSelection(plan_ids=[expected], explanation="A distinct supplied indoor option.")]);
    with patch("planning.agent.backup_model", model) {
        result = generate_plans(context, now, use_llm=True);
        assert result["mode"] == "llm" and [p["id"] for p in result["plans"]] == [expected];
    }
    bad = MockLLM(outputs=[BackupSelection(plan_ids=["invented"], explanation="Unsupported")]);
    with patch("planning.agent.backup_model", bad) {
        fallback = generate_plans(context, now, use_llm=True);
        assert fallback["mode"] == "deterministic" and len(fallback["plans"]) == 3;
    }
}

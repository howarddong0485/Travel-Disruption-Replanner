# Contributing

The project is currently in design. Read the [README](README.md), [architecture](docs/ARCHITECTURE.md), and [roadmap](docs/ROADMAP.md) before beginning implementation.

## Component ownership

The basic travel planner is a shared foundation, built first by a temporary lead or pair as a separately scoped task. It accepts basic trip inputs, generates an initial itinerary from mock data, and provides a minimal itinerary view. This foundation task does not occupy one of the five ongoing feature-owner assignments.

Person numbers are placeholders until the team assigns names.

| Person | Owns | Proposed directories |
| --- | --- | --- |
| 1 | Personalization and feasibility: ProfileAgent, mandatory filters, budget ledger, ConstraintValidator, and profile/constraint UI | `profile/`, `filter/`, `budget/`, `validate/` |
| 2 | Policies and risk detection: PolicyAgent, cancellation tracking, RiskAnalyzer, source evidence, and risk/policy UI | `policy/`, `risk/` |
| 3 | Proactive backup planning: BackupAgent, alternative search/refresh adapters, validated Plan B/C options, and backup UI | `backup/`, `tools/alternatives/` |
| 4 | Disruption and dependency-aware replanning: ReplanAgent, disruption simulator, dependency traversal, version-safe patch application, and disruption UI | `replan/`, `events/` |
| 5 | Comparison and traveler control: ComparatorAgent, comparison explanations, review/accept/reject interactions, and shared page shell | `compare/`, `ui/review/`, `ui/shell/` |

Each feature owner owns its logic, feature-specific UI components, tests, and integration. Modules develop independently against agreed inputs/outputs and shared fixtures; runtime dependencies go through those interfaces. Person 5 owns the review UI and page shell, not every feature's UI.

Person 1 supplies the authoritative budget and feasibility calculations; Person 2 supplies evidenced policy/refund rules; Person 5 consumes these outputs instead of duplicating monetary logic. Person 4 owns patch application and trip-version checks; Person 5 calls that interface only after explicit traveler acceptance.

Assign one named owner at a time to shared schemas, orchestration walkers, common tool adapters, fixtures, and CI. The integration role may rotate by phase and is not permanently assigned to Person 1. Shared contract changes require coordination with affected owners. Proposed directories describe future boundaries; the application is not yet implemented.

## Development workflow

1. Open an issue describing the behavior, component owner, dependencies, and acceptance criteria.
2. Agree on any shared schema or interface changes with the integrator first.
3. Create a focused branch, for example `feat/proactive-backups` or `docs/architecture`.
4. Implement against shared fixture data and existing contracts. Keep provider parsing inside tool adapters.
5. Add meaningful checks for changed behavior, especially budget, time, dependencies, and invalid agent output.
6. Open a pull request summarizing the behavior, validation performed, limitations, and affected interfaces. Request review from the component owner and integrator for shared-contract changes.
7. Merge after applicable checks and reviews, then update documentation if behavior or setup changed.

Do not add speculative install commands or describe planned features as implemented. The initial stack decision should establish exact development and test commands and add them to the README. Formal branch protections, CI, and CODEOWNERS are not configured by this documentation; configure them after assigning actual GitHub usernames and choosing the stack.

## Review expectations

- Respect hard traveler constraints; make uncertainty and infeasibility visible.
- Calculate monetary totals and timing in code, with explicit units, currencies, and time zones.
- Preserve source references and freshness for provider facts and policy terms.
- Validate LLM output and bound retries; never silently relax constraints.
- Keep schema changes versioned and provide migration guidance when necessary.
- Cover failure paths such as unavailable inventory, missing policies, stale patches, and provider errors.
- Use synthetic traveler data in fixtures. Do not commit credentials, booking references, payment details, or personal documents.
- Keep paid placement separate from organic recommendation logic under the proposed sponsorship policy.

Documentation-only changes should receive link, example, and consistency checks. Once executable code exists, record the actual test commands and results in each relevant pull request.

# Contributing

The project is currently in design. Read the [README](README.md), [architecture](docs/ARCHITECTURE.md), and [roadmap](docs/ROADMAP.md) before beginning implementation.

## Component ownership

| Primary owner | Scope | Proposed directories |
| --- | --- | --- |
| Person 1 — Integrator | Schemas, orchestrator walkers, validator, CI, shared documentation coordination | `schema/`, `walkers/`, `validate/`, `.github/` |
| Person 2 | Profiles, filters, place tagging, budget ledger | `profile/`, `filter/`, `budget/` |
| Person 3 | Initial planner and mock/live tool adapters | `planner/`, `tools/` |
| Person 4 | Policies, risks, backups, cancellation tracking | `policy/`, `risk/`, `backup/` |
| Person 5 | Replanning, comparison, simulator, interface | `replan/`, `compare/`, `ui/` |

These ownership boundaries apply to human contributors and coding agents. Assign one owner per component and scope each task to explicit files or directories. Collaborate through shared contracts rather than making broad rewrites across other owners' modules. Cross-component changes are allowed when coordinated with the affected owners.

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

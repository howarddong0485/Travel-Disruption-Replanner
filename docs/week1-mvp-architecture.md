# Week 1: MVP Scope and System Architecture

## Product Goal

Build an AI Travel Planner that supports the full trip lifecycle:

1. personalized trip planning,
2. deterministic constraint validation,
3. proactive risk detection,
4. backup Plan B/C generation before travel,
5. real-time and dependency-aware replanning after disruptions, and
6. comparison of replacement plans.

The main product hook is that the system does not wait until a disruption occurs. It identifies vulnerable parts of a trip ahead of time and prepares backup options.

## MVP Scope

### Core features from the current planning document

- **Budget-aware travel planner**
  - tracks budget constraints across the itinerary
  - keeps cost-sensitive choices visible during planning and replanning
- **Initial itinerary generation and optimization**
  - builds a general travel plan under hard timing and traveler constraints
- **Refund / cancellation policy awareness**
  - uses structured policy information when comparing alternatives
- **Proactive backup planner**
  - creates Plan B/C options before the trip for vulnerable itinerary items
  - compares alternatives by cost, convenience, time, refund loss, and experience quality
- **Risk detection**
  - flags tight connections, weather-sensitive activities, long drives, limited opening hours, and non-refundable bookings
- **Real-time travel replanner**
  - rebuilds affected parts of the trip after delays, cancellations, weather changes, closures, or user changes
- **Dependency-aware replanning**
  - understands that changing one booking may affect hotels, rental cars, restaurants, attractions, or later transportation
- **Alternative comparison**
  - presents replacement options with deterministic cost/time/refund comparisons plus an explanation of tradeoffs

### Supplemental features

- Traveler Profile / Trip Memory
- hotel and restaurant filters or modes, including dietary, pet-friendly, and child-friendly constraints
- suggested landmarks based on traveler interests
- updates based on explicit user feedback about recommendations

### Exploratory ideas outside the first MVP

- disruption claims assistance using airline / hotel policies
- user-selectable travel-insurance preferences or coverage strategy
- live booking integrations
- monetization experiments such as mock ads
- sponsorships, subject to ranking-quality and conflict-of-interest concerns

## End-to-End Workflow

```text
Traveler Input
    ↓
ProfileAgent
    ↓
PlannerAgent
    ↓
ConstraintValidator
    ↓
PolicyAgent / Policy Data
    ↓
RiskAnalyzer
    ↓
BackupAgent
    ↓
Initial Trip + Plan B/C
    ↓
Disruption Event
    ↓
ReplanAgent
    ↓
ConstraintValidator
    ↓
ComparatorAgent
    ↓
Updated Trip + Alternative Comparison
```

## Agent and Component Responsibilities

### Orchestrator Walker
Routes the trip lifecycle and coordinates calls between agents and deterministic components.

### ProfileAgent
Uses an LLM to convert free-text traveler preferences into a structured `TravelerProfile`.

Example fields:
- budget
- dining preferences
- pets
- children
- interests
- travel pace
- risk tolerance

### PlannerAgent
Uses an LLM plus external tools to build the initial itinerary under hard constraints.

### PolicyAgent
Extracts or converts airline, hotel, and booking terms into structured refund and cancellation policy data.

### RiskAnalyzer
Primarily deterministic. Flags risky itinerary components such as:
- tight connections
- weather-sensitive activities
- long drives
- limited opening hours
- non-refundable bookings

A small LLM call may be used for subjective classification, such as determining whether an attraction is weather-sensitive.

### BackupAgent
Uses an LLM plus tools to generate Plan B/C alternatives for vulnerable itinerary components before the trip.

### ReplanAgent
Repairs only the affected portion of the trip after a disruption rather than regenerating the entire itinerary.

### ComparatorAgent
Uses deterministic code to compare:
- cost
- travel time
- refund loss
- schedule impact

The LLM may evaluate experience quality and explain the tradeoffs to the user.

### ConstraintValidator
Deterministically rejects plans that violate hard constraints such as:
- budget
- timing
- opening hours
- pet requirements
- child requirements
- impossible travel times

Validation errors are fed back to the planner/replanner for a limited number of retries.

## LLM vs. Deterministic Code

### LLM responsibilities

- interpret free-text traveler preferences
- generate candidate itineraries
- extract structured policy information from text
- classify subjective travel risks
- generate backup alternatives
- explain recommendations and tradeoffs
- repair affected trip segments after disruptions

### Deterministic-code responsibilities

- cost calculations
- travel-time calculations
- refund-loss calculations
- schedule consistency
- opening-hour validation
- budget validation
- hard traveler constraints
- risk rules where objective thresholds are available
- ranking metrics where exact calculations are possible

The LLM should not be trusted to perform calculations that can be done reliably in code.

## Initial Shared Data Model

The exact Jac schema will be finalized during implementation, but the MVP should support at least:

### TravelerProfile
- budget
- interests
- dining preferences
- pet requirements
- child requirements
- pace
- risk tolerance

### Trip
- origin
- destination(s)
- dates
- travelers
- budget
- itinerary days
- total estimated cost

### TripItem
- type: flight / hotel / activity / restaurant / ground transport
- start time
- end time
- location
- estimated cost
- reservation information
- refund policy
- dependencies
- risk flags

### RefundPolicy
- refundable / non-refundable
- cancellation deadline
- refund amount or percentage
- change fee
- source text / confidence where applicable

### RiskFlag
- risk type
- severity
- explanation
- triggering condition

### AlternativePlan
- affected trip item(s)
- replacement items
- additional cost
- travel-time difference
- refund loss
- constraint-validation result
- experience score / explanation

## External Data / Tool Strategy

Potential sources identified during planning:

- Expedia Group APIs: lodging / travel inventory
- Google Places API: restaurants, attractions, landmarks, hotels, opening hours, ratings, categories
- Yelp Fusion API: restaurants and local businesses
- OpenWeather API: current weather and forecasts

### MVP integration strategy

Start with mock tool responses so the agent workflow can be developed and tested independently of API availability and rate limits.

Recommended order for real integrations:
1. weather,
2. places / attractions / restaurants,
3. routing / travel-time data,
4. flight / hotel inventory if feasible.

## Proposed Component Ownership

To minimize overlapping edits, each team member should primarily own a component area.

| Owner | Primary responsibility | Suggested directories |
|---|---|---|
| 1 — Integrator | shared schema, orchestration, validation, CI | `schema/`, `walkers/`, `validate/` |
| 2 — Profile | traveler profile, filters, budget ledger | `profile/`, `filter/`, `budget/` |
| 3 — Planner | initial planner and external tool layer | `planner/`, `tools/` |
| 4 — Risk / Backup | policies, risk analysis, proactive backup plans | `policy/`, `risk/`, `backup/` |
| 5 — Replan / UI | disruption replanning, comparison, UI | `replan/`, `compare/`, `ui/` |

This ownership model does not prevent collaboration or review; it is intended to reduce conflicting edits and make issue ownership clear.

## Initial Repository Structure

```text
schema/
walkers/
validate/
profile/
filter/
budget/
planner/
tools/
policy/
risk/
backup/
replan/
compare/
ui/
docs/
```

Implementation directories can be created as the first vertical slice is built rather than all at once.

## Next Vertical Slice

The next implementation milestone should demonstrate a minimal end-to-end path:

```text
Traveler free-text input
    ↓
Structured TravelerProfile
    ↓
Basic itinerary generated from mock tools
    ↓
ConstraintValidator checks the itinerary
    ↓
One risk is detected
    ↓
One backup alternative is generated
```

This slice is intentionally narrow so the team can validate the architecture before implementing the full planner.

## Definition of Done for This Planning Issue

- MVP scope and non-goals are documented
- end-to-end workflow is documented
- agent responsibilities are documented
- LLM and deterministic-code boundaries are defined
- initial data-model requirements are defined
- team component ownership is documented
- API/tool strategy is documented
- next implementation milestone is identified

Closes #1

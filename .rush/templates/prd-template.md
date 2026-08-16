<!-- Budget: 200 lines. Density over completeness. -->
<!-- PRODUCT artifact: what and why. No technology, no endpoints, no screens, no data schemas —
     those belong to architecture.md and spec.md. If it would still be true after a full
     rewrite of the stack, it belongs here; if it wouldn't, it doesn't. -->
<!-- Filled by /rush-prd. Location: specs/{{FEATURE_ID}}/prd.md (or specs/prd.md for a
     product-level PRD covering the whole backlog). -->

# PRD: {{PRODUCT_OR_FEATURE_TITLE}}

## Vision

<!-- One paragraph: the world this makes true that isn't true today. No implementation, no
     roadmap — just the destination. -->
{{VISION_STATEMENT}}

## Goals

<!-- 3-7 outcomes, not tasks. Each must be falsifiable: a reader can later say "we hit this" or
     "we didn't" without needing to ask anyone what it meant. -->
1. {{GOAL_1}}
2. {{GOAL_2}}

## Requirements

<!-- Numbered, testable statements ("the system MUST/SHOULD ..."). Each one must be verifiable
     by a test a QA person could write without reading code. No UI layout, no tech stack, no
     endpoint names — that is spec.md's job once a feature is broken out. -->
- **R1.** {{REQUIREMENT_1}}
- **R2.** {{REQUIREMENT_2}}

## Success Criteria

<!-- Measurable AND technology-agnostic — a number or an observable state, never an
     implementation move. Good: "95th percentile checkout completes in under 3s". Bad: "add a
     cache layer". -->
- {{SUCCESS_CRITERION_1}}
- {{SUCCESS_CRITERION_2}}

## User Journeys

<!-- Each journey is a named, numbered sequence of steps a real user takes end to end, in
     user-observable terms only (no screens, no components). These become the journey tests
     referenced in specs/integration-map.md — write each step so it could become a test line
     without guessing. -->

### {{JOURNEY_ID}}: {{JOURNEY_TITLE}}
1. {{STEP_1}}
2. {{STEP_2}}

## Context

<!-- Background a reader needs to interpret the rest: market, constraints, prior art, related
     features. Keep it to what changes the reader's understanding, not history for its own
     sake. -->
{{CONTEXT_NOTES}}

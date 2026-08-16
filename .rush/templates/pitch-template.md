<!-- Budget: 60 lines. Density over completeness. -->
<!-- PRODUCT artifact: the problem and the appetite to solve it. Never technology, endpoints,
     schemas or screens — those belong to architecture/spec. If a sentence names a library, a
     table or a component, it does not belong in a pitch. -->
<!-- Filled by /rush-pitch. Location: specs/{{FEATURE_ID}}/pitch.md -->

# Pitch: {{FEATURE_TITLE}}

## Problem

<!-- The pain in the user's own terms, one or two paragraphs or a short list of concrete
     symptoms. No solution language: "users can't reconcile refunds" not "we need a refunds
     dashboard". -->
{{PROBLEM_STATEMENT}}

## Who It's For

<!-- The actual user/persona and the situation they're in, not a demographic profile. -->
{{TARGET_USER}}

## Appetite

<!-- A time/effort budget, not an estimate: it fixes scope to fit the time available, it does
     not predict how long the work will take. Always pair it with a circuit breaker — what
     happens if the appetite runs out before the shape converges. -->
- Budget: {{APPETITE_BUDGET}} <!-- e.g. "2 weeks, 1 engineer" -->
- Circuit breaker: {{CIRCUIT_BREAKER}}

## Solution

<!-- Broad strokes only — the shape a reader could sketch on a napkin. No component names, no
     data model, no library choice: that is architecture's job, not this artifact's. -->
{{SOLUTION_SKETCH}}

## Risks

<!-- Rabbit holes: specific details that could blow the appetite if not bounded now. -->
- {{RISK_1}}
- {{RISK_2}}

## Out of Scope

<!-- Explicit no-gos — the line that stops scope creep mid-build. Tempting adjacent work goes
     here by name, not left implicit. -->
- {{OUT_OF_SCOPE_1}}
- {{OUT_OF_SCOPE_2}}

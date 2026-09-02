<!-- Density over completeness: as long as the content honestly requires, never padded to look
     thorough, never truncated to hit a number. -->
<!-- SPEC artifact: observable technical WHAT — interfaces, data, states, edge cases. Never
     internal implementation detail (class layout, variable names, private helpers — that's
     plan.md), never agent process ("run the test suite", "commit at the end" — that's harness
     config in .rush/config.json), and never acceptance criteria or the Definition of Done —
     those live in done-contract.md now, merged with the checks that enforce them, so a criterion
     is never separated from what proves it. -->
<!-- Filled by /rush-spec. Location: specs/{{FEATURE_ID}}/spec.md -->

# Spec: {{FEATURE_TITLE}}

## Behaviour

<!-- What the system does, observable from outside. A tester should be able to verify this
     without reading the implementation. -->
{{BEHAVIOUR_DESCRIPTION}}

## Interfaces

<!-- Every entry links a contract file — never inline a copy of a contract owned elsewhere.
     Must stay consistent with specs/integration-map.md; do not invent an entry here that the
     map doesn't also carry. -->

### Provides

<!-- What this feature exposes to the rest of the system. -->
- `{{KIND}}` **{{NAME}}** — see `{{CONTRACT_PATH}}#{{POINTER}}`

### Consumes

<!-- What this feature calls, and which feature provides it. Must resolve to a provider already
     declared in the integration map — never invent an interface another feature is supposed to
     provide; that gap is a finding to report instead. -->
- `{{KIND}}` **{{NAME}}** from `{{PROVIDING_FEATURE_ID}}` — see `{{CONTRACT_PATH}}#{{POINTER}}`

## Data

<!-- Entities touched, who owns them, their lifecycle. Migrations are flagged here, not
     designed here. -->
- {{ENTITY_1}}: {{OWNERSHIP_AND_LIFECYCLE_1}}

## Edge Cases & Failure Modes

<!-- What happens on invalid input, a dependency being down, an operation being retried. A spec
     without this is half a spec. -->
- {{EDGE_CASE_1}} → {{EXPECTED_BEHAVIOUR_1}}
- {{EDGE_CASE_2}} → {{EXPECTED_BEHAVIOUR_2}}

## Out of Scope

<!-- The anti-scope-creep line: what this feature explicitly does not do. -->
- {{OUT_OF_SCOPE_1}}

## Assumptions

<!-- Every informed default chosen instead of asking. If an assumption turns out wrong, this is
     where a reader finds out why it was made in the first place. -->
- {{ASSUMPTION_1}}

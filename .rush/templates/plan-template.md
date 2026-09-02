<!-- Density over completeness: as long as the content honestly requires, never padded to look
     thorough, never truncated to hit a number. -->
<!-- PLAN artifact: the HOW of implementation. Never redefines behaviour — that's spec.md's
     job; if the plan needs behaviour the spec doesn't describe, fix the spec first, don't let
     this drift ahead of it. -->
<!-- Filled by /rush-spec. Location: specs/{{FEATURE_ID}}/plan.md -->

# Plan: {{FEATURE_TITLE}}

## Approach

<!-- The implementation strategy in a few sentences: what gets built, in what shape, using what
     already exists. Not a restatement of the spec's behaviour. -->
{{APPROACH_SUMMARY}}

## Files & Modules Affected

<!-- Concrete paths, new or modified. This is exactly what check-as-built.sh diffs against the
     real git history — keep it accurate, not aspirational. -->
- `{{PATH_1}}` — {{WHAT_CHANGES_1}}
- `{{PATH_2}}` — {{WHAT_CHANGES_2}}

## Order of Work

<!-- Sequenced steps at module granularity, in dependency order. Not the task list (tasks.md
     owns individually-verifiable units) — this is the shape of the sequence. -->
1. {{STEP_1}}
2. {{STEP_2}}

## Risks

<!-- Technical risks specific to this implementation approach — not product risk (the pitch's
     job) and not a structural trade-off (architecture.md's job). -->
- {{RISK_1}}

## Alternatives Rejected

<!-- Implementation-level alternatives considered and why not chosen. A structural alternative
     belongs in an ADR, not here. -->
- **{{ALTERNATIVE_1}}** — rejected because {{REASON_1}}

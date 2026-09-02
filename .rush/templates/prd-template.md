<!-- PRD artifact (SPEC level): the complete product definition of everything this spec will
     build. It is the first artifact of the L flow and the one every later artifact is traced
     back to — architecture reads it to decide structure, /rush-features splits it into feature
     units, each feature's own prd.md cites its requirement ids, and /rush-analyze checks that
     nothing downstream contradicts it. -->
<!-- Length: whatever the product honestly requires. A spec covering a real system does not fit
     in two pages, and truncating it just moves the missing decisions into someone's head. What
     is NOT welcome is padding: restating the same requirement three ways, background nobody
     acts on, or prose written to look thorough. Every line should change what someone builds,
     tests or rejects. -->
<!-- Technology-agnostic. No stack, no endpoint, no table, no screen, no library. If a sentence
     would stop being true after a full rewrite of the implementation, it belongs in
     architecture.md or spec.md, not here. The one exception is a constraint the business
     genuinely imposes ("must run on the customer's existing Postgres") — that is a constraint,
     and it goes under Constraints and Dependencies with the reason attached. -->
<!-- Filled by /rush-prd. Location: specs/{{SPEC_ID}}/prd.md -->

# PRD: {{SPEC_TITLE}}

**Spec**: `specs/{{SPEC_ID}}/` · **Status**: {{DRAFT_OR_APPROVED}} · **Last updated**: {{DATE}}

## Overview

<!-- The problem, who has it, what changes when this exists, and the one-paragraph shape of the
     answer. A reader who stops here should be able to say what is being built and why it is
     worth building. If a pitch.md exists, this is where its problem statement is carried
     forward and sharpened — not copied. -->

### Problem

{{PROBLEM_STATEMENT}}

### Vision

{{VISION_STATEMENT}}

## Users and Use Cases

<!-- Who this is for, in the situation they are actually in — not a demographic. One subsection
     per distinct user type whose needs differ enough to change what gets built; if two "types"
     want the same thing, they are one type. Each carries the jobs they are trying to do, so a
     requirement below can be traced to somebody who wanted it. -->

### {{USER_TYPE_1}}

- **Context**: {{WHEN_AND_WHERE_THEY_HIT_THIS}}
- **Jobs to be done**: {{WHAT_THEY_ARE_TRYING_TO_ACCOMPLISH}}
- **Today's workaround**: {{WHAT_THEY_DO_WITHOUT_THIS_AND_WHAT_IT_COSTS}}

## Goals

<!-- Outcomes, not tasks, and each one falsifiable: a reader must later be able to say "we hit
     this" or "we didn't" without asking anyone what it meant. Ordered by priority, because the
     order is what gets used when something has to be cut. -->

1. {{GOAL_1}}
2. {{GOAL_2}}

## Out of Scope

<!-- Named explicitly, with the reason. This is the line that stops scope creep three weeks in,
     and the reason is what stops it being re-litigated every week. "Not now" and "not ever" are
     different — say which. -->

- **{{EXCLUDED_1}}** — {{WHY_AND_WHETHER_EVER}}

## Functional Requirements

<!-- Numbered `FR-NNN`, stable for the life of the spec (never renumber — a feature's prd.md and
     the traceability tables cite these ids). Each one testable: phrased so someone could write a
     pass/fail check without asking you what you meant.

     Prefer the EARS shapes, which remove most ambiguity for free:
       Ubiquitous  — THE SYSTEM SHALL <behaviour>
       Event       — WHEN <trigger> THE SYSTEM SHALL <behaviour>
       State       — WHILE <state> THE SYSTEM SHALL <behaviour>
       Conditional — IF <condition> THEN THE SYSTEM SHALL <behaviour>
       Optional    — WHERE <feature is included> THE SYSTEM SHALL <behaviour>

     Group by capability, not by layer. Mark priority where the appetite implies cuts are
     likely. A requirement you cannot yet settle gets `[NEEDS CLARIFICATION]` and an entry in
     the spec's questions.md — never a vague sentence that hides the gap. -->

### {{CAPABILITY_GROUP_1}}

| Id | Requirement | Priority | Serves |
|---|---|---|---|
| FR-001 | {{REQUIREMENT_TEXT}} | must \| should \| could | {{GOAL_OR_USER_TYPE}} |

## Quality Attributes

<!-- The non-functional requirements, each with a MEASURABLE target and the condition it holds
     under — "fast" and "secure" are not requirements. These are what /rush-architect turns into
     fitness functions, so write each one so a check could assert it.

     Cover the ones that apply and say `N/A because …` for the ones that do not; a silently
     skipped row is how a system ships with no accessibility story and nobody noticing. -->

| Attribute | Target | Condition | How it will be judged |
|---|---|---|---|
| Performance | {{TARGET}} | {{UNDER_WHAT_LOAD}} | {{OBSERVABLE_CHECK}} |
| Availability | {{TARGET}} | {{OVER_WHAT_WINDOW}} | {{OBSERVABLE_CHECK}} |
| Security and privacy | {{TARGET}} | {{FOR_WHAT_DATA}} | {{OBSERVABLE_CHECK}} |
| Accessibility | {{TARGET}} | {{FOR_WHOM}} | {{OBSERVABLE_CHECK}} |
| Compliance | {{TARGET}} | {{WHICH_REGIME}} | {{OBSERVABLE_CHECK}} |
| Observability | {{TARGET}} | {{FOR_WHICH_FLOWS}} | {{OBSERVABLE_CHECK}} |

## Domain and Data

<!-- The concepts this system reasons about, at the level a domain expert would recognise:
     entity, what it means, who owns it, how it comes into being and what ends it. No schema,
     no column types, no storage choice — those are architecture's. What belongs here is the
     part a rewrite would not change: the meaning, the ownership, the lifecycle, and the rules
     that must hold regardless of how it is stored. -->

| Concept | Means | Owned by | Lifecycle | Invariants |
|---|---|---|---|---|
| {{ENTITY_1}} | {{DEFINITION}} | {{OWNER}} | {{CREATED_TO_RETIRED}} | {{WHAT_MUST_ALWAYS_HOLD}} |

## User Journeys

<!-- Each journey is one end-to-end path a real user takes, in user-observable terms only. These
     are not narrative colour: /rush-features turns each into a journey test that must pass for
     the delivery to close, so a step written vaguely produces a test nobody can write. Include
     the unhappy paths that matter — a journey with only its happy path is half a journey. -->

### {{JOURNEY_ID}}: {{JOURNEY_TITLE}}

- **Actor**: {{WHICH_USER_TYPE}}
- **Precondition**: {{WHAT_IS_TRUE_BEFORE}}
- **Covers**: {{FR_IDS}}

1. {{STEP_1}}
2. {{STEP_2}}

- **Success**: {{WHAT_THE_USER_ENDS_UP_WITH}}
- **When it goes wrong**: {{THE_FAILURE_THAT_MATTERS_AND_WHAT_THE_USER_SEES}}

## Constraints and Dependencies

<!-- What is fixed before anyone designs anything: regulation, existing systems that must be
     integrated with, platforms that must be supported, deadlines that are real, budget the
     business has actually set. Each with the source of the constraint — an unattributed
     constraint gets argued with forever. -->

| Constraint | Source | Consequence if ignored |
|---|---|---|
| {{CONSTRAINT_1}} | {{WHO_OR_WHAT_IMPOSES_IT}} | {{WHAT_BREAKS}} |

## Success Metrics

<!-- How anyone will know, after shipping, whether this worked — measured on users or the
     business, never on the system's internals. "p95 latency under 300ms" is a quality attribute,
     not a success metric; "users complete checkout without abandoning" is a success metric.
     Each needs a baseline (what it is today) or an explicit "unknown, will measure first". -->

| Metric | Baseline today | Target | Measured how | By when |
|---|---|---|---|---|
| {{METRIC_1}} | {{BASELINE_OR_UNKNOWN}} | {{TARGET}} | {{SOURCE_OF_TRUTH}} | {{HORIZON}} |

## Risks

<!-- What could make this the wrong thing to build, or make it fail even if built correctly.
     Each with what would tell you early that it is happening. A risk with no early signal is a
     risk you will discover at launch. -->

| Risk | Impact if it lands | Early signal | Mitigation |
|---|---|---|---|
| {{RISK_1}} | {{IMPACT}} | {{WHAT_YOU_WOULD_SEE_FIRST}} | {{RESPONSE}} |

## Assumptions

<!-- Every informed default taken instead of asking, and everything believed to be true without
     having verified it. This is the section that ages fastest and matters most in review: an
     assumption written down can be checked, an assumption in someone's head cannot. Anything
     still genuinely open belongs in the spec's questions.md as well, with the assumption
     adopted meanwhile. -->

- {{ASSUMPTION_1}} — {{WHY_WE_BELIEVE_IT_AND_WHAT_CHANGES_IF_WRONG}}

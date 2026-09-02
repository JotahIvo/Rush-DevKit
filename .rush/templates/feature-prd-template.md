<!-- PRD artifact (FEATURE level): the product slice one feature delivers. Deliberately contained
     — the spec's own prd.md already holds the full product definition, and repeating it here is
     how two documents start disagreeing. This one answers a narrower question: of everything the
     spec promised, which part does THIS feature deliver, to whom, and how will we know it
     landed. -->
<!-- The division of labour inside a feature: prd.md is the product slice (who, why, which of the
     spec's requirements), spec.md is the observable technical behaviour (interfaces, data, edge
     cases, failure modes). If you are writing an endpoint name or an error payload, you are in
     the wrong file. -->
<!-- Written by /rush-spec, in the same pass that writes spec.md, plan.md, tasks.md and
     done-contract.md. Location: specs/{{SPEC_ID}}/{{FEATURE_ID}}/prd.md -->

# Feature PRD: {{FEATURE_TITLE}}

**Feature**: `{{SPEC_ID}}/{{FEATURE_ID}}` · **Parent PRD**: `specs/{{SPEC_ID}}/prd.md`

## Overview

<!-- Two or three sentences: what this feature lets someone do that they cannot do today, and
     which of the spec's goals it serves. Written so a reader who has not read the parent PRD
     still understands what this slice is for. -->

{{WHAT_THIS_FEATURE_DELIVERS}}

**Serves**: {{PARENT_GOALS_OR_JOURNEYS}}

## Users

<!-- Which of the parent PRD's user types this feature actually touches, and what changes for
     them. Not a re-listing of every user in the product — only the ones this slice serves. -->

- **{{USER_TYPE}}** — {{WHAT_CHANGES_FOR_THEM}}

## Requirements

<!-- What this feature must do, numbered locally (`R1`, `R2`, …) and each one testable. These are
     the parent PRD's requirements narrowed to this feature's boundary — narrowed, not invented.
     A requirement here that traces to nothing upstream is either scope creep or a gap in the
     parent PRD; either way it is a finding to report, not something to quietly add. -->

- **R1.** {{REQUIREMENT_1}}
- **R2.** {{REQUIREMENT_2}}

## Traceability

<!-- The row that makes two PRD levels coherent instead of duplicated: every requirement above
     maps to at least one `FR-NNN` in the parent PRD. A blank right-hand cell is the finding —
     it means this feature is building something nobody asked for, or the parent PRD is missing
     a requirement it should have stated. -->

| This feature | Parent PRD |
|---|---|
| R1 | {{FR_IDS}} |
| R2 | {{FR_IDS}} |

**Parent requirements NOT covered here**: {{FR_IDS_LEFT_TO_OTHER_FEATURES_OR_NONE}}

<!-- Naming what this feature deliberately leaves to a sibling is what stops two features from
     each assuming the other one handled it. -->

## Out of Scope

<!-- What this feature specifically does not do, including the parts of the parent PRD that a
     reader might reasonably expect to find here. Name the sibling feature that owns it when
     there is one. -->

- {{EXCLUDED_1}} — {{OWNED_BY_WHICH_FEATURE_OR_NOT_AT_ALL}}

## Success Criteria

<!-- How anyone judges that this feature landed, in user-observable terms. These become the
     acceptance criteria in done-contract.md, so each one must be something a check or a named
     human gate can settle — write them as the question you would ask to decide. -->

- {{SUCCESS_CRITERION_1}}
- {{SUCCESS_CRITERION_2}}

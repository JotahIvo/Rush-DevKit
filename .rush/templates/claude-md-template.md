<!-- Budget: 60 lines, hard cap. Density over completeness. -->
<!-- HARNESS artifact: a pilot's checklist, not a style guide. Every rule below must trace to a
     real constraint or a past failure — if you can't name the failure it prevents, delete it.
     Everything else lives in .rush/ and is read on demand, never memorized upfront here. -->
<!-- Filled by /rush-init from detect-stack.sh output and the answers it gathers.
     Location: CLAUDE.md (project root) -->

# {{PROJECT_NAME}}

{{ONE_LINE_PROJECT_DESCRIPTION}}

## Before You Touch Code

- Read `.rush/config.json` first — settings there are a contract, not a suggestion.
- Current feature: `.rush/state.json`. Spec, plan, tasks: `specs/<feature-id>/`.
- Binding principles: `.rush/memory/constitution.md`. A `MUST` violation blocks the work.

## Rules

<!-- One bullet per rule, one-line reason attached inline. Delete every example that doesn't
     apply to this project, and never add a rule "just in case" — that is exactly how this file
     rots back into a style guide. -->
- {{RULE_1}} — because {{REASON_1}}
- {{RULE_2}} — because {{REASON_2}}
- {{RULE_3}} — because {{REASON_3}}

## Commands

<!-- Filled verbatim from `.rush/scripts/detect-stack.sh --json`; never hand-guessed. -->
- test: `{{TEST_COMMAND}}`
- lint: `{{LINT_COMMAND}}`
- build: `{{BUILD_COMMAND}}`

## Where Everything Else Lives

- Architecture decisions: `.rush/memory/architecture.md` + `specs/*/adr/`
- Cross-feature contracts: `specs/integration-map.md`, `specs/shared-contracts/`
- Open questions / known debt: `.rush/memory/questions.md`, `.rush/memory/debt.md`
- Scripts (never reimplement in prose what these already do): `.rush/scripts/`

<!-- Do not paste spec, plan or architecture content into this file. It is a pointer, not a
     mirror — a mirror goes stale the moment the thing it copied changes. -->

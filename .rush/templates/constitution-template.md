<!-- Budget: 200 lines. Density over completeness. -->
<!-- HARNESS artifact: binding project principles — how agents and humans must behave on this
     project. Never product decisions (pitch/PRD's job) and never a technology choice with no
     governance implication (architecture's job). -->
<!-- Filled by /rush-init, amended only through the process this file itself defines.
     Location: .rush/memory/constitution.md -->

<!--
Sync Impact Report (update on every amendment, keep as an HTML comment so it never counts
against the reader's budget)
- Version: {{OLD_VERSION}} -> {{NEW_VERSION}}
- Principles added: {{ADDED_PRINCIPLES}}
- Principles removed: {{REMOVED_PRINCIPLES}}
- Principles modified: {{MODIFIED_PRINCIPLES}}
- Templates/agents requiring review: {{DEPENDENT_ARTIFACTS}}
- Follow-up TODOs: {{FOLLOW_UPS}}
-->

# Constitution: {{PROJECT_NAME}}

**Version {{VERSION}} — ratified {{RATIFICATION_DATE}}, last amended {{DATE}}**

<!-- Start minimal. A constitution grows by ratchet: a principle is added only after a real
     failure it would have prevented, never speculatively "just in case". If you cannot name
     the incident or the concrete risk, the principle isn't ready to be written yet. -->

## Principles

<!-- One subsection per principle. State MUST or SHOULD explicitly — the word decides whether
     violating it blocks work (see Enforcement below). -->

### {{PRINCIPLE_ID}}. {{PRINCIPLE_TITLE}} ({{MUST_OR_SHOULD}})

<!-- The rule itself, then the rationale tied to a real failure or a concrete, named risk. A
     principle with no rationale is decoration, not governance. -->
{{PRINCIPLE_STATEMENT}}

**Why**: {{RATIONALE_TIED_TO_REAL_FAILURE_OR_RISK}}

## Governance

### Amendment Process

<!-- Who may propose a change, who approves it, and what evidence a proposal must carry
     (usually: the failure or friction that motivates it). -->
{{AMENDMENT_PROCESS}}

### Versioning

<!-- Semantic-ish versioning applied to this document itself. -->
- MAJOR: {{MAJOR_VERSION_RULE}} <!-- e.g. a principle removed or redefined incompatibly -->
- MINOR: {{MINOR_VERSION_RULE}} <!-- e.g. a principle added -->
- PATCH: {{PATCH_VERSION_RULE}} <!-- e.g. wording clarified with no semantic change -->

### Enforcement

<!-- Name exactly what a violation blocks — merge, done-check.sh, promotion to `done` — so
     "blocks" is a mechanism, not a mood. -->
A `MUST` principle violated by an artifact or by generated code **blocks {{WHAT_A_MUST_VIOLATION_BLOCKS}}**
until resolved or the constitution is amended through the process above.
A `SHOULD` violation is reported as a finding but does not block, unless the project's
`.rush/config.json` says otherwise.

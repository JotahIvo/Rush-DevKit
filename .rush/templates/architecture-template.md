<!-- Density over completeness: as long as the content honestly requires, never padded to look
     thorough, never truncated to hit a number. -->
<!-- ARCHITECTURE artifact: structural HOW and trade-offs for the COMPLETE system this spec is
     building — not one section per feature. Never a step-by-step implementation recipe (that's
     plan.md) and never a redefinition of behaviour (that's spec.md). -->
<!-- Filled by /rush-architect, once per spec. This is the full, authoritative version.
     Location: specs/{{SPEC_ID}}/architecture.md
     A condensed digest of this file (never a copy of its full text) is appended to
     .rush/memory/architecture.md from .rush/templates/architecture-summary-template.md — that
     shared file accumulates a summary per spec, not the full content of every one. -->

# Architecture: {{SPEC_TITLE}}

## Applicable Disciplines

<!-- Walk all 13, in order. For each, either state the decision in one line, or write "N/A
     because <reason>". An "N/A" with no reason hides a decision that was never actually made. -->
- **Data**: {{DATA_NOTE_OR_NA}}
- **API / Integration**: {{API_NOTE_OR_NA}}
- **Security**: {{SECURITY_NOTE_OR_NA}}
- **Scalability**: {{SCALABILITY_NOTE_OR_NA}}
- **Resilience**: {{RESILIENCE_NOTE_OR_NA}}
- **Performance**: {{PERFORMANCE_NOTE_OR_NA}}
- **Observability**: {{OBSERVABILITY_NOTE_OR_NA}}
- **Deployment / Infra**: {{DEPLOYMENT_NOTE_OR_NA}}
- **Concurrency / Consistency**: {{CONCURRENCY_NOTE_OR_NA}}
- **Compliance / Privacy**: {{COMPLIANCE_NOTE_OR_NA}}
- **Cost**: {{COST_NOTE_OR_NA}}
- **Accessibility**: {{ACCESSIBILITY_NOTE_OR_NA}}
- **Testability**: {{TESTABILITY_NOTE_OR_NA}}

## Candidate Approaches

<!-- 2-3 approaches that were genuinely viable, each with its trade-off. Never write a strawman
     just to justify the chosen one; if only one approach was ever real, say why the others
     were not. -->
1. **{{APPROACH_1_NAME}}** — {{APPROACH_1_TRADEOFF}}
2. **{{APPROACH_2_NAME}}** — {{APPROACH_2_TRADEOFF}}
3. **{{APPROACH_3_NAME}}** — {{APPROACH_3_TRADEOFF}}

## Decision

<!-- The chosen approach and the one-line reason it wins on the goals that matter here. Link an
     ADR if the decision was contested enough to warrant one. -->
{{CHOSEN_APPROACH}} — see {{ADR_LINK_OR_NONE}}

## Quality Attribute Impact

<!-- What gets better and what gets worse. A decision with no named cost is suspect. -->
- {{QUALITY_IMPACT_1}}
- {{QUALITY_IMPACT_2}}

## Security (STRIDE-lite)

<!-- One line per category that applies; "N/A because <reason>" otherwise. -->
- **Spoofing**: {{SPOOFING_NOTE_OR_NA}}
- **Tampering**: {{TAMPERING_NOTE_OR_NA}}
- **Repudiation**: {{REPUDIATION_NOTE_OR_NA}}
- **Information disclosure**: {{DISCLOSURE_NOTE_OR_NA}}
- **Denial of service**: {{DOS_NOTE_OR_NA}}
- **Elevation of privilege**: {{PRIVILEGE_NOTE_OR_NA}}

## Resilience & Failure Modes

<!-- What fails, how the system degrades, what the recovery path is. The failure behaviour the
     design commits to — not a test plan. -->
- {{FAILURE_MODE_1}} → {{DEGRADATION_OR_RECOVERY_1}}

## Performance Budgets

<!-- Numeric, measurable ceilings: latency, throughput, payload size, memory. -->
- {{METRIC_1}}: {{BUDGET_VALUE_1}}

## Observability

<!-- What must be logged/metriced/traced to know, in production, that this decision is
     holding. -->
- {{SIGNAL_1}}

## Fitness Functions

<!-- Every decision above must produce at least one executable check registered under
     .rush/memory/fitness/*.sh. List them here by name so drift is caught by `fitness.sh`, not
     just documented and forgotten. -->
- `{{FITNESS_FUNCTION_NAME}}` — {{WHAT_IT_CHECKS}} (`.rush/memory/fitness/{{SCRIPT_FILE}}`)

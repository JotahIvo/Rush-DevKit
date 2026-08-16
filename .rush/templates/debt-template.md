<!-- DEBT artifact: structured technical debt log, not a vague TODO list. Every entry names the
     shortcut and its cost so debt is a recorded decision, not an accident discovered later. -->
<!-- Appended to by any agent that knowingly takes a shortcut under time pressure.
     Location: .rush/memory/debt.md -->

# Technical Debt

<!-- STATUS is one of: open | accepted (won't repay, documented trade-off) | repaid -->

## {{DEBT_ID}} — {{STATUS}}

- **Date**: {{DATE}}
- **Shortcut taken**: {{SHORTCUT_DESCRIPTION}}
- **Why**: {{REASON_FOR_SHORTCUT}}
- **Estimated cost to repay**: {{REPAY_ESTIMATE}}
<!-- Effort/time, and what breaks or gets harder the longer this stays unpaid. -->
- **Originating feature/task**: {{FEATURE_OR_TASK_ID}}

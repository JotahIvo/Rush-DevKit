<!-- QUESTIONS artifact: async, non-blocking Q&A log. An agent that hits a non-blocking question
     appends an entry here with the assumption it adopted, and keeps working — it never stalls
     waiting for an answer to land in this file. -->
<!-- Appended to by any agent, resolved by a human or a later agent.
     Location: .rush/memory/questions.md -->

# Open Questions

<!-- One entry per question. Never delete an entry, even after it's answered — the assumption
     recorded may already have shipped in an artifact, and the history explains why. -->

## {{QUESTION_ID}} — {{STATUS}}
<!-- STATUS is one of: open | answered -->

- **Date**: {{DATE}}
- **Asked by**: {{ASKING_AGENT}}
- **Question**: {{QUESTION_TEXT}}
- **Assumption adopted meanwhile**: {{ASSUMPTION_TEXT}}
- **Answer**: {{ANSWER_TEXT}}
<!-- Leave the answer placeholder empty (or omit the line) while status is `open`. -->

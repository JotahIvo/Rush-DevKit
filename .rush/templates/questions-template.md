<!-- QUESTIONS artifact: async, non-blocking Q&A log for ONE spec (and every feature nested under
     it). An agent that hits a non-blocking question appends an entry here with the assumption it
     adopted, and keeps working — it never stalls waiting for an answer to land in this file. -->
<!-- Appended to by any agent, resolved by a human or a later agent. Lives inside the spec's own
     folder (not one shared file for the whole project) so questions stay next to the work they're
     about instead of piling up in a single, hard-to-scan global log. Created empty by
     new-spec.sh; every entry below is added later, by whichever agent first hits a question.
     Location: specs/{{FEATURE_ID}}/questions.md -->

# Open Questions: {{FEATURE_TITLE}}

<!-- One entry per question. Never delete an entry, even after it's answered — the assumption
     recorded may already have shipped in an artifact, and the history explains why. Append new
     entries in this exact shape (STATUS is one of: open | answered):

## <question-id> — <status>

- **Date**: <YYYY-MM-DD>
- **Asked by**: <agent that asked>
- **Question**: <question text>
- **Assumption adopted meanwhile**: <assumption text>
- **Answer**: <answer text — omit this line while status is `open`>
-->

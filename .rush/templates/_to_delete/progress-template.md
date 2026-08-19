<!-- PROGRESS artifact: session diary for one feature, append-only. Never rewrite a past entry —
     only add new ones. This is what lets a session with no memory of the last one pick up
     exactly where it left off. -->
<!-- Filled by every agent that works a session on this feature (last step before ending).
     Location: specs/{{FEATURE_ID}}/progress.md -->

# Progress: {{FEATURE_TITLE}}

<!-- Newest entry on top. Each entry is a few lines — this is a diary, not a changelog, and
     definitely not a copy of the diff. -->

## {{DATE}} — {{SESSION_SUMMARY_TITLE}}

**Changed**: {{WHAT_CHANGED}}

**Decisions**: {{DECISIONS_MADE_THIS_SESSION}}

**Next**: {{WHAT_IS_NEXT}}

**Resume at**: {{WHERE_TO_RESUME}}
<!-- A file, a task id, or a specific open question — concrete enough that a cold session
     doesn't have to re-derive it from the diff. -->

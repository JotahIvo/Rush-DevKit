<!-- TASKS artifact: HOW, as ordered independently-verifiable units of work, plus the session
     diary for this feature. Never redefines behaviour — that's spec.md's job. No budget declared
     in script-interfaces.md; keep every task small enough that its verify: command can be run in
     one sitting. -->
<!-- Filled by /rush-spec — all tasks start `pending`. Status changes only through
     .rush/scripts/task-status.sh, never by hand-editing this file's status markers. The Session
     Log at the bottom absorbs what used to be a separate progress.md: every agent that works a
     session on this feature appends one entry there (last step before ending) instead of writing
     to a second file.
     Location: specs/{{FEATURE_ID}}/tasks.md -->

# Tasks: {{FEATURE_TITLE}}

## Legend

| Status | Meaning |
|---|---|
| `pending` | Not started. |
| `in_progress` | An agent is actively working on it. |
| `blocked` | Cannot proceed; reason recorded under the task. |
| `done` | Verified complete. |

**Only `rush-verifier` may set a task to `done`**, via
`.rush/scripts/task-status.sh <feature-id> --set <task-id> done --by rush-verifier`. Any other
actor attempting to promote to `done` is rejected by the script with a non-zero exit — that is
by design, not a bug to route around. The `- [ ]`/`- [x]` checkbox on the status line is a visual
mirror of the status token (checked only when status is `done`) — it is written automatically by
`task-status.sh`, never hand-toggled independently of the status word.

## Tasks

<!-- Each task: a stable id (never renumber or reuse an id, even if the task is dropped — mark
     it blocked/superseded instead), a dense title, its current status, and a verify: command
     that proves completion without human judgement. A task with no verify: line is not ready
     to be worked; write the check before the code. -->

### {{TASK_ID}} — {{TASK_TITLE}}
- [ ] status: `pending`
- verify: `{{VERIFY_COMMAND}}`

### {{TASK_ID_2}} — {{TASK_TITLE_2}}
- [ ] status: `pending`
- verify: `{{VERIFY_COMMAND_2}}`

## Session Log

<!-- Newest entry on top. Each entry is a few lines — this is a diary, not a changelog, and
     definitely not a copy of the diff. Entries use "####" (not "###") on purpose: task headings
     are "###" and are parsed as tasks by every script that reads this file — a session-log entry
     must never be mistaken for one. -->

#### {{DATE}} — {{SESSION_SUMMARY_TITLE}}

**Changed**: {{WHAT_CHANGED}}

**Decisions**: {{DECISIONS_MADE_THIS_SESSION}}

**Next**: {{WHAT_IS_NEXT}}

**Resume at**: {{WHERE_TO_RESUME}}
<!-- A task id or a specific open question — concrete enough that a cold session doesn't have to
     re-derive it from the diff. -->

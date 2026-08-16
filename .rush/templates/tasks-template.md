<!-- TASKS artifact: HOW, as ordered independently-verifiable units of work. Never redefines
     behaviour — that's spec.md's job. No budget declared in script-interfaces.md; keep every
     task small enough that its verify: command can be run in one sitting. -->
<!-- Filled by /rush-spec — all tasks start `pending`. Status changes only through
     .rush/scripts/task-status.sh, never by hand-editing this file's status markers.
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
by design, not a bug to route around.

## Tasks

<!-- Each task: a stable id (never renumber or reuse an id, even if the task is dropped — mark
     it blocked/superseded instead), a dense title, its current status, and a verify: command
     that proves completion without human judgement. A task with no verify: line is not ready
     to be worked; write the check before the code. -->

### {{TASK_ID}} — {{TASK_TITLE}}
- status: `pending`
- verify: `{{VERIFY_COMMAND}}`

### {{TASK_ID_2}} — {{TASK_TITLE_2}}
- status: `pending`
- verify: `{{VERIFY_COMMAND_2}}`

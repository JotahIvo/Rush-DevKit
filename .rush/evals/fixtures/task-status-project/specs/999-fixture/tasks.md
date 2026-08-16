# Tasks: Fixture Feature

## Legend

| Status | Meaning |
|---|---|
| `pending` | Not started. |
| `in_progress` | An agent is actively working on it. |
| `blocked` | Cannot proceed; reason recorded under the task. |
| `done` | Verified complete. |

**Only `rush-verifier` may set a task to `done`**, via
`.rush/scripts/task-status.sh <feature-id> --set <task-id> done --by rush-verifier`.

## Tasks

### T1 — Fixture task
- status: `pending`
- verify: `true`

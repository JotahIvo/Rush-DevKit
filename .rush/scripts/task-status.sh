#!/usr/bin/env bash
# task-status.sh - read and change task status in specs/<feature-id>/tasks.md.
# Hard rule: promoting a task to `done` requires `--by rush-verifier`; any
# other actor is rejected. Only rush-verifier promotes work to done.
#
# Usage: task-status.sh <feature-id> [--list] [--set <task-id> <status>] [--by <actor>] [--json]
#
# Exit 0 ok, 1 domain-level failure (task not found, promotion rejected),
# 2 usage/internal error.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: task-status.sh <feature-id> [--list] [--set <task-id> <status>] [--by <actor>] [--json]

Reads or changes task status in specs/<feature-id>/tasks.md (the
"### <id> - <title>" / "- status: `...`" / "- verify: `...`" format
from .rush/templates/tasks-template.md). Status is one of: pending,
in_progress, blocked, done.

Hard rule: only `--by rush-verifier` may set a task to `done`. Any
other actor (or no --by at all) is rejected with a non-zero exit - this
is by design, not a bug to route around. Non-`done` transitions do not
require --by, though passing it is recommended for the audit trail.

  <feature-id>        Full id or numeric prefix (e.g. "007" resolves to
                       "007-checkout").
  --list               List all tasks. Default action when --set is not
                       given.
  --set <id> <status>  Set task <id>'s status.
  --by <actor>         Who is making this change (required, and must be
                       "rush-verifier", to set status to "done").
  --json               Print a single JSON object on stdout, nothing else.
  -h, --help           Show this help.

Exit codes: 0 ok, 1 task not found / promotion rejected, 2 usage/internal error.
EOF
}

json_mode="false"
feature_arg=""
do_list="false"
do_set="false"
set_id=""
set_status=""
by_actor=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true"; shift ;;
    --list) do_list="true"; shift ;;
    --set)
      [ "$#" -ge 3 ] || { echo "task-status.sh: --set requires <task-id> <status>" >&2; exit 2; }
      do_set="true"; set_id="$2"; set_status="$3"; shift 3 ;;
    --by)
      [ "$#" -ge 2 ] || { echo "task-status.sh: --by requires a value" >&2; exit 2; }
      by_actor="$2"; shift 2 ;;
    -*) echo "task-status.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [ -n "$feature_arg" ]; then
        echo "task-status.sh: unexpected extra argument: $1" >&2; exit 2
      fi
      feature_arg="$1"; shift ;;
  esac
done

if [ -z "$feature_arg" ]; then
  echo "task-status.sh: <feature-id> is required" >&2
  usage >&2
  exit 2
fi

if [ "$do_set" = "true" ]; then
  case "$set_status" in
    pending|in_progress|blocked|done) ;;
    *)
      echo "task-status.sh: invalid status '$set_status' (expected: pending, in_progress, blocked, done)" >&2
      exit 2
      ;;
  esac
fi

root="$(rush_root)" || exit 2
py="$(rush_python)" || exit 2
lib="${RUSH_LIB_DIR:-$root/.rush/scripts/lib}/rushlib.py"

# The hard rule: only rush-verifier may promote a task to done. Checked
# before anything touches the file.
if [ "$do_set" = "true" ] && [ "$set_status" = "done" ] && [ "$by_actor" != "rush-verifier" ]; then
  msg="task-status.sh: only rush-verifier may set a task to 'done' (got --by '${by_actor:-<none>}'). Every other actor must leave the task at its current status and let rush-verifier promote it after verifying the work."
  if [ "$json_mode" = "true" ]; then
    "$py" -c "
import json, sys
print(json.dumps({'ok': False, 'error': 'promotion_rejected', 'message': sys.argv[1]}))
" "$msg"
  else
    echo "$msg" >&2
  fi
  exit 1
fi

feature_dir="$(rush_feature_dir "$feature_arg")" || exit 2
tasks_file="$root/$feature_dir/tasks.md"

if [ ! -f "$tasks_file" ]; then
  echo "task-status.sh: no tasks.md at $feature_dir/tasks.md" >&2
  exit 2
fi

if [ "$do_set" = "true" ]; then
  result_file="$(mktemp)"
  trap 'rm -f "$result_file"' EXIT
  set +e
  "$py" "$lib" tasks-set "$tasks_file" "$set_id" "$set_status" > "$result_file" 2>"${result_file}.err"
  status=$?
  set -e
  if [ "$status" -eq 2 ]; then
    cat "${result_file}.err" >&2
    rm -f "${result_file}.err"
    exit 2
  fi
  if [ "$status" -eq 1 ]; then
    err_msg="$(cat "${result_file}.err")"
    rm -f "${result_file}.err"
    if [ "$json_mode" = "true" ]; then
      "$py" -c "
import json, sys
print(json.dumps({'ok': False, 'feature': sys.argv[1], 'error': 'task_not_found', 'message': sys.argv[2]}))
" "$feature_dir" "$err_msg"
    else
      echo "$err_msg" >&2
    fi
    exit 1
  fi
  rm -f "${result_file}.err"
  updated_task="$(cat "$result_file")"
  if [ "$json_mode" = "true" ]; then
    "$py" -c "
import json, sys
print(json.dumps({'ok': True, 'feature': sys.argv[1], 'task': json.loads(sys.argv[2])}))
" "$feature_dir" "$updated_task"
  else
    "$py" -c "
import json, sys
t = json.loads(sys.argv[1])
print('%s -> %s: %s' % (t['id'], t['status'], t['title']))
" "$updated_task"
    rush_ok "$feature_dir/tasks.md updated"
  fi
  exit 0
fi

# Default action: --list (explicit or implied when neither --list nor --set given).
result_file="$(mktemp)"
trap 'rm -f "$result_file"' EXIT
set +e
"$py" "$lib" tasks-list "$tasks_file" > "$result_file" 2>"${result_file}.err"
status=$?
set -e
if [ "$status" -ne 0 ]; then
  cat "${result_file}.err" >&2
  rm -f "${result_file}.err"
  exit 2
fi
rm -f "${result_file}.err"
tasks_json="$(cat "$result_file")"

if [ "$json_mode" = "true" ]; then
  "$py" -c "
import json, sys
print(json.dumps({'feature': sys.argv[1], 'tasks': json.loads(sys.argv[2])}, ensure_ascii=False))
" "$feature_dir" "$tasks_json"
else
  "$py" -c "
import json, sys
tasks = json.loads(sys.argv[1])
if not tasks:
    print('no tasks found')
else:
    for t in tasks:
        verify = t['verify'] or '(no verify command)'
        print('[%-11s] %-6s %s  (verify: %s)' % (t['status'], t['id'], t['title'], verify))
    counts = {}
    for t in tasks:
        counts[t['status']] = counts.get(t['status'], 0) + 1
    print('%d task(s): %s' % (len(tasks), ', '.join('%s=%d' % (k, v) for k, v in sorted(counts.items()))))
" "$tasks_json"
fi

exit 0

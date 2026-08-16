#!/usr/bin/env bash
# session-start.sh — SessionStart hook.
#
# Calls `.rush/scripts/session-start.sh --json` and prints a compact context
# block so the agent begins the session with the ritual state (current
# feature, task counts, unanswered questions, dirty tree, ...).
#
# Degrades SILENTLY (exit 0, no output) whenever the project has no
# .rush/state.json yet, the session-start script is missing, or anything else
# goes wrong. This hook must never fail the session start.
#
# Usage: session-start.sh   (reads the Claude Code hook JSON payload from stdin)

set -uo pipefail

usage() {
  cat <<'EOF'
session-start.sh - SessionStart hook that prints the /rush session ritual
context (current feature, task counts, open questions, dirty tree, ...).

Degrades silently (exit 0, no output) if the project has not been
initialised yet. Wired via .claude/settings.json.

Options:
  -h, --help   Show this help and exit.
EOF
}

for arg in "${@:-}"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
  esac
done

# Consume (and discard) the hook JSON on stdin so nothing is left dangling.
cat >/dev/null 2>&1 || true

if ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$ROOT" ] || [ ! -d "$ROOT/.rush" ]; then
  d="$PWD"
  ROOT=""
  while [ -n "$d" ]; do
    if [ -d "$d/.rush" ]; then ROOT="$d"; break; fi
    [ "$d" = "/" ] && break
    d="$(dirname "$d")"
  done
fi
if [ -z "$ROOT" ] || [ ! -d "$ROOT/.rush" ]; then
  exit 0
fi

# No state.json yet => project not initialised => degrade silently.
if [ ! -f "$ROOT/.rush/state.json" ]; then
  exit 0
fi

SCRIPT="$ROOT/.rush/scripts/session-start.sh"
if [ ! -f "$SCRIPT" ]; then
  exit 0
fi

RAW=""
if [ -x "$SCRIPT" ]; then
  RAW="$("$SCRIPT" --json 2>/dev/null)" || RAW=""
elif command -v bash >/dev/null 2>&1; then
  RAW="$(bash "$SCRIPT" --json 2>/dev/null)" || RAW=""
fi

if [ -z "$RAW" ]; then
  exit 0
fi

PYCODE=$(cat <<'PYEOF'
import json
import sys


def main():
    raw = sys.stdin.read()
    if not raw.strip():
        return
    try:
        data = json.loads(raw)
    except Exception:
        return
    if not isinstance(data, dict):
        return

    lines = ["## Rush session state"]

    feature = data.get("current_feature")
    if feature:
        lines.append("- Current feature: %s" % feature)

    tasks = data.get("tasks") or data.get("task_counts")
    if isinstance(tasks, dict) and tasks:
        parts = ", ".join("%s: %s" % (k, v) for k, v in tasks.items())
        lines.append("- Tasks by status: %s" % parts)

    questions = data.get("open_questions") or data.get("questions")
    if isinstance(questions, list) and questions:
        lines.append("- Unanswered questions: %d" % len(questions))
    elif isinstance(questions, int) and questions:
        lines.append("- Unanswered questions: %d" % questions)

    debt = data.get("open_debt") or data.get("debt")
    if isinstance(debt, list) and debt:
        lines.append("- Open debt items: %d" % len(debt))
    elif isinstance(debt, int) and debt:
        lines.append("- Open debt items: %d" % debt)

    dirty = data.get("dirty_tree") or data.get("working_tree_dirty")
    if dirty:
        lines.append("- Working tree: dirty (uncommitted changes present)")

    last_commits = data.get("last_commits")
    if isinstance(last_commits, list) and last_commits:
        lines.append("- Last commit: %s" % last_commits[0])

    last_progress = data.get("last_progress_entry") or data.get("last_progress")
    if last_progress:
        lines.append("- Last progress entry: %s" % last_progress)

    baseline_test = data.get("baseline_test_command") or data.get("test_command")
    if baseline_test:
        lines.append("- Suggested baseline test: %s" % baseline_test)

    if len(lines) == 1:
        # Nothing meaningful to show.
        return

    context = "\n".join(lines)
    out = {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": context,
        }
    }
    sys.stdout.write(json.dumps(out) + "\n")


try:
    main()
except Exception:
    pass
PYEOF
)

printf '%s' "$RAW" | python3 -c "$PYCODE" 2>/dev/null
exit 0

#!/usr/bin/env bash
# session-start.sh - the session ritual: current feature, task counts,
# unanswered questions, open debt, working tree cleanliness, recent
# commits, the last progress entry, and a suggested baseline test
# command. Read-only: never writes anything.
#
# Usage: session-start.sh [--json]
#
# Exit 0 always on a successful run, 2 on usage or internal error.
#
# JSON field names are load-bearing: .rush/hooks/session-start.sh (the
# Claude Code SessionStart hook) reads current_feature, tasks,
# open_questions, open_debt, dirty_tree, last_commits,
# last_progress_entry and baseline_test_command from this script's
# --json output verbatim.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: session-start.sh [--json]

Prints the session-start ritual: current feature, task counts by
status, unanswered questions (.rush/memory/questions.md), open debt
(.rush/memory/debt.md), whether the working tree is dirty, the last 5
commits, the newest progress.md entry, and a suggested baseline test
command (from detect-stack.sh). Read-only.

  --json       Print a single JSON object on stdout, nothing else.
  -h, --help   Show this help.

Exit codes: 0 ok, 2 usage/internal error.
EOF
}

json_mode="false"
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true" ;;
    *) echo "session-start.sh: unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

root="$(rush_root)" || exit 2
py="$(rush_python)" || exit 2

current_feature="$(rush_current_feature)" || exit 2

feature_dir=""
if [ -n "$current_feature" ]; then
  feature_dir="$(rush_feature_dir "$current_feature" 2>/dev/null || true)"
fi

dirty="false"
last_commits_raw=""
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ -n "$(git -C "$root" status --porcelain 2>/dev/null || true)" ]; then
    dirty="true"
  fi
  last_commits_raw="$(git -C "$root" log -n 5 --pretty=format:'%h %s' 2>/dev/null || true)"
fi

# Best-effort: a project with no detect-stack.sh yet (or one that fails)
# just means no baseline test suggestion, not a hard failure here.
detect_json=""
if [ -x "$root/.rush/scripts/detect-stack.sh" ]; then
  detect_json="$("$root/.rush/scripts/detect-stack.sh" --json 2>/dev/null || true)"
fi

result_file="$(mktemp)"
trap 'rm -f "$result_file"' EXIT

set +e
"$py" - "$root" "$current_feature" "$feature_dir" "$dirty" "$last_commits_raw" "$detect_json" \
  > "$result_file" <<'PYEOF'
import json, os, re, sys

root, current_feature, feature_dir, dirty, last_commits_raw, detect_json = sys.argv[1:7]

sys.path.insert(0, os.environ.get("RUSH_LIB_DIR") or os.path.join(root, ".rush", "scripts", "lib"))
import rushlib  # noqa: E402


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


# --- task counts by status ---------------------------------------------
task_counts = {s: 0 for s in rushlib.STATUS_CHOICES}
if feature_dir:
    tasks_text = read(os.path.join(root, feature_dir, "tasks.md"))
    if tasks_text is not None:
        for t in rushlib.parse_tasks(tasks_text):
            task_counts[t["status"]] = task_counts.get(t["status"], 0) + 1

# --- open questions / open debt: "## <ID> - <STATUS>" headings ---------
_ID_STATUS_RE = re.compile(r"^(\S+)\s*[—–-]\s*(\S+)\s*$")
_FIELD_RE_TEMPLATE = r"\*\*%s\*\*:\s*(.+)"


def open_entries(path, status_field_name, open_statuses):
    text = read(path)
    if text is None:
        return []
    out = []
    field_re = re.compile(_FIELD_RE_TEMPLATE % re.escape(status_field_name))
    for h in rushlib.parse_headings(text):
        if h["level"] != 2:
            continue
        m = _ID_STATUS_RE.match(h["title"])
        if not m:
            continue
        entry_id, status = m.group(1), m.group(2).lower()
        if status not in open_statuses:
            continue
        fm = field_re.search(h["content"])
        text_val = fm.group(1).strip() if fm else ""
        out.append({"id": entry_id, "text": text_val})
    return out


open_questions = open_entries(os.path.join(root, ".rush", "memory", "questions.md"), "Question", {"open"})
open_debt = open_entries(os.path.join(root, ".rush", "memory", "debt.md"), "Shortcut taken", {"open"})

# --- last progress entry: newest entry is topmost -----------------------
last_progress_entry = None
if feature_dir:
    progress_text = read(os.path.join(root, feature_dir, "progress.md"))
    if progress_text is not None:
        for h in rushlib.parse_headings(progress_text):
            if h["level"] == 2:
                last_progress_entry = h["title"]
                break

# --- baseline test command ------------------------------------------------
baseline_test_command = None
if detect_json.strip():
    try:
        detected = json.loads(detect_json)
        baseline_test_command = ((detected.get("commands") or {}).get("test"))
    except json.JSONDecodeError:
        pass

last_commits = [line for line in last_commits_raw.split("\n") if line.strip() != ""]

out = {
    "current_feature": current_feature or None,
    "feature_dir": feature_dir or None,
    "tasks": task_counts,
    "open_questions": open_questions,
    "open_debt": open_debt,
    "dirty_tree": dirty == "true",
    "last_commits": last_commits,
    "last_progress_entry": last_progress_entry,
    "baseline_test_command": baseline_test_command,
}
print(json.dumps(out, ensure_ascii=False))
PYEOF
status=$?
set -e

if [ "$status" -ne 0 ]; then
  cat "$result_file" >&2 2>/dev/null || true
  exit 2
fi

payload="$(cat "$result_file")"

if [ "$json_mode" = "true" ]; then
  printf '%s\n' "$payload"
else
  "$py" - "$payload" <<'PYEOF'
import json, sys

data = json.loads(sys.argv[1])


def show(v):
    return "(none)" if v in (None, "") else v


print("current feature: %s" % show(data["current_feature"]))
t = data["tasks"]
print("tasks: pending=%d in_progress=%d blocked=%d done=%d" % (
    t.get("pending", 0), t.get("in_progress", 0), t.get("blocked", 0), t.get("done", 0)))
print("open questions: %d" % len(data["open_questions"]))
for q in data["open_questions"]:
    print("  - %s: %s" % (q["id"], q["text"] or "(no text)"))
print("open debt: %d" % len(data["open_debt"]))
for d in data["open_debt"]:
    print("  - %s: %s" % (d["id"], d["text"] or "(no text)"))
print("working tree: %s" % ("dirty" if data["dirty_tree"] else "clean"))
print("last commits:")
if data["last_commits"]:
    for c in data["last_commits"]:
        print("  %s" % c)
else:
    print("  (none)")
print("last progress entry: %s" % show(data["last_progress_entry"]))
print("baseline test command: %s" % show(data["baseline_test_command"]))
PYEOF
fi

exit 0

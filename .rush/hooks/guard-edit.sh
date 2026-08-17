#!/usr/bin/env bash
# guard-edit.sh — PreToolUse hook for Edit|Write|NotebookEdit.
#
# Reads the hook JSON payload (tool_input.file_path, agent_type, ...) on stdin
# and enforces:
#   1. specs/*/tasks.md: promoting a task to status "done" is denied unless
#      agent_type == "rush-verifier" (only the verifier promotes tasks).
#   2. .rush/config.json and .rush/memory/constitution.md: any edit is denied;
#      these require explicit human approval.
#   3. security.sensitive_paths: allowed, but surfaced via systemMessage.
#   4. test files: denied when autonomy.edit_tests is "ask" or "deny" — never
#      loosen the test to make it pass.
#
# Contract: exit 2 + stderr + PreToolUse "deny" JSON on stdout to BLOCK.
# Exit 0 to allow (optionally with a "systemMessage" JSON for warnings).
# ANY unexpected internal failure must fail OPEN (exit 0, silent).
#
# Usage: guard-edit.sh   (reads the Claude Code hook JSON payload from stdin)

set -uo pipefail

usage() {
  cat <<'EOF'
guard-edit.sh - PreToolUse hook that protects tasks.md, config, constitution
and test files from unwanted edits.

Reads the Claude Code hook JSON payload from stdin (fields: tool_name,
tool_input, agent_type, ...). Not meant to be run interactively; wired via
.claude/settings.json.

Options:
  -h, --help   Show this help and exit.
EOF
}

for arg in "${@:-}"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
  esac
done

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

# Python source goes to a temp file, never through $(cat <<HEREDOC).
# Reason (real bug, macOS bash 3.2): the command-substitution parser scans the
# heredoc body and chokes on a literal backtick with "unexpected EOF while
# looking for matching backtick-quote. That bricked this hook, and a broken PreToolUse
# hook blocks every write in the project — including its own fix.
# Keeping stdin free also lets Python read the hook payload without argv limits.
PYFILE="$(mktemp "${TMPDIR:-/tmp}/rush-hook.XXXXXX")" || exit 0
trap 'rm -f "$PYFILE"' EXIT
cat > "$PYFILE" <<'PYEOF'
import fnmatch
import json
import os
import re
import sys


def cfg_get(cfg, dotted, default=None):
    cur = cfg
    for part in dotted.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return default
    return cur


def deny(reason):
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }
    sys.stdout.write(json.dumps(out) + "\n")
    sys.stderr.write(reason + "\n")
    sys.exit(2)


def allow(system_message=None):
    if system_message:
        sys.stdout.write(json.dumps({"systemMessage": system_message}) + "\n")
    sys.exit(0)


TASK_ID_RE = re.compile(r"\b(T-?\d+|TASK-\d+)\b")
# The shipped template writes the status as markdown code: "- status: <bt>done<bt>"
# (<bt> = backtick). Allow the usual decorations around the word. The backtick is
# written as \x60 on purpose: a literal one here has already broken this file once
# under macOS bash 3.2, and nothing warns you until every write is blocked.
DONE_STATUS_RE = re.compile(
    "\\bstatus\\b\\s*[:=]\\s*[\\x60'\"*\\[\\s]*done\\b", re.IGNORECASE
)
DONE_CHECKBOX_RE = re.compile(r"-\s*\[[xX]\]")


def task_done_map(content):
    """Best-effort map of {task_id: is_done}, stateful across lines.

    The shipped tasks-template.md puts the id on a heading ('### T1 - Title')
    and the status on a following bullet ('- status: done', usually in backticks),
    so a same-line
    heuristic would miss every real promotion. We therefore track the current
    task: a heading (or any line carrying a task id) opens a task scope, and a
    later 'status: done' inside that scope marks it done. Same-line and
    checkbox forms keep working, so custom task formats degrade gracefully.
    """
    result = {}
    current = None
    for line in content.splitlines():
        m = TASK_ID_RE.search(line)
        if m:
            current = m.group(1)
            result.setdefault(current, False)
            # Same-line form: '### T1 - title  status: done' or '- [x] T1 ...'
            if DONE_STATUS_RE.search(line) or DONE_CHECKBOX_RE.search(line):
                result[current] = True
            continue
        if current is None:
            continue
        # A new top-level heading without a task id closes the current scope.
        if line.startswith("#"):
            current = None
            continue
        if DONE_STATUS_RE.search(line) or DONE_CHECKBOX_RE.search(line):
            result[current] = True
    return result


def is_tasks_md(rel_path):
    return re.search(r"(^|/)specs/[^/]+/tasks\.md$", rel_path) is not None


def relpath(root, file_path):
    if not file_path:
        return ""
    try:
        ap = file_path if os.path.isabs(file_path) else os.path.join(root, file_path)
        ap = os.path.normpath(ap)
        rp = os.path.relpath(ap, root)
        return rp.replace(os.sep, "/")
    except Exception:
        return file_path


TEST_FILE_RE = re.compile(
    r"(^|/)(tests?|__tests__|spec)(/|$)"
    r"|[._-](test|spec)\.[A-Za-z0-9]+$"
    r"|(^|/)test_[^/]+\.py$"
    r"|_test\.[A-Za-z0-9]+$"
)


def is_test_file(rel_path):
    return bool(TEST_FILE_RE.search(rel_path))


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        allow()
        return

    tool_name = payload.get("tool_name")
    if tool_name not in ("Edit", "Write", "NotebookEdit"):
        allow()
        return

    tool_input = payload.get("tool_input") or {}
    file_path = tool_input.get("file_path") or tool_input.get("notebook_path")
    if not file_path:
        allow()
        return

    root = sys.argv[1]
    agent_type = payload.get("agent_type") or ""
    rel_path = relpath(root, file_path)

    cfg_path = os.path.join(root, ".rush", "config.json")
    cfg = {}
    if os.path.isfile(cfg_path):
        try:
            with open(cfg_path, "r") as f:
                cfg = json.load(f)
        except Exception:
            cfg = {}

    # 2. Protected harness files: config.json and constitution.md.
    protected_suffixes = (".rush/config.json", ".rush/memory/constitution.md")
    if rel_path in protected_suffixes or any(
        rel_path.endswith("/" + p) for p in protected_suffixes
    ):
        # Creating these is how /rush-init and /rush-new bootstrap a project, so a
        # blanket deny made the harness unable to install itself. What must stay
        # protected is *changing* an existing one behind the human's back: config
        # and constitution are the two files every other rule is derived from.
        if not os.path.isfile(os.path.join(root, rel_path)):
            allow(
                "Creating %s. This file is human-owned from now on: later edits "
                "are blocked and must be made by you or by re-running /rush-init "
                "after you remove it." % rel_path
            )
        deny(
            "%s already exists and requires explicit human approval to change — "
            "an agent may not edit it. Edit it yourself, or delete it and re-run "
            "/rush-init to regenerate it from scratch." % rel_path
        )

    # 1. tasks.md: only rush-verifier may set a task to 'done'.
    if is_tasks_md(rel_path):
        old_content = ""
        abs_path = os.path.join(root, rel_path)
        if os.path.isfile(abs_path):
            try:
                with open(abs_path, "r", errors="replace") as f:
                    old_content = f.read()
            except Exception:
                old_content = ""

        if tool_name == "Write":
            new_content = tool_input.get("content", "")
        elif tool_name == "Edit":
            old_string = tool_input.get("old_string", "")
            new_string = tool_input.get("new_string", "")
            if old_string and old_string in old_content:
                new_content = old_content.replace(old_string, new_string, 1)
            else:
                new_content = old_content + "\n" + new_string
        else:
            new_content = tool_input.get("new_source", "")

        old_map = task_done_map(old_content)
        new_map = task_done_map(new_content)
        newly_done = sorted(
            tid for tid, done in new_map.items()
            if done and not old_map.get(tid, False)
        )
        if newly_done and agent_type != "rush-verifier":
            deny(
                "Only rush-verifier may promote a task to 'done' in %s "
                "(attempted by agent_type=%r for task(s): %s). Run the "
                "verification and let rush-verifier update the status "
                "instead of editing it directly." % (
                    rel_path, agent_type or "<main>", ", ".join(newly_done),
                )
            )

    # 4. Test files: never loosen the test to make it pass.
    # Default mirrors .rush/config.schema.json's own default for
    # autonomy.edit_tests ("ask"), so a missing/incomplete config.json is
    # still safe-by-default.
    edit_tests = cfg_get(cfg, "autonomy.edit_tests", "ask")
    if is_test_file(rel_path) and edit_tests in ("ask", "deny"):
        deny(
            "Editing test file %s is blocked by autonomy.edit_tests=%r in "
            ".rush/config.json: never loosen the test to make it pass. If "
            "the test itself is wrong, a human must review and approve the "
            "change (edit the file directly, or set "
            "autonomy.edit_tests=\"allow\" after reviewing)." % (
                rel_path, edit_tests,
            )
        )

    # 3. Sensitive paths: allow, but warn.
    sensitive = cfg_get(cfg, "security.sensitive_paths", []) or []
    if isinstance(sensitive, list):
        for pattern in sensitive:
            if not isinstance(pattern, str) or not pattern:
                continue
            if fnmatch.fnmatch(rel_path, pattern) or fnmatch.fnmatch(
                "/" + rel_path, pattern
            ):
                allow(
                    "Editing %s, which matches security.sensitive_paths "
                    "(%r). Review this change carefully." % (rel_path, pattern)
                )
                return

    allow()


try:
    main()
except SystemExit:
    raise
except Exception:
    sys.exit(0)
PYEOF

python3 "$PYFILE" "$ROOT"
rc=$?
exit "$rc"

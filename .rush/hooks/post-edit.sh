#!/usr/bin/env bash
# post-edit.sh — PostToolUse hook for Edit|Write.
#
# Runs the project's formatter (.rush/config.json -> commands.format) after an
# edit, when enabled. This hook NEVER fails the tool call: whatever happens,
# it exits 0. Problems are reported only via the "systemMessage" field of the
# PostToolUse JSON on stdout, never via a non-zero exit code.
#
# Usage: post-edit.sh   (reads the Claude Code hook JSON payload from stdin)

set -uo pipefail

usage() {
  cat <<'EOF'
post-edit.sh - PostToolUse hook that runs the configured formatter after an
edit. Always exits 0; problems are surfaced as a systemMessage, never as a
tool failure.

Reads the Claude Code hook JSON payload from stdin. Not meant to be run
interactively; wired via .claude/settings.json.

Options:
  -h, --help   Show this help and exit.
EOF
}

for arg in "${@:-}"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
  esac
done

# This hook must NEVER fail the tool call, no matter what. Every exit path
# below is 0.
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

PYCODE=$(cat <<'PYEOF'
import json
import os
import subprocess
import sys


def cfg_get(cfg, dotted, default=None):
    cur = cfg
    for part in dotted.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return default
    return cur


def note(message):
    sys.stdout.write(json.dumps({"systemMessage": message}) + "\n")


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return

    if payload.get("tool_name") not in ("Edit", "Write"):
        return

    tool_input = payload.get("tool_input") or {}
    file_path = tool_input.get("file_path")
    if not file_path:
        return

    root = sys.argv[1]
    cfg_path = os.path.join(root, ".rush", "config.json")
    cfg = {}
    if os.path.isfile(cfg_path):
        try:
            with open(cfg_path, "r") as f:
                cfg = json.load(f)
        except Exception:
            cfg = {}

    # .rush/config.schema.json has no separate on/off switch for formatting:
    # commands.format is null unless rush-init/doctor actually detected (or a
    # human configured) a formatter, so "configured" IS "enabled" here.
    fmt_cmd = cfg_get(cfg, "commands.format", None)
    if not fmt_cmd or not isinstance(fmt_cmd, str) or not fmt_cmd.strip():
        return

    abs_path = file_path if os.path.isabs(file_path) else os.path.join(root, file_path)
    if not os.path.isfile(abs_path):
        return

    rel_path = os.path.relpath(abs_path, root).replace(os.sep, "/")
    cmd = fmt_cmd.replace("{file}", rel_path) if "{file}" in fmt_cmd else fmt_cmd

    try:
        proc = subprocess.run(
            cmd, shell=True, cwd=root, capture_output=True, text=True, timeout=30
        )
    except Exception as exc:
        note("post-edit formatter could not run (%s): %s" % (fmt_cmd, exc))
        return

    if proc.returncode != 0:
        tail = (proc.stderr or proc.stdout or "").strip().splitlines()[-10:]
        note(
            "commands.format ('%s') exited %d after editing %s. Output:\n%s"
            % (fmt_cmd, proc.returncode, rel_path, "\n".join(tail))
        )


try:
    main()
except Exception:
    pass
sys.exit(0)
PYEOF
)

python3 -c "$PYCODE" "$ROOT" 2>/dev/null
exit 0

#!/usr/bin/env bash
# guard-bash.sh — PreToolUse hook for the Bash tool.
#
# Reads the hook JSON payload (tool_input.command) on stdin and enforces, from
# .rush/config.json:
#   - security.blocked_commands   -> always deny a match
#   - git.allow_commit == false   -> deny `git commit`
#   - git.allow_push   == false   -> deny `git push`
#   - security.secret_scan_before_commit -> run .rush/scripts/secret-scan.sh --staged
#     before a `git commit` and deny if it finds a secret (exit 1)
#   - git.commit_convention       -> deny a `git commit -m` whose message does not
#     match the configured convention
#
# Contract: exit 2 + stderr message + PreToolUse "deny" JSON on stdout to BLOCK.
# Exit 0 (with no output, or with an "allow" systemMessage) to let the tool call
# proceed. ANY unexpected internal failure must fail OPEN (exit 0, silent) — a
# broken hook must never brick the user's session. Only a deliberate policy
# violation is allowed to exit 2.
#
# Usage: guard-bash.sh   (reads the Claude Code hook JSON payload from stdin)

set -uo pipefail

usage() {
  cat <<'EOF'
guard-bash.sh - PreToolUse hook that enforces git/security policy on Bash calls.

Reads the Claude Code hook JSON payload from stdin (fields: tool_name, tool_input,
agent_type, ...). Not meant to be run interactively; wired via .claude/settings.json.

Options:
  -h, --help   Show this help and exit.
EOF
}

for arg in "${@:-}"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
  esac
done

# python3 is required for everything below; if it is missing we cannot enforce
# policy, so fail open rather than break every Bash call.
if ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi

# Resolve the project root: prefer CLAUDE_PROJECT_DIR, fall back to walking up
# from the current directory. If we cannot find a .rush project, there is
# nothing to enforce yet (e.g. before /rush-init) -> fail open.
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
# looking for matching `'". That bricked this hook, and a broken PreToolUse
# hook blocks every write in the project — including its own fix.
# Keeping stdin free also lets Python read the hook payload without argv limits.
PYFILE="$(mktemp "${TMPDIR:-/tmp}/rush-hook.XXXXXX")" || exit 0
trap 'rm -f "$PYFILE"' EXIT
cat > "$PYFILE" <<'PYEOF'
import json
import os
import re
import shlex
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


def split_segments(command):
    # Best-effort split on shell control operators so we can inspect each
    # individual command in a compound line (a && b ; c | d).
    return re.split(r"&&|\|\||;|\|", command)


def segment_tokens(segment):
    try:
        return shlex.split(segment, comments=False, posix=True)
    except ValueError:
        return segment.split()


def git_subcommand(tokens):
    if not tokens or tokens[0] != "git":
        return None, tokens
    for i, tok in enumerate(tokens[1:], start=1):
        if not tok.startswith("-"):
            return tok, tokens[i + 1:]
    return None, []


def extract_message(rest_tokens):
    for i, tok in enumerate(rest_tokens):
        if tok in ("-m", "--message"):
            if i + 1 < len(rest_tokens):
                return rest_tokens[i + 1]
        if tok.startswith("--message="):
            return tok[len("--message="):]
    return None


CONVENTIONAL_RE = re.compile(
    r"^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)"
    r"(\([^)]+\))?(!)?: .+"
)
# Gitmoji: message starts with an emoji (or a ':shortcode:' alias) then a space.
GITMOJI_RE = re.compile(
    r"^(:[a-z0-9_+\-]+:|[\U0001F300-\U0001FAFF☀-➿])\s+\S"
)


def check_commit_convention(message, convention):
    """Return (ok, description) for git.commit_convention (schema enum:
    'conventional' | 'gitmoji' | 'none' | 'custom')."""
    if not convention or convention == "none":
        return True, None
    header = message.splitlines()[0] if message else ""
    if convention == "conventional":
        return bool(CONVENTIONAL_RE.match(header)), (
            "conventional commits: '<type>(<scope>)?: <subject>' where type is one "
            "of feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert "
            "(e.g. 'fix(auth): handle expired token')"
        )
    if convention == "gitmoji":
        return bool(GITMOJI_RE.match(header)), (
            "gitmoji: message must start with an emoji or ':shortcode:' "
            "followed by a space (e.g. ':bug: fix expired token handling')"
        )
    # 'custom' (or any unrecognised value): the convention is documented in
    # .rush/memory/constitution.md / CLAUDE.md, not something this hook can
    # statically validate — do not guess a rule, do not block on it.
    return True, None


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        allow()
        return

    if payload.get("tool_name") != "Bash":
        allow()
        return

    command = (payload.get("tool_input") or {}).get("command")
    if not command or not isinstance(command, str):
        allow()
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

    # 1. security.blocked_commands — always deny on match.
    blocked = cfg_get(cfg, "security.blocked_commands", []) or []
    if isinstance(blocked, list):
        for pattern in blocked:
            if not isinstance(pattern, str) or not pattern:
                continue
            try:
                matched = re.search(pattern, command) is not None
            except re.error:
                matched = pattern in command
            if matched:
                deny(
                    "Blocked by security.blocked_commands (pattern: %r) in "
                    ".rush/config.json. This command is not permitted in this "
                    "project. If it should be, a human must edit "
                    "security.blocked_commands in .rush/config.json." % pattern
                )

    segments = split_segments(command)
    parsed = [git_subcommand(segment_tokens(s)) for s in segments if s.strip()]

    allow_commit = cfg_get(cfg, "git.allow_commit", True)
    # Defaults mirror .rush/config.schema.json's own declared defaults, so a
    # config.json that omits a field (or is entirely missing) behaves exactly
    # as if that field were set to the schema's safe default.
    allow_push = cfg_get(cfg, "git.allow_push", False)
    secret_scan_before_commit = cfg_get(cfg, "security.secret_scan_before_commit", True)
    commit_convention = cfg_get(cfg, "git.commit_convention", "conventional")

    commit_rest = None
    push_seen = False
    for subcmd, rest in parsed:
        if subcmd == "commit":
            commit_rest = rest
        elif subcmd == "push":
            push_seen = True

    # 2. git.allow_commit
    if commit_rest is not None and allow_commit is False:
        deny(
            "Blocked by git.allow_commit=false in .rush/config.json. This "
            "project does not allow agents to run 'git commit'. A human must "
            "either commit manually or set git.allow_commit=true."
        )

    # 3. git.allow_push
    if push_seen and allow_push is False:
        deny(
            "Blocked by git.allow_push=false in .rush/config.json. This "
            "project does not allow agents to run 'git push'. A human must "
            "either push manually or set git.allow_push=true."
        )

    # 4. security.secret_scan_before_commit
    if commit_rest is not None and secret_scan_before_commit:
        scan_path = os.path.join(root, ".rush", "scripts", "secret-scan.sh")
        if os.path.isfile(scan_path):
            try:
                cmd = [scan_path, "--staged"]
                if not os.access(scan_path, os.X_OK):
                    cmd = ["bash", scan_path, "--staged"]
                proc = subprocess.run(
                    cmd, cwd=root, capture_output=True, text=True, timeout=60
                )
                if proc.returncode == 1:
                    deny(
                        "Blocked by security.secret_scan_before_commit=true in "
                        ".rush/config.json: .rush/scripts/secret-scan.sh --staged "
                        "found a likely secret in the staged changes. Remove the "
                        "secret (or add an allow pattern to "
                        ".rush/secret-scan-allow if it is a false positive) and "
                        "retry the commit."
                    )
                elif proc.returncode not in (0, 1):
                    # Internal failure of the scanner itself: fail open, but
                    # surface it so the human notices the scan did not run.
                    allow(
                        "secret-scan.sh exited %d (internal error) — secret scan "
                        "was NOT performed for this commit." % proc.returncode
                    )
                    return
            except Exception:
                allow(
                    "secret-scan.sh could not be run — secret scan was NOT "
                    "performed for this commit."
                )
                return

    # 5. git.commit_convention
    if commit_rest is not None and commit_convention:
        message = extract_message(commit_rest)
        if message is not None:
            ok, desc = check_commit_convention(message, commit_convention)
            if not ok:
                deny(
                    "Blocked by git.commit_convention in .rush/config.json: "
                    "commit message %r does not match the expected format "
                    "(%s). Rewrite the message to match, or a human can "
                    "change git.commit_convention in .rush/config.json." % (
                        message, desc,
                    )
                )

    allow()


try:
    main()
except SystemExit:
    raise
except Exception:
    # Any unexpected internal failure must fail OPEN.
    sys.exit(0)
PYEOF

python3 "$PYFILE" "$ROOT"
rc=$?
exit "$rc"

#!/usr/bin/env bash
# lint-shell-portability.sh - static check for shell constructs that break on
# the oldest bash the kit supports (macOS ships bash 3.2 and always will,
# because bash 4+ is GPLv3).
#
# This exists because of a real incident, not as a style preference: a literal
# backtick inside `PYCODE=$(cat <<'PYEOF' ... PYEOF)` makes bash 3.2 fail to
# parse the file at all ("unexpected EOF while looking for matching backtick").
# The file was a PreToolUse hook, so the parse error blocked every write in the
# project - including the edit that would have fixed it. bash 5 parses it fine,
# so CI on Linux and every test in a Linux container stay green while macOS
# users are hard-blocked.
#
# Usage: lint-shell-portability.sh [--json] [<path> ...]
#
# Exit 0 clean, 1 violations found, 2 usage/internal error.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: lint-shell-portability.sh [--json] [<path> ...]

Scans shell scripts for constructs that fail on macOS bash 3.2:

  heredoc_in_command_substitution
      $(cat <<'EOF' ... EOF) - bash 3.2 mis-parses the heredoc body. Write the
      body to a temp file instead; it also keeps stdin free for real input.
  backtick_in_heredoc
      A literal backtick inside any heredoc body. Harmless on its own, fatal
      once that heredoc ends up inside a command substitution. Use \x60.
  bash4_builtin
      mapfile / readarray / declare -A / ${var,,} / ${var^^}
  gnu_only_flag
      grep -P, sed -i without a backup suffix, date -d, readlink -f,
      the timeout binary (absent on stock macOS)

With no <path>, scans .rush/**/*.sh and install.sh from the project root.

  --json       Print a single JSON object on stdout, nothing else.
  -h, --help   Show this help.

Exit codes: 0 clean, 1 violations found, 2 usage/internal error.
EOF
}

json_mode="false"
paths=""
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true" ;;
    -*) echo "lint-shell-portability.sh: unknown option: $arg" >&2; usage >&2; exit 2 ;;
    *) paths="$paths $arg" ;;
  esac
done

script_dir="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$script_dir/lib/common.sh" ]; then
  # shellcheck disable=SC1091
  . "$script_dir/lib/common.sh"
  root="$(rush_root)" || exit 2
  py="$(rush_python)" || exit 2
else
  root="$PWD"
  py="python3"
fi

# shellcheck disable=SC2086
"$py" "$script_dir/lib/lint_portability.py" "$json_mode" "$root" $paths

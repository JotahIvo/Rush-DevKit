#!/usr/bin/env bash
# set-current.sh — move .rush/state.json's cursor to the spec/feature being worked on right now.
#
# The cursor exists so session-start.sh, /rush-brief and every skill that takes no argument know
# what "the current work" is. Nothing used to move it after creation, which produced a specific,
# repeatable wrong answer: create a spec's features in one batch, and current_feature is left on
# whichever one happened to be created last; implement 001 through 00N and the cursor stays on
# 00N the whole way, only agreeing with reality on the final feature.
#
# So creation no longer claims the cursor for a batch (new-feature.sh --no-activate), and the
# skills that actually start working on one feature call this on entry. Setting the cursor is a
# statement about attention, not about what was created most recently.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: set-current.sh [--spec <spec-id>] [--feature <feature-id>] [--clear-feature] [--json]

Points .rush/state.json at the work in progress.

  --spec <id>       Make this spec current. Id or unambiguous numeric prefix.
  --feature <id>    Make this feature current. Id or unambiguous prefix; resolved inside
                    --spec when given, otherwise across every spec. Setting a feature also
                    sets its spec — the two can never disagree.
  --clear-feature   Set current_feature to "" (the spec is active, no single feature is).
  --json            Print a single JSON object on stdout, nothing else.
  -h, --help        Show this help and exit.

At least one of --spec, --feature or --clear-feature is required.

Exit codes: 0 ok, 2 usage error, unknown id, or an ambiguous prefix (the message names the
collision, exactly as rush_feature_dir reports it).
EOF
}

SPEC_ARG=""
FEATURE_ARG=""
CLEAR_FEATURE=false
JSON_OUT=false

while [ $# -gt 0 ]; do
  case "$1" in
    --spec)
      [ $# -ge 2 ] || rush_die "--spec requires a spec id" 2
      SPEC_ARG="$2"; shift 2 ;;
    --feature)
      [ $# -ge 2 ] || rush_die "--feature requires a feature id" 2
      FEATURE_ARG="$2"; shift 2 ;;
    --clear-feature) CLEAR_FEATURE=true; shift ;;
    --json) JSON_OUT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) rush_die "unknown argument: $1" 2 ;;
  esac
done

if [ -z "$SPEC_ARG" ] && [ -z "$FEATURE_ARG" ] && [ "$CLEAR_FEATURE" = false ]; then
  usage >&2
  exit 2
fi
if [ -n "$FEATURE_ARG" ] && [ "$CLEAR_FEATURE" = true ]; then
  rush_die "--feature and --clear-feature are mutually exclusive" 2
fi

ROOT="$(rush_root)" || exit 2
PY="$(rush_python)" || exit 2
export RUSH_ROOT="$ROOT"
LIB="${RUSH_LIB_DIR:-$ROOT/.rush/scripts/lib}/rushlib.py"
STATE="$ROOT/.rush/state.json"

SPEC_ID=""
FEATURE_ID=""

if [ -n "$FEATURE_ARG" ]; then
  # rush_feature_dir echoes specs/<spec-id>/<feature-id> and fails with a named
  # ambiguity when a bare id matches under more than one spec. Deriving the spec
  # from the resolved path is what keeps the two cursor fields consistent.
  FEATURE_DIR="$(rush_feature_dir "$FEATURE_ARG" "$SPEC_ARG")" || exit 2
  FEATURE_ID="$(basename "$FEATURE_DIR")"
  SPEC_ID="$(basename "$(dirname "$FEATURE_DIR")")"
elif [ -n "$SPEC_ARG" ]; then
  SPEC_DIR="$(rush_spec_dir "$SPEC_ARG")" || exit 2
  SPEC_ID="$(basename "$SPEC_DIR")"
fi

if [ -n "$SPEC_ID" ]; then
  SPEC_JSON="$("$PY" -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$SPEC_ID")"
  "$PY" "$LIB" json-set "$STATE" current_spec "$SPEC_JSON" || exit 2
fi

if [ "$CLEAR_FEATURE" = true ]; then
  "$PY" "$LIB" json-set "$STATE" current_feature '""' || exit 2
elif [ -n "$FEATURE_ID" ]; then
  FEATURE_JSON="$("$PY" -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$FEATURE_ID")"
  "$PY" "$LIB" json-set "$STATE" current_feature "$FEATURE_JSON" || exit 2
fi

CURRENT_SPEC="$(rush_current_spec)" || exit 2
CURRENT_FEATURE="$(rush_current_feature)" || exit 2

if [ "$JSON_OUT" = true ]; then
  "$PY" -c '
import json, sys
spec, feature = sys.argv[1], sys.argv[2]
print(json.dumps({
    "current_spec": spec or None,
    "current_feature": feature or None,
    "dir": ("specs/%s/%s" % (spec, feature)) if spec and feature else (("specs/%s" % spec) if spec else None),
}, ensure_ascii=False))
' "$CURRENT_SPEC" "$CURRENT_FEATURE"
  exit 0
fi

if [ -n "$CURRENT_FEATURE" ]; then
  rush_ok "current: specs/$CURRENT_SPEC/$CURRENT_FEATURE"
elif [ -n "$CURRENT_SPEC" ]; then
  rush_ok "current: specs/$CURRENT_SPEC (no feature)"
else
  rush_ok "current: nothing set"
fi

exit 0

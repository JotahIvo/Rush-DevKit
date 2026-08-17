# common.sh - shared bash helpers for .rush/scripts/*.sh
#
# Sourced, never executed: `. "$(dirname "$0")/lib/common.sh"`.
# Targets macOS bash 3.2 and Linux bash. No bashisms newer than 3.2
# (no `mapfile`, no associative arrays, no `${var,,}`).
#
# Functions that *resolve* something (rush_root, rush_python) never call
# `exit` themselves: they print to stderr and `return 1` on failure, so
# they are safe to use inside `$(...)`. Callers use the idiom:
#
#   root="$(rush_root)" || exit 2
#   py="$(rush_python)" || exit 2
#
# Functions that are pure *messages* (rush_die, rush_warn, rush_ok,
# rush_info, rush_json_out) write to the right stream and, for rush_die
# and rush_json_out, terminate the process directly — call them only from
# the main script body, never from inside `$(...)`.

if [ -n "${RUSH_LIB_COMMON_SH_LOADED:-}" ]; then
  return 0 2>/dev/null || exit 0
fi
RUSH_LIB_COMMON_SH_LOADED=1

# Where this library lives. Scripts must resolve rushlib.py relative to
# THEMSELVES, not to the project root: the two coincide in a normal install,
# but not when a script is invoked against another directory (eval fixtures,
# a project that vendored only part of the kit). Resolving via the project
# root made triage.sh fail with a missing rushlib.py in exactly that case.
RUSH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
export RUSH_LIB_DIR

# --- messages (stderr) ------------------------------------------------

# rush_die <msg> [exit-code]
# Print an error and exit the process. Default exit code is 2 (usage /
# internal error), matching the kit-wide convention. Only call this from
# the main script body — not from inside `$(...)`.
rush_die() {
  printf '[rush] ERROR: %s\n' "$1" >&2
  exit "${2:-2}"
}

# rush_warn <msg>
rush_warn() {
  printf '[rush] WARN: %s\n' "$1" >&2
}

# rush_ok <msg>
rush_ok() {
  printf '[rush] OK: %s\n' "$1" >&2
}

# rush_info <msg>
rush_info() {
  printf '[rush] %s\n' "$1" >&2
}

# rush_json_out <json>
# Print exactly one JSON object/array to stdout and exit 0. Per contract,
# --json mode prints one JSON value on stdout and nothing else.
rush_json_out() {
  printf '%s\n' "$1"
  exit 0
}

# --- environment resolution --------------------------------------------

# rush_have <cmd>
# True (exit 0) if <cmd> is available on PATH.
rush_have() {
  command -v "$1" >/dev/null 2>&1
}

# rush_python
# Echo the command to invoke Python 3 (a path or bare name suitable for
# `"$(rush_python)" script.py ...`). Returns 1 with an actionable message
# on stderr if no Python 3 interpreter is available.
rush_python() {
  if rush_have python3; then
    command -v python3
    return 0
  fi
  if rush_have python; then
    if python -c 'import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1; then
      command -v python
      return 0
    fi
  fi
  printf '[rush] ERROR: python3 not found on PATH.\n' >&2
  printf '  Rush DevKit scripts require Python 3.8+ (stdlib only, no packages).\n' >&2
  printf '  Install it and retry, e.g.:\n' >&2
  printf '    macOS:  brew install python3\n' >&2
  printf '    Debian/Ubuntu: sudo apt-get install python3\n' >&2
  printf '    https://www.python.org/downloads/\n' >&2
  return 1
}

# --- project discovery ---------------------------------------------------

# rush_root
# Echo the absolute path of the project root (the directory that contains
# `.rush/`), searching upward from the current working directory. Returns
# 1 with a message on stderr if none is found.
rush_root() {
  local dir
  dir="$(pwd -P 2>/dev/null)" || dir="$PWD"
  while :; do
    if [ -d "$dir/.rush" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    if [ "$dir" = "/" ]; then
      break
    fi
    dir="$(dirname "$dir")"
  done
  printf '[rush] ERROR: no .rush/ directory found in %s or any parent directory.\n' "$PWD" >&2
  printf '  Run this from inside a Rush DevKit project (or a subdirectory of one).\n' >&2
  return 1
}

# _rush_root_env
# Internal: RUSH_ROOT if already exported/set by the caller, else resolve
# it fresh via rush_root. Used by helpers below so a script that already
# did `root="$(rush_root)"` and `export RUSH_ROOT="$root"` doesn't pay to
# re-walk the filesystem on every helper call.
_rush_root_env() {
  if [ -n "${RUSH_ROOT:-}" ]; then
    printf '%s\n' "$RUSH_ROOT"
    return 0
  fi
  rush_root
}

# rush_config <dotted.path> [default]
# Read a value from .rush/config.json at a dotted path (e.g.
# "triage.max_files_for_S"). Prints the value (raw for strings/numbers,
# "true"/"false" for booleans, compact JSON for arrays/objects) or the
# given default (default: empty string) when the key or the file is
# absent. A config.json that exists but fails to parse as JSON is a real
# error: this returns 1 (callers should `|| exit 2`).
rush_config() {
  local path="$1"
  local default="${2:-}"
  local root py
  root="$(_rush_root_env)" || return 1
  py="$(rush_python)" || return 1
  "$py" "${RUSH_LIB_DIR:-$root/.rush/scripts/lib}/rushlib.py" json-get \
    "$root/.rush/config.json" "$path" --default "$default"
}

# rush_config_bool <dotted.path> [default:true|false]
# Like rush_config but coerces the result to "true" or "false".
rush_config_bool() {
  local path="$1"
  local default="${2:-false}"
  local root py
  root="$(_rush_root_env)" || return 1
  py="$(rush_python)" || return 1
  "$py" "${RUSH_LIB_DIR:-$root/.rush/scripts/lib}/rushlib.py" json-get \
    "$root/.rush/config.json" "$path" --type bool --default "$default"
}

# --- spec / feature nesting -------------------------------------------
#
# specs/<spec-id>/ is the PARENT unit ("spec"): pitch.md and prd.md live
# directly in it. Deliverable work lives one level deeper, in
# specs/<spec-id>/<feature-id>/: spec.md, plan.md, tasks.md,
# done-contract.md, progress.md. Both levels carry their own independent
# numeric id (feature ids restart at 001 inside each spec, same as task
# ids restart inside each feature's tasks.md). This nesting exists because
# a spec is routinely one appetite/PRD worth of work split into several
# features by /rush-features, and those features belong together on disk,
# not scattered as siblings with only integration-map.md tying them back.

# rush_spec_dir <id>
# Echo "specs/<full-spec-id>" resolving a partial numeric prefix
# ("001" -> "specs/001-autenticacao"). Exact matches win over prefix
# matching. Returns 1 with a message on stderr if there is no match or
# more than one.
rush_spec_dir() {
  local id="${1:-}"
  if [ -z "$id" ]; then
    printf '[rush] ERROR: rush_spec_dir requires a spec id.\n' >&2
    return 1
  fi
  local root specs
  root="$(_rush_root_env)" || return 1
  specs="$root/specs"
  if [ ! -d "$specs" ]; then
    printf '[rush] ERROR: no specs/ directory under %s.\n' "$root" >&2
    return 1
  fi
  if [ -d "$specs/$id" ]; then
    printf 'specs/%s\n' "$id"
    return 0
  fi
  local restore_nullglob count match base d
  restore_nullglob="$(shopt -p nullglob 2>/dev/null || true)"
  shopt -s nullglob
  count=0
  match=""
  for d in "$specs/$id"*/; do
    base="$(basename "$d")"
    count=$((count + 1))
    match="$base"
  done
  eval "$restore_nullglob" 2>/dev/null || true
  if [ "$count" -eq 0 ]; then
    printf "[rush] ERROR: no spec matches id/prefix '%s' under specs/.\n" "$id" >&2
    return 1
  fi
  if [ "$count" -gt 1 ]; then
    printf "[rush] ERROR: '%s' matches more than one spec under specs/; be more specific.\n" "$id" >&2
    return 1
  fi
  printf 'specs/%s\n' "$match"
  return 0
}

# rush_feature_dir <feature-id> [spec-id]
# Echo "specs/<spec-id>/<full-feature-id>" — the level where
# spec.md/plan.md/tasks.md/done-contract.md/progress.md actually live.
# Searches every spec under specs/*/ unless [spec-id] narrows it (pass it
# whenever you already know the spec, and always when a feature id/prefix
# could plausibly collide across specs). Exact match wins over prefix
# match. Returns 1 with a message on stderr if there is no match or more
# than one — the error names the ambiguity and how to resolve it.
rush_feature_dir() {
  local id="${1:-}"
  local spec_id="${2:-}"
  if [ -z "$id" ]; then
    printf '[rush] ERROR: rush_feature_dir requires a feature id.\n' >&2
    return 1
  fi
  local root specs
  root="$(_rush_root_env)" || return 1
  specs="$root/specs"
  if [ ! -d "$specs" ]; then
    printf '[rush] ERROR: no specs/ directory under %s.\n' "$root" >&2
    return 1
  fi

  local scope=""
  if [ -n "$spec_id" ]; then
    local spec_dir
    spec_dir="$(rush_spec_dir "$spec_id")" || return 1
    scope="$root/$spec_dir"
  fi

  local restore_nullglob count match sd d
  restore_nullglob="$(shopt -p nullglob 2>/dev/null || true)"
  shopt -s nullglob

  # Pass 1: exact match.
  count=0
  match=""
  if [ -n "$scope" ]; then
    if [ -d "$scope/$id" ]; then
      count=1
      match="$scope/$id"
    fi
  else
    for sd in "$specs"/*/; do
      if [ -d "$sd$id" ]; then
        count=$((count + 1))
        match="$sd$id"
      fi
    done
  fi
  if [ "$count" -eq 1 ]; then
    eval "$restore_nullglob" 2>/dev/null || true
    printf 'specs/%s\n' "${match#"$specs"/}"
    return 0
  fi
  if [ "$count" -gt 1 ]; then
    eval "$restore_nullglob" 2>/dev/null || true
    printf "[rush] ERROR: '%s' matches a feature under more than one spec; pass the spec id (rush_feature_dir '%s' <spec-id>).\n" "$id" "$id" >&2
    return 1
  fi

  # Pass 2: prefix match.
  count=0
  match=""
  if [ -n "$scope" ]; then
    for d in "$scope/$id"*/; do
      count=$((count + 1))
      match="${d%/}"
    done
  else
    for sd in "$specs"/*/; do
      for d in "$sd$id"*/; do
        count=$((count + 1))
        match="${d%/}"
      done
    done
  fi
  eval "$restore_nullglob" 2>/dev/null || true

  if [ "$count" -eq 0 ]; then
    printf "[rush] ERROR: no feature matches id/prefix '%s' under specs/*/.\n" "$id" >&2
    return 1
  fi
  if [ "$count" -gt 1 ]; then
    printf "[rush] ERROR: '%s' matches more than one feature under specs/*/; be more specific (or pass the spec id).\n" "$id" >&2
    return 1
  fi
  printf 'specs/%s\n' "${match#"$specs"/}"
  return 0
}

# rush_current_spec
# Echo the active spec id from .rush/state.json -> current_spec. Prints an
# empty string (exit 0) when there is no state.json or none is set.
rush_current_spec() {
  local root py state
  root="$(_rush_root_env)" || return 1
  state="$root/.rush/state.json"
  if [ ! -f "$state" ]; then
    printf ''
    return 0
  fi
  py="$(rush_python)" || return 1
  "$py" "${RUSH_LIB_DIR:-$root/.rush/scripts/lib}/rushlib.py" json-get "$state" current_spec --default ""
}

# rush_current_feature
# Echo the active feature id (inside the active spec) from
# .rush/state.json -> current_feature. Prints an empty string (exit 0)
# when there is no state.json or no feature is set.
rush_current_feature() {
  local root py state
  root="$(_rush_root_env)" || return 1
  state="$root/.rush/state.json"
  if [ ! -f "$state" ]; then
    printf ''
    return 0
  fi
  py="$(rush_python)" || return 1
  "$py" "${RUSH_LIB_DIR:-$root/.rush/scripts/lib}/rushlib.py" json-get "$state" current_feature --default ""
}

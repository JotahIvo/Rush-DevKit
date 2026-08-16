#!/usr/bin/env bash
# triage.sh - deterministic part of S/M/L triage. Never decides alone
# when there is real uncertainty: it flags needs_human_confirmation
# instead of guessing.
#
# Usage: triage.sh [--paths "a b c"] [--files N] [--json]
#
# Exit 0 always on a successful run (S/M/L is a classification, not a
# pass/fail check), 2 on usage or internal error.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: triage.sh [--paths "a b c"] [--files N] [--json]

Deterministic signals for S/M/L triage: file count, sensitive paths
touched (config.json -> security.sensitive_paths), a contract file
changed, a migration was touched, or a new dependency was added
(lockfile/manifest changed). Any of those forces level L. Otherwise:
file_count <= triage.max_files_for_S -> S; else M with
needs_human_confirmation: true (this script never picks between S and M
by itself when there's no strong signal either way).

  --paths "a b c"   Explicit space-separated path list to evaluate.
                     Without it, paths are derived from
                     `git diff --name-only HEAD` plus untracked files.
  --files N         Override the file_count used for the S/M threshold.
                     Useful with --paths omitted when only a count is
                     known. Signals that need real paths (sensitive/
                     contract/migration/dependency) are skipped in that
                     case and noted in `reasons`.
  --json            Print a single JSON object on stdout, nothing else.
  -h, --help        Show this help.

Exit codes: 0 ok, 2 usage/internal error.
EOF
}

json_mode="false"
paths_arg=""
paths_given="false"
files_override=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true"; shift ;;
    --paths)
      [ "$#" -ge 2 ] || { echo "triage.sh: --paths requires a value" >&2; exit 2; }
      paths_arg="$2"; paths_given="true"; shift 2 ;;
    --files)
      [ "$#" -ge 2 ] || { echo "triage.sh: --files requires a value" >&2; exit 2; }
      files_override="$2"; shift 2 ;;
    -*) echo "triage.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) echo "triage.sh: unexpected argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -n "$files_override" ]; then
  case "$files_override" in
    ''|*[!0-9]*) echo "triage.sh: --files expects a non-negative integer, got '$files_override'" >&2; exit 2 ;;
  esac
fi

root="$(rush_root)" || exit 2
py="$(rush_python)" || exit 2

paths_known="true"
paths_list=""

if [ "$paths_given" = "true" ]; then
  # --paths is a single space-separated argument by contract; rely on
  # word-splitting on purpose to turn it into one path per line.
  # shellcheck disable=SC2086
  paths_list="$(printf '%s\n' $paths_arg)"
elif [ -n "$files_override" ]; then
  paths_known="false"
else
  # Derive from the working tree: staged/unstaged diff against HEAD, plus
  # untracked files. In a repo with no commits yet there is no HEAD, so
  # diff against git's well-known empty-tree object instead.
  if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git -C "$root" rev-parse --verify -q HEAD >/dev/null 2>&1; then
      diff_paths="$(git -C "$root" diff --name-only HEAD 2>/dev/null || true)"
    else
      empty_tree="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
      diff_paths="$(git -C "$root" diff --name-only "$empty_tree" 2>/dev/null || true)"
    fi
    untracked_paths="$(git -C "$root" ls-files --others --exclude-standard 2>/dev/null || true)"
    paths_list="$(printf '%s\n%s\n' "$diff_paths" "$untracked_paths" | awk 'NF && !seen[$0]++')"
  else
    paths_known="false"
  fi
fi

file_count="${files_override:-}"
if [ -z "$file_count" ]; then
  if [ "$paths_known" = "true" ]; then
    file_count="$(printf '%s\n' "$paths_list" | awk 'NF' | wc -l | tr -d ' ')"
  else
    file_count=0
  fi
fi

max_files_s="$(rush_config triage.max_files_for_S 3)" || exit 2

result_file="$(mktemp)"
paths_file="$(mktemp)"
trap 'rm -f "$result_file" "$paths_file"' EXIT
printf '%s\n' "$paths_list" > "$paths_file"

# paths travel via a temp file, not a pipe: stdin here is the Python
# source itself (fed via the heredoc below), so piping data into it
# would be silently lost (consumed as part of reading the program).
set +e
"$py" - "$root" "$file_count" "$max_files_s" "$paths_known" "$paths_file" > "$result_file" <<'PYEOF'
import json, os, sys

root = sys.argv[1]
file_count = int(sys.argv[2])
max_files_s = sys.argv[3]
paths_known = sys.argv[4] == "true"
paths_file = sys.argv[5]
with open(paths_file, encoding="utf-8") as f:
    paths = [p for p in f.read().split("\n") if p.strip() != ""]

try:
    max_files_s = int(max_files_s)
except ValueError:
    max_files_s = 3

sys.path.insert(0, os.environ.get("RUSH_LIB_DIR") or os.path.join(root, ".rush", "scripts", "lib"))
import rushlib  # noqa: E402

cfg_path = os.path.join(root, ".rush", "config.json")
cfg = {}
if os.path.isfile(cfg_path):
    try:
        cfg = rushlib.load_json_file(cfg_path)
    except (OSError, json.JSONDecodeError) as e:
        print("triage.sh: cannot parse .rush/config.json: %s" % e, file=sys.stderr)
        sys.exit(2)

sensitive_raw = rushlib.get_path(cfg, "security.sensitive_paths")
sensitive_paths = sensitive_raw if isinstance(sensitive_raw, list) else []
sensitive_paths = [str(s) for s in sensitive_paths]

# Scoped to what validate-contracts.sh validates: specs/*/contracts/ and
# specs/shared-contracts/. Deliberately not a bare ".schema.json" suffix
# match - that would also fire on unrelated schemas elsewhere in the
# repo (e.g. .rush/config.schema.json), which is not a feature contract.


def is_contract_path(p):
    if not p.startswith("specs/"):
        return False
    return "/contracts/" in ("/" + p) or "/shared-contracts/" in ("/" + p)
MIGRATION_MARKERS = ("/migrations/", "/migration/")
DEPENDENCY_FILES = {
    "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb",
    "requirements.txt", "poetry.lock", "pyproject.toml", "Pipfile", "Pipfile.lock", "uv.lock",
    "go.mod", "go.sum", "Cargo.toml", "Cargo.lock", "Gemfile", "Gemfile.lock",
    "composer.json", "composer.lock",
}

sensitive_hits = []
contract_changed = False
migration_detected = False
new_dependency = False

for p in paths:
    norm = "/" + p.strip("/") + "/"
    for s in sensitive_paths:
        if not s:
            continue
        s_norm = s if s.startswith("/") else "/" + s
        if p.startswith(s.lstrip("/")) or s_norm.rstrip("/") + "/" in norm:
            if p not in sensitive_hits:
                sensitive_hits.append(p)
            break
    if is_contract_path(p):
        contract_changed = True
    if any(marker in norm for marker in MIGRATION_MARKERS):
        migration_detected = True
    if os.path.basename(p) in DEPENDENCY_FILES:
        new_dependency = True

reasons = []
forced = False
if not paths_known:
    reasons.append("no explicit paths and no usable git working tree; only file_count is known")

if sensitive_hits:
    forced = True
    reasons.append("touches sensitive path(s): %s" % ", ".join(sensitive_hits))
if contract_changed:
    forced = True
    reasons.append("touches a contract file (specs/*/contracts/ or shared-contracts/)")
if migration_detected:
    forced = True
    reasons.append("touches a migration")
if new_dependency:
    forced = True
    reasons.append("adds/changes a dependency manifest or lockfile")

needs_human_confirmation = False
if forced:
    level = "L"
elif file_count <= max_files_s:
    level = "S"
else:
    level = "M"
    needs_human_confirmation = True
    reasons.append(
        "file_count (%d) > triage.max_files_for_S (%d) with no strong signal either way"
        % (file_count, max_files_s)
    )

out = {
    "level": level,
    "forced": forced,
    "signals": {
        "file_count": file_count,
        "sensitive_paths_touched": sensitive_hits,
        "contract_changed": contract_changed,
        "migration_detected": migration_detected,
        "new_dependency": new_dependency,
    },
    "reasons": reasons,
    "needs_human_confirmation": needs_human_confirmation,
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
print("level: %s%s" % (data["level"], " (forced)" if data["forced"] else ""))
s = data["signals"]
print("  file_count: %d" % s["file_count"])
if s["sensitive_paths_touched"]:
    print("  sensitive_paths_touched: %s" % ", ".join(s["sensitive_paths_touched"]))
print("  contract_changed: %s" % s["contract_changed"])
print("  migration_detected: %s" % s["migration_detected"])
print("  new_dependency: %s" % s["new_dependency"])
if data["reasons"]:
    print("reasons:")
    for r in data["reasons"]:
        print("  - %s" % r)
if data["needs_human_confirmation"]:
    print("needs human confirmation: yes")
PYEOF
fi

exit 0

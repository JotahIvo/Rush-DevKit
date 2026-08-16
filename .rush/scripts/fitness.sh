#!/usr/bin/env bash
# fitness.sh - run every .rush/memory/fitness/*.sh fitness function,
# filtered by scope, and aggregate the results.
#
# Usage: fitness.sh [<feature-id>|--all] [--json]
#
# Exit 0 all fitness functions pass, 1 at least one fails, 2 usage/internal.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: fitness.sh [<feature-id>|--all] [--json]

Runs every *.sh file under .rush/memory/fitness/. Each file must declare,
in its leading comment block:

  # description: <one line>
  # scope: all | <feature-id>[,<feature-id>...]

A fitness function is run when its scope is "all", or when it lists the
requested feature id (or a prefix/superset match of it). With no argument
(or --all), every fitness function runs regardless of scope.

Each function runs with the project root as its working directory and
must exit 0 (pass) or non-zero (fail). Passing functions report an empty
output_tail; failing functions report their last 40 lines of output. A
file missing its header, or not executable, is reported invalid (fails
the run).

  --json       Print a single JSON object on stdout, nothing else.
  -h, --help   Show this help.

Exit codes: 0 all pass, 1 at least one fails or is invalid, 2 usage/internal error.
EOF
}

json_mode="false"
target="--all"
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true" ;;
    --all) target="--all" ;;
    -*) echo "fitness.sh: unknown option: $arg" >&2; usage >&2; exit 2 ;;
    *) target="$arg" ;;
  esac
done

root="$(rush_root)" || exit 2
fitness_dir="$root/.rush/memory/fitness"

files=""
if [ -d "$fitness_dir" ]; then
  for f in "$fitness_dir"/*.sh; do
    [ -e "$f" ] || continue
    files="$files $f"
  done
fi

result_file="$(mktemp)"
trap 'rm -f "$result_file"' EXIT

set +e
# shellcheck disable=SC2086
"$(rush_python)" - "$root" "$target" $files > "$result_file" <<'PYEOF'
import json, os, re, subprocess, sys

root, target = sys.argv[1], sys.argv[2]
files = sys.argv[3:]

def tail_lines(text, n=40):
    return "\n".join(text.splitlines()[-n:])

def scope_applies(scope, target):
    if target == "--all":
        return True
    if scope == "all":
        return True
    scope_ids = [s.strip() for s in scope.split(",") if s.strip()]
    return any(s == target or s.startswith(target) or target.startswith(s) for s in scope_ids)

entries = []
for f in files:
    base = os.path.basename(f)
    try:
        with open(f, encoding="utf-8", errors="replace") as fh:
            head = fh.read(4000)
    except Exception as e:
        entries.append({
            "name": base, "description": "", "scope": "",
            "status": "invalid", "exit_code": None,
            "output_tail": "could not read file: %s" % e,
        })
        continue

    dm = re.search(r"^#\s*description:\s*(.*)$", head, re.MULTILINE)
    sm = re.search(r"^#\s*scope:\s*(.*)$", head, re.MULTILINE)
    description = dm.group(1).strip() if dm else ""
    scope = sm.group(1).strip() if sm else ""

    # A missing header is a defect in the fitness function itself: always
    # surface it (it is not filtered out by scope, since it has none).
    if not description or not scope:
        entries.append({
            "name": base, "description": description, "scope": scope,
            "status": "invalid", "exit_code": None,
            "output_tail": "missing required '# description:' and/or '# scope:' header",
        })
        continue

    if not scope_applies(scope, target):
        continue

    if not os.access(f, os.X_OK):
        entries.append({
            "name": base, "description": description, "scope": scope,
            "status": "invalid", "exit_code": None,
            "output_tail": "%s is not executable (chmod +x it)" % base,
        })
        continue

    try:
        proc = subprocess.run([f], cwd=root, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, timeout=120)
        out = proc.stdout.decode("utf-8", errors="replace")
        ec = proc.returncode
    except subprocess.TimeoutExpired:
        out = "TIMEOUT after 120s"
        ec = None
    except Exception as e:
        out = "failed to execute: %s" % e
        ec = None

    status = "pass" if ec == 0 else "fail"
    entries.append({
        "name": base, "description": description, "scope": scope,
        "status": status, "exit_code": ec,
        "output_tail": "" if status == "pass" else tail_lines(out, 40),
    })

passed = sum(1 for e in entries if e["status"] == "pass")
failed = sum(1 for e in entries if e["status"] != "pass")
ok = failed == 0
out = {"ok": ok, "scope": target, "checked": entries, "summary": {"passed": passed, "failed": failed}}
print(json.dumps(out))
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
  "$(rush_python)" - "$payload" <<'PYEOF'
import json, sys
data = json.loads(sys.argv[1])
print("fitness scope: %s" % data["scope"])
if not data["checked"]:
    print("no fitness functions apply")
for c in data["checked"]:
    mark = {"pass": "PASS", "fail": "FAIL", "invalid": "INVALID"}.get(c["status"], c["status"].upper())
    print("  [%s] %s - %s" % (mark, c["name"], c["description"] or "(no description)"))
    if c["status"] != "pass" and c["output_tail"]:
        for line in c["output_tail"].splitlines():
            print("      %s" % line)
s = data["summary"]
print("summary: %d passed, %d failed" % (s["passed"], s["failed"]))
PYEOF
fi

ok="$("$(rush_python)" -c "import json,sys; print(json.loads(sys.argv[1])['ok'])" "$payload")"
if [ "$ok" = "True" ]; then
  exit 0
else
  exit 1
fi

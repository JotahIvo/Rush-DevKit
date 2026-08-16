#!/usr/bin/env bash
# done-check.sh - the Definition of Done executor. Parses the fenced
# ```json block of specs/<feature-id>/done-contract.md, runs every "run"
# command from the project root with a timeout, and compares against
# "expect". Success is silent, failure is verbose.
#
# Usage: done-check.sh <feature-id> [--json] [--only <check-name>]
#
# Exit 0 all checks pass and all gates confirmed, 1 a check failed or a
# gate is pending, 2 usage/internal error.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: done-check.sh <feature-id> [--json] [--only <check-name>]

Runs every "run" command declared in specs/<feature-id>/done-contract.md's
fenced ```json block from the project root, and compares each result
against its "expect":

  exit 0 | exit N        exit code must equal N
  contains: <text>       combined stdout+stderr must contain <text>
  not_contains: <text>   combined stdout+stderr must not contain <text>

Timeout per check: config.json -> verification.check_timeout_seconds
(default 600 seconds).

Passing checks report an empty output_tail. Failing checks report the
last 40 lines of combined output.

human_gates are reported unconfirmed unless recorded in
.rush/state.json -> gates_confirmed.<feature-id> (an array of the exact
gate text strings that have been confirmed).

  --only <name>   Run/report only the check with this exact name.
  --json          Print a single JSON object on stdout, nothing else.
  -h, --help      Show this help.

Exit codes: 0 ok, 1 a check failed or a gate is pending, 2 usage/internal error.
EOF
}

json_mode="false"
only=""
feature_id=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true"; shift ;;
    --only)
      shift
      [ $# -gt 0 ] || { echo "done-check.sh: --only requires a check name" >&2; exit 2; }
      only="$1"; shift ;;
    -*) echo "done-check.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [ -n "$feature_id" ]; then
        echo "done-check.sh: unexpected extra argument: $1" >&2; exit 2
      fi
      feature_id="$1"; shift ;;
  esac
done

if [ -z "$feature_id" ]; then
  echo "done-check.sh: <feature-id> is required" >&2
  usage >&2
  exit 2
fi

root="$(rush_root)" || exit 2

result_file="$(mktemp)"
trap 'rm -f "$result_file"' EXIT

set +e
"$(rush_python)" - "$root" "$feature_id" "$only" > "$result_file" <<'PYEOF'
import json, os, re, subprocess, sys, time

root, feature_id, only = sys.argv[1], sys.argv[2], sys.argv[3]

def resolve_feature_dir():
    specs = os.path.join(root, "specs")
    if os.path.isdir(os.path.join(specs, feature_id)):
        return feature_id
    if not os.path.isdir(specs):
        return None
    matches = [n for n in sorted(os.listdir(specs))
               if os.path.isdir(os.path.join(specs, n)) and n.startswith(feature_id)]
    if len(matches) == 1:
        return matches[0]
    return None

fid = resolve_feature_dir()
if fid is None:
    print(json.dumps({"error": "no feature matching '%s'" % feature_id}), file=sys.stderr)
    sys.exit(2)

contract_path = os.path.join(root, "specs", fid, "done-contract.md")
if not os.path.isfile(contract_path):
    print(json.dumps({"error": "not found: specs/%s/done-contract.md" % fid}), file=sys.stderr)
    sys.exit(2)

with open(contract_path, encoding="utf-8") as f:
    text = f.read()

m = re.search(r"```json\s*\n(.*?)```", text, re.DOTALL)
if not m:
    print(json.dumps({"error": "no fenced json block found in done-contract.md"}), file=sys.stderr)
    sys.exit(2)

try:
    contract = json.loads(m.group(1))
except Exception as e:
    print(json.dumps({"error": "fenced json block does not parse: %s" % e}), file=sys.stderr)
    sys.exit(2)

checks = contract.get("checks")
if not isinstance(checks, list) or not checks:
    print(json.dumps({"error": "done-contract.md 'checks' must be a non-empty array"}), file=sys.stderr)
    sys.exit(2)

if only:
    names = [c.get("name") for c in checks if isinstance(c, dict)]
    if only not in names:
        print(json.dumps({"error": "no check named '%s' (available: %s)" % (only, ", ".join(str(n) for n in names))}), file=sys.stderr)
        sys.exit(2)
    checks = [c for c in checks if c.get("name") == only]

def load_config():
    cfg_path = os.path.join(root, ".rush", "config.json")
    try:
        with open(cfg_path) as f:
            return json.load(f)
    except Exception:
        return {}

cfg = load_config()
timeout_s = 600
try:
    timeout_s = int(((cfg.get("verification") or {}).get("check_timeout_seconds")) or 600)
except Exception:
    timeout_s = 600

def parse_expect(expect):
    if not isinstance(expect, str):
        return None
    s = expect.strip()
    m = re.match(r"^exit\s+(-?\d+)$", s)
    if m:
        return ("exit", int(m.group(1)))
    m = re.match(r"^contains:\s*(.*)$", s, re.DOTALL)
    if m:
        return ("contains", m.group(1))
    m = re.match(r"^not_contains:\s*(.*)$", s, re.DOTALL)
    if m:
        return ("not_contains", m.group(1))
    return None

def tail_lines(text, n=40):
    lines = text.splitlines()
    return "\n".join(lines[-n:])

results = []
passed = 0
failed = 0

for c in checks:
    name = c.get("name", "<unnamed check>")
    run = c.get("run")
    expect_raw = c.get("expect")
    parsed = parse_expect(expect_raw)
    start = time.time()
    if not run or parsed is None:
        results.append({
            "name": name, "status": "fail", "exit_code": None,
            "duration_ms": 0,
            "output_tail": "malformed check: run=%r expect=%r" % (run, expect_raw),
        })
        failed += 1
        continue
    try:
        proc = subprocess.run(
            run, shell=True, cwd=root,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=timeout_s,
        )
        out = proc.stdout.decode("utf-8", errors="replace")
        exit_code = proc.returncode
        timed_out = False
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode("utf-8", errors="replace") if isinstance(e.stdout, (bytes, bytearray)) else (e.stdout or "")
        exit_code = None
        timed_out = True
    duration_ms = int((time.time() - start) * 1000)

    kind, value = parsed
    if timed_out:
        ok = False
        out = (out + "\n[done-check] TIMEOUT after %ds" % timeout_s) if out else "[done-check] TIMEOUT after %ds" % timeout_s
    elif kind == "exit":
        ok = (exit_code == value)
    elif kind == "contains":
        ok = (value in out)
    elif kind == "not_contains":
        ok = (value not in out)
    else:
        ok = False

    status = "pass" if ok else "fail"
    if status == "pass":
        passed += 1
        output_tail = ""
    else:
        failed += 1
        output_tail = tail_lines(out, 40)

    results.append({
        "name": name, "status": status, "exit_code": exit_code,
        "duration_ms": duration_ms, "output_tail": output_tail,
    })

gates_raw = contract.get("human_gates") or []
state_path = os.path.join(root, ".rush", "state.json")
try:
    with open(state_path) as f:
        state = json.load(f)
except Exception:
    state = {}
confirmed_list = ((state.get("gates_confirmed") or {}).get(fid)) or []
if not isinstance(confirmed_list, list):
    confirmed_list = []

gates = []
gates_pending = 0
for g in gates_raw:
    text_g = g if isinstance(g, str) else str(g)
    confirmed = text_g in confirmed_list
    if not confirmed:
        gates_pending += 1
    gates.append({"text": text_g, "confirmed": confirmed})

ok = (failed == 0 and gates_pending == 0)
out = {
    "ok": ok,
    "feature": fid,
    "checks": results,
    "human_gates": gates,
    "summary": {"passed": passed, "failed": failed, "gates_pending": gates_pending},
}
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
print("done-check: %s" % data["feature"])
for c in data["checks"]:
    mark = "PASS" if c["status"] == "pass" else "FAIL"
    print("  [%s] %s (%s, %dms)" % (mark, c["name"], c["exit_code"], c["duration_ms"]))
    if c["status"] != "pass" and c["output_tail"]:
        for line in c["output_tail"].splitlines():
            print("      %s" % line)
for g in data["human_gates"]:
    mark = "CONFIRMED" if g["confirmed"] else "PENDING"
    print("  [%s] gate: %s" % (mark, g["text"]))
s = data["summary"]
print("summary: %d passed, %d failed, %d gate(s) pending" % (s["passed"], s["failed"], s["gates_pending"]))
PYEOF
fi

ok="$("$(rush_python)" -c "import json,sys; print(json.loads(sys.argv[1])['ok'])" "$payload")"
if [ "$ok" = "True" ]; then
  exit 0
else
  exit 1
fi

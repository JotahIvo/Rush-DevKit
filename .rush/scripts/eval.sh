#!/usr/bin/env bash
# eval.sh — Rush DevKit eval runner.
#
# For each case in .rush/evals/<agent>/cases/*.json, applies the deterministic
# graders and reports. Graders that require judgement are marked "manual" and
# listed for human review — this runner never fakes an evaluation it cannot
# measure. See docs/internals/script-interfaces.md.
#
# Exit codes: 0 = every deterministic grader passed (manual graders may still
# be pending)   1 = at least one deterministic grader failed
# 2 = usage error / internal failure
#
# Usage: eval.sh [<agent>|--all] [--agent <name>] [--case <id>] [--json]

set -uo pipefail

usage() {
  cat <<'EOF'
eval.sh - Rush DevKit eval runner.

Runs the deterministic graders for each case under
.rush/evals/<agent>/cases/*.json and reports pass/fail/manual. Case format:

  {
    "id": "spec-budget-respected",
    "agent": "rush-spec",
    "description": "...",
    "given": { "cwd": "optional, relative to project root", "setup": "optional shell command" },
    "graders": [
      { "type": "script", "run": "<command>", "expect": "exit 0" },
      { "type": "file_exists", "path": "specs/007-checkout/spec.md" },
      { "type": "budget", "file": "specs/007-checkout/spec.md", "max_lines": 150 },
      { "type": "contains", "file": "specs/007-checkout/spec.md", "text": "## Acceptance Criteria" },
      { "type": "manual", "rubric": "..." }
    ]
  }

'expect' for the "script" grader: "exit 0", "exit N", "contains: <text>",
"not_contains: <text>" (same vocabulary as done-check.sh).

Usage: eval.sh [<agent>|--all] [--agent <name>] [--case <id>] [--json]

Options:
  <agent>          Run all cases for this agent (positional shorthand for --agent).
  --agent <name>   Run all cases for this agent.
  --all            Run cases for every agent under .rush/evals/.
  --case <id>      Run only the case with this id (scoped to --agent if given,
                   otherwise searched across every agent).
  --json           Print a single JSON object on stdout and nothing else.
  -h, --help       Show this help and exit.

Exit codes:
  0  every deterministic grader passed
  1  at least one deterministic grader failed
  2  usage error or internal failure
EOF
}

AGENT=""
ALL=0
CASE_ID=""
JSON_OUT=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --json) JSON_OUT=1; shift ;;
    --all) ALL=1; shift ;;
    --agent)
      shift
      [ $# -gt 0 ] || { echo "eval.sh: --agent requires a value" >&2; exit 2; }
      AGENT="$1"; shift ;;
    --case)
      shift
      [ $# -gt 0 ] || { echo "eval.sh: --case requires a value" >&2; exit 2; }
      CASE_ID="$1"; shift ;;
    --*)
      echo "eval.sh: unknown option: $1" >&2
      usage >&2
      exit 2 ;;
    *)
      if [ -z "$AGENT" ]; then
        AGENT="$1"
      else
        echo "eval.sh: unexpected argument: $1" >&2
        usage >&2
        exit 2
      fi
      shift ;;
  esac
done

if [ "$ALL" -eq 1 ] && [ -n "$AGENT" ]; then
  echo "eval.sh: --all cannot be combined with an agent name" >&2
  exit 2
fi
if [ "$ALL" -eq 0 ] && [ -z "$AGENT" ] && [ -z "$CASE_ID" ]; then
  echo "eval.sh: specify an agent, --all, or --case <id>" >&2
  usage >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "eval.sh: python3 is required but was not found in PATH" >&2
  exit 2
fi

d="$PWD"
ROOT=""
while [ -n "$d" ]; do
  if [ -d "$d/.rush" ]; then ROOT="$d"; break; fi
  [ "$d" = "/" ] && break
  d="$(dirname "$d")"
done
if [ -z "$ROOT" ]; then
  echo "eval.sh: no .rush/ directory found in $PWD or any parent" >&2
  exit 2
fi

python3 - "$ROOT" "$AGENT" "$ALL" "$CASE_ID" "$JSON_OUT" <<'PYEOF'
import json
import os
import re
import subprocess
import sys

ROOT, AGENT, ALL, CASE_ID, JSON_OUT = sys.argv[1:6]
ALL = ALL == "1"
JSON_OUT = JSON_OUT == "1"
EVALS_DIR = os.path.join(ROOT, ".rush", "evals")


def die(msg, code=2):
    sys.stderr.write("eval.sh: %s\n" % msg)
    sys.exit(code)


def list_agents():
    if not os.path.isdir(EVALS_DIR):
        return []
    return sorted(
        a for a in os.listdir(EVALS_DIR)
        if os.path.isdir(os.path.join(EVALS_DIR, a, "cases"))
    )


def list_cases(agent):
    cases_dir = os.path.join(EVALS_DIR, agent, "cases")
    if not os.path.isdir(cases_dir):
        return []
    out = []
    for fn in sorted(os.listdir(cases_dir)):
        if fn.endswith(".json"):
            out.append(os.path.join(cases_dir, fn))
    return out


def run_cmd(cmd, cwd, timeout=120):
    try:
        proc = subprocess.run(
            cmd, shell=True, cwd=cwd, capture_output=True, text=True, timeout=timeout
        )
        return proc.returncode, (proc.stdout or ""), (proc.stderr or "")
    except subprocess.TimeoutExpired:
        return None, "", "timed out after %ss" % timeout
    except Exception as exc:
        return None, "", "could not run: %s" % exc


EXPECT_EXIT_RE = re.compile(r"^exit\s+(\d+)$")


def check_expect(expect, rc, out, err):
    expect = (expect or "exit 0").strip()
    m = EXPECT_EXIT_RE.match(expect)
    if m:
        want = int(m.group(1))
        if rc is None:
            return False, "did not complete (expected exit %d): %s" % (want, err.strip()[-300:])
        ok = rc == want
        return ok, ("exit %d" % rc) if ok else ("expected exit %d, got %d. %s" % (
            want, rc, (err or out).strip()[-300:]))
    if expect.startswith("contains:"):
        text = expect[len("contains:"):].strip()
        hay = out + err
        ok = text in hay
        return ok, "found" if ok else "did not find %r in output" % text
    if expect.startswith("not_contains:"):
        text = expect[len("not_contains:"):].strip()
        hay = out + err
        ok = text not in hay
        return ok, "absent as expected" if ok else "unexpectedly found %r in output" % text
    return False, "unrecognised expect syntax: %r" % expect


def resolve_path(cwd, path):
    if os.path.isabs(path):
        return path
    return os.path.join(cwd, path)


def run_grader(g, cwd):
    gtype = g.get("type")
    if gtype == "script":
        rc, out, err = run_cmd(g.get("run", ""), cwd)
        ok, detail = check_expect(g.get("expect"), rc, out, err)
        return {"type": gtype, "ok": ok, "detail": detail}
    if gtype == "file_exists":
        p = resolve_path(cwd, g.get("path", ""))
        ok = os.path.isfile(p) or os.path.isdir(p)
        return {"type": gtype, "ok": ok,
                "detail": "exists" if ok else "not found: %s" % g.get("path")}
    if gtype == "budget":
        p = resolve_path(cwd, g.get("file", ""))
        try:
            with open(p, "r", errors="ignore") as f:
                n = sum(1 for _ in f)
        except Exception as exc:
            return {"type": gtype, "ok": False, "detail": "could not read %s: %s" % (g.get("file"), exc)}
        max_lines = g.get("max_lines")
        ok = max_lines is None or n <= max_lines
        return {"type": gtype, "ok": ok, "detail": "%d lines (max %s)" % (n, max_lines)}
    if gtype == "contains":
        p = resolve_path(cwd, g.get("file", ""))
        try:
            with open(p, "r", errors="ignore") as f:
                content = f.read()
        except Exception as exc:
            return {"type": gtype, "ok": False, "detail": "could not read %s: %s" % (g.get("file"), exc)}
        text = g.get("text", "")
        ok = text in content
        return {"type": gtype, "ok": ok,
                "detail": "found" if ok else "text not found in %s" % g.get("file")}
    if gtype == "manual":
        return {"type": gtype, "ok": None, "detail": g.get("rubric", "")}
    return {"type": gtype, "ok": False, "detail": "unknown grader type: %r" % gtype}


def run_case(case_path, agent_hint):
    try:
        with open(case_path, "r") as f:
            case = json.load(f)
    except Exception as exc:
        return {
            "id": os.path.basename(case_path).rsplit(".", 1)[0],
            "status": "fail",
            "error": "could not parse case file: %s" % exc,
            "graders": [],
        }

    case_id = case.get("id", os.path.basename(case_path).rsplit(".", 1)[0])
    given = case.get("given") or {}
    cwd = ROOT
    if given.get("cwd"):
        cwd = resolve_path(ROOT, given["cwd"])

    setup_note = None
    if given.get("setup"):
        rc, out, err = run_cmd(given["setup"], cwd)
        if rc != 0:
            setup_note = "given.setup exited %s: %s" % (rc, (err or out).strip()[-300:])

    grader_results = []
    for g in case.get("graders", []) or []:
        try:
            grader_results.append(run_grader(g, cwd))
        except Exception as exc:
            grader_results.append({"type": g.get("type"), "ok": False,
                                    "detail": "grader crashed: %s" % exc})

    has_fail = any(r["ok"] is False for r in grader_results)
    has_manual = any(r["ok"] is None for r in grader_results)
    if has_fail:
        status = "fail"
    elif has_manual:
        status = "manual"
    else:
        status = "pass"

    result = {"id": case_id, "status": status, "graders": grader_results}
    if setup_note:
        result["setup_warning"] = setup_note
    return result


def eval_agent(agent):
    cases = list_cases(agent)
    results = [run_case(cp, agent) for cp in cases]
    passed = sum(1 for r in results if r["status"] == "pass")
    failed = sum(1 for r in results if r["status"] == "fail")
    manual = sum(1 for r in results if r["status"] == "manual")
    return {
        "agent": agent,
        "total": len(results),
        "passed": passed,
        "failed": failed,
        "manual": manual,
        "cases": results,
    }


# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
exit_code = 0

if CASE_ID:
    agents = [AGENT] if AGENT else list_agents()
    found = None
    for a in agents:
        for cp in list_cases(a):
            stem = os.path.basename(cp).rsplit(".", 1)[0]
            if stem == CASE_ID:
                found = (a, cp)
                break
        if found:
            break
    if not found:
        die("no case with id %r found%s" % (
            CASE_ID, (" for agent %r" % AGENT) if AGENT else ""))
    a, cp = found
    r = run_case(cp, a)
    result = {"agent": a, "total": 1, "passed": 1 if r["status"] == "pass" else 0,
              "failed": 1 if r["status"] == "fail" else 0,
              "manual": 1 if r["status"] == "manual" else 0, "cases": [r]}
    exit_code = 1 if r["status"] == "fail" else 0
elif ALL:
    agents = list_agents()
    per_agent = [eval_agent(a) for a in agents]
    total = sum(a["total"] for a in per_agent)
    passed = sum(a["passed"] for a in per_agent)
    failed = sum(a["failed"] for a in per_agent)
    manual = sum(a["manual"] for a in per_agent)
    result = {
        "all": True,
        "total": total, "passed": passed, "failed": failed, "manual": manual,
        "agents": per_agent,
    }
    exit_code = 1 if failed else 0
else:
    if not os.path.isdir(os.path.join(EVALS_DIR, AGENT)):
        die("no eval cases found for agent %r under .rush/evals/" % AGENT)
    result = eval_agent(AGENT)
    exit_code = 1 if result["failed"] else 0

if JSON_OUT:
    sys.stdout.write(json.dumps(result) + "\n")
else:
    def print_agent(a):
        print("agent: %s  total=%d passed=%d failed=%d manual=%d" % (
            a["agent"], a["total"], a["passed"], a["failed"], a["manual"]))
        for c in a["cases"]:
            print("  [%s] %s" % (c["status"].upper(), c["id"]))
            if c["status"] != "pass":
                for g in c.get("graders", []):
                    if g["ok"] is not True:
                        print("      - %s: %s" % (g["type"], g["detail"]))

    if ALL:
        for a in result["agents"]:
            print_agent(a)
        print("")
        print("TOTAL: total=%d passed=%d failed=%d manual=%d" % (
            result["total"], result["passed"], result["failed"], result["manual"]))
    else:
        print_agent(result)

sys.exit(exit_code)
PYEOF
exit $?

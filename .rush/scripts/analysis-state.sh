#!/usr/bin/env bash
# analysis-state.sh - what /rush-analyze already judged, and what moved since.
#
# /rush-analyze's judgement pass is the most expensive read in the flow: it
# holds a feature's whole artifact set in mind at once and reasons across it.
# Re-running it against files nobody touched returns the previous verdict at
# the previous price, which is what makes "run analyze again after the fix"
# cost as much as the first analysis.
#
# This records the fingerprint of everything a verdict was issued against, and
# on the next run says exactly which of those files changed. The narrowing is
# deterministic and lives here, in a script, rather than in an agent's memory
# of what it looked at last time.
#
# Four inputs void any narrowing and force a full pass, because a change to any
# of them can flip a verdict on a file that did not itself change:
# the constitution, the integration map, any contract this feature provides or
# consumes, and the absence of a recorded verdict.
#
# Usage:
#   analysis-state.sh <feature-id> [--spec <spec-id>] [--json]
#   analysis-state.sh <feature-id> --record <GO|NO-GO> [--spec <spec-id>] [--json]
#
# Exit 0 on success, 2 on usage or internal error.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: analysis-state.sh <feature-id> [--record <GO|NO-GO>] [--spec <spec-id>] [--json]

Without --record: reports the last recorded verdict for this feature, which of
the artifacts it was issued against have changed since, and whether a full
judgement pass is required (`full_pass_required`, with `full_pass_reason`).

With --record: stores the verdict plus a fingerprint of every artifact it was
issued against, in .rush/state.json -> analysis.<feature-id>.

  --record <verdict>   GO or NO-GO. Only a GO is usable as a narrowing baseline;
                       a NO-GO is recorded so the next run can show what moved,
                       but it never narrows anything.
  --spec <spec-id>     Scope the feature lookup to one spec.
  --json               Print one JSON object on stdout, nothing else.
  -h, --help           Show this help.

Exit codes: 0 ok, 2 usage/internal error.
EOF
}

feature_arg=""
spec_arg=""
record=""
json_mode="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true" ;;
    --record)
      shift
      [ "$#" -gt 0 ] || { echo "analysis-state.sh: --record requires GO or NO-GO" >&2; exit 2; }
      record="$1"
      ;;
    --spec)
      shift
      [ "$#" -gt 0 ] || { echo "analysis-state.sh: --spec requires a value" >&2; exit 2; }
      spec_arg="$1"
      ;;
    -*) echo "analysis-state.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      [ -z "$feature_arg" ] || { echo "analysis-state.sh: unexpected extra argument: $1" >&2; exit 2; }
      feature_arg="$1"
      ;;
  esac
  shift
done

case "$record" in
  ""|GO|NO-GO) ;;
  *) echo "analysis-state.sh: --record takes GO or NO-GO, not '$record'" >&2; exit 2 ;;
esac

root="$(rush_root)" || exit 2
py="$(rush_python)" || exit 2
export RUSH_ROOT="$root"

[ -n "$feature_arg" ] || feature_arg="$(rush_current_feature)" || exit 2
[ -n "$feature_arg" ] || rush_die "no feature id given and .rush/state.json has no current_feature."
[ -n "$spec_arg" ] || spec_arg="$(rush_current_spec)" || exit 2

feature_dir="$(rush_feature_dir "$feature_arg" "$spec_arg")" || exit 2

"$py" - "$root" "$feature_dir" "$record" "$json_mode" <<'PYEOF'
import hashlib, json, os, sys

root, feature_dir, record, json_mode = sys.argv[1:5]
feature_key = feature_dir[len("specs/"):] if feature_dir.startswith("specs/") else feature_dir

state_path = os.path.join(root, ".rush", "state.json")


def digest(rel):
    p = os.path.join(root, rel)
    try:
        with open(p, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()[:16]
    except OSError:
        return None


def contract_paths():
    out = []
    for base in (os.path.join(feature_dir, "contracts"), os.path.join("specs", "shared-contracts")):
        d = os.path.join(root, base)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if not name.startswith("."):
                out.append((base + "/" + name).replace(os.sep, "/"))
    return out


# VOIDING inputs are fingerprinted separately from the feature's own artifacts:
# a change to one of them invalidates the whole verdict, not just the file that
# changed, because it can flip a judgement on an artifact nobody edited.
ARTIFACTS = [feature_dir + "/" + n for n in
             ("spec.md", "plan.md", "tasks.md", "done-contract.md", "prd.md")]
VOIDING = [".rush/memory/constitution.md", "specs/integration-map.md"] + contract_paths()

current = {
    "artifacts": {rel: digest(rel) for rel in ARTIFACTS if digest(rel) is not None},
    "voiding": {rel: digest(rel) for rel in VOIDING if digest(rel) is not None},
}

try:
    with open(state_path, encoding="utf-8") as f:
        state = json.load(f)
except (OSError, ValueError):
    state = {}
if not isinstance(state, dict):
    state = {}

analysis = state.get("analysis")
if not isinstance(analysis, dict):
    analysis = {}
previous = analysis.get(feature_key)

if record:
    import datetime
    analysis[feature_key] = {
        "verdict": record,
        "at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "fingerprints": current,
    }
    state["analysis"] = analysis
    tmp = state_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, state_path)
    out = {"feature": feature_key, "recorded": record, "files": len(current["artifacts"])}
    print(json.dumps(out, ensure_ascii=False) if json_mode == "true"
          else "recorded %s for %s against %d artifacts" % (record, feature_key, len(current["artifacts"])))
    raise SystemExit(0)

reason = None
changed = []
unchanged = []
if not isinstance(previous, dict) or not previous.get("fingerprints"):
    reason = "no previous verdict recorded for this feature"
elif previous.get("verdict") != "GO":
    reason = "previous verdict was %s, not GO" % previous.get("verdict")
else:
    prev = previous["fingerprints"]
    prev_void = prev.get("voiding") or {}
    void_changed = [
        rel for rel in set(list(prev_void) + list(current["voiding"]))
        if prev_void.get(rel) != current["voiding"].get(rel)
    ]
    if void_changed:
        reason = "changed since last GO: %s" % ", ".join(sorted(void_changed))
    else:
        prev_art = prev.get("artifacts") or {}
        for rel in sorted(set(list(prev_art) + list(current["artifacts"]))):
            if prev_art.get(rel) != current["artifacts"].get(rel):
                changed.append(rel)
            else:
                unchanged.append(rel)

out = {
    "feature": feature_key,
    "previous_verdict": (previous or {}).get("verdict"),
    "previous_at": (previous or {}).get("at"),
    "full_pass_required": reason is not None,
    "full_pass_reason": reason,
    "changed": changed,
    "unchanged": unchanged,
}

if json_mode == "true":
    print(json.dumps(out, ensure_ascii=False))
else:
    print("feature: %s" % feature_key)
    print("previous verdict: %s%s" % (out["previous_verdict"] or "(none)",
                                      " at " + out["previous_at"] if out["previous_at"] else ""))
    if reason:
        print("full judgement pass required: %s" % reason)
    else:
        print("delta pass allowed")
        print("changed since last GO: %s" % (", ".join(changed) or "(nothing)"))
        print("unchanged: %s" % (", ".join(unchanged) or "(none)"))
PYEOF
exit 0

#!/usr/bin/env bash
# validate-integration-map.sh - validate the provides/consumes/depends_on
# graph in specs/integration-map.md. This is the kit's defence against
# features that don't connect.
#
# Usage: validate-integration-map.sh [--json]
#
# Exit 0 no errors, 1 violations found, 2 usage/internal error.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: validate-integration-map.sh [--json]

Parses the fenced ```json block of specs/integration-map.md (shape:
features[] with id/provides/consumes/depends_on, optional
shared_contracts[], journeys[]) and validates the graph between
features.

Detects: consume_without_provider, duplicate_provider, dependency_cycle,
journey_missing_feature, journey_without_test, unknown_feature_ref.

Prints a topological "order" array over depends_on: a safe implementation
order (dependencies before their dependents).

  --json       Print a single JSON object on stdout, nothing else.
  -h, --help   Show this help.

Exit codes: 0 ok, 1 violations found, 2 usage/internal error.
EOF
}

json_mode="false"
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true" ;;
    *) echo "validate-integration-map.sh: unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

root="$(rush_root)" || exit 2
map_file="$root/specs/integration-map.md"

if [ ! -f "$map_file" ]; then
  # A missing map is only a problem once features exist. A fresh project has nothing to
  # connect yet, and reporting an internal error there would make doctor.sh cry wolf on
  # every clean install.
  # Features are nested one level under their spec: specs/<spec-id>/<feature-id>/.
  # A spec dir with only pitch.md/prd.md (no features split out yet) has
  # nothing to connect, so it must not count here.
  feature_count=0
  if [ -d "$root/specs" ]; then
    for sd in "$root"/specs/*/; do
      [ -d "$sd" ] || continue
      case "$(basename "$sd")" in
        shared-contracts) continue ;;
      esac
      for fd in "$sd"*/; do
        [ -d "$fd" ] || continue
        feature_count=$((feature_count + 1))
      done
    done
  fi
  if [ "$feature_count" -eq 0 ]; then
    if [ "$json_mode" = "true" ]; then
      printf '{"ok": true, "features": 0, "journeys": 0, "violations": [], "order": [], "note": "no integration map yet and no features to connect"}\n'
    else
      echo "no features yet — nothing to validate" >&2
    fi
    exit 0
  fi
  if [ "$json_mode" = "true" ]; then
    printf '{"ok": false, "features": %d, "journeys": 0, "violations": [{"rule": "missing_integration_map", "detail": "%d feature(s) exist under specs/ but specs/integration-map.md is missing — features have no declared provides/consumes", "severity": "error"}], "order": []}\n' "$feature_count" "$feature_count"
  else
    echo "ERROR: $feature_count feature(s) exist but specs/integration-map.md is missing" >&2
    echo "  run /rush-features to declare what each feature provides and consumes" >&2
  fi
  exit 1
fi

result_file="$(mktemp)"
trap 'rm -f "$result_file"' EXIT

set +e
"$(rush_python)" - "$map_file" > "$result_file" <<'PYEOF'
import json, re, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()

m = re.search(r"```json\s*\n(.*?)```", text, re.DOTALL)
if not m:
    print(json.dumps({"error": "no fenced json block found in integration-map.md"}), file=sys.stderr)
    sys.exit(2)

try:
    data = json.loads(m.group(1))
except Exception as e:
    print(json.dumps({"error": "fenced json block does not parse: %s" % e}), file=sys.stderr)
    sys.exit(2)

if not isinstance(data, dict) or "features" not in data:
    print(json.dumps({"error": "integration map json must have a 'features' array"}), file=sys.stderr)
    sys.exit(2)

features_list = data.get("features") or []
if not isinstance(features_list, list):
    print(json.dumps({"error": "'features' must be an array"}), file=sys.stderr)
    sys.exit(2)

shared_contracts = data.get("shared_contracts") or []
journeys = data.get("journeys") or []

features = {}
for f in features_list:
    fid = f.get("id")
    if fid:
        features[fid] = f
known_ids = set(features.keys())

violations = []

def add(rule, feature, detail, severity="error"):
    violations.append({"rule": rule, "feature": feature, "detail": detail, "severity": severity})

def entry_key(e):
    return (e.get("kind"), e.get("name"))

# --- duplicate_provider -----------------------------------------------------
provider_of = {}  # (kind,name) -> [feature ids]
for fid, fdef in features.items():
    for p in (fdef.get("provides") or []):
        provider_of.setdefault(entry_key(p), []).append(fid)

for key, providers in provider_of.items():
    if len(providers) > 1:
        add("duplicate_provider", ", ".join(sorted(providers)),
            "%s '%s' is provided by more than one feature: %s" % (key[0], key[1], ", ".join(sorted(providers))))

# --- consume_without_provider + unknown_feature_ref (via 'from') -----------
for fid, fdef in features.items():
    for c in (fdef.get("consumes") or []):
        frm = c.get("from")
        key = entry_key(c)
        if not frm:
            add("consume_without_provider", fid,
                "consumes %s '%s' without declaring 'from' (which feature provides it)" % (key[0], key[1]))
            continue
        if frm not in known_ids:
            add("unknown_feature_ref", fid,
                "consumes %s '%s' 'from' unknown feature '%s'" % (key[0], key[1], frm))
            continue
        provider_provides = {entry_key(p) for p in (features[frm].get("provides") or [])}
        if key not in provider_provides:
            add("consume_without_provider", fid,
                "consumes %s '%s' from '%s', which does not provide it" % (key[0], key[1], frm))

# --- unknown_feature_ref via depends_on --------------------------------------
for fid, fdef in features.items():
    for dep in (fdef.get("depends_on") or []):
        if dep not in known_ids:
            add("unknown_feature_ref", fid,
                "depends_on references unknown feature '%s'" % dep)

# --- dependency_cycle over depends_on ----------------------------------------
edges = {fid: set(d for d in (features[fid].get("depends_on") or []) if d in known_ids) for fid in features}

WHITE, GRAY, BLACK = 0, 1, 2
color = {fid: WHITE for fid in features}
cycle_reported = set()

def dfs_cycle(node, stack):
    color[node] = GRAY
    stack.append(node)
    for nxt in sorted(edges.get(node, [])):
        if color.get(nxt, WHITE) == WHITE:
            if dfs_cycle(nxt, stack):
                return True
        elif color.get(nxt) == GRAY:
            idx = stack.index(nxt)
            cyc = stack[idx:] + [nxt]
            key = tuple(sorted(set(cyc)))
            if key not in cycle_reported:
                cycle_reported.add(key)
                add("dependency_cycle", " -> ".join(cyc), "dependency cycle: %s" % " -> ".join(cyc))
            return True
    stack.pop()
    color[node] = BLACK
    return False

for fid in sorted(features):
    if color[fid] == WHITE:
        dfs_cycle(fid, [])

# --- shared_contracts owner must be a known feature --------------------------
for sc in shared_contracts:
    owner = sc.get("owner")
    name = sc.get("name") or sc.get("path") or "<unnamed shared contract>"
    if not owner:
        add("unknown_feature_ref", name, "shared_contracts entry '%s' has no 'owner'" % name)
    elif owner not in known_ids:
        add("unknown_feature_ref", name, "shared_contracts entry '%s' has unknown owner '%s'" % (name, owner))

# --- journeys ------------------------------------------------------------------
for j in journeys:
    jname = j.get("id") or j.get("name") or "<unnamed journey>"
    jfeatures = j.get("features") or []
    for fid in jfeatures:
        if fid not in known_ids:
            add("unknown_feature_ref", fid, "journey '%s' references unknown feature '%s'" % (jname, fid))
    if not j.get("test"):
        add("journey_without_test", jname, "journey '%s' has no 'test' field" % jname)
    jf_known = [fid for fid in jfeatures if fid in known_ids]
    jf_set = set(jf_known)
    for fid in jf_known:
        for dep in (features[fid].get("depends_on") or []):
            if dep in known_ids and dep not in jf_set:
                add("journey_missing_feature", jname,
                    "journey '%s' includes '%s' which depends_on '%s', not listed in the journey" % (jname, fid, dep))

# --- topological order (Kahn's algorithm) over depends_on: a dependency
# comes before its dependent. Deterministic tie-break by feature id.
indegree = {fid: len(edges.get(fid, set())) for fid in features}
adj = {fid: set() for fid in features}  # dependency -> dependents
for fid, deps in edges.items():
    for dep in deps:
        adj[dep].add(fid)

import heapq
order = []
heap = sorted([fid for fid, d in indegree.items() if d == 0])
heapq.heapify(heap)
remaining = dict(indegree)
visited = set()
while heap:
    node = heapq.heappop(heap)
    if node in visited:
        continue
    visited.add(node)
    order.append(node)
    for nxt in sorted(adj.get(node, [])):
        remaining[nxt] -= 1
        if remaining[nxt] == 0 and nxt not in visited:
            heapq.heappush(heap, nxt)
for fid in sorted(features):
    if fid not in visited:
        order.append(fid)

ok = not any(v["severity"] == "error" for v in violations)
out = {
    "ok": ok,
    "features": len(features),
    "journeys": len(journeys),
    "violations": violations,
    "order": order,
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
print("features: %d, journeys: %d" % (data["features"], data["journeys"]))
if not data["violations"]:
    print("OK: graph is consistent")
else:
    for v in data["violations"]:
        print("[%s] %s (feature: %s)" % (v["rule"], v["detail"], v["feature"]))
    print("%d violation(s)" % len(data["violations"]))
print("order: %s" % ", ".join(data["order"]))
PYEOF
fi

ok="$("$(rush_python)" -c "import json,sys; print(json.loads(sys.argv[1])['ok'])" "$payload")"
if [ "$ok" = "True" ]; then
  exit 0
else
  exit 1
fi

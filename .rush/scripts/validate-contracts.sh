#!/usr/bin/env bash
# validate-contracts.sh - parse and validate contract files under
# specs/*/contracts/ and specs/shared-contracts/: OpenAPI (JSON or simple
# YAML), JSON Schema, AsyncAPI. Checks that files parse, that local $ref
# pointers resolve, and that shared contracts declare an owner that exists
# in the integration map.
#
# Usage: validate-contracts.sh [<feature-id>|--all] [--json]
#
# Exit 0 ok, 1 invalid contract found, 2 usage/internal error.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: validate-contracts.sh [<feature-id>|--all] [--json]

Parses contract files under specs/<feature-id>/contracts/ (or every
feature's contracts/ with --all, which is also the default) plus
specs/shared-contracts/.

Recognises OpenAPI (has an "openapi" key), AsyncAPI (has an "asyncapi"
key), and JSON Schema (has "$schema" or a "type"/"properties" pair).
Files may be JSON or YAML. If PyYAML is not installed, YAML files are
reported as skipped_no_yaml (not a failure) while JSON files still get
fully validated.

Validates: the file parses; local $ref pointers (internal '#/...' and
relative file refs) resolve; every contract under specs/shared-contracts/
has an owner that names a feature which exists in specs/integration-map.md.
The owner is looked up from integration-map.md's shared_contracts[] entry
matching this file's path (or, failing that, an inline "owner"/"x-owner"
field in the contract file itself).

  --json       Print a single JSON object on stdout, nothing else.
  -h, --help   Show this help.

Exit codes: 0 ok, 1 invalid contract(s) found, 2 usage/internal error.
EOF
}

json_mode="false"
target="--all"
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true" ;;
    --all) target="--all" ;;
    -*) echo "validate-contracts.sh: unknown option: $arg" >&2; usage >&2; exit 2 ;;
    *) target="$arg" ;;
  esac
done

root="$(rush_root)" || exit 2

result_file="$(mktemp)"
trap 'rm -f "$result_file"' EXIT

set +e
"$(rush_python)" - "$root" "$target" > "$result_file" <<'PYEOF'
import json, os, re, sys

root, target = sys.argv[1], sys.argv[2]

try:
    import yaml  # type: ignore
    HAVE_YAML = True
except Exception:
    HAVE_YAML = False


def feature_dirs():
    specs = os.path.join(root, "specs")
    if not os.path.isdir(specs):
        return []
    out = []
    for name in sorted(os.listdir(specs)):
        if os.path.isdir(os.path.join(specs, name)) and re.match(r"^\d{3}-", name):
            out.append(name)
    return out


if target == "--all":
    fids = feature_dirs()
else:
    fdir = os.path.join(root, "specs", target)
    if not os.path.isdir(fdir):
        matches = [n for n in feature_dirs() if n.startswith(target)]
        if len(matches) != 1:
            print(json.dumps({"error": "no feature matching '%s'" % target}), file=sys.stderr)
            sys.exit(2)
        target = matches[0]
    fids = [target]

contract_dirs = []
for fid in fids:
    d = os.path.join(root, "specs", fid, "contracts")
    if os.path.isdir(d):
        contract_dirs.append((d, "specs/%s/contracts" % fid, False))
shared_dir = os.path.join(root, "specs", "shared-contracts")
if os.path.isdir(shared_dir):
    contract_dirs.append((shared_dir, "specs/shared-contracts", True))

def load_integration_map():
    """Return (known_feature_ids or None, shared_contract_owner_by_path dict)."""
    p = os.path.join(root, "specs", "integration-map.md")
    if not os.path.isfile(p):
        return None, {}
    with open(p, encoding="utf-8") as f:
        text = f.read()
    m = re.search(r"```json\s*\n(.*?)```", text, re.DOTALL)
    if not m:
        return None, {}
    try:
        data = json.loads(m.group(1))
    except Exception:
        return None, {}
    feats = data.get("features") or []
    ids = [f.get("id") for f in feats if isinstance(f, dict) and f.get("id")]
    owners = {}
    for sc in (data.get("shared_contracts") or []):
        if not isinstance(sc, dict):
            continue
        owner = sc.get("owner")
        for key_field in ("path", "name"):
            v = sc.get(key_field)
            if v:
                owners[v] = owner
                owners[os.path.basename(str(v))] = owner
    return ids, owners

known_features, shared_owner_by_key = load_integration_map()

files = []
for d, rel_dir, is_shared in contract_dirs:
    for name in sorted(os.listdir(d)):
        p = os.path.join(d, name)
        if not os.path.isfile(p):
            continue
        if not name.lower().endswith((".json", ".yaml", ".yml")):
            continue
        files.append((p, "%s/%s" % (rel_dir, name), is_shared))

violations = []
skipped = []
checked = []

def add(rel, rule, message, severity="error"):
    violations.append({"file": rel, "rule": rule, "message": message, "severity": severity})

def parse_file(p, rel):
    is_yaml = rel.lower().endswith((".yaml", ".yml"))
    with open(p, encoding="utf-8") as f:
        raw = f.read()
    if is_yaml:
        if not HAVE_YAML:
            skipped.append({"file": rel, "reason": "skipped_no_yaml"})
            return None
        try:
            return yaml.safe_load(raw)
        except Exception as e:
            add(rel, "parse_error", "YAML does not parse: %s" % e)
            return None
    else:
        try:
            return json.loads(raw)
        except Exception as e:
            add(rel, "parse_error", "JSON does not parse: %s" % e)
            return None

def contract_kind(doc):
    if not isinstance(doc, dict):
        return "unknown"
    if "openapi" in doc:
        return "openapi"
    if "asyncapi" in doc:
        return "asyncapi"
    if "$schema" in doc or ("type" in doc and "properties" in doc):
        return "jsonschema"
    return "unknown"

def resolve_pointer(doc, pointer):
    if pointer in ("", "/"):
        return doc
    parts = pointer.lstrip("#").lstrip("/").split("/")
    cur = doc
    for part in parts:
        part = part.replace("~1", "/").replace("~0", "~")
        if isinstance(cur, dict):
            if part not in cur:
                return None, False
            cur = cur[part]
        elif isinstance(cur, list):
            try:
                idx = int(part)
            except ValueError:
                return None, False
            if idx < 0 or idx >= len(cur):
                return None, False
            cur = cur[idx]
        else:
            return None, False
    return cur, True

def walk_refs(node, path=""):
    if isinstance(node, dict):
        if "$ref" in node and isinstance(node["$ref"], str):
            yield node["$ref"]
        for k, v in node.items():
            yield from walk_refs(v, path + "/" + str(k))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from walk_refs(v, path + "/%d" % i)

def check_refs(doc, rel, p):
    base_dir = os.path.dirname(p)
    for ref in walk_refs(doc):
        if ref.startswith("http://") or ref.startswith("https://"):
            continue  # remote refs out of scope (no network)
        if ref.startswith("#"):
            _, ok = resolve_pointer(doc, ref)
            if not ok:
                add(rel, "unresolved_ref", "internal $ref does not resolve: %s" % ref)
            continue
        # relative file ref, optionally with a #/pointer suffix
        file_part, _, pointer_part = ref.partition("#")
        target_path = os.path.normpath(os.path.join(base_dir, file_part))
        if not os.path.isfile(target_path):
            add(rel, "unresolved_ref", "$ref target file not found: %s" % ref)
            continue
        if pointer_part:
            try:
                if target_path.lower().endswith((".yaml", ".yml")):
                    if not HAVE_YAML:
                        continue
                    with open(target_path, encoding="utf-8") as f:
                        target_doc = yaml.safe_load(f.read())
                else:
                    with open(target_path, encoding="utf-8") as f:
                        target_doc = json.load(f)
            except Exception:
                add(rel, "unresolved_ref", "$ref target file does not parse: %s" % ref)
                continue
            _, ok = resolve_pointer(target_doc, "#" + pointer_part)
            if not ok:
                add(rel, "unresolved_ref", "$ref pointer not found in target file: %s" % ref)

for p, rel, is_shared in files:
    checked.append(rel)
    doc = parse_file(p, rel)
    if doc is None:
        continue
    kind = contract_kind(doc)
    check_refs(doc, rel, p)
    if is_shared:
        # Primary source of truth: specs/integration-map.md's shared_contracts[]
        # registry (matched by path, falling back to basename). An inline
        # "owner"/"x-owner" field in the contract file itself is accepted too,
        # for tooling that prefers to self-declare, but the registry is what
        # rush-contracts is instructed to maintain.
        registry_owner = shared_owner_by_key.get(rel) or shared_owner_by_key.get(os.path.basename(rel))
        inline_owner = (doc.get("owner") or doc.get("x-owner")) if isinstance(doc, dict) else None
        owner = registry_owner or inline_owner
        if not owner:
            add(rel, "missing_owner",
                "not registered with an owner in specs/integration-map.md -> shared_contracts[], "
                "and no inline 'owner'/'x-owner' field")
        elif known_features is not None:
            resolved = owner in known_features or any(f.startswith(owner) for f in known_features)
            if not resolved:
                add(rel, "unknown_owner", "owner '%s' is not a feature in integration-map.md" % owner)

ok = not any(v["severity"] == "error" for v in violations)
out = {"ok": ok, "checked": checked, "skipped": skipped, "violations": violations}
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
print("checked %d contract file(s)" % len(data["checked"]))
for s in data["skipped"]:
    print("[skipped] %s: %s" % (s["file"], s["reason"]))
if not data["violations"]:
    print("OK: no violations")
else:
    for v in data["violations"]:
        print("[%s] %s: %s (%s)" % (v["severity"], v["file"], v["message"], v["rule"]))
    print("%d violation(s)" % len(data["violations"]))
PYEOF
fi

ok="$("$(rush_python)" -c "import json,sys; print(json.loads(sys.argv[1])['ok'])" "$payload")"
if [ "$ok" = "True" ]; then
  exit 0
else
  exit 1
fi

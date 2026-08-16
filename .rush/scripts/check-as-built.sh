#!/usr/bin/env bash
# check-as-built.sh - spec-drift detection: files touched by the feature's
# commits vs files declared in plan.md, contract-declared endpoints not
# found anywhere in the source tree, and spec.md left stale across too
# many code commits.
#
# Usage: check-as-built.sh <feature-id> [--json]
#
# Exit 0 no drift, 1 drift found, 2 usage/internal error.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: check-as-built.sh <feature-id> [--json]

Compares specs/<feature-id> against what git and the contracts show:

  unplanned_file        a file touched by the feature's commits that is
                         not declared in plan.md's Files section
  endpoint_not_implemented
                         a "METHOD /path" declared in
                         specs/<feature-id>/contracts/*.json that no file
                         under the project (outside specs/ and .rush/)
                         mentions
  stale_spec             spec.md has not been touched in the last N code
                         commits (config.json -> verification.stale_spec_commits,
                         default 10)

A commit is considered to belong to the feature when its subject contains
the feature id (e.g. "007-checkout: add cart totals"), matching this
kit's default commit_convention/branch_pattern. Commits with no feature id
in the subject are not attributed to any feature, even if they happen to
touch specs/<feature-id>/.

  --json       Print a single JSON object on stdout, nothing else.
  -h, --help   Show this help.

Exit codes: 0 no drift, 1 drift found, 2 usage/internal error.
EOF
}

json_mode="false"
feature_id=""
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true" ;;
    -*) echo "check-as-built.sh: unknown option: $arg" >&2; usage >&2; exit 2 ;;
    *)
      if [ -n "$feature_id" ]; then
        echo "check-as-built.sh: unexpected extra argument: $arg" >&2; exit 2
      fi
      feature_id="$arg" ;;
  esac
done

if [ -z "$feature_id" ]; then
  echo "check-as-built.sh: <feature-id> is required" >&2
  usage >&2
  exit 2
fi

root="$(rush_root)" || exit 2

result_file="$(mktemp)"
trap 'rm -f "$result_file"' EXIT

set +e
"$(rush_python)" - "$root" "$feature_id" > "$result_file" <<'PYEOF'
import json, os, re, subprocess, sys

root, feature_id = sys.argv[1], sys.argv[2]

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

def load_config():
    try:
        with open(os.path.join(root, ".rush", "config.json")) as f:
            return json.load(f)
    except Exception:
        return {}

cfg = load_config()
try:
    stale_threshold = int(((cfg.get("verification") or {}).get("stale_spec_commits")) or 10)
except Exception:
    stale_threshold = 10

def git(*args):
    try:
        p = subprocess.run(["git"] + list(args), cwd=root, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
        if p.returncode != 0:
            return None
        return p.stdout
    except Exception:
        return None

is_git = git("rev-parse", "--is-inside-work-tree") is not None

drift = []

def add(kind, detail):
    drift.append({"kind": kind, "detail": detail})

feature_dir_rel = "specs/%s" % fid

# --- files touched by the feature's commits -------------------------------
feature_files = set()
if is_git:
    log = git("log", "--format=%H\x1f%s", "--name-only") or ""
    commits = []
    cur_hash = None
    cur_subject = None
    cur_files = []
    for line in log.split("\n"):
        if "\x1f" in line:
            if cur_hash is not None:
                commits.append((cur_hash, cur_subject, cur_files))
            cur_hash, cur_subject = line.split("\x1f", 1)
            cur_files = []
        elif line.strip():
            cur_files.append(line.strip())
    if cur_hash is not None:
        commits.append((cur_hash, cur_subject, cur_files))

    def belongs_to_feature(subject, files):
        # Subject-only on purpose: config.default.json's branch_pattern
        # ("feat/NNN-slug") and commit_convention ("conventional") both
        # assume commit subjects carry the feature id/scope. Falling back
        # to "touches specs/<id>/" would misattribute any commit that
        # bundles spec-writing with unrelated files (e.g. a first bootstrap
        # commit) to every feature it happens to touch.
        return fid in subject

    for h, subject, files in commits:
        if belongs_to_feature(subject, files):
            for f in files:
                if f.startswith("specs/") or f.startswith(".rush/"):
                    continue
                feature_files.add(f)

# --- plan.md declared files -------------------------------------------------
plan_path = os.path.join(root, feature_dir_rel, "plan.md")
declared = set()
if os.path.isfile(plan_path):
    with open(plan_path, encoding="utf-8") as f:
        plan_text = f.read()
    m = re.search(r"^#{1,6}\s*Files.*?\n(.*?)(?=^#{1,6}\s|\Z)", plan_text, re.DOTALL | re.MULTILINE | re.IGNORECASE)
    if m:
        for line in m.group(1).split("\n"):
            if not re.match(r"\s*[-*]\s", line):
                continue
            # Prefer an inline-code span ("- `path/to/file.ts` — why"), the
            # shape plan-template.md uses; fall back to the first bare
            # path-like token on the bullet.
            cm = re.search(r"`([^`]+)`", line)
            if cm:
                declared.add(cm.group(1).strip())
                continue
            bm = re.match(r"\s*[-*]\s+(\S+)", line)
            if bm:
                declared.add(bm.group(1).strip())

def is_declared(path):
    for d in declared:
        if path == d or path.startswith(d.rstrip("/") + "/"):
            return True
    return False

for f in sorted(feature_files):
    if not is_declared(f):
        add("unplanned_file", "%s is not listed in plan.md" % f)

# --- contract-declared endpoints not found in source ------------------------
contracts_dir = os.path.join(root, feature_dir_rel, "contracts")
endpoints = []
if os.path.isdir(contracts_dir):
    for name in sorted(os.listdir(contracts_dir)):
        if not name.lower().endswith(".json"):
            continue
        p = os.path.join(contracts_dir, name)
        try:
            with open(p, encoding="utf-8") as f:
                doc = json.load(f)
        except Exception:
            continue
        if isinstance(doc, dict) and "openapi" in doc:
            for path_, methods in (doc.get("paths") or {}).items():
                if not isinstance(methods, dict):
                    continue
                for method in methods:
                    if method.upper() in ("GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"):
                        endpoints.append("%s %s" % (method.upper(), path_))
        elif isinstance(doc, dict) and "asyncapi" in doc:
            for chan in (doc.get("channels") or {}):
                endpoints.append(chan)

def search_repo_for(token, exclude_dirs):
    if is_git:
        out = subprocess.run(
            ["git", "grep", "-l", "-F", token],
            cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        if out.returncode in (0, 1):
            files = [f for f in out.stdout.split("\n") if f.strip()]
            files = [f for f in files if not any(f.startswith(e) for e in exclude_dirs)]
            return files
    # fallback: walk filesystem
    hits = []
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root)
        if rel_dir == ".":
            rel_dir = ""
        if any(rel_dir == e.rstrip("/") or rel_dir.startswith(e) for e in exclude_dirs):
            dirnames[:] = []
            continue
        if ".git" in dirnames:
            dirnames.remove(".git")
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            try:
                with open(p, "rb") as fh:
                    data = fh.read()
                if token.encode("utf-8") in data:
                    hits.append(os.path.relpath(p, root))
            except Exception:
                continue
    return hits

exclude = ["specs/", ".rush/", ".git/"]
for ep in endpoints:
    parts = ep.split(" ", 1)
    path_only = parts[1] if len(parts) == 2 else ep
    hits = search_repo_for(path_only, exclude)
    if not hits:
        add("endpoint_not_implemented", "%s declared in contracts but not referenced anywhere in the source tree" % ep)

# --- stale spec --------------------------------------------------------------
spec_path_rel = "%s/spec.md" % feature_dir_rel
if is_git:
    spec_log = git("log", "-1", "--format=%H", "--", spec_path_rel)
    last_spec_commit = (spec_log or "").strip()
    if last_spec_commit:
        since = git("log", "--format=%H", "%s..HEAD" % last_spec_commit) or ""
        code_commits_since = 0
        for h in [l for l in since.split("\n") if l.strip()]:
            files = (git("show", "--name-only", "--format=", h) or "").split("\n")
            files = [f for f in files if f.strip()]
            if any(not (f.startswith("specs/") or f.startswith(".rush/")) for f in files):
                code_commits_since += 1
        if code_commits_since >= stale_threshold:
            add("stale_spec", "spec.md has not been updated in the last %d code commit(s) (threshold: %d)" % (code_commits_since, stale_threshold))

ok = len(drift) == 0
out = {"ok": ok, "feature": fid, "drift": drift}
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
print("check-as-built: %s" % data["feature"])
if not data["drift"]:
    print("OK: no drift")
else:
    for d in data["drift"]:
        print("[%s] %s" % (d["kind"], d["detail"]))
    print("%d drift item(s)" % len(data["drift"]))
PYEOF
fi

ok="$("$(rush_python)" -c "import json,sys; print(json.loads(sys.argv[1])['ok'])" "$payload")"
if [ "$ok" = "True" ]; then
  exit 0
else
  exit 1
fi

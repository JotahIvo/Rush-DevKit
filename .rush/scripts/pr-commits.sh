#!/usr/bin/env bash
# pr-commits.sh — the factual basis for /rush-pr: every commit since a spec's directory first
# entered git history, plus the current done-check status of every feature under that spec.
#
# A PR's unit in this kit is the spec, not a single feature: several features close under one
# spec and the pull request is opened once for the lot. Reconstructing that commit range by
# hand ("git log since roughly when we started") is exactly the kind of thing that must be
# identical every time, so it lives here and not in a prompt.
#
# Feature status comes from done-check.sh, which really runs each feature's done-contract
# checks — that can take as long as the project's test suite. --no-checks skips them and
# reports done_check_ok: null, which /rush-pr already treats as "unknown, ask the user".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: pr-commits.sh <spec-id> [--no-checks] [--json]

Collects everything /rush-pr needs to describe one spec's pull request:

  - the commit range from the commit that first added specs/<spec-id>/ through HEAD,
    with each commit's sha, date, author, subject and the files it touched
  - every feature under the spec, with its done-check result and pending human gates

  <spec-id>     Spec id or unambiguous numeric prefix (e.g. 003 or 003-checkout).
  --no-checks   Do not run done-check.sh per feature; report done_check_ok as null.
                Use when the checks are slow and the caller only needs the commits.
  --json        Print a single JSON object on stdout, nothing else.
  -h, --help    Show this help and exit.

Exit codes: 0 every feature under the spec is complete (or --no-checks was given),
1 at least one feature is incomplete (failing check or pending human gate) — a valid
result, not an error, 2 usage or internal error (no git repository, unknown spec).
EOF
}

SPEC_ARG=""
RUN_CHECKS=true
JSON_OUT=false

while [ $# -gt 0 ]; do
  case "$1" in
    --no-checks) RUN_CHECKS=false; shift ;;
    --json) JSON_OUT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) rush_die "unknown option: $1" 2 ;;
    *)
      if [ -n "$SPEC_ARG" ]; then
        rush_die "unexpected extra argument: $1" 2
      fi
      SPEC_ARG="$1"; shift ;;
  esac
done

ROOT="$(rush_root)" || exit 2
PY="$(rush_python)" || exit 2
export RUSH_ROOT="$ROOT"

if [ -z "$SPEC_ARG" ]; then
  SPEC_ARG="$(rush_current_spec)" || exit 2
  if [ -z "$SPEC_ARG" ]; then
    rush_die "no <spec-id> given and no current_spec in .rush/state.json" 2
  fi
fi

SPEC_DIR="$(rush_spec_dir "$SPEC_ARG")" || exit 2
SPEC_ID="$(basename "$SPEC_DIR")"

if ! rush_have git; then
  rush_die "git not found on PATH — this script reads the project's commit history" 2
fi
if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  rush_die "$ROOT is not inside a git repository — there is no commit history to read" 2
fi

PYFILE="$(mktemp "${TMPDIR:-/tmp}/rush-pr-commits.XXXXXX")" || exit 2
trap 'rm -f "$PYFILE"' EXIT

cat > "$PYFILE" <<'PYEOF'
import json
import os
import re
import subprocess
import sys

root, spec_id, spec_dir, run_checks_flag = sys.argv[1:5]
run_checks = run_checks_flag == "1"

RS = "\x1e"  # record separator between commits
US = "\x1f"  # field separator inside a commit's header line
FEATURE_RE = re.compile(r"^\d{3}-")


def git(args):
    """Run a git command in the project root. Returns (exit_code, stdout)."""
    proc = subprocess.run(
        ["git", "-C", root] + args,
        capture_output=True, text=True,
    )
    return proc.returncode, proc.stdout


def first_commit_touching_spec():
    code, out = git(["log", "--diff-filter=A", "--format=%H", "--", spec_dir])
    if code != 0:
        return None
    shas = [line.strip() for line in out.splitlines() if line.strip()]
    return shas[-1] if shas else None


def resolve_range(first):
    """Commits from the one that created the spec directory through HEAD, inclusive.

    'first^..HEAD' excludes first's parent, not first. When first is the repository's
    root commit it has no parent, so the whole history up to HEAD is the range.
    """
    if first is None:
        return None
    code, _ = git(["rev-parse", "--verify", "--quiet", first + "^"])
    if code == 0:
        return "%s^..HEAD" % first
    return "HEAD"


def read_commits(rev_range):
    fmt = RS + "%H" + US + "%h" + US + "%aI" + US + "%an" + US + "%s"
    code, out = git(["log", "--format=" + fmt, "--name-only", rev_range])
    if code != 0:
        return []
    commits = []
    for chunk in out.split(RS):
        if not chunk.strip():
            continue
        lines = chunk.splitlines()
        header = lines[0].split(US)
        if len(header) < 5:
            continue
        sha, short, date, author, subject = header[:5]
        files = [line.strip() for line in lines[1:] if line.strip()]
        code_parents, parents_out = git(["rev-list", "--parents", "-n", "1", sha])
        is_merge = code_parents == 0 and len(parents_out.split()) > 2
        commits.append({
            "sha": sha,
            "short": short,
            "date": date,
            "author": author,
            "subject": subject,
            "files": files,
            "merge": is_merge,
        })
    return commits


def feature_ids():
    full = os.path.join(root, spec_dir)
    if not os.path.isdir(full):
        return []
    return sorted(
        name for name in os.listdir(full)
        if FEATURE_RE.match(name) and os.path.isdir(os.path.join(full, name))
    )


def done_check(node_id):
    """Run done-check.sh for one feature. Returns the feature's status dict.

    done_check_ok is deliberately tri-state: True, False, or None when the check could
    not be run at all (no done-contract yet, --no-checks, an internal failure). /rush-pr
    treats None the same as False — something to raise with the user, never to assume.
    """
    status = {
        "done_check_ok": None,
        "checks_passed": None,
        "checks_failed": None,
        "gates_pending": None,
        "note": None,
    }
    contract = os.path.join(root, spec_dir, node_id.split("/")[-1], "done-contract.md")
    if not os.path.isfile(contract):
        status["note"] = "no done-contract.md"
        return status
    if not run_checks:
        status["note"] = "not run (--no-checks)"
        return status
    script = os.path.join(root, ".rush", "scripts", "done-check.sh")
    cmd = [script, node_id, "--json"]
    if not os.access(script, os.X_OK):
        cmd = ["bash"] + cmd
    try:
        proc = subprocess.run(cmd, cwd=root, capture_output=True, text=True)
    except OSError as exc:
        status["note"] = "done-check.sh could not be run: %s" % exc
        return status
    try:
        data = json.loads(proc.stdout)
    except ValueError:
        status["note"] = "done-check.sh exited %d without parseable JSON" % proc.returncode
        return status
    summary = data.get("summary") or {}
    status["done_check_ok"] = bool(data.get("ok"))
    status["checks_passed"] = summary.get("passed")
    status["checks_failed"] = summary.get("failed")
    status["gates_pending"] = summary.get("gates_pending")
    return status


def feature_title(feature_id):
    """First '# ' heading of the feature's spec.md, when it has one."""
    path = os.path.join(root, spec_dir, feature_id, "spec.md")
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                if line.startswith("# "):
                    return line[2:].strip() or None
    except OSError:
        return None
    return None


first = first_commit_touching_spec()
rev_range = resolve_range(first)
commits = read_commits(rev_range) if rev_range else []

code_head, head_out = git(["rev-parse", "HEAD"])
head_sha = head_out.strip() if code_head == 0 else None
code_branch, branch_out = git(["rev-parse", "--abbrev-ref", "HEAD"])
branch = branch_out.strip() if code_branch == 0 else None

features = []
incomplete = 0
for fid in feature_ids():
    node_id = "%s/%s" % (spec_id, fid)
    entry = {
        "id": fid,
        "node_id": node_id,
        "dir": "%s/%s" % (spec_dir, fid),
        "title": feature_title(fid),
    }
    entry.update(done_check(node_id))
    if entry["done_check_ok"] is not True or (entry["gates_pending"] or 0) > 0:
        incomplete += 1
    features.append(entry)

# With --no-checks nothing was measured, so "incomplete" would be an artefact of not
# looking. Report it as unknown and exit 0 — the caller already treats a null
# done_check_ok per feature as something to raise with the user.
incomplete_reported = incomplete if run_checks else None

result = {
    "spec_id": spec_id,
    "spec_dir": spec_dir,
    "branch": branch,
    "range": {
        "from": first,
        "from_short": first[:7] if first else None,
        "to": head_sha,
        "rev_range": rev_range,
    },
    "commit_count": len(commits),
    "commits": commits,
    "features": features,
    "summary": {
        "features": len(features),
        "features_incomplete": incomplete_reported,
        "commits": len(commits),
        "checks_run": run_checks,
    },
}
if first is None:
    result["note"] = (
        "specs/%s/ has no commit adding it yet — nothing of this spec is in git history, "
        "so there is no commit range to report." % spec_id
    )

print(json.dumps(result, ensure_ascii=False))
sys.exit(1 if (run_checks and incomplete) else 0)
PYEOF

set +e
OUT="$("$PY" "$PYFILE" "$ROOT" "$SPEC_ID" "$SPEC_DIR" \
  "$([ "$RUN_CHECKS" = true ] && echo 1 || echo 0)")"
RC=$?
set -e

if [ "$RC" -gt 1 ]; then
  rush_die "pr-commits.sh: internal failure collecting commits for $SPEC_ID" 2
fi

if [ "$JSON_OUT" = true ]; then
  printf '%s\n' "$OUT"
  exit "$RC"
fi

"$PY" -c "
import json, sys
d = json.loads(sys.argv[1])
print('spec:     %s (%s)' % (d['spec_id'], d['spec_dir']))
if d.get('note'):
    print('note:     %s' % d['note'])
r = d['range']
print('range:    %s..%s (%d commits)' % (r['from_short'] or '-', (r['to'] or '')[:7] or '-', d['commit_count']))
inc = d['summary']['features_incomplete']
if inc is None:
    print('features: %d, completeness not checked (--no-checks)' % d['summary']['features'])
else:
    print('features: %d, %d incomplete' % (d['summary']['features'], inc))
for f in d['features']:
    ok = f['done_check_ok']
    label = 'done' if ok is True else ('INCOMPLETE' if ok is False else 'unknown')
    extra = f[\"note\"] or ''
    gates = f['gates_pending']
    if gates:
        extra = ('%s; %d gate(s) pending' % (extra, gates)).strip('; ')
    print('  - %-28s %-11s %s' % (f['id'], label, extra))
" "$OUT"

exit "$RC"

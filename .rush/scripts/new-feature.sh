#!/usr/bin/env bash
# new-feature.sh - create specs/<spec-id>/MMM-<slug>/ (a FEATURE, nested
# under its parent spec) from .rush/templates/, register it in
# .rush/state.json, and make it the current feature. Idempotent: an
# existing slug under that spec returns its directory without
# overwriting anything.
#
# A feature is a deliverable unit split out of a spec by /rush-features
# (or written directly for a spec with only one feature). It always lives
# inside its spec's own directory - never as a sibling under specs/ - and
# its id is numbered independently starting at 001 within that spec, the
# same way task ids restart inside each feature's tasks.md.
#
# The spec itself must already exist: create it first with new-spec.sh.
#
# Usage: new-feature.sh <spec-id> <slug> [--title "..."] [--json]
#
# Exit 0 ok (created or already existed), 2 usage/internal error.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: new-feature.sh <spec-id> <slug> [--title "..."] [--json]

Creates specs/<spec-id>/MMM-<slug>/ (MMM is the next sequential 3-digit
id *within that spec*; a different spec numbers its own features
starting at 001 too), copying spec.md, plan.md, tasks.md,
done-contract.md and progress.md from .rush/templates/ (only the ones
that exist there are copied), with {{FEATURE_ID}}, {{FEATURE_TITLE}} and
{{DATE}} substituted. Registers the feature in .rush/state.json
(current_spec, current_feature, features[] - each record carries the
owning spec_id).

<spec-id> may be a full id or a numeric prefix (resolved the same way
feature ids are, via rush_spec_dir) and must already exist - run
new-spec.sh first if it doesn't.

Idempotent: if specs/<spec-id>/MMM-<slug>/ already exists for this slug,
it is returned as-is (already_existed: true, created: []) - existing
artifacts are never overwritten. current_spec/current_feature are still
updated to point at it, since re-running this is how you switch the
active feature.

  <spec-id>     The parent spec's id or numeric prefix, e.g. "001".
  <slug>        Kebab-case feature name, e.g. "login-google". Normalised
                (lowercased, non [a-z0-9-] characters become '-') if not
                already in that shape.
  --title "..." Human title for the feature. Defaults to the slug with
                hyphens turned into spaces and each word capitalised.
  --json        Print a single JSON object on stdout, nothing else.
  -h, --help    Show this help.

Exit codes: 0 ok, 2 usage/internal error.
EOF
}

json_mode="false"
title_arg=""
title_given="false"
spec_id_raw=""
slug_raw=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true"; shift ;;
    --title)
      [ "$#" -ge 2 ] || { echo "new-feature.sh: --title requires a value" >&2; exit 2; }
      title_arg="$2"; title_given="true"; shift 2 ;;
    -*) echo "new-feature.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [ -z "$spec_id_raw" ]; then
        spec_id_raw="$1"; shift
      elif [ -z "$slug_raw" ]; then
        slug_raw="$1"; shift
      else
        echo "new-feature.sh: unexpected extra argument: $1" >&2; exit 2
      fi
      ;;
  esac
done

if [ -z "$spec_id_raw" ] || [ -z "$slug_raw" ]; then
  echo "new-feature.sh: <spec-id> and <slug> are both required" >&2
  usage >&2
  exit 2
fi

root="$(rush_root)" || exit 2
py="$(rush_python)" || exit 2
lib="${RUSH_LIB_DIR:-$root/.rush/scripts/lib}/rushlib.py"
date_str="$(date +%Y-%m-%d)"

spec_dir_rel="$(rush_spec_dir "$spec_id_raw")" || exit 2
spec_id="$(basename "$spec_dir_rel")"

result_file="$(mktemp)"
py_src="$(mktemp "${TMPDIR:-/tmp}/rush-newfeature.XXXXXX.py")"
trap 'rm -f "$result_file" "$py_src"' EXIT
cat > "$py_src" <<'PYEOF'
import json, os, re, sys

root, spec_dir_rel, spec_id, slug_raw, title_arg, title_given, date_str = sys.argv[1:8]
title_given = title_given == "true"

slug = re.sub(r"[^a-z0-9-]+", "-", slug_raw.strip().lower())
slug = re.sub(r"-{2,}", "-", slug).strip("-")
if not slug:
    print("new-feature.sh: slug '%s' has no usable characters after normalisation" % slug_raw, file=sys.stderr)
    sys.exit(2)

if title_given:
    title = title_arg
else:
    title = " ".join(w.capitalize() for w in slug.split("-") if w)

spec_abs = os.path.join(root, spec_dir_rel)
if not os.path.isdir(spec_abs):
    print("new-feature.sh: spec directory %s does not exist" % spec_dir_rel, file=sys.stderr)
    sys.exit(2)

existing = None
next_num = 1
for name in sorted(os.listdir(spec_abs)):
    full = os.path.join(spec_abs, name)
    if not os.path.isdir(full):
        continue
    m = re.match(r"^(\d{3})-(.+)$", name)
    if not m:
        continue
    num, existing_slug = int(m.group(1)), m.group(2)
    if num + 1 > next_num:
        next_num = num + 1
    if existing_slug == slug:
        existing = name

already_existed = existing is not None
if already_existed:
    feature_id = existing
    if not title_given:
        state_path = os.path.join(root, ".rush", "state.json")
        try:
            with open(state_path, encoding="utf-8") as f:
                state = json.load(f)
            for rec in state.get("features") or []:
                if isinstance(rec, dict) and rec.get("id") == feature_id and rec.get("spec_id") == spec_id and rec.get("title"):
                    title = rec["title"]
                    break
        except (OSError, json.JSONDecodeError):
            pass
else:
    feature_id = "%03d-%s" % (next_num, slug)

feature_dir_abs = os.path.join(spec_abs, feature_id)
os.makedirs(feature_dir_abs, exist_ok=True)

created = []
if not already_existed:
    templates_dir = os.path.join(root, ".rush", "templates")
    template_map = [
        ("spec-template.md", "spec.md"),
        ("plan-template.md", "plan.md"),
        ("tasks-template.md", "tasks.md"),
        ("done-contract-template.md", "done-contract.md"),
        ("progress-template.md", "progress.md"),
    ]
    for template_name, dest_name in template_map:
        src = os.path.join(templates_dir, template_name)
        if not os.path.isfile(src):
            continue
        with open(src, encoding="utf-8") as f:
            text = f.read()
        text = text.replace("{{FEATURE_ID}}", feature_id)
        text = text.replace("{{FEATURE_TITLE}}", title)
        text = text.replace("{{DATE}}", date_str)
        dest = os.path.join(feature_dir_abs, dest_name)
        with open(dest, "w", encoding="utf-8") as f:
            f.write(text)
        created.append(dest_name)

out = {
    "spec_id": spec_id,
    "feature_id": feature_id,
    "dir": "%s/%s" % (spec_dir_rel, feature_id),
    "title": title,
    "slug": slug,
    "created": created,
    "already_existed": already_existed,
}
print(json.dumps(out, ensure_ascii=False))
PYEOF

set +e
"$py" "$py_src" "$root" "$spec_dir_rel" "$spec_id" "$slug_raw" "$title_arg" "$title_given" "$date_str" > "$result_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
  cat "$result_file" >&2 2>/dev/null || true
  exit 2
fi

payload="$(cat "$result_file")"

feature_id="$("$py" -c "import json,sys; print(json.loads(sys.argv[1])['feature_id'])" "$payload")"
feature_dir="$("$py" -c "import json,sys; print(json.loads(sys.argv[1])['dir'])" "$payload")"
title="$("$py" -c "import json,sys; print(json.loads(sys.argv[1])['title'])" "$payload")"
already_existed="$("$py" -c "import json,sys; print(json.loads(sys.argv[1])['already_existed'])" "$payload")"

state="$root/.rush/state.json"

spec_id_json="$("$py" -c "import json,sys; print(json.dumps(sys.argv[1]))" "$spec_id")"
feature_id_json="$("$py" -c "import json,sys; print(json.dumps(sys.argv[1]))" "$feature_id")"
"$py" "$lib" json-set "$state" current_spec "$spec_id_json" || exit 2
"$py" "$lib" json-set "$state" current_feature "$feature_id_json" || exit 2

feature_record_file="$(mktemp)"
trap 'rm -f "$result_file" "$py_src" "$feature_record_file"' EXIT
"$py" -c "
import json, sys
spec_id, feature_id, feature_dir, title = sys.argv[1:5]
print(json.dumps({'id': feature_id, 'spec_id': spec_id, 'dir': feature_dir, 'title': title}))
" "$spec_id" "$feature_id" "$feature_dir" "$title" > "$feature_record_file"
feature_record="$(cat "$feature_record_file")"
# Dedup by 'dir', not 'id': feature ids restart at 001 inside every spec on
# purpose, so "001-..." from two different specs is an expected collision on
# 'id' alone. 'dir' (specs/<spec-id>/<feature-id>) is unique by construction.
"$py" "$lib" json-list-append "$state" features "$feature_record" --key dir || exit 2

if [ "$json_mode" = "true" ]; then
  printf '%s\n' "$payload"
else
  if [ "$already_existed" = "True" ]; then
    rush_info "feature '$feature_id' already existed at $feature_dir (now the current feature, spec '$spec_id')"
  else
    rush_ok "created $feature_dir"
    "$py" -c "
import json, sys
d = json.loads(sys.argv[1])
for f in d['created']:
    print('  - %s/%s' % (d['dir'], f))
" "$payload"
  fi
fi

exit 0

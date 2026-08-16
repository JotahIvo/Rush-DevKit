#!/usr/bin/env bash
# new-feature.sh - create specs/NNN-<slug>/ from .rush/templates/, register
# it in .rush/state.json, and make it the current feature. Idempotent: an
# existing slug returns its directory without overwriting anything.
#
# Usage: new-feature.sh <slug> [--title "..."] [--json]
#
# Exit 0 ok (created or already existed), 2 usage/internal error.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: new-feature.sh <slug> [--title "..."] [--json]

Creates specs/NNN-<slug>/ (NNN is the next sequential 3-digit id),
copying spec.md, plan.md, tasks.md, done-contract.md and progress.md
from .rush/templates/ (only the ones that exist there are copied), with
{{FEATURE_ID}}, {{FEATURE_TITLE}} and {{DATE}} substituted. Registers
the feature in .rush/state.json (current_feature, features[]).

Idempotent: if a specs/NNN-<slug>/ directory already exists for this
slug, it is returned as-is (already_existed: true, created: []) -
existing artifacts are never overwritten. current_feature is still
updated to point at it, since re-running this is how you switch the
active feature.

  <slug>        Kebab-case feature name, e.g. "checkout". Normalised
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
      if [ -n "$slug_raw" ]; then
        echo "new-feature.sh: unexpected extra argument: $1" >&2; exit 2
      fi
      slug_raw="$1"; shift ;;
  esac
done

if [ -z "$slug_raw" ]; then
  echo "new-feature.sh: <slug> is required" >&2
  usage >&2
  exit 2
fi

root="$(rush_root)" || exit 2
py="$(rush_python)" || exit 2
lib="${RUSH_LIB_DIR:-$root/.rush/scripts/lib}/rushlib.py"
date_str="$(date +%Y-%m-%d)"

result_file="$(mktemp)"
trap 'rm -f "$result_file"' EXIT

# All the string handling (slugify, next-id, template substitution, file
# copy) happens in one Python pass, then bash uses its JSON result to
# update .rush/state.json via rushlib.py's CLI (so the atomic-write logic
# lives in one place).
set +e
"$py" - "$root" "$slug_raw" "$title_arg" "$title_given" "$date_str" > "$result_file" <<'PYEOF'
import json, os, re, sys

root, slug_raw, title_arg, title_given, date_str = sys.argv[1:6]
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

specs_dir = os.path.join(root, "specs")
os.makedirs(specs_dir, exist_ok=True)

existing = None
next_num = 1
if os.path.isdir(specs_dir):
    for name in sorted(os.listdir(specs_dir)):
        full = os.path.join(specs_dir, name)
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
    # Preserve a previously-recorded title across idempotent re-runs
    # instead of silently downgrading it to the slug-derived default
    # whenever this is called again without --title.
    if not title_given:
        state_path = os.path.join(root, ".rush", "state.json")
        try:
            with open(state_path, encoding="utf-8") as f:
                state = json.load(f)
            for rec in state.get("features") or []:
                if isinstance(rec, dict) and rec.get("id") == feature_id and rec.get("title"):
                    title = rec["title"]
                    break
        except (OSError, json.JSONDecodeError):
            pass
else:
    feature_id = "%03d-%s" % (next_num, slug)

feature_dir = os.path.join(specs_dir, feature_id)
os.makedirs(feature_dir, exist_ok=True)

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
        dest = os.path.join(feature_dir, dest_name)
        with open(dest, "w", encoding="utf-8") as f:
            f.write(text)
        created.append(dest_name)

out = {
    "feature_id": feature_id,
    "dir": "specs/%s" % feature_id,
    "title": title,
    "slug": slug,
    "created": created,
    "already_existed": already_existed,
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

feature_id="$("$py" -c "import json,sys; print(json.loads(sys.argv[1])['feature_id'])" "$payload")"
feature_dir="$("$py" -c "import json,sys; print(json.loads(sys.argv[1])['dir'])" "$payload")"
title="$("$py" -c "import json,sys; print(json.loads(sys.argv[1])['title'])" "$payload")"
already_existed="$("$py" -c "import json,sys; print(json.loads(sys.argv[1])['already_existed'])" "$payload")"

state="$root/.rush/state.json"

# Title is free text (may contain quotes, backslashes, unicode); build
# both JSON fragments with Python via argv, never by string-interpolating
# it into a Python or JSON literal by hand.
feature_id_json="$("$py" -c "import json,sys; print(json.dumps(sys.argv[1]))" "$feature_id")"
"$py" "$lib" json-set "$state" current_feature "$feature_id_json" || exit 2

feature_record="$("$py" - "$feature_id" "$feature_dir" "$title" <<'PYEOF'
import json, sys
fid, fdir, title = sys.argv[1:4]
print(json.dumps({"id": fid, "dir": fdir, "title": title}))
PYEOF
)"
"$py" "$lib" json-list-append "$state" features "$feature_record" --key id || exit 2

if [ "$json_mode" = "true" ]; then
  printf '%s\n' "$payload"
else
  if [ "$already_existed" = "True" ]; then
    rush_info "feature '$feature_id' already existed at $feature_dir (now the current feature)"
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

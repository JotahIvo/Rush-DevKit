#!/usr/bin/env bash
# new-spec.sh - create specs/NNN-<slug>/ (the PARENT unit) from
# .rush/templates/, register it in .rush/state.json, and make it the
# current spec. Idempotent: an existing slug returns its directory
# without overwriting anything.
#
# A spec is one appetite/PRD worth of product intent: pitch.md and
# prd.md live directly in it. Deliverable work is split into one or more
# FEATURES underneath it, each its own specs/<spec-id>/<feature-id>/ made
# by new-feature.sh — never a sibling of the spec.
#
# Also seeds specs/NNN-<slug>/questions.md (empty, from questions-template.md) — questions live
# per-spec now, not in one shared .rush/memory/questions.md, so every spec needs its own from the
# start.
#
# Usage: new-spec.sh <slug> [--title "..."] [--json]
#
# Exit 0 ok (created or already existed), 2 usage/internal error.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: new-spec.sh <slug> [--title "..."] [--pitch] [--minimal] [--json]

Creates specs/NNN-<slug>/ (NNN is the next sequential 3-digit id at the
top level of specs/), copying prd.md and questions.md from
.rush/templates/{prd,questions}-template.md (only the ones that exist
there are copied), with {{SPEC_ID}}/{{FEATURE_ID}},
{{SPEC_TITLE}}/{{FEATURE_TITLE}} and {{DATE}} substituted. Registers the
spec in .rush/state.json (current_spec, specs[]).

pitch.md is NOT created by default: the pitch is an optional pre-step for
an idea that is still one sentence long, and an unfilled pitch template
sitting in every spec is just a placeholder violation waiting to be
reported. Pass --pitch (which /rush-pitch does) to seed it.

Deliverable work does NOT go here directly: once the spec exists, split
it into features with new-feature.sh <spec-id> <feature-slug>, which
creates specs/NNN-<slug>/MMM-<feature-slug>/.

Idempotent: if a specs/NNN-<slug>/ directory already exists for this
slug, it is returned as-is (already_existed: true, created: []) -
existing artifacts are never overwritten. current_spec is still updated
to point at it, since re-running this is how you switch the active spec.

  <slug>        Kebab-case spec name, e.g. "autenticacao-google".
                Normalised (lowercased, non [a-z0-9-] characters become
                '-') if not already in that shape.
  --title "..." Human title for the spec. Defaults to the slug with
                hyphens turned into spaces and each word capitalised.
  --pitch       Also seed pitch.md from pitch-template.md. Only /rush-pitch
                needs this; the PRD is the flow's real entry point.
  --minimal     Seed only questions.md — no prd.md. For the M-scope path
                (/rush-quick), which needs a numbered spec to nest its one
                feature under but deliberately skips the product layer. An
                unfilled prd.md left behind by that path is a placeholder
                violation nobody will ever resolve.
  --json        Print a single JSON object on stdout, nothing else.
  -h, --help    Show this help.

Exit codes: 0 ok, 2 usage/internal error.
EOF
}

json_mode="false"
title_arg=""
title_given="false"
with_pitch="false"
minimal="false"
slug_raw=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true"; shift ;;
    --pitch) with_pitch="true"; shift ;;
    --minimal) minimal="true"; shift ;;
    --title)
      [ "$#" -ge 2 ] || { echo "new-spec.sh: --title requires a value" >&2; exit 2; }
      title_arg="$2"; title_given="true"; shift 2 ;;
    -*) echo "new-spec.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [ -n "$slug_raw" ]; then
        echo "new-spec.sh: unexpected extra argument: $1" >&2; exit 2
      fi
      slug_raw="$1"; shift ;;
  esac
done

if [ -z "$slug_raw" ]; then
  echo "new-spec.sh: <slug> is required" >&2
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
# lives in one place). Python source is a real .py file, never an inline
# heredoc-in-$( ): see the note in guard-edit.sh for why (macOS bash 3.2).
py_src="$(mktemp "${TMPDIR:-/tmp}/rush-newspec.XXXXXX.py")"
trap 'rm -f "$result_file" "$py_src"' EXIT
cat > "$py_src" <<'PYEOF'
import json, os, re, sys

root, slug_raw, title_arg, title_given, date_str, with_pitch_arg, minimal_arg = sys.argv[1:8]
with_pitch = with_pitch_arg == "true"
minimal = minimal_arg == "true"
title_given = title_given == "true"

slug = re.sub(r"[^a-z0-9-]+", "-", slug_raw.strip().lower())
slug = re.sub(r"-{2,}", "-", slug).strip("-")
if not slug:
    print("new-spec.sh: slug '%s' has no usable characters after normalisation" % slug_raw, file=sys.stderr)
    sys.exit(2)

if title_given:
    title = title_arg
else:
    title = " ".join(w.capitalize() for w in slug.split("-") if w)

specs_dir = os.path.join(root, "specs")
os.makedirs(specs_dir, exist_ok=True)

existing = None
next_num = 1
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
    spec_id = existing
    if not title_given:
        state_path = os.path.join(root, ".rush", "state.json")
        try:
            with open(state_path, encoding="utf-8") as f:
                state = json.load(f)
            for rec in state.get("specs") or []:
                if isinstance(rec, dict) and rec.get("id") == spec_id and rec.get("title"):
                    title = rec["title"]
                    break
        except (OSError, json.JSONDecodeError):
            pass
else:
    spec_id = "%03d-%s" % (next_num, slug)

spec_dir = os.path.join(specs_dir, spec_id)
os.makedirs(spec_dir, exist_ok=True)

created = []
if not already_existed:
    templates_dir = os.path.join(root, ".rush", "templates")
    template_map = [("questions-template.md", "questions.md")]
    if not minimal:
        template_map.insert(0, ("prd-template.md", "prd.md"))
    if with_pitch:
        template_map.insert(0, ("pitch-template.md", "pitch.md"))
    for template_name, dest_name in template_map:
        src = os.path.join(templates_dir, template_name)
        if not os.path.isfile(src):
            continue
        with open(src, encoding="utf-8") as f:
            text = f.read()
        # A spec's own templates address it as SPEC_*; the older FEATURE_*
        # names are still substituted so a project that customised a template
        # before this rename keeps working.
        text = text.replace("{{SPEC_ID}}", spec_id)
        text = text.replace("{{SPEC_TITLE}}", title)
        text = text.replace("{{FEATURE_ID}}", spec_id)
        text = text.replace("{{FEATURE_TITLE}}", title)
        text = text.replace("{{DATE}}", date_str)
        dest = os.path.join(spec_dir, dest_name)
        with open(dest, "w", encoding="utf-8") as f:
            f.write(text)
        created.append(dest_name)

out = {
    "spec_id": spec_id,
    "dir": "specs/%s" % spec_id,
    "title": title,
    "slug": slug,
    "created": created,
    "already_existed": already_existed,
}
print(json.dumps(out, ensure_ascii=False))
PYEOF

set +e
"$py" "$py_src" "$root" "$slug_raw" "$title_arg" "$title_given" "$date_str" "$with_pitch" "$minimal" > "$result_file"
status=$?
set -e

if [ "$status" -ne 0 ]; then
  cat "$result_file" >&2 2>/dev/null || true
  exit 2
fi

payload="$(cat "$result_file")"

spec_id="$("$py" -c "import json,sys; print(json.loads(sys.argv[1])['spec_id'])" "$payload")"
spec_dir="$("$py" -c "import json,sys; print(json.loads(sys.argv[1])['dir'])" "$payload")"
title="$("$py" -c "import json,sys; print(json.loads(sys.argv[1])['title'])" "$payload")"
already_existed="$("$py" -c "import json,sys; print(json.loads(sys.argv[1])['already_existed'])" "$payload")"

state="$root/.rush/state.json"

spec_id_json="$("$py" -c "import json,sys; print(json.dumps(sys.argv[1]))" "$spec_id")"
"$py" "$lib" json-set "$state" current_spec "$spec_id_json" || exit 2
# Switching spec resets which feature within it is "current" - an old
# current_feature pointing at a different spec's feature is worse than none.
"$py" "$lib" json-set "$state" current_feature '""' || exit 2

spec_record_file="$(mktemp)"
trap 'rm -f "$result_file" "$py_src" "$spec_record_file"' EXIT
"$py" -c "
import json, sys
spec_id, spec_dir, title = sys.argv[1:4]
print(json.dumps({'id': spec_id, 'dir': spec_dir, 'title': title}))
" "$spec_id" "$spec_dir" "$title" > "$spec_record_file"
spec_record="$(cat "$spec_record_file")"
"$py" "$lib" json-list-append "$state" specs "$spec_record" --key id || exit 2

if [ "$json_mode" = "true" ]; then
  printf '%s\n' "$payload"
else
  if [ "$already_existed" = "True" ]; then
    rush_info "spec '$spec_id' already existed at $spec_dir (now the current spec)"
  else
    rush_ok "created $spec_dir"
    "$py" -c "
import json, sys
d = json.loads(sys.argv[1])
for f in d['created']:
    print('  - %s/%s' % (d['dir'], f))
" "$payload"
  fi
  rush_info "next: new-feature.sh $spec_id <feature-slug> to split it into deliverable units"
fi

exit 0

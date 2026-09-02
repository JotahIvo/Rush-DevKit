#!/usr/bin/env bash
# update.sh — update the Rush DevKit inside a project that has already adapted itself.
#
# Usage:
#   ./update.sh <target-repo> [--dry-run] [--adopt] [--json]
#   ./update.sh <target-repo> --finalize [--json]
#
# The counterpart to install.sh, and deliberately a separate command: install refuses to touch
# what already exists, which is right the first time and useless every time after. After
# /rush-init a project owns its config.json, its memory, its specs, the eval cases /rush-retro
# wrote, sometimes a customised template — and an update has to leave all of that standing while
# still bringing the kit's own files forward.
#
# This runs from the NEW kit, against the project. That direction is not incidental: only the
# version introducing a change ships the migration that explains what that change means for a
# config written before it. An updater living inside the project would always be one version too
# old to know.
#
# What it does, in order:
#   1. Classifies every file: kit-owned, seeded-once, or the project's (see lib/kitfiles.py).
#   2. Applies everything unambiguous — new files, kit files the project never touched, files
#      the kit dropped — backing up each one first.
#   3. Merges .claude/settings.json field by field: the kit's hook entries are refreshed, the
#      project's own hooks and permissions are left alone.
#   4. Runs the config migrations for every version in the range, which tell an inherited
#      default apart from a value the project chose.
#   5. Stages, and does NOT resolve, files changed both upstream and locally. The working copy
#      stays exactly as the project left it; the three versions (base/local/new) go side by side
#      under .rush/.update/ for /rush-update to merge.
#
# Nothing under specs/, .rush/memory/, CLAUDE.md, config.json or state.json is ever written by
# this script, except the config migrations in step 4.
set -euo pipefail

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$KIT_DIR/.rush/scripts/lib/kitfiles.py"

DRY_RUN=0
ADOPT=0
JSON=0
FINALIZE=0
TARGET=""

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --dry-run) DRY_RUN=1 ;;
    --adopt) ADOPT=1 ;;
    --json) JSON=1 ;;
    --finalize) FINALIZE=1 ;;
    -*) echo "unknown option: $1" >&2; usage 2 ;;
    *) if [ -n "$TARGET" ]; then echo "unexpected argument: $1" >&2; usage 2; fi; TARGET="$1" ;;
  esac
  shift
done

[ -n "$TARGET" ] || { echo "error: target repository path is required" >&2; usage 2; }
[ -d "$TARGET" ] || { echo "error: '$TARGET' is not a directory" >&2; exit 2; }
TARGET="$(cd "$TARGET" && pwd)"
[ "$TARGET" != "$KIT_DIR" ] || { echo "error: target is the kit itself" >&2; exit 2; }
[ -d "$TARGET/.rush" ] || { echo "error: '$TARGET' has no .rush/ — use install.sh first" >&2; exit 2; }

if command -v python3 >/dev/null 2>&1; then PY=python3
elif command -v python >/dev/null 2>&1; then PY=python
else echo "error: python3 is required" >&2; exit 2; fi

FROM_VERSION="$("$PY" -c "
import json, os, sys
p = os.path.join(sys.argv[1], '.rush', 'manifest.json')
try:
    print(json.load(open(p))['kit_version'])
except Exception:
    try:
        print(open(os.path.join(sys.argv[1], '.rush', 'VERSION')).read().strip())
    except Exception:
        print('')
" "$TARGET")"
TO_VERSION="$(cat "$KIT_DIR/.rush/VERSION" 2>/dev/null || echo "")"

PENDING="$TARGET/.rush/.update/pending.json"

# --------------------------------------------------------------------- finalize

if [ "$FINALIZE" -eq 1 ]; then
  [ -f "$PENDING" ] || { echo "error: no pending update in $TARGET (.rush/.update/pending.json)" >&2; exit 2; }
  STAMP="$("$PY" -c "import json,sys;print(json.load(open(sys.argv[1]))['stamp'])" "$PENDING")"
  "$PY" "$LIB" snapshot --kit "$KIT_DIR" --target "$TARGET" --version "$TO_VERSION" >/dev/null
  rm -rf "$TARGET/.rush/.update/$STAMP" "$PENDING"
  rmdir "$TARGET/.rush/.update" 2>/dev/null || true
  if [ "$JSON" -eq 1 ]; then
    printf '{"finalized":true,"kit_version":"%s"}\n' "$TO_VERSION"
  else
    echo "Update finalised. Kit version: $TO_VERSION"
    echo "Backups from this update are kept under .rush/backups/$STAMP/ — delete when happy."
  fi
  exit 0
fi

# --------------------------------------------------------------------- dry run

if [ "$DRY_RUN" -eq 1 ]; then
  ADOPT_FLAG=""
  [ "$ADOPT" -eq 1 ] && ADOPT_FLAG="--adopt"
  set +e
  PLAN="$("$PY" "$LIB" plan --kit "$KIT_DIR" --target "$TARGET" $ADOPT_FLAG)"
  RC=$?
  set -e
  MIG="$("$PY" "$LIB" migrate --kit "$KIT_DIR" --target "$TARGET" --from "$FROM_VERSION" --to "$TO_VERSION" --dry-run)"
  if [ "$JSON" -eq 1 ]; then
    "$PY" -c "
import json, sys
print(json.dumps({'dry_run': True, 'plan': json.loads(sys.argv[1]), 'migrations': json.loads(sys.argv[2])}, ensure_ascii=False))
" "$PLAN" "$MIG"
    exit "$RC"
  fi
  "$PY" -c "
import json, sys
p = json.loads(sys.argv[1]); m = json.loads(sys.argv[2])
if p.get('error'):
    print('error: ' + p['error']); raise SystemExit(2)
print('Rush DevKit %s -> %s  (dry run, nothing written)' % (p['from_version'], p['to_version']))
s = p['summary']
print('  add %d   update %d   remove %d   conflict %d   untouched-local %d   unchanged %d'
      % (s['add'], s['update'], s['remove'], s['conflict'], s['local_only'], s['unchanged']))
for c in p['conflict']:
    how = 'agent can merge' if c['agent_mergeable'] else 'needs a human'
    print('  CONFLICT  %-52s (%s)' % (c['path'], how))
for c in m.get('changes', []):
    print('  CONFIG    %-22s %s' % (c['key'], c['action']))
" "$PLAN" "$MIG"
  exit "$RC"
fi

# --------------------------------------------------------------------- apply

ADOPT_FLAG=""
[ "$ADOPT" -eq 1 ] && ADOPT_FLAG="--adopt"

set +e
OUT="$("$PY" "$LIB" apply --kit "$KIT_DIR" --target "$TARGET" $ADOPT_FLAG)"
RC=$?
set -e
if [ "$RC" -gt 1 ]; then
  printf '%s\n' "$OUT" >&2
  exit 2
fi

MIG="$("$PY" "$LIB" migrate --kit "$KIT_DIR" --target "$TARGET" --from "$FROM_VERSION" --to "$TO_VERSION")"

STAMP="$("$PY" -c "import json,sys;print(json.loads(sys.argv[1])['applied']['stamp'])" "$OUT")"
CONFLICTS="$("$PY" -c "import json,sys;print(len(json.loads(sys.argv[1])['applied']['staged']))" "$OUT")"

mkdir -p "$TARGET/.rush/.update"
"$PY" -c "
import json, sys
out = json.loads(sys.argv[1]); mig = json.loads(sys.argv[2])
doc = {
    'stamp': out['applied']['stamp'],
    'from_version': out['plan']['from_version'],
    'to_version': out['plan']['to_version'],
    'summary': out['plan']['summary'],
    'applied': out['applied'],
    'migrations': mig,
    'notes': out['plan'].get('notes', []),
}
with open(sys.argv[3], 'w', encoding='utf-8') as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write('\n')
" "$OUT" "$MIG" "$PENDING"

# The kit's own VERSION file is copied like any other kit file, so a project with conflicts
# would otherwise claim the new version while still holding old prompts. The manifest is the
# real record, and it is only written at --finalize.

if [ "$JSON" -eq 1 ]; then
  cat "$PENDING"
else
  "$PY" -c "
import json, sys
d = json.load(open(sys.argv[1]))
a = d['applied']; s = d['summary']
print('Rush DevKit %s -> %s' % (d['from_version'], d['to_version']))
print('  written %d   removed %d   backed up %d   conflicts %d'
      % (len(a['written']), len(a['removed']), len(a['backed_up']), len(a['staged'])))
for n in d.get('notes', []):
    print('  note: ' + n)
for c in d['migrations'].get('changes', []):
    mark = '  !' if c.get('attention') else '   '
    print('%s CONFIG %-22s %s' % (mark, c['key'], c['action']))
for st in a['staged']:
    how = 'agent can merge' if st['agent_mergeable'] else 'needs a human'
    print('   CONFLICT %-52s (%s)' % (st['path'], how))
" "$PENDING"
fi

if [ "$CONFLICTS" -gt 0 ]; then
  if [ "$JSON" -eq 0 ]; then
    echo ""
    echo "$CONFLICTS file(s) changed both upstream and in this project. Their working copies are"
    echo "untouched; the three versions are staged under .rush/.update/$STAMP/."
    echo "Resolve them with /rush-update inside the project, then run:"
    echo "  $KIT_DIR/update.sh $TARGET --finalize"
  fi
  exit 1
fi

"$PY" "$LIB" snapshot --kit "$KIT_DIR" --target "$TARGET" --version "$TO_VERSION" >/dev/null
rm -f "$PENDING"
rmdir "$TARGET/.rush/.update" 2>/dev/null || true

if [ "$JSON" -eq 0 ]; then
  echo ""
  echo "No conflicts. Kit version: $TO_VERSION"
  echo "Verify with: $TARGET/.rush/scripts/doctor.sh && $TARGET/.rush/scripts/eval.sh --all"
fi
exit 0

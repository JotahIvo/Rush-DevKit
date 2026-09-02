#!/usr/bin/env bash
# session-context.sh — owns the naming and lookup of the session-context files that
# /rush-context-save writes and /rush-context-load reads, under .rush/memory/sessions/.
#
# The file's *content* is the skill's job; the file's *identity* is this script's, so neither
# side has to invent a filename or decide by inspection which saved context is the newest one.
#
#   new-path <slug>   Where the next session-context file goes (creates the directory only).
#   latest            The most recent saved file, or found:false when there is none.
#   list              Every saved file, newest first.
#
# .rush/memory/sessions/ is local scratch, not a project artifact: new-path reports whether the
# project's .gitignore already covers it so the skill can offer to add it (it never edits
# .gitignore itself, and neither does this script).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: session-context.sh new-path <slug> [--json]
       session-context.sh latest [--json]
       session-context.sh list [--json]

Resolves paths under .rush/memory/sessions/ for /rush-context-save and /rush-context-load.

  new-path <slug>  Echo the path for a new session-context file, named
                   <YYYY-MM-DD>-<slug>.md (a numeric suffix is added if that name is
                   taken). Creates .rush/memory/sessions/ if missing; writes no file.
                   Reports dir_existed (false on the first save in a project) and
                   gitignored (whether .gitignore already covers the directory).
  latest           Echo the newest saved file. found:false, exit 0, when none exists —
                   an empty store is a valid answer, not an error.
  list             Echo every saved file, newest first.

  --json           Print a single JSON object on stdout, nothing else.
  -h, --help       Show this help and exit.

Exit codes: 0 success (including an empty store), 2 usage or internal error.
EOF
}

SUBCOMMAND=""
SLUG=""
JSON_OUT=false

while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON_OUT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) rush_die "unknown option: $1" 2 ;;
    *)
      if [ -z "$SUBCOMMAND" ]; then
        SUBCOMMAND="$1"
      elif [ -z "$SLUG" ]; then
        SLUG="$1"
      else
        rush_die "unexpected extra argument: $1" 2
      fi
      shift ;;
  esac
done

case "$SUBCOMMAND" in
  new-path|latest|list) ;;
  "") usage >&2; exit 2 ;;
  *) rush_die "unknown subcommand: $SUBCOMMAND (expected new-path, latest or list)" 2 ;;
esac

if [ "$SUBCOMMAND" = "new-path" ] && [ -z "$SLUG" ]; then
  rush_die "new-path requires a slug (e.g. session-context.sh new-path triage-rewrite)" 2
fi

ROOT="$(rush_root)" || exit 2
PY="$(rush_python)" || exit 2

PYFILE="$(mktemp "${TMPDIR:-/tmp}/rush-session-context.XXXXXX")" || exit 2
trap 'rm -f "$PYFILE"' EXIT

cat > "$PYFILE" <<'PYEOF'
import datetime
import json
import os
import re
import sys

root, subcommand, slug = sys.argv[1], sys.argv[2], sys.argv[3]

SESSIONS_REL = os.path.join(".rush", "memory", "sessions")
SESSIONS_DIR = os.path.join(root, SESSIONS_REL)
NAME_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})-(.+)\.md$")

# .gitignore entries that would cover .rush/memory/sessions/. A project may ignore the
# directory itself or any parent of it; anything else is not coverage, and saying so
# honestly is the point — the skill offers to add an entry, it never assumes one.
COVERING = (
    ".rush/memory/sessions",
    ".rush/memory/sessions/",
    "/.rush/memory/sessions",
    "/.rush/memory/sessions/",
    ".rush/memory",
    ".rush/memory/",
    "/.rush/memory",
    "/.rush/memory/",
    ".rush",
    ".rush/",
    "/.rush",
    "/.rush/",
)


def sanitize(raw):
    s = raw.strip().lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s[:48].strip("-")


def gitignored():
    path = os.path.join(root, ".gitignore")
    if not os.path.isfile(path):
        return False
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                entry = line.strip()
                if not entry or entry.startswith("#"):
                    continue
                if entry in COVERING:
                    return True
    except OSError:
        return False
    return False


def entries():
    if not os.path.isdir(SESSIONS_DIR):
        return []
    out = []
    for name in os.listdir(SESSIONS_DIR):
        m = NAME_RE.match(name)
        if not m:
            continue
        full = os.path.join(SESSIONS_DIR, name)
        if not os.path.isfile(full):
            continue
        try:
            st = os.stat(full)
        except OSError:
            continue
        out.append({
            "path": "%s/%s" % (SESSIONS_REL.replace(os.sep, "/"), name),
            "slug": m.group(2),
            "date": m.group(1),
            "mtime": int(st.st_mtime),
            "bytes": st.st_size,
        })
    # Newest first. Filename date leads because it is what the human reads; mtime breaks
    # ties within a day, which is exactly when more than one save happens.
    out.sort(key=lambda e: (e["date"], e["mtime"], e["slug"]), reverse=True)
    return out


def fail(message):
    print(json.dumps({"error": message}), file=sys.stderr)
    sys.exit(2)


if subcommand == "new-path":
    clean = sanitize(slug)
    if not clean:
        fail("slug %r contains no usable characters (expected letters or digits)" % slug)
    dir_existed = os.path.isdir(SESSIONS_DIR)
    try:
        os.makedirs(SESSIONS_DIR, exist_ok=True)
    except OSError as exc:
        fail("could not create %s: %s" % (SESSIONS_REL, exc))
    date = datetime.date.today().isoformat()
    candidate = "%s-%s.md" % (date, clean)
    suffix = 2
    while os.path.exists(os.path.join(SESSIONS_DIR, candidate)):
        candidate = "%s-%s-%d.md" % (date, clean, suffix)
        suffix += 1
    print(json.dumps({
        "path": "%s/%s" % (SESSIONS_REL.replace(os.sep, "/"), candidate),
        "slug": clean,
        "date": date,
        "dir_existed": dir_existed,
        "gitignored": gitignored(),
    }, ensure_ascii=False))
    sys.exit(0)

if subcommand == "latest":
    found = entries()
    if not found:
        print(json.dumps({"found": False, "path": None, "count": 0}))
        sys.exit(0)
    newest = dict(found[0])
    newest["found"] = True
    newest["count"] = len(found)
    print(json.dumps(newest, ensure_ascii=False))
    sys.exit(0)

found = entries()
print(json.dumps({"count": len(found), "sessions": found}, ensure_ascii=False))
PYEOF

OUT="$("$PY" "$PYFILE" "$ROOT" "$SUBCOMMAND" "$SLUG")" || exit 2

if [ "$JSON_OUT" = true ]; then
  printf '%s\n' "$OUT"
  exit 0
fi

case "$SUBCOMMAND" in
  new-path)
    "$PY" -c "
import json, sys
d = json.loads(sys.argv[1])
print(d['path'])
if not d['dir_existed'] and not d['gitignored']:
    sys.stderr.write('[rush] WARN: .gitignore does not cover .rush/memory/sessions/ — session context is local scratch and should not be committed.\n')
" "$OUT"
    ;;
  latest)
    "$PY" -c "
import json, sys
d = json.loads(sys.argv[1])
if not d['found']:
    sys.stderr.write('[rush] no session context saved yet (run /rush-context-save first).\n')
else:
    print(d['path'])
" "$OUT"
    ;;
  list)
    "$PY" -c "
import json, sys
d = json.loads(sys.argv[1])
if d['count'] == 0:
    sys.stderr.write('[rush] no session context saved yet (run /rush-context-save first).\n')
for e in d['sessions']:
    print('%s  %s  (%d bytes)' % (e['date'], e['path'], e['bytes']))
" "$OUT"
    ;;
esac

exit 0

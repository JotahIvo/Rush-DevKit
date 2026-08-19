#!/usr/bin/env bash
# memory-prune.sh — archive resolved/closed sections out of the shared memory files that only ever
# grow (.rush/memory/debt.md, .rush/memory/architecture.md's per-spec digest), so every skill that
# reads one of them in full stops paying, on every read, for history nobody needs anymore.
#
# Archiving means moving a whole "## heading" section, byte for byte, from the active file into a
# sibling <name>.archive.md next to it. Nothing under .rush/memory/ is ever deleted; it stops being
# in the file skills read by default. `--restore <id>` reverses one move.
#
# This is a thin caller over rushlib.py's existing markdown parsing (parse_headings) and atomic
# writer (dump_text_file) — it does not reimplement markdown parsing. See docs/harness.md
# "Determinism belongs to scripts."
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: memory-prune.sh [--file debt|architecture|all] [--older-than N] [--dry-run] [--restore ID] [--json]

Archives resolved/closed sections out of shared .rush/memory/ files that accumulate over the
project's lifetime, into a sibling <name>.archive.md. Nothing is deleted.

  --file debt|architecture|all   Which file to prune (default: all).
  --older-than N                 Age in days before a resolved section is eligible (default:
                                  memory.archive_after_days in .rush/config.json, else 90).
  --dry-run                      Report what would move without writing anything.
  --restore ID                   Move one archived section (a debt id, or a spec id for the
                                  architecture digest) back into its active file. Ignores --file.
  --json                         Machine-readable output.

Eligibility (an "open" / unresolved entry is never touched, regardless of age):
  debt.md                Section status is "accepted" or "repaid" (read from its own
                          "## <id> — <status>" heading) AND the most recent YYYY-MM-DD date found
                          inside that section is older than the threshold.
  architecture.md digest  A spec's digest section is eligible only when every feature directory
                          under specs/<spec-id>/ has its `feature_close` gate confirmed in
                          .rush/state.json -> gates_confirmed (i.e. the spec is fully closed) AND
                          the section's most recent date is older than the threshold. A spec still
                          open, or a section with no date to judge age from, is never archived.
EOF
}

ROOT="$(rush_root)" || exit 2
PY="$(rush_python)" || exit 2

TARGET="all"
OLDER_THAN=""
DRY_RUN=false
RESTORE_ID=""
JSON_OUT=false

while [ $# -gt 0 ]; do
  case "$1" in
    --file) TARGET="${2:-}"; shift 2 ;;
    --older-than) OLDER_THAN="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --restore) RESTORE_ID="${2:-}"; shift 2 ;;
    --json) JSON_OUT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) rush_die "unknown argument: $1" 2 ;;
  esac
done

case "$TARGET" in
  debt|architecture|all) ;;
  *) rush_die "--file must be debt, architecture or all" 2 ;;
esac

if [ -z "$OLDER_THAN" ]; then
  OLDER_THAN="$(rush_config "memory.archive_after_days" "90")"
fi
case "$OLDER_THAN" in
  ''|*[!0-9]*) rush_die "--older-than must be a non-negative integer" 2 ;;
esac

PYFILE="$(mktemp)"
trap 'rm -f "$PYFILE"' EXIT

cat > "$PYFILE" <<'PYEOF'
import datetime
import json
import os
import re
import sys

(root, lib_dir, target, older_than, dry_run_flag, restore_id) = sys.argv[1:7]
older_than = int(older_than)
dry_run = dry_run_flag == "1"

sys.path.insert(0, lib_dir)
import rushlib  # noqa: E402

DEBT_FILE = os.path.join(root, ".rush", "memory", "debt.md")
DEBT_ARCHIVE = os.path.join(root, ".rush", "memory", "debt.archive.md")
ARCH_FILE = os.path.join(root, ".rush", "memory", "architecture.md")
ARCH_ARCHIVE = os.path.join(root, ".rush", "memory", "architecture.archive.md")
STATE_FILE = os.path.join(root, ".rush", "state.json")

DATE_RE = re.compile(r"(\d{4}-\d{2}-\d{2})")
ARCHIVE_HEADER = (
    "<!-- Archived by memory-prune.sh. Sections here are moved out of the active file verbatim,\n"
    "     never deleted. Run `memory-prune.sh --restore <id>` to move one back. -->\n"
)
today = datetime.date.today()


def read(path):
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return f.read()


def write(path, text):
    if not dry_run:
        rushlib.dump_text_file(path, text)


def most_recent_date(text):
    dates = []
    for m in DATE_RE.finditer(text):
        try:
            dates.append(datetime.date.fromisoformat(m.group(1)))
        except ValueError:
            continue
    return max(dates) if dates else None


def top_level_sections(text):
    """Level-2 ('## ...') sections with their exact source span, so removal/append is byte-exact."""
    headings = rushlib.parse_headings(text)
    lines = text.splitlines(keepends=True)
    sections = []
    level2 = [h for h in headings if h["level"] == 2]
    for h in level2:
        start = h["line"] - 1
        end = len(lines)
        for other in headings:
            if other["line"] > h["line"] and other["level"] <= 2:
                end = other["line"] - 1
                break
        sections.append({"title": h["title"], "start": start, "end": end, "text": "".join(lines[start:end])})
    return lines, sections


def remove_sections(text, sections_to_remove):
    lines = text.splitlines(keepends=True)
    ranges = sorted((s["start"], s["end"]) for s in sections_to_remove)
    keep, pos = [], 0
    for start, end in ranges:
        keep.extend(lines[pos:start])
        pos = max(pos, end)
    keep.extend(lines[pos:])
    return "".join(keep)


def append_to_archive(archive_path, section_text):
    existing = read(archive_path)
    if existing is None:
        existing = ARCHIVE_HEADER
    sep = "" if existing.endswith("\n\n") else ("\n" if existing.endswith("\n") else "\n\n")
    write(archive_path, existing + sep + section_text.rstrip("\n") + "\n")


result = {"target": target, "older_than_days": older_than, "dry_run": dry_run, "actions": []}


def prune_debt():
    text = read(DEBT_FILE)
    if text is None:
        return
    _, sections = top_level_sections(text)
    to_remove = []
    for s in sections:
        # debt-template.md heading shape: "## {{DEBT_ID}} — {{STATUS}}"
        m = re.match(r"^(.+?)\s*[—–-]\s*(accepted|repaid)\s*$", s["title"], re.IGNORECASE)
        if not m:
            continue
        debt_id, status = m.group(1).strip(), m.group(2).lower()
        d = most_recent_date(s["text"])
        if d is None or (today - d).days <= older_than:
            continue
        to_remove.append(s)
        result["actions"].append({"file": "debt.md", "id": debt_id, "status": status,
                                   "age_days": (today - d).days, "action": "archived"})
    if not to_remove:
        return
    for s in to_remove:
        append_to_archive(DEBT_ARCHIVE, s["text"])
    write(DEBT_FILE, remove_sections(text, to_remove))


def spec_fully_closed(spec_id):
    state = None
    if os.path.isfile(STATE_FILE):
        try:
            state = rushlib.load_json_file(STATE_FILE)
        except Exception:
            state = None
    gates = {}
    if isinstance(state, dict):
        raw_gates = state.get("gates_confirmed")
        if isinstance(raw_gates, dict):
            gates = raw_gates
    spec_dir = os.path.join(root, "specs", spec_id)
    if not os.path.isdir(spec_dir):
        return False
    feature_dirs = sorted(
        d for d in os.listdir(spec_dir)
        if re.match(r"^\d{3}-", d) and os.path.isdir(os.path.join(spec_dir, d))
    )
    if not feature_dirs:
        return False
    for fd in feature_dirs:
        rel = "specs/%s/%s" % (spec_id, fd)
        confirmed = gates.get(rel)
        if not confirmed:
            return False
    return True


def prune_architecture():
    text = read(ARCH_FILE)
    if text is None:
        return
    _, sections = top_level_sections(text)
    to_remove = []
    for s in sections:
        # architecture-summary-template.md heading shape: "## {{SPEC_ID}} — {{SPEC_TITLE}}"
        m = re.match(r"^(\d{3}-[a-z0-9-]+)\s*[—–-]", s["title"], re.IGNORECASE)
        if not m:
            continue
        spec_id = m.group(1)
        d = most_recent_date(s["text"])
        if d is None or (today - d).days <= older_than:
            continue
        if not spec_fully_closed(spec_id):
            continue
        to_remove.append(s)
        result["actions"].append({"file": "architecture.md", "id": spec_id,
                                   "age_days": (today - d).days, "action": "archived"})
    if not to_remove:
        return
    for s in to_remove:
        append_to_archive(ARCH_ARCHIVE, s["text"])
    write(ARCH_FILE, remove_sections(text, to_remove))


def restore(section_id):
    for active_path, archive_path, label in (
        (DEBT_FILE, DEBT_ARCHIVE, "debt.md"),
        (ARCH_FILE, ARCH_ARCHIVE, "architecture.md"),
    ):
        archive_text = read(archive_path)
        if archive_text is None:
            continue
        _, sections = top_level_sections(archive_text)
        match = next((s for s in sections if s["title"].lower().startswith(section_id.lower())), None)
        if match is None:
            continue
        write(archive_path, remove_sections(archive_text, [match]))
        active_text = read(active_path) or ""
        sep = "" if (not active_text or active_text.endswith("\n\n")) else "\n"
        write(active_path, active_text + sep + match["text"].rstrip("\n") + "\n\n")
        result["actions"].append({"file": label, "id": section_id, "action": "restored"})
        return
    result["actions"].append({"file": None, "id": section_id, "action": "not_found_in_any_archive"})


if restore_id:
    restore(restore_id)
else:
    if target in ("debt", "all"):
        prune_debt()
    if target in ("architecture", "all"):
        prune_architecture()

print(json.dumps(result, ensure_ascii=False))
PYEOF

OUT="$("$PY" "$PYFILE" "$ROOT" "$SCRIPT_DIR/lib" "$TARGET" "$OLDER_THAN" \
  "$([ "$DRY_RUN" = true ] && echo 1 || echo 0)" "$RESTORE_ID")"

if [ "$JSON_OUT" = true ]; then
  printf '%s\n' "$OUT"
else
  COUNT="$("$PY" -c "import json,sys; print(len(json.loads(sys.argv[1])['actions']))" "$OUT")"
  if [ "$COUNT" -eq 0 ]; then
    rush_ok "nothing eligible to archive (threshold: ${OLDER_THAN}d)"
  else
    "$PY" -c "
import json, sys
d = json.loads(sys.argv[1])
verb = 'would archive' if d['dry_run'] else 'archived'
for a in d['actions']:
    if a['action'] == 'restored':
        print('restored: %s (%s)' % (a['id'], a['file']))
    elif a['action'] == 'not_found_in_any_archive':
        print('not found in any archive: %s' % a['id'])
    else:
        print('%s: %s (%s, %dd old)' % (verb, a['id'], a['file'], a['age_days']))
" "$OUT"
  fi
fi

exit 0

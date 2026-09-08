#!/usr/bin/env bash
# questions.sh - read and write specs/<spec-id>/questions.md without loading it.
#
# questions.md is append-only by design: an entry is never deleted, because the
# assumption recorded in it may already have shipped inside an artifact. That
# design is right and this script does not change it — but it means the file
# only grows, and every skill that used to "read questions.md" was reading a
# log where the answered entries (the overwhelming majority, and the longest
# ones) had no bearing on the work in hand.
#
# So: `--open` returns only what is still unanswered, `--add` and `--answer`
# write entries in the exact template shape instead of hand-editing, and
# `--archive-answered` moves settled entries into questions.archive.md, leaving
# a one-line index behind. Nothing is ever lost; it just stops being read.
#
# Usage:
#   questions.sh [<spec-id>] --open [--json]
#   questions.sh [<spec-id>] --list [--json]
#   questions.sh [<spec-id>] --add "<question>" --assumption "<text>" --by <agent> [--json]
#   questions.sh [<spec-id>] --answer <id> "<answer text>" [--json]
#   questions.sh [<spec-id>] --archive-answered [--older-than <days>] [--json]
#
# Exit 0 on success, 2 on usage or internal error.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: questions.sh [<spec-id>] <action> [options]

Actions:
  --open                     List only entries whose status is `open`.
  --list                     List every entry (id, status, one-line question).
  --add "<question>"         Append a new open entry; --assumption is required
                             (an open question with no assumption recorded is a
                             stall, not a question), --by names the agent.
  --answer <id> "<text>"     Answer an open entry and flip it to `answered`.
  --archive-answered         Move answered entries to questions.archive.md,
                             leaving a one-line index. --older-than <days>
                             restricts it to entries dated further back
                             (default: .rush/config.json -> memory.archive_after_days).

Options:
  --assumption <text>        The assumption adopted meanwhile (with --add).
  --by <agent>               Agent recording the entry (with --add).
  --older-than <days>        With --archive-answered.
  --json                     Print one JSON object on stdout, nothing else.
  -h, --help                 Show this help.

<spec-id> defaults to .rush/state.json -> current_spec.
Exit codes: 0 ok, 2 usage/internal error.
EOF
}

action=""
spec_arg=""
json_mode="false"
q_text=""
assumption=""
by_agent=""
answer_id=""
answer_text=""
older_than=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true" ;;
    --open|--list|--archive-answered)
      [ -z "$action" ] || { echo "questions.sh: only one action at a time" >&2; exit 2; }
      action="${1#--}"
      ;;
    --add)
      [ -z "$action" ] || { echo "questions.sh: only one action at a time" >&2; exit 2; }
      action="add"; shift
      [ "$#" -gt 0 ] || { echo "questions.sh: --add requires the question text" >&2; exit 2; }
      q_text="$1"
      ;;
    --answer)
      [ -z "$action" ] || { echo "questions.sh: only one action at a time" >&2; exit 2; }
      action="answer"; shift
      [ "$#" -gt 0 ] || { echo "questions.sh: --answer requires <id> \"<text>\"" >&2; exit 2; }
      answer_id="$1"; shift
      [ "$#" -gt 0 ] || { echo "questions.sh: --answer requires the answer text" >&2; exit 2; }
      answer_text="$1"
      ;;
    --assumption) shift; [ "$#" -gt 0 ] || { echo "questions.sh: --assumption requires a value" >&2; exit 2; }; assumption="$1" ;;
    --by) shift; [ "$#" -gt 0 ] || { echo "questions.sh: --by requires a value" >&2; exit 2; }; by_agent="$1" ;;
    --older-than) shift; [ "$#" -gt 0 ] || { echo "questions.sh: --older-than requires a value" >&2; exit 2; }; older_than="$1" ;;
    -*) echo "questions.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      [ -z "$spec_arg" ] || { echo "questions.sh: unexpected extra argument: $1" >&2; exit 2; }
      spec_arg="$1"
      ;;
  esac
  shift
done

[ -n "$action" ] || { usage >&2; exit 2; }

root="$(rush_root)" || exit 2
py="$(rush_python)" || exit 2
export RUSH_ROOT="$root"

spec_id="$spec_arg"
[ -n "$spec_id" ] || spec_id="$(rush_current_spec)" || exit 2
[ -n "$spec_id" ] || rush_die "no spec id given and .rush/state.json has no current_spec."

spec_dir="$(rush_spec_dir "$spec_id")" || exit 2

if [ -z "$older_than" ]; then
  older_than="$(rush_config memory.archive_after_days 90 2>/dev/null || echo 90)"
fi

set +e
"$py" - "$root" "$spec_dir" "$action" "$json_mode" "$q_text" "$assumption" "$by_agent" \
  "$answer_id" "$answer_text" "$older_than" <<'PYEOF'
import datetime, json, os, re, sys

(root, spec_dir, action, json_mode, q_text, assumption, by_agent,
 answer_id, answer_text, older_than) = sys.argv[1:11]

sys.path.insert(0, os.environ.get("RUSH_LIB_DIR") or os.path.join(root, ".rush", "scripts", "lib"))
import rushlib  # noqa: E402

path = os.path.join(root, spec_dir, "questions.md")
archive_path = os.path.join(root, spec_dir, "questions.archive.md")
rel = os.path.join(spec_dir, "questions.md").replace(os.sep, "/")

ID_STATUS = re.compile(r"^(\S+)\s*[—–-]\s*(\S+)\s*$")
FIELD = lambda name: re.compile(r"\*\*%s\*\*:\s*(.+)" % re.escape(name))


def read(p):
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def fail(msg):
    sys.stderr.write("questions.sh: %s\n" % msg)
    raise SystemExit(2)


text = read(path)
if text is None:
    fail("no questions.md at %s" % rel)


def entries(src):
    out = []
    for h in rushlib.parse_headings(src):
        if h["level"] != 2:
            continue
        m = ID_STATUS.match(h["title"])
        if not m:
            continue
        content = h["content"]

        def field(name):
            fm = FIELD(name).search(content)
            return fm.group(1).strip() if fm else ""

        # "## <question-id> — <status>" in the template's own comment is a shape,
        # not an entry; counting it would inflate every total by one.
        if "<" in m.group(1) or "<" in m.group(2):
            continue
        out.append({
            "id": m.group(1),
            "status": m.group(2).lower(),
            "date": field("Date"),
            "asked_by": field("Asked by"),
            "question": field("Question"),
            "assumption": field("Assumption adopted meanwhile"),
            "answer": field("Answer"),
            "raw": "## %s\n%s" % (h["title"], content),
        })
    return out


def emit(payload, lines):
    if json_mode == "true":
        print(json.dumps(payload, ensure_ascii=False))
    else:
        for line in lines:
            print(line)


all_entries = entries(text)

if action in ("open", "list"):
    want = [e for e in all_entries if action == "list" or e["status"] == "open"]
    slim = [{k: e[k] for k in ("id", "status", "date", "asked_by", "question", "assumption")}
            for e in want]
    emit(
        {"file": rel, "total": len(all_entries), "returned": len(slim), "questions": slim},
        ["%s %s of %s total in %s"
         % (len(slim), "open" if action == "open" else "shown", len(all_entries), rel)]
        + ["  - %s [%s] %s" % (e["id"], e["status"], e["question"] or "(no text)") for e in slim],
    )
    raise SystemExit(0)

if action == "add":
    if not q_text.strip():
        fail("--add requires a non-empty question")
    if not assumption.strip():
        fail("--add requires --assumption: an open question with no assumption "
             "recorded stalls the work instead of documenting it")
    nums = []
    for e in all_entries:
        m = re.search(r"(\d+)$", e["id"])
        if m:
            nums.append(int(m.group(1)))
    new_id = "Q%03d" % ((max(nums) + 1) if nums else 1)
    today = datetime.date.today().isoformat()
    block = (
        "\n## %s — open\n\n"
        "- **Date**: %s\n"
        "- **Asked by**: %s\n"
        "- **Question**: %s\n"
        "- **Assumption adopted meanwhile**: %s\n"
        % (new_id, today, by_agent or "unknown", q_text.strip(), assumption.strip())
    )
    with open(path, "a", encoding="utf-8") as f:
        f.write(block)
    emit({"file": rel, "added": new_id, "status": "open"},
         ["added %s to %s" % (new_id, rel)])
    raise SystemExit(0)

if action == "answer":
    target = None
    for e in all_entries:
        if e["id"] == answer_id:
            target = e
            break
    if target is None:
        fail("no entry with id %r in %s" % (answer_id, rel))
    if target["status"] != "open":
        fail("%s is already %r; an answered entry is never rewritten" % (answer_id, target["status"]))
    old_head = "## %s — %s" % (target["id"], target["status"])
    if old_head not in text:
        # parse_headings normalises the dash; find the real heading line.
        for line in text.splitlines():
            if line.startswith("## " + target["id"]):
                old_head = line
                break
    new_head = "## %s — answered" % target["id"]
    updated = text.replace(old_head, new_head, 1)
    # The answer line goes at the end of that entry's block, per the template.
    marker = "- **Assumption adopted meanwhile**:"
    idx = updated.find(marker, updated.find(new_head))
    if idx == -1:
        fail("%s has no 'Assumption adopted meanwhile' line to anchor the answer to" % answer_id)
    end = updated.find("\n", idx)
    end = len(updated) if end == -1 else end
    updated = updated[:end] + "\n- **Answer**: " + answer_text.strip() + updated[end:]
    rushlib.dump_text_file(path, updated)
    emit({"file": rel, "answered": answer_id}, ["answered %s in %s" % (answer_id, rel)])
    raise SystemExit(0)

if action == "archive-answered":
    try:
        days = int(older_than)
    except ValueError:
        days = 90
    cutoff = datetime.date.today() - datetime.timedelta(days=days)
    moved, kept_index = [], []
    for e in all_entries:
        if e["status"] != "answered":
            continue
        try:
            d = datetime.date.fromisoformat(e["date"])
        except ValueError:
            continue
        if d <= cutoff:
            moved.append(e)
    if moved:
        # Cut each entry out by line range rather than by matching a
        # reconstructed block: parse_headings normalises whitespace, so the
        # reconstruction is not byte-identical to the file and a string replace
        # silently removes nothing while reporting success.
        lines = text.splitlines()
        starts = [i for i, ln in enumerate(lines) if ln.startswith("## ")]
        span = {}
        for n, i in enumerate(starts):
            head = lines[i][3:].strip()
            m = ID_STATUS.match(head)
            if not m:
                continue
            end = starts[n + 1] if n + 1 < len(starts) else len(lines)
            span[m.group(1)] = (i, end)
        moved = [e for e in moved if e["id"] in span]

        header = ""
        if not os.path.isfile(archive_path):
            header = (
                "<!-- Answered questions moved out of questions.md by "
                ".rush/scripts/questions.sh --archive-answered. Nothing here is "
                "deleted; it is only out of the way of the files agents read. -->\n\n"
                "# Answered Questions (archive)\n"
            )
        with open(archive_path, "a", encoding="utf-8") as f:
            if header:
                f.write(header)
            for e in moved:
                i, end = span[e["id"]]
                f.write("\n" + "\n".join(lines[i:end]).rstrip() + "\n")

        drop = set()
        for e in moved:
            i, end = span[e["id"]]
            drop.update(range(i, end))
            kept_index.append(
                "- %s — answered, archived: %s" % (e["id"], (e["question"] or "")[:120])
            )
        updated = "\n".join(ln for n, ln in enumerate(lines) if n not in drop)
        # The index of what was archived always ends the file. Lift the existing
        # "## Archived" section out — that section ONLY, up to the next heading,
        # since entries added after the last archive run live below it — and
        # re-append it with the new lines.
        ulines = updated.splitlines()
        prior_index = []
        start = None
        for n, ln in enumerate(ulines):
            if ln.strip() == "## Archived":
                start = n
                break
        if start is not None:
            stop = len(ulines)
            for n in range(start + 1, len(ulines)):
                if ulines[n].startswith("## "):
                    stop = n
                    break
            prior_index = [ln for ln in ulines[start:stop] if ln.startswith("- ")]
            ulines = ulines[:start] + ulines[stop:]
        index_lines = []
        for ln in prior_index + kept_index:
            if ln not in index_lines:
                index_lines.append(ln)
        kept_index = index_lines
        prior_index = []
        updated = "\n".join(ulines).rstrip()
        updated += (
            "\n\n## Archived\n\n<!-- Full text in questions.archive.md. -->\n"
            + "\n".join(prior_index + kept_index) + "\n"
        )
        updated = re.sub(r"\n{4,}", "\n\n\n", updated)
        rushlib.dump_text_file(path, updated)
    emit(
        {"file": rel, "archive": os.path.join(spec_dir, "questions.archive.md").replace(os.sep, "/"),
         "archived": [e["id"] for e in moved], "remaining": len(all_entries) - len(moved)},
        ["archived %d answered entries to questions.archive.md (%d entries remain in %s)"
         % (len(moved), len(all_entries) - len(moved), rel)],
    )
    raise SystemExit(0)

fail("unknown action %r" % action)
PYEOF
status=$?
set -e
exit "$status"

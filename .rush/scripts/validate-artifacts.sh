#!/usr/bin/env bash
# validate-artifacts.sh - required sections + unresolved placeholder markers
# for rush artifacts (a feature's prd.md, spec.md, plan.md, tasks.md and
# done-contract.md; a spec's pitch.md, prd.md, questions.md and
# architecture.md; CLAUDE.md, constitution.md, and the condensed per-spec
# digest in .rush/memory/architecture.md).
#
# Line budgets are also enforced here, but NOTHING has a built-in ceiling any
# more: every default is None, and a budget applies only where a project sets
# one in .rush/config.json -> budgets. See DEFAULT_BUDGETS below.
#
# Usage: validate-artifacts.sh [<feature-id>|--all] [--json]
#
# Exit 0 no severity:error violations, 1 violations found, 2 usage/internal.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: validate-artifacts.sh [<feature-id>|--all] [--json]

Validates required sections and unresolved placeholder markers
([NEEDS CLARIFICATION], TODO, {{...}}, unfilled <...>) across rush
artifacts, plus any line budget the project has explicitly set in
.rush/config.json -> budgets (none are set by default).

  <feature-id>   Validate specs/<feature-id>/{prd,spec,plan,tasks,done-contract}.md.
  --all          Validate every feature dir, every spec's own artifacts
                 (pitch.md, prd.md, questions.md, architecture.md, and its
                 condensed summary in .rush/memory/architecture.md), plus
                 project-wide artifacts (CLAUDE.md,
                 .rush/memory/constitution.md), if present. Default when no
                 argument given.
  --json         Print a single JSON object on stdout, nothing else.
  -h, --help     Show this help.

Exit codes: 0 ok, 1 violations (severity:error present), 2 usage/internal error.
EOF
}

json_mode="false"
target=""
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true" ;;
    --all) target="--all" ;;
    -*) echo "validate-artifacts.sh: unknown option: $arg" >&2; usage >&2; exit 2 ;;
    *)
      if [ -n "$target" ] && [ "$target" != "--all" ]; then
        echo "validate-artifacts.sh: unexpected extra argument: $arg" >&2; exit 2
      fi
      target="$arg"
      ;;
  esac
done
[ -n "$target" ] || target="--all"

root="$(rush_root)" || exit 2

result_file="$(mktemp)"
trap 'rm -f "$result_file"' EXIT

set +e
"$(rush_python)" - "$root" "$target" > "$result_file" <<'PYEOF'
import json, os, re, sys

root, target = sys.argv[1], sys.argv[2]

# Keys match .rush/config.schema.json -> budgets (NOT the artifact
# filenames): pitch, prd, spec, plan, architecture, architecture_summary,
# claude_md, constitution. "architecture" bounds a spec's own, complete
# specs/<spec-id>/architecture.md; "architecture_summary" bounds the
# condensed per-spec digest appended to the shared .rush/memory/architecture.md.
#
# Every default is None: NO artifact has a built-in line ceiling. A document is
# as long as its content honestly requires, and a PRD or an architecture cut
# short to hit a number just moves the missing decisions into someone's head.
# The mechanism stays because a project may genuinely want a cap on a specific
# file (a CLAUDE.md every agent reads on every run is the usual case) — set the
# key in .rush/config.json -> budgets and this check enforces it again.
DEFAULT_BUDGETS = {
    "pitch": None,
    "prd": None,
    "spec": None,
    "plan": None,
    "architecture": None,
    "architecture_summary": None,
    "claude_md": None,
    "constitution": None,
}

# Maps an artifact's basename to its budgets config key. "architecture.md"
# here means the full, per-spec version at specs/<spec-id>/architecture.md —
# the shared .rush/memory/architecture.md is an ever-growing index of many
# specs' summaries and is budgeted per-section instead (see
# check_architecture_summary_section).
BASENAME_TO_BUDGET_KEY = {
    "pitch.md": "pitch",
    "prd.md": "prd",
    "spec.md": "spec",
    "plan.md": "plan",
    "architecture.md": "architecture",
    "CLAUDE.md": "claude_md",
    "constitution.md": "constitution",
}

def load_config():
    cfg_path = os.path.join(root, ".rush", "config.json")
    try:
        with open(cfg_path) as f:
            return json.load(f)
    except Exception:
        return {}

def budgets():
    cfg = load_config()
    b = dict(DEFAULT_BUDGETS)
    overrides = cfg.get("budgets") if isinstance(cfg, dict) else None
    if isinstance(overrides, dict):
        for k, v in overrides.items():
            if v is None:
                b[k] = None
                continue
            try:
                b[k] = int(v)
            except Exception:
                pass
    return b

FENCE_RE = re.compile(r"^\s*```")

def strip_noncounted(text):
    """Return list of (line_no, line) for lines outside fenced code blocks
    and outside HTML comments. line_no is 1-indexed, matches original file."""
    lines = text.split("\n")
    out = []
    in_fence = False
    in_comment = False
    for i, line in enumerate(lines, start=1):
        if not in_comment and FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if not in_comment and "<!--" in line:
            if "-->" in line.split("<!--", 1)[1]:
                # comment opens and closes on the same line
                before = line.split("<!--", 1)[0]
                after = line.split("-->", 1)[1] if "-->" in line else ""
                remainder = before + after
                if remainder.strip():
                    out.append((i, remainder))
                continue
            in_comment = True
            before = line.split("<!--", 1)[0]
            if before.strip():
                out.append((i, before))
            continue
        if in_comment:
            if "-->" in line:
                in_comment = False
                after = line.split("-->", 1)[1]
                if after.strip():
                    out.append((i, after))
            continue
        out.append((i, line))
    return out

def budget_line_count(text):
    return len(strip_noncounted(text))

HTML_TAGS = {
    "div", "span", "br", "img", "a", "p", "table", "tr", "td", "th", "ul",
    "li", "ol", "b", "i", "em", "strong", "code", "pre", "h1", "h2", "h3",
    "h4", "h5", "h6", "html", "body", "head", "script", "style", "small",
    "sup", "sub", "hr", "blockquote", "kbd", "summary", "details",
}

PLACEHOLDER_CURLY_RE = re.compile(r"\{\{[^}\n]*\}\}")
PLACEHOLDER_ANGLE_RE = re.compile(r"</?([A-Za-z][A-Za-z0-9 _\-/]*)>")
TODO_RE = re.compile(r"\bTODO\b")
NEEDS_CLARIFICATION_RE = re.compile(r"\[NEEDS CLARIFICATION\]")

def find_placeholders(text):
    """Scan non-fenced, non-comment lines for unresolved placeholder
    markers. Returns list of (line_no, marker_text)."""
    found = []
    for line_no, line in strip_noncounted(text):
        for m in NEEDS_CLARIFICATION_RE.finditer(line):
            found.append((line_no, m.group(0)))
        for m in TODO_RE.finditer(line):
            found.append((line_no, m.group(0)))
        for m in PLACEHOLDER_CURLY_RE.finditer(line):
            found.append((line_no, m.group(0)))
        for m in PLACEHOLDER_ANGLE_RE.finditer(line):
            tag = m.group(1).strip().split()[0].lower() if m.group(1).strip() else ""
            if tag in HTML_TAGS:
                continue
            found.append((line_no, m.group(0)))
    return found

# Keyed by artifact KIND, not by basename: prd.md exists at two levels with
# deliberately different shapes — the spec's own complete product definition,
# and a feature's contained slice of it — so the caller says which one it is
# passing rather than the check guessing from a filename they share.
REQUIRED_SECTIONS = {
    "spec.md": ["behav", "interface", "data", "edge case", "out of scope", "assumption"],
    "plan.md": ["approach", "files", "order of work", "risk", "alternative"],
    "spec-prd": ["overview", "use cases", "goals", "out of scope",
                 "functional requirements", "quality attributes", "journeys",
                 "success metrics", "assumptions"],
    "feature-prd": ["overview", "requirements", "traceability", "out of scope",
                    "success criteria"],
    # Acceptance criteria moved out of spec.md and into done-contract.md, merged
    # with the Definition of Done that enforces them — this required-section
    # check is the section-heading half of that; check_done_contract() below
    # separately validates the fenced ```json block and its coverage table.
    "done-contract.md": ["acceptance criteria", "definition of done", "acceptance criteria coverage"],
}

def headings(text):
    hs = []
    in_fence = False
    for line in text.split("\n"):
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if line.lstrip().startswith("#"):
            hs.append(line.strip("# ").strip().lower())
    return hs

def check_sections(rel_path, text, violations, kind=None):
    base = kind or os.path.basename(rel_path)
    required = REQUIRED_SECTIONS.get(base)
    if not required:
        return
    hs = headings(text)
    for keyword in required:
        if not any(keyword in h for h in hs):
            violations.append({
                "file": rel_path, "rule": "missing_section",
                "message": "missing required section containing '%s'" % keyword,
                "severity": "error",
            })

def check_budget(rel_path, text, violations, budget_map):
    base = os.path.basename(rel_path)
    key = BASENAME_TO_BUDGET_KEY.get(base)
    if key is None:
        return
    limit = budget_map.get(key)
    if limit is None:
        return
    n = budget_line_count(text)
    if n > limit:
        violations.append({
            "file": rel_path, "rule": "budget",
            "message": "%d lines (max %d)" % (n, limit),
            "severity": "error",
        })

def check_placeholders(rel_path, text, violations):
    for line_no, marker in find_placeholders(text):
        violations.append({
            "file": rel_path, "rule": "placeholder",
            "message": "unresolved placeholder '%s' at line %d" % (marker, line_no),
            "severity": "error",
        })

def check_tasks(rel_path, text, violations):
    # A task is either a level-3 heading ("### T1 — Title", the shape
    # .rush/templates/tasks-template.md uses) or, tolerated as a fallback,
    # a top-level checklist/numbered-list item ("- [ ] ..." / "1. ...").
    # A "## Legend" or other non-task ### heading is not itself a task; we
    # only treat "###" headings as tasks (task ids live one level below
    # the "## Tasks" section, never at "##").
    #
    # Once a task is opened by an H3 heading, only another H3 (or a higher
    # heading) closes it — a "- [x] status: `done`" checkbox sub-bullet
    # inside the task's own body must never be mistaken for the start of a
    # new (flat-style) task, even though it matches the same "- [ ]"
    # shape the fallback checklist format uses at the top level.
    in_fence = False
    lines = text.split("\n")
    tasks = []
    current = None
    current_is_h3 = False
    for line in lines:
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        is_h3_task = re.match(r"^\s*###\s+\S", line)
        is_checklist = re.match(r"^\s*[-*]\s*\[[ xX]\]", line)
        is_numbered = re.match(r"^\s*\d+[.)]\s+", line)
        starts_new_task = is_h3_task or (not current_is_h3 and (is_checklist or is_numbered))
        if starts_new_task:
            if current is not None:
                tasks.append(current)
            current = {"header": line.strip(), "body": []}
            current_is_h3 = bool(is_h3_task)
        elif current is not None:
            current["body"].append(line)
        elif re.match(r"^\s*##\s+", line):
            # a "##" section boundary before any task started: nothing to do
            pass
    if current is not None:
        tasks.append(current)
    if not tasks:
        violations.append({
            "file": rel_path, "rule": "missing_section",
            "message": "no tasks found (expected a checklist or numbered list)",
            "severity": "error",
        })
        return
    for t in tasks:
        block = t["header"] + "\n" + "\n".join(t["body"])
        if "verify:" not in block.lower():
            violations.append({
                "file": rel_path, "rule": "missing_verify",
                "message": "task without 'verify:' line: %s" % t["header"][:80],
                "severity": "error",
            })

def check_done_contract(rel_path, text, violations):
    m = re.search(r"```json\s*\n(.*?)```", text, re.DOTALL)
    if not m:
        violations.append({
            "file": rel_path, "rule": "missing_done_json",
            "message": "no fenced ```json block found",
            "severity": "error",
        })
        return
    try:
        data = json.loads(m.group(1))
    except Exception as e:
        violations.append({
            "file": rel_path, "rule": "invalid_done_json",
            "message": "fenced json block does not parse: %s" % e,
            "severity": "error",
        })
        return
    if "checks" not in data or not isinstance(data["checks"], list) or not data["checks"]:
        violations.append({
            "file": rel_path, "rule": "invalid_done_json",
            "message": "'checks' must be a non-empty array",
            "severity": "error",
        })
    else:
        for c in data["checks"]:
            if not isinstance(c, dict) or not all(k in c for k in ("name", "run", "expect")):
                violations.append({
                    "file": rel_path, "rule": "invalid_done_json",
                    "message": "each check needs name, run, expect: %r" % (c,),
                    "severity": "error",
                })
    if "human_gates" not in data or not isinstance(data["human_gates"], list):
        violations.append({
            "file": rel_path, "rule": "invalid_done_json",
            "message": "'human_gates' must be an array (may be empty)",
            "severity": "error",
        })

def check_architecture_summary_section(rel_path, text, spec_id, violations, budget_map):
    # Finds this spec's condensed digest inside the shared, ever-growing
    # .rush/memory/architecture.md (one "## <spec-id> — ..." section per
    # spec, from architecture-summary-template.md) and budgets *that
    # section alone* — never the whole accumulating file, which has no
    # single sensible ceiling since it only ever grows as specs are added.
    hs_positions = []
    lines = text.split("\n")
    in_fence = False
    for i, line in enumerate(lines):
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if re.match(r"^#{1,6}\s+", line):
            level = len(line) - len(line.lstrip("#"))
            hs_positions.append((i, level, line.strip("# ").strip()))
    start = None
    start_level = None
    for i, level, title in hs_positions:
        if spec_id in title:
            start = i
            start_level = level
            break
    if start is None:
        return
    end = len(lines)
    for i, level, title in hs_positions:
        if i > start and level <= start_level:
            end = i
            break
    section_text = "\n".join(lines[start:end])
    n = budget_line_count(section_text)
    limit = budget_map.get("architecture_summary")
    if limit is None:
        return
    if n > limit:
        violations.append({
            "file": rel_path, "rule": "budget",
            "message": "summary section for %s: %d lines (max %d)" % (spec_id, n, limit),
            "severity": "error",
        })
    check_placeholders(rel_path, section_text, violations)

def read(rel):
    p = os.path.join(root, rel)
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except Exception:
        return None

def feature_ids():
    # Features live nested one level under their spec: specs/<spec-id>/<feature-id>/.
    # Returns "<spec-id>/<feature-id>" composites so "specs/%s" % fid below still
    # points at the right directory without every caller needing to know about
    # the nesting.
    specs = os.path.join(root, "specs")
    if not os.path.isdir(specs):
        return []
    out = []
    for spec_name in sorted(os.listdir(specs)):
        spec_path = os.path.join(specs, spec_name)
        if not os.path.isdir(spec_path) or not re.match(r"^\d{3}-", spec_name):
            continue
        for feat_name in sorted(os.listdir(spec_path)):
            feat_path = os.path.join(spec_path, feat_name)
            if os.path.isdir(feat_path) and re.match(r"^\d{3}-", feat_name):
                out.append("%s/%s" % (spec_name, feat_name))
    return out

def spec_ids():
    specs = os.path.join(root, "specs")
    if not os.path.isdir(specs):
        return []
    return sorted(
        n for n in os.listdir(specs)
        if os.path.isdir(os.path.join(specs, n)) and re.match(r"^\d{3}-", n)
    )

violations = []
checked = []
bmap = budgets()

def validate_feature(fid):
    fdir = "specs/%s" % fid
    for fname in ("prd.md", "spec.md", "plan.md", "tasks.md", "done-contract.md"):
        rel = "%s/%s" % (fdir, fname)
        text = read(rel)
        if text is None:
            continue
        checked.append(rel)
        check_budget(rel, text, violations, bmap)
        check_placeholders(rel, text, violations)
        if fname == "tasks.md":
            check_tasks(rel, text, violations)
        elif fname == "done-contract.md":
            check_done_contract(rel, text, violations)
            check_sections(rel, text, violations)
        elif fname == "prd.md":
            check_sections(rel, text, violations, kind="feature-prd")
        else:
            check_sections(rel, text, violations)

def validate_spec(spec_id):
    # pitch.md/prd.md/questions.md/architecture.md all live directly in
    # specs/<spec-id>/ now (the v0.2.0 nested layout) — this is also the
    # only place any of them is actually checked; there is no separate
    # top-level specs/pitch.md or specs/prd.md any more.
    sdir = "specs/%s" % spec_id
    for fname in ("pitch.md", "prd.md", "questions.md", "architecture.md"):
        rel = "%s/%s" % (sdir, fname)
        text = read(rel)
        if text is None:
            continue
        checked.append(rel)
        check_budget(rel, text, violations, bmap)
        check_placeholders(rel, text, violations)
        if fname == "prd.md":
            check_sections(rel, text, violations, kind="spec-prd")
    arch_mem_text = read(".rush/memory/architecture.md")
    if arch_mem_text is not None:
        checked.append(".rush/memory/architecture.md#%s" % spec_id)
        check_architecture_summary_section(".rush/memory/architecture.md", arch_mem_text, spec_id, violations, bmap)

def validate_project_wide():
    for rel in ("CLAUDE.md", ".rush/memory/constitution.md"):
        text = read(rel)
        if text is None:
            continue
        checked.append(rel)
        check_budget(rel, text, violations, bmap)
        check_placeholders(rel, text, violations)

if target == "--all":
    for fid in feature_ids():
        validate_feature(fid)
    for sid in spec_ids():
        validate_spec(sid)
    validate_project_wide()
else:
    fdir_path = os.path.join(root, "specs", target)
    if not os.path.isdir(fdir_path):
        matches = [n for n in (os.listdir(os.path.join(root, "specs")) if os.path.isdir(os.path.join(root, "specs")) else []) if n.startswith(target)]
        if len(matches) == 1:
            target = matches[0]
        else:
            print(json.dumps({"error": "no feature matching '%s'" % target}), file=sys.stderr)
            sys.exit(2)
    validate_feature(target)

ok = not any(v["severity"] == "error" for v in violations)
out = {"ok": ok, "checked": checked, "violations": violations}
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
print("checked %d file(s)" % len(data["checked"]))
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

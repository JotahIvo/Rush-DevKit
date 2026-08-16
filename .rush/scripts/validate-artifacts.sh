#!/usr/bin/env bash
# validate-artifacts.sh - required sections + line budgets + unresolved
# placeholder markers for rush artifacts (spec.md, plan.md, tasks.md,
# done-contract.md, pitch.md, prd.md, CLAUDE.md, constitution.md, and the
# per-feature section of architecture.md).
#
# Usage: validate-artifacts.sh [<feature-id>|--all] [--json]
#
# Exit 0 no severity:error violations, 1 violations found, 2 usage/internal.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: validate-artifacts.sh [<feature-id>|--all] [--json]

Validates required sections, line budgets and unresolved placeholder
markers ([NEEDS CLARIFICATION], TODO, {{...}}, unfilled <...>) across
rush artifacts.

  <feature-id>   Validate specs/<feature-id>/{spec,plan,tasks,done-contract}.md
                 plus that feature's architecture.md section, if present.
  --all          Validate every feature dir plus project-wide artifacts
                 (CLAUDE.md, .rush/memory/constitution.md, specs/pitch.md,
                 specs/prd.md), if present. Default when no argument given.
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
# filenames): pitch, prd, spec, plan, architecture, claude_md, constitution.
DEFAULT_BUDGETS = {
    "pitch": 60,
    "prd": 200,
    "spec": 150,
    "plan": 100,
    "architecture": 100,
    "claude_md": 60,
    "constitution": 200,
}

# Maps an artifact's basename to its budgets config key.
BASENAME_TO_BUDGET_KEY = {
    "pitch.md": "pitch",
    "prd.md": "prd",
    "spec.md": "spec",
    "plan.md": "plan",
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

REQUIRED_SECTIONS = {
    "spec.md": ["behav", "interface", "data", "edge case", "acceptance criteria", "out of scope", "assumption"],
    "plan.md": ["approach", "files", "order of work", "risk", "alternative"],
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

def check_sections(rel_path, text, violations):
    base = os.path.basename(rel_path)
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
    in_fence = False
    lines = text.split("\n")
    tasks = []
    current = None
    for line in lines:
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        is_h3_task = re.match(r"^\s*###\s+\S", line)
        is_checklist = re.match(r"^\s*[-*]\s*\[[ xX]\]", line)
        is_numbered = re.match(r"^\s*\d+[.)]\s+", line)
        if is_h3_task or is_checklist or is_numbered:
            if current is not None:
                tasks.append(current)
            current = {"header": line.strip(), "body": []}
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

def check_architecture_section(rel_path, text, feature_id, violations, budget_map):
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
        if feature_id in title:
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
    limit = budget_map.get("architecture", DEFAULT_BUDGETS["architecture"])
    if n > limit:
        violations.append({
            "file": rel_path, "rule": "budget",
            "message": "section for %s: %d lines (max %d)" % (feature_id, n, limit),
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
    specs = os.path.join(root, "specs")
    if not os.path.isdir(specs):
        return []
    out = []
    for name in sorted(os.listdir(specs)):
        if os.path.isdir(os.path.join(specs, name)) and re.match(r"^\d{3}-", name):
            out.append(name)
    return out

violations = []
checked = []
bmap = budgets()

def validate_feature(fid):
    fdir = "specs/%s" % fid
    for fname in ("spec.md", "plan.md", "tasks.md", "done-contract.md"):
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
        else:
            check_sections(rel, text, violations)
    arch_text = read(".rush/memory/architecture.md")
    if arch_text is not None:
        check_architecture_section(".rush/memory/architecture.md", arch_text, fid, violations, bmap)

def validate_project_wide():
    for rel in ("CLAUDE.md", ".rush/memory/constitution.md", "specs/pitch.md", "specs/prd.md"):
        text = read(rel)
        if text is None:
            continue
        checked.append(rel)
        check_budget(rel, text, violations, bmap)
        check_placeholders(rel, text, violations)

if target == "--all":
    for fid in feature_ids():
        validate_feature(fid)
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

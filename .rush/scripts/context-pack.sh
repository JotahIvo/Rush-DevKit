#!/usr/bin/env bash
# context-pack.sh - the one read that replaces six.
#
# Every skill used to open .rush/config.json, .rush/memory/constitution.md,
# specs/integration-map.md, specs/shared-contracts/, the spec's
# architecture.md and its ADRs in full, on every invocation. For a spec the
# size of a real one that is tens of thousands of words re-read per command,
# most of it irrelevant to the feature at hand. This script reads all of it
# once and emits only the slice that applies: the constitution's binding
# lines, this feature's own row of the integration map (plus the journeys
# that cross it), contract PATHS rather than contract bodies, ADR decisions
# rather than ADR prose, open questions rather than the whole log.
#
# Skills read this instead of those files. They still open a specific file
# in full when they are about to WRITE it, or when the pack names something
# they must inspect (a contract they are generating against, an ADR whose
# reasoning actually matters here).
#
# Usage: context-pack.sh [<feature-id>] [--spec <spec-id>] [--json]
#
# With no feature-id, packs the current feature from .rush/state.json; with
# neither, packs spec-level context only (no feature slice).
#
# Exit 0 always on a successful run, 2 on usage or internal error.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: context-pack.sh [<feature-id>] [--spec <spec-id>] [--json]

Emits one compact context digest for a feature, replacing the per-skill
ritual of reading config.json, constitution.md, integration-map.md,
shared-contracts/, architecture.md and the ADRs in full.

Contains: the config keys skills actually branch on; the constitution's
binding (MUST/NEVER) lines only; this feature's provides/consumes/depends_on
and the journeys crossing it; the contract file PATHS in play; ADR ids,
titles and decision lines; open questions and this feature's open debt;
artifact paths with line counts against their budget; task counts.

  <feature-id>   Feature to pack. Defaults to .rush/state.json -> current_feature.
  --spec <id>    Scope the feature lookup to one spec (needed when a bare
                 feature id exists under more than one spec).
  --json         Print a single JSON object on stdout, nothing else.
  -h, --help     Show this help.

Exit codes: 0 ok, 2 usage/internal error.
EOF
}

json_mode="false"
feature_arg=""
spec_arg=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true" ;;
    --spec)
      shift
      [ "$#" -gt 0 ] || { echo "context-pack.sh: --spec requires a value" >&2; exit 2; }
      spec_arg="$1"
      ;;
    --spec=*) spec_arg="${1#--spec=}" ;;
    -*) echo "context-pack.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [ -n "$feature_arg" ]; then
        echo "context-pack.sh: unexpected extra argument: $1" >&2; exit 2
      fi
      feature_arg="$1"
      ;;
  esac
  shift
done

root="$(rush_root)" || exit 2
py="$(rush_python)" || exit 2
export RUSH_ROOT="$root"

current_spec="$(rush_current_spec)" || exit 2
current_feature="$(rush_current_feature)" || exit 2

feature_id="$feature_arg"
[ -n "$feature_id" ] || feature_id="$current_feature"

spec_id="$spec_arg"
[ -n "$spec_id" ] || spec_id="$current_spec"

feature_dir=""
if [ -n "$feature_id" ]; then
  # A miss here is not fatal: spec-level context is still worth emitting,
  # and the caller sees feature_dir: null rather than an error it can't act on.
  feature_dir="$(rush_feature_dir "$feature_id" "$spec_id" 2>/dev/null || true)"
fi
if [ -n "$feature_dir" ] && [ -z "$spec_id" ]; then
  spec_id="$(basename "$(dirname "$feature_dir")")"
fi

spec_dir=""
if [ -n "$spec_id" ]; then
  spec_dir="$(rush_spec_dir "$spec_id" 2>/dev/null || true)"
fi

result_file="$(mktemp)"
trap 'rm -f "$result_file"' EXIT

set +e
"$py" - "$root" "$spec_dir" "$feature_dir" "$json_mode" > "$result_file" <<'PYEOF'
import json, os, re, sys

root, spec_dir, feature_dir, json_mode = sys.argv[1:5]

sys.path.insert(0, os.environ.get("RUSH_LIB_DIR") or os.path.join(root, ".rush", "scripts", "lib"))
import rushlib  # noqa: E402


def read(*parts):
    try:
        with open(os.path.join(root, *parts), encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def load_json(*parts):
    raw = read(*parts)
    if raw is None:
        return None
    try:
        return json.loads(raw)
    except ValueError:
        return None


cfg = load_json(".rush", "config.json") or {}


def cfg_get(dotted, default=None):
    cur = cfg
    for part in dotted.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return default
    return cur


# --- config: only the keys a skill actually branches on -----------------
budgets = {k: v for k, v in (cfg_get("budgets") or {}).items() if v is not None}
config_slice = {
    "language_docs": cfg_get("language.docs", "en"),
    "gates": cfg_get("gates", {}),
    "autonomy": cfg_get("autonomy", {}),
    "commands": {k: v for k, v in (cfg_get("commands") or {}).items() if v},
    "git": {
        "allow_commit": cfg_get("git.allow_commit", True),
        "allow_push": cfg_get("git.allow_push", False),
        "commit_convention": cfg_get("git.commit_convention", "conventional"),
        "branch_pattern": cfg_get("git.branch_pattern"),
    },
    "budgets": budgets,
    "sensitive_paths": cfg_get("security.sensitive_paths", []),
    "ai_features": cfg_get("ai_features", False),
}

# --- constitution: the binding lines, not the essay ----------------------
# A principle only binds when it is stated as one. Everything else in that
# file is rationale, and rationale is what a skill can afford to skip.
BINDING = re.compile(
    r"\b(MUST NOT|MUST|NEVER|SHALL NOT|SHALL|"
    r"NUNCA|SEMPRE|OBRIGAT\w+|PROIBID\w+|NÃO PODE|NÃO DEVE|DEVE)\b"
)
constitution_lines = []
constitution_text = read(".rush", "memory", "constitution.md")
constitution_truncated = False
if constitution_text:
    for raw_line in constitution_text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("<!--"):
            continue
        # Headings count: a constitution routinely states the principle in the
        # heading ("3. Errors are one shape (MUST)") and spends the body on why.
        line = line.lstrip("#").lstrip("-*").strip()
        if not line:
            continue
        if BINDING.search(line):
            constitution_lines.append(line)
    # Same sentence restated in a heading and its first body line is one rule.
    seen = set()
    deduped = []
    for line in constitution_lines:
        key = re.sub(r"[^\w]+", "", line.lower())[:80]
        if key in seen:
            continue
        seen.add(key)
        deduped.append(line)
    constitution_lines = deduped
    # A constitution written without any of those markers is not a licence to
    # skip it: fall back to its section titles so the caller still knows what
    # it binds on, and say plainly that the file must be opened.
    if not constitution_lines:
        constitution_lines = [
            h["title"] for h in rushlib.parse_headings(constitution_text) if h["level"] <= 3
        ]
        constitution_truncated = True

# --- integration map: this feature's row, and only it --------------------
imap_text = read("specs", "integration-map.md")
imap = None
if imap_text:
    block = rushlib.extract_json_block(imap_text)
    if block:
        try:
            imap = json.loads(block)
        except ValueError:
            imap = None

feature_key = feature_dir[len("specs/"):] if feature_dir.startswith("specs/") else feature_dir
map_slice = {
    "feature": None,
    "journeys": [],
    "consumed_from": [],
    "provided_to": [],
    "parse_error": imap_text is not None and imap is None,
}
if isinstance(imap, dict) and feature_key:
    features = imap.get("features") or []
    by_id = {f.get("id"): f for f in features if isinstance(f, dict)}
    me = by_id.get(feature_key)
    if me:
        map_slice["feature"] = {
            "id": me.get("id"),
            "title": me.get("title"),
            "provides": me.get("provides") or [],
            "consumes": me.get("consumes") or [],
            "depends_on": me.get("depends_on") or [],
        }
        # Who satisfies what I consume: the caller needs the provider's id and
        # contract path, never the provider's own working files.
        for c in me.get("consumes") or []:
            src = c.get("from")
            provider = by_id.get(src)
            map_slice["consumed_from"].append({
                "kind": c.get("kind"),
                "name": c.get("name"),
                "from": src,
                "contract": c.get("contract"),
                "provider_exists": provider is not None,
            })
        # Who breaks if I change what I provide. This is the cross-feature
        # blast radius, and it is the one thing a per-feature read cannot see.
        mine = {(p.get("kind"), p.get("name")) for p in (me.get("provides") or [])}
        for other in features:
            if not isinstance(other, dict) or other.get("id") == feature_key:
                continue
            for c in other.get("consumes") or []:
                if (c.get("kind"), c.get("name")) in mine:
                    map_slice["provided_to"].append({
                        "kind": c.get("kind"),
                        "name": c.get("name"),
                        "consumer": other.get("id"),
                    })
    for j in imap.get("journeys") or []:
        if isinstance(j, dict) and feature_key in (j.get("features") or []):
            map_slice["journeys"].append({
                "id": j.get("id"),
                "description": j.get("description"),
                "features": j.get("features") or [],
                "test": j.get("test"),
            })

# --- contracts: paths, never bodies --------------------------------------
def list_files(*parts):
    d = os.path.join(root, *parts)
    out = []
    if os.path.isdir(d):
        for name in sorted(os.listdir(d)):
            if name.startswith("."):
                continue
            p = os.path.join(d, name)
            if os.path.isfile(p):
                out.append(os.path.relpath(p, root).replace(os.sep, "/"))
    return out


contracts = {
    "own": list_files(feature_dir, "contracts") if feature_dir else [],
    "shared": list_files("specs", "shared-contracts"),
}

# --- architecture: decisions, not prose ----------------------------------
adrs = []
adr_dirs = [os.path.join(".rush", "memory", "decisions")]
if spec_dir:
    adr_dirs.append(os.path.join(spec_dir, "adr"))
for d in adr_dirs:
    abs_d = os.path.join(root, d)
    if not os.path.isdir(abs_d):
        continue
    for name in sorted(os.listdir(abs_d)):
        if not name.endswith(".md"):
            continue
        text = read(d, name) or ""
        title = ""
        decision = ""
        status = ""
        for h in rushlib.parse_headings(text):
            low = h["title"].lower()
            if h["level"] == 1 and not title:
                title = h["title"]
            if low.startswith("decision") or low.startswith("decis"):
                decision = " ".join(h["content"].split())[:400]
            if low.startswith("status"):
                status = " ".join(h["content"].split())[:80]
        adrs.append({
            "path": (d + "/" + name).replace(os.sep, "/"),
            "title": title or name,
            "status": status,
            "decision": decision,
        })

architecture_sections = []
if spec_dir:
    arch_text = read(spec_dir, "architecture.md")
    if arch_text:
        architecture_sections = [
            {"title": h["title"], "lines": len(h["content"].splitlines())}
            for h in rushlib.parse_headings(arch_text)
            if h["level"] == 2
        ]

# --- open questions and this feature's debt ------------------------------
_ID_STATUS_RE = re.compile(r"^(\S+)\s*[—–-]\s*(\S+)\s*$")


def open_entries(path_parts, field_name, open_statuses, must_mention=None):
    text = read(*path_parts)
    if text is None:
        return []
    field_re = re.compile(r"\*\*%s\*\*:\s*(.+)" % re.escape(field_name))
    out = []
    for h in rushlib.parse_headings(text):
        if h["level"] != 2:
            continue
        m = _ID_STATUS_RE.match(h["title"])
        if not m:
            continue
        entry_id, status = m.group(1), m.group(2).lower()
        if status not in open_statuses:
            continue
        if must_mention and must_mention not in h["content"]:
            continue
        fm = field_re.search(h["content"])
        out.append({"id": entry_id, "text": (fm.group(1).strip() if fm else "")[:300]})
    return out


open_questions = []
questions_total = 0
if spec_dir:
    qtext = read(spec_dir, "questions.md")
    if qtext is not None:
        questions_total = sum(
            1 for h in rushlib.parse_headings(qtext)
            if h["level"] == 2 and _ID_STATUS_RE.match(h["title"])
            and "<" not in h["title"]
        )
    open_questions = open_entries((spec_dir, "questions.md"), "Question", {"open"})

feature_leaf = os.path.basename(feature_dir) if feature_dir else None
open_debt = open_entries(
    (".rush", "memory", "debt.md"), "Shortcut taken", {"open"},
    must_mention=feature_leaf,
)

# --- artifacts: what exists, how big, and whether it is over budget ------
BUDGET_KEY = {
    "spec.md": "spec", "plan.md": "plan", "prd.md": "prd",
    "tasks.md": "tasks", "done-contract.md": "done_contract",
}
artifacts = []
if feature_dir:
    for name in ("spec.md", "plan.md", "tasks.md", "done-contract.md", "prd.md"):
        text = read(feature_dir, name)
        if text is None:
            continue
        lines = rushlib.count_content_lines(text)
        budget = budgets.get(BUDGET_KEY.get(name, ""))
        artifacts.append({
            "path": (feature_dir + "/" + name),
            "lines": lines,
            "budget": budget,
            "over_budget": bool(budget) and lines > budget,
        })

task_counts = {s: 0 for s in rushlib.STATUS_CHOICES}
next_task = None
if feature_dir:
    ttext = read(feature_dir, "tasks.md")
    if ttext is not None:
        for t in rushlib.parse_tasks(ttext):
            task_counts[t["status"]] = task_counts.get(t["status"], 0) + 1
            if next_task is None and t["status"] in ("pending", "in_progress"):
                next_task = {"id": t.get("id"), "status": t["status"]}

out = {
    "spec_dir": spec_dir or None,
    "feature_dir": feature_dir or None,
    "feature_id": feature_key or None,
    "config": config_slice,
    "constitution": {
        "path": ".rush/memory/constitution.md",
        "binding_lines": constitution_lines,
        "headings_only": constitution_truncated,
    },
    "integration_map": map_slice,
    "contracts": contracts,
    "adrs": adrs,
    "architecture_sections": architecture_sections,
    "open_questions": open_questions,
    "questions_total": questions_total,
    "open_debt": open_debt,
    "artifacts": artifacts,
    "tasks": task_counts,
    "next_task": next_task,
}

if json_mode == "true":
    print(json.dumps(out, ensure_ascii=False))
    raise SystemExit(0)


def line(s=""):
    print(s)


line("context pack: %s" % (out["feature_id"] or out["spec_dir"] or "(no feature)"))
line("language: %s | gates: %s" % (
    config_slice["language_docs"],
    ", ".join("%s=%s" % kv for kv in sorted(config_slice["gates"].items())) or "(none)"))
line("budgets: %s" % (", ".join("%s=%s" % kv for kv in sorted(budgets.items())) or "(none set)"))
line("")
line("constitution (binding lines%s):" % (" - HEADINGS ONLY, open the file" if constitution_truncated else ""))
for c in constitution_lines:
    line("  - %s" % c)
line("")
f = map_slice["feature"]
if f:
    line("integration map:")
    line("  provides: %s" % (", ".join("%s %s" % (p.get("kind"), p.get("name")) for p in f["provides"]) or "none"))
    line("  consumes: %s" % (", ".join("%s %s <- %s" % (c.get("kind"), c.get("name"), c.get("from")) for c in f["consumes"]) or "none"))
    line("  depends_on: %s" % (", ".join(f["depends_on"]) or "none"))
    if map_slice["provided_to"]:
        line("  consumers that break if I change what I provide:")
        for p in map_slice["provided_to"]:
            line("    - %s consumes %s %s" % (p["consumer"], p["kind"], p["name"]))
    for j in map_slice["journeys"]:
        line("  journey %s: %s | test: %s" % (j["id"], j["description"], j["test"]))
else:
    line("integration map: no entry for this feature")
line("")
line("contracts (paths only - open one only if you are writing against it):")
for c in contracts["own"] + contracts["shared"]:
    line("  - %s" % c)
line("")
if adrs:
    line("ADRs:")
    for a in adrs:
        line("  - %s [%s] %s" % (a["title"], a["status"] or "?", a["path"]))
        if a["decision"]:
            line("      decision: %s" % a["decision"])
if architecture_sections:
    line("")
    line("architecture.md sections (read the one you need, not the file):")
    for s in architecture_sections:
        line("  - %s (%d lines)" % (s["title"], s["lines"]))
line("")
line("open questions: %d of %d total" % (len(open_questions), questions_total))
for q in open_questions:
    line("  - %s: %s" % (q["id"], q["text"] or "(no text)"))
line("open debt for this feature: %d" % len(open_debt))
for d in open_debt:
    line("  - %s: %s" % (d["id"], d["text"] or "(no text)"))
line("")
if artifacts:
    line("artifacts:")
    for a in artifacts:
        flag = " OVER BUDGET" if a["over_budget"] else ""
        line("  - %s (%d lines, budget %s)%s" % (a["path"], a["lines"], a["budget"] or "-", flag))
line("tasks: %s" % ", ".join("%s=%d" % kv for kv in sorted(task_counts.items())))
if next_task:
    line("next task: %s (%s)" % (next_task["id"], next_task["status"]))
PYEOF
status=$?
set -e

if [ "$status" -ne 0 ]; then
  cat "$result_file" >&2 2>/dev/null || true
  exit 2
fi

cat "$result_file"
exit 0

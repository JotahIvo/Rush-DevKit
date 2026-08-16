#!/usr/bin/env bash
# doctor.sh — Rush DevKit health diagnostic.
#
# See docs/internals/script-interfaces.md for the contract. Exit codes:
#   0 = no severity:error findings   1 = at least one severity:error finding
#   2 = usage error / internal failure (e.g. not inside a .rush project)
#
# Usage: doctor.sh [--json] [--fix-suggestions]

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
doctor.sh - Rush DevKit health diagnostic.

Checks: config.json validity (against config.schema.json when present),
scripts executable + syntactically valid, hooks referenced in
.claude/settings.json exist and are executable, commands.* resolve,
python3 availability, orphan specs / code without a spec (heuristic),
validate-integration-map.sh result, artifact budgets, stale questions.md /
debt.md entries (doctor.stale_days, default 14), and kit version.

Usage: doctor.sh [--json] [--fix-suggestions]

Options:
  --json              Print a single JSON object on stdout and nothing else.
  --fix-suggestions   Include a suggested remediation for each finding.
  -h, --help          Show this help and exit.

Exit codes:
  0  no severity:error findings
  1  at least one severity:error finding
  2  usage error or internal failure
EOF
}

JSON_OUT=0
FIX=0
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --json) JSON_OUT=1 ;;
    --fix-suggestions) FIX=1 ;;
    *)
      echo "doctor.sh: unknown argument: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "doctor.sh: python3 is required but was not found in PATH" >&2
  exit 2
fi

# Resolve project root by walking up from PWD looking for .rush/.
d="$PWD"
ROOT=""
while [ -n "$d" ]; do
  if [ -d "$d/.rush" ]; then ROOT="$d"; break; fi
  [ "$d" = "/" ] && break
  d="$(dirname "$d")"
done
if [ -z "$ROOT" ]; then
  echo "doctor.sh: no .rush/ directory found in $PWD or any parent" >&2
  exit 2
fi

python3 - "$ROOT" "$JSON_OUT" "$FIX" <<'PYEOF'
import datetime
import json
import os
import re
import shlex
import shutil
import subprocess
import sys

ROOT = sys.argv[1]
JSON_OUT = sys.argv[2] == "1"
FIX = sys.argv[3] == "1"

checks = []


def add(name, severity, ok, message, suggestion=None):
    # severity: "info" | "warning" | "error"
    checks.append({
        "name": name,
        "severity": severity,
        "ok": ok,
        "message": message,
        "suggestion": suggestion,
    })


def rel(p):
    try:
        return os.path.relpath(p, ROOT).replace(os.sep, "/")
    except Exception:
        return p


def read_json(path):
    try:
        with open(path, "r") as f:
            return json.load(f), None
    except FileNotFoundError:
        return None, "missing"
    except Exception as exc:
        return None, str(exc)


def cfg_get(cfg, dotted, default=None):
    cur = cfg
    for part in dotted.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return default
    return cur


# ---------------------------------------------------------------------------
# 1. config.json exists and validates against config.schema.json
# ---------------------------------------------------------------------------
cfg_path = os.path.join(ROOT, ".rush", "config.json")
schema_path = os.path.join(ROOT, ".rush", "config.schema.json")
cfg, cfg_err = read_json(cfg_path)

if cfg_err == "missing":
    add("config_exists", "error", False, ".rush/config.json not found.",
        "Run /rush-init to generate .rush/config.json.")
    cfg = {}
elif cfg_err:
    add("config_exists", "error", False,
        ".rush/config.json is not valid JSON: %s" % cfg_err,
        "Fix the JSON syntax in .rush/config.json.")
    cfg = {}
else:
    add("config_exists", "info", True, ".rush/config.json is present and valid JSON.")

if not os.path.isfile(schema_path):
    add("config_schema", "info", True,
        ".rush/config.schema.json not present yet — schema validation skipped.")
elif cfg_err:
    add("config_schema", "info", True,
        "config.json invalid — schema validation skipped.")
else:
    schema, schema_err = read_json(schema_path)
    if schema_err:
        add("config_schema", "warning", False,
            ".rush/config.schema.json is not valid JSON: %s" % schema_err,
            "Fix the JSON syntax in .rush/config.schema.json.")
    else:
        def validate(instance, schema, path="$"):
            errors = []
            if not isinstance(schema, dict):
                return errors
            if "type" in schema:
                t = schema["type"]
                types = t if isinstance(t, list) else [t]
                pytypes = {
                    "object": dict, "array": list, "string": str,
                    "number": (int, float), "integer": int,
                    "boolean": bool, "null": type(None),
                }
                ok = any(
                    isinstance(instance, pytypes[tt]) and not (
                        tt == "integer" and isinstance(instance, bool)
                    ) and not (
                        tt == "number" and isinstance(instance, bool)
                    )
                    for tt in types if tt in pytypes
                )
                if not ok:
                    errors.append("%s: expected type %s, got %s" % (
                        path, "/".join(types), type(instance).__name__))
                    return errors
            if "enum" in schema and instance not in schema["enum"]:
                errors.append("%s: value %r not in enum %r" % (
                    path, instance, schema["enum"]))
            if isinstance(instance, dict):
                for req in schema.get("required", []) or []:
                    if req not in instance:
                        errors.append("%s: missing required property %r" % (path, req))
                props = schema.get("properties", {}) or {}
                if schema.get("additionalProperties") is False:
                    extra = [k for k in instance if k not in props]
                    for k in extra:
                        errors.append("%s: unexpected property %r (additionalProperties: false)" % (path, k))
                for k, v in instance.items():
                    if k in props:
                        errors.extend(validate(v, props[k], path + "." + k))
            if isinstance(instance, list):
                items = schema.get("items")
                if isinstance(items, dict):
                    for i, v in enumerate(instance):
                        errors.extend(validate(v, items, "%s[%d]" % (path, i)))
            if isinstance(instance, str):
                pat = schema.get("pattern")
                if pat:
                    try:
                        if not re.search(pat, instance):
                            errors.append("%s: %r does not match pattern %r" % (
                                path, instance, pat))
                    except re.error:
                        pass
            if isinstance(instance, (int, float)) and not isinstance(instance, bool):
                if "minimum" in schema and instance < schema["minimum"]:
                    errors.append("%s: %r < minimum %r" % (path, instance, schema["minimum"]))
                if "maximum" in schema and instance > schema["maximum"]:
                    errors.append("%s: %r > maximum %r" % (path, instance, schema["maximum"]))
            return errors

        try:
            errors = validate(cfg, schema)
        except Exception as exc:
            errors = ["validator internal error: %s" % exc]
        if errors:
            add("config_schema", "error", False,
                "config.json violates config.schema.json:\n  - " + "\n  - ".join(errors[:20]),
                "Fix the listed fields in .rush/config.json.")
        else:
            add("config_schema", "info", True, "config.json matches config.schema.json.")

# ---------------------------------------------------------------------------
# 2. all .rush/scripts/*.sh (recursively) are executable and pass bash -n
# ---------------------------------------------------------------------------
scripts_dir = os.path.join(ROOT, ".rush", "scripts")
sh_files = []
if os.path.isdir(scripts_dir):
    for dirpath, dirnames, filenames in os.walk(scripts_dir):
        for fn in filenames:
            if fn.endswith(".sh"):
                sh_files.append(os.path.join(dirpath, fn))

bad_exec = []
bad_syntax = []
for sp in sorted(sh_files):
    if not os.access(sp, os.X_OK):
        bad_exec.append(rel(sp))
    try:
        proc = subprocess.run(["bash", "-n", sp], capture_output=True, text=True, timeout=15)
        if proc.returncode != 0:
            bad_syntax.append("%s: %s" % (rel(sp), proc.stderr.strip().splitlines()[-1] if proc.stderr.strip() else "syntax error"))
    except Exception as exc:
        bad_syntax.append("%s: could not run bash -n (%s)" % (rel(sp), exc))

if not sh_files:
    add("scripts_present", "warning", False, "No .sh files found under .rush/scripts/.",
        "Populate .rush/scripts/ with the kit's scripts.")
else:
    add("scripts_present", "info", True, "%d script(s) found under .rush/scripts/." % len(sh_files))

if bad_exec:
    add("scripts_executable", "error", False,
        "Not executable: " + ", ".join(bad_exec),
        "chmod +x " + " ".join(bad_exec))
elif sh_files:
    add("scripts_executable", "info", True, "All scripts are executable.")

if bad_syntax:
    add("scripts_syntax", "error", False,
        "bash -n failed for:\n  - " + "\n  - ".join(bad_syntax),
        "Fix the syntax errors listed above.")
elif sh_files:
    add("scripts_syntax", "info", True, "All scripts pass 'bash -n'.")

# ---------------------------------------------------------------------------
# 3. every hook referenced in .claude/settings.json exists and is executable
# ---------------------------------------------------------------------------
settings_path = os.path.join(ROOT, ".claude", "settings.json")
settings, settings_err = read_json(settings_path)
if settings_err == "missing":
    add("hooks_wired", "warning", False, ".claude/settings.json not found.",
        "Create .claude/settings.json to wire the .rush/hooks/*.sh scripts.")
elif settings_err:
    add("hooks_wired", "error", False,
        ".claude/settings.json is not valid JSON: %s" % settings_err,
        "Fix the JSON syntax in .claude/settings.json.")
else:
    missing_hooks = []
    total_hooks = 0
    hooks_cfg = settings.get("hooks", {}) if isinstance(settings, dict) else {}
    for event, groups in (hooks_cfg or {}).items():
        if not isinstance(groups, list):
            continue
        for group in groups:
            for h in (group.get("hooks", []) or []):
                cmd = h.get("command", "")
                if not cmd or h.get("type") != "command":
                    continue
                total_hooks += 1
                expanded = cmd.replace("${CLAUDE_PROJECT_DIR}", ROOT)
                try:
                    tokens = shlex.split(expanded)
                except ValueError:
                    tokens = expanded.split()
                script_path = tokens[0] if tokens else expanded
                if not os.path.isabs(script_path):
                    script_path = os.path.join(ROOT, script_path)
                if not os.path.isfile(script_path):
                    missing_hooks.append("%s (%s)" % (rel(script_path), event))
                elif not os.access(script_path, os.X_OK):
                    missing_hooks.append("%s (%s) not executable" % (rel(script_path), event))
    if missing_hooks:
        add("hooks_wired", "error", False,
            "Hook(s) referenced in .claude/settings.json are missing or not executable:\n  - "
            + "\n  - ".join(missing_hooks),
            "Create/chmod +x the missing hook script(s).")
    else:
        add("hooks_wired", "info", True,
            "%d hook command(s) in .claude/settings.json resolve." % total_hooks)

# ---------------------------------------------------------------------------
# 4. commands.* in config.json resolve
# ---------------------------------------------------------------------------
commands = cfg_get(cfg, "commands", {}) or {}
if not isinstance(commands, dict) or not commands:
    add("commands_resolve", "info", True, "No commands.* configured to check.")
else:
    unresolved = []
    for name, cmd in commands.items():
        if not isinstance(cmd, str) or not cmd.strip():
            continue
        try:
            tokens = shlex.split(cmd)
        except ValueError:
            tokens = cmd.split()
        if not tokens:
            continue
        exe = tokens[0]
        if exe in ("npm", "npx", "yarn", "pnpm", "python3", "python", "pip", "pip3"):
            if shutil.which(exe) is None:
                unresolved.append("%s: %r (%s not in PATH)" % (name, cmd, exe))
        elif shutil.which(exe) is None and not os.path.isfile(os.path.join(ROOT, exe)):
            unresolved.append("%s: %r (%s not found)" % (name, cmd, exe))
    if unresolved:
        add("commands_resolve", "warning", False,
            "commands.* that do not currently resolve:\n  - " + "\n  - ".join(unresolved),
            "Install the missing tool(s), or fix commands.* in .rush/config.json.")
    else:
        add("commands_resolve", "info", True, "All configured commands.* resolve.")

# ---------------------------------------------------------------------------
# 5. python3 availability (doctor.sh is itself running under python3, so this
#    is more about confirming it is the SAME python3 project scripts expect)
# ---------------------------------------------------------------------------
py3 = shutil.which("python3")
if py3:
    add("python3_available", "info", True, "python3 found at %s." % py3)
else:
    add("python3_available", "error", False, "python3 not found in PATH.",
        "Install python3 — it is required by every .rush/scripts/*.sh.")

# ---------------------------------------------------------------------------
# 6. orphan specs / code without a spec (heuristic, best-effort)
# ---------------------------------------------------------------------------
specs_dir = os.path.join(ROOT, "specs")
if not os.path.isdir(specs_dir):
    add("orphan_specs", "info", True, "No specs/ directory yet — nothing to check.")
else:
    feature_dirs = sorted(
        d for d in os.listdir(specs_dir)
        if os.path.isdir(os.path.join(specs_dir, d)) and d != "shared-contracts"
    )
    IGNORE_DIRS = {".git", "node_modules", ".rush", "specs", "dist", "build", "vendor"}

    def iter_repo_files():
        for dirpath, dirnames, filenames in os.walk(ROOT):
            dirnames[:] = [d for d in dirnames if d not in IGNORE_DIRS and not d.startswith(".")]
            for fn in filenames:
                yield os.path.join(dirpath, fn)

    orphans = []
    if feature_dirs:
        repo_files = list(iter_repo_files())
        for fd in feature_dirs:
            slug = re.sub(r"^\d+-", "", fd)
            found = False
            needles = [fd, slug]
            for fp in repo_files:
                try:
                    with open(fp, "r", errors="ignore") as f:
                        content = f.read()
                except Exception:
                    continue
                if any(n and n in content for n in needles):
                    found = True
                    break
            if not found:
                orphans.append(fd)
    if orphans:
        add("orphan_specs", "warning", False,
            "Spec dir(s) with no reference found anywhere else in the repo "
            "(heuristic — feature id/slug string match): " + ", ".join(orphans),
            "Confirm these features were actually implemented, or archive the spec.")
    else:
        add("orphan_specs", "info", True,
            "No orphan specs detected (%d feature dir(s) checked)." % len(feature_dirs))

add("code_without_spec", "info", True,
    "Not computed: detecting code with no corresponding spec requires a "
    "repo-specific source/feature mapping this heuristic does not have "
    "enough signal for. Skipped rather than guessed.")

# ---------------------------------------------------------------------------
# 7. validate-integration-map.sh
# ---------------------------------------------------------------------------
vim_path = os.path.join(ROOT, ".rush", "scripts", "validate-integration-map.sh")
if not os.path.isfile(vim_path):
    add("integration_map", "info", True, "validate-integration-map.sh not present yet — skipped.")
else:
    try:
        cmd = [vim_path, "--json"] if os.access(vim_path, os.X_OK) else ["bash", vim_path, "--json"]
        proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=60)
        if proc.returncode == 2:
            add("integration_map", "warning", False,
                "validate-integration-map.sh exited 2 (internal error): %s" % proc.stderr.strip()[-400:],
                "Investigate the script failure directly.")
        elif proc.returncode == 1:
            add("integration_map", "error", False,
                "validate-integration-map.sh found violations: %s" % proc.stdout.strip()[-800:],
                "Run .rush/scripts/validate-integration-map.sh to see details and fix the map.")
        elif proc.returncode == 0:
            add("integration_map", "info", True, "Integration map is valid.")
        else:
            add("integration_map", "warning", False,
                "validate-integration-map.sh exited unexpected code %d." % proc.returncode)
    except Exception as exc:
        add("integration_map", "warning", False,
            "Could not run validate-integration-map.sh: %s" % exc)

# ---------------------------------------------------------------------------
# 8. artifact budgets (validate-artifacts.sh --all)
# ---------------------------------------------------------------------------
va_path = os.path.join(ROOT, ".rush", "scripts", "validate-artifacts.sh")
if not os.path.isfile(va_path):
    add("artifact_budgets", "info", True, "validate-artifacts.sh not present yet — skipped.")
else:
    try:
        cmd = [va_path, "--all", "--json"] if os.access(va_path, os.X_OK) else ["bash", va_path, "--all", "--json"]
        proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=60)
        if proc.returncode == 1:
            add("artifact_budgets", "error", False,
                "validate-artifacts.sh --all found violations: %s" % proc.stdout.strip()[-800:],
                "Run .rush/scripts/validate-artifacts.sh --all to see details.")
        elif proc.returncode == 0:
            add("artifact_budgets", "info", True, "All artifacts within budget.")
        else:
            add("artifact_budgets", "warning", False,
                "validate-artifacts.sh --all exited unexpected code %d." % proc.returncode)
    except Exception as exc:
        add("artifact_budgets", "warning", False,
            "Could not run validate-artifacts.sh: %s" % exc)

# ---------------------------------------------------------------------------
# 9. stale questions.md / debt.md entries
# ---------------------------------------------------------------------------
stale_days = cfg_get(cfg, "doctor.stale_days", 14)
try:
    stale_days = int(stale_days)
except Exception:
    stale_days = 14

DATE_RE = re.compile(r"(\d{4}-\d{2}-\d{2})")


def stale_entries(path, today):
    if not os.path.isfile(path):
        return None, []
    try:
        with open(path, "r", errors="ignore") as f:
            lines = f.readlines()
    except Exception:
        return None, []
    stale = []
    for line in lines:
        m = DATE_RE.search(line)
        if not m:
            continue
        try:
            d = datetime.date.fromisoformat(m.group(1))
        except Exception:
            continue
        age = (today - d).days
        if age > stale_days:
            resolved = re.search(r"\b(answered|resolved|closed|done)\b", line, re.IGNORECASE)
            if not resolved:
                stale.append((line.strip()[:120], age))
    return lines, stale


today = datetime.date.today()
q_path = os.path.join(ROOT, ".rush", "memory", "questions.md")
d_path = os.path.join(ROOT, ".rush", "memory", "debt.md")

q_lines, q_stale = stale_entries(q_path, today)
if q_lines is None:
    add("questions_stale", "info", True, ".rush/memory/questions.md not present yet — skipped.")
elif q_stale:
    add("questions_stale", "warning", False,
        "%d entr(y/ies) in questions.md older than %d day(s):\n  - " % (len(q_stale), stale_days)
        + "\n  - ".join("%s (%dd)" % (t, a) for t, a in q_stale[:10]),
        "Answer or explicitly close these questions.")
else:
    add("questions_stale", "info", True, "No stale entries in questions.md.")

d_lines, d_stale = stale_entries(d_path, today)
if d_lines is None:
    add("debt_stale", "info", True, ".rush/memory/debt.md not present yet — skipped.")
elif d_stale:
    add("debt_stale", "warning", False,
        "%d item(s) in debt.md older than %d day(s):\n  - " % (len(d_stale), stale_days)
        + "\n  - ".join("%s (%dd)" % (t, a) for t, a in d_stale[:10]),
        "Triage these debt items: fix, schedule, or explicitly accept.")
else:
    add("debt_stale", "info", True, "No stale entries in debt.md.")

# ---------------------------------------------------------------------------
# 10. kit version
# ---------------------------------------------------------------------------
version_path = os.path.join(ROOT, ".rush", "VERSION")
if os.path.isfile(version_path):
    try:
        with open(version_path, "r") as f:
            v = f.read().strip()
        add("kit_version", "info", True, "Kit version: %s" % v)
    except Exception as exc:
        add("kit_version", "warning", False, "Could not read .rush/VERSION: %s" % exc)
else:
    add("kit_version", "warning", False, ".rush/VERSION not found.",
        "Create .rush/VERSION with the installed kit version.")

# ---------------------------------------------------------------------------
# Summarise and print
# ---------------------------------------------------------------------------
errors = [c for c in checks if c["severity"] == "error"]
warnings = [c for c in checks if c["severity"] == "warning"]
infos = [c for c in checks if c["severity"] == "info"]

result = {
    "ok": len(errors) == 0,
    "root": ROOT,
    "checks": checks,
    "summary": {"errors": len(errors), "warnings": len(warnings), "info": len(infos)},
}

if JSON_OUT:
    sys.stdout.write(json.dumps(result) + "\n")
else:
    icon = {"error": "[ERROR]", "warning": "[WARN] ", "info": "[OK]   "}
    for c in checks:
        print("%s %-22s %s" % (icon[c["severity"]], c["name"], c["message"].splitlines()[0]))
        for extra_line in c["message"].splitlines()[1:]:
            print("           %s" % extra_line)
        if FIX and c.get("suggestion") and not c["ok"]:
            print("           fix: %s" % c["suggestion"])
    print("")
    print("summary: %d error(s), %d warning(s), %d info" % (
        len(errors), len(warnings), len(infos)))

sys.exit(1 if errors else 0)
PYEOF
exit $?

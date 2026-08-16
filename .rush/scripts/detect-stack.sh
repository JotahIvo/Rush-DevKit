#!/usr/bin/env bash
# detect-stack.sh - deterministic stack detection. Never guesses via an
# LLM: every field comes from a file that exists on disk or from git
# history. Undetected fields are null, never inferred.
#
# Usage: detect-stack.sh [--json]
#
# Exit 0 always on a successful run (this is a report, not a check),
# 2 on usage or internal error.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: detect-stack.sh [--json]

Deterministic detection of language/runtime/package manager (from
lockfiles), framework and AI SDKs (from dependency names), test/build/
lint/format/typecheck commands (from package.json scripts, Makefile or
pyproject.toml), database/ORM, migrations directory, CI config files,
source/test file counts, and the real commit message convention (from
the last 100 `git log` subjects, not what CONTRIBUTING.md claims).

Fields that cannot be determined from disk/git are `null` - this script
never guesses.

  --json       Print a single JSON object on stdout, nothing else.
  -h, --help   Show this help.

Exit codes: 0 ok, 2 usage/internal error.
EOF
}

json_mode="false"
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true" ;;
    *) echo "detect-stack.sh: unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

root="$(rush_root)" || exit 2
py="$(rush_python)" || exit 2

# Git is bash's job, not Python's: gather the raw commit subjects here
# (last 100, oldest analysis point first doesn't matter - order is
# irrelevant to the ratio) and hand them to Python on stdin. In a fresh
# repo with no commits this is legitimately empty.
commit_log=""
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  commit_log="$(git -C "$root" log -n 100 --pretty=format:%s 2>/dev/null || true)"
fi

result_file="$(mktemp)"
trap 'rm -f "$result_file"' EXIT

# commit_log travels as argv, not stdin: stdin here is the Python source
# itself (fed via the heredoc below), so piping into it would be lost.
set +e
"$py" - "$root" "$commit_log" > "$result_file" <<'PYEOF'
import json, os, re, sys

root = sys.argv[1]
commit_log = sys.argv[2]


def exists(*parts):
    return os.path.exists(os.path.join(root, *parts))


def read(*parts):
    p = os.path.join(root, *parts)
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def read_json(*parts):
    text = read(*parts)
    if text is None:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


result = {
    "language": None,
    "runtime": None,
    "package_manager": None,
    "framework": None,
    "monorepo": False,
    "commands": {"test": None, "lint": None, "build": None, "format": None, "typecheck": None},
    "database": None,
    "orm": None,
    "migrations": None,
    "ci": [],
    "ai_sdks": None,
    "commit_convention": None,
    "preset_suggestion": None,
    "test_files": 0,
    "source_files": 0,
}

pkg = read_json("package.json")
has_node = isinstance(pkg, dict)

dep_keys = set()
scripts = {}
if has_node:
    for section in ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies"):
        deps = pkg.get(section)
        if isinstance(deps, dict):
            dep_keys.update(deps.keys())
    if isinstance(pkg.get("scripts"), dict):
        scripts = pkg["scripts"]

pyproject_text = read("pyproject.toml")
requirements_text = read("requirements.txt")
pipfile_text = read("Pipfile")
has_python = (
    pyproject_text is not None
    or requirements_text is not None
    or pipfile_text is not None
    or exists("manage.py")
)
py_haystack = " ".join(t.lower() for t in (pyproject_text, requirements_text, pipfile_text) if t)

go_mod = read("go.mod")
cargo_toml = read("Cargo.toml")
composer_json = read_json("composer.json")
gemfile = read("Gemfile")

# --- language / runtime / package manager -------------------------------
if has_node:
    result["runtime"] = "node"
    if exists("deno.json") or exists("deno.jsonc"):
        result["runtime"] = "deno"
    elif exists("bun.lockb"):
        result["runtime"] = "bun"
    if exists("pnpm-lock.yaml"):
        result["package_manager"] = "pnpm"
    elif exists("yarn.lock"):
        result["package_manager"] = "yarn"
    elif exists("bun.lockb"):
        result["package_manager"] = "bun"
    elif exists("package-lock.json"):
        result["package_manager"] = "npm"
    # A project can be TypeScript without a tsconfig at the root (monorepo package,
    # framework-managed config), so also probe for real .ts sources before deciding.
    # Getting this wrong silently zeroes the file counts below.
    def _has_ts_sources():
        # Local exclusion set: EXCLUDE_DIR_NAMES is defined further down, after this runs.
        skip = ("node_modules", "dist", "build", "out", "vendor", "coverage", "tmp")
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [
                d for d in dirnames if d not in skip and not d.startswith(".")
            ]
            for fn in filenames:
                if fn.endswith((".ts", ".tsx")) and not fn.endswith(".d.ts"):
                    return True
        return False

    has_ts = exists("tsconfig.json") or "typescript" in dep_keys or _has_ts_sources()
    result["language"] = "typescript" if has_ts else "javascript"
elif has_python:
    result["language"] = "python"
    result["runtime"] = "python"
    if exists("poetry.lock"):
        result["package_manager"] = "poetry"
    elif exists("uv.lock"):
        result["package_manager"] = "uv"
    elif exists("Pipfile.lock"):
        result["package_manager"] = "pipenv"
    elif requirements_text is not None or pyproject_text is not None:
        result["package_manager"] = "pip"
elif go_mod is not None:
    result["language"] = "go"
    result["runtime"] = "go"
    result["package_manager"] = "go modules"
elif cargo_toml is not None:
    result["language"] = "rust"
    result["runtime"] = "rust"
    result["package_manager"] = "cargo"
elif composer_json is not None:
    result["language"] = "php"
    result["runtime"] = "php"
    result["package_manager"] = "composer"
elif gemfile is not None:
    result["language"] = "ruby"
    result["runtime"] = "ruby"
    result["package_manager"] = "bundler"

# --- monorepo -------------------------------------------------------------
monorepo = False
if has_node and isinstance(pkg.get("workspaces"), (list, dict)):
    monorepo = True
if exists("pnpm-workspace.yaml") or exists("lerna.json") or exists("turbo.json") or exists("nx.json"):
    monorepo = True
result["monorepo"] = monorepo

# --- framework --------------------------------------------------------
NODE_FRAMEWORKS = [
    ("next", "nextjs"),
    ("nuxt", "nuxt"),
    ("nuxt3", "nuxt"),
    ("@nestjs/core", "nestjs"),
    ("@angular/core", "angular"),
    ("@sveltejs/kit", "sveltekit"),
    ("svelte", "svelte"),
    ("remix", "remix"),
    ("@remix-run/react", "remix"),
    ("fastify", "fastify"),
    ("express", "express"),
    ("vue", "vue"),
    ("react", "react"),
]
PY_FRAMEWORK_MARKERS = [("django", "django"), ("fastapi", "fastapi"), ("flask", "flask"), ("pyramid", "pyramid")]

framework = None
if has_node:
    for pkgname, fw in NODE_FRAMEWORKS:
        if pkgname in dep_keys:
            framework = fw
            break
elif has_python:
    for marker, fw in PY_FRAMEWORK_MARKERS:
        if re.search(r"\b" + re.escape(marker) + r"\b", py_haystack):
            framework = fw
            break
    if framework is None and exists("manage.py"):
        framework = "django"
elif gemfile is not None and re.search(r"\brails\b", gemfile, re.IGNORECASE):
    framework = "rails"
result["framework"] = framework

# --- database / orm ----------------------------------------------------
NODE_ORMS = [
    ("prisma", "prisma"),
    ("@prisma/client", "prisma"),
    ("typeorm", "typeorm"),
    ("sequelize", "sequelize"),
    ("drizzle-orm", "drizzle"),
    ("mongoose", "mongoose"),
    ("knex", "knex"),
]

orm = None
database = None
if has_node:
    for pkgname, o in NODE_ORMS:
        if pkgname in dep_keys:
            orm = o
            break
    if orm == "mongoose":
        database = "mongodb"
    if database is None:
        for pkgname, db in (
            ("pg", "postgresql"),
            ("mysql2", "mysql"),
            ("mysql", "mysql"),
            ("better-sqlite3", "sqlite"),
            ("sqlite3", "sqlite"),
        ):
            if pkgname in dep_keys:
                database = db
                break
elif has_python:
    if re.search(r"\bsqlalchemy\b", py_haystack):
        orm = "sqlalchemy"
    elif re.search(r"\btortoise-orm\b", py_haystack):
        orm = "tortoise"
    elif re.search(r"\bpeewee\b", py_haystack):
        orm = "peewee"
    elif framework == "django":
        orm = "django-orm"
    for marker, db in (
        ("psycopg2", "postgresql"),
        ("psycopg", "postgresql"),
        ("pymysql", "mysql"),
        ("mysqlclient", "mysql"),
        ("asyncpg", "postgresql"),
    ):
        if marker in py_haystack:
            database = db
            break

if orm == "prisma":
    schema = read("prisma", "schema.prisma")
    if schema:
        m = re.search(r'datasource\s+\w+\s*\{[^}]*?provider\s*=\s*"([^"]+)"', schema, re.DOTALL)
        if m:
            database = m.group(1)

result["orm"] = orm
result["database"] = database

# --- migrations dir -----------------------------------------------------
for candidate in ("prisma/migrations", "migrations", "db/migrations", "src/migrations", "alembic/versions"):
    if exists(*candidate.split("/")):
        result["migrations"] = candidate
        break

# --- CI -------------------------------------------------------------------
ci_files = []
gh_dir = os.path.join(root, ".github", "workflows")
if os.path.isdir(gh_dir):
    for name in sorted(os.listdir(gh_dir)):
        if name.endswith((".yml", ".yaml")):
            ci_files.append("/".join([".github", "workflows", name]))
for candidate in (".gitlab-ci.yml", ".circleci/config.yml", "Jenkinsfile", "azure-pipelines.yml", ".drone.yml"):
    if exists(*candidate.split("/")):
        ci_files.append(candidate)
result["ci"] = ci_files

# --- AI SDKs --------------------------------------------------------------
AI_NODE_PKGS = [
    "@anthropic-ai/sdk",
    "openai",
    "@google/generative-ai",
    "@google-cloud/vertexai",
    "langchain",
    "@langchain/core",
    "@langchain/community",
    "llamaindex",
    "cohere-ai",
    "@aws-sdk/client-bedrock-runtime",
    "groq-sdk",
    "ollama",
]
AI_PY_PKGS = [
    "anthropic",
    "openai",
    "langchain",
    "llama-index",
    "llama_index",
    "google-generativeai",
    "google-cloud-aiplatform",
    "cohere",
    "ollama",
    "groq",
]

if has_node:
    result["ai_sdks"] = sorted(p for p in AI_NODE_PKGS if p in dep_keys)
elif has_python:
    result["ai_sdks"] = sorted(
        marker for marker in AI_PY_PKGS if re.search(r"\b" + re.escape(marker.lower()) + r"\b", py_haystack)
    )

# --- commands ---------------------------------------------------------
def node_run(script_name, pm):
    if script_name == "test" and pm in (None, "npm"):
        return "npm test"
    pm = pm or "npm"
    if pm == "npm":
        return "npm run %s" % script_name
    if pm == "yarn":
        return "yarn %s" % script_name
    if pm == "pnpm":
        return "pnpm %s" % script_name
    if pm == "bun":
        return "bun run %s" % script_name
    return "%s run %s" % (pm, script_name)


if has_node:
    pm = result["package_manager"]
    for key, aliases in (
        ("test", ["test"]),
        ("lint", ["lint"]),
        ("build", ["build"]),
        ("format", ["format", "fmt"]),
        ("typecheck", ["typecheck", "type-check"]),
    ):
        for alias in aliases:
            if alias in scripts:
                result["commands"][key] = node_run(alias, pm)
                break
    if result["commands"]["typecheck"] is None and exists("tsconfig.json"):
        result["commands"]["typecheck"] = "npx tsc --noEmit"
elif has_python:
    makefile = read("Makefile")
    make_targets = set()
    if makefile:
        for m in re.finditer(r"^([A-Za-z0-9_-]+)\s*:", makefile, re.MULTILINE):
            make_targets.add(m.group(1))
    for key, aliases in (
        ("test", ["test"]),
        ("lint", ["lint"]),
        ("build", ["build"]),
        ("format", ["format", "fmt"]),
        ("typecheck", ["typecheck", "type-check"]),
    ):
        for alias in aliases:
            if alias in make_targets:
                result["commands"][key] = "make %s" % alias
                break
    if result["commands"]["test"] is None and ("pytest" in py_haystack or exists("pytest.ini") or exists("tests")):
        result["commands"]["test"] = "pytest"
    if result["commands"]["lint"] is None:
        if "ruff" in py_haystack:
            result["commands"]["lint"] = "ruff check ."
        elif "flake8" in py_haystack:
            result["commands"]["lint"] = "flake8"
    if result["commands"]["format"] is None and "black" in py_haystack:
        result["commands"]["format"] = "black ."
    if result["commands"]["typecheck"] is None and "mypy" in py_haystack:
        result["commands"]["typecheck"] = "mypy ."

# --- source / test file counts -----------------------------------------
LANG_EXTENSIONS = {
    "typescript": [".ts", ".tsx", ".js", ".jsx"],
    "javascript": [".js", ".jsx", ".mjs", ".cjs"],
    "python": [".py"],
    "go": [".go"],
    "rust": [".rs"],
    "php": [".php"],
    "ruby": [".rb"],
}
EXCLUDE_DIR_NAMES = {
    "node_modules", "dist", "build", "out", "coverage", "vendor",
    "venv", ".venv", "env", "__pycache__", ".tox", "target", ".turbo",
    ".next", ".nuxt", ".git", ".rush",
}
TEST_NAME_RE = re.compile(r"(\.test\.|\.spec\.|_test\.|_spec\.|^test_|^conftest\.)", re.IGNORECASE)

exts = LANG_EXTENSIONS.get(result["language"], [])
test_files = 0
source_files = 0
if exts:
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIR_NAMES and not d.startswith(".")]
        base_dir = os.path.basename(dirpath)
        in_test_dir = base_dir in ("test", "tests", "__tests__", "spec")
        for fn in filenames:
            _, ext = os.path.splitext(fn)
            if ext.lower() not in exts:
                continue
            if in_test_dir or TEST_NAME_RE.search(fn):
                test_files += 1
            else:
                source_files += 1
result["test_files"] = test_files
result["source_files"] = source_files

# --- commit convention (the real pattern, not the declared one) -----------
subjects = [s for s in commit_log.split("\n") if s.strip() != ""]
if subjects:
    sample = len(subjects)
    conv_re = re.compile(r"^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)(\([^)]+\))?!?:\s+\S")
    conv_count = sum(1 for s in subjects if conv_re.match(s))
    conv_ratio = conv_count / sample
    gitmoji_re = re.compile(r"^[\U0001F300-\U0001FAFF☀-➿]")
    gitmoji_count = sum(1 for s in subjects if gitmoji_re.match(s))
    gitmoji_ratio = gitmoji_count / sample
    if conv_ratio >= 0.6:
        result["commit_convention"] = {"detected": "conventional", "confidence": round(conv_ratio, 2), "sample": sample}
    elif gitmoji_ratio >= 0.6:
        result["commit_convention"] = {"detected": "gitmoji", "confidence": round(gitmoji_ratio, 2), "sample": sample}
    else:
        best = max(conv_ratio, gitmoji_ratio)
        result["commit_convention"] = {"detected": "freeform", "confidence": round(1 - best, 2), "sample": sample}
else:
    result["commit_convention"] = None

# --- preset suggestion: match .rush/presets/*.json on framework+orm -------
preset_suggestion = None
presets_dir = os.path.join(root, ".rush", "presets")
if os.path.isdir(presets_dir):
    candidates = []
    for name in sorted(os.listdir(presets_dir)):
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(presets_dir, name), encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue
        match = data.get("match") if isinstance(data, dict) else None
        if not isinstance(match, dict) or not match:
            continue
        # A preset's `match` block is {dependencies: [...], files: [...], lockfiles: [...]}.
        # Scoring, not equality: dependencies are the strong signal (a project rarely has
        # another stack's core packages), files are supporting evidence, and lockfiles are
        # weak on their own (every npm project has one), so they only break ties.
        score = 0
        dep_hits = 0
        for dep in match.get("dependencies", []) or []:
            if dep in dep_keys:
                dep_hits += 1
        score += dep_hits * 3
        for rel in match.get("files", []) or []:
            if exists(*rel.split("/")):
                score += 2
        for lock in match.get("lockfiles", []) or []:
            if exists(lock):
                score += 1
                break
        # Require real evidence: at least one core dependency, or a signature file.
        has_file_evidence = any(
            exists(*rel.split("/")) for rel in (match.get("files", []) or [])
        )
        if dep_hits > 0 or has_file_evidence:
            candidates.append((score, name[:-5]))
    if candidates:
        candidates.sort(key=lambda t: (-t[0], t[1]))
        preset_suggestion = candidates[0][1]
result["preset_suggestion"] = preset_suggestion

print(json.dumps(result, ensure_ascii=False))
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
  "$py" - "$payload" <<'PYEOF'
import json, sys

data = json.loads(sys.argv[1])


def show(v):
    return "null" if v is None else v


print("language:        %s" % show(data["language"]))
print("runtime:         %s" % show(data["runtime"]))
print("package manager: %s" % show(data["package_manager"]))
print("framework:       %s" % show(data["framework"]))
print("monorepo:        %s" % data["monorepo"])
print("database/orm:    %s / %s" % (show(data["database"]), show(data["orm"])))
print("migrations:      %s" % show(data["migrations"]))
print("ci:              %s" % (", ".join(data["ci"]) if data["ci"] else "none"))
print("ai sdks:         %s" % (", ".join(data["ai_sdks"]) if data["ai_sdks"] else show(data["ai_sdks"])))
cc = data["commit_convention"]
if cc:
    print("commit style:    %s (confidence %.2f, sample %d)" % (cc["detected"], cc["confidence"], cc["sample"]))
else:
    print("commit style:    null (no commits)")
print("preset:          %s" % show(data["preset_suggestion"]))
print("source files:    %d (tests: %d)" % (data["source_files"], data["test_files"]))
print("commands:")
for k, v in data["commands"].items():
    print("  %-10s %s" % (k + ":", show(v)))
PYEOF
fi

exit 0

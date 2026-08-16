#!/usr/bin/env bash
# secret-scan.sh - regex-based secret detection (provider key formats,
# PEM private key blocks, high-entropy generic assignments).
#
# Usage: secret-scan.sh [--staged|--paths "a b c"] [--json]
#
# Exit 0 no findings, 1 findings, 2 usage/internal error.
set -euo pipefail

. "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: secret-scan.sh [--staged|--paths "a b c"] [--json]

Scans for likely secrets: AWS access/secret keys, GitHub/GitLab tokens,
Slack tokens, Google API keys, PEM private key blocks, and generic
password|secret|token|api_key assignments whose value has high entropy.

  --staged       Scan only added lines of `git diff --cached` (pre-commit
                  use case).
  --paths "..."  Scan this space-separated list of paths instead of the
                  whole tree.
  (no flag)      Scan every git-tracked file (or, outside a git repo,
                  every file under the project root).

Lockfiles, minified files (*.min.js/css or very long lines) and binary
files are skipped, as are findings matched by .rush/secret-scan-allow
(one regex per line, matched against the finding's source line) and
obvious placeholders (xxx, changeme, <your-key>, example, ...).

  --json       Print a single JSON object on stdout, nothing else.
  -h, --help   Show this help.

Exit codes: 0 no findings, 1 findings, 2 usage/internal error.
EOF
}

json_mode="false"
mode="tree"
paths_arg=""
expect_paths_value="false"
for arg in "$@"; do
  if [ "$expect_paths_value" = "true" ]; then
    paths_arg="$arg"
    expect_paths_value="false"
    continue
  fi
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --json) json_mode="true" ;;
    --staged) mode="staged" ;;
    --paths=*) mode="paths"; paths_arg="${arg#--paths=}" ;;
    --paths) mode="paths"; expect_paths_value="true" ;;
    -*) echo "secret-scan.sh: unknown option: $arg" >&2; usage >&2; exit 2 ;;
    *) echo "secret-scan.sh: unexpected extra argument: $arg" >&2; exit 2 ;;
  esac
done
if [ "$expect_paths_value" = "true" ]; then
  echo "secret-scan.sh: --paths requires an argument" >&2
  exit 2
fi

root="$(rush_root)" || exit 2

result_file="$(mktemp)"
diff_file="$(mktemp)"
trap 'rm -f "$result_file" "$diff_file"' EXIT

if [ "$mode" = "staged" ]; then
  (cd "$root" && git diff --cached -U0) > "$diff_file" 2>/dev/null
  diff_status=$?
  if [ "$diff_status" -ne 0 ]; then
    echo "secret-scan.sh: 'git diff --cached' failed (not a git repo?)" >&2
    exit 2
  fi
fi

scan_py() {
"$(rush_python)" - "$root" "$mode" "$paths_arg" "$diff_file" > "$result_file" <<'PYEOF'
import json, math, os, re, subprocess, sys

root, mode, paths_arg, diff_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

LOCKFILES = {
    "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "Gemfile.lock",
    "poetry.lock", "Cargo.lock", "composer.lock", "go.sum", "Pipfile.lock",
    "mix.lock",
}

PLACEHOLDER_VALUES = {
    "xxx", "xxxx", "xxxxx", "changeme", "change_me", "example",
    "your-key", "your-key-here", "your_api_key", "yourkey", "placeholder",
    "dummy", "test", "testing", "fake", "sample", "todo", "redacted",
    "null", "none", "undefined", "insert_key_here", "replace_me",
    "secret", "password", "token", "apikey", "api_key",
}

RULES = [
    ("aws_access_key_id", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("aws_secret_access_key", re.compile(
        r"(?i)aws[a-z_]*secret[a-z_]*\s*[:=]\s*['\"]?[A-Za-z0-9/+=]{40}['\"]?")),
    ("github_token", re.compile(r"gh[pousr]_[A-Za-z0-9]{36,}")),
    ("gitlab_token", re.compile(r"glpat-[A-Za-z0-9\-_]{20,}")),
    ("slack_token", re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}")),
    ("google_api_key", re.compile(r"AIza[0-9A-Za-z\-_]{35}")),
    ("private_key_pem", re.compile(
        r"-----BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----")),
]

GENERIC_RE = re.compile(
    r"(?i)\b(password|passwd|secret|token|api[_-]?key)\b\s*[:=]\s*"
    r"['\"]?([A-Za-z0-9/+_\-\.]{12,})['\"]?"
)

MINIFIED_NAME_RE = re.compile(r"\.min\.(js|css)$", re.IGNORECASE)

def is_lockfile(name):
    return name in LOCKFILES

def looks_binary(data):
    return b"\x00" in data[:8192]

def shannon_entropy(s):
    if not s:
        return 0.0
    freq = {}
    for c in s:
        freq[c] = freq.get(c, 0) + 1
    n = len(s)
    ent = 0.0
    for c in freq.values():
        p = c / n
        ent -= p * math.log2(p)
    return ent

def is_placeholder(value):
    v = value.strip().strip("'\"").lower()
    if v in PLACEHOLDER_VALUES:
        return True
    if re.fullmatch(r"[<{].*[>}]", v):
        return True
    if re.fullmatch(r"x{3,}", v):
        return True
    if re.fullmatch(r"\*{3,}", v):
        return True
    if len(set(v)) <= 2:
        return True
    return False

def load_allowlist():
    p = os.path.join(root, ".rush", "secret-scan-allow")
    patterns = []
    if os.path.isfile(p):
        with open(p, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                try:
                    patterns.append(re.compile(line))
                except re.error:
                    continue
    return patterns

ALLOW = load_allowlist()

def is_allowed(line):
    return any(p.search(line) for p in ALLOW)

def scan_line(line):
    hits = []
    for rule, pattern in RULES:
        m = pattern.search(line)
        if m:
            hits.append((rule, m.group(0)))
    m = GENERIC_RE.search(line)
    if m:
        value = m.group(2)
        if not is_placeholder(value) and shannon_entropy(value) >= 3.3:
            hits.append(("generic_high_entropy_assignment", m.group(0)))
    return hits

def mask(text):
    if len(text) <= 8:
        return text[:2] + "***"
    return text[:6] + "..." + "(%d chars)" % len(text)

findings = []
scanned = 0

def process_text(rel_path, text):
    global scanned
    base = os.path.basename(rel_path)
    if is_lockfile(base) or MINIFIED_NAME_RE.search(base):
        return
    scanned += 1
    for i, line in enumerate(text.split("\n"), start=1):
        if len(line) > 2000:
            continue  # heuristic: skip minified / generated long lines
        if is_allowed(line):
            continue
        for rule, matched in scan_line(line):
            findings.append({
                "file": rel_path, "line": i, "rule": rule,
                "match": mask(matched), "severity": "error",
            })

def read_text_file(path):
    try:
        with open(path, "rb") as f:
            data = f.read()
    except Exception:
        return None
    if looks_binary(data):
        return None
    return data.decode("utf-8", errors="replace")

if mode == "staged":
    with open(diff_file, encoding="utf-8", errors="replace") as f:
        diff_text = f.read()
    current_file = None
    for line in diff_text.split("\n"):
        if line.startswith("+++ "):
            p = line[4:].strip()
            if p.startswith("b/"):
                p = p[2:]
            current_file = None if p == "/dev/null" else p
            continue
        if line.startswith("+") and not line.startswith("+++"):
            if current_file is None:
                continue
            content = line[1:]
            base = os.path.basename(current_file)
            if is_lockfile(base) or MINIFIED_NAME_RE.search(base):
                continue
            if is_allowed(content):
                continue
            for rule, matched in scan_line(content):
                findings.append({
                    "file": current_file, "line": None, "rule": rule,
                    "match": mask(matched), "severity": "error",
                })
    scanned = len({f["file"] for f in findings}) if findings else 0
elif mode == "paths":
    targets = [p for p in paths_arg.split() if p]
    for rel in targets:
        p = os.path.join(root, rel)
        if os.path.isdir(p):
            for dirpath, dirnames, filenames in os.walk(p):
                if ".git" in dirnames:
                    dirnames.remove(".git")
                for fn in filenames:
                    fp = os.path.join(dirpath, fn)
                    text = read_text_file(fp)
                    if text is not None:
                        process_text(os.path.relpath(fp, root), text)
        elif os.path.isfile(p):
            text = read_text_file(p)
            if text is not None:
                process_text(rel, text)
else:
    files = None
    try:
        proc = subprocess.run(["git", "ls-files"], cwd=root,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if proc.returncode == 0:
            files = [f for f in proc.stdout.split("\n") if f.strip()]
    except Exception:
        files = None
    if files is None:
        files = []
        for dirpath, dirnames, filenames in os.walk(root):
            if ".git" in dirnames:
                dirnames.remove(".git")
            for fn in filenames:
                files.append(os.path.relpath(os.path.join(dirpath, fn), root))
    for rel in files:
        p = os.path.join(root, rel)
        text = read_text_file(p)
        if text is not None:
            process_text(rel, text)

ok = len(findings) == 0
out = {"ok": ok, "mode": mode, "scanned_files": scanned, "findings": findings,
       "summary": {"findings": len(findings)}}
print(json.dumps(out))
PYEOF
}

set +e
scan_py < /dev/null
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
print("secret-scan (%s): %d file(s) scanned" % (data["mode"], data["scanned_files"]))
if not data["findings"]:
    print("OK: no findings")
else:
    for f in data["findings"]:
        loc = "%s:%s" % (f["file"], f["line"] if f["line"] is not None else "?")
        print("[%s] %s -> %s" % (f["rule"], loc, f["match"]))
    print("%d finding(s)" % len(data["findings"]))
PYEOF
fi

ok="$("$(rush_python)" -c "import json,sys; print(json.loads(sys.argv[1])['ok'])" "$payload")"
if [ "$ok" = "True" ]; then
  exit 0
else
  exit 1
fi

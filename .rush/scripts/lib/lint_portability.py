#!/usr/bin/env python3
"""Static portability checks for the kit's shell scripts (macOS bash 3.2).

Kept as a real Python file rather than an inline heredoc for the obvious
reason: this module's whole job is to detect the hazards of inline heredocs,
and it needs literal backticks in its own patterns to do so.

Run via .rush/scripts/lint-shell-portability.sh.
"""

from __future__ import annotations

import json
import os
import re
import sys

BACKTICK = chr(96)

# A heredoc opener: <<EOF, <<-EOF, <<'EOF', <<"EOF"
HEREDOC_OPEN = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")

BASH4 = [
    (re.compile(r"^\s*mapfile\b|[|;&]\s*mapfile\b"), "mapfile is bash 4+"),
    (re.compile(r"^\s*readarray\b|[|;&]\s*readarray\b"), "readarray is bash 4+"),
    (re.compile(r"declare\s+-A\b"), "associative arrays are bash 4+"),
    (re.compile(r"\$\{[A-Za-z_][A-Za-z0-9_]*,,"), "${var,,} is bash 4+"),
    (re.compile(r"\$\{[A-Za-z_][A-Za-z0-9_]*\^\^"), "${var^^} is bash 4+"),
]

GNU_ONLY = [
    (re.compile(r"\bgrep\s+(-[A-Za-z]*\s+)*-[A-Za-z]*P\b"), "grep -P is GNU-only"),
    (re.compile(r"\bsed\s+-i\s+(-e|[^.'\"\s-])"), "sed -i needs a backup suffix on BSD"),
    (re.compile(r"\bsed\s+-i\s*$"), "sed -i needs a backup suffix on BSD"),
    (re.compile(r"\bdate\s+-d\b"), "date -d is GNU-only"),
    (re.compile(r"\breadlink\s+-f\b"), "readlink -f is GNU-only"),
    (re.compile(r"(^|[|;&(]\s*)timeout\s+\d"), "the timeout binary is absent on stock macOS"),
]


def strip_comment(line: str) -> str:
    """Drop a trailing shell comment. Crude but adequate: bash discards
    comments before parsing, so hazards inside them are not real hazards, and
    flagging them trains people to ignore the linter."""
    out = []
    quote = None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = None
            out.append(ch)
            continue
        if ch in "'\"":
            quote = ch
            out.append(ch)
            continue
        if ch == "#" and (i == 0 or line[i - 1] in " \t"):
            break
        out.append(ch)
    return "".join(out)


def scan(path: str):
    """Return a list of violation dicts for one shell script."""
    violations = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    except OSError as exc:
        return [{"file": path, "line": 0, "rule": "unreadable",
                 "message": str(exc), "severity": "error"}]

    heredoc_delim = None          # inside a heredoc body when set
    heredoc_start = 0
    heredoc_in_subst = False

    for n, raw in enumerate(lines, 1):
        if heredoc_delim is not None:
            if raw.strip() == heredoc_delim:
                heredoc_delim = None
                heredoc_in_subst = False
                continue
            # Only flagged inside a command substitution: that combination is
            # what actually breaks bash 3.2. A backtick in an ordinary heredoc
            # (every usage() block has one) is harmless, and warning on it would
            # produce 20 findings nobody reads - the kit retires checks that
            # never catch a real failure instead of shipping noise.
            if heredoc_in_subst and BACKTICK in raw:
                violations.append({
                    "file": path, "line": n,
                    "rule": "heredoc_in_command_substitution",
                    "message": ("literal backtick inside a heredoc that is inside "
                                "$( ) - bash 3.2 cannot parse this file at all"),
                    "severity": "error",
                })
            continue

        code = strip_comment(raw)
        if not code.strip():
            continue

        m = HEREDOC_OPEN.search(code)
        if m:
            heredoc_delim = m.group(2)
            heredoc_start = n
            before = code[: m.start()]
            # Opened inside a command substitution on the same line: the classic
            # PYCODE=$(cat <<'PYEOF' ... ) construct.
            heredoc_in_subst = before.count("$(") > before.count(")")
            if heredoc_in_subst:
                violations.append({
                    "file": path, "line": n, "rule": "heredoc_in_command_substitution",
                    "message": (
                        "heredoc opened inside $( ) — bash 3.2 mis-parses the body. "
                        "Write it to a temp file: cat > \"$F\" <<'EOF' ... EOF"
                    ),
                    "severity": "error",
                })
            continue

        for pattern, why in BASH4:
            if pattern.search(code):
                violations.append({"file": path, "line": n, "rule": "bash4_builtin",
                                   "message": why, "severity": "error"})
        for pattern, why in GNU_ONLY:
            if pattern.search(code):
                violations.append({"file": path, "line": n, "rule": "gnu_only_flag",
                                   "message": why, "severity": "error"})

    if heredoc_delim is not None:
        violations.append({
            "file": path, "line": heredoc_start, "rule": "unterminated_heredoc",
            "message": "heredoc '%s' is never closed" % heredoc_delim,
            "severity": "error",
        })
    return violations


def collect(root: str, args):
    if args:
        # Explicit paths are always scanned, including fixtures: that is how the
        # eval proves the linter still detects the hazard.
        return [a for a in args if a.endswith(".sh")]
    found = []
    # Eval fixtures are deliberately broken samples, not shipped code. Scanning
    # them by default would make the linter permanently red and train everyone
    # to ignore it.
    skip_prefix = os.path.join(root, ".rush", "evals", "fixtures")
    for base in (os.path.join(root, ".rush"),):
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if not d.startswith(".")]
            if dirpath.startswith(skip_prefix):
                continue
            for fn in sorted(filenames):
                if fn.endswith(".sh"):
                    found.append(os.path.join(dirpath, fn))
    install = os.path.join(root, "install.sh")
    if os.path.isfile(install):
        found.append(install)
    return sorted(found)


def main() -> int:
    json_mode = sys.argv[1] == "true"
    root = sys.argv[2]
    files = collect(root, sys.argv[3:])

    violations = []
    for f in files:
        violations.extend(scan(f))

    errors = [v for v in violations if v["severity"] == "error"]
    for v in violations:
        v["file"] = os.path.relpath(v["file"], root)

    if json_mode:
        print(json.dumps({
            "ok": not errors,
            "scanned": len(files),
            "violations": violations,
        }))
    else:
        if not violations:
            sys.stderr.write("portability: clean (%d files)\n" % len(files))
        for v in violations:
            sys.stderr.write("%s:%s [%s] %s: %s\n" % (
                v["file"], v["line"], v["severity"], v["rule"], v["message"]))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""check_process_leak.py — deterministic checker for the rush-spec eval suite.

Scans a spec.md for agent-process instructions (harness configuration, e.g. "run the test
suite", "commit at the end") that must never appear in a spec: they belong in .rush/config.json
or the implementing agent's own guardrails, never in the WHAT artifact. See
docs/internals/kit-conventions.md, "Fronteira O QUE / COMO" and rush-spec's SKILL.md Guardrail 6.

Usage: check_process_leak.py <spec.md>
Exit 0: no process-instruction phrase found (the spec is clean).
Exit 1: at least one phrase found (printed, one per line) — the WHAT/HOW boundary was violated.
"""
import re
import sys

PATTERNS = [
    r"run the tests?",
    r"run the test suite",
    r"\bcommit\b.{0,20}\b(the|this|at the end|result)\b",
    r"\bgit (commit|push)\b",
    r"\bnpm (test|run)\b",
]

def main():
    if len(sys.argv) != 2:
        print("usage: check_process_leak.py <spec.md>", file=sys.stderr)
        return 2
    with open(sys.argv[1], encoding="utf-8") as f:
        text = f.read()

    hits = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        for pat in PATTERNS:
            if re.search(pat, line, re.IGNORECASE):
                hits.append("line %d: %s" % (line_no, line.strip()))
                break

    if hits:
        print("PROCESS_INSTRUCTIONS_FOUND:")
        for h in hits:
            print("  " + h)
        return 1
    print("clean: no agent-process instructions found")
    return 0

if __name__ == "__main__":
    sys.exit(main())

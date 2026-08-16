#!/usr/bin/env python3
"""check_ac_coverage.py — deterministic checker shared by the rush-spec and rush-analyze eval
suites.

Cross-references spec.md's numbered "## Acceptance Criteria" list against done-contract.md's
"## Acceptance Criteria Coverage" markdown table. Every acceptance criterion in spec.md must have
a row in that table (mapping it to a check name or a human gate) — see rush-spec's SKILL.md
process step 7 ("Every acceptance criterion must be traceable...") and rush-analyze's SKILL.md
process step 3 ("Uncovered acceptance criteria").

Usage: check_ac_coverage.py <spec.md> <done-contract.md>
Exit 0: every acceptance criterion in spec.md has a coverage row.
Exit 1: at least one acceptance criterion is uncovered (printed).
Exit 2: usage/parse error.
"""
import re
import sys


def acceptance_criteria_numbers(spec_text):
    m = re.search(r"^##\s*Acceptance Criteria\s*$(.*?)(^##\s|\Z)", spec_text, re.MULTILINE | re.DOTALL)
    if not m:
        return []
    section = m.group(1)
    return [int(n) for n in re.findall(r"^\s*(\d+)\.\s", section, re.MULTILINE)]


def covered_numbers(done_contract_text):
    m = re.search(r"^##\s*Acceptance Criteria Coverage\s*$(.*)", done_contract_text, re.MULTILINE | re.DOTALL)
    if not m:
        return []
    section = m.group(1)
    nums = []
    for line in section.splitlines():
        row = re.match(r"^\|\s*(\d+)\s*\|", line)
        if row:
            nums.append(int(row.group(1)))
    return nums


def main():
    if len(sys.argv) != 3:
        print("usage: check_ac_coverage.py <spec.md> <done-contract.md>", file=sys.stderr)
        return 2
    with open(sys.argv[1], encoding="utf-8") as f:
        spec_text = f.read()
    with open(sys.argv[2], encoding="utf-8") as f:
        dc_text = f.read()

    acs = set(acceptance_criteria_numbers(spec_text))
    covered = set(covered_numbers(dc_text))
    uncovered = sorted(acs - covered)

    if uncovered:
        print("UNCOVERED_ACCEPTANCE_CRITERIA: %s" % ", ".join(str(n) for n in uncovered))
        return 1
    print("all %d acceptance criteria are covered" % len(acs))
    return 0


if __name__ == "__main__":
    sys.exit(main())

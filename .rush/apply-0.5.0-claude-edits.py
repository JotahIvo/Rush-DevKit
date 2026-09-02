#!/usr/bin/env python3
"""Applies the 0.5.0 changes that live under .claude/.

Everything else in 0.5.0 is already on disk. These three files could not be written from the
Claude session because the desktop bridge refuses any write under `.claude/` — a sensible
restriction, and not one worth working around from the outside. Run this once from the project
root, check `git diff`, then delete this file.

    python3 .rush/apply-0.5.0-claude-edits.py

It is idempotent: running it twice reports "already applied" and changes nothing.
"""
import os
import sys

FEATURES_OLD = """3. `.rush/memory/architecture.md` and ADRs — structural boundaries a feature split must respect
   (e.g. a bounded context should map to one or a small number of features, not be sliced across
   many with a chatty interface between them)."""

FEATURES_NEW = """3. `specs/<spec-id>/architecture.md` (this spec's full architecture) and its ADRs — structural
   boundaries a feature split must respect (e.g. a bounded context should map to one or a small
   number of features, not be sliced across many with a chatty interface between them).
   `.rush/memory/architecture.md` holds only a condensed digest per spec — read the full file for
   the spec whose PRD you are splitting, not the digest."""

ANALYZE_INPUT_OLD = "5. `.rush/memory/architecture.md` and the relevant ADRs."

ANALYZE_INPUT_NEW = """5. `specs/<spec-id>/architecture.md` — the full architecture of the spec this feature belongs to,
   plus the relevant ADRs. `.rush/memory/architecture.md` only holds a condensed digest per spec;
   judging whether `plan.md` contradicts a structural decision requires the full file, not the
   digest."""

ANALYZE_STEP_OLD = """   - **Architecture not reflected**: any decision in `architecture.md`/ADRs relevant to this
     feature that `plan.md` silently ignores or contradicts."""

ANALYZE_STEP_NEW = """   - **Architecture not reflected**: any decision in `specs/<spec-id>/architecture.md` or its ADRs
     relevant to this feature that `plan.md` silently ignores or contradicts."""

FIXTURE_PATH = os.path.join(
    ".rush", "evals", "fixtures", "skill-missing-script",
    ".claude", "skills", "fixture-skill", "SKILL.md",
)

FIXTURE_BODY = """---
name: fixture-skill
description: Fixture only. A skill that references a harness script which does not exist, so doctor.sh's skill_dependencies check has something real to catch.
model: haiku
---

## Purpose

Not a real skill. It exists so an eval case can prove that a prompt referencing a missing
script is reported, instead of being discovered by a user when the command fails.

## Process

1. Run `.rush/scripts/does-not-exist.sh --json` and read its output.
"""

EDITS = [
    (os.path.join(".claude", "skills", "rush-features", "SKILL.md"),
     [(FEATURES_OLD, FEATURES_NEW)]),
    (os.path.join(".claude", "skills", "rush-analyze", "SKILL.md"),
     [(ANALYZE_INPUT_OLD, ANALYZE_INPUT_NEW),
      (ANALYZE_STEP_OLD, ANALYZE_STEP_NEW)]),
]


def fail(message):
    sys.stderr.write("ERROR: %s\n" % message)
    sys.exit(1)


def main():
    if not os.path.isdir(".rush") or not os.path.isdir(".claude"):
        fail("run this from the project root (the directory holding .rush/ and .claude/)")

    changed = 0
    for path, pairs in EDITS:
        if not os.path.isfile(path):
            fail("not found: %s" % path)
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        if all(new in text for _, new in pairs):
            print("already applied: %s" % path)
            continue
        for old, new in pairs:
            count = text.count(old)
            if count != 1:
                fail("%s: expected exactly one occurrence of the original text, found %d — "
                     "the file has been edited since; apply this change by hand." % (path, count))
            text = text.replace(old, new)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        print("patched: %s" % path)
        changed += 1

    if os.path.isfile(FIXTURE_PATH):
        print("already present: %s" % FIXTURE_PATH)
    else:
        os.makedirs(os.path.dirname(FIXTURE_PATH), exist_ok=True)
        with open(FIXTURE_PATH, "w", encoding="utf-8") as fh:
            fh.write(FIXTURE_BODY)
        print("created: %s" % FIXTURE_PATH)
        changed += 1

    print("\n%d file(s) changed. Now run:" % changed)
    print("  .rush/scripts/doctor.sh")
    print("  .rush/scripts/eval.sh --all")
    print("then delete this script: rm .rush/apply-0.5.0-claude-edits.py")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Moves the 0.6.0 changes that live under .claude/ into place.

Everything else in 0.6.0 is already on disk. These files could not be written from the Claude
session because the desktop bridge refuses any write under `.claude/` — a sensible restriction,
and not one worth working around from the outside. So the new versions were staged next door, in
`.rush/_incoming/dot-claude/`, and this copies them across.

    python3 .rush/apply-0.6.0-claude-edits.py

Then check `git diff` and delete both this script and `.rush/_incoming/`. Running it twice is
safe: it reports files that are already identical and copies nothing.

It also carries the three 0.5.0 edits, in case that release's applier was never run — those are
folded into the staged files, plus the eval fixture below.
"""
import filecmp
import os
import shutil
import sys

STAGING = os.path.join(".rush", "_incoming", "dot-claude")
TARGET = ".claude"

# 0.5.0 leftover: the fixture skill that doctor.sh's skill_dependencies check is pointed at by
# .rush/evals/kit/cases/kit-skill-harness-references-exist.json. Also under .claude/, also
# unwritable from the session, so it is recreated here rather than staged.
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


def fail(message):
    sys.stderr.write("ERROR: %s\n" % message)
    sys.exit(1)


def main():
    if not os.path.isdir(".rush") or not os.path.isdir(TARGET):
        fail("run this from the project root (the directory holding .rush/ and .claude/)")
    if not os.path.isdir(STAGING):
        fail("%s not found — nothing staged to apply. If you already ran this, delete the "
             "script; the changes are in place." % STAGING)

    copied, unchanged = 0, 0
    for dirpath, _dirnames, filenames in os.walk(STAGING):
        for name in sorted(filenames):
            src = os.path.join(dirpath, name)
            rel = os.path.relpath(src, STAGING)
            dst = os.path.join(TARGET, rel)
            if os.path.isfile(dst) and filecmp.cmp(src, dst, shallow=False):
                unchanged += 1
                continue
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
            print("updated: %s" % dst)
            copied += 1

    if os.path.isfile(FIXTURE_PATH):
        print("already present: %s" % FIXTURE_PATH)
    else:
        os.makedirs(os.path.dirname(FIXTURE_PATH), exist_ok=True)
        with open(FIXTURE_PATH, "w", encoding="utf-8") as fh:
            fh.write(FIXTURE_BODY)
        print("created: %s" % FIXTURE_PATH)
        copied += 1

    print("\n%d file(s) updated, %d already identical. Now run:" % (copied, unchanged))
    print("  .rush/scripts/doctor.sh")
    print("  .rush/scripts/eval.sh --all")
    print("then clean up:")
    print("  rm -rf .rush/_incoming .rush/apply-0.6.0-claude-edits.py")


if __name__ == "__main__":
    main()

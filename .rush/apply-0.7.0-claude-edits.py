#!/usr/bin/env python3
"""Moves the 0.7.0 addition that lives under .claude/ into place.

Only one file this time: the /rush-update skill. It could not be written from the Claude session
because the desktop bridge refuses any write under `.claude/`, so it was staged next door in
`.rush/_incoming/dot-claude/` and this copies it across.

    python3 .rush/apply-0.7.0-claude-edits.py

Then check `git diff` and delete both this script and `.rush/_incoming/`. Running it twice is
safe: it reports files that are already identical and copies nothing.
"""
import filecmp
import os
import shutil
import sys

STAGING = os.path.join(".rush", "_incoming", "dot-claude")
TARGET = ".claude"


def main():
    if not os.path.isdir(".rush") or not os.path.isdir(TARGET):
        sys.stderr.write("ERROR: run this from the project root\n")
        return 1
    if not os.path.isdir(STAGING):
        sys.stderr.write("ERROR: %s not found — nothing staged to apply.\n" % STAGING)
        return 1

    copied = unchanged = 0
    for dirpath, _dirnames, filenames in os.walk(STAGING):
        for name in sorted(filenames):
            src = os.path.join(dirpath, name)
            dst = os.path.join(TARGET, os.path.relpath(src, STAGING))
            if os.path.isfile(dst) and filecmp.cmp(src, dst, shallow=False):
                unchanged += 1
                continue
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
            print("updated: %s" % dst)
            copied += 1

    print("\n%d file(s) updated, %d already identical. Now run:" % (copied, unchanged))
    print("  .rush/scripts/doctor.sh")
    print("  .rush/scripts/eval.sh --all")
    print("then clean up:")
    print("  rm -rf .rush/_incoming .rush/apply-0.7.0-claude-edits.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())

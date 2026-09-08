---
name: broken
description: Fixture skill for kit-skill-harness-references-exist. It names a harness script that was never written, which is the exact shape of the real failure the eval guards — /rush-pr and the context-save/load pair shipped referencing scripts and templates that did not exist, and nothing caught it until a user invoked the command.
---

## Purpose

Exists only to be found by `doctor.sh`'s `skill_dependencies` check. Do not install it.

## Process

1. Run `.rush/scripts/does-not-exist.sh --json` and use its output.
2. Fill `.rush/templates/also-does-not-exist.md`.

A path carrying a `<placeholder>` such as `.rush/scripts/<name>.sh` is a shape, not a file, and
the check skips it on purpose — that skip is part of what this fixture pins down.

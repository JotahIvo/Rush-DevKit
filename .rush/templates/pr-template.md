<!-- PR artifact: the pull request description for ONE spec — pitch through every feature that
     split out of it — ready to paste into GitHub/GitLab. The spec is the PR's unit here, not a
     single feature: several features close under one spec and the PR opens once for the lot. -->
<!-- Filled by /rush-pr from .rush/scripts/pr-commits.sh's JSON (commit range + per-feature
     done-check status) — never from a hand-run `git log`. The head of this file is fixed; the
     body below "Sections" is whatever .rush/memory/pr-preferences.md defines, in its order.
     Location: specs/{{SPEC_ID}}/pr.md -->

# {{PR_TITLE}}

**Spec**: `specs/{{SPEC_ID}}/` · **Generated**: {{DATE}} · **Commits**: {{COMMIT_COUNT}}
**Status**: {{OVERALL_STATUS}}

<!-- OVERALL_STATUS is either "all features done" or "partial — <n> incomplete". It comes from
     pr-commits.sh's summary, never from reading the commits and judging they look finished. -->

## Features

<!-- One row per feature under this spec. `Status` is the feature's actual done-check result:
     done | incomplete | unknown — a feature whose checks fail, or whose human gates are still
     pending, is listed as incomplete no matter how its commits read. `Notes` carries something
     only when there is something worth flagging (a failing check, a pending gate, a notable
     scope change) — never an invented summary to fill the cell. -->

| Feature | Title | Status | Notes |
|---|---|---|---|
| `{{FEATURE_ID_1}}` | {{FEATURE_TITLE_1}} | {{FEATURE_STATUS_1}} | {{FEATURE_NOTE_1}} |

---

<!-- Everything below this line is defined by .rush/memory/pr-preferences.md: exactly the
     sections it lists, in its order. Do not add a section it does not mention, and do not drop
     one because this spec has nothing to say for it — write "Nothing to report" instead, so a
     reader can tell the difference between "checked, nothing there" and "not checked". -->

## {{PREFERENCE_SECTION_1}}

{{PREFERENCE_SECTION_1_BODY}}

## {{PREFERENCE_SECTION_2}}

{{PREFERENCE_SECTION_2_BODY}}

<!-- PR-PREFERENCES artifact: this project's standing PR description format, agreed once with the
     user and reused for every PR after that. It exists so /rush-pr never invents its own section
     headings — it fills the ones declared here. -->
<!-- Written by /rush-pr on its first run in a project (and updated in place only when the user
     explicitly asks to change the format — never as a one-off tweak to a single PR).
     Location: .rush/memory/pr-preferences.md -->

# PR Preferences

## Sections

<!-- The sections every PR description carries, in the order they should appear. /rush-pr fills
     exactly these — no more, no fewer. A section with nothing to say for a given spec gets
     "Nothing to report", never silent omission. Keep the list short: a format nobody reads to
     the end is a format that stops being filled honestly. -->

1. {{SECTION_NAME_1}} — {{WHAT_GOES_IN_IT_1}}
2. {{SECTION_NAME_2}} — {{WHAT_GOES_IN_IT_2}}

## Tone and Length

- **Tone**: {{TONE}}
- **Length**: {{LENGTH_GUIDANCE}}

## Always Include

<!-- Things that must appear in every PR description: a ticket link in a given shape, a
     reviewer checklist, required mentions. Write "nothing" if there are none. -->
- {{ALWAYS_INCLUDE_1}}

## Never Include

<!-- Things this project does not want in a PR description: internal task ids, agent process
     detail, pasted diffs, screenshots of local runs. Write "nothing" if there are none. -->
- {{NEVER_INCLUDE_1}}

## Notes

<!-- Anything else that shapes the format and is not covered above (e.g. "title must match the
     branch name", "we squash-merge, so the PR title becomes the commit subject"). -->
{{NOTES_OR_NONE}}

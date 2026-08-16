<!-- CHECKLIST artifact: generic quality checklist used by /rush-review and /rush-analyze. Every
     item must trace to a real failure it once caught, or would have caught — nothing added
     "just in case". Items that never trigger get retired by /rush-retro, so the list stays
     sharp instead of growing forever. -->
<!-- Two uses, same shape:
     1. /rush-review copies this structure into specs/<feature-id>/review.md to record the
        findings of one feature's assisted review (add a severity line per finding:
        blocker | should-fix | nitpick).
     2. The project's standing checklist lives at .rush/memory/checklist.md, pruned by
        /rush-retro as items prove themselves useless. -->

# Quality Checklist

## {{CHECK_ID}} — {{CHECK_TITLE}}

- **Checks for**: {{WHAT_IT_CATCHES}}
- **Traces to**: {{REAL_FAILURE_OR_INCIDENT_THAT_JUSTIFIED_IT}}
<!-- No incident/near-miss to name means the item isn't ready to be added yet. -->
- **How to verify**: {{VERIFICATION_STEPS_OR_COMMAND}}
- **Times triggered**: {{COUNT}}
<!-- /rush-retro reads this count; an item stuck at 0 across enough cycles is a candidate for
     retirement, not a permanent fixture. -->

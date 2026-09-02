<!-- SESSION-CONTEXT artifact: what one chat session worked out that lives ONLY in that chat.
     Reasoning, approaches tried and dropped, the thread that was still open when the session
     ended — none of it survives the session unless something writes it down. Everything the kit
     already records durably (tasks.md's Session Log, a spec's questions.md, debt.md,
     done-contract.md) is referenced by path here, never copied: this file is for the rest. -->
<!-- Written by /rush-context-save, read by /rush-context-load. Local scratch, not a project
     artifact — .rush/memory/sessions/ belongs in .gitignore.
     Location: .rush/memory/sessions/{{DATE}}-{{SLUG}}.md (path from session-context.sh new-path) -->

# Session: {{TOPIC}}

**Saved**: {{DATE}} · **Spec**: {{CURRENT_SPEC_OR_NONE}} · **Feature**: {{CURRENT_FEATURE_OR_NONE}}

<!-- The spec/feature the session was working in, from session-start.sh, so /rush-context-load can
     tell immediately whether project state has moved on since this was saved. -->

## Goal

<!-- What this session was actually trying to achieve, in plain terms — not a restated task list. -->
{{SESSION_GOAL}}

## Decisions Made

<!-- Decisions reached in conversation, with the reason. Something already written into a spec,
     a done-contract or debt.md gets a path reference here, not a copy. -->
- {{DECISION_1}}

## Ruled Out

<!-- The highest-value section in this file. An adopted decision is usually visible in the
     resulting code or artifact; a rejected approach is invisible unless recorded, and a fresh
     session will re-propose exactly what was already tried and dismissed. Each entry: the
     approach, and why it was dropped. Write "none this session" if there genuinely were none —
     never invent one to fill the section. -->
- {{RULED_OUT_1}} — {{WHY_1}}

## Files Touched

<!-- Read or edited during the session, so the next one knows where the work landed. -->
- `{{FILE_1}}` — {{WHAT_CHANGED_1}}

## Open Thread

<!-- What was in progress when the session ended, and the exact next concrete step. This is the
     first thing /rush-context-load surfaces, so it carries more weight than anything else here:
     "continue working on this" is a failed Open Thread. If nothing was in progress, say so
     explicitly. -->
{{WHAT_WAS_IN_PROGRESS}}

**Next step**: {{EXACT_NEXT_STEP}}

## Explicitly Not Yet Done

<!-- Things consciously deferred during the session — not forgotten, decided against for now.
     Recording them here is what stops them from being silently forgotten a second time. -->
- {{DEFERRED_1}}

## Belongs Elsewhere

<!-- Anything that came up in conversation and should be recorded in a durable file this skill
     does not own (debt.md, a spec's questions.md, the spec itself). Named here for the user to
     route; /rush-context-save never writes to those files itself. Write "none" if there is
     nothing. -->
- {{ITEM_1}} → {{TARGET_FILE_1}}

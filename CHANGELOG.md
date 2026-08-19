# Changelog

## 0.3.0

Six workflow changes, all driven by real friction running the kit on a live project: too many
manual `/rush-spec` invocations per spec, architecture scoped to a feature when it's really a
whole-system decision, a contracts step that was never skipped so it stopped earning its own
command, a progress.md nobody kept reading separately from tasks.md, acceptance criteria that could
drift out of sync with the checks meant to enforce them, and one global `questions.md` that became
unreadable once more than one spec was in flight.

### Added

- **`/rush-spec-all <spec-id>`** — runs `/rush-spec`'s full process for every feature nested under
  one spec, in dependency order (provider before consumer, from the integration map's topological
  order where available, otherwise numeric order). One feature failing or ending in unresolved
  questions never stops the rest from being attempted. Orchestration only: it carries none of its
  own content guardrails and waives none of `/rush-spec`'s.
- **`specs/<spec-id>/architecture.md`** — the complete, authoritative architecture for the whole
  system a spec builds, written once per spec by `/rush-architect` (budget 200 lines) instead of
  one section per feature in the shared memory file.
- **`.rush/templates/architecture-summary-template.md`** — the condensed per-spec digest
  `/rush-architect` appends to `.rush/memory/architecture.md` (budget 25 lines) after writing the
  full version. A pointer plus a handful of facts, never a copy of the full document's text.
- **`specs/<spec-id>/questions.md`**, seeded empty by `new-spec.sh` for every new spec.

### Changed

- **Architecture moved from per-feature to per-spec, and split into a full version plus a
  summary.** `/rush-architect` now runs once per spec (it always ran at the spec level in its
  Inputs, but wrote a per-feature section before) and produces the complete system architecture at
  `specs/<spec-id>/architecture.md`. `.rush/memory/architecture.md` now accumulates one condensed
  digest per spec instead of one full section per feature — reading every spec's architecture in
  full no longer means reading an ever-growing single file. `validate-artifacts.sh` budgets the two
  separately (`architecture`: 200 lines for the full file, new `architecture_summary`: 25 lines for
  the digest section).
- **Contract generation folded into `/rush-spec`.** When a feature's `spec.md` declares an
  interface it provides, `/rush-spec` now generates that interface's contract file(s) (OpenAPI,
  JSON Schema, AsyncAPI) itself, as part of its own process — no separate command is needed for the
  normal flow. `/rush-contracts` still exists, repurposed as the tool for re-syncing a contract
  after it changes post-freeze (or generating one `/rush-spec` skipped for some reason); its
  mechanics are unchanged, only its role in the flow is narrower now.
- **`progress.md` retired; `tasks.md` absorbed it.** Every feature's session diary now lives in a
  `## Session Log` section at the bottom of `tasks.md` (level-4 `####` entries on purpose — task
  headings are level-3 and every script that parses tasks treats "###" as a potential task, so the
  log had to be a level nothing else uses). `new-feature.sh` no longer copies
  `progress-template.md`; `session-start.sh` reads the newest Session Log entry instead of a
  separate file's newest heading.
- **Each task's status line now carries a `[ ]`/`[x]` checkbox**, e.g. `` - [x] status: `done` ``,
  toggled automatically by `task-status.sh`/`rushlib.py`'s `set_task_status` (checked only when
  status is `done`) — a glance at `tasks.md` now shows completion without reading every status
  word. Reading stays backward compatible with files that have no checkbox yet; the first status
  change on such a file adds one.
- **Acceptance criteria moved from `spec.md` into `done-contract.md`.** A criterion and the check
  (or human gate) that enforces it are now written and read together, in one document, instead of
  living in two files that could silently drift apart. `spec.md` no longer has an "Acceptance
  Criteria" section (dropped from `validate-artifacts.sh`'s required sections for it);
  `done-contract.md` gained one, immediately before the Definition of Done JSON block, and
  `validate-artifacts.sh` now requires "Acceptance Criteria", "Definition of Done" and "Acceptance
  Criteria Coverage" sections in it.
- **`questions.md` moved from one shared `.rush/memory/questions.md` to one per spec**,
  `specs/<spec-id>/questions.md`, seeded by `new-spec.sh`. A big multi-spec project no longer has
  every spec's non-blocking questions interleaved in one file — each spec's questions sit with its
  own artifacts. `session-start.sh` reads the current spec's file; `doctor.sh`'s staleness check
  scans every spec's file and reports across all of them. The canonical Guardrail 7 text ("Blocking
  question: ask the user. Non-blocking question: append to...") changed to match in all 18 skills
  and in `docs/internals/kit-conventions.md`.

### Migration

Projects on `0.2.x` upgrading in place: for each existing feature, move its `progress.md` content
into a new `## Session Log` section at the bottom of `tasks.md` (by hand, or leave the old file —
nothing deletes it automatically) and delete `progress.md` once migrated. For each spec, create
`specs/<spec-id>/questions.md` (copy over any entries from the old shared
`.rush/memory/questions.md` that concern that spec) — the old shared file is not deleted
automatically either. For each feature's `spec.md`, move its "Acceptance Criteria" section into
`done-contract.md` (immediately before the Definition of Done block) and add or update the
Coverage table there. For each spec that already ran `/rush-architect`, its old per-feature section
in `.rush/memory/architecture.md` can be split into a full `specs/<spec-id>/architecture.md` plus a
condensed digest the next time `/rush-architect` runs for it — nothing requires doing this
retroactively for closed specs.

## 0.2.0

Structural change: features now nest under their spec, both levels carry their
own numeric id, and `.rush/state.json` tracks the active spec and the active
feature inside it separately. Driven directly by real usage: a pitch run
without a PRD left an unnumbered `specs/<slug>/` directory with only
`pitch.md` and no `state.json`, and `/rush-features` created several
`specs/NNN-slug/` as siblings when the user's mental model was one numbered
parent containing them.

### Changed

- **specs/ is now two levels: `specs/<spec-id>/<feature-id>/`.** A spec
  (`specs/NNN-slug/`) is the parent unit — `pitch.md` and `prd.md` live
  directly in it. A feature (`specs/<spec-id>/MMM-slug/`) is a deliverable
  unit split out of it by `/rush-features` (or the single implicit feature
  `/rush-quick` creates) — `spec.md`, `plan.md`, `tasks.md`,
  `done-contract.md`, `progress.md` live there. Feature ids restart at `001`
  inside every spec, the same way task ids restart inside every feature's
  `tasks.md` — a bare feature id can therefore collide across specs, which is
  expected, not an error; pass the spec id to disambiguate.
- **`new-feature.sh` now requires `<spec-id> <slug>`** (previously just
  `<slug>`) and creates the feature nested under that spec. A new
  **`new-spec.sh <slug>`** creates the parent, scaffolding `pitch.md`/`prd.md`
  from templates.
- **`.rush/state.json` gained `current_spec`** alongside `current_feature`
  (now scoped to the active spec) and a top-level `specs[]` registry, next to
  the existing `features[]` (each record now carries `spec_id`, and is
  deduplicated by `dir` rather than `id`, since ids are only unique within
  their spec).
- **`rush_feature_dir` in `common.sh` resolves the nested path** and takes an
  optional `[spec-id]` to scope/disambiguate; a new **`rush_spec_dir`**
  resolves the parent level. Every script that already called
  `rush_feature_dir` and just joined paths onto its result (`task-status.sh`,
  `done-check.sh`, `fitness.sh`, …) needed no further change. Scripts with
  their own duplicated resolution logic (`check-as-built.sh`,
  `validate-artifacts.sh`, `validate-contracts.sh`,
  `validate-integration-map.sh`) were updated to search both levels.
- **`guard-edit.sh`'s tasks.md protection** now matches
  `specs/<spec-id>/<feature-id>/tasks.md`.
- **`/rush-pitch` numbers a spec immediately** via `new-spec.sh`, instead of
  staging an unnumbered `specs/<slug>/pitch.md` and deferring numbering to a
  later `/rush-features` run that might not happen (the exact gap that
  produced the bug this release fixes). `/rush-architect` and `/rush-prd` now
  explicitly operate at the spec level (`<spec-id>`, pre-`/rush-features`);
  `/rush-features` creates each split feature nested under the spec it split
  and uses `<spec-id>/<feature-id>` as the node id in `integration-map.md`;
  `/rush-quick` and `/rush-spec` create a spec (if needed) before the feature
  nested inside it.
- Decided against a per-spec architecture summary file: `/rush-architect`'s
  output keeps accumulating as one section per feature in the shared
  `.rush/memory/architecture.md` — unchanged from 0.1.x.

### Migration

There is no automatic migrator in this release (see the open item on an
update path that doesn't require re-running `/rush-init`). An existing flat
`specs/NNN-slug/` project needs its feature directories moved under the spec
they belong to and `.rush/state.json` rebuilt by hand — see
`docs/internals/script-interfaces.md` for the exact shape.

## 0.1.1

Fixes a shipping bug that made the kit unusable on macOS.

### Fixed

- **`guard-edit.sh` could not be parsed by macOS bash 3.2** (`unexpected EOF while
  looking for matching backtick`). A literal backtick inside a heredoc inside
  `$( )` is a whole-file syntax error on bash 3.2 — and since this is a
  `PreToolUse` hook, the failure blocked *every* `Write` and `Edit` in the
  project, including the edit that would have fixed it. `bash -n` under bash 5
  passed throughout, which is why it shipped.
  All four hooks now write their Python to a temp file instead of using
  `PYCODE=$(cat <<'PYEOF' … )`, which also keeps stdin free for the hook payload
  and removes the argv size limit. `new-feature.sh` had the same latent
  construct and was converted too.
- **`.rush/config.json` and `constitution.md` were denied unconditionally**, so
  `/rush-init` could not create them — the harness was unable to install itself.
  Creating them is now allowed (with a notice that the file becomes human-owned);
  modifying an existing one is still denied.

### Added

- **`.rush/scripts/lint-shell-portability.sh`** — static check for constructs
  that break on macOS bash 3.2: heredocs inside `$( )`, bash 4+ builtins
  (`mapfile`, `declare -A`, `${var,,}`), and GNU-only flags (`grep -P`,
  `sed -i` without a suffix, `date -d`, `readlink -f`, the `timeout` binary).
  Wired into `doctor.sh` as the `shell_portability` check, and covered by the
  eval case `kit-no-bash32-breaking-constructs`, whose fixture reproduces the
  original incident.

The ratchet applied to the kit itself: the failure became a mechanism, not a
note asking people to be careful.

## 0.1.0

First release. 17 skills, 3 subagents, 14 scripts, 4 hooks, 17 templates,
3 stack presets, 17 eval cases.

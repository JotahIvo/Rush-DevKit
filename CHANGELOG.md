# Changelog

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

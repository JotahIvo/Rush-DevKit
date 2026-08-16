# Writing a preset

A preset is how the kit knows a stack. It is consumed at two different moments:

- **`rush-init`** (existing project): runs `.rush/scripts/detect-stack.sh`, which inspects the
  repository and proposes a `preset_suggestion`. `rush-init` loads the matching
  `.rush/presets/<id>.json`, merges its `config_overrides` into `config.default.json`, seeds
  `.rush/memory/constitution.md` / `CLAUDE.md` with the preset's `conventions`, and copies
  `fitness_functions` into `.rush/memory/fitness/`.
- **`rush-new`** (greenfield project): skips detection entirely and runs the preset's `scaffold`
  block — the stack's own official generator, plus `post_scaffold` steps — then proceeds exactly
  like `rush-init` on the result.

A preset never runs code by itself and never talks to the network. Everything in it is a static
declaration; the scripts that consume it (`detect-stack.sh`, `rush-init`, `rush-new`) are what
execute.

## Shape

Every preset validates against `.rush/presets/preset.schema.json` (JSON Schema, draft 2020-12).
Required top-level fields: `id`, `name`, `description`, `match`, `commands`, `conventions`,
`structure`, `contract_style`. Optional: `fitness_functions`, `config_overrides`, `scaffold`.

- **`match`** — the deterministic signals `detect-stack.sh` looks for: `dependencies` (package
  names in the manifest), `files` (paths/globs whose presence is diagnostic), `lockfiles` (which
  package manager). No signal here is ever a guess; if a stack can't be recognised from files on
  disk, it doesn't belong in `match`.
- **`commands`** — real, currently-correct CLI invocations for `test`/`lint`/`build`/`format`/
  `typecheck`. Omit a field entirely rather than inventing a command that isn't standard for the
  ecosystem; `rush-init` leaves the corresponding `config.json → commands.*` as `null` and a human
  fills it in.
- **`conventions`** — prose rules seeded into `CLAUDE.md`/`constitution.md`. See "Earned rules
  only" below; this is the part reviewers should scrutinise hardest.
- **`structure`** — where code/tests/migrations conventionally live for this stack, used to seed
  `architecture.md` and to give `rush-explorer` a starting point.
- **`fitness_functions`** — starter executable checks copied into `.rush/memory/fitness/` and run
  by `fitness.sh`. Each `script` is a complete, portable bash script (see the portability rules
  below) that exits 0 when the constraint holds.
- **`config_overrides`** — a partial `config.json` merged over the default (e.g. `security.
  sensitive_paths` seeded from what `match.files` found, or a stack-appropriate `autonomy.
  migrations` default). Must validate against `config.schema.json` once merged.
- **`scaffold`** — greenfield only. `commands` is the stack's *official* generator invocation
  (`nest new`, `create-next-app`, ...). If a stack genuinely has no official scaffolding tool, say
  so honestly with the ecosystem's documented manual setup — never invent a generator that doesn't
  exist.
- **`contract_style`** — `rest-openapi` | `graphql` | `events`. Tells `rush-contracts` and
  `validate-contracts.sh` what shape of contract file to expect for features built on this stack.

## Earned rules only

Every entry in `conventions` and `fitness_functions` must trace back to a **real constraint**:
a framework guarantee that breaks without the rule, a documented footgun, or a failure mode the
ecosystem is known for. Each convention carries a mandatory `reason` field for exactly this
reason — a reviewer should be able to read `reason` and either agree it's a real constraint or
reject the rule as taste dressed up as principle.

Not earned: "use 2-space indentation", "prefer `const` over `let`", "name files kebab-case".
These are style preferences a formatter or linter enforces (or doesn't matter at all) — they do
not belong in a preset.

Earned: "controllers must not import the ORM client directly" (reason: the framework's own test
utilities are built around swapping injected providers, and inline queries can't be unit-tested
the same way), "hand-edit migration files" (reason: the migration tool's autogenerate diffs the
real schema against ORM metadata, and hand edits desync that history).

If you can't write a `reason` that points at something concrete and checkable, the rule isn't
ready for a preset.

## Fitness function portability

Scripts follow the same portability rules as everything under `.rush/scripts/`
(`docs/internals/script-interfaces.md`): `#!/usr/bin/env bash`, `set -euo pipefail`, must run on
both bash 3.2 (macOS) and Linux, no GNU-only flags (`grep -P`, `grep --include`, `sed -i` without
a suffix, `date -d`), no `jq` dependency. Prefer `find ... -exec` / a `for` loop over `grep -r
--include` for filtering by filename. If the check needs real parsing (not just pattern
matching), shell out to `python3` with **stdlib only**, exactly like the core scripts do.

Every fitness function must exit `0` when the constraint holds and a non-zero exit with an
explanatory message otherwise — `fitness.sh` treats silence-on-pass / verbose-on-fail as the
contract.

## Contribution checklist

- [ ] `id` is kebab-case, stable, and matches the filename (`<id>.json`)
- [ ] `match` signals are things that genuinely exist on disk for this stack — verified against a
      real project, not assumed
- [ ] Every command in `commands` is the actual, currently-documented CLI invocation for this
      ecosystem; nothing invented, nothing guessed
- [ ] Every `conventions` entry has a `reason` that names a concrete constraint, not a preference
- [ ] `fitness_functions` scripts pass `bash -n` and have been run against both a passing and a
      failing fixture by hand
- [ ] `config_overrides` merges cleanly over `config.default.json` and the result still validates
      against `config.schema.json`
- [ ] `scaffold.commands` is the ecosystem's own official generator, or an honest documented
      manual setup if no official generator exists — never a third-party template presented as
      official
- [ ] The preset file itself validates against `preset.schema.json`
      (`python3 -c "import json,jsonschema; jsonschema.validate(json.load(open('<id>.json')), json.load(open('preset.schema.json')))"`)

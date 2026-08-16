# Rush DevKit eval suite

This directory holds regression tests for **agent behaviour**, not for code. Each case encodes a
failure mode a Rush agent (or its harness) could reintroduce — a spec that leaks process
instructions, an integration map with a dangling consumer, a task promoted to `done` by the wrong
actor — and states, mechanically or in a precise rubric, what "still safe" looks like.

## Philosophy

- **Start small, from real failures.** A handful of cases that trace to something that actually
  went wrong beats hundreds of synthetic ones nobody trusts. `/rush-retro` is the mechanism that
  keeps this true (see below) — new cases are added because a feature closed with a failure this
  suite didn't catch, not because "more coverage" sounds good.
- **Layered graders, cheapest first.** A case should reach for the least subjective grader that
  can actually measure the property:
  1. **Deterministic code** — `script` (usually calling one of the kit's own validators:
     `validate-artifacts.sh`, `validate-integration-map.sh`, `task-status.sh`, a hook), `budget`,
     `contains`, `file_exists`. If a script or a grep can tell pass from fail, use it — it never
     drifts, never disagrees with itself, and costs nothing to re-run.
  2. **Judgement, only where unavoidable** — `manual`, for properties no script can measure (a
     GO/NO-GO verdict, whether a diff "weakens" a test, whether an agent stopped at its attempt
     budget). These still return a structured pass/fail, just from a human or reviewing agent
     applying a written rubric instead of a script applying a comparison.
  3. **Human last.** The runner never fakes grading a `manual` case — it reports `manual` and
     lists the rubric for a person to apply. Pretending a rubric was checked when it wasn't is
     worse than admitting nobody checked it yet.
- **Never let the runner pretend.** `.rush/scripts/eval.sh` only ever reports `pass`, `fail`, or
  `manual`. There is no fourth state where a case "probably passed." If a case depends on a live
  agent run that hasn't happened, its grader must be `manual` (or a deterministic grader whose
  fixture is provided here so it evaluates something real *right now* — see "Two kinds of case"
  below) — never a `file_exists`/`budget` check quietly pointed at an artifact nobody produced
  yet, which would just fail every time until someone remembers to run the agent first.

## Two kinds of case

**Mechanism cases** point every grader at a fixture under `.rush/evals/fixtures/` that this repo
ships. They run today, with no agent involved, and must genuinely pass — they prove the
deterministic safety net (a validator, a hook, a script) still catches the failure mode it was
built for. Most cases in this suite are this kind: e.g. `rush-features/cases/
features-consume-without-provider-caught.json` points `validate-integration-map.sh` at a broken
fixture map and asserts it reports `consume_without_provider`. If someone weakens the validator,
this case starts failing immediately, with no agent needed to notice.

**Behavioural cases** describe a scenario for an operator to actually run through the named agent
(`given.scenario`), then grade the transcript/output against a `manual` rubric — because the
property (did the agent invent a provider instead of reporting the gap? did it stop at exactly 3
attempts?) only exists once the agent has acted. These always carry a `manual` grader so the
runner reports `manual`, never a spurious `fail`, when nobody has run the scenario yet.

## Case format

One JSON file per case, under `.rush/evals/<agent>/cases/<case-id>.json`:

```json
{
  "id": "spec-budget-violation-caught",
  "agent": "rush-spec",
  "description": "A spec.md over the 150-line budget must be caught by validate-artifacts.sh, not shipped silently.",
  "given": {
    "cwd": ".rush/evals/fixtures/over-budget-spec",
    "scenario": "Fixture project containing specs/001-fixture/spec.md, deliberately 182 lines (budget is 150)."
  },
  "graders": [
    { "type": "file_exists", "path": "specs/001-fixture/spec.md" },
    { "type": "script", "run": "../../../../.rush/scripts/validate-artifacts.sh 001-fixture --json", "expect": "exit 1" },
    { "type": "script", "run": "../../../../.rush/scripts/validate-artifacts.sh 001-fixture --json", "expect": "contains: \"rule\": \"budget\"" }
  ]
}
```

Fields:

- `id` — matches the filename stem (`eval.sh --case <id>` looks up by filename, not this field;
  keep them identical so both ways of finding a case agree).
- `agent` — the skill this case guards, matching the directory name it lives under.
- `description` — **states the failure mode plainly**: what breaking would look like, and which
  guardrail/process step in the agent's `SKILL.md` it traces to. This is what makes a case
  self-documenting when it starts failing months later.
- `given` — the setup. `cwd` (optional) is a path relative to the project root; when set, every
  grader's `script.run` and file paths are resolved relative to it — this is how a case points at
  a fixture under `.rush/evals/fixtures/<name>/` instead of the real (usually empty, in this
  template repo) `specs/` tree. `setup` (optional) is a shell command run once before grading;
  none of the cases here use it, since fixtures are checked-in files, not generated at eval time —
  prefer that when possible, it keeps runs deterministic and diffable. `scenario` (optional, free
  text, ignored by the runner) documents the prompt an operator runs for a behavioural case.
- `graders` — see grader types below. A case's overall status is `fail` if any grader is `false`,
  else `manual` if any grader is `manual`, else `pass`.

### Grader types

| Type | Checks | Notes |
|---|---|---|
| `script` | Runs `run` (shell, from `given.cwd` or the project root), compares against `expect` | `expect`: `"exit 0"`, `"exit N"`, `"contains: <text>"`, `"not_contains: <text>"` — checked against combined stdout+stderr |
| `file_exists` | A file or directory exists at `path` | |
| `budget` | A file has at most `max_lines` lines (raw count, no comment/fence stripping — for the kit's own budget rule including that stripping, call `validate-artifacts.sh` via a `script` grader instead) | |
| `contains` | A file's content contains `text` | |
| `manual` | Always reports `ok: null` (status `manual`) with `rubric` as the text a human/reviewing agent applies | See rubric rule below |

### Fixture cases run against `.rush/evals/fixtures/`

Because this repo has no `specs/` tree of its own (it is the template, not a project), most
mechanism cases need a *fixture project*: a directory under `.rush/evals/fixtures/<name>/` with
its own `.rush/` marker (usually just `.rush/config.json`, or nothing at all) so
`.rush/scripts/lib/common.sh`'s `rush_root` resolves the fixture directory as the project root
when a grader's `given.cwd` points inside it. A fixture that needs a kit script to see
`.rush/scripts/lib/rushlib.py` (anything using `rush_config`, e.g. `triage.sh`) needs a symlink —
see `fixtures/sensitive-path-project/.rush/scripts` for the pattern: `ln -s ../../../../scripts
scripts` from inside the fixture's `.rush/`. From a fixture at
`.rush/evals/fixtures/<name>/`, four `../` reaches the real project root, so a `script` grader
invoking a real kit script looks like `"run": "../../../../.rush/scripts/<script>.sh ..."`.

Keep fixtures tiny and obviously synthetic (fake ids, `POST /fixture`-style names, a one-line
`# not a real feature` comment) — a fixture that looks like real project data invites someone to
"fix" it instead of recognising it as a test input.

## The manual-grader rubric rule

A `manual` grader's `rubric` must be precise enough that **two different people (or two different
reviewing agents) grading the same transcript would reach the same verdict**. That means:

- State PASS and FAIL conditions explicitly, not just "check if it did the right thing."
- Name the exact artifact/section/behaviour to look for, not a vague quality ("the report is
  reasonable").
- Call out the specific way this rule tends to get rationalised away, if there is one — that's
  usually why the case exists. Compare `implement-never-weakens-test-under-approval.json`'s
  rubric, which explicitly says a weakened assertion "even if accompanied by a comment explaining
  why" is still a FAIL — because the comment is exactly how this failure sneaks past a lenient
  reviewer.
- Prefer naming what does **not** count as a violation too (e.g. "adding a brand-new test
  alongside the untouched original is not a violation on its own") — this stops a rubric from
  being read more strictly than intended.

If you cannot write a rubric this precise, the property probably isn't ready to be an eval yet —
narrow it until it is, rather than shipping a vague one two reviewers would score differently.

## How `/rush-retro` adds cases from real failures

`/rush-retro` is the only place new cases are expected to appear in the normal course of a
project. After a feature closes (or during a periodic sweep), it:

1. Reviews what actually happened — `progress.md`, git history, `done-check.sh` failure history,
   `/rush-review` findings — not what was planned.
2. Classifies each failure: caught early (no action), caught late (the check works but should run
   earlier — not a new case), or **not caught until a human found it**.
3. For every "not caught at all" failure, prefers a mechanism over a written rule, in this order:
   a new eval case here (if the failure is checkable, even loosely, against a script or a precise
   rubric), a fitness function (if it's a structural property of the codebase), an earned rule in
   `CLAUDE.md` (if no deterministic check is feasible), or — rarely, and only with human
   confirmation — a new constitution `MUST`.
4. Logs the addition in `.rush/memory/lessons.md`, citing the specific failure the case traces to.
5. Runs `.rush/scripts/eval.sh <agent> --case <id> --json` for each new case, to confirm the
   runner parses and classifies it correctly before considering the retro done.

A case added this way should read exactly like the ones in this suite: a `description` naming the
failure, a `given` an operator can actually reproduce, and graders no more subjective than the
property requires.

## Running the suite

```sh
.rush/scripts/eval.sh --agent rush-spec --json     # one agent
.rush/scripts/eval.sh --all --json                 # every agent
.rush/scripts/eval.sh --case spec-budget-violation-caught --json   # one case, any agent
.rush/scripts/eval.sh rush-implement                # human-readable output
```

Exit code is `0` when every deterministic grader passed (manual cases may still be pending — they
never fail the run by themselves), `1` when at least one deterministic grader failed, `2` on a
usage or internal error. CI or a pre-merge hook can gate on the exit code alone; a person still
has to work through the `manual` list separately, since the runner cannot close that loop itself.

## Retiring a saturated eval

An eval that has passed on every run for a long stretch, across enough changes to the agent it
guards, has stopped being informative — it is now checking that the sun rises. `/rush-retro` step
4 (retire dead checklist items) applies here too: propose removing a case when you can show it
never fired (never went from pass to fail, or never surfaced a real disagreement in a `manual`
review) across the period under review. Removing a saturated case is not a loss of coverage; it is
budget freed for the next case that actually traces to a failure. When in doubt, prefer narrowing
a case's fixture to something closer to the edge that keeps causing trouble over deleting it
outright — but if nothing has been close to that edge in a long time either, delete it.

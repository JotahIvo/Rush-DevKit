"""0.8.0 — context economy: new config sections, and budgets back on for new projects.

0.8.0's subject is not what the kit writes, it is what every command re-reads before it starts.
Two sections arrive:

- `artifacts.feature_prd` ("off"): the feature-level prd.md stops being generated. It restated the
  parent PRD and the feature's own spec.md, and analyze, implement, review and retro each paid to
  read the copy. Its one load-bearing part — the map from a feature's behaviour back to the parent
  PRD's requirement ids — is a required Traceability section in spec.md whenever prd.md is absent.
  Existing prd.md files are left exactly where they are and keep being validated; this only stops
  new ones from being written.
- `context.*`: whether commands read `context-pack.sh` instead of six files, whether they read only
  open questions, and whether `/rush-analyze` may judge only what changed since its last GO.

(0.8.0 also added `models.*`, per-command model overrides. Nothing ever read them — a skill's model
lives in its own frontmatter — so 0.8.1 dropped the section and this migration no longer adds it;
0.8.1's migration removes it from configs that already got it.)

Budgets are the one judgement call. 0.6.0 released them all to null on purpose, and that was right
for the reason it gave: a document cut short to hit a number moves the missing decisions into
somebody's head. What 0.6.0 could not see is the second cost — an artifact nobody has time to read
is skimmed once by the human and then re-read in full by every command after it, so length is paid
for twice, and the second payment is the one that ends a session early. config.default.json ships
numbers again for new projects. This migration does NOT write them into an existing config: files
already on disk were written without a ceiling, and failing a validation that passed yesterday, for
files nobody touched, is not a migration. It reports the numbers and leaves the choice.
"""
VERSION = "0.8.0"
DESCRIPTION = "Context-economy config: artifacts.feature_prd, context.*; budgets reported, not imposed."

NEW_SECTIONS = {
    "artifacts": {"feature_prd": "off"},
    "context": {
        "pack_first": True,
        "questions_open_only": True,
        "skip_analysis_when_unchanged": True,
    },
}

# Numbers config.default.json ships from 0.8.0 on. Suggested, never written here.
SUGGESTED_BUDGETS = {
    "pitch": 80, "prd": 400, "spec": 150, "plan": 100, "tasks": 200,
    "done_contract": 120, "architecture": 250, "architecture_summary": 40,
    "claude_md": 60, "constitution": 150,
}

WHY_FEATURE_PRD = (
    "the feature-level prd.md is off from 0.8.0: it restated the parent PRD and the feature's own "
    "spec.md, and every later command paid to read the copy. Existing prd.md files stay and keep "
    'being validated — only new features stop getting one. Set to "on" to keep generating them.'
)


def migrate(config, changes):
    for section, defaults in NEW_SECTIONS.items():
        existing = config.get(section)
        if not isinstance(existing, dict):
            config[section] = dict(defaults)
            changes.append({
                "key": section,
                "action": "added",
                "to": dict(defaults),
                "why": WHY_FEATURE_PRD if section == "artifacts" else (
                    "new in 0.8.0; every key ships at the value that costs least to read."
                ),
                "attention": section == "artifacts",
            })
            continue
        for key, value in defaults.items():
            if key in existing:
                continue
            existing[key] = value
            changes.append({
                "key": "%s.%s" % (section, key),
                "action": "added",
                "to": value,
                "why": "new in 0.8.0.",
            })

    budgets = config.get("budgets")
    if not isinstance(budgets, dict):
        return

    # tasks.md and done-contract.md became budgetable in 0.8.0. tasks.md is the
    # artifact re-read most often across a feature's life, so it is the one where
    # length compounds fastest — but it is also the one most likely to already be
    # long in a project mid-flight, so it arrives null like the rest.
    for key in ("tasks", "done_contract"):
        if key not in budgets:
            budgets[key] = None
            changes.append({
                "key": "budgets.%s" % key,
                "action": "added",
                "to": None,
                "why": "newly budgetable in 0.8.0 (default %d for new projects); null here so "
                       "nothing that passed yesterday fails today." % SUGGESTED_BUDGETS[key],
            })

    unset = sorted(k for k, v in budgets.items() if v is None)
    if unset:
        changes.append({
            "key": "budgets",
            "action": "kept",
            "from": "all null" if len(unset) == len(budgets) else ", ".join(unset),
            "why": "0.8.0 ships budgets ON for new projects (%s). They are NOT written here: "
                   "these files were authored without a ceiling, and failing a validation that "
                   "passed yesterday is not a migration. Turn them on when you next revise an "
                   "artifact — a budget that fires means 'this document is trying to be two "
                   "documents', never 'raise the number'."
                   % ", ".join("%s=%d" % (k, SUGGESTED_BUDGETS[k]) for k in unset
                               if k in SUGGESTED_BUDGETS),
            "attention": True,
        })

"""0.6.0 — artifact line budgets are off by default.

Every key under `budgets` used to ship with a number, and validate-artifacts.sh carried the same
numbers as built-in fallbacks. 0.6.0 made them all null: a document is as long as its content
honestly requires, and a PRD or an architecture cut short to hit a number only moves the missing
decisions into somebody's head.

A project updating from an earlier version still has the old numbers written into its config.json
— but almost nobody typed them. They came from config.default.json at /rush-init time. So the
distinction that matters is whether each number was inherited or chosen: an inherited one is
released, a chosen one is kept and reported, because a project that deliberately capped its
CLAUDE.md at 40 lines meant it.
"""
VERSION = "0.6.0"
DESCRIPTION = "Artifact budgets default to null (no limit); release inherited numbers, keep chosen ones."

# What config.default.json shipped for these keys in every version before 0.6.0.
PREVIOUS_DEFAULTS = {
    "pitch": 60,
    "prd": 200,
    "spec": 150,
    "plan": 100,
    "architecture": 200,
    "architecture_summary": 25,
    "claude_md": 60,
    "constitution": 200,
}


def migrate(config, changes):
    budgets = config.get("budgets")
    if not isinstance(budgets, dict):
        return

    for key, old_default in PREVIOUS_DEFAULTS.items():
        if key not in budgets:
            continue
        current = budgets[key]
        if current is None:
            continue
        if current == old_default:
            budgets[key] = None
            changes.append({
                "key": "budgets.%s" % key,
                "action": "migrated",
                "from": current,
                "to": None,
                "why": "this was the inherited default, not a decision — released, so the "
                       "artifact is as long as it needs to be.",
            })
        else:
            changes.append({
                "key": "budgets.%s" % key,
                "action": "kept",
                "from": current,
                "why": "differs from the old default (%s), so the project chose it on purpose. "
                       "It stays enforced. Set it to null if you want the 0.6.0 behaviour."
                       % old_default,
                "attention": True,
            })

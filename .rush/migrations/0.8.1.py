"""0.8.1 — `models.*` removed: a config key with nothing behind it.

0.8.0 added `models.*` as per-command model overrides. No script, hook or skill ever read it, and
none could: a skill runs on the model in its own SKILL.md frontmatter, chosen before any of its
instructions execute. The section promised a cost lever that did not exist, which is worse than
not having one — someone sets `spec: "sonnet"`, sees no difference, and stops trusting the config.

The schema no longer accepts the section, so it has to leave every config that got it. All-null
was never a decision and goes silently into the report. A value someone set is still removed —
it never had an effect, and keeping it would fail validation — but it is reported with attention,
naming where the choice actually lives now: the `model:` line of that skill's frontmatter.
"""
VERSION = "0.8.1"
DESCRIPTION = "Remove models.*, which nothing ever read; the model lives in each skill's frontmatter."


def migrate(config, changes):
    if "models" not in config:
        return

    models = config.pop("models")
    chosen = {}
    if isinstance(models, dict):
        chosen = {k: v for k, v in models.items() if v is not None}

    if not chosen:
        changes.append({
            "key": "models",
            "action": "removed",
            "from": models,
            "why": "never read by anything; every key was still the inherited null.",
        })
        return

    changes.append({
        "key": "models",
        "action": "removed",
        "from": models,
        "why": "never read by anything — the values set here (%s) had no effect. To change a "
               "command's model, edit the `model:` line in .claude/skills/rush-<command>/SKILL.md "
               "(a kit file: an update will treat it as a customisation and stage it for "
               "/rush-update rather than overwrite it)."
               % ", ".join("%s=%s" % (k, v) for k, v in sorted(chosen.items())),
        "attention": True,
    })

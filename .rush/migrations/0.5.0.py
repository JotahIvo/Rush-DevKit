"""0.5.0 — git.branch_pattern stopped being decorative.

Until 0.4.0 the field was advisory: config.schema.json described a naming convention and no hook
read it. 0.5.0 wired it into guard-bash.sh, which now denies creating a branch whose name matches
no pattern AND denies a commit made on a branch that matches none.

That turns a value nobody ever had to think about into one that blocks work. A project carrying
the old default string would start having every commit on `main` refused the moment it updated —
not because anyone chose that, but because they inherited a default written when the field did
nothing. So: an inherited value follows the kit, a chosen one is kept and reported.
"""
VERSION = "0.5.0"
DESCRIPTION = "git.branch_pattern is now enforced; migrate the inherited default to a list."

OLD_DEFAULT = "feat/NNN-slug"
NEW_DEFAULT = ["feat/NNN-slug", "main", "master"]


def migrate(config, changes):
    git = config.get("git")
    if not isinstance(git, dict):
        return

    if "branch_pattern" not in git:
        git["branch_pattern"] = list(NEW_DEFAULT)
        changes.append({
            "key": "git.branch_pattern",
            "action": "added",
            "to": list(NEW_DEFAULT),
            "why": "the field is now enforced by guard-bash.sh and was absent; added the default, "
                   "which accepts feature branches plus main/master.",
        })
        return

    current = git["branch_pattern"]

    if current == OLD_DEFAULT:
        git["branch_pattern"] = list(NEW_DEFAULT)
        changes.append({
            "key": "git.branch_pattern",
            "action": "migrated",
            "from": current,
            "to": list(NEW_DEFAULT),
            "why": "this was the inherited default from a version where the field did nothing. "
                   "Left as a bare string it would now deny every commit on main.",
        })
        return

    if current is None or current == [] or current == "":
        changes.append({
            "key": "git.branch_pattern",
            "action": "kept",
            "from": current,
            "why": "empty/null means the check stays off, which is still a valid choice.",
        })
        return

    changes.append({
        "key": "git.branch_pattern",
        "action": "kept",
        "from": current,
        "why": "this is a value the project set deliberately, so it stands. Note that from 0.5.0 "
               "it is ENFORCED: creating a branch that does not match is denied, and so is a "
               "commit on a branch that does not match. If commits on your default branch should "
               "keep working, add it to the list (the field now accepts one).",
        "attention": True,
    })

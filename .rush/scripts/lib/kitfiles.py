#!/usr/bin/env python3
"""Kit file bookkeeping: what the kit owns, what the project owns, and what changed.

This is the shared brain behind `install.sh` and `update.sh`. It exists so that updating a kit
inside a project that has already adapted itself (a generated config.json, a written
constitution, eval cases /rush-retro added, maybe a customised template) is a *decidable*
operation instead of a guess.

Three ownership classes, decided by path and nothing else:

  kit    Files the kit ships and keeps owning. Replaced on update when the project has not
         touched them. `.rush/scripts`, `.rush/hooks`, `.rush/templates`, `.rush/presets`,
         the eval cases and fixtures the kit ships, `.claude/skills`, `.claude/agents`,
         `config.schema.json`, `config.default.json`, `VERSION`.
  seed   Written once at install, then the project's forever. `.rush/memory/**` (the example
         fitness function, the decisions/ placeholder) — a kit update never reaches into a
         project's memory.
  merge  `.claude/settings.json`: the kit owns the four rush hook entries, the project owns
         everything else in the file. Merged field by field, deterministically, by this module.

Anything else under the project is not the kit's business and never appears in a plan:
config.json, state.json, specs/, CLAUDE.md, secret-scan-allow, eval cases the kit never
shipped.

The update needs THREE versions of a file to merge honestly — the one the kit installed
(`base`), the one on disk now (`local`), and the one the new kit ships (`new`). Only with the
base can "the user changed this" be told apart from "the kit changed this". So install writes a
baseline tarball of every kit-class file alongside the manifest, and that is what makes a
three-way merge possible instead of guesswork.

Stdlib only, Python 3.8+, per the kit's own script contract.
"""
import argparse
import fnmatch
import hashlib
import io
import json
import os
import shutil
import sys
import tarfile
import time

MANIFEST_REL = os.path.join(".rush", "manifest.json")
BASELINE_REL = os.path.join(".rush", "baseline.tar.gz")
UPDATE_DIR_REL = os.path.join(".rush", ".update")
BACKUP_DIR_REL = os.path.join(".rush", "backups")

# Roots install.sh copies from the kit. Order matters only for readability.
KIT_ROOTS = (".claude", ".rush")

# Paths that exist inside those roots but are never the kit's to manage.
NEVER_MANAGED = (
    ".rush/config.json",
    ".rush/state.json",
    ".rush/manifest.json",
    ".rush/baseline.tar.gz",
    ".rush/secret-scan-allow",
    ".rush/backups/*",
    ".rush/.update/*",
    ".rush/_incoming/*",
    "*.pyc",
    "*/__pycache__/*",
    ".DS_Store",
    "*/.DS_Store",
)

SEED_PATTERNS = (
    ".rush/memory/*",
    ".rush/memory/*/*",
)

MERGE_PATTERNS = (
    ".claude/settings.json",
)

# Inside a seed root, these stay kit-owned: they are documentation of the mechanism, not
# content the project authors.
SEED_EXCEPTIONS = (
    ".rush/memory/README.md",
)

# Classes the updater's agent may merge by judgement. Everything else that conflicts stops and
# asks a human: a bad merge in a hook blocks every write in the project, including its own fix.
AGENT_MERGEABLE = (
    ".claude/skills/*",
    ".claude/skills/*/*",
    ".claude/agents/*",
    ".rush/templates/*",
)


def norm(path):
    return path.replace(os.sep, "/")


def matches_any(rel, patterns):
    return any(fnmatch.fnmatch(rel, p) for p in patterns)


def classify(rel):
    """Return 'kit', 'seed', 'merge' or None (not managed) for a project-relative path."""
    rel = norm(rel)
    if matches_any(rel, NEVER_MANAGED):
        return None
    if not any(rel == r or rel.startswith(r + "/") for r in KIT_ROOTS):
        return None
    if rel in MERGE_PATTERNS:
        return "merge"
    if rel in SEED_EXCEPTIONS:
        return "kit"
    if matches_any(rel, SEED_PATTERNS):
        return "seed"
    return "kit"


def agent_mergeable(rel):
    return matches_any(norm(rel), AGENT_MERGEABLE)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def walk_kit(root):
    """Every managed file under a kit or project root, as {relpath: class}."""
    out = {}
    for top in KIT_ROOTS:
        base = os.path.join(root, top)
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in ("__pycache__", "backups", ".update", "_incoming")]
            for name in filenames:
                full = os.path.join(dirpath, name)
                rel = norm(os.path.relpath(full, root))
                cls = classify(rel)
                if cls:
                    out[rel] = cls
    return out


# --------------------------------------------------------------------------- manifest


def read_manifest(target):
    path = os.path.join(target, MANIFEST_REL)
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return None


def write_manifest(target, version, files, extra=None):
    """files: {relpath: {"sha256":..., "class":...}}"""
    manifest = {
        "kit_version": version,
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "files": dict(sorted(files.items())),
    }
    existing = read_manifest(target)
    manifest["installed_at"] = (existing or {}).get("installed_at") or manifest["updated_at"]
    if extra:
        manifest.update(extra)
    path = os.path.join(target, MANIFEST_REL)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, path)
    return manifest


def snapshot(kit, target, version):
    """Record the manifest (hashes of what is on disk) and the baseline (what the kit ships).

    The two deliberately differ for a file the project has customised: the manifest hash is of
    the LOCAL file, so the next update can tell it was touched; the baseline holds the kit's
    pristine version, so that next update has a base to merge against.
    """
    for rel in DEFERRED_TO_SNAPSHOT:
        src = os.path.join(kit, rel)
        if os.path.isfile(src):
            dst = os.path.join(target, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)

    kit_files = walk_kit(kit)
    files = {}
    for rel, cls in sorted(kit_files.items()):
        local = os.path.join(target, rel)
        if not os.path.isfile(local):
            continue
        entry = {"sha256": sha256_file(local), "class": cls}
        # kit_sha256 is what the KIT shipped for this file at this version, which is a different
        # thing from what is on disk whenever the project (or a merge) has diverged. Recording
        # both is what makes the next update a real three-way comparison: local vs shipped tells
        # us the project customised it, shipped-then vs shipped-now tells us the kit changed it.
        # Without it, a file the updater's agent merged looks pristine at the next update and
        # gets silently overwritten with the kit's version — losing the merge.
        src = os.path.join(kit, rel)
        if cls == "kit" and os.path.isfile(src):
            entry["kit_sha256"] = sha256_file(src)
        files[rel] = entry

    baseline_path = os.path.join(target, BASELINE_REL)
    os.makedirs(os.path.dirname(baseline_path), exist_ok=True)
    tmp = baseline_path + ".tmp"
    with tarfile.open(tmp, "w:gz") as tar:
        for rel, cls in sorted(kit_files.items()):
            if cls != "kit":
                continue
            src = os.path.join(kit, rel)
            if os.path.isfile(src):
                tar.add(src, arcname=rel)
    os.replace(tmp, baseline_path)

    return write_manifest(target, version, files)


def baseline_bytes(target, rel):
    """The pristine content the kit installed for one file, or None."""
    path = os.path.join(target, BASELINE_REL)
    if not os.path.isfile(path):
        return None
    try:
        with tarfile.open(path, "r:gz") as tar:
            member = tar.getmember(norm(rel))
            fh = tar.extractfile(member)
            return fh.read() if fh else None
    except Exception:
        return None


# --------------------------------------------------------------------------- planning


def read_version(root):
    path = os.path.join(root, ".rush", "VERSION")
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read().strip()
    except Exception:
        return None


def plan(kit, target, adopt=False):
    """Decide, file by file, what an update would do. Writes nothing."""
    manifest = read_manifest(target)
    from_version = (manifest or {}).get("kit_version") or read_version(target)
    to_version = read_version(kit)

    result = {
        "from_version": from_version,
        "to_version": to_version,
        "adopted": False,
        "target": target,
        "add": [],          # kit ships it, project does not have it
        "update": [],       # changed upstream, untouched locally -> safe replace
        "remove": [],       # kit dropped it, untouched locally -> safe delete
        "conflict": [],     # changed upstream AND locally
        "local_only": [],   # locally modified, unchanged upstream -> left alone, reported
        "unchanged": [],
        "seed_missing": [], # seed file the project never got (new memory scaffold, etc.)
        "settings_merge": None,
        "notes": [],
    }

    if manifest is None:
        if not adopt:
            result["error"] = (
                "no .rush/manifest.json in %s — this project was installed before the kit "
                "tracked what it owns. Re-run with --adopt to generate one from the current "
                "state." % target
            )
            return result
        result["adopted"] = True
        result["notes"].append(
            "Adopted a project with no manifest: local modifications to kit files cannot be "
            "detected on this first update, because there is nothing to compare against. Every "
            "kit file is treated as pristine and replaced; the originals are backed up."
        )

    known = (manifest or {}).get("files") or {}
    kit_files = walk_kit(kit)

    for rel, cls in sorted(kit_files.items()):
        local_path = os.path.join(target, rel)
        kit_path = os.path.join(kit, rel)
        exists = os.path.isfile(local_path)

        if cls == "merge":
            if exists:
                result["settings_merge"] = rel
            else:
                result["add"].append({"path": rel, "class": cls})
            continue

        if cls == "seed":
            if not exists:
                result["seed_missing"].append({"path": rel, "class": cls})
            continue

        new_sha = sha256_file(kit_path)
        if not exists:
            result["add"].append({"path": rel, "class": cls})
            continue

        local_sha = sha256_file(local_path)
        entry = known.get(rel) or {}
        # The reference for both questions is what the kit SHIPPED at the installed version.
        # Older manifests only recorded the local hash; falling back to it is right for them,
        # since at install time the two were the same file.
        shipped = entry.get("kit_sha256") or entry.get("sha256")
        locally_modified = shipped is not None and local_sha != shipped
        upstream_changed = shipped is None or new_sha != shipped

        if local_sha == new_sha:
            result["unchanged"].append({"path": rel})
        elif locally_modified and upstream_changed:
            result["conflict"].append({
                "path": rel,
                "class": cls,
                "agent_mergeable": agent_mergeable(rel),
                "has_base": baseline_bytes(target, rel) is not None,
            })
        elif locally_modified:
            result["local_only"].append({"path": rel})
        else:
            result["update"].append({"path": rel, "class": cls})

    for rel, meta in sorted(known.items()):
        if rel in kit_files or (meta.get("class") != "kit"):
            continue
        local_path = os.path.join(target, rel)
        if not os.path.isfile(local_path):
            continue
        if sha256_file(local_path) == meta.get("sha256"):
            result["remove"].append({"path": rel})
        else:
            result["conflict"].append({
                "path": rel, "class": "kit", "agent_mergeable": False,
                "has_base": baseline_bytes(target, rel) is not None,
                "reason": "removed upstream but modified locally",
            })

    result["summary"] = {
        "add": len(result["add"]),
        "update": len(result["update"]),
        "remove": len(result["remove"]),
        "conflict": len(result["conflict"]),
        "local_only": len(result["local_only"]),
        "unchanged": len(result["unchanged"]),
        "seed_missing": len(result["seed_missing"]),
    }
    return result


# --------------------------------------------------------------------------- settings merge


def merge_settings(kit, target, rel, dry_run=False):
    """Ensure the kit's hook wiring is current without touching anything else in the file.

    A project's .claude/settings.json is shared ground: the kit owns the entries whose command
    points at .rush/hooks/, the project owns permissions, other hooks, everything else. This
    replaces only the former, matched by the hook script path, and leaves the rest byte for byte.
    """
    kit_path = os.path.join(kit, rel)
    local_path = os.path.join(target, rel)
    report = {"path": rel, "changed": [], "kept": 0}
    try:
        with open(kit_path, encoding="utf-8") as fh:
            kit_cfg = json.load(fh)
        with open(local_path, encoding="utf-8") as fh:
            local_cfg = json.load(fh)
    except Exception as exc:
        report["error"] = "could not parse settings.json: %s" % exc
        return report

    def hook_command(entry):
        for h in (entry.get("hooks") or []):
            cmd = h.get("command") or ""
            if ".rush/hooks/" in cmd:
                return cmd.split(".rush/hooks/")[-1].split()[0]
        return None

    kit_hooks = kit_cfg.get("hooks") or {}
    local_hooks = local_cfg.setdefault("hooks", {})

    for event, groups in kit_hooks.items():
        local_groups = local_hooks.setdefault(event, [])
        for group in groups:
            name = hook_command(group)
            if name is None:
                continue
            replaced = False
            for i, existing in enumerate(local_groups):
                if hook_command(existing) == name:
                    if existing != group:
                        local_groups[i] = group
                        report["changed"].append("%s/%s" % (event, name))
                    replaced = True
                    break
            if not replaced:
                local_groups.append(group)
                report["changed"].append("%s/%s (added)" % (event, name))
        report["kept"] += sum(1 for g in local_groups if hook_command(g) is None)

    if not dry_run and report["changed"]:
        tmp = local_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(local_cfg, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        os.replace(tmp, local_path)
    return report


# --------------------------------------------------------------------------- apply


def backup(target, rel, stamp):
    src = os.path.join(target, rel)
    if not os.path.isfile(src):
        return None
    dst = os.path.join(target, BACKUP_DIR_REL, stamp, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)
    return norm(os.path.relpath(dst, target))


# .rush/VERSION is written by snapshot(), not by apply(), so it can never claim a version the
# project has not finished moving to. A half-applied update with conflicts still pending would
# otherwise report the new version to doctor.sh while running the old prompts.
DEFERRED_TO_SNAPSHOT = (".rush/VERSION",)


def apply_plan(kit, target, p, stamp=None):
    """Apply everything the plan decided without judgement, and stage the rest for the agent."""
    stamp = stamp or time.strftime("%Y%m%d-%H%M%S")
    applied = {"stamp": stamp, "backed_up": [], "written": [], "removed": [], "staged": []}

    for item in p["add"] + p["update"] + p["seed_missing"]:
        rel = item["path"]
        if norm(rel) in DEFERRED_TO_SNAPSHOT:
            continue
        src = os.path.join(kit, rel)
        dst = os.path.join(target, rel)
        if os.path.isfile(dst):
            b = backup(target, rel, stamp)
            if b:
                applied["backed_up"].append(b)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(src, dst)
        if rel.endswith(".sh"):
            os.chmod(dst, 0o755)
        applied["written"].append(rel)

    for item in p["remove"]:
        rel = item["path"]
        b = backup(target, rel, stamp)
        if b:
            applied["backed_up"].append(b)
        try:
            os.remove(os.path.join(target, rel))
            applied["removed"].append(rel)
        except OSError:
            pass

    # Conflicts: stage the three versions side by side. Nothing in the project is changed —
    # the working file stays exactly as the user left it until the merge is resolved.
    stage_root = os.path.join(target, UPDATE_DIR_REL, stamp)
    for item in p["conflict"]:
        rel = item["path"]
        for kind, data in (
            ("base", baseline_bytes(target, rel)),
            ("local", _read_bytes(os.path.join(target, rel))),
            ("new", _read_bytes(os.path.join(kit, rel))),
        ):
            if data is None:
                continue
            dst = os.path.join(stage_root, kind, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "wb") as fh:
                fh.write(data)
        b = backup(target, rel, stamp)
        if b:
            applied["backed_up"].append(b)
        applied["staged"].append({
            "path": rel,
            "agent_mergeable": item.get("agent_mergeable", False),
            "base": norm(os.path.join(UPDATE_DIR_REL, stamp, "base", rel)),
            "local": norm(os.path.join(UPDATE_DIR_REL, stamp, "local", rel)),
            "new": norm(os.path.join(UPDATE_DIR_REL, stamp, "new", rel)),
            "reason": item.get("reason", "changed upstream and locally"),
        })

    return applied


def _read_bytes(path):
    if not os.path.isfile(path):
        return None
    with open(path, "rb") as fh:
        return fh.read()


# --------------------------------------------------------------------------- migrations


def _semver(v):
    try:
        return tuple(int(x) for x in str(v).strip().split(".")[:3])
    except Exception:
        return (0, 0, 0)


def load_migrations(kit):
    """Migration modules from the NEW kit, ordered by version.

    They live in the kit being installed, never in the project, because only the version
    introducing a change knows what that change means for a config written before it.
    """
    import importlib.util

    d = os.path.join(kit, ".rush", "migrations")
    if not os.path.isdir(d):
        return []
    mods = []
    for name in sorted(os.listdir(d)):
        if not name.endswith(".py") or name.startswith("_"):
            continue
        path = os.path.join(d, name)
        spec = importlib.util.spec_from_file_location("rush_migration_" + name[:-3].replace(".", "_"), path)
        if spec is None or spec.loader is None:
            continue
        mod = importlib.util.module_from_spec(spec)
        try:
            spec.loader.exec_module(mod)
        except Exception as exc:
            mods.append(("0.0.0", name, None, str(exc)))
            continue
        mods.append((getattr(mod, "VERSION", name[:-3]), name, mod, None))
    mods.sort(key=lambda m: _semver(m[0]))
    return mods


def migrate_config(kit, target, from_version, to_version, dry_run=False):
    """Apply every migration in (from_version, to_version] to .rush/config.json.

    The question each migration answers is not "what is the new default" but "did the project
    CHOOSE this value, or inherit it from a default that has since changed". A value equal to
    the old default was never a decision, so it follows the kit; a value the project set on
    purpose is kept, and reported so nobody is surprised by it later.
    """
    cfg_path = os.path.join(target, ".rush", "config.json")
    result = {"config": ".rush/config.json", "applied": [], "changes": [], "skipped": []}
    if not os.path.isfile(cfg_path):
        result["skipped"].append("no config.json yet — nothing to migrate (it is generated by /rush-init)")
        return result
    try:
        with open(cfg_path, encoding="utf-8") as fh:
            cfg = json.load(fh)
    except Exception as exc:
        result["error"] = "config.json does not parse: %s" % exc
        return result

    lo, hi = _semver(from_version), _semver(to_version)
    for version, name, mod, err in load_migrations(kit):
        if err:
            result["skipped"].append("%s failed to load: %s" % (name, err))
            continue
        v = _semver(version)
        if not (lo < v <= hi):
            continue
        changes = []
        try:
            mod.migrate(cfg, changes)
        except Exception as exc:
            result["skipped"].append("%s raised: %s" % (name, exc))
            continue
        result["applied"].append({"version": version, "description": getattr(mod, "DESCRIPTION", "")})
        result["changes"].extend(changes)

    if not dry_run and result["changes"]:
        tmp = cfg_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(cfg, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        os.replace(tmp, cfg_path)
    return result


# --------------------------------------------------------------------------- CLI


def _cmd_plan(args):
    p = plan(args.kit, args.target, adopt=args.adopt)
    print(json.dumps(p, indent=2 if args.pretty else None, ensure_ascii=False))
    return 2 if p.get("error") else (1 if p["summary"]["conflict"] else 0)


def _cmd_apply(args):
    p = plan(args.kit, args.target, adopt=args.adopt)
    if p.get("error"):
        print(json.dumps(p, ensure_ascii=False))
        return 2
    applied = apply_plan(args.kit, args.target, p)
    if p.get("settings_merge"):
        applied["settings"] = merge_settings(args.kit, args.target, p["settings_merge"])
    out = {"plan": p, "applied": applied}
    print(json.dumps(out, indent=2 if args.pretty else None, ensure_ascii=False))
    return 1 if applied["staged"] else 0


def _cmd_snapshot(args):
    m = snapshot(args.kit, args.target, args.version or read_version(args.kit))
    print(json.dumps({"kit_version": m["kit_version"], "files": len(m["files"])}, ensure_ascii=False))
    return 0


def _cmd_migrate(args):
    r = migrate_config(args.kit, args.target, args.from_version, args.to_version, dry_run=args.dry_run)
    print(json.dumps(r, indent=2 if args.pretty else None, ensure_ascii=False))
    return 2 if r.get("error") else 0


def _cmd_classify(args):
    print(json.dumps({p: classify(p) for p in args.paths}, ensure_ascii=False))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("plan", help="Decide what an update would do. Writes nothing.")
    sp.add_argument("--kit", required=True)
    sp.add_argument("--target", required=True)
    sp.add_argument("--adopt", action="store_true")
    sp.add_argument("--pretty", action="store_true")
    sp.set_defaults(func=_cmd_plan)

    sp = sub.add_parser("apply", help="Apply the unambiguous part and stage conflicts.")
    sp.add_argument("--kit", required=True)
    sp.add_argument("--target", required=True)
    sp.add_argument("--adopt", action="store_true")
    sp.add_argument("--pretty", action="store_true")
    sp.set_defaults(func=_cmd_apply)

    sp = sub.add_parser("snapshot", help="Write .rush/manifest.json and .rush/baseline.tar.gz.")
    sp.add_argument("--kit", required=True)
    sp.add_argument("--target", required=True)
    sp.add_argument("--version")
    sp.set_defaults(func=_cmd_snapshot)

    sp = sub.add_parser("migrate", help="Apply config.json migrations between two versions.")
    sp.add_argument("--kit", required=True)
    sp.add_argument("--target", required=True)
    sp.add_argument("--from", dest="from_version", required=True)
    sp.add_argument("--to", dest="to_version", required=True)
    sp.add_argument("--dry-run", action="store_true")
    sp.add_argument("--pretty", action="store_true")
    sp.set_defaults(func=_cmd_migrate)

    sp = sub.add_parser("classify", help="Print the ownership class of one or more paths.")
    sp.add_argument("paths", nargs="+")
    sp.set_defaults(func=_cmd_classify)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

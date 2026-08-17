# Changelog

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

#!/usr/bin/env bash
# description: no module imports another module's internals directly (must go through its public index/API)
# scope: all
#
# This is a copy-paste template for a project fitness function. Fitness
# functions live in .rush/memory/fitness/*.sh, are run by
# .rush/scripts/fitness.sh, and encode an architectural rule from
# .rush/memory/architecture.md as an executable check instead of prose
# that nobody re-reads.
#
# Contract every fitness function must honour:
#   - #!/usr/bin/env bash + set -euo pipefail
#   - the two header comments above (description / scope), read verbatim
#     by fitness.sh via regex - keep them on their own "# key: value" line
#   - scope is "all" or a comma-separated list of feature ids (or
#     prefixes, e.g. "007" matches "007-checkout")
#   - runs with the project root as its current working directory
#   - exit 0 = pass, exit 1 = fail (any non-zero = fail)
#   - on failure, print what it found to stdout/stderr; fitness.sh keeps
#     the last 40 lines and only shows them when the check fails
#   - no network, no writes outside a temp dir
#
# What this example checks: source files under src/<module>/ must not
# import a sibling module's internal files directly
# (src/other-module/internal/...); they may only import that module's
# public entry point (src/other-module/index.*, src/other-module.*).
# Adjust MODULES_ROOT and the import-statement regex to match your stack
# (this default pattern covers common JS/TS relative-import syntax).
set -euo pipefail

MODULES_ROOT="src"
violations=0

if [ ! -d "$MODULES_ROOT" ]; then
  # Nothing to check yet (e.g. a fresh project) - that is not a violation.
  exit 0
fi

# Find relative imports that reach into another module's internals, e.g.:
#   import { x } from "../other-module/internal/thing"
# but allow imports of another module's public entry point:
#   import { x } from "../other-module"
#   import { x } from "../other-module/index"
while IFS= read -r match; do
  file="${match%%:*}"
  rest="${match#*:}"
  line_no="${rest%%:*}"
  content="${rest#*:}"

  file_module="$(printf '%s' "$file" | sed -n "s#^$MODULES_ROOT/\\([^/]*\\)/.*#\\1#p")"
  target_module="$(printf '%s' "$content" | sed -n "s#.*\\.\\./\\([^/'\"]*\\)/internal/.*#\\1#p")"

  if [ -n "$file_module" ] && [ -n "$target_module" ] && [ "$file_module" != "$target_module" ]; then
    echo "cross-module internal import: $file:$line_no imports $target_module/internal from module '$file_module'"
    echo "    $content"
    violations=$((violations + 1))
  fi
done < <(grep -rnE "from ['\"]\.\./[^'\"]+/internal/" "$MODULES_ROOT" --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' 2>/dev/null || true)

if [ "$violations" -gt 0 ]; then
  echo "$violations cross-module internal import(s) found"
  exit 1
fi

exit 0

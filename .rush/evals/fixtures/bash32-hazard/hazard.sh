#!/usr/bin/env bash
# Synthetic reproduction of the real incident: a heredoc inside $( ) whose body
# contains a literal backtick. bash 5 parses this; macOS bash 3.2 does not, and
# fails with a whole-file syntax error.
PYCODE=$(cat <<'PYEOF'
import re
DONE = re.compile(r"status:\s*[`']*done")
PYEOF
)
python3 -c "$PYCODE"

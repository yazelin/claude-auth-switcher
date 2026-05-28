#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
line="source \"$root/shell/bash.sh\""
rc="$HOME/.bashrc"
chmod +x "$root/bin/cl"
if grep -Fq "$line" "$rc" 2>/dev/null; then
  echo "already wired into $rc"
else
  printf '\n# claude-auth-switcher\n%s\n' "$line" >> "$rc"
  echo "added to $rc"
fi
command -v jq   >/dev/null || echo "WARNING: jq not found — install it (e.g. apt install jq / brew install jq)"
command -v curl >/dev/null || echo "WARNING: curl not found"
echo "done. Open a new shell, then: cl import <name>"

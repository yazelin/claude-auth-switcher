#!/usr/bin/env bash
# Undo what install.sh / install-oneliner.sh did:
#   - remove the "# claude-auth-switcher" + source line from your shell rc file(s)
# By default your saved accounts in ~/.claude_auth_profiles are KEPT.
# Pass --purge to also delete them.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
line="source \"$root/shell/bash.sh\""
profiles_dir="${CL_PROFILES_DIR:-$HOME/.claude_auth_profiles}"

purge=0
for arg in "$@"; do
  case "$arg" in
    --purge) purge=1 ;;
    -h|--help)
      echo "usage: bash uninstall.sh [--purge]"
      echo "  --purge   also delete saved accounts in $profiles_dir"
      exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Remove our block from a single rc file (the comment line, the exact source
# line, and any source line still pointing at a claude-auth-switcher install).
clean_rc() {
  local rc="$1"
  [ -f "$rc" ] || return 0
  if ! grep -Fq "claude-auth-switcher" "$rc" 2>/dev/null; then
    return 0
  fi
  local tmp; tmp="$(mktemp)"
  awk -v exact="$line" '
    $0 == "# claude-auth-switcher" { next }
    $0 == exact { next }
    /claude-auth-switcher\/shell\/bash\.sh/ { next }
    { print }
  ' "$rc" > "$tmp"
  if ! cmp -s "$rc" "$tmp"; then
    cp "$rc" "$rc.cl-bak"
    cat "$tmp" > "$rc"
    echo "cleaned $rc (backup: $rc.cl-bak)"
  fi
  rm -f "$tmp"
}

for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile"; do
  clean_rc "$rc"
done

if [ "$purge" -eq 1 ]; then
  if [ -d "$profiles_dir" ]; then
    rm -rf "$profiles_dir"
    echo "purged saved accounts: $profiles_dir"
  fi
else
  if [ -d "$profiles_dir" ]; then
    echo "kept saved accounts: $profiles_dir (re-run with --purge to remove)"
  fi
fi

echo
echo "shell wiring removed. The 'cl' command is gone from new shells."
echo "This repo was left in place. To delete it too, run:"
echo "  rm -rf \"$root\""

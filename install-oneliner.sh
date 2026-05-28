#!/usr/bin/env bash
set -euo pipefail
repo="${CL_REPO:-https://github.com/yazelin/claude-auth-switcher.git}"
dest="${CL_DEST:-$HOME/claude-auth-switcher}"
if [ -d "$dest/.git" ]; then
  git -C "$dest" pull --ff-only
else
  git clone "$repo" "$dest"
fi
bash "$dest/install.sh"

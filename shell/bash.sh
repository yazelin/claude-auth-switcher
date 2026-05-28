# Source from ~/.bashrc:  source "$HOME/claude-auth-switcher/shell/bash.sh"
_cl_file="${BASH_SOURCE[0]}"
while [ -L "$_cl_file" ]; do
  _cl_dir="$(cd -P "$(dirname "$_cl_file")" && pwd)"
  _cl_file="$(readlink "$_cl_file")"
  case "$_cl_file" in /*) ;; *) _cl_file="$_cl_dir/$_cl_file" ;; esac
done
_cl_root="$(cd -P "$(dirname "$_cl_file")/.." && pwd)"
cl() { "$_cl_root/bin/cl" "$@"; }

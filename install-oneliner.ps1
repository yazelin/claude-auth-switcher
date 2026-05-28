# irm https://raw.githubusercontent.com/yazelin/claude-auth-switcher/main/install-oneliner.ps1 | iex
$ErrorActionPreference = 'Stop'
$repo = if ($env:CL_REPO) { $env:CL_REPO } else { 'https://github.com/yazelin/claude-auth-switcher.git' }
$dest = if ($env:CL_DEST) { $env:CL_DEST } else { Join-Path $HOME 'claude-auth-switcher' }
if (Test-Path (Join-Path $dest '.git')) {
  git -C $dest pull --ff-only
} else {
  git clone $repo $dest
}
& (Join-Path $dest 'install.ps1')

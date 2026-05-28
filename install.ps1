# Wire claude-auth-switcher into your PowerShell profile.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$line = ". `"$root\shell\powershell.ps1`""
if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
if (Select-String -Path $PROFILE -SimpleMatch $line -Quiet) {
  "already wired into $PROFILE"
} else {
  Add-Content -Path $PROFILE -Value "`n# claude-auth-switcher`n$line"
  "added to $PROFILE"
}
"done. Open a new PowerShell, then: cl import <name>"

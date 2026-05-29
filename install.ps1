# Wire claude-auth-switcher into your PowerShell profile(s).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$line = ". `"$root\shell\powershell.ps1`""

# The cl function prefers pwsh (PowerShell 7) when present, else powershell (5.1),
# and the two hosts read different profiles. Wire both so cl works whichever you
# launch. MyDocuments resolves redirected Documents folders (e.g. OneDrive).
$docs = [Environment]::GetFolderPath('MyDocuments')
$targets = @(
  $PROFILE
  Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
  Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'
) | Select-Object -Unique

foreach ($p in $targets) {
  if (-not (Test-Path $p)) { New-Item -ItemType File -Path $p -Force | Out-Null }
  if (Select-String -Path $p -SimpleMatch $line -Quiet) {
    "already wired into $p"
  } else {
    Add-Content -Path $p -Value "`n# claude-auth-switcher`n$line"
    "added to $p"
  }
}
"done. Open a new PowerShell, then: cl import <name>"

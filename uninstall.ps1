# Undo what install.ps1 / install-oneliner.ps1 did:
#   - remove the "# claude-auth-switcher" + dot-source line from your PowerShell profile(s)
# By default your saved accounts in %USERPROFILE%\.claude_auth_profiles are KEPT.
# Pass -Purge to also delete them.
param([switch]$Purge)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$line = ". `"$root\shell\powershell.ps1`""
$profilesDir = if ($env:CL_PROFILES_DIR) { $env:CL_PROFILES_DIR } else { Join-Path $env:USERPROFILE '.claude_auth_profiles' }

# install.ps1 wires every host's profile, so clean all the same candidates.
$docs = [Environment]::GetFolderPath('MyDocuments')
$targets = @(
  $PROFILE
  Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
  Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'
) | Select-Object -Unique

foreach ($p in $targets) {
  if (-not (Test-Path $p)) { continue }
  $content = Get-Content -LiteralPath $p
  $kept = $content | Where-Object {
    ($_.Trim() -ne '# claude-auth-switcher') -and
    ($_.Trim() -ne $line) -and
    ($_ -notmatch 'claude-auth-switcher[\\/]shell[\\/]powershell\.ps1')
  }
  if ($kept.Count -ne $content.Count) {
    Copy-Item -LiteralPath $p -Destination "$p.cl-bak" -Force
    Set-Content -LiteralPath $p -Value $kept
    "cleaned $p (backup: $p.cl-bak)"
  }
}

if ($Purge) {
  if (Test-Path -LiteralPath $profilesDir) {
    Remove-Item -LiteralPath $profilesDir -Recurse -Force
    "purged saved accounts: $profilesDir"
  }
} else {
  if (Test-Path -LiteralPath $profilesDir) {
    "kept saved accounts: $profilesDir (re-run with -Purge to remove)"
  }
}

""
"Shell wiring removed. The 'cl' command is gone from new PowerShell sessions."
"This repo was left in place. To delete it too, run:"
"  Remove-Item -Recurse -Force `"$root`""

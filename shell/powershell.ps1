# Dot-source from your PowerShell profile:
#   . "$HOME\claude-auth-switcher\shell\powershell.ps1"
$script:ClRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script:ClExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
function cl { & $script:ClExe -NoProfile -File (Join-Path $script:ClRoot 'bin\cl.ps1') @args }

# Dot-source from your PowerShell profile:
#   . "$HOME\claude-auth-switcher\shell\powershell.ps1"
$script:ClRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
function cl { & pwsh -NoProfile -File (Join-Path $script:ClRoot 'bin\cl.ps1') @args }

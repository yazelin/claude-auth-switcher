# claude-auth-switcher - Windows / PowerShell port of bin/cl.
#
# NOTE: assumes Claude Code stores credentials as a plaintext JSON file at
# $env:USERPROFILE\.claude\.credentials.json. This must be confirmed on a real
# Windows machine (see docs/superpowers/specs/...section 4). If the store turns
# out to be DPAPI / Credential Manager, the Read-Cred/Write-Cred functions below
# are the only places that need changing.

[CmdletBinding()]
param(
  [Parameter(Position = 0)] [string] $Command = 'help',
  [Parameter(Position = 1, ValueFromRemainingArguments = $true)] [string[]] $Rest
)

$ErrorActionPreference = 'Stop'

$CL_CRED         = if ($env:CL_CRED)         { $env:CL_CRED }         else { Join-Path $env:USERPROFILE '.claude\.credentials.json' }
$CL_PROFILES_DIR = if ($env:CL_PROFILES_DIR) { $env:CL_PROFILES_DIR } else { Join-Path $env:USERPROFILE '.claude_auth_profiles' }
$CL_CLIENT_ID    = if ($env:CL_CLIENT_ID)    { $env:CL_CLIENT_ID }    else { '9d1c250a-e61b-44d9-88ed-5944d1962f5e' }
$CL_TOKEN_URL    = if ($env:CL_TOKEN_URL)    { $env:CL_TOKEN_URL }    else { 'https://platform.claude.com/v1/oauth/token' }
$CL_USAGE_URL    = if ($env:CL_USAGE_URL)    { $env:CL_USAGE_URL }    else { 'https://api.anthropic.com/api/oauth/usage' }
$CL_REFRESH_BUFFER_MS = 60000

function Die([string]$msg) { Write-Error "cl: $msg"; exit 1 }
function Now-Ms { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }

function Ensure-Dir {
  if (-not (Test-Path $CL_PROFILES_DIR)) { New-Item -ItemType Directory -Path $CL_PROFILES_DIR | Out-Null }
}

# --- The two platform-specific primitives (change these if storage isn't plaintext) ---
function Read-Cred {
  if (-not (Test-Path $CL_CRED)) { Die "no credentials at $CL_CRED - log in with Claude Code first" }
  Get-Content $CL_CRED -Raw | ConvertFrom-Json
}
function Write-Cred($cred) {
  $cred | ConvertTo-Json -Depth 25 | Set-Content $CL_CRED -Encoding utf8
}
# -------------------------------------------------------------------------------------

function Profile-Path([string]$name) { Join-Path $CL_PROFILES_DIR "$name.json" }
function Usage-Path([string]$name)   { Join-Path $CL_PROFILES_DIR "$name.usage.json" }
function Current-Path                 { Join-Path $CL_PROFILES_DIR 'current' }

function Get-Current {
  if (Test-Path (Current-Path)) { (Get-Content (Current-Path) -Raw).Trim() } else { 'none' }
}
function Set-Current([string]$name) { $name | Set-Content (Current-Path) -Encoding utf8 }

function Token-Expired($oauth) {
  $exp = if ($oauth.expiresAt) { [int64]$oauth.expiresAt } else { 0 }
  return ($exp -lt ((Now-Ms) + $CL_REFRESH_BUFFER_MS))
}

function Refresh-Oauth($oauth) {
  $body = @{ grant_type = 'refresh_token'; refresh_token = $oauth.refreshToken; client_id = $CL_CLIENT_ID } | ConvertTo-Json
  $resp = Invoke-RestMethod -Method Post -Uri $CL_TOKEN_URL -ContentType 'application/json' -Body $body
  if (-not $resp.access_token) { return $null }
  $oauth.accessToken  = $resp.access_token
  if ($resp.refresh_token) { $oauth.refreshToken = $resp.refresh_token }
  $expin = if ($resp.expires_in) { [int64]$resp.expires_in } else { 0 }
  $oauth.expiresAt = (Now-Ms) + ($expin * 1000)
  return $oauth
}

function Fetch-Usage([string]$access) {
  Invoke-RestMethod -Uri $CL_USAGE_URL -Headers @{
    Authorization       = "Bearer $access"
    'anthropic-beta'    = 'oauth-2025-04-20'
    'anthropic-version' = '2023-06-01'
  }
}

function Format-Usage($usage) {
  foreach ($row in @(
      @('5h', 'five_hour'), @('weekly', 'seven_day'),
      @('weekly-opus', 'seven_day_opus'), @('weekly-sonnet', 'seven_day_sonnet'))) {
    $b = $usage.($row[1])
    if ($null -ne $b -and $null -ne $b.utilization) {
      $reset = if ($b.resets_at) { ([datetime]$b.resets_at).ToString('MM/dd HH:mm') } else { '' }
      '{0,-14} {1,5}% used   {2}' -f $row[0], $b.utilization, ($(if ($reset) { "reset $reset" } else { '' }))
    }
  }
}

function Find-ProfileByRefresh([string]$want) {
  Get-ChildItem $CL_PROFILES_DIR -Filter '*.json' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike '*.usage.json' } | ForEach-Object {
      $o = Get-Content $_.FullName -Raw | ConvertFrom-Json
      if ($o.refreshToken -eq $want) { return ($_.BaseName) }
    } | Select-Object -First 1
}

function Cmd-Help {
@'
usage:
  cl login <name>        Add a new account (opens browser OAuth)
  cl import <name>       Save current ~/.claude account as a profile
  cl use <name>          Switch active account (merges only claudeAiOauth)
  cl switch              Interactive switcher
  cl list                List profiles, active marker, cached usage
  cl usage [name|--all]  Fetch live usage (default: active)
  cl current             Print active profile
  cl remove <name>       Delete a profile
  cl export <a.zip>      Back up all profiles
  cl restore <a.zip>     Restore profiles from archive
  cl doctor              Show paths, profile summary
  cl help                Show this help

env: CL_PROFILES_DIR (default ~\.claude_auth_profiles), CL_CRED (default ~\.claude\.credentials.json)
'@
}

function Cmd-Login([string]$name) {
  if (-not $name) { Die 'usage: cl login <name>' }
  if (-not (Test-Path $CL_CRED)) { Die "no credentials at $CL_CRED - run claude first to initialise Claude Code" }

  $backup = "$CL_CRED.cl_bak"
  Copy-Item $CL_CRED $backup -Force
  Remove-Item $CL_CRED -Force

  $ok = $false
  try {
    & claude auth login
    if (Test-Path $CL_CRED) {
      $cred = Get-Content $CL_CRED -Raw | ConvertFrom-Json
      if ($cred.claudeAiOauth) {
        Ensure-Dir
        $cred.claudeAiOauth | ConvertTo-Json -Depth 25 | Set-Content (Profile-Path $name) -Encoding utf8
        Set-Current $name
        $ok = $true
      }
    }
  } finally {
    if (Test-Path $backup) {
      Copy-Item $backup $CL_CRED -Force
      Remove-Item $backup -Force
    }
  }

  if ($ok) { "saved as '$name'; run 'cl use $name' to switch" }
  else { Die 'login did not complete or credentials were not written' }
}

function Cmd-Import([string]$name) {
  if (-not $name) { Die 'usage: cl import <name>' }
  $cred = Read-Cred
  if (-not $cred.claudeAiOauth) { Die "no claudeAiOauth block in $CL_CRED" }
  $cred.claudeAiOauth | ConvertTo-Json -Depth 25 | Set-Content (Profile-Path $name) -Encoding utf8
  Set-Current $name
  "imported '$name'"
}

function Cmd-Use([string[]]$argv) {
  $name = $null; $force = $false
  foreach ($a in $argv) {
    switch -regex ($a) {
      '^(--force|-y|--yes)$' { $force = $true }
      '^-' { Die "unknown flag $a" }
      default { $name = $a }
    }
  }
  if (-not $name) { Die 'usage: cl use <name> [--force]' }
  $pf = Profile-Path $name
  if (-not (Test-Path $pf)) { Die "no such profile: $name" }
  if (Test-Path $CL_CRED) {
    $cred = Read-Cred
    $curRt = $cred.claudeAiOauth.refreshToken
    $owner = Find-ProfileByRefresh $curRt
    if (-not $owner -and -not $force) {
      Die "current account is not saved as a profile - 'cl import <name>' first, or pass --force"
    }
  } else {
    $cred = [PSCustomObject]@{}
  }
  $oauth = Get-Content $pf -Raw | ConvertFrom-Json
  if (Token-Expired $oauth) {
    $r = Refresh-Oauth $oauth
    if ($null -eq $r) { Die "token refresh failed for '$name' - re-login in Claude Code then 'cl import $name'" }
    $oauth = $r
    $oauth | ConvertTo-Json -Depth 25 | Set-Content $pf -Encoding utf8
  }
  $cred.claudeAiOauth = $oauth
  Write-Cred $cred
  Set-Current $name
  "switched to '$name'"
}

function Cmd-List {
  $cur = Get-Current
  $items = Get-ChildItem $CL_PROFILES_DIR -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*.usage.json' }
  if (-not $items) { 'no profiles - ''cl import <name>'' to add one'; return }
  foreach ($f in $items) {
    $name = $f.BaseName
    $o = Get-Content $f.FullName -Raw | ConvertFrom-Json
    $mark = if ($name -eq $cur) { '* ' } else { '  ' }
    $sub = if ($o.subscriptionType) { $o.subscriptionType } else { '?' }
    $extra = ''
    $uf = Usage-Path $name
    if (Test-Path $uf) {
      $u = Get-Content $uf -Raw | ConvertFrom-Json
      $extra = "5h=$($u.five_hour.utilization)% wk=$($u.seven_day.utilization)%"
    }
    '{0}{1,-16} {2,-6} {3}' -f $mark, $name, $sub, $extra
  }
}

function Usage-One([string]$name) {
  $pf = Profile-Path $name
  if (-not (Test-Path $pf)) { "  (${name}: no such profile)"; return }
  $oauth = Get-Content $pf -Raw | ConvertFrom-Json
  if (Token-Expired $oauth) {
    $r = Refresh-Oauth $oauth
    if ($r) { $oauth = $r; $oauth | ConvertTo-Json -Depth 25 | Set-Content $pf -Encoding utf8 }
  }
  try {
    $usage = Fetch-Usage $oauth.accessToken
  } catch { "$($name): usage query failed: $_"; return }
  $usage | ConvertTo-Json -Depth 25 | Set-Content (Usage-Path $name) -Encoding utf8
  "$($name):"
  Format-Usage $usage
}

function Cmd-Usage([string[]]$argv) {
  $arg = if ($argv) { $argv[0] } else { '' }
  if ($arg -eq '--all') {
    Get-ChildItem $CL_PROFILES_DIR -Filter '*.json' -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -notlike '*.usage.json' } | ForEach-Object { Usage-One $_.BaseName }
  } elseif ($arg) {
    Usage-One $arg
  } else {
    $cur = Get-Current
    if ($cur -eq 'none') { Die 'no active profile' }
    Usage-One $cur
  }
}

function Cmd-Remove([string]$name) {
  if (-not $name) { Die 'usage: cl remove <name>' }
  $pf = Profile-Path $name
  if (-not (Test-Path $pf)) { Die "no such profile: $name" }
  Remove-Item $pf -Force
  if (Test-Path (Usage-Path $name)) { Remove-Item (Usage-Path $name) -Force }
  if ((Get-Current) -eq $name -and (Test-Path (Current-Path))) { Remove-Item (Current-Path) -Force }
  "removed '$name'"
}

function Cmd-Switch {
  $names = Get-ChildItem $CL_PROFILES_DIR -Filter '*.json' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike '*.usage.json' } | ForEach-Object { $_.BaseName }
  if (-not $names) { Die "no profiles - 'cl import <name>' first" }
  if (Get-Process claude -ErrorAction SilentlyContinue) {
    Write-Warning 'a claude process is running; switching changes its token on next API call.'
  }
  'select a profile:'
  for ($i = 0; $i -lt $names.Count; $i++) { '  {0}) {1}' -f ($i + 1), $names[$i] }
  $sel = Read-Host 'choice'
  if ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $names.Count) { Die 'invalid choice' }
  Cmd-Use @($names[[int]$sel - 1])
}

function Cmd-Export([string]$arc) {
  if (-not $arc) { Die 'usage: cl export <archive.zip>' }
  Compress-Archive -Path (Join-Path $CL_PROFILES_DIR '*.json') -DestinationPath $arc -Force
  "exported profiles to $arc"
}
function Cmd-Restore([string]$arc) {
  if (-not $arc) { Die 'usage: cl restore <archive.zip>' }
  if (-not (Test-Path $arc)) { Die "no such archive: $arc" }
  Ensure-Dir
  Expand-Archive -Path $arc -DestinationPath $CL_PROFILES_DIR -Force
  "restored profiles from $arc"
}

function Cmd-Doctor {
  'claude-auth-switcher doctor'
  "  profiles dir : $CL_PROFILES_DIR"
  "  credentials  : $CL_CRED $(if (Test-Path $CL_CRED) {'(present)'} else {'(MISSING)'})"
  "  claude proc  : $(if (Get-Process claude -ErrorAction SilentlyContinue) {'running'} else {'not running'})"
  "  active       : $(Get-Current)"
  '  profiles     :'
  Cmd-List | ForEach-Object { "    $_" }
}

Ensure-Dir
switch ($Command) {
  'help'    { Cmd-Help }
  '-h'      { Cmd-Help }
  '--help'  { Cmd-Help }
  'login'   { Cmd-Login ($Rest[0]) }
  'import'  { Cmd-Import ($Rest[0]) }
  'use'     { Cmd-Use $Rest }
  'switch'  { Cmd-Switch }
  'list'    { Cmd-List }
  'ls'      { Cmd-List }
  'usage'   { Cmd-Usage $Rest }
  'current' { Get-Current }
  'remove'  { Cmd-Remove ($Rest[0]) }
  'rm'      { Cmd-Remove ($Rest[0]) }
  'export'  { Cmd-Export ($Rest[0]) }
  'restore' { Cmd-Restore ($Rest[0]) }
  'doctor'  { Cmd-Doctor }
  default   { Cmd-Help }
}

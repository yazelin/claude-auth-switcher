# claude-auth-switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pure-shell CLI (`cl`) that manages multiple Claude subscription accounts on one machine, switching the active account by swapping only the `claudeAiOauth` block of `~/.claude/.credentials.json` while preserving everything else.

**Architecture:** Testable core logic lives in a sourceable `lib/core.sh` (credential merge, token refresh, usage fetch/format — pure functions whose HTTP calls go through overridable wrappers). `bin/cl` is a thin CLI that parses args, takes a lock, does file IO, and calls the core functions. Windows (`bin/cl.ps1`) mirrors the same profile layout via PowerShell, gated behind a credential-storage verification spike.

**Tech Stack:** bash 5 + jq + curl (Linux/macOS-shell); PowerShell 5+ with built-in `ConvertFrom-Json` (Windows). Tests: a plain-bash harness (no bats), mocking HTTP by redefining wrapper functions.

**Reference:** mirrors `/home/ct/codex-auth-switcher` (command set, file layout, install flow). The validated design is in `docs/superpowers/specs/2026-05-29-claude-auth-switcher-design.md`.

---

## File Structure

```
claude-auth-switcher/
  lib/core.sh                  # sourceable pure functions + constants (testable heart)
  bin/cl                       # bash CLI dispatch
  bin/cl.ps1                   # Windows CLI (Phase 2, gated on verification)
  shell/bash.sh                # thin ~/.bashrc wrapper defining the `cl` function
  shell/powershell.ps1         # thin PowerShell profile wrapper (Phase 2)
  install.sh                   # clone-aware installer (wires bash.sh into profile)
  install-oneliner.sh          # curl|bash bootstrap that clones then runs install.sh
  install.ps1 / install-oneliner.ps1   # Windows installers (Phase 2)
  tests/helpers.sh             # assert helpers + fixtures
  tests/run.sh                 # test runner (runs all tests/test_*.sh)
  tests/test_*.sh              # one file per unit
  README.md
  LICENSE
  .gitignore                   # already present
  docs/                        # GitHub Pages (Phase 3)
```

Key boundaries:
- `lib/core.sh` has **no top-level side effects** — sourcing it only defines constants + functions, so tests can source it and redefine the HTTP wrappers before calling.
- All network access goes through exactly two wrappers: `cl_http_post_json` and `cl_http_get_usage`. Tests override these; nothing else touches curl.
- Constants (`CL_CLIENT_ID`, `CL_TOKEN_URL`, `CL_USAGE_URL`, `CL_CRED`, `CL_PROFILES_DIR`) are set with `: "${VAR:=default}"` so env vars override them in tests and at runtime.

---

# Phase 1 — Linux/bash (complete, shippable on its own)

## Task 1: Test harness

**Files:**
- Create: `tests/helpers.sh`
- Create: `tests/run.sh`
- Create: `tests/test_smoke.sh`

- [ ] **Step 1: Write the harness helpers**

Create `tests/helpers.sh`:

```bash
# Sourced by every test file. Provides assertions + a temp fixture dir.
set -u
CL_TEST_FAILS=0

_red()   { printf '\033[31m%s\033[0m\n' "$*"; }
_green() { printf '\033[32m%s\033[0m\n' "$*"; }

assert_eq() { # want, got, msg
  if [ "$1" != "$2" ]; then
    _red "  FAIL: ${3:-assert_eq}"; _red "    want: [$1]"; _red "    got:  [$2]"
    CL_TEST_FAILS=$((CL_TEST_FAILS+1))
  fi
}
assert_contains() { # haystack, needle, msg
  case "$1" in
    *"$2"*) ;;
    *) _red "  FAIL: ${3:-assert_contains}"; _red "    [$1] does not contain [$2]"
       CL_TEST_FAILS=$((CL_TEST_FAILS+1)) ;;
  esac
}
assert_ok()  { if ! eval "$1"; then _red "  FAIL: expected success: $1"; CL_TEST_FAILS=$((CL_TEST_FAILS+1)); fi; }
assert_fail(){ if eval "$1" 2>/dev/null; then _red "  FAIL: expected failure: $1"; CL_TEST_FAILS=$((CL_TEST_FAILS+1)); fi; }

# A throwaway HOME-like sandbox for a test; sets CL_CRED + CL_PROFILES_DIR into it.
new_sandbox() {
  CL_SANDBOX="$(mktemp -d)"
  export CL_PROFILES_DIR="$CL_SANDBOX/profiles"
  export CL_CRED="$CL_SANDBOX/.credentials.json"
  mkdir -p "$CL_PROFILES_DIR"
}
cleanup_sandbox() { [ -n "${CL_SANDBOX:-}" ] && rm -rf "$CL_SANDBOX"; }

# A realistic credentials.json: account token + an unrelated MCP token.
write_sample_cred() { # path, account-name-tag
  cat > "$1" <<JSON
{
  "claudeAiOauth": {
    "accessToken": "acc-${2}",
    "refreshToken": "ref-${2}",
    "expiresAt": 99999999999999,
    "subscriptionType": "max",
    "rateLimitTier": "default_claude_max_20x",
    "scopes": ["user:inference"]
  },
  "mcpOAuth": {
    "plugin:supabase:supabase|abc": { "serverName": "supabase", "accessToken": "MCP-KEEP-ME" }
  }
}
JSON
}
```

- [ ] **Step 2: Write the runner**

Create `tests/run.sh`:

```bash
#!/usr/bin/env bash
# Runs every tests/test_*.sh in a subshell. Exit non-zero if any assertion failed.
set -u
cd "$(dirname "$0")"
total=0
for t in test_*.sh; do
  echo "== $t =="
  ( CL_TEST_FAILS=0; source ./helpers.sh; source "./$t"; exit "$CL_TEST_FAILS" )
  rc=$?
  total=$((total+rc))
done
if [ "$total" -eq 0 ]; then printf '\033[32mALL TESTS PASSED\033[0m\n'; else printf '\033[31m%d FAILURE(S)\033[0m\n' "$total"; fi
exit "$total"
```

- [ ] **Step 3: Write a smoke test**

Create `tests/test_smoke.sh`:

```bash
assert_eq "1" "1" "harness runs"
new_sandbox
write_sample_cred "$CL_CRED" "alpha"
assert_contains "$(cat "$CL_CRED")" "MCP-KEEP-ME" "sample cred written"
cleanup_sandbox
```

- [ ] **Step 4: Run the harness**

Run: `chmod +x tests/run.sh && bash tests/run.sh`
Expected: `== test_smoke.sh ==` then `ALL TESTS PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/
git commit -m "test: plain-bash test harness + smoke test"
```

---

## Task 2: lib/core.sh — constants, cl_now_ms, cl_read_oauth

**Files:**
- Create: `lib/core.sh`
- Create: `tests/test_read_oauth.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_read_oauth.sh`:

```bash
source "$(dirname "$0")/../lib/core.sh"
new_sandbox
write_sample_cred "$CL_CRED" "alpha"

oauth="$(cl_read_oauth "$CL_CRED")"
assert_eq "acc-alpha" "$(echo "$oauth" | jq -r '.accessToken')" "reads accessToken"
assert_eq "ref-alpha" "$(echo "$oauth" | jq -r '.refreshToken')" "reads refreshToken"

now="$(cl_now_ms)"
assert_ok "[ \"$now\" -gt 1700000000000 ]"   # plausibly an epoch-ms value
cleanup_sandbox
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_read_oauth`
Expected: FAIL — `lib/core.sh` does not exist / functions undefined.

- [ ] **Step 3: Write minimal implementation**

Create `lib/core.sh`:

```bash
# Sourceable core for claude-auth-switcher. No top-level side effects beyond
# defining constants + functions. HTTP goes only through cl_http_* wrappers
# so tests can override them.

: "${CL_CRED:=$HOME/.claude/.credentials.json}"
: "${CL_PROFILES_DIR:=$HOME/.claude_auth_profiles}"
: "${CL_CLIENT_ID:=9d1c250a-e61b-44d9-88ed-5944d1962f5e}"
: "${CL_TOKEN_URL:=https://platform.claude.com/v1/oauth/token}"
: "${CL_USAGE_URL:=https://api.anthropic.com/api/oauth/usage}"
: "${CL_REFRESH_BUFFER_MS:=60000}"

cl_now_ms() { echo "$(( $(date +%s) * 1000 ))"; }

# Print the compact claudeAiOauth object from a credentials file.
cl_read_oauth() { jq -c '.claudeAiOauth' "$1"; }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_read_oauth; bash tests/run.sh >/dev/null; echo "exit=$?"`
Expected: no FAIL lines for test_read_oauth; overall exit=0.

- [ ] **Step 5: Commit**

```bash
git add lib/core.sh tests/test_read_oauth.sh
git commit -m "feat(core): constants, cl_now_ms, cl_read_oauth"
```

---

## Task 3: cl_merge_oauth — the critical preserve-mcpOAuth merge

**Files:**
- Modify: `lib/core.sh`
- Create: `tests/test_merge.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_merge.sh`:

```bash
source "$(dirname "$0")/../lib/core.sh"
new_sandbox
write_sample_cred "$CL_CRED" "alpha"

new_oauth='{"accessToken":"acc-beta","refreshToken":"ref-beta","expiresAt":123,"subscriptionType":"pro","rateLimitTier":"t","scopes":["user:inference"]}'
cl_merge_oauth "$CL_CRED" "$new_oauth"

merged="$(cat "$CL_CRED")"
assert_eq "acc-beta"   "$(echo "$merged" | jq -r '.claudeAiOauth.accessToken')" "account token replaced"
assert_eq "MCP-KEEP-ME" "$(echo "$merged" | jq -r '.mcpOAuth["plugin:supabase:supabase|abc"].accessToken')" "MCP token preserved"
assert_ok "echo \"$merged\" | jq -e . >/dev/null"   # still valid JSON
cleanup_sandbox
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_merge`
Expected: FAIL — `cl_merge_oauth: command not found`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/core.sh`:

```bash
# Replace ONLY .claudeAiOauth in the credentials file, preserving mcpOAuth and
# everything else. Writes atomically and tightens permissions.
cl_merge_oauth() { # cred_file, oauth_json
  local cred="$1" oauth="$2" tmp
  tmp="$(mktemp)"
  jq --argjson o "$oauth" '.claudeAiOauth = $o' "$cred" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$cred"
  chmod 600 "$cred" 2>/dev/null || true
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_merge; bash tests/run.sh >/dev/null; echo "exit=$?"`
Expected: no FAIL for test_merge; exit=0.

- [ ] **Step 5: Commit**

```bash
git add lib/core.sh tests/test_merge.sh
git commit -m "feat(core): cl_merge_oauth preserving mcpOAuth"
```

---

## Task 4: cl_token_expired

**Files:**
- Modify: `lib/core.sh`
- Create: `tests/test_expired.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_expired.sh`:

```bash
source "$(dirname "$0")/../lib/core.sh"
# Far-future expiry → not expired
assert_fail "cl_token_expired '{\"expiresAt\": 99999999999999}'"
# Zero expiry → expired
assert_ok   "cl_token_expired '{\"expiresAt\": 0}'"
# Missing expiresAt → treat as expired
assert_ok   "cl_token_expired '{}'"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_expired`
Expected: FAIL — `cl_token_expired: command not found`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/core.sh`:

```bash
# Return 0 (true) if the oauth's token is expired or within the refresh buffer.
cl_token_expired() { # oauth_json
  local exp; exp="$(echo "$1" | jq -r '.expiresAt // 0')"
  [ "$exp" -lt "$(( $(cl_now_ms) + CL_REFRESH_BUFFER_MS ))" ]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_expired; bash tests/run.sh >/dev/null; echo "exit=$?"`
Expected: no FAIL for test_expired; exit=0.

- [ ] **Step 5: Commit**

```bash
git add lib/core.sh tests/test_expired.sh
git commit -m "feat(core): cl_token_expired"
```

---

## Task 5: HTTP wrappers + cl_refresh

**Files:**
- Modify: `lib/core.sh`
- Create: `tests/test_refresh.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_refresh.sh`:

```bash
source "$(dirname "$0")/../lib/core.sh"

# Override the HTTP wrapper to return a canned token response.
cl_http_post_json() { echo '{"access_token":"acc-NEW","refresh_token":"ref-NEW","expires_in":3600}'; }

old_oauth='{"accessToken":"acc-OLD","refreshToken":"ref-OLD","expiresAt":0,"subscriptionType":"max"}'
new_oauth="$(cl_refresh "$old_oauth")"
assert_eq "acc-NEW" "$(echo "$new_oauth" | jq -r '.accessToken')"  "access token updated"
assert_eq "ref-NEW" "$(echo "$new_oauth" | jq -r '.refreshToken')" "refresh token rotated"
assert_eq "max"     "$(echo "$new_oauth" | jq -r '.subscriptionType')" "other fields preserved"
assert_ok "[ \"$(echo "$new_oauth" | jq -r '.expiresAt')\" -gt $(cl_now_ms) ]" "expiresAt advanced"

# If server omits a rotated refresh token, keep the old one.
cl_http_post_json() { echo '{"access_token":"acc-NEW2","expires_in":3600}'; }
n2="$(cl_refresh "$old_oauth")"
assert_eq "ref-OLD" "$(echo "$n2" | jq -r '.refreshToken')" "keeps old refresh when not rotated"

# On a failure response, cl_refresh returns non-zero.
cl_http_post_json() { echo '{"error":"invalid_grant"}'; }
assert_fail "cl_refresh '$old_oauth'"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_refresh`
Expected: FAIL — `cl_refresh: command not found`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/core.sh`:

```bash
# The ONLY two functions that touch the network. Tests redefine these.
cl_http_post_json() { # url, json_body
  curl -s "$1" -H 'Content-Type: application/json' -d "$2"
}
cl_http_get_usage() { # access_token
  curl -s "$CL_USAGE_URL" \
    -H "Authorization: Bearer $1" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "anthropic-version: 2023-06-01"
}

# Given an oauth object, refresh its tokens and echo the updated object.
# Returns non-zero if the server did not return an access_token.
cl_refresh() { # oauth_json
  local oauth="$1" rt body resp acc ref expin
  rt="$(echo "$oauth" | jq -r '.refreshToken')"
  body="$(jq -n --arg rt "$rt" --arg cid "$CL_CLIENT_ID" \
          '{grant_type:"refresh_token", refresh_token:$rt, client_id:$cid}')"
  resp="$(cl_http_post_json "$CL_TOKEN_URL" "$body")"
  acc="$(echo "$resp" | jq -r '.access_token // empty')"
  [ -n "$acc" ] || return 1
  ref="$(echo "$resp" | jq -r '.refresh_token // empty')"
  expin="$(echo "$resp" | jq -r '.expires_in // 0')"
  local new_exp=$(( $(cl_now_ms) + expin * 1000 ))
  echo "$oauth" | jq -c \
    --arg a "$acc" --arg r "${ref:-$rt}" --argjson e "$new_exp" \
    '.accessToken=$a | .refreshToken=$r | .expiresAt=$e'
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_refresh; bash tests/run.sh >/dev/null; echo "exit=$?"`
Expected: no FAIL for test_refresh; exit=0.

- [ ] **Step 5: Commit**

```bash
git add lib/core.sh tests/test_refresh.sh
git commit -m "feat(core): http wrappers + cl_refresh"
```

---

## Task 6: cl_fetch_usage + cl_format_usage

**Files:**
- Modify: `lib/core.sh`
- Create: `tests/test_usage.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_usage.sh`:

```bash
source "$(dirname "$0")/../lib/core.sh"

sample='{"five_hour":{"utilization":16,"resets_at":"2026-05-29T05:40:00+00:00"},
         "seven_day":{"utilization":3,"resets_at":"2026-06-03T18:00:00+00:00"},
         "seven_day_opus":null,
         "seven_day_sonnet":{"utilization":0,"resets_at":null}}'

out="$(cl_format_usage "$sample")"
assert_contains "$out" "16" "shows 5h utilization"
assert_contains "$out" "3"  "shows weekly utilization"
assert_contains "$out" "5"  "shows 5-hour label marker"     # the literal '5' in label/percent
# A null bucket must not appear as a row:
assert_eq "" "$(echo "$out" | grep -i opus || true)" "null bucket omitted"

# cl_fetch_usage delegates to the overridable getter:
cl_http_get_usage() { echo "$sample"; }
fetched="$(cl_fetch_usage "any-token")"
assert_eq "16" "$(echo "$fetched" | jq -r '.five_hour.utilization')" "fetch returns json"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_usage`
Expected: FAIL — `cl_format_usage: command not found`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/core.sh`:

```bash
# Fetch raw usage JSON for an access token.
cl_fetch_usage() { cl_http_get_usage "$1"; }

# Render a usage JSON object as a small human table. Skips null/absent buckets.
cl_format_usage() { # usage_json
  local usage="$1"
  _cl_usage_row() { # label, key
    local u rs
    u="$(echo "$usage" | jq -r --arg k "$2" '.[$k].utilization // empty')"
    [ -n "$u" ] || return 0
    rs="$(echo "$usage" | jq -r --arg k "$2" '.[$k].resets_at // empty')"
    if [ -n "$rs" ] && [ "$rs" != "null" ]; then
      rs="$(date -d "$rs" '+%m/%d %H:%M' 2>/dev/null || echo "$rs")"
      printf '  %-12s %5s%%   reset %s\n' "$1" "$u" "$rs"
    else
      printf '  %-12s %5s%%\n' "$1" "$u"
    fi
  }
  _cl_usage_row "5h"          five_hour
  _cl_usage_row "weekly"      seven_day
  _cl_usage_row "weekly-opus" seven_day_opus
  _cl_usage_row "weekly-sonnet" seven_day_sonnet
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_usage; bash tests/run.sh >/dev/null; echo "exit=$?"`
Expected: no FAIL for test_usage; exit=0.

- [ ] **Step 5: Commit**

```bash
git add lib/core.sh tests/test_usage.sh
git commit -m "feat(core): cl_fetch_usage + cl_format_usage"
```

---

## Task 7: cl_find_profile_by_refresh

**Files:**
- Modify: `lib/core.sh`
- Create: `tests/test_find_profile.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_find_profile.sh`:

```bash
source "$(dirname "$0")/../lib/core.sh"
new_sandbox
echo '{"refreshToken":"ref-personal"}' > "$CL_PROFILES_DIR/personal.json"
echo '{"refreshToken":"ref-company"}'  > "$CL_PROFILES_DIR/company.json"

assert_eq "personal" "$(cl_find_profile_by_refresh "$CL_PROFILES_DIR" "ref-personal")" "matches personal"
assert_eq "company"  "$(cl_find_profile_by_refresh "$CL_PROFILES_DIR" "ref-company")"  "matches company"
assert_eq ""         "$(cl_find_profile_by_refresh "$CL_PROFILES_DIR" "ref-unknown")"  "no match -> empty"
cleanup_sandbox
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_find_profile`
Expected: FAIL — `cl_find_profile_by_refresh: command not found`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/core.sh`:

```bash
# Echo the profile name whose stored refreshToken matches, or empty.
cl_find_profile_by_refresh() { # profiles_dir, refresh_token
  local dir="$1" want="$2" f name rt
  for f in "$dir"/*.json; do
    [ -e "$f" ] || continue
    case "$f" in *.usage.json) continue;; esac
    rt="$(jq -r '.refreshToken // empty' "$f" 2>/dev/null)"
    if [ "$rt" = "$want" ]; then
      name="$(basename "$f" .json)"; echo "$name"; return 0
    fi
  done
  echo ""
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_find_profile; bash tests/run.sh >/dev/null; echo "exit=$?"`
Expected: no FAIL for test_find_profile; exit=0.

- [ ] **Step 5: Commit**

```bash
git add lib/core.sh tests/test_find_profile.sh
git commit -m "feat(core): cl_find_profile_by_refresh"
```

---

## Task 8: bin/cl skeleton — dispatch, help, current

**Files:**
- Create: `bin/cl`
- Create: `tests/test_cli_basic.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_cli_basic.sh`:

```bash
CL="$(dirname "$0")/../bin/cl"
new_sandbox

assert_contains "$(bash "$CL" help)" "cl use" "help lists commands"
assert_contains "$(bash "$CL" 2>&1)" "cl use" "no-arg shows help"
# current with nothing set:
assert_contains "$(bash "$CL" current 2>&1)" "none" "current with no profile says none"
echo "personal" > "$CL_PROFILES_DIR/current"
assert_eq "personal" "$(bash "$CL" current)" "current echoes active profile"
cleanup_sandbox
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_cli_basic`
Expected: FAIL — `bin/cl` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `bin/cl`:

```bash
#!/usr/bin/env bash
set -euo pipefail
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$_here/lib/core.sh"

die() { printf 'cl: %s\n' "$*" >&2; exit 1; }

cl_usage_help() {
  cat <<'EOF'
usage:
  cl import <name>       Save current ~/.claude account as a profile
  cl use <name>          Switch active account (merges only claudeAiOauth)
  cl switch              Interactive switcher
  cl list                List profiles, active marker, usage %
  cl usage [name|--all]  Fetch live usage (default: active)
  cl current             Print active profile
  cl remove <name>       Delete a profile
  cl export <a.tgz>      Back up all profiles
  cl restore <a.tgz>     Restore profiles from archive
  cl doctor              Show paths, claude process state, profile summary
  cl help                Show this help

env: CL_PROFILES_DIR (default ~/.claude_auth_profiles), CL_CRED (default ~/.claude/.credentials.json)
EOF
}

cmd_current() {
  if [ -f "$CL_PROFILES_DIR/current" ]; then cat "$CL_PROFILES_DIR/current"; else echo "none"; fi
}

main() {
  mkdir -p "$CL_PROFILES_DIR"
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    help|-h|--help) cl_usage_help ;;
    current)        cmd_current ;;
    *)              cl_usage_help; [ "$cmd" = "help" ] || exit 0 ;;
  esac
}
main "$@"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x bin/cl; bash tests/run.sh 2>&1 | grep -A3 test_cli_basic; bash tests/run.sh >/dev/null; echo "exit=$?"`
Expected: no FAIL for test_cli_basic; exit=0.

- [ ] **Step 5: Commit**

```bash
git add bin/cl tests/test_cli_basic.sh
git commit -m "feat(cli): cl skeleton with help + current"
```

---

## Task 9: cl import

**Files:**
- Modify: `bin/cl`
- Create: `tests/test_cli_import.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_cli_import.sh`:

```bash
CL="$(dirname "$0")/../bin/cl"
new_sandbox
write_sample_cred "$CL_CRED" "alpha"

bash "$CL" import personal
assert_ok "[ -f \"$CL_PROFILES_DIR/personal.json\" ]" "profile file created"
assert_eq "acc-alpha" "$(jq -r '.accessToken' "$CL_PROFILES_DIR/personal.json")" "stores claudeAiOauth only"
assert_eq "null" "$(jq -r '.mcpOAuth // \"null\"' "$CL_PROFILES_DIR/personal.json")" "does not store mcpOAuth"
assert_eq "personal" "$(cat "$CL_PROFILES_DIR/current")" "import sets current"

# Importing with no credentials file fails clearly.
rm -f "$CL_CRED"
assert_fail "bash \"$CL\" import x"
cleanup_sandbox
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_cli_import`
Expected: FAIL — import not implemented (help printed instead of creating file).

- [ ] **Step 3: Write minimal implementation**

In `bin/cl`, add the function before `main()`:

```bash
cmd_import() { # name
  local name="${1:-}"; [ -n "$name" ] || die "usage: cl import <name>"
  [ -f "$CL_CRED" ] || die "no credentials at $CL_CRED — log in with Claude Code first"
  local oauth; oauth="$(cl_read_oauth "$CL_CRED")"
  [ "$oauth" != "null" ] || die "no claudeAiOauth block in $CL_CRED"
  umask 077
  echo "$oauth" | jq . > "$CL_PROFILES_DIR/$name.json"
  chmod 700 "$CL_PROFILES_DIR" 2>/dev/null || true
  echo "$name" > "$CL_PROFILES_DIR/current"
  echo "imported '$name'"
}
```

Add a `case` branch in `main()`:

```bash
    import)         cmd_import "$@" ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_cli_import; bash tests/run.sh >/dev/null; echo "exit=$?"`
Expected: no FAIL for test_cli_import; exit=0.

- [ ] **Step 5: Commit**

```bash
git add bin/cl tests/test_cli_import.sh
git commit -m "feat(cli): cl import"
```

---

## Task 10: cl use — lock, unsaved-current guard, refresh-on-switch

**Files:**
- Modify: `bin/cl`
- Create: `tests/test_cli_use.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_cli_use.sh`:

```bash
CL="$(dirname "$0")/../bin/cl"
new_sandbox
# Force a stub refresh so no network is hit, and a far-future expiry so it isn't called.
export CL_TOKEN_URL="stub"   # not used because tokens are fresh below

# Two saved profiles (fresh tokens -> no refresh path).
echo '{"accessToken":"acc-p","refreshToken":"ref-p","expiresAt":99999999999999}' > "$CL_PROFILES_DIR/personal.json"
echo '{"accessToken":"acc-c","refreshToken":"ref-c","expiresAt":99999999999999}' > "$CL_PROFILES_DIR/company.json"

# Live creds currently belong to 'personal' (matching refresh token), plus an MCP token.
cat > "$CL_CRED" <<JSON
{"claudeAiOauth":{"accessToken":"acc-p","refreshToken":"ref-p","expiresAt":99999999999999},
 "mcpOAuth":{"x":{"accessToken":"MCP-KEEP"}}}
JSON
echo "personal" > "$CL_PROFILES_DIR/current"

bash "$CL" use company
assert_eq "acc-c"    "$(jq -r '.claudeAiOauth.accessToken' "$CL_CRED")" "active token switched"
assert_eq "MCP-KEEP" "$(jq -r '.mcpOAuth.x.accessToken' "$CL_CRED")"    "mcp preserved on switch"
assert_eq "company"  "$(cat "$CL_PROFILES_DIR/current")" "current updated"

# Unknown profile fails.
assert_fail "bash \"$CL\" use nope"

# Guard: if live creds match no profile, plain 'use' refuses without --force.
cat > "$CL_CRED" <<JSON
{"claudeAiOauth":{"accessToken":"acc-orphan","refreshToken":"ref-orphan","expiresAt":99999999999999},"mcpOAuth":{}}
JSON
assert_fail "bash \"$CL\" use personal"
assert_ok   "bash \"$CL\" use personal --force"
cleanup_sandbox
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_cli_use`
Expected: FAIL — use not implemented.

- [ ] **Step 3: Write minimal implementation**

In `bin/cl`, add:

```bash
cl_lock()   { mkdir "$CL_PROFILES_DIR/.lock" 2>/dev/null || die "another cl operation is in progress (stale lock? rm -rf $CL_PROFILES_DIR/.lock)"; }
cl_unlock() { rmdir "$CL_PROFILES_DIR/.lock" 2>/dev/null || true; }

cmd_use() { # name [--force|-y]
  local name="" force=0 a
  for a in "$@"; do
    case "$a" in --force|-y|--yes) force=1 ;; -*) die "unknown flag $a" ;; *) name="$a" ;; esac
  done
  [ -n "$name" ] || die "usage: cl use <name> [--force]"
  local pf="$CL_PROFILES_DIR/$name.json"
  [ -f "$pf" ] || die "no such profile: $name"
  [ -f "$CL_CRED" ] || die "no credentials at $CL_CRED — log in with Claude Code first"

  # Guard: refuse to clobber an unsaved current account.
  local cur_rt owner
  cur_rt="$(cl_read_oauth "$CL_CRED" | jq -r '.refreshToken // empty')"
  owner="$(cl_find_profile_by_refresh "$CL_PROFILES_DIR" "$cur_rt")"
  if [ -z "$owner" ] && [ "$force" -ne 1 ]; then
    die "current account is not saved as a profile — 'cl import <name>' first, or pass --force to overwrite"
  fi

  cl_lock; trap cl_unlock EXIT
  local oauth; oauth="$(cat "$pf")"
  if cl_token_expired "$oauth"; then
    local refreshed
    if refreshed="$(cl_refresh "$oauth")"; then
      oauth="$refreshed"; echo "$oauth" | jq . > "$pf"
    else
      cl_unlock; trap - EXIT
      die "token refresh failed for '$name' — re-login in Claude Code on that account then 'cl import $name'"
    fi
  fi
  cl_merge_oauth "$CL_CRED" "$(echo "$oauth" | jq -c .)"
  echo "$name" > "$CL_PROFILES_DIR/current"
  cl_unlock; trap - EXIT
  echo "switched to '$name'"
}
```

Add to `main()` case:

```bash
    use)            cmd_use "$@" ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_cli_use; bash tests/run.sh >/dev/null; echo "exit=$?"`
Expected: no FAIL for test_cli_use; exit=0.

- [ ] **Step 5: Commit**

```bash
git add bin/cl tests/test_cli_use.sh
git commit -m "feat(cli): cl use with lock, unsaved guard, refresh-on-switch"
```

---

## Task 11: cl list

**Files:**
- Modify: `bin/cl`
- Create: `tests/test_cli_list.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_cli_list.sh`:

```bash
CL="$(dirname "$0")/../bin/cl"
new_sandbox
echo '{"accessToken":"a","refreshToken":"r1","expiresAt":99999999999999,"subscriptionType":"max"}' > "$CL_PROFILES_DIR/personal.json"
echo '{"accessToken":"b","refreshToken":"r2","expiresAt":99999999999999,"subscriptionType":"pro"}' > "$CL_PROFILES_DIR/company.json"
echo "personal" > "$CL_PROFILES_DIR/current"

out="$(bash "$CL" list)"
assert_contains "$out" "personal" "lists personal"
assert_contains "$out" "company"  "lists company"
assert_contains "$out" "*"        "marks the active profile with a star"
# the active line carries the marker:
assert_contains "$(echo "$out" | grep personal)" "*" "active line has marker"
cleanup_sandbox
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_cli_list`
Expected: FAIL — list not implemented.

- [ ] **Step 3: Write minimal implementation**

In `bin/cl`, add:

```bash
cmd_list() {
  local cur="" f name
  [ -f "$CL_PROFILES_DIR/current" ] && cur="$(cat "$CL_PROFILES_DIR/current")"
  local found=0
  for f in "$CL_PROFILES_DIR"/*.json; do
    [ -e "$f" ] || continue
    case "$f" in *.usage.json) continue;; esac
    found=1
    name="$(basename "$f" .json)"
    local mark="  "; [ "$name" = "$cur" ] && mark="* "
    local sub; sub="$(jq -r '.subscriptionType // "?"' "$f")"
    # show cached usage if present
    local uf="$CL_PROFILES_DIR/$name.usage.json" extra=""
    if [ -f "$uf" ]; then
      extra="$(jq -r '"5h=" + ((.five_hour.utilization|tostring)//"?") + "% wk=" + ((.seven_day.utilization|tostring)//"?") + "%"' "$uf" 2>/dev/null || true)"
    fi
    printf '%s%-16s %-6s %s\n' "$mark" "$name" "$sub" "$extra"
  done
  [ "$found" -eq 1 ] || echo "no profiles — 'cl import <name>' to add one"
}
```

Add to `main()` case:

```bash
    list)           cmd_list ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_cli_list; bash tests/run.sh >/dev/null; echo "exit=$?"`
Expected: no FAIL for test_cli_list; exit=0.

- [ ] **Step 5: Commit**

```bash
git add bin/cl tests/test_cli_list.sh
git commit -m "feat(cli): cl list with active marker + cached usage"
```

---

## Task 12: cl usage

**Files:**
- Modify: `bin/cl`
- Create: `tests/test_cli_usage.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_cli_usage.sh`:

```bash
# Use a fake bin/cl that sources a stubbed core so no network happens.
CL="$(dirname "$0")/../bin/cl"
new_sandbox
echo '{"accessToken":"a","refreshToken":"r1","expiresAt":99999999999999}' > "$CL_PROFILES_DIR/personal.json"
echo "personal" > "$CL_PROFILES_DIR/current"

# Inject a fake usage getter via env-pointed override file that bin/cl sources if set.
cat > "$CL_SANDBOX/override.sh" <<'OV'
cl_http_get_usage() { echo '{"five_hour":{"utilization":42,"resets_at":null},"seven_day":{"utilization":7,"resets_at":null}}'; }
OV
export CL_OVERRIDE="$CL_SANDBOX/override.sh"

out="$(bash "$CL" usage)"
assert_contains "$out" "42" "usage shows 5h percent"
assert_contains "$out" "7"  "usage shows weekly percent"
assert_ok "[ -f \"$CL_PROFILES_DIR/personal.usage.json\" ]" "usage cached to disk"
cleanup_sandbox
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_cli_usage`
Expected: FAIL — usage not implemented / CL_OVERRIDE not honored.

- [ ] **Step 3: Write minimal implementation**

In `bin/cl`, immediately after `source "$_here/lib/core.sh"`, add an optional override hook (for tests):

```bash
[ -n "${CL_OVERRIDE:-}" ] && [ -f "$CL_OVERRIDE" ] && source "$CL_OVERRIDE"
```

Then add the command:

```bash
_cl_usage_one() { # name
  local name="$1" pf="$CL_PROFILES_DIR/$name.json"
  [ -f "$pf" ] || { echo "  ($name: no such profile)"; return 0; }
  local oauth acc
  oauth="$(cat "$pf")"
  if cl_token_expired "$oauth"; then
    local r; if r="$(cl_refresh "$oauth")"; then oauth="$r"; echo "$oauth" | jq . > "$pf"; fi
  fi
  acc="$(echo "$oauth" | jq -r '.accessToken')"
  local usage; usage="$(cl_fetch_usage "$acc")"
  if echo "$usage" | jq -e '.five_hour' >/dev/null 2>&1; then
    echo "$usage" | jq . > "$CL_PROFILES_DIR/$name.usage.json"
    echo "$name:"
    cl_format_usage "$usage"
  else
    echo "$name: usage query failed: $usage"
  fi
}

cmd_usage() { # [name|--all]
  local arg="${1:-}"
  if [ "$arg" = "--all" ]; then
    local f name
    for f in "$CL_PROFILES_DIR"/*.json; do
      [ -e "$f" ] || continue; case "$f" in *.usage.json) continue;; esac
      _cl_usage_one "$(basename "$f" .json)"
    done
  elif [ -n "$arg" ]; then
    _cl_usage_one "$arg"
  else
    local cur; cur="$(cmd_current)"; [ "$cur" = "none" ] && die "no active profile"
    _cl_usage_one "$cur"
  fi
}
```

Add to `main()` case:

```bash
    usage)          cmd_usage "$@" ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_cli_usage; bash tests/run.sh >/dev/null; echo "exit=$?"`
Expected: no FAIL for test_cli_usage; exit=0.

- [ ] **Step 5: Commit**

```bash
git add bin/cl tests/test_cli_usage.sh
git commit -m "feat(cli): cl usage (live fetch + cache)"
```

---

## Task 13: cl remove + cl switch

**Files:**
- Modify: `bin/cl`
- Create: `tests/test_cli_remove.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_cli_remove.sh`:

```bash
CL="$(dirname "$0")/../bin/cl"
new_sandbox
echo '{"refreshToken":"r1"}' > "$CL_PROFILES_DIR/personal.json"
echo '{"five_hour":{"utilization":1}}' > "$CL_PROFILES_DIR/personal.usage.json"

bash "$CL" remove personal
assert_fail "[ -f \"$CL_PROFILES_DIR/personal.json\" ]" "profile removed"
assert_fail "[ -f \"$CL_PROFILES_DIR/personal.usage.json\" ]" "usage cache removed too"
assert_fail "bash \"$CL\" remove ghost"   # removing nonexistent fails
cleanup_sandbox
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_cli_remove`
Expected: FAIL — remove not implemented.

- [ ] **Step 3: Write minimal implementation**

In `bin/cl`, add:

```bash
cmd_remove() { # name
  local name="${1:-}"; [ -n "$name" ] || die "usage: cl remove <name>"
  local pf="$CL_PROFILES_DIR/$name.json"
  [ -f "$pf" ] || die "no such profile: $name"
  rm -f "$pf" "$CL_PROFILES_DIR/$name.usage.json"
  [ "$(cmd_current)" = "$name" ] && rm -f "$CL_PROFILES_DIR/current"
  echo "removed '$name'"
}

cl_claude_running() { pgrep -x claude >/dev/null 2>&1 || pgrep -f '/claude(\s|$)' >/dev/null 2>&1; }

cmd_switch() { # interactive
  local names=() f
  for f in "$CL_PROFILES_DIR"/*.json; do
    [ -e "$f" ] || continue; case "$f" in *.usage.json) continue;; esac
    names+=("$(basename "$f" .json)")
  done
  [ "${#names[@]}" -gt 0 ] || die "no profiles — 'cl import <name>' first"
  if cl_claude_running; then echo "warning: a claude process is running; switching changes its token on next API call." >&2; fi
  echo "select a profile:"
  local i=1 n
  for n in "${names[@]}"; do printf '  %d) %s\n' "$i" "$n"; i=$((i+1)); done
  printf 'choice: '; local sel; read -r sel
  [ "$sel" -ge 1 ] 2>/dev/null && [ "$sel" -le "${#names[@]}" ] || die "invalid choice"
  cmd_use "${names[$((sel-1))]}"
}
```

Add to `main()` case:

```bash
    remove|rm)      cmd_remove "$@" ;;
    switch)         cmd_switch ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_cli_remove; bash tests/run.sh >/dev/null; echo "exit=$?"`
Expected: no FAIL for test_cli_remove; exit=0.

- [ ] **Step 5: Commit**

```bash
git add bin/cl tests/test_cli_remove.sh
git commit -m "feat(cli): cl remove + interactive switch"
```

---

## Task 14: cl export + cl restore

**Files:**
- Modify: `bin/cl`
- Create: `tests/test_cli_export.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_cli_export.sh`:

```bash
CL="$(dirname "$0")/../bin/cl"
new_sandbox
echo '{"refreshToken":"r1"}' > "$CL_PROFILES_DIR/personal.json"
echo '{"refreshToken":"r2"}' > "$CL_PROFILES_DIR/company.json"
arc="$CL_SANDBOX/backup.tgz"

bash "$CL" export "$arc"
assert_ok "[ -s \"$arc\" ]" "archive created"

rm -f "$CL_PROFILES_DIR/personal.json" "$CL_PROFILES_DIR/company.json"
bash "$CL" restore "$arc"
assert_ok "[ -f \"$CL_PROFILES_DIR/personal.json\" ]" "personal restored"
assert_eq "r2" "$(jq -r .refreshToken "$CL_PROFILES_DIR/company.json")" "company restored intact"
cleanup_sandbox
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_cli_export`
Expected: FAIL — export/restore not implemented.

- [ ] **Step 3: Write minimal implementation**

In `bin/cl`, add:

```bash
cmd_export() { # archive.tgz
  local arc="${1:-}"; [ -n "$arc" ] || die "usage: cl export <archive.tgz>"
  ( cd "$CL_PROFILES_DIR" && tar czf "$arc" --exclude='.lock' . )
  echo "exported profiles to $arc"
}
cmd_restore() { # archive.tgz
  local arc="${1:-}"; [ -n "$arc" ] || die "usage: cl restore <archive.tgz>"
  [ -f "$arc" ] || die "no such archive: $arc"
  mkdir -p "$CL_PROFILES_DIR"; chmod 700 "$CL_PROFILES_DIR" 2>/dev/null || true
  tar xzf "$arc" -C "$CL_PROFILES_DIR"
  echo "restored profiles from $arc"
}
```

Add to `main()` case:

```bash
    export)         cmd_export "$@" ;;
    restore)        cmd_restore "$@" ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_cli_export; bash tests/run.sh >/dev/null; echo "exit=$?"`
Expected: no FAIL for test_cli_export; exit=0.

- [ ] **Step 5: Commit**

```bash
git add bin/cl tests/test_cli_export.sh
git commit -m "feat(cli): cl export + restore"
```

---

## Task 15: cl doctor

**Files:**
- Modify: `bin/cl`
- Create: `tests/test_cli_doctor.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_cli_doctor.sh`:

```bash
CL="$(dirname "$0")/../bin/cl"
new_sandbox
write_sample_cred "$CL_CRED" "alpha"
echo '{"refreshToken":"r1"}' > "$CL_PROFILES_DIR/personal.json"

out="$(bash "$CL" doctor)"
assert_contains "$out" "$CL_PROFILES_DIR" "doctor prints profiles dir"
assert_contains "$out" "$CL_CRED"         "doctor prints cred path"
assert_contains "$out" "personal"         "doctor lists a profile"
assert_contains "$out" "jq"               "doctor reports jq presence"
cleanup_sandbox
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_cli_doctor`
Expected: FAIL — doctor not implemented.

- [ ] **Step 3: Write minimal implementation**

In `bin/cl`, add:

```bash
cmd_doctor() {
  echo "claude-auth-switcher doctor"
  echo "  profiles dir : $CL_PROFILES_DIR"
  echo "  credentials  : $CL_CRED $( [ -f "$CL_CRED" ] && echo '(present)' || echo '(MISSING)')"
  echo "  jq           : $(command -v jq || echo 'MISSING')"
  echo "  curl         : $(command -v curl || echo 'MISSING')"
  echo "  claude proc  : $(cl_claude_running && echo running || echo 'not running')"
  echo "  active       : $(cmd_current)"
  echo "  profiles     :"
  cmd_list | sed 's/^/    /'
}
```

Add to `main()` case:

```bash
    doctor)         cmd_doctor ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_cli_doctor; bash tests/run.sh >/dev/null; echo "exit=$?"`
Expected: no FAIL for test_cli_doctor; exit=0.

- [ ] **Step 5: Commit**

```bash
git add bin/cl tests/test_cli_doctor.sh
git commit -m "feat(cli): cl doctor"
```

---

## Task 16: shell wrapper + installers (bash)

**Files:**
- Create: `shell/bash.sh`
- Create: `install.sh`
- Create: `install-oneliner.sh`

- [ ] **Step 1: Write the shell wrapper**

Create `shell/bash.sh` (mirrors codex-auth-switcher's symlink-resolving pattern):

```bash
# Source from ~/.bashrc:  source "$HOME/claude-auth-switcher/shell/bash.sh"
_cl_file="${BASH_SOURCE[0]}"
while [ -L "$_cl_file" ]; do
  _cl_dir="$(cd -P "$(dirname "$_cl_file")" && pwd)"
  _cl_file="$(readlink "$_cl_file")"
  case "$_cl_file" in /*) ;; *) _cl_file="$_cl_dir/$_cl_file" ;; esac
done
_cl_root="$(cd -P "$(dirname "$_cl_file")/.." && pwd)"
cl() { "$_cl_root/bin/cl" "$@"; }
```

- [ ] **Step 2: Write install.sh**

Create `install.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
line="source \"$root/shell/bash.sh\""
rc="$HOME/.bashrc"
chmod +x "$root/bin/cl"
if grep -Fq "$line" "$rc" 2>/dev/null; then
  echo "already wired into $rc"
else
  printf '\n# claude-auth-switcher\n%s\n' "$line" >> "$rc"
  echo "added to $rc"
fi
command -v jq  >/dev/null || echo "WARNING: jq not found — install it (e.g. apt install jq)"
command -v curl >/dev/null || echo "WARNING: curl not found"
echo "done. Open a new shell, then: cl import <name>"
```

- [ ] **Step 3: Write install-oneliner.sh**

Create `install-oneliner.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
repo="${CL_REPO:-https://github.com/yazelin/claude-auth-switcher.git}"
dest="${CL_DEST:-$HOME/claude-auth-switcher}"
if [ -d "$dest/.git" ]; then git -C "$dest" pull --ff-only; else git clone "$repo" "$dest"; fi
bash "$dest/install.sh"
```

- [ ] **Step 4: Verify the wrapper sources cleanly**

Run:
```bash
chmod +x install.sh install-oneliner.sh
bash -c 'source shell/bash.sh && type cl && cl help | head -1'
```
Expected: `cl is a function` and the help's first line.

- [ ] **Step 5: Commit**

```bash
git add shell/bash.sh install.sh install-oneliner.sh
git commit -m "feat(install): bash shell wrapper + installers"
```

---

## Task 17: README + LICENSE + GitHub Pages docs

**Files:**
- Create: `README.md`
- Create: `LICENSE`
- Create: `docs/_config.yml`, `docs/index.md`, `docs/.nojekyll`

- [ ] **Step 1: Write README.md**

Cover: what it is, the personal/company use case, install one-liner, command table (copied from `cl help`), the "switching changes the active token in place; one account at a time" model, and the security note about refresh tokens in `~/.claude_auth_profiles`. Mirror tone/sections of `/home/ct/codex-auth-switcher/README.md`.

- [ ] **Step 2: Write LICENSE**

Copy the license type used by codex-auth-switcher:
```bash
cp /home/ct/codex-auth-switcher/LICENSE ./LICENSE
```
Update the year/holder line if needed.

- [ ] **Step 3: Write docs/ for GitHub Pages**

Mirror `/home/ct/codex-auth-switcher/docs/` structure: `.nojekyll`, `_config.yml`, `index.md` (landing page pointing at install one-liner + command reference).

- [ ] **Step 4: Sanity check**

Run: `ls README.md LICENSE docs/index.md docs/_config.yml docs/.nojekyll && bash tests/run.sh >/dev/null && echo OK`
Expected: all files listed, tests still pass, `OK`.

- [ ] **Step 5: Commit**

```bash
git add README.md LICENSE docs/
git commit -m "docs: README, LICENSE, GitHub Pages landing"
```

---

# Phase 2 — Windows (PowerShell) — GATED

> Do not start Phase 2 until Task 18 confirms how Claude Code stores credentials on Windows. The implementation in Task 19 assumes a plaintext JSON file; if Task 18 finds DPAPI/encrypted storage, revise Task 19's read/write before implementing.

## Task 18: Windows credential-storage verification spike

**Files:** none (investigation; record findings in `docs/superpowers/specs/2026-05-29-claude-auth-switcher-design.md` section 4)

- [ ] **Step 1: On a Windows machine with Claude Code logged in, locate the credentials**

Run in PowerShell:
```powershell
Get-ChildItem "$env:USERPROFILE\.claude" -Force | Select-Object Name,Length
Test-Path "$env:USERPROFILE\.claude\.credentials.json"
```

- [ ] **Step 2: Check whether it is plaintext JSON**

```powershell
Get-Content "$env:USERPROFILE\.claude\.credentials.json" -Raw | ConvertFrom-Json | Select-Object -ExpandProperty claudeAiOauth
```
Expected if plaintext: an object with `accessToken`/`refreshToken`/`expiresAt`.
If this errors or shows binary/encrypted content, the store is NOT plaintext — record that.

- [ ] **Step 3: Record the finding**

Edit the spec's section 4 with: exact path, plaintext vs encrypted, and (if encrypted) the mechanism (likely Windows Credential Manager / DPAPI). Commit:
```bash
git commit -am "docs: record Windows credential storage finding"
```

- [ ] **Step 4: Decide**

- Plaintext JSON file → proceed to Task 19 as written.
- Credential Manager / DPAPI → before Task 19, design the PowerShell read/write against that API (e.g. `cmdkey` / `CredRead` / `Unprotect-CmdletBinding`), then adjust Task 19.

## Task 19: bin/cl.ps1 + PowerShell wrapper + installers

**Files:**
- Create: `bin/cl.ps1`, `shell/powershell.ps1`, `install.ps1`, `install-oneliner.ps1`

> Mirror the bash command set (import/use/switch/list/usage/current/remove/export/restore/doctor) using PowerShell's built-in `ConvertFrom-Json`/`ConvertTo-Json` (no jq). Reuse the same `~\.claude_auth_profiles` layout and `current` file so profiles are cross-tool compatible. Implement the same critical merge: read credentials JSON, replace only `.claudeAiOauth`, keep `.mcpOAuth`, write back. Mirror `cl_refresh` against `CL_TOKEN_URL` with `Invoke-RestMethod`. Because there is no bats-equivalent harness here, add a `tests/Test-Core.ps1` Pester-or-plain script asserting the merge preserves `mcpOAuth`. Detailed step-by-step code to be written at execution time once Task 18's finding fixes the read/write primitives.

- [ ] **Step 1:** After Task 18, expand this task into bite-sized steps mirroring Tasks 3/5/9/10 in PowerShell, then implement.

---

## Self-Review notes

- **Spec coverage:** §2 scope (one-at-a-time, Linux+Windows, core+value) → Phase 1 + Phase 2; §3 endpoints → Tasks 5/6; §5 merge preserving mcpOAuth → Task 3 + Task 10; §5 lock → Task 10; §6 every command → Tasks 8–15; §7 file layout → Tasks 16–17; §8 error handling → die() paths in Tasks 9/10/12; §9 security (perms, gitignore, no token echo) → Task 9 umask/chmod, existing .gitignore; §10 testing → harness Task 1 + per-feature tests; §4 Windows unknown → Task 18 gate.
- **Type/name consistency:** function names (`cl_read_oauth`, `cl_merge_oauth`, `cl_token_expired`, `cl_refresh`, `cl_fetch_usage`, `cl_format_usage`, `cl_find_profile_by_refresh`, `cl_http_post_json`, `cl_http_get_usage`) used identically across lib + CLI + tests.
- **No placeholders** in Phase 1. Phase 2 Task 19 is intentionally deferred behind the Task 18 verification gate (cannot write correct Windows read/write code without it) and says so explicitly.
```

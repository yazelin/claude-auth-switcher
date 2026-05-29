# Sourceable core for claude-auth-switcher. No top-level side effects beyond
# defining constants + functions. All network access goes through the two
# cl_http_* wrappers so tests can override them.

: "${CL_CRED:=$HOME/.claude/.credentials.json}"
: "${CL_ACCOUNT:=$HOME/.claude.json}"
: "${CL_PROFILES_DIR:=$HOME/.claude_auth_profiles}"
: "${CL_CLIENT_ID:=9d1c250a-e61b-44d9-88ed-5944d1962f5e}"
: "${CL_TOKEN_URL:=https://platform.claude.com/v1/oauth/token}"
: "${CL_USAGE_URL:=https://api.anthropic.com/api/oauth/usage}"
: "${CL_REFRESH_BUFFER_MS:=60000}"

cl_now_ms() { echo "$(( $(date +%s) * 1000 ))"; }

# Print the compact claudeAiOauth object from a credentials file.
cl_read_oauth() { jq -c '.claudeAiOauth' "$1"; }

# Replace ONLY .claudeAiOauth in the credentials file, preserving mcpOAuth and
# everything else. Writes atomically and tightens permissions.
cl_merge_oauth() { # cred_file, oauth_json
  local cred="$1" oauth="$2" tmp
  tmp="$(mktemp)"
  jq --argjson o "$oauth" '.claudeAiOauth = $o' "$cred" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$cred"
  chmod 600 "$cred" 2>/dev/null || true
}

# --- Account identity (~/.claude.json -> .oauthAccount) -------------------------------
# Claude Code splits a logged-in account across TWO files: the token lives in
# .credentials.json (.claudeAiOauth) while the subscription identity (account
# UUID, org, billing tier) lives in ~/.claude.json (.oauthAccount). Switching
# only the token leaves a mismatch that drops Claude Code to API billing, so we
# must move .oauthAccount too.

# Print the compact .oauthAccount object, or empty if absent.
cl_read_account() { # account_file
  [ -f "$1" ] || return 0
  jq -c '.oauthAccount // empty' "$1" 2>/dev/null || true
}

# Replace ONLY .oauthAccount in ~/.claude.json, preserving every other key
# (projects, history, ...). Writes atomically.
cl_write_account() { # account_file, oauth_account_json
  local file="$1" acct="$2" tmp
  [ -n "$acct" ] && [ "$acct" != "null" ] || return 0
  [ -f "$file" ] || { echo "cl: no $file to update; run Claude Code once first" >&2; return 0; }
  tmp="$(mktemp)"
  jq --argjson a "$acct" '.oauthAccount = $a' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$file"
}
# -------------------------------------------------------------------------------------

# Return 0 (true) if the oauth's token is expired or within the refresh buffer.
cl_token_expired() { # oauth_json
  local exp; exp="$(echo "$1" | jq -r '.expiresAt // 0')"
  [ "$exp" -lt "$(( $(cl_now_ms) + CL_REFRESH_BUFFER_MS ))" ]
}

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
  local oauth="$1" rt body resp acc ref expin new_exp
  rt="$(echo "$oauth" | jq -r '.refreshToken')"
  body="$(jq -n --arg rt "$rt" --arg cid "$CL_CLIENT_ID" \
          '{grant_type:"refresh_token", refresh_token:$rt, client_id:$cid}')"
  resp="$(cl_http_post_json "$CL_TOKEN_URL" "$body")"
  acc="$(echo "$resp" | jq -r '.access_token // empty')"
  [ -n "$acc" ] || return 1
  ref="$(echo "$resp" | jq -r '.refresh_token // empty')"
  expin="$(echo "$resp" | jq -r '.expires_in // 0')"
  new_exp=$(( $(cl_now_ms) + expin * 1000 ))
  echo "$oauth" | jq -c \
    --arg a "$acc" --arg r "${ref:-$rt}" --argjson e "$new_exp" \
    '.accessToken=$a | .refreshToken=$r | .expiresAt=$e'
}

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
      printf '  %-14s %5s%% used   reset %s\n' "$1" "$u" "$rs"
    else
      printf '  %-14s %5s%% used\n' "$1" "$u"
    fi
  }
  _cl_usage_row "5h"            five_hour
  _cl_usage_row "weekly"        seven_day
  _cl_usage_row "weekly-opus"   seven_day_opus
  _cl_usage_row "weekly-sonnet" seven_day_sonnet
}

# Echo the profile name whose stored refreshToken matches, or empty.
cl_find_profile_by_refresh() { # profiles_dir, refresh_token
  local dir="$1" want="$2" f name rt
  for f in "$dir"/*.json; do
    [ -e "$f" ] || continue
    case "$f" in *.usage.json|*.account.json) continue;; esac
    rt="$(jq -r '.refreshToken // empty' "$f" 2>/dev/null)"
    if [ "$rt" = "$want" ]; then
      name="$(basename "$f" .json)"; echo "$name"; return 0
    fi
  done
  echo ""
}

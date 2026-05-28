# Sourced by every test file (via run.sh). Provides assertions + a temp fixture.
set -u

# Repo root, resolved from this file's location (robust regardless of $0).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CL_TEST_FAILS=${CL_TEST_FAILS:-0}

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
assert_ok()   { if ! eval "$1"; then _red "  FAIL: expected success: ${2:-$1}"; CL_TEST_FAILS=$((CL_TEST_FAILS+1)); fi; }
assert_fail() { if eval "$1" 2>/dev/null; then _red "  FAIL: expected failure: ${2:-$1}"; CL_TEST_FAILS=$((CL_TEST_FAILS+1)); fi; }

# A throwaway sandbox; points CL_CRED + CL_PROFILES_DIR into it.
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

source "$ROOT/lib/core.sh"
new_sandbox
write_sample_cred "$CL_CRED" "alpha"

new_oauth='{"accessToken":"acc-beta","refreshToken":"ref-beta","expiresAt":123,"subscriptionType":"pro","rateLimitTier":"t","scopes":["user:inference"]}'
cl_merge_oauth "$CL_CRED" "$new_oauth"

merged="$(cat "$CL_CRED")"
assert_eq "acc-beta"    "$(echo "$merged" | jq -r '.claudeAiOauth.accessToken')" "account token replaced"
assert_eq "MCP-KEEP-ME" "$(echo "$merged" | jq -r '.mcpOAuth["plugin:supabase:supabase|abc"].accessToken')" "MCP token preserved"
assert_ok "echo '$merged' | jq -e . >/dev/null" "still valid JSON"
cleanup_sandbox

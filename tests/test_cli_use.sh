CL="$ROOT/bin/cl"
new_sandbox

# Two saved profiles with fresh tokens (far-future expiry -> no refresh path).
echo '{"accessToken":"acc-p","refreshToken":"ref-p","expiresAt":99999999999999}' > "$CL_PROFILES_DIR/personal.json"
echo '{"accessToken":"acc-c","refreshToken":"ref-c","expiresAt":99999999999999}' > "$CL_PROFILES_DIR/company.json"

# Live creds currently belong to 'personal', plus an MCP token.
cat > "$CL_CRED" <<JSON
{"claudeAiOauth":{"accessToken":"acc-p","refreshToken":"ref-p","expiresAt":99999999999999},
 "mcpOAuth":{"x":{"accessToken":"MCP-KEEP"}}}
JSON
echo "personal" > "$CL_PROFILES_DIR/current"

bash "$CL" use company
assert_eq "acc-c"    "$(jq -r '.claudeAiOauth.accessToken' "$CL_CRED")" "active token switched"
assert_eq "MCP-KEEP" "$(jq -r '.mcpOAuth.x.accessToken' "$CL_CRED")"    "mcp preserved on switch"
assert_eq "company"  "$(cat "$CL_PROFILES_DIR/current")" "current updated"

assert_fail "bash \"$CL\" use nope" "unknown profile fails"

# Guard: live creds match no profile -> plain use refuses, --force overrides.
cat > "$CL_CRED" <<JSON
{"claudeAiOauth":{"accessToken":"acc-orphan","refreshToken":"ref-orphan","expiresAt":99999999999999},"mcpOAuth":{}}
JSON
assert_fail "bash \"$CL\" use personal" "unsaved current blocks switch"
assert_ok   "bash \"$CL\" use personal --force" "force overrides guard"
cleanup_sandbox

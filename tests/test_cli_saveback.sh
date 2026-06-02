CL="$ROOT/bin/cl"

# --- save-back captures a token a live session rotated, into the current profile ---
new_sandbox
export CL_ACCOUNT="$CL_SANDBOX/.claude.json"

echo '{"accessToken":"acc-p1","refreshToken":"ref-p1","expiresAt":99999999999999}' > "$CL_PROFILES_DIR/personal.json"
echo '{"accountUuid":"AAA","organizationUuid":"ORG1","emailAddress":"p@x.com"}'    > "$CL_PROFILES_DIR/personal.account.json"
echo '{"accessToken":"acc-c","refreshToken":"ref-c","expiresAt":99999999999999}'   > "$CL_PROFILES_DIR/company.json"
echo '{"accountUuid":"CCC","organizationUuid":"ORG2"}'                              > "$CL_PROFILES_DIR/company.account.json"
echo "personal" > "$CL_PROFILES_DIR/current"

# Live creds belong to the SAME account AAA as 'personal', but the token was
# rotated (ref-p2) by a live session — the profile still holds the old ref-p1.
cat > "$CL_CRED" <<JSON
{"claudeAiOauth":{"accessToken":"acc-p2","refreshToken":"ref-p2","expiresAt":99999999999999},"mcpOAuth":{"x":{"accessToken":"MCP-KEEP"}}}
JSON
echo '{"oauthAccount":{"accountUuid":"AAA","organizationUuid":"ORG1","emailAddress":"p@x.com"}}' > "$CL_ACCOUNT"

bash "$CL" use company >/dev/null
assert_eq "ref-p2"   "$(jq -r '.refreshToken' "$CL_PROFILES_DIR/personal.json")" "save-back: rotated current token folded into its profile"
assert_eq "acc-c"    "$(jq -r '.claudeAiOauth.accessToken' "$CL_CRED")"           "switched to company"
assert_eq "MCP-KEEP" "$(jq -r '.mcpOAuth.x.accessToken' "$CL_CRED")"              "mcp preserved"
cleanup_sandbox

# --- no-clobber: when the live account differs from the current profile's saved
#     account, save-back must NOT overwrite the profile (avoids data loss) ---
new_sandbox
export CL_ACCOUNT="$CL_SANDBOX/.claude.json"

echo '{"accessToken":"acc-p1","refreshToken":"ref-p1","expiresAt":99999999999999}' > "$CL_PROFILES_DIR/personal.json"
echo '{"accountUuid":"AAA","organizationUuid":"ORG1"}'                              > "$CL_PROFILES_DIR/personal.account.json"
echo '{"accessToken":"acc-c","refreshToken":"ref-c","expiresAt":99999999999999}'   > "$CL_PROFILES_DIR/company.json"
echo '{"accountUuid":"CCC","organizationUuid":"ORG2"}'                              > "$CL_PROFILES_DIR/company.account.json"
echo "personal" > "$CL_PROFILES_DIR/current"

# Live creds are a DIFFERENT account ZZZ (e.g. user ran `claude auth login` directly).
cat > "$CL_CRED" <<JSON
{"claudeAiOauth":{"accessToken":"acc-z","refreshToken":"ref-z","expiresAt":99999999999999},"mcpOAuth":{}}
JSON
echo '{"oauthAccount":{"accountUuid":"ZZZ","organizationUuid":"ORGX"}}' > "$CL_ACCOUNT"

bash "$CL" use company --force >/dev/null
assert_eq "ref-p1" "$(jq -r '.refreshToken' "$CL_PROFILES_DIR/personal.json")" "save-back: does NOT clobber profile when live account differs"
cleanup_sandbox

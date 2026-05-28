CL="$ROOT/bin/cl"
new_sandbox
write_sample_cred "$CL_CRED" "alpha"

bash "$CL" import personal
assert_ok "[ -f \"$CL_PROFILES_DIR/personal.json\" ]" "profile file created"
assert_eq "acc-alpha" "$(jq -r '.accessToken' "$CL_PROFILES_DIR/personal.json")" "stores claudeAiOauth only"
assert_eq "null" "$(jq -r '.mcpOAuth' "$CL_PROFILES_DIR/personal.json")" "does not store mcpOAuth"
assert_eq "personal" "$(cat "$CL_PROFILES_DIR/current")" "import sets current"

rm -f "$CL_CRED"
assert_fail "bash \"$CL\" import x" "import without creds fails"
cleanup_sandbox

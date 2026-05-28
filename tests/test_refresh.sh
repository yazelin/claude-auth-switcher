source "$ROOT/lib/core.sh"

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
assert_fail "cl_refresh '$old_oauth'" "fails on error response"

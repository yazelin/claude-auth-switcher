CL="$ROOT/bin/cl"
new_sandbox
echo '{"accessToken":"a","refreshToken":"r1","expiresAt":99999999999999,"subscriptionType":"max"}' > "$CL_PROFILES_DIR/personal.json"
echo '{"accessToken":"b","refreshToken":"r2","expiresAt":99999999999999,"subscriptionType":"pro"}' > "$CL_PROFILES_DIR/company.json"
echo '{"emailAddress":"alice@example.com"}' > "$CL_PROFILES_DIR/personal.account.json"
echo '{"five_hour":{"utilization":42,"resets_at":null},"seven_day":{"utilization":18,"resets_at":null}}' > "$CL_PROFILES_DIR/personal.usage.json"
echo "personal" > "$CL_PROFILES_DIR/current"

out="$(bash "$CL" list)"
assert_contains "$out" "CURRENT"            "prints table header"
assert_contains "$out" "personal"           "lists personal"
assert_contains "$out" "company"            "lists company"
assert_contains "$out" "max"                "shows plan"
assert_contains "$out" "al***@example.com"  "masks email"
assert_contains "$out" "5h 42% used"        "shows cached usage from disk"
assert_contains "$(echo "$out" | grep personal)" "*" "active line has marker"
cleanup_sandbox

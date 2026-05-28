CL="$ROOT/bin/cl"
new_sandbox
echo '{"accessToken":"a","refreshToken":"r1","expiresAt":99999999999999,"subscriptionType":"max"}' > "$CL_PROFILES_DIR/personal.json"
echo '{"accessToken":"b","refreshToken":"r2","expiresAt":99999999999999,"subscriptionType":"pro"}' > "$CL_PROFILES_DIR/company.json"
echo "personal" > "$CL_PROFILES_DIR/current"

out="$(bash "$CL" list)"
assert_contains "$out" "personal" "lists personal"
assert_contains "$out" "company"  "lists company"
assert_contains "$out" "*"        "marks active with star"
assert_contains "$(echo "$out" | grep personal)" "*" "active line has marker"
cleanup_sandbox

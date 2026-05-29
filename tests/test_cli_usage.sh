CL="$ROOT/bin/cl"
new_sandbox
echo '{"accessToken":"a","refreshToken":"r1","expiresAt":99999999999999}' > "$CL_PROFILES_DIR/personal.json"
echo "personal" > "$CL_PROFILES_DIR/current"

# Inject a fake usage getter that bin/cl sources via CL_OVERRIDE (no network).
cat > "$CL_SANDBOX/override.sh" <<'OV'
cl_http_get_usage() { echo '{"five_hour":{"utilization":42,"resets_at":null},"seven_day":{"utilization":7,"resets_at":null}}'; }
OV
export CL_OVERRIDE="$CL_SANDBOX/override.sh"

out="$(bash "$CL" usage)"
assert_contains "$out" "42" "usage shows 5h percent"
assert_contains "$out" "7"  "usage shows weekly percent"
assert_ok "[ -f \"$CL_PROFILES_DIR/personal.usage.json\" ]" "usage cached to disk"

# --all refreshes every profile then prints the side-by-side table, not stacked blocks.
out_all="$(bash "$CL" usage --all)"
assert_contains "$out_all" "CURRENT"  "usage --all prints the comparison table header"
assert_contains "$out_all" "personal" "usage --all lists the profile in the table"
assert_contains "$out_all" "5h 42% used" "usage --all table shows refreshed usage"
cleanup_sandbox

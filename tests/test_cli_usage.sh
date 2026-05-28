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
cleanup_sandbox

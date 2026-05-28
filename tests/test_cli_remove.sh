CL="$ROOT/bin/cl"
new_sandbox
echo '{"refreshToken":"r1"}' > "$CL_PROFILES_DIR/personal.json"
echo '{"five_hour":{"utilization":1}}' > "$CL_PROFILES_DIR/personal.usage.json"

bash "$CL" remove personal
assert_fail "[ -f \"$CL_PROFILES_DIR/personal.json\" ]" "profile removed"
assert_fail "[ -f \"$CL_PROFILES_DIR/personal.usage.json\" ]" "usage cache removed too"
assert_fail "bash \"$CL\" remove ghost" "removing nonexistent fails"
cleanup_sandbox

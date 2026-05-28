CL="$ROOT/bin/cl"
new_sandbox

assert_contains "$(bash "$CL" help)" "cl use" "help lists commands"
assert_contains "$(bash "$CL" 2>&1)" "cl use" "no-arg shows help"
assert_contains "$(bash "$CL" current 2>&1)" "none" "current with no profile says none"
echo "personal" > "$CL_PROFILES_DIR/current"
assert_eq "personal" "$(bash "$CL" current)" "current echoes active profile"
cleanup_sandbox

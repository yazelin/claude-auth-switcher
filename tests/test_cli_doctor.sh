CL="$ROOT/bin/cl"
new_sandbox
write_sample_cred "$CL_CRED" "alpha"
echo '{"refreshToken":"r1"}' > "$CL_PROFILES_DIR/personal.json"

out="$(bash "$CL" doctor)"
assert_contains "$out" "$CL_PROFILES_DIR" "doctor prints profiles dir"
assert_contains "$out" "$CL_CRED"         "doctor prints cred path"
assert_contains "$out" "personal"         "doctor lists a profile"
assert_contains "$out" "jq"               "doctor reports jq presence"
cleanup_sandbox

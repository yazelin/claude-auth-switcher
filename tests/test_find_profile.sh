source "$ROOT/lib/core.sh"
new_sandbox
echo '{"refreshToken":"ref-personal"}' > "$CL_PROFILES_DIR/personal.json"
echo '{"refreshToken":"ref-company"}'  > "$CL_PROFILES_DIR/company.json"

assert_eq "personal" "$(cl_find_profile_by_refresh "$CL_PROFILES_DIR" "ref-personal")" "matches personal"
assert_eq "company"  "$(cl_find_profile_by_refresh "$CL_PROFILES_DIR" "ref-company")"  "matches company"
assert_eq ""         "$(cl_find_profile_by_refresh "$CL_PROFILES_DIR" "ref-unknown")"  "no match -> empty"
cleanup_sandbox

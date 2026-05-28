CL="$ROOT/bin/cl"
new_sandbox
echo '{"refreshToken":"r1"}' > "$CL_PROFILES_DIR/personal.json"
echo '{"refreshToken":"r2"}' > "$CL_PROFILES_DIR/company.json"
arc="$CL_SANDBOX/backup.tgz"

bash "$CL" export "$arc"
assert_ok "[ -s \"$arc\" ]" "archive created"

rm -f "$CL_PROFILES_DIR/personal.json" "$CL_PROFILES_DIR/company.json"
bash "$CL" restore "$arc"
assert_ok "[ -f \"$CL_PROFILES_DIR/personal.json\" ]" "personal restored"
assert_eq "r2" "$(jq -r .refreshToken "$CL_PROFILES_DIR/company.json")" "company restored intact"
cleanup_sandbox

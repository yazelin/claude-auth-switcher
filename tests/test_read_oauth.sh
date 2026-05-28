source "$ROOT/lib/core.sh"
new_sandbox
write_sample_cred "$CL_CRED" "alpha"

oauth="$(cl_read_oauth "$CL_CRED")"
assert_eq "acc-alpha" "$(echo "$oauth" | jq -r '.accessToken')" "reads accessToken"
assert_eq "ref-alpha" "$(echo "$oauth" | jq -r '.refreshToken')" "reads refreshToken"

now="$(cl_now_ms)"
assert_ok "[ \"$now\" -gt 1700000000000 ]" "now_ms is epoch-ms"
cleanup_sandbox

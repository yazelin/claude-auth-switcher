assert_eq "1" "1" "harness runs"
new_sandbox
write_sample_cred "$CL_CRED" "alpha"
assert_contains "$(cat "$CL_CRED")" "MCP-KEEP-ME" "sample cred written"
cleanup_sandbox

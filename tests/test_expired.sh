source "$ROOT/lib/core.sh"
# Far-future expiry -> not expired
assert_fail "cl_token_expired '{\"expiresAt\": 99999999999999}'" "far future not expired"
# Zero expiry -> expired
assert_ok   "cl_token_expired '{\"expiresAt\": 0}'" "zero is expired"
# Missing expiresAt -> treat as expired
assert_ok   "cl_token_expired '{}'" "missing is expired"

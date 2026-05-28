source "$ROOT/lib/core.sh"

sample='{"five_hour":{"utilization":16,"resets_at":"2026-05-29T05:40:00+00:00"},
         "seven_day":{"utilization":3,"resets_at":"2026-06-03T18:00:00+00:00"},
         "seven_day_opus":null,
         "seven_day_sonnet":{"utilization":0,"resets_at":null}}'

out="$(cl_format_usage "$sample")"
assert_contains "$out" "16" "shows 5h utilization"
assert_contains "$out" "3"  "shows weekly utilization"
assert_contains "$out" "5h" "shows 5h label"
assert_eq "" "$(echo "$out" | grep -i opus || true)" "null bucket omitted"

# cl_fetch_usage delegates to the overridable getter:
cl_http_get_usage() { echo "$sample"; }
fetched="$(cl_fetch_usage "any-token")"
assert_eq "16" "$(echo "$fetched" | jq -r '.five_hour.utilization')" "fetch returns json"

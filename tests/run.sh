#!/usr/bin/env bash
# Runs every tests/test_*.sh in a subshell. Exit non-zero if any assertion failed.
set -u
cd "$(dirname "$0")"
total=0
for t in test_*.sh; do
  [ -e "$t" ] || continue
  echo "== $t =="
  ( CL_TEST_FAILS=0; source ./helpers.sh; source "./$t"; exit "$CL_TEST_FAILS" )
  total=$((total + $?))
done
if [ "$total" -eq 0 ]; then printf '\033[32mALL TESTS PASSED\033[0m\n'; else printf '\033[31m%d FAILURE(S)\033[0m\n' "$total"; fi
exit "$total"

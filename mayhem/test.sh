#!/usr/bin/env bash
#
# leveldb/mayhem/test.sh — RUN leveldb's GoogleTest suite (leveldb_tests, built by build.sh) → CTRF.
# PATCH-grade oracle. mayhem/build.sh compiled build-tests/leveldb_tests with normal flags; this only
# runs it and reports counts.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN=./build-tests/leveldb_tests
[ -x "$BIN" ] || { echo "missing $BIN — run mayhem/build.sh first" >&2; exit 2; }
out="$("$BIN" 2>&1)"; echo "$out"

# GoogleTest summary lines: "[==========] N tests from M ... ran.", "[ PASSED ] P tests.",
# "[ SKIPPED ] S tests, ...". failed = total - passed - skipped (avoids parsing repeated FAILED lines).
total=$(  printf '%s\n' "$out" | sed -n 's/.*\[=*\] \([0-9][0-9]*\) tests* from .*ran\..*/\1/p'    | tail -1)
passed=$( printf '%s\n' "$out" | sed -n 's/.*\[ *PASSED *\] \([0-9][0-9]*\) tests*\..*/\1/p'        | tail -1)
skipped=$(printf '%s\n' "$out" | sed -n 's/.*\[ *SKIPPED *\] \([0-9][0-9]*\) tests*,.*/\1/p'        | tail -1)
: "${total:=0}" "${passed:=0}" "${skipped:=0}"
failed=$(( total - passed - skipped )); [ "$failed" -lt 0 ] && failed=0

emit_ctrf "googletest" "$passed" "$failed" "$skipped"

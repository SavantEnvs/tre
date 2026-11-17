#!/usr/bin/env bash
#
# mayhem/test.sh — RUN TRE's own test suite (built by mayhem/build.sh in mayhem/build-test).
# exit 0 = pass. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
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


T="$SRC/mayhem/build-test/tests"
passed=0; failed=0
pass() { echo "PASS: $1"; passed=$((passed+1)); }
fail() { echo "FAIL: $1"; failed=$((failed+1)); }

for b in retest wretest test-str-source; do
  [ -x "$T/$b" ] || { echo "missing test runner $T/$b — mayhem/build.sh did not build it" >&2; exit 1; }
done
[ -x "$SRC/mayhem/build-test/src/agrep" ] || { echo "missing agrep test build" >&2; exit 1; }

# retest / wretest: known-answer regcomp/regexec tests; they print "All N tests passed." only when
# every asserted match offset was right.
for b in retest wretest; do
  out=$("$T/$b" 2>&1); rc=$?
  if [ $rc -eq 0 ] && grep -Eq '^All [1-9][0-9]* tests passed\.$' <<<"$out"; then pass "$b"
  else echo "$out" | tail -20; fail "$b"; fi
done

# test-str-source: tre_reguexec back-reference matches; exactly 3 matches and 2 non-matches.
out=$("$T/test-str-source" 2>&1); rc=$?
nm=$(grep -c '^Match: ' <<<"$out"); nn=$(grep -c '^No match: ' <<<"$out")
if [ $rc -eq 0 ] && [ "$nm" -eq 3 ] && [ "$nn" -eq 2 ] \
   && grep -qF 'Match: /(foo)\1/ matches "foofoo" in "xfoofofoofoo"' <<<"$out"; then pass test-str-source
else echo "$out"; fail test-str-source; fi

# agrep: upstream's golden-output suites (tests/agrep/*.args → diff against *.ok).
work=$(mktemp -d)
for args in "$SRC"/tests/agrep/*.args; do
  base=$(basename "$args" .args)
  mkdir -p "$work/$base/src" && cp "$args" "${args%.args}.input" "${args%.args}.ok" "$work/$base/"
  ln -sf "$SRC/mayhem/build-test/src/agrep" "$work/$base/src/agrep"
  out=$(cd "$work/$base" && srcdir=. builddir=. top_builddir=. host_triplet=x86_64-pc-linux-gnu \
        sh "$SRC/tests/agrep/run-tests.sh" 2>&1); rc=$?
  if [ $rc -eq 0 ] && grep -q '^1/1 tests OK$' <<<"$out"; then pass "agrep:$base"
  else echo "$out" | tail -20; fail "agrep:$base"; fi
done
rm -rf "$work"

emit_ctrf "tre-check" "$passed" "$failed" 0

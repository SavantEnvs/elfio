#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
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

# RUN the gtest suite built by build.sh (from its fixture-copy dir; tests find elf_examples/ and ario/ there).
BT="$SRC/build-tests"
[ -x "$BT/ELFIOTest" ] || { echo "missing $BT/ELFIOTest — build.sh must build it" >&2; emit_ctrf "gtest" 0 1 0; exit 1; }
[ -x "$BT/kat_probe" ] || { echo "missing $BT/kat_probe — build.sh must build it" >&2; emit_ctrf "gtest" 0 1 0; exit 1; }

out="$(cd "$BT" && ./ELFIOTest 2>&1)"; rc=$?
printf '%s\n' "$out" | tail -15
passed=$(printf '%s\n' "$out" | sed -n 's/^\[  PASSED  \] \([0-9]*\) tests\?\..*/\1/p' | tail -1)
failed=$(printf '%s\n' "$out" | sed -n 's/^\[  FAILED  \] \([0-9]*\) tests\?, listed below.*/\1/p' | tail -1)
skipped=$(printf '%s\n' "$out" | sed -n 's/^\[  SKIPPED \] \([0-9]*\) tests\?, listed below.*/\1/p' | tail -1)
passed=${passed:-0}; failed=${failed:-0}; skipped=${skipped:-0}
# A run that printed no gtest verdict (crash, or a neutered binary) is a failure, not a pass.
if [ "$passed" -eq 0 ] && [ "$failed" -eq 0 ]; then failed=1; fi
if [ "$rc" -ne 0 ] && [ "$failed" -eq 0 ]; then failed=1; fi

# Known-answer probes: fixed ELF fixture -> exact parsed fields, compared here in bash.
kat() {
  local f="$1" want="$2" got
  got="$(cd "$BT" && ./kat_probe "elf_examples/$f" 2>&1 | tr '\n' '|')"
  if [ "$got" = "$want" ]; then passed=$((passed+1)); else
    echo "KAT FAIL $f: got [$got] want [$want]" >&2; failed=$((failed+1)); fi
}
kat hello_64    'class=2 machine=62 type=2 entry=0x4003c0 sections=29 segments=8|.text size=456 addr=0x4003c0|'
kat hello_32    'class=1 machine=3 type=2 entry=0x80482b0 sections=28 segments=7|.text size=424 addr=0x80482b0|'
kat test_ppc    'class=1 machine=20 type=2 entry=0x10000550 sections=31 segments=8|.text size=1152 addr=0x10000550|'
kat hello_arm.o 'class=1 machine=40 type=1 entry=0x0 sections=10 segments=0|.text size=36 addr=0x0|'

emit_ctrf "gtest" "$passed" "$failed" "$skipped"

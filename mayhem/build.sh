#!/usr/bin/env bash
#
# mayhem/build.sh — ELFIO and ARIO are header-only, so the "project" is compiled into each harness /
# test translation unit. Builds: the sanitized libFuzzer harnesses (+ -standalone reproducers), the
# gtest suite with NORMAL flags (build-tests/, gitignored by upstream's /build*/ rule), and a KAT probe.
# GoogleTest comes from the apt libgtest-dev package (no network, so the offline PATCH re-run works).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
OUT=/mayhem
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1) Sanitized fuzz harnesses + standalone reproducers (headers are compiled into the harness TU).
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$TMP/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$TMP/standalone_main.o"
for h in elfio_fuzzer ario_fuzzer; do
    $CXX -std=c++17 -O1 $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE -I"$SRC" \
        "$SRC/mayhem/harnesses/$h.cpp" "$TMP/lsan_off.o" -o "$OUT/$h"
    $CXX -std=c++17 -O1 $SANITIZER_FLAGS $DEBUG_FLAGS -I"$SRC" \
        "$SRC/mayhem/harnesses/$h.cpp" "$TMP/standalone_main.o" "$TMP/lsan_off.o" -o "$OUT/$h-standalone"
done

# 2) The project's own gtest suite, NORMAL flags, run from a copy of the fixture dirs.
BT="$SRC/build-tests"
mkdir -p "$BT"
rm -rf "$BT/elf_examples" "$BT/ario"
cp -r "$SRC/tests/elf_examples" "$SRC/tests/ario" "$BT/"
pids=()
for f in ELFIOTest ELFIOTest1 ELFIOTest2 ARIOTest; do
    $CXX -std=c++17 -O1 $COVERAGE_FLAGS -I"$SRC" -c "$SRC/tests/$f.cpp" -o "$BT/$f.o" &
    pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
$CXX $COVERAGE_FLAGS "$BT"/ELFIOTest.o "$BT"/ELFIOTest1.o "$BT"/ELFIOTest2.o "$BT"/ARIOTest.o \
    -lgtest_main -lgtest -pthread -o "$BT/ELFIOTest"

# 3) Known-answer probe (normal flags) used by test.sh.
$CXX -std=c++17 -O1 -I"$SRC" "$SRC/mayhem/kat_probe.cpp" -o "$BT/kat_probe"

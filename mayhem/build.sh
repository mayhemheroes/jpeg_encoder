#!/usr/bin/env bash
#
# mayhem/build.sh — build jpeg_encoder's fuzz harness + standalone reproducer + test oracle.
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# 1) Sanitized, coverage-instrumented build of the project library object (the code we fuzz).
#    -fsanitize=fuzzer-no-link adds SanitizerCoverage to the LIBRARY itself (not just the harness),
#    so the fuzzer sees edges inside jpeg_encoder.cpp. The fuzzer binary links the real libFuzzer
#    runtime; the standalone reproducer links ASan's weak (no-op) sancov stubs.
$CXX $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS -std=c++11 -I"$SRC" -c "$SRC/jpeg_encoder.cpp" -o /tmp/jpeg_encoder.san.o

# 2a) The libFuzzer harness (instrumented + fuzzing engine).
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE -std=c++11 -I"$SRC" \
    "$SRC/mayhem/fuzz-jpeg.cpp" /tmp/jpeg_encoder.san.o -o /mayhem/fuzzjpeg

# 2b) Standalone (non-fuzzer) run-once reproducer. The C++ harness references
#     LLVMFuzzerTestOneInput with C linkage, so compile the LLVM standalone driver as a C
#     object first (clang++ would otherwise mangle the reference).
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++11 -I"$SRC" \
    "$SRC/mayhem/fuzz-jpeg.cpp" /tmp/standalone_main.o /tmp/jpeg_encoder.san.o \
    -o /mayhem/fuzzjpeg-standalone

# 3) The behavioral test oracle, built with the project's NORMAL flags (clean, no sanitizers)
#    so test.sh stays an honest functional oracle. Append $COVERAGE_FLAGS (empty by default).
$CXX -O2 $COVERAGE_FLAGS -std=c++11 -I"$SRC" \
    "$SRC/mayhem/test_oracle.cpp" "$SRC/jpeg_encoder.cpp" -o /mayhem/test_oracle

echo "build.sh: built /mayhem/fuzzjpeg, /mayhem/fuzzjpeg-standalone, /mayhem/test_oracle"

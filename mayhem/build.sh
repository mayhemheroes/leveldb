#!/usr/bin/env bash
# leveldb/mayhem/build.sh — cmake build (ASan+UBSan) + the fuzz_db libFuzzer harness.
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}" ; : "${MAYHEM_JOBS:=$(nproc)}"
export CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS DEBUG_FLAGS
cd "$SRC"
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DLEVELDB_BUILD_TESTS=0 -DLEVELDB_BUILD_BENCHMARKS=0 \
      -DCMAKE_CXX_STANDARD=17 -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS" ..
cmake --build . -j"$MAYHEM_JOBS"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -fno-rtti -std=c++17 -DLEVELDB_PLATFORM_POSIX=1 \
     -I "$SRC/build/include" -I "$SRC" -I "$SRC/include" \
     "$SRC/mayhem/fuzz_db.cc" $LIB_FUZZING_ENGINE libleveldb.a -o /mayhem/fuzz_db
# also a standalone (non-fuzzer) reproducer: same harness + LLVM's standalone main, no fuzzing engine.
# Compile the driver as C ($CC) so its LLVMFuzzerTestOneInput ref keeps C linkage (clang++ would mangle it).
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -fno-rtti -std=c++17 -DLEVELDB_PLATFORM_POSIX=1 \
     -I "$SRC/build/include" -I "$SRC" -I "$SRC/include" \
     "$SRC/mayhem/fuzz_db.cc" /tmp/standalone_main.o libleveldb.a -o /mayhem/fuzz_db-standalone

# Build leveldb's own GoogleTest suite (NORMAL flags, separate build dir) so mayhem/test.sh only
# RUNS it. googletest is baked into the image (Dockerfile); fetch as a fallback if absent.
cd "$SRC"
[ -n "$(ls -A third_party/googletest 2>/dev/null)" ] || git submodule update --init third_party/googletest
cmake -S . -B build-tests -DCMAKE_BUILD_TYPE=Release -DLEVELDB_BUILD_TESTS=1 \
      -DLEVELDB_BUILD_BENCHMARKS=0 -DCMAKE_CXX_STANDARD=17 >/dev/null
cmake --build build-tests -j"$MAYHEM_JOBS" --target leveldb_tests

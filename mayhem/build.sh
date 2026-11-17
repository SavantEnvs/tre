#!/usr/bin/env bash
#
# mayhem/build.sh — build TRE's fuzz targets and its test suite (runs as `mayhem` in /mayhem).
#
# Upstream is autotools without a committed configure: utils/autogen.sh generates it (outputs are
# covered by upstream's .gitignore files). Three out-of-tree builds, all under mayhem/ and ignored by
# mayhem/.gitignore so `git clean -ffdX` removes their configure state:
#   mayhem/build-fuzz  libtre.a with $SANITIZER_FLAGS + SanCov  -> the four libFuzzer harnesses
#   mayhem/build-afl   agrep with afl-clang-fast + $SANITIZER_FLAGS -> the agrep AFL target
#   mayhem/build-test  normal flags, `make check` programs       -> what mayhem/test.sh runs
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
M="$SRC/mayhem"

# 0) Generate configure (re-generated after a git clean, or when configure.ac is newer).
if [ ! -x configure ] || [ configure.ac -nt configure ] || [ ! -f Makefile.in ]; then
  sh utils/autogen.sh
fi

conf() {  # conf <builddir> <CC> <CFLAGS> [extra configure args]
  local dir="$1" cc="$2" cflags="$3"; shift 3
  mkdir -p "$dir"
  if [ ! -f "$dir/config.status" ] || [ "$SRC/configure" -nt "$dir/config.status" ]; then
    (cd "$dir" && "$SRC/configure" --disable-shared --enable-static --disable-nls \
        CC="$cc" CFLAGS="$cflags" "$@")
  fi
}

# 1) Sanitized library. SanCov (-fsanitize=fuzzer-no-link) is passed to make only, so configure's
#    link tests don't need the libFuzzer runtime.
conf "$M/build-fuzz" "$CC" "-O1 $SANITIZER_FLAGS $DEBUG_FLAGS" --disable-agrep
make -C "$M/build-fuzz/lib" -j"$MAYHEM_JOBS" \
  CFLAGS="-O1 $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link"
LIBTRE="$M/build-fuzz/lib/.libs/libtre.a"
INC=(-I"$SRC/include" -I"$M/build-fuzz/include/tre")

$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$M/lsan_off.cc" -o "$M/build-fuzz/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$M/build-fuzz/standalone_main.o"
for h in regexec regwexec regbexec reguexec; do
  src="$M/harnesses/fuzz_$h.c"
  $CC -O1 $SANITIZER_FLAGS $DEBUG_FLAGS "${INC[@]}" -c "$src" -o "$M/build-fuzz/fuzz_$h.o"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$M/build-fuzz/fuzz_$h.o" "$LIBTRE" \
    "$M/build-fuzz/lsan_off.o" -o "$SRC/fuzz_$h"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$M/build-fuzz/standalone_main.o" "$M/build-fuzz/fuzz_$h.o" \
    "$LIBTRE" "$M/build-fuzz/lsan_off.o" -o "$SRC/fuzz_$h-standalone"
done

# 2) agrep, AFL-instrumented, the whole project sanitized. lsan_off is linked through LIBS.
mkdir -p "$M/build-afl"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$M/lsan_off.cc" -o "$M/build-afl/lsan_off.o"
conf "$M/build-afl" afl-clang-fast "-O1 $SANITIZER_FLAGS $DEBUG_FLAGS"
for d in include lib; do make -C "$M/build-afl/$d" -j"$MAYHEM_JOBS"; done
make -C "$M/build-afl/src" -j"$MAYHEM_JOBS" LIBS="$M/build-afl/lsan_off.o"
cp -f "$M/build-afl/src/agrep" "$SRC/agrep-afl"

# 3) Test suite with the project's normal flags (built, not run: mayhem/test.sh runs it).
conf "$M/build-test" "$CC" "-O2 $COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS"
for d in include lib src; do make -C "$M/build-test/$d" -j"$MAYHEM_JOBS"; done
make -C "$M/build-test/tests" -j"$MAYHEM_JOBS" check TESTS= SUBDIRS=

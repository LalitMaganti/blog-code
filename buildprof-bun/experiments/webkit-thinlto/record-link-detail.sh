#!/usr/bin/env bash
set -euo pipefail
root=/home/lalitm/bun-bench/webkit-thinlto-20260905
suffix=${BUILDPROF_EXPERIMENT_SUFFIX:-process-only}
case "$suffix" in process-only | shards4-link-detail) ;; *) exit 2 ;; esac
run=$root/results-$suffix/webkit-thin
recorder=/home/lalitm/bun-bench/buildprof-src/target/release/buildprof
test "$PWD" = "$root/dag-$suffix/link/build/webkit-experiment"
test -f bun-profile
test ! -e bun-profile.first-link
mv bun-profile bun-profile.first-link
# Expose the compiler and linker selection to buildprof's compiler wrapper.
# All link inputs and optimization flags remain the same.
sed 's#/usr/lib/llvm-21/bin/clang++#clang++ -fuse-ld=lld#g' build.ninja >compiler-detail.ninja
grep -q 'clang++ -fuse-ld=lld' compiler-detail.ninja
export PATH=/usr/lib/llvm-21/bin:$PATH
"$recorder" --compiler-traces --no-open -o "$run/bun-zig-webkit-thin-link-detail.buildprof" \
  -- ninja -d keeprsp -f compiler-detail.ninja bun-profile
cp bun-profile.rsp "$run/final-link.rsp"
./bun-profile --revision
./bun-profile -e 'console.log("link replay passed")'

#!/usr/bin/env bash
set -euo pipefail

bench_root=${BUILDPROF_BENCH_ROOT:-/home/lalitm/bun-bench}
checkout=${BUILDPROF_LINK_CHECKOUT:-$bench_root/ci-dag-repro/link}
artifact_root=${BUILDPROF_ARTIFACT_ROOT:-$bench_root/original-traces/ci-zig/artifacts}
output_root=${BUILDPROF_OUTPUT_ROOT:-$bench_root/original-traces/ci-zig}
build_dir=build/original-ci-link-detail
build_abs=$checkout/$build_dir
trace=$output_root/bun-zig-full-lto-link-detail.buildprof
log=$output_root/bun-zig-full-lto-link-detail.log
manifest=$output_root/bun-zig-full-lto-link-detail.manifest
recorder=$bench_root/buildprof-src/target/release/buildprof
capture=$bench_root/recording-bin/capture-bun-compiler-detail.sh
revision=0d9b296af33f2b851fcbf4df3e9ec89751734ba4

test -x "$recorder"
test -x "$capture"
test "$(git -C "$checkout" rev-parse HEAD)" = "$revision"
test -z "$(git -C "$checkout" status --porcelain)"
test ! -e "$trace"
test ! -e "$build_abs"

cleanup() {
  rm -rf -- "$build_abs"
}
trap cleanup EXIT

mkdir -p "$build_abs"
cp -a "$artifact_root/linux-x64-build-cpp/." "$build_abs/"
cp -a "$artifact_root/linux-x64-build-zig/." "$build_abs/"

cd "$checkout"
node --experimental-strip-types scripts/build.ts \
  "--build-dir=$build_dir" \
  --profile=ci-link-only \
  --configure-only

{
  echo "era=zig"
  echo "kind=historical-ci-full-lto-link-detail"
  echo "revision=$revision"
  echo "source_trace=$output_root/bun-zig-original-ci.buildprof"
  echo "command=ninja -C $build_dir bun-profile"
  echo "started_at=$(date --iso-8601=seconds)"
  echo "host=$(hostname)"
  echo "logical_cpus=$(nproc)"
  echo "memory_bytes=$(awk '/MemTotal/{print $2 * 1024}' /proc/meminfo)"
  echo "recorder_sha256=$(sha256sum "$recorder" | awk '{print $1}')"
} >"$manifest"

cd "$build_abs"
export PATH=/usr/lib/llvm-21/bin:$PATH
BUILDPROF_BIN=$recorder \
  BUILDPROF_OUTPUT=$trace \
  "$capture" bun-profile 2>&1 | tee "$log"

{
  echo "finished_at=$(date --iso-8601=seconds)"
  echo "trace_bytes=$(stat -c %s "$trace")"
  echo "trace_sha256=$(sha256sum "$trace" | awk '{print $1}')"
} >>"$manifest"

echo "Zig full-LTO link detail trace complete: $trace"

#!/usr/bin/env bash
set -euo pipefail

bench_root=${BUILDPROF_BENCH_ROOT:-/home/lalitm/bun-bench}
checkout=${BUILDPROF_CHECKOUT:-$bench_root/ci-rust-repro}
git_root=${BUILDPROF_GIT_ROOT:-/home/lalitm/depot/projects/bun}
run_root=${BUILDPROF_RUN_ROOT:-$bench_root/original-traces/ci-rust}
cache_root=${BUILDPROF_CACHE_ROOT:-$bench_root/recording-cache/rust}
revision=34cbb9a40b4bd1bd767d134a7065e66c2432a676
build_dir=${BUILDPROF_BUILD_DIR:-build/original-ci}
trace=$run_root/bun-rust-original-ci.buildprof
log=$run_root/bun-rust-original-ci.log
manifest=$run_root/bun-rust-original-ci.manifest
artifact_root=$run_root/artifacts
image=ghcr.io/oven-sh/bun-development-docker-image:latest
recorder=$bench_root/buildprof-src/target/release/buildprof
command=(node --experimental-strip-types scripts/build.ts "--build-dir=$build_dir" --profile=ci-build --os=linux --arch=x64 --abi=gnu)

mkdir -p "$run_root"
test ! -e "$trace"
test ! -e "$artifact_root"
test -x "$recorder"
test "$(git -C "$checkout" rev-parse HEAD)" = "$revision"
test -z "$(git -C "$checkout" status --porcelain)"
test ! -e "$checkout/$build_dir"

{
  echo "era=rust"
  echo "kind=historical-ci"
  echo "revision=$revision"
  echo "command=${command[*]}"
  echo "started_at=$(date --iso-8601=seconds)"
  echo "host=$(hostname)"
  echo "logical_cpus=$(nproc)"
  echo "memory_bytes=$(awk '/MemTotal/{print $2 * 1024}' /proc/meminfo)"
  echo "image=$image"
  echo "image_id=$(docker image inspect --format '{{.Id}}' "$image")"
  echo "recorder_sha256=$(sha256sum "$recorder" | awk '{print $1}')"
} >"$manifest"

mkdir "$artifact_root"

docker run --rm \
  --cap-add SYS_PTRACE \
  --security-opt seccomp=unconfined \
  -v "$bench_root:$bench_root" \
  -v "$git_root:$git_root:ro" \
  -v "$cache_root/cargo-registry:/opt/rust/registry" \
  -v "$cache_root/cargo-git:/opt/rust/git" \
  -v "$cache_root/bun-install:/root/.bun/install/cache" \
  -v "$cache_root/bun-build:/root/.bun/build-cache" \
  -w "$checkout" \
  -e CCACHE_DISABLE=1 \
  -e CI=true \
  -e BUILDKITE_STEP_KEY=linux-x64-build-bun \
  -e BUILDPROF_ARTIFACT_ROOT="$artifact_root" \
  -e PATH="$bench_root/ci-dag-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  --entrypoint "$recorder" \
  "$image" \
  --no-open -o "$trace" -- "${command[@]}" 2>&1 | tee "$log"

{
  echo "finished_at=$(date --iso-8601=seconds)"
  echo "trace_bytes=$(stat -c %s "$trace")"
  echo "trace_sha256=$(sha256sum "$trace" | awk '{print $1}')"
} >>"$manifest"

echo "historical Rust CI trace complete: $trace"

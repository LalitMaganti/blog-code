#!/usr/bin/env bash
set -euo pipefail

bench_root=${BUILDPROF_BENCH_ROOT:-/home/lalitm/bun-bench}
dag_root=${BUILDPROF_DAG_ROOT:-$bench_root/ci-dag-repro}
git_root=${BUILDPROF_GIT_ROOT:-/home/lalitm/depot/projects/bun}
run_root=${BUILDPROF_RUN_ROOT:-$bench_root/original-traces/ci-zig}
cache_root=${BUILDPROF_CACHE_ROOT:-$bench_root/recording-cache/zig}
revision=0d9b296af33f2b851fcbf4df3e9ec89751734ba4
build_dir=${BUILDPROF_BUILD_DIR:-build/original-ci}
artifact_root=$run_root/artifacts
trace=$run_root/bun-zig-original-ci.buildprof
log=$run_root/bun-zig-original-ci.log
manifest=$run_root/bun-zig-original-ci.manifest
image=ghcr.io/oven-sh/bun-development-docker-image:latest
recorder=$bench_root/buildprof-src/target/release/buildprof
harness=$bench_root/recording-bin/run-zig-ci-dag.sh

mkdir -p "$run_root"
test ! -e "$trace"
test ! -e "$artifact_root"
test -x "$recorder"
test -x "$harness"
for lane in cpp zig link; do
  checkout=$dag_root/$lane
  test "$(git -C "$checkout" rev-parse HEAD)" = "$revision"
  test -z "$(git -C "$checkout" status --porcelain)"
  test ! -e "$checkout/$build_dir"
done

{
  echo "era=zig"
  echo "kind=historical-ci-single-machine-dag"
  echo "revision=$revision"
  echo "cpp_command=node --experimental-strip-types scripts/build.ts --build-dir=$build_dir --profile=ci-cpp-only"
  echo "zig_command=node --experimental-strip-types scripts/build.ts --build-dir=$build_dir --profile=ci-zig-only --os=linux --arch=x64 --abi=gnu"
  echo "link_command=node --experimental-strip-types scripts/build.ts --build-dir=$build_dir --profile=ci-link-only"
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
  -v "$cache_root/cargo-registry:/root/.cargo/registry" \
  -v "$cache_root/cargo-git:/root/.cargo/git" \
  -v "$cache_root/bun-install:/root/.bun/install/cache" \
  -v "$cache_root/bun-build:/root/.bun/build-cache" \
  -w "$bench_root" \
  -e CCACHE_DISABLE=1 \
  -e BUILDPROF_DAG_ROOT="$dag_root" \
  -e BUILDPROF_ARTIFACT_ROOT="$artifact_root" \
  -e BUILDPROF_BUILD_DIR="$build_dir" \
  -e PATH="$bench_root/ci-dag-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  --entrypoint "$recorder" \
  "$image" \
  --no-open -o "$trace" -- "$harness" 2>&1 | tee "$log"

{
  echo "finished_at=$(date --iso-8601=seconds)"
  echo "trace_bytes=$(stat -c %s "$trace")"
  echo "trace_sha256=$(sha256sum "$trace" | awk '{print $1}')"
} >>"$manifest"

echo "historical Zig CI trace complete: $trace"

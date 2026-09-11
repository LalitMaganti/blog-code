#!/usr/bin/env bash
set -euo pipefail

era=${1:?usage: record-bun-developer-series.sh zig|rust}
case "$era" in
  zig)
    revision=0d9b296af33f2b851fcbf4df3e9ec89751734ba4
    native_patch=incremental-zig.patch
    cargo_home=/root/.cargo
    ;;
  rust)
    revision=34cbb9a40b4bd1bd767d134a7065e66c2432a676
    native_patch=incremental-rust.patch
    cargo_home=/opt/rust
    ;;
  *)
    echo "era must be zig or rust" >&2
    exit 2
    ;;
esac

bench_root=${BUILDPROF_BENCH_ROOT:-/home/lalitm/bun-bench}
checkout=${BUILDPROF_CHECKOUT:-$bench_root/$era}
git_root=${BUILDPROF_GIT_ROOT:-/home/lalitm/depot/projects/bun}
run_root=${BUILDPROF_RUN_ROOT:-$bench_root/original-traces/developer-$era}
asset_root=${BUILDPROF_ASSET_ROOT:-$bench_root/recording-bin}
cache_root=${BUILDPROF_CACHE_ROOT:-$bench_root/recording-cache/$era}
recorder=${BUILDPROF_BIN:-$bench_root/buildprof-src/target/release/buildprof}
image=${BUILDPROF_IMAGE:-ghcr.io/oven-sh/bun-development-docker-image:latest}

mkdir -p "$run_root"
mkdir -p "$cache_root/cargo-registry" "$cache_root/cargo-git" "$cache_root/bun-install" "$cache_root/bun-build"
test -x "$recorder"
test -d "$git_root/.git"
test "$(git -C "$checkout" rev-parse HEAD)" = "$revision"
test -z "$(git -C "$checkout" status --porcelain)"
git -C "$checkout" apply --check "$asset_root/$native_patch"
git -C "$checkout" apply --check "$asset_root/incremental-cpp.patch"
if [[ ${BUILDPROF_ONLY_CPP:-0} == 1 ]]; then
  test -d "$checkout/build/debug"
else
  test ! -e "$checkout/build/debug"
  test ! -e "$checkout/build/release"
fi

record() {
  name=$1
  shift
  trace="$run_root/bun-$era-$name.buildprof"
  log="$run_root/bun-$era-$name.log"
  manifest="$run_root/bun-$era-$name.manifest"
  test ! -e "$trace"

  {
    echo "era=$era"
    echo "name=$name"
    echo "revision=$revision"
    echo "command=$*"
    echo "started_at=$(date --iso-8601=seconds)"
    echo "host=$(hostname)"
    echo "logical_cpus=$(nproc)"
    echo "memory_bytes=$(awk '/MemTotal/{print $2 * 1024}' /proc/meminfo)"
    echo "kernel=$(uname -r)"
    echo "image=$image"
    echo "image_id=$(docker image inspect --format '{{.Id}}' "$image")"
    echo "recorder_sha256=$(sha256sum "$recorder" | awk '{print $1}')"
    echo "source_diff_sha256=$(git -C "$checkout" diff --binary | sha256sum | awk '{print $1}')"
  } >"$manifest"

  docker run --rm \
    --cap-add SYS_PTRACE \
    --security-opt seccomp=unconfined \
    -v "$bench_root:$bench_root" \
    -v "$git_root:$git_root:ro" \
    -v "$cache_root/cargo-registry:$cargo_home/registry" \
    -v "$cache_root/cargo-git:$cargo_home/git" \
    -v "$cache_root/bun-install:/root/.bun/install/cache" \
    -v "$cache_root/bun-build:/root/.bun/build-cache" \
    -w "$checkout" \
    -e CCACHE_DISABLE=1 \
    --entrypoint "$recorder" \
    "$image" \
    --no-open -o "$trace" -- "$@" 2>&1 | tee "$log"

  {
    echo "finished_at=$(date --iso-8601=seconds)"
    echo "trace_bytes=$(stat -c %s "$trace")"
    echo "trace_sha256=$(sha256sum "$trace" | awk '{print $1}')"
  } >>"$manifest"
}

if [[ ${BUILDPROF_ONLY_CPP:-0} != 1 ]]; then
  # Dependencies and toolchains are retained, but compiled outputs begin empty.
  record release-clean bun run build:release
  record debug-clean bun run build
  record debug-no-change bun run build

  git -C "$checkout" apply "$asset_root/$native_patch"
  record debug-native-edit bun run build
  git -C "$checkout" apply --reverse "$asset_root/$native_patch"
fi

# Settle the reversed native edit before measuring a C++-only source change.
docker run --rm \
  -v "$bench_root:$bench_root" \
  -v "$git_root:$git_root:ro" \
  -v "$cache_root/cargo-registry:$cargo_home/registry" \
  -v "$cache_root/cargo-git:$cargo_home/git" \
  -v "$cache_root/bun-install:/root/.bun/install/cache" \
  -v "$cache_root/bun-build:/root/.bun/build-cache" \
  -w "$checkout" \
  -e CCACHE_DISABLE=1 \
  --entrypoint bun \
  "$image" run build

git -C "$checkout" apply "$asset_root/incremental-cpp.patch"
record debug-cpp-edit bun run build
git -C "$checkout" apply --reverse "$asset_root/incremental-cpp.patch"

test -z "$(git -C "$checkout" status --porcelain)"
echo "developer trace series complete: $run_root"

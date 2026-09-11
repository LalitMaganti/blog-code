#!/usr/bin/env bash
set -Eeuo pipefail

bench_root=/home/lalitm/bun-bench
queue_root=$bench_root/original-traces-0.2
scripts=$bench_root/recording-bin
dag_scripts=$bench_root/ci-dag-bin
dag_root=$bench_root/ci-dag-repro
recorder=$bench_root/buildprof-src/target/release/buildprof
image=alpine:latest
status=$queue_root/queue.status

mkdir -p "$queue_root"
exec >>"$queue_root/queue.log" 2>&1

stamp() {
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" | tee -a "$status"
}

remove_as_root() {
  docker run --rm -v "$bench_root:$bench_root" "$image" rm -rf -- "$@"
}

reverse_if_applied() {
  local checkout=$1
  local patch=$2
  if git -C "$checkout" apply --reverse --check "$patch" >/dev/null 2>&1; then
    git -C "$checkout" apply --reverse "$patch"
  fi
}

cleanup_ci_builds() {
  local build_name=$1
  remove_as_root \
    "$dag_root/cpp/build/$build_name" \
    "$dag_root/zig/build/$build_name" \
    "$dag_root/link/build/$build_name"
}

cleanup_rust_ci() {
  local build_name=$1
  remove_as_root "$bench_root/rust/build/$build_name"
}

cleanup_developer() {
  local era=$1
  reverse_if_applied "$bench_root/$era" "$scripts/incremental-$era.patch"
  reverse_if_applied "$bench_root/$era" "$scripts/incremental-cpp.patch"
  remove_as_root "$bench_root/$era/build/debug" "$bench_root/$era/build/release"
}

cleanup_thin_patch() {
  local checkout
  for checkout in cpp zig link; do
    reverse_if_applied "$dag_root/$checkout" "$dag_scripts/zig-thinlto.patch"
  done
}

on_exit() {
  local code=$?
  cleanup_thin_patch || true
  cleanup_developer zig || true
  cleanup_developer rust || true
  if ((code != 0)); then
    stamp "QUEUE FAILED exit=$code current=$(cat "$queue_root/current" 2>/dev/null || true)"
    touch "$queue_root/queue.failed"
  fi
}
trap on_exit EXIT

run_job() {
  local name=$1
  shift
  if [[ -e "$queue_root/jobs/$name.done" ]]; then
    stamp "SKIP $name already complete"
    return
  fi
  mkdir -p "$queue_root/jobs"
  printf '%s\n' "$name" >"$queue_root/current"
  stamp "START $name"
  "$@"
  touch "$queue_root/jobs/$name.done"
  stamp "DONE $name"
}

test "$("$recorder" --version)" = "buildprof 0.2.0"
test "$(git -C "$bench_root/buildprof-src" rev-parse HEAD)" = 38a0d0ec45e5b25c3e3356a9ba12c7e091260071
rm -f "$queue_root/queue.done" "$queue_root/queue.failed"
stamp "QUEUE START recorder=$($recorder --version)"

zig_ci_build=recording-0.2-ci
run_job zig-ci env \
  BUILDPROF_RUN_ROOT="$queue_root/ci-zig" \
  BUILDPROF_BUILD_DIR="build/$zig_ci_build" \
  "$scripts/record-original-zig-ci.sh"

run_job zig-link-detail docker run --rm \
  --cap-add SYS_PTRACE \
  --security-opt seccomp=unconfined \
  -v "$bench_root:$bench_root" \
  -v /home/lalitm/depot/projects/bun:/home/lalitm/depot/projects/bun:ro \
  -w "$bench_root" \
  -e BUILDPROF_ARTIFACT_ROOT="$queue_root/ci-zig/artifacts" \
  -e BUILDPROF_OUTPUT_ROOT="$queue_root/ci-zig" \
  --entrypoint bash \
  ghcr.io/oven-sh/bun-development-docker-image:latest \
  "$scripts/record-zig-full-lto-link-detail.sh"
cleanup_ci_builds "$zig_ci_build"
remove_as_root "$queue_root/ci-zig/artifacts"

rust_ci_build=recording-0.2-ci
run_job rust-ci env \
  BUILDPROF_RUN_ROOT="$queue_root/ci-rust" \
  BUILDPROF_CHECKOUT="$bench_root/rust" \
  BUILDPROF_BUILD_DIR="build/$rust_ci_build" \
  "$scripts/record-original-rust-ci.sh"
cleanup_rust_ci "$rust_ci_build"

full_build=recording-0.2-lto-full
run_job zig-full-lto env \
  BUILDPROF_RUN_ROOT="$queue_root/zig-lto-pair" \
  BUILDPROF_BUILD_DIR="build/$full_build" \
  "$dag_scripts/record-zig-ci-dag-variant.sh" full-lto
cleanup_ci_builds "$full_build"
remove_as_root "$queue_root/zig-lto-pair/artifacts-full-lto"

for checkout in cpp zig link; do
  git -C "$dag_root/$checkout" apply "$dag_scripts/zig-thinlto.patch"
done
thin_build=recording-0.2-lto-thin
run_job zig-thin-lto env \
  BUILDPROF_RUN_ROOT="$queue_root/zig-lto-pair" \
  BUILDPROF_BUILD_DIR="build/$thin_build" \
  "$dag_scripts/record-zig-ci-dag-variant.sh" thin-lto
cleanup_ci_builds "$thin_build"
remove_as_root "$queue_root/zig-lto-pair/artifacts-thin-lto"
cleanup_thin_patch

run_job developer-zig env \
  BUILDPROF_RUN_ROOT="$queue_root/developer-zig" \
  "$scripts/record-bun-developer-series.sh" zig
cleanup_developer zig

run_job developer-rust env \
  BUILDPROF_RUN_ROOT="$queue_root/developer-rust" \
  "$scripts/record-bun-developer-series.sh" rust
cleanup_developer rust

rm -f "$queue_root/current"
touch "$queue_root/queue.done"
stamp "QUEUE DONE"

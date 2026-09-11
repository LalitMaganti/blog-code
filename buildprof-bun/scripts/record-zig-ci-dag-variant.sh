#!/usr/bin/env bash
set -euo pipefail

variant=${1:?usage: record-zig-ci-dag-variant.sh VARIANT}
case "$variant" in
  full-lto | thin-lto) ;;
  *)
    echo "variant must be full-lto or thin-lto" >&2
    exit 2
    ;;
esac

bench_root=${BUILDPROF_BENCH_ROOT:-/home/lalitm/bun-bench}
dag_root=${BUILDPROF_DAG_ROOT:-$bench_root/ci-dag-repro}
git_root=${BUILDPROF_GIT_ROOT:-/home/lalitm/depot/projects/bun}
run_root=${BUILDPROF_RUN_ROOT:-$bench_root/original-traces/zig-lto-pair-current}
revision=0d9b296af33f2b851fcbf4df3e9ec89751734ba4
build_dir=${BUILDPROF_BUILD_DIR:-build/lto-pair-current-$variant}
artifact_root="$run_root/artifacts-$variant"
trace="$run_root/bun-zig-ci-dag-$variant.buildprof"
log="$run_root/bun-zig-ci-dag-$variant.log"
manifest="$run_root/bun-zig-ci-dag-$variant.manifest"
image=ghcr.io/oven-sh/bun-development-docker-image:latest
recorder="$bench_root/buildprof-src/target/release/buildprof"
harness="$bench_root/ci-dag-bin/run-zig-ci-dag.sh"
thin_patch="$bench_root/ci-dag-bin/zig-thinlto.patch"

mkdir -p "$run_root"
for checkout in cpp zig link; do
  path="$dag_root/$checkout"
  test "$(git -C "$path" rev-parse HEAD)" = "$revision"
  if [[ $variant == full-lto ]]; then
    test -z "$(git -C "$path" status --porcelain)" || {
      echo "$path must be clean for full-lto" >&2
      git -C "$path" status --short >&2
      exit 1
    }
    git -C "$path" apply --check "$thin_patch"
  else
    git -C "$path" diff --check
    expected_status=$' M build.zig\n M scripts/build/deps/webkit.ts\n M scripts/build/flags.ts'
    actual_status=$(git -C "$path" status --porcelain)
    test "$actual_status" = "$expected_status" || {
      echo "$path has edits beyond the expected ThinLTO patch" >&2
      git -C "$path" status --short >&2
      exit 1
    }
    git -C "$path" apply --reverse --check "$thin_patch" || {
      echo "$path does not contain exactly the expected ThinLTO patch" >&2
      git -C "$path" status --short >&2
      exit 1
    }
  fi
  test ! -e "$path/$build_dir" || {
    echo "refusing reused build directory: $path/$build_dir" >&2
    exit 1
  }
done
test ! -e "$artifact_root" || {
  echo "refusing reused artifact root: $artifact_root" >&2
  exit 1
}
test ! -e "$trace" || {
  echo "refusing to overwrite trace: $trace" >&2
  exit 1
}
test -x "$recorder"
test -x "$harness"
test -d "$git_root/.git"

# Worktree .git files point back into the parent repository. Verify that the
# same revision is visible from inside the exact container/mount arrangement
# before starting an expensive recording.
for checkout in cpp zig link; do
  container_revision=$(docker run --rm \
    -v "$bench_root:$bench_root" \
    -v "$git_root:$git_root:ro" \
    -w "$dag_root/$checkout" \
    --entrypoint git "$image" rev-parse HEAD)
  test "$container_revision" = "$revision" || {
    echo "container cannot resolve $checkout at $revision" >&2
    exit 1
  }
done

{
  echo "variant=$variant"
  echo "started_at=$(date --iso-8601=seconds)"
  echo "revision=$revision"
  echo "build_dir=$build_dir"
  echo "artifact_root=$artifact_root"
  echo "trace=$trace"
  echo "host=$(hostname)"
  echo "logical_cpus=$(nproc)"
  echo "memory_bytes=$(awk '/MemTotal/{print $2 * 1024}' /proc/meminfo)"
  echo "kernel=$(uname -r)"
  echo "image=$image"
  echo "image_id=$(docker image inspect --format '{{.Id}}' "$image")"
  echo "recorder_sha256=$(sha256sum "$recorder" | awk '{print $1}')"
  for checkout in cpp zig link; do
    echo "$checkout.diff_sha256=$(git -C "$dag_root/$checkout" diff --binary | sha256sum | awk '{print $1}')"
  done
} >"$manifest"

mkdir "$artifact_root"
docker run --rm \
  --cap-add SYS_PTRACE \
  --security-opt seccomp=unconfined \
  -v "$bench_root:$bench_root" \
  -v "$git_root:$git_root:ro" \
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

echo "trace: $trace"
echo "manifest: $manifest"

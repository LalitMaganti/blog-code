#!/usr/bin/env bash
set -euo pipefail

: "${BUILDPROF_DAG_ROOT:?BUILDPROF_DAG_ROOT must be set}"
: "${BUILDPROF_ARTIFACT_ROOT:?BUILDPROF_ARTIFACT_ROOT must be set}"

# BUILDKITE_STEP_KEY alone does not make Bun's scripts enter CI mode.
export CI=true

cpp_checkout="$BUILDPROF_DAG_ROOT/cpp"
zig_checkout="$BUILDPROF_DAG_ROOT/zig"
link_checkout="$BUILDPROF_DAG_ROOT/link"
build_dir=${BUILDPROF_BUILD_DIR:-build/ci-dag}
shards=${BUILDPROF_ZIG_SHARDS:-1}
case "$shards" in 1 | 4) ;; *)
  echo 'Supported shard counts: 1 or 4' >&2
  exit 2
  ;;
esac
node=(node --experimental-strip-types scripts/build.ts "--build-dir=$build_dir")
target=(--os=linux --arch=x64 --abi=gnu)

run_cpp() {
  cd "$cpp_checkout"
  BUILDKITE_STEP_KEY=linux-x64-build-cpp \
    "${node[@]}" --profile=ci-cpp-only
}

run_zig() {
  cd "$zig_checkout"
  BUILDKITE_STEP_KEY=linux-x64-build-zig \
    "${node[@]}" --profile=ci-zig-only "${target[@]}"
}

echo "buildprof-dag: launching C++ and Zig producers"
run_cpp &
cpp_pid=$!
run_zig &
zig_pid=$!

set +e
wait "$cpp_pid"
cpp_status=$?
wait "$zig_pid"
zig_status=$?
set -e

if ((cpp_status != 0 || zig_status != 0)); then
  echo "buildprof-dag: producer failure: cpp=$cpp_status zig=$zig_status" >&2
  exit 1
fi

echo "buildprof-dag: producers complete; starting local artifact handoff"
cpp_artifacts=(
  libbun-profile.a
  deps/lolhtml/x86_64-unknown-linux-gnu/release/liblolhtml.a
  cache/webkit-5488984d20e0dbfe-lto/lib/libWTF.a
  cache/webkit-5488984d20e0dbfe-lto/lib/libJavaScriptCore.a
  cache/webkit-5488984d20e0dbfe-lto/lib/libicudata.a
  cache/webkit-5488984d20e0dbfe-lto/lib/libicui18n.a
  cache/webkit-5488984d20e0dbfe-lto/lib/libicuuc.a
  cache/webkit-5488984d20e0dbfe-lto/lib/libbmalloc.a
)

(
  cd "$cpp_checkout/$build_dir"
  IFS=';'
  BUILDKITE_STEP_KEY=linux-x64-build-cpp \
    buildkite-agent artifact upload "${cpp_artifacts[*]}"
)
(
  cd "$zig_checkout/$build_dir"
  zig_artifacts=(bun-zig.o)
  if [[ $shards == 4 ]]; then
    zig_artifacts=(bun-zig.0.o bun-zig.1.o bun-zig.2.o bun-zig.3.o)
  fi
  IFS=';'
  BUILDKITE_STEP_KEY=linux-x64-build-zig \
    buildkite-agent artifact upload "${zig_artifacts[*]}"
)

mkdir -p "$link_checkout/$build_dir"
(
  cd "$link_checkout/$build_dir"
  BUILDKITE_STEP_KEY=linux-x64-build-bun \
    buildkite-agent artifact download '*' . --step linux-x64-build-cpp
  BUILDKITE_STEP_KEY=linux-x64-build-bun \
    buildkite-agent artifact download '*' . --step linux-x64-build-zig
)

echo "buildprof-dag: artifact handoff complete; starting link"
cd "$link_checkout"
BUILDKITE_STEP_KEY=linux-x64-build-bun \
  "${node[@]}" --profile=ci-link-only

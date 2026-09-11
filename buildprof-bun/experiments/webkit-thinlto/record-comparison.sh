#!/usr/bin/env bash
set -Eeuo pipefail

root=/home/lalitm/bun-bench/webkit-thinlto-20260905
bench=/home/lalitm/bun-bench
repo=/home/lalitm/depot/projects/bun
revision=0d9b296af33f2b851fcbf4df3e9ec89751734ba4
image=sha256:d57ac1c6ae0003e55a140b127640c01fff1199409fd1a6fd1daa4690956e4f4e
recorder=$bench/buildprof-src/target/release/buildprof
code_root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
shards=${BUILDPROF_ZIG_SHARDS:-1}
case "$shards" in 1) suffix=process-only ;; 4) suffix=shards4 ;; *) exit 2 ;; esac
if [[ $shards == 4 && ${BUILDPROF_LINK_DETAIL:-0} == 1 ]]; then suffix=shards4-link-detail; fi
dag=$root/dag-$suffix
results=$root/results-$suffix
bin=$root/bin-$suffix
cd "$root"
exec > >(tee -a "comparison-$suffix.log") 2>&1
write_exit_status() {
  local result=$?
  printf "exit=%s\nfinished=%s\n" "$result" "$(date --iso-8601=seconds)" >"comparison-$suffix.status"
}
trap write_exit_status EXIT

# Do not benchmark while WebKit is competing for CPU and memory.
while systemctl --user is-active --quiet webkit-thinlto-split-20260905.service; do
  sleep 30
done
grep -qx 'exit=0' build.status
test -s bun-webkit-linux-amd64-lto.tar.gz
test "$("$recorder" --version)" = 'buildprof 0.2.0'
test "$(sha256sum "$recorder" | cut -d' ' -f1)" = 4a628ce32221e7c9c73e18083fd54393f5f137741a02912574377a48c6550f14
test ! -e "$dag"
docker run --rm -v "$bench:$bench" -w "$root" --entrypoint bash "$image" \
  "$code_root/experiments/webkit-thinlto/inspect-archives.sh" >archive-bitcode.log 2>&1

url=https://github.com/oven-sh/WebKit/releases/download/autobuild-5488984d20e0dbfe4be2c3ba8fb18eb81a5e0e8b/bun-webkit-linux-amd64-lto.tar.gz
key=$(printf %s "$url" | sha256sum | cut -c1-32)
mkdir -p prefetch-original/by-url prefetch-thin/by-url "$results" "$bin"
test -s original-webkit.tar.gz || curl --fail --location --retry 3 "$url" -o original-webkit.tar.gz
cp --reflink=auto original-webkit.tar.gz "prefetch-original/by-url/$key"
cp --reflink=auto bun-webkit-linux-amd64-lto.tar.gz "prefetch-thin/by-url/$key"
sha256sum original-webkit.tar.gz bun-webkit-linux-amd64-lto.tar.gz >"$results/input-archives.sha256"
cp "$code_root/scripts/run-zig-ci-dag.sh" "$bin/run-zig-ci-dag.sh"
cp "$code_root/scripts/local-buildkite-agent.sh" "$bin/buildkite-agent"
cp "$code_root/patches/zig-thinlto.patch" "$results/bun-thinlto.patch"
chmod +x "$bin/run-zig-ci-dag.sh" "$bin/buildkite-agent"
for part in cpp zig link; do
  git -C "$repo" worktree add --detach "$dag/$part" "$revision"
  # Match the existing reproductions' already-installed Zig toolchain.
  mkdir -p "$dag/$part/vendor"
  cp -a --reflink=auto "$bench/zig/vendor/zig" "$dag/$part/vendor/zig"
  if [[ $shards == 4 ]]; then
    git -C "$dag/$part" apply "$code_root/experiments/webkit-thinlto/zig-four-shards.patch"
  fi
done

variants=(full hybrid webkit-thin)
if [[ $shards == 4 ]]; then variants=(webkit-thin); fi
for variant in "${variants[@]}"; do
  if [[ $variant == hybrid || $shards == 4 ]]; then
    for part in cpp zig link; do
      git -C "$dag/$part" apply "$results/bun-thinlto.patch"
    done
  fi
  cache=$root/prefetch-original
  if [[ $variant == webkit-thin ]]; then cache=$root/prefetch-thin; fi
  run=$results/$variant
  mkdir "$run"
  mkdir "$run/artifacts"
  {
    echo "variant=$variant"
    echo "compiler_traces=false"
    echo "zig_shards=$shards"
    sha256sum "$dag/zig/vendor/zig/zig"
    cat "$dag/zig/vendor/zig/.zig-commit"
    sha256sum "$code_root/experiments/webkit-thinlto/record-comparison.sh" "$bin/run-zig-ci-dag.sh" "$bin/buildkite-agent"
    echo "bun_revision=$revision"
    echo "webkit_revision=5488984d20e0dbfe4be2c3ba8fb18eb81a5e0e8b"
    echo "image=$image"
    echo "started=$(date --iso-8601=seconds)"
    echo "prefetch=$cache"
    echo 'webkit_download=outside_timing; extraction=inside_timing'
    sha256sum "$cache/by-url/$key" "$recorder"
    git -C "$dag/cpp" diff
  } >"$run/manifest"
  docker run --rm --cap-add SYS_PTRACE --security-opt seccomp=unconfined \
    -v "$bench:$bench" -v "$repo:$repo:ro" -w "$bench" \
    -e CCACHE_DISABLE=1 -e BUN_BUILD_PREFETCH_DIR="$cache" \
    -e BUILDPROF_DAG_ROOT="$dag" \
    -e BUILDPROF_ARTIFACT_ROOT="$run/artifacts" \
    -e BUILDPROF_BUILD_DIR=build/webkit-experiment \
    -e BUILDPROF_ZIG_SHARDS="$shards" \
    -e PATH="$bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    --entrypoint "$recorder" "$image" \
    --no-open -o "$run/bun-zig-ci-$variant.buildprof" \
    -- "$bin/run-zig-ci-dag.sh" 2>&1 | tee "$run/build.log"
  echo "build_finished=$(date --iso-8601=seconds)" >>"$run/manifest"

  docker run --rm -v "$bench:$bench" -v "$repo:$repo:ro" \
    -w "$dag/link/build/webkit-experiment" --entrypoint bash "$image" \
    -c './bun-profile --revision && ./bun-profile -e '\''if ([1,2,3].map(x=>x*2).join() !== "2,4,6") throw Error("smoke"); console.log(new Intl.DateTimeFormat("en-US", {timeZone:"UTC"}).format(new Date(0))); console.log("smoke passed")'\'' && ninja -t commands bun-profile | tail -1' \
    >"$run/validation.log" 2>&1

  if [[ $variant == webkit-thin && ($shards == 1 || ${BUILDPROF_LINK_DETAIL:-0} == 1) ]]; then
    docker run --rm --cap-add SYS_PTRACE --security-opt seccomp=unconfined \
      -v "$bench:$bench" -v "$repo:$repo:ro" \
      -e BUILDPROF_EXPERIMENT_SUFFIX="$suffix" \
      -w "$dag/link/build/webkit-experiment" --entrypoint bash "$image" \
      "$code_root/experiments/webkit-thinlto/record-link-detail.sh" >"$run/link-detail.log" 2>&1
  fi

  if [[ $shards == 4 ]]; then
    docker run --rm -v "$bench:$bench" \
      -w "$dag/link/build/webkit-experiment" --entrypoint bash "$image" \
      "$code_root/experiments/webkit-thinlto/validate-shards.sh" >"$run/shard-validation.log" 2>&1
  fi

  docker run --rm -v "$bench:$bench" --entrypoint bash "$image" \
    -c 'cd "$1"; find cache/webkit-5488984d20e0dbfe-lto/lib -maxdepth 1 -name "*.a" -exec sha256sum {} +' \
    bash "$dag/link/build/webkit-experiment" >"$run/linked-archives.sha256"
  if [[ $variant == webkit-thin ]]; then
    # Fail before cleanup if the build silently consumed the old archives.
    awk '$2 ~ /\/(libWTF|libJavaScriptCore|libicudata|libicui18n|libicuuc|libbmalloc)\.a$/ {sub(/^.*\//, "", $2); print}' archives.sha256 | sort >"$run/expected-archives"
    awk '$2 ~ /\/(libWTF|libJavaScriptCore|libicudata|libicui18n|libicuuc|libbmalloc)\.a$/ {sub(/^.*\//, "", $2); print}' "$run/linked-archives.sha256" | sort >"$run/actual-archives"
    test "$(wc -l <"$run/actual-archives")" -eq 6
    diff -u "$run/expected-archives" "$run/actual-archives"
  fi
  sha256sum "$run"/*.buildprof >>"$run/manifest"
  echo "finished=$(date --iso-8601=seconds)" >>"$run/manifest"
  if [[ ${BUILDPROF_KEEP_OUTPUTS:-0} == 1 ]]; then
    touch "$run/done"
    continue
  fi
  # Only generated outputs from this isolated experiment are removed.
  docker run --rm -v "$root:$root" --entrypoint rm "$image" -rf -- \
    "$dag/cpp/build/webkit-experiment" \
    "$dag/zig/build/webkit-experiment" \
    "$dag/link/build/webkit-experiment" \
    "$run/artifacts"
  touch "$run/done"
done

#!/usr/bin/env bash
set -euo pipefail

: "${BUILDPROF_BIN:?BUILDPROF_BIN must be set}"
: "${BUILDPROF_OUTPUT:?BUILDPROF_OUTPUT must be set}"

target=${1:?usage: capture-bun-compiler-detail.sh NINJA_TARGET}
command=$(ninja -t commands "$target" | tail -1)

# Ninja materializes response files only while it executes an edge. For those
# commands, use a temporary copy of the graph and route its resolved clang++
# path through Buildprof without changing the original build.ninja.
if [[ $command == *'@bun-profile.rsp'* ]]; then
  trace_ninja=$(mktemp "${TMPDIR:-/tmp}/buildprof-ninja.XXXXXX")
  trap 'rm -f "$trace_ninja"' EXIT
  cp build.ninja "$trace_ninja"
  # The real --ld-path=ld.lld is inside the response file, which the wrapper
  # cannot inspect. Restate the same linker choice outside it so Buildprof
  # knows to inject LLD's --time-trace output.
  sed -i "s#/usr/lib/llvm-21/bin/clang++#clang++ -fuse-ld=lld#g" "$trace_ninja"
  ninja -f "$trace_ninja" -t clean "$target"
  "$BUILDPROF_BIN" --compiler-traces --no-open -o "$BUILDPROF_OUTPUT" \
    -- ninja -f "$trace_ninja" "$target"
  exit
fi

# Existing Ninja files contain the resolved compiler path and ccache prefix.
# Replay the generated command unchanged apart from routing clang++ through
# Buildprof's opt-in compiler wrapper so it can inject and import -ftime-trace.
command=${command/\/usr\/bin\/ccache \/usr\/lib\/llvm-21\/bin\/clang++/clang++}
command=${command/\/usr\/lib\/llvm-21\/bin\/clang++/clang++}

"$BUILDPROF_BIN" --compiler-traces --no-open -o "$BUILDPROF_OUTPUT" \
  -- bash -c "$command"

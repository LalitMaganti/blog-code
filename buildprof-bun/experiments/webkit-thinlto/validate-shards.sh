#!/usr/bin/env bash
set -euo pipefail
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
test ! -e bun-zig.o
for shard in bun-zig.0.o bun-zig.1.o bun-zig.2.o bun-zig.3.o; do
  test -s "$shard"
  sha256sum "$shard"
  llvm-bcanalyzer-21 "$shard" >"$scratch/bitcode"
  grep -Fq 'Block ID #20 (GLOBALVAL_SUMMARY_BLOCK)' "$scratch/bitcode"
  grep -F "$shard" build.ninja
done
echo 'Four ThinLTO objects present in the final-link checkout and Ninja graph.'

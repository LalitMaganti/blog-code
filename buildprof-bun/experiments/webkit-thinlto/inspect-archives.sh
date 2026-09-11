#!/usr/bin/env bash
set -euo pipefail
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
for library in JavaScriptCore WTF bmalloc icui18n icuuc; do
  archive=bun-webkit/lib/lib$library.a
  found=0
  llvm-ar-21 t "$archive" >"$scratch/members"
  while IFS= read -r member; do
    llvm-ar-21 p "$archive" "$member" >"$scratch/member.bc"
    if ! llvm-bcanalyzer-21 -dump "$scratch/member.bc" >"$scratch/dump" 2>/dev/null; then
      continue
    fi
    echo "archive=$archive member=$member"
    grep 'GLOBALVAL_SUMMARY_BLOCK' "$scratch/dump"
    grep -q '<GLOBALVAL_SUMMARY_BLOCK ' "$scratch/dump"
    llvm-dis-21 "$scratch/member.bc" -o "$scratch/member.ll"
    grep -E 'ThinLTO|EnableSplitLTOUnit' "$scratch/member.ll"
    found=1
    break
  done <"$scratch/members"
  test "$found" -eq 1
done
# ICU data is a native data-only object, not compiler bitcode.
llvm-ar-21 t bun-webkit/lib/libicudata.a

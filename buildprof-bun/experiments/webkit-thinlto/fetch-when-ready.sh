#!/usr/bin/env bash
set -euo pipefail
: "${BUILDPROF_NOTES_ROOT:?Set BUILDPROF_NOTES_ROOT to the build-trace notes directory}"
remote=/home/lalitm/bun-bench/webkit-thinlto-20260905
local_evidence=$BUILDPROF_NOTES_ROOT/evidence/webkit-thinlto-20260905
mkdir -p "$local_evidence"
while true; do
  if ssh -o BatchMode=yes -o ConnectTimeout=10 codey "test -f '$remote/r2-ready/READY'"; then break; fi
  if ssh -o BatchMode=yes -o ConnectTimeout=10 codey "test -f '$remote/package-r2.status' && ! grep -qx 'exit=0' '$remote/package-r2.status'"; then
    echo 'Remote packaging failed; inspect package-r2.log on codey.' >&2
    exit 1
  fi
  sleep 60
done
# Traces are already compressed. No transport recompression or remote writes.
rsync -a -e 'ssh -o BatchMode=yes -o ConnectTimeout=10' \
  "codey:$remote/r2-ready/" "$local_evidence/"
cd "$local_evidence/public/buildprof-bun/2026-09-05-webkit-thinlto"
shasum -a 256 -c SHA256SUMS
mkdir -p "$BUILDPROF_NOTES_ROOT/r2-upload/public/buildprof-bun"
rsync -a "$local_evidence/public/" "$BUILDPROF_NOTES_ROOT/r2-upload/public/"
cp "$local_evidence/links.md" "$BUILDPROF_NOTES_ROOT/r2-upload/webkit-thinlto-links.md"
printf 'Fetched, checksummed, and staged for R2. Nothing uploaded.\n' >"$local_evidence/FETCHED"

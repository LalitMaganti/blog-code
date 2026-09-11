#!/usr/bin/env bash
set -euo pipefail

: "${BUILDPROF_BIN:?BUILDPROF_BIN must be set}"
: "${BUILDPROF_OUTPUT:?BUILDPROF_OUTPUT must be set}"

destination=${1:?usage: capture-bun-cold-prebuilt.sh CACHE_DIRECTORY NINJA_TARGET}
target=${2:?usage: capture-bun-cold-prebuilt.sh CACHE_DIRECTORY NINJA_TARGET}

case "$destination" in
  "$PWD"/cache/*) ;;
  *)
    echo "refusing cache move outside $PWD/cache: $destination" >&2
    exit 2
    ;;
esac

backup_root=$(mktemp -d "$PWD/cache/.buildprof-cold-backup.XXXXXX")
backup="$backup_root/original"

restore() {
  if [[ -e $destination ]]; then
    rm -rf -- "$destination"
  fi
  if [[ -e $backup ]]; then
    mv -- "$backup" "$destination"
  fi
  rmdir "$backup_root" 2>/dev/null || true
}
trap restore EXIT INT TERM

if [[ -e $destination ]]; then
  mv -- "$destination" "$backup"
fi

"$BUILDPROF_BIN" --no-open -o "$BUILDPROF_OUTPUT" -- ninja "$target"

#!/usr/bin/env bash
set -euo pipefail
root=/home/lalitm/bun-bench/webkit-thinlto-20260905
scripts=$(cd -- "$(dirname -- "$0")" && pwd)
exec >>"$root/package-r2.log" 2>&1
write_exit_status() {
  local result=$?
  printf "exit=%s\n" "$result" >"$root/package-r2.status"
}
trap write_exit_status EXIT
while systemctl --user is-active --quiet bun-webkit-process-only-20260905.service; do
  sleep 30
done
node "$scripts/package-r2.mjs"

#!/usr/bin/env bash
set -euo pipefail

root=${1:-/home/lalitm/bun-bench/original-traces}
tp=${TRACE_PROCESSOR:-/home/lalitm/.local/share/perfetto/prebuilts/trace_processor_shell}

find "$root" -name '*.buildprof' -print0 | sort -z | while IFS= read -r -d '' trace; do
  output=$("$tp" query "$trace" "select printf('%.3f', (end_ts-start_ts)/1e9) as seconds from trace_bounds" 2>/dev/null)
  seconds=$(printf '%s\n' "$output" | tail -1 | tr -d '"\r')
  printf '%s\t%s\n' "${trace#"$root"/}" "$seconds"
done

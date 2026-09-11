#!/usr/bin/env bash
set -euo pipefail
recipe=$(cd -- "$(dirname -- "$0")" && pwd)
experiment=/home/lalitm/bun-bench/webkit-thinlto-20260905
source_dir=/home/lalitm/bun-bench/webkit-5488984d
revision=5488984d20e0dbfe4be2c3ba8fb18eb81a5e0e8b
cd "$experiment"
exec > >(tee -a build.log) 2>&1
write_exit_status() {
  local result=$?
  printf "exit=%s\nfinished=%s\n" "$result" "$(date --iso-8601=seconds)" >build.status
}
trap write_exit_status EXIT
test "$(git -C "$source_dir" rev-parse HEAD)" = "$revision"
test -z "$(git -C "$source_dir" status --porcelain)"
printf 'revision=%s\nstarted=%s\n' "$revision" "$(date --iso-8601=seconds)" >build.manifest
sha256sum "$recipe/Dockerfile" "$recipe/build-webkit.sh" >>build.manifest
docker buildx build --progress=plain --platform=linux/amd64 \
  --build-arg 'LTO_FLAG=-flto=thin -fwhole-program-vtables -fforce-emit-vtables -fsplit-lto-unit' \
  --build-arg 'MARCH_FLAG=-march=haswell' \
  --build-arg 'RELEASE_FLAGS=-O3 -DNDEBUG=1' \
  --build-arg WEBKIT_RELEASE_TYPE=Release \
  --target artifact --output "type=local,dest=$experiment/bun-webkit" \
  -f "$recipe/Dockerfile" "$source_dir"
printf '#define BUN_WEBKIT_VERSION "%s"\n' "$revision" >>bun-webkit/include/cmakeconfig.h
printf '{"name":"bun-webkit-linux-amd64-lto","version":"0.0.1-%s","os":["linux"],"cpu":["x64"]}\n' "$revision" >bun-webkit/package.json
find bun-webkit/lib -maxdepth 1 -type f -name '*.a' -exec sha256sum {} + >archives.sha256
tar -czf bun-webkit-linux-amd64-lto.tar.gz bun-webkit
sha256sum bun-webkit-linux-amd64-lto.tar.gz >>build.manifest

import { readFile, writeFile, mkdir, copyFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";

const root = "/home/lalitm/bun-bench/webkit-thinlto-20260905";
const shardDetail = process.argv.includes("--shards4-link-detail");
const sharded = shardDetail || process.argv.includes("--shards4");
const suffix = shardDetail
  ? "shards4-link-detail"
  : sharded
    ? "shards4"
    : "process-only";
const bundle = `${root}/r2-ready${sharded ? `-${suffix}` : ""}`;
const status = await readFile(`${root}/comparison-${suffix}.status`, "utf8");
if (!/^exit=0$/m.test(status))
  throw Error("Comparison has not completed successfully");
const prefix = shardDetail
  ? "buildprof-bun/2026-09-06-shards4-link-detail"
  : `buildprof-bun/2026-09-05-webkit-thinlto${sharded ? "-shards4" : ""}`;
const output = `${bundle}/public/${prefix}`;
const evidence = `${bundle}/evidence`;
await mkdir(output, { recursive: true });
await mkdir(evidence, { recursive: true });
const recordings = [];
for (const variant of sharded
  ? ["webkit-thin"]
  : ["full", "hybrid", "webkit-thin"]) {
  const source = `${root}/results-${suffix}/${variant}`;
  await readFile(`${source}/done`);
  const manifest = await readFile(`${source}/manifest`, "utf8");
  if (!manifest.includes("compiler_traces=false"))
    throw Error("Instrumented comparison");
  const names = [`bun-zig-ci-${variant}`];
  if (variant === "webkit-thin" && (!sharded || shardDetail))
    names.push("bun-zig-webkit-thin-link-detail");
  for (const name of names) {
    const bytes = await readFile(`${source}/${name}.buildprof`);
    const sha256 = createHash("sha256").update(bytes).digest("hex");
    if (
      !manifest
        .split("\n")
        .some(
          (line) =>
            line.startsWith(`${sha256}  `) &&
            line.endsWith(`/${name}.buildprof`),
        )
    ) {
      throw Error(`Manifest checksum mismatch: ${name}`);
    }
    if (bytes.subarray(0, 4).toString("hex") !== "28b52ffd")
      throw Error("Unexpected trace format");
    const filename = `${name}-${sha256.slice(0, 16)}.buildprof`;
    await copyFile(`${source}/${name}.buildprof`, `${output}/${filename}`);
    recordings.push({
      name,
      variant,
      zigShards: sharded ? 4 : 1,
      key: `${prefix}/${filename}`,
      bytes: bytes.length,
      sha256,
      compilerTraces: name.endsWith("link-detail"),
    });
  }
  for (const file of ["manifest", "validation.log", "linked-archives.sha256"]) {
    await copyFile(`${source}/${file}`, `${evidence}/${variant}-${file}`);
  }
  if (sharded)
    await copyFile(
      `${source}/shard-validation.log`,
      `${evidence}/shard-validation.log`,
    );
  if (shardDetail) {
    await copyFile(`${source}/final-link.rsp`, `${evidence}/final-link.rsp`);
    await copyFile(`${source}/link-detail.log`, `${evidence}/link-detail.log`);
  }
}
await writeFile(
  `${output}/index.json`,
  JSON.stringify(
    { recorderVersion: "0.2.0", viewerVersion: "0.2.2", recordings },
    null,
    2,
  ) + "\n",
);
await writeFile(
  `${output}/SHA256SUMS`,
  recordings.map((r) => `${r.sha256}  ${path.basename(r.key)}`).join("\n") +
    "\n",
);
await writeFile(
  `${bundle}/links.md`,
  "# Trace links (after upload)\n\n" +
    recordings
      .map((r) => {
        const url = `https://blogexamples.lalitm.com/${r.key}`;
        return `- ${r.name} (${(r.bytes / 1e6).toFixed(1)} MB): [Open in buildprof](https://buildprof.lalitm.com/v0.2.2/#!/?url=${encodeURIComponent(url)}) · [Download](${url})`;
      })
      .join("\n") +
    "\n",
);
await writeFile(
  `${bundle}/READY`,
  "Checksums verified. Upload public/ only.\n",
);
console.log(`Prepared ${recordings.length} traces for R2; nothing uploaded.`);

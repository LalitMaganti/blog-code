#!/usr/bin/env python3
"""Release-binary comparison: baseline, --no-file-events, default recording."""

import hashlib
import json
import os
import random
import subprocess
import time
from pathlib import Path

base = Path("/home/lalitm/bun-bench/overhead-20260909")
root = base / "collection-options"
root.mkdir(exist_ok=True)
source = Path("/home/lalitm/bun-bench/collection-controls-20260909")
env = dict(
    os.environ,
    PATH="/home/lalitm/.cargo/bin:/usr/local/bin:/usr/bin:/bin",
    CCACHE_DISABLE="1",
    CARGO_INCREMENTAL="0",
)
env.pop("RUSTC_WRAPPER", None)
env.pop("RUSTC_WORKSPACE_WRAPPER", None)
with (root / "compile.log").open("w") as log:
    subprocess.run(
        ["cargo", "build", "--release", "--locked"],
        cwd=source,
        env=env,
        stdout=log,
        stderr=subprocess.STDOUT,
        check=True,
    )
recorder = source / "target/release/buildprof"
manifest = json.loads((base / "manifest.json").read_text())
manifest.update(
    recorded_at=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    recorder_source_commit="67782c8",
    recorder_sha256=hashlib.sha256(recorder.read_bytes()).hexdigest(),
    pairs=None,
    repeats=5,
    seed=20260910,
    method=(
        "Five randomized rounds of three modes per project after one "
        "unmeasured warmup. Clean outputs before every run, warm caches and "
        "downloads, six jobs, ccache and Cargo incremental compilation "
        "disabled. Wall time includes trace writing. Compiler traces "
        "disabled. Release build of collection-controls implementation, no "
        "diagnostic instrumentation."
    ),
)
(root / "manifest.json").write_text(json.dumps(manifest, indent=2))
results = []
for project in ["ripgrep", "redis"]:
    cwd = base / project
    if project == "ripgrep":
        env["CARGO_TARGET_DIR"] = str(base / "ripgrep-target")
        clean = ["cargo", "clean"]
        command = ["cargo", "build", "--release", "--locked", "--offline", "-j6"]
    else:
        env.pop("CARGO_TARGET_DIR", None)
        clean = ["make", "distclean"]
        command = ["make", "-j6", "MALLOC=libc", "BUILD_TLS=no"]
    schedule = [(-1, "warmup")]
    rng = random.Random(20260910)
    for repeat in range(5):
        modes = ["untraced", "process-only", "filesystem"]
        rng.shuffle(modes)
        schedule.extend((repeat, mode) for mode in modes)
    for repeat, mode in schedule:
        prefix = f"{project}-{repeat}-{mode}"
        with (root / (prefix + ".log")).open("w") as log:
            subprocess.run(
                clean,
                cwd=cwd,
                env=env,
                stdout=log,
                stderr=subprocess.STDOUT,
                check=True,
            )
            args = command
            if mode in ["process-only", "filesystem"]:
                args = (
                    [
                        str(recorder),
                        "--no-open",
                        "-o",
                        str(root / (prefix + ".buildprof")),
                    ]
                    + (["--no-file-events"] if mode == "process-only" else [])
                    + ["--"]
                    + command
                )
            print("START", prefix, flush=True)
            start = time.perf_counter()
            proc = subprocess.run(
                args, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT
            )
            result = {
                "project": project,
                "repeat": repeat,
                "mode": mode,
                "seconds": time.perf_counter() - start,
                "exit_code": proc.returncode,
                "command": args,
            }
            results.append(result)
            (root / "results.json").write_text(json.dumps(results, indent=2))
            print("DONE", result, flush=True)
            if proc.returncode:
                raise SystemExit(proc.returncode)
(root / "complete").write_text("ok\n")

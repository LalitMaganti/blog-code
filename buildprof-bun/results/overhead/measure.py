#!/usr/bin/env python3
"""Five randomized pairs of clean builds; warm downloads and OS caches.
Run on Codey. Uses dedicated copies and targets, never cleans source checkouts.
"""

import hashlib
import json
import os
import platform
import random
import subprocess
import time
from pathlib import Path

root = Path("/home/lalitm/bun-bench/overhead-20260909")
root.mkdir(exist_ok=True)
recorder = Path("/home/lalitm/depot/projects/buildprof/target/release/buildprof")
env = dict(os.environ, CCACHE_DISABLE="1", CARGO_INCREMENTAL="0")
env["PATH"] = "/home/lalitm/.cargo/bin:/usr/local/bin:/usr/bin:/bin"
env.pop("RUSTC_WRAPPER", None)
env.pop("RUSTC_WORKSPACE_WRAPPER", None)


def output(args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, env=env, text=True).strip()


projects = []
for name in ["ripgrep", "redis"]:
    source = Path("/home/lalitm/bt-matrix") / name
    dest = root / name
    if not dest.exists():
        dest.mkdir()
        archive = subprocess.Popen(
            ["git", "archive", "HEAD"], cwd=source, stdout=subprocess.PIPE
        )
        subprocess.run(["tar", "-x", "-C", str(dest)], stdin=archive.stdout, check=True)
        assert archive.stdout is not None
        archive.stdout.close()
        assert archive.wait() == 0
    projects.append(
        {
            "name": name,
            "cwd": str(dest),
            "commit": output(["git", "rev-parse", "HEAD"], source),
        }
    )
manifest = {
    "recorded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "platform": platform.platform(),
    "cpu": output(["lscpu"]),
    "recorder_version": output([str(recorder), "--version"]),
    "recorder_sha256": hashlib.sha256(recorder.read_bytes()).hexdigest(),
    "recorder_source_commit": output(
        ["git", "rev-parse", "HEAD"], "/home/lalitm/depot/projects/buildprof"
    ),
    "cargo": output(["cargo", "--version"]),
    "cc": output(["cc", "--version"]),
    "projects": projects,
    "pairs": 5,
    "seed": 20260909,
    "method": (
        "one unmeasured warm-up per project, then five randomized "
        "baseline/recorded pairs; clean outside timer; wall clock includes "
        "trace serialization; -j6; downloads and filesystem caches warm; "
        "ccache and incremental compilation disabled; no compiler tracing"
    ),
}
(root / "manifest.json").write_text(json.dumps(manifest, indent=2))
results = []
for project in projects:
    name = project["name"]
    cwd = Path(project["cwd"])
    if name == "ripgrep":
        env["CARGO_TARGET_DIR"] = str(root / "ripgrep-target")
        subprocess.run(["cargo", "fetch", "--locked"], cwd=cwd, env=env, check=True)
        clean = ["cargo", "clean"]
        command = ["cargo", "build", "--release", "--locked", "--offline", "-j6"]
    else:
        env.pop("CARGO_TARGET_DIR", None)
        clean = ["make", "distclean"]
        command = ["make", "-j6", "MALLOC=libc", "BUILD_TLS=no"]
    rng = random.Random(20260909)
    schedule = [(-1, "warmup")]
    for pair in range(5):
        modes = ["baseline", "recorded"]
        rng.shuffle(modes)
        schedule.extend((pair, mode) for mode in modes)
    for pair, mode in schedule:
        prefix = f"{name}-{pair}-{mode}"
        with (root / (prefix + ".log")).open("w") as log:
            subprocess.run(
                clean,
                cwd=cwd,
                env=env,
                stdout=log,
                stderr=subprocess.STDOUT,
                check=True,
            )
            trace = root / (prefix + ".buildprof")
            args = (
                [str(recorder), "--no-open", "-o", str(trace), "--"]
                if mode == "recorded"
                else []
            ) + command
            print("START", prefix, flush=True)
            load = os.getloadavg()
            start = time.perf_counter()
            proc = subprocess.run(
                args, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT
            )
            elapsed = time.perf_counter() - start
            result = {
                "project": name,
                "pair": pair,
                "mode": mode,
                "seconds": elapsed,
                "exit_code": proc.returncode,
                "command": args,
                "load_before": load,
                "trace_bytes": trace.stat().st_size if trace.exists() else None,
            }
            results.append(result)
            (root / "results.json").write_text(json.dumps(results, indent=2))
            print(
                "DONE", prefix, round(elapsed, 3), "exit", proc.returncode, flush=True
            )
            if proc.returncode:
                raise SystemExit(proc.returncode)
(root / "complete").write_text("ok\n")

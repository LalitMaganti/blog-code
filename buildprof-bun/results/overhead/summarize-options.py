#!/usr/bin/env python3
import json
import statistics
from pathlib import Path

root = Path(__file__).resolve().parent / "collection-options"
rows = json.loads((root / "results.json").read_text())
assert all(r["exit_code"] == 0 for r in rows)
short = [
    "| Build | Untraced | Processes only | Processes + files |",
    "| --- | ---: | ---: | ---: |",
]
long = [
    "# Collection-option overhead",
    "",
    (
        "Release build of the implementation at `67782c8`, with no diagnostic "
        "instrumentation. Five randomized rounds per project, each containing "
        "an untraced build, a process-only recording (`--no-file-events`), "
        "and a default recording. One unmeasured warm-up precedes each "
        "project. Clean outputs before every run; OS caches and downloads "
        "warm; six jobs; ccache and Cargo incremental compilation disabled; "
        "compiler traces disabled. Wall time includes recording and writing "
        "the trace."
    ),
    "",
    "| Build | Mode | Median | Range | Increase vs untraced median |",
    "| --- | --- | ---: | ---: | ---: |",
]
for project, label in [("ripgrep", "ripgrep / Cargo"), ("redis", "Redis / Make")]:
    groups = {
        m: [r["seconds"] for r in rows if r["project"] == project and r["mode"] == m]
        for m in ["untraced", "process-only", "filesystem"]
    }
    assert all(len(v) == 5 for v in groups.values()), "Incomplete measurements"
    medians = {m: statistics.median(v) for m, v in groups.items()}
    short.append(
        "| " + label + " | " + " | ".join(f"{medians[m]:.2f}s" for m in groups) + " |"
    )
    for mode, values in groups.items():
        long.append(
            f"| {label} | {mode} | {medians[mode]:.3f}s | "
            f"{min(values):.3f}–{max(values):.3f}s | "
            f"{(medians[mode] / medians['untraced'] - 1) * 100:.2f}% |"
        )
long += [
    "",
    "## Article table",
    "",
    *short,
    "",
    (
        "These are results for these workloads on this machine, not overhead "
        "bounds. Small differences within run-to-run variation should not be "
        "interpreted as precise speedups or slowdowns. `manifest.json` "
        "preserves machine/toolchain/revision details and the release binary "
        "hash; `results.json` preserves every command and timing."
    ),
    "",
]
(root / "timings.md").write_text("\n".join(long))
(root / "article-table.md").write_text("\n".join(short) + "\n")
print("\n".join(short))

# Radix-sort benchmarks

## Run the harness

Requires Python 3, Make and Clang on macOS or Linux.

```sh
python3 setup.py
make -j3
make smoke
./build/study --synthetic > synthetic.txt
```

`setup.py` downloads pinned upstream dependencies; [SOURCES.md](SOURCES.md) lists revisions and adapter differences. The harness checks key order, row permutation and stable tie order where applicable; incorrect output prints `!` and exits nonzero.

Real-column key files are not included. Supply a directory of `.u64` files containing consecutive little-endian unsigned 64-bit keys, in original row order:

```sh
./build/study --real /path/to/keys > real.txt
```

This also runs 4,096- and 65,536-row samples where available. Exact reproduction of the recorded trace results requires the original key files.

## Inspect the results

[Complete comparison tables](comparisons.md) include all 72 inputs and ten variants on each machine.

```sh
python3 report.py mac.txt x86.txt > comparisons.md
python3 occupancy.py /path/to/keys/*.u64
```

| Raw column | Approach |
|---|---|
| `comparison` | Standard comparison sort |
| `ours16` | Fixed 16-bit LSD |
| `ours` | Perfetto adaptive |
| `fixed8`, `msd8` | 8-bit LSD and MSD |
| `lsd11`, `wc11` | 11-bit LSD, without and with write buffers |
| `clickhouse` | ClickHouse numeric permutation path |
| `duckdb` | DuckDB without compression |
| `duck_comp` | DuckDB with compression |

## Diagnostic programs

```sh
make diagnostics
./build/test_cost_model
```

`test_ch_breakdown` and `test_duck_verge` expect `keys/chrome_slice_name.u64` and `keys/example_sched_ts_by_cpu.u64` respectively. They reproduce the separate key-width and existing-order investigations below. `occupancy.py` reports active buckets and the smallest group receiving 90% of writes for each 16-bit pass.

## Main comparison

Raw output: [Apple Silicon](mac.txt), [Intel Ice Lake VM](x86.txt). Raw times are microseconds; `duck_comp` is the compressed DuckDB variant used in the post.

| Setup | Value |
|---|---|
| Inputs per machine | 16 full trace columns; two smaller samples per column; 24 synthetic inputs |
| Variants | 10 |
| Record | 8-byte key + 8-byte row reference |
| Execution | One thread; contiguous records; common input prepared before timing |
| Key preparation | Shared upper bytes cleared for all variants |
| Repetitions | One warm-up; 5 measured for large inputs, 12 for small; best time |
| DuckDB compression | Bounds precomputed; compression, sorting, restoration timed; null marker skipped |
| Allocation | Adapter allocations included |
| Verification | Key order and row permutation; stable variants also check ties; all passed |
| Build | clang++ -O3 -std=c++17 -falign-functions=64; ClickHouse adapter C++20 |
| Scope | Extracted sorting cores; excludes SQL execution, parallel merges, paged iterators |

Geometric mean time relative to Perfetto, across full trace columns:

| Approach | Laptop / Perfetto | Server / Perfetto |
|---|---:|---:|
| Perfetto adaptive | 1.000 | 1.000 |
| ClickHouse sorting core | 3.183 | 3.069 |
| DuckDB sorting core, compressed keys | 2.874 | 2.043 |
| 8-bit LSD | 1.716 | 1.455 |
| 8-bit MSD | 3.169 | 3.591 |
| 11-bit LSD | 1.456 | 1.348 |
| Buffered 11-bit LSD | 2.654 | 1.581 |
| Standard comparison sort | 9.786 | 8.221 |

## Earlier diagnostic measurements

Separate experiments; these are not results from the main rerun.

### ClickHouse key width

Slice-name IDs: 409,977 rows, keys fit in 16 bits.

| Path | Time |
|---|---:|
| Speculative trySort | <1 µs |
| UInt64 radix sort, 8 passes | 8.08 ms |
| UInt16 radix sort, 2 passes | 1.83 ms |
| Perfetto adaptive, 1 pass | 0.50 ms |

### DuckDB existing order

| Input | Rows | Ascending runs | Mean run length |
|---|---:|---:|---:|
| example_sched_ts_by_cpu | 384,623 | 8 | 48,078 |
| chrome_slice_dur | — | 252,520 | 1.6 |

| First 4,096 scheduling timestamps | Time |
|---|---:|
| Original order | 8.2 µs |
| Original order, warm cache | 1.1 µs |
| Shuffled | 131.0 µs |

### First-pass bucket occupancy, 16-bit digits

| Column | Rows | Buckets touched | Buckets receiving 90% of rows |
|---|---:|---:|---:|
| heap_obj_self_size | 1,306,442 | 1,401 | 26 |
| heap_ref_field | 5,868,134 | 43,449 | 164 |
| chrome_slice_name | 409,977 | 1,140 | 154 |
| sched_ps_sched_utid | 221,809 | 809 | 124 |

### Bucket bookkeeping, Apple Silicon

| Operation | Time |
|---|---:|
| Clear 65,536 32-bit counts | 2.04 µs |
| Prefix sum | 36.50 µs |
| Total | 38.54 µs |

| Rows | Record movement |
|---:|---:|
| 1,024 | 0.38 µs |
| 4,096 | 1.54 µs |
| 16,384 | 7.67 µs |
| 65,536 | 25.96 µs |

Width heuristic: minimize `passes × (4 × rows + buckets)` in relative cost units, not nanoseconds.

### Synthetic inputs

4,194,304 unsigned 64-bit keys. Random: fixed-seed generator. Golden-ratio: successive row numbers multiplied by an odd constant modulo the 64-bit range.

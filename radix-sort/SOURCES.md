# Upstream dependencies

`setup.py` downloads these immutable revisions into ignored `deps/`, including their license files. No upstream source is checked into this example. `deps/manifest.json` records each URL and SHA-256 digest.

| Project | Revision | Files |
|---|---|---|
| [Perfetto](https://github.com/google/perfetto/tree/4a4addaf0240460387d9f923d4f14796e52cffa9) | `4a4addaf0240460387d9f923d4f14796e52cffa9` | Sort header and supporting public headers |
| [ClickHouse](https://github.com/ClickHouse/ClickHouse/tree/207ee2ca2206f406faafa69c435c663318080547) | `207ee2ca2206f406faafa69c435c663318080547` | RadixSort, RadixSortHelper, pdqsort |
| [DuckDB 1.4.0](https://github.com/duckdb/duckdb/tree/b8a06e4a22672e254cd0baa68a3dbed2eb51c56e) | `b8a06e4a22672e254cd0baa68a3dbed2eb51c56e` | ska_sort, pdqsort, vergesort and detail headers |

The downloaded sorting implementations match the local snapshots used for the recorded rerun. The ClickHouse SHA identifies matching file contents; the original scratchpad did not record its checkout revision.

`support/` contains standalone compatibility definitions: ClickHouse integer aliases, allocator and sort wrappers, DuckDB numeric-cast helpers, and Perfetto build flags. They omit database memory tracking, interrupt checks, debug shuffling and multitarget dispatch. The adapters benchmark extracted sorting paths, not complete database execution.

Changes to the driver after the recorded run: clearer file errors, nonzero exit on incorrect output, and a smaller `--smoke` input set. The measured sorting routines and full synthetic generation are unchanged.

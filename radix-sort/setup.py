#!/usr/bin/env python3
"""Download pinned upstream dependencies; keep them outside version control."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parent
PINS = {
    'clickhouse': ('ClickHouse/ClickHouse', '207ee2ca2206f406faafa69c435c663318080547'),
    'duckdb': ('duckdb/duckdb', 'b8a06e4a22672e254cd0baa68a3dbed2eb51c56e'),
    'perfetto': ('google/perfetto', '4a4addaf0240460387d9f923d4f14796e52cffa9'),
}
FILES = [
    ('clickhouse', 'src/Common/RadixSort.h', 'ch/Common/RadixSort.h'),
    ('clickhouse', 'src/Columns/RadixSortHelper.h', 'ch/Columns/RadixSortHelper.h'),
    ('clickhouse', 'contrib/pdqsort/pdqsort.h', 'ch/pdqsort.h'),
    ('clickhouse', 'LICENSE', 'licenses/ClickHouse-APACHE.txt'),
    ('clickhouse', 'contrib/pdqsort/license.txt', 'licenses/ClickHouse-pdqsort.txt'),
    ('duckdb', 'third_party/ska_sort/ska_sort.hpp', 'duck/ska_sort.hpp'),
    ('duckdb', 'third_party/pdqsort/pdqsort.h', 'duck/pdqsort.h'),
    ('duckdb', 'third_party/vergesort/vergesort.h', 'duck/vergesort.h'),
    ('duckdb', 'third_party/ska_sort/LICENSE', 'licenses/ska-sort.txt'),
    ('duckdb', 'third_party/pdqsort/LICENSE', 'licenses/DuckDB-pdqsort.txt'),
    ('duckdb', 'third_party/vergesort/LICENSE', 'licenses/vergesort.txt'),
    ('perfetto', 'src/trace_processor/core/util/sort.h', 'perfetto/src/trace_processor/core/util/sort.h'),
    ('perfetto', 'include/perfetto/ext/base/bits.h', 'perfetto/include/perfetto/ext/base/bits.h'),
    ('perfetto', 'include/perfetto/base/build_config.h', 'perfetto/include/perfetto/base/build_config.h'),
    ('perfetto', 'include/perfetto/base/compiler.h', 'perfetto/include/perfetto/base/compiler.h'),
    ('perfetto', 'include/perfetto/public/compiler.h', 'perfetto/include/perfetto/public/compiler.h'),
    ('perfetto', 'LICENSE', 'licenses/Perfetto-APACHE.txt'),
]
FILES += [('duckdb', 'third_party/vergesort/detail/' + name, 'duck/detail/' + name)
          for name in ['insertion_sort.h', 'is_sorted_until.h', 'iter_sort3.h', 'log2.h', 'prevnext.h', 'quicksort.h']]

def download(entry):
    project, source, target = entry
    repo, revision = PINS[project]
    url = f'https://raw.githubusercontent.com/{repo}/{revision}/{source}'
    request = urllib.request.Request(url, headers={'User-Agent': 'radix-blog-benchmark'})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read()
    destination = ROOT / 'deps' / target
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)
    return {'file': target, 'url': url, 'sha256': hashlib.sha256(data).hexdigest()}

if __name__ == '__main__':
    with ThreadPoolExecutor(max_workers=6) as pool:
        manifest = list(pool.map(download, FILES))
    (ROOT / 'deps' / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Downloaded {len(manifest)} pinned files into deps/.')

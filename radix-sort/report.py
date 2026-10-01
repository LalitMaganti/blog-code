#!/usr/bin/env python3
"""Render complete raw comparisons and the post's aggregate ratios as Markdown."""
import argparse
import math
from pathlib import Path

LABELS = {
    'comparison': 'Comparison sort', 'ours16': 'Fixed 16-bit LSD',
    'ours': 'Perfetto adaptive', 'fixed8': '8-bit LSD', 'msd8': '8-bit MSD',
    'lsd11': '11-bit LSD', 'wc11': 'Buffered 11-bit LSD',
    'clickhouse': 'ClickHouse', 'duckdb': 'DuckDB uncompressed',
    'duck_comp': 'DuckDB compressed',
}

def load(path):
    lines = path.read_text().splitlines()
    columns = lines[0].split()[3:13]
    assert len(columns) == 10 and set(columns) == set(LABELS), path
    rows = []
    for line in lines[1:]:
        fields = line.split()
        if not fields:
            continue
        if '!' in line:
            raise ValueError(f'Correctness failure: {path}: {line}')
        if len(fields) != 13:
            raise ValueError(f'Malformed row: {path}: {line}')
        rows.append((fields[0], int(fields[1]), int(fields[2]), dict(zip(columns, map(float, fields[3:])))))
    return columns, rows

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', nargs='+', type=Path)
    args = parser.parse_args()
    print('# Complete radix-sort comparisons\n\nTimes are milliseconds, converted from raw microseconds.\n')
    for path in args.files:
        columns, rows = load(path)
        print(f'## {path.name}\n')
        full = [r for r in rows if '/' not in r[0]]
        if full:
            print('Geometric mean time relative to Perfetto, full trace columns:\n')
            print('| Approach | Relative time |\n|---|---:|')
            for col in columns:
                ratio = math.exp(sum(math.log(r[3][col] / r[3]['ours']) for r in full) / len(full))
                print(f'| {LABELS[col]} | {ratio:.3f}× |')
            print()
        print('| Dataset | Rows | Key bits | ' + ' | '.join(LABELS[c] for c in columns) + ' |')
        print('|---|---:|---:|' + '---:|' * len(columns))
        for name, count, bits, values in rows:
            print(f'| {name} | {count:,} | {bits} | ' + ' | '.join(f'{values[c] / 1000:.4f}' for c in columns) + ' |')
        if path != args.files[-1]:
            print()

#!/usr/bin/env python3
"""Count active and hot buckets for each 16-bit pass on .u64 key files."""
import argparse
from array import array
from pathlib import Path
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('files', nargs='+', type=Path)
args = parser.parse_args()
print('| Column | Rows | Pass | Buckets touched | Buckets receiving 90% |\n|---|---:|---:|---:|---:|')
for path in args.files:
    data = path.read_bytes()
    if not data or len(data) % 8:
        raise ValueError(f'{path}: expected nonempty little-endian uint64 values')
    keys = array('Q'); keys.frombytes(data)
    if sys.byteorder != 'little':
        keys.byteswap()
    diff = 0
    for key in keys:
        diff |= key ^ keys[0]
    bits = ((diff.bit_length() + 7) // 8) * 8
    for pass_number in range((bits + 15) // 16):
        counts = [0] * 65536
        for key in keys:
            counts[(key >> (pass_number * 16)) & 65535] += 1
        touched = sum(c > 0 for c in counts)
        total = hot = 0
        for c in sorted(counts, reverse=True):
            total += c; hot += 1
            if total * 10 >= len(keys) * 9:
                break
        print(f'| {path.stem} | {len(keys):,} | {pass_number} | {touched:,} | {hot:,} |')

#!/usr/bin/env python3
"""Losslessly recompress PNG IDAT only; preserve every other chunk and scanline byte."""
import argparse
import struct
import zlib
from pathlib import Path


def optimize(path):
    original = path.read_bytes()
    if original[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError(f'Invalid PNG: {path}')
    chunks, offset = [], 8
    while offset < len(original):
        size = struct.unpack('>I', original[offset:offset + 4])[0]
        kind = original[offset + 4:offset + 8]
        payload = original[offset + 8:offset + 8 + size]
        chunk = original[offset:offset + size + 12]
        if len(chunk) != size + 12 or zlib.crc32(kind + payload) != struct.unpack('>I', chunk[-4:])[0]:
            raise ValueError(f'Invalid chunk: {path}')
        chunks.append((kind, payload, chunk))
        offset += size + 12
    compressed = b''.join(data for kind, data, _ in chunks if kind == b'IDAT')
    scanlines = zlib.decompress(compressed)
    candidates = [compressed]
    for strategy in (zlib.Z_DEFAULT_STRATEGY, zlib.Z_FILTERED, zlib.Z_RLE):
        compressor = zlib.compressobj(9, zlib.DEFLATED, 15, 9, strategy)
        candidates.append(compressor.compress(scanlines) + compressor.flush())
    best = min(candidates, key=len)
    if zlib.decompress(best) != scanlines:
        raise ValueError(f'Pixel data changed: {path}')
    result, written = original[:8], False
    for kind, _, chunk in chunks:
        if kind != b'IDAT':
            result += chunk
        elif not written:
            result += struct.pack('>I', len(best)) + b'IDAT' + best + struct.pack('>I', zlib.crc32(b'IDAT' + best))
            written = True
    if len(result) < len(original):
        path.write_bytes(result)
    return len(original), min(len(original), len(result))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    before = after = 0
    for path in sorted(args.directory.rglob('*.png')):
        a, b = optimize(path)
        before += a
        after += b
        print(f'{path.name}: {a} -> {b} bytes, scanlines unchanged')
    print(f'Total: {before} -> {after} bytes; saved {before-after} bytes')

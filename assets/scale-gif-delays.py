#!/usr/bin/env python3
"""Scale every frame delay in a GIF by a factor, without re-encoding.

Walks the GIF block structure, finds Graphics Control Extensions, and
multiplies each delay (centiseconds) by SCALE. Everything else passes
through byte-for-byte, so the file keeps its original palette and size.
"""
import struct
import sys

SCALE = 4 / 3  # 0.75x speed


def main(src, dst):
    data = open(src, "rb").read()
    out = bytearray(data)
    pos = 13  # header(6) + logical screen descriptor(7)

    # skip global color table if present
    packed = data[10]
    if packed & 0x80:
        pos += 3 * (2 << (packed & 0x07))

    changed = 0
    error = 0.0  # carries centisecond rounding remainder between frames
    while pos < len(out):
        block = out[pos]
        if block == 0x3B:  # trailer
            break
        if block == 0x21:  # extension
            label = out[pos + 1]
            sub = pos + 2
            if label == 0xF9:  # graphic control extension
                size = out[sub]
                flags, lo, hi, _transparent = out[sub + 1 : sub + 5]
                delay = lo | (hi << 8)
                exact = delay * SCALE + error
                new_delay = min(round(exact), 0xFFFF)
                error = exact - new_delay
                out[sub + 2] = new_delay & 0xFF
                out[sub + 3] = (new_delay >> 8) & 0xFF
                changed += 1
                pos = sub + 1 + size + 1
            else:
                pos = sub
                while out[pos] != 0:
                    pos += out[pos] + 1
                pos += 1
        elif block == 0x2C:  # image descriptor
            packed_image = out[pos + 9]
            pos += 10
            if packed_image & 0x80:
                pos += 3 * (2 << (packed_image & 0x07))
            pos += 1  # LZW minimum code size
            while out[pos] != 0:
                pos += out[pos] + 1
            pos += 1
        else:
            raise SystemExit(f"unknown block 0x{block:02x} at {pos}")

    open(dst, "wb").write(bytes(out))
    print(f"scaled {changed} frame delays by {SCALE:.3f}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

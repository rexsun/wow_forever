"""Convert a square RGBA image into a BLP2 cursor texture for the WoW client.

Usage: uv run --with pillow python tools/cursor_blp.py <source.tga|png> <dest.blp>

Writes the same BLP2 layout as Blizzard's own cursor files (palette colors,
8-bit alpha plane, full mip chain), because the client is known to accept
that encoding for interface/cursor/*.blp.

The wowf 1.60.1 client ignores loose files under Interface/Cursor (tested
2026-11-10), so the output cannot replace a game cursor by itself.
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

from PIL import Image

HEADER = struct.Struct("<4sIBBBBII16I16I")
PALETTE_BYTES = 256 * 4
DATA_START = HEADER.size + PALETTE_BYTES
ENCODING_PALETTE = 1
ALPHA_DEPTH = 8
PREFERRED_FORMAT = 8
MAX_MIPS = 16


def _mip_chain(image: Image.Image) -> list[Image.Image]:
    levels = [image]
    while levels[-1].width > 1 or levels[-1].height > 1:
        prev = levels[-1]
        size = (max(1, prev.width // 2), max(1, prev.height // 2))
        levels.append(prev.resize(size, Image.LANCZOS))
    return levels[:MAX_MIPS]


def _palette_source(image: Image.Image) -> Image.Image:
    # Fully transparent pixels carry arbitrary RGB; flatten them so they do not waste palette slots.
    rgb = Image.new("RGB", image.size, (0, 0, 0))
    rgb.paste(image.convert("RGB"), mask=image.getchannel("A").point(lambda a: 255 if a else 0))
    return rgb


def encode_blp(image: Image.Image) -> bytes:
    image = image.convert("RGBA")
    if image.width != image.height or image.width & (image.width - 1):
        raise ValueError(f"cursor must be a square power of two, got {image.size}")
    levels = _mip_chain(image)
    palette_image = _palette_source(image).quantize(256, method=Image.Quantize.MEDIANCUT)
    rgb_palette = (palette_image.getpalette() or [])[: 256 * 3]
    rgb_palette += [0] * (256 * 3 - len(rgb_palette))

    blocks = []
    for level in levels:
        indices = _palette_source(level).quantize(palette=palette_image, dither=Image.Dither.NONE)
        blocks.append(indices.tobytes() + level.getchannel("A").tobytes())

    offsets, sizes, cursor = [], [], DATA_START
    for block in blocks:
        offsets.append(cursor)
        sizes.append(len(block))
        cursor += len(block)
    pad = [0] * (MAX_MIPS - len(blocks))

    header = HEADER.pack(
        b"BLP2", 1, ENCODING_PALETTE, ALPHA_DEPTH, PREFERRED_FORMAT, 1,
        image.width, image.height, *(offsets + pad), *(sizes + pad),
    )
    palette = bytearray()
    for i in range(256):
        r, g, b = rgb_palette[i * 3: i * 3 + 3]
        palette += bytes((b, g, r, 0))
    return header + bytes(palette) + b"".join(blocks)


def decode_blp(data: bytes, mip: int = 0) -> Image.Image:
    """Decode a palette-encoded BLP2 (alpha depth 0, 1 or 8) mip level to RGBA."""
    magic, _, encoding, alpha_depth, _, _, width, height, *rest = HEADER.unpack_from(data)
    offsets, sizes = rest[:MAX_MIPS], rest[MAX_MIPS:]
    if magic != b"BLP2" or encoding != ENCODING_PALETTE:
        raise ValueError(f"unsupported BLP: magic={magic!r} encoding={encoding}")
    if not sizes[mip]:
        raise ValueError(f"mip {mip} not present")
    w, h = max(1, width >> mip), max(1, height >> mip)
    palette = data[HEADER.size: DATA_START]
    block = data[offsets[mip]: offsets[mip] + sizes[mip]]
    count = w * h
    pixels = bytearray()
    for i in range(count):
        b, g, r, _ = palette[block[i] * 4: block[i] * 4 + 4]
        if alpha_depth == 8:
            a = block[count + i]
        elif alpha_depth == 1:
            a = 255 if block[count + i // 8] >> (i % 8) & 1 else 0
        else:
            a = 255
        pixels += bytes((r, g, b, a))
    return Image.frombytes("RGBA", (w, h), bytes(pixels))


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    source, dest = Path(argv[1]), Path(argv[2])
    with Image.open(source) as image:
        data = encode_blp(image)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    print(f"wrote {dest} ({len(data)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

"""Run with uv run --with pillow python -m unittest tools/test_cursor_blp.py."""

import struct
import sys
import unittest
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cursor_blp import DATA_START, HEADER, decode_blp, encode_blp


def sample(size: int = 16) -> Image.Image:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for y in range(size):
        for x in range(size):
            if x + y < size:
                image.putpixel((x, y), (20 * x % 256, 40, 200, 255 - 10 * y))
    return image


class CursorBlpTests(unittest.TestCase):
    def test_header_matches_blizzard_cursor_layout(self) -> None:
        data = encode_blp(sample())
        magic, kind, encoding, alpha_depth, preferred, has_mips, w, h, *rest = HEADER.unpack_from(data)
        offsets, sizes = rest[:16], rest[16:]
        self.assertEqual((magic, kind, encoding, alpha_depth, preferred, has_mips), (b"BLP2", 1, 1, 8, 8, 1))
        self.assertEqual((w, h), (16, 16))
        self.assertEqual(sizes[:5], [512, 128, 32, 8, 2])
        self.assertEqual(sizes[5:], [0] * 11)
        self.assertEqual(offsets[0], DATA_START)
        self.assertEqual(offsets[4] + sizes[4], len(data))

    def test_round_trip_keeps_alpha_exact_and_colors_close(self) -> None:
        source = sample()
        decoded = decode_blp(encode_blp(source))
        self.assertEqual(decoded.getchannel("A").tobytes(), source.getchannel("A").tobytes())
        for a, b in zip(source.getdata(), decoded.getdata()):
            if a[3]:
                self.assertLessEqual(max(abs(x - y) for x, y in zip(a[:3], b[:3])), 8)

    def test_decodes_one_bit_alpha_like_blizzard_point(self) -> None:
        data = bytearray(encode_blp(sample(2)))
        struct.pack_into("<B", data, 9, 1)
        size = HEADER.unpack_from(data)[8 + 16]
        offset = HEADER.unpack_from(data)[8]
        data[offset + 4: offset + size] = bytes([0b0101]) + bytes(size - 5)
        alpha = decode_blp(bytes(data)).getchannel("A").tobytes()
        self.assertEqual(alpha, bytes((255, 0, 255, 0)))

    def test_rejects_non_power_of_two(self) -> None:
        with self.assertRaises(ValueError):
            encode_blp(Image.new("RGBA", (24, 24)))


if __name__ == "__main__":
    unittest.main()

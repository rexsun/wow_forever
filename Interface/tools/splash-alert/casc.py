"""Read one file by FileDataID from the game's local CASC storage. Read-only; it never touches the network.

Formats: https://wowdev.wiki/CASC (local index, BLTE, encoding, MFST root).
"""

from __future__ import annotations

import struct
import zlib
from bisect import bisect_right
from pathlib import Path

DATA_HEADER = 0x1E
INDEX_KEY = 9
INDEX_ENTRY = 18
INDEX_ENTRIES_AT = 0x28
ARCHIVE_OFFSET_BITS = 30
ROOT_MAGIC = b"TSFM"
ROOT_NO_NAME_HASH = 0x10000000
LOCALE_ENUS = 0x2
LOCALE_ALL = 0xFFFFFFFF


class CascError(RuntimeError):
    pass


def _build_info(install: Path, product: str) -> dict[str, str]:
    lines = (install / ".build.info").read_text(encoding="utf-8").splitlines()
    names = [column.split("!")[0] for column in lines[0].split("|")]
    rows = [dict(zip(names, line.split("|"))) for line in lines[1:] if line.strip()]
    for row in rows:
        if row.get("Product") == product and row.get("Active") == "1":
            return row
    raise CascError(f"product {product!r} is not installed in {install}")


def _config(data: Path, key: str) -> dict[str, list[str]]:
    text = (data / "config" / key[:2] / key[2:4] / key).read_text(encoding="utf-8")
    return {k.strip(): v.split() for k, _, v in (line.partition("=") for line in text.splitlines())
            if v and not k.startswith("#")}


def blte_decode(blob: bytes) -> bytes:
    if blob[:4] != b"BLTE":
        raise CascError("not a BLTE stream")
    header_size = struct.unpack_from(">I", blob, 4)[0]
    if header_size == 0:
        return _blte_chunk(blob[8:])
    count = int.from_bytes(blob[9:12], "big")
    sizes = [struct.unpack_from(">I", blob, 12 + i * 24)[0] for i in range(count)]
    out, at = [], header_size
    for size in sizes:
        out.append(_blte_chunk(blob[at:at + size]))
        at += size
    return b"".join(out)


def _blte_chunk(chunk: bytes) -> bytes:
    mode = chunk[:1]
    if mode == b"N":
        return chunk[1:]
    if mode == b"Z":
        return zlib.decompress(chunk[1:])
    if mode == b"E":
        raise CascError("the file is encrypted")
    raise CascError(f"unsupported BLTE chunk mode {mode!r}")


class Casc:
    def __init__(self, install: Path, product: str) -> None:
        self._data = install / "Data"
        info = _build_info(install, product)
        self.build_key = info["Build Key"]
        build = _config(self._data, self.build_key)
        self._index = self._read_indices()
        self._encoding = blte_decode(self._read_ekey(bytes.fromhex(build["encoding"][1])))
        self._encoding_pages = self._encoding_page_table()
        self._root = blte_decode(self._read_ckey(bytes.fromhex(build["root"][0])))

    def read_fdid(self, fdid: int) -> bytes:
        ckey = self._root_lookup(fdid)
        if ckey is None:
            raise CascError(f"file {fdid} is not in this build")
        return blte_decode(self._read_ckey(ckey))

    def _read_indices(self) -> dict[bytes, tuple[int, int, int]]:
        latest: dict[str, Path] = {}
        for path in sorted((self._data / "data").glob("*.idx")):
            latest[path.name[:2]] = path
        index: dict[bytes, tuple[int, int, int]] = {}
        for path in latest.values():
            raw = path.read_bytes()
            size = struct.unpack_from("<I", raw, 0x20)[0]
            for at in range(INDEX_ENTRIES_AT, INDEX_ENTRIES_AT + size, INDEX_ENTRY):
                key = raw[at:at + INDEX_KEY]
                packed = int.from_bytes(raw[at + INDEX_KEY:at + INDEX_KEY + 5], "big")
                length = struct.unpack_from("<I", raw, at + INDEX_KEY + 5)[0]
                index.setdefault(key, (packed >> ARCHIVE_OFFSET_BITS,
                                       packed & ((1 << ARCHIVE_OFFSET_BITS) - 1), length))
        return index

    def _read_ekey(self, ekey: bytes) -> bytes:
        entry = self._index.get(ekey[:INDEX_KEY])
        if entry is None:
            raise CascError(f"{ekey.hex()} is not stored locally")
        archive, offset, length = entry
        with open(self._data / "data" / f"data.{archive:03d}", "rb") as f:
            f.seek(offset + DATA_HEADER)
            return f.read(length - DATA_HEADER)

    def _read_ckey(self, ckey: bytes) -> bytes:
        return self._read_ekey(self._encoding_lookup(ckey))

    def _encoding_page_table(self) -> tuple[list[bytes], int, int]:
        enc = self._encoding
        if enc[:2] != b"EN":
            raise CascError("unknown encoding file")
        page_kb, = struct.unpack_from(">H", enc, 5)
        page_count, = struct.unpack_from(">I", enc, 9)
        espec_size = int.from_bytes(enc[18:22], "big")
        table = 22 + espec_size
        first_keys = [enc[table + i * 32:table + i * 32 + 16] for i in range(page_count)]
        return first_keys, table + page_count * 32, page_kb * 1024

    def _encoding_lookup(self, ckey: bytes) -> bytes:
        first_keys, pages_at, page_size = self._encoding_pages
        page = bisect_right(first_keys, ckey) - 1
        if page < 0:
            raise CascError(f"content {ckey.hex()} is not in the encoding table")
        enc, at = self._encoding, pages_at + page * page_size
        end = at + page_size
        while at + 22 <= end:
            count = enc[at]
            if count == 0:
                break
            if enc[at + 6:at + 22] == ckey:
                return enc[at + 22:at + 38]
            at += 22 + 16 * count
        raise CascError(f"content {ckey.hex()} is not in the encoding table")

    def _root_lookup(self, fdid: int) -> bytes | None:
        root = self._root
        if root[:4] != ROOT_MAGIC:
            raise CascError("unsupported root format")
        header_size, version = struct.unpack_from("<II", root, 4)
        if header_size > 0x100:  # Older MFST: the header is only the two file counts.
            at, version = 12, 0
        else:
            at = header_size
        found: bytes | None = None
        while at < len(root):
            count, = struct.unpack_from("<I", root, at)
            if version >= 2:
                locale, flags_a, flags_b = struct.unpack_from("<III", root, at + 4)
                content = flags_a | flags_b | (root[at + 16] << 17)
                at += 17
            else:
                content, locale = struct.unpack_from("<II", root, at + 4)
                at += 12
            deltas = struct.unpack_from(f"<{count}i", root, at)
            at += 4 * count
            ckeys_at = at
            at += 16 * count
            if not content & ROOT_NO_NAME_HASH:
                at += 8 * count
            if locale != LOCALE_ALL and not locale & LOCALE_ENUS and found is not None:
                continue
            current = -1
            for i, delta in enumerate(deltas):
                current += delta + 1
                if current == fdid:
                    found = root[ckeys_at + 16 * i:ckeys_at + 16 * (i + 1)]
                    if locale & LOCALE_ENUS:
                        return found
                    break
                if current > fdid:
                    break
        return found

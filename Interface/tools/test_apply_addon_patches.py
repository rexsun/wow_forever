"""Run with uv run python -m unittest tools/test_apply_addon_patches.py."""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from apply_addon_patches import ADDONS, PATCHES, apply_patches


def write_upstream(root: Path, newline: str = "\n") -> None:
    grouped: dict[str, list[str]] = {}
    for patch in PATCHES:
        grouped.setdefault(patch.file, []).append(patch.upstream)
    for relative, lines in grouped.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", encoding="utf-8", newline="") as stream:
            stream.write(newline.join(["-- head", *lines, "-- tail"]) + newline)


class ApplyAddonPatchesTests(unittest.TestCase):
    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)

    def test_applies_every_patch_and_is_idempotent(self) -> None:
        write_upstream(self.root)
        self.assertTrue(apply_patches(self.root, check=True))
        self.assertEqual(apply_patches(self.root), [])
        self.assertEqual(apply_patches(self.root, check=True), [])
        before = {path: path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        self.assertEqual(apply_patches(self.root), [])
        self.assertEqual(before, {path: path.read_bytes() for path in before})

    def test_preserves_line_endings(self) -> None:
        write_upstream(self.root, "\r\n")
        self.assertEqual(apply_patches(self.root), [])
        for path in self.root.rglob("*"):
            if path.is_file():
                self.assertEqual(path.read_bytes().count(b"\n"), path.read_bytes().count(b"\r\n"))

    def test_changed_upstream_fails_without_writing_anything(self) -> None:
        write_upstream(self.root)
        changed = self.root / PATCHES[-1].file
        changed.write_text("-- upstream rewrote this file\n", encoding="utf-8")
        before = {path: path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        problems = apply_patches(self.root)
        self.assertTrue(any(PATCHES[-1].file in problem for problem in problems))
        self.assertEqual(before, {path: path.read_bytes() for path in before})

    def test_uncovered_font_reference_fails(self) -> None:
        write_upstream(self.root)
        fonts = self.root / PATCHES[0].file
        with fonts.open("a", encoding="utf-8") as stream:
            stream.write('LSM:Register("font", "New", Bundle("sharedmedia-fonts", "YUI New.ttf"), 255)\n')
        self.assertTrue(any("uncovered" in problem for problem in apply_patches(self.root)))

    def test_installed_pack_is_patched(self) -> None:
        self.assertEqual(apply_patches(ADDONS, check=True), [])


if __name__ == "__main__":
    unittest.main()

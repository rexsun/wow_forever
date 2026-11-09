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
            body = newline.join(["-- head", *lines, "-- tail"]).replace("\r\n", "\n").replace("\n", newline)
            stream.write(body + newline)


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

    def test_additive_patch_keeps_upstream_line_once_with_file_line_endings(self) -> None:
        write_upstream(self.root, "\r\n")
        self.assertEqual(apply_patches(self.root), [])
        self.assertEqual(apply_patches(self.root), [])
        toc = (self.root / "Skinner/Skinner.toc").read_bytes()
        self.assertEqual(toc.count(b"[Family]\\_Support.xml\r\n"), 1)
        self.assertEqual(toc.count(b"Forever\\_Support.xml"), 1)

    def test_stray_upstream_line_beside_additive_patch_fails(self) -> None:
        write_upstream(self.root)
        self.assertEqual(apply_patches(self.root), [])
        toc = self.root / "Skinner/Skinner.toc"
        with toc.open("a", encoding="utf-8", newline="") as stream:
            stream.write("[Family]\\_Support.xml\n")
        self.assertTrue(any("both patched" in problem for problem in apply_patches(self.root, check=True)))

    def test_installed_skinner_loads_forever_support_only_on_forever(self) -> None:
        toc = (ADDONS / "Skinner/Skinner.toc").read_text(encoding="utf-8")
        self.assertIn(
            "Forever\\_Support.xml [AllowLoadGameType camelot] [ExcludeLoadGameType standard, classic]", toc
        )

    def test_installed_details_guards_every_spec_icon_lookup(self) -> None:
        for relative in (
            "Details/classes/class_damage.lua",
            "Details/functions/util.lua",
            "Details/frames/window_breakdown_midnight/breakdown_dataprovider.lua",
            "Details/core/parser_nocleu_tp.lua",
        ):
            for line in (ADDONS / relative).read_text(encoding="utf-8").splitlines():
                if ":GetSpecInfoFromSpecIcon(" in line or ":GetSpecIdFromSpecIcon(" in line or "guidCache[icon" in line:
                    self.assertIn("issecretvalue", line, f"{relative}: {line.strip()}")

    def test_multiline_upstream_matches_crlf_files(self) -> None:
        write_upstream(self.root, "\r\n")
        self.assertEqual(apply_patches(self.root), [])
        overrides = (self.root / "BagBrother/core/features/uiOverrides.lua").read_bytes()
        self.assertNotIn(b"'combinedBags', nil", overrides)

    def test_installed_bagnon_forces_individual_bags_outside_tutorial_guard(self) -> None:
        text = (ADDONS / "BagBrother/core/features/uiOverrides.lua").read_text(encoding="utf-8")
        self.assertNotIn("'combinedBags', nil", text)
        self.assertEqual(text.count("C_CVar.SetCVar('combinedBags', '0')"), 3)
        self.assertLess(text.index("C_CVar.SetCVar('combinedBags', '0')"), text.index("LE_FRAME_TUTORIAL_EQUIP_REAGENT_BAG"))

    def test_installed_fishing_sounds_silence_other_channels_at_full_effects(self) -> None:
        relative = "EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_Fishing.lua"
        text = (ADDONS / relative).read_text(encoding="utf-8")
        block = text[text.index("local SOUND_CVARS = {") : text.index("local function KeyOn")]
        for cvar in ("Sound_MusicVolume", "Sound_AmbienceVolume", "Sound_DialogVolume"):
            self.assertIn(f"{cvar} = function() return 0 end", block)
        for cvar in ("Sound_SFXVolume", "Sound_MasterVolume"):
            self.assertIn(f"{cvar} = function() return 1 end", block)

    def test_installed_pack_is_patched(self) -> None:
        self.assertEqual(apply_patches(ADDONS, check=True), [])


if __name__ == "__main__":
    unittest.main()

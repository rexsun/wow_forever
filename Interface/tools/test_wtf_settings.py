import importlib.util
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("wtf_settings", Path(__file__).with_name("wtf_settings.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.game = self.root / "game"
        self.saved = self.game / "WTF/Account/SECRET123/HiddenRealm/HiddenCharacter/SavedVariables"
        self.saved.mkdir(parents=True)
        (self.game / "Interface").mkdir()
        self.state = self.root / "private"
        self.output = self.game / "Interface/Settings/WTF"
        subprocess.run(["git", "init", "-q", str(self.game)], check=True)
        (self.game / ".gitignore").write_text("/WTF/\n")
        self.source = self.saved / "YUI.lua"
        self.source.write_text('YUIDB = { ["profiles"] = { ["HiddenCharacter - HiddenRealm"] = { ["scale"] = 0.8, ["enabled"] = true, ["accountID"] = 1234567, ["note"] = "Name#1234", }, }, }')

    def tearDown(self):
        self.temp.cleanup()

    def export(self):
        return MODULE.export_settings(self.game, self.state)

    def test_privacy_and_stable_aliases(self):
        self.export()
        first = {p.relative_to(self.output): p.read_bytes() for p in self.output.rglob("*.json")}
        text = str(list(first)) + b"".join(first.values()).decode()
        for secret in ("SECRET123", "HiddenRealm", "HiddenCharacter", "Name#1234", "1234567"):
            self.assertNotIn(secret, text)
        self.assertIn("0.8", MODULE.readable_snapshot(self.output, self.state))
        self.assertIn("true", text)
        self.export()
        self.assertEqual(first, {p.relative_to(self.output): p.read_bytes() for p in self.output.rglob("*.json")})
        self.assertIn("HiddenCharacter", (self.state / "map.json").read_text())

    def test_failure_preserves_previous_snapshot(self):
        self.export()
        before = {p: p.read_bytes() for p in self.output.rglob("*.json")}
        self.source.write_text('YUIDB = os.execute("never execute")')
        with self.assertRaises(MODULE.SettingsError):
            self.export()
        self.assertEqual(before, {p: p.read_bytes() for p in self.output.rglob("*.json")})

    def test_only_approved_files_and_settings_cvars(self):
        (self.saved / "!BugGrabber.lua").write_text('bad data containing secrets')
        (self.game / "WTF/Config.wtf").write_text('SET accountName "SECRET123"\nSET gxWindowedResolution "1920x1080"\nSET uiScale "0.75"\n')
        self.export()
        self.assertFalse(any("BugGrabber" in p.name for p in self.output.rglob("*")))
        decoded = MODULE.readable_snapshot(self.output, self.state)
        self.assertIn("1920x1080", decoded)
        self.assertNotIn("accountName", decoded)

    def test_git_index_is_untouched(self):
        subprocess.run(["git", "-C", str(self.game), "add", ".gitignore"], check=True)
        index = self.game / ".git/index"
        before = index.read_bytes()
        self.export()
        self.assertEqual(before, index.read_bytes())

    def test_local_review_decodes_keys_and_values(self):
        self.export()
        decoded = MODULE.readable_snapshot(self.output, self.state)
        self.assertIn('scale', decoded)
        self.assertIn('HiddenCharacter - HiddenRealm', decoded)

    def test_parser_handles_lua_escaping_comments_and_arrays(self):
        parsed = MODULE.parse_lua('DB = { "a\\n\\065", -- trailing\n [2] = false, ["nested"] = {value = -1.25e2;}, }')
        self.assertEqual(parsed["DB"][1], "a\nA")
        self.assertEqual(parsed["DB"]["nested"]["value"], -125)

    def test_lock_excludes_another_exporter(self):
        with MODULE.state_lock(self.state):
            with self.assertRaises(MODULE.SettingsError):
                self.export()

    def test_missing_private_map_does_not_reassign_existing_aliases(self):
        self.export()
        (self.state / "map.json").unlink()
        with self.assertRaises(MODULE.SettingsError):
            self.export()

    def test_dry_run_does_not_publish_or_save_map(self):
        MODULE.export_settings(self.game, self.state, dry_run=True)
        self.assertFalse(self.output.exists())
        self.assertFalse((self.state / "map.json").exists())

    def test_restart_before_publication_preserves_snapshot(self):
        self.export()
        before = {p: p.read_bytes() for p in self.output.rglob("*.json")}
        def restarted():
            raise MODULE.SettingsError("Game restarted")
        with self.assertRaises(MODULE.SettingsError):
            MODULE.export_settings(self.game, self.state, before_publish=restarted)
        self.assertEqual(before, {p: p.read_bytes() for p in self.output.rglob("*.json")})

    def test_numeric_keys_are_also_private(self):
        self.source.write_text('DB = { [123456789] = { ["scale"] = 0.75 } }')
        self.export()
        self.assertNotIn("123456789", "".join(p.read_text() for p in self.output.rglob("*.json")))

    def test_unknown_numeric_identity_fields_are_private(self):
        self.source.write_text('DB = { ["unexpectedField"] = 987654321, ["scale"] = 0.85 }')
        self.export()
        text = "".join(p.read_text() for p in self.output.rglob("*.json"))
        self.assertNotIn("987654321", text)
        self.assertIn("0.85", MODULE.readable_snapshot(self.output, self.state))

    def test_invalid_alias_map_cannot_publish_private_text(self):
        self.export()
        data = json.loads((self.state / "map.json").read_text())
        data["strings"]["scale"] = "SECRET123"
        (self.state / "map.json").write_text(json.dumps(data))
        with self.assertRaises(MODULE.SettingsError):
            self.export()

    def test_local_review_includes_untracked_baseline(self):
        self.export()
        stream = io.StringIO()
        with redirect_stdout(stream):
            MODULE.review(self.game, self.state)
        self.assertIn('scale', stream.getvalue())
        self.assertIn('0.8', stream.getvalue())

    def test_new_source_file_during_export_defers_publication(self):
        self.export()
        before = {p: p.read_bytes() for p in self.output.rglob("*.json")}
        def add_file():
            (self.saved / 'EllesmereUI.lua').write_text('DB = {scale = 1}')
        with self.assertRaises(MODULE.SettingsError):
            MODULE.export_settings(self.game, self.state, before_publish=add_file)
        self.assertEqual(before, {p: p.read_bytes() for p in self.output.rglob("*.json")})


if __name__ == "__main__":
    unittest.main()

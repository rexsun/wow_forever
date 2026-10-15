import importlib.util
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


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
        (self.game / ".gitignore").write_text("/WTF/\n/Interface/.env*\n!/Interface/.env.example\n")
        self.source = self.saved / "YUI.lua"
        self.source.write_text('YUIDB = { ["profiles"] = { ["HiddenCharacter - HiddenRealm"] = { ["scale"] = 0.8, ["enabled"] = true, ["accountID"] = 1234567, ["note"] = "Name#1234", }, }, }')

    def tearDown(self):
        self.temp.cleanup()

    def export(self):
        return MODULE.export_settings(self.game, self.state)

    def test_current_pack_exports_gearinsight_and_excludes_retired_addons(self):
        (self.saved / "GearInsight_Forever.lua").write_text('GearInsightForeverDB = {keysHud=false, qm={autoPlates=false}}')
        for name in ("RXPGuides", "DungeonsForever", "TalentsForeverBook"):
            (self.saved / (name + ".lua")).write_text('RetiredDB = {enabled=true}')
        self.export()
        files = {p.name for p in self.output.rglob("*.json")}
        self.assertIn("GearInsight_Forever.json", files)
        self.assertTrue(files.isdisjoint({"RXPGuides.json", "DungeonsForever.json", "TalentsForeverBook.json"}))

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
        self.assertIn("HiddenCharacter", (self.game / 'Interface/.env').read_text())

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
        (self.game / 'Interface/.env').unlink()
        with self.assertRaises(MODULE.SettingsError):
            self.export()

    def test_dry_run_does_not_publish_or_save_map(self):
        MODULE.export_settings(self.game, self.state, dry_run=True)
        self.assertFalse(self.output.exists())
        self.assertFalse((self.game / 'Interface/.env').exists())

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
        data = MODULE.load_aliases(self.game)
        data["strings"]["scale"] = "SECRET123"
        with self.assertRaises(MODULE.SettingsError):
            MODULE.save_aliases(self.game, data)

    def test_env_variables_preserve_quotes_unicode_and_multiline_values(self):
        path = self.game / 'Interface/.env'
        path.write_text('WTF_SETTINGS_STATE_DIR=\'D:\\Private\\Settings\'\nWTF_MAP_VERSION=1\n')
        data = {'version':1,'strings':{'a"\\\né':'text-0000001'},'numbers':{'0.85':'number-0000001'}}
        MODULE.save_aliases(self.game, data)
        self.assertEqual(MODULE.load_aliases(self.game), data)
        self.assertEqual(MODULE.read_env(path)['WTF_SETTINGS_STATE_DIR'], 'D:\\Private\\Settings')

    def test_private_env_must_be_ignored_and_untracked(self):
        (self.game / '.gitignore').write_text('/WTF/\n')
        with self.assertRaises(MODULE.SettingsError):
            self.export()

    def test_invalid_alias_variable_is_rejected(self):
        path = self.game / 'Interface/.env'
        path.write_text('WTF_MAP_VERSION=1\nWTF_TEXT_SECRET="scale"\n')
        with self.assertRaises(MODULE.SettingsError):
            MODULE.load_aliases(self.game)

    def test_example_only_env_cannot_reassign_existing_snapshots(self):
        self.export()
        before = {p: p.read_bytes() for p in self.output.rglob('*.json')}
        (self.game / 'Interface/.env').write_text('WTF_MAP_VERSION=1\n')
        with self.assertRaises(MODULE.SettingsError):
            self.export()
        self.assertEqual(before, {p: p.read_bytes() for p in self.output.rglob('*.json')})

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

    def test_restore_round_trip_and_private_backup(self):
        expected = MODULE.parse_lua(self.source.read_text())
        self.export()
        snapshots = {p: p.read_bytes() for p in self.output.rglob('*.json')}
        private = (self.game / 'Interface/.env').read_bytes()
        subprocess.run(['git', '-C', str(self.game), 'add', '.gitignore'], check=True)
        index = (self.game / '.git/index').read_bytes()
        changed = b'YUIDB = { ["scale"] = 0.1 }\n'
        self.source.write_bytes(changed)
        count, backup = MODULE.restore_settings(self.game, self.state)
        self.assertEqual(count, 1)
        self.assertEqual(expected, MODULE.parse_lua(self.source.read_text()))
        self.assertEqual((backup / self.source.relative_to(self.game / 'WTF')).read_bytes(), changed)
        self.assertEqual(snapshots, {p: p.read_bytes() for p in self.output.rglob('*.json')})
        self.assertEqual(private, (self.game / 'Interface/.env').read_bytes())
        self.assertEqual(index, (self.game / '.git/index').read_bytes())

    def test_restore_preserves_config_identity_and_unrepresented_files(self):
        config = self.game / 'WTF/Config.wtf'
        config.write_text('SET accountName "SECRET123"\nSET uiScale "0.8"\n')
        self.export()
        config.write_text('SET accountName "CURRENT456"\nSET uiScale "0.5"\nSET gamma "1.2"\n')
        other = self.saved / 'OtherAddon.lua'
        other.write_text('OtherDB = { untouched = true }')
        MODULE.restore_settings(self.game, self.state)
        self.assertIn('SET accountName "CURRENT456"', config.read_text())
        self.assertIn('SET uiScale "0.8"', config.read_text())
        self.assertIn('SET gamma "1.2"', config.read_text())
        self.assertEqual(other.read_text(), 'OtherDB = { untouched = true }')

    def test_restore_missing_file_in_existing_account(self):
        self.export()
        self.source.unlink()
        MODULE.restore_settings(self.game, self.state)
        self.assertIn('YUIDB', self.source.read_text())

    def test_restore_dry_run_preserves_live_bundle_map_and_index(self):
        self.export()
        self.source.write_text('YUIDB = { changed = true }')
        before = {p: p.read_bytes() for p in self.game.rglob('*') if p.is_file()}
        private = (self.game / 'Interface/.env').read_bytes()
        count, backup = MODULE.restore_settings(self.game, self.state, dry_run=True)
        self.assertEqual(count, 1)
        self.assertIsNone(backup)
        self.assertEqual(before, {p: p.read_bytes() for p in self.game.rglob('*') if p.is_file()})
        self.assertEqual(private, (self.game / 'Interface/.env').read_bytes())
        self.assertFalse((self.state / 'backups').exists())

    def test_restore_rejects_unknown_alias_before_writes(self):
        self.export()
        snapshot = next(self.output.rglob('YUI.json'))
        data = json.loads(snapshot.read_text())
        data['$table'][0]['key'] = {'$text':'text-9999999'}
        snapshot.write_text(json.dumps(data))
        before = self.source.read_bytes()
        with self.assertRaises(MODULE.SettingsError):
            MODULE.restore_settings(self.game, self.state)
        self.assertEqual(before, self.source.read_bytes())

    def test_restore_rejects_mapped_path_traversal(self):
        self.export()
        data = MODULE.load_aliases(self.game)
        token = data['strings'].pop('SECRET123')
        data['strings']['..'] = token
        MODULE.save_aliases(self.game, data)
        with self.assertRaises(MODULE.SettingsError):
            MODULE.restore_settings(self.game, self.state)

    def test_restore_does_not_recreate_missing_account(self):
        self.export()
        account = self.game / 'WTF/Account/SECRET123'
        account.rename(account.with_name('CURRENT456'))
        with self.assertRaises(MODULE.SettingsError):
            MODULE.restore_settings(self.game, self.state)
        self.assertFalse(account.exists())

    def test_restore_rolls_back_all_previous_replacements(self):
        config = self.game / 'WTF/Config.wtf'
        config.write_text('SET uiScale "0.8"\n')
        self.export()
        config.write_text('SET uiScale "0.5"\n')
        self.source.write_text('YUIDB = { changed = true }')
        original_config = config.read_bytes()
        original_lua = self.source.read_bytes()
        real_write = MODULE.atomic_bytes
        calls = []
        def fail_second(path, content):
            calls.append(path)
            if len(calls) == 2:
                raise OSError('Simulated replacement failure')
            return real_write(path, content)
        with patch.object(MODULE, 'atomic_bytes', side_effect=fail_second):
            with self.assertRaises(MODULE.SettingsError):
                MODULE.restore_settings(self.game, self.state)
        self.assertEqual(original_config, config.read_bytes())
        self.assertEqual(original_lua, self.source.read_bytes())

    def test_restore_restart_refusal_before_writes(self):
        self.export()
        before = self.source.read_bytes()
        def restarted():
            raise MODULE.SettingsError('Game restarted')
        with self.assertRaises(MODULE.SettingsError):
            MODULE.restore_settings(self.game, self.state, before_publish=restarted)
        self.assertEqual(before, self.source.read_bytes())

    def test_restore_lua_strings_are_not_executable(self):
        value = {'DB': {'quote': '"\\\n\x00é', 'payload': 'os.execute("never")', 1: False}}
        serialized = MODULE.serialize_lua(value)
        self.assertEqual(value, MODULE.parse_lua(serialized))

    def test_restore_rejects_unapproved_cvar(self):
        config = self.game / 'WTF/Config.wtf'
        config.write_text('SET uiScale "0.8"\n')
        self.export()
        data = MODULE.load_aliases(self.game)
        token = data['strings'].pop('uiScale')
        data['strings']['accountName'] = token
        MODULE.save_aliases(self.game, data)
        with self.assertRaises(MODULE.SettingsError):
            MODULE.restore_settings(self.game, self.state)

    def test_restore_rejects_raw_text_in_snapshot(self):
        self.export()
        snapshot = next(self.output.rglob('YUI.json'))
        data = json.loads(snapshot.read_text())
        data['$table'][0]['value'] = 'os.execute("never")'
        snapshot.write_text(json.dumps(data))
        with self.assertRaises(MODULE.SettingsError):
            MODULE.restore_settings(self.game, self.state)

    def test_restore_rolls_back_new_files_on_failure(self):
        config = self.game / 'WTF/Config.wtf'
        config.write_text('SET uiScale "0.8"\n')
        self.export()
        config.unlink()
        self.source.write_text('YUIDB = { changed = true }')
        real_write = MODULE.atomic_bytes
        calls = []
        def fail_second(path, content):
            calls.append(path)
            if len(calls) == 2:
                raise OSError('Simulated replacement failure')
            return real_write(path, content)
        with patch.object(MODULE, 'atomic_bytes', side_effect=fail_second):
            with self.assertRaises(MODULE.SettingsError):
                MODULE.restore_settings(self.game, self.state)
        self.assertFalse(config.exists())
        self.assertEqual(self.source.read_text(), 'YUIDB = { changed = true }')

    def test_restore_serializes_escaped_utf8_and_binary_bytes(self):
        self.assertEqual(MODULE.parse_lua(r'DB = {text = "\195\169", binary = "\255"}'), {'DB': {'text': 'é', 'binary': '\udcff'}})
        self.assertEqual(MODULE.parse_lua(MODULE.serialize_lua({'DB': {'text': 'é', 'binary': '\udcff'}})), {'DB': {'text': 'é', 'binary': '\udcff'}})

    def test_restore_empty_config_preserves_exact_bytes(self):
        original = b'SET accountName "SECRET123"'
        self.assertEqual(MODULE.merge_config(original, {}), original)

    def test_restore_rejects_lua_keyword_global(self):
        with self.assertRaises(MODULE.SettingsError):
            MODULE.serialize_lua({'end': 1})


if __name__ == "__main__":
    unittest.main()

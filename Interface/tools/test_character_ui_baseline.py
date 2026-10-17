import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent))
from wtf_settings import parse_lua, serialize_lua

SPEC = importlib.util.spec_from_file_location('character_ui_baseline', Path(__file__).with_name('character_ui_baseline.py'))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RefreshTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.game = Path(self.temp.name)
        self.config = self.game / 'Interface/Settings/character-ui-source.local.json'
        self.config.parent.mkdir(parents=True)
        self.addon = self.game / 'Interface/AddOns/CharacterUIBaseline'
        self.addon.mkdir(parents=True)
        self.settings = dict(sourceAccount='account-A', sourceRealm='70',
            sourceCharacter='Source-Surname', sourceRealmName='Test Realm', fallbackLayoutName='YUI v3')
        self.seed(self.settings)
        self.config.write_text(json.dumps(self.settings))

    def seed(self, cfg, font=18):
        source = self.game / 'WTF/Account' / cfg['sourceAccount'] / cfg['sourceRealm'] / cfg['sourceCharacter']
        source.mkdir(parents=True)
        source.joinpath('config-cache.wtf').write_text('SET showQuestLevel "1"\nSET primaryTalentTree "999"\nSET trackedQuests "PRIVATE"\n')
        source.joinpath('chat-cache.txt').write_text(f'WINDOW 1\nSIZE {font}\nPOSITION BOTTOMLEFT 0.01 0.02\nDIMENSIONS 475 265\nMESSAGES\nEND\n')
        saved = source.parents[1] / 'SavedVariables'
        saved.mkdir(exist_ok=True)
        saved.joinpath('EllesmereUI.lua').write_text(serialize_lua({'EllesmereUIDB': {
            'activeProfile':'Default','specProfiles':{'test':'keep'},'profiles':{'Default':{'addons':{
            'EllesmereUIRaidFrames':{'partyUnlockPos':{'point':'CENTER','relPoint':'CENTER','x':12,'y':34},'specOverrides':{'keep':True}}}}}}}))
        return source

    def generated(self):
        return (self.addon/'Baseline.lua').read_text()

    def test_refresh_tracks_source_changes_without_writing_wtf(self):
        before={p:p.read_bytes() for p in (self.game/'WTF').rglob('*') if p.is_file()}
        self.assertTrue(MODULE.refresh(self.game))
        first=self.generated()
        self.assertNotIn('primaryTalentTree',first)
        self.assertNotIn('specOverrides',first)
        self.assertNotIn('specProfiles',first)
        self.assertNotIn('PRIVATE',first)
        self.assertEqual(before,{p:p.read_bytes() for p in before})
        self.assertFalse(MODULE.refresh(self.game))
        source=self.game/'WTF/Account/account-A/70/Source-Surname/config-cache.wtf'
        source.write_text('SET showQuestLevel "0"\n')
        self.assertTrue(MODULE.refresh(self.game))
        self.assertNotEqual(first,self.generated())

    def test_account_and_character_are_configurable(self):
        MODULE.refresh(self.game)
        old=(self.addon/'Source.local.lua').read_text()
        cfg={**self.settings,'sourceAccount':'account-B','sourceCharacter':'New-Surname'}
        self.seed(cfg,font=22)
        self.config.write_text(json.dumps(cfg))
        MODULE.refresh(self.game)
        self.assertNotEqual(old,(self.addon/'Source.local.lua').read_text())
        self.assertIn('22',self.generated())

    def test_missing_or_unsafe_source_leaves_generated_files_intact(self):
        MODULE.refresh(self.game)
        before={p:p.read_bytes() for p in self.addon.iterdir()}
        for value in ('../outside','missing',r'account\other'):
            self.config.write_text(json.dumps({**self.settings,'sourceAccount':value}))
            with self.assertRaises((ValueError,OSError)):
                MODULE.refresh(self.game)
            self.assertEqual(before,{p:p.read_bytes() for p in before})

    def test_dry_run_and_absent_config_do_not_write(self):
        self.assertTrue(MODULE.refresh(self.game,dry_run=True))
        self.assertEqual(list(self.addon.iterdir()),[])
        self.config.unlink()
        self.assertFalse(MODULE.refresh(self.game))

    def test_source_publication_is_bound_to_configured_identity(self):
        MODULE.refresh(self.game)
        key=MODULE.read_config(self.game)['key']
        saved=self.game/'WTF/Account/account-A/SavedVariables/CharacterUIBaseline.lua'
        data={'CharacterUIBaselineAccountDB':{'sourceKey':key,'baseline':{
            'layoutName':'My Live Layout','nativeLayout':'SOURCE_NATIVE_UI', 'euiPositions':{'partyUnlockPos':{'point':'CENTER','relPoint':'CENTER','x':99,'y':77}},
            'talents':{'never':True},'specProfiles':{'never':True}}}}
        saved.write_text(serialize_lua(data))
        MODULE.refresh(self.game)
        self.assertIn('My Live Layout',self.generated())
        self.assertIn('SOURCE_NATIVE_UI',self.generated())
        self.assertNotIn('talents',self.generated())
        saved.write_text(serialize_lua({'CharacterUIBaselineAccountDB':{'sourceKey':'OTHER','baseline':{'layoutName':'Wrong'}}}))
        MODULE.refresh(self.game)
        self.assertNotIn('Wrong',self.generated())

    def test_failed_second_write_rolls_back_both_generated_files(self):
        MODULE.refresh(self.game)
        before={p:p.read_bytes() for p in self.addon.iterdir()}
        cfg={**self.settings,'sourceAccount':'account-B','sourceCharacter':'New-Surname'}
        self.seed(cfg,font=22)
        self.config.write_text(json.dumps(cfg))
        real=MODULE.atomic_bytes
        failed=False
        def fail(path,data):
            nonlocal failed
            if path.name=='Source.local.lua' and not failed:
                failed=True
                raise OSError('simulated failure')
            return real(path,data)
        with patch.object(MODULE,'atomic_bytes',side_effect=fail):
            with self.assertRaises(OSError):MODULE.refresh(self.game)
        self.assertEqual(before,{p:p.read_bytes() for p in before})

    def test_disabling_works_even_when_source_folder_is_unavailable(self):
        MODULE.refresh(self.game)
        old=self.generated()
        self.config.write_text(json.dumps({**self.settings,'enabled':False,'sourceAccount':'unavailable'}))
        self.assertTrue(MODULE.refresh(self.game))
        self.assertEqual(old,self.generated())
        self.assertIn('["enabled"] = false',(self.addon/'Source.local.lua').read_text())


if __name__=='__main__':
    unittest.main()

"""Refresh the login UI baseline from a privately configured source WTF folder."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import uuid

from wtf_settings import SettingsError, atomic_bytes, lua_value, parse_lua, require_game_closed

DISPLAY_CVARS = frozenset({
    'nameplateSelectedScale', 'cooldownViewerEnabled', 'nameplateMaxDistance',
    'nameplateMinScale', 'mapFade', 'showQuestLevel', 'cameraSavedPitch',
    'nameplateMaxAlphaDistance', 'enableMultiActionBars', 'cameraSavedDistance',
    'nameplateTargetBehindMaxDistance', 'nameplateMinAlpha', 'nameplateMaxAlpha',
    'nameplateMinAlphaDistance', 'nameplateMaxScale',
})
POINTS = {'CENTER', 'LEFT', 'RIGHT', 'TOP', 'BOTTOM', 'TOPLEFT', 'TOPRIGHT', 'BOTTOMLEFT', 'BOTTOMRIGHT'}
CONFIG = 'Interface/Settings/character-ui-source.local.json'


def component(value):
    if not isinstance(value, str) or not value.strip() or value in {'.', '..'} or any(c in value for c in '/\\:\x00'):
        raise ValueError('Invalid UI source path component')
    return value


def read_config(game):
    game = Path(game).resolve()
    path = game / CONFIG
    if not path.exists():
        return None
    cfg = json.loads(path.read_text(encoding='utf-8-sig'))
    allowed = {'sourceAccount', 'sourceRealm', 'sourceCharacter', 'sourceRealmName', 'fallbackLayoutName', 'enabled'}
    if not isinstance(cfg, dict) or set(cfg) - allowed or not isinstance(cfg.get('enabled', True), bool):
        raise ValueError('Invalid UI source configuration')
    for field in ('sourceAccount', 'sourceRealm', 'sourceCharacter'):
        component(cfg.get(field))
    for field in ('sourceRealmName', 'fallbackLayoutName'):
        if not isinstance(cfg.get(field), str) or not cfg[field].strip():
            raise ValueError('Missing UI source realm or fallback layout name')
    accounts = (game / 'WTF/Account').resolve()
    account = accounts / cfg['sourceAccount']
    source = account / cfg['sourceRealm'] / cfg['sourceCharacter']
    if not source.resolve().is_relative_to(accounts) or (cfg.get('enabled', True) and not source.is_dir()):
        raise ValueError('Configured UI source does not exist inside this installation')
    identity = [cfg[k] for k in ('sourceAccount', 'sourceRealm', 'sourceCharacter', 'sourceRealmName')]
    return {**cfg, 'enabled': cfg.get('enabled', True), 'key': hashlib.sha256(json.dumps(identity).encode()).hexdigest()[:24],
            'source': source, 'account': account}


def position(value):
    if not isinstance(value, dict) or value.get('point') not in POINTS or value.get('relPoint') not in POINTS:
        return None
    if not all(type(value.get(k)) in (int, float) and math.isfinite(value[k]) for k in ('x', 'y')):
        return None
    return {k: value[k] for k in ('point', 'relPoint', 'x', 'y')}


def saved(path):
    try:
        return parse_lua(path.read_text(encoding='utf-8-sig')) if path.exists() else {}
    except SettingsError as error:
        raise ValueError('Source saved variables are invalid') from error


def build(cfg):
    raw = cfg['source'].joinpath('config-cache.wtf').read_text(encoding='utf-8-sig')
    cvars = {key: value for key, value in re.findall(r'^SET (\S+) "(.*)"$', raw, re.M) if key in DISPLAY_CVARS}
    if not cvars:
        raise ValueError('Source has no supported display preferences')
    chat = cfg['source'].joinpath('chat-cache.txt').read_text(encoding='utf-8-sig')
    window = re.search(r'^WINDOW 1\n(.*?)(?=^WINDOW \d+\n|\Z)', chat, re.M | re.S)
    if not window:
        raise ValueError('Source primary chat window is missing')
    font = re.search(r'^SIZE (\d+(?:\.\d+)?)$', window[1], re.M)
    anchor = re.search(r'^POSITION BOTTOMLEFT ([\d.]+) ([\d.]+)$', window[1], re.M)
    size = re.search(r'^DIMENSIONS ([\d.]+) ([\d.]+)$', window[1], re.M)
    if not (font and anchor and size):
        raise ValueError('Source primary chat geometry is unavailable')
    chat = dict(x=float(anchor[1]), y=float(anchor[2]), width=float(size[1]), height=float(size[2]))
    if not (0 <= chat['x'] <= 1 and 0 <= chat['y'] <= 1 and 0 < chat['width'] <= 10000
            and 0 < chat['height'] <= 10000 and 6 <= float(font[1]) <= 72):
        raise ValueError('Source primary chat geometry is invalid')
    account_saved = cfg['account'] / 'SavedVariables'
    eui = saved(account_saved / 'EllesmereUI.lua').get('EllesmereUIDB', {})
    profile = eui.get('profiles', {}).get(eui.get('activeProfile', 'Default'), {})
    raid = profile.get('addons', {}).get('EllesmereUIRaidFrames', {})
    positions = {k: p for k in ('partyUnlockPos', 'unlockPos') if (p := position(raid.get(k))) is not None}
    publication = saved(account_saved / 'CharacterUIBaseline.lua').get('CharacterUIBaselineAccountDB', {})
    published = publication.get('baseline', {}) if publication.get('sourceKey') == cfg['key'] else {}
    layout = published.get('layoutName', cfg['fallbackLayoutName'])
    if not isinstance(layout, str) or not layout or len(layout) > 200:
        raise ValueError('Source layout name is invalid')
    for key in ('partyUnlockPos', 'unlockPos'):
        p = position(published.get('euiPositions', {}).get(key))
        if p:
            positions[key] = p
    result = dict(revision=2, layoutName=layout, cvars=cvars, chatFontSize=float(font[1]), chat=chat, euiPositions=positions)
    if type(published.get('presetLayout')) is int and published['presetLayout'] in (1, 2):
        result['presetLayout'] = published['presetLayout']
    native = published.get('nativeLayout')
    if isinstance(native, str) and 0 < len(native) <= 2 * 1024 * 1024:
        result['nativeLayout'] = native
    return result


def refresh(game, dry_run=False, before_publish=None):
    game = Path(game).resolve()
    cfg = read_config(game)
    if cfg is None:
        return False
    defaults = build(cfg) if cfg['enabled'] else None
    metadata = {k: cfg[k] for k in ('enabled', 'key')}
    metadata.update(character=cfg['sourceCharacter'], realmName=cfg['sourceRealmName'])
    addon = game / 'Interface/AddOns/CharacterUIBaseline'
    if not addon.resolve().is_relative_to((game / 'Interface/AddOns').resolve()) or not addon.is_dir():
        raise ValueError('CharacterUIBaseline addon directory is unavailable')
    outputs = {
        addon / 'Source.local.lua': ('local _, baseline = ...\nbaseline.source = ' + lua_value(metadata) + '\n').encode('utf-8'),
    }
    if defaults is not None:
        outputs = {addon / 'Baseline.lua': ('local _, baseline = ...\nlocal defaults = ' + lua_value(defaults)
            + '\nfor key, value in pairs(defaults) do baseline[key] = value end\n').encode('utf-8'), **outputs}
    previous = {path: path.read_bytes() if path.exists() else None for path in outputs}
    changed = {p: data for p, data in outputs.items() if previous[p] != data}
    if not changed or dry_run:
        return bool(changed)
    if before_publish:
        before_publish()
    if read_config(game) != cfg:
        raise ValueError('UI source configuration changed during refresh')
    backup = game / 'addon-backups' / ('ui-baseline-refresh-' + datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S-') + uuid.uuid4().hex[:8])
    backup.mkdir(parents=True)
    for path in outputs:
        if previous[path] is not None:
            (backup / path.name).write_bytes(previous[path])
    written = []
    try:
        for path, data in changed.items():
            if (path.read_bytes() if path.exists() else None) != previous[path]:
                raise ValueError('Generated baseline changed during refresh')
            written.append(path)
            atomic_bytes(path, data)
    except Exception:
        for path in reversed(written):
            if previous[path] is None:
                if path.exists():
                    path.unlink()
            else:
                atomic_bytes(path, previous[path])
        raise
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    game = args.game_root.resolve()
    try:
        require_game_closed(game)
        changed = refresh(game, dry_run=args.dry_run, before_publish=lambda: require_game_closed(game))
    except (SettingsError, OSError, ValueError, TypeError, KeyError, AttributeError, RecursionError):
        print('UI baseline refresh failed; check the private source configuration and source UI files.')
        return 1
    print('UI baseline refresh validated.' if args.dry_run else 'UI baseline refreshed.' if changed else 'UI baseline already current or not configured.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

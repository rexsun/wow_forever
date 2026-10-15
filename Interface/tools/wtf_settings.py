"""Parse approved WTF data without executing Lua; publish anonymous JSON snapshots."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import difflib
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import uuid


APPROVED_LUA = frozenset({
    "EllesmereUI.lua", "EllesmereUINameplates.lua", "EllesmereUIRaidFrames.lua",
    "EllesmereUIUnitFrames.lua", "YUI.lua", "GearInsight_Forever.lua",
})
APPROVED_CVARS = frozenset({
    "gxWindowedResolution", "gxMaximize", "gxWindow", "useUiScale", "uiScale",
    "cameraDistanceMaxZoomFactor", "nameplateMaxDistance", "targetNearestDistanceRadius",
    "outlineModeShowLootEffectWhenDisabled", "ffxGlow", "volumeFog", "ResampleAlwaysSharpen",
    "contrast", "brightness", "gamma", "Sound_MasterVolume", "Sound_MusicVolume",
    "Sound_SFXVolume", "Sound_AmbienceVolume", "Sound_DialogVolume",
})


class SettingsError(Exception):
    pass


class LuaParser:
    def __init__(self, text):
        self.text = text.lstrip("\ufeff")
        self.pos = 0

    def skip(self):
        while self.pos < len(self.text):
            match = re.match(r"\s+|--[^\r\n]*", self.text[self.pos:])
            if not match:
                return
            if self.text.startswith("--[", self.pos):
                long = re.match(r"--\[(=*)\[", self.text[self.pos:])
                if long:
                    end = self.text.find("]" + long[1] + "]", self.pos + len(long[0]))
                    if end < 0:
                        raise SettingsError("Unterminated Lua comment.")
                    self.pos = end + len(long[1]) + 2
                    continue
            self.pos += len(match[0])

    def accept(self, char):
        self.skip()
        if self.text.startswith(char, self.pos):
            self.pos += len(char)
            return True
        return False

    def require(self, char):
        if not self.accept(char):
            raise SettingsError("Unsupported saved-variable syntax.")

    def name(self):
        self.skip()
        match = re.match(r"[A-Za-z_][A-Za-z_0-9]*", self.text[self.pos:])
        if not match:
            raise SettingsError("Expected a saved-variable name.")
        self.pos += len(match[0])
        return match[0]

    def string(self):
        quote = self.text[self.pos]
        self.pos += 1
        out = bytearray()
        escapes = {"a": "\a", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v", "\\": "\\", '"': '"', "'": "'"}
        while self.pos < len(self.text):
            char = self.text[self.pos]
            self.pos += 1
            if char == quote:
                return bytes(out).decode('utf-8', errors='surrogateescape')
            if char == "\\":
                if self.pos >= len(self.text):
                    break
                char = self.text[self.pos]
                self.pos += 1
                if char.isdigit():
                    digits = char
                    while len(digits) < 3 and self.pos < len(self.text) and self.text[self.pos].isdigit():
                        digits += self.text[self.pos]
                        self.pos += 1
                    if int(digits) > 255:
                        raise SettingsError("Invalid Lua string escape.")
                    out.append(int(digits))
                    continue
                elif char in escapes:
                    char = escapes[char]
                elif char == "\r":
                    if self.pos < len(self.text) and self.text[self.pos] == "\n":
                        self.pos += 1
                    char = "\n"
                elif char != "\n":
                    raise SettingsError("Unsupported Lua string escape.")
            out.extend(char.encode('utf-8', errors='surrogateescape'))
        raise SettingsError("Unterminated Lua string.")

    def value(self, depth=0):
        if depth > 100:
            raise SettingsError("Saved-variable nesting is too deep.")
        self.skip()
        if self.pos >= len(self.text):
            raise SettingsError("Incomplete saved variables.")
        char = self.text[self.pos]
        if char in "\"'":
            return self.string()
        if self.accept("{"):
            result = {}
            index = 1
            while not self.accept("}"):
                if self.accept("["):
                    key = self.value(depth + 1)
                    if isinstance(key, bool) or not isinstance(key, (str, int, float)):
                        raise SettingsError("Unsupported Lua table key.")
                    self.require("]")
                    self.require("=")
                    value = self.value(depth + 1)
                else:
                    self.skip()
                    named = re.match(r"([A-Za-z_][A-Za-z_0-9]*)\s*=(?!=)", self.text[self.pos:])
                    if named:
                        key = named[1]
                        self.pos += len(named[0])
                    else:
                        key = index
                        index += 1
                    value = self.value(depth + 1)
                if key in result:
                    raise SettingsError("Duplicate saved-variable key.")
                if value is not None:
                    result[key] = value
                if self.accept(",") or self.accept(";"):
                    continue
                self.require("}")
                break
            return result
        number = re.match(r"-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)", self.text[self.pos:])
        if number:
            self.pos += len(number[0])
            token = number[0]
            value = int(token, 16) if "x" in token.lower() else float(token) if any(c in token.lower() for c in ".e") else int(token)
            if isinstance(value, float) and not math.isfinite(value):
                raise SettingsError("Non-finite saved-variable number.")
            return value
        literal = self.name()
        if literal not in {"true", "false", "nil"}:
            raise SettingsError("Executable Lua is not accepted.")
        return {"true": True, "false": False, "nil": None}[literal]

    def parse(self):
        result = {}
        while True:
            self.skip()
            if self.pos == len(self.text):
                return result
            name = self.name()
            self.require("=")
            if name in result:
                raise SettingsError("Duplicate saved-variable assignment.")
            result[name] = self.value()
            self.accept(";")


def parse_lua(text):
    return LuaParser(text).parse()


def json_text(value):
    return json.dumps(value, ensure_ascii=True, indent=2, allow_nan=False) + "\n"


def atomic_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".env.local-" if path.name == '.env' else ".write-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(text)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read_env(path):
    values = {}
    if not path.exists():
        return values
    reject_links(path)
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        match = re.fullmatch(r'(?:export\s+)?([A-Za-z_][A-Za-z_0-9]*)\s*=\s*(.*)', line)
        if not match or match[1] in values:
            raise SettingsError("Invalid or duplicate .env variable.")
        value = match[2].strip()
        if value.startswith('"'):
            try:
                value = json.loads(value)
            except ValueError:
                raise SettingsError("Invalid quoted .env value.") from None
            if not isinstance(value, str):
                raise SettingsError(".env values must be strings.")
        elif value.startswith("'"):
            if len(value) < 2 or not value.endswith("'"):
                raise SettingsError("Invalid quoted .env value.")
            value = value[1:-1]
        else:
            value = value.split(' #', 1)[0].rstrip()
        values[match[1]] = value
    return values


def load_aliases(game):
    values = read_env(Path(game) / 'Interface/.env')
    if values.get('WTF_MAP_VERSION') != '1':
        raise SettingsError("Restore/export requires a valid private Interface/.env alias mapping.")
    data = {'version': 1, 'strings': {}, 'numbers': {}}
    for key, value in values.items():
        match = re.fullmatch(r'WTF_(TEXT|NUMBER)_(\d{7})', key)
        if not match:
            if key.startswith(('WTF_TEXT_', 'WTF_NUMBER_')):
                raise SettingsError("Invalid alias variable name in .env.")
            continue
        name, prefix = ('strings', 'text') if match[1] == 'TEXT' else ('numbers', 'number')
        if value in data[name]:
            raise SettingsError("Duplicate alias value in .env.")
        data[name][value] = prefix + '-' + match[2]
    return data


def save_aliases(game, data):
    path = Path(game) / 'Interface/.env'
    tracked = subprocess.run(['git', '-C', str(game), 'ls-files', '--error-unmatch', '--', 'Interface/.env'], capture_output=True)
    ignored = subprocess.run(['git', '-C', str(game), 'check-ignore', '--no-index', '-q', '--', 'Interface/.env'], capture_output=True)
    if tracked.returncode == 0 or ignored.returncode != 0:
        raise SettingsError("Interface/.env must be untracked and ignored before saving private aliases.")
    values = read_env(path)
    values = {key: value for key, value in values.items() if not re.fullmatch(r'WTF_(TEXT|NUMBER)_\d{7}', key)}
    values['WTF_MAP_VERSION'] = '1'
    for name, prefix in (('strings', 'TEXT'), ('numbers', 'NUMBER')):
        for value, token in data[name].items():
            if not isinstance(token, str) or not re.fullmatch(('text' if name == 'strings' else 'number') + r'-\d{7}', token):
                raise SettingsError("Invalid alias token.")
            values['WTF_' + prefix + '_' + token.split('-')[1]] = value
    content = '# Private settings aliases. Keep this file out of Git.\n'
    content += ''.join(key + '=' + json.dumps(value, ensure_ascii=True) + '\n' for key, value in sorted(values.items()))
    atomic_text(path, content)


@contextmanager
def state_lock(state):
    state.mkdir(parents=True, exist_ok=True)
    lock = state / "export.lock"
    stream = lock.open("a+b")
    stream.seek(0, os.SEEK_END)
    if stream.tell() == 0:
        stream.write(b"0")
        stream.flush()
    stream.seek(0)
    try:
        if os.name == "nt":
            import msvcrt
            msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        stream.close()
        raise SettingsError("Another settings operation holds the private-state lock.") from None
    try:
        yield
    finally:
        stream.close()


class Aliases:
    def __init__(self, data):
        self.data = data

    def text(self, value):
        mapping = self.data["strings"]
        if value not in mapping:
            mapping[value] = f"text-{len(mapping) + 1:07d}"
        return mapping[value]

    def number(self, value):
        mapping = self.data["numbers"]
        key = json.dumps(value)
        if key not in mapping:
            mapping[key] = f"number-{len(mapping) + 1:07d}"
        return {"$number": mapping[key]}

    def encode(self, value):
        if isinstance(value, str):
            return {"$text": self.text(value)}
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            return self.number(value)
        if isinstance(value, dict):
            entries = []
            for key, item in value.items():
                entries.append({"key": self.encode(key), "value": self.encode(item)})
            entries.sort(key=lambda item: json.dumps(item["key"], sort_keys=True))
            return {"$table": entries}
        return value


def reject_links(path):
    if path.is_symlink() or path.is_junction():
        raise SettingsError("Linked settings or private-state paths are not supported.")


def approved_inventory(wtf):
    return {p for p in wtf.rglob("*") if p.is_file() and (p.name in APPROVED_LUA or p == wtf / "Config.wtf")}


def export_settings(game, state, dry_run=False, before_publish=None):
    game, state = Path(game).resolve(), Path(state).absolute()
    output = game / "Interface/Settings/WTF"
    for path in (state, *state.parents, output, output.parent):
        reject_links(path)
    if state == game or game in state.parents:
        raise SettingsError("The private alias map must be outside the game repository.")
    with state_lock(state):
        map_path = game / "Interface/.env"
        if output.exists() and not map_path.exists():
            raise SettingsError("Existing snapshots require their original private alias map.")
        data = load_aliases(game) if map_path.exists() else {"version": 1, "strings": {}, "numbers": {}}
        if data.get("version") != 1 or not isinstance(data.get("strings"), dict) or not isinstance(data.get("numbers"), dict):
            raise SettingsError("Unsupported private alias map.")
        for field, prefix in (("strings", "text"), ("numbers", "number")):
            tokens = list(data[field].values())
            if len(set(tokens)) != len(tokens) or any(not isinstance(token, str) or not re.fullmatch(prefix + r"-\d{7}", token) for token in tokens):
                raise SettingsError("Invalid private alias map.")
        aliases = Aliases(data)
        if output.exists():
            reverse = {name: {v: k for k, v in data[name].items()} for name in ('strings', 'numbers')}
            for snapshot in output.rglob('*.json'):
                reject_links(snapshot)
                restore_decode(json.loads(snapshot.read_bytes()), reverse)
                if any(part.startswith('text-') and part not in reverse['strings'] for part in snapshot.relative_to(output).parts):
                    raise SettingsError("Existing snapshots require their complete original .env mapping.")
        wtf = game / "WTF"
        if not wtf.is_dir():
            raise SettingsError("WTF directory is missing.")
        reject_links(wtf)
        snapshots = {}
        observed = {}
        for folder, directories, files in os.walk(wtf, followlinks=False):
            directories.sort()
            for name in directories:
                reject_links(Path(folder) / name)
            for name in sorted(files):
                path = Path(folder) / name
                if name not in APPROVED_LUA and path != wtf / "Config.wtf":
                    continue
                reject_links(path)
                raw = path.read_bytes()
                observed[path] = raw
                text = raw.decode("utf-8-sig")
                if path == wtf / "Config.wtf":
                    values = {}
                    for line in text.splitlines():
                        match = re.fullmatch(r'\s*SET\s+(\w+)\s+"([^"\r\n]*)"\s*', line)
                        if match and match[1] in APPROVED_CVARS:
                            values[match[1]] = match[2]
                    relative = Path("global/Config.json")
                else:
                    values = parse_lua(text)
                    parts = path.relative_to(wtf).parts[:-1]
                    anonymous = [part if part in {"Account", "SavedVariables"} else aliases.text(part) for part in parts]
                    relative = Path("scopes", *anonymous, path.stem + ".json")
                snapshots[relative] = json_text(aliases.encode(values))
        if not snapshots:
            raise SettingsError("No approved settings were found.")
        if approved_inventory(wtf) != set(observed) or any(path.read_bytes() != raw for path, raw in observed.items()):
            raise SettingsError("WTF changed during export; retry after the game exits.")
        if before_publish:
            before_publish()
        if dry_run:
            return len(snapshots)
        output.parent.mkdir(parents=True, exist_ok=True)
        staging = Path(tempfile.mkdtemp(prefix=".wtf-stage.local-", dir=output.parent))
        backup = staging.with_name(staging.name + "-backup")
        published = False
        try:
            for relative, contents in snapshots.items():
                destination = staging / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_text(contents, encoding="utf-8", newline="\n")
            save_aliases(game, data)
            if before_publish:
                before_publish()
            if approved_inventory(wtf) != set(observed) or any(path.read_bytes() != raw for path, raw in observed.items()):
                raise SettingsError("WTF changed during export; retry after the game exits.")
            if output.exists():
                if not output.is_dir():
                    raise SettingsError("Snapshot target must be a directory.")
                if any(p.is_symlink() or p.is_junction() for p in output.rglob("*")):
                    raise SettingsError("Snapshot target contains linked paths.")
                output.rename(backup)
            try:
                staging.rename(output)
                published = True
            except OSError:
                if backup.exists():
                    backup.rename(output)
                raise
        finally:
            if staging.exists():
                shutil.rmtree(staging)
            if published and backup.exists():
                shutil.rmtree(backup)
        return len(snapshots)


def decode(value, reverse):
    if isinstance(value, dict):
        if "$text" in value:
            return reverse["strings"][value["$text"]]
        if "$number" in value:
            return json.loads(reverse["numbers"][value["$number"]])
        if "$table" in value:
            return [{"key": decode(entry["key"], reverse), "value": decode(entry["value"], reverse)} for entry in value["$table"]]
    return value


def restore_decode(value, reverse, depth=0):
    if depth > 100:
        raise SettingsError("Snapshot nesting is too deep.")
    if value is None or isinstance(value, bool):
        return value
    if not isinstance(value, dict) or len(value) != 1:
        raise SettingsError("Snapshot contains unaliased or unsupported data.")
    try:
        if "$text" in value:
            decoded = reverse["strings"][value["$text"]]
            if not isinstance(decoded, str):
                raise SettingsError("Invalid text alias.")
            return decoded
        if "$number" in value:
            decoded = json.loads(reverse["numbers"][value["$number"]])
            if isinstance(decoded, bool) or not isinstance(decoded, (int, float)) or not math.isfinite(decoded):
                raise SettingsError("Invalid numeric alias.")
            return decoded
        if "$table" in value and isinstance(value["$table"], list):
            result = {}
            for entry in value["$table"]:
                if not isinstance(entry, dict) or set(entry) != {"key", "value"}:
                    raise SettingsError("Invalid snapshot table entry.")
                key = restore_decode(entry["key"], reverse, depth + 1)
                if isinstance(key, bool) or not isinstance(key, (str, int, float)) or key in result:
                    raise SettingsError("Invalid or duplicate snapshot table key.")
                result[key] = restore_decode(entry["value"], reverse, depth + 1)
            return result
    except (KeyError, TypeError, ValueError, OverflowError):
        raise SettingsError("Snapshot alias is missing or invalid in the private map.") from None
    raise SettingsError("Unsupported snapshot schema.")


def lua_value(value, depth=0):
    if isinstance(value, str):
        escaped = []
        for char in value:
            if char in {'"', '\\'}:
                escaped.append('\\' + char)
            elif ord(char) < 32 or ord(char) == 127:
                escaped.append('\\' + f"{ord(char):03d}")
            elif 0xDC80 <= ord(char) <= 0xDCFF:
                escaped.append('\\' + f"{ord(char) - 0xDC00:03d}")
            else:
                escaped.append(char)
        return '"' + ''.join(escaped) + '"'
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        if not math.isfinite(value):
            raise SettingsError("Non-finite Lua number.")
        return repr(value)
    if isinstance(value, dict):
        indent = '\t' * depth
        entries = []
        for key in sorted(value, key=lambda key: (isinstance(key, str), str(key))):
            entries.append(indent + '\t[' + lua_value(key) + '] = ' + lua_value(value[key], depth + 1) + ',\n')
        return '{\n' + ''.join(entries) + indent + '}'
    raise SettingsError("Unsupported decoded Lua value.")


def serialize_lua(values):
    keywords = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while'}
    if not isinstance(values, dict) or any(not isinstance(name, str) or not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", name) or name in keywords for name in values):
        raise SettingsError("Invalid saved-variable global name.")
    text = ''.join(name + ' = ' + lua_value(values[name]) + '\n' for name in sorted(values))
    if parse_lua(text) != values:
        raise SettingsError("Restored Lua failed its round-trip check.")
    return text


def atomic_bytes(path, content):
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".restore-")
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def validate_component(part):
    if not isinstance(part, str) or not part or part in {'.', '..'} or re.search(r'[<>:"/\\|?*\x00-\x1f]', part) or part.endswith((' ', '.')) or re.fullmatch(r'(?:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\..*)?', part, re.I):
        raise SettingsError("Unsafe mapped destination component.")
    return part


def checked_destination(wtf, relative):
    target = wtf / relative
    if not target.resolve().is_relative_to(wtf.resolve()):
        raise SettingsError("Restore destination escapes WTF.")
    for path in (target, *target.parents):
        reject_links(path)
        if path == wtf:
            break
    if not target.parent.is_dir():
        raise SettingsError("Mapped account or character folder is missing. Restore will not create another account.")
    if target.exists() and not target.is_file():
        raise SettingsError("Restore destination is not a regular file.")
    return target


def merge_config(original, values):
    if not isinstance(values, dict) or any(key not in APPROVED_CVARS or not isinstance(value, str) or re.search('["\r\n\x00]', value) for key, value in values.items()):
        raise SettingsError("Snapshot contains an unapproved CVar or invalid value.")
    if not values:
        return original if original is not None else b''
    text = original.decode('utf-8-sig') if original is not None else ''
    newline = '\r\n' if '\r\n' in text else '\n'
    replaced = set()
    lines = []
    for line in text.splitlines(keepends=True):
        match = re.match(r'^\s*SET\s+(\w+)\s+', line)
        if match and match[1] in values:
            key = match[1]
            if key not in replaced:
                lines.append(f'SET {key} "{values[key]}"' + newline)
                replaced.add(key)
        else:
            lines.append(line)
    if lines and not lines[-1].endswith(('\n', '\r')):
        lines[-1] += newline
    for key in sorted(values.keys() - replaced):
        lines.append(f'SET {key} "{values[key]}"' + newline)
    bom = b'\xef\xbb\xbf' if original and original.startswith(b'\xef\xbb\xbf') else b''
    return bom + ''.join(lines).encode('utf-8')


def restore_settings(game, state, dry_run=False, before_publish=None):
    game, state = Path(game).resolve(), Path(state).absolute()
    bundle = game / 'Interface/Settings/WTF'
    wtf = game / 'WTF'
    if state == game or game in state.parents:
        raise SettingsError("Private state must remain outside the repository.")
    for path in (state, *state.parents, bundle, bundle.parent, bundle.parent.parent, wtf):
        reject_links(path)
    if not bundle.is_dir() or not wtf.is_dir():
        raise SettingsError("Snapshot bundle or live WTF directory is missing.")
    with state_lock(state):
        map_path = game / 'Interface/.env'
        reject_links(map_path)
        if not map_path.is_file():
            raise SettingsError("Restore requires the original private alias map.")
        map_bytes = map_path.read_bytes()
        data = load_aliases(game)
        if data.get('version') != 1:
            raise SettingsError("Unsupported private alias map.")
        reverse = {}
        for name, prefix in (('strings', 'text'), ('numbers', 'number')):
            mapping = data.get(name)
            if not isinstance(mapping, dict) or any(not isinstance(token, str) or not re.fullmatch(prefix + r'-\d{7}', token) for token in mapping.values()) or len(set(mapping.values())) != len(mapping):
                raise SettingsError("Invalid private alias map.")
            reverse[name] = {v: k for k, v in mapping.items()}
        sources = {}
        plan = {}
        for source in sorted(bundle.rglob('*')):
            reject_links(source)
            if source.is_dir():
                continue
            parts = source.relative_to(bundle).parts
            raw = source.read_bytes()
            values = restore_decode(json.loads(raw), reverse)
            if parts == ('global', 'Config.json'):
                relative = Path('Config.wtf')
            else:
                if len(parts) not in {5, 7} or parts[:2] != ('scopes', 'Account') or parts[-2] != 'SavedVariables' or Path(parts[-1]).suffix != '.json':
                    raise SettingsError("Unrecognized snapshot path.")
                filename = Path(parts[-1]).stem + '.lua'
                if filename not in APPROVED_LUA:
                    raise SettingsError("Unapproved addon snapshot.")
                try:
                    components = [validate_component(reverse['strings'][part]) for part in parts[2:-2]]
                except KeyError:
                    raise SettingsError("Destination alias is missing from the private map.") from None
                relative = Path('Account', *components, 'SavedVariables', filename)
            target = checked_destination(wtf, relative)
            if target in plan:
                raise SettingsError("Multiple snapshots resolve to the same destination.")
            old = target.read_bytes() if target.exists() else None
            replacement = merge_config(old, values) if parts == ('global', 'Config.json') else serialize_lua(values).encode('utf-8')
            sources[source] = raw
            plan[target] = (relative, old, replacement)
        if not plan:
            raise SettingsError("The restore bundle is empty.")

        def validate_plan():
            if before_publish:
                before_publish()
            if map_path.read_bytes() != map_bytes or {p for p in bundle.rglob('*') if p.is_file()} != set(sources) or any(p.read_bytes() != raw for p, raw in sources.items()):
                raise SettingsError("Restore bundle or private map changed during validation.")
            for target, (relative, old, _) in plan.items():
                checked_destination(wtf, relative)
                actual = target.read_bytes() if target.exists() else None
                if actual != old:
                    raise SettingsError("Live WTF changed during restore validation.")

        validate_plan()
        if dry_run:
            return len(plan), None
        changed = {target: item for target, item in plan.items() if item[1] != item[2]}
        if not changed:
            return len(plan), None
        backup_root = state / 'backups'
        reject_links(backup_root)
        backup = backup_root / ('restore-' + datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8])
        backup.mkdir(parents=True)
        manifest = {'status': 'prepared', 'files': []}
        for target, (relative, old, replacement) in changed.items():
            if old is not None:
                saved = backup / relative
                saved.parent.mkdir(parents=True, exist_ok=True)
                saved.write_bytes(old)
            staged = backup / 'prepared' / relative
            staged.parent.mkdir(parents=True, exist_ok=True)
            staged.write_bytes(replacement)
            manifest['files'].append({'path': relative.as_posix(), 'existed': old is not None})
        atomic_text(backup / 'manifest.json', json_text(manifest))
        validate_plan()
        applied = []
        try:
            for target, (relative, old, replacement) in changed.items():
                if before_publish:
                    before_publish()
                checked_destination(wtf, relative)
                actual = target.read_bytes() if target.exists() else None
                if actual != old:
                    raise SettingsError("Live settings changed before replacement.")
                applied.append(target)
                atomic_bytes(target, replacement)
                if target.read_bytes() != replacement:
                    raise SettingsError("Restored file verification failed.")
            manifest['status'] = 'restored'
            atomic_text(backup / 'manifest.json', json_text(manifest))
        except BaseException:
            failed = False
            for target in reversed(applied):
                try:
                    relative, old, _ = changed[target]
                    checked_destination(wtf, relative)
                    if old is None:
                        target.unlink(missing_ok=True)
                    else:
                        atomic_bytes(target, old)
                except (OSError, SettingsError):
                    failed = True
            manifest['status'] = 'rollback-incomplete' if failed else 'rolled-back'
            atomic_text(backup / 'manifest.json', json_text(manifest))
            if failed:
                raise SettingsError("Restore failed and rollback is incomplete. Private backup: " + backup.name) from None
            raise SettingsError("Restore failed; live files were rolled back. Private backup: " + backup.name) from None
        return len(plan), backup


def readable_snapshot(output, state):
    data = load_aliases(Path(output).parents[2])
    reverse = {name: {v: k for k, v in data[name].items()} for name in ("strings", "numbers")}
    return "".join(str(p.relative_to(output)) + "\n" + json_text(decode(json.loads(p.read_text(encoding="utf-8")), reverse)) for p in sorted(Path(output).rglob("*.json")))


def review(game, state):
    data = load_aliases(game)
    reverse = {name: {v: k for k, v in data[name].items()} for name in ("strings", "numbers")}
    prefix = "Interface/Settings/WTF/"
    tracked = subprocess.run(["git", "-C", str(game), "ls-tree", "-r", "--name-only", "HEAD", "--", prefix], capture_output=True, text=True)
    current = {prefix + p.relative_to(game / prefix).as_posix(): p for p in (game / prefix).rglob("*.json")}
    for name in sorted(set(tracked.stdout.splitlines()) | set(current)):
        old = subprocess.run(["git", "-C", str(game), "show", "HEAD:" + name], capture_output=True, text=True, encoding="utf-8")
        old_text = json_text(decode(json.loads(old.stdout), reverse)) if old.returncode == 0 else ""
        new_text = json_text(decode(json.loads(current[name].read_text(encoding="utf-8")), reverse)) if name in current else ""
        print("".join(difflib.unified_diff(old_text.splitlines(True), new_text.splitlines(True), fromfile="HEAD/" + name, tofile="working/" + name)), end="")


def require_game_closed(game):
    if os.name != "nt":
        return
    env = dict(os.environ, WOW_SETTINGS_GAME_ROOT=str(game))
    command = "$ErrorActionPreference='Stop'; $root=$env:WOW_SETTINGS_GAME_ROOT; foreach($p in @(Get-CimInstance Win32_Process -Filter \"Name LIKE 'Wow%.exe'\")) { if(-not $p.ExecutablePath -or (Split-Path $p.ExecutablePath -Parent) -ieq $root) { exit 2 } }; exit 0"
    result = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", command], env=env, capture_output=True)
    if result.returncode != 0:
        raise SettingsError("Game closure could not be confirmed. Close WoW before changing settings files.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("export", "review", "restore"))
    parser.add_argument("--game-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--state", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    game = args.game_root.resolve()
    identity = hashlib.sha256(str(game).casefold().encode()).hexdigest()[:16]
    try:
        env_values = read_env(game / 'Interface/.env')
        configured_state = env_values.get('WTF_SETTINGS_STATE_DIR') or os.environ.get('WTF_SETTINGS_STATE_DIR')
        state = args.state or (Path(os.path.expandvars(configured_state)) if configured_state else Path(os.environ["LOCALAPPDATA"]) / "WowSettings" / identity)
        if args.mode == "review":
            review(game, state)
        elif args.mode == "restore":
            require_game_closed(game)
            count, backup = restore_settings(game, state, dry_run=args.dry_run, before_publish=lambda: require_game_closed(game))
            print(f"{'Validated' if args.dry_run else 'Restored'} {count} settings targets. Snapshot bundle and Git untouched.")
            if backup:
                print('Private backup: ' + backup.name)
        else:
            require_game_closed(game)
            count = export_settings(game, state, dry_run=args.dry_run, before_publish=lambda: require_game_closed(game))
            print(f"{'Validated' if args.dry_run else 'Exported'} {count} anonymous settings files. Git index and history untouched.")
    except (SettingsError, OSError, ValueError, KeyError, TypeError, RecursionError) as error:
        print(str(error) if isinstance(error, SettingsError) else "Settings operation failed; no private file paths or contents are logged.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

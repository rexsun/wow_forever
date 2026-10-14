"""Parse approved WTF data without executing Lua; publish anonymous JSON snapshots."""

import argparse
from contextlib import contextmanager
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


APPROVED_LUA = frozenset({
    "EllesmereUI.lua", "EllesmereUINameplates.lua", "EllesmereUIRaidFrames.lua",
    "EllesmereUIUnitFrames.lua", "YUI.lua", "RXPGuides.lua",
    "DungeonsForever.lua", "TalentsForeverBook.lua",
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
        out = []
        escapes = {"a": "\a", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v", "\\": "\\", '"': '"', "'": "'"}
        while self.pos < len(self.text):
            char = self.text[self.pos]
            self.pos += 1
            if char == quote:
                return "".join(out)
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
                    char = chr(int(digits))
                elif char in escapes:
                    char = escapes[char]
                elif char == "\r":
                    if self.pos < len(self.text) and self.text[self.pos] == "\n":
                        self.pos += 1
                    char = "\n"
                elif char != "\n":
                    raise SettingsError("Unsupported Lua string escape.")
            out.append(char)
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
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".write-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(text)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


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
        raise SettingsError("Another exporter holds the private-state lock.") from None
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
        map_path = state / "map.json"
        if output.exists() and not map_path.exists():
            raise SettingsError("Existing snapshots require their original private alias map.")
        data = json.loads(map_path.read_text(encoding="utf-8")) if map_path.exists() else {"version": 1, "strings": {}, "numbers": {}}
        if data.get("version") != 1 or not isinstance(data.get("strings"), dict) or not isinstance(data.get("numbers"), dict):
            raise SettingsError("Unsupported private alias map.")
        for field, prefix in (("strings", "text"), ("numbers", "number")):
            tokens = list(data[field].values())
            if len(set(tokens)) != len(tokens) or any(not isinstance(token, str) or not re.fullmatch(prefix + r"-\d{7}", token) for token in tokens):
                raise SettingsError("Invalid private alias map.")
        aliases = Aliases(data)
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
            atomic_text(map_path, json_text(data))
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


def readable_snapshot(output, state):
    data = json.loads((Path(state) / "map.json").read_text(encoding="utf-8"))
    reverse = {name: {v: k for k, v in data[name].items()} for name in ("strings", "numbers")}
    return "".join(str(p.relative_to(output)) + "\n" + json_text(decode(json.loads(p.read_text(encoding="utf-8")), reverse)) for p in sorted(Path(output).rglob("*.json")))


def review(game, state):
    data = json.loads((state / "map.json").read_text(encoding="utf-8"))
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
        raise SettingsError("Game closure could not be confirmed. Close WoW before exporting.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("export", "review"))
    parser.add_argument("--game-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--state", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    game = args.game_root.resolve()
    identity = hashlib.sha256(str(game).casefold().encode()).hexdigest()[:16]
    state = args.state or Path(os.environ["LOCALAPPDATA"]) / "WowSettings" / identity
    try:
        if args.mode == "review":
            review(game, state)
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

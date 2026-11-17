"""The running game: its process, whether it has focus, Fishing Key presses and relevant settings."""

from __future__ import annotations

import ctypes
import logging
import re
import threading
import time
from ctypes import wintypes
from pathlib import Path
from typing import Callable, Iterable

import psutil

log = logging.getLogger("splash-alert")

GAME_ROOT = Path(__file__).resolve().parents[3]
GAME_EXE = GAME_ROOT / "Wow.exe"
KEY_POLL_S = 0.005
KEY_DOWN = 0x8000
KEYS = {"delete": 0x2E, "backspace": 0x08}

_user32 = ctypes.WinDLL("user32")
_user32.GetForegroundWindow.restype = wintypes.HWND
_user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
_user32.GetAsyncKeyState.restype = ctypes.c_short
_user32.GetAsyncKeyState.argtypes = [ctypes.c_int]


def find_game_pid() -> int | None:
    """This installation's Wow.exe if it runs, otherwise any Wow.exe."""
    fallback = None
    for proc in psutil.process_iter(["pid", "name", "exe"]):
        if (proc.info["name"] or "").lower() != "wow.exe":
            continue
        exe = proc.info["exe"]
        if exe and Path(exe).resolve() == GAME_EXE.resolve():
            return proc.info["pid"]
        fallback = fallback or proc.info["pid"]
    return fallback


def is_running(pid: int) -> bool:
    try:
        return psutil.Process(pid).is_running()
    except psutil.NoSuchProcess:
        return False


def foreground_pid() -> int | None:
    hwnd = _user32.GetForegroundWindow()
    if not hwnd:
        return None
    pid = wintypes.DWORD()
    _user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    return pid.value or None


def parse_keys(names: Iterable[str]) -> list[int]:
    codes = []
    for name in names:
        key = name.strip().lower()
        if key not in KEYS:
            raise ValueError(f"unknown key {name!r}; choose from {', '.join(KEYS)}")
        codes.append(KEYS[key])
    return codes


def watch_keys(codes: list[int], game_pid: Callable[[], int | None],
               on_press: Callable[[float], None], stop: threading.Event) -> None:
    """Calls on_press(perf_counter time) when a key goes down while the game has focus. Only reads keys."""
    was_down = {code: False for code in codes}
    while not stop.is_set():
        for code in codes:
            down = bool(_user32.GetAsyncKeyState(code) & KEY_DOWN)
            if down and not was_down[code]:
                pid = game_pid()
                if pid is not None and foreground_pid() == pid:
                    on_press(time.perf_counter())
            was_down[code] = down
        time.sleep(KEY_POLL_S)


def warn_about_settings(config: Path = GAME_ROOT / "WTF" / "Config.wtf") -> None:
    try:
        text = config.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return
    match = re.search(r'^SET Sound_EnableSoundWhenGameIsInBG "(\d)"', text, re.MULTILINE | re.IGNORECASE)
    if not match or match.group(1) != "1":
        log.warning("The game mutes itself in the background. Turn on Settings > Audio > "
                    "'Sound in Background', or no splash is heard while you use another window.")

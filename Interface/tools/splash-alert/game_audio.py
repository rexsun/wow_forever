"""Tracks whether WoW runs and captures its audio only while a fishing line is out."""

from __future__ import annotations

import logging
import threading
import time
from typing import Callable

import numpy as np

from game import find_game_pid, is_running

log = logging.getLogger("splash-alert")

FIND_GAME_S = 2.0
WATCH_S = 0.25
RETRY_S = 5.0
JOIN_S = 2.0

Capture = Callable[[int, Callable[[float, np.ndarray], None], threading.Event], None]


class GameAudio:
    """Polls for the game every FIND_GAME_S; listen_until(t) opens (or extends) capture until time t."""

    def __init__(self, on_chunk: Callable[[float, np.ndarray], None], stop: threading.Event,
                 find_pid: Callable[[], int | None] = find_game_pid,
                 alive: Callable[[int], bool] = is_running,
                 capture: Capture | None = None,
                 clock: Callable[[], float] = time.perf_counter) -> None:
        self._on_chunk = on_chunk
        self._stop = stop
        self._find_pid = find_pid
        self._alive = alive
        if capture is None:
            # Imported here, on the caller's thread: importing comtypes initialises COM on the importing
            # thread, and a capture thread that did it first could no longer join the multithreaded apartment.
            from wasapi_capture import capture_process as capture
        self._capture_fn = capture
        self._clock = clock
        self._wake = threading.Event()
        self._until = 0.0
        self.pid: int | None = None
        self.capturing = False
        self._thread = threading.Thread(target=self._supervise, name="game-audio", daemon=True)

    def start(self) -> None:
        self._thread.start()

    def join(self, timeout: float | None = None) -> None:
        self._thread.join(timeout)

    def listen_until(self, t: float) -> None:
        self._until = max(self._until, t)
        self._wake.set()

    def _listening(self) -> bool:
        return self._clock() < self._until

    def _track_game(self) -> int | None:
        if self.pid is not None and self._alive(self.pid):
            return self.pid
        pid = self._find_pid()
        if pid != self.pid:
            if pid is None:
                log.info("WoW closed; waiting for it to start.")
            else:
                log.info("WoW is running (process %d); listening only while your line is out.", pid)
            self.pid = pid
        return pid

    def _supervise(self) -> None:
        log.info("Waiting for WoW to start...")
        while not self._stop.is_set():
            pid = self._track_game()
            if pid is not None and self._listening():
                error = self._capture(pid)
                if error and not self._stop.is_set():
                    log.error("%s; trying again in %.0f s.", error, RETRY_S)
                    self._stop.wait(RETRY_S)
                continue
            self._wake.wait(FIND_GAME_S)
            self._wake.clear()

    def _capture(self, pid: int) -> str | None:
        errors: list[str] = []
        capture_stop = threading.Event()

        def target() -> None:
            try:
                self._capture_fn(pid, self._on_chunk, capture_stop)
            except Exception as exc:  # noqa: BLE001 - report and keep supervising
                errors.append(str(exc) or type(exc).__name__)

        thread = threading.Thread(target=target, name="capture", daemon=True)
        log.debug("Capturing WoW's audio.")
        self.capturing = True
        thread.start()
        while (not self._stop.is_set() and thread.is_alive() and self._listening()
               and self._alive(pid)):
            self._stop.wait(WATCH_S)
        capture_stop.set()
        thread.join(JOIN_S)
        self.capturing = False
        log.debug("Stopped capturing.")
        return errors[0] if errors else None

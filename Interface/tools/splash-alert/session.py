"""Which sound events count: bites while your line is out (run) and splash samples (calibrate)."""

from __future__ import annotations

import logging
import threading
from collections import deque
from typing import Callable

from detector import Calibration, SoundEvent, similarity

log = logging.getLogger("splash-alert")

# Casting animation and the bobber landing come first; the Fishing channel lasts about 21 s.
LISTEN_DELAY_S = 1.5
LISTEN_WINDOW_S = 25.0
REACTION_S = 3.0
MIN_REACTION_S = 0.15
RECENT_EVENTS = 64


class BiteSession:
    """Each Fishing Key press opens a listening window; the first matching splash in it fires once."""

    def __init__(self, calibration: Callable[[], Calibration | None], on_bite: Callable[[], None],
                 on_key: Callable[[], None], on_uncalibrated: Callable[[], None] = lambda: None) -> None:
        """on_uncalibrated runs at the first cast without a calibration, and again only after one has loaded."""
        self._calibration = calibration
        self._on_bite = on_bite
        self._on_key = on_key
        self._on_uncalibrated = on_uncalibrated
        self._lock = threading.Lock()
        self._listen_from: float | None = None
        self._listen_until = 0.0
        self._fired = False
        self._told_uncalibrated = False

    def key_pressed(self, t: float) -> None:
        with self._lock:
            self._listen_from = t + LISTEN_DELAY_S
            self._listen_until = t + LISTEN_WINDOW_S
            self._fired = False
        self._on_key()
        if self._calibration() is not None:
            self._told_uncalibrated = False
            log.info("Line out; listening for a bite.")
        elif not self._told_uncalibrated:
            self._told_uncalibrated = True
            self._on_uncalibrated()

    def event(self, ev: SoundEvent) -> bool:
        cal = self._calibration()
        if cal is None:
            return False
        with self._lock:
            if self._fired or self._listen_from is None:
                return False
            if not self._listen_from <= ev.start <= self._listen_until:
                return False
            score = similarity(ev.profile, cal.template)
            loud = ev.peak_db >= cal.level_db
            alike = score >= cal.similarity
            log.debug("sound %.1f dB (needs %.1f), match %.2f (needs %.2f)",
                      ev.peak_db, cal.level_db, score, cal.similarity)
            if not (loud and alike):
                return False
            self._fired = True
        log.info("Bite! (%.1f dB, match %.2f)", ev.peak_db, score)
        self._on_bite()
        return True


class CalibrationSession:
    """Presses alternate cast and reel-in; the loudest sound just before a reel-in is a splash sample.

    A reel-in press with no sound before it is taken as a new cast, so a missed press realigns itself.
    """

    def __init__(self, wanted: int, on_sample: Callable[[SoundEvent, int], None],
                 on_cast: Callable[[bool], None]) -> None:
        self._wanted = wanted
        self._on_sample = on_sample
        self._on_cast = on_cast
        self._lock = threading.Lock()
        self._recent: deque[SoundEvent] = deque(maxlen=RECENT_EVENTS)
        self._cast_at: float | None = None
        self.samples: list[SoundEvent] = []
        self.done = threading.Event()

    def event(self, ev: SoundEvent) -> None:
        with self._lock:
            self._recent.append(ev)

    def key_pressed(self, t: float) -> None:
        with self._lock:
            if self.done.is_set():
                return
            sample = self._splash_before(t) if self._cast_at is not None else None
            if sample is None:
                missed = self._cast_at is not None
                self._cast_at = t
            else:
                self._cast_at = None
                self.samples.append(sample)
                count = len(self.samples)
                if count >= self._wanted:
                    self.done.set()
        if sample is None:
            self._on_cast(missed)
        else:
            self._on_sample(sample, count)

    def _splash_before(self, t: float) -> SoundEvent | None:
        earliest = max(t - REACTION_S, self._cast_at + LISTEN_DELAY_S)
        candidates = [e for e in self._recent if earliest <= e.start <= t - MIN_REACTION_S]
        return max(candidates, key=lambda e: e.peak_db) if candidates else None

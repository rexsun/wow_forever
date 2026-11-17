"""Which sound events count: bites while your line is out (run) and splash samples (calibrate)."""

from __future__ import annotations

import logging
import threading
from collections import deque
from typing import Callable

from detector import Calibration, SoundEvent, calibrate

log = logging.getLogger("splash-alert")

# Casting animation and the bobber landing come first; the Fishing channel lasts about 21 s.
LISTEN_DELAY_S = 1.5
LISTEN_WINDOW_S = 25.0
CHANNEL_S = 21.0
REACTION_S = 3.0
MIN_REACTION_S = 0.15
RECENT_EVENTS = 64
# A reel-in this soon after an alert means the alert was the bite you fished for.
LEARN_REACTION_S = 10.0
LEARN_SAMPLES = 3
# A bite comes in nearly every cast, so several channels running out unmatched mean the template misses.
SILENT_CASTS_NOTICE = 3


class BiteSession:
    """Each Fishing Key press opens a listening window; the first matching splash in it fires once.

    on_uncalibrated runs at the first press without a calibration, and again only after one has loaded.
    on_reeled gets the alert's sound when you press soon after it while the game's own sound is in use.
    on_silent runs when SILENT_CASTS_NOTICE casts in a row ran out with nothing matched.
    """

    def __init__(self, calibration: Callable[[], Calibration | None], on_bite: Callable[[], None],
                 on_key: Callable[[], None], on_uncalibrated: Callable[[], None] = lambda: None,
                 on_reeled: Callable[[SoundEvent], None] = lambda ev: None,
                 on_silent: Callable[[], None] = lambda: None) -> None:
        self._calibration = calibration
        self._on_bite = on_bite
        self._on_key = on_key
        self._on_uncalibrated = on_uncalibrated
        self._on_reeled = on_reeled
        self._on_silent = on_silent
        self._lock = threading.Lock()
        self._pressed_at: float | None = None
        self._listen_from: float | None = None
        self._listen_until = 0.0
        self._bite: SoundEvent | None = None
        self._best = float("-inf")
        self._told_uncalibrated = False
        self._silent_casts = 0

    def key_pressed(self, t: float) -> None:
        with self._lock:
            pressed_at, bite, best = self._pressed_at, self._bite, self._best
            self._pressed_at = t
            self._listen_from = t + LISTEN_DELAY_S
            self._listen_until = t + LISTEN_WINDOW_S
            self._bite = None
            self._best = float("-inf")
        self._on_key()
        cal = self._calibration()
        if cal is None:
            if not self._told_uncalibrated:
                self._told_uncalibrated = True
                self._on_uncalibrated()
            return
        self._told_uncalibrated = False
        self._review(cal, t, pressed_at, bite, best)
        log.info("Line out; listening for a bite.")

    def _review(self, cal: Calibration, t: float, pressed_at: float | None, bite: SoundEvent | None,
                best: float) -> None:
        if bite is not None:
            self._silent_casts = 0
            if cal.source == "game" and t - bite.start <= LEARN_REACTION_S:
                self._on_reeled(bite)
            return
        if pressed_at is None or t - pressed_at < CHANNEL_S:
            return
        closest = f"{best:.2f}" if best > float("-inf") else "none"
        log.info("No bite matched while the line was out (closest match %s, needs %.2f).", closest, cal.similarity)
        self._silent_casts += 1
        if self._silent_casts >= SILENT_CASTS_NOTICE:
            self._silent_casts = 0
            self._on_silent()

    def event(self, ev: SoundEvent) -> bool:
        cal = self._calibration()
        if cal is None:
            return False
        with self._lock:
            if self._bite is not None or self._listen_from is None:
                return False
            if not self._listen_from <= ev.start <= self._listen_until:
                return False
            score, decoy = cal.match(ev.profile)
            self._best = max(self._best, score)
            loud = cal.level_db is None or ev.peak_db >= cal.level_db
            alike = score >= cal.similarity and not decoy
            log.debug("sound %.1f dB (needs %s), match %.2f (needs %.2f)%s", ev.peak_db,
                      "any" if cal.level_db is None else f"{cal.level_db:.1f}", score, cal.similarity,
                      ", closer to another game sound" if decoy else "")
            if not (loud and alike):
                return False
            self._bite = ev
        log.info("Bite! (%.1f dB, match %.2f)", ev.peak_db, score)
        self._on_bite()
        return True


class SplashLearner:
    """Turns bites you reeled in into a calibration of your own splash, measured where you fish."""

    def __init__(self, on_learned: Callable[[Calibration], None], wanted: int = LEARN_SAMPLES) -> None:
        self._on_learned = on_learned
        self._wanted = wanted
        self._samples: list[SoundEvent] = []

    def add(self, ev: SoundEvent) -> None:
        self._samples = [*self._samples, ev][-self._wanted:]
        if len(self._samples) < self._wanted:
            log.info("Learning your splash: %d/%d bites.", len(self._samples), self._wanted)
            return
        try:
            cal = calibrate(self._samples, source="learned")
        except ValueError as exc:
            log.info("Not learned yet (%s); still listening.", exc)
            return
        self._samples = []
        self._on_learned(cal)


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

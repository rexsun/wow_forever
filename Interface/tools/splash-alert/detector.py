"""Splash detection on the game's audio: framing, sound events, spectral matching, calibration."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Sequence

import numpy as np

SAMPLE_RATE = 44100
FRAME = 1024
EVENT_FRAMES = 11
SILENCE_DB = -100.0
ONSET_DB = 12.0
MIN_EVENT_DB = -60.0
FLOOR_ALPHA = 0.05
TAIL_MAX_S = 2.0
GAP_RESET_S = 0.1
BAND_COUNT = 24
BAND_LOW_HZ = 150.0
BAND_HIGH_HZ = 11000.0
PROFILE_RANGE_DB = 40.0
LEVEL_MARGIN_DB = 6.0
SIMILARITY_SLACK = 0.1
SIMILARITY_RANGE = (0.6, 0.95)
MIN_SAMPLE_AGREEMENT = 0.5


@dataclass(frozen=True)
class SoundEvent:
    start: float
    peak_db: float
    profile: np.ndarray


@dataclass(frozen=True)
class Calibration:
    template: np.ndarray
    level_db: float
    similarity: float
    samples: int

    def to_json(self) -> dict:
        return {
            "template": [round(float(v), 6) for v in self.template],
            "level_db": round(self.level_db, 2),
            "similarity": round(self.similarity, 3),
            "samples": self.samples,
            "sample_rate": SAMPLE_RATE,
            "frame": FRAME,
            "bands": BAND_COUNT,
        }

    @classmethod
    def from_json(cls, data: dict) -> "Calibration":
        if (data.get("sample_rate"), data.get("frame"), data.get("bands")) != (SAMPLE_RATE, FRAME, BAND_COUNT):
            raise ValueError("calibration was made with different audio settings; calibrate again")
        template = np.asarray(data["template"], dtype=np.float64)
        if template.shape != (BAND_COUNT,):
            raise ValueError("calibration template has the wrong size; calibrate again")
        return cls(template, float(data["level_db"]), float(data["similarity"]), int(data["samples"]))


def frame_db(frame: np.ndarray) -> float:
    rms = float(np.sqrt(np.mean(np.square(frame, dtype=np.float64))))
    return max(SILENCE_DB, 20.0 * np.log10(rms + 1e-12))


def _band_bins() -> list[np.ndarray]:
    freqs = np.fft.rfftfreq(FRAME, 1.0 / SAMPLE_RATE)
    edges = np.geomspace(BAND_LOW_HZ, BAND_HIGH_HZ, BAND_COUNT + 1)
    return [np.nonzero((freqs >= lo) & (freqs < hi))[0] for lo, hi in zip(edges[:-1], edges[1:])]


_BANDS = _band_bins()
_WINDOW = np.hanning(FRAME)


def profile(frames: Sequence[np.ndarray]) -> np.ndarray:
    """Unit-length log band spectrum with its mean removed: the sound's shape, independent of loudness."""
    power = np.zeros(FRAME // 2 + 1)
    for frame in frames:
        power += np.abs(np.fft.rfft(frame * _WINDOW)) ** 2
    bands = 10.0 * np.log10(np.array([power[idx].sum() for idx in _BANDS]) + 1e-12)
    # Without a floor, near-silent bands dominate the shape and a pure tone resembles a splash.
    bands = np.maximum(bands, bands.max() - PROFILE_RANGE_DB)
    bands -= bands.mean()
    norm = np.linalg.norm(bands)
    return bands / norm if norm > 0 else bands


def similarity(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.dot(a, b))


class Framer:
    """Cuts timestamped mono chunks into fixed frames, each stamped with its first sample's time."""

    def __init__(self, on_frame: Callable[[float, np.ndarray], None]) -> None:
        self._on_frame = on_frame
        self._buffer = np.zeros(0, dtype=np.float32)
        self._start = 0.0

    def feed(self, chunk_time: float, samples: np.ndarray) -> None:
        expected = self._start + len(self._buffer) / SAMPLE_RATE
        if len(self._buffer) == 0 or abs(chunk_time - expected) > GAP_RESET_S:
            self._buffer = np.zeros(0, dtype=np.float32)
            self._start = chunk_time
        self._buffer = np.concatenate([self._buffer, samples.astype(np.float32, copy=False)])
        offset = 0
        while len(self._buffer) - offset >= FRAME:
            self._on_frame(self._start + offset / SAMPLE_RATE, self._buffer[offset:offset + FRAME])
            offset += FRAME
        self._buffer = self._buffer[offset:].copy()
        self._start += offset / SAMPLE_RATE


class EventDetector:
    """Turns frames into sound events: a rise of ONSET_DB over the noise floor, measured over EVENT_FRAMES."""

    def __init__(self, on_event: Callable[[SoundEvent], None]) -> None:
        self._on_event = on_event
        self._floor = SILENCE_DB
        self._frames: list[np.ndarray] = []
        self._levels: list[float] = []
        self._event_start = 0.0
        self._tail_until: float | None = None

    @property
    def floor_db(self) -> float:
        return self._floor

    def frame(self, t: float, samples: np.ndarray) -> None:
        db = frame_db(samples)
        if self._frames:
            self._collect(samples, db)
            return
        if self._tail_until is not None:
            # Wait out the sound's tail so one long sound is one event.
            if db < self._floor + ONSET_DB - 3.0 or t >= self._tail_until:
                self._tail_until = None
            return
        if db >= self._floor + ONSET_DB and db >= MIN_EVENT_DB:
            self._event_start = t
            self._collect(samples, db)
            return
        self._floor += FLOOR_ALPHA * (db - self._floor)

    def _collect(self, samples: np.ndarray, db: float) -> None:
        self._frames.append(samples.copy())
        self._levels.append(db)
        if len(self._frames) < EVENT_FRAMES:
            return
        event = SoundEvent(self._event_start, max(self._levels), profile(self._frames))
        self._frames, self._levels = [], []
        self._tail_until = event.start + TAIL_MAX_S
        self._on_event(event)


def calibrate(events: Sequence[SoundEvent]) -> Calibration:
    if not events:
        raise ValueError("no splashes recorded")
    profiles = np.array([e.profile for e in events])
    mean = profiles.mean(axis=0)
    template = mean / np.linalg.norm(mean)
    agreement = min(similarity(p, template) for p in profiles)
    if agreement < MIN_SAMPLE_AGREEMENT:
        raise ValueError(
            f"the recorded splashes sound too different from each other (agreement {agreement:.2f}); "
            "calibrate again away from other players, with music and ambience off"
        )
    lo, hi = SIMILARITY_RANGE
    threshold = min(hi, max(lo, agreement - SIMILARITY_SLACK))
    level = min(e.peak_db for e in events) - LEVEL_MARGIN_DB
    return Calibration(template, level, threshold, len(events))

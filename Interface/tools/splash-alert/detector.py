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
MAX_SHIFT_FRAMES = 2
CALIBRATION_FORMAT = 2
SOURCES = ("game", "learned", "calibrate")


@dataclass(frozen=True)
class SoundEvent:
    start: float
    peak_db: float
    profile: np.ndarray


@dataclass(frozen=True)
class Calibration:
    """level_db is None for the game's own sound: its loudness at your bobber is unknown until learned.

    decoys are profiles of other game sounds that resemble the splash; a sound closer to one is not a bite.
    """

    template: np.ndarray
    level_db: float | None
    similarity: float
    samples: int
    source: str = "calibrate"
    decoys: tuple[np.ndarray, ...] = ()

    def match(self, sound: np.ndarray) -> tuple[float, bool]:
        """The sound's similarity to the template, and whether it is closer to a decoy."""
        score = similarity(sound, self.template)
        return score, any(similarity(sound, decoy) > score for decoy in self.decoys)

    def to_json(self) -> dict:
        return {
            "format": CALIBRATION_FORMAT,
            "source": self.source,
            "template": _rows(self.template),
            "decoys": [_rows(decoy) for decoy in self.decoys],
            "level_db": None if self.level_db is None else round(self.level_db, 2),
            "similarity": round(self.similarity, 3),
            "samples": self.samples,
            "sample_rate": SAMPLE_RATE,
            "frame": FRAME,
            "bands": BAND_COUNT,
            "event_frames": EVENT_FRAMES,
        }

    @classmethod
    def from_json(cls, data: dict) -> "Calibration":
        settings = (data.get("format"), data.get("sample_rate"), data.get("frame"), data.get("bands"),
                    data.get("event_frames"))
        if settings != (CALIBRATION_FORMAT, SAMPLE_RATE, FRAME, BAND_COUNT, EVENT_FRAMES):
            raise ValueError("calibration was made with different audio settings")
        template = _profile_array(data["template"])
        decoys = tuple(_profile_array(decoy) for decoy in data.get("decoys", []))
        source = data.get("source")
        if source not in SOURCES:
            raise ValueError(f"unknown calibration source {source!r}")
        level = data["level_db"]
        return cls(template, None if level is None else float(level), float(data["similarity"]),
                   int(data["samples"]), source, decoys)


def _rows(m: np.ndarray) -> list[list[float]]:
    return [[round(float(v), 6) for v in row] for row in m]


def _profile_array(rows: list) -> np.ndarray:
    m = np.asarray(rows, dtype=np.float64)
    if m.shape != (EVENT_FRAMES, BAND_COUNT):
        raise ValueError("calibration profile has the wrong size")
    return m


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
    """Log band spectrum of each frame (frames x bands), unit length with its mean removed.

    Keeping the frames apart matches how the sound changes over time, not only its average spectrum:
    against a sample of the game's own sounds that rejects about ten times more non-splashes.
    """
    rows = []
    for frame in frames:
        power = np.abs(np.fft.rfft(frame * _WINDOW)) ** 2
        rows.append([power[idx].sum() for idx in _BANDS])
    bands = 10.0 * np.log10(np.asarray(rows, dtype=np.float64) + 1e-12)
    # Without a floor, near-silent bands dominate the shape and a pure tone resembles a splash.
    bands = np.maximum(bands, bands.max() - PROFILE_RANGE_DB)
    return _unit(bands)


def _unit(m: np.ndarray) -> np.ndarray:
    m = m - m.mean()
    norm = np.linalg.norm(m)
    return m / norm if norm > 0 else m


def similarity(a: np.ndarray, b: np.ndarray) -> float:
    """Best match over small time shifts, since an onset is found a frame or two earlier in a quieter scene."""
    rows = min(len(a), len(b))
    a, b = a[:rows], b[:rows]
    best = float(np.sum(a * b))
    for shift in range(1, min(MAX_SHIFT_FRAMES, rows - 1) + 1):
        for x, y in ((a[shift:], b[:-shift]), (a[:-shift], b[shift:])):
            best = max(best, float(np.sum(_unit(x) * _unit(y))))
    return best


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


def calibrate(events: Sequence[SoundEvent], source: str = "calibrate") -> Calibration:
    if not events:
        raise ValueError("no splashes recorded")
    profiles = np.array([e.profile for e in events])
    template = _unit(profiles.mean(axis=0))
    agreement = min(similarity(p, template) for p in profiles)
    if agreement < MIN_SAMPLE_AGREEMENT:
        raise ValueError(
            f"the recorded splashes sound too different from each other (agreement {agreement:.2f}); "
            "calibrate again away from other players, with music and ambience off"
        )
    lo, hi = SIMILARITY_RANGE
    threshold = min(hi, max(lo, agreement - SIMILARITY_SLACK))
    level = min(e.peak_db for e in events) - LEVEL_MARGIN_DB
    return Calibration(template, level, threshold, len(events), source)

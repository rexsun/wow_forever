"""The splash template taken from the game's own bite sound, so the alert works before any calibration."""

from __future__ import annotations

import io
import logging
from pathlib import Path

import numpy as np

from casc import Casc
from detector import SAMPLE_RATE, Calibration, EventDetector, Framer, SoundEvent
from game import GAME_ROOT

log = logging.getLogger("splash-alert")

# sound/spells/tradeskills/fishbite.ogg, the sound your bobber makes on a bite.
BITE_SOUND_FDID = 569816
# sound/spells/fishingbobber_ver2_1..3.ogg score about 0.7-0.8 against the bite, so they are told apart by
# which they resemble more.
DECOY_FDIDS = (569285, 568970, 569044)
# Measured on the game's own files: a bite 20 dB quieter or muffled still scores 0.75-0.8 (heavy background
# noise lowers it to about 0.65), while about 3.5% of 1,276 sounds sampled from the game reach 0.7.
GAME_SIMILARITY = 0.7
PADDING_S = 1.0
NOISE_FLOOR = 1e-4
CHUNK = 441


def flavor_product(game_root: Path = GAME_ROOT) -> str:
    lines = (game_root / ".flavor.info").read_text(encoding="utf-8").split()
    return lines[-1]


def decode(ogg: bytes) -> np.ndarray:
    import soundfile

    data, rate = soundfile.read(io.BytesIO(ogg), dtype="float32", always_2d=True)
    mono = data.mean(axis=1)
    if rate == SAMPLE_RATE:
        return mono
    count = int(len(mono) * SAMPLE_RATE / rate)
    return np.interp(np.arange(count) * rate / SAMPLE_RATE, np.arange(len(mono)), mono).astype(np.float32)


def first_event(sound: np.ndarray) -> SoundEvent:
    """Runs the sound through the live detector, so the template is cut exactly like a live event."""
    events: list[SoundEvent] = []
    framer = Framer(EventDetector(events.append).frame)
    padding = np.zeros(int(PADDING_S * SAMPLE_RATE), dtype=np.float32)
    signal = np.concatenate([padding, sound, padding])
    signal += NOISE_FLOOR * np.random.default_rng(0).standard_normal(len(signal)).astype(np.float32)
    for offset in range(0, len(signal), CHUNK):
        framer.feed(offset / SAMPLE_RATE, signal[offset:offset + CHUNK])
    if not events:
        raise ValueError("the game's bite sound produced no sound event")
    return events[0]


def game_calibration(game_root: Path = GAME_ROOT) -> Calibration:
    casc = Casc(game_root.parent, flavor_product(game_root))
    event = first_event(decode(casc.read_fdid(BITE_SOUND_FDID)))
    decoys = tuple(first_event(decode(casc.read_fdid(fdid))).profile for fdid in DECOY_FDIDS)
    log.info("Built the splash template from the game's bite sound (build %s).", casc.build_key)
    return Calibration(event.profile, None, GAME_SIMILARITY, 0, "game", decoys)

"""Run with: uv run --no-project --with numpy --with psutil python -m unittest discover -s tools/splash-alert"""

import json
import os
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from detector import (FRAME, LEVEL_MARGIN_DB, SAMPLE_RATE, Calibration, EventDetector, Framer,
                      SoundEvent, calibrate, frame_db, profile, similarity)
from game_audio import GameAudio
from session import LISTEN_DELAY_S, BiteSession, CalibrationSession
from splash_alert import CalibrationFile

RNG = np.random.default_rng(7)


def splash(seconds: float = 0.6, gain: float = 0.3) -> np.ndarray:
    """Band-limited noise burst with a fast attack and decay, like a water splash."""
    n = int(seconds * SAMPLE_RATE)
    spectrum = np.fft.rfft(RNG.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1 / SAMPLE_RATE)
    spectrum *= np.exp(-((np.log(freqs + 1) - np.log(1500)) ** 2) / 1.2)
    noise = np.fft.irfft(spectrum, n)
    noise /= np.max(np.abs(noise))
    return (gain * noise * np.exp(-np.linspace(0, 6, n))).astype(np.float32)


def tone(seconds: float = 0.6, hz: float = 440.0, gain: float = 0.3) -> np.ndarray:
    t = np.arange(int(seconds * SAMPLE_RATE)) / SAMPLE_RATE
    return (gain * np.sin(2 * np.pi * hz * t)).astype(np.float32)


def silence(seconds: float) -> np.ndarray:
    return (1e-4 * RNG.standard_normal(int(seconds * SAMPLE_RATE))).astype(np.float32)


def detect(signal: np.ndarray, start: float = 100.0, chunk: int = 441) -> list[SoundEvent]:
    events: list[SoundEvent] = []
    framer = Framer(EventDetector(events.append).frame)
    for offset in range(0, len(signal), chunk):
        framer.feed(start + offset / SAMPLE_RATE, signal[offset:offset + chunk])
    return events


class FramerTests(unittest.TestCase):
    def test_frames_carry_the_time_of_their_first_sample(self):
        frames = []
        framer = Framer(lambda t, f: frames.append((t, len(f))))
        framer.feed(10.0, np.zeros(700, np.float32))
        framer.feed(10.0 + 700 / SAMPLE_RATE, np.zeros(700, np.float32))
        self.assertEqual([(10.0, FRAME)], [(round(t, 9), n) for t, n in frames])

    def test_a_gap_in_the_stream_drops_the_partial_frame(self):
        frames = []
        framer = Framer(lambda t, f: frames.append(t))
        framer.feed(10.0, np.zeros(700, np.float32))
        framer.feed(20.0, np.zeros(FRAME, np.float32))
        self.assertEqual([20.0], frames)


class DetectorTests(unittest.TestCase):
    def test_a_splash_after_silence_is_one_event_at_its_onset(self):
        events = detect(np.concatenate([silence(1.0), splash(), silence(1.0)]))
        self.assertEqual(1, len(events))
        self.assertAlmostEqual(101.0, events[0].start, delta=FRAME / SAMPLE_RATE)
        self.assertGreater(events[0].peak_db, -35)

    def test_two_splashes_far_apart_are_two_events(self):
        signal = np.concatenate([silence(1.0), splash(), silence(3.0), splash(), silence(0.5)])
        self.assertEqual(2, len(detect(signal)))

    def test_quiet_noise_is_no_event(self):
        self.assertEqual([], detect(silence(3.0)))

    def test_shape_ignores_loudness_and_tells_splash_from_tone(self):
        a = profile([splash(0.1, 0.3)[:FRAME]])
        b = profile([splash(0.1, 0.03)[:FRAME]])
        c = profile([tone(0.1)[:FRAME]])
        self.assertGreater(similarity(a, b), 0.9)
        self.assertLess(similarity(a, c), 0.5)
        self.assertLess(similarity(a, profile([tone(0.1, hz=1500)[:FRAME]])), 0.5)

    def test_frame_db_of_full_scale_sine_is_about_minus_3(self):
        self.assertAlmostEqual(-3.0, frame_db(tone(0.1, gain=1.0)[:FRAME]), delta=0.2)


class CalibrationTests(unittest.TestCase):
    def test_consistent_splashes_set_level_and_threshold(self):
        events = [detect(np.concatenate([silence(1.0), splash(gain=g)]))[0] for g in (0.3, 0.2, 0.25)]
        cal = calibrate(events)
        self.assertAlmostEqual(min(e.peak_db for e in events) - LEVEL_MARGIN_DB, cal.level_db)
        self.assertTrue(0.6 <= cal.similarity <= 0.95)

    def test_round_trip_keeps_values(self):
        cal = calibrate([detect(np.concatenate([silence(1.0), splash()]))[0]])
        back = Calibration.from_json(cal.to_json())
        np.testing.assert_allclose(cal.template, back.template, atol=1e-5)
        self.assertAlmostEqual(cal.level_db, back.level_db, places=1)

    def test_unrelated_sounds_are_refused(self):
        events = [detect(np.concatenate([silence(1.0), s]))[0] for s in (splash(), tone(), tone(hz=3000))]
        with self.assertRaises(ValueError):
            calibrate(events)

    def test_other_audio_settings_are_refused(self):
        data = calibrate([detect(np.concatenate([silence(1.0), splash()]))[0]]).to_json()
        data["sample_rate"] = 48000
        with self.assertRaises(ValueError):
            Calibration.from_json(data)


def event(start: float, sound: np.ndarray) -> SoundEvent:
    return SoundEvent(start, frame_db(sound[:FRAME]), profile([sound[:FRAME]]))


class BiteSessionTests(unittest.TestCase):
    def setUp(self):
        self.bites, self.keys = [], []
        loud = event(0, splash())
        self.cal = Calibration(loud.profile, loud.peak_db - LEVEL_MARGIN_DB, 0.8, 1)
        self.session = BiteSession(lambda: self.cal, lambda: self.bites.append(1), lambda: self.keys.append(1))

    def test_nothing_fires_before_a_cast(self):
        self.assertFalse(self.session.event(event(5.0, splash())))

    def test_bite_fires_once_per_cast(self):
        self.session.key_pressed(0.0)
        self.assertTrue(self.session.event(event(8.0, splash())))
        self.assertFalse(self.session.event(event(9.0, splash())))
        self.session.key_pressed(10.0)
        self.assertTrue(self.session.event(event(15.0, splash())))
        self.assertEqual([1, 1], self.bites)
        self.assertEqual([1, 1], self.keys)

    def test_ignores_sounds_while_casting_and_after_the_line_ends(self):
        self.session.key_pressed(0.0)
        self.assertFalse(self.session.event(event(LISTEN_DELAY_S / 2, splash())))
        self.assertFalse(self.session.event(event(30.0, splash())))

    def test_ignores_distant_splashes_and_other_sounds(self):
        self.session.key_pressed(0.0)
        self.assertFalse(self.session.event(event(5.0, splash(gain=0.01))))
        self.assertFalse(self.session.event(event(6.0, tone())))
        self.assertEqual([], self.bites)

    def test_logs_each_cast_when_calibrated(self):
        with self.assertLogs("splash-alert", "INFO") as logs:
            self.session.key_pressed(0.0)
        self.assertIn("Line out", logs.output[0])


class UncalibratedTests(unittest.TestCase):
    def setUp(self):
        self.cal, self.told = None, []
        self.session = BiteSession(lambda: self.cal, lambda: None, lambda: None,
                                   on_uncalibrated=lambda: self.told.append(1))

    def test_tells_once_until_a_calibration_loads(self):
        self.session.key_pressed(0.0)
        self.session.key_pressed(30.0)
        self.assertEqual([1], self.told)
        self.assertFalse(self.session.event(event(35.0, splash())))

    def test_tells_again_when_the_calibration_is_lost(self):
        self.session.key_pressed(0.0)
        loud = event(0, splash())
        self.cal = Calibration(loud.profile, loud.peak_db - LEVEL_MARGIN_DB, 0.8, 1)
        self.session.key_pressed(30.0)
        self.cal = None
        self.session.key_pressed(60.0)
        self.assertEqual([1, 1], self.told)


class CalibrationSessionTests(unittest.TestCase):
    def setUp(self):
        self.casts, self.samples = [], []
        self.session = CalibrationSession(2, lambda ev, n: self.samples.append(n), self.casts.append)

    def test_records_the_splash_before_each_reel_in(self):
        self.session.key_pressed(0.0)
        self.session.event(event(6.0, splash(gain=0.05)))
        self.session.event(event(6.5, splash()))
        self.session.key_pressed(7.0)
        self.session.key_pressed(7.5)
        self.session.event(event(12.0, splash()))
        self.session.key_pressed(12.4)
        self.assertEqual([1, 2], self.samples)
        self.assertEqual(6.5, self.session.samples[0].start)
        self.assertTrue(self.session.done.is_set())

    def test_reel_in_without_a_sound_counts_as_a_new_cast(self):
        self.session.key_pressed(0.0)
        self.session.key_pressed(10.0)
        self.assertEqual([False, True], self.casts)
        self.assertEqual([], self.samples)

    def test_sounds_before_the_cast_are_not_samples(self):
        self.session.event(event(4.0, splash()))
        self.session.key_pressed(5.0)
        self.session.key_pressed(6.0)
        self.assertEqual([], self.samples)


def wait_for(condition, timeout: float = 2.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return True
        time.sleep(0.01)
    return False


class GameAudioTests(unittest.TestCase):
    def make(self, pid=42):
        self.starts, self.running = [], {pid}
        self.stop = threading.Event()

        def capture(p, on_chunk, stop):
            self.starts.append(p)
            stop.wait(5)

        audio = GameAudio(lambda t, s: None, self.stop,
                          find_pid=lambda: pid if pid in self.running else None,
                          alive=lambda p: p in self.running, capture=capture)
        audio.start()
        self.addCleanup(lambda: (self.stop.set(), audio.join(3)))
        return audio

    def test_tracks_the_game_without_capturing_before_a_cast(self):
        audio = self.make()
        self.assertTrue(wait_for(lambda: audio.pid == 42))
        time.sleep(0.3)
        self.assertEqual([], self.starts)

    def test_captures_only_for_the_listening_window(self):
        audio = self.make()
        self.assertTrue(wait_for(lambda: audio.pid == 42))
        audio.listen_until(time.perf_counter() + 0.5)
        self.assertTrue(wait_for(lambda: audio.capturing))
        self.assertTrue(wait_for(lambda: not audio.capturing))
        self.assertEqual([42], self.starts)

    def test_stops_capturing_when_the_game_closes(self):
        audio = self.make()
        self.assertTrue(wait_for(lambda: audio.pid == 42))
        audio.listen_until(time.perf_counter() + 30)
        self.assertTrue(wait_for(lambda: audio.capturing))
        self.running.clear()
        self.assertTrue(wait_for(lambda: not audio.capturing and audio.pid is None))

    def test_no_game_means_no_capture(self):
        audio = self.make(pid=None)
        audio.listen_until(time.perf_counter() + 30)
        time.sleep(0.3)
        self.assertEqual([], self.starts)


class CalibrationFileTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.path = Path(folder.name) / "calibration.local.json"
        self.file = CalibrationFile(self.path)
        self.data = calibrate([detect(np.concatenate([silence(1.0), splash()]))[0]]).to_json()

    def write(self, text: str, mtime: int) -> None:
        self.path.write_text(text, encoding="utf-8")
        os.utime(self.path, (mtime, mtime))

    def test_missing_file_is_not_calibrated(self):
        with self.assertLogs("splash-alert", "WARNING"):
            self.assertIsNone(self.file.refresh())

    def test_loads_and_reloads_when_the_file_changes(self):
        self.write(json.dumps(self.data), 1000)
        first = self.file.refresh()
        self.assertIsNotNone(first)
        self.assertIs(first, self.file.refresh())
        self.write(json.dumps({**self.data, "level_db": -1.0}), 2000)
        self.assertEqual(-1.0, self.file.refresh().level_db)

    def test_broken_file_is_not_calibrated(self):
        self.write("{not json", 1000)
        with self.assertLogs("splash-alert", "WARNING"):
            self.assertIsNone(self.file.refresh())


if __name__ == "__main__":
    unittest.main()

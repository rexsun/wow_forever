# /// script
# requires-python = ">=3.12"
# dependencies = ["numpy>=2", "comtypes>=1.4", "psutil>=6", "PySide6>=6.8"]
# ///
"""Splash Alert: flashes the screen when your fishing bobber splashes. It listens only; it never presses keys."""

from __future__ import annotations

import argparse
import ctypes
import json
import logging
import logging.handlers
import signal
import sys
import threading
from pathlib import Path
from typing import Callable

from detector import Calibration, EventDetector, Framer, SoundEvent, calibrate
from game import parse_keys, warn_about_settings, watch_keys
from game_audio import GameAudio
from session import LISTEN_WINDOW_S, BiteSession, CalibrationSession

log = logging.getLogger("splash-alert")

CALIBRATION_FILE = Path(__file__).with_name("calibration.local.json")
DEFAULT_KEYS = "delete,backspace"
MUTEX_NAME = "Local\\WoWSplashAlert"
ERROR_ALREADY_EXISTS = 183
LOG_BYTES = 1 << 20
NOT_CALIBRATED_TEXT = "🎣 Not calibrated"


class CalibrationFile:
    """Reloads the calibration when its file changes, so a running alert picks up a new calibration."""

    def __init__(self, path: Path = CALIBRATION_FILE) -> None:
        self._path = path
        self._mtime: float | None = None
        self.value: Calibration | None = None

    def refresh(self) -> Calibration | None:
        try:
            mtime = self._path.stat().st_mtime
        except FileNotFoundError:
            log.warning("Not calibrated yet; run: uv run splash_alert.py calibrate")
            self._mtime, self.value = None, None
            return None
        if mtime != self._mtime:
            self._mtime = mtime
            try:
                self.value = Calibration.from_json(json.loads(self._path.read_text(encoding="utf-8")))
                log.info("Calibration loaded.")
            except (OSError, ValueError, KeyError) as exc:
                self.value = None
                log.warning("%s is unusable (%s); run: uv run splash_alert.py calibrate", self._path.name, exc)
        return self.value


def _single_instance() -> None:
    """The mutex handle stays open, and the name taken, until the process exits."""
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.CreateMutexW.restype = ctypes.c_void_p
    handle = kernel32.CreateMutexW(None, False, MUTEX_NAME)
    if handle and ctypes.get_last_error() == ERROR_ALREADY_EXISTS:
        raise SystemExit("Splash Alert is already running.")


def _listen(audio: GameAudio, on_press: Callable[[float], None]) -> Callable[[float], None]:
    def pressed(t: float) -> None:
        audio.listen_until(t + LISTEN_WINDOW_S)
        on_press(t)
    return pressed


def _start_keys(keys: str, audio: GameAudio, on_press: Callable[[float], None], stop: threading.Event) -> None:
    codes = parse_keys(keys.split(","))
    threading.Thread(target=watch_keys, args=(codes, lambda: audio.pid, _listen(audio, on_press), stop),
                     name="keys", daemon=True).start()


def cmd_calibrate(args: argparse.Namespace) -> None:
    stop = threading.Event()

    def on_cast(missed: bool) -> None:
        if missed:
            log.info("No sound came before that press, so it counts as a new cast.")
        log.info("Line out. Press the Fishing Key as soon as you hear the splash.")

    def on_sample(ev: SoundEvent, count: int) -> None:
        log.info("Splash %d/%d recorded (%.1f dB). Cast again.", count, args.samples, ev.peak_db)

    cal_session = CalibrationSession(args.samples, on_sample, on_cast)
    detector = EventDetector(cal_session.event)
    audio = GameAudio(Framer(detector.frame).feed, stop)
    warn_about_settings()
    audio.start()
    _start_keys(args.keys, audio, cal_session.key_pressed, stop)
    log.info("Calibration: stand at your fishing spot away from other players, apply a lure first, "
             "and fish %d times with the Fishing Key (%s). Ctrl+C cancels.", args.samples, args.keys)
    try:
        while not cal_session.done.wait(0.2):
            pass
    except KeyboardInterrupt:
        stop.set()
        raise SystemExit("Calibration cancelled; nothing saved.") from None
    stop.set()
    try:
        cal = calibrate(cal_session.samples)
    except ValueError as exc:
        raise SystemExit(f"Calibration failed: {exc}.") from None
    CALIBRATION_FILE.write_text(json.dumps(cal.to_json(), indent=2) + "\n", encoding="utf-8")
    log.info("Saved %s: splashes louder than %.1f dB with a match of %.2f or more count as bites.",
             CALIBRATION_FILE.name, cal.level_db, cal.similarity)


def _qt_app():
    from PySide6.QtCore import QTimer
    from PySide6.QtWidgets import QApplication

    app = QApplication(sys.argv[:1])
    app.setQuitOnLastWindowClosed(False)
    signal.signal(signal.SIGINT, lambda *_: app.quit())
    # Qt's event loop blocks Python signal handling; a periodic no-op lets Ctrl+C through.
    keepalive = QTimer(app)
    keepalive.timeout.connect(lambda: None)
    keepalive.start(200)
    return app


def _style(args: argparse.Namespace):
    from overlay import OverlayStyle

    if not 0.0 <= args.opacity <= 1.0:
        raise SystemExit("--opacity must be between 0 and 1")
    if args.duration <= 0:
        raise SystemExit("--duration must be positive")
    return OverlayStyle(opacity=args.opacity, duration_s=args.duration)


def cmd_run(args: argparse.Namespace) -> None:
    from overlay import Overlay

    _single_instance()
    style = _style(args)
    cal_file = CalibrationFile()
    cal_file.refresh()
    app = _qt_app()
    overlay = Overlay(style)
    stop = threading.Event()

    def on_key() -> None:
        cal_file.refresh()
        overlay.dismiss.emit()

    # The log is out of sight while playing, so a missing calibration is also shown on screen.
    bite = BiteSession(lambda: cal_file.value, on_bite=overlay.show_bite.emit, on_key=on_key,
                       on_uncalibrated=lambda: overlay.show_message.emit(NOT_CALIBRATED_TEXT))
    detector = EventDetector(bite.event)
    audio = GameAudio(Framer(detector.frame).feed, stop)
    warn_about_settings()
    audio.start()
    _start_keys(args.keys, audio, bite.key_pressed, stop)
    log.info("Ready. Fish with the Fishing Key (%s); the screen flashes on a bite.", args.keys)
    try:
        app.exec()
    finally:
        stop.set()


def cmd_preview(args: argparse.Namespace) -> None:
    from PySide6.QtCore import QTimer

    from overlay import Overlay

    style = _style(args)
    app = _qt_app()
    overlay = Overlay(style)
    overlay.show_bite.emit()
    QTimer.singleShot(int(style.duration_s * 1000) + 300, app.quit)
    app.exec()


def _configure_logging(verbose: bool, log_file: Path | None) -> None:
    handler: logging.Handler
    if log_file:
        log_file.parent.mkdir(parents=True, exist_ok=True)
        handler = logging.handlers.RotatingFileHandler(log_file, maxBytes=LOG_BYTES, backupCount=1, encoding="utf-8")
    else:
        handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("%(asctime)s %(message)s", "%Y-%m-%d %H:%M:%S" if log_file else "%H:%M:%S"))
    logging.basicConfig(level=logging.INFO, handlers=[handler])
    # Only this tool's debug lines; comtypes logs every COM call at debug level.
    log.setLevel(logging.DEBUG if verbose else logging.INFO)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-v", "--verbose", action="store_true", help="log every sound heard while the line is out")
    parser.add_argument("--log-file", type=Path, help="write the log to this file instead of the console")
    sub = parser.add_subparsers(dest="command", required=True)

    def overlay_options(p: argparse.ArgumentParser) -> None:
        p.add_argument("--duration", type=float, default=3.0, help="seconds the overlay stays up (default 3)")
        p.add_argument("--opacity", type=float, default=0.2, help="background opacity 0-1 (default 0.2)")

    run = sub.add_parser("run", help="flash the screen on each bite")
    run.add_argument("--keys", default=DEFAULT_KEYS, help=f"Fishing Key(s) (default {DEFAULT_KEYS})")
    overlay_options(run)
    run.set_defaults(func=cmd_run)

    cal = sub.add_parser("calibrate", help="record your bobber's splash at your fishing spot")
    cal.add_argument("--keys", default=DEFAULT_KEYS, help=f"Fishing Key(s) (default {DEFAULT_KEYS})")
    cal.add_argument("--samples", type=int, default=3, help="splashes to record (default 3)")
    cal.set_defaults(func=cmd_calibrate)

    preview = sub.add_parser("preview", help="show the overlay once")
    overlay_options(preview)
    preview.set_defaults(func=cmd_preview)

    args = parser.parse_args(argv)
    _configure_logging(args.verbose, args.log_file)
    try:
        parse_keys(getattr(args, "keys", DEFAULT_KEYS).split(","))
    except ValueError as exc:
        parser.error(str(exc))
    if getattr(args, "samples", 1) < 1:
        parser.error("--samples must be at least 1")
    try:
        args.func(args)
    except SystemExit as exc:
        if isinstance(exc.code, str):
            log.error(exc.code)
            raise SystemExit(1) from None
        raise
    except Exception:
        log.exception("Splash Alert stopped unexpectedly")
        raise


if __name__ == "__main__":
    main()

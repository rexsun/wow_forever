# Splash Alert

Flashes a full-screen overlay when your fishing bobber splashes, so you can do something else while fishing. It only listens: it never presses keys, clicks, or reads or changes game memory. You still press the Fishing Key yourself.

## How it works

- **Game audio only, and only while your line is out.** It checks every 2 s whether `Wow.exe` runs, but records nothing until you press the Fishing Key in the game; capture then runs for 25 s after your last press and stops. It uses Windows 11 process loopback, so it hears only the game: videos, music or voice chat in other apps cannot trigger it. Windows hands over the game's mixed sound, not single sounds, so the splash is picked out of that by the next two rules.
- **Your cast only.** Each press of the Fishing Key (Delete or Backspace, counted only while WoW has focus) opens a 25-second listening window, starting 1.5 s after the press to skip the cast. The first matching splash fires once; the next press starts again and closes the overlay.
- **Your bobber only.** A sound counts when it is loud enough (your bobber is the closest) and its spectrum matches the splash recorded during calibration. Fainter splashes from players farther away, and other sounds, are ignored. A bobber landing right beside yours can still trigger it; then reel in and cast again.
- **Overlay.** A 20% black wash over every monitor with `🎣 Bite!` centred in Maple Mono NF CN at 64 pt, light blue (`#ADD8E6`). It is click-through, never takes focus, and closes after 3 s or when you press the Fishing Key. Points follow each monitor's DPI, so the text is the same physical size at 1080p, 1440p and 4K.

## Setup

1. In EllesmereUI → Forever Essentials, turn on **Fishing Key** and bind it to Delete or Backspace. Turn on **Fishing Sounds** so music, ambience and dialog are silent while fishing.
2. In the game's audio settings, turn on **Sound in Background** (`Sound_EnableSoundWhenGameIsInBG`); otherwise the game is silent while another window has focus. The tool warns at start-up if it is off.
3. Use **Windowed (Fullscreen)**, the game's default; exclusive fullscreen would draw over the overlay.
4. Calibrate at your fishing spot, away from other players, with a lure already applied:

   ```powershell
   cd "Interface\tools\splash-alert"
   uv run splash_alert.py calibrate
   ```

   Cast with the Fishing Key, and press it again as soon as you hear the splash; repeat three times. The tool saves `calibration.local.json` (ignored by Git). Calibrate again after changing game volume or if alerts are missed or false.

   Until then `run` cannot detect a bite: at your first cast it shows `🎣 Not calibrated` in the overlay instead (once, and again only if the calibration is later lost).

## Auto-start

```powershell
.\autostart.ps1 -Mode Install     # start now and at every sign-in, hidden
.\autostart.ps1 -Mode Status      # task state, calibration and the last log lines
.\autostart.ps1 -Mode Uninstall   # stop it and remove auto-start
```

A current-user sign-in task runs `splash_alert.vbs`, which starts `run` with no window and logs to `%LOCALAPPDATA%\SplashAlert\splash-alert.log` (1 MiB, one old copy kept). Each Fishing Key press it counts logs `Line out` (or `Not calibrated yet`), so a log with none after you fished means the key was not seen. Only one `run` can be active, so stop auto-start before a manual `run`; `calibrate` works alongside it, and the running copy picks up the new calibration at the next cast.

## Use

```powershell
uv run splash_alert.py run              # Ctrl+C quits
uv run splash_alert.py -v run           # also log every sound heard while the line is out
uv run splash_alert.py preview          # show the overlay once
```

`run` and `preview` take `--duration SECONDS` (default 3) and `--opacity 0-1` (default 0.2); `run` and `calibrate` take `--keys delete,backspace`. Requires Windows 11 (or Windows 10 build 20348+) and `uv`; uv installs Python 3.12+, numpy, comtypes, psutil and PySide6 on first run.

## Tests

```powershell
uv run --no-project --with numpy --with psutil python -m unittest discover -s tools/splash-alert
```

## Rules

The tool sends no input to the game; it is a notification, like a louder splash sound. It is a personal reading of the game's rules on unattended play, not an official ruling.

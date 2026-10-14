# Settings snapshots

`WTF/` under this directory is generated after the game exits. It is eligible for version control; the live game-root `WTF/` remains ignored. Newly generated snapshots are untracked until you manually add them.

The exporter never stages, commits or pushes. It never modifies live WTF.

## Operation

From the game's Interface directory, install and immediately start the current-user sign-in task:

```powershell
.\watch_wtf_settings.ps1 -Mode Install
```

Alternatively run the watcher in a terminal, stopping it with Ctrl+C:

```powershell
.\watch_wtf_settings.ps1 -Mode Watch
```

The watcher polls every two seconds. It observes only WoW executables directly in this installation, waits until all of them have exited, then requires six seconds without WTF file changes. A restart during export defers the snapshot. Starting the watcher while the game is closed exports one baseline. Failed exports retry after 30 seconds and preserve the previous snapshot. Duplicate watcher instances are prevented.

Manual export or validation, with the game closed:

```powershell
.\watch_wtf_settings.ps1 -Mode Export
.\watch_wtf_settings.ps1 -Mode Export -DryRun
```

Review readable changes against HEAD locally:

```powershell
.\watch_wtf_settings.ps1 -Mode Review
git diff -- Settings/WTF
git status --short -- Settings/WTF
```

Review resolves private aliases, so its terminal output can contain your identifiers. Keep that output local. Ordinary Git diffs contain aliases. After reviewing, stage and commit explicitly:

```powershell
git add -- Settings/WTF
git commit -m "Update interface settings"
```

Remove the sign-in task without deleting settings or the private map:

```powershell
.\watch_wtf_settings.ps1 -Mode Uninstall
```

## Privacy and coverage

All strings, including setting keys, profile labels and directory identifiers, become stable `text-*` aliases. All numeric keys and values become `number-*` aliases, so an unexpected numeric identifier cannot leak through an unknown field. Booleans remain visible. Local Review restores readable setting names and values. Lua is parsed as data and never executed. Anonymous JSON preserves table types and mixed keys; it is a review artifact, not a Lua file for the game to load.

The private reverse map and watcher log are stored in `%LOCALAPPDATA%\WowSettings\<installation-hash>\`, outside this repository. Keep a private backup of `map.json`; do not share or commit it. Losing it prevents consistent exports and readable review of existing snapshots. Moving the installation changes its hash: transfer the original private map to the new installation's private-state directory before exporting. Repeated values remain linkable across snapshots, and the map provides reversibility; this is pseudonymization, not encryption.

The approved files are EllesmereUI, its three modular frame/nameplate saved files, YUI, RXPGuides, DungeonsForever and TalentsForeverBook. An explicit CVar allowlist includes display resolution, UI scale, camera/nameplate preferences, display effects and sound volumes. Other addons, Blizzard data, macros, keybindings, backups, logs and arbitrary Config.wtf fields are excluded. Profile selection and addon settings in those approved Lua files are captured; they may also contain aliased runtime data that adds noise to diffs. File names still reveal which supported addons you use; stable aliases reveal when values repeat or change.

The exporter owns the complete generated `Settings/WTF/` directory and replaces it as a unit. Put hand-written documentation outside it. A private file lock serializes exports and releases automatically if the exporter exits or crashes. The old snapshot is restored on a failed replacement; if Windows also blocks rollback, the previous snapshot is retained in an ignored `.wtf-stage.local-*-backup` directory for recovery.

Windows PowerShell 5.1, `uv`, a uv-managed Python 3.13+ and Git are required. The installed task runs as the current user with limited privileges and a hidden window; no administrator elevation or password is requested. Logs contain generic status messages and rotate at 1 MiB. If a WoW process's executable path cannot be read, export waits rather than assuming closure.

`adopt_addons.ps1` still copies live WTF and therefore contains real account paths. Its existing behavior is appropriate for a private machine-to-machine transfer. Copying Interface includes these anonymous snapshots, but does not install the watcher task, copy its external private map or restore snapshots into live WTF. Automatic restore is deliberately separate from exit capture.

## Verification

```powershell
uv run --no-project python tools/test_wtf_settings.py
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/wtf-watcher-tests.ps1
```

Fixture tests exercise privacy, repeatable output, parsing without Lua execution, previous-snapshot preservation, private-map validation, concurrency, review decoding and an unchanged Git index. PowerShell checks exercise session transitions, initial baseline, retry, settling and restart cancellation.

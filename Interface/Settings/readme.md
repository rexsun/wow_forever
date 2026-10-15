# Settings snapshots

`WTF/` under this directory is generated after the game exits. It is eligible for version control; the live game-root `WTF/` remains ignored. Newly generated snapshots are untracked until you manually add them.

The tool never stages, commits or pushes. Export leaves live WTF untouched; Restore changes only the represented approved live files.

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

## Restore the current bundle

With WoW closed, treat the files currently in `Interface/Settings/WTF` as the intended settings bundle:

```powershell
.\watch_wtf_settings.ps1 -Mode Restore -DryRun
.\watch_wtf_settings.ps1 -Mode Restore
```

Restore does not check out a commit or read HEAD. Select your desired snapshot files before running it. It resolves their aliases using `Interface/.env` and restores the original mapped account/character paths already present in this installation. Missing account/character folders, unsafe paths, missing aliases and invalid snapshot data fail before live writes. It does not guess a different account or profile destination.

Approved account-level addon files are restored with their shared configuration and profile definitions. Excluded character records, profile-to-character assignments and runtime data are preserved from the current live file, including excluded data nested inside profiles. This protection also applies to older, unfiltered snapshots: their excluded data is ignored, and legacy character-file snapshots are skipped. Missing addon files can be recreated inside existing account SavedVariables folders without resurrecting excluded historical data.

Within represented addon files, included configuration is replaced by the selected snapshot; omitted included settings are removed. Excluded live data is retained even beneath a profile absent from the selected bundle. Approved CVars represented in Config.json are merged into live Config.wtf; account information and other CVars are preserved. Files absent from the bundle are not deleted.

The command pauses a running scheduled watcher, holds its installation mutex, checks closure and stable writes, then restores under the private state lock. It resumes the task afterward without exporting a startup baseline over your selected bundle. If you run a foreground watcher, stop it with Ctrl+C before restoring. A previously stopped task remains stopped.

Before replacement, changed files and prepared replacements are backed up privately in `<state-directory>\backups\restore-<timestamp>-<id>`. A private manifest records which files existed. Failed writes trigger rollback, including removal of newly created files; incomplete rollback retains the backup and reports its identifier. Neither the selected snapshots nor Git are changed. DryRun validates destinations and data without modifying live files or creating restore backups.

## Private .env mappings

`Interface/.env` is ignored by Git; `.env.example` is the shareable format reference. Export generates the full private alias list. Preserve and privately back up this file. Replacing it with the example cannot recover existing snapshots.

```dotenv
WTF_MAP_VERSION=1
# Optional; otherwise locks/logs/backups stay under LocalAppData.
# WTF_SETTINGS_STATE_DIR='D:\Private\WowSettings'
# Illustrative aliases, not real mappings:
# WTF_TEXT_0000001="settingName"
# WTF_NUMBER_0000001="0.85"
```

PowerShell loads the optional state-directory environment variable. The helper reads the text/number mapping variables directly from the same .env file, rather than putting thousands of aliases into the Windows process environment. Double-quoted values use JSON escaping for quotes, backslashes and newlines; single-quoted values preserve backslashes literally. Variables are data, never shell code. Export preserves non-alias variables when updating the file.

Existing aliases were migrated from the former external map.json without changing snapshots. That old file remains a private historical backup; the tool now uses .env for all mappings. Moving the installation preserves the mappings if .env is copied privately; adjust any explicitly configured state directory for the destination. The optional state directory must be absolute and outside the game repository.

## Privacy and coverage

All strings, including setting keys, profile labels and directory identifiers, become stable `text-*` aliases. All numeric keys and values become `number-*` aliases, so an unexpected numeric identifier cannot leak through an unknown field. Booleans remain visible. Local Review restores readable setting names and values. Lua is parsed as data and never executed. Anonymous JSON preserves table types and mixed keys; it is a review artifact, not a Lua file for the game to load.

The private reverse map is now `Interface/.env`, excluded from Git. Logs, locks and restore backups default to `%LOCALAPPDATA%\WowSettings\<installation-hash>\`, outside this repository, with an optional override in .env. Losing .env prevents consistent exports, readable review and restore. Repeated values remain linkable across snapshots, and the map provides reversibility; this is pseudonymization, not encryption.

The approved account-level files are EllesmereUI, its three modular frame/nameplate saved files, YUI and GearInsight Forever. Character SavedVariables files are excluded entirely. An explicit CVar allowlist includes display resolution, UI scale, camera/nameplate preferences, display effects and sound volumes. Other addons, Blizzard data, standalone macros/keybindings, backups, logs and arbitrary Config.wtf fields are excluded. File names still reveal which supported addons you use; stable aliases reveal when values repeat or change.

The helper filters parsed data before assigning aliases:

- Shared UI profile definitions, layouts, fonts, scales, feature preferences and migration markers remain included. Named profiles and class/spec display configuration remain reusable settings; per-character profile assignments do not.
- Character, realm, class, race and faction database scopes and profileKeys are excluded. YUI gold, XP/session statistics, known flights, character installations, chat/input/whisper history, mail records and per-character console preferences are excluded. Only its reviewed global migration/schema markers, switch-prompt preference and settings-window scale are included. HUD spell-preview caches, action-bar runtime status and CPU diagnostics are excluded.
- EllesmereUI's last-character specialization cache, uninstall recovery records and login-version/patch-notification state are excluded. Shared spec-to-profile configuration and migration markers remain included.
- GearInsight uses a preference allowlist: collection toggle, minimap settings, leveling-panel visibility/position, key HUD/board visibility and position, key mode, and quest-group sharing/range/nameplate preferences. Character identities, progression, deaths, loot, plans, wishlists, generated macros, key sources/backups, upload payloads, social records and navigation/page state are excluded. Unknown GearInsight fields are excluded by default.

The next export removes previously captured excluded data from the current snapshot directory; it does not rewrite Git history or erase historical private aliases. Addon updates may still add real defaults and migrations. Review the filter when addon schemas change; this is a policy for the installed schemas, not a universal detector of arbitrary future character data.

The exporter owns the complete generated `Settings/WTF/` directory and replaces it as a unit. Put hand-written documentation outside it. A private file lock serializes exports and releases automatically if the exporter exits or crashes. The old snapshot is restored on a failed replacement; if Windows also blocks rollback, the previous snapshot is retained in an ignored `.wtf-stage.local-*-backup` directory for recovery.

Windows PowerShell 5.1, `uv`, a uv-managed Python 3.13+ and Git are required. The installed task runs as the current user with limited privileges and a hidden window; no administrator elevation or password is requested. Logs contain generic status messages and rotate at 1 MiB. If a WoW process's executable path cannot be read, export waits rather than assuming closure.

`adopt_addons.ps1` still copies live WTF and therefore contains real account paths. Its existing behavior is appropriate for a private machine-to-machine transfer. Copying Interface also copies .env and the snapshots, but does not install the watcher task or copy external logs/backups. Restore remains an explicit command, separate from exit capture.

## Verification

```powershell
uv run --no-project python tools/test_wtf_settings.py
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/wtf-watcher-tests.ps1
```

Fixture tests exercise privacy, repeatable output, safe parsing/serialization, .env mappings, unchanged source/index, selective Config merging, private backups, missing destinations, restart refusal and rollback. PowerShell checks exercise session transitions, initial baseline, retry, settling, process filtering and restore's watcher suspension/resumption.

# Auto-update another machine from GitHub

[`Interface/sync_from_github.ps1`](Interface/sync_from_github.ps1) keeps a second installation on the repository's `main` branch. It runs hidden at every Windows sign-in.

Install it only on machines that consume the repository, because each sync force-resets the checkout to `origin/main`. Install refuses a checkout with uncommitted or unpushed work, or one where the settings export watcher task is installed.

## Set up the new machine

Do this once, with WoW closed:

1. Install Git and uv: `winget install --id Git.Git -e` and `winget install --id astral-sh.uv -e`. Restore needs Python 3.13 or newer under uv. If uv has none, Install and each sync install one with `uv python install 3.13`.
2. Start the game once and log in with the same account, so `WTF\Account\<account>` exists.
3. Copy `Interface\.env` privately from the main machine. Copying it by hand is fine. Copy it again whenever a sync logs "Copy Interface\.env from the main machine again": exports on the main machine add aliases that an older copy cannot decode.
4. Download the script and run it with Windows PowerShell 5.1:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/rexsun/wow_forever/main/Interface/sync_from_github.ps1 -OutFile .\sync_from_github.ps1
powershell -ExecutionPolicy Bypass -File .\sync_from_github.ps1 -Mode Install -GameRoot 'D:\...\World of Warcraft\_forever_'
```

If the game root is not a Git checkout yet, Install creates one:

- It moves the old `Interface` folder to `addon-backups\bootstrap-<timestamp>`.
- It copies the Git-ignored private files found in that old folder into the new `Interface`: `.env`, and the CharacterUIBaseline source configuration (`Settings/character-ui-source.local.json`, `AddOns/CharacterUIBaseline/Source.local.lua`) that an earlier adoption brought over. Later syncs leave these ignored files alone.
- It copies any tracked YUI font it is about to replace into the same backup.
- It leaves the rest of `Fonts`, the client and `WTF` alone.
- If anything fails, it rolls all of this back.

Install then registers the current-user task `WoWSync-<installation-hash>`. The task starts 30 seconds after sign-in, runs without elevation and opens no visible window. Install finishes by running one sync in the terminal.

If the game lives under `C:\Program Files`, grant your account Modify permission on the game root instead of running elevated. If Git reports that the folder is owned by another account, Install adds that one path to Git's `safe.directory`.

## What each sync does

1. Fetches `main`, retrying three times 30 seconds apart. If the machine is offline, it continues with the current checkout.
2. Waits for this installation's WoW to close, if it is running.
3. Moves the checkout to `origin/main`.
   - Edits to tracked files are first saved as `local-changes-<timestamp>.patch` in the private state directory.
   - Local commits are kept on a `sync-backup-<timestamp>` branch.
   - Addons removed upstream disappear along with their tracked files. Untracked and ignored files stay.
4. Restores `Interface/Settings/WTF` through `watch_wtf_settings.ps1 -Mode Restore`, but only when that folder changed since its last successful restore. Settings you change in game therefore survive until the bundle changes again. If `.env`, uv or the account folder is missing, the restore is skipped or fails with a hint, and the next sign-in retries it.
5. Fits the window to this machine. Like `adopt_addons.ps1 -Resolution`, it sets `gxWindowedResolution` and the EllesmereUI options-panel scale, and keeps the restored gameplay UI scale. The resolution comes from the first of these that applies:
   1. a fixed `-Resolution` given to Install (`Auto` clears it);
   2. the game's own setting, whenever it differs from what the script last wrote. This covers the first run and later in-game changes;
   3. the value last applied;
   4. the primary display's mode in physical pixels.

   Each value snaps to the largest supported size that fits: 1920x1080, 2560x1440 or 3840x2160. An ultrawide 3440x1440 display becomes 2560x1440.

## Maintenance

The private state directory `%LOCALAPPDATA%\WowSettings\<installation-hash>\` holds `sync.json` and the rotating `sync.log`. `sync.json` records the tool paths, the fixed resolution, the applied resolution and the last restored bundle.

```powershell
.\Interface\sync_from_github.ps1 -Mode Status
.\Interface\sync_from_github.ps1 -Mode Sync
.\Interface\sync_from_github.ps1 -Mode Install -Resolution 2560x1440
.\Interface\sync_from_github.ps1 -Mode Uninstall
```

Tests: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File Interface/tools/sync-from-github-tests.ps1`. The settings bundle itself is described in [Interface/Settings/readme.md](Interface/Settings/readme.md).

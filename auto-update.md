# Auto-update another machine from GitHub

[`Interface/sync_from_github.ps1`](Interface/sync_from_github.ps1) keeps a second installation on the repository's `main` branch. It runs hidden at every Windows sign-in.

Install it only on machines that consume the repository, because each sync force-resets the checkout to `origin/main`. Install refuses a checkout with uncommitted or unpushed work, or one where the settings export watcher task is installed.

## Set up the new machine

Do this once, with WoW closed:

1. Install Git and uv: `winget install --id Git.Git -e` and `winget install --id astral-sh.uv -e`. Restore needs Python 3.13 or newer under uv. If uv has none, Install and each sync install one with `uv python install 3.13`.
2. Start the game once and log in with the same account, so `WTF\Account\<account>` exists.
3. Copy `Interface\.env` privately from the main machine. Copying it by hand is fine. Exports on the main machine add aliases that an older copy cannot decode, so either copy it again whenever a sync logs "Copy Interface\.env from the main machine again", or let each sync fetch it over SSH (see [Fetch the alias map over SSH](#fetch-the-alias-map-over-ssh)).
4. Download the script and run it with Windows PowerShell 5.1:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/rexsun/wow_forever/main/Interface/sync_from_github.ps1 -OutFile .\sync_from_github.ps1
powershell -ExecutionPolicy Bypass -File .\sync_from_github.ps1 -Mode Install -GameRoot 'D:\...\World of Warcraft\_forever_'
```

If the game root is not a Git checkout yet, Install creates one:

- It keeps the Git data in `repo.git` in the private state directory (see [Maintenance](#maintenance)) and leaves only a one-line `.git` pointer file in the game root. Battle.net checks every file under the install, and Git writes its object files read-only. A `.git` folder in the game root fails that check, and Battle.net then repairs the game with repeated same-version updates.
- It moves the old `Interface` folder to `bootstrap-<timestamp>` in `WoW Addon Backups\<game folder>` beside the WoW install folder (for `D:\Program Files\World of Warcraft\_forever_` that is `D:\Program Files\WoW Addon Backups\_forever_`). Keeping backups outside the Battle.net install stops its file checks from scanning them. If your account can't create or write that folder, as under Blizzard's default `C:\Program Files (x86)`, backups go to `addon-backups` inside the game root instead. To keep them outside, have an administrator create the folder once and give your account Modify permission on it.
- It copies the Git-ignored private files found in that old folder into the new `Interface`: `.env`, and the CharacterUIBaseline source configuration (`Settings/character-ui-source.local.json`, `AddOns/CharacterUIBaseline/Source.local.lua`) that an earlier adoption brought over. Later syncs leave these ignored files alone.
- It copies any tracked YUI font it is about to replace into the same backup.
- It leaves the rest of `Fonts`, the client and `WTF` alone.
- If anything fails, it rolls all of this back.

Install then registers the current-user task `WoWSync-<installation-hash>`. The task starts 30 seconds after sign-in, runs without elevation and opens no visible window. Install finishes by running one sync in the terminal.

If the game root is already a checkout with a `.git` folder inside it, from before Install kept Git data outside, Install moves that folder to `repo.git` in the private state directory. Each sync does the same for older installations. The move copies first, checks that the checkout still points at the same commit, and only then deletes the old folder. If anything fails, `.git` stays where it was and the log says why.

If the game lives under `C:\Program Files`, grant your account Modify permission on the game root instead of running elevated. If Git reports that the folder is owned by another account, Install adds that one path to Git's `safe.directory`.

## What each sync does

1. Fetches `main`, retrying three times 30 seconds apart. If the machine is offline, it continues with the current checkout.
2. Waits for this installation's WoW to close, if it is running.
3. Moves the checkout to `origin/main`.
   - Edits to tracked files are first saved as `local-changes-<timestamp>.patch` in the private state directory.
   - Local commits are kept on a `sync-backup-<timestamp>` branch.
   - Addons removed upstream disappear along with their tracked files. Untracked and ignored files stay.
4. Restores `Interface/Settings/WTF` through `watch_wtf_settings.ps1 -Mode Restore`, but only when that folder changed since its last successful restore. Settings you change in game therefore survive until the bundle changes again. With `-EnvSource` set, the restore first fetches `Interface\.env` from the main machine. If `.env`, uv or the account folder is missing, the restore is skipped or fails with a hint, and the next sign-in retries it.
5. Fits the window to this machine. Like `adopt_addons.ps1 -Resolution`, it sets `gxWindowedResolution` and the EllesmereUI options-panel scale, and keeps the restored gameplay UI scale. The resolution comes from the first of these that applies:
   1. a fixed `-Resolution` given to Install (`Auto` clears it);
   2. the game's own setting, whenever it differs from what the script last wrote. This covers the first run and later in-game changes;
   3. the value last applied;
   4. the primary display's mode in physical pixels.

   Each value snaps to the largest supported size that fits: 1920x1080, 2560x1440 or 3840x2160. An ultrawide 3440x1440 display becomes 2560x1440.

## Fetch the alias map over SSH

The synced machine pulls the map itself, so it doesn't matter whether it was on when the map changed. It fetches only when a restore is pending.

1. On the synced machine, create a key without a passphrase. The hidden task cannot answer a prompt.

   ```powershell
   ssh-keygen -t ed25519 -N '""' -C wowsync -f $HOME\.ssh\wowsync_ed25519
   ```

2. On the main machine, run an OpenSSH server and authorize that public key with a forced command that prints the map as base64. Base64 is plain ASCII, so a PowerShell or cmd default shell cannot re-encode the UTF-8 file on its way out. Build the line like this:

   ```powershell
   $read = "`$ProgressPreference = 'SilentlyContinue'; [Convert]::ToBase64String([IO.File]::ReadAllBytes('D:\...\World of Warcraft\_forever_\Interface\.env'))"
   $command = 'powershell -NoProfile -NonInteractive -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($read))
   'restrict,command="' + $command + '" ' + (Get-Content .\wowsync_ed25519.pub)
   ```

   For an administrator account, this line goes in `%ProgramData%\ssh\administrators_authorized_keys`. Otherwise it goes in `~\.ssh\authorized_keys`. `restrict` turns off forwarding and terminals, and `command=` replaces whatever the client asks to run, so the key can do nothing but read the map.
3. On the synced machine, record the source once:

   ```powershell
   .\Interface\sync_from_github.ps1 -Mode Install -EnvSource user@main-host -EnvSourceKey $HOME\.ssh\wowsync_ed25519
   ```

Each fetch first checks that port 22 answers within 5 seconds, and `ssh` is stopped after 60 seconds, so a switched-off main machine costs the sync a few seconds. The fetched map replaces the local one only when it keeps every alias the local copy has, because the main machine only ever adds aliases. The replaced copy is saved as `env-<timestamp>.bak` in the private state directory, and the two newest are kept. A refused map, an unreachable source or a missing key is logged as `Interface\.env not refreshed`. The restore then runs with the local copy, and if that fails, the next sign-in tries again. The first connection records the source's host key. `-EnvSource off` turns fetching off.

## Maintenance

The private state directory `%LOCALAPPDATA%\WowSettings\<installation-hash>\` holds `sync.json`, the rotating `sync.log` and the checkout's Git data `repo.git`. Don't delete it while sync is installed: the game root's `.git` file points into it. `-Mode Status` shows where the Git data and backups are.

Every backup kind keeps only its two newest copies, and older ones are deleted:

- After each sync: `bootstrap-*` folders, `local-changes-*.patch`, `env-*.bak` and `sync-backup-*` branches.
- After each settings restore: `restore-*` folders in the state directory's `backups`.
- After each run of `adopt_addons.ps1` and `tools/character_ui_baseline.py refresh`: their own backup folders.

Folders with other names in the backup folder are never touched. `sync.json` records the tool paths, the fixed resolution, the applied resolution, the alias-map source and the last restored bundle.

```powershell
.\Interface\sync_from_github.ps1 -Mode Status
.\Interface\sync_from_github.ps1 -Mode Sync
.\Interface\sync_from_github.ps1 -Mode Install -Resolution 2560x1440
.\Interface\sync_from_github.ps1 -Mode Uninstall
```

Tests: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File Interface/tools/sync-from-github-tests.ps1`. The settings bundle itself is described in [Interface/Settings/readme.md](Interface/Settings/readme.md).

# WoW: Forever add-ons

Version control for the user interface of a **World of Warcraft: Forever** client (`wowf`). The repository root is the game's `_forever_` folder. Interface files, selected custom fonts and anonymous settings snapshots are eligible for version control. The game client, caches, logs and live `WTF` settings are ignored (see [.gitignore](.gitignore)).

## Game version

| | |
| --- | --- |
| Client | 1.60.1.70790 (`wowf`, region `us`) |
| Add-on interface | 16001 |

Every add-on here must declare Interface 16001 in its TOC and work on this client.

## Contents

- [Interface/AddOns/readme.md](Interface/AddOns/readme.md): YUI v338, modular EllesmereUI 9.4 frames/nameplates, RXPGuides and four specialist addons, with OverlapSettingsGuard. The frame and arrow setup has been reported working in-game; see the inventory for remaining caveats.
- [Interface/AddOns/updates-2026-Q4.md](Interface/AddOns/updates-2026-Q4.md): change log, one file per calendar quarter (`updates-YYYY-QN.md`), newest first. It covers installs, removals, setting changes and local patches, which upstream updates can overwrite. [Interface/CHANGELOG.md](Interface/CHANGELOG.md) links every quarter.
- [Interface/AGENTS.md](Interface/AGENTS.md): rules for maintaining the add-ons.
- [Interface/Settings/readme.md](Interface/Settings/readme.md): anonymous settings snapshots after game exit, with readable local review and manual Git staging/commits.
- [auto-update.md](auto-update.md): set up another machine to update its add-ons and settings from GitHub at every sign-in.

## Updating

Exit the game before replacing add-on folders. Record each change in the current quarter's `AddOns/updates-YYYY-QN.md` and keep `readme.md` in sync. Then commit.

The `ForeverUI` branch preserves the addon bundle before the 2026-10-10 replacement. Its saved settings are separately backed up in `addon-backups/foreverui-replacement-20261010-211803/WTF`; switching branches does not restore WTF.

## Moving to another display

Run the adoption utility from the source game root after closing WoW on both machines:

```powershell
.\Interface\adopt_addons.ps1 '\\destination\WoW\_forever_' -Resolution 1920x1080
```

The argument is the existing destination game root. The script copies Interface, WTF and Fonts from the source installation where it runs. Resolution also accepts 2560x1440 or 3840x2160. The script fits EUI's options window and sets the windowed resolution; it preserves gameplay UI scale, frame positions and fonts. Without Resolution it copies settings unchanged. Maximized mode uses the destination display's native resolution. Destination Interface/WTF are backed up before replacement, with rollback on failure. Source WTF is never modified.

EUI and YUI share Default with new characters. RestedXP uses a supported default template for new character profiles; guide progress, Blizzard keybindings and character-only layout settings remain separate. WTF is ignored by Git, so pulling this repository alone does not install the configured settings. Use the adoption utility with the same account, or transfer SavedVariables into the destination account folder.

## Keeping another machine in sync

[`Interface/sync_from_github.ps1`](Interface/sync_from_github.ps1) keeps a second installation on `main`. Install it once on that machine, with WoW closed:

```powershell
powershell -ExecutionPolicy Bypass -File .\sync_from_github.ps1 -Mode Install -GameRoot 'D:\...\World of Warcraft\_forever_'
```

Install turns the game root into a checkout if it isn't one yet, with its Git data outside the install, and registers a hidden current-user task `WoWSync-<installation-hash>` that runs at every sign-in. Each sync:

1. fetches `main` and waits for that installation's WoW to close;
2. force-resets the checkout to `origin/main`, saving tracked edits as a patch and local commits on a `sync-backup-<timestamp>` branch;
3. restores the `Interface/Settings/WTF` bundle when it changed (this needs `Interface\.env` from the main machine, copied by hand or fetched over SSH with `-EnvSource`);
4. fits the windowed resolution and EllesmereUI options scale to the display.

Use it only on machines that consume the repository: Install refuses a checkout with uncommitted or unpushed work, or one running the settings export watcher. `-Mode Status`, `-Mode Sync` and `-Mode Uninstall` show the state and log, run a sync now, and remove the task. The private state and log are in `%LOCALAPPDATA%\WowSettings\<installation-hash>\`.

Keep Git data and backups outside the install. Battle.net checks every file under `_forever_`, and Git writes its object files read-only. A `.git` folder in the game root fails that check ("Permissions check failure"), and Battle.net then repairs the game with repeated same-version updates.

- **Git data:** the script keeps it in `repo.git` in the private state folder, with only a `.git` pointer file in the game root. Install and every sync move an older in-game `.git` folder there.
- **Other checkouts:** on a machine without the sync, such as the one where add-ons are edited, move the Git data out by hand with `git init --separate-git-dir <folder outside the install>`.
- **Backups:** they go to `WoW Addon Backups\_forever_` beside the WoW install folder. If your account can't write there, as under `C:\Program Files (x86)`, they fall back to `addon-backups` inside the game root. To keep them outside, have an administrator create the folder once and give your account Modify permission on it.

[auto-update.md](auto-update.md) has the full setup, the SSH alias-map fetch and the maintenance commands.

## Release migration

The active project is now in `_forever_` for the installed `wowf` release build 1.60.1.70532 (Interface 16001). The beta copy is retained only as a migration source; use the release folder for subsequent edits and Git operations.

The 2026-10-23 migration carries Git history and uncommitted changes, the complete Interface (including private snapshot aliases and source configuration), live WTF and Fonts. Historical addon backups, diagnostics, utility files and private watcher state are preserved in `WoW Addon Backups/_forever_/beta-migration-20261023-141603/`, beside the WoW install folder (moved out of `_forever_/addon-backups/` on 2026-11-25). These private files stay outside version control. Client binaries and caches come from the release installation.

The beta settings watcher is removed and the release watcher uses the release installation path. Existing beta realm/character folders remain intact; release realms and characters may have different identities, so select the intended shared profiles and update the private source-character configuration if needed after first login. Migration and offline tests do not establish in-game compatibility or rendering at 1080p, 1440p and 4K.

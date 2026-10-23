# WoW: Forever add-ons

Version control for the user interface of a **World of Warcraft: Forever** client (`wowf`). The repository root is the game's `_forever_` folder. Interface files, selected custom fonts and anonymous settings snapshots are eligible for version control. The game client, caches, logs and live `WTF` settings are ignored (see [.gitignore](.gitignore)).

## Game version

| | |
| --- | --- |
| Client | 1.60.1.70532 (`wowf`, region `us`) |
| Add-on interface | 16001 |

Every add-on here must declare Interface 16001 in its TOC and work on this client.

## Contents

- [Interface/AddOns/readme.md](Interface/AddOns/readme.md): YUI v338, modular EllesmereUI 9.4 frames/nameplates, RXPGuides and four specialist addons, with OverlapSettingsGuard. The frame and arrow setup has been reported working in-game; see the inventory for remaining caveats.
- [Interface/AddOns/updates.md](Interface/AddOns/updates.md): change log, newest first. It covers installs, removals, setting changes and local patches, which upstream updates can overwrite.
- [Interface/AGENTS.md](Interface/AGENTS.md): rules for maintaining the add-ons.
- [Interface/Settings/readme.md](Interface/Settings/readme.md): anonymous settings snapshots after game exit, with readable local review and manual Git staging/commits.

## Updating

Exit the game before replacing add-on folders. Record each change in `updates.md` and keep `readme.md` in sync. Then commit.

The `ForeverUI` branch preserves the addon bundle before the 2026-10-10 replacement. Its saved settings are separately backed up in `addon-backups/foreverui-replacement-20261010-211803/WTF`; switching branches does not restore WTF.

## Moving to another display

Run the adoption utility from the source game root after closing WoW on both machines:

```powershell
.\Interface\adopt_addons.ps1 '\\destination\WoW\_forever_' -Resolution 1920x1080
```

The argument is the existing destination game root. The script copies Interface, WTF and Fonts from the source installation where it runs. Resolution also accepts 2560x1440 or 3840x2160. The script fits EUI's options window and sets the windowed resolution; it preserves gameplay UI scale, frame positions and fonts. Without Resolution it copies settings unchanged. Maximized mode uses the destination display's native resolution. Destination Interface/WTF are backed up before replacement, with rollback on failure. Source WTF is never modified.

EUI and YUI share Default with new characters. RestedXP uses a supported default template for new character profiles; guide progress, Blizzard keybindings and character-only layout settings remain separate. WTF is ignored by Git, so pulling this repository alone does not install the configured settings. Use the adoption utility with the same account, or transfer SavedVariables into the destination account folder.

## Release migration

The active project is now in `_forever_` for the installed `wowf` release build 1.60.1.70532 (Interface 16001). The beta copy is retained only as a migration source; use the release folder for subsequent edits and Git operations.

The 2026-10-23 migration carries Git history and uncommitted changes, the complete Interface (including private snapshot aliases and source configuration), live WTF and Fonts. Historical addon backups, diagnostics, utility files and private watcher state are preserved in `_forever_/addon-backups/beta-migration-20261023-141603/`. These private files stay outside version control. Client binaries and caches come from the release installation.

The beta settings watcher is removed and the release watcher uses the release installation path. Existing beta realm/character folders remain intact; release realms and characters may have different identities, so select the intended shared profiles and update the private source-character configuration if needed after first login. Migration and offline tests do not establish in-game compatibility or rendering at 1080p, 1440p and 4K.

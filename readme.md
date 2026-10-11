# WoW: Forever add-ons

Version control for the user interface of a **World of Warcraft: Forever** client (`wow_classic_beta`). The repository root is the game's `_classic_beta_` folder, and only `Interface/` is tracked. The game client, caches, logs, fonts and `WTF` settings are ignored (see [.gitignore](.gitignore)).

## Game version

| | |
| --- | --- |
| Client | 1.60.1.70338 (`wow_classic_beta`, region `us`) |
| Add-on interface | 16001 |

Every add-on here must declare Interface 16001 in its TOC and work on this client.

## Contents

- [Interface/AddOns/readme.md](Interface/AddOns/readme.md): YUI v338, modular EllesmereUI 9.4 frames/nameplates, RXPGuides and four specialist addons, with OverlapSettingsGuard. The frame and arrow setup has been reported working in-game; see the inventory for remaining caveats.
- [Interface/AddOns/updates.md](Interface/AddOns/updates.md): change log, newest first. It covers installs, removals, setting changes and local patches, which upstream updates can overwrite.
- [Interface/AGENTS.md](Interface/AGENTS.md): rules for maintaining the add-ons.

## Updating

Exit the game before replacing add-on folders. Record each change in `updates.md` and keep `readme.md` in sync. Then commit.

The `ForeverUI` branch preserves the addon bundle before the 2026-10-10 replacement. Its saved settings are separately backed up in `addon-backups/foreverui-replacement-20261010-211803/WTF`; switching branches does not restore WTF.

## Moving to another display

Run the adoption utility on the destination after closing WoW on both machines:

```powershell
.\Interface\adopt_addons.ps1 '\\source\WoW\_classic_beta_' -Resolution 1920x1080
```

The source path is the game root containing Interface and WTF. Resolution also accepts 2560x1440 or 3840x2160. The script fits EUI's options window and sets the windowed resolution; it preserves gameplay UI scale, frame positions and fonts. Without Resolution it copies settings unchanged. Maximized mode uses the destination display's native resolution. Destination Interface/WTF are backed up before replacement, with rollback on failure. Source WTF is never modified.

EUI and YUI share Default with new characters. RestedXP uses a supported default template for new character profiles; guide progress, Blizzard keybindings and character-only layout settings remain separate. WTF is ignored by Git, so pulling this repository alone does not install the configured settings. Use the adoption utility with the same account, or transfer SavedVariables into the destination account folder.
# WoW: Forever add-ons

Version control for the user interface of a **World of Warcraft: Forever** client (`wow_classic_beta`). The repository root is the game's `_classic_beta_` folder, and only `Interface/` is tracked. The game client, caches, logs, fonts and `WTF` settings are ignored (see [.gitignore](.gitignore)).

## Game version

| | |
| --- | --- |
| Client | 1.60.1.70338 (`wow_classic_beta`, region `us`) |
| Add-on interface | 16001 |

Every add-on here must declare Interface 16001 in its TOC and work on this client.

## Contents

- [Interface/AddOns/readme.md](Interface/AddOns/readme.md): installed add-ons with versions, sources and purpose. ClassUIEnhanced handles combat trackers and Plater handles nameplates; Blizzard supplies action bars, bags and unit/group frames, with Leatrix Plus for minimap/chat. Details!, Deadly Boss Mods, Leatrix Maps, RareScanner, Auctionator and others remain installed.
- [Interface/AddOns/updates.md](Interface/AddOns/updates.md): change log, newest first. It covers installs, removals, setting changes and the local patches to ForeverUI, which an upstream update would overwrite.
- [Interface/AGENTS.md](Interface/AGENTS.md): rules for maintaining the add-ons.

## Updating

Exit the game before replacing add-on folders. Record each change in `updates.md` and keep `readme.md` in sync. Then commit.

The `ForeverUI` branch preserves the addon bundle before the 2026-10-10 replacement. Its saved settings are separately backed up in `addon-backups/foreverui-replacement-20261010-211803/WTF`; switching branches does not restore WTF.

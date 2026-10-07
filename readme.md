# WoW: Forever add-ons

Version control for the user interface of a **World of Warcraft: Forever** client (`wow_classic_beta`). The repository root is the game's `_classic_beta_` folder, and only `Interface/` is tracked. The game client, caches, logs, fonts and `WTF` settings are ignored (see [.gitignore](.gitignore)).

## Game version

| | |
| --- | --- |
| Client | 1.60.1.70245 (`wow_classic_beta`, region `us`) |
| Add-on interface | 16001 |

Every add-on here must declare Interface 16001 in its TOC and work on this client.

## Contents

- [Interface/AddOns/readme.md](Interface/AddOns/readme.md): installed add-ons with versions, sources and purpose. The main UI is ForeverUI, alongside Details!, Deadly Boss Mods, Leatrix Plus and Leatrix Maps, RareScanner, Auctionator and others.
- [Interface/AddOns/updates.md](Interface/AddOns/updates.md): change log, newest first. It covers installs, removals, setting changes and the local patches to ForeverUI, which an upstream update would overwrite.
- [Interface/AGENTS.md](Interface/AGENTS.md): rules for maintaining the add-ons.

## Updating

Exit the game before replacing add-on folders. Record each change in `updates.md` and keep `readme.md` in sync. Then commit.

# WoW: Forever add-ons

Inventory checked 2026-10-09 for `_classic_beta_/Interface/AddOns` (client 1.60.1). These are installed package versions; in-game behavior still needs a character login. See [updates.md](updates.md) for the change history.

## Installed packages

| Package | Installed version | Folders | Purpose and source |
| --- | --- | --- | --- |
| ForeverUI | 0.4.65 + local keybind-label, party-frame taint and combat ping patches | `ForeverUI` | Main interface: frames, bars, nameplates, bags, chat, and layout controls. Action buttons are patched to show standard game key bindings, and hidden Blizzard party/raid frames are faded instead of hidden, the adopted armour-damage frame is moved with the C originals, ForeverUI's own action buttons run on their own event loop instead of Blizzard's shared ones (`Modules/ActionBars/OwnButtons.lua`), and Blizzard's buttons are no longer wrapped, so Edit Mode is not tainted. Their ping attributes are not set in combat; they update when combat ends. The chat module re-applies its font size after the game or another add-on resets it, and the minimap module gathers buttons that add-ons create after login; see [updates.md](updates.md). [CurseForge](https://www.curseforge.com/wow/addons/foreverui) |
| QuestForever | 0.4.7 + local combat map-pin patch | `QuestForever` | Quest helper bundled in the ForeverUI archive. It can be enabled from ForeverUI. Its world map pins skip `SetPassThroughButtons` in combat (`Pins.lua`), so opening the quest log in combat is not blocked. [ForeverUI package](https://www.curseforge.com/wow/addons/foreverui/files/9047043) |
| Details! | Details.20261006.15326.172 | `Details`, `Details_Compare2`, `Details_DataStorage`, `Details_EncounterDetails`, `Details_RaidCheck`, `Details_Streamer`, `Details_TinyThreat`, `Details_Vanguard` | Damage, healing, and threat meter (replaces ForeverMeter). Loads through its `_Camelot.toc` files (Interface 16001). [CurseForge](https://www.curseforge.com/wow/addons/details) |
| BugGrabber | v12.1.0 | `!BugGrabber` | Captures Lua errors. It has no display of its own; ForeverUI also installs an error handler. [CurseForge](https://www.curseforge.com/wow/addons/bug-grabber) |
| Leatrix Maps | 1.60.18-forever | `Leatrix_Maps` | World map and battlefield map enhancements. [CurseForge](https://www.curseforge.com/wow/addons/leatrix-maps) |
| Talents Forever | 0.37.1 (beta) | `TalentsForeverBook` | Talent planner for WoW: Forever. [CurseForge](https://www.curseforge.com/wow/addons/talents-forever) |
| DungeonsForever | 1.6.9 + local global-leak fix | `DungeonsForever` | Dungeon handbook: overviews, boss loot, quests, and profession guides. Open with `/df`. Loot-card rows no longer leak the global `r` (`Core/DungeonUI.lua`). [CurseForge](https://www.curseforge.com/wow/addons/dungeonsforever) |
| Deadly Boss Mods | 12.1.12 core | `DBM-*` (9 folders) | Encounter timers and alerts. Update the bundled DBM folders together. [CurseForge](https://www.curseforge.com/wow/addons/deadly-boss-mods) |
| Leatrix Plus | 1.60.11 | `Leatrix_Plus` | Optional quality of life settings. [CurseForge](https://www.curseforge.com/wow/addons/leatrix-plus) |
| RareScanner | 1.60.1.b6 | `RareScanner` | Rare, event, and treasure alerts. [CurseForge](https://www.curseforge.com/wow/addons/rarescanner) |
| Auctionator | 340 | `Auctionator` | Auction house tools. [CurseForge](https://www.curseforge.com/wow/addons/auctionator) |
| RangeDisplay | v6.3.6 | `RangeDisplay`, `RangeDisplay_Options` | Estimated unit range. Both TOCs include 16001; in-game behavior remains unverified. [CurseForge](https://www.curseforge.com/wow/addons/range-display) |
| RestedXP Guides | v4.11.21 | `RXPGuides` | Leveling guides with step list, waypoint arrow, map pins and quest/gossip/flight automation. Open with `/rxp`. Its main TOC lists 16001 and loads Forever's own guides and data (game type `camelot`). [CurseForge](https://www.curseforge.com/wow/addons/restedxp-guide) |

ForeverUI 0.4.65 and QuestForever 0.4.7 came from the [Forever 1.60.1 release](https://www.curseforge.com/wow/addons/foreverui/files/9047043). Both TOCs declare Interface 16001. Open ForeverUI with `/fui`; use `/fui move` to position its frames. ForeverUI includes its own nameplates and quest navigation. ElvUI, Platynator, LuckyoneUI, TomTom, and WeakAuras have been removed from the active add-on directory along with their companion folders and saved variables.

## OverlapSettingsGuard (our own add-on)

Version 0.2.0, folder `OverlapSettingsGuard`, written for this installation and not downloaded from anywhere. It keeps settings switched off when they duplicate a feature of another installed add-on. If one is switched on in game, it switches it back off and shows a popup explaining why. Type `/osg` to see its rules. See [OverlapSettingsGuard/readme.md](OverlapSettingsGuard/readme.md) for details.

## Updating safely

1. Exit WoW before replacing add-on folders.
2. Download a release labeled **Forever / 1.60.1** from the linked project page. Keep all folders in a package at matching versions.
3. Preserve the retained add-ons' `WTF` saved variables unless you intend to reset their settings.
4. Log into a character, check the feature, and inspect fresh `Logs/General.log` and `Logs/FrameXML.log` entries. File metadata alone does not prove in-game behavior.
5. Record the version, date, and result in [updates.md](updates.md).

The removed folders and settings were moved outside the beta installation to `D:\tmp\wow-forever-ui-replaced-2026-10-03` because automatic command review rejected permanent deletion. They are inactive and can be restored from there if needed.

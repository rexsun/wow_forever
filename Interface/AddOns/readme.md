# WoW: Forever add-ons

Inventory checked 2026-10-10 for `_classic_beta_/Interface/AddOns` (client 1.60.1.70338, Interface 16001). These are installed package versions; in-game behavior still needs a character login. See [updates.md](updates.md) for the change history.

## Installed packages

| Package | Installed version | Folders | Purpose and source |
| --- | --- | --- | --- |
| ClassUIEnhanced | 3.1.0 | `ClassUIEnhanced` | Cooldown/buff trackers, player health/resources and player/target/focus cast bars. Does not replace full unit or party/raid frames. Its main TOC lists Interface 16001. Open with `/cue`. [CurseForge release](https://www.curseforge.com/wow/addons/classuienhanced/files/9106446) |
| Plater Nameplates | Plater-v658-Forever | `Plater` | Configurable nameplates, threat colours, debuffs and nameplate cast bars. Loads through `Plater_Camelot.toc` (Interface 16001). Personal health/mana and class resource displays are guarded off in favour of ClassUIEnhanced. Open with `/plater`. [CurseForge release](https://www.curseforge.com/wow/addons/plater-nameplates/files/9119013) |
| Details! | Details.20261006.15326.172 | `Details`, `Details_Compare2`, `Details_DataStorage`, `Details_EncounterDetails`, `Details_RaidCheck`, `Details_Streamer`, `Details_TinyThreat`, `Details_Vanguard` | Damage, healing, and threat meter (replaces ForeverMeter). Loads through its `_Camelot.toc` files (Interface 16001). [CurseForge](https://www.curseforge.com/wow/addons/details) |
| BugGrabber | v12.1.0 | `!BugGrabber` | Captures Lua errors. It has no display of its own; BugSack is not installed. [CurseForge](https://www.curseforge.com/wow/addons/bug-grabber) |
| Leatrix Maps | 1.60.18-forever | `Leatrix_Maps` | World map and battlefield map enhancements. [CurseForge](https://www.curseforge.com/wow/addons/leatrix-maps) |
| Talents Forever | 0.37.1 (beta) | `TalentsForeverBook` | Talent planner for WoW: Forever. [CurseForge](https://www.curseforge.com/wow/addons/talents-forever) |
| DungeonsForever | 1.6.9 + local global-leak fix | `DungeonsForever` | Dungeon handbook: overviews, boss loot, quests, and profession guides. Open with `/df`. Loot-card rows no longer leak the global `r` (`Core/DungeonUI.lua`). [CurseForge](https://www.curseforge.com/wow/addons/dungeonsforever) |
| Deadly Boss Mods | 12.1.12 core | `DBM-*` (9 folders) | Encounter timers and alerts. Update the bundled DBM folders together. [CurseForge](https://www.curseforge.com/wow/addons/deadly-boss-mods) |
| Leatrix Plus | 1.60.11 | `Leatrix_Plus` | Optional quality of life settings. [CurseForge](https://www.curseforge.com/wow/addons/leatrix-plus) |
| RareScanner | 1.60.1.b6 | `RareScanner` | Rare, event, and treasure alerts. [CurseForge](https://www.curseforge.com/wow/addons/rarescanner) |
| Auctionator | 340 | `Auctionator` | Auction house tools. [CurseForge](https://www.curseforge.com/wow/addons/auctionator) |
| RangeDisplay | v6.3.6 | `RangeDisplay`, `RangeDisplay_Options` | Estimated unit range. Both TOCs include 16001; in-game behavior remains unverified. [CurseForge](https://www.curseforge.com/wow/addons/range-display) |
| RestedXP Guides | v4.11.21 | `RXPGuides` | Leveling guides with step list, waypoint arrow, map pins and quest/gossip/flight automation. Quest/gossip/reward automation is locked off in favor of Leatrix Plus; guide navigation and recommendations remain available. Open with `/rxp`. Its main TOC lists 16001 and loads Forever's own guides and data (game type `camelot`). [CurseForge](https://www.curseforge.com/wow/addons/restedxp-guide) |

Blizzard owns action bars, bags, player/target/focus/pet unit frames and party/raid frames. Leatrix Plus owns minimap and chat enhancements: Enhance minimap, Square minimap, Minimap button bag, chat font size 12 and Move editbox to top are enabled; Hide addon menu is off. Leatrix Combat plates is off because Plater owns nameplate visibility. RestedXP retains quest navigation and Leatrix retains quest automation. ClassUIEnhanced handles duplicate Blizzard cooldown viewers through its own first-login prompt; allow it to hide those viewers for a single tracker display.

ForeverUI 0.4.65 and bundled QuestForever 0.4.7, including local patches, are preserved on the `ForeverUI` Git branch at `50579665b579eb33f52f649f1834c57af2fea606`. Their folders were moved out of AddOns. A complete pre-migration WTF copy and the removed folders/settings are in `_classic_beta_/addon-backups/foreverui-replacement-20261010-211803/`. Existing Plater settings are retained. ElvUI, Platynator, LuckyoneUI, TomTom and WeakAuras remain uninstalled.

To restore the previous bundle, close WoW and switch to the `ForeverUI` branch from a clean checkout. Restore `WTF` from the migration backup to recover the previous settings and character addon lists. Switching branches alone does not restore WTF, because it is excluded from Git. Preserve any newer settings before restoring.

## OverlapSettingsGuard (our own add-on)

Version 0.3.0, folder `OverlapSettingsGuard`, written for this installation and not downloaded from anywhere. It keeps settings switched off when they duplicate a feature of another installed add-on. If one is switched on in game, it switches it back off and shows a popup explaining why. Type `/osg` to see its rules. See [OverlapSettingsGuard/readme.md](OverlapSettingsGuard/readme.md) for details.

## Updating safely

### Adopt from another machine

Close WoW on both machines. On the destination, place `adopt_addons.ps1` in its `Interface` folder, then run from the destination game root:

```powershell
.\Interface\adopt_addons.ps1 \\machine-source\WoW\_classic_beta_
```

The argument is the shared **game root containing Interface and WTF**. If the `WoW` share points directly at `_classic_beta_`, use `\\machine-source\WoW` instead. The destination is inferred from the script location, not the current working directory.

The script runs without confirmation prompts; keep both games closed until the transfer completes. The script refuses to run while a local WoW process exists. It stages both folders, moves the existing destination folders into `addon-backups/<timestamp>-<unique-id>/` beside `Interface`, then installs the staged folders. Replacement avoids retaining obsolete addons; copy failures leave the originals in place, and replacement failures trigger restoration. Logs and any failed transfer files remain with the backup. The utility is preserved if the source lacks it.

Fonts are excluded, and settings are copied unchanged: no resolution or UI scale conversion. This adopts the versions installed on the source, including local patches. Use the same compatible client and account/character identities. To restore, close WoW, move the adopted folders aside, and move the backed-up `Interface` and `WTF` into the destination game root.

### Update packages

1. Exit WoW before replacing add-on folders.
2. Download a release labeled **Forever / 1.60.1** from the linked project page. Keep all folders in a package at matching versions.
3. Preserve the retained add-ons' `WTF` saved variables unless you intend to reset their settings.
4. Log into a character, check the feature, and inspect fresh `Logs/General.log` and `Logs/FrameXML.log` entries. File metadata alone does not prove in-game behavior.
5. Record the version, date, and result in [updates.md](updates.md).

The removed folders and settings were moved outside the beta installation to `D:\tmp\wow-forever-ui-replaced-2026-10-03` because automatic command review rejected permanent deletion. They are inactive and can be restored from there if needed.

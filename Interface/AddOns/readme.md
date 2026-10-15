# WoW: Forever add-ons

Updated 2026-10-15 for client 1.60.1.70374 / Interface 16001. Ten upstream addon folders plus the local OverlapSettingsGuard are installed. EllesmereUI owns individual/group frames and nameplates; YUI owns bars, bindings and the remaining interface features. GearInsight provides talents, loot, gear farming, macros and leveling planning.

| Package | Version | Purpose and source |
| --- | --- | --- |
| YUI | v341 | Action bars, HUD, maps/minimap, chat, equipment, mail/merchant and combat helpers. [Forever source](https://www.wclbox.com/games/1/PluginItem/17520?version=9). Interface 16001/camelot. Two portable-font reference files differ from upstream. |
| GearInsight Forever | 0.4.31 | Talent simulator/default builds, leveling plan, gear farm suggestions, loot/wishlists, macros, dungeon quests, achievements/legacy and beta information. `/gi` or `/gif`. [Official site](https://gearinsight.app/wow/forever), [release listing](https://www.curseforge.com/wow/addons/gearinsight-forever), [installed ZIP](https://gearinsight.app/wow/dl/GearInsight-Forever-0.4.31.zip?s=forever_zip). Latest published release checked 2026-10-15; released 2026-10-14. TOC includes Interface 16001. Upstream files are unchanged. |
| Auctionator | 341 | Auction shopping, selling and pricing. [Release](https://www.curseforge.com/wow/addons/auctionator/files/9162359). Interface 16001. |
| !BugGrabber | v12.1.0 | Captures Lua errors; `/buggrabber 1` prints a captured error. [Release](https://www.curseforge.com/wow/addons/bug-grabber/files/8907587). Interface 16001. |
| EllesmereUI | 9.5.5 | Shared framework. [Suite release](https://www.curseforge.com/wow/addons/ellesmereui/files/9182709). Interface 16001. |
| EllesmereUIUnitFrames | 9.5.5 | Player, target, focus, pet and boss frames; player castbar retained. Same suite release. |
| EllesmereUIRaidFrames | 9.5.5 | Party/raid frames; all eight raid groups enabled. Same suite release. |
| EllesmereUINameplates | 9.5.5 | Nameplates and cast/aura displays; duplicate class power kept off. Same suite release. |
| EllesmereUIOptions | 9.5.5 | Required load-on-demand settings panels. Same suite release. |
| EllesmereUILocales | 9.5.5 | Load-on-demand translations, including zhTW. Same suite release. |
| OverlapSettingsGuard | 0.7.0 | Local ownership enforcement, eleven conditional rules, chat reporting and ten startup CVars. `/osg`. [Policy table](OverlapSettingsGuard/readme.md). Interface 16001. |

## Feature ownership and overlaps

- YUI retains quest/gossip automation, junk selling, its quest-item action bar, experience display, action bars and bindings.
- EllesmereUI retains individual/group frames, nameplates, health/cast displays and class resources. The guard disables competing YUI health/cast/resource HUDs and nameplate synchronization, plus EUI's duplicate nameplate power display. Swing timers and YUI cooldown tracking remain available.
- GearInsight's combined resource/DoT/cooldown/proc HUD is off while either YUI or EUI Unit Frames owns those displays. Its separate rotation recommendation board remains available.
- GearInsight's floating leveling panel is off while YUI owns the experience display. The main leveling plan, talents, macros and gear recommendations remain available.
- GearInsight automatic friendly-nameplate toggling is off while EUI Nameplates loads. The guard restores only a pending toggle recorded by GearInsight; it does not force user-selected friendly visibility.
- GearInsight's bar-placement, key assignment/presets and restore actions are read-only while YUI loads. Its key inspection and macro creation/import remain available. Place imported macros using the normal owner UI.
- GearInsight item translations and Forever change notes supplement tooltip styling. Map destinations, its unique rotation board and user-invoked system macros remain optional; these may change the shared map waypoint or startup CVars when used.

GearInsight uses the same Chinese strings for zhCN and zhTW, largely Simplified Chinese. The zhTW client remains selected. Client terminology can differ from its bundled Chinese names; name-dependent features require live verification.

## Settings and transfer

Existing YUI/EUI settings, resolution, UI scale, fonts, macros and bindings are preserved. GearInsight account defaults start with `qm.autoPlates=false`, `keysHud=false` and `leveling.shown=false`; the guard enforces ownership again after login, including new characters. Existing character addon lists enable GearInsight. Guide progress, saved talent plans and wishlists from the retired packages are not migrated into GearInsight.

The three replaced packages and their `.lua`/`.lua.bak` saved settings were removed from active AddOns/WTF. Obsolete guard integration and active settings snapshots were removed. Private recovery copies live outside Interface under `_classic_beta_/addon-backups/gearinsight-20261015-102755`. Historical changelogs are retained.

`Settings/WTF` captures anonymous EUI/YUI/GearInsight settings; live WTF and the private alias map remain outside Git. The settings watcher resumes after migration. See [settings documentation](../Settings/readme.md).

Run the adoption script from the source game root with WoW closed on both installations:

```powershell
.\Interface\adopt_addons.ps1 \\destination\WoW\_classic_beta_ -Resolution 1920x1080
```

The positional destination must already exist and be writable; `-Destination <path>` is equivalent. The script replaces destination Interface/WTF after backup and merges Fonts, preserving destination-only font files. It rolls back failed replacements. `-Resolution` supports 1920x1080, 2560x1440 and 3840x2160; EUI options scales are 0.90 / 1.00 / 1.50 respectively. Without it, settings are preserved. Account folder differences require manual saved-variable transfer. The script checks local processes and cannot confirm the remote game's state. No source-code change was needed to carry the migrated pack.

## Portable fonts

YUI's seven bundled fonts have byte-identical copies under game-root Fonts: `YUIInterBlack.ttf`, `YUIInterBold.ttf`, `YUIText.ttf`, `YUILongZhu.ttf`, `YUIHOOGE.ttf`, `YUIDamage1.ttf` and `YUIDark.ttf`. Two YUI source files use those paths while retaining font-selection names. EllesmereUI's saved `fctFont` selects the LongZhu copy; EUI owns damage text. Font sizes/layouts are unchanged. Updates can overwrite the YUI references; retain the copies and reapply those references. Adoption copies and backs up Fonts. Fully exit/restart to discover new assets.

YUI's full YUnitFrames product is not loaded by its Forever loader, and it has no party/raid replacement in this pack. Keep EUI for those frames. YUI's Platynator installer step remains unused. Old standalone EUI folders remain absent.

## Verification and limits

The migration checks guard behavior, current package/dependency integrity, saved-setting cleanup and preservation, fresh class/faction profiles, font assets, anonymous settings capture and adoption at all three target resolutions. These checks do not simulate game rendering. The subsequent 2026-10-15 10:38-10:53 session captured no new BugGrabber errors and retained GearInsight's guarded settings. AsyncFile.log still reported one YUIInterBlack.ttf manifest-load failure and two missing texture ID 137237 failures; the texture's caller is not identified. The four older BugGrabber reports were unchanged. Glyphs, tooltips, secret-value handling and appearance at 1080p/1440p/4K remain incompletely verified.

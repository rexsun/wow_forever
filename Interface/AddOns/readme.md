# WoW: Forever add-ons

Migrated 2026-10-23 to the installed release client 1.60.1.70532 (`wowf`, `_forever_`) / Interface 16001. Addon versions and source links below are unchanged; release loading still needs an in-game check. Twenty-three upstream addon folders plus two local addons are installed. EllesmereUI owns individual/group frames and nameplates; YUI owns bars, bindings and interface helpers. GearInsight provides talents, loot, gear farming, macros and leveling planning. Details owns combat meters and analysis. Skinner supplies complementary Blizzard-window skins. Waypoint UI owns in-world navigation display. Bagnon owns bag, bank and guild-bank windows.

| Package | Version | Purpose and source |
| --- | --- | --- |
| YUI | v341 | Action bars, HUD, maps/minimap, chat, equipment, mail/merchant and combat helpers. [Forever source](https://www.wclbox.com/games/1/PluginItem/17520?version=9). Interface 16001/camelot. Two portable-font reference files differ from upstream. |
| GearInsight Forever | 0.4.31 | Talent simulator/default builds, leveling plan, gear farm suggestions, loot/wishlists, macros, dungeon quests, achievements/legacy and beta information. `/gi` or `/gif`. [Official site](https://gearinsight.app/wow/forever), [release listing](https://www.curseforge.com/wow/addons/gearinsight-forever), [installed ZIP](https://gearinsight.app/wow/dl/GearInsight-Forever-0.4.31.zip?s=forever_zip). Latest published release checked 2026-10-15; released 2026-10-14. TOC includes Interface 16001. Upstream files are unchanged. |
| Auctionator | 341 | Auction shopping, selling and pricing. [Release](https://www.curseforge.com/wow/addons/auctionator/files/9162359). Interface 16001. |
| !BugGrabber | v12.1.0 | Captures Lua errors; `/buggrabber 1` prints a captured error. [Release](https://www.curseforge.com/wow/addons/bug-grabber/files/8907587). Interface 16001. |
| Details | Details.20261014.15330.172 | Damage/healing meters and combat analysis; `/details`. [Release](https://www.curseforge.com/wow/addons/details/files/9177176), 2026-10-14; latest checked 2026-10-15. `Details_Camelot.toc` supports Interface 16001. Upstream files unchanged. |
| Details_DataStorage | Bundled with 15330.172 | Load-on-demand combat data storage. Same Details release; Interface 16001. |
| Details_Compare2 | Bundled with 15330.172 | Player comparison tab in combat breakdowns. Same Details release; Interface 16001. |
| Details_EncounterDetails | Bundled with 15330.172 | Encounter summaries, phases, charts and emotes. Same Details release; Interface 16001. |
| Details_RaidCheck | Bundled with 15330.172 | Group talent/item-level and food/flask inspection. Same Details release; Interface 16001. |
| Details_TinyThreat | Bundled with 15330.172 | Group threat ranking within a Details window. Same Details release; Interface 16001. |
| EllesmereUI | 9.5.5 | Shared framework. [Suite release](https://www.curseforge.com/wow/addons/ellesmereui/files/9182709). Interface 16001. |
| EllesmereUIUnitFrames | 9.5.5 | Player, target, focus, pet and boss frames; player castbar retained. Same suite release. |
| EllesmereUIRaidFrames | 9.5.5 | Party/raid frames; all eight raid groups enabled. Same suite release. |
| EllesmereUINameplates | 9.5.5 | Nameplates and cast/aura displays; duplicate class power kept off. Same suite release. |
| EllesmereUIOptions | 9.5.5 | Required load-on-demand settings panels. Same suite release. |
| EllesmereUILocales | 9.5.5 | Load-on-demand translations, including zhTW. Same suite release. |
| Skinner | beta12.70425.2 | Styles Blizzard windows and supported addon windows. `/skinner` or `/skin`. [Author's packaged release](https://github.com/jncl/Skinner/releases/tag/beta12.70425.2), published 2026-10-16; latest checked 2026-10-17. Includes Interface 16001 and dedicated Forever/Camelot support. Bundled libraries; upstream files unchanged. |
| Waypoint UI | 1.7.3 | In-world waypoint, pinpoint and navigator arrow for the super-tracked quest, map pin or point of interest; `/way`, `/waypoint`, `/wp`. [Release](https://www.curseforge.com/wow/addons/waypointui/files/8961715), 2026-09-24; latest checked 2026-10-17. `WaypointUI_Camelot.toc` supports Interface 16001. GPLv3; upstream files unchanged. |
| Bagnon | 12.1.7 | Single-window inventory/bank/guild-bank replacement with search, sorting, cross-character views and tooltip item counts; `/bagnon`, `/bgn`. [Release](https://www.curseforge.com/wow/addons/bagnon/files/9193505), 2026-10-15; latest checked 2026-10-17. Interface list includes 16001. Upstream files unchanged. |
| BagBrother | Bundled with 12.1.7 | Required shared core and character inventory cache (`BrotherBags`). Same release; Interface 16001. |
| Bagnon_Bank, Bagnon_GuildBank, Bagnon_Config | Bundled with 12.1.7 | Load-on-demand bank, guild-bank and options modules. Same release; Interface 16001. |
| OverlapSettingsGuard | 0.8.0 | Local ownership enforcement, 23 conditional rules, chat reporting and ten startup CVars. `/osg`. [Policy table](OverlapSettingsGuard/readme.md). Interface 16001. |
| CharacterUIBaseline | 0.3.0 | Local per-login UI sync (layout reported, not applied) from a configurable source account/character; source logout publication and automatic post-exit refresh. `/uib`, `/uib apply`, `/uib capture`. [Configuration and scope](CharacterUIBaseline/readme.md). Interface 16001. |

## Feature ownership and overlaps

- YUI retains quest/gossip automation, junk selling, its quest-item action bar, experience display, action bars and bindings.
- EllesmereUI retains individual/group frames, nameplates, health/cast displays and class resources. The guard disables competing YUI health/cast/resource HUDs and nameplate synchronization, plus EUI's duplicate nameplate power display. Swing timers and YUI cooldown tracking remain available.
- GearInsight's combined resource/DoT/cooldown/proc HUD is off while either YUI or EUI Unit Frames owns those displays. Its separate rotation recommendation board remains available.
- GearInsight's floating leveling panel is off while YUI owns the experience display. The main leveling plan, talents, macros and gear recommendations remain available.
- GearInsight automatic friendly-nameplate toggling is off while EUI Nameplates loads. The guard restores only a pending toggle recorded by GearInsight; it does not force user-selected friendly visibility.
- GearInsight's bar-placement, key assignment/presets and restore actions are read-only while YUI loads. Its key inspection and macro creation/import remain available. Place imported macros using the normal owner UI.
- GearInsight item translations and Forever change notes supplement tooltip styling. Map destinations, its unique rotation board and user-invoked system macros remain optional; these may change the shared map waypoint or startup CVars when used.
- Details is the only installed combat meter: YUI's Forever loader does not load YDamageMeter, and EllesmereUIDamageMeters is absent. YUI's Details specialization-icon integration remains enabled because it supplements the meter. TinyThreat group rankings supplement EUI's per-unit threat indicators. Details Raid Check and GearInsight talent planning serve different purposes.
- The optional Details_Streamer cast/action overlay and Details_Vanguard tank-health/debuff frames are not installed because existing YUI/EUI displays own those features. Review these exclusions again if installing additional Details plugins.
- Skinner's individual/party/compact frames, castbar and nameplate skins stay off under the corresponding EUI owners. Its action/status bars, minimap/buttons, world map, chat and tooltip skins stay off while YUI loads. Details and DetailsFramework widget skinning stay off while Details loads. Every guarded setting is listed in the [policy table](OverlapSettingsGuard/readme.md); Blizzard-window and Auctionator skins remain available.
- Waypoint UI replaces Blizzard's in-world navigation frame and sets `showInGameNavigation` on until logout at each load. YUI map markers/event navigation and GearInsight map destinations only choose the super-tracked target, which Waypoint UI then displays; GearInsight's printed `/way` coordinates become usable. EUI's `/way` command belongs to the absent EllesmereUIQoL module. No installed addon registers `/way`, `/waypoint` or `/wp`, and Skinner has no Waypoint UI skin. No guard policy is required. Its default "Game Font" follows the client font (Rurutia).
- Bagnon replaces Blizzard's bag, bank and guild-bank windows. YUI's Blizzard-bag enhancements become inactive while it loads: the combined-bag position (x=0.88, y=0.30), `fixBagSortButton`, and the Profession Assistant entry docked on the Blizzard backpack. With YUI `bagsBarVisibility="auto"`, Blizzard bags never report open, so the Blizzard bag bar stays hidden; Bagnon's own bag-slot toggle replaces it. Set that YUI option to `show` to keep the bar visible. EllesmereUIBags, which EUI auto-disables beside Bagnon, is absent. No installed addon adds tooltip item counts. Skinner's Bagnon skin follows its `ContainerFrames` setting as complementary styling. No guard policy is required because the YUI settings are inert rather than competing.

GearInsight uses the same Chinese strings for zhCN and zhTW, largely Simplified Chinese. The zhTW client remains selected. Client terminology can differ from its bundled Chinese names; name-dependent features require live verification.

## Settings and transfer

Existing YUI/EUI settings, resolution, UI scale, fonts, macros and bindings are preserved. GearInsight account defaults start with `qm.autoPlates=false`, `keysHud=false` and `leveling.shown=false`; the guard enforces ownership again after login, including new characters. Existing character addon lists enable GearInsight. Guide progress, saved talent plans and wishlists from the retired packages are not migrated into GearInsight.

The six selected Details modules are enabled in existing character addon lists. Their first-run window/options setup is left to upstream; no new profile or fixed window position is imposed. Details saved combat databases are not part of anonymous settings capture, but the private adoption script copies them with the rest of live WTF. Existing settings and gameplay UI scale are unchanged at all three target resolutions; verify meter placement and text in-game at each resolution.

Skinner is enabled in the four existing character addon lists. The guard applies its ownership settings before login skinning and after profile changes, including new accounts; it covers stored profiles and UnitFrames namespace defaults. Skinner settings are not yet included in anonymous snapshots, but adoption copies all live WTF, including future SkinnerDB saved profiles. No resolution, UI scale, map size or viewport is changed. If a skin was already applied before a later option change, follow the guard's chat request to `/reload`.

YUI's official buff icons and tracked buff bars retain their original relative anchors in the active placement stores and saved HUD preset; the direct-center override was reverted. The combined bag window keeps its normalized center at x=0.88, y=0.30, leaving room above the lower-right bag bar while retaining automatic bag-bar visibility. Buff visibility settings and assignments are preserved. Actual bag clearance depends on bag dimensions; check it in-game at the three supported resolutions.

All four existing characters use the reference native UI baseline. CharacterUIBaseline 0.3.0 reapplies the supported baseline on every target login/reload, skipping the configured source character. It no longer selects or imports Edit Mode layouts, which tainted Edit Mode and blocked logout; it reports a differing layout so it can be selected manually. Edit `Settings/character-ui-source.local.json` to change its account/character. Source logout publishes current UI values for same-account character switching; the existing post-exit watcher refreshes generated files for subsequent client starts and other accounts. EUI/YUI shared settings remain in place; Details retains its shared reference profile. Spec/talent selections, spec-to-profile assignments, macros, bindings, subscriptions, tracking and combat history are excluded. See the addon readme for exact scope and refresh commands.

The three replaced packages and their `.lua`/`.lua.bak` saved settings were removed from active AddOns/WTF. Obsolete guard integration and active settings snapshots were removed. Private recovery copies live outside Interface under `_classic_beta_/addon-backups/gearinsight-20261015-102755`. Historical changelogs are retained.

`Settings/WTF` captures anonymous, reusable account-level EUI/YUI/GearInsight configuration. Character records, progression, profile-to-character assignments and runtime caches are excluded; restore preserves their current live values. Live WTF and the private alias map remain outside Git. See [settings documentation](../Settings/readme.md).

Run the adoption script from the source game root with WoW closed on both installations:

```powershell
.\Interface\adopt_addons.ps1 \\destination\WoW\_classic_beta_ -Resolution 1920x1080
```

The positional destination must already exist and be writable; `-Destination <path>` is equivalent. The script replaces destination Interface/WTF after backup and merges Fonts, preserving destination-only font files. It rolls back failed replacements. `-Resolution` supports 1920x1080, 2560x1440 and 3840x2160; EUI options scales are 0.90 / 1.00 / 1.50 respectively. Without it, settings are preserved. Account folder differences require manual saved-variable transfer. The script checks local processes and cannot confirm the remote game's state. No source-code change was needed to carry the migrated pack.

## Portable fonts

YUI's seven bundled fonts have byte-identical copies under game-root Fonts: `YUIInterBlack.ttf`, `YUIInterBold.ttf`, `YUIText.ttf`, `YUILongZhu.ttf`, `YUIHOOGE.ttf`, `YUIDamage1.ttf` and `YUIDark.ttf`. Two YUI source files use those paths while retaining font-selection names. EllesmereUI's saved `fctFont` selects the LongZhu copy; EUI owns damage text. Font sizes/layouts are unchanged. Updates can overwrite the YUI references; retain the copies and reapply those references. Adoption copies and backs up Fonts. Fully exit/restart to discover new assets.

## Default game font

Rurutia (Montserrat + Source Han Sans SC ExtraBold, from SharedMedia_Rurutia v2.2.9) replaces the client's standard, header, unit-name and chat font files in game-root Fonts: `FRIZQT__.TTF`, `FRIZQT___CYR.TTF`, `ARIALN.TTF`, `MORPHEUS.ttf`, `MORPHEUS_CYR.TTF`, `ARHei.ttf`, `ARKai_T.ttf`, `arheiuhk_bd.ttf`, `bHEI00M.ttf`, `bHEI01B.ttf` and `bLEI00D.ttf`. It covers Big5 (zhTW) and GBK (zhCN) except one unused bopomofo tone mark; Traditional text uses Simplified-standard glyph shapes. The damage-text files `skurri.ttf`, `SKURRI_CYR.TTF`, `ARKai_C.ttf` and `bKAI00M.ttf` are unchanged. Add-ons on default/system fonts follow it; explicit picks such as YUI's bundled faces do not. These copies are not tracked by Git; adoption carries them with Fonts.

YUI's full YUnitFrames product is not loaded by its Forever loader, and it has no party/raid replacement in this pack. Keep EUI for those frames. YUI's Platynator installer step remains unused. Old standalone EUI folders remain absent.

## Verification and limits

The migration checks guard behavior, current package/dependency integrity, saved-setting cleanup and preservation, fresh class/faction profiles, font assets, anonymous settings capture and adoption at all three target resolutions. These checks do not simulate game rendering. The subsequent 2026-10-15 10:38-10:53 session captured no new BugGrabber errors and retained GearInsight's guarded settings. AsyncFile.log still reported one YUIInterBlack.ttf manifest-load failure and two missing texture ID 137237 failures; the texture's caller is not identified. The four older BugGrabber reports were unchanged. Glyphs, tooltips, secret-value handling and appearance at 1080p/1440p/4K remain incompletely verified.

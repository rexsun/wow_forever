# WoW: Forever add-on updates

This log records changes made in `World of Warcraft/_forever_/Interface/AddOns` (previously `_classic_beta_`). See [readme.md](readme.md) for the current inventory and sources.

## 2026-11-09 - Install GatherLite 8.4.3 and Lueur 1.5.0 (OverlapSettingsGuard 0.11.0)

- Install `GatherLite` 8.4.3 by Wuild ([file 9510987](https://www.curseforge.com/wow/addons/gatherlite/files/9510987)) and `Lueur` 1.5.0 by Armytille ([file 9523609](https://www.curseforge.com/wow/addons/lueur/files/9523609)) from CurseForge. Both TOCs list Interface 16001, the installed files are byte-identical to the releases, and both are enabled in all 15 character addon lists. DungeonsForever was reviewed and not adopted: it overlaps GearInsight, MapUtils and YUI's spellbook and talent handling, and loads all seven modules at login by default.
- Guard: two new rules, 42 in total. `lueur.nodeherbs` and `lueur.nodeore` keep Lueur's minimap markers off while MapUtils loads, using a new `Lueur` adapter.
- Overlap review, no rule needed: GatherLite's minimap markers show possible spawn locations rather than tracked nodes, so they stay on beside MapUtils'. Its map reveal and zoom apply only to its own window.
- Defaults left on and worth knowing: GatherLite broadcasts its version number every 10 seconds to guild, group and yell addon channels and loads about 12 MB of route data at login. Lueur keeps soft-target interact on at 15 yards in all directions until logout.
- Caveats: Lueur shares `SoftTargetInteractRange` with EUI Fishing Key, and its glow attaches to game-object nameplates that EUI Nameplates also handles; check fishing and that the glow appears. GatherLite's compressed route data was not decoded during review.
- Backup: `addon-backups/gatherlite-lueur-install-20261109` holds the 15 edited character addon lists.
- Verification: 71 guard tests pass, 6 of them new. Nothing was run in game or checked at the three supported resolutions.

## 2026-11-09 - Silence other channels in Forever Essentials Fishing Sounds

- Local patch to EllesmereUI Forever Essentials 9.8: while Fishing Sounds is on and you fish, music, ambience and dialog go to 0 and effects and master volume go to 100%, instead of music and ambience × 0.3 and effects at least 80%. The existing CVar hold restores your exact values when you move, enter combat or change zone. `tools/apply_addon_patches.py` reapplies it, now 25 patches.
- The tooltip and its zhTW translation describe the new behavior. Other locales show the English text until upstream translates it.
- Not possible: hearing only your own float. Every float plays the same sound file on the effects channel, and addons get no bite or sound event, so other players' floats stay audible and are raised along with yours. Researched against addon listings, the Blizzard forums and addon-author notes; none shows a way around this.
- Overlap review, no new rule needed: YUI only offers manual volume controls and writes no volume during fishing.
- Verification: 12 patch-tool tests pass, one of them new. Nothing was run in game.

## 2026-11-08 - Install MapUtils 1.4.25 (OverlapSettingsGuard 0.10.0)

- Install `MapUtils` 1.4.25 by D4KiR from CurseForge ([file 9494803](https://www.curseforge.com/wow/addons/maputils/files/9494803)); `MapUtils_Camelot.toc` lists Interface 16001 and the installed files are byte-identical to the release. It is enabled in all 15 character addon lists. Chosen over BetterMaps 1.28.0 because it ships 224 boss pins (BetterMaps ships 32 positions, 31 of them rough, and learns the rest from kills) and adds pins to the existing map.
- Guard: seven new rules, 40 in total. `mu.worldmapmove`, `mu.worldmapscale`, `mu.worldmapfade`, `mu.mapreveal` and `mu.pierpins` keep the competing MapUtils settings off while YUI loads. `yui.flightmarkers` keeps YUI's flight-point marker off, so MapUtils' discovered/undiscovered pins are the only ones. `euife.zonelevels` keeps Forever Essentials Zone Levels off. New `Adapters/MapUtils.lua` writes `MAUTTAB`, because MapUtils publishes no API; its rules run before `PLAYER_LOGIN`.
- Overlap review, no rule needed: moving transports, minimap piers, dungeon entrances, meeting stones, zone crossings, quest-giver pins and gathering icons have no installed counterpart. One Map (stepless zoom, on by default) changes how the world map zooms, but YUI has no equivalent. MapUtils yields its window control to YUI by itself once YUI has made the map movable or scaled it (saved YUI scale 1.4).
- Defaults left on and worth knowing: MapUtils shares your map position with your guild (at most every 5 seconds while moving, never in instances) and joins a hidden `MapUtils` chat channel, using guild and group messages too, to exchange transport timetables. Switch these off in `/maputils`.
- Caveats: MapUtils uses its own dungeon maps and boss pins only if the client has no native art for those instances; confirm "Show boss pins" appears in `/maputils`. Undiscovered flight points need each character to open a flight master before they are confirmed. Neither fishing pool locations nor zone-crossing coverage were checked in game. Nothing was run in game, including appearance at 1080p, 1440p and 4K.
- Backup: `addon-backups/maputils-install-20261108` holds the 15 edited character addon lists.
- Verification: 65 guard tests pass, 9 of them new.

## 2026-11-07 - Update six addon packages (OverlapSettingsGuard 0.9.1)

- Update YUI v352 to v354, GearInsight Forever 0.5.11 to 0.7.4 (beta channel, like earlier versions), EllesmereUI suite 9.7.6 to 9.8 (installed modules only), Details 15400.172 to 15402.172 (the six installed folders), Auctionator 341 to 342 and !BugGrabber v12.1.0 to v12.1.1. Every TOC still lists Interface 16001. Skinner, Waypoint UI, Bagnon and LootRollMover were already current. Details' newer `-1`/`-2` alpha builds and the uninstalled EUI modules, `Details_Streamer` and `Details_Vanguard` are not installed.
- Local patches: all 21 reapply unchanged. Details 15402 now has its own secret check on row-hover truncation, but only when `IsAddonApocalypseWow()` is true, so the local patch is kept.
- Guard: `yui.chatkeywordfilter` keeps YChat's keyword filter off. Its reason text now says GearInsight owns level-up filtering through `/gi lvlmute` rather than claiming the filter is on: GearInsight 0.7.x turned its level-up filter off by default, so other players' level-up announcements now show in chat until `/gi 屏蔽升级 开` is used. YUI v354 adds `[GearInsight插件]` to its default keywords (the filter stays off) and migrates uncustomized keyword lists without changing `enabled`.
- Overlap review, no new rule needed:
  - GearInsight 0.7.x: all guarded keys and the ten locked editing methods are unchanged. New default-on features stay within GearInsight or need a click: PvP kill/death pop-up (its map link briefly sets and restores the user waypoint; watch for Waypoint UI flicker), guild level-prefix zone tag (inactive under `gi.guildchatlevel`), character-panel corner icons, quest-chain tracker, guild-invite menu entry, LibDBIcon minimap button, and free-for-all loot when leading a group formed from its Group tab. Own level-ups now post to guild automatically every fifth level with a pop-up at other levels; the old milestone default is migrated. Hunter-pet sightings and tames, with NPC ID and coordinates, are always recorded for its updater. No new CVars, bindings, Edit Mode writes or protected calls.
  - YUI v354: the quest-tracker scroll and auto-turn-in button now follow EllesmereUI's custom quest tracker through hooks and write no EUI settings. Paladin Seal of Righteousness tracking migrates to ranks 1-8.
  - EllesmereUI 9.8: guarded keys unchanged. New default-on options (target sounds, elite/classification markers in instances) stay within EUI. The 97 new files are rounded-corner masks, two icons and a friends list that runs only with the uninstalled Blizzard Skins module. The saved damage font now applies only if the client locale can draw it; on zhTW this needs LSM to list `Fonts\YUILongZhu.ttf`, which YUI registers after EUI loads, so the font is first applied at `PLAYER_LOGIN` instead of at load. Unverified in game.
  - Details 15402: `show_percent` now defaults on (cosmetic, one-time upgrade). The `cooltip.lua:2517` secret-value error is fixed upstream, `rounded_panel.lua:432` partly, and `fw.lua:6016` is unchanged.
  - Auctionator 342: Forever search/duration fixes. It now drops Hidden Items and favourites whose item is unknown to the client.
- `tools/font-asset-tests.py` now loads EUI's real damage-font locale gate instead of failing on the missing `EllesmereUI` table.
- Backup: `addon-backups/addon-upgrade-20261107` holds the replaced folders and live WTF.
- Verification: 56 guard tests, 11 patch-tool tests, settings, baseline, fresh-profile, font and adoption tests pass. 2,673 Lua files compile under Lua 5.1 except five unchanged-style files that start with a UTF-8 BOM, which the client accepts. Nothing was run in game.

## 2026-11-06 - Enlarge the Forever Essentials Bobber Indicator

- `EllesmereUIForeverEssentials_Fishing.lua`: `INDICATOR_SIZE` 40 → 100 UI units, as a local patch in `tools/apply_addon_patches.py`. Upstream hard-codes the size and registers the indicator with Unlock Mode as fixed-size, so there was no setting for it. The key label and border scale with it; its saved position is unchanged.
- Caveat: the indicator is a status icon only. Clicks pass through it to the world, but it takes mouse hover, so the cursor cannot hover a bobber behind it; keep it away from where the bobber lands (move it in Unlock Mode). The size is in UI units, so its share of the screen depends on the UI scale at 1080p, 1440p and 4K. Unverified in game.
- Verification: `apply_addon_patches.py --check` reports 21 patches in place; `tools/test_apply_addon_patches.py` passes.

## 2026-11-06 - Keep only the latest two adoption backups

- `adopt_addons.ps1`: after a successful adoption, delete older backups the script made in the destination's `addon-backups`, keeping the newest two (including the one just made). Only folders named like the script's own backups (`yyyyMMdd-HHmmss-<guid>`) are counted; hand-made backups there are never touched. A backup that cannot be deleted produces a warning, not a failed adoption. Failed or rolled-back runs prune nothing.
- Verification: `tools/adopt-addons-tests.ps1` passes, including a new check that a third run removes the oldest backup and keeps an unrelated folder.

## 2026-11-06 - Replace LootRollAnchor with LootRollMover 8.3

- Install `LootRollMover` 8.3 by Xruptor from CurseForge ([file 9163856](https://www.curseforge.com/wow/addons/lootrollmover/files/9163856)); its TOC lists Interface 16001. Upstream files unchanged. It takes LootRollAnchor's place in all 14 character addon lists.
- Remove the local `LootRollAnchor` addon, its tests and its current documentation (revert of `f255b24`); its `LootRollAnchorDB` saved variables are deleted. The 2026-11-05 entry below is kept as history.
- Account-wide default in `LRMDB` (LootRollMover has no profiles or per-character settings, so it applies to every character): anchor `BOTTOM` of UIParent, x=-4, y=154. In the shared `Default` YUI profile all characters use, action bar 3's top is 113 UI units above the screen bottom (main bar y=3, then main, bar 2 and bar 3 at 36 units with 1-unit gaps). The stance and totem bars sit 2 units above bar 3's top-left corner at 36 units tall, so their top is 151 and can reach the roll column for classes with three or more buttons. The first roll window's bottom is 5 units above that (156). No UI scale is set, so the screen is 768 units tall and the gap is the same at 1080p, 1440p and 4K. The -4/+2 offsets cancel the gap LootRollMover leaves between its anchor and the roll window, which keeps the window centred.
- `alertEnabled=false`: LootRollMover otherwise moves Blizzard's alert toasts to a new anchor at screen centre. No other setting is changed.
- Overlap review: no other installed addon positions the roll stack or alert toasts on this client; YUI's loot-roll bridge loads only on retail. No guard policy is added.
- Caveats: YUI HUD groups centred near y=169 (important, utility, resources) and the buff group can still overlap the roll stack while it is shown; accepted because rolls are short-lived. The position is fixed, so it does not follow later changes to YUI bar size, rows or position; drag it with `/lrm anchor`. LootRollMover re-anchors the roll windows from Blizzard's `GroupLootContainer_Update`/`GroupLootFrame_OnShow` hooks; whether this client's bottom-managed layout moves them afterwards is unverified in-game, as is placement at 1080p, 1440p and 4K.
- Backups of the edited character addon lists are in `addon-backups/lootrollanchor-removal-20261106`.

## 2026-11-06 - Install EllesmereUI Forever Essentials for its fishing tools (OverlapSettingsGuard 0.9.0)

- Install `EllesmereUIForeverEssentials` 9.7.6 from the same suite release as the other EUI modules ([file 9450137](https://www.curseforge.com/wow/addons/ellesmereui/files/9450137)); upstream files unchanged. This reverses the 2026-11-05 decision to keep it out. Its options pages were already installed with `EllesmereUIOptions`, so the Fishing settings showed in the panel but did nothing. It is enabled in all 14 character addon lists.
- Wanted features: Fishing Key (one key equips your best pole, casts, reels in through soft interact, applies lures and shows a bobber indicator), Double-Click to Cast, Fishing Sounds, and the world map's Show Fishing Skill. Every fishing option is off until set in EllesmereUI → Forever Essentials → General → Fishing.
- No module settings were saved before, so only upstream defaults apply: every feature is off except Flight Timer, which nothing else installed provides.
- Eight new guard rules (adapter `ForeverEssentials`) lock off the features that duplicate an installed owner: spell uprank, map reveal, map fade, travel markers, junk items, classic spellbook and classic talents (YUI), and the threat meter (Details_TinyThreat). The guard sets `enabled=false` and calls the feature's `Apply`, so no reload is needed.
- Overlap review, no rule needed: the fishing key temporarily raises the `SoftTargetInteract*` CVars and fishing sounds the volume CVars while fishing, then restores them; no installed addon or startup CVar touches them. No installed addon has a fishing key or zone-level labels. YUI only records known flight paths and has no flight timer. The other unguarded features (gathering skill, loot feed, quest rewards, pet summon, active form, simplified stats, macro manager) are off by default and were not reviewed; review them before switching one on.
- Verification: 56 guard tests pass (five new), and every module and guard Lua file compiles under Lua 5.1. Unverified in game.

## 2026-11-05 - Fix loot roll window position (LootRollAnchor 0.1.0)

- Problem: the group loot roll window appeared at wrong spots, and sometimes not visibly at all before its roll timed out.
- Cause, from the Forever 1.60.1.70790 interface source:
  - Blizzard places `GroupLootContainer` (the roll stack) in its bottom managed container. The container's height comes from the first visible, default-position frame in `OverrideActionBar`, `MultiBarBottomLeft` and `MicroMenuContainer` (`Blizzard_EditMode/Camelot/EditModeUtil.lua`).
  - YUI hides the micro menu and keeps the native bars as invisible copies, so the height is read from frames that are not where the visible bars are, and it changes whenever Blizzard re-runs its bottom layout.
  - YUI's bridge that lifts the roll stack above its bars and HUD (`YHUD/View/Bridges/Loot.lua`) loads only on retail.
- Fix: new local addon `LootRollAnchor`. It registers an EllesmereUI frame placer for `GroupLootContainer`, which runs each time Blizzard lays the stack out, before the frame draws. The stack is centred on screen, starts 120 UI units above the bottom of the screen, and steps above every shown YUI action-bar holder and YHUD group in the roll column. It is enabled in all 14 existing character addon lists.
- Overlap review: no other installed addon positions the roll stack. Skinner's loot-frame skin is styling only. EllesmereUI's `cdm` placer owner is otherwise used only by the absent EllesmereUICooldownManager. No guard policy is added.
- Caveats:
  - The "not shown until timeout" symptom is attributed to the same misplacement and is not confirmed in-game.
  - A YUI frame that appears only after a roll opens is not avoided until the next layout.
  - `/lra` reports the current anchor and the computed spot.
- Verification: 8 new LootRollAnchor tests and the existing suites pass, and the addon's Lua compiles under Lua 5.1. Placement is unverified in-game at 1080p, 1440p and 4K.

## 2026-11-05 - Guard Details row hover against a secret truncation value

- Problem: hovering a Details meter row threw `window_main.lua:1022: attempt to perform boolean test on a secret boolean value` (BugGrabber, 4 times in the first session on the upgraded pack). Upstream skips the truncation check only when the row text has a secret aspect, but `IsTruncated()` can still return a secret boolean. The line is unchanged between 15339 and 15400, so the upgrade did not cause it.
- A local patch skips the check when the result is secret, so the pop-out for long names is not shown for that row. `tools/apply_addon_patches.py` now holds 20 patches.
- The same session logged one `ADDON_ACTION_BLOCKED` for `Button:SetPassThroughButtons()` from Blizzard's world-map quest pins, blamed on GearInsight. An earlier session, before the upgrade, blamed Skinner for the same error, so it is left alone. The two new chat guard rules saved `messageFilter.enabled=false` and `guildChatLevel=false`. The `MultiBarRight:SetScale` warning and the Skinner startup errors did not return.
- Verification: patch-tool tests pass, and all 2,625 Lua files compile under Lua 5.1. The fix is unverified in-game.

## 2026-11-05 - Update six addon packages and guard two new chat filters (OverlapSettingsGuard 0.8.3)

- Update YUI v351 to v352, GearInsight Forever 0.5.9 to 0.5.11, EllesmereUI suite 9.7.3 to 9.7.6, Details 15339.172 to 15400.172, Waypoint UI 1.7.4 to 1.7.5 and Bagnon 12.1.7 to 12.1.8. Skinner and Auctionator were already current. !BugGrabber stays at v12.1.0.
- Keep `EllesmereUIForeverEssentials` and the other unused EUI modules, `Details_Streamer` and `Details_Vanguard` out. Forever Essentials competes with YUI's rank upgrade, map reveal and fade, junk selling and talent/spellbook handling, and with Details' threat display.
- Two new guard rules, both active while YUI and GearInsight load:
  - `yui.chatkeywordfilter`: YUI v352's YChat keyword filter is on by default and hides any player message containing `[GearInsight 无限版]` or `白云飞整合插件任务指南` in 19 channels, history and replay. GearInsight's own level-up filter already covers its announcements. The guard turns `messageFilter.enabled` off through YChat's setter in the active profile, and in stored profiles that have a YChat table. The keyword list is kept.
  - `gi.guildchatlevel`: GearInsight 0.5.11 re-enables the guild/officer level prefix (`[26]` before the message) through a chat filter, and YUI owns chat. The guard sets `ui.guildChatLevel=false`. The filter checks the flag per message, so no reload is needed.
- Details now ships upstream commit `803d6220` and our parser guard, so four of the six local Details patches are already upstream. The death-log (`util.lua`) and Midnight breakdown lookups still need the local patch. The patch tool still holds 19 patches and applies cleanly.
- Overlap review, no further rule needed:
  - GearInsight 0.5.11 quest-mate sharing now uses guild chat and hidden addon whispers to up to six nearby players. It runs only after the Group tab loads, and `/gi qm off` stops it. GearInsight now also records gathering-node coordinates. All ten locked editing methods are unchanged.
  - Waypoint UI hooks the YUI minimap's `OnMouseUp` for custom pins, which are off by default.
  - EUI 9.7.4-9.7.6 adds only opt-in features to installed modules. Under the WoW Forever nameplate style, only Highlight marks the target now (Glow and border choices are ignored).
  - Bagnon 12.1.8 only stops counting warband bank slots on Forever.
- Risk review: none of the six updates changes a key or method the guard uses, and the new versions write no Edit Mode layouts or CVars.
  - Unverified API on 1.60.1: Waypoint UI's new `SuperTrackedFrame:CheckInitializeNavigationFrame()` call, and EUI's opt-in unit-frame Max Health Style (`GetUnitTotalModifiedMaxHealthPercent`). Leave Max Health Style off until it is confirmed in-game.
  - YUI now requires a windup block in ranged swing-timer settings, which its validation fills in.
- YUI's archive has Chinese media filenames, which `unzip` garbled. It was extracted with the archive's UTF-8 names instead, and all 178 voice/music files match v351 byte for byte.
- Backup: `addon-backups/addon-upgrade-20261105` holds the replaced folders and live WTF.
- Verification:
  - 51 guard tests pass, 4 of them new. 11 patch-tool tests, 44 settings tests and 7 baseline tests pass, plus the baseline runtime, fresh-profile, font and adoption checks.
  - All 2,625 Lua files under AddOns compile under Lua 5.1.
  - Nothing was run in game: settings migrations, `/osg` (25 rules), the two chat rules, nameplate target marking and appearance at 1080p/1440p/4K still need in-game checks.

## 2026-11-05 - Turn off bloom at startup (OverlapSettingsGuard 0.8.2)

- Added `SetCVar("graphicsBloomUserMult", "0")` to the startup console settings, after `volumeFog 0`. `volumeFog 0` was already applied at startup and is unchanged.
- The client stores this setting (`Config.wtf` had `graphicsBloomUserMult "1"`), and no installed addon writes it, so no overlap rule is added. `raidGraphicsBloomUserMult`, used by the raid graphics preset, is left unchanged.
- Verification: 47 tests pass, including the startup CVar order test, which now checks eleven values. The visible effect is unverified in-game. The value is the same at 1080p, 1440p and 4K.

## 2026-11-04 - Set the baseline chat font to 12

- Problem: chat font size 12 returned to 18 at each login. YUI has no separate message size and uses Blizzard's chat setting. CharacterUIBaseline reapplies the source character's font to every target character at every login, and the source's value was 18.
- Set 12 in all three places it is stored: the source character's `chat-cache.txt` (all ten windows), the source publication in `CharacterUIBaseline.lua` saved variables, and generated `Baseline.lua`, rebuilt with `tools/character_ui_baseline.py`. Only the font value changed in `Baseline.lua`. `addon-backups/chat-font-20261104` holds the previous files.
- Caveats: logging in on the source character can restore the server's copy of its chat settings and publish 18 again at logout; set 12 on that character if that happens. Chat windows on target characters still follow the baseline at every login, so a different size set on one target will not last.
- Verification: 7 baseline helper tests and the runtime baseline checks pass. The size after login is unverified in-game.

## 2026-11-04 - Correction: save the right-bar minimap flag in-game

- The offline edit in the entry below was replaced by the server's copy at the 17:40 login, and the `MultiBarRight:SetScale` warning continued. YUI's Edit Mode claims keep the Minimap and action bars from being selected there, so the flag had to be saved in-game.
- A first `C_EditMode.SaveLayouts` command passed only `GetLayouts()` output and had no effect, because `SaveLayouts` expects the presets first. Saving through `EllesmereUI.EditModeLayoutsForSave()`, which adds them, marked the Minimap non-default in `rex`.
- Verification: `MinimapCluster:IsInDefaultPosition()` stayed `false` after `/reload` and after a full logout and login. The layout file on disk has the new flag. The warning stayed at 945 from the reload through the player's fights and logout. Addon code still must not write Edit Mode layouts at login: this was a one-time manual command. On a new account or a reset layout, the warning can return until the flag is saved again.

## 2026-11-04 - Stop Blizzard's bag window opening beside Bagnon

- Problem: bag buttons opened Bagnon and a Blizzard bag window together. Bagnon hides only `ContainerFrame1..N` and relies on `combinedBags` being off, or `ContainerFrameCombinedBags` opens too. Its `C_CVar.SetCVar('combinedBags', nil)` left no saved value in any WTF config, so the likely cause is that the nil write does nothing on this client.
- Local patches to `BagBrother/core/features/uiOverrides.lua` write an explicit `0` at load and whenever the CVar changes while Bagnon's inventory is enabled, including outside the tutorial-constant guard that upstream's write sits behind. `tools/apply_addon_patches.py` now also matches multi-line text in CRLF files and holds 19 patches.
- Caveats: the value is saved, so if Bagnon's inventory is later disabled, Blizzard uses separate bags until `combinedBags` is set back to 1. Blizzard still uses its combined window in gamepad mode, which this does not change. The CVar's live value before the fix was not read in-game.
- Overlap review: no new guard rule. YUI reads the combined window but never writes this CVar. Its combined-bag position, `fixBagSortButton` and Profession Assistant backpack entry stay inactive as already documented.
- Verification: patch-tool and guard tests pass, and the patched file compiles under Lua 5.1. In-game, the bag button now opens only Bagnon.

## 2026-11-04 - Fix Skinner startup, Details secret icons and right-bar scale warnings

- Skinner: beta12.70688.1 removed `Forever\_Support.xml` from its TOC and relies on `[Family]`, which is `Mainline` on this client (Blizzard's own Edit Mode TOC only resolves that way). `SetupForever_*` stayed nil, `OnInitialize` aborted at `Skinner.lua:51`, and `prdb`, `Backdrop` and `lmAddons` were never set, so Skinner was non-functional. A local patch restores the line. Upstream's latest code still lacks it.
- Details: `specIconID` can be secret, and using it as a table key threw `fw.lua:6016` on window refreshes. Local patches apply upstream commit `803d6220` (not yet released) and guard three more lookups of the same kind that it leaves open: `util.lua` death logs, the Midnight breakdown data provider and `bParser.GetSerial`.
- Right action bars: YUI places the minimap at the bottom of the screen while the `rex` Edit Mode layout still marked it default, so Blizzard computed the bars' space from its bottom edge: (2 - 10) - (86 + 24) = -118, and -118 / 562 = the logged scale of -0.209964. The cached layout now marks the Minimap non-default with the same anchor, so the limit becomes the top of the screen. This changes a flag rather than a position, so it does not vary by resolution, and YUI still places the minimap. It was edited offline because addon Edit Mode writes taint Blizzard's handler (see 2026-10-17). `addon-backups/error-fixes-20261104` holds the previous `edit-mode-cache-account.txt` and `cache.md5`.
- `tools/apply_addon_patches.py` now supports additive patches and keeps each file's line endings; it holds 16 patches.
- Overlap review: no new guard rule. These fixes change no overlapping setting, and the guard's Skinner policies apply again now that Skinner starts.
- Verification: patch-tool tests and guard tests pass, and the patched Lua files compile under Lua 5.1. In-game loading is unverified. If the server copy replaces the layout edit at login, the scale warning returns.

## 2026-11-04 - Update six addon packages and adapt the guard

- Update YUI v341 to v351, GearInsight Forever 0.4.31 to 0.5.9, EllesmereUI suite 9.5.5 to 9.7.3, Skinner beta12.70425.2 to beta12.70688.1, Details 15330.172 to 15339.172 and Waypoint UI 1.7.3 to 1.7.4. Auctionator 341 and Bagnon 12.1.7 were already current. !BugGrabber stays at v12.1.0 by choice; v12.1.1 only bumps its TOC.
- Add `GearInsight_Forever_Group` and `GearInsight_Forever_Guild`, which 0.5.9 requires for those tabs, and enable them in existing character addon lists. Keep unused EUI modules, `Details_Streamer` and `Details_Vanguard` out.
- OverlapSettingsGuard 0.8.1: GearInsight removed `Keys.ApplyAll` and added five editing methods, which would have blocked the entire action-bar lock; the lock now covers ten methods and survives a missing one. Friendly-nameplate enforcement handles `QM` moving to a load-on-demand module and sets `platesV3` so upstream's one-time migration cannot re-enable `autoPlates`. YUI rules now cover the resource manager's `itemsByContext`, which edited contexts read instead of `bySpec`.
- Exclude Skinner's new EllesmereUI skin with a local patch. Upstream, it moves Skinner to a new profile with all Blizzard skins disabled and depends on callbacks from the absent EllesmereUIBlizzardSkin; Skinner has no setting to skip it. No Skinner "EllesmereUI" profile was created because the skin never ran.
- Add `tools/apply_addon_patches.py` to reapply this patch and YUI's eight portable-font references after updates; it fails without writing if upstream text changed. YUI's seven bundled fonts are byte-identical to v341, so game-root copies are unchanged.
- Overlap review: no new guard rule. YUI's `EllesmereUIEnhancement` window styling needs the absent EllesmereUIBlizzardSkin. Its damage-meter reset prompt is opt-in and supplements Details. GearInsight now hides other players' level-up announcements by default and announces your own at every tenth level; no installed addon overlaps this.
- Backup: `addon-backups/addon-upgrade-20261104` holds the replaced folders and live WTF. Verification: every installed file matches its release archive except the two YUI files and one Skinner file patched above; 2,130 Lua files compile under Lua 5.1; 47 guard tests, 5 patch tests, 51 settings/baseline tests, font, fresh-profile, baseline runtime and adoption checks pass. Nothing was run in game: settings migrations, `/osg`, the Group tab, `AsyncFile.log` and appearance at 1080p/1440p/4K still require in-game checks.

## 2026-10-23 - Inspect release client language resources

- Verify release `wowf` installed-language tags include enUS and zhTW only, with no zhCN; live WTF selects zhTW text and enUS audio. No separate zhCN client pack is registered for release, so no client-resource deletion is needed.
- Keep all custom fonts (including zhCN-named overrides), addon translations and zhTW resources. The three temporarily removed font overrides were restored byte-for-byte from beta.
- Beta's separate installed-language record still lists zhCN. Shared game archives, beta installation and migration backups are unchanged.

## 2026-10-23 - Migrate beta project to release

- Migrate the working repository, complete Interface, live WTF and Fonts to `_forever_`, the installed `wowf` 1.60.1.70532 release. Retain Git history, branches, index and the four existing uncommitted files. No addon is installed, updated or removed; feature ownership and overlap policies are unchanged.
- Preserve existing addon backups, font backup, diagnostics, utility files and private watcher state under `addon-backups/beta-migration-20261023-141603`. Keep beta files intact until uninstall.
- Update the current inventory and adoption examples for release; replace the beta scheduled settings watcher with the release watcher. Private source-character identities are retained rather than guessed for new release realms.
- Verify copied files with SHA256 and run existing adoption, overlap guard and settings checks from release. First release login, profile/realm mapping and visuals at 1080p/1440p/4K require in-game verification.

## 2026-10-17 - Stop CharacterUIBaseline Edit Mode writes

- Problem: on a target character, 0.2.0 called `C_EditMode.SetActiveLayout` from addon code. BugGrabber recorded `EditMode: Error updating layout info in EDIT_MODE_LAYOUTS_UPDATED handler` with that call on the stack, and the character could not log out. It also switched the character to Blizzard's `現代模式` (Modern) preset, because the source's latest logout publication (09:39) recorded that preset rather than `YUI v3`.
- CharacterUIBaseline 0.3.0 never selects or imports Edit Mode layouts. It compares the active layout name read-only and prints both names when they differ; the player selects the layout once in Edit Mode. CVars are written only when they differ from the source value. Chat font/geometry and EUI party/raid positions still sync each login. The source still publishes its layout name (no native layout export).
- Follow-up: the source's saved Edit Mode selection is layout `11` (first spec) and `YUI v3` (other specs); neither is Modern, so the logout-time API value was wrong. The source now remembers its layout on world entry and `EDIT_MODE_LAYOUTS_UPDATED` and publishes that at logout. Lu Jessica's per-spec selection (`edit-mode-cache-character.txt`) was restored offline to match the source; the previous file is in the backup under `WTF-Lu-Jessica`. The stale published layout name refreshes on the source's next login/logout.
- The 10:44 logout "crash" was a Windows-reported hang (AppHangB1) while the client rewrote large `.slug`/`.slugo` font caches (latest written 11 seconds before the hang ended), the first rebuild after the Rurutia font replacement. No add-on error was saved; saved variables from that session were not written.
- Backup: `addon-backups/uib-no-editmode-20261017-104044`. Verification: 12 runtime checks (including no Edit Mode writes, mismatch reporting and three resolutions), helper unit tests and 39 guard tests pass; all addon Lua compiles under Lua 5.1. Logout and layout selection still require an in-game check after `/reload`.

## 2026-10-17 - Install Bagnon 12.1.7

- Install upstream Bagnon 12.1.7 (CurseForge file 9193505, 2026-10-15) unchanged: `Bagnon`, required `BagBrother` and load-on-demand `Bagnon_Bank`, `Bagnon_GuildBank`, `Bagnon_Config`. Every TOC lists Interface 16001. All 188 files are byte-identical to the release archive.
- Overlap review: Bagnon replaces Blizzard bag/bank windows, so YUI's combined-bag position, bag-sort fix and Profession Assistant backpack entry go inactive, and YUI's `auto` bag-bar visibility keeps the Blizzard bag bar hidden. EUI's competing EllesmereUIBags is absent; no installed addon adds tooltip item counts; Skinner's Bagnon skin is complementary. No guard policy added; the guard readme records the review.
- `BrotherBags` stores per-character inventory caches; it is outside the anonymous settings allowlist and travels only with live WTF through adoption. No saved settings were changed. Window placement at 1080p/1440p/4K, bank/guild-bank loading and the Profession Assistant entry still require in-game checks.

## 2026-10-17 - Install Waypoint UI 1.7.3

- Install upstream Waypoint UI 1.7.3 (CurseForge file 8961715, 2026-09-24) unchanged; its `WaypointUI_Camelot.toc` declares Interface 16001. 240 files are byte-identical to the release archive.
- Overlap review: it hides Blizzard's in-world super-tracking frame, forces `showInGameNavigation` on until logout and registers `/way`, `/waypoint`, `/wp`. YUI map markers/event navigation and GearInsight map destinations set the target it displays; no installed addon owns these slash commands (EUI's optional `/way` lives in the absent EllesmereUIQoL), and Skinner has no competing skin. No guard policy was added; the guard readme records the review.
- Its default font is the client game font, so it follows Rurutia. No saved settings or adoption changes; first-load settings come from upstream defaults. Settings persistence across `/reload` and a full restart still requires an in-game check.

## 2026-10-17 - Use Rurutia as the default game font

- Replace eleven non-damage client font files in game-root Fonts (Latin/Cyrillic standard, header and narrow; zhCN and zhTW standard, unit-name and chat) with Rurutia v2.2.9, superseding the previous Maple Mono NF CN copies. Keep the four damage-text files (`skurri.ttf`, `SKURRI_CYR.TTF`, `ARKai_C.ttf`, `bKAI00M.ttf`) and YUI's bundled fonts unchanged.
- Coverage check: Big5 13,741/13,742 (missing only U+02CD) and GBK 21,791/21,791. No add-on code or saved setting changed; EUI's zhTW system font resolves to `bLEI00D.ttf`.
- Backup of the eleven replaced files: `addon-backups/default-font-rurutia-20261017-081346/Fonts`. All replacements are byte-identical to the source file. In-game rendering needs a full client restart and visual check.

## 2026-10-17 - Revert YUI buff placement overrides

- Restore the original relative anchors for official buff icons and tracked buff bars in all six active/saved placement tables from the pre-change backup. Preserve buff visibility, tracked content and specialization settings.
- Keep the combined bag position, configurable source character and login synchronization unchanged. Refresh the anonymous YUI snapshot so adoption retains the reverted anchors.
- Recovery backup: `addon-backups/revert-yui-buffs-20261017-075222` outside Interface. Parsed-data comparison confirms only the six placement tables changed; all 153 other WTF files are byte-identical to that backup. Visual placement still requires an in-game check.

## 2026-10-17 - Synchronize the configurable source UI on every login

- Upgrade local CharacterUIBaseline to 0.2.0. Replace the persisted revision skip with a session gate: target characters sync on every login/UI reload; zone changes do not repeat it. The configured source is excluded from application and publishes its current UI at logout or `/uib capture`.
- Add private `Settings/character-ui-source.local.json` for source account, realm folder, character folder, in-game realm and fallback layout name, plus an anonymous example. Generate private `Source.local.lua` with a source identity key; changing sources ignores stale publications. Configure the previously selected reference as the initial source.
- Refresh the generated baseline from source WTF during the existing post-exit settings export, without writing live WTF. Same-account character switches use the latest account publication; cross-account distribution uses the generated fallback on the next client start. The offline helper validates paths and source data, supports dry runs/disabling, backs up changed generated files and rolls both files back on write failure.
- Sync the existing UI-only CVar allowlist, native chat font/primary geometry and EUI party/raid positions. Capture/export the source native layout and use EUI's existing import API when a target's named layout is absent or different. Defer combat/Edit Mode editing and bound readiness retries. OSG startup preferences still run normally and can supersede conflicting captured CVars; no continuous competing display toggle is introduced, so its 23 rules remain unchanged.
- Preserve specialization/talent choices, spec-to-profile assignments, per-spec content/documents, action contents, macros, bindings, subscriptions, tracking and combat history. Source and generated private configuration are ignored by Git and carried by adoption. A transferred installation may require changing the configured source folder identifiers.
- Recovery copies of the previous initializer, live WTF, helper/tests and documentation are outside Interface under `addon-backups/login-ui-sync-20261017-072226`. In-game identity matching, source publication and final visuals still require a fresh source/target login cycle.
- Verification: 51 Python tests (44 settings plus seven source-refresh cases), eleven runtime checks including source publication, native custom/preset layouts, per-login application, spec/talent exclusions and three-resolution geometry; 39 guard tests and 18 fresh-character profiles pass. Three-resolution adoption carries both private configuration files intact and preserves rollback behavior. All 151 live WTF files are byte-identical to the pre-change backup. Generated output is stable, all initializer Lua files compile under Lua 5.1 and TOC references resolve. The existing watcher task is running and uses the updated exporter without reinstalling it.

## 2026-10-17 - Share the reference UI across characters

- Synchronize the other three existing characters with the reference character's native Edit Mode selection, saved UI-window positions, chat presentation and fifteen display-only character CVars. Enable the local initializer on all four. Preserve character macros/bindings, chat subscriptions, quest/currency/profession tracking, role selections, community IDs and mixed addon gameplay databases.
- EUI and YUI already use shared account profiles. Retain EUI's `Default` party position, x=-446.4761980796349 and y=20.57142892175792 relative to screen center; no per-character EUI database exists to clone. Correct the differing native Edit Mode selection and refresh the shared EUI frames during initialization. Native layout differences are observed; the original visual symptom still needs in-game confirmation.
- Configure Details to always use the reference character's existing shared profile and align existing character profile pointers. Preserve the other stored profiles and all combat histories. Keep future per-character initialization markers outside anonymous settings capture.
- Install local CharacterUIBaseline 0.1.0 for Interface 16001. Capture native layout name `YUI v3`, display CVars, chat font 18 and normalized primary chat geometry. Apply once during first login, defer combat/Edit Mode editing, bound readiness retries and expose `/uib apply`. Use the existing named layout instead of importing upstream defaults. No upstream addon is patched. This is a captured template, not automatic mirroring of later source-character edits.
- Review initialization overlaps in the guard readme; no continuously competing setting toggle is introduced, so its 23 enforcement policies remain unchanged. Adoption already copies the initializer and live revision markers with all Interface/WTF files.
- Back up live WTF, anonymous snapshots and current pack documentation outside Interface under `addon-backups/character-ui-20261017-071132`. The manifest lists twenty changed/created WTF files. First-login behavior and visual consistency at 1080p/1440p/4K require in-game verification.
- Verification: five initializer checks, including the three target resolutions; all 39 overlap-guard tests; 18 fresh character profiles. Generated baseline and initializer compile under Lua 5.1, all TOC references exist, and exact-file/semantic checks confirm the twenty WTF changes while preserving macros, bindings, subscriptions, tracking and combat history. Anonymous snapshots are refreshed; the existing adoption script needs no modification.

## 2026-10-17 - Save independent buff anchors and bag clearance

- Change only YUI saved configuration: anchor the official buff icon group directly to UIParent center and its tracked-bar group to center minus 64 UI units. Update both YHUD placement storage and suite layout storage, plus the corresponding anchors in the existing saved HUD configuration set, so selecting that set does not restore the old dependent anchors.
- Save the combined bag window center at normalized screen coordinates x=0.88, y=0.30 using YUI's existing permanent window-position support. Retain automatic bag-bar visibility, existing window scale, individual-bag layout and all other window positions. This is a fixed saved position with generous clearance, not a dynamic 12-unit collision rule; varying bag dimensions still need an in-game check at 1080p/1440p/4K.
- Preserve all per-specialization buff assignments, serialized content documents, native buff import, action bars, resource ownership rules and UI scale. The saved Mage configurations contain no tracked buffs, and neither the prior saved-variable backup nor saved HUD preset contains missing Mage selections to restore. No spell assignments are invented. An empty tracked group still needs its buffs selected in-game; these saved-position changes do not repair the previously recorded native CooldownViewer taint errors.
- Back up all live WTF and the prior anonymous snapshots outside Interface under `addon-backups/yui-layout-20261017-070043`. Apply seven targeted table edits in live YUI.lua without rewriting unrelated file contents; refresh the anonymous settings snapshot. No addon source or adoption-script changes are needed.
- Verification: the updated saved variables load under Lua 5.1, a semantic allowlist confirms only the intended placement fields changed, and only live YUI.lua and anonymous YUI.json differ from their backups. Normalized bag coordinates are valid at all three target resolutions. Actual buff rendering and bag dimensions still need an in-game check.

## 2026-10-17 - Install Skinner with guarded ownership

- Install the author's packaged [Skinner beta12.70425.2 prerelease](https://github.com/jncl/Skinner/releases/tag/beta12.70425.2), published 2026-10-16 and latest checked 2026-10-17. It declares Interface 16001 and dedicated Forever/Camelot support for the installed 1.60.1.70450 client. All 377 package files are unchanged. Archive SHA256: `46087dd15c0f20cdbc8eddb5b71c16fdd59b57a9dea99a2d2c8f91e9a412b87c`.
- Upgrade OverlapSettingsGuard to 0.8.0 with twelve Skinner policies, for 23 total rules. Each overlapping setting is listed in Policy.lua and the policy table: individual/party/compact frames, castbars and nameplates stay with EUI; action/status bars, maps/minimap, chat and tooltips stay with YUI. Disable Skinner's Details and DetailsFramework library skins to retain Details appearance. Blizzard-window and Auctionator skins remain available.
- Enforce Skinner's active and stored profiles, cached skin profile and UnitFrames namespace with inherited defaults. Check before PLAYER_LOGIN and again at login to precede Skinner's module enable and delayed skin passes; retain combat deferral and normal profile-change/periodic checks. Request a manual reload when a changed skin has already been applied. No upstream source patch, layout, viewport, map-size or UI-scale change.
- Enable Skinner in four existing character addon lists. All 137 other live WTF files are byte-identical to the backup; existing anonymous settings snapshot edits are preserved. Skinner settings remain outside anonymous capture, while adoption copies future live SkinnerDB settings with all other WTF data. The existing adoption script copies Skinner and the updated guard without a code change.
- Recovery copies of WTF, the previous guard, current documentation, adoption script and release ZIP are outside Interface in `addon-backups/skinner-20261017-063922`.
- Verification: 39 Lua 5.1 guard tests, including actual Skinner AceDB/default/UnitFrames source, first-login timing and real profile resets; 365 package TOC/XML references resolve and 349 Skinner/guard Lua files compile. Adoption checks pass at 1080p/1440p/4K, including scale preservation and failure rollback. In-game loading, beta API behavior and appearance at these resolutions still require a fresh client session.

## 2026-10-15 - Keep settings monitoring invisible

- Launch the sign-in watcher through Windows Script Host with a hidden PowerShell child, avoiding a console at startup. Start uv interpreter discovery and Python exports with console creation disabled and captured output; retain manual command output and failure handling. Background export status goes to the existing private watcher log.
- Add helper checks for no console window, quoted paths and nonzero exits with large output on both streams. Addons, overlap policies and adoption behavior are unchanged.

## 2026-10-15 - Restrict tracked snapshots to reusable configuration

- Filter account-level addon settings before anonymization; exclude character files/scopes, profile-to-character mappings, gold, XP, session statistics, known flights, social/history records and runtime caches. Retain shared UI profiles, layouts, fonts, feature preferences and migration markers. GearInsight preferences use an explicit allowlist.
- Restore shared configuration while preserving current excluded data, including nested caches and records absent from the selected bundle. Ignore excluded data in older snapshots and skip legacy character-file snapshots. Regenerate the current settings bundle without modifying live WTF.
- Keep private adoption as a full live-WTF transfer. Filtering applies to version-controlled snapshots, not the private game installation or adoption backups. Existing Git history and private aliases are retained.
- Verification: 44 settings tests and 19 watcher/restore lifecycle checks pass, including gameplay-only export stability, shared-preference retention, old-snapshot protection and missing-file restore. Seven real settings targets validate in restore dry run; all 106 live WTF files remain byte-identical after export, and a repeated export produces identical snapshots.

## 2026-10-15 - Install Details combat analysis

- Install unchanged Details.20261014.15330.172 from [CurseForge file 9177176](https://www.curseforge.com/wow/addons/details/files/9177176), the latest release checked 2026-10-15. The release supports Forever 1.60.1; all six selected modules have Interface 16001 Camelot TOCs. Archive SHA256: `67c4fe6c81e7bc331098e67bce00ee049735d278a7c9d04c9d749930233e5086`.
- Install Details, Details_DataStorage, Details_Compare2, Details_EncounterDetails, Details_RaidCheck and Details_TinyThreat; enable them in existing character addon lists. Omit optional Details_Streamer and Details_Vanguard to avoid duplicate cast/action overlays and tank health/debuff frames.
- Confirm YUI's Forever loader excludes YDamageMeter and EUI Damage Meters is absent. Details is the sole combat meter; YUI icon synchronization and EUI threat indicators remain complementary. No new overlapping setting remains in the selected modules, so the guard's existing eleven rules stay unchanged. Document the overlap review in its readme.
- Preserve all existing saved addon settings, UI scale, fonts and layouts. First-run Details window setup is upstream. Private recovery copies of WTF, current documentation and the release ZIP live outside Interface under `_classic_beta_/addon-backups/details-20261015-111109`. The adoption script already copies the new folders and future live saved variables at all three target resolutions.
- Verification: all 636 installed files match the official archive; six Camelot TOCs and 311 reachable load files/dependencies resolve; all 33 guard tests and three-resolution adoption/rollback checks pass. Four character lists enable the modules; all other live WTF files are byte-identical to the recovery copy. In-game loading, combat data, Chinese UI text and meter placement at 1080p/1440p/4K still need a fresh client session.

## 2026-10-15 - Inspect the first post-migration session

- Checked the 10:38-10:53 session: no new BugGrabber errors; all four older reports and counters were unchanged. GearInsight persisted the disabled overlapping HUD, floating leveling panel and automatic friendly-nameplate settings.
- AsyncFile.log recorded one YUIInterBlack.ttf manifest-load failure and two failures for texture ID 137237. The font exists on disk; the texture's caller is not identified. These asset issues remain unresolved. Old FrameXML/taint logs do not describe this session.
- No new crash artifacts were found. Voice disconnection coincided with shutdown; startup CVar validation messages remain a lower-priority beta-client finding. No runtime settings were changed during inspection.

## 2026-10-15 - Replace the planning addons with GearInsight Forever

- Install unchanged GearInsight Forever 0.4.31 from the official Forever ZIP, latest published release checked 2026-10-15. TOC includes Interface 16001. Archive SHA256: `84edba6d538689323a0775fe10f212bae1d19dde01cdde73780917f31030ce46`.
- Remove DungeonsForever 1.8.6, TalentsForeverBook 0.38.2 and RestedXP 4.11.23 from active AddOns, along with eight account/character `.lua`/`.lua.bak` saved files. Clean their entries from four character AddOns.txt files and enable GearInsight there. No guide, talent-plan or wishlist migration into GearInsight is attempted.
- Upgrade OverlapSettingsGuard to 0.7.0: retain the six YUI/EUI ownership rules and replace six obsolete RestedXP rules with five GearInsight rules. Disable its automatic friendly-nameplate toggling, combined resource/cooldown/DoT/proc HUD and floating leveling panel. Keep its key/bar editing actions read-only under YUI without modifying upstream source. Preserve talents, loot, planning, macros and the distinct rotation board.
- Seed account GearInsight overlap defaults off, preserve YUI/EUI settings and other WTF bytes, and switch anonymous settings capture to EUI/YUI/GearInsight. Remove obsolete RestedXP adapter, dependencies, fixtures, tests and current documentation. Update fresh-profile checks to use YUI's installed AceDB libraries. Preserve historical changelogs and private aliases.
- Keep private recovery copies outside Interface under `_classic_beta_/addon-backups/gearinsight-20261015-102755`; retired active files were moved there. Existing unrelated working changes remain. The settings watcher was paused for migration and resumed afterward.
- Verification: 33 Lua 5.1 guard tests, including actual GearInsight bar-editor code; 36 settings tests; 18 fresh class/faction profiles; seven font assets and EUI damage-font application; adoption at 1080p/1440p/4K with rollback; 19 watcher/restore checks. Official archive integrity, removed files and preservation of unrelated active files are checked separately. The existing adoption script copies the new pack without code changes. In-game loading and rendering remain unverified.

## 2026-10-14 - Upgrade Forever addons and retain EUI frame ownership

- Upgraded YUI v338 to v341, Auctionator 340 to 341, DungeonsForever 1.8.0 to 1.8.6, TalentsForeverBook 0.38.1 to 0.38.2 beta and all six installed EllesmereUI folders from 9.4 to 9.5.5. Official release links are in the inventory; all declare Interface 16001 for the installed 1.60.1.70374 client. RestedXP v4.11.23 and BugGrabber v12.1.0 remain current. YUI's listing dates v341 October 15; the Forever download was already available on October 14 local time.
- Kept EUI Unit Frames, Raid Frames, Nameplates, Options, Locales and shared core; installed no other suite modules. Inspection of YUI v341 confirms no party/raid replacement, an unloaded YUnitFrames product and player-only health/cast HUD resources.
- Updated OverlapSettingsGuard to 0.6.0 with separate player-health and player-cast policies. Cover resource selections, all 27 Forever specialization IDs, druid forms, stored profiles/HUD sets, dedicated cast-only groups and native castbar suppression. Retain swing timers and other HUD content; defer changes in combat and retry failed refreshes independently per rule.
- Reapplied YUI's portable SharedMedia font references and talent-rank Inter Black path. All seven game-root font copies match the new upstream font bytes. TalentsForeverBook 0.38.2 already selects regular Cinzel upstream, removing the need for its previous local patch. EUI damage-font settings and all live WTF files are preserved byte-for-byte.
- Upstream changes include YUI player bars and interface fixes; EUI frame/aura customization and CPU improvements; DungeonsForever gear/reputation pages and expanded datasets; Talents Forever gamepad, trainer, keybinding and leveling-order fixes; Auctionator Retail compatibility metadata. DungeonsForever publishes no changelog; its changes were identified by archive comparison. New EUI suite features outside the six retained modules are not installed. Existing optional map/navigation, quest-item and statistics overlaps remain user choices.
- Backed up AddOns, WTF, tools, the root changelog and adoption script under `_classic_beta_/addon-backups/upgrade-20261014-155318`; retained moved original package folders there as well. The archive hash manifest is stored with the backup. No settings were reset.
- Verification: 32 Lua 5.1 guard tests, including installed YUI catalog normalization; seven font assets and EUI damage-font application; 18 fresh class/faction profiles; adoption at 1080p/1440p/4K plus backup/rollback; 35 settings tests and 19 watcher/restore checks. Package integrity and exact file sets are checked against the release archives except the two documented YUI font-reference files. `adopt_addons.ps1` already copies the updated pack and guard, so its code is unchanged. Live loading, errors and rendering at all three resolutions still need an in-game session.

## 2026-10-13 - Add explicit settings restore and private .env aliases

- Added `watch_wtf_settings.ps1 -Mode Restore`, with DryRun validation, strict alias/path checks, complete restoration of represented addon saved files, selective Config.wtf merging, private backups and rollback.
- Pause/resume the scheduled watcher around restoration without overwriting the selected source bundle at startup. Foreground watchers must be stopped first; a previously stopped task remains stopped.
- Migrated private mappings to ignored Interface/.env and added .env.example. Existing aliases and anonymous snapshots are preserved. Logs/locks/backups stay outside the repository, with an optional state-directory override. Addon code and overlap policies are unchanged.

## 2026-10-13 - Add anonymous settings capture after game exit

- Added `Interface/watch_wtf_settings.ps1`, a restricted data parser/exporter and local settings-review documentation. Optional current-user sign-in installation monitors this game installation and exports after all its WoW processes exit and WTF writes settle.
- Snapshots in `Interface/Settings/WTF` alias every text and numeric value using a private map outside the repository. Live WTF, addon behavior, resolution values, existing overlap policies and adoption's private-copy behavior are unchanged.
- No automatic staging, commits or pushes. Fixture checks cover privacy, stable aliases, failure preservation, parser safety, concurrent exports, readable review and the Git index; watcher checks cover lifecycle, retries and settling.

## 2026-10-13 - Match screenshot display settings at startup

- Updated OverlapSettingsGuard to 0.5.2. Append separate SetCVar calls for Contrast 85, Brightness 55 and Gamma 1.5 after the existing seven startup commands, matching the screenshot's 85%, 55% and 1.5 values.
- Retained once-per-login/reload timing and documented EllesmereUI's contrast Optimize/Restore overlap. Later option changes can overwrite these startup values; continuous policies and resolution-specific layouts are unchanged. Adoption already copies the updated files.
- Verification: all 26 Lua 5.1 tests pass, including the ten calls in order with exact values and reload/zone-transition behavior. Live client rendering remains unverified.

## 2026-10-13 - Add six startup console settings

- Updated OverlapSettingsGuard to 0.5.1. After the existing loot-effect command, make separate SetCVar calls in order: cameraDistanceMaxZoomFactor 4, nameplateMaxDistance 41, targetNearestDistanceRadius 50, ffxGlow 0, volumeFog 0 and ResampleAlwaysSharpen 1.
- Retained the two-second world-entry delay and once-per-login/reload behavior. Documented existing camera, nameplate-distance and sharpening writers; later addon option/profile changes can overwrite these startup preferences. Continuous overlap rules remain unchanged.
- Verification: 26 Lua 5.1 tests cover individual calls, exact order/values, startup timing, zone transitions and reloads. Live client acceptance/effects still need in-game verification. Values are shared across 1080p, 1440p and 4K; adoption already copies the changed files.

## 2026-10-12 - Complete 1080p UNC adoption after a transient move failure

- A non-mutating DELETE-access scan found no denied handles in 5,015 destination Interface entries. A scratch directory move and the exact original Interface move succeeded; the original was restored immediately after the probe. The earlier sharing error did not establish that any user application was open, and its precise trigger remains unknown.
- Retried full adoption successfully. Destination Interface, WTF and Fonts were installed, with window resolution 1920x1080 and EUI panel scale 0.90. Original folders and copy logs are retained in destination `addon-backups/20261012-173033-8c0fb3a3e40843d28cd0763971b018e4`.
- Verified destination resolution, EUI scale and LongZhu selection, all seven custom font hashes, YUI font-path Lua/script hashes and presence of each original-folder backup. No remote processes were stopped or remote-management configuration changed.

## 2026-10-12 - Diagnose a locked destination during UNC adoption

- Exercised adoption against a writable UNC destination at 1920x1080. Interface, WTF and Fonts staged successfully, and the staged EUI panel scale was fitted to 0.90. Windows then refused to back up the destination Interface directory because it was in use; no replacement completed. The staged files and copy logs remain in destination addon-backups.
- Adoption failures now identify the operation and destination path, including backup and install steps, before reporting preservation or rollback. Added a simulated locked-directory regression that checks the error identifies the affected operation and original folders remain intact.
- Windows PowerShell regression checks pass. The destination lock must be released before retrying; remote-client state cannot be verified through the available management connection. No remote processes were stopped.

## 2026-10-12 - Push addon adoption from the current game root

- Reversed adoption's direction: run `Interface/adopt_addons.ps1` from the local source game root, passing the destination root as its only positional argument. The named parameter is now `-Destination`; a writable UNC share is supported through filesystem/robocopy operations.
- Reject runs whose current directory is not the game root containing the invoked script. Validate source Interface/AddOns and WTF/Config.wtf, existing destination directory and non-overlapping roots before staging. Check WoW processes locally on the source; close the remote client separately.
- Kept destination backups/logs, exact Interface/WTF replacement, optional Fonts merging, rollback and resolution fitting. Source files remain unchanged. Corrected the existing invalid-EUI test fixture so its rejection case actually executes.
- Verification: Windows PowerShell 5.1 tests with real robocopy pass for both argument forms, repeated transfers, all three resolutions, full source preservation, wrong working directory, invalid/overlapping roots, empty destination, local-client refusal, fonts, copy failure and folder/font rollback. Actual UNC permissions and remote-client state remain untested. No addon ownership or overlap policy changed.

## 2026-10-12 - Correct custom fonts to the game-root Fonts directory

- Corrected all seven YUI custom-font registrations and talent rank text to `Fonts\YUI*.ttf`, using the game-root Fonts directory beside Interface. Updated EllesmereUI's LongZhu damage-font selection to `Fonts\YUILongZhu.ttf`. Copies match the original YUI files; existing game font overrides are unchanged.
- Git tracks these seven custom font copies so a checkout includes the assets their paths require. Other game-root font overrides and caches remain excluded.
- Retained the misplaced Interface font copies and pre-correction EllesmereUI settings under `_classic_beta_/addon-backups/font-root-correction-20261012-164919`. Interface no longer contains a Fonts directory.
- Restored the disabled border/arrow/sound registrations and commented background values removed during the font change. No texture or sound file bytes or active paths were changed; the YUI source diff now changes only font paths.
- Adoption now stages source Fonts over a copy of destination Fonts, preserving destination-only files and backing up the original directory. Fonts participates in rollback. Sources without Fonts keep the destination font directory unchanged.
- Local verification covers all seven font registrations, byte identity/numeric glyphs, EllesmereUI damage-font application, adoption merge/preservation and folder/font rollback. A full game restart and live font loading/appearance checks remain required.

## 2026-10-12 - Move all YUI font references to Interface fonts

- Copied the remaining Inter Bold, Text, HOOGE, Damage1 and Dark files into `Interface\Fonts` using names without spaces, alongside the existing Inter Black and LongZhu copies. All seven files remain byte-identical to the original YUI assets.
- Inspected YUI Lua, XML, TOC and configuration references. All seven SharedMedia font registrations now use `Interface\Fonts`; talent ranks already use that folder. SharedMedia selection names remain unchanged. Blizzard font references and YBar's legacy missing-bundle path check do not reference these copied assets and remain intact.
- The adoption script already copies the complete Interface directory, including every font copy. No new overlapping setting or owner was introduced; existing overlap policies remain applicable. LongZhu remains the selected damage font through EllesmereUI.
- Verification: expanded font checks pass for all seven registered faces, copied hashes and numeric glyphs, plus EllesmereUI's saved LongZhu application. Full game restart and in-game font loading/appearance checks remain required. Upstream YUI updates can overwrite the registration patch.

## 2026-10-12 - Restore custom range font and select LongZhu damage text

- Replaced the previous locale-font substitution with YUI's original Inter Black face for its existing SharedMedia selection and talent rank text. The saved target-distance selection remains valid.
- Copied `YUI Inter Black.ttf` and `YUI LongZhu.ttf` byte-for-byte to `Interface\Fonts\YUIInterBlack.ttf` and `Interface\Fonts\YUILongZhu.ttf`. YUI uses these short, fresh asset paths for those selections instead of default fonts. This is a path workaround for the prior manifest errors, pending confirmation by the game client.
- With WoW closed, selected the LongZhu copy through EllesmereUI's existing saved `fctFont` setting. Original settings are backed up at `_classic_beta_/addon-backups/font-restore-20261012-154126/EllesmereUI.lua`. EllesmereUI already owns damage-font application; no new competing writer or overlap policy was added.
- Clarified adoption-script documentation: Interface fonts and WTF settings are copied; game-root Fonts remain excluded. Added a font-copy regression check. No font-size, UI-scale or layout changes were made.
- Verification: custom font registrations, copied hashes/numeric glyphs and EllesmereUI's actual startup font application pass locally. All 26 overlap guard tests, 18 fresh-profile compatibility checks and adoption checks (including Interface fonts and all three resolutions) pass. A full game restart is required for new assets and cached damage fonts; in-game appearance and absence of manifest errors at 1080p, 1440p and 4K remain pending. Upstream YUI updates may overwrite the Lua patch. TalentsForeverBook's existing Cinzel workaround is unchanged.

## 2026-10-12 - Avoid recurring addon font loading failures

- Confirmed both font errors in the October 12 08:02-10:37 session: TalentsForeverBook Cinzel-Bold at 08:03:10 and YUI Inter Black at 08:05:25, each reporting `Can't find file in build manifest`.
- Changed both TalentsForeverBook title paths to the existing regular Cinzel font. Changed YUI talent rank text and its legacy Inter Black SharedMedia registration to the client locale font, retaining the saved selection key. Font weight/face changes; sizes and layout remain unchanged.
- No new overlap setting or ownership change; existing policies remain applicable. The adoption script already copies these Interface Lua files. No top-level font overrides or saved settings were changed. The game arrow texture failure remains separate.
- Verification: Lua 5.1 syntax and overlap guard suite checked locally. A subsequent game session must confirm font loading and appearance at 1080p, 1440p and 4K. Upstream addon updates may overwrite this local patch.

## 2026-10-11 - Apply loot-effect console setting at startup

- Updated OverlapSettingsGuard to 0.5.0. After initial world entry and a two-second initialization delay, apply `outlineModeShowLootEffectWhenDisabled = 1` using SetCVar, equivalent to `/console outlineModeShowLootEffectWhenDisabled 1`. Run after the initial guard checks on every login and UI reload, regardless of the selected addon profile.
- Startup now waits for PLAYER_ENTERING_WORLD rather than PLAYER_LOGIN and is queued only once per session. Zone transitions and periodic checks do not repeat the CVar write. Arbitrary later addon/profile changes can still overwrite it.
- No new overlap rule, profile-table mutation, layout or adoption-script change is required. Chat-only notifications remain unchanged.
- Verification: all 26 Lua 5.1 tests pass, including delayed startup, later world entries and reload reapplication. Live loot rendering remains pending.

## 2026-10-11 - Remove obsolete OverlapSettingsGuard integrations

- Updated the local guard to 0.4.3. Deleted 11 obsolete policies for removed addons and the Leatrix, Plater and Kallye adapters; removed their TOC dependencies and unused RestedXP nameplate-distance key. The pack now has ten rules for YUI, EllesmereUI, RestedXP and TalentsForeverBook.
- Removed obsolete adapter fixtures and tests, plus orphaned Kallye setup test scripts. Retained current-pack profile/template, hook, combat, timer, reload-message and refresh-retry coverage. Added installed-pack dependency and unused-adapter checks.
- Updated the policy table, inventory and AGENTS.md removal requirements. Existing overlap ownership and chat-only reporting remain intact. No new overlapping setting was introduced; no settings, layout or adoption-script changes are required.
- Verification: all 24 Lua 5.1 guard tests pass. Live in-game confirmation remains pending.

## 2026-10-11 - OverlapSettingsGuard messages moved to chat

- Updated local OverlapSettingsGuard to 0.4.2. Removed both notification popups; setting names, ownership reasons and affected profiles remain in chat. Changes requiring a reload print a `/reload` reminder instead of a dialog.
- Existing overlap policies and combat deferral remain unchanged. Chat output uses the existing game print API across 1080p, 1440p and 4K; no layout or adoption-script changes are needed.
- Verification: all 34 Lua 5.1 guard tests pass, including login, stored-profile changes, option hooks, timer enforcement and chat reload reminders. Live in-game confirmation remains pending.

## 2026-10-11 - Verify new characters and resolution-aware adoption

- User confirmed the repaired EUI frames and RestedXP arrow work in-game. Verified EUI/YUI shared Default profiles and RestedXP's separate character profiles. Saved the working RXP layout as its supported new-character default with complete upstream defaults and overlap options off; guide progress remains separate.
- Removed the three inactive EUI standalone folders from the installation to prevent default-enabled conflicts on fresh characters. The shared core and selected modules remain byte-identical to the upstream release.
- Added optional -Resolution to adopt_addons.ps1 for 1920x1080, 2560x1440 and 3840x2160. It changes only the staged gxWindowedResolution and EUI panelScale (0.90/1.00/1.50), preserving gameplay UI scale, positions, Unicode and source settings. Without this option copying is unchanged; existing backup/rollback behavior is retained.
- Verified 18 new class/faction profiles with the installed EUI/AceDB engines; 34 guard tests pass. Adoption tests pass for transfers/repeated runs, all three resolutions, source preservation, rejection paths and rollback. Resolution tests establish panel fit; live appearance on other displays remains unverified.
- Latest BugGrabber session records one blocked SubmitBug() call attributed to DungeonsForever through Blizzard PTR feedback. No EUI/RestedXP errors were captured; the separate feedback-report issue remains unresolved. WTF remains excluded from Git and is transferred by the adoption script.
## 2026-10-11 - Repair EUI startup and RestedXP arrow visibility

- Confirmed that EUI 9.4 standalone modules deliberately become inert when another standalone is enabled. Installed the unmodified shared EllesmereUI 9.4 core with UnitFrames, RaidFrames, Nameplates, Options and Locales from the official suite release; no other suite modules are installed. Disabled the three standalone addons for all four stored characters.
- Migrated the minimal player-castbar and eight raid-group preferences into EllesmereUIDB. Explicitly enabled EUI player/target frame sources. Upgraded OverlapSettingsGuard to 0.4.1, updated ownership dependencies/database and covered encoded spec overrides for nameplate class power.
- Stopped the lingering WoW process at the user's request before writing settings. Explicitly enabled RestedXP and its arrow, disabled raid hiding and reset the arrow to a top-center anchor with scale 1 and 32-unit size. Preserved current guide and progress. Saved settings/logs do not establish the exact runtime reason; arrow rendering still requires a valid active waypoint and player location/facing.
- Latest BugGrabber errors are empty; old FrameXML/taint reports are from previous configurations. Verified 704 installed upstream files against archive bytes, six Interface 16001 TOCs, four character addon lists and saved-variable settings. All 34 Lua 5.1 guard tests pass. Live rendering at 1080p/1440p/4K remains pending.
## 2026-10-11 - Restore OverlapSettingsGuard with YUI/EllesmereUI policies

- Restored the local guard from ClassUI and upgraded it to 0.4.0. Added YUI and EllesmereUI adapters and nine policies; retained twelve legacy policies, of which the RestedXP/TalentsForeverBook talent-guidance rule is active in this installation.
- Enforce YUI nameplate outline/friendly-nameplate synchronization off while EllesmereUI Nameplates loads; enforce YHUD mana/rage/energy/combo-point displays off while EllesmereUI Unit Frames loads. Cover active/stored profiles, stored HUD sets and druid forms; retain swing timers. Refresh live runtimes and retry failed refreshes.
- Keep EllesmereUI nameplate class-power displays off while its unit frames load, including saved profiles/spec presets. Assign quest/gossip/reward automation and junk selling to YUI, disabling competing RestedXP options. TalentsForeverBook owns talent guidance. Navigation and optional statistics remain user-adjustable.
- Enabled the guard for four stored characters. It checks after login, on supported hooks and every two seconds, defers during combat, reports blocked APIs, and exposes status/reasons via /osg. Addon enable lists and optional appearance settings are tracked separately; the guard does not turn disabled addons on.
- Verification: 33 Lua 5.1 tests pass, including missing APIs, refresh retries, profile resets, combat deferral and retained swing timers. Upstream YUI/EllesmereUI packages remain unmodified. Live rendering and three-resolution validation remain pending.

## 2026-10-11 - Install EllesmereUI standalone frames and nameplates

- Installed EUIStandaloneUnitFrames, EUIStandaloneRaidFrames and EUIStandaloneNameplates 9.4 from the official CurseForge files linked in the inventory. All declare Interface 16001 and Forever 1.60.1 support. Enabled all three for four stored characters.
- Assigned individual frames, party/raid frames and nameplates to EllesmereUI. Left YUI's unloaded YUnitFrames product unchanged. Enabled EllesmereUI's player castbar and visibility of all eight raid groups in saved settings.
- Disabled YUI's nameplate outline and friendly-nameplate synchronization. Disabled YHUD mana/rage/energy/combo-point resource displays across all nine Forever classes, druid form overrides and the saved HUD configuration set; retained swing timers and cooldown tracking. EllesmereUI nameplate class-power display is off by upstream default.
- No upstream Lua/XML was edited and OverlapSettingsGuard remains absent under the prior code restriction. Settings are not continuously enforced, and unrelated automation/talent/navigation overlaps remain configurable.
- Verified archive integrity and paths, all 1,598 installed files against archive bytes, saved-variable Lua syntax and intended resource settings. Live rendering, group combat and 1080p/1440p/4K layouts remain unverified.

## 2026-10-11 - Restore specialist addons and inspect YUI frames

- Installed latest published Forever-compatible Auctionator 340, DungeonsForever 1.8.0, TalentsForeverBook 0.38.1 (beta) and !BugGrabber v12.1.0. Sources are linked in the inventory; all declare Interface 16001.
- Checked archive integrity and paths; verified all 983 installed files against archive bytes with zero mismatches. No upstream addon code was locally edited. Live loading remains pending.
- Documented talent-guidance overlap with RXPGuides and optional DungeonsForever navigation overlap. No settings or overlap policy were changed, and OverlapSettingsGuard remains absent.
- Traced unavailable YUI individual frames to an unloaded YUnitFrames product; it does not provide group frames. Nameplate presets require external Platynator plus an existing YUI profile. Recorded recommendations without applying frame fixes.

## 2026-10-11 - Clean YUI and RestedXP trial

- Switched to main and removed every previous addon folder, including OverlapSettingsGuard. Installed unmodified YUI v338 from the wclbox Forever download and RXPGuides v4.11.23 from the official GitHub release. Both declare Interface 16001 and camelot loading.
- Deleted the entire WTF folder at the user's request. No backup was created; the user already backed up. Kept the game's top-level Fonts directory and the adoption utility.
- Identified optional overlaps in quest/gossip automation, junk selling, quest-item displays, experience statistics and map navigation. No guard or custom settings are installed for this fresh-default trial.
- Verified download archive integrity, staged TOCs, final folder inventory, copied-file hashes and absence of WTF before launching. In-game behavior and all three target resolutions remain unverified.

## 2026-10-10 - Kallye group frames installed and obsolete UI integrations removed

- Installed Kallye Raid Frames release 12.1.003c ([CurseForge file 8975166](https://www.curseforge.com/wow/addons/kallye-raid-frames/files/8975166)); its TOC reports 12.1.003 and includes Interface 16001. Enabled it for all four stored characters. Backed up WTF before installation to `_classic_beta_/addon-backups/kallye-install-20261010-214742/WTF`.
- Enabled health highlights, custom group auras and raid markers. Set nearby/out-of-range alpha to 100/55, three buffs at 75% size and three debuffs at 125% size. Kept inverted bars, solo frames and nameplate styling off. Hid Blizzard auras in favour of Kallye's; kept the taint-method workaround off. Enabled role icons, hid damage-role icons and realm suffixes, and enabled death icons. Individual Blizzard unit frames and Leatrix's raid toggle remain unchanged.
- Added a local `LocalSetup.lua` and TOC entry for one-time raid-style party setup at next login. It waits for Edit Mode readiness and combat to end, changes only the party style, copies an immutable preset if needed, and preserves later user changes. Serialized offline layout caches are unchanged. Upstream updates may overwrite the patch.
- OverlapSettingsGuard 0.3.1 adds `kallye.nameplates` to prevent Kallye nameplate styling while Plater loads. Group-frame features remain available.
- Removed the obsolete ForeverUI adapter, TOC dependency, eight policies, related adapter settings, fixtures and tests from the active branch. Replaced generic guard coverage with current addon scenarios. The `ForeverUI` backup branch and migration backup preserve rollback; historical change-log entries remain historical records. RestedXP upgrade tooltips are now user-adjustable; existing saved values are unchanged.
- Updated inventory, overlap-policy documentation and project changelog. Verification: 20 Lua 5.1 guard tests and four setup tests pass. Live group combat appearance, aura behavior and Edit Mode API effects still need an in-game login.

## 2026-10-10 - ForeverUI replaced by ClassUIEnhanced and Plater

- Created local backup branch `ForeverUI` at `50579665b579eb33f52f649f1834c57af2fea606`, preserving the complete pre-migration tracked addon bundle. Copied all WTF settings to `_classic_beta_/addon-backups/foreverui-replacement-20261010-211803/WTF` before changing settings. Git excludes WTF.
- Installed unmodified ClassUIEnhanced 3.1.0 ([CurseForge file 9106446](https://www.curseforge.com/wow/addons/classuienhanced/files/9106446)) and Plater v658 ([file 9119013](https://www.curseforge.com/wow/addons/plater-nameplates/files/9119013)). Their main and Camelot TOCs respectively declare Interface 16001, matching client 1.60.1.70338. Existing Plater saved profiles are retained.
- Uninstalled ForeverUI 0.4.65 and its bundled QuestForever 0.4.7 by moving their folders and saved-variable files into the migration backup. Removed their character AddOns.txt entries; enabled ClassUIEnhanced, Plater and OverlapSettingsGuard for all four stored characters.
- Blizzard owns action bars, bags and full unit/party/raid frames. ClassUIEnhanced owns trackers, player health/resources and player/target/focus cast bars; Plater owns nameplates. Leatrix Enhance minimap and Minimap button bag are on, Square minimap remains on, Hide addon menu is off, chat font is enabled at 12 and Move editbox to top is on. Leatrix Combat plates is off. Standard game keybindings and Blizzard layouts are preserved.
- OverlapSettingsGuard 0.3.0 adds rules for Leatrix combat plates and Plater class resource/personal health-mana displays, enforcing across stored Plater profiles and live CVars after combat. RestedXP's maximum nameplate-distance rule now depends on Plater. Legacy ForeverUI rules remain inactive. Leatrix options are labelled locked only when their policy is active.
- ClassUIEnhanced manages duplicate Blizzard cooldown viewers through its own first-login prompt; allow it to hide the viewers while retaining the Cooldown Manager data source. Personal Plater health/resource/buff displays disappear with its personal bar, leaving CUE trackers. Leatrix quest automation and RestedXP navigation remain unchanged.
- Verification: 27 Lua 5.1 guard tests pass, including no-ForeverUI ownership, inactive option labels, stored profiles, profile changes and combat deferral. Package contents, TOC references, saved-setting syntax and backup integrity are checked separately. In-game cooldown behaviour, quest-item use and group-frame appearance still require login.

## 2026-10-10 - Removed adoption confirmation prompt

- Removed the typed `CLOSED` confirmation from `Interface/adopt_addons.ps1`. With the source argument supplied, adoption proceeds without interactive confirmation.
- Updated usage documentation and regression tests to reject any interactive prompt. Backup, rollback and validation behavior are unchanged.

## 2026-10-10 - Addon and settings adoption script

- Added `Interface/adopt_addons.ps1`, accepting one positional source game-root path (including a UNC share). The destination comes from the script location. It requires source Interface/AddOns and WTF/Config.wtf, rejects overlapping roots and links, refuses local WoW processes, and requires confirmation that source WoW is closed.
- Stages copies with robocopy, retains dated destination backups under the game root's `addon-backups`, then replaces Interface and WTF exactly. Copy failures preserve the originals; replacement failures trigger rollback. Logs and failed copies are retained. Fonts and resolution/UI scale settings are unchanged; the utility remains available if absent from the source.
- Documented usage and restoration in `AddOns/readme.md`. No addon packages or overlap policy changed, and no live saved variables were modified.
- Verification: Windows PowerShell 5.1 regression tests with real robocopy in temporary installations cover exact replacement, backup contents, repeat runs, unchanged source/settings/Fonts, invalid sources, local WoW refusal, cancellation, copy failure and replacement rollback. UNC access depends on the destination's share permissions and has not been exercised against another machine.

## 2026-10-10 - Party frames enabled for groups

- Cause: the shared ForeverUI Default profile hid Blizzard's party frames (`hideBlizzardParty = true`) while all replacement role grids were off (`gridsUp.dps`, `tank` and `healer` were false). This left two-person parties without a visible party frame.
- With WoW closed, set `frames.gridsUp.dps = true` and `frames.gridSolo.dps = false` in `WTF/Account/308676042#1/SavedVariables/ForeverUI.lua`. The DPS grid now shows in parties and raids and stays hidden solo. Existing layout and click bindings are preserved.
- Overlap inspection: ForeverUI and Blizzard provide party frames; Blizzard's remain hidden to avoid duplicates. No addon package or overlap policy changed.
- Verification: saved variables load in Lua 5.1; a full table comparison confirms only the two intended settings changed. Executed ForeverUI's actual grid-state and visibility functions: party driver is `[group:raid] hide; [group] show; hide`, with no minimum party size; raid headers show in raids. All 24 OverlapSettingsGuard tests pass. Visual confirmation awaits the next login and party invite.
- Backup: `D:\tmp\wow-party-frames-20261010-075324\ForeverUI.lua`.

## 2026-10-09 - Quest automation moved to Leatrix Plus; OverlapSettingsGuard 0.2.1

- Replaced the two rules disabling Leatrix quest/gossip automation with four rules disabling RestedXP quest acceptance/turn-in, gossip, guide-selected rewards and calculated reward choices. All stored profiles and templates are covered while both add-ons load.
- With WoW closed, enabled Leatrix AutomateQuests, AutomateGossip, AutoQuestRegular, AutoQuestDaily, AutoQuestWeekly and AutoQuestCompleted; AutoQuestShift is off. Set all four RestedXP automation flags off in every current account profile. No account or character templates currently exist. Leatrix settings remain user-adjustable.
- RestedXP flight-path, binding and trainer automation are unchanged. Reward recommendations remain available. Leatrix still requires manual selection when a quest offers multiple reward choices.
- Verification: 24 guard tests pass, including enforcement across profiles and changes from options; Lua syntax and saved settings checked. In-game behavior awaits the next login.
- Saved-variable backups: `D:\tmp\wow-quest-automation-20261009-183620`.

## 2026-10-09 — RestedXP Guides installed; OverlapSettingsGuard 0.2.0

- Installed RestedXP Guides v4.11.21 (CurseForge file 9104439), folder `RXPGuides`. Its main TOC lists Interface 16001, and its file list loads Forever's own guides, quest data and flight data for game type `camelot`. RestedXP's own add-on incompatibility list (TomTom, SilverDragon, TotemTimers, Leatrix Maps, Narcissus) flags nothing installed: it checks "Leatrix Maps" with a space, which never matches the `Leatrix_Maps` folder. No RestedXP saved variables existed before. Not yet confirmed in game.
- Overlaps found with RestedXP, now locked by OverlapSettingsGuard (six new rules, 14 in all):
  - flight times: Leatrix Plus "Show flight times" is locked off (already off); RestedXP's are kept;
  - junk selling: Leatrix Plus keeps "Sell junk automatically", so RestedXP Auto Sell Junk and ForeverUI Loot "Sell junk" are locked off (both already off);
  - talent guides: RestedXP's are locked off in favour of Talents Forever;
  - item upgrade tooltips: RestedXP's are locked off in favour of ForeverUI's Loot module (RestedXP's quest reward advice stays on);
  - nameplate range: RestedXP's "Maximize Nameplate Distance" set the range to 41 at every loading screen, overriding ForeverUI's 60. It is locked off.
- Checked, no overlap: rare scanning (RestedXP's scanner is disabled on this client, RareScanner stays), target marking vs ForeverUI Markers, RestedXP's quest item window, its quest log additions, its leveling tracker vs ForeverUI XPBar.
- OverlapSettingsGuard now switches a setting off at every level the add-on stores it:
  - ForeverUI: the active profile (live), plus every other profile in `ForeverUIDB.profiles`.
  - RestedXP: the live profile of this character, every stored profile in `RXPSettings.profiles`, the account template `RXPData.defaultProfile` and the character template `RXPCData.localDB`.
  - Leatrix Plus: has only one account-wide copy, `LeaPlusDB`.
  - The chat line names the other copies it changed.
- Expected at the first login with RestedXP, all switched off by the guard with one popup offering a reload:
  - Leatrix Plus Automate quests and Automate gossip (both on);
  - ForeverUI QuestForever and "open the quest guide on accept" (both on in profile "Default");
  - RestedXP talent guides, upgrade tooltips and nameplate distance (on by RestedXP's defaults).
- Tests: 23 cases pass and all add-on Lua files parse. One test expectation was wrong and was corrected: a stored RestedXP profile without its own value inherits the account template, as AceDB does, so the guard doesn't write it. Not yet confirmed in game.

## 2026-10-09 — OverlapSettingsGuard 0.1.0 added

- New add-on of our own, `OverlapSettingsGuard`. It keeps settings that duplicate another installed add-on's feature switched off: at login, after any change in game (switched back on the next frame, after combat if in combat), with a chat line and a popup giving the reason. There is no in-game override. Its eight rules and how it works are in [OverlapSettingsGuard/readme.md](OverlapSettingsGuard/readme.md).
- Active now: the three Leatrix Plus rules overlapping ForeverUI (Enhance minimap, Move editbox to top, Set chat font size). They were already off (2026-10-07 entries), so the first login changes nothing. The five RestedXP Guide rules (Leatrix quest/gossip automation; ForeverUI QuestForever, guide on accept, waypoint arrow) start once RestedXP Guide is installed.
- Leatrix Plus checkboxes have no names, so they are found by page and position as of Leatrix Plus 1.60.11. If a Leatrix update moves one, `/osg` shows that rule as "cannot enforce" rather than switching the wrong option.
- Tests: `tools/overlapsettingsguard-tests` (16 cases, Lua 5.1 through `lupa`, run with `uv`) pass; all add-on Lua files parse (luaparser). One test caught a bug before release: a Leatrix checkbox never shown since login holds a stale state, so clicking it could have switched the option on. The switch now reads the live value into the box first. Not yet confirmed in game.
- `AGENTS.md`: new policy line. Overlapping settings of each installed or updated add-on go into OverlapSettingsGuard's policy.

## 2026-10-08 — Blocked-action errors from the 8 Oct session

The game logs (`General.log`, `FrameXML.log` and the others) had no Lua errors for the 21:04–22:20 session. BugGrabber recorded three blocked actions:

- 21:07, ForeverUI: `ForeverUIbar2Button3:SetAttribute()`. Cause: an `ACTIONBAR_SLOT_CHANGED` in combat reached the button through ForeverUI's own event driver (`OwnButtons.lua`, the 4 Oct patch). Blizzard's `UpdateAction` ends in `UpdatePingAttributes`, which calls `SetAttribute` on the protected button, and that call ran as ForeverUI. Fix in `ForeverUI/Modules/ActionBars/OwnButtons.lua`: `GuardPing` wraps `UpdatePingAttributes` on ForeverUI's own buttons only. In combat it records the button and returns; the driver replays the update on `PLAYER_REGEN_ENABLED`. `ActionBars.lua` `GuardButtonCooldowns` also applies it, so every ForeverUI button gets the guard when it is built. Ping targets on a changed slot update when combat ends; icons, counts and cooldowns update as before.
- 21:44, QuestForever: `Frame:SetPassThroughButtons()`, after opening the quest log (world map) in combat. Cause: `AcquirePin` runs Blizzard's `CheckMouseButtonPassthrough` on each QuestForever pin, and that call is protected in combat. Fix in `QuestForever/Pins.lua`: the pin mixin's `SetPassThroughButtons` does nothing in combat and calls the original otherwise. A pin placed in combat keeps its previous pass-through setting.
- 21:29, DungeonsForever: `SubmitBug()`. On a quest turn-in, the beta client's built-in feedback module (`Blizzard_PTRFeedback`, `AutoQuestReport` attached to `QuestFrame`) submitted its report while execution was tainted by DungeonsForever. The only effect was that one automatic beta quest report was not sent. The exact tainted value was not identified. Blizzard's report code reads only game API results and its own survey frame, so the likely source is DungeonsForever showing tooltips through `GameTooltip`, which runs the feedback module's tooltip hook as DungeonsForever. No fix is available on the add-on side. A related bug was fixed: `DungeonsForever/Core/DungeonUI.lua` `makeRow` (loot cards) assigned its row to the global `r`. The variable is now local; the function already returned the row, so nothing else changes.
- All four edited files parse (luaparser); a scan of `DungeonsForever/Core` finds no other global writes besides its saved variables and slash commands. Not yet confirmed in game. Check BugGrabber after the next session that includes combat. A ForeverUI, QuestForever or DungeonsForever update overwrites these patches.

## 2026-10-07 — Leatrix Plus minimap and edit box options off

- At the user's request, turned off Leatrix Plus "Enhance minimap" (`MinimapModder`) and "Move editbox to top" (`MoveChatEditBoxToTop`) in `WTF/Account/308676042#1/SavedVariables/Leatrix_Plus.lua`, with WoW not running. ForeverUI's Minimap module and its chat "Where you type: Above the chat" setting now handle these alone. Leatrix's `SquareMinimap` and other minimap sub-settings only apply under "Enhance minimap", so they are inactive too. The pre-change file is still `D:\tmp\wow-forever-chat-minimap-2026-10-07\Leatrix_Plus.lua.orig`. Confirmed in game by the user on 2026-10-07.

## 2026-10-07 — Chat font held at ForeverUI's size; late minimap buttons gathered

- Chat font. Cause: Leatrix Plus "Set chat font size" was on at 20, ran after ForeverUI at login, and hooked `FCF_SetChatWindowFontSize`, so the chat showed Leatrix's size until opening ForeverUI's options repainted it at ForeverUI's 12. Fixes:
  - Turned Leatrix Plus `SetChatFontSize` off in `WTF/Account/308676042#1/SavedVariables/Leatrix_Plus.lua` (WoW was not running). The original is in `D:\tmp\wow-forever-chat-minimap-2026-10-07\Leatrix_Plus.lua.orig`.
  - `ForeverUI/Modules/Chat/Chat.lua`: new `HookFontSize`, called from `OnEnable`, re-applies ForeverUI's chat size to every chat window (whisper windows included, via `CHAT_FRAMES`) after `FCF_SetChatWindowFontSize`, `FCF_OpenTemporaryWindow`, `PLAYER_ENTERING_WORLD`, `UPDATE_CHAT_WINDOWS` and `UPDATE_FLOATING_CHAT_WINDOWS`. The game's stored per-window size (Leatrix had written 20 for window 1) no longer wins after login. A size of "The UI's own" (0) still leaves the game's size alone.
- Minimap buttons. Cause: ForeverUI collected minimap buttons into its bar (default spot: the screen's top-right corner, `/fui move` → "Minimap buttons") only once, at `PLAYER_LOGIN`. Buttons made later stayed on the map's edge: those of add-ons loading after ForeverUI (Leatrix Plus, Leatrix Maps, RareScanner, Talents Forever) and LibDBIcon buttons registered at or after login. Fix in `ForeverUI/Modules/Minimap/Minimap.lua`:
  - `WatchForLateButtons` runs the gather again, coalesced to once per second and out of combat, after `ADDON_LOADED`, `PLAYER_ENTERING_WORLD`, LibDBIcon's `LibDBIcon_IconCreated` callback, and 5 s and 15 s after enable.
  - `SquareButton` now uses a button's own `.icon` texture when it has one. LibDBIcon creates its dark round background first, which had been picked as the icon and stretched instead of the picture.
- Overlaps left in place: Leatrix Plus "Enhance minimap" (`MinimapModder`, with `SquareMinimap`) and ForeverUI both square and restyle the minimap. Leatrix "Move editbox to top" and ForeverUI "Where you type: Above the chat" both move the input line.
- Both Lua files parse (luaparser). Confirmed in game by the user on 2026-10-07: chat at 12, minimap icons in the top-right bar. A ForeverUI update overwrites these patches.

## 2026-10-07 — Maple Mono font for zh-TW (outside AddOns)

- After the switch to `textLocale "zhTW"`, the client used its zh-TW fonts, which `_classic_beta_/Fonts` did not override. Copied `MapleMono-NF-CN-Regular.ttf` from [Maple Mono v7.9 NF CN unhinted](https://github.com/subframe7536/maple-font/releases/download/v7.9/MapleMono-NF-CN-unhinted.zip) to `bHEI00M.ttf`, `bHEI01B.ttf`, `bKAI00M.ttf`, `bLEI00D.ttf` and `arheiuhk_bd.ttf`. The existing ten font overrides were already that same file (matching MD5).
- Deleted the five `.slug`/`.slugo` font caches that had been built from Blizzard's original fonts so the client rebuilds them. Not yet confirmed in game.

## 2026-10-07 — Five add-ons installed, ForeverMeter removed

- Installed the latest CurseForge files that list Forever 1.60.1: Leatrix Maps 1.60.18-forever (file 9091243), BugGrabber v12.1.0 (8907587), Details! Details.20261006.15326.172 (9082615, eight folders), Talents Forever 0.37.1 beta (9059414, folder `TalentsForeverBook`), and DungeonsForever 1.6.9 (9065559). Every package has a TOC declaring Interface 16001; Details! uses `_Camelot.toc` files, a suffix the client binary recognizes.
- Uninstalled ForeverMeter at the user's request: deleted the folder, permanently deleted `WTF/Account/308676042#1/SavedVariables/ForeverMeter.lua` and `.lua.bak` (no backup, as requested), and removed its line from the two character `AddOns.txt` files that listed it.
- Overlaps: Details! replaces ForeverMeter as the only meter. BugGrabber and ForeverUI both install a Lua error handler; BugGrabber has no display without BugSack. Leatrix Maps and Leatrix Plus both touch the world map; QuestForever adds its own map pins.
- The account still holds `Details.lua` and `Details_Streamer.lua` saved variables from the Details! install removed on 2026-10-02; the new Details! will read them.
- Not yet confirmed in game. Details! last failed here on 2026-10-02 with missing-library and unsupported-event errors, so check `Logs/General.log` after the next login.

## 2026-10-04 — ForeverUI Edit Mode taint: verified fixed, !TaintProbe removed

- Verification run 18:36 to 18:43, with a `/reload`: `Logs/General.log` holds no Lua errors, and ForeverUI's error log has nothing after 18:35:25, the previous session. After the reload, `!TaintProbe` recorded no tainted Edit Mode snap writes. The fields that had been tainted at login, `snappedToFrame` on `MainActionBar`, `MainStatusTrackingBarContainer` and `StanceBar`, and `MultiCastActionBarFrame.inMainActionBarState`, are no longer tainted. What remains tainted is only ForeverUI's own marker fields (`fuiConcealed`, `fuiFadeHook`, `fuiGrabHeld`), which Blizzard code does not read, and two ChatFrame1 history fields written when ForeverUI prints to chat.
- Removed `!TaintProbe`: the folder, its saved variables and its lines in the four characters' `AddOns.txt`. All are moved to `D:\tmp\wow-forever-foreverui-taint-2026-10-04\`.
- The earlier local patches stay in place: the `Layout.lua` fade, `Movers.lua` `SetPointBase`, the `Skin.lua` `Deafen` and `Conceal` changes, and the stance/pet/possess list in `ActionBars.lua`. Each removes a real addon write into Blizzard frames, even though the root cause was the shared button loop. A ForeverUI update will overwrite all of these. Check whether upstream has moved its buttons out of Blizzard's loops before reapplying.

## 2026-10-04 — ForeverUI Edit Mode taint: root cause found, own button loop (fifth patch)

- The error recurred at 18:26:40 after the fourth patch. `!TaintProbe` caught 45 tainted Edit Mode snap writes, all to `MainActionBar`, `MainStatusTrackingBarContainer` and `StanceBar`, with one call stack and no ForeverUI frame on it: `ActionBarController.lua:68` (bar event) → `ActionBarController_UpdateAll` → `ValidateActionBarTransition` → `MainActionBar:Show` → `UpdateVisibility` → `EditModeManager:UpdateActionBarLayout` → `UpdateBottomActionBarPositions` → `SetPoint` → `SetSnappedToFrame`.
- Cause: `ActionBarController_UpdateAll` first runs `for k, frame in pairs(ActionBarButtonEventsFrame.frames) do frame:UpdateAction() end`. ForeverUI's own action buttons, built from `ActionBarButtonTemplate`, are in that list. Running them makes the rest of the call run as ForeverUI, so Edit Mode's bar layout records are written tainted on every page or bar-state event. Every later Edit Mode pass reads them and redraws Blizzard's party frames tainted. The same shared loops are why ForeverUI wrapped Blizzard's buttons' cooldowns, and that wrapping tainted other Blizzard code.
- Fix:
  - New `ForeverUI/Modules/ActionBars/OwnButtons.lua` (added to `ForeverUI.toc` after `ActionBars.lua`). It is ForeverUI's own event and update driver for its buttons, mirroring the events of Blizzard's `ActionBarButtonEventsFrame` and `ActionBarActionEventsFrame`, including the spell-ID filter for spellcast events, plus the `ActionBarButtonUpdateFrame` OnUpdate. It takes ForeverUI's buttons out of the two keyed lists and keeps them out through secure post-hooks on `RegisterFrame` and `UnregisterFrame`.
  - `ActionBars.lua`:
    - `DropSleepingPadsFromLoop` now also drops ForeverUI's buttons from the ordered `ActionBarButtonEventsFrame.frames` and hands them to the new driver. Everything from the first such entry to the end goes, so no Blizzard entry is shifted. If an awake Blizzard button sits after them, as in controller mode, it leaves the list alone as before.
    - `GuardButtonCooldowns` now wraps only ForeverUI's own buttons. Blizzard's buttons are no longer touched.
    - `OnEnable` runs the sweep straight after building the bars, before the first world-entry bar update.
- Not covered: Blizzard's assisted-combat highlight and the "countdown for cooldowns" option are not forwarded to ForeverUI's buttons. ForeverUI's buttons still share Blizzard's range and usability watcher lists, which affect colours only.
- Backups in `D:\tmp\wow-forever-foreverui-taint-2026-10-04\`: `ActionBars.lua.before-ownloop` and `ForeverUI.toc.orig`. `ActionBars.lua`, `OwnButtons.lua` and `Skin.lua` parse as Lua 5.1. `!TaintProbe` stays installed to verify the fix.

## 2026-10-04 — ForeverUI Edit Mode taint: fourth patch (Conceal) and !TaintProbe

- Result of the third patch: after a full restart at 12:43, entering Edit Mode still raised the `CompactUnitFrame.lua:699` error (6× from 12:44:02). The chat `AddMessage` "attempt to call a nil value" error did not return with taint logging off, which fits its link to taint logging.
- New evidence from the 11:58 `taint.log`: the other blocked actions have origin lines at `EditModeSystemTemplates.lua:731 ClearFrameSnap()` (on `MainStatusTrackingBarContainer` and `MainActionBar`) and `ObjectiveTrackerFrame:GetAvailableHeight()`. Edit Mode writes those snap records (`snappedToFrame`, `snappedFrames`) itself through its `SetPoint`/`ClearAllPoints`/`Hide` overrides. They carry ForeverUI's taint when that Lua runs inside ForeverUI's call. Edit Mode's `for snappedFrame in pairs(self.snappedFrames)` loop matches the `(for generator)` origin seen at entry.
- Fix in `ForeverUI/Core/Skin.lua`: `skin.Conceal` now fades every Edit Mode system frame (detected by the `HideBase`/`system` fields Edit Mode puts on them) instead of `HideBase` plus a reparent to a hidden frame. This covers the bag bar, cast bar and status-tracking manager hidden by the user's settings. Their OnHide no longer runs Edit Mode code under ForeverUI's name. Parses as Lua 5.1.
- Added `!TaintProbe` 2.0, a temporary read-only diagnostic. The `!` makes it load before ForeverUI. It post-hooks every Edit Mode system's `SetSnappedToFrame` and `ClearFrameSnap`, and records the call stack whenever a snap record ends up tainted. It also snapshots tainted fields on Edit Mode systems and party frames at login, 10 s after, and on entering Edit Mode, into `TaintProbeDB`. Enabled in all four characters' `AddOns.txt`.

## 2026-10-04 — ForeverUI Edit Mode taint: cooldown wrappers on Blizzard buttons (third patch)

- Evidence: `Logs/taint.log` (taint logging was on from 11:58 to 12:04). On each "Edit Mode" click from the game menu, the game blocked `TargetUnit()` and `FocusUnit()` in `RefreshTargetAndFocus` as ForeverUI's. It then raised the `CompactUnitFrame.lua:699` error in `RefreshPartyFrames`. So the taint entered Edit Mode's setup sequence before either step, in the part that shows the stance, pet and possess bars. In combat the same log shows Blizzard's `MultiBarBottomLeft` buttons running tainted from `ActionButton.lua:891 ActionButton_SetOrClearCooldown()`.
- Cause: ForeverUI writes its own Lua function in place of `SetCooldown` on Blizzard's button cooldown frames (`skin.GuardCooldowns`, called from `Skin.Deafen` for every child of a Blizzard bar it hides) and in `ActionBars.lua`'s `BLIZZARD_BUTTONS` sweep. A field written by an addon taints every Blizzard read of it. When Edit Mode opens it shows the stance, pet and possess bars, their buttons update their cooldowns, and the rest of the pass, including the party frames, runs tainted.
- Fix:
  - `Core/Skin.lua`: removed `skin.GuardCooldowns` and its call from `Deafen`, which still takes the mouse off hidden Blizzard buttons.
  - `Modules/ActionBars/ActionBars.lua`: removed `StanceButton`, `ShapeshiftButton`, `PetActionButton` and `PossessButton` from `BLIZZARD_BUTTONS`. Those bars drive their own buttons and never run in the shared action-button loops the wrapper was guarding.
  - Blizzard's main and multi-bar action buttons are still wrapped, as upstream intended.
- Backups: `D:\tmp\wow-forever-foreverui-taint-2026-10-04\Skin.lua.before-cooldowns` and `ActionBars.lua.before-cooldowns`. Both files parse as Lua 5.1 (luaparse).
- Removed the `TaintProbe` diagnostic addon. It never loaded, because the game was not restarted after it was added, and `taint.log` answered the question. It is kept at `D:\tmp\wow-forever-foreverui-taint-2026-10-04\TaintProbe`.
- Other errors in this session's `General.log`:
  - `attempt to call a nil value` from chat `AddMessage` (150×, 11:56 to 12:04). It began in the minute taint logging was switched on and does not pass through ForeverUI's code. `taintLog` was not saved to `Config.wtf`, so it is off at the next launch. If the error comes back without it, it needs another look.
  - `GetAuraDataByIndex()` at 11:21: one occurrence, before the `Movers.lua` patch.
- Residual, not user-visible: the taint log still shows ForeverUI's own code hitting secret values inside its `pcall` guards, and Blizzard's main and multi-bar buttons blocked in combat by the remaining wrappers. The full cure is upstream's: take ForeverUI's own buttons out of Blizzard's shared button loops.
- Not yet confirmed in game.

## 2026-10-04 — TaintProbe diagnostic installed

- The `Movers.lua` patch below did not stop the error. ForeverUI's error log recorded it again at 11:57:08 and 11:57:27, after the patched file had loaded. `General.log` names only the tainting addon, not the tainted value, and `Logs/taint.log` was not written.
- Added a local read-only addon, `TaintProbe`. Ten seconds after login, half a second after Edit Mode opens, and on `/taintprobe`, it lists every tainted global and every tainted field under Blizzard's party, raid and Edit Mode frames, with the tainting addon's name, into `TaintProbeDB`. It writes into no Blizzard table, and it watches Edit Mode with a secure post-hook.
- Temporary: remove the `TaintProbe` folder and its saved variables once the cause is found.

## 2026-10-04 — ForeverUI Edit Mode taint errors, second patch (Movers.lua)

- Symptom: the `CompactUnitFrame.lua:699 ... 'oldR' (a secret number value, while execution tainted by 'ForeverUI')` error came back at 11:34 (count 2), in a session started after the morning patch below. It appeared when Edit Mode opened from the game menu. So the `Stash()` change was not the real taint source.
- Cause: `Logs/EditMode.log` shows the saved layout anchors Edit Mode system 16 (`DurabilityFrame`) to `ForeverUIGrabDurabilityFrame`. ForeverUI adopts `DurabilityFrame` at every login (`ADOPTED` / `ns.RegrabAll` in `Core/Movers.lua`). Its `Hold()` repositioned the frame with plain `ClearAllPoints`/`SetPoint`, and on an Edit Mode system those are Lua overrides that write into the Edit Mode manager. A `hooksecurefunc(frame, "SetPoint")` re-ran that inside every Edit Mode pass, so the manager's state carried ForeverUI's taint. The party frame refresh later in the same pass then ran tainted.
- Fix: `Hold()` now calls the C originals through `ns.Skin.Plain(frame, "ClearAllPoints")` and `ns.Skin.Plain(frame, "SetPoint", ...)` (`ClearAllPointsBase`/`SetPointBase`). This is the addon's own approach for Edit Mode frames elsewhere. Non-Edit Mode frames fall back to the normal methods. The armour-damage figure still follows its `/fui move` handle.
- The morning `Stash()` change in `Layout.lua` stays in place.
- Backup: `D:\tmp\wow-forever-foreverui-taint-2026-10-04\Movers.lua.orig`.
- `Core/Movers.lua` parses as Lua 5.1 (luaparse). Not yet confirmed in game.

## 2026-10-04 — ForeverUI Edit Mode taint errors (local patch)

- Symptom: two Lua errors in this morning's session, both blaming ForeverUI. `CompactUnitFrame.lua:699: attempt to compare local 'oldR' (a secret number value, while execution tainted by 'ForeverUI')` appeared 9 times between 07:36 and 07:41, on entering or leaving Edit Mode and on ticking its party-frame boxes. `GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'ForeverUI'` came from Edit Mode's `InvokeOnAnyEditModeSystemAnchorChanged` at 07:50 and 07:59, each at a level-up. Sources: `Logs/General.log`, the console history in `WTF/SavedVariables/Blizzard_Console.lua`, and ForeverUI's own error log in its saved variables.
- Cause: ForeverUI 0.4.65 hides Blizzard's party frames by default (a new behaviour in that release). Its `Stash()` in `Modules/Frames/Layout.lua` hid `PartyFrame` and `CompactPartyFrame` and moved them under a hidden parent. That fires Blizzard's OnHide code inside ForeverUI's call, so the Edit Mode systems carried ForeverUI's taint into later Edit Mode passes. ForeverUI's own `Skin.Conceal` already avoids this for managed and protected frames, but the party/raid code did not.
- Fix: `Core/Skin.lua` now exports its existing `Fade` helper as `skin.Fade`. `Stash()` in `Modules/Frames/Layout.lua` now fades the frame to alpha 0 (kept at 0) and turns the mouse off on it and its buttons. It still unregisters their events. It no longer hides or reparents them. The same path covers `CompactRaidFrameContainer` when "Hide Blizzard's raid frames" is on. Blizzard's party frames stay invisible and unclickable, as before.
- Backups: `D:\tmp\wow-forever-foreverui-taint-2026-10-04\Layout.lua.orig` and `Skin.lua.orig`. A ForeverUI update will overwrite this patch and the 2026-10-03 keybind patch; check whether upstream fixed both before reapplying.
- Both edited files parse as Lua 5.1 (luaparse). Not yet confirmed in game: after `/reload`, open and close Edit Mode and watch for the errors.

## 2026-10-03 — ForeverUI action bar keybind labels (local patch)

- Symptom: ForeverUI action buttons showed no key labels.
- Cause: ForeverUI showed a key only when it had been bound with ForeverUI's own keybind mode (`CLICK ForeverUI…Button:LeftButton`). The account's `bindings-cache.wtf` holds standard game bindings such as `ACTIONBUTTON7` and `MULTIACTIONBAR1BUTTON1`. These bindings press the same action slots, but ForeverUI ignored them.
- Fix in `ForeverUI/Modules/ActionBars/ActionBars.lua`: each bar is mapped to the game's binding command for its slots (Main bar `ACTIONBUTTON`, Bar 2-8 `MULTIACTIONBAR1-7BUTTON`). A button now shows its ForeverUI binding, or the game's binding when no ForeverUI binding exists. Keybind mode's tooltip and status text use the same lookup. Backspace in keybind mode now clears both bindings, so a cleared key disappears from the button.
- The original file is backed up at `D:\tmp\wow-forever-foreverui-hotkeys-2026-10-03\ActionBars.lua.orig`. A ForeverUI update will overwrite this patch; reapply it if the upstream release still has the problem.
- Verified the edited file parses as Lua 5.1 (luaparse). In-game display is not yet confirmed.

## 2026-10-03 — ForeverUI replacement

- At the user's request, removed ElvUI (including Libraries and Options), Platynator, LuckyoneUI, TomTom, and WeakAuras (including Archive, ModelPaths, Options, and Templates) from the active `AddOns` directory.
- Moved 15 matching account and character saved-variable files (`.lua` and `.lua.bak`) out of `WTF`. Removed 34 stale entries, including WeakAurasCompanion, from the four character `AddOns.txt` files. Retained add-ons' settings were preserved.
- Automatic command review rejected permanent folder deletion. The removed addon folders and saved variables are inactive at `D:\tmp\wow-forever-ui-replaced-2026-10-03`.
- Installed [ForeverUI 0.4.65](https://www.curseforge.com/wow/addons/foreverui/files/9047043) from the official Forever 1.60.1 archive. The archive also bundles `QuestForever` 0.4.7; both folders declare Interface 16001.
- Marked `ForeverUI` and `QuestForever` enabled in all four character `AddOns.txt` files.
- Updated [readme.md](readme.md) to reflect the active inventory. Installation and file checks are complete; an in-game character login is still needed to confirm behavior.

## 2026-10-02 — Inventory documentation

- Added [readme.md](readme.md) with installed versions, source pages, compatibility notes, and a repeatable update procedure.
- Added this change log to preserve the reason for each replacement and the remaining ElvUI and RangeDisplay checks.

## 2026-10-02 — RangeDisplay trial

- Installed the latest CurseForge RangeDisplay v6.3.6 package (`RangeDisplay` and `RangeDisplay_Options`) at the user's request.
- CurseForge does not list Forever as a supported flavor for this release, although both `.toc` files declare interface 16001. In-game behavior and Lua errors remain unverified.

## 2026-10-02 — LuckyoneUI layout dependency

- Found that LuckyoneUI's full player and target unit frame layout requires ElvUI. LuckyoneUI alone had loaded, but ElvUI was absent, explaining why those frames stayed unchanged.
- Installed official ElvUI v15.26 (`ElvUI`, `ElvUI_Libraries`, `ElvUI_Options`) at the user's request. The official release does not list Forever 1.60.1, and no completed character session has confirmed it works there. The in-game layout command is `/lucky install` if ElvUI loads.
- Rechecked installed add-on metadata: no required add-on dependency was missing. Optional integration names are not required packages. The later 19:37 launch reached the login queue, then exited before character selection; it logged no fresh Lua errors and cannot establish whether ElvUI loads in game.

## 2026-10-02 — Lua error repair

- Inspected `Logs/General.log` and `Logs/FrameXML.log`. WeakAuras Forever 1.3.2 had Lua syntax errors; Plater v656 repeatedly failed in the Forever UI; Details! produced missing-library and unsupported-event errors.
- Backed up affected add-on folders under `D:\tmp\wow-forever-repair-2026-10-02\backup`.
- Replaced WeakAuras Forever 1.3.2 with the working 1.3.0 package, including its five folders. Replaced Plater with Platynator 493 and Details! with Forever Details Meter v1.8.
- After a character session, the fresh `General.log` contained no Lua errors. Saved variables for WeakAuras, Platynator, and ForeverMeter had updated. The old `FrameXML.log` entries predate this repair.

## 2026-10-02 — Initial installation

- Installed the requested LuckyoneUI, Plater, WeakAuras, Details!, DBM, Leatrix Plus, TomTom, RareScanner, and Auctionator packages from CurseForge files selected for WoW: Forever 1.60.1.
- Confirmed `_classic_beta_` as the user's intended game installation.

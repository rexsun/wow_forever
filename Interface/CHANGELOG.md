## [GearInsight 1.0.1 / OverlapSettingsGuard 0.13.0] - 2026-11-12
### Features
- Update GearInsight Forever to 1.0.1.
- Add seven guard rules (layer network, officer auto-accept, guildmate auto-invite, auto-leave, Group module auto-load, city friendly nameplates, item level) and extend the chat-prefix rule to whisper and party chat.
### Design Rationale
- The layer network does not duplicate another addon, but it broadcasts character data and changes groups by default; guarding it keeps the pack's no-surprise network posture. The rules pair with YUI as the chat and group owner.
- Settings are written straight into GearInsight's saved table when the guard loads, because GearInsight sends its first heartbeat on the first frame after loading and publishes no API for most switches.
### Notes & Caveats
- Stopping the Group module auto-load also removes its thank-you popup; GearInsight has no separate switch. Unverified in game and at the three supported resolutions.

## [Addon update / OverlapSettingsGuard 0.12.0] - 2026-11-12
### Features
- Update YUI v357, Auctionator 346, Bagnon 12.1.9, MapUtils 1.6.3, GatherLite 8.4.7 and Lueur 1.7.0.
- Add guard rule `yui.auctionhelper`, which keeps YUI's new Forever Auction Helper panel off while Auctionator loads.
### Design Rationale
- Auctionator already owns shopping lists and searches; a second docked shopping panel at the auction house would duplicate it. The rule uses YUI's own component switch so the panel hides without a reload and saved shopping lists are kept.
- YUI's optional `!YUI_Error` is left out because !BugGrabber already collects errors and `!YUI_Error` would take over BugGrabber's chat notice.
- GearInsight 1.0.1 stays held at 0.7.4: its layer network, city nameplate toggling, whisper/party prefixes and self-loading Group module are still on by default and outside the guard.
### Notes & Caveats
- MapUtils' new Piers button can switch its pier pins back on until the next load. YUI's installer now imports Edit Mode layout "YUI v4". Unverified in game and at the three supported resolutions.

## [Addon update 2026-11-10] - 2026-11-10
### Features
- Update YUI v355, Auctionator 344, Details 15410.172, EllesmereUI 9.8.4, GatherLite 8.4.5, Lueur 1.6.1 and MapUtils 1.5.6.
- Add a local MapUtils patch so its world-map fader follows only its own fade setting.
### Design Rationale
- GearInsight 0.9.7 is held at 0.7.4: its new default-on layer network auto-invites, auto-accepts and auto-leaves groups and broadcasts on public channels, and its city nameplate and whisper/party prefix features bypass the guard. Guard rules should exist before it is adopted.
- A one-line patch keeps YUI as the world-map fade owner, matching the existing `mu.worldmapfade` decision; handing fade to MapUtils instead would have changed the look and the guard ownership split.
### Notes & Caveats
- EUI 9.8.4 needs Lueur 1.6.x for its interact-icon handling. EUI re-keys per-character data by GUID at each character's first login. Unverified in game and at the three supported resolutions.

## [OverlapSettingsGuard 0.11.1] - 2026-11-09
### Features
- Unexplored areas of the world map are visible again. MapUtils now owns the reveal and YUI's reveal is kept off while MapUtils loads.
### Design Rationale
- One Map hides the exploration layer YUI draws on and only draws unexplored areas when MapUtils' reveal is on, so MapUtils is the one owner that works with One Map on or off. Turning One Map off instead would have kept YUI's look but removed stepless zoom.
### Notes & Caveats
- The reveal now uses MapUtils' Blue tint rather than YUI's color. Removing MapUtils later leaves YUI's reveal saved as off, so turn it back on in YUI. Unverified in game and at the three supported resolutions.

## [GatherLite 8.4.3 / Lueur 1.5.0 / OverlapSettingsGuard 0.11.0] - 2026-11-09
### Features
- Install GatherLite for known gathering locations, fish areas and zone routes, and Lueur for an in-world glow on the object you would interact with.
- Add two guard rules that keep Lueur's minimap herb and ore markers off while MapUtils loads.
### Design Rationale
- MapUtils stays the owner of markers for tracked nodes because Lueur draws the same nodes and each of its scans briefly hides the minimap. GatherLite's markers show possible spawn locations, a different kind of information, so they stay on.
- Lueur publishes no API, so the guard writes its saved table before login, when no reload is needed.
### Notes & Caveats
- GatherLite broadcasts its version every 10 seconds and loads about 12 MB of route data at login. Lueur keeps soft-target interact on until logout and shares a CVar with EUI Fishing Key. Unverified in game and at the three supported resolutions.

## [MapUtils 1.4.25 / OverlapSettingsGuard 0.10.0] - 2026-11-08
### Features
- Install MapUtils for undiscovered flight points, zone crossings, fishing-skill and zone-level labels, and dungeon maps with boss pins.
- Add seven guard rules that split world map ownership between YUI and MapUtils and keep Forever Essentials Zone Levels off.
### Design Rationale
- YUI keeps the map window and static transport markers it already manages. MapUtils owns flight points because YUI shows an unconfirmed point as a normal pin.
- MapUtils publishes no API, so the guard writes its saved table before login, when no reload is needed.
### Notes & Caveats
- MapUtils' One Map zoom, guild position sharing and hidden timetable channel are on by default and left on. Boss pins depend on the client lacking native art for those instances. Unverified in game and at the three supported resolutions.

## [Addon update / OverlapSettingsGuard 0.9.1] - 2026-11-07
### Features
- Update YUI v354, GearInsight Forever 0.7.4, EllesmereUI 9.8, Details 15402.172, Auctionator 342 and !BugGrabber v12.1.1.
### Design Rationale
- Keep a single owner for level-up announcement filtering (GearInsight) even though it is now off by default, rather than re-enabling YUI's broader keyword filter.
### Notes & Caveats
- Other players' level-up announcements show again until `/gi 屏蔽升级 开`. GearInsight now auto-posts every fifth own level-up. EUI 9.8 applies the LongZhu damage font from PLAYER_LOGIN on zhTW. All unverified in game.

## [LootRollMover 8.3] - 2026-11-06
### Features
- Replace the local LootRollAnchor addon with LootRollMover 8.3 from CurseForge. Its account-wide default centres the roll window 5 UI units above YUI's stance and totem bars on top of action bar 3.
### Design Rationale
- A maintained community addon with a fixed, user-adjustable anchor replaces local placement code that depended on EllesmereUI's frame placer and YUI internals.
### Notes & Caveats
- The anchor is a fixed offset computed from the shared YUI profile; it does not follow later bar-layout changes. The alert-toast mover is turned off. YUI's centred HUD groups may overlap a shown roll window; accepted as rolls are short-lived. Unverified in-game at the three supported resolutions.

## [LootRollAnchor 0.1.0] - 2026-11-05
### Features
- Add the local addon LootRollAnchor, which keeps Blizzard's group loot roll stack centred and above YUI's visible action bars and HUD groups.
### Design Rationale
- Blizzard derives the stack's height on this client from native bottom bars that YUI hides or keeps invisible, and YUI's own fix for this loads only on retail. A separate addon keeps the fix out of upstream files and survives YUI updates.
- Position through EllesmereUI's frame placer rather than direct SetPoint calls: it reapplies after each Blizzard layout, before drawing, and hands Blizzard's anchor back when it is removed.
### Notes & Caveats
- Requires EllesmereUI. Shares the `cdm` placer owner with the absent EllesmereUICooldownManager. Unverified in-game at the three supported resolutions.

## [Addon update / OverlapSettingsGuard 0.8.3] - 2026-11-05
### Features
- Update YUI v352, GearInsight Forever 0.5.11, EllesmereUI 9.7.6, Details 15400.172, Waypoint UI 1.7.5 and Bagnon 12.1.8.
- Add guard rules `yui.chatkeywordfilter` and `gi.guildchatlevel`, which keep the new default-on YChat keyword filter and GearInsight's guild-chat level prefix off while both addons load.
### Design Rationale
- Both are chat-message filters added by default in this round. YUI owns chat, and GearInsight's existing level-up filter already covers the announcements YChat's keywords target, so neither new filter is needed. The YChat rule turns the filter off but keeps its keyword list, so turning it back on later restores the list.
- Use each addon's own setter (`SetMessageFilterEnabled`, `GuildChatLevel.SetEnabled`) for the live state, so YChat refreshes its filter interests and no reload is needed.
### Notes & Caveats
- Four local Details patches are now upstream; the patch tool treats them as already applied. Replaced folders and live WTF are in `addon-backups/addon-upgrade-20261105`. In-game loading, `/osg` and all three resolutions are not yet verified.

## [Addon update / OverlapSettingsGuard 0.8.1] - 2026-11-04
### Features
- Update YUI v351, GearInsight Forever 0.5.9, EllesmereUI 9.7.3, Skinner beta12.70688.1, Details 15339.172 and Waypoint UI 1.7.4. !BugGrabber stays at v12.1.0.
- Extend the guard to GearInsight's new editing methods and load-on-demand Group module, and to YUI's resource manager contexts.
- Add `tools/apply_addon_patches.py` for local patches that recur on every update.
### Design Rationale
- Lock editing methods individually so one upstream removal cannot cancel the rest, and fail a test on unclassified methods so new ones are reviewed at update time. GearInsight and YUI both ship several releases per week.
- Exclude Skinner's EllesmereUI skin by patch because upstream offers no setting and it would disable the Blizzard skins the pack keeps Skinner for.
- Keep YUI's portable-font paths to preserve current behavior; whether upstream's bundled paths now load cleanly is untested.
### Notes & Caveats
- Saved settings migrate on first login. Replaced folders and live WTF are in `addon-backups/addon-upgrade-20261104`. In-game loading, `/osg` and all three resolutions are not yet verified.

## [Release migration] - 2026-10-23
### Features
- Migrate the beta working project, Git history, live settings, private mappings and complete fonts to the installed `_forever_` release build 1.60.1.70532 / Interface 16001.
- Move settings capture to the release installation and preserve historical backups outside beta.
### Design Rationale
- Use the existing adoption utility to preserve UI configuration and rollback behavior. Keep addon versions and overlap ownership unchanged because the installed beta and release clients share the same build and interface version.
### Notes & Caveats
- Existing beta realm/character identities are retained. New release identities may require selecting shared profiles and updating the private UI source configuration. In-game loading and all three display resolutions remain to be checked.

## [Per-login source UI sync / CharacterUIBaseline 0.2.0] - 2026-10-17
### Features
- Synchronize targets from a configurable source account/character on every login/reload; exclude the source and publish its latest UI at logout.
- Refresh generated fallback settings through the existing post-exit watcher. Support changed source identities, native layout import, safe path validation, dry runs and rollback.
### Design Rationale
- Game addons cannot read another character/account's WTF directly. Use account SavedVariables for source-to-target character switches and an offline bridge for persisted/cross-account updates.
- Apply only whitelisted UI values, leaving specialization/talent choices and profile assignments intact. Use a session gate rather than a permanent revision skip.
### Notes & Caveats
- Cross-account source updates require the post-exit refresh and another client start. Source changes must be published by logout or `/uib capture`; another running client's unsaved settings are unavailable.
- Runtime scope remains native layout, display CVars, chat font/primary geometry and EUI party/raid positions. Other addon appearance remains managed by existing shared profiles. Live timing and visuals need in-game verification.

## [Shared character UI / CharacterUIBaseline 0.1.0] - 2026-10-17
### Features
- Synchronize existing characters' native UI layout, window placement, chat presentation and display-only preferences from the reference character. Use its existing Details profile account-wide.
- Add a first-login initializer for supported captured defaults, with combat/editing deferral, bounded retries and explicit `/uib apply`.
### Design Rationale
- EUI/YUI settings already share account profiles. Preserve that ownership, select the native layout by name and refresh EUI frames afterward instead of copying mixed character databases or patching upstream addons.
- Mark successful initialization per character so later deliberate customization survives subsequent logins.
### Notes & Caveats
- Preserve macros, bindings, subscriptions, progression/tracking and combat history. The initializer uses a captured template rather than following future filesystem changes to the reference character.
- Adoption carries the addon and live markers. API-stub tests cover onboarding and the three target resolutions; actual first-login behavior and visual placement need in-game verification.

## [Skinner beta12.70425.2 / OverlapSettingsGuard 0.8.0] - 2026-10-17
### Features
- Install the author's packaged Skinner prerelease with Interface 16001/Forever support and enable it in existing character addon lists.
- Add twelve conditional Skinner policies covering all competing frame/castbar/nameplate, action-bar, map/minimap, chat, tooltip and Details skins, bringing the guard to 23 rules.
### Design Rationale
- Keep EUI/YUI/Details appearance ownership and let Skinner style complementary Blizzard windows and Auctionator. Use a local adapter for active/stored/namespace AceDB profiles rather than patching upstream source.
- Enforce before Skinner's login module enable and delayed skin passes, then use profile callbacks and periodic checks. Request reload when texture/hook changes have already been applied.
### Notes & Caveats
- All 377 Skinner files match the release archive. Thirty-nine guard tests include its installed AceDB and default/schema code. Live WTF changes are limited to four addon-list enablement entries; existing saved settings and three-resolution layouts/scales are preserved.
- Adoption already copies the new addon, guard and future live SkinnerDB settings; its three-resolution and rollback tests pass. Skinner is not yet part of anonymous settings capture. Backups are outside Interface; in-game loading and rendering at 1080p/1440p/4K remain unverified.

## [WTF settings snapshots 1.2] - 2026-10-15
### Features
- Capture reusable account-level addon configuration while excluding character records, assignments, progression, social history and runtime caches. Regenerate current snapshots using the filter.
- Preserve excluded current live data during restore, including when restoring older unfiltered snapshots. Skip legacy character-file snapshots.
### Design Rationale
- Anonymization alone does not make gameplay records useful configuration. Filter known data boundaries before aliasing; use an explicit preference allowlist for GearInsight's mixed settings/character database.
- Apply the same policy during restore so a settings rollback cannot roll back or erase character history. Preserve migration markers to avoid rerunning migrations against restored layouts.
### Notes & Caveats
- Existing Git history and ignored private aliases are not rewritten. Named shared profiles and class/spec display preferences remain included; addon schema updates require filter review.
- Private adoption still transfers full live WTF. Display resolution/scale handling and installed addon sources/versions are unchanged.

## [Details combat analysis 15330.172] - 2026-10-15
### Features
- Install Details.20261014.15330.172 and its bundled Storage, Compare2, Encounter Breakdown, Raid Check and Tiny Threat modules for Interface 16001.
### Design Rationale
- Use Details as the sole combat meter. YUI's Forever damage-meter module is not loaded and the EUI damage-meter module is absent. Exclude optional Streamer/Vanguard displays to retain existing cast/group-frame ownership without adding unnecessary guard rules.
### Notes & Caveats
- Existing layouts, fonts and saved addon settings are preserved. Adoption already copies the selected folders and live WTF; Details combat databases are not added to anonymous snapshots. Live loading and window placement at 1080p/1440p/4K need in-game verification.

## [GearInsight migration / OverlapSettingsGuard 0.7.0] - 2026-10-15
### Features
- Install GearInsight Forever 0.4.31 and remove DungeonsForever, TalentsForeverBook and RestedXP with their active settings and obsolete guard integration.
- Add five GearInsight ownership rules for friendly nameplates, the combined combat/resource HUD, floating leveling panel and action-bar/keybinding edits.
- Capture GearInsight anonymous settings and seed overlapping displays off for existing accounts.
### Design Rationale
- Retain YUI for bars, bindings and interface helpers and EUI for frames/resources/nameplates. Keep GearInsight's talents, gear, macros, planning and distinct rotation recommendations.
- Use the local guard for runtime enforcement and conditional editing locks because upstream provides no bar-editor disable setting. Keep the upstream archive unchanged and preserve unrelated saved state.
### Notes & Caveats
- Retired active files and a full recovery copy are outside Interface in addon-backups. Saved plans/progress/wishlists are not imported into GearInsight. Historical changes and private alias mappings remain available.
- Thirty-three guard tests, 36 settings tests, 18 fresh profiles, fonts, three-resolution adoption and 19 watcher checks pass. The adoption script carries the new pack unchanged. Live loading, Chinese terminology and rendering at the three resolutions still need in-game verification.

## [Forever addon refresh / OverlapSettingsGuard 0.6.0] - 2026-10-14
### Features
- Upgrade YUI to v341, Auctionator to 341, DungeonsForever to 1.8.6, TalentsForeverBook to 0.38.2 beta and the six installed EUI modules to 9.5.5.
- Keep YUI player health/cast resources, dedicated cast groups and native castbar suppression off while EUI Unit Frames loads.
### Design Rationale
- Retain EUI ownership of individual, party/raid and nameplate frames because YUI v341 does not replace party/raid frames and its full unit-frame product is not loaded on Forever.
- Preserve saved layouts and portable fonts; enforce overlap through the guard rather than changing upstream HUD rendering. Talents Forever now includes the regular Cinzel selection upstream.
### Notes & Caveats
- Backups and the archive hash manifest are outside Interface under addon-backups. All live WTF files remain unchanged. Only the two existing YUI font-reference patches differ from the selected upstream releases.
- Thirty-two guard tests include the installed catalog; font, 18 fresh-profile, three-resolution adoption, settings and watcher checks pass. Live rendering and client API behavior still require an in-game session. The existing adoption script carries the new files without code changes.

## [WTF settings restore 1.1] - 2026-10-13
### Features
- Add Restore and Restore -DryRun using the current anonymous snapshot folder, with mapped existing-account destinations, selective CVar merging, private backups and rollback.
- Move private aliases into ignored Interface/.env and add .env.example; load an optional private state-directory variable from the file.
### Design Rationale
- Treat the selected bundle as the recovery source without changing Git. Pause/resume the scheduled watcher and skip its startup export to preserve that source.
- Retain the full reversible text/number map as flat .env variables; read bulk aliases directly instead of enlarging the Windows process environment. Parse and serialize Lua as data.
### Notes & Caveats
- Restore replaces represented addon saved files completely, including profiles; files absent from the bundle and unrepresented Config.wtf fields remain intact. Account/character folders must already exist.
- Preserve the complete .env privately. Existing aliases are migrated without changing snapshots; the former map.json remains only a private backup. Restore has been validated in fixtures and against the installed bundle with DryRun; live restoration is not run during implementation.

## [WTF exit snapshots 1.0] - 2026-10-13
### Features
- Add a current-user sign-in watcher and manual export/review commands for anonymous settings snapshots after WoW exits.
- Keep staging, commits and pushes manual; preserve live WTF and the Git index.
### Design Rationale
- Parse approved saved-variable data without executing Lua and alias every text and numeric value. Keep the reverse map outside the repository and decode diffs only for local review.
- Wait for the installation's processes to exit and file writes to settle; publish snapshots as a unit with locking and rollback.
### Notes & Caveats
- Coverage is restricted to eight approved addon saved-file names and an explicit CVar allowlist. Snapshots are anonymous JSON review artifacts; adoption continues copying live WTF privately.
- Preserve the private alias map for consistent future exports. Fixture tests and a successful current-WTF export supplement watcher lifecycle checks; real game shutdown timing remains a live check.

## [OverlapSettingsGuard 0.5.2] - 2026-10-13
### Features
- Add startup contrast 85%, brightness 55% and gamma 1.5 to match the requested display settings.
### Design Rationale
- Append separate SetCVar calls to the established ordered startup sequence, preserving the world-entry delay and once-per-login/reload behavior.
### Notes & Caveats
- EllesmereUI Optimize/Restore can change contrast later. Twenty-six Lua 5.1 stub tests cover all ten startup values and their order; live rendering remains unverified. Values are shared across all three resolutions.

## [OverlapSettingsGuard 0.5.1] - 2026-10-13
### Features
- Apply six additional startup CVars after the loot-effect setting: camera zoom 4, nameplate distance 41, nearest-target radius 50, glow 0, volume fog 0 and sharpening 1.
### Design Rationale
- Preserve separate SetCVar calls in the requested order and the existing two-second world-entry delay, once per login or reload.
### Notes & Caveats
- Other addon options can overwrite these preferences later. Lua 5.1 stub tests cover call order, values and lifecycle; live client acceptance/effects remain unverified. All three resolutions use the same values; adoption already includes the files.

## [Source-to-destination adoption] - 2026-10-12
### Features
- Use the current game-root directory as adoption's source and the positional `Destination` argument as its target, including writable UNC shares.
- Preserve source files, destination backup/rollback, optional font merging and resolution fitting.
### Design Rationale
- Run the utility where the maintained addon pack lives and send it to another installation. Require the current directory to match the script's source root to prevent accidental direction errors.
### Notes & Caveats
- This reverses the former argument meaning; `-Source` becomes `-Destination`. Run from the source root and close both clients. Local tests cover both argument forms and all three resolutions; actual UNC access and the remote client's process state remain unverified.

## [Game-root font adoption] - 2026-10-12
### Features
- Use copies of all seven YUI custom fonts in the game-root Fonts directory and select LongZhu for damage text.
- Include optional source Fonts in adoption, preserving destination-only files with backup and rollback.
### Design Rationale
- Keep custom faces intact through direct game-root paths. Stage a merged Fonts directory before replacing anything so a failed adoption can restore the original files.
### Notes & Caveats
- Sources without Fonts preserve destination Fonts. Upstream YUI updates can overwrite the font registration patch. Game restart and live rendering checks remain required.

## [OverlapSettingsGuard 0.5.0] - 2026-10-11
### Features
- Apply `outlineModeShowLootEffectWhenDisabled = 1` after initial world entry on every login and UI reload.
### Design Rationale
- SetCVar gives the console command's effect for every selected addon profile. Delay startup until two seconds after world entry so normal initialization runs first; write after the guard's initial checks.
### Notes & Caveats
- Twenty-six Lua 5.1 tests pass. The startup write is once per session; arbitrary later addon initialization or profile changes can override it. Live loot rendering remains unverified.

## [OverlapSettingsGuard 0.4.3] - 2026-10-11
### Features
- Remove obsolete policies, adapters, dependencies and tests for addons outside the installed pack; retain ten current overlap rules and chat-only reporting.
### Design Rationale
- The guard should describe and maintain the installed pack. Removing unused integrations keeps policy ownership and tests aligned with the actual addon inventory.
### Notes & Caveats
- Twenty-four Lua 5.1 tests pass, including installed-pack dependency validation. Removed integrations require implementation again if their addons return. Live game behavior remains unverified.

## [Portable profiles / resolution-aware adoption] - 2026-10-11
### Features
- Configure RestedXP's supported new-character default and retire conflicting standalone folders; verify shared EUI/YUI profiles.
- Add optional destination Resolution to the adoption utility, fitting EUI options at 1080p, 1440p and 4K while preserving gameplay layout.
### Design Rationale
- Fresh characters need a complete RestedXP default template. A frozen options scale of 1.5 exceeds 1080p; resize only this window during staging, leaving the working gameplay layout intact.
### Notes & Caveats
- Eighteen new-character profiles, 34 guard tests and adoption/rollback tests pass. User confirmed frame/arrow behavior locally; visual validation on other displays remains pending. WTF is not versioned. One separate DungeonsForever/Blizzard PTR SubmitBug() blocked-action report remains unresolved.
## [EUI shared frames / OverlapSettingsGuard 0.4.1] - 2026-10-11
### Features
- Replace the mutually incompatible standalone combination with shared EUI 9.4 frame modules and migrate preferences; retain the old standalone folders disabled.
- Retarget overlap enforcement to shared modules/database, including spec overrides. Reset RestedXP arrow visibility and placement without changing guide progress.
### Design Rationale
- Upstream standalone conflict guards prevent multiple standalone modules from running. The modular suite supports the requested combination without source patches or unrelated feature modules.
### Notes & Caveats
- Thirty-four guard tests pass; 704 upstream files match the release archive. RestedXP raid hiding was enabled, but its precise runtime failure is unconfirmed. Live frame/arrow rendering and three-resolution validation remain pending.
## [OverlapSettingsGuard 0.4.0] - 2026-10-11
### Features
- Restore continuous overlap enforcement for YUI/EllesmereUI frame resources and nameplates, RestedXP automation, and TalentsForeverBook talent ownership.
### Design Rationale
- Saved settings alone cannot preserve ownership after user changes or profile resets. Reuse the combat-safe guard with adapters for the current upstream APIs.
### Notes & Caveats
- Thirty-three Lua 5.1 tests pass. Stored HUD configurations, druid forms and nameplate presets are covered, with blocked-API reporting and refresh retries. Swing timers and optional layouts remain adjustable. Upstream addon source is unchanged; live rendering remains pending.

## [YUI / EllesmereUI standalone frames] - 2026-10-11
### Features
- Install EllesmereUI standalone Unit Frames, Raid Frames and Nameplates 9.4 alongside YUI and the specialist addons.
### Design Rationale
- Give individual frames, group frames and nameplates to supported Forever packages without modifying YUI's dormant unit-frame loader.
### Notes & Caveats
- Disable competing YUI nameplate options and mana/rage/energy/combo-point HUD bars through saved settings. Retain swing timers and cooldown tracking. No source patches or continuous overlap enforcement; live loading and three-resolution validation remain pending.

## [YUI trial / specialist addons restored] - 2026-10-11
### Features
- Restore Auctionator 340, DungeonsForever 1.8.0, TalentsForeverBook 0.38.1 and !BugGrabber v12.1.0 alongside YUI and RXPGuides.
### Design Rationale
- Retain specialist auction, dungeon, talent and Lua-error tools while evaluating the upstream YUI interface.
### Notes & Caveats
- All four declare Interface 16001 and match their archives. TalentsForeverBook is a beta. Overlaps and YUI frame limitations are documented; no local addon code or settings changes were applied. Live verification remains pending.

## [Clean YUI trial / RestedXP 4.11.23] - 2026-10-11
### Features
- Replace all addon folders with YUI v338 and RXPGuides v4.11.23, and delete WTF for fresh defaults.
### Design Rationale
- Evaluate the two upstream addons without prior profiles, local patches or enforced overlap settings. The user has already backed up.
### Notes & Caveats
- Both packages declare Interface 16001 and Forever loading. Potential overlapping features remain user-adjustable. Top-level game Fonts are retained. In-game behavior and 1080p, 1440p and 4K layouts require validation. No new backup was created.

## [Kallye group frames / OverlapSettingsGuard 0.3.1] - 2026-10-10
### Features
- Install Kallye Raid Frames 12.1.003c with group health highlights, range fading, auras and markers, plus one-time raid-style party setup.
- Guard Kallye nameplate styling for Plater and remove obsolete integration code and policies for the uninstalled ForeverUI bundle.
### Design Rationale
- Enhance Blizzard group frames while retaining one owner for nameplates. Preserve existing Edit Mode positions and use the backup branch for rollback instead of retaining inactive integration code.
### Notes & Caveats
- Interface 16001 is declared. Settings are enabled for all stored characters and WTF is backed up separately. The local party setup patch can be overwritten by upstream updates. Twenty guard tests and four setup tests pass; in-game rendering and API verification remain pending.

## [Combat UI migration / OverlapSettingsGuard 0.3.0] - 2026-10-10
### Features
- Replace ForeverUI and bundled QuestForever with ClassUIEnhanced 3.1.0 and Plater v658 for WoW Forever 1.60.1.
- Enable Leatrix minimap/chat enhancements and retain Blizzard action bars, bags and full unit/group frames.
- Guard overlapping Plater resources/personal bars, Leatrix combat plates and RestedXP nameplate distance, including Plater profiles and combat deferral.
### Design Rationale
- Give each UI area one owner and avoid the broad hooks and maintenance of the previous full UI replacement. Preserve the original bundle on the ForeverUI branch and save WTF separately because it is excluded from Git.
### Notes & Caveats
- Packages declare Interface 16001; Plater uses its Camelot TOC. Existing Plater settings are retained. ClassUIEnhanced's first-login prompt handles duplicate Blizzard cooldown viewers. Full unit frames remain Blizzard's; CUE provides player health/resources and cast bars. In-game confirmation is pending.

## [Addon adoption utility 1.0] - 2026-10-10
### Features
- Adopt Interface and WTF from a shared source game root using one PowerShell argument, with staged copies, dated backups and rollback.
### Design Rationale
- Replace entire folders to retain source patches and settings while avoiding obsolete destination addons. Preserve originals before replacement and copy settings unchanged to retain the existing layout.
### Notes & Caveats
- Close WoW on both machines; the script verifies local processes and asks for source confirmation. Fonts are excluded. Share access must already be available. Tested with Windows PowerShell 5.1 and real robocopy in temporary installations; a remote share transfer remains untested.

## [OverlapSettingsGuard 0.2.1] - 2026-10-09
### Features
- Leatrix Plus handles broad quest acceptance, turn-in and gossip; RestedXP quest and reward automation is locked off.
### Design Rationale
- Guide-dependent automation left quests outside the active route manual. Retain RestedXP navigation while giving quest interactions to Leatrix.
### Notes & Caveats
- Multi-choice rewards require manual selection. Leatrix settings remain user-adjustable. RestedXP flight-path, binding and trainer automation are unchanged. Verified with 24 guard tests; in-game confirmation is pending.

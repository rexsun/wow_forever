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

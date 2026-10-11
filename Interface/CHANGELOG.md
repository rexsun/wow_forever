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


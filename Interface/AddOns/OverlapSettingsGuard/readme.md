# OverlapSettingsGuard

Version 0.3.1, for Interface 16001. This local addon keeps duplicate features switched off while all addons named in a rule are loaded. `/osg` lists every rule and its current status.

## Policy

| Rule | Setting kept off | Required addons | Owner and reason |
| --- | --- | --- | --- |
| `kallye.nameplates` | Kallye `ActiveNameplatesColor` | Kallye Raid Frames, Plater | Plater owns nameplate colours, names, textures and icons. Kallye enhances Blizzard group frames. |
| `rxp.autoquests` | RestedXP `enableQuestAutomation` | RestedXP, Leatrix Plus | Leatrix accepts and turns in quests outside the guide as well. |
| `rxp.autogossip` | RestedXP `enableGossipAutomation` | RestedXP, Leatrix Plus | Leatrix owns quest gossip. |
| `rxp.questrewards` | RestedXP `enableQuestRewardAutomation` | RestedXP, Leatrix Plus | Leatrix owns turn-ins; guide-selected rewards must not compete. |
| `rxp.questchoices` | RestedXP `enableQuestChoiceAutomation` | RestedXP, Leatrix Plus | Leatrix owns turn-ins; calculated rewards must not compete. |
| `leatrix.flighttimes` | Leatrix `ShowFlightTimes` | Leatrix Plus, RestedXP | RestedXP owns flight timings and progress. |
| `rxp.selljunk` | RestedXP `autoSellJunk` | RestedXP, Leatrix Plus | Leatrix owns automatic junk selling. |
| `rxp.talentguides` | RestedXP `enableTalentGuides` | RestedXP, Talents Forever | Talents Forever owns talent planning. |
| `rxp.nameplatedistance` | RestedXP `enableMaxNameplateDistance` | RestedXP, Plater | Plater owns nameplate distance; RestedXP otherwise resets it at loading screens. |
| `leatrix.combatplates` | Leatrix `CombatPlates` | Leatrix Plus, Plater | Plater owns enemy nameplate visibility. |
| `plater.resources` | Plater resource bars | Plater, ClassUIEnhanced | ClassUIEnhanced owns class resources. |
| `plater.personalbar` | Plater personal health/mana bars | Plater, ClassUIEnhanced | ClassUIEnhanced owns player health/power tracking. |

Blizzard owns action bars, bags and full unit frames. Kallye enhances Blizzard compact group frames. Leatrix minimap/chat settings remain adjustable. ClassUIEnhanced's own prompt hides duplicate Blizzard cooldown viewers without disabling their data source.

## Enforcement and scope

Checks run after login, on supported option hooks and every two seconds as a fallback. Changes wait until combat ends. A popup explains reverted settings, with a reload button when needed; repeated popups for a rule are limited to once per ten seconds. Failed enforcement is reported in chat rather than silently changing an unidentified option.

- Leatrix's live settings are private, so its adapter locates and clicks its option checkboxes. Page/anchor coordinates and reload markers are verified against 1.60.11. Only active policy options receive a locked tooltip; unfamiliar checkbox layouts report a blocked rule. Saved values are written by Leatrix on logout.
- RestedXP enforcement covers the live profile, stored profiles and account/character templates. Missing stored values inherit the account template or addon defaults. Changes in shared profiles also affect other characters using those profiles.
- Plater enforcement covers all stored profiles and the live personal-nameplate CVar. Its configuration refresh hook catches profile changes.
- Kallye enforcement changes only `ActiveNameplatesColor` in its account settings. Its option refresh hook catches re-enabling; party/raid health, auras and raid markers remain available. Kallye's nameplate hooks read this flag live.

## Maintenance and verification

Add overlapping settings to `Policy.lua` and this table. Extend the relevant adapter and tests when needed; new adapters must be loaded by the TOC and test harness. Verify against installed source when updating addon versions.

```powershell
uv run --no-project --with lupa python tools/overlapsettingsguard-tests/run_tests.py
```

The 20 tests use Lua 5.1 and game/addon stubs. They cover policy validation, stored profiles and templates, option hooks, combat deferral, inactive dependencies, Leatrix checkbox identification, popup suppression and current UI ownership. They do not verify live rendering or game API behavior.

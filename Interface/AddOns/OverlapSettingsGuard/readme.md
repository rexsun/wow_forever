# OverlapSettingsGuard

Version 0.4.1, for Interface 16001. This local addon keeps duplicate features switched off while all addons named in a rule are loaded. `/osg` lists every rule and its current status. It does not enable disabled addons or lock optional appearance choices on.

## Policy

| Rule | Setting kept off | Required addons | Owner and reason |
| --- | --- | --- | --- |
| `yui.nameplateoutline` | YUI `UtilityTools_Config.nameplateOutline` | YUI, EllesmereUINameplates | EllesmereUI owns nameplate fonts and styling. |
| `yui.friendlynameplates` | YUI `UtilityTools_Config.syncFriendlyNameplates` | YUI, EllesmereUINameplates | EllesmereUI owns friendly nameplate visibility and CVars. |
| `yui.resources` | YHUD mana, rage, energy and combo-point selections, including druid forms | YUI, EllesmereUIUnitFrames | EllesmereUI owns player power/class resources. YUI swing timers and cooldown tracking stay available. |
| `eui.nameplatepower` | EllesmereUI nameplate `showClassPower` | EllesmereUINameplates, EllesmereUIUnitFrames | Unit frames own class resources; no second display on the target nameplate. |
| `rxp.yui.autoquests` | RestedXP `enableQuestAutomation` | RestedXP, YUI | YUI owns quest acceptance and turn-ins. |
| `rxp.yui.autogossip` | RestedXP `enableGossipAutomation` | RestedXP, YUI | YUI owns quest gossip. |
| `rxp.yui.questrewards` | RestedXP `enableQuestRewardAutomation` | RestedXP, YUI | YUI owns turn-ins; RestedXP guide reward selection must not compete. |
| `rxp.yui.questchoices` | RestedXP `enableQuestChoiceAutomation` | RestedXP, YUI | YUI owns turn-ins; calculated RestedXP choices must not compete. |
| `rxp.yui.selljunk` | RestedXP `autoSellJunk` | RestedXP, YUI | YUI owns junk selling. |
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

In the current configuration EllesmereUI owns individual/group frames and nameplates; YUI owns the remaining interface features. The following ownership applies only when legacy owners are installed: Kallye enhances Blizzard compact group frames. Leatrix minimap/chat settings remain adjustable. ClassUIEnhanced's own prompt hides duplicate Blizzard cooldown viewers without disabling their data source.

## Enforcement and scope

Checks run after login, on supported option hooks and every two seconds as a fallback. Changes wait until combat ends. A popup explains reverted settings, with a reload button when needed; repeated popups for a rule are limited to once per ten seconds. Failed enforcement is reported in chat rather than silently changing an unidentified option.

The current installation activates the nine YUI/EllesmereUI rules plus `rxp.talentguides`. Legacy rules for Leatrix, Plater, Kallye and ClassUIEnhanced remain inactive because those addons are absent. Ownership is conditional on addons being loaded, rather than the owner's optional feature currently being enabled; use the owner's settings when choosing whether to automate a task.

- Leatrix's live settings are private, so its adapter locates and clicks its option checkboxes. Page/anchor coordinates and reload markers are verified against 1.60.11. Only active policy options receive a locked tooltip; unfamiliar checkbox layouts report a blocked rule. Saved values are written by Leatrix on logout.
- RestedXP enforcement covers the live profile, stored profiles and account/character templates. Missing stored values inherit the account template or addon defaults. Changes in shared profiles also affect other characters using those profiles.
- Plater enforcement covers all stored profiles and the live personal-nameplate CVar. Its configuration refresh hook catches profile changes.
- Kallye enforcement changes only `ActiveNameplatesColor` in its account settings. Its option refresh hook catches re-enabling; party/raid health, auras and raid markers remain available. Kallye's nameplate hooks read this flag live.
- YUI enforcement covers the active suite profile, stored profiles and stored HUD configuration sets. Resource selections use v338's Forever specialization catalog, including druid forms; swing timers are untouched. Nameplate runtime Disable methods restore/stop their behavior, and YHUD's configuration-change API rebuilds its active display. Missing APIs block enforcement before storage changes. Failed HUD refreshes remain pending for retry.
- EllesmereUI enforcement covers nameplate profiles, spec presets and encoded spec override keys in EllesmereUIDB, using `_ENP_RefreshAllSettings` for the live display. Missing refresh APIs report a blocked rule; failed refreshes are retried. This adapter was verified against shared-suite 9.4.

Addon enablement is recorded separately in each character's AddOns.txt. Player castbar and eight raid-group visibility preferences are saved in the EllesmereUI core profiles; they remain user-adjustable. Layout positions, general HUD content, route/map-pin displays and optional overlapping statistics are not continuously forced by the guard.

## Maintenance and verification

Add overlapping settings to `Policy.lua` and this table. Extend the relevant adapter and tests when needed; new adapters must be loaded by the TOC and test harness. Verify against installed source when updating addon versions.

```powershell
uv run --no-project --with lupa python tools/overlapsettingsguard-tests/run_tests.py
```

The 34 tests use Lua 5.1 and game/addon stubs. They cover policy validation, stored profiles/templates/HUD sets, form overrides, option hooks, combat deferral, profile resets, inactive dependencies, missing APIs, refresh failure/retry, swing preservation, legacy ownership and current YUI/EllesmereUI ownership. They do not verify live rendering or game API behavior.

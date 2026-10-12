# OverlapSettingsGuard

Version 0.4.3, for Interface 16001. This local addon keeps duplicate features switched off while all addons named in a rule are loaded. `/osg` lists every rule and its current status. It does not enable disabled addons or lock optional appearance choices on.

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
| `rxp.talentguides` | RestedXP `enableTalentGuides` | RestedXP, Talents Forever | Talents Forever owns talent planning. |

EllesmereUI owns individual/group frames and nameplates; YUI owns the remaining interface features.

## Enforcement and scope

Checks run after login, on supported option hooks and every two seconds as a fallback. Changes wait until combat ends. Chat messages explain reverted settings and name any other affected profiles. When a reload is needed, chat asks you to type `/reload` when ready. The guard never opens a popup. Failed enforcement is also reported in chat.

The policy contains ten rules for the installed pack: nine YUI/EllesmereUI rules plus `rxp.talentguides`. Ownership is conditional on addons being loaded, rather than the owner's optional feature currently being enabled; use the owner's settings when choosing whether to automate a task.

- RestedXP enforcement covers the live profile, stored profiles and account/character templates. Missing stored values inherit the account template or addon defaults. Changes in shared profiles also affect other characters using those profiles.
- YUI enforcement covers the active suite profile, stored profiles and stored HUD configuration sets. Resource selections use v338's Forever specialization catalog, including druid forms; swing timers are untouched. Nameplate runtime Disable methods restore/stop their behavior, and YHUD's configuration-change API rebuilds its active display. Missing APIs block enforcement before storage changes. Failed HUD refreshes remain pending for retry.
- EllesmereUI enforcement covers nameplate profiles, spec presets and encoded spec override keys in EllesmereUIDB, using `_ENP_RefreshAllSettings` for the live display. Missing refresh APIs report a blocked rule; failed refreshes are retried. This adapter was verified against shared-suite 9.4.

Addon enablement is recorded separately in each character's AddOns.txt. Player castbar and eight raid-group visibility preferences are saved in the EllesmereUI core profiles; they remain user-adjustable. Layout positions, general HUD content, route/map-pin displays and optional overlapping statistics are not continuously forced by the guard.

## Maintenance and verification

Add overlapping settings to `Policy.lua` and this table. Extend the relevant adapter and tests when needed; new adapters must be loaded by the TOC and test harness. Verify against installed source when updating addon versions. When an addon is removed, delete its obsolete policies, adapters, TOC dependencies, tests and current documentation.

```powershell
uv run --no-project --with lupa python tools/overlapsettingsguard-tests/run_tests.py
```

The 24 tests use Lua 5.1 and game/addon stubs. They cover policy validation, stored profiles/templates/HUD sets, form overrides, option hooks, combat deferral, profile resets, inactive dependencies, missing APIs, refresh failure/retry, swing preservation, installed-pack dependency validation and current YUI/EllesmereUI ownership. They do not verify live rendering or game API behavior.

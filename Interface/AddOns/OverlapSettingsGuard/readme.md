# OverlapSettingsGuard

Version 0.8.0, for Interface 16001. This local addon keeps duplicate features switched off while all addons named in a rule are loaded. `/osg` lists every rule and its current status. It does not enable disabled addons or lock optional appearance choices on.

## Policy

| Rule | Setting kept off | Required addons | Owner and reason |
| --- | --- | --- | --- |
| `yui.nameplateoutline` | YUI `UtilityTools_Config.nameplateOutline` | YUI, EllesmereUINameplates | EllesmereUI owns nameplate fonts and styling. |
| `yui.friendlynameplates` | YUI `UtilityTools_Config.syncFriendlyNameplates` | YUI, EllesmereUINameplates | EllesmereUI owns friendly nameplate visibility and CVars. |
| `yui.resources` | YHUD mana, rage, energy and combo-point selections, including druid forms | YUI, EllesmereUIUnitFrames | EllesmereUI owns player power/class resources. YUI swing timers and cooldown tracking stay available. |
| `yui.playerhealth` | YHUD `health` selections across resource groups, specs and druid forms | YUI, EllesmereUIUnitFrames | EllesmereUI owns the player health display. |
| `yui.playercast` | YHUD `cast` selections, enabled `cast-only` resource groups and `playerCast.hideNative` | YUI, EllesmereUIUnitFrames | EllesmereUI owns the player castbar; stored HUD sets follow the same rule. |
| `eui.nameplatepower` | EllesmereUI nameplate `showClassPower` | EllesmereUINameplates, EllesmereUIUnitFrames | Unit frames own class resources; no second display on the target nameplate. |
| `gi.friendlynameplates` | GearInsight `qm.autoPlates`, restoring any `qm.platesWeOpened` toggle | GearInsight_Forever, EllesmereUINameplates | EllesmereUI owns friendly-nameplate visibility. |
| `gi.combathud` | GearInsight `keysHud` and its visible runtime frame | GearInsight_Forever, YUI | YUI owns cooldown, DoT and proc tracking. |
| `gi.resources` | The same combined GearInsight `keysHud` | GearInsight_Forever, EllesmereUIUnitFrames | EllesmereUI owns player power and combo points, even without YUI. |
| `gi.levelingstats` | GearInsight `leveling.shown` and its floating frame | GearInsight_Forever, YUI | YUI owns the experience display. The main GearInsight leveling plan remains available. |
| `gi.actionbaredits` | Runtime lock on GearInsight bar placement, binding assignment/presets and restores | GearInsight_Forever, YUI | YUI owns bars and bindings; GearInsight key inspection and macro import remain available. |
| `skinner.unitframes` | UnitFrames namespace `player`, `target`, `focus`, `pet`, `petlvl`, `arena` | Skinner, EllesmereUIUnitFrames | EllesmereUI owns individual frames, including hunter/warlock pets. |
| `skinner.partyframes` | UnitFrames namespace `party` | Skinner, EllesmereUIRaidFrames | EllesmereUI owns party frames. |
| `skinner.castingbar` | `CastingBar.skin`, `CastingBar.glaze` | Skinner, EllesmereUIUnitFrames | EllesmereUI owns the player castbar. |
| `skinner.compactframes` | `CompactFrames.skin`, `CompactFrames.sbars` | Skinner, EllesmereUIRaidFrames | EllesmereUI owns party/raid frames and health bars. |
| `skinner.nameplates` | `Nameplates` | Skinner, EllesmereUINameplates | EllesmereUI owns nameplate styling. |
| `skinner.actionbars` | `MainMenuBar.skin`, `glazesb`, `altpowerbar`, `actbtns`, `extraab` | Skinner, YUI | YUI owns action/status bars and supporting displays. |
| `skinner.minimap` | `Minimap.skin`, `gloss`; `MinimapButtons.skin`, `style` | Skinner, YUI | YUI owns minimap appearance and buttons. |
| `skinner.worldmap` | `WorldMap.skin` | Skinner, YUI | YUI owns world map appearance/layout; map size is preserved. |
| `skinner.chat` | `ChatBubbles.skin`, `ChatButtons`, `ChatConfig`, `ChatEditBox.skin`, `ChatFrames`, `ChatTabs`, `ChatTabsFade`, `CombatLogQBF` | Skinner, YUI | YUI owns chat windows, input, tabs, bubbles and combat-log controls. |
| `skinner.tooltips` | `Tooltips.skin`, `Tooltips.glazesb` | Skinner, YUI | YUI retains tooltip appearance/behavior. GearInsight tooltip content remains available. |
| `skinner.details` | `DisabledSkins.Details=true` | Skinner, Details | Disable the competing skin; Details owns meter appearance. |
| `skinner.detailsframework` | `DisabledSkins["DetailsFramework-1.0 (Lib)"]=true` | Skinner, Details | Disable framework widget reskinning; Details retains its appearance. |

EllesmereUI owns individual/group frames and nameplates; YUI owns the remaining interface features.

Details.20261014.15330.172 is the pack's only combat meter, with bundled DataStorage, Compare2, EncounterDetails, RaidCheck and TinyThreat modules. YUI's Forever loader excludes YDamageMeter, and EllesmereUIDamageMeters is absent. YUI's Details icon synchronization and EUI's per-unit threat styling are complementary. Details_Streamer and Details_Vanguard remain excluded. Skinner's Details and DetailsFramework library skins are now explicitly disabled; the Auctionator skin remains available.

## Enforcement and scope

Checks run after login, on supported option hooks and every two seconds as a fallback. Changes wait until combat ends. Chat messages explain reverted settings and name any other affected profiles. When a reload is needed, chat asks you to type `/reload` when ready. The guard never opens a popup. Failed enforcement is also reported in chat.

The policy contains 23 rules for the installed pack. Ownership is conditional on addons being loaded, rather than the owner's optional feature currently being enabled; use the owner's settings when choosing whether to automate a task.

CharacterUIBaseline 0.2.0 synchronizes existing owner settings once on each target login/reload, rather than creating a second display or continuous feature toggle, so the policy stays at 23 rules. Its overlaps are native Edit Mode layout (including importing the source layout when different), chat font/primary-window geometry, EUI `partyUnlockPos`/`unlockPos`, and these display CVars: `nameplateSelectedScale`, `nameplateMaxDistance`, `nameplateMinScale`, `nameplateMaxScale`, `nameplateMaxAlphaDistance`, `nameplateTargetBehindMaxDistance`, `nameplateMinAlpha`, `nameplateMaxAlpha`, `nameplateMinAlphaDistance`, `cooldownViewerEnabled`, `mapFade`, `showQuestLevel`, `cameraSavedPitch`, `cameraSavedDistance` and `enableMultiActionBars`. The source character is excluded and publishes at logout; target edits are reset on the next login. OSG startup preferences still run normally after login and may supersede conflicting captured CVars. EUI spec-to-profile mappings and all specialization/talent data are preserved. `/uib apply` explicitly retries sync; no per-setting lock-off rule is appropriate for this ownership-preserving coordinator.

- GearInsight enforcement targets its current account database, including upstream defaults when fields are absent. Option hooks request a check on the next frame; periodic checks catch database resets and visible frames left behind after failed refreshes. Missing APIs report blocked before storage changes. The combined resource/cooldown HUD cannot be split with upstream settings, so either relevant owner disables it. The separate rotation recommendation board (`keysBoard`) remains available.
- GearInsight has no setting to disable its action-bar editor. The adapter wraps only its six public editing methods (`ApplyAll`, `PlaceMissing`, `Restore`, `AssignSlotKey`, `ApplyKeyTemplate`, `RestoreStolen`) with a conditional runtime lock. It preserves caller return types and forwards to the original methods if YUI is not loaded. No protected game APIs or upstream source files are replaced. The lock is checked again after method replacement. A blocked edit explains ownership in chat.
- YUI enforcement covers the active suite profile, stored profiles and stored HUD configuration sets. Resource selections use v341's Forever specialization catalog, including druid forms; swing timers are untouched. Player health and cast resources are opt-in upstream, so missing selections do not trigger a change. Dedicated cast-only groups bypass selections and are separately disabled; native castbar suppression stays off. Nameplate runtime Disable methods restore/stop their behavior, and YHUD's configuration-change API rebuilds its active display. Missing APIs block enforcement before storage changes. Failed HUD refreshes remain pending per rule for retry.
- EllesmereUI enforcement covers nameplate profiles, spec presets and encoded spec override keys in EllesmereUIDB, using `_ENP_RefreshAllSettings` for the live display. Missing refresh APIs report a blocked rule; failed refreshes are retried. This adapter was verified against shared-suite 9.5.5.
- Skinner enforcement covers the current AceDB profile, its cached active skin profile, stored profiles and the UnitFrames namespace, including inherited defaults. Skinner-only checks also run when the guard loads and at `PLAYER_LOGIN`, before Skinner's delayed skin passes; profile reset/copy/change callbacks and periodic checks catch later edits. Already applied skins require `/reload` because changing settings cannot undo their texture and hook changes. Missing databases or malformed setting paths report blocked before that rule mutates storage. Upstream Skinner files stay unchanged. Blizzard-window and Auctionator skinning remain available; no layout, UI-scale or viewport setting is imposed.

Addon enablement is recorded separately in each character's AddOns.txt. Player castbar and eight raid-group visibility preferences are saved in the EllesmereUI core profiles; they remain user-adjustable. Layout positions, general HUD content, route/map-pin displays and optional overlapping statistics are not continuously forced by the guard.

## Startup console settings

Two seconds after the first `PLAYER_ENTERING_WORLD` event on each login or UI reload, after the initial overlap checks, the guard makes one separate `SetCVar` call per command, in this order. Each call has the same effect as entering its console command in chat, regardless of the selected addon profile.

```text
/console outlineModeShowLootEffectWhenDisabled 1
/console cameraDistanceMaxZoomFactor 4
/console nameplateMaxDistance 41
/console targetNearestDistanceRadius 50
/console ffxGlow 0
/console volumeFog 0
/console ResampleAlwaysSharpen 1
/console Contrast 85
/console Brightness 55
/console Gamma 1.5
```

Startup overlaps: YUI's installer and EllesmereUI's camera options also write camera zoom; EllesmereUINameplates writes nameplate distance 60; EllesmereUI's graphics options also write sharpening and its Optimize/Restore actions write contrast. These startup preferences do not disable those addon options or add continuous enforcement rules to `Policy.lua`.

Contrast and brightness use percentage values (85 and 55); gamma uses 1.5.

The values are applied once per session; zone transitions and the two-second overlap checker do not reapply them. Delayed addon initialization or later profile changes can still overwrite them. Startup coverage uses game API stubs; verify the client's accepted values and visible effects in-game. No addon-profile tables or resolution-specific layouts are changed; the same values apply at 1080p, 1440p and 4K. The adoption script already copies these addon files.

## Maintenance and verification

Add overlapping settings to `Policy.lua` and this table. Extend the relevant adapter and tests when needed; new adapters must be loaded by the TOC and test harness. Verify against installed source when updating addon versions. When an addon is removed, delete its obsolete policies, adapters, TOC dependencies, tests and current documentation.

```powershell
uv run --no-project --with lupa python tools/overlapsettingsguard-tests/run_tests.py
```

The 39 tests use Lua 5.1, game/addon stubs and installed source. They cover policy validation/dependencies, YUI profiles/HUD sets and druid forms, EUI spec overrides, combat deferral, reset detection, runtime refresh failures/retries, GearInsight upstream defaults, visible frames, owner conditions, safe return types and its actual bar-editor code. Skinner coverage includes startup before login, nested settings, stored/namespace profiles, default inheritance, missing owners/databases, reload reporting and real profile resets using its installed AceDB, Core Options and UnitFrames source. Tests verify preserved planning/wishlists/rotation advice and no action/binding writes through guarded editor methods. They also verify all ten startup CVars, ordering and once-per-session behavior.

GearInsight 0.4.31 is the verified adapter baseline. Its translated tooltips enrich content rather than replacing YUI/EUI styling. Map destinations and the unique rotation board remain user choices. User-invoked graphics/camera macros can change startup CVars later, just like existing owner options. Layouts are unchanged; actual loading, secret-value handling and rendering at 1080p/1440p/4K still require in-game verification.

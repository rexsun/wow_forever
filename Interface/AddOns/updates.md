# WoW: Forever add-on updates

This log records changes made in `World of Warcraft/_classic_beta_/Interface/AddOns`. See [readme.md](readme.md) for the current inventory and sources.

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

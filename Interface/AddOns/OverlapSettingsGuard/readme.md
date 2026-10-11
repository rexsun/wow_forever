# OverlapSettingsGuard

Version 0.3.0, written for this installation (WoW: Forever 1.60.1, Interface 16001). It isn't published anywhere.

Some installed add-ons provide the same feature. When both copies run, they undo each other's work, for example two add-ons both setting the chat font size. OverlapSettingsGuard keeps the duplicate setting in one add-on switched **off**:

- **At login** (2 s after `PLAYER_LOGIN`), any locked setting that is on gets switched off.
- **When you switch one on in game**, through the add-on's options, a slash command or a profile change, it is switched back off on the next frame.
- **Each time it switches something off**, it prints a chat line and shows a popup naming the setting and the reason. If the change needs a reload, the popup offers "Reload now". The popup for one setting appears at most once every 10 s.
- **In combat**, the switch waits until combat ends.

There is no in-game override. To allow a setting, change [Policy.lua](Policy.lua) and this readme.

## Policy

A rule only applies while every add-on in its "Locked off when loaded" column is loaded. Add-on loading is per character, so this is checked on the character that is logged in.

| Rule id | Setting | Locked off when loaded | Why |
|---|---|---|---|
| `leatrix.minimap` | Leatrix Plus: Enhance minimap (`MinimapModder`) | Leatrix Plus, ForeverUI | ForeverUI's Minimap module already squares and styles the minimap. |
| `leatrix.editbox` | Leatrix Plus: Move editbox to top (`MoveChatEditBoxToTop`) | Leatrix Plus, ForeverUI | ForeverUI's chat setting "Where you type" places the edit box. |
| `leatrix.chatfont` | Leatrix Plus: Set chat font size (`SetChatFontSize`) | Leatrix Plus, ForeverUI | ForeverUI sets the chat font size; Leatrix's size overrides it after login. |
| `rxp.autoquests` | RestedXP: Quest auto accept/turn in (`enableQuestAutomation`) | RestedXP, Leatrix Plus | Leatrix accepts and turns in quests broadly, including quests outside the active guide. |
| `rxp.autogossip` | RestedXP: Gossip automation (`enableGossipAutomation`) | RestedXP, Leatrix Plus | Leatrix handles gossip for quest interactions. |
| `rxp.questrewards` | RestedXP: Quest auto rewards (`enableQuestRewardAutomation`) | RestedXP, Leatrix Plus | Leatrix owns turn-ins; RestedXP must not claim guide-selected rewards. |
| `rxp.questchoices` | RestedXP: Quest Reward Automation (`enableQuestChoiceAutomation`) | RestedXP, Leatrix Plus | Leatrix owns turn-ins; RestedXP must not claim calculated rewards. |
| `leatrix.flighttimes` | Leatrix Plus: Show flight times (`ShowFlightTimes`) | Leatrix Plus, RestedXP | RestedXP shows flight times on the flight map and a flight progress bar. |
| `fui.questforever` | ForeverUI: QuestForever module | ForeverUI, RestedXP | RestedXP draws its route on the map and minimap; QuestForever pins every quest you could take. |
| `fui.guideonaccept` | ForeverUI: open the quest guide on accept (`guideOnAccept`, `guideOnAcceptPad`) | ForeverUI, RestedXP | Leatrix accepts quests automatically and RestedXP shows its own steps, so the guide would open at almost every quest giver. |
| `fui.arrow` | ForeverUI: waypoint arrow (Arrow module) | ForeverUI, RestedXP | RestedXP has its own arrow to the next step. |
| `fui.selljunk` | ForeverUI: sell junk at vendors (Loot `sellJunk`) | ForeverUI, Leatrix Plus | Leatrix Plus "Sell junk automatically" sells grey items. |
| `rxp.selljunk` | RestedXP: Auto Sell Junk (`autoSellJunk`) | RestedXP, Leatrix Plus | Leatrix Plus "Sell junk automatically" sells grey items. RestedXP's delete-junk key stays. |
| `rxp.talentguides` | RestedXP: Enable Talents Guides (`enableTalentGuides`) | RestedXP, Talents Forever | Talents Forever plans talents for Forever's talent window. RestedXP's talent guide hooks the old talent frame. |
| `rxp.upgradetooltip` | RestedXP: item upgrade tooltips (keeps `disableUpgradeTooltip` ticked) | RestedXP, ForeverUI | ForeverUI's Loot module marks upgrades in tooltips and bags. RestedXP's quest reward advice stays on. |
| `rxp.nameplatedistance` | RestedXP: Maximize Nameplate Distance (`enableMaxNameplateDistance`) | RestedXP, Plater | It sets nameplate range to 41 at every loading screen, overriding Plater's nameplate distance. |
| `leatrix.combatplates` | Leatrix Plus: Combat plates (`CombatPlates`) | Leatrix Plus, Plater | Plater owns visibility; Leatrix toggles enemy nameplates at each combat transition. |
| `plater.resources` | Plater: Resource bars (`resources_settings.global_settings.show`) | Plater, ClassUIEnhanced | ClassUIEnhanced owns the player's class resource display. |
| `plater.personalbar` | Plater: Personal health and mana bars (`nameplateShowSelf`, including `saved_cvars`) | Plater, ClassUIEnhanced | ClassUIEnhanced owns player health and power tracking; Blizzard unit frames remain available. |

ForeverUI is uninstalled. Rules requiring it are inactive and remain for compatibility if it is restored. Leatrix minimap, chat font and editbox settings are now available; inactive rules do not label those options locked. Blizzard action bars, bags and unit/group frames remain the defaults. ClassUIEnhanced's own prompt controls hiding duplicate Blizzard cooldown viewers; the guard does not disable the Cooldown Manager that supplies its data.

Leatrix Plus is the quest automation provider: `AutomateQuests`, `AutomateGossip`, `AutoQuestRegular`, `AutoQuestDaily`, `AutoQuestWeekly` and `AutoQuestCompleted` are enabled in the saved settings; `AutoQuestShift` is off. These settings remain user-adjustable; the guard no longer locks Leatrix quest/gossip automation off. Quests with multiple reward choices still require a manual choice. RestedXP flight-path, binding and trainer automation remain unchanged.

RestedXP is the add-on folder `RXPGuides`; Talents Forever is `TalentsForeverBook`.

## Where each setting is switched off

Each add-on stores settings at a different level. The guard switches a locked setting off in every place the add-on can load it from, so no character or profile brings it back:

| Add-on | Account level | Profile / character level |
|---|---|---|
| Leatrix Plus | `LeaPlusDB`, one copy for the whole account. The live value is switched off, and Leatrix saves it when you log out or reload. | None: Leatrix has no per-character settings. |
| ForeverUI | `ForeverUIDB.profiles`: every stored profile is switched off. | The active profile (`ForeverUI.db`, the profile mapped to this character in `ForeverUIDB.characters`) is switched off through ForeverUI's own functions, so the change takes effect at once. |
| RestedXP | `RXPSettings.profiles`: every character's stored profile. `RXPData.defaultProfile`: the account template new profiles start from. | The live profile (`RXP.settings.profile`, this character's) and `RXPCData.localDB` (this character's fallback template). |
| Plater | `PlaterDB.profiles`: resource displays and saved personal-bar CVars in every stored profile. | The active `Plater.db.profile` and the live `nameplateShowSelf` CVar. |

Notes:

- **Shared profiles.** A ForeverUI profile can be shared by several characters (all of yours use "Default"). Switching a setting off in it applies to each character using it, including characters that don't load the other add-on.
- **Inherited values.** RestedXP leaves out a stored value that equals its template. A stored RestedXP profile without its own value inherits the account template, so once the template is off, that profile is off too.
- **Chat line.** When copies other than the live one are changed, the chat line lists them ("Also switched off in profiles: …").

## Commands

`/osg` lists every rule and its status, then runs a check:

- **locked off**: the setting is off.
- **on, switching off**: the setting is on and the check now switches it off.
- **inactive**: an add-on the rule needs isn't loaded.
- **cannot enforce**: the setting can't be read. The line says why, and the same warning is printed once per session.

## How settings are read and noticed

**Leatrix Plus** ([Adapters/LeatrixPlus.lua](Adapters/LeatrixPlus.lua)). Leatrix keeps its live values private, so the guard works through Leatrix's own option checkboxes:

- **Finding a checkbox.** The checkboxes have no names. Each is found on its options page (child frames of `LeaPlusGlobalPanel`, Page0 to Page9 in creation order) by where it is anchored. The anchor doesn't depend on the game language.
- **Checking it's the right one.** A second check uses the `*` Leatrix adds to the label of options that need a reload.
- **Reading.** The checkbox's own OnShow handler is called to re-read Leatrix's live value.
- **Switching off.** The checkbox is clicked through Leatrix's own handler, so Leatrix's reload button and its automation hooks behave as if you had clicked it.
- **Tooltip.** A "Locked off by OverlapSettingsGuard" line is added.

The positions come from Leatrix Plus 1.60.11. If an update moves a checkbox, its rule shows **cannot enforce** with the reason and the installed Leatrix version, rather than switching the wrong option.

**ForeverUI** ([Adapters/ForeverUI.lua](Adapters/ForeverUI.lua)):

- **Switching off the active profile.** Through ForeverUI's own functions: `QuestForever.Toggle(false)` and `SetModuleEnabled("Arrow", false)`. For the guide-on-accept and sell-junk settings, the guard writes the value and refreshes ForeverUI's options page.
- **Noticing changes.** The guard hooks `RefreshOptions`, `SetModuleEnabled` and the quest guide's `PaintAutoLine`.

**RestedXP** ([Adapters/RestedXP.lua](Adapters/RestedXP.lua)):

- **Switching off.** The guard writes the values directly. RestedXP reads quest, reward, gossip, sell-junk and tooltip settings when they are used. Talent guides and nameplate distance only take effect after a reload, so the popup offers one when they were on for this character.
- **Noticing changes.** The guard hooks AceConfig's `NotifyChange` for the "RestedXP Guides" options.

**All add-ons.** A check every 2 s catches changes that reach no hook, such as `/fui quests guide on`, RestedXP slash commands or a RestedXP profile switch.

**Plater** ([Adapters/Plater.lua](Adapters/Plater.lua)): resource bars are disabled in the active and every stored profile. The personal bar is disabled through `nameplateShowSelf`, and any enabled stored copies of that CVar are reset. `Plater:RefreshConfig()` applies the changes and is hooked to notice profile refreshes; the ticker also catches direct options/CVar edits. Changes wait until combat ends. Missing live Plater settings or an unavailable CVar report cannot enforce rather than guessing.

## Adding a rule

1. Add an entry to `Policy.lua`. `when[1]` must be the add-on that owns the setting.
2. If the adapter doesn't know the setting yet, add it to the adapter's table (`SPOTS` in the Leatrix adapter, `SETTINGS` in the ForeverUI adapter, `KEYS` in the RestedXP adapter). A new add-on gets a new file in `Adapters/` plus a line in the `.toc`.
3. Add the rule to the table above.
4. Run the tests:

   ```
   uv run --no-project --with lupa python tools/overlapsettingsguard-tests/run_tests.py
   ```

   They run the add-on in Lua 5.1 against stand-ins for the game, Leatrix Plus, ForeverUI, RestedXP and Plater. A mistake in `Policy.lua` (unknown adapter or key, duplicate id) also prints a "policy error" line at login.

## Known limits

- Leatrix Plus checkboxes are found by position, so a Leatrix update can make its rules **cannot enforce** until `SPOTS` is updated.
- A setting that needs a reload stays active until you reload. The guard switches off its stored value and offers the reload.
- Stored profiles are only checked while a character that loads both add-ons of a rule is logged in. Until then, other characters' copies keep whatever they hold.

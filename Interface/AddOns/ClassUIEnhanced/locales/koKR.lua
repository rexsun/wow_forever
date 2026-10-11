
local _
---@type string, private
local addonName, private = ...

if GetLocale() ~= "koKR" then return end

local L = private.L

--[[Translation missing --]]
L["A"] = "A"
--[[Translation missing --]]
L["ABOUT_AUTHORS"] = "cont1nuity and Terciob"
--[[Translation missing --]]
L["ABOUT_AUTHORS_LABEL"] = "Authors"
--[[Translation missing --]]
L["ABOUT_CHANGELOG"] = "Changelog"
--[[Translation missing --]]
L["ABOUT_CHANGELOG_DEV"] = [=[Changelog is available in release builds.
See CHANGELOG.md for the full history.]=]
--[[Translation missing --]]
L["ABOUT_DESCRIPTION"] = "A comprehensive class UI replacement that brings your cooldowns, resources, cast bars, and buffs together into one fully customizable, anchored layout - all configurable directly through WoW's Edit Mode."
--[[Translation missing --]]
L["ABOUT_DISCORD_LABEL"] = "Discord"
--[[Translation missing --]]
L["ABOUT_VERSION_LABEL"] = "Version"
--[[Translation missing --]]
L["ADDITIONAL_FRAMES_DESC"] = "Create custom frames that pull specific spells from any combination of trackers into independent, positionable frames with their own layout settings."
--[[Translation missing --]]
L["AF_EDIT_IN_TRACKING_DESC"] = "This frame's spells and items, their order, custom spells, per-spell active buff duration, pandemic glow exclusions, per-spell bar colors, missing glows and Track On are set in the Tracking tab. Opens it on this frame."
--[[Translation missing --]]
L["AF_SPELL_FILTER_PLACEHOLDER"] = "Filter by name or ID..."
--[[Translation missing --]]
L["ANCHOR_BOTTOM"] = "Bottom"
--[[Translation missing --]]
L["ANCHOR_BOTTOMLEFT"] = "Bottom Left"
--[[Translation missing --]]
L["ANCHOR_BOTTOMRIGHT"] = "Bottom Right"
--[[Translation missing --]]
L["ANCHOR_CENTER"] = "Center"
--[[Translation missing --]]
L["ANCHOR_CIRCULAR_ERROR"] = "Cannot anchor %s to %s: this would create a circular anchor chain."
--[[Translation missing --]]
L["ANCHOR_CURSOR"] = "Follow Mouse"
--[[Translation missing --]]
L["ANCHOR_LEFT"] = "Left"
--[[Translation missing --]]
L["ANCHOR_NONE"] = "None (Free Moving)"
--[[Translation missing --]]
L["ANCHOR_RIGHT"] = "Right"
--[[Translation missing --]]
L["ANCHOR_TOP"] = "Top"
--[[Translation missing --]]
L["ANCHOR_TOPLEFT"] = "Top Left"
--[[Translation missing --]]
L["ANCHOR_TOPRIGHT"] = "Top Right"
--[[Translation missing --]]
L["ARCANE_MANA_BAR"] = "Show Mana for Arcane"
--[[Translation missing --]]
L["ARCANE_MANA_BAR_DESC"] = "Show the primary resource bar (mana) for Arcane Mages even when Auto-Hide is enabled. Arcane relies heavily on mana management."
--[[Translation missing --]]
L["ASSISTED_HIGHLIGHT_OFF_CONFIRM"] = [=[No tracker uses Rotation Highlight any more.

Also turn off Blizzard's Assisted Highlight on your action bars? It was turned on for Rotation Highlight.]=]
--[[Translation missing --]]
L["AUG_EBON_MIGHT_BAR"] = "Show Ebon Might for Augmentation"
--[[Translation missing --]]
L["AUG_EBON_MIGHT_BAR_DESC"] = "Show Ebon Might remaining duration on the primary resource bar for Augmentation Evokers. When disabled, standard mana bar rules apply."
--[[Translation missing --]]
L["AUG_EBON_MIGHT_CRIT_COLOR_VALUE"] = "Crit Ebon Might Color"
--[[Translation missing --]]
L["AUG_EBON_MIGHT_CRIT_COLOR_VALUE_DESC"] = "Color used for the border glow while a crit-roll Ebon Might is active. Default is pale gold."
--[[Translation missing --]]
L["AUG_EBON_MIGHT_CRIT_GLOW"] = "Highlight Crit Ebon Might (Glow)"
--[[Translation missing --]]
L["AUG_EBON_MIGHT_CRIT_GLOW_DESC"] = "Pulse a gold border around the Ebon Might bar while a crit-roll Ebon Might is active, so you know to extend it."
--[[Translation missing --]]
L["AUG_EBON_MIGHT_DOUBLE_TIME_TEXT"] = "Show Double Time Remaining"
--[[Translation missing --]]
L["AUG_EBON_MIGHT_DOUBLE_TIME_TEXT_DESC"] = "Show the remaining Double Time duration next to the Ebon Might bar (12.1+ only). Double Time is the buff granted while a crit-roll Ebon Might is active."
--[[Translation missing --]]
L["AUG_EBON_MIGHT_LIVE_UPDATE"] = "Live Ebon Might Stat Update"
--[[Translation missing --]]
L["AUG_EBON_MIGHT_LIVE_UPDATE_DESC"] = "Poll an ally's Ebon Might buff every 1s so the displayed stat value stays in sync when your main stat changes mid-buff (trinket procs, gear swaps). Disable to only refresh on each cast."
--[[Translation missing --]]
L["AUG_EBON_MIGHT_SHOW_DUPLICATES"] = "Show Duplicate Duration"
--[[Translation missing --]]
L["AUG_EBON_MIGHT_SHOW_DUPLICATES_DESC"] = "Show how long your Duplicate has left on the Ebon Might bar. Hidden when no Duplicate is active."
--[[Translation missing --]]
L["AUG_EBON_MIGHT_SHOW_STAT"] = "Show Ebon Might Stat Value"
--[[Translation missing --]]
L["AUG_EBON_MIGHT_SHOW_STAT_DESC"] = "Append the granted main-stat value (e.g. +12.3k) to the Ebon Might bar text. Off shows duration only."
--[[Translation missing --]]
L["AURA_UNIT_BOTH"] = "Both"
--[[Translation missing --]]
L["AURA_UNIT_DESC"] = "Which unit this spell's aura is watched on. Both watches you and your target; Player only shows it while it is on you; Target only shows it while it is on your target."
--[[Translation missing --]]
L["AURA_UNIT_HEADER"] = "Track On"
--[[Translation missing --]]
L["AURA_UNIT_PLAYER"] = "Player"
--[[Translation missing --]]
L["AURA_UNIT_TARGET"] = "Target"
--[[Translation missing --]]
L["AUTO_HIDE"] = "Auto-Hide"
--[[Translation missing --]]
L["AUTO_HIDE_DESC"] = "Automatically hide the primary resource bar for mana specs that do not benefit from it. Per-class overrides are available in the Class Specific Tweaks section."
--[[Translation missing --]]
L["AUTO_HIDE_EDIT_DESC"] = "Automatically hide the primary resource bar for mana specs that do not benefit from tracking mana. Per-class overrides are available in the Class Specific Tweaks section."
--[[Translation missing --]]
L["AUTO_HIDE_MANA_POTIONS_DESC"] = "Automatically hide mana potions for non-healer specs that do not benefit from them."
--[[Translation missing --]]
L["B"] = "B"
--[[Translation missing --]]
L["BALANCE_MANA_BAR"] = "Show Mana for Balance"
--[[Translation missing --]]
L["BALANCE_MANA_BAR_DESC"] = "Show the mana bar for Balance Druids even when Auto-Hide is enabled. Astral Power is shown on the Secondary Resources bar."
--[[Translation missing --]]
L["BAR_BORDER_COLOR"] = "Border Color"
--[[Translation missing --]]
L["BAR_BORDER_COLOR_DESC"] = "Color of the border around health, resource, and cast bars."
--[[Translation missing --]]
L["BAR_BORDER_ENABLED"] = "Show Border"
--[[Translation missing --]]
L["BAR_BORDER_ENABLED_DESC"] = "Show a thin border around health, resource, and cast bars."
--[[Translation missing --]]
L["BAR_BORDER_HEADER"] = "Bar Borders"
--[[Translation missing --]]
L["BAR_BORDER_INSIDE"] = "Inside Border"
--[[Translation missing --]]
L["BAR_BORDER_INSIDE_DESC"] = "Draw the border inside the bar instead of outside. Inside borders overlap the bar content."
--[[Translation missing --]]
L["BG_COLOR_HEALTH"] = "Health Bar Background"
--[[Translation missing --]]
L["BG_COLOR_HEALTH_DESC"] = "Background color for the player health bar."
--[[Translation missing --]]
L["BG_COLOR_PRIMARY"] = "Background"
--[[Translation missing --]]
L["BG_COLOR_PRIMARY_DESC"] = "Background color for the primary resource bar."
--[[Translation missing --]]
L["BG_COLOR_SECONDARY"] = "Secondary Resource Background"
--[[Translation missing --]]
L["BG_COLOR_SECONDARY_DESC"] = "Background color for the secondary resource bar segments."
--[[Translation missing --]]
L["BORDER_SIZE"] = "Border Thickness"
--[[Translation missing --]]
L["BORDER_SIZE_DESC"] = "Thickness of the border in pixels."
--[[Translation missing --]]
L["BREAKPOINT_FILL_INTERPOLATION"] = "Fill Transition"
--[[Translation missing --]]
L["BREAKPOINT_FILL_INTERPOLATION_DESC"] = [=[How fill color changes between breakpoints.

Step: instant snap at each threshold.
Linear: smooth gradient between thresholds.]=]
--[[Translation missing --]]
L["BREAKPOINT_PIP_ADD"] = "Add"
--[[Translation missing --]]
L["BREAKPOINT_PIP_FILL_COLOR"] = "Fill Color"
--[[Translation missing --]]
L["BREAKPOINT_PIP_FILL_ENABLED"] = "Fill"
--[[Translation missing --]]
L["BREAKPOINT_PIP_FILL_ENABLED_DESC"] = "Recolor the resource bar fill when power reaches this threshold."
--[[Translation missing --]]
L["BREAKPOINT_PIP_MODE"] = "Value Mode"
--[[Translation missing --]]
L["BREAKPOINT_PIP_MODE_DESC"] = [=[How pip values are interpreted.

Percent: position pips at a percentage of max power (0-100).
Absolute: position pips at a fixed power value (e.g. 45 energy).]=]
--[[Translation missing --]]
L["BREAKPOINT_PIP_REMOVE"] = "Remove"
--[[Translation missing --]]
L["BREAKPOINT_PIP_SHOW_LINE"] = "Show Pip Line"
--[[Translation missing --]]
L["BREAKPOINT_PIP_SHOW_LINE_DESC"] = "Show the pip as a line over the bar. When disabled, only the background zone color behind the bar fill is shown."
--[[Translation missing --]]
L["BREAKPOINT_PIP_WIDTH"] = "Pip Width"
--[[Translation missing --]]
L["BREAKPOINT_PIP_ZONE_AUTO_HIDE"] = "Hide Zone at Threshold"
--[[Translation missing --]]
L["BREAKPOINT_PIP_ZONE_AUTO_HIDE_DESC"] = "Automatically hide the background zone when the resource bar reaches its threshold. When disabled, zones are always visible."
--[[Translation missing --]]
L["BREAKPOINT_PIP_ZONE_COLOR"] = "Zone color"
--[[Translation missing --]]
L["BREAKPOINT_PIP_ZONE_DIRECTION_DESC"] = "Which side of the breakpoint to color."
--[[Translation missing --]]
L["BREAKPOINT_PIP_ZONE_ENABLED"] = "Zone"
--[[Translation missing --]]
L["BREAKPOINT_PIP_ZONE_ENABLED_DESC"] = "Color the background region on one side of this breakpoint."
--[[Translation missing --]]
L["BREAKPOINT_PIP_ZONE_NEXT"] = "Next"
--[[Translation missing --]]
L["BREAKPOINT_PIP_ZONE_PREVIOUS"] = "Prev"
--[[Translation missing --]]
L["BREAKPOINT_PIPS_EMPTY"] = "No breakpoint pips for this spec."
--[[Translation missing --]]
L["BREAKPOINT_PIPS_ENABLED"] = "Enable Breakpoint Pips"
--[[Translation missing --]]
L["BREAKPOINT_PIPS_ENABLED_DESC"] = "Show thin vertical lines on the primary resource bar at specific percentage thresholds. Settings are saved per specialization."
--[[Translation missing --]]
L["BREAKPOINT_PIPS_HEADER"] = "Primary Resource Breakpoint Pips"
--[[Translation missing --]]
L["BREAKPOINT_PIPS_HEADER_SECONDARY"] = "Secondary Resource Breakpoint Pips"
--[[Translation missing --]]
L["BREAKPOINT_PIPS_SPEC_ENABLED"] = "Enable (This Spec)"
--[[Translation missing --]]
L["BREAKPOINT_PIPS_SPEC_ENABLED_DESC"] = "Per-spec toggle. Only honored when the global Enable toggle is on. Specs without an entry default to enabled."
--[[Translation missing --]]
L["BREAKPOINT_PIPS_SPEC_LABEL"] = "Pips for %s"
--[[Translation missing --]]
L["BUFF_CAT_FLASK"] = "Flasks"
--[[Translation missing --]]
L["BUFF_CAT_FOOD"] = "Food"
--[[Translation missing --]]
L["BUFF_CAT_IMBUE"] = "Weapon Imbues"
--[[Translation missing --]]
L["BUFF_CAT_OIL"] = "Weapon Oils"
--[[Translation missing --]]
L["BUFF_CAT_POISON"] = "Weapon Poisons"
--[[Translation missing --]]
L["BUFF_CAT_RUNE"] = "Augment Runes"
--[[Translation missing --]]
L["BUFF_CAT_WEAPON_BUFF"] = "Weapon Buffs"
--[[Translation missing --]]
L["BUTTON_PRESS_ENABLED"] = "Show Pressed Overlay"
--[[Translation missing --]]
L["BUTTON_PRESS_ENABLED_DESC"] = "Show a darkened overlay on tracker icons when the corresponding action bar keybind is pressed, mimicking the action bar push effect."
--[[Translation missing --]]
L["BUTTON_PRESS_HEADER"] = "Button Press"
--[[Translation missing --]]
L["CANCEL_IMPORT"] = "Cancel"
--[[Translation missing --]]
L["CANNOT_OPEN_EDIT_MODE_COMBAT"] = "Cannot open Edit Mode during combat."
--[[Translation missing --]]
L["CAST_TEXT_FORMAT_BOTH"] = "Both"
--[[Translation missing --]]
L["CAST_TEXT_FORMAT_NAME"] = "Spell Name"
--[[Translation missing --]]
L["CAST_TEXT_FORMAT_NONE"] = "None"
--[[Translation missing --]]
L["CAST_TEXT_FORMAT_TIME"] = "Cast Time"
--[[Translation missing --]]
L["CAST_TIME_STYLE_ELAPSED_TOTAL"] = "Elapsed / Total"
--[[Translation missing --]]
L["CAST_TIME_STYLE_REMAINING"] = "Remaining"
--[[Translation missing --]]
L["CAST_TIME_STYLE_REMAINING_TOTAL"] = "Remaining / Total"
--[[Translation missing --]]
L["CASTBAR_COLORS_HEADER"] = "Cast Bar Colors"
--[[Translation missing --]]
L["CDM_ALERTS_DESC"] = [=[Plays the sound and visual alerts configured in Blizzard's own Cooldown Manager options, since ClassUIEnhanced keeps its window hidden, and the alerts you set per spell with Alerts in the Tracking tab. Nothing happens until you configure at least one.

Some alerts only Blizzard's Cooldown Manager can play: pandemic, charge gained, and text-to-speech when a buff is gained or lost. If you set one up, ClassUIEnhanced turns the Cooldown Manager on and keeps it hidden so they play. Alerts for a spell becoming ready or going on cooldown play only for spells a ClassUIEnhanced tracker is showing. To hear every alert exactly as Blizzard plays it, turn on Target Debuff Sounds.]=]
--[[Translation missing --]]
L["CDM_ALERTS_TOGGLE"] = "Cooldown Manager Alerts"
--[[Translation missing --]]
L["CDM_AUTO_FETCH_DESC"] = "When enabled, the trackers automatically follow your Cooldown Manager configuration (including spells you moved between categories or hid there). When disabled, only your manually tracked spells are shown. Manually tracked spells always apply either way."
--[[Translation missing --]]
L["CDM_AUTO_FETCH_TOGGLE"] = "Auto-Populate From Cooldown Manager"
--[[Translation missing --]]
L["CDM_HIDE_CONFIRM"] = "Turn It Off"
--[[Translation missing --]]
L["CDM_HIDE_KEEP"] = "Keep It"
--[[Translation missing --]]
L["CDM_HIDE_NEVER"] = "Keep It, Don't Ask Again"
--[[Translation missing --]]
L["CDM_HIDE_PROMPT"] = [=[Nothing in your current ClassUIEnhanced setup needs Blizzard's Cooldown Manager, and ClassUIEnhanced draws its own cooldown icons.

Turn the Cooldown Manager off?

If you use it for something ClassUIEnhanced does not show, keep it. You can turn it back on at any time in Blizzard's settings.]=]
--[[Translation missing --]]
L["CDM_SECTION_HEADER"] = "Blizzard Cooldown Manager"
--[[Translation missing --]]
L["CDM_SUPPRESS_VIEWERS_DESC"] = "Hide Blizzard's Cooldown Manager on this character, and keep it hidden even if something turns it back on. Answering Turn It Off in ClassUIEnhanced's prompt ticks this for you. Switch this off if another addon needs the Cooldown Manager visible - ClassUIEnhanced will then leave Blizzard's frames completely alone. This setting belongs to this character, not to the profile."
--[[Translation missing --]]
L["CDM_SUPPRESS_VIEWERS_TOGGLE"] = "Hide Blizzard's Cooldown Manager"
--[[Translation missing --]]
L["CDM_TARGET_SOUNDS_DESC"] = "Sounds for your debuffs on your target can only be played by Blizzard's Cooldown Manager, because ClassUIEnhanced cannot tell your debuff from another player's. This requires the Cooldown Manager to be enabled: ClassUIEnhanced turns it on and keeps it hidden, and it then plays all of its own alerts. Turning this off again turns the Cooldown Manager back off if you chose Turn It Off."
--[[Translation missing --]]
L["CDM_TARGET_SOUNDS_TOGGLE"] = "Target Debuff Sounds"
--[[Translation missing --]]
L["CHANGE_ALL_FONTS_APPLIED"] = "Font settings applied to all components."
--[[Translation missing --]]
L["CHANGE_ALL_FONTS_APPLY"] = "Apply to All"
--[[Translation missing --]]
L["CHANGE_ALL_FONTS_APPLY_DESC"] = "Overwrite every font setting (cast bars, resources, timers, stacks) with the values above."
--[[Translation missing --]]
L["CHANGE_ALL_FONTS_HEADER"] = "Change All Fonts"
--[[Translation missing --]]
L["CHANGE_ALL_TEXTURES_APPLIED"] = "Texture applied to all bar components."
--[[Translation missing --]]
L["CHANGE_ALL_TEXTURES_APPLY"] = "Apply to All"
--[[Translation missing --]]
L["CHANGE_ALL_TEXTURES_APPLY_DESC"] = "Overwrite every bar texture (cast bars, resources, health) with the selected texture."
--[[Translation missing --]]
L["CHANGE_ALL_TEXTURES_HEADER"] = "Change All Textures"
--[[Translation missing --]]
L["CLASS_DEATHKNIGHT"] = "Death Knight"
--[[Translation missing --]]
L["CLASS_DEATHKNIGHT_DESC"] = "Custom color for Death Knight secondary resources."
--[[Translation missing --]]
L["CLASS_DRUID"] = "Druid"
--[[Translation missing --]]
L["CLASS_DRUID_DESC"] = "Custom color for Druid secondary resources."
--[[Translation missing --]]
L["CLASS_EVOKER"] = "Evoker"
--[[Translation missing --]]
L["CLASS_EVOKER_DESC"] = "Custom color for Evoker secondary resources."
--[[Translation missing --]]
L["CLASS_MAGE"] = "Mage"
--[[Translation missing --]]
L["CLASS_MAGE_DESC"] = "Custom color for Mage secondary resources."
--[[Translation missing --]]
L["CLASS_MONK"] = "Monk"
--[[Translation missing --]]
L["CLASS_MONK_DESC"] = "Custom color for Monk secondary resources."
--[[Translation missing --]]
L["CLASS_PALADIN"] = "Paladin"
--[[Translation missing --]]
L["CLASS_PALADIN_DESC"] = "Custom color for Paladin secondary resources."
--[[Translation missing --]]
L["CLASS_ROGUE"] = "Rogue"
--[[Translation missing --]]
L["CLASS_ROGUE_DESC"] = "Custom color for Rogue secondary resources."
--[[Translation missing --]]
L["CLASS_TWEAKS_HEADER"] = "Class Specific Tweaks"
--[[Translation missing --]]
L["CLASS_WARLOCK"] = "Warlock"
--[[Translation missing --]]
L["CLASS_WARLOCK_DESC"] = "Custom color for Warlock secondary resources."
--[[Translation missing --]]
L["COLOR_BACKGROUND"] = "Background"
--[[Translation missing --]]
L["COLOR_BACKGROUND_DESC"] = "The background color behind the cast bar."
--[[Translation missing --]]
L["COLOR_BACKGROUND_TEXTURE"] = "Background Texture"
--[[Translation missing --]]
L["COLOR_BACKGROUND_TEXTURE_DESC"] = "Select a statusbar texture for the cast bar background. Default uses a solid color."
--[[Translation missing --]]
L["COLOR_CASTING"] = "Casting"
--[[Translation missing --]]
L["COLOR_CASTING_DESC"] = "The bar color while a spell is being cast."
--[[Translation missing --]]
L["COLOR_CHANNELING"] = "Channeling"
--[[Translation missing --]]
L["COLOR_CHANNELING_DESC"] = "The bar color while a spell is being channeled."
--[[Translation missing --]]
L["COLOR_EMPOWERED"] = "Empowered"
--[[Translation missing --]]
L["COLOR_EMPOWERED_DESC"] = "The bar color for empowered (hold-to-cast) spells."
--[[Translation missing --]]
L["COLOR_FINISHED"] = "Finished"
--[[Translation missing --]]
L["COLOR_FINISHED_DESC"] = "The bar color when a cast finishes successfully."
--[[Translation missing --]]
L["COLOR_IMPORTANT"] = "Important"
--[[Translation missing --]]
L["COLOR_IMPORTANT_DESC"] = "The bar color for important spells."
--[[Translation missing --]]
L["COLOR_INSTANT_CAST"] = "Instant Cast Bar"
--[[Translation missing --]]
L["COLOR_INSTANT_CAST_DESC"] = "Bar color shown when displaying the global cooldown after an instant-cast spell."
--[[Translation missing --]]
L["COLOR_INTERRUPTED"] = "Interrupted"
--[[Translation missing --]]
L["COLOR_INTERRUPTED_DESC"] = "The bar color when a cast is interrupted."
--[[Translation missing --]]
L["COLOR_MODE_CLASS"] = "Class Color"
--[[Translation missing --]]
L["COLOR_MODE_GRADIENT"] = "Health Gradient"
--[[Translation missing --]]
L["COLOR_NON_INTERRUPTIBLE"] = "Non-Interruptible"
--[[Translation missing --]]
L["COLOR_NON_INTERRUPTIBLE_DESC"] = "The bar color for casts that cannot be interrupted."
--[[Translation missing --]]
L["COLOR_USE_CLASS_COLOR"] = "Use Class Color"
--[[Translation missing --]]
L["COLOR_USE_CLASS_COLOR_DESC"] = "Override the casting and channeling bar colors with your class color. Applies to the player cast bar only."
--[[Translation missing --]]
L["COLORS_TAB_DESCRIPTION"] = "Customize colors for cast bars, health bars, resource bars, and borders."
--[[Translation missing --]]
L["COMP_BUFF_TRACKER"] = "Buff Tracker"
--[[Translation missing --]]
L["COMP_BUFF_TRACKER_BARS"] = "Buff Tracker Bars"
--[[Translation missing --]]
L["COMP_CONSUMABLE_BUFF_TRACKER"] = "Consumable Buff Tracker"
--[[Translation missing --]]
L["COMP_CONSUMABLE_TRACKER"] = "Consumable Tracker"
--[[Translation missing --]]
L["COMP_COOLDOWN_TRACKER"] = "Cooldown Tracker"
--[[Translation missing --]]
L["COMP_FOCUS_CAST_BAR"] = "Focus Cast Bar"
--[[Translation missing --]]
L["COMP_GLOBAL_COOLDOWN"] = "Global Cooldown"
--[[Translation missing --]]
L["COMP_OUTBOUND_BUFF_TRACKER"] = "Outbound Buff Tracker"
--[[Translation missing --]]
L["COMP_PLAYER_CAST_BAR"] = "Player Cast Bar"
--[[Translation missing --]]
L["COMP_PLAYER_HEALTH_BAR"] = "Player Health Bar"
--[[Translation missing --]]
L["COMP_PRIMARY_RESOURCES"] = "Primary Resources"
--[[Translation missing --]]
L["COMP_RACIAL_TRACKER"] = "Racial Tracker"
--[[Translation missing --]]
L["COMP_RAID_BUFF_TRACKER"] = "Raid Buff Tracker"
--[[Translation missing --]]
L["COMP_SECONDARY_RESOURCES"] = "Secondary Resources"
--[[Translation missing --]]
L["COMP_TARGET_CAST_BAR"] = "Target Cast Bar"
--[[Translation missing --]]
L["COMP_TRINKET_TRACKER"] = "Trinket Tracker"
--[[Translation missing --]]
L["COMP_UTILITIES_TRACKER"] = "Utilities Tracker"
--[[Translation missing --]]
L["COMPONENT_BG_BORDER_COLOR"] = "Border Color"
--[[Translation missing --]]
L["COMPONENT_BG_BORDER_COLOR_DESC"] = "Color of the border outline."
--[[Translation missing --]]
L["COMPONENT_BG_BORDER_STYLE"] = "Background Style"
--[[Translation missing --]]
L["COMPONENT_BG_BORDER_STYLE_DESC"] = "Style of the background panel."
--[[Translation missing --]]
L["COMPONENT_BG_COLOR"] = "Background Color"
--[[Translation missing --]]
L["COMPONENT_BG_COLOR_DESC"] = "Fill color for the background panel."
--[[Translation missing --]]
L["COMPONENT_BG_ENABLED"] = "Show Background"
--[[Translation missing --]]
L["COMPONENT_BG_ENABLED_DESC"] = "Show a colored background panel behind this component."
--[[Translation missing --]]
L["COMPONENT_BG_HEADER"] = "Background"
--[[Translation missing --]]
L["COMPONENT_BG_PADDING_H"] = "Horizontal Padding"
--[[Translation missing --]]
L["COMPONENT_BG_PADDING_H_DESC"] = "How far the background extends beyond the component on the left and right."
--[[Translation missing --]]
L["COMPONENT_BG_PADDING_V"] = "Vertical Padding"
--[[Translation missing --]]
L["COMPONENT_BG_PADDING_V_DESC"] = "How far the background extends beyond the component on the top and bottom."
--[[Translation missing --]]
L["COMPONENT_BG_ROUNDED"] = "Rounded Corners"
--[[Translation missing --]]
L["COMPONENT_BG_ROUNDED_DESC"] = "Use rounded corners on the background instead of sharp edges."
--[[Translation missing --]]
L["COMPONENT_BG_ROUNDNESS"] = "Roundness"
--[[Translation missing --]]
L["COMPONENT_BG_ROUNDNESS_DESC"] = "How rounded the corners are. Higher values are more rounded."
--[[Translation missing --]]
L["CONFIRM_IMPORT"] = "Confirm Import"
--[[Translation missing --]]
L["CONSUMABLE_CAT_COMBAT"] = "Combat Potions"
--[[Translation missing --]]
L["CONSUMABLE_CAT_HEALTH"] = "Health Potions"
--[[Translation missing --]]
L["CONSUMABLE_CAT_HEALTHSTONE"] = "Healthstones"
--[[Translation missing --]]
L["CONSUMABLE_CAT_MANA"] = "Mana Potions"
--[[Translation missing --]]
L["CONSUMABLE_CAT_UTILITY"] = "Utility"
--[[Translation missing --]]
L["COOLDOWN_MANAGER_SETTINGS"] = "Cooldown Manager Settings"
--[[Translation missing --]]
L["CREATE_BAR_FRAME"] = "+ Bar"
--[[Translation missing --]]
L["CREATE_BUFFS_FRAME"] = "+ Buffs"
--[[Translation missing --]]
L["CREATE_SPELLS_FRAME"] = "+ Spells"
--[[Translation missing --]]
L["CUSTOM_SPELLS_INVALID_ID"] = "Invalid or unknown spell ID."
--[[Translation missing --]]
L["CUSTOM_SPELLS_USABLE_ONLY"] = "Only When Usable"
--[[Translation missing --]]
L["CUSTOM_SPELLS_USABLE_ONLY_DESC"] = "Hide this entry on characters that cannot cast the spell (not in the current spellbook/spec). On by default; turn off for item-cast spells like Hearthstone."
--[[Translation missing --]]
L["DEBUG_ENABLED"] = "Debug Mode"
--[[Translation missing --]]
L["DEBUG_ENABLED_DESC"] = [=[Print internal diagnostic messages to chat.
Useful when reporting issues or troubleshooting behavior.
Can also be toggled with /cue debug.]=]
--[[Translation missing --]]
L["DEBUG_HEADER"] = "Debug"
--[[Translation missing --]]
L["DEBUG_OFF"] = "OFF"
--[[Translation missing --]]
L["DEBUG_ON"] = "ON"
--[[Translation missing --]]
L["DEBUG_TOGGLED"] = "Debug mode:"
--[[Translation missing --]]
L["DEFAULT_PROFILE_NAME"] = "imported"
--[[Translation missing --]]
L["DELETE_FRAME"] = "Delete"
--[[Translation missing --]]
L["DELETE_FRAME_CONFIRM"] = [=[Delete additional frame '%s'?

Assigned spells will return to their original trackers.]=]
--[[Translation missing --]]
L["DETACH_ON_DRAG"] = "%s detached from anchor."
--[[Translation missing --]]
L["DISABLED_OPTION"] = "<Disabled>"
--[[Translation missing --]]
L["DRUID_MANA_BAR"] = "Show Mana for Guardian"
--[[Translation missing --]]
L["DRUID_MANA_BAR_DESC"] = "Show the mana bar for Guardian Druids even when Auto-Hide is enabled."
--[[Translation missing --]]
L["EDITMODE_FRAME_VISIBILITY"] = "ClassUIEnhanced Visibility"
--[[Translation missing --]]
L["EDITMODE_FRAME_VISIBILITY_DESC"] = "Controls which frames are visible during Edit Mode. This does not disable any trackers."
--[[Translation missing --]]
L["EDITMODE_VIS_HIDE_ALL"] = "Hide All"
--[[Translation missing --]]
L["EDITMODE_VIS_SHOW_ALL"] = "Show All"
--[[Translation missing --]]
L["EVOKER_MANA_BAR"] = "Show Mana for Devastation"
--[[Translation missing --]]
L["EVOKER_MANA_BAR_DESC"] = "Show the mana bar for Devastation Evokers even when Auto-Hide is enabled."
--[[Translation missing --]]
L["EXPORT_BUTTON"] = "Export"
--[[Translation missing --]]
L["EXPORT_SEGMENTS_LABEL"] = "What to export:"
--[[Translation missing --]]
L["FILL_DIRECTION_LEFT"] = "Right to Left"
--[[Translation missing --]]
L["FILL_DIRECTION_RIGHT"] = "Left to Right"
--[[Translation missing --]]
L["FIVE_SECOND_RULE_SIZE_BOTTOM"] = "Bottom Third"
--[[Translation missing --]]
L["FIVE_SECOND_RULE_SIZE_FULL"] = "Full Height"
--[[Translation missing --]]
L["FIVE_SECOND_RULE_SIZE_TOP"] = "Top Third"
--[[Translation missing --]]
L["FRAME_NAME_LABEL"] = "Frame Name"
--[[Translation missing --]]
L["FRAME_STRATA_INHERIT"] = "Inherit"
--[[Translation missing --]]
L["FRAME_TYPE_LABEL"] = "Type: %s"
--[[Translation missing --]]
L["GENERAL_TAB_DESCRIPTION"] = "Most component settings - size, position, anchoring, and visual options - are configured directly through WoW's Edit Mode. Select any component in Edit Mode to access its settings. This panel contains global settings that apply across all components."
--[[Translation missing --]]
L["GLOW_HEADER_ACTIVE"] = "Active Buff"
--[[Translation missing --]]
L["GLOW_HEADER_ACTIVE_AURA"] = "Active Aura Glow"
--[[Translation missing --]]
L["GLOW_HEADER_APPROACHING"] = "Approaching"
--[[Translation missing --]]
L["GLOW_HEADER_EXPIRING"] = "Expiring Buff"
--[[Translation missing --]]
L["GLOW_HEADER_FLASH"] = "Flash"
--[[Translation missing --]]
L["GLOW_HEADER_MISSING"] = "Missing Buff"
--[[Translation missing --]]
L["GLOW_HEADER_PANDEMIC"] = "Pandemic Glow"
--[[Translation missing --]]
L["GLOW_HEADER_PULSE"] = "Pulse"
--[[Translation missing --]]
L["HEALTH_GRADIENT_COLORS_HEADER"] = "Health Bar Gradient"
--[[Translation missing --]]
L["HEALTH_GRADIENT_FULL"] = "Full Health"
--[[Translation missing --]]
L["HEALTH_GRADIENT_FULL_DESC"] = "Color at 100% health."
--[[Translation missing --]]
L["HEALTH_GRADIENT_LOW"] = "Low Health"
--[[Translation missing --]]
L["HEALTH_GRADIENT_LOW_DESC"] = "Color at 0% health."
--[[Translation missing --]]
L["HEALTH_GRADIENT_MID"] = "Half Health"
--[[Translation missing --]]
L["HEALTH_GRADIENT_MID_DESC"] = "Color at 50% health."
--[[Translation missing --]]
L["ICON_ASPECT_RATIO"] = "Preserve Aspect Ratio"
--[[Translation missing --]]
L["ICON_ASPECT_RATIO_DESC"] = "Keep the original square proportions of icon textures when an icon is stretched to a non-square shape, cropping excess instead of distorting."
--[[Translation missing --]]
L["ICON_BORDER_COLOR"] = "Border Color"
--[[Translation missing --]]
L["ICON_BORDER_COLOR_DESC"] = "Color of the border around tracker icons."
--[[Translation missing --]]
L["ICON_BORDER_ENABLED"] = "Show Border"
--[[Translation missing --]]
L["ICON_BORDER_ENABLED_DESC"] = "Show a thin border around tracker icons (cooldowns, buffs, trinkets, consumables)."
--[[Translation missing --]]
L["ICON_BORDER_HEADER"] = "Icon Borders"
--[[Translation missing --]]
L["ICON_BORDER_INSIDE"] = "Inside Border"
--[[Translation missing --]]
L["ICON_BORDER_INSIDE_DESC"] = "Draw the border inside the icon instead of outside. Inside borders overlap the icon content."
--[[Translation missing --]]
L["ICON_ORDER_CATEGORY_1711"] = "Healthstone"
--[[Translation missing --]]
L["ICON_ORDER_CATEGORY_2566"] = "Demonic Healthstone"
--[[Translation missing --]]
L["ICON_ORDER_CATEGORY_30"] = "Health Potion"
--[[Translation missing --]]
L["ICON_ORDER_CATEGORY_4"] = "Combat Potion"
--[[Translation missing --]]
L["ICON_ORDER_CONSUMABLE"] = "Consumable"
--[[Translation missing --]]
L["ICON_ORDER_EMPTY"] = "Nothing tracked for this specialization."
--[[Translation missing --]]
L["ICON_ORDER_RESET"] = "Reset to default order"
--[[Translation missing --]]
L["ICON_ORDER_RESET_DESC"] = "Discard the arrangement for your current specialization. This tracker then follows the All specs arrangement, or the game's Cooldown Manager order if there is none. With All specs ticked, discard the All specs arrangement instead."
--[[Translation missing --]]
L["ICON_ORDER_TRINKET"] = "Trinket"
--[[Translation missing --]]
L["ICON_ORDER_UNTRACKED"] = "not tracked on this spec"
--[[Translation missing --]]
L["ICON_OVERRIDES_NO_RESULTS"] = "No matching icons found."
--[[Translation missing --]]
L["ICON_OVERRIDES_PICKER_SEARCH"] = "Search or enter icon ID/path..."
--[[Translation missing --]]
L["ICON_OVERRIDES_PICKER_TITLE"] = "Select Icon"
--[[Translation missing --]]
L["ICON_ZOOM_ENABLED"] = "Zoom Icons"
--[[Translation missing --]]
L["ICON_ZOOM_ENABLED_DESC"] = "Zoom in slightly on spell and item icons to crop the default border edge for a cleaner look."
--[[Translation missing --]]
L["ICON_ZOOM_HEADER"] = "Icon Appearance"
--[[Translation missing --]]
L["IMPORT_AS_NEW"] = "Import as new profile"
--[[Translation missing --]]
L["IMPORT_BUTTON"] = "Import"
--[[Translation missing --]]
L["IMPORT_EXPORT_STRING_LABEL"] = "Import / Export String:"
--[[Translation missing --]]
L["IMPORT_FAILED"] = "Import failed: %s"
--[[Translation missing --]]
L["IMPORT_INTO_CURRENT"] = "Import into current profile"
--[[Translation missing --]]
L["IMPORT_NO_SEGMENTS_SELECTED"] = "No segments selected for import."
--[[Translation missing --]]
L["IMPORT_SEGMENTS_LABEL"] = "Detected segments:"
--[[Translation missing --]]
L["IMPORT_SOURCE_INFO"] = "Source: %s (v%s, game %s)"
--[[Translation missing --]]
L["IMPORT_SOURCE_INFO_NO_VERSION"] = "Source: %s"
--[[Translation missing --]]
L["IMPORT_SOURCE_REVISION_ONLY"] = "Revision: %s"
--[[Translation missing --]]
L["ITEM_NOT_EQUIPPED"] = "(not equipped)"
--[[Translation missing --]]
L["LAYOUT_ALIGNMENT_BOTTOM"] = "Bottom"
--[[Translation missing --]]
L["LAYOUT_ALIGNMENT_CENTER"] = "Center"
--[[Translation missing --]]
L["LAYOUT_ALIGNMENT_LEFT"] = "Left"
--[[Translation missing --]]
L["LAYOUT_ALIGNMENT_RIGHT"] = "Right"
--[[Translation missing --]]
L["LAYOUT_ALIGNMENT_TOP"] = "Top"
--[[Translation missing --]]
L["LAYOUT_DIRECTION_HORIZONTAL"] = "Horizontal"
--[[Translation missing --]]
L["LAYOUT_DIRECTION_VERTICAL"] = "Vertical"
--[[Translation missing --]]
L["LAYOUT_SYNC_CLEAR"] = "Clear Stored Layouts"
--[[Translation missing --]]
L["LAYOUT_SYNC_CLEAR_CONFIRM"] = "Clear"
--[[Translation missing --]]
L["LAYOUT_SYNC_CLEAR_DESC"] = "Remove all stored Cooldown Manager layouts from the current profile."
--[[Translation missing --]]
L["LAYOUT_SYNC_CLEAR_PROMPT"] = [=[Clear all stored cooldown layouts?

You can also clear them later from the Options panel.]=]
--[[Translation missing --]]
L["LAYOUT_SYNC_ENABLED"] = "Layout Storage"
--[[Translation missing --]]
L["LAYOUT_SYNC_ENABLED_DESC"] = "Store and restore Cooldown Manager layouts per class across characters. Layouts are saved when you close the CDM settings window or click Save below."
--[[Translation missing --]]
L["LAYOUT_SYNC_HEADER"] = "Cooldown Layout Sync"
--[[Translation missing --]]
L["LAYOUT_SYNC_KEEP"] = "Keep"
--[[Translation missing --]]
L["LAYOUT_SYNC_SAVE"] = "Save Current Layout"
--[[Translation missing --]]
L["LAYOUT_SYNC_SAVE_DESC"] = "Store the current Cooldown Manager layout for your class."
--[[Translation missing --]]
L["MINIMAP_HEADER"] = "Minimap"
--[[Translation missing --]]
L["MINIMAP_SHOW"] = "Show Minimap Icon"
--[[Translation missing --]]
L["MINIMAP_SHOW_DESC"] = [=[Show the ClassUIEnhanced minimap button.
This setting is shared across all profiles.]=]
--[[Translation missing --]]
L["MINIMAP_TOGGLED_OFF"] = "Minimap icon hidden. Use /cue minimap to show it again."
--[[Translation missing --]]
L["MINIMAP_TOGGLED_ON"] = "Minimap icon shown."
--[[Translation missing --]]
L["MOVE_DOWN"] = "Down"
--[[Translation missing --]]
L["MOVE_UP"] = "Up"
--[[Translation missing --]]
L["NEW_BAR_FRAME_NAME"] = "Bar Frame"
--[[Translation missing --]]
L["NEW_BUFFS_FRAME_NAME"] = "Buffs Frame"
--[[Translation missing --]]
L["NEW_SPELLS_FRAME_NAME"] = "Spells Frame"
--[[Translation missing --]]
L["NO_FRAMES_CREATED"] = [=[No additional frames created yet.
Use the buttons above to create one.]=]
--[[Translation missing --]]
L["OPEN_COMPONENT_SETTINGS"] = "Component Settings"
--[[Translation missing --]]
L["OPEN_EDIT_MODE"] = "Open Edit Mode"
--[[Translation missing --]]
L["OPTIONS_PANEL_RESET"] = "Options panel scale and position reset."
--[[Translation missing --]]
L["OPTIONS_TITLE"] = "ClassUIEnhanced Options"
--[[Translation missing --]]
L["OVERFLOW_LEFT"] = "Left"
--[[Translation missing --]]
L["OVERFLOW_RIGHT"] = "Right"
--[[Translation missing --]]
L["PALADIN_MANA_BAR"] = "Show Mana for Paladin"
--[[Translation missing --]]
L["PALADIN_MANA_BAR_DESC"] = "Show the mana bar for Protection and Retribution Paladins even when Auto-Hide is enabled. Useful for tracking mana for self-healing."
--[[Translation missing --]]
L["PANDEMIC_STYLE_BORDER"] = "Solid Border (Outside)"
--[[Translation missing --]]
L["PANDEMIC_STYLE_BORDER_INSIDE"] = "Solid Border (Inside)"
--[[Translation missing --]]
L["PARTIAL_IMPORT_APPLIED"] = "Imported %d segment(s) into profile '%s'."
--[[Translation missing --]]
L["PARTY_CORNERS"] = "Rounded Corners"
--[[Translation missing --]]
L["PARTY_CORNERS_ALL"] = "All"
--[[Translation missing --]]
L["PARTY_CORNERS_BL"] = "Bottom-Left Only"
--[[Translation missing --]]
L["PARTY_CORNERS_BOTTOM"] = "Bottom"
--[[Translation missing --]]
L["PARTY_CORNERS_BR"] = "Bottom-Right Only"
--[[Translation missing --]]
L["PARTY_CORNERS_DESC"] = "Which corners of the Party border are rounded."
--[[Translation missing --]]
L["PARTY_CORNERS_LEFT"] = "Left"
--[[Translation missing --]]
L["PARTY_CORNERS_RIGHT"] = "Right"
--[[Translation missing --]]
L["PARTY_CORNERS_TL"] = "Top-Left Only"
--[[Translation missing --]]
L["PARTY_CORNERS_TOP"] = "Top"
--[[Translation missing --]]
L["PARTY_CORNERS_TR"] = "Top-Right Only"
--[[Translation missing --]]
L["POWER_ENERGY"] = "Energy"
--[[Translation missing --]]
L["POWER_ENERGY_DESC"] = "Custom color for the energy resource bar."
--[[Translation missing --]]
L["POWER_FOCUS"] = "Focus"
--[[Translation missing --]]
L["POWER_FOCUS_DESC"] = "Custom color for the focus resource bar."
--[[Translation missing --]]
L["POWER_FURY"] = "Fury"
--[[Translation missing --]]
L["POWER_FURY_DESC"] = "Custom color for the fury resource bar."
--[[Translation missing --]]
L["POWER_INSANITY"] = "Insanity"
--[[Translation missing --]]
L["POWER_INSANITY_DESC"] = "Custom color for the insanity resource bar."
--[[Translation missing --]]
L["POWER_LUNAR_POWER"] = "Lunar Power"
--[[Translation missing --]]
L["POWER_LUNAR_POWER_DESC"] = "Custom color for the lunar power resource bar."
--[[Translation missing --]]
L["POWER_MAELSTROM"] = "Maelstrom"
--[[Translation missing --]]
L["POWER_MAELSTROM_DESC"] = "Custom color for the maelstrom resource bar."
--[[Translation missing --]]
L["POWER_MANA"] = "Mana"
--[[Translation missing --]]
L["POWER_MANA_DESC"] = "Custom color for the mana resource bar."
--[[Translation missing --]]
L["POWER_PAIN"] = "Pain"
--[[Translation missing --]]
L["POWER_PAIN_DESC"] = "Custom color for the pain resource bar."
--[[Translation missing --]]
L["POWER_RAGE"] = "Rage"
--[[Translation missing --]]
L["POWER_RAGE_DESC"] = "Custom color for the rage resource bar."
--[[Translation missing --]]
L["POWER_RUNIC_POWER"] = "Runic Power"
--[[Translation missing --]]
L["POWER_RUNIC_POWER_DESC"] = "Custom color for the runic power resource bar."
--[[Translation missing --]]
L["PRIEST_MANA_BAR"] = "Show Mana for Shadow"
--[[Translation missing --]]
L["PRIEST_MANA_BAR_DESC"] = "Show the mana bar for Shadow Priests even when Auto-Hide is enabled. Insanity is shown on the Secondary Resources bar."
--[[Translation missing --]]
L["PRIMARY_OVERRIDE_COLOR"] = "Use Default Power Colors"
--[[Translation missing --]]
L["PRIMARY_OVERRIDE_COLOR_DESC"] = "When enabled, uses the default power type colors for the resource bar. Disable to set custom colors per resource type."
--[[Translation missing --]]
L["PRIMARY_RESOURCE_HEADER"] = "Primary Resource"
--[[Translation missing --]]
L["PROC_GLOW_ALPHA"] = "Glow Opacity"
--[[Translation missing --]]
L["PROC_GLOW_ALPHA_DESC"] = "Opacity of the proc glow (0 = invisible, 100 = full)."
--[[Translation missing --]]
L["PROC_GLOW_COLOR"] = "Glow Color"
--[[Translation missing --]]
L["PROC_GLOW_COLOR_DESC"] = "Color tint for the proc glow."
--[[Translation missing --]]
L["PROC_GLOW_HEADER"] = "Proc Glow"
--[[Translation missing --]]
L["PROC_GLOW_STYLE"] = "Glow Style"
--[[Translation missing --]]
L["PROC_GLOW_STYLE_DESC"] = "Choose how proc glows are drawn on tracker icons."
--[[Translation missing --]]
L["PROC_GLOW_THICKNESS"] = "Border Thickness"
--[[Translation missing --]]
L["PROC_GLOW_THICKNESS_DESC"] = "Pixel thickness of the Solid Border proc glow styles (1-6)."
--[[Translation missing --]]
L["PROC_STYLE_ANTS"] = "Marching Ants"
--[[Translation missing --]]
L["PROC_STYLE_AUTOCAST"] = "Autocast Shine"
--[[Translation missing --]]
L["PROC_STYLE_BLIZZARD"] = "Blizzard (Proc)"
--[[Translation missing --]]
L["PROC_STYLE_BORDER"] = "Solid Border (Outside)"
--[[Translation missing --]]
L["PROC_STYLE_BORDER_INSIDE"] = "Solid Border (Inside)"
--[[Translation missing --]]
L["PROC_STYLE_NONE"] = "Hidden"
--[[Translation missing --]]
L["PROC_STYLE_PIXEL"] = "Pixel Lines"
--[[Translation missing --]]
L["PROFILE_COPY_CONFIRM"] = "Overwrite the profile \"%s\" with the settings of \"%s\"? This cannot be undone."
--[[Translation missing --]]
L["PROFILE_NAME_LABEL"] = "Profile Name (for import):"
--[[Translation missing --]]
L["PROFILE_RESET_CONFIRM"] = "Reset the profile \"%s\" to its defaults? This cannot be undone."
--[[Translation missing --]]
L["PROFILE_SOURCE_LABEL"] = "Profile source:"
--[[Translation missing --]]
L["PROFILE_SWITCH_DEFERRED_COMBAT"] = "Profile applied. Frames that are locked during combat will finish updating when you leave combat."
--[[Translation missing --]]
L["RAID_BUFF_ARCANE_INTELLECT"] = "Arcane Intellect"
--[[Translation missing --]]
L["RAID_BUFF_BATTLE_SHOUT"] = "Battle Shout"
--[[Translation missing --]]
L["RAID_BUFF_BLESSING_OF_KINGS"] = "Blessing of Kings"
--[[Translation missing --]]
L["RAID_BUFF_BLESSING_OF_MIGHT"] = "Blessing of Might"
--[[Translation missing --]]
L["RAID_BUFF_BLESSING_OF_THE_BRONZE"] = "Blessing of the Bronze"
--[[Translation missing --]]
L["RAID_BUFF_COMMANDING_SHOUT"] = "Commanding Shout"
--[[Translation missing --]]
L["RAID_BUFF_DARK_INTENT"] = "Dark Intent"
--[[Translation missing --]]
L["RAID_BUFF_FORTITUDE"] = "Power Word: Fortitude"
--[[Translation missing --]]
L["RAID_BUFF_HORN_OF_WINTER"] = "Horn of Winter"
--[[Translation missing --]]
L["RAID_BUFF_LEGACY_OF_THE_EMPEROR"] = "Legacy of the Emperor"
--[[Translation missing --]]
L["RAID_BUFF_LEGACY_OF_THE_WHITE_TIGER"] = "Legacy of the White Tiger"
--[[Translation missing --]]
L["RAID_BUFF_MARK_OF_THE_WILD"] = "Mark of the Wild"
--[[Translation missing --]]
L["RAID_BUFF_SKYFURY"] = "Skyfury"
--[[Translation missing --]]
L["RESOURCE_COLORS_HEADER"] = "Secondary Resource Colors"
--[[Translation missing --]]
L["RESOURCE_CUSTOM_COLORS_HEADER"] = "Special Secondary Colors"
--[[Translation missing --]]
L["SECTION_ANCHORING"] = "Anchoring and Size"
--[[Translation missing --]]
L["SECTION_BAR_LAYOUT"] = "Bar Layout"
--[[Translation missing --]]
L["SECTION_CLASS_FEATURES"] = "Class Features"
--[[Translation missing --]]
L["SECTION_EXCLUDED_TRINKETS"] = "Excluded Trinkets"
--[[Translation missing --]]
L["SECTION_FEATURES"] = "Features"
--[[Translation missing --]]
L["SECTION_FONTS"] = "Fonts"
--[[Translation missing --]]
L["SECTION_GLOW_EFFECTS"] = "Glow Effects"
--[[Translation missing --]]
L["SECTION_ICON_LAYOUT"] = "Icon Layout"
--[[Translation missing --]]
L["SECTION_LAYOUT_SETTINGS"] = "Layout Settings"
--[[Translation missing --]]
L["SECTION_OUTBOUND_DISPLAY"] = "Display"
--[[Translation missing --]]
L["SECTION_OUTBOUND_FILTERING"] = "Filtering & Sort"
--[[Translation missing --]]
L["SECTION_SLOT_SELECTION"] = "Slot Selection"
--[[Translation missing --]]
L["SECTION_TEXT_DISPLAY"] = "Text Display"
--[[Translation missing --]]
L["SECTION_TEXTURE"] = "Texture"
--[[Translation missing --]]
L["SECTION_TOOLTIP"] = "Tooltip"
--[[Translation missing --]]
L["SECTION_TRACKED_ITEMS"] = "Tracked Items"
--[[Translation missing --]]
L["SECTION_TRACKED_RACIALS"] = "Tracked Racials"
--[[Translation missing --]]
L["SECTION_VISIBILITY"] = "Visibility"
--[[Translation missing --]]
L["SEGMENT_ADDITIONAL_FRAMES"] = "Additional Frames"
--[[Translation missing --]]
L["SEGMENT_ADDITIONAL_FRAMES_DESC"] = "User-created additional frames with their assigned spells and visual settings."
--[[Translation missing --]]
L["SEGMENT_BREAKPOINT_PIPS"] = "Breakpoint Pips"
--[[Translation missing --]]
L["SEGMENT_BREAKPOINT_PIPS_DESC"] = "Per-specialization breakpoint pip markers on the primary resource bar."
--[[Translation missing --]]
L["SEGMENT_BUFF_TRACKER"] = "Buff Tracker"
--[[Translation missing --]]
L["SEGMENT_BUFF_TRACKER_BARS"] = "Buff Tracker Bars"
--[[Translation missing --]]
L["SEGMENT_BUFF_TRACKER_BARS_DESC"] = "Visual settings for the Buff Tracker Bars (bar width, icon size, growth direction, fonts)."
--[[Translation missing --]]
L["SEGMENT_BUFF_TRACKER_DESC"] = "Visual settings for the Buff Tracker (icon size, overflow, spacing)."
--[[Translation missing --]]
L["SEGMENT_CASTBAR_COLORS"] = "Castbar Colors"
--[[Translation missing --]]
L["SEGMENT_CASTBAR_COLORS_DESC"] = "Colors for casting, channeling, finished, interrupted, and empowered cast bar states."
--[[Translation missing --]]
L["SEGMENT_CONSUMABLE_BUFF_TRACKER"] = "Consumable Buff Tracker"
--[[Translation missing --]]
L["SEGMENT_CONSUMABLE_BUFF_TRACKER_DESC"] = "Settings for the Consumable Buff Tracker (flask, food, rune, oil, weapon buff status)."
--[[Translation missing --]]
L["SEGMENT_CONSUMABLE_TRACKER"] = "Consumable Tracker"
--[[Translation missing --]]
L["SEGMENT_CONSUMABLE_TRACKER_DESC"] = "Visual settings for the Consumable Tracker (layout, tracked items)."
--[[Translation missing --]]
L["SEGMENT_COOLDOWN_LAYOUT_SYNC"] = "Blizzard CDM Class Profiles"
--[[Translation missing --]]
L["SEGMENT_COOLDOWN_LAYOUT_SYNC_DESC"] = "Stored per-class Blizzard Cooldown Manager layouts for automatic restore on login."
--[[Translation missing --]]
L["SEGMENT_COOLDOWN_TRACKER"] = "Cooldown Tracker"
--[[Translation missing --]]
L["SEGMENT_COOLDOWN_TRACKER_DESC"] = "Visual settings for the Cooldown Tracker (icon size, overflow, spacing)."
--[[Translation missing --]]
L["SEGMENT_FOCUS_CAST_BAR"] = "Focus Cast Bar"
--[[Translation missing --]]
L["SEGMENT_FOCUS_CAST_BAR_DESC"] = "Visual settings for the Focus Cast Bar (texture, fonts)."
--[[Translation missing --]]
L["SEGMENT_GENERAL"] = "General"
--[[Translation missing --]]
L["SEGMENT_GENERAL_DESC"] = "Auto-hide, Arcane mana bar, and other general preferences."
--[[Translation missing --]]
L["SEGMENT_GLOBAL_COOLDOWN"] = "Global Cooldown"
--[[Translation missing --]]
L["SEGMENT_GLOBAL_COOLDOWN_DESC"] = "Visual settings for the Global Cooldown bar (texture, colors)."
--[[Translation missing --]]
L["SEGMENT_GROUP_COMPONENTS"] = "Components"
--[[Translation missing --]]
L["SEGMENT_GROUP_GENERAL"] = "General Settings"
--[[Translation missing --]]
L["SEGMENT_GROUP_POSITIONING"] = "Positioning"
--[[Translation missing --]]
L["SEGMENT_HEALTH_GRADIENT_COLORS"] = "Health Gradient Colors"
--[[Translation missing --]]
L["SEGMENT_HEALTH_GRADIENT_COLORS_DESC"] = "Custom colors for the health bar gradient (low, mid, full health thresholds)."
--[[Translation missing --]]
L["SEGMENT_ICON_OVERRIDES"] = "Icon Overrides"
--[[Translation missing --]]
L["SEGMENT_ICON_OVERRIDES_DESC"] = "Custom icon textures for specific spells, applied across all trackers."
--[[Translation missing --]]
L["SEGMENT_LAYOUT"] = "Layout"
--[[Translation missing --]]
L["SEGMENT_LAYOUT_DESC"] = "Layout, positioning, anchoring, and sizing of all components."
--[[Translation missing --]]
L["SEGMENT_OUTBOUND_BUFF_TRACKER"] = "Outbound Buff Tracker"
--[[Translation missing --]]
L["SEGMENT_OUTBOUND_BUFF_TRACKER_DESC"] = "Settings for the Outbound Buff Tracker (buffs you applied on party/raid members, e.g. Prescience)."
--[[Translation missing --]]
L["SEGMENT_PLAYER_CAST_BAR"] = "Player Cast Bar"
--[[Translation missing --]]
L["SEGMENT_PLAYER_CAST_BAR_DESC"] = "Visual settings for the Player Cast Bar (texture, fonts)."
--[[Translation missing --]]
L["SEGMENT_PLAYER_HEALTH_BAR"] = "Player Health Bar"
--[[Translation missing --]]
L["SEGMENT_PLAYER_HEALTH_BAR_DESC"] = "Visual settings for the Player Health Bar (color mode, text format, fonts)."
--[[Translation missing --]]
L["SEGMENT_PRIMARY_RESOURCES"] = "Primary Resources"
--[[Translation missing --]]
L["SEGMENT_PRIMARY_RESOURCES_DESC"] = "Visual settings for the Primary Resources bar."
--[[Translation missing --]]
L["SEGMENT_RACIAL_TRACKER"] = "Racial Tracker"
--[[Translation missing --]]
L["SEGMENT_RACIAL_TRACKER_DESC"] = "Visual settings for the Racial Tracker (layout, icon size)."
--[[Translation missing --]]
L["SEGMENT_RAID_BUFF_TRACKER"] = "Raid Buff Tracker"
--[[Translation missing --]]
L["SEGMENT_RAID_BUFF_TRACKER_DESC"] = "Settings for the Raid Buff Tracker (class raid buff status)."
--[[Translation missing --]]
L["SEGMENT_RESOURCE_COLORS"] = "Resource Colors"
--[[Translation missing --]]
L["SEGMENT_RESOURCE_COLORS_DESC"] = "Custom class colors for secondary resource indicators."
--[[Translation missing --]]
L["SEGMENT_SECONDARY_RESOURCES"] = "Secondary Resources"
--[[Translation missing --]]
L["SEGMENT_SECONDARY_RESOURCES_DESC"] = "Visual settings for the Secondary Resources bar."
--[[Translation missing --]]
L["SEGMENT_SPELL_ALERTS"] = "Spell Alerts"
--[[Translation missing --]]
L["SEGMENT_SPELL_ALERTS_DESC"] = "The alerts you set for specific spells in the Tracking tab."
--[[Translation missing --]]
L["SEGMENT_TARGET_CAST_BAR"] = "Target Cast Bar"
--[[Translation missing --]]
L["SEGMENT_TARGET_CAST_BAR_DESC"] = "Visual settings for the Target Cast Bar (texture, fonts)."
--[[Translation missing --]]
L["SEGMENT_TRACKING_OVERRIDES"] = "Tracking Overrides"
--[[Translation missing --]]
L["SEGMENT_TRACKING_OVERRIDES_DESC"] = "Which of this addon's trackers each Cooldown Manager spell appears in, or whether it is hidden. Blizzard's own Cooldown Manager layout is not changed."
--[[Translation missing --]]
L["SEGMENT_TRINKET_TRACKER"] = "Trinket Tracker"
--[[Translation missing --]]
L["SEGMENT_TRINKET_TRACKER_DESC"] = "Visual settings for the Trinket Tracker (layout, slot reservation)."
--[[Translation missing --]]
L["SEGMENT_UTILITIES_TRACKER"] = "Utilities Tracker"
--[[Translation missing --]]
L["SEGMENT_UTILITIES_TRACKER_DESC"] = "Visual settings for the Utilities Tracker (icon size, overflow, spacing)."
--[[Translation missing --]]
L["SELECT_ALL"] = "Select All"
--[[Translation missing --]]
L["SELECT_NONE"] = "Select None"
--[[Translation missing --]]
L["SETTING_ACTIVE_GLOW"] = "Active Aura Glow"
--[[Translation missing --]]
L["SETTING_ACTIVE_GLOW_COLOR"] = "Active Glow Color"
--[[Translation missing --]]
L["SETTING_ACTIVE_GLOW_COLOR_DESC"] = "Choose the color of the active aura glow effect."
--[[Translation missing --]]
L["SETTING_ACTIVE_GLOW_DESC"] = "Show a persistent glow on icons while their aura is active. When combined with Pandemic Glow, the color swaps to the pandemic color in the refresh window."
--[[Translation missing --]]
L["SETTING_ALWAYS_SHOW_TRACKED"] = "Always Show Tracked Auras"
--[[Translation missing --]]
L["SETTING_ALWAYS_SHOW_TRACKED_DESC"] = "Keep every tracked aura on screen in a fixed grid instead of only showing the active ones. Off shows only the active ones. Several options u2014 icon overrides, active aura glow, proc glow, per-spell colors, and the width and overflow layout modes u2014 only work while this is on."
--[[Translation missing --]]
L["SETTING_ANCHOR_FRAME"] = "Anchor Frame"
--[[Translation missing --]]
L["SETTING_ANCHOR_FRAME_DESC"] = [=[Choose which component this frame attaches to.
Select 'None (Free Moving)' to position it freely by dragging.]=]
--[[Translation missing --]]
L["SETTING_ANCHOR_OFFSET"] = "Anchor Offset"
--[[Translation missing --]]
L["SETTING_ANCHOR_OFFSET_X"] = "Offset X"
--[[Translation missing --]]
L["SETTING_ANCHOR_OFFSET_X_DESC"] = [=[Horizontal offset in pixels from the anchor point.
Positive moves right, negative moves left.]=]
--[[Translation missing --]]
L["SETTING_ANCHOR_OFFSET_Y"] = "Offset Y"
--[[Translation missing --]]
L["SETTING_ANCHOR_OFFSET_Y_DESC"] = [=[Vertical offset in pixels from the anchor point.
Positive moves up, negative moves down.]=]
--[[Translation missing --]]
L["SETTING_ANCHOR_POINT"] = "Anchor Point"
--[[Translation missing --]]
L["SETTING_ANCHOR_POINT_DESC"] = [=[Which point on the screen this frame is anchored to.
Changing this recalculates offsets so the frame stays in place.]=]
--[[Translation missing --]]
L["SETTING_ANCHOR_SIDE"] = "Anchor Side"
--[[Translation missing --]]
L["SETTING_ANCHOR_SIDE_DESC"] = "Which side of the anchor frame to attach to."
--[[Translation missing --]]
L["SETTING_ANCHORING"] = "Anchoring and Size"
--[[Translation missing --]]
L["SETTING_ARMS_SWEEPING_STRIKES"] = "Show Sweeping Strikes"
--[[Translation missing --]]
L["SETTING_ARMS_SWEEPING_STRIKES_COLOR"] = "Sweeping Strikes Color"
--[[Translation missing --]]
L["SETTING_ARMS_SWEEPING_STRIKES_COLOR_DESC"] = "Bar color for Sweeping Strikes stack segments."
--[[Translation missing --]]
L["SETTING_ARMS_SWEEPING_STRIKES_DESC"] = "Show Sweeping Strikes stack segments for Arms Warriors. Each single-target damaging ability consumes a stack to trigger an extra hit. 12 stacks base, 18 with the Improved Sweeping Strikes talent. Requires the Sweeping Strikes talent."
--[[Translation missing --]]
L["SETTING_BAR_COLLAPSE"] = "Collapse Width in Icon Only"
--[[Translation missing --]]
L["SETTING_BAR_COLLAPSE_DESC"] = [=[When enabled and Bar Content is 'Icon Only', the tracker width collapses to the icon size; children anchored to it reflow tighter.
Disabled (default): Icon Only keeps the configured Bar Width u2014 matches pre-update behavior.]=]
--[[Translation missing --]]
L["SETTING_BAR_COLOR"] = "Bar Color"
--[[Translation missing --]]
L["SETTING_BAR_COLOR_DESC"] = "Color of the GCD bar."
--[[Translation missing --]]
L["SETTING_BAR_CONTENT"] = "Bar Content"
--[[Translation missing --]]
L["SETTING_BAR_CONTENT_BAR_ONLY"] = "Bar Only"
--[[Translation missing --]]
L["SETTING_BAR_CONTENT_BAR_ONLY_NO_NAME"] = "Bar Only (No Name)"
--[[Translation missing --]]
L["SETTING_BAR_CONTENT_DESC"] = "Controls which elements are visible on each bar."
--[[Translation missing --]]
L["SETTING_BAR_CONTENT_ICON_AND_BAR"] = "Icon & Bar"
--[[Translation missing --]]
L["SETTING_BAR_CONTENT_ICON_AND_BAR_NO_NAME"] = "Icon & Bar (No Name)"
--[[Translation missing --]]
L["SETTING_BAR_CONTENT_ICON_ONLY"] = "Icon Only"
--[[Translation missing --]]
L["SETTING_BAR_FILL_COLOR"] = "Bar Fill Color"
--[[Translation missing --]]
L["SETTING_BAR_FILL_COLOR_DESC"] = "Color of the status bar fill."
--[[Translation missing --]]
L["SETTING_BAR_HEIGHT"] = "Bar Height"
--[[Translation missing --]]
L["SETTING_BAR_HEIGHT_DESC"] = "Height of each individual bar in pixels."
--[[Translation missing --]]
L["SETTING_BAR_ICON_OFFSET_DESC"] = "Spacing in pixels between the icon and the progress bar."
--[[Translation missing --]]
L["SETTING_BAR_ICON_OFFSET_X"] = "Icon X Offset"
--[[Translation missing --]]
L["SETTING_BAR_ICON_OFFSET_X_DESC"] = "Horizontal offset of the icon in pixels. Positive values move right."
--[[Translation missing --]]
L["SETTING_BAR_ICON_OFFSET_Y"] = "Icon Y Offset"
--[[Translation missing --]]
L["SETTING_BAR_ICON_OFFSET_Y_DESC"] = "Vertical offset of the icon in pixels. Positive values move up."
--[[Translation missing --]]
L["SETTING_BAR_LAYOUT"] = "Bar Layout"
--[[Translation missing --]]
L["SETTING_BAR_SIZE_FILL"] = "Fill Width"
--[[Translation missing --]]
L["SETTING_BAR_SIZE_FIXED"] = "Fixed Width"
--[[Translation missing --]]
L["SETTING_BAR_SIZE_MODE"] = "Size Mode"
--[[Translation missing --]]
L["SETTING_BAR_SIZE_MODE_DESC"] = [=[Choose how bar width is determined.
'Fixed Width' uses the Bar Width slider for each bar.
'Fill Width' stretches bars to fill the container width.]=]
--[[Translation missing --]]
L["SETTING_BAR_SMOOTHING"] = "Bar Smoothing"
--[[Translation missing --]]
L["SETTING_BAR_SMOOTHING_DESC"] = "Smoothly animate resource bar changes instead of snapping instantly."
--[[Translation missing --]]
L["SETTING_BAR_SPACING"] = "Bar Spacing"
--[[Translation missing --]]
L["SETTING_BAR_SPACING_DESC"] = "Gap between bars in pixels."
--[[Translation missing --]]
L["SETTING_BAR_WIDTH"] = "Bar Width"
--[[Translation missing --]]
L["SETTING_BAR_WIDTH_DESC"] = "Width of each individual bar in pixels."
--[[Translation missing --]]
L["SETTING_BLOCK_DIRECTION"] = "Block Direction"
--[[Translation missing --]]
L["SETTING_BLOCK_DIRECTION_DESC"] = "Arrange the block grid horizontally (rows, for top/bottom placement) or vertically (columns, for side placement)."
--[[Translation missing --]]
L["SETTING_BREWMASTER_STAGGER"] = "Show Stagger"
--[[Translation missing --]]
L["SETTING_BREWMASTER_STAGGER_DESC"] = "Show a Stagger bar for Brewmaster Monks, displaying the amount of damage currently being staggered."
--[[Translation missing --]]
L["SETTING_BREWMASTER_VITALITY"] = "Show Vitality (Brewmaster)"
--[[Translation missing --]]
L["SETTING_BREWMASTER_VITALITY_DESC"] = "Show a Vitality bar for Brewmaster Monks with the Aspect of Harmony hero talent, displaying stored vitality. Replaces the Stagger bar when enabled."
--[[Translation missing --]]
L["SETTING_BUILDER_PREDICTION"] = "Show Builder Prediction"
--[[Translation missing --]]
L["SETTING_BUILDER_PREDICTION_COLOR"] = "Builder Prediction Color"
--[[Translation missing --]]
L["SETTING_BUILDER_PREDICTION_COLOR_DESC"] = "Color used for the overlay showing predicted resource gain during a cast."
--[[Translation missing --]]
L["SETTING_BUILDER_PREDICTION_DESC"] = "Preview incoming resource on empty segments when casting a resource-generating spell."
--[[Translation missing --]]
L["SETTING_CAST_NAME_MAX_WIDTH"] = "Spell Name Max Width"
--[[Translation missing --]]
L["SETTING_CAST_NAME_MAX_WIDTH_DESC"] = "Limit the spell name text width to a percentage of the cast bar width. Long names will be truncated with an ellipsis. Set to 0 to disable the limit."
--[[Translation missing --]]
L["SETTING_CAST_NAME_TEXT"] = "Cast Name Text"
--[[Translation missing --]]
L["SETTING_CAST_TEXT_FORMAT"] = "Text Display"
--[[Translation missing --]]
L["SETTING_CAST_TEXT_FORMAT_DESC"] = "Choose what text to show on the cast bar."
--[[Translation missing --]]
L["SETTING_CAST_TEXTURE"] = "Cast Texture"
--[[Translation missing --]]
L["SETTING_CAST_TEXTURE_DESC"] = "Select a statusbar texture for the cast bar."
--[[Translation missing --]]
L["SETTING_CAST_TIME_STYLE"] = "Cast Time Style"
--[[Translation missing --]]
L["SETTING_CAST_TIME_STYLE_DESC"] = "Choose how the cast time is written. The total is the full cast or channel duration."
--[[Translation missing --]]
L["SETTING_CAST_TIME_TEXT"] = "Cast Time Text"
--[[Translation missing --]]
L["SETTING_CDM_GLOW_COLOR"] = "Ready Alert Color"
--[[Translation missing --]]
L["SETTING_CDM_GLOW_COLOR_DESC"] = "Color of Blizzard's cooldown-ready alert overlay (the brief glow/ants animation shown when a cooldown becomes available)."
--[[Translation missing --]]
L["SETTING_CHARGED_COMBO_COLOR"] = "Charged Combo Point Border"
--[[Translation missing --]]
L["SETTING_CHARGED_COMBO_COLOR_DESC"] = "Border color shown around charged (overloaded) combo points."
--[[Translation missing --]]
L["SETTING_CLICKABLE"] = "Clickable"
--[[Translation missing --]]
L["SETTING_CLICKABLE_DESC"] = "Allow clicking icons to use the corresponding consumable item."
--[[Translation missing --]]
L["SETTING_COLLAPSE_LAYOUT"] = "Mix Player and Target Auras (Experimental)"
--[[Translation missing --]]
L["SETTING_COLLAPSE_LAYOUT_DESC"] = "Show your buffs and your target's auras together in your Tracking order, instead of every target aura after your own. Everything stays on one line: the overflow and row layout options do not apply, and proc glow is not shown. Not available with Always Show Tracked Auras."
--[[Translation missing --]]
L["SETTING_COLOR_MODE"] = "Bar Color"
--[[Translation missing --]]
L["SETTING_COLOR_MODE_DESC"] = [=[Choose the health bar color style.
Class Color uses your class color.
Health Gradient transitions from green (full) through yellow (half) to red (low).]=]
--[[Translation missing --]]
L["SETTING_COUNT_TEXT"] = "Count Text"
--[[Translation missing --]]
L["SETTING_CT_SHOW_COMBAT_POTIONS"] = "Show Combat Potions"
--[[Translation missing --]]
L["SETTING_CT_SHOW_COMBAT_POTIONS_DESC"] = "Display combat potion icons alongside your offensive cooldowns."
--[[Translation missing --]]
L["SETTING_CT_SHOW_TRINKETS"] = "Show Trinkets"
--[[Translation missing --]]
L["SETTING_CT_SHOW_TRINKETS_DESC"] = "Display equipped on-use trinket icons alongside your offensive cooldowns."
--[[Translation missing --]]
L["SETTING_DESATURATE_INACTIVE"] = "Desaturate Inactive Auras"
--[[Translation missing --]]
L["SETTING_DESATURATE_INACTIVE_DESC"] = "Show a tracked aura's icon in grey while it is not applied, or while you have no target for an aura tracked on your target. It turns back to full colour when the aura is applied. Only available with Always Show Tracked Auras."
--[[Translation missing --]]
L["SETTING_DEVOURER_REAP_AMMO_COLOR"] = "Souls Nearby Bar Color"
--[[Translation missing --]]
L["SETTING_DEVOURER_REAP_AMMO_COLOR_DESC"] = "Color of the thin souls-nearby meter along the bottom of the soul bar. Fills 0 to the Reap cap as Soul Fragments spawn. Requires Soul Fragments (1245577) to be added to Blizzard's CooldownSettings -> Buffs -> Tracked BUFFS."
--[[Translation missing --]]
L["SETTING_DEVOURER_REAP_FORECAST"] = "Devourer Reap Forecast"
--[[Translation missing --]]
L["SETTING_DEVOURER_REAP_FORECAST_DESC"] = "Overlay the soul bar with a preview showing how many souls the next Reap will add (4 base, 10 with Moment of Craving)."
--[[Translation missing --]]
L["SETTING_DEVOURER_REAP_FORECAST_SHOW_TEXT"] = "Show Reap Forecast Text"
--[[Translation missing --]]
L["SETTING_DEVOURER_REAP_FORECAST_SHOW_TEXT_DESC"] = "Override the soul bar's value text with 'current (nearby)'. Shows regardless of the global Show Value setting. The (nearby) suffix requires Soul Fragments (1245577) added to Blizzard's CooldownSettings -> Buffs; without it the text shows only the current soul count."
--[[Translation missing --]]
L["SETTING_DEVOURER_REAP_PIP_COLOR"] = "Breakpoint Pip Color"
--[[Translation missing --]]
L["SETTING_DEVOURER_REAP_PIP_COLOR_DESC"] = "Color of the vertical breakpoint marker at 30 souls (the point where Collapsing Star becomes castable). Only visible during Void Metamorphosis."
--[[Translation missing --]]
L["SETTING_DEVOURER_REAP_PREVIEW_COLOR"] = "Reap Preview Color"
--[[Translation missing --]]
L["SETTING_DEVOURER_REAP_PREVIEW_COLOR_DESC"] = "Color of the overlay showing how much progress the next Reap will add."
--[[Translation missing --]]
L["SETTING_DH_ART_OF_GLAIVE_COLOR"] = "Art of the Glaive Color"
--[[Translation missing --]]
L["SETTING_DH_ART_OF_GLAIVE_COLOR_DESC"] = "Bar color for the Art of the Glaive stack segments."
--[[Translation missing --]]
L["SETTING_DH_ART_OF_GLAIVE_DEVOURER"] = "Show Art of the Glaive (Devourer)"
--[[Translation missing --]]
L["SETTING_DH_ART_OF_GLAIVE_DEVOURER_DESC"] = "Devourer Demon Hunters running Aldrachi Reaver: add a bar counting the Soul Fragments you have consumed toward your next Reaver's Glaive, alongside your usual bar rather than replacing it. Fills at 20."
--[[Translation missing --]]
L["SETTING_DH_ART_OF_GLAIVE_HAVOC"] = "Show Art of the Glaive (Havoc)"
--[[Translation missing --]]
L["SETTING_DH_ART_OF_GLAIVE_HAVOC_DESC"] = "Havoc Demon Hunters running Aldrachi Reaver: show a bar counting the Soul Fragments you have consumed toward your next Reaver's Glaive. Fills at 6. Havoc has no other resource bar, so this one stands on its own."
--[[Translation missing --]]
L["SETTING_DH_ART_OF_GLAIVE_VENGEANCE"] = "Show Art of the Glaive (Vengeance)"
--[[Translation missing --]]
L["SETTING_DH_ART_OF_GLAIVE_VENGEANCE_DESC"] = "Vengeance Demon Hunters running Aldrachi Reaver: add a bar counting the Soul Fragments you have consumed toward your next Reaver's Glaive, alongside your usual bar rather than replacing it. Fills at 20."
--[[Translation missing --]]
L["SETTING_DH_NEARBY_SOULS"] = "Show Nearby Soul Fragments"
--[[Translation missing --]]
L["SETTING_DH_NEARBY_SOULS_COLOR"] = "Nearby Soul Fragments Color"
--[[Translation missing --]]
L["SETTING_DH_NEARBY_SOULS_COLOR_DESC"] = "Bar color for the nearby Soul Fragment stack segments."
--[[Translation missing --]]
L["SETTING_DH_NEARBY_SOULS_DESC"] = "Demon Hunters only: add a bar counting the Soul Fragments lying near you that you have not picked up yet, alongside your usual bar rather than replacing it. Up to 20 stacks on Havoc and Vengeance, 15 on Devourer. On Havoc it shows on its own, or alongside Art of the Glaive when that is shown."
--[[Translation missing --]]
L["SETTING_DISCIPLINE_RADIANCE_CHARGES"] = "Track Discipline Radiance charges"
--[[Translation missing --]]
L["SETTING_DISCIPLINE_RADIANCE_CHARGES_DESC"] = "Show Power Word: Radiance charge segments for Discipline Priests, displaying how many charges are currently available with a fractional fill on the recharging segment. Discipline Priest only."
--[[Translation missing --]]
L["SETTING_DISCIPLINE_RADIANCE_COLOR"] = "Power Word: Radiance Color"
--[[Translation missing --]]
L["SETTING_DISCIPLINE_RADIANCE_COLOR_DESC"] = "Bar color for Power Word: Radiance charge segments."
--[[Translation missing --]]
L["SETTING_DK_BLOOD_COLOR"] = "Rune Color (Blood)"
--[[Translation missing --]]
L["SETTING_DK_BLOOD_COLOR_DESC"] = "Bar color for Death Knight runes when playing Blood spec."
--[[Translation missing --]]
L["SETTING_DK_FROST_COLOR"] = "Rune Color (Frost)"
--[[Translation missing --]]
L["SETTING_DK_FROST_COLOR_DESC"] = "Bar color for Death Knight runes when playing Frost spec."
--[[Translation missing --]]
L["SETTING_DK_UNHOLY_COLOR"] = "Rune Color (Unholy)"
--[[Translation missing --]]
L["SETTING_DK_UNHOLY_COLOR_DESC"] = "Bar color for Death Knight runes when playing Unholy spec."
--[[Translation missing --]]
L["SETTING_DRUID_CAT_FORM"] = "Show in Cat Form"
--[[Translation missing --]]
L["SETTING_DRUID_CAT_FORM_DESC"] = "Show combo points when shifting into Cat Form on non-Feral specializations. The bar automatically hides when leaving Cat Form."
--[[Translation missing --]]
L["SETTING_DURATION_TEXT"] = "Duration Text"
--[[Translation missing --]]
L["SETTING_ENABLED"] = "Enabled"
--[[Translation missing --]]
L["SETTING_ENABLED_DESC"] = [=[Enable or disable this component.
Disabled components are hidden during normal gameplay but visible in Edit Mode.]=]
--[[Translation missing --]]
L["SETTING_ENHANCEMENT_MAELSTROM_WEAPON"] = "Show Maelstrom Weapon"
--[[Translation missing --]]
L["SETTING_ENHANCEMENT_MAELSTROM_WEAPON_DESC"] = "Show Maelstrom Weapon stack segments for Shamans with the Maelstrom Weapon talent. Stacks are gained from melee abilities and allow spenders to be cast instantly at 5 or more stacks."
--[[Translation missing --]]
L["SETTING_ENHANCEMENT_MW_COLOR"] = "Maelstrom Weapon Color"
--[[Translation missing --]]
L["SETTING_ENHANCEMENT_MW_COLOR_DESC"] = "Bar color for Maelstrom Weapon stack segments."
--[[Translation missing --]]
L["SETTING_ENHANCEMENT_MW_THRESHOLD"] = "Highlight 5+ Stacks"
--[[Translation missing --]]
L["SETTING_ENHANCEMENT_MW_THRESHOLD_COLOR"] = "Maelstrom Weapon Color (5+ Stacks)"
--[[Translation missing --]]
L["SETTING_ENHANCEMENT_MW_THRESHOLD_COLOR_DESC"] = "Bar color for Maelstrom Weapon segments at 5 or more stacks, when spenders become instant cast."
--[[Translation missing --]]
L["SETTING_ENHANCEMENT_MW_THRESHOLD_DESC"] = "Use a different color for Maelstrom Weapon segments at 5 or more stacks, indicating spenders can be cast instantly."
--[[Translation missing --]]
L["SETTING_EVOKER_ESSENCE_BURST"] = "Show Essence Burst"
--[[Translation missing --]]
L["SETTING_EVOKER_ESSENCE_BURST_COLOR"] = "Essence Burst Color"
--[[Translation missing --]]
L["SETTING_EVOKER_ESSENCE_BURST_COLOR_DESC"] = "Bar color used for Essence segments affected by Essence Burst."
--[[Translation missing --]]
L["SETTING_EVOKER_ESSENCE_BURST_DESC"] = "Change the color of Essence bars that would be saved by an Essence Burst proc. Requires Essence Burst to be tracked in the Buff Tracker, or the affected spender spells to show a glow in the Cooldown Tracker."
--[[Translation missing --]]
L["SETTING_EVOKER_ESSENCE_PREDICTION"] = "Show Spender Prediction"
--[[Translation missing --]]
L["SETTING_EVOKER_ESSENCE_PREDICTION_DESC"] = "Highlight the leftmost Essence segments that would be consumed by your next main spender. The highlight shares the Essence Burst color and sits underneath the bar border."
--[[Translation missing --]]
L["SETTING_EVOKER_UNBOUND_FLAME"] = "Show Unbound Flame Charges"
--[[Translation missing --]]
L["SETTING_EVOKER_UNBOUND_FLAME_COLOR"] = "Unbound Flame Color"
--[[Translation missing --]]
L["SETTING_EVOKER_UNBOUND_FLAME_COLOR_DESC"] = "Bar color for the Unbound Flame charge segments."
--[[Translation missing --]]
L["SETTING_EVOKER_UNBOUND_FLAME_DESC"] = "Devastation Evokers with 4 points in Rising Fury only: add a second bar counting the Unbound Flame casts you have left after Dragonrage ends, alongside your Essence rather than replacing it. 4 charges, each one a cast, and the buff expires after 60 seconds whether you spend them or not."
--[[Translation missing --]]
L["SETTING_EVOKER_UNBOUND_FLAME_EXPIRY"] = "Unbound Flame Expiry Border"
--[[Translation missing --]]
L["SETTING_EVOKER_UNBOUND_FLAME_EXPIRY_COLOR"] = "Unbound Flame Expiry Border Color"
--[[Translation missing --]]
L["SETTING_EVOKER_UNBOUND_FLAME_EXPIRY_COLOR_DESC"] = "Border color for the Unbound Flame expiry border."
--[[Translation missing --]]
L["SETTING_EVOKER_UNBOUND_FLAME_EXPIRY_DESC"] = "Draw a border around the Unbound Flame bar while the buff is close to expiring. The game decides when to show it, which is the only way to get a timing cue out of a buff whose duration addons cannot read. Experimental: the game may compute no such window for this buff, in which case the border never appears."
--[[Translation missing --]]
L["SETTING_EXCLUDE_TRINKET_DROP"] = "Drop Trinket Here"
--[[Translation missing --]]
L["SETTING_EXCLUDE_TRINKET_DROP_DESC"] = "Pick up a trinket from your inventory, then click this button to add it to the exclude list."
--[[Translation missing --]]
L["SETTING_EXCLUDE_TRINKET_INPUT"] = "Add Trinket"
--[[Translation missing --]]
L["SETTING_EXCLUDE_TRINKET_INPUT_DESC"] = "Enter an item name or ID. You can also shift-click an equipped item while this field is focused."
--[[Translation missing --]]
L["SETTING_EXCLUDED_LIST"] = "Excluded"
--[[Translation missing --]]
L["SETTING_EXPIRING_TIME"] = "Expiring Threshold"
--[[Translation missing --]]
L["SETTING_EXPIRING_TIME_DESC"] = "Seconds remaining before the expiring glow activates."
--[[Translation missing --]]
L["SETTING_EXTRA_ROW_HEIGHT"] = "Extra Row Height"
--[[Translation missing --]]
L["SETTING_EXTRA_ROW_HEIGHT_DESC"] = "Height in pixels of each additional resource row. The main resource keeps the Height setting above, and the frame grows by this much for every extra row rather than dividing the space."
--[[Translation missing --]]
L["SETTING_FILL_DIRECTION"] = "Fill Direction"
--[[Translation missing --]]
L["SETTING_FILL_DIRECTION_DESC"] = "Direction the bar fills as the GCD expires."
--[[Translation missing --]]
L["SETTING_FIRE_BLAST_CHARGES"] = "Show Fire Blast Charges"
--[[Translation missing --]]
L["SETTING_FIRE_BLAST_CHARGES_DESC"] = "Show Fire Blast charge segments for Fire Mages, displaying how many charges are currently available."
--[[Translation missing --]]
L["SETTING_FIRE_BLAST_COLOR"] = "Fire Blast Color"
--[[Translation missing --]]
L["SETTING_FIRE_BLAST_COLOR_DESC"] = "Bar color for Fire Blast charge segments."
--[[Translation missing --]]
L["SETTING_FIVE_SECOND_RULE"] = "Show Five-Second Rule"
--[[Translation missing --]]
L["SETTING_FIVE_SECOND_RULE_DESC"] = "A spark crosses the mana bar during the five seconds after you spend mana, while Spirit-based mana regeneration is paused."
--[[Translation missing --]]
L["SETTING_FIVE_SECOND_RULE_SIZE"] = "Five-Second Rule Size"
--[[Translation missing --]]
L["SETTING_FIVE_SECOND_RULE_SIZE_DESC"] = "How much of the mana bar's height the five-second-rule spark covers: all of it, or only its top or bottom third."
--[[Translation missing --]]
L["SETTING_FIXED_HEIGHT"] = "Fixed Height"
--[[Translation missing --]]
L["SETTING_FIXED_HEIGHT_SPREAD"] = "Fixed Height (Spread)"
--[[Translation missing --]]
L["SETTING_FIXED_HEIGHT_STRETCH"] = "Fixed Height (Stretch)"
--[[Translation missing --]]
L["SETTING_FIXED_WIDTH"] = "Fixed Width"
--[[Translation missing --]]
L["SETTING_FIXED_WIDTH_SPREAD"] = "Fixed Width (Spread)"
--[[Translation missing --]]
L["SETTING_FIXED_WIDTH_STRETCH"] = "Fixed Width (Stretch)"
--[[Translation missing --]]
L["SETTING_FONT"] = "Font"
--[[Translation missing --]]
L["SETTING_FONT_ANCHOR"] = "Position"
--[[Translation missing --]]
L["SETTING_FONT_ANCHOR_DESC"] = "Anchor point for this text within its parent frame."
--[[Translation missing --]]
L["SETTING_FONT_COLOR"] = "Font Color"
--[[Translation missing --]]
L["SETTING_FONT_COLOR_DESC"] = "Color of the text."
--[[Translation missing --]]
L["SETTING_FONT_DESC"] = "Select a font face."
--[[Translation missing --]]
L["SETTING_FONT_OFFSET_X"] = "X Offset"
--[[Translation missing --]]
L["SETTING_FONT_OFFSET_X_DESC"] = "Horizontal pixel offset from the anchor point."
--[[Translation missing --]]
L["SETTING_FONT_OFFSET_Y"] = "Y Offset"
--[[Translation missing --]]
L["SETTING_FONT_OFFSET_Y_DESC"] = "Vertical pixel offset from the anchor point."
--[[Translation missing --]]
L["SETTING_FONT_OUTLINE"] = "Font Outline"
--[[Translation missing --]]
L["SETTING_FONT_OUTLINE_DESC"] = "Text outline style for readability against different backgrounds."
--[[Translation missing --]]
L["SETTING_FONT_SHADOW_COLOR"] = "Shadow Color"
--[[Translation missing --]]
L["SETTING_FONT_SHADOW_COLOR_DESC"] = "Color of the text shadow. Only applies when font outline is set to None."
--[[Translation missing --]]
L["SETTING_FONT_SHADOW_OFFSET_X"] = "Shadow X"
--[[Translation missing --]]
L["SETTING_FONT_SHADOW_OFFSET_X_DESC"] = "Horizontal shadow offset in pixels. Only applies when font outline is set to None."
--[[Translation missing --]]
L["SETTING_FONT_SHADOW_OFFSET_Y"] = "Shadow Y"
--[[Translation missing --]]
L["SETTING_FONT_SHADOW_OFFSET_Y_DESC"] = "Vertical shadow offset in pixels. Only applies when font outline is set to None."
--[[Translation missing --]]
L["SETTING_FONT_SIZE"] = "Font Size"
--[[Translation missing --]]
L["SETTING_FONT_SIZE_DESC"] = "Font size in points."
--[[Translation missing --]]
L["SETTING_FORCE_DESATURATION"] = "Always Desaturate On Cooldown"
--[[Translation missing --]]
L["SETTING_FORCE_DESATURATION_DESC"] = "Keep an icon greyed out while its buff is active, instead of showing it in full color. Applies for the whole buff, even if the cooldown ends first. Ignored if 'No Desaturation' is enabled."
--[[Translation missing --]]
L["SETTING_FRAME_POINT"] = "Frame Point"
--[[Translation missing --]]
L["SETTING_FRAME_POINT_DESC"] = [=[Which point on the frame itself is used as the reference edge.
Changing this recalculates offsets so the frame stays in place.]=]
--[[Translation missing --]]
L["SETTING_FRAME_STRATA"] = "Frame Strata"
--[[Translation missing --]]
L["SETTING_FRAME_STRATA_DESC"] = [=[Controls which draw layer this component uses. Higher strata draw on top of lower strata.

Inherit: Walks the anchor parent chain; free-moving roots fall back to Medium.

Use Background/Low to sit beneath the default UI, or High/Dialog/Tooltip to sit on top of other addon frames.]=]
--[[Translation missing --]]
L["SETTING_FREE_OFFSET_X"] = "X Offset"
--[[Translation missing --]]
L["SETTING_FREE_OFFSET_X_DESC"] = "Horizontal pixel offset from the anchor point on the screen."
--[[Translation missing --]]
L["SETTING_FREE_OFFSET_Y"] = "Y Offset"
--[[Translation missing --]]
L["SETTING_FREE_OFFSET_Y_DESC"] = "Vertical pixel offset from the anchor point on the screen."
--[[Translation missing --]]
L["SETTING_FROST_ICICLES"] = "Show Icicles"
--[[Translation missing --]]
L["SETTING_FROST_ICICLES_COLOR"] = "Icicles Color"
--[[Translation missing --]]
L["SETTING_FROST_ICICLES_COLOR_DESC"] = "Bar color for Icicle generation segments."
--[[Translation missing --]]
L["SETTING_FROST_ICICLES_DESC"] = "Show Icicle generation segments for Frost Mages. Icicles generate automatically every 6 seconds (modified by haste), up to 5. At 5 Icicles, Glacial Spike becomes available. A glow appears at full stacks."
--[[Translation missing --]]
L["SETTING_FURY_WHIRLWIND"] = "Show Whirlwind Charges"
--[[Translation missing --]]
L["SETTING_FURY_WHIRLWIND_COLOR"] = "Whirlwind Color"
--[[Translation missing --]]
L["SETTING_FURY_WHIRLWIND_COLOR_DESC"] = "Bar color for Improved Whirlwind charge segments."
--[[Translation missing --]]
L["SETTING_FURY_WHIRLWIND_DESC"] = "Show Improved Whirlwind charge segments for Fury Warriors. Charges are gained by casting Whirlwind (or Thunder Clap with Crackling/Crashing Thunder) and consumed by single-target spenders. Requires the Improved Whirlwind talent."
--[[Translation missing --]]
L["SETTING_GCD_DURATION_TEXT"] = "Duration Text"
--[[Translation missing --]]
L["SETTING_GCD_EDGE_CHARGES"] = "GCD Edge on Available Charges"
--[[Translation missing --]]
L["SETTING_GCD_EDGE_CHARGES_DESC"] = "Show GCD as an edge sweep instead of a dark swipe on charge spells with remaining charges, matching action bar behavior."
--[[Translation missing --]]
L["SETTING_GCD_SPELL_NAME_TEXT"] = "Spell Name Text"
--[[Translation missing --]]
L["SETTING_GLOW_ACTIVE"] = "Active Buff Glow"
--[[Translation missing --]]
L["SETTING_GLOW_ACTIVE_DESC"] = "Show a green border glow and remaining duration while a trinket or combat potion's buff effect is active on your character. Duration is automatically detected from the item."
--[[Translation missing --]]
L["SETTING_GLOW_APPROACHING"] = "Approaching Ready"
--[[Translation missing --]]
L["SETTING_GLOW_APPROACHING_DESC"] = "Show a subtle border glow when an item is about to come off cooldown."
--[[Translation missing --]]
L["SETTING_GLOW_APPROACHING_TIME"] = "Approaching Time"
--[[Translation missing --]]
L["SETTING_GLOW_APPROACHING_TIME_DESC"] = [=[How many seconds before the cooldown ends to start the approaching glow.
0 = off.]=]
--[[Translation missing --]]
L["SETTING_GLOW_COMBAT_POTIONS_ONLY"] = "Combat Potions Only"
--[[Translation missing --]]
L["SETTING_GLOW_COMBAT_POTIONS_ONLY_DESC"] = "Only show cooldown glows (flash, pulse, approaching) on combat potions. Health potions, mana potions, and healthstones will not glow."
--[[Translation missing --]]
L["SETTING_GLOW_DURATION"] = "Pulse Duration"
--[[Translation missing --]]
L["SETTING_GLOW_DURATION_DESC"] = [=[How many seconds the persistent pulse lasts.
0 = until the item is used or combat ends.]=]
--[[Translation missing --]]
L["SETTING_GLOW_EFFECTS"] = "Glow Effects"
--[[Translation missing --]]
L["SETTING_GLOW_ENABLED"] = "Enable Glow"
--[[Translation missing --]]
L["SETTING_GLOW_ENABLED_DESC"] = "Show glow effects on icons when cooldowns become available during combat."
--[[Translation missing --]]
L["SETTING_GLOW_EXPIRING"] = "Glow When Expiring"
--[[Translation missing --]]
L["SETTING_GLOW_EXPIRING_DESC"] = "Glow on icons when the buff is about to expire."
--[[Translation missing --]]
L["SETTING_GLOW_FLASH"] = "Flash on Ready"
--[[Translation missing --]]
L["SETTING_GLOW_FLASH_DESC"] = "Play a brief flash animation when an item comes off cooldown during combat."
--[[Translation missing --]]
L["SETTING_GLOW_MISSING"] = "Glow When Missing"
--[[Translation missing --]]
L["SETTING_GLOW_MISSING_DESC"] = "Pulse glow on icons for missing buffs."
--[[Translation missing --]]
L["SETTING_GLOW_PULSE"] = "Persistent Pulse"
--[[Translation missing --]]
L["SETTING_GLOW_PULSE_DESC"] = "Show a continuous pulsing glow on ready items during combat."
--[[Translation missing --]]
L["SETTING_GLOW_READY_IN_MPLUS"] = "Glow When Ready in Mythic+"
--[[Translation missing --]]
L["SETTING_GLOW_READY_IN_MPLUS_DESC"] = [=[While inside an active Mythic+ keystone run, keep the pulse glow active whenever a tracked potion is ready to use.
Respects the 'Combat potions only' toggle.]=]
--[[Translation missing --]]
L["SETTING_GROWTH_DIRECTION"] = "Growth Direction"
--[[Translation missing --]]
L["SETTING_GROWTH_DIRECTION_DESC"] = [=[Direction bars stack when new buffs appear.
Vertical: Up or Down.
Horizontal: Left or Right.]=]
--[[Translation missing --]]
L["SETTING_GROWTH_DOWN"] = "Down"
--[[Translation missing --]]
L["SETTING_GROWTH_LEFT"] = "Left"
--[[Translation missing --]]
L["SETTING_GROWTH_RIGHT"] = "Right"
--[[Translation missing --]]
L["SETTING_GROWTH_UP"] = "Up"
--[[Translation missing --]]
L["SETTING_GUARDIAN_IRONFUR"] = "Show Ironfur"
--[[Translation missing --]]
L["SETTING_GUARDIAN_IRONFUR_COLOR"] = "Ironfur Color"
--[[Translation missing --]]
L["SETTING_GUARDIAN_IRONFUR_COLOR_DESC"] = "Bar color for the Ironfur duration bar."
--[[Translation missing --]]
L["SETTING_GUARDIAN_IRONFUR_DESC"] = "Show Ironfur duration bar for Guardian Druids. Displays a single bar that drains over the buff duration with tick marks showing when each stack expires."
--[[Translation missing --]]
L["SETTING_HEIGHT"] = "Height"
--[[Translation missing --]]
L["SETTING_HEIGHT_DESC"] = "Set the frame height in pixels."
--[[Translation missing --]]
L["SETTING_HIDE_ACTIVE_SWIPE"] = "Hide Active Buff Duration"
--[[Translation missing --]]
L["SETTING_HIDE_ACTIVE_SWIPE_DESC"] = "Hide the yellow buff duration overlay on cooldown icons while their effect is active. When the spell is still on cooldown, the normal cooldown timer is shown instead."
--[[Translation missing --]]
L["SETTING_HIDE_CD_SWIPE"] = "Hide Cooldown Swipe"
--[[Translation missing --]]
L["SETTING_HIDE_CD_SWIPE_DESC"] = "Hide the dark cooldown swipe animation on icons when a spell is on cooldown. Timer text and other visual indicators are not affected."
--[[Translation missing --]]
L["SETTING_HIDE_CD_TEXT"] = "Hide Timer Text"
--[[Translation missing --]]
L["SETTING_HIDE_CD_TEXT_DESC"] = "Hide the cooldown countdown numbers shown on icons. Useful when using an external cooldown addon like OmniCC."
--[[Translation missing --]]
L["SETTING_HIDE_CHARGE_CD_TEXT"] = "Hide Charge Recharge Text"
--[[Translation missing --]]
L["SETTING_HIDE_CHARGE_CD_TEXT_DESC"] = "Hide cooldown countdown text for charge spells while charges remain available, matching action bar behavior. Text only appears when all charges are depleted."
--[[Translation missing --]]
L["SETTING_HIDE_GCD_SWIPE"] = "Hide GCD Swipe"
--[[Translation missing --]]
L["SETTING_HIDE_GCD_SWIPE_DESC"] = "Hide the dark cooldown swipe that briefly appears on all spell icons during the Global Cooldown."
--[[Translation missing --]]
L["SETTING_HIDE_ICON"] = "Hide Icon Texture"
--[[Translation missing --]]
L["SETTING_HIDE_ICON_DESC"] = "Hide the spell icon texture. Cooldown text, charge counts, and other overlays remain visible."
--[[Translation missing --]]
L["SETTING_HIDE_INACTIVE_BG"] = "Hide Background When Inactive"
--[[Translation missing --]]
L["SETTING_HIDE_INACTIVE_BG_DESC"] = "Hide the component background when neither the cast bar nor the GCD bar is actively showing."
--[[Translation missing --]]
L["SETTING_HIDE_READY_BLINK"] = "Hide Ready Blink"
--[[Translation missing --]]
L["SETTING_HIDE_READY_BLINK_DESC"] = "Suppress the flash/blink Blizzard plays when a spell finishes its cooldown. The icon stays fully visible; only the end-of-cooldown blink is removed. Independent of Icon Visibility."
--[[Translation missing --]]
L["SETTING_HIDE_WHEN_APPLIED"] = "Hide When Applied"
--[[Translation missing --]]
L["SETTING_HIDE_WHEN_APPLIED_DESC"] = "Hide icons for buffs that are currently active."
--[[Translation missing --]]
L["SETTING_HIDE_ZERO_CHARGES"] = "Hide Zero Charges"
--[[Translation missing --]]
L["SETTING_HIDE_ZERO_CHARGES_DESC"] = "Hide the charge count text on icons when all charges are depleted. The cooldown swipe still indicates recharge progress."
--[[Translation missing --]]
L["SETTING_ICON_HEIGHT"] = "Icon Height Override"
--[[Translation missing --]]
L["SETTING_ICON_HEIGHT_DESC"] = [=[Override icon height in pixels.
Set to 0 to match Icon Size (square icons).
Has no effect in Fixed Width (Stretch) mode.]=]
--[[Translation missing --]]
L["SETTING_ICON_LAYOUT"] = "Icon Layout"
--[[Translation missing --]]
L["SETTING_ICON_OFFSET"] = "Icon Offset"
--[[Translation missing --]]
L["SETTING_ICON_OFFSET_DESC"] = "Spacing in pixels between icons."
--[[Translation missing --]]
L["SETTING_ICON_SIZE"] = "Icon Size"
--[[Translation missing --]]
L["SETTING_ICON_SIZE_DESC"] = "Size of each icon in pixels."
--[[Translation missing --]]
L["SETTING_ICON_VISIBILITY_DISABLED"] = "Disabled"
--[[Translation missing --]]
L["SETTING_ICON_VISIBILITY_FADE_ONCD"] = "Fade When On Cooldown"
--[[Translation missing --]]
L["SETTING_ICON_VISIBILITY_FADE_READY"] = "Fade When Ready"
--[[Translation missing --]]
L["SETTING_ICON_VISIBILITY_FADED_ALPHA"] = "Faded Alpha"
--[[Translation missing --]]
L["SETTING_ICON_VISIBILITY_FADED_ALPHA_DESC"] = "Target opacity for icons in fade modes, as a fraction of the component's normal alpha. 0 fully hides the icon (but it still occupies its layout slot); higher values dim it without removing it. Has no effect in the hide modes."
--[[Translation missing --]]
L["SETTING_ICON_VISIBILITY_HIDE_ONCD"] = "Hide When On Cooldown"
--[[Translation missing --]]
L["SETTING_ICON_VISIBILITY_HIDE_READY"] = "Hide When Ready"
--[[Translation missing --]]
L["SETTING_ICON_VISIBILITY_MODE"] = "Icon Visibility"
--[[Translation missing --]]
L["SETTING_ICON_VISIBILITY_MODE_DESC"] = "Remove spells from the layout based on their cooldown. 'When Ready' hides spells that are off cooldown; 'When On Cooldown' hides spells that are currently unavailable. Fade variants animate the transition instead of snapping."
--[[Translation missing --]]
L["SETTING_ICON_VISIBILITY_TREAT_CHARGING_AS_ON_CD"] = "Treat Charging Charge Spells as On Cooldown"
--[[Translation missing --]]
L["SETTING_ICON_VISIBILITY_TREAT_CHARGING_AS_ON_CD_DESC"] = "When on: a charge spell with any recharge in flight counts as on cooldown (hide/fade applies even with charges still available). When off: only the fully-depleted state (no charges left) counts as on cooldown."
--[[Translation missing --]]
L["SETTING_INSTANT_ONLY"] = "Instant Casts Only"
--[[Translation missing --]]
L["SETTING_INSTANT_ONLY_DESC"] = "Only show the GCD bar for instant cast spells. Hides it when a cast bar is already visible."
--[[Translation missing --]]
L["SETTING_INTERACTABLE"] = "Interactable"
--[[Translation missing --]]
L["SETTING_INTERACTABLE_DESC"] = [=[Makes the health bar clickable. Left-click to target yourself, right-click to open the player menu.

Note: The clickable area will not adjust its position on screen during combat.]=]
--[[Translation missing --]]
L["SETTING_KEYBIND_TEXT"] = "Keybind Text"
--[[Translation missing --]]
L["SETTING_LATENCY_COLOR"] = "Latency Color"
--[[Translation missing --]]
L["SETTING_LATENCY_COLOR_DESC"] = "Color of the latency overlay."
--[[Translation missing --]]
L["SETTING_LAYOUT"] = "Layout"
--[[Translation missing --]]
L["SETTING_LAYOUT_ALIGNMENT"] = "Alignment"
--[[Translation missing --]]
L["SETTING_LAYOUT_ALIGNMENT_DESC"] = [=[Align items within the frame.
Horizontal: Left, Center, or Right.
Vertical: Top, Center, or Bottom.]=]
--[[Translation missing --]]
L["SETTING_LAYOUT_BLOCK"] = "Block"
--[[Translation missing --]]
L["SETTING_LAYOUT_DESC"] = "Arrange trinket icons horizontally (side by side) or vertically (stacked)."
--[[Translation missing --]]
L["SETTING_LAYOUT_DIRECTION"] = "Layout Direction"
--[[Translation missing --]]
L["SETTING_LAYOUT_DIRECTION_DESC"] = "Arrange items horizontally (in rows) or vertically (in columns)."
--[[Translation missing --]]
L["SETTING_LAYOUT_HORIZONTAL"] = "Horizontal"
--[[Translation missing --]]
L["SETTING_LAYOUT_VERTICAL"] = "Vertical"
--[[Translation missing --]]
L["SETTING_MAGE_ARCANE_SALVO_COLOR"] = "Arcane Salvo Color"
--[[Translation missing --]]
L["SETTING_MAGE_ARCANE_SALVO_COLOR_DESC"] = "Bar color for the Arcane Salvo stack segments."
--[[Translation missing --]]
L["SETTING_MAGE_ARCANE_SALVO_STACKS"] = "Show Arcane Salvo Stacks"
--[[Translation missing --]]
L["SETTING_MAGE_ARCANE_SALVO_STACKS_DESC"] = "Arcane Mages only: add a second bar tracking your banked Arcane Salvo stacks, alongside your Arcane Charges rather than replacing them. 20 stacks, or 25 with the Spellfire Salvo hero talent."
--[[Translation missing --]]
L["SETTING_MAGE_SHATTER_COLOR"] = "Shatter Color"
--[[Translation missing --]]
L["SETTING_MAGE_SHATTER_COLOR_DESC"] = "Bar color for the Shatter stack segments."
--[[Translation missing --]]
L["SETTING_MAGE_SHATTER_STACKS"] = "Show Shatter Stacks"
--[[Translation missing --]]
L["SETTING_MAGE_SHATTER_STACKS_DESC"] = "Frost Mages only: add a bar tracking stacks of Freezing on your current target, which is what Shatter consumes. 20 stacks. It shows alongside Icicles, or on its own with Show Icicles off. The bar follows your target automatically and hides on friendly targets."
--[[Translation missing --]]
L["SETTING_MARKSMAN_AIMED_SHOT"] = "Show Aimed Shot Charges"
--[[Translation missing --]]
L["SETTING_MARKSMAN_AIMED_SHOT_COLOR"] = "Aimed Shot Color"
--[[Translation missing --]]
L["SETTING_MARKSMAN_AIMED_SHOT_COLOR_DESC"] = "Bar color for Aimed Shot charge segments."
--[[Translation missing --]]
L["SETTING_MARKSMAN_AIMED_SHOT_DESC"] = "Show Aimed Shot charge segments for Marksmanship Hunters, displaying how many charges are currently available."
--[[Translation missing --]]
L["SETTING_MARKSMAN_LOCK_AND_LOAD"] = "Lock and Load Glow"
--[[Translation missing --]]
L["SETTING_MARKSMAN_LOCK_AND_LOAD_COLOR"] = "Lock and Load Color"
--[[Translation missing --]]
L["SETTING_MARKSMAN_LOCK_AND_LOAD_COLOR_DESC"] = "Bar color for Aimed Shot segments when Lock and Load is active."
--[[Translation missing --]]
L["SETTING_MARKSMAN_LOCK_AND_LOAD_DESC"] = "Highlight Aimed Shot charge segments when Lock and Load procs, indicating your next Aimed Shot is instant and free."
--[[Translation missing --]]
L["SETTING_MASS_DISINTEGRATE_GLOW"] = "Mass Disintegrate Glow"
--[[Translation missing --]]
L["SETTING_MASS_DISINTEGRATE_GLOW_DESC"] = "Show a pulsing border glow on the cast bar when channeling Disintegrate with Mass Disintegrate charges active (Scalecommander Evoker)."
--[[Translation missing --]]
L["SETTING_MAX_PER_ROW"] = "Max Per Row"
--[[Translation missing --]]
L["SETTING_MAX_PER_ROW_DESC"] = [=[Number of icons per row (horizontal) or per column (vertical).
Only available when Size Mode is set to Max Per Row.]=]
--[[Translation missing --]]
L["SETTING_MAX_WIDTH"] = "Overflow"
--[[Translation missing --]]
L["SETTING_MIN_WIDTH"] = "Min Width"
--[[Translation missing --]]
L["SETTING_MIN_WIDTH_DESC"] = [=[Minimum frame width in pixels whenever the frame sizes itself to its icons u2014 vertical layout, Max Per Row, or any mode with an explicit Icon Size.
Prevents the frame from shrinking too narrow when few icons are shown.
Set to 0 to disable.]=]
--[[Translation missing --]]
L["SETTING_MISTWEAVER_TEACHINGS"] = "Show Teachings of the Monastery"
--[[Translation missing --]]
L["SETTING_MISTWEAVER_TEACHINGS_COLOR"] = "Teachings of the Monastery Color"
--[[Translation missing --]]
L["SETTING_MISTWEAVER_TEACHINGS_COLOR_DESC"] = "Bar color for Teachings of the Monastery stack segments."
--[[Translation missing --]]
L["SETTING_MISTWEAVER_TEACHINGS_DESC"] = "Show Teachings of the Monastery stack segments for Mistweaver Monks. Built by Tiger Palm (up to 4) and consumed by Blackout Kick. Takes the Mistweaver secondary slot over Vitality when both are enabled. Requires the Teachings of the Monastery talent."
--[[Translation missing --]]
L["SETTING_MISTWEAVER_VITALITY"] = "Show Vitality (Mistweaver)"
--[[Translation missing --]]
L["SETTING_MISTWEAVER_VITALITY_DESC"] = "Show a Vitality bar for Mistweaver Monks with the Aspect of Harmony hero talent, displaying stored vitality."
--[[Translation missing --]]
L["SETTING_NAME_TEXT"] = "Name Text"
--[[Translation missing --]]
L["SETTING_NO_CD_OVERLAY"] = "No Cooldown Dimming"
--[[Translation missing --]]
L["SETTING_NO_CD_OVERLAY_DESC"] = "When hiding the active buff duration, do not darken the icon while the spell is on cooldown. A light golden pie sweep still indicates cooldown progress."
--[[Translation missing --]]
L["SETTING_NO_CD_OVERLAY_EDGE_ONLY"] = "Edge-Only Indicator"
--[[Translation missing --]]
L["SETTING_NO_CD_OVERLAY_EDGE_ONLY_DESC"] = "When 'No Cooldown Dimming' is on, show only the leading swipe edge instead of the tinted pie sweep. Has no effect unless 'No Cooldown Dimming' is enabled."
--[[Translation missing --]]
L["SETTING_NO_DESATURATION"] = "No Desaturation"
--[[Translation missing --]]
L["SETTING_NO_DESATURATION_DESC"] = "Keep ability icons fully saturated (colorful) even while on cooldown, instead of greying them out."
--[[Translation missing --]]
L["SETTING_NO_RANGE_TINT"] = "No Out of Range Tint"
--[[Translation missing --]]
L["SETTING_NO_RANGE_TINT_DESC"] = "Do not tint ability icons red and shaded while your target is out of range."
--[[Translation missing --]]
L["SETTING_OPACITY"] = "Opacity"
--[[Translation missing --]]
L["SETTING_OPACITY_DESC"] = [=[Controls the transparency of this component.

Opacity is inherited through the anchor chain u2014 a child's effective opacity is its own value multiplied by its parent's effective opacity.]=]
--[[Translation missing --]]
L["SETTING_ORIENTATION"] = "Orientation"
--[[Translation missing --]]
L["SETTING_ORIENTATION_DESC"] = [=[Set the bar fill direction.
Horizontal fills left to right.
Vertical fills bottom to top.]=]
--[[Translation missing --]]
L["SETTING_ORIENTATION_HORIZONTAL"] = "Horizontal"
--[[Translation missing --]]
L["SETTING_ORIENTATION_VERTICAL"] = "Vertical"
--[[Translation missing --]]
L["SETTING_OUTBOUND_ADD_SPELL"] = "Add Spell ID"
--[[Translation missing --]]
L["SETTING_OUTBOUND_ADD_SPELL_DESC"] = "Enter a spell ID to track outbound casts of this spell on party/raid members."
--[[Translation missing --]]
L["SETTING_OUTBOUND_FILTER_SELF_CAST"] = "Filter Self Cast"
--[[Translation missing --]]
L["SETTING_OUTBOUND_FILTER_SELF_CAST_DESC"] = "Hide bars for auras the player applied on themselves (e.g. your own Prescience)."
--[[Translation missing --]]
L["SETTING_OUTBOUND_MAX_BARS"] = "Max Bars"
--[[Translation missing --]]
L["SETTING_OUTBOUND_MAX_BARS_DESC"] = "Maximum number of bars rendered simultaneously."
--[[Translation missing --]]
L["SETTING_OUTBOUND_NAME_COLOR_CLASS"] = "Class Color"
--[[Translation missing --]]
L["SETTING_OUTBOUND_NAME_COLOR_SOURCE"] = "Name Color Source"
--[[Translation missing --]]
L["SETTING_OUTBOUND_NAME_COLOR_SOURCE_DESC"] = "Color the recipient name by class color or a fixed color."
--[[Translation missing --]]
L["SETTING_OUTBOUND_NAME_COLOR_STATIC"] = "Static Color"
--[[Translation missing --]]
L["SETTING_OUTBOUND_NAME_COLOR_STATIC_DESC"] = "The static recipient name color used when name color source is 'Static Color'."
--[[Translation missing --]]
L["SETTING_OUTBOUND_OVERFLOW_HIDE"] = "Hide Overflow"
--[[Translation missing --]]
L["SETTING_OUTBOUND_OVERFLOW_HIDE_DESC"] = "When enabled, entries past Max Bars are hidden. When disabled, all active bars render regardless of the limit."
--[[Translation missing --]]
L["SETTING_OUTBOUND_REMOVE_SPELL_DESC"] = "Click to stop tracking this spell."
--[[Translation missing --]]
L["SETTING_OUTBOUND_SORT_NAME_ASC"] = "Recipient Name (A-Z)"
--[[Translation missing --]]
L["SETTING_OUTBOUND_SORT_ORDER"] = "Sort Order"
--[[Translation missing --]]
L["SETTING_OUTBOUND_SORT_ORDER_DESC"] = "Order of bars when multiple buffs are active."
--[[Translation missing --]]
L["SETTING_OUTBOUND_SORT_REMAINING_ASC"] = "Remaining (shortest first)"
--[[Translation missing --]]
L["SETTING_OUTBOUND_SORT_REMAINING_DESC"] = "Remaining (longest first)"
--[[Translation missing --]]
L["SETTING_OVERFLOW_DIRECTION"] = "Overflow Direction"
--[[Translation missing --]]
L["SETTING_OVERFLOW_DIRECTION_DESC"] = [=[Direction overflow icons expand.
Horizontal: 'Top' or 'Bottom' for row stacking.
Vertical: 'Left' or 'Right' for column stacking.]=]
--[[Translation missing --]]
L["SETTING_OVERFLOW_ICON_SIZE"] = "Overflow Icon Size"
--[[Translation missing --]]
L["SETTING_OVERFLOW_ICON_SIZE_DESC"] = "Size of icons in the overflow (secondary) row."
--[[Translation missing --]]
L["SETTING_PALADIN_DIVINE_PURPOSE"] = "Show Divine Purpose"
--[[Translation missing --]]
L["SETTING_PALADIN_DIVINE_PURPOSE_COLOR"] = "Divine Purpose Color"
--[[Translation missing --]]
L["SETTING_PALADIN_DIVINE_PURPOSE_COLOR_DESC"] = "Bar color used for Holy Power segments when Divine Purpose is active."
--[[Translation missing --]]
L["SETTING_PALADIN_DIVINE_PURPOSE_DESC"] = "Change the color of filled Holy Power segments while Divine Purpose is active, indicating a free cast."
--[[Translation missing --]]
L["SETTING_PALADIN_SWING_COLOR"] = "Fill Color"
--[[Translation missing --]]
L["SETTING_PALADIN_SWING_COLOR_DESC"] = "Color for the swing timer fill bar."
--[[Translation missing --]]
L["SETTING_PALADIN_SWING_CUSTOM_COLOR"] = "Use Custom Fill Color"
--[[Translation missing --]]
L["SETTING_PALADIN_SWING_CUSTOM_COLOR_DESC"] = "Use a custom color for the swing timer fill bar instead of the automatic lighter shade."
--[[Translation missing --]]
L["SETTING_PALADIN_SWING_OVERFLOW"] = "Show Overflow Border at Max"
--[[Translation missing --]]
L["SETTING_PALADIN_SWING_OVERFLOW_DESC"] = "When Holy Power is full and Crusading Strikes is charging, show a glowing border on the last segment that builds as the swing timer progresses. Signals incoming wasted Holy Power generation."
--[[Translation missing --]]
L["SETTING_PALADIN_SWING_OVERFLOW_GLOW"] = "Pulse When Ready"
--[[Translation missing --]]
L["SETTING_PALADIN_SWING_OVERFLOW_GLOW_DESC"] = "Pulse the overflow border when the swing timer completes at full Holy Power."
--[[Translation missing --]]
L["SETTING_PALADIN_SWING_TIMER"] = "Show Crusading Strikes Swing Timer"
--[[Translation missing --]]
L["SETTING_PALADIN_SWING_TIMER_DESC"] = "Gradually fill the next empty Holy Power segment as the Crusading Strikes auto-attack timer progresses, showing when the next Holy Power will be gained from a swing. Requires the Crusading Strikes talent."
--[[Translation missing --]]
L["SETTING_PANDEMIC_GLOW"] = "Pandemic Border Glow"
--[[Translation missing --]]
L["SETTING_PANDEMIC_GLOW_COLOR"] = "Pandemic Glow Color"
--[[Translation missing --]]
L["SETTING_PANDEMIC_GLOW_COLOR_DESC"] = "Color of the pandemic border."
--[[Translation missing --]]
L["SETTING_PANDEMIC_GLOW_DESC"] = "Show a border on buff icons when the aura enters its pandemic window (can be refreshed without wasting duration)."
--[[Translation missing --]]
L["SETTING_PANDEMIC_GLOW_STYLE"] = "Glow Style"
--[[Translation missing --]]
L["SETTING_PANDEMIC_GLOW_STYLE_DESC"] = "Choose the visual style of the pandemic glow effect."
--[[Translation missing --]]
L["SETTING_PANDEMIC_GLOW_THICKNESS"] = "Border Thickness"
--[[Translation missing --]]
L["SETTING_PANDEMIC_GLOW_THICKNESS_DESC"] = "Pixel thickness of the Solid Border glow style (1-6)."
--[[Translation missing --]]
L["SETTING_POSITION_OFFSET"] = "Follow Gap"
--[[Translation missing --]]
L["SETTING_POSITION_OFFSET_DESC"] = "Pixel gap between this component and the reference frame edge."
--[[Translation missing --]]
L["SETTING_POSITION_REFERENCE"] = "Follow Frame"
--[[Translation missing --]]
L["SETTING_POSITION_REFERENCE_DESC"] = [=[Position this component relative to another frame using screen coordinates.
Updated out of combat only. Does not create an anchor chain.]=]
--[[Translation missing --]]
L["SETTING_POSITION_SIDE"] = "Follow Side"
--[[Translation missing --]]
L["SETTING_POSITION_SIDE_DESC"] = "Which side of the reference frame to position on."
--[[Translation missing --]]
L["SETTING_PROTECTION_IGNORE_PAIN"] = "Show Ignore Pain"
--[[Translation missing --]]
L["SETTING_PROTECTION_IGNORE_PAIN_COLOR"] = "Ignore Pain Color"
--[[Translation missing --]]
L["SETTING_PROTECTION_IGNORE_PAIN_COLOR_DESC"] = "Bar color for the Ignore Pain bar."
--[[Translation missing --]]
L["SETTING_PROTECTION_IGNORE_PAIN_DESC"] = "Show an Ignore Pain bar for Protection Warriors."
--[[Translation missing --]]
L["SETTING_PROTECTION_IGNORE_PAIN_PANDEMIC"] = "Pandemic Glow"
--[[Translation missing --]]
L["SETTING_PROTECTION_IGNORE_PAIN_PANDEMIC_DESC"] = "Pulse and recolor the border when Ignore Pain is in the pandemic window (last 30% of duration)."
--[[Translation missing --]]
L["SETTING_PROTECTION_IGNORE_PAIN_TIME_BAR"] = "Switch to Time Remaining"
--[[Translation missing --]]
L["SETTING_PROTECTION_IGNORE_PAIN_TIME_BAR_DESC"] = "Switch the bar fill from absorb stacks to time remaining. When enabled, the bar drains over the buff duration and stack count is shown as text instead."
--[[Translation missing --]]
L["SETTING_PUSHBACK_FLASH"] = "Pushback Cutaway"
--[[Translation missing --]]
L["SETTING_PUSHBACK_FLASH_DESC"] = "When taking damage pushes a cast back or cuts a channel short, the progress you lost stays on the bar as a red block for a moment, then fades. Pushback from damage is a classic-era mechanic; on modern content it rarely happens."
--[[Translation missing --]]
L["SETTING_QUEUE_PIP_COLOR"] = "Queue Window Color"
--[[Translation missing --]]
L["SETTING_QUEUE_PIP_COLOR_DESC"] = "Color of the spell queue window marker."
--[[Translation missing --]]
L["SETTING_REMOVE_EXCLUDED"] = "Click to remove"
--[[Translation missing --]]
L["SETTING_RESERVE_SLOTS"] = "Reserve Slots"
--[[Translation missing --]]
L["SETTING_RESERVE_SLOTS_DESC"] = "Always reserve space for 2 trinket slots, even when fewer trinkets are equipped."
--[[Translation missing --]]
L["SETTING_REVERSE_SWIPE"] = "Reverse Cooldown Swipe"
--[[Translation missing --]]
L["SETTING_REVERSE_SWIPE_DESC"] = "Reverse the direction of cooldown and GCD swipe animations on icons."
--[[Translation missing --]]
L["SETTING_ROGUE_CDG_COLOR"] = "Coup de Gr\\195\\162ce Pip Color"
--[[Translation missing --]]
L["SETTING_ROGUE_CDG_COLOR_DESC"] = "Color for Coup de Gr\\195\\162ce progress pips on combo point segments."
--[[Translation missing --]]
L["SETTING_ROGUE_COUP_DE_GRACE"] = "Show Coup de Gr\\195\\162ce Progress"
--[[Translation missing --]]
L["SETTING_ROGUE_COUP_DE_GRACE_DESC"] = "Show small colored pips on combo point segments tracking Escalating Blade stacks toward Coup de Gr\\195\\162ce. Requires the Coup de Gr\\195\\162ce talent (Trickster hero talent tree)."
--[[Translation missing --]]
L["SETTING_ROTATION_HIGHLIGHT"] = "Rotation Highlight"
--[[Translation missing --]]
L["SETTING_ROTATION_HIGHLIGHT_DESC"] = "Show Blizzard's rotation-helper \"ants\" animation on whichever tracker icon the Assisted Combat system currently suggests as the next cast. Enabling this also turns on Blizzard's Assisted Highlight, which draws the same suggestion on your action bars. When no tracker uses it any more, you are asked whether to turn Blizzard's off again."
--[[Translation missing --]]
L["SETTING_ROUTE_COMBAT_POTIONS"] = "Show in Cooldown Tracker"
--[[Translation missing --]]
L["SETTING_ROUTE_COMBAT_POTIONS_DESC"] = "Display combat potion icons inside the Cooldown Tracker alongside your offensive cooldowns."
--[[Translation missing --]]
L["SETTING_ROUTE_TRINKETS"] = "Show in Cooldown Tracker"
--[[Translation missing --]]
L["SETTING_ROUTE_TRINKETS_DESC"] = "Display equipped on-use trinket icons inside the Cooldown Tracker alongside your offensive cooldowns."
--[[Translation missing --]]
L["SETTING_SHIELD_OFFSET_X"] = "Shield Horizontal Offset"
--[[Translation missing --]]
L["SETTING_SHIELD_OFFSET_X_DESC"] = "Horizontal offset of the shield indicator from the left edge of the cast bar."
--[[Translation missing --]]
L["SETTING_SHIELD_OFFSET_Y"] = "Shield Vertical Offset"
--[[Translation missing --]]
L["SETTING_SHIELD_OFFSET_Y_DESC"] = "Vertical offset of the shield indicator from the left edge of the cast bar."
--[[Translation missing --]]
L["SETTING_SHIELD_SCALE"] = "Shield Size"
--[[Translation missing --]]
L["SETTING_SHIELD_SCALE_DESC"] = "Scale the shield indicator. 1.0 is the default size."
--[[Translation missing --]]
L["SETTING_SHOW_ACTIVE_DURATION"] = "Show Active Duration"
--[[Translation missing --]]
L["SETTING_SHOW_ACTIVE_DURATION_DESC"] = "When enabled, shows the remaining buff duration while a trinket effect is active, switching to cooldown when it expires. When disabled, always shows the cooldown countdown."
--[[Translation missing --]]
L["SETTING_SHOW_ALL_BUFFS"] = "Show All Buffs"
--[[Translation missing --]]
L["SETTING_SHOW_ALL_BUFFS_DESC"] = "Show icons for all six class raid buffs, not just the one your class provides."
--[[Translation missing --]]
L["SETTING_SHOW_CAST_ICON"] = "Show Spell Icon"
--[[Translation missing --]]
L["SETTING_SHOW_CAST_ICON_DESC"] = "Show the spell icon on the cast bar."
--[[Translation missing --]]
L["SETTING_SHOW_CHANNEL_TICKS"] = "Channel Ticks"
--[[Translation missing --]]
L["SETTING_SHOW_CHANNEL_TICKS_DESC"] = "Show tick marks on the cast bar during channeled spells, indicating when each tick of damage or healing fires."
--[[Translation missing --]]
L["SETTING_SHOW_COUNT"] = "Show Count"
--[[Translation missing --]]
L["SETTING_SHOW_COUNT_DESC"] = "Display the item count on each consumable icon."
--[[Translation missing --]]
L["SETTING_SHOW_DURATION"] = "Show Duration"
--[[Translation missing --]]
L["SETTING_SHOW_DURATION_DESC"] = "Display the remaining GCD time on the bar."
--[[Translation missing --]]
L["SETTING_SHOW_HEALING_PREDICTION"] = "Show Healing Prediction"
--[[Translation missing --]]
L["SETTING_SHOW_HEALING_PREDICTION_DESC"] = "Show the incoming healing prediction overlay on the health bar."
--[[Translation missing --]]
L["SETTING_SHOW_IN_CHALLENGE_MODE"] = "Show in Mythic+"
--[[Translation missing --]]
L["SETTING_SHOW_IN_CHALLENGE_MODE_DESC"] = "Keep the tracker visible inside Mythic+ dungeons. Buff detection may be unreliable due to secret aura data."
--[[Translation missing --]]
L["SETTING_SHOW_KEYBIND"] = "Show Keybind"
--[[Translation missing --]]
L["SETTING_SHOW_KEYBIND_DESC"] = "Display the keyboard shortcut for each spell on its icon."
--[[Translation missing --]]
L["SETTING_SHOW_LATENCY"] = "Show Latency"
--[[Translation missing --]]
L["SETTING_SHOW_LATENCY_DESC"] = "Show a latency overlay covering the end of the bar u2014 the window in which the next cast can already be queued."
--[[Translation missing --]]
L["SETTING_SHOW_OVERRIDE_BAR_ABILITIES"] = "Show Override Bar Abilities"
--[[Translation missing --]]
L["SETTING_SHOW_OVERRIDE_BAR_ABILITIES_DESC"] = "Display override action bar abilities in the tracker during quests and scenarios that replace your action bar."
--[[Translation missing --]]
L["SETTING_SHOW_OVERRIDE_KEYBIND_TEXT"] = "Show Keybind on Override/Skyriding Bar"
--[[Translation missing --]]
L["SETTING_SHOW_OVERRIDE_KEYBIND_TEXT_DESC"] = "Display action bar keybind text on vehicle, override, and skyriding ability icons. Independent from the regular keybind text toggle."
--[[Translation missing --]]
L["SETTING_SHOW_PASSIVE_TRINKETS"] = "Show Passive Trinkets"
--[[Translation missing --]]
L["SETTING_SHOW_PASSIVE_TRINKETS_DESC"] = "Show proc trinkets that trigger automatically and have no on-use button. When off, only on-use trinkets are shown."
--[[Translation missing --]]
L["SETTING_SHOW_QUEUE_PIP"] = "Show Spell Queue Window"
--[[Translation missing --]]
L["SETTING_SHOW_QUEUE_PIP_DESC"] = "Show a marker on the GCD bar indicating when you can start queuing your next spell."
--[[Translation missing --]]
L["SETTING_SHOW_SHIELD"] = "Show Shield Indicator"
--[[Translation missing --]]
L["SETTING_SHOW_SHIELD_DESC"] = "Show a shield icon on the cast bar when the cast cannot be interrupted."
--[[Translation missing --]]
L["SETTING_SHOW_SHIELDS"] = "Show Shields"
--[[Translation missing --]]
L["SETTING_SHOW_SHIELDS_DESC"] = "Show the damage absorb shield overlay on the health bar."
--[[Translation missing --]]
L["SETTING_SHOW_SKYRIDING_ABILITIES"] = "Show Skyriding Abilities"
--[[Translation missing --]]
L["SETTING_SHOW_SKYRIDING_ABILITIES_DESC"] = "Display skyriding ability cooldowns in the tracker when mounted on a skyriding mount. Uses your existing tracker layout settings."
--[[Translation missing --]]
L["SETTING_SHOW_SLOT_1"] = "Trinket 1"
--[[Translation missing --]]
L["SETTING_SHOW_SLOT_1_DESC"] = "Show the first trinket slot."
--[[Translation missing --]]
L["SETTING_SHOW_SLOT_2"] = "Trinket 2"
--[[Translation missing --]]
L["SETTING_SHOW_SLOT_2_DESC"] = "Show the second trinket slot."
--[[Translation missing --]]
L["SETTING_SHOW_SPARK"] = "Show Spark"
--[[Translation missing --]]
L["SETTING_SHOW_SPARK_DESC"] = "Show the spark indicator on the cast bar."
--[[Translation missing --]]
L["SETTING_SHOW_SPELL_NAME"] = "Show Spell Name"
--[[Translation missing --]]
L["SETTING_SHOW_SPELL_NAME_DESC"] = "Display the name of the spell that triggered the GCD. Only shown for instant cast spells."
--[[Translation missing --]]
L["SETTING_SHOW_TIMER"] = "Show Timer"
--[[Translation missing --]]
L["SETTING_SHOW_TIMER_DESC"] = "Show the remaining duration text on each bar."
--[[Translation missing --]]
L["SETTING_SHOW_TOTEMS"] = "Track Totems"
--[[Translation missing --]]
L["SETTING_SHOW_TOTEMS_DESC"] = [=[Show each of your active totems - shaman totems, and everything the game files as one, such as Dreadstalkers and Demonic Tyrant.

These never appear as tracked buffs, because they place nothing on you. A place is reserved for each totem slot, so that a totem placed during a fight can still appear. On buff icons they lead the row, and empty ones close up unless Always Show Tracked Auras is on.]=]
--[[Translation missing --]]
L["SETTING_SHOW_VALUE"] = "Show Value"
--[[Translation missing --]]
L["SETTING_SHOW_VALUE_DESC"] = "Display the current resource count as a number in the center of the bar."
--[[Translation missing --]]
L["SETTING_SHOW_VEHICLE_ABILITIES"] = "Show Vehicle Abilities"
--[[Translation missing --]]
L["SETTING_SHOW_VEHICLE_ABILITIES_DESC"] = "Display vehicle action bar abilities in the tracker when controlling a vehicle."
--[[Translation missing --]]
L["SETTING_SHOW_WHEN_CASTING"] = "Show When Casting"
--[[Translation missing --]]
L["SETTING_SHOW_WHEN_CASTING_DESC"] = "Always show the cast bar while casting or channeling, even when the anchor parent is hidden or visibility rules would hide it."
--[[Translation missing --]]
L["SETTING_SIZE"] = "Size"
--[[Translation missing --]]
L["SETTING_SIZE_MODE"] = "Size Mode"
--[[Translation missing --]]
L["SETTING_SIZE_MODE_DESC"] = [=[Choose how icons are sized and arranged.
'Overflow' uses a fixed icon size; extra icons wrap into overflow rows (horizontal) or columns (vertical).
'Max Per Row' uses a fixed number of icons per row or column.
'Fixed Width/Height' dynamically resizes square icons to fit the frame.
'Spread' spaces icons evenly across the frame.
'Stretch' stretches icons along the primary axis to fill the frame.]=]
--[[Translation missing --]]
L["SETTING_SKYRIDING_SHOW_SPEED"] = "Show Flight Speed"
--[[Translation missing --]]
L["SETTING_SKYRIDING_SHOW_SPEED_DESC"] = "Display your current flight speed on the vigor bar while skyriding."
--[[Translation missing --]]
L["SETTING_SKYRIDING_VIGOR"] = "Show Skyriding Vigor"
--[[Translation missing --]]
L["SETTING_SKYRIDING_VIGOR_DESC"] = "Replace the secondary resource bar with skyriding vigor charges while mounted on a skyriding mount. Charges glow lighter blue during Thrill of the Skies."
--[[Translation missing --]]
L["SETTING_SORT_RUNES"] = "Sort Runes"
--[[Translation missing --]]
L["SETTING_SORT_RUNES_DESC"] = "Group ready runes on the left and regenerating runes on the right, instead of showing them in slot order."
--[[Translation missing --]]
L["SETTING_SOUL_FRAG_DEV_COLOR"] = "Soul Fragment Color (Devourer)"
--[[Translation missing --]]
L["SETTING_SOUL_FRAG_DEV_COLOR_DESC"] = "Bar color for Devourer Demon Hunter Soul Fragment bar."
--[[Translation missing --]]
L["SETTING_SOUL_FRAG_VENG_COLOR"] = "Soul Fragment Color (Vengeance)"
--[[Translation missing --]]
L["SETTING_SOUL_FRAG_VENG_COLOR_DESC"] = "Bar color for Vengeance Demon Hunter Soul Fragment segments."
--[[Translation missing --]]
L["SETTING_SPEND_PREDICTION"] = "Show Spend Prediction"
--[[Translation missing --]]
L["SETTING_SPEND_PREDICTION_COLOR"] = "Spend Prediction Color"
--[[Translation missing --]]
L["SETTING_SPEND_PREDICTION_COLOR_DESC"] = "Color used for the overlay showing predicted mana cost during a cast."
--[[Translation missing --]]
L["SETTING_SPEND_PREDICTION_DESC"] = "Show an overlay on the mana bar previewing how much mana the current cast will consume."
--[[Translation missing --]]
L["SETTING_STACK_STRIP_SEGMENTED"] = "Split Stack Bars into Segments"
--[[Translation missing --]]
L["SETTING_STACK_STRIP_SEGMENTED_DESC"] = "Draw the stack bars u2014 Sweeping Strikes, Teachings of the Monastery, Shatter stacks, Wild Imps, Arcane Salvo and nearby Soul Fragments u2014 as one segment per stack. Turn this off to show a single continuous bar that fills as the stacks build instead."
--[[Translation missing --]]
L["SETTING_STACKS_TEXT"] = "Stacks Text"
--[[Translation missing --]]
L["SETTING_STAGGER_COLOR_HEAVY"] = "Stagger Color (Heavy)"
--[[Translation missing --]]
L["SETTING_STAGGER_COLOR_HEAVY_DESC"] = "Bar color when Stagger is at a heavy level."
--[[Translation missing --]]
L["SETTING_STAGGER_COLOR_LIGHT"] = "Stagger Color (Light)"
--[[Translation missing --]]
L["SETTING_STAGGER_COLOR_LIGHT_DESC"] = "Bar color when Stagger is at a light level."
--[[Translation missing --]]
L["SETTING_STAGGER_COLOR_MODERATE"] = "Stagger Color (Moderate)"
--[[Translation missing --]]
L["SETTING_STAGGER_COLOR_MODERATE_DESC"] = "Bar color when Stagger is at a moderate level."
--[[Translation missing --]]
L["SETTING_STAGGER_PIPS"] = "Stagger Threshold Markers"
--[[Translation missing --]]
L["SETTING_STAGGER_PIPS_DESC"] = "Show pip marks at 30% and 60% stagger thresholds with colored background sections."
--[[Translation missing --]]
L["SETTING_STATIC_BG"] = "Static Background Color"
--[[Translation missing --]]
L["SETTING_STATIC_BG_DESC"] = "Always use the background color below instead of deriving it from the active resource color."
--[[Translation missing --]]
L["SETTING_SUPPRESS_BUFF_ICON_SWAP"] = "Don't Override Icons on Procs"
--[[Translation missing --]]
L["SETTING_SUPPRESS_BUFF_ICON_SWAP_DESC"] = "Prevent buff/proc effects from swapping the spell icon. The original ability icon is always shown."
--[[Translation missing --]]
L["SETTING_SURVIVAL_TIP_OF_THE_SPEAR"] = "Show Tip of the Spear"
--[[Translation missing --]]
L["SETTING_SURVIVAL_TIP_OF_THE_SPEAR_DESC"] = "Show Tip of the Spear stack segments for Survival Hunters. Stacks are gained from Kill Command and consumed by other abilities for bonus damage. Requires the Tip of the Spear talent."
--[[Translation missing --]]
L["SETTING_SURVIVAL_TOTS_COLOR"] = "Tip of the Spear Color"
--[[Translation missing --]]
L["SETTING_SURVIVAL_TOTS_COLOR_DESC"] = "Bar color for Tip of the Spear stack segments."
--[[Translation missing --]]
L["SETTING_TEXT"] = "Text"
--[[Translation missing --]]
L["SETTING_TEXT_FORMAT"] = "Text Format"
--[[Translation missing --]]
L["SETTING_TEXT_FORMAT_DESC"] = "Choose what text to display on the health bar."
--[[Translation missing --]]
L["SETTING_TEXT_FORMAT_MANA"] = "Mana Text Format"
--[[Translation missing --]]
L["SETTING_TEXT_FORMAT_MANA_DESC"] = "Choose what text to display when the resource is mana."
--[[Translation missing --]]
L["SETTING_TEXT_FORMAT_OTHER"] = "Resource Text Format"
--[[Translation missing --]]
L["SETTING_TEXT_FORMAT_OTHER_DESC"] = "Choose what text to display for energy, rage, and other resources."
--[[Translation missing --]]
L["SETTING_TEXTURE"] = "Texture"
--[[Translation missing --]]
L["SETTING_TEXTURE_DEFAULT"] = "Default"
--[[Translation missing --]]
L["SETTING_TEXTURE_DESC"] = "Select a statusbar texture for the bar fill."
--[[Translation missing --]]
L["SETTING_TIMER_TEXT"] = "Timer Text"
--[[Translation missing --]]
L["SETTING_TRACK_INSTANT_CASTS"] = "Track Instant Casts"
--[[Translation missing --]]
L["SETTING_TRACK_INSTANT_CASTS_DESC"] = "Briefly show the global cooldown as a backward-draining cast bar when you cast an instant spell."
--[[Translation missing --]]
L["SETTING_TRACKED_ITEMS"] = "Tracked Items"
--[[Translation missing --]]
L["SETTING_VALUE_TEXT"] = "Value Text"
--[[Translation missing --]]
L["SETTING_VIGOR_COLOR"] = "Vigor Color"
--[[Translation missing --]]
L["SETTING_VIGOR_COLOR_DESC"] = "Bar color for Skyriding Vigor charges."
--[[Translation missing --]]
L["SETTING_VIGOR_THRILL_COLOR"] = "Vigor Thrill Color"
--[[Translation missing --]]
L["SETTING_VIGOR_THRILL_COLOR_DESC"] = "Bar color for Skyriding Vigor charges during Thrill of the Skies."
--[[Translation missing --]]
L["SETTING_VISIBILITY"] = "Visibility"
--[[Translation missing --]]
L["SETTING_VISIBILITY_DESC"] = [=[Controls the base visibility behavior.

Inherit: Follows the anchor parent chain (default).
Always: Visible at all times.
Auto: Follows Blizzard's cooldown viewer availability u2014 hidden in vehicles, pet battles, and other situations where the game hides the cooldown manager.
Hidden: Always hidden u2014 the component stays active but its frame is never shown. Use when routing output to additional frames.

Use Visibility Rules below to add conditional hide or fade effects.]=]
--[[Translation missing --]]
L["SETTING_VITALITY_COLOR"] = "Vitality Color"
--[[Translation missing --]]
L["SETTING_VITALITY_COLOR_DESC"] = "Bar color for the Vitality (Aspect of Harmony) bar."
--[[Translation missing --]]
L["SETTING_WARLOCK_SHARD_FRAGMENTS"] = "Show Soul Shard Fragments"
--[[Translation missing --]]
L["SETTING_WARLOCK_SHARD_FRAGMENTS_DESC"] = "Show the value text as a fractional Soul Shard count (e.g. 3.6) instead of whole shards. Requires Show Value. Affects Destruction Warlock only; other specs always generate whole shards."
--[[Translation missing --]]
L["SETTING_WARLOCK_SPEND_PREDICTION"] = "Show Spend Prediction"
--[[Translation missing --]]
L["SETTING_WARLOCK_SPEND_PREDICTION_DESC"] = "Grey out Soul Shard segments that will be consumed when casting a shard-spending spell, previewing the cost during the cast."
--[[Translation missing --]]
L["SETTING_WARLOCK_WILD_IMPS"] = "Show Wild Imps"
--[[Translation missing --]]
L["SETTING_WARLOCK_WILD_IMPS_COLOR"] = "Wild Imps Color"
--[[Translation missing --]]
L["SETTING_WARLOCK_WILD_IMPS_COLOR_DESC"] = "Bar color for the Wild Imp segments."
--[[Translation missing --]]
L["SETTING_WARLOCK_WILD_IMPS_DESC"] = "Demonology Warlocks only: add a second bar showing how many Wild Imps you currently command. 15 stacks, alongside your Soul Shards rather than replacing them."
--[[Translation missing --]]
L["SETTING_WIDTH"] = "Width"
--[[Translation missing --]]
L["SETTING_WIDTH_DESC"] = [=[Set the frame width in pixels.
Disabled when anchored in Percentage width mode or when Size Mode is set to Max Per Row.]=]
--[[Translation missing --]]
L["SETTING_WIDTH_MODE"] = "Size Mode"
--[[Translation missing --]]
L["SETTING_WIDTH_MODE_DESC"] = [=[Choose how size is determined when anchored.
Percentage scales from the anchor frame.
Absolute uses a fixed pixel size.]=]
--[[Translation missing --]]
L["SETTING_WIDTH_PCT"] = "Size %"
--[[Translation missing --]]
L["SETTING_WIDTH_PCT_DESC"] = [=[Scale this component's size as a percentage of its anchor frame.
Applies to width for top/bottom anchors, height for left/right anchors.]=]
--[[Translation missing --]]
L["SHAMAN_MANA_BAR"] = "Show Mana for Shaman"
--[[Translation missing --]]
L["SHAMAN_MANA_BAR_DESC"] = "Show the mana bar for Elemental and Enhancement Shamans even when Auto-Hide is enabled. Elemental's Maelstrom is shown on the Secondary Resources bar."
--[[Translation missing --]]
L["SOURCE_CONSUMABLES"] = "Consumables"
--[[Translation missing --]]
L["SOURCE_RACIALS"] = "Racials"
--[[Translation missing --]]
L["SOURCE_TRINKETS"] = "Trinkets"
--[[Translation missing --]]
L["SPEC_PROFILE_SYNC_DEFAULT"] = "Default Fallback"
--[[Translation missing --]]
L["SPEC_PROFILE_SYNC_DEFAULT_DESC"] = "Profile to use when no specialization or role mapping matches."
--[[Translation missing --]]
L["SPEC_PROFILE_SYNC_ENABLED"] = "Enable Auto-Switching"
--[[Translation missing --]]
L["SPEC_PROFILE_SYNC_ENABLED_DESC"] = "Automatically switch profiles when you change specialization."
--[[Translation missing --]]
L["SPEC_PROFILE_SYNC_GROUP_1"] = "Primary Talents"
--[[Translation missing --]]
L["SPEC_PROFILE_SYNC_GROUP_2"] = "Secondary Talents"
--[[Translation missing --]]
L["SPEC_PROFILE_SYNC_GROUP_DESC"] = "Assign a profile for this talent group. It is switched to when you activate the group (dual spec)."
--[[Translation missing --]]
L["SPEC_PROFILE_SYNC_GROUP_HEADER"] = "Talent Group"
--[[Translation missing --]]
L["SPEC_PROFILE_SYNC_HEADER"] = "Automatic Profile Switching"
--[[Translation missing --]]
L["SPEC_PROFILE_SYNC_ROLE_DESC"] = "Assign a profile based on your spec's role. Only used when no specialization mapping is set."
--[[Translation missing --]]
L["SPEC_PROFILE_SYNC_ROLE_HEADER"] = "Role Fallback"
--[[Translation missing --]]
L["SPEC_PROFILE_SYNC_SPEC_DESC"] = "Assign a profile for this specialization. Takes priority over role mappings."
--[[Translation missing --]]
L["SPEC_PROFILE_SYNC_SPEC_HEADER"] = "Specialization"
--[[Translation missing --]]
L["SPELL_ALREADY_ASSIGNED"] = "(assigned to %s)"
--[[Translation missing --]]
L["STACK_STRIP_NAME_ARCANE_SALVO"] = "Arcane Salvo"
--[[Translation missing --]]
L["STACK_STRIP_NAME_ART_OF_GLAIVE"] = "Art of the Glaive"
--[[Translation missing --]]
L["STACK_STRIP_NAME_NEARBY_SOULS"] = "Nearby Soul Fragments"
--[[Translation missing --]]
L["STACK_STRIP_NAME_SHATTER"] = "Shatter Stacks"
--[[Translation missing --]]
L["STACK_STRIP_NAME_SWEEPING_STRIKES"] = "Sweeping Strikes"
--[[Translation missing --]]
L["STACK_STRIP_NAME_TEACHINGS"] = "Teachings of the Monastery"
--[[Translation missing --]]
L["STACK_STRIP_NAME_UNBOUND_FLAME"] = "Unbound Flame"
--[[Translation missing --]]
L["STACK_STRIP_NAME_WILD_IMPS"] = "Wild Imps"
--[[Translation missing --]]
L["TAB_ABOUT"] = "About"
--[[Translation missing --]]
L["TAB_ADDITIONAL_TRACKERS"] = "Custom Trackers"
--[[Translation missing --]]
L["TAB_COLORS"] = "Colors"
--[[Translation missing --]]
L["TAB_GENERAL"] = "General"
--[[Translation missing --]]
L["TAB_IMPORT_EXPORT"] = "Import / Export"
--[[Translation missing --]]
L["TAB_PROFILE_MANAGEMENT"] = "Profile Management"
--[[Translation missing --]]
L["TAB_TRACKERS"] = "Trackers"
--[[Translation missing --]]
L["TAB_TRACKING"] = "Tracking"
--[[Translation missing --]]
L["TEXT_FORMAT_BOTH"] = "Both"
--[[Translation missing --]]
L["TEXT_FORMAT_CURRENT"] = "Current Value"
--[[Translation missing --]]
L["TEXT_FORMAT_NONE"] = "None"
--[[Translation missing --]]
L["TEXT_FORMAT_PERCENT"] = "Percentage"
--[[Translation missing --]]
L["THRESHOLD_COLORS_ADD"] = "Add"
--[[Translation missing --]]
L["THRESHOLD_COLORS_COLOR"] = "Color"
--[[Translation missing --]]
L["THRESHOLD_COLORS_EMPTY"] = "No thresholds configured for this spec."
--[[Translation missing --]]
L["THRESHOLD_COLORS_ENABLED"] = "Enable Threshold Colors"
--[[Translation missing --]]
L["THRESHOLD_COLORS_ENABLED_DESC"] = "Recolor secondary resource segments when the current count reaches configured thresholds. Settings are saved per specialization. Toggle to disable without deleting your setup."
--[[Translation missing --]]
L["THRESHOLD_COLORS_GLOBAL_ENABLED"] = "Enable (Global)"
--[[Translation missing --]]
L["THRESHOLD_COLORS_GLOBAL_ENABLED_DESC"] = "Master toggle for threshold color overrides. When off, thresholds are disabled for every spec regardless of the per-spec toggle."
--[[Translation missing --]]
L["THRESHOLD_COLORS_HEADER"] = "Resource Threshold Colors"
--[[Translation missing --]]
L["THRESHOLD_COLORS_MODE"] = "Color Mode"
--[[Translation missing --]]
L["THRESHOLD_COLORS_MODE_ALL"] = "All"
--[[Translation missing --]]
L["THRESHOLD_COLORS_MODE_ALL_PREVIOUS"] = "All Previous"
--[[Translation missing --]]
L["THRESHOLD_COLORS_MODE_DESC"] = "How many segments to recolor when this threshold is reached."
--[[Translation missing --]]
L["THRESHOLD_COLORS_MODE_SINGLE"] = "Single"
--[[Translation missing --]]
L["THRESHOLD_COLORS_REMOVE"] = "Remove"
--[[Translation missing --]]
L["THRESHOLD_COLORS_RESOURCE"] = "Applies To"
--[[Translation missing --]]
L["THRESHOLD_COLORS_RESOURCE_DESC"] = "Which bar this threshold recolors. Pick a stack bar to color that bar instead of your main resource."
--[[Translation missing --]]
L["THRESHOLD_COLORS_RESOURCE_PRIMARY"] = "Main Resource"
--[[Translation missing --]]
L["THRESHOLD_COLORS_SECRET_RESOURCE_HINT"] = "This resource supports only 'All' mode due to protected game state."
--[[Translation missing --]]
L["THRESHOLD_COLORS_SPEC_ENABLED"] = "Enable (This Spec)"
--[[Translation missing --]]
L["THRESHOLD_COLORS_SPEC_ENABLED_DESC"] = "Per-spec toggle. Only honored when the global toggle is enabled. Missing entries default to enabled."
--[[Translation missing --]]
L["THRESHOLD_COLORS_SPEC_LABEL"] = "Thresholds for %s"
--[[Translation missing --]]
L["THRESHOLD_COLORS_STACK_GLOW"] = "Animated Threshold Border"
--[[Translation missing --]]
L["THRESHOLD_COLORS_STACK_GLOW_DESC"] = "On stack strips (Arcane Salvo, Shatter, Wild Imps and the rest), draw a pulsing border in each threshold's color, which lights up the moment you reach that stack. With one threshold set, the whole bar is outlined. With several, each one owns a stretch of the border, so passing them lights the bar up section by section."
--[[Translation missing --]]
L["THRESHOLD_COLORS_STACK_HINT"] = "On stack bars the color mode shapes the Animated Threshold Border exactly: Single outlines just that segment, All Previous outlines up to it, All outlines the whole bar. The segment recolor can only follow Single exactly u2014 the game protects the stack count, so a segment can report that the count reached it and nothing else. Under All Previous and All the recolor falls back to coloring from the chosen stack upward, so it never colors a segment you have not earned. Segment recoloring also needs segmented stack bars; the border works either way."
--[[Translation missing --]]
L["THRESHOLD_COLORS_VALUE"] = "At Value"
--[[Translation missing --]]
L["THRESHOLD_COLORS_VALUE_DESC"] = "Segment index that triggers the color (1-based)."
--[[Translation missing --]]
L["TOOLTIP_ANCHOR"] = "Tooltip Anchor"
--[[Translation missing --]]
L["TOOLTIP_ANCHOR_CURSOR"] = "Cursor"
--[[Translation missing --]]
L["TOOLTIP_ANCHOR_DEFAULT"] = "Default"
--[[Translation missing --]]
L["TOOLTIP_ANCHOR_DESC"] = [=[Where the tooltip appears relative to the hovered icon.

Default: Blizzard's default position.
Cursor: Snaps to the cursor when hover begins.
Right of Icon: Anchored to the right edge of the icon.
Above Icon: Anchored above the icon.]=]
--[[Translation missing --]]
L["TOOLTIP_ANCHOR_RIGHT"] = "Right of Icon"
--[[Translation missing --]]
L["TOOLTIP_ANCHOR_TOP"] = "Above Icon"
--[[Translation missing --]]
L["TOOLTIP_AURA_SPELL_IDS"] = "Show Aura Spell IDs"
--[[Translation missing --]]
L["TOOLTIP_AURA_SPELL_IDS_DESC"] = [=[Show the spell ID on buff and debuff tooltips.
This is a Blizzard game setting, shared across all characters and profiles.]=]
--[[Translation missing --]]
L["TOOLTIP_LEFT_CLICK"] = "|cffaaaaaaLeft-click|r to open Edit Mode"
--[[Translation missing --]]
L["TOOLTIP_MODE"] = "Tooltip"
--[[Translation missing --]]
L["TOOLTIP_MODE_ALWAYS"] = "Always"
--[[Translation missing --]]
L["TOOLTIP_MODE_DESC"] = [=[Controls when hovering an icon shows the spell or item tooltip.

Always: Tooltip shows whenever you hover.
Out of Combat: Tooltip shows only outside combat u2014 hidden automatically when combat starts.
Off: No tooltip is shown.]=]
--[[Translation missing --]]
L["TOOLTIP_MODE_OFF"] = "Off"
--[[Translation missing --]]
L["TOOLTIP_MODE_OUT_OF_COMBAT"] = "Out of Combat"
--[[Translation missing --]]
L["TOOLTIP_RIGHT_CLICK"] = "|cffaaaaaaRight-click|r to open Options"
--[[Translation missing --]]
L["TRACKER_GROUP_CAST_BARS"] = "Cast Bars"
--[[Translation missing --]]
L["TRACKER_GROUP_ICON"] = "Icon Trackers"
--[[Translation missing --]]
L["TRACKER_GROUP_ITEMS"] = "Item Trackers"
--[[Translation missing --]]
L["TRACKER_GROUP_RESOURCES"] = "Resource Bars"
--[[Translation missing --]]
L["TRACKERS_EDIT_IN_TRACKING"] = "Edit spells in the Tracking tab"
--[[Translation missing --]]
L["TRACKERS_EDIT_IN_TRACKING_DESC"] = "Order, custom spells, per-spell active buff duration, pandemic glow exclusions, per-spell bar colors, missing glows and Track On for this tracker are set in the Tracking tab. Opens it on this tracker."
--[[Translation missing --]]
L["TRACKERS_HINT"] = "Component positioning is done in Edit Mode. Some options are mirrored here for convenience."
--[[Translation missing --]]
L["TRACKERS_SELECT_PROMPT"] = "Select a tracker from the list to configure it."
--[[Translation missing --]]
L["TRACKING_ACTIVE_SWIPE"] = "Show Active Buff Duration"
--[[Translation missing --]]
L["TRACKING_ACTIVE_SWIPE_DESC"] = "While this spell's buff is active, its icon shows the buff's remaining time. Uncheck to show only the cooldown for this spell. Has no effect while Hide Active Buff Duration is on for the whole display."
--[[Translation missing --]]
L["TRACKING_ADD_AURA"] = "Add aura by spell ID..."
--[[Translation missing --]]
L["TRACKING_ADD_AURA_EXISTS"] = "That spell is already in this list."
--[[Translation missing --]]
L["TRACKING_ADD_ITEM"] = "Add item..."
--[[Translation missing --]]
L["TRACKING_ADD_ITEM_DESC"] = "Add a trinket slot, a consumable category or a racial ability to this frame."
--[[Translation missing --]]
L["TRACKING_ADD_SPELL"] = "Add spell by spell ID..."
--[[Translation missing --]]
L["TRACKING_ALERT_ADD"] = "Add Alert"
--[[Translation missing --]]
L["TRACKING_ALERT_ADD_FULL_DESC"] = "A spell can have up to 3 alerts."
--[[Translation missing --]]
L["TRACKING_ALERT_EXISTS"] = "This spell already has that alert."
--[[Translation missing --]]
L["TRACKING_ALERT_SAMPLE"] = "Play Sample"
--[[Translation missing --]]
L["TRACKING_ALERT_SOUND"] = "Sound"
--[[Translation missing --]]
L["TRACKING_ALERT_VISUAL"] = "Visual"
--[[Translation missing --]]
L["TRACKING_ALERT_WHEN"] = "When"
--[[Translation missing --]]
L["TRACKING_ALERTS"] = "Alerts"
--[[Translation missing --]]
L["TRACKING_ALERTS_BLIZZARD_ONLY"] = "Played by the Cooldown Manager"
--[[Translation missing --]]
L["TRACKING_ALERTS_BLIZZARD_ONLY_DESC"] = "ClassUIEnhanced cannot play this alert, so Blizzard's Cooldown Manager plays it, whatever you set here. Change it in the Cooldown Manager's settings."
--[[Translation missing --]]
L["TRACKING_ALERTS_DESC"] = "Sound, text-to-speech and visual alerts for this spell. It starts with the alerts set in Blizzard's Cooldown Manager. Your first change makes it a list of its own, which ClassUIEnhanced plays instead of the Cooldown Manager's alerts for this spell. The icons on the button show which kinds of alert the spell has: a sound, a visual, or both."
--[[Translation missing --]]
L["TRACKING_ALERTS_DOUBLE"] = "The Cooldown Manager plays its alerts too"
--[[Translation missing --]]
L["TRACKING_ALERTS_DOUBLE_DESC"] = "Blizzard's Cooldown Manager is running, so it also plays the alerts it has for this spell, next to these. Only removing them in its own settings stops that."
--[[Translation missing --]]
L["TRACKING_ALERTS_FROM_CDM"] = "From the Cooldown Manager"
--[[Translation missing --]]
L["TRACKING_ALERTS_NONE"] = "No alerts"
--[[Translation missing --]]
L["TRACKING_ALERTS_NONE_DESC"] = "Only spells can have alerts here. Set alerts for items in Blizzard's Cooldown Manager."
--[[Translation missing --]]
L["TRACKING_ALERTS_OWN"] = "Set in ClassUIEnhanced"
--[[Translation missing --]]
L["TRACKING_ALERTS_RESET"] = "Reset to Cooldown Manager"
--[[Translation missing --]]
L["TRACKING_ALERTS_RESET_DESC"] = "Drop this spell's own list and play the Cooldown Manager's alerts for it again."
--[[Translation missing --]]
L["TRACKING_ALL_SPECS"] = "All specs"
--[[Translation missing --]]
L["TRACKING_ALL_SPECS_DESC"] = "Moving or removing a Cooldown Manager entry between trackers applies to your current specialization only. Tick this to apply it to every specialization instead; a specialization's own moves still win over it. Entries you have not learned always apply to every specialization. Moves into an Additional Frame always apply to every specialization. Arranging a tracker's icons also applies to your current specialization only; with this ticked you arrange the order every specialization without its own shares, and your current specialization switches to it. A custom aura you add shows on your current specialization only; tick this to add it for every specialization, or to put one back on every specialization with its This spec box."
--[[Translation missing --]]
L["TRACKING_BADGE_BY_NAME"] = "by name: %d"
--[[Translation missing --]]
L["TRACKING_BADGE_BY_NAME_PENDING"] = "by name: looking up"
--[[Translation missing --]]
L["TRACKING_BADGE_DUPLICATE"] = "duplicate"
--[[Translation missing --]]
L["TRACKING_BADGE_INACTIVE"] = "inactive"
--[[Translation missing --]]
L["TRACKING_BADGE_OTHER_SPEC"] = "not on this spec"
--[[Translation missing --]]
L["TRACKING_BADGE_SPELLBOOK"] = "in spellbook"
--[[Translation missing --]]
L["TRACKING_BADGE_UNLEARNED"] = "not learned"
--[[Translation missing --]]
L["TRACKING_BORDER_CLEAR"] = "Clear Border Color"
--[[Translation missing --]]
L["TRACKING_BORDER_CLEAR_DESC"] = "Go back to the icon border setting for this spell."
--[[Translation missing --]]
L["TRACKING_BORDER_COLOR"] = "Border Color"
--[[Translation missing --]]
L["TRACKING_BORDER_COLOR_DESC"] = "Give this spell's icon a border in a color of its own, even while the icon border is off for everything else. Its size and placement follow the icon border setting."
--[[Translation missing --]]
L["TRACKING_BY_NAME"] = "Match by name"
--[[Translation missing --]]
L["TRACKING_BY_NAME_DESC"] = "Show this aura for every spell with the same name, such as every rank of a buff, including ranks other players cast on you. The first time a name is used, the addon looks it up in the background, which can take a few seconds and pauses in combat."
--[[Translation missing --]]
L["TRACKING_CHANGE_ICON"] = "Change icon"
--[[Translation missing --]]
L["TRACKING_CHANGE_ICON_DESC"] = "Choose a different icon for this spell. It changes everywhere the spell is shown. Right-click to go back to the default icon."
--[[Translation missing --]]
L["TRACKING_COLLAPSE_ALL"] = "Collapse all"
--[[Translation missing --]]
L["TRACKING_COPY_EXISTS_AURA"] = "Already on an aura tracker"
--[[Translation missing --]]
L["TRACKING_COPY_EXISTS_COOLDOWN"] = "Already on a cooldown tracker"
--[[Translation missing --]]
L["TRACKING_COPY_TO"] = "Copy to"
--[[Translation missing --]]
L["TRACKING_EXPAND_ALL"] = "Expand all"
--[[Translation missing --]]
L["TRACKING_FORCE_ACTIVE"] = "Force Active"
--[[Translation missing --]]
L["TRACKING_FORCE_ACTIVE_DESC"] = "Show this entry although Blizzard's Cooldown Manager counts it inactive. Applies to every spec. A cooldown shows only while you have the spell."
--[[Translation missing --]]
L["TRACKING_FRAME_DISABLED"] = "(Disabled)"
--[[Translation missing --]]
L["TRACKING_ICON_HINT"] = "Left-click to choose a different icon. Right-click to go back to the default icon."
--[[Translation missing --]]
L["TRACKING_IN_SECTION"] = "In: %s"
--[[Translation missing --]]
L["TRACKING_INACTIVE_DESC"] = "You have this spell, but Blizzard's Cooldown Manager doesn't count this entry as active for your character, so no tracker shows it. On WoW Forever that is every rank below your highest. Tick Force Active to show it anyway (spell ranks use the Rank button instead)."
--[[Translation missing --]]
L["TRACKING_MISSING_GLOW"] = "Glow When Missing"
--[[Translation missing --]]
L["TRACKING_MISSING_GLOW_COLOR"] = "Missing Glow Color"
--[[Translation missing --]]
L["TRACKING_MISSING_GLOW_COLOR_DESC"] = "The color of this spell's missing glow."
--[[Translation missing --]]
L["TRACKING_MISSING_GLOW_DESC"] = "Glow around this icon while the buff or debuff is not up, and stop while it is. Tracked on the target, it glows only while you have a target: set Track On to Target for a debuff and to Player for a buff on yourself. A summon applies no aura, so it always glows."
--[[Translation missing --]]
L["TRACKING_MOVE_TO"] = "Move to"
--[[Translation missing --]]
L["TRACKING_NO_TARGETS"] = "There is no other place this entry can be moved to."
--[[Translation missing --]]
L["TRACKING_NOT_READY"] = "Cooldown Manager data not ready yet. This list fills in as soon as it is."
--[[Translation missing --]]
L["TRACKING_OPTIONS"] = "Options"
--[[Translation missing --]]
L["TRACKING_OPTIONS_DESC"] = "Settings for this spell only: active buff duration, pandemic glow, glow when missing, Track On, Only When Usable, This spec and Force Active, whichever apply here."
--[[Translation missing --]]
L["TRACKING_OPTIONS_NONE_DESC"] = "This entry has no settings of its own."
--[[Translation missing --]]
L["TRACKING_ORDER_LOCKED"] = "The game arranges this display itself while it hides inactive auras, so an order set here would have no effect. Turn on Always Show Tracked Auras to arrange it."
--[[Translation missing --]]
L["TRACKING_OTHER_SPEC_DESC"] = "Added on another specialization. Tick 'This spec' under Options to show it for this spec, too."
--[[Translation missing --]]
L["TRACKING_PANDEMIC_DESC"] = "Pandemic glow for this spell. Uncheck to leave it out of the display's pandemic glow."
--[[Translation missing --]]
L["TRACKING_POOL"] = "Not tracked"
--[[Translation missing --]]
L["TRACKING_POOL_AURAS"] = "Auras"
--[[Translation missing --]]
L["TRACKING_POOL_COOLDOWNS"] = "Cooldowns"
--[[Translation missing --]]
L["TRACKING_POOL_EMPTY"] = "Nothing here."
--[[Translation missing --]]
L["TRACKING_POOL_SPELLBOOK"] = "Spellbook"
--[[Translation missing --]]
L["TRACKING_POOL_STALE"] = "Saved, but not tracked on this spec"
--[[Translation missing --]]
L["TRACKING_RANK"] = "Rank"
--[[Translation missing --]]
L["TRACKING_RANK_ALL"] = "All ranks"
--[[Translation missing --]]
L["TRACKING_RANK_DESC"] = "Pick what this spell is tracked as. All ranks (buffs) shows one icon for whichever rank is on you; Highest (cooldowns) shows your highest learned rank and follows it as you learn new ones. Picking one rank tracks only that rank here, and the spell's other ranks here go to Not tracked. Moving or removing the row acts on what it shows."
--[[Translation missing --]]
L["TRACKING_RANK_FAMILY_CONFIRM"] = "Some ranks of %s are in %s. Move every rank here?"
--[[Translation missing --]]
L["TRACKING_RANK_HIGHEST"] = "Highest"
--[[Translation missing --]]
L["TRACKING_RANK_SINGLE_CONFIRM"] = "%s is in %s. Move it here? The spell's other ranks here go to Not tracked."
--[[Translation missing --]]
L["TRACKING_RANK_SWAP_CONFIRM"] = "%s is in %s. Move it here? The rank shown here now goes to Not tracked."
--[[Translation missing --]]
L["TRACKING_REF_active_swipe_excludes"] = "active buff duration exclusion"
--[[Translation missing --]]
L["TRACKING_REF_assigned_spells"] = "Additional Frame assignment"
--[[Translation missing --]]
L["TRACKING_REF_icon_overrides"] = "icon override"
--[[Translation missing --]]
L["TRACKING_REF_missing_glow"] = "missing glow"
--[[Translation missing --]]
L["TRACKING_REF_pandemic_glow_excludes"] = "pandemic glow exclusion"
--[[Translation missing --]]
L["TRACKING_REF_priority_order"] = "place in the icon order"
--[[Translation missing --]]
L["TRACKING_REF_spell_borders"] = "icon border color"
--[[Translation missing --]]
L["TRACKING_REF_spell_colors"] = "bar color"
--[[Translation missing --]]
L["TRACKING_REMOVE"] = "Remove"
--[[Translation missing --]]
L["TRACKING_REMOVE_ASSIGNED_DESC"] = "Take this entry out of this Additional Frame. It goes back to the tracker that normally shows it."
--[[Translation missing --]]
L["TRACKING_REMOVE_CDM_DESC"] = "Stop showing this entry in this tracker. It moves to Not tracked, and Move to brings it back."
--[[Translation missing --]]
L["TRACKING_REMOVE_CUSTOM_DESC"] = "Stop tracking this custom spell here."
--[[Translation missing --]]
L["TRACKING_REMOVE_NONE_DESC"] = "There is nothing to remove for this entry here."
--[[Translation missing --]]
L["TRACKING_REMOVE_STALE_DESC"] = "Forget what this profile still saves for this entry here: its place in the order, its assignment to this frame, its pandemic glow exclusion, its bar color, or its icon override."
--[[Translation missing --]]
L["TRACKING_RESET_MOVES"] = "Reset moves"
--[[Translation missing --]]
L["TRACKING_RESET_MOVES_DESC"] = "Undo every move made for your current specialization, for both trackers of this kind (cooldowns or buffs). With All specs ticked, undo the moves made for every specialization instead. An entry goes back to its All specs move if it has one, otherwise to where the game's Cooldown Manager files it."
--[[Translation missing --]]
L["TRACKING_SAVED_AS"] = "Saved: %s"
--[[Translation missing --]]
L["TRACKING_SHOW_UNLEARNED"] = "Show unlearned"
--[[Translation missing --]]
L["TRACKING_SHOW_UNLEARNED_DESC"] = "Also list entries this character does not currently have."
--[[Translation missing --]]
L["TRACKING_SPELL_COLOR_DESC"] = "Bar color for this spell. Click to choose one; right-click to go back to the bar color of the whole display. Dimmed while no color of its own is set."
--[[Translation missing --]]
L["TRACKING_THIS_SPEC"] = "This spec"
--[[Translation missing --]]
L["TRACKING_THIS_SPEC_DESC"] = "Show this custom aura on your current specialization. A custom aura shows on the specialization you added it on; tick this on another specialization to show it there too. With All specs ticked, ticking this shows it on every specialization again."
--[[Translation missing --]]
L["TRACKING_UNKNOWN_SPELL"] = "[unknown spell %d]"
--[[Translation missing --]]
L["TRINKET_SLOT_1"] = "Trinket 1"
--[[Translation missing --]]
L["TRINKET_SLOT_2"] = "Trinket 2"
--[[Translation missing --]]
L["USE_CLASS_COLOR"] = "Use Class Color"
--[[Translation missing --]]
L["USE_CLASS_COLOR_DESC"] = "When enabled, resources use the default class color. Disable to set custom colors per class."
--[[Translation missing --]]
L["VISIBILITY_ALWAYS"] = "Always"
--[[Translation missing --]]
L["VISIBILITY_AUTO"] = "Auto"
--[[Translation missing --]]
L["VISIBILITY_FADE_OPACITY"] = "Fade Opacity"
--[[Translation missing --]]
L["VISIBILITY_FADE_OPACITY_DESC"] = "Opacity level when a fade rule is active. Lower values mean more transparent."
--[[Translation missing --]]
L["VISIBILITY_HIDDEN"] = "Hidden"
--[[Translation missing --]]
L["VISIBILITY_INHERIT"] = "Inherit"
--[[Translation missing --]]
L["VISIBILITY_RULE_FADE"] = "Fade"
--[[Translation missing --]]
L["VISIBILITY_RULE_HIDE"] = "Hide"
--[[Translation missing --]]
L["VISIBILITY_RULE_MOUNTED"] = "When Mounted"
--[[Translation missing --]]
L["VISIBILITY_RULE_MOUNTED_DESC"] = "Action when mounted, in a vehicle, pet battle, on a taxi, or in a cinematic scene."
--[[Translation missing --]]
L["VISIBILITY_RULE_NO_TARGET"] = "No Target"
--[[Translation missing --]]
L["VISIBILITY_RULE_NO_TARGET_DESC"] = "Action when you have no target selected."
--[[Translation missing --]]
L["VISIBILITY_RULE_OFF"] = "Off"
--[[Translation missing --]]
L["VISIBILITY_RULE_OUT_OF_COMBAT"] = "Out of Combat"
--[[Translation missing --]]
L["VISIBILITY_RULE_OUT_OF_COMBAT_DESC"] = "Action when not in combat."
--[[Translation missing --]]
L["VISIBILITY_RULES"] = "Visibility Rules"
--[[Translation missing --]]
L["VISIBILITY_RULES_DESC"] = "Conditional rules that hide or fade this component based on game state. Multiple rules can be combined u2014 if any rule says Hide, the component is hidden; if any says Fade, it fades to the configured opacity."
--[[Translation missing --]]
L["WIDTH_MODE_ABSOLUTE"] = "Absolute"
--[[Translation missing --]]
L["WIDTH_MODE_PERCENT"] = "Percentage"
--[[Translation missing --]]
L["X"] = "X"
--[[Translation missing --]]
L["Y"] = "Y"


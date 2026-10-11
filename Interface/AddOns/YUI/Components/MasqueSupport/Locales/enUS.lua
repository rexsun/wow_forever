local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("enUS") then return end

YUI.Locale:Register("MasqueSupport", "enUS", {
    ["feature.name"] = "Masque Support",
    ["feature.description"] = "Adds Masque skinning support for Blizzard action bars and auras. Reload the UI after changes.",

    ["masque.group.action_bars"] = "Action Bars",
    ["masque.group.player_auras"] = "Player Auras",
    ["masque.group.target_buffs"] = "Target Buffs",
    ["masque.group.target_debuffs"] = "Target Debuffs",
    ["masque.group.unit_frame_buffs_debuffs"] = "Unit Frame Buffs/Debuffs",

    ["settings.blizzard_action_bars.label"] = "Blizzard Action Bars",
    ["settings.blizzard_action_bars.tooltip"] = "Enable Masque skinning for Blizzard action bars. Group: Blizzard > Action Bars.",
    ["settings.blizzard_auras.label"] = "Blizzard Auras",
    ["settings.blizzard_auras.tooltip"] = "Enable Masque skinning for Blizzard buffs/debuffs. Groups: Blizzard > Player Auras / Target Buffs / Target Debuffs; EQoL unit frame auras use EnhanceQoL > Unit Frame Buffs/Debuffs.",
    ["settings.reload_note"] = "Tip: after checking or unchecking, close settings and reload the UI for changes to take effect; skins from old groups are not migrated, so reselect them under the new Blizzard / EnhanceQoL groups.",
})

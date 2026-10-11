local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("deDE") then return end

YUI.Locale:Register("MasqueSupport", "deDE", {
    ["feature.name"] = "Masque-Unterstützung",
    ["feature.description"] = "Aktiviert Masque-Skins für Blizzard-Aktionsleisten und Auren.",
    ["masque.group.action_bars"] = "Aktionsleisten",
    ["masque.group.player_auras"] = "Spieler Auras",
    ["masque.group.target_buffs"] = "Target Buffs",
    ["masque.group.target_debuffs"] = "Target Debuffs",
    ["masque.group.unit_frame_buffs_debuffs"] = "Unit Frame Buffs/Debuffs",

    ["settings.blizzard_action_bars.label"] = "Blizzard Action Bars",
    ["settings.blizzard_action_bars.tooltip"] = "Aktivieren Sie Masque Skinning für Blizzard-Aktionsleisten.",
    ["settings.blizzard_auras.label"] = "Blizzard Auras",
    ["settings.blizzard_auras.tooltip"] = "Aktivieren Sie Masque Skinning für Blizzard Buffs/debuffs. Gruppen: Blizzard > Player Auras / Target Buffs / Target Debuffs; EQoL Unit Frame Auras verwenden EnhanceQoL > Unit Frame Buffs/Debuffs.",
    ["settings.reload_note"] = "Tipp: Schließen Sie nach dem Überprüfen oder Deaktivieren die Einstellungen und laden Sie die Benutzeroberfläche neu, damit Änderungen wirksam werden; Skins aus alten Gruppen werden nicht migriert, also wählen Sie sie unter den neuen Blizzard / EnhanceQoL-Gruppen neu aus.",
})

local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("esMX") then return end

YUI.Locale:Register("MasqueSupport", "esMX", {
    ["feature.name"] = "Compatibilidad con Masque",
    ["feature.description"] = "Permite aplicar diseños de Masque a barras de acción y auras de Blizzard.",
    ["masque.group.action_bars"] = "Barras de acción",
    ["masque.group.player_auras"] = "Jugador Auras",
    ["masque.group.target_buffs"] = "Blanco Buffs",
    ["masque.group.target_debuffs"] = "Deudas de blanco",
    ["masque.group.unit_frame_buffs_debuffs"] = "Unidad Frame Buffs/Debuffs",

    ["settings.blizzard_action_bars.label"] = "Blizzard Action Bars",
    ["settings.blizzard_action_bars.tooltip"] = "Enable Másque para barritas de acción de Blizzard. Grupo: Blizzard  Confeccionar Bares de acción.",
    ["settings.blizzard_auras.label"] = "Blizzard Auras",
    ["settings.blizzard_auras.tooltip"] = "Habilitar el despilfarro de máscaras para Blizzard Buffs/debuffs. Grupos: Blizzard но Player Auras / Target Buffs / Target Debuffs; EQoL unit frame auras use EnhanceQoL ≤ Unit Frame Buffs/Debuffs.",
    ["settings.reload_note"] = "Sugerencia: después de comprobar o desmarque, cerrar ajustes y recargar la UI para que los cambios surtan efecto; las pieles de grupos antiguos no son migradas, así que reeléctelas bajo los nuevos grupos Blizzard / EnhanceQoL.",
})

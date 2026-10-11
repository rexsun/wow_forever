local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("ptBR") then return end

YUI.Locale:Register("MasqueSupport", "ptBR", {
    ["feature.name"] = "Suporte ao Masque",
    ["feature.description"] = "Permite aplicar skins do Masque às barras de ação e auras da Blizzard.",
    ["masque.group.action_bars"] = "Barras de ação",
    ["masque.group.player_auras"] = " Jogador Auras",
    ["masque.group.target_buffs"] = " Alvo Buffs",
    ["masque.group.target_debuffs"] = " Alvo Debuffs",
    ["masque.group.unit_frame_buffs_debuffs"] = " Unidade Frame Buffs/Debuffs",

    ["settings.blizzard_action_bars.label"] = "Bares de Ação Blizzard",
    ["settings.blizzard_action_bars.tooltip"] = "Activar o esfolamento do masque para barras de ação da Blizzard. Grupo: Blizzard > Barras de ação.",
    ["settings.blizzard_auras.label"] = "Blizzard Auras",
    ["settings.blizzard_auras.tooltip"] = "Activar o esfolamento masque para os entusiastas da Blizzard/debuffs. Grupos: Blizzard > Player Auras / Target Buffs / Target Debuffs; EQoL unit frame auras use EnhanceQoL > Unit Frame Buffs/Debuffs.",
    ["settings.reload_note"] = "Dica: após verificar ou desmarcar, feche as configurações e recarregue a interface para que as alterações façam efeito; skins de grupos antigos não são migrados, então reselecione-os sob os novos grupos Blizzard / EnhanceQoL.",
})

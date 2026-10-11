local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("itIT") then return end

YUI.Locale:Register("MasqueSupport", "itIT", {
    ["feature.name"] = "Supporto Masque",
    ["feature.description"] = "Consente le skin Masque per barre delle azioni e aure di Blizzard.",
    ["masque.group.action_bars"] = "Barre delle azioni",
    ["masque.group.player_auras"] = "Giocatore Auras",
    ["masque.group.target_buffs"] = "Potenziamenti",
    ["masque.group.target_debuffs"] = "Debito mirato",
    ["masque.group.unit_frame_buffs_debuffs"] = "Unità telaio Buffs/Debuffs",

    ["settings.blizzard_action_bars.label"] = "Blizzard Action Bar",
    ["settings.blizzard_action_bars.tooltip"] = "Abilitare la maschera per barre di azione Blizzard. Gruppo: Blizzard > Azione Bar.",
    ["settings.blizzard_auras.label"] = "Blizzard Auras",
    ["settings.blizzard_auras.tooltip"] = "Abilitare la maschera per Blizzard buffs/debuffs. Gruppi: Blizzard > Player Auras / Target Buffs / Target Debuffs; EQoL unità frame auras utilizzare EnhanceQoL > Unità Buffs/Debuffs.",
    ["settings.reload_note"] = "Suggerimento: dopo aver controllato o deselezionato, chiudere le impostazioni e ricaricare l'interfaccia utente per le modifiche da prendere effetto; le pelli di vecchi gruppi non sono migrate, quindi le riscuote sotto i nuovi gruppi Blizzard / EnhanceQoL.",
})

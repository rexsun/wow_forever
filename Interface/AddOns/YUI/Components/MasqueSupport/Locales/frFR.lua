local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("frFR") then return end

YUI.Locale:Register("MasqueSupport", "frFR", {
    ["feature.name"] = "Prise en charge de Masque",
    ["feature.description"] = "Permet d’appliquer les apparences Masque aux barres d’action et auras de Blizzard.",
    ["masque.group.action_bars"] = "Barres d’action",
    ["masque.group.player_auras"] = "Joueur Auras",
    ["masque.group.target_buffs"] = "Cibler les Buffs",
    ["masque.group.target_debuffs"] = "Ciblez les débris",
    ["masque.group.unit_frame_buffs_debuffs"] = "Unit Frame Buffs/Debuffs ",

    ["settings.blizzard_action_bars.label"] = " Barres d'action Blizzard",
    ["settings.blizzard_action_bars.tooltip"] = "Activer la peau Masque pour les barres d'action Blizzard. Groupe: Blizzard > Barres d'action.",
    ["settings.blizzard_auras.label"] = "Auras Blizzard",
    ["settings.blizzard_auras.tooltip"] = "Activer le skinning Masque pour les buffs Blizzard/debuffs. Groupes: Blizzard > Player Auras / Target Buffs / Target Debuffs; EQoL unit frame auras utiliser EnhanceQoL > Unit frame Buffs/Debuffs.",
    ["settings.reload_note"] = "Astuce : après avoir vérifié ou décoché, fermez les paramètres et rechargez l'interface utilisateur pour que les changements prennent effet; les peaux des anciens groupes ne sont pas migrées, donc réélectionnez-les sous les nouveaux groupes Blizzard / EnhanceQoL.",
})

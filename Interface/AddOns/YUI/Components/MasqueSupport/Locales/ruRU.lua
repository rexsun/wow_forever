local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("ruRU") then return end

YUI.Locale:Register("MasqueSupport", "ruRU", {
    ["feature.name"] = "Поддержка Masque",
    ["feature.description"] = "Применяет оформление Masque к панелям команд и аурам Blizzard.",
    ["masque.group.action_bars"] = "Панели команд",
    ["masque.group.player_auras"] = "Игрок Ауры",
    ["masque.group.target_buffs"] = "Цель Баффс",
    ["masque.group.target_debuffs"] = "Таргет Дебаффс",
    ["masque.group.unit_frame_buffs_debuffs"] = "Подразделение Frame Buffs/Debuffs",

    ["settings.blizzard_action_bars.label"] = "Blizzard Action Bars",
    ["settings.blizzard_action_bars.tooltip"] = "Включите маскирование для экшн-баров Blizzard. Group: Blizzard > Action Bars.",
    ["settings.blizzard_auras.label"] = "Blizzard Auras",
    ["settings.blizzard_auras.tooltip"] = "Включите маскировку для Blizzard buffs/debuffs. Группы: Blizzard > Player Auras / Target Buffs / Target Debuffs; EQoL unit frame auras используют EnhanceQoL > Unit Frame Buffs/Debuffs.",
    ["settings.reload_note"] = "Совет: после проверки или отмены проверки закройте настройки и перезагрузите пользовательский интерфейс для внесения изменений; скины из старых групп не мигрируют, поэтому переизберите их под новые группы Blizzard / EnhanceQoL.",
})

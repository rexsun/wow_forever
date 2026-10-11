local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("ruRU") then return end

YUI.Locale:Register("SocialEnhancement", "ruRU", {
    ["feature.name"] = "Социальные функции",
    ["feature.description"] = "Улучшает выбор цели клавишей Tab и действия в меню игрока.",
    ["settings.tab_cycle"] = "Используйте Tab/Shift+Tab для циклического чата",
    ["settings.tab_cycle.tooltip"] = "Циклы с помощью поддерживаемых групп, гильдий и чат-мишеней без изменения входного текста.",
    ["settings.tab_cycle.ychat"] = "Переключением таб-целей управляет YChat.",
    ["settings.right_click"] = "Улучшите меню правого клика игрока",
    ["settings.right_click.tooltip"] = "Добавляет действия друга и гильдии в поддерживаемые меню игроков.",
    ["settings.right_click.conflict"] = "Недоступен, поскольку этим меню управляет другой аддон интерфейса.",
    ["menu.add_friend"] = "Добавь друга",
    ["menu.invite_guild"] = "Пригласите Гильдию",
})

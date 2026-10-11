local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("ruRU") then return end

YUI.Locale:Register("RightPlus", "ruRU", {
    ["feature.name"] = "Действия контекстного меню",
    ["feature.description"] = "Добавляет действия друзей и гильдии в контекстные меню игроков.",
})

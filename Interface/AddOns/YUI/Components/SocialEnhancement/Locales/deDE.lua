local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("deDE") then return end

YUI.Locale:Register("SocialEnhancement", "deDE", {
    ["feature.name"] = "Soziale Funktionen",
    ["feature.description"] = "Erweitert Zielwechsel per Tab und optionale Aktionen in Spielermenüs.",
    ["settings.tab_cycle"] = "Verwenden Sie Tab / Shift + Tab zum Zyklus Chat-Ziele",
    ["settings.tab_cycle.tooltip"] = "Durchläuft unterstützte gruppen-, zunft- und world-chat-ziele, ohne den eingabetext zu ändern.",
    ["settings.tab_cycle.ychat"] = "Tab-Zielwechsel wird von YChat verwaltet.",
    ["settings.right_click"] = "Verbessern Sie die Player-Rechtsklick-Menüs",
    ["settings.right_click.tooltip"] = "Fügt freund- und gildeneinladungsaktionen zu den unterstützten spielermenüs.",
    ["settings.right_click.conflict"] = "Nicht verfügbar, da ein anderes Interface-Addon diese Menüs verwaltet.",
    ["menu.add_friend"] = "Fügen Sie Freund hinzu",
    ["menu.invite_guild"] = "Laden Sie zu Guild",
})

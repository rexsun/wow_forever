local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("deDE") then return end

YUI.Locale:Register("RightPlus", "deDE", {
    ["feature.name"] = "Kontextmenü-Aktionen",
    ["feature.description"] = "Ergänzt Freund- und Gildenaktionen in Spieler-Kontextmenüs.",
})

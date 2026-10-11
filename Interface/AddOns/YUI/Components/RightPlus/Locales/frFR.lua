local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("frFR") then return end

YUI.Locale:Register("RightPlus", "frFR", {
    ["feature.name"] = "Actions du menu contextuel",
    ["feature.description"] = "Ajoute les actions d’ami et de guilde aux menus contextuels des joueurs.",
})

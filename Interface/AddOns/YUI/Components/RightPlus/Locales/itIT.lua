local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("itIT") then return end

YUI.Locale:Register("RightPlus", "itIT", {
    ["feature.name"] = "Azioni del menu contestuale",
    ["feature.description"] = "Aggiunge azioni per amici e gilda ai menu contestuali dei giocatori.",
})

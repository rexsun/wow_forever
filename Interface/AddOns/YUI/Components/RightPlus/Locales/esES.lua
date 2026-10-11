local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("esES") then return end

YUI.Locale:Register("RightPlus", "esES", {
    ["feature.name"] = "Acciones del menú contextual",
    ["feature.description"] = "Añade acciones de amistad y hermandad a los menús de jugador.",
})

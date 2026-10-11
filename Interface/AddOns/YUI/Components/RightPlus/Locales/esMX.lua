local YUI = _G.YUI

if YUI.Locale.ShouldLoad and not YUI.Locale:ShouldLoad("esMX") then return end

YUI.Locale:Register("RightPlus", "esMX", {
    ["feature.name"] = "Acciones del menú contextual",
    ["feature.description"] = "Agrega acciones de amistad y hermandad a los menús de jugador.",
})

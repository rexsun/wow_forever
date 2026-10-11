local YHUD = _G.YUI and _G.YUI.YHUD
local Catalog = YHUD and YHUD.ResourceCatalog
if not Catalog then return end

Catalog:RegisterClassPack("PALADIN", {
    [65] = { "mana", "holyPower" },
    [66] = { "mana", "holyPower" },
    [70] = { "mana", "holyPower", "remoteStrike" },
})

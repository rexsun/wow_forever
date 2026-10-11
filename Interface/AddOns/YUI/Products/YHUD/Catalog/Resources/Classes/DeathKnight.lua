local YHUD = _G.YUI and _G.YUI.YHUD
local Catalog = YHUD and YHUD.ResourceCatalog
if not Catalog then return end

Catalog:RegisterClassPack("DEATHKNIGHT", {
    [250] = { "runicPower", "runes" },
    [251] = { "runicPower", "runes" },
    [252] = { "runicPower", "runes" },
})

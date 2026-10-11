local YHUD = _G.YUI and _G.YUI.YHUD
local Catalog = YHUD and YHUD.ResourceCatalog
if not Catalog then return end

Catalog:RegisterClassPack("ROGUE", {
    [259] = { "energy", "comboPoints" },
    [260] = { "energy", "comboPoints" },
    [261] = { "energy", "comboPoints" },
})

local YHUD = _G.YUI and _G.YUI.YHUD
local Catalog = YHUD and YHUD.ResourceCatalog
if not Catalog then return end

Catalog:RegisterClassPack("EVOKER", {
    [1467] = { "essence" },
    [1468] = { "mana", "essence" },
    [1473] = { "essence", "ebonMight" },
})

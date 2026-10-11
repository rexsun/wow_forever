local YHUD = _G.YUI and _G.YUI.YHUD
local Catalog = YHUD and YHUD.ResourceCatalog
if not Catalog then return end

Catalog:RegisterClassPack("PRIEST", {
    [256] = { "mana" },
    [257] = { "mana" },
    [258] = { "mana", "insanity" },
})

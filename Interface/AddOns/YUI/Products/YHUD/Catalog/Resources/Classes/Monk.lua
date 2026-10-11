local YHUD = _G.YUI and _G.YUI.YHUD
local Catalog = YHUD and YHUD.ResourceCatalog
if not Catalog then return end

Catalog:RegisterClassPack("MONK", {
    [268] = { "energy", "stagger" },
    [269] = { "energy", "chi" },
    [270] = { "mana" },
})

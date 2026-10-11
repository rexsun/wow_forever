local YHUD = _G.YUI and _G.YUI.YHUD
local Catalog = YHUD and YHUD.ResourceCatalog
if not Catalog then return end

Catalog:RegisterClassPack("WARRIOR", {
    [71] = { "rage", "sweepingStrikes" },
    [72] = { "rage", "enrage", "whirlwindStacks" },
    [73] = { "rage", "ignorePain" },
})

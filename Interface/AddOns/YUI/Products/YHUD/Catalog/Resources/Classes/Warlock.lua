local YHUD = _G.YUI and _G.YUI.YHUD
local Catalog = YHUD and YHUD.ResourceCatalog
if not Catalog then return end

Catalog:RegisterClassPack("WARLOCK", {
    [265] = { "mana", "soulShards" },
    [266] = { "mana", "soulShards", "demonicCore" },
    [267] = { "mana", "soulShards" },
})

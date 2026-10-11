local YHUD = _G.YUI and _G.YUI.YHUD
local Catalog = YHUD and YHUD.ResourceCatalog
if not Catalog then return end

Catalog:RegisterClassPack("MAGE", {
    [62] = { "mana", "arcaneCharges", "arcaneSalvo" },
    [63] = { "mana", "fireBlastCharges" },
    [64] = { "mana", "frozen", "icicles" },
})

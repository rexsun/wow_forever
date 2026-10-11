local YHUD = _G.YUI and _G.YUI.YHUD
local Catalog = YHUD and YHUD.ResourceCatalog
if not Catalog then return end

Catalog:RegisterClassPack("DEMONHUNTER", {
    [577] = { "fury" },
    [581] = { "fury", "vengeanceSoulFragments" },
    [1480] = { "mana", "fury", "devourerSoulFragments" },
})

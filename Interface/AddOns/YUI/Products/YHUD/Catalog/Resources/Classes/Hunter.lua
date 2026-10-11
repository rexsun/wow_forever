local YHUD = _G.YUI and _G.YUI.YHUD
local Catalog = YHUD and YHUD.ResourceCatalog
if not Catalog then return end

Catalog:RegisterClassPack("HUNTER", {
    [253] = { "focus" },
    [254] = { "focus" },
    [255] = { "focus", "tipOfTheSpear" },
})

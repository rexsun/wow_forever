local YHUD = _G.YUI and _G.YUI.YHUD
local Catalog = YHUD and YHUD.ResourceCatalog
if not Catalog then return end

Catalog:RegisterClassPack("SHAMAN", {
    [262] = { "mana", "maelstrom" },
    [263] = { "mana", "maelstromWeapon" },
    [264] = { "mana" },
})

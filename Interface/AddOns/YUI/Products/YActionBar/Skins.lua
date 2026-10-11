local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

local YAB = YUI.YActionBar
local Skins = {}
YAB.Skins = Skins

Skins.DEFAULT = "default"

Skins.aliases = {
    ["native"] = "default",
    ["yui-default"] = "default",
    ["minimal"] = "default",
    ["circle"] = "default",
    ["hex"] = "default",
}

Skins.registry = {
    ["default"] = {
        label = "默认",
        iconZoom = 0.08,
        padding = 2,
        surface = "color.surface.sunken",
        border = "color.border.default",
        hoverSurface = "color.control.hover",
        hoverBorder = "color.border.default",
        pressedSurface = "color.control.active",
        activeBorder = "color.border.default",
        emptySurface = "color.control.bg",
        disabledBorder = "color.border.subtle",
        noManaBorder = "color.state.info",
        outOfRangeBorder = "color.state.error",
        normalIconColor = { 1, 1, 1, 1 },
        outOfRangeIconColor = { 0.62, 0.06, 0.04, 1 },
        unusableIconColor = { 0.32, 0.32, 0.32, 1 },
        noManaIconColor = { 0.48, 0.62, 1, 1 },
        outOfRangeTextColor = { 1, 0.18, 0.12, 1 },
        cooldownDesaturation = 1,
        text = "color.text.primary",
        mutedText = "color.text.secondary",
    },
}

function Skins:Normalize(skinId)
    skinId = tostring(skinId or self.DEFAULT)
    skinId = self.aliases[skinId] or skinId
    if not self.registry[skinId] then
        return self.DEFAULT
    end
    return skinId
end

function Skins:GetDefinition(skinId)
    return self.registry[self:Normalize(skinId)] or self.registry[self.DEFAULT]
end

function Skins:GetOptions()
    local def = self.registry[self.DEFAULT]
    return { { text = def.label, value = self.DEFAULT } }
end

function Skins:ApplyButton(button, skinId, options)
    if not button then return end
    skinId = self:Normalize(skinId)
    if YAB.Visuals and YAB.Visuals.ApplyButton then
        return YAB.Visuals:ApplyButton(button, skinId, options)
    end
    return false
end

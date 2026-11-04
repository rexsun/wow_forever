local YUI = _G.YUI
local GUI2 = YUI.GUI2
local managed = setmetatable({}, { __mode = "k" })

local function SyncVisibility(icon)
    local state = icon.gui2UIIcon
    local shown = state.active and icon:IsShown()
    state.shine:SetShown(shown)
    state.effect:SetShown(shown and state.effectFits)
end

local function SyncAlpha(icon)
    local state = icon.gui2UIIcon
    if not state.active then return end
    local alpha = icon:GetAlpha()
    state.shine:SetAlpha(alpha)
    state.effect:SetAlpha(alpha)
end

local function SyncCoordinates(icon, ...)
    local state = icon.gui2UIIcon
    if not state.active then return end
    state.shine:SetTexCoord(...)
    state.effect:SetTexCoord(...)
end

local function SyncParent(icon)
    local state = icon.gui2UIIcon
    if not state.active then return end
    state.effect:SetParent(icon:GetParent())
    state.shine:SetParent(icon:GetParent())
end

local function SyncLayer(icon)
    local state = icon.gui2UIIcon
    if not state.active then return end
    local layer, level = icon:GetDrawLayer()
    level = level or 0
    -- Never change the caller's layer. At the lowest sublevel the dark
    -- effect cannot sit underneath; omit it rather than cover the body.
    state.effectFits = level > -8
    state.effect:SetDrawLayer(layer, math.max(-8, level - 1))
    state.shine:SetDrawLayer(layer, math.min(7, level + 1))
    SyncVisibility(icon)
end

local function SourceChanged(icon, source)
    GUI2:ApplyUIIconEffect(icon, source)
end

local function AtlasChanged(icon)
    GUI2:ApplyUIIconEffect(icon)
end

function GUI2:ApplyUIIconEffect(icon, source)
    local name = type(source) == "string" and source:match("[\\/]gui2[\\/]icons[\\/]ui[\\/]([%w%-]+)%-64%.png$")
    if name and self:GetUIIcon(name) ~= source then name = nil end
    local state = icon.gui2UIIcon
    if not name then
        if state then
            state.active = false
            managed[icon] = nil
            SyncVisibility(icon)
        end
        return
    end
    if state and state.active and state.source == source then return end

    if not state then
        local parent = icon:GetParent()
        state = { effect = parent:CreateTexture(nil, "ARTWORK"), shine = parent:CreateTexture(nil, "ARTWORK") }
        icon.gui2UIIcon = state
        for _, texture in ipairs({state.effect, state.shine}) do
            self:ApplyTexturePixelPolicy(texture)
            texture:SetAllPoints(icon)
        end
        -- Only shared artwork gets hooks. These bounded texture updates never
        -- install an OnUpdate, a theme listener or a per-icon event subscription.
        hooksecurefunc(icon, "SetTexture", SourceChanged)
        hooksecurefunc(icon, "SetAtlas", AtlasChanged)
        hooksecurefunc(icon, "SetAlpha", SyncAlpha)
        hooksecurefunc(icon, "SetVertexColor", SyncAlpha)
        hooksecurefunc(icon, "SetTexCoord", SyncCoordinates)
        hooksecurefunc(icon, "SetDrawLayer", SyncLayer)
        hooksecurefunc(icon, "SetParent", SyncParent)
        hooksecurefunc(icon, "Show", SyncVisibility)
        hooksecurefunc(icon, "Hide", SyncVisibility)
        hooksecurefunc(icon, "SetShown", SyncVisibility)
    end
    state.active = true
    managed[icon] = true
    if state.source ~= source then
        state.effect:SetTexture((source:gsub("%-64%.png$", "-64-effect.png")))
        state.shine:SetTexture((source:gsub("%-64%.png$", "-64-shine.png")))
        state.source = source
    end
    SyncParent(icon)
    SyncLayer(icon)
    SyncCoordinates(icon, icon:GetTexCoord())
    SyncAlpha(icon)
    SyncVisibility(icon)
end

function GUI2:RefreshUIIconEffects()
    for icon in pairs(managed) do SyncVisibility(icon) end
end

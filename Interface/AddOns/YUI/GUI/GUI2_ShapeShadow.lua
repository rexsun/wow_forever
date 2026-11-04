local YUI = _G.YUI
local GUI2 = YUI and YUI.GUI2
if not GUI2 then return end

local Assets = YUI.Assets
local issecretvalue = _G.issecretvalue
local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function Number(value, fallback)
    if IsSecret(value) then return fallback end
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return fallback end
    return value
end

local function Component(value, fallback)
    return math.max(0, math.min(1, Number(value, fallback)))
end

local bindings = setmetatable({}, { __mode = "k" })
local hookedFrames = setmetatable({}, { __mode = "k" })

local function InCombat()
    local combat = YUI.API and (YUI.API.Combat or YUI.API.Security)
    local query = combat and (combat.InCombatLockdown or combat.InCombat)
    return query and query() or (_G.InCombatLockdown and _G.InCombatLockdown()) or false
end

local function HideTexture(handle)
    if not handle.shown then return 0 end
    handle.texture:Hide()
    handle.shown = false
    return 1
end

GUI2.ShapeShadowDefaults = { color = { 0, 0, 0, 0.5 } }

-- Eight outside slices keep the blur width independent of a bar's aspect ratio.
-- No centre slice: adjacent bars retain their own track/background colours.
local rectSlices = {
    { "BOTTOMRIGHT", "TOPLEFT", 0, 0, 0, 0.125, 0, 0.125 },
    { "BOTTOMLEFT", "TOPRIGHT", 0, 0, 0.875, 1, 0, 0.125 },
    { "TOPRIGHT", "BOTTOMLEFT", 0, 0, 0, 0.125, 0.875, 1 },
    { "TOPLEFT", "BOTTOMRIGHT", 0, 0, 0.875, 1, 0.875, 1 },
    { "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT", 0.49, 0.51, 0, 0.125 },
    { "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT", 0.49, 0.51, 0.875, 1 },
    { "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT", 0, 0.125, 0.49, 0.51 },
    { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", 0.875, 1, 0.49, 0.51 },
}

function GUI2:CreateRectShadow(parent)
    if not parent or not parent.CreateTexture or (parent.IsForbidden and parent:IsForbidden()) then return nil end
    local handle = { textures = {}, shown = false }
    for index, slice in ipairs(rectSlices) do
        local texture = parent:CreateTexture(nil, "BACKGROUND", nil, -8)
        texture:SetTexture(Assets:Core("gui2\\shapes\\shadow-square.tga"))
        texture:SetTexCoord(slice[5], slice[6], slice[7], slice[8])
        texture:SetBlendMode("BLEND")
        if self.ApplyTexturePixelPolicy then self:ApplyTexturePixelPolicy(texture) end
        texture:Hide()
        handle.textures[index] = texture
    end
    return handle
end

function GUI2:HideRectShadow(handle)
    if not handle or not handle.shown then return 0 end
    for _, texture in ipairs(handle.textures) do texture:Hide() end
    handle.shown = false
    return 8
end

-- Anchors follow the complete public contour, never the changing fill texture.
function GUI2:ApplyRectShadow(handle, style, anchor)
    if not handle then return 0 end
    if not style or IsSecret(style.enabled) or style.enabled ~= true
        or IsSecret(anchor) or not anchor then return self:HideRectShadow(handle) end
    local color = not IsSecret(style.color) and type(style.color) == "table" and style.color or {}
    local r, g, b, a = Component(color[1], 0), Component(color[2], 0), Component(color[3], 0), Component(color[4], 0.5)
    if a <= 0 then return self:HideRectShadow(handle) end
    local extent = math.max(1, math.min(12, Number(style.extent, 4)))
    local geometryChanged = handle.anchor ~= anchor or handle.extent ~= extent
    local colorChanged = handle.r ~= r or handle.g ~= g or handle.b ~= b or handle.a ~= a
    local writes = 0
    for index, texture in ipairs(handle.textures) do
        if geometryChanged then
            local slice = rectSlices[index]
            texture:ClearAllPoints()
            texture:SetPoint(slice[1], anchor, slice[2], 0, 0)
            if index <= 4 then texture:SetSize(extent, extent)
            else
                texture:SetPoint(slice[3], anchor, slice[4], 0, 0)
                if index <= 6 then texture:SetHeight(extent) else texture:SetWidth(extent) end
            end
            writes = writes + 4
        end
        if colorChanged then texture:SetVertexColor(r, g, b, a); writes = writes + 1 end
        if not handle.shown then texture:Show(); writes = writes + 1 end
    end
    handle.anchor, handle.extent = anchor, extent
    handle.r, handle.g, handle.b, handle.a, handle.shown = r, g, b, a, true
    return writes
end

-- Concentric discs share one inverse mask, so changing the outside extent
-- never moves the inner contour or paints over a translucent cell background.
local circleLayers, circleFalloff = 12, {}
for index = 0, circleLayers do
    circleFalloff[index] = (math.exp(-4.5 * (index / circleLayers) ^ 2) - math.exp(-4.5))
        / (1 - math.exp(-4.5))
end

function GUI2:CreateCircleShadow(parent)
    if not parent or not parent.CreateMaskTexture or (parent.IsForbidden and parent:IsForbidden()) then return nil end
    local handle = { textures = {}, shown = false,
        maskPath = Assets:Core("gui2\\shapes\\duration-ring-inner-mask.tga"),
        fillPath = Assets:Core("gui2\\shapes\\circle-mask.tga") }
    local mask = parent:CreateMaskTexture(nil, "BACKGROUND")
    mask:SetTexture(handle.maskPath, "CLAMP", "CLAMP", "LINEAR")
    if self.ApplyTexturePixelPolicy then self:ApplyTexturePixelPolicy(mask) end
    handle.mask = mask
    for index = 1, circleLayers do
        local texture = parent:CreateTexture(nil, "BACKGROUND", nil, -8)
        texture:SetTexture(handle.fillPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
        texture:SetBlendMode("BLEND")
        if self.ApplyTexturePixelPolicy then self:ApplyTexturePixelPolicy(texture) end
        texture:AddMaskTexture(mask)
        texture:Hide()
        handle.textures[index] = texture
    end
    return handle
end

function GUI2:HideCircleShadow(handle)
    if not handle or not handle.shown then return 0 end
    for _, texture in ipairs(handle.textures) do texture:Hide() end
    handle.shown = false
    return circleLayers
end

function GUI2:ApplyCircleShadow(handle, style, geometry)
    if not handle then return 0 end
    if not style or IsSecret(style.enabled) or style.enabled ~= true or not geometry
        or IsSecret(geometry.anchor) or not geometry.anchor then return self:HideCircleShadow(handle) end
    local width, height = Number(geometry.width, 0), Number(geometry.height, 0)
    if width <= 0 or height <= 0 then return self:HideCircleShadow(handle) end
    local extent = math.max(1, math.min(12, Number(style.extent, 4)))
    local color = not IsSecret(style.color) and type(style.color) == "table" and style.color or {}
    local r, g, b, a = Component(color[1], 0), Component(color[2], 0), Component(color[3], 0), Component(color[4], .5)
    if a <= 0 then return self:HideCircleShadow(handle) end
    local maskPath = geometry.maskTexture or Assets:Core("gui2\\shapes\\duration-ring-inner-mask.tga")
    local fillPath = geometry.fillTexture or Assets:Core("gui2\\shapes\\circle-mask.tga")
    local materialChanged = handle.maskPath ~= maskPath or handle.fillPath ~= fillPath
    local changed = materialChanged or handle.anchor ~= geometry.anchor or handle.innerWidth ~= width
        or handle.innerHeight ~= height or handle.extent ~= extent
    local colorChanged = handle.r ~= r or handle.g ~= g or handle.b ~= b or handle.a ~= a
    local writes = 0
    if materialChanged then
        handle.mask:SetTexture(maskPath, "CLAMP", "CLAMP", "LINEAR")
        handle.maskPath, handle.fillPath = maskPath, fillPath
        writes = writes + 1
    end
    if changed then
        local outerWidth, outerHeight = width + 2 * extent, height + 2 * extent
        local sx, sy = .75 * outerWidth / width, .75 * outerHeight / height
        handle.mask:ClearAllPoints()
        handle.mask:SetPoint("CENTER", geometry.anchor, "CENTER", 0, 0)
        handle.mask:SetSize(outerWidth, outerHeight)
        handle.mask:SetTexCoord(.5 - sx / 2, .5 + sx / 2, .5 - sy / 2, .5 + sy / 2)
        handle.width, handle.height = outerWidth, outerHeight
        writes = writes + 4
    end
    for index, texture in ipairs(handle.textures) do
        if materialChanged then
            texture:SetTexture(fillPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "LINEAR")
            writes = writes + 1
        end
        if changed then
            texture:ClearAllPoints()
            texture:SetPoint("CENTER", geometry.anchor, "CENTER", 0, 0)
            texture:SetSize(width + 2 * extent * index / circleLayers, height + 2 * extent * index / circleLayers)
            writes = writes + 3
        end
        if colorChanged then
            local far = a * circleFalloff[index]
            texture:SetVertexColor(r, g, b, (a * circleFalloff[index - 1] - far) / (1 - far))
            writes = writes + 1
        end
        if not handle.shown then texture:Show(); writes = writes + 1 end
    end
    handle.anchor, handle.innerWidth, handle.innerHeight, handle.extent = geometry.anchor, width, height, extent
    handle.r, handle.g, handle.b, handle.a, handle.shown = r, g, b, a, true
    return writes
end

local barShadows = setmetatable({}, { __mode = "k" })

function GUI2:HideBarShadow(frame, owner)
    local state = barShadows[frame]
    if not state or (owner and state.owner ~= owner) then return end
    state.style.enabled = false
    state.owner = nil
    self:HideRectShadow(state.rect)
    for _, cell in pairs(state.cells) do
        self:HideRectShadow(cell.rect)
        self:HideCircleShadow(cell.circle)
    end
end

-- Called only by configuration/layout changes; no fill values or native sizes.
function GUI2:RefreshBarShadow(frame)
    local state = barShadows[frame]
    if not state or not state.style.enabled then return end
    local config = frame.gui2ResourceDisplayConfig
    local mode = config and config.mode
    local nativePoints = mode == "nativePoints"
        or (mode == "dots" and config.nativePointStyle ~= nil)
    local separated = nativePoints or mode == "cells" or mode == "dots"
    if not separated then
        state.rect = state.rect or self:CreateRectShadow(frame)
        self:ApplyRectShadow(state.rect, state.style, frame.track or frame)
    else
        self:HideRectShadow(state.rect)
    end
    -- Native artwork owns its outline. Retain the authored shadow state for
    -- later geometric reuse, but hide old surfaces and allocate none here.
    local count = separated and not nativePoints and (frame.gui2ResourceActiveCellCount or 0) or 0
    for index = 1, math.max(count, #state.cells) do
        local cell = frame.resourceCells and frame.resourceCells[index]
        local shadow = state.cells[index]
        if index <= count and cell then
            shadow = shadow or {}
            state.cells[index] = shadow
            if mode == "dots" then
                self:HideRectShadow(shadow.rect)
                shadow.circle = shadow.circle or self:CreateCircleShadow(cell.host)
                self:ApplyCircleShadow(shadow.circle, state.style, {
                    anchor = cell.host, width = cell.gui2ResourceShadowWidth,
                    height = cell.gui2ResourceShadowHeight,
                    maskTexture = cell.gui2ResourcePointShadowMask,
                    fillTexture = cell.gui2ResourcePointShadowFill,
                })
            else
                self:HideCircleShadow(shadow.circle)
                shadow.rect = shadow.rect or self:CreateRectShadow(cell.host)
                self:ApplyRectShadow(shadow.rect, state.style, cell.host)
            end
        elseif shadow then
            self:HideRectShadow(shadow.rect)
            self:HideCircleShadow(shadow.circle)
        end
    end
end

function GUI2:SetBarShadow(frame, enabled, color, owner, extent)
    if not enabled then self:HideBarShadow(frame, owner); return end
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
    local state = barShadows[frame]
    if not state then
        state = { style = { color = {} }, cells = {} }
        barShadows[frame] = state
    end
    color = type(color) == "table" and color or {}
    local rgba = state.style.color
    rgba[1], rgba[2], rgba[3], rgba[4] = color.r or color[1] or 0, color.g or color[2] or 0,
        color.b or color[3] or 0, color.a or color[4] or 0.5
    state.style.enabled = true
    state.style.extent = math.max(1, math.min(12, Number(extent, 4)))
    state.owner = owner
    self:RefreshBarShadow(frame)
end

GUI2.ShapeShadowMaterials = {}
for shape, aspect in pairs({
    square = 1, roundedSquare = 1, circle = 1,
    flatSquare = 1.35, flatRounded = 1.35, diamond = 1,
    wideSquare = 10 / 9, wideRounded = 10 / 9,
}) do
    GUI2.ShapeShadowMaterials[shape] = {
        path = Assets:Core("gui2\\shapes\\shadow-" .. shape .. ".tga"),
        widthScale = 128 / 96,
        heightScale = 128 / (96 / aspect),
    }
end

-- Ownership stays in side tables; the frame's native scripts are preserved.
function GUI2:CreateShapeShadow(parent)
    if not parent or not parent.CreateTexture then return nil end
    if parent.IsForbidden and parent:IsForbidden() then return nil end
    local texture = parent:CreateTexture(nil, "BACKGROUND", nil, -8)
    texture:SetBlendMode("BLEND")
    if self.ApplyTexturePixelPolicy then self:ApplyTexturePixelPolicy(texture) end
    texture:Hide()
    return { texture = texture, parent = parent, shown = false }
end

function GUI2:HideShapeShadow(handle)
    if not handle then return 0 end
    if bindings[handle.parent] == handle then bindings[handle.parent] = nil end
    handle.contour, handle.boundStyle, handle.deferInCombat = nil, nil, nil
    handle.pending = nil
    return HideTexture(handle)
end

-- style: enabled/shape/color; geometry: anchor/width/height/offsetX/offsetY/allowLayout.
-- Configuration geometry is authoritative; native frame sizes are never queried.
function GUI2:ApplyShapeShadow(handle, style, geometry)
    if not handle or not style then return 0 end
    if IsSecret(style.enabled) or style.enabled ~= true then return self:HideShapeShadow(handle) end
    if not geometry or IsSecret(geometry.allowLayout) or geometry.allowLayout == false then
        handle.pending = true
        return 0
    end
    local width, height = Number(geometry.width, 0), Number(geometry.height, 0)
    if width <= 0 or height <= 0 or IsSecret(geometry.anchor) or not geometry.anchor then return self:HideShapeShadow(handle) end
    local shape = not IsSecret(style.shape) and style.shape or "square"
    local material = self.ShapeShadowMaterials[shape] or self.ShapeShadowMaterials.square
    local color = not IsSecret(style.color) and type(style.color) == "table" and style.color
        or self.ShapeShadowDefaults.color
    local r, g, b, a = Component(color[1], 0), Component(color[2], 0), Component(color[3], 0), Component(color[4], 0.5)
    if a <= 0 then return HideTexture(handle) end
    local writes, texture = 0, handle.texture
    if handle.path ~= material.path then
        texture:SetTexture(material.path)
        handle.path = material.path
        writes = writes + 1
    end
    local offsetX, offsetY = Number(geometry.offsetX, 0), Number(geometry.offsetY, 0)
    local renderWidth, renderHeight = width * material.widthScale, height * material.heightScale
    if handle.anchor ~= geometry.anchor or handle.width ~= renderWidth or handle.height ~= renderHeight
        or handle.offsetX ~= offsetX or handle.offsetY ~= offsetY then
        texture:ClearAllPoints()
        texture:SetPoint("CENTER", geometry.anchor, "CENTER", offsetX, offsetY)
        texture:SetSize(renderWidth, renderHeight)
        handle.anchor, handle.width, handle.height = geometry.anchor, renderWidth, renderHeight
        handle.offsetX, handle.offsetY = offsetX, offsetY
        writes = writes + 3
    end
    if handle.r ~= r or handle.g ~= g or handle.b ~= b or handle.a ~= a then
        texture:SetVertexColor(r, g, b, a)
        handle.r, handle.g, handle.b, handle.a = r, g, b, a
        writes = writes + 1
    end
    if not handle.shown then
        texture:Show()
        handle.shown = true
        writes = writes + 1
    end
    handle.pending = nil
    return writes
end

local function ReadContourSize(contour)
    if IsSecret(contour) or not contour then return nil end
    if contour.IsForbidden and contour:IsForbidden() then return nil end
    local ok, width, height
    if contour.GetSize then
        ok, width, height = pcall(contour.GetSize, contour)
    elseif contour.GetWidth and contour.GetHeight then
        ok, width = pcall(contour.GetWidth, contour)
        if ok then ok, height = pcall(contour.GetHeight, contour) end
    end
    if not ok then return nil end
    width, height = Number(width, nil), Number(height, nil)
    if not width or not height or width <= 0 or height <= 0 then return nil end
    return width, height
end

local OnBoundSizeChanged

local function RefreshBinding(handle)
    if handle.deferInCombat and InCombat() then
        handle.pending = true
        return 0
    end
    local parent = handle.parent
    if not hookedFrames[parent] then
        if not parent.HookScript then return GUI2:HideShapeShadow(handle) end
        local ok = pcall(parent.HookScript, parent, "OnSizeChanged", OnBoundSizeChanged)
        if not ok then return GUI2:HideShapeShadow(handle) end
        hookedFrames[parent] = true
    end
    local width, height = ReadContourSize(handle.contour)
    if not width then
        handle.pending = true
        return HideTexture(handle)
    end
    local geometry = handle.boundGeometry
    geometry.anchor, geometry.width, geometry.height = handle.contour, width, height
    handle.pending = nil
    return GUI2:ApplyShapeShadow(handle, handle.boundStyle, geometry)
end

OnBoundSizeChanged = function(frame)
    local handle = bindings[frame]
    if handle then RefreshBinding(handle) end
end

-- The visible contour, also used by the border, is the only geometry source.
function GUI2:BindShapeShadow(handle, style, contour, deferInCombat)
    if not handle or not style then return 0 end
    if IsSecret(style.enabled) or style.enabled ~= true then return self:HideShapeShadow(handle) end
    if IsSecret(contour) or not contour then return self:HideShapeShadow(handle) end
    local parent = handle.parent
    local previous = bindings[parent]
    if previous and previous ~= handle then self:HideShapeShadow(previous) end
    handle.boundGeometry = handle.boundGeometry or {}
    handle.contour, handle.boundStyle, handle.deferInCombat = contour, style, deferInCombat == true
    bindings[parent] = handle
    return RefreshBinding(handle)
end

-- Reuse the consumers' existing out-of-combat lifecycle; no extra event owner.
function GUI2:FlushShapeShadowBindings()
    if InCombat() then return 0 end
    local writes = 0
    for _, handle in pairs(bindings) do
        if handle.pending then writes = writes + RefreshBinding(handle) end
    end
    return writes
end

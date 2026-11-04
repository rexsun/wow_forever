local YUI = _G.YUI
if not YUI then return end

local GUI2 = YUI.GUI2
if not GUI2 then return end

local Assets = YUI.Assets
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local Visual = GUI2.Visual or {}
GUI2.Visual = Visual

Visual.implementationType = "native-enhanced"
Visual.states = Visual.states or setmetatable({}, { __mode = "k" })
Visual.statusBarBorders = Visual.statusBarBorders
    or setmetatable({}, { __mode = "k" })
Visual.nativeStatusBarStates = Visual.nativeStatusBarStates
    or setmetatable({}, { __mode = "k" })

local WHITE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_COLOR = { 1, 1, 1, 1 }
local DEFAULT_BORDER = { 0, 0, 0, 1 }
local DEFAULT_BACKGROUND = { 0, 0, 0, 0.72 }
local DEFAULT_SWIPE = { 0, 0, 0, 0.82 }
-- 原生 Cooldown 按自身尺寸缩放；所有图标形状先共用同一基础样式。
-- 圆形模式和内容遮罩仍由形状预设决定，不在 Lua 中计算旋转角度。
local DEFAULT_COOLDOWN_EDGE = {
    texture = (YUI.IsRetail == true or YUI.IsForever == true)
        and "Interface\\Cooldown\\UI-HUD-ActionBar-SecondaryCooldown" or nil,
    scale = 2.1,
    color = { 0.973, 0.839, 0.604, 1 },
}

local PROC_FLIPBOOK_ROWS = 6
local PROC_FLIPBOOK_COLUMNS = 5
local PROC_FLIPBOOK_FRAMES = 30
local PROC_START_DURATION = 0.32
local PROC_LOOP_DURATION = 1
local PROC_START_FADE_DELAY = 0.24
local PROC_START_FADE_DURATION = 0.08
local PROC_LOOP_FADE_DELAY = 0.25
local PROC_LOOP_FADE_DURATION = 0.10
local PROC_TEMPLATE_SCALE = 1.4
local PROC_SQUARE_TARGET_FIT_SCALE = 0.05
local PROC_TEMPLATE_START_SCALE = 3.28
local PROC_CIRCLE_START_SCALE = 2.25
local PROC_CIRCLE_LOOP_SCALE = 1.58
local PROC_APPEARANCE_OUTSET_SCALE = 0.20
local PROC_APPEARANCE_AXIS_SCALE = 0.25

local effectBorders = setmetatable({}, { __mode = "k" })
local contourFlashes = setmetatable({}, { __mode = "k" })

function GUI2:HasIconCooldownFlash(cooldown)
    return contourFlashes[cooldown] == true
end

-- Public skin configuration only; no measurements of restricted descendants.
function GUI2:GetIconGlowInset(target, shape, width, height)
    local owner = target and (target.gui2GlowSkinOwner or target.gui2GlowTarget or target)
    if not owner or (self.IsIconSkinManaged and self:IsIconSkinManaged(owner)) then return 0, 0 end
    local border = effectBorders[owner] or owner.gui2IconBorder
    if not border then return 0, 0 end
    local pixel = self:GetPixelSize(owner, 1, 1)
    local preset = self:GetIconAppearancePreset(shape)
    local ratio = preset.cooldownInsets and preset.cooldownInsets[border] or self.IconCooldownInsets[border]
    if ratio then return math.max(pixel, width * ratio * 0.5), math.max(pixel, height * ratio * 0.5) end
    local inset = math.max(pixel, self:GetIconBorderThickness(border) * pixel * 0.5)
    return inset, inset
end

local function IsSquareProcTarget(shape)
    return shape == "square"
        or shape == "flatSquare"
        or shape == "wideSquare"
end

local function GetManagedProcTargetFit(frame, width, height, targetShape)
    if not IsSquareProcTarget(targetShape) then return 0 end
    local pixel = GUI2.GetPixelSize
        and GUI2:GetPixelSize(frame, 1, 1)
        or (GUI2.mult or 1)
    local fit = math.min(width, height) * PROC_SQUARE_TARGET_FIT_SCALE
    return math.floor(fit / pixel + 0.5) * pixel
end

local function SnapManagedProcValue(frame, value, pixel)
    pixel = pixel or (GUI2.GetPixelSize
        and GUI2:GetPixelSize(frame, 1, 1)) or (GUI2.mult or 1)
    if not pixel or pixel <= 0 then return tonumber(value) or 0 end
    return math.floor((tonumber(value) or 0) / pixel + 0.5) * pixel
end

local function GetManagedProcAppearanceSize(frame, width, height)
    if frame.gui2ProcAppearanceCustom ~= true then
        return width, height
    end
    local pixel = GUI2.GetPixelSize
        and GUI2:GetPixelSize(frame, 1, 1) or (GUI2.mult or 1)
    local base = math.min(width, height)
    local size = frame.gui2ProcAppearanceSize or 1
    local outset = SnapManagedProcValue(
        frame,
        base * PROC_APPEARANCE_OUTSET_SCALE * (size - 1),
        pixel
    )
    local expandX = SnapManagedProcValue(
        frame,
        width * PROC_APPEARANCE_AXIS_SCALE
            * (frame.gui2ProcAppearanceOffsetX or 0),
        pixel
    )
    local expandY = SnapManagedProcValue(
        frame,
        height * PROC_APPEARANCE_AXIS_SCALE
            * (frame.gui2ProcAppearanceOffsetY or 0),
        pixel
    )
    local horizontalCompensation = pixel
        * (frame.gui2ProcHorizontalCompensationPixels or 0)
    return math.max(pixel, width + 2 * (
        outset + expandX + horizontalCompensation
    )), math.max(pixel, height + 2 * (outset + expandY))
end

local function Bundle(path)
    if Assets and Assets.Bundle then
        return Assets:Bundle("sharedmedia-statusbars", path)
    end
    return WHITE
end

local function CoreMedia(path)
    if Assets and Assets.Core then
        return Assets:Core(path)
    end
    return "Interface\\AddOns\\"
        .. (YUI.AddonName or "YUI")
        .. "\\Media\\Core\\"
        .. tostring(path or "")
end

local PROC_CIRCLE_START =
    CoreMedia("gui2\\proc\\circle-proc-start-flipbook.blp")
local COOLDOWN_CIRCLE_RIPPLE =
    CoreMedia("gui2\\glow\\cooldown-circle-ripple.blp")
local PROC_CIRCLE_LOOP =
    CoreMedia("gui2\\proc\\circle-proc-loop-flipbook.blp")
local PROC_CIRCLE_BORDER =
    CoreMedia("gui2\\shapes\\circle-border-4.tga")
local PROC_CIRCLE_SOFT =
    CoreMedia("gui2\\shapes\\circle-border-3.tga")
local PROC_SQUARE_FALLBACK = "Interface\\Buttons\\UI-ActionButton-Border"

-- Independent state/objects; reuse only the proc loop artwork, without its burst.
function GUI2:LayoutManagedAssistedHighlight(glow, target, width, height, level, strata, shape)
    if not (glow and target and width and height) then return false end
    if glow.gui2IconSkinHost then return false end
    local material = shape == "circle" and "circle" or "square"
    local changed = false
    if glow.gui2AssistedMaterial ~= material then
        if material == "circle" then
            glow.Flipbook:SetTexture(PROC_CIRCLE_LOOP)
        else
            glow.Flipbook:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
        end
        glow.Flipbook:SetDesaturated(true)
        glow.Flipbook:SetVertexColor(0.24, 0.78, 1, 1)
        glow.gui2AssistedMaterial = material
        changed = true
    end
    local pixel = self.GetPixelSize and self:GetPixelSize(target, 1, 1) or self.mult or 1
    local insetX, insetY = self:GetIconGlowInset(target, shape, width, height)
    width, height = width - insetX * 2, height - insetY * 2
    width, height = math.max(pixel, width - pixel * 2), math.max(pixel, height - pixel * 2)
    if glow.gui2AssistedTarget ~= target or glow.gui2AssistedWidth ~= width
        or glow.gui2AssistedHeight ~= height or glow.gui2AssistedLevel ~= level
        or glow.gui2AssistedStrata ~= strata or glow.gui2AssistedShape ~= shape then
        glow:ClearAllPoints()
        glow:SetPoint("CENTER", target, "CENTER", 0, 0)
        glow:SetSize(width, height)
        if level then glow:SetFrameLevel(level) end
        if strata then glow:SetFrameStrata(strata) end
        glow.Flipbook:ClearAllPoints()
        glow.Flipbook:SetPoint("CENTER", glow, "CENTER", 0, 0)
        -- Fit the visible loop inside the gold loop, including the artwork's overscan.
        local scale = material == "circle" and (PROC_CIRCLE_LOOP_SCALE * 0.94)
            or (IsSquareProcTarget(shape) and 66 / 45 or PROC_TEMPLATE_SCALE)
        if shape == "diamond" then scale = scale / math.sqrt(2) end
        glow.Flipbook:SetSize(width * scale, height * scale)
        glow.Flipbook:SetRotation(shape == "diamond" and math.pi / 4 or 0)
        glow.gui2AssistedShape = shape
        glow.gui2AssistedTarget = target
        glow.gui2AssistedWidth, glow.gui2AssistedHeight = width, height
        glow.gui2AssistedLevel, glow.gui2AssistedStrata = level, strata
        changed = true
    end
    return changed
end

function GUI2:CreateManagedAssistedHighlight(target, width, height, level, strata, shape)
    if YUI.IsRetail ~= true or not target
        or (InCombatLockdown and InCombatLockdown()) then return nil end
    local glow = CreateFrame("Frame", nil, target, "ActionBarButtonAssistedCombatHighlightTemplate")
    glow:EnableMouse(false)
    self:LayoutManagedAssistedHighlight(glow, target, width, height, level, strata, shape)
    glow:Hide()
    return glow
end

function GUI2:SetManagedAssistedHighlightShown(glow, shown)
    if not glow then return false end
    shown = shown == true
    if (glow.gui2AssistedPlaying == true) == shown and glow:IsShown() == shown then return false end
    if shown then
        glow:Show()
        glow.Flipbook.Anim:Play()
    else
        glow.Flipbook.Anim:Stop()
        glow:Hide()
    end
    glow.gui2AssistedPlaying = shown
    return true
end

local STATUS_BAR_TEXTURES = {
    solid = WHITE,
    ["yui-g1"] = Bundle("YUI G1.tga"),
    ["yui-g2"] = Bundle("YUI G2.tga"),
}

-- 两张内置材质的首尾像素包含用于旧式边缘塑形的暗带。StatusBar
-- 会把该暗带绘制在一侧，看起来像不对称的第二层边框；公共快照在采样
-- 阶段裁掉它，真正的边框只由 GUI2 像素边框负责。
local STATUS_BAR_TEX_COORDS = {
    ["yui-g1"] = { 0, 1, 3 / 32, 27 / 32 },
    ["yui-g2"] = { 0, 1, 3 / 32, 27 / 32 },
}

local function Clamp(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value then return fallback end
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function ColorComponent(color, key, index, fallback)
    if type(color) ~= "table" then return fallback end
    local value = color[key]
    if value == nil then value = color[index] end
    value = tonumber(value)
    if value == nil then return fallback end
    return Clamp(value, 0, 1, fallback)
end

local function CompileColor(source, output, fallback)
    output = output or {}
    fallback = fallback or DEFAULT_COLOR
    output[1] = ColorComponent(source, "r", 1, fallback[1])
    output[2] = ColorComponent(source, "g", 2, fallback[2])
    output[3] = ColorComponent(source, "b", 3, fallback[3])
    output[4] = ColorComponent(source, "a", 4, fallback[4] or 1)
    return output
end

local function SameColor(a, b)
    return a and b
        and a[1] == b[1] and a[2] == b[2]
        and a[3] == b[3] and a[4] == b[4]
end

local function CopyColor(source, output)
    output = output or {}
    output[1], output[2], output[3], output[4] =
        source[1], source[2], source[3], source[4]
    return output
end

local function CreateAnimation(group, animationType)
    if not (group and group.CreateAnimation) then return nil end
    local ok, animation = pcall(
        group.CreateAnimation,
        group,
        animationType
    )
    return ok and animation or nil
end

local function SetAnimationTarget(animation, target)
    if not (animation and target and animation.SetTarget) then
        return false
    end
    return pcall(animation.SetTarget, animation, target) == true
end

local function ConfigureFlipbook(
    animation,
    target,
    duration,
    order
)
    if not SetAnimationTarget(animation, target) then return false end
    local ok = true
    if animation.SetDuration then
        ok = pcall(animation.SetDuration, animation, duration) and ok
    end
    if animation.SetOrder then
        ok = pcall(animation.SetOrder, animation, order) and ok
    end
    if animation.SetFlipBookRows then
        ok = pcall(
            animation.SetFlipBookRows,
            animation,
            PROC_FLIPBOOK_ROWS
        ) and ok
    end
    if animation.SetFlipBookColumns then
        ok = pcall(
            animation.SetFlipBookColumns,
            animation,
            PROC_FLIPBOOK_COLUMNS
        ) and ok
    end
    if animation.SetFlipBookFrames then
        ok = pcall(
            animation.SetFlipBookFrames,
            animation,
            PROC_FLIPBOOK_FRAMES
        ) and ok
    end
    if animation.SetFlipBookFrameWidth then
        ok = pcall(
            animation.SetFlipBookFrameWidth,
            animation,
            0
        ) and ok
    end
    if animation.SetFlipBookFrameHeight then
        ok = pcall(
            animation.SetFlipBookFrameHeight,
            animation,
            0
        ) and ok
    end
    return ok
end

local function ConfigureAlpha(
    animation,
    target,
    fromAlpha,
    toAlpha,
    duration,
    order,
    delay
)
    if not SetAnimationTarget(animation, target) then return false end
    local ok = true
    if animation.SetFromAlpha then
        ok = pcall(
            animation.SetFromAlpha,
            animation,
            fromAlpha
        ) and ok
    end
    if animation.SetToAlpha then
        ok = pcall(
            animation.SetToAlpha,
            animation,
            toAlpha
        ) and ok
    end
    if animation.SetDuration then
        ok = pcall(animation.SetDuration, animation, duration) and ok
    end
    if animation.SetOrder then
        ok = pcall(animation.SetOrder, animation, order) and ok
    end
    if delay and delay > 0 then
        if not animation.SetStartDelay then return false end
        ok = pcall(animation.SetStartDelay, animation, delay) and ok
    end
    return ok
end

local function NormalizeShape(shape)
    if shape == "rounded" then return "roundedSquare" end
    if GUI2.IconAppearancePresets
        and GUI2.IconAppearancePresets[shape] then
        return shape
    end
    return "square"
end

local function NormalizeBorder(border)
    if GUI2.IconBorderThickness
        and GUI2.IconBorderThickness[border] ~= nil then
        return border
    end
    return "thin"
end

local function NormalizeFont(font)
    if type(font) == "string" and font ~= "" then return font end
    return "default"
end

local function NormalizeOutline(outline)
    if outline == "none"
        or outline == "shadow"
        or outline == "outline"
        or outline == "outlineShadow"
        or outline == "thickShadow"
        or outline == "thick" then
        return outline
    end
    return "none"
end

local function NormalizeTextPosition(position)
    if position == "top" or position == "bottom"
        or position == "left" or position == "right"
        or position == "top-left" or position == "bottom-left"
        or position == "top-right" or position == "bottom-right" then
        return position
    end
    return "center"
end

function GUI2:GetStatusBarTexture(textureId)
    if STATUS_BAR_TEXTURES[textureId] then
        return STATUS_BAR_TEXTURES[textureId], textureId
    end
    if type(textureId) == "string" and textureId:find("\\", 1, true) then
        return textureId, textureId
    end
    if LSM and LSM.Fetch and type(textureId) == "string" then
        local path = LSM:Fetch("statusbar", textureId, true)
        if path then return path, textureId end
    end
    return STATUS_BAR_TEXTURES.solid, "solid"
end

function GUI2:CompileTextStyle(input, output, defaults)
    local explicitlyDisabled = input == false
    input = type(input) == "table" and input or {}
    defaults = type(defaults) == "table" and defaults or {}
    output = output or {}
    output.enabled = not explicitlyDisabled and input.enabled ~= false
    output.font = NormalizeFont(input.font or defaults.font)
    output.size = math.floor(Clamp(
        input.size,
        8,
        32,
        tonumber(defaults.size) or 12
    ) + 0.5)
    output.outline = NormalizeOutline(input.outline or defaults.outline)
    output.monochrome = input.monochrome == true or (input.monochrome == nil and defaults.monochrome == true)
    output.position = NormalizeTextPosition(
        input.position or defaults.position
    )
    output.anchor = type(input.anchor) == "string"
        and input.anchor or defaults.anchor
    output.offsetX = Clamp(
        input.offsetX,
        -64,
        64,
        tonumber(defaults.offsetX) or 0
    )
    output.offsetY = Clamp(
        input.offsetY,
        -64,
        64,
        tonumber(defaults.offsetY) or 0
    )
    output.color = CompileColor(
        input.color,
        output.color,
        defaults.color or DEFAULT_COLOR
    )
    return output
end

function GUI2:CompileIconStyle(input, output)
    input = type(input) == "table" and input or {}
    output = output or {}
    output.shape = NormalizeShape(input.shape or input.iconShape)
    output.border = NormalizeBorder(input.border or input.iconBorder)
    output.borderThickness = GUI2.GetIconBorderThickness
        and GUI2:GetIconBorderThickness(output.border) or 1
    output.zoom = Clamp(
        input.zoom or input.iconZoom,
        0,
        0.24,
        0.08
    )
    local preset = GUI2.GetIconAppearancePreset
        and GUI2:GetIconAppearancePreset(output.shape) or {}
    output.aspect = tonumber(preset and preset.aspect) or 1
    output.mask = GUI2.GetIconAppearanceMask
        and GUI2:GetIconAppearanceMask(output.shape, output.border)
        or (preset and preset.mask or nil)
    output.borderFamily = GUI2.GetIconBorderFamily
        and GUI2:GetIconBorderFamily(output.shape, output.border)
        or (preset and preset.borderFamily or nil)
    output.swipeTexture = (GUI2.GetIconCooldownTexture
        and GUI2:GetIconCooldownTexture(output.shape, output.border)) or output.mask
        or (preset and preset.swipe)
        or WHITE
    output.circular = preset and preset.circular == true or false
    output.cooldownEdge = DEFAULT_COOLDOWN_EDGE
    output.borderColor = CompileColor(
        input.borderColor or input.iconBorderColor,
        output.borderColor,
        DEFAULT_BORDER
    )
    if GUI2.IsIconBorderMaterial and GUI2:IsIconBorderMaterial(output.border) then
        for i = 1, 4 do output.borderColor[i] = 1 end
    end
    output.backgroundMode = input.iconBackground or input.background
    output.backgroundColor = CompileColor(
        input.backgroundColor or input.iconBackgroundColor,
        output.backgroundColor,
        DEFAULT_BACKGROUND
    )
    output.swipeColor = CompileColor(
        input.swipeColor or input.cooldownSwipeColor,
        output.swipeColor,
        DEFAULT_SWIPE
    )
    local drawSwipe = input.drawSwipe
    if type(drawSwipe) ~= "boolean" then
        drawSwipe = input.cooldownSwipe
    end
    if type(drawSwipe) == "boolean" then
        output.drawSwipe = drawSwipe
    else
        output.drawSwipe = nil
    end
    output.drawBling = input.drawBling == true
        or input.cooldownBling == true
    output.cooldownText = GUI2:CompileTextStyle(
        input.cooldownTextStyle or {
            enabled = input.cooldownText,
            font = input.cooldownTextFont,
            size = input.cooldownTextSize,
            outline = input.cooldownTextOutline,
            monochrome = input.cooldownTextMonochrome,
            position = input.cooldownTextPosition,
            offsetX = input.cooldownTextOffsetX,
            offsetY = input.cooldownTextOffsetY,
            color = input.cooldownTextColor,
        },
        output.cooldownText,
        {
            enabled = true,
            size = 14,
            outline = "outline",
            position = "center",
            color = DEFAULT_COLOR,
        }
    )
    output.countText = GUI2:CompileTextStyle(
        input.countTextStyle or {
            enabled = input.countText,
            font = input.countTextFont,
            size = input.countTextSize,
            outline = input.countTextOutline,
            monochrome = input.countTextMonochrome,
            position = input.countTextPosition,
            offsetX = input.countTextOffsetX,
            offsetY = input.countTextOffsetY,
            color = input.countTextColor,
        },
        output.countText,
        {
            enabled = true,
            size = 12,
            outline = "outline",
            position = "bottom",
            offsetX = -2,
            offsetY = 2,
            color = DEFAULT_COLOR,
        }
    )
    return output
end

function GUI2:CompileStatusBarStyle(input, output)
    input = type(input) == "table" and input or {}
    output = output or {}
    output.texture, output.textureId = self:GetStatusBarTexture(
        input.textureId or input.fillTexture or "solid"
    )
    local coords = STATUS_BAR_TEX_COORDS[output.textureId]
    output.textureU0 = coords and coords[1] or 0
    output.textureU1 = coords and coords[2] or 1
    output.textureV0 = coords and coords[3] or 0
    output.textureV1 = coords and coords[4] or 1
    output.fillColorMode = input.fillColorMode == "resource"
        and "resource" or "custom"
    output.fillColor = CompileColor(
        input.fillColor,
        output.fillColor,
        { 0.25, 0.55, 0.95, 1 }
    )
    output.trackColor = CompileColor(
        input.trackColor or input.backgroundColor,
        output.trackColor,
        { 0.04, 0.06, 0.08, 0.92 }
    )
    local numericBorder = tonumber(input.border)
    if numericBorder then
        output.border = numericBorder
        output.borderThickness = Clamp(numericBorder, 0, 12, 1)
    else
        output.border = NormalizeBorder(input.border)
        output.borderThickness = GUI2.GetIconBorderThickness
            and GUI2:GetIconBorderThickness(output.border) or 1
    end
    output.borderColor = CompileColor(
        input.borderColor,
        output.borderColor,
        DEFAULT_BORDER
    )
    output.showIcon = input.showIcon ~= false
    output.nameText = self:CompileTextStyle(
        input.nameTextStyle or input.nameText,
        output.nameText,
        { size = 12, outline = "outline", position = "left" }
    )
    output.timeText = self:CompileTextStyle(
        input.timeTextStyle or input.timeText,
        output.timeText,
        { size = 12, outline = "outline", position = "right" }
    )
    output.countText = self:CompileTextStyle(
        input.countTextStyle or input.countText,
        output.countText,
        { size = 12, outline = "outline", position = "right" }
    )
    return output
end

local function GetNativeStatusBarState(statusBar)
    local state = Visual.nativeStatusBarStates[statusBar]
    if not state then
        state = {}
        Visual.nativeStatusBarStates[statusBar] = state
    end
    return state
end

local function InvalidateNativeStatusBarMaterial(state, texture)
    state.textureObject = texture
    state.texture = nil
    state.textureAtlas = nil
    state.textureU0 = nil
    state.textureU1 = nil
    state.textureV0 = nil
    state.textureV1 = nil
    state.pixelPolicyObject = nil
    state.orientation = nil
    state.rotatesTexture = nil
    state.fillStyle = nil
    state.appliedColorR = nil
    state.appliedColorG = nil
    state.appliedColorB = nil
    state.appliedColorA = nil
end

local function ResolveNativeStatusBarColor(color, fallbackState)
    if type(color) == "string" then
        return GUI2:GetColor(color)
    end
    if type(color) == "table" then
        return color[1] or color.r or 1,
            color[2] or color.g or 1,
            color[3] or color.b or 1,
            (color[4] or color.a) == nil and 1
                or (color[4] or color.a)
    end
    if fallbackState and fallbackState.colorR ~= nil then
        return fallbackState.colorR,
            fallbackState.colorG,
            fallbackState.colorB,
            fallbackState.colorA
    end
    return 1, 1, 1, 1
end

function GUI2:ResolveNativeStatusBarDirection(orientation, direction)
    local vertical = orientation == "vertical" or orientation == "VERTICAL"
    local reverse = direction == true or direction == "reverse"
        or (vertical and direction == "down")
        or (not vertical and direction == "right")
    -- Retail Standard grows left-to-right or top-to-bottom. Reverse grows
    -- right-to-left or bottom-to-top. Authored texture left is always the
    -- logical fill start, so vertical forward deliberately uses Reverse.
    local nativeReverse
    if vertical then
        nativeReverse = not reverse
    else
        nativeReverse = reverse
    end
    return vertical and "VERTICAL" or "HORIZONTAL",
        vertical,
        nativeReverse,
        reverse and "reverse" or "forward"
end

local function NativeStatusBarTexturePolicyWasReplaced(texture)
    if not texture then return false end
    if texture.GetHorizTile then
        local ok, value = pcall(texture.GetHorizTile, texture)
        if ok and value ~= false then return true end
    end
    if texture.GetVertTile then
        local ok, value = pcall(texture.GetVertTile, texture)
        if ok and value ~= false then return true end
    end
    return false
end

local function ApplyNativeStatusBarTexturePolicy(
    statusBar,
    state,
    texture,
    force
)
    if not texture then return 0 end
    if force ~= true
        and state.pixelPolicyObject == texture then
        return 0
    end
    if GUI2.ApplyTexturePixelPolicy then
        GUI2:ApplyTexturePixelPolicy(texture)
    end
    if texture.SetHorizTile then texture:SetHorizTile(false) end
    if texture.SetVertTile then texture:SetVertTile(false) end
    state.pixelPolicyObject = texture
    return 1
end

local function NativeStatusBarMaterialWasReplaced(texture, expected, atlas)
    if (type(expected) ~= "string" and type(expected) ~= "number") or not (texture and texture.GetTexture) then
        return false
    end
    local ok, current = pcall(texture.GetTexture, texture)
    if not ok or (_G.issecretvalue and _G.issecretvalue(current)) then return false end
    if type(current) == type(expected) and current ~= expected then return true end
    if atlas and texture.GetAtlas then
        local atlasOK, currentAtlas = pcall(texture.GetAtlas, texture)
        return atlasOK and not (_G.issecretvalue and _G.issecretvalue(currentAtlas))
            and currentAtlas ~= atlas
    end
    return false
end

function GUI2:RefreshNativeStatusBarTexturePolicy(statusBar)
    if not (statusBar and statusBar.GetStatusBarTexture) then return 0 end
    local state = GetNativeStatusBarState(statusBar)
    local texture = statusBar:GetStatusBarTexture()
    if state.textureObject ~= texture then
        InvalidateNativeStatusBarMaterial(state, texture)
    end
    return ApplyNativeStatusBarTexturePolicy(
        statusBar,
        state,
        texture,
        NativeStatusBarTexturePolicyWasReplaced(texture)
    )
end

function GUI2:InvalidateNativeStatusBarStyle(statusBar)
    if not statusBar then return false end
    local state = GetNativeStatusBarState(statusBar)
    local texture = statusBar.GetStatusBarTexture
        and statusBar:GetStatusBarTexture() or nil
    InvalidateNativeStatusBarMaterial(state, texture)
    return true
end

function GUI2:InvalidateNativeStatusBarColor(statusBar)
    if not statusBar then return false end
    local state = GetNativeStatusBarState(statusBar)
    state.appliedColorR = nil
    state.appliedColorG = nil
    state.appliedColorB = nil
    state.appliedColorA = nil
    return true
end

function GUI2:ApplyNativeStatusBarTransientColor(statusBar, r, g, b, a)
    if not (statusBar and statusBar.SetStatusBarColor) then return 0 end
    local state = GetNativeStatusBarState(statusBar)
    local texture = statusBar.GetStatusBarTexture
        and statusBar:GetStatusBarTexture() or nil
    if state.textureObject ~= texture then
        InvalidateNativeStatusBarMaterial(state, texture)
    end
    if not pcall(statusBar.SetStatusBarColor, statusBar, r, g, b, a) then
        return 0
    end
    -- Transient components may be secret. Never normalize, compare or retain
    -- them; invalidate only the public applied-color cache so the next
    -- authored color restores once and then resumes ordinary deduplication.
    state.appliedColorR = nil
    state.appliedColorG = nil
    state.appliedColorB = nil
    state.appliedColorA = nil
    return 1
end

function GUI2:ApplyNativeStatusBarColor(statusBar, r, g, b, a, force)
    if not (statusBar and statusBar.SetStatusBarColor) then return 0 end
    if type(r) == "string" then
        r, g, b, a = GUI2:GetColor(r)
    elseif type(r) == "table" then
        r, g, b, a = ResolveNativeStatusBarColor(r)
    else
        r = tonumber(r) or 1
        g = tonumber(g) or 1
        b = tonumber(b) or 1
        a = a == nil and 1 or a
    end
    local state = GetNativeStatusBarState(statusBar)
    local texture = statusBar.GetStatusBarTexture
        and statusBar:GetStatusBarTexture() or nil
    if state.textureObject ~= texture then
        InvalidateNativeStatusBarMaterial(state, texture)
    end
    state.colorR, state.colorG, state.colorB, state.colorA = r, g, b, a
    -- Retail can return secret components from GetStatusBarColor. Native/C-side
    -- resets must invalidate or explicitly restore this authored color instead
    -- of feeding protected readbacks into Lua comparisons.
    if force ~= true
        and state.appliedColorR == r
        and state.appliedColorG == g
        and state.appliedColorB == b
        and state.appliedColorA == a then
        return 0
    end
    statusBar:SetStatusBarColor(r, g, b, a)
    state.appliedColorR = r
    state.appliedColorG = g
    state.appliedColorB = b
    state.appliedColorA = a
    return 1
end

function GUI2:RestoreNativeStatusBarColor(statusBar, snapshot)
    if not (statusBar and statusBar.SetStatusBarColor) then return 0 end
    local state = GetNativeStatusBarState(statusBar)
    local texture = statusBar.GetStatusBarTexture
        and statusBar:GetStatusBarTexture() or nil
    if state.textureObject ~= texture then
        InvalidateNativeStatusBarMaterial(state, texture)
    end
    snapshot = type(snapshot) == "table" and snapshot or nil
    local r, g, b, a = ResolveNativeStatusBarColor(
        snapshot and snapshot.fillColor,
        state
    )
    return self:ApplyNativeStatusBarColor(
        statusBar,
        r,
        g,
        b,
        a,
        true
    )
end

function GUI2:ApplyNativeStatusBarStyle(
    statusBar,
    snapshot,
    orientation,
    direction,
    force
)
    if not (statusBar and statusBar.SetStatusBarTexture) then return 0 end
    snapshot = type(snapshot) == "table" and snapshot or {}
    local state = GetNativeStatusBarState(statusBar)
    local texture = statusBar.GetStatusBarTexture
        and statusBar:GetStatusBarTexture() or nil
    if state.textureObject ~= texture then
        InvalidateNativeStatusBarMaterial(state, texture)
    end

    local nextTexture = snapshot.texture
    if (type(nextTexture) ~= "string" and type(nextTexture) ~= "number") or nextTexture == "" then
        nextTexture = self:GetStatusBarTexture(
            snapshot.textureId or snapshot.fillTexture or "solid"
        )
    end
    local nextAtlas = type(snapshot.textureAtlas) == "string" and snapshot.textureAtlas ~= ""
        and snapshot.textureAtlas or nil
    local u0 = tonumber(snapshot.textureU0) or 0
    local u1 = tonumber(snapshot.textureU1) or 1
    local v0 = tonumber(snapshot.textureV0) or 0
    local v1 = tonumber(snapshot.textureV1) or 1
    local configureDirection = orientation ~= nil or direction ~= nil
    local nativeOrientation, rotatesTexture, fillStyle
    if configureDirection then
        nativeOrientation, rotatesTexture, fillStyle =
            self:ResolveNativeStatusBarDirection(orientation, direction)
    end
    local writes = 0
    local materialChanged = force == true or state.texture ~= nextTexture
        or state.textureAtlas ~= nextAtlas
        or NativeStatusBarMaterialWasReplaced(texture, nextTexture, nextAtlas)

    -- Order is intentional. Retail can reset vertex color while changing the
    -- material or rotation, so color is always the final operation below.
    if materialChanged then
        statusBar:SetStatusBarTexture(nextTexture)
        writes = writes + 1
        texture = statusBar.GetStatusBarTexture
            and statusBar:GetStatusBarTexture() or nil
        if state.textureObject ~= texture then
            InvalidateNativeStatusBarMaterial(state, texture)
        end
        state.texture = nextTexture
        state.textureAtlas = nextAtlas
        if nextAtlas and texture and texture.SetAtlas then
            -- StatusBar rebuilds the fill's UVs on value/timer/layout changes.
            -- Preserve native atlas identity so it clips within this sub-image.
            texture:SetAtlas(nextAtlas, false, "LINEAR")
            writes = writes + 1
        end
    end
    local coordinatesChanged = force == true or materialChanged
        or state.textureU0 ~= u0 or state.textureU1 ~= u1
        or state.textureV0 ~= v0 or state.textureV1 ~= v1
    if coordinatesChanged and texture then
        if not (nextAtlas and texture.SetAtlas) and texture.SetTexCoord then
            texture:SetTexCoord(u0, u1, v0, v1)
            writes = writes + 1
        end
        state.textureU0, state.textureU1 = u0, u1
        state.textureV0, state.textureV1 = v0, v1
    end
    writes = writes + ApplyNativeStatusBarTexturePolicy(
        statusBar,
        state,
        texture,
        force == true or materialChanged
    )

    local geometryChanged = materialChanged or coordinatesChanged
    if configureDirection
        and (force == true or materialChanged
            or state.orientation ~= nativeOrientation) then
        if statusBar.SetOrientation then
            statusBar:SetOrientation(nativeOrientation)
            writes = writes + 1
        end
        state.orientation = nativeOrientation
        geometryChanged = true
    end
    if configureDirection
        and (force == true or materialChanged
            or state.rotatesTexture ~= rotatesTexture) then
        if statusBar.SetRotatesTexture then
            statusBar:SetRotatesTexture(rotatesTexture)
            writes = writes + 1
        end
        state.rotatesTexture = rotatesTexture
        geometryChanged = true
    end
    if configureDirection
        and (force == true or materialChanged
            or state.fillStyle ~= fillStyle) then
        local styles = Enum and Enum.StatusBarFillStyle
        if statusBar.SetFillStyle and styles then
            statusBar:SetFillStyle(
                fillStyle and styles.Reverse or styles.Standard
            )
            writes = writes + 1
        elseif statusBar.SetReverseFill then
            statusBar:SetReverseFill(fillStyle)
            writes = writes + 1
        end
        state.fillStyle = fillStyle
        geometryChanged = true
    end

    local r, g, b, a = ResolveNativeStatusBarColor(
        snapshot.fillColor,
        state
    )
    writes = writes + self:ApplyNativeStatusBarColor(
        statusBar,
        r,
        g,
        b,
        a,
        force == true or geometryChanged
    )
    return writes
end

local function StopAnimationGroup(group)
    if group and group.IsPlaying and group:IsPlaying() then
        group:Stop()
    end
end

local function PlayAnimationGroup(group)
    if group then
        if group.IsPlaying and group:IsPlaying() then
            group:Stop()
        end
        group:Play()
    end
end

local function StopProcAnimations(frame)
    if not frame then return end
    StopAnimationGroup(frame.ProcStartAnim)
    StopAnimationGroup(frame.ProcStartFadeOut)
    StopAnimationGroup(frame.ProcLoopFadeIn)
    StopAnimationGroup(frame.ProcLoop)
    if frame.ProcLoopAnim ~= frame.ProcLoop then StopAnimationGroup(frame.ProcLoopAnim) end
    StopAnimationGroup(frame.gui2ProcPulse)
    if frame.ProcStartFlipbook then
        frame.ProcStartFlipbook:SetAlpha(0)
    end
    if frame.ProcLoopFlipbook then
        frame.ProcLoopFlipbook:SetAlpha(0)
    end
    frame.gui2ProcPlaying = false
    frame:Hide()
end

local function CreateCircleProcFallback(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame.gui2ManagedProcGlow = true
    frame.gui2ProcShape = "circle"
    frame:EnableMouse(false)
    frame:Hide()

    local border = frame:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints(frame)
    border:SetTexture(PROC_CIRCLE_BORDER)
    border:SetVertexColor(1, 0.78, 0.16, 1)
    border:SetBlendMode("ADD")
    frame.gui2ProcBorder = border

    local soft = frame:CreateTexture(nil, "OVERLAY")
    soft:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 2)
    soft:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
    soft:SetTexture(PROC_CIRCLE_SOFT)
    soft:SetVertexColor(1, 0.78, 0.16, 0.72)
    soft:SetBlendMode("ADD")
    frame.gui2ProcSoft = soft

    local pulse = frame:CreateAnimationGroup()
    pulse:SetLooping("REPEAT")
    local fadeIn = pulse:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.65)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.42)
    fadeIn:SetOrder(1)
    local fadeOut = pulse:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0.65)
    fadeOut:SetDuration(0.42)
    fadeOut:SetOrder(2)
    frame.gui2ProcPulse = pulse
    frame.gui2ProcPulseFadeIn = fadeIn
    frame.gui2ProcPulseFadeOut = fadeOut
    frame.gui2ProcBackend = "circle-fallback"
    return frame
end

local function CreateSquareProcFallback(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame.gui2ManagedProcGlow = true
    frame.gui2ProcShape = "square"
    frame.gui2ProcFallback = true
    frame:EnableMouse(false)
    frame:Hide()

    local border = frame:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints(frame)
    border:SetTexture(PROC_SQUARE_FALLBACK)
    border:SetVertexColor(1, 0.78, 0.16, 1)
    border:SetBlendMode("ADD")
    frame.gui2ProcBorder = border

    local pulse = frame:CreateAnimationGroup()
    pulse:SetLooping("REPEAT")
    local fadeIn = pulse:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.65)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.42)
    fadeIn:SetOrder(1)
    local fadeOut = pulse:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0.65)
    fadeOut:SetDuration(0.42)
    fadeOut:SetOrder(2)
    frame.gui2ProcPulse = pulse
    frame.gui2ProcPulseFadeIn = fadeIn
    frame.gui2ProcPulseFadeOut = fadeOut
    frame.gui2ProcBackend = "square-fallback"
    return frame
end

local function CreateCircleProcGlow(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame.gui2ManagedProcGlow = true
    frame.gui2ProcShape = "circle"
    frame.gui2ProcFlipbook = true
    frame:EnableMouse(false)
    frame:SetAlpha(1)
    frame:Hide()

    local startTexture = frame:CreateTexture(nil, "OVERLAY")
    startTexture:SetAllPoints(frame)
    startTexture:SetTexture(PROC_CIRCLE_START)
    startTexture:SetBlendMode("ADD")
    startTexture:SetAlpha(1)
    frame.ProcStartFlipbook = startTexture

    local loopTexture = frame:CreateTexture(nil, "OVERLAY")
    loopTexture:SetPoint("CENTER", frame, "CENTER", 0, 0)
    loopTexture:SetTexture(PROC_CIRCLE_LOOP)
    loopTexture:SetBlendMode("ADD")
    loopTexture:SetAlpha(0)
    frame.ProcLoopFlipbook = loopTexture

    local startGroup = frame:CreateAnimationGroup()
    if startGroup.SetToFinalAlpha then
        startGroup:SetToFinalAlpha(true)
    end
    local startAlpha = CreateAnimation(startGroup, "Alpha")
    local startFlip = CreateAnimation(startGroup, "FlipBook")
    local valid = ConfigureAlpha(
        startAlpha,
        startTexture,
        1,
        1,
        0.001,
        1
    ) and ConfigureFlipbook(
        startFlip,
        startTexture,
        PROC_START_DURATION,
        2
    )
    frame.ProcStartAnim = startGroup
    frame.gui2ProcStartAlphaAnimation = startAlpha
    frame.gui2ProcStartFlipAnimation = startFlip

    local startFade = frame:CreateAnimationGroup()
    if startFade.SetToFinalAlpha then
        startFade:SetToFinalAlpha(true)
    end
    local startFadeAnimation = CreateAnimation(startFade, "Alpha")
    valid = valid and ConfigureAlpha(
        startFadeAnimation,
        startTexture,
        1,
        0,
        PROC_START_FADE_DURATION,
        1,
        PROC_START_FADE_DELAY
    )
    if startFade.SetScript then
        startFade:SetScript("OnFinished", function()
            startTexture:SetAlpha(0)
            startTexture:Hide()
        end)
    end
    frame.ProcStartFadeOut = startFade
    frame.gui2ProcStartFadeAnimation = startFadeAnimation

    local loopGroup = frame:CreateAnimationGroup()
    loopGroup:SetLooping("REPEAT")
    local loopFlipAnimation = CreateAnimation(loopGroup, "FlipBook")
    valid = valid and ConfigureFlipbook(
        loopFlipAnimation,
        loopTexture,
        PROC_LOOP_DURATION,
        1
    )
    frame.ProcLoop = loopGroup
    frame.gui2ProcLoopFlipAnimation = loopFlipAnimation

    local loopFade = frame:CreateAnimationGroup()
    if loopFade.SetToFinalAlpha then
        loopFade:SetToFinalAlpha(true)
    end
    local loopFadeAnimation = CreateAnimation(loopFade, "Alpha")
    valid = valid and ConfigureAlpha(
        loopFadeAnimation,
        loopTexture,
        0,
        1,
        PROC_LOOP_FADE_DURATION,
        1,
        PROC_LOOP_FADE_DELAY
    )
    frame.ProcLoopFadeIn = loopFade
    frame.gui2ProcLoopFadeAnimation = loopFadeAnimation

    if not valid then
        StopProcAnimations(frame)
        return nil
    end
    frame.gui2ProcBackend = "circle-flipbook"
    return frame
end

function GUI2:CreateManagedProcGlow(
    parent,
    shape,
    width,
    height,
    frameLevel,
    frameStrata,
    targetShape
)
    if not parent then return nil end
    shape = shape == "circle" and "circle" or "square"
    local frame
    if shape == "circle" then
        frame = CreateCircleProcGlow(parent)
            or CreateCircleProcFallback(parent)
    else
        local ok, value = pcall(
            CreateFrame,
            "Frame",
            nil,
            parent,
            "ActionButtonSpellAlertTemplate"
        )
        if ok then frame = value end
        if frame then
            frame.gui2ManagedProcGlow = true
            frame.gui2ProcShape = "square"
            frame.gui2ProcTemplate = true
            frame:EnableMouse(false)
            frame:SetAlpha(1)
            frame:Hide()
        end
        frame = frame or CreateSquareProcFallback(parent)
    end
    if frame then
        self:LayoutManagedProcGlow(
            frame,
            parent,
            width,
            height,
            frameLevel,
            frameStrata,
            targetShape or shape
        )
        if self.AdoptIconSkinEffects then self:AdoptIconSkinEffects(parent, frame) end
    end
    return frame
end

function GUI2:LayoutManagedProcGlow(
    frame,
    parent,
    width,
    height,
    frameLevel,
    frameStrata,
    targetShape
)
    if not (frame and parent) then return false end
    if frame.gui2IconSkinHost then return false end
    width = tonumber(width)
        or (parent.GetWidth and parent:GetWidth()) or 36
    height = tonumber(height)
        or (parent.GetHeight and parent:GetHeight()) or 36
    frame.gui2ProcLayoutParent = parent
    frame.gui2ProcLayoutWidth = width
    frame.gui2ProcLayoutHeight = height
    frame.gui2ProcLayoutFrameLevel = frameLevel
    frame.gui2ProcLayoutFrameStrata = frameStrata
    targetShape = targetShape or frame.gui2ProcTargetShape
        or frame.gui2ProcShape
    frame.gui2ProcTargetShape = targetShape
    local insetX, insetY = self:GetIconGlowInset(parent, targetShape, width, height)
    frame.gui2ProcInsetX, frame.gui2ProcInsetY = insetX, insetY
    local visualWidth, visualHeight = GetManagedProcAppearanceSize(
        frame,
        width - insetX * 2,
        height - insetY * 2
    )
    local rotation = targetShape == "diamond" and math.pi / 4 or 0
    if rotation ~= 0 then
        visualWidth, visualHeight = visualWidth / math.sqrt(2), visualHeight / math.sqrt(2)
    end
    if frame.gui2ProcRotation ~= rotation then
        if frame.ProcStartFlipbook and frame.ProcStartFlipbook.SetRotation then frame.ProcStartFlipbook:SetRotation(rotation) end
        if frame.ProcLoopFlipbook and frame.ProcLoopFlipbook.SetRotation then frame.ProcLoopFlipbook:SetRotation(rotation) end
        if frame.gui2ProcBorder and frame.gui2ProcBorder.SetRotation then frame.gui2ProcBorder:SetRotation(rotation) end
        if frame.gui2ProcSoft and frame.gui2ProcSoft.SetRotation then frame.gui2ProcSoft:SetRotation(rotation) end
        frame.gui2ProcRotation = rotation
    end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", parent, "CENTER", 0, 0)
    if type(frameStrata) == "string" and frame.SetFrameStrata then
        frame:SetFrameStrata(frameStrata)
    end
    if type(frameLevel) == "number" and frame.SetFrameLevel then
        frame:SetFrameLevel(frameLevel)
    elseif frame.SetFrameLevel and parent.GetFrameLevel then
        frame:SetFrameLevel((parent:GetFrameLevel() or 0) + 8)
    end
    if frame.gui2ProcTemplate then
        local targetFit = GetManagedProcTargetFit(
            frame,
            visualWidth,
            visualHeight,
            targetShape
        )
        frame:SetSize(
            visualWidth * PROC_TEMPLATE_SCALE + targetFit * 2,
            visualHeight * PROC_TEMPLATE_SCALE + targetFit * 2
        )
        if frame.ProcStartFlipbook then
            frame.ProcStartFlipbook:ClearAllPoints()
            frame.ProcStartFlipbook:SetPoint("CENTER", frame)
            frame.ProcStartFlipbook:SetSize(
                visualWidth * PROC_TEMPLATE_START_SCALE,
                visualHeight * PROC_TEMPLATE_START_SCALE
            )
        end
        if frame.ProcLoopFlipbook then
            frame.ProcLoopFlipbook:ClearAllPoints()
            frame.ProcLoopFlipbook:SetAllPoints(frame)
        end
    elseif frame.gui2ProcFlipbook then
        frame:SetSize(
            visualWidth * PROC_CIRCLE_START_SCALE,
            visualHeight * PROC_CIRCLE_START_SCALE
        )
        frame.ProcStartFlipbook:ClearAllPoints()
        frame.ProcStartFlipbook:SetAllPoints(frame)
        frame.ProcLoopFlipbook:ClearAllPoints()
        frame.ProcLoopFlipbook:SetPoint("CENTER", frame)
        frame.ProcLoopFlipbook:SetSize(
            visualWidth * PROC_CIRCLE_LOOP_SCALE,
            visualHeight * PROC_CIRCLE_LOOP_SCALE
        )
    elseif frame.gui2ProcFallback then
        local targetFit = GetManagedProcTargetFit(
            frame,
            visualWidth,
            visualHeight,
            targetShape
        )
        frame:SetSize(
            visualWidth * PROC_TEMPLATE_SCALE + targetFit * 2,
            visualHeight * PROC_TEMPLATE_SCALE + targetFit * 2
        )
    else
        frame:SetSize(visualWidth + 6, visualHeight + 6)
    end
    return true
end

local function SetManagedProcAnimationDuration(animation, duration)
    if animation and animation.SetDuration then
        pcall(animation.SetDuration, animation, duration)
    end
end

local function SetManagedProcAnimationDelay(animation, delay)
    if animation and animation.SetStartDelay then
        pcall(animation.SetStartDelay, animation, delay)
    end
end

local function SetManagedProcTextureAppearance(
    texture,
    hasCustomColor,
    r,
    g,
    b,
    alpha
)
    if not texture then return end
    if texture.SetDesaturated then
        texture:SetDesaturated(hasCustomColor)
    end
    if texture.SetVertexColor then
        texture:SetVertexColor(r, g, b, alpha)
    end
end

function GUI2:SetManagedProcGlowAppearance(frame, appearance)
    if frame and frame.gui2IconSkinHost then return false end
    if not frame then return false end
    local custom = type(appearance) == "table"
    appearance = custom and appearance or {}
    local hasCustomColor = type(appearance.color) == "table"
    local color = hasCustomColor and appearance.color or DEFAULT_COLOR
    local r = ColorComponent(color, "r", 1, 1)
    local g = ColorComponent(color, "g", 2, 1)
    local b = ColorComponent(color, "b", 3, 1)
    local colorAlpha = ColorComponent(color, "a", 4, 1)
    local alpha = Clamp(appearance.alpha, 0, 1, 1) * colorAlpha
    local size = Clamp(appearance.size, 0.25, 5, 1)
    local speed = Clamp(appearance.speed, 0, 4, 1)
    local effectiveSpeed = math.max(0.2, speed)
    local offsetX = Clamp(
        appearance.offsetX or appearance.xOffset,
        -1,
        1,
        0
    )
    local offsetY = Clamp(
        appearance.offsetY or appearance.yOffset,
        -1,
        1,
        0
    )
    local horizontalCompensation = Clamp(
        appearance.horizontalCompensationPixels,
        0,
        4,
        0
    )
    local changed = frame.gui2ProcAppearanceCustom ~= custom
        or frame.gui2ProcAppearanceHasCustomColor ~= hasCustomColor
        or frame.gui2ProcAppearanceR ~= r
        or frame.gui2ProcAppearanceG ~= g
        or frame.gui2ProcAppearanceB ~= b
        or frame.gui2ProcAppearanceAlpha ~= alpha
        or frame.gui2ProcAppearanceSize ~= size
        or frame.gui2ProcAppearanceSpeed ~= speed
        or frame.gui2ProcAppearanceOffsetX ~= offsetX
        or frame.gui2ProcAppearanceOffsetY ~= offsetY
        or frame.gui2ProcHorizontalCompensationPixels
            ~= horizontalCompensation
    if not changed then return false end

    frame.gui2ProcAppearanceCustom = custom
    frame.gui2ProcAppearanceHasCustomColor = hasCustomColor
    frame.gui2ProcAppearanceR = r
    frame.gui2ProcAppearanceG = g
    frame.gui2ProcAppearanceB = b
    frame.gui2ProcAppearanceAlpha = alpha
    frame.gui2ProcAppearanceSize = size
    frame.gui2ProcAppearanceSpeed = speed
    frame.gui2ProcAppearanceOffsetX = offsetX
    frame.gui2ProcAppearanceOffsetY = offsetY
    frame.gui2ProcHorizontalCompensationPixels = horizontalCompensation

    SetManagedProcTextureAppearance(
        frame.ProcStartFlipbook,
        hasCustomColor,
        r,
        g,
        b,
        alpha
    )
    SetManagedProcTextureAppearance(
        frame.ProcLoopFlipbook,
        hasCustomColor,
        r,
        g,
        b,
        alpha
    )
    SetManagedProcTextureAppearance(
        frame.gui2ProcBorder,
        hasCustomColor,
        r,
        g,
        b,
        alpha
    )
    SetManagedProcTextureAppearance(
        frame.gui2ProcSoft,
        hasCustomColor,
        r,
        g,
        b,
        alpha * 0.72
    )

    SetManagedProcAnimationDuration(
        frame.gui2ProcStartAlphaAnimation,
        0.001 / effectiveSpeed
    )
    SetManagedProcAnimationDuration(
        frame.gui2ProcStartFlipAnimation,
        PROC_START_DURATION / effectiveSpeed
    )
    SetManagedProcAnimationDuration(
        frame.gui2ProcStartFadeAnimation,
        PROC_START_FADE_DURATION / effectiveSpeed
    )
    SetManagedProcAnimationDelay(
        frame.gui2ProcStartFadeAnimation,
        PROC_START_FADE_DELAY / effectiveSpeed
    )
    SetManagedProcAnimationDuration(
        frame.gui2ProcLoopFlipAnimation,
        PROC_LOOP_DURATION / effectiveSpeed
    )
    SetManagedProcAnimationDuration(
        frame.gui2ProcLoopFadeAnimation,
        PROC_LOOP_FADE_DURATION / effectiveSpeed
    )
    SetManagedProcAnimationDelay(
        frame.gui2ProcLoopFadeAnimation,
        PROC_LOOP_FADE_DELAY / effectiveSpeed
    )
    SetManagedProcAnimationDuration(
        frame.gui2ProcPulseFadeIn,
        0.42 / effectiveSpeed
    )
    SetManagedProcAnimationDuration(
        frame.gui2ProcPulseFadeOut,
        0.42 / effectiveSpeed
    )

    if frame.gui2ProcLayoutParent then
        self:LayoutManagedProcGlow(
            frame,
            frame.gui2ProcLayoutParent,
            frame.gui2ProcLayoutWidth,
            frame.gui2ProcLayoutHeight,
            frame.gui2ProcLayoutFrameLevel,
            frame.gui2ProcLayoutFrameStrata,
            frame.gui2ProcTargetShape
        )
    end
    return true
end

function GUI2:SetManagedProcGlowShown(frame, shown)
    if not frame then return false end
    shown = shown == true
    -- 受限后代只使用自己维护的播放请求，不读取可能为 secret 的原生显隐。
    local isShown = frame.gui2ProcPlaying == true
    if not frame.gui2ProcRestricted then isShown = frame.IsShown and frame:IsShown() or false end
    if shown then
        if frame.gui2ProcPlaying == true and isShown then
            return false
        end
    elseif frame.gui2ProcPlaying ~= true and not isShown then
        return false
    end
    if not shown then
        StopProcAnimations(frame)
        return true
    end
    if frame.gui2IconSkinHost and self.RefreshIconSkinProc then self:RefreshIconSkinProc(frame) end
    -- Trigger glows enter their accepted steady loop immediately on every shape.
    -- Entry and crossfade tracks stay inactive; there is no size handoff.
    if frame.ProcStartFlipbook then
        frame.ProcStartFlipbook:SetAlpha(0)
        frame.ProcStartFlipbook:Hide()
    end
    if frame.ProcLoopFlipbook then
        frame.ProcLoopFlipbook:SetAlpha(1)
        frame.ProcLoopFlipbook:Show()
    end
    frame.gui2ProcPlaying = true
    frame:Show()
    PlayAnimationGroup(frame.ProcLoopAnim or frame.ProcLoop)
    PlayAnimationGroup(frame.gui2ProcPulse)
    return true
end

local function GetState(target, state)
    if state then return state end
    if not target then return {} end
    state = Visual.states[target]
    if not state then
        state = {}
        Visual.states[target] = state
    end
    return state
end

local function IsSecretValue(value)
    local Security = YUI.API and YUI.API.Security
    if not (Security and type(Security.IsSecretValue) == "function") then
        return false
    end
    local ok, secret = pcall(Security.IsSecretValue, value)
    return ok and secret == true
end

local function SetShown(region, shown, state, key)
    if not region then return 0 end
    shown = shown == true
    if state[key] == shown then return 0 end
    state[key] = shown
    if region.top or region.bottom or region.left or region.right then
        local edges = {
            region.top,
            region.bottom,
            region.left,
            region.right,
        }
        for index = 1, #edges do
            local edge = edges[index]
            if edge and edge.SetShown then edge:SetShown(shown) end
        end
    elseif region.SetShown then
        region:SetShown(shown)
    elseif shown and region.Show then
        region:Show()
    elseif not shown and region.Hide then
        region:Hide()
    end
    return 1
end

local function HideRegion(region)
    if not region then return end
    if region.top or region.bottom or region.left or region.right then
        local edges = {
            region.top,
            region.bottom,
            region.left,
            region.right,
        }
        for index = 1, #edges do
            local edge = edges[index]
            if edge and edge.Hide then edge:Hide() end
        end
    elseif region.Hide then
        region:Hide()
    end
end

local function ApplyTextureColor(region, color, state, key, colorTexture)
    if not region or SameColor(state[key], color) then return 0 end
    state[key] = CopyColor(color, state[key])
    if region.top or region.bottom or region.left or region.right then
        local edges = {
            region.top,
            region.bottom,
            region.left,
            region.right,
        }
        for index = 1, #edges do
            local edge = edges[index]
            if edge and edge.SetColorTexture then
                edge:SetColorTexture(
                    color[1],
                    color[2],
                    color[3],
                    color[4]
                )
            elseif edge and edge.SetVertexColor then
                edge:SetVertexColor(
                    color[1],
                    color[2],
                    color[3],
                    color[4]
                )
            end
        end
    elseif colorTexture and region.SetColorTexture then
        region:SetColorTexture(color[1], color[2], color[3], color[4])
    elseif region.SetBackdropColor then
        region:SetBackdropColor(color[1], color[2], color[3], color[4])
    elseif region.SetVertexColor then
        region:SetVertexColor(color[1], color[2], color[3], color[4])
    end
    return 1
end

function GUI2:ApplyIconTexCoord(icon, zoom, aspect, state)
    if not (icon and icon.SetTexCoord) then return 0 end
    state = state or {}
    zoom = math.max(0, math.min(tonumber(zoom) or 0, 0.49))
    aspect = tonumber(aspect) or 1
    if state.zoom == zoom and state.aspect == aspect then return 0 end
    state.zoom = zoom
    state.aspect = aspect
    if aspect and aspect > 1 then
        local sourceWidth = 1 - (zoom * 2)
        local sourceHeight = sourceWidth / aspect
        if sourceHeight > 1 then sourceHeight = 1 end
        local top = (1 - sourceHeight) * 0.5
        icon:SetTexCoord(zoom, 1 - zoom, top, 1 - top)
    else
        icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
    end
    return 1
end

local function ResetRegionState(state, key, region, ...)
    if state[key] == region then return end
    state[key] = region
    for index = 1, select("#", ...) do
        state[select(index, ...)] = nil
    end
end

local function ApplyBorderThickness(target, thickness, state, key)
    local pixelOwner = target.pixelOwner
        or target.statusBar
        or target.owner
    local pixelSize = GUI2.GetPixelSize
        and GUI2:GetPixelSize(
            pixelOwner,
            math.max(thickness, 1),
            math.max(thickness, 1)
        )
        or math.max(1, thickness * (GUI2.mult or 1))
    local pixelKey = key .. "Pixel"
    if state[key] == thickness
        and state[pixelKey] == pixelSize then
        return 0
    end
    local applied = false
    if target.SetBorderThickness then
        target:SetBorderThickness(thickness, pixelSize)
        applied = true
    else
        if target.border
            and target.border.top
            and target.border.bottom
            and target.border.left
            and target.border.right then
            if GUI2.LayoutPixelBorder and pixelOwner then
                GUI2:LayoutPixelBorder(
                    target.border,
                    pixelOwner,
                    thickness,
                    0,
                    0,
                    pixelSize
                )
            else
                target.border.top:SetHeight(pixelSize)
                target.border.bottom:SetHeight(pixelSize)
                target.border.left:SetWidth(pixelSize)
                target.border.right:SetWidth(pixelSize)
            end
            applied = true
        else
            local owner = target.owner
            local borders = owner and owner.gui2Borders
            if borders then
                borders.widthPixels = math.max(thickness, 1)
                if owner.UpdateGUI2PixelScale then
                    owner:UpdateGUI2PixelScale()
                end
                applied = true
            end
        end
    end
    state[key] = thickness
    state[pixelKey] = pixelSize
    return applied and 1 or 0
end

function GUI2:ApplyIconChrome(target, snapshot, state)
    if not target then return 0 end
    if self.IsIconSkinManaged and self:IsIconSkinManaged(target.icon or target) then return 0 end
    snapshot = snapshot or {}
    effectBorders[target.owner or target] = snapshot.border
    state = GetState(target, state)
    local border = target.border
    if target.shapeBorder or target.pixelBorder then
        border = snapshot.borderFamily
            and target.shapeBorder or target.pixelBorder
    end
    if state.iconBorderTarget
        and state.iconBorderTarget ~= border then
        HideRegion(state.iconBorderTarget)
    end
    ResetRegionState(
        state,
        "iconBorderTarget",
        border,
        "borderColor",
        "borderShown",
        "iconBorderThickness"
    )
    local writes = self:ApplyIconTexCoord(
        target.icon or target,
        tonumber(snapshot.zoom) or 0.08,
        tonumber(snapshot.aspect) or 1,
        state
    )
    local background = target.background
    local atlas = snapshot.backgroundMode == "blizzard" and "ui-hud-actionbar-iconframe-slot" or nil
    if background and background.SetAtlas and atlas then
        if state.backgroundAtlas ~= atlas then
            background:SetAtlas(atlas)
            background:SetVertexColor(1, 1, 1, 0.92)
            state.backgroundAtlas, state.backgroundColor = atlas, nil
            writes = writes + 2
        end
        if target.mask and state.backgroundMask ~= target.mask and background.AddMaskTexture then
            if state.backgroundMask then background:RemoveMaskTexture(state.backgroundMask) end
            local attached = false
            if background.GetNumMaskTextures and background.GetMaskTexture then
                for index = 1, background:GetNumMaskTextures() do
                    if background:GetMaskTexture(index) == target.mask then attached = true; break end
                end
            end
            if not attached then background:AddMaskTexture(target.mask); writes = writes + 1 end
            state.backgroundMask = target.mask
        end
    else
        if background and state.backgroundAtlas then
            background:SetVertexColor(1, 1, 1, 1)
            state.backgroundAtlas, state.backgroundColor = nil, nil
        end
        writes = writes + ApplyTextureColor(background, snapshot.backgroundColor or DEFAULT_BACKGROUND,
            state, "backgroundColor", true)
    end
    writes = writes + ApplyTextureColor(
        border,
        snapshot.borderColor or DEFAULT_BORDER,
        state,
        "borderColor",
        false
    )
    local borderThickness = tonumber(snapshot.borderThickness) or 0
    writes = writes + ApplyBorderThickness(
        target,
        borderThickness,
        state,
        "iconBorderThickness"
    )
    writes = writes + SetShown(
        border,
        borderThickness > 0,
        state,
        "borderShown"
    )
    if target.mask and target.mask.SetTexture then
        local mask = snapshot.mask
        if state.mask ~= mask then
            state.mask = mask
            target.mask:SetTexture(mask or WHITE)
            writes = writes + 1
        end
        writes = writes + SetShown(
            target.mask,
            mask ~= nil,
            state,
            "maskShown"
        )
    end
    return writes
end

function GUI2:ApplyIconDesaturation(target, amount, state)
    local icon = target and (target.icon or target)
    if not icon then return 0 end
    amount = Clamp(amount, 0, 1, 0)
    state = GetState(icon, state)
    if state.iconDesaturation == amount then return 0 end
    if icon.SetDesaturation then
        icon:SetDesaturation(amount)
    elseif icon.SetDesaturated then
        icon:SetDesaturated(amount > 0)
    else
        return 0
    end
    state.iconDesaturation = amount
    return 1
end

function GUI2:EnsureStatusBarBorder(statusBar)
    if not (statusBar and self.CreateTexture) then return nil end
    local edges = Visual.statusBarBorders[statusBar]
    if edges then return edges end

    local function Edge()
        local texture = self:CreateTexture(statusBar, {
            layer = "OVERLAY",
            subLevel = 7,
        })
        if self.ApplyTexturePixelPolicy then
            self:ApplyTexturePixelPolicy(texture)
        end
        texture:Hide()
        return texture
    end

    edges = {
        top = Edge(),
        bottom = Edge(),
        left = Edge(),
        right = Edge(),
    }
    edges.top:SetPoint("TOPLEFT", statusBar, "TOPLEFT", 0, 0)
    edges.top:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, 0)
    edges.bottom:SetPoint("BOTTOMLEFT", statusBar, "BOTTOMLEFT", 0, 0)
    edges.bottom:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
    edges.left:SetPoint("TOPLEFT", statusBar, "TOPLEFT", 0, 0)
    edges.left:SetPoint("BOTTOMLEFT", statusBar, "BOTTOMLEFT", 0, 0)
    edges.right:SetPoint("TOPRIGHT", statusBar, "TOPRIGHT", 0, 0)
    edges.right:SetPoint("BOTTOMRIGHT", statusBar, "BOTTOMRIGHT", 0, 0)
    Visual.statusBarBorders[statusBar] = edges
    return edges
end

function GUI2:UseStatusBarBorder(component, statusBar)
    if component then
        component.gui2UseStatusBarBorder = true
    end
    return self:EnsureStatusBarBorder(statusBar)
end

function GUI2:ApplyCooldownSwipe(target, drawSwipe, reverse, state)
    local cooldown = target and (target.cooldown or target)
    if not cooldown then return 0 end
    state = GetState(cooldown, state)
    local writes = 0
    if type(drawSwipe) == "boolean"
        and cooldown.SetDrawSwipe and state.drawSwipe ~= drawSwipe then
        cooldown:SetDrawSwipe(drawSwipe)
        state.drawSwipe = drawSwipe
        writes = writes + 1
    end
    if type(reverse) == "boolean"
        and cooldown.SetReverse and state.reverse ~= reverse then
        cooldown:SetReverse(reverse)
        state.reverse = reverse
        writes = writes + 1
    end
    return writes
end

function GUI2:GetCooldownEdgeStyle(snapshot)
    return snapshot and snapshot.cooldownEdge or DEFAULT_COOLDOWN_EDGE
end

function GUI2:ApplyCooldownEdgeStyle(target, snapshot, state)
    local cooldown = target and (target.cooldown or target)
    if not cooldown then return 0 end
    if self.IsIconSkinManaged and self:IsIconSkinManaged(cooldown) then return 0 end
    local edge = self:GetCooldownEdgeStyle(snapshot)
    local color = edge.color
    state = GetState(cooldown, state)
    local writes = 0
    if edge.texture and cooldown.SetEdgeTexture and state.edgeTexture ~= edge.texture then
        cooldown:SetEdgeTexture(edge.texture, color[1], color[2], color[3], color[4])
        state.edgeTexture = edge.texture
        state.edgeColor = CopyColor(color, state.edgeColor)
        -- 纹理 setter 可能重新打开亮边，业务显示策略须在样式之后重申。
        state.drawEdge = nil
        writes = writes + 1
    elseif cooldown.SetEdgeColor and not SameColor(state.edgeColor, color) then
        cooldown:SetEdgeColor(color[1], color[2], color[3], color[4])
        state.edgeColor = CopyColor(color, state.edgeColor)
        writes = writes + 1
    end
    if cooldown.SetEdgeScale and state.edgeScale ~= edge.scale
        and (not state.original or state.original.edgeScale ~= nil) then
        cooldown:SetEdgeScale(edge.scale)
        state.edgeScale = edge.scale
        writes = writes + 1
    end
    if writes > 0 then state.chargeRecoveryRuntime = nil end
    return writes
end

-- 仅在外观/布局变更时调用。尺寸来自配置，绝不读取受限冷却的运行态尺寸。
function GUI2:RestoreIconCooldownLayout(cooldown)
    local layout = cooldown and cooldown.gui2CooldownLayout
    if not (layout and layout.active) then return 0 end
    cooldown:ClearAllPoints()
    for _, point in ipairs(layout.points) do
        cooldown:SetPoint((unpack or table.unpack)(point))
    end
    layout.active = false
    return #layout.points + 1
end

-- Paint only: callers retain region ownership, geometry and semantic visibility.
-- Cache on the existing region; no host, animation or per-refresh table is needed.
function GUI2:PaintIconStateTexture(texture, shape, color, path, force)
    if not texture then return 0 end
    local textures = self.IconStateInnerTextures
    path = path or textures and (textures[shape] or textures.square)
    if not path then return 0 end
    color = color or DEFAULT_COLOR
    local writes = 0
    if force or texture.gui2StatePath ~= path then
        if not (pcall(texture.SetTexture, texture, path)
            and pcall(texture.SetTexCoord, texture, 0, 1, 0, 1)
            and pcall(texture.SetBlendMode, texture, "ADD")) then return writes end
        texture.gui2StatePath = path
        writes = writes + 3
    end
    local r, g, b, a = color[1] or 1, color[2] or 1, color[3] or 1, color[4]
    if a == nil then a = 1 end
    if force or texture.gui2StateR ~= r or texture.gui2StateG ~= g
        or texture.gui2StateB ~= b or texture.gui2StateA ~= a then
        if not pcall(texture.SetVertexColor, texture, r, g, b, a) then return writes end
        texture.gui2StateR, texture.gui2StateG, texture.gui2StateB, texture.gui2StateA = r, g, b, a
        writes = writes + 1
    end
    return writes
end

local StaticIconState = {}
StaticIconState.__index = StaticIconState
function StaticIconState:SetGlowParams(params)
    self.params = params or self.params
    return GUI2:PaintIconStateTexture(self.Texture, self.shape, self.params and self.params.color)
end
function StaticIconState:SetGlowShape(shape)
    self.shape = shape
    return GUI2:PaintIconStateTexture(self.Texture, shape, self.params and self.params.color)
end
function StaticIconState:SetGlowShown(shown)
    shown = shown == true
    if self.shown == shown then return false end
    self.shown = shown
    if shown then self.Texture:Show() else self.Texture:Hide() end
    return true
end

-- A lightweight handle for owners that already have a suitable overlay host.
function GUI2:CreateStaticIconState(target, shape, params)
    local texture = self:CreateTexture(target, { layer = "OVERLAY", subLevel = 7 })
    texture:SetAllPoints(target)
    local state = setmetatable({ target = target, Texture = texture, shape = shape }, StaticIconState)
    state:SetGlowParams(params)
    state:SetGlowShown(false)
    return state
end

-- CDM owns FlashAnim and its (possibly secret) start delays. Reuse its existing
-- Alpha/FlipBook tracks; never replace the group or read/copy the delay.
function GUI2:RestoreIconCooldownFlash(state)
    local flash = state and state.flash
    if not flash or not state.active then return false end
    if state.anchor and not flash.gui2OwnedFlash then contourFlashes[state.anchor] = nil end
    local group, texture = state.group, state.texture
    if flash.gui2OwnedFlash then group:Stop() end
    group.PlayAnim:SetFlipBookRows(11)
    group.PlayAnim:SetFlipBookColumns(2)
    group.PlayAnim:SetFlipBookFrames(22)
    texture:SetAtlas(state.atlas or "UI-HUD-ActionBar-GCD-Flipbook")
    texture:SetRotation(state.rotation or 0)
    texture:ClearAllPoints()
    for _, point in ipairs(state.points) do texture:SetPoint((unpack or table.unpack)(point)) end
    state.active, state.shape, state.anchor = false, nil, nil
    return true
end

function GUI2:ApplyIconCooldownFlash(flash, cooldown, snapshot, state, width, height)
    if not (flash and cooldown and snapshot and state) then return false end
    local shape = snapshot.shape
    if (shape ~= "circle" and shape ~= "diamond")
        or (self.IsIconSkinManaged and self:IsIconSkinManaged(cooldown))
        or IsSecretValue(width) or IsSecretValue(height)
        or type(width) ~= "number" or type(height) ~= "number"
        or width <= 0 or height <= 0 then
        return self:RestoreIconCooldownFlash(state)
    end
    local group, texture = flash.FlashAnim, flash.Flipbook
    if not (texture and group and group.ShowAnim and group.PlayAnim) then return false end
    local layout = cooldown.gui2CooldownLayout
    local layoutX = layout and layout.active and layout.x or 0
    local layoutY = layout and layout.active and layout.y or 0
    local border = layout and layout.active and 0
        or (snapshot.borderThickness or 0) * self:GetPixelSize(cooldown, 1, 1)
    local contentWidth, contentHeight = width - 2 * layoutX, height - 2 * layoutY
    local diameter = math.max(1, math.min(contentWidth, contentHeight) - border * 2)
    -- The circle uses a subtle outward ripple; diamond rotates the native GCD artwork.
    -- Two anchors preserve the original explicit size for restoration. All
    -- arithmetic uses public configuration dimensions, never cooldown:GetSize().
    local quad = diameter * (shape == "circle" and 1.25 or 1.1 / math.sqrt(2))
    local x, y = (contentWidth - quad) / 2, (contentHeight - quad) / 2
    if state.active and state.flash == flash and state.texture == texture and state.group == group
        and state.shape == shape and state.anchor == cooldown
        and state.x == x and state.y == y then return false end
    if state.flash ~= flash or state.texture ~= texture or state.group ~= group then
        self:RestoreIconCooldownFlash(state)
        state.flash, state.points = flash, {}
        state.texture, state.group = texture, group
        state.atlas = texture.GetAtlas and texture:GetAtlas()
        local rotation
        if texture.GetRotation then rotation = texture:GetRotation() end
        state.rotation = not IsSecretValue(rotation) and rotation or 0
        if texture.GetNumPoints then
            for index = 1, texture:GetNumPoints() do
                state.points[index] = { texture:GetPoint(index) }
            end
        end
    end
    if not state.active or state.shape ~= shape then
        -- Native CDM may already be waiting on its secret start delay. Styling
        -- must neither cancel that schedule nor restart it from this moment.
        if flash.gui2OwnedFlash then group:Stop() end
        if shape == "circle" then
            group.PlayAnim:SetFlipBookRows(4)
            group.PlayAnim:SetFlipBookColumns(4)
            group.PlayAnim:SetFlipBookFrames(16)
            texture:SetTexture(COOLDOWN_CIRCLE_RIPPLE)
            texture:SetTexCoord(0, 1, 0, 1)
            texture:SetRotation(0)
        else
            group.PlayAnim:SetFlipBookRows(11)
            group.PlayAnim:SetFlipBookColumns(2)
            group.PlayAnim:SetFlipBookFrames(22)
            texture:SetAtlas(state.atlas or "UI-HUD-ActionBar-GCD-Flipbook")
            texture:SetRotation(math.pi / 4)
        end
    end
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", cooldown, "TOPLEFT", x, -y)
    texture:SetPoint("BOTTOMRIGHT", cooldown, "BOTTOMRIGHT", -x, y)
    if not flash.gui2OwnedFlash then
        if state.anchor and state.anchor ~= cooldown then contourFlashes[state.anchor] = nil end
        contourFlashes[cooldown] = true
    end
    state.active, state.shape, state.anchor, state.x, state.y = true, shape, cooldown, x, y
    return true
end

local function StopOwnedCooldownFlash(flash)
    flash.FlashAnim:Stop()
    flash:Hide()
end

local function OwnedCooldownFlashHidden(flash)
    flash.FlashAnim:Stop()
    flash:Hide()
    if flash.onStopped then flash.onStopped(flash) end
end

local function OwnedCooldownFlashFinished(group)
    group:GetParent():Hide()
end

-- Only for independently owned visuals. Never adopt a live CDM/action-button
-- flash: its native animation may carry secret delays or another active state.
function GUI2:CreateIconCooldownFlash(owner)
    if not (YUI.IsRetail or YUI.IsForever) then return nil end
    local ok, flash = pcall(CreateFrame, "Frame", nil, owner, "ActionButtonCooldownFlashTemplate")
    if not ok then return nil end
    if not (flash.Flipbook and flash.FlashAnim) then flash:Hide(); return nil end
    flash:EnableMouse(false)
    local group = flash.FlashAnim
    group.PlayAnim = group:GetAnimations()
    group.ShowAnim = group:CreateAnimation("Alpha")
    group.ShowAnim:SetChildKey("Flipbook")
    group.ShowAnim:SetOrder(1)
    group.ShowAnim:SetFromAlpha(1)
    group.ShowAnim:SetToAlpha(1)
    group.ShowAnim:SetDuration(0)
    group:SetLooping("NONE")
    group:SetScript("OnFinished", OwnedCooldownFlashFinished)
    flash:SetScript("OnHide", OwnedCooldownFlashHidden)
    flash.gui2FlashState = {}
    flash.gui2OwnedFlash = true
    flash.Stop = StopOwnedCooldownFlash
    flash:Hide()
    return flash
end

function GUI2:LayoutIconCooldownFlash(flash, cooldown, snapshot, width, height, level)
    if not flash then return end
    local state = flash.gui2FlashState
    if state.layoutAnchor ~= cooldown or state.layoutWidth ~= width
        or state.layoutHeight ~= height or state.layoutLevel ~= level then
        flash:Stop()
        flash:ClearAllPoints()
        flash:SetPoint("TOPLEFT", cooldown, "TOPLEFT", 0, 1)
        flash:SetPoint("BOTTOMRIGHT", cooldown, "BOTTOMRIGHT", 0, 1)
        if level then flash:SetFrameLevel(level) end
        state.layoutAnchor, state.layoutWidth, state.layoutHeight, state.layoutLevel = cooldown, width, height, level
    end
    self:ApplyIconCooldownFlash(flash, cooldown, snapshot, state, width, height)
end

function GUI2:PlayIconCooldownFlash(flash)
    if not flash then return false end
    local owner = flash:GetParent()
    if not owner:IsVisible() then return false end
    flash:Stop()
    flash:Show()
    flash.FlashAnim:Play()
    return true
end

function GUI2:ApplyIconCooldownLayout(cooldown, reference, shape, border, width, height)
    if not (cooldown and reference and cooldown.ClearAllPoints and cooldown.SetPoint)
        or (self.IsIconSkinManaged and self:IsIconSkinManaged(cooldown)) then return 0 end
    local inset = self.IconCooldownInsets and self.IconCooldownInsets[border]
    if not inset then return self:RestoreIconCooldownLayout(cooldown) end
    if IsSecretValue(width) or IsSecretValue(height)
        or not (type(width) == "number" and type(height) == "number") then return 0 end
    local preset = self:GetIconAppearancePreset(shape)
    inset = preset.cooldownInsets and preset.cooldownInsets[border] or inset
    local x, y = width * inset, height * (preset.aspect or 1) * inset
    local layout = cooldown.gui2CooldownLayout
    if not layout then layout = {}; cooldown.gui2CooldownLayout = layout end
    if layout.active and layout.reference == reference and layout.x == x and layout.y == y then return 0 end
    if not layout.active then
        layout.points = {}
        if cooldown.GetNumPoints and cooldown.GetPoint then
            local count = cooldown:GetNumPoints()
            if IsSecretValue(count) then return 0 end
            for i = 1, count do
                layout.points[i] = { cooldown:GetPoint(i) }
            end
        end
    end
    cooldown:ClearAllPoints()
    cooldown:SetPoint("TOPLEFT", reference, "TOPLEFT", x, -y)
    cooldown:SetPoint("BOTTOMRIGHT", reference, "BOTTOMRIGHT", -x, y)
    layout.active, layout.reference, layout.x, layout.y = true, reference, x, y
    return 3
end

function GUI2:ApplyCooldownChrome(target, snapshot, state)
    local cooldown = target and (target.cooldown or target)
    if not cooldown then return 0 end
    snapshot = snapshot or {}
    state = GetState(cooldown, state)
    local writes = self:ApplyCooldownSwipe(
        cooldown,
        snapshot.drawSwipe,
        nil,
        state
    )
    local managed = self.IsIconSkinManaged and self:IsIconSkinManaged(cooldown)
    if not managed then writes = writes + self:ApplyCooldownEdgeStyle(cooldown, snapshot, state) end
    local texture = snapshot.swipeTexture or WHITE
    local color = snapshot.swipeColor or DEFAULT_SWIPE
    if not managed and cooldown.SetSwipeTexture
        and (state.swipeTexture ~= texture
            or not SameColor(state.swipeColor, color)) then
        if pcall(
            cooldown.SetSwipeTexture,
            cooldown,
            texture,
            color[1],
            color[2],
            color[3],
            color[4]
        ) then
            state.swipeTexture = texture
            state.swipeColor = CopyColor(color, state.swipeColor)
            writes = writes + 1
        end
    end
    local circular = snapshot.circular == true
    if not managed and cooldown.SetUseCircularEdge and state.circular ~= circular then
        cooldown:SetUseCircularEdge(circular)
        state.circular = circular
        writes = writes + 1
    end
    if not managed and cooldown.SetDrawEdge and state.drawEdge ~= false then
        cooldown:SetDrawEdge(false)
        state.drawEdge = false
        writes = writes + 1
    end
    local drawBling = snapshot.drawBling == true and not self:HasIconCooldownFlash(cooldown)
    if cooldown.SetDrawBling and state.drawBling ~= drawBling then
        cooldown:SetDrawBling(drawBling)
        state.drawBling = drawBling
        writes = writes + 1
    end
    local textStyle = snapshot.cooldownText
    if textStyle then
        if cooldown.SetHideCountdownNumbers
            and state.hideNumbers ~= (textStyle.enabled == false) then
            state.hideNumbers = textStyle.enabled == false
            cooldown:SetHideCountdownNumbers(state.hideNumbers)
            writes = writes + 1
        end
        local text
        if cooldown.GetCountdownFontString then
            local ok, value = pcall(
                cooldown.GetCountdownFontString,
                cooldown
            )
            if ok then text = value end
        end
        if text then
            state.text = state.text or {}
            writes = writes + self:ApplyTextStyle(
                text,
                textStyle,
                state.text
            )
        end
    end
    return writes
end

local countMeasureFrame, countMeasureText
local countMeasureFont, countMeasureSize, countMeasureOutline
local countMeasureWidth, countMeasureHeight

function GUI2:SizeStatusBarCountText(fontString, appearance, state)
    appearance = type(appearance) == "table" and appearance or {}
    if state and state.numericRegion == fontString
        and state.numericFont == appearance.font
        and state.numericSize == appearance.size
        and state.numericOutline == appearance.outline
        and state.numericMonochrome == (appearance.monochrome == true) then return false end
    if not countMeasureText then
        -- 测量对象不进入 AuraFrame 子树，永远只接收公开数字样本。
        countMeasureFrame = GUI2:CreateFrame(_G.UIParent, {
            hidden = true, mouse = false,
        })
        countMeasureText = GUI2:CreateText(countMeasureFrame, "", 13)
        countMeasureText:SetWordWrap(false)
    end
    appearance = type(appearance) == "table" and appearance or {}
    GUI2:ApplyFontAppearance(countMeasureText, appearance)
    local font, size, outline = countMeasureText:GetFont()
    if countMeasureFont ~= font or countMeasureSize ~= size
        or countMeasureOutline ~= outline then
        local width, height = 0, 0
        for digit = 0, 9 do
            countMeasureText:SetText(string.rep(tostring(digit), 10))
            width = math.max(width, countMeasureText:GetStringWidth())
            height = math.max(height, countMeasureText:GetStringHeight())
        end
        countMeasureWidth = math.ceil(width) + 4
        countMeasureHeight = math.ceil(math.max(height, size)) + 4
        countMeasureFont, countMeasureSize, countMeasureOutline =
            font, size, outline
    end
    fontString:SetWordWrap(false)
    fontString:SetNonSpaceWrap(false)
    fontString:SetMaxLines(1)
    fontString:SetJustifyV("MIDDLE")
    fontString:SetSize(countMeasureWidth, countMeasureHeight)
    if state then
        state.numericRegion, state.numericFont = fontString, appearance.font
        state.numericSize, state.numericOutline = appearance.size, appearance.outline
        state.numericMonochrome = appearance.monochrome == true
    end
    return true
end

function GUI2:ApplyTextStyle(target, snapshot, state)
    if not (target and target.SetFont) then return 0 end
    snapshot = snapshot or {}
    state = GetState(target, state)
    local writes = 0
    local font = snapshot.font or "default"
    local size = snapshot.size or 12
    local outline = snapshot.outline or "none"
    local monochrome = snapshot.monochrome == true
    if state.font ~= font
        or state.fontSize ~= size
        or state.fontOutline ~= outline
        or state.fontMonochrome ~= monochrome then
        self:ApplyFontAppearance(target, snapshot)
        state.font = font
        state.fontSize = size
        state.fontOutline = outline
        state.fontMonochrome = monochrome
        writes = writes + 1
    end
    local color = snapshot.color or DEFAULT_COLOR
    local red = ColorComponent(color, "r", 1, DEFAULT_COLOR[1])
    local green = ColorComponent(color, "g", 2, DEFAULT_COLOR[2])
    local blue = ColorComponent(color, "b", 3, DEFAULT_COLOR[3])
    local alpha = ColorComponent(color, "a", 4, DEFAULT_COLOR[4])
    if target.SetTextColor and not (state.color
        and state.color[1] == red
        and state.color[2] == green
        and state.color[3] == blue
        and state.color[4] == alpha) then
        target:SetTextColor(red, green, blue, alpha)
        state.color = state.color or {}
        state.color[1], state.color[2] = red, green
        state.color[3], state.color[4] = blue, alpha
        writes = writes + 1
    end
    if target.SetShown and state.preserveVisibility ~= true then
        writes = writes + SetShown(
            target,
            snapshot.enabled ~= false,
            state,
            "shown"
        )
    end
    if state.preserveAnchors ~= true and target.ClearAllPoints and target.SetPoint
        and not (self.IsIconSkinManaged and self:IsIconSkinManaged(target)) then
        local position = snapshot.position or "center"
        local point = "CENTER"
        local justify = "CENTER"
        local x = tonumber(snapshot.offsetX) or 0
        local y = tonumber(snapshot.offsetY) or 0
        if position == "top" then
            point = "TOP"
        elseif position == "bottom" then
            point = "BOTTOM"
        elseif position == "left" then
            point = "LEFT"
            justify = "LEFT"
        elseif position == "right" then
            point = "RIGHT"
            justify = "RIGHT"
        elseif position == "top-left" then
            point = "TOPLEFT"
            x = x + 2
            y = y - 2
            justify = "LEFT"
        elseif position == "bottom-left" then
            point = "BOTTOMLEFT"
            x = x + 2
            y = y + 2
            justify = "LEFT"
        elseif position == "top-right" then
            point = "TOPRIGHT"
            x = x - 2
            y = y - 2
            justify = "RIGHT"
        elseif position == "bottom-right" then
            point = "BOTTOMRIGHT"
            x = x - 2
            y = y + 2
            justify = "RIGHT"
        end
        local parent = target.GetParent and target:GetParent() or nil
        local layout = parent and parent.gui2CooldownLayout
        if layout and layout.active then parent = layout.reference end
        if state.anchorPoint ~= point
            or state.anchorParent ~= parent
            or state.anchorX ~= x
            or state.anchorY ~= y
            or state.anchorJustify ~= justify then
            target:ClearAllPoints()
            if parent then
                target:SetPoint(point, parent, point, x, y)
            else
                target:SetPoint(point, x, y)
            end
            if target.SetJustifyH then target:SetJustifyH(justify) end
            state.anchorPoint = point
            state.anchorParent = parent
            state.anchorX = x
            state.anchorY = y
            state.anchorJustify = justify
            writes = writes + 1
        end
    end
    return writes
end

function GUI2:PositionStatusBarText(
    fontString,
    appearance,
    orientation,
    track,
    icon,
    showIcon,
    kind,
    state,
    preferPosition,
    trustedWidth
)
    if not (fontString and track
        and fontString.ClearAllPoints and fontString.SetPoint) then
        return false
    end
    appearance = type(appearance) == "table" and appearance or {}
    state = GetState(fontString, state)
    local anchor = appearance.anchor
    if type(anchor) ~= "string" or anchor == "auto" then
        local position = appearance.position
        if preferPosition == true
            and (position == "center"
                or position == "top"
                or position == "bottom"
                or position == "left"
                or position == "right"
                or position == "top-left"
                or position == "bottom-left"
                or position == "top-right"
                or position == "bottom-right") then
            anchor = position == "center"
                and "bar-center" or "bar-" .. position
        elseif kind == "count" then
            if orientation == "vertical" then
                anchor = "bar-outside-top"
            else
                anchor = showIcon == false
                    and "bar-outside-right" or "icon-bottom-right"
            end
        elseif kind == "time" then
            anchor = orientation == "vertical"
                and "bar-bottom" or "bar-right"
        else
            anchor = "bar-center"
        end
    elseif anchor:find("icon-", 1, true) == 1
        and (showIcon == false or not icon) then
        anchor = "bar-" .. anchor:sub(6)
    end

    local target = anchor:find("icon-", 1, true) == 1
        and icon or track
    if not target then return false end
    local point = "CENTER"
    local relativePoint = "CENTER"
    local x, y = 0, 0
    local justify = "CENTER"
    local outside = anchor:find("bar%-outside%-") == 1
    local top = anchor:find("top", 1, true) ~= nil
    local bottom = anchor:find("bottom", 1, true) ~= nil
    local left = anchor:find("left", 1, true) ~= nil
    local right = anchor:find("right", 1, true) ~= nil
    if outside then
        if top then
            point, relativePoint, y = "BOTTOM", "TOP", 2
        elseif bottom then
            point, relativePoint, y = "TOP", "BOTTOM", -2
        elseif left then
            point, relativePoint, x, justify =
                "RIGHT", "LEFT", -2, "RIGHT"
        else
            point, relativePoint, x, justify =
                "LEFT", "RIGHT", 2, "LEFT"
        end
    elseif top and left then
        point, relativePoint, x, y, justify =
            "TOPLEFT", "TOPLEFT", 2, -2, "LEFT"
    elseif top and right then
        point, relativePoint, x, y, justify =
            "TOPRIGHT", "TOPRIGHT", -2, -2, "RIGHT"
    elseif bottom and left then
        point, relativePoint, x, y, justify =
            "BOTTOMLEFT", "BOTTOMLEFT", 2, 2, "LEFT"
    elseif bottom and right then
        point, relativePoint, x, y, justify =
            "BOTTOMRIGHT", "BOTTOMRIGHT", -2, 2, "RIGHT"
    elseif top then
        point, relativePoint, y = "TOP", "TOP", -2
    elseif bottom then
        point, relativePoint, y = "BOTTOM", "BOTTOM", 2
    elseif left then
        point, relativePoint, x, justify = "LEFT", "LEFT", 3, "LEFT"
    elseif right then
        point, relativePoint, x, justify = "RIGHT", "RIGHT", -3, "RIGHT"
    end
    x = x + (tonumber(appearance.offsetX) or 0)
    y = y + (tonumber(appearance.offsetY) or 0)

    local changed = state.region ~= fontString or state.target ~= target
        or state.point ~= point or state.relativePoint ~= relativePoint
        or state.x ~= x or state.y ~= y or state.justify ~= justify
    if changed then
        fontString:ClearAllPoints()
        fontString:SetPoint(point, target, relativePoint, x, y)
        if fontString.SetJustifyH then
            fontString:SetJustifyH(justify)
        end
        if state then
            state.region = fontString
            state.target = target
            state.point = point
            state.relativePoint = relativePoint
            state.x, state.y = x, y
            state.justify = justify
        end
    end
    if kind == "name" and fontString.SetWidth then
        local layoutWidth
        if type(trustedWidth) == "number"
            and not IsSecretValue(trustedWidth) then
            layoutWidth = trustedWidth
        elseif track.GetWidth then
            local ok, value = pcall(track.GetWidth, track)
            if ok and type(value) == "number"
                and not IsSecretValue(value) then
                layoutWidth = value
            end
        end
        if layoutWidth == nil then
            state.nameWidth = nil
            return true, anchor, changed
        end
        local width = math.max(1, layoutWidth - 8)
        if state.nameWidth ~= width or state.nameWidthRegion ~= fontString then
            fontString:SetWidth(width)
            state.nameWidth = width
            state.nameWidthRegion = fontString
            changed = true
        end
    end
    return true, anchor, changed
end

function GUI2:ApplyStatusBarChrome(target, snapshot, state)
    if not target then return 0 end
    snapshot = snapshot or {}
    state = GetState(target, state)
    ResetRegionState(
        state,
        "statusBorderTarget",
        target.border,
        "statusBorderColor",
        "statusBorderShown",
        "statusBorderThickness"
    )
    local bar = target.statusBar or target.bar or target
    local writes = self:ApplyNativeStatusBarStyle(
        bar,
        snapshot,
        target.orientation,
        target.fillDirection,
        target.forceNativeStatusBarStyle == true
    )
    target.forceNativeStatusBarStyle = nil
    writes = writes + ApplyTextureColor(
        target.track or target.background,
        snapshot.trackColor or DEFAULT_BACKGROUND,
        state,
        "trackColor",
        true
    )
    writes = writes + ApplyTextureColor(
        target.border,
        snapshot.borderColor or DEFAULT_BORDER,
        state,
        "statusBorderColor",
        false
    )
    local borderThickness = tonumber(snapshot.borderThickness) or 0
    writes = writes + ApplyBorderThickness(
        target,
        borderThickness,
        state,
        "statusBorderThickness"
    )
    writes = writes + SetShown(
        target.border,
        borderThickness > 0,
        state,
        "statusBorderShown"
    )
    return writes
end

function GUI2:RestoreVisual(target, state)
    if not target then return false end
    self:RestoreIconCooldownLayout(target.cooldown)
    state = state or Visual.states[target]
    if not state then return false end
    local original = state.original
    if original then
        local icon = target.icon or target
        if icon and icon.SetTexCoord and original.texCoord then
            icon:SetTexCoord(
                original.texCoord[1],
                original.texCoord[2],
                original.texCoord[3],
                original.texCoord[4]
            )
        end
        local cooldown = target.cooldown
        if cooldown and state.edgeTexture and original.edgeTexture
            and cooldown.SetEdgeTexture then
            local color = original.edgeColor or DEFAULT_COLOR
            cooldown:SetEdgeTexture(original.edgeTexture, color[1], color[2], color[3], color[4])
        end
        if cooldown and state.edgeScale and original.edgeScale ~= nil
            and cooldown.SetEdgeScale then
            cooldown:SetEdgeScale(original.edgeScale)
        end
        if cooldown and original.hideNumbers ~= nil
            and cooldown.SetHideCountdownNumbers then
            cooldown:SetHideCountdownNumbers(original.hideNumbers)
        end
        if cooldown and original.drawEdge ~= nil
            and cooldown.SetDrawEdge then
            cooldown:SetDrawEdge(original.drawEdge)
        end
        if cooldown and original.drawBling ~= nil
            and cooldown.SetDrawBling then
            cooldown:SetDrawBling(original.drawBling)
        end
        if cooldown and original.drawSwipe ~= nil
            and cooldown.SetDrawSwipe then
            cooldown:SetDrawSwipe(original.drawSwipe)
        end
        if cooldown and original.reverse ~= nil
            and cooldown.SetReverse then
            cooldown:SetReverse(original.reverse)
        end
        if cooldown and original.rotation ~= nil
            and cooldown.SetRotation then
            cooldown:SetRotation(original.rotation)
        end
        if cooldown and original.useCircularEdge ~= nil
            and cooldown.SetUseCircularEdge then
            cooldown:SetUseCircularEdge(original.useCircularEdge)
        end
        if cooldown and original.swipeTexture
            and original.swipeColor
            and cooldown.SetSwipeTexture then
            pcall(
                cooldown.SetSwipeTexture,
                cooldown,
                original.swipeTexture,
                original.swipeColor[1],
                original.swipeColor[2],
                original.swipeColor[3],
                original.swipeColor[4]
            )
        end
        local bar = target.statusBar or target.bar
        if bar and original.statusBarTexture
            and bar.SetStatusBarTexture then
            bar:SetStatusBarTexture(original.statusBarTexture)
        end
        if bar and original.statusBarColor
            and bar.SetStatusBarColor then
            bar:SetStatusBarColor(
                original.statusBarColor[1],
                original.statusBarColor[2],
                original.statusBarColor[3],
                original.statusBarColor[4]
            )
        end
        if bar then
            self:InvalidateNativeStatusBarStyle(bar)
        end
        local track = target.track or target.background
        if track and original.trackTexture and track.SetTexture then
            track:SetTexture(original.trackTexture)
        end
        if track and original.trackColor and track.SetVertexColor then
            track:SetVertexColor(
                original.trackColor[1],
                original.trackColor[2],
                original.trackColor[3],
                original.trackColor[4]
            )
        end
    end
    Visual.states[target] = nil
    return true
end

function GUI2:CaptureVisual(target, state)
    if not target then return nil end
    state = GetState(target, state)
    if state.original then return state end
    local original = {}
    local icon = target.icon or target
    if icon and icon.GetTexCoord then
        original.texCoord = { icon:GetTexCoord() }
    end
    local cooldown = target.cooldown
    if cooldown and cooldown.GetEdgeScale then
        local ok, value = pcall(cooldown.GetEdgeScale, cooldown)
        if ok and not IsSecretValue(value) and type(value) == "number" then
            original.edgeScale = value
        end
    end
    if cooldown and cooldown.GetHideCountdownNumbers then
        original.hideNumbers = cooldown:GetHideCountdownNumbers()
    end
    if cooldown and cooldown.GetDrawEdge then
        local ok, value = pcall(cooldown.GetDrawEdge, cooldown)
        if ok then original.drawEdge = value end
    end
    if cooldown and cooldown.GetDrawBling then
        local ok, value = pcall(cooldown.GetDrawBling, cooldown)
        if ok then original.drawBling = value end
    end
    if cooldown and cooldown.GetDrawSwipe then
        local ok, value = pcall(cooldown.GetDrawSwipe, cooldown)
        if ok then original.drawSwipe = value end
    end
    if cooldown and cooldown.GetReverse then
        local ok, value = pcall(cooldown.GetReverse, cooldown)
        if ok then original.reverse = value end
    end
    if cooldown and cooldown.GetRotation then
        local ok, value = pcall(cooldown.GetRotation, cooldown)
        if ok then original.rotation = value end
    end
    local bar = target.statusBar or target.bar
    if bar and bar.GetStatusBarTexture then
        local texture = bar:GetStatusBarTexture()
        if texture and texture.GetTexture then
            original.statusBarTexture = texture:GetTexture()
        elseif type(texture) == "string" then
            original.statusBarTexture = texture
        end
    end
    if bar and bar.GetStatusBarColor then
        original.statusBarColor = { bar:GetStatusBarColor() }
    end
    local track = target.track or target.background
    if track and track.GetTexture then
        original.trackTexture = track:GetTexture()
    end
    if track and track.GetVertexColor then
        original.trackColor = { track:GetVertexColor() }
    end
    state.original = original
    return state
end

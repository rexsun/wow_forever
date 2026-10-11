local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD or YUI.IsRetail == false then return end

local GUI2 = YUI.GUI2
local App = GUI2 and GUI2.Application
local Event = YUI.Event
local Visibility = YUI.Visibility
local UnitAPI = YUI.API and YUI.API.Unit
local SpellAPI = YUI.API and YUI.API.Spell
if not (GUI2 and GUI2.CreateFrame and UnitAPI and SpellAPI) then return end

local Skyriding = YHUD.Skyriding or {}
YHUD.Skyriding = Skyriding

local CreateFrame = _G.CreateFrame
local GetTime = _G.GetTime
local math_abs = math.abs
local math_exp = math.exp
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local string_format = string.format
local tonumber = tonumber
local tostring = tostring
local type = type

local LAYOUT_ID = "yhud.skyriding"
local GROUP_ID = YHUD.GROUP_IDS and YHUD.GROUP_IDS.SKYRIDING
    or "group:system:skyriding"
local FIXED_VISIBILITY_RULE = { skyriding = "in" }
local UPDATE_INTERVAL = 1 / 60
local BASE_RUN_SPEED = 7
local SPEED_RESPONSE = 10
local SPEED_EPSILON = 0.0005
local PIP_EPSILON = 0.003
local RECHARGE_ALPHA = 0.5

local SPELL_SKYWARD_ASCENT = 372610
local SPELL_SECOND_WIND = 425782
local SPELL_WHIRLING_SURGE = 361584

local DEFAULT_STYLE_ID = "halo"
local BASE_STYLE = {
    maxSpeedPercent = 1300,
    thrillSpeedPercent = 789,
    normalColor = { 0.08, 0.72, 0.82, 1 },
    thrillColor = { 1.00, 0.58, 0.12, 1 },
    vigorColor = { 0.10, 0.88, 0.64, 1 },
    secondWindColor = { 1.00, 0.76, 0.18, 1 },
    backgroundColor = { 0.025, 0.035, 0.055, 0.88 },
    emptyColor = { 0.08, 0.10, 0.14, 0.94 },
    tickColor = { 1, 1, 1, 0.62 },
}

local BUILTIN_STYLES = {
    horizon = {
        id = "horizon",
        nameKey = "skyriding.style.horizon",
        buildKind = "horizon",
    },
    halo = {
        id = "halo",
        nameKey = "skyriding.style.halo",
        buildKind = "halo",
    },
}

for _, style in pairs(BUILTIN_STYLES) do
    for field, value in pairs(BASE_STYLE) do
        if style[field] == nil then style[field] = value end
    end
end

Skyriding.styles = Skyriding.styles or {}
Skyriding.styles.horizon = BUILTIN_STYLES.horizon
Skyriding.styles.halo = BUILTIN_STYLES.halo
Skyriding.styleId = DEFAULT_STYLE_ID
Skyriding.settings = Skyriding.settings
    or (YHUD.NormalizeSkyridingSettings
        and YHUD:NormalizeSkyridingSettings(nil)
        or { enabled = false, style = DEFAULT_STYLE_ID, styles = {} })
Skyriding.enabled = Skyriding.settings.enabled == true
Skyriding.surfaces = Skyriding.surfaces or {}
Skyriding.active = Skyriding.active == true
Skyriding.designerPreview = Skyriding.designerPreview == true
Skyriding.layoutPreview = Skyriding.layoutPreview == true
Skyriding.elapsed = 0
Skyriding.smoothedSpeed = 0
Skyriding.speedFraction = -1
Skyriding.vigorDirty = true
Skyriding.secondWindDirty = true
Skyriding.cooldownDirty = true
Skyriding.gcdDirty = true
Skyriding.vigorActive = false
Skyriding.secondWindActive = false

local visibilityOwner = {}
local spellOwner = {}

local function RootOnUpdate(_, elapsed)
    local ok, err = pcall(Skyriding.OnUpdate, Skyriding, elapsed)
    if not ok and Skyriding.HandleRuntimeFailure then
        Skyriding:HandleRuntimeFailure("update", err)
    end
end

local function T(key, fallback)
    return YHUD:T(key, fallback)
end

local function SetShown(frame, shown)
    if not frame then return false end
    shown = shown == true
    local current = frame.IsShown and frame:IsShown() == true
    if current == shown then return false end
    if shown then frame:Show() else frame:Hide() end
    return true
end

local function SetStatusBarValue(bar, value, epsilon)
    if not bar then return false end
    value = math_max(0, math_min(1, tonumber(value) or 0))
    local current = tonumber(bar._yhudSkyridingValue)
    if current and math_abs(current - value) <= (epsilon or 0) then
        return false
    end
    bar._yhudSkyridingValue = value
    bar:SetValue(value)
    return true
end

local function CreateSolidTexture(parent, layer, color)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetTexture("Interface\\Buttons\\WHITE8x8")
    texture:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    texture:SetAllPoints(parent)
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
    return texture
end

local function CreateBar(parent, height, color, emptyColor)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(height)
    bar:SetMinMaxValues(0, 1)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
    bar.bg = CreateSolidTexture(bar, "BACKGROUND", emptyColor)
    SetStatusBarValue(bar, 0)
    if GUI2.CreateBorder then GUI2:CreateBorder(bar, "color.border.subtle") end
    return bar
end

local function CreatePipRow(parent, count, height, color, emptyColor)
    local row = GUI2:CreateFrame(parent, { height = height })
    row.pips = {}
    for index = 1, count do
        row.pips[index] = CreateBar(row, height, color, emptyColor)
    end
    return row
end

local function CreateCooldownIcon(parent, spellID, size, appearance)
    appearance = type(appearance) == "table" and appearance or {}
    local info = SpellAPI.GetInfo and SpellAPI.GetInfo(spellID)
    local iconTexture = info and (info.iconID or info.originalIconID)
        or "Interface\\Icons\\INV_Misc_QuestionMark"
    if App and App.CreateCooldownIcon then
        return App:CreateCooldownIcon(parent, {
            size = size,
            icon = iconTexture,
            shape = appearance.shape or "square",
            border = appearance.border or "thin",
            variant = appearance.variant or "bare",
            cooldownText = {
                enabled = true,
                font = "default",
                size = 12,
                outline = "outline",
                position = "center",
            },
        })
    end
    local icon = GUI2:CreateFrame(parent, { width = size, height = size })
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints(icon)
    icon.texture:SetTexture(iconTexture)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.cooldown = CreateFrame(
        "Cooldown",
        nil,
        icon,
        "CooldownFrameTemplate"
    )
    icon.cooldown:SetAllPoints(icon)
    icon.cooldown:SetDrawEdge(false)
    if icon.cooldown.SetHideCountdownNumbers then
        icon.cooldown:SetHideCountdownNumbers(false)
    end
    if GUI2.CreateBorder then GUI2:CreateBorder(icon, "color.border.default") end
    return icon
end

local function CreateSpeedBar(parent, height, style)
    local speed = CreateBar(
        parent,
        height,
        style.normalColor,
        style.backgroundColor
    )
    speed.tick = speed:CreateTexture(nil, "OVERLAY")
    speed.tick:SetTexture("Interface\\Buttons\\WHITE8x8")
    speed.text = GUI2:CreateText(
        speed,
        "0%",
        "font.size.sm",
        "color.text.primary",
        "CENTER"
    )
    return speed
end

local function SetStatusColor(target, color)
    if not (target and color) then return end
    target:SetStatusBarColor(
        color.r or color[1],
        color.g or color[2],
        color.b or color[3],
        color.a or color[4] or 1
    )
end

local function LayoutPips(row, width, gap)
    local count = #row.pips
    for index = 1, count do
        local pip = row.pips[index]
        pip:ClearAllPoints()
        pip:SetPoint("TOP", row, "TOP", 0, 0)
        pip:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
        if index == 1 then
            pip:SetPoint("LEFT", row, "LEFT", 0, 0)
        else
            pip:SetPoint("LEFT", row.pips[index - 1], "RIGHT", gap, 0)
        end
        if index == count then
            pip:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        else
            pip:SetWidth(math_max(1, (width - gap * (count - 1)) / count))
        end
    end
end

local function ApplySpeedFont(surface, settings)
    local text = surface and surface.speed and surface.speed.text
    if not text then return end
    if GUI2.ApplyFontAppearance then
        GUI2:ApplyFontAppearance(text, {
            font = settings.speedFont or "default",
            size = tonumber(settings.speedFontSize) or 12,
            outline = "outline",
        })
    end
end

local function BuildHaloSurface(root, style)
    local surface = GUI2:CreateFrame(root, { hidden = true })
    surface.stack = GUI2:CreateFrame(surface, { width = 340, height = 41 })
    surface.speed = CreateSpeedBar(surface.stack, 16, style)
    surface.speed.text:SetPoint("CENTER", surface.speed, "CENTER", 0, 0)
    surface.vigor = CreatePipRow(
        surface.stack,
        6,
        10,
        style.vigorColor,
        style.emptyColor
    )
    surface.secondWind = CreatePipRow(
        surface.stack,
        3,
        7,
        style.secondWindColor,
        style.emptyColor
    )
    surface.cooldown = CreateCooldownIcon(surface, SPELL_WHIRLING_SURGE, 41)
    surface:Hide()
    return surface
end

local function BuildHorizonSurface(root, style)
    local surface = GUI2:CreateFrame(root, { hidden = true })
    surface.speed = CreateSpeedBar(surface, 18, style)
    surface.vigor = CreatePipRow(
        surface,
        6,
        8,
        style.vigorColor,
        style.emptyColor
    )
    surface.secondWind = CreatePipRow(
        surface,
        3,
        8,
        style.secondWindColor,
        style.emptyColor
    )
    surface.cooldown = CreateCooldownIcon(
        surface,
        SPELL_WHIRLING_SURGE,
        48,
        {
            shape = "circle",
            border = "none",
            variant = "bare",
        }
    )
    if App and App.CreateDurationRing then
        surface.gcdRing = App:CreateDurationRing(surface, {
            size = 54,
            thickness = 4,
            material = "framed",
            reverse = true,
            fillColor = "color.state.warning",
            trackColor = { 0.06, 0.10, 0.17, 1 },
            centerColor = { 0, 0, 0, 0 },
            contentSize = 48,
            bezelPixels = 2,
            shadowPixels = 1,
            contactOverlapPixels = 1,
            cooldownText = { enabled = false },
        })
    end
    if surface.speed.SetFrameLevel then surface.speed:SetFrameLevel(1) end
    if surface.vigor.SetFrameLevel then surface.vigor:SetFrameLevel(2) end
    if surface.secondWind.SetFrameLevel then
        surface.secondWind:SetFrameLevel(2)
    end
    if surface.gcdRing and surface.gcdRing.SetFrameLevel then
        surface.gcdRing:SetFrameLevel(4)
    end
    if surface.cooldown.SetFrameLevel then surface.cooldown:SetFrameLevel(7) end
    surface:Hide()
    return surface
end

function Skyriding:RegisterStyle(id, style)
    if type(id) ~= "string" or id == "" or type(style) ~= "table" then
        return false
    end
    style.id = id
    self.styles[id] = style
    return true
end

function Skyriding:GetStyle()
    return self.styles[self.styleId] or self.styles[DEFAULT_STYLE_ID]
end

function Skyriding:GetStyleSettings(styleId)
    styleId = self.styles[styleId] and styleId or self.styleId
    local settings = self.settings and self.settings.styles
    return settings and settings[styleId]
        or (YHUD.GetDefaultSkyridingStyleSettings
            and YHUD:GetDefaultSkyridingStyleSettings(styleId))
        or {}
end

function Skyriding:ResolveHorizonRingSize(
    ring,
    iconSize,
    ringThickness,
    contactOverlap
)
    iconSize = math_max(1, tonumber(iconSize) or 48)
    ringThickness = tonumber(ringThickness) or 4
    if ringThickness >= 11 then
        ringThickness = 14
    elseif ringThickness >= 6 then
        ringThickness = 8
    else
        ringThickness = 4
    end
    local pixelSize = math_max(0, tonumber(contactOverlap) or 0)
    local ringSize = iconSize + ringThickness * 2
    if ring and ring.ResolveDurationRingMetrics then
        local _, resolvedStroke, _, resolvedOuterRadius =
            ring:ResolveDurationRingMetrics(
                iconSize,
                ringThickness,
                iconSize,
                ringThickness
            )
        local resolvedInnerRadius =
            (tonumber(resolvedOuterRadius) or 0)
            - (tonumber(resolvedStroke) or 0)
        local targetInnerRadius = math_max(
            1,
            iconSize * 0.5 + pixelSize * 2
        )
        if resolvedInnerRadius > 0 then
            ringSize = iconSize * targetInnerRadius
                / resolvedInnerRadius
        end
    end
    return ringSize, ringThickness
end

function Skyriding:SetStyle(id)
    if id ~= DEFAULT_STYLE_ID or not self.styles[id] then return false end
    if self.styleId == id then return true end
    local previous = self.activeSurface
    self.styleId = id
    if previous then previous:Hide() end
    self.activeSurface = nil
    self.cooldownDirty = true
    self.gcdDirty = true
    self.vigorDirty = true
    self.secondWindDirty = true
    if self.root then self:ApplyStyle() end
    return true
end

function Skyriding:ApplySettings(profile, deferRuntimeSync)
    local settings = YHUD.GetSkyridingSettings
        and YHUD:GetSkyridingSettings(profile)
        or { enabled = false, style = DEFAULT_STYLE_ID, styles = {} }
    local styleId = self.styles[settings.style]
        and settings.style or DEFAULT_STYLE_ID
    settings.style = styleId
    self.settings = settings
    self.enabled = settings.enabled == true
    local changed = self.styleId ~= styleId
    self.styleId = styleId
    if changed and self.activeSurface then self.activeSurface:Hide() end
    if changed then self.activeSurface = nil end
    self.cooldownDirty = true
    self.gcdDirty = true
    if self.root then self:ApplyStyle() end
    if YUI.Layout and YUI.Layout.InvalidateAnchorProvider then
        YUI.Layout:InvalidateAnchorProvider(LAYOUT_ID)
    end
    if self.active and deferRuntimeSync ~= true
        and self.SyncConfigurationActivity then
        local synced, code = self:SyncConfigurationActivity()
        if synced == nil then return nil, code end
    end
    return settings
end

function Skyriding:GetDefaultPlacement()
    return {
        anchor = {
            point = "TOP",
            relative = "UIParent",
            relativePoint = "CENTER",
        },
        offset = { x = 0, y = -200 },
    }
end

function Skyriding:MeasureHaloLayout(settings)
    return tonumber(settings.width) or 340,
        (tonumber(settings.speedHeight) or 16)
        + (tonumber(settings.vigorHeight) or 10)
        + (tonumber(settings.secondWindHeight) or 7)
        + (tonumber(settings.rowGap) or 4) * 2
end

function Skyriding:ApplyStyle()
    local root = self.root
    local style = self:GetStyle()
    if not (root and style) then return false end
    local surface = self.surfaces[self.styleId]
    if not surface then
        surface = style.buildKind == "halo"
            and BuildHaloSurface(root, style)
            or BuildHorizonSurface(root, style)
        self.surfaces[self.styleId] = surface
    end
    for id, candidate in pairs(self.surfaces) do
        SetShown(candidate, self.enabled == true and id == self.styleId)
    end
    self.activeSurface = surface
    root.speed = surface.speed
    root.vigor = surface.vigor
    root.secondWind = surface.secondWind
    root.cooldown = surface.cooldown
    root.gcdRing = surface.gcdRing

    local settings = self:GetStyleSettings(self.styleId)
    local totalWidth = tonumber(settings.width) or 340
    local speedHeight = tonumber(settings.speedHeight) or 16
    local rowGap = tonumber(settings.rowGap) or 4
    local pipGap = tonumber(settings.pipGap) or 3
    local vigorColor = settings.vigorColor or style.vigorColor
    local secondWindColor = settings.secondWindColor or style.secondWindColor
    local speedWidth = totalWidth
    local rootHeight

    surface:ClearAllPoints()
    surface:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    if self.styleId == "halo" then
        local vigorHeight = tonumber(settings.vigorHeight) or 10
        local secondWindHeight = tonumber(settings.secondWindHeight) or 7
        local _, stackHeight = self:MeasureHaloLayout(settings)
        local iconSize = stackHeight
        speedWidth = math_max(1, totalWidth - iconSize - rowGap)
        rootHeight = stackHeight
        surface:SetSize(totalWidth, rootHeight)
        surface.stack:SetSize(speedWidth, stackHeight)
        surface.stack:ClearAllPoints()
        surface.stack:SetPoint("LEFT", surface, "LEFT", 0, 0)
        surface.speed:SetSize(speedWidth, speedHeight)
        surface.speed:ClearAllPoints()
        surface.speed:SetPoint("TOPLEFT", surface.stack, "TOPLEFT", 0, 0)
        surface.vigor:SetSize(speedWidth, vigorHeight)
        surface.vigor:ClearAllPoints()
        surface.vigor:SetPoint("TOPLEFT", surface.speed, "BOTTOMLEFT", 0, -rowGap)
        surface.secondWind:SetSize(speedWidth, secondWindHeight)
        surface.secondWind:ClearAllPoints()
        surface.secondWind:SetPoint(
            "TOPLEFT",
            surface.vigor,
            "BOTTOMLEFT",
            0,
            -rowGap
        )
        surface.cooldown:SetSize(iconSize, iconSize)
        if surface.cooldown.SetIconAppearance then
            surface.cooldown:SetIconAppearance({
                size = iconSize,
                shape = "square",
                border = "thin",
            })
        end
        surface.cooldown:ClearAllPoints()
        surface.cooldown:SetPoint("LEFT", surface.stack, "RIGHT", rowGap, 0)
        surface.speed.text:ClearAllPoints()
        surface.speed.text:SetPoint("CENTER", surface.speed, "CENTER", 0, 0)
        LayoutPips(surface.vigor, speedWidth, pipGap)
        LayoutPips(surface.secondWind, speedWidth, pipGap)
    else
        local resourceHeight = tonumber(settings.resourceHeight) or 8
        local iconSize = tonumber(settings.iconSize) or 48
        surface.cooldown:SetSize(iconSize, iconSize)
        if surface.cooldown.SetIconAppearance then
            surface.cooldown:SetIconAppearance({
                size = iconSize,
                shape = "circle",
                border = "none",
            })
        end
        local resolvedIconSize = surface.cooldown.GetWidth
            and tonumber(surface.cooldown:GetWidth()) or iconSize
        resolvedIconSize = math_max(1, resolvedIconSize or iconSize)
        local contactOverlap = GUI2.GetPixelSize
            and GUI2:GetPixelSize(surface.cooldown, 1, 1) or 1
        local ringSize, ringThickness = self:ResolveHorizonRingSize(
            surface.gcdRing,
            resolvedIconSize,
            settings.ringThickness,
            contactOverlap
        )
        local visualRingSize = ringSize
        local visualRingOverflow = contactOverlap * 3
        if surface.gcdRing then
            if surface.gcdRing.SetDurationRingStyle then
                surface.gcdRing:SetDurationRingStyle({
                    direction = "clockwise",
                    reverse = true,
                    start = "top",
                    thickness = ringThickness,
                    material = "framed",
                    contentSize = resolvedIconSize,
                    bezelPixels = 2,
                    shadowPixels = 1,
                    contactOverlapPixels = 1,
                })
            end
            if surface.gcdRing.SetDurationRingSize then
                surface.gcdRing:SetDurationRingSize(
                    ringSize,
                    0,
                    ringThickness,
                    resolvedIconSize,
                    ringThickness
                )
            else
                surface.gcdRing:SetSize(ringSize, ringSize)
            end
            if surface.gcdRing.GetDurationRingVisualSize then
                visualRingSize = surface.gcdRing:GetDurationRingVisualSize()
            end
            if surface.gcdRing.GetDurationRingVisualOverflow then
                visualRingOverflow =
                    surface.gcdRing:GetDurationRingVisualOverflow()
            end
        end
        local stackHeight = speedHeight + rowGap + resourceHeight
        local centerY = resourceHeight + rowGap + speedHeight * 0.5
        local bottomPad = math_max(0, visualRingSize * 0.5 - centerY)
        local contentHeight = math_max(
            stackHeight + bottomPad,
            bottomPad + centerY + visualRingSize * 0.5
        )
        rootHeight = contentHeight
        local halfGap = visualRingSize * 0.5 + 4
        local resourceWidth = math_max(1, totalWidth * 0.5 - halfGap)
        surface:SetSize(totalWidth, rootHeight)
        surface.speed:SetSize(totalWidth, speedHeight)
        surface.speed:ClearAllPoints()
        surface.speed:SetPoint(
            "BOTTOMLEFT",
            surface,
            "BOTTOMLEFT",
            0,
            bottomPad + resourceHeight + rowGap
        )
        surface.vigor:SetSize(resourceWidth, resourceHeight)
        surface.vigor:ClearAllPoints()
        surface.vigor:SetPoint("BOTTOMLEFT", surface, "BOTTOMLEFT", 0, bottomPad)
        surface.secondWind:SetSize(resourceWidth, resourceHeight)
        surface.secondWind:ClearAllPoints()
        surface.secondWind:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", 0, bottomPad)
        surface.cooldown:ClearAllPoints()
        surface.cooldown:SetPoint(
            "CENTER",
            surface,
            "BOTTOM",
            0,
            bottomPad + centerY
        )
        if surface.gcdRing then
            surface.gcdRing:ClearAllPoints()
            surface.gcdRing:SetPoint("CENTER", surface.cooldown, "CENTER", 0, 0)
        end
        surface.speed.text:ClearAllPoints()
        surface.speed.text:SetPoint(
            "BOTTOM",
            surface.gcdRing or surface.cooldown,
            "TOP",
            0,
            4 + visualRingOverflow
        )
        LayoutPips(surface.vigor, resourceWidth, pipGap)
        LayoutPips(surface.secondWind, resourceWidth, pipGap)
    end

    root:SetSize(totalWidth, rootHeight)
    root:SetScale(1)
    ApplySpeedFont(surface, settings)
    surface.speed:SetStatusBarColor(unpack(style.normalColor))
    surface.speed.bg:SetVertexColor(unpack(style.backgroundColor))
    for index = 1, #surface.vigor.pips do
        SetStatusColor(surface.vigor.pips[index], vigorColor)
        surface.vigor.pips[index].bg:SetVertexColor(unpack(style.emptyColor))
    end
    for index = 1, #surface.secondWind.pips do
        SetStatusColor(surface.secondWind.pips[index], secondWindColor)
        surface.secondWind.pips[index].bg:SetVertexColor(unpack(style.emptyColor))
    end
    local threshold = (tonumber(style.thrillSpeedPercent) or 0)
        / math_max(1, tonumber(style.maxSpeedPercent) or 1)
    threshold = math_max(0, math_min(1, threshold))
    surface.speed.tick:ClearAllPoints()
    surface.speed.tick:SetPoint("TOP", surface.speed, "TOP", 0, 0)
    surface.speed.tick:SetPoint("BOTTOM", surface.speed, "BOTTOM", 0, 0)
    surface.speed.tick:SetPoint(
        "CENTER",
        surface.speed,
        "LEFT",
        speedWidth * threshold,
        0
    )
    surface.speed.tick:SetWidth(GUI2.GetPixelSize
        and GUI2:GetPixelSize(surface.speed, 1, 1) or 1)
    surface.speed.tick:SetVertexColor(unpack(style.tickColor))
    local view = YHUD.View
    if view and view.designMode and self.runtime
        and view.RefreshDesignChromeGeometry then
        view:RefreshDesignChromeGeometry(self.runtime)
    end
    return true
end

function Skyriding:RegisterRuntimeGroup()
    local root = self.root
    local view = YHUD.View
    if not (root and view and view.groups) then return false end
    if self.runtime and view.groups[GROUP_ID] == self.runtime then
        return true
    end
    local runtime = {
        id = GROUP_ID,
        frame = root,
        baseFrameStrata = root.GetFrameStrata
            and root:GetFrameStrata() or "MEDIUM",
        baseFrameLevel = root.GetFrameLevel
            and root:GetFrameLevel() or 1,
        group = {
            id = GROUP_ID,
            kind = "system",
            name = T("skyriding.title", "驭龙术"),
            layout = "resource",
            order = 1000,
            displayLayer = 5,
            visibility = FIXED_VISIBILITY_RULE,
        },
        enabled = true,
        monitorCount = 0,
        monitorIds = {},
        monitorLanes = {},
        nativeFrames = {},
        nativeByMonitor = {},
        nativeCategories = {},
        layoutEligible = true,
        visibilityAllowed = false,
        visibilityReason = "initial",
        presentationReady = false,
        runtimeOwned = true,
        designContent = true,
        layoutId = LAYOUT_ID,
        ignoreDesignerSurface = true,
        ignoreDesignBypass = true,
    }
    view.groups[GROUP_ID] = runtime
    self.runtime = runtime
    if view.designMode and view.RefreshDesignModePresentation then
        view:RefreshDesignModePresentation(true, true, true)
    end
    return true
end

function Skyriding:Build()
    if self.root then
        self:RegisterRuntimeGroup()
        return self.root
    end
    local root = GUI2:CreateFrame(_G.UIParent, {
        name = "YUI_YHUD_Skyriding",
        width = 420,
        height = 76,
        frameStrata = "MEDIUM",
    })
    root:Hide()
    root.surfaces = self.surfaces
    self.root = root
    self:RegisterRuntimeGroup()
    self:ApplyStyle()
    return root
end

function Skyriding:UnregisterRuntimeGroup()
    local view = YHUD.View
    if view and view.groups and view.groups[GROUP_ID] == self.runtime then
        view.groups[GROUP_ID] = nil
    end
    self.runtime = nil
    return true
end

function Skyriding:RegisterLayout()
    if self.layoutRegistered then return true end
    local Layout = YUI.Layout
    local root = self:Build()
    if not (Layout and Layout.RegisterFrame and root) then
        root:ClearAllPoints()
        root:SetPoint("TOP", _G.UIParent, "CENTER", 0, -200)
        return false
    end
    local entry = Layout:RegisterFrame(LAYOUT_ID, {
        frame = root,
        title = T("skyriding.title", "驭龙术"),
        category = "product",
        editModeCategory = "monitor",
        editModeFilterGroup = "monitor.skyriding",
        editModeDefaultVisible = false,
        defaultPlacement = function()
            return Skyriding:GetDefaultPlacement()
        end,
        movable = true,
        snap = true,
        pixelAlignOrigin = true,
        minWidth = 120,
        minHeight = 36,
        isEnabled = function()
            return Skyriding.active == true
        end,
        openPluginSettings = function()
            if YHUD.DesignerUI and YHUD.DesignerUI.Open then
                local opened = YHUD.DesignerUI:Open("layout")
                if opened and YHUD.DesignerUI.SetDesignerMode then
                    YHUD.DesignerUI:SetDesignerMode("skyriding")
                end
                return opened
            end
            return YHUD:OpenSettings()
        end,
        onEnterEditMode = function()
            local visible = Layout.IsEditMoverVisible
                and Layout:IsEditMoverVisible(LAYOUT_ID) ~= false
            Skyriding:SetLayoutPreview(visible)
        end,
        onExitEditMode = function()
            Skyriding:SetLayoutPreview(false)
        end,
        onEditModeFilterChanged = function(_, visible)
            Skyriding:SetLayoutPreview(visible == true)
        end,
    })
    self.layoutRegistered = entry ~= nil and entry ~= false
    return self.layoutRegistered
end

function Skyriding:UnregisterLayout()
    local Layout = YUI.Layout
    if self.layoutRegistered and Layout and Layout.UnregisterFrame then
        Layout:UnregisterFrame(LAYOUT_ID)
    end
    self.layoutRegistered = false
end

function Skyriding:IsPreviewing()
    return self.designerPreview == true or self.layoutPreview == true
end

function Skyriding:ReadGlidingInfo()
    if self:IsPreviewing() then
        return true, true, BASE_RUN_SPEED * 8.6, "preview"
    end
    return UnitAPI.GetPlayerGlidingInfo()
end

function Skyriding:UpdateSpeed(dt, forwardSpeed)
    local style = self:GetStyle()
    local target = math_max(0, tonumber(forwardSpeed) or 0)
    local alpha = 1 - math_exp(-SPEED_RESPONSE * math_max(0, dt or 0))
    self.smoothedSpeed = self.smoothedSpeed
        + (target - self.smoothedSpeed) * alpha
    if target == 0 and self.smoothedSpeed < 0.01 then self.smoothedSpeed = 0 end
    local speedPercent = self.smoothedSpeed / BASE_RUN_SPEED * 100
    local fraction = math_max(0, math_min(
        1,
        speedPercent / math_max(1, style.maxSpeedPercent or 1)
    ))
    if SetStatusBarValue(self.root.speed, fraction, SPEED_EPSILON) then
        self.root.speed.text:SetText(string_format(
            "%d%%",
            math_floor(speedPercent + 0.5)
        ))
        local color = speedPercent >= (style.thrillSpeedPercent or 0)
            and style.thrillColor or style.normalColor
        self.root.speed:SetStatusBarColor(unpack(color))
    end
end

local function ApplyChargeRow(row, count, info, previewCurrent, previewProgress)
    if not info and previewCurrent == nil then return false end
    local current = info and tonumber(info.currentCharges) or previewCurrent or 0
    local maximum = info and tonumber(info.maxCharges) or count
    maximum = math_max(1, math_min(count, maximum or count))
    current = math_max(0, math_min(maximum, current or 0))
    local progress = previewProgress or 0
    if info and current < maximum
        and (tonumber(info.cooldownDuration) or 0) > 0 then
        local elapsed = GetTime() - (tonumber(info.cooldownStartTime) or 0)
        progress = elapsed / info.cooldownDuration
    end
    progress = math_max(0, math_min(1, progress))
    for index = 1, count do
        local pip = row.pips[index]
        local recharging = index == current + 1 and current < maximum
        local value = index <= current and 1
            or (recharging and progress or 0)
        if pip._yhudSkyridingRecharging ~= recharging then
            pip:GetStatusBarTexture():SetAlpha(recharging and RECHARGE_ALPHA or 1)
            pip._yhudSkyridingRecharging = recharging
        end
        SetStatusBarValue(pip, value, PIP_EPSILON)
    end
    return current < maximum
end

function Skyriding:UpdateCharges()
    local preview = self:IsPreviewing()
    if self.vigorDirty or self.vigorActive or preview then
        local info = not preview and SpellAPI.GetCharges
            and SpellAPI.GetCharges(SPELL_SKYWARD_ASCENT) or nil
        self.vigorActive = ApplyChargeRow(
            self.root.vigor,
            6,
            info,
            preview and 4 or nil,
            preview and 0.65 or nil
        )
        self.vigorDirty = false
    end
    if self.secondWindDirty or self.secondWindActive or preview then
        local info = not preview and SpellAPI.GetCharges
            and SpellAPI.GetCharges(SPELL_SECOND_WIND) or nil
        self.secondWindActive = ApplyChargeRow(
            self.root.secondWind,
            3,
            info,
            preview and 1 or nil,
            preview and 0.42 or nil
        )
        self.secondWindDirty = false
    end
end

function Skyriding:UpdateCooldown()
    if not self.cooldownDirty and not self:IsPreviewing() then return end
    local startTime, duration
    if self:IsPreviewing() then
        startTime = GetTime() - 4
        duration = 12
    else
        local info = SpellAPI.GetCooldown
            and SpellAPI.GetCooldown(SPELL_WHIRLING_SURGE)
        startTime = info and tonumber(info.startTime) or 0
        duration = info and tonumber(info.duration) or 0
        if duration <= 1.5 then startTime, duration = 0, 0 end
    end
    if self.cooldownStart ~= startTime or self.cooldownDuration ~= duration then
        if duration > 0 then
            self.root.cooldown.cooldown:SetCooldown(startTime, duration)
        elseif self.root.cooldown.cooldown.Clear then
            self.root.cooldown.cooldown:Clear()
        end
        self.cooldownStart = startTime
        self.cooldownDuration = duration
    end
    self.cooldownDirty = false
end

function Skyriding:UpdateGCD()
    if not self.gcdDirty and not self:IsPreviewing() then return false end
    local ring = self.activeSurface and self.activeSurface.gcdRing
    if not ring then
        self.gcdDirty = false
        return false
    end
    local applied = false
    if self:IsPreviewing() then
        if ring.SetDurationFromTimes then
            applied = ring:SetDurationFromTimes(GetTime() - 0.45, 1.5, 1)
                ~= false
        end
    else
        local durationObject = SpellAPI.GetGlobalCooldownDurationObject
            and SpellAPI.GetGlobalCooldownDurationObject()
        if durationObject and ring.SetDurationObject then
            applied = ring:SetDurationObject(durationObject, true) ~= false
        elseif ring.ClearDuration then
            ring:ClearDuration()
            applied = true
        end
    end
    self.gcdDirty = false
    return applied
end

function Skyriding:NeedsTick()
    return self.enabled == true and (self:IsPreviewing()
        or self.isGliding == true
        or self.smoothedSpeed > 0
        or self.vigorDirty == true
        or self.secondWindDirty == true
        or self.gcdDirty == true
        or self.vigorActive == true
        or self.secondWindActive == true)
end

function Skyriding:SyncTick()
    local root = self.root
    if not root then return end
    local wanted = root:IsShown() and self:NeedsTick()
    local current = root:GetScript("OnUpdate") ~= nil
    if current == wanted then return end
    root:SetScript("OnUpdate", wanted and RootOnUpdate or nil)
end

function Skyriding:OnUpdate(dt)
    self.elapsed = self.elapsed + (tonumber(dt) or 0)
    if self.elapsed < UPDATE_INTERVAL then return end
    local elapsed = self.elapsed
    self.elapsed = 0
    local isGliding, canGlide, speed = self:ReadGlidingInfo()
    self.isGliding = isGliding == true
    self.canGlide = canGlide == true
    if not self:IsPreviewing() and canGlide ~= true then
        self:HidePresentation()
        return
    end
    self:UpdateSpeed(elapsed, self.isGliding and speed or 0)
    self:UpdateCharges()
    self:UpdateCooldown()
    if self.gcdDirty then self:UpdateGCD() end
    self:SyncTick()
end

function Skyriding:RegisterSpellEvents()
    if self.spellEventsRegistered or not (Event and Event.On) then return end
    Event:On("SPELL_UPDATE_CHARGES", "RefreshCharges", spellOwner, {
        moduleId = YHUD.PRODUCT_ID,
        traceName = "YHUD:SkyridingCharges",
    })
    Event:On("SPELL_UPDATE_COOLDOWN", "RefreshCooldown", spellOwner, {
        moduleId = YHUD.PRODUCT_ID,
        traceName = "YHUD:SkyridingCooldown",
    })
    local castEvents = {
        "UNIT_SPELLCAST_START",
        "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED",
        "UNIT_SPELLCAST_STOP",
    }
    for index = 1, #castEvents do
        Event:On(castEvents[index], "RefreshGCD", spellOwner, {
            unit = "player",
            moduleId = YHUD.PRODUCT_ID,
            traceName = "YHUD:SkyridingGCD",
        })
    end
    self.spellEventsRegistered = true
end

function Skyriding:UnregisterSpellEvents()
    if self.spellEventsRegistered and Event and Event.OffOwner then
        Event:OffOwner(spellOwner)
    end
    self.spellEventsRegistered = false
end

function Skyriding:HidePresentation()
    self.presentationCommitted = false
    pcall(self.UnregisterSpellEvents, self)
    if self.runtime then self.runtime.presentationReady = false end
    local root = self.root
    if root then
        pcall(root.SetScript, root, "OnUpdate", nil)
        local view = YHUD.View
        if view and view.ProjectGroupVisibility and self.runtime then
            pcall(view.ProjectGroupVisibility, view, GROUP_ID)
        else
            pcall(SetShown, root, false)
        end
        self.elapsed = 0
        self.smoothedSpeed = 0
        if root.speed then
            pcall(SetStatusBarValue, root.speed, 0)
            if root.speed.text and root.speed.text.SetText then
                pcall(root.speed.text.SetText, root.speed.text, "0%")
            end
        end
        local ring = self.activeSurface and self.activeSurface.gcdRing
        if ring and ring.ClearDuration then pcall(ring.ClearDuration, ring) end
    end
    return true
end

function Skyriding:HandleRuntimeFailure(stage, err, deactivate)
    local code = "skyriding-" .. tostring(stage or "runtime")
    self.lastRuntimeError = tostring(err or code)
    self:HidePresentation()
    if deactivate == true then
        pcall(self.UnregisterVisibilityEvents, self)
        self.active = false
        pcall(self.UnregisterLayout, self)
        pcall(self.UnregisterRuntimeGroup, self)
    end
    local diagnostics = YHUD.Diagnostics
    if diagnostics and diagnostics.Record then
        pcall(diagnostics.Record, diagnostics, "skyriding-runtime", {
                stage = tostring(stage or "runtime"),
                error = self.lastRuntimeError,
            })
    end
    return nil, code
end

function Skyriding:RefreshVisibility()
    if not self.active then return false end
    local runtime = self.runtime

    if self.enabled ~= true then
        local buildOK, root = pcall(self.Build, self)
        if not buildOK or not root then
            return self:HandleRuntimeFailure(
                "build-disabled",
                buildOK and "missing-root" or root
            )
        end
        self:UnregisterSpellEvents()
        self:SyncTick()
        self.elapsed = 0
        self.smoothedSpeed = 0
        self.isGliding = false
        self.canGlide = false
        self.vigorActive = false
        self.secondWindActive = false
        self.presentationCommitted = false
        for _, surface in pairs(self.surfaces) do
            SetShown(surface, false)
        end
        local ring = self.activeSurface and self.activeSurface.gcdRing
        if ring and ring.ClearDuration then ring:ClearDuration() end
        local preview = self:IsPreviewing()
        if runtime then
            runtime.presentationReady = preview
            runtime.visibilityAllowed = preview
            runtime.visibilityReason = preview
                and "disabled-preview" or "disabled"
        end
        local view = YHUD.View
        if view and view.ProjectGroupVisibility and runtime then
            local shownOK, shownError = pcall(
                view.ProjectGroupVisibility,
                view,
                GROUP_ID
            )
            if not shownOK then
                return self:HandleRuntimeFailure(
                    "show-disabled",
                    shownError
                )
            end
        else
            SetShown(root, preview)
        end
        return preview
    end

    local visible = runtime and runtime.visibilityAllowed == true
    if not visible then
        self:HidePresentation()
        return false
    end

    local buildOK, root = pcall(self.Build, self)
    if not buildOK or not root then
        return self:HandleRuntimeFailure(
            "build",
            buildOK and "missing-root" or root
        )
    end
    self.vigorDirty = true
    self.secondWindDirty = true
    self.cooldownDirty = true
    self.gcdDirty = true
    local chargesOK, chargesError = pcall(self.UpdateCharges, self)
    if not chargesOK then
        return self:HandleRuntimeFailure("charges", chargesError)
    end
    local cooldownOK, cooldownError = pcall(self.UpdateCooldown, self)
    if not cooldownOK then
        return self:HandleRuntimeFailure("cooldown", cooldownError)
    end
    local gcdOK, gcdError = pcall(self.UpdateGCD, self)
    if not gcdOK then
        return self:HandleRuntimeFailure("gcd", gcdError)
    end
    local eventsOK, eventsError = pcall(self.RegisterSpellEvents, self)
    if not eventsOK then
        return self:HandleRuntimeFailure("spell-events", eventsError)
    end
    self.presentationCommitted = true
    if runtime then runtime.presentationReady = true end
    local shownOK, shownError
    local view = YHUD.View
    if view and view.ProjectGroupVisibility and runtime then
        shownOK, shownError = pcall(
            view.ProjectGroupVisibility,
            view,
            GROUP_ID
        )
    else
        shownOK, shownError = pcall(SetShown, root, true)
    end
    if not shownOK then
        return self:HandleRuntimeFailure("show", shownError)
    end
    local tickOK, tickError = pcall(self.SyncTick, self)
    if not tickOK then
        return self:HandleRuntimeFailure("tick", tickError)
    end
    self.lastRuntimeError = nil
    return true
end

function Skyriding:SetDesignerPreview(enabled)
    enabled = enabled == true
    if self.designerPreview == enabled then return false end
    self.designerPreview = enabled
    if self.visibilityHandle and Visibility and Visibility.SetBypass then
        Visibility:SetBypass(self.visibilityHandle, self:IsPreviewing())
    else
        self:RefreshVisibility()
    end
    local view = YHUD.View
    if view and view.designMode then
        if view.ApplyGroupDisplayLayers then
            view:ApplyGroupDisplayLayers(view.profile)
        end
        if view.RefreshDesignModePresentation then
            view:RefreshDesignModePresentation(true, true, true)
        end
    end
    return true
end

function Skyriding:SetLayoutPreview(enabled)
    enabled = enabled == true
    if self.layoutPreview == enabled then return false end
    self.layoutPreview = enabled
    if self.visibilityHandle and Visibility and Visibility.SetBypass then
        Visibility:SetBypass(self.visibilityHandle, self:IsPreviewing())
    else
        self:RefreshVisibility()
    end
    return true
end

function visibilityOwner:RefreshSkyriding(visible, reason)
    local runtime = Skyriding.runtime
    if runtime then
        runtime.visibilityAllowed = visible ~= false
        runtime.visibilityReason = reason
    end
    Skyriding:RefreshVisibility()
end

function spellOwner:RefreshCharges()
    Skyriding.vigorDirty = true
    Skyriding.secondWindDirty = true
    local ok, err = pcall(Skyriding.SyncTick, Skyriding)
    if not ok then Skyriding:HandleRuntimeFailure("charge-event", err) end
end

function spellOwner:RefreshCooldown()
    Skyriding.cooldownDirty = true
    Skyriding.gcdDirty = true
    local ok, err = pcall(function()
        Skyriding:UpdateCooldown()
        Skyriding:UpdateGCD()
    end)
    if not ok then Skyriding:HandleRuntimeFailure("cooldown-event", err) end
end

function spellOwner:RefreshGCD()
    Skyriding.gcdDirty = true
    local ok, err = pcall(Skyriding.UpdateGCD, Skyriding)
    if not ok then Skyriding:HandleRuntimeFailure("gcd-event", err) end
end

function Skyriding:RegisterVisibilityEvents()
    if self.visibilityEventsRegistered then return true end
    if not (Visibility and Visibility.Watch) then
        return nil, "visibility-unavailable"
    end
    local handle = Visibility:Watch(
        visibilityOwner,
        FIXED_VISIBILITY_RULE,
        "RefreshSkyriding",
        {
            moduleId = YHUD.PRODUCT_ID,
            bypass = self:IsPreviewing(),
        }
    )
    if not handle then return nil, "visibility-register-failed" end
    self.visibilityHandle = handle
    self.visibilityEventsRegistered = true
    return true
end

function Skyriding:UnregisterVisibilityEvents()
    if self.visibilityHandle and Visibility and Visibility.Release then
        Visibility:Release(self.visibilityHandle)
    end
    self.visibilityHandle = nil
    self.visibilityEventsRegistered = false
    return true
end

function Skyriding:SyncConfigurationActivity()
    if not self.active then return false end
    if self.enabled == true then
        local registered, code = self:RegisterVisibilityEvents()
        if not registered then return nil, code end
    else
        self:UnregisterVisibilityEvents()
    end
    return self:RefreshVisibility()
end

function Skyriding:Enable(profile)
    if self.active then
        local settingsOK, settingsError = pcall(
            self.ApplySettings,
            self,
            profile,
            true
        )
        if not settingsOK then
            return self:HandleRuntimeFailure("settings", settingsError)
        end
        local synced, code = self:SyncConfigurationActivity()
        if synced == nil then return nil, code end
        return true
    end
    self.active = true
    local buildOK, root = pcall(self.Build, self)
    if not buildOK or not root then
        return self:HandleRuntimeFailure(
            "build",
            buildOK and "missing-root" or root,
            true
        )
    end
    local settingsOK, settingsError = pcall(
        self.ApplySettings,
        self,
        profile,
        true
    )
    if not settingsOK then
        return self:HandleRuntimeFailure("settings", settingsError, true)
    end
    local layoutOK, layoutError = pcall(self.RegisterLayout, self)
    if not layoutOK then
        return self:HandleRuntimeFailure("layout", layoutError, true)
    end
    local synced, code = self:SyncConfigurationActivity()
    if synced == nil then
        return self:HandleRuntimeFailure(
            "configuration-activity",
            code,
            true
        )
    end
    return true
end

function Skyriding:Disable()
    self:HidePresentation()
    self:UnregisterSpellEvents()
    self:UnregisterVisibilityEvents()
    self.spellEventsRegistered = false
    self.active = false
    self.designerPreview = false
    self.layoutPreview = false
    self.isGliding = false
    self.canGlide = false
    self.presentationCommitted = false
    self.elapsed = 0
    self.smoothedSpeed = 0
    self:UnregisterLayout()
    self:UnregisterRuntimeGroup()
    return true
end

Skyriding.LAYOUT_ID = LAYOUT_ID
Skyriding.GROUP_ID = GROUP_ID
Skyriding.DEFAULT_STYLE_ID = DEFAULT_STYLE_ID

-- Cold geometry must not initialize the product or its runtime profile.
if YUI.Layout and YUI.Layout.RegisterAnchorProvider then
    YUI.Layout:RegisterAnchorProvider(LAYOUT_ID, {
        name = "YUI_YHUD_Skyriding",
        resolve = function()
            local profile = YUI.DB and YUI.DB.GetProfile and YUI.DB:GetProfile()
            if not profile or not YHUD.NormalizeSkyridingSettings then return nil end
            local db = profile[YHUD.STORAGE_KEY or "YHUD"]
            local config = db and db.profile
            local settings = YHUD:NormalizeSkyridingSettings(config and config.skyriding)
            if settings.style ~= "halo" then return nil end
            local width, height = Skyriding:MeasureHaloLayout(settings.styles.halo)
            return Skyriding:GetDefaultPlacement(), width, height, 1
        end,
    })
end

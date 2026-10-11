local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local GUI2 = YUI.GUI2
local App = GUI2 and GUI2.Application
if not (GUI2 and GUI2.CreateFrame and App and App.CreateCooldownIcon) then return end

local View = YHUD.View or {}
YHUD.View = View

local ResourceCatalog = YHUD.ResourceCatalog
local Glow = YHUD.Glow
local RuntimeSound = YHUD.Sound
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local DEFAULT_ICON_SIZE = 42
local DEFAULT_SPACING = 6
local DEFAULT_MAX_PER_LINE = 6
local DEFAULT_BAR_WIDTH = 244
local DEFAULT_BAR_HEIGHT = 24
local DEFAULT_RING_DIAMETER = 52
local DEFAULT_RESOURCE_WIDTH = 290
local DEFAULT_RESOURCE_HEIGHT = 16
local EMPTY_DESIGN_GROUP_WIDTH = 120

local LAYOUT_VIEWS = {
    icons = "icon",
    bars = "bar",
    rings = "ring",
    resource = "resource",
}

View.groups = View.groups or {}
View.byMonitor = View.byMonitor or {}
View.monitorsBySource = View.monitorsBySource or {}
View.desiredMonitors = View.desiredMonitors or {}
View.combatGlowMonitors = View.combatGlowMonitors or {}
View.combatResourceMonitors = View.combatResourceMonitors or {}
View.combatResourceChangedGroups = View.combatResourceChangedGroups or {}
View.unavailableMonitors = View.unavailableMonitors or {}
View.visibilityHandles = View.visibilityHandles or {}
View.free = View.free or {}
View.freeCount = View.freeCount or 0
View.freeFilteredAuraChainIcons = View.freeFilteredAuraChainIcons or {}
View.freeFilteredAuraChainIconCount =
    View.freeFilteredAuraChainIconCount or 0
View.freeBars = View.freeBars or {}
View.freeBarCount = View.freeBarCount or 0
View.freeRings = View.freeRings or {}
View.freeRingCount = View.freeRingCount or 0
View.freeResources = View.freeResources or {}
View.freeResourceCount = View.freeResourceCount or 0
View.active = View.active == true
View.preview = View.preview == true
View.layoutEditMode = View.layoutEditMode == true
View.profile = View.profile
View.designMode = View.designMode == true
View.designerSurfaceVisible = View.designerSurfaceVisible ~= false
View.designerSkyridingState = View.designerSkyridingState == true
View.designSelect = nil
View.designAdd = nil
View.designSelectMonitor = nil
View.designReorderMonitor = nil
View.selectedMonitorId = nil
View.resourcePreviewClassFile = nil
View.resourcePreviewSpecID = nil
View.resourcePreviewFormKey = nil
View.resourceStylePreviewResourceId = nil
View.inCombat = View.inCombat == true
View.iconShadowStates = View.iconShadowStates or setmetatable({}, { __mode = "k" })
View.designTooltipTimer = View.designTooltipTimer or nil
View.designTooltipPendingSlot = View.designTooltipPendingSlot or nil
View.designTooltipDeadline = tonumber(View.designTooltipDeadline) or nil
View.designTooltipGeneration =
    tonumber(View.designTooltipGeneration) or 0

local function IsInCombat()
    local combat = YUI.API and YUI.API.Combat
    return combat and combat.InCombatLockdown
        and combat.InCombatLockdown() == true
end

local function AddMonitorStat(field, amount)
    if YUI.Monitor and YUI.Monitor.AddDataStat then
        YUI.Monitor:AddDataStat(field, amount)
    end
end

local function AddViewWrite(layout)
    if YHUD.Stats then
        YHUD.Stats:Add(layout and "layoutWrites" or "viewWrites")
    end
    AddMonitorStat("uiWrites", 1)
end

local function ProfileNowMS()
    if YHUD.performanceDiagnosticsEnabled ~= true
        or type(debugprofilestop) ~= "function" then
        return nil
    end
    local ok, value = pcall(debugprofilestop)
    return ok and type(value) == "number" and value or nil
end

local function AddPerformanceStat(field, amount)
    if YHUD.Stats then YHUD.Stats:Add(field, amount) end
end

local function FinishPerformanceStat(field, startedAt)
    if not startedAt then return end
    local finishedAt = ProfileNowMS()
    if finishedAt then
        AddPerformanceStat(field, math.max(0, finishedAt - startedAt))
    end
end

local function SafeName(value)
    return tostring(value):gsub("[^%w_]", "_")
end

local function GroupName(group)
    if type(group) ~= "table" then return "-" end
    if group.nameKey then
        return YHUD:T(group.nameKey, group.name or group.id or "-")
    end
    return group.name or group.id or "-"
end

local function GetIconLayout(profile, groupId)
    local group = profile and profile.groups and profile.groups.items
        and profile.groups.items[groupId]
    local layout = YHUD.GetIconGroupLayout
        and YHUD:GetIconGroupLayout(profile, groupId) or {}
    local style = YHUD.GetIconGroupStyle
        and YHUD:GetIconGroupStyle(profile, groupId) or {}
    local iconSize = type(layout.iconSize) == "number"
        and layout.iconSize or DEFAULT_ICON_SIZE
    local columnSpacing = type(layout.columnSpacing) == "number"
        and layout.columnSpacing or DEFAULT_SPACING
    local rowSpacing = type(layout.rowSpacing) == "number"
        and layout.rowSpacing or DEFAULT_SPACING
    local maxPerLine = type(layout.maxPerLine) == "number"
        and layout.maxPerLine or DEFAULT_MAX_PER_LINE
    local wrapDirection = layout.wrapDirection
    if wrapDirection ~= "up" then
        wrapDirection = "down"
    end
    local alignment = layout.alignment
    if alignment ~= "start" and alignment ~= "end" then
        alignment = "center"
    end
    local rowDirection = layout.rowDirection == "left" and "left" or "right"
    local shape = style.iconShape or "roundedSquare"
    local iconWidth
    local iconHeight
    if GUI2.GetIconAppearanceSize then
        iconWidth, iconHeight =
            GUI2:GetIconAppearanceSize(iconSize, shape)
    else
        iconWidth = iconSize
        iconHeight = iconSize
    end
    local result = {
        smoothProgress = false,
        iconSize = iconSize,
        iconWidth = iconWidth,
        iconHeight = iconHeight,
        columnSpacing = columnSpacing,
        rowSpacing = rowSpacing,
        maxPerLine = maxPerLine,
        wrapDirection = wrapDirection,
        alignment = alignment,
        rowDirection = rowDirection,
        showTooltip = not group or group.showTooltip ~= false,
        shape = shape,
        border = style.iconBorder or "thin",
        iconZoom = style.iconZoom or 0.08,
        iconBorderColor = style.iconBorderColor,
        iconBackgroundColor = style.iconBackgroundColor,
        iconShadow = style.iconShadow ~= false,
        iconShadowColor = style.iconShadowColor,
        cooldownSwipeColor = style.cooldownSwipeColor,
        cooldownSwipe = style.cooldownSwipe ~= false,
        cooldownGCD = style.cooldownGCD ~= false,
        cooldownBling = style.cooldownBling == true,
        cooldownText = style.cooldownText ~= false,
        cooldownTextFont = style.cooldownTextFont or "default",
        cooldownTextSize = style.cooldownTextSize or 14,
        cooldownTextOutline = style.cooldownTextOutline or "outlineShadow",
        cooldownTextPosition = style.cooldownTextPosition or "center",
        cooldownTextOffsetX = style.cooldownTextOffsetX or 0,
        cooldownTextOffsetY = style.cooldownTextOffsetY or 0,
        cooldownTextColor = style.cooldownTextColor or {
            r = 1,
            g = 1,
            b = 1,
            a = 1,
        },
        keybindTextMode = style.keybindTextMode or "off",
        keybindTextFont = style.keybindTextFont or "default",
        keybindTextSize = style.keybindTextSize or 12,
        keybindTextOutline = style.keybindTextOutline or "outlineShadow",
        keybindTextPosition = style.keybindTextPosition or "top-right",
        keybindTextOffsetX = style.keybindTextOffsetX or 2,
        keybindTextOffsetY = style.keybindTextOffsetY or 1,
        keybindTextColor = style.keybindTextColor,
        keybindTextOverrides = style.keybindTextOverrides,
        countText = style.countText ~= false,
        countTextFont = style.countTextFont or "default",
        countTextSize = style.countTextSize or 12,
        countTextOutline = style.countTextOutline or "outlineShadow",
        countTextPosition = style.countTextPosition or "bottom",
        countTextOffsetX = style.countTextOffsetX or -2,
        countTextOffsetY = style.countTextOffsetY or 2,
        countTextColor = style.countTextColor,
    }
    if GUI2.CompileIconStyle then
        result.iconStyle = GUI2:CompileIconStyle(style)
    end
    return result
end

local function GetDurationLayout(profile, groupId, layoutType)
    local group = profile and profile.groups and profile.groups.items
        and profile.groups.items[groupId]
    local layout = YHUD.GetDurationGroupLayout
        and YHUD:GetDurationGroupLayout(profile, groupId, layoutType) or {}
    local style = YHUD.GetDurationGroupStyle
        and YHUD:GetDurationGroupStyle(profile, groupId) or {}
    local columnSpacing = type(layout.columnSpacing) == "number"
        and layout.columnSpacing or DEFAULT_SPACING
    local rowSpacing = type(layout.rowSpacing) == "number"
        and layout.rowSpacing or DEFAULT_SPACING
    local maxPerLine = type(layout.maxPerLine) == "number"
        and layout.maxPerLine or DEFAULT_MAX_PER_LINE
    local alignment = layout.alignment
    if alignment ~= "start" and alignment ~= "end" then
        alignment = "center"
    end
    local wrapDirection = layout.wrapDirection == "up" and "up" or "down"
    local orientation = layout.orientation == "vertical"
        and "vertical" or "horizontal"
    local useExplicitTextAnchors = layoutType == "bars"
    local result = {
        layoutType = layoutType,
        view = LAYOUT_VIEWS[layoutType],
        smoothProgress = layoutType == "bars"
            and style.smoothProgress == true,
        columnSpacing = columnSpacing,
        rowSpacing = rowSpacing,
        maxPerLine = maxPerLine,
        ringStep = layout.ringStep or 8,
        direction = layout.direction or "grid",
        alignment = alignment,
        wrapDirection = wrapDirection,
        showTooltip = not group or group.showTooltip ~= false,
        shape = style.iconShape or "square",
        border = style.iconBorder or "thin",
        iconZoom = style.iconZoom or 0.08,
        iconBorderColor = style.iconBorderColor,
        iconBackgroundColor = style.iconBackgroundColor,
        cooldownSwipeColor = style.cooldownSwipeColor,
        cooldownText = style.timeText ~= false,
        cooldownTextFont = style.timeTextFont or "default",
        cooldownTextSize = style.timeTextSize or 12,
        cooldownTextOutline = style.timeTextOutline or "outlineShadow",
        cooldownTextPosition = style.timeTextPosition or "right",
        cooldownTextAnchor = useExplicitTextAnchors
            and (style.timeTextAnchor or "bar-right") or nil,
        cooldownTextOffsetX = style.timeTextOffsetX or 0,
        cooldownTextOffsetY = style.timeTextOffsetY or 0,
        cooldownTextColor = style.timeTextColor or {
            r = 1,
            g = 1,
            b = 1,
            a = 1,
        },
        countText = style.countText ~= false,
        countTextFont = style.countTextFont or "default",
        countTextSize = style.countTextSize or 12,
        countTextOutline = style.countTextOutline or "outlineShadow",
        countTextPosition = style.countTextPosition or "bottom",
        countTextAnchor = useExplicitTextAnchors
            and (style.countTextAnchor or "icon-bottom-right") or nil,
        countTextOffsetX = style.countTextOffsetX or -2,
        countTextOffsetY = style.countTextOffsetY or 2,
        countTextColor = style.countTextColor,
        nameText = orientation ~= "vertical" and style.nameText ~= false,
        nameTextFormat = style.nameTextFormat or "%n",
        nameTextFont = style.nameTextFont or "default",
        nameTextSize = style.nameTextSize or 12,
        nameTextOutline = style.nameTextOutline or "outlineShadow",
        nameTextPosition = style.nameTextPosition or "center",
        nameTextAnchor = useExplicitTextAnchors
            and (style.nameTextAnchor or "bar-center") or nil,
        nameTextOffsetX = style.nameTextOffsetX or 0,
        nameTextOffsetY = style.nameTextOffsetY or 0,
        nameTextColor = style.nameTextColor or {
            r = 1,
            g = 1,
            b = 1,
            a = 1,
        },
        fillColor = style.fillColor or {
            r = 0.25,
            g = 0.55,
            b = 0.95,
            a = 1,
        },
        fillTexture = style.fillTexture or "yui-g1",
        trackColor = style.trackColor,
        borderColor = style.borderColor,
        showIcon = style.showIcon ~= false,
        timeText = style.timeText ~= false,
        timeTextFont = style.timeTextFont or "default",
        timeTextSize = style.timeTextSize or 12,
        timeTextOutline = style.timeTextOutline or "outlineShadow",
        timeTextPosition = style.timeTextPosition or "right",
        timeTextAnchor = useExplicitTextAnchors
            and (style.timeTextAnchor or "bar-right") or nil,
        timeTextOffsetX = style.timeTextOffsetX or 0,
        timeTextOffsetY = style.timeTextOffsetY or 0,
        timeTextColor = style.timeTextColor,
        ringThickness = style.ringThickness or 8,
        ringDirection = style.ringDirection or "clockwise",
        ringStart = style.ringStart or "top",
        ringTrackColor = style.ringTrackColor,
        ringBorderColor = style.ringBorderColor,
    }
    if GUI2.CompileIconStyle then
        result.iconStyle = GUI2:CompileIconStyle(style)
        result.iconStyle.drawBling = false
        if layoutType == "rings" then
            local preset = GUI2.GetIconAppearancePreset
                and GUI2:GetIconAppearancePreset("circle") or {}
            result.iconStyle.shape = "circle"
            result.iconStyle.zoom = 0
            result.iconStyle.aspect =
                tonumber(preset and preset.aspect) or 1
            result.iconStyle.mask = GUI2.GetIconAppearanceMask
                and GUI2:GetIconAppearanceMask(
                    "circle",
                    result.iconStyle.border
                )
                or (preset and preset.mask or nil)
            result.iconStyle.borderFamily =
                preset and preset.borderFamily or nil
            result.iconStyle.swipeTexture = result.iconStyle.mask
                or (preset and preset.swipe)
                or result.iconStyle.swipeTexture
            result.iconStyle.circular = true
        end
        if layoutType == "rings"
            and type(style.ringBorderColor) == "table"
            and type(result.iconStyle.borderColor) == "table" then
            local source = style.ringBorderColor
            local target = result.iconStyle.borderColor
            target[1] = source.r or source[1] or target[1]
            target[2] = source.g or source[2] or target[2]
            target[3] = source.b or source[3] or target[3]
            target[4] = source.a or source[4] or target[4]
        end
    end
    if GUI2.CompileStatusBarStyle then
        result.statusBarStyle = GUI2:CompileStatusBarStyle({
            fillTexture = result.fillTexture,
            fillColor = result.fillColor,
            trackColor = result.trackColor,
            border = result.border,
            borderColor = result.borderColor,
            showIcon = result.showIcon,
            nameText = {
                enabled = result.nameText,
                font = result.nameTextFont,
                size = result.nameTextSize,
                outline = result.nameTextOutline,
                position = result.nameTextPosition,
                anchor = result.nameTextAnchor,
                offsetX = result.nameTextOffsetX,
                offsetY = result.nameTextOffsetY,
                color = result.nameTextColor,
            },
            timeText = {
                enabled = result.timeText,
                font = result.timeTextFont,
                size = result.timeTextSize,
                outline = result.timeTextOutline,
                position = result.timeTextPosition,
                anchor = result.timeTextAnchor,
                offsetX = result.timeTextOffsetX,
                offsetY = result.timeTextOffsetY,
                color = result.timeTextColor,
            },
            countText = {
                enabled = result.countText,
                font = result.countTextFont,
                size = result.countTextSize,
                outline = result.countTextOutline,
                position = result.countTextPosition,
                anchor = result.countTextAnchor,
                offsetX = result.countTextOffsetX,
                offsetY = result.countTextOffsetY,
                color = result.countTextColor,
            },
        })
    end

    if layoutType == "rings" then
        result.diameter = type(layout.diameter) == "number"
            and layout.diameter or DEFAULT_RING_DIAMETER
        result.itemWidth = result.diameter
        result.itemHeight = result.diameter
        return result
    end

    result.orientation = orientation
    result.fillDirection = layout.fillDirection == "reverse"
        and "reverse" or "forward"
    local outerLength = type(layout.width) == "number"
        and layout.width or DEFAULT_BAR_WIDTH
    local outerThickness = type(layout.height) == "number"
        and layout.height or DEFAULT_BAR_HEIGHT
    result.itemWidth = result.orientation == "vertical"
        and outerThickness or outerLength
    result.itemHeight = result.orientation == "vertical"
        and outerLength or outerThickness
    local iconPosition = layout.iconPosition or "left"
    if result.orientation == "vertical" then
        if iconPosition == "left" then
            iconPosition = "bottom"
        elseif iconPosition == "right" then
            iconPosition = "top"
        end
    end
    result.iconPosition = iconPosition
    result.iconGap = type(layout.iconGap) == "number"
        and layout.iconGap or 0
    result.barWidth = result.itemWidth
    result.barHeight = result.itemHeight
    result.iconSize = result.orientation == "vertical"
        and result.itemWidth or result.itemHeight
    if result.iconPosition == "left"
        or result.iconPosition == "right" then
        if result.orientation == "vertical" then
            result.iconSize = math.max(
                1,
                (result.itemWidth - result.iconGap) / 2
            )
        end
        result.barWidth = math.max(
            1,
            result.itemWidth - result.iconSize - result.iconGap
        )
    elseif result.iconPosition == "top"
        or result.iconPosition == "bottom" then
        if result.orientation ~= "vertical" then
            result.iconSize = math.max(
                1,
                (result.itemHeight - result.iconGap) / 2
            )
        end
        result.barHeight = math.max(
            1,
            result.itemHeight - result.iconSize - result.iconGap
        )
    end
    return result
end

local function GetResourceLayout(profile, groupId)
    local layout = YHUD.GetResourceGroupLayout
        and YHUD:GetResourceGroupLayout(profile, groupId) or {}
    local style = YHUD.GetResourceGroupStyle
        and YHUD:GetResourceGroupStyle(profile, groupId) or {}
    local direction = layout.direction
    if direction ~= "left" and direction ~= "up" and direction ~= "down" then
        direction = "right"
    end
    local alignment = layout.alignment
    if alignment ~= "start" and alignment ~= "end" then
        alignment = "center"
    end
    local width = type(layout.width) == "number"
        and layout.width or DEFAULT_RESOURCE_WIDTH
    local minWidth = type(layout.minWidth) == "number"
        and layout.minWidth or 150
    local widthMode = layout.widthMode == "fixed" and "fixed" or "auto"
    local initialWidth = widthMode == "auto" and minWidth or width
    local height = type(layout.height) == "number"
        and layout.height or DEFAULT_RESOURCE_HEIGHT
    local result = {
        layoutType = "resource",
        view = "resource",
        smoothProgress = style.smoothProgress == true,
        resourceWidthMode = widthMode,
        resourceFixedWidth = width,
        resourceMinWidth = minWidth,
        resourceWidth = initialWidth,
        resourceHeight = height,
        handPairMode = layout.handPairMode,
        mainHandFillDirection = layout.mainHandFillDirection,
        offHandFillDirection = layout.offHandFillDirection,
        itemWidth = initialWidth,
        itemHeight = height,
        spacing = type(layout.spacing) == "number"
            and layout.spacing or DEFAULT_SPACING,
        maxPerLine = DEFAULT_MAX_PER_LINE,
        direction = direction,
        alignment = alignment,
        orientation = layout.orientation == "vertical"
            and "vertical" or "horizontal",
        fillDirection = layout.fillDirection == "reverse"
            and "reverse" or "forward",
        border = style.border or "thin",
        borderColor = style.borderColor,
        fillTexture = style.fillTexture or "yui-g1",
        fillColorMode = style.fillColorMode or "resource",
        fillColor = style.fillColor,
        textFont = style.textFont or "default",
        textSize = style.textSize or 12,
        textOutline = style.textOutline or "outlineShadow",
        textColor = style.textColor or {
            r = 1,
            g = 1,
            b = 1,
            a = 1,
        },
        backgroundColor = style.backgroundColor or {
            r = 0.04,
            g = 0.06,
            b = 0.08,
            a = 0.92,
        },
        resourceProfile = profile,
        resourceGroupId = groupId,
        resourceStyleToken = {},
    }
    if GUI2.CompileStatusBarStyle then
        result.statusBarStyle = GUI2:CompileStatusBarStyle({
            fillTexture = result.fillTexture,
            fillColorMode = result.fillColorMode,
            fillColor = result.fillColor,
            trackColor = result.backgroundColor,
            border = result.border,
            borderColor = result.borderColor,
            timeText = {
                enabled = true,
                font = result.textFont,
                size = result.textSize,
                outline = result.textOutline,
                position = "center",
                color = result.textColor,
            },
        })
    end
    return result
end

local function FormatMonitorName(formatText, name)
    formatText = type(formatText) == "string"
        and formatText ~= "" and formatText or "%n"
    name = type(name) == "string" and name or "-"
    return (formatText:gsub("%%n", name))
end

local function GetEntryName(entry)
    return YHUD:GetEntryDisplayName(entry, "-")
end

local function SameColor(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then
        return left == right
    end
    return (left.r or left[1]) == (right.r or right[1])
        and (left.g or left[2]) == (right.g or right[2])
        and (left.b or left[3]) == (right.b or right[3])
        and (left.a or left[4]) == (right.a or right[4])
end

local function CopyColor(source, target)
    if type(source) ~= "table" then return source end
    target = type(target) == "table" and target or {}
    target[1] = source.r or source[1]
    target[2] = source.g or source[2]
    target[3] = source.b or source[3]
    target[4] = source.a or source[4]
    target.r, target.g, target.b, target.a = nil, nil, nil, nil
    return target
end

local function SameTextStyle(left, right)
    if left == right then return true end
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    return left.enabled == right.enabled
        and left.font == right.font
        and left.size == right.size
        and left.outline == right.outline
        and left.position == right.position
        and left.offsetX == right.offsetX
        and left.offsetY == right.offsetY
        and SameColor(left.color, right.color)
end

local function SameIconStyle(left, right)
    if left == right then return true end
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    return left.shape == right.shape
        and left.border == right.border
        and left.borderThickness == right.borderThickness
        and left.zoom == right.zoom
        and left.aspect == right.aspect
        and left.mask == right.mask
        and left.borderFamily == right.borderFamily
        and left.swipeTexture == right.swipeTexture
        and left.circular == right.circular
        and SameColor(left.borderColor, right.borderColor)
        and SameColor(left.backgroundColor, right.backgroundColor)
        and SameColor(left.swipeColor, right.swipeColor)
        and left.drawSwipe == right.drawSwipe
        and left.drawBling == right.drawBling
        and SameTextStyle(left.cooldownText, right.cooldownText)
        and SameTextStyle(left.countText, right.countText)
end

local function SameStatusBarStyle(left, right)
    if left == right then return true end
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    return left.texture == right.texture
        and left.textureId == right.textureId
        and left.textureU0 == right.textureU0
        and left.textureU1 == right.textureU1
        and left.textureV0 == right.textureV0
        and left.textureV1 == right.textureV1
        and left.fillColorMode == right.fillColorMode
        and left.border == right.border
        and left.borderThickness == right.borderThickness
        and left.showIcon == right.showIcon
        and SameColor(left.fillColor, right.fillColor)
        and SameColor(left.trackColor, right.trackColor)
        and SameColor(left.borderColor, right.borderColor)
        and SameTextStyle(left.nameText, right.nameText)
        and SameTextStyle(left.timeText, right.timeText)
        and SameTextStyle(left.countText, right.countText)
end

local function SameGlowAppearance(slot, appearance)
    local color = appearance and appearance.color
    return appearance
        and slot._yhudGlowStyle == appearance.style
        and slot._yhudGlowSize == appearance.size
        and slot._yhudGlowLines == appearance.lines
        and slot._yhudGlowThickness == appearance.thickness
        and slot._yhudGlowSpeed == appearance.speed
        and slot._yhudGlowAlpha == appearance.alpha
        and slot._yhudGlowOffsetX == appearance.offsetX
        and slot._yhudGlowOffsetY == appearance.offsetY
        and type(color) == "table"
        and slot._yhudGlowColorR == color[1]
        and slot._yhudGlowColorG == color[2]
        and slot._yhudGlowColorB == color[3]
        and slot._yhudGlowColorA == color[4]
end

local function CacheGlowAppearance(slot, appearance)
    local color = appearance.color
    slot._yhudGlowStyle = appearance.style
    slot._yhudGlowSize = appearance.size
    slot._yhudGlowLines = appearance.lines
    slot._yhudGlowThickness = appearance.thickness
    slot._yhudGlowSpeed = appearance.speed
    slot._yhudGlowAlpha = appearance.alpha
    slot._yhudGlowOffsetX = appearance.offsetX
    slot._yhudGlowOffsetY = appearance.offsetY
    slot._yhudGlowColorR = color[1]
    slot._yhudGlowColorG = color[2]
    slot._yhudGlowColorB = color[3]
    slot._yhudGlowColorA = color[4]
end

local RUNTIME_LAYOUT_FIELDS = {
    "layoutType",
    "view",
    "iconSize",
    "iconWidth",
    "iconHeight",
    "itemWidth",
    "itemHeight",
    "barWidth",
    "barHeight",
    "orientation",
    "iconPosition",
    "iconGap",
    "diameter",
    "resourceWidth",
    "resourceWidthMode",
    "resourceFixedWidth",
    "resourceMinWidth",
    "resourceHeight",
    "spacing",
    "columnSpacing",
    "rowSpacing",
    "maxPerLine",
    "ringStep",
    "direction",
    "wrapDirection",
    "alignment",
    "rowDirection",
    "showTooltip",
    "fillDirection",
    "shape",
    "border",
    "iconZoom",
    "iconShadow",
    "fillTexture",
    "fillColorMode",
    "showIcon",
    "smoothProgress",
    "timeText",
    "timeTextFont",
    "timeTextSize",
    "timeTextOutline",
    "timeTextPosition",
    "timeTextAnchor",
    "timeTextOffsetX",
    "timeTextOffsetY",
    "ringThickness",
    "ringDirection",
    "ringStart",
    "cooldownText",
    "cooldownSwipe",
    "cooldownGCD",
    "cooldownTextFont",
    "cooldownTextSize",
    "cooldownTextOutline",
    "cooldownTextPosition",
    "cooldownTextAnchor",
    "cooldownTextOffsetX",
    "cooldownTextOffsetY",
    "keybindTextMode",
    "keybindTextFont",
    "keybindTextSize",
    "keybindTextOutline",
    "keybindTextPosition",
    "keybindTextOffsetX",
    "keybindTextOffsetY",
    "countText",
    "countTextFont",
    "countTextSize",
    "countTextOutline",
    "countTextPosition",
    "countTextAnchor",
    "countTextOffsetX",
    "countTextOffsetY",
    "nameText",
    "nameTextFormat",
    "nameTextFont",
    "nameTextSize",
    "nameTextOutline",
    "nameTextPosition",
    "nameTextAnchor",
    "nameTextOffsetX",
    "nameTextOffsetY",
    "valueText",
    "textFont",
    "textSize",
    "textOutline",
    "resourceProfile",
    "handPairMode",
    "mainHandFillDirection",
    "offHandFillDirection",
    "resourceGroupId",
    "resourceStyleToken",
}

local RUNTIME_COLOR_FIELDS = {
    "cooldownTextColor",
    "keybindTextColor",
    "countTextColor",
    "iconBorderColor",
    "iconBackgroundColor",
    "iconShadowColor",
    "cooldownSwipeColor",
    "nameTextColor",
    "fillColor",
    "trackColor",
    "borderColor",
    "timeTextColor",
    "ringTrackColor",
    "ringBorderColor",
    "textColor",
    "backgroundColor",
}

local function ApplyRuntimeLayout(runtime, layout, replace)
    replace = replace == true
    local changed = false
    for index = 1, #RUNTIME_LAYOUT_FIELDS do
        local field = RUNTIME_LAYOUT_FIELDS[index]
        local value = layout[field]
        if replace or value ~= nil then
            if runtime[field] ~= value then changed = true end
            runtime[field] = value
        end
    end
    for index = 1, #RUNTIME_COLOR_FIELDS do
        local field = RUNTIME_COLOR_FIELDS[index]
        local value = layout[field]
        if value ~= nil then
            if not SameColor(runtime[field], value) then changed = true end
            runtime[field] = CopyColor(value, runtime[field])
        elseif replace and runtime[field] ~= nil then
            changed = true
            runtime[field] = nil
        end
    end
    if layout.iconStyle then
        if not SameIconStyle(runtime.iconStyle, layout.iconStyle) then
            changed = true
        end
        runtime.iconStyle = layout.iconStyle
    elseif replace and runtime.iconStyle ~= nil then
        changed = true
        runtime.iconStyle = nil
    end
    if layout.statusBarStyle then
        if not SameStatusBarStyle(
            runtime.statusBarStyle,
            layout.statusBarStyle
        ) then
            changed = true
        end
        runtime.statusBarStyle = layout.statusBarStyle
    elseif replace and runtime.statusBarStyle ~= nil then
        changed = true
        runtime.statusBarStyle = nil
    end
    if layout.keybindTextOverrides ~= nil then
        local current = runtime.keybindTextOverrides
        local incoming = layout.keybindTextOverrides
        local same = type(current) == "table" and type(incoming) == "table"
        if same then
            for spellID, text in pairs(current) do
                if incoming[spellID] ~= text then same = false break end
            end
            if same then
                for spellID in pairs(incoming) do
                    if current[spellID] == nil then same = false break end
                end
            end
        end
        if not same then
            changed = true
            current = {}
            for spellID, text in pairs(incoming) do current[spellID] = text end
            runtime.keybindTextOverrides = current
        end
    elseif replace and runtime.keybindTextOverrides ~= nil then
        changed = true
        runtime.keybindTextOverrides = nil
    end
    return changed
end


View._internal = {
    GUI2 = GUI2,
    App = App,
    ResourceCatalog = ResourceCatalog,
    Glow = Glow,
    Sound = RuntimeSound,
    IsInCombat = IsInCombat,
    QUESTION_ICON = QUESTION_ICON,
    DEFAULT_ICON_SIZE = DEFAULT_ICON_SIZE,
    DEFAULT_SPACING = DEFAULT_SPACING,
    DEFAULT_MAX_PER_LINE = DEFAULT_MAX_PER_LINE,
    EMPTY_DESIGN_GROUP_WIDTH = EMPTY_DESIGN_GROUP_WIDTH,
    LAYOUT_VIEWS = LAYOUT_VIEWS,
    AddMonitorStat = AddMonitorStat,
    AddViewWrite = AddViewWrite,
    ProfileNowMS = ProfileNowMS,
    AddPerformanceStat = AddPerformanceStat,
    FinishPerformanceStat = FinishPerformanceStat,
    SafeName = SafeName,
    GroupName = GroupName,
    GetIconLayout = GetIconLayout,
    GetDurationLayout = GetDurationLayout,
    GetResourceLayout = GetResourceLayout,
    FormatMonitorName = FormatMonitorName,
    GetEntryName = GetEntryName,
    SameColor = SameColor,
    SameGlowAppearance = SameGlowAppearance,
    CacheGlowAppearance = CacheGlowAppearance,
    ApplyRuntimeLayout = ApplyRuntimeLayout,
}

function View:HideIconShadow(frame)
    local state = self.iconShadowStates and self.iconShadowStates[frame]
    if not state then return 0 end
    state.runtime, state.pending = nil, nil
    return GUI2:HideShapeShadow(state.handle)
end

-- Own and native icons share one retained handle per physical frame.
-- Geometry follows the same physical frame as the icon border.
function View:ApplyIconShadow(frame, runtime, allowLayout)
    if not (frame and GUI2.BindShapeShadow) then return 0 end
    if not runtime or runtime.view ~= "icon" then
        return self:HideIconShadow(frame)
    end
    local state = self.iconShadowStates[frame]
    local enabled = runtime.iconShadow ~= false
    local color = runtime.iconShadowColor
    if not state then
        if not enabled then return 0 end
        state = { style = { color = {} } }
        self.iconShadowStates[frame] = state
    end
    state.runtime = runtime
    if allowLayout ~= nil then state.deferInCombat = true end
    local style = state.style
    style.enabled, style.shape = enabled, runtime.shape
    local rgba = style.color
    rgba[1], rgba[2], rgba[3], rgba[4] = color and (color.r or color[1]) or 0,
        color and (color.g or color[2]) or 0, color and (color.b or color[3]) or 0,
        color and (color.a or color[4]) or 0.5
    if not enabled or rgba[4] == 0 then
        state.pending = nil
        return GUI2:HideShapeShadow(state.handle)
    end
    if allowLayout == false then
        state.pending = true
        local bridge = YHUD.NativeBridge
        if bridge and bridge.ScheduleDeferred then bridge:ScheduleDeferred("categories") end
        return 0
    end
    if not state.handle then state.handle = GUI2:CreateShapeShadow(frame) end
    state.pending = nil
    return GUI2:BindShapeShadow(state.handle, style, frame, state.deferInCombat)
end

function View:PreviewIconShadowColor(frame, color)
    local state = self.iconShadowStates and self.iconShadowStates[frame]
    if not (state and state.runtime) then return false end
    state.previewStyle = state.previewStyle or { color = {} }
    local preview = state.previewStyle
    preview.enabled, preview.shape = state.style.enabled, state.style.shape
    local rgba = preview.color
    rgba[1], rgba[2], rgba[3], rgba[4] = color.r or color[1] or 0,
        color.g or color[2] or 0, color.b or color[3] or 0,
        color.a or color[4] or 0.5
    if not state.handle then
        if not preview.enabled or rgba[4] == 0 or state.pending
            or (state.deferInCombat and IsInCombat()) then
            return false
        end
        state.handle = GUI2:CreateShapeShadow(frame)
    end
    GUI2:BindShapeShadow(state.handle, preview, frame, state.deferInCombat)
    return true
end

function View:FlushPendingIconShadows()
    local writes = 0
    for frame, state in pairs(self.iconShadowStates) do
        if state.pending and state.runtime then
            writes = writes + self:ApplyIconShadow(frame, state.runtime, true)
        end
    end
    return writes + GUI2:FlushShapeShadowBindings()
end

function View:Enable(profile)
    self.active = true
    self.inCombat = IsInCombat()
    self:ApplyConfig(profile)
    return true
end

function View:IsGroupLevelDisplayAllowed(runtime)
    return self.preview == true or self.designMode == true
        or self.layoutEditMode == true
        or not (YHUD.IsGroupLevelRestricted
            and YHUD:IsGroupLevelRestricted(runtime.group))
end

function View:OnGroupVisibilityChanged(visible, reason, groupId)
    local runtime = groupId and self.groups[groupId]
    if not runtime then return false end
    visible = visible ~= false
    if runtime.visibilityAllowed == visible
        and runtime.visibilityReason == reason then
        return false
    end
    local visibilityChanged = runtime.visibilityAllowed ~= visible
    runtime.visibilityAllowed = visible
    runtime.visibilityReason = reason
    if visibilityChanged and self.active and not self.syncingVisibility then
        self:ProjectGroupVisibility(groupId)
    end
    return visibilityChanged
end

function View:SyncGroupVisibility(profile)
    local service = YUI.Visibility
    local handles = self.visibilityHandles or {}
    self.visibilityHandles = handles
    local groups = profile and profile.groups and profile.groups.items or {}
    local seen = {}
    self.syncingVisibility = true

    for groupId, group in pairs(groups) do
        local runtime = self.groups[groupId]
        if runtime and runtime.enabled and service and service.Register then
            seen[groupId] = true
            local handle = handles[groupId]
            if handle then
                service:Update(handle, group.visibility)
                service:SetBypass(handle, self.designMode)
            else
                handle = service:Register({
                    backend = "event", owner = self,
                    rule = group.visibility,
                    callback = "OnGroupVisibilityChanged",
                    capabilities = { hover = false },
                    moduleId = YHUD.PRODUCT_ID,
                    context = groupId,
                    bypass = self.designMode,
                })
                handles[groupId] = handle
                if not handle then
                    runtime.visibilityAllowed = true
                    runtime.visibilityReason = "unavailable"
                end
            end
        elseif runtime then
            runtime.visibilityAllowed = true
            runtime.visibilityReason = "inactive"
        end
    end

    for groupId, handle in pairs(handles) do
        if not seen[groupId] then
            if service and service.Release then service:Release(handle) end
            handles[groupId] = nil
        end
    end
    self.syncingVisibility = nil
    return true
end

function View:SetVisibilityBypass(enabled)
    local service = YUI.Visibility
    if not (service and service.SetBypass) then return 0 end
    enabled = enabled == true
    local changed = 0
    self.syncingVisibility = true
    for _, handle in pairs(self.visibilityHandles or {}) do
        if service:SetBypass(handle, enabled) then changed = changed + 1 end
    end
    if not enabled and service.Refresh then service:Refresh() end
    self.syncingVisibility = nil
    if self.active and self.ProjectAllGroupVisibility then
        self:ProjectAllGroupVisibility()
    end
    return changed
end

function View:Disable()
    self.active = false
    self.layoutNativeSnapshot = nil
    self.preview = false
    self.layoutEditMode = false
    self.designerSurfaceVisible = true
    if self.ClearDesignResourceValuePreview then
        self:ClearDesignResourceValuePreview()
    end
    self:SetDesignMode(false)
    if YHUD.Sound and YHUD.Sound.Reset then YHUD.Sound:Reset() end
    if self.ReleaseFilteredAuraDisplays then
        self:ReleaseFilteredAuraDisplays()
    end
    if YUI.Visibility and YUI.Visibility.ReleaseOwner then
        YUI.Visibility:ReleaseOwner(self)
    end
    for groupId in pairs(self.visibilityHandles or {}) do
        self.visibilityHandles[groupId] = nil
    end
    for monitorId in pairs(self.byMonitor) do
        self:ReleaseSlot(monitorId)
    end
    if self.ReleasePooledResourceAuraDisplays then
        self:ReleasePooledResourceAuraDisplays()
    end
    for groupId, runtime in pairs(self.groups) do
        if self.InvalidateResourcePrefixLayout then
            self:InvalidateResourcePrefixLayout(groupId, true)
        end
        runtime.visibilityAllowed = true
        runtime.visibilityReason = "disabled"
        runtime.presentationGroupPlan = nil
        runtime.presentationGeometry = nil
        runtime.frame:Hide()
    end
    self.presentationPlan = nil
    self.layoutProjectionContext = nil
end

function View:GetFrame()
    local profile = self.profile or (YHUD.GetConfigProfile and YHUD:GetConfigProfile())
    local groups = profile and profile.groups and profile.groups.items
    if type(groups) == "table" and groups[YHUD.GROUP_IDS.TRINKETS] then
        return self:GetGroupFrame(YHUD.GROUP_IDS.TRINKETS)
    end
    local monitors = profile and profile.monitors
    local slotMonitor = type(monitors) == "table"
        and monitors["monitor:slot:13"]
    if slotMonitor and groups and groups[slotMonitor.groupId] then
        return self:GetGroupFrame(slotMonitor.groupId)
    end
    local order = profile and profile.groups and profile.groups.order
    local groupId = type(order) == "table" and order[1]
        or YHUD.GROUP_IDS.IMPORTANT
    return self:GetGroupFrame(groupId)
end

function View:GetGroupFrame(groupId)
    local runtime = self.groups[groupId]
    if runtime then return runtime.frame end
    local profile = self.profile or (YHUD.GetConfigProfile and YHUD:GetConfigProfile())
    local group = profile and profile.groups and profile.groups.items
        and profile.groups.items[groupId]
    if not group then return nil end
    return self:CreateGroupHolder(groupId, group).frame
end

function View:GetGroupContentCount(groupId)
    local runtime = self.groups[groupId]
    return runtime and runtime.monitorCount or 0
end

local function GetNativeStableSize(runtime)
    return runtime.itemWidth or runtime.iconWidth or 42,
        runtime.itemHeight or runtime.iconHeight or 42
end

local function EnsureNativeStableSlot(runtime, monitorId)
    runtime.nativeStableSlots = runtime.nativeStableSlots or {}
    local slot = runtime.nativeStableSlots[monitorId]
    local width, height = GetNativeStableSize(runtime)
    if not slot then
        slot = GUI2:CreateFrame(runtime.frame, {
            width = width,
            height = height,
            mouse = false,
            hidden = true,
        })
        slot._yhudNativeStableSlot = true
        runtime.nativeStableSlots[monitorId] = slot
    end
    if not (GUI2.SetPixelSnappedSize and GUI2:SetPixelSnappedSize(
        slot,
        width,
        height,
        1,
        1
    )) then
        slot:SetSize(width, height)
    end
    local view = YHUD.View
    if view and view.GetMonitorDisplayLayer then
        local level, strata = view:GetMonitorDisplayLayer(runtime, monitorId)
        if strata and slot.SetFrameStrata then slot:SetFrameStrata(strata) end
        if level and slot.SetFrameLevel then slot:SetFrameLevel(level) end
    end
    return slot
end

local function AttachNativeFrameToStableSlot(slot, frame)
    slot._yhudNativeFrame = frame
    if not frame then
        slot:Hide()
        return
    end
    frame:ClearAllPoints()
    if type(frame.SetAllPoints) == "function" then
        frame:SetAllPoints(slot)
    else
        frame:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
        frame:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0, 0)
    end
    frame._yhudPlaced = true
end

function View:ReattachNativeStableFrame(groupId, monitorId, frame, category)
    local runtime = self.groups[groupId]
    local slots = runtime and runtime.nativeStableSlots
    local slot = slots and slots[monitorId]
    if not (slot and frame) then return false end
    local content = category and runtime.nativeCategories
        and runtime.nativeCategories[category]
    if content and content.byMonitor then
        content.byMonitor[monitorId] = frame
    end
    AttachNativeFrameToStableSlot(slot, frame)
    return true
end

function View:DetachNativeStableFrame(groupId, monitorId, frame, category)
    local runtime = self.groups[groupId]
    local slots = runtime and runtime.nativeStableSlots
    local slot = slots and slots[monitorId]
    if not (runtime and slot and frame) then return false end
    local detached = false
    local content = category and runtime.nativeCategories
        and runtime.nativeCategories[category]
    if content and content.byMonitor
        and content.byMonitor[monitorId] == frame then
        content.byMonitor[monitorId] = nil
        detached = true
    end
    if slot._yhudNativeFrame == frame then
        slot._yhudNativeFrame = nil
        detached = true
    end
    return detached
end

local function RebuildNativeGroupFrames(runtime)
    local byMonitor = {}
    local frames = {}
    local usedStableSlots = {}
    local categories = {}
    for category in pairs(runtime.nativeCategories or {}) do
        categories[#categories + 1] = category
    end
    table.sort(categories)
    for index = 1, #categories do
        local content = runtime.nativeCategories[categories[index]]
        if content.stableMembers then
            for monitorId in pairs(content.stableMembers) do
                local slot = EnsureNativeStableSlot(runtime, monitorId)
                local frame = content.byMonitor
                    and content.byMonitor[monitorId]
                AttachNativeFrameToStableSlot(slot, frame)
                if frame then
                    slot:Show()
                    byMonitor[monitorId] = slot
                    usedStableSlots[slot] = true
                end
            end
        else
            for monitorId, frame in pairs(content.byMonitor or {}) do
                byMonitor[monitorId] = frame
            end
        end
        for frameIndex = 1, #(content.frames or {}) do
            frames[#frames + 1] = content.frames[frameIndex]
        end
    end
    for _, slot in pairs(runtime.nativeStableSlots or {}) do
        if not usedStableSlots[slot] then
            slot._yhudNativeFrame = nil
            slot:Hide()
        end
    end
    runtime.nativeByMonitor = byMonitor
    runtime.nativeFrames = frames
end

function View:RefreshNativeGroupFrames(groupId)
    local runtime = self.groups[groupId]
    if not runtime then return false end
    RebuildNativeGroupFrames(runtime)
    runtime.nativeWidth = nil
    runtime.nativeHeight = nil
    runtime.nativeOffsetX = nil
    runtime.nativeOffsetY = nil
    local changed = self:RelayoutGroup(groupId)
    if self.designMode and self.RefreshDesignChromeGeometry then
        self:RefreshDesignChromeGeometry(runtime)
    end
    return changed
end

local function NativeFrameMapEquals(left, right)
    left = type(left) == "table" and left or {}
    right = type(right) == "table" and right or {}
    for key, value in pairs(left) do
        if right[key] ~= value then return false end
    end
    for key, value in pairs(right) do
        if left[key] ~= value then return false end
    end
    return true
end

local function NativeFrameArrayEquals(left, right)
    left = type(left) == "table" and left or {}
    right = type(right) == "table" and right or {}
    if #left ~= #right then return false end
    for index = 1, #left do
        if left[index] ~= right[index] then return false end
    end
    return true
end

function View:SuspendNativePresentation()
    if self.layoutNativeSnapshot then return false end
    local snapshot = {}
    local suspended = false
    for groupId, runtime in pairs(self.groups) do
        local categories = runtime.nativeCategories
        if type(categories) == "table" and next(categories) ~= nil then
            local suspendedCategories = {}
            local slots = {}
            for monitorId, slot in pairs(runtime.nativeStableSlots or {}) do
                slots[monitorId] = {
                    slot = slot,
                    frame = slot._yhudNativeFrame,
                    shown = slot:IsShown(),
                }
                slot._yhudNativeFrame = nil
                slot:Hide()
            end
            snapshot[groupId] = {
                runtime = runtime,
                categories = categories,
                byMonitor = runtime.nativeByMonitor,
                frames = runtime.nativeFrames,
                suspendedCategories = suspendedCategories,
                slots = slots,
            }
            runtime.nativeCategories = suspendedCategories
            runtime.nativeByMonitor = {}
            runtime.nativeFrames = {}
            suspended = true
        end
    end
    self.layoutNativeSnapshot = snapshot
    return suspended
end

function View:ResumeNativePresentation()
    local snapshot = self.layoutNativeSnapshot
    if not snapshot then return false end
    self.layoutNativeSnapshot = nil
    local restored = false
    for groupId, saved in pairs(snapshot) do
        local runtime = self.groups[groupId]
        if runtime == saved.runtime
            and runtime.nativeCategories == saved.suspendedCategories
            and next(runtime.nativeCategories) == nil then
            runtime.nativeCategories = saved.categories
            runtime.nativeByMonitor = saved.byMonitor
            runtime.nativeFrames = saved.frames
            -- Restore existing slots only; combat exit must not rebuild anchors.
            for monitorId, binding in pairs(saved.slots) do
                local slot = runtime.nativeStableSlots
                    and runtime.nativeStableSlots[monitorId]
                if slot == binding.slot then
                    slot._yhudNativeFrame = binding.frame
                    if binding.shown then slot:Show() else slot:Hide() end
                end
            end
            restored = true
        end
    end
    return restored
end

function View:SetNativeGroupFrames(
    groupId,
    byMonitor,
    frames,
    category,
    forceLayout,
    stableMembers
)
    local runtime = self.groups[groupId]
    if not runtime then return false end

    category = type(category) == "string" and category or "__legacy"
    byMonitor = type(byMonitor) == "table" and byMonitor or {}
    frames = type(frames) == "table" and frames or {}
    runtime.nativeCategories = runtime.nativeCategories or {}
    local previous = runtime.nativeCategories[category]
    local stableWidth, stableHeight = GetNativeStableSize(runtime)
    if forceLayout ~= true
        and previous
        and NativeFrameMapEquals(previous.byMonitor, byMonitor)
        and NativeFrameArrayEquals(previous.frames, frames)
        and NativeFrameMapEquals(previous.stableMembers, stableMembers)
        and previous.stableWidth == stableWidth
        and previous.stableHeight == stableHeight then
        return false
    end
    runtime.nativeCategories[category] = {
        byMonitor = byMonitor,
        frames = frames,
        stableMembers = type(stableMembers) == "table"
            and stableMembers or nil,
        stableWidth = stableWidth,
        stableHeight = stableHeight,
    }
    return self:RefreshNativeGroupFrames(groupId)
end

function View:ClearNativeGroupFrames(groupId, category)
    local runtime = self.groups[groupId]
    if not runtime then return false end

    runtime.nativeCategories = runtime.nativeCategories or {}
    if type(category) == "string" then
        if runtime.nativeCategories[category] == nil then return false end
        runtime.nativeCategories[category] = nil
    else
        if next(runtime.nativeCategories) == nil then return false end
        runtime.nativeCategories = {}
    end
    return self:RefreshNativeGroupFrames(groupId)
end

function View:SetNativeGroupSize(
    groupId,
    width,
    height,
    offsetX,
    offsetY
)
    local runtime = self.groups[groupId]
    if not runtime
        or type(width) ~= "number"
        or type(height) ~= "number"
        or width <= 0
        or height <= 0 then
        return false
    end

    runtime.nativeWidth = width
    runtime.nativeHeight = height
    runtime.nativeOffsetX = tonumber(offsetX) or 0
    runtime.nativeOffsetY = tonumber(offsetY) or 0
    local changed = self:RelayoutGroup(groupId)
    if self.designMode and self.RefreshDesignChromeGeometry then
        self:RefreshDesignChromeGeometry(runtime)
    end
    return changed
end

function View:ClearNativeGroupSize(groupId)
    local runtime = self.groups[groupId]
    if not runtime then return false end

    runtime.nativeWidth = nil
    runtime.nativeHeight = nil
    runtime.nativeOffsetX = nil
    runtime.nativeOffsetY = nil
    local changed = self:RelayoutGroup(groupId)
    if self.designMode and self.RefreshDesignChromeGeometry then
        self:RefreshDesignChromeGeometry(runtime)
    end
    return changed
end

function View:GetGroupMoverBounds(groupId)
    local runtime = self.groups[groupId]
    if not runtime then return nil end
    local frame = runtime.frame
    if self._internal.GetAutoIconRowWidth
        and self._internal.GetAutoIconRowWidth(runtime) then
        return frame and frame.GetWidth and frame:GetWidth(),
            frame and frame.GetHeight and frame:GetHeight() or runtime.nativeHeight,
            0, 0
    end
    local width = runtime.nativeWidth
        or (frame and frame.GetWidth and frame:GetWidth())
    local height = runtime.nativeHeight
        or (frame and frame.GetHeight and frame:GetHeight())
    return width,
        height,
        runtime.nativeOffsetX or 0,
        runtime.nativeOffsetY or 0
end

function View:GetGroupFrames(target, includeDisabled)
    target = type(target) == "table" and target or {}
    for groupId, runtime in pairs(self.groups) do
        if includeDisabled == true or runtime.enabled then
            target[groupId] = runtime.frame
        end
    end
    return target
end

function View:GetIconGroupFrames(target)
    target = type(target) == "table" and target or {}
    for groupId, runtime in pairs(self.groups) do
        if runtime.enabled and runtime.view == "icon" then
            target[groupId] = runtime.frame
        end
    end
    return target
end

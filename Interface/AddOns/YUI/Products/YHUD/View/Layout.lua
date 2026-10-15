local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local View = YHUD and YHUD.View
local I = View and View._internal
if not I then return end

local GUI2 = I.GUI2
local App = I.App
local ResourceCatalog = I.ResourceCatalog
local Glow = I.Glow
local RuntimeSound = I.Sound
local IsInCombat = I.IsInCombat
local QUESTION_ICON = I.QUESTION_ICON
local DEFAULT_ICON_SIZE = I.DEFAULT_ICON_SIZE
local DEFAULT_SPACING = I.DEFAULT_SPACING
local DEFAULT_MAX_PER_LINE = I.DEFAULT_MAX_PER_LINE
local EMPTY_DESIGN_GROUP_WIDTH = I.EMPTY_DESIGN_GROUP_WIDTH
local LAYOUT_VIEWS = I.LAYOUT_VIEWS
local AddViewWrite = I.AddViewWrite
local ProfileNowMS = I.ProfileNowMS
local AddPerformanceStat = I.AddPerformanceStat
local FinishPerformanceStat = I.FinishPerformanceStat
local SafeName = I.SafeName
local GroupName = I.GroupName
local GetIconLayout = I.GetIconLayout
local GetDurationLayout = I.GetDurationLayout
local GetResourceLayout = I.GetResourceLayout
local FormatMonitorName = I.FormatMonitorName
local GetEntryName = I.GetEntryName
local SameGlowAppearance = I.SameGlowAppearance
local CacheGlowAppearance = I.CacheGlowAppearance
local ApplyRuntimeLayout = I.ApplyRuntimeLayout
local BuildGroupGeometry = I.BuildGroupGeometry
local ApplyGroupGeometry = I.ApplyGroupGeometry
local CreateFrame = _G.CreateFrame
local Security = YUI.API and YUI.API.Security

local layoutGeometryByFrame = setmetatable({}, { __mode = "k" })

local GROUP_DISPLAY_LAYER_HEADROOM = 32
local GROUP_TEXT_LAYER_OFFSET = 16
local RUNTIME_DISPLAY_LAYER_BASE = 1
local FILTERED_AURA_ANCHOR_SINGLE_ORIGIN = 1
local FILTERED_AURA_ANCHOR_SINGLE_FIXED_HALF = 2
local FILTERED_AURA_ANCHOR_SPECIAL_ROW_BASE = 100
local FILTERED_AURA_ANCHOR_SPECIAL_ORIGIN_BASE = 200
local FILTERED_AURA_ANCHOR_SPECIAL_FIXED_HALF_BASE = 300
local DESIGN_DISPLAY_LAYER_BASE = 180
local DESIGN_DISPLAY_STRATA = "FULLSCREEN"

function View:CreateGroupHolder(groupId, group)
    local runtime = self.groups[groupId]
    if runtime then return runtime end

    local name = groupId == YHUD.GROUP_IDS.TRINKETS
        and "YUI_YHUD_TrinketGroup"
        or ("YUI_YHUD_Group_" .. SafeName(groupId))
    local holder = GUI2:CreateFrame(UIParent, {
        name = name,
        width = DEFAULT_ICON_SIZE,
        height = DEFAULT_ICON_SIZE,
        mouse = false,
        hidden = true,
    })
    local order = type(group) == "table" and tonumber(group.order) or 6
    if type(group) == "table" and group.kind == "user" then
        holder:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    else
        holder:SetPoint(
            "BOTTOM",
            UIParent,
            "BOTTOM",
            0,
            220 + (6 - (order or 6)) * 54
        )
    end

    runtime = {
        id = groupId,
        frame = holder,
        baseFrameStrata = holder.GetFrameStrata
            and holder:GetFrameStrata() or "MEDIUM",
        baseFrameLevel = holder.GetFrameLevel
            and holder:GetFrameLevel() or RUNTIME_DISPLAY_LAYER_BASE,
        group = group,
        enabled = false,
        layoutMode = "auto",
        layoutType = "icons",
        view = "icon",
        monitorIds = {},
        monitorLanes = {},
        monitorCount = 0,
        nativeByMonitor = {},
        nativeFrames = {},
        nativeCategories = {},
        iconSize = DEFAULT_ICON_SIZE,
        iconWidth = DEFAULT_ICON_SIZE,
        iconHeight = DEFAULT_ICON_SIZE,
        itemWidth = DEFAULT_ICON_SIZE,
        itemHeight = DEFAULT_ICON_SIZE,
        barWidth = DEFAULT_BAR_WIDTH,
        barHeight = DEFAULT_BAR_HEIGHT,
        orientation = "horizontal",
        iconPosition = "left",
        iconGap = 0,
        diameter = DEFAULT_RING_DIAMETER,
        resourceWidth = DEFAULT_RESOURCE_WIDTH,
        resourceHeight = DEFAULT_RESOURCE_HEIGHT,
        spacing = DEFAULT_SPACING,
        columnSpacing = DEFAULT_SPACING,
        rowSpacing = DEFAULT_SPACING,
        maxPerLine = DEFAULT_MAX_PER_LINE,
        direction = "right",
        wrapDirection = "down",
        alignment = "center",
        rowDirection = "right",
        fillDirection = "forward",
        shape = "roundedSquare",
        border = "thin",
        cooldownText = true,
        cooldownTextFont = "default",
        cooldownTextSize = 14,
        cooldownTextOutline = "outlineShadow",
        cooldownTextPosition = "center",
        cooldownTextColor = {
            r = 1,
            g = 1,
            b = 1,
            a = 1,
        },
        keybindTextMode = "off",
        keybindTextFont = "default",
        keybindTextSize = 12,
        keybindTextOutline = "outlineShadow",
        keybindTextPosition = "top-right",
        keybindTextOffsetX = 2,
        keybindTextOffsetY = 1,
        keybindTextColor = { r = 1, g = 1, b = 1, a = 1 },
        keybindTextOverrides = {},
        nameText = true,
        nameTextFormat = "%n",
        nameTextFont = "default",
        nameTextSize = 12,
        nameTextOutline = "outlineShadow",
        nameTextPosition = "center",
        nameTextColor = {
            r = 1,
            g = 1,
            b = 1,
            a = 1,
        },
        fillColor = {
            r = 0.25,
            g = 0.55,
            b = 0.95,
            a = 1,
        },
        textFont = "default",
        textSize = 12,
        textOutline = "outlineShadow",
        textColor = {
            r = 1,
            g = 1,
            b = 1,
            a = 1,
        },
        backgroundColor = {
            r = 0.04,
            g = 0.06,
            b = 0.08,
            a = 0.92,
        },
        layoutEligible = false,
        fixedResourceGeometryReady = false,
        visibilityAllowed = true,
        visibilityReason = "initial",
    }
    self.groups[groupId] = runtime
    if groupId == YHUD.GROUP_IDS.TRINKETS then
        self.holder = holder
    end
    return runtime
end

local function SameLayoutNumber(left, right)
    return type(left) == "number"
        and type(right) == "number"
        and math.abs(left - right) < 0.001
end

local function IsSecretLayoutValue(value)
    return Security
        and Security.IsSecretValue
        and Security.IsSecretValue(value) == true
end

local function SafeLayoutNumber(value)
    if value == nil or IsSecretLayoutValue(value) then return nil end
    if Security and Security.SafeNumber then
        local ok, numberValue = pcall(Security.SafeNumber, value)
        if ok and numberValue ~= nil
            and not IsSecretLayoutValue(numberValue) then
            return numberValue
        end
        return nil
    end
    local ok, numberValue = pcall(tonumber, value)
    if ok and numberValue ~= nil
        and not IsSecretLayoutValue(numberValue) then
        return numberValue
    end
    return nil
end

local function SafeLayoutString(value)
    if value == nil or IsSecretLayoutValue(value) then return nil end
    if Security and Security.SafeString then
        local ok, stringValue = pcall(Security.SafeString, value)
        if ok and type(stringValue) == "string"
            and not IsSecretLayoutValue(stringValue) then
            return stringValue
        end
        return nil
    end
    return type(value) == "string" and value or nil
end

local function SafeLayoutMethod(frame, methodName, ...)
    local method = frame and frame[methodName]
    if type(method) ~= "function" then return false end
    return pcall(method, frame, ...)
end

local function GetLayoutGeometry(frame, create)
    local geometry = layoutGeometryByFrame[frame]
    if not geometry and create then
        geometry = {}
        layoutGeometryByFrame[frame] = geometry
    end
    return geometry
end

local function SetLayoutSize(frame, width, height)
    if not frame then return false end
    local widthOK, currentWidth = SafeLayoutMethod(frame, "GetWidth")
    local heightOK, currentHeight = SafeLayoutMethod(frame, "GetHeight")
    currentWidth = widthOK and SafeLayoutNumber(currentWidth) or nil
    currentHeight = heightOK and SafeLayoutNumber(currentHeight) or nil
    local geometry = GetLayoutGeometry(frame, false)
    local widthMatches = currentWidth ~= nil
        and SameLayoutNumber(currentWidth, width)
        or widthOK and currentWidth == nil and geometry
            and SameLayoutNumber(geometry.width, width)
    local heightMatches = currentHeight ~= nil
        and SameLayoutNumber(currentHeight, height)
        or heightOK and currentHeight == nil and geometry
            and SameLayoutNumber(geometry.height, height)
    if widthMatches and heightMatches then
        geometry = geometry or GetLayoutGeometry(frame, true)
        geometry.width = width
        geometry.height = height
        return false
    end
    frame:SetSize(width, height)
    geometry = geometry or GetLayoutGeometry(frame, true)
    geometry.width = width
    geometry.height = height
    return true
end

local function CachedLayoutPointMatches(
    geometry,
    point,
    relativeTo,
    relativePoint,
    offsetX,
    offsetY
)
    return geometry
        and geometry.point == point
        and geometry.relativeTo == relativeTo
        and geometry.relativePoint == relativePoint
        and SameLayoutNumber(geometry.offsetX or 0, offsetX)
        and SameLayoutNumber(geometry.offsetY or 0, offsetY)
end

local function RefreshPixelAlignedPlacements(self, groupId)
    local bridge = YHUD.LayoutBridge
    if bridge and bridge.RefreshPixelAlignedPlacements then
        return bridge:RefreshPixelAlignedPlacements(groupId) == true
    end
    return false
end

local function RefreshPixelAlignedPlacementsIfNeeded(self, groupId)
    local bridge = YHUD.LayoutBridge
    if bridge and bridge.RefreshPixelAlignedPlacementsIfNeeded then
        return bridge:RefreshPixelAlignedPlacementsIfNeeded(groupId)
    end
    local refreshed = RefreshPixelAlignedPlacements(self, groupId)
    local count = refreshed and 1 or 0
    return count, count, count, false
end

local function RequestPixelAlignmentRefresh(
    self,
    groupId,
    holderSizeChanged,
    refreshAll,
    combatResourceEdge
)
    if holderSizeChanged ~= true then return false end
    if self.deferPixelAlignmentRefresh then
        self.pixelAlignmentRefreshPending = true
        return false
    end
    if combatResourceEdge == true then
        local startedAt = ProfileNowMS()
        local visited, applied, unavailable, globalFallback =
            RefreshPixelAlignedPlacementsIfNeeded(self, groupId)
        visited = tonumber(visited) or 0
        applied = tonumber(applied) or 0
        unavailable = tonumber(unavailable) or 0
        AddPerformanceStat("resourcePixelAlignmentRefreshes")
        AddPerformanceStat("resourcePixelAlignmentVisited", visited)
        AddPerformanceStat("resourcePixelAlignmentApplied", applied)
        AddPerformanceStat(
            "resourcePixelAlignmentSkipped",
            math.max(0, visited - applied)
        )
        AddPerformanceStat("resourcePixelAlignmentUnavailable", unavailable)
        if globalFallback == true then
            AddPerformanceStat("resourcePixelAlignmentGlobalFallbacks")
        end
        FinishPerformanceStat("resourcePixelAlignmentRefreshMS", startedAt)
        return applied > 0
    end
    local targetGroupId = groupId
    if refreshAll == true then targetGroupId = nil end
    return RefreshPixelAlignedPlacements(self, targetGroupId)
end

local function GetPixelLayoutScale(frame)
    if GUI2.GetPixelLayoutScale then
        return GUI2:GetPixelLayoutScale(frame)
    end
    return nil
end

local function SnapLayoutBoundary(frame, value, layoutScale)
    if GUI2.SnapLayoutBoundary then
        local snapped = GUI2:SnapLayoutBoundary(
            frame,
            value,
            layoutScale
        )
        if type(snapped) == "number" then return snapped end
    end
    return value
end

local function LayoutPointMatches(
    frame,
    point,
    relativeTo,
    relativePoint,
    offsetX,
    offsetY,
    cacheOnly
)
    local geometry = GetLayoutGeometry(frame, false)
    if cacheOnly == true then
        return CachedLayoutPointMatches(
            geometry,
            point,
            relativeTo,
            relativePoint,
            offsetX,
            offsetY
        ) == true
    end

    if frame.GetNumPoints and frame.GetPoint then
        local countOK, count = SafeLayoutMethod(frame, "GetNumPoints")
        count = countOK and SafeLayoutNumber(count) or nil
        if count == 1 then
            local pointOK, currentPoint, currentRelative,
                currentRelativePoint, currentX, currentY =
                    SafeLayoutMethod(frame, "GetPoint", 1)
            local pointSecret = IsSecretLayoutValue(currentPoint)
                or IsSecretLayoutValue(currentRelative)
                or IsSecretLayoutValue(currentRelativePoint)
                or IsSecretLayoutValue(currentX)
                or IsSecretLayoutValue(currentY)
            currentPoint = pointOK and SafeLayoutString(currentPoint) or nil
            currentRelativePoint = pointOK
                and SafeLayoutString(currentRelativePoint) or nil
            currentX = pointOK and SafeLayoutNumber(currentX) or nil
            currentY = pointOK and SafeLayoutNumber(currentY) or nil
            if currentPoint and currentRelativePoint
                and currentX ~= nil and currentY ~= nil
                and not IsSecretLayoutValue(currentRelative) then
                return currentPoint == point
                and currentRelative == relativeTo
                and currentRelativePoint == relativePoint
                and SameLayoutNumber(currentX, offsetX)
                and SameLayoutNumber(currentY, offsetY)
            end
            if not pointOK or pointSecret then
                return CachedLayoutPointMatches(
                    geometry,
                    point,
                    relativeTo,
                    relativePoint,
                    offsetX,
                    offsetY
                ) == true
            end
            return false
        elseif count ~= nil then
            return false
        end
    elseif type(frame) == "table" then
        if type(frame.point) == "table" then
            local current = frame.point
            local pointSecret = IsSecretLayoutValue(current[1])
                or IsSecretLayoutValue(current[2])
                or IsSecretLayoutValue(current[3])
                or IsSecretLayoutValue(current[4])
                or IsSecretLayoutValue(current[5])
            local currentPoint = SafeLayoutString(current[1])
            local currentRelativePoint = SafeLayoutString(current[3])
            local currentX = SafeLayoutNumber(current[4])
            local currentY = SafeLayoutNumber(current[5])
            if currentPoint and currentRelativePoint
                and currentX ~= nil and currentY ~= nil
                and not IsSecretLayoutValue(current[2]) then
                return currentPoint == point
                    and current[2] == relativeTo
                    and currentRelativePoint == relativePoint
                    and SameLayoutNumber(currentX, offsetX)
                    and SameLayoutNumber(currentY, offsetY)
            end
            if pointSecret then
                return CachedLayoutPointMatches(
                    geometry,
                    point,
                    relativeTo,
                    relativePoint,
                    offsetX,
                    offsetY
                ) == true
            end
            return false
        end
        return false
    end
    return CachedLayoutPointMatches(
        geometry,
        point,
        relativeTo,
        relativePoint,
        offsetX,
        offsetY
    ) == true
end

local function SetLayoutPoint(
    frame,
    point,
    relativeTo,
    relativePoint,
    offsetX,
    offsetY,
    cacheOnly
)
    if LayoutPointMatches(
        frame,
        point,
        relativeTo,
        relativePoint,
        offsetX,
        offsetY,
        cacheOnly
    ) then
        return false
    end
    frame:ClearAllPoints()
    frame:SetPoint(
        point,
        relativeTo,
        relativePoint,
        offsetX,
        offsetY
    )
    local geometry = GetLayoutGeometry(frame, true)
    geometry.point = point
    geometry.relativeTo = relativeTo
    geometry.relativePoint = relativePoint
    geometry.offsetX = offsetX
    geometry.offsetY = offsetY
    return true
end

local function SetEngineManagedLayoutPoint(
    frame,
    point,
    relativeTo,
    relativePoint,
    offsetX,
    offsetY
)
    return SetLayoutPoint(
        frame,
        point,
        relativeTo,
        relativePoint,
        offsetX,
        offsetY,
        true
    )
end

function I.ClearManagedLayoutPoint(frame)
    if not (frame and frame.ClearAllPoints) then return false end
    frame:ClearAllPoints()
    local geometry = GetLayoutGeometry(frame, false)
    if geometry then
        geometry.point = nil
        geometry.relativeTo = nil
        geometry.relativePoint = nil
        geometry.offsetX = nil
        geometry.offsetY = nil
    end
    return true
end

local function SetLayoutShown(frame, shown)
    local current = frame.IsShown and frame:IsShown()
    if current == shown then return false end
    if shown then frame:Show() else frame:Hide() end
    return true
end

function View:IsDesignerGroupStateAllowed(runtime)
    local designerStateAllowed = true
    if self.designMode and self.designerSkyridingState == true
        and runtime.runtimeOwned ~= true then
        local rule = runtime.visibilityRule
            or (runtime.group and runtime.group.visibility)
        local hide = type(rule) == "table" and rule.hide or nil
        if rule and rule.version == 2 then
            local branch = YUI.Visibility:GetBranch(rule, self.inCombat)
            hide = YUI.Visibility:HasActiveHides(branch) and branch.hide or nil
        end
        designerStateAllowed = not (
            type(hide) == "table" and hide.skyriding == true
        )
    end
    return designerStateAllowed
end

local function ProjectRuntimeVisibility(self, runtime)
    local designerStateAllowed = self:IsDesignerGroupStateAllowed(runtime)
    runtime.designerStateAllowed = designerStateAllowed
    local shown = self.active == true
        and (
            runtime.ignoreDesignerSurface == true
            or self.designerSurfaceVisible ~= false
        )
        and runtime.enabled == true
        and runtime.layoutEligible == true
        and runtime.presentationReady ~= false
        and designerStateAllowed
        and self:IsGroupLevelDisplayAllowed(runtime)
        and (
            runtime.visibilityAllowed ~= false
            or self.layoutEditMode
            or (self.designMode and runtime.ignoreDesignBypass ~= true)
        )
    local holderWrote = SetLayoutShown(runtime.frame, shown)
    local nativeChanged = false
    local bridge = YHUD.NativeBridge
    if bridge and bridge.ApplyGroupVisibility then
        nativeChanged = bridge:ApplyGroupVisibility(runtime.id) == true
    end
    return holderWrote, nativeChanged
end

function View:SetDesignerSkyridingState(enabled)
    enabled = enabled == true
    if self.designerSkyridingState == enabled then return false end
    self.designerSkyridingState = enabled
    if self.designMode then
        self:ProjectAllGroupVisibility()
        if self.designProjection and self.RefreshDesignProjectionVisibility then
            for _, runtime in pairs(self.designProjection.groups) do
                self:RefreshDesignProjectionVisibility(runtime)
            end
        end
    end
    return true
end

function View:ProjectGroupVisibility(groupId)
    local runtime = self.groups[groupId]
    if not runtime then return false end
    local holderWrote, nativeChanged = ProjectRuntimeVisibility(self, runtime)
    AddViewWrite(holderWrote)
    return holderWrote or nativeChanged
end

function View:ProjectAllGroupVisibility()
    local changed = false
    for groupId in pairs(self.groups) do
        if self:ProjectGroupVisibility(groupId) then changed = true end
    end
    return changed
end

function View:ProjectSingleResourceVisibility(groupId)
    local runtime = self.groups[groupId]
    if not (runtime and runtime.view == "resource"
        and runtime.monitorCount == 1
        and #(runtime.nativeFrames or {}) == 0
        and not (type(runtime.filteredAuraWidth) == "number"
            and runtime.filteredAuraWidth > 0)
        and not (type(runtime.filteredAuraHeight) == "number"
            and runtime.filteredAuraHeight > 0)) then
        return false
    end

    local monitorId = runtime.monitorIds[1]
    local slot = monitorId and self.byMonitor[monitorId]
    runtime.layoutEligible = slot ~= nil
        and slot._yhudVisibilitySuppressed ~= true
        or self.layoutEditMode or self.designMode
    local wrote = ProjectRuntimeVisibility(self, runtime)
    AddViewWrite(wrote)
    return true
end

function View:ProjectFixedResourceVisibility(groupId)
    local runtime = self.groups[groupId]
    if not (runtime
        and runtime.enabled == true
        and runtime.view == "resource"
        and runtime.layoutMode == "fixed"
        and runtime.fixedResourceGeometryReady == true
        and runtime.monitorCount > 0) then
        AddPerformanceStat("resourceFixedProjectionFallbacks")
        return false
    end

    local visibleCount = 0
    for index = 1, runtime.monitorCount do
        local monitorId = runtime.monitorIds[index]
        local slot = monitorId and self.byMonitor[monitorId]
        if not (slot
            and slot._yhudView == "resource"
            and slot._yhudGroupId == runtime.id) then
            runtime.fixedResourceGeometryReady = false
            AddPerformanceStat("resourceFixedProjectionFallbacks")
            return false
        end
        if slot._yhudVisibilitySuppressed ~= true then
            visibleCount = visibleCount + 1
        end
    end

    runtime.layoutEligible = visibleCount > 0
        or self.layoutEditMode or self.designMode
    local holderWrote = ProjectRuntimeVisibility(self, runtime)
    if holderWrote then AddViewWrite(false) end
    AddPerformanceStat("resourceFixedProjectionHits")
    return true
end

local function SetLayoutFrameLevel(frame, level)
    if not (frame and frame.SetFrameLevel) then return false end
    local current = frame.GetFrameLevel and frame:GetFrameLevel() or nil
    if current == level then return false end
    frame:SetFrameLevel(level)
    return true
end

local function SetLayoutFrameStrata(frame, strata)
    if not (frame and frame.SetFrameStrata and type(strata) == "string") then
        return false
    end
    local current = frame.GetFrameStrata and frame:GetFrameStrata() or nil
    if current == strata then return false end
    frame:SetFrameStrata(strata)
    return true
end

function View:GetMonitorDisplayLayer(runtime, monitorId)
    if not runtime then return nil, nil end
    local levels = runtime.displayLevelByMonitor
    local level = levels and levels[monitorId]
        or (runtime.displayLayerBase and runtime.displayLayerBase + 1)
    return level, runtime.displayLayerStrata
end

function View:GetMonitorTextLayer(runtime)
    if not runtime then return nil, nil end
    local level = runtime.displayTextLevel
    if not level and runtime.displayLayerBase then
        level = runtime.displayLayerBase
            + math.max(1, tonumber(runtime.monitorCount) or 0)
            + GROUP_TEXT_LAYER_OFFSET
    end
    return level, runtime.displayLayerStrata
end

function I.AssignRuntimeDisplayLayers(runtime, base, strata)
    if not runtime then return base end
    base = tonumber(base) or 0
    runtime.displayLayerBase = base
    runtime.displayLayerStrata = strata
    runtime.displayLevelByMonitor = runtime.displayLevelByMonitor or {}
    local levels = runtime.displayLevelByMonitor
    for monitorId in pairs(levels) do levels[monitorId] = nil end
    local monitorCount = tonumber(runtime.monitorCount) or 0
    for monitorIndex = 1, monitorCount do
        local monitorId = runtime.monitorIds[monitorIndex]
        if monitorId then levels[monitorId] = base + monitorIndex end
    end
    local contentCount = math.max(1, monitorCount)
    runtime.displayTextLevel = base + contentCount
        + GROUP_TEXT_LAYER_OFFSET
    return base + contentCount + GROUP_DISPLAY_LAYER_HEADROOM
end

function View:ApplyGroupDisplayLayers(profile, projection)
    profile = profile or self.profile
    local groups = projection and projection.groups or self.groups
    local byMonitor = projection and projection.byMonitor or self.byMonitor
    local groupItems = profile and profile.groups and profile.groups.items or {}
    local groupOrder = profile and profile.groups and profile.groups.order or {}
    local ordered = {}
    local included = {}
    for index = 1, #groupOrder do
        local groupId = groupOrder[index]
        local group = groupItems[groupId]
        local runtime = groups[groupId]
        if group and runtime then
            included[groupId] = true
            ordered[#ordered + 1] = {
                id = groupId,
                group = group,
                runtime = runtime,
                order = tonumber(group.order) or index,
                displayLayer = tonumber(group.displayLayer) or 5,
            }
        end
    end
    for groupId, runtime in pairs(groups or {}) do
        if runtime.runtimeOwned == true and not included[groupId] then
            local group = runtime.group or {}
            ordered[#ordered + 1] = {
                id = groupId,
                group = group,
                runtime = runtime,
                order = tonumber(group.order) or 1000,
                displayLayer = tonumber(group.displayLayer) or 5,
            }
        end
    end
    table.sort(ordered, function(left, right)
        if left.displayLayer ~= right.displayLayer then
            return left.displayLayer < right.displayLayer
        end
        if left.order ~= right.order then return left.order < right.order end
        return left.id < right.id
    end)

    local cursor = self.designMode
        and DESIGN_DISPLAY_LAYER_BASE or RUNTIME_DISPLAY_LAYER_BASE
    local changed = false
    for index = 1, #ordered do
        local runtime = ordered[index].runtime
        local targetStrata = self.designMode
            and DESIGN_DISPLAY_STRATA or runtime.baseFrameStrata
        local nextCursor = I.AssignRuntimeDisplayLayers(
            runtime,
            cursor,
            targetStrata
        )
        changed = SetLayoutFrameStrata(runtime.frame, targetStrata) or changed
        changed = SetLayoutFrameLevel(runtime.frame, cursor) or changed
        cursor = nextCursor
    end
    local owner = projection or self
    owner.displayLayerTop = cursor

    for monitorId, slot in pairs(byMonitor or {}) do
        local runtime = slot and groups[slot._yhudGroupId]
        local level, strata = self:GetMonitorDisplayLayer(runtime, monitorId)
        if level then
            changed = SetLayoutFrameStrata(slot, strata) or changed
            changed = SetLayoutFrameLevel(slot, level) or changed
            if slot._yhudView == "icon"
                and self.RefreshFilteredAuraSlotLayers then
                changed = self:RefreshFilteredAuraSlotLayers(
                    slot,
                    runtime
                ) == true or changed
            elseif slot._yhudView == "bar" then
                changed = self:RefreshDurationBarTextLayers(slot, runtime)
                    or changed
            elseif slot._yhudView == "resource" then
                changed = self:RefreshResourceTextLayers(slot, runtime)
                    or changed
            end
        end
    end

    -- 独立预览只更新自身槽位，不能改写正式运行时和原生接管帧。
    if projection then return changed end

    -- 实际增益条不是 byMonitor 中的代理槽位；它们由 AuraContainer 持有。
    -- 这里只使用公开配置层级，不读取受限 AuraFrame 的几何或显隐。
    for _, records in pairs(self.filteredAuraGlowRecords or {}) do
        for index = 1, #records do
            local slot = records[index].slot
            if slot and slot._yhudView == "bar" then
                local runtime = self.groups[slot._yhudGroupId]
                changed = self:RefreshDurationBarTextLayers(slot, runtime)
                    or changed
            end
        end
    end

    local nativeBridge = YHUD.NativeBridge
    if nativeBridge and nativeBridge.ApplyManagedFrameLayers then
        changed = nativeBridge:ApplyManagedFrameLayers() == true or changed
    end
    return changed
end

local function SetRingGeometry(
    slot,
    diameter,
    border,
    thickness,
    referenceDiameter,
    material
)
    if slot.SetDurationRingSize then
        if slot._yhudRingDiameter == diameter
            and slot._yhudRingBorder == border
            and slot._yhudRingThickness == thickness
            and slot._yhudRingReferenceDiameter == referenceDiameter
            and slot._yhudRingMaterial == material then
            return false
        end
        slot:SetDurationRingSize(
            diameter,
            border,
            thickness,
            referenceDiameter,
            material
        )
        slot._yhudRingDiameter = diameter
        slot._yhudRingBorder = border
        slot._yhudRingThickness = thickness
        slot._yhudRingReferenceDiameter = referenceDiameter
        slot._yhudRingMaterial = material
        return true
    end
    return SetLayoutSize(slot, diameter, diameter)
end

local function ApplyRuntimeGeometry(runtime, frames, geometry)
    local layoutScale = GetPixelLayoutScale(runtime.frame)
    local adapter = {
        runtime = runtime,
        frames = frames,
        layoutScale = layoutScale,
        wrote = false,
        holderSizeChanged = false,
        snappedWidth = 0,
        geometryMode = geometry.mode,
    }
    function adapter:SetHolderSize(width, height)
        local snappedWidth = self.geometryMode == "concentric" and width
            or SnapLayoutBoundary(
                self.runtime.frame,
                width,
                self.layoutScale
            )
        local snappedHeight = self.geometryMode == "concentric" and height
            or SnapLayoutBoundary(
                self.runtime.frame,
                height,
                self.layoutScale
            )
        self.snappedWidth = snappedWidth
        self.holderSizeChanged = SetLayoutSize(
            self.runtime.frame,
            snappedWidth,
            snappedHeight
        )
        self.wrote = self.holderSizeChanged or self.wrote
        return self.holderSizeChanged
    end
    function adapter:SetItemSize()
        -- Item dimensions are snapped together with their placement so both
        -- boundaries use the same pixel scale.
        return false
    end
    function adapter:SetRingGeometry(index, placement)
        local slot = self.frames[index]
        if not slot then return false end
        local changed = SetRingGeometry(
            slot,
            placement.diameter,
            self.runtime.border,
            placement.thickness or self.runtime.ringThickness,
            placement.referenceDiameter,
            placement.material
        )
        self.wrote = changed or self.wrote
        return changed
    end
    function adapter:SetItemPoint(index, placement)
        local slot = self.frames[index]
        if not slot then return false end
        local function SnapOffset(value)
            value = value or 0
            if self.geometryMode == "resource" and value < 0 then
                return -SnapLayoutBoundary(
                    self.runtime.frame,
                    -value,
                    self.layoutScale
                )
            end
            return SnapLayoutBoundary(
                self.runtime.frame,
                value,
                self.layoutScale
            )
        end
        local x = SnapOffset(placement.x)
        local y = SnapOffset(placement.y)
        local changed = false
        if self.runtime.view == "resource" and self.runtime.handPairMode == "split"
            and slot.SetResourceBarSize and placement.width and placement.height then
            changed = slot:SetResourceBarSize(placement.width, placement.height, self.runtime.orientation) == true
                or changed
        end
        if self.runtime.view ~= "bar"
            and self.runtime.view ~= "ring"
            and self.runtime.view ~= "resource"
            and placement.width and placement.height then
            local xEnd = SnapLayoutBoundary(
                self.runtime.frame,
                (placement.x or 0) + placement.width,
                self.layoutScale
            )
            local yEnd = SnapLayoutBoundary(
                self.runtime.frame,
                (placement.y or 0) + placement.height,
                self.layoutScale
            )
            local width, height = math.abs(xEnd - x), math.abs(yEnd - y)
            changed = SetLayoutSize(
                slot,
                width,
                height
            ) or changed
        end
        changed = SetLayoutPoint(
            slot,
            placement.point,
            self.runtime.frame,
            placement.relativePoint,
            x,
            y
        ) or changed
        slot._yhudPlaced = true
        self.wrote = changed or self.wrote
        return changed
    end
    function adapter:SetItemFrameLevel(index, offset)
        local slot = self.frames[index]
        if not (slot and slot.SetFrameLevel) then return false end
        local base = self.runtime.frame.GetFrameLevel
            and self.runtime.frame:GetFrameLevel() or 0
        local changed = SetLayoutFrameLevel(slot, base + offset)
        if changed and slot._yhudView == "resource" then
            View:RefreshResourceTextLayers(slot, self.runtime)
        end
        self.wrote = changed or self.wrote
        return changed
    end
    ApplyGroupGeometry(geometry, adapter)
    return adapter.wrote, adapter.holderSizeChanged, adapter.snappedWidth
end

local function ResolveResourceWidth(self, runtime)
    local width = tonumber(runtime.resourceFixedWidth)
        or tonumber(runtime.resourceWidth)
        or DEFAULT_RESOURCE_WIDTH
    if runtime.resourceWidthMode == "auto" then
        local minWidth = tonumber(runtime.resourceMinWidth) or 150
        local importantWidth = tonumber(self.importantGroupContentWidth)
        width = math.max(minWidth, importantWidth or 0)
    end
    local layoutScale = GetPixelLayoutScale(runtime.frame)
    return SnapLayoutBoundary(runtime.frame, width, layoutScale)
end
I.ResolveResourceWidth = ResolveResourceWidth

local function ClearResourceEdgeLayout(runtime, releaseStorage)
    local cache = runtime and runtime.resourceEdgeLayout
    if not cache then return false end
    cache.valid = false
    if releaseStorage == true then runtime.resourceEdgeLayout = nil end
    return true
end

local function ClearResourcePrefixLayout(runtime, releaseStorage)
    local cache = runtime and runtime.resourcePrefixLayout
    if not cache then return false end
    cache.valid = false
    if releaseStorage ~= true then return true end

    local count = tonumber(cache.count) or 0
    for index = 1, count do
        cache.monitorIds[index] = nil
        cache.slots[index] = nil
        cache.slotWidths[index] = nil
        cache.slotHeights[index] = nil
        cache.prefixWidths[index] = nil
        cache.prefixHeights[index] = nil
    end
    cache.prefixWidths[0] = nil
    cache.prefixHeights[0] = nil
    runtime.resourcePrefixLayout = nil
    return true
end

function View:InvalidateResourcePrefixLayout(groupId, releaseStorage)
    local runtime = self.groups and self.groups[groupId]
    local prefixCleared = ClearResourcePrefixLayout(runtime, releaseStorage)
    local edgeCleared = ClearResourceEdgeLayout(runtime, releaseStorage)
    return prefixCleared or edgeCleared
end

local function BuildResourcePrefixLayout(
    self,
    runtime,
    frames,
    visibleCount,
    hasNativeContent
)
    local existing = runtime.resourcePrefixLayout
    if existing then existing.valid = false end

    local count = tonumber(runtime.monitorCount) or 0
    if runtime.handPairMode == "split" or count <= 1 or runtime.hasCombatResourceVisibility ~= true
        or hasNativeContent == true
        or self.preview or self.designMode or self.layoutEditMode
        or (runtime.nativeFrames and #runtime.nativeFrames > 0)
        or (runtime.nativeByMonitor and next(runtime.nativeByMonitor))
        or (type(runtime.nativeWidth) == "number" and runtime.nativeWidth > 0)
        or (type(runtime.nativeHeight) == "number" and runtime.nativeHeight > 0)
        or (type(runtime.filteredAuraWidth) == "number"
            and runtime.filteredAuraWidth > 0)
        or (type(runtime.filteredAuraHeight) == "number"
            and runtime.filteredAuraHeight > 0) then
        return nil, visibleCount
    end

    local perLine = math.min(
        math.max(1, runtime.maxPerLine or DEFAULT_MAX_PER_LINE),
        count
    )
    if count > perLine and runtime.alignment ~= "start" then
        return nil, visibleCount
    end

    local horizontal = runtime.direction == "right"
        or runtime.direction == "left"
    local firstCrossSize
    local actualVisible = 0
    local hiddenStarted = false
    for index = 1, count do
        local monitorId = runtime.monitorIds[index]
        local monitor = monitorId and self.desiredMonitors[monitorId]
        local slot = monitorId and self.byMonitor[monitorId]
        if not (monitorId and monitor and slot
            and slot._yhudView == "resource"
            and slot._yhudGroupId == runtime.id)
            or slot._yhudNativePersistentPlaceholder == true
            or (self.filteredAuraFrames
                and self.filteredAuraFrames[monitorId]) then
            return nil, visibleCount
        end

        local suppressed = slot._yhudVisibilitySuppressed == true
        if suppressed then
            hiddenStarted = true
        elseif hiddenStarted then
            return nil, visibleCount
        else
            actualVisible = actualVisible + 1
            if frames[actualVisible] ~= slot then
                return nil, visibleCount
            end
        end

        if horizontal then
            local crossSize = slot.GetHeight and tonumber(slot:GetHeight())
                or runtime.resourceHeight or DEFAULT_RESOURCE_HEIGHT
            if type(crossSize) ~= "number" or crossSize <= 0 then
                return nil, visibleCount
            end
            if firstCrossSize == nil then
                firstCrossSize = crossSize
            elseif not SameLayoutNumber(firstCrossSize, crossSize) then
                return nil, visibleCount
            end
        end
    end
    if actualVisible ~= visibleCount then
        return nil, visibleCount
    end

    -- Only expand the caller's compact visible-frame array after the complete
    -- prefix contract has passed. A middle hidden slot is a valid generic
    -- layout case; mutating frames before rejecting it would make that hidden
    -- slot occupy the next visible position and leave a hole on screen.
    for index = 1, count do
        frames[index] = self.byMonitor[runtime.monitorIds[index]]
    end

    local cache = existing or {
        monitorIds = {},
        slots = {},
        slotWidths = {},
        slotHeights = {},
        prefixWidths = {},
        prefixHeights = {},
    }
    local previousCount = tonumber(cache.count) or 0
    for index = 1, count do
        cache.monitorIds[index] = runtime.monitorIds[index]
        cache.slots[index] = frames[index]
    end
    for index = count + 1, previousCount do
        cache.monitorIds[index] = nil
        cache.slots[index] = nil
        cache.slotWidths[index] = nil
        cache.slotHeights[index] = nil
        cache.prefixWidths[index] = nil
        cache.prefixHeights[index] = nil
    end
    cache.count = count
    cache.valid = false
    runtime.resourcePrefixLayout = cache
    return cache, count
end

local function ApplyEffectiveResourceWidth(runtime, frames, count, width)
    local wrote = false
    runtime.effectiveResourceWidth = width
    for index = 1, count do
        local slot = frames[index]
        local currentWidth = slot and slot.GetWidth
            and tonumber(slot:GetWidth()) or nil
        local resourceWidth = slot and tonumber(slot.gui2ResourceWidth)
        local resourceWidthOutOfSync = resourceWidth ~= nil
            and not SameLayoutNumber(resourceWidth, width)
        if slot and (not SameLayoutNumber(currentWidth, width)
            or resourceWidthOutOfSync) then
            local height = slot.GetHeight and tonumber(slot:GetHeight())
                or runtime.resourceHeight or DEFAULT_RESOURCE_HEIGHT
            if slot.SetResourceBarSize then
                slot:SetResourceBarSize(width, height, runtime.orientation)
                wrote = true
            else
                wrote = SetLayoutSize(slot, width, height) or wrote
            end
        end
    end
    return wrote
end

local function PrepareResourceEdgeState(
    runtime,
    cache,
    state,
    useCombatVisibility,
    spacing,
    minimumStep,
    layoutScale
)
    local visibleSlots = {}
    local visibleMetrics = {}
    local sourceIndices = {}
    for index = 1, cache.count do
        local monitor = cache.monitors[index]
        local suppressed = cache.outSuppressed[index] == true
        if useCombatVisibility
            and monitor.resourceVisibilityMode == "nonzeroOrCombat" then
            suppressed = false
        end
        state.suppressed[index] = suppressed
        state.primaryOffsets[index] = nil
        state.secondaryOffsets[index] = nil
        if not suppressed then
            local visibleIndex = #visibleSlots + 1
            visibleSlots[visibleIndex] = cache.slots[index]
            visibleMetrics[visibleIndex] = {
                width = cache.slotWidths[index],
                height = cache.slotHeights[index],
            }
            sourceIndices[visibleIndex] = index
        end
    end
    local visibleCount = #visibleSlots
    state.visibleCount = visibleCount
    if visibleCount == 0 then
        state.width = 0
        state.height = 0
        return
    end
    local geometry = BuildGroupGeometry(
        {
            view = "resource",
            direction = runtime.direction,
            alignment = runtime.alignment,
            maxPerLine = runtime.maxPerLine,
            spacing = spacing,
            effectiveResourceWidth = runtime.effectiveResourceWidth,
            resourceWidth = runtime.resourceWidth,
            resourceHeight = runtime.resourceHeight,
        },
        visibleSlots,
        visibleCount,
        {
            minimumPixelStep = minimumStep,
            resourceMetrics = visibleMetrics,
        }
    )
    state.width = SnapLayoutBoundary(
        runtime.frame,
        geometry.width,
        layoutScale
    )
    state.height = SnapLayoutBoundary(
        runtime.frame,
        geometry.height,
        layoutScale
    )
    for visibleIndex = 1, visibleCount do
        local sourceIndex = sourceIndices[visibleIndex]
        local placement = geometry.placements[visibleIndex]
        if runtime.direction == "left" then
            state.primaryOffsets[sourceIndex] = -placement.x
            state.secondaryOffsets[sourceIndex] = -placement.y
        elseif runtime.direction == "down" then
            state.primaryOffsets[sourceIndex] = -placement.y
            state.secondaryOffsets[sourceIndex] = placement.x
        elseif runtime.direction == "up" then
            state.primaryOffsets[sourceIndex] = placement.y
            state.secondaryOffsets[sourceIndex] = placement.x
        else
            state.primaryOffsets[sourceIndex] = placement.x
            state.secondaryOffsets[sourceIndex] = -placement.y
        end
        state.primaryOffsets[sourceIndex] = SnapLayoutBoundary(
            runtime.frame,
            state.primaryOffsets[sourceIndex],
            layoutScale
        )
        state.secondaryOffsets[sourceIndex] = SnapLayoutBoundary(
            runtime.frame,
            state.secondaryOffsets[sourceIndex],
            layoutScale
        )
    end
end

local function BuildResourceEdgeLayout(
    self,
    runtime,
    hasNativeContent
)
    local existing = runtime.resourceEdgeLayout
    if existing then existing.valid = false end
    local count = tonumber(runtime.monitorCount) or 0
    local perLine = math.min(
        math.max(1, runtime.maxPerLine or DEFAULT_MAX_PER_LINE),
        math.max(1, count)
    )
    if runtime.handPairMode == "split" or count <= 1 or count > perLine
        or runtime.hasCombatResourceVisibility ~= true
        or self.inCombat == true or IsInCombat()
        or hasNativeContent == true
        or self.preview or self.designMode or self.layoutEditMode
        or (runtime.nativeFrames and #runtime.nativeFrames > 0)
        or (runtime.nativeByMonitor and next(runtime.nativeByMonitor))
        or (type(runtime.filteredAuraWidth) == "number"
            and runtime.filteredAuraWidth > 0)
        or (type(runtime.filteredAuraHeight) == "number"
            and runtime.filteredAuraHeight > 0) then
        ClearResourceEdgeLayout(runtime, true)
        return false
    end

    local cache = existing or {
        monitorIds = {},
        monitors = {},
        slots = {},
        slotWidths = {},
        slotHeights = {},
        outSuppressed = {},
        outOfCombat = {
            suppressed = {},
            primaryOffsets = {},
            secondaryOffsets = {},
        },
        inCombat = {
            suppressed = {},
            primaryOffsets = {},
            secondaryOffsets = {},
        },
    }
    local previousCount = tonumber(cache.count) or 0
    local hasMiddleGap = false
    local hiddenSeen = false
    for index = 1, count do
        local monitorId = runtime.monitorIds[index]
        local monitor = monitorId and self.desiredMonitors[monitorId]
        local slot = monitorId and self.byMonitor[monitorId]
        if not (monitorId and monitor and slot
            and slot._yhudView == "resource"
            and slot._yhudGroupId == runtime.id)
            or slot._yhudNativePersistentPlaceholder == true
            or (self.filteredAuraFrames
                and self.filteredAuraFrames[monitorId]) then
            ClearResourceEdgeLayout(runtime, true)
            return false
        end
        local suppressed = slot._yhudVisibilitySuppressed == true
        if suppressed then
            hiddenSeen = true
        elseif hiddenSeen then
            hasMiddleGap = true
        end
        cache.monitorIds[index] = monitorId
        cache.monitors[index] = monitor
        cache.slots[index] = slot
        cache.outSuppressed[index] = suppressed
    end
    if not hasMiddleGap then
        ClearResourceEdgeLayout(runtime, true)
        return false
    end
    for index = count + 1, previousCount do
        cache.monitorIds[index] = nil
        cache.monitors[index] = nil
        cache.slots[index] = nil
        cache.slotWidths[index] = nil
        cache.slotHeights[index] = nil
        cache.outSuppressed[index] = nil
        cache.outOfCombat.suppressed[index] = nil
        cache.outOfCombat.primaryOffsets[index] = nil
        cache.outOfCombat.secondaryOffsets[index] = nil
        cache.inCombat.suppressed[index] = nil
        cache.inCombat.primaryOffsets[index] = nil
        cache.inCombat.secondaryOffsets[index] = nil
    end
    cache.count = count

    local effectiveWidth = ResolveResourceWidth(self, runtime)
    if ApplyEffectiveResourceWidth(
        runtime,
        cache.slots,
        count,
        effectiveWidth
    ) then
        AddViewWrite(false)
    end
    for index = 1, count do
        local slot = cache.slots[index]
        local width = slot.GetWidth and tonumber(slot:GetWidth())
        local height = slot.GetHeight and tonumber(slot:GetHeight())
        if type(width) ~= "number" or width <= 0
            or type(height) ~= "number" or height <= 0 then
            ClearResourceEdgeLayout(runtime, true)
            return false
        end
        cache.slotWidths[index] = width
        cache.slotHeights[index] = height
    end

    local spacing = tonumber(runtime.spacing) or 0
    if spacing ~= 0 and GUI2.GetPixelSize then
        local spacingPixels = math.abs(spacing)
        local snappedSpacing = GUI2:GetPixelSize(
            runtime.frame,
            spacingPixels,
            spacingPixels
        )
        spacing = spacing < 0 and -snappedSpacing or snappedSpacing
    end
    local minimumStep = GUI2.GetPixelSize
        and GUI2:GetPixelSize(runtime.frame, 1, 1)
        or (GUI2.mult or 1)
    local layoutScale = GetPixelLayoutScale(runtime.frame)
    PrepareResourceEdgeState(
        runtime,
        cache,
        cache.outOfCombat,
        false,
        spacing,
        minimumStep,
        layoutScale
    )
    PrepareResourceEdgeState(
        runtime,
        cache,
        cache.inCombat,
        true,
        spacing,
        minimumStep,
        layoutScale
    )
    cache.direction = runtime.direction
    cache.alignment = runtime.alignment
    cache.maxPerLine = runtime.maxPerLine
    cache.spacing = runtime.spacing
    cache.layoutScale = layoutScale
    cache.effectiveWidth = effectiveWidth
    cache.valid = true
    runtime.resourceEdgeLayout = cache
    AddPerformanceStat("resourceEdgePrepared")
    AddPerformanceStat("resourceEdgePreparedSlots", count)
    return true
end

local function PublishImportantGroupWidth(
    self,
    groupId,
    width,
    hasContent
)
    if groupId ~= YHUD.GROUP_IDS.IMPORTANT then return false end
    local nextWidth = hasContent and tonumber(width) or nil
    if nextWidth and nextWidth <= 0 then nextWidth = nil end
    local previousWidth = self.importantGroupContentWidth
    if (previousWidth == nil and nextWidth == nil)
        or SameLayoutNumber(previousWidth, nextWidth) then
        return false
    end
    self.importantGroupContentWidth = nextWidth

    if self.autoResourceWidthRelayout then
        return true
    end
    self.autoResourceWidthRelayout = true
    for resourceGroupId, resourceRuntime in pairs(self.groups) do
        if resourceRuntime.view == "resource" and resourceRuntime.resourceWidthMode == "auto" then
            self:RelayoutGroup(resourceGroupId)
        end
    end
    self.autoResourceWidthRelayout = nil
    return true
end

local function RelayoutResourceFrames(
    self,
    runtime,
    groupId,
    frames,
    count,
    hasNativeContent,
    combatResourceEdge,
    visibleCount,
    prefixCache
)
    visibleCount = tonumber(visibleCount) or count
    local wrote = false
    local effectiveWidth = ResolveResourceWidth(self, runtime)
    if runtime.handPairMode ~= "split" then
        wrote = ApplyEffectiveResourceWidth(runtime, frames, count, effectiveWidth) or wrote
    end
    local minimumStep = GUI2.GetPixelSize
        and GUI2:GetPixelSize(runtime.frame, 1, 1)
        or (GUI2.mult or 1)
    local resourceMetrics = {}
    local layoutScale = GetPixelLayoutScale(runtime.frame)
    local presentationMembers = runtime.presentationGroupPlan
        and runtime.presentationGroupPlan.memberById or nil
    for index = 1, count do
        -- Auto layout compacts hidden members; the visible slot retains its own
        -- presentation even when it no longer occupies the original index.
        local slot = frames[index]
        local monitorId = slot and slot._yhudMonitorId or runtime.monitorIds[index]
        local member = monitorId and presentationMembers
            and presentationMembers[monitorId] or nil
        local spec = member and member.resourceSpec
        local height = spec and spec.height
            or slot and slot.gui2ResourceHeight
            or slot and slot.height
            or runtime.resourceHeight
            or DEFAULT_RESOURCE_HEIGHT
        -- Quantize the actual bars before accumulating their positions. Snapping
        -- only the cumulative offsets leaves fractional heights at shared edges.
        height = math.max(minimumStep, SnapLayoutBoundary(runtime.frame, height, layoutScale))
        if slot and slot.SetResourceBarSize and slot.gui2ResourceHeight ~= height then
            slot:SetResourceBarSize(effectiveWidth, height, runtime.orientation)
            wrote = true
        end
        resourceMetrics[index] = {
            resourceId = slot and slot._yhudResourceId,
            width = effectiveWidth,
            height = height,
        }
    end
    local geometry = BuildGroupGeometry(
        runtime,
        frames,
        count,
        {
            visibleCount = prefixCache and visibleCount or nil,
            pixelSize = GUI2.GetPixelSize and function(pixels)
                return GUI2:GetPixelSize(runtime.frame, pixels, pixels)
            end or nil,
            minimumPixelStep = minimumStep,
            resourceMetrics = resourceMetrics,
        }
    )
    local metrics = geometry.metrics or {}
    local width = geometry.width
    local height = geometry.height
    local fallbackHeight = runtime.resourceHeight or runtime.itemHeight
        or DEFAULT_RESOURCE_HEIGHT
    if prefixCache then
        local prefixWidths = prefixCache.prefixWidths
        local prefixHeights = prefixCache.prefixHeights
        prefixWidths[0] = 0
        prefixHeights[0] = 0
        for position = 1, count do
            prefixWidths[position] = SnapLayoutBoundary(
                runtime.frame,
                geometry.prefixWidths[position] or 0,
                layoutScale
            )
            prefixHeights[position] = SnapLayoutBoundary(
                runtime.frame,
                geometry.prefixHeights[position] or 0,
                layoutScale
            )
        end
        width = prefixWidths[visibleCount]
        height = prefixHeights[visibleCount]
    end
    if visibleCount == 0 and runtime.filteredAuraWidth
        and runtime.filteredAuraHeight then
        width = runtime.filteredAuraWidth
        height = runtime.filteredAuraHeight
    elseif visibleCount == 0 and runtime.nativeWidth and runtime.nativeHeight then
        width = runtime.nativeWidth
        height = runtime.nativeHeight
    elseif visibleCount == 0 and (self.designMode or self.layoutEditMode) then
        width = EMPTY_DESIGN_GROUP_WIDTH
        height = math.max(fallbackHeight, 38)
    end
    geometry.width = width
    geometry.height = height
    local geometryWrote, holderSizeChanged = ApplyRuntimeGeometry(
        runtime,
        frames,
        geometry
    )
    wrote = geometryWrote or wrote
    runtime.presentationGeometry = geometry
    for position = 1, count do
        local metric = metrics[position]
        if prefixCache then
            prefixCache.slotWidths[position] = metric and metric.width or nil
            prefixCache.slotHeights[position] = metric and metric.height or nil
        end
    end

    if prefixCache then
        prefixCache.direction = runtime.direction
        prefixCache.alignment = runtime.alignment
        prefixCache.maxPerLine = runtime.maxPerLine
        prefixCache.spacing = runtime.spacing
        prefixCache.layoutScale = layoutScale
        prefixCache.effectiveWidth = effectiveWidth
        prefixCache.valid = true
    end

    runtime.layoutEligible = visibleCount > 0 or hasNativeContent
        or self.layoutEditMode or self.designMode
    wrote = ProjectRuntimeVisibility(self, runtime) or wrote
    RequestPixelAlignmentRefresh(
        self,
        groupId,
        holderSizeChanged,
        hasNativeContent,
        combatResourceEdge
    )
    AddViewWrite(wrote)
    return wrote
end

local function RejectResourcePrefixProjection(runtime, startedAt)
    local cache = runtime and runtime.resourcePrefixLayout
    if cache then cache.valid = false end
    AddPerformanceStat("resourcePrefixProjectionFallbacks")
    FinishPerformanceStat("resourcePrefixProjectionMS", startedAt)
    return false
end

function View:ProjectPreparedResourcePrefix(groupId)
    local startedAt = ProfileNowMS()
    local runtime = self.groups[groupId]
    local cache = runtime and runtime.resourcePrefixLayout
    if not cache then return false end
    if not (self.active and runtime and runtime.enabled == true
        and runtime.view == "resource"
        and runtime.hasCombatResourceVisibility == true
        and cache and cache.valid == true)
        or self.preview or self.designMode or self.layoutEditMode
        or (runtime.nativeFrames and #runtime.nativeFrames > 0)
        or (runtime.nativeByMonitor and next(runtime.nativeByMonitor))
        or (type(runtime.filteredAuraWidth) == "number"
            and runtime.filteredAuraWidth > 0)
        or (type(runtime.filteredAuraHeight) == "number"
            and runtime.filteredAuraHeight > 0)
        or cache.count ~= runtime.monitorCount
        or cache.direction ~= runtime.direction
        or cache.alignment ~= runtime.alignment
        or cache.maxPerLine ~= runtime.maxPerLine
        or cache.spacing ~= runtime.spacing then
        return RejectResourcePrefixProjection(runtime, startedAt)
    end

    local layoutScale = GetPixelLayoutScale(runtime.frame)
    if cache.layoutScale ~= layoutScale
        and not SameLayoutNumber(cache.layoutScale, layoutScale) then
        return RejectResourcePrefixProjection(runtime, startedAt)
    end
    local effectiveWidth = ResolveResourceWidth(self, runtime)
    if not SameLayoutNumber(cache.effectiveWidth, effectiveWidth) then
        return RejectResourcePrefixProjection(runtime, startedAt)
    end

    local visibleCount = 0
    local hiddenStarted = false
    for index = 1, cache.count do
        local monitorId = runtime.monitorIds[index]
        local slot = monitorId and self.byMonitor[monitorId]
        local width = slot and slot.GetWidth and tonumber(slot:GetWidth())
        local height = slot and slot.GetHeight and tonumber(slot:GetHeight())
        if monitorId ~= cache.monitorIds[index]
            or not slot
            or slot ~= cache.slots[index]
            or slot._yhudView ~= "resource"
            or slot._yhudGroupId ~= runtime.id
            or not SameLayoutNumber(width, cache.slotWidths[index])
            or not SameLayoutNumber(height, cache.slotHeights[index]) then
            return RejectResourcePrefixProjection(runtime, startedAt)
        end

        if slot._yhudVisibilitySuppressed == true then
            hiddenStarted = true
        elseif hiddenStarted then
            return RejectResourcePrefixProjection(runtime, startedAt)
        else
            visibleCount = index
        end
    end

    local width = cache.prefixWidths[visibleCount]
    local height = cache.prefixHeights[visibleCount]
    if type(width) ~= "number" or type(height) ~= "number" then
        return RejectResourcePrefixProjection(runtime, startedAt)
    end

    local holderSizeChanged = SetLayoutSize(runtime.frame, width, height)
    runtime.layoutEligible = visibleCount > 0
    local holderWrote = ProjectRuntimeVisibility(self, runtime)
    local wrote = holderSizeChanged or holderWrote
    RequestPixelAlignmentRefresh(
        self,
        groupId,
        holderSizeChanged,
        false,
        true
    )
    AddViewWrite(wrote)
    AddPerformanceStat("resourcePrefixProjectionHits")
    FinishPerformanceStat("resourcePrefixProjectionMS", startedAt)
    return true
end

local function RejectResourceEdgeProjection(runtime, startedAt)
    local cache = runtime and runtime.resourceEdgeLayout
    if cache then cache.valid = false end
    AddPerformanceStat("resourceEdgeProjectionFallbacks")
    FinishPerformanceStat("resourceEdgeProjectionMS", startedAt)
    return false
end

function View:ProjectPreparedResourceEdgeLayout(groupId)
    local startedAt = ProfileNowMS()
    local runtime = self.groups[groupId]
    local cache = runtime and runtime.resourceEdgeLayout
    if not cache then return false end
    if not (self.active and runtime and runtime.enabled == true
        and runtime.view == "resource"
        and runtime.hasCombatResourceVisibility == true
        and cache.valid == true)
        or self.preview or self.designMode or self.layoutEditMode
        or (runtime.nativeFrames and #runtime.nativeFrames > 0)
        or (runtime.nativeByMonitor and next(runtime.nativeByMonitor))
        or (type(runtime.filteredAuraWidth) == "number"
            and runtime.filteredAuraWidth > 0)
        or (type(runtime.filteredAuraHeight) == "number"
            and runtime.filteredAuraHeight > 0)
        or cache.count ~= runtime.monitorCount
        or cache.direction ~= runtime.direction
        or cache.alignment ~= runtime.alignment
        or cache.maxPerLine ~= runtime.maxPerLine
        or cache.spacing ~= runtime.spacing then
        return RejectResourceEdgeProjection(runtime, startedAt)
    end

    local layoutScale = GetPixelLayoutScale(runtime.frame)
    if cache.layoutScale ~= layoutScale
        and not SameLayoutNumber(cache.layoutScale, layoutScale) then
        return RejectResourceEdgeProjection(runtime, startedAt)
    end
    local effectiveWidth = ResolveResourceWidth(self, runtime)
    if not SameLayoutNumber(cache.effectiveWidth, effectiveWidth) then
        return RejectResourceEdgeProjection(runtime, startedAt)
    end

    local state = self.inCombat == true
        and cache.inCombat or cache.outOfCombat
    for index = 1, cache.count do
        local monitorId = runtime.monitorIds[index]
        local monitor = monitorId and self.desiredMonitors[monitorId]
        local slot = monitorId and self.byMonitor[monitorId]
        local width = slot and slot.GetWidth and tonumber(slot:GetWidth())
        local height = slot and slot.GetHeight and tonumber(slot:GetHeight())
        if monitorId ~= cache.monitorIds[index]
            or monitor ~= cache.monitors[index]
            or not slot or slot ~= cache.slots[index]
            or slot._yhudView ~= "resource"
            or slot._yhudGroupId ~= runtime.id
            or (slot._yhudVisibilitySuppressed == true)
                ~= (state.suppressed[index] == true)
            or not SameLayoutNumber(width, cache.slotWidths[index])
            or not SameLayoutNumber(height, cache.slotHeights[index]) then
            return RejectResourceEdgeProjection(runtime, startedAt)
        end
    end

    local wrote = false
    for index = 1, cache.count do
        if state.suppressed[index] ~= true then
            local slot = cache.slots[index]
            local primaryOffset = state.primaryOffsets[index]
            local secondaryOffset = state.secondaryOffsets[index]
            if runtime.direction == "left" then
                wrote = SetLayoutPoint(
                    slot,
                    "TOPRIGHT",
                    runtime.frame,
                    "TOPRIGHT",
                    -primaryOffset,
                    -secondaryOffset
                ) or wrote
            elseif runtime.direction == "down" then
                wrote = SetLayoutPoint(
                    slot,
                    "TOPLEFT",
                    runtime.frame,
                    "TOPLEFT",
                    secondaryOffset,
                    -primaryOffset
                ) or wrote
            elseif runtime.direction == "up" then
                wrote = SetLayoutPoint(
                    slot,
                    "BOTTOMLEFT",
                    runtime.frame,
                    "BOTTOMLEFT",
                    secondaryOffset,
                    primaryOffset
                ) or wrote
            else
                wrote = SetLayoutPoint(
                    slot,
                    "TOPLEFT",
                    runtime.frame,
                    "TOPLEFT",
                    primaryOffset,
                    -secondaryOffset
                ) or wrote
            end
            slot._yhudPlaced = true
        end
    end

    local holderSizeChanged = SetLayoutSize(
        runtime.frame,
        state.width,
        state.height
    )
    runtime.layoutEligible = state.visibleCount > 0
    local holderWrote = ProjectRuntimeVisibility(self, runtime)
    wrote = holderSizeChanged or holderWrote or wrote
    RequestPixelAlignmentRefresh(
        self,
        groupId,
        holderSizeChanged,
        false,
        true
    )
    AddViewWrite(wrote)
    AddPerformanceStat("resourceEdgeProjectionHits")
    FinishPerformanceStat("resourceEdgeProjectionMS", startedAt)
    return true
end

function View:IsMonitorLayoutParticipating(monitor, state, fixedLayout)
    if type(monitor) ~= "table" then
        return true
    end
    if monitor._yhudPreviewOnly == true then
        return self.preview == true
    end
    if I.IsPlayerCastCollapsed and I.IsPlayerCastCollapsed(self, monitor, state) then return false end
    if monitor._yhudEquipmentTriggerKind ~= "active-timer" then
        return true
    end
    if fixedLayout == true or self.preview == true then
        return true
    end
    if state == nil and YHUD.Model and YHUD.Model.GetState then
        state = YHUD.Model:GetState(monitor.sourceKey)
    end
    return type(state) == "table" and state.available == true
end

local function AcquireFilteredAuraLayoutAnchor(runtime, key)
    local anchors = runtime.filteredAuraLayoutAnchors
    if not anchors then
        anchors = {}
        runtime.filteredAuraLayoutAnchors = anchors
    end
    local anchor = anchors[key]
    if anchor then return anchor end
    anchor = CreateFrame(
        "Frame",
        nil,
        runtime.frame,
        "DisableUntrustedLayoutScriptsTemplate"
    )
    anchors[key] = anchor
    return anchor
end

local function ResolveFilteredAuraLayoutFrame(self, runtime, monitorId)
    local monitor = monitorId and self.desiredMonitors[monitorId]
    local nativeFrame = runtime.nativeByMonitor
        and runtime.nativeByMonitor[monitorId]
    local ownedFrame = self.byMonitor[monitorId]
    if ownedFrame
        and not self:IsMonitorLayoutParticipating(
            monitor,
            nil,
            false
        ) then
        ownedFrame._yhudLayoutParticipating = false
        self:ReleaseSlot(monitorId)
        ownedFrame = nil
    end
    if ownedFrame and ownedFrame._yhudVisibilitySuppressed == true then
        ownedFrame = nil
    end
    local persistentPlaceholder = ownedFrame
        and ownedFrame._yhudNativePersistentPlaceholder == true
    if persistentPlaceholder then
        local hidden = nativeFrame ~= nil
        if ownedFrame._yhudNativePlaceholderHidden ~= hidden then
            ownedFrame._yhudNativePlaceholderHidden = hidden
            if hidden then ownedFrame:Hide() else ownedFrame:Show() end
        end
    end
    local frame = persistentPlaceholder and nativeFrame
        or ownedFrame
        or nativeFrame
    if persistentPlaceholder and not frame then frame = ownedFrame end
    return frame, nativeFrame
end

local function ResetFilteredAuraLayoutCache(runtime)
    local cache = runtime.filteredAuraLayoutCache
    if not cache then
        cache = {
            normalFrames = {},
            normalKinds = {},
            normalValues = {},
            specialKinds = {},
            specialValues = {},
            sequenceKinds = {},
            sequenceValues = {},
        }
        runtime.filteredAuraLayoutCache = cache
    end
    cache.normalKinds = cache.normalKinds or {}
    cache.normalValues = cache.normalValues or {}
    cache.normalCount = 0
    cache.specialCount = 0
    cache.specialSequenceCount = 0
    cache.sequenceCount = 0
    return cache
end

local function ClearFilteredAuraLayoutCacheTail(cache)
    for index = cache.normalCount + 1, #cache.normalKinds do
        cache.normalFrames[index] = nil
        cache.normalKinds[index] = nil
        cache.normalValues[index] = nil
    end
    for index = cache.specialSequenceCount + 1,
        #cache.specialKinds do
        cache.specialKinds[index] = nil
        cache.specialValues[index] = nil
    end
    for index = cache.sequenceCount + 1, #cache.sequenceKinds do
        cache.sequenceKinds[index] = nil
        cache.sequenceValues[index] = nil
    end
end

local function CollectFilteredAuraLayout(self, runtime)
    local cache = ResetFilteredAuraLayoutCache(runtime)
    local usedNative = runtime.filteredAuraUsedNative or {}
    runtime.filteredAuraUsedNative = usedNative
    for frame in pairs(usedNative) do usedNative[frame] = nil end
    for index = 1, runtime.monitorCount do
        local monitorId = runtime.monitorIds[index]
        local monitor = monitorId and self.desiredMonitors[monitorId]
        local entry = monitor and self.profile and self.profile.entries
            and self.profile.entries[monitor.entryKey]
        local presentationMember = runtime.presentationGroupPlan
            and runtime.presentationGroupPlan.memberById
            and runtime.presentationGroupPlan.memberById[monitorId]
        local special = presentationMember
            and presentationMember.special == true
            or false
        local dynamic = self.filteredAuraDynamicNodes
            and self.filteredAuraDynamicNodes[monitorId]
        if dynamic and dynamic.node then
            local projectedNative = runtime.nativeByMonitor
                and runtime.nativeByMonitor[monitorId]
            if projectedNative then usedNative[projectedNative] = true end
            if special then
                cache.specialCount = cache.specialCount + 1
                cache.specialSequenceCount = cache.specialSequenceCount + 1
                cache.specialKinds[cache.specialSequenceCount] = "special"
                cache.specialValues[cache.specialSequenceCount] = monitorId
            else
                cache.normalCount = cache.normalCount + 1
                cache.normalFrames[cache.normalCount] = nil
                cache.normalKinds[cache.normalCount] = "normal-dynamic"
                cache.normalValues[cache.normalCount] = monitorId
            end
            cache.sequenceCount = cache.sequenceCount + 1
            cache.sequenceKinds[cache.sequenceCount] = special
                and "special" or "normal-dynamic"
            cache.sequenceValues[cache.sequenceCount] = monitorId
        else
            local frame, nativeFrame = ResolveFilteredAuraLayoutFrame(
                self,
                runtime,
                monitorId
            )
            if nativeFrame then usedNative[nativeFrame] = true end
            if frame then
                if special then
                    cache.specialSequenceCount =
                        cache.specialSequenceCount + 1
                    cache.specialKinds[cache.specialSequenceCount] =
                        "special-frame"
                    cache.specialValues[cache.specialSequenceCount] = frame
                else
                    cache.normalCount = cache.normalCount + 1
                    cache.normalFrames[cache.normalCount] = frame
                    cache.normalKinds[cache.normalCount] = "normal"
                    cache.normalValues[cache.normalCount] = frame
                end
                cache.sequenceCount = cache.sequenceCount + 1
                cache.sequenceKinds[cache.sequenceCount] = special
                    and "special-frame" or "normal"
                cache.sequenceValues[cache.sequenceCount] = frame
                usedNative[frame] = true
            end
        end
    end
    for index = 1, #(runtime.nativeFrames or {}) do
        local frame = runtime.nativeFrames[index]
        if frame and not usedNative[frame] then
            cache.normalCount = cache.normalCount + 1
            cache.normalFrames[cache.normalCount] = frame
            cache.normalKinds[cache.normalCount] = "normal"
            cache.normalValues[cache.normalCount] = frame
            cache.sequenceCount = cache.sequenceCount + 1
            cache.sequenceKinds[cache.sequenceCount] = "normal"
            cache.sequenceValues[cache.sequenceCount] = frame
            usedNative[frame] = true
        end
    end
    ClearFilteredAuraLayoutCacheTail(cache)
    return cache
end

local function AnchorFilteredAuraFlowNode(
    node,
    cursor,
    cursorPoint,
    growth
)
    if growth == "left" then
        return SetEngineManagedLayoutPoint(
            node,
            "RIGHT",
            cursor,
            cursorPoint or "LEFT",
            0,
            0
        )
    end
    return SetEngineManagedLayoutPoint(
        node,
        "LEFT",
        cursor,
        cursorPoint or "RIGHT",
        0,
        0
    )
end

local function ResolveFilteredAuraPlannedItem(cache, itemIndex)
    if itemIndex <= cache.normalCount then
        return cache.normalKinds[itemIndex] or "normal",
            cache.normalValues[itemIndex] or cache.normalFrames[itemIndex]
    end
    local specialIndex = itemIndex - cache.normalCount
    return cache.specialKinds[specialIndex],
        cache.specialValues[specialIndex]
end

local function ResolveFilteredAuraDynamicDisplay(self, kind, value)
    if kind ~= "special" and kind ~= "normal-dynamic" then return nil end
    return self.filteredAuraDynamicNodes
        and self.filteredAuraDynamicNodes[value]
end

local function ResolveFilteredAuraChainGrowth(runtime)
    if runtime.alignment == "center" then
        return runtime.rowDirection == "left" and "left" or "right"
    end
    -- Start/end are physical left/right alignment.  Grow inward from that
    -- edge; traversal order below preserves the configured row direction.
    return runtime.alignment == "end" and "left" or "right"
end

local function PrepareFilteredAuraFixedCell(
    runtime,
    frame,
    itemWidth,
    itemHeight,
    cellWidth,
    growth
)
    if not frame then return nil, false end
    local wrote = false
    local cell = frame._yhudFilteredAuraChainCarrier
    if not cell then return nil, false end
    wrote = SetLayoutSize(cell, cellWidth, itemHeight) or wrote
    wrote = SetLayoutSize(frame, itemWidth, itemHeight) or wrote
    if growth == "left" then
        wrote = SetEngineManagedLayoutPoint(
            frame,
            "RIGHT",
            cell,
            "RIGHT",
            0,
            0
        ) or wrote
    else
        wrote = SetEngineManagedLayoutPoint(
            frame,
            "LEFT",
            cell,
            "LEFT",
            0,
            0
        ) or wrote
    end
    frame._yhudPlaced = true
    return cell, wrote
end

local function PlaceFilteredAuraPlannedStaticRow(
    runtime,
    geometry,
    row,
    cache
)
    local wrote = false
    for column = 1, #row.indices do
        local itemIndex = row.indices[column]
        local _, frame = ResolveFilteredAuraPlannedItem(cache, itemIndex)
        local placement = geometry.placements[itemIndex]
        if frame and placement then
            wrote = SetLayoutSize(
                frame,
                placement.width,
                placement.height
            ) or wrote
            wrote = SetLayoutPoint(
                frame,
                placement.point,
                runtime.frame,
                placement.relativePoint,
                placement.x,
                placement.y
            ) or wrote
            frame._yhudPlaced = true
        end
    end
    return wrote
end

local function PlaceFilteredAuraPlannedDynamicRow(
    self,
    runtime,
    geometry,
    row,
    rowIndex,
    cache
)
    local wrote = false
    local itemWidth = geometry.itemWidth
    local itemHeight = geometry.itemHeight
    local columnSpacing = geometry.columnSpacing
    local cellWidth = itemWidth + columnSpacing
    local growth = ResolveFilteredAuraChainGrowth(runtime)
    local rowFrame = AcquireFilteredAuraLayoutAnchor(
        runtime,
        FILTERED_AURA_ANCHOR_SPECIAL_ROW_BASE + rowIndex
    )
    wrote = SetLayoutSize(rowFrame, geometry.width, itemHeight) or wrote
    local y = (rowIndex - 1) * (itemHeight + geometry.rowSpacing)
    if runtime.wrapDirection == "up" then
        wrote = SetLayoutPoint(
            rowFrame,
            "BOTTOMLEFT",
            runtime.frame,
            "BOTTOMLEFT",
            0,
            y
        ) or wrote
    else
        wrote = SetLayoutPoint(
            rowFrame,
            "TOPLEFT",
            runtime.frame,
            "TOPLEFT",
            0,
            -y
        ) or wrote
    end

    local origin = AcquireFilteredAuraLayoutAnchor(
        runtime,
        FILTERED_AURA_ANCHOR_SPECIAL_ORIGIN_BASE + rowIndex
    )
    wrote = SetLayoutSize(origin, 0.001, itemHeight) or wrote
    local cursor = origin
    local cursorPoint
    if runtime.alignment == "center" then
        local inset = columnSpacing / 2
        if growth == "left" then inset = -inset end
        wrote = SetLayoutPoint(
            origin,
            "CENTER",
            rowFrame,
            "CENTER",
            inset,
            0
        ) or wrote
        cursorPoint = "CENTER"

        local fixedCount = 0
        for column = 1, #row.indices do
            local kind = ResolveFilteredAuraPlannedItem(
                cache,
                row.indices[column]
            )
            if kind ~= "special" and kind ~= "normal-dynamic" then
                fixedCount = fixedCount + 1
            end
        end
        if fixedCount > 0 then
            local fixedHalf = AcquireFilteredAuraLayoutAnchor(
                runtime,
                FILTERED_AURA_ANCHOR_SPECIAL_FIXED_HALF_BASE + rowIndex
            )
            wrote = SetLayoutSize(
                fixedHalf,
                fixedCount * cellWidth / 2,
                itemHeight
            ) or wrote
            if growth == "left" then
                wrote = SetLayoutPoint(
                    fixedHalf,
                    "LEFT",
                    cursor,
                    cursorPoint,
                    0,
                    0
                ) or wrote
                cursorPoint = "RIGHT"
            else
                wrote = SetLayoutPoint(
                    fixedHalf,
                    "RIGHT",
                    cursor,
                    cursorPoint,
                    0,
                    0
                ) or wrote
                cursorPoint = "LEFT"
            end
            cursor = fixedHalf
        end
        local balanceGrowth = growth == "left" and "right" or "left"
        for column = 1, #row.indices do
            local kind, value = ResolveFilteredAuraPlannedItem(
                cache,
                row.indices[column]
            )
            local display = ResolveFilteredAuraDynamicDisplay(
                self,
                kind,
                value
            )
            if display and display.balanceNode
                and display.balanceEndNode then
                wrote = AnchorFilteredAuraFlowNode(
                    display.balanceNode,
                    cursor,
                    cursorPoint,
                    balanceGrowth
                ) or wrote
                cursor = display.balanceEndNode
                cursorPoint = "CENTER"
            end
        end
    else
        cursorPoint = runtime.alignment == "end" and "RIGHT" or "LEFT"
        wrote = SetLayoutPoint(
            origin,
            cursorPoint,
            rowFrame,
            cursorPoint,
            0,
            0
        ) or wrote
    end

    local configuredGrowth = runtime.rowDirection == "left"
        and "left" or "right"
    local reverseTraversal = growth ~= configuredGrowth
    for traversal = 1, #row.indices do
        local column = reverseTraversal
            and (#row.indices - traversal + 1) or traversal
        local itemIndex = row.indices[column]
        local kind, value = ResolveFilteredAuraPlannedItem(cache, itemIndex)
        local display = ResolveFilteredAuraDynamicDisplay(self, kind, value)
        if display and display.node and display.endNode then
            wrote = AnchorFilteredAuraFlowNode(
                display.node,
                cursor,
                cursorPoint,
                growth
            ) or wrote
            cursor = display.endNode
            cursorPoint = "CENTER"
        elseif kind ~= "special" and kind ~= "normal-dynamic" then
            local cell, cellWrote = PrepareFilteredAuraFixedCell(
                runtime,
                value,
                itemWidth,
                itemHeight,
                cellWidth,
                growth
            )
            wrote = cellWrote or wrote
            if cell then
                wrote = AnchorFilteredAuraFlowNode(
                    cell,
                    cursor,
                    cursorPoint,
                    growth
                ) or wrote
                cursor = cell
                cursorPoint = growth == "left" and "LEFT" or "RIGHT"
            end
        end
    end
    return wrote
end

-- Dynamic Aura containers expose secret geometry.  The visible chain therefore
-- advances through engine-managed endpoints instead of reading any size or
-- visibility value back into Lua.
local function RelayoutFilteredAuraSingleLine(self, runtime, groupId, cache)
    if cache.specialCount == 0 then return false end
    local itemWidth = runtime.itemWidth or DEFAULT_ICON_SIZE
    local itemHeight = runtime.itemHeight or DEFAULT_ICON_SIZE
    local columnSpacing = math.max(0, tonumber(runtime.columnSpacing) or 0)
    local cellWidth = itemWidth + columnSpacing
    local count = cache.sequenceCount
    local contentWidth = math.max(itemWidth, count * cellWidth - columnSpacing)
    local width = I.GetAutoIconRowWidth(runtime) or contentWidth
    local holderSizeChanged = SetLayoutSize(runtime.frame, width, itemHeight)
    local wrote = holderSizeChanged
    local growth = ResolveFilteredAuraChainGrowth(runtime)
    local origin = AcquireFilteredAuraLayoutAnchor(
        runtime,
        FILTERED_AURA_ANCHOR_SINGLE_ORIGIN
    )
    wrote = SetLayoutSize(origin, 0.001, itemHeight) or wrote
    local cursor = origin
    local cursorPoint
    if runtime.alignment == "center" then
        local inset = columnSpacing / 2
        if growth == "left" then inset = -inset end
        wrote = SetLayoutPoint(
            origin,
            "CENTER",
            runtime.frame,
            "CENTER",
            inset,
            0
        ) or wrote
        cursorPoint = "CENTER"
        local fixedCount = 0
        for index = 1, cache.sequenceCount do
            if cache.sequenceKinds[index] ~= "special"
                and cache.sequenceKinds[index] ~= "normal-dynamic" then
                fixedCount = fixedCount + 1
            end
        end
        if fixedCount > 0 then
            local fixedHalf = AcquireFilteredAuraLayoutAnchor(
                runtime,
                FILTERED_AURA_ANCHOR_SINGLE_FIXED_HALF
            )
            wrote = SetLayoutSize(
                fixedHalf,
                fixedCount * cellWidth / 2,
                itemHeight
            ) or wrote
            if growth == "left" then
                wrote = SetLayoutPoint(
                    fixedHalf,
                    "LEFT",
                    cursor,
                    cursorPoint,
                    0,
                    0
                ) or wrote
                cursorPoint = "RIGHT"
            else
                wrote = SetLayoutPoint(
                    fixedHalf,
                    "RIGHT",
                    cursor,
                    cursorPoint,
                    0,
                    0
                ) or wrote
                cursorPoint = "LEFT"
            end
            cursor = fixedHalf
        end
        local balanceGrowth = growth == "left" and "right" or "left"
        for index = 1, cache.sequenceCount do
            if cache.sequenceKinds[index] == "special"
                or cache.sequenceKinds[index] == "normal-dynamic" then
                local display = self.filteredAuraDynamicNodes[
                    cache.sequenceValues[index]
                ]
                if display and display.balanceNode
                    and display.balanceEndNode then
                    wrote = AnchorFilteredAuraFlowNode(
                        display.balanceNode,
                        cursor,
                        cursorPoint,
                        balanceGrowth
                    ) or wrote
                    cursor = display.balanceEndNode
                    cursorPoint = "CENTER"
                end
            end
        end

    else
        cursorPoint = runtime.alignment == "end" and "RIGHT" or "LEFT"
        wrote = SetLayoutPoint(
            origin, cursorPoint, runtime.frame, cursorPoint, 0, 0
        ) or wrote
    end

    local configuredGrowth = runtime.rowDirection == "left" and "left" or "right"
    local reverseTraversal = growth ~= configuredGrowth
    for traversal = 1, cache.sequenceCount do
        local index = reverseTraversal
            and (cache.sequenceCount - traversal + 1) or traversal
        local kind = cache.sequenceKinds[index]
        local value = cache.sequenceValues[index]
        local display = ResolveFilteredAuraDynamicDisplay(self, kind, value)
        if display and display.node and display.endNode then
            wrote = AnchorFilteredAuraFlowNode(
                display.node,
                cursor,
                cursorPoint,
                growth
            ) or wrote
            cursor = display.endNode
            cursorPoint = "CENTER"
        elseif kind ~= "special" and kind ~= "normal-dynamic" then
            local cell, cellWrote = PrepareFilteredAuraFixedCell(
                runtime,
                value,
                itemWidth,
                itemHeight,
                cellWidth,
                growth
            )
            wrote = cellWrote or wrote
            if cell then
                wrote = AnchorFilteredAuraFlowNode(
                    cell,
                    cursor,
                    cursorPoint,
                    growth
                ) or wrote
                cursor = cell
                cursorPoint = growth == "left" and "LEFT" or "RIGHT"
            end
        end
    end
    runtime.layoutEligible = count > 0
    wrote = ProjectRuntimeVisibility(self, runtime) or wrote
    RequestPixelAlignmentRefresh(self, groupId, holderSizeChanged, true)
    AddViewWrite(wrote)
    PublishImportantGroupWidth(self, groupId, contentWidth, count > 0)
    return true, wrote
end

local function RelayoutFilteredAuraSegments(self, runtime, groupId, cache)
    local specialCount = cache.specialSequenceCount
    if specialCount == 0 then return false end
    local geometryItems, specialFlags = {}, {}
    for index = 1, cache.normalCount do
        geometryItems[#geometryItems + 1] = cache.normalFrames[index] or true
        specialFlags[#specialFlags + 1] = false
    end
    for index = 1, specialCount do
        geometryItems[#geometryItems + 1] = true
        specialFlags[#specialFlags + 1] = true
    end
    local geometry = BuildGroupGeometry(
        runtime,
        geometryItems,
        #geometryItems,
        {
            segmented = true,
            specialFlags = specialFlags,
        }
    )
    runtime.presentationGeometry = geometry
    local holderSizeChanged = SetLayoutSize(
        runtime.frame,
        geometry.width,
        geometry.height
    )
    local wrote = holderSizeChanged
    local rowCount = #(geometry.rows or {})
    for rowIndex = 1, rowCount do
        local row = geometry.rows[rowIndex]
        local hasDynamic = false
        for column = 1, #row.indices do
            local kind = ResolveFilteredAuraPlannedItem(
                cache,
                row.indices[column]
            )
            if kind == "special" or kind == "normal-dynamic" then
                hasDynamic = true
                break
            end
        end
        if hasDynamic then
            wrote = PlaceFilteredAuraPlannedDynamicRow(
                self,
                runtime,
                geometry,
                row,
                rowIndex,
                cache
            ) or wrote
        else
            wrote = PlaceFilteredAuraPlannedStaticRow(
                runtime,
                geometry,
                row,
                cache
            ) or wrote
        end
    end
    runtime.layoutEligible = cache.normalCount > 0 or specialCount > 0
    wrote = ProjectRuntimeVisibility(self, runtime) or wrote
    RequestPixelAlignmentRefresh(self, groupId, holderSizeChanged, true)
    AddViewWrite(wrote)
    PublishImportantGroupWidth(
        self,
        groupId,
        geometry.contentWidth or geometry.width,
        runtime.layoutEligible
    )
    return true, wrote
end

local function RelayoutFilteredAuraDynamicGroup(self, runtime, groupId)
    if runtime.view ~= "icon" or runtime.layoutMode == "fixed" then
        return false
    end
    local strategy = runtime.filteredAuraProjectionStrategy
    local state = runtime.filteredAuraProjectionState
    local independentPure = strategy == YHUD.FILTERED_AURA_LAYOUT_ENGINE_FLOW
        and state and state.hasScopeMismatch == true
    local singleLine = strategy ==
        YHUD.FILTERED_AURA_LAYOUT_MIXED_DYNAMIC_SINGLE_LINE
    local segmented = strategy ==
        YHUD.FILTERED_AURA_LAYOUT_MIXED_SEGMENTED_OVERFLOW
    if not (singleLine or segmented or independentPure) then return false end
    local cache = CollectFilteredAuraLayout(self, runtime)
    if singleLine and cache.specialCount > 0 then
        return RelayoutFilteredAuraSingleLine(self, runtime, groupId, cache)
    end
    if segmented or independentPure then
        return RelayoutFilteredAuraSegments(self, runtime, groupId, cache)
    end
    return false
end

function View:RelayoutGroupCore(groupId, combatResourceEdge)
    local runtime = self.groups[groupId]
    if not runtime then return false end

    local filteredAuraHandled, filteredAuraWrote =
        RelayoutFilteredAuraDynamicGroup(self, runtime, groupId)
    if filteredAuraHandled then return filteredAuraWrote end

    local wrote = false
    local holderSizeChanged = false
    local frames = {}
    local frameCount = 0
    local visibleCount = 0
    local fixedLayout = runtime.layoutMode == "fixed"
    local layoutCount = fixedLayout and runtime.monitorCount or 0
    local collapsedCastCount = 0
    local usedNative = {}
    local hasNativeFrames = false
    for index = 1, runtime.monitorCount do
        local monitorId = runtime.monitorIds[index]
        local monitor = monitorId and self.desiredMonitors[monitorId]
        local nativeFrame = runtime.nativeByMonitor
            and runtime.nativeByMonitor[monitorId]
        local ownedFrame = self.byMonitor[monitorId]
        if I.IsPlayerCastCollapsed and I.IsPlayerCastCollapsed(self, monitor) then
            collapsedCastCount = collapsedCastCount + 1
        end
        if ownedFrame
            and not self:IsMonitorLayoutParticipating(
                monitor,
                nil,
                fixedLayout
            ) then
            ownedFrame._yhudLayoutParticipating = false
            self:ReleaseSlot(monitorId)
            ownedFrame = nil
            wrote = true
        elseif ownedFrame
            and monitor
            and monitor._yhudEquipmentTriggerKind == "active-timer" then
            ownedFrame._yhudLayoutParticipating = true
        end
        local visibilitySuppressed = ownedFrame
            and ownedFrame._yhudVisibilitySuppressed == true
        if visibilitySuppressed and not fixedLayout then
            ownedFrame = nil
        end
        local persistentPlaceholder = ownedFrame
            and ownedFrame._yhudNativePersistentPlaceholder == true
        if persistentPlaceholder then
            local hidden = nativeFrame ~= nil
            if ownedFrame._yhudNativePlaceholderHidden ~= hidden then
                ownedFrame._yhudNativePlaceholderHidden = hidden
                if hidden then ownedFrame:Hide() else ownedFrame:Show() end
                wrote = true
            end
        elseif ownedFrame and ownedFrame._yhudNativePlaceholderHidden == true then
            ownedFrame._yhudNativePlaceholderHidden = nil
            ownedFrame:Show()
            wrote = true
        end
        local frame = persistentPlaceholder and nativeFrame
            or ownedFrame
            or (self.filteredAuraFrames
                and self.filteredAuraFrames[monitorId])
            or nativeFrame
        if persistentPlaceholder and not frame then frame = ownedFrame end
        if nativeFrame then
            usedNative[nativeFrame] = true
        end
        if frame then
            frameCount = frameCount + 1
            local frameIndex = fixedLayout and (index - collapsedCastCount) or frameCount
            frames[frameIndex] = frame
            usedNative[frame] = true
            if frame == nativeFrame then hasNativeFrames = true end
            if not visibilitySuppressed then
                visibleCount = visibleCount + 1
            end
        end
    end
    layoutCount = layoutCount - collapsedCastCount
    for index = 1, #(runtime.nativeFrames or {}) do
        local frame = runtime.nativeFrames[index]
        if frame and not usedNative[frame] then
            frameCount = frameCount + 1
            if fixedLayout then
                layoutCount = layoutCount + 1
                frames[layoutCount] = frame
            else
                frames[frameCount] = frame
            end
            usedNative[frame] = true
            hasNativeFrames = true
            visibleCount = visibleCount + 1
        end
    end
    local count = fixedLayout and layoutCount or frameCount
    local hasNativeContent = hasNativeFrames
        or (type(runtime.filteredAuraWidth) == "number"
            and runtime.filteredAuraWidth > 0
            and type(runtime.filteredAuraHeight) == "number"
            and runtime.filteredAuraHeight > 0)
    if not hasNativeContent then
        hasNativeContent = frameCount == 0
            and type(runtime.nativeWidth) == "number"
            and runtime.nativeWidth > 0
            and type(runtime.nativeHeight) == "number"
            and runtime.nativeHeight > 0
    end

    local concentric = runtime.view == "ring"
        and (runtime.direction == "outward"
            or runtime.direction == "inward")
    if concentric then
        local geometry = BuildGroupGeometry(
            runtime,
            frames,
            count,
            { fixedLayout = fixedLayout }
        )
        if hasNativeContent then
            geometry.width = math.max(
                geometry.width or 0,
                tonumber(runtime.nativeWidth) or 0,
                tonumber(runtime.nativeHeight) or 0
            )
            geometry.height = geometry.width
        end
        local geometryWrote, geometrySizeChanged, snappedWidth =
            ApplyRuntimeGeometry(runtime, frames, geometry)
        wrote = geometryWrote or wrote
        holderSizeChanged = geometrySizeChanged or holderSizeChanged
        runtime.presentationGeometry = geometry
        runtime.layoutEligible = visibleCount > 0 or hasNativeContent
            or self.layoutEditMode or self.designMode
        local holderWrote = ProjectRuntimeVisibility(self, runtime)
        wrote = holderWrote or wrote
        RequestPixelAlignmentRefresh(
            self,
            groupId,
            holderSizeChanged,
            hasNativeContent
        )
        AddViewWrite(wrote)
        PublishImportantGroupWidth(
            self,
            groupId,
            snappedWidth > 0 and snappedWidth or geometry.width,
            visibleCount > 0 or hasNativeContent
        )
        return wrote
    end

    if runtime.view == "resource" then
        if fixedLayout then
            ClearResourcePrefixLayout(runtime, true)
            ClearResourceEdgeLayout(runtime, true)
            local result = RelayoutResourceFrames(
                self,
                runtime,
                groupId,
                frames,
                count,
                hasNativeContent,
                combatResourceEdge,
                visibleCount,
                nil
            )
            runtime.fixedResourceGeometryReady =
                frameCount == runtime.monitorCount
            return result
        end
        runtime.fixedResourceGeometryReady = false
        local prepareStartedAt = ProfileNowMS()
        local prefixCache, resourceLayoutCount = BuildResourcePrefixLayout(
            self,
            runtime,
            frames,
            visibleCount,
            hasNativeContent
        )
        if not prefixCache then
            ClearResourcePrefixLayout(runtime, true)
            resourceLayoutCount = visibleCount
        end
        local result = RelayoutResourceFrames(
            self,
            runtime,
            groupId,
            frames,
            resourceLayoutCount,
            hasNativeContent,
            combatResourceEdge,
            visibleCount,
            prefixCache
        )
        if prefixCache then
            ClearResourceEdgeLayout(runtime, true)
            AddPerformanceStat("resourcePrefixPrepared")
            AddPerformanceStat(
                "resourcePrefixPreparedSlots",
                math.max(0, resourceLayoutCount - visibleCount)
            )
            FinishPerformanceStat("resourcePrefixPrepareMS", prepareStartedAt)
        else
            local edgePrepareStartedAt = ProfileNowMS()
            if BuildResourceEdgeLayout(
                self,
                runtime,
                hasNativeContent
            ) then
                FinishPerformanceStat(
                    "resourceEdgePrepareMS",
                    edgePrepareStartedAt
                )
            end
        end
        return result
    end

    local geometry = BuildGroupGeometry(
        runtime,
        frames,
        count,
        {
            fixedLayout = fixedLayout,
            design = self.designMode or self.layoutEditMode,
        }
    )
    if count == 0 and runtime.nativeWidth and runtime.nativeHeight then
        geometry.width = runtime.nativeWidth
        geometry.height = runtime.nativeHeight
    end
    local rowWidth = I.GetAutoIconRowWidth(runtime)
    if rowWidth then
        if count == 0 then
            geometry.contentWidth = runtime.filteredAuraWidth
                or runtime.nativeWidth or geometry.contentWidth
            geometry.height = runtime.filteredAuraHeight
                or runtime.nativeHeight or geometry.height
        end
        geometry.width = rowWidth
    end
    local geometryWrote, geometrySizeChanged, snappedWidth =
        ApplyRuntimeGeometry(runtime, frames, geometry)
    wrote = geometryWrote or wrote
    holderSizeChanged = geometrySizeChanged or holderSizeChanged
    runtime.presentationGeometry = geometry
    runtime.layoutEligible = visibleCount > 0 or hasNativeContent
        or self.layoutEditMode or self.designMode
    local holderWrote = ProjectRuntimeVisibility(self, runtime)
    wrote = holderWrote or wrote
    RequestPixelAlignmentRefresh(
        self,
        groupId,
        holderSizeChanged,
        hasNativeContent
    )
    AddViewWrite(wrote)
    PublishImportantGroupWidth(
        self,
        groupId,
        geometry.contentWidth and SnapLayoutBoundary(
            runtime.frame, geometry.contentWidth, GetPixelLayoutScale(runtime.frame)
        ) or snappedWidth,
        visibleCount > 0 or hasNativeContent
    )
    return wrote
end

function View:RelayoutGroup(groupId, combatResourceEdge)
    local runtime = self.groups[groupId]
    if runtime and runtime.runtimeOwned == true then
        return self:ProjectGroupVisibility(groupId)
    end
    local trackedBuff = runtime
        and runtime.nativeCategories
        and runtime.nativeCategories.trackedBuff
    local bridge = YHUD.NativeBridge
    if not (trackedBuff
        and bridge
        and bridge.BeginDynamicGeometryLayout
        and bridge.FinishDynamicGeometryLayout) then
        return self:RelayoutGroupCore(groupId, combatResourceEdge)
    end

    bridge:BeginDynamicGeometryLayout()
    local ok, wrote = pcall(
        self.RelayoutGroupCore,
        self,
        groupId,
        combatResourceEdge
    )
    if not ok then
        if bridge.AbortDynamicGeometryLayout then
            bridge:AbortDynamicGeometryLayout()
        end
        error(wrote, 0)
    end
    bridge:FinishDynamicGeometryLayout(
        runtime.nativeByMonitor,
        runtime.nativeFrames
    )
    return wrote
end

function View:Relayout()
    local wasDeferred = self.deferPixelAlignmentRefresh == true
    self.deferPixelAlignmentRefresh = true
    for groupId in pairs(self.groups) do
        self:RelayoutGroup(groupId)
    end
    self.deferPixelAlignmentRefresh = wasDeferred
    if not wasDeferred and self.pixelAlignmentRefreshPending then
        self.pixelAlignmentRefreshPending = nil
        RefreshPixelAlignedPlacements(self)
    end
    return true
end

function View:ApplyConfig(profile, options)
    if not profile then return false end
    options = type(options) == "table" and options or nil
    local layoutBridge = YHUD.LayoutBridge
    if layoutBridge and layoutBridge.PrepareProfileTransition then
        local prepared = layoutBridge:PrepareProfileTransition(profile)
        if prepared == false then return false end
    end
    local restartDurationPreview = self.designMode
        and self.designDurationPreviewEnabled == true
    if restartDurationPreview and self.SetDesignDurationPreviewEnabled then
        self:SetDesignDurationPreviewEnabled(false)
    end
    self.profile = profile
    self.inCombat = IsInCombat()
    if RuntimeSound and RuntimeSound.Reset then RuntimeSound:Reset() end

    local previousDesired = self.desiredMonitors
    local groups = profile.groups and profile.groups.items or {}
    local groupOrder = profile.groups and profile.groups.order or {}
    local projectionContext = YHUD.BuildMonitorLayoutProjectionContext
        and YHUD:BuildMonitorLayoutProjectionContext(
            profile,
            self.preview == true
        ) or nil
    local presentationPlan = I.BeginPresentationPlan(profile, {
        preview = self.preview == true,
        projectionContext = projectionContext,
        resourceClassFile = self.resourcePreviewClassFile,
        resourceSpecID = self.resourcePreviewSpecID,
        resourceFormKey = self.resourcePreviewFormKey,
        focusedResourceId = self.resourceStylePreviewResourceId,
        focusedResourceGroupId = self.resourceStylePreviewGroupId,
    })
    if not presentationPlan then return false end
    self.layoutProjectionContext = projectionContext
    for index = 1, #groupOrder do
        local groupId = groupOrder[index]
        local group = groups[groupId]
        local groupPlan = I.FinishPresentationGroup(
            presentationPlan,
            groupId
        )
        if group and groupPlan and groupPlan.expectedView then
            local runtime = self:CreateGroupHolder(groupId, group)
            self:ConfigureGroup(
                runtime,
                profile,
                group,
                projectionContext,
                groupPlan
            )
            runtime.presentationGroupPlan = groupPlan
            runtime.monitorCount = #groupPlan.members
            runtime.hasCombatResourceVisibility =
                groupPlan.hasCombatResourceVisibility == true
            for monitorIndex = 1, runtime.monitorCount do
                local member = groupPlan.members[monitorIndex]
                runtime.monitorIds[monitorIndex] = member.physicalId
                runtime.monitorLanes[monitorIndex] = member.lane
            end
            for monitorIndex = runtime.monitorCount + 1,
                #runtime.monitorIds do
                runtime.monitorIds[monitorIndex] = nil
                runtime.monitorLanes[monitorIndex] = nil
            end
        end
    end
    local desiredMonitors = presentationPlan.desiredMonitors
    local monitorsBySource = presentationPlan.monitorsBySource
    local unavailableMonitors = presentationPlan.unavailableMonitors
    self.presentationPlan = presentationPlan
    for groupId, runtime in pairs(self.groups) do
        local group = groups[groupId]
        if runtime.runtimeOwned ~= true
            and (not group or not LAYOUT_VIEWS[group.layout]) then
            ClearResourcePrefixLayout(runtime, true)
            ClearResourceEdgeLayout(runtime, true)
            runtime.enabled = false
            runtime.monitorCount = 0
            runtime.hasCombatResourceVisibility = false
            runtime.frame:Hide()
        end
    end

    self:SyncGroupVisibility(profile)

    for monitorId in pairs(previousDesired) do
        if not desiredMonitors[monitorId] then
            self:ReleaseSlot(monitorId)
        end
    end
    local combatGlowMonitors = {}
    local combatResourceMonitors = {}
    for monitorId, monitor in pairs(desiredMonitors) do
        local compiledGlow = I.Glow and I.Glow.Compile
            and I.Glow:Compile(profile, monitor) or nil
        monitor._yhudGlowRuntime = compiledGlow
        local compiledSound = RuntimeSound
            and RuntimeSound.Compile
            and RuntimeSound:Compile(profile, monitor) or nil
        monitor._yhudSoundRuntime = compiledSound
        local entry = profile.entries
            and profile.entries[monitor.entryKey]
        monitor._yhudNativeAuraSoundManaged = compiledSound ~= nil
            and entry ~= nil
            and entry.origin == "official-cdm"
            and (entry.officialCategory == "trackedBuff"
                or entry.officialCategory == "trackedBar")
            and YHUD.IsOfficialNativeView ~= nil
            and YHUD:IsOfficialNativeView(
                entry.officialCategory,
                monitor.view
            )
            or nil
        local soundState = compiledSound and YHUD.Model
            and YHUD.Model.GetState
            and YHUD.Model:GetState(monitor.sourceKey) or nil
        if soundState and self.ObserveMonitorSound then
            -- RuntimeSound was reset at this cold boundary, so the current
            -- authoritative sample only establishes a baseline. It cannot
            -- synthesize an activation sound during load or rebuild.
            self:ObserveMonitorSound(monitor, soundState)
        end
        if compiledGlow and compiledGlow.hasCombatOnly == true then
            combatGlowMonitors[monitorId] = true
        end
        if monitor.resourceVisibilityMode == "nonzeroOrCombat" then
            combatResourceMonitors[#combatResourceMonitors + 1] = monitorId
        end
    end
    self.desiredMonitors = desiredMonitors
    self.combatGlowMonitors = combatGlowMonitors
    self.combatResourceMonitors = combatResourceMonitors
    self.monitorsBySource = monitorsBySource
    self.unavailableMonitors = unavailableMonitors

    self:ApplyGroupDisplayLayers(profile)

    if self.SyncFilteredAuraDisplays then
        self:SyncFilteredAuraDisplays(profile)
    end
    local nativeBridge = YHUD.NativeBridge
    if nativeBridge and nativeBridge.ApplyGroupVisibility then
        for groupId, runtime in pairs(self.groups) do
            if runtime and runtime.enabled == true then
                nativeBridge:ApplyGroupVisibility(groupId)
            end
        end
    end

    -- ApplyConfig is the cold configuration boundary. Existing slots must be
    -- reconfigured here as well, because a per-monitor appearance override can
    -- change without changing group geometry or reallocating the slot.
    for monitorId, slot in pairs(self.byMonitor) do
        local desired = desiredMonitors[monitorId]
        local runtime = desired and self.groups[desired.groupId]
        -- A structural move keeps the monitor id but changes the component
        -- contract. Do not apply the target view's chrome to the stale slot:
        -- RefreshAll -> AcquireSlot will release it to its original pool and
        -- configure a correctly typed slot under the target group.
        if runtime
            and slot._yhudView == runtime.view
            and slot._yhudGroupId == runtime.id then
            self:ConfigureSlot(slot, runtime, desired)
        end
    end

    if YHUD.Diagnostics then YHUD.Diagnostics:ApplyConfig(profile) end
    if options and options.refreshMode == "layout-preview"
        and self.RefreshLayoutPreview then
        self:RefreshLayoutPreview(true)
    else
        self:RefreshAll()
    end
    if self.ReconcilePlayerHelpfulFilteredAuraDisplays then
        self:ReconcilePlayerHelpfulFilteredAuraDisplays()
    end
    if restartDurationPreview
        and self.designMode
        and self.SetDesignDurationPreviewEnabled then
        self:SetDesignDurationPreviewEnabled(true)
    end
    if layoutBridge and layoutBridge.FinalizeProfileTransition then
        layoutBridge:FinalizeProfileTransition(profile)
    end
    if self.ReassertDesignProjectionLiveSuppression then
        self:ReassertDesignProjectionLiveSuppression()
    end
    return true
end

function View:ApplyResourceProjection(profile, presets, groupId)
    if not self.active or type(profile) ~= "table" then
        return false
    end
    if groupId == nil then
        local changed = false
        for _, id in ipairs(profile.groups.order or {}) do
            if profile.groups.items[id].layout == "resource" then
                changed = self:ApplyResourceProjection(profile,
                    ResourceCatalog:GetGroupPresets(profile, id), id) or changed
            end
        end
        return changed
    end
    presets = type(presets) == "table" and presets or ResourceCatalog:GetGroupPresets(profile, groupId)
    local runtime = self.groups[groupId]
    if not runtime or runtime.view ~= "resource"
        or runtime.enabled ~= true then
        return false
    end

    -- Form/spec projection is a cold structural boundary. Synchronize combat
    -- truth before newly projected nonzeroOrCombat monitors consume it.
    self.inCombat = IsInCombat()

    local presentationPlan = I.BeginPresentationPlan(profile, {
        preview = self.preview == true,
        projectionContext = self.layoutProjectionContext,
        resourcePresets = presets,
    })
    local groupPlan = presentationPlan
        and I.FinishPresentationGroup(presentationPlan, groupId) or nil
    if not groupPlan then return false end

    local previousIds = {}
    for index = 1, runtime.monitorCount do
        previousIds[index] = runtime.monitorIds[index]
    end
    for index = 1, #previousIds do
        local monitorId = previousIds[index]
        local monitor = self.desiredMonitors[monitorId]
        if monitor and monitor._yhudSynthetic == true then
            local consumers = self.monitorsBySource[monitor.sourceKey]
            if consumers then
                local writeIndex = 1
                for readIndex = 1, #consumers do
                    if consumers[readIndex] ~= monitorId then
                        consumers[writeIndex] = consumers[readIndex]
                        writeIndex = writeIndex + 1
                    end
                end
                for clearIndex = #consumers, writeIndex, -1 do
                    consumers[clearIndex] = nil
                end
                if #consumers == 0 then
                    self.monitorsBySource[monitor.sourceKey] = nil
                end
            end
            self.desiredMonitors[monitorId] = nil
            self.unavailableMonitors[monitorId] = nil
            if self.presentationPlan then
                self.presentationPlan.desiredMonitors[monitorId] = nil
                self.presentationPlan.membersById[monitorId] = nil
            end
        end
    end

    runtime.presentationGroupPlan = groupPlan
    runtime.monitorCount = #groupPlan.members
    runtime.hasCombatResourceVisibility =
        groupPlan.hasCombatResourceVisibility == true
    for index = 1, runtime.monitorCount do
        local member = groupPlan.members[index]
        local monitorId = member.physicalId
        runtime.monitorIds[index] = monitorId
        runtime.monitorLanes[index] = member.lane
        self.desiredMonitors[monitorId] = member.monitor
        local consumers = presentationPlan.monitorsBySource[member.sourceKey]
        if consumers then
            local targets = self.monitorsBySource[member.sourceKey] or {}
            self.monitorsBySource[member.sourceKey] = targets
            for consumerIndex = 1, #consumers do
                local found = false
                for targetIndex = 1, #targets do
                    if targets[targetIndex] == consumers[consumerIndex] then found = true break end
                end
                if not found then targets[#targets + 1] = consumers[consumerIndex] end
            end
        end
        if self.presentationPlan then
            self.presentationPlan.desiredMonitors[monitorId] = member.monitor
            self.presentationPlan.membersById[monitorId] = member
        end
    end
    for index = runtime.monitorCount + 1, #runtime.monitorIds do
        runtime.monitorIds[index] = nil
        runtime.monitorLanes[index] = nil
    end
    if self.presentationPlan then
        self.presentationPlan.groupPlans[groupId] = groupPlan
    end

    for index = 1, #previousIds do
        local monitorId = previousIds[index]
        if not self.desiredMonitors[monitorId] then
            self:ReleaseSlot(monitorId)
        end
    end
    local combatResourceMonitors = {}
    for monitorId, monitor in pairs(self.desiredMonitors) do
        if monitor.resourceVisibilityMode == "nonzeroOrCombat" then
            combatResourceMonitors[#combatResourceMonitors + 1] = monitorId
        end
    end
    self.combatResourceMonitors = combatResourceMonitors
    self:ApplyGroupDisplayLayers(profile)
    for index = 1, runtime.monitorCount do
        local monitorId = runtime.monitorIds[index]
        local slot = self.byMonitor[monitorId]
        if slot then
            self:ConfigureSlot(slot, runtime, self.desiredMonitors[monitorId])
        end
    end
    self:RelayoutGroup(groupId)
    if self.ReconcilePlayerHelpfulFilteredAuraDisplays then
        self:ReconcilePlayerHelpfulFilteredAuraDisplays()
    end
    return true
end

local ADDON_NAME, YUI = ...
local GUI2 = YUI.GUI2
local CoreLocale = YUI.Locale and YUI.Locale.Get and YUI.Locale:Get("Core") or {}

local function T(key, fallback)
    return CoreLocale[key] or fallback or key
end

if not YUI.Components then return end
local Components = YUI.Components
local External = YUI.API and YUI.API.External

local MinimapCollection = {}
local frame
local container
local buttons = {}
local buttonStates = setmetatable({}, { __mode = "k" })
local isCollapsed = true
local hideTimer = 0
local minimapScaleHooked = false
local hideDelay = 1.5 -- 倒计时时间
local isCountingDown = false
local forceHideTime = 0
local panelBackgroundFrame
local panelBackground
local panelVisualRect = { x = 0, y = 0, width = 0, height = 0, visible = false }
local timerBarFrame
local timerBar -- 倒计时进度条
local animGroup -- 抽屉动画组

local PANEL_FRAME_STRATA = "MEDIUM"
local PANEL_FRAME_LEVEL = 10
local PANEL_BACKGROUND_FRAME_STRATA = "LOW"
local PANEL_BACKGROUND_MIN_FRAME_LEVEL = 20
local PANEL_BACKGROUND_TRACKER_LEVEL_PADDING = 5
local PANEL_BACKGROUND_TRACKER_SCAN_DEPTH = 4
local PANEL_BUTTON_FRAME_LEVEL_OFFSET = 10
local PANEL_TIMER_FRAME_LEVEL_OFFSET = 20

-- 忽略列表
local ignoreButtons = {
    'MinimapBackdrop',
    'MinimapCompassTexture',
    'MinimapZoomIn',
    'MinimapZoomOut',
    'MiniMapVoiceChatFrame',
    'MiniMapWorldMapButton',
    'MiniMapTracking',
    'MiniMapTrackingButton',
    'MiniMapMailFrame',
    'MiniMapBattlefieldFrame',
    'MiniMapLFGFrame',
    'MinimapZoneTextButton',
    'MiniMapInstanceDifficulty',
    'GuildInstanceDifficulty',
    'QueueStatusMinimapButton',
    'GameTimeFrame',
    'TimeManagerClockButton',
    'FeedbackUIButton',
    'HelpOpenTicketButton',
    'MiniMapChallengeMode',
    'MinimapOrganisator',
    'QueueStatusButton',
    'LFGMinimapFrame',
}

local ignorePatterns = {
    "^QuestieFrame",
    "^HandyNotes",
    "^GatherMate",
    "^Gatherer",
    "^TomTom",
    "^Nauticus",
    "^WestPointer",
    "Pin$",
    "Note$",
    "Node$",
}

-- 默认配置
local defaults = {
    iconSize = 24,
    showOnMouseOver = true,
    expandMode = "hoverIcon",
    mainIconVisibility = "always",
    mainIconPosition = "bottomRight",
    panelPosition = "bottom",
    panelBackground = "none",
    panelOffset = 10,
    spacingX = 4,
    spacingY = 4,
    mainIconSize = 20,
    mainIconOffsetX = 2,
    mainIconOffsetY = 2,
}

local function IsValidOption(value, values)
    for _, item in ipairs(values) do
        if value == item then
            return true
        end
    end
    return false
end

local function ClampNumber(value, defaultValue, minValue, maxValue)
    value = tonumber(value)
    if type(value) ~= "number" then
        value = defaultValue
    end
    if type(minValue) == "number" and value < minValue then
        value = minValue
    end
    if type(maxValue) == "number" and value > maxValue then
        value = maxValue
    end
    return value
end

local function NormalizeBehaviorConfig(db)
    if type(db) ~= "table" then return defaults end

    if db._minimapCollectionBehaviorVersion ~= 1 then
        db.expandMode = db.showOnMouseOver == false and "clickIcon" or "hoverIcon"
        db.mainIconVisibility = db.mainIconVisibility or "always"
        db.mainIconPosition = db.mainIconPosition or "bottomRight"
        db.panelPosition = db.panelPosition or "bottom"
        db.panelBackground = db.panelBackground or "none"
        db.panelOffset = db.panelOffset or defaults.panelOffset
        db._minimapCollectionBehaviorVersion = 1
    end

    if not IsValidOption(db.expandMode, { "hoverIcon", "clickIcon" }) then
        db.expandMode = defaults.expandMode
    end
    if not IsValidOption(db.mainIconVisibility, { "always", "hoverHotspot" }) then
        db.mainIconVisibility = defaults.mainIconVisibility
    end
    if not IsValidOption(db.mainIconPosition, { "topLeft", "topRight", "bottomLeft", "bottomRight" }) then
        db.mainIconPosition = defaults.mainIconPosition
    end
    if not IsValidOption(db.panelPosition, { "bottom", "top", "left", "right" }) then
        db.panelPosition = defaults.panelPosition
    end
    if not IsValidOption(db.panelBackground, { "none", "black", "translucent" }) then
        db.panelBackground = defaults.panelBackground
    end
    local legacyMainIconOffset = ClampNumber(db.mainIconOffset, defaults.mainIconOffsetX, -100, 100)
    if db.mainIconOffsetX == nil then
        db.mainIconOffsetX = legacyMainIconOffset
    end
    if db.mainIconOffsetY == nil then
        db.mainIconOffsetY = legacyMainIconOffset
    end
    db.mainIconOffsetX = ClampNumber(db.mainIconOffsetX, defaults.mainIconOffsetX, -100, 100)
    db.mainIconOffsetY = ClampNumber(db.mainIconOffsetY, defaults.mainIconOffsetY, -100, 100)
    db.panelOffset = ClampNumber(db.panelOffset, defaults.panelOffset, -100, 100)

    return db
end

-- 获取配置表
local function GetDB()
    if Components and Components.EnsureConfig then
        return NormalizeBehaviorConfig(Components:EnsureConfig("MinimapCollection_Config", defaults) or defaults)
    end
    return NormalizeBehaviorConfig(defaults)
end

local function SafeRead(reader)
    if type(reader) ~= "function" then return nil end
    local ok, value = pcall(reader)
    if ok then
        return value
    end
    return nil
end

local function GetBlockingCollector(options)
    if type(External) ~= "table" or type(External.ResolveCapability) ~= "function" then return nil, "unknown" end
    local ok, snapshot = pcall(External.ResolveCapability, External, "ui.minimap.collector", options)
    if not ok or type(snapshot) ~= "table" then return nil, "unknown" end
    if snapshot.status == "active" then return snapshot.controller, "active" end
    if snapshot.status == "unknown" then return nil, "unknown" end
    return nil, "inactive"
end

local function IsBlockedByExternalCollector(options)
    local _, status = GetBlockingCollector(options)
    return status == "active" or status == "unknown"
end

local function GetButtonState(btn, create)
    if not btn then return nil end

    local state = buttonStates[btn]
    if not state and create then
        state = {}
        buttonStates[btn] = state
    end
    return state
end

local function ClearButtonStateIfEmpty(btn, state)
    state = state or GetButtonState(btn)
    if state and state.lock == nil and state.layout == nil then
        buttonStates[btn] = nil
    end
end

-- 锁定按钮防止原生插件重置位置
local lockedButtonMethods = {
    "SetPoint",
    "SetParent",
    "SetSize",
    "SetFrameLevel",
    "SetFrameStrata",
    "ClearAllPoints",
}
local lockedButtonNoop = function() end
local internalButtonMethodPrefix = "__yui_minimapCollection_"
local SetPanelPoint
local RestoreLandingPageMinimapButton

local function GetInternalButtonMethodKey(method)
    return internalButtonMethodPrefix .. method
end

local function GetSavedButtonMethod(btn, method)
    if not btn or type(method) ~= "string" then return nil end

    local internalMethodKey = GetInternalButtonMethodKey(method)
    local internalMethod = rawget(btn, internalMethodKey)
    if type(internalMethod) == "function" then
        return internalMethod
    end

    local state = GetButtonState(btn)
    local lock = state and state.lock
    if type(lock) == "table" and type(lock.methods) == "table" and type(lock.methods[method]) == "function" then
        return lock.methods[method]
    end

    local current = btn[method]
    if type(current) == "function" and current ~= lockedButtonNoop then
        return current
    end

    return nil
end

local function InternalizeButtonMethod(btn, method)
    if not btn or type(method) ~= "string" then return nil end

    local internalMethodKey = GetInternalButtonMethodKey(method)
    local internalMethod = rawget(btn, internalMethodKey)
    if type(internalMethod) == "function" then
        return internalMethod
    end

    local methodFunc = btn[method]
    if type(methodFunc) ~= "function" or methodFunc == lockedButtonNoop then
        return nil
    end

    btn[internalMethodKey] = methodFunc
    return methodFunc
end

local function EnsureButtonLockMetadata(btn)
    if not btn then return nil end

    local state = GetButtonState(btn)
    local lock = state and state.lock
    if type(lock) == "table" and type(lock.methods) == "table" and type(lock.restore) == "table" then
        for _, method in ipairs(lockedButtonMethods) do
            if type(lock.methods[method]) == "function" and type(rawget(btn, GetInternalButtonMethodKey(method))) ~= "function" then
                btn[GetInternalButtonMethodKey(method)] = lock.methods[method]
            end
        end
        return lock
    end

    lock = { restore = {}, methods = {} }
    for _, method in ipairs(lockedButtonMethods) do
        lock.restore[method] = rawget(btn, method)
        lock.methods[method] = InternalizeButtonMethod(btn, method)
    end
    state = GetButtonState(btn, true)
    state.lock = lock
    return lock
end

local function CallButtonMethod(btn, method, ...)
    local func = GetSavedButtonMethod(btn, method)
    if type(func) ~= "function" then return nil end

    local ok, result = pcall(func, btn, ...)
    if ok then
        return result
    end
    return nil
end

local function LockButton(btn)
    if not EnsureButtonLockMetadata(btn) then return end
    btn.SetPoint = lockedButtonNoop
    btn.SetParent = lockedButtonNoop
    btn.SetSize = lockedButtonNoop
    btn.SetFrameLevel = lockedButtonNoop
    btn.SetFrameStrata = lockedButtonNoop
    btn.ClearAllPoints = lockedButtonNoop
end

local function UnlockButton(btn)
    local state = GetButtonState(btn)
    local lock = state and state.lock
    if type(lock) ~= "table" then return end
    for _, method in ipairs(lockedButtonMethods) do
        btn[method] = type(lock.restore) == "table" and lock.restore[method] or nil
        btn[GetInternalButtonMethodKey(method)] = nil
    end
    state.lock = nil
    ClearButtonStateIfEmpty(btn, state)
end

-- 更新布局
local function GetEffectiveScaleSafe(frameObject)
    if frameObject and frameObject.GetEffectiveScale then
        local scale = SafeRead(function()
            return frameObject:GetEffectiveScale()
        end)
        if type(scale) == "number" and scale > 0 then
            return scale
        end
    end
    return nil
end

local function GetMinimapVisualScaleRatio()
    local minimapScale = GetEffectiveScaleSafe(Minimap) or 1
    local uiScale = GetEffectiveScaleSafe(UIParent) or 1
    local ratio = minimapScale / uiScale

    if type(ratio) ~= "number" or ratio <= 0 then
        return 1
    end

    return ratio
end

local function GetEffectiveMinimapPanelWidth()
    local baseWidth = 140
    if Minimap and Minimap.GetWidth then
        local width = Minimap:GetWidth()
        if type(width) == "number" and width > 0 then
            baseWidth = width
        end
    end

    local minimapScale = GetEffectiveScaleSafe(Minimap) or 1
    local panelScale = GetEffectiveScaleSafe(container) or GetEffectiveScaleSafe(UIParent) or 1
    local panelWidth = baseWidth * minimapScale / panelScale

    if type(panelWidth) ~= "number" or panelWidth <= 0 then
        panelWidth = baseWidth
    end
    if panelWidth < 40 then
        panelWidth = baseWidth > 40 and baseWidth or 140
    end

    return panelWidth
end

local function GetEffectiveMinimapPanelHeight()
    local baseHeight = 140
    if Minimap and Minimap.GetHeight then
        local height = Minimap:GetHeight()
        if type(height) == "number" and height > 0 then
            baseHeight = height
        end
    end

    local minimapScale = GetEffectiveScaleSafe(Minimap) or 1
    local panelScale = GetEffectiveScaleSafe(container) or GetEffectiveScaleSafe(UIParent) or 1
    local panelHeight = baseHeight * minimapScale / panelScale

    if type(panelHeight) ~= "number" or panelHeight <= 0 then
        panelHeight = baseHeight
    end
    if panelHeight < 40 then
        panelHeight = baseHeight > 40 and baseHeight or 140
    end

    return panelHeight
end

local PANEL_VISUAL_CONTENT_PADDING = 2
local PANEL_VISUAL_BORDER_PADDING = 1
local PANEL_VISUAL_OUTER_PADDING = PANEL_VISUAL_CONTENT_PADDING + PANEL_VISUAL_BORDER_PADDING

local function SetPanelVisualRect(x, y, width, height)
    if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then
        panelVisualRect.visible = false
        panelVisualRect.x = 0
        panelVisualRect.y = 0
        panelVisualRect.width = 0
        panelVisualRect.height = 0
        return
    end

    panelVisualRect.visible = true
    panelVisualRect.x = x - PANEL_VISUAL_OUTER_PADDING
    panelVisualRect.y = y + PANEL_VISUAL_OUTER_PADDING
    panelVisualRect.width = width + PANEL_VISUAL_OUTER_PADDING * 2
    panelVisualRect.height = height + PANEL_VISUAL_OUTER_PADDING * 2
end

local backgroundTrackerFrameNames = {
    "ObjectiveTrackerFrame",
    "WatchFrame",
    "WatchFrameLines",
    "UIParentRightManagedFrameContainer",
}

local function GetMaxLowFrameLevel(frameObject, depth, maxLevel)
    if not frameObject or depth > PANEL_BACKGROUND_TRACKER_SCAN_DEPTH then return maxLevel end

    SafeRead(function()
        local strata = frameObject.GetFrameStrata and frameObject:GetFrameStrata()
        if (strata == nil or strata == "LOW" or strata == "PARENT") and frameObject.GetFrameLevel then
            local level = frameObject:GetFrameLevel()
            if type(level) == "number" and level > maxLevel then
                maxLevel = level
            end
        end

        if frameObject.GetChildren then
            local children = { frameObject:GetChildren() }
            for _, child in ipairs(children) do
                maxLevel = GetMaxLowFrameLevel(child, depth + 1, maxLevel)
            end
        end
    end)

    return maxLevel
end

local function GetPanelBackgroundFrameLevel()
    local maxLevel = PANEL_BACKGROUND_MIN_FRAME_LEVEL

    for _, name in ipairs(backgroundTrackerFrameNames) do
        maxLevel = GetMaxLowFrameLevel(_G[name], 1, maxLevel)
    end

    return maxLevel + PANEL_BACKGROUND_TRACKER_LEVEL_PADDING
end

local function ApplyPanelBackgroundLayer()
    if not panelBackgroundFrame then return end

    SafeRead(function()
        if panelBackgroundFrame.SetFrameStrata then
            panelBackgroundFrame:SetFrameStrata(PANEL_BACKGROUND_FRAME_STRATA)
        end
        if panelBackgroundFrame.SetFrameLevel then
            panelBackgroundFrame:SetFrameLevel(GetPanelBackgroundFrameLevel())
        end
    end)
end

local function UpdatePanelBackground()
    if not panelBackgroundFrame or not panelBackground then return end

    local mode = GetDB().panelBackground or "none"
    if mode == "none" or not panelVisualRect.visible then
        panelBackgroundFrame:Hide()
        return
    end

    local alpha = mode == "black" and 1 or 0.6
    panelBackgroundFrame:ClearAllPoints()
    panelBackgroundFrame:SetPoint("TOPLEFT", container, "TOPLEFT", panelVisualRect.x, panelVisualRect.y)
    panelBackgroundFrame:SetSize(panelVisualRect.width, panelVisualRect.height)
    ApplyPanelBackgroundLayer()
    panelBackground:SetVertexColor(0, 0, 0, alpha)
    panelBackgroundFrame:Show()
end

local function RaiseCapturedButton(btn)
    if not btn or not container then return end

    SafeRead(function()
        if container.GetFrameStrata then
            CallButtonMethod(btn, "SetFrameStrata", container:GetFrameStrata())
        end
        if container.GetFrameLevel then
            CallButtonMethod(btn, "SetFrameLevel", math.max((container:GetFrameLevel() or PANEL_FRAME_LEVEL) + PANEL_BUTTON_FRAME_LEVEL_OFFSET, 20))
        end
    end)
end

local function UpdateLayout()
    if not container then return end
    local db = GetDB()
    local size = db.iconSize or 24
    local spacingX = db.spacingX or 4
    local spacingY = db.spacingY or 4
    local padding = 6
    local position = db.panelPosition or "bottom"

    if position == "left" or position == "right" then
        local panelHeight = GetEffectiveMinimapPanelHeight()
        local timerReserve = 4
        local maxRows = math.floor((panelHeight - padding * 2 - timerReserve + spacingY) / (size + spacingY))
        if maxRows < 1 then maxRows = 1 end

        local activeButtons = {}
        for btn in pairs(buttons) do
            if btn:IsShown() then
                table.insert(activeButtons, btn)
            end
        end
        table.sort(activeButtons, function(a, b)
            local nameA = a:GetName() or tostring(a)
            local nameB = b:GetName() or tostring(b)
            return nameA < nameB
        end)

        local count = #activeButtons
        local totalCols = math.ceil(count / maxRows)
        if totalCols < 1 then totalCols = 0 end
        local usedRows = math.min(count, maxRows)
        local iconAreaWidth = totalCols * size + (totalCols > 0 and (totalCols - 1) * spacingX or 0)
        local iconAreaHeight = usedRows * size + (usedRows > 0 and (usedRows - 1) * spacingY or 0)

        local containerWidth = padding * 2 + totalCols * size + (totalCols > 0 and (totalCols - 1) * spacingX or 0)
        if count == 0 then containerWidth = 14 end
        local startY = count > 0 and math.max((panelHeight - iconAreaHeight) / 2, padding) or padding
        local iconAreaX = position == "left" and (containerWidth - padding - iconAreaWidth) or padding
        local iconAreaY = -startY

        for index, btn in ipairs(activeButtons) do
            CallButtonMethod(btn, "ClearAllPoints")
            CallButtonMethod(btn, "SetSize", size, size)
            RaiseCapturedButton(btn)

            local row = (index - 1) % maxRows
            local col = math.floor((index - 1) / maxRows)
            local x
            if position == "left" then
                x = containerWidth - padding - size - col * (size + spacingX)
            else
                x = padding + col * (size + spacingX)
            end
            local y = -(startY + row * (size + spacingY))

            CallButtonMethod(btn, "SetPoint", "TOPLEFT", container, "TOPLEFT", x, y)
        end

        container:SetSize(containerWidth, panelHeight)
        SetPanelVisualRect(iconAreaX, iconAreaY, count > 0 and iconAreaWidth or 0, count > 0 and iconAreaHeight or 0)
        UpdatePanelBackground()
        if container:IsShown() and SetPanelPoint then
            SetPanelPoint()
        end

        if timerBar then
            timerBar:SetWidth(panelVisualRect.visible and panelVisualRect.width or math.max(containerWidth - padding * 2, 1))
        end

        return panelHeight
    end
    
    local panelWidth = GetEffectiveMinimapPanelWidth()
    local maxCols = math.floor((panelWidth - padding * 2 + spacingX) / (size + spacingX))
    if maxCols < 1 then maxCols = 1 end
    
    local activeButtons = {}
    -- 按名称排序保证稳定
    for btn in pairs(buttons) do
        table.insert(activeButtons, btn)
    end
    table.sort(activeButtons, function(a, b)
        local nameA = a:GetName() or tostring(a)
        local nameB = b:GetName() or tostring(b)
        return nameA < nameB
    end)
    
    local col, row = 0, 0
    local count = 0
    local shownCount = 0
    for _, btn in ipairs(activeButtons) do
        if btn:IsShown() then
            shownCount = shownCount + 1
        end
    end
    local usedCols = math.min(shownCount, maxCols)
    local iconAreaWidth = usedCols * size + (usedCols > 0 and (usedCols - 1) * spacingX or 0)
    local startX = shownCount > 0 and math.max((panelWidth - iconAreaWidth) / 2, padding) or padding
    
    for _, btn in ipairs(activeButtons) do
        if btn:IsShown() then
            -- 解除锁定以设置位置
            local meta = getmetatable(btn)
            CallButtonMethod(btn, "ClearAllPoints")
            CallButtonMethod(btn, "SetSize", size, size)
            RaiseCapturedButton(btn)
            
            local x = startX + col * (size + spacingX)
            local y = -(padding + row * (size + spacingY))
            
            CallButtonMethod(btn, "SetPoint", "TOPLEFT", container, "TOPLEFT", x, y)
            
            col = col + 1
            if col >= maxCols then
                col = 0
                row = row + 1
            end
            count = count + 1
        end
    end
    
    local totalRows = row + (col > 0 and 1 or 0)
    local iconAreaHeight = totalRows * size + (totalRows > 0 and (totalRows - 1) * spacingY or 0)
    -- 为底部进度条预留 4px 空间
    local containerHeight = padding * 2 + totalRows * size + (totalRows > 0 and (totalRows - 1) * spacingY or 0) + 4
    if count == 0 then containerHeight = 14 end
    
    container:SetSize(panelWidth, containerHeight)
    SetPanelVisualRect(startX, -padding, count > 0 and iconAreaWidth or 0, count > 0 and iconAreaHeight or 0)
    UpdatePanelBackground()
    if container:IsShown() and SetPanelPoint then
        SetPanelPoint()
    end
    
    -- 更新进度条宽度
    if timerBar then
        timerBar:SetWidth(panelVisualRect.visible and panelVisualRect.width or (panelWidth - padding * 2))
    end
    
    return containerHeight
end

local function SetBorderVisibility(btn, visible)
    local borders = btn and btn.gui2Borders
    if type(borders) ~= "table" then return end
    if borders.top then borders.top:SetShown(visible) end
    if borders.bottom then borders.bottom:SetShown(visible) end
    if borders.left then borders.left:SetShown(visible) end
    if borders.right then borders.right:SetShown(visible) end
end

local function SaveButtonLayout(btn, parent)
    local state = GetButtonState(btn, true)
    if state.layout then return end

    local layout = { parent = parent, points = {} }
    layout.frameLevel = SafeRead(function()
        return btn.GetFrameLevel and btn:GetFrameLevel()
    end)
    layout.frameStrata = SafeRead(function()
        return btn.GetFrameStrata and btn:GetFrameStrata()
    end)
    layout.width = SafeRead(function()
        return btn.GetWidth and btn:GetWidth()
    end)
    layout.height = SafeRead(function()
        return btn.GetHeight and btn:GetHeight()
    end)
    if btn.GetNumPoints and btn.GetPoint then
        local numPoints = btn:GetNumPoints() or 0
        for i = 1, numPoints do
            local point, relativeTo, relativePoint, xOfs, yOfs = btn:GetPoint(i)
            layout.points[i] = {
                point = point,
                relativeTo = relativeTo,
                relativePoint = relativePoint,
                xOfs = xOfs,
                yOfs = yOfs,
            }
        end
    end
    state.layout = layout
end

local function RestoreButtonLayout(btn)
    local state = GetButtonState(btn)
    local layout = state and state.layout
    if type(layout) ~= "table" then return end

    local parent = layout.parent
    if not parent or parent == container then
        parent = Minimap
    end

    btn:SetParent(parent)
    SafeRead(function()
        if layout.frameStrata and btn.SetFrameStrata then
            btn:SetFrameStrata(layout.frameStrata)
        end
        if layout.frameLevel and btn.SetFrameLevel then
            btn:SetFrameLevel(layout.frameLevel)
        end
        if layout.width and layout.height and btn.SetSize then
            btn:SetSize(layout.width, layout.height)
        end
    end)
    btn:ClearAllPoints()

    local restored = false
    if type(layout.points) == "table" then
        for _, point in ipairs(layout.points) do
            if point and point.point then
                btn:SetPoint(point.point, point.relativeTo, point.relativePoint, point.xOfs, point.yOfs)
                restored = true
            end
        end
    end

    if not restored then
        btn:SetPoint("CENTER", parent, "CENTER", 0, 0)
    end

    state.layout = nil
    ClearButtonStateIfEmpty(btn, state)
end

local StopButtonScan

local function ReleaseCapturedButtons()
    if StopButtonScan then StopButtonScan() end

    if InCombatLockdown and InCombatLockdown() then return false end

    local btn = next(buttons)
    while btn do
        UnlockButton(btn)
        RestoreLandingPageMinimapButton(btn)
        if btn.yui_bg then
            btn.yui_bg:Hide()
        end
        SetBorderVisibility(btn, false)
        SafeRead(function()
            RestoreButtonLayout(btn)
        end)
        buttons[btn] = nil
        btn = next(buttons)
    end

    return true
end

local RefreshConflictState
local conflictWatcher
local conflictWatcherWorldHandle
local hideBlizzardAddonCompartment = false
local addonCompartmentHooked = false

local function GetAddonCompartmentFrame()
    return SafeRead(function()
        return _G.AddonCompartmentFrame
    end)
end

local function HideBlizzardAddonCompartment()
    hideBlizzardAddonCompartment = true

    local addonCompartment = GetAddonCompartmentFrame()
    if not addonCompartment then return end

    if not addonCompartmentHooked and addonCompartment.HookScript then
        addonCompartment:HookScript("OnShow", function(self)
            if hideBlizzardAddonCompartment then
                self:Hide()
            end
        end)
        addonCompartmentHooked = true
    end

    if addonCompartment.Hide then
        addonCompartment:Hide()
    end
end

local function RestoreBlizzardAddonCompartment()
    hideBlizzardAddonCompartment = false

    local addonCompartment = GetAddonCompartmentFrame()
    if not addonCompartment then return end

    SafeRead(function()
        if type(addonCompartment.UpdateDisplay) == "function" then
            addonCompartment:UpdateDisplay()
        elseif addonCompartment.Show then
            addonCompartment:Show()
        end
    end)
end

local function EnsureConflictWatcher()
    if conflictWatcher or not CreateFrame then return end
    conflictWatcher = CreateFrame("Frame")
    conflictWatcher:RegisterEvent("ADDON_LOADED")
    conflictWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    conflictWatcher:SetScript("OnEvent", function(_, event)
        if RefreshConflictState(event == "ADDON_LOADED" and { force = true } or nil) then return end
        if hideBlizzardAddonCompartment then
            HideBlizzardAddonCompartment()
        end
    end)
    if YUI.Event and not conflictWatcherWorldHandle then
        conflictWatcherWorldHandle = YUI.Event:On("YUI_WORLD_READY", function()
            if RefreshConflictState() then return end
            if hideBlizzardAddonCompartment then
                HideBlizzardAddonCompartment()
            end
        end, nil, { priority = -1000 })
    end
end

local function DeactivateForConflict()
    if StopButtonScan then StopButtonScan() end

    isCollapsed = true
    hideTimer = 0
    isCountingDown = false
    forceHideTime = 0

    if animGroup then
        animGroup:Stop()
    end
    if timerBar then
        timerBar:Hide()
    end
    if container then
        container:Hide()
    end
    if frame then
        frame:Hide()
    end
    RestoreBlizzardAddonCompartment()
end

RefreshConflictState = function(options)
    local controller, status = GetBlockingCollector(options)
    if status ~= "active" and status ~= "unknown" then
        if YUI.Yield then YUI.Yield:Clear("minimap_collection") end
        return false
    end
    ReleaseCapturedButtons()
    DeactivateForConflict()
    if status == "active" and YUI.Yield then
        local enabled = YUI.Components and YUI.Components.IsEnabled
            and YUI.Components:IsEnabled("MinimapCollection")
        YUI.Yield:Set("minimap_collection", controller, {
            status = status,
            enabled = enabled == true,
        })
    elseif YUI.Yield then
        YUI.Yield:Clear("minimap_collection")
    end
    return true
end

-- 抓取与美化按钮
-- 预分配表以减少 GC 压力
local cachedMinimapChildren = {}
local cachedMinimapBackdropChildren = {}
local cachedRegions = {}
local IsHoverExpandMode

-- 需要追踪图标材质动态更新的插件白名单
local trackHooks = {
    ["LibDBIcon10_BugSack"] = true,
    ["BugSack"] = true,
}

local function IsNarcissusMinimapButton(object, name)
    if name == "Narci_MinimapButton" then
        return true
    end

    return SafeRead(function()
        local background = object and object.Background
        if not background or not background.GetTexture then return false end
        local texture = background:GetTexture()
        if type(texture) ~= "string" then return false end
        return string.find(string.lower(texture), "interface\\addons\\narcissus\\art\\minimap\\logo%-") ~= nil
    end) == true
end

local function HideNarcissusDecorations(object)
    SafeRead(function()
        if object.Background then
            object.Background:SetScale(1)
        end
        if object.Color then
            object.Color:SetAlpha(0)
            object.Color:Hide()
        end
        if object.Bling then
            object.Bling:SetAlpha(0)
            object.Bling:Hide()
            if object.Bling.animScale then
                object.Bling.animScale:Stop()
            end
        end
    end)
end

local function StyleNarcissusMinimapButton(object)
    SafeRead(function()
        local background = object.Background
        if background then
            background:ClearAllPoints()
            background:SetAllPoints(object)
            background:SetScale(1)
            background:Show()
        end
        HideNarcissusDecorations(object)
    end)

    if not object.yui_narcissus_background_hooked and type(hooksecurefunc) == "function" and object.SetBackground then
        SafeRead(function()
            hooksecurefunc(object, "SetBackground", function()
                StyleNarcissusMinimapButton(object)
            end)
            object.yui_narcissus_background_hooked = true
        end)
    end
end

local landingPageMinimapButtonNames = {
    ExpansionLandingPageMinimapButton = true,
    GarrisonLandingPageMinimapButton = true,
}

local landingPageDecorationKeys = {
    "LoopingGlow",
    "CircleGlow",
    "SoftButtonGlow",
    "SideToastGlow",
    "AlertBG",
    "AlertText",
}

local landingPageAnimationKeys = {
    "MinimapLoopPulseAnim",
    "MinimapPulseAnim",
    "MinimapAlertAnim",
}

local function IsLandingPageMinimapButton(object, name)
    if name and landingPageMinimapButtonNames[name] then
        return true
    end

    return object ~= nil and (
        object == _G.ExpansionLandingPageMinimapButton or
        object == _G.GarrisonLandingPageMinimapButton
    )
end

local function SaveLandingPageDecorationState(object, region)
    if not object or not region then return end
    local state = object.yui_landingPageDecorationState
    if type(state) ~= "table" then
        state = {}
        object.yui_landingPageDecorationState = state
    end
    if state[region] then return end

    state[region] = {
        alpha = SafeRead(function()
            return region.GetAlpha and region:GetAlpha()
        end),
        shown = SafeRead(function()
            return region.IsShown and region:IsShown()
        end),
    }
end

local function HideLandingPageDecoration(object, region)
    if not region then return end
    SaveLandingPageDecorationState(object, region)
    SafeRead(function()
        if region.SetAlpha then region:SetAlpha(0) end
        if region.Hide then region:Hide() end
    end)
end

local function RestoreLandingPageDecorations(object)
    local state = object and object.yui_landingPageDecorationState
    if type(state) ~= "table" then return end

    for region, info in pairs(state) do
        SafeRead(function()
            if region.SetAlpha and type(info.alpha) == "number" then
                region:SetAlpha(info.alpha)
            end
            if region.Show and info.shown == true then
                region:Show()
            elseif region.Hide and info.shown == false then
                region:Hide()
            end
        end)
    end
    object.yui_landingPageDecorationState = nil
end

local function FitLandingPageIconTexture(texture, owner)
    if not texture or not owner then return end
    SafeRead(function()
        if texture.ClearAllPoints then texture:ClearAllPoints() end
        if texture.SetAllPoints then texture:SetAllPoints(owner) end
        if texture.SetTexCoord then texture:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end)
end

local function StopLandingPageAnimations(object)
    for _, key in ipairs(landingPageAnimationKeys) do
        local anim = object and object[key]
        if anim and anim.Stop then
            SafeRead(function()
                anim:Stop()
            end)
        end
    end
end

local function StyleLandingPageMinimapButton(object)
    if not object or not object.yui_landingPageCaptured then return end

    StopLandingPageAnimations(object)

    SafeRead(function()
        if object.GetNormalTexture then
            FitLandingPageIconTexture(object:GetNormalTexture(), object)
        end
        if object.GetPushedTexture then
            FitLandingPageIconTexture(object:GetPushedTexture(), object)
        end
        if object.GetHighlightTexture then
            FitLandingPageIconTexture(object:GetHighlightTexture(), object)
        end
    end)

    for _, key in ipairs(landingPageDecorationKeys) do
        HideLandingPageDecoration(object, object[key])
    end
end

local function HookLandingPageMinimapButton(object)
    if not object or object.yui_landingPageHooked then return end

    if type(hooksecurefunc) == "function" then
        for _, method in ipairs({
            "SetLandingPageIconFromAtlases",
            "UpdateIcon",
            "TriggerPulseLock",
            "TriggerAlert",
            "HidePulse",
            "ClearPulses",
        }) do
            if type(object[method]) == "function" then
                SafeRead(function()
                    hooksecurefunc(object, method, function()
                        StyleLandingPageMinimapButton(object)
                    end)
                end)
            end
        end
    end

    for _, key in ipairs(landingPageAnimationKeys) do
        local anim = object[key]
        if anim and anim.HookScript then
            SafeRead(function()
                anim:HookScript("OnPlay", function()
                    StyleLandingPageMinimapButton(object)
                end)
            end)
        end
    end

    object.yui_landingPageHooked = true
end

RestoreLandingPageMinimapButton = function(object)
    if not IsLandingPageMinimapButton(object, object and object.GetName and object:GetName()) then return end

    object.yui_landingPageCaptured = nil
    RestoreLandingPageDecorations(object)

    SafeRead(function()
        if type(object.RefreshButton) == "function" then
            object:RefreshButton(true)
        elseif type(object.UpdateIcon) == "function" then
            object:UpdateIcon()
        end
    end)
end

local function ProcessButton(object)
    if not container or IsBlockedByExternalCollector() then return false end
    if not object or type(object) ~= 'table' or not object.IsObjectType or not object:IsObjectType('Button') then return false end
    
    local name = object:GetName()
    
    if buttons[object] then return false end
    if object == frame then return false end -- 自己
    
    if name then
        for _, ignore in ipairs(ignoreButtons) do
            if name == ignore then return false end
        end
        for _, pattern in ipairs(ignorePatterns) do
            if name:find(pattern) then return false end
        end
    end
    
    local isMinimapButton = false
    local parent = object:GetParent()
    
    if parent == Minimap or parent == MinimapBackdrop then
        isMinimapButton = true
    elseif name and (name:find('Minimap') or name:find('MiniMap') or name:find('LibDBIcon')) then
        isMinimapButton = true
    end
    
    if not isMinimapButton then return false end
    EnsureButtonLockMetadata(object)
    SaveButtonLayout(object, parent)
    CallButtonMethod(object, "SetParent", container)
    
    -- Move into the collection container through the saved native method.
    RaiseCapturedButton(object)
    
    local isNarcissusButton = IsNarcissusMinimapButton(object, name)
    local isLandingPageButton = IsLandingPageMinimapButton(object, name)
    if isNarcissusButton then
        StyleNarcissusMinimapButton(object)
    elseif isLandingPageButton then
        object.yui_landingPageCaptured = true
        HookLandingPageMinimapButton(object)
        StyleLandingPageMinimapButton(object)
    else
    wipe(cachedRegions)
    local regions = {object:GetRegions()}
    for i, r in ipairs(regions) do
        cachedRegions[i] = r
    end
    
    for _, region in ipairs(cachedRegions) do
        if region:IsObjectType('Texture') then
            local texture = region:GetTexture()
            
            local isBorderOrBg = false
            if type(texture) == "string" then
                local lowerTex = string.lower(texture)

                -- 隐藏特定路径的材质（如原生圆形遮罩、边框等）
                if string.find(lowerTex, "interface\\characterframe") or 
                    string.find(lowerTex, "interface\\minimap") or
                    string.find(lowerTex, "border") or 
                    string.find(lowerTex, "background") or 
                    string.find(lowerTex, "alphamask") then
                    isBorderOrBg = true
                end
            elseif type(texture) == "number" then
                -- 常见的原生圆形遮罩或边框材质 ID
                if texture == 136430 or texture == 136467 or texture == 136477 then
                    isBorderOrBg = true
                end
            end
            
            if isBorderOrBg then
                region:SetTexture(nil)
                region:Hide()
            elseif texture then
                -- 保留的应该就是图标本身，铺满按钮并裁剪边缘
                region:ClearAllPoints()
                region:SetAllPoints()
                region:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                -- 修复白名单插件（如BugSack）动态更换材质导致样式丢失的问题
                -- if name and trackHooks[name] and not region.yui_hooked_texture then
                --     hooksecurefunc(region, "SetTexture", function(self)
                --         self:ClearAllPoints()
                --         self:SetAllPoints()
                --         self:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                --     end)
                --     region.yui_hooked_texture = true
                -- end
            end
        end
    end
    
    -- 为按钮添加极简 YUI 边框
    end
    GUI2:CreateBorder(object, "color.border.default")
    
    -- 为按钮底层添加一个黑底，防止非方形图标透出背景
    if not object.yui_bg then
        object.yui_bg = GUI2:CreateTexture(object, { layer = "BACKGROUND", texture = "Interface\\Buttons\\WHITE8x8" })
        object.yui_bg:SetAllPoints()
        object.yui_bg:SetVertexColor(0, 0, 0, 0.9)
        object.yui_bg:SetDrawLayer("BACKGROUND", -1)
    else
        object.yui_bg:Show()
    end
    SetBorderVisibility(object, true)
    
    -- 添加悬停高亮效果 (修改边框颜色)
    if not object.yui_hooked_hover then
        if object:HasScript("OnEnter") then
            object:HookScript("OnEnter", function()
                GUI2:SetBorderColor(object, "color.border.accent")
                if isNarcissusButton then
                    HideNarcissusDecorations(object)
                elseif isLandingPageButton then
                    StyleLandingPageMinimapButton(object)
                end
            end)
        else
            object:SetScript("OnEnter", function()
                GUI2:SetBorderColor(object, "color.border.accent")
                if isNarcissusButton then
                    HideNarcissusDecorations(object)
                elseif isLandingPageButton then
                    StyleLandingPageMinimapButton(object)
                end
            end)
        end
        
        if object:HasScript("OnLeave") then
            object:HookScript("OnLeave", function()
                GUI2:SetBorderColor(object, "color.border.default")
                if isNarcissusButton then
                    HideNarcissusDecorations(object)
                elseif isLandingPageButton then
                    StyleLandingPageMinimapButton(object)
                end
            end)
        else
            object:SetScript("OnLeave", function()
                GUI2:SetBorderColor(object, "color.border.default")
                if isNarcissusButton then
                    HideNarcissusDecorations(object)
                elseif isLandingPageButton then
                    StyleLandingPageMinimapButton(object)
                end
            end)
        end
        object.yui_hooked_hover = true
    end
    
    -- 移除原生拖拽
    if object.GetScript and object:GetScript("OnDragStart") then
        object:SetScript('OnDragStart', nil)
        object:SetScript('OnDragStop', nil)
    end
    
    -- Hook 点击，强制 3 秒后隐藏
    if not object.yui_hooked_click and object:HasScript("OnClick") then
        object:HookScript("OnClick", function()
            if IsHoverExpandMode() then
                forceHideTime = GetTime() + hideDelay
            end
        end)
        object.yui_hooked_click = true
    end
    
    -- 锁定按钮位置
    LockButton(object)
    RaiseCapturedButton(object)

    if not object.yui_hooked_show then
        if object:HasScript("OnShow") then object:HookScript("OnShow", function() UpdateLayout() end) end
        if object:HasScript("OnHide") then object:HookScript("OnHide", function() UpdateLayout() end) end
        object.yui_hooked_show = true
    end
    
    buttons[object] = true
    return true
end

local function GrabMinimapButtons()
    if RefreshConflictState() then return end
    if InCombatLockdown() then return end
    
    local changed = false
    
    wipe(cachedMinimapChildren)
    local children = {Minimap:GetChildren()}
    for i, c in ipairs(children) do cachedMinimapChildren[i] = c end
    
    for _, child in ipairs(cachedMinimapChildren) do
        if ProcessButton(child) then changed = true end
    end
    
    local ldi = LibStub('LibDBIcon-1.0', true)
    if ldi and ldi.objects then
        for _, btn in pairs(ldi.objects) do
            if ProcessButton(btn) then changed = true end
        end
    end
    
    if MinimapBackdrop then
        wipe(cachedMinimapBackdropChildren)
        local bd_children = {MinimapBackdrop:GetChildren()}
        for i, c in ipairs(bd_children) do cachedMinimapBackdropChildren[i] = c end
        
        for _, child in ipairs(cachedMinimapBackdropChildren) do
            if ProcessButton(child) then changed = true end
        end
    end
    
    if changed then
        UpdateLayout()
    end
end

local StartButtonScan
local buttonScanTicker
local buttonScanInitialTimer
local buttonScanGeneration = 0
local buttonScanActive = false

local function RunButtonScan(generation)
    if not buttonScanActive or generation ~= buttonScanGeneration then return end
    local cpuWatchdog = YUI.CPUWatchdog
    local cpuStartedAt = cpuWatchdog and cpuWatchdog.timingActive and cpuWatchdog:BeginProbeTiming()
    GrabMinimapButtons()
    if cpuStartedAt then cpuWatchdog:EndProbeTiming("component.minimap-collection", cpuStartedAt) end
end

StopButtonScan = function()
    buttonScanActive = false
    buttonScanGeneration = buttonScanGeneration + 1

    if buttonScanInitialTimer and buttonScanInitialTimer.Cancel then
        pcall(buttonScanInitialTimer.Cancel, buttonScanInitialTimer)
    end
    buttonScanInitialTimer = nil

    if buttonScanTicker and buttonScanTicker.Cancel then
        pcall(buttonScanTicker.Cancel, buttonScanTicker)
    end
    buttonScanTicker = nil
end

StartButtonScan = function()
    if buttonScanActive or not C_Timer then return end

    buttonScanActive = true
    buttonScanGeneration = buttonScanGeneration + 1
    local generation = buttonScanGeneration

    if C_Timer.NewTimer then
        buttonScanInitialTimer = C_Timer.NewTimer(2, function()
            buttonScanInitialTimer = nil
            RunButtonScan(generation)
        end)
    elseif C_Timer.After then
        C_Timer.After(2, function()
            RunButtonScan(generation)
        end)
    end

    if C_Timer.NewTicker then
        buttonScanTicker = C_Timer.NewTicker(10, function()
            RunButtonScan(generation)
        end)
    elseif C_Timer.After then
        local function ScheduleFallback()
            C_Timer.After(10, function()
                if not buttonScanActive or generation ~= buttonScanGeneration then return end
                RunButtonScan(generation)
                ScheduleFallback()
            end)
        end
        ScheduleFallback()
    end
end

local cpuWatchdog = YUI.CPUWatchdog
if cpuWatchdog and cpuWatchdog.RegisterProbe then
    cpuWatchdog:RegisterProbe("component.minimap-collection", {
        localeKey = "cpu_watch.probe.minimap_collection",
        kind = "function",
        target = RunButtonScan,
        snapshot = function()
            return { running = buttonScanActive == true, generation = buttonScanGeneration or 0 }
        end,
        activityFields = { "generation" },
        minActivity = 5,
    })
end

-- 更新倒计时进度条
local function UpdateTimerBar(progress)
    if not timerBar then return end
    if not panelVisualRect.visible then
        timerBar:Hide()
        return
    end

    SafeRead(function()
        if timerBarFrame and timerBarFrame.SetFrameStrata and container.GetFrameStrata then
            timerBarFrame:SetFrameStrata(container:GetFrameStrata())
        end
        if timerBarFrame and timerBarFrame.SetFrameLevel and container.GetFrameLevel then
            timerBarFrame:SetFrameLevel((container:GetFrameLevel() or PANEL_FRAME_LEVEL) + PANEL_TIMER_FRAME_LEVEL_OFFSET)
        end
    end)

    if type(progress) ~= "number" then
        progress = 0
    elseif progress < 0 then
        progress = 0
    elseif progress > 1 then
        progress = 1
    end

    local width = panelVisualRect.width * progress
    
    if width <= 0 then
        timerBar:Hide()
    else
        timerBar:ClearAllPoints()
        timerBar:SetPoint("BOTTOMLEFT", container, "TOPLEFT", panelVisualRect.x, panelVisualRect.y - panelVisualRect.height)
        timerBar:SetHeight(2)
        timerBar:SetWidth(width)
        timerBar:Show()
    end
end

-- 创建抽屉动画
local function GetOrCreateAnimGroup()
    if animGroup then return animGroup end
    
    animGroup = container:CreateAnimationGroup()
    
    local trans = animGroup:CreateAnimation("Translation")
    trans:SetDuration(0.2)
    trans:SetSmoothing("OUT")
    animGroup.trans = trans
    
    local alpha = animGroup:CreateAnimation("Alpha")
    alpha:SetDuration(0.2)
    alpha:SetSmoothing("OUT")
    animGroup.alpha = alpha
    
    return animGroup
end

local PANEL_SLIDE_MIN_DISTANCE = 16

local function GetPanelOffset(db)
    db = db or GetDB()
    return ClampNumber(db and db.panelOffset, defaults.panelOffset, -100, 100)
end

IsHoverExpandMode = function()
    return GetDB().expandMode ~= "clickIcon"
end

local function IsHoverHotspotIcon()
    return GetDB().mainIconVisibility == "hoverHotspot"
end

local function GetFrameBounds(frameObject)
    if not frameObject then return nil end
    if not frameObject.GetLeft or not frameObject.GetRight or not frameObject.GetTop or not frameObject.GetBottom then
        return nil
    end

    local ok, left, right, top, bottom = pcall(function()
        return frameObject:GetLeft(), frameObject:GetRight(), frameObject:GetTop(), frameObject:GetBottom()
    end)
    if not ok then return nil end

    if type(left) ~= "number" or type(right) ~= "number" or type(top) ~= "number" or type(bottom) ~= "number" then
        return nil
    end

    return left, right, top, bottom
end

local function GetUIParentBounds()
    if not UIParent then return nil end

    local ok, left, right, top, bottom, width, height = pcall(function()
        return UIParent:GetLeft(), UIParent:GetRight(), UIParent:GetTop(), UIParent:GetBottom(), UIParent:GetWidth(), UIParent:GetHeight()
    end)
    if not ok then return nil end

    if type(left) ~= "number" then left = 0 end
    if type(bottom) ~= "number" then bottom = 0 end
    if type(right) ~= "number" then
        right = left + (type(width) == "number" and width or 0)
    end
    if type(top) ~= "number" then
        top = bottom + (type(height) == "number" and height or 0)
    end

    if right <= left or top <= bottom then return nil end

    return left, right, top, bottom
end

local function GetPanelClampOffset(extraX, extraY)
    if not container or not Minimap then return 0, 0 end

    local panelWidth = container:GetWidth() or 0
    local panelHeight = container:GetHeight() or 0
    if panelWidth <= 0 or panelHeight <= 0 then return 0, 0 end

    local mapLeft, mapRight, mapTop, mapBottom = GetFrameBounds(Minimap)
    local screenLeft, screenRight, screenTop, screenBottom = GetUIParentBounds()
    if not mapLeft or not screenLeft then return 0, 0 end

    local db = GetDB()
    local position = db.panelPosition or "bottom"
    local gap = GetPanelOffset(db)
    local left, right, top, bottom
    extraX = extraX or 0
    extraY = extraY or 0

    if position == "top" then
        left = ((mapLeft + mapRight) / 2) - panelWidth / 2 + extraX
        right = left + panelWidth
        bottom = mapTop + gap + extraY
        top = bottom + panelHeight
    elseif position == "left" then
        right = mapLeft - gap + extraX
        left = right - panelWidth
        top = ((mapTop + mapBottom) / 2) + panelHeight / 2 + extraY
        bottom = top - panelHeight
    elseif position == "right" then
        left = mapRight + gap + extraX
        right = left + panelWidth
        top = ((mapTop + mapBottom) / 2) + panelHeight / 2 + extraY
        bottom = top - panelHeight
    else
        left = ((mapLeft + mapRight) / 2) - panelWidth / 2 + extraX
        right = left + panelWidth
        top = mapBottom - gap + extraY
        bottom = top - panelHeight
    end

    if panelVisualRect.visible then
        local containerLeft = left
        local containerTop = top
        left = containerLeft + panelVisualRect.x
        right = left + panelVisualRect.width
        top = containerTop + panelVisualRect.y
        bottom = top - panelVisualRect.height
    end

    local clampX, clampY = 0, 0
    if left < screenLeft then
        clampX = screenLeft - left
    elseif right > screenRight then
        clampX = screenRight - right
    end
    if bottom < screenBottom then
        clampY = screenBottom - bottom
    elseif top > screenTop then
        clampY = screenTop - top
    end

    return clampX, clampY
end

SetPanelPoint = function(extraX, extraY)
    if not container or not Minimap then return end
    local db = GetDB()
    local position = db.panelPosition or "bottom"
    local gap = GetPanelOffset(db)
    extraX = extraX or 0
    extraY = extraY or 0
    local clampX, clampY = GetPanelClampOffset(extraX, extraY)
    extraX = extraX + clampX
    extraY = extraY + clampY

    container:ClearAllPoints()
    if position == "top" then
        container:SetPoint("BOTTOM", Minimap, "TOP", extraX, gap + extraY)
    elseif position == "left" then
        container:SetPoint("RIGHT", Minimap, "LEFT", -gap + extraX, extraY)
    elseif position == "right" then
        container:SetPoint("LEFT", Minimap, "RIGHT", gap + extraX, extraY)
    else
        container:SetPoint("TOP", Minimap, "BOTTOM", extraX, -gap + extraY)
    end
end

local function GetPanelSlideMotion()
    local db = GetDB()
    local offset = GetPanelOffset(db)
    local distance = math.abs(offset)
    if distance < PANEL_SLIDE_MIN_DISTANCE then
        return 0, 0, 0, 0
    end

    local position = db.panelPosition or "bottom"
    local baseSlideX, baseSlideY = 0, 0
    if position == "top" then
        baseSlideY = distance
    elseif position == "left" then
        baseSlideX = -distance
    elseif position == "right" then
        baseSlideX = distance
    else
        baseSlideY = -distance
    end

    local startRequestedX = -baseSlideX
    local startRequestedY = -baseSlideY
    local finalClampX, finalClampY = GetPanelClampOffset(0, 0)
    local startClampX, startClampY = GetPanelClampOffset(startRequestedX, startRequestedY)
    local startExtraX = startRequestedX + (startClampX or 0)
    local startExtraY = startRequestedY + (startClampY or 0)
    local finalExtraX = finalClampX or 0
    local finalExtraY = finalClampY or 0
    local animX = finalExtraX - startExtraX
    local animY = finalExtraY - startExtraY
    local effectiveDistance = math.sqrt(animX * animX + animY * animY)
    if effectiveDistance < PANEL_SLIDE_MIN_DISTANCE then
        return 0, 0, 0, 0
    end

    return startExtraX, startExtraY, animX, animY
end

local function UpdateMainIconVisibility()
    if not frame then return end
    if IsHoverHotspotIcon() and isCollapsed and not frame:IsMouseOver() then
        frame:SetAlpha(0)
    else
        frame:SetAlpha(1)
    end
end

-- 切换容器显示状态
local function ToggleContainer(show)
    if RefreshConflictState() then return end
    if not frame or not container then return end

    if show == nil then
        isCollapsed = not isCollapsed
    else
        isCollapsed = not show
    end
    
    local anim = GetOrCreateAnimGroup()
    anim:Stop()
    anim:SetScript("OnFinished", nil)
    
    if isCollapsed then
        local _, _, animX, animY = GetPanelSlideMotion()

        anim.trans:SetOffset(-animX, -animY)
        anim.alpha:SetFromAlpha(container:GetAlpha())
        anim.alpha:SetToAlpha(0)
        
        anim:SetScript("OnFinished", function()
            container:Hide()
            SetPanelPoint()
            if timerBar then timerBar:Hide() end
            UpdateMainIconVisibility()
        end)
        anim:Play()
        
        isCountingDown = false
    else
        GrabMinimapButtons()
        UpdateLayout()
        local startExtraX, startExtraY, animX, animY = GetPanelSlideMotion()
        
        container:Show()
        if timerBar then timerBar:Hide() end
        
        SetPanelPoint(startExtraX, startExtraY)
        anim.trans:SetOffset(animX, animY)
        anim.alpha:SetFromAlpha(0)
        anim.alpha:SetToAlpha(1)
        
        anim:SetScript("OnFinished", function()
            SetPanelPoint()
        end)
        
        anim:Play()
        
        isCountingDown = true
        hideTimer = 0
        forceHideTime = 0
        UpdateMainIconVisibility()
    end
end

-- 刷新主图标
local function UpdateMainIcon()
    if not frame then return end
    local db = GetDB()
    local size = db.mainIconSize or 20
    local offsetX = db.mainIconOffsetX or defaults.mainIconOffsetX
    local offsetY = db.mainIconOffsetY or defaults.mainIconOffsetY
    local position = db.mainIconPosition or defaults.mainIconPosition
    local scaleRatio = GetMinimapVisualScaleRatio()
    local visualOffsetX = offsetX / scaleRatio
    local visualOffsetY = offsetY / scaleRatio
    
    frame:SetScale(1 / scaleRatio)
    frame:SetSize(size, size)
    frame:ClearAllPoints()
    if position == "topLeft" then
        frame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -visualOffsetX, visualOffsetY)
    elseif position == "topRight" then
        frame:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", visualOffsetX, visualOffsetY)
    elseif position == "bottomLeft" then
        frame:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", -visualOffsetX, -visualOffsetY)
    else
        frame:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", visualOffsetX, -visualOffsetY)
    end
    
    if frame.icon then
        frame.icon:SetSize(size * 0.7, size * 0.7)
    end
    UpdateMainIconVisibility()
end

-- 初始化 UI
local function EnsureMinimapScaleWatcher()
    if minimapScaleHooked then return end
    if type(hooksecurefunc) ~= "function" or not Minimap then return end

    SafeRead(function()
        hooksecurefunc(Minimap, "SetScale", function()
            UpdateMainIcon()
            UpdateLayout()
        end)
        hooksecurefunc(Minimap, "SetSize", function()
            UpdateMainIcon()
            UpdateLayout()
        end)
        minimapScaleHooked = true
    end)
end

local function InitUI()
    if IsBlockedByExternalCollector() then return end
    if frame then return end
    local db = GetDB()
    EnsureConflictWatcher()
    EnsureMinimapScaleWatcher()
    
    -- 收纳按钮
    frame = GUI2:CreateButtonFrame(Minimap, { name = "YUI_MinimapCollectionBtn" })
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    
    local icon = GUI2:CreateTexture(frame, { layer = "ARTWORK", atlas = "ParagonReputation_Bag" })
    icon:SetPoint("CENTER")
    frame.icon = icon

    -- 增加悬浮高亮
    frame:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    local hl = frame:GetHighlightTexture()
    hl:SetVertexColor(1, 1, 1, 0.2)
    hl:SetBlendMode("ADD")
    
    UpdateMainIcon()
    
    -- 容器框架
    container = GUI2:CreateFrame(UIParent, { name = "YUI_MinimapCollectionContainer", template = "BackdropTemplate", frameStrata = PANEL_FRAME_STRATA, frameLevel = PANEL_FRAME_LEVEL, clamped = false })
    SetPanelPoint()
    container:Hide()

    panelBackgroundFrame = GUI2:CreateFrame(container, { name = "YUI_MinimapCollectionPanelBackground", template = "BackdropTemplate", frameStrata = PANEL_BACKGROUND_FRAME_STRATA, frameLevel = GetPanelBackgroundFrameLevel(), mouse = false })
    ApplyPanelBackgroundLayer()
    panelBackgroundFrame:Hide()
    panelBackground = GUI2:CreateTexture(panelBackgroundFrame, { layer = "BACKGROUND", texture = "Interface\\Buttons\\WHITE8x8" })
    panelBackground:SetAllPoints()
    GUI2:CreateBorder(panelBackgroundFrame, "color.border.default")
    
    -- 倒计时进度条
    timerBarFrame = GUI2:CreateFrame(container, { name = "YUI_MinimapCollectionTimerBar", frameStrata = container:GetFrameStrata(), frameLevel = (container:GetFrameLevel() or PANEL_FRAME_LEVEL) + PANEL_TIMER_FRAME_LEVEL_OFFSET })
    timerBarFrame:EnableMouse(false)
    timerBar = timerBarFrame
    timerBar:SetHeight(2)
    timerBar:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 6, 6)
    timerBar:Hide()
    local timerBarTexture = GUI2:CreateTexture(timerBarFrame, { layer = "ARTWORK", texture = "Interface\\Buttons\\WHITE8x8" })
    timerBarTexture:SetAllPoints()
    timerBarTexture:SetVertexColor(1, 1, 1, 0.5)
    
    -- 鼠标事件与自动隐藏逻辑
    container:SetScript("OnUpdate", function(self, elapsed)
        if RefreshConflictState() then return end
        if not self:IsShown() then return end
        if isCollapsed then return end -- 如果已经处于收起状态（动画播放中或已隐藏），不再重复触发
        
        local db = GetDB()
        
        if not IsHoverExpandMode() then
            if timerBar and timerBar:IsShown() then timerBar:Hide() end
            return 
        end
        
        local mouseIsOver = self:IsMouseOver() or frame:IsMouseOver()
        local currentTime = GetTime()
        
        -- 强制隐藏检查 (点击了插件按钮后 3 秒)
        if forceHideTime > 0 then
            local remaining = forceHideTime - currentTime
            if remaining <= 0 then
                ToggleContainer(false)
                return
            else
                UpdateTimerBar(remaining / hideDelay)
            end
            return
        end
        
        if mouseIsOver then
            hideTimer = 0
            if timerBar and timerBar:IsShown() then timerBar:Hide() end
        else
            hideTimer = hideTimer + elapsed
            local remaining = hideDelay - hideTimer
            if remaining <= 0 then
                ToggleContainer(false)
            else
                UpdateTimerBar(remaining / hideDelay)
            end
        end
        UpdateMainIconVisibility()
    end)
    
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if YUI.Settings and YUI.Settings.Toggle then
                 local settingsFrame = YUI.Settings.Elements and YUI.Settings.Elements.frame
                 if not settingsFrame or not settingsFrame:IsShown() then
                     YUI.Settings:Toggle()
                 end
                 
                if YUI.Components and YUI.Components.features and YUI.Components.features["MinimapCollection"] then
                    local feature = YUI.Components.features["MinimapCollection"]
                    
                    local yboxModule = nil
                    if YUI.Settings.modules then
                        for _, mod in ipairs(YUI.Settings.modules) do
                            if mod.id == "suite.settings.general" or mod.id == "toolbox.settings"
                                or mod.name == "组件管理" or mod.name == "功能百宝箱" then
                                yboxModule = mod
                                break
                            end
                        end
                    end
                    
                    if yboxModule then
                        YUI.Settings:SelectModule(yboxModule)
                        
                          if YUI.Settings.OpenComponentFeature then
                              YUI.Settings:OpenComponentFeature("MinimapCollection")
                          elseif YUI.Components.OpenFeatureSettings then
                              YUI.Components:OpenFeatureSettings("MinimapCollection")
                          end
                      end
                end
            end
        else
            if IsHoverExpandMode() then
                if isCollapsed then
                    ToggleContainer(true)
                end
            else
                ToggleContainer()
            end
        end
    end)
    
    frame:SetScript("OnEnter", function(self)
        if RefreshConflictState() then return end
        UpdateMainIconVisibility()
        if IsHoverExpandMode() and isCollapsed then
            ToggleContainer(true)
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine(T("minimap_collection.tooltip.title", "Minimap Buttons"), 1, 0.82, 0)
        if IsHoverExpandMode() then
            GameTooltip:AddLine(T("minimap_collection.tooltip.hover", "Hover: open button list"), 0.6, 0.6, 0.6)
        else
            GameTooltip:AddLine(T("minimap_collection.tooltip.click", "Left Click: toggle button list"), 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine(T("minimap_collection.tooltip.settings", "Right Click: open settings"), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    
    frame:SetScript("OnLeave", function(self)
        YUI.HideGameTooltip()
        UpdateMainIconVisibility()
    end)
    
    -- 战场图标避让
    if MiniMapBattlefieldFrame then
        local function RepositionBattlefieldFrame()
            if MiniMapBattlefieldFrame:IsShown() then
                local db = GetDB()
                local size = db.mainIconSize or 20
                
                -- 重定位并修改尺寸
                MiniMapBattlefieldFrame:ClearAllPoints()
                MiniMapBattlefieldFrame:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
                MiniMapBattlefieldFrame:SetSize(size, size)
                
                -- 隐藏默认边框并调整图标
                local regions = {MiniMapBattlefieldFrame:GetRegions()}
                for _, region in ipairs(regions) do
                    if region:IsObjectType('Texture') then
                        local texture = region:GetTexture()
                        local isBorderOrBg = false
                        if type(texture) == "string" then
                            local lowerTex = string.lower(texture)
                            if string.find(lowerTex, "interface\\characterframe") or 
                               string.find(lowerTex, "interface\\minimap") or
                               string.find(lowerTex, "border") or 
                               string.find(lowerTex, "background") or 
                               string.find(lowerTex, "alphamask") then
                                isBorderOrBg = true
                            end
                        elseif type(texture) == "number" then
                            if texture == 136430 or texture == 136467 then
                                isBorderOrBg = true
                            end
                        end
                        
                        if isBorderOrBg then
                            region:SetTexture(nil)
                            region:Hide()
                        elseif texture then
                            -- 调整主图标以铺满
                            region:ClearAllPoints()
                            region:SetAllPoints()
                            region:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        end
                    end
                end
                
                -- 添加统一背景和边框
                -- if not MiniMapBattlefieldFrame.yui_bg then
                --     MiniMapBattlefieldFrame.yui_bg = MiniMapBattlefieldFrame:CreateTexture(nil, "BACKGROUND")
                --     MiniMapBattlefieldFrame.yui_bg:SetAllPoints()
                --     MiniMapBattlefieldFrame.yui_bg:SetTexture("Interface\\Buttons\\WHITE8x8")
                --     MiniMapBattlefieldFrame.yui_bg:SetVertexColor(0, 0, 0, 1)
                -- end
            end
        end
        MiniMapBattlefieldFrame:HookScript("OnShow", RepositionBattlefieldFrame)
        if MiniMapBattlefieldFrame:IsShown() then
            RepositionBattlefieldFrame()
        end
    end
    
    -- LFG图标避让
    if LFGMinimapFrame then
        local function RepositionLFGFrame()
            if LFGMinimapFrame:IsShown() then
                local db = GetDB()
                local size = (db.mainIconSize or 20) + 4
                
                -- 重定位并修改尺寸 (+2)
                LFGMinimapFrame:ClearAllPoints()
                -- 定位到小地图的右上角
                LFGMinimapFrame:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -2, -2)
                LFGMinimapFrame:SetSize(size, size)
                
                -- 隐藏默认边框并调整图标
                local regions = {LFGMinimapFrame:GetRegions()}
                for _, region in ipairs(regions) do
                    if region:IsObjectType('Texture') then
                        local texture = region:GetTexture()
                        local isBorderOrBg = false
                        if type(texture) == "string" then
                            local lowerTex = string.lower(texture)
                            if string.find(lowerTex, "interface\\characterframe") or 
                               string.find(lowerTex, "interface\\minimap") or
                               string.find(lowerTex, "border") or 
                               string.find(lowerTex, "background") or 
                               string.find(lowerTex, "alphamask") then
                                isBorderOrBg = true
                            end
                        elseif type(texture) == "number" then
                            if texture == 136430 or texture == 136467 then
                                isBorderOrBg = true
                            end
                        end
                        
                        if isBorderOrBg then
                            region:SetTexture(nil)
                            region:Hide()
                        elseif texture then
                            -- 调整主图标以铺满
                            region:ClearAllPoints()
                            region:SetAllPoints()
                            region:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        end
                    end
                end
            end
        end
        LFGMinimapFrame:HookScript("OnShow", RepositionLFGFrame)
        if LFGMinimapFrame:IsShown() then
            RepositionLFGFrame()
        end
    end
end

-- 获取配置
local function GetEffectiveState()
    local blocker, status = GetBlockingCollector()
    if status == "active" or status == "unknown" then
        return {
            effective = false,
            kind = status == "active" and "yield" or nil,
            controller = blocker,
            featureKey = "minimap_collection",
            status = status,
            tone = "warning",
        }
    end
    return { effective = true }
end

local function GetOptions(feature)
    local db = GetDB()

    return {
        {
            type = "custom",
            render = function(parent, x, y, availableWidth)
                local pageWidth = math.min(availableWidth or 620, 620)
                local rowHeight = 32
                local rowGap = 10
                local sectionGap = 14
                local fieldGap = 24
                local labelWidth = 96
                local sliderValueWidth = 44
                local colWidth = math.floor((pageWidth - fieldGap) / 2)
                local cursorY = 0

                local root = GUI2:CreateFrame(parent, { width = pageWidth, height = 1 })
                root:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

                local function Advance(amount)
                    cursorY = cursorY - amount
                end

                local function AddSection(label)
                    local divider = GUI2:CreateDivider(root, pageWidth, nil, label, true)
                    divider:SetPoint("TOPLEFT", root, "TOPLEFT", 0, cursorY)
                    Advance((divider:GetHeight() or 16) + sectionGap)
                end

                local function AddRow(height, gap)
                    local row = GUI2:CreateFrame(root, { width = pageWidth, height = height or rowHeight })
                    row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, cursorY)
                    Advance((height or rowHeight) + (gap or rowGap))
                    return row
                end

                local function ColX(index)
                    return (index - 1) * (colWidth + fieldGap)
                end

                local function AddLabel(row, text, xOffset, width)
                    local label = GUI2:CreateText(row, text, "font.size.md", "color.text.primary")
                    label:SetPoint("LEFT", row, "LEFT", xOffset, 0)
                    label:SetWidth(width or labelWidth)
                    label:SetJustifyH("LEFT")
                    label:SetWordWrap(false)
                    return label
                end

                local function AddDropdown(row, colIndex, label, opts)
                    local xOffset = ColX(colIndex)
                    local controlWidth = colWidth - labelWidth
                    AddLabel(row, label, xOffset, labelWidth)
                    local dropdown = GUI2.Form:CreateDropdown(row, {
                        width = controlWidth,
                        options = opts.options,
                        get = opts.get,
                        set = opts.set,
                    })
                    dropdown:SetPoint("LEFT", row, "LEFT", xOffset + labelWidth, 0)
                    return dropdown
                end

                local function AddSlider(row, colIndex, label, opts)
                    local slider = GUI2.Form:CreateSlider(row, {
                        label = label,
                        inline = true,
                        width = colWidth,
                        labelWidth = labelWidth,
                        inputWidth = sliderValueWidth,
                        min = opts.min,
                        max = opts.max,
                        step = opts.step,
                        get = opts.get,
                        set = opts.set,
                    })
                    slider:SetPoint("LEFT", row, "LEFT", ColX(colIndex), 0)
                    return slider
                end

                AddSection(T("minimap_collection.settings.main_icon", "Collection Button"))
                local mainIconBehaviorRow = AddRow(rowHeight)
                AddDropdown(mainIconBehaviorRow, 1, T("minimap_collection.settings.main_icon_position", "Button Position"), {
                    options = {
                        { text = T("minimap_collection.position.top_left", "Top Left"), value = "topLeft" },
                        { text = T("minimap_collection.position.top_right", "Top Right"), value = "topRight" },
                        { text = T("minimap_collection.position.bottom_left", "Bottom Left"), value = "bottomLeft" },
                        { text = T("minimap_collection.position.bottom_right", "Bottom Right"), value = "bottomRight" },
                    },
                    get = function() return db.mainIconPosition end,
                    set = function(v)
                        db.mainIconPosition = v
                        UpdateMainIcon()
                    end,
                })
                AddDropdown(mainIconBehaviorRow, 2, T("minimap_collection.settings.main_icon_visibility", "Button Visibility"), {
                    options = {
                        { text = T("minimap_collection.visibility.always", "Always"), value = "always" },
                        { text = T("minimap_collection.visibility.hover", "On Hover"), value = "hoverHotspot" },
                    },
                    get = function() return db.mainIconVisibility end,
                    set = function(v)
                        db.mainIconVisibility = v
                        UpdateMainIconVisibility()
                    end,
                })

                local mainIconSizeRow = AddRow(rowHeight)
                AddSlider(mainIconSizeRow, 1, T("minimap_collection.settings.main_icon_size", "Button Size"), {
                    min = 16, max = 40, step = 1,
                    get = function() return db.mainIconSize end,
                    set = function(v) db.mainIconSize = v; UpdateMainIcon() end,
                })

                local mainIconOffsetRow = AddRow(rowHeight)
                AddSlider(mainIconOffsetRow, 1, T("common.offset_x", "X Offset"), {
                    min = -100, max = 100, step = 1,
                    get = function() return db.mainIconOffsetX end,
                    set = function(v) db.mainIconOffsetX = v; UpdateMainIcon() end,
                })
                AddSlider(mainIconOffsetRow, 2, T("common.offset_y", "Y Offset"), {
                    min = -100, max = 100, step = 1,
                    get = function() return db.mainIconOffsetY end,
                    set = function(v) db.mainIconOffsetY = v; UpdateMainIcon() end,
                })

                AddSection(T("minimap_collection.settings.panel", "Collection Panel"))
                local panelBehaviorRow = AddRow(rowHeight)
                AddDropdown(panelBehaviorRow, 1, T("minimap_collection.settings.expand_mode", "Open Panel"), {
                    options = {
                        { text = T("minimap_collection.expand.hover", "Hover Button"), value = "hoverIcon" },
                        { text = T("minimap_collection.expand.click", "Click Button"), value = "clickIcon" },
                    },
                    get = function() return db.expandMode end,
                    set = function(v)
                        db.expandMode = v
                        hideTimer = 0
                        forceHideTime = 0
                        if timerBar then timerBar:Hide() end
                        UpdateMainIconVisibility()
                    end,
                })
                AddDropdown(panelBehaviorRow, 2, T("minimap_collection.settings.background", "Panel Background"), {
                    options = {
                        { text = T("common.none", "None"), value = "none" },
                        { text = T("minimap_collection.background.black", "Black"), value = "black" },
                        { text = T("minimap_collection.background.translucent", "Translucent"), value = "translucent" },
                    },
                    get = function() return db.panelBackground end,
                    set = function(v)
                        db.panelBackground = v
                        UpdateLayout()
                    end,
                })

                local panelPositionRow = AddRow(rowHeight)
                AddDropdown(panelPositionRow, 1, T("minimap_collection.settings.panel_position", "Panel Position"), {
                    options = {
                        { text = T("minimap_collection.panel.bottom", "Below Minimap"), value = "bottom" },
                        { text = T("minimap_collection.panel.top", "Above Minimap"), value = "top" },
                        { text = T("minimap_collection.panel.left", "Left of Minimap"), value = "left" },
                        { text = T("minimap_collection.panel.right", "Right of Minimap"), value = "right" },
                    },
                    get = function() return db.panelPosition end,
                    set = function(v)
                        db.panelPosition = v
                        if container then
                            if container:IsShown() then
                                UpdateLayout()
                            end
                            SetPanelPoint()
                        end
                    end,
                })
                AddSlider(panelPositionRow, 2, T("minimap_collection.settings.panel_offset", "Panel Offset"), {
                    min = -100, max = 100, step = 1,
                    get = function() return db.panelOffset end,
                    set = function(v)
                        db.panelOffset = v
                        if container then
                            if container:IsShown() then
                                UpdateLayout()
                            end
                            SetPanelPoint()
                        end
                    end,
                })

                AddSection(T("minimap_collection.settings.addon_icons", "Addon Buttons"))
                local iconSizeRow = AddRow(rowHeight)
                AddSlider(iconSizeRow, 1, T("minimap_collection.settings.addon_icon_size", "Addon Button Size"), {
                    min = 16, max = 40, step = 1,
                    get = function() return db.iconSize end,
                    set = function(v) db.iconSize = v; UpdateLayout() end,
                })

                local iconSpacingRow = AddRow(rowHeight, 0)
                AddSlider(iconSpacingRow, 1, T("minimap_collection.settings.row_spacing", "Row Spacing"), {
                    min = 0, max = 20, step = 1,
                    get = function() return db.spacingY end,
                    set = function(v) db.spacingY = v; UpdateLayout() end,
                })
                AddSlider(iconSpacingRow, 2, T("minimap_collection.settings.column_spacing", "Column Spacing"), {
                    min = 0, max = 20, step = 1,
                    get = function() return db.spacingX end,
                    set = function(v) db.spacingX = v; UpdateLayout() end,
                })

                local totalHeight = math.abs(cursorY) + 4
                root:SetHeight(totalHeight)
                return pageWidth, totalHeight
            end,
        },
    }
end

-- 注册功能
YUI.Components:RegisterFeature("MinimapCollection", {
    name = "小地图插件收纳",
    default = false,
    description = "把小地图插件按钮收进统一面板，可选择滑过或点击展开。",
    callback = function(enable)
        local db = GetDB()
        
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = v end
        end
        
        if enable then
            if RefreshConflictState({ force = true }) then return end
            InitUI()
            HideBlizzardAddonCompartment()
            if frame then
                StartButtonScan()
                frame:Show()
            end
        else
            ReleaseCapturedButtons()
            RestoreBlizzardAddonCompartment()
            if YUI.Yield then YUI.Yield:Clear("minimap_collection") end
            if frame then frame:Hide() end
            if container then container:Hide() end
        end
    end,
    GetOptions = GetOptions,
    GetEffectiveState = GetEffectiveState
})

if YUI.Event and YUI.Event.On then
    YUI.Event:On("YUI_EXTERNAL_STATE_CHANGED", function()
        local blocked = RefreshConflictState({ force = true })
        if blocked then return end
        local enabled = YUI.Components and YUI.Components.IsEnabled
            and YUI.Components:IsEnabled("MinimapCollection")
        if enabled then
            InitUI()
            HideBlizzardAddonCompartment()
            if frame then StartButtonScan(); frame:Show() end
        end
    end, nil, { moduleId = "component:MinimapCollection" })
end

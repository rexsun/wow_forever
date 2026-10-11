local YUI = _G.YUI
if not YUI or not YUI.YMap then return end

local YMap = YUI.YMap
local GUI2 = YUI.GUI2
local Security = YUI.API and YUI.API.Security
local SharedStats = YMap.Stats

local WorldMap = YMap.WorldMap or {}
YMap.WorldMap = WorldMap

local CoordinateDriver = YMap.CoordinateDriver or {}
YMap.CoordinateDriver = CoordinateDriver

local math_abs = math.abs
local math_floor = math.floor
local string_format = string.format
local type = type

local CURSOR_INTERVAL = 0.10
local PLAYER_INTERVAL = 0.25
local MINIMAP_INTERVAL = 0.50
local POSITION_EPSILON = 0.05

local VALID_POINTS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local config = {
    enabled = true,
    scale = 1,
    rememberPosition = true,
    fadeWhenMoving = false,
    movingAlpha = 0.8,
    playerCoordinates = true,
    cursorCoordinates = true,
    playerLabel = "玩家",
    cursorLabel = "鼠标",
}

local state = {
    requestedEnabled = false,
    enabled = false,
    attached = false,
    waitingForAddon = false,
    hooksInstalled = false,
    globalHookInstalled = false,
    frame = nil,
    hookedFrame = nil,
    coordinateOverlay = nil,
    playerText = nil,
    cursorText = nil,
    dragHandle = nil,
    nativeState = nil,
    nativeCaptured = false,
    positionOwned = false,
    applying = false,
    dragging = false,
    pendingRefresh = false,
    pendingRestore = false,
    driverActive = false,
    cursorElapsed = 0,
    playerElapsed = 0,
    cursorVisible = false,
    playerVisible = false,
    cursorQX = nil,
    cursorQY = nil,
    playerQX = nil,
    playerQY = nil,
    cursorReads = 0,
    playerReads = 0,
    textWrites = 0,
    restoreFailures = 0,
    movementFadeAlpha = nil,
}

local eventFrame = CreateFrame("Frame")
local coordinateDriver = CreateFrame("Frame")
coordinateDriver:Hide()

local coordinateDriverActive = false
local minimapConsumerActive = false
local minimapConsumerCallback
local minimapElapsed = 0
local directionCallback, metricsCallback
local directionActive, metricsActive = false, false
local directionElapsed, metricsElapsed = 0, 0

local ApplyNow
local AttachWorldMap
local RefreshEffectiveState
local RestoreNativeNow
local RefreshCoordinateDriverActivity

local function Clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function IncrementStat(field, amount)
    amount = amount or 1
    if SharedStats and SharedStats.Increment then
        SharedStats:Increment(field, amount)
    elseif SharedStats and type(SharedStats[field]) == "number" then
        SharedStats[field] = SharedStats[field] + amount
    end
end

local function SetStat(field, value)
    if SharedStats and SharedStats.Set then
        SharedStats:Set(field, value)
    elseif SharedStats and SharedStats[field] ~= nil then
        SharedStats[field] = value
    end
end

local function InCombatLockdownSafe()
    if Security and Security.InCombatLockdown then
        return Security.InCombatLockdown() == true
    end
    if InCombatLockdown then
        return InCombatLockdown() == true
    end
    return false
end

local function IsMaximized(frame)
    return frame and frame.IsMaximized and frame:IsMaximized() == true
end

local function GetWorldMapDB()
    if type(YMap.GetDB) ~= "function" then return nil end
    local db = YMap:GetDB()
    return type(db) == "table" and type(db.worldMap) == "table" and db.worldMap or nil
end

local function ReadConfig()
    local worldMap = GetWorldMapDB()
    local coordinates = worldMap and worldMap.coordinates
    local scale = worldMap and tonumber(worldMap.scale) or 1

    config.enabled = not worldMap or worldMap.enabled ~= false
    config.scale = Clamp(scale or 1, 0.5, 2)
    config.rememberPosition = not worldMap or worldMap.rememberPosition ~= false
    config.fadeWhenMoving = worldMap and worldMap.fadeWhenMoving == true
    config.movingAlpha = Clamp(worldMap and tonumber(worldMap.movingAlpha) or 0.8, 0.1, 1)
    config.playerCoordinates = type(coordinates) ~= "table" or coordinates.player ~= false
    config.cursorCoordinates = type(coordinates) ~= "table" or coordinates.cursor ~= false

    if type(YMap.T) == "function" then
        config.playerLabel = YMap:T("coordinates.player", "玩家")
        config.cursorLabel = YMap:T("coordinates.cursor", "鼠标")
    end
end

local function NativeMovementFadePredicate()
    return GetCVarBool("mapFade") and state.frame and not state.frame:IsMouseOver()
end

local function ReleaseMovementFade(restoreNative)
    if not state.movementFadeAlpha then return end
    local frame = state.frame
    local fader = PlayerMovementFrameFader
    state.movementFadeAlpha = nil
    if not frame or not fader then return end
    fader.RemoveFrame(frame)
    if restoreNative and frame:IsShown() then
        fader.AddDeferredFrame(frame, 0.5, 1, 0.5, NativeMovementFadePredicate)
    end
end

local function RefreshMovementFade()
    local frame = state.frame
    if not state.enabled or not config.fadeWhenMoving or not frame or not frame:IsShown() then
        ReleaseMovementFade(true)
        return
    end
    local fader = PlayerMovementFrameFader
    if state.hookedFrame ~= frame or not fader or not fader.AddFrame
        or not fader.RemoveFrame or not fader.AddDeferredFrame then return end
    if state.movementFadeAlpha == config.movingAlpha then return end
    -- 使用原生共享驱动，移动中打开地图也立即参与渐隐；不修改 mapFade CVar。
    fader.AddFrame(frame, config.movingAlpha, 1, 0.5)
    state.movementFadeAlpha = config.movingAlpha
end

local function UpdateRegenRegistration()
    if state.pendingRefresh or state.pendingRestore then
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

local function QueueRefresh()
    state.pendingRefresh = true
    UpdateRegenRegistration()
end

local function QueueRestore()
    state.pendingRestore = true
    UpdateRegenRegistration()
end

local function StopWaitingForAddon()
    if not state.waitingForAddon then return end
    state.waitingForAddon = false
    eventFrame:UnregisterEvent("ADDON_LOADED")
end

local function WaitForAddon()
    if state.waitingForAddon then return end
    state.waitingForAddon = true
    eventFrame:RegisterEvent("ADDON_LOADED")
end

local function HidePlayerText()
    if state.playerText and state.playerVisible then
        state.playerText:Hide()
    end
    state.playerVisible = false
    state.playerQX = nil
    state.playerQY = nil
end

local function HideCursorText()
    if state.cursorText and state.cursorVisible then
        state.cursorText:Hide()
    end
    state.cursorVisible = false
    state.cursorQX = nil
    state.cursorQY = nil
end

local function HideCoordinateVisuals()
    HidePlayerText()
    HideCursorText()
    if state.coordinateOverlay then
        state.coordinateOverlay:Hide()
    end
end

local function StopCoordinateDriver()
    if not state.driverActive then
        SetStat("worldMapDriverActive", false)
        if RefreshCoordinateDriverActivity then RefreshCoordinateDriverActivity() end
        return
    end
    state.driverActive = false
    state.cursorElapsed = 0
    state.playerElapsed = 0
    SetStat("worldMapDriverActive", false)
    if RefreshCoordinateDriverActivity then RefreshCoordinateDriverActivity() end
end

local function QuantizeCoordinate(value)
    if type(value) ~= "number" then return nil end
    value = Clamp(value, 0, 1)
    return math_floor(value * 1000 + 0.5)
end

local function SetPlayerCoordinates(x, y)
    local qx = QuantizeCoordinate(x)
    local qy = QuantizeCoordinate(y)
    if not qx or not qy then
        HidePlayerText()
        return
    end
    if state.playerVisible and state.playerQX == qx and state.playerQY == qy then return end

    state.playerQX = qx
    state.playerQY = qy
    state.playerText:SetText(string_format("%s: %.1f, %.1f", config.playerLabel, qx / 10, qy / 10))
    if not state.playerVisible then
        state.playerText:Show()
        state.playerVisible = true
    end
    state.textWrites = state.textWrites + 1
    IncrementStat("worldMapTextWrites")
end

local function SetCursorCoordinates(x, y)
    local qx = QuantizeCoordinate(x)
    local qy = QuantizeCoordinate(y)
    if not qx or not qy then
        HideCursorText()
        return
    end
    if state.cursorVisible and state.cursorQX == qx and state.cursorQY == qy then return end

    state.cursorQX = qx
    state.cursorQY = qy
    state.cursorText:SetText(string_format("%s: %.1f, %.1f", config.cursorLabel, qx / 10, qy / 10))
    if not state.cursorVisible then
        state.cursorText:Show()
        state.cursorVisible = true
    end
    state.textWrites = state.textWrites + 1
    IncrementStat("worldMapTextWrites")
end

local function UpdatePlayerCoordinates()
    local frame = state.frame
    if not config.playerCoordinates or not frame or not state.playerText then
        HidePlayerText()
        return
    end

    local mapID = frame.GetMapID and frame:GetMapID()
    if not mapID or not C_Map or not C_Map.GetPlayerMapPosition then
        HidePlayerText()
        return
    end

    state.playerReads = state.playerReads + 1
    IncrementStat("worldMapPlayerReads")
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then
        HidePlayerText()
        return
    end

    local x, y
    if position.GetXY then
        x, y = position:GetXY()
    else
        x, y = position.x, position.y
    end
    SetPlayerCoordinates(x, y)
end

local function UpdateCursorCoordinates()
    local frame = state.frame
    local scrollContainer = frame and frame.ScrollContainer
    if not config.cursorCoordinates or not frame or not state.cursorText or not scrollContainer then
        HideCursorText()
        return
    end
    if scrollContainer.IsMouseOver and not scrollContainer:IsMouseOver() then
        HideCursorText()
        return
    end
    if not frame.GetNormalizedCursorPosition then
        HideCursorText()
        return
    end

    state.cursorReads = state.cursorReads + 1
    IncrementStat("worldMapCursorReads")
    local x, y = frame:GetNormalizedCursorPosition()
    SetCursorCoordinates(x, y)
end

local function CoordinateOnUpdate(_, elapsed)
    local cpuWatchdog = YUI.CPUWatchdog
    local cpuStartedAt = cpuWatchdog and cpuWatchdog.timingActive and cpuWatchdog:BeginProbeTiming()

    if state.driverActive then
        if not state.enabled or not state.frame or not state.frame:IsShown() then
            StopCoordinateDriver()
        else
            state.cursorElapsed = state.cursorElapsed + elapsed
            state.playerElapsed = state.playerElapsed + elapsed

            if state.cursorElapsed >= CURSOR_INTERVAL then
                state.cursorElapsed = state.cursorElapsed % CURSOR_INTERVAL
                UpdateCursorCoordinates()
            end
            if state.playerElapsed >= PLAYER_INTERVAL then
                state.playerElapsed = state.playerElapsed % PLAYER_INTERVAL
                UpdatePlayerCoordinates()
            end
        end
    end

    if minimapConsumerActive and minimapConsumerCallback then
        minimapElapsed = minimapElapsed + elapsed
        if minimapElapsed >= MINIMAP_INTERVAL then
            minimapElapsed = minimapElapsed % MINIMAP_INTERVAL
            minimapConsumerCallback()
        end
    end
    if directionActive then
        directionElapsed = directionElapsed + elapsed
        if directionElapsed >= 0.05 then
            directionElapsed = directionElapsed % 0.05
            directionCallback()
        end
    end
    if metricsActive then
        metricsElapsed = metricsElapsed + elapsed
        if metricsElapsed >= 1 then
            metricsElapsed = metricsElapsed % 1
            metricsCallback()
        end
    end
    if cpuStartedAt then cpuWatchdog:EndProbeTiming("product.ymap-coordinates", cpuStartedAt) end
end

RefreshCoordinateDriverActivity = function()
    local shouldRun = state.driverActive == true or minimapConsumerActive == true
        or directionActive == true or metricsActive == true
    if shouldRun == coordinateDriverActive then
        SetStat("coordinateDriverActive", shouldRun)
        return
    end
    coordinateDriverActive = shouldRun
    SetStat("coordinateDriverActive", shouldRun)
    if shouldRun then
        coordinateDriver:Show()
        coordinateDriver:SetScript("OnUpdate", CoordinateOnUpdate)
    else
        coordinateDriver:SetScript("OnUpdate", nil)
        coordinateDriver:Hide()
    end
end

local function StartCoordinateDriver()
    local frame = state.frame
    if not state.enabled or not frame or not frame:IsShown() then
        StopCoordinateDriver()
        return
    end
    if not config.playerCoordinates and not config.cursorCoordinates then
        StopCoordinateDriver()
        HideCoordinateVisuals()
        return
    end

    if state.coordinateOverlay then
        state.coordinateOverlay:Show()
    end
    if not config.playerCoordinates then HidePlayerText() end
    if not config.cursorCoordinates then HideCursorText() end
    if state.driverActive then return end

    state.cursorElapsed = CURSOR_INTERVAL
    state.playerElapsed = PLAYER_INTERVAL
    state.driverActive = true
    SetStat("worldMapDriverActive", true)
    RefreshCoordinateDriverActivity()
end

function CoordinateDriver:RegisterMinimapConsumer(callback)
    if type(callback) ~= "function" then return false end
    if minimapConsumerCallback and minimapConsumerCallback ~= callback then return false end
    minimapConsumerCallback = callback
    return true
end

function CoordinateDriver:SetMinimapActive(active)
    active = active == true and type(minimapConsumerCallback) == "function"
    if minimapConsumerActive == active then
        SetStat("minimapCoordinateConsumerActive", active)
        RefreshCoordinateDriverActivity()
        return active
    end
    minimapConsumerActive = active
    minimapElapsed = 0
    SetStat("minimapCoordinateConsumerActive", active)
    if active then minimapConsumerCallback() end
    RefreshCoordinateDriverActivity()
    return active
end

function CoordinateDriver:RegisterDirectionConsumer(callback)
    if type(callback) ~= "function" or (directionCallback and directionCallback ~= callback) then return false end
    directionCallback = callback
    return true
end

function CoordinateDriver:SetDirectionActive(active)
    directionActive = active == true and directionCallback ~= nil
    if not directionActive then directionElapsed = 0 end
    RefreshCoordinateDriverActivity()
    return directionActive
end

function CoordinateDriver:RegisterMetricsConsumer(callback)
    if type(callback) ~= "function" or (metricsCallback and metricsCallback ~= callback) then return false end
    metricsCallback = callback
    return true
end

function CoordinateDriver:SetMetricsActive(active)
    metricsActive = active == true and metricsCallback ~= nil
    if not metricsActive then metricsElapsed = 0 end
    RefreshCoordinateDriverActivity()
    return metricsActive
end

function CoordinateDriver:IsActive()
    return coordinateDriverActive == true
end

function CoordinateDriver:IsMinimapActive()
    return minimapConsumerActive == true
end

local cpuWatchdog = YUI.CPUWatchdog
if cpuWatchdog and cpuWatchdog.RegisterProbe then
    cpuWatchdog:RegisterProbe("product.ymap-coordinates", {
        localeKey = "cpu_watch.probe.ymap_coordinates",
        kind = "frame",
        target = coordinateDriver,
        snapshot = function()
            return {
                running = coordinateDriverActive == true,
                worldMap = state.driverActive == true,
                minimap = minimapConsumerActive == true,
            }
        end,
    })
end

local function CaptureNativeState()
    if state.nativeCaptured then return true end
    local frame = state.frame
    if not frame or not frame:IsShown() then return false end

    local native = {
        scale = frame:GetScale(),
        movable = frame.IsMovable and frame:IsMovable() or false,
        clamped = frame.IsClampedToScreen and frame:IsClampedToScreen() or false,
        points = {},
    }
    local pointCount = frame.GetNumPoints and frame:GetNumPoints() or 0
    for index = 1, pointCount do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(index)
        native.points[index] = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = x,
            y = y,
        }
    end
    state.nativeState = native
    state.nativeCaptured = true
    return true
end

local function RestorePoints(points)
    local frame = state.frame
    if not frame then return end
    frame:ClearAllPoints()
    for index = 1, #points do
        local point = points[index]
        frame:SetPoint(point.point, point.relativeTo, point.relativePoint, point.x, point.y)
    end
end

local function RefreshUIPanelPosition()
    if type(UpdateUIPanelPositions) == "function" and state.frame then
        UpdateUIPanelPositions(state.frame)
    end
end

local function RestoreNativePointsOnly()
    local native = state.nativeState
    if not native then return end
    RestorePoints(native.points)
    RefreshUIPanelPosition()
    state.positionOwned = false
end

local function RestoreNativeUnsafe()
    local frame = state.frame
    local native = state.nativeState
    if not frame or not native then return end

    state.applying = true
    if state.dragging and frame.StopMovingOrSizing then
        frame:StopMovingOrSizing()
    end
    state.dragging = false

    if frame:GetScale() ~= native.scale then
        frame:SetScale(native.scale)
    end
    if frame.SetMovable then frame:SetMovable(native.movable) end
    if frame.SetClampedToScreen then frame:SetClampedToScreen(native.clamped) end
    RestorePoints(native.points)
    RefreshUIPanelPosition()

    state.applying = false
    state.positionOwned = false
    state.nativeState = nil
    state.nativeCaptured = false
end

RestoreNativeNow = function()
    if not state.nativeCaptured then
        state.pendingRestore = false
        UpdateRegenRegistration()
        return true
    end
    if InCombatLockdownSafe() then
        QueueRestore()
        return false
    end

    local ok = pcall(RestoreNativeUnsafe)
    if not ok then
        state.applying = false
        state.restoreFailures = state.restoreFailures + 1
        IncrementStat("restoreFailures")
    end
    state.pendingRestore = false
    UpdateRegenRegistration()
    return ok
end

local function ComputeCenterOffsets(frame)
    local centerX, centerY = frame:GetCenter()
    local parentWidth, parentHeight = UIParent:GetSize()
    if not centerX or not centerY or not parentWidth or not parentHeight then return nil end

    local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    local parentScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if not frameScale or frameScale <= 0 then frameScale = 1 end
    if not parentScale or parentScale <= 0 then parentScale = 1 end
    local ratio = frameScale / parentScale

    local x = centerX * ratio - parentWidth / 2
    local y = centerY * ratio - parentHeight / 2
    local halfWidth = frame:GetWidth() * ratio / 2
    local halfHeight = frame:GetHeight() * ratio / 2

    if halfWidth * 2 >= parentWidth then
        x = 0
    else
        x = Clamp(x, -parentWidth / 2 + halfWidth, parentWidth / 2 - halfWidth)
    end
    if halfHeight * 2 >= parentHeight then
        y = 0
    else
        y = Clamp(y, -parentHeight / 2 + halfHeight, parentHeight / 2 - halfHeight)
    end
    return x, y
end

local function StoreCenterPosition(x, y)
    local worldMap = GetWorldMapDB()
    if not worldMap or not x or not y then return false end
    worldMap.position = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = math_floor(x * 10 + 0.5) / 10,
        y = math_floor(y * 10 + 0.5) / 10,
    }
    return true
end

local function CaptureAndStorePosition()
    if not config.rememberPosition or IsMaximized(state.frame) then return false end
    local x, y = ComputeCenterOffsets(state.frame)
    return StoreCenterPosition(x, y)
end

local function PointsMatchCenter(frame, x, y)
    if frame:GetNumPoints() ~= 1 then return false end
    local point, relativeTo, relativePoint, currentX, currentY = frame:GetPoint(1)
    return point == "CENTER"
        and relativeTo == UIParent
        and relativePoint == "CENTER"
        and type(currentX) == "number"
        and type(currentY) == "number"
        and math_abs(currentX - x) <= POSITION_EPSILON
        and math_abs(currentY - y) <= POSITION_EPSILON
end

local function ApplyCenterPosition(x, y)
    local frame = state.frame
    if PointsMatchCenter(frame, x, y) then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function ApplyStoredPosition()
    local worldMap = GetWorldMapDB()
    local position = worldMap and worldMap.position
    if type(position) ~= "table" then
        state.positionOwned = false
        return
    end

    local point = position.point or position[1]
    local relativePoint = position.relativePoint or position[3] or point
    local x = tonumber(position.x ~= nil and position.x or position[4]) or 0
    local y = tonumber(position.y ~= nil and position.y or position[5]) or 0
    if not VALID_POINTS[point] then point = "CENTER" end
    if not VALID_POINTS[relativePoint] then relativePoint = point end

    if point == "CENTER" and relativePoint == "CENTER" then
        local frame = state.frame
        local parentWidth, parentHeight = UIParent:GetSize()
        local frameScale = frame:GetEffectiveScale()
        local parentScale = UIParent:GetEffectiveScale()
        local ratio = parentScale > 0 and frameScale / parentScale or 1
        local halfWidth = frame:GetWidth() * ratio / 2
        local halfHeight = frame:GetHeight() * ratio / 2
        if halfWidth * 2 >= parentWidth then
            x = 0
        else
            x = Clamp(x, -parentWidth / 2 + halfWidth, parentWidth / 2 - halfWidth)
        end
        if halfHeight * 2 >= parentHeight then
            y = 0
        else
            y = Clamp(y, -parentHeight / 2 + halfHeight, parentHeight / 2 - halfHeight)
        end
        ApplyCenterPosition(x, y)
    else
        local frame = state.frame
        frame:ClearAllPoints()
        frame:SetPoint(point, UIParent, relativePoint, x, y)
        local centerX, centerY = ComputeCenterOffsets(frame)
        if centerX and centerY then
            StoreCenterPosition(centerX, centerY)
            ApplyCenterPosition(centerX, centerY)
        end
    end
    state.positionOwned = true
end

local function UpdateDragHandle()
    local handle = state.dragHandle
    if not handle then return end
    local shown = state.enabled
        and state.frame
        and state.frame:IsShown()
        and config.rememberPosition
        and not IsMaximized(state.frame)
    handle:SetShown(shown == true)
end

local function ApplyFrameStateUnsafe()
    local frame = state.frame
    if not frame or not frame:IsShown() then return end
    if not CaptureNativeState() then return end

    state.applying = true
    local targetScale = IsMaximized(frame) and 1 or config.scale
    if math_abs(frame:GetScale() - targetScale) > 0.0001 then
        frame:SetScale(targetScale)
    end

    if IsMaximized(frame) then
        local native = state.nativeState
        if native then
            if frame.SetMovable then frame:SetMovable(native.movable) end
            if frame.SetClampedToScreen then frame:SetClampedToScreen(native.clamped) end
        end
    elseif config.rememberPosition then
        if frame.SetMovable then frame:SetMovable(true) end
        if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
        ApplyStoredPosition()
    else
        if state.positionOwned then RestoreNativePointsOnly() end
        local native = state.nativeState
        if native then
            if frame.SetMovable then frame:SetMovable(native.movable) end
            if frame.SetClampedToScreen then frame:SetClampedToScreen(native.clamped) end
        end
    end
    state.applying = false

    UpdateDragHandle()
    StartCoordinateDriver()
end

ApplyNow = function()
    state.pendingRefresh = false
    UpdateRegenRegistration()
    if not state.enabled or state.applying or state.dragging then return false end
    if InCombatLockdownSafe() then
        QueueRefresh()
        return false
    end

    local ok = pcall(ApplyFrameStateUnsafe)
    if not ok then
        state.applying = false
        state.restoreFailures = state.restoreFailures + 1
        IncrementStat("restoreFailures")
    end
    return ok
end

local function RequestApply()
    if not state.enabled or state.applying or state.dragging then return end
    if InCombatLockdownSafe() then
        QueueRefresh()
    else
        ApplyNow()
    end
end

local function OnDragStartCallback()
    if not state.enabled
        or not config.rememberPosition
        or IsMaximized(state.frame)
        or InCombatLockdownSafe()
    then
        return false
    end
    state.dragging = true
    return true
end

local function OnDragStop()
    if not state.dragging then return end
    state.dragging = false
    if not state.enabled then return end
    CaptureAndStorePosition()
    RequestApply()
end

local function CreateVisuals(frame)
    if state.coordinateOverlay and state.dragHandle then return true end
    if not GUI2 or not GUI2.CreateFrame or not GUI2.CreateText then return false end

    if not state.coordinateOverlay then
        local overlay = GUI2:CreateFrame(frame, {
            kind = "YMapWorldMapCoordinates",
            mouse = false,
            hidden = true,
        })
        overlay:SetAllPoints(frame.ScrollContainer)
        overlay:SetFrameLevel((frame.ScrollContainer:GetFrameLevel() or 0) + 50)

        local playerText = GUI2:CreateText(overlay, "", "font.size.sm", "color.text.primary", "LEFT")
        playerText:SetSize(220, 18)
        playerText:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 12, 9)
        playerText:Hide()

        local cursorText = GUI2:CreateText(overlay, "", "font.size.sm", "color.text.primary", "RIGHT")
        cursorText:SetSize(220, 18)
        cursorText:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -12, 9)
        cursorText:Hide()

        state.coordinateOverlay = overlay
        state.playerText = playerText
        state.cursorText = cursorText
    end

    if not state.dragHandle then
        local borderFrame = frame.BorderFrame
        local titleContainer = borderFrame and borderFrame.TitleContainer
        if not borderFrame or not titleContainer then return false end

        local handle = GUI2:CreateFrame(borderFrame, {
            type = "Button",
            template = "PanelDragBarTemplate",
            kind = "YMapWorldMapDragHandle",
            hidden = true,
        })
        handle:SetHeight(titleContainer:GetHeight() or 20)
        handle:SetPoint("LEFT", titleContainer, "LEFT", 0, 0)
        local minimizeFrame = borderFrame.MaximizeMinimizeFrame
        if minimizeFrame then
            handle:SetPoint("RIGHT", minimizeFrame, "LEFT", -3, 0)
        else
            handle:SetPoint("RIGHT", titleContainer, "RIGHT", 0, 0)
        end
        handle:SetFrameLevel(titleContainer:GetFrameLevel() + 1)
        if handle.Init then handle:Init(frame) end
        if handle.SetOnDragStartCallback then
            handle:SetOnDragStartCallback(OnDragStartCallback)
        end
        handle:HookScript("OnDragStop", OnDragStop)
        state.dragHandle = handle
    end
    return true
end

local function OnWorldMapShow(frame)
    if not state.enabled or frame ~= state.frame then return end
    -- 原生 OnShow 已重新注册默认渐隐，本次显示需要重新应用自定义值。
    state.movementFadeAlpha = nil
    RefreshMovementFade()
    RequestApply()
end

local function OnWorldMapHide(frame)
    if frame ~= state.frame then return end
    ReleaseMovementFade(false)
    StopCoordinateDriver()
    HideCoordinateVisuals()
end

local function OnDisplayStateChanged(frame)
    if not state.enabled or frame ~= state.frame then return end
    -- 首次显示必须等原生 OnShow 完整结束后再捕获恢复基线。
    if not state.nativeCaptured then return end
    RequestApply()
end

local function OnScaleChanged(frame, scale)
    if not state.enabled
        or frame ~= state.frame
        or state.applying
        or state.dragging
        or not state.nativeCaptured
        or not frame:IsShown()
    then
        return
    end
    local targetScale = IsMaximized(frame) and 1 or config.scale
    if type(scale) == "number" and math_abs(scale - targetScale) > 0.0001 then
        RequestApply()
    end
end

local function OnUIPanelPositionsUpdated()
    local frame = state.frame
    if not state.enabled
        or not state.nativeCaptured
        or state.applying
        or state.dragging
        or not frame
        or not frame:IsShown()
        or IsMaximized(frame)
    then
        return
    end
    RequestApply()
end

local function InstallHooks(frame)
    if state.hookedFrame == frame then return true end
    frame:HookScript("OnShow", OnWorldMapShow)
    frame:HookScript("OnHide", OnWorldMapHide)
    if frame.SynchronizeDisplayState then
        hooksecurefunc(frame, "SynchronizeDisplayState", OnDisplayStateChanged)
    end
    if frame.SetScale then
        hooksecurefunc(frame, "SetScale", OnScaleChanged)
    end
    if not state.globalHookInstalled and type(UpdateUIPanelPositions) == "function" then
        hooksecurefunc("UpdateUIPanelPositions", OnUIPanelPositionsUpdated)
        state.globalHookInstalled = true
    end
    state.hookedFrame = frame
    state.hooksInstalled = true
    return true
end

local function PrepareAttachedFrame()
    local frame = state.frame
    if not frame then return false end
    if InCombatLockdownSafe() then
        QueueRefresh()
        return false
    end
    if not InstallHooks(frame) then return false end
    RefreshMovementFade()
    if not CreateVisuals(frame) then return false end
    if frame:IsShown() then
        return ApplyNow()
    end
    HideCoordinateVisuals()
    UpdateDragHandle()
    return true
end

AttachWorldMap = function(frame)
    if not frame then return false end
    StopWaitingForAddon()
    state.frame = frame
    state.attached = true
    return PrepareAttachedFrame()
end

local function Activate()
    if state.enabled then return true end
    state.enabled = true
    state.pendingRestore = false
    UpdateRegenRegistration()

    local frame = _G.WorldMapFrame
    if frame then
        AttachWorldMap(frame)
    else
        WaitForAddon()
    end
    return true
end

local function Deactivate()
    if not state.enabled and not state.pendingRestore then
        StopWaitingForAddon()
        return true
    end

    state.enabled = false
    ReleaseMovementFade(true)
    state.pendingRefresh = false
    StopWaitingForAddon()
    StopCoordinateDriver()
    HideCoordinateVisuals()
    if state.dragHandle then state.dragHandle:Hide() end

    if state.nativeCaptured then
        if InCombatLockdownSafe() then
            QueueRestore()
        else
            RestoreNativeNow()
        end
    else
        state.pendingRestore = false
        UpdateRegenRegistration()
    end
    return true
end

RefreshEffectiveState = function()
    ReadConfig()
    local shouldEnable = state.requestedEnabled and config.enabled and (YUI.IsForever or YUI.IsRetail) == true
    if shouldEnable then
        Activate()
        if state.attached then PrepareAttachedFrame() end
        RefreshMovementFade()
    else
        Deactivate()
    end
    return state.enabled
end

local function OnEvent(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= "Blizzard_WorldMap" then return end
        StopWaitingForAddon()
        if state.enabled then
            AttachWorldMap(_G.WorldMapFrame)
        end
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if InCombatLockdownSafe() then return end
        if state.pendingRestore and not state.enabled then
            RestoreNativeNow()
        elseif state.enabled then
            state.pendingRestore = false
            state.pendingRefresh = false
            UpdateRegenRegistration()
            if state.frame then PrepareAttachedFrame() end
        else
            state.pendingRefresh = false
            state.pendingRestore = false
            UpdateRegenRegistration()
        end
    end
end

eventFrame:SetScript("OnEvent", OnEvent)

function WorldMap:Enable()
    state.requestedEnabled = true
    return RefreshEffectiveState()
end

function WorldMap:Disable()
    state.requestedEnabled = false
    return Deactivate()
end

function WorldMap:Refresh()
    local wasPlayerCoordinates = config.playerCoordinates
    local wasCursorCoordinates = config.cursorCoordinates
    local oldPlayerLabel = config.playerLabel
    local oldCursorLabel = config.cursorLabel
    local enabled = RefreshEffectiveState()

    if wasPlayerCoordinates ~= config.playerCoordinates or oldPlayerLabel ~= config.playerLabel then
        HidePlayerText()
    end
    if wasCursorCoordinates ~= config.cursorCoordinates or oldCursorLabel ~= config.cursorLabel then
        HideCursorText()
    end
    if enabled and state.attached then RequestApply() end
    return enabled
end

function WorldMap:ResetPosition()
    local worldMap = GetWorldMapDB()
    if not worldMap then return false end
    worldMap.position = nil

    if state.enabled and state.nativeCaptured and not IsMaximized(state.frame) then
        if InCombatLockdownSafe() then
            QueueRefresh()
        else
            state.applying = true
            RestoreNativePointsOnly()
            state.applying = false
            RequestApply()
        end
    end
    return true
end

function WorldMap:GetStats(target)
    target = type(target) == "table" and target or {}
    target.worldMapDriverActive = state.driverActive
    target.coordinateDriverActive = coordinateDriverActive
    target.minimapCoordinateConsumerActive = minimapConsumerActive
    target.worldMapCursorReads = SharedStats and SharedStats.worldMapCursorReads or state.cursorReads
    target.worldMapPlayerReads = SharedStats and SharedStats.worldMapPlayerReads or state.playerReads
    target.worldMapTextWrites = SharedStats and SharedStats.worldMapTextWrites or state.textWrites
    target.worldMapEnabled = state.enabled
    target.worldMapAttached = state.attached
    target.worldMapWaitingForAddon = state.waitingForAddon
    target.worldMapPendingRefresh = state.pendingRefresh
    target.worldMapPendingRestore = state.pendingRestore
    target.worldMapRestoreFailures = state.restoreFailures
    return target
end

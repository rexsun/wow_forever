local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable

if not YUI or not YUI.IsRetail then return end

local YMap = YUI.YMap
local GUI2 = YUI.GUI2
local Event = YUI.Event
local F = YUI.F
local API = YUI.API and YUI.API.EventScheduler
local WorldQuestAPI = YUI.API and YUI.API.WorldQuest
local Security = YUI.API and YUI.API.Security
local Model = YUI.WorldEventTrackerModel
local NavigationFallbacks = YUI.WorldEventTrackerNavigationFallbacks or {}
local Locale = YUI.Locale and YUI.Locale:Get("WorldEventTracker") or {}

if not YMap or not GUI2 or not Event or not F or not API or not WorldQuestAPI or not Model then return end

local DEFAULTS = {
    summaryRows = 2,
    showRewarded = true,
    showSeasonCurrencies = true,
    defaultCollapsed = false,
    summarySeriesEnabled = {},
    discoveredSeries = {},
}
local MAP_ADDON = "Blizzard_WorldMap"
local SUMMARY_MIN_WIDTH = 360
local SUMMARY_MAXIMIZED_LEFT_RATIO = 0.20
local SUMMARY_HEADER_HEIGHT = 28
local SUMMARY_COLLAPSED_HEIGHT = SUMMARY_HEADER_HEIGHT + 4
local SUMMARY_ROW_HEIGHT = 52
local SUMMARY_GAP = 6
local SUMMARY_ROW_MIN = 1
local SUMMARY_ROW_MAX = 3
local SUMMARY_PER_ROW_MIN = 2
local SUMMARY_PER_ROW_MAX = 4
local SUMMARY_ITEM_MAX = SUMMARY_ROW_MAX * SUMMARY_PER_ROW_MAX
local SCHEDULE_MAX_HEIGHT = 420
local SCHEDULE_ROW_HEIGHT = 48
local SCHEDULE_HEADING_HEIGHT = 24
local ROTATION_CLUSTER_LIMIT = 5
local IMMINENT_WINDOW_SECONDS = 1800
local SUMMARY_TIME_COLUMN_WIDTH = 100
local SUMMARY_TEXT_RIGHT_RESERVE = 88
local SCHEDULE_TIME_COLUMN_WIDTH = 116
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local CLAIMED_CHECKMARK = F:GetAtlasString("event-scheduler-green-checkmark", 18, 18, 0, -1)
local SEASON_CURRENCY_BAR_MIN_WIDTH = 980
local SEASON_CURRENCY_ITEM_FALLBACK_WIDTH = 116
local SEASON_CURRENCY_ITEM_HEIGHT = 20
local SEASON_CURRENCY_ICON_SIZE = 16
local SEASON_CURRENCY_TEXT_GAP = 2
local SEASON_CURRENCY_GAP = 6
local SEASON_CURRENCIES = {
    { id = 3446, colorQuality = 5, labelKey = "currency.myth", fallbackName = "Myth" },
    { id = 3445, colorQuality = 4, labelKey = "currency.hero", fallbackName = "Hero" },
    { id = 3444, colorQuality = 3, labelKey = "currency.champion", fallbackName = "Champion" },
    { id = 3443, colorQuality = 2, labelKey = "currency.veteran", fallbackName = "Veteran" },
}
local SEASON_CURRENCY_IDS = {
    [3446] = true,
    [3445] = true,
    [3444] = true,
    [3443] = true,
}
local runtime = {
    enabled = false,
    hooked = false,
    mapCallbacksRegistered = false,
    schedulerAttached = false,
    profileCallbacksRegistered = false,
    expanded = false,
    summaryCollapsed = false,
    eventOwner = {},
    addonOwner = {},
    mapEventOwner = {},
    boundaryTimer = nil,
    questRefreshTimer = nil,
    countdownTicker = nil,
    pingTimer = nil,
    pendingPingLocation = nil,
    pingPin = nil,
    countdownRows = {},
    countdownRowCount = 0,
    snapshot = nil,
    worldBossSnapshot = nil,
    eventMapIDs = {},
    seenEventMapIDs = {},
    eventLocationCache = {},
    model = nil,
    frame = nil,
}

local RefreshFromSnapshot

local function T(key, fallback)
    local value = Locale[key]
    if type(value) == "string" and value ~= "" then return value end
    return fallback or key
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return false end
    return true, a, b, c
end

local function IsSecret(value)
    if Security and type(Security.IsSecretValue) == "function" then
        local ok, result = pcall(Security.IsSecretValue, value)
        if ok then return result == true end
    end
    if type(issecretvalue) == "function" then
        local ok, result = pcall(issecretvalue, value)
        if ok then return result == true end
    end
    return false
end

local function SafeField(value, key)
    if type(value) ~= "table" or IsSecret(value) then return nil end
    local ok, result = pcall(function() return value[key] end)
    if not ok or IsSecret(result) then return nil end
    return result
end

local function SafeNumber(value, minimum)
    if type(value) ~= "number" or IsSecret(value) then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    if minimum ~= nil and value < minimum then return nil end
    return value
end

local function SafeInteger(value, minimum)
    value = SafeNumber(value, minimum)
    return value and math.floor(value) or nil
end

local function FormatCurrencyAmount(value)
    value = SafeInteger(value, 0) or 0
    if type(BreakUpLargeNumbers) == "function" then
        local ok, text = pcall(BreakUpLargeNumbers, value)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return tostring(value)
end

local function ClampSummaryRows(value)
    value = math.floor(tonumber(value) or DEFAULTS.summaryRows)
    return math.max(SUMMARY_ROW_MIN, math.min(SUMMARY_ROW_MAX, value))
end

local function ClampSummaryPerRow(value)
    value = math.floor(tonumber(value) or 4)
    return math.max(SUMMARY_PER_ROW_MIN, math.min(SUMMARY_PER_ROW_MAX, value))
end

local function GetConfig()
    local config = YMap:GetDB().worldEvents
    if config.summaryPerRow == nil then
        config.summaryPerRow = ClampSummaryPerRow(nil)
    end
    config.summaryRows = ClampSummaryRows(config.summaryRows)
    config.summaryPerRow = ClampSummaryPerRow(config.summaryPerRow)
    config.showRewarded = config.showRewarded ~= false
    config.showSeasonCurrencies = config.showSeasonCurrencies ~= false
    config.defaultCollapsed = config.defaultCollapsed == true
    if type(config.summarySeriesEnabled) ~= "table" then config.summarySeriesEnabled = {} end
    if type(config.discoveredSeries) ~= "table" then config.discoveredSeries = {} end
    return config
end

local function ClearMap(map)
    for key in pairs(map) do map[key] = nil end
end

local function GetClientLocale()
    if type(GetLocale) == "function" then
        local ok, value = pcall(GetLocale)
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    return "enUS"
end

local function ResolveEventLocationCached(areaPoiID)
    local cached = runtime.eventLocationCache[areaPoiID]
    if cached ~= nil then return cached ~= false and cached or nil end
    local location = API.GetEventLocation(areaPoiID)
    runtime.eventLocationCache[areaPoiID] = location or false
    return location
end

local function CollectEventMapIDsFromList(list)
    list = type(list) == "table" and list or {}
    for index = 1, #list do
        local areaPoiID = list[index] and list[index].areaPoiID
        local location = areaPoiID and ResolveEventLocationCached(areaPoiID) or nil
        local mapID = location and (location.uiMapID or location.linkedUiMapID) or nil
        if type(mapID) == "number" and mapID >= 1 and not runtime.seenEventMapIDs[mapID] then
            runtime.seenEventMapIDs[mapID] = true
            runtime.eventMapIDs[#runtime.eventMapIDs + 1] = mapID
        end
    end
end

local function CollectEventMapIDs(snapshot)
    for index = #runtime.eventMapIDs, 1, -1 do runtime.eventMapIDs[index] = nil end
    ClearMap(runtime.seenEventMapIDs)
    ClearMap(runtime.eventLocationCache)
    CollectEventMapIDsFromList(snapshot and snapshot.ongoing)
    CollectEventMapIDsFromList(snapshot and snapshot.scheduled)
    return runtime.eventMapIDs
end

local function RememberDiscoveredSeries(config, model)
    local locale = GetClientLocale()
    local series = model and model.series or {}
    for index = 1, #series do
        local item = series[index]
        if item.key ~= "world-boss" and type(item.label) == "string" and item.label ~= "" then
            local entry = config.discoveredSeries[item.key]
            if type(entry) ~= "table" then
                entry = { labels = {} }
                config.discoveredSeries[item.key] = entry
            elseif type(entry.labels) ~= "table" then
                entry.labels = {}
            end
            if entry.labels[locale] ~= item.label then entry.labels[locale] = item.label end
        end
    end
end

local function GetScheduledDisplayLimit()
    local value
    local ok = pcall(function()
        value = Constants and Constants.EventScheduler
            and Constants.EventScheduler.SCHEDULED_EVENT_FUTURE_LIMIT
    end)
    value = ok and tonumber(value) or nil
    if not value or value < 1 then return 12 end
    return math.max(1, math.floor(value))
end

local function IsShown(frame)
    return frame and type(frame.IsShown) == "function" and frame:IsShown() == true
end

local function GetServerNow()
    if type(GetServerTime) == "function" then
        local ok, value = pcall(GetServerTime)
        if ok and type(value) == "number" then return value end
    end
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and type(value) == "number" then return value end
    end
    return 0
end

local function GetFrameNow()
    if type(GetTime) == "function" then
        local ok, value = pcall(GetTime)
        if ok and type(value) == "number" then return value end
    end
    return 0
end

local function FormatRemaining(seconds)
    return Model.FormatClock(seconds, T("state.days_clock", "%dd %02d:%02d:%02d"))
end

local function FormatStartTime(timestamp, includeDate)
    if type(timestamp) ~= "number" or type(date) ~= "function" then
        return T("state.start_unknown", "Start time unavailable")
    end
    local ok, text = pcall(date, includeDate and "%m/%d %H:%M" or "%H:%M", timestamp)
    if ok and type(text) == "string" then return text end
    return T("state.start_unknown", "Start time unavailable")
end

local function CreateText(parent, size, color, justify)
    local text = GUI2:CreateText(parent, "", size or "font.size.sm", color or "color.text.primary", justify or "LEFT")
    text:SetWordWrap(false)
    return text
end

local function DisableTimeDriver(row)
    if row.durationObject then
        SafeCall(row.durationObject.Reset, row.durationObject)
        if row.progress and row.progress.SetTimerDuration then
            SafeCall(row.progress.SetTimerDuration, row.progress, row.durationObject)
        end
    end
    if row.progress then
        SafeCall(row.progress.SetMinMaxValues, row.progress, 0, 1)
        SafeCall(row.progress.SetValue, row.progress, 0)
        row.progress:Hide()
    end
    row.timeDriven = false
    row.countdownTarget = nil
    row.lastCountdownText = nil
end

local function DisableAllTimeDrivers()
    local frame = runtime.frame
    if not frame then return end
    for index = 1, #frame.summaryRows do DisableTimeDriver(frame.summaryRows[index]) end
    for index = 1, #frame.scheduleRows do DisableTimeDriver(frame.scheduleRows[index]) end
end

local function CancelCountdownTicker()
    local ticker = runtime.countdownTicker
    runtime.countdownTicker = nil
    if ticker and type(ticker.Cancel) == "function" then pcall(ticker.Cancel, ticker) end
end

local function ClearCountdownRows()
    for index = 1, runtime.countdownRowCount do runtime.countdownRows[index] = nil end
    runtime.countdownRowCount = 0
end

local function UpdateCountdownRows()
    local serverNow = GetServerNow()
    for index = 1, runtime.countdownRowCount do
        local row = runtime.countdownRows[index]
        local target = row and row.countdownTarget
        if target then
            local secondsLeft = math.max(0, math.ceil(target - serverNow))
            local text = FormatRemaining(secondsLeft)
            if text ~= row.lastCountdownText then
                row.timeSecondary:SetText(text)
                row.lastCountdownText = text
            end
        end
    end
end

local function RefreshCountdownTicker()
    CancelCountdownTicker()
    ClearCountdownRows()
    local frame = runtime.frame
    if not runtime.enabled or not frame or not IsShown(frame.map) then return end

    for index = 1, #frame.summaryRows do
        local row = frame.summaryRows[index]
        if row.countdownTarget and IsShown(row) then
            runtime.countdownRowCount = runtime.countdownRowCount + 1
            runtime.countdownRows[runtime.countdownRowCount] = row
        end
    end
    if runtime.expanded and IsShown(frame.schedule) then
        for index = 1, #frame.scheduleRows do
            local row = frame.scheduleRows[index]
            if row.countdownTarget and IsShown(row) then
                runtime.countdownRowCount = runtime.countdownRowCount + 1
                runtime.countdownRows[runtime.countdownRowCount] = row
            end
        end
    end

    if runtime.countdownRowCount == 0 then return end
    UpdateCountdownRows()
    if C_Timer and type(C_Timer.NewTicker) == "function" then
        local ok, ticker = pcall(C_Timer.NewTicker, 1, UpdateCountdownRows)
        if ok then runtime.countdownTicker = ticker end
    end
end

local function EnsureDurationObject(row)
    if row.durationObject then return true end
    if not (C_DurationUtil and type(C_DurationUtil.CreateDuration) == "function") then return false end
    local durationOk, durationObject = pcall(C_DurationUtil.CreateDuration)
    if not durationOk or not durationObject then return false end
    row.durationObject = durationObject
    return true
end

local function GetProgressSpan(item, now)
    local startTime, endTime = item.startTime, item.endTime
    if item.displayInfo.hideTimeLeft == true or type(startTime) ~= "number" then return nil end
    if item.ongoing and type(endTime) == "number" and endTime > startTime then
        return startTime, endTime, "color.state.success"
    end
    if not item.ongoing and startTime > now and startTime - now <= IMMINENT_WINDOW_SECONDS then
        return startTime - IMMINENT_WINDOW_SECONDS, startTime, "color.state.warning"
    end
end

local function SetProgressColor(row, colorKey)
    row.progressColorKey = colorKey
    row.progress:SetStatusBarColor(GUI2:GetColor(colorKey))
end

local function SetStaticProgress(row, item, now)
    local progressStart, progressEnd, colorKey = GetProgressSpan(item, now)
    if not progressStart then row.progress:Hide() return end
    row.progress:SetMinMaxValues(0, 1)
    row.progress:SetValue(math.max(0, math.min(1, (now - progressStart) / (progressEnd - progressStart))))
    SetProgressColor(row, colorKey)
    row.progress:Show()
end

local function ConfigureTimeDriver(row, item, dynamic, allowProgress, serverNow, frameNow)
    DisableTimeDriver(row)
    local displayInfo = item.displayInfo or {}
    local startTime, endTime = item.startTime, item.endTime
    local targetTime
    if item.ongoing then
        targetTime = type(endTime) == "number" and endTime or nil
    else
        targetTime = type(startTime) == "number" and startTime or nil
    end

    local secondsLeft = targetTime and math.max(0, targetTime - serverNow)
    if not secondsLeft and item.ongoing and item.location then
        secondsLeft = item.location.secondsLeft
    end
    if displayInfo.hideTimeLeft == true then secondsLeft = nil end

    if item.ongoing and item.rewardsClaimed == true then
        row.timePrimary:SetText(CLAIMED_CHECKMARK)
        GUI2:SetTextColorKey(row.timePrimary, "color.state.success")
    elseif item.ongoing then
        row.timePrimary:SetText(T("state.ongoing", "Ongoing"))
        GUI2:SetTextColorKey(row.timePrimary, "color.state.success")
    else
        row.timePrimary:SetText(string.format(T("state.starts", "Starts %s"), FormatStartTime(startTime, item.group == "later")))
        GUI2:SetTextColorKey(row.timePrimary, "color.state.warning")
    end

    if displayInfo.hideTimeLeft == true then
        row.timeSecondary:SetText("")
    elseif type(secondsLeft) == "number" then
        local text = FormatRemaining(secondsLeft)
        row.timeSecondary:SetText(text)
        if dynamic and secondsLeft > 0 then
            row.countdownTarget = serverNow + secondsLeft
            row.lastCountdownText = text
        end
    else
        row.timeSecondary:SetText("")
    end

    if not allowProgress then row.progress:Hide() return end

    local progressStart, progressEnd, progressColor = GetProgressSpan(item, serverNow)
    if not progressStart then row.progress:Hide() return end

    if not EnsureDurationObject(row) then
        SetStaticProgress(row, item, serverNow)
        return
    end
    local frameStart = frameNow + (progressStart - serverNow)
    local frameTarget = frameNow + (progressEnd - serverNow)
    if SafeCall(row.durationObject.SetTimeSpan, row.durationObject, frameStart, frameTarget)
        and SafeCall(row.progress.SetTimerDuration, row.progress, row.durationObject)
    then
        SetProgressColor(row, progressColor)
        row.progress:Show()
        row.timeDriven = true
    else
        SetStaticProgress(row, item, serverNow)
    end
end

local function SetEventIcon(row, item)
    local location = item.location or {}
    local atlas = item.displayInfo and item.displayInfo.overrideAtlas or location.atlasName
    local atlasApplied = false
    if type(atlas) == "string" and row.icon.SetAtlas then
        atlasApplied = SafeCall(row.icon.SetAtlas, row.icon, atlas, false)
    end
    if not atlasApplied then
        row.icon:SetTexture(DEFAULT_ICON)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    elseif row.icon.SetTexCoord then
        row.icon:SetTexCoord(0, 1, 0, 1)
    end
    if row.icon.SetDesaturated then row.icon:SetDesaturated(item.rewardsClaimed == true) end
end

local function HideTooltip()
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
end

local function CancelPingTimer()
    local timer = runtime.pingTimer
    runtime.pingTimer = nil
    runtime.pendingPingLocation = nil
    if timer and type(timer.Cancel) == "function" then pcall(timer.Cancel, timer) end
end

local function ReleasePingPin()
    local pin = runtime.pingPin
    runtime.pingPin = nil
    if not pin then return end
    SafeCall(pin.Stop, pin)
    local map = runtime.frame and runtime.frame.map
    if map and type(map.RemovePin) == "function" then SafeCall(map.RemovePin, map, pin) end
end

local function IsUsableNavigationLocation(location)
    if type(location) ~= "table" then return false end
    local x, y = location.positionX, location.positionY
    local mapID = location.uiMapID or location.linkedUiMapID
    return type(mapID) == "number"
        and type(x) == "number" and x > 0 and x < 1
        and type(y) == "number" and y > 0 and y < 1
end

local function TryPingLocation(location)
    if not IsUsableNavigationLocation(location) then return false end
    local x, y = location.positionX, location.positionY
    local mapID = location.uiMapID or location.linkedUiMapID

    local map = runtime.frame and runtime.frame.map
    if not map or not IsShown(map) then return false end
    if type(map.GetMapID) == "function" then
        local ok, currentMapID = SafeCall(map.GetMapID, map)
        if ok and type(currentMapID) == "number" and currentMapID ~= mapID then return false end
    end
    local pin = runtime.pingPin
    if not pin and type(map.AcquirePin) == "function" then
        local ok, acquired = SafeCall(map.AcquirePin, map, "MapPinPingTemplate")
        if ok then
            pin = acquired
            runtime.pingPin = pin
            SafeCall(pin.UseFrameLevelType, pin, "PIN_FRAME_LEVEL_QUEST_PING")
        end
    end
    if pin then
        SafeCall(pin.Stop, pin)
        SafeCall(pin.SetNumLoops, pin, 1)
        SafeCall(pin.PlayAt, pin, x, y)
    end
    return true
end

local function CompleteDeferredPing()
    runtime.pingTimer = nil
    local location = runtime.pendingPingLocation
    runtime.pendingPingLocation = nil
    if runtime.enabled and runtime.frame and IsShown(runtime.frame.map) then TryPingLocation(location) end
end

local function PingLocation(location)
    CancelPingTimer()
    if TryPingLocation(location) then return end
    if not (C_Timer and type(C_Timer.NewTimer) == "function") then return end
    runtime.pendingPingLocation = location
    local ok, timer = pcall(C_Timer.NewTimer, 0, CompleteDeferredPing)
    if ok and timer then
        runtime.pingTimer = timer
    else
        runtime.pendingPingLocation = nil
    end
end

local function OpenWorldEventSettings()
    HideTooltip()
    runtime.expanded = false
    if runtime.frame then
        runtime.frame.schedule:Hide()
        for index = 1, #runtime.frame.scheduleRows do
            DisableTimeDriver(runtime.frame.scheduleRows[index])
        end
        RefreshCountdownTicker()
    end
    YMap:OpenSettings("worldEvents")
end

local function GetNavigationLocation(item)
    if type(item) ~= "table" then return nil end
    local fallback = NavigationFallbacks[item.areaPoiID]
    if IsUsableNavigationLocation(fallback) then return fallback end
    if IsUsableNavigationLocation(item.location) then return item.location end
    return nil
end

local function ShowEventTooltip(row)
    local item = row.item
    if not item or not GameTooltip then return end
    local location = item.location or {}
    local navigationLocation = GetNavigationLocation(item)
    GameTooltip:ClearLines()
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(location.name or T("event.unknown", "World Event"), 1, 0.82, 0.2)
    if location.zoneName then GameTooltip:AddLine(location.zoneName, 0.78, 0.82, 0.9) end
    if item.displayInfo.hideDescription ~= true and location.description then
        GameTooltip:AddLine(location.description, 1, 1, 1, true)
    end
    if item.rewardsClaimed == true then
        GameTooltip:AddLine(T("tooltip.claimed", "Rewards claimed"), 0.45, 0.9, 0.55)
    end
    local tracked = item.source == "worldBoss" and WorldQuestAPI.GetTrackedQuestID() or API.GetTrackedAreaPOI()
    local trackedIdentity = item.source == "worldBoss" and item.questID or item.areaPoiID
    if tracked == trackedIdentity then
        GameTooltip:AddLine(T("tooltip.tracked", "Currently tracked"), 0.45, 0.75, 1)
    end
    GameTooltip:AddLine(" ")
    local waypoint = API.GetUserWaypoint()
    local mapID = navigationLocation and (navigationLocation.uiMapID or navigationLocation.linkedUiMapID)
    local sameWaypoint = waypoint and mapID and waypoint.uiMapID == mapID
        and navigationLocation
        and math.abs(waypoint.positionX - navigationLocation.positionX) <= 0.0001
        and math.abs(waypoint.positionY - navigationLocation.positionY) <= 0.0001
    GameTooltip:AddLine(sameWaypoint
        and T("tooltip.left_click_clear", "Left-click: Clear waypoint and locate")
        or T("tooltip.left_click_set", "Left-click: Set waypoint and locate"), 0.65, 0.75, 0.9)
    if item.ongoing then
        GameTooltip:AddLine(item.source == "worldBoss"
            and T("tooltip.right_click_world_boss", "Right-click: Toggle world quest tracking")
            or T("tooltip.right_click", "Right-click: Toggle Area POI tracking"), 0.65, 0.75, 0.9)
    end
    GameTooltip:Show()
end

local function OnRowClick(row, button)
    local item = row.item
    if not item then return end
    if button == "LeftButton" then
        local navigationLocation = GetNavigationLocation(item)
        if item.source == "worldBoss" then
            WorldQuestAPI.ToggleWorldBossWaypoint(item.questID, navigationLocation)
            local opened, _, location = WorldQuestAPI.OpenWorldBoss(item.questID, navigationLocation)
            if opened and IsUsableNavigationLocation(location) then PingLocation(location) end
        else
            API.ToggleEventWaypoint(item.areaPoiID, navigationLocation)
            local opened, _, location = API.OpenEvent(item.areaPoiID, navigationLocation)
            local pingLocation = IsUsableNavigationLocation(location) and location or navigationLocation
            if opened and pingLocation then PingLocation(pingLocation) end
        end
    elseif button == "RightButton" and item.ongoing then
        if item.source == "worldBoss" then
            WorldQuestAPI.ToggleTrackedQuest(item.questID)
        else
            API.ToggleTrackedAreaPOI(item.areaPoiID)
        end
        ShowEventTooltip(row)
    end
end

local function CreateEventRow(parent, compact)
    local row = GUI2:CreateButtonFrame(parent, {
        template = "BackdropTemplate",
        height = compact and SUMMARY_ROW_HEIGHT or SCHEDULE_ROW_HEIGHT,
        surface = "color.surface.raised",
        border = "color.border.subtle",
    })
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local iconSize = compact and 28 or 30
    local timeColumnWidth = compact and SUMMARY_TIME_COLUMN_WIDTH or SCHEDULE_TIME_COLUMN_WIDTH
    local textRightReserve = compact and SUMMARY_TEXT_RIGHT_RESERVE or timeColumnWidth + 12
    local primaryFont = "font.size.md"
    local secondaryFont = "font.size.sm"
    row.icon = GUI2:CreateTexture(row, { width = iconSize, height = iconSize, layer = "ARTWORK" })
    row.icon:SetPoint("LEFT", row, "LEFT", 8, compact and 2 or 0)
    row.name = CreateText(row, primaryFont, "color.text.primary")
    row.name:SetPoint("BOTTOMLEFT", row, "LEFT", iconSize + 15, 1)
    row.name:SetPoint("BOTTOMRIGHT", row, "RIGHT", -textRightReserve, 1)
    row.location = CreateText(row, secondaryFont, "color.text.muted")
    row.location:SetPoint("TOPLEFT", row, "LEFT", iconSize + 15, -1)
    row.location:SetPoint("TOPRIGHT", row, "RIGHT", -textRightReserve, -1)
    row.timePrimary = CreateText(row, primaryFont, "color.text.secondary", "RIGHT")
    row.timePrimary:SetPoint("BOTTOMRIGHT", row, "RIGHT", -8, 1)
    row.timePrimary:SetWidth(timeColumnWidth)
    row.timeSecondary = CreateText(row, secondaryFont, "color.text.muted", "RIGHT")
    row.timeSecondary:SetPoint("TOPRIGHT", row, "RIGHT", -8, -1)
    row.timeSecondary:SetWidth(timeColumnWidth)
    row.progress = GUI2:CreateFrame(row, { type = "StatusBar", height = 3 })
    row.progress:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
    row.progress:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    row.progress:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    row.progress:SetStatusBarColor(GUI2:GetColor("color.state.success"))
    row.progress:Hide()
    row.compact = compact == true
    row:SetScript("OnClick", OnRowClick)
    row:SetScript("OnEnter", ShowEventTooltip)
    row:SetScript("OnLeave", HideTooltip)
    row:Hide()
    return row
end

local function UpdateEventRow(row, item, dynamic, allowProgress, serverNow, frameNow)
    row.item = item
    local location = item.location or {}
    local name = location.name or T("event.unknown", "World Event")
    local locationText = location.zoneName or T("location.unknown", "Location unavailable")
    if row.compact then
        local seriesName, eventName = Model.SplitSeriesName(name)
        if seriesName then
            name = eventName
            locationText = seriesName .. " " .. locationText
        end
    end
    row.name:SetText(name)
    row.location:SetText(locationText)
    SetEventIcon(row, item)
    row:SetAlpha(item.rewardsClaimed == true and 0.55 or 1)
    ConfigureTimeDriver(row, item, dynamic, allowProgress, serverNow, frameNow)
    row:Show()
end

local function CreateHeaderButton(parent, text, width, height)
    return GUI2:CreateButton(parent, text or "", width or 100, height or 22)
end

local function CreateCollapseButton(parent)
    return GUI2:CreateIconButton(parent, {
        size = 22,
        microIcon = "arrow-big-up",
        microIconSize = 16,
        padding = 3,
        iconColor = "color.text.accent",
        preserveIconColor = false,
    })
end

local function SetButtonText(button, value)
    if type(button.SetText) == "function" then
        button:SetText(value or "")
    elseif button.text and type(button.text.SetText) == "function" then
        button.text:SetText(value or "")
    end
end

local function SetSeasonCurrencyTextColor(text, colorQuality, quantity)
    if quantity <= 0 then
        if type(GUI2.SetTextColorKey) == "function" then
            GUI2:SetTextColorKey(text, "color.text.muted")
        end
        return
    end

    local color = type(ITEM_QUALITY_COLORS) == "table" and SafeField(ITEM_QUALITY_COLORS, colorQuality) or nil
    local r = color and SafeNumber(SafeField(color, "r"), 0) or nil
    local g = color and SafeNumber(SafeField(color, "g"), 0) or nil
    local b = color and SafeNumber(SafeField(color, "b"), 0) or nil
    if not (r and g and b) then
        if colorQuality == 5 then
            r, g, b = 1, 0.5, 0
        elseif colorQuality == 4 then
            r, g, b = 0.64, 0.21, 0.93
        elseif colorQuality == 3 then
            r, g, b = 0, 0.44, 0.87
        end
    end
    if r and g and b and type(text.SetTextColor) == "function" then
        text:SetTextColor(r, g, b, 1)
    elseif type(GUI2.SetTextColorKey) == "function" then
        GUI2:SetTextColorKey(text, "color.text.primary")
    end
end

local function MeasureSeasonCurrencyText(text)
    local measure = text and (text.GetUnboundedStringWidth or text.GetStringWidth)
    if type(measure) ~= "function" then return nil end
    local ok, width = SafeCall(measure, text)
    return ok and SafeNumber(width, 0) or nil
end

local function LayoutSeasonCurrencyItems(bar)
    local previous
    local totalWidth = 0
    for index = 1, #bar.items do
        local item = bar.items[index]
        item:ClearAllPoints()
        if item:IsShown() then
            local labelWidth = MeasureSeasonCurrencyText(item.label)
            local valueWidth = MeasureSeasonCurrencyText(item.value)
            local itemWidth = SEASON_CURRENCY_ITEM_FALLBACK_WIDTH
            if labelWidth and valueWidth then
                itemWidth = math.ceil(SEASON_CURRENCY_ICON_SIZE
                    + SEASON_CURRENCY_TEXT_GAP + labelWidth
                    + SEASON_CURRENCY_TEXT_GAP + valueWidth)
            end
            item:SetWidth(itemWidth)
            if previous then
                item:SetPoint("LEFT", previous, "RIGHT", SEASON_CURRENCY_GAP, 0)
                totalWidth = totalWidth + SEASON_CURRENCY_GAP
            else
                item:SetPoint("LEFT", bar, "LEFT", 0, 0)
            end
            totalWidth = totalWidth + itemWidth
            previous = item
        end
    end
    bar.hasVisibleItems = previous ~= nil
    bar:SetWidth(totalWidth > 0 and totalWidth or 1)
end

local function ShowSeasonCurrencyTooltip(item)
    if not (item and GameTooltip and type(GameTooltip.SetOwner) == "function"
        and type(GameTooltip.SetCurrencyByID) == "function") then return end
    GameTooltip:SetOwner(item, "ANCHOR_RIGHT")
    GameTooltip:SetCurrencyByID(item.currencyID)
    if type(GameTooltip.Show) == "function" then GameTooltip:Show() end
end

local function HideSeasonCurrencyTooltip(item)
    if not GameTooltip then return end
    if type(GameTooltip.IsOwned) == "function" and not GameTooltip:IsOwned(item) then return end
    HideTooltip()
end

local function CreateSeasonCurrencyBar(parent)
    local bar = GUI2:CreateFrame(parent, {
        width = 1,
        height = SEASON_CURRENCY_ITEM_HEIGHT,
    })
    bar.items = {}
    bar.seasonCurrencyBar = true
    bar.hasVisibleItems = false
    bar.enabled = false
    for index = 1, #SEASON_CURRENCIES do
        local definition = SEASON_CURRENCIES[index]
        local item = GUI2:CreateFrame(bar, {
            width = SEASON_CURRENCY_ITEM_FALLBACK_WIDTH,
            height = SEASON_CURRENCY_ITEM_HEIGHT,
        })
        item.currencyID = definition.id
        item:EnableMouse(true)
        item:SetScript("OnEnter", ShowSeasonCurrencyTooltip)
        item:SetScript("OnLeave", HideSeasonCurrencyTooltip)
        item.definition = definition
        item.icon = GUI2:CreateTexture(item, {
            width = SEASON_CURRENCY_ICON_SIZE,
            height = SEASON_CURRENCY_ICON_SIZE,
            layer = "ARTWORK",
        })
        item.icon:SetPoint("LEFT", item, "LEFT", 0, 0)
        if type(item.icon.SetTexCoord) == "function" then item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        item.label = CreateText(item, "font.size.sm", "color.text.primary")
        item.label:SetPoint("LEFT", item.icon, "RIGHT", SEASON_CURRENCY_TEXT_GAP, 0)
        item.label:SetText(T(definition.labelKey, definition.fallbackName))
        item.value = CreateText(item, "font.size.sm", "color.text.secondary")
        item.value:SetPoint("LEFT", item.label, "RIGHT", SEASON_CURRENCY_TEXT_GAP, 0)
        item.value:SetPoint("RIGHT", item, "RIGHT", 0, 0)
        item.value:SetJustifyH("LEFT")
        item:Hide()
        bar.items[index] = item
    end
    bar:Hide()
    return bar
end

local function LayoutSeasonCurrencyBar(frame, width)
    local bar = frame and frame.currencyBar
    if not bar then return end
    bar:SetShown(bar.enabled and bar.hasVisibleItems and width >= SEASON_CURRENCY_BAR_MIN_WIDTH)
end

local function RefreshSeasonCurrencyBar(currencyID)
    local frame = runtime.frame
    local bar = frame and frame.currencyBar
    if not bar then return end
    local config = GetConfig()
    local currencyAPI = type(C_CurrencyInfo) == "table" and C_CurrencyInfo.GetCurrencyInfo or nil
    bar.enabled = config.showSeasonCurrencies == true and type(currencyAPI) == "function"
    for index = 1, #bar.items do
        local item = bar.items[index]
        local definition = item.definition
        if currencyID == nil or currencyID == definition.id then
            local info
            if bar.enabled then
                local ok, result = SafeCall(currencyAPI, definition.id)
                if ok and type(result) == "table" and not IsSecret(result) then info = result end
            end

            local iconFileID = info and SafeInteger(SafeField(info, "iconFileID"), 1) or nil
            local quantity = info and SafeInteger(SafeField(info, "quantity"), 0) or nil
            if iconFileID and quantity then
                local maxQuantity = SafeInteger(SafeField(info, "maxQuantity"), 0)
                local quantityText = FormatCurrencyAmount(quantity)
                if maxQuantity and maxQuantity > 0 then
                    quantityText = quantityText .. "/" .. FormatCurrencyAmount(maxQuantity)
                end
                item.icon:SetTexture(iconFileID)
                item.label:SetText(T(definition.labelKey, definition.fallbackName))
                item.value:SetText(quantityText)
                SetSeasonCurrencyTextColor(item.label, definition.colorQuality, quantity)
                SetSeasonCurrencyTextColor(item.value, definition.colorQuality, quantity)
                item:Show()
            else
                item:Hide()
            end
        end
    end

    LayoutSeasonCurrencyItems(bar)

    local width = tonumber(frame.summary:GetWidth()) or 0
    LayoutSeasonCurrencyBar(frame, width)
end

local function ShowCollapseTooltip(button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddLine(runtime.summaryCollapsed
        and T("tooltip.expand_summary", "Expand event summary")
        or T("tooltip.collapse_summary", "Collapse event summary"), 1, 0.82, 0.2)
    GameTooltip:Show()
end

local function BuildFrames(map)
    if runtime.frame then return runtime.frame end
    local frame = {
        map = map,
        summaryRows = {},
        scheduleRows = {},
        headings = {},
    }

    frame.summary = GUI2:CreateFrame(map, {
        name = "YUIWorldEventTrackerSummary",
        template = "BackdropTemplate",
        height = 86,
        surface = "color.surface.panel",
        border = "color.border.default",
        shadow = true,
    })
    frame.summary:SetFrameLevel((map:GetFrameLevel() or 1) + 30)

    frame.title = CreateText(frame.summary, "font.size.md", "color.text.heading")
    frame.title:SetPoint("LEFT", frame.summary, "TOPLEFT", 10, -SUMMARY_COLLAPSED_HEIGHT / 2)
    frame.count = CreateText(frame.summary, "font.size.sm", "color.text.secondary")
    frame.count:SetPoint("LEFT", frame.title, "RIGHT", 8, 0)
    frame.summaryEmpty = CreateText(frame.summary, "font.size.sm", "color.text.muted", "CENTER")
    frame.summaryEmpty:SetPoint("TOPLEFT", frame.summary, "TOPLEFT", 10, -SUMMARY_HEADER_HEIGHT - 13)
    frame.summaryEmpty:SetPoint("RIGHT", frame.summary, "RIGHT", -10, 0)
    frame.summaryEmpty:SetWordWrap(true)
    frame.summaryEmpty:Hide()
    frame.allButton = CreateHeaderButton(frame.summary, "", 112, 22)
    frame.currencyBar = CreateSeasonCurrencyBar(frame.summary)
    frame.currencyBar:SetPoint("CENTER", frame.summary, "TOP", 0, -SUMMARY_COLLAPSED_HEIGHT / 2)

    for index = 1, SUMMARY_ITEM_MAX do
        frame.summaryRows[index] = CreateEventRow(frame.summary, true)
    end

    frame.schedule = GUI2:CreateFrame(map, {
        name = "YUIWorldEventTrackerSchedule",
        template = "BackdropTemplate",
        surface = "color.surface.popup",
        border = "color.border.default",
        shadow = true,
    })
    frame.schedule:SetFrameLevel((map:GetFrameLevel() or 1) + 31)
    if frame.schedule.SetFrameStrata then frame.schedule:SetFrameStrata("DIALOG") end
    if frame.schedule.SetToplevel then frame.schedule:SetToplevel(true) end
    frame.scheduleTitle = CreateText(frame.schedule, "font.size.lg", "color.text.heading")
    frame.scheduleTitle:SetPoint("TOPLEFT", frame.schedule, "TOPLEFT", 12, -9)
    frame.closeButton = CreateHeaderButton(frame.schedule, "×", 24, 22)
    frame.closeButton:SetPoint("TOPRIGHT", frame.schedule, "TOPRIGHT", -7, -7)
    frame.collapseButton = CreateCollapseButton(frame.summary)
    frame.collapseButton:SetPoint("RIGHT", frame.summary, "TOPRIGHT", -6, -SUMMARY_COLLAPSED_HEIGHT / 2)
    frame.settingsButton = CreateHeaderButton(frame.summary, T("summary.settings", "Settings"), 58, 22)
    frame.settingsButton:SetPoint("TOPRIGHT", frame.collapseButton, "TOPLEFT", -4, 0)
    frame.allButton:SetPoint("TOPRIGHT", frame.settingsButton, "TOPLEFT", -4, 0)
    frame.settingsButton:SetScript("OnClick", OpenWorldEventSettings)
    if type(frame.collapseButton.HookScript) == "function" then
        frame.collapseButton:HookScript("OnEnter", ShowCollapseTooltip)
        frame.collapseButton:HookScript("OnLeave", HideTooltip)
    end
    frame.scroll = GUI2:CreateScrollFrame(frame.schedule, { template = "UIPanelScrollFrameTemplate" })
    frame.scroll:SetPoint("TOPLEFT", frame.schedule, "TOPLEFT", 8, -36)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame.schedule, "BOTTOMRIGHT", -27, 8)
    frame.content = frame.scroll.child
    frame.empty = CreateText(frame.content, "font.size.md", "color.text.muted", "CENTER")
    frame.empty:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 8, -20)
    frame.empty:SetPoint("RIGHT", frame.content, "RIGHT", -8, 0)
    frame.empty:SetWordWrap(true)

    local groupKeys = { "ongoing", "today", "later" }
    for index = 1, #groupKeys do
        local heading = CreateText(frame.content, "font.size.md", "color.text.heading")
        heading.groupKey = groupKeys[index]
        heading:SetText(T("group." .. groupKeys[index], groupKeys[index]))
        heading:Hide()
        frame.headings[index] = heading
    end

    frame.allButton:SetScript("OnClick", function()
        runtime.expanded = not runtime.expanded
        frame.schedule:SetShown(runtime.expanded)
        if runtime.expanded then
            RefreshFromSnapshot()
        else
            for index = 1, #frame.scheduleRows do DisableTimeDriver(frame.scheduleRows[index]) end
            RefreshCountdownTicker()
        end
    end)
    frame.closeButton:SetScript("OnClick", function()
        runtime.expanded = false
        frame.schedule:Hide()
        for index = 1, #frame.scheduleRows do DisableTimeDriver(frame.scheduleRows[index]) end
        RefreshCountdownTicker()
    end)
    frame.collapseButton:SetScript("OnClick", function()
        runtime.summaryCollapsed = not runtime.summaryCollapsed
        if runtime.summaryCollapsed then
            runtime.expanded = false
            frame.schedule:Hide()
            for index = 1, #frame.scheduleRows do DisableTimeDriver(frame.scheduleRows[index]) end
        end
        RefreshFromSnapshot()
    end)
    frame.schedule:Hide()
    runtime.frame = frame
    return frame
end

local function LayoutSummary(frame, width, count, perRow)
    if runtime.summaryCollapsed then
        frame.summary:SetHeight(SUMMARY_COLLAPSED_HEIGHT)
        return
    end
    local columns = ClampSummaryPerRow(perRow)
    local rows = count > 0 and math.ceil(count / columns) or 1
    local contentTop = SUMMARY_HEADER_HEIGHT + 2
    local contentWidth = width - 12
    local itemWidth = (contentWidth - (columns - 1) * SUMMARY_GAP) / columns
    for index = 1, SUMMARY_ITEM_MAX do
        local row = frame.summaryRows[index]
        row:ClearAllPoints()
        if index <= count then
            local column = (index - 1) % columns
            local rowIndex = math.floor((index - 1) / columns)
            row:SetPoint("TOPLEFT", frame.summary, "TOPLEFT", 6 + column * (itemWidth + SUMMARY_GAP), -contentTop - rowIndex * (SUMMARY_ROW_HEIGHT + SUMMARY_GAP))
            row:SetSize(itemWidth, SUMMARY_ROW_HEIGHT)
        end
    end
    frame.summary:SetHeight(contentTop + rows * SUMMARY_ROW_HEIGHT + (rows - 1) * SUMMARY_GAP + 6)
end

local function LayoutMapFrames()
    local frame = runtime.frame
    if not frame or not frame.map then return end
    local map = frame.map
    local width = math.max(SUMMARY_MIN_WIDTH, tonumber(map:GetWidth()) or SUMMARY_MIN_WIDTH)
    local maximized = type(map.IsMaximized) == "function" and map:IsMaximized() == true
    frame.summary:ClearAllPoints()
    if maximized then
        -- 全屏时为左下角地图按钮和坐标留空，保持右侧和底部边距不变。
        local leftInset = math.min(width * SUMMARY_MAXIMIZED_LEFT_RATIO, math.max(12, width - SUMMARY_MIN_WIDTH - 12))
        width = math.max(SUMMARY_MIN_WIDTH, width - leftInset - 12)
        frame.summary:SetPoint("BOTTOMLEFT", map, "BOTTOMLEFT", leftInset, 12)
    else
        frame.summary:SetPoint("TOPLEFT", map, "BOTTOMLEFT", 0, -4)
    end
    frame.summary:SetWidth(width)
    frame.count:SetShown(width >= 460)
    LayoutSeasonCurrencyBar(frame, width)
    local config = GetConfig()
    LayoutSummary(frame, width, runtime.model and #runtime.model.summary or 0, config.summaryPerRow)

    frame.schedule:ClearAllPoints()
    frame.schedule:SetPoint("BOTTOMLEFT", frame.summary, "TOPLEFT", 0, 6)
    frame.schedule:SetWidth(width)
    local mapHeight = tonumber(map:GetHeight()) or SCHEDULE_MAX_HEIGHT
    frame.schedule:SetHeight(math.max(160, math.min(SCHEDULE_MAX_HEIGHT, mapHeight * 0.65)))
    frame.content:SetWidth(math.max(1, width - 45))
end

local function AcquireScheduleRow(frame, index)
    local row = frame.scheduleRows[index]
    if not row then
        row = CreateEventRow(frame.content, false)
        frame.scheduleRows[index] = row
    end
    return row
end

local function PopulateSchedule(frame, model, status, serverNow, frameNow)
    for index = 1, #frame.scheduleRows do
        DisableTimeDriver(frame.scheduleRows[index])
        frame.scheduleRows[index].item = nil
        frame.scheduleRows[index]:Hide()
    end
    for index = 1, #frame.headings do frame.headings[index]:Hide() end

    if status ~= "ready" or model.total == 0 then
        if status == "loading" then frame.empty:SetText(T("loading", "Loading…"))
        elseif status == "unsupported" then frame.empty:SetText(T("unsupported", "Unavailable"))
        else frame.empty:SetText(T("empty", "No events")) end
        frame.empty:Show()
        frame.content:SetHeight(90)
        return
    end

    frame.empty:Hide()
    local groups = { model.ongoing, model.today, model.later }
    local y = 0
    local rowIndex = 0
    for groupIndex = 1, #groups do
        local group = groups[groupIndex]
        if #group > 0 then
            local heading = frame.headings[groupIndex]
            heading:ClearAllPoints()
            heading:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 7, -y)
            heading:SetPoint("RIGHT", frame.content, "RIGHT", -7, 0)
            heading:Show()
            y = y + SCHEDULE_HEADING_HEIGHT
            for index = 1, #group do
                rowIndex = rowIndex + 1
                local row = AcquireScheduleRow(frame, rowIndex)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 4, -y)
                row:SetPoint("RIGHT", frame.content, "RIGHT", -4, 0)
                row:SetHeight(SCHEDULE_ROW_HEIGHT)
                UpdateEventRow(row, group[index], runtime.expanded, true, serverNow, frameNow)
                y = y + SCHEDULE_ROW_HEIGHT + 4
            end
            y = y + 4
        end
    end
    frame.content:SetHeight(math.max(1, y + 4))
end

local function CancelBoundaryTimer()
    local timer = runtime.boundaryTimer
    runtime.boundaryTimer = nil
    if timer and type(timer.Cancel) == "function" then pcall(timer.Cancel, timer) end
end

local function GetNextMidnight(now)
    if type(date) ~= "function" or type(time) ~= "function" then return nil end
    local ok, parts = pcall(date, "*t", now)
    if not ok or type(parts) ~= "table" then return nil end
    parts.hour, parts.min, parts.sec = 0, 0, 0
    parts.day = (parts.day or 0) + 1
    local midnightOk, midnight = pcall(time, parts)
    if midnightOk and type(midnight) == "number" and midnight > now then return midnight end
end

local function ScheduleBoundary(model, now)
    CancelBoundaryTimer()
    if not runtime.enabled or not runtime.frame or not IsShown(runtime.frame.map) then return end
    if not (C_Timer and type(C_Timer.NewTimer) == "function") then return end
    local nextBoundary = model and model.nextBoundary or nil
    local midnight = GetNextMidnight(now)
    if midnight and (not nextBoundary or midnight < nextBoundary) then nextBoundary = midnight end
    if not nextBoundary then return end
    local delay = math.max(0.05, nextBoundary - now + 0.05)
    local timer
    local timerOk, createdTimer = pcall(C_Timer.NewTimer, delay, function()
        if runtime.boundaryTimer ~= timer then return end
        runtime.boundaryTimer = nil
        if not runtime.enabled or not runtime.frame or not IsShown(runtime.frame.map) then return end
        API.RequestEvents()
        RefreshFromSnapshot()
    end)
    if timerOk and createdTimer then
        timer = createdTimer
        runtime.boundaryTimer = timer
    end
end

RefreshFromSnapshot = function()
    if not runtime.enabled or not runtime.frame or not IsShown(runtime.frame.map) then return end
    CancelCountdownTicker()
    ClearCountdownRows()
    local config = GetConfig()
    runtime.snapshot = API.GetSnapshot(runtime.snapshot)
    local serverNow = GetServerNow()
    local frameNow = GetFrameNow()
    runtime.worldBossSnapshot = WorldQuestAPI.GetWorldBossSnapshot(
        CollectEventMapIDs(runtime.snapshot),
        runtime.snapshot.activeContinentName,
        serverNow,
        runtime.worldBossSnapshot
    )
    runtime.model = Model.Build(runtime.snapshot, {
        now = serverNow,
        summaryLimit = config.summaryRows * config.summaryPerRow,
        scheduledLimit = GetScheduledDisplayLimit(),
        rotationLimit = ROTATION_CLUSTER_LIMIT,
        imminentWindow = IMMINENT_WINDOW_SECONDS,
        showRewarded = config.showRewarded,
        seriesLocale = GetClientLocale(),
        summarySeriesEnabled = config.summarySeriesEnabled,
        worldBosses = runtime.worldBossSnapshot.bosses,
        locationResolver = ResolveEventLocationCached,
    }, runtime.model)
    RememberDiscoveredSeries(config, runtime.model)

    local frame = runtime.frame
    frame.title:SetText(T("summary.title", "World Events"))
    frame.count:SetText(string.format(T("summary.count", "%d active"), runtime.model.ongoingCount))
    SetButtonText(frame.allButton, string.format(T("summary.all", "Full Schedule · %d"), runtime.model.total))
    SetButtonText(frame.settingsButton, T("summary.settings", "Settings"))
    if type(frame.collapseButton.SetIcon) == "function" then
        frame.collapseButton:SetIcon(runtime.summaryCollapsed and "arrow-big-down" or "arrow-big-up")
    end
    frame.scheduleTitle:SetText(T("summary.title", "World Events"))
    RefreshSeasonCurrencyBar()

    for index = 1, SUMMARY_ITEM_MAX do
        local row = frame.summaryRows[index]
        DisableTimeDriver(row)
        row.item = nil
        row:Hide()
    end
    if not runtime.summaryCollapsed then
        for index = 1, #runtime.model.summary do
            UpdateEventRow(frame.summaryRows[index], runtime.model.summary[index], true, true, serverNow, frameNow)
        end
    end
    if not runtime.summaryCollapsed and #runtime.model.summary == 0 then
        if runtime.model.filteredSummaryCount > 0 and runtime.model.total > 0 then
            frame.summaryEmpty:SetText(T("empty.filtered", "No events match the summary filters."))
        elseif runtime.snapshot.status == "loading" then
            frame.summaryEmpty:SetText(T("loading", "Loading…"))
        elseif runtime.snapshot.status == "unsupported" then
            frame.summaryEmpty:SetText(T("unsupported", "Unavailable"))
        else
            frame.summaryEmpty:SetText(T("empty", "No events"))
        end
        frame.summaryEmpty:Show()
    else
        frame.summaryEmpty:Hide()
    end
    LayoutMapFrames()
    PopulateSchedule(frame, runtime.model, runtime.snapshot.status, serverNow, frameNow)
    RefreshCountdownTicker()
    ScheduleBoundary(runtime.model, serverNow)
end

local function DetachScheduler()
    if runtime.schedulerAttached then
        Event:OffOwner(runtime.eventOwner)
        runtime.schedulerAttached = false
    end
end

local function OnSchedulerUpdate()
    RefreshFromSnapshot()
end

local function OnCurrencyDisplayUpdate(_, currencyID)
    if currencyID ~= nil then
        currencyID = SafeInteger(currencyID, 1)
        if not currencyID or not SEASON_CURRENCY_IDS[currencyID] then return end
    end
    if not runtime.enabled or not runtime.frame or not IsShown(runtime.frame.map) then return end
    RefreshSeasonCurrencyBar(currencyID)
end

local function CancelQuestRefreshTimer()
    local timer = runtime.questRefreshTimer
    runtime.questRefreshTimer = nil
    if timer and type(timer.Cancel) == "function" then pcall(timer.Cancel, timer) end
end

local function QueueQuestRefresh()
    if runtime.questRefreshTimer or not runtime.enabled or not runtime.frame or not IsShown(runtime.frame.map) then return end
    if not (C_Timer and type(C_Timer.NewTimer) == "function") then
        RefreshFromSnapshot()
        return
    end
    local timer
    local ok, created = pcall(C_Timer.NewTimer, 0, function()
        if runtime.questRefreshTimer ~= timer then return end
        runtime.questRefreshTimer = nil
        if runtime.enabled and runtime.frame and IsShown(runtime.frame.map) then RefreshFromSnapshot() end
    end)
    if ok and created then
        timer = created
        runtime.questRefreshTimer = timer
    end
end

local function AttachScheduler()
    if runtime.schedulerAttached then return end
    Event:On("EVENT_SCHEDULER_UPDATE", OnSchedulerUpdate, runtime.eventOwner, {
        moduleId = "ymap",
        traceName = "WorldEventTracker:scheduler-update",
    })
    Event:On("CURRENCY_DISPLAY_UPDATE", OnCurrencyDisplayUpdate, runtime.eventOwner, {
        moduleId = "ymap",
        traceName = "WorldEventTracker:currency-update",
    })
    for _, eventName in ipairs({ "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "TASK_PROGRESS_UPDATE", "QUEST_DATA_LOAD_RESULT" }) do
        Event:On(eventName, QueueQuestRefresh, runtime.eventOwner, {
            moduleId = "ymap",
            traceName = "WorldEventTracker:quest-update",
        })
    end
    runtime.schedulerAttached = true
end

local function OnMapShow()
    if not runtime.enabled then return end
    AttachScheduler()
    API.RequestEvents()
    RefreshFromSnapshot()
end

local function OnMapHide()
    DetachScheduler()
    CancelQuestRefreshTimer()
    CancelBoundaryTimer()
    CancelCountdownTicker()
    ClearCountdownRows()
    CancelPingTimer()
    ReleasePingPin()
    DisableAllTimeDrivers()
    runtime.expanded = false
    if runtime.frame then runtime.frame.schedule:Hide() end
    HideTooltip()
end

local function OnMapSizeChanged()
    if runtime.enabled and runtime.frame and IsShown(runtime.frame.map) then
        LayoutMapFrames()
    end
end

local function RegisterMapCallbacks()
    if runtime.mapCallbacksRegistered then return true end
    if not (EventRegistry and type(EventRegistry.RegisterCallback) == "function") then return false end
    EventRegistry:RegisterCallback("WorldMapOnShow", OnMapShow, runtime.mapEventOwner)
    EventRegistry:RegisterCallback("WorldMapOnHide", OnMapHide, runtime.mapEventOwner)
    runtime.mapCallbacksRegistered = true
    return true
end

local function UnregisterMapCallbacks()
    if not runtime.mapCallbacksRegistered then return end
    if EventRegistry and type(EventRegistry.UnregisterCallback) == "function" then
        EventRegistry:UnregisterCallback("WorldMapOnShow", runtime.mapEventOwner)
        EventRegistry:UnregisterCallback("WorldMapOnHide", runtime.mapEventOwner)
    end
    runtime.mapCallbacksRegistered = false
end

local function AttachMap(map)
    if not map then return false end
    BuildFrames(map)
    if not RegisterMapCallbacks() then return false end
    if not runtime.hooked then
        map:HookScript("OnSizeChanged", OnMapSizeChanged)
        runtime.hooked = true
    end
    Event:OffOwner(runtime.addonOwner)
    if runtime.enabled and IsShown(map) then OnMapShow() end
    return true
end

local function OnAddonLoaded(_, addonName)
    if addonName == MAP_ADDON and _G.WorldMapFrame then AttachMap(_G.WorldMapFrame) end
end

local function EnsureMap()
    if _G.WorldMapFrame then return AttachMap(_G.WorldMapFrame) end
    Event:OffOwner(runtime.addonOwner)
    Event:On("ADDON_LOADED", OnAddonLoaded, runtime.addonOwner, {
        moduleId = "ymap",
        traceName = "WorldEventTracker:world-map-load",
    })
    return false
end

local function SetEnabled(enabled, resetSummaryState)
    enabled = enabled == true
    local wasEnabled = runtime.enabled
    runtime.enabled = enabled
    if enabled and (resetSummaryState == true or not wasEnabled) then
        runtime.summaryCollapsed = GetConfig().defaultCollapsed == true
    end
    if runtime.enabled then
        EnsureMap()
    else
        Event:OffOwner(runtime.addonOwner)
        UnregisterMapCallbacks()
        OnMapHide()
        if runtime.frame then runtime.frame.summary:Hide() end
    end
    if runtime.enabled and runtime.frame then runtime.frame.summary:Show() end
end

local Feature = {}
YMap.WorldEvents = Feature

function Feature:Enable()
    SetEnabled(true)
end

function Feature:Disable()
    SetEnabled(false)
    self.RefreshCurrentModule = nil
end

function Feature:GetOptions()
    local config = GetConfig()
    local function RefreshSettings()
        if self.RefreshCurrentModule then self:RefreshCurrentModule() end
    end
    local function Refresh()
        if runtime.enabled and runtime.frame and IsShown(runtime.frame.map) then RefreshFromSnapshot() end
        RefreshSettings()
    end
    local function RefreshCurrencies()
        if runtime.enabled and runtime.frame and IsShown(runtime.frame.map) then RefreshSeasonCurrencyBar() end
        RefreshSettings()
    end
    local options = {
        {
            type = "row",
            children = {
                {
                    type = "slider",
                    label = T("settings.summary_rows", "Summary Rows"),
                    inline = true,
                    width = 230,
                    labelWidth = 130,
                    inputWidth = 42,
                    min = SUMMARY_ROW_MIN,
                    max = SUMMARY_ROW_MAX,
                    step = 1,
                    get = function() return ClampSummaryRows(config.summaryRows) end,
                    set = function(value) config.summaryRows = ClampSummaryRows(value) end,
                    onChange = Refresh,
                },
                {
                    type = "slider",
                    label = T("settings.summary_per_row", "Events per Row"),
                    inline = true,
                    width = 230,
                    labelWidth = 130,
                    inputWidth = 42,
                    min = SUMMARY_PER_ROW_MIN,
                    max = SUMMARY_PER_ROW_MAX,
                    step = 1,
                    get = function() return ClampSummaryPerRow(config.summaryPerRow) end,
                    set = function(value) config.summaryPerRow = ClampSummaryPerRow(value) end,
                    onChange = Refresh,
                },
            },
        },
        {
            type = "row",
            children = {
                {
                    type = "checkbox",
                    label = T("settings.show_rewarded", "Show Claimed Events"),
                    width = 230,
                    get = function() return config.showRewarded ~= false end,
                    set = function(value) config.showRewarded = value == true end,
                    onChange = Refresh,
                },
                {
                    type = "checkbox",
                    label = T("settings.show_season_currencies", "Show Season Crests"),
                    width = 230,
                    get = function() return config.showSeasonCurrencies ~= false end,
                    set = function(value) config.showSeasonCurrencies = value == true end,
                    onChange = RefreshCurrencies,
                },
                {
                    type = "checkbox",
                    label = T("settings.default_collapsed", "Start Summary Collapsed"),
                    width = 230,
                    get = function() return config.defaultCollapsed == true end,
                    set = function(value) config.defaultCollapsed = value == true end,
                    onChange = RefreshSettings,
                },
            },
        },
        {
            type = "text",
            label = T("settings.summary_series", "Summary Activity Series"),
            colorKey = "color.text.primary",
        },
    }

    local locale = GetClientLocale()
    local seriesOptions = {
        { key = "world-boss", label = T("series.world_boss", "World Bosses") },
    }
    for key, entry in pairs(config.discoveredSeries) do
        if key ~= "world-boss" and type(entry) == "table" then
            local labels = type(entry.labels) == "table" and entry.labels or {}
            local label = labels[locale]
            if type(label) == "string" and label ~= "" then
                seriesOptions[#seriesOptions + 1] = { key = key, label = label }
            end
        end
    end
    table.sort(seriesOptions, function(a, b)
        if a.key == "world-boss" then return true end
        if b.key == "world-boss" then return false end
        if a.label == b.label then return a.key < b.key end
        return a.label < b.label
    end)

    local function CreateSeriesCheckbox(series)
        local seriesKey = series.key
        return {
            type = "checkbox",
            label = series.label,
            width = 230,
            get = function() return config.summarySeriesEnabled[seriesKey] ~= false end,
            set = function(value) config.summarySeriesEnabled[seriesKey] = value == true end,
            onChange = Refresh,
        }
    end

    for index = 1, #seriesOptions, 2 do
        local row = { type = "row", children = {} }
        for offset = 0, 1 do
            local series = seriesOptions[index + offset]
            if series then
                row.children[#row.children + 1] = CreateSeriesCheckbox(series)
            end
        end
        options[#options + 1] = row
    end

    options[#options + 1] =
        {
            type = "text",
            label = T("settings.credit", "Thanks to 枫岚 for providing the Curse Tide coordinates and waypoint data."),
            colorKey = "color.text.muted",
        }
    return options
end

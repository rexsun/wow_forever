local YUI = _G.YUI
if not YUI or not YUI.YChat then return end

local YChat = YUI.YChat
local Adapter = YChat.Adapter
local MetadataRing = YChat.MetadataRing
if not Adapter or not MetadataRing then return end
local Stats = YChat.Stats

local Shadow = {}
YChat.Shadow = Shadow

local L = YUI.Locale and YUI.Locale:Get("YChat") or {}
local date = _G.date
local GetServerTime = _G.GetServerTime
local GetTime = _G.GetTime
local ceil = math.ceil
local floor = math.floor
local huge = math.huge
local format = string.format
local gsub = string.gsub
local lower = string.lower
local pairs = pairs
local pcall = pcall
local tostring = tostring
local type = type

local function ZeroTime()
    return 0
end

local ReadArrivalTime = type(GetTime) == "function" and GetTime or ZeroTime
local ReadServerTime = type(GetServerTime) == "function" and GetServerTime or nil
local FormatLocalTime = type(date) == "function" and date or nil

local RIGHT_INSET = 4
local TIMESTAMP_MIN_WIDTH = 64
local TIMESTAMP_MIN_WIDTH_HM = 44
local TIMESTAMP_MAX_WIDTH = 128
local TIMESTAMP_WIDTH_SAMPLES = {
    "00:00:00", "11:11:11", "22:22:22",
    "33:33:33", "44:44:44", "55:55:55",
    "66:66:66", "77:77:77", "99:99:99",
    "88:88:88",
}
local TIMESTAMP_WIDTH_SAMPLES_HM = {
    "00:00", "11:11", "22:22", "33:33", "44:44",
    "55:55", "66:66", "77:77", "88:88", "99:99",
}
local TIMESTAMP_WIDTH_PADDING = 4
local TIMESTAMP_LEFT_INSET = 6
local BODY_VERTICAL_SAFE_INSET = 1
local METADATA_CAPACITY = MetadataRing.HARD_CAPACITY or 1000
local OVERLAY_CAPACITY = 192
local EXTREME_FLOOD_PER_SECOND = 500
local EXTREME_FLOOD_PER_TICK = MetadataRing.DEFAULT_CAPACITY or 128
local ARRIVAL_TICKS_PER_SECOND = 1000
local EXTREME_RESTORE_DELAY_FRAMES = 3
local tableCreate = table.create

local function NewHotArray(capacity)
    return type(tableCreate) == "function" and tableCreate(capacity) or {}
end

local frameStates = setmetatable({}, { __mode = "k" })
local overlayByLine = setmetatable({}, { __mode = "k" })
local frameByLine = setmetatable({}, { __mode = "k" })
local hasEntryByOverlay = setmetatable({}, { __mode = "k" })
local shownByOverlay = setmetatable({}, { __mode = "k" })
local floodGroupTimes = NewHotArray(EXTREME_FLOOD_PER_SECOND)
local floodGroupCounts = NewHotArray(EXTREME_FLOOD_PER_SECOND)
local probeFrame
local cachedSecond
local cachedArrivalTick
local cachedTimestamp = ""
local cachedFormat = "hms"
local SYSTEM_TIMESTAMP_NONE = "none"
local systemTimestampSnapshot
local systemTimestampManaged = false
local systemTimestampTarget
local systemTimestampApplying = false
local floodGroupHead = 1
local floodGroupTail = 0
local floodGroupCount = 0
local floodWindowCount = 0
local floodCurrentTick
local floodCurrentTime
local floodCurrentCount = 0
local floodLastTime
local probeState
local deferredRestoreFrame
local deferredRestoreFramesRemaining = 0
local syntheticTimestampFrame
local syntheticTimestampEpoch
local adapterCallbacks
local EnterQ3
local ActivateFrame
local GetHistoryEntryInCallback = Adapter.GetHistoryEntryInCallback
local GetHistoryCursor = Adapter.GetHistoryCursor
local GetHistoryEntryFromCursorInCallback = Adapter.GetHistoryEntryFromCursorInCallback
local ReadScrollOffsetInCallback = Adapter.ReadScrollOffsetInCallback
local VisitDisplayEntriesInCallback = Adapter.VisitDisplayEntriesInCallback
local GetProbeDisplayLinesInCallback = Adapter.GetProbeDisplayLinesInCallback
local SetOverlayAlphaInCallback = Adapter.SetOverlayAlphaInCallback
local SetOverlayTextInCallback = Adapter.SetOverlayTextInCallback
local IncrementMetadataAppends = Stats and Stats.IncrementMetadataAppends

Shadow.enabled = false
Shadow.probeEnabled = false
Shadow.lastReason = "not-started"
Shadow.qualityState = "Q3"
Shadow.stopAfterRestore = false
Shadow.productionMode = false
Shadow.activeTimestampLayout = "column"
Shadow.activeTimestampFormat = "hms"
Shadow.activeTimestampColor = nil
Shadow.activationReason = nil
Shadow.activationFailures = 0
Shadow.restrictionPaused = false

local function T(key, fallback)
    local value = L[key]
    return type(value) == "string" and value ~= "" and value or fallback
end

local function StatIncrement(field, amount)
    local stats = YChat.Stats
    if stats and stats.Increment then stats:Increment(field, amount) end
end

local function StatSet(field, value)
    local stats = YChat.Stats
    if stats and stats.Set then stats:Set(field, value) end
end

local function SetQualityState(value)
    Shadow.qualityState = value
    StatSet("qualityState", value)
end

local function ReadArrivalSample()
    local arrivalTime = ReadArrivalTime()
    if type(arrivalTime) ~= "number"
        or not (arrivalTime > -huge and arrivalTime < huge)
    then
        return nil
    end
    return arrivalTime, floor(arrivalTime * ARRIVAL_TICKS_PER_SECOND)
end

local function ReadTimestampConfig()
    local config = YChat.GetTimestamp and YChat:GetTimestamp()
    return type(config) == "table" and config or YChat.Defaults.timestamp
end

local function ApplyNativeInlineIndent(frame, requestLayout)
    local desired = ReadTimestampConfig().nativeIndentedWrap == true
    local current, readReason = Adapter:ReadIndentedWordWrap(frame)
    if current == nil then return false, false, readReason end
    if current == desired then return true, false end

    local applied, applyReason = Adapter:SetIndentedWordWrap(frame, desired)
    if not applied then return false, false, applyReason end
    local confirmed, confirmReason = Adapter:ReadIndentedWordWrap(frame)
    if confirmed == nil then return false, false, confirmReason end
    if confirmed ~= desired then return false, false, "native-indent-write-unconfirmed" end
    if requestLayout then
        local requested, requestReason = Adapter:RequestNativeLayout(frame)
        if not requested then return false, false, requestReason end
    end
    return true, true
end

local function TimestampPattern(formatName)
    return formatName == "hm" and "%H:%M" or "%H:%M:%S"
end

local function FormatServerSecond(second)
    if type(second) ~= "number" or not FormatLocalTime then
        return nil
    end
    local value = FormatLocalTime(TimestampPattern(ReadTimestampConfig().format), second)
    return type(value) == "string" and value ~= "" and value or nil
end

local function GetTimestampLabel(arrivalTime, arrivalTick)
    local config = ReadTimestampConfig()
    if arrivalTick == cachedArrivalTick and config.format == cachedFormat then
        return cachedTimestamp, cachedSecond
    end
    local second = ReadServerTime and ReadServerTime() or floor(arrivalTime)
    local timestamp = cachedTimestamp
    if second ~= cachedSecond or config.format ~= cachedFormat then
        if FormatLocalTime then
            local value = FormatLocalTime(TimestampPattern(config.format), second)
            timestamp = type(value) == "string" and value ~= "" and value or ""
        end
    end
    cachedArrivalTick = arrivalTick
    cachedSecond = second
    cachedFormat = config.format
    cachedTimestamp = timestamp
    return cachedTimestamp, cachedSecond
end

local function ResetFloodWindow()
    floodGroupHead = 1
    floodGroupTail = 0
    floodGroupCount = 0
    floodWindowCount = 0
    floodCurrentTick = nil
    floodCurrentTime = nil
    floodCurrentCount = 0
    floodLastTime = nil
end

local function IsExtremeFlood(now, arrivalTick)
    if floodLastTime ~= nil and now < floodLastTime then return true end
    floodLastTime = now

    if floodCurrentTick == arrivalTick then
        floodCurrentTime = now
        floodCurrentCount = floodCurrentCount + 1
        floodWindowCount = floodWindowCount + 1
        return floodCurrentCount >= EXTREME_FLOOD_PER_TICK
            or floodWindowCount >= EXTREME_FLOOD_PER_SECOND
    end

    if floodCurrentTick ~= nil then
        if floodGroupCount >= EXTREME_FLOOD_PER_SECOND then return true end
        if floodGroupCount == 0 then
            floodGroupTail = floodGroupHead
        else
            floodGroupTail = (floodGroupTail % EXTREME_FLOOD_PER_SECOND) + 1
        end
        floodGroupTimes[floodGroupTail] = floodCurrentTime
        floodGroupCounts[floodGroupTail] = floodCurrentCount
        floodGroupCount = floodGroupCount + 1
        floodCurrentTick = nil
        floodCurrentTime = nil
        floodCurrentCount = 0
    end

    while floodGroupCount > 0 do
        local oldest = floodGroupTimes[floodGroupHead]
        if type(oldest) ~= "number" then return true end
        if now - oldest <= 1 then break end
        local expiredCount = floodGroupCounts[floodGroupHead]
        if type(expiredCount) ~= "number" then return true end
        floodWindowCount = floodWindowCount - expiredCount
        floodGroupHead = (floodGroupHead % EXTREME_FLOOD_PER_SECOND) + 1
        floodGroupCount = floodGroupCount - 1
    end

    floodCurrentTick = arrivalTick
    floodCurrentTime = now
    floodCurrentCount = 1
    floodWindowCount = floodWindowCount + 1
    return floodCurrentCount >= EXTREME_FLOOD_PER_TICK
        or floodWindowCount >= EXTREME_FLOOD_PER_SECOND
end

local function PrimeRing(frame, ring)
    ring:Reset()
    local count, countReason = Adapter:ReadNumMessages(frame)
    if count == nil then return ring:Invalidate(countReason or "PRIME_COUNT") end
    local capacity = ring:Capacity()
    if count > capacity then return ring:Invalidate("CAPACITY") end
    if count < 1 then return true end

    local monotonicNow = ReadArrivalTime()
    local serverNow = ReadServerTime and ReadServerTime() or nil
    local clocksValid = type(monotonicNow) == "number"
        and monotonicNow >= 0
        and monotonicNow < huge
        and type(serverNow) == "number"
        and serverNow >= 0
        and serverNow < huge

    local function ReadHistoricalMetadata(index)
        local entry, nativeTimestamp = Adapter:ReadHistoricalEntrySample(frame, index)
        if entry == nil then return nil end
        if not clocksValid
            or type(nativeTimestamp) ~= "number"
            or nativeTimestamp > monotonicNow
        then
            return entry
        end
        local epoch = floor(serverNow - (monotonicNow - nativeTimestamp) + 0.5)
        if epoch < 0 or epoch >= huge then return entry end
        return entry, epoch, FormatServerSecond(epoch)
    end

    local newest, newestTime, newestLabel = ReadHistoricalMetadata(1)
    if newest == nil then return ring:Invalidate("PRIME_MAPPING") end
    local pushed, pushReason = ring:PushFront(newest, newestTime, newestLabel)
    if not pushed then return ring:Invalidate(pushReason or "PRIME_APPEND") end
    for index = 2, count do
        local entry, timestamp, label = ReadHistoricalMetadata(index)
        if entry == nil then return ring:Invalidate("PRIME_MAPPING") end
        pushed, pushReason = ring:PushBack(entry, timestamp, label)
        if not pushed then return ring:Invalidate(pushReason or "PRIME_APPEND") end
    end
    return true
end

local function EnsureFrameState(frame)
    local state = frameStates[frame]
    if state then return state end

    local maxLines, maxReason = Adapter:ReadMaxLines(frame)
    local capacity = maxLines or MetadataRing.DEFAULT_CAPACITY or 128
    if capacity > METADATA_CAPACITY then capacity = METADATA_CAPACITY end
    local ring = MetadataRing:EnsureForFrame(frame, capacity)
    local historyCursor = GetHistoryCursor and GetHistoryCursor(Adapter, frame) or nil
    state = {
        ring = ring,
        ringAppend = ring.Append,
        ringIsValid = ring.IsValid,
        ringGetDisplayMetadata = ring.GetDisplayMetadataInCallback,
        historyCursor = historyCursor,
        originalIndent = nil,
        mode = nil,
        host = nil,
        hostReady = false,
        timestampFontObject = nil,
        timestampFontFile = nil,
        timestampFontHeight = nil,
        timestampFontFlags = nil,
        timestampWidth = nil,
        bodyInset = nil,
        overlays = NewHotArray(OVERLAY_CAPACITY),
        boundLines = NewHotArray(OVERLAY_CAPACITY),
        overlayHasEntry = NewHotArray(OVERLAY_CAPACITY),
        overlayLabels = NewHotArray(OVERLAY_CAPACITY),
        overlayAllocatedCount = 0,
        overlayCount = 0,
        displayWrites = 0,
        displaySkips = 0,
        probeApplied = false,
        managed = false,
        observed = false,
        restorePending = false,
        restoreAwaitingLayout = false,
        restoreRetryConsumed = false,
        restoreDeferred = false,
        resumeAfterRestore = false,
        activationFailed = false,
    }
    frameStates[frame] = state
    local invalidReason
    if maxLines == nil then
        invalidReason = maxReason or "MAX_LINES"
    elseif maxLines > METADATA_CAPACITY then
        invalidReason = "CAPACITY"
    elseif historyCursor == nil then
        invalidReason = "HISTORY_CURSOR"
    elseif not PrimeRing(frame, ring) then
        invalidReason = "PRIME"
    end
    if invalidReason then
        ring:Invalidate(invalidReason)
        StatIncrement("shadowMismatches")
    end
    return state
end

local function UnbindLines(state)
    for index = 1, #state.boundLines do
        local line = state.boundLines[index]
        if line then
            local overlay = overlayByLine[line]
            if overlay then hasEntryByOverlay[overlay] = nil end
            Adapter:UnbindVisibleLineOverlay(line, overlay)
            overlayByLine[line] = nil
            frameByLine[line] = nil
        end
        state.boundLines[index] = nil
        state.overlayHasEntry[index] = nil
    end
end

local function RefreshManagedGauges()
    local managed = 0
    local pending = 0
    for _, state in pairs(frameStates) do
        if state.managed == true then managed = managed + 1 end
        if state.restorePending == true then pending = pending + 1 end
    end
    Shadow.probeEnabled = managed > 0
    StatSet("managedFrames", managed)
    StatSet("pendingRestores", pending)
    return managed, pending
end

local function HasOtherPendingRestore(exceptFrame)
    for frame, state in pairs(frameStates) do
        if frame ~= exceptFrame and state.restorePending == true then return true end
    end
    return false
end

local function RefreshPoolGauges()
    local active = 0
    local capacity = 0
    for _, state in pairs(frameStates) do
        active = active + #state.boundLines
        capacity = capacity + state.overlayCount
    end
    StatSet("poolActive", active)
    StatSet("poolFree", capacity - active)
end

local function SetOverlayShown(overlay, shown)
    shown = shown == true
    if shownByOverlay[overlay] == shown then return true, false end

    local ok, reason
    if shown then
        ok, reason = Adapter:ShowOverlay(overlay)
    else
        ok, reason = Adapter:HideOverlay(overlay)
    end
    if not ok then return false, reason end

    shownByOverlay[overlay] = shown
    return true, true
end

local function HideOverlays(state)
    local firstReason
    for index = 1, state.overlayCount do
        local overlay = state.overlays[index]
        if overlay then
            local hidden, reason = SetOverlayShown(overlay, false)
            if not hidden and not firstReason then firstReason = reason or "timestamp-overlay-hide-failed" end
        end
    end
    RefreshPoolGauges()
    if firstReason then return false, firstReason end
    return true
end

local function RefreshCleanupLeaks()
    local count = 0
    for _, state in pairs(frameStates) do
        if state.restorePending then count = count + 1 end
    end
    StatSet("cleanupLeaks", count)
end

local function EnsureTimestampMetrics(state, overlay, config)
    if state.timestampWidth ~= nil and state.bodyInset ~= nil then return true end

    local maxWidth = 0
    local samples = config.format == "hm" and TIMESTAMP_WIDTH_SAMPLES_HM
        or TIMESTAMP_WIDTH_SAMPLES
    for index = 1, #samples do
        local measured, reason =
            Adapter:MeasureTimestampOverlayWidth(overlay, samples[index])
        if measured == nil then return false, reason end
        if measured > maxWidth then maxWidth = measured end
    end

    local width = ceil(maxWidth + TIMESTAMP_WIDTH_PADDING)
    local minimumWidth = config.format == "hm"
        and TIMESTAMP_MIN_WIDTH_HM
        or TIMESTAMP_MIN_WIDTH
    if width < minimumWidth then width = minimumWidth end
    if width > TIMESTAMP_MAX_WIDTH then return false, "timestamp-width-out-of-range" end

    state.timestampWidth = width
    state.bodyInset = TIMESTAMP_LEFT_INSET + width + config.gap
    return true
end

local function RestoreSystemTimestamp()
    if not systemTimestampManaged then return true end
    if type(systemTimestampSnapshot) ~= "string" or systemTimestampSnapshot == "" then
        return false, "system-timestamp-snapshot-missing"
    end
    systemTimestampApplying = true
    local restored, reason = Adapter:SetSystemTimestampFormat(systemTimestampSnapshot)
    systemTimestampApplying = false
    if not restored then return false, reason end
    systemTimestampManaged = false
    systemTimestampTarget = nil
    systemTimestampSnapshot = nil
    return true
end

local function TimestampColorByte(value)
    if type(value) ~= "number" or value ~= value then return nil end
    if value < 0 then value = 0 elseif value > 1 then value = 1 end
    return floor(value * 255 + 0.5)
end

local function CopyTimestampColor(value)
    local fallback = YChat.Defaults.timestamp.color
    if type(value) ~= "table" then value = fallback end
    local red = TimestampColorByte(value[1])
    local green = TimestampColorByte(value[2])
    local blue = TimestampColorByte(value[3])
    if red == nil or green == nil or blue == nil then
        value = fallback
        red = TimestampColorByte(value[1])
        green = TimestampColorByte(value[2])
        blue = TimestampColorByte(value[3])
    end
    if red == nil or green == nil or blue == nil then return nil end
    return { value[1], value[2], value[3], value[4] }
end

local function ResolveManagedSystemTimestamp(layout, formatName, color)
    if layout == "column" then return SYSTEM_TIMESTAMP_NONE end
    if layout ~= "nativeInline" then return nil, "timestamp-layout-invalid" end
    local key = formatName == "hm"
        and "TIMESTAMP_FORMAT_HHMM_24HR"
        or "TIMESTAMP_FORMAT_HHMMSS_24HR"
    local value = _G[key]
    if type(value) ~= "string" or value == "" then
        return nil, "system-timestamp-format-unavailable"
    end
    local red = type(color) == "table" and TimestampColorByte(color[1]) or nil
    local green = type(color) == "table" and TimestampColorByte(color[2]) or nil
    local blue = type(color) == "table" and TimestampColorByte(color[3]) or nil
    if red == nil or green == nil or blue == nil then
        return nil, "system-timestamp-color-invalid"
    end
    return format("|cff%02x%02x%02x", red, green, blue) .. value .. "|r"
end

local function ApplySystemTimestampTarget(target)
    if type(target) ~= "string" or target == "" then
        return false, "system-timestamp-target-invalid"
    end
    local current, readReason = Adapter:ReadSystemTimestampFormat()
    if current == nil then return false, readReason end
    if not systemTimestampManaged or current ~= systemTimestampTarget then
        systemTimestampSnapshot = current
    end
    if current ~= target then
        systemTimestampApplying = true
        local applied, applyReason = Adapter:SetSystemTimestampFormat(target)
        systemTimestampApplying = false
        if not applied then return false, applyReason end
    end
    systemTimestampManaged = true
    systemTimestampTarget = target
    return true
end

local function ReassertSystemTimestampTarget()
    if not systemTimestampManaged
        or type(systemTimestampTarget) ~= "string"
        or systemTimestampTarget == ""
    then
        return true
    end
    local current, readReason = Adapter:ReadSystemTimestampFormat()
    if current == nil then return false, readReason end
    if current == systemTimestampTarget then return true end
    systemTimestampSnapshot = current
    systemTimestampApplying = true
    local applied, applyReason = Adapter:SetSystemTimestampFormat(systemTimestampTarget)
    systemTimestampApplying = false
    if not applied then return false, applyReason end
    return true
end

local function PrepareProbeFrame(frame, state)
    local config = ReadTimestampConfig()
    local fontFile, fontHeight, fontFlags,
        shadowR, shadowG, shadowB, shadowA, shadowX, shadowY, fontReason
    local typography = YChat.Typography
    if typography and type(typography.ReadAppliedTextStyle) == "function" then
        fontFile, fontHeight, fontFlags,
            shadowR, shadowG, shadowB, shadowA, shadowX, shadowY, fontReason =
            typography:ReadAppliedTextStyle(frame)
    end
    if fontFile == nil and type(Adapter.ReadTimestampTextStyle) == "function" then
        fontFile, fontHeight, fontFlags,
            shadowR, shadowG, shadowB, shadowA, shadowX, shadowY, fontReason =
            Adapter:ReadTimestampTextStyle(frame)
    elseif fontFile == nil then
        fontFile, fontHeight, fontFlags, fontReason = Adapter:ReadTimestampFontStyle(frame)
        shadowR, shadowG, shadowB, shadowA, shadowX, shadowY = 0, 0, 0, 0, 0, 0
    end
    if fontFile == nil then return false, fontReason end
    local fontObject, fontObjectReason = Adapter:ReadTimestampFontObject(frame)
    if fontObject == nil then return false, fontObjectReason end

    local fontChanged = state.timestampFontObject ~= fontObject
        or state.timestampFontFile ~= fontFile
        or state.timestampFontHeight ~= fontHeight
        or state.timestampFontFlags ~= fontFlags
        or state.timestampShadowR ~= shadowR
        or state.timestampShadowG ~= shadowG
        or state.timestampShadowB ~= shadowB
        or state.timestampShadowA ~= shadowA
        or state.timestampShadowX ~= shadowX
        or state.timestampShadowY ~= shadowY
    local poolIncomplete = state.overlayCount < OVERLAY_CAPACITY
    local color = config.color
    local configChanged = state.timestampFormat ~= config.format
        or state.timestampGap ~= config.gap
        or state.timestampColorR ~= color[1]
        or state.timestampColorG ~= color[2]
        or state.timestampColorB ~= color[3]
        or state.timestampColorA ~= color[4]

    local host = state.host
    if host and state.hostReady and not fontChanged and not configChanged and not poolIncomplete then
        return true
    end

    if not host then
        local reason
        host, reason = Adapter:AllocateOverlayHost(frame)
        if not host then return false, reason end
        state.host = host
    end

    if not state.hostReady then
        local configured, configureReason = Adapter:ConfigureOverlayHost(host, frame)
        if not configured then
            Adapter:IsolateOverlayHost(host)
            return false, configureReason
        end
        state.hostReady = true
    end

    local isolated, isolateReason = Adapter:IsolateOverlayHost(host)
    if not isolated then return false, isolateReason end

    if fontChanged or configChanged then
        state.timestampWidth = nil
        state.bodyInset = nil
    end

    local firstIndex = (fontChanged or configChanged) and 1 or state.overlayCount + 1
    for index = firstIndex, OVERLAY_CAPACITY do
        local overlay = state.overlays[index]
        if not overlay then
            local reason
            overlay, reason = Adapter:AllocateTimestampOverlay(host)
            if not overlay then
                RefreshPoolGauges()
                return false, reason
            end
            state.overlays[index] = overlay
            state.overlayAllocatedCount = index
        end

        local fontOK, overlayFontReason =
            Adapter:ConfigureTimestampOverlayFontObject(overlay, fontObject)
        if not fontOK then
            Adapter:IsolateTimestampOverlay(overlay)
            Adapter:IsolateOverlayHost(host)
            RefreshPoolGauges()
            return false, overlayFontReason
        end

        local metricsOK, metricsReason = EnsureTimestampMetrics(state, overlay, config)
        if not metricsOK then
            Adapter:IsolateTimestampOverlay(overlay)
            Adapter:IsolateOverlayHost(host)
            RefreshPoolGauges()
            return false, metricsReason
        end

        local configured, configureReason = Adapter:ConfigureTimestampOverlay(
            overlay,
            state.timestampWidth,
            color,
            ""
        )
        if not configured then
            Adapter:IsolateTimestampOverlay(overlay)
            Adapter:IsolateOverlayHost(host)
            RefreshPoolGauges()
            return false, configureReason
        end
        state.overlayLabels[index] = ""
        state.overlayHasEntry[index] = nil
        shownByOverlay[overlay] = false
        if index > state.overlayCount then state.overlayCount = index end
    end

    state.timestampFontObject = fontObject
    state.timestampFontFile = fontFile
    state.timestampFontHeight = fontHeight
    state.timestampFontFlags = fontFlags
    state.timestampShadowR = shadowR
    state.timestampShadowG = shadowG
    state.timestampShadowB = shadowB
    state.timestampShadowA = shadowA
    state.timestampShadowX = shadowX
    state.timestampShadowY = shadowY
    state.timestampFormat = config.format
    state.timestampGap = config.gap
    state.timestampColorR = color[1]
    state.timestampColorG = color[2]
    state.timestampColorB = color[3]
    state.timestampColorA = color[4]
    RefreshPoolGauges()
    return true
end

local function BindOverlay(overlay, line, width)
    local config = ReadTimestampConfig()
    local bound, reason =
        Adapter:AnchorTimestampOverlay(overlay, line, width, config.gap)
    if bound then shownByOverlay[overlay] = false end
    return bound, reason
end

local function ApplyProbeLayout(frame, state)
    Adapter:SetLineSyncEnabled(false)
    local lineCount = Adapter:GetNumVisibleLines(frame)
    if lineCount > state.overlayCount then return false, "overlay-capacity" end

    local frameOK, frameReason = Adapter:CanCallProtected(frame)
    if not frameOK then return false, frameReason end
    if not state.host or not state.hostReady then return false, "overlay-host-not-ready" end
    local hostOK, hostReason = Adapter:CanCallProtected(state.host)
    if not hostOK then return false, hostReason end
    local overlaysOK, overlaysReason = Adapter:PreflightTimestampOverlays(state.overlays, lineCount)
    if not overlaysOK then return false, overlaysReason end
    local linesOK, linesReason = Adapter:PreflightVisibleLayout(frame)
    if not linesOK then return false, linesReason end
    local hooksOK, hookReason = Adapter:EnsureVisibleLineHooks(frame)
    if not hooksOK then return false, hookReason end

    local hidden, hideReason = HideOverlays(state)
    if not hidden then return false, hideReason end
    UnbindLines(state)

    local topInsert, insertReason = Adapter:ReadInsertModeTop(frame)
    if topInsert == nil then return false, insertReason end
    local spacing, spacingReason = Adapter:ReadSpacing(frame)
    if spacing == nil then return false, spacingReason end
    local bodyInset = state.bodyInset
    if type(bodyInset) ~= "number" then return false, "timestamp-metrics-missing" end
    local layoutOK, layoutReason = Adapter:ApplyVisibleLayout(
        frame,
        bodyInset,
        RIGHT_INSET,
        spacing,
        topInsert,
        BODY_VERTICAL_SAFE_INSET
    )
    if not layoutOK then return false, layoutReason end

    for index = 1, lineCount do
        local line = Adapter:GetVisibleLine(frame, index)
        local overlay = state.overlays[index]
        if not line or not overlay then return false, "visible-line-missing" end
        local bound, bindReason = BindOverlay(overlay, line, state.timestampWidth)
        if not bound then return false, bindReason end
        local adapterBound, adapterBindReason =
            Adapter:BindVisibleLineOverlay(line, overlay)
        if not adapterBound then return false, adapterBindReason end
        overlayByLine[line] = overlay
        frameByLine[line] = frame
        state.boundLines[index] = line
    end

    state.probeApplied = true
    local hostShown, hostShowReason = Adapter:SetOverlayHostShown(state.host, true)
    if not hostShown then
        state.probeApplied = false
        return false, hostShowReason
    end
    local lineSyncReset, lineSyncResetReason =
        Adapter:ResetVisibleLineSyncStates(frame)
    if not lineSyncReset then
        state.probeApplied = false
        return false, lineSyncResetReason
    end
    local lineSyncEnabled, lineSyncReason = Adapter:SetLineSyncEnabled(true)
    if not lineSyncEnabled then
        state.probeApplied = false
        return false, lineSyncReason
    end
    RefreshPoolGauges()
    return true
end

local function RequestNativeRestore(frame, state)
    state.restoreDeferred = false
    state.restoreAwaitingLayout = false
    state.restoreRequestInProgress = true
    RefreshCleanupLeaks()
    local indentOK, indentReason = Adapter:RestoreNativeLayout(frame, state.originalIndent)
    local layoutOK, layoutReason = false, "native-layout-not-requested"
    if indentOK then layoutOK, layoutReason = Adapter:RequestNativeLayout(frame) end
    state.restoreRequestInProgress = false
    if not state.restorePending then return true end
    state.restoreAwaitingLayout = indentOK == true and layoutOK == true
    if state.restoreAwaitingLayout then return false, "native-restore-pending" end
    return false,
        (not indentOK and indentReason)
        or layoutReason
        or "native-restore-failed"
end

local function RestoreFrame(frame, state, retry, defer)
    if not state then return true end
    if state.restoreAwaitingLayout then return false, "native-restore-pending" end

    if state.restorePending then
        if retry ~= true then return false, "native-restore-pending" end
        if state.restoreDeferred then return false, "native-restore-deferred" end
        if state.restoreRetryConsumed then return false, "native-restore-retry-consumed" end
        state.restoreRetryConsumed = true
        return RequestNativeRestore(frame, state)
    end

    state.restorePending = true
    state.restoreRetryConsumed = false

    local hostOK, hostReason = true
    if state.host then hostOK, hostReason = Adapter:SetOverlayHostShown(state.host, false) end
    local overlaysOK, overlaysReason = true
    if not hostOK then overlaysOK, overlaysReason = HideOverlays(state) end
    state.probeApplied = false
    RefreshCleanupLeaks()

    if defer == true and hostOK then
        state.restoreDeferred = true
        deferredRestoreFrame = frame
        deferredRestoreFramesRemaining = EXTREME_RESTORE_DELAY_FRAMES
        local scheduled, scheduleReason = Adapter:SetDeferredDriverEnabled(true)
        if scheduled then return false, "native-restore-deferred" end
        state.restoreDeferred = false
        deferredRestoreFrame = nil
        deferredRestoreFramesRemaining = 0
        Shadow.lastReason = scheduleReason or "native-restore-driver-failed"
    end

    local restored, restoreReason = RequestNativeRestore(frame, state)
    if restored then return true end
    if restoreReason == "native-restore-pending" then
        return false, restoreReason
    end
    return false,
        (not overlaysOK and overlaysReason)
        or (not hostOK and hostReason)
        or restoreReason
        or "native-restore-failed"
end

local function DeferredRestoreStep()
    local frame = deferredRestoreFrame
    local state = frame and frameStates[frame]
    if not frame
        or not state
        or not state.restorePending
        or not state.restoreDeferred
    then
        local appearance = YChat.Appearance
        if appearance
            and type(appearance.IsRestoreRetryActive) == "function"
            and appearance:IsRestoreRetryActive()
            and type(appearance.OnDeferredRestoreStep) == "function"
        then
            local callOK, stillPending, completed =
                pcall(appearance.OnDeferredRestoreStep, appearance)
            if callOK and stillPending == true then return end
            local stopped, stopReason = Adapter:SetDeferredDriverEnabled(false)
            if not stopped then
                Shadow.lastReason =
                    stopReason or "appearance-restore-driver-stop-failed"
                return
            end
            if not callOK then
                Shadow.lastReason = "appearance-restore-driver-callback-failed"
                return
            end
            if completed
                and type(YChat.OnAppearanceRestoreConfirmed) == "function"
            then
                local confirmationCallOK, confirmed, confirmationReason =
                    pcall(YChat.OnAppearanceRestoreConfirmed, YChat)
                if not confirmationCallOK or confirmed ~= true then
                    Shadow.lastReason = confirmationReason
                        or "appearance-restore-confirmation-failed"
                end
            end
            return
        end
        Adapter:SetDeferredDriverEnabled(false)
        deferredRestoreFrame = nil
        deferredRestoreFramesRemaining = 0
        return
    end

    deferredRestoreFramesRemaining = deferredRestoreFramesRemaining - 1
    if deferredRestoreFramesRemaining > 0 then return end

    local appearance = YChat.Appearance
    local appearancePending = appearance
        and type(appearance.IsRestoreRetryActive) == "function"
        and appearance:IsRestoreRetryActive()
    if not appearancePending then
        local stopped, stopReason = Adapter:SetDeferredDriverEnabled(false)
        if not stopped then
            Shadow.lastReason = stopReason or "native-restore-driver-stop-failed"
            return
        end
    end

    deferredRestoreFrame = nil
    deferredRestoreFramesRemaining = 0
    local restored, restoreReason = RequestNativeRestore(frame, state)
    if not restored and restoreReason ~= "native-restore-pending" then
        Shadow.lastReason = restoreReason or "native-restore-request-failed"
    end
end

local function RetryPendingRestore()
    local retried = false
    for frame, state in pairs(frameStates) do
        if state.restorePending
            and not state.restoreAwaitingLayout
            and not state.restoreRetryConsumed
        then
            if state.restoreDeferred then
                if Adapter:HasDeferredDriverCleanupFailure() then
                    local appearance = YChat.Appearance
                    if appearance
                        and type(appearance.IsRestoreRetryActive) == "function"
                        and appearance:IsRestoreRetryActive()
                    then
                        return retried
                    end
                    local stopped, stopReason = Adapter:SetDeferredDriverEnabled(false)
                    if not stopped then
                        Shadow.lastReason = stopReason or "native-restore-driver-stop-failed"
                        return retried
                    end
                    state.restoreDeferred = false
                    deferredRestoreFrame = nil
                    deferredRestoreFramesRemaining = 0
                    local restored, restoreReason = RequestNativeRestore(frame, state)
                    if not restored and restoreReason ~= "native-restore-pending" then
                        Shadow.lastReason = restoreReason or "native-restore-request-failed"
                    end
                    retried = true
                end
            else
                RestoreFrame(frame, state, true)
                retried = true
            end
        end
    end
    return retried
end

EnterQ3 = function(reason, frame)
    local wasProbe = Shadow.probeEnabled
    local restoreReason
    Shadow.lastReason = reason or "unknown"
    ResetFloodWindow()
    local appearance = YChat.Appearance
    if appearance and type(appearance.QuiesceAnimations) == "function" then
        pcall(appearance.QuiesceAnimations, appearance)
    end

    if frame then
        local state = frameStates[frame]
        if state and (state.managed or state.probeApplied or state.restorePending) then
            state.managed = false
            state.resumeAfterRestore = Shadow.productionMode
                and (reason == "restriction-paused" or reason == "restriction-unknown")
            local deferRestore = reason == "extreme-flood"
            local restored
            restored, restoreReason = RestoreFrame(frame, state, false, deferRestore)
            if not restored and restoreReason ~= "native-restore-pending"
                and restoreReason ~= "native-restore-deferred"
            then
                Shadow.lastReason = restoreReason or Shadow.lastReason
            end
        end
    else
        Adapter:SetLineSyncEnabled(false)
        Adapter:SetDisplaySyncEnabled(false)
        for target, state in pairs(frameStates) do
            if state.managed or state.probeApplied or state.restorePending then
                state.managed = false
                state.resumeAfterRestore = Shadow.productionMode
                    and (reason == "restriction-paused" or reason == "restriction-unknown")
                local restored, detail = RestoreFrame(target, state)
                if not restored and not restoreReason then restoreReason = detail end
            end
        end
    end

    local managed = RefreshManagedGauges()
    if managed > 0 then
        SetQualityState("Q2")
    else
        Adapter:SetLineSyncEnabled(false)
        Adapter:SetDisplaySyncEnabled(false)
        SetQualityState("Q3")
    end
    if wasProbe then
        StatIncrement("qualityTransitions")
        StatIncrement("q3Fallbacks")
    end
    if restoreReason then
        Shadow.lastReason = Shadow.lastReason .. "-restore-pending"
        return false, restoreReason
    end
    return false, Shadow.lastReason
end

local function FrameDiscovered(frame, valid, reason)
    local channelInput = YChat.ChannelInput
    if channelInput and type(channelInput.OnFrameDiscovered) == "function" then
        pcall(channelInput.OnFrameDiscovered, channelInput, frame, valid, reason)
    end
    local history = YChat.HistoryRuntime
    if history and type(history.OnFrameDiscovered) == "function" then
        pcall(history.OnFrameDiscovered, history, frame, valid, reason)
    end
    local appearance = YChat.Appearance
    if appearance and type(appearance.OnFrameDiscovered) == "function" then
        pcall(appearance.OnFrameDiscovered, appearance, frame, valid, reason)
    end
    local typography = YChat.Typography
    if typography and type(typography.OnFrameDiscovered) == "function" then
        pcall(typography.OnFrameDiscovered, typography, frame, valid, reason)
    end
    if not valid then
        local state = frameStates[frame]
        if state then
            state.observed = false
            if state.activationFailed then
                state.activationFailed = false
                if Shadow.activationFailures > 0 then
                    Shadow.activationFailures = Shadow.activationFailures - 1
                end
            end
        end
        if state and (state.managed or state.probeApplied or state.restorePending) then
            StatIncrement("shadowMismatches")
            EnterQ3(reason or "frame-invalid", frame)
        end
        return
    end
    local state = EnsureFrameState(frame)
    state.observed = true
    if Shadow.productionMode
        and Shadow.enabled
        and state.managed
        and state.mode == "nativeInline"
        and not state.restorePending
    then
        local applied, _, applyReason = ApplyNativeInlineIndent(frame, true)
        if not applied then EnterQ3(applyReason, frame) end
    elseif Shadow.productionMode and Shadow.enabled and not state.managed and not state.restorePending then
        local activated = ActivateFrame and ActivateFrame(frame, Shadow.activationReason or "frame-discovered")
        if activated == true then
            if state.activationFailed then
                state.activationFailed = false
                if Shadow.activationFailures > 0 then
                    Shadow.activationFailures = Shadow.activationFailures - 1
                end
            end
        elseif not state.activationFailed then
            state.activationFailed = true
            Shadow.activationFailures = Shadow.activationFailures + 1
        end
        local managed = RefreshManagedGauges()
        if managed > 0 then
            SetQualityState(Shadow.activationFailures > 0 and "Q2" or "Q0")
        end
    end
end

local function WindowsChanged(reason)
    local result = true
    local appearance = YChat.Appearance
    if appearance and type(appearance.OnWindowsChanged) == "function" then
        result = appearance:OnWindowsChanged(reason)
    end
    local typography = YChat.Typography
    if typography and type(typography.OnWindowsChanged) == "function" then
        local typographyOK = typography:OnWindowsChanged(reason)
        if typographyOK == false then result = false end
    end
    local channelInput = YChat.ChannelInput
    if channelInput and type(channelInput.OnWindowsChanged) == "function" then
        local channelOK = channelInput:OnWindowsChanged(reason)
        if channelOK == false then result = false end
    end
    local retry = YChat.RetryPendingVisualDomains
    if type(retry) == "function" then pcall(retry, YChat, reason) end
    return result
end

local function TemporaryTypographyChanged(frame, active, reason)
    local typography = YChat.Typography
    if typography and type(typography.OnTemporaryFrameChanged) == "function" then
        return typography:OnTemporaryFrameChanged(frame, active, reason)
    end
    return true
end

local function NativeFontSizeChanged(frame, fontSize)
    local typography = YChat.Typography
    if typography and type(typography.OnNativeFontSizeChanged) == "function" then
        return typography:OnNativeFontSizeChanged(frame, fontSize)
    end
    return true
end

local function ChannelsChanged(reason)
    local channelInput = YChat.ChannelInput
    if channelInput and type(channelInput.OnChannelsChanged) == "function" then
        return channelInput:OnChannelsChanged(reason)
    end
    return true
end

local function MessageAppended(frame)
    if not Shadow.enabled or Shadow.restrictionPaused then return end
    local elementFade = YChat.ElementFade
    if elementFade and type(elementFade.OnMessage) == "function" then
        elementFade:OnMessage(frame)
    end
    local state = frameStates[frame]
    if not state or state.observed ~= true or state.restorePending then return end
    if Shadow.activeTimestampLayout == "nativeInline" then
        local appearance = YChat.Appearance
        if appearance and type(appearance.OnMessage) == "function" then
            appearance:OnMessage(frame)
        end
        return
    end
    local ring = state.ring
    if ring.valid ~= true then return end

    local arrivalTime = ReadArrivalTime()
    if type(arrivalTime) ~= "number"
        or not (arrivalTime > -huge and arrivalTime < huge)
    then
        EnterQ3("arrival-time-invalid", frame)
        return
    end
    local arrivalTick = floor(arrivalTime * ARRIVAL_TICKS_PER_SECOND)
    local extremeFlood = false
    if state.managed then extremeFlood = IsExtremeFlood(arrivalTime, arrivalTick) end

    local entry = GetHistoryEntryFromCursorInCallback(
        Adapter,
        frame,
        state.historyCursor,
        1
    )
    if entry == nil then
        StatIncrement("shadowMismatches")
        EnterQ3("append-entry-missing", frame)
        return
    end
    local timestamp
    local serverSecond
    if syntheticTimestampFrame == frame
        and type(syntheticTimestampEpoch) == "number"
    then
        serverSecond = syntheticTimestampEpoch
        timestamp = FormatServerSecond(serverSecond)
        syntheticTimestampFrame = nil
        syntheticTimestampEpoch = nil
    elseif arrivalTick == cachedArrivalTick
        and ReadTimestampConfig().format == cachedFormat
    then
        timestamp = cachedTimestamp
        serverSecond = cachedSecond
    else
        timestamp, serverSecond = GetTimestampLabel(arrivalTime, arrivalTick)
    end
    local ok = state.ringAppend(ring, entry, serverSecond, timestamp)
    if ok then
        if IncrementMetadataAppends then
            IncrementMetadataAppends(Stats)
        else
            StatIncrement("metadataAppends")
        end
        if extremeFlood then
            EnterQ3("extreme-flood", frame)
        else
            local appearance = YChat.Appearance
            if appearance and type(appearance.OnMessage) == "function" then
                appearance:OnMessage(frame)
            end
        end
    else
        StatIncrement("shadowMismatches")
        EnterQ3("append-mapping-failed", frame)
    end
end

local function MessageBackfilled(frame)
    if not Shadow.enabled then return end
    if Shadow.restrictionPaused then return end
    if Shadow.activeTimestampLayout == "nativeInline" then return end
    local state = frameStates[frame]
    if not state or state.observed ~= true or state.restorePending then return end
    local ring = state.ring
    if not state.ringIsValid(ring) then return end

    if state.managed then
        local arrivalTime, arrivalTick = ReadArrivalSample()
        if arrivalTime == nil then
            EnterQ3("arrival-time-invalid", frame)
            return
        end
        if IsExtremeFlood(arrivalTime, arrivalTick) then
            EnterQ3("extreme-flood", frame)
            return
        end
    end

    local count, countReason = Adapter:ReadNumMessages(frame)
    if count == nil then
        StatIncrement("shadowMismatches")
        EnterQ3(countReason or "backfill-count", frame)
        return
    end
    local entry = GetHistoryEntryInCallback(Adapter, frame, count)
    if entry == nil then
        StatIncrement("shadowMismatches")
        EnterQ3("backfill-entry-missing", frame)
        return
    end
    if ring:Find(entry) == entry then return end
    local timestamp
    local label
    if syntheticTimestampFrame == frame
        and type(syntheticTimestampEpoch) == "number"
    then
        timestamp = syntheticTimestampEpoch
        label = FormatServerSecond(timestamp)
        syntheticTimestampFrame = nil
        syntheticTimestampEpoch = nil
    end
    if ring:Backfill(entry, timestamp, label) then
        if IncrementMetadataAppends then
            IncrementMetadataAppends(Stats)
        else
            StatIncrement("metadataAppends")
        end
        return
    end
    StatIncrement("shadowMismatches")
    EnterQ3("backfill-mapping-missing", frame)
end

local function NativeMappingInvalidated(frame, reason)
    if Shadow.restrictionPaused then return end
    if Shadow.activeTimestampLayout == "nativeInline" then return end
    local state = frameStates[frame]
    if not state or state.observed ~= true or state.restorePending then return end
    if reason == "CLEAR" then
        state.ring:Reset()
        return
    end
    if reason == "MAX_LINES" then
        local maxLines, maxReason = Adapter:ReadMaxLines(frame)
        if maxLines == nil or maxLines > METADATA_CAPACITY then
            state.ring:Invalidate(maxReason or "CAPACITY")
            if state.managed then EnterQ3(maxReason or "max-lines-capacity", frame) end
            return
        end
        MetadataRing:ReleaseFrame(frame)
        local ring = MetadataRing:EnsureForFrame(frame, maxLines)
        state.ring = ring
        state.ringAppend = ring.Append
        state.ringIsValid = ring.IsValid
        state.ringGetDisplayMetadata = ring.GetDisplayMetadataInCallback
        if not PrimeRing(frame, ring) and state.managed then EnterQ3("max-lines-prime", frame) end
        return
    end

    state.ring:Invalidate(reason)
    StatIncrement("shadowMismatches")
    if state.managed then EnterQ3("native-" .. lower(reason or "mutation"), frame) end
end

local function PrepareDeferredStop()
    local ownerCallback = YChat.OnShadowRestoreConfirmed
    if type(ownerCallback) ~= "function" then return false, "restore-owner-callback-missing" end

    local callbackOK, prepared, prepareReason = pcall(ownerCallback, YChat)
    if not callbackOK then return false, "restore-owner-callback-error" end
    if prepared ~= true then return false, prepareReason or "restore-owner-cleanup-failed" end

    local disableCallOK, disabled, disableReason = pcall(Adapter.Disable, Adapter)
    if not disableCallOK then return false, "adapter-disable-error" end
    if disabled ~= true then return false, disableReason or "adapter-disable-failed" end
    return true
end

local function NativeLayoutRefreshed(frame)
    local appearance = YChat.Appearance
    if appearance and type(appearance.OnNativeLayoutRefreshed) == "function" then
        pcall(appearance.OnNativeLayoutRefreshed, appearance, frame)
    end
    if Shadow.restrictionPaused then return end
    local state = frameStates[frame]
    if state and state.restorePending then
        if state.restoreDeferred then return end
        state.restoreAwaitingLayout = false
        local hostOK = true
        if state.host then hostOK = Adapter:SetOverlayHostShown(state.host, false) end
        local indent, indentReason = Adapter:ReadIndentedWordWrap(frame)
        if not hostOK or indent == nil or indent ~= (state.originalIndent ~= false) then
            state.restorePending = true
            Shadow.lastReason = indentReason or "native-restore-ack-failed"
            RefreshCleanupLeaks()
            return
        end

        if Shadow.stopAfterRestore and state.restoreRequestInProgress then
            state.restorePending = true
            Shadow.lastReason = "native-restore-pending"
            RefreshCleanupLeaks()
            return
        end

        UnbindLines(state)
        RefreshPoolGauges()
        if (not Shadow.productionMode or Shadow.stopAfterRestore)
            and not HasOtherPendingRestore(frame)
        then
            local systemRestored, systemRestoreReason = RestoreSystemTimestamp()
            if not systemRestored then
                state.restorePending = true
                Shadow.lastReason = systemRestoreReason or "system-timestamp-restore-failed"
                Adapter:RequestNativeLayout(frame)
                RefreshCleanupLeaks()
                return
            end
        end
        local deferredStop = Shadow.stopAfterRestore
            and not state.restoreRequestInProgress
            and not HasOtherPendingRestore(frame)
        if deferredStop then
            local prepared, prepareReason = PrepareDeferredStop()
            if not prepared then
                state.restorePending = true
                Shadow.lastReason = prepareReason or "native-restore-finalize-failed"
                RefreshCleanupLeaks()
                return
            end
        end

        local resumeAfterRestore = state.resumeAfterRestore == true
        state.restorePending = false
        state.restoreDeferred = false
        state.restoreRetryConsumed = false
        state.resumeAfterRestore = false
        state.needsRestrictionRefresh = nil
        state.managed = false
        state.mode = nil
        state.originalIndent = nil
        RefreshCleanupLeaks()
        RefreshManagedGauges()
        if frame == probeFrame and not Shadow.probeEnabled then
            probeFrame = nil
            probeState = nil
        end
        Shadow.lastReason = "native-restored"
        StatIncrement("q3Restores")
        if deferredStop then
            Shadow.productionMode = false
            Shadow.stopAfterRestore = false
            Shadow.enabled = false
            local committed = YChat.OnShadowRestoreCommitted
            if type(committed) == "function" then pcall(committed, YChat) end
        end
        if resumeAfterRestore
            and Shadow.productionMode
            and Shadow.enabled
            and Adapter:IsEnabled()
        then
            Adapter:RegisterFrame(frame)
        end
        return
    end

    if not Shadow.probeEnabled or not state or state.managed ~= true then return end
    local restriction = Adapter:GetRestrictionState()
    local unsupportedAllowed = restriction == "UNSUPPORTED" and YUI.IsWrath == true
    if restriction ~= "OPEN" and not unsupportedAllowed then
        EnterQ3("restriction-" .. lower(restriction), frame)
        return
    end

    state = EnsureFrameState(frame)
    if state.mode == "nativeInline" then
        local indentOK, _, indentReason = ApplyNativeInlineIndent(frame, false)
        if not indentOK then EnterQ3(indentReason, frame) end
        return
    end
    local prepared, prepareReason = PrepareProbeFrame(frame, state)
    if not prepared then
        EnterQ3(prepareReason, frame)
        return
    end
    local ok, reason = ApplyProbeLayout(frame, state)
    if not ok then EnterQ3(reason, frame) end
end

local function SyncProbeDisplayEntries(frame, state, offset)
    local lines, lineCount, lineReason =
        GetProbeDisplayLinesInCallback(Adapter, frame)
    if not lines then return nil, 0, lineReason end

    local ring = state.ring
    local capacity = ring and ring.capacity
    local count = ring and ring.count
    local head = ring and ring.head
    local entries = ring and ring.entries
    local labels = ring and ring.labels
    if not ring
        or ring.valid ~= true
        or type(capacity) ~= "number"
        or capacity < 1
        or type(count) ~= "number"
        or count < 0
        or type(head) ~= "number"
        or type(entries) ~= "table"
        or type(labels) ~= "table"
    then
        return nil, 0, "metadata-ring-invalid"
    end

    local overlays = state.overlays
    local boundLines = state.boundLines
    local overlayHasEntry = state.overlayHasEntry
    local overlayLabels = state.overlayLabels
    local bufferIndex = offset + 1
    local slot
    if bufferIndex >= 1 and bufferIndex <= count then
        slot = ((head + bufferIndex - 2) % capacity) + 1
    end

    local comparisons = 0
    local displayWrites = 0
    local displaySkips = 0
    for index = 1, lineCount do
        local line = lines[index]
        local overlay = overlays[index]
        if not overlay or boundLines[index] ~= line then
            return nil, comparisons, "visible-line-binding-mismatch"
        end

        local visibleEntry = line and line.messageInfo or nil
        local mappedEntry = slot and entries[slot] or nil
        local label = slot and labels[slot] or nil
        if visibleEntry ~= nil then comparisons = comparisons + 1 end
        if mappedEntry ~= visibleEntry then
            return nil, comparisons, "metadata-mapping-missing"
        end

        if visibleEntry == nil or type(label) ~= "string" or label == "" then
            if overlayHasEntry[index] == true then
                overlayHasEntry[index] = nil
                hasEntryByOverlay[overlay] = nil
            end
            if shownByOverlay[overlay] == true then
                local hidden = SetOverlayShown(overlay, false)
                if not hidden then return nil, comparisons, "overlay-hide" end
            end
        else
            local visibleLabel = label
            if overlayLabels[index] ~= visibleLabel then
                local written, writeReason =
                    SetOverlayTextInCallback(Adapter, overlay, visibleLabel)
                if not written then return nil, comparisons, writeReason end
                overlayLabels[index] = visibleLabel
                displayWrites = displayWrites + 1
            else
                displaySkips = displaySkips + 1
            end
            if overlayHasEntry[index] ~= true then
                overlayHasEntry[index] = true
                hasEntryByOverlay[overlay] = true
            end
            if shownByOverlay[overlay] ~= true then
                local shown = SetOverlayShown(overlay, true)
                if not shown then return nil, comparisons, "overlay-show" end
            end
        end

        bufferIndex = bufferIndex + 1
        if slot then
            if bufferIndex <= count then
                slot = slot < capacity and slot + 1 or 1
            else
                slot = nil
            end
        end
    end

    state.displayWrites = displayWrites
    state.displaySkips = displaySkips
    return lineCount, comparisons
end

local function NativeDisplayRefreshed(frame)
    if not Shadow.enabled then return end
    if Shadow.restrictionPaused then return end
    local state = frameStates[frame]
    if not state or state.observed ~= true or state.restorePending then return end
    if state.mode == "nativeInline" then return end
    local offset, offsetReason = ReadScrollOffsetInCallback(Adapter, frame)
    if offset == nil then
        StatIncrement("shadowMismatches")
        EnterQ3(offsetReason or "scroll-offset", frame)
        return
    end

    state.displayWrites = 0
    state.displaySkips = 0
    if state.probeApplied then
        local lineCount, comparisons, displayReason =
            SyncProbeDisplayEntries(frame, state, offset)
        if lineCount == nil then
            if comparisons > 0 then StatIncrement("shadowComparisons", comparisons) end
            if displayReason == "metadata-mapping-missing"
                or displayReason == "visible-line-binding-mismatch"
            then
                StatIncrement("shadowMismatches")
            end
            EnterQ3(displayReason or "display-validation", frame)
            return
        end
        if comparisons > 0 then StatIncrement("shadowComparisons", comparisons) end
        if lineCount > 0 then StatIncrement("visibleLineSyncs", lineCount) end
        if state.displayWrites > 0 then StatIncrement("overlayWrites", state.displayWrites) end
        if state.displaySkips > 0 then StatIncrement("noOpSkips", state.displaySkips) end
        return
    end

    local lineCount, comparisons, displayReason =
        VisitDisplayEntriesInCallback(Adapter, frame, offset, nil, state)
    if lineCount == nil then
        if comparisons > 0 then StatIncrement("shadowComparisons", comparisons) end
        if displayReason == "identity-mismatch"
            or displayReason == "metadata-mapping-missing"
            or displayReason == "visible-line-binding-mismatch"
        then
            StatIncrement("shadowMismatches")
        end
        EnterQ3(displayReason or "display-validation", frame)
        return
    end

    if comparisons > 0 then StatIncrement("shadowComparisons", comparisons) end
    if lineCount > 0 then StatIncrement("visibleLineSyncs", lineCount) end
    if state.displayWrites > 0 then StatIncrement("overlayWrites", state.displayWrites) end
    if state.displaySkips > 0 then StatIncrement("noOpSkips", state.displaySkips) end
end

local function NativeLineAlpha(line, value)
    if not Shadow.probeEnabled or Shadow.restrictionPaused then return end
    local overlay = overlayByLine[line]
    if not overlay then return end
    if not SetOverlayAlphaInCallback(Adapter, overlay, value) then
        EnterQ3("alpha-sync", frameByLine[line])
    end
end

local function NativeLineShow(line)
    if not Shadow.probeEnabled or Shadow.restrictionPaused then return end
    local overlay = overlayByLine[line]
    if overlay
        and hasEntryByOverlay[overlay] == true
        and shownByOverlay[overlay] ~= true
        and not SetOverlayShown(overlay, true)
    then
        EnterQ3("show-sync", frameByLine[line])
    end
end

local function NativeLineHide(line)
    if not Shadow.probeEnabled or Shadow.restrictionPaused then return end
    local overlay = overlayByLine[line]
    if overlay and not SetOverlayShown(overlay, false) then
        EnterQ3("hide-sync", frameByLine[line])
    end
end

local function RestrictionChanged(state)
    if (state == "PAUSED" or state == "UNKNOWN") and Shadow.probeEnabled then
        StatIncrement("secretBypasses")
        Shadow.restrictionPaused = true
        Adapter:SetLineSyncEnabled(false)
        Adapter:SetDisplaySyncEnabled(false)
        for _, frameState in pairs(frameStates) do
            if frameState.managed == true then
                frameState.needsRestrictionRefresh = true
            end
        end
        SetQualityState("Q2")
        Shadow.lastReason = "restriction-" .. lower(state) .. "-visuals-preserved"
    elseif state == "OPEN" then
        Shadow.restrictionPaused = false
        RetryPendingRestore()
    end
    local callback = YChat.OnRestrictionStateChanged
    if type(callback) == "function" then pcall(callback, YChat, state) end
end

local function AdapterCallbackFailed(name)
    if name == "onDeferred" then
        local frame = deferredRestoreFrame or probeFrame
        local state = frame and frameStates[frame]
        deferredRestoreFrame = nil
        deferredRestoreFramesRemaining = 0
        if state and state.restorePending then
            state.restoreDeferred = false
            local restored, restoreReason = RequestNativeRestore(frame, state)
            if not restored then
                Shadow.lastReason = restoreReason or "native-restore-request-failed"
            end
            return
        end
    end
    EnterQ3("callback-" .. lower(name or "unknown"))
end

local function RescanFrame(frame)
    Adapter:RegisterFrame(frame)
    local state = frameStates[frame]
    if state and state.needsRestrictionRefresh == true and ActivateFrame then
        ActivateFrame(frame, "restriction-open-refresh")
    end
end

ActivateFrame = function(frame, reason)
    if not Shadow.enabled then return false, "shadow-disabled" end
    local state = EnsureFrameState(frame)
    if state.restorePending then return false, "native-restore-pending" end
    local restriction = Adapter:GetRestrictionState()
    if state.managed
        and (state.mode == "nativeInline" or state.probeApplied)
    then
        if state.needsRestrictionRefresh ~= true then return true end
        if restriction ~= "OPEN" then return true end
        state.needsRestrictionRefresh = false
        if state.mode == "nativeInline" then
            local indentOK, _, indentReason = ApplyNativeInlineIndent(frame, false)
            if not indentOK then return EnterQ3(indentReason, frame) end
            return true
        end
        local maxLines, maxReason = Adapter:ReadMaxLines(frame)
        if maxLines == nil or maxLines > METADATA_CAPACITY then
            return EnterQ3(maxReason or "metadata-capacity-exceeded", frame)
        end
        MetadataRing:ReleaseFrame(frame)
        state.ring = MetadataRing:EnsureForFrame(frame, maxLines)
        state.ringAppend = state.ring.Append
        state.ringIsValid = state.ring.IsValid
        state.ringGetDisplayMetadata = state.ring.GetDisplayMetadataInCallback
        if not PrimeRing(frame, state.ring) then
            return EnterQ3("metadata-reprime-failed", frame)
        end
        local prepared, prepareReason = PrepareProbeFrame(frame, state)
        if not prepared then return EnterQ3(prepareReason, frame) end
        local applied, applyReason = ApplyProbeLayout(frame, state)
        if not applied then return EnterQ3(applyReason, frame) end
        return true
    end

    local unsupportedAllowed = restriction == "UNSUPPORTED" and YUI.IsWrath == true
    if restriction ~= "OPEN" and not unsupportedAllowed then
        StatIncrement("secretBypasses")
        return false, "restriction-" .. lower(restriction)
    end

    local maxLines, maxReason = Adapter:ReadMaxLines(frame)
    if maxLines == nil then return false, maxReason end
    if maxLines > METADATA_CAPACITY then return false, "metadata-capacity-exceeded" end
    local protectedOK, protectedReason = Adapter:CanCallProtected(frame)
    if not protectedOK then return false, protectedReason end

    local originalIndent, indentReason = Adapter:ReadIndentedWordWrap(frame)
    if originalIndent == nil then return false, indentReason end
    state.originalIndent = originalIndent

    if Shadow.activeTimestampLayout == "nativeInline" then
        state.managed = true
        state.mode = "nativeInline"
        Shadow.lastReason = reason or "native-inline-frame-enabled"
        RefreshManagedGauges()
        local indentOK, _, inlineIndentReason = ApplyNativeInlineIndent(frame, true)
        if not indentOK then return EnterQ3(inlineIndentReason, frame) end
        if state.managed ~= true then return false, Shadow.lastReason end
        return true
    end

    local layoutOK, layoutReason = Adapter:PreflightVisibleLayout(frame)
    if not layoutOK then return false, layoutReason end

    if not state.ring:IsValid() or state.ring:Capacity() ~= maxLines then
        MetadataRing:ReleaseFrame(frame)
        state.ring = MetadataRing:EnsureForFrame(frame, maxLines)
        state.ringAppend = state.ring.Append
        state.ringIsValid = state.ring.IsValid
        state.ringGetDisplayMetadata = state.ring.GetDisplayMetadataInCallback
    end
    if not PrimeRing(frame, state.ring) then return false, "metadata-reprime-failed" end

    local prepared, prepareReason = PrepareProbeFrame(frame, state)
    if not prepared then return false, prepareReason end

    state.managed = true
    state.mode = "column"
    Shadow.lastReason = reason or "permanent-frame-enabled"
    RefreshManagedGauges()
    layoutOK, layoutReason = Adapter:SetIndentedWordWrap(frame, false)
    if not layoutOK then return EnterQ3(layoutReason, frame) end
    if state.managed ~= true then return false, Shadow.lastReason end
    return true
end

adapterCallbacks = {
    onFrame = FrameDiscovered,
    onWindowsChanged = WindowsChanged,
    onTemporaryTypography = TemporaryTypographyChanged,
    onNativeFontSizeChanged = NativeFontSizeChanged,
    onChannelsChanged = ChannelsChanged,
    onDisplay = NativeDisplayRefreshed,
    onLayout = NativeLayoutRefreshed,
    onAdd = MessageAppended,
    onBackfill = MessageBackfilled,
    onInvalidate = NativeMappingInvalidated,
    onLineAlpha = NativeLineAlpha,
    onLineShow = NativeLineShow,
    onLineHide = NativeLineHide,
    onRestriction = RestrictionChanged,
    onDeferred = DeferredRestoreStep,
    onError = AdapterCallbackFailed,
}

function Shadow:IsEnabled()
    return self.enabled == true
end

function Shadow:IsProbeEnabled()
    return self.probeEnabled == true
end

function Shadow:SetNextHistoricalTimestamp(frame, epoch)
    if frame == nil
        or type(epoch) ~= "number"
        or epoch <= -huge
        or epoch >= huge
        or syntheticTimestampFrame ~= nil
    then
        return false, "historical-timestamp-invalid"
    end
    syntheticTimestampFrame = frame
    syntheticTimestampEpoch = floor(epoch + 0.5)
    return true
end

function Shadow:ClearNextHistoricalTimestamp(frame)
    if frame == nil or syntheticTimestampFrame == frame then
        syntheticTimestampFrame = nil
        syntheticTimestampEpoch = nil
    end
    return true
end

function Shadow:IsNativePrintTimestampActive()
    return self.enabled == true
        and self.productionMode == true
        and self.qualityState ~= "Q3"
        and self.activeTimestampLayout == "nativeInline"
        and systemTimestampManaged == true
        and type(systemTimestampTarget) == "string"
        and systemTimestampTarget ~= ""
end

function Shadow:GetNativePrintTimestamp()
    if not self:IsNativePrintTimestampActive() or not FormatLocalTime then return nil end
    local pattern = gsub(systemTimestampTarget, "%s+|r$", "|r")
    local epoch = ReadServerTime and ReadServerTime() or nil
    local ok, value
    if type(epoch) == "number" and epoch > -huge and epoch < huge then
        ok, value = pcall(FormatLocalTime, pattern, epoch)
    else
        ok, value = pcall(FormatLocalTime, pattern)
    end
    if not ok or type(value) ~= "string" or value == "" then return nil end
    return value
end

function Shadow:FormatHistoricalInlineTimestamp(epoch)
    if not self:IsNativePrintTimestampActive()
        or not FormatLocalTime
        or type(epoch) ~= "number"
        or epoch <= -huge
        or epoch >= huge
    then
        return nil
    end
    local pattern = gsub(systemTimestampTarget, "%s+|r$", "|r")
    local ok, value = pcall(FormatLocalTime, pattern, floor(epoch + 0.5))
    if not ok or type(value) ~= "string" or value == "" then return nil end
    return value
end

function Shadow:RefreshTimestampConfiguration(reason)
    if self.activeTimestampLayout == "nativeInline" then
        if not self.productionMode then
            self.lastReason = reason or "native-inline-config-inactive"
            return true
        end
        local target, targetReason = ResolveManagedSystemTimestamp(
            self.activeTimestampLayout,
            self.activeTimestampFormat,
            self.activeTimestampColor
        )
        if not target then return false, targetReason end
        local applied, applyReason = ApplySystemTimestampTarget(target)
        if not applied then
            self.lastReason = applyReason or reason or "native-inline-config-refresh-failed"
            return false, applyReason
        end
        for frame, state in pairs(frameStates) do
            if state.managed and state.mode == "nativeInline" and not state.restorePending then
                local indentOK, _, indentReason = ApplyNativeInlineIndent(frame, true)
                if not indentOK then return EnterQ3(indentReason, frame) end
            end
        end
        self.lastReason = applyReason or reason or "native-inline-config-refreshed"
        return true
    end
    cachedSecond = nil
    cachedArrivalTick = nil
    cachedTimestamp = ""
    cachedFormat = ReadTimestampConfig().format
    local firstReason
    for frame, state in pairs(frameStates) do
        if state.ring and type(state.ring.Relabel) == "function" then
            local relabeled, relabelReason = state.ring:Relabel(FormatServerSecond)
            if not relabeled and not firstReason then
                firstReason = relabelReason or "timestamp-relabel-failed"
            end
        end
        if state.managed or state.probeApplied then
            local prepared, prepareReason = PrepareProbeFrame(frame, state)
            if prepared then
                Adapter:RequestNativeLayout(frame)
            elseif not firstReason then
                firstReason = prepareReason or "timestamp-refresh-failed"
            end
        end
    end
    self.lastReason = firstReason or reason or "timestamp-config-refreshed"
    return firstReason == nil, firstReason
end

function Shadow:GetRuntimeGauges(target)
    target = target or {}
    local active = 0
    local capacity = 0
    local leaks = 0
    local managed = 0
    for _, state in pairs(frameStates) do
        active = active + #state.boundLines
        capacity = capacity + state.overlayCount
        if state.restorePending then leaks = leaks + 1 end
        if state.managed then managed = managed + 1 end
    end
    target.poolActive = active
    target.poolFree = capacity - active
    target.cleanupLeaks = leaks
    target.qualityState = self.qualityState or "Q3"
    target.activeDrivers = Adapter:IsDeferredDriverEnabled() and 1 or 0
    target.activeTickers = 0
    target.activeTimers = 0
    target.activeAnimations = 0
    target.managedFrames = managed
    target.pendingRestores = leaks
    target.activationFailures = self.activationFailures or 0
    return target
end

function Shadow:SetEnabled(enabled, reason)
    enabled = enabled == true
    if enabled and self.stopAfterRestore then return false, "native-restore-pending" end
    if self.enabled == enabled then
        if not enabled and Adapter:IsEnabled() then return Adapter:Disable() end
        return true
    end

    if enabled then
        self.restrictionPaused = false
        self.enabled = true
        self.lastReason = reason or "shadow-observe"
        SetQualityState("Q3")
        if not Adapter:Enable(adapterCallbacks) then
            self.enabled = false
            return false, "adapter-enable-failed"
        end
        return true
    end

    self.stopAfterRestore = true
    local restored, restoreReason = self:Restore(reason or "shadow-disabled")
    if not restored then return false, restoreReason end
    local disabled, disableReason = Adapter:Disable()
    if not disabled then return false, disableReason end
    self.stopAfterRestore = false
    self.restrictionPaused = false
    self.enabled = false
    return true
end

function Shadow:SetProbeEnabled(enabled, reason, frameName)
    enabled = enabled == true
    if not enabled then
        self.productionMode = false
        return self:Restore(reason or "probe-disabled")
    end
    if not self.enabled then
        local ok, detail = self:SetEnabled(true)
        if not ok then return false, detail end
    end

    local restriction = Adapter:GetRestrictionState()
    local unsupportedAllowed = restriction == "UNSUPPORTED" and YUI.IsWrath == true
    if restriction ~= "OPEN" and not unsupportedAllowed then
        StatIncrement("secretBypasses")
        return false, "restriction-" .. lower(restriction)
    end

    local frame = Adapter:FindFrame(frameName or "ChatFrame1")
    if not frame then return false, "chat-frame-not-found" end
    if self.productionMode and frameStates[frame] and frameStates[frame].managed then return true end
    self.productionMode = false
    if probeFrame and probeFrame ~= frame then
        local previousState = frameStates[probeFrame]
        if previousState then
            previousState.managed = false
            local restored, restoreReason = RestoreFrame(probeFrame, previousState)
            if not restored then
                self.lastReason = "probe-switch-restore-pending"
                RefreshManagedGauges()
                SetQualityState("Q3")
                return false, restoreReason or self.lastReason
            end
        end
    end
    local displaySyncEnabled, displaySyncReason = Adapter:SetDisplaySyncEnabled(true)
    if not displaySyncEnabled then return false, displaySyncReason end
    local activated, activationReason = ActivateFrame(frame, reason or "probe-enabled")
    if not activated then
        Adapter:SetDisplaySyncEnabled(false)
        return false, activationReason
    end
    probeFrame = frame
    probeState = frameStates[frame]
    ResetFloodWindow()
    SetQualityState("Q0")
    StatIncrement("qualityTransitions")
    return true
end

function Shadow:SetPermanentWindowsEnabled(enabled, reason)
    enabled = enabled == true
    if not enabled then
        self.productionMode = false
        return self:Restore(reason or "permanent-windows-disabled")
    end
    if self.stopAfterRestore then return false, "native-restore-pending" end
    if not self.enabled then
        local ok, detail = self:SetEnabled(true, reason)
        if not ok then return false, detail end
    end

    local restriction = Adapter:GetRestrictionState()
    if restriction ~= "OPEN" then
        StatIncrement("secretBypasses")
        return false, "restriction-" .. lower(restriction)
    end

    local target, targetReason = ResolveManagedSystemTimestamp(
        self.activeTimestampLayout,
        self.activeTimestampFormat,
        self.activeTimestampColor
    )
    if not target then return false, targetReason end
    local timestampManaged, timestampManageReason = ApplySystemTimestampTarget(target)
    if not timestampManaged then return false, timestampManageReason end

    local displaySyncEnabled, displaySyncReason = Adapter:SetDisplaySyncEnabled(
        self.activeTimestampLayout == "column"
    )
    if not displaySyncEnabled then
        RestoreSystemTimestamp()
        return false, displaySyncReason
    end

    self.productionMode = true
    self.activationReason = reason or "permanent-windows-enabled"
    self.activationFailures = 0
    for _, state in pairs(frameStates) do state.activationFailed = false end
    ResetFloodWindow()
    Adapter:ForEachFrame(RescanFrame)
    self.activationReason = nil

    local managed = RefreshManagedGauges()
    if managed < 1 then
        Adapter:SetDisplaySyncEnabled(false)
        SetQualityState("Q3")
        local systemRestored, systemRestoreReason = RestoreSystemTimestamp()
        if not systemRestored then return false, systemRestoreReason end
        return false, self.lastReason or "no-supported-permanent-chat-frame"
    end
    SetQualityState(self.activationFailures > 0 and "Q2" or "Q0")
    StatIncrement("qualityTransitions")
    return true
end

function Shadow:RunProbe(argument)
    argument = type(argument) == "string" and argument or ""
    local normalized = lower(argument)
    if normalized == "off" then return self:SetProbeEnabled(false, "command") end
    if normalized == "toggle" then return self:SetProbeEnabled(not self.probeEnabled, "command") end
    if normalized == "" or normalized == "on" then return self:SetProbeEnabled(true, "command") end
    return self:SetProbeEnabled(true, "command", argument)
end

function Shadow:Restore(reason)
    Adapter:SetLineSyncEnabled(false)
    Adapter:SetDisplaySyncEnabled(false)
    local wasProbe = self.probeEnabled
    ResetFloodWindow()
    local pendingReason
    for frame, state in pairs(frameStates) do
        if state.managed or state.probeApplied or state.restorePending then
            state.managed = false
            state.resumeAfterRestore = false
            local restored, restoreReason = RestoreFrame(frame, state)
            if not restored and not pendingReason then
                pendingReason = restoreReason or "native-restore-pending"
            end
        end
    end
    RefreshManagedGauges()
    self.lastReason = reason or "restored"
    SetQualityState("Q3")
    if wasProbe then StatIncrement("qualityTransitions") end
    if pendingReason then
        self.lastReason = (reason or "restore") .. "-pending"
        return false, pendingReason
    end
    self.productionMode = false
    local systemRestored, systemRestoreReason = RestoreSystemTimestamp()
    if not systemRestored then
        self.lastReason = systemRestoreReason or "system-timestamp-restore-failed"
        return false, self.lastReason
    end
    probeFrame = nil
    probeState = nil
    return true
end

function Shadow:OnModuleEnable()
    local config = ReadTimestampConfig()
    local layout = YChat.timestampLayoutAtLoad
        or (type(config.layout) == "string" and config.layout)
        or "column"
    if layout ~= "nativeInline" then layout = "column" end
    local formatName = YChat.timestampFormatAtLoad
        or (type(config.format) == "string" and config.format)
        or "hms"
    if formatName ~= "hm" then formatName = "hms" end
    local color = CopyTimestampColor(YChat.timestampColorAtLoad or config.color)
    if not color then return false, "system-timestamp-color-invalid" end
    YChat.timestampLayoutAtLoad = YChat.timestampLayoutAtLoad or layout
    YChat.timestampFormatAtLoad = YChat.timestampFormatAtLoad or formatName
    YChat.timestampColorAtLoad = YChat.timestampColorAtLoad or color
    if YChat.timestampEnabledAtLoad == nil then
        YChat.timestampEnabledAtLoad = config.enabled == true
    end
    self.activeTimestampLayout = YChat.timestampLayoutAtLoad
    self.activeTimestampFormat = YChat.timestampFormatAtLoad
    self.activeTimestampColor = CopyTimestampColor(YChat.timestampColorAtLoad)
    if not self.activeTimestampColor then return false, "system-timestamp-color-invalid" end
    return true
end

function Shadow:OnModuleDisable()
    return self:SetEnabled(false)
end

function Shadow:OnLifecycleEvent(event, arg1)
    if not self.enabled then return true end
    if event == "PLAYER_ENTERING_WORLD" then
        Adapter:RefreshRestrictionState()
        Adapter:ForEachFrame(RescanFrame)
        RetryPendingRestore()
    elseif event == "PLAYER_REGEN_ENABLED" and YUI.IsWrath == true then
        RetryPendingRestore()
    elseif event == "CVAR_UPDATE"
        and systemTimestampManaged
        and not systemTimestampApplying
        and type(arg1) == "string"
        and lower(arg1) == "showtimestamps"
    then
        local applied, applyReason = ReassertSystemTimestampTarget()
        if not applied then self.lastReason = applyReason end
    end
    return true
end

function Shadow:BuildReport()
    local stats = YChat.Stats
    if not stats or not stats.Get then return T("command.report.empty", "No validation data is available yet.") end
    return format(
        T("command.report.summary", "comparisons=%d mismatches=%d bypasses=%d quality=%s cleanupLeaks=%d"),
        stats:Get("shadowComparisons") or 0,
        stats:Get("shadowMismatches") or 0,
        stats:Get("secretBypasses") or 0,
        tostring(stats:Get("qualityState") or "Q3"),
        stats:Get("cleanupLeaks") or 0
    )
end

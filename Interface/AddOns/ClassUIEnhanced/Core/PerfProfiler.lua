
-- Performance profiler for ClassUIEnhanced.
-- Wraps all addon functions via metatable proxies, collecting per-function
-- timing and memory allocation data using C_AddOnProfiler.MeasureCall.
-- Zero overhead when not actively profiling.

local _
---@type string, private
local addonName, private = ...

---@type detailsframework
local framework = _G["DetailsFramework"]

local debugprofilestop = debugprofilestop
local rawset = rawset

local pairs = pairs
local ipairs = ipairs
local type = type
local getmetatable = getmetatable
local setmetatable = setmetatable
local wipe = wipe
local format = string.format
local tinsert = table.insert
local sort = table.sort

-- ── State ────────────────────────────────────────────────────────────────────

local profiling = false
local startTime = 0
local stopTime = 0

---@type table<string, table<string, {calls:number, totalTime:number, minTime:number, maxTime:number, allocBytes:number, deallocBytes:number}>>
local stats = {}

---@type {n:string, ts:number, ms:number}[]
local traceLog = {}

---@type table<string, {shadow:table, target:table}>
local shadows = {}

local startMetrics = nil
local endMetrics = nil

local reportPanel = nil

-- ── Skip list ────────────────────────────────────────────────────────────────

local skipKeys = {
    L = true,
    public = true,
    db = true,
    profile = true,
    defaultSettings = true,
    Enum = true,
    externalAnchors = true,
    editModeHidden = true,
    changelog = true,
    pandemicColorCurve = true,
    PerfProfiler = true,
}

local function shouldSkip(key, value)
    if type(value) ~= "table" then return true end
    if skipKeys[key] then return true end
    if type(key) == "string" and key:sub(1, 1) == "_" then return true end
    if type(key) == "string" and key:sub(1, 3) == "lib" then return true end
    if getmetatable(value) ~= nil then return true end
    return false
end

-- ── Stats helpers ────────────────────────────────────────────────────────────

local function newStat()
    return { calls = 0, totalTime = 0, minTime = math.huge, maxTime = 0, allocBytes = 0, deallocBytes = 0 }
end

local function ensureGroup(groupName)
    if not stats[groupName] then
        stats[groupName] = {}
    end
    return stats[groupName]
end

local function ensureStat(groupName, funcName)
    local group = ensureGroup(groupName)
    if not group[funcName] then
        group[funcName] = newStat()
    end
    return group[funcName]
end

-- ── Wrapper factory ──────────────────────────────────────────────────────────
-- Uses C_AddOnProfiler.MeasureCall for timing + per-call memory allocation.
-- The inner processResults function uses varargs passthrough (return ...)
-- to forward all return values regardless of count (Perfy pattern).

local function wrapFunction(groupName, funcName, originalFunc)
    local s = ensureStat(groupName, funcName)
    local function processResults(results, ...)
        local elapsed = results.elapsedMilliseconds
        s.calls = s.calls + 1
        s.totalTime = s.totalTime + elapsed
        s.allocBytes = s.allocBytes + results.allocatedBytes
        s.deallocBytes = s.deallocBytes + results.deallocatedBytes
        if elapsed < s.minTime then s.minTime = elapsed end
        if elapsed > s.maxTime then s.maxTime = elapsed end
        traceLog[#traceLog + 1] = { n = groupName .. "." .. funcName, ts = debugprofilestop(), ms = elapsed }
        return ...
    end
    return function(...)
        return processResults(C_AddOnProfiler.MeasureCall(originalFunc, ...))
    end
end

-- ── Table wrapping ───────────────────────────────────────────────────────────

local function wrapTable(groupName, targetTable)
    local shadow = {} -- original functions, keyed by name
    local cache = {}  -- wrapped versions, lazily created by __index
    shadows[groupName] = { shadow = shadow, target = targetTable }
    for k, v in pairs(targetTable) do
        if type(v) == "function" then
            shadow[k] = v
            rawset(targetTable, k, nil)
        end
    end
    setmetatable(targetTable, {
        __index = function(_, key)
            local orig = shadow[key]
            if orig then
                if not cache[key] then cache[key] = wrapFunction(groupName, key, orig) end
                return cache[key]
            end
            -- __index only fires when rawget returns nil. Non-function fields
            -- were never removed, so Lua finds them via rawget before here.
            return nil
        end
    })
end

local function unwrapAll()
    for _, info in pairs(shadows) do
        setmetatable(info.target, nil)
        for k, v in pairs(info.shadow) do rawset(info.target, k, v) end
    end
    wipe(shadows)
end

-- ── Callback.Trigger wrapper ─────────────────────────────────────────────────
-- Special handling: wrap Trigger to record per-event-name timing in a
-- "Callback.Events" stats group, in addition to the normal Callback.Trigger stat.
-- Must be called AFTER wrapTable has processed Callback, so we can grab the
-- real original from the shadow table (avoids __index returning wrapped version).

local originalTrigger = nil

local function installCallbackWrapper()
    local shadowInfo = shadows["Callback"]
    if not shadowInfo then return end
    local origTrigger = shadowInfo.shadow["Trigger"]
    if not origTrigger then return end
    originalTrigger = origTrigger

    local function processCallbackResults(callbackName, results, ...)
        local eventGroup = ensureGroup("Callback.Events")
        local s = eventGroup[callbackName]
        if not s then
            s = newStat()
            eventGroup[callbackName] = s
        end
        local elapsed = results.elapsedMilliseconds
        s.calls = s.calls + 1
        s.totalTime = s.totalTime + elapsed
        s.allocBytes = s.allocBytes + results.allocatedBytes
        s.deallocBytes = s.deallocBytes + results.deallocatedBytes
        if elapsed < s.minTime then s.minTime = elapsed end
        if elapsed > s.maxTime then s.maxTime = elapsed end
        traceLog[#traceLog + 1] = { n = "Callback." .. callbackName, ts = debugprofilestop(), ms = elapsed }
        return ...
    end

    local wrappedTrigger = function(callbackName, ...)
        return processCallbackResults(callbackName, C_AddOnProfiler.MeasureCall(originalTrigger, callbackName, ...))
    end

    -- Remove Trigger from shadow so __index won't double-wrap it.
    -- Place wrappedTrigger directly on the table so rawget finds it.
    shadowInfo.shadow["Trigger"] = nil
    rawset(private.Callback, "Trigger", wrappedTrigger)
end

local function restoreCallbackTrigger()
    if originalTrigger and private.Callback then
        -- Clear the rawset override and put the original back in shadow
        -- so unwrapAll restores it properly
        rawset(private.Callback, "Trigger", nil)
        local shadowInfo = shadows["Callback"]
        if shadowInfo then
            shadowInfo.shadow["Trigger"] = originalTrigger
        else
            -- Shadow already cleaned up, restore directly
            rawset(private.Callback, "Trigger", originalTrigger)
        end
    end
    originalTrigger = nil
end

-- ── C_AddOnProfiler metrics ──────────────────────────────────────────────────

local addonMetricNames = {
    "SessionAverageTime", "RecentAverageTime", "EncounterAverageTime",
    "LastTime", "PeakTime",
    "CountTimeOver1Ms", "CountTimeOver5Ms", "CountTimeOver10Ms",
    "CountTimeOver50Ms", "CountTimeOver100Ms", "CountTimeOver500Ms", "CountTimeOver1000Ms",
}

local function captureAddonMetrics()
    if not C_AddOnProfiler or not C_AddOnProfiler.IsEnabled() then return nil end
    local snapshot = { cue = {}, overall = {} }
    for _, metric in ipairs(addonMetricNames) do
        local enumVal = Enum.AddOnProfilerMetric[metric]
        if enumVal then
            snapshot.cue[metric] = C_AddOnProfiler.GetAddOnMetric(addonName, enumVal)
            snapshot.overall[metric] = C_AddOnProfiler.GetOverallMetric(enumVal)
        end
    end
    return snapshot
end

-- ── Formatting helpers ───────────────────────────────────────────────────────

local function fmtTime(ms)
    if not ms or ms == math.huge or ms == 0 then return "0" end
    if ms >= 1000 then return format("%.1fs", ms / 1000) end
    if ms >= 1 then return format("%.3fms", ms) end
    return format("%.4fms", ms)
end

-- Metrics that are counts (not durations) — display as plain integers
local countMetrics = {
    CountTimeOver1Ms = true, CountTimeOver5Ms = true, CountTimeOver10Ms = true,
    CountTimeOver50Ms = true, CountTimeOver100Ms = true, CountTimeOver500Ms = true,
    CountTimeOver1000Ms = true,
}

-- Metrics where addon-vs-overall percentage is meaningless (maximums, not sums)
local noPercentMetrics = {
    PeakTime = true, LastTime = true,
}

local function fmtMetric(name, val)
    if countMetrics[name] then return format("%d", val) end
    return fmtTime(val)
end

local function fmtBytes(bytes)
    if not bytes or bytes == 0 then return "0B" end
    if bytes >= 1048576 then return format("%.1fMB", bytes / 1048576) end
    if bytes >= 1024 then return format("%.1fKB", bytes / 1024) end
    return format("%dB", bytes)
end

local function fmtMem(kb)
    if not kb then return "?" end
    if kb >= 1024 then return format("%.1fMB", kb / 1024) end
    return format("%.1fKB", kb)
end

local function fmtPercent(value, total)
    if not total or total == 0 then return "" end
    return format(" (%.1f%%)", value / total * 100)
end

-- ── Report generation ────────────────────────────────────────────────────────

local function generateReport()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local duration = (profiling and debugprofilestop() or stopTime) - startTime
    local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"
    add("=== CUE Performance Report === v" .. version)
    add("Duration: " .. fmtTime(duration))
    add("")

    -- C_AddOnProfiler counters are all anchored to login, so raw values include
    -- the /reload loading screen (a multi-second frame that dominates PeakTime
    -- and the CountTimeOverXMs buckets).  Which metrics can be scoped to the
    -- profiling window is decided by the API, not by preference:
    --   * CountTimeOverXMs are monotonic tick counters, so an end-minus-start
    --     snapshot diff scopes them exactly.
    --   * The rest cannot be diffed.  SessionAverageTime/RecentAverageTime/
    --     EncounterAverageTime are means (a difference of two means is not the
    --     window's mean), PeakTime is a max (a difference of two maxima is 0
    --     whenever the window's peak is below the since-login peak), and
    --     LastTime is a single tick.  There is no cumulative total-time or
    --     tick-count metric to reconstruct them from.
    -- So the since-login block lists every metric raw, and a window block adds
    -- the counts diffed on top of it — each number carries its own scope in the
    -- header rather than sharing one easily-misread header.
    local metrics = profiling and captureAddonMetrics() or endMetrics
    if metrics then
        local startOverall = startMetrics and startMetrics.overall
        local startCue = startMetrics and startMetrics.cue

        local function windowCount(current, start, metric)
            local val = current[metric]
            if val and start and start[metric] then
                val = val - start[metric]
            end
            return val
        end

        -- The window block carries only the diffable counters; the since-login
        -- block stays complete (every metric, raw) so the counts can still be
        -- read against the whole session.  showPct is false for the Overall
        -- blocks, whose rows would be compared against themselves.
        local function addBlock(label, windowScoped, current, start, showPct)
            -- No start snapshot (profiler enabled mid-session) means no window
            -- to diff against; skip rather than relabel since-login values.
            if windowScoped and not start then return end
            local scope = windowScoped and "profiling window" or "since login"
            local rows = {}
            for _, metric in ipairs(addonMetricNames) do
                if countMetrics[metric] or not windowScoped then
                    local val = windowScoped and windowCount(current, start, metric) or current[metric]
                    if val and val > 0 then
                        local pct = ""
                        if showPct and not noPercentMetrics[metric] then
                            local overall = windowScoped
                                and windowCount(metrics.overall, startOverall, metric)
                                or metrics.overall[metric]
                            pct = fmtPercent(val, overall)
                        end
                        rows[#rows + 1] = "  " .. metric .. ": " .. fmtMetric(metric, val) .. pct
                    end
                end
            end
            if #rows == 0 then return end
            add("--- " .. label .. " Addon Metrics (" .. scope .. ") ---")
            for _, row in ipairs(rows) do add(row) end
            add("")
        end

        addBlock("Overall", true, metrics.overall, startOverall, false)
        addBlock("ClassUIEnhanced", true, metrics.cue, startCue, true)
        addBlock("Overall", false, metrics.overall, startOverall, false)
        addBlock("ClassUIEnhanced", false, metrics.cue, startCue, true)

        -- Top 10
        if C_AddOnProfiler and C_AddOnProfiler.GetTopKAddOnsForMetric then
            local top = C_AddOnProfiler.GetTopKAddOnsForMetric(Enum.AddOnProfilerMetric.RecentAverageTime, 10)
            if top and #top > 0 then
                add("--- Top 10 Addons (by RecentAverageTime) ---")
                for i, entry in ipairs(top) do
                    add("  " .. i .. ". " .. entry.addOnName .. "  " .. fmtTime(entry.metricValue))
                end
                add("")
            end
        end
    end

    -- Memory (summed from per-call MeasureCall data)
    local totalAlloc, totalDealloc = 0, 0
    for _, group in pairs(stats) do
        for _, s in pairs(group) do
            totalAlloc = totalAlloc + s.allocBytes
            totalDealloc = totalDealloc + s.deallocBytes
        end
    end
    if totalAlloc > 0 or totalDealloc > 0 then
        add("--- Memory (per-call sum) ---")
        add("  Allocated: " .. fmtMem(totalAlloc / 1024) .. " | Deallocated: " .. fmtMem(totalDealloc / 1024) .. " | Net: " .. fmtMem((totalAlloc - totalDealloc) / 1024))
        add("")
    end

    -- Per-function by component
    add("--- Per-Function Breakdown (by component) ---")
    add("")

    local sortedGroups = {}
    for groupName, group in pairs(stats) do
        if groupName ~= "Callback.Events" then
            local groupTotal = 0
            local groupCalls = 0
            local groupAlloc = 0
            for _, s in pairs(group) do
                groupTotal = groupTotal + s.totalTime
                groupCalls = groupCalls + s.calls
                groupAlloc = groupAlloc + s.allocBytes
            end
            if groupCalls > 0 then
                sortedGroups[#sortedGroups + 1] = { name = groupName, totalTime = groupTotal, calls = groupCalls, allocBytes = groupAlloc, group = group }
            end
        end
    end
    sort(sortedGroups, function(a, b) return a.totalTime > b.totalTime end)

    for _, g in ipairs(sortedGroups) do
        add("  [" .. g.name .. "] total: " .. fmtTime(g.totalTime) .. " | " .. g.calls .. " calls | alloc: " .. fmtBytes(g.allocBytes))

        local sortedFuncs = {}
        for funcName, s in pairs(g.group) do
            if s.calls > 0 then
                sortedFuncs[#sortedFuncs + 1] = { name = funcName, s = s }
            end
        end
        sort(sortedFuncs, function(a, b) return a.s.totalTime > b.s.totalTime end)

        for _, f in ipairs(sortedFuncs) do
            local s = f.s
            local avg = s.totalTime / s.calls
            add("    " .. f.name
                .. "  " .. s.calls
                .. "  " .. fmtTime(s.totalTime)
                .. "  avg " .. fmtTime(avg)
                .. "  min " .. fmtTime(s.minTime)
                .. "  max " .. fmtTime(s.maxTime)
                .. "  alloc " .. fmtBytes(s.allocBytes))
        end
        add("")
    end

    -- Per-function flat sorted by total time
    add("--- Per-Function Breakdown (by total time) ---")
    local allFuncs = {}
    for groupName, group in pairs(stats) do
        if groupName ~= "Callback.Events" then
            for funcName, s in pairs(group) do
                if s.calls > 0 then
                    allFuncs[#allFuncs + 1] = { name = groupName .. "." .. funcName, s = s }
                end
            end
        end
    end
    sort(allFuncs, function(a, b) return a.s.totalTime > b.s.totalTime end)
    for _, f in ipairs(allFuncs) do
        local s = f.s
        add("  " .. f.name
            .. "  " .. s.calls
            .. "  " .. fmtTime(s.totalTime)
            .. "  avg " .. fmtTime(s.totalTime / s.calls)
            .. "  alloc " .. fmtBytes(s.allocBytes))
    end
    add("")

    -- Callback events
    local eventGroup = stats["Callback.Events"]
    if eventGroup then
        add("--- Callback Events (by total time) ---")
        local sortedEvents = {}
        for eventName, s in pairs(eventGroup) do
            if s.calls > 0 then
                sortedEvents[#sortedEvents + 1] = { name = eventName, s = s }
            end
        end
        sort(sortedEvents, function(a, b) return a.s.totalTime > b.s.totalTime end)
        for _, e in ipairs(sortedEvents) do
            local s = e.s
            add("  " .. e.name
                .. "  " .. s.calls
                .. "  " .. fmtTime(s.totalTime)
                .. "  avg " .. fmtTime(s.totalTime / s.calls))
        end
        add("")
    end

    return table.concat(lines, "\n")
end

-- ── Report panel ─────────────────────────────────────────────────────────────

local REPORT_PANEL_W, REPORT_PANEL_H = 750, 550
local REPORT_EDITOR_W, REPORT_EDITOR_H = 730, 510
local TRACE_PANEL_W, TRACE_PANEL_H = 550, 180
local TRACE_EDITOR_W, TRACE_EDITOR_H = 530, 130

local function showReportView(text)
    reportPanel.copyBox:ClearFocus()
    reportPanel.copyBox:SetText("")
    reportPanel.copyBox:Hide()
    reportPanel.hintLabel:Hide()
    reportPanel:SetSize(REPORT_PANEL_W, REPORT_PANEL_H)
    reportPanel.editor:SetSize(REPORT_EDITOR_W, REPORT_EDITOR_H)
    reportPanel.editor:SetText(text)
    reportPanel.editor:Show()
end

local function showCopyView(text)
    reportPanel.editor:Hide()
    reportPanel:SetSize(TRACE_PANEL_W, TRACE_PANEL_H)
    reportPanel.editor:SetSize(TRACE_EDITOR_W, TRACE_EDITOR_H)
    reportPanel.copyBox:SetText(text)
    reportPanel.copyBox:Show()
    reportPanel.hintLabel:Show()
    C_Timer.After(0, function()
        if reportPanel.copyBox:IsShown() then
            reportPanel.copyBox:SetFocus()
            reportPanel.copyBox:HighlightText()
        end
    end)
end

local function getOrCreateReportPanel()
    if reportPanel then return reportPanel end
    reportPanel = framework:CreateSimplePanel(UIParent, REPORT_PANEL_W, REPORT_PANEL_H, "CUE Perf Report", "CUEPerfReportPanel")
    reportPanel:SetPoint("CENTER")
    reportPanel:SetFrameStrata("DIALOG")

    local luaeditor_backdrop_color = { .2, .2, .2, .5 }
    local luaeditor_border_color = { 0, 0, 0, 1 }
    local editor = framework:NewSpecialLuaEditorEntry(reportPanel, REPORT_EDITOR_W, REPORT_EDITOR_H, "PerfEditor", "$parentPerfEditor", true, false)
    editor.editbox:SetMaxBytes(0)
    editor.editbox:SetMaxLetters(0)
    editor.editbox:SetFontObject("GameFontHighlight")
    editor:SetPoint("TOPLEFT", reportPanel, "TOPLEFT", 10, -30)
    editor:SetBackdrop({ edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1, bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tileSize = 64, tile = true })
    editor:SetBackdropBorderColor(unpack(luaeditor_border_color))
    editor:SetBackdropColor(unpack(luaeditor_backdrop_color))
    framework:ReskinSlider(editor.scroll)
    reportPanel.editor = editor

    local copyBox = CreateFrame("EditBox", "CUEPerfCopyBox", reportPanel, "BackdropTemplate")
    copyBox:SetPoint("TOPLEFT", editor, "TOPLEFT", 0, -20)
    copyBox:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", 0, 0)
    copyBox:SetMultiLine(false)
    copyBox:SetAutoFocus(false)
    copyBox:SetFontObject("GameFontHighlight")
    copyBox:SetMaxBytes(0)
    copyBox:SetMaxLetters(0)
    copyBox:SetBackdrop({
        edgeFile = [[Interface\Buttons\WHITE8X8]], edgeSize = 1,
        bgFile = [[Interface\Tooltips\UI-Tooltip-Background]], tileSize = 64, tile = true,
    })
    copyBox:SetBackdropBorderColor(unpack(luaeditor_border_color))
    copyBox:SetBackdropColor(unpack(luaeditor_backdrop_color))
    copyBox:SetTextInsets(6, 6, 4, 4)
    copyBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    copyBox:Hide()
    reportPanel.copyBox = copyBox

    local copyBoxClickCatcher = CreateFrame("Frame", nil, copyBox)
    copyBoxClickCatcher:SetAllPoints(copyBox)
    copyBoxClickCatcher:EnableMouse(true)
    local function reselectCopyBox()
        copyBox:SetFocus()
        copyBox:HighlightText()
    end
    copyBoxClickCatcher:SetScript("OnMouseDown", reselectCopyBox)
    copyBox:SetScript("OnCursorChanged", reselectCopyBox)

    local hintLabel = reportPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hintLabel:SetPoint("BOTTOMLEFT", copyBox, "TOPLEFT", 0, 4)
    hintLabel:SetPoint("BOTTOMRIGHT", copyBox, "TOPRIGHT", 0, 4)
    hintLabel:SetJustifyH("CENTER")
    hintLabel:SetText("Click the box below and press Ctrl+C to copy the full trace string.")
    hintLabel:Hide()
    reportPanel.hintLabel = hintLabel

    reportPanel:HookScript("OnHide", function()
        if reportPanel.copyBox then
            reportPanel.copyBox:ClearFocus()
            reportPanel.copyBox:SetText("")
            reportPanel.copyBox:Hide()
        end
        if reportPanel.hintLabel then
            reportPanel.hintLabel:Hide()
        end
        if reportPanel.editor then
            reportPanel.editor:Show()
        end
    end)

    tinsert(UISpecialFrames, "CUEPerfReportPanel")
    reportPanel:Hide()
    return reportPanel
end

local function showReport()
    local panel = getOrCreateReportPanel()
    showReportView(generateReport())
    panel:Show()
end

-- ── Start / Stop ─────────────────────────────────────────────────────────────

local function startProfiling()
    if profiling then
        private.print("Profiling already running. Use /cueperf stop first.")
        return
    end

    -- Reset state
    wipe(stats)
    wipe(traceLog)
    wipe(shadows)

    -- Wrap all addon tables
    for key, value in pairs(private) do
        if type(key) == "string" and not shouldSkip(key, value) then
            wrapTable(key, value)
        end
    end

    -- Wrap component tables (may overlap with above, shadows check handles it)
    if private.ComponentManager and private.ComponentManager.GetAllComponents then
        for _, comp in ipairs(private.ComponentManager.GetAllComponents()) do
            local compName = comp.name or comp.GetComponentName and comp.GetComponentName()
            if compName and not shadows[compName] then
                wrapTable(compName, comp)
            end
        end
    end

    -- Install special Callback.Trigger wrapper
    installCallbackWrapper()

    -- Capture start metrics AFTER wrapping so wrapper allocation overhead
    -- is excluded from the profiled memory delta
    startMetrics = captureAddonMetrics()

    startTime = debugprofilestop()
    profiling = true

    private.print("Profiling started.")
end

local function stopProfiling()
    if not profiling then
        private.print("Profiling is not running.")
        return
    end

    stopTime = debugprofilestop()
    profiling = false

    -- Capture end metrics before unwrapping
    endMetrics = captureAddonMetrics()

    -- Restore callback trigger before unwrapAll (it's stored via rawset)
    restoreCallbackTrigger()

    -- Restore all original functions
    unwrapAll()

    private.print("Profiling stopped. Duration: " .. fmtTime(stopTime - startTime))
    showReport()
end

-- ── Trace export ─────────────────────────────────────────────────────────────

local function exportTrace()
    if #traceLog == 0 then
        private.print("No trace data. Run /cueperf start first.")
        return
    end

    -- Build a compact table for CBOR serialization.
    -- Each entry: {n = name, ts = endTimestamp(ms), ms = duration(ms)}
    -- Convert to Chrome Trace microseconds for the viewer.
    local traceData = {}
    for i, entry in ipairs(traceLog) do
        local endTs = entry.ts * 1000 -- ms → µs
        local durUs = entry.ms * 1000
        traceData[i] = { n = entry.n, ts = endTs - durUs, dur = durUs }
    end

    -- CBOR → Deflate → Base64 (same pipeline as ProfileManager import/export)
    local serialized = C_EncodingUtil.SerializeCBOR(traceData)
    local compressed = C_EncodingUtil.CompressString(serialized, Enum.CompressionMethod.Deflate, Enum.CompressionLevel.OptimizeForSize)
    local encoded = C_EncodingUtil.EncodeBase64(compressed)

    local panel = getOrCreateReportPanel()
    showCopyView(encoded)
    panel:Show()

    private.print("Trace exported (" .. #traceLog .. " events, " .. #encoded .. " chars). Click the box and press Ctrl+C to copy into tools/perf_viewer.html.")
end

-- ── Slash commands ───────────────────────────────────────────────────────────

SLASH_CUEPERF1 = "/cueperf"

SlashCmdList["CUEPERF"] = function(msg)
    local cmd = msg:trim():lower()

    if cmd == "" then
        if profiling then
            stopProfiling()
        else
            startProfiling()
        end
    elseif cmd == "start" then
        startProfiling()
    elseif cmd == "stop" then
        stopProfiling()
    elseif cmd == "report" then
        showReport()
    elseif cmd == "reset" then
        wipe(stats)
        wipe(traceLog)
        startMetrics = captureAddonMetrics()
        startTime = debugprofilestop()
        private.print("Stats reset.")
    elseif cmd == "trace" then
        exportTrace()
    else
        private.print("Usage: /cueperf [start || stop || report || reset || trace]")
    end
end

-- Register help entries for /cue help
private.slashHelp = private.slashHelp or {}
tinsert(private.slashHelp, { cmd = "perf", desc = "toggle performance profiling (/cueperf)" })

-- Expose for minimap menu detection
private.PerfProfiler = {
    IsRunning = function() return profiling end,
    Start = startProfiling,
    Stop = stopProfiling,
    ShowReport = showReport,
    ExportTrace = exportTrace,
}

local YUI = _G.YUI
if not YUI or YUI.SystemMetrics then return end

-- Product-neutral system readings and the shared memory/CPU/network tooltip.
local Metrics = {}
YUI.SystemMetrics = Metrics
local SystemAPI = YUI.API and YUI.API.System or YUI.WOW_API
local FrameAPI = YUI.API and YUI.API.Frame or YUI.WOW_API
local CombatAPI = YUI.API and YUI.API.Combat or YUI.WOW_API
local GUI2 = YUI.GUI2

local function PublicNumber(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

function Metrics:ReadFPS()
    local value = GetFramerate and PublicNumber(GetFramerate())
    return value and math.min(999, math.max(0, math.floor(value))) or 0
end

function Metrics:ReadLatency()
    local home, world
    if GetNetStats then
        local _, _, h, w = GetNetStats()
        home, world = PublicNumber(h), PublicNumber(w)
    end
    home, world = home or 0, world or 0
    return math.min(999, math.max(0, home, world)), home, world
end

function Metrics:Bind(Module, context)
local L = YUI.Locale:Get("SystemMetrics")
local LC = YUI.Locale:Get("Core")
local GetSystemDB = context.getConfig
local IsSystemReady = context.isReady
local cpuProbeID = (context.probePrefix or "product.system-metrics") .. "-cpu-panel"
local systemProbeID = (context.probePrefix or "product.system-metrics") .. "-system"
local pinnedProbeID = (context.probePrefix or "product.system-metrics") .. "-pinned"
local UPDATE_INTERVAL = 1.0
local NETWORK_UPDATE_INTERVAL = 5.0
local TOOLTIP_REFRESH_INTERVAL = 1.0
local TOOLTIP_SORT_INTERVAL = 3.0
local CPU_DIAGNOSTIC_REFRESH_INTERVAL = 5.0
local TOOLTIP_SHIFT_CHECK_INTERVAL = 0.2
local USAGE_REFRESH_SLICE_MS = 1.0
local USAGE_REFRESH_MAX_ADDONS_PER_SLICE = 4
local USAGE_TOOLTIP_DEFAULT_ROWS = 12
local USAGE_TOOLTIP_MAX_ROWS = 40
local USAGE_TOOLTIP_SCREEN_MARGIN = 12
local USAGE_TOOLTIP_FOOTER_ROWS = 7
local PINNED_TOOLTIP_WIDTH = 400
local PINNED_TOOLTIP_PADDING = 12
local PINNED_TOOLTIP_ROW_HEIGHT = 20
local PINNED_TOOLTIP_MIN_HEIGHT = 72
local PINNED_TOOLTIP_TEXT_GAP = 8
local PINNED_TOOLTIP_VALUE_WIDTH = 110
local PINNED_TOOLTIP_CURRENT_WIDTH = 58
local PINNED_TOOLTIP_PEAK_WIDTH = 68
local PINNED_TOOLTIP_COUNT_WIDTH = 58
local PINNED_TOOLTIP_COLUMN_GAP = 6
local GAME_TOOLTIP_METRIC_WIDTH = PINNED_TOOLTIP_CURRENT_WIDTH
    + PINNED_TOOLTIP_PEAK_WIDTH + PINNED_TOOLTIP_COUNT_WIDTH
    + (PINNED_TOOLTIP_COLUMN_GAP * 2)
local GAME_TOOLTIP_NAME_WIDTH = PINNED_TOOLTIP_WIDTH
    - (PINNED_TOOLTIP_PADDING * 2) - GAME_TOOLTIP_METRIC_WIDTH
    - PINNED_TOOLTIP_TEXT_GAP
local GAME_TOOLTIP_METRIC_FORMAT = "%7s %8s %7s"
local PINNED_TOOLTIP_FONT_SIZE = 14
local PINNED_TOOLTIP_BACKGROUND_ALPHA = 0.90
local DEFAULT_CPU_SPIKE_THRESHOLD_MS = 10
local VALID_CPU_SPIKE_THRESHOLDS = {
    [1] = true,
    [5] = true,
    [10] = true,
    [50] = true,
}
local CPU_COUNT_RESET_STATE_VERSION = 1
local CPU_COUNT_RESET_GLOBAL_KEY = "_ybarCPUCountReset"
local CPU_COUNT_RESET_PROCESS_TOLERANCE_SECONDS = 2

local function FormatMemory(value)
    if value > 1024 then
        return format("%.1f mb", value / 1024)
    else
        return format("%.0f kb", value)
    end
end

local function FormatCPU(value)
    if value > 1 then
        return format("%.0f ms", value)
    end

    if value < 0.01 then
        return format("%.4f ms", value)
    end

    return format("%.2f ms", value)
end

local function FormatCPUPercent(value)
    if value >= 10 then return format("%.0f%%", value) end
    if value >= 0.1 then return format("%.1f%%", value) end
    if value >= 0.01 then return format("%.2f%%", value) end
    return "<0.01%"
end

local function FormatCPUPeak(value)
    value = tonumber(value) or 0
    if value <= 0 then return "0ms" end
    if value >= 100 then return format("%.0fms", value) end
    if value >= 10 then return format("%.1fms", value) end
    if value >= 0.01 then return format("%.2fms", value) end
    return "<0.01ms"
end

local function FormatCPUCount(value)
    value = tonumber(value) or 0
    return tostring(math.max(0, math.floor(value)))
end

local function GetSystemCVar(name)
    if SystemAPI and SystemAPI.GetCVar then
        return SystemAPI.GetCVar(name)
    end

    if GetCVar then
        return GetCVar(name)
    end

    return nil
end

local function GetSystemCVarBool(name)
    if SystemAPI and SystemAPI.GetCVarBool then
        return SystemAPI.GetCVarBool(name)
    end

    if GetCVarBool then
        return GetCVarBool(name)
    end

    local value = GetSystemCVar(name)
    return value == true or value == 1 or value == "1" or value == "true"
end

local function SetSystemCVar(name, value)
    if SystemAPI and SystemAPI.SetCVar then
        return SystemAPI.SetCVar(name, value)
    end

    if SetCVar then
        SetCVar(name, value)
        return true
    end

    return false
end

local function GetCurrentFramerate() return Metrics:ReadFPS() end

local infoTable = {}
local workTable = {}
local infoCount = 0
local displayCount = 0
local committedAddonByName = {}
local addonByName = {}
local delimiterFamilyCounts = {}
local familyCounts = {}
local familyRows = {}
local displayRows = {}
local displayGeneration = 0
local addonRosterGeneration = 0
local addonRosterChangeGeneration = 0
local addonRosterDirty = true
local addonRosterInitialized = false
local hasAddonFamilies = false
local usageRefreshJob
local usageRefreshTimer
local usageRefreshGeneration = 0
local usageSortLastUpdate
local usageSortMetric
local function SortMemoryDesc(a, b)
    return (a.memory or 0) > (b.memory or 0)
end

local function SortCPUDesc(a, b)
    return (a.cpu or 0) > (b.cpu or 0)
end

local function GetUsageAddonInfo(index)
    local name, title, _, fourth, fifth = SystemAPI.GetAddOnInfo(index)
    local loadable = fourth
    if not (C_AddOns and C_AddOns.GetAddOnInfo) then
        loadable = fifth
    end

    return name, title or name, loadable
end

local function ClearKeyedTable(target)
    for key in pairs(target) do target[key] = nil end
end

local function IsFamilyPrefix(baseName, addonName)
    local baseLength = #baseName
    if baseLength >= #addonName or addonName:sub(1, baseLength) ~= baseName then
        return false
    end
    local nextCharacter = addonName:sub(baseLength + 1, baseLength + 1)
    return nextCharacter == "_"
        or nextCharacter == "-"
        or nextCharacter:match("%u") ~= nil
        or nextCharacter:match("%d") ~= nil
end

local function BeginAddonFamilyResolution()
    ClearKeyedTable(addonByName)
    ClearKeyedTable(delimiterFamilyCounts)
    ClearKeyedTable(familyCounts)
end

local function IndexAddonFamily(data)
    addonByName[data.name] = data
    local delimiterRoot = data.name:match("^([^_%-]+)[_%-]")
    data.delimiterRoot = delimiterRoot
    if delimiterRoot and #delimiterRoot >= 3 then
        delimiterFamilyCounts[delimiterRoot] =
            (delimiterFamilyCounts[delimiterRoot] or 0) + 1
    end
end

local function ResolveAddonFamily(data)
    local name = data.name
    local base
    for length = #name - 1, 4, -1 do
        local candidate = addonByName[name:sub(1, length)]
        if candidate and IsFamilyPrefix(candidate.name, name) then
            base = candidate
            break
        end
    end
    if base then
        data.familyKey = base.name
        data.familyTitle = base.title
    elseif data.delimiterRoot
        and (delimiterFamilyCounts[data.delimiterRoot] or 0) > 1
    then
        data.familyKey = data.delimiterRoot
        data.familyTitle = data.delimiterRoot
    else
        data.familyKey = name
        data.familyTitle = data.title
    end
    familyCounts[data.familyKey] = (familyCounts[data.familyKey] or 0) + 1
end

local function FinalizeAddonFamily(data)
    data.familyCount = familyCounts[data.familyKey] or 1
    if data.familyCount > 1 then
        data.familyDisplayTitle = format("%s (%d)", data.familyTitle, data.familyCount)
        return true
    end
    data.familyKey = data.name
    data.familyTitle = data.title
    data.familyDisplayTitle = data.title
    return false
end

local function CopyUsageRow(target, source)
    target.index = source.index
    target.name = source.name
    target.title = source.title
    target.loadable = source.loadable
    target.delimiterRoot = source.delimiterRoot
    target.familyKey = source.familyKey
    target.familyTitle = source.familyTitle
    target.familyDisplayTitle = source.familyDisplayTitle
    target.familyCount = source.familyCount
    target.memory = source.memory or 0
    target.cpu = source.cpu or 0
    target.peak = source.peak or 0
    target.spikeCount = source.spikeCount or 0
end

local function RebuildGroupedDisplayRows(metric, sortRows)
    displayGeneration = displayGeneration + 1
    local generation = displayGeneration
    local count = 0
    for index = 1, infoCount do
        local data = infoTable[index]
        local key = data.familyKey
        local row = familyRows[key]
        if not row then
            row = {}
            familyRows[key] = row
        end
        if row.generation ~= generation then
            row.generation = generation
            row.key = key
            row.title = data.familyDisplayTitle
            row.memory = 0
            row.cpu = 0
            row.peak = 0
            row.spikeCount = 0
            row.members = data.familyCount
            count = count + 1
        end
        row[metric] = (row[metric] or 0) + (data[metric] or 0)
        if metric == "cpu" then
            row.peak = math.max(row.peak or 0, data.peak or 0)
            row.spikeCount = (row.spikeCount or 0) + (data.spikeCount or 0)
        end
    end

    if sortRows or displayCount ~= count then
        for index = 1, #displayRows do displayRows[index] = nil end
        local added = 0
        for index = 1, infoCount do
            local row = familyRows[infoTable[index].familyKey]
            if row and row.generation == generation and row.displayGeneration ~= generation then
                row.displayGeneration = generation
                added = added + 1
                displayRows[added] = row
            end
        end
        displayCount = added
        table.sort(displayRows, metric == "cpu" and SortCPUDesc or SortMemoryDesc)
    end
end

local function ReorderUsageRows(metric)
    table.sort(infoTable, metric == "cpu" and SortCPUDesc or SortMemoryDesc)
    if hasAddonFamilies then
        RebuildGroupedDisplayRows(metric, true)
    else
        displayCount = 0
    end
end

local function RefreshGroupedDisplayValues(metric)
    if hasAddonFamilies then
        RebuildGroupedDisplayRows(metric, false)
    else
        displayCount = 0
    end
end

local function BuildDisplayRows(metric, splitFamilies)
    if splitFamilies or not hasAddonFamilies then
        return infoTable, infoCount
    end
    return displayRows, displayCount
end

local function GetSystemCPUProbeState()
    return {
        runtimeRunning = Module.runtimeTicker ~= nil,
        pinnedRunning = Module.pinnedTooltipTicker ~= nil,
        pinnedShown = Module:IsPinnedTooltipShown() == true,
        refreshPending = usageRefreshJob ~= nil,
        refreshPhase = usageRefreshJob and usageRefreshJob.stage or nil,
    }
end

local function PinnedTooltipTickerCallback()
    local cpuWatchdog = YUI.CPUWatchdog
    local cpuStartedAt = cpuWatchdog and cpuWatchdog.timingActive and cpuWatchdog:BeginProbeTiming()
    if Module:IsPinnedTooltipShown() then
        Module:RefreshPinnedTooltip(true)
    else
        Module:StopPinnedTooltipTicker()
    end
    if cpuStartedAt then cpuWatchdog:EndProbeTiming(pinnedProbeID, cpuStartedAt) end
end

local function SystemRuntimeTickerCallback()
    local cpuWatchdog = YUI.CPUWatchdog
    local cpuStartedAt = cpuWatchdog and cpuWatchdog.timingActive and cpuWatchdog:BeginProbeTiming()
    Module:RefreshRuntimeValues(false)
    if cpuStartedAt then cpuWatchdog:EndProbeTiming(systemProbeID, cpuStartedAt) end
end

local usageTooltipDataMode
local usageTooltipDataLastUpdate
local usageTooltipTotalMemory
local usageTooltipTotalCPU
local usageTooltipCPUIsRecent = false
local usageTooltipApplicationCPU
local usageTooltipOverallPeak
local usageTooltipOverallSpikeCount
local usageTooltipDiagnosticsAvailable = false
local usageTooltipDiagnosticLastUpdate
local usageTooltipDiagnosticThreshold
local usageTooltipDiagnosticRosterGeneration
local cpuCountResetActive = false
local cpuCountResetBaselines = {
    [1] = {},
    [5] = {},
    [10] = {},
    [50] = {},
}
local cpuOverallCountResetBaselines = {}
local cpuCountResetProcessStartedAt
local cpuCountResetStateDirty = false
local cpuCountResetRestoreAttempted = false

local function NormalizeResetCount(value, baseline)
    if value == nil or baseline == nil then return value, false end
    if value < baseline then return value, true end
    return value - baseline, false
end

local function IsValidCPUCount(value)
    return type(value) == "number"
        and value >= 0
        and value == value
        and value ~= math.huge
end

local function GetCPUCountResetProcessStartedAt()
    local serverTime = SystemAPI.GetServerTime and SystemAPI.GetServerTime() or nil
    local uptime = CombatAPI.GetTime and CombatAPI.GetTime() or nil
    if not IsValidCPUCount(serverTime) or not IsValidCPUCount(uptime) then
        return nil
    end
    return serverTime - uptime
end

local function ClearCPUCountResetMemory()
    for _, baselines in pairs(cpuCountResetBaselines) do
        ClearKeyedTable(baselines)
    end
    ClearKeyedTable(cpuOverallCountResetBaselines)
    cpuCountResetActive = false
    cpuCountResetProcessStartedAt = nil
    cpuCountResetStateDirty = false
end

local function CopyValidCPUCounts(target, source, keyedByName)
    if type(source) ~= "table" then return false end
    local copied = false
    for key, value in pairs(source) do
        local validKey = keyedByName and type(key) == "string" and key ~= ""
            or not keyedByName and VALID_CPU_SPIKE_THRESHOLDS[key] == true
        if validKey and IsValidCPUCount(value) then
            target[key] = math.floor(value)
            copied = true
        end
    end
    return copied
end

local function SaveCPUCountResetState()
    cpuCountResetStateDirty = false
    local global = YUI and YUI.global
    if type(global) ~= "table" then return false end
    if not cpuCountResetActive then
        global[CPU_COUNT_RESET_GLOBAL_KEY] = nil
        return true
    end

    local processStartedAt = GetCPUCountResetProcessStartedAt()
        or cpuCountResetProcessStartedAt
    if type(processStartedAt) ~= "number" then
        global[CPU_COUNT_RESET_GLOBAL_KEY] = nil
        return false
    end

    local addonCounts = {}
    for threshold, baselines in pairs(cpuCountResetBaselines) do
        local saved = {}
        CopyValidCPUCounts(saved, baselines, true)
        addonCounts[threshold] = saved
    end
    local overallCounts = {}
    CopyValidCPUCounts(overallCounts, cpuOverallCountResetBaselines, false)
    global[CPU_COUNT_RESET_GLOBAL_KEY] = {
        version = CPU_COUNT_RESET_STATE_VERSION,
        processStartedAt = processStartedAt,
        addonCounts = addonCounts,
        overallCounts = overallCounts,
    }
    cpuCountResetProcessStartedAt = processStartedAt
    return true
end

local function RestoreCPUCountResetState()
    cpuCountResetRestoreAttempted = true
    ClearCPUCountResetMemory()
    local global = YUI and YUI.global
    local state = type(global) == "table" and global[CPU_COUNT_RESET_GLOBAL_KEY] or nil
    if type(state) ~= "table" or state.version ~= CPU_COUNT_RESET_STATE_VERSION then
        if type(global) == "table" then global[CPU_COUNT_RESET_GLOBAL_KEY] = nil end
        return false
    end

    local processStartedAt = GetCPUCountResetProcessStartedAt()
    if type(processStartedAt) ~= "number"
        or type(state.processStartedAt) ~= "number"
        or math.abs(processStartedAt - state.processStartedAt)
            > CPU_COUNT_RESET_PROCESS_TOLERANCE_SECONDS
    then
        global[CPU_COUNT_RESET_GLOBAL_KEY] = nil
        return false
    end

    local restored = false
    local addonCounts = state.addonCounts
    if type(addonCounts) == "table" then
        for threshold, baselines in pairs(cpuCountResetBaselines) do
            restored = CopyValidCPUCounts(baselines, addonCounts[threshold], true) or restored
        end
    end
    restored = CopyValidCPUCounts(
        cpuOverallCountResetBaselines,
        state.overallCounts,
        false
    ) or restored
    cpuCountResetActive = restored
    cpuCountResetProcessStartedAt = processStartedAt
    if not restored then global[CPU_COUNT_RESET_GLOBAL_KEY] = nil end
    return restored
end

local function ApplyAddonCountReset(name, threshold, value)
    if not cpuCountResetActive then return value end
    local baselines = cpuCountResetBaselines[threshold]
    local baseline = baselines and baselines[name]
    local normalized, rebase = NormalizeResetCount(value, baseline)
    if rebase then
        baselines[name] = 0
        cpuCountResetStateDirty = true
    end
    return normalized
end

local function ApplyOverallCountReset(threshold, value)
    if not cpuCountResetActive then return value end
    local baseline = cpuOverallCountResetBaselines[threshold]
    local normalized, rebase = NormalizeResetCount(value, baseline)
    if rebase then
        cpuOverallCountResetBaselines[threshold] = 0
        cpuCountResetStateDirty = true
    end
    return normalized
end

local function BeginCPUCountResetCapture(job)
    cpuCountResetRestoreAttempted = true
    job.resetAddonCounts = {
        [1] = {},
        [5] = {},
        [10] = {},
        [50] = {},
    }
    job.resetOverallCounts = {}
    job.resetCaptured = false
    job.resetIndex = 1
    job.stage = "reset-baselines"
end

local function CaptureCPUCountResetRow(job, data)
    for threshold, baselines in pairs(job.resetAddonCounts) do
        local count = SystemAPI.GetAddOnCPUThresholdCount
            and SystemAPI.GetAddOnCPUThresholdCount(data.name, threshold)
            or nil
        if count ~= nil then
            baselines[data.name] = count
            job.resetCaptured = true
        end
    end
end

local function FinishCPUCountResetCapture(job)
    for threshold in pairs(job.resetAddonCounts) do
        local count = SystemAPI.GetOverallCPUThresholdCount
            and SystemAPI.GetOverallCPUThresholdCount(threshold)
            or nil
        if count ~= nil then
            job.resetOverallCounts[threshold] = count
            job.resetCaptured = true
        end
    end

end

local function ProfileNowMS()
    if debugprofilestop then return debugprofilestop() end
    if CombatAPI.GetTime then return CombatAPI.GetTime() * 1000 end
    return 0
end

local function IsUsageTooltipVisible()
    if Module:IsPinnedTooltipShown() then return true end
    local owner = Module.usageTooltipOwner
    if not owner or owner.isHovered ~= true then return false end
    if not GameTooltip or not GameTooltip.GetOwner then return true end
    local tooltipOwner = GameTooltip:GetOwner()
    return tooltipOwner == owner or tooltipOwner == owner.actionHost
end

local function RefreshVisibleUsageTooltip()
    if Module:IsPinnedTooltipShown() then
        Module:RefreshPinnedTooltip(false)
        return
    end
    local owner = Module.usageTooltipOwner
    if owner and owner.isHovered and owner.RefreshUsageTooltip then
        owner:RefreshUsageTooltip(false)
    end
end

local function CancelUsageRefresh()
    usageRefreshGeneration = usageRefreshGeneration + 1
    local timer = usageRefreshTimer
    usageRefreshTimer = nil
    usageRefreshJob = nil
    if timer and timer ~= true and timer.Cancel then
        timer:Cancel()
    end
end

local function ClearUsageTooltipCache()
    CancelUsageRefresh()
    usageTooltipDataMode = nil
    usageTooltipDataLastUpdate = nil
    usageTooltipTotalMemory = nil
    usageTooltipTotalCPU = nil
    usageTooltipCPUIsRecent = false
    usageTooltipApplicationCPU = nil
    usageTooltipOverallPeak = nil
    usageTooltipOverallSpikeCount = nil
    usageTooltipDiagnosticsAvailable = false
    usageTooltipDiagnosticLastUpdate = nil
    usageTooltipDiagnosticThreshold = nil
    usageTooltipDiagnosticRosterGeneration = nil
end

local function AcquireUsageWorkRow(index)
    local data = workTable[index]
    if not data then
        data = {}
        workTable[index] = data
    end
    return data
end

local function PrepareUsageMetricPhase(job)
    if job.useMemory then
        if UpdateAddOnMemoryUsage then UpdateAddOnMemoryUsage() end
    elseif not job.modern and UpdateAddOnCPUUsage then
        UpdateAddOnCPUUsage()
    end
    job.metricIndex = 1
    job.totalValue = 0
    job.stage = "metrics"
end

local function FinishUsageMetricPhase(job)
    if not job.useMemory and job.modern then
        job.totalValue = SystemAPI.GetOverallCPURecentAverage
            and SystemAPI.GetOverallCPURecentAverage()
            or job.totalValue
        job.applicationCPU = SystemAPI.GetApplicationCPURecentAverage
            and SystemAPI.GetApplicationCPURecentAverage()
            or nil
    end
    if job.diagnosticsDue then
        job.diagnosticIndex = 1
        job.diagnosticsAvailable = false
        job.stage = "diagnostics"
    else
        job.stage = "commit"
    end
end

local function CommitUsageRefresh(job)
    if usageRefreshJob ~= job or job.generation ~= usageRefreshGeneration then return false end
    if job.rosterChangeGeneration ~= addonRosterChangeGeneration then
        CancelUsageRefresh()
        RefreshVisibleUsageTooltip()
        return false
    end

    for index = job.rowCount + 1, #workTable do workTable[index] = nil end
    infoTable, workTable = workTable, infoTable
    infoCount = job.rowCount

    if job.rosterChanged then
        hasAddonFamilies = job.hasAddonFamilies == true
        addonRosterInitialized = true
        addonRosterDirty = false
        addonRosterGeneration = addonRosterGeneration + 1
    end

    ClearKeyedTable(committedAddonByName)
    for index = 1, infoCount do
        committedAddonByName[infoTable[index].name] = infoTable[index]
    end

    local now = CombatAPI.GetTime()
    local metric = job.useMemory and "memory" or "cpu"
    local sortRows = job.rosterChanged
        or usageSortMetric ~= metric
        or not usageSortLastUpdate
        or now - usageSortLastUpdate >= TOOLTIP_SORT_INTERVAL
    if sortRows then
        ReorderUsageRows(metric)
        usageSortMetric = metric
        usageSortLastUpdate = now
    else
        RefreshGroupedDisplayValues(metric)
    end

    usageTooltipDataMode = job.mode
    usageTooltipDataLastUpdate = now
    if job.useMemory then
        usageTooltipTotalMemory = job.totalValue or 0
        usageTooltipCPUIsRecent = false
        usageTooltipApplicationCPU = nil
    else
        usageTooltipTotalCPU = job.totalValue or 0
        usageTooltipCPUIsRecent = job.modern == true
        usageTooltipApplicationCPU = job.applicationCPU
    end

    if job.diagnosticsDue then
        usageTooltipOverallPeak = job.overallPeak
        usageTooltipOverallSpikeCount = job.overallSpikeCount
        usageTooltipDiagnosticsAvailable = job.diagnosticsAvailable == true
        usageTooltipDiagnosticLastUpdate = now
        usageTooltipDiagnosticThreshold = job.threshold
        usageTooltipDiagnosticRosterGeneration = addonRosterGeneration
        if cpuCountResetStateDirty then SaveCPUCountResetState() end
    end

    local onCommit = job.onCommit
    usageRefreshJob = nil
    usageRefreshTimer = nil
    if onCommit then
        onCommit(job)
    else
        RefreshVisibleUsageTooltip()
    end
    return true
end

local function CommitCPUCountResetCapture(job)
    if usageRefreshJob ~= job or job.generation ~= usageRefreshGeneration then return false end
    if job.rosterChangeGeneration ~= addonRosterChangeGeneration then
        CancelUsageRefresh()
        return false
    end
    cpuCountResetBaselines = job.resetAddonCounts
    cpuOverallCountResetBaselines = job.resetOverallCounts
    cpuCountResetActive = job.resetCaptured == true
    cpuCountResetProcessStartedAt = GetCPUCountResetProcessStartedAt()
    cpuCountResetStateDirty = false
    SaveCPUCountResetState()
    local onCommit = job.onCommit
    usageRefreshJob = nil
    usageRefreshTimer = nil
    if onCommit then onCommit(job) end
    return true
end

local ScheduleUsageRefresh

local function RunUsageRefreshSlice(job)
    if usageRefreshJob ~= job or job.generation ~= usageRefreshGeneration then return 0, false end
    if not IsUsageTooltipVisible() then
        CancelUsageRefresh()
        return 0, false
    end

    local cpuWatchdog = YUI.CPUWatchdog
    local cpuStartedAt = cpuWatchdog and cpuWatchdog.timingActive and cpuWatchdog:BeginProbeTiming()
    local deadline = ProfileNowMS() + USAGE_REFRESH_SLICE_MS
    local processed = 0
    local finished = false

    repeat
        if job.stage == "roster" then
            local index = job.rosterIndex
            if index > job.rosterTotal then
                if job.resetOnly then
                    job.stage = "reset-prepare"
                else
                    job.familyIndex = 1
                    job.stage = "families"
                end
            else
                local name, title, loadable = GetUsageAddonInfo(index)
                local loaded = SystemAPI.IsAddOnLoaded(index)
                    or (name and SystemAPI.IsAddOnLoaded(name))
                if loaded and type(name) == "string" and name ~= "" then
                    job.rowCount = job.rowCount + 1
                    local data = AcquireUsageWorkRow(job.rowCount)
                    local previous = committedAddonByName[name]
                    data.index = index
                    data.name = name
                    data.title = title or name or tostring(index)
                    data.loadable = loadable
                    data.memory = previous and previous.memory or 0
                    data.cpu = previous and previous.cpu or 0
                    data.peak = previous and previous.peak or 0
                    data.spikeCount = previous and previous.spikeCount or 0
                    IndexAddonFamily(data)
                end
                job.rosterIndex = index + 1
                processed = processed + 1
            end
        elseif job.stage == "families" then
            local index = job.familyIndex
            if index > job.rowCount then
                job.familyIndex = 1
                job.stage = "family-finalize"
            else
                ResolveAddonFamily(workTable[index])
                job.familyIndex = index + 1
                processed = processed + 1
            end
        elseif job.stage == "family-finalize" then
            local index = job.familyIndex
            if index > job.rowCount then
                job.stage = "metric-prepare"
            else
                if FinalizeAddonFamily(workTable[index]) then
                    job.hasAddonFamilies = true
                end
                job.familyIndex = index + 1
                processed = processed + 1
            end
        elseif job.stage == "metric-prepare" then
            PrepareUsageMetricPhase(job)
        elseif job.stage == "reset-prepare" then
            BeginCPUCountResetCapture(job)
        elseif job.stage == "reset-baselines" then
            local index = job.resetIndex
            if index > job.rowCount then
                FinishCPUCountResetCapture(job)
                job.stage = job.resetOnly and "reset-commit" or "metric-prepare"
            else
                local data = job.rosterChanged and workTable[index] or infoTable[index]
                CaptureCPUCountResetRow(job, data)
                job.resetIndex = index + 1
                processed = processed + 1
            end
        elseif job.stage == "metrics" then
            local index = job.metricIndex
            if index > job.rowCount then
                FinishUsageMetricPhase(job)
            else
                local data = workTable[index]
                if not job.rosterChanged then
                    data = AcquireUsageWorkRow(index)
                    CopyUsageRow(data, infoTable[index])
                end
                if job.useMemory then
                    local value = GetAddOnMemoryUsage and GetAddOnMemoryUsage(data.index) or 0
                    data.memory = value
                    job.totalValue = job.totalValue + value
                elseif job.modern then
                    local value = SystemAPI.GetAddOnCPURecentAverage(data.name) or 0
                    data.cpu = value
                    job.totalValue = job.totalValue + value
                else
                    local value = GetAddOnCPUUsage and GetAddOnCPUUsage(data.index) or 0
                    data.cpu = value
                    job.totalValue = job.totalValue + value
                end
                job.metricIndex = index + 1
                processed = processed + 1
            end
        elseif job.stage == "diagnostics" then
            local index = job.diagnosticIndex
            if index > job.rowCount then
                job.overallPeak = SystemAPI.GetOverallCPUPeakTime
                    and SystemAPI.GetOverallCPUPeakTime()
                    or nil
                job.overallSpikeCount = SystemAPI.GetOverallCPUThresholdCount
                    and SystemAPI.GetOverallCPUThresholdCount(job.threshold)
                    or nil
                job.overallSpikeCount = ApplyOverallCountReset(
                    job.threshold,
                    job.overallSpikeCount
                )
                if job.overallPeak ~= nil or job.overallSpikeCount ~= nil then
                    job.diagnosticsAvailable = true
                end
                job.stage = "commit"
            else
                local data = workTable[index]
                local peak = SystemAPI.GetAddOnCPUPeakTime
                    and SystemAPI.GetAddOnCPUPeakTime(data.name)
                    or nil
                local count = SystemAPI.GetAddOnCPUThresholdCount
                    and SystemAPI.GetAddOnCPUThresholdCount(data.name, job.threshold)
                    or nil
                count = ApplyAddonCountReset(data.name, job.threshold, count)
                if peak ~= nil or count ~= nil then job.diagnosticsAvailable = true end
                data.peak = peak or 0
                data.spikeCount = count or 0
                job.diagnosticIndex = index + 1
                processed = processed + 1
            end
        elseif job.stage == "commit" then
            finished = CommitUsageRefresh(job)
            break
        elseif job.stage == "reset-commit" then
            finished = CommitCPUCountResetCapture(job)
            break
        else
            CancelUsageRefresh()
            break
        end
    until processed >= USAGE_REFRESH_MAX_ADDONS_PER_SLICE
        or ProfileNowMS() >= deadline

    if cpuStartedAt then
        cpuWatchdog:EndProbeTiming(cpuProbeID, cpuStartedAt)
    end
    if usageRefreshJob == job and not finished and not job.synchronous then
        ScheduleUsageRefresh(job)
    end
    return processed, finished
end

ScheduleUsageRefresh = function(job)
    if usageRefreshJob ~= job or usageRefreshTimer then return end
    if not job.resume then
        job.resume = function()
            usageRefreshTimer = nil
            if usageRefreshJob ~= job or job.generation ~= usageRefreshGeneration then return end
            RunUsageRefreshSlice(job)
        end
    end
    if C_Timer and C_Timer.NewTimer then
        usageRefreshTimer = C_Timer.NewTimer(0, job.resume)
    else
        job.synchronous = true
        while usageRefreshJob == job do RunUsageRefreshSlice(job) end
        job.synchronous = nil
    end
end

local function StartUsageRefresh(mode, now, options)
    options = options or {}
    if usageRefreshJob and usageRefreshJob.mode == mode
        and not options.captureResetBaselines
    then
        return usageRefreshJob
    end
    if usageRefreshJob then CancelUsageRefresh() end

    usageRefreshGeneration = usageRefreshGeneration + 1
    local useMemory = mode == "memory"
    local modern = not useMemory
        and SystemAPI.CanReadRecentAddOnCPUUsage
        and SystemAPI.CanReadRecentAddOnCPUUsage() == true
    local db = GetSystemDB()
    local threshold = tonumber(db.cpuSpikeThresholdMs)
    if not VALID_CPU_SPIKE_THRESHOLDS[threshold] then
        threshold = DEFAULT_CPU_SPIKE_THRESHOLD_MS
    end
    if modern and not cpuCountResetRestoreAttempted then RestoreCPUCountResetState() end

    local rosterChanged = addonRosterDirty or not addonRosterInitialized
    local job = {
        generation = usageRefreshGeneration,
        rosterChangeGeneration = addonRosterChangeGeneration,
        mode = mode,
        useMemory = useMemory,
        modern = modern,
        threshold = threshold,
        captureResetBaselines = options.captureResetBaselines == true,
        resetOnly = options.resetOnly == true,
        onCommit = options.onCommit,
        rosterChanged = rosterChanged,
        rowCount = rosterChanged and 0 or infoCount,
        hasAddonFamilies = rosterChanged and false or hasAddonFamilies,
        diagnosticsDue = modern and (
            rosterChanged
            or not usageTooltipDiagnosticLastUpdate
            or usageTooltipDiagnosticThreshold ~= threshold
            or usageTooltipDiagnosticRosterGeneration ~= addonRosterGeneration
            or now - usageTooltipDiagnosticLastUpdate >= CPU_DIAGNOSTIC_REFRESH_INTERVAL
        ),
    }
    if rosterChanged then
        BeginAddonFamilyResolution()
        job.rosterIndex = 1
        job.rosterTotal = math.max(0, tonumber(SystemAPI.GetNumAddOns()) or 0)
        job.stage = "roster"
    else
        job.stage = job.captureResetBaselines and "reset-prepare" or "metric-prepare"
    end

    usageRefreshJob = job
    ScheduleUsageRefresh(job)
    return job
end

local function RefreshUsageTooltipData(useMemory, forceData, now)
    local mode = useMemory and "memory" or "cpu"
    local ready = usageTooltipDataMode == mode and usageTooltipDataLastUpdate ~= nil
    local refreshData = forceData
        or addonRosterDirty
        or not ready
        or now - usageTooltipDataLastUpdate >= TOOLTIP_REFRESH_INTERVAL
    if refreshData then StartUsageRefresh(mode, now) end

    local total = useMemory and (usageTooltipTotalMemory or 0)
        or (usageTooltipTotalCPU or 0)
    return total, ready
end

local function StartCPUUsageReset(now, callback)
    return StartUsageRefresh("cpu", now, {
        captureResetBaselines = true,
        resetOnly = true,
        onCommit = function(job)
            local reset = SystemAPI.ResetCPUUsage
                and SystemAPI.ResetCPUUsage() == true
            if reset then Module.loginTime = CombatAPI.GetTime() end
            ClearUsageTooltipCache()
            if callback then callback(reset, job.resetCaptured == true) end
            if IsUsageTooltipVisible() then RefreshVisibleUsageTooltip() end
        end,
    })
end

local cpuWatchdog = YUI.CPUWatchdog
if cpuWatchdog and cpuWatchdog.RegisterProbe then
    cpuWatchdog:RegisterProbe(cpuProbeID, {
        localeKey = context.cpuProbeLocaleKey or "cpu_watch.probe.ybar_cpu_panel",
        kind = "function",
        target = RunUsageRefreshSlice,
        snapshot = GetSystemCPUProbeState,
    })
    cpuWatchdog:RegisterProbe(systemProbeID, {
        localeKey = context.systemProbeLocaleKey or "cpu_watch.probe.ybar_system",
        kind = "function",
        target = SystemRuntimeTickerCallback,
        snapshot = GetSystemCPUProbeState,
    })
    cpuWatchdog:RegisterProbe(pinnedProbeID, {
        localeKey = context.pinnedProbeLocaleKey or "cpu_watch.probe.ybar_pinned",
        kind = "function",
        target = PinnedTooltipTickerCallback,
        includeSubroutines = false,
        snapshot = GetSystemCPUProbeState,
    })
end

local function SetPinnedTextColor(text, r, g, b, a)
    if not text then return end
    text:SetTextColor(r or 1, g or 1, b or 1, a or 1)
end

local function ApplyPinnedTooltipBackdrop(frame)
    if not frame then return end

    local r, g, b = 0.02, 0.02, 0.025
    if GUI2 and GUI2.GetColor then
        r, g, b = GUI2:GetColor("color.surface.popup", { 0.02, 0.02, 0.025, 1 })
    end

    if frame.SetBackdropColor then
        frame:SetBackdropColor(r, g, b, PINNED_TOOLTIP_BACKGROUND_ALPHA)
    end

    local border = frame.gui2NativeBorder
    if border and border.Center and border.Center.Hide then
        border.Center:Hide()
    end
end

local function HidePinnedMetricTexts(row)
    if row.current then row.current:Hide() end
    if row.peak then row.peak:Hide() end
    if row.count then row.count:Hide() end
end

local function AcquirePinnedTooltipRow(frame)
    frame.usedRows = (frame.usedRows or 0) + 1
    local index = frame.usedRows
    local rows = frame.rows
    local row = rows[index]
    if not row then
        row = {}
        row.left = GUI2:CreateText(frame, "", PINNED_TOOLTIP_FONT_SIZE, "color.text.primary", "LEFT")
        row.left:SetWordWrap(false)
        row.right = GUI2:CreateText(frame, "", PINNED_TOOLTIP_FONT_SIZE, "color.text.primary", "RIGHT")
        row.right:SetWordWrap(false)
        rows[index] = row
    end

    local y = -PINNED_TOOLTIP_PADDING - ((index - 1) * PINNED_TOOLTIP_ROW_HEIGHT)
    row.left:ClearAllPoints()
    row.right:ClearAllPoints()
    row.left:SetPoint("TOPLEFT", frame, "TOPLEFT", PINNED_TOOLTIP_PADDING, y)
    row.left:SetHeight(PINNED_TOOLTIP_ROW_HEIGHT)
    row.right:SetHeight(PINNED_TOOLTIP_ROW_HEIGHT)
    row.left:Show()
    return row
end

local function AddPinnedTooltipLine(frame, text, r, g, b)
    local row = AcquirePinnedTooltipRow(frame)
    row.right:Hide()
    HidePinnedMetricTexts(row)
    row.left:SetPoint("RIGHT", frame, "RIGHT", -PINNED_TOOLTIP_PADDING, 0)
    row.left:SetWidth(PINNED_TOOLTIP_WIDTH - (PINNED_TOOLTIP_PADDING * 2))
    row.left:SetJustifyH("LEFT")
    row.left:SetText(text == " " and "" or (text or ""))
    SetPinnedTextColor(row.left, r, g, b)
end

local function AddPinnedTooltipDoubleLine(frame, left, right, lr, lg, lb, rr, rg, rb)
    local row = AcquirePinnedTooltipRow(frame)
    HidePinnedMetricTexts(row)
    row.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PINNED_TOOLTIP_PADDING,
        -PINNED_TOOLTIP_PADDING - ((frame.usedRows - 1) * PINNED_TOOLTIP_ROW_HEIGHT))
    row.right:SetWidth(PINNED_TOOLTIP_VALUE_WIDTH)
    row.left:SetPoint("RIGHT", row.right, "LEFT", -PINNED_TOOLTIP_TEXT_GAP, 0)
    row.left:SetWidth(PINNED_TOOLTIP_WIDTH - (PINNED_TOOLTIP_PADDING * 2) -
        PINNED_TOOLTIP_VALUE_WIDTH - PINNED_TOOLTIP_TEXT_GAP)
    row.left:SetJustifyH("LEFT")
    row.right:SetJustifyH("RIGHT")
    row.left:SetText(left or "")
    row.right:SetText(right or "")
    SetPinnedTextColor(row.left, lr, lg, lb)
    SetPinnedTextColor(row.right, rr, rg, rb)
    row.right:Show()
end

local function EnsurePinnedMetricTexts(frame, row)
    if row.current then return end
    row.current = GUI2:CreateText(frame, "", PINNED_TOOLTIP_FONT_SIZE, "color.text.primary", "RIGHT")
    row.peak = GUI2:CreateText(frame, "", PINNED_TOOLTIP_FONT_SIZE, "color.text.primary", "RIGHT")
    row.count = GUI2:CreateText(frame, "", PINNED_TOOLTIP_FONT_SIZE, "color.text.primary", "RIGHT")
    row.current:SetWordWrap(false)
    row.peak:SetWordWrap(false)
    row.count:SetWordWrap(false)
end

local function AddPinnedTooltipMetricRow(frame, left, current, peak, count,
    lr, lg, lb, vr, vg, vb)
    local row = AcquirePinnedTooltipRow(frame)
    EnsurePinnedMetricTexts(frame, row)
    row.right:Hide()

    local y = -PINNED_TOOLTIP_PADDING - ((frame.usedRows - 1) * PINNED_TOOLTIP_ROW_HEIGHT)
    local peakRight = PINNED_TOOLTIP_PADDING + PINNED_TOOLTIP_COUNT_WIDTH
        + PINNED_TOOLTIP_COLUMN_GAP
    local currentRight = peakRight + PINNED_TOOLTIP_PEAK_WIDTH
        + PINNED_TOOLTIP_COLUMN_GAP
    local leftRight = currentRight + PINNED_TOOLTIP_CURRENT_WIDTH
        + PINNED_TOOLTIP_TEXT_GAP
    row.count:ClearAllPoints()
    row.peak:ClearAllPoints()
    row.current:ClearAllPoints()
    row.count:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PINNED_TOOLTIP_PADDING, y)
    row.peak:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -peakRight, y)
    row.current:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -currentRight, y)
    row.left:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -leftRight, y)
    row.count:SetWidth(PINNED_TOOLTIP_COUNT_WIDTH)
    row.peak:SetWidth(PINNED_TOOLTIP_PEAK_WIDTH)
    row.current:SetWidth(PINNED_TOOLTIP_CURRENT_WIDTH)
    row.left:SetWidth(PINNED_TOOLTIP_WIDTH - (PINNED_TOOLTIP_PADDING * 2)
        - PINNED_TOOLTIP_CURRENT_WIDTH - PINNED_TOOLTIP_PEAK_WIDTH
        - PINNED_TOOLTIP_COUNT_WIDTH - (PINNED_TOOLTIP_COLUMN_GAP * 2)
        - PINNED_TOOLTIP_TEXT_GAP)
    row.current:SetHeight(PINNED_TOOLTIP_ROW_HEIGHT)
    row.peak:SetHeight(PINNED_TOOLTIP_ROW_HEIGHT)
    row.count:SetHeight(PINNED_TOOLTIP_ROW_HEIGHT)
    row.left:SetJustifyH("LEFT")
    row.current:SetJustifyH("RIGHT")
    row.peak:SetJustifyH("RIGHT")
    row.count:SetJustifyH("RIGHT")
    row.left:SetText(left or "")
    row.current:SetText(current or "")
    row.peak:SetText(peak or "")
    row.count:SetText(count or "")
    SetPinnedTextColor(row.left, lr, lg, lb)
    SetPinnedTextColor(row.current, vr, vg, vb)
    SetPinnedTextColor(row.peak, vr, vg, vb)
    SetPinnedTextColor(row.count, vr, vg, vb)
    row.current:Show()
    row.peak:Show()
    row.count:Show()
end

local function BeginPinnedTooltipRender(frame)
    frame.usedRows = 0
end

local function FinishPinnedTooltipRender(frame)
    for i = (frame.usedRows or 0) + 1, #(frame.rows or {}) do
        local row = frame.rows[i]
        if row then
            row.left:Hide()
            row.right:Hide()
            HidePinnedMetricTexts(row)
        end
    end
    frame:SetHeight(math.max(PINNED_TOOLTIP_MIN_HEIGHT,
        (PINNED_TOOLTIP_PADDING * 2) + ((frame.usedRows or 0) * PINNED_TOOLTIP_ROW_HEIGHT)))
end

local GameTooltipUsageWriter = {
    metricLineCount = 0,
    metricLeftLines = {},
    metricRightLines = {},
    metricRows = {},
}

local function GetGameTooltipMetricLine(lineIndex, right)
    local getter = right and GameTooltip.GetRightLine or GameTooltip.GetLeftLine
    if type(getter) == "function" then
        return getter(GameTooltip, lineIndex)
    end
    return _G[format("GameTooltipText%s%d", right and "Right" or "Left", lineIndex)]
end

function GameTooltipUsageWriter:ResetMetricLayout()
    for index = 1, self.metricLineCount do
        local left = self.metricLeftLines[index]
        local right = self.metricRightLines[index]
        local row = self.metricRows[index]
        -- Tooltip geometry and alpha readbacks can be secret on Retail. Return
        -- the shared native lines to their unconstrained template defaults.
        if left and left.SetWidth then
            left:SetWidth(0)
        end
        if right and right.SetWidth then
            right:SetWidth(0)
        end
        if right and right.SetAlpha then
            right:SetAlpha(1)
        end
        if row then
            row.current:Hide()
            row.peak:Hide()
            row.count:Hide()
        end
        self.metricLeftLines[index] = nil
        self.metricRightLines[index] = nil
    end
    self.metricLineCount = 0
end

local function ApplyGameTooltipMetricFont(text, source)
    if not text or not source or not source.GetFont or not text.SetFont then return end
    local font, size, flags = source:GetFont()
    if font and size then
        text:SetFont(font, size, flags or "")
    end
end

local function AcquireGameTooltipMetricRow(writer, index, rightLine)
    local row = writer.metricRows[index]
    if not row then
        row = {
            current = GUI2:CreateText(GameTooltip, "", PINNED_TOOLTIP_FONT_SIZE,
                "color.text.primary", "RIGHT"),
            peak = GUI2:CreateText(GameTooltip, "", PINNED_TOOLTIP_FONT_SIZE,
                "color.text.primary", "RIGHT"),
            count = GUI2:CreateText(GameTooltip, "", PINNED_TOOLTIP_FONT_SIZE,
                "color.text.primary", "RIGHT"),
        }
        row.current:SetWordWrap(false)
        row.peak:SetWordWrap(false)
        row.count:SetWordWrap(false)
        writer.metricRows[index] = row
    end

    ApplyGameTooltipMetricFont(row.current, rightLine)
    ApplyGameTooltipMetricFont(row.peak, rightLine)
    ApplyGameTooltipMetricFont(row.count, rightLine)
    return row
end

local function ApplyGameTooltipMetricRowLayout(row, rightLine)
    if not row or not rightLine then return end

    row.count:ClearAllPoints()
    row.peak:ClearAllPoints()
    row.current:ClearAllPoints()
    row.count:SetPoint("RIGHT", rightLine, "RIGHT", 0, 0)
    row.peak:SetPoint("RIGHT", row.count, "LEFT", -PINNED_TOOLTIP_COLUMN_GAP, 0)
    row.current:SetPoint("RIGHT", row.peak, "LEFT", -PINNED_TOOLTIP_COLUMN_GAP, 0)
    row.count:SetWidth(PINNED_TOOLTIP_COUNT_WIDTH)
    row.peak:SetWidth(PINNED_TOOLTIP_PEAK_WIDTH)
    row.current:SetWidth(PINNED_TOOLTIP_CURRENT_WIDTH)
    row.count:SetJustifyH("RIGHT")
    row.peak:SetJustifyH("RIGHT")
    row.current:SetJustifyH("RIGHT")
    row.count:Show()
    row.peak:Show()
    row.current:Show()
end

function GameTooltipUsageWriter:ApplyMetricLayout()
    for index = 1, self.metricLineCount do
        local left = self.metricLeftLines[index]
        local right = self.metricRightLines[index]
        local row = self.metricRows[index]
        if left then
            left:SetWidth(GAME_TOOLTIP_NAME_WIDTH)
        end
        if right then
            right:SetWidth(GAME_TOOLTIP_METRIC_WIDTH)
            right:SetAlpha(0)
            ApplyGameTooltipMetricRowLayout(row, right)
        end
    end
end

function GameTooltipUsageWriter:AddLine(text, r, g, b)
    if r then
        GameTooltip:AddLine(text, r, g, b)
    else
        GameTooltip:AddLine(text)
    end
end

function GameTooltipUsageWriter:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
    GameTooltip:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
end

function GameTooltipUsageWriter:AddMetricRow(left, current, peak, count,
    lr, lg, lb, vr, vg, vb)
    GameTooltip:AddDoubleLine(left, format(GAME_TOOLTIP_METRIC_FORMAT, current, peak, count),
        lr, lg, lb, vr, vg, vb)
    local lineIndex = GameTooltip:NumLines()
    local leftLine = GetGameTooltipMetricLine(lineIndex, false)
    local rightLine = GetGameTooltipMetricLine(lineIndex, true)
    self.metricLineCount = self.metricLineCount + 1
    local slot = self.metricLineCount
    self.metricLeftLines[slot] = leftLine
    self.metricRightLines[slot] = rightLine
    if leftLine then
        leftLine:SetWidth(GAME_TOOLTIP_NAME_WIDTH)
    end
    if rightLine then
        local row = AcquireGameTooltipMetricRow(self, slot, rightLine)
        row.current:SetText(current or "")
        row.peak:SetText(peak or "")
        row.count:SetText(count or "")
        SetPinnedTextColor(row.current, vr, vg, vb)
        SetPinnedTextColor(row.peak, vr, vg, vb)
        SetPinnedTextColor(row.count, vr, vg, vb)
        rightLine:SetWidth(GAME_TOOLTIP_METRIC_WIDTH)
        rightLine:SetAlpha(0)
        ApplyGameTooltipMetricRowLayout(row, rightLine)
    end
end

local PinnedTooltipUsageWriter = {}

function PinnedTooltipUsageWriter:AddLine(text, r, g, b)
    AddPinnedTooltipLine(self.frame, text, r, g, b)
end

function PinnedTooltipUsageWriter:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
    AddPinnedTooltipDoubleLine(self.frame, left, right, lr, lg, lb, rr, rg, rb)
end

function PinnedTooltipUsageWriter:AddMetricRow(left, current, peak, count,
    lr, lg, lb, vr, vg, vb)
    AddPinnedTooltipMetricRow(self.frame, left, current, peak, count,
        lr, lg, lb, vr, vg, vb)
end

local function ResetUsageGameTooltipLayout()
    GameTooltipUsageWriter:ResetMetricLayout()
    if GameTooltip and GameTooltip.SetMinimumWidth then
        GameTooltip:SetMinimumWidth(0, false)
    end
end

local usageTooltipCleanupHooked = false

local function EnsureUsageGameTooltipCleanupHook()
    if usageTooltipCleanupHooked then return true end
    if not GameTooltip or type(GameTooltip.HookScript) ~= "function" then
        return false
    end
    local ok = pcall(
        GameTooltip.HookScript,
        GameTooltip,
        "OnTooltipCleared",
        ResetUsageGameTooltipLayout
    )
    if ok then usageTooltipCleanupHooked = true end
    return ok
end

local function GetUsageTooltipUIHeight()
    local height = UIParent and UIParent.GetHeight and UIParent:GetHeight()
    height = tonumber(height)
    if height and height > 0 then return height end
    height = GetScreenHeight and tonumber(GetScreenHeight()) or nil
    return height and height > 0 and height or 768
end

local function GetUsageTooltipAvailableHeight(anchor, belowAnchor, gap)
    local screenHeight = GetUsageTooltipUIHeight()
    local fallback = math.max(
        PINNED_TOOLTIP_MIN_HEIGHT,
        screenHeight - (USAGE_TOOLTIP_SCREEN_MARGIN * 2)
    )
    if not anchor then return fallback end

    gap = math.max(0, tonumber(gap) or 0)
    if belowAnchor then
        local bottom = anchor.GetBottom and anchor:GetBottom()
        if bottom then
            return math.max(
                PINNED_TOOLTIP_MIN_HEIGHT,
                bottom - gap - USAGE_TOOLTIP_SCREEN_MARGIN
            )
        end
    else
        local top = anchor.GetTop and anchor:GetTop()
        if top then
            return math.max(
                PINNED_TOOLTIP_MIN_HEIGHT,
                screenHeight - top - gap - USAGE_TOOLTIP_SCREEN_MARGIN
            )
        end
    end
    return fallback
end

local function CalculateUsageTooltipRowLimit(maxHeight, useMemory, recentCPU,
    diagnosticsAvailable, showShiftHint, showFamilyNote)
    local fixedRows = USAGE_TOOLTIP_FOOTER_ROWS
    if useMemory then
        fixedRows = fixedRows + 4 -- title, gap, total, gap
    else
        fixedRows = fixedRows + 3 -- title, first gap, addon-list gap
        if recentCPU then fixedRows = fixedRows + 1 end
        fixedRows = fixedRows + ((recentCPU and diagnosticsAvailable) and 2 or 1)
    end
    if showShiftHint then fixedRows = fixedRows + 1 end
    if showFamilyNote then fixedRows = fixedRows + 1 end

    local height = math.max(
        PINNED_TOOLTIP_MIN_HEIGHT,
        tonumber(maxHeight) or GetUsageTooltipAvailableHeight()
    )
    local totalRows = math.floor(
        math.max(0, height - (PINNED_TOOLTIP_PADDING * 2)) / PINNED_TOOLTIP_ROW_HEIGHT
    )
    return math.max(1, math.min(USAGE_TOOLTIP_MAX_ROWS, totalRows - fixedRows))
end

local function RenderUsageTooltipContent(writer, opts)
    opts = opts or {}

    local now = CombatAPI.GetTime()
    local showAll = opts.showAll == true
    local scriptProfile = GetSystemCVarBool("scriptProfile")
    local modernCPU = SystemAPI.CanReadRecentAddOnCPUUsage
        and SystemAPI.CanReadRecentAddOnCPUUsage() == true
    local useMemory = Module.showMemory or (not modernCPU and not scriptProfile)
    local db = GetSystemDB()
    local mergeFamilies = db.mergeAddonFamilies ~= false
    local threshold = tonumber(db.cpuSpikeThresholdMs)
    if not VALID_CPU_SPIKE_THRESHOLDS[threshold] then
        threshold = DEFAULT_CPU_SPIKE_THRESHOLD_MS
    end
    local mode = useMemory and "memory" or "cpu"
    local total, dataReady = RefreshUsageTooltipData(useMemory, opts.forceData == true, now)
    local rows, rowCount = infoTable, 0
    if dataReady then
        rows, rowCount = BuildDisplayRows(
            mode,
            not mergeFamilies or showAll
        )
    end
    local showFamilyNote = not useMemory
        and usageTooltipCPUIsRecent
        and usageTooltipDiagnosticsAvailable
        and mergeFamilies and hasAddonFamilies and not showAll
    local showShiftHint = opts.includeHoldShiftHint ~= false
        and not showAll
        and ((mergeFamilies and hasAddonFamilies)
            or rowCount > USAGE_TOOLTIP_DEFAULT_ROWS)
    local screenRowLimit = CalculateUsageTooltipRowLimit(
        opts.maxHeight,
        useMemory,
        usageTooltipCPUIsRecent,
        usageTooltipDiagnosticsAvailable,
        showShiftHint,
        showFamilyNote
    )
    local maxShown = min(
        USAGE_TOOLTIP_MAX_ROWS,
        screenRowLimit,
        showAll and rowCount or USAGE_TOOLTIP_DEFAULT_ROWS
    )
    if not showShiftHint
        and opts.includeHoldShiftHint ~= false
        and not showAll
        and rowCount > maxShown
    then
        showShiftHint = true
        screenRowLimit = CalculateUsageTooltipRowLimit(
            opts.maxHeight,
            useMemory,
            usageTooltipCPUIsRecent,
            usageTooltipDiagnosticsAvailable,
            true,
            showFamilyNote
        )
        maxShown = min(maxShown, screenRowLimit)
    end

    if useMemory then
        writer:AddLine(L["system.tooltip.memory_title"], 1, 0.82, 0)
        writer:AddLine(" ")
        writer:AddDoubleLine(L["system.tooltip.total_system"], FormatMemory(total),
            0.6, 0.8, 1, 1, 1, 1)
        writer:AddLine(" ")

        local numShown = 0
        for _, data in ipairs(rows) do
            if numShown >= maxShown then break end
            if data.memory > 0 then
                writer:AddDoubleLine(data.title, FormatMemory(data.memory),
                    1, 1, 1, 1, 0.82, 0)
                numShown = numShown + 1
            end
        end

        if showShiftHint then
            writer:AddLine(
                mergeFamilies and hasAddonFamilies
                    and L["system.tooltip.hold_shift_show_all"]
                    or L["system.tooltip.hold_shift_expand"],
                0, 1, 0
            )
        end
    else
        local divisor = usageTooltipCPUIsRecent
            and 1
            or math.max(1, now - Module.loginTime)

        writer:AddLine(L["system.tooltip.cpu_title"], 1, 0.82, 0)
        if usageTooltipCPUIsRecent then
            writer:AddLine(L["system.tooltip.cpu_recent_hint"], 0.5, 0.5, 0.5)
        end
        writer:AddLine(" ")
        local applicationCPU = usageTooltipApplicationCPU
        local totalPercent = applicationCPU and applicationCPU > 0
            and (total / applicationCPU) * 100
            or 0
        local totalText = usageTooltipCPUIsRecent
            and FormatCPUPercent(totalPercent)
            or FormatCPU(total / divisor)
        if usageTooltipCPUIsRecent and usageTooltipDiagnosticsAvailable then
            writer:AddMetricRow(
                L["system.tooltip.column_addon"],
                L["system.tooltip.column_current"],
                L["system.tooltip.column_peak"],
                format(L["system.tooltip.column_over_threshold"], threshold),
                0.5, 0.5, 0.5, 0.5, 0.5, 0.5
            )
            writer:AddMetricRow(
                L["system.tooltip.total_system"],
                totalText,
                usageTooltipOverallPeak ~= nil
                    and FormatCPUPeak(usageTooltipOverallPeak)
                    or "-",
                usageTooltipOverallSpikeCount ~= nil
                    and FormatCPUCount(usageTooltipOverallSpikeCount)
                    or "-",
                0.6, 0.8, 1, 1, 1, 1
            )
        else
            writer:AddDoubleLine(L["system.tooltip.total_system"], totalText,
                0.6, 0.8, 1, 1, 1, 1)
        end
        writer:AddLine(" ")

        local numShown = 0
        for _, data in ipairs(rows) do
            if numShown >= maxShown then break end
            if data.cpu > 0 or (usageTooltipDiagnosticsAvailable
                and ((data.peak or 0) > 0 or (data.spikeCount or 0) > 0))
            then
                local denominator = applicationCPU
                    and (applicationCPU - total + data.cpu)
                    or nil
                local valueText = usageTooltipCPUIsRecent
                    and FormatCPUPercent(
                        denominator and denominator > 0
                            and (data.cpu / denominator) * 100
                            or 0
                    )
                    or FormatCPU(data.cpu / divisor)
                if usageTooltipCPUIsRecent and usageTooltipDiagnosticsAvailable then
                    writer:AddMetricRow(
                        data.title,
                        valueText,
                        FormatCPUPeak(data.peak or 0),
                        FormatCPUCount(data.spikeCount or 0),
                        1, 1, 1, 1, 0.82, 0
                    )
                else
                    writer:AddDoubleLine(data.title, valueText,
                        1, 1, 1, 1, 0.82, 0)
                end
                numShown = numShown + 1
            end
        end

        if showFamilyNote then
            writer:AddLine(L["system.tooltip.family_diagnostic_note"], 0.5, 0.5, 0.5)
        end

        if showShiftHint then
            writer:AddLine(
                mergeFamilies and hasAddonFamilies
                    and L["system.tooltip.hold_shift_show_all"]
                    or L["system.tooltip.hold_shift_expand"],
                0, 1, 0
            )
        end
    end

    local headerColor = CreateColor(1, 0.82, 0)
    local headerHex = headerColor:GenerateHexColor()
    local white = "|cffffffff"
    local gold = "|c" .. headerHex
    local pinAction = opts.pinned and L["system.action.unpin_tooltip"] or L["system.action.pin_tooltip"]

    writer:AddLine(" ")
    writer:AddLine(format("%s%s: |r%s%s|r", white, LC["common.left_click"], gold, L["system.action.collect_memory"]))
    local cpuAction = L["system.action.reset_cpu_stats"]
    writer:AddLine(format("%s%s: |r%s%s|r", white, LC["common.right_click"], gold, cpuAction))
    writer:AddLine(format("%sShift + %s: |r%s%s|r", white, LC["common.left_click"], gold, pinAction))
    writer:AddLine(format("%sShift + %s: |r%s%s|r", white, LC["common.right_click"], gold, L["system.action.toggle_memory_cpu"]))
    writer:AddLine(" ")
    writer:AddLine(format("|cff808080%s: %s|r", LC["common.alt_left_click"], LC["common.open_settings"]))
end

function Module:OnAddonLoaded()
    addonRosterDirty = true
    addonRosterChangeGeneration = addonRosterChangeGeneration + 1
    if usageRefreshJob then CancelUsageRefresh() end
    if IsUsageTooltipVisible() then RefreshVisibleUsageTooltip() end
end

function Module:IsPinnedTooltipShown()
    return self.pinnedTooltipFrame and self.pinnedTooltipFrame.IsShown and self.pinnedTooltipFrame:IsShown()
end

function Module:EnsurePinnedTooltipFrame()
    if self.pinnedTooltipFrame then
        return self.pinnedTooltipFrame
    end

    local frame = GUI2:CreatePanel(UIParent, {
        name = context.pinnedName,
        width = PINNED_TOOLTIP_WIDTH,
        height = PINNED_TOOLTIP_MIN_HEIGHT,
        surface = "color.surface.popup",
        border = "color.popup.border",
        nativeFrameBorder = true,
        nativeFrameBorderStyle = "tooltip",
        shadow = true,
        shadowKey = "shadow.popup.size",
    })
    local refreshTheme = frame.RefreshTheme
    frame.RefreshTheme = function(object)
        if refreshTheme then
            refreshTheme(object)
        end
        ApplyPinnedTooltipBackdrop(object)
    end
    ApplyPinnedTooltipBackdrop(frame)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.pinnedUserMoved = true
        self.usageMaxHeight = GetUsageTooltipAvailableHeight()
    end)
    frame:SetScript("OnHide", function()
        Module:StopPinnedTooltipTicker()
    end)
    frame.rows = {}
    frame:Hide()

    self.pinnedTooltipFrame = frame
    return frame
end

function Module:PositionPinnedTooltip(anchor)
    local frame = self:EnsurePinnedTooltipFrame()
    if frame.pinnedUserMoved then return frame end

    frame:ClearAllPoints()
    if anchor and anchor.GetBottom and anchor:GetBottom()
        and anchor:GetBottom() > GetUsageTooltipUIHeight() / 2
    then
        frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
        frame.usageMaxHeight = GetUsageTooltipAvailableHeight(anchor, true, 10)
    elseif anchor then
        frame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 10)
        frame.usageMaxHeight = GetUsageTooltipAvailableHeight(anchor, false, 10)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        frame.usageMaxHeight = GetUsageTooltipAvailableHeight()
    end

    return frame
end

function Module:StopPinnedTooltipTicker()
    if self.pinnedTooltipTicker and self.pinnedTooltipTicker.Cancel then
        self.pinnedTooltipTicker:Cancel()
    end
    self.pinnedTooltipTicker = nil

    if self.pinnedTooltipFrame then
        self.pinnedTooltipFrame:SetScript("OnUpdate", nil)
        self.pinnedTooltipFrame.pinnedTooltipElapsed = nil
    end
end

function Module:StartPinnedTooltipTicker()
    self:StopPinnedTooltipTicker()

    if C_Timer and C_Timer.NewTicker then
        self.pinnedTooltipTicker = C_Timer.NewTicker(TOOLTIP_REFRESH_INTERVAL, PinnedTooltipTickerCallback)
        return
    end

    local frame = self.pinnedTooltipFrame
    if not frame then return end
    frame.pinnedTooltipElapsed = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        if not Module:IsPinnedTooltipShown() then
            Module:StopPinnedTooltipTicker()
            return
        end

        self.pinnedTooltipElapsed = (self.pinnedTooltipElapsed or 0) + elapsed
        if self.pinnedTooltipElapsed < TOOLTIP_REFRESH_INTERVAL then return end
        self.pinnedTooltipElapsed = 0
        Module:RefreshPinnedTooltip(true)
    end)
end

function Module:RefreshPinnedTooltip(forceData)
    local frame = self.pinnedTooltipFrame
    if not frame or not frame:IsShown() then return end
    if not IsSystemReady(self.frame) then
        self:HidePinnedTooltip(true)
        return
    end

    BeginPinnedTooltipRender(frame)
    PinnedTooltipUsageWriter.frame = frame
    RenderUsageTooltipContent(PinnedTooltipUsageWriter, {
        forceData = forceData == true,
        showAll = FrameAPI.IsShiftKeyDown() == true,
        includeHoldShiftHint = true,
        pinned = true,
        maxHeight = frame.usageMaxHeight,
    })
    PinnedTooltipUsageWriter.frame = nil
    FinishPinnedTooltipRender(frame)
end

function Module:ShowPinnedTooltip(anchor)
    if not IsSystemReady(self.frame) then return end

    local frame = self:PositionPinnedTooltip(anchor)
    frame:Show()
    self:RefreshPinnedTooltip(true)
    self:StartPinnedTooltipTicker()
    YUI:Print("|cff66C6FF" .. L["system.message.tooltip_pinned"] .. "|r")
end

function Module:HidePinnedTooltip(silent)
    self:StopPinnedTooltipTicker()
    CancelUsageRefresh()

    if self.pinnedTooltipFrame then
        self.pinnedTooltipFrame:Hide()
    end

    if not silent then
        YUI:Print("|cff66C6FF" .. L["system.message.tooltip_unpinned"] .. "|r")
    end
end

function Module:TogglePinnedTooltip(anchor)
    if self:IsPinnedTooltipShown() then
        self:HidePinnedTooltip(false)
    else
        self:ShowPinnedTooltip(anchor)
    end
end

function Module:CreateFPSButton(parent)
    local btn = context.createMetricButton(parent, "FPS")
    btn.Update = function(self, force)
        if not IsSystemReady(Module.frame) then return end
        local now = CombatAPI.GetTime()
        local interval = UPDATE_INTERVAL
        if force or self.lastValue == nil or not self.lastUpdate or now - self.lastUpdate >= interval then
            self.lastValue = GetCurrentFramerate()
            self.lastUpdate = now
        end
        context.renderMetric(self, "FPS", self.lastValue, force == true)
    end

    -- 捕获模块实例以供闭包使用
    local module = Module
    local RefreshTooltip

    local function IsTooltipOwner(self)
        if not GameTooltip or not GameTooltip.GetOwner then return false end
        local owner = GameTooltip:GetOwner()
        return owner == self or owner == self.actionHost
    end

    local function HideUsageGameTooltip(self)
        if IsTooltipOwner(self) then
            ResetUsageGameTooltipLayout()
            YUI.HideGameTooltip()
        end
    end

    local function IsButtonHovered(self)
        return (self.IsMouseOver and self:IsMouseOver()) or
            (self.actionHost and self.actionHost.IsMouseOver and self.actionHost:IsMouseOver())
    end

    local function StopTooltipWatcher(self)
        self:SetScript("OnUpdate", nil)
        self.tooltipUpdateTimer = nil
        self.lastShiftState = nil
    end

    local function StartTooltipWatcher(self)
        if not IsSystemReady(Module.frame) then return end
        if module:IsPinnedTooltipShown() then
            HideUsageGameTooltip(self)
            StopTooltipWatcher(self)
            return
        end

        self.tooltipUpdateTimer = 0
        self.lastShiftState = FrameAPI.IsShiftKeyDown()
        self:SetScript("OnUpdate", function(frame, elapsed)
            if not IsSystemReady(Module.frame) then
                StopTooltipWatcher(frame)
                return
            end

            if module:IsPinnedTooltipShown() then
                HideUsageGameTooltip(frame)
                StopTooltipWatcher(frame)
                return
            end

            frame.tooltipUpdateTimer = (frame.tooltipUpdateTimer or 0) + elapsed
            if frame.tooltipUpdateTimer < TOOLTIP_SHIFT_CHECK_INTERVAL then return end
            frame.tooltipUpdateTimer = 0

            if not IsTooltipOwner(frame) then return end

            local isShift = FrameAPI.IsShiftKeyDown()
            local shiftChanged = frame.lastShiftState ~= isShift
            frame.lastShiftState = isShift

            local now = CombatAPI.GetTime()
            local dataDue = not usageTooltipDataLastUpdate or
                (now - usageTooltipDataLastUpdate >= TOOLTIP_REFRESH_INTERVAL)

            if shiftChanged or dataDue then
                RefreshTooltip(frame, dataDue)
            end
        end)
    end

    local function FinishHover(self)
        if not IsSystemReady(Module.frame) then return end

        if not self.isHovered and not IsTooltipOwner(self) then return end

        StopTooltipWatcher(self)
        self.isHovered = false
        if module.usageTooltipOwner == self then
            module.usageTooltipOwner = nil
        end
        if not module:IsPinnedTooltipShown() then
            CancelUsageRefresh()
        end
        if self.Update then self:Update(false) end

        if context.onLeave then context.onLeave(Module.frame) end

        if IsTooltipOwner(self) then
            HideUsageGameTooltip(self)
        end
    end

    btn.metricOnClick = function(self, button)
        if not IsSystemReady(Module.frame) then return end

        if button == "LeftButton" then
            if FrameAPI.IsAltKeyDown() then
                context.openSettings()
                return
            end
            if FrameAPI.IsShiftKeyDown() then
                module:TogglePinnedTooltip(self)
                if module:IsPinnedTooltipShown() then
                    HideUsageGameTooltip(self)
                    StopTooltipWatcher(self)
                elseif IsButtonHovered(self) and RefreshTooltip then
                    RefreshTooltip(self, true)
                    StartTooltipWatcher(self)
                end
                return
            end

            local before = gcinfo()
            collectgarbage("collect")
            local after = gcinfo()
            ClearUsageTooltipCache()
            YUI:Print(format("|cff66C6FF%s|r", format(L["system.message.memory_reclaimed"], FormatMemory(before - after))))
            module:UpdateButtons(true)
            module:RefreshPinnedTooltip(true)
            if IsTooltipOwner(self) and RefreshTooltip then
                RefreshTooltip(self, true)
            end
        elseif button == "RightButton" then
            if FrameAPI.IsShiftKeyDown() then
                -- 切换内存/CPU 视图状态
                local scriptProfile = GetSystemCVarBool("scriptProfile")
                local modernCPU = SystemAPI.CanReadRecentAddOnCPUUsage
                    and SystemAPI.CanReadRecentAddOnCPUUsage() == true
                if modernCPU then
                    module.showMemory = not module.showMemory
                    if module.showMemory then
                        YUI:Print("|cff66C6FF" .. L["system.message.switched_memory"] .. "|r")
                    end
                    ClearUsageTooltipCache()
                    module:RefreshPinnedTooltip(true)
                    if IsTooltipOwner(self) and RefreshTooltip then
                        RefreshTooltip(self, true)
                    end
                    return
                end
                -- 仅当 profiling 开启且未强制显示内存时处于 CPU 模式
                local isCpuMode = scriptProfile and not module.showMemory

                if isCpuMode then
                    -- 当前为 CPU -> 切换至内存
                    module.showMemory = true
                    SetSystemCVar("scriptProfile", 0)
                    YUI:Print("|cff66C6FF" .. L["system.message.switched_memory"] .. "|r")
                else
                    -- 当前为内存 -> 切换至 CPU
                    if not scriptProfile then
                        local Settings = YUI.Settings
                        if Settings and Settings.ShowConfirmPopup then
                            Settings:ShowConfirmPopup(L["system.popup.cpu_usage"], function()
                                SetSystemCVar("scriptProfile", 1)
                                FrameAPI.ReloadUI()
                            end, {
                                titleText = L["system.popup.enable_reload"],
                                acceptText = L["system.popup.enable_reload"],
                                acceptTone = "warning",
                            })
                        end
                    else
                        -- Profiling 已开启，仅切换视图标志
                        module.showMemory = false
                    end
                end

                ClearUsageTooltipCache()
                module:RefreshPinnedTooltip(true)
                if IsTooltipOwner(self) and RefreshTooltip then
                    RefreshTooltip(self, true)
                end
            elseif SystemAPI.CanReadRecentAddOnCPUUsage
                and SystemAPI.CanReadRecentAddOnCPUUsage() == true
            then
                StartCPUUsageReset(CombatAPI.GetTime(), function(reset, diagnosticsReset)
                    YUI:Print("|cff66C6FF" .. L[
                        (reset or diagnosticsReset) and "system.message.cpu_stats_reset"
                            or "system.message.cpu_stats_refreshed"
                    ] .. "|r")
                end)
            elseif SystemAPI.ResetCPUUsage and SystemAPI.ResetCPUUsage() then
                module.loginTime = CombatAPI.GetTime()
                ClearUsageTooltipCache()
                YUI:Print("|cff66C6FF" .. L["system.message.cpu_stats_reset"] .. "|r")
                module:RefreshPinnedTooltip(true)
                if IsTooltipOwner(self) and RefreshTooltip then
                    RefreshTooltip(self, true)
                end
            end
        end
    end

    RefreshTooltip = function(self, forceData)
        if not IsSystemReady(Module.frame) then return end
        if module:IsPinnedTooltipShown() then
            HideUsageGameTooltip(self)
            StopTooltipWatcher(self)
            return
        end

        module.usageTooltipOwner = self

        local tooltipAnchor = "ANCHOR_TOP"
        local yOffset = 20
        local belowAnchor = self:GetBottom() > GetUsageTooltipUIHeight() / 2
        if belowAnchor then
            tooltipAnchor = "ANCHOR_BOTTOM"
            yOffset = -20
        end
        GameTooltipUsageWriter:ResetMetricLayout()
        EnsureUsageGameTooltipCleanupHook()
        GameTooltip:SetOwner(self, tooltipAnchor, 0, yOffset)
        GameTooltip:ClearLines()
        if GameTooltip.SetMinimumWidth then
            GameTooltip:SetMinimumWidth(PINNED_TOOLTIP_WIDTH, true)
        end
        RenderUsageTooltipContent(GameTooltipUsageWriter, {
            forceData = forceData == true,
            showAll = FrameAPI.IsShiftKeyDown(),
            includeHoldShiftHint = true,
            pinned = module:IsPinnedTooltipShown(),
            maxHeight = GetUsageTooltipAvailableHeight(self, belowAnchor, 20),
        })
        GameTooltip:Show()
        GameTooltipUsageWriter:ApplyMetricLayout()
    end
    btn.RefreshUsageTooltip = RefreshTooltip

    btn:SetScript("OnEnter", function(self)
        if not IsSystemReady(Module.frame) then return end

        local wasHovered = self.isHovered
        self.isHovered = true
        module.usageTooltipOwner = self
        if self.Update then self:Update() end
        if module:IsPinnedTooltipShown() then
            HideUsageGameTooltip(self)
            StopTooltipWatcher(self)
        else
            RefreshTooltip(self, true)
            StartTooltipWatcher(self)
        end

        if not wasHovered and context.onEnter then context.onEnter(Module.frame) end
    end)

    btn:SetScript("OnLeave", function(self)
        C_Timer.After(0, function()
            if not IsSystemReady(Module.frame) then return end
            if IsButtonHovered(self) then return end
            FinishHover(self)
        end)
    end)

    context.installActions(btn)
    return btn
end

function Module:CreateLatencyButton(parent)
    local btn = context.createMetricButton(parent, "LATENCY")
    btn.Update = function(self, force)
        if not IsSystemReady(Module.frame) then return end
        local now = CombatAPI.GetTime()
        local interval = NETWORK_UPDATE_INTERVAL
        if force or self.lastValue == nil or not self.lastUpdate or now - self.lastUpdate >= interval then
            self.lastValue = Metrics:ReadLatency()
            self.lastUpdate = now
        end
        context.renderMetric(self, "LATENCY", self.lastValue, force == true)
    end

    btn:SetScript("OnEnter", function(self)
        if not IsSystemReady(Module.frame) then return end

        if context.onEnter then context.onEnter(Module.frame) end
        self.isHovered = true
        if self.Update then self:Update(false) end

        local tooltipAnchor = "ANCHOR_TOP"
        local yOffset = 20
        if self:GetBottom() > GetScreenHeight() / 2 then
            tooltipAnchor = "ANCHOR_BOTTOM"
            yOffset = -20
        end
        ResetUsageGameTooltipLayout()
        GameTooltip:SetOwner(self, tooltipAnchor, 0, yOffset)
        GameTooltip:ClearLines()

        local _, latencyHome, latencyWorld = Metrics:ReadLatency()
        GameTooltip:AddLine(L["system.tooltip.network_latency"])
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L["system.tooltip.home_latency"], latencyHome .. " ms", 1, 1, 1, 1, 0.82, 0)
        GameTooltip:AddDoubleLine(L["system.tooltip.world_latency"], latencyWorld .. " ms", 1, 1, 1, 1, 0.82, 0)

        local headerColor = CreateColor(1, 0.82, 0)
        local headerHex = headerColor:GenerateHexColor()
        local white = "|cffffffff"
        local gold = "|c" .. headerHex

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(format("|cff808080%s: %s|r", LC["common.alt_left_click"], LC["common.open_settings"]))

        GameTooltip:Show()
    end)

    btn.metricOnClick = function(self, button)
        if not IsSystemReady(Module.frame) then return end

        if button == "LeftButton" and FrameAPI.IsAltKeyDown() then
            context.openSettings()
        end
    end

    btn:SetScript("OnLeave", function(self)
        if not IsSystemReady(Module.frame) then return end

        if context.onLeave then context.onLeave(Module.frame) end
        self.isHovered = false
        if self.Update then self:Update(false) end
        YUI.HideGameTooltip()
    end)

    context.installActions(btn)
    return btn
end


local service = {
    RestoreCPUCountResetState = RestoreCPUCountResetState,
    CancelUsageRefresh = CancelUsageRefresh,
    ClearUsageTooltipCache = ClearUsageTooltipCache,
    ResetUsageGameTooltipLayout = ResetUsageGameTooltipLayout,
    SystemRuntimeTickerCallback = SystemRuntimeTickerCallback,
    GetStats = GetSystemCPUProbeState,
}
function service:Stop()
    Module:HidePinnedTooltip(true)
    Module.usageTooltipOwner = nil
    for _, btn in ipairs(Module.buttons or {}) do
        btn:SetScript("OnUpdate", nil)
        btn.isHovered = false
        btn.tooltipUpdateTimer, btn.lastShiftState = nil, nil
        if GameTooltip and GameTooltip.GetOwner then
            local owner = GameTooltip:GetOwner()
            if owner == btn or owner == btn.actionHost then
                ResetUsageGameTooltipLayout()
                YUI.HideGameTooltip()
            end
        end
    end
    ClearUsageTooltipCache()
end
return service
end

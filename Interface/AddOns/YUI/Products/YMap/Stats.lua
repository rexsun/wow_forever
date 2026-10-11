local YUI = _G.YUI
if not YUI or not YUI.YMap then return end

local YMap = YUI.YMap
local Stats = {
    enabled = false,
    coordinateDriverActive = false,
    directionLineActive = false,
    directionLineVisible = false,
    directionLineReads = 0,
    directionLineWrites = 0,
    directionLineDotPool = 0,
    minimapMetricsActive = false,
    minimapMetricsWrites = 0,
    minimapMetricsLayouts = 0,
    minimapMetricsTooltipRefreshPending = false,
    minimapMetricsPinnedShown = false,
    worldMapDriverActive = false,
    worldMapCursorReads = 0,
    worldMapPlayerReads = 0,
    worldMapTextWrites = 0,
    minimapActive = false,
    minimapReconciles = 0,
    minimapCoordinateConsumerActive = false,
    minimapCoordinateReads = 0,
    minimapCoordinateTextWrites = 0,
    progressBarsVisible = 0,
    progressBarValueUpdates = 0,
    progressBarGeometryChanges = 0,
    progressBarEventsActive = false,
    buttonDiscoveryScans = 0,
    capturedButtons = 0,
    drawerHoverCloseTimerActive = false,
    drawerCloseTimerActive = false,
    drawerTransitionState = "parked",
    drawerAnimationActive = false,
    drawerStyledLibDBIcons = 0,
    drawerStyledLandingButtons = 0,
    drawerVisualRestoreFailures = 0,
    drawerInteractiveButtons = 0,
    drawerMouseStateRepairs = 0,
    drawerInputRestoreFailures = 0,
    restoreFailures = 0,
    pendingRefresh = false,
    conflictBlocked = false,
    shadowComparisons = 0,
    shadowMismatches = 0,
}
YMap.Stats = Stats

local REQUIRED_FIELDS = {
    "enabled",
    "coordinateDriverActive",
    "directionLineActive",
    "directionLineVisible",
    "directionLineReads",
    "directionLineWrites",
    "directionLineDotPool",
    "minimapMetricsActive",
    "minimapMetricsWrites",
    "minimapMetricsLayouts",
    "minimapMetricsTooltipRefreshPending",
    "minimapMetricsPinnedShown",
    "worldMapDriverActive",
    "worldMapCursorReads",
    "worldMapPlayerReads",
    "worldMapTextWrites",
    "minimapActive",
    "minimapReconciles",
    "minimapCoordinateConsumerActive",
    "minimapCoordinateReads",
    "minimapCoordinateTextWrites",
    "progressBarsVisible",
    "progressBarValueUpdates",
    "progressBarGeometryChanges",
    "progressBarEventsActive",
    "buttonDiscoveryScans",
    "capturedButtons",
    "drawerHoverCloseTimerActive",
    "drawerCloseTimerActive",
    "drawerTransitionState",
    "drawerAnimationActive",
    "drawerStyledLibDBIcons",
    "drawerStyledLandingButtons",
    "drawerVisualRestoreFailures",
    "drawerInteractiveButtons",
    "drawerMouseStateRepairs",
    "drawerInputRestoreFailures",
    "restoreFailures",
    "pendingRefresh",
    "conflictBlocked",
    "shadowComparisons",
    "shadowMismatches",
}

function Stats:Increment(field, amount)
    if type(self[field]) ~= "number" then return false end
    self[field] = self[field] + (tonumber(amount) or 1)
    return true
end

function Stats:Set(field, value)
    if self[field] == nil then return false end
    self[field] = value
    return true
end

function Stats:RecordShadowComparison(expected, actual)
    self.shadowComparisons = self.shadowComparisons + 1
    local matches = expected == actual
    if not matches then
        self.shadowMismatches = self.shadowMismatches + 1
    end
    return matches
end

function Stats:GetSnapshot(target)
    target = type(target) == "table" and target or {}
    for index = 1, #REQUIRED_FIELDS do
        local field = REQUIRED_FIELDS[index]
        target[field] = self[field]
    end
    return target
end

function YMap:GetStats()
    local snapshot = Stats:GetSnapshot({})
    local pendingRefresh = snapshot.pendingRefresh == true
    local conflictBlocked = snapshot.conflictBlocked == true
    local restoreFailures = snapshot.restoreFailures

    local function MergeSubsystem(subsystem)
        if not (subsystem and subsystem.GetStats) then return end
        local values = subsystem:GetStats({})
        pendingRefresh = pendingRefresh
            or values.pendingRefresh == true
            or values.worldMapPendingRefresh == true
            or values.worldMapPendingRestore == true
        conflictBlocked = conflictBlocked or values.conflictBlocked == true
        for key, value in pairs(values) do
            if key ~= "pendingRefresh" and key ~= "conflictBlocked" and key ~= "restoreFailures" then
                snapshot[key] = value
            end
        end
    end

    if self.WorldMap and self.WorldMap.GetStats then
        MergeSubsystem(self.WorldMap)
    end
    if self.MapReveal then MergeSubsystem(self.MapReveal) end
    if self.DirectionLine then MergeSubsystem(self.DirectionLine) end
    if self.MetricsWidget then MergeSubsystem(self.MetricsWidget) end
    if self.Minimap and self.Minimap.GetStats then
        MergeSubsystem(self.Minimap)
    end
    if self.ProgressBars and self.ProgressBars.GetStats then
        MergeSubsystem(self.ProgressBars)
    end
    if self.ButtonDrawer and self.ButtonDrawer.GetStats then
        MergeSubsystem(self.ButtonDrawer)
    end
    snapshot.pendingRefresh = pendingRefresh
    snapshot.conflictBlocked = conflictBlocked
    snapshot.restoreFailures = restoreFailures
    if self.HotDiagnostics and self.HotDiagnostics.GetSnapshot then
        snapshot.diagnostics = self.HotDiagnostics:GetSnapshot({})
    end
    return snapshot
end

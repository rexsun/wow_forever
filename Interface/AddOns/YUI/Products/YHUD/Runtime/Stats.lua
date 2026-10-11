local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local Stats = YHUD.Stats or {}
YHUD.Stats = Stats

Stats.values = Stats.values or {
    identityChanges = 0,
    cooldownChanges = 0,
    resourceChanges = 0,
    availabilityChanges = 0,
    viewWrites = 0,
    layoutWrites = 0,
    sourceErrors = 0,
    configApplies = 0,
    resourceFormRequests = 0,
    resourceFormChanges = 0,
    resourceFormNoops = 0,
    resourceFormForcedReads = 0,
}
Stats.values.resourceFormRequests = Stats.values.resourceFormRequests or 0
Stats.values.resourceFormChanges = Stats.values.resourceFormChanges or 0
Stats.values.resourceFormNoops = Stats.values.resourceFormNoops or 0
Stats.values.resourceFormForcedReads =
    Stats.values.resourceFormForcedReads or 0
local RESOURCE_VISIBILITY_FIELDS = {
    "combatStateEvents",
    "combatStateMS",
    "combatEntryEvents",
    "combatEntryMS",
    "combatExitEvents",
    "combatExitMS",
    "combatAuraQueues",
    "combatContextRequests",
    "auraMaxRecoveryAttempts",
    "auraMaxRecoveryUnchanged",
    "auraMaxRecoveryChanged",
    "auraMaxRecoveryDeferred",
    "auraControlEvents",
    "auraControlCoalesced",
    "auraControlFlushes",
    "auraControlDisplayRefreshes",
    "auraControlSourceQueues",
    "combatRefreshes",
    "combatRefreshMS",
    "combatEntryRefreshMS",
    "combatExitRefreshMS",
    "combatGlowApplyMS",
    "combatResourceVisibilityMS",
    "combatResourceProjectionMS",
    "combatResourceFastPathHits",
    "combatResourceFallbacks",
    "resourceVisibilitySuppressions",
    "resourceVisibilityRestores",
    "resourceVisibilityNoops",
    "resourceVisibilityMS",
    "resourceSlotAcquires",
    "resourceAcquireMS",
    "resourceFullReleases",
    "resourceReleaseMS",
    "resourceRelayouts",
    "resourceRelayoutMS",
    "resourcePrefixPrepared",
    "resourcePrefixPreparedSlots",
    "resourcePrefixPrepareMS",
    "resourcePrefixProjectionHits",
    "resourcePrefixProjectionFallbacks",
    "resourcePrefixProjectionMS",
    "resourceEdgePrepared",
    "resourceEdgePreparedSlots",
    "resourceEdgePrepareMS",
    "resourceEdgeProjectionHits",
    "resourceEdgeProjectionFallbacks",
    "resourceEdgeProjectionMS",
    "resourceFixedProjectionHits",
    "resourceFixedProjectionFallbacks",
    "resourcePixelAlignmentRefreshes",
    "resourcePixelAlignmentRefreshMS",
    "resourcePixelAlignmentVisited",
    "resourcePixelAlignmentApplied",
    "resourcePixelAlignmentSkipped",
    "resourcePixelAlignmentUnavailable",
    "resourcePixelAlignmentGlobalFallbacks",
}
for index = 1, #RESOURCE_VISIBILITY_FIELDS do
    local field = RESOURCE_VISIBILITY_FIELDS[index]
    Stats.values[field] = Stats.values[field] or 0
end

local ACTIVE_TRINKET_FIELDS = {
    "activeTrinketEvents",
    "activeTrinketNoops",
    "activeTrinketProjectionApplies",
    "activeTrinketCombatDeferred",
    "activeTrinketProjectionMS",
}
for index = 1, #ACTIVE_TRINKET_FIELDS do
    local field = ACTIVE_TRINKET_FIELDS[index]
    Stats.values[field] = Stats.values[field] or 0
end

local DESIGN_HOVER_FIELDS = {
    "designHoverEvents",
    "designOutlineRefreshes",
    "designTooltipRequests",
    "designTooltipRenewals",
    "designTooltipShows",
    "designTooltipCancels",
    "designTooltipMS",
}
for index = 1, #DESIGN_HOVER_FIELDS do
    local field = DESIGN_HOVER_FIELDS[index]
    Stats.values[field] = Stats.values[field] or 0
end

local RESOURCE_PREVIEW_FIELDS = {
    "resourcePreviewLoops",
    "resourcePreviewAnimationFrames",
    "resourcePreviewFrameSkips",
    "resourcePreviewWrites",
    "resourcePreviewSameValueSkips",
    "resourcePreviewDiscreteWrites",
    "resourcePreviewHoldTimers",
    "resourcePreviewCleanups",
    "resourcePreviewGroupRefreshes",
    "resourcePreviewFullRefreshAvoided",
    "resourcePreviewElapsedMS",
    "resourcePreviewAppearanceSyncs",
    "resourcePreviewAppearanceElapsedMS",
}
for index = 1, #RESOURCE_PREVIEW_FIELDS do
    local field = RESOURCE_PREVIEW_FIELDS[index]
    Stats.values[field] = Stats.values[field] or 0
end

local SHARED_FIELDS = {
    "activeSources",
    "activeSubscriptions",
    "activeIndexes",
    "activeTicks",
    "events",
    "candidateKeys",
    "changedKeys",
    "apiReads",
    "sourceStateBuilds",
    "fanOutMonitors",
    "queueRequests",
    "coalescedRequests",
    "flushPasses",
    "uiWrites",
    "noOpSkips",
    "forcedDispatches",
    "poolActive",
    "poolFree",
    "fallbacks",
    "shadowComparisons",
    "shadowMismatches",
    "broadcastRequests",
    "coalescedBroadcasts",
    "broadcastFlushes",
    "broadcastSources",
}
local NATIVE_FIELDS = {
    "exactAuraSignals",
    "exactAuraVisibilityChanges",
    "exactAuraStableSignals",
    "itemFrameAcquireSignals",
    "itemFrameAcquireElapsedMS",
    "itemFrameAcquireMaxMS",
    "staticCooldownSignals",
    "staticCooldownElapsedMS",
    "staticCooldownMaxMS",
    "staticPositionRepairs",
    "staticPositionElapsedMS",
    "staticPositionMaxMS",
    "frameStateCreates",
    "iconChromeCreates",
    "statusChromeCreates",
    "procGlowCreates",
    "pandemicGlowCreates",
    "categorySyncRequests",
    "categorySyncCoalesced",
    "categorySyncFlushes",
    "categorySyncs",
    "categorySyncElapsedMS",
    "categorySyncScannedFrames",
    "categorySyncMaxFrames",
    "exactNativeBarRewrites",
    "layoutWrites",
    "dynamicMembershipSignals",
    "dynamicMembershipChanges",
    "dynamicMembershipFlushes",
    "dynamicMembershipScannedMembers",
    "dynamicMembershipMaxMembers",
    "dynamicGroupFlushes",
    "dynamicLayoutSignals",
    "dynamicLayoutFlushes",
    "categoryStructureFlushes",
    "categoryFlushProfileReads",
}
local PROFILE_FIELDS = {
    "hits",
    "misses",
    "invalidations",
    "revision",
}
local CDM_FIELDS = {
    "reconciles",
    "noChangeSkips",
    "changedReconciles",
    "nativeSettingsSignals",
    "layoutUnchangedSkips",
}
local CONTEXT_FIELDS = {
    "requests",
    "coalesced",
    "executions",
    "elapsedMS",
    "configApplyMS",
    "profileMS",
    "reconcileMS",
    "viewMS",
    "layoutMS",
    "nativeBridgeMS",
    "sourcesMS",
    "refreshMS",
}
local nativeStatsScratch = {}
local profileStatsScratch = {}
local cdmStatsScratch = {}

function Stats:Add(field, amount)
    local current = self.values[field]
    if current == nil then return false end
    self.values[field] = current + (tonumber(amount) or 1)
    return true
end

function Stats:GetSnapshot(target)
    target = target or {}
    for field, value in pairs(self.values) do
        target["yhud_" .. field] = value
    end
    for index = 1, #SHARED_FIELDS do
        local field = SHARED_FIELDS[index]
        target[field] = 0
    end
    if YUI.Monitor and YUI.Monitor.GetDataStats then
        YUI.Monitor:GetDataStats(target)
    end
    local context = YHUD.contextRefreshStats
    if type(context) == "table" then
        for index = 1, #CONTEXT_FIELDS do
            local field = CONTEXT_FIELDS[index]
            target["yhud_context_" .. field] = context[field] or 0
        end
    end
    local native = YHUD.NativeBridge
    if native and native.GetStats then
        local nativeStats = native:GetStats(nativeStatsScratch)
        for index = 1, #NATIVE_FIELDS do
            local field = NATIVE_FIELDS[index]
            target["yhud_native_" .. field] = nativeStats[field] or 0
        end
    end
    if YHUD.GetProfileCacheStats then
        local profile = YHUD:GetProfileCacheStats(profileStatsScratch)
        for index = 1, #PROFILE_FIELDS do
            local field = PROFILE_FIELDS[index]
            target["yhud_profile_" .. field] = profile[field] or 0
        end
    end
    local cdm = YHUD.CDMCatalog
    if cdm and cdm.GetStats then
        local cdmStats = cdm:GetStats(cdmStatsScratch)
        for index = 1, #CDM_FIELDS do
            local field = CDM_FIELDS[index]
            target["yhud_cdm_" .. field] = cdmStats[field] or 0
        end
    end
    return target
end

function YHUD:GetStats(target)
    return Stats:GetSnapshot(target)
end

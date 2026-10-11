local YUI = _G.YUI
if not YUI or not YUI.YChat then return end

local YChat = YUI.YChat
local Stats = {}
YChat.Stats = Stats

local values = {
    itemLinksCache = 0,
    itemLinksPending = 0,
    itemLinksQueries = 0,
    itemLinksCacheHits = 0,
    itemLinksFailures = 0,
    itemLinksFilters = 0,
    events = 0,
    listeners = 0,
    messageHooks = 0,
    supportedFrames = 0,
    bypassedFrames = 0,
    managedFrames = 0,
    appearanceManagedFrames = 0,
    pendingRestores = 0,
    appearancePendingRestores = 0,
    appearanceTargetGeneration = 0,
    appearanceTargetRebinds = 0,
    appearanceDomainFailures = 0,
    appearanceSuspendedDomains = 0,
    appearanceEnabled = false,
    appearanceMutationPaused = false,
    appearanceRefreshPending = false,
    appearanceLastFailure = "none",
    appearanceLastFailureDomain = "none",
    elementFadeEnabled = false,
    elementFadeScope = "all",
    elementFadeScopeEligible = true,
    elementFadeInstanceKnown = false,
    elementFadeInInstance = false,
    elementFadeInstanceType = "unknown",
    elementFadeSettingsOpen = false,
    elementFadeStatsMode = "none",
    elementFadeStatsConditionMatched = false,
    elementFadeStatsLinkedHidden = false,
    typographyManagedFrames = 0,
    typographyWrites = 0,
    typographyDomainFailures = 0,
    typographyRestoreFailures = 0,
    typographyEnabled = false,
    typographyLastFailure = "none",
    channelFilterInstalled = false,
    channelFormatWrappersInstalled = false,
    channelCacheEntries = 0,
    channelTransformQueueDepth = 0,
    channelTransformQueueDrops = 0,
    channelTransformDirtyFrames = 0,
    channelTransforms = 0,
    channelTransformBypasses = 0,
    channelTransformExternalReconciles = 0,
    channelTransformLastFailure = "none",
    channelLinkTakeoverReady = false,
    channelLinkTakeoverFrames = 0,
    channelLinkHoverDrivers = 0,
    deferredDriverInstalled = false,
    deferredDriverRestoreRequested = false,
    deferredDriverMessageRequested = false,
    deferredDriverChannelRequested = false,
    deferredDriverRunFrames = 0,
    deferredDriverCleanupFailed = false,
    tabHookInstalled = false,
    arrowModeManagedEditBoxes = 0,
    arrowModePendingRestores = 0,
    arrowModeLastFailure = "none",
    inputSkinEnabled = false,
    inputSkinManagedFrames = 0,
    inputSkinAllocatedTextures = 0,
    inputSkinLastFailure = "none",
    safeMessageEnabled = false,
    safeMessageFilters = 0,
    safeMessageQueueDepth = 0,
    safeMessageQueueDrops = 0,
    safeMessageFilterCalls = 0,
    safeMessageFilterBypasses = 0,
    safeMessageDuplicateBypasses = 0,
    safeMessageDrainFrames = 0,
    whisperNameColorRuntimeEnabled = false,
    whisperNameColorEnabled = false,
    whisperNameColorFilterInstalled = false,
    whisperNameColorFilterCalls = 0,
    whisperNameColorFilterBypasses = 0,
    whisperNameColorColoredNames = 0,
    whisperNameColorLastFailure = "none",
    autoInviteRuntimeEnabled = false,
    autoInviteConfigEnabled = false,
    autoInviteAttempts = 0,
    autoInviteSuccesses = 0,
    autoInviteBypasses = 0,
    historyRuntimeEnabled = false,
    historyConfigEnabled = false,
    historyStoredMessages = 0,
    historyRecordedMessages = 0,
    historyReplayedMessages = 0,
    historyBypasses = 0,
    historyClearOperations = 0,
    nativeSettlePending = 0,
    nativeSettleFrames = 0,
    combatLogManaged = 0,
    combatLogHidden = 0,
    combatLogRestorePending = 0,
    copyPopupShown = 0,
    copyBufferedLines = 0,
    layoutPending = 0,
    layoutRegistered = 0,
    layoutPlacementRepairs = 0,
    activationFailures = 0,
    runtimeBlocked = false,
    runtimeBlockedReason = "none",
    metadataAppends = 0,
    dirtyRequests = 0,
    coalescedRequests = 0,
    flushPasses = 0,
    visibleLineSyncs = 0,
    overlayWrites = 0,
    noOpSkips = 0,
    activeDrivers = 0,
    activeTickers = 0,
    activeTimers = 0,
    activeAnimations = 0,
    poolActive = 0,
    poolFree = 0,
    shadowComparisons = 0,
    shadowMismatches = 0,
    secretBypasses = 0,
    restrictionState = "UNKNOWN",
    restrictionTransitions = 0,
    qualityState = "Q3",
    qualityTransitions = 0,
    q3Fallbacks = 0,
    q3Restores = 0,
    adapterMismatches = 0,
    filterCalls = 0,
    filterBypasses = 0,
    historyWrites = 0,
    historyPrivateDrops = 0,
    historySecretDrops = 0,
    automationAttempts = 0,
    automationBypasses = 0,
    cleanupRuns = 0,
    cleanupLeaks = 0,
}

local counterDefaults = {
    events = 0,
    metadataAppends = 0,
    dirtyRequests = 0,
    coalescedRequests = 0,
    flushPasses = 0,
    visibleLineSyncs = 0,
    overlayWrites = 0,
    noOpSkips = 0,
    shadowComparisons = 0,
    shadowMismatches = 0,
    secretBypasses = 0,
    restrictionTransitions = 0,
    qualityTransitions = 0,
    q3Fallbacks = 0,
    q3Restores = 0,
    adapterMismatches = 0,
    typographyWrites = 0,
    typographyDomainFailures = 0,
    typographyRestoreFailures = 0,
    safeMessageQueueDrops = 0,
    safeMessageFilterCalls = 0,
    safeMessageFilterBypasses = 0,
    safeMessageDuplicateBypasses = 0,
    safeMessageDrainFrames = 0,
    whisperNameColorFilterCalls = 0,
    whisperNameColorFilterBypasses = 0,
    whisperNameColorColoredNames = 0,
    autoInviteAttempts = 0,
    autoInviteSuccesses = 0,
    autoInviteBypasses = 0,
    historyRecordedMessages = 0,
    historyReplayedMessages = 0,
    historyBypasses = 0,
    historyClearOperations = 0,
    filterCalls = 0,
    filterBypasses = 0,
    channelTransformQueueDrops = 0,
    channelTransforms = 0,
    channelTransformBypasses = 0,
    channelTransformExternalReconciles = 0,
    historyWrites = 0,
    historyPrivateDrops = 0,
    historySecretDrops = 0,
    automationAttempts = 0,
    automationBypasses = 0,
    cleanupRuns = 0,
}

function Stats:ResetCounters()
    for field, defaultValue in pairs(counterDefaults) do
        values[field] = defaultValue
    end
end

function Stats:Reset()
    self:ResetCounters()
end

function Stats:Increment(field, amount)
    local current = values[field]
    if type(current) ~= "number" then return false end

    values[field] = current + (amount or 1)
    return true
end

function Stats:IncrementMetadataAppends()
    values.metadataAppends = values.metadataAppends + 1
    return true
end

function Stats:Set(field, value)
    if values[field] == nil then return false end
    values[field] = value
    return true
end

function Stats:Get(field)
    return values[field]
end

function Stats:GetSnapshot(target)
    target = target or {}
    for field, value in pairs(values) do
        target[field] = value
    end
    return target
end

function YChat:GetStats(target)
    return Stats:GetSnapshot(target)
end

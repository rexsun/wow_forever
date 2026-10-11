local ADDON_NAME = ...
local YUI = _G.YUI
if not YUI or not YUI.YChat then return end

local YChat = YUI.YChat
local L = YUI.Locale and YUI.Locale:Get("YChat") or {}
local format = string.format
local lower = string.lower
local match = string.match
local tostring = tostring
local type = type

local LOW_FREQUENCY_EVENTS = {
    "PLAYER_ENTERING_WORLD",
}
local adapterGaugeScratch = {}
local shadowGaugeScratch = {}
local appearanceGaugeScratch = {}
local elementFadeGaugeScratch = {}
local typographyGaugeScratch = {}
local channelInputGaugeScratch = {}
local inputSkinGaugeScratch = {}
local safeMessageGaugeScratch = {}
local itemLinksGaugeScratch = {}
local whisperNameColorGaugeScratch = {}
local autoInviteGaugeScratch = {}
local historyGaugeScratch = {}
local RETAIL_PRODUCT = (YUI.IsForever or YUI.IsRetail) == true

local function T(key, fallback)
    local value = L[key]
    return type(value) == "string" and value ~= "" and value or fallback
end

local function Print(message)
    if YUI.Print then
        YUI:Print("|cff66c6ffYChat:|r", message)
    elseif _G.print then
        _G.print("YChat:", message)
    end
end

local function PrintOperationFailure(reason)
    if reason == "native-restore-pending" then
        Print(T(
            "command.restore.pending",
            "Native layout restoration is awaiting confirmation; the operation will finish after the next native layout pass."
        ))
        return
    end
    Print(format(T("command.failed", "Operation failed: %s"), tostring(reason or "unknown")))
end

local function InvokeShadow(method, ...)
    local shadow = YChat.Shadow
    local callback = shadow and shadow[method]
    if type(callback) ~= "function" then
        return false, T("command.shadow_unavailable", "The shadow prototype is not available yet.")
    end

    local callOK, result, detail = pcall(callback, shadow, ...)
    if not callOK then
        return false, tostring(result)
    end
    if result == false then
        return false, tostring(detail or "unknown")
    end
    return true, result, detail
end

local function CallShadow(method, ...)
    local ok, result, detail = InvokeShadow(method, ...)
    if not ok then
        Print(format(T("command.failed", "Operation failed: %s"), tostring(result)))
        return false
    end
    if type(result) == "string" and result ~= "" then
        Print(result)
    elseif type(detail) == "string" and detail ~= "" then
        Print(detail)
    end
    return true
end

local function CallShadowQuiet(method, ...)
    return InvokeShadow(method, ...)
end

local function InvokeAppearance(method, ...)
    local appearance = YChat.Appearance
    if type(appearance) ~= "table" then return true end
    local callback = appearance and appearance[method]
    if type(callback) ~= "function" then
        return false, "appearance-unavailable"
    end
    local callOK, result, detail = pcall(callback, appearance, ...)
    if not callOK then return false, tostring(result) end
    if result == false then return false, tostring(detail or "unknown") end
    return true, result, detail
end

local function InvokeRuntimeModule(moduleName, method, ...)
    local module = YChat[moduleName]
    if type(module) ~= "table" then return true end
    local callback = module[method]
    if type(callback) ~= "function" then
        return false, lower(moduleName) .. "-unavailable"
    end
    local callOK, result, detail = pcall(callback, module, ...)
    if not callOK then return false, tostring(result) end
    if result == false then return false, tostring(detail or "unknown") end
    return true, result, detail
end

local function EventFrameOnEvent(_, event, arg1, arg2)
    if RETAIL_PRODUCT and event == "PLAYER_LOGOUT" then
        InvokeRuntimeModule("ChannelInput", "PruneSavedInputHistory")
        return
    end
    if YChat.Stats and YChat.Stats.Increment then
        YChat.Stats:Increment("events")
    end
    if (event == "ADDON_LOADED" or event == "PLAYER_ENTERING_WORLD")
        and YChat.runtimeEnabled
        and YChat.ConflictGuard
        and type(YChat.ConflictGuard.Check) == "function"
    then
        local conflict = YChat.ConflictGuard:Check(event == "ADDON_LOADED" and { force = true } or nil)
        if conflict and conflict.blocked and YChat.YieldToExternalChatController then
            YChat:YieldToExternalChatController(conflict)
            return
        end
    end
    CallShadowQuiet("OnLifecycleEvent", event, arg1)
    if RETAIL_PRODUCT and event == "PLAYER_ENTERING_WORLD" and YChat.runtimeEnabled then
        InvokeRuntimeModule("ElementFade", "OnWindowsChanged", event)
    end
    if RETAIL_PRODUCT and event == "PLAYER_ENTERING_WORLD"
        and YChat.runtimeEnabled and YChat.ApplyRetailTimestamp
    then
        YChat:ApplyRetailTimestamp("entering-world")
        if type(YChat.RetryPendingVisualDomains) == "function" then
            YChat:RetryPendingVisualDomains("entering-world")
        end
        local history = YChat.HistoryRuntime
        if history and type(history.ReplayOnLogin) == "function" then
            pcall(history.ReplayOnLogin, history, arg1, arg2)
        end
    elseif RETAIL_PRODUCT
        and event == "ADDON_LOADED"
        and arg1 == "Blizzard_CombatLog"
    then
        InvokeAppearance("OnWindowsChanged", "combat-log-loaded")
    elseif RETAIL_PRODUCT and event == "PLAYER_REGEN_ENABLED" then
        if type(YChat.RetryPendingVisualDomains) == "function" then
            YChat:RetryPendingVisualDomains("player-regen-enabled")
        end
    elseif RETAIL_PRODUCT
        and (event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED")
    then
        InvokeAppearance("OnWindowsChanged", event)
    end
end

function YChat:RefreshRuntimeGauges()
    local stats = self.Stats
    if not (stats and stats.Set) then return false end
    if self.ItemLinks and self.ItemLinks.GetRuntimeGauges then
        self.ItemLinks:GetRuntimeGauges(itemLinksGaugeScratch)
        for key, value in pairs(itemLinksGaugeScratch) do stats:Set(key, value) end
    end

    local adapter = self.Adapter
    if adapter and adapter.GetRuntimeGauges then
        adapter:GetRuntimeGauges(adapterGaugeScratch)
    else
        adapterGaugeScratch.listeners = 0
        adapterGaugeScratch.messageHooks = 0
        adapterGaugeScratch.restrictionState = "UNKNOWN"
        adapterGaugeScratch.supportedFrames = 0
        adapterGaugeScratch.bypassedFrames = 0
        adapterGaugeScratch.channelLinkTakeoverFrames = 0
        adapterGaugeScratch.channelLinkHoverDrivers = 0
        adapterGaugeScratch.deferredDriverInstalled = false
        adapterGaugeScratch.deferredDriverRestoreRequested = false
        adapterGaugeScratch.deferredDriverMessageRequested = false
        adapterGaugeScratch.deferredDriverRunFrames = 0
        adapterGaugeScratch.deferredDriverCleanupFailed = false
    end

    local shadow = self.Shadow
    if shadow and shadow.GetRuntimeGauges then
        shadow:GetRuntimeGauges(shadowGaugeScratch)
    else
        shadowGaugeScratch.poolActive = 0
        shadowGaugeScratch.poolFree = 0
        shadowGaugeScratch.cleanupLeaks = 0
        shadowGaugeScratch.qualityState = "Q3"
        shadowGaugeScratch.activeDrivers = 0
        shadowGaugeScratch.activeTickers = 0
        shadowGaugeScratch.activeTimers = 0
        shadowGaugeScratch.activeAnimations = 0
        shadowGaugeScratch.managedFrames = 0
        shadowGaugeScratch.pendingRestores = 0
        shadowGaugeScratch.activationFailures = 0
    end

    local appearance = self.Appearance
    if appearance and appearance.GetRuntimeGauges then
        appearance:GetRuntimeGauges(appearanceGaugeScratch)
    else
        appearanceGaugeScratch.managedFrames = 0
        appearanceGaugeScratch.pendingRestores = 0
        appearanceGaugeScratch.activeDrivers = 0
        appearanceGaugeScratch.activeTickers = 0
        appearanceGaugeScratch.activeTimers = 0
        appearanceGaugeScratch.activeAnimations = 0
        appearanceGaugeScratch.appearanceEnabled = false
        appearanceGaugeScratch.appearanceMutationPaused = false
        appearanceGaugeScratch.appearanceRefreshPending = false
        appearanceGaugeScratch.appearanceLastFailure = nil
        appearanceGaugeScratch.appearanceLastFailureDomain = nil
    end
    local elementFade = self.ElementFade
    if elementFade and elementFade.GetRuntimeGauges then
        elementFade:GetRuntimeGauges(elementFadeGaugeScratch)
    else
        elementFadeGaugeScratch.elementFadeEnabled = false
        elementFadeGaugeScratch.elementFadeScope = "all"
        elementFadeGaugeScratch.elementFadeScopeEligible = true
        elementFadeGaugeScratch.elementFadeInstanceKnown = false
        elementFadeGaugeScratch.elementFadeInInstance = false
        elementFadeGaugeScratch.elementFadeInstanceType = "unknown"
        elementFadeGaugeScratch.elementFadeSettingsOpen = false
        elementFadeGaugeScratch.elementFadeStatsMode = "none"
        elementFadeGaugeScratch.elementFadeStatsConditionMatched = false
        elementFadeGaugeScratch.elementFadeStatsLinkedHidden = false
        elementFadeGaugeScratch.elementFadeActiveDrivers = 0
        elementFadeGaugeScratch.elementFadeActiveTimers = 0
    end
    local typography = self.Typography
    if typography and typography.GetRuntimeGauges then
        typography:GetRuntimeGauges(typographyGaugeScratch)
    else
        typographyGaugeScratch.typographyManagedFrames = 0
        typographyGaugeScratch.typographyEnabled = false
        typographyGaugeScratch.typographyLastFailure = "none"
    end
    local channelInput = self.ChannelInput
    if channelInput and channelInput.GetRuntimeGauges then
        channelInput:GetRuntimeGauges(channelInputGaugeScratch)
    else
        channelInputGaugeScratch.channelFilterInstalled = false
        channelInputGaugeScratch.channelFormatWrappersInstalled = false
        channelInputGaugeScratch.channelTransformQueueDepth = 0
        channelInputGaugeScratch.channelLinkTakeoverReady = false
        channelInputGaugeScratch.tabHookInstalled = false
        channelInputGaugeScratch.arrowModeManagedEditBoxes = 0
        channelInputGaugeScratch.arrowModePendingRestores = 0
        channelInputGaugeScratch.arrowModeLastFailure = "none"
    end
    local inputSkin = self.InputSkin
    if inputSkin and inputSkin.GetRuntimeGauges then
        inputSkin:GetRuntimeGauges(inputSkinGaugeScratch)
    else
        inputSkinGaugeScratch.inputSkinEnabled = false
        inputSkinGaugeScratch.inputSkinManagedFrames = 0
        inputSkinGaugeScratch.inputSkinAllocatedTextures = 0
        inputSkinGaugeScratch.inputSkinLastFailure = "none"
    end
    local safeMessage = self.SafeMessage
    if safeMessage and safeMessage.GetRuntimeGauges then
        safeMessage:GetRuntimeGauges(safeMessageGaugeScratch)
    else
        safeMessageGaugeScratch.safeMessageEnabled = false
        safeMessageGaugeScratch.safeMessageFilters = 0
        safeMessageGaugeScratch.safeMessageQueueDepth = 0
        safeMessageGaugeScratch.safeMessageQueueDrops = 0
    end
    local whisperNameColor = self.WhisperNameColor
    if whisperNameColor and whisperNameColor.GetRuntimeGauges then
        whisperNameColor:GetRuntimeGauges(whisperNameColorGaugeScratch)
    else
        whisperNameColorGaugeScratch.whisperNameColorRuntimeEnabled = false
        whisperNameColorGaugeScratch.whisperNameColorEnabled = false
        whisperNameColorGaugeScratch.whisperNameColorFilterInstalled = false
        whisperNameColorGaugeScratch.whisperNameColorFilterCalls = 0
        whisperNameColorGaugeScratch.whisperNameColorFilterBypasses = 0
        whisperNameColorGaugeScratch.whisperNameColorColoredNames = 0
        whisperNameColorGaugeScratch.whisperNameColorLastFailure = "none"
    end
    local autoInvite = self.AutoInvite
    if autoInvite and autoInvite.GetRuntimeGauges then
        autoInvite:GetRuntimeGauges(autoInviteGaugeScratch)
    else
        autoInviteGaugeScratch.autoInviteRuntimeEnabled = false
        autoInviteGaugeScratch.autoInviteConfigEnabled = false
    end
    local history = self.HistoryRuntime
    if history and history.GetRuntimeGauges then
        history:GetRuntimeGauges(historyGaugeScratch)
    else
        historyGaugeScratch.historyRuntimeEnabled = false
        historyGaugeScratch.historyConfigEnabled = false
        historyGaugeScratch.historyStoredMessages = 0
    end

    stats:Set("listeners", (self.lifecycleListenerCount or 0) + (adapterGaugeScratch.listeners or 0))
    stats:Set("messageHooks", adapterGaugeScratch.messageHooks or 0)
    stats:Set("restrictionState", adapterGaugeScratch.restrictionState or "UNKNOWN")
    stats:Set("supportedFrames", adapterGaugeScratch.supportedFrames or 0)
    stats:Set("bypassedFrames", adapterGaugeScratch.bypassedFrames or 0)
    stats:Set("poolActive", shadowGaugeScratch.poolActive or 0)
    stats:Set("poolFree", shadowGaugeScratch.poolFree or 0)
    stats:Set("cleanupLeaks", shadowGaugeScratch.cleanupLeaks or 0)
    stats:Set("qualityState", shadowGaugeScratch.qualityState or "Q3")
    stats:Set(
        "activeDrivers",
        (shadowGaugeScratch.activeDrivers or 0)
            + (appearanceGaugeScratch.activeDrivers or 0)
            + (elementFadeGaugeScratch.elementFadeActiveDrivers or 0)
    )
    stats:Set(
        "activeTickers",
        (shadowGaugeScratch.activeTickers or 0)
            + (appearanceGaugeScratch.activeTickers or 0)
    )
    stats:Set(
        "activeTimers",
        (shadowGaugeScratch.activeTimers or 0)
            + (appearanceGaugeScratch.activeTimers or 0)
            + (elementFadeGaugeScratch.elementFadeActiveTimers or 0)
    )
    stats:Set(
        "activeAnimations",
        (shadowGaugeScratch.activeAnimations or 0)
            + (appearanceGaugeScratch.activeAnimations or 0)
    )
    stats:Set("managedFrames", shadowGaugeScratch.managedFrames or 0)
    stats:Set("appearanceManagedFrames", appearanceGaugeScratch.managedFrames or 0)
    stats:Set(
        "pendingRestores",
        (shadowGaugeScratch.pendingRestores or 0)
            + (appearanceGaugeScratch.pendingRestores or 0)
    )
    stats:Set(
        "appearancePendingRestores",
        appearanceGaugeScratch.pendingRestores or 0
    )
    stats:Set(
        "appearanceTargetGeneration",
        appearanceGaugeScratch.appearanceTargetGeneration or 0
    )
    stats:Set(
        "appearanceTargetRebinds",
        appearanceGaugeScratch.appearanceTargetRebinds or 0
    )
    stats:Set(
        "appearanceDomainFailures",
        appearanceGaugeScratch.appearanceDomainFailures or 0
    )
    stats:Set(
        "appearanceSuspendedDomains",
        appearanceGaugeScratch.appearanceSuspendedDomains or 0
    )
    stats:Set("appearanceEnabled", appearanceGaugeScratch.appearanceEnabled == true)
    stats:Set(
        "appearanceMutationPaused",
        appearanceGaugeScratch.appearanceMutationPaused == true
    )
    stats:Set(
        "appearanceRefreshPending",
        appearanceGaugeScratch.appearanceRefreshPending == true
    )
    stats:Set(
        "appearanceLastFailure",
        appearanceGaugeScratch.appearanceLastFailure or "none"
    )
    stats:Set(
        "appearanceLastFailureDomain",
        appearanceGaugeScratch.appearanceLastFailureDomain or "none"
    )
    stats:Set("elementFadeEnabled", elementFadeGaugeScratch.elementFadeEnabled == true)
    stats:Set("elementFadeScope", elementFadeGaugeScratch.elementFadeScope or "all")
    stats:Set(
        "elementFadeScopeEligible",
        elementFadeGaugeScratch.elementFadeScopeEligible == true
    )
    stats:Set(
        "elementFadeInstanceKnown",
        elementFadeGaugeScratch.elementFadeInstanceKnown == true
    )
    stats:Set(
        "elementFadeInInstance",
        elementFadeGaugeScratch.elementFadeInInstance == true
    )
    stats:Set(
        "elementFadeInstanceType",
        elementFadeGaugeScratch.elementFadeInstanceType or "unknown"
    )
    stats:Set(
        "elementFadeSettingsOpen",
        elementFadeGaugeScratch.elementFadeSettingsOpen == true
    )
    stats:Set(
        "elementFadeStatsMode",
        elementFadeGaugeScratch.elementFadeStatsMode or "none"
    )
    stats:Set(
        "elementFadeStatsConditionMatched",
        elementFadeGaugeScratch.elementFadeStatsConditionMatched == true
    )
    stats:Set(
        "elementFadeStatsLinkedHidden",
        elementFadeGaugeScratch.elementFadeStatsLinkedHidden == true
    )
    stats:Set(
        "typographyManagedFrames",
        typographyGaugeScratch.typographyManagedFrames or 0
    )
    stats:Set("typographyEnabled", typographyGaugeScratch.typographyEnabled == true)
    stats:Set(
        "typographyLastFailure",
        typographyGaugeScratch.typographyLastFailure or "none"
    )
    stats:Set(
        "channelFilterInstalled",
        channelInputGaugeScratch.channelFilterInstalled == true
    )
    stats:Set(
        "channelFormatWrappersInstalled",
        channelInputGaugeScratch.channelFormatWrappersInstalled == true
    )
    stats:Set(
        "channelTransformQueueDepth",
        channelInputGaugeScratch.channelTransformQueueDepth or 0
    )
    stats:Set(
        "channelLinkTakeoverReady",
        channelInputGaugeScratch.channelLinkTakeoverReady == true
    )
    stats:Set(
        "channelLinkTakeoverFrames",
        adapterGaugeScratch.channelLinkTakeoverFrames or 0
    )
    stats:Set(
        "channelLinkHoverDrivers",
        adapterGaugeScratch.channelLinkHoverDrivers or 0
    )
    stats:Set("deferredDriverInstalled", adapterGaugeScratch.deferredDriverInstalled == true)
    stats:Set(
        "deferredDriverRestoreRequested",
        adapterGaugeScratch.deferredDriverRestoreRequested == true
    )
    stats:Set(
        "deferredDriverMessageRequested",
        adapterGaugeScratch.deferredDriverMessageRequested == true
    )
    stats:Set(
        "deferredDriverRunFrames",
        adapterGaugeScratch.deferredDriverRunFrames or 0
    )
    stats:Set(
        "deferredDriverCleanupFailed",
        adapterGaugeScratch.deferredDriverCleanupFailed == true
    )
    stats:Set("tabHookInstalled", channelInputGaugeScratch.tabHookInstalled == true)
    stats:Set(
        "arrowModeManagedEditBoxes",
        channelInputGaugeScratch.arrowModeManagedEditBoxes or 0
    )
    stats:Set(
        "arrowModePendingRestores",
        channelInputGaugeScratch.arrowModePendingRestores or 0
    )
    stats:Set(
        "arrowModeLastFailure",
        channelInputGaugeScratch.arrowModeLastFailure or "none"
    )
    stats:Set("inputSkinEnabled", inputSkinGaugeScratch.inputSkinEnabled == true)
    stats:Set(
        "inputSkinManagedFrames",
        inputSkinGaugeScratch.inputSkinManagedFrames or 0
    )
    stats:Set(
        "inputSkinAllocatedTextures",
        inputSkinGaugeScratch.inputSkinAllocatedTextures or 0
    )
    stats:Set(
        "inputSkinLastFailure",
        inputSkinGaugeScratch.inputSkinLastFailure or "none"
    )
    stats:Set("safeMessageEnabled", safeMessageGaugeScratch.safeMessageEnabled == true)
    stats:Set("safeMessageFilters", safeMessageGaugeScratch.safeMessageFilters or 0)
    stats:Set(
        "safeMessageQueueDepth",
        safeMessageGaugeScratch.safeMessageQueueDepth or 0
    )
    stats:Set(
        "safeMessageQueueDrops",
        safeMessageGaugeScratch.safeMessageQueueDrops or 0
    )
    stats:Set(
        "whisperNameColorRuntimeEnabled",
        whisperNameColorGaugeScratch.whisperNameColorRuntimeEnabled == true
    )
    stats:Set(
        "whisperNameColorEnabled",
        whisperNameColorGaugeScratch.whisperNameColorEnabled == true
    )
    stats:Set(
        "whisperNameColorFilterInstalled",
        whisperNameColorGaugeScratch.whisperNameColorFilterInstalled == true
    )
    stats:Set(
        "whisperNameColorFilterCalls",
        whisperNameColorGaugeScratch.whisperNameColorFilterCalls or 0
    )
    stats:Set(
        "whisperNameColorFilterBypasses",
        whisperNameColorGaugeScratch.whisperNameColorFilterBypasses or 0
    )
    stats:Set(
        "whisperNameColorColoredNames",
        whisperNameColorGaugeScratch.whisperNameColorColoredNames or 0
    )
    stats:Set(
        "whisperNameColorLastFailure",
        whisperNameColorGaugeScratch.whisperNameColorLastFailure or "none"
    )
    stats:Set(
        "autoInviteRuntimeEnabled",
        autoInviteGaugeScratch.autoInviteRuntimeEnabled == true
    )
    stats:Set(
        "autoInviteConfigEnabled",
        autoInviteGaugeScratch.autoInviteConfigEnabled == true
    )
    stats:Set(
        "historyRuntimeEnabled",
        historyGaugeScratch.historyRuntimeEnabled == true
    )
    stats:Set(
        "historyConfigEnabled",
        historyGaugeScratch.historyConfigEnabled == true
    )
    stats:Set(
        "historyStoredMessages",
        historyGaugeScratch.historyStoredMessages or 0
    )
    stats:Set("nativeSettlePending", appearanceGaugeScratch.nativeSettlePending or 0)
    stats:Set("nativeSettleFrames", appearanceGaugeScratch.nativeSettleFrames or 0)
    stats:Set("combatLogManaged", appearanceGaugeScratch.combatLogManaged or 0)
    stats:Set("combatLogHidden", appearanceGaugeScratch.combatLogHidden or 0)
    stats:Set(
        "combatLogRestorePending",
        appearanceGaugeScratch.combatLogRestorePending or 0
    )
    stats:Set("copyPopupShown", appearanceGaugeScratch.copyPopupShown or 0)
    stats:Set("copyBufferedLines", appearanceGaugeScratch.copyBufferedLines or 0)
    stats:Set("layoutPending", appearanceGaugeScratch.layoutPending or 0)
    stats:Set("layoutRegistered", appearanceGaugeScratch.layoutRegistered or 0)
    stats:Set(
        "layoutPlacementRepairs",
        appearanceGaugeScratch.layoutPlacementRepairs or 0
    )
    stats:Set("activationFailures", shadowGaugeScratch.activationFailures or 0)
    stats:Set("runtimeBlocked", self.runtimeBlocked == true)
    stats:Set("runtimeBlockedReason", self.runtimeBlockedReason or "none")
    return true
end

function YChat:AttachRuntime()
    if not self.eventFrame then
        if type(_G.CreateFrame) ~= "function" then return false end
        self.eventFrame = _G.CreateFrame("Frame", "YUI_YChat_LifecycleEventFrame")
    end

    local frame = self.eventFrame
    frame:SetScript("OnEvent", EventFrameOnEvent)
    frame:UnregisterAllEvents()
    for index = 1, #LOW_FREQUENCY_EVENTS do
        frame:RegisterEvent(LOW_FREQUENCY_EVENTS[index])
    end
    if RETAIL_PRODUCT then
        frame:RegisterEvent("ADDON_LOADED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
        frame:RegisterEvent("UI_SCALE_CHANGED")
        frame:RegisterEvent("CVAR_UPDATE")
        frame:RegisterEvent("PLAYER_LOGOUT")
    end
    if YUI.IsWrath == true then frame:RegisterEvent("PLAYER_REGEN_ENABLED") end

    self.lifecycleListenerCount = #LOW_FREQUENCY_EVENTS
        + (RETAIL_PRODUCT and 6 or 0)
        + (YUI.IsWrath == true and 1 or 0)
    self.runtimeEnabled = true
    self:RefreshRuntimeGauges()
    return true
end

function YChat:DetachRuntime()
    if self.eventFrame then
        self.eventFrame:UnregisterAllEvents()
        self.eventFrame:SetScript("OnEvent", nil)
    end
    self.lifecycleListenerCount = 0
    if self.Stats and self.Stats.Increment then
        self.Stats:Increment("cleanupRuns")
    end
    self.runtimeEnabled = false
    self:RefreshRuntimeGauges()
end

function YChat:FinalizeRuntimeDisable()
    if self.runtimeEnabled then self:DetachRuntime() end
    local panel = self.DevPanel
    if panel and type(panel.Hide) == "function" then pcall(panel.Hide, panel) end
    self.lifecycleDisablePending = false
    self.sessionEnabled = self.runtimeBlocked == true
    return true
end

function YChat:ResumeDeferredEnable(source)
    if self.enableAfterRestore ~= true then return true end
    local shadow = self.Shadow
    if type(shadow) == "table" and shadow.stopAfterRestore == true then
        return false, "native-restore-pending"
    end

    self.lifecycleDisablePending = false
    self.enableAfterRestore = false
    self.sessionEnabled = true
    local callOK, enabled = pcall(self.OnLifecycleEnable, self)
    if not callOK or enabled ~= true then
        self.sessionEnabled = false
        self.productionPendingReason = callOK
            and "deferred-enable-failed"
            or tostring(enabled or "deferred-enable-failed")
        return false, self.productionPendingReason
    end
    self.productionPendingReason = nil
    pcall(self.RefreshRuntimeGauges, self)
    return true, source or "native-restore-committed"
end

function YChat:SetConflictBlocked(conflict)
    conflict = conflict or { blocked = true, matches = {} }
    self.enableAfterRestore = false
    self.runtimeBlocked = true
    self.runtimeBlockedReason = "external-chat-controller"
    self.runtimeBlockedController = conflict.controller
    self.externalConflict = conflict
    self.productionPendingReason = self.runtimeBlockedReason
    self.sessionEnabled = true
    if conflict.status == "active" and YUI.Yield then
        YUI.Yield:Set("chat", conflict.controller, {
            status = conflict.status,
            matches = conflict.matches,
            enabled = true,
        })
    elseif YUI.Yield then
        YUI.Yield:Clear("chat")
    end
    self:RefreshRuntimeGauges()
    return true
end

function YChat:GetYieldController()
    if self.runtimeBlocked == true and type(self.externalConflict) == "table"
        and self.externalConflict.blocked == true
        and self.externalConflict.status == "active" then
        return type(self.runtimeBlockedController) == "string" and self.runtimeBlockedController or nil, true
    end
    return nil, false
end

function YChat:YieldToExternalChatController(conflict)
    if self.runtimeEnabled
        or (type(self.Shadow) == "table" and self.Shadow.enabled == true)
        or (type(self.Appearance) == "table" and self.Appearance.enabled == true)
    then
        local disabled, reason = pcall(self.OnLifecycleDisable, self)
        if not disabled then self.productionPendingReason = tostring(reason) end
    end
    return self:SetConflictBlocked(conflict)
end

function YChat:OnLifecycleEnable()
    local conflict = self.ConflictGuard and self.ConflictGuard:Check()
        or { blocked = false, matches = {} }
    if conflict.blocked then
        return self:SetConflictBlocked(conflict)
    end

    self.externalConflict = conflict
    self.runtimeBlocked = false
    self.runtimeBlockedReason = nil
    self.runtimeBlockedController = nil
    if YUI.Yield then YUI.Yield:Clear("chat") end
    local shadow = self.Shadow
    if self.lifecycleDisablePending or (type(shadow) == "table" and shadow.stopAfterRestore == true) then
        self.enableAfterRestore = true
        self.sessionEnabled = false
        self.productionPendingReason = "native-restore-pending"
        return true
    end
    self.enableAfterRestore = false
    if not self:AttachRuntime() then error("YChat runtime attach failed") end
    local enabled, reason = InvokeShadow("OnModuleEnable")
    if not enabled then
        self:DetachRuntime()
        error(reason or "YChat shadow lifecycle enable failed")
    end
    if RETAIL_PRODUCT then self:ApplyRetailTimestamp("lifecycle-enable") end
    self.sessionEnabled = true
    return true
end

function YChat:OnLifecycleDisable()
    self.enableAfterRestore = false
    self.runtimeBlocked = false
    self.runtimeBlockedReason = nil
    self.runtimeBlockedController = nil
    self.externalConflict = nil
    self.lastConflictNotice = nil
    if YUI.Yield then YUI.Yield:Clear("chat") end
    local shadowActive = type(self.Shadow) == "table" and self.Shadow.enabled == true
    local adapterActive = type(self.Adapter) == "table" and self.Adapter.enabled == true
    local safeMessageActive = type(self.SafeMessage) == "table"
        and self.SafeMessage.enabled == true
    local whisperNameColorActive = type(self.WhisperNameColor) == "table"
        and (
            self.WhisperNameColor.runtimeEnabled == true
            or self.WhisperNameColor.filterInstalled == true
        )
    if not self.runtimeEnabled
        and not shadowActive
        and not adapterActive
        and not safeMessageActive
        and not whisperNameColorActive
        and not (self.ItemLinks and (self.ItemLinks.enabled or self.ItemLinks.filterInstalled))
    then
        self.sessionEnabled = false
        self.productionPendingReason = nil
        self:RefreshRuntimeGauges()
        return true
    end
    local whisperNameDisabled, whisperNameReason =
        InvokeRuntimeModule("WhisperNameColor", "SetEnabled", false, "lifecycle-disable")
    if not whisperNameDisabled then
        error(whisperNameReason or "YChat whisper-name color disable failed")
    end
    local itemLinksDisabled, itemLinksReason = InvokeRuntimeModule("ItemLinks", "SetEnabled", false)
    if not itemLinksDisabled then error(itemLinksReason or "YChat item links disable failed") end
    local safeDisabled, safeReason =
        InvokeRuntimeModule("SafeMessage", "SetEnabled", false, "lifecycle-disable")
    if not safeDisabled then
        error(safeReason or "YChat safe-message disable failed")
    end
    local autoInviteDisabled, autoInviteReason =
        InvokeRuntimeModule("AutoInvite", "SetEnabled", false, "lifecycle-disable")
    if not autoInviteDisabled then
        error(autoInviteReason or "YChat auto-invite disable failed")
    end
    local historyDisabled, historyReason =
        InvokeRuntimeModule("HistoryRuntime", "SetEnabled", false, "lifecycle-disable")
    if not historyDisabled then
        error(historyReason or "YChat history disable failed")
    end
    local channelDisabled, channelReason =
        InvokeRuntimeModule("ChannelInput", "SetEnabled", false, "lifecycle-disable")
    local channelRestorePending = false
    if not channelDisabled then
        channelRestorePending = type(self.ChannelInput) == "table"
            and self.ChannelInput.restorePending == true
        if not channelRestorePending then
            error(channelReason or "YChat channel-input disable failed")
        end
        self.lifecycleDisablePending = true
        self.sessionEnabled = false
        self.productionPendingReason = channelReason
    end
    local typographyDisabled, typographyReason =
        InvokeRuntimeModule("Typography", "SetEnabled", false, "lifecycle-disable")
    if not typographyDisabled then
        error(typographyReason or "YChat typography restore failed")
    end
    local appearanceActive = type(self.Appearance) == "table"
        and (
            self.Appearance.enabled == true
            or (self.Appearance.restorePending or 0) > 0
        )
    if appearanceActive then
        local appearanceDisabled, appearanceReason =
            InvokeAppearance("SetEnabled", false, "lifecycle-disable")
        if not appearanceDisabled then
            self.lifecycleDisablePending = true
            self.sessionEnabled = false
            self.productionPendingReason = appearanceReason
            return true
        end
    end
    if channelRestorePending then return true end

    local disabled, reason = InvokeShadow("OnModuleDisable")
    if not disabled then
        if reason == "native-restore-pending" then
            self.lifecycleDisablePending = true
            self.sessionEnabled = false
            return true
        end
        error(reason or "YChat native restore is pending")
    end
    return self:FinalizeRuntimeDisable()
end

function YChat:OnAppearanceRestoreConfirmed()
    if not self.lifecycleDisablePending then return true end
    local channelInput = self.ChannelInput
    if channelInput and channelInput.restorePending == true then
        return true, "channel-input-restore-pending"
    end
    if channelInput and channelInput.GetRuntimeGauges then
        channelInput:GetRuntimeGauges(channelInputGaugeScratch)
        if (channelInputGaugeScratch.arrowModePendingRestores or 0) > 0 then
            return true, "channel-input-restore-pending"
        end
    end
    local appearance = self.Appearance
    if appearance and appearance.GetRuntimeGauges then
        appearance:GetRuntimeGauges(appearanceGaugeScratch)
        if (appearanceGaugeScratch.pendingRestores or 0) > 0 then
            return false, "appearance-restore-pending"
        end
    end

    if self.enableAfterRestore == true then
        return self:ResumeDeferredEnable("appearance-restore-committed")
    end

    local shadowDisabled, shadowReason = InvokeShadow("OnModuleDisable")
    if not shadowDisabled then
        self.productionPendingReason = shadowReason
        if shadowReason == "native-restore-pending" then return true end
        return false, shadowReason
    end
    return self:FinalizeRuntimeDisable()
end

function YChat:OnChannelInputRestoreConfirmed()
    return self:OnAppearanceRestoreConfirmed()
end

function YChat:ApplyRetailTimestamp(source)
    if not RETAIL_PRODUCT or not self.runtimeEnabled or self.lifecycleDisablePending then
        return true
    end
    local shadowOK, shadowReason = InvokeShadow("SetEnabled", true, source or "retail-runtime")
    if not shadowOK then
        self.productionPendingReason = shadowReason
        return true
    end

    local autoInviteOK, autoInviteReason =
        InvokeRuntimeModule("AutoInvite", "SetEnabled", true, source or "retail-runtime")
    local historyOK, historyReason =
        InvokeRuntimeModule("HistoryRuntime", "SetEnabled", true, source or "retail-runtime")
    local typographyOK, typographyReason =
        InvokeRuntimeModule("Typography", "SetEnabled", true, source or "retail-runtime")
    local channelOK, channelReason =
        InvokeRuntimeModule("ChannelInput", "SetEnabled", true, source or "retail-runtime")
    local whisperNameOK, whisperNameReason =
        InvokeRuntimeModule("WhisperNameColor", "SetEnabled", true, source or "retail-runtime")

    local appearanceOK, appearanceReason =
        InvokeAppearance("SetEnabled", true, source or "retail-runtime")
    local appearanceReady = appearanceOK
        and (
            type(self.Appearance) ~= "table"
            or self.Appearance.tooltipAvailable ~= false
        )
    if not appearanceReady then
        self.productionPendingReason = appearanceReason
            or (
                type(self.Appearance) == "table"
                and self.Appearance.tooltipReason
            )
            or "appearance-capability-pending"
    end

    local activeTimestampLayout = self.timestampLayoutAtLoad
        or (self.GetTimestampValue and self:GetTimestampValue("layout"))
        or "column"
    local timestampEnabled
    if activeTimestampLayout == "nativeInline" then
        timestampEnabled = self.timestampEnabledAtLoad == true
    else
        timestampEnabled = self.IsTimestampEnabled and self:IsTimestampEnabled() == true
    end
    local probeOK, probeReason = InvokeShadow(
        "SetPermanentWindowsEnabled",
        timestampEnabled,
        source or "retail-runtime"
    )
    local timestampConfigOK, timestampConfigReason =
        InvokeShadow("RefreshTimestampConfiguration", source or "retail-runtime")
    local safeMessageOK, safeMessageReason =
        InvokeRuntimeModule("SafeMessage", "SetEnabled", true, source or "retail-runtime")
    local itemLinksOK, itemLinksReason = InvokeRuntimeModule("ItemLinks", "SetEnabled", true)
    local allReady = probeOK
        and appearanceReady
        and autoInviteOK
        and historyOK
        and typographyOK
        and channelOK
        and whisperNameOK
        and timestampConfigOK
        and safeMessageOK
        and itemLinksOK
    if allReady then
        self.productionPendingReason = nil
    else
        self.productionPendingReason =
            probeReason
            or appearanceReason
            or autoInviteReason
            or historyReason
            or typographyReason
            or channelReason
            or whisperNameReason
            or timestampConfigReason
            or safeMessageReason
            or itemLinksReason
            or (
                type(self.Appearance) == "table"
                and self.Appearance.tooltipReason
            )
    end
    self:RefreshRuntimeGauges()
    return true
end

function YChat:RetryPendingVisualDomains(reason)
    if not RETAIL_PRODUCT or not self.runtimeEnabled then return true end
    reason = reason or "visual-domain-retry"
    local productionReason = self.productionPendingReason
    local productionReasonIsVisual = false
    local retried = false

    local appearance = self.Appearance
    if appearance and type(appearance.HasPendingVisualRetry) == "function"
        and appearance:HasPendingVisualRetry()
        and type(appearance.RetryPendingVisuals) == "function"
    then
        retried = true
        productionReasonIsVisual = productionReasonIsVisual
            or productionReason == appearance.lastMutationFailure
            or productionReason == appearance.lastReason
        pcall(appearance.RetryPendingVisuals, appearance, reason)
    end

    local typography = self.Typography
    if typography and type(typography.HasPendingVisualRetry) == "function"
        and typography:HasPendingVisualRetry()
        and type(typography.RefreshAll) == "function"
    then
        retried = true
        productionReasonIsVisual = productionReasonIsVisual
            or productionReason == typography.lastFailure
        pcall(typography.RefreshAll, typography, reason)
    end

    local layout = self.MainLayout
    if layout and layout.pending == true
        and type(layout.OnPlayerRegenEnabled) == "function"
    then
        retried = true
        productionReasonIsVisual = productionReasonIsVisual
            or productionReason == layout.lastReason
        pcall(layout.OnPlayerRegenEnabled, layout)
    end

    local combatLog = self.CombatLog
    if combatLog and type(combatLog.HasPendingVisualRetry) == "function"
        and combatLog:HasPendingVisualRetry()
        and type(combatLog.Reconcile) == "function"
    then
        retried = true
        productionReasonIsVisual = productionReasonIsVisual
            or productionReason == combatLog.lastReason
        pcall(combatLog.Reconcile, combatLog)
    end
    if retried then
        local stillPending = appearance
            and type(appearance.HasPendingVisualRetry) == "function"
            and appearance:HasPendingVisualRetry()
        stillPending = stillPending or (
            typography
            and type(typography.HasPendingVisualRetry) == "function"
            and typography:HasPendingVisualRetry()
        )
        stillPending = stillPending or (layout and layout.pending == true)
        stillPending = stillPending or (
            combatLog
            and type(combatLog.HasPendingVisualRetry) == "function"
            and combatLog:HasPendingVisualRetry()
        )
        if not stillPending and productionReasonIsVisual then
            self.productionPendingReason = nil
        end
        self:RefreshRuntimeGauges()
    end
    return true
end

function YChat:OnRestrictionStateChanged(state)
    if not RETAIL_PRODUCT then return true end
    local channelInput = self.ChannelInput
    if channelInput and type(channelInput.OnRestrictionStateChanged) == "function" then
        pcall(channelInput.OnRestrictionStateChanged, channelInput, state)
    end
    local copyViewer = self.CopyViewer
    if copyViewer and type(copyViewer.OnRestrictionStateChanged) == "function" then
        pcall(copyViewer.OnRestrictionStateChanged, copyViewer, state)
    end
    local history = self.HistoryRuntime
    if history and type(history.OnRestrictionStateChanged) == "function" then
        pcall(history.OnRestrictionStateChanged, history, state)
    end
    local elementFade = self.ElementFade
    if elementFade and type(elementFade.OnRestrictionStateChanged) == "function" then
        pcall(elementFade.OnRestrictionStateChanged, elementFade, state)
    end

    if state == "OPEN" and self.lifecycleDisablePending then
        local appearanceDisabled, appearanceReason =
            InvokeAppearance("SetEnabled", false, "restriction-open-disable")
        if not appearanceDisabled then
            self.productionPendingReason = appearanceReason
            return true
        end
        return self:OnAppearanceRestoreConfirmed()
    end

    if state == "UNKNOWN" and self.runtimeEnabled then
        InvokeAppearance("SetMutationPaused", true, "restriction-unknown")
        local layout = self.MainLayout
        if layout and type(layout.OnRestrictionStateChanged) == "function" then
            pcall(layout.OnRestrictionStateChanged, layout, state)
        end
        return true
    end

    if state == "PAUSED" and self.runtimeEnabled then
        InvokeAppearance("SetMutationPaused", false, "restriction-paused-visuals")
        local layout = self.MainLayout
        if layout and type(layout.OnRestrictionStateChanged) == "function" then
            pcall(layout.OnRestrictionStateChanged, layout, state)
        end
        return true
    end

    if state == "OPEN" and self.runtimeEnabled then
        InvokeAppearance("SetMutationPaused", false, "restriction-open")
        local layout = self.MainLayout
        if layout and type(layout.OnRestrictionStateChanged) == "function" then
            pcall(layout.OnRestrictionStateChanged, layout, state)
        end
        self:RetryPendingVisualDomains("restriction-open")
        return self:ApplyRetailTimestamp("restriction-open")
    end
    return true
end

function YChat:OnLifecycleInitialize()
    if RETAIL_PRODUCT and self.EnsureDB then
        self:EnsureDB()
        InvokeRuntimeModule("ChannelInput", "InitializeInputHistory")
        self.timestampLayoutAtLoad = self:GetTimestampValue("layout") or "column"
        self.timestampFormatAtLoad = self:GetTimestampValue("format") or "hms"
        self.timestampColorAtLoad = self:GetTimestampValue("color")
        self.timestampEnabledAtLoad = self:IsTimestampEnabled() == true
    end
    return true
end

function YChat:OnLifecycleProfileChanged()
    if not RETAIL_PRODUCT then return true end
    self.db = nil
    if self.EnsureDB then self:EnsureDB() end
    if self.runtimeEnabled and self.IsEnabled and self:IsEnabled() then
        self:ApplyRetailTimestamp("profile-changed")
    end
    return true
end

function YChat:OnLifecycleConfigChanged(reason)
    if RETAIL_PRODUCT and self.runtimeEnabled then
        self:ApplyRetailTimestamp(reason or "config-changed")
    end
    return true
end

function YChat:SetSessionEnabled(enabled)
    enabled = enabled == true
    local result = false
    local runtime = YUI.Module
    if runtime and type(runtime.SetEnabled) == "function" then
        result = runtime:SetEnabled(self.PRODUCT_ID, enabled) == true
    elseif runtime and enabled and type(runtime.Enable) == "function" then
        self.sessionEnabled = true
        result = runtime:Enable(self.PRODUCT_ID) == true
    elseif runtime and not enabled and type(runtime.Disable) == "function" then
        self.sessionEnabled = false
        result = runtime:Disable(self.PRODUCT_ID) == true
    else
        self.sessionEnabled = enabled
        local ok = pcall(enabled and self.OnLifecycleEnable or self.OnLifecycleDisable, self)
        result = ok
    end

    if enabled and self.enableAfterRestore == true then
        self.sessionEnabled = false
        if not result then return false, "module-lifecycle-failed" end
        return true, "enable-deferred"
    end

    if not enabled and self.lifecycleDisablePending then
        self.sessionEnabled = false
        if not result then return false, "module-lifecycle-failed" end
        return true, "disable-deferred"
    end

    local actual = self.runtimeEnabled == true or self.runtimeBlocked == true
    self.sessionEnabled = actual
    if actual ~= enabled then
        if enabled and runtime and type(runtime.Disable) == "function" then
            pcall(runtime.Disable, runtime, self.PRODUCT_ID)
        end
        return false, "runtime-state-mismatch"
    end
    if not result then return false, "module-lifecycle-failed" end
    return true
end

local function ShadowIsEnabled()
    local shadow = YChat.Shadow
    if type(shadow) ~= "table" then return false end
    if type(shadow.IsEnabled) == "function" then
        local ok, enabled = pcall(shadow.IsEnabled, shadow)
        if ok then return enabled == true end
    end
    return shadow.enabled == true
end

local function ProbeIsEnabled()
    local shadow = YChat.Shadow
    if type(shadow) ~= "table" or type(shadow.IsProbeEnabled) ~= "function" then return false end
    local ok, enabled = pcall(shadow.IsProbeEnabled, shadow)
    return ok and enabled == true
end

function YChat:IsShadowEnabled()
    return ShadowIsEnabled()
end

function YChat:IsProbeEnabled()
    return ProbeIsEnabled()
end

function YChat:SetShadowEnabled(enabled, source)
    enabled = enabled == true
    source = type(source) == "string" and source ~= "" and source or "public"
    if enabled then
        local runtimeWasEnabled = self.runtimeEnabled == true
        local runtimeOK, runtimeReason = self:SetSessionEnabled(true)
        if not runtimeOK then return false, runtimeReason end

        local shadowOK, shadowReason = InvokeShadow("SetEnabled", true, source)
        if not shadowOK then
            if not runtimeWasEnabled then self:SetSessionEnabled(false) end
            return false, shadowReason
        end
        self:RefreshRuntimeGauges()
        return true
    end

    local shadowOK, shadowReason = InvokeShadow("SetEnabled", false, source)
    if not shadowOK then
        self:RefreshRuntimeGauges()
        return false, shadowReason
    end
    local runtimeOK, runtimeReason = self:SetSessionEnabled(false)
    self:RefreshRuntimeGauges()
    if not runtimeOK then return false, runtimeReason end
    return true
end

function YChat:SetProbeEnabled(enabled, source, frameName)
    enabled = enabled == true
    source = type(source) == "string" and source ~= "" and source or "public"
    if not enabled then
        local ok, reason = InvokeShadow("SetProbeEnabled", false, source)
        self:RefreshRuntimeGauges()
        return ok, reason
    end

    local runtimeWasEnabled = self.runtimeEnabled == true
    local shadowWasEnabled = ShadowIsEnabled()
    local shadowOK, shadowReason = self:SetShadowEnabled(true, source)
    if not shadowOK then return false, shadowReason end

    local probeOK, probeReason = InvokeShadow("SetProbeEnabled", true, source, frameName)
    if not probeOK then
        if not shadowWasEnabled then
            local rollbackOK = InvokeShadow("SetEnabled", false)
            if rollbackOK and not runtimeWasEnabled then self:SetSessionEnabled(false) end
        end
        self:RefreshRuntimeGauges()
        return false, probeReason
    end
    self:RefreshRuntimeGauges()
    return true
end

function YChat:RunProbe(argument, source)
    argument = type(argument) == "string" and argument or ""
    local normalized = lower(argument)
    if normalized == "off" then return self:SetProbeEnabled(false, source) end
    if normalized == "toggle" then return self:SetProbeEnabled(not ProbeIsEnabled(), source) end
    if normalized == "" or normalized == "on" then return self:SetProbeEnabled(true, source) end
    return self:SetProbeEnabled(true, source, argument)
end

function YChat:RestoreNative(source)
    source = type(source) == "string" and source ~= "" and source or "native-restore"
    local appearanceOK, appearanceReason = InvokeAppearance("SetEnabled", false, source)
    if not appearanceOK then
        self.lifecycleDisablePending = true
        self.sessionEnabled = false
        self:RefreshRuntimeGauges()
        return false, appearanceReason
    end
    local shadowOK, shadowReason = InvokeShadow("SetEnabled", false, source)
    if not shadowOK then
        self:RefreshRuntimeGauges()
        return false, shadowReason
    end
    local runtimeOK, runtimeReason = self:SetSessionEnabled(false)
    self:RefreshRuntimeGauges()
    if not runtimeOK then return false, runtimeReason end
    return true
end

function YChat:OnShadowRestoreConfirmed()
    local appearanceOK, appearanceReason =
        InvokeAppearance("SetEnabled", false, "shadow-restore-confirmed")
    if not appearanceOK then
        return false, appearanceReason or "appearance-restore-pending"
    end
    local runtime = YUI.Module
    if not self.lifecycleDisablePending then
        if runtime and type(runtime.SetEnabled) == "function" then
            local callOK, disabled = pcall(runtime.SetEnabled, runtime, self.PRODUCT_ID, false)
            if not callOK or disabled ~= true then return false, "module-disable-failed" end
        elseif runtime and type(runtime.Disable) == "function" then
            local callOK, disabled = pcall(runtime.Disable, runtime, self.PRODUCT_ID)
            if not callOK or disabled ~= true then return false, "module-disable-failed" end
        else
            self.lifecycleDisablePending = true
            self.sessionEnabled = false
        end
    end

    if not self.lifecycleDisablePending then
        self.lifecycleDisablePending = true
        self.sessionEnabled = false
    end

    if self.runtimeEnabled then
        local detached = pcall(self.DetachRuntime, self)
        if not detached or self.runtimeEnabled then return false, "runtime-detach-failed" end
    end
    local panel = self.DevPanel
    if panel and type(panel.Hide) == "function" then
        local hidden, result = pcall(panel.Hide, panel)
        if not hidden or result ~= true then return false, "dev-panel-hide-failed" end
    end
    return true
end

function YChat:OnShadowRestoreCommitted()
    self.lifecycleDisablePending = false
    self.sessionEnabled = false
    pcall(self.RefreshRuntimeGauges, self)
    pcall(Print, T("command.restore.done", "The native chat presentation has been restored."))
    if self.enableAfterRestore == true then
        return self:ResumeDeferredEnable("shadow-restore-committed")
    end
    return true
end

function YChat:ResetDiagnostics()
    if self.Stats and self.Stats.ResetCounters then
        self.Stats:ResetCounters()
    elseif self.Stats and self.Stats.Reset then
        self.Stats:Reset()
    end
    self:RefreshRuntimeGauges()
    if self.DevPanel and self.DevPanel.Refresh then self.DevPanel:Refresh() end
    return true
end

function YChat:GetDiagnosticsSnapshot(target)
    self:RefreshRuntimeGauges()
    if self.Stats and self.Stats.GetSnapshot then return self.Stats:GetSnapshot(target) end
    return target or {}
end

local function PrintHelp()
    Print(T("command.help.title", "Stage 0 commands:"))
    Print(T("command.help.help", "/ychat help - show this help"))
    Print(T("command.help.status", "/ychat status - show the current state"))
    Print(T("command.help.shadow", "/ychat shadow on|off|toggle - control shadow mode"))
    Print(T("command.help.probe", "/ychat probe [name] - run a safe probe"))
    Print(T("command.help.restore", "/ychat restore - restore the native chat presentation"))
    Print(T("command.help.fade", "/ychat fade - fade the current chat group now"))
    Print(T("command.help.fade_test", "/ychat fadetest - fade and print the final visual state"))
    Print(T("command.help.report", "/ychat report - print the validation summary"))
    Print(T("command.help.panel", "/ychat panel - toggle the developer validation panel"))
    Print(T("command.help.reset", "/ychat reset - reset validation counters"))
end

local function PrintAppearanceStatus(stats)
    if not (stats and stats.Get) then return end
    local appearanceState = stats:Get("appearanceEnabled")
        and T("command.state.enabled", "enabled")
        or T("command.state.disabled", "disabled")
    Print(format(
        T(
            "command.status.appearance",
            "appearance=%s, mutationPaused=%s, refreshPending=%s, lastFailure=%s/%s"
        ),
        appearanceState,
        tostring(stats:Get("appearanceMutationPaused") == true),
        tostring(stats:Get("appearanceRefreshPending") == true),
        tostring(stats:Get("appearanceLastFailureDomain") or "none"),
        tostring(stats:Get("appearanceLastFailure") or "none")
    ))
end

local function PrintStatus()
    YChat:RefreshRuntimeGauges()
    local runtimeState = YChat.runtimeEnabled
        and T("command.state.enabled", "enabled")
        or T("command.state.disabled", "disabled")
    local shadowState = ShadowIsEnabled()
        and T("command.state.enabled", "enabled")
        or T("command.state.disabled", "disabled")
    local probeState = ProbeIsEnabled()
        and T("command.state.enabled", "enabled")
        or T("command.state.disabled", "disabled")
    local restriction = YChat.Adapter and YChat.Adapter.GetRestrictionState
        and YChat.Adapter:GetRestrictionState()
        or "UNKNOWN"
    Print(format(T("command.status", "module=%s, shadow=%s, probe=%s, restriction=%s"), runtimeState, shadowState, probeState, restriction))

    local stats = YChat.Stats
    if stats and stats.Get then
        Print(format(
            T("command.status.stats", "comparisons=%d, mismatches=%d, quality=%s"),
            tonumber(stats:Get("shadowComparisons")) or 0,
            tonumber(stats:Get("shadowMismatches")) or 0,
            tostring(stats:Get("qualityState") or "Q3")
        ))
        PrintAppearanceStatus(stats)
    end
end

local function HandleShadow(argument)
    argument = lower(argument or "")
    if argument == "" or argument == "status" then
        Print(ShadowIsEnabled()
            and T("command.shadow.enabled", "Shadow mode is enabled.")
            or T("command.shadow.disabled", "Shadow mode is disabled."))
        return
    end

    local enabled
    if argument == "on" then
        enabled = true
    elseif argument == "off" then
        enabled = false
    elseif argument == "toggle" then
        enabled = not ShadowIsEnabled()
    else
        Print(T("command.shadow.usage", "Usage: /ychat shadow on|off|toggle"))
        return
    end

    local ok, reason = YChat:SetShadowEnabled(enabled, "command")
    if ok then
        Print(enabled
            and T("command.shadow.enabled", "Shadow mode is enabled.")
            or T("command.shadow.disabled", "Shadow mode is disabled."))
    else
        PrintOperationFailure(reason)
    end
end

local function HandleProbe(argument)
    local ok, reason = YChat:RunProbe(argument ~= "" and argument or nil, "command")
    if ok then
        Print(T("command.probe.started", "The safe probe has completed or is running."))
    else
        PrintOperationFailure(reason)
    end
end

local function HandleRestore()
    local ok, reason = YChat:RestoreNative("command")
    if ok then
        Print(T("command.restore.done", "The native chat presentation has been restored."))
    else
        PrintOperationFailure(reason)
    end
end

local function BuildFallbackReport()
    local stats = YChat.Stats
    if not (stats and stats.Get) then
        return T("command.report.empty", "No validation data is available yet.")
    end
    return format(
        T("command.report.summary", "comparisons=%d mismatches=%d bypasses=%d quality=%s cleanupLeaks=%d"),
        tonumber(stats:Get("shadowComparisons")) or 0,
        tonumber(stats:Get("shadowMismatches")) or 0,
        tonumber(stats:Get("secretBypasses")) or 0,
        tostring(stats:Get("qualityState") or "Q3"),
        tonumber(stats:Get("cleanupLeaks")) or 0
    )
end

local function HandleReport()
    local shadow = YChat.Shadow
    if shadow and type(shadow.BuildReport) == "function" then
        CallShadow("BuildReport")
    else
        Print(BuildFallbackReport())
    end
    YChat:RefreshRuntimeGauges()
    PrintAppearanceStatus(YChat.Stats)
end

local function HandlePanel()
    local panel = YChat.DevPanel
    if not panel or type(panel.Toggle) ~= "function" then
        Print(T("command.panel.unavailable", "The developer panel is unavailable."))
        return
    end
    local ok, result, detail = pcall(panel.Toggle, panel)
    if not ok or result == false then
        Print(format(T("command.failed", "Operation failed: %s"), tostring(detail or result)))
    end
end

local function HandleReset()
    local ok, reason = YChat:ResetDiagnostics("command")
    if ok then
        Print(T("command.reset.done", "Validation counters have been reset."))
    else
        Print(format(T("command.failed", "Operation failed: %s"), tostring(reason or "unknown")))
    end
end

local function HandleFade()
    local elementFade = YChat.ElementFade
    if not elementFade or type(elementFade.RequestHide) ~= "function" then
        Print(T("command.fade.unavailable", "Chat fading is not currently available."))
        return
    end
    local ok = elementFade:RequestHide(
        _G.ChatFrame1,
        "element-fade-command",
        true
    )
    if not ok then
        Print(T("command.fade.unavailable", "Chat fading is not currently available."))
    end
end

local function ReadDiagnosticAlpha(object)
    if not object or type(object.GetAlpha) ~= "function" then return -1 end
    local ok, value = pcall(object.GetAlpha, object)
    if not ok or type(value) ~= "number" then return -1 end
    return value
end

local function PrintFadeTestResult()
    local elementFade = YChat.ElementFade
    local main = _G.ChatFrame1
    local combat = _G.ChatFrame2
    local combatTab = _G.ChatFrame2Tab
    local combatTitle = combatTab and combatTab.Text
    local mainHidden = elementFade and elementFade:IsFrameHidden(main) == true
    local combatHidden = elementFade and elementFade:IsFrameHidden(combat) == true
    local visibility = elementFade and elementFade:GetFrameVisibility(main) or -1
    Print(format(
        T(
            "command.fade_test.result",
            "mainHidden=%s combatHidden=%s visibility=%.3f combatTab=%.3f combatTitle=%.3f"
        ),
        tostring(mainHidden),
        tostring(combatHidden),
        tonumber(visibility) or -1,
        ReadDiagnosticAlpha(combatTab),
        ReadDiagnosticAlpha(combatTitle)
    ))
end

local function HandleFadeTest()
    local elementFade = YChat.ElementFade
    if not elementFade or type(elementFade.RequestHide) ~= "function" then
        Print(T("command.fade.unavailable", "Chat fading is not currently available."))
        return
    end
    local ok = elementFade:RequestHide(
        _G.ChatFrame1,
        "element-fade-test-command",
        true,
        PrintFadeTestResult
    )
    if not ok then
        Print(T("command.fade.unavailable", "Chat fading is not currently available."))
    end
end

function YChat:HandleSlash(message)
    message = type(message) == "string" and message or ""
    local command, argument = match(message, "^(%S*)%s*(.-)%s*$")
    command = lower(command or "")
    argument = argument or ""

    if command == "" or command == "help" then
        PrintHelp()
    elseif command == "status" then
        PrintStatus()
    elseif command == "shadow" then
        HandleShadow(argument)
    elseif command == "probe" then
        HandleProbe(argument)
    elseif command == "restore" then
        HandleRestore()
    elseif command == "fade" then
        HandleFade()
    elseif command == "fadetest" then
        HandleFadeTest()
    elseif command == "report" then
        HandleReport()
    elseif command == "panel" then
        HandlePanel()
    elseif command == "reset" then
        HandleReset()
    else
        Print(T("command.unknown", "Unknown command. Use /ychat help."))
    end
end

if YUI.Commands and YUI.Commands.Register then
    YUI.Commands:Register({
        id = "ychat",
        productId = YUI.CoreMode == "suite" and "suite" or YChat.PRODUCT_ID,
        aliases = { "/ychat" },
        handler = function(message)
            YChat:HandleSlash(message)
        end,
    })
end

if YUI.RegisterProduct then
    YUI:RegisterProduct({
        id = YChat.PRODUCT_ID,
        title = "YChat",
        titleKey = "product.title",
        titleNamespace = "YChat",
        shortTitle = "YChat",
        shortTitleKey = "product.short_title",
        shortTitleNamespace = "YChat",
        notes = "Chat window enhancement and appearance",
        notesKey = "product.notes",
        notesNamespace = "YChat",
        author = "阿言",
        addonName = ADDON_NAME or YUI.AddonName,
        settingsScope = "ychat",
        settings = {
            enabled = RETAIL_PRODUCT,
            entry = RETAIL_PRODUCT and YChat.SETTINGS_ENTRY or nil,
            commonPages = RETAIL_PRODUCT and { "core.profiles", "core.about" } or {},
            minimapIcon = false,
        },
        db = {
            enabled = RETAIL_PRODUCT,
            savedVariable = RETAIL_PRODUCT and "YUI_DB" or nil,
            storageKey = RETAIL_PRODUCT and YChat.STORAGE_KEY or nil,
        },
    })
end

if YUI.Module and YUI.Module.Register then
    YUI.Module:Register({
        id = YChat.PRODUCT_ID,
        name = "YChat",
        product = YChat.PRODUCT_ID,
        scope = "ychat",
        defaultEnabled = false,
        owner = YChat,
        dependencies = RETAIL_PRODUCT
            and { "core.db", "core.locale", "core.api", "gui", "settings" }
            or { "core.locale", "core.api" },
        getEnabled = function(owner)
            if RETAIL_PRODUCT and owner.IsEnabled then return owner:IsEnabled() end
            return owner.sessionEnabled == true
        end,
        setEnabled = function(owner, enabled)
            enabled = enabled == true
            local shadow = owner.Shadow
            local pendingRestore = enabled
                and (
                    owner.lifecycleDisablePending
                    or (type(shadow) == "table" and shadow.stopAfterRestore == true)
                )
            local persisted
            if RETAIL_PRODUCT and owner.SetEnabled then
                persisted = owner:SetEnabled(enabled, true)
            else
                owner.sessionEnabled = enabled
                persisted = true
            end
            if pendingRestore then
                owner.enableAfterRestore = true
                owner.sessionEnabled = false
            elseif not enabled then
                owner.enableAfterRestore = false
            end
            return persisted
        end,
        OnInitialize = "OnLifecycleInitialize",
        OnEnable = "OnLifecycleEnable",
        OnDisable = "OnLifecycleDisable",
        OnProfileChanged = "OnLifecycleProfileChanged",
        OnConfigChanged = "OnLifecycleConfigChanged",
    })
end

if YUI.Event and YUI.Event.On then
    YUI.Event:On("YUI_EXTERNAL_STATE_CHANGED", function()
        if not (YChat.runtimeEnabled or YChat.externalConflict) then return end
        local conflict = YChat.ConflictGuard and YChat.ConflictGuard:Check()
        if type(conflict) ~= "table" then return end
        if conflict.blocked == true then
            if not YChat.externalConflict or YChat.externalConflict.controller ~= conflict.controller then
                YChat:YieldToExternalChatController(conflict)
            end
        elseif YChat.externalConflict then
            YChat:OnLifecycleEnable()
        end
    end, YChat, { moduleId = "ychat", traceName = "YChat:ExternalStateChanged" })
end

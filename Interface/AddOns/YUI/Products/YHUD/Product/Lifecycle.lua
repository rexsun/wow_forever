local ADDON_NAME = ...
local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

YHUD.name = "Halo"
YHUD.contextRefreshStats = YHUD.contextRefreshStats or {
    requests = 0,
    coalesced = 0,
    executions = 0,
    elapsedMS = 0,
    configApplyMS = 0,
    profileMS = 0,
    reconcileMS = 0,
    viewMS = 0,
    layoutMS = 0,
    nativeBridgeMS = 0,
    sourcesMS = 0,
    refreshMS = 0,
}
YHUD.contextRefreshStats.configApplyMS =
    YHUD.contextRefreshStats.configApplyMS or 0
YHUD.contextRefreshStats.profileMS =
    YHUD.contextRefreshStats.profileMS or 0
YHUD.contextRefreshStats.reconcileMS =
    YHUD.contextRefreshStats.reconcileMS or 0
YHUD.contextRefreshStats.viewMS =
    YHUD.contextRefreshStats.viewMS or 0
YHUD.contextRefreshStats.layoutMS =
    YHUD.contextRefreshStats.layoutMS or 0
YHUD.contextRefreshStats.nativeBridgeMS =
    YHUD.contextRefreshStats.nativeBridgeMS or 0
YHUD.contextRefreshStats.sourcesMS =
    YHUD.contextRefreshStats.sourcesMS or 0
YHUD.contextRefreshStats.refreshMS =
    YHUD.contextRefreshStats.refreshMS or 0
YHUD.performanceDiagnosticsEnabled =
    YHUD.performanceDiagnosticsEnabled == true

local CONTEXT_REFRESH_DELAY = 0
local SPECIALIZATION_RETRY_DELAY = 0.05
local SPECIALIZATION_RETRY_LIMIT = 10
local STARTUP_RETRY_DELAYS = { 0, 0.05, 0.1, 0.25, 0.5, 1, 2 }

local function ContextRefreshTimerCallback()
    local watchdog = YUI.CPUWatchdog
    if watchdog and watchdog.autoCapture then
        return watchdog:MeasureTargetTask("yhud.context-timer", YHUD.RunPendingContextRefresh, YHUD)
    end
    if watchdog and watchdog.sceneCapture then
        return watchdog:MeasureSceneTask("yhud.context-timer", YHUD.RunPendingContextRefresh, YHUD)
    end
    YHUD:RunPendingContextRefresh()
end

function YHUD:SetPerformanceDiagnosticsEnabled(enabled)
    self.performanceDiagnosticsEnabled = enabled == true
    return self.performanceDiagnosticsEnabled
end

function YHUD:IsPerformanceDiagnosticsEnabled()
    return self.performanceDiagnosticsEnabled == true
end

local function ProfileNowMS()
    if YHUD.performanceDiagnosticsEnabled ~= true then return nil end
    if type(debugprofilestop) ~= "function" then return nil end
    local ok, value = pcall(debugprofilestop)
    return ok and type(value) == "number" and value or nil
end

local function RecordStageElapsed(stats, field, startedAt)
    if not (stats and field and startedAt) then return end
    local finishedAt = ProfileNowMS()
    if finishedAt then
        stats[field] = (stats[field] or 0)
            + math.max(0, finishedAt - startedAt)
    end
end

local function RecordLifecycleDiagnostic(name, detail)
    local diagnostics = YHUD.Diagnostics
    if diagnostics and type(diagnostics.Record) == "function" then
        diagnostics:Record(name, detail)
    end
end

local function GetCachedLifecycleRuntimeProfile(canonical, specKey)
    local revision = tonumber(YHUD.runtimeProfileRevision) or 0
    if YHUD._runtimeProfile
        and YHUD._runtimeProfileCanonical == canonical
        and YHUD._runtimeProfileSpecKey == specKey
        and YHUD._runtimeProfileRevision == revision then
        return YHUD._runtimeProfile
    end
    return nil
end

local initialSpecializationRecoveryOwner =
    YHUD.initialSpecializationRecoveryOwner or {}
YHUD.initialSpecializationRecoveryOwner =
    initialSpecializationRecoveryOwner
YHUD.startupRecoveryOwner = initialSpecializationRecoveryOwner

function initialSpecializationRecoveryOwner:OnContextChanged(eventName, unit)
    if eventName == "PLAYER_SPECIALIZATION_CHANGED"
        and unit ~= nil and unit ~= "player" then
        return false
    end
    if not YHUD:IsEnabled() then return false end
    if eventName == "YUI_WORLD_READY" then
        YHUD.startupWorldReady = true
    end
    if YHUD.runtimeMode ~= nil then
        return YHUD:RequestContextRefresh(
            "specialization-recovery"
        )
    end
    return YHUD:RequestStartupRecovery(eventName)
end

local function RegisterInitialSpecializationRecovery()
    local owner = initialSpecializationRecoveryOwner
    if owner.registered == true then return true end
    local event = YUI.Event
    if not (event and type(event.On) == "function") then return false end
    event:On(
        "PLAYER_SPECIALIZATION_CHANGED",
        "OnContextChanged",
        owner,
        {
            unit = "player",
            moduleId = YHUD.PRODUCT_ID,
            traceName = "YHUD.InitialSpecializationRecovery",
        }
    )
    event:On(
        "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
        "OnContextChanged",
        owner,
        {
            moduleId = YHUD.PRODUCT_ID,
            traceName = "YHUD.InitialSpecializationRecovery",
        }
    )
    for _, eventName in ipairs({
        "YUI_WORLD_READY",
        "TRAIT_CONFIG_UPDATED",
        "ACTIVE_COMBAT_CONFIG_CHANGED",
    }) do
        event:On(
            eventName,
            "OnContextChanged",
            owner,
            {
                moduleId = YHUD.PRODUCT_ID,
                traceName = "YHUD.SpecializationRecovery",
            }
        )
    end
    owner.registered = true
    return true
end

local function UnregisterInitialSpecializationRecovery()
    local owner = initialSpecializationRecoveryOwner
    if owner.registered ~= true then return false end
    if YUI.Event and type(YUI.Event.OffOwner) == "function" then
        YUI.Event:OffOwner(owner)
    end
    owner.registered = false
    return true
end

local function CanUseInitialResourceMode()
    return (YHUD.runtimeMode == "resource-only"
            or YHUD.startupAllowResourceOnly == true)
        and YHUD:IsInitialSpecialization()
end

local function IsWorldReady()
    if YHUD.startupWorldReady == true then return true end
    local lifecycle = YUI.Lifecycle
    return lifecycle and type(lifecycle.IsReady) == "function"
        and lifecycle:IsReady("YUI_WORLD_READY") == true
end

local function StartupRetryTimerCallback()
    local generation = YHUD.startupRetryTimerGeneration
    YHUD.startupRetryTimer = nil
    YHUD.startupRetryTimerGeneration = nil
    if generation ~= YHUD.startupGeneration then return false end
    local watchdog = YUI.CPUWatchdog
    if watchdog and watchdog.sceneCapture then
        return watchdog:MeasureSceneTask("yhud.startup-retry", YHUD.TryActivateRuntime, YHUD, "startup-retry")
    end
    return YHUD:TryActivateRuntime("startup-retry")
end

function YHUD:CancelStartupRecoveryTimer()
    if self.startupRetryTimer and self.startupRetryTimer.Cancel then
        self.startupRetryTimer:Cancel()
    end
    self.startupRetryTimer = nil
    self.startupRetryTimerGeneration = nil
end

function YHUD:ScheduleStartupRecovery(reason, reset)
    if not self:IsEnabled() or self.runtimeMode ~= nil then return false end
    if self.startupRetryTimer then return true end
    if reset == true or type(self.startupRetryIndex) ~= "number" then
        self.startupRetryIndex = 1
    end
    local retryIndex = self.startupRetryIndex
    local delay = STARTUP_RETRY_DELAYS[retryIndex]
    if delay == nil then return false end
    self.startupRetryIndex = retryIndex + 1
    self.startupPendingReason = reason or self.startupPendingReason
        or "startup-recovery"
    if C_Timer and C_Timer.NewTimer then
        self.startupRetryTimerGeneration = self.startupGeneration
        local watchdog = YUI.CPUWatchdog
        if watchdog and watchdog.sceneCapture then watchdog:SceneTaskScheduled("yhud.startup-retry") end
        self.startupRetryTimer = C_Timer.NewTimer(
            delay,
            StartupRetryTimerCallback
        )
        return true
    end
    if delay == 0 then return self:TryActivateRuntime(reason) end
    return false
end

function YHUD:RequestStartupRecovery(reason)
    if not self:IsEnabled() then return false end
    if self.runtimeMode ~= nil then
        return self:RequestContextRefresh(reason or "startup-recovery")
    end
    self.startupRecoveryPending = true
    self.startupPendingReason = reason or self.startupPendingReason
        or "startup-recovery"
    return self:ScheduleStartupRecovery(
        self.startupPendingReason,
        self.startupRetryTimer == nil
    )
end

local function BuildLifecycleRuntimeProfile(profile, specKey)
    local canonical = YHUD:GetCanonicalProfile(profile)
    if type(canonical) ~= "table" then
        return nil, "invalid-profile"
    end
    if not YHUD:IsStableSpecKey(specKey) then
        if CanUseInitialResourceMode() then
            return YHUD:CreateInitialResourceProfile(canonical), {
                changed = false,
                resourceOnly = true,
            }
        end
        return nil, "invalid-spec-key"
    end
    local configSets = YHUD.ConfigSets
    if not (configSets
        and type(configSets.MaterializeProfile) == "function") then
        return nil, "config-materialize-unavailable"
    end

    local revision = tonumber(YHUD.runtimeProfileRevision) or 0
    local materialized, report, _, preparedRuntime =
        configSets:MaterializeProfile(
        canonical,
        specKey,
        false,
        { traceStages = true }
    )
    if not materialized then return nil, report end
    local scoped = preparedRuntime
    local code
    if type(scoped) ~= "table"
        or rawget(scoped, "_yhudCanonical") ~= materialized
        or rawget(scoped, "_yhudSpecKey") ~= specKey then
        scoped, code = YHUD:GetScopedProfile(materialized, specKey, true)
    end
    if not scoped then return nil, code end
    if revision ~= (tonumber(YHUD.runtimeProfileRevision) or 0)
        or specKey ~= YHUD:GetCurrentSpecKey() then
        return nil, "runtime-profile-stale"
    end

    YHUD._runtimeProfile = scoped
    YHUD._runtimeProfileCanonical = canonical
    YHUD._runtimeProfileSpecKey = specKey
    YHUD._runtimeProfileRevision = revision
    local stats = YHUD.profileCacheStats
    if stats then stats.misses = (stats.misses or 0) + 1 end
    return scoped, report
end

local function ApplyRuntimeMode(profile)
    local resourceOnly = type(profile) == "table"
        and profile._yhudInitialResourceOnly == true
    local nextMode = resourceOnly and "resource-only" or "full"
    if YHUD.runtimeMode == nextMode then return nextMode end
    if resourceOnly and YHUD.runtimeMode == "full" then
        return nil, "specialization-transition"
    end

    if YHUD.BlizzardSettings and YHUD.BlizzardSettings.Sync then
        YHUD.BlizzardSettings:Sync(
            profile,
            resourceOnly,
            "runtime-mode"
        )
    end

    if resourceOnly then
        if YHUD.KeybindText and YHUD.KeybindText.Disable then
            YHUD.KeybindText:Disable()
        end
        if YHUD.KeybindResolver and YHUD.KeybindResolver.Disable then
            YHUD.KeybindResolver:Disable()
        end
        if YHUD.NativeBridge and YHUD.NativeBridge.Disable then
            YHUD.NativeBridge:Disable()
        end
        if YHUD.CDMCatalog and YHUD.CDMCatalog.UnregisterCallbacks then
            YHUD.CDMCatalog:UnregisterCallbacks()
        end
        if YHUD.Sources and YHUD.Sources.Disable then
            YHUD.Sources:Disable()
            if YHUD.Sources.EnableResourceOnly then
                YHUD.Sources:EnableResourceOnly(profile)
            elseif YHUD.Sources.Enable then
                YHUD.Sources:Enable(profile)
            end
        end
    else
        if YHUD.KeybindResolver and YHUD.KeybindResolver.Enable then
            YHUD.KeybindResolver:Enable()
        end
        if YHUD.NativeBridge and YHUD.NativeBridge.PrepareOfficialRuntime then
            YHUD.NativeBridge:PrepareOfficialRuntime()
        end
        if YHUD.NativeBridge and YHUD.NativeBridge.Enable then
            YHUD.NativeBridge:Enable(profile)
        end
        if YHUD.KeybindText and YHUD.KeybindText.Enable then
            YHUD.KeybindText:Enable()
        end
        if YHUD.CDMCatalog and YHUD.CDMCatalog.RegisterCallbacks then
            YHUD.CDMCatalog:RegisterCallbacks()
        end
        if YHUD.Sources and YHUD.Sources.Disable and YHUD.Sources.Enable then
            YHUD.Sources:Disable()
            YHUD.Sources:Enable(profile)
        end
    end
    YHUD.runtimeMode = nextMode
    if resourceOnly then
        RegisterInitialSpecializationRecovery()
    else
        UnregisterInitialSpecializationRecovery()
    end
    return nextMode
end

local function PreserveDesignerContext(specKey, reason)
    local Designer = YHUD.Designer
    if not (Designer and Designer.IsOpen and Designer:IsOpen()) then
        return nil
    end
    if type(Designer.OnRuntimeSpecChanged) ~= "function"
        or type(Designer.GetSession) ~= "function" then
        return nil
    end
    local changed, code = Designer:OnRuntimeSpecChanged(specKey, reason)
    if changed == nil then
        if YHUD.Diagnostics and type(YHUD.Diagnostics.Record) == "function" then
            YHUD.Diagnostics:Record("designer-context", code)
        end
        return nil
    end
    return Designer:GetSession()
end

local function NotifyDesignerRuntimeApplied(session, specKey, reason, refreshed)
    if not session then return end
    session.runtimeContextApplied = refreshed == true
    session.runtimeContextAppliedSpecKey = specKey
    session.uiRefreshPending = true

    local DesignerUI = YHUD.DesignerUI
    if DesignerUI and DesignerUI.active == true then
        DesignerUI.previewRuntimeDirty = false
        if type(DesignerUI.OnRuntimeContextChanged) == "function" then
            DesignerUI:OnRuntimeContextChanged({
                reason = reason,
                runtimeSpecKey = specKey,
                viewSpecKey = session.viewSpecKey,
                staticPreview = session.staticPreview == true,
                refreshed = refreshed == true,
            })
            session.uiRefreshPending = false
        end
    end

    if YUI.Event and type(YUI.Event.Emit) == "function" then
        YUI.Event:Emit("YHUD_DESIGNER_RUNTIME_CONTEXT_REFRESHED", {
            reason = reason,
            runtimeSpecKey = specKey,
            viewSpecKey = session.viewSpecKey,
            staticPreview = session.staticPreview == true,
            refreshed = refreshed == true,
        })
    end
end

function YHUD:IsEnabled()
    local db = self:GetDB()
    return db and (self.IS_STANDALONE or db.enabled == true)
end

function YHUD:SetEnabled(enabled, fromLifecycle)
    if self.IS_STANDALONE and enabled ~= true then return false end
    local db = self:GetDB()
    if not db then return false end
    enabled = enabled == true
    db.enabled = enabled
    if not fromLifecycle and YUI.Module and YUI.Module.SetEnabled then
        return YUI.Module:SetEnabled(self.PRODUCT_ID, enabled)
    end
    return true
end

function YHUD:Initialize()
    local db = self:EnsureDB()
    self:LoadConsolePreferences()
    if self.BlizzardSettings and self.BlizzardSettings.Initialize then
        self.BlizzardSettings:Initialize(db and db.enabled == true)
    end
    if self.ConfigSets then
        self.ConfigSets:RegisterProvider()
        self.ConfigSets:EnsureDefaultUserSet()
    end
    return true
end

function YHUD:Refresh(reason, preparedCanonical, preparedSpecKey, stageStats)
    local specKey = preparedSpecKey or self:GetCurrentSpecKey()
    local canonical = preparedCanonical or self:GetConfigProfile()
    if not canonical then return false end
    if self.runtimeMode == "full"
        and type(canonical) == "table"
        and canonical._yhudInitialResourceOnly == true then
        return nil, "specialization-transition"
    end
    local profile, profileCode
    if type(canonical) == "table"
        and canonical._yhudInitialResourceOnly == true then
        profile = canonical
    elseif canonical == self._runtimeProfile
        and rawget(canonical, "_yhudSpecKey") == specKey then
        profile = canonical
    elseif self:IsStableSpecKey(specKey) then
        profile, profileCode = self:GetRuntimeProfile(canonical, specKey, true)
    elseif CanUseInitialResourceMode() then
        profile, profileCode = self:CreateInitialResourceProfile(canonical)
    else
        return false
    end
    if not profile then return nil, profileCode end
    local resourceOnly = profile._yhudInitialResourceOnly == true
    if self.BlizzardSettings and self.BlizzardSettings.Sync then
        self.BlizzardSettings:Sync(
            profile,
            resourceOnly,
            reason or "yhud-refresh"
        )
    end
    if self.View and self.View.active then
        local startedAt = stageStats and ProfileNowMS()
        self.View:ApplyConfig(profile)
        RecordStageElapsed(stageStats, "viewMS", startedAt)
    end
    if self.Skyriding and self.Skyriding.active
        and self.Skyriding.ApplySettings then
        local ok, err = pcall(
            self.Skyriding.ApplySettings,
            self.Skyriding,
            profile
        )
        if not ok and self.Skyriding.HandleRuntimeFailure then
            self.Skyriding:HandleRuntimeFailure(
                "settings-refresh",
                err
            )
        end
    end
    if self.LayoutBridge and self.View and self.View.active then
        local startedAt = stageStats and ProfileNowMS()
        self.LayoutBridge:Sync(profile)
        RecordStageElapsed(stageStats, "layoutMS", startedAt)
    end
    if not resourceOnly and self.NativeBridge and self.View and self.View.active then
        local startedAt = stageStats and ProfileNowMS()
        self.NativeBridge:Sync(profile, reason or "yhud-refresh")
        RecordStageElapsed(stageStats, "nativeBridgeMS", startedAt)
    end
    if self.Sources and self.Sources.active then
        local startedAt = stageStats and ProfileNowMS()
        self.Sources:ApplyConfig(profile)
        self.Sources:Refresh(reason or "yhud-refresh", true)
        RecordStageElapsed(stageStats, "sourcesMS", startedAt)
    end
    return true
end

function YHUD:CancelPendingContextRefresh()
    if self.pendingContextTimer and self.pendingContextTimer.Cancel then
        self.pendingContextTimer:Cancel()
    end
    self.pendingContextTimer = nil
    self.pendingContextReason = nil
    self.pendingContextCombat = false
    self.pendingContextCatalogMaterialized = nil
    self.pendingContextSpecializationRetries = 0
    self.pendingContextImmediate = nil
end

function YHUD:RequestContextRefresh(reason, options)
    options = type(options) == "table" and options or {}
    local immediate = options.immediate == true
    if immediate then
        local configRuntime = YUI.Settings
            and YUI.Settings.ConfigSetRuntime
        if self.pendingContextReason ~= nil
            or self.pendingContextTimer ~= nil
            or self.pendingContextCombat == true
            or (configRuntime and configRuntime._contextTimer) then
            return nil, "context-refresh-busy"
        end
        if InCombatLockdown and InCombatLockdown() then
            return nil, "context-refresh-combat"
        end
    end
    local stats = self.contextRefreshStats
    stats.requests = stats.requests + 1
    local catalogMaterialized = options.catalogMaterialized == true
    if self.pendingContextReason == nil then
        self.pendingContextCatalogMaterialized = catalogMaterialized
        self.pendingContextSpecializationRetries = 0
    elseif not catalogMaterialized then
        self.pendingContextCatalogMaterialized = false
    end
    self.pendingContextReason = self.pendingContextReason
        or reason or "context-changed"
    self.pendingContextImmediate = immediate or nil
    if immediate then
        return self:RunPendingContextRefresh()
    end
    if InCombatLockdown and InCombatLockdown() then
        if self.pendingContextTimer or self.pendingContextCombat then
            stats.coalesced = stats.coalesced + 1
        end
        if self.pendingContextTimer and self.pendingContextTimer.Cancel then
            self.pendingContextTimer:Cancel()
        end
        self.pendingContextTimer = nil
        self.pendingContextCombat = true
        return true
    end
    if self.pendingContextTimer then
        stats.coalesced = stats.coalesced + 1
        return true
    end
    self.pendingContextCombat = false
    if C_Timer and C_Timer.NewTimer then
        local watchdog = YUI.CPUWatchdog
        if watchdog and watchdog.sceneCapture then watchdog:SceneTaskScheduled("yhud.context-timer") end
        self.pendingContextTimer = C_Timer.NewTimer(
            CONTEXT_REFRESH_DELAY,
            ContextRefreshTimerCallback
        )
        return true
    end
    return self:RunPendingContextRefresh()
end

function YHUD:RunPendingContextRefresh()
    self.pendingContextTimer = nil
    local immediate = self.pendingContextImmediate == true
    if not self:IsEnabled() then
        self.pendingContextReason = nil
        self.pendingContextCombat = false
        self.pendingContextCatalogMaterialized = nil
        self.pendingContextImmediate = nil
        return false
    end
    local configRuntime = YUI.Settings
        and YUI.Settings.ConfigSetRuntime
    if configRuntime and configRuntime._contextTimer
        and C_Timer and C_Timer.NewTimer then
        self.contextRefreshStats.coalesced =
            self.contextRefreshStats.coalesced + 1
        local watchdog = YUI.CPUWatchdog
        if watchdog and watchdog.sceneCapture then watchdog:SceneTaskScheduled("yhud.context-timer") end
        self.pendingContextTimer = C_Timer.NewTimer(
            0.01,
            ContextRefreshTimerCallback
        )
        return true
    end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingContextCombat = true
        return false
    end
    local specKey = self:GetCurrentSpecKey()
    if not self:IsStableSpecKey(specKey)
        and not CanUseInitialResourceMode() then
        self.pendingContextCombat = false
        if immediate then
            self.pendingContextReason = nil
            self.pendingContextCatalogMaterialized = nil
            self.pendingContextSpecializationRetries = 0
            self.pendingContextImmediate = nil
            return nil, "invalid-spec-key"
        end
        if self.runtimeMode == "full" then
            RecordLifecycleDiagnostic(
                "context-specialization-transition",
                self.pendingContextReason or "context-changed"
            )
            local retryCount = tonumber(
                self.pendingContextSpecializationRetries
            ) or 0
            if retryCount < SPECIALIZATION_RETRY_LIMIT
                and C_Timer and C_Timer.NewTimer then
                self.pendingContextSpecializationRetries =
                    retryCount + 1
                local watchdog = YUI.CPUWatchdog
                if watchdog and watchdog.sceneCapture then watchdog:SceneTaskScheduled("yhud.context-timer") end
                self.pendingContextTimer = C_Timer.NewTimer(
                    SPECIALIZATION_RETRY_DELAY,
                    ContextRefreshTimerCallback
                )
                return true
            end
        end
        return false
    end
    local reason = self.pendingContextReason or "context-changed"
    local catalogMaterialized =
        self.pendingContextCatalogMaterialized == true
    self.pendingContextReason = nil
    self.pendingContextCombat = false
    self.pendingContextCatalogMaterialized = nil
    self.pendingContextSpecializationRetries = 0
    self.pendingContextImmediate = nil
    local startedAt = ProfileNowMS()
    local stats = self.contextRefreshStats
    stats.executions = stats.executions + 1

    if self.NativeBridge and self.NativeBridge.CancelPendingCategorySync then
        self.NativeBridge:CancelPendingCategorySync(true)
    end
    if self.CDMCatalog and self.CDMCatalog.CancelPendingReconcile then
        self.CDMCatalog:CancelPendingReconcile()
    end
    local cooldownViewer = YUI.API and YUI.API.CooldownViewer
    if cooldownViewer and cooldownViewer.InvalidateAuraStackSources then
        cooldownViewer:InvalidateAuraStackSources()
    end
    if self.SpecialResources and self.SpecialResources.OnPlayerStateReset then
        self.SpecialResources:OnPlayerStateReset()
    end
    local designerSession = PreserveDesignerContext(specKey, reason)

    local profileStartedAt = ProfileNowMS()
    local canonical = self:GetConfigProfile()
    local profileFinishedAt = ProfileNowMS()
    if profileStartedAt and profileFinishedAt then
        stats.profileMS = stats.profileMS
            + math.max(0, profileFinishedAt - profileStartedAt)
    end
    local preparedRuntime = catalogMaterialized
        and GetCachedLifecycleRuntimeProfile(canonical, specKey) or nil
    if not preparedRuntime then
        local reconcileStartedAt = ProfileNowMS()
        local runtimeProfile, runtimeCode = BuildLifecycleRuntimeProfile(
            canonical,
            specKey
        )
        local reconcileFinishedAt = ProfileNowMS()
        if reconcileStartedAt and reconcileFinishedAt then
            stats.reconcileMS = stats.reconcileMS
                + math.max(0, reconcileFinishedAt - reconcileStartedAt)
        end
        if not runtimeProfile then
            RecordLifecycleDiagnostic(
                "context-runtime-profile",
                runtimeCode
            )
            local finishedAt = ProfileNowMS()
            if startedAt and finishedAt then
                stats.elapsedMS = stats.elapsedMS
                    + math.max(0, finishedAt - startedAt)
            end
            NotifyDesignerRuntimeApplied(
                designerSession,
                specKey,
                reason,
                false
            )
            return nil, runtimeCode
        end
        preparedRuntime = runtimeProfile
    end
    local runtimeMode, runtimeModeCode = ApplyRuntimeMode(preparedRuntime)
    if not runtimeMode then
        RecordLifecycleDiagnostic("context-runtime-mode", runtimeModeCode)
        return nil, runtimeModeCode
    end
    local refreshStartedAt = ProfileNowMS()
    local refreshed, refreshCode = self:Refresh(
        "context-coalesced",
        canonical,
        specKey,
        stats
    )
    if refreshed == nil then
        RecordLifecycleDiagnostic("context-runtime-profile", refreshCode)
    end
    local refreshFinishedAt = ProfileNowMS()
    if refreshStartedAt and refreshFinishedAt then
        stats.refreshMS = stats.refreshMS
            + math.max(0, refreshFinishedAt - refreshStartedAt)
    end
    local finishedAt = ProfileNowMS()
    if startedAt and finishedAt then
        stats.elapsedMS = stats.elapsedMS + math.max(0, finishedAt - startedAt)
    end
    NotifyDesignerRuntimeApplied(
        designerSession,
        specKey,
        reason,
        refreshed
    )
    return refreshed, refreshCode
end

function YHUD:GetContextRefreshStats()
    return self.contextRefreshStats
end

function YHUD:GetYieldController()
    local conflict = self.externalConflict
    if self.runtimeBlocked == true and type(conflict) == "table"
        and conflict.blocked == true and conflict.status == "active" then
        return conflict.controller, true
    end
    return nil, false
end

function YHUD:SetConflictBlocked(conflict)
    conflict = conflict or { blocked = true, status = "unknown", matches = {} }
    self:OnLifecycleDisable(true)
    self.startupState = "blocked"
    self.runtimeBlocked = true
    self.runtimeBlockedReason = conflict.reason or "external-cooldown-controller"
    self.externalConflict = conflict
    if conflict.status == "active" and YUI.Yield then
        YUI.Yield:Set("cooldown", conflict.controller, {
            status = conflict.status,
            matches = conflict.matches,
            enabled = true,
        })
    elseif YUI.Yield then
        YUI.Yield:Clear("cooldown")
    end
    return true
end

local function BeginEnableTrace(name)
    local watchdog = YUI.CPUWatchdog
    local startedAt = watchdog and watchdog.sceneCapture and watchdog:BeginProbeTiming()
    local trace = YUI.Trace
    if not (trace and trace.enabled ~= false
        and type(trace.Begin) == "function") then
        return nil, startedAt and { cpuStartedAt = startedAt, cpuName = name } or nil
    end
    local ok, record = pcall(
        trace.Begin,
        trace,
        "Products",
        name,
        nil,
        {
            moduleId = YHUD.PRODUCT_ID,
            phase = "OnEnable",
        }
    )
    record = ok and record or nil
    if startedAt then
        record = record or {}
        record.cpuStartedAt, record.cpuName = startedAt, name
    end
    return trace, record
end

local function FinishEnableTrace(trace, record, detail)
    if record and record.cpuStartedAt then
        local watchdog = YUI.CPUWatchdog
        watchdog:EndDynamicProbeTiming(record.cpuName, record.cpuName, nil, record.cpuStartedAt)
        record.cpuStartedAt, record.cpuName = nil, nil
    end
    if not (trace and record and type(trace.Finish) == "function") then
        return
    end
    pcall(trace.Finish, trace, record, "ok", nil, detail)
end

function YHUD:ActivateLifecycleRuntime(specKey, resourceOnly)
    local canonical = self:GetConfigProfile()
    if not canonical then return nil, "profile-unavailable" end
    local stageTrace, stageRecord
    stageTrace, stageRecord =
        BeginEnableTrace("YHUD:Enable:ReconcileContext")
    FinishEnableTrace(
        stageTrace,
        stageRecord,
        "runtimeOnly=true;storageChanged=false"
    )
    stageTrace, stageRecord =
        BeginEnableTrace("YHUD:Enable:RuntimeProfile")
    self.startupAllowResourceOnly = resourceOnly == true
    local profile, profileReport = BuildLifecycleRuntimeProfile(
        canonical,
        specKey
    )
    self.startupAllowResourceOnly = nil
    local profileCode = not profile and profileReport or nil
    local runtimeChanged = profile
        and type(profileReport) == "table"
        and profileReport.changed == true
    local runtimeStages = type(profileReport) == "table"
        and profileReport.runtimeStages or nil
    local runtimeStageDetail = runtimeStages and string.format(
        ";copyMS=%.2f;decodeMS=%.2f;normalizeMS=%.2f;catalogMS=%.2f"
            .. ";finalizeMS=%.2f;preparedRuntime=%s",
        tonumber(runtimeStages.copyMS) or 0,
        tonumber(runtimeStages.decodeMS) or 0,
        tonumber(runtimeStages.normalizeMS) or 0,
        tonumber(runtimeStages.catalogMS) or 0,
        tonumber(runtimeStages.finalizeMS) or 0,
        runtimeStages.preparedRuntime == true and "true" or "false"
    ) or ""
    FinishEnableTrace(
        stageTrace,
        stageRecord,
        string.format(
            "spec=%s;source=%s;runtimeChanged=%s;available=%s%s",
            tostring(specKey),
            type(canonical.specDocuments) == "table"
                and "spec-document" or "expanded-profile",
            runtimeChanged and "true" or "false",
            profile and "true" or "false",
            (profileCode and (";error=" .. tostring(profileCode)) or "")
                .. runtimeStageDetail
        )
    )
    if not profile then
        RecordLifecycleDiagnostic("enable-runtime-profile", profileCode)
        return nil, profileCode or "runtime-profile-unavailable"
    end
    if not resourceOnly and self.KeybindResolver then
        self.KeybindResolver:Enable()
    end
    if self.BlizzardSettings and self.BlizzardSettings.Enable then
        self.BlizzardSettings:Enable(profile, resourceOnly, "enable")
    end

    stageTrace, stageRecord =
        BeginEnableTrace("YHUD:Enable:PrepareOfficialRuntime")
    if not resourceOnly and self.NativeBridge
        and self.NativeBridge.PrepareOfficialRuntime then
        self.NativeBridge:PrepareOfficialRuntime()
    end
    FinishEnableTrace(stageTrace, stageRecord)

    stageTrace, stageRecord =
        BeginEnableTrace("YHUD:Enable:ViewSourcesLayout")
    if self.View then self.View:Enable(profile) end
    if self.Sources then
        if resourceOnly and self.Sources.EnableResourceOnly then
            self.Sources:EnableResourceOnly(profile)
        else
            self.Sources:Enable(profile)
        end
    end
    if self.LayoutBridge then self.LayoutBridge:Sync(profile) end
    FinishEnableTrace(stageTrace, stageRecord)

    stageTrace, stageRecord =
        BeginEnableTrace("YHUD:Enable:Persistence")
    FinishEnableTrace(
        stageTrace,
        stageRecord,
        "save=false;reason=runtime-only"
    )

    stageTrace, stageRecord =
        BeginEnableTrace("YHUD:Enable:NativeBridge")
    if not resourceOnly and self.NativeBridge then
        self.NativeBridge:Enable(profile)
    end
    FinishEnableTrace(stageTrace, stageRecord)

    stageTrace, stageRecord =
        BeginEnableTrace("YHUD:Enable:Skyriding")
    local skyridingReady = true
    local skyridingCode
    if self.Skyriding then
        skyridingReady, skyridingCode = self.Skyriding:Enable(profile)
    end
    if skyridingReady == nil then
        RecordLifecycleDiagnostic("skyriding-enable", skyridingCode)
    end
    FinishEnableTrace(
        stageTrace,
        stageRecord,
        skyridingReady == nil
            and ("available=false;error=" .. tostring(skyridingCode))
            or "available=true"
    )

    stageTrace, stageRecord =
        BeginEnableTrace("YHUD:Enable:Refresh")
    if not resourceOnly and self.KeybindText then self.KeybindText:Enable() end
    if not resourceOnly and self.CDMCatalog
        and self.CDMCatalog.RegisterCallbacks then
        self.CDMCatalog:RegisterCallbacks()
    end
    local refreshed, refreshCode = self:Refresh("enable", profile, specKey)
    if refreshed == nil then
        RecordLifecycleDiagnostic("enable-runtime-refresh", refreshCode)
        if self.BlizzardSettings then
            self.BlizzardSettings:Disable("enable-failed")
        end
        return nil, refreshCode
    end
    self.runtimeMode = resourceOnly and "resource-only" or "full"
    self.startupState = "active"
    self.startupRecoveryPending = false
    self.startupPendingReason = nil
    self.startupRetryIndex = nil
    self:CancelStartupRecoveryTimer()
    if resourceOnly then
        RegisterInitialSpecializationRecovery()
    else
        UnregisterInitialSpecializationRecovery()
    end
    FinishEnableTrace(stageTrace, stageRecord)
    return true
end

function YHUD:TryActivateRuntime(reason)
    if not self:IsEnabled() then return false, "disabled" end
    if self.runtimeMode ~= nil then return true, self.runtimeMode end
    if self.startupActivating == true then return false, "activating" end

    self.startupActivating = true
    local worldReady = IsWorldReady()
    if worldReady then self.startupWorldReady = true end

    local stageTrace, stageRecord =
        BeginEnableTrace("YHUD:Enable:ConflictCheck")
    local conflictOptions = worldReady and { force = true } or nil
    local conflict = self.ConflictGuard
        and self.ConflictGuard:Check(conflictOptions)
        or { blocked = false, status = "inactive", matches = {} }
    FinishEnableTrace(
        stageTrace,
        stageRecord,
        conflict.blocked == true and "blocked=true" or "blocked=false"
    )
    if conflict.blocked == true then
        self.startupActivating = false
        if conflict.status == "active" then
            self.startupState = "blocked"
            return self:SetConflictBlocked(conflict), conflict.reason
        end
        self.runtimeBlocked = true
        self.runtimeBlockedReason = conflict.reason
            or "external-state-unreadable"
        self.externalConflict = conflict
        self.startupState = worldReady and "blocked" or "waiting-world"
        if worldReady and self:ScheduleStartupRecovery(reason, false) then
            self.startupState = "waiting-world"
        else
            RecordLifecycleDiagnostic(
                "startup-conflict",
                self.runtimeBlockedReason
            )
        end
        return false, self.runtimeBlockedReason
    end

    self.runtimeBlocked = false
    self.runtimeBlockedReason = nil
    self.externalConflict = nil
    if YUI.Yield then YUI.Yield:Clear("cooldown") end

    local specKey = self:GetCurrentSpecKey()
    local stable = self:IsStableSpecKey(specKey)
    local initial = not stable and self:IsInitialSpecialization()
    if not stable then
        self.startupActivating = false
        if not worldReady then
            self.startupState = "waiting-world"
            self.startupPendingReason = reason or "waiting-world"
            return false, "waiting-world"
        end
        if self:ScheduleStartupRecovery(reason, false) then
            self.startupState = "waiting-spec"
            return false, "waiting-spec"
        end
        if not initial then
            self.startupState = "waiting-spec"
            RecordLifecycleDiagnostic(
                "startup-specialization",
                "invalid-spec-key"
            )
            return false, "invalid-spec-key"
        end
    end

    self.startupState = "activating"
    local activated, code = self:ActivateLifecycleRuntime(
        specKey,
        not stable and initial
    )
    self.startupActivating = false
    if activated then return true, self.runtimeMode end
    if code == "runtime-profile-stale"
        and self:ScheduleStartupRecovery(reason, false) then
        self.startupState = "waiting-spec"
        return false, code
    end
    self.startupState = "blocked"
    RecordLifecycleDiagnostic("startup-runtime", code)
    return nil, code
end

function YHUD:OnLifecycleEnable()
    if self.LevelDisplay then self.LevelDisplay:Enable() end
    if self.runtimeMode ~= nil and self.startupState == "active" then
        return true
    end
    if self.startupRecoveryPending == true then
        self:RequestStartupRecovery("enable-resume")
        return true
    end

    self.startupGeneration = (tonumber(self.startupGeneration) or 0) + 1
    self:CancelStartupRecoveryTimer()
    self.startupWorldReady = IsWorldReady()
    self.startupState = self.startupWorldReady
        and "waiting-spec" or "waiting-world"
    self.startupRecoveryPending = true
    self.startupPendingReason = "enable"
    self.startupRetryIndex = 1
    self.startupActivating = false
    RegisterInitialSpecializationRecovery()

    local activated, code = self:TryActivateRuntime("enable")
    if activated == nil then return nil, code end
    return true, code
end

function YHUD:OnLifecycleDisable(keepConflict)
    if self.LevelDisplay then self.LevelDisplay:Disable() end
    self.startupGeneration = (tonumber(self.startupGeneration) or 0) + 1
    self:CancelStartupRecoveryTimer()
    self:CancelPendingContextRefresh()
    UnregisterInitialSpecializationRecovery()
    if self.KeybindText then self.KeybindText:Disable() end
    if self.KeybindResolver then self.KeybindResolver:Disable() end
    if self.DesignerUI and self.DesignerUI.active then
        self.DesignerUI:ForceClose("designer-product-disabled")
    end
    if self.Skyriding then self.Skyriding:Disable() end
    if self.NativeBridge then self.NativeBridge:Disable() end
    if self.CDMCatalog and self.CDMCatalog.UnregisterCallbacks then
        self.CDMCatalog:UnregisterCallbacks()
    end
    if self.Sources then self.Sources:Disable() end
    self.runtimeMode = nil
    self.startupRecoveryPending = false
    self.startupPendingReason = nil
    self.startupRetryIndex = nil
    self.startupActivating = false
    self.startupAllowResourceOnly = nil
    self.startupState = keepConflict == true and "blocked" or nil
    if self.LayoutBridge then self.LayoutBridge:Unregister() end
    if self.View then self.View:Disable() end
    if self.BlizzardSettings then
        self.BlizzardSettings:Disable("lifecycle-disabled")
    end
    if self.Model then self.Model:Reset() end
    if keepConflict ~= true then
        self.runtimeBlocked = false
        self.runtimeBlockedReason = nil
        self.externalConflict = nil
        if YUI.Yield then YUI.Yield:Clear("cooldown") end
    end
    return true
end

function YHUD:OnLifecycleProfileChanged()
    if self.DesignerUI and self.DesignerUI.active then
        self.DesignerUI:ForceClose("designer-config-set-changed")
    end
    self:InvalidateRuntimeProfile()
    if self.InvalidateDBCache then self:InvalidateDBCache() end
    self:EnsureDB(true)
    if self.ConfigSets then self.ConfigSets:EnsureDefaultUserSet(true) end
    local specKey = self:GetCurrentSpecKey()
    local canonical = self:GetConfigProfile()
    local profile, code = BuildLifecycleRuntimeProfile(canonical, specKey)
    if not profile then
        RecordLifecycleDiagnostic("profile-runtime-profile", code)
        return nil, code
    end
    return self:Refresh("profile-changed")
end

function YHUD:OnLifecycleConfigChanged()
    self:InvalidateRuntimeProfile()
    local specKey = self:GetCurrentSpecKey()
    local canonical = self:GetConfigProfile()
    local profile, code = BuildLifecycleRuntimeProfile(canonical, specKey)
    if not profile then
        RecordLifecycleDiagnostic("config-runtime-profile", code)
        return nil, code
    end
    return self:Refresh("config-changed")
end

function YHUD:OnLifecycleLayoutChanged()
    if self.View and self.View.active then
        self.View:Relayout()
    end
    if self.NativeBridge and self.NativeBridge.active then
        self.NativeBridge:Sync(nil, "layout-changed")
    end
    return true
end

function YHUD:OpenSettings()
    if YUI.Settings and YUI.Settings.OpenProduct then
        return YUI.Settings:OpenProduct(self.PRODUCT_ID, self.SETTINGS_ENTRY)
    end
    if YUI.OpenSettings then
        return YUI:OpenSettings("YHUD", self.PRODUCT_ID)
    end
    return false
end

local function RegisterCommands()
    if not (YUI.Commands and YUI.Commands.Register) then return end
    local function HandleCommand(message)
        if YHUD.KeybindResolver
            and YHUD.KeybindResolver:HandleCommand(message) then
            return
        end
        YHUD:OpenSettings()
    end

    YUI.Commands:Register({
        id = "yhud",
        productId = YUI.CoreMode == "suite" and "suite" or YHUD.PRODUCT_ID,
        aliases = { "/halo", "/yhud" },
        handler = HandleCommand,
    })
    if not _G.SlashCmdList then return end
    local function Dispatch(message)
        if YUI.HandleSlashCommand and YUI:HandleSlashCommand(message) then
            return
        end
        HandleCommand(message)
    end
    -- Product metadata may have registered either alias before the runtime.
    -- Only adopt our own command slots; never overwrite another addon's alias.
    for _, alias in ipairs({ "/halo", "/yhud" }) do
        local slashID = YUI.Commands.registeredAliases
            and YUI.Commands.registeredAliases[alias]
        if slashID == "YUI_PRODUCT_YHUD" or slashID == "YUI_PRODUCT_YHUD_1" then
            _G.SlashCmdList[slashID] = Dispatch
        end
    end
end

RegisterCommands()

local function PrepareTransferExportValue(path, value)
    if path ~= YHUD.STORAGE_KEY or type(value) ~= "table" then
        return nil, "invalid_payload"
    end
    local adapter = YHUD.ConfigSets
    if not (adapter and type(adapter.PrepareGraphicalProfileForTransfer) == "function") then
        return nil, "config_sets_unavailable"
    end
    local profile, code, detail = adapter:PrepareGraphicalProfileForTransfer(
        value.profile,
        true
    )
    if not profile then return nil, code, detail end
    value.profile = profile
    return value
end

local function PrepareTransferStoredValue(path, value)
    if path ~= YHUD.STORAGE_KEY or type(value) ~= "table" then
        return nil, "invalid_payload"
    end
    local adapter = YHUD.ConfigSets
    if not (adapter and type(adapter.PrepareProfileForStorage) == "function") then
        return nil, "config_sets_unavailable"
    end
    local stored = YHUD:CopyValue(value)
    local profile, code, detail = adapter:PrepareProfileForStorage(
        stored.profile,
        true
    )
    if not profile then return nil, code, detail end
    stored.profile = profile
    return stored
end

if YUI.RegisterProduct then
    YUI:RegisterProduct({
        id = YHUD.PRODUCT_ID,
        title = "Halo Monitor · YanForge",
        titleKey = "product.title",
        titleNamespace = "YHUD",
        shortTitle = "Halo Monitor",
        shortTitleKey = "product.short_title",
        shortTitleNamespace = "YHUD",
        logo = "icons\\logo_32.png",
        smallLogo = "icons\\logo_32.png",
        logoCrop = false,
        notes = "Halo Monitor · YanForge",
        notesKey = "product.notes",
        notesNamespace = "YHUD",
        author = "阿言",
        addonName = ADDON_NAME or YUI.AddonName,
        settingsScope = YHUD.PRODUCT_ID,
        settings = {
            enabled = true,
            entry = YHUD.SETTINGS_ENTRY,
            commonPages = { "core.profiles", "core.about" },
            minimapIcon = YHUD.IS_STANDALONE == true,
        },
        db = {
            enabled = true,
            savedVariable = YUI.CoreMode == "suite" and "YUI_DB" or "YUI_YHUD_DB",
            storageKey = YHUD.STORAGE_KEY,
        },
        transfer = {
            prepareStoredValue = PrepareTransferStoredValue,
            prepareExportValue = PrepareTransferExportValue,
            splitImport = function(payload)
                if not YHUD.Sharing then return nil end
                return YHUD.Sharing:SplitProfileImport(payload)
            end,
        },
        commands = {
            { alias = "/halo", aliases = { "/yhud" }, action = "openSettings", entry = YHUD.SETTINGS_ENTRY },
        },
    })
end

if YUI.Module and YUI.Module.Register then
    YUI.Module:Register({
        id = YHUD.PRODUCT_ID,
        name = "Halo",
        product = YHUD.PRODUCT_ID,
        scope = YHUD.PRODUCT_ID,
        defaultEnabled = false,
        owner = YHUD,
        dependencies = { "core.db", "core.event", "core.locale", "core.api", "gui", "settings" },
        getEnabled = function(owner)
            return owner:IsEnabled()
        end,
        setEnabled = function(owner, enabled)
            return owner:SetEnabled(enabled, true)
        end,
        OnInitialize = "Initialize",
        OnEnable = "OnLifecycleEnable",
        OnDisable = "OnLifecycleDisable",
        OnProfileChanged = "OnLifecycleProfileChanged",
        OnConfigChanged = "OnLifecycleConfigChanged",
        OnLayoutChanged = "OnLifecycleLayoutChanged",
    })
end

local function MeasureStartup(name, callback)
    local trace = YUI.Trace
    if trace and trace.enabled ~= false and type(trace.Measure) == "function" then
        return trace:Measure("Products", name, callback, nil, {
            moduleId = YHUD.PRODUCT_ID,
            phase = "YUI_DB_READY",
        })
    end
    return callback()
end

local function EnsureStartupDB()
    return YHUD:EnsureDB()
end

local function RegisterStartupConfigSets()
    return YHUD.ConfigSets:RegisterProvider()
end

local function EnsureStartupDefaultUserSet()
    return YHUD.ConfigSets:EnsureDefaultUserSet()
end

if YUI.Event and YUI.Event.On then
    YUI.Event:On("YUI_DB_READY", function()
        MeasureStartup("YHUD:Startup:EnsureDB", EnsureStartupDB)
        if YHUD.ConfigSets then
            MeasureStartup(
                "YHUD:Startup:RegisterConfigSets",
                RegisterStartupConfigSets
            )
            MeasureStartup(
                "YHUD:Startup:EnsureDefaultUserSet",
                EnsureStartupDefaultUserSet
            )
        end
    end, YHUD, {
        priority = 4000,
        traceName = "YHUD:EnsureDB",
        moduleId = YHUD.PRODUCT_ID,
        phase = "YUI_DB_READY",
    })
    YUI.Event:On("YUI_EXTERNAL_STATE_CHANGED", function()
        if not YHUD:IsEnabled() then return end
        local conflict = YHUD.ConflictGuard and YHUD.ConflictGuard:Check()
        if type(conflict) ~= "table" then return end
        local wasYielded = type(YHUD.externalConflict) == "table"
            and YHUD.externalConflict.blocked == true
        if conflict.blocked == true then
            if not wasYielded
                or YHUD.externalConflict.controller ~= conflict.controller
                or YHUD.externalConflict.status ~= conflict.status then
                YHUD:SetConflictBlocked(conflict)
            end
        elseif wasYielded then
            YHUD:OnLifecycleEnable()
        end
    end, YHUD, {
        moduleId = YHUD.PRODUCT_ID,
        traceName = "YHUD:ExternalStateChanged",
    })
end

if YUI.Components and YUI.Components.Register then
    YUI.Components:Register({
        id = YHUD.PRODUCT_ID,
        kind = "product",
        displayName = "Halo Monitor",
        description = YHUD:T("product.description", "高性能、可配置的正式服冷却监控产品。"),
        tags = { "战斗辅助", "美化皮肤" },
        settingsMode = "external",
        standalone = true,
        order = 915,
        storageKey = YHUD.STORAGE_KEY,
        sourceRoot = "Products\\YHUD",
        versions = { "mainline" },
        getEnabled = function()
            return YHUD:IsEnabled()
        end,
        getEffectiveState = function()
            local controller, yielded = YHUD:GetYieldController()
            if yielded then
                return {
                    effective = false,
                    kind = "yield",
                    controller = controller,
                    featureKey = "cooldown",
                    status = "active",
                    tone = "warning",
                }
            end
            if YHUD.runtimeBlocked then
                return {
                    effective = false,
                    reason = YHUD.runtimeBlockedReason,
                    tone = "danger",
                }
            end
            return { effective = true }
        end,
        setEnabled = function(_, enabled)
            return YHUD:SetEnabled(enabled)
        end,
        getEffectiveState = function()
            return { effective = YHUD:IsEnabled() }
        end,
        openSettings = function()
            return YHUD:OpenSettings()
        end,
    })
end

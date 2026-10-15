local YUI = _G.YUI
if not YUI or not YUI.Settings or not YUI.Settings.ConfigSets then return end

local S = YUI.Settings
S.ConfigSetRuntime = S.ConfigSetRuntime or {}
local Runtime = S.ConfigSetRuntime
if Runtime._loaded then return end
Runtime._loaded = true

Runtime.MODULE_ID = "settings.config_set_runtime"
Runtime.pendingByProvider = Runtime.pendingByProvider or {}
Runtime.lastErrors = Runtime.lastErrors or {}
Runtime.contextStats = Runtime.contextStats or {
    requests = 0,
    coalesced = 0,
    executions = 0,
    elapsedMS = 0,
}

local CONTEXT_RECONCILE_DELAY = 0.1

local function ProfileNowMS()
    if type(debugprofilestop) ~= "function" then return nil end
    local ok, value = pcall(debugprofilestop)
    return ok and type(value) == "number" and value or nil
end

local function ContextReconcileTimerCallback()
    Runtime._contextTimer = nil
    local reason = Runtime._contextReason or "context-coalesced"
    Runtime._contextReason = nil
    local stats = Runtime.contextStats
    stats.executions = stats.executions + 1
    local startedAt = ProfileNowMS()
    Runtime:ReconcileAll(reason)
    local finishedAt = ProfileNowMS()
    if startedAt and finishedAt then
        stats.elapsedMS = stats.elapsedMS + math.max(0, finishedAt - startedAt)
    end
end

local function ReferencesEqual(left, right)
    return type(left) == "table"
        and type(right) == "table"
        and left.kind == right.kind
        and left.id == right.id
end

local function SupportsConfigurationModes(provider)
    return type(provider) == "table"
        and type(provider.configurationModes) == "table"
        and provider.configurationModes.isolatedLibraries == true
end

local function UsesAutomaticConfiguration(provider)
    return SupportsConfigurationModes(provider)
        or (
            provider
            and provider.specializationAssignments
            and provider.autoApplyAssignments
        )
end

local function IsInCombat()
    local CombatAPI = YUI.API and YUI.API.Combat or YUI.WOW_API or {}
    local callback = CombatAPI.InCombatLockdown or _G.InCombatLockdown
    if type(callback) ~= "function" then return false end
    local ok, value = pcall(callback)
    return ok and value == true
end

local function IsWorldReady()
    if Runtime._worldReady then return true end
    local lifecycle = YUI.Lifecycle
    if lifecycle and type(lifecycle.IsReady) == "function" then
        return lifecycle:IsReady("YUI_WORLD_READY")
    end
    return false
end

local function IsRetryable(code)
    return code == "busy"
        or code == "db_not_ready"
        or code == "runtime_not_ready"
        or code == "runtime-inactive"
        or code == "combat-lockdown"
        or code == "combat_lockdown"
end

function Runtime:SetPending(providerId, reason)
    self.pendingByProvider[providerId] = {
        reason = reason or "pending",
    }
end

function Runtime:ClearPending(providerId)
    self.pendingByProvider[providerId] = nil
end

function Runtime:ReconcileProvider(providerId, reason)
    local service = S.ConfigSets
    local provider = service and service:GetProvider(providerId)
    if not provider then
        self:ClearPending(providerId)
        return nil, "provider_not_found"
    end
    if not UsesAutomaticConfiguration(provider) then
        self:ClearPending(providerId)
        return false, "automatic_assignments_disabled"
    end

    local transfer = S.ConfigTransfer
    if transfer and transfer.IsImporting and transfer:IsImporting(provider.productId) then
        self:SetPending(providerId, "import-in-progress")
        return nil, "import-in-progress"
    end

    local code, detail
    local configurationMode
    if SupportsConfigurationModes(provider) then
        configurationMode, code, detail =
            service:GetConfigurationMode(providerId)
        if not configurationMode then
            if IsRetryable(code) then
                self:SetPending(providerId, code or "db_not_ready")
            else
                self:ClearPending(providerId)
                self.lastErrors[providerId] =
                    tostring(detail or code or "configuration-mode-read-failed")
            end
            return nil, code, detail
        end
    end

    local reference
    if configurationMode == "unified" then
        reference, code, detail = service:GetConfigurationModeReference(
            providerId,
            configurationMode
        )
        if not reference then
            self:ClearPending(providerId)
            return false, code or "assignment_not_found", detail
        end
    else
        local assignments
        assignments, code, detail = service:GetAssignments(providerId)
        if not assignments then
            if IsRetryable(code) then
                self:SetPending(providerId, code or "db_not_ready")
            else
                self:ClearPending(providerId)
                self.lastErrors[providerId] =
                    tostring(detail or code or "assignment-read-failed")
            end
            return nil, code, detail
        end

        -- 旧账号没有显式进入专精路由模式时，只向 UI 暴露 Provider 的默认兜底，
        -- 绝不在登录或专精切换时主动覆盖当前配置。
        if assignments.enabled ~= true then
            self:ClearPending(providerId)
            return false, "assignments_not_enabled"
        end
    end
    if not self._enabled or not IsWorldReady() then
        self:SetPending(providerId, "runtime_not_ready")
        return nil, "runtime_not_ready"
    end

    local specKey = service:GetCurrentSpecializationKey()
    if not reference then
        reference, code, detail = service:ResolveAssignment(providerId, specKey)
        if not reference then
            self:ClearPending(providerId)
            return false, code or "assignment_not_found", detail
        end
    end

    local active
    active, code, detail = service:GetActiveReference(providerId)
    if code then
        self:SetPending(providerId, code)
        return nil, code, detail
    end
    if IsInCombat() then
        self:SetPending(providerId, "combat-lockdown")
        return nil, "combat-lockdown"
    end
    if ReferencesEqual(active, reference) then
        self:ClearPending(providerId)
        self.lastErrors[providerId] = nil
        return false, "already_active"
    end
    if service.busy[providerId] then
        self:SetPending(providerId, "busy")
        return nil, "busy"
    end
    if type(provider.assignmentReady) == "function" then
        local ok, ready, readyCode = pcall(provider.assignmentReady, {
            action = "assignment_ready",
            providerId = providerId,
            productId = provider.productId,
            reference = reference,
            specializationKey = specKey,
            reason = reason,
            service = service,
            runtime = self,
        })
        if not ok then
            self:SetPending(providerId, "runtime_not_ready")
            self.lastErrors[providerId] = tostring(ready)
            return nil, "runtime_not_ready", ready
        end
        if ready ~= true then
            local pendingReason = readyCode or "runtime_not_ready"
            self:SetPending(providerId, pendingReason)
            return nil, pendingReason
        end
    end

    local result
    result, code, detail = service:Apply(providerId, reference, self, {
        recordUndo = false,
        automatic = true,
        specializationKey = specKey,
        reason = reason or "assignment-reconcile",
    })
    if not result then
        if IsRetryable(code) then
            self:SetPending(providerId, code)
        else
            self:ClearPending(providerId)
            self.lastErrors[providerId] = tostring(detail or code)
        end
        return nil, code, detail
    end

    self:ClearPending(providerId)
    self.lastErrors[providerId] = nil
    return result
end

function Runtime:ReconcileAll(reason)
    local service = S.ConfigSets
    if not service then return 0 end
    local count = 0
    for providerId, provider in pairs(service.providers or {}) do
        if UsesAutomaticConfiguration(provider) then
            count = count + 1
            self:ReconcileProvider(providerId, reason)
        end
    end
    return count
end

function Runtime:RequestContextReconcile(reason)
    local stats = self.contextStats
    stats.requests = stats.requests + 1
    self._contextReason = self._contextReason
        or reason or "context-coalesced"
    if self._contextTimer then
        stats.coalesced = stats.coalesced + 1
        return true
    end
    if C_Timer and C_Timer.NewTimer then
        self._contextTimer = C_Timer.NewTimer(
            CONTEXT_RECONCILE_DELAY,
            ContextReconcileTimerCallback
        )
        return true
    end
    ContextReconcileTimerCallback()
    return true
end

function Runtime:CancelContextReconcile()
    if self._contextTimer and self._contextTimer.Cancel then
        self._contextTimer:Cancel()
    end
    self._contextTimer = nil
    self._contextReason = nil
end

function Runtime:GetContextStats()
    return self.contextStats
end

function Runtime:FlushPending(reason)
    if next(self.pendingByProvider) == nil then return 0 end
    local pending = {}
    for providerId in pairs(self.pendingByProvider) do
        pending[#pending + 1] = providerId
    end
    table.sort(pending)
    for _, providerId in ipairs(pending) do
        self:ReconcileProvider(providerId, reason or "pending-flush")
    end
    return #pending
end

function Runtime:OnWorldReady()
    self._worldReady = true
    self:ReconcileAll("world-ready")
end

function Runtime:OnPlayerSpecializationChanged(_, unit)
    if unit ~= nil and unit ~= "player" then return end
    self:RequestContextReconcile("specialization-changed")
end

function Runtime:OnSpecializationChanged(event)
    self:RequestContextReconcile(event or "specialization-changed")
end

function Runtime:OnAssignmentsChanged(_, providerId)
    if providerId then
        self:ReconcileProvider(providerId, "assignments-changed")
    end
end

function Runtime:OnConfigurationModeChanged(_, providerId)
    if providerId then
        self:ReconcileProvider(providerId, "configuration-mode-changed")
    end
end

function Runtime:OnProviderRegistered(_, providerId)
    if providerId then
        self:ReconcileProvider(providerId, "provider-registered")
    end
end

function Runtime:OnModuleEnabled(_, moduleId, moduleDefinition)
    local service = S.ConfigSets
    for providerId, provider in pairs(service and service.providers or {}) do
        if UsesAutomaticConfiguration(provider) then
            local matches = moduleId == providerId
                or moduleId == provider.productId
                or (type(moduleDefinition) == "table" and (
                    moduleDefinition.product == provider.productId
                    or moduleDefinition.scope == providerId
                    or moduleDefinition.scope == provider.productId
                    or moduleDefinition.parent == providerId
                    or moduleDefinition.parent == provider.productId
                ))
            if matches then
                self:ReconcileProvider(providerId, "module-enabled")
            end
        end
    end
end

function Runtime:OnPlayerRegenEnabled()
    self:FlushPending("combat-ended")
end

function Runtime:OnImportReleased()
    if self._enabled then self:FlushPending("import-released") end
end

function Runtime:OnTransactionsInvalidated()
    local service = S.ConfigSets
    for providerId, provider in pairs(service and service.providers or {}) do
        if UsesAutomaticConfiguration(provider) then
            self:SetPending(providerId, "profile-changed")
        end
    end
end

function Runtime:OnProfileChanged()
    self:ReconcileAll("profile-changed")
end

function Runtime:OnEnable()
    if self._enabled then return end
    local Event = YUI.Event
    if not Event then return end
    self._enabled = true

    Event:On("YUI_WORLD_READY", "OnWorldReady", self, {
        moduleId = self.MODULE_ID,
        phase = "YUI_WORLD_READY",
    })
    Event:On("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled", self, {
        moduleId = self.MODULE_ID,
        phase = "PLAYER_REGEN_ENABLED",
    })
    Event:On("PLAYER_SPECIALIZATION_CHANGED", "OnPlayerSpecializationChanged", self, {
        moduleId = self.MODULE_ID,
        phase = "PLAYER_SPECIALIZATION_CHANGED",
    })
    Event:On("ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "OnSpecializationChanged", self, {
        moduleId = self.MODULE_ID,
        phase = "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    })
    Event:On("ACTIVE_TALENT_GROUP_CHANGED", "OnSpecializationChanged", self, {
        moduleId = self.MODULE_ID,
        phase = "ACTIVE_TALENT_GROUP_CHANGED",
    })
    Event:On("CHARACTER_POINTS_CHANGED", "OnSpecializationChanged", self, {
        moduleId = self.MODULE_ID,
        phase = "CHARACTER_POINTS_CHANGED",
    })
    Event:On("PLAYER_TALENT_UPDATE", "OnSpecializationChanged", self, {
        moduleId = self.MODULE_ID,
        phase = "PLAYER_TALENT_UPDATE",
    })
    Event:On("ACTIVE_COMBAT_CONFIG_CHANGED", "OnSpecializationChanged", self, {
        moduleId = self.MODULE_ID,
        phase = "ACTIVE_COMBAT_CONFIG_CHANGED",
    })
    Event:On("TRAIT_CONFIG_UPDATED", "OnSpecializationChanged", self, {
        moduleId = self.MODULE_ID,
        phase = "TRAIT_CONFIG_UPDATED",
    })
    Event:On("YUI_CONFIG_SET_ASSIGNMENTS_CHANGED", "OnAssignmentsChanged", self, {
        moduleId = self.MODULE_ID,
        phase = "assignments-changed",
    })
    Event:On("YUI_CONFIG_SET_MODE_CHANGED", "OnConfigurationModeChanged", self, {
        moduleId = self.MODULE_ID,
        phase = "YUI_CONFIG_SET_MODE_CHANGED",
    })
    Event:On("YUI_CONFIG_SET_PROVIDER_REGISTERED", "OnProviderRegistered", self, {
        moduleId = self.MODULE_ID,
        phase = "provider-registered",
    })
    Event:On("YUI_MODULE_ENABLED", "OnModuleEnabled", self, {
        moduleId = self.MODULE_ID,
        phase = "module-enabled",
    })
    Event:On("YUI_CONFIG_TRANSFER_RELEASED", "OnImportReleased", self, {
        moduleId = self.MODULE_ID,
        phase = "import-released",
    })

    if IsWorldReady() then
        self._worldReady = true
        self:ReconcileAll("runtime-enabled")
    end
end

function Runtime:OnDisable()
    self:CancelContextReconcile()
    if YUI.Event and type(YUI.Event.OffOwner) == "function" then
        YUI.Event:OffOwner(self)
    end
    self._enabled = false
    for providerId in pairs(self.pendingByProvider) do
        self.pendingByProvider[providerId] = nil
    end
end

local moduleDefinition = {
        id = Runtime.MODULE_ID,
        name = "Config Set Runtime",
        product = YUI.ProductId or "suite",
        scope = "settings",
        owner = Runtime,
        dependencies = { "core.db", "core.event" },
        getEnabled = function()
            return true
        end,
        OnEnable = "OnEnable",
        OnDisable = "OnDisable",
        OnProfileChanged = "OnProfileChanged",
}

function Runtime:RegisterModule()
    if self._moduleRegistered then return true end
    local Module = YUI.Module
    if not (Module and type(Module.Register) == "function") then
        return false
    end
    local registered = Module:Register(moduleDefinition)
    if not registered then return false end
    self._moduleRegistered = true
    return true
end

local databaseReady = YUI.Lifecycle
    and type(YUI.Lifecycle.IsReady) == "function"
    and YUI.Lifecycle:IsReady("YUI_DB_READY")
if databaseReady then
    Runtime:RegisterModule()
elseif YUI.Event then
    Runtime._moduleRegistrationHandle = YUI.Event:Once(
        "YUI_DB_READY",
        "RegisterModule",
        Runtime,
        {
            priority = 9000,
            moduleId = Runtime.MODULE_ID,
            phase = "YUI_DB_READY",
        }
    )
else
    Runtime:RegisterModule()
end

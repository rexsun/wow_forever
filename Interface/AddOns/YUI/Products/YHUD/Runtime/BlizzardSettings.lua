local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local System = YUI.API and YUI.API.System
local BlizzardSettings = YHUD.BlizzardSettings or {}
YHUD.BlizzardSettings = BlizzardSettings

local COOLDOWN_CVAR = "cooldownViewerEnabled"
local PERSONAL_RESOURCE_CVAR = "nameplateShowSelf"
local STORAGE_KEY = "YHUDBlizzardSettings"
local CONTEST_WINDOW_SECONDS = 1
local CONTEST_LIMIT = 3

BlizzardSettings.owner = BlizzardSettings.owner or {}
BlizzardSettings.pending = BlizzardSettings.pending or {}
BlizzardSettings.warned = BlizzardSettings.warned or {}
BlizzardSettings.contest = BlizzardSettings.contest or {}
BlizzardSettings.active = false
BlizzardSettings.resourceOnly = true
BlizzardSettings.writeDepth = 0
BlizzardSettings.generation = tonumber(BlizzardSettings.generation) or 0

local function IsInCombat()
    return type(InCombatLockdown) == "function"
        and InCombatLockdown() == true
end

local function RecordDiagnostic(code, detail)
    local diagnostics = YHUD.Diagnostics
    if diagnostics and type(diagnostics.Record) == "function" then
        diagnostics:Record(code, detail)
    end
end

local function PrintWarning(key, fallback)
    if BlizzardSettings.warned[key] then return false end
    BlizzardSettings.warned[key] = true
    local message = YHUD:T(key, fallback)
    if YUI.Print then
        YUI:Print(message)
    elseif type(_G.print) == "function" then
        _G.print(message)
    end
    return true
end

local function WarningForCVar(name, contested)
    if name == COOLDOWN_CVAR then
        if contested then
            return "runtime.blizzard_settings.cooldown_contested",
                "YHUD stopped retrying Blizzard Cooldown Manager because another addon keeps changing the setting."
        end
        return "runtime.blizzard_settings.cooldown_failed",
            "YHUD could not enable Blizzard Cooldown Manager. Enable it under Options > Advanced."
    end
    if contested then
        return "runtime.blizzard_settings.personal_resource_contested",
            "YHUD stopped retrying Blizzard Personal Resource Display because another addon keeps changing the setting."
    end
    return "runtime.blizzard_settings.personal_resource_failed",
        "YHUD could not hide Blizzard Personal Resource Display. Disable it under Options > Combat."
end

local function WarnCVar(name, contested)
    local key, fallback = WarningForCVar(name, contested)
    return PrintWarning(key, fallback)
end

local function ParseBoolean(value)
    if value == true or value == 1 or value == "1" or value == "true" then
        return true
    end
    if value == false or value == 0 or value == "0" or value == "false" then
        return false
    end
    return nil
end

local function ReadCVarBoolean(name)
    if not (System and type(System.GetCVarSafe) == "function") then
        return nil, "api-unavailable"
    end
    local raw = System.GetCVarSafe(name)
    if raw == nil then return nil, "cvar-unavailable" end
    if type(System.GetCVarBool) == "function" then
        return System.GetCVarBool(name) == true
    end
    local value = ParseBoolean(raw)
    if value == nil then return nil, "invalid-cvar-value" end
    return value
end

local function GetCharacterStorage(create)
    local db = YUI.DB and type(YUI.DB.GetAceDB) == "function"
        and YUI.DB:GetAceDB(YHUD.PRODUCT_ID) or nil
    local charKey = db and db.keys and db.keys.char
    local global = db and db.global
    if type(charKey) ~= "string" or charKey == ""
        or type(global) ~= "table" then
        return nil, "character-storage-unavailable"
    end

    local root = global[STORAGE_KEY]
    if type(root) ~= "table" then
        if not create then return nil end
        root = { characters = {} }
        global[STORAGE_KEY] = root
    end
    if type(root.characters) ~= "table" then
        if not create then return nil end
        root.characters = {}
    end
    local state = root.characters[charKey]
    if type(state) ~= "table" and create then
        state = {}
        root.characters[charKey] = state
    end
    return state, nil, root, charKey
end

local function ClearPersonalResourceOwnership()
    local state, _, root, charKey = GetCharacterStorage(false)
    if not state then return false end
    state.personalResourceBaseline = nil
    if next(state) == nil and root and charKey then
        root.characters[charKey] = nil
    end
    return true
end

local function GetPersonalResourceBaseline()
    local state = GetCharacterStorage(false)
    if type(state) ~= "table" then return nil end
    if state.personalResourceBaseline == true then return true end
    if state.personalResourceBaseline ~= nil then
        ClearPersonalResourceOwnership()
    end
    return nil
end

local function SetPersonalResourceBaseline(value)
    local state, code = GetCharacterStorage(true)
    if not state then return false, code end
    state.personalResourceBaseline = value == true
    return true
end

local function ResetContestState()
    for _, state in pairs(BlizzardSettings.contest) do
        state.windowStart = nil
        state.count = 0
        state.blocked = false
    end
end

local function GetTimeNow()
    return System and type(System.GetTime) == "function"
        and System.GetTime() or 0
end

local function RegisterContest(name)
    local now = tonumber(GetTimeNow()) or 0
    local state = BlizzardSettings.contest[name]
    if not state then
        state = { count = 0, blocked = false }
        BlizzardSettings.contest[name] = state
    end
    if type(state.windowStart) ~= "number"
        or now - state.windowStart > CONTEST_WINDOW_SECONDS then
        state.windowStart = now
        state.count = 0
        state.blocked = false
    end
    state.count = state.count + 1
    if state.count < CONTEST_LIMIT then return false end
    state.blocked = true
    BlizzardSettings.pending[name] = nil
    RecordDiagnostic("blizzard-settings-contested", name)
    WarnCVar(name, true)
    return true
end

local function IsContestBlocked(name)
    local state = BlizzardSettings.contest[name]
    return state and state.blocked == true or false
end

function BlizzardSettings:CancelPendingSync()
    if self.syncTimer and self.syncTimer.Cancel then
        self.syncTimer:Cancel()
    end
    self.syncTimer = nil
    self.syncTimerGeneration = nil
    self.pendingReason = nil
end

function BlizzardSettings.TimerCallback()
    local generation = BlizzardSettings.syncTimerGeneration
    local reason = BlizzardSettings.pendingReason or "cvar-update"
    BlizzardSettings.syncTimer = nil
    BlizzardSettings.syncTimerGeneration = nil
    BlizzardSettings.pendingReason = nil
    if generation ~= BlizzardSettings.generation
        or BlizzardSettings.active ~= true then
        return false
    end
    return BlizzardSettings:Sync(nil, nil, reason)
end

function BlizzardSettings:QueueSync(reason)
    if self.active ~= true or self.syncTimer then return false end
    self.pendingReason = reason or "cvar-update"
    self.syncTimerGeneration = self.generation
    if C_Timer and type(C_Timer.NewTimer) == "function" then
        self.syncTimer = C_Timer.NewTimer(0, self.TimerCallback)
        return self.syncTimer ~= nil
    end
    local pendingReason = self.pendingReason
    self.pendingReason = nil
    self.syncTimerGeneration = nil
    return self:Sync(nil, nil, pendingReason)
end

function BlizzardSettings:WriteCVar(name, desired)
    if not (System and type(System.SetCVar) == "function") then
        self.pending[name] = true
        RecordDiagnostic(
            "blizzard-settings-write-failed",
            name .. ":api-unavailable"
        )
        if not IsInCombat() then WarnCVar(name, false) end
        return false, "api-unavailable", false
    end
    local current, code = ReadCVarBoolean(name)
    if current == nil then
        self.pending[name] = true
        RecordDiagnostic(
            "blizzard-settings-write-failed",
            name .. ":" .. tostring(code)
        )
        if not IsInCombat() then WarnCVar(name, false) end
        return false, code, false
    end
    if current == desired then
        self.pending[name] = nil
        return true, nil, false
    end
    if self.writeDepth > 0 then
        return false, "write-reentrant", false
    end

    self.writeDepth = self.writeDepth + 1
    local wrote = System.SetCVar(name, desired and 1 or 0) == true
    self.writeDepth = self.writeDepth - 1
    local verified, verifyCode = ReadCVarBoolean(name)
    if wrote and verified == desired then
        self.pending[name] = nil
        return true, nil, true
    end

    self.pending[name] = true
    code = verifyCode or (IsInCombat() and "combat-write-failed"
        or (wrote and "write-verification-failed" or "write-failed"))
    RecordDiagnostic("blizzard-settings-write-failed", name .. ":" .. code)
    if not IsInCombat() then WarnCVar(name, false) end
    return false, code, false
end

local function IsCooldownViewerAvailable()
    local adapter = YUI.API and YUI.API.CooldownViewer
    if not (adapter and type(adapter.IsAvailable) == "function") then
        return true
    end
    local ok, available, reason = pcall(adapter.IsAvailable, adapter)
    if not ok then return false, "availability-check-failed" end
    if available == false then return false, reason or "viewer-unavailable" end
    return true
end

function BlizzardSettings:ApplyCooldownManager(reason)
    if self.active ~= true or self.resourceOnly == true then
        self.pending[COOLDOWN_CVAR] = nil
        return true
    end
    if reason == "cvar-update" and IsContestBlocked(COOLDOWN_CVAR) then
        return false, "contested"
    end
    local available, code = IsCooldownViewerAvailable()
    if not available then
        self.pending[COOLDOWN_CVAR] = true
        RecordDiagnostic("blizzard-settings-cooldown-unavailable", code)
        WarnCVar(COOLDOWN_CVAR, false)
        return false, code
    end
    return self:WriteCVar(COOLDOWN_CVAR, true)
end

local function ShouldHidePersonalResource(settings)
    return settings.active == true
        and (not YHUD.consolePreferences
            or YHUD.consolePreferences.autoHidePersonalResource ~= false)
        and YHUD:HasEnabledResourceGroup(settings.profile)
        and not (YHUD.IsResourceLevelRestricted and YHUD:IsResourceLevelRestricted())
end

function BlizzardSettings:ApplyPersonalResource(reason)
    local shouldHide = ShouldHidePersonalResource(self)
    if reason == "cvar-update" and IsContestBlocked(PERSONAL_RESOURCE_CVAR) then
        return false, "contested"
    end

    if shouldHide then
        local current, code = ReadCVarBoolean(PERSONAL_RESOURCE_CVAR)
        if current == nil then
            self.pending[PERSONAL_RESOURCE_CVAR] = true
            RecordDiagnostic("blizzard-settings-personal-unavailable", code)
            WarnCVar(PERSONAL_RESOURCE_CVAR, false)
            return false, code
        end
        if current == false then
            self.pending[PERSONAL_RESOURCE_CVAR] = nil
            return true
        end

        local baselineCreated = GetPersonalResourceBaseline() == nil
        if baselineCreated then
            local stored, storageCode = SetPersonalResourceBaseline(true)
            if not stored then
                self.pending[PERSONAL_RESOURCE_CVAR] = true
                RecordDiagnostic(
                    "blizzard-settings-personal-storage",
                    storageCode
                )
                WarnCVar(PERSONAL_RESOURCE_CVAR, false)
                return false, storageCode
            end
        end
        local applied, applyCode = self:WriteCVar(
            PERSONAL_RESOURCE_CVAR,
            false
        )
        if not applied and baselineCreated then
            ClearPersonalResourceOwnership()
        end
        return applied, applyCode
    end

    local baseline = GetPersonalResourceBaseline()
    if baseline == nil then
        self.pending[PERSONAL_RESOURCE_CVAR] = nil
        return true
    end
    local current, code = ReadCVarBoolean(PERSONAL_RESOURCE_CVAR)
    if current == nil then
        self.pending[PERSONAL_RESOURCE_CVAR] = true
        RecordDiagnostic("blizzard-settings-personal-restore", code)
        WarnCVar(PERSONAL_RESOURCE_CVAR, false)
        return false, code
    end
    if current == baseline then
        self.pending[PERSONAL_RESOURCE_CVAR] = nil
        ClearPersonalResourceOwnership()
        return true
    end
    local restored, restoreCode = self:WriteCVar(
        PERSONAL_RESOURCE_CVAR,
        baseline
    )
    if restored then ClearPersonalResourceOwnership() end
    return restored, restoreCode
end

function BlizzardSettings:Sync(profile, resourceOnly, reason)
    if type(profile) == "table" then self.profile = profile end
    if type(resourceOnly) == "boolean" then
        self.resourceOnly = resourceOnly
    elseif type(profile) == "table" then
        self.resourceOnly = profile._yhudInitialResourceOnly == true
    end
    reason = reason or "sync"
    if reason ~= "cvar-update" and reason ~= "player-regen" then
        ResetContestState()
    end
    local cooldownOK, cooldownCode = self:ApplyCooldownManager(reason)
    local resourceOK, resourceCode = self:ApplyPersonalResource(reason)
    if cooldownOK and resourceOK then return true end
    return false, cooldownCode or resourceCode
end

function BlizzardSettings.owner:OnEvent(eventName, cvarName)
    if eventName == "CVAR_UPDATE" then
        return BlizzardSettings:OnCVarUpdate(cvarName)
    end
    if eventName == "PLAYER_REGEN_ENABLED" then
        return BlizzardSettings:OnPlayerRegenEnabled()
    end
    return false
end

function BlizzardSettings:RegisterSignals()
    local owner = self.owner
    if owner.registered == true then return true end
    if not (YUI.Event and type(YUI.Event.On) == "function") then
        return false
    end
    YUI.Event:On("CVAR_UPDATE", "OnEvent", owner, {
        moduleId = "YHUD.BlizzardSettings",
    })
    YUI.Event:On("PLAYER_REGEN_ENABLED", "OnEvent", owner, {
        moduleId = "YHUD.BlizzardSettings",
    })
    owner.registered = true
    return true
end

function BlizzardSettings:UnregisterSignals()
    local owner = self.owner
    if owner.registered == true
        and YUI.Event and type(YUI.Event.OffOwner) == "function" then
        YUI.Event:OffOwner(owner)
    end
    owner.registered = false
end

function BlizzardSettings:GetDesiredValue(name)
    if name == COOLDOWN_CVAR then
        return self.active == true and self.resourceOnly ~= true and true or nil
    end
    if name == PERSONAL_RESOURCE_CVAR then
        if ShouldHidePersonalResource(self) then
            return false
        end
        return GetPersonalResourceBaseline()
    end
    return nil
end

function BlizzardSettings:OnCVarUpdate(cvarName)
    if self.active ~= true or self.writeDepth > 0 then return false end
    local normalized = type(cvarName) == "string"
        and string.lower(cvarName) or ""
    local name
    if normalized == string.lower(COOLDOWN_CVAR) then
        name = COOLDOWN_CVAR
    elseif normalized == string.lower(PERSONAL_RESOURCE_CVAR) then
        name = PERSONAL_RESOURCE_CVAR
    else
        return false
    end
    local desired = self:GetDesiredValue(name)
    if desired == nil then return false end
    local current = ReadCVarBoolean(name)
    if current == desired then return false end
    if RegisterContest(name) then return false end
    return self:QueueSync("cvar-update")
end

function BlizzardSettings:OnPlayerRegenEnabled()
    if self.active ~= true then return false end
    if not self.pending[COOLDOWN_CVAR]
        and not self.pending[PERSONAL_RESOURCE_CVAR] then
        return false
    end
    return self:Sync(nil, nil, "player-regen")
end

function BlizzardSettings:Initialize(productEnabled)
    self.active = false
    self.profile = nil
    self.resourceOnly = true
    self:CancelPendingSync()
    self:UnregisterSignals()
    if productEnabled ~= true then
        return self:ApplyPersonalResource("initialize-recovery")
    end
    return true
end

function BlizzardSettings:Enable(profile, resourceOnly, reason)
    self.generation = self.generation + 1
    self:CancelPendingSync()
    self.active = true
    self.profile = profile
    self.resourceOnly = resourceOnly == true
    self:RegisterSignals()
    return self:Sync(profile, self.resourceOnly, reason or "enable")
end

function BlizzardSettings:Disable(reason)
    self.generation = self.generation + 1
    self:CancelPendingSync()
    self.active = false
    self.profile = nil
    self.resourceOnly = true
    local restored, code = self:ApplyPersonalResource(
        reason or "disable"
    )
    self.pending[COOLDOWN_CVAR] = nil
    self:UnregisterSignals()
    ResetContestState()
    return restored, code
end

function BlizzardSettings:GetState(target)
    target = target or {}
    target.active = self.active == true
    target.resourceOnly = self.resourceOnly == true
    target.cooldownViewerEnabled = ReadCVarBoolean(COOLDOWN_CVAR)
    target.personalResourceEnabled = ReadCVarBoolean(
        PERSONAL_RESOURCE_CVAR
    )
    target.personalResourceBaseline = GetPersonalResourceBaseline()
    target.cooldownPending = self.pending[COOLDOWN_CVAR] == true
    target.personalResourcePending =
        self.pending[PERSONAL_RESOURCE_CVAR] == true
    target.cooldownContested = IsContestBlocked(COOLDOWN_CVAR)
    target.personalResourceContested =
        IsContestBlocked(PERSONAL_RESOURCE_CVAR)
    return target
end

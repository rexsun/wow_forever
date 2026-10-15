local _, addonTable = ...
local YUI = _G.YUI or addonTable
local Native = YUI and YUI.NativeInterface
local System = YUI and YUI.API and YUI.API.System
local Security = YUI and YUI.API and YUI.API.Security
if not (Native and Native.IS_SUITE and YUI.IsForever == true and System and Security) then return end

local CVARS = {
    { "outlineModeShowLootEffectWhenDisabled", "1" },
    { "graphicsOutlineMode", "0" },
    { "OutlineEngineMode", "0" },
    { "raidGraphicsOutlineMode", "0" },
    { "RAIDOutlineEngineMode", "0" },
}
local WATCHED = { graphicsquality = true, raidgraphicsquality = true }
for _, entry in ipairs(CVARS) do WATCHED[entry[1]:lower()] = true end

local owner, recoveryOwner = {}, {}
local watching, recovering, applying = false, false, false
local timer, pending, lastError
local applyWrites, restoreWrites = 0, 0
local Reconcile

local function Desired()
    return Native.runtimeEnabled == true and Native:GetConfig().questLootSparkles == true
end

local function Read(name)
    local value = System.GetCVarSafe(name)
    if Security.IsSecretValue(value) or type(value) ~= "string" then return nil end
    return value
end

local function Storage(create)
    local global = YUI.DB and YUI.DB.GetGlobal and YUI.DB:GetGlobal(Native.PRODUCT_ID)
    if type(global) ~= "table" then return nil end
    local saved = global.nativeQuestLootSparkles
    if type(saved) ~= "table" and create then
        saved = {}
        global.nativeQuestLootSparkles = saved
    end
    return type(saved) == "table" and saved or nil
end

local function CancelTimer()
    if timer then timer:Cancel(); timer = nil end
end

local function OnRecovery()
    if not Security.InCombatLockdown() then Reconcile() end
end

local function SetRecovery(enabled)
    if enabled == recovering then return end
    recovering = enabled
    if enabled then
        YUI.Event:On("PLAYER_REGEN_ENABLED", OnRecovery, recoveryOwner, { moduleId = Native.MODULE_ID })
    else
        YUI.Event:OffOwner(recoveryOwner)
    end
end

local function Write(name, value, restoring)
    if Read(name) == value then return true end
    if not System.SetCVarSafe(name, value) or Read(name) ~= value then
        lastError = name
        return false
    end
    if restoring then restoreWrites = restoreWrites + 1 else applyWrites = applyWrites + 1 end
    return true
end

Reconcile = function()
    CancelTimer()
    local desired = Desired()
    local saved = Storage(desired)
    if not saved then
        pending = nil
        lastError = desired and "storage-unavailable" or nil
        SetRecovery(false)
        return false
    end
    if Security.InCombatLockdown() then
        pending = desired and "apply" or (next(saved) ~= nil and "restore" or nil)
        SetRecovery(pending ~= nil)
        return true
    end

    pending, lastError = nil, nil
    applying = true
    if desired then
        local sparkleName = CVARS[1][1]
        if Read(sparkleName) == nil then
            applying = false
            lastError = sparkleName
            SetRecovery(false)
            return false
        end
        -- Capture every value before writing: graphics settings can change engine CVars too.
        for _, entry in ipairs(CVARS) do
            local name = entry[1]
            if saved[name] == nil then saved[name] = Read(name) end
        end
        -- Do not turn outlines off if this client rejects the native sparkle switch.
        if Write(sparkleName, CVARS[1][2], false) then
            for index = 2, #CVARS do
                local name, value = CVARS[index][1], CVARS[index][2]
                if saved[name] ~= nil then Write(name, value, false) end
            end
        end
    else
        for _, entry in ipairs(CVARS) do
            local name = entry[1]
            local original = saved[name]
            if type(original) == "string" and Write(name, original, true) then saved[name] = nil end
        end
        if next(saved) ~= nil then pending = "restore" end
    end
    applying = false
    SetRecovery(pending ~= nil)
    return lastError == nil
end

local function OnTimer()
    timer = nil
    Reconcile()
end

local function Schedule(delay)
    CancelTimer()
    if C_Timer and C_Timer.NewTimer then timer = C_Timer.NewTimer(delay, OnTimer) end
end

local function OnLogin()
    Reconcile()
    if Desired() then Schedule(5) end
end

local function OnCVarChanged(_, name)
    if applying or not Desired() or Security.IsSecretValue(name) or type(name) ~= "string" then return end
    name = name:lower()
    if not WATCHED[name] then return end
    if name ~= "graphicsquality" and name ~= "raidgraphicsquality" then
        local changed = false
        for _, entry in ipairs(CVARS) do
            local current = Read(entry[1])
            if current ~= nil and current ~= entry[2] then changed = true; break end
        end
        if not changed then return end
    end
    Schedule(1)
end

local function StopWatching()
    CancelTimer()
    if watching then YUI.Event:OffOwner(owner) end
    watching = false
end

function Native:RefreshQuestLootSparkles()
    if not Desired() then
        StopWatching()
        return Reconcile()
    end
    if not watching then
        watching = true
        local options = { moduleId = self.MODULE_ID, traceName = "NativeInterface:quest-sparkles" }
        YUI.Event:On("PLAYER_LOGIN", OnLogin, owner, options)
        YUI.Event:On("VARIABLES_LOADED", OnLogin, owner, options)
        YUI.Event:On("CVAR_UPDATE", OnCVarChanged, owner, options)
        if type(IsLoggedIn) ~= "function" or IsLoggedIn() then OnLogin() end
        return true
    end
    return Reconcile()
end

function Native:ReleaseQuestLootSparkles()
    StopWatching()
    return Reconcile()
end

function Native:GetQuestLootSparklesDiagnostics()
    local saved, count = Storage(false), 0
    if saved then for _, entry in ipairs(CVARS) do if saved[entry[1]] ~= nil then count = count + 1 end end end
    return {
        enabled = Desired(), watching = watching, recovering = recovering,
        timerPending = timer ~= nil, pending = pending, savedCVars = count,
        applyWrites = applyWrites, restoreWrites = restoreWrites, lastError = lastError,
    }
end

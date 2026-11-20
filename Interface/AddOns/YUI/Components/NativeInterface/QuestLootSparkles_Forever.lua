local _, addonTable = ...
local YUI = _G.YUI or addonTable
local Native = YUI and YUI.NativeInterface
local System = YUI and YUI.API and YUI.API.System
local Security = YUI and YUI.API and YUI.API.Security
if not (Native and Native.IS_SUITE and YUI.IsForever == true and System and Security) then return end

local SPARKLE_CVAR = "outlineModeShowLootEffectWhenDisabled"
local SPARKLE_EVENT_NAME = SPARKLE_CVAR:lower()
local LEGACY_OUTLINES = {
    { "graphicsOutlineMode", "OutlineEngineMode" },
    { "raidGraphicsOutlineMode", "RAIDOutlineEngineMode" },
}
local WATCHED = { graphicsquality = true, raidgraphicsquality = true, [SPARKLE_EVENT_NAME] = true }

local owner, recoveryOwner = {}, {}
local watching, applying = false, false
local timer, recoveryEvent, pending, lastError
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

local function IsPlayerLoggedIn()
    return type(IsLoggedIn) ~= "function" or IsLoggedIn()
end

local function SetRecovery(event)
    if event == recoveryEvent then return end
    if recoveryEvent then YUI.Event:OffOwner(recoveryOwner) end
    recoveryEvent = event
    if event then
        YUI.Event:On(event, Reconcile, recoveryOwner, { moduleId = Native.MODULE_ID })
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

local function RestoreLegacyOutline(saved, graphicsName, engineName)
    local graphics, engine = saved[graphicsName], saved[engineName]
    if graphics == nil and engine == nil then return true end

    if type(graphics) == "string" then
        local current = Read(graphicsName)
        if current and current ~= "0" and current ~= graphics then
            saved[graphicsName], saved[engineName] = nil, nil
            return true
        end
        -- The graphics write can also change the engine value. Keep the pair until both are settled.
        if not Write(graphicsName, graphics, true) then return false end
    end
    if type(engine) == "string" and not Write(engineName, engine, true) then return false end
    saved[graphicsName], saved[engineName] = nil, nil
    return true
end

Reconcile = function()
    CancelTimer()
    local desired = Desired()
    local loggedIn = IsPlayerLoggedIn()
    local saved = Storage(desired and loggedIn)
    if not loggedIn then
        pending = not desired and saved and next(saved) ~= nil and "restore" or nil
        SetRecovery(pending and "PLAYER_LOGIN")
        return true
    end
    if not saved then
        pending = nil
        lastError = desired and "storage-unavailable" or nil
        SetRecovery(nil)
        return false
    end
    if Security.InCombatLockdown() then
        pending = desired and "apply" or (next(saved) ~= nil and "restore" or nil)
        SetRecovery(pending and "PLAYER_REGEN_ENABLED")
        return true
    end

    pending, lastError = nil, nil
    applying = true
    for _, pair in ipairs(LEGACY_OUTLINES) do
        if not RestoreLegacyOutline(saved, pair[1], pair[2]) then pending = "restore" end
    end

    local original = saved[SPARKLE_CVAR]
    if desired then
        local current = Read(SPARKLE_CVAR)
        if current then
            if original == nil then saved[SPARKLE_CVAR] = current end
            Write(SPARKLE_CVAR, "1", false)
        else
            lastError = SPARKLE_CVAR
        end
    elseif type(original) == "string" then
        if Write(SPARKLE_CVAR, original, true) then
            saved[SPARKLE_CVAR] = nil
        else
            pending = "restore"
        end
    end
    applying = false
    SetRecovery(pending and "PLAYER_REGEN_ENABLED")
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
    if not IsPlayerLoggedIn() then return end
    Reconcile()
    if Desired() then Schedule(5) end
end

local function OnCVarChanged(_, name)
    if applying or not Desired() or Security.IsSecretValue(name) or type(name) ~= "string" then return end
    name = name:lower()
    if not WATCHED[name] then return end
    if name == SPARKLE_EVENT_NAME then
        local current = Read(SPARKLE_CVAR)
        if current == nil or current == "1" then return end
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
        OnLogin()
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
    if saved then for _ in pairs(saved) do count = count + 1 end end
    return {
        enabled = Desired(), watching = watching, recovering = recoveryEvent ~= nil,
        timerPending = timer ~= nil, pending = pending, savedCVars = count,
        applyWrites = applyWrites, restoreWrites = restoreWrites, lastError = lastError,
    }
end

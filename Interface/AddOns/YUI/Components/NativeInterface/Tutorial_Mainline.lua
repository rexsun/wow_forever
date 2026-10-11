local _, addonTable = ...
local YUI = _G.YUI or addonTable
local Native = YUI and YUI.NativeInterface
if not (Native and YUI.IsRetail == true) then return end

local Event = YUI.Event
local SYSTEM_ID = "TutorialSupertracking"
local eventOwner = {}
local hookInstalled = false
local loadWatching = false
local suppressions = 0
local lastError

local function IsDesired()
    return Native.runtimeEnabled == true
        and Native:GetConfig().suppressSupertrackTutorial == true
end

local function AcknowledgeCurrent()
    local helpTip = _G.HelpTip
    if not (helpTip and type(helpTip.AcknowledgeSystem) == "function") then return false end
    local ok, err = pcall(helpTip.AcknowledgeSystem, helpTip, SYSTEM_ID)
    if not ok then lastError = tostring(err) end
    return ok
end

local function MarkComplete()
    if type(_G.SetCVarBitfield) ~= "function"
        or type(_G.LE_FRAME_TUTORIAL_HOW_TO_SUPERTRACK) ~= "number" then
        return false
    end
    local ok, err = pcall(
        _G.SetCVarBitfield,
        "closedInfoFrames",
        _G.LE_FRAME_TUTORIAL_HOW_TO_SUPERTRACK,
        true
    )
    if not ok then lastError = tostring(err) end
    return ok
end

local function OnHelpTipShown(_, _, info)
    if not IsDesired() or type(info) ~= "table" or info.system ~= SYSTEM_ID then return end
    suppressions = suppressions + 1
    MarkComplete()
    AcknowledgeCurrent()
end

local function EnsureHook()
    if hookInstalled then return true end
    local helpTip = _G.HelpTip
    if not (helpTip and type(helpTip.Show) == "function" and type(_G.hooksecurefunc) == "function") then
        return false
    end
    local ok, err = pcall(_G.hooksecurefunc, helpTip, "Show", OnHelpTipShown)
    if not ok then
        lastError = tostring(err)
        return false
    end
    hookInstalled = true
    return true
end

local function StopLoadWatching()
    if loadWatching and Event and Event.OffOwner then Event:OffOwner(eventOwner) end
    loadWatching = false
end

local function OnAddonLoaded(_, addonName)
    if addonName ~= "Blizzard_Tutorials" and addonName ~= "Blizzard_SharedXML" then return end
    if EnsureHook() then
        StopLoadWatching()
        if IsDesired() then
            MarkComplete()
            AcknowledgeCurrent()
        end
    end
end

local function EnsureLoadWatching()
    if loadWatching or not (Event and Event.On) then return end
    Event:On("ADDON_LOADED", OnAddonLoaded, eventOwner, {
        moduleId = Native.MODULE_ID,
        traceName = "NativeInterface:tutorial-load",
    })
    loadWatching = true
end

function Native:RefreshTutorial()
    if not IsDesired() then
        StopLoadWatching()
        return true
    end
    MarkComplete()
    AcknowledgeCurrent()
    if not EnsureHook() then EnsureLoadWatching() end
    return true
end

function Native:ReleaseTutorial()
    StopLoadWatching()
    return true
end

function Native:GetTutorialDiagnostics()
    return {
        hookInstalled = hookInstalled,
        loadWatching = loadWatching,
        suppressions = suppressions,
        lastError = lastError,
    }
end

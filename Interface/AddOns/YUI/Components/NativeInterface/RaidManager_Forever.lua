local _, addonTable = ...
local YUI = _G.YUI or addonTable
local Native = YUI and YUI.NativeInterface
local Security = YUI and YUI.API and YUI.API.Security
if not (Native and YUI.IsForever == true and Security) then return end

local owner, recoveryOwner = {}, {}
local states = setmetatable({}, { __mode = "k" })
local targets
local GUARD_METHODS = { "IsForbidden", "HasSecretValues" }
local MODERN_PANEL_KEYS = { "BottomButtons", "GamepadInputIcon", "FrameGlow", "LeftJumpHint", "RightJumpHint", "FocusJumpHint" }
local watching, recovering = false, false
local lastReason, hideWrites, restoreWrites = "inactive", 0, 0
local layout, targetCount, failedCheck, lastTarget, lastMethod, lastError
local Refresh, Suppress

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function ReadState(frame, mouse)
    local ok, value = Security.SafeMethod("NativeInterface:raid-manager-state", frame, mouse and "IsMouseEnabled" or "IsShown")
    if ok and Public(value) and type(value) == "boolean" then return value end
end

local function WriteState(frame, state, value)
    lastTarget = state.label
    lastMethod = state.mouse and "EnableMouse" or (value and "Show" or "Hide")
    state.writing = true
    local ok, err
    if state.mouse then
        ok, err = Security.SafeMethod("NativeInterface:raid-manager-mouse", frame, "EnableMouse", value)
    else
        ok, err = Security.SafeMethod("NativeInterface:raid-manager-visibility", frame, lastMethod)
    end
    state.writing = false
    if not ok and Public(err) and type(err) == "string" then lastError = err end
    return ok
end

local function Usable(frame)
    if not frame or not Public(frame) then return false end
    for _, method in ipairs(GUARD_METHODS) do
        if type(frame[method]) == "function" then
            local ok, value = Security.SafeMethod("NativeInterface:raid-manager-guard", frame, method)
            if not (ok and Public(value) and value == false) then return false end
        end
    end
    return true
end

local function OnRecovery()
    if not Security.InCombatLockdown() then Refresh() end
end

local function SetRecovery(enabled)
    if enabled == recovering then return end
    recovering = enabled
    if enabled then
        YUI.Event:On("PLAYER_REGEN_ENABLED", OnRecovery, recoveryOwner, {
            moduleId = Native.MODULE_ID, traceName = "NativeInterface:raid-manager-recovery",
        })
    else
        YUI.Event:OffOwner(recoveryOwner)
    end
end

local function Restore(frame, state)
    if not state.owned then return true end
    lastTarget, lastMethod = state.label, "restore"
    if Security.InCombatLockdown() then lastReason = "combat-deferred"; return false end
    if not Usable(frame) then lastReason = "frame-unavailable"; return false end
    if state.wanted == nil then lastReason = "state-unknown"; return false end
    lastMethod = state.mouse and "IsMouseEnabled" or "IsShown"
    local value = ReadState(frame, state.mouse)
    if value == nil then lastReason = "state-unknown"; return false end
    if value ~= state.wanted then
        if not WriteState(frame, state, state.wanted) then lastReason = "restore-failed"; return false end
        restoreWrites = restoreWrites + 1
    end
    state.owned = false
    return true
end

local function ReleaseAll(keep)
    local pending = false
    for frame, state in pairs(states) do
        if not (keep and keep[frame]) and not Restore(frame, state) then pending = true end
    end
    return not pending
end

Suppress = function(frame, state)
    lastTarget, lastMethod = state.label, "guard"
    if not Usable(frame) then lastReason = "frame-unavailable"; return false end
    if Security.InCombatLockdown() then
        -- Native refreshes may Show a visual child in combat. Never write a protected or unknown object.
        lastMethod = "IsProtected"
        local ok, protected = Security.SafeMethod("NativeInterface:raid-manager-protected", frame, "IsProtected")
        if not (ok and Public(protected) and protected == false) then
            SetRecovery(true); lastReason = "combat-deferred"; return false
        end
    end
    lastMethod = state.mouse and "IsMouseEnabled" or "IsShown"
    local value = ReadState(frame, state.mouse)
    if value == nil then lastReason = "state-unknown"; return false end
    if not value then return true end
    if not WriteState(frame, state, false) then lastReason = "hide-failed"; return false end
    state.owned = true
    hideWrites = hideWrites + 1
    lastReason = "hidden"
    return true
end

local function OnNativeIntent(frame, value)
    local state = states[frame]
    if not state or state.writing or not (watching or state.owned) then return end
    if not Public(value) or type(value) ~= "boolean" then state.wanted = nil; return end
    state.wanted = value
    if not value then
        -- Native collapse/Hide or mouse disabling takes precedence over our saved intent.
        state.owned = false
    elseif watching and targets and targets[frame] then
        Suppress(frame, state)
    end
end

local function OnNativeShow(frame)
    OnNativeIntent(frame, true)
end

local function OnNativeHide(frame)
    OnNativeIntent(frame, false)
end

local function OnNativeSetShown(frame, shown)
    OnNativeIntent(frame, shown)
end

local function AttachHook(frame, state, method, callback)
    local ok, err = Security.SafeHook("NativeInterface:raid-manager-" .. method, frame, method, callback)
    if not ok then
        lastTarget, lastMethod = state.label, method
        if Public(err) and type(err) == "string" then lastError = err end
    end
    return ok
end

local function EnsureHooks(frame, mouse, label)
    local state = states[frame]
    if not state or not state.owned then
        local value = ReadState(frame, mouse)
        if value == nil then return end
        state = state or { mouse = mouse }
        state.wanted = value
        states[frame] = state
    end
    state.label = label
    if mouse then
        if not state.mouseHook then
            state.mouseHook = AttachHook(frame, state, "EnableMouse", OnNativeIntent)
        end
        if state.mouseHook then return state end
        return
    end
    if not state.showHook then
        state.showHook = AttachHook(frame, state, "Show", OnNativeShow)
    end
    if not state.hideHook then
        state.hideHook = AttachHook(frame, state, "Hide", OnNativeHide)
    end
    if not state.setShownHook then
        state.setShownHook = AttachHook(frame, state, "SetShown", OnNativeSetShown)
    end
    if state.showHook and state.hideHook and state.setShownHook then return state end
end

local function IsChild(frame, parent)
    if not Usable(frame) then return false end
    local ok, value = Security.SafeMethod("NativeInterface:raid-manager-parent", frame, "GetParent")
    return ok and Public(value) and value == parent
end

local function StructureFailure(check)
    failedCheck = check
    return nil, "structure-unconfirmed"
end

local function AddPanelChild(frame, key, list, keep, required)
    local child = frame[key]
    if not Public(child) then failedCheck = key .. ":unavailable"; return false end
    if not child and not required then return true end
    if not IsChild(child, frame) then failedCheck = key .. ":parent"; return false end
    if not keep[child] then list[#list + 1] = child; keep[child] = key end
    return true
end

local function HealthOutsideVisuals(health, keep, manager)
    if not health then return true end
    local node = health
    -- Health containers may be reparented to unnamed holders; confirm that no hidden visual is an ancestor.
    for _ = 1, 32 do
        if not Public(node) then return false end
        if node == manager or node == UIParent then return true end
        if not Usable(node) then return false end
        if keep[node] then return false end
        local ok, parent = Security.SafeMethod("NativeInterface:raid-manager-health-parent", node, "GetParent")
        if not (ok and Public(parent)) then return false end
        if not parent then return true end
        node = parent
    end
    return false
end

local function CollectTargets(frame)
    layout, targetCount = nil, 0
    local container = _G.CompactRaidFrameContainer
    if not IsChild(frame, UIParent) then return StructureFailure("manager:parent") end
    if not (Public(container) and Usable(container) and Public(frame.container) and frame.container == container) then
        return StructureFailure("health-container:identity")
    end
    local list, keep = {}, { [frame] = "manager.mouse" }
    if not AddPanelChild(frame, "displayFrame", list, keep, true) then return nil, "structure-unconfirmed" end
    if Public(frame.toggleButtonForward) and frame.toggleButtonForward then
        layout = "modern"
        for _, key in ipairs({ "toggleButtonForward", "toggleButtonBack" }) do
            if not AddPanelChild(frame, key, list, keep, true) then return nil, "structure-unconfirmed" end
        end
        for _, key in ipairs(MODERN_PANEL_KEYS) do
            if not AddPanelChild(frame, key, list, keep, false) then return nil, "structure-unconfirmed" end
        end
    else
        layout = "classic"
        if not AddPanelChild(frame, "toggleButton", list, keep, true) then return nil, "structure-unconfirmed" end
    end
    local regions = { Security.SafeMethod("NativeInterface:raid-manager-regions", frame, "GetRegions") }
    if not regions[1] then return StructureFailure("manager:GetRegions") end
    for index = 2, #regions do
        local region = regions[index]
        if not IsChild(region, frame) then return StructureFailure("region:parent") end
        local ok, kind = Security.SafeMethod("NativeInterface:raid-manager-region-type", region, "GetObjectType")
        if not (ok and Public(kind) and (kind == "Texture" or kind == "FontString")) then
            return StructureFailure("region:type")
        end
        if not keep[region] then list[#list + 1] = region; keep[region] = "region:" .. (index - 1) end
    end
    if not HealthOutsideVisuals(container, keep, frame) then return StructureFailure("raid-health:ancestor") end
    if not HealthOutsideVisuals(_G.CompactPartyFrame, keep, frame) then return StructureFailure("party-health:ancestor") end
    -- Validate every state before installing hooks or changing any visual.
    if ReadState(frame, true) == nil then failedCheck = "manager:mouse-state"; return nil, "state-unknown" end
    for _, visual in ipairs(list) do
        if ReadState(visual, false) == nil then failedCheck = keep[visual] .. ":shown-state"; return nil, "state-unknown" end
    end
    list[#list + 1] = frame -- Disable only the parent's hit area; child health input remains enabled.
    targetCount = #list
    return list, keep
end

local function OnWorldEntered()
    if watching then Refresh() end
end

local function OnAddonLoaded(_, addonName)
    if watching and addonName == "Blizzard_CompactRaidFrames" then Refresh() end
end

local function SetWatching(enabled)
    if enabled == watching then return end
    watching = enabled
    if enabled then
        local options = { moduleId = Native.MODULE_ID, traceName = "NativeInterface:raid-manager" }
        YUI.Event:On("ADDON_LOADED", OnAddonLoaded, owner, options)
        YUI.Event:On("PLAYER_ENTERING_WORLD", OnWorldEntered, owner, options)
    else
        YUI.Event:OffOwner(owner)
    end
end

Refresh = function()
    failedCheck, lastError = nil, nil
    local enabled = Native.runtimeEnabled and Native:GetConfig().hideRaidManager == true
    SetWatching(enabled)
    if not enabled then
        targets = nil
        local restored = ReleaseAll()
        SetRecovery(not restored)
        if restored then lastReason = "inactive" end
        return restored
    end
    if Security.InCombatLockdown() then
        SetRecovery(true); lastReason = "combat-deferred"; return false
    end
    local frame = _G.CompactRaidFrameManager
    local list, keep
    if Usable(frame) then list, keep = CollectTargets(frame) else keep = "frame-unavailable" end
    if not list then
        targets = nil
        SetRecovery(not ReleaseAll())
        lastReason = keep; return false
    end
    SetRecovery(not ReleaseAll(keep))
    for _, visual in ipairs(list) do
        if not EnsureHooks(visual, visual == frame, keep[visual]) then
            local target, method, err = lastTarget, lastMethod, lastError
            targets = nil
            SetRecovery(not ReleaseAll())
            lastTarget, lastMethod, lastError = target, method, err
            lastReason = "hooks-unavailable"; return false
        end
    end
    targets = keep
    for _, visual in ipairs(list) do
        if not Suppress(visual, states[visual]) then
            local reason, target, method, err = lastReason, lastTarget, lastMethod, lastError
            targets = nil
            SetRecovery(not ReleaseAll())
            lastTarget, lastMethod, lastError = target, method, err
            lastReason = reason; return false
        end
    end
    lastReason = "hidden"
    return true
end

function Native:RefreshRaidManager()
    return Refresh()
end

function Native:ReleaseRaidManager()
    SetWatching(false)
    targets = nil
    local restored = ReleaseAll()
    SetRecovery(not restored)
    if restored then lastReason = "inactive" end
    return restored
end

function Native:GetRaidManagerDiagnostics()
    local owned = 0
    for _, state in pairs(states) do if state.owned then owned = owned + 1 end end
    return {
        implementation = "visual-children-v3", layout = layout, targetCount = targetCount,
        watching = watching, recovering = recovering, ownedFrames = owned,
        hideWrites = hideWrites, restoreWrites = restoreWrites, lastReason = lastReason,
        failedCheck = failedCheck, lastTarget = lastTarget, lastMethod = lastMethod, lastError = lastError,
    }
end

local _, addonTable = ...
local YUI = _G.YUI or addonTable
local Native = YUI and YUI.NativeInterface
local Security = YUI and YUI.API and YUI.API.Security
if not (Native and YUI.IsForever == true and Security) then return end

local owner, recoveryOwner = {}, {}
local states = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local layoutHooks = setmetatable({}, { __mode = "k" })
local watching, recovering, refreshing = false, false, false
local lastReason, hideWrites, restoreWrites = "inactive", 0, 0
local Refresh, ReleaseAll

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Number(value)
    return Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function Usable(frame)
    return frame and (not frame.IsForbidden or not frame:IsForbidden())
        and (not frame.HasSecretValues or not frame:HasSecretValues())
end

local function Shown(frame, method)
    local ok, value = Security.SafeMethod("NativeInterface:bag-sort-visible", frame, method or "IsShown")
    local known = ok and Public(value) and type(value) == "boolean"
    return known and value == true, known
end

local function Rect(frame)
    local ok, x, y, width, height = Security.SafeMethod("NativeInterface:bag-sort-rect", frame, "GetRect")
    local scaleOK, scale = Security.SafeMethod("NativeInterface:bag-sort-scale", frame, "GetEffectiveScale")
    if not (ok and scaleOK and Number(x) and Number(y) and Number(width) and Number(height)
        and Number(scale) and width > 0 and height > 0 and scale > 0) then return end
    x, y, width, height = x * scale, y * scale, (x + width) * scale, (y + height) * scale
    if Number(x) and Number(y) and Number(width) and Number(height) then return x, y, width, height end
end

local function Overlaps(left, right)
    local ax, ay, ar, at = Rect(left)
    local bx, by, br, bt = Rect(right)
    return ax ~= nil and bx ~= nil and ax < br and bx < ar and ay < bt and by < at
end

local function OnRecovery()
    if Security.InCombatLockdown() then return end
    if watching then Refresh("combat-ended") else ReleaseAll() end
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

local function Restore(frame, state)
    if not state.owned then return true end
    if not state.wantedShown then state.owned = false; return true end
    if Security.InCombatLockdown() then return false end
    state.writing = true
    local ok = Security.SafeMethod("NativeInterface:bag-sort-restore", frame, "Show")
    state.writing = false
    if ok then state.owned = false; restoreWrites = restoreWrites + 1 end
    return ok
end

ReleaseAll = function(except)
    local pending = false
    for frame, state in pairs(states) do
        if frame ~= except and not Restore(frame, state) then pending = true end
    end
    SetRecovery(pending)
end

local function OnNativeShow(frame)
    local state = states[frame]
    if not state or state.writing or not (watching or state.owned) then return end
    state.wantedShown = true
    if watching then Refresh("native-show") end
end

local function OnNativeHide(frame)
    local state = states[frame]
    if not state or state.writing or not (watching or state.owned) then return end
    -- Observe Hide calls even when the frame is already hidden by this feature.
    state.wantedShown = false
    state.owned = false
end

local function OnNativeSetShown(frame, shown)
    local state = states[frame]
    if not state or state.writing or not (watching or state.owned) then return end
    if not Public(shown) then state.owned = false; state.wantedShown = false; return end
    if shown then OnNativeShow(frame) else OnNativeHide(frame) end
end

local function OnLayout()
    if watching then Refresh("bag-layout") end
end

local function HookLayout(frame)
    if hooked[frame] then return end
    local showOK = Security.SafeMethod("NativeInterface:bag-sort-on-show", frame, "HookScript", "OnShow", OnLayout)
    if showOK then hooked[frame] = true end
end

local function EnsureButton(frame)
    local state = states[frame]
    if not state then
        state = { wantedShown = Shown(frame) }
        states[frame] = state
    end
    if not state.showHook then
        state.showHook = Security.SafeHook("NativeInterface:bag-sort-show", frame, "Show", OnNativeShow)
    end
    if not state.hideHook then
        state.hideHook = Security.SafeHook("NativeInterface:bag-sort-hide", frame, "Hide", OnNativeHide)
    end
    if not (state.showHook and state.hideHook) then return end
    if not state.setShownHook and type(frame.SetShown) == "function" then
        state.setShownHook = Security.SafeHook("NativeInterface:bag-sort-set-shown", frame, "SetShown", OnNativeSetShown)
    end
    return state
end

local function Evaluate()
    local input = _G.InputUtil
    local inputOK, mkb = Security.SafeCall("NativeInterface:bag-sort-input", input and input.IsMKBUIEnabled)
    if not (inputOK and Public(mkb) and mkb == true) then
        ReleaseAll(); lastReason = "keyboard-mouse-unconfirmed"; return
    end
    local container, bar, sort = _G.ContainerFrameCombinedBags, _G.GamepadBagBar, _G.BagItemAutoSortButton
    local button = bar and bar.BackpackButton
    if not (Usable(container) and Usable(bar) and Usable(sort) and Usable(button)
        and bar:GetParent() == container and button:GetParent() == bar) then
        ReleaseAll(); lastReason = "native-structure-unconfirmed"; return
    end
    HookLayout(container)
    HookLayout(sort)
    if not layoutHooks[container] and type(container.UpdateSearchBox) == "function" then
        layoutHooks[container] = Security.SafeHook("NativeInterface:bag-sort-layout", container, "UpdateSearchBox", OnLayout)
    end
    local state = EnsureButton(button)
    if not state then ReleaseAll(); lastReason = "native-hooks-unavailable"; return end
    if not state.owned then state.wantedShown = Shown(button) end
    if not (sort:GetParent() == container and Shown(sort, "IsVisible") and state.wantedShown
        and Shown(bar, "IsVisible") and Overlaps(button, sort)) then
        ReleaseAll(); lastReason = "no-overlap"; return
    end
    ReleaseAll(button)
    if not Shown(button) then lastReason = "suppressed"; return end
    if Security.InCombatLockdown() then
        SetRecovery(true); lastReason = "combat-deferred"; return
    end
    state.writing = true
    state.owned = true
    local ok = Security.SafeMethod("NativeInterface:bag-sort-hide", button, "Hide")
    state.writing = false
    if ok then
        hideWrites = hideWrites + 1; lastReason = "suppressed"
    else
        local shown, known = Shown(button)
        state.owned = known and not shown
        lastReason = "hide-failed"
    end
end

Refresh = function(reason)
    if refreshing then return end
    refreshing = true
    local ok = Security.SafeCall("NativeInterface:bag-sort-refresh", Evaluate)
    if not ok then ReleaseAll(); lastReason = "native-check-failed" end
    refreshing = false
end

local function OnEvent(event, addonName)
    if not watching then return end
    if event == "ADDON_LOADED" and addonName ~= "Blizzard_UIPanels_Game"
        and addonName ~= "Blizzard_MainMenuBarBagButtons" then return end
    Refresh(event)
end

function Native:RefreshBagSortFix(reason)
    local enabled = self.runtimeEnabled == true and self:GetConfig().fixBagSortButton == true
        and YUI.Event and type(YUI.Event.On) == "function" and type(YUI.Event.OffOwner) == "function"
    enabled = enabled == true
    if enabled ~= watching then
        watching = enabled
        if enabled then
            for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "INPUT_DEVICE_INTERFACE_TRANSITION" }) do
                YUI.Event:On(event, OnEvent, owner, { moduleId = self.MODULE_ID })
            end
        else
            if YUI.Event and YUI.Event.OffOwner then YUI.Event:OffOwner(owner) end
        end
    end
    if watching then Refresh(reason) else
        ReleaseAll(); lastReason = recovering and "restore-deferred" or "inactive"
    end
end

function Native:ReleaseBagSortFix()
    watching = false
    if YUI.Event and YUI.Event.OffOwner then YUI.Event:OffOwner(owner) end
    ReleaseAll()
    lastReason = recovering and "restore-deferred" or "inactive"
end

function Native:GetBagSortFixDiagnostics()
    local owned = 0
    for _, state in pairs(states) do if state.owned then owned = owned + 1 end end
    return { watching = watching, recovering = recovering, owned = owned,
        lastReason = lastReason, hideWrites = hideWrites, restoreWrites = restoreWrites }
end

local _, addonTable = ...
local YUI = _G.YUI or addonTable
local Native = YUI and YUI.NativeInterface
if not (Native and YUI.IsRetail == true) then return end

local Event = YUI.Event
local Security = YUI.API and YUI.API.Security
local System = YUI.API and YUI.API.System
local GUI2 = YUI.GUI2
local L = YUI.Locale and YUI.Locale:Get("NativeInterface") or {}

local nativeEventOwner = {}
local buffCollapseEventOwner = {}
local nativeEventAttached = false
local buffCollapseEventAttached = false

local buffCollapseActive = false
local buffCollapsePending
local buffCollapseHardFailed = false
local buffCollapseAddonObserved = false
local buffCollapseFrame
local buffCollapseButton
local buffCollapseOriginalAlpha
local buffCollapseOriginalMouseEnabled
local buffCollapseSnapshotCaptured = false
local buffCollapseReportedFailures = {}

local NATIVE_WIDGET_ORDER = { "topCenterWidget", "powerBarWidget" }
local NATIVE_WIDGETS = {
    topCenterWidget = {
        sourceName = "UIWidgetTopCenterContainerFrame",
        holderName = "YUIUtilityToolsTopCenterWidgetHolder",
        layoutId = "yui.component.utilityTools.topCenterWidget",
        titleKey = "layout.top_center_widget",
        width = 160,
        height = 24,
        restoreMode = "point",
        expectedRelativeName = "UIParent",
        defaultPlacement = {
            version = 2,
            anchor = { point = "TOP", relative = "UIParent", relativePoint = "TOP" },
            offset = { x = 0, y = -50 },
        },
    },
    powerBarWidget = {
        sourceName = "UIWidgetPowerBarContainerFrame",
        holderName = "YUIUtilityToolsPowerBarWidgetHolder",
        layoutId = "yui.component.utilityTools.powerBarWidget",
        titleKey = "layout.power_bar_widget",
        width = 120,
        height = 24,
        restoreMode = "encounter",
        expectedRelativeName = "EncounterBar",
        yieldsToNDui = true,
        defaultPlacement = {
            version = 2,
            anchor = { point = "TOP", relative = "UIParent", relativePoint = "TOP" },
            offset = { x = 0, y = -75 },
        },
    },
}

local nativeStates = {}
for _, key in ipairs(NATIVE_WIDGET_ORDER) do
    nativeStates[key] = {
        hookedSources = setmetatable({}, { __mode = "k" }),
        reportedFailures = {},
    }
end

local runtimeConfig = {}
local function GetRuntimeConfig()
    local config = Native:GetConfig()
    runtimeConfig.hideBuffCollapseButton = config.hideBuffCollapseButton == true
    runtimeConfig.topCenterWidget = config.manageTopCenterWidget == true
    runtimeConfig.powerBarWidget = config.managePowerBarWidget == true
    return runtimeConfig
end

local function T(key, fallback)
    return L[key] or fallback or key
end

local function OpenNativeInterfaceSettings()
    return Native:OpenSettings()
end

local function SafeCall(label, func, ...)
    if not (Security and type(Security.SafeCall) == "function") then
        return false, "security unavailable"
    end
    return Security.SafeCall(label, func, ...)
end

local function SafeMethod(label, object, method, ...)
    if not (Security and type(Security.SafeMethod) == "function") then
        return false, "security unavailable"
    end
    return Security.SafeMethod(label, object, method, ...)
end

local function ReadField(object, key)
    if object == nil then return nil end
    return object[key]
end

local function SafeReadField(label, object, key)
    return SafeCall(label, ReadField, object, key)
end

local function IsSecretValue(value)
    if not (Security and type(Security.IsSecretValue) == "function") then return nil end
    local ok, result = SafeCall(
        "NativeInterface:IsSecretValue",
        Security.IsSecretValue,
        value
    )
    if not ok or type(result) ~= "boolean" then return nil end
    return result
end

local function HasFunction(object, key)
    local ok, value = pcall(ReadField, object, key)
    return ok and type(value) == "function"
end

local function HasNativeCoreCapabilities()
    return Security ~= nil
        and HasFunction(Security, "SafeCall")
        and HasFunction(Security, "SafeMethod")
        and HasFunction(Security, "SafeHook")
        and HasFunction(Security, "InCombatLockdown")
        and HasFunction(Security, "IsSecretValue")
        and YUI.Layout ~= nil
        and HasFunction(YUI.Layout, "RegisterFrame")
        and HasFunction(YUI.Layout, "UnregisterFrame")
        and GUI2 ~= nil
        and HasFunction(GUI2, "CreateFrame")
        and _G.UIParent ~= nil
end

local function ReportNativeFailure(state, reason)
    reason = tostring(reason or "unknown")
    if state.reportedFailures[reason] then return end
    state.reportedFailures[reason] = true
    if type(YUI.Debug) == "function" then
        pcall(YUI.Debug, YUI, "Components | NativeInterface | Native interface ownership disabled | " .. reason)
    end
end

local function MarkNativeHardFailure(state, reason)
    local alreadyFailed = state.hardFailed == true
    state.hardFailed = true
    state.status = "unsafe"
    state.reasonKey = "settings.native_interface.unavailable"
    if not alreadyFailed then ReportNativeFailure(state, reason) end
end

local function GetCombatState()
    if not (Security and type(Security.InCombatLockdown) == "function") then
        return nil
    end
    local ok, inCombat = SafeCall(
        "NativeInterface:InCombatLockdown",
        Security.InCombatLockdown
    )
    if not ok or IsSecretValue(inCombat) ~= false or type(inCombat) ~= "boolean" then return nil end
    return inCombat == true
end

local RefreshBuffCollapseRuntime
local AttachBuffCollapseEvents
local DetachBuffCollapseEvents

local function ReportBuffCollapseFailure(reason)
    reason = type(reason) == "string" and reason or "unknown"
    if buffCollapseReportedFailures[reason] then return end
    buffCollapseReportedFailures[reason] = true
    if type(YUI.Debug) == "function" then
        pcall(
            YUI.Debug,
            YUI,
            "Components | NativeInterface | Buff collapse button ownership disabled | " .. reason
        )
    end
end

local function MarkBuffCollapseHardFailure(reason)
    buffCollapseActive = false
    buffCollapsePending = nil
    buffCollapseHardFailed = true
    ReportBuffCollapseFailure(reason)
end

local function ResetBuffCollapseFailure()
    buffCollapseHardFailed = false
    buffCollapseReportedFailures = {}
end

local function ReadSafeFrameFlag(frame, method, label)
    if not HasFunction(frame, method) then return nil end
    local ok, value = SafeMethod(label, frame, method)
    if not ok or IsSecretValue(value) ~= false or type(value) ~= "boolean" then
        return nil
    end
    return value
end

local function IsBuffFrameAddOnLoaded()
    if System and type(System.GetAddOnLoadedState) == "function" then
        local ok, loaded = pcall(System.GetAddOnLoadedState, "Blizzard_BuffFrame")
        if ok and type(loaded) == "boolean" then return loaded end
    end
    return buffCollapseAddonObserved == true
end

local function ProbeBuffCollapseTarget()
    local frameOK, frame = SafeReadField(
        "NativeInterface:BuffCollapse:ReadBuffFrame",
        _G,
        "BuffFrame"
    )
    if not frameOK then return nil, nil, "unsafe-read" end
    if frame == nil then return nil, nil, "pending-load" end

    local buttonOK, button = SafeReadField(
        "NativeInterface:BuffCollapse:ReadButton",
        frame,
        "CollapseAndExpandButton"
    )
    if not buttonOK then return nil, nil, "unsafe-read" end
    if button == nil then return nil, nil, "pending-load" end

    if not HasFunction(frame, "SetBuffsExpandedState")
        or not HasFunction(frame, "Update")
        or not HasFunction(button, "GetAlpha")
        or not HasFunction(button, "SetAlpha")
        or not HasFunction(button, "IsMouseEnabled")
        or not HasFunction(button, "EnableMouse")
    then
        return nil, nil, "missing-capability"
    end

    local frameForbidden = ReadSafeFrameFlag(
        frame,
        "IsForbidden",
        "NativeInterface:BuffCollapse:FrameIsForbidden"
    )
    local frameProtected = ReadSafeFrameFlag(
        frame,
        "IsProtected",
        "NativeInterface:BuffCollapse:FrameIsProtected"
    )
    local buttonForbidden = ReadSafeFrameFlag(
        button,
        "IsForbidden",
        "NativeInterface:BuffCollapse:ButtonIsForbidden"
    )
    local buttonProtected = ReadSafeFrameFlag(
        button,
        "IsProtected",
        "NativeInterface:BuffCollapse:ButtonIsProtected"
    )
    if frameForbidden == nil or frameProtected == nil
        or buttonForbidden == nil or buttonProtected == nil
    then
        return nil, nil, "unsafe-frame-state"
    end
    if frameForbidden or frameProtected or buttonForbidden or buttonProtected then
        return nil, nil, "protected-or-forbidden"
    end

    return frame, button
end

local function ClearBuffCollapseSnapshot()
    buffCollapseOriginalAlpha = nil
    buffCollapseOriginalMouseEnabled = nil
    buffCollapseSnapshotCaptured = false
end

local function CaptureBuffCollapseSnapshot(button)
    local alphaOK, alpha = SafeMethod(
        "NativeInterface:BuffCollapse:GetAlpha",
        button,
        "GetAlpha"
    )
    if not alphaOK or IsSecretValue(alpha) ~= false or type(alpha) ~= "number" then
        return false, "unsafe-alpha-state"
    end

    local mouseOK, mouseEnabled = SafeMethod(
        "NativeInterface:BuffCollapse:IsMouseEnabled",
        button,
        "IsMouseEnabled"
    )
    if not mouseOK or IsSecretValue(mouseEnabled) ~= false or type(mouseEnabled) ~= "boolean" then
        return false, "unsafe-mouse-state"
    end

    buffCollapseOriginalAlpha = alpha
    buffCollapseOriginalMouseEnabled = mouseEnabled
    buffCollapseSnapshotCaptured = true
    return true
end

local function RestoreBuffCollapseVisuals()
    if not buffCollapseSnapshotCaptured then return true end
    local button = buffCollapseButton
    if not button then return false end

    local alphaOK = SafeMethod(
        "NativeInterface:BuffCollapse:RestoreAlpha",
        button,
        "SetAlpha",
        buffCollapseOriginalAlpha
    )
    local mouseOK = SafeMethod(
        "NativeInterface:BuffCollapse:RestoreMouse",
        button,
        "EnableMouse",
        buffCollapseOriginalMouseEnabled
    )
    if not alphaOK or not mouseOK then return false end

    ClearBuffCollapseSnapshot()
    return true
end

local function ApplyBuffCollapseState(frame, button)
    if buffCollapseActive and frame == buffCollapseFrame and button == buffCollapseButton then
        return true
    end
    if buffCollapseSnapshotCaptured and not RestoreBuffCollapseVisuals() then
        MarkBuffCollapseHardFailure("unresolved-visual-state")
        return false
    end

    buffCollapseFrame = frame
    buffCollapseButton = button
    local captured, captureReason = CaptureBuffCollapseSnapshot(button)
    if not captured then
        buffCollapseFrame = nil
        buffCollapseButton = nil
        MarkBuffCollapseHardFailure(captureReason)
        return false
    end

    local expandedOK, expanded = SafeReadField(
        "NativeInterface:BuffCollapse:ReadExpandedState",
        frame,
        "isExpanded"
    )
    if not expandedOK or IsSecretValue(expanded) ~= false or type(expanded) ~= "boolean" then
        ClearBuffCollapseSnapshot()
        buffCollapseFrame = nil
        buffCollapseButton = nil
        MarkBuffCollapseHardFailure("unsafe-expanded-state")
        return false
    end
    if not expanded then
        local expandOK = SafeMethod(
            "NativeInterface:BuffCollapse:Expand",
            frame,
            "SetBuffsExpandedState",
            true
        )
        if not expandOK then
            ClearBuffCollapseSnapshot()
            buffCollapseFrame = nil
            buffCollapseButton = nil
            MarkBuffCollapseHardFailure("expand-failed")
            return false
        end
    end

    local alphaOK = SafeMethod(
        "NativeInterface:BuffCollapse:SetAlpha",
        button,
        "SetAlpha",
        0
    )
    local mouseOK = alphaOK and SafeMethod(
        "NativeInterface:BuffCollapse:DisableMouse",
        button,
        "EnableMouse",
        false
    ) or false
    if not alphaOK or not mouseOK then
        RestoreBuffCollapseVisuals()
        buffCollapseFrame = nil
        buffCollapseButton = nil
        MarkBuffCollapseHardFailure(alphaOK and "disable-mouse-failed" or "set-alpha-failed")
        return false
    end

    buffCollapseActive = true
    return true
end

local function OnBuffCollapseRuntimeEvent(event, addonName)
    if event == "ADDON_LOADED" then
        if addonName ~= "Blizzard_BuffFrame" then return end
        buffCollapseAddonObserved = true
    elseif event ~= "PLAYER_REGEN_ENABLED" then
        return
    end
    if RefreshBuffCollapseRuntime then RefreshBuffCollapseRuntime() end
end

AttachBuffCollapseEvents = function()
    if buffCollapseEventAttached then return true end
    if not (Event and type(Event.On) == "function" and type(Event.OffOwner) == "function") then
        return false
    end
    local addonOK = SafeCall(
        "NativeInterface:BuffCollapse:Listen:ADDON_LOADED",
        Event.On,
        Event,
        "ADDON_LOADED",
        OnBuffCollapseRuntimeEvent,
        buffCollapseEventOwner,
        { moduleId = Native.MODULE_ID }
    )
    local regenOK = addonOK and SafeCall(
        "NativeInterface:BuffCollapse:Listen:PLAYER_REGEN_ENABLED",
        Event.On,
        Event,
        "PLAYER_REGEN_ENABLED",
        OnBuffCollapseRuntimeEvent,
        buffCollapseEventOwner,
        { moduleId = Native.MODULE_ID }
    ) or false
    if not regenOK then
        SafeCall(
            "NativeInterface:BuffCollapse:ListenCleanup",
            Event.OffOwner,
            Event,
            buffCollapseEventOwner
        )
        return false
    end
    buffCollapseEventAttached = true
    return true
end

DetachBuffCollapseEvents = function()
    if not buffCollapseEventAttached then return end
    if Event and type(Event.OffOwner) == "function" then
        SafeCall(
            "NativeInterface:BuffCollapse:DetachEvents",
            Event.OffOwner,
            Event,
            buffCollapseEventOwner
        )
    end
    buffCollapseEventAttached = false
end

RefreshBuffCollapseRuntime = function()
    local nativeDB = GetRuntimeConfig()
    local desired = Native.runtimeEnabled and YUI.IsRetail == true
        and nativeDB.hideBuffCollapseButton == true
    local wasActive = buffCollapseActive
    if not desired then
        buffCollapseActive = false
        if not wasActive and buffCollapsePending ~= "restore" and not buffCollapseSnapshotCaptured then
            buffCollapsePending = nil
            DetachBuffCollapseEvents()
            return
        end

        local inCombat = GetCombatState()
        if inCombat == true then
            buffCollapsePending = "restore"
            if not AttachBuffCollapseEvents() then
                buffCollapsePending = nil
                ReportBuffCollapseFailure("restore-event-bus-unavailable")
            end
            return
        end
        if inCombat ~= false then
            ReportBuffCollapseFailure("restore-combat-state-unsafe")
            return
        end
        local restored = RestoreBuffCollapseVisuals()
        local nativeRestored = true
        if buffCollapseFrame and HasFunction(buffCollapseFrame, "Update") then
            nativeRestored = SafeMethod(
                "NativeInterface:BuffCollapse:RestoreNativeState",
                buffCollapseFrame,
                "Update"
            )
        end
        if not restored or not nativeRestored then
            buffCollapsePending = "restore"
            ReportBuffCollapseFailure(restored and "restore-native-failed" or "restore-visual-failed")
            if not AttachBuffCollapseEvents() then
                ReportBuffCollapseFailure("restore-event-bus-unavailable")
            end
            return
        end
        buffCollapsePending = nil
        DetachBuffCollapseEvents()
        buffCollapseFrame = nil
        buffCollapseButton = nil
        return
    end

    if buffCollapseHardFailed then
        buffCollapseActive = false
        buffCollapsePending = nil
        DetachBuffCollapseEvents()
        return
    end

    if buffCollapseActive then
        buffCollapsePending = nil
        DetachBuffCollapseEvents()
        return
    end

    local inCombat = GetCombatState()
    if inCombat == true then
        buffCollapseActive = false
        buffCollapsePending = "apply"
        if not AttachBuffCollapseEvents() then
            MarkBuffCollapseHardFailure("event-bus-unavailable")
        end
        return
    end
    if inCombat ~= false then
        MarkBuffCollapseHardFailure("unsafe-combat-state")
        DetachBuffCollapseEvents()
        return
    end

    local frame, button, reason = ProbeBuffCollapseTarget()
    if not frame then
        buffCollapseActive = false
        if reason == "pending-load" and not IsBuffFrameAddOnLoaded() then
            buffCollapsePending = "load"
            if not AttachBuffCollapseEvents() then
                MarkBuffCollapseHardFailure("event-bus-unavailable")
            end
        else
            MarkBuffCollapseHardFailure(reason or "target-unavailable")
            DetachBuffCollapseEvents()
        end
        return
    end

    buffCollapsePending = nil
    DetachBuffCollapseEvents()
    if not ApplyBuffCollapseState(frame, button) then
        buffCollapseActive = false
    end
end

local function ProbeAddOnLoaded(addonName)
    local external = YUI.API and YUI.API.External
    if type(external) ~= "table" or type(external.IsLoaded) ~= "function" then return nil end
    local ok, loaded = pcall(external.IsLoaded, external, addonName)
    if not ok or type(loaded) ~= "boolean" then return nil end
    return loaded
end

local function BuildExternalContext()
    return {
        elvui = ProbeAddOnLoaded("ElvUI"),
        ndui = ProbeAddOnLoaded("NDui"),
    }
end

local function CaptureNativePoint(definition, source)
    local ok, count = SafeMethod(
        "NativeInterface:GetNumPoints:" .. definition.sourceName,
        source,
        "GetNumPoints"
    )
    if not ok or IsSecretValue(count) ~= false or type(count) ~= "number" then
        return nil, "unsafe"
    end
    if count == 0 and definition.restoreMode == "encounter" then
        return { count = 0 }
    end
    if count ~= 1 then
        return nil, "unsafe"
    end

    local pointOK, point, relativeTo, relativePoint, x, y = SafeMethod(
        "NativeInterface:GetPoint:" .. definition.sourceName,
        source,
        "GetPoint",
        1
    )
    if not pointOK
        or IsSecretValue(point) ~= false
        or IsSecretValue(relativeTo) ~= false
        or IsSecretValue(relativePoint) ~= false
        or IsSecretValue(x) ~= false
        or IsSecretValue(y) ~= false
        or type(point) ~= "string"
        or type(relativePoint) ~= "string"
        or type(x) ~= "number"
        or type(y) ~= "number"
    then
        return nil, "unsafe"
    end

    return {
        count = 1,
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local function CheckNativeFrameSafety(definition, source)
    local forbiddenOK, forbidden = SafeMethod(
        "NativeInterface:IsForbidden:" .. definition.sourceName,
        source,
        "IsForbidden"
    )
    if not forbiddenOK or IsSecretValue(forbidden) ~= false or type(forbidden) ~= "boolean" or forbidden then
        return false, "unsafe"
    end

    local protectedOK, protected = SafeMethod(
        "NativeInterface:IsProtected:" .. definition.sourceName,
        source,
        "IsProtected"
    )
    if not protectedOK or IsSecretValue(protected) ~= false or type(protected) ~= "boolean" or protected then
        return false, "unsafe"
    end
    return true
end

local function CheckNativeSourceCapabilities(definition, source)
    for _, method in ipairs({ "GetNumPoints", "GetPoint", "IsForbidden", "IsProtected", "ClearAllPoints", "SetPoint" }) do
        local ok, value = SafeReadField(
            "NativeInterface:Method:" .. definition.sourceName .. ":" .. method,
            source,
            method
        )
        if not ok or type(value) ~= "function" then return false end
    end

    if definition.restoreMode == "encounter" then
        local encounterOK, encounterBar = SafeReadField(
            "NativeInterface:EncounterBar",
            _G,
            "EncounterBar"
        )
        if not encounterOK or not encounterBar then return false end
        local layoutOK, layoutMethod = SafeReadField(
            "NativeInterface:EncounterBar:Layout",
            encounterBar,
            "Layout"
        )
        if not layoutOK or type(layoutMethod) ~= "function" then return false end
    end
    return true
end

local function HasForeignOwner(definition, state, source, snapshot)
    local holderOK, containerHolder = SafeReadField(
        "NativeInterface:containerHolder:" .. definition.sourceName,
        source,
        "containerHolder"
    )
    if not holderOK or IsSecretValue(containerHolder) ~= false then return nil end
    if containerHolder ~= nil and containerHolder ~= state.holder then
        return true
    end
    if not snapshot or snapshot.count == 0 then return false end

    local expectedOK, expectedRelative = SafeReadField(
        "NativeInterface:expectedRelative:" .. definition.sourceName,
        _G,
        definition.expectedRelativeName
    )
    if not expectedOK or IsSecretValue(expectedRelative) ~= false then return nil end
    local relativeTo = snapshot.relativeTo
    if relativeTo == nil
        or relativeTo == expectedRelative
        or relativeTo == definition.expectedRelativeName
        or relativeTo == state.holder
    then
        return false
    end
    return true
end

local function EvaluateNativeWidget(definition, state, externalContext)
    if state.hardFailed then
        return "unsafe", state.source, nil, "settings.native_interface.unavailable", "hard failure"
    end
    if externalContext.elvui == nil then
        return "unsafe", nil, nil, "settings.native_interface.unavailable"
    end
    if externalContext.elvui then
        return "external", nil, nil, "settings.native_interface.managed_by_elvui"
    end
    if definition.yieldsToNDui then
        if externalContext.ndui == nil then
            return "unsafe", nil, nil, "settings.native_interface.unavailable"
        end
        if externalContext.ndui then
            return "external", nil, nil, "settings.native_interface.managed_by_ndui"
        end
    end
    if not HasNativeCoreCapabilities() then
        return "unsafe", nil, nil, "settings.native_interface.unavailable"
    end

    local sourceOK, source = SafeReadField(
        "NativeInterface:source:" .. definition.sourceName,
        _G,
        definition.sourceName
    )
    if not sourceOK or IsSecretValue(source) ~= false then
        return "unsafe", nil, nil, "settings.native_interface.unavailable"
    end
    if not source then
        return "pending", nil, nil
    end

    if not CheckNativeSourceCapabilities(definition, source) then
        return "unsafe", source, nil, "settings.native_interface.unavailable", "missing source capability"
    end

    local safe, reason = CheckNativeFrameSafety(definition, source)
    if not safe then
        return "unsafe", source, nil, "settings.native_interface.unavailable", reason
    end
    local snapshot, captureReason = CaptureNativePoint(definition, source)
    if not snapshot then
        return "unsafe", source, nil, "settings.native_interface.unavailable", captureReason
    end
    local foreignOwner = HasForeignOwner(definition, state, source, snapshot)
    if foreignOwner == nil then
        return "unsafe", source, snapshot, "settings.native_interface.unavailable"
    end
    if foreignOwner then
        return "external", source, snapshot, "settings.native_interface.managed_externally"
    end
    return "available", source, snapshot
end

local function EnsureNativeHolder(definition, state)
    if state.holder then return state.holder end
    if not (GUI2 and type(GUI2.CreateFrame) == "function" and _G.UIParent) then
        return nil, "GUI2 unavailable"
    end
    local ok, holder = SafeCall(
        "NativeInterface:CreateHolder:" .. definition.layoutId,
        GUI2.CreateFrame,
        GUI2,
        _G.UIParent,
        {
            name = definition.holderName,
            width = definition.width,
            height = definition.height,
            mouse = false,
        }
    )
    if not ok or not holder then return nil, "holder creation failed" end
    if holder.EnableMouse then holder:EnableMouse(false) end
    if holder.Hide then holder:Hide() end
    state.holder = holder
    return holder
end

local function IsSourceAnchoredToHolder(definition, state, source)
    if not (source and state.holder) then return false end
    local snapshot = CaptureNativePoint(definition, source)
    return snapshot
        and snapshot.count == 1
        and snapshot.point == "CENTER"
        and snapshot.relativeTo == state.holder
        and snapshot.relativePoint == "CENTER"
        and snapshot.x == 0
        and snapshot.y == 0
        or false
end

local function ReanchorNativeSource(definition, state, source)
    if not (state.active and source and state.holder) then return false end
    local inCombat = GetCombatState()
    if inCombat == nil or inCombat then
        state.pending = "acquire"
        return false
    end
    if IsSourceAnchoredToHolder(definition, state, source) then return true end
    if state.applying then return false end

    local previous = CaptureNativePoint(definition, source)
    if not previous then
        ReportNativeFailure(state, definition.sourceName .. ":anchor-snapshot")
        return false
    end

    state.applying = true
    local clearOK = SafeMethod(
        "NativeInterface:ClearAllPoints:" .. definition.sourceName,
        source,
        "ClearAllPoints"
    )
    local pointOK = clearOK and SafeMethod(
        "NativeInterface:SetPoint:" .. definition.sourceName,
        source,
        "SetPoint",
        "CENTER",
        state.holder,
        "CENTER",
        0,
        0
    ) or false
    if clearOK and not pointOK then
        local rollbackClearOK = SafeMethod(
            "NativeInterface:RollbackClear:" .. definition.sourceName,
            source,
            "ClearAllPoints"
        )
        if rollbackClearOK and previous.count == 1 then
            SafeMethod(
                "NativeInterface:RollbackPoint:" .. definition.sourceName,
                source,
                "SetPoint",
                previous.point,
                previous.relativeTo,
                previous.relativePoint,
                previous.x,
                previous.y
            )
        end
    end
    state.applying = false
    if not pointOK then
        ReportNativeFailure(state, definition.sourceName .. ":anchor")
        return false
    end
    state.pending = nil
    return true
end

local function HookMustYieldOwnership(definition, state, source)
    local elvuiLoaded = ProbeAddOnLoaded("ElvUI")
    if elvuiLoaded ~= false then return true end
    if definition.yieldsToNDui and ProbeAddOnLoaded("NDui") ~= false then return true end
    local snapshot = CaptureNativePoint(definition, source)
    if not snapshot then return true end
    local foreignOwner = HasForeignOwner(definition, state, source, snapshot)
    return foreignOwner ~= false
end

local ReleaseNativeWidget

local function EnsureNativeHook(definition, state, source)
    if state.hookedSources[source] then return true end
    if not (Security and type(Security.SafeHook) == "function") then
        return false, "SafeHook unavailable"
    end
    local ok, err = Security.SafeHook(
        "NativeInterface:SetPointHook:" .. definition.sourceName,
        source,
        "SetPoint",
        function(frame)
            if frame ~= state.source or not state.active or state.applying then return end
            if HookMustYieldOwnership(definition, state, frame) then
                state.active = false
                state.pending = "release"
                return
            end
            if not ReanchorNativeSource(definition, state, frame) and state.pending ~= "acquire" then
                state.active = false
                MarkNativeHardFailure(state, definition.sourceName .. ":hook-reanchor")
                if ReleaseNativeWidget then ReleaseNativeWidget(definition, state) end
            end
        end
    )
    if not ok then return false, err end
    state.hookedSources[source] = true
    return true
end

local function RegisterNativeLayout(definition, state)
    if state.layoutRegistered then return true end
    local layout = YUI.Layout
    if not (layout and type(layout.RegisterFrame) == "function") then
        return false, "Layout unavailable"
    end
    local ok, entry = SafeCall(
        "NativeInterface:RegisterFrame:" .. definition.layoutId,
        layout.RegisterFrame,
        layout,
        definition.layoutId,
        {
            frame = state.holder,
            title = T(definition.titleKey),
            category = "component",
            defaultPlacement = definition.defaultPlacement,
            combatProtected = false,
            movable = true,
            snap = true,
            anchorTargets = { "UIParent" },
            minWidth = definition.width,
            minHeight = definition.height,
            openPluginSettings = OpenNativeInterfaceSettings,
        }
    )
    if not ok or not entry then return false, "Layout registration failed" end
    state.layoutRegistered = true
    if state.holder.Show then state.holder:Show() end
    return true
end

local function UnregisterNativeLayout(definition, state)
    if not state.layoutRegistered then return true end
    local layout = YUI.Layout
    if not (layout and type(layout.UnregisterFrame) == "function") then return false end
    local ok, result = SafeCall(
        "NativeInterface:UnregisterFrame:" .. definition.layoutId,
        layout.UnregisterFrame,
        layout,
        definition.layoutId
    )
    if ok and result ~= false then
        state.layoutRegistered = false
        return true
    end
    return false
end

local function RestoreNativeSource(definition, state)
    local source = state.source
    if not source or not state.holder or not IsSourceAnchoredToHolder(definition, state, source) then
        return true
    end
    local inCombat = GetCombatState()
    if inCombat == nil or inCombat then
        state.pending = "release"
        return false
    end
    local safe = CheckNativeFrameSafety(definition, source)
    if not safe then return false end

    if definition.restoreMode == "encounter" then
        local encounterOK, encounterBar = SafeReadField(
            "NativeInterface:EncounterBar",
            _G,
            "EncounterBar"
        )
        if not encounterOK or not encounterBar then return false end
        local layoutOK = SafeMethod(
            "NativeInterface:EncounterBarLayout",
            encounterBar,
            "Layout"
        )
        if layoutOK then state.pending = nil end
        return layoutOK == true
    end

    local original = state.originalPlacement
    if not original or original.count ~= 1 then return false end
    state.applying = true
    local clearOK = SafeMethod(
        "NativeInterface:RestoreClear:" .. definition.sourceName,
        source,
        "ClearAllPoints"
    )
    local pointOK = clearOK and SafeMethod(
        "NativeInterface:RestorePoint:" .. definition.sourceName,
        source,
        "SetPoint",
        original.point,
        original.relativeTo,
        original.relativePoint,
        original.x,
        original.y
    ) or false
    if not pointOK then
        SafeMethod(
            "NativeInterface:RestoreHolder:" .. definition.sourceName,
            source,
            "ClearAllPoints"
        )
        SafeMethod(
            "NativeInterface:RestoreHolderPoint:" .. definition.sourceName,
            source,
            "SetPoint",
            "CENTER",
            state.holder,
            "CENTER",
            0,
            0
        )
    end
    state.applying = false
    if pointOK then state.pending = nil end
    return pointOK == true
end

ReleaseNativeWidget = function(definition, state)
    if not (state.active or state.layoutRegistered or state.pending) then return true end
    if state.pending == "acquire" and not (state.active or state.layoutRegistered) then
        state.pending = nil
        state.source = nil
        state.originalPlacement = nil
        return true
    end
    state.active = false
    local restored = RestoreNativeSource(definition, state)
    if not restored and state.pending == "release" then return false end
    UnregisterNativeLayout(definition, state)
    if restored and state.holder and state.holder.Hide then state.holder:Hide() end
    if restored then
        state.source = nil
        state.originalPlacement = nil
        state.pending = nil
    end
    return restored
end

local function AcquireNativeWidget(definition, state, externalContext)
    local status, source, snapshot, reasonKey, detail = EvaluateNativeWidget(definition, state, externalContext)
    state.status = status
    state.reasonKey = reasonKey
    if status ~= "available" then
        if status == "unsafe" and not state.hardFailed then
            MarkNativeHardFailure(state, detail or definition.sourceName .. ":unsafe")
        end
        if state.active or state.layoutRegistered or state.pending then ReleaseNativeWidget(definition, state) end
        if status == "pending" then state.pending = "acquire" end
        return false
    end

    local inCombat = GetCombatState()
    if inCombat == nil or inCombat then
        state.pending = "acquire"
        return false
    end
    if state.active and state.source == source then
        return ReanchorNativeSource(definition, state, source)
    end
    if state.active or state.layoutRegistered then
        ReleaseNativeWidget(definition, state)
    end

    local holder, holderError = EnsureNativeHolder(definition, state)
    if not holder then
        MarkNativeHardFailure(state, holderError)
        return false
    end
    local hookOK, hookError = EnsureNativeHook(definition, state, source)
    if not hookOK then
        MarkNativeHardFailure(state, hookError)
        return false
    end

    if state.source ~= source or not state.originalPlacement then
        state.originalPlacement = snapshot
    end
    state.source = source
    local registered, registerError = RegisterNativeLayout(definition, state)
    if not registered then
        MarkNativeHardFailure(state, registerError)
        state.source = nil
        state.originalPlacement = nil
        return false
    end

    state.active = true
    if not ReanchorNativeSource(definition, state, source) then
        state.active = false
        local restored = RestoreNativeSource(definition, state)
        UnregisterNativeLayout(definition, state)
        if restored and state.holder and state.holder.Hide then state.holder:Hide() end
        if restored then
            state.source = nil
            state.originalPlacement = nil
            state.pending = nil
        end
        MarkNativeHardFailure(state, definition.sourceName .. ":acquire-reanchor")
        return false
    end
    state.status = "active"
    state.reasonKey = nil
    state.pending = nil
    return true
end

local RefreshNativeInterfaceRuntime

local function OnNativeRuntimeEvent()
    if RefreshNativeInterfaceRuntime then RefreshNativeInterfaceRuntime() end
end

local function AttachNativeEvents()
    if nativeEventAttached then return true end
    if not (Event and type(Event.On) == "function" and type(Event.OffOwner) == "function") then
        return false
    end
    local addonOK = SafeCall(
        "NativeInterface:Listen:ADDON_LOADED",
        Event.On,
        Event,
        "ADDON_LOADED",
        OnNativeRuntimeEvent,
        nativeEventOwner,
        { moduleId = Native.MODULE_ID }
    )
    local regenOK = addonOK and SafeCall(
        "NativeInterface:Listen:PLAYER_REGEN_ENABLED",
        Event.On,
        Event,
        "PLAYER_REGEN_ENABLED",
        OnNativeRuntimeEvent,
        nativeEventOwner,
        { moduleId = Native.MODULE_ID }
    ) or false
    if not regenOK then
        SafeCall(
            "NativeInterface:ListenCleanup",
            Event.OffOwner,
            Event,
            nativeEventOwner
        )
        return false
    end
    nativeEventAttached = true
    return true
end

local function DetachNativeEvents()
    if not nativeEventAttached then return end
    if Event and type(Event.OffOwner) == "function" then
        SafeCall(
            "NativeInterface:DetachEvents",
            Event.OffOwner,
            Event,
            nativeEventOwner
        )
    end
    nativeEventAttached = false
end

local function HasNativePendingState()
    for _, key in ipairs(NATIVE_WIDGET_ORDER) do
        local state = nativeStates[key]
        if state.pending or state.active or state.layoutRegistered then return true end
    end
    return false
end

RefreshNativeInterfaceRuntime = function()
    local nativeDB = GetRuntimeConfig()
    local wantsAny = Native.runtimeEnabled and YUI.IsRetail == true
        and (nativeDB.topCenterWidget == true or nativeDB.powerBarWidget == true)

    if wantsAny and not AttachNativeEvents() then
        for _, key in ipairs(NATIVE_WIDGET_ORDER) do
            local state = nativeStates[key]
            MarkNativeHardFailure(state, "EventBus unavailable")
            ReleaseNativeWidget(NATIVE_WIDGETS[key], state)
        end
        return
    end

    local externalContext = wantsAny and BuildExternalContext() or nil
    local yieldController
    for _, key in ipairs(NATIVE_WIDGET_ORDER) do
        local definition = NATIVE_WIDGETS[key]
        local state = nativeStates[key]
        local desired = wantsAny and nativeDB[key] == true
        if desired then
            AcquireNativeWidget(definition, state, externalContext)
            if externalContext then
                if externalContext.elvui == true then
                    yieldController = "ElvUI"
                elseif definition.yieldsToNDui and externalContext.ndui == true then
                    yieldController = yieldController or "NDui"
                end
            end
        else
            state.status = "disabled"
            state.reasonKey = nil
            ReleaseNativeWidget(definition, state)
        end
    end

    if wantsAny and yieldController and YUI.Yield then
        YUI.Yield:Set("native_interface", yieldController, {
            status = "active",
            enabled = true,
        })
    elseif YUI.Yield then
        YUI.Yield:Clear("native_interface")
    end

    if not wantsAny and not HasNativePendingState() then DetachNativeEvents() end
end

local function GetNativeSettingsAvailability()
    local result = {}
    local externalContext = BuildExternalContext()
    for _, key in ipairs(NATIVE_WIDGET_ORDER) do
        local definition = NATIVE_WIDGETS[key]
        local state = nativeStates[key]
        local status, _, _, reasonKey = EvaluateNativeWidget(definition, state, externalContext)
        local controller
        if status == "external" then
            if externalContext.elvui == true then
                controller = "ElvUI"
            elseif definition.yieldsToNDui and externalContext.ndui == true then
                controller = "NDui"
            end
        end
        result[key] = {
            disabled = status == "external" or status == "unsafe",
            tooltip = T(reasonKey or ("settings.native_interface." .. key .. ".tooltip")),
            controller = controller,
        }
    end
    return result
end
function Native:RefreshRetail()
    RefreshNativeInterfaceRuntime()
    RefreshBuffCollapseRuntime()
    return true
end

function Native:GetSettingsAvailability(key)
    local availability = GetNativeSettingsAvailability()
    if key == "manageTopCenterWidget" then key = "topCenterWidget" end
    if key == "managePowerBarWidget" then key = "powerBarWidget" end
    return key and availability[key] or availability
end

function Native:ResetOptionFailure(key)
    if key == "hideBuffCollapseButton" then
        ResetBuffCollapseFailure()
        return
    end
    local stateKey = key == "manageTopCenterWidget" and "topCenterWidget"
        or key == "managePowerBarWidget" and "powerBarWidget"
    local state = stateKey and nativeStates[stateKey]
    if state then
        state.hardFailed = false
        state.reportedFailures = {}
    end
end

function Native:ResetAllFailures()
    ResetBuffCollapseFailure()
    for _, key in ipairs(NATIVE_WIDGET_ORDER) do
        nativeStates[key].hardFailed = false
        nativeStates[key].reportedFailures = {}
    end
end

function Native:GetRetailDiagnostics()
    return {
        nativeEvents = nativeEventAttached,
        buffEvents = buffCollapseEventAttached,
        buffActive = buffCollapseActive,
        buffPending = buffCollapsePending,
        topCenterStatus = nativeStates.topCenterWidget.status,
        topCenterPending = nativeStates.topCenterWidget.pending,
        powerBarStatus = nativeStates.powerBarWidget.status,
        powerBarPending = nativeStates.powerBarWidget.pending,
    }
end

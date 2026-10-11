local ADDON_NAME, YUI = ...
YUI = YUI or _G.YUI
if not YUI then return end

local Skins = YUI.Appearance and YUI.Appearance.Skins or YUI.Skins
local Security = YUI.API and YUI.API.Security or YUI.WOW_API or {}
local cpuWatchdog = YUI.CPUWatchdog

local function Measured(callback, kind)
    if cpuWatchdog and cpuWatchdog.WrapAppearanceCallback then
        return cpuWatchdog:WrapAppearanceCallback("ndui", kind, callback)
    end
    return callback
end
local function ScheduleAfter(delay, callback)
    return C_Timer.After(delay, Measured(callback, "delayed"))
end
local function ScheduleTimer(delay, callback)
    return C_Timer.NewTimer(delay, Measured(callback, "delayed"))
end

local ENABLE_KEY = "ndui"
local OPTION_KEY = "nduiUnitFrameTextShadow"
local LIGHT_MODE_KEY = "lightMode"
local REFRESH_DELAY = 0.1

local hooksInstalled = false
local initCallbackRegistered = false
local refreshScheduled = false
local refreshTimer
local refreshRosterTransaction = false
local styledFonts = setmetatable({}, { __mode = "k" })

local TARGET_STYLES = {
    player = true,
    target = true,
    focus = true,
    pet = true,
    tot = true,
    focustarget = true,
    boss = true,
    arena = true,
    raid = true,
}

local SINGLE_LIGHT_MODE_STYLES = {
    player = true,
    target = true,
    focus = true,
    pet = true,
    tot = true,
    focustarget = true,
}

local STYLE_UNIT_FALLBACK = {
    player = "player",
    target = "target",
    focus = "focus",
    pet = "pet",
    tot = "targettarget",
    focustarget = "focustarget",
}

local function SafeCall(label, func, ...)
    if Security and Security.SafeCall then
        return Security.SafeCall("Appearance | NDui | " .. tostring(label or "callback"), func, ...)
    end

    if type(func) ~= "function" then
        return false, "target is not a function"
    end

    local ok, result = pcall(func, ...)
    if not ok and YUI.Debug then
        YUI:Debug("Appearance | NDui callback failed: " .. tostring(result))
    end
    return ok, result
end

local function SafeHook(label, object, method, callback)
    callback = Measured(callback, "hook")
    if Security and Security.SafeHook then
        return Security.SafeHook("Appearance | NDui | " .. tostring(label or method or "hook"), object, method, callback)
    end

    if type(hooksecurefunc) ~= "function" or not object or type(method) ~= "string" or type(object[method]) ~= "function" then
        return false
    end

    local ok, err = pcall(hooksecurefunc, object, method, function(...)
        SafeCall(label, callback, ...)
    end)
    if not ok and YUI.Debug then
        YUI:Debug("Appearance | NDui hook failed: " .. tostring(method) .. " - " .. tostring(err))
    end
    return ok
end

local function IsNDuiEnabled()
    if not (Skins and Skins.IsEnabled) then
        return false
    end
    return Skins.IsEnabled(ENABLE_KEY)
end

local function IsTextShadowEnabled()
    return IsNDuiEnabled() and Skins.IsEnabled(OPTION_KEY)
end

local function IsLightModeEnabled()
    if not IsNDuiEnabled() then
        return false
    end
    if Skins and Skins.GetOption then
        return Skins.GetOption(LIGHT_MODE_KEY, false) == true
    end
    return false
end

local function IsTargetUnitFrame(frame)
    if not frame or frame.isNamePlate then
        return false
    end

    local style = frame.mystyle
    return style ~= nil and TARGET_STYLES[style] == true
end

local function ResolveUnitFrameUnit(frame)
    if not frame then return nil end
    if frame.unit ~= nil and frame.unit ~= "" then
        return frame.unit
    end
    if frame.GetAttribute then
        local ok, unit = SafeCall("frame:GetAttribute(unit)", frame.GetAttribute, frame, "unit")
        if ok and unit ~= nil and unit ~= "" then
            return unit
        end
    end
    return STYLE_UNIT_FALLBACK[frame.mystyle]
end

local function PrepareFontStringForShadow(fontString)
    if not fontString.SetFontObject then
        return
    end

    local font, size, flags
    if fontString.GetFont then
        font, size, flags = fontString:GetFont()
    end

    local r, g, b, a
    if fontString.GetTextColor then
        r, g, b, a = fontString:GetTextColor()
    end

    local justifyH, justifyV
    if fontString.GetJustifyH then
        justifyH = fontString:GetJustifyH()
    end
    if fontString.GetJustifyV then
        justifyV = fontString:GetJustifyV()
    end

    SafeCall("fontString:SetFontObject", fontString.SetFontObject, fontString, "GameFontHighlight")

    if font and size and fontString.SetFont then
        fontString:SetFont(font, size, flags)
    end
    if r and g and b and fontString.SetTextColor then
        if a ~= nil then
            fontString:SetTextColor(r, g, b, a)
        else
            fontString:SetTextColor(r, g, b)
        end
    end
    if justifyH and fontString.SetJustifyH then
        fontString:SetJustifyH(justifyH)
    end
    if justifyV and fontString.SetJustifyV then
        fontString:SetJustifyV(justifyV)
    end
end

local function ApplyFontShadow(fontString)
    if not fontString or styledFonts[fontString] then
        return
    end
    if not fontString.SetShadowOffset or not fontString.SetShadowColor then
        return
    end

    PrepareFontStringForShadow(fontString)
    fontString:SetShadowColor(0, 0, 0, 1)
    fontString:SetShadowOffset(1, -1)
    styledFonts[fontString] = true
end

local function ApplyFontShadowsRecursive(object, seen, depth)
    if not object or seen[object] then
        return
    end

    seen[object] = true
    depth = depth or 0
    if depth > 8 then
        return
    end

    if object.IsObjectType and object:IsObjectType("FontString") then
        ApplyFontShadow(object)
        return
    end

    if object.GetRegions then
        local count = select("#", object:GetRegions())
        for index = 1, count do
            local region = select(index, object:GetRegions())
            if region and region.IsObjectType and region:IsObjectType("FontString") then
                ApplyFontShadow(region)
            end
        end
    end

    if object.GetChildren then
        local count = select("#", object:GetChildren())
        for index = 1, count do
            local child = select(index, object:GetChildren())
            ApplyFontShadowsRecursive(child, seen, depth + 1)
        end
    end
end

local function ApplyShadowToUnitFrame(frame)
    if not IsTextShadowEnabled() or not IsTargetUnitFrame(frame) then
        return
    end

    ApplyFontShadowsRecursive(frame, {}, 0)
end

local function ApplyLightModeToUnitFrame(frame)
    if not IsLightModeEnabled() or not IsTargetUnitFrame(frame) then
        return
    end
    if frame.Health and Skins and Skins.ApplyLightModeToBar then
        local unit = ResolveUnitFrameUnit(frame)
        if not unit then return end
        Skins.ApplyLightModeToBar(frame.Health, unit)
    end
end

local function ApplyNDuiUnitFrame(frame)
    ApplyShadowToUnitFrame(frame)
    ApplyLightModeToUnitFrame(frame)
end

local function GetNDui()
    local ns = _G.NDui
    if type(ns) ~= "table" then
        return nil
    end
    return ns
end

local function GetNDuiUnitFrames()
    local ns = GetNDui()
    local oUF = ns and ns.oUF
    local objects = oUF and oUF.objects
    if type(objects) ~= "table" then
        return nil
    end
    return objects, oUF, ns
end

local function RefreshAllUnitFrames()
    if not IsNDuiEnabled() then
        return
    end

    local objects = GetNDuiUnitFrames()
    if not objects then
        return
    end

    for _, frame in pairs(objects) do
        ApplyNDuiUnitFrame(frame)
    end
end

local function RunQueuedRefresh()
    refreshScheduled = false
    refreshTimer = nil
    local rosterTransaction = refreshRosterTransaction
    refreshRosterTransaction = false
    local startedAt = cpuWatchdog and cpuWatchdog:BeginProbeTiming()
    SafeCall("RefreshAllUnitFrames", RefreshAllUnitFrames)
    if startedAt then
        cpuWatchdog:EndProbeTiming(
            "appearance.ndui.refresh",
            startedAt,
            "NDui appearance refresh",
            nil,
            rosterTransaction and cpuWatchdog.ROSTER_TRANSACTION_GROUP_ID or nil,
            rosterTransaction and cpuWatchdog.ROSTER_TRANSACTION_LABEL or nil
        )
    end
end

local function QueueRefresh(delay, event)
    if event == "GROUP_ROSTER_UPDATE" then refreshRosterTransaction = true end
    if refreshScheduled then
        return
    end

    refreshScheduled = true
    if C_Timer and C_Timer.NewTimer then
        refreshTimer = ScheduleTimer(delay or REFRESH_DELAY, RunQueuedRefresh)
    elseif C_Timer and C_Timer.After then
        ScheduleAfter(delay or REFRESH_DELAY, RunQueuedRefresh)
    else
        RunQueuedRefresh()
    end
end

local function RegisterInitCallback(oUF)
    if initCallbackRegistered or not oUF or type(oUF.RegisterInitCallback) ~= "function" then
        return
    end

    local ok = SafeCall("oUF.RegisterInitCallback", function()
        oUF:RegisterInitCallback(function(frame)
            SafeCall("ApplyNDuiUnitFrame(init)", ApplyNDuiUnitFrame, frame)
        end)
    end)
    if ok then
        initCallbackRegistered = true
    end
end

local function InstallHooks()
    local objects, oUF, ns = GetNDuiUnitFrames()
    if not oUF then
        return false
    end

    RegisterInitCallback(oUF)

    if hooksInstalled then
        return true
    end

    local B = ns and ns[1]
    local UF = B and B.GetModule and B:GetModule("UnitFrames")
    if type(UF) ~= "table" then
        return false
    end

    local refreshMethods = {
        "UpdateTextScale",
        "UpdateRaidTextScale",
        "UpdateUFAuras",
        "RefreshUFAuras",
        "RefreshBuffAndDebuff",
        "UpdatePartyElements",
        "ToggleAddPower",
        "ToggleUFClassPower",
        "CreateAndUpdatePartyHeader",
        "CreateAndUpdateRaidHeader",
        "UpdatePartyPetHeader",
    }

    for _, method in ipairs(refreshMethods) do
        if type(UF[method]) == "function" then
            SafeHook("UF." .. method, UF, method, function()
                QueueRefresh()
            end)
        end
    end

    if type(UF.UpdateHealthBarColor) == "function" then
        SafeHook("UF.UpdateHealthBarColor", UF, "UpdateHealthBarColor", function(frame)
            if IsLightModeEnabled() and frame then
                ApplyLightModeToUnitFrame(frame)
            end
        end)
    end

    if type(UF.HealthPostUpdate) == "function" then
        SafeHook("UF.HealthPostUpdate", UF, "HealthPostUpdate", function(element, unit)
            local frame = element and element.__owner
            if not (IsLightModeEnabled() and frame and frame.Health == element and SINGLE_LIGHT_MODE_STYLES[frame.mystyle]) then
                return
            end
            if Skins and Skins.ApplyLightModeToBar then
                Skins.ApplyLightModeToBar(element, unit or ResolveUnitFrameUnit(frame))
            end
        end)
    end

    if type(UF.PostCreateButton) == "function" then
        SafeHook("UF.PostCreateButton", UF, "PostCreateButton", function(_, button)
            if IsNDuiEnabled() and button then
                ApplyNDuiUnitFrame(button)
            end
        end)
    end

    hooksInstalled = true
    QueueRefresh(0)
    return true
end

local retryToken = 0
local retryDelays = { 0.25, 0.5, 1, 2, 4 }

local function EnableNDuiTextShadow(attempt)
    if not IsNDuiEnabled() then
        return
    end

    if InstallHooks() then
        QueueRefresh(0)
        return
    end

    attempt = attempt or 1
    local delay = retryDelays[attempt]
    if delay and C_Timer and C_Timer.After then
        local token = retryToken
        ScheduleAfter(delay, function()
            if token == retryToken then
                EnableNDuiTextShadow(attempt + 1)
            end
        end)
    end
end

local function RefreshEnabledState()
    retryToken = retryToken + 1
    if IsNDuiEnabled() then
        EnableNDuiTextShadow(1)
    end
end

local function RequestLightModeRefresh(event)
    if IsLightModeEnabled() then
        QueueRefresh(0, event)
    end
end

if YUI.Event then
    YUI.Event:On("YUI_DB_READY", function()
        RefreshEnabledState()
    end, nil, { priority = -200 })

    YUI.Event:On("PLAYER_LOGIN", function()
        RefreshEnabledState()
    end, nil, { priority = -200 })

    YUI.Event:On("PLAYER_ENTERING_WORLD", function()
        RefreshEnabledState()
    end, nil, { priority = -200 })

    YUI.Event:On("ADDON_LOADED", function(_, addonName)
        if addonName == "NDui" then
            RefreshEnabledState()
        end
    end, nil, { priority = -200 })

    YUI.Event:On("YUI_APPEARANCE_SKIN_OPTION_CHANGED", function(_, key)
        if key == ENABLE_KEY or key == OPTION_KEY or key == LIGHT_MODE_KEY then
            RefreshEnabledState()
        end
    end)

    YUI.Event:On("PLAYER_TARGET_CHANGED", RequestLightModeRefresh, nil, { priority = -200 })
    YUI.Event:On("PLAYER_FOCUS_CHANGED", RequestLightModeRefresh, nil, { priority = -200 })
    YUI.Event:On("GROUP_ROSTER_UPDATE", RequestLightModeRefresh, nil, {
        priority = -200,
        traceName = "Appearance:NDui:GROUP_ROSTER_UPDATE",
        throttle = 0.1,
    })
    YUI.Event:On("UNIT_PET", RequestLightModeRefresh, nil, { priority = -200 })
end

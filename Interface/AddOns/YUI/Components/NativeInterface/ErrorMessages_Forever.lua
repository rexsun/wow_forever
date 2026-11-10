local _, addonTable = ...
local YUI = _G.YUI or addonTable
local Native = YUI and YUI.NativeInterface
local Security = YUI and YUI.API and YUI.API.Security
if not (Native and YUI.IsForever == true and Security) then return end

local LAYOUT_ID = Native.ERROR_MESSAGES_LAYOUT_ID
local owner = {}
local holder, errorPreview, infoPreview, source, originalPoint
local registered, active, restoreNeeded = false, false, false
local waitingCombat, waitingFrame = false, false
local lastReason = "disabled"

local function Public(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Number(value)
    return Public(value) and type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function Method(frame, method, ...)
    return Security.SafeMethod("NativeInterface:error-messages:" .. method, frame, method, ...)
end

local function Usable(frame)
    if not frame then return false end
    for _, method in ipairs({ "IsForbidden", "IsProtected", "HasSecretValues" }) do
        if frame[method] then
            local ok, value = Method(frame, method)
            if not ok or not Public(value) or value ~= false then return false end
        end
    end
    return type(frame.GetPoint) == "function" and type(frame.SetPoint) == "function"
end

local function ReadPoint(frame)
    local ok, count = Method(frame, "GetNumPoints")
    if not ok or not Public(count) or count ~= 1 then return nil end
    local pointOK, point, relative, relativePoint, x, y = Method(frame, "GetPoint", 1)
    if not pointOK or not Public(point) or not Public(relative) or not Public(relativePoint)
        or type(point) ~= "string" or type(relativePoint) ~= "string"
        or not Number(x) or not Number(y) then return nil end
    return { point = point, relative = relative, relativePoint = relativePoint, x = x, y = y }
end

local function WritePoint(frame, point)
    return Method(frame, "ClearAllPoints")
        and Method(frame, "SetPoint", point.point, point.relative, point.relativePoint, point.x, point.y)
end

local function SetPreview(shown)
    if shown and active and not errorPreview then
        local gui = YUI.GUI2
        errorPreview = gui:CreateText(holder, Native:GetLocaleText("preview.error_messages.error"),
            "font.size.lg", "color.state.error", "CENTER")
        infoPreview = gui:CreateText(holder, Native:GetLocaleText("preview.error_messages.info"),
            "font.size.lg", "color.state.warning", "CENTER")
        if _G.ErrorFont then
            errorPreview:SetFontObject(_G.ErrorFont)
            infoPreview:SetFontObject(_G.ErrorFont)
        end
        if _G.RED_FONT_COLOR then
            errorPreview:SetText(RED_FONT_COLOR:WrapTextInColorCode(Native:GetLocaleText("preview.error_messages.error")))
        end
        if _G.YELLOW_FONT_COLOR then
            infoPreview:SetText(YELLOW_FONT_COLOR:WrapTextInColorCode(Native:GetLocaleText("preview.error_messages.info")))
        end
        errorPreview:SetPoint("TOP", holder, "TOP", 0, 0)
        infoPreview:SetPoint("BOTTOM", holder, "BOTTOM", 0, 0)
    end
    if errorPreview then errorPreview:SetShown(shown and active) end
    if infoPreview then infoPreview:SetShown(shown and active) end
end

local function OnReady(_, addonName)
    if addonName == nil or addonName == "Blizzard_UIErrorsFrame" then
        Native:RefreshErrorMessages()
    end
end

local function WaitFor(combat, frame)
    if waitingCombat == combat and waitingFrame == frame then return end
    YUI.Event:OffOwner(owner)
    waitingCombat, waitingFrame = combat, frame
    local options = { moduleId = Native.MODULE_ID }
    if combat then YUI.Event:On("PLAYER_REGEN_ENABLED", OnReady, owner, options) end
    if frame then YUI.Event:On("ADDON_LOADED", OnReady, owner, options) end
end

local function Release()
    SetPreview(false)
    active = false
    if registered then
        YUI.Layout:UnregisterFrame(LAYOUT_ID)
        registered = false
    end
    if source then
        if not Usable(source) then
            lastReason = "restore-unavailable"
            WaitFor(true, false)
            return false
        end
        local current = ReadPoint(source)
        if not current and not restoreNeeded then
            lastReason = "restore-anchor-unavailable"
            WaitFor(true, false)
            return false
        end
        if restoreNeeded or (current and current.relative == holder) then
            if not WritePoint(source, originalPoint) then
                restoreNeeded = true
                lastReason = "restore-failed"
                WaitFor(true, false)
                return false
            end
        end
    end
    source, originalPoint = nil, nil
    active, restoreNeeded = false, false
    if holder then holder:Hide() end
    WaitFor(false, false)
    lastReason = "disabled"
    return true
end

local function Refresh(enabled)
    if not enabled then SetPreview(false) end
    if not enabled and not source and not registered then
        WaitFor(false, false)
        lastReason = "disabled"
        return true
    end
    if Security.InCombatLockdown() then
        lastReason = "combat-pending"
        WaitFor(true, false)
        return false
    end
    if not enabled then return Release() end
    if active and source == _G.UIErrorsFrame and not restoreNeeded then
        local current = Usable(source) and ReadPoint(source)
        if not current or current.relative ~= holder then
            Release()
            lastReason = "ownership-changed"
            return false
        end
        YUI.Layout:RefreshFrame(LAYOUT_ID)
        WaitFor(false, false)
        lastReason = "active"
        return true
    end
    if source and not Release() then return false end
    local frame = _G.UIErrorsFrame
    if not frame then
        lastReason = "frame-pending"
        WaitFor(false, true)
        return false
    end
    WaitFor(false, false)
    local point = Usable(frame) and ReadPoint(frame)
    if not point or point.relative ~= _G.UIParent then
        lastReason = "native-anchor-unavailable"
        return false
    end
    local layout, gui = YUI.Layout, YUI.GUI2
    if not (layout and layout.RegisterFrame and gui and gui.CreateFrame and gui.CreateText) then
        lastReason = "layout-unavailable"
        return false
    end
    if not holder then
        local holderOK, value = Security.SafeCall("NativeInterface:error-messages:holder", gui.CreateFrame, gui, UIParent, {
            name = "YUINativeErrorMessagesHolder", width = 512, height = 60,
            mouse = false, frameStrata = "DIALOG",
        })
        if not holderOK or not value then
            lastReason = "holder-unavailable"
            return false
        end
        holder = value
    end
    source, originalPoint = frame, point
    local ok, entry = Security.SafeCall("NativeInterface:error-messages:register", layout.RegisterFrame,
        layout, LAYOUT_ID, {
            frame = holder,
            title = Native:GetLocaleText("layout.error_messages"),
            category = "component", editModeCategory = "information",
            defaultPlacement = {
                version = 2,
                anchor = { point = point.point, relative = "UIParent", relativePoint = point.relativePoint },
                offset = { x = point.x, y = point.y },
            },
            movable = true, snap = true, combatProtected = false,
            anchorTargets = { "UIParent" }, strictAnchorTargets = true,
            minWidth = 512, minHeight = 60,
            openPluginSettings = function() Native:OpenSettings() end,
            onEnterEditMode = function() SetPreview(true) end,
            onExitEditMode = function() SetPreview(false) end,
            onEditModeFilterChanged = function(_, visible) SetPreview(visible) end,
        })
    registered = ok and entry and true or false
    if not registered then
        Security.SafeCall("NativeInterface:error-messages:unregister", layout.UnregisterFrame, layout, LAYOUT_ID)
        Release()
        lastReason = "registration-failed"
        return false
    end
    restoreNeeded = true
    if not WritePoint(source, { point = "TOP", relative = holder, relativePoint = "TOP", x = 0, y = 0 }) then
        Release()
        lastReason = "anchor-failed"
        return false
    end
    active, restoreNeeded = true, false
    holder:Show()
    if layout.RefreshEditSessionEntry then layout:RefreshEditSessionEntry(LAYOUT_ID) end
    lastReason = "active"
    return true
end

function Native:RefreshErrorMessages()
    return Refresh(self.runtimeEnabled and self:GetConfig().manageErrorMessages == true)
end

function Native:ReleaseErrorMessages()
    return Refresh(false)
end

function Native:GetErrorMessagesDiagnostics()
    return {
        active = active, registered = registered, pending = waitingCombat or waitingFrame,
        lastReason = lastReason,
    }
end

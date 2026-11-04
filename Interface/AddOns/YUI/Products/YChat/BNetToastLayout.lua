local YUI = _G.YUI
local YChat = YUI and YUI.YChat
if not YChat or (YUI.IsRetail or YUI.IsForever) ~= true then return end

local Adapter = YChat.Adapter
local GUI2 = YUI.GUI2
if not Adapter or not GUI2 then return end

local ToastLayout = { enabled = false, pending = false, restorePending = false }
YChat.BNetToastLayout = ToastLayout

local L = YUI.Locale and YUI.Locale:Get("YChat") or {}
local LAYOUT_ID = "ychat.bnetToast"
local HOLDER_NAME = "YUI_YChatBNetToastHolder"
local points = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local nativePoints, scratchPoints = {}, {}
local nativePointCount = 0
local hasSnapshot = false
local applying = false

local function Safe(value)
    return Adapter:IsExplicitlySafeValue(value) == true
end

local function Finite(value)
    return Safe(value) and type(value) == "number"
        and value > -math.huge and value < math.huge
end

local function MutationAllowed(frame)
    local state = Adapter:GetRestrictionState()
    return (state == "OPEN" or state == "PAUSED")
        and Adapter:CanCallProtected(frame) == true
end

local function NativeFrame()
    local frame = _G.BNToastFrame
    if not Safe(frame) or not frame
        or type(frame.GetNumPoints) ~= "function"
        or type(frame.GetPoint) ~= "function"
        or type(frame.ClearAllPoints) ~= "function"
        or type(frame.SetPoint) ~= "function"
        or type(frame.GetWidth) ~= "function"
        or type(frame.GetHeight) ~= "function"
        or type(frame.IsShown) ~= "function"
        or type(frame.HookScript) ~= "function"
    then
        return nil
    end
    return frame
end

local function CaptureNative(frame)
    local ok, count = pcall(frame.GetNumPoints, frame)
    if not ok or not Finite(count) or count < 1 or count > 8 or count % 1 ~= 0 then
        return false
    end
    for index = 1, count do
        local read, point, relative, relativePoint, x, y = pcall(frame.GetPoint, frame, index)
        if not read or not Safe(point) or not Safe(relative) or not Safe(relativePoint)
            or type(point) ~= "string" or not points[point]
            or type(relativePoint) ~= "string" or not points[relativePoint]
            or not Finite(x) or not Finite(y)
        then
            return false
        end
        local entry = scratchPoints[index]
        if not entry then entry = {}; scratchPoints[index] = entry end
        entry[1], entry[2], entry[3], entry[4], entry[5] = point, relative, relativePoint, x, y
    end
    nativePoints, scratchPoints = scratchPoints, nativePoints
    nativePointCount = count
    hasSnapshot = true
    return true
end

local function MatchesNativeSnapshot(frame)
    local ok, count = pcall(frame.GetNumPoints, frame)
    if not ok or not Safe(count) or count ~= nativePointCount then return false end
    for index = 1, count do
        local read, point, relative, relativePoint, x, y = pcall(frame.GetPoint, frame, index)
        if not read or not Safe(point) or not Safe(relative) or not Safe(relativePoint)
            or not Safe(x) or not Safe(y)
        then
            return false
        end
        local p = nativePoints[index]
        if point ~= p[1] or relative ~= p[2] or relativePoint ~= p[3] or x ~= p[4] or y ~= p[5] then
            return false
        end
    end
    return true
end

local function ApplyNative()
    if not ToastLayout.enabled or applying then return true end
    local appearance = YChat.Appearance
    if appearance and appearance.enabled ~= true then return true end
    local frame, holder = NativeFrame(), ToastLayout.holder
    if not frame or not holder or not hasSnapshot or not MutationAllowed(frame) then
        ToastLayout.pending = true
        return false, "bnet-toast-placement-pending"
    end
    local read, count = pcall(frame.GetNumPoints, frame)
    if read and Safe(count) and count == 1 then
        local ok, point, relative, relativePoint, x, y = pcall(frame.GetPoint, frame, 1)
        if ok and Safe(point) and Safe(relative) and Safe(relativePoint) and Safe(x) and Safe(y)
            and point == "BOTTOMLEFT" and relative == holder and relativePoint == "BOTTOMLEFT"
            and x == 0 and y == 0
        then
            ToastLayout.pending = false
            return true
        end
    end
    applying = true
    local ok = pcall(frame.ClearAllPoints, frame)
        and pcall(frame.SetPoint, frame, "BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
    applying = false
    ToastLayout.pending = not ok
    return ok, not ok and "bnet-toast-placement-failed" or nil
end

local function SyncSize(frame)
    local holder = ToastLayout.holder
    if not holder then return true end
    local widthOK, width = pcall(frame.GetWidth, frame)
    local heightOK, height = pcall(frame.GetHeight, frame)
    if not widthOK or not heightOK or not Finite(width) or not Finite(height)
        or width <= 0 or height <= 0
    then
        return false
    end
    if holder:GetWidth() ~= width or holder:GetHeight() ~= height then
        holder:SetSize(width, height)
    end
    return true
end

local function DefaultPlacement()
    local container = _G.ChatAlertFrame
    if container and type(container.GetLeft) == "function" and type(container.GetBottom) == "function" then
        local xOK, x = pcall(container.GetLeft, container)
        local yOK, y = pcall(container.GetBottom, container)
        if xOK and yOK and Finite(x) and Finite(y) then
            local point = "BOTTOMLEFT"
            if type(container.GetJustification) == "function" and type(container.GetWidth) == "function" then
                local justifyOK, justify = pcall(container.GetJustification, container)
                local widthOK, width = pcall(container.GetWidth, container)
                if justifyOK and Safe(justify) and widthOK and Finite(width) then
                    if justify == "RIGHT" then point, x = "BOTTOMRIGHT", x + width
                    elseif justify == "CENTER" then point, x = "BOTTOM", x + width / 2 end
                end
            end
            ToastLayout.defaultPlacement = {
                anchor = { point = point, relative = "UIParent", relativePoint = "BOTTOMLEFT" },
                offset = { x = x, y = y },
            }
        end
    end
    return ToastLayout.defaultPlacement
end

local function IsEnabled()
    return ToastLayout.enabled and ToastLayout.layoutRegistered == true
end

local function OpenSettings()
    if YUI.Settings and YUI.Settings.OpenProduct then
        YUI.Settings:OpenProduct(YChat.PRODUCT_ID, YChat.SETTINGS_ENTRY)
    end
end

local function NativeAnchorsUpdated()
    if not ToastLayout.enabled or applying then return end
    local frame = NativeFrame()
    if not frame or not MutationAllowed(frame) then
        ToastLayout.pending = true
        return
    end
    local shownOK, shown = pcall(frame.IsShown, frame)
    -- Hidden toasts are skipped by the native container; their current point may be ours.
    if not shownOK or not Safe(shown) or shown ~= true then return end
    if not CaptureNative(frame) then ToastLayout.pending = true; return end
    SyncSize(frame)
    ApplyNative()
end

local function NativeShown(frame)
    if not ToastLayout.enabled or applying or frame ~= _G.BNToastFrame then return end
    ApplyNative()
end

local function NativeSizeChanged(frame)
    if not ToastLayout.enabled or applying or frame ~= _G.BNToastFrame then return end
    if MutationAllowed(frame) then SyncSize(frame) end
end

local function EnsureHolder(frame)
    local layout = YUI.Layout
    if not layout or type(layout.RegisterFrame) ~= "function" or not DefaultPlacement() then return false end
    if not ToastLayout.holder then
        local holder = GUI2:CreateFrame(_G.UIParent, { name = HOLDER_NAME, movable = true, clamped = false })
        if not holder then return false end
        ToastLayout.holder = holder
        holder:Hide()
    end
    if not SyncSize(frame) then return false end
    if not ToastLayout.layoutRegistered then
        local entry = layout:RegisterFrame(LAYOUT_ID, {
            frame = ToastLayout.holder,
            title = L["layout.bnet_toast"] or "Battle.net notifications",
            category = "product",
            defaultPlacement = DefaultPlacement,
            movable = true,
            snap = true,
            anchorTargets = { "UIParent" },
            strictAnchorTargets = true,
            combatProtected = false,
            showOnlyInEditMode = true,
            isEnabled = IsEnabled,
            onApply = ApplyNative,
            openPluginSettings = OpenSettings,
        })
        ToastLayout.layoutRegistered = entry and true or false
        if not entry then return false end
    end
    layout:RefreshFrame(LAYOUT_ID)
    return true
end

function ToastLayout:OnWindowsChanged()
    if not self.enabled then return true end
    local frame = NativeFrame()
    if not frame or not MutationAllowed(frame) then
        self.pending = true
        return true, "bnet-toast-unavailable"
    end
    if (not hasSnapshot and not CaptureNative(frame))
        or not Adapter:InstallBNetToastLayoutHooks(frame, NativeAnchorsUpdated, NativeShown, NativeSizeChanged)
        or not EnsureHolder(frame)
    then
        self.pending = true
        return false, "bnet-toast-prepare-pending"
    end
    return ApplyNative()
end

function ToastLayout:RestoreAll()
    self.enabled = false
    self.pending = false
    if self.holder then self.holder:Hide() end
    if self.layoutRegistered and YUI.Layout then YUI.Layout:RefreshFrame(LAYOUT_ID) end
    if not hasSnapshot then self.restorePending = false; return true end
    local frame = NativeFrame()
    if not frame or not MutationAllowed(frame) then
        self.restorePending = true
        return false, "bnet-toast-restore-pending"
    end
    local restored = pcall(frame.ClearAllPoints, frame)
    for index = 1, nativePointCount do
        local p = nativePoints[index]
        restored = restored and pcall(frame.SetPoint, frame, p[1], p[2], p[3], p[4], p[5])
    end
    restored = restored and MatchesNativeSnapshot(frame)
    self.restorePending = not restored
    if restored then hasSnapshot = false end
    return restored, not restored and "bnet-toast-restore-failed" or nil
end

function ToastLayout:SetEnabled(enabled)
    if enabled ~= true then return self:RestoreAll() end
    if self.restorePending then
        local restored, reason = self:RestoreAll()
        if not restored then return false, reason end
    end
    self.enabled = true
    return self:OnWindowsChanged()
end

function ToastLayout:OnPlayerRegenEnabled()
    if self.restorePending then return self:RestoreAll() end
    if self.pending then return self:OnWindowsChanged() end
    return true
end

function ToastLayout:GetRuntimeGauges(target)
    target = target or {}
    target.bnetToastRegistered = self.layoutRegistered and 1 or 0
    target.bnetToastPending = self.pending and 1 or 0
    target.bnetToastRestorePending = self.restorePending and 1 or 0
    return target
end

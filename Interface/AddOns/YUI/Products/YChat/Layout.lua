local YUI = _G.YUI
local YChat = YUI and YUI.YChat
if not YChat or (YUI.IsForever or YUI.IsRetail) ~= true then return end

local Adapter = YChat.Adapter
local GUI2 = YUI.GUI2 or YUI.GUI
if not Adapter then return end
local L = YUI.Locale and YUI.Locale:Get("YChat") or {}

local MainLayout = {}
YChat.MainLayout = MainLayout

local LAYOUT_ID = "ychat.main"
local HOLDER_NAME = "YUI_YChatMainHolder"
local abs = math.abs
local floor = math.floor
local huge = math.huge
local max = math.max
local pcall = pcall
local type = type
local InstallHooks
local DisableFrameScreenClamp

local function T(key, fallback)
    local value = L[key]
    return type(value) == "string" and value ~= "" and value or fallback
end

local function OpenChatSettings()
    local settings = YUI.Settings
    if settings and type(settings.OpenProduct) == "function" then
        return settings:OpenProduct(YChat.PRODUCT_ID, YChat.SETTINGS_ENTRY)
    end
    if type(YUI.OpenSettings) == "function" then
        return YUI:OpenSettings("YChat", YChat.PRODUCT_ID)
    end
    return false
end

MainLayout.enabled = false
MainLayout.holder = nil
MainLayout.layoutRegistered = false
MainLayout.snapshot = nil
MainLayout.applying = false
MainLayout.pending = false
MainLayout.lastReason = "not-started"
MainLayout.boundsWidth = nil
MainLayout.boundsHeight = nil
MainLayout.boundsOffsetX = 0
MainLayout.boundsOffsetY = 0
MainLayout.screenBoundsWidth = nil
MainLayout.screenBoundsHeight = nil
MainLayout.screenBoundsOffsetX = 0
MainLayout.screenBoundsOffsetY = 0
MainLayout.syncScheduled = false
MainLayout.syncTimer = nil

local function CreateEarlyHolder()
    local parent = _G.UIParent
    if not parent or not (GUI2 and type(GUI2.CreateFrame) == "function") then
        return nil, "layout-gui-unavailable"
    end

    local holder = _G[HOLDER_NAME]
    if holder then
        if type(holder.GetName) ~= "function"
            or type(holder.GetParent) ~= "function"
            or holder:GetName() ~= HOLDER_NAME
            or holder:GetParent() ~= parent
        then
            return nil, "layout-holder-identity-mismatch"
        end
    else
        holder = GUI2:CreateFrame(parent, {
            name = HOLDER_NAME,
            width = YChat.MAIN_WINDOW_MIN_WIDTH,
            height = YChat.MAIN_WINDOW_MIN_HEIGHT,
            movable = true,
            clamped = false,
        })
    end
    if not holder then return nil, "layout-holder-create-failed" end

    holder:SetSize(YChat.MAIN_WINDOW_MIN_WIDTH, YChat.MAIN_WINDOW_MIN_HEIGHT)
    if type(holder.SetClampedToScreen) == "function" then
        holder:SetClampedToScreen(false)
    end
    holder:Hide()
    return holder
end

MainLayout.holder, MainLayout.holderReason = CreateEarlyHolder()

local function IsFinite(value)
    return type(value) == "number" and value > -huge and value < huge
end

local function ReadFrameSize(frame)
    if not frame
        or type(frame.GetWidth) ~= "function"
        or type(frame.GetHeight) ~= "function"
    then
        return nil
    end
    local widthOK, width = pcall(frame.GetWidth, frame)
    local heightOK, height = pcall(frame.GetHeight, frame)
    if not widthOK or not heightOK
        or not IsFinite(width) or width <= 0
        or not IsFinite(height) or height <= 0
    then
        return nil
    end
    return width, height
end

local function IsPlacementSane(placement)
    local anchor = placement and placement.anchor
    local offset = placement and placement.offset
    if type(anchor) ~= "table" or type(offset) ~= "table"
        or anchor.relative ~= "UIParent"
        or not IsFinite(offset.x)
        or not IsFinite(offset.y)
    then
        return false
    end
    local width, height = ReadFrameSize(_G.UIParent)
    local limitX = max(width and width * 1.5 or 0, 2048)
    local limitY = max(height and height * 1.5 or 0, 2048)
    return abs(offset.x) <= limitX and abs(offset.y) <= limitY
end

local function SafeDefaultPlacement()
    return {
        version = 2,
        anchor = {
            point = "BOTTOMLEFT",
            relative = "UIParent",
            relativePoint = "BOTTOMLEFT",
        },
        offset = { x = 32, y = 44 },
    }
end

local function SafeFrame()
    local frame = _G.ChatFrame1
    if frame == nil or frame ~= _G.DEFAULT_CHAT_FRAME then
        return nil, "layout-main-frame-identity-mismatch"
    end
    if not Adapter:IsTrustedSupportedFrame(frame) then
        return nil, "layout-main-frame-unsupported"
    end
    if Adapter:CanCallProtected(frame) ~= true then
        return nil, "layout-main-frame-protected"
    end
    return frame
end

local function CapturePoints(frame)
    if type(frame.GetNumPoints) ~= "function"
        or type(frame.GetPoint) ~= "function"
    then
        return nil, "layout-point-api-missing"
    end
    local countOK, count = pcall(frame.GetNumPoints, frame)
    if not countOK or not IsFinite(count) or count < 1 or count > 8 or floor(count) ~= count then
        return nil, "layout-point-count-invalid"
    end
    local points = {}
    for index = 1, count do
        local ok, point, relativeTo, relativePoint, x, y =
            pcall(frame.GetPoint, frame, index)
        if not ok
            or type(point) ~= "string"
            or type(relativePoint) ~= "string"
            or not IsFinite(x)
            or not IsFinite(y)
            or Adapter:IsExplicitlySafeValue(relativeTo) ~= true
        then
            return nil, "layout-point-invalid"
        end
        points[index] = { point, relativeTo, relativePoint, x, y }
    end
    return points
end

local function CaptureSnapshot(frame)
    local points, reason = CapturePoints(frame)
    if not points then return nil, reason end
    local widthOK, width = pcall(frame.GetWidth, frame)
    local heightOK, height = pcall(frame.GetHeight, frame)
    if not widthOK or not heightOK or not IsFinite(width) or not IsFinite(height) then
        return nil, "layout-size-capture-failed"
    end
    local movable
    if type(frame.IsMovable) == "function" then
        local ok
        ok, movable = pcall(frame.IsMovable, frame)
        if not ok or type(movable) ~= "boolean" then
            return nil, "layout-movable-capture-failed"
        end
    end
    local userPlaced
    if type(frame.IsUserPlaced) == "function" then
        local ok
        ok, userPlaced = pcall(frame.IsUserPlaced, frame)
        if not ok or type(userPlaced) ~= "boolean" then
            return nil, "layout-user-placed-capture-failed"
        end
    end
    if type(frame.IsClampedToScreen) ~= "function"
        or type(frame.GetClampRectInsets) ~= "function"
        or type(frame.SetClampedToScreen) ~= "function"
        or type(frame.SetClampRectInsets) ~= "function"
    then
        return nil, "layout-clamp-api-missing"
    end
    local clampedOK, clampedToScreen = pcall(frame.IsClampedToScreen, frame)
    if not clampedOK or type(clampedToScreen) ~= "boolean" then
        return nil, "layout-clamped-state-capture-failed"
    end
    local insetsOK, clampLeft, clampRight, clampTop, clampBottom =
        pcall(frame.GetClampRectInsets, frame)
    if not insetsOK
        or not IsFinite(clampLeft)
        or not IsFinite(clampRight)
        or not IsFinite(clampTop)
        or not IsFinite(clampBottom)
    then
        return nil, "layout-clamp-insets-capture-failed"
    end
    return {
        points = points,
        width = width,
        height = height,
        movable = movable,
        userPlaced = userPlaced,
        clampedToScreen = clampedToScreen,
        clampInsets = { clampLeft, clampRight, clampTop, clampBottom },
    }
end

local function CapturePlacement(frame)
    local parent = _G.UIParent
    if not parent
        or type(frame.GetNumPoints) ~= "function"
        or type(frame.GetCenter) ~= "function"
        or type(parent.GetCenter) ~= "function"
    then
        return nil
    end
    local countOK, count = pcall(frame.GetNumPoints, frame)
    if not countOK or not IsFinite(count) or count < 1 then return nil end
    local frameOK, x, y = pcall(frame.GetCenter, frame)
    local parentOK, parentX, parentY = pcall(parent.GetCenter, parent)
    if not frameOK
        or not parentOK
        or not IsFinite(x)
        or not IsFinite(y)
        or not IsFinite(parentX)
        or not IsFinite(parentY)
    then
        return nil
    end
    return {
        version = 2,
        anchor = {
            point = "CENTER",
            relative = "UIParent",
            relativePoint = "CENTER",
        },
        offset = {
            x = floor((x - parentX) + 0.5),
            y = floor((y - parentY) + 0.5),
        },
    }
end

local function ReadUIParentAnchor(frame)
    if not frame
        or type(frame.GetNumPoints) ~= "function"
        or type(frame.GetPoint) ~= "function"
    then
        return nil, "layout-anchor-api-missing"
    end
    local countOK, count = pcall(frame.GetNumPoints, frame)
    if not countOK or count ~= 1 then
        return nil, "layout-anchor-count-invalid"
    end
    local pointOK, point, relativeTo, relativePoint, x, y =
        pcall(frame.GetPoint, frame, 1)
    if not pointOK
        or type(point) ~= "string"
        or relativeTo ~= _G.UIParent
        or type(relativePoint) ~= "string"
        or not IsFinite(x)
        or not IsFinite(y)
    then
        return nil, "layout-anchor-not-uiparent"
    end
    return { point, relativeTo, relativePoint, x, y }
end

local function SetHolderPlacement(holder, placement)
    if not IsPlacementSane(placement) then
        return false, "layout-holder-placement-invalid"
    end
    local ok = pcall(holder.ClearAllPoints, holder)
    if ok then
        ok = pcall(
            holder.SetPoint,
            holder,
            placement.anchor.point,
            _G.UIParent,
            placement.anchor.relativePoint,
            placement.offset.x,
            placement.offset.y
        )
    end
    return ok, ok and nil or "layout-holder-placement-failed"
end

local function GetMoverBounds()
    local holder = MainLayout.holder
    return MainLayout.boundsWidth or holder:GetWidth(),
        MainLayout.boundsHeight or holder:GetHeight(),
        MainLayout.boundsOffsetX or 0,
        MainLayout.boundsOffsetY or 0
end

local function GetClampBounds()
    local holder = MainLayout.holder
    return MainLayout.screenBoundsWidth or MainLayout.boundsWidth or holder:GetWidth(),
        MainLayout.screenBoundsHeight or MainLayout.boundsHeight or holder:GetHeight(),
        MainLayout.screenBoundsOffsetX or MainLayout.boundsOffsetX or 0,
        MainLayout.screenBoundsOffsetY or MainLayout.boundsOffsetY or 0
end

local function ResetBoundsToHolder(holder)
    local width, height = ReadFrameSize(holder)
    width = width or YChat.MAIN_WINDOW_MIN_WIDTH
    height = height or YChat.MAIN_WINDOW_MIN_HEIGHT
    MainLayout.boundsWidth = width
    MainLayout.boundsHeight = height
    MainLayout.boundsOffsetX = 0
    MainLayout.boundsOffsetY = 0
    MainLayout.screenBoundsWidth = width
    MainLayout.screenBoundsHeight = height
    MainLayout.screenBoundsOffsetX = 0
    MainLayout.screenBoundsOffsetY = 0
end

local function IsMeasuredEnvelopePlausible(
    holder,
    width,
    height,
    offsetX,
    offsetY,
    screenWidth,
    screenHeight,
    screenOffsetX,
    screenOffsetY
)
    local parentWidth, parentHeight = ReadFrameSize(_G.UIParent)
    local holderWidth, holderHeight = ReadFrameSize(holder)
    if not parentWidth or not parentHeight or not holderWidth or not holderHeight then
        return false
    end
    return IsFinite(width) and width > 0 and width <= parentWidth
        and IsFinite(height) and height > 0 and height <= parentHeight
        and IsFinite(offsetX) and abs(offsetX) <= parentWidth
        and IsFinite(offsetY) and abs(offsetY) <= parentHeight
        and IsFinite(screenWidth) and screenWidth > 0 and screenWidth <= parentWidth
        and IsFinite(screenHeight) and screenHeight > 0 and screenHeight <= parentHeight
        and IsFinite(screenOffsetX) and abs(screenOffsetX) <= parentWidth
        and IsFinite(screenOffsetY) and abs(screenOffsetY) <= parentHeight
end

local function ClampEnvelopeToScreen(holder)
    local parent = _G.UIParent
    local width = MainLayout.screenBoundsWidth or MainLayout.boundsWidth
    local height = MainLayout.screenBoundsHeight or MainLayout.boundsHeight
    local offsetX = MainLayout.screenBoundsOffsetX or MainLayout.boundsOffsetX or 0
    local offsetY = MainLayout.screenBoundsOffsetY or MainLayout.boundsOffsetY or 0
    if not parent
        or not IsFinite(width)
        or not IsFinite(height)
        or type(holder.GetCenter) ~= "function"
        or type(parent.GetCenter) ~= "function"
        or type(parent.GetWidth) ~= "function"
        or type(parent.GetHeight) ~= "function"
    then
        return false, "layout-screen-envelope-unavailable"
    end

    local holderOK, holderX, holderY = pcall(holder.GetCenter, holder)
    local parentOK, parentX, parentY = pcall(parent.GetCenter, parent)
    local widthOK, parentWidth = pcall(parent.GetWidth, parent)
    local heightOK, parentHeight = pcall(parent.GetHeight, parent)
    if not holderOK
        or not parentOK
        or not widthOK
        or not heightOK
        or not IsFinite(holderX)
        or not IsFinite(holderY)
        or not IsFinite(parentX)
        or not IsFinite(parentY)
        or not IsFinite(parentWidth)
        or not IsFinite(parentHeight)
        or parentWidth <= 0
        or parentHeight <= 0
    then
        return false, "layout-screen-envelope-invalid"
    end

    local screenLeft = parentX - parentWidth * 0.5
    local screenRight = parentX + parentWidth * 0.5
    local screenBottom = parentY - parentHeight * 0.5
    local screenTop = parentY + parentHeight * 0.5
    local envelopeX = holderX + offsetX
    local envelopeY = holderY + offsetY
    local envelopeLeft = envelopeX - width * 0.5
    local envelopeRight = envelopeX + width * 0.5
    local envelopeBottom = envelopeY - height * 0.5
    local envelopeTop = envelopeY + height * 0.5
    local shiftX = 0
    local shiftY = 0
    if envelopeLeft < screenLeft then
        shiftX = screenLeft - envelopeLeft
    elseif envelopeRight > screenRight then
        shiftX = screenRight - envelopeRight
    end
    if envelopeBottom < screenBottom then
        shiftY = screenBottom - envelopeBottom
    elseif envelopeTop > screenTop then
        shiftY = screenTop - envelopeTop
    end
    if shiftX == 0 and shiftY == 0 then return true, false end

    local ok = pcall(holder.ClearAllPoints, holder)
    if ok then
        ok = pcall(
            holder.SetPoint,
            holder,
            "CENTER",
            parent,
            "CENTER",
            (holderX + shiftX) - parentX,
            (holderY + shiftY) - parentY
        )
    end
    return ok, ok and true or "layout-screen-envelope-clamp-failed"
end

local function RefreshMoverBounds(frame)
    local holder = MainLayout.holder
    if not holder then return false, "layout-holder-unavailable" end
    local width, height, offsetX, offsetY,
        screenWidth, screenHeight, screenOffsetX, screenOffsetY =
        Adapter:MeasureMainLayoutEnvelope(
            frame,
            holder,
            YChat.Appearance and YChat.Appearance:GetInputVisualInset(frame) or 0
        )
    if IsMeasuredEnvelopePlausible(
        holder,
        width,
        height,
        offsetX,
        offsetY,
        screenWidth,
        screenHeight,
        screenOffsetX,
        screenOffsetY
    ) then
        MainLayout.boundsWidth = width
        MainLayout.boundsHeight = height
        MainLayout.boundsOffsetX = offsetX
        MainLayout.boundsOffsetY = offsetY
        if IsFinite(screenWidth)
            and screenWidth > 0
            and IsFinite(screenHeight)
            and screenHeight > 0
            and IsFinite(screenOffsetX)
            and IsFinite(screenOffsetY)
        then
            MainLayout.screenBoundsWidth = screenWidth
            MainLayout.screenBoundsHeight = screenHeight
            MainLayout.screenBoundsOffsetX = screenOffsetX
            MainLayout.screenBoundsOffsetY = screenOffsetY
        else
            MainLayout.screenBoundsWidth = width
            MainLayout.screenBoundsHeight = height
            MainLayout.screenBoundsOffsetX = offsetX
            MainLayout.screenBoundsOffsetY = offsetY
        end
    else
        ResetBoundsToHolder(holder)
    end
    local clamped, clampReason = ClampEnvelopeToScreen(holder)
    return clamped, clamped and nil or clampReason
end

local function IsLayoutEnabled()
    return MainLayout.enabled == true
end

local function RepairSavedPlacement(layout, nativePlacement)
    if not layout
        or type(layout.GetPlacement) ~= "function"
        or type(layout.ResetFrame) ~= "function"
        or not IsPlacementSane(nativePlacement)
    then
        return false
    end
    local placement = layout:GetPlacement(LAYOUT_ID)
    if IsPlacementSane(placement) then return false end

    ResetBoundsToHolder(MainLayout.holder)
    local resetOK, reset = pcall(layout.ResetFrame, layout, LAYOUT_ID)
    if not resetOK or reset ~= true then
        if type(layout.SetPlacement) ~= "function" then return false end
        resetOK, reset = pcall(
            layout.SetPlacement,
            layout,
            LAYOUT_ID,
            nativePlacement,
            true
        )
        if not resetOK or reset ~= true then return false end
    end

    local readOK, repaired = pcall(layout.GetPlacement, layout, LAYOUT_ID)
    return readOK and IsPlacementSane(repaired)
end

local function EnsureHolder(frame)
    local holder = MainLayout.holder
    if not holder then return nil, MainLayout.holderReason or "layout-holder-unavailable" end
    if MainLayout.holderInitialized then return holder end

    holder:SetSize(frame:GetWidth(), frame:GetHeight())
    if type(holder.SetClampedToScreen) == "function" then
        holder:SetClampedToScreen(false)
    end

    local layout = YUI.Layout
    local placement = CapturePlacement(frame)
    local hasSavedPlacement = false
    if layout and type(layout.HasPlacement) == "function" then
        local savedOK, saved = pcall(layout.HasPlacement, layout, LAYOUT_ID)
        hasSavedPlacement = savedOK and saved == true
    end
    if not IsPlacementSane(placement) and not hasSavedPlacement then
        return nil, "layout-trusted-placement-unavailable"
    end

    local defaultPlacement = IsPlacementSane(placement)
        and placement or SafeDefaultPlacement()
    if not SetHolderPlacement(holder, defaultPlacement) then
        return nil, "layout-holder-placement-failed"
    end

    if layout and type(layout.RegisterFrame) == "function" then
        local entry = layout:RegisterFrame(LAYOUT_ID, {
            frame = holder,
            title = T("layout.chat_frame", "Chat Frame"),
            category = "product",
            defaultPlacement = defaultPlacement,
            movable = true,
            snap = true,
            anchorTargets = { "UIParent" },
            strictAnchorTargets = true,
            combatProtected = false,
            showOnlyInEditMode = true,
            minWidth = YChat.MAIN_WINDOW_MIN_WIDTH,
            minHeight = YChat.MAIN_WINDOW_MIN_HEIGHT,
            getMoverBounds = GetMoverBounds,
            getClampBounds = GetClampBounds,
            isEnabled = IsLayoutEnabled,
            openPluginSettings = OpenChatSettings,
        })
        MainLayout.layoutRegistered = entry ~= nil
        if not entry then return nil, "layout-register-failed" end
        if RepairSavedPlacement(layout, placement) then
            MainLayout.placementRepairCount = (MainLayout.placementRepairCount or 0) + 1
            if YUI.Print then
                YUI:Print("|cff66c6ffYChat:|r", T(
                    "layout.position_repaired",
                    "An invalid chat-frame position was reset to its default."
                ))
            end
        end
        local readOK, registeredPlacement = pcall(layout.GetPlacement, layout, LAYOUT_ID)
        if not readOK or not IsPlacementSane(registeredPlacement) then
            return nil, "layout-registered-placement-invalid"
        end
        if not SetHolderPlacement(holder, registeredPlacement) then
            return nil, "layout-holder-placement-failed"
        end
    end
    holder:Hide()
    MainLayout.holderInitialized = true
    return holder
end

local function RepairLegacyFrameAnchor(frame, holder)
    if type(frame.GetNumPoints) ~= "function"
        or type(frame.GetPoint) ~= "function"
    then
        return false, "layout-point-api-missing"
    end

    local countOK, count = pcall(frame.GetNumPoints, frame)
    if not countOK or not IsFinite(count) or count < 0 or count > 8 then
        return false, "layout-point-count-invalid"
    end

    local needsRepair = count == 0
    for index = 1, count do
        local pointOK, _, relativeTo = pcall(frame.GetPoint, frame, index)
        if not pointOK then return false, "layout-point-invalid" end
        if relativeTo == holder then
            needsRepair = true
            break
        end
        if relativeTo and type(relativeTo.GetName) == "function" then
            local nameOK, name = pcall(relativeTo.GetName, relativeTo)
            if nameOK and name == HOLDER_NAME then
                needsRepair = true
                break
            end
        end
    end
    if not needsRepair then return true, false end

    local width, height = ReadFrameSize(frame)
    if not width or not height then return false, "layout-size-unavailable" end
    local clampedOK, clampedToScreen = pcall(frame.IsClampedToScreen, frame)
    local insetsOK, clampLeft, clampRight, clampTop, clampBottom =
        pcall(frame.GetClampRectInsets, frame)
    if not clampedOK
        or type(clampedToScreen) ~= "boolean"
        or not insetsOK
        or not IsFinite(clampLeft)
        or not IsFinite(clampRight)
        or not IsFinite(clampTop)
        or not IsFinite(clampBottom)
    then
        return false, "layout-clamp-state-capture-failed"
    end
    local clampDisabled, clampReason = DisableFrameScreenClamp(frame)
    if not clampDisabled then return false, clampReason end
    local repaired, repairReason = Adapter:ApplyMainLayoutRect(
        frame,
        holder,
        width,
        height
    )
    if not repaired then return false, repairReason end
    MainLayout.legacyAnchorRepairCount = (MainLayout.legacyAnchorRepairCount or 0) + 1
    return true, true, {
        clampedToScreen = clampedToScreen,
        clampInsets = { clampLeft, clampRight, clampTop, clampBottom },
    }
end

local function ApplyFrameRectFromHolder(frame, holder, width, height)
    return Adapter:ApplyMainLayoutRect(frame, holder, width, height)
end

DisableFrameScreenClamp = function(frame)
    if type(frame.SetClampedToScreen) ~= "function"
        or type(frame.IsClampedToScreen) ~= "function"
        or type(frame.SetClampRectInsets) ~= "function"
        or type(frame.GetClampRectInsets) ~= "function"
    then
        return false, "layout-clamp-api-missing"
    end

    local ok = pcall(frame.SetClampedToScreen, frame, false)
    if ok then
        ok = pcall(frame.SetClampRectInsets, frame, 0, 0, 0, 0)
    end
    if not ok then return false, "layout-native-clamp-disable-failed" end

    local clampedOK, clamped = pcall(frame.IsClampedToScreen, frame)
    local insetsOK, left, right, top, bottom = pcall(frame.GetClampRectInsets, frame)
    if not clampedOK
        or clamped ~= false
        or not insetsOK
        or left ~= 0
        or right ~= 0
        or top ~= 0
        or bottom ~= 0
    then
        return false, "layout-native-clamp-readback-mismatch"
    end
    return true
end

local function ClaimNativeEditModeSystem(frame)
    local layout = YUI.Layout
    if layout and type(layout.SetNativeEditModeClaim) == "function" then
        local ok = layout:SetNativeEditModeClaim(MainLayout, frame, true)
        MainLayout.nativeEditModeClaimed = ok == true
    end
    return true
end

local function LayoutMutationAllowed()
    local state = Adapter:GetRestrictionState()
    return state == "OPEN" or state == "PAUSED"
end

local function ApplyAuthoritativeLayout(frame)
    local holder = MainLayout.holder
    local db = YChat:GetLayout()
    if not holder or type(db) ~= "table" then
        return false, "layout-state-unavailable"
    end
    local width = db.mainWidth
    local height = db.mainHeight
    if not IsFinite(width) or not IsFinite(height) then
        return false, "layout-size-unavailable"
    end
    if not LayoutMutationAllowed() then
        MainLayout.pending = true
        return false, "layout-restriction-not-open"
    end
    if Adapter:CanCallProtected(frame) ~= true then
        MainLayout.pending = true
        return false, "layout-main-frame-protected"
    end

    MainLayout.applying = true
    local ok = pcall(holder.SetSize, holder, width, height)
    local applyReason
    if ok then
        ok, applyReason = DisableFrameScreenClamp(frame)
    end
    if ok then
        ok, applyReason = ApplyFrameRectFromHolder(frame, holder, width, height)
    end
    if ok and type(frame.SetMovable) == "function" then
        ok = pcall(frame.SetMovable, frame, false)
    end
    if ok and type(frame.SetUserPlaced) == "function" then
        ok = pcall(frame.SetUserPlaced, frame, false)
    end
    if ok then
        local boundsOK, boundsReason = RefreshMoverBounds(frame)
        ok = boundsOK == true
        if not ok then applyReason = boundsReason end
    end
    if ok and MainLayout.layoutRegistered
        and YUI.Layout
        and type(YUI.Layout.RefreshFrame) == "function"
    then
        local refreshOK, refreshed = pcall(YUI.Layout.RefreshFrame, YUI.Layout, LAYOUT_ID)
        ok = refreshOK and refreshed == true
        if not ok then applyReason = "layout-holder-refresh-failed" end
    end
    if ok then
        ok, applyReason = DisableFrameScreenClamp(frame)
    end
    if ok then
        ok, applyReason = ApplyFrameRectFromHolder(frame, holder, width, height)
    end
    if ok then ClaimNativeEditModeSystem(frame) end
    MainLayout.applying = false
    if not ok then
        MainLayout.pending = true
        return false, applyReason or "layout-apply-failed"
    end
    MainLayout.pending = false
    return true
end

local function PrepareLayout(frame)
    if MainLayout.snapshot
        and MainLayout.holderInitialized
        and MainLayout.hooksInstalled
    then
        return true
    end
    local holder, holderReason = EnsureHolder(frame)
    if not holder then return false, holderReason end
    local repaired, repairReason, repairedClampState = RepairLegacyFrameAnchor(frame, holder)
    if not repaired then return false, repairReason end

    if not MainLayout.snapshot then
        local snapshot, snapshotReason = CaptureSnapshot(frame)
        if not snapshot then return false, snapshotReason end
        if repairedClampState then
            snapshot.clampedToScreen = repairedClampState.clampedToScreen
            snapshot.clampInsets = repairedClampState.clampInsets
        end
        MainLayout.snapshot = snapshot
        local db = YChat:GetLayout()
        if db.mainWidth == nil then db.mainWidth = floor(snapshot.width + 0.5) end
        if db.mainHeight == nil then db.mainHeight = floor(snapshot.height + 0.5) end
    end
    return InstallHooks(frame)
end

local function DeferredLayoutSync()
    MainLayout.syncScheduled = false
    MainLayout.syncTimer = nil
    if not MainLayout.enabled or MainLayout.applying then return end
    if not LayoutMutationAllowed() then
        MainLayout.pending = true
        MainLayout.lastReason = "layout-restriction-not-open"
        return
    end
    local frame, frameReason = SafeFrame()
    if not frame then
        MainLayout.pending = true
        MainLayout.lastReason = frameReason or "layout-main-frame-unavailable"
        return
    end
    local prepared, prepareReason = PrepareLayout(frame)
    if not prepared then
        MainLayout.pending = true
        MainLayout.lastReason = prepareReason or "layout-prepare-failed"
        return
    end
    local applied, applyReason = ApplyAuthoritativeLayout(frame)
    MainLayout.lastReason = applyReason or "layout-deferred-sync"
    if not applied then MainLayout.pending = true end
end

local function ScheduleLayoutSync(frame)
    if not MainLayout.enabled
        or MainLayout.applying
        or frame ~= _G.ChatFrame1
    then
        return true
    end
    MainLayout.pending = true
    if not LayoutMutationAllowed() or MainLayout.syncScheduled then return true end
    local timer, timerReason = Adapter:CreateOneShotTimer(0, DeferredLayoutSync)
    if not timer then return false, timerReason end
    MainLayout.syncScheduled = true
    MainLayout.syncTimer = timer
    return true
end

local function ScheduleClaimedLayoutSync(frame)
    local scheduled, reason = ScheduleLayoutSync(frame)
    if scheduled then ClaimNativeEditModeSystem(frame) end
    return scheduled, reason
end

local function NativeLayoutMutated(frame)
    ScheduleLayoutSync(frame)
end

InstallHooks = function(frame)
    if MainLayout.hooksInstalled then return true end
    local ok = Adapter:InstallMainLayoutHooks(
        frame,
        MainLayout.holder,
        NativeLayoutMutated
    )
    if not ok then return false, "layout-hook-install-failed" end
    MainLayout.hooksInstalled = true
    return true
end

local function RestoreSnapshot(frame)
    local snapshot = MainLayout.snapshot
    if not snapshot then return true end
    if Adapter:CanCallProtected(frame) ~= true then
        MainLayout.pending = true
        return false, "layout-restore-protected"
    end
    MainLayout.applying = true
    local ok = pcall(frame.ClearAllPoints, frame)
    for index = 1, #snapshot.points do
        local point = snapshot.points[index]
        if ok then
            ok = pcall(
                frame.SetPoint,
                frame,
                point[1],
                point[2],
                point[3],
                point[4],
                point[5]
            )
        end
    end
    if ok then ok = pcall(frame.SetSize, frame, snapshot.width, snapshot.height) end
    if ok and snapshot.movable ~= nil and type(frame.SetMovable) == "function" then
        ok = pcall(frame.SetMovable, frame, snapshot.movable)
    end
    if ok and snapshot.userPlaced ~= nil and type(frame.SetUserPlaced) == "function" then
        ok = pcall(frame.SetUserPlaced, frame, snapshot.userPlaced)
    end
    local insets = snapshot.clampInsets
    if ok and insets then
        ok = pcall(
            frame.SetClampRectInsets,
            frame,
            insets[1],
            insets[2],
            insets[3],
            insets[4]
        )
    end
    if ok and snapshot.clampedToScreen ~= nil then
        ok = pcall(frame.SetClampedToScreen, frame, snapshot.clampedToScreen)
    end
    MainLayout.applying = false
    MainLayout.pending = not ok
    if ok then MainLayout.snapshot = nil end
    return ok, ok and nil or "layout-restore-failed"
end

local function ReleaseNativeEditModeSystem()
    local layout = YUI.Layout
    MainLayout.nativeEditModeClaimed = false
    if layout and type(layout.ReleaseNativeEditModeOwner) == "function" then
        return layout:ReleaseNativeEditModeOwner(MainLayout)
    end
    return true
end

function MainLayout:SetEnabled(enabled, reason)
    enabled = enabled == true
    if enabled and not LayoutMutationAllowed() then
        self.enabled = true
        self.pending = true
        self.lastReason = reason or "layout-restriction-not-open"
        return true
    end
    if not enabled and not LayoutMutationAllowed() then
        self.enabled = false
        self.pending = true
        if self.syncTimer then Adapter:CancelOneShotTimer(self.syncTimer) end
        self.syncTimer = nil
        self.syncScheduled = false
        ReleaseNativeEditModeSystem()
        self.lastReason = reason or "layout-restore-restriction-not-open"
        return false, "layout-restore-restriction-not-open"
    end
    local frame, frameReason = SafeFrame()
    if not frame then
        self.lastReason = frameReason
        return false, frameReason
    end
    if not enabled then
        self.enabled = false
        if self.syncTimer then Adapter:CancelOneShotTimer(self.syncTimer) end
        self.syncTimer = nil
        self.syncScheduled = false
        local restored, restoreReason = RestoreSnapshot(frame)
        local selectionRestored, selectionReason = ReleaseNativeEditModeSystem()
        if self.holder then self.holder:Hide() end
        if self.layoutRegistered
            and YUI.Layout
            and type(YUI.Layout.RefreshFrame) == "function"
        then
            YUI.Layout:RefreshFrame(LAYOUT_ID)
        end
        local ok = restored and selectionRestored
        local finalReason = restoreReason or selectionReason
        self.lastReason = finalReason or reason or "layout-disabled"
        return ok, finalReason
    end

    self.enabled = true
    local scheduled, scheduleReason = ScheduleClaimedLayoutSync(frame)
    self.lastReason = scheduleReason or reason or "layout-enabled"
    return scheduled, scheduleReason
end

function MainLayout:OnWindowsChanged()
    if not self.enabled then return true end
    local frame, reason = SafeFrame()
    if not frame then return false, reason end
    if not LayoutMutationAllowed() then
        self.pending = true
        return true, "layout-restriction-not-open"
    end
    return ScheduleClaimedLayoutSync(frame)
end

function MainLayout:OnRestrictionStateChanged(state)
    if state ~= "OPEN" and state ~= "PAUSED" then
        if not self.enabled and not self.pending then return true end
        self.pending = true
        if self.syncTimer then Adapter:CancelOneShotTimer(self.syncTimer) end
        self.syncTimer = nil
        self.syncScheduled = false
        return true
    end
    local frame, reason = SafeFrame()
    if not frame then return false, reason end
    if not self.enabled then
        local restored, restoreReason = RestoreSnapshot(frame)
        local selectionRestored, selectionReason = ReleaseNativeEditModeSystem()
        return restored and selectionRestored, restoreReason or selectionReason
    end
    return ScheduleClaimedLayoutSync(frame)
end

function MainLayout:OnPlayerRegenEnabled()
    if not self.pending then return true end
    if self.enabled then return self:OnWindowsChanged() end
    local frame, reason = SafeFrame()
    if not frame then return false, reason end
    local restored, restoreReason = RestoreSnapshot(frame)
    local selectionRestored, selectionReason = ReleaseNativeEditModeSystem()
    return restored and selectionRestored, restoreReason or selectionReason
end

function MainLayout:RestoreAll(reason)
    return self:SetEnabled(false, reason or "layout-restored")
end

function MainLayout:GetRuntimeGauges(target)
    target = target or {}
    target.layoutPending = self.pending and 1 or 0
    target.layoutRegistered = self.layoutRegistered and 1 or 0
    target.layoutPlacementRepairs = self.placementRepairCount or 0
    target.activeTimers = (target.activeTimers or 0)
        + (self.syncScheduled and 1 or 0)
    return target
end

-- Read native geometry only; never enable chat ownership to resolve an anchor.
if YUI.Layout and YUI.Layout.RegisterAnchorProvider then
    YUI.Layout:RegisterAnchorProvider(LAYOUT_ID, {
        name = HOLDER_NAME,
        strictAnchorTargets = true,
        anchorTargets = { "UIParent" },
        resolve = function()
            local frame = SafeFrame()
            if not frame then return nil end
            local width, height = ReadFrameSize(frame)
            local placement = CapturePlacement(frame)
            if not width or not IsPlacementSane(placement) then return nil end
            return placement, width, height, 1
        end,
    })
end

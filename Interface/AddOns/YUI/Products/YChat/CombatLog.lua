local YUI = _G.YUI
local YChat = YUI and YUI.YChat
if not YChat or (YUI.IsForever or YUI.IsRetail) ~= true then return end

local Adapter = YChat.Adapter
if not Adapter then return end
local GUI2 = YUI.GUI2 or YUI.GUI
local huge = math.huge
local UIFrameFadeRemoveFrame = _G.UIFrameFadeRemoveFrame
local FADE_HIDDEN_EPSILON = 0.001

local CombatLog = {}
YChat.CombatLog = CombatLog

local pcall = pcall
local type = type

CombatLog.enabled = false
CombatLog.state = nil
CombatLog.applying = false
CombatLog.lastReason = "not-started"
CombatLog.dockHookInstalled = false
CombatLog.fadeRepairCount = 0
CombatLog.fadeRepairFailures = 0
local dockMutationObserved = false

local function Call(object, method, ...)
    local callback = object and object[method]
    if type(callback) ~= "function" then return false end
    return pcall(callback, object, ...)
end

local function IsFiniteNumber(value)
    return type(value) == "number" and value > -huge and value < huge
end

local function GetPixelSize(region, desiredPixels, minimumPixels)
    if GUI2 and type(GUI2.GetPixelSize) == "function" then
        local ok, size = pcall(
            GUI2.GetPixelSize,
            GUI2,
            region,
            desiredPixels,
            minimumPixels
        )
        if ok and IsFiniteNumber(size) and size > 0 then return size end
    end
    return desiredPixels
end

local function CapturePoints(object)
    if Adapter:CanCallProtected(object) ~= true
        or type(object.GetNumPoints) ~= "function"
        or type(object.GetPoint) ~= "function"
    then
        return nil, "combat-log-point-api-missing"
    end
    local countOK, count = pcall(object.GetNumPoints, object)
    if not countOK or type(count) ~= "number" or count < 1 then
        return nil, "combat-log-point-count-invalid"
    end
    local points = {}
    for index = 1, count do
        local ok, point, relativeTo, relativePoint, x, y =
            pcall(object.GetPoint, object, index)
        if not ok
            or type(point) ~= "string"
            or (relativePoint ~= nil and type(relativePoint) ~= "string")
            or not IsFiniteNumber(x or 0)
            or not IsFiniteNumber(y or 0)
        then
            return nil, "combat-log-point-capture-failed"
        end
        points[index] = { point, relativeTo, relativePoint, x or 0, y or 0 }
    end
    return points
end

local function RestorePoints(object, points)
    if type(points) ~= "table"
        or Adapter:CanCallProtected(object) ~= true
        or not Call(object, "ClearAllPoints")
    then
        return false
    end
    for index = 1, #points do
        local point = points[index]
        if not Call(
            object,
            "SetPoint",
            point[1],
            point[2],
            point[3],
            point[4],
            point[5]
        ) then
            return false
        end
    end
    return true
end

local function CaptureRegionAlpha(regions)
    local result = {}
    for index = 1, #regions do
        local region = regions[index]
        if Adapter:CanCallProtected(region) ~= true then
            return nil, "combat-log-region-protected"
        end
        local ok, alpha = pcall(region.GetAlpha, region)
        if not ok or type(alpha) ~= "number" then
            return nil, "combat-log-region-capture-failed"
        end
        result[index] = { region = region, alpha = alpha }
    end
    return result
end

local function CaptureObject(object)
    if Adapter:CanCallProtected(object) ~= true then
        return nil, "combat-log-object-protected"
    end
    local shownOK, shown = pcall(object.IsShown, object)
    local alphaOK, alpha = pcall(object.GetAlpha, object)
    local mouse
    local mouseOK = true
    if type(object.IsMouseEnabled) == "function" then
        mouseOK, mouse = pcall(object.IsMouseEnabled, object)
    end
    if not shownOK
        or not alphaOK
        or not mouseOK
        or type(shown) ~= "boolean"
        or type(alpha) ~= "number"
        or (mouse ~= nil and type(mouse) ~= "boolean")
    then
        return nil, "combat-log-object-capture-failed"
    end
    return { object = object, shown = shown, alpha = alpha, mouse = mouse }
end

local function RefreshObjectSnapshot(entry)
    local object = entry and entry.object
    if not object or Adapter:CanCallProtected(object) ~= true then return false end
    local shownOK, shown = pcall(object.IsShown, object)
    local alphaOK, alpha = pcall(object.GetAlpha, object)
    local mouseOK, mouse = true, entry.mouse
    if type(object.IsMouseEnabled) == "function" then
        mouseOK, mouse = pcall(object.IsMouseEnabled, object)
    end
    if not shownOK
        or not alphaOK
        or not mouseOK
        or type(shown) ~= "boolean"
        or type(alpha) ~= "number"
        or (mouse ~= nil and type(mouse) ~= "boolean")
    then
        return false
    end
    entry.shown = shown
    entry.alpha = alpha
    entry.mouse = mouse
    return true
end

local function RestoreObject(entry)
    local object = entry and entry.object
    if not object or Adapter:CanCallProtected(object) ~= true then return false end
    if entry.mouse ~= nil and not Call(object, "EnableMouse", entry.mouse) then
        return false
    end
    return Call(object, "SetAlpha", entry.alpha)
        and Call(object, entry.shown and "Show" or "Hide")
end

local function SetRegionAlpha(snapshot, alpha, cancelNativeFade)
    for index = 1, #snapshot do
        local entry = snapshot[index]
        local allowed = Adapter:CanCallProtected(entry.region) == true
        local fadeRemoved = not cancelNativeFade
            or (type(UIFrameFadeRemoveFrame) == "function"
                and pcall(UIFrameFadeRemoveFrame, entry.region))
        local alphaSet = allowed
            and Call(entry.region, "SetAlpha", alpha == nil and entry.alpha or alpha)
        if not fadeRemoved or not alphaSet then
            return false
        end
    end
    return true
end

local function CreateFlat(parent, layer, subLevel)
    if Adapter:CanCallProtected(parent) ~= true then return nil end
    local ok, texture = pcall(parent.CreateTexture, parent, nil, layer, nil, subLevel)
    if not ok or not texture then return nil end
    texture:SetColorTexture(1, 1, 1, 1)
    if type(texture.SetSnapToPixelGrid) == "function" then
        pcall(texture.SetSnapToPixelGrid, texture, false)
    end
    if type(texture.SetTexelSnappingBias) == "function" then
        pcall(texture.SetTexelSnappingBias, texture, 0)
    end
    texture:Hide()
    return texture
end

local function AllocateBox(parent, anchor)
    local background = CreateFlat(parent, "BACKGROUND", -7)
    local top = CreateFlat(parent, "BORDER", 6)
    local bottom = CreateFlat(parent, "BORDER", 6)
    local left = CreateFlat(parent, "BORDER", 6)
    local right = CreateFlat(parent, "BORDER", 6)
    if not background or not top or not bottom or not left or not right then
        return nil
    end
    background:SetAllPoints(anchor)
    top:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
    top:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)
    left:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, 0)
    left:SetWidth(1)
    right:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(1)
    return {
        background = background,
        anchor = anchor,
        border = { top, bottom, left, right },
    }
end

local function HideBox(box)
    if not box then return true end
    box.background:Hide()
    for index = 1, #box.border do box.border[index]:Hide() end
    return true
end

local function ApplyBox(box, appearance)
    local color = appearance.borderColor
    local appearanceModule = YChat.Appearance
    if appearanceModule and type(appearanceModule.ResolveBorderColor) == "function" then
        local r, g, b, a = appearanceModule:ResolveBorderColor(appearance)
        if r ~= nil then color = { r, g, b, a } end
    end
    local backgroundColor = appearance.backgroundColor
    box.background:SetColorTexture(
        backgroundColor[1],
        backgroundColor[2],
        backgroundColor[3],
        backgroundColor[4]
    )
    box.background:SetAlpha(appearance.backgroundAlpha)
    if appearance.backgroundAlpha > 0 then box.background:Show() else box.background:Hide() end
    local shown = appearance.borderStyle ~= "none"
    local thickness = GetPixelSize(box.anchor, appearance.borderWidth or 1, 1)
    for index = 1, #box.border do
        local line = box.border[index]
        line:SetColorTexture(color[1], color[2], color[3], color[4])
        if index <= 2 then line:SetHeight(thickness) else line:SetWidth(thickness) end
        if shown then line:Show() else line:Hide() end
    end
    return true
end

local function ApplyQuickBarDivider(box, appearance)
    local color = appearance.borderColor
    local appearanceModule = YChat.Appearance
    if appearanceModule and type(appearanceModule.ResolveBorderColor) == "function" then
        local r, g, b, a = appearanceModule:ResolveBorderColor(appearance)
        if r ~= nil then color = { r, g, b, a } end
    end
    local thickness = GetPixelSize(box.anchor, appearance.borderWidth or 1, 1)
    box.background:Hide()
    box.border[1]:Hide()
    box.border[3]:Hide()
    box.border[4]:Hide()
    local divider = box.border[2]
    divider:SetHeight(thickness)
    divider:SetColorTexture(color[1], color[2], color[3], color[4])
    if appearance.borderStyle ~= "none" then divider:Show() else divider:Hide() end
    return true
end

local function AlignQuickBar(state)
    local quickBar = state.targets.quickBar
    local background = state.targets.background
    if Adapter:CanCallProtected(quickBar) ~= true then return false end
    local heightOK, height = pcall(quickBar.GetHeight, quickBar)
    if not heightOK or not IsFiniteNumber(height) or height <= 0 then return false end
    if not Call(quickBar, "ClearAllPoints")
        or not Call(
            quickBar,
            "SetPoint",
            "BOTTOMLEFT",
            background,
            "TOPLEFT",
            0,
            -height
        )
        or not Call(
            quickBar,
            "SetPoint",
            "BOTTOMRIGHT",
            background,
            "TOPRIGHT",
            0,
            -height
        )
    then
        RestorePoints(quickBar, state.quickPoints)
        return false
    end
    state.quickAligned = true
    return true
end

local function RestoreQuickBarLayout(state)
    if not state.quickAligned then return true end
    local restored = RestorePoints(state.targets.quickBar, state.quickPoints)
    if restored then state.quickAligned = false end
    return restored
end

local function EnsureState()
    if CombatLog.state then return CombatLog.state end
    local targets, targetReason = Adapter:GetCombatLogTargets()
    if not targets then return nil, targetReason end
    local frameRegions, frameReason = CaptureRegionAlpha(targets.frameRegions)
    if not frameRegions then return nil, frameReason end
    local quickRegions, quickReason = CaptureRegionAlpha(targets.quickRegions)
    if not quickRegions then return nil, quickReason end
    local frameObject, objectReason = CaptureObject(targets.frame)
    if not frameObject then return nil, objectReason end
    local tabObject, tabReason = CaptureObject(targets.tab)
    if not tabObject then return nil, tabReason end
    local quickObject, quickObjectReason = CaptureObject(targets.quickBar)
    if not quickObject then return nil, quickObjectReason end
    local scrollObject, scrollObjectReason = CaptureObject(targets.scrollBar)
    if not scrollObject then return nil, scrollObjectReason end
    local buttonFrameObject, buttonFrameReason = CaptureObject(targets.buttonFrame)
    if not buttonFrameObject then return nil, buttonFrameReason end
    local resizeObject, resizeReason = CaptureObject(targets.resizeButton)
    if not resizeObject then return nil, resizeReason end
    local scrollToBottomObject, scrollToBottomReason = CaptureObject(targets.scrollToBottomButton)
    if not scrollToBottomObject then return nil, scrollToBottomReason end
    local quickPoints, quickPointReason = CapturePoints(targets.quickBar)
    if not quickPoints then return nil, quickPointReason end
    local dockPoints, dockPointReason = CapturePoints(targets.dockScrollFrame)
    if not dockPoints then return nil, dockPointReason end
    local frameBox = AllocateBox(targets.frame, targets.background)
    local quickBox = AllocateBox(targets.quickBar, targets.quickBar)
    if not frameBox or not quickBox then
        HideBox(frameBox)
        HideBox(quickBox)
        return nil, "combat-log-art-allocation-failed"
    end
    local state = {
        targets = targets,
        frameRegions = frameRegions,
        quickRegions = quickRegions,
        frameObject = frameObject,
        tabObject = tabObject,
        quickObject = quickObject,
        scrollObject = scrollObject,
        buttonFrameObject = buttonFrameObject,
        resizeObject = resizeObject,
        scrollToBottomObject = scrollToBottomObject,
        quickPoints = quickPoints,
        dockPoints = dockPoints,
        quickAligned = false,
        dockSlotCollapsed = false,
        frameBox = frameBox,
        quickBox = quickBox,
        applied = false,
        hidden = false,
        nativeControlsSuppressed = false,
        restorePending = false,
    }
    CombatLog.state = state
    return state
end

local function SuppressShown(object)
    return Call(object, "EnableMouse", false)
        and Call(object, "SetAlpha", 0)
        and Call(object, "Hide")
end

local function CollapseDockSlot(state)
    local appearance = YChat:GetAppearance()
    local spacing = type(appearance) == "table" and appearance.tabSpacing or 0
    local collapsed = Adapter:CollapseCombatLogDockSlot(state.targets, spacing)
    if not collapsed then
        RestorePoints(state.targets.dockScrollFrame, state.dockPoints)
        state.dockSlotCollapsed = false
        return false
    end
    state.dockSlotCollapsed = true
    return true
end

local function RestoreDockSlot(state)
    if not state.dockSlotCollapsed then return true end
    local restored = Adapter:RestoreCombatLogDockSlot(state.targets)
    if not restored then
        restored = RestorePoints(state.targets.dockScrollFrame, state.dockPoints)
    end
    state.dockSlotCollapsed = not restored
    return restored
end

local function RestoreHidden(state)
    if not state.hidden and not state.dockSlotCollapsed then return true end
    local wasApplying = CombatLog.applying
    CombatLog.applying = true
    local ok = RestoreDockSlot(state)
    ok = RestoreObject(state.frameObject) and ok
    ok = RestoreObject(state.tabObject) and ok
    ok = RestoreObject(state.quickObject) and ok
    CombatLog.applying = wasApplying
    state.hidden = not ok
    return ok
end

local function CancelNativeFade(object)
    return type(UIFrameFadeRemoveFrame) == "function"
        and pcall(UIFrameFadeRemoveFrame, object)
end

local function SuppressNativeControl(object, cancelNativeFade)
    local fadeRemoved = not cancelNativeFade or CancelNativeFade(object)
    local suppressed = SuppressShown(object)
    return fadeRemoved and suppressed
end

local function SuppressNativeControls(state, cancelNativeFade)
    state.nativeControlsSuppressed = true
    local ok = SuppressNativeControl(state.targets.scrollBar, cancelNativeFade)
    ok = SuppressNativeControl(state.targets.buttonFrame, cancelNativeFade) and ok
    ok = SuppressNativeControl(state.targets.resizeButton, cancelNativeFade) and ok
    ok = SuppressNativeControl(state.targets.scrollToBottomButton, cancelNativeFade) and ok
    return ok
end

local function RestoreNativeControls(state)
    if not state.nativeControlsSuppressed then return true end
    local restored = RestoreObject(state.scrollObject)
    restored = RestoreObject(state.buttonFrameObject) and restored
    restored = RestoreObject(state.resizeObject) and restored
    restored = RestoreObject(state.scrollToBottomObject) and restored
    state.nativeControlsSuppressed = not restored
    return restored
end

local function HideCombatLog(state)
    local frame = state.targets.frame
    local selected = Adapter:IsAppearanceTabSelected(frame)
    if selected == true
        and type(_G.FCF_SelectDockFrame) == "function"
        and _G.ChatFrame1
    then
        pcall(_G.FCF_SelectDockFrame, _G.ChatFrame1)
    elseif selected == nil then
        return false, "combat-log-selection-unknown"
    end
    CombatLog.applying = true
    state.hidden = true
    local ok = SuppressShown(state.targets.quickBar)
        and SuppressShown(state.targets.tab)
        and SuppressShown(frame)
        and SuppressNativeControls(state, true)
        and CollapseDockSlot(state)
    if not ok then
        local restored = RestoreDockSlot(state)
        restored = RestoreObject(state.frameObject) and restored
        restored = RestoreObject(state.tabObject) and restored
        restored = RestoreObject(state.quickObject) and restored
        restored = RestoreNativeControls(state) and restored
        state.hidden = not restored
    end
    CombatLog.applying = false
    state.applied = ok
    state.restorePending = not ok
    return ok, ok and nil or "combat-log-hide-failed"
end

local function RollbackStyle(state)
    CombatLog.applying = true
    local ok = HideBox(state.frameBox)
    ok = HideBox(state.quickBox) and ok
    ok = SetRegionAlpha(state.frameRegions, nil) and ok
    ok = SetRegionAlpha(state.quickRegions, nil) and ok
    ok = RestoreQuickBarLayout(state) and ok
    ok = RestoreNativeControls(state) and ok
    ok = RestoreHidden(state) and ok
    CombatLog.applying = false
    state.applied = false
    state.restorePending = not ok
    return ok
end

local function ApplyState(state)
    local restriction = Adapter:GetRestrictionState()
    if restriction ~= "OPEN" and restriction ~= "PAUSED" then
        return false, "restriction-not-open"
    end
    local appearance = YChat:GetAppearance()
    if type(appearance) ~= "table" then
        return false, "combat-log-appearance-unavailable"
    end
    if appearance.hideCombatLog == true then return HideCombatLog(state) end
    if not RestoreHidden(state) then return false, "combat-log-visibility-restore-failed" end
    if not AlignQuickBar(state) then
        RollbackStyle(state)
        return false, "combat-log-layout-apply-failed"
    end
    CombatLog.applying = true
    local ok = SuppressNativeControls(state, true)
    CombatLog.applying = false
    ok = ok and SetRegionAlpha(state.frameRegions, 0, true)
        and SetRegionAlpha(state.quickRegions, 0, true)
        and ApplyBox(state.frameBox, appearance)
        and ApplyQuickBarDivider(state.quickBox, appearance)
    if not ok then
        RollbackStyle(state)
        return false, "combat-log-style-apply-failed"
    end
    state.applied = ok
    state.restorePending = false
    return true
end

local function ReadCurrentFadeVisibility(state)
    local elementFade = YChat.ElementFade
    if not elementFade or type(elementFade.GetFrameVisibility) ~= "function" then
        return nil
    end
    local ok, visibility = pcall(
        elementFade.GetFrameVisibility,
        elementFade,
        state.targets.frame
    )
    if not ok or not IsFiniteNumber(visibility) then return nil end
    if visibility < 0 then return 0 end
    if visibility > 1 then return 1 end
    return visibility
end

local function SetAlphaZero(object, cancelNativeFade)
    if not object or Adapter:CanCallProtected(object) ~= true then return false end
    local ok, alpha = pcall(object.GetAlpha, object)
    if ok and IsFiniteNumber(alpha) and alpha <= FADE_HIDDEN_EPSILON then
        return true
    end
    if cancelNativeFade and not CancelNativeFade(object) then return false end
    return Call(object, "SetAlpha", 0)
end

local function RepairFullyFadedVisuals(state)
    if not state
        or state.applied ~= true
        or state.restorePending == true
        or state.hidden == true
    then
        return false, true
    end
    local visibility = ReadCurrentFadeVisibility(state)
    if visibility == nil or visibility > FADE_HIDDEN_EPSILON then
        return false, true
    end

    local restriction = Adapter:GetRestrictionState()
    if restriction ~= "OPEN" and restriction ~= "PAUSED" then
        return true, false
    end

    local targets = state.targets
    local wasApplying = CombatLog.applying
    CombatLog.applying = true
    local ok = SetAlphaZero(targets.frame, false)
        and SetAlphaZero(targets.quickBar, true)
    CombatLog.applying = wasApplying

    if ok then
        CombatLog.fadeRepairCount = CombatLog.fadeRepairCount + 1
        CombatLog.lastReason = "combat-log-fully-faded-repaired"
    else
        CombatLog.fadeRepairFailures = CombatLog.fadeRepairFailures + 1
        CombatLog.lastReason = "combat-log-fully-faded-repair-failed"
    end
    return true, ok
end

local function NativeObjectShown(object)
    if not CombatLog.enabled or CombatLog.applying then return end
    local state = CombatLog.state
    local handled = state and RepairFullyFadedVisuals(state)
    if handled then return end
    if state then
        local hidden = state.hidden == true
        if object == state.targets.frame then
            if hidden then
                state.frameObject.shown = true
            else
                RefreshObjectSnapshot(state.frameObject)
            end
        elseif object == state.targets.tab then
            if hidden then
                state.tabObject.shown = true
            else
                RefreshObjectSnapshot(state.tabObject)
            end
        elseif object == state.targets.quickBar then
            if hidden then
                state.quickObject.shown = true
            else
                RefreshObjectSnapshot(state.quickObject)
            end
        elseif object == state.targets.scrollBar then
            if not state.nativeControlsSuppressed then
                RefreshObjectSnapshot(state.scrollObject)
            end
        elseif object == state.targets.buttonFrame then
            if not state.nativeControlsSuppressed then
                RefreshObjectSnapshot(state.buttonFrameObject)
            end
        elseif object == state.targets.resizeButton then
            if not state.nativeControlsSuppressed then
                RefreshObjectSnapshot(state.resizeObject)
            end
        elseif object == state.targets.scrollToBottomButton then
            if not state.nativeControlsSuppressed then
                RefreshObjectSnapshot(state.scrollToBottomObject)
            end
        end
    end
    CombatLog:Reconcile()
end

local function NativeVisualsChanged(frame)
    local restriction = Adapter:GetRestrictionState()
    if not CombatLog.enabled or CombatLog.applying then return end
    local state = CombatLog.state
    if state
        and (frame == state.targets.frame
            or frame == state.targets.quickBar)
    then
        local handled = RepairFullyFadedVisuals(state)
        if handled then return end
    end
    if not state
        or state.applied ~= true
        or frame ~= state.targets.frame
        or (restriction ~= "OPEN" and restriction ~= "PAUSED")
    then
        return
    end

    CombatLog.applying = true
    local ok = SetRegionAlpha(state.frameRegions, 0, true)
    ok = SetRegionAlpha(state.quickRegions, 0, true) and ok
    ok = SuppressNativeControls(state, true) and ok
    CombatLog.applying = false

    local elementFade = YChat.ElementFade
    if ok
        and elementFade
        and type(elementFade.GetFrameVisibility) == "function"
    then
        local visibility = elementFade:GetFrameVisibility(state.targets.frame)
        ok = CombatLog:ApplyElementFade(visibility, true) == true and ok
    end

    if not ok then
        state.restorePending = true
        CombatLog.lastReason = "combat-log-native-visual-suppress-failed"
    end
end

local function NativeDockTabColorsChanged(tab)
    local state = CombatLog.state
    if CombatLog.enabled
        and not CombatLog.applying
        and state
        and tab == state.targets.tab
    then
        dockMutationObserved = true
    end
end

local function NativeDockTabsChanged(dock, forceUpdate)
    if not CombatLog.enabled
        or CombatLog.applying
    then
        return
    end
    if forceUpdate ~= true and dockMutationObserved ~= true then return end
    dockMutationObserved = false
    local restriction = Adapter:GetRestrictionState()
    if dock ~= _G.GeneralDockManager
        or (restriction ~= "OPEN" and restriction ~= "PAUSED")
    then
        return
    end
    local state = CombatLog.state
    local appearance = YChat:GetAppearance()
    if not state
        or state.targets.dock ~= dock
        or type(appearance) ~= "table"
        or appearance.hideCombatLog ~= true
    then
        return
    end

    CombatLog.applying = true
    local ok = SuppressShown(state.targets.tab)
        and CollapseDockSlot(state)
    CombatLog.applying = false
    if not ok then
        state.restorePending = true
        CombatLog.lastReason = "combat-log-dock-slot-collapse-failed"
    end
end

local function EnsureHooks(state)
    if not CombatLog.hooksInstalled then
        local ok = Adapter:InstallCombatLogLifecycleHooks(
            state.targets,
            NativeObjectShown,
            NativeVisualsChanged
        )
        CombatLog.hooksInstalled = ok
        if not ok then return false, "combat-log-hook-install-failed" end
    end
    if not CombatLog.quickHookInstalled
        and type(Adapter.InstallCombatLogQuickButtonHook) == "function"
    then
        local installed = Adapter:InstallCombatLogQuickButtonHook(NativeObjectShown)
        CombatLog.quickHookInstalled = installed == true
    end
    local appearance = YChat:GetAppearance()
    if type(appearance) == "table"
        and appearance.hideCombatLog == true
        and not CombatLog.dockHookInstalled
    then
        local installed, installReason = Adapter:InstallCombatLogDockHooks(
            state.targets,
            NativeDockTabColorsChanged,
            NativeDockTabsChanged
        )
        if not installed then
            return false, installReason or "combat-log-dock-hook-install-failed"
        end
        CombatLog.dockHookInstalled = true
    end
    return true
end

function CombatLog:Reconcile()
    if not self.enabled then return true end
    local state, stateReason = EnsureState()
    if not state then
        self.lastReason = stateReason
        self.retryPending = true
        return false, stateReason
    end
    local hooksOK, hooksReason = EnsureHooks(state)
    if not hooksOK then
        self.retryPending = true
        return false, hooksReason
    end
    local applied, reason = ApplyState(state)
    self.lastReason = reason or "combat-log-applied"
    self.retryPending = applied ~= true
    if applied then
        local elementFade = YChat.ElementFade
        if elementFade and type(elementFade.OnWindowsChanged) == "function" then
            pcall(
                elementFade.OnWindowsChanged,
                elementFade,
                "combat-log-reconciled"
            )
        end
    end
    return applied, reason
end

function CombatLog:HasPendingVisualRetry()
    return self.enabled == true and self.retryPending == true
end

function CombatLog:SetEnabled(enabled, reason)
    self.enabled = enabled == true
    if not self.enabled then
        self.retryPending = false
        return self:RestoreAll(reason or "combat-log-disabled")
    end
    return self:Reconcile()
end

function CombatLog:RestoreAll(reason)
    self.enabled = false
    dockMutationObserved = false
    local state = self.state
    if not state then return true end
    CombatLog.applying = true
    local ok = HideBox(state.frameBox)
    ok = HideBox(state.quickBox) and ok
    ok = SetRegionAlpha(state.frameRegions, nil) and ok
    ok = SetRegionAlpha(state.quickRegions, nil) and ok
    ok = RestoreQuickBarLayout(state) and ok
    ok = RestoreNativeControls(state) and ok
    ok = RestoreDockSlot(state) and ok
    ok = RestoreObject(state.frameObject) and ok
    ok = RestoreObject(state.tabObject) and ok
    ok = RestoreObject(state.quickObject) and ok
    CombatLog.applying = false
    state.applied = false
    state.hidden = false
    state.restorePending = not ok
    self.lastReason = ok and (reason or "combat-log-restored")
        or "combat-log-restore-pending"
    return ok, ok and nil or self.lastReason
end

function CombatLog:OnWindowsChanged()
    return self:Reconcile()
end

function CombatLog:OnRestrictionOpen()
    return self:Reconcile()
end

local function SetElementFadeAlpha(object, alpha, cancelNativeFade)
    if not object or Adapter:CanCallProtected(object) ~= true then return false end
    if cancelNativeFade and type(UIFrameFadeRemoveFrame) == "function" then
        pcall(UIFrameFadeRemoveFrame, object)
    end
    return Call(object, "SetAlpha", alpha)
end

function CombatLog:ApplyElementFade(visibility, cancelNativeFade)
    local state = self.state
    if not self.enabled
        or not state
        or state.applied ~= true
        or state.restorePending == true
        or state.hidden == true
    then
        return true
    end
    visibility = tonumber(visibility) or 1
    if visibility < 0 then visibility = 0 end
    if visibility > 1 then visibility = 1 end

    local appearance = YChat:GetAppearance()
    if type(appearance) ~= "table" then
        return false, "combat-log-element-fade-appearance-unavailable"
    end

    local wasApplying = self.applying
    self.applying = true
    local quickBase = state.quickObject.alpha or 1
    if cancelNativeFade and visibility >= 0.999 then
        local quickOK, quickAlpha = pcall(
            state.targets.quickBar.GetAlpha,
            state.targets.quickBar
        )
        if quickOK and IsFiniteNumber(quickAlpha) and quickAlpha >= quickBase then
            quickBase = quickAlpha
        end
    end

    local ok = SetElementFadeAlpha(
        state.targets.frame,
        (state.frameObject.alpha or 1) * visibility,
        false
    ) and SetElementFadeAlpha(
        state.targets.quickBar,
        quickBase * visibility,
        cancelNativeFade
    )

    local frameBox = state.frameBox
    if frameBox then
        ok = SetElementFadeAlpha(
            frameBox.background,
            appearance.backgroundAlpha * visibility,
            false
        ) and ok
        for index = 1, #frameBox.border do
            ok = SetElementFadeAlpha(
                frameBox.border[index],
                visibility,
                false
            ) and ok
        end
    end
    local quickBox = state.quickBox
    if quickBox and quickBox.border[2] then
        ok = SetElementFadeAlpha(
            quickBox.border[2],
            visibility,
            false
        ) and ok
    end
    self.applying = wasApplying
    if not ok then
        self.lastReason = "combat-log-element-fade-failed"
        return false, self.lastReason
    end
    return true
end

function CombatLog:GetRuntimeGauges(target)
    target = target or {}
    local state = self.state
    target.combatLogManaged = state and state.applied and 1 or 0
    target.combatLogHidden = state and state.hidden and 1 or 0
    target.combatLogRestorePending = state and state.restorePending and 1 or 0
    target.combatLogFadeRepairs = self.fadeRepairCount or 0
    target.combatLogFadeRepairFailures = self.fadeRepairFailures or 0
    return target
end

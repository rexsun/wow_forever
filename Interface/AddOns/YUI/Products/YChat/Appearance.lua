local YUI = _G.YUI
local YChat = YUI and YUI.YChat
if not YChat or (YUI.IsForever or YUI.IsRetail) ~= true then return end

local Adapter = YChat.Adapter
if not Adapter then return end

local Appearance = {}
YChat.Appearance = Appearance

local UnitAPI = YUI.API and YUI.API.Unit
local GUI2 = YUI.GUI2 or YUI.GUI
local hooksecurefunc = _G.hooksecurefunc
local UIFrameFadeRemoveFrame = _G.UIFrameFadeRemoveFrame
local abs = math.abs
local floor = math.floor
local huge = math.huge
local pairs = pairs
local pcall = pcall
local type = type
local unpack = table.unpack or unpack

local TOP_INPUT_OFFSET = 36
local INPUT_ART_INSET_PIXELS = 3
local MAX_RESTORE_RETRY_ATTEMPTS = 3
local MAX_NATIVE_SETTLE_FRAMES = 2
local TAB_INACTIVE_ALPHA = 0.65
local DOMAIN_FRAME = "frame"
local DOMAIN_TAB = "tab"
local DOMAIN_BUTTONS = "buttons"
local DOMAIN_SCROLL = "scroll"
local DOMAIN_INPUT = "input"
local VALID_POINTS = {
    TOPLEFT = true,
    TOPRIGHT = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
    LEFT = true,
    RIGHT = true,
    TOP = true,
    BOTTOM = true,
    CENTER = true,
}
local NATIVE_BUTTON_MUTATION_METHODS = {
    "OnGroupStatusChanged",
    "Reinitialize",
    "SetToastDirection",
    "CheckShowToast",
    "ToastToFriendFinished",
    "UpdateQueueIcon",
    "ShowToast",
    "HideToast",
}
local EMPTY_BUTTONS = {}

local frameStates = setmetatable({}, { __mode = "k" })
local animationStates = setmetatable({}, { __mode = "k" })
local allocationFailures = setmetatable({}, { __mode = "k" })
local tabStates = setmetatable({}, { __mode = "k" })
local tabOnlyStates = setmetatable({}, { __mode = "k" })
local tabAlphaHooks = setmetatable({}, { __mode = "k" })
local tabTextOwners = setmetatable({}, { __mode = "k" })
local tabTextAlphaHooks = setmetatable({}, { __mode = "k" })
local tabPressHooks = setmetatable({}, { __mode = "k" })
local buttonOwners = setmetatable({}, { __mode = "k" })
local buttonHooks = setmetatable({}, { __mode = "k" })
local buttonDomains = setmetatable({}, { __mode = "k" })
local buttonMethodHooks = setmetatable({}, { __mode = "k" })
local overflowRowSnapshots = setmetatable({}, { __mode = "k" })
local overflowSkinState
local activeAnimations = 0
local allocatedTextures = 0
local allocatedAnimationGroups = 0
local capturedFrames = 0
local capturedAppearanceTabs = 0
local tabScanGeneration = 0
local forceFrameReconcile = false
local forceInputLayoutReconcile = false
local nativeDockWidthSyncActive = false
local nativeDockMutationObserved = false
local nativeHookStates = {}
local targetGeneration = 0
local domainFailureCount = 0
local targetRebindCount = 0
local SuppressNativeFrameVisuals
local UpdateNativeWindowAlpha
local UpdateNativeTabSnapshot
local HandleNativeMutationFailure
local RefreshAppearanceTabs
local ApplyAppearanceTab
local ApplyDiscoveredFrame
local SyncManagedTabVisuals
local RepairManagedTabColors
local ReconcileLateGlobalButtons
local CanSuppressNativeMutation
local SetManagedTabAlpha
local SetManagedTabTextAlpha
local SuppressFrameDomain
local SuppressButtonDomain
local SuppressScrollDomain
local UpdateManagedTabPressedVisual
local RefreshOverflowSkin
local RestoreOverflowSkin
local StyleOverflowList
local ReadAlpha
local GetManagedFrameVisibility

Appearance.enabled = false
Appearance.lastReason = "not-started"
Appearance.managedFrames = 0
Appearance.restorePending = 0
Appearance.frameRestorePending = 0
Appearance.tooltipAvailable = false
Appearance.tooltipReason = "tooltip-not-started"
Appearance.restoreRetryActive = false
Appearance.restoreRetryAttempts = 0
Appearance.mutationPaused = false
Appearance.mutationRefreshPending = false

local function IsFiniteNumber(value)
    return type(value) == "number" and value > -huge and value < huge
end

local function IsSafeValue(value)
    return Adapter:IsExplicitlySafeValue(value) == true
end

local function NearlyEqual(left, right)
    return IsFiniteNumber(left)
        and IsFiniteNumber(right)
        and abs(left - right) <= 0.0001
end

local function IsVisualMutationAllowed()
    local state = Adapter:GetRestrictionState()
    return state == "OPEN" or state == "PAUSED"
end

local function IsActiveManagedState(state)
    return Appearance.enabled == true
        and state ~= nil
        and state.inactive ~= true
        and state.applied == true
        and state.restorePending ~= true
        and Appearance.mutationPaused ~= true
        and IsVisualMutationAllowed()
end

local function GetActiveManagedState(frame, includeTabOnly)
    local state = frameStates[frame]
    if not state and includeTabOnly == true then state = tabOnlyStates[frame] end
    if IsActiveManagedState(state) then return state end
    return nil
end

local function CallMethod(object, methodName, ...)
    local callback = object and object[methodName]
    if type(callback) ~= "function" then return false end
    return pcall(callback, object, ...)
end

local function NativeButtonShown(button)
    local state = buttonOwners[button]
    local domain = buttonDomains[button] or DOMAIN_BUTTONS
    if not state
        or state.hideNativeButtons ~= true
        or not Appearance.enabled
        or state.applied ~= true
        or state.restorePending == true
        or not IsVisualMutationAllowed()
        or Appearance.mutationPaused == true
    then
        return
    end
    if Adapter:CanCallProtected(button) ~= true then
        HandleNativeMutationFailure(
            state,
            "appearance-native-" .. domain .. "-protected",
            domain,
            false
        )
        return
    end
    if not CallMethod(button, "EnableMouse", false)
        or not CallMethod(button, "SetAlpha", 0)
        or not CallMethod(button, "Hide")
    then
        HandleNativeMutationFailure(
            state,
            "appearance-native-" .. domain .. "-show-suppress-failed",
            domain,
            false
        )
    end
end

local function NativeFrameVisualsChanged(frame)
    local state = GetActiveManagedState(frame)
    if not state then return end
    local desiredAlpha = state.selected == true and 1 or TAB_INACTIVE_ALPHA
    if not SetManagedTabAlpha
        or not SetManagedTabAlpha(state, desiredAlpha, true)
    then
        HandleNativeMutationFailure(
            state,
            "appearance-native-tab-fade-cancel-failed",
            DOMAIN_TAB,
            false
        )
        return
    end
    local ok, reason, domain = SuppressNativeFrameVisuals(state)
    if not ok then
        HandleNativeMutationFailure(
            state,
            reason,
            domain or DOMAIN_FRAME,
            false
        )
    end
end

local function NativeWindowAlphaChanged(frame, alpha)
    local state = frameStates[frame]
    if not IsActiveManagedState(state) or not UpdateNativeWindowAlpha then return end
    local ok, reason = UpdateNativeWindowAlpha(state, alpha)
    if not ok and HandleNativeMutationFailure then
        HandleNativeMutationFailure(state, reason, DOMAIN_FRAME, false)
        return
    end
    ok, reason = SuppressFrameDomain(state)
    local domain = DOMAIN_FRAME
    if ok then
        domain = DOMAIN_BUTTONS
        ok, reason = SuppressButtonDomain(state)
    end
    if not ok then
        HandleNativeMutationFailure(state, reason, domain, false)
    end
end

local function NativeWindowColorChanged(frame)
    local state = GetActiveManagedState(frame)
    if not state then return end
    local ok, reason = SuppressFrameDomain(state)
    if not ok then
        HandleNativeMutationFailure(state, reason, DOMAIN_FRAME, false)
    end
end

local function NativeWindowUpdateCompleted(id)
    if Appearance.enabled ~= true
        or Appearance.mutationPaused == true
        or not IsVisualMutationAllowed()
        or type(Adapter.ResolveAppearanceFrameByID) ~= "function"
    then
        return
    end
    local frame = Adapter:ResolveAppearanceFrameByID(id)
    if not GetActiveManagedState(frame) then return end
    Appearance:ScheduleNativeSettle("native-window-update")
end

local function NativeScrollChanged(frame)
    local state = GetActiveManagedState(frame)
    if not state then return end
    local ok, reason = SuppressScrollDomain(state)
    if not ok then
        HandleNativeMutationFailure(state, reason, DOMAIN_SCROLL, false)
    end
end

local function NativeButtonRailChanged(frame)
    local state = GetActiveManagedState(frame)
    if not state then return end
    local ok, reason = SuppressButtonDomain(state)
    if not ok then
        HandleNativeMutationFailure(state, reason, DOMAIN_BUTTONS, false)
    end
end

local function NativeDockLifecycleChanged(frame)
    if not GetActiveManagedState(frame) then return end
    Appearance:ScheduleNativeSettle("native-dock-lifecycle")
end

local function ReconcileDockGeometryAfterNativeMutation()
    if nativeDockWidthSyncActive
        or Appearance.enabled ~= true
        or Appearance.mutationPaused == true
        or not IsVisualMutationAllowed()
        or type(Adapter.ReconcileAppearanceDockTabWidths) ~= "function"
    then
        return
    end
    local appearance = YChat:GetAppearance()
    if not appearance then return end
    nativeDockWidthSyncActive = true
    local reconciled, reason = Adapter:ReconcileAppearanceDockTabWidths(
        appearance.tabWidth,
        appearance.tabWidthMode,
        appearance.tabSpacing,
        appearance.tabLeftInset,
        appearance.hideCombatLog == true,
        true
    )
    nativeDockWidthSyncActive = false
    if not reconciled then
        Appearance.lastReason = reason or "appearance-dock-tab-immediate-reconcile-failed"
    end
end

local function RepairManagedDockTabs()
    if not RepairManagedTabColors then return end
    for _, state in pairs(frameStates) do
        if IsActiveManagedState(state) then
            local selected, reason = Adapter:IsAppearanceTabSelected(state.frame)
            if type(selected) == "boolean" then
                local repaired, repairReason = RepairManagedTabColors(state, selected)
                if not repaired then
                    HandleNativeMutationFailure(
                        state,
                        repairReason,
                        DOMAIN_TAB,
                        false
                    )
                end
            else
                HandleNativeMutationFailure(
                    state,
                    reason or "appearance-tab-selection-unavailable",
                    DOMAIN_TAB,
                    false
                )
            end
        end
    end
    for _, state in pairs(tabOnlyStates) do
        if IsActiveManagedState(state) then
            local selected, reason = Adapter:IsAppearanceTabSelected(state.frame)
            if type(selected) == "boolean" then
                local repaired, repairReason = RepairManagedTabColors(state, selected)
                if not repaired then
                    HandleNativeMutationFailure(
                        state,
                        repairReason,
                        DOMAIN_TAB,
                        false
                    )
                end
            else
                HandleNativeMutationFailure(
                    state,
                    reason or "appearance-tab-selection-unavailable",
                    DOMAIN_TAB,
                    false
                )
            end
        end
    end
end

local function NativeDockSelectionChanged(_, frame)
    ReconcileDockGeometryAfterNativeMutation()
    if not GetActiveManagedState(frame, true) then return end
    RepairManagedDockTabs()
    if RefreshOverflowSkin then RefreshOverflowSkin() end
end

local function NativeManagedButtonMutated(button)
    local state = buttonOwners[button]
    if IsActiveManagedState(state) then
        NativeButtonShown(button)
    end
end

local function NativeTabAlphaChanged(tab, alpha)
    local state = tabStates[tab]
    if nativeDockWidthSyncActive
        or not IsActiveManagedState(state)
        or state.settingTabAlpha == true
    then
        return
    end
    if not IsSafeValue(alpha) or not IsFiniteNumber(alpha) then
        if HandleNativeMutationFailure then
            HandleNativeMutationFailure(
                state,
                "appearance-native-tab-alpha-invalid",
                DOMAIN_TAB,
                false
            )
        end
        return
    end
    state.snapshot.tabAlpha = alpha
    if not CanSuppressNativeMutation
        or not CanSuppressNativeMutation(state)
    then
        return
    end
    local desiredAlpha = state.selected == true and 1 or TAB_INACTIVE_ALPHA
    local visibility = GetManagedFrameVisibility(state)
    if visibility == nil then
        HandleNativeMutationFailure(
            state,
            "appearance-native-tab-visibility-invalid",
            DOMAIN_TAB,
            false
        )
        return
    end
    local currentAlpha = ReadAlpha(state.targets.tab)
    local alphaMatches = NearlyEqual(currentAlpha, desiredAlpha * visibility)
    local repaired = alphaMatches and SetManagedTabTextAlpha(state, visibility)
        or SetManagedTabAlpha(state, desiredAlpha, true)
    if not repaired then
        if HandleNativeMutationFailure then
            HandleNativeMutationFailure(
                state,
                "appearance-native-tab-alpha-reapply-failed",
                DOMAIN_TAB,
                false
            )
        end
        return
    end
end

local function NativeTabTextAlphaChanged(tabText, alpha)
    local state = tabTextOwners[tabText]
    if not IsActiveManagedState(state) or state.settingTabTextAlpha == true then return end
    if not IsSafeValue(alpha) or not IsFiniteNumber(alpha) then
        if HandleNativeMutationFailure then
            HandleNativeMutationFailure(
                state,
                "appearance-native-tab-text-alpha-invalid",
                DOMAIN_TAB,
                false
            )
        end
        return
    end
    if not CanSuppressNativeMutation
        or not CanSuppressNativeMutation(state)
    then
        return
    end
    if not SetManagedTabTextAlpha
        or not SetManagedTabTextAlpha(state)
    then
        if HandleNativeMutationFailure then
            HandleNativeMutationFailure(
                state,
                "appearance-native-tab-text-alpha-reapply-failed",
                DOMAIN_TAB,
                false
            )
        end
        return
    end
end

local function NativeTabColorsChanged(tab, selected)
    local state = tabStates[tab]
    if nativeDockWidthSyncActive or not IsActiveManagedState(state) then return end
    nativeDockMutationObserved = true
    if UpdateNativeTabSnapshot then
        local updated, updateReason = UpdateNativeTabSnapshot(state)
        if not updated and HandleNativeMutationFailure then
            HandleNativeMutationFailure(state, updateReason, DOMAIN_TAB, false)
            return
        end
    end
    if RepairManagedTabColors then
        local synced, syncReason = RepairManagedTabColors(state, selected)
        if not synced then
            if HandleNativeMutationFailure then
                HandleNativeMutationFailure(state, syncReason, DOMAIN_TAB, false)
            end
            return
        end
    end
end

local function NativeDockTabsChanged(_, forceUpdate)
    if nativeDockWidthSyncActive or Appearance.enabled ~= true then return end
    if forceUpdate ~= true and nativeDockMutationObserved ~= true then return end
    nativeDockMutationObserved = false
    RepairManagedDockTabs()
    ReconcileDockGeometryAfterNativeMutation()
    if RefreshOverflowSkin then RefreshOverflowSkin() end
end

local function NativeOverflowListUpdated(list)
    if Appearance.mutationPaused == true or not IsVisualMutationAllowed() then return end
    if StyleOverflowList then StyleOverflowList(list) end
end

local function InstallNativeHook(name, callback)
    if nativeHookStates[name] == true then return true end
    if type(_G[name]) ~= "function" then return false, "native-hook-api-missing" end
    local installed = pcall(hooksecurefunc, name, callback)
    if installed then nativeHookStates[name] = true end
    return installed, installed and nil or "native-hook-install-failed"
end

local function EnsureNativeHooks()
    if type(hooksecurefunc) ~= "function"
        or type(UIFrameFadeRemoveFrame) ~= "function"
    then
        return false, "appearance-native-hook-api-missing"
    end
    local required = {
        { "FCF_FadeInChatFrame", NativeFrameVisualsChanged },
        { "FCF_FadeOutChatFrame", NativeFrameVisualsChanged },
        { "FCF_SetWindowAlpha", NativeWindowAlphaChanged },
        { "FCFTab_UpdateColors", NativeTabColorsChanged },
    }
    local optional = {
        { "FCFDock_UpdateTabs", NativeDockTabsChanged },
        { "FCFDockOverflowList_Update", NativeOverflowListUpdated },
        { "FloatingChatFrame_Update", NativeWindowUpdateCompleted },
        { "FloatingChatFrame_UpdateScroll", NativeScrollChanged },
        { "FCF_SetWindowColor", NativeWindowColorChanged },
        { "FCF_SetButtonSide", NativeButtonRailChanged },
        { "FCF_UpdateButtonSide", NativeButtonRailChanged },
        { "FCF_UpdateResizeButton", NativeButtonRailChanged },
        { "FCF_DockFrame", NativeDockLifecycleChanged },
        { "FCF_UnDockFrame", NativeDockLifecycleChanged },
        { "FCF_SetWindowName", NativeDockLifecycleChanged },
        { "FCF_MinimizeFrame", NativeDockLifecycleChanged },
        { "FCF_MaximizeFrame", NativeDockLifecycleChanged },
        { "FCFDock_SelectWindow", NativeDockSelectionChanged },
    }
    local requiredPending = false
    for index = 1, #required do
        local definition = required[index]
        local installed = InstallNativeHook(definition[1], definition[2])
        if not installed then requiredPending = true end
    end
    for index = 1, #optional do
        local definition = optional[index]
        InstallNativeHook(definition[1], definition[2])
    end
    if requiredPending then
        return false, "appearance-native-hook-install-pending"
    end
    if not nativeHookStates.FCF_FadeInChatFrame
        or not nativeHookStates.FCF_FadeOutChatFrame
        or not nativeHookStates.FCF_SetWindowAlpha
        or not nativeHookStates.FCFTab_UpdateColors
    then
        return false, "appearance-native-hook-install-failed"
    end

    return true
end

ReadAlpha = function(region)
    local callback = region and region.GetAlpha
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback, region)
    if not ok or not IsSafeValue(value) or not IsFiniteNumber(value) then return nil end
    return value
end

local function CaptureRegions(regions, captureTexture, captureShown)
    local snapshot = {}
    for index = 1, #regions do
        local region = regions[index]
        local allowed = Adapter:CanCallProtected(region)
        local alpha = allowed == true and ReadAlpha(region) or nil
        if alpha == nil then return nil, "appearance-region-capture-failed" end
        local shown
        if captureShown == true then
            local shownOK
            shownOK, shown = pcall(region.IsShown, region)
            if not shownOK
                or not IsSafeValue(shown)
                or type(shown) ~= "boolean"
            then
                return nil, "appearance-region-shown-capture-failed"
            end
        end
        local texture, atlas
        if captureTexture == true then
            local textureOK
            textureOK, texture = pcall(region.GetTexture, region)
            if not textureOK
                or (texture ~= nil
                    and (not IsSafeValue(texture)
                        or (type(texture) ~= "string"
                            and (not IsFiniteNumber(texture) or floor(texture) ~= texture))))
            then
                return nil, "appearance-tab-texture-capture-failed"
            end
            if type(region.GetAtlas) == "function" then
                local atlasOK
                atlasOK, atlas = pcall(region.GetAtlas, region)
                if not atlasOK
                    or (atlas ~= nil
                        and (not IsSafeValue(atlas) or type(atlas) ~= "string"))
                then
                    return nil, "appearance-tab-atlas-capture-failed"
                end
            end
        end
        snapshot[index] = {
            region = region,
            alpha = alpha,
            shown = shown,
            texture = texture,
            atlas = atlas,
        }
    end
    return snapshot
end

local function CaptureEditBoxPoints(editBox)
    local allowed = Adapter:CanCallProtected(editBox)
    if allowed ~= true then return nil, "appearance-editbox-protected" end

    local countOK, count = pcall(editBox.GetNumPoints, editBox)
    if not countOK
        or not IsSafeValue(count)
        or not IsFiniteNumber(count)
        or floor(count) ~= count
        or count < 1
        or count > 8
    then
        return nil, "appearance-editbox-point-count-invalid"
    end

    local points = {}
    for index = 1, count do
        local ok, point, relativeTo, relativePoint, x, y =
            pcall(editBox.GetPoint, editBox, index)
        if not ok
            or not IsSafeValue(point)
            or not IsSafeValue(relativeTo)
            or not IsSafeValue(relativePoint)
            or not IsSafeValue(x)
            or not IsSafeValue(y)
            or type(point) ~= "string"
            or VALID_POINTS[point] ~= true
            or type(relativePoint) ~= "string"
            or VALID_POINTS[relativePoint] ~= true
            or not IsFiniteNumber(x)
            or not IsFiniteNumber(y)
        then
            return nil, "appearance-editbox-point-invalid"
        end
        points[index] = {
            point,
            relativeTo,
            relativePoint,
            x,
            y,
        }
    end
    return points
end

local function CaptureEditBoxHeight(editBox)
    if type(editBox.GetHeight) ~= "function"
        or type(editBox.SetHeight) ~= "function"
    then
        return nil, "appearance-editbox-height-api-missing"
    end
    local ok, height = pcall(editBox.GetHeight, editBox)
    if not ok or not IsSafeValue(height)
        or not IsFiniteNumber(height) or height <= 0
    then
        return nil, "appearance-editbox-height-invalid"
    end
    return height
end

local function CaptureInputTextAlignment(editBox)
    if type(editBox.GetJustifyV) ~= "function"
        or type(editBox.SetJustifyV) ~= "function"
    then
        return nil
    end
    local ok, justify = pcall(editBox.GetJustifyV, editBox)
    if not ok or not IsSafeValue(justify) or type(justify) ~= "string" then
        return nil, "appearance-editbox-justify-invalid"
    end
    return justify
end

local function CaptureOptionalHeight(frame)
    if not frame
        or type(frame.GetHeight) ~= "function"
        or type(frame.SetHeight) ~= "function"
    then
        return nil
    end
    local ok, height = pcall(frame.GetHeight, frame)
    if not ok or not IsSafeValue(height)
        or not IsFiniteNumber(height) or height <= 0
    then
        return nil, "appearance-input-language-height-invalid"
    end
    return height
end

local function CaptureButtonObjects(buttons)
    local snapshot = {}
    for index = 1, #buttons do
        local button = buttons[index]
        if Adapter:CanCallProtected(button) ~= true then
            return nil, "appearance-button-object-protected"
        end
        local shownOK, shown = pcall(button.IsShown, button)
        local alphaOK, alpha = pcall(button.GetAlpha, button)
        local mouseOK, mouse = pcall(button.IsMouseEnabled, button)
        if not shownOK
            or not alphaOK
            or not mouseOK
            or not IsSafeValue(shown)
            or not IsSafeValue(alpha)
            or not IsSafeValue(mouse)
            or type(shown) ~= "boolean"
            or not IsFiniteNumber(alpha)
            or type(mouse) ~= "boolean"
        then
            return nil, "appearance-button-object-capture-failed"
        end
        local enabled
        if type(button.IsEnabled) == "function" then
            local enabledOK
            enabledOK, enabled = pcall(button.IsEnabled, button)
            if not enabledOK
                or not IsSafeValue(enabled)
                or type(enabled) ~= "boolean"
            then
                return nil, "appearance-button-enabled-capture-failed"
            end
        end
        snapshot[index] = {
            button = button,
            shown = shown,
            alpha = alpha,
            mouse = mouse,
            enabled = enabled,
        }
    end
    return snapshot
end

function Appearance:CaptureOptionalControls(targets)
    local buttonRegions, buttonReason = CaptureRegions(targets.buttonRegions)
    if not buttonRegions then return nil, nil, nil, buttonReason end
    local buttonObjects, objectReason =
        CaptureButtonObjects(targets.buttonObjects or EMPTY_BUTTONS)
    if not buttonObjects then return nil, nil, nil, objectReason end
    local scrollObjects, scrollReason =
        CaptureButtonObjects(targets.scrollObjects or EMPTY_BUTTONS)
    if not scrollObjects then return nil, nil, nil, scrollReason end
    return buttonRegions, buttonObjects, scrollObjects
end

function Appearance:CaptureInputPresentation(targets)
    if not targets.editBox then return nil, nil, nil, nil end
    local points, pointReason = CaptureEditBoxPoints(targets.editBox)
    if not points then return nil, nil, nil, nil, pointReason end
    local height, heightReason = CaptureEditBoxHeight(targets.editBox)
    if not height then return nil, nil, nil, nil, heightReason end
    local justifyV, justifyReason = CaptureInputTextAlignment(targets.editBox)
    if justifyReason then return nil, nil, nil, nil, justifyReason end
    local languageHeight, languageReason =
        CaptureOptionalHeight(targets.inputLanguageButton)
    if languageReason then return nil, nil, nil, nil, languageReason end
    return points, height, justifyV, languageHeight
end

local function CaptureTabPresentation(targets)
    local tabAlpha = ReadAlpha(targets.tab)
    if tabAlpha == nil then return nil, "appearance-tab-alpha-capture-failed" end
    local tabTextAlpha = ReadAlpha(targets.tabText)
    if tabTextAlpha == nil then
        return nil, "appearance-tab-text-alpha-capture-failed"
    end
    local ignoresParentAlpha
    if type(targets.tabText.IsIgnoringParentAlpha) == "function" then
        local ignoreOK, value = pcall(
            targets.tabText.IsIgnoringParentAlpha,
            targets.tabText
        )
        if not ignoreOK or type(value) ~= "boolean" then
            return nil, "appearance-tab-text-parent-alpha-capture-failed"
        end
        ignoresParentAlpha = value
    end
    local pushedOK, pushedX, pushedY = pcall(
        targets.tab.GetPushedTextOffset,
        targets.tab
    )
    if not pushedOK
        or not IsSafeValue(pushedX)
        or not IsFiniteNumber(pushedX)
        or not IsSafeValue(pushedY)
        or not IsFiniteNumber(pushedY)
    then
        return nil, "appearance-tab-pushed-offset-capture-failed"
    end
    local tabText = targets.tabText
    local textOK, r, g, b, a = pcall(tabText.GetTextColor, tabText)
    if not textOK
        or not IsSafeValue(r)
        or not IsSafeValue(g)
        or not IsSafeValue(b)
        or not IsSafeValue(a)
        or not IsFiniteNumber(r)
        or not IsFiniteNumber(g)
        or not IsFiniteNumber(b)
        or not IsFiniteNumber(a)
    then
        return nil, "appearance-tab-color-capture-failed"
    end

    local fontOK, fontFile, fontHeight, fontFlags = pcall(tabText.GetFont, tabText)
    if not fontOK
        or not IsSafeValue(fontFile)
        or type(fontFile) ~= "string"
        or fontFile == ""
        or not IsSafeValue(fontHeight)
        or not IsFiniteNumber(fontHeight)
        or not IsSafeValue(fontFlags)
        or (fontFlags ~= nil and type(fontFlags) ~= "string")
    then
        return nil, "appearance-tab-font-capture-failed"
    end
    local shadowOK, shadowR, shadowG, shadowB, shadowA =
        pcall(tabText.GetShadowColor, tabText)
    if not shadowOK
        or not IsSafeValue(shadowR)
        or not IsFiniteNumber(shadowR)
        or not IsSafeValue(shadowG)
        or not IsFiniteNumber(shadowG)
        or not IsSafeValue(shadowB)
        or not IsFiniteNumber(shadowB)
        or not IsSafeValue(shadowA)
        or not IsFiniteNumber(shadowA)
    then
        return nil, "appearance-tab-shadow-color-capture-failed"
    end
    local offsetOK, shadowX, shadowY = pcall(tabText.GetShadowOffset, tabText)
    if not offsetOK
        or not IsSafeValue(shadowX)
        or not IsFiniteNumber(shadowX)
        or not IsSafeValue(shadowY)
        or not IsFiniteNumber(shadowY)
    then
        return nil, "appearance-tab-shadow-offset-capture-failed"
    end
    local tabTextPoints, pointReason = CaptureEditBoxPoints(tabText)
    if not tabTextPoints then
        return nil, pointReason or "appearance-tab-text-point-capture-failed"
    end
    return {
        tabAlpha = tabAlpha,
        tabTextAlpha = tabTextAlpha,
        tabTextIgnoresParentAlpha = ignoresParentAlpha,
        tabTextColor = { r, g, b, a },
        tabFont = { fontFile, fontHeight, fontFlags },
        tabShadowColor = { shadowR, shadowG, shadowB, shadowA },
        tabShadowOffset = { shadowX, shadowY },
        tabTextPoints = tabTextPoints,
        tabPushedTextOffset = { pushedX, pushedY },
    }
end

local function CaptureFrame(targets)
    local tabPresentation, presentationReason = CaptureTabPresentation(targets)
    if not tabPresentation then return nil, presentationReason end

    local frameRegions, frameReason = CaptureRegions(targets.frameRegions, false, true)
    if not frameRegions then return nil, frameReason end
    local tabRegions, tabReason = CaptureRegions(targets.tabRegions, true)
    if not tabRegions then return nil, tabReason end
    local buttonRegions, buttonObjects, scrollObjects, controlsReason =
        Appearance:CaptureOptionalControls(targets)
    local controlsPending = buttonRegions == nil
    if controlsPending then
        buttonRegions = {}
        buttonObjects = {}
        scrollObjects = {}
    end
    local editBoxPoints
    local editBoxHeight
    local editBoxJustifyV
    local inputLanguageButtonHeight
    local inputReason
    if targets.editBox then
        editBoxPoints, editBoxHeight, editBoxJustifyV,
            inputLanguageButtonHeight, inputReason =
            Appearance:CaptureInputPresentation(targets)
    end

    tabPresentation.frameRegions = frameRegions
    tabPresentation.tabRegions = tabRegions
    tabPresentation.buttonRegions = buttonRegions
    tabPresentation.buttonObjects = buttonObjects
    tabPresentation.scrollObjects = scrollObjects
    tabPresentation.editBoxPoints = editBoxPoints
    tabPresentation.editBoxHeight = editBoxHeight
    tabPresentation.editBoxJustifyV = editBoxJustifyV
    tabPresentation.inputLanguageButtonHeight = inputLanguageButtonHeight
    tabPresentation.controlsCapturePending = controlsPending
    tabPresentation.controlsCaptureReason = controlsReason
    tabPresentation.inputCapturePending = targets.editBox ~= nil and editBoxPoints == nil
    tabPresentation.inputCaptureReason = inputReason
    return tabPresentation
end

local function CaptureTab(targets)
    local snapshot, presentationReason = CaptureTabPresentation(targets)
    if not snapshot then return nil, presentationReason end
    local tabRegions, tabReason = CaptureRegions(targets.tabRegions, true)
    if not tabRegions then return nil, tabReason end
    snapshot.tabRegions = tabRegions
    return snapshot
end

local function PreflightAppearanceTargets(targets)
    local allowed = Adapter:CanCallProtected(targets.frame)
    if allowed ~= true then return false, "appearance-frame-protected" end
    allowed = Adapter:CanCallProtected(targets.tab)
    if allowed ~= true then return false, "appearance-tab-protected" end
    allowed = Adapter:CanCallProtected(targets.tabText)
    if allowed ~= true then return false, "appearance-tab-text-protected" end
    local regions = targets.frameRegions
    for index = 1, #regions do
        allowed = Adapter:CanCallProtected(regions[index])
        if allowed ~= true then return false, "appearance-frame-region-protected" end
    end
    regions = targets.tabRegions
    for index = 1, #regions do
        allowed = Adapter:CanCallProtected(regions[index])
        if allowed ~= true then return false, "appearance-tab-region-protected" end
    end
    return true
end

local function PreflightTabTargets(targets)
    if Adapter:CanCallProtected(targets.frame) ~= true then
        return false, "appearance-tab-frame-protected"
    end
    if Adapter:CanCallProtected(targets.tab) ~= true then
        return false, "appearance-tab-protected"
    end
    if Adapter:CanCallProtected(targets.tabText) ~= true then
        return false, "appearance-tab-text-protected"
    end
    for index = 1, #targets.tabRegions do
        if Adapter:CanCallProtected(targets.tabRegions[index]) ~= true then
            return false, "appearance-tab-region-protected"
        end
    end
    return true
end

local function CreateTexture(parent, layer, subLevel)
    local allowed = Adapter:CanCallProtected(parent)
    if allowed ~= true then return nil, "appearance-art-parent-protected" end
    local callback = parent and parent.CreateTexture
    if type(callback) ~= "function" then return nil, "appearance-art-api-missing" end
    local ok, texture = pcall(callback, parent, nil, layer, nil, subLevel)
    if not ok or not texture then return nil, "appearance-art-create-failed" end
    allocatedTextures = allocatedTextures + 1
    if not CallMethod(texture, "Hide") then
        return nil, "appearance-art-hide-failed"
    end
    return texture
end

local function ConfigureFlatTexture(texture)
    if type(texture.SetSnapToPixelGrid) == "function" then
        pcall(texture.SetSnapToPixelGrid, texture, false)
    end
    if type(texture.SetTexelSnappingBias) == "function" then
        pcall(texture.SetTexelSnappingBias, texture, 0)
    end
    return CallMethod(texture, "Hide")
        and CallMethod(texture, "SetColorTexture", 1, 1, 1, 1)
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

local function ReadThemeColor(key)
    if not GUI2 or type(GUI2.GetColor) ~= "function" then return nil end
    local ok, r, g, b, a = pcall(GUI2.GetColor, GUI2, key)
    if not ok then return nil end
    return r, g, b, a
end

local function PaintFlatTexture(texture, key)
    local r, g, b, a = ReadThemeColor(key)
    if r == nil then return false end
    return CallMethod(texture, "SetColorTexture", r, g, b, a)
        and CallMethod(texture, "Show")
end

local function CreateOverflowBorder(parent)
    local size = GetPixelSize(parent, 1, 1)
    local border = {}
    local definitions = {
        { "TOPLEFT", "TOPRIGHT", "SetHeight" },
        { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight" },
        { "TOPLEFT", "BOTTOMLEFT", "SetWidth" },
        { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth" },
    }
    for index = 1, #definitions do
        local texture = CreateTexture(parent, "OVERLAY", 7)
        if not texture or not ConfigureFlatTexture(texture) then return nil end
        local definition = definitions[index]
        if not CallMethod(texture, "ClearAllPoints")
            or not CallMethod(texture, "SetPoint", definition[1], parent, definition[1], 0, 0)
            or not CallMethod(texture, "SetPoint", definition[2], parent, definition[2], 0, 0)
            or not CallMethod(texture, definition[3], size)
        then
            return nil
        end
        border[index] = texture
    end
    return border
end

local function SetOverflowBorder(border, key, shown)
    if type(border) ~= "table" then return false end
    local r, g, b, a = ReadThemeColor(key)
    if r == nil then return false end
    for index = 1, #border do
        local texture = border[index]
        if shown then
            if not CallMethod(texture, "SetColorTexture", r, g, b, a)
                or not CallMethod(texture, "Show")
            then
                return false
            end
        elseif not CallMethod(texture, "Hide") then
            return false
        end
    end
    return true
end

local function CaptureOverflowTexture(region)
    local snapshot = CaptureRegions({ region }, true, true)
    snapshot = snapshot and snapshot[1]
    if not snapshot then return nil end
    if type(region.GetTexCoord) == "function" then
        local ok, ulX, ulY, llX, llY, urX, urY, lrX, lrY =
            pcall(region.GetTexCoord, region)
        if ok then
            snapshot.texCoords = { ulX, ulY, llX, llY, urX, urY, lrX, lrY }
        end
    end
    if type(region.GetVertexColor) == "function" then
        local ok, r, g, b, a = pcall(region.GetVertexColor, region)
        if ok then
            snapshot.vertexR = r
            snapshot.vertexG = g
            snapshot.vertexB = b
            snapshot.vertexA = a
        end
    end
    return snapshot
end

local function RestoreOverflowTexture(snapshot)
    local region = snapshot and snapshot.region
    if not region then return false end
    local restored
    if snapshot.atlas and type(region.SetAtlas) == "function" then
        restored = pcall(region.SetAtlas, region, snapshot.atlas, false)
    else
        restored = pcall(region.SetTexture, region, snapshot.texture)
    end
    if not restored or not pcall(region.SetAlpha, region, snapshot.alpha) then return false end
    if snapshot.texCoords and type(region.SetTexCoord) == "function" then
        if not pcall(region.SetTexCoord, region, unpack(snapshot.texCoords)) then
            return false
        end
    end
    if snapshot.vertexR ~= nil and type(region.SetVertexColor) == "function" then
        if not pcall(
            region.SetVertexColor,
            region,
            snapshot.vertexR,
            snapshot.vertexG,
            snapshot.vertexB,
            snapshot.vertexA
        ) then
            return false
        end
    end
    if snapshot.shown then return CallMethod(region, "Show") end
    return CallMethod(region, "Hide")
end

local function CaptureOverflowLayering(list)
    if not list
        or type(list.GetFrameStrata) ~= "function"
        or type(list.SetFrameStrata) ~= "function"
        or type(list.GetFrameLevel) ~= "function"
        or type(list.SetFrameLevel) ~= "function"
    then
        return nil
    end
    local strataOK, strata = pcall(list.GetFrameStrata, list)
    local levelOK, level = pcall(list.GetFrameLevel, list)
    if not strataOK or not levelOK
        or type(strata) ~= "string" or strata == ""
        or not IsFiniteNumber(level)
    then
        return nil
    end
    return { strata = strata, level = level }
end

local function ApplyOverflowLayering(list, snapshot)
    if not list or type(snapshot) ~= "table" then return false end
    return pcall(list.SetFrameStrata, list, "DIALOG")
        and pcall(list.SetFrameLevel, list, snapshot.level)
end

local function RestoreOverflowLayering(list, snapshot)
    if not list or type(snapshot) ~= "table" then return false end
    return pcall(list.SetFrameStrata, list, snapshot.strata)
        and pcall(list.SetFrameLevel, list, snapshot.level)
end

local function CaptureOverflowBackdrop(list)
    if not list
        or type(list.GetBackdropColor) ~= "function"
        or type(list.GetBackdropBorderColor) ~= "function"
    then
        return nil
    end
    local bgOK, bgR, bgG, bgB, bgA = pcall(list.GetBackdropColor, list)
    local borderOK, borderR, borderG, borderB, borderA =
        pcall(list.GetBackdropBorderColor, list)
    if not bgOK or not borderOK then return nil end
    return {
        bgR, bgG, bgB, bgA,
        borderR, borderG, borderB, borderA,
    }
end

local function SuppressOverflowBackdrop(list)
    return pcall(list.SetBackdropColor, list, 0, 0, 0, 0)
        and pcall(list.SetBackdropBorderColor, list, 0, 0, 0, 0)
end

local function RestoreOverflowBackdrop(list, snapshot)
    if not list or type(snapshot) ~= "table" then return false end
    return pcall(
        list.SetBackdropColor,
        list,
        snapshot[1], snapshot[2], snapshot[3], snapshot[4]
    ) and pcall(
        list.SetBackdropBorderColor,
        list,
        snapshot[5], snapshot[6], snapshot[7], snapshot[8]
    )
end

local function CaptureOverflowRow(row, list)
    local fontString = row and row.GetFontString and row:GetFontString()
    local highlight = row and row.highlight
    if not fontString
        or type(fontString.GetFont) ~= "function"
        or type(fontString.GetTextColor) ~= "function"
        or not highlight
    then
        return nil
    end
    local fontOK, file, height, flags = pcall(fontString.GetFont, fontString)
    local colorOK, r, g, b, a = pcall(fontString.GetTextColor, fontString)
    local highlightSnapshot = CaptureOverflowTexture(highlight)
    if not fontOK or not colorOK or not highlightSnapshot then return nil end
    return {
        list = list,
        fontString = fontString,
        fontFile = file,
        fontHeight = height,
        fontFlags = flags,
        textR = r,
        textG = g,
        textB = b,
        textA = a,
        highlight = highlightSnapshot,
    }
end

local function RestoreOverflowRow(snapshot)
    local fontString = snapshot and snapshot.fontString
    if not fontString then return false end
    local fontOK = pcall(
        fontString.SetFont,
        fontString,
        snapshot.fontFile,
        snapshot.fontHeight,
        snapshot.fontFlags
    )
    local colorOK = pcall(
        fontString.SetTextColor,
        fontString,
        snapshot.textR,
        snapshot.textG,
        snapshot.textB,
        snapshot.textA
    )
    return fontOK and colorOK and RestoreOverflowTexture(snapshot.highlight)
end

local function SetOverflowButtonState(state, mode)
    if not state or state.applied ~= true then return end
    local surface = mode == "pressed" and "color.control.active"
        or mode == "hover" and "color.control.hover"
        or "color.control.bg"
    local iconKey = mode == "normal"
        and "color.dropdown.arrow.default"
        or "color.dropdown.arrow.hover"
    local iconR, iconG, iconB, iconA = ReadThemeColor(iconKey)
    PaintFlatTexture(state.buttonBackground, surface)
    if iconR ~= nil then
        pcall(state.buttonIcon.SetVertexColor, state.buttonIcon, iconR, iconG, iconB, iconA)
    end
    SetOverflowBorder(
        state.buttonBorder,
        mode == "normal" and "color.border.subtle" or "color.border.accent",
        true
    )
end

StyleOverflowList = function(list)
    local state = overflowSkinState
    if Appearance.enabled ~= true
        or not state
        or state.applied ~= true
        or list ~= state.targets.list
    then
        return
    end
    if not ApplyOverflowLayering(list, state.layerSnapshot) then return end
    PaintFlatTexture(state.listBackground, "color.surface.window")
    SetOverflowBorder(state.listBorder, "color.border.default", true)
    SuppressOverflowBackdrop(list)
    local fontFile = GUI2 and GUI2.GetFont
        and GUI2:GetFont("font.family.body")
    local fontSize = GUI2 and GUI2.GetMetric
        and GUI2:GetMetric("font.size.md", 13)
    local textR, textG, textB, textA = ReadThemeColor("color.text.primary")
    local accentR, accentG, accentB = ReadThemeColor("color.accent.primary")
    local buttons = list.buttons
    for index = 1, #buttons do
        local row = buttons[index]
        local snapshot = overflowRowSnapshots[row]
        if not snapshot then
            snapshot = CaptureOverflowRow(row, list)
            overflowRowSnapshots[row] = snapshot
        end
        local fontString = row.GetFontString and row:GetFontString()
        if snapshot and fontString and type(fontFile) == "string" then
            pcall(fontString.SetFont, fontString, fontFile, fontSize, "")
            if textR ~= nil then
                pcall(fontString.SetTextColor, fontString, textR, textG, textB, textA)
            end
            if row.highlight and accentR ~= nil then
                pcall(row.highlight.SetTexture, row.highlight, "Interface\\Buttons\\WHITE8x8")
                pcall(row.highlight.SetVertexColor, row.highlight, accentR, accentG, accentB, 0.18)
                pcall(row.highlight.SetAlpha, row.highlight, 1)
            end
        end
    end
    if list.numTabs then
        if not state.numTabsSnapshot and type(list.numTabs.GetFont) == "function" then
            local ok, file, height, flags = pcall(list.numTabs.GetFont, list.numTabs)
            local colorOK, r, g, b, a = pcall(list.numTabs.GetTextColor, list.numTabs)
            if ok and colorOK then
                state.numTabsSnapshot = { file, height, flags, r, g, b, a }
            end
        end
        if type(fontFile) == "string" then
            pcall(list.numTabs.SetFont, list.numTabs, fontFile, fontSize, "")
        end
        local secondaryR, secondaryG, secondaryB, secondaryA =
            ReadThemeColor("color.text.secondary")
        if secondaryR ~= nil then
            pcall(
                list.numTabs.SetTextColor,
                list.numTabs,
                secondaryR,
                secondaryG,
                secondaryB,
                secondaryA
            )
        end
    end
end

RefreshOverflowSkin = function()
    if Appearance.enabled ~= true
        or Appearance.mutationPaused == true
        or not IsVisualMutationAllowed()
    then
        return false, "dock-overflow-skin-not-open"
    end
    if type(Adapter.GetDockOverflowTargets) ~= "function" then
        return true, "dock-overflow-target-api-unavailable"
    end
    local targets, targetReason = Adapter:GetDockOverflowTargets()
    if not targets then return false, targetReason end
    local state = overflowSkinState
    if state and state.targets.button ~= targets.button then
        RestoreOverflowSkin()
        state = nil
    end
    if not state then
        local normalSnapshot = CaptureOverflowTexture(targets.normalTexture)
        local highlightSnapshot = CaptureOverflowTexture(targets.highlightTexture)
        local backdropSnapshot = CaptureOverflowBackdrop(targets.list)
        local layerSnapshot = CaptureOverflowLayering(targets.list)
        if not normalSnapshot or not highlightSnapshot or not backdropSnapshot
            or not layerSnapshot
        then
            return false, "dock-overflow-texture-capture-failed"
        end
        local buttonBackground = CreateTexture(targets.button, "BACKGROUND", 7)
        local buttonIcon = CreateTexture(targets.button, "ARTWORK", 7)
        local listBackground = CreateTexture(targets.list, "BACKGROUND", 7)
        local buttonBorder = CreateOverflowBorder(targets.button)
        local listBorder = CreateOverflowBorder(targets.list)
        if not buttonBackground or not buttonIcon or not listBackground
            or not buttonBorder or not listBorder
            or not ConfigureFlatTexture(buttonBackground)
            or not ConfigureFlatTexture(listBackground)
            or not CallMethod(buttonBackground, "SetAllPoints", targets.button)
            or not CallMethod(buttonIcon, "SetPoint", "TOPLEFT", targets.button, "TOPLEFT", 2, -2)
            or not CallMethod(buttonIcon, "SetPoint", "BOTTOMRIGHT", targets.button, "BOTTOMRIGHT", -2, 2)
            or not CallMethod(listBackground, "SetAllPoints", targets.list)
        then
            return false, "dock-overflow-art-allocation-failed"
        end
        state = {
            targets = targets,
            normalSnapshot = normalSnapshot,
            highlightSnapshot = highlightSnapshot,
            backdropSnapshot = backdropSnapshot,
            layerSnapshot = layerSnapshot,
            buttonBackground = buttonBackground,
            buttonIcon = buttonIcon,
            listBackground = listBackground,
            buttonBorder = buttonBorder,
            listBorder = listBorder,
            applied = false,
        }
        overflowSkinState = state
        if not state.hooksInstalled then
            local hookedButton = targets.button
            targets.button:HookScript("OnEnter", function()
                if Appearance.enabled and overflowSkinState
                    and overflowSkinState.targets.button == hookedButton
                then
                    SetOverflowButtonState(overflowSkinState, "hover")
                end
            end)
            targets.button:HookScript("OnLeave", function()
                if Appearance.enabled and overflowSkinState
                    and overflowSkinState.targets.button == hookedButton
                then
                    SetOverflowButtonState(overflowSkinState, "normal")
                end
            end)
            targets.button:HookScript("OnMouseDown", function()
                if Appearance.enabled and overflowSkinState
                    and overflowSkinState.targets.button == hookedButton
                then
                    SetOverflowButtonState(overflowSkinState, "pressed")
                end
            end)
            targets.button:HookScript("OnMouseUp", function()
                if Appearance.enabled and overflowSkinState
                    and overflowSkinState.targets.button == hookedButton
                then
                    SetOverflowButtonState(overflowSkinState, "hover")
                end
            end)
            local hookedList = targets.list
            targets.list:HookScript("OnShow", function()
                if Appearance.enabled and overflowSkinState
                    and overflowSkinState.targets.list == hookedList
                then
                    StyleOverflowList(hookedList)
                end
            end)
            state.hooksInstalled = true
        end
    end

    local applyMicroIcon = GUI2 and GUI2.ApplyMicroIcon
    if type(applyMicroIcon) ~= "function" then
        return false, "dock-overflow-icon-unavailable"
    end
    local normal = targets.normalTexture
    local highlight = targets.highlightTexture
    local textR, textG, textB, textA = ReadThemeColor("color.dropdown.arrow.default")
    local accentR, accentG, accentB, accentA = ReadThemeColor("color.accent.primary")
    if not pcall(applyMicroIcon, GUI2, state.buttonIcon, "arrow-big-down", 16)
        or not pcall(normal.SetAlpha, normal, 0)
        or not pcall(applyMicroIcon, GUI2, highlight, "arrow-big-down", 16)
        or textR == nil or accentR == nil
        or not pcall(state.buttonIcon.SetVertexColor, state.buttonIcon, textR, textG, textB, textA)
        or not pcall(highlight.SetVertexColor, highlight, accentR, accentG, accentB, accentA)
        or not CallMethod(state.buttonIcon, "Show")
        or not SuppressOverflowBackdrop(targets.list)
        or not ApplyOverflowLayering(targets.list, state.layerSnapshot)
    then
        return false, "dock-overflow-icon-apply-failed"
    end
    state.applied = true
    PaintFlatTexture(state.buttonBackground, "color.control.bg")
    PaintFlatTexture(state.listBackground, "color.surface.window")
    SetOverflowBorder(state.buttonBorder, "color.border.subtle", true)
    SetOverflowBorder(state.listBorder, "color.border.default", true)
    StyleOverflowList(targets.list)
    return true
end

RestoreOverflowSkin = function()
    local state = overflowSkinState
    if not state or state.applied ~= true then return true end
    local restored = RestoreOverflowTexture(state.normalSnapshot)
        and RestoreOverflowTexture(state.highlightSnapshot)
        and RestoreOverflowBackdrop(state.targets.list, state.backdropSnapshot)
        and RestoreOverflowLayering(state.targets.list, state.layerSnapshot)
    CallMethod(state.buttonBackground, "Hide")
    CallMethod(state.buttonIcon, "Hide")
    CallMethod(state.listBackground, "Hide")
    SetOverflowBorder(state.buttonBorder, "color.border.default", false)
    SetOverflowBorder(state.listBorder, "color.border.default", false)
    for row, snapshot in pairs(overflowRowSnapshots) do
        if snapshot.list == state.targets.list then
            if not RestoreOverflowRow(snapshot) then restored = false end
            overflowRowSnapshots[row] = nil
        end
    end
    if state.numTabsSnapshot and state.targets.list.numTabs then
        local values = state.numTabsSnapshot
        local text = state.targets.list.numTabs
        if not pcall(text.SetFont, text, values[1], values[2], values[3])
            or not pcall(text.SetTextColor, text, values[4], values[5], values[6], values[7])
        then
            restored = false
        end
    end
    state.numTabsSnapshot = nil
    state.applied = false
    return restored, restored and nil or "dock-overflow-restore-failed"
end

local function ConfigureLine(texture, anchor, firstPoint, secondPoint)
    return CallMethod(texture, "ClearAllPoints")
        and CallMethod(
            texture,
            "SetPoint",
            firstPoint[1],
            anchor,
            firstPoint[2],
            firstPoint[3],
            firstPoint[4]
        )
        and CallMethod(
            texture,
            "SetPoint",
            secondPoint[1],
            anchor,
            secondPoint[2],
            secondPoint[3],
            secondPoint[4]
        )
end

local function ConfigureTabUnderline(
    texture,
    tabText,
    textEffect,
    textWidth,
    textHeight
)
    local overhang = GetPixelSize(tabText, 4, 1)
    local offsetPixels = (
        textEffect == "outline"
        or textEffect == "thick"
        or textEffect == "outlineShadow"
    )
        and 5
        or 4
    local offset = GetPixelSize(tabText, offsetPixels, 1)
    local thickness = GetPixelSize(tabText, 2, 1)
    return CallMethod(texture, "ClearAllPoints")
        and CallMethod(
            texture,
            "SetPoint",
            "TOP",
            tabText,
            "CENTER",
            0,
            -((textHeight * 0.5) + offset)
        )
        and CallMethod(texture, "SetWidth", textWidth + (overhang * 2))
        and CallMethod(texture, "SetHeight", thickness)
end

local function ConfigureTabBlock(texture, tabText, textWidth, textHeight)
    local horizontalPadding = GetPixelSize(tabText, 6, 1)
    local verticalPadding = GetPixelSize(tabText, 5, 1)
    local minimumHeight = GetPixelSize(tabText, 24, 1)
    local height = math.max(
        minimumHeight,
        textHeight + (verticalPadding * 2)
    )
    return CallMethod(texture, "ClearAllPoints")
        and CallMethod(
            texture,
            "SetPoint",
            "CENTER",
            tabText,
            "CENTER",
            0,
            0
        )
        and CallMethod(texture, "SetWidth", textWidth + (horizontalPadding * 2))
        and CallMethod(texture, "SetHeight", height)
end

local function ConfigureTabSlotBlock(texture, tabText, tabWidth, textHeight)
    local verticalPadding = GetPixelSize(tabText, 5, 1)
    local minimumHeight = GetPixelSize(tabText, 24, 1)
    local height = math.max(
        minimumHeight,
        textHeight + (verticalPadding * 2)
    )
    return CallMethod(texture, "ClearAllPoints")
        and CallMethod(texture, "SetPoint", "CENTER", tabText, "CENTER", 0, 0)
        and CallMethod(texture, "SetWidth", tabWidth)
        and CallMethod(texture, "SetHeight", height)
end

local function ConfigureDarkUnderline(texture, block, tabText)
    local thickness = GetPixelSize(tabText, 2, 1)
    return CallMethod(texture, "ClearAllPoints")
        and CallMethod(texture, "SetPoint", "BOTTOMLEFT", block, "BOTTOMLEFT", 0, 0)
        and CallMethod(texture, "SetPoint", "BOTTOMRIGHT", block, "BOTTOMRIGHT", 0, 0)
        and CallMethod(texture, "SetHeight", thickness)
end

local function ConfigureTabArtGeometry(
    art,
    tabText,
    tabStyle,
    textEffect,
    tabWidth
)
    local textWidth, textHeight = Adapter:ReadAppearanceTabTextMetrics(tabText)
    if not textWidth or not textHeight then return false end
    local darkUnderline = tabStyle == "darkUnderline"
    local slotBlock = darkUnderline or tabStyle == "block"
    local ok
    if slotBlock then
        ok = ConfigureTabSlotBlock(art.block, tabText, tabWidth, textHeight)
    else
        ok = ConfigureTabBlock(art.block, tabText, textWidth, textHeight)
    end
    if darkUnderline then
        ok = ConfigureDarkUnderline(art.underline, art.block, tabText) and ok
    else
        ok = ConfigureTabUnderline(
            art.underline,
            tabText,
            textEffect,
            textWidth,
            textHeight
        ) and ok
    end
    if art.glow then
        ok = ConfigureTabUnderline(
            art.glow,
            tabText,
            textEffect,
            textWidth,
            textHeight
        ) and ok
    end
    return ok
end

local function OnAnimationStopped(group)
    local state = animationStates[group]
    if not state or state.activeAnimation ~= group then return end
    state.activeAnimation = nil
    if activeAnimations > 0 then activeAnimations = activeAnimations - 1 end
    local art = state.art
    if art and art.glow then CallMethod(art.glow, "Hide") end
end

local function ConfigureAnimationGroup(group, first, second)
    if not group or type(group.CreateAnimation) ~= "function" then return false end
    local firstOK, firstAnimation = pcall(group.CreateAnimation, group, "Alpha")
    local secondOK, secondAnimation = pcall(group.CreateAnimation, group, "Alpha")
    if not firstOK or not secondOK or not firstAnimation or not secondAnimation then return false end

    return CallMethod(firstAnimation, "SetOrder", 1)
        and CallMethod(firstAnimation, "SetDuration", first[1])
        and CallMethod(firstAnimation, "SetFromAlpha", first[2])
        and CallMethod(firstAnimation, "SetToAlpha", first[3])
        and CallMethod(secondAnimation, "SetOrder", 2)
        and CallMethod(secondAnimation, "SetDuration", second[1])
        and CallMethod(secondAnimation, "SetFromAlpha", second[2])
        and CallMethod(secondAnimation, "SetToAlpha", second[3])
        and CallMethod(group, "SetScript", "OnFinished", OnAnimationStopped)
        and CallMethod(group, "SetScript", "OnStop", OnAnimationStopped)
end

local function AllocateArt(targets)
    local frame = targets.frame
    local tab = targets.tab
    local background, reason = CreateTexture(frame, "BACKGROUND", -7)
    if not background then return nil, reason end
    local top = CreateTexture(frame, "BORDER", 1)
    local bottom = CreateTexture(frame, "BORDER", 1)
    local left = CreateTexture(frame, "BORDER", 1)
    local right = CreateTexture(frame, "BORDER", 1)
    local underline = CreateTexture(tab, "ARTWORK", 1)
    local block = CreateTexture(tab, "BACKGROUND", 1)
    local glow = CreateTexture(tab, "OVERLAY", 2)
    if not top or not bottom or not left or not right or not underline or not block or not glow then
        return nil, "appearance-art-create-incomplete"
    end

    local textures = { background, top, bottom, left, right, underline, block, glow }
    for index = 1, #textures do
        if not ConfigureFlatTexture(textures[index]) then
            return nil, "appearance-art-configure-failed"
        end
    end

    local anchor = targets.background
    if not CallMethod(background, "ClearAllPoints")
        or not CallMethod(background, "SetAllPoints", anchor)
        or not ConfigureLine(
            top,
            anchor,
            { "TOPLEFT", "TOPLEFT", 0, 0 },
            { "TOPRIGHT", "TOPRIGHT", 0, 0 }
        )
        or not ConfigureLine(
            bottom,
            anchor,
            { "BOTTOMLEFT", "BOTTOMLEFT", 0, 0 },
            { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 }
        )
        or not ConfigureLine(
            left,
            anchor,
            { "TOPLEFT", "TOPLEFT", 0, 0 },
            { "BOTTOMLEFT", "BOTTOMLEFT", 0, 0 }
        )
        or not ConfigureLine(
            right,
            anchor,
            { "TOPRIGHT", "TOPRIGHT", 0, 0 },
            { "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0 }
        )
        or not CallMethod(underline, "Hide")
        or not CallMethod(block, "Hide")
        or not CallMethod(glow, "Hide")
    then
        return nil, "appearance-art-anchor-failed"
    end

    local createFadeAnimationGroup = targets.tabText.CreateAnimationGroup
    local createGlowAnimationGroup = glow.CreateAnimationGroup
    if type(createFadeAnimationGroup) ~= "function"
        or type(createGlowAnimationGroup) ~= "function"
    then
        return nil, "appearance-animation-api-missing"
    end
    local fadeOK, fadeGroup = pcall(createFadeAnimationGroup, targets.tabText)
    local glowOK, glowGroup = pcall(createGlowAnimationGroup, glow)
    if fadeOK and fadeGroup then
        allocatedAnimationGroups = allocatedAnimationGroups + 1
    end
    if glowOK and glowGroup then
        allocatedAnimationGroups = allocatedAnimationGroups + 1
    end
    if not fadeOK
        or not glowOK
        or not ConfigureAnimationGroup(fadeGroup, { 0.22, 0.18, 1 }, { 0.08, 1, 1 })
        or not ConfigureAnimationGroup(glowGroup, { 0.12, 0, 0.85 }, { 0.52, 0.85, 0 })
    then
        return nil, "appearance-animation-configure-failed"
    end

    return {
        background = background,
        top = top,
        bottom = bottom,
        left = left,
        right = right,
        underline = underline,
        block = block,
        glow = glow,
        fadeGroup = fadeGroup,
        glowGroup = glowGroup,
        textures = textures,
    }
end

local function AllocateTabArt(targets)
    local tab = targets.tab
    local underline, reason = CreateTexture(tab, "ARTWORK", 1)
    if not underline then return nil, reason end
    local block = CreateTexture(tab, "BACKGROUND", 1)
    if not block then return nil, "appearance-tab-art-create-incomplete" end
    if not ConfigureFlatTexture(underline)
        or not ConfigureFlatTexture(block)
        or not CallMethod(underline, "Hide")
        or not CallMethod(block, "Hide")
    then
        return nil, "appearance-tab-art-configure-failed"
    end
    return {
        underline = underline,
        block = block,
        textures = { underline, block },
    }
end

local function StopAnimation(state)
    local group = state and state.activeAnimation
    if not group then return true end
    if not CallMethod(group, "Stop") then
        OnAnimationStopped(group)
        return false
    end
    OnAnimationStopped(group)
    return true
end

local function SetRegionAlpha(snapshot, hidden, cancelNativeFade)
    for index = 1, #snapshot do
        local entry = snapshot[index]
        local alpha = hidden and 0 or entry.alpha
        local allowed = Adapter:CanCallProtected(entry.region)
        if allowed ~= true then return false end
        if hidden
            and cancelNativeFade
            and not pcall(UIFrameFadeRemoveFrame, entry.region)
        then
            return false
        end
        if not CallMethod(entry.region, "SetAlpha", alpha) then
            return false
        end
    end
    return true
end

local function SetFrameRegionsSuppressed(snapshot, suppressed)
    if type(snapshot) ~= "table" then return false end
    for index = 1, #snapshot do
        local entry = snapshot[index]
        local region = entry.region
        if Adapter:CanCallProtected(region) ~= true then return false end
        if suppressed then
            if not pcall(UIFrameFadeRemoveFrame, region)
                or not CallMethod(region, "SetAlpha", 0)
                or not CallMethod(region, "Hide")
            then
                return false
            end
        else
            if not CallMethod(region, "SetAlpha", entry.alpha)
                or not CallMethod(region, entry.shown and "Show" or "Hide")
            then
                return false
            end
        end
    end
    return true
end

GetManagedFrameVisibility = function(state)
    local visibility = 1
    local elementFade = YChat.ElementFade
    if elementFade
        and type(elementFade.GetFrameVisibility) == "function"
    then
        visibility = elementFade:GetFrameVisibility(state.frame)
    elseif elementFade
        and type(elementFade.IsFrameHidden) == "function"
        and elementFade:IsFrameHidden(state.frame) == true
    then
        visibility = 0
    end
    if not IsSafeValue(visibility) or not IsFiniteNumber(visibility) then
        return nil
    end
    if visibility < 0 then return 0 end
    if visibility > 1 then return 1 end
    return visibility
end

SetManagedTabTextAlpha = function(state, visibility)
    if not state or state.frame ~= _G.ChatFrame2 then return true end
    local tabText = state.targets and state.targets.tabText
    local snapshot = state.snapshot
    local baseAlpha = snapshot and snapshot.tabTextAlpha
    visibility = visibility == nil and GetManagedFrameVisibility(state) or visibility
    if not tabText
        or not IsSafeValue(baseAlpha)
        or not IsFiniteNumber(baseAlpha)
        or not IsSafeValue(visibility)
        or not IsFiniteNumber(visibility)
        or Adapter:CanCallProtected(tabText) ~= true
        or type(tabText.SetIgnoreParentAlpha) ~= "function"
    then
        return false
    end
    local ignoresParentAlpha = false
    if type(tabText.IsIgnoringParentAlpha) == "function" then
        local ignoreOK, value = pcall(tabText.IsIgnoringParentAlpha, tabText)
        if not ignoreOK or not IsSafeValue(value) or type(value) ~= "boolean" then
            return false
        end
        ignoresParentAlpha = value
    end
    local desiredAlpha = baseAlpha * visibility
    local currentAlpha = ReadAlpha(tabText)
    if ignoresParentAlpha and NearlyEqual(currentAlpha, desiredAlpha) then
        return true
    end
    state.settingTabTextAlpha = true
    local ok = ignoresParentAlpha
        or CallMethod(tabText, "SetIgnoreParentAlpha", true)
    if ok and not NearlyEqual(currentAlpha, desiredAlpha) then
        ok = CallMethod(tabText, "SetAlpha", desiredAlpha)
    end
    state.settingTabTextAlpha = false
    return ok
end

SetManagedTabAlpha = function(state, alpha, cancelNativeFade)
    local tab = state and state.targets and state.targets.tab
    if not tab
        or not IsSafeValue(alpha)
        or not IsFiniteNumber(alpha)
        or Adapter:CanCallProtected(tab) ~= true
    then
        return false
    end
    local visibility = GetManagedFrameVisibility(state)
    if visibility == nil then return false end
    alpha = alpha * visibility
    if cancelNativeFade and not pcall(UIFrameFadeRemoveFrame, tab) then return false end
    local currentAlpha = ReadAlpha(tab)
    if currentAlpha == nil then return false end
    local ok = true
    if not NearlyEqual(currentAlpha, alpha) then
        state.settingTabAlpha = true
        ok = CallMethod(tab, "SetAlpha", alpha)
        state.settingTabAlpha = false
    end
    if ok then ok = SetManagedTabTextAlpha(state, visibility) end
    return ok
end

local function ApplyTabTextEffect(tabText, effect, fontSize)
    if Adapter:CanCallProtected(tabText) ~= true then return false end
    local fontOK, fontFile = pcall(tabText.GetFont, tabText)
    if not fontOK
        or not IsSafeValue(fontFile)
        or type(fontFile) ~= "string"
        or fontFile == ""
        or not IsSafeValue(fontSize)
        or not IsFiniteNumber(fontSize)
    then
        return false
    end
    local outline = effect == "outline" or effect == "outlineShadow"
    local thick = effect == "thick"
    local shadow = effect == "shadow" or effect == "outlineShadow"
    local flags = thick and "THICKOUTLINE" or (outline and "OUTLINE" or "")
    return CallMethod(tabText, "SetFont", fontFile, fontSize, flags)
        and CallMethod(tabText, "SetShadowColor", 0, 0, 0, shadow and 1 or 0)
        and CallMethod(tabText, "SetShadowOffset", shadow and 1 or 0, shadow and -1 or 0)
end

local function RestoreTabTextPoints(tabText, points)
    if type(points) ~= "table" or not CallMethod(tabText, "ClearAllPoints") then
        return false
    end
    for index = 1, #points do
        local point = points[index]
        if not CallMethod(
            tabText,
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

local function NormalizeTabTextAnchor(tab, tabText, nativePoints)
    if Adapter:CanCallProtected(tab) ~= true
        or Adapter:CanCallProtected(tabText) ~= true
        or not CallMethod(tabText, "ClearAllPoints")
    then
        return false
    end
    if CallMethod(
        tabText,
        "SetPoint",
        "CENTER",
        tab,
        "CENTER",
        0,
        -GetPixelSize(tabText, 6, 1)
    ) then
        return true
    end
    RestoreTabTextPoints(tabText, nativePoints)
    return false
end

local function TryApplyTabTypography(state, effect, fontSize, tabWidth)
    if state
        and state.tabTypographyPending == true
        and state.tabTypographyAttemptGeneration == tabScanGeneration
    then
        return false
    end
    if state then state.tabTypographyAttemptGeneration = tabScanGeneration end
    local tabText = state and state.targets and state.targets.tabText
    if not tabText or Adapter:CanCallProtected(tabText) ~= true then
        if state then state.tabTypographyPending = true end
        return false
    end
    local fontOK, oldFile, oldHeight, oldFlags = pcall(tabText.GetFont, tabText)
    local colorOK, oldR, oldG, oldB, oldA = pcall(tabText.GetShadowColor, tabText)
    local offsetOK, oldX, oldY = pcall(tabText.GetShadowOffset, tabText)
    if not fontOK
        or not colorOK
        or not offsetOK
        or type(oldFile) ~= "string"
        or oldFile == ""
        or not IsSafeValue(oldHeight)
        or not IsFiniteNumber(oldHeight)
        or (oldFlags ~= nil
            and (not IsSafeValue(oldFlags) or type(oldFlags) ~= "string"))
        or not IsSafeValue(oldR)
        or not IsSafeValue(oldG)
        or not IsSafeValue(oldB)
        or not IsSafeValue(oldA)
        or not IsSafeValue(oldX)
        or not IsSafeValue(oldY)
    then
        state.tabTypographyPending = true
        return false
    end

    local applied = ApplyTabTextEffect(tabText, effect, fontSize)
        and Adapter:ReconcileAppearanceTabWidth(state.frame, tabWidth) == true
        and NormalizeTabTextAnchor(
            state.targets.tab,
            tabText,
            state.snapshot.tabTextPoints
        )
    if not applied then
        CallMethod(tabText, "SetFont", oldFile, oldHeight, oldFlags or "")
        CallMethod(tabText, "SetShadowColor", oldR, oldG, oldB, oldA)
        CallMethod(tabText, "SetShadowOffset", oldX, oldY)
        state.tabTypographyPending = true
        return false
    end
    state.tabTypographyPending = false
    return true
end

local function RestoreTabPresentation(state)
    local snapshot = state and state.snapshot
    local targets = state and state.targets
    if not snapshot or not targets then return false end
    local tabText = targets.tabText
    local font = snapshot.tabFont
    local shadowColor = snapshot.tabShadowColor
    local shadowOffset = snapshot.tabShadowOffset
    local pushedOffset = snapshot.tabPushedTextOffset
    local color = snapshot.tabTextColor
    local restored = SetManagedTabAlpha(state, snapshot.tabAlpha, true)
        and Adapter:CanCallProtected(targets.tab) == true
        and CallMethod(
            targets.tab,
            "SetPushedTextOffset",
            pushedOffset[1],
            pushedOffset[2]
        )
        and Adapter:CanCallProtected(tabText) == true
        and CallMethod(tabText, "SetFont", font[1], font[2], font[3])
        and CallMethod(
            tabText,
            "SetShadowColor",
            shadowColor[1],
            shadowColor[2],
            shadowColor[3],
            shadowColor[4]
        )
        and CallMethod(tabText, "SetShadowOffset", shadowOffset[1], shadowOffset[2])
        and CallMethod(tabText, "SetTextColor", color[1], color[2], color[3], color[4])
    if not restored then return false end
    state.settingTabTextAlpha = true
    restored = CallMethod(tabText, "SetAlpha", snapshot.tabTextAlpha or 1)
    state.settingTabTextAlpha = false
    restored = restored and (snapshot.tabTextIgnoresParentAlpha == nil
            or CallMethod(
                tabText,
                "SetIgnoreParentAlpha",
                snapshot.tabTextIgnoresParentAlpha
            ))
    if not restored then return false end
    if not RestoreTabTextPoints(tabText, snapshot.tabTextPoints) then return false end
    Adapter:ReconcileAppearanceTabWidth(state.frame)
    return true
end

local function SetTabRegionsSuppressed(snapshot, suppressed)
    for index = 1, #snapshot do
        local entry = snapshot[index]
        local region = entry.region
        if Adapter:CanCallProtected(region) ~= true then return false end
        if suppressed then
            local currentAlpha = ReadAlpha(region)
            if currentAlpha == nil then return false end
            local textureOK, texture = pcall(region.GetTexture, region)
            if not textureOK then return false end
            if texture ~= nil
                and (not IsSafeValue(texture)
                    or (type(texture) ~= "string"
                        and (not IsFiniteNumber(texture) or floor(texture) ~= texture)))
            then
                return false
            end
            local atlas
            if type(region.GetAtlas) == "function" then
                local atlasOK
                atlasOK, atlas = pcall(region.GetAtlas, region)
                if not atlasOK
                    or (atlas ~= nil
                        and (not IsSafeValue(atlas) or type(atlas) ~= "string"))
                then
                    return false
                end
                if atlas == "" then atlas = nil end
            end
            if atlas ~= nil then
                entry.atlas = atlas
                entry.texture = texture
            elseif texture ~= nil then
                entry.atlas = nil
                entry.texture = texture
            end
            if texture ~= nil or atlas ~= nil then
                if not CallMethod(region, "SetTexture", nil)
                    or not CallMethod(region, "SetColorTexture", 0, 0, 0, 0)
                then
                    return false
                end
            end
            if not NearlyEqual(currentAlpha, 0)
                and not CallMethod(region, "SetAlpha", 0)
            then
                return false
            end
        elseif entry.atlas ~= nil and entry.atlas ~= "" then
            if type(region.SetAtlas) ~= "function"
                or not CallMethod(region, "SetAtlas", entry.atlas)
            then
                return false
            end
        else
            if not CallMethod(region, "SetTexture", entry.texture) then
                return false
            end
        end
        if not suppressed and not CallMethod(region, "SetAlpha", entry.alpha) then
            return false
        end
    end
    return true
end

local function HideArt(art)
    if not art then return true end
    local ok = true
    for index = 1, #art.textures do
        if not CallMethod(art.textures[index], "Hide") then ok = false end
    end
    return ok
end

local function HideFrameArt(art)
    if not art then return true end
    return CallMethod(art.background, "Hide")
        and CallMethod(art.top, "Hide")
        and CallMethod(art.bottom, "Hide")
        and CallMethod(art.left, "Hide")
        and CallMethod(art.right, "Hide")
end

local function HideTabArt(state)
    if not state or not state.art then return true end
    StopAnimation(state)
    local art = state.art
    local ok = CallMethod(art.underline, "Hide")
        and CallMethod(art.block, "Hide")
    if art.glow then ok = CallMethod(art.glow, "Hide") and ok end
    return ok
end

local function RestoreEditBox(editBox, points, height, justifyV, languageButton, languageHeight)
    local allowed = Adapter:CanCallProtected(editBox)
    if allowed ~= true
        or not CallMethod(editBox, "SetHeight", height)
        or not CallMethod(editBox, "ClearAllPoints")
    then
        return false
    end
    for index = 1, #points do
        local point = points[index]
        if not CallMethod(
            editBox,
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
    if justifyV ~= nil and not CallMethod(editBox, "SetJustifyV", justifyV) then
        return false
    end
    if languageHeight ~= nil
        and languageButton
        and not CallMethod(languageButton, "SetHeight", languageHeight)
    then
        return false
    end
    return true
end

local function SetButtonObjects(snapshot, hidden)
    for index = 1, #snapshot do
        local entry = snapshot[index]
        local button = entry.button
        if Adapter:CanCallProtected(button) ~= true then return false end
        if hidden then
            if entry.enabled ~= nil and type(button.Disable) == "function"
                and not CallMethod(button, "Disable")
            then
                return false
            end
            if not CallMethod(button, "EnableMouse", false)
                or not CallMethod(button, "SetAlpha", 0)
                or not CallMethod(button, "Hide")
            then
                return false
            end
        else
            if entry.enabled ~= nil then
                local method = entry.enabled and "Enable" or "Disable"
                if type(button[method]) ~= "function"
                    or not CallMethod(button, method)
                then
                    return false
                end
            end
            if not CallMethod(button, "EnableMouse", entry.mouse)
                or not CallMethod(button, "SetAlpha", entry.alpha)
                or not CallMethod(button, entry.shown and "Show" or "Hide")
            then
                return false
            end
        end
    end
    return true
end

local function InstallButtonMethodHooks(button)
    if buttonMethodHooks[button] == true or type(hooksecurefunc) ~= "function" then
        return true
    end
    for index = 1, #NATIVE_BUTTON_MUTATION_METHODS do
        local methodName = NATIVE_BUTTON_MUTATION_METHODS[index]
        if type(button[methodName]) == "function" then
            local installed = pcall(
                hooksecurefunc,
                button,
                methodName,
                NativeManagedButtonMutated
            )
            if not installed then
                Appearance.lastOptionalButtonHookFailure = methodName
            end
        end
    end
    buttonMethodHooks[button] = true
    return true
end

local function InstallButtonHooks(state, snapshot, domain)
    snapshot = snapshot or state.snapshot.buttonObjects
    domain = domain or DOMAIN_BUTTONS
    for index = 1, #snapshot do
        local button = snapshot[index].button
        buttonOwners[button] = state
        buttonDomains[button] = domain
        if buttonHooks[button] ~= true then
            if type(button.HookScript) ~= "function"
                or not CallMethod(button, "HookScript", "OnShow", NativeButtonShown)
            then
                return false
            end
            buttonHooks[button] = true
        end
        if not InstallButtonMethodHooks(button) then return false end
    end
    return true
end

local function InstallTabAlphaHook(tab)
    if tabAlphaHooks[tab] == true then return true end
    if type(tab) ~= "table" and type(tab) ~= "userdata" then return false end
    if type(tab.SetAlpha) ~= "function" or type(hooksecurefunc) ~= "function" then
        return false
    end
    local installed = pcall(hooksecurefunc, tab, "SetAlpha", NativeTabAlphaChanged)
    if not installed then return false end
    tabAlphaHooks[tab] = true
    return true
end

local function InstallTabTextAlphaHook(tabText)
    if tabTextAlphaHooks[tabText] == true then return true end
    if type(tabText) ~= "table" and type(tabText) ~= "userdata" then return false end
    if type(tabText.SetAlpha) ~= "function" or type(hooksecurefunc) ~= "function" then
        return false
    end
    local installed = pcall(
        hooksecurefunc,
        tabText,
        "SetAlpha",
        NativeTabTextAlphaChanged
    )
    if not installed then return false end
    tabTextAlphaHooks[tabText] = true
    return true
end

local function BindTabTextAlphaOwner(state)
    if not state or state.frame ~= _G.ChatFrame2 then return true end
    local tabText = state.targets and state.targets.tabText
    if not tabText then return false end
    tabTextOwners[tabText] = state
    if InstallTabTextAlphaHook(tabText) then return true end
    if tabTextOwners[tabText] == state then tabTextOwners[tabText] = nil end
    return false
end

local function ClearTabTextAlphaOwner(state)
    local tabText = state and state.targets and state.targets.tabText
    if tabText and tabTextOwners[tabText] == state then
        tabTextOwners[tabText] = nil
    end
end

local function ManagedTabMouseDown(tab, button)
    if button == "LeftButton" and UpdateManagedTabPressedVisual then
        UpdateManagedTabPressedVisual(tab, true)
    end
end

local function ManagedTabMouseUp(tab, button)
    if button == "LeftButton" and UpdateManagedTabPressedVisual then
        UpdateManagedTabPressedVisual(tab, false)
    end
end

local function ManagedTabMouseLeave(tab)
    if UpdateManagedTabPressedVisual then
        UpdateManagedTabPressedVisual(tab, false)
    end
end

local function ManagedTabHidden(tab)
    local state = tabStates[tab]
    if state and state.pressed == true and UpdateManagedTabPressedVisual then
        UpdateManagedTabPressedVisual(tab, false)
    end
    if state then state.pressed = false end
end

local function InstallTabPressHooks(tab)
    if tabPressHooks[tab] == true then return true end
    if type(tab.HookScript) ~= "function"
        or not CallMethod(tab, "HookScript", "OnMouseDown", ManagedTabMouseDown)
        or not CallMethod(tab, "HookScript", "OnMouseUp", ManagedTabMouseUp)
        or not CallMethod(tab, "HookScript", "OnLeave", ManagedTabMouseLeave)
        or not CallMethod(tab, "HookScript", "OnHide", ManagedTabHidden)
    then
        return false
    end
    tabPressHooks[tab] = true
    return true
end

local lateButtonState

local function RegisterLateGlobalButton(button)
    local state = lateButtonState
    if not state or buttonOwners[button] == state then return end
    if buttonOwners[button] ~= nil then
        state.lateButtonReason = "appearance-global-button-owner-mismatch"
        return
    end
    local captured, captureReason = CaptureButtonObjects({ button })
    if not captured then
        state.lateButtonReason =
            captureReason or "appearance-global-button-capture-failed"
        return
    end
    buttonOwners[button] = state
    buttonDomains[button] = DOMAIN_BUTTONS
    if buttonHooks[button] ~= true then
        if type(button.HookScript) ~= "function"
            or not CallMethod(button, "HookScript", "OnShow", NativeButtonShown)
        then
            buttonOwners[button] = nil
            state.lateButtonReason = "appearance-global-button-hook-failed"
            return
        end
        buttonHooks[button] = true
    end
    if not InstallButtonMethodHooks(button) then
        buttonOwners[button] = nil
        buttonDomains[button] = nil
        state.lateButtonReason = "appearance-global-button-method-hook-failed"
        return
    end
    local snapshot = state.snapshot.buttonObjects
    snapshot[#snapshot + 1] = captured[1]
    if state.hideNativeButtons == true
        and CanSuppressNativeMutation(state)
        and not SetButtonObjects(captured, true)
    then
        state.lateButtonReason = "appearance-global-button-suppress-failed"
        HandleNativeMutationFailure(
            state,
            state.lateButtonReason,
            DOMAIN_BUTTONS
        )
    end
end

ReconcileLateGlobalButtons = function(state)
    if not state
        or state.frame ~= _G.ChatFrame1
        or not IsVisualMutationAllowed()
        or type(Adapter.ForEachGlobalChatButton) ~= "function"
    then
        return true
    end
    state.lateButtonReason = nil
    lateButtonState = state
    Adapter:ForEachGlobalChatButton(RegisterLateGlobalButton)
    lateButtonState = nil
    return state.lateButtonReason == nil, state.lateButtonReason
end

local function RestoreState(state)
    if not state then return true end
    if state.applied ~= true and state.restorePending ~= true then
        StopAnimation(state)
        return true
    end
    state.applied = false
    state.pressed = false
    state.restorePending = true
    StopAnimation(state)
    local snapshot = state.snapshot
    local targets = state.targets
    local ok = HideArt(state.art)
    ok = SetFrameRegionsSuppressed(snapshot.frameRegions, false) and ok
    ok = SetTabRegionsSuppressed(snapshot.tabRegions, false) and ok
    ok = SetRegionAlpha(snapshot.buttonRegions, false, false) and ok
    ok = SetButtonObjects(snapshot.buttonObjects, false) and ok
    ok = SetButtonObjects(snapshot.scrollObjects or EMPTY_BUTTONS, false) and ok
    ok = RestoreTabPresentation(state) and ok
    if targets.editBox and snapshot.editBoxPoints then
        ok = RestoreEditBox(
            targets.editBox,
            snapshot.editBoxPoints,
            snapshot.editBoxHeight,
            snapshot.editBoxJustifyV,
            targets.inputLanguageButton,
            snapshot.inputLanguageButtonHeight
        ) and ok
    end
    state.restorePending = not ok
    return ok
end

local function RestoreTabState(state)
    if not state then return true end
    if state.applied ~= true and state.restorePending ~= true then
        return true
    end
    state.applied = false
    state.pressed = false
    state.restorePending = true
    local snapshot = state.snapshot
    local targets = state.targets
    local ok = HideArt(state.art)
    ok = SetTabRegionsSuppressed(snapshot.tabRegions, false) and ok
    ok = RestoreTabPresentation(state) and ok
    state.restorePending = not ok
    return ok
end

local function GetTabColor(appearance)
    if appearance.classColorTabs == true
        and UnitAPI
        and type(UnitAPI.GetUnitClassColor) == "function"
    then
        local ok, color = pcall(UnitAPI.GetUnitClassColor, "player")
        if ok and type(color) == "table" then
            local r = color.r
            local g = color.g
            local b = color.b
            if IsSafeValue(r)
                and IsSafeValue(g)
                and IsSafeValue(b)
                and IsFiniteNumber(r)
                and IsFiniteNumber(g)
                and IsFiniteNumber(b)
            then
                return r, g, b
            end
        end
    end
    local color = appearance.tabColor
    return color[1], color[2], color[3]
end

local function GetBorderColor(appearance)
    local color = appearance.borderColor
    if appearance.classColorBorder == true
        and UnitAPI
        and type(UnitAPI.GetUnitClassColor) == "function"
    then
        local ok, classColor = pcall(UnitAPI.GetUnitClassColor, "player")
        if ok and type(classColor) == "table" then
            local r = classColor.r
            local g = classColor.g
            local b = classColor.b
            if IsSafeValue(r)
                and IsSafeValue(g)
                and IsSafeValue(b)
            then
                return r, g, b, color[4]
            end
        end
    end
    return color[1], color[2], color[3], color[4]
end

function Appearance:ResolveBorderColor(appearance)
    if type(appearance) ~= "table" or type(appearance.borderColor) ~= "table" then
        return nil
    end
    return GetBorderColor(appearance)
end

local function GetTypographyTabWidth(appearance)
    if appearance.tabWidthMode == "fixed" then return appearance.tabWidth end
    return nil
end

local function ResolveTabSlotWidth(state, appearance)
    if appearance.tabWidthMode == "fixed" then return appearance.tabWidth end
    if type(Adapter.ReadAppearanceTabWidth) ~= "function" then return nil end
    return Adapter:ReadAppearanceTabWidth(state.targets.tab)
end

local function GetInputHorizontalOffsets(targets)
    local editBox = targets.editBox
    local inset = GetPixelSize(editBox, INPUT_ART_INSET_PIXELS, 1)
    local right = inset
    if targets.inputLanguageButton then
        local overhang = Adapter:ReadInputLanguageButtonOverhang(
            targets.frame,
            editBox,
            targets.inputLanguageButton
        )
        if IsFiniteNumber(overhang) then right = inset - overhang end
    end
    return -inset, right
end

local function GetBottomInputOffset(targets)
    return GetPixelSize(targets.editBox, INPUT_ART_INSET_PIXELS, 1)
end

local function ApplyInputPosition(targets, position, height)
    local editBox = targets.editBox
    local frame = targets.frame
    local horizontalAnchor = targets.background or frame
    if not editBox then return true end
    local leftOffset, rightOffset = GetInputHorizontalOffsets(targets)
    local bottomOffset = GetBottomInputOffset(targets)
    local allowed = Adapter:CanCallProtected(editBox)
    if allowed ~= true
        or not CallMethod(editBox, "SetHeight", height)
        or (type(editBox.SetJustifyV) == "function"
            and not CallMethod(editBox, "SetJustifyV", "MIDDLE"))
        or not CallMethod(editBox, "ClearAllPoints")
    then
        return false
    end
    if position == "top" then
        if not CallMethod(
            editBox,
            "SetPoint",
            "BOTTOMLEFT",
            horizontalAnchor,
            "TOPLEFT",
            leftOffset,
            TOP_INPUT_OFFSET
        ) then
            return false
        end
    elseif not CallMethod(
        editBox,
        "SetPoint",
        "TOPLEFT",
        horizontalAnchor,
        "BOTTOMLEFT",
        leftOffset,
        bottomOffset
    ) then
        return false
    end
    local anchored = CallMethod(
        editBox,
        "SetPoint",
        "RIGHT",
        horizontalAnchor,
        "RIGHT",
        rightOffset,
        0
    )
    if not anchored then return false end
    local languageButton = targets.inputLanguageButton
    if languageButton and type(languageButton.SetHeight) == "function" then
        return CallMethod(languageButton, "SetHeight", height)
    end
    return true
end

local function InputPositionMatches(targets, position, height)
    local editBox = targets.editBox
    local frame = targets.frame
    local horizontalAnchor = targets.background or frame
    if not editBox then return true end
    local leftOffset, rightOffset = GetInputHorizontalOffsets(targets)
    local bottomOffset = GetBottomInputOffset(targets)
    local heightOK, actualHeight = pcall(editBox.GetHeight, editBox)
    if not heightOK or not IsSafeValue(actualHeight)
        or not IsFiniteNumber(actualHeight)
        or abs(actualHeight - height) > 0.01
    then
        return false
    end
    if type(editBox.GetJustifyV) == "function" then
        local justifyOK, justifyV = pcall(editBox.GetJustifyV, editBox)
        if not justifyOK or not IsSafeValue(justifyV) or justifyV ~= "MIDDLE" then
            return false
        end
    end
    local languageButton = targets.inputLanguageButton
    if languageButton and type(languageButton.GetHeight) == "function" then
        local languageOK, languageHeight = pcall(languageButton.GetHeight, languageButton)
        if not languageOK or not IsSafeValue(languageHeight)
            or not IsFiniteNumber(languageHeight)
            or abs(languageHeight - height) > 0.01
        then
            return false
        end
    end
    local countOK, count = pcall(editBox.GetNumPoints, editBox)
    if not countOK or not IsSafeValue(count) or count ~= 2 then return false end

    local firstOK, point, relativeTo, relativePoint, x, y =
        pcall(editBox.GetPoint, editBox, 1)
    if not firstOK
        or not IsSafeValue(point)
        or not IsSafeValue(relativeTo)
        or not IsSafeValue(relativePoint)
        or not IsSafeValue(x)
        or not IsSafeValue(y)
        or relativeTo ~= horizontalAnchor
    then
        return false
    end
    if position == "top" then
        if point ~= "BOTTOMLEFT"
            or relativePoint ~= "TOPLEFT"
            or x ~= leftOffset
            or y ~= TOP_INPUT_OFFSET
        then
            return false
        end
    elseif point ~= "TOPLEFT"
        or relativePoint ~= "BOTTOMLEFT"
        or x ~= leftOffset
        or y ~= bottomOffset
    then
        return false
    end

    local secondOK, secondPoint, secondRelativeTo, secondRelativePoint, secondX, secondY =
        pcall(editBox.GetPoint, editBox, 2)
    return secondOK
        and IsSafeValue(secondPoint)
        and IsSafeValue(secondRelativeTo)
        and IsSafeValue(secondRelativePoint)
        and IsSafeValue(secondX)
        and IsSafeValue(secondY)
        and secondPoint == "RIGHT"
        and secondRelativeTo == horizontalAnchor
        and secondRelativePoint == "RIGHT"
        and secondX == rightOffset
        and secondY == 0
end

local function SkinCacheMatches(
    state,
    appearance,
    r,
    g,
    b,
    borderR,
    borderG,
    borderB,
    borderA,
    tabSlotWidth
)
    local cache = state.cache
    local backgroundColor = appearance.backgroundColor
    return cache
        and cache.backgroundAlpha == appearance.backgroundAlpha
        and cache.backgroundR == backgroundColor[1]
        and cache.backgroundG == backgroundColor[2]
        and cache.backgroundB == backgroundColor[3]
        and cache.backgroundA == backgroundColor[4]
        and cache.borderStyle == appearance.borderStyle
        and cache.borderWidth == appearance.borderWidth
        and cache.borderPixelSize == GetPixelSize(
            state.targets.background,
            appearance.borderWidth or 1,
            1
        )
        and cache.underlineThickness == GetPixelSize(
            state.targets.tabText,
            2,
            1
        )
        and cache.borderR == borderR
        and cache.borderG == borderG
        and cache.borderB == borderB
        and cache.borderA == borderA
        and cache.tabStyle == appearance.tabStyle
        and cache.tabWidthMode == appearance.tabWidthMode
        and cache.tabSlotWidth == tabSlotWidth
        and cache.classColorTabs == appearance.classColorTabs
        and cache.classColorBorder == appearance.classColorBorder
        and cache.hideNativeButtons == appearance.hideNativeButtons
        and cache.inputPosition == appearance.inputPosition
        and cache.inputHeight == appearance.inputHeight
        and cache.r == r
        and cache.g == g
        and cache.b == b
end

local function UpdateCache(
    state,
    appearance,
    r,
    g,
    b,
    borderR,
    borderG,
    borderB,
    borderA,
    tabSlotWidth
)
    local cache = state.cache or {}
    state.cache = cache
    local backgroundColor = appearance.backgroundColor
    cache.backgroundAlpha = appearance.backgroundAlpha
    cache.backgroundR = backgroundColor[1]
    cache.backgroundG = backgroundColor[2]
    cache.backgroundB = backgroundColor[3]
    cache.backgroundA = backgroundColor[4]
    cache.borderStyle = appearance.borderStyle
    cache.borderWidth = appearance.borderWidth
    cache.borderPixelSize = GetPixelSize(
        state.targets.background,
        appearance.borderWidth or 1,
        1
    )
    cache.underlineThickness = GetPixelSize(state.targets.tabText, 2, 1)
    cache.borderR = borderR
    cache.borderG = borderG
    cache.borderB = borderB
    cache.borderA = borderA
    cache.tabStyle = appearance.tabStyle
    cache.tabTextEffect = appearance.tabTextEffect
    cache.tabFontSize = appearance.tabFontSize
    cache.tabWidth = appearance.tabWidth
    cache.tabWidthMode = appearance.tabWidthMode
    cache.tabSlotWidth = tabSlotWidth
    cache.tabTypographyWidth = GetTypographyTabWidth(appearance)
    cache.classColorTabs = appearance.classColorTabs
    cache.classColorBorder = appearance.classColorBorder
    cache.hideNativeButtons = appearance.hideNativeButtons
    cache.inputPosition = appearance.inputPosition
    cache.inputHeight = appearance.inputHeight
    cache.messageEffect = appearance.messageEffect
    cache.r = r
    cache.g = g
    cache.b = b
end

CanSuppressNativeMutation = function(state)
    return Appearance.enabled == true
        and state
        and state.applied == true
        and state.restorePending ~= true
        and Appearance.mutationPaused ~= true
        and IsVisualMutationAllowed()
end

SuppressFrameDomain = function(state)
    if not CanSuppressNativeMutation(state) then return true end
    if not SetFrameRegionsSuppressed(state.snapshot.frameRegions, true) then
        return false, "appearance-native-frame-suppress-failed"
    end
    return true
end

SuppressButtonDomain = function(state)
    if not CanSuppressNativeMutation(state)
        or state.hideNativeButtons ~= true
    then
        return true
    end
    if not SetRegionAlpha(state.snapshot.buttonRegions, true, true)
        or not SetButtonObjects(state.snapshot.buttonObjects, true)
    then
        return false, "appearance-native-button-suppress-failed"
    end
    return true
end

SuppressScrollDomain = function(state)
    if not CanSuppressNativeMutation(state)
        or state.hideNativeButtons ~= true
    then
        return true
    end
    if not SetButtonObjects(state.snapshot.scrollObjects or EMPTY_BUTTONS, true) then
        return false, "appearance-native-scroll-suppress-failed"
    end
    return true
end

SuppressNativeFrameVisuals = function(state)
    if not CanSuppressNativeMutation(state) then return true end
    local ok, reason = SuppressFrameDomain(state)
    if not ok then return false, reason, DOMAIN_FRAME end
    ok, reason = SuppressButtonDomain(state)
    if not ok then return false, reason, DOMAIN_BUTTONS end
    ok, reason = SuppressScrollDomain(state)
    if not ok then return false, reason, DOMAIN_SCROLL end
    return true
end

UpdateNativeWindowAlpha = function(state, alpha)
    if not Appearance.enabled
        or not state
        or state.applied ~= true
        or state.restorePending == true
    then
        return true
    end
    if not IsSafeValue(alpha) or not IsFiniteNumber(alpha) then
        return false, "appearance-native-alpha-invalid"
    end
    local frameRegions = state.snapshot.frameRegions
    local buttonRegions = state.snapshot.buttonRegions
    for index = 1, #frameRegions do
        frameRegions[index].alpha = alpha
    end
    local windowRegionCount = state.targets.buttonWindowRegionCount or 0
    if windowRegionCount > #buttonRegions then
        windowRegionCount = #buttonRegions
    end
    for index = 1, windowRegionCount do
        buttonRegions[index].alpha = alpha
    end
    return true
end

UpdateNativeTabSnapshot = function(state)
    local snapshot = state and state.snapshot
    local tabText = state and state.targets and state.targets.tabText
    if not snapshot or not tabText then
        return false, "appearance-native-tab-snapshot-unavailable"
    end
    local colorOK, r, g, b, a = pcall(tabText.GetTextColor, tabText)
    if not colorOK
        or not IsSafeValue(r)
        or not IsSafeValue(g)
        or not IsSafeValue(b)
        or not IsSafeValue(a)
        or not IsFiniteNumber(r)
        or not IsFiniteNumber(g)
        or not IsFiniteNumber(b)
        or not IsFiniteNumber(a)
    then
        return false, "appearance-native-tab-color-capture-failed"
    end
    local cache = state.cache
    if not cache
        or not NearlyEqual(r, cache.r)
        or not NearlyEqual(g, cache.g)
        or not NearlyEqual(b, cache.b)
        or not NearlyEqual(a, 1)
    then
        snapshot.tabTextColor[1] = r
        snapshot.tabTextColor[2] = g
        snapshot.tabTextColor[3] = b
        snapshot.tabTextColor[4] = a
    end
    return true
end

local function ApplyTabArt(
    state,
    tabStyle,
    textEffect,
    tabWidth,
    selected,
    r,
    g,
    b
)
    if type(selected) ~= "boolean" or not IsSafeValue(selected) then
        return false, "appearance-tab-selection-unsafe"
    end
    local art = state and state.art
    if not art or not art.underline or not art.block then
        return false, "appearance-tab-art-unavailable"
    end
    if not ConfigureTabArtGeometry(
        art,
        state.targets.tabText,
        tabStyle,
        textEffect,
        tabWidth
    ) then
        return false, "appearance-tab-geometry-unavailable"
    end

    local darkUnderline = tabStyle == "darkUnderline"
    local underlineShown = selected
        and (tabStyle == "underline" or darkUnderline)
    local blockShown = selected and tabStyle == "block"
    local blockR, blockG, blockB, blockAlpha = r, g, b, 0.20
    if darkUnderline then
        blockShown = true
        blockR, blockG, blockB = 0, 0, 0
        local targetAlpha = selected and 0.75 or 0.20
        local parentAlpha = selected and 1 or TAB_INACTIVE_ALPHA
        blockAlpha = math.min(1, targetAlpha / parentAlpha)
    end
    local ok = CallMethod(
        art.underline,
        "SetColorTexture",
        r,
        g,
        b,
        0.92
    )
        and CallMethod(art.underline, underlineShown and "Show" or "Hide")
        and CallMethod(
            art.block,
            "SetColorTexture",
            blockR,
            blockG,
            blockB,
            blockAlpha
        )
        and CallMethod(art.block, blockShown and "Show" or "Hide")
    if art.glow then
        ok = CallMethod(art.glow, "SetColorTexture", r, g, b, 1) and ok
        if not state.activeAnimation then
            ok = CallMethod(art.glow, "Hide") and ok
        end
    end
    return ok
end

UpdateManagedTabPressedVisual = function(tab, pressed)
    local state = tabStates[tab]
    if not state
        or state.applied ~= true
        or state.inactive == true
        or not state.cache
        or not CanSuppressNativeMutation(state)
    then
        return
    end
    pressed = pressed == true
    if state.pressed == pressed then return end
    local offset = pressed and GetPixelSize(tab, 1, 1) or 0
    if not CallMethod(tab, "SetPushedTextOffset", offset, -offset) then
        HandleNativeMutationFailure(
            state,
            "appearance-tab-press-feedback-failed",
            DOMAIN_TAB
        )
        return
    end
    state.pressed = pressed
end

SyncManagedTabVisuals = function(state, selected)
    if not CanSuppressNativeMutation(state) then return true end
    if type(selected) ~= "boolean" or not IsSafeValue(selected) then
        return false, "appearance-tab-selection-unsafe"
    end
    local cache = state.cache
    local tabText = state.targets.tabText
    if not cache
        or not SetTabRegionsSuppressed(state.snapshot.tabRegions, true)
        or not CallMethod(state.targets.tab, "SetPushedTextOffset", 0, 0)
        or Adapter:CanCallProtected(tabText) ~= true
        or not CallMethod(tabText, "SetTextColor", cache.r, cache.g, cache.b, 1)
        or not SetManagedTabAlpha(
            state,
            selected and 1 or TAB_INACTIVE_ALPHA,
            true
        )
    then
        return false, "appearance-native-tab-reapply-failed"
    end
    TryApplyTabTypography(
        state,
        cache.tabTextEffect,
        cache.tabFontSize,
        cache.tabTypographyWidth
    )
    if selected and state.activeAnimation then StopAnimation(state) end
    if not ApplyTabArt(
        state,
        cache.tabStyle,
        cache.tabTextEffect,
        cache.tabSlotWidth,
        selected,
        cache.r,
        cache.g,
        cache.b
    )
    then
        return false, "appearance-tab-selection-apply-failed"
    end
    state.selected = selected
    return true
end

RepairManagedTabColors = function(state, selected)
    if not CanSuppressNativeMutation(state) then return true end
    if type(selected) ~= "boolean" or not IsSafeValue(selected) then
        return false, "appearance-tab-selection-unsafe"
    end
    local cache = state.cache
    local snapshot = state.snapshot
    local tabText = state.targets and state.targets.tabText
    if not cache
        or not snapshot
        or not tabText
        or not SetTabRegionsSuppressed(snapshot.tabRegions, true)
    then
        return false, "appearance-native-tab-region-repair-failed"
    end

    local colorOK, currentR, currentG, currentB, currentA =
        pcall(tabText.GetTextColor, tabText)
    if not colorOK
        or not IsSafeValue(currentR)
        or not IsSafeValue(currentG)
        or not IsSafeValue(currentB)
        or not IsSafeValue(currentA)
        or not IsFiniteNumber(currentR)
        or not IsFiniteNumber(currentG)
        or not IsFiniteNumber(currentB)
        or not IsFiniteNumber(currentA)
    then
        return false, "appearance-native-tab-color-read-failed"
    end
    if not NearlyEqual(currentR, cache.r)
        or not NearlyEqual(currentG, cache.g)
        or not NearlyEqual(currentB, cache.b)
        or not NearlyEqual(currentA, 1)
    then
        if Adapter:CanCallProtected(tabText) ~= true
            or not CallMethod(tabText, "SetTextColor", cache.r, cache.g, cache.b, 1)
        then
            return false, "appearance-native-tab-color-repair-failed"
        end
    end

    if state.selected == selected then return true end
    if not SetManagedTabAlpha(
        state,
        selected and 1 or TAB_INACTIVE_ALPHA,
        false
    ) then
        return false, "appearance-native-tab-selection-alpha-failed"
    end
    if selected and state.activeAnimation then StopAnimation(state) end
    if not ApplyTabArt(
        state,
        cache.tabStyle,
        cache.tabTextEffect,
        cache.tabSlotWidth,
        selected,
        cache.r,
        cache.g,
        cache.b
    ) then
        return false, "appearance-tab-selection-apply-failed"
    end
    state.selected = selected
    return true
end

HandleNativeMutationFailure = function(state, reason, domain, scheduleRetry)
    domainFailureCount = domainFailureCount + 1
    Appearance.lastMutationFailure = reason or "appearance-native-mutation-failed"
    Appearance.lastMutationDomain = domain or "unknown"
    if scheduleRetry ~= false
        and Appearance.enabled
        and Appearance.mutationPaused ~= true
        and IsVisualMutationAllowed()
    then
        Appearance:ScheduleNativeSettle(
            Appearance.lastMutationFailure,
            domain == DOMAIN_INPUT
        )
    end
    return false, Appearance.lastMutationFailure
end

function Appearance:RefreshOptionalSnapshots(state)
    local snapshot = state.snapshot
    local targets = state.targets
    local controlsChanged = false
    local inputChanged = false

    if state.controlsCapturePending == true then
        local buttonRegions, buttonObjects, scrollObjects, reason =
            self:CaptureOptionalControls(targets)
        if buttonRegions then
            snapshot.buttonRegions = buttonRegions
            snapshot.buttonObjects = buttonObjects
            snapshot.scrollObjects = scrollObjects
            state.controlsCapturePending = false
            state.controlsCaptureReason = nil
            controlsChanged = InstallButtonHooks(state, buttonObjects, DOMAIN_BUTTONS)
                and InstallButtonHooks(state, scrollObjects, DOMAIN_SCROLL)
            if not controlsChanged then
                state.controlsCapturePending = true
                state.controlsCaptureReason = "appearance-button-hook-install-failed"
            end
        else
            state.controlsCaptureReason = reason
        end
    end

    if state.inputCapturePending == true then
        local points, height, justifyV, languageHeight, reason =
            self:CaptureInputPresentation(targets)
        if points then
            snapshot.editBoxPoints = points
            snapshot.editBoxHeight = height
            snapshot.editBoxJustifyV = justifyV
            snapshot.inputLanguageButtonHeight = languageHeight
            state.inputCapturePending = false
            state.inputCaptureReason = nil
            inputChanged = true
        else
            state.inputCaptureReason = reason
        end
    end

    if state.controlsCapturePending or state.inputCapturePending then
        Appearance.mutationRefreshPending = true
        Appearance.lastMutationFailure = state.controlsCaptureReason
            or state.inputCaptureReason
            or "appearance-optional-capability-pending"
        Appearance.lastMutationDomain = state.controlsCapturePending
            and DOMAIN_BUTTONS
            or DOMAIN_INPUT
    else
        Appearance.lastMutationFailure = "none"
        Appearance.lastMutationDomain = "none"
    end
    return inputChanged
end

local function ApplyState(state, appearance, forceLayout)
    if not IsVisualMutationAllowed() then return false, "restriction-not-open" end

    local inputChanged = false
    if state.applied == true
        and (state.controlsCapturePending == true or state.inputCapturePending == true)
    then
        inputChanged = Appearance:RefreshOptionalSnapshots(state)
    end
    forceLayout = forceLayout == true or inputChanged == true

    local selected, selectionReason =
        Adapter:IsAppearanceTabSelected(state.frame)
    if type(selected) ~= "boolean" then
        return false, selectionReason or "appearance-tab-selection-unavailable"
    end
    local r, g, b = GetTabColor(appearance)
    local borderR, borderG, borderB, borderA = GetBorderColor(appearance)
    local tabSlotWidth = ResolveTabSlotWidth(state, appearance)
    if not IsFiniteNumber(tabSlotWidth) or tabSlotWidth <= 0 then
        return false, "appearance-tab-slot-width-unavailable"
    end
    local cacheMatches = state.applied and SkinCacheMatches(
        state,
        appearance,
        r,
        g,
        b,
        borderR,
        borderG,
        borderB,
        borderA,
        tabSlotWidth
    )
    if cacheMatches then
        local effectChanged = state.cache.messageEffect ~= appearance.messageEffect
        if effectChanged then
            StopAnimation(state)
            state.effect = appearance.messageEffect
            state.cache.messageEffect = appearance.messageEffect
        end
        local tabTypographyChanged = state.cache.tabTextEffect ~= appearance.tabTextEffect
            or state.cache.tabFontSize ~= appearance.tabFontSize
            or state.cache.tabWidth ~= appearance.tabWidth
            or state.cache.tabWidthMode ~= appearance.tabWidthMode
            or state.tabTypographyPending == true
        if tabTypographyChanged then
            state.cache.tabTextEffect = appearance.tabTextEffect
            state.cache.tabFontSize = appearance.tabFontSize
            state.cache.tabWidth = appearance.tabWidth
            state.cache.tabWidthMode = appearance.tabWidthMode
            state.cache.tabTypographyWidth = GetTypographyTabWidth(appearance)
            TryApplyTabTypography(
                state,
                appearance.tabTextEffect,
                appearance.tabFontSize,
                state.cache.tabTypographyWidth
            )
        end
        local suppressed, suppressReason, suppressDomain =
            SuppressNativeFrameVisuals(state)
        if not suppressed then
            HandleNativeMutationFailure(
                state,
                suppressReason,
                suppressDomain or DOMAIN_FRAME
            )
        end
        local synced, syncReason = SyncManagedTabVisuals(state, selected)
        if not synced then
            HandleNativeMutationFailure(
                state,
                syncReason or "appearance-native-tab-reapply-failed",
                DOMAIN_TAB
            )
        end
        if not state.snapshot.editBoxPoints
            or not forceLayout
            or InputPositionMatches(
            state.targets,
            appearance.inputPosition,
            appearance.inputHeight
        ) then
            return true, effectChanged or tabTypographyChanged
        end
        if ApplyInputPosition(
            state.targets,
            appearance.inputPosition,
            appearance.inputHeight
        ) then
            return true, true
        end
        RestoreEditBox(
            state.targets.editBox,
            state.snapshot.editBoxPoints,
            state.snapshot.editBoxHeight,
            state.snapshot.editBoxJustifyV,
            state.targets.inputLanguageButton,
            state.snapshot.inputLanguageButtonHeight
        )
        HandleNativeMutationFailure(
            state,
            "appearance-input-reapply-failed",
            DOMAIN_INPUT
        )
        return true, false
    end

    StopAnimation(state)
    local snapshot = state.snapshot
    local targets = state.targets
    local art = state.art
    state.applied = true
    state.restorePending = true
    state.hideNativeButtons = appearance.hideNativeButtons == true
    local ok = SetFrameRegionsSuppressed(snapshot.frameRegions, true)
        and SetTabRegionsSuppressed(snapshot.tabRegions, true)
        and CallMethod(targets.tab, "SetPushedTextOffset", 0, 0)
        and Adapter:CanCallProtected(targets.tabText) == true
        and CallMethod(targets.tabText, "SetTextColor", r, g, b, 1)
        and SetManagedTabAlpha(state, selected and 1 or TAB_INACTIVE_ALPHA, true)
    if not ok then
        RestoreState(state)
        return false, "appearance-native-apply-failed"
    end

    local buttonsOK = SetRegionAlpha(
        snapshot.buttonRegions,
        appearance.hideNativeButtons == true,
        appearance.hideNativeButtons == true
    ) and SetButtonObjects(
        snapshot.buttonObjects,
        appearance.hideNativeButtons == true
    )
    if not buttonsOK then
        HandleNativeMutationFailure(
            state,
            "appearance-native-button-apply-failed",
            DOMAIN_BUTTONS
        )
    end
    local scrollOK = SetButtonObjects(
        snapshot.scrollObjects or EMPTY_BUTTONS,
        appearance.hideNativeButtons == true
    )
    if not scrollOK then
        HandleNativeMutationFailure(
            state,
            "appearance-native-scroll-apply-failed",
            DOMAIN_SCROLL
        )
    end
    if snapshot.editBoxPoints and not ApplyInputPosition(
        targets,
        appearance.inputPosition,
        appearance.inputHeight
    ) then
        RestoreEditBox(
            targets.editBox,
            snapshot.editBoxPoints,
            snapshot.editBoxHeight,
            snapshot.editBoxJustifyV,
            targets.inputLanguageButton,
            snapshot.inputLanguageButtonHeight
        )
        HandleNativeMutationFailure(
            state,
            "appearance-input-apply-failed",
            DOMAIN_INPUT
        )
    end

    local frameVisibility = GetManagedFrameVisibility(state)
    if frameVisibility == nil then
        RestoreState(state)
        return false, "appearance-element-fade-visibility-unavailable"
    end
    if appearance.backgroundAlpha > 0 then
        local backgroundColor = appearance.backgroundColor
        ok = CallMethod(
            art.background,
            "SetColorTexture",
            backgroundColor[1],
            backgroundColor[2],
            backgroundColor[3],
            backgroundColor[4]
        )
            and CallMethod(
                art.background,
                "SetAlpha",
                appearance.backgroundAlpha * frameVisibility
            )
            and CallMethod(art.background, "Show")
    else
        ok = CallMethod(art.background, "Hide")
    end

    local thickness = GetPixelSize(
        targets.background,
        appearance.borderWidth or 1,
        1
    )
    ok = ok
        and CallMethod(art.top, "SetHeight", thickness)
        and CallMethod(art.bottom, "SetHeight", thickness)
        and CallMethod(art.left, "SetWidth", thickness)
        and CallMethod(art.right, "SetWidth", thickness)
    local borderShown = appearance.borderStyle ~= "none"
    for _, texture in pairs({
        art.top,
        art.bottom,
        art.left,
        art.right,
    }) do
        ok = ok
            and CallMethod(
                texture,
                "SetColorTexture",
                borderR,
                borderG,
                borderB,
                borderA
            )
            and CallMethod(texture, borderShown and "Show" or "Hide")
    end

    TryApplyTabTypography(
        state,
        appearance.tabTextEffect,
        appearance.tabFontSize,
        GetTypographyTabWidth(appearance)
    )
    ok = ok and ApplyTabArt(
        state,
        appearance.tabStyle,
        appearance.tabTextEffect,
        tabSlotWidth,
        selected,
        r,
        g,
        b
    )
    if not ok then
        RestoreState(state)
        return false, "appearance-art-apply-failed"
    end

    state.effect = appearance.messageEffect
    state.selected = selected
    state.applied = true
    state.restorePending = false
    if state.controlsCapturePending or state.inputCapturePending then
        Appearance.mutationRefreshPending = true
    end
    UpdateCache(
        state,
        appearance,
        r,
        g,
        b,
        borderR,
        borderG,
        borderB,
        borderA,
        tabSlotWidth
    )
    return true, true
end

local function ApplyTabState(state, appearance)
    if not IsVisualMutationAllowed() then
        return false, "restriction-not-open"
    end
    local selected, selectionReason =
        Adapter:IsAppearanceTabSelected(state.frame)
    if type(selected) ~= "boolean" then
        return false, selectionReason or "appearance-tab-selection-unavailable"
    end
    local r, g, b = GetTabColor(appearance)
    local tabSlotWidth = ResolveTabSlotWidth(state, appearance)
    if not IsFiniteNumber(tabSlotWidth) or tabSlotWidth <= 0 then
        return false, "appearance-tab-slot-width-unavailable"
    end
    local cache = state.cache
    if state.applied
        and cache
        and cache.tabStyle == appearance.tabStyle
        and cache.tabTextEffect == appearance.tabTextEffect
        and cache.tabFontSize == appearance.tabFontSize
        and cache.tabWidth == appearance.tabWidth
        and cache.tabWidthMode == appearance.tabWidthMode
        and cache.tabSlotWidth == tabSlotWidth
        and cache.underlineThickness == GetPixelSize(
            state.targets.tabText,
            2,
            1
        )
        and cache.classColorTabs == appearance.classColorTabs
        and cache.r == r
        and cache.g == g
        and cache.b == b
        and state.tabTypographyPending ~= true
    then
        if state.selected ~= selected then
            local synced, syncReason = SyncManagedTabVisuals(state, selected)
            if not synced then
                RestoreTabState(state)
                return false, syncReason or "appearance-tab-selection-apply-failed"
            end
        end
        return true, false
    end

    state.applied = true
    state.restorePending = true
    TryApplyTabTypography(
        state,
        appearance.tabTextEffect,
        appearance.tabFontSize,
        GetTypographyTabWidth(appearance)
    )
    local ok = SetTabRegionsSuppressed(state.snapshot.tabRegions, true)
        and CallMethod(state.targets.tab, "SetPushedTextOffset", 0, 0)
        and Adapter:CanCallProtected(state.targets.tabText) == true
        and CallMethod(state.targets.tabText, "SetTextColor", r, g, b, 1)
        and SetManagedTabAlpha(state, selected and 1 or TAB_INACTIVE_ALPHA, true)
        and ApplyTabArt(
            state,
            appearance.tabStyle,
            appearance.tabTextEffect,
            tabSlotWidth,
            selected,
            r,
            g,
            b
        )
    if not ok then
        RestoreTabState(state)
        return false, "appearance-tab-apply-failed"
    end
    cache = cache or {}
    state.cache = cache
    cache.tabStyle = appearance.tabStyle
    cache.tabTextEffect = appearance.tabTextEffect
    cache.tabFontSize = appearance.tabFontSize
    cache.tabWidth = appearance.tabWidth
    cache.tabWidthMode = appearance.tabWidthMode
    cache.tabSlotWidth = tabSlotWidth
    cache.tabTypographyWidth = GetTypographyTabWidth(appearance)
    cache.underlineThickness = GetPixelSize(state.targets.tabText, 2, 1)
    cache.classColorTabs = appearance.classColorTabs
    cache.r = r
    cache.g = g
    cache.b = b
    state.selected = selected
    state.applied = true
    state.restorePending = false
    return true, true
end

local function ClearButtonBindings(state)
    local snapshot = state and state.snapshot
    if not snapshot then return end
    local buttons = snapshot.buttonObjects or EMPTY_BUTTONS
    for index = 1, #buttons do
        local button = buttons[index].button
        if buttonOwners[button] == state then
            buttonOwners[button] = nil
            buttonDomains[button] = nil
        end
    end
    buttons = snapshot.scrollObjects or EMPTY_BUTTONS
    for index = 1, #buttons do
        local button = buttons[index].button
        if buttonOwners[button] == state then
            buttonOwners[button] = nil
            buttonDomains[button] = nil
        end
    end
end

local function RetireFrameState(frame, state)
    if not RestoreState(state) then return false, "appearance-generation-restore-pending" end
    ClearButtonBindings(state)
    ClearTabTextAlphaOwner(state)
    frameStates[frame] = nil
    tabStates[state.targets.tab] = nil
    animationStates[state.art.fadeGroup] = nil
    animationStates[state.art.glowGroup] = nil
    allocationFailures[frame] = nil
    if type(Adapter.InvalidateAppearanceTargets) == "function" then
        local invalidated, reason = Adapter:InvalidateAppearanceTargets(
            frame,
            state.targets
        )
        if not invalidated then return false, reason end
    end
    if capturedFrames > 0 then capturedFrames = capturedFrames - 1 end
    targetRebindCount = targetRebindCount + 1
    return true
end

local function RetireTabState(frame, state)
    if not RestoreTabState(state) then return false, "appearance-tab-generation-restore-pending" end
    tabOnlyStates[frame] = nil
    ClearTabTextAlphaOwner(state)
    tabStates[state.targets.tab] = nil
    if capturedAppearanceTabs > 0 then
        capturedAppearanceTabs = capturedAppearanceTabs - 1
    end
    targetRebindCount = targetRebindCount + 1
    return true
end

local function DeactivateFrameState(state)
    if not state or state.inactive == true then return true end
    if not RestoreState(state) then
        return false, "appearance-inactive-frame-restore-pending"
    end
    ClearButtonBindings(state)
    state.inactive = true
    state.cache = nil
    state.tabTypographyPending = false
    state.seenGeneration = nil
    return true
end

local function ReactivateFrameState(frame, state)
    local targets, targetReason = Adapter:GetAppearanceTargets(frame)
    if not targets then return nil, targetReason end
    local preflightOK, preflightReason = PreflightAppearanceTargets(targets)
    if not preflightOK then return nil, preflightReason end
    local selected, selectionReason = Adapter:IsAppearanceTabSelected(frame)
    if type(selected) ~= "boolean" then
        return nil, selectionReason or "appearance-tab-selection-unavailable"
    end
    local snapshot, snapshotReason = CaptureFrame(targets)
    if not snapshot then return nil, snapshotReason end

    state.targets = targets
    state.snapshot = snapshot
    state.controlsCapturePending = snapshot.controlsCapturePending == true
    state.controlsCaptureReason = snapshot.controlsCaptureReason
    state.inputCapturePending = snapshot.inputCapturePending == true
    state.inputCaptureReason = snapshot.inputCaptureReason
    state.applied = false
    state.restorePending = false
    state.selected = selected
    state.pressed = false
    state.inactive = false
    state.tabTypographyPending = false
    tabStates[targets.tab] = state
    if not InstallTabAlphaHook(targets.tab)
        or not BindTabTextAlphaOwner(state)
        or not InstallTabPressHooks(targets.tab)
        or not InstallButtonHooks(state, snapshot.buttonObjects, DOMAIN_BUTTONS)
        or not InstallButtonHooks(state, snapshot.scrollObjects, DOMAIN_SCROLL)
    then
        ClearButtonBindings(state)
        state.inactive = true
        return nil, "appearance-inactive-frame-hook-install-failed"
    end
    return state
end

local function DeactivateTabState(state)
    if not state or state.inactive == true then return true end
    if not RestoreTabState(state) then
        return false, "appearance-inactive-tab-restore-pending"
    end
    state.inactive = true
    state.cache = nil
    state.tabTypographyPending = false
    state.seenGeneration = nil
    return true
end

local function ReactivateTabState(frame, state)
    local targets, targetReason = Adapter:GetAppearanceTabTargets(frame)
    if not targets then return nil, targetReason end
    local preflightOK, preflightReason = PreflightTabTargets(targets)
    if not preflightOK then return nil, preflightReason end
    local selected, selectionReason = Adapter:IsAppearanceTabSelected(frame)
    if type(selected) ~= "boolean" then
        return nil, selectionReason or "appearance-tab-selection-unavailable"
    end
    local snapshot, snapshotReason = CaptureTab(targets)
    if not snapshot then return nil, snapshotReason end

    state.targets = targets
    state.snapshot = snapshot
    state.applied = false
    state.restorePending = false
    state.selected = selected
    state.pressed = false
    state.inactive = false
    state.tabTypographyPending = false
    tabStates[targets.tab] = state
    if not InstallTabAlphaHook(targets.tab)
        or not BindTabTextAlphaOwner(state)
        or not InstallTabPressHooks(targets.tab)
    then
        state.inactive = true
        return nil, "appearance-inactive-tab-hook-install-failed"
    end
    return state
end

local function EnsureState(frame)
    local state = frameStates[frame]
    if state
        and type(Adapter.AppearanceTargetsMatch) == "function"
        and not Adapter:AppearanceTargetsMatch(frame, state.targets)
    then
        local retired, retireReason = RetireFrameState(frame, state)
        if not retired then return nil, retireReason end
        state = nil
    end
    if state and state.inactive == true then
        return ReactivateFrameState(frame, state)
    end
    if state then return state end
    local allocationReason = allocationFailures[frame]
    if allocationReason then return nil, allocationReason end

    local tabOnlyState = tabOnlyStates[frame]
    if tabOnlyState then
        local retired, retireReason = RetireTabState(frame, tabOnlyState)
        if not retired then return nil, retireReason end
    end

    local targets, targetReason = Adapter:GetAppearanceTargets(frame)
    if not targets then return nil, targetReason end
    local preflightOK, preflightReason = PreflightAppearanceTargets(targets)
    if not preflightOK then return nil, preflightReason end
    local selected, selectionReason = Adapter:IsAppearanceTabSelected(frame)
    if type(selected) ~= "boolean" then
        return nil, selectionReason or "appearance-tab-selection-unavailable"
    end
    local snapshot, snapshotReason = CaptureFrame(targets)
    if not snapshot then return nil, snapshotReason end
    local art, artReason = AllocateArt(targets)
    if not art then
        allocationReason = artReason or "appearance-art-allocation-failed"
        if not string.find(allocationReason, "protected", 1, true) then
            allocationFailures[frame] = allocationReason
        end
        return nil, allocationReason
    end

    state = {
        frame = frame,
        targets = targets,
        snapshot = snapshot,
        art = art,
        applied = false,
        restorePending = false,
        selected = selected,
        pressed = false,
        inactive = false,
        generation = targetGeneration + 1,
        controlsCapturePending = snapshot.controlsCapturePending == true,
        controlsCaptureReason = snapshot.controlsCaptureReason,
        inputCapturePending = snapshot.inputCapturePending == true,
        inputCaptureReason = snapshot.inputCaptureReason,
    }
    targetGeneration = state.generation
    frameStates[frame] = state
    tabStates[targets.tab] = state
    animationStates[art.fadeGroup] = state
    animationStates[art.glowGroup] = state
    if not InstallTabAlphaHook(targets.tab)
        or not BindTabTextAlphaOwner(state)
        or not InstallTabPressHooks(targets.tab)
        or not InstallButtonHooks(state, snapshot.buttonObjects, DOMAIN_BUTTONS)
        or not InstallButtonHooks(state, snapshot.scrollObjects, DOMAIN_SCROLL)
    then
        ClearButtonBindings(state)
        ClearTabTextAlphaOwner(state)
        frameStates[frame] = nil
        tabStates[targets.tab] = nil
        animationStates[art.fadeGroup] = nil
        animationStates[art.glowGroup] = nil
        HideArt(art)
        return nil, "appearance-button-hook-install-failed"
    end
    capturedFrames = capturedFrames + 1
    return state
end

local function EnsureTabState(frame)
    if frameStates[frame] then return nil, "appearance-full-frame-managed" end
    local state = tabOnlyStates[frame]
    if state
        and type(Adapter.AppearanceTabTargetsMatch) == "function"
        and not Adapter:AppearanceTabTargetsMatch(frame, state.targets)
    then
        local retired, retireReason = RetireTabState(frame, state)
        if not retired then return nil, retireReason end
        state = nil
    end
    if state and state.inactive == true then
        return ReactivateTabState(frame, state)
    end
    if state then return state end
    local targets, targetReason = Adapter:GetAppearanceTabTargets(frame)
    if not targets then return nil, targetReason end
    local preflightOK, preflightReason = PreflightTabTargets(targets)
    if not preflightOK then return nil, preflightReason end
    local selected, selectionReason = Adapter:IsAppearanceTabSelected(frame)
    if type(selected) ~= "boolean" then
        return nil, selectionReason or "appearance-tab-selection-unavailable"
    end
    local snapshot, snapshotReason = CaptureTab(targets)
    if not snapshot then return nil, snapshotReason end
    local art, artReason = AllocateTabArt(targets)
    if not art then return nil, artReason end
    state = {
        frame = frame,
        targets = targets,
        snapshot = snapshot,
        art = art,
        applied = false,
        restorePending = false,
        selected = selected,
        pressed = false,
        inactive = false,
        generation = targetGeneration + 1,
    }
    targetGeneration = state.generation
    tabOnlyStates[frame] = state
    tabStates[targets.tab] = state
    if not InstallTabAlphaHook(targets.tab)
        or not BindTabTextAlphaOwner(state)
        or not InstallTabPressHooks(targets.tab)
    then
        tabOnlyStates[frame] = nil
        tabStates[targets.tab] = nil
        ClearTabTextAlphaOwner(state)
        HideArt(art)
        return nil, "appearance-tab-alpha-hook-install-failed"
    end
    capturedAppearanceTabs = capturedAppearanceTabs + 1
    return state
end

local function RefreshGauges()
    local managed = 0
    local pending = 0
    local suspended = 0
    for _, state in pairs(frameStates) do
        if state.applied then managed = managed + 1 end
        if state.restorePending then pending = pending + 1 end
        if state.controlsCapturePending then suspended = suspended + 1 end
        if state.inputCapturePending then suspended = suspended + 1 end
    end
    for _, state in pairs(tabOnlyStates) do
        if state.restorePending then pending = pending + 1 end
    end
    Appearance.managedFrames = managed
    Appearance.suspendedDomains = suspended
    Appearance.frameRestorePending = pending
    Appearance.restorePending = pending
        + (Adapter.tooltipCleanupPending and 1 or 0)
        + (YChat.CombatLog
            and YChat.CombatLog.state
            and YChat.CombatLog.state.restorePending
            and 1
            or 0)
        + (YChat.MainLayout and YChat.MainLayout.pending and 1 or 0)
    return managed, Appearance.restorePending
end

ApplyAppearanceTab = function(frame)
    if frameStates[frame] then
        frameStates[frame].seenGeneration = tabScanGeneration
        return true
    end
    if type(Adapter.IsAppearanceFrameSupported) == "function"
        and Adapter:IsAppearanceFrameSupported(frame) == true
    then
        Appearance.lastReason = "appearance-full-frame-unavailable"
        return false
    end
    local state, stateReason = EnsureTabState(frame)
    if not state then
        Appearance.lastReason = stateReason or "appearance-tab-state-unavailable"
        return false
    end
    local appearance = YChat:GetAppearance()
    if type(appearance) ~= "table" then return false end
    local applied, applyReason = ApplyTabState(state, appearance)
    state.seenGeneration = tabScanGeneration
    if not applied then Appearance.lastReason = applyReason end
    return applied
end

local function SyncDockSelectedTab(state)
    if not state or state.seenGeneration ~= tabScanGeneration then return true end
    local selected, selectionReason =
        Adapter:IsAppearanceTabSelected(state.frame)
    if type(selected) ~= "boolean" then
        if frameStates[state.frame] == state then
            RestoreState(state)
        else
            RestoreTabState(state)
        end
        Appearance.lastReason = selectionReason
            or "appearance-tab-selection-unavailable"
        return false
    end
    local synced, syncReason = SyncManagedTabVisuals(state, selected)
    if not synced then
        Appearance.lastReason = syncReason
            or "appearance-tab-selection-apply-failed"
        return false
    end
    return true
end

local function NotifyExtensionsWindowsChanged(reason)
    local extensions = {
        YChat.CombatLog,
        YChat.CopyViewer,
        YChat.InputSkin,
        YChat.MainLayout,
        YChat.ElementFade,
    }
    for index = 1, #extensions do
        local extension = extensions[index]
        if extension and type(extension.OnWindowsChanged) == "function" then
            pcall(
                extension.OnWindowsChanged,
                extension,
                reason or "appearance-windows-changed"
            )
        end
    end
end

RefreshAppearanceTabs = function(
    forceNativeTabs,
    forceNativeFrames,
    reconcileDockWidths,
    reconcileInputLayout
)
    if Appearance.enabled ~= true
        or Appearance.mutationPaused == true
        or not IsVisualMutationAllowed()
    then
        if Appearance.enabled then Appearance.mutationRefreshPending = true end
        return
    end
    Appearance.mutationRefreshPending = false
    tabScanGeneration = tabScanGeneration + 1
    forceFrameReconcile = forceNativeFrames == true
    forceInputLayoutReconcile = reconcileInputLayout == true
    if type(Adapter.ForEachAppearanceFrame) == "function" then
        Adapter:ForEachAppearanceFrame(ApplyDiscoveredFrame)
    else
        Adapter:ForEachSupportedFrame(ApplyDiscoveredFrame)
    end
    forceFrameReconcile = false
    forceInputLayoutReconcile = false
    for _, state in pairs(frameStates) do
        if state.seenGeneration ~= tabScanGeneration
            and state.inactive ~= true
        then
            local deactivated, deactivateReason = DeactivateFrameState(state)
            if not deactivated then
                Appearance.lastReason = deactivateReason
                    or "appearance-inactive-frame-deactivate-failed"
            end
        end
    end
    if type(Adapter.ForEachAppearanceTab) == "function" then
        Adapter:ForEachAppearanceTab(ApplyAppearanceTab)
    end
    if forceNativeTabs == true then
        -- Native lifecycle hooks can run while Blizzard is still closing,
        -- renaming, or reusing a permanent chat-window slot. Never call back
        -- into FCFDock_UpdateTabs from that stack. Width reconciliation is
        -- reserved for the bounded post-transaction settle pass.
        if reconcileDockWidths == true
            and type(Adapter.ReconcileAppearanceDockTabWidths) == "function"
        then
            nativeDockWidthSyncActive = true
            local appearance = YChat:GetAppearance()
            local reconciled, reconcileReason =
                Adapter:ReconcileAppearanceDockTabWidths(
                    appearance and appearance.tabWidth,
                    appearance and appearance.tabWidthMode,
                    appearance and appearance.tabSpacing,
                    appearance and appearance.tabLeftInset,
                    appearance and appearance.hideCombatLog == true
                )
            nativeDockWidthSyncActive = false
            if not reconciled then
                Appearance.lastReason = reconcileReason
                    or "appearance-dock-tab-reconcile-failed"
            else
                -- Typography changes alter the native auto-width measurement.
                -- Reapply cached art and text anchors against the final dock slots
                -- in the same config refresh instead of waiting for settle.
                for _, state in pairs(frameStates) do
                    if state.seenGeneration == tabScanGeneration then
                        local applied, applyReason = ApplyState(state, appearance, false)
                        if not applied then
                            Appearance.lastReason = applyReason
                                or "appearance-dock-tab-final-frame-apply-failed"
                        end
                    end
                end
                for _, state in pairs(tabOnlyStates) do
                    if state.seenGeneration == tabScanGeneration then
                        local applied, applyReason = ApplyTabState(state, appearance)
                        if not applied then
                            Appearance.lastReason = applyReason
                                or "appearance-dock-tab-final-tab-apply-failed"
                        end
                    end
                end
            end
        end
        for _, state in pairs(frameStates) do
            SyncDockSelectedTab(state)
        end
        for _, state in pairs(tabOnlyStates) do
            SyncDockSelectedTab(state)
        end
    end
    for _, state in pairs(tabOnlyStates) do
        if state.seenGeneration ~= tabScanGeneration then
            local deactivated, deactivateReason = DeactivateTabState(state)
            if not deactivated then
                Appearance.lastReason = deactivateReason
                    or "appearance-inactive-tab-deactivate-failed"
            end
        end
    end
    local overflowApplied, overflowReason = RefreshOverflowSkin()
    if not overflowApplied then
        Appearance.lastReason = overflowReason or "dock-overflow-skin-apply-failed"
    end
    RefreshGauges()
end

function Appearance:ApplyFrame(frame, reason, forceLayout, forceNative)
    if not self.enabled then return false, "appearance-disabled" end
    if self.mutationPaused or not IsVisualMutationAllowed() then
        self.mutationRefreshPending = true
        return false, "restriction-not-open"
    end
    local state, stateReason = EnsureState(frame)
    if not state then
        self.lastReason = stateReason or "appearance-state-unavailable"
        if type(self.lastReason) == "string"
            and string.find(self.lastReason, "protected", 1, true)
        then
            self.mutationRefreshPending = true
        end
        RefreshGauges()
        return false, self.lastReason
    end
    local buttonsReady, buttonReason = ReconcileLateGlobalButtons(state)
    if not buttonsReady then
        self.lastReason = buttonReason or "appearance-global-button-reconcile-failed"
    end

    local appearance = YChat:GetAppearance()
    if type(appearance) ~= "table" then return false, "appearance-config-unavailable" end
    local applied, applyReason = ApplyState(
        state,
        appearance,
        forceLayout == true
    )
    self.lastReason = applied and (reason or "appearance-applied")
        or (applyReason or "appearance-apply-failed")
    RefreshGauges()
    return applied, applyReason
end

function Appearance:RestoreFrame(frame, reason)
    local state = frameStates[frame]
    if not state then return true end
    if not IsVisualMutationAllowed() then
        state.restorePending = state.applied == true or state.restorePending == true
        self.lastReason = "restriction-not-open"
        RefreshGauges()
        return false, self.lastReason
    end
    local restored = RestoreState(state)
    self.lastReason = restored and (reason or "appearance-restored")
        or "appearance-restore-pending"
    RefreshGauges()
    return restored, restored and nil or "appearance-restore-pending"
end

function Appearance:RestoreAll(reason)
    if not IsVisualMutationAllowed() then
        for _, state in pairs(frameStates) do
            state.restorePending = state.applied == true
                or state.restorePending == true
        end
        for _, state in pairs(tabOnlyStates) do
            state.restorePending = state.applied == true
                or state.restorePending == true
        end
        self.lastReason = "restriction-not-open"
        RefreshGauges()
        return false, self.lastReason
    end
    local firstReason
    local tooltipCleared, tooltipReason = Adapter:ClearHyperlinkTooltip()
    if not tooltipCleared then firstReason = tooltipReason end
    local overflowRestored, overflowReason = RestoreOverflowSkin()
    if not overflowRestored and not firstReason then firstReason = overflowReason end
    local extensions = {
        YChat.CombatLog,
        YChat.CopyViewer,
        YChat.InputSkin,
        YChat.MainLayout,
        YChat.ElementFade,
    }
    for index = 1, #extensions do
        local extension = extensions[index]
        if extension and type(extension.RestoreAll) == "function" then
            local ok, restored, restoreReason =
                pcall(extension.RestoreAll, extension, reason)
            if (not ok or restored ~= true) and not firstReason then
                firstReason = restoreReason or "appearance-extension-restore-pending"
            end
        end
    end
    for frame in pairs(frameStates) do
        local restored, restoreReason = self:RestoreFrame(frame, reason)
        if not restored and not firstReason then firstReason = restoreReason end
    end
    for _, state in pairs(tabOnlyStates) do
        if not RestoreTabState(state) and not firstReason then
            firstReason = "appearance-tab-restore-pending"
        end
    end
    local dockRestored, dockRestoreReason =
        Adapter:ReconcileAppearanceDockTabWidths()
    if not dockRestored and not firstReason then
        firstReason = dockRestoreReason or "appearance-dock-tab-restore-pending"
    end
    RefreshGauges()
    if firstReason then return false, firstReason end
    return true
end

function Appearance:ScheduleRestoreRetry()
    if self.restoreRetryActive then return true end
    if not IsVisualMutationAllowed() or not Adapter:IsEnabled() then
        return false, "appearance-restore-retry-not-open"
    end
    self.nativeSettleActive = false
    self.nativeSettleFramesRemaining = 0
    local scheduled, scheduleReason = Adapter:SetDeferredDriverEnabled(true)
    if not scheduled then return false, scheduleReason end
    self.restoreRetryActive = true
    self.restoreRetryAttempts = 0
    return true
end

function Appearance:IsRestoreRetryActive()
    return self.restoreRetryActive == true or self.nativeSettleActive == true
end

function Appearance:OnDeferredRestoreStep()
    if not self.restoreRetryActive and self.nativeSettleActive then
        if not self.enabled
            or self.mutationPaused
            or not IsVisualMutationAllowed()
        then
            self.nativeSettleActive = false
            self.nativeSettleFramesRemaining = 0
            self.mutationRefreshPending = self.enabled == true
            return false, false
        end
        self.nativeSettleFramesRemaining =
            (self.nativeSettleFramesRemaining or 1) - 1
        if self.nativeSettleFramesRemaining > 0 then return true, false end
        self.nativeSettleActive = false
        self.nativeSettleFramesRemaining = 0
        local reconcileInputLayout = self.nativeSettleForceLayout == true
        local windowsReason = self.pendingWindowsReason
        self.nativeSettleForceLayout = false
        self.pendingWindowsReason = nil
        RefreshAppearanceTabs(true, true, true, reconcileInputLayout)
        if windowsReason then NotifyExtensionsWindowsChanged(windowsReason) end
        return self.nativeSettleActive == true, false
    end
    if not self.restoreRetryActive then return false, false end
    if not IsVisualMutationAllowed() then
        self.restoreRetryActive = false
        self.restoreRetryAttempts = 0
        RefreshGauges()
        return false, false
    end
    self.restoreRetryAttempts = self.restoreRetryAttempts + 1

    local tooltipDisabled, tooltipReason =
        Adapter:SetHyperlinkTooltipEnabled(false)
    local restored, restoreReason =
        self:RestoreAll("appearance-deferred-restore")
    if tooltipDisabled and restored then
        self.restoreRetryActive = false
        self.restoreRetryAttempts = 0
        self.tooltipReason = nil
        RefreshGauges()
        return self.nativeSettleActive == true, true
    end

    self.lastReason = tooltipReason
        or restoreReason
        or "appearance-deferred-restore-pending"
    if self.restoreRetryAttempts >= MAX_RESTORE_RETRY_ATTEMPTS then
        self.restoreRetryActive = false
        self.restoreRetryAttempts = 0
        RefreshGauges()
        return false, false
    end
    RefreshGauges()
    return true, false
end

function Appearance:ScheduleNativeSettle(reason, forceLayout)
    if not self.enabled then
        return false, "appearance-native-settle-disabled"
    end
    if self.mutationPaused or not IsVisualMutationAllowed() then
        self.mutationRefreshPending = true
        return false, "appearance-native-settle-not-open"
    end
    self.mutationRefreshPending = false
    self.nativeSettleForceLayout = self.nativeSettleForceLayout == true
        or forceLayout == true
    if self.nativeSettleActive then return true end
    self.nativeSettleActive = true
    self.nativeSettleFramesRemaining = MAX_NATIVE_SETTLE_FRAMES
    local scheduled, scheduleReason = Adapter:SetDeferredDriverEnabled(true)
    if not scheduled then
        self.nativeSettleActive = false
        self.nativeSettleFramesRemaining = 0
        self.nativeSettleForceLayout = false
        return false, scheduleReason
    end
    return true
end

ApplyDiscoveredFrame = function(frame)
    Appearance:ApplyFrame(
        frame,
        "appearance-rescan",
        forceInputLayoutReconcile,
        forceFrameReconcile
    )
    local state = frameStates[frame]
    if state then state.seenGeneration = tabScanGeneration end
end

function Appearance:PreviewInputHeight(value)
    if not self.enabled or self.mutationPaused
        or not IsVisualMutationAllowed()
        or not IsFiniteNumber(value)
    then
        return false, "appearance-input-preview-unavailable"
    end
    local minimum = YChat.INPUT_HEIGHT_MIN or 20
    local maximum = YChat.INPUT_HEIGHT_MAX or 48
    local height = floor(value + 0.5)
    if height < minimum then height = minimum end
    if height > maximum then height = maximum end
    local appearance = YChat:GetAppearance()
    if type(appearance) ~= "table" then
        return false, "appearance-config-unavailable"
    end

    local mainFrame = _G.ChatFrame1
    local state = frameStates[mainFrame]
    if not state then
        for frame, candidate in pairs(frameStates) do
            if frame == mainFrame or candidate.frame == mainFrame then
                state = candidate
                break
            end
        end
    end
    local applied = state
        and state.applied == true
        and state.targets
        and state.targets.editBox ~= nil
        or false
    if applied then
        if not ApplyInputPosition(state.targets, appearance.inputPosition, height) then
            return false, "appearance-input-preview-failed"
        end
        state.cache.inputHeight = height
    end
    self.lastReason = applied
        and "appearance-input-height-preview"
        or "appearance-input-preview-no-frame"
    return applied
end

function Appearance:GetInputVisualInset(frame)
    local state = frameStates[frame]
    local editBox = state and state.targets and state.targets.editBox
    if not editBox then return nil end
    return GetPixelSize(editBox, INPUT_ART_INSET_PIXELS, 1)
end

function Appearance:SetEnabled(enabled, reason)
    enabled = enabled == true
    if not enabled then
        self.enabled = false
        nativeDockMutationObserved = false
        self.nativeSettleActive = false
        self.nativeSettleFramesRemaining = 0
        self.nativeSettleForceLayout = false
        self.pendingWindowsReason = nil
        self.mutationRefreshPending = false
        self.tooltipAvailable = false
        local tooltipDisabled, tooltipReason =
            Adapter:SetHyperlinkTooltipEnabled(false)
        local restored, restoreReason =
            self:RestoreAll(reason or "appearance-disabled")
        if not tooltipDisabled then
            self.tooltipReason = tooltipReason or "tooltip-cleanup-pending"
            RefreshGauges()
            self:ScheduleRestoreRetry()
            return false, self.tooltipReason
        end
        self.tooltipReason = nil
        if not restored then
            self:ScheduleRestoreRetry()
            return false, restoreReason
        end
        self.restoreRetryActive = false
        self.restoreRetryAttempts = 0
        self.mutationPaused = false
        return true
    end

    if not Adapter:IsEnabled() then return false, "adapter-disabled" end
    local alreadyEnabled = self.enabled == true
    RefreshGauges()
    if self.restoreRetryActive or self.restorePending > 0 then
        return false, "appearance-restore-pending"
    end
    local hooksOK, hooksReason = EnsureNativeHooks()
    self.enabled = true
    if not hooksOK then self.lastReason = hooksReason end
    local appearance = YChat:GetAppearance()
    if type(appearance) ~= "table" then
        if not alreadyEnabled then self.enabled = false end
        return false, "appearance-config-unavailable"
    end
    local tooltipEnabled, tooltipReason =
        Adapter:SetHyperlinkTooltipEnabled(true, appearance.tooltipAnchor)
    self.tooltipAvailable = tooltipEnabled == true
    self.tooltipReason = tooltipEnabled and nil
        or (tooltipReason or "tooltip-unavailable")
    RefreshAppearanceTabs(true, false, true)
    self:ScheduleNativeSettle(reason or "appearance-enabled")
    local extensions = {
        YChat.CombatLog,
        YChat.CopyViewer,
        YChat.InputSkin,
        YChat.MainLayout,
        YChat.ElementFade,
    }
    local coordinateOnly = alreadyEnabled
    for index = 1, #extensions do
        local extension = extensions[index]
        if coordinateOnly
            and extension
            and type(extension.OnWindowsChanged) == "function"
        then
            pcall(
                extension.OnWindowsChanged,
                extension,
                reason or "appearance-config-refresh"
            )
        elseif extension and type(extension.SetEnabled) == "function" then
            pcall(extension.SetEnabled, extension, true, reason or "appearance-enabled")
        end
    end
    RefreshGauges()
    self.lastReason = reason or "appearance-enabled"
    return true
end

function Appearance:OnFrameDiscovered(frame, valid, reason)
    if YChat.CopyViewer and type(YChat.CopyViewer.OnFrameDiscovered) == "function" then
        pcall(YChat.CopyViewer.OnFrameDiscovered, YChat.CopyViewer, frame, valid)
    end
    if YChat.InputSkin and type(YChat.InputSkin.OnFrameDiscovered) == "function" then
        pcall(YChat.InputSkin.OnFrameDiscovered, YChat.InputSkin, frame, valid)
    end
    if YChat.ElementFade and type(YChat.ElementFade.OnFrameDiscovered) == "function" then
        pcall(YChat.ElementFade.OnFrameDiscovered, YChat.ElementFade, frame, valid)
    end
    if not valid then
        local tooltipCleared, tooltipReason = Adapter:ClearHyperlinkTooltip(frame)
        local restored, restoreReason =
            self:RestoreFrame(frame, reason or "appearance-frame-invalid")
        if not tooltipCleared then
            RefreshGauges()
            return false, tooltipReason
        end
        return restored, restoreReason
    end
    if not self.enabled then return true end
    if self.mutationPaused or not IsVisualMutationAllowed() then
        self.mutationRefreshPending = true
        return true
    end
    self:ScheduleNativeSettle(reason or "appearance-frame-discovered")
    return true
end

function Appearance:OnWindowsChanged(reason)
    EnsureNativeHooks()
    if not self.enabled then return true end
    self.lastReason = reason or "appearance-windows-changed"
    self.pendingWindowsReason = self.lastReason
    self:ScheduleNativeSettle(reason or "appearance-windows-changed")
    return true
end

function Appearance:OnNativeLayoutRefreshed(frame)
    if YChat.MainLayout
        and type(YChat.MainLayout.OnWindowsChanged) == "function"
        and frame == _G.ChatFrame1
    then
        pcall(YChat.MainLayout.OnWindowsChanged, YChat.MainLayout)
    end
    local state = frameStates[frame]
    if not state then return true end
    if state.restorePending then
        if not IsVisualMutationAllowed() then
            return false, "restriction-not-open"
        end
        local restored, restoreReason =
            self:RestoreFrame(frame, "appearance-restore-retry")
        RefreshGauges()
        if restored
            and self.restorePending == 0
            and self.enabled ~= true
            and YChat.lifecycleDisablePending
            and type(YChat.OnAppearanceRestoreConfirmed) == "function"
        then
            self.restoreRetryActive = false
            self.restoreRetryAttempts = 0
            pcall(YChat.OnAppearanceRestoreConfirmed, YChat)
        end
        return restored, restoreReason
    end
    if not self.enabled then return true end
    self:ScheduleNativeSettle("appearance-native-layout", true)
    return true
end

function Appearance:SetMutationPaused(paused, reason)
    paused = paused == true
    self.mutationPaused = paused
    self.lastReason = reason or (paused
        and "appearance-mutation-paused"
        or "appearance-mutation-resumed")
    if paused then
        self:QuiesceAnimations()
        self.nativeSettleActive = false
        self.nativeSettleFramesRemaining = 0
        self.mutationRefreshPending = self.enabled == true
        RefreshGauges()
        return true
    end
    if not self.enabled then
        self.mutationRefreshPending = false
        RefreshGauges()
        return true
    end
    if not IsVisualMutationAllowed() then
        self.mutationRefreshPending = true
        RefreshGauges()
        return false, "restriction-not-open"
    end
    EnsureNativeHooks()
    self:ScheduleNativeSettle(reason or "appearance-mutation-resumed")
    RefreshGauges()
    return true
end

function Appearance:HasPendingVisualRetry()
    return self.enabled == true
        and self.mutationRefreshPending == true
        and self.nativeSettleActive ~= true
end

function Appearance:RetryPendingVisuals(reason)
    if not self:HasPendingVisualRetry() then return true end
    if self.mutationPaused or not IsVisualMutationAllowed() then
        return false, "restriction-not-open"
    end
    return self:ScheduleNativeSettle(reason or "appearance-pending-retry", true)
end

local function SetElementFadeAlpha(object, alpha, cancelNativeFade)
    if not object then return true end
    if Adapter:CanCallProtected(object) ~= true
        or type(object.SetAlpha) ~= "function"
    then
        return false
    end
    if cancelNativeFade and type(UIFrameFadeRemoveFrame) == "function" then
        pcall(UIFrameFadeRemoveFrame, object)
    end
    return CallMethod(object, "SetAlpha", alpha)
end

function Appearance:ApplyElementFade(frame, visibility, cancelNativeFade)
    if not self.enabled then
        return false, "appearance-element-fade-not-ready"
    end
    local state = frameStates[frame] or tabOnlyStates[frame]
    if not state or state.applied ~= true or state.restorePending == true then
        return true
    end
    if type(visibility) == "boolean" then
        visibility = visibility and 0 or 1
    end
    visibility = tonumber(visibility) or 1
    if visibility < 0 then visibility = 0 end
    if visibility > 1 then visibility = 1 end
    local restricted = Adapter:GetRestrictionState() ~= "OPEN"
    local selected
    if restricted then
        if visibility < 0.999 then
            return false, "appearance-element-fade-restricted-hide"
        end
        selected = state.selected == true
        local tab = state.targets and state.targets.tab
        if not tab or Adapter:CanCallProtected(tab) ~= true then
            return false, "appearance-element-fade-tab-unavailable"
        end
        if cancelNativeFade and type(UIFrameFadeRemoveFrame) == "function" then
            pcall(UIFrameFadeRemoveFrame, tab)
        end
        state.settingTabAlpha = true
        local tabOK = CallMethod(
            tab,
            "SetAlpha",
            selected and 1 or TAB_INACTIVE_ALPHA
        )
        state.settingTabAlpha = false
        if not tabOK then return false, "appearance-element-fade-tab-failed" end

        if state.frame == _G.ChatFrame2 then
            local tabText = state.targets.tabText
            local baseAlpha = state.snapshot and state.snapshot.tabTextAlpha
            if not tabText
                or not IsSafeValue(baseAlpha)
                or not IsFiniteNumber(baseAlpha)
                or Adapter:CanCallProtected(tabText) ~= true
            then
                return false, "appearance-element-fade-tab-text-unavailable"
            end
            state.settingTabTextAlpha = true
            local textOK = CallMethod(tabText, "SetAlpha", baseAlpha)
            state.settingTabTextAlpha = false
            if not textOK then
                return false, "appearance-element-fade-tab-text-failed"
            end
        end
    else
        local selectionReason
        selected, selectionReason = Adapter:IsAppearanceTabSelected(state.frame)
        if type(selected) ~= "boolean" then
            return false, selectionReason or "appearance-element-fade-selection-unavailable"
        end
    end
    if not restricted and cancelNativeFade then
        local synced, syncReason = SyncManagedTabVisuals(state, selected)
        if not synced then return false, syncReason end
    elseif not restricted and not SetManagedTabAlpha(
        state,
        selected and 1 or TAB_INACTIVE_ALPHA,
        false
    ) then
        return false, "appearance-element-fade-tab-failed"
    end

    local appearance = YChat:GetAppearance()
    local art = state.art
    if art then
        local backgroundAlpha = (appearance and appearance.backgroundAlpha or 0)
            * visibility
        if art.background and not SetElementFadeAlpha(
            art.background,
            backgroundAlpha,
            cancelNativeFade
        ) then
            return false, "appearance-element-fade-background-failed"
        end
        local borderAlpha = visibility
        if (art.top and not SetElementFadeAlpha(art.top, borderAlpha, cancelNativeFade))
            or (art.bottom and not SetElementFadeAlpha(art.bottom, borderAlpha, cancelNativeFade))
            or (art.left and not SetElementFadeAlpha(art.left, borderAlpha, cancelNativeFade))
            or (art.right and not SetElementFadeAlpha(art.right, borderAlpha, cancelNativeFade))
        then
            return false, "appearance-element-fade-border-failed"
        end
    end

    if state.targets and state.snapshot then
        local buttonsHidden = appearance and appearance.hideNativeButtons == true
        local buttonAlpha = buttonsHidden and 0 or visibility
        local buttonObjects = state.snapshot.buttonObjects or EMPTY_BUTTONS
        for index = 1, #buttonObjects do
            local button = buttonObjects[index].button
            local targetAlpha = button == state.targets.scrollToBottomButton
                and (buttonsHidden and 0 or 0.65 * visibility)
                or buttonAlpha
            if not SetElementFadeAlpha(button, targetAlpha, cancelNativeFade) then
                return false, "appearance-element-fade-button-failed"
            end
        end
        local scrollAlpha = buttonsHidden and 0 or 0.6 * visibility
        local scrollObjects = state.snapshot.scrollObjects or EMPTY_BUTTONS
        for index = 1, #scrollObjects do
            if not SetElementFadeAlpha(
                scrollObjects[index].button,
                scrollAlpha,
                cancelNativeFade
            ) then
                return false, "appearance-element-fade-scroll-failed"
            end
        end
        if state.frame == _G.ChatFrame1 then
            local dock = _G.GENERAL_CHAT_DOCK or _G.GeneralDockManager
            local overflowButton = dock and dock.overflowButton
            if overflowButton
                and not SetElementFadeAlpha(
                    overflowButton,
                    visibility,
                    cancelNativeFade
                )
            then
                return false, "appearance-element-fade-overflow-failed"
            end
        end
    end

    return true
end

function Appearance:OnMessage(frame)
    if not self.enabled or activeAnimations > 32 then return end
    local state = frameStates[frame]
    if not state
        or state.applied ~= true
        or YChat.Shadow.qualityState ~= "Q0"
        or state.effect == "none"
        or state.selected == true
    then
        return
    end

    local fade = state.effect == "fade"
    local group = fade and state.art.fadeGroup or state.art.glowGroup
    if state.activeAnimation then StopAnimation(state) end
    if fade then
        if not CallMethod(state.art.glow, "Hide") then return end
    elseif not CallMethod(state.art.glow, "Show") then
        return
    end
    state.activeAnimation = group
    activeAnimations = activeAnimations + 1
    if not CallMethod(group, "Play") then OnAnimationStopped(group) end
end

function Appearance:GetRuntimeGauges(target)
    target = target or {}
    RefreshGauges()
    target.managedFrames = self.managedFrames or 0
    target.pendingRestores = self.restorePending or 0
    target.activeAnimations = activeAnimations
    target.activeDrivers = 0
    target.activeTickers = 0
    target.activeTimers = 0
    target.capturedFrames = capturedFrames
    target.appearanceOnlyTabs = capturedAppearanceTabs
    target.allocatedTextures = allocatedTextures
    target.allocatedAnimationGroups = allocatedAnimationGroups
    target.appearanceTargetGeneration = targetGeneration
    target.appearanceTargetRebinds = targetRebindCount
    target.appearanceDomainFailures = domainFailureCount
    target.appearanceSuspendedDomains = self.suspendedDomains or 0
    target.appearanceEnabled = self.enabled == true
    target.appearanceMutationPaused = self.mutationPaused == true
    target.appearanceRefreshPending = self.mutationRefreshPending == true
        or self.nativeSettleActive == true
    target.appearanceLastFailure = self.lastMutationFailure
    target.appearanceLastFailureDomain = self.lastMutationDomain
    target.nativeSettlePending = self.nativeSettleActive and 1 or 0
    target.nativeSettleFrames = self.nativeSettleFramesRemaining or 0
    target.tooltipReady = self.tooltipAvailable == true
    target.tooltipCleanupPending = Adapter.tooltipCleanupPending and 1 or 0
    if YChat.CombatLog and type(YChat.CombatLog.GetRuntimeGauges) == "function" then
        YChat.CombatLog:GetRuntimeGauges(target)
    end
    if YChat.CopyViewer and type(YChat.CopyViewer.GetRuntimeGauges) == "function" then
        YChat.CopyViewer:GetRuntimeGauges(target)
    end
    if YChat.MainLayout and type(YChat.MainLayout.GetRuntimeGauges) == "function" then
        YChat.MainLayout:GetRuntimeGauges(target)
    end
    return target
end

function Appearance:QuiesceAnimations()
    for _, state in pairs(frameStates) do StopAnimation(state) end
    return activeAnimations == 0
end

local function NativeTabRegionsSuppressed(state)
    if not state or state.applied ~= true then return false end
    local snapshot = state.snapshot
    local regions = snapshot and snapshot.tabRegions
    if type(regions) ~= "table" then return false end
    for index = 1, #regions do
        local region = regions[index].region
        local textureOK, texture = pcall(region.GetTexture, region)
        local alphaOK, alpha = pcall(region.GetAlpha, region)
        if not textureOK
            or not alphaOK
            or texture ~= nil
            or alpha ~= 0
        then
            return false
        end
    end
    return true
end

function Appearance:GetAcceptanceSnapshot(target)
    target = target or {}
    local captured = 0
    local managed = 0
    local managedTabs = 0
    local suppressedTabs = 0
    local pending = 0
    local inputMatches = 0
    local failed = 0
    local appearanceOnlyTabs = 0
    local appearance = YChat:GetAppearance()

    for _, state in pairs(frameStates) do
        captured = captured + 1
        if state.applied then
            managed = managed + 1
            managedTabs = managedTabs + 1
            if NativeTabRegionsSuppressed(state) then
                suppressedTabs = suppressedTabs + 1
            end
            if appearance
                and InputPositionMatches(
                    state.targets,
                    appearance.inputPosition,
                    appearance.inputHeight
                )
            then
                inputMatches = inputMatches + 1
            end
        end
        if state.restorePending then pending = pending + 1 end
    end
    for _, state in pairs(tabOnlyStates) do
        appearanceOnlyTabs = appearanceOnlyTabs + 1
        if state.applied then
            managedTabs = managedTabs + 1
            if NativeTabRegionsSuppressed(state) then
                suppressedTabs = suppressedTabs + 1
            end
        end
        if state.restorePending then pending = pending + 1 end
    end
    for _ in pairs(allocationFailures) do failed = failed + 1 end
    if Adapter.tooltipCleanupPending then pending = pending + 1 end

    target.capturedFrames = captured
    target.appearanceOnlyTabs = appearanceOnlyTabs
    target.managedFrames = managed
    target.managedTabs = managedTabs
    target.nativeTabsSuppressed = suppressedTabs
    target.pendingRestores = pending
    target.inputMatches = inputMatches
    target.allocationFailures = failed
    target.allocatedTextures = allocatedTextures
    target.allocatedAnimationGroups = allocatedAnimationGroups
    target.targetGeneration = targetGeneration
    target.targetRebinds = targetRebindCount
    target.domainFailures = domainFailureCount
    target.suspendedDomains = self.suspendedDomains or 0
    target.nativeSettlePending = self.nativeSettleActive and 1 or 0
    target.mutationPaused = self.mutationPaused == true
    target.refreshPending = self.mutationRefreshPending == true
        or self.nativeSettleActive == true
    target.lastMutationFailure = self.lastMutationFailure
    target.lastMutationFailureDomain = self.lastMutationDomain
    target.activeAnimations = activeAnimations
    target.tooltipReady = self.tooltipAvailable == true
    return target
end

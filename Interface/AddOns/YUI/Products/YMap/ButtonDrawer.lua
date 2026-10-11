local YUI = _G.YUI
if not YUI or not YUI.YMap then return end

local YMap = YUI.YMap
local GUI2 = YUI.GUI2
local Event = YUI.Event
local Animation = YUI.Animation
local Unpack = _G.unpack or table.unpack

local ButtonDrawer = {}
YMap.ButtonDrawer = ButtonDrawer
ButtonDrawer.itemBackings = ButtonDrawer.itemBackings
    or setmetatable({}, { __mode = "k" })
ButtonDrawer.itemBorders = ButtonDrawer.itemBorders
    or setmetatable({}, { __mode = "k" })

local DEFAULTS = {
    enabled = true,
    iconSize = 28,
    spacingX = 4,
    spacingY = 4,
    expandMode = "hoverIcon",
    layoutDirection = "rightDown",
    itemsPerLine = 8,
    panelBackground = "transparent",
    panelPadding = 4,
    triggerSize = 20,
    triggerVisibility = "always",
    triggerPosition = "bottomRight",
    triggerOffsetX = 2,
    triggerOffsetY = 2,
}

local ADDON_LOAD_DEBOUNCE = 0.25
local HOVER_CLOSE_DELAY = 1.5
local PANEL_ANIMATION_DURATION = 0.2
local DISCOVERY_EVENT = "YUI_YMAP_BUTTON_DISCOVERY"
local LAYOUT_EVENT = "YUI_YMAP_BUTTON_LAYOUT"
local RECOVERY_EVENT = "YUI_YMAP_BUTTON_RECOVERY"
local MAX_ITEMS_PER_LINE = 16
local CLOSE_PROGRESS_HEIGHT = 2
local DRAWER_FRAME_STRATA = "DIALOG"
local DRAWER_BACKGROUND_STRATA = "HIGH"
local DRAWER_FRAME_LEVEL = 20
local MODULE_ID = "product:ymap"

ButtonDrawer.LAYOUT_DIRECTIONS = {
    rightDown = { vertical = false, reverseX = false, reverseY = false },
    leftDown = { vertical = false, reverseX = true, reverseY = false },
    rightUp = { vertical = false, reverseX = false, reverseY = true },
    leftUp = { vertical = false, reverseX = true, reverseY = true },
    downRight = { vertical = true, reverseX = false, reverseY = false },
    downLeft = { vertical = true, reverseX = true, reverseY = false },
    upRight = { vertical = true, reverseX = false, reverseY = true },
    upLeft = { vertical = true, reverseX = true, reverseY = true },
}

ButtonDrawer.TRIGGER_ICON_ATLAS = "ParagonReputation_Bag"
ButtonDrawer.TRIGGER_ICON_RATIO = 0.7
ButtonDrawer.LAYOUT_ID = "yui.product.ymap.buttonDrawer"
ButtonDrawer.LAYOUT_ANCHOR_NAME = "YMapMinimapHolder"
ButtonDrawer.LAYOUT_ANCHOR_MIGRATION_VERSION = 1
ButtonDrawer.DEFAULT_LAYOUT_OFFSET = 10
ButtonDrawer.PANEL_SLIDE_DISTANCE = 20
ButtonDrawer.LEGACY_DECORATION_TEXTURE_IDS = {
    [136430] = true,
    [136467] = true,
    [136477] = true,
}
ButtonDrawer.LEGACY_DECORATION_TEXTURE_PATTERNS = {
    "interface\\characterframe",
    "interface\\minimap",
    "border",
    "background",
    "alphamask",
}

local ownershipToken = {}
local eventOwner = {}
local regenOwner = {}
local recoveryOwner = {}
local libDBIconOwner = {}
local panelAnimationOwner = {}
local progressAnimationOwner = {}
local helpTipAnchorOwner = {}

local active = false
local panel
local background
local trigger
local triggerIcon
local backgroundTexture
local closeProgress
local closeProgressTexture
local hoverCloseTimer
local libDBIconLibrary
local minimapHooksInstalled = false
local transitionToken = 0
local progressToken = 0
local settingsPreviewActive = false
local settingsPreviewPanelWasShown = false

local snapshots = setmetatable({}, { __mode = "k" })
local captured = setmetatable({}, { __mode = "k" })
local hookedButtons = setmetatable({}, { __mode = "k" })
local hookedLandingButtons = setmetatable({}, { __mode = "k" })
local seenCandidates = setmetatable({}, { __mode = "k" })
local ignoredObjects = setmetatable({}, { __mode = "k" })
local allowedParents = setmetatable({}, { __mode = "k" })
ButtonDrawer.hookedLayeredLogoButtons = ButtonDrawer.hookedLayeredLogoButtons
    or setmetatable({}, { __mode = "k" })

local externalButtons = {}
local slotFrames = {}
local buttonWriteGuard = false
local landingRefreshGuard = false
local nativeLandingRefreshRequested = false

local pendingAction
local pendingReason

local stats = {
    enabled = false,
    buttonDiscoveryScans = 0,
    capturedButtons = 0,
    restoreFailures = 0,
    pendingRefresh = false,
    externalButtons = 0,
    compartmentButtons = 0,
    compartmentEntries = 0,
    skippedCandidates = 0,
    ownershipLosses = 0,
    panelShown = false,
    transitionState = "parked",
    animationActive = false,
    compartmentHidden = false,
    drawerHoverCloseTimerActive = false,
    styledLibDBIcons = 0,
    styledLandingButtons = 0,
    visualRestoreFailures = 0,
    interactiveButtons = 0,
    mouseStateRepairs = 0,
    inputRestoreFailures = 0,
    settingsPreviewActive = false,
    lastReason = nil,
}

local NATIVE_NAMES = {
    AddonCompartmentFrame = true,
    FeedbackUIButton = true,
    GameTimeFrame = true,
    GuildInstanceDifficulty = true,
    HelpOpenTicketButton = true,
    LFGMinimapFrame = true,
    MiniMapBattlefieldFrame = true,
    MiniMapChallengeMode = true,
    MiniMapInstanceDifficulty = true,
    MiniMapLFGFrame = true,
    MiniMapMailFrame = true,
    MiniMapTracking = true,
    MiniMapTrackingButton = true,
    MiniMapWorldMapButton = true,
    MinimapBackdrop = true,
    MinimapCompassTexture = true,
    MinimapZoneTextButton = true,
    MinimapZoomIn = true,
    MinimapZoomOut = true,
    QueueStatusButton = true,
    QueueStatusMinimapButton = true,
    TimeManagerClockButton = true,
}

local LANDING_PAGE_NAMES = {
    ExpansionLandingPageMinimapButton = true,
    GarrisonLandingPageMinimapButton = true,
}

local LANDING_PAGE_NAME_SUFFIX = "LandingPageMinimapButton"

local LANDING_PAGE_DECORATION_KEYS = {
    "LoopingGlow",
    "CircleGlow",
    "SoftButtonGlow",
    "SideToastGlow",
    "AlertBG",
    "AlertText",
}

local LANDING_PAGE_ANIMATION_KEYS = {
    "MinimapLoopPulseAnim",
    "MinimapPulseAnim",
    "MinimapAlertAnim",
}

local LANDING_PAGE_REFRESH_METHODS = {
    "SetLandingPageIconFromAtlases",
    "UpdateIcon",
    "RefreshButton",
    "TriggerPulseLock",
    "TriggerAlert",
    "HidePulse",
    "ClearPulses",
}


local function ClearTable(target)
    for key in pairs(target) do
        target[key] = nil
    end
end

local function ClampNumber(value, fallback, minimum, maximum)
    value = tonumber(value)
    if type(value) ~= "number" then value = fallback end
    if value < minimum then value = minimum end
    if value > maximum then value = maximum end
    return value
end

local function CallMethod(object, methodName, ...)
    local method = object and object[methodName]
    if type(method) ~= "function" then return false end
    return pcall(method, object, ...)
end

local function UnlockButtonLayers(button)
    local success = true
    local ok, fixed = CallMethod(button, "HasFixedFrameStrata")
    if ok and fixed == true then
        success = CallMethod(button, "SetFixedFrameStrata", false)
    end
    ok, fixed = CallMethod(button, "HasFixedFrameLevel")
    if ok and fixed == true then
        if not CallMethod(button, "SetFixedFrameLevel", false) then success = false end
    end
    return success
end

function ButtonDrawer:_WriteMouseState(frame, enabled, countRepair)
    if not frame then return false end
    enabled = enabled == true
    local success = true
    local changed = false

    local ok, current = CallMethod(frame, "IsMouseEnabled")
    if ok and current ~= enabled then
        changed = true
        if not CallMethod(frame, "EnableMouse", enabled) then success = false end
    elseif not ok and type(frame.EnableMouse) == "function" then
        changed = true
        if not CallMethod(frame, "EnableMouse", enabled) then success = false end
    end

    ok, current = CallMethod(frame, "IsMouseMotionEnabled")
    if ok and current ~= enabled then
        changed = true
        if not CallMethod(frame, "SetMouseMotionEnabled", enabled) then success = false end
    end

    ok, current = CallMethod(frame, "IsMouseClickEnabled")
    if ok and current ~= enabled then
        changed = true
        if not CallMethod(frame, "SetMouseClickEnabled", enabled) then success = false end
    end

    if changed and countRepair then
        stats.mouseStateRepairs = stats.mouseStateRepairs + 1
    end
    return success
end

function ButtonDrawer:_RestoreInputState(frame, snapshot)
    if not frame or not snapshot then return true end
    local success = true
    local methods = snapshot.methods or {}
    local wasGuarded = buttonWriteGuard
    buttonWriteGuard = true
    local function restore(methodName, value)
        if value == nil then return end
        if type(methods[methodName]) ~= "function" or frame[methodName] ~= methods[methodName] then
            success = false
            return
        end
        if not CallMethod(frame, methodName, value) then success = false end
    end
    restore("EnableMouse", snapshot.mouseEnabled)
    restore("SetMouseMotionEnabled", snapshot.mouseMotionEnabled)
    restore("SetMouseClickEnabled", snapshot.mouseClickEnabled)
    buttonWriteGuard = wasGuarded
    if not success then stats.inputRestoreFailures = stats.inputRestoreFailures + 1 end
    return success
end

function ButtonDrawer:_IsPanelInputEnabled()
    local state = stats.transitionState
    return active and stats.panelShown == true and state ~= "closing" and state ~= "parked"
end

function ButtonDrawer:_SetDrawerInputEnabled(enabled, countRepair)
    enabled = enabled == true
    local interactive = 0
    local wasGuarded = buttonWriteGuard
    buttonWriteGuard = true
    for index = 1, #externalButtons do
        local button = externalButtons[index]
        if captured[button] == ownershipToken then
            self:_WriteMouseState(button, enabled, countRepair)
            local shownOK, shown = CallMethod(button, "IsShown")
            if enabled and shownOK and shown == true then interactive = interactive + 1 end
        end
    end
    buttonWriteGuard = wasGuarded
    stats.interactiveButtons = interactive
end

local function IsNativeLandingPageButton(button, name)
    if type(name) == "string" and LANDING_PAGE_NAMES[name] then return true end
    return button ~= nil and (
        button == _G.ExpansionLandingPageMinimapButton
        or button == _G.GarrisonLandingPageMinimapButton
    )
end

local function GetLandingPageRole(button, name)
    if IsNativeLandingPageButton(button, name) then return "native" end
    if type(name) == "string"
        and name:sub(-#LANDING_PAGE_NAME_SUFFIX) == LANDING_PAGE_NAME_SUFFIX
    then
        return "replacement"
    end
    return nil
end

local function IsLandingPageButton(button, name)
    return GetLandingPageRole(button, name) ~= nil
end

function ButtonDrawer:_IsLayeredLogoButton(button)
    return button ~= nil
        and button.Background ~= nil
        and button.Color ~= nil
        and button.Bling ~= nil
        and button.Bling.animScale ~= nil
        and type(button.SetBackground) == "function"
end

local function GetLibDBIcon()
    local libStub = _G.LibStub
    if not libStub then return nil end
    local ok, library = pcall(libStub, "LibDBIcon-1.0", true)
    if ok and type(library) == "table" then return library end
    return nil
end

local function IsInCombat()
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true
end

local function GetConfig()
    if type(YMap.GetDB) == "function" then
        local ok, db = pcall(YMap.GetDB, YMap)
        if ok and type(db) == "table" and type(db.buttonDrawer) == "table" then
            return db.buttonDrawer
        end
    end
    return DEFAULTS
end

function ButtonDrawer:_IsExpansionEntryHidden()
    if type(YMap.GetDB) ~= "function" then return false end
    local ok, db = pcall(YMap.GetDB, YMap)
    if not ok or type(db) ~= "table" then return false end
    local minimap = db.minimap
    if type(minimap) ~= "table" or minimap.style ~= "square" then return false end
    local elements = minimap.squareElements
    local expansion = type(elements) == "table" and elements.expansion or nil
    return type(expansion) == "table" and expansion.hidden == true
end

local function GetText(key, fallback)
    if type(YMap.T) == "function" then
        local ok, value = pcall(YMap.T, YMap, key)
        if ok and type(value) == "string" and value ~= "" and value ~= key then
            return value
        end
    end
    return fallback
end

function ButtonDrawer.GetDefaultLayoutPlacement()
    return {
        version = 2,
        anchor = {
            point = "TOP",
            relative = ButtonDrawer.LAYOUT_ANCHOR_NAME,
            relativePoint = "BOTTOM",
        },
        offset = { x = 0, y = -ButtonDrawer.DEFAULT_LAYOUT_OFFSET },
    }
end

function ButtonDrawer.GetPanelDirection()
    local holder = ButtonDrawer.layoutHolder
    local minimap = _G.Minimap
    local holderOK, holderX, holderY = CallMethod(holder, "GetCenter")
    local minimapOK, minimapX, minimapY = CallMethod(minimap, "GetCenter")
    if holderOK and minimapOK
        and type(holderX) == "number" and type(holderY) == "number"
        and type(minimapX) == "number" and type(minimapY) == "number"
    then
        local deltaX = holderX - minimapX
        local deltaY = holderY - minimapY
        if math.abs(deltaX) > math.abs(deltaY) then
            return deltaX < 0 and "left" or "right"
        end
        return deltaY > 0 and "top" or "bottom"
    end
    local direction = ButtonDrawer.LAYOUT_DIRECTIONS[GetConfig().layoutDirection]
    return direction and direction.vertical and "right" or "bottom"
end

function ButtonDrawer.GetLayoutMoverBounds()
    local holder = ButtonDrawer.layoutHolder
    local width = holder and holder.GetWidth and holder:GetWidth() or 24
    local height = holder and holder.GetHeight and holder:GetHeight() or 24
    return math.max(tonumber(width) or 24, 24), math.max(tonumber(height) or 24, 24), 0, 0
end

function ButtonDrawer.OpenLayoutSettings()
    if type(YMap.OpenSettings) == "function" then
        return YMap:OpenSettings()
    end
    return false
end

function ButtonDrawer.IsLayoutEnabled()
    return active == true and GetConfig().enabled == true
end

function ButtonDrawer:_ApplyDefaultLayoutHolderPlacement()
    local holder = self.layoutHolder
    local anchorFrame = _G[self.LAYOUT_ANCHOR_NAME] or _G.Minimap
    if not holder or not anchorFrame then return false end
    local placement = self.GetDefaultLayoutPlacement()
    local anchor = placement.anchor
    local offset = placement.offset
    holder:ClearAllPoints()
    holder:SetPoint(anchor.point, anchorFrame, anchor.relativePoint, offset.x, offset.y)
    return true
end

function ButtonDrawer:_MigrateLayoutAnchor()
    local db = type(YMap.GetDB) == "function" and YMap:GetDB() or nil
    if type(db) ~= "table" then return false end
    db.migrations = type(db.migrations) == "table" and db.migrations or {}
    if (tonumber(db.migrations.buttonDrawerAnchor) or 0) >= self.LAYOUT_ANCHOR_MIGRATION_VERSION then
        return false
    end

    local layout = YUI.Layout
    if not (layout and type(layout.GetPlacement) == "function" and type(layout.SetPlacement) == "function") then
        return false
    end
    local placement = layout:GetPlacement(self.LAYOUT_ID)
    if not placement then return false end
    local anchor = type(placement.anchor) == "table" and placement.anchor or nil
    if anchor and anchor.relative == "Minimap" then
        anchor.relative = self.LAYOUT_ANCHOR_NAME
        if layout:SetPlacement(self.LAYOUT_ID, placement, true) ~= true then
            return false
        end
    end
    db.migrations.buttonDrawerAnchor = self.LAYOUT_ANCHOR_MIGRATION_VERSION
    return true
end

function ButtonDrawer:_EnsureLayoutHolder()
    if self.layoutHolder then return self.layoutHolder end
    if not GUI2 or type(GUI2.CreateFrame) ~= "function" or not _G.UIParent then return nil end
    self.layoutHolder = GUI2:CreateFrame(_G.UIParent, {
        name = "YUI_YMap_ButtonDrawerLayoutHolder",
        width = 24,
        height = 24,
        frameStrata = "LOW",
        frameLevel = 1,
        mouse = false,
        clamped = true,
        hidden = true,
    })
    if self.layoutHolder then
        self.layoutHolder:EnableMouse(false)
        self:_ApplyDefaultLayoutHolderPlacement()
    end
    return self.layoutHolder
end

function ButtonDrawer:_RegisterLayoutHolder()
    local holder = self:_EnsureLayoutHolder()
    local layout = YUI.Layout
    if not holder then return false end
    if not layout or type(layout.RegisterFrame) ~= "function" then
        self:_ApplyDefaultLayoutHolderPlacement()
        return false
    end
    self.layoutSpec = self.layoutSpec or {
        placementStorage = YMap.PlacementStorage,
        category = "product",
        defaultPlacement = self.GetDefaultLayoutPlacement,
        combatProtected = false,
        movable = true,
        snap = true,
        anchorTargets = { "UIParent", "YMapMinimapHolder" },
        showOnlyInEditMode = true,
        minWidth = 24,
        minHeight = 24,
        getMoverBounds = self.GetLayoutMoverBounds,
        openPluginSettings = self.OpenLayoutSettings,
        isEnabled = self.IsLayoutEnabled,
    }
    self.layoutSpec.frame = holder
    self.layoutSpec.title = GetText("layout.button_drawer", "Minimap Button Drawer")
    self.layoutRegistered = layout:RegisterFrame(self.LAYOUT_ID, self.layoutSpec) ~= nil
    if self.layoutRegistered then
        self:_MigrateLayoutAnchor()
    end
    return self.layoutRegistered
end

function ButtonDrawer:_SyncLayoutHolder(width, height)
    local holder = self:_EnsureLayoutHolder()
    if not holder then return nil end
    width = math.max(tonumber(width) or 24, 24)
    height = math.max(tonumber(height) or 24, 24)
    local sizeChanged = holder:GetWidth() ~= width or holder:GetHeight() ~= height
    if sizeChanged then holder:SetSize(width, height) end

    local layout = YUI.Layout
    if not self.layoutRegistered then
        self:_RegisterLayoutHolder()
    elseif not layout then
        self:_ApplyDefaultLayoutHolderPlacement()
    end
    if sizeChanged
        and self.layoutRegistered
        and layout
        and type(layout.RefreshFrame) == "function"
    then
        layout:RefreshFrame(self.LAYOUT_ID)
    end
    return holder
end

function ButtonDrawer:_UnregisterLayoutHolder()
    local layout = YUI.Layout
    if self.layoutRegistered and layout and type(layout.UnregisterFrame) == "function" then
        layout:UnregisterFrame(self.LAYOUT_ID)
    end
    self.layoutRegistered = false
    if self.layoutHolder then self.layoutHolder:Hide() end
end

local function SetSharedStat(field, value)
    local shared = YMap.Stats
    if shared and type(shared.Set) == "function" then
        shared:Set(field, value)
    elseif type(shared) == "table" and shared[field] ~= nil then
        shared[field] = value
    end
end

local function IncrementSharedStat(field, amount)
    local shared = YMap.Stats
    if shared and type(shared.Increment) == "function" then
        shared:Increment(field, amount)
    elseif type(shared) == "table" and type(shared[field]) == "number" then
        shared[field] = shared[field] + (amount or 1)
    end
end

local function SetEnabledStat(value)
    stats.enabled = value == true
end

local function SetPendingStat(value)
    stats.pendingRefresh = value == true
    SetSharedStat("pendingRefresh", stats.pendingRefresh)
end

local function SetCapturedStat(value)
    stats.capturedButtons = value
    SetSharedStat("capturedButtons", value)
end

local function SetHoverTimerStat(value)
    stats.drawerHoverCloseTimerActive = value == true
    SetSharedStat("drawerHoverCloseTimerActive", stats.drawerHoverCloseTimerActive)
    SetSharedStat("drawerCloseTimerActive", stats.drawerHoverCloseTimerActive)
end

local function SetTransitionState(value)
    stats.transitionState = value or "parked"
    SetSharedStat("drawerTransitionState", stats.transitionState)
end

local function SetAnimationStat(value)
    stats.animationActive = value == true
    SetSharedStat("drawerAnimationActive", stats.animationActive)
end

local function IncrementScanStat()
    stats.buttonDiscoveryScans = stats.buttonDiscoveryScans + 1
    IncrementSharedStat("buttonDiscoveryScans", 1)
end

local function IncrementVisualRestoreFailure()
    stats.visualRestoreFailures = stats.visualRestoreFailures + 1
    IncrementSharedStat("drawerVisualRestoreFailures", 1)
end

local function IncrementRestoreFailure()
    stats.restoreFailures = stats.restoreFailures + 1
    IncrementSharedStat("restoreFailures", 1)
end

local function IsHoverMode()
    local mode = GetConfig().expandMode
    return mode == "hoverIcon" or mode == "hoverPanel"
end

local function IsFrameShown(frame)
    local ok, shown = CallMethod(frame, "IsShown")
    return ok and shown == true
end

local function GetFrameParent(frame)
    local ok, parent = CallMethod(frame, "GetParent")
    if ok then return parent end
    return nil
end

local MaybeHideHoverPanel
local LayoutPanel

local function StopAnimationOwner(owner)
    if Animation and type(Animation.StopOwner) == "function" then
        pcall(Animation.StopOwner, Animation, owner, false)
    end
end

local function ShouldAnimate(target)
    if not Animation or type(Animation.Play) ~= "function" then return false end
    if GUI2 and type(GUI2.ShouldAnimateControl) == "function" then
        local ok, allowed = pcall(GUI2.ShouldAnimateControl, GUI2, target, {
            duration = PANEL_ANIMATION_DURATION,
        })
        if not ok or allowed ~= true then return false end
    end
    return true
end

local function StopCloseProgress()
    progressToken = progressToken + 1
    StopAnimationOwner(progressAnimationOwner)
    if closeProgress then
        CallMethod(closeProgress, "Hide")
        CallMethod(closeProgress, "SetScale", 1)
    end
end

local function StartCloseProgress()
    if not closeProgress or not background or not ShouldAnimate(closeProgress) then return end
    StopCloseProgress()
    progressToken = progressToken + 1
    local token = progressToken
    local _, width = CallMethod(background, "GetWidth")
    width = tonumber(width) or 1
    closeProgress:ClearAllPoints()
    closeProgress:SetPoint("BOTTOMLEFT", background, "BOTTOMLEFT", 0, 0)
    closeProgress:SetSize(math.max(width, 1), CLOSE_PROGRESS_HEIGHT)
    closeProgress:SetScale(1)
    closeProgress:SetAlpha(1)
    closeProgress:Show()
    local handle = Animation:Play(closeProgress, {
        driver = "native",
        owner = progressAnimationOwner,
        key = "drawer-close-progress",
        mode = "replace",
        duration = HOVER_CLOSE_DELAY,
        easing = "linear",
        effects = {
            {
                type = "scale",
                fromScaleX = 1,
                fromScaleY = 1,
                toScaleX = 0,
                toScaleY = 1,
                origin = "LEFT",
            },
        },
        onFinished = function(_, _, finished)
            if finished and token == progressToken and closeProgress then
                closeProgress:Hide()
                closeProgress:SetScale(1)
            end
        end,
    })
    if not handle or handle.noop then
        closeProgress:Hide()
    end
end

local function CancelHoverClose()
    local timer = hoverCloseTimer
    hoverCloseTimer = nil
    SetHoverTimerStat(false)
    if timer and type(timer.Cancel) == "function" then
        pcall(timer.Cancel, timer)
    end
    StopCloseProgress()
end

local function OnHoverCloseTimer()
    hoverCloseTimer = nil
    SetHoverTimerStat(false)
    StopCloseProgress()
    if MaybeHideHoverPanel then MaybeHideHoverPanel() end
end

local function ScheduleHoverClose()
    if settingsPreviewActive then
        CancelHoverClose()
        return
    end
    if not active or not IsHoverMode() or stats.panelShown ~= true then
        CancelHoverClose()
        return
    end
    CancelHoverClose()
    local timerAPI = _G.C_Timer
    if timerAPI and type(timerAPI.NewTimer) == "function" then
        local ok, timer = pcall(timerAPI.NewTimer, HOVER_CLOSE_DELAY, OnHoverCloseTimer)
        if ok and timer then
            hoverCloseTimer = timer
            SetHoverTimerStat(true)
            StartCloseProgress()
            return
        end
    end
    OnHoverCloseTimer()
end

local function StopPanelAnimation()
    transitionToken = transitionToken + 1
    StopAnimationOwner(panelAnimationOwner)
    SetAnimationStat(false)
end

local function ParkPanel()
    if not panel then return end
    ButtonDrawer:_SetDrawerInputEnabled(false)
    panel:EnableMouse(false)
    CallMethod(panel, "SetMouseMotionEnabled", false)
    CallMethod(panel, "SetMouseClickEnabled", false)
    panel:SetAlpha(0)
    CallMethod(panel, "SetClampedToScreen", false)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", _G.UIParent, "BOTTOMRIGHT", 1000, -1000)
    panel:Show()
    SetTransitionState("parked")
    ButtonDrawer:_UpdatePanelHotspot()
end

local function SettlePanelOpen()
    if not panel then return end
    CallMethod(panel, "SetClampedToScreen", true)
    panel:SetAlpha(1)
    panel:EnableMouse(false)
    CallMethod(panel, "SetMouseMotionEnabled", false)
    CallMethod(panel, "SetMouseClickEnabled", false)
    ButtonDrawer:_SetDrawerInputEnabled(true)
    panel:Show()
    SetTransitionState("open")
    ButtonDrawer:_UpdatePanelHotspot()
end

local function GetPanelSlideOffset()
    local distance = ButtonDrawer.PANEL_SLIDE_DISTANCE
    local position = ButtonDrawer.GetPanelDirection()
    if position == "top" then
        return 0, -distance
    elseif position == "left" then
        return distance, 0
    elseif position == "right" then
        return -distance, 0
    end
    return 0, distance
end

function ButtonDrawer:_OffsetPanelAnchor(xOffset, yOffset)
    if not panel or (xOffset == 0 and yOffset == 0) then return true end
    local ok, point, relativeTo, relativePoint, x, y = CallMethod(panel, "GetPoint", 1)
    if not ok or not point then return false end
    panel:ClearAllPoints()
    panel:SetPoint(
        point,
        relativeTo,
        relativePoint,
        (tonumber(x) or 0) + xOffset,
        (tonumber(y) or 0) + yOffset
    )
    return true
end

local function PlayPanelTransition(opening)
    if not panel then return end
    StopPanelAnimation()
    if LayoutPanel then LayoutPanel(true) end
    if opening and stats.panelShown ~= true then
        ParkPanel()
        return
    end
    transitionToken = transitionToken + 1
    local token = transitionToken
    local fromX, fromY = 0, 0
    if GetConfig().expandMode ~= "hoverPanel" then
        fromX, fromY = GetPanelSlideOffset()
    end
    if not ShouldAnimate(panel) then
        if opening then
            if LayoutPanel then LayoutPanel(true) end
            SettlePanelOpen()
        else
            ParkPanel()
        end
        return
    end

    panel:Show()
    if opening then
        ButtonDrawer:_SetDrawerInputEnabled(true)
        panel:SetAlpha(0)
        ButtonDrawer:_OffsetPanelAnchor(fromX, fromY)
        SetTransitionState("opening")
        ButtonDrawer:_UpdatePanelHotspot()
    else
        panel:SetAlpha(1)
        ButtonDrawer:_SetDrawerInputEnabled(false)
        SetTransitionState("closing")
        ButtonDrawer:_UpdatePanelHotspot()
    end
    SetAnimationStat(true)

    local effects = {
        { type = "alpha", from = opening and 0 or 1, to = opening and 1 or 0 },
    }
    if fromX ~= 0 or fromY ~= 0 then
        effects[#effects + 1] = opening and {
            type = "translation",
            fromX = fromX,
            fromY = fromY,
            toX = 0,
            toY = 0,
        } or {
            type = "translation",
            fromX = 0,
            fromY = 0,
            toX = fromX,
            toY = fromY,
        }
    end

    local handle = Animation:Play(panel, {
        driver = "native",
        owner = panelAnimationOwner,
        key = "drawer-panel",
        mode = "replace",
        duration = PANEL_ANIMATION_DURATION,
        easing = "out",
        effects = effects,
        onFinished = function(_, _, finished)
            if token ~= transitionToken then return end
            SetAnimationStat(false)
            if not finished or stats.panelShown ~= opening then return end
            if opening then
                if LayoutPanel then LayoutPanel(true) end
                SettlePanelOpen()
            else
                ParkPanel()
            end
        end,
    })
    if not handle or handle.noop then
        SetAnimationStat(false)
        if opening then
            if LayoutPanel then LayoutPanel(true) end
            SettlePanelOpen()
        else
            ParkPanel()
        end
    end
end

local function SetPanelShown(shown, animate)
    if settingsPreviewActive and active and stats.capturedButtons > 0 then shown = true end
    shown = shown == true and active and stats.capturedButtons > 0
    CancelHoverClose()
    local state = stats.transitionState
    if stats.panelShown == shown then
        if shown and (state == "open" or state == "opening") then
            ButtonDrawer:_UpdatePanelHotspot()
            return
        end
        if not shown and (state == "parked" or state == "closing") then
            ButtonDrawer:_UpdatePanelHotspot()
            return
        end
    end
    stats.panelShown = shown
    if shown then
        if LayoutPanel then LayoutPanel(true) end
        if animate == false then
            StopPanelAnimation()
            SettlePanelOpen()
        else
            PlayPanelTransition(true)
        end
    else
        if animate == false then
            StopPanelAnimation()
            ParkPanel()
        else
            PlayPanelTransition(false)
        end
    end
end

function ButtonDrawer:_UpdatePanelHotspot()
    local hotspot = self.panelHotspot
    if not hotspot then return end
    local config = GetConfig()
    local holder = self.layoutHolder
    local shouldShow = active
        and config.enabled == true
        and config.expandMode == "hoverPanel"
        and stats.capturedButtons > 0
        and stats.panelShown ~= true
        and stats.transitionState == "parked"
        and holder ~= nil
    if not shouldShow then
        hotspot:Hide()
        return
    end

    hotspot:ClearAllPoints()
    hotspot:SetPoint("CENTER", holder, "CENTER", 0, 0)
    hotspot:SetSize(
        math.max(tonumber(holder:GetWidth()) or 24, 24),
        math.max(tonumber(holder:GetHeight()) or 24, 24)
    )
    hotspot:Show()
end

local function AnyItemMouseOver()
    for index = 1, #externalButtons do
        local button = externalButtons[index]
        if captured[button] == ownershipToken then
            local ok, over = CallMethod(button, "IsMouseOver")
            if ok and over == true then return true end
        end
    end
    return false
end

MaybeHideHoverPanel = function()
    if settingsPreviewActive or not active or not IsHoverMode() then return end
    local triggerOver = trigger and trigger:IsMouseOver()
    local bridgeOver = background and background:IsMouseOver()
    local hotspot = ButtonDrawer.panelHotspot
    local hotspotOver = hotspot and hotspot:IsMouseOver()
    if not triggerOver and not bridgeOver and not hotspotOver and not AnyItemMouseOver() then
        SetPanelShown(false)
    end
end

local function OnTriggerClick(_, mouseButton)
    if not active then return end
    if mouseButton == "RightButton" then
        if type(YMap.OpenSettings) == "function" then pcall(YMap.OpenSettings, YMap) end
        SetPanelShown(false)
        return
    end
    if mouseButton ~= "LeftButton" then return end
    if IsHoverMode() then
        SetPanelShown(true)
    else
        SetPanelShown(not stats.panelShown)
    end
end

local function ShowTriggerTooltip()
    local tooltip = _G.GameTooltip
    if not tooltip or not trigger then return end
    CallMethod(tooltip, "SetOwner", trigger, "ANCHOR_LEFT")
    if type(tooltip.SetText) == "function" then
        tooltip:SetText(GetText("buttonDrawer.tooltip", "小地图按钮抽屉"))
    end
    if type(tooltip.AddLine) == "function" then
        tooltip:AddLine(GetText("buttonDrawer.tooltip.settings", "右键打开地图设置"), 0.65, 0.65, 0.65)
    end
    CallMethod(tooltip, "Show")
end

local function HideTriggerTooltip()
    local tooltip = _G.GameTooltip
    if not tooltip or not trigger then return end
    local ok, owned = CallMethod(tooltip, "IsOwned", trigger)
    if ok and owned == true then CallMethod(tooltip, "Hide") end
end

local function OnTriggerEnter()
    CancelHoverClose()
    if active and GetConfig().expandMode == "hoverIcon" then
        SetPanelShown(true)
    end
    ShowTriggerTooltip()
end

local function OnTriggerLeave()
    HideTriggerTooltip()
    ScheduleHoverClose()
end

function ButtonDrawer._OnPanelHotspotEnter()
    CancelHoverClose()
    if active and GetConfig().expandMode == "hoverPanel" then
        SetPanelShown(true)
    end
end

function ButtonDrawer._OnPanelHotspotLeave()
    ScheduleHoverClose()
end

local function OnPanelEnter()
    CancelHoverClose()
    if active and IsHoverMode() then
        SetPanelShown(true)
    end
end

local function OnPanelLeave()
    ScheduleHoverClose()
end

local OnExternalParentChanged
local OnExternalLayoutMutation
local QueueDiscovery
local QueueLayout
local QueueRecovery
local QueueForCombat

local function OnExternalEnter(button)
    if active and captured[button] == ownershipToken and IsHoverMode() then
        CancelHoverClose()
        SetPanelShown(true)
    end
    ButtonDrawer:_SetItemBorderColor(button, "color.border.accent")
end

local function OnExternalLeave(button)
    if not active or captured[button] ~= ownershipToken then return end
    ButtonDrawer:_SetItemBorderColor(button, "color.border.default")
    ScheduleHoverClose()
end

local function OnExternalClick(button)
    if not active or captured[button] ~= ownershipToken then return end
    if IsHoverMode() then ScheduleHoverClose() end
end

local function OnExternalVisibilityChanged(button)
    if not active or captured[button] ~= ownershipToken then return end
    local snapshot = snapshots[button]
    if snapshot then
        snapshot.shown = IsFrameShown(button)
        if snapshot.shown ~= true then snapshot.slot = nil end
    end
    if landingRefreshGuard then return end
    if snapshot and snapshot.landingRole == "replacement" then
        if snapshot.shown ~= true then nativeLandingRefreshRequested = true end
        if QueueDiscovery then QueueDiscovery("landing-entry-visibility") end
        return
    end
    if QueueLayout then QueueLayout("button-visibility") end
end

local function HookExternalButton(button)
    if hookedButtons[button] then return end
    local method = button and button.HookScript
    if type(method) ~= "function" then return end
    pcall(method, button, "OnEnter", OnExternalEnter)
    pcall(method, button, "OnLeave", OnExternalLeave)
    pcall(method, button, "OnClick", OnExternalClick)
    pcall(method, button, "OnShow", OnExternalVisibilityChanged)
    pcall(method, button, "OnHide", OnExternalVisibilityChanged)
    if type(_G.hooksecurefunc) == "function" and type(button.SetParent) == "function" then
        pcall(_G.hooksecurefunc, button, "SetParent", OnExternalParentChanged)
    end
    if type(_G.hooksecurefunc) == "function" then
        for _, methodName in ipairs({
            "ClearAllPoints",
            "SetPoint",
            "SetSize",
            "SetScale",
            "SetFrameStrata",
            "SetFrameLevel",
            "SetFixedFrameStrata",
            "SetFixedFrameLevel",
            "EnableMouse",
            "SetMouseMotionEnabled",
            "SetMouseClickEnabled",
            "SetHitRectInsets",
        }) do
            if type(button[methodName]) == "function" then
                pcall(_G.hooksecurefunc, button, methodName, OnExternalLayoutMutation)
            end
        end
    end
    hookedButtons[button] = true
end

local function AddIgnoredObject(object)
    if object then ignoredObjects[object] = true end
end

local function RebuildDiscoveryBoundaries()
    ClearTable(allowedParents)
    ClearTable(ignoredObjects)

    local minimap = _G.Minimap
    local cluster = _G.MinimapCluster
    local backdrop = _G.MinimapBackdrop or (minimap and minimap.Backdrop)
    local container = cluster and cluster.MinimapContainer

    if minimap then allowedParents[minimap] = true end
    if cluster then allowedParents[cluster] = true end
    if backdrop then allowedParents[backdrop] = true end
    if container then allowedParents[container] = true end

    AddIgnoredObject(minimap)
    AddIgnoredObject(cluster)
    AddIgnoredObject(backdrop)
    AddIgnoredObject(container)
    AddIgnoredObject(panel)
    AddIgnoredObject(background)
    AddIgnoredObject(closeProgress)
    AddIgnoredObject(trigger)
    for index = 1, #slotFrames do AddIgnoredObject(slotFrames[index]) end

    if minimap then
        AddIgnoredObject(minimap.ZoomHitArea)
        AddIgnoredObject(minimap.ZoomIn)
        AddIgnoredObject(minimap.ZoomOut)
    end
    if cluster then
        AddIgnoredObject(cluster.BorderTop)
        AddIgnoredObject(cluster.ZoneTextButton)
        AddIgnoredObject(cluster.Tracking)
        AddIgnoredObject(cluster.IndicatorFrame)
        AddIgnoredObject(cluster.InstanceDifficulty)
    end

    AddIgnoredObject(_G.AddonCompartmentFrame)
    AddIgnoredObject(_G.GameTimeFrame)
    AddIgnoredObject(_G.LFGMinimapFrame)
    AddIgnoredObject(_G.MiniMapBattlefieldFrame)
    AddIgnoredObject(_G.MiniMapChallengeMode)
    AddIgnoredObject(_G.MiniMapInstanceDifficulty)
    AddIgnoredObject(_G.MiniMapLFGFrame)
    AddIgnoredObject(_G.MiniMapMailFrame)
    AddIgnoredObject(_G.MiniMapTracking)
    AddIgnoredObject(_G.MiniMapTrackingButton)
    AddIgnoredObject(_G.MinimapZoneTextButton)
    AddIgnoredObject(_G.MinimapZoomIn)
    AddIgnoredObject(_G.MinimapZoomOut)
    AddIgnoredObject(_G.QueueStatusMinimapButton)
    AddIgnoredObject(_G.TimeManagerClockButton)
end

local function IsIgnoredName(name, button)
    if type(name) ~= "string" then return false end
    if NATIVE_NAMES[name] then return true end
    local icons = YUI.MinimapIcon and YUI.MinimapIcon.buttons
    if button and icons and button.productId and icons[button.productId] == button then return false end
    if name:find("^YUI_") or name:find("^YMap") then return true end
    if name:find("Pin%d*$") or name:find("Node%d*$") or name:find("Note%d*$") then return true end
    return false
end

local function IsSafeCandidate(button, source, suppressNativeLanding)
    if not button or ignoredObjects[button] or captured[button] == ownershipToken then return false end
    if seenCandidates[button] then return false end

    local parent = GetFrameParent(button)
    if not allowedParents[parent] then return false end

    local ok, forbidden = CallMethod(button, "IsForbidden")
    if ok and forbidden == true then return false end
    ok, forbidden = CallMethod(button, "IsProtected")
    if ok and forbidden == true then return false end

    local _, name = CallMethod(button, "GetName")
    if IsIgnoredName(name, button) then return false end
    if suppressNativeLanding and IsNativeLandingPageButton(button, name) then return false end
    if IsLandingPageButton(button, name) and ButtonDrawer:_IsExpansionEntryHidden() then return false end
    if source ~= "libdbicon" and (type(name) ~= "string" or name == "") then
        return false
    end

    local _, isButton = CallMethod(button, "IsObjectType", "Button")
    if not isButton then
        local _, onClick = CallMethod(button, "GetScript", "OnClick")
        if type(onClick) ~= "function" then return false end
    end

    if source ~= "libdbicon" and source ~= "landing-page" and not IsFrameShown(button) then return false end
    seenCandidates[button] = true
    return true
end

local function CapturePoints(object)
    local points = {}
    local _, pointCount = CallMethod(object, "GetNumPoints")
    pointCount = tonumber(pointCount) or 0
    for index = 1, pointCount do
        local ok, point, relativeTo, relativePoint, x, y = CallMethod(object, "GetPoint", index)
        if ok and point then
            points[#points + 1] = {
                point = point,
                relativeTo = relativeTo,
                relativePoint = relativePoint,
                x = x,
                y = y,
            }
        end
    end
    return points
end

local function ResolveRegion(button, state)
    if not button or type(state) ~= "table" then return nil end
    if state.identityKind == "field" then
        return button[state.identityKey]
    elseif state.identityKind == "normal" then
        local ok, region = CallMethod(button, "GetNormalTexture")
        return ok and region or button.normalTexture
    elseif state.identityKind == "pushed" then
        local ok, region = CallMethod(button, "GetPushedTexture")
        return ok and region or button.pushedTexture
    elseif state.identityKind == "highlight" then
        local ok, region = CallMethod(button, "GetHighlightTexture")
        return ok and region or button.highlightTexture
    end
    return state.region
end

local function CaptureRegionState(region, identityKind, identityKey)
    if not region then return nil end
    local state = {
        region = region,
        identityKind = identityKind,
        identityKey = identityKey,
        points = CapturePoints(region),
    }
    local ok, value = CallMethod(region, "GetWidth")
    if ok then state.width = value end
    ok, value = CallMethod(region, "GetHeight")
    if ok then state.height = value end
    ok, value = CallMethod(region, "GetScale")
    if ok then state.scale = value end
    ok, value = CallMethod(region, "GetAlpha")
    if ok then state.alpha = value end
    ok, value = CallMethod(region, "IsShown")
    if ok then state.shown = value == true end
    local layerOK, layer, subLevel = CallMethod(region, "GetDrawLayer")
    if layerOK then
        state.drawLayer = layer
        state.drawSubLevel = subLevel
    end
    local texOK, a, b, c, d, e, f, g, h = CallMethod(region, "GetTexCoord")
    if texOK and a ~= nil then
        state.texCoord = { a, b, c, d, e, f, g, h }
        state.texCoordCount = h ~= nil and 8 or 4
    end
    return state
end

local function RegionIdentityMatches(button, state)
    return state and state.region and ResolveRegion(button, state) == state.region
end

local function RestoreRegionState(button, state)
    if not state then return true end
    if not RegionIdentityMatches(button, state) then
        IncrementVisualRestoreFailure()
        return false
    end
    local region = state.region
    local success = true
    if type(region.ClearAllPoints) == "function" then
        if not CallMethod(region, "ClearAllPoints") then success = false end
        for index = 1, #state.points do
            local point = state.points[index]
            if not CallMethod(
                region,
                "SetPoint",
                point.point,
                point.relativeTo,
                point.relativePoint,
                point.x,
                point.y
            ) then
                success = false
            end
        end
    end
    if type(state.width) == "number" and type(state.height) == "number" and type(region.SetSize) == "function" then
        if not CallMethod(region, "SetSize", state.width, state.height) then success = false end
    end
    if type(state.scale) == "number" and type(region.SetScale) == "function" then
        if not CallMethod(region, "SetScale", state.scale) then success = false end
    end
    if state.texCoord and type(region.SetTexCoord) == "function" then
        local ok = pcall(region.SetTexCoord, region, Unpack(state.texCoord, 1, state.texCoordCount))
        if not ok then success = false end
    end
    if state.drawLayer and type(region.SetDrawLayer) == "function" then
        if not CallMethod(region, "SetDrawLayer", state.drawLayer, state.drawSubLevel or 0) then success = false end
    end
    if type(state.alpha) == "number" and type(region.SetAlpha) == "function" then
        if not CallMethod(region, "SetAlpha", state.alpha) then success = false end
    end
    if state.shown ~= nil then
        if type(region.SetShown) == "function" then
            if not CallMethod(region, "SetShown", state.shown) then success = false end
        elseif not CallMethod(region, state.shown and "Show" or "Hide") then
            success = false
        end
    end
    if not success then IncrementVisualRestoreFailure() end
    return success
end

local function FillRegion(button, state, forceShow)
    if not RegionIdentityMatches(button, state) then return false end
    local region = state.region
    if type(region.ClearAllPoints) == "function" then CallMethod(region, "ClearAllPoints") end
    if type(region.SetAllPoints) == "function" then
        CallMethod(region, "SetAllPoints", button)
    else
        CallMethod(region, "SetPoint", "TOPLEFT", button, "TOPLEFT", 0, 0)
        CallMethod(region, "SetPoint", "BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    end
    CallMethod(region, "SetTexCoord", 0.08, 0.92, 0.08, 0.92)
    if forceShow then
        CallMethod(region, "SetAlpha", 1)
        CallMethod(region, "Show")
    end
    return true
end

local function HideRegion(button, state)
    if not RegionIdentityMatches(button, state) then return false end
    CallMethod(state.region, "SetAlpha", 0)
    CallMethod(state.region, "Hide")
    return true
end

function ButtonDrawer:_IsLegacyDecorationTexture(texture)
    if type(texture) == "number" then
        return self.LEGACY_DECORATION_TEXTURE_IDS[texture] == true
    end
    if type(texture) ~= "string" or texture == "" then return false end
    local normalized = texture:lower():gsub("/", "\\")
    local patterns = self.LEGACY_DECORATION_TEXTURE_PATTERNS
    for index = 1, #patterns do
        if normalized:find(patterns[index], 1, true) then return true end
    end
    return false
end

function ButtonDrawer:_CaptureLegacyRegionGroups(button, state)
    state.extraIcons = {}
    state.extraDecorations = {}
    if not button or type(button.GetRegions) ~= "function" then return state end

    local seen = {}
    for _, key in ipairs({ "icon", "border", "background", "highlight" }) do
        local regionState = state[key]
        if regionState and regionState.region then seen[regionState.region] = true end
    end

    local ok, regions = pcall(function() return { button:GetRegions() } end)
    if not ok or type(regions) ~= "table" then return state end
    for index = 1, #regions do
        local region = regions[index]
        if region and not seen[region] then
            local typeOK, isTexture = CallMethod(region, "IsObjectType", "Texture")
            if typeOK and isTexture == true then
                local textureOK, texture = CallMethod(region, "GetTexture")
                local atlasOK, atlas = CallMethod(region, "GetAtlas")
                if (textureOK and texture ~= nil) or (atlasOK and atlas ~= nil) then
                    local regionState = CaptureRegionState(region, "direct")
                    if self:_IsLegacyDecorationTexture(atlas)
                        or self:_IsLegacyDecorationTexture(texture)
                    then
                        state.extraDecorations[#state.extraDecorations + 1] = regionState
                    else
                        state.extraIcons[#state.extraIcons + 1] = regionState
                    end
                end
            end
        end
    end
    return state
end

function ButtonDrawer:_CaptureLegacyButtonState(button)
    local highlight
    local ok, value = CallMethod(button, "GetHighlightTexture")
    if ok then highlight = value end
    local state = self:_CaptureLegacyRegionGroups(button, {
        kind = "legacy-button",
        highlight = CaptureRegionState(highlight or button.highlightTexture, "highlight"),
    })
    if not state.highlight and #state.extraIcons == 0 and #state.extraDecorations == 0 then return nil end
    return state
end

local function CaptureLibDBIconState(button)
    local highlight
    local ok, value = CallMethod(button, "GetHighlightTexture")
    if ok then highlight = value end
    return ButtonDrawer:_CaptureLegacyRegionGroups(button, {
        kind = "libdbicon",
        icon = CaptureRegionState(button.icon, "field", "icon"),
        border = CaptureRegionState(button.border, "field", "border"),
        background = CaptureRegionState(button.background, "field", "background"),
        highlight = CaptureRegionState(highlight or button.highlightTexture, "highlight"),
    })
end

function ButtonDrawer:_CaptureLayeredLogoState(button)
    local animation = button.Bling and button.Bling.animScale
    local playing = false
    if animation then
        local ok, value = CallMethod(animation, "IsPlaying")
        playing = ok and value == true
    end
    return {
        kind = "layered-logo",
        background = CaptureRegionState(button.Background, "field", "Background"),
        color = CaptureRegionState(button.Color, "field", "Color"),
        bling = CaptureRegionState(button.Bling, "field", "Bling"),
        animation = animation,
        animationPlaying = playing,
    }
end

local function CaptureLandingPageState(button)
    local normalOK, normal = CallMethod(button, "GetNormalTexture")
    local pushedOK, pushed = CallMethod(button, "GetPushedTexture")
    local highlightOK, highlight = CallMethod(button, "GetHighlightTexture")
    local state = {
        kind = "landing-page",
        normal = CaptureRegionState(normalOK and normal or button.normalTexture, "normal"),
        pushed = CaptureRegionState(pushedOK and pushed or button.pushedTexture, "pushed"),
        highlight = CaptureRegionState(highlightOK and highlight or button.highlightTexture, "highlight"),
        decorations = {},
        animations = {},
    }
    for index = 1, #LANDING_PAGE_DECORATION_KEYS do
        local key = LANDING_PAGE_DECORATION_KEYS[index]
        state.decorations[key] = CaptureRegionState(button[key], "field", key)
    end
    for index = 1, #LANDING_PAGE_ANIMATION_KEYS do
        local key = LANDING_PAGE_ANIMATION_KEYS[index]
        local animation = button[key]
        local playing = false
        if animation then
            local playingOK, value = CallMethod(animation, "IsPlaying")
            playing = playingOK and value == true
        end
        state.animations[key] = {
            animation = animation,
            playing = playing,
        }
    end
    return state
end

local function NormalizeCapturedSlot(button, snapshot)
    local slot = snapshot and snapshot.slot
    if not slot or not active or captured[button] ~= ownershipToken then return end
    local iconSize = ClampNumber(GetConfig().iconSize, DEFAULTS.iconSize, 16, 64)
    buttonWriteGuard = true
    CallMethod(button, "ClearAllPoints")
    CallMethod(button, "SetPoint", "CENTER", slot, "CENTER", 0, 0)
    CallMethod(button, "SetSize", iconSize, iconSize)
    CallMethod(button, "SetScale", 1)
    ButtonDrawer:_WriteMouseState(button, ButtonDrawer:_IsPanelInputEnabled(), true)
    if type(button.SetHitRectInsets) == "function" then
        CallMethod(button, "SetHitRectInsets", 0, 0, 0, 0)
    end
    buttonWriteGuard = false
end

local function ApplySpecialVisual(button, snapshot)
    local special = snapshot and snapshot.special
    if not special then return end
    if special.kind == "layered-logo" then
        if RegionIdentityMatches(button, special.background) then
            local background = special.background.region
            CallMethod(background, "ClearAllPoints")
            if type(background.SetAllPoints) == "function" then
                CallMethod(background, "SetAllPoints", button)
            else
                CallMethod(background, "SetPoint", "TOPLEFT", button, "TOPLEFT", 0, 0)
                CallMethod(background, "SetPoint", "BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
            end
            CallMethod(background, "SetScale", 1)
            CallMethod(background, "Show")
        end
        HideRegion(button, special.color)
        HideRegion(button, special.bling)
        if special.animation then CallMethod(special.animation, "Stop") end
        return
    end
    if special.kind == "libdbicon" then
        FillRegion(button, special.icon, true)
        HideRegion(button, special.border)
        HideRegion(button, special.background)
        HideRegion(button, special.highlight)
        for index = 1, #special.extraDecorations do
            HideRegion(button, special.extraDecorations[index])
        end
        for index = 1, #special.extraIcons do
            FillRegion(button, special.extraIcons[index], false)
        end
        return
    end
    if special.kind == "legacy-button" then
        HideRegion(button, special.highlight)
        for index = 1, #special.extraDecorations do
            HideRegion(button, special.extraDecorations[index])
        end
        for index = 1, #special.extraIcons do
            FillRegion(button, special.extraIcons[index], false)
        end
        return
    end
    if special.kind ~= "landing-page" then return end
    FillRegion(button, special.normal, false)
    FillRegion(button, special.pushed, false)
    FillRegion(button, special.highlight, false)
    for index = 1, #LANDING_PAGE_DECORATION_KEYS do
        HideRegion(button, special.decorations[LANDING_PAGE_DECORATION_KEYS[index]])
    end
    for index = 1, #LANDING_PAGE_ANIMATION_KEYS do
        local animationState = special.animations[LANDING_PAGE_ANIMATION_KEYS[index]]
        if animationState and animationState.animation then
            CallMethod(animationState.animation, "Stop")
        end
    end
    NormalizeCapturedSlot(button, snapshot)
end

local function RestoreSpecialVisual(button, snapshot, skipNativeRefresh)
    ButtonDrawer:_HideItemSurface(button)
    ButtonDrawer:_RestoreInputState(button, snapshot)
    local special = snapshot and snapshot.special
    if not special then return true end
    local success = true
    if special.kind == "layered-logo" then
        success = RestoreRegionState(button, special.background) and success
        success = RestoreRegionState(button, special.color) and success
        success = RestoreRegionState(button, special.bling) and success
        if special.animationPlaying and special.animation then
            local ok, playing = CallMethod(special.animation, "IsPlaying")
            if not ok or playing ~= true then CallMethod(special.animation, "Play") end
        end
        return success
    end
    if special.kind == "libdbicon" then
        success = RestoreRegionState(button, special.icon) and success
        success = RestoreRegionState(button, special.border) and success
        success = RestoreRegionState(button, special.background) and success
        success = RestoreRegionState(button, special.highlight) and success
        for index = 1, #special.extraDecorations do
            success = RestoreRegionState(button, special.extraDecorations[index]) and success
        end
        for index = 1, #special.extraIcons do
            success = RestoreRegionState(button, special.extraIcons[index]) and success
        end
        return success
    end
    if special.kind == "legacy-button" then
        success = RestoreRegionState(button, special.highlight) and success
        for index = 1, #special.extraDecorations do
            success = RestoreRegionState(button, special.extraDecorations[index]) and success
        end
        for index = 1, #special.extraIcons do
            success = RestoreRegionState(button, special.extraIcons[index]) and success
        end
        return success
    end
    if special.kind ~= "landing-page" then return true end
    success = RestoreRegionState(button, special.normal) and success
    success = RestoreRegionState(button, special.pushed) and success
    success = RestoreRegionState(button, special.highlight) and success
    for index = 1, #LANDING_PAGE_DECORATION_KEYS do
        success = RestoreRegionState(
            button,
            special.decorations[LANDING_PAGE_DECORATION_KEYS[index]]
        ) and success
    end
    if not skipNativeRefresh then
        if type(button.RefreshButton) == "function" then
            local ok = pcall(button.RefreshButton, button, true)
            if not ok then IncrementVisualRestoreFailure() end
            success = ok and success
        elseif type(button.UpdateIcon) == "function" then
            local ok = pcall(button.UpdateIcon, button)
            if not ok then IncrementVisualRestoreFailure() end
            success = ok and success
        end
        for index = 1, #LANDING_PAGE_ANIMATION_KEYS do
            local animationState = special.animations[LANDING_PAGE_ANIMATION_KEYS[index]]
            if animationState and animationState.playing and animationState.animation then
                local playingOK, playing = CallMethod(animationState.animation, "IsPlaying")
                if not playingOK or playing ~= true then CallMethod(animationState.animation, "Play") end
            end
        end
    end
    return success
end

local function OnLandingPageVisualMutation(button)
    if not active or captured[button] ~= ownershipToken or GetFrameParent(button) ~= panel then return end
    local snapshot = snapshots[button]
    if snapshot and snapshot.special and snapshot.special.kind == "landing-page" then
        ApplySpecialVisual(button, snapshot)
    end
end

local function EnsureLandingPageHooks(button)
    if not button or hookedLandingButtons[button] then return end
    if type(_G.hooksecurefunc) == "function" then
        for index = 1, #LANDING_PAGE_REFRESH_METHODS do
            local methodName = LANDING_PAGE_REFRESH_METHODS[index]
            if type(button[methodName]) == "function" then
                pcall(_G.hooksecurefunc, button, methodName, function()
                    OnLandingPageVisualMutation(button)
                end)
            end
        end
    end
    for index = 1, #LANDING_PAGE_ANIMATION_KEYS do
        local animation = button[LANDING_PAGE_ANIMATION_KEYS[index]]
        if animation and type(animation.HookScript) == "function" then
            pcall(animation.HookScript, animation, "OnPlay", function()
                OnLandingPageVisualMutation(button)
            end)
        end
    end
    hookedLandingButtons[button] = true
end

function ButtonDrawer:_OnLayeredLogoVisualMutation(button)
    if not active or captured[button] ~= ownershipToken or GetFrameParent(button) ~= panel then return end
    local snapshot = snapshots[button]
    if snapshot and snapshot.special and snapshot.special.kind == "layered-logo" then
        ApplySpecialVisual(button, snapshot)
    end
end

function ButtonDrawer:_EnsureLayeredLogoHooks(button)
    if not button or self.hookedLayeredLogoButtons[button] then return end
    if type(_G.hooksecurefunc) == "function" and type(button.SetBackground) == "function" then
        pcall(_G.hooksecurefunc, button, "SetBackground", function()
            ButtonDrawer:_OnLayeredLogoVisualMutation(button)
        end)
    end
    local animation = button.Bling and button.Bling.animScale
    if animation and type(animation.HookScript) == "function" then
        pcall(animation.HookScript, animation, "OnPlay", function()
            ButtonDrawer:_OnLayeredLogoVisualMutation(button)
        end)
    end
    self.hookedLayeredLogoButtons[button] = true
end

local function UpdateStyledCount(snapshot, delta)
    local special = snapshot and snapshot.special
    if not special then return end
    if special.kind == "libdbicon" then
        stats.styledLibDBIcons = math.max(0, stats.styledLibDBIcons + delta)
    elseif special.kind == "landing-page" then
        stats.styledLandingButtons = math.max(0, stats.styledLandingButtons + delta)
    end
end

local function SetSnapshotVisualApplied(snapshot, applied)
    if not snapshot or snapshot.visualApplied == applied then return end
    snapshot.visualApplied = applied == true
    UpdateStyledCount(snapshot, applied and 1 or -1)
    local special = snapshot.special
    if not special or special.kind ~= "landing-page" then return end
    local api = YUI.API and YUI.API.BlizzardUI
    local method = applied and "AcquireHelpTipAnchor" or "ReleaseHelpTipAnchor"
    if api and type(api[method]) == "function" then
        pcall(api[method], api, helpTipAnchorOwner, snapshot.button)
    end
end

local function CaptureSnapshot(button, source)
    local snapshot = {
        owner = ownershipToken,
        button = button,
        source = source,
        parent = GetFrameParent(button),
        points = {},
        methods = {
            SetParent = button.SetParent,
            SetFrameStrata = button.SetFrameStrata,
            SetFrameLevel = button.SetFrameLevel,
            SetFixedFrameStrata = button.SetFixedFrameStrata,
            SetFixedFrameLevel = button.SetFixedFrameLevel,
            SetSize = button.SetSize,
            SetScale = button.SetScale,
            EnableMouse = button.EnableMouse,
            SetMouseMotionEnabled = button.SetMouseMotionEnabled,
            SetMouseClickEnabled = button.SetMouseClickEnabled,
            SetHitRectInsets = button.SetHitRectInsets,
            ClearAllPoints = button.ClearAllPoints,
            SetPoint = button.SetPoint,
            SetShown = button.SetShown,
        },
    }
    if not snapshot.parent then return nil end
    local _, name = CallMethod(button, "GetName")
    snapshot.landingRole = GetLandingPageRole(button, name)
    if snapshot.landingRole == "native" then
        snapshot.special = CaptureLandingPageState(button)
    elseif ButtonDrawer:_IsLayeredLogoButton(button) then
        snapshot.special = ButtonDrawer:_CaptureLayeredLogoState(button)
    elseif source == "libdbicon"
        or (type(name) == "string" and name:find("^LibDBIcon%d+_"))
    then
        snapshot.special = CaptureLibDBIconState(button)
    else
        snapshot.special = ButtonDrawer:_CaptureLegacyButtonState(button)
    end

    local ok, value = CallMethod(button, "GetWidth")
    if ok then snapshot.width = value end
    ok, value = CallMethod(button, "GetHeight")
    if ok then snapshot.height = value end
    ok, value = CallMethod(button, "GetScale")
    if ok then snapshot.scale = value end
    ok, value = CallMethod(button, "GetFrameStrata")
    if ok then snapshot.strata = value end
    ok, value = CallMethod(button, "GetFrameLevel")
    if ok then snapshot.level = value end
    ok, value = CallMethod(button, "HasFixedFrameStrata")
    if ok and type(value) == "boolean" then snapshot.fixedStrata = value end
    ok, value = CallMethod(button, "HasFixedFrameLevel")
    if ok and type(value) == "boolean" then snapshot.fixedLevel = value end
    ok, value = CallMethod(button, "IsShown")
    if ok then snapshot.shown = value == true end
    ok, value = CallMethod(button, "IsMouseEnabled")
    if ok then snapshot.mouseEnabled = value == true end
    ok, value = CallMethod(button, "IsMouseMotionEnabled")
    if ok then snapshot.mouseMotionEnabled = value == true end
    ok, value = CallMethod(button, "IsMouseClickEnabled")
    if ok then snapshot.mouseClickEnabled = value == true end
    local hitOK, left, right, top, bottom = CallMethod(button, "GetHitRectInsets")
    if hitOK then snapshot.hitRectInsets = { left, right, top, bottom } end

    snapshot.points = CapturePoints(button)
    return snapshot
end

local function RestoreSnapshot(button, snapshot, requireOwnership, options)
    if type(snapshot) ~= "table" or snapshot.owner ~= ownershipToken then return false end
    if requireOwnership and GetFrameParent(button) ~= panel then
        return false
    end
    options = type(options) == "table" and options or nil
    for methodName, methodIdentity in pairs(snapshot.methods or {}) do
        if type(methodIdentity) == "function" and button[methodName] ~= methodIdentity then
            RestoreSpecialVisual(button, snapshot, true)
            return false
        end
    end

    local success = true
    buttonWriteGuard = true
    if not UnlockButtonLayers(button) then success = false end
    if not CallMethod(button, "SetParent", snapshot.parent) then success = false end
    if snapshot.strata and not CallMethod(button, "SetFrameStrata", snapshot.strata) then success = false end
    if type(snapshot.level) == "number" and not CallMethod(button, "SetFrameLevel", snapshot.level) then success = false end
    if snapshot.fixedStrata ~= nil
        and not CallMethod(button, "SetFixedFrameStrata", snapshot.fixedStrata) then success = false end
    if snapshot.fixedLevel ~= nil
        and not CallMethod(button, "SetFixedFrameLevel", snapshot.fixedLevel) then success = false end
    if type(snapshot.width) == "number" and type(snapshot.height) == "number" then
        if not CallMethod(button, "SetSize", snapshot.width, snapshot.height) then success = false end
    end
    if type(snapshot.scale) == "number" and not CallMethod(button, "SetScale", snapshot.scale) then success = false end
    if snapshot.hitRectInsets and not CallMethod(
        button,
        "SetHitRectInsets",
        snapshot.hitRectInsets[1],
        snapshot.hitRectInsets[2],
        snapshot.hitRectInsets[3],
        snapshot.hitRectInsets[4]
    ) then
        success = false
    end
    if not CallMethod(button, "ClearAllPoints") then success = false end
    for index = 1, #snapshot.points do
        local point = snapshot.points[index]
        if not CallMethod(
            button,
            "SetPoint",
            point.point,
            point.relativeTo,
            point.relativePoint,
            point.x,
            point.y
        ) then
            success = false
        end
    end
    if (not options or options.restoreShown ~= false)
        and snapshot.shown ~= nil
        and not CallMethod(button, "SetShown", snapshot.shown)
    then
        success = false
    end
    RestoreSpecialVisual(button, snapshot, options and options.skipNativeRefresh == true)
    buttonWriteGuard = false
    return success
end

local function RemoveExternalButton(button)
    for index = #externalButtons, 1, -1 do
        if externalButtons[index] == button then
            for moveIndex = index, #externalButtons - 1 do
                externalButtons[moveIndex] = externalButtons[moveIndex + 1]
            end
            externalButtons[#externalButtons] = nil
            return true
        end
    end
    return false
end

local function IsLandingSnapshot(snapshot)
    return snapshot
        and snapshot.special
        and snapshot.special.kind == "landing-page"
end

local function IsLandingEntrySnapshot(snapshot)
    return snapshot
        and (snapshot.landingRole == "native" or snapshot.landingRole == "replacement")
end

local function NotifyLandingPageReleased()
    local minimap = YMap.Minimap
    if minimap and type(minimap.OnButtonDrawerReleased) == "function" then
        pcall(minimap.OnButtonDrawerReleased, minimap, "button-drawer-release")
    end
end

function ButtonDrawer:_ReleaseHiddenLandingPageButtons()
    if not self:_IsExpansionEntryHidden() then return false end
    local changed = false
    local landingReleased = false
    for index = #externalButtons, 1, -1 do
        local button = externalButtons[index]
        local snapshot = snapshots[button]
        if IsLandingEntrySnapshot(snapshot) then
            local parent = GetFrameParent(button)
            if parent == panel then
                if RestoreSnapshot(button, snapshot, true) then
                    SetSnapshotVisualApplied(snapshot, false)
                    captured[button] = nil
                    snapshots[button] = nil
                    RemoveExternalButton(button)
                    landingReleased = landingReleased or IsLandingSnapshot(snapshot)
                else
                    IncrementRestoreFailure()
                    SetSnapshotVisualApplied(snapshot, false)
                    captured[button] = nil
                    snapshot.yielded = true
                end
                changed = true
            elseif parent == snapshot.parent then
                RestoreSpecialVisual(button, snapshot, true)
                SetSnapshotVisualApplied(snapshot, false)
                captured[button] = nil
                snapshots[button] = nil
                RemoveExternalButton(button)
                landingReleased = landingReleased or IsLandingSnapshot(snapshot)
                changed = true
            end
        end
    end
    if landingReleased then NotifyLandingPageReleased() end
    return changed
end

function ButtonDrawer:_ReleaseIgnoredButtons()
    local changed = false
    for index = #externalButtons, 1, -1 do
        local button = externalButtons[index]
        local snapshot = snapshots[button]
        local _, name = CallMethod(button, "GetName")
        if snapshot and IsIgnoredName(name, button) then
            local parent = GetFrameParent(button)
            if parent == panel then
                if RestoreSnapshot(button, snapshot, true) then
                    SetSnapshotVisualApplied(snapshot, false)
                    captured[button] = nil
                    snapshots[button] = nil
                    RemoveExternalButton(button)
                else
                    IncrementRestoreFailure()
                    SetSnapshotVisualApplied(snapshot, false)
                    captured[button] = nil
                    snapshot.yielded = true
                end
                changed = true
            elseif parent == snapshot.parent then
                RestoreSpecialVisual(button, snapshot, true)
                SetSnapshotVisualApplied(snapshot, false)
                captured[button] = nil
                snapshots[button] = nil
                RemoveExternalButton(button)
                changed = true
            end
        end
    end
    return changed
end

OnExternalParentChanged = function(button)
    if buttonWriteGuard then return end
    local snapshot = snapshots[button]
    if type(snapshot) ~= "table" or snapshot.owner ~= ownershipToken then return end

    local parent = GetFrameParent(button)
    if captured[button] == ownershipToken and parent ~= panel then
        captured[button] = nil
        snapshot.yielded = true
        RestoreSpecialVisual(button, snapshot, true)
        SetSnapshotVisualApplied(snapshot, false)
        stats.ownershipLosses = stats.ownershipLosses + 1
        if snapshot.landingRole == "replacement" then
            snapshots[button] = nil
            RemoveExternalButton(button)
            nativeLandingRefreshRequested = true
            if active and QueueDiscovery then QueueDiscovery("landing-entry-parent") end
            return
        end
        if active and QueueLayout then QueueLayout("ownership-yield") end
        return
    end
    if snapshot.yielded ~= true then return end

    if parent == panel then
        if active and not (IsLandingEntrySnapshot(snapshot) and ButtonDrawer:_IsExpansionEntryHidden()) then
            snapshot.yielded = false
            captured[button] = ownershipToken
            ApplySpecialVisual(button, snapshot)
            SetSnapshotVisualApplied(snapshot, snapshot.special ~= nil)
            if QueueLayout then QueueLayout("ownership-return") end
        elseif QueueRecovery then
            QueueRecovery("ownership-return")
        end
    elseif parent == snapshot.parent then
        local landingReleased = IsLandingSnapshot(snapshot)
        RestoreSpecialVisual(button, snapshot, true)
        SetSnapshotVisualApplied(snapshot, false)
        captured[button] = nil
        snapshots[button] = nil
        RemoveExternalButton(button)
        if active and QueueLayout then QueueLayout("ownership-released") end
        if landingReleased then NotifyLandingPageReleased() end
    end
end

OnExternalLayoutMutation = function(button)
    if buttonWriteGuard
        or landingRefreshGuard
        or not active
        or captured[button] ~= ownershipToken
    then
        return
    end
    if QueueLayout then QueueLayout("button-layout") end
end

local function OnRecovery()
    local changed = false
    local landingReleased = false
    for index = #externalButtons, 1, -1 do
        local button = externalButtons[index]
        local snapshot = snapshots[button]
        if snapshot and snapshot.yielded == true then
            local parent = GetFrameParent(button)
            if parent == panel then
                if active and not (IsLandingEntrySnapshot(snapshot) and ButtonDrawer:_IsExpansionEntryHidden()) then
                    snapshot.yielded = false
                    captured[button] = ownershipToken
                    ApplySpecialVisual(button, snapshot)
                    SetSnapshotVisualApplied(snapshot, snapshot.special ~= nil)
                    changed = true
                elseif IsInCombat() then
                    if QueueForCombat then QueueForCombat("restore", "ownership-return") end
                elseif RestoreSnapshot(button, snapshot, true) then
                    landingReleased = landingReleased or IsLandingSnapshot(snapshot)
                    SetSnapshotVisualApplied(snapshot, false)
                    captured[button] = nil
                    snapshots[button] = nil
                    RemoveExternalButton(button)
                else
                    IncrementRestoreFailure()
                end
            elseif parent == snapshot.parent then
                landingReleased = landingReleased or IsLandingSnapshot(snapshot)
                RestoreSpecialVisual(button, snapshot, true)
                SetSnapshotVisualApplied(snapshot, false)
                captured[button] = nil
                snapshots[button] = nil
                RemoveExternalButton(button)
                changed = true
            end
        end
    end
    if changed and active and QueueLayout then QueueLayout("ownership-recovered") end
    if landingReleased then NotifyLandingPageReleased() end
end

QueueRecovery = function(reason)
    if Event and type(Event.Once) == "function" and type(Event.Emit) == "function" then
        if type(Event.OffOwner) == "function" then Event:OffOwner(recoveryOwner) end
        Event:Once(RECOVERY_EVENT, OnRecovery, recoveryOwner, {
            debounce = 0.01,
            moduleId = MODULE_ID,
        })
        Event:Emit(RECOVERY_EVENT, reason or "recovery")
        return true
    end
    OnRecovery()
    return true
end

local function CaptureButton(button, source, suppressNativeLanding)
    if not IsSafeCandidate(button, source, suppressNativeLanding) then return false end
    local snapshot = CaptureSnapshot(button, source)
    if not snapshot then
        stats.skippedCandidates = stats.skippedCandidates + 1
        return false
    end

    local config = GetConfig()
    local iconSize = ClampNumber(config.iconSize, DEFAULTS.iconSize, 16, 64)
    buttonWriteGuard = true
    local success = UnlockButtonLayers(button)
    if success then success = CallMethod(button, "SetParent", panel) end
    if success then success = CallMethod(button, "ClearAllPoints") end
    if success then success = CallMethod(button, "SetSize", iconSize, iconSize) end
    if success then success = CallMethod(button, "SetScale", 1) end
    if success then
        success = ButtonDrawer:_WriteMouseState(
            button,
            ButtonDrawer:_IsPanelInputEnabled(),
            true
        )
    end
    if success and snapshot.special and type(button.SetHitRectInsets) == "function" then
        success = CallMethod(button, "SetHitRectInsets", 0, 0, 0, 0)
    end
    if success then success = CallMethod(button, "SetFrameStrata", DRAWER_FRAME_STRATA) end
    if success then success = CallMethod(button, "SetFrameLevel", panel:GetFrameLevel() + 3) end
    buttonWriteGuard = false

    if not success then
        RestoreSnapshot(button, snapshot, false)
        stats.skippedCandidates = stats.skippedCandidates + 1
        return false
    end

    snapshots[button] = snapshot
    captured[button] = ownershipToken
    externalButtons[#externalButtons + 1] = button
    ApplySpecialVisual(button, snapshot)
    SetSnapshotVisualApplied(snapshot, snapshot.special ~= nil)
    if IsLandingSnapshot(snapshot) then
        EnsureLandingPageHooks(button)
    elseif snapshot.special and snapshot.special.kind == "layered-logo" then
        ButtonDrawer:_EnsureLayeredLogoHooks(button)
    end
    HookExternalButton(button)
    return true
end

local function PruneLostButtons()
    local writeIndex = 1
    local landingReleased = false
    for readIndex = 1, #externalButtons do
        local button = externalButtons[readIndex]
        local snapshot = snapshots[button]
        local parent = GetFrameParent(button)
        if snapshot then
            if captured[button] == ownershipToken and parent ~= panel then
                captured[button] = nil
                snapshot.yielded = true
                RestoreSpecialVisual(button, snapshot, true)
                SetSnapshotVisualApplied(snapshot, false)
                stats.ownershipLosses = stats.ownershipLosses + 1
            elseif snapshot.yielded == true
                and parent == panel
                and active
                and not (IsLandingEntrySnapshot(snapshot) and ButtonDrawer:_IsExpansionEntryHidden())
            then
                snapshot.yielded = false
                captured[button] = ownershipToken
                ApplySpecialVisual(button, snapshot)
                SetSnapshotVisualApplied(snapshot, snapshot.special ~= nil)
            elseif snapshot.yielded == true and parent == snapshot.parent then
                landingReleased = landingReleased or IsLandingSnapshot(snapshot)
                RestoreSpecialVisual(button, snapshot, true)
                SetSnapshotVisualApplied(snapshot, false)
                captured[button] = nil
                snapshots[button] = nil
                snapshot = nil
            end
            if snapshot then
                externalButtons[writeIndex] = button
                writeIndex = writeIndex + 1
            end
        end
    end
    for index = writeIndex, #externalButtons do
        externalButtons[index] = nil
    end
    if landingReleased then NotifyLandingPageReleased() end
end

local function ReleaseExternalButtons()
    local writeIndex = 1
    local landingReleased = false
    for readIndex = 1, #externalButtons do
        local button = externalButtons[readIndex]
        local snapshot = snapshots[button]
        local retain = false
        if snapshot and GetFrameParent(button) == panel then
            if RestoreSnapshot(button, snapshot, true) then
                landingReleased = landingReleased or IsLandingSnapshot(snapshot)
                SetSnapshotVisualApplied(snapshot, false)
                captured[button] = nil
                snapshots[button] = nil
            else
                IncrementRestoreFailure()
                SetSnapshotVisualApplied(snapshot, false)
                captured[button] = nil
                snapshot.yielded = true
                retain = true
            end
        elseif snapshot then
            RestoreSpecialVisual(button, snapshot, true)
            SetSnapshotVisualApplied(snapshot, false)
            captured[button] = nil
            snapshot.yielded = true
            retain = true
        else
            captured[button] = nil
        end
        if retain then
            externalButtons[writeIndex] = button
            writeIndex = writeIndex + 1
        end
    end
    for index = writeIndex, #externalButtons do externalButtons[index] = nil end
    stats.externalButtons = 0
    local api = YUI.API and YUI.API.BlizzardUI
    if api and type(api.ReleaseOwner) == "function" then
        pcall(api.ReleaseOwner, api, helpTipAnchorOwner)
    end
    if landingReleased then NotifyLandingPageReleased() end
end

local function ReleaseSuppressedNativeLandingButton(button, snapshot)
    if not IsLandingSnapshot(snapshot) then return false end
    landingRefreshGuard = true
    local hidden = CallMethod(button, "Hide")
    landingRefreshGuard = false
    if not hidden then return false end

    if GetFrameParent(button) == panel then
        return RestoreSnapshot(button, snapshot, true, {
            restoreShown = false,
            skipNativeRefresh = true,
        })
    end
    if GetFrameParent(button) == snapshot.parent then
        RestoreSpecialVisual(button, snapshot, true)
        return true
    end
    return false
end

local function ReleaseSuppressedNativeLandingButtons()
    for index = #externalButtons, 1, -1 do
        local button = externalButtons[index]
        local snapshot = snapshots[button]
        if IsLandingSnapshot(snapshot) and captured[button] == ownershipToken then
            if ReleaseSuppressedNativeLandingButton(button, snapshot) then
                SetSnapshotVisualApplied(snapshot, false)
                captured[button] = nil
                snapshots[button] = nil
                RemoveExternalButton(button)
            else
                IncrementRestoreFailure()
                SetSnapshotVisualApplied(snapshot, false)
                captured[button] = nil
                snapshot.yielded = true
            end
        end
    end
end

local function FindVisibleLandingReplacement()
    for index = 1, #externalButtons do
        local button = externalButtons[index]
        local snapshot = snapshots[button]
        if snapshot
            and snapshot.landingRole == "replacement"
            and captured[button] == ownershipToken
            and IsFrameShown(button)
        then
            return button
        end
    end
    return nil
end

local function RefreshHiddenNativeLandingButtons()
    for index = #externalButtons, 1, -1 do
        local button = externalButtons[index]
        local snapshot = snapshots[button]
        if IsLandingSnapshot(snapshot)
            and captured[button] == ownershipToken
            and not IsFrameShown(button)
            and type(button.RefreshButton) == "function"
        then
            landingRefreshGuard = true
            local ok = pcall(button.RefreshButton, button, true)
            landingRefreshGuard = false
            if not ok then
                IncrementVisualRestoreFailure()
                if ReleaseSuppressedNativeLandingButton(button, snapshot) then
                    SetSnapshotVisualApplied(snapshot, false)
                    captured[button] = nil
                    snapshots[button] = nil
                    RemoveExternalButton(button)
                else
                    IncrementRestoreFailure()
                    SetSnapshotVisualApplied(snapshot, false)
                    captured[button] = nil
                    snapshot.yielded = true
                end
            end
        end
    end
end

local function ScanParent(parent, suppressNativeLanding)
    if not parent or type(parent.GetChildren) ~= "function" then return end
    local children = { parent:GetChildren() }
    for index = 1, #children do
        local button = children[index]
        local _, name = CallMethod(button, "GetName")
        local source = IsLandingPageButton(button, name) and "landing-page" or "direct"
        CaptureButton(button, source, suppressNativeLanding)
    end
end

local function ScanLandingReplacementParent(parent)
    if not parent or type(parent.GetChildren) ~= "function" then return end
    local children = { parent:GetChildren() }
    for index = 1, #children do
        local button = children[index]
        local _, name = CallMethod(button, "GetName")
        if GetLandingPageRole(button, name) == "replacement" then
            CaptureButton(button, "landing-page", false)
        end
    end
end

local function OnLibDBIconCreated()
    if active and QueueDiscovery then QueueDiscovery("libdbicon-created") end
end

local function DetachLibDBIconCallback()
    local library = libDBIconLibrary
    libDBIconLibrary = nil
    if library and type(library.UnregisterCallback) == "function" then
        pcall(library.UnregisterCallback, libDBIconOwner, "LibDBIcon_IconCreated")
    end
end

local function EnsureLibDBIconCallback()
    local library = GetLibDBIcon()
    if library == libDBIconLibrary then return library ~= nil end
    DetachLibDBIconCallback()
    if not library or type(library.RegisterCallback) ~= "function" then return false end
    local ok = pcall(
        library.RegisterCallback,
        libDBIconOwner,
        "LibDBIcon_IconCreated",
        OnLibDBIconCreated
    )
    if ok then libDBIconLibrary = library end
    return ok
end

local function ScanLibDBIcon()
    local library = GetLibDBIcon()
    if not library or type(library.objects) ~= "table" then return end
    for _, button in pairs(library.objects) do
        CaptureButton(button, "libdbicon")
    end
end

local function ApplyBackgroundStyle(config)
    if not background or not backgroundTexture then return end
    local mode = config.panelBackground
    if mode == "none" then
        background:Hide()
        return
    end
    local transparent = mode == "transparent" or mode == "translucent"
    background:SetFrameStrata(DRAWER_BACKGROUND_STRATA)
    background:SetFrameLevel(panel:GetFrameLevel())
    background:SetAlpha(1)
    backgroundTexture:SetTexture("Interface\\Buttons\\WHITE8x8")
    backgroundTexture:SetVertexColor(0, 0, 0, transparent and 0.6 or 1)
    if GUI2 and type(GUI2.SetBorderColor) == "function" then
        GUI2:SetBorderColor(background, "color.border.default")
    end
    background:Show()
end

local function GetEffectiveScale(frame)
    local ok, scale = CallMethod(frame, "GetEffectiveScale")
    if ok and type(scale) == "number" and scale > 0 then return scale end
    ok, scale = CallMethod(frame, "GetScale")
    if ok and type(scale) == "number" and scale > 0 then return scale end
    return 1
end

local function GetMinimapVisualScaleRatio()
    local ratio = GetEffectiveScale(_G.Minimap) / GetEffectiveScale(_G.UIParent)
    if type(ratio) ~= "number" or ratio <= 0 then return 1 end
    return ratio
end

local function ApplyTriggerLayout(config)
    if not trigger or not _G.Minimap then return end
    local size = ClampNumber(config.triggerSize, DEFAULTS.triggerSize, 10, 40)
    local x = ClampNumber(config.triggerOffsetX, DEFAULTS.triggerOffsetX, -100, 100)
    local y = ClampNumber(config.triggerOffsetY, DEFAULTS.triggerOffsetY, -100, 100)
    local position = config.triggerPosition
    local scaleRatio = GetMinimapVisualScaleRatio()
    local visualX = x / scaleRatio
    local visualY = y / scaleRatio

    trigger:SetScale(1 / scaleRatio)
    trigger:SetSize(size, size)
    if triggerIcon then
        triggerIcon:SetSize(
            size * ButtonDrawer.TRIGGER_ICON_RATIO,
            size * ButtonDrawer.TRIGGER_ICON_RATIO
        )
    end
    trigger:SetAlpha(1)
    trigger:ClearAllPoints()
    if position == "topLeft" then
        trigger:SetPoint("TOPLEFT", _G.Minimap, "TOPLEFT", -visualX, visualY)
    elseif position == "topRight" then
        trigger:SetPoint("TOPRIGHT", _G.Minimap, "TOPRIGHT", visualX, visualY)
    elseif position == "bottomLeft" then
        trigger:SetPoint("BOTTOMLEFT", _G.Minimap, "BOTTOMLEFT", -visualX, -visualY)
    else
        trigger:SetPoint("BOTTOMRIGHT", _G.Minimap, "BOTTOMRIGHT", visualX, -visualY)
    end
    if config.expandMode == "hoverPanel" then
        trigger:Hide()
    else
        trigger:Show()
    end
end

local function GetOrCreateSlot(index)
    local slot = slotFrames[index]
    if slot then return slot end
    if not GUI2 or type(GUI2.CreateFrame) ~= "function" or not panel then return nil end
    slot = GUI2:CreateFrame(panel, {
        name = "YUI_YMap_ButtonDrawerSlot" .. index,
        width = DEFAULTS.iconSize,
        height = DEFAULTS.iconSize,
        frameStrata = DRAWER_FRAME_STRATA,
        frameLevel = panel:GetFrameLevel() + 2,
        mouse = false,
        hidden = true,
    })
    if slot then
        slot:EnableMouse(false)
        slotFrames[index] = slot
    end
    return slot
end

function ButtonDrawer:_EnsureItemBacking(frame)
    if not frame or not GUI2 or type(GUI2.CreateTexture) ~= "function" then return nil end
    local backing = self.itemBackings[frame]
    if not backing then
        backing = GUI2:CreateTexture(frame, {
            layer = "BACKGROUND",
            texture = "Interface\\Buttons\\WHITE8x8",
        })
        if not backing then return nil end
        backing:SetAllPoints(frame)
        backing:SetVertexColor(0, 0, 0, 0.9)
        if type(backing.SetDrawLayer) == "function" then
            backing:SetDrawLayer("BACKGROUND", -1)
        end
        self.itemBackings[frame] = backing
    end
    backing:SetAllPoints(frame)
    backing:SetVertexColor(0, 0, 0, 0.9)
    if type(backing.SetDrawLayer) == "function" then
        backing:SetDrawLayer("BACKGROUND", -1)
    end
    backing:Show()
    return backing
end

function ButtonDrawer:_HideItemBacking(frame)
    local backing = frame and self.itemBackings[frame]
    if backing then backing:Hide() end
end

function ButtonDrawer:_EnsureItemBorder(frame)
    if not frame or not GUI2 or type(GUI2.CreateTexture) ~= "function" then return nil end
    local border = self.itemBorders[frame]
    if not border then
        border = {}
        for _, edge in ipairs({ "top", "bottom", "left", "right" }) do
            local texture = GUI2:CreateTexture(frame, {
                layer = "OVERLAY",
                texture = "Interface\\Buttons\\WHITE8x8",
            })
            if not texture then return nil end
            border[edge] = texture
        end
        border.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        border.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        border.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        border.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        border.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        border.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        border.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        border.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        self.itemBorders[frame] = border
    end
    local size = 1
    if type(GUI2.GetPixelSize) == "function" then
        local ok, value = pcall(GUI2.GetPixelSize, GUI2, frame, 1, 1)
        if ok and type(value) == "number" and value > 0 then size = value end
    end
    border.top:SetHeight(size)
    border.bottom:SetHeight(size)
    border.left:SetWidth(size)
    border.right:SetWidth(size)
    for _, texture in pairs(border) do texture:Show() end
    self:_SetItemBorderColor(frame, "color.border.default")
    return border
end

function ButtonDrawer:_SetItemBorderColor(frame, colorKey)
    local border = frame and self.itemBorders[frame]
    if not border then return end
    local r, g, b, a = 1, 1, 1, 1
    if GUI2 and type(GUI2.GetColor) == "function" then
        local ok, cr, cg, cb, ca = pcall(GUI2.GetColor, GUI2, colorKey)
        if ok and type(cr) == "number" then
            r, g, b, a = cr, cg, cb, ca or 1
        end
    end
    for _, texture in pairs(border) do texture:SetVertexColor(r, g, b, a) end
end

function ButtonDrawer:_HideItemSurface(frame)
    self:_HideItemBacking(frame)
    local border = frame and self.itemBorders[frame]
    if border then
        for _, texture in pairs(border) do texture:Hide() end
    end
end

local function PlaceItem(frame, index, rows, columns, direction, config, panelPadding)
    local iconSize = ClampNumber(config.iconSize, DEFAULTS.iconSize, 16, 64)
    local spacingX = ClampNumber(config.spacingX, DEFAULTS.spacingX, 0, 32)
    local spacingY = ClampNumber(config.spacingY, DEFAULTS.spacingY, 0, 32)
    local row
    local column
    if direction.vertical then
        row = (index - 1) % rows
        column = math.floor((index - 1) / rows)
    else
        row = math.floor((index - 1) / columns)
        column = (index - 1) % columns
    end
    if direction.reverseX then column = columns - column - 1 end
    if direction.reverseY then row = rows - row - 1 end
    local slot = GetOrCreateSlot(index)
    if not slot then return false end
    slot:ClearAllPoints()
    slot:SetPoint(
        "TOPLEFT",
        background,
        "TOPLEFT",
        panelPadding + column * (iconSize + spacingX),
        -panelPadding - row * (iconSize + spacingY)
    )
    slot:SetSize(iconSize, iconSize)
    slot:SetFrameStrata(DRAWER_FRAME_STRATA)
    slot:SetFrameLevel(panel:GetFrameLevel() + 2)
    slot:EnableMouse(false)
    slot:Show()
    local snapshot = snapshots[frame]
    if snapshot then snapshot.slot = slot end
    if not snapshot then frame.drawerSlot = slot end
    buttonWriteGuard = true
    UnlockButtonLayers(frame)
    CallMethod(frame, "ClearAllPoints")
    CallMethod(frame, "SetPoint", "CENTER", slot, "CENTER", 0, 0)
    CallMethod(frame, "SetSize", iconSize, iconSize)
    CallMethod(frame, "SetScale", 1)
    CallMethod(frame, "SetFrameStrata", DRAWER_FRAME_STRATA)
    CallMethod(frame, "SetFrameLevel", panel:GetFrameLevel() + 3)
    ButtonDrawer:_WriteMouseState(frame, ButtonDrawer:_IsPanelInputEnabled(), true)
    buttonWriteGuard = false
    ButtonDrawer:_EnsureItemBacking(frame)
    ButtonDrawer:_EnsureItemBorder(frame)
    if snapshot then ApplySpecialVisual(frame, snapshot) end
    return true
end

LayoutPanel = function()
    if not panel or not background or not trigger then return end
    PruneLostButtons()
    CallMethod(panel, "SetClampedToScreen", true)

    local ownedExternal = 0
    local visibleExternal = 0
    for index = 1, #externalButtons do
        local button = externalButtons[index]
        if captured[button] == ownershipToken then
            ownedExternal = ownedExternal + 1
            if IsFrameShown(button) then visibleExternal = visibleExternal + 1 end
        end
    end
    local total = visibleExternal
    stats.externalButtons = ownedExternal
    SetCapturedStat(ownedExternal)
    local config = GetConfig()

    if total == 0 then
        ButtonDrawer:_SyncLayoutHolder(24, 24)
        trigger:Hide()
        for index = 1, #slotFrames do
            slotFrames[index]:Hide()
        end
        SetPanelShown(false, false)
        return
    end

    local iconSize = ClampNumber(config.iconSize, DEFAULTS.iconSize, 16, 64)
    local spacingX = ClampNumber(config.spacingX, DEFAULTS.spacingX, 0, 32)
    local spacingY = ClampNumber(config.spacingY, DEFAULTS.spacingY, 0, 32)
    local panelPadding = ClampNumber(config.panelPadding, DEFAULTS.panelPadding, 0, 16)
    local direction = ButtonDrawer.LAYOUT_DIRECTIONS[config.layoutDirection]
        or ButtonDrawer.LAYOUT_DIRECTIONS.rightDown
    local itemsPerLine = math.floor(
        ClampNumber(config.itemsPerLine, DEFAULTS.itemsPerLine, 1, MAX_ITEMS_PER_LINE) + 0.5
    )
    local rows
    local columns
    if direction.vertical then
        rows = math.min(total, itemsPerLine)
        columns = math.ceil(total / rows)
    else
        columns = math.min(total, itemsPerLine)
        rows = math.ceil(total / columns)
    end

    local iconAreaWidth = columns * iconSize + math.max(columns - 1, 0) * spacingX
    local iconAreaHeight = rows * iconSize + math.max(rows - 1, 0) * spacingY
    local panelWidth = panelPadding * 2 + iconAreaWidth
    local panelHeight = panelPadding * 2 + iconAreaHeight
    local holder = ButtonDrawer:_SyncLayoutHolder(panelWidth, panelHeight)
    background:SetSize(panelWidth, panelHeight)

    panel:ClearAllPoints()
    background:ClearAllPoints()
    panel:SetSize(panelWidth, panelHeight)
    if holder then
        panel:SetPoint("CENTER", holder, "CENTER", 0, 0)
    else
        local placement = ButtonDrawer.GetDefaultLayoutPlacement()
        local anchorFrame = _G[placement.anchor.relative] or _G.Minimap
        panel:SetPoint(
            placement.anchor.point,
            anchorFrame,
            placement.anchor.relativePoint,
            placement.offset.x,
            placement.offset.y
        )
    end
    background:SetAllPoints(panel)

    local itemIndex = 0
    for index = 1, #externalButtons do
        local button = externalButtons[index]
        if captured[button] == ownershipToken and IsFrameShown(button) then
            itemIndex = itemIndex + 1
            PlaceItem(button, itemIndex, rows, columns, direction, config, panelPadding)
        end
    end
    for index = itemIndex + 1, #slotFrames do
        slotFrames[index]:Hide()
    end

    ButtonDrawer:_SetDrawerInputEnabled(ButtonDrawer:_IsPanelInputEnabled(), true)
    ApplyBackgroundStyle(config)
    ApplyTriggerLayout(config)
    panel:Show()
    ButtonDrawer:_UpdatePanelHotspot()
end

local function Scan(reason)
    if not active then return false end
    if IsInCombat() then return false end

    IncrementScanStat()
    stats.lastReason = reason or "refresh"
    ClearTable(seenCandidates)
    RebuildDiscoveryBoundaries()
    ButtonDrawer:_ReleaseHiddenLandingPageButtons()
    ButtonDrawer:_ReleaseIgnoredButtons()
    PruneLostButtons()
    EnsureLibDBIconCallback()

    local cluster = _G.MinimapCluster
    local container = cluster and cluster.MinimapContainer
    ScanLandingReplacementParent(_G.Minimap)
    ScanLandingReplacementParent(_G.MinimapBackdrop)
    ScanLandingReplacementParent(cluster)
    ScanLandingReplacementParent(container)
    ScanLibDBIcon()

    local replacementActive = FindVisibleLandingReplacement() ~= nil
    if replacementActive then ReleaseSuppressedNativeLandingButtons() end

    ScanParent(_G.Minimap, replacementActive)
    ScanParent(_G.MinimapBackdrop, replacementActive)
    ScanParent(cluster, replacementActive)
    ScanParent(container, replacementActive)
    CaptureButton(_G.ExpansionLandingPageMinimapButton, "landing-page", replacementActive)
    CaptureButton(_G.GarrisonLandingPageMinimapButton, "landing-page", replacementActive)
    if nativeLandingRefreshRequested then
        nativeLandingRefreshRequested = false
        if not replacementActive and not ButtonDrawer:_IsExpansionEntryHidden() then
            RefreshHiddenNativeLandingButtons()
        end
    end
    local targetShown = stats.panelShown
    StopPanelAnimation()
    LayoutPanel(true)
    if targetShown and stats.capturedButtons > 0 then
        SettlePanelOpen()
    else
        stats.panelShown = false
        ParkPanel()
    end
    SetPendingStat(false)
    pendingAction = nil
    pendingReason = nil
    return true
end

local function HideUI(finalHide)
    SetPanelShown(false, false)
    StopCloseProgress()
    HideTriggerTooltip()
    if trigger then trigger:Hide() end
    if ButtonDrawer.panelHotspot then ButtonDrawer.panelHotspot:Hide() end
    for index = 1, #slotFrames do
        slotFrames[index]:Hide()
        if slotFrames[index].borderFrame then slotFrames[index].borderFrame:Hide() end
    end
    if background then background:Hide() end
    if closeProgress then closeProgress:Hide() end
    if finalHide and panel then panel:Hide() end
end

local function OnRegen()
    local action = pendingAction
    local reason = pendingReason
    pendingAction = nil
    pendingReason = nil
    SetPendingStat(false)

    if action == "restore" or not active then
        ReleaseExternalButtons()
        HideUI(true)
        SetCapturedStat(0)
        return
    end
    Scan(reason or "combat-deferred")
end

QueueForCombat = function(action, reason)
    -- The most recent lifecycle intent wins: disable -> enable during the same
    -- combat lockdown must refresh, while enable -> disable must restore.
    pendingAction = action
    pendingReason = reason or pendingReason
    SetPendingStat(true)
    if Event and type(Event.OffOwner) == "function" then
        Event:OffOwner(regenOwner)
        Event:OffOwner(recoveryOwner)
    end
    if Event and type(Event.Once) == "function" then
        Event:Once("PLAYER_REGEN_ENABLED", OnRegen, regenOwner, { moduleId = MODULE_ID })
    end
end

local function OnAddonLoaded()
    if not active then return end
    EnsureLibDBIconCallback()
    if QueueDiscovery then QueueDiscovery("addon-loaded") end
end

local function OnWorldReady()
    if active and QueueDiscovery then
        nativeLandingRefreshRequested = true
        QueueDiscovery("world-ready")
    end
end

local function OnDiscovery(_, reason)
    if not active then return end
    ButtonDrawer:Refresh(reason or "discovery")
end

local function OnLayout()
    if not active or not LayoutPanel then return end
    local targetShown = stats.panelShown
    StopPanelAnimation()
    LayoutPanel(true)
    if targetShown and stats.capturedButtons > 0 then
        SettlePanelOpen()
    else
        stats.panelShown = false
        ParkPanel()
    end
end

QueueDiscovery = function(reason)
    if not active then return false end
    SetPendingStat(true)
    if Event and type(Event.Emit) == "function" then
        Event:Emit(DISCOVERY_EVENT, reason or "discovery")
        return true
    end
    return ButtonDrawer:Refresh(reason or "discovery")
end

QueueLayout = function(reason)
    if not active then return false end
    if Event and type(Event.Emit) == "function" then
        Event:Emit(LAYOUT_EVENT, reason or "layout")
        return true
    end
    if LayoutPanel then LayoutPanel() end
    return true
end

local function AttachEvents()
    if not Event or type(Event.On) ~= "function" then return false end
    if type(Event.OffOwner) == "function" then Event:OffOwner(eventOwner) end
    Event:On(DISCOVERY_EVENT, OnDiscovery, eventOwner, {
        debounce = ADDON_LOAD_DEBOUNCE,
        moduleId = MODULE_ID,
    })
    Event:On(LAYOUT_EVENT, OnLayout, eventOwner, {
        debounce = 0.01,
        moduleId = MODULE_ID,
    })
    Event:On("ADDON_LOADED", OnAddonLoaded, eventOwner, {
        moduleId = MODULE_ID,
    })
    if type(Event.Once) == "function" then
        Event:Once("YUI_WORLD_READY", OnWorldReady, eventOwner, {
            moduleId = MODULE_ID,
        })
    end
    return true
end

local function DetachEvents()
    if Event and type(Event.OffOwner) == "function" then
        Event:OffOwner(eventOwner)
    end
end

local function OnMinimapMetricsChanged()
    if active and QueueLayout then QueueLayout("minimap-metrics") end
end

local function EnsureMinimapHooks()
    local minimap = _G.Minimap
    if minimapHooksInstalled or not minimap or type(_G.hooksecurefunc) ~= "function" then return end
    local installed = false
    for _, methodName in ipairs({ "SetScale", "SetSize" }) do
        if type(minimap[methodName]) == "function" then
            local ok = pcall(_G.hooksecurefunc, minimap, methodName, OnMinimapMetricsChanged)
            installed = installed or ok
        end
    end
    minimapHooksInstalled = installed
end

local function CreateUI()
    if panel and background and backgroundTexture and ButtonDrawer.panelHotspot and trigger and triggerIcon and closeProgress then
        StopPanelAnimation()
        StopCloseProgress()
        ParkPanel()
        return true
    end
    if panel then panel:Hide() end
    if background then background:Hide() end
    if ButtonDrawer.panelHotspot then ButtonDrawer.panelHotspot:Hide() end
    if trigger then trigger:Hide() end
    panel = nil
    background = nil
    ButtonDrawer.panelHotspot = nil
    backgroundTexture = nil
    closeProgress = nil
    closeProgressTexture = nil
    trigger = nil
    triggerIcon = nil
    if not GUI2 or not _G.UIParent or not _G.Minimap then return false end
    if type(GUI2.CreateFrame) ~= "function"
        or type(GUI2.CreateButtonFrame) ~= "function"
        or type(GUI2.CreateTexture) ~= "function"
    then
        return false
    end

    panel = GUI2:CreateFrame(_G.UIParent, {
        name = "YUI_YMap_ButtonDrawer",
        width = 1,
        height = 1,
        frameStrata = DRAWER_FRAME_STRATA,
        frameLevel = DRAWER_FRAME_LEVEL,
        mouse = false,
        clamped = true,
        hidden = true,
    })
    if not panel then return false end
    background = GUI2:CreateFrame(panel, {
        name = "YUI_YMap_ButtonDrawerBackground",
        width = 1,
        height = 1,
        frameStrata = DRAWER_BACKGROUND_STRATA,
        frameLevel = panel:GetFrameLevel(),
        mouse = true,
        hidden = true,
    })
    if not background then
        panel:Hide()
        panel = nil
        return false
    end
    background:EnableMouse(true)
    CallMethod(background, "SetMouseMotionEnabled", true)
    CallMethod(background, "SetMouseClickEnabled", false)
    backgroundTexture = GUI2:CreateTexture(background, {
        layer = "BACKGROUND",
        texture = "Interface\\Buttons\\WHITE8x8",
    })
    if not backgroundTexture then
        panel:Hide()
        panel = nil
        background = nil
        return false
    end
    backgroundTexture:SetAllPoints(background)
    if type(GUI2.CreateBorder) == "function" then
        GUI2:CreateBorder(background, "color.border.default")
    end

    ButtonDrawer.panelHotspot = GUI2:CreateFrame(_G.UIParent, {
        name = "YUI_YMap_ButtonDrawerPanelHotspot",
        width = 24,
        height = 24,
        frameStrata = DRAWER_FRAME_STRATA,
        frameLevel = panel:GetFrameLevel() + 1,
        mouse = true,
        clamped = true,
        hidden = true,
    })
    if not ButtonDrawer.panelHotspot then
        panel:Hide()
        panel = nil
        background = nil
        backgroundTexture = nil
        return false
    end
    ButtonDrawer.panelHotspot:EnableMouse(true)
    CallMethod(ButtonDrawer.panelHotspot, "SetMouseMotionEnabled", true)
    CallMethod(ButtonDrawer.panelHotspot, "SetMouseClickEnabled", false)
    ButtonDrawer.panelHotspot:SetScript("OnEnter", ButtonDrawer._OnPanelHotspotEnter)
    ButtonDrawer.panelHotspot:SetScript("OnLeave", ButtonDrawer._OnPanelHotspotLeave)

    closeProgress = GUI2:CreateFrame(panel, {
        name = "YUI_YMap_ButtonDrawerCloseProgress",
        width = 1,
        height = CLOSE_PROGRESS_HEIGHT,
        frameStrata = DRAWER_FRAME_STRATA,
        frameLevel = panel:GetFrameLevel() + 20,
        mouse = false,
        hidden = true,
    })
    if not closeProgress then
        panel:Hide()
        panel = nil
        background = nil
        backgroundTexture = nil
        return false
    end
    closeProgressTexture = GUI2:CreateTexture(closeProgress, {
        layer = "ARTWORK",
        texture = "Interface\\Buttons\\WHITE8x8",
    })
    if not closeProgressTexture then
        panel:Hide()
        panel = nil
        background = nil
        backgroundTexture = nil
        closeProgress = nil
        return false
    end
    closeProgressTexture:SetAllPoints(closeProgress)
    closeProgressTexture:SetVertexColor(1, 1, 1, 0.5)

    trigger = GUI2:CreateButtonFrame(_G.Minimap, {
        name = "YUI_YMap_ButtonDrawerTrigger",
        width = DEFAULTS.triggerSize,
        height = DEFAULTS.triggerSize,
    })
    if not trigger then
        panel:Hide()
        panel = nil
        background = nil
        return false
    end
    triggerIcon = GUI2:CreateTexture(trigger, {
        layer = "ARTWORK",
        atlas = ButtonDrawer.TRIGGER_ICON_ATLAS,
    })
    if not triggerIcon then
        trigger:Hide()
        panel:Hide()
        panel = nil
        background = nil
        trigger = nil
        return false
    end
    triggerIcon:SetPoint("CENTER")
    if type(trigger.SetHighlightTexture) == "function" then
        trigger:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
        local highlight = trigger:GetHighlightTexture()
        if highlight then
            highlight:SetVertexColor(1, 1, 1, 0.2)
            highlight:SetBlendMode("ADD")
        end
    end
    trigger:SetFrameStrata(DRAWER_FRAME_STRATA)
    trigger:SetFrameLevel((_G.Minimap:GetFrameLevel() or 0) + 20)
    if type(trigger.RegisterForClicks) == "function" then
        trigger:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    trigger:SetScript("OnClick", OnTriggerClick)
    trigger:HookScript("OnEnter", OnTriggerEnter)
    trigger:HookScript("OnLeave", OnTriggerLeave)
    trigger:Hide()

    panel:EnableMouse(false)
    CallMethod(panel, "SetMouseMotionEnabled", false)
    CallMethod(panel, "SetMouseClickEnabled", false)
    background:SetScript("OnEnter", OnPanelEnter)
    background:SetScript("OnLeave", OnPanelLeave)
    ParkPanel()
    EnsureMinimapHooks()
    return true
end

function ButtonDrawer:Enable(reason)
    local config = GetConfig()
    if config.enabled ~= true then
        self:Disable()
        return false
    end
    if active then
        return self:Refresh(reason or "enable")
    end
    if not CreateUI() or not AttachEvents() then
        SetEnabledStat(false)
        return false
    end

    active = true
    nativeLandingRefreshRequested = true
    SetEnabledStat(true)
    self:_SyncLayoutHolder(24, 24)
    EnsureLibDBIconCallback()
    return self:Refresh(reason or "enable")
end

function ButtonDrawer:SetSettingsPreview(enabled)
    enabled = enabled == true
    if enabled then
        local config = GetConfig()
        if not active or config.enabled ~= true or not trigger then return false end
        if not settingsPreviewActive then
            settingsPreviewPanelWasShown = stats.panelShown == true
        end
        settingsPreviewActive = true
        stats.settingsPreviewActive = true
        CancelHoverClose()
        ApplyTriggerLayout(config)
        SetPanelShown(true, false)
        return stats.capturedButtons > 0
    end

    if not settingsPreviewActive then return true end
    local restorePanel = settingsPreviewPanelWasShown == true
    settingsPreviewActive = false
    settingsPreviewPanelWasShown = false
    stats.settingsPreviewActive = false
    CancelHoverClose()
    if trigger then ApplyTriggerLayout(GetConfig()) end
    SetPanelShown(restorePanel, false)
    if restorePanel and IsHoverMode() and MaybeHideHoverPanel then
        MaybeHideHoverPanel()
    end
    return true
end

function ButtonDrawer:Disable()
    settingsPreviewActive = false
    settingsPreviewPanelWasShown = false
    stats.settingsPreviewActive = false
    active = false
    nativeLandingRefreshRequested = false
    landingRefreshGuard = false
    SetEnabledStat(false)
    self:_UnregisterLayoutHolder()
    CancelHoverClose()
    DetachEvents()
    DetachLibDBIconCallback()
    if Event and type(Event.OffOwner) == "function" then
        Event:OffOwner(regenOwner)
        Event:OffOwner(recoveryOwner)
    end
    pendingAction = nil
    pendingReason = nil
    SetPendingStat(false)
    HideUI(false)
    if IsInCombat() and #externalButtons > 0 then
        QueueForCombat("restore", "disable")
        return false
    end
    ReleaseExternalButtons()
    HideUI(true)
    SetCapturedStat(0)
    return true
end

function ButtonDrawer:Refresh(reason)
    local config = GetConfig()
    if config.enabled ~= true then
        self:Disable()
        return false
    end
    if not active then
        return self:Enable()
    end
    if IsInCombat() then
        QueueForCombat("refresh", reason or "refresh")
        return false
    end
    return Scan(reason or "refresh")
end

function ButtonDrawer:IsCaptured(frame)
    local snapshot = frame and snapshots[frame]
    return type(snapshot) == "table" and snapshot.owner == ownershipToken
end

function ButtonDrawer:GetStats(target)
    target = type(target) == "table" and target or {}
    target.buttonDiscoveryScans = stats.buttonDiscoveryScans
    target.capturedButtons = stats.capturedButtons
    target.restoreFailures = stats.restoreFailures
    target.pendingRefresh = stats.pendingRefresh
    target.buttonDrawerEnabled = stats.enabled
    target.buttonDrawerExternalButtons = stats.externalButtons
    target.buttonDrawerCompartmentButtons = stats.compartmentButtons
    target.buttonDrawerCompartmentEntries = stats.compartmentEntries
    target.buttonDrawerSkippedCandidates = stats.skippedCandidates
    target.buttonDrawerOwnershipLosses = stats.ownershipLosses
    target.buttonDrawerPanelShown = stats.panelShown
    target.buttonDrawerCompartmentHidden = stats.compartmentHidden
    target.drawerHoverCloseTimerActive = stats.drawerHoverCloseTimerActive
    target.drawerCloseTimerActive = stats.drawerHoverCloseTimerActive
    target.drawerTransitionState = stats.transitionState
    target.drawerAnimationActive = stats.animationActive
    target.drawerStyledLibDBIcons = stats.styledLibDBIcons
    target.drawerStyledLandingButtons = stats.styledLandingButtons
    target.drawerVisualRestoreFailures = stats.visualRestoreFailures
    target.drawerInteractiveButtons = stats.interactiveButtons
    target.drawerMouseStateRepairs = stats.mouseStateRepairs
    target.drawerInputRestoreFailures = stats.inputRestoreFailures
    target.drawerSettingsPreviewActive = stats.settingsPreviewActive
    target.buttonDrawerLastReason = stats.lastReason
    return target
end

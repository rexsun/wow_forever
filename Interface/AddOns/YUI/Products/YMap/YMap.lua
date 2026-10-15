local ADDON_NAME = ...
local YUI = _G.YUI
if not YUI or not YUI.YMap or (not YUI.IsForever and YUI.IsRetail == false) then return end

local YMap = YUI.YMap
YMap.name = "YMap"

local function Clamp(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value then return fallback end
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function Enum(value, allowed, fallback)
    return allowed[value] and value or fallback
end

local DEFAULT_SQUARE_BORDER_COLOR = { 0.22, 0.26, 0.32, 1 }
local DEFAULT_EXPERIENCE_COLOR = { 0.58, 0, 0.55, 1 }
local DEFAULT_STATUS_BAR_COLOR = { 0, 0, 0, 1 }

local function NormalizeColor(value, fallback)
    if type(value) ~= "table" then value = {} end
    value[1] = Clamp(value[1] or value.r, 0, 1, fallback[1])
    value[2] = Clamp(value[2] or value.g, 0, 1, fallback[2])
    value[3] = Clamp(value[3] or value.b, 0, 1, fallback[3])
    value[4] = Clamp(value[4] or value.a, 0, 1, fallback[4])
    value.r, value.g, value.b, value.a = nil, nil, nil, nil
    return value
end

local VALID_QUEUE_ANCHORS = {
    TOPLEFT = true,
    TOPRIGHT = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
}
local VALID_SQUARE_CLOCK_POSITIONS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}
VALID_SQUARE_CLOCK_POSITIONS.CENTER = true
local VALID_ZONE_NAME_MODES = { never = true, hover = true, always = true }
local VALID_SQUARE_CLOCK_MODES = { never = true, always = true, hover = true }
local VALID_COORDINATE_DISPLAY_MODES = { always = true, hover = true }
local VALID_COORDINATE_POSITIONS = VALID_SQUARE_CLOCK_POSITIONS
local VALID_DRAWER_EXPAND_MODES = { hoverIcon = true, hoverPanel = true, click = true }
local VALID_DRAWER_DIRECTIONS = {
    rightDown = true,
    leftDown = true,
    rightUp = true,
    leftUp = true,
    downRight = true,
    downLeft = true,
    upRight = true,
    upLeft = true,
}
local VALID_DRAWER_BACKGROUNDS = { none = true, solid = true, transparent = true }
local VALID_TRIGGER_POSITIONS = {
    topLeft = true,
    topRight = true,
    bottomLeft = true,
    bottomRight = true,
}
local VALID_STATUS_BAR_POSITIONS = {
    bottom = true,
    top = true,
    left = true,
    right = true,
}
local VALID_STATUS_BAR_TEXT_DISPLAYS = { hover = true, always = true }
local VALID_TEXT_OUTLINES = {inherit=true, none=true, outline=true, thick=true, shadow=true, outlineShadow=true}
local VALID_TEXT_SHADOWS = {inherit=true, on=true, off=true}
local DEFAULT_TEXT_COLOR = {1,1,1,1}

local function NormalizeTextStyle(config)
    config.font = type(config.font) == "string" and config.font ~= "" and config.font or "inherit"
    config.outline = Enum(config.outline, VALID_TEXT_OUTLINES, "inherit")
    config.shadow = Enum(config.shadow, VALID_TEXT_SHADOWS, "inherit")
    config.customColor = config.customColor == true
    config.color = NormalizeColor(config.color, DEFAULT_TEXT_COLOR)
    config.layoutMode = config.layoutMode == "custom" and "custom" or "auto"
    config.offsetX = Clamp(config.offsetX, -200, 200, 0)
    config.offsetY = Clamp(config.offsetY, -200, 200, 0)
    config.autoOffsetX = Clamp(config.autoOffsetX, -200, 200, 0)
    config.autoOffsetY = Clamp(config.autoOffsetY, -200, 200, 0)
end

local function NormalizeDB(db)
    if type(db) ~= "table" then return db end
    local worldMap = db.worldMap
    local minimap = db.minimap
    local drawer = db.buttonDrawer
    if type(worldMap) == "table" then
        if type(worldMap.directionLine) ~= "table" then worldMap.directionLine = {} end
        local line = worldMap.directionLine
        line.enabled = line.enabled == true
        line.style = line.style == "dashed" and "dashed" or "solid"
        line.thickness = Clamp(line.thickness, 1, 6, 2)
        line.dotSize = Clamp(line.dotSize, 1, 6, 3)
        line.dotSpacing = Clamp(line.dotSpacing, 4, 32, 8)
        line.color = NormalizeColor(line.color, YMap.Defaults.worldMap.directionLine.color)
        worldMap.scale = Clamp(worldMap.scale, 0.5, 2, 1)
        worldMap.fadeWhenMoving = worldMap.fadeWhenMoving == true
        worldMap.movingAlpha = Clamp(worldMap.movingAlpha, 0.1, 1, 0.8)
        if type(worldMap.reveal) ~= "table" then worldMap.reveal = {} end
        worldMap.reveal.enabled = worldMap.reveal.enabled ~= false
        worldMap.reveal.tint = worldMap.reveal.tint ~= false
        worldMap.reveal.color = NormalizeColor(worldMap.reveal.color, YMap.Defaults.worldMap.reveal.color)
    end
    if type(minimap) == "table" then
        minimap.style = minimap.style == "native" and "native" or "square"
        minimap.size = Clamp(minimap.size, 120, 400, 175)
        -- 保留旧 Profile 字段用于兼容；小地图最终边长只由 size 决定。
        minimap.scale = Clamp(minimap.scale, 0.5, 2, 1)
        minimap.zoneTextAlignment = minimap.zoneTextAlignment == "center" and "center" or "native"
        if type(minimap.nativeAppearance) == "table" then
            local appearance = minimap.nativeAppearance
            appearance.hideClock = appearance.hideClock ~= false
            appearance.hideCalendar = appearance.hideCalendar == true
            appearance.zoneNameFontSize = Clamp(appearance.zoneNameFontSize, 8, 24, 14)
        end
        if type(minimap.squareAppearance) == "table" then
            local appearance = minimap.squareAppearance
            appearance.borderWidth = Clamp(appearance.borderWidth, 0, 8, 1)
            appearance.borderColor = NormalizeColor(appearance.borderColor, DEFAULT_SQUARE_BORDER_COLOR)
            appearance.zoneNameMode = Enum(appearance.zoneNameMode, VALID_ZONE_NAME_MODES, "hover")
            appearance.zoneNameFontSize = Clamp(appearance.zoneNameFontSize, 8, 24, 11)
            if type(appearance.clock) ~= "table" then appearance.clock = {} end
            if type(appearance.zoneName) ~= "table" then appearance.zoneName = {} end
            NormalizeTextStyle(appearance.clock)
            NormalizeTextStyle(appearance.zoneName)
            appearance.clock.fontSize = Clamp(appearance.clock.fontSize, 0, 24, 0)
            if appearance.clock.fontSize > 0 and appearance.clock.fontSize < 8 then appearance.clock.fontSize = 8 end
            appearance.zoneName.position = Enum(appearance.zoneName.position, VALID_COORDINATE_POSITIONS, "TOP")
            appearance.clockMode = Enum(appearance.clockMode, VALID_SQUARE_CLOCK_MODES, "never")
            appearance.clockPosition = Enum(
                appearance.clockPosition,
                VALID_SQUARE_CLOCK_POSITIONS,
                "TOPRIGHT"
            )
            if type(appearance.coordinates) ~= "table" then
                appearance.coordinates = {}
            end
            if type(appearance.metrics) ~= "table" then appearance.metrics = {} end
            local metrics = appearance.metrics
            metrics.enabled = metrics.enabled == true
            metrics.showFPS = metrics.showFPS ~= false
            metrics.showLatency = metrics.showLatency ~= false
            metrics.displayMode = Enum(metrics.displayMode, VALID_COORDINATE_DISPLAY_MODES, "always")
            metrics.position = Enum(metrics.position, VALID_COORDINATE_POSITIONS, "BOTTOM")
            metrics.fontSize = Clamp(metrics.fontSize, 8, 24, 11)
            NormalizeTextStyle(metrics)
            metrics.fpsColor = NormalizeColor(metrics.fpsColor, DEFAULT_TEXT_COLOR)
            metrics.latencyColor = NormalizeColor(metrics.latencyColor, DEFAULT_TEXT_COLOR)
            metrics.spacing = Clamp(metrics.spacing, 8, 32, 12)
            if metrics.colorMode == nil then metrics.colorMode=metrics.customColor and "fixed" or "threshold" end
            if YUI.SystemMetrics and YUI.SystemMetrics.Display then YUI.SystemMetrics.Display:Normalize(metrics) end
            local coordinates = appearance.coordinates
            coordinates.enabled = coordinates.enabled == true
            coordinates.displayMode = Enum(
                coordinates.displayMode,
                VALID_COORDINATE_DISPLAY_MODES,
                "always"
            )
            coordinates.position = Enum(
                coordinates.position,
                VALID_COORDINATE_POSITIONS,
                "BOTTOM"
            )
            coordinates.fontSize = Clamp(coordinates.fontSize, 8, 24, 11)
            NormalizeTextStyle(coordinates)
        end
        if type(minimap.queue) == "table" then
            minimap.queue.size = Clamp(minimap.queue.size, 6, 64, 18)
            minimap.queue.anchor = Enum(minimap.queue.anchor, VALID_QUEUE_ANCHORS, "BOTTOMLEFT")
            minimap.queue.offsetX = Clamp(minimap.queue.offsetX, -200, 200, -5)
            minimap.queue.offsetY = Clamp(minimap.queue.offsetY, -200, 200, -5)
        end
        if type(minimap.belowWidget) == "table" then
            minimap.belowWidget.width = Clamp(minimap.belowWidget.width, 120, 500, 200)
        end
        if type(minimap.statusBars) ~= "table" then
            minimap.statusBars = YMap:CopyValue(YMap.Defaults.minimap.statusBars)
        end
        local statusBars = minimap.statusBars
        statusBars.experienceEnabled = statusBars.experienceEnabled == true
        statusBars.reputationEnabled = statusBars.reputationEnabled == true
        statusBars.position = Enum(statusBars.position, VALID_STATUS_BAR_POSITIONS, "bottom")
        statusBars.thickness = Clamp(statusBars.thickness, 8, 32, 12)
        if type(statusBars.texture) ~= "string"
            or statusBars.texture == ""
            or #statusBars.texture > 160 then
            statusBars.texture = "yui-g1"
        elseif YUI.GUI2 and type(YUI.GUI2.GetStatusBarTexture) == "function" then
            local ok, _, resolvedTexture = pcall(
                YUI.GUI2.GetStatusBarTexture,
                YUI.GUI2,
                statusBars.texture
            )
            if ok and resolvedTexture ~= statusBars.texture then
                statusBars.texture = "yui-g1"
            end
        end
        statusBars.experienceColor = NormalizeColor(
            statusBars.experienceColor,
            DEFAULT_EXPERIENCE_COLOR
        )
        statusBars.borderWidth = Clamp(statusBars.borderWidth, 0, 4, 1)
        statusBars.borderColor = NormalizeColor(
            statusBars.borderColor,
            DEFAULT_STATUS_BAR_COLOR
        )
        statusBars.backgroundColor = NormalizeColor(
            statusBars.backgroundColor,
            DEFAULT_STATUS_BAR_COLOR
        )
        statusBars.mapGap = Clamp(statusBars.mapGap, 0, 16, 2)
        statusBars.barGap = Clamp(statusBars.barGap, 0, 16, 1)
        statusBars.textDisplay = Enum(
            statusBars.textDisplay,
            VALID_STATUS_BAR_TEXT_DISPLAYS,
            "hover"
        )
        local squareElements = minimap.squareElements
        local difficulty = type(squareElements) == "table" and squareElements.difficulty or nil
        if type(difficulty) == "table" then
            difficulty.textStyle = difficulty.textStyle == "en" and "en" or "zh"
        end
    end
    if type(drawer) == "table" then
        drawer.iconSize = Clamp(drawer.iconSize, 16, 64, 28)
        drawer.spacingX = Clamp(drawer.spacingX, 0, 24, 4)
        drawer.spacingY = Clamp(drawer.spacingY, 0, 24, 4)
        drawer.expandMode = Enum(drawer.expandMode, VALID_DRAWER_EXPAND_MODES, "hoverIcon")
        if drawer.layoutDirection == "horizontal" then
            drawer.layoutDirection = "rightDown"
        elseif drawer.layoutDirection == "vertical" then
            drawer.layoutDirection = "downRight"
        end
        drawer.layoutDirection = Enum(drawer.layoutDirection, VALID_DRAWER_DIRECTIONS, "rightDown")
        drawer.itemsPerLine = math.floor(Clamp(drawer.itemsPerLine, 1, 16, 8) + 0.5)
        drawer.panelBackground = Enum(drawer.panelBackground, VALID_DRAWER_BACKGROUNDS, "transparent")
        drawer.panelPadding = Clamp(drawer.panelPadding, 0, 16, 4)
        drawer.triggerSize = Clamp(drawer.triggerSize, 10, 40, 20)
        drawer.triggerVisibility = "always"
        drawer.triggerPosition = Enum(drawer.triggerPosition, VALID_TRIGGER_POSITIONS, "bottomRight")
        drawer.triggerOffsetX = Clamp(drawer.triggerOffsetX, -100, 100, 2)
        drawer.triggerOffsetY = Clamp(drawer.triggerOffsetY, -100, 100, 2)
    end
    return db
end

local function Print(message)
    if YUI.Print then
        YUI:Print("YMap: " .. tostring(message))
    elseif print then
        print("YMap: " .. tostring(message))
    end
end

function YMap:T(key, fallback)
    local locale = YUI.Locale and YUI.Locale.Get and YUI.Locale:Get("YMap") or nil
    local value = locale and locale[key]
    if type(value) == "string" and value ~= "" then
        return value
    end
    return fallback or key
end

function YMap:GetProfile()
    if YUI.DB and YUI.DB.GetProfile then
        local profile = YUI.DB:GetProfile(self.Host and self.Host.productId or self.PRODUCT_ID)
        if type(profile) == "table" then return profile end
    end
    return nil
end

function YMap:EnsureDB()
    local profile = self:GetProfile()
    if type(profile) ~= "table" then
        self.db = self.db or self:CopyValue(self.Defaults)
        return NormalizeDB(self.db)
    end
    if type(profile[self.STORAGE_KEY]) ~= "table" then
        profile[self.STORAGE_KEY] = {}
    end
    self.db = profile[self.STORAGE_KEY]
    self:MergeDefaults(self.db)
    return NormalizeDB(self.db)
end

function YMap:GetDB()
    return self:EnsureDB()
end

function YMap:IsEnabled()
    if self.Host and self.Host.settingsMode == "toolbox"
        and YUI.Components and YUI.Components.IsToolboxEnabled
        and not YUI.Components:IsToolboxEnabled(self.Host.productId) then return false end
    local db = self:GetDB()
    return db and db.enabled == true
end

function YMap:SetEnabled(enabled, fromLifecycle)
    local db = self:GetDB()
    if not db then return false end
    enabled = enabled == true
    db.enabled = enabled
    if not fromLifecycle and YUI.Module and YUI.Module.SetEnabled then
        return YUI.Module:SetEnabled(self.PRODUCT_ID, enabled)
    end
    return true
end

function YMap:GetMinimapConflictReason()
    local reason
    local minimap = self.Minimap
    if minimap then
        if minimap.GetConflictReason then
            reason = minimap:GetConflictReason()
        end
        reason = reason or minimap.conflictReason
    end
    if not reason then
        local guard = self.ConflictGuard
        if guard and guard.GetReason then reason = guard:GetReason() end
    end
    if not reason then return nil end
    local keys = {
        ["unsupported-client"] = "conflict.unsupported_client",
        ["Blizzard_Minimap"] = "conflict.native_unavailable",
        ["YUI.GUI2"] = "conflict.gui_unavailable",
        ["MinimapParent"] = "conflict.parent_owned",
        ["GetMinimapShape"] = "conflict.shape_owned",
        ["ExternalMinimap"] = "conflict.detected",
        ["apply-error"] = "conflict.apply_error",
    }
    return self:T(keys[reason] or "conflict.detected", tostring(reason))
end

local function Call(subsystem, method, ...)
    local callback = subsystem and subsystem[method]
    if type(callback) ~= "function" then return true end
    local ok, result, detail = pcall(callback, subsystem, ...)
    if not ok then
        Print(result)
        return false, result
    end
    return result ~= false, detail
end

local function RuntimeIsActive()
    local runtime = YUI.Module
    local state = runtime and runtime.GetState and runtime:GetState(YMap.PRODUCT_ID)
    return state ~= nil
        and state.initialized == true
        and state.enabled == true
        and state.status == "enabled"
end

local function ApplyMinimapAndDrawer(db, reason)
    local minimapRequested = db.minimap.enabled == true
    local drawerRequested = minimapRequested and db.buttonDrawer.enabled == true
    local conflictBefore = YMap:GetMinimapConflictReason()
    local drawerReleased = false

    -- Release ownership before a minimap refresh/disable that must reclaim native
    -- frames. This keeps special buttons from being restored after the minimap has
    -- already calculated its final slots.
    if not drawerRequested or conflictBefore then
        Call(YMap.ButtonDrawer, "Disable")
        drawerReleased = true
    end

    local minimapActive = false
    if minimapRequested then
        minimapActive = Call(YMap.Minimap, "Enable", reason)
    else
        Call(YMap.Minimap, "Disable")
    end

    local conflictReason = YMap:GetMinimapConflictReason()
    local rawConflict = YMap.Minimap and YMap.Minimap.GetConflictReason
        and YMap.Minimap:GetConflictReason()
    if minimapRequested and (rawConflict == "ExternalMinimap"
        or rawConflict == "MinimapParent" or rawConflict == "GetMinimapShape") then
        local controller, snapshot
        if YMap.Minimap and type(YMap.Minimap.GetConflictController) == "function" then
            controller, snapshot = YMap.Minimap:GetConflictController()
        end
        if YUI.Yield then
            YUI.Yield:Set("minimap", controller, {
                status = "active",
                matches = snapshot and snapshot.matches,
                enabled = true,
            })
        end
    elseif YUI.Yield then
        YUI.Yield:Clear("minimap")
    end
    if drawerRequested and minimapActive and not conflictReason then
        Call(YMap.ButtonDrawer, "Enable", reason)
    elseif not drawerReleased then
        Call(YMap.ButtonDrawer, "Disable")
    end

    return minimapActive, conflictReason
end

function YMap:Initialize()
    self:EnsureDB()
    if self.Migration and self.Migration.Run and (not self.Host or self.Host.legacyMigration) then
        self.Migration:Run()
        NormalizeDB(self.db)
    end
    return true
end

function YMap:OnLifecycleEnable()
    local db = self:GetDB()
    if not db or db.enabled ~= true then return false end
    if self.Stats then
        self.Stats.enabled = true
        self.Stats.pendingRefresh = false
    end

    if db.worldMap.enabled == true then
        Call(self.WorldMap, "Enable")
    else
        Call(self.WorldMap, "Disable")
    end

    Call(self.DirectionLine, db.worldMap.enabled == true and db.worldMap.directionLine
        and db.worldMap.directionLine.enabled == true and "Enable" or "Disable")
    Call(self.MapReveal, db.worldMap.enabled == true and "Enable" or "Disable")
    Call(self.Markers, db.markers.enabled == true and "Enable" or "Disable")
    Call(self.WorldEvents, db.worldEvents.enabled == true and "Enable" or "Disable")
    local minimapActive, conflictReason = ApplyMinimapAndDrawer(db)
    if self.Stats then
        self.Stats.minimapActive = minimapActive == true and conflictReason == nil
        self.Stats.conflictBlocked = conflictReason ~= nil
    end
    return true
end

function YMap:OnLifecycleDisable()
    Call(self.DirectionLine, "Disable")
    Call(self.MapReveal, "Disable")
    Call(self.Markers, "Disable")
    Call(self.WorldEvents, "Disable")
    Call(self.ButtonDrawer, "Disable")
    Call(self.Minimap, "Disable")
    Call(self.WorldMap, "Disable")
    if YUI.Yield then YUI.Yield:Clear("minimap") end
    if self.Stats then
        self.Stats.enabled = false
        self.Stats.worldMapDriverActive = false
        self.Stats.minimapActive = false
        self.Stats.pendingRefresh = false
        self.Stats.capturedButtons = 0
        self.Stats.conflictBlocked = false
    end
    return true
end

function YMap:OnLifecycleProfileChanged()
    local runtimeState = YUI.Module and YUI.Module.GetState and YUI.Module:GetState(self.PRODUCT_ID)
    local wasRuntimeEnabled = runtimeState and runtimeState.enabled == true
    self.db = nil
    self:EnsureDB()
    if self.Migration and self.Migration.Run and (not self.Host or self.Host.legacyMigration) then
        self.Migration:Run()
    end
    -- Runtime:NotifyProfileChanged keeps the previous enabled bit until after this
    -- callback. Only enabled -> enabled needs an explicit clean re-entry. For every
    -- transition that changes the enabled bit, Runtime owns the following lifecycle
    -- call so disabled profiles are not cleaned up twice.
    if wasRuntimeEnabled and self:IsEnabled() then
        self:OnLifecycleDisable()
        self:OnLifecycleEnable()
    end
end

function YMap:OnLifecycleConfigChanged(reason)
    self:Refresh(reason or "config")
end

function YMap:OnLifecycleLayoutChanged()
    if RuntimeIsActive() and self.Minimap then
        Call(self.Minimap, "Refresh", "layout")
    end
end

function YMap:Enable()
    return self:SetEnabled(true)
end

function YMap:Disable()
    return self:SetEnabled(false)
end

function YMap:Refresh(reason)
    if YUI.Layout and YUI.Layout.InvalidateAnchorProvider then
        YUI.Layout:InvalidateAnchorProvider(self.LAYOUT_ID or "yui.product.ymap.minimap")
    end
    if not self:IsEnabled() or not RuntimeIsActive() then return false end
    local db = self:GetDB()
    if self.Stats then self.Stats.pendingRefresh = true end

    if db.worldMap.enabled == true then
        Call(self.WorldMap, "Enable", reason)
    else
        Call(self.WorldMap, "Disable")
    end

    Call(self.DirectionLine, db.worldMap.enabled == true and db.worldMap.directionLine
        and db.worldMap.directionLine.enabled == true and "Enable" or "Disable")
    Call(self.MapReveal, db.worldMap.enabled == true and "Enable" or "Disable")
    Call(self.Markers, db.markers.enabled == true and "Enable" or "Disable")
    Call(self.WorldEvents, db.worldEvents.enabled == true and "Enable" or "Disable")
    local minimapActive, conflictReason = ApplyMinimapAndDrawer(db, reason)

    if self.Stats then
        self.Stats.minimapActive = minimapActive == true and conflictReason == nil
        self.Stats.conflictBlocked = conflictReason ~= nil
        self.Stats.pendingRefresh = false
    end
    return true
end

function YMap:OpenSettings(tab)
    if tab and self.SetSettingsTab then self:SetSettingsTab(tab) end
    if self.Host and self.Host.settingsMode == "toolbox" then
        return YUI.Settings:OpenComponentFeature(self.PRODUCT_ID)
    end
    if YUI.Settings and YUI.Settings.OpenProduct then
        return YUI.Settings:OpenProduct(self.PRODUCT_ID, self.SETTINGS_ENTRY)
    end
    if YUI.OpenSettings then
        return YUI:OpenSettings("YMap", self.PRODUCT_ID)
    end
    return false
end

local function RegisterCommands()
    if not (YUI.Commands and YUI.Commands.Register) then return end
    YUI.Commands:Register({
        id = "ymap",
        productId = YMap.Host and YMap.Host.productId or "suite",
        aliases = { "/ymap" },
        handler = function()
            YMap:OpenSettings()
        end,
    })
end

RegisterCommands()

if YUI.RegisterProduct then
    YUI:RegisterProduct({
        id = YMap.PRODUCT_ID,
        title = "YMap",
        titleKey = "product.title",
        titleNamespace = "YMap",
        shortTitle = "YMap",
        shortTitleKey = "product.short_title",
        shortTitleNamespace = "YMap",
        notes = "地图增强产品",
        notesKey = "product.notes",
        notesNamespace = "YMap",
        author = "阿言",
        addonName = ADDON_NAME or YUI.AddonName,
        profileExportPrefix = "!YUI-YMap-v1:",
        settingsScope = YMap.PRODUCT_ID,
        settings = {
            enabled = not YMap.Host or YMap.Host.settingsMode == "navigation",
            entry = YMap.SETTINGS_ENTRY,
            commonPages = { "core.profiles", "core.about" },
            minimapIcon = false,
        },
        db = {
            enabled = false,
            savedVariable = YMap.Host and YMap.Host.savedVariable or "YUI_DB",
            storageKey = YMap.STORAGE_KEY,
        },
        commands = {},
    })
end

if YUI.Module and YUI.Module.Register then
    YUI.Module:Register({
        id = YMap.PRODUCT_ID,
        name = "YMap",
        product = YMap.Host and YMap.Host.productId or YMap.PRODUCT_ID,
        scope = YMap.PRODUCT_ID,
        defaultEnabled = false,
        owner = YMap,
        dependencies = { "core.db", "core.event", "core.locale", "core.api", "gui", "settings" },
        getEnabled = function(owner)
            return owner:IsEnabled()
        end,
        setEnabled = function(owner, enabled)
            return owner:SetEnabled(enabled, true)
        end,
        OnInitialize = "Initialize",
        OnEnable = "OnLifecycleEnable",
        OnDisable = "OnLifecycleDisable",
        OnProfileChanged = "OnLifecycleProfileChanged",
        OnConfigChanged = "OnLifecycleConfigChanged",
        OnLayoutChanged = "OnLifecycleLayoutChanged",
    })
end

if YUI.Event and YUI.Event.On then
    YUI.Event:On("YUI_DB_READY", function()
        YMap:EnsureDB()
        if YMap.Migration and YMap.Migration.Run and (not YMap.Host or YMap.Host.legacyMigration) then
            YMap.Migration:Run()
        end
    end, YMap, {
        priority = 4000,
        traceName = "YMap:EnsureDB",
        moduleId = YMap.PRODUCT_ID,
        phase = "YUI_DB_READY",
    })
end

-- Transfer ownership follows the host profile, independently of product DB creation.
local Transfer = YUI.Settings and YUI.Settings.ConfigTransfer
if Transfer then
    local layoutIds = { YMap.LAYOUT_ID, YMap.BELOW_WIDGET_LAYOUT_ID, "yui.product.ymap.buttonDrawer" }
    local legacyPaths = {
        ["component.map_enhancement"] = { "MapEnhancement_Config", "markers" },
        ["component.world_event_tracker"] = { "WorldEventTracker_Config", "worldEvents" },
    }
    local function ValidPayload(payload, path, legacy)
        if type(payload) ~= "table" or type(payload.data) ~= "table"
            or type(payload.present) ~= "table" or type(payload.layouts) ~= "table"
            or type(payload.layoutPresent) ~= "table"
            or type(payload.present[path]) ~= "boolean" then return false end
        local allowed = { data = true, present = true, layouts = true, layoutPresent = true }
        if legacy then allowed.enabled = true else allowed.legacyMapSections = true end
        for key in pairs(payload) do if not allowed[key] then return false end end
        for key in pairs(payload.present) do if key ~= path then return false end end
        for key, value in pairs(payload.data) do
            if key ~= path or payload.present[path] ~= true or type(value) ~= "table" then return false end
        end
        if payload.present[path] and type(payload.data[path]) ~= "table" then return false end
        if legacy then
            return type(payload.enabled) == "boolean" and next(payload.layouts) == nil
                and next(payload.layoutPresent) == nil
        end
        local layouts = {}
        for _, id in ipairs(layoutIds) do
            layouts[id] = true
            if type(payload.layoutPresent[id]) ~= "boolean" then return false end
        end
        for id in pairs(payload.layoutPresent) do if not layouts[id] then return false end end
        for id, value in pairs(payload.layouts) do
            if not layouts[id] or type(value) ~= "table" then return false end
        end
        return true
    end
    local function MergeLegacy(aliases, context)
        local canonical = context.canonical
        local payload
        if canonical then
            if canonical.entry.schemaVersion ~= 1 or not ValidPayload(canonical.payload, "YMap") then return nil end
            payload = YMap:CopyValue(canonical.payload)
        else
            payload = { data = { YMap = {} }, present = { YMap = true }, layouts = {},
                layoutPresent = {}, legacyMapSections = true }
            for _, id in ipairs(layoutIds) do payload.layoutPresent[id] = false end
        end
        for id, source in pairs(aliases) do
            local mapping = legacyPaths[id]
            if not mapping or source.schemaVersion ~= 1
                or not ValidPayload(source.payload, mapping[1], true) then return nil end
            local db = payload.data.YMap
            if not db then db = {}; payload.data.YMap = db; payload.present.YMap = true end
            if db[mapping[2]] == nil then
                local config = YMap:CopyValue(source.payload.data[mapping[1]] or {})
                config.enabled = source.payload.enabled
                db[mapping[2]] = config
                if canonical and config.enabled and db.enabled ~= true then
                    -- The old independent feature did not activate the disabled map product.
                    for _, key in ipairs({ "minimap", "worldMap", "buttonDrawer" }) do
                        db[key] = type(db[key]) == "table" and db[key] or {}
                        db[key].enabled = false
                    end
                    db.enabled = true
                end
            end
        end
        return payload
    end
    Transfer:RegisterModule({
        id = "product.ymap", kind = "product", schemaVersion = 1,
        labelKey = "product.title", labelNamespace = "YMap",
        productId = function() return YMap.Host and YMap.Host.productId or "suite" end,
        clients = { retail = true, forever = true }, dataPaths = { "YMap" }, layoutIds = layoutIds,
        requiresReload = true,
        importAliases = { "component.map_enhancement", "component.world_event_tracker" },
        mergeCanonicalImportAliases = true,
        mergeImportAliases = MergeLegacy,
        normalize = function(payload, context)
            if not ValidPayload(payload, "YMap") then return nil, "invalid_module_payload" end
            if payload.legacyMapSections ~= nil then
                if payload.legacyMapSections ~= true or payload.present.YMap ~= true then
                    return nil, "invalid_module_payload"
                end
                local imported = payload.data.YMap
                for key in pairs(imported) do
                    if key ~= "markers" and key ~= "worldEvents" then return nil, "invalid_module_payload" end
                end
                local preview = context and (context.previewNewProfile or context.importNewProfile)
                local profile = not preview and YMap:GetProfile() or nil
                local db = YMap:CopyValue(profile and profile.YMap or YMap.Defaults)
                if not (profile and profile.YMap) then
                    db.minimap.enabled = false
                    db.worldMap.enabled = false
                    db.buttonDrawer.enabled = false
                    db.markers.enabled = false
                    db.worldEvents.enabled = false
                end
                for key, value in pairs(imported) do db[key] = value end
                -- Independent legacy features must remain usable when no map product existed.
                if imported.markers and imported.markers.enabled
                    or imported.worldEvents and imported.worldEvents.enabled then
                    if db.enabled ~= true then
                        for _, key in ipairs({ "minimap", "worldMap", "buttonDrawer" }) do
                            db[key] = type(db[key]) == "table" and db[key] or {}
                            db[key].enabled = false
                        end
                    end
                    db.enabled = true
                end
                payload.data.YMap = db
                local layout = YUI.Layout
                for _, id in ipairs(layoutIds) do
                    local placement = not preview and layout and layout._private
                        and layout._private.GetSavedPlacement and layout._private.GetSavedPlacement(id)
                    payload.layouts[id] = placement and YMap:CopyValue(placement) or nil
                    payload.layoutPresent[id] = placement ~= nil and placement ~= false
                end
                payload.legacyMapSections = nil
            end
            return payload
        end,
    })
end

if YUI.Components and YUI.Components.Register then
    YUI.Components:Register({
        id = YMap.PRODUCT_ID,
        kind = "product",
        product = YMap.Host and YMap.Host.productId or YMap.PRODUCT_ID,
        defaultEnabled = YMap.Defaults.enabled,
        displayName = YMap.Host and YMap.Host.settingsMode == "toolbox" and YMap:T("settings.toolbox_title", "Map Enhancement") or "YMap",
        localeNamespace = "YMap",
        nameKey = YMap.Host and YMap.Host.settingsMode == "toolbox" and "settings.toolbox_title" or "product.title",
        description = YMap:T("product.description", "地图增强产品。"),
        tags = { "实用功能", "美化皮肤" },
        settingsMode = YMap.Host and YMap.Host.settingsMode == "toolbox" and "inline" or "external",
        toolboxManaged = YMap.Host and YMap.Host.settingsMode == "toolbox",
        name = YMap.Host and YMap.Host.settingsMode == "toolbox" and YMap:T("settings.toolbox_title", "Map Enhancement") or nil,
        RenderSettings = function(_, parent, context) return YMap:RenderSettings(parent, context) end,
        OnSettingsLeave = function() YMap:OnSettingsLeave() end,
        standalone = false,
        order = 920,
        storageKey = YMap.STORAGE_KEY,
        sourceRoot = "Products\\YMap",
        modSwitchImage = "modswitch\\mapenhancement-bg.png",
        modSwitchImageCrop = false,
        versions = { "mainline" },
        getEnabled = function()
            return YMap:IsEnabled()
        end,
        setEnabled = function(_, enabled)
            return YMap:SetEnabled(enabled)
        end,
        getEffectiveState = function()
            local reason = YMap:GetMinimapConflictReason()
            if reason and YMap:IsEnabled() then
                return { effective = true, partial = true, reason = reason, tone = "warning" }
            end
            return { effective = YMap:IsEnabled() }
        end,
        openSettings = function()
            return YMap:OpenSettings()
        end,
    })
end

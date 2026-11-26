local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.YMap or (YUI.IsRetail == false and not YUI.IsForever) then return end

local Event = YUI.Event
local MapEnhancement = YUI.YMap.Markers or {}
YUI.YMap.Markers = MapEnhancement

local MAP_ADDON = "Blizzard_WorldMap"
local PIN_TEMPLATE = "YUIMapMarkersPinTemplate"
local QUICK_FILTER_TEMPLATE = "YUIMapMarkersQuickFilterButtonTemplate"
local RXP_ADDON = "RXPGuides"
local RXP_TORNADO_MAP_ID = 2521
local RXP_TORNADO_TOOLTIP = "Tornado"
local PROFESSION_SCOPE_LEARNED = "learned"
local PROFESSION_SCOPE_ALL = "all"
local PROFESSION_SCOPE_NONE = "none"
local CATEGORY_ORDER = { "travel", "service", "equipment", "collection", "trainer", "special" }
local CATEGORY_KEYS = {}
for index = 1, #CATEGORY_ORDER do CATEGORY_KEYS[CATEGORY_ORDER[index]] = true end

local DEFAULTS = {
    displayMode = YUI.IsRetail and "text" or "icon",
    iconSize = 14,
    professionScope = "auto",
    markersHidden = false,
    serviceFilters = {},
    fontSize = 11,
    buttonOffsetX = 0,
    buttonOffsetY = 0,
    fontOutline = "OUTLINE",
    showTooltips = true,
    enableWaypoints = true,
    hideRxpTornadoPins = true,
    maps = {},
}

local runtime = {
    enabled = false,
    provider = nil,
    map = nil,
    addonOwner = {},
    eventOwner = {},
    profileCallbacksRegistered = false,
    zoomMapID = nil,
    compactZoom = false,
    pendingCombatRefresh = false,
    quickFilterButton = nil,
    primaryProfessionIDs = {},
    primaryProfessionCount = 0,
    normalizedConfig = nil,
    rxpGuide = nil,
    rxpFilterEnabled = nil,
    rxpFilteredCount = 0,
    stats = { refreshes = 0, activePins = 0, providerAttached = false, zoomModeChanges = 0 },
}

local rxpHooked = setmetatable({}, { __mode = "k" })

local function T(key, fallback)
    local locale = YUI.Locale and YUI.Locale:Get("YMapMarkers") or nil
    local value = locale and locale[key]
    if not value or value == "" or value == key then return fallback or key end
    return value
end

local function CopyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            CopyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function ClampColorChannel(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return math.max(0, math.min(1, value))
end

local function GetDefaultCategoryColor(category)
    local data = MapEnhancement.Data
    local definition = data and data.categories and data.categories[category]
    local color = definition and definition.color
    return type(color) == "table" and color or { 1, 1, 1 }
end

local function CopyCategoryColor(value, fallback)
    fallback = fallback or { 1, 1, 1 }
    value = type(value) == "table" and value or fallback
    return {
        ClampColorChannel(value[1] or value.r, fallback[1]),
        ClampColorChannel(value[2] or value.g, fallback[2]),
        ClampColorChannel(value[3] or value.b, fallback[3]),
    }
end

local function CategoryColorsEqual(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    for index = 1, 3 do
        if math.abs((tonumber(left[index]) or 0) - (tonumber(right[index]) or 0)) > 0.0005 then
            return false
        end
    end
    return true
end

local function PruneEmptyTable(config, key)
    local value = config and config[key]
    if type(value) == "table" and next(value) == nil then config[key] = nil end
end

local function NormalizeSparseCategories(config)
    local categories = config.categories
    if type(categories) == "table" then
        for category, value in pairs(categories) do
            if not CATEGORY_KEYS[category] or value ~= false then categories[category] = nil end
        end
        PruneEmptyTable(config, "categories")
    else
        config.categories = nil
    end

    local categoryColors = config.categoryColors
    if type(categoryColors) == "table" then
        for category, value in pairs(categoryColors) do
            if not CATEGORY_KEYS[category] or type(value) ~= "table" then
                categoryColors[category] = nil
            else
                local defaultColor = GetDefaultCategoryColor(category)
                local normalized = CopyCategoryColor(value, defaultColor)
                categoryColors[category] = CategoryColorsEqual(normalized, defaultColor) and nil or normalized
            end
        end
        PruneEmptyTable(config, "categoryColors")
    else
        config.categoryColors = nil
    end
end

local function NormalizeButtonOffset(value)
    value = tonumber(value) or 0
    if value ~= value then return 0 end
    return math.max(-500, math.min(500, math.floor(value + 0.5)))
end

function MapEnhancement:GetConfig()
    local config = YUI.YMap:GetDB().markers
    CopyDefaults(config, DEFAULTS)
    if YUI.IsForever then config.showOpposingFactionNPCs = config.showOpposingFactionNPCs == true end
    config.hideRxpTornadoPins = config.hideRxpTornadoPins ~= false
    -- 正式服只提供文字；Forever 保留原有模式及默认值。
    config.buttonOffsetX = NormalizeButtonOffset(config.buttonOffsetX)
    config.buttonOffsetY = NormalizeButtonOffset(config.buttonOffsetY)
    if YUI.IsRetail then config.displayMode = "text"
    elseif config.displayMode ~= "text" then config.displayMode = "icon" end
    config.iconSize = math.max(10, math.min(32, tonumber(config.iconSize) or DEFAULTS.iconSize))
    if config.professionScope ~= "learned" and config.professionScope ~= "all" and config.professionScope ~= "none" then config.professionScope = "auto" end
    config.fontSize = math.max(8, math.min(24, tonumber(config.fontSize) or DEFAULTS.fontSize))
    if runtime.normalizedConfig ~= config then
        NormalizeSparseCategories(config)
        runtime.normalizedConfig = config
    end
    return config
end

MapEnhancement.GetConfig = MapEnhancement.GetConfig

local function IsRXPLoaded()
    if not YUI.IsForever then return false end
    local System = YUI.API and YUI.API.System
    if not (System and type(System.IsAddOnLoaded) == "function") then return false end
    local ok, loaded = pcall(System.IsAddOnLoaded, RXP_ADDON)
    return ok and loaded == true
end

local function GetRXPAddon()
    if not IsRXPLoaded() then return nil end
    local stub = _G.LibStub
    if not (stub and type(stub.GetLibrary) == "function") then return nil end
    local ace = stub:GetLibrary("AceAddon-3.0", true)
    if not (ace and type(ace.GetAddon) == "function") then return nil end
    local rxp = ace:GetAddon(RXP_ADDON, true)
    if not (rxp and type(rxp.UpdateMap) == "function") then return nil end
    return rxp
end

function MapEnhancement:IsRXPCompatibilityAvailable()
    return GetRXPAddon() ~= nil
end

-- RXP 的 Skyborne 指南把龙卷风刷新点写成固定 .pin；只改运行时元素，不动指南文件。
local function ApplyRXPTornadoFilter(rxp, enabled)
    local guide = rxp and rxp.currentGuide
    if not guide or type(guide.steps) ~= "table" then
        runtime.rxpGuide, runtime.rxpFilterEnabled, runtime.rxpFilteredCount = nil, nil, 0
        return 0
    end
    if runtime.rxpGuide == guide and runtime.rxpFilterEnabled == enabled then
        return runtime.rxpFilteredCount or 0
    end
    runtime.rxpGuide, runtime.rxpFilterEnabled = guide, enabled
    local count = 0
    for _, step in ipairs(guide.steps) do
        local elements = type(step) == "table" and step.elements or nil
        if type(elements) == "table" then
            for _, element in ipairs(elements) do
                if element.tag == "pin" and element.mapTooltip == RXP_TORNADO_TOOLTIP
                    and tonumber(element.zone) == RXP_TORNADO_MAP_ID then
                    if enabled then
                        if not element.__yuiRxpTornadoFiltered then
                            element.__yuiRxpTornadoOriginalHidePin = element.hidePin
                            element.__yuiRxpTornadoFiltered = true
                        end
                        element.hidePin = true
                        count = count + 1
                    elseif element.__yuiRxpTornadoFiltered then
                        element.hidePin = element.__yuiRxpTornadoOriginalHidePin
                        element.__yuiRxpTornadoOriginalHidePin = nil
                        element.__yuiRxpTornadoFiltered = nil
                    end
                end
            end
        end
    end
    runtime.rxpFilteredCount = count
    return count
end

local function EnsureRXPHook()
    local rxp = GetRXPAddon()
    if not rxp or rxpHooked[rxp] then return rxp end
    local original = rxp.UpdateMap
    if type(original) ~= "function" then return nil end
    rxp.UpdateMap = function(self, ...)
        local config = MapEnhancement:GetConfig()
        local enabled = runtime.enabled and config.hideRxpTornadoPins ~= false
        ApplyRXPTornadoFilter(rxp, enabled)
        return original(self, ...)
    end
    rxpHooked[rxp] = true
    return rxp
end

function MapEnhancement:RefreshRXPFilter(refreshPins)
    if not runtime.enabled then return false end
    local rxp = EnsureRXPHook()
    if not rxp then return false end
    local config = self:GetConfig()
    ApplyRXPTornadoFilter(rxp, config.hideRxpTornadoPins ~= false)
    if refreshPins and _G.WorldMapFrame then rxp:UpdateMap(true) end
    return true
end


-- Forever 的世界地图枚举不提供可靠的角色解锁否定值；航线窗口与有向连接提供证据。
local function GetFlightKnowledge()
    local db = YUI.DB and YUI.DB:GetAceDB()
    if db and db.char then
        db.char.ymapKnownFlightsForever = db.char.ymapKnownFlightsForever or {}
        return db.char.ymapKnownFlightsForever
    end
    runtime.flightKnowledge = runtime.flightKnowledge or {}
    return runtime.flightKnowledge
end

function MapEnhancement:CaptureFlightKnowledge()
    if not (YUI.IsForever and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return end
    local mapID = GetTaxiMapID and GetTaxiMapID()
    if not mapID then return end
    local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes,mapID)
    if not ok or type(nodes) ~= "table" then return end
    local states = Enum and Enum.FlightPathState or {}
    local current, reachable, unreachable = states.Current or 0, states.Reachable or 1, states.Unreachable or 2
    local hasCurrent = false
    for _, node in ipairs(nodes) do
        if not node.isMapLayerTransition and node.state == current and self.Data:IsPlayerFlight(node.nodeID) then hasCurrent = true; break end
    end
    if not hasCurrent then return end -- 空响应或非当前航线图不构成同步证据。
    local known = GetFlightKnowledge()
    local usable, blocked = {}, {}
    for _, node in ipairs(nodes) do
        if not node.isMapLayerTransition and self.Data:IsPlayerFlight(node.nodeID) then
            if node.state == current or node.state == reachable then
                known[node.nodeID] = true
                usable[node.nodeID] = true
            elseif node.state == unreachable then
                blocked[node.nodeID] = true
            end
        end
    end
    -- 仅同一窗口可达起点的直接航线可证明未开启；不把历史已知或缺失节点用于推断。
    for from in pairs(usable) do
        for _, to in ipairs(self.Data.flightRoutes and self.Data.flightRoutes[from] or {}) do
            if blocked[to] and known[to] ~= true then known[to] = false end
        end
    end
end

function MapEnhancement:ForgetFlightNegatives()
    if not YUI.IsForever then return end
    local known = GetFlightKnowledge()
    for nodeID, value in pairs(known) do
        if value == false then known[nodeID] = nil end
    end
end

function MapEnhancement:NeedsFlightSync()
    if not YUI.IsForever then return false end
    local known = GetFlightKnowledge()
    return self.Data:HasUnsyncedFlight(known)
end

function MapEnhancement:GetFlightState(nodeID,node)
    if YUI.IsForever then
        if not self.Data:IsPlayerFlight(nodeID) then return nil end
        local state = GetFlightKnowledge()[nodeID]
        if state == true then return "discovered" end
        if state == false then return "undiscovered" end
        if node and node.isUndiscovered == true then return "undiscovered" end
        return "unknown"
    end
    return node and type(node.isUndiscovered) == "boolean"
        and (node.isUndiscovered and "undiscovered" or "discovered") or "unknown"
end

local ProviderMixin = {}

local nativeFlightsHidden = setmetatable({}, {__mode="k"})
local nativeFlightHooked = false
local function HideDuplicateFlight(pin, info)
    if not runtime.enabled or not info then return end
    local map = pin.GetMap and pin:GetMap()
    if map ~= runtime.map then return end
    local mapID = map:GetMapID()
    local provider = runtime.provider
    local stitchedFlights = provider and provider.refreshedMapID == mapID and provider.stitchedFlights
    local duplicate
    if stitchedFlights then
        duplicate = stitchedFlights[info.nodeID]
    else
        local config = MapEnhancement:GetConfig()
        duplicate = config.maps[mapID] ~= false and MapEnhancement.Data
            and MapEnhancement.Data:HasFlight(mapID, info.nodeID, config.showOpposingFactionNPCs == true)
    end
    if duplicate then
        nativeFlightsHidden[pin] = true
        pin:Hide()
    end
end

local function SyncNativeFlights(restore)
    local map = runtime.map
    if not (nativeFlightHooked and map and map.EnumeratePinsByTemplate) then return end
    for pin in map:EnumeratePinsByTemplate("FlightPointPinTemplate") do
        if restore then
            if nativeFlightsHidden[pin] then pin:Show(); nativeFlightsHidden[pin] = nil end
        else HideDuplicateFlight(pin,pin.poiInfo) end
    end
end

local Refresh
local UpdateQuickFilterButton

function MapEnhancement:GetCategoryEnabled(category, config)
    if not CATEGORY_KEYS[category] then return true end
    config = config or self:GetConfig()
    return type(config.categories) ~= "table" or config.categories[category] ~= false
end

function MapEnhancement:SetCategoryEnabled(category, enabled, config)
    if not CATEGORY_KEYS[category] then return false end
    config = config or self:GetConfig()
    if enabled == false then
        if type(config.categories) ~= "table" then config.categories = {} end
        config.categories[category] = false
    elseif type(config.categories) == "table" then
        config.categories[category] = nil
        PruneEmptyTable(config, "categories")
    end
    return true
end

function MapEnhancement:GetCategoryColor(category, config)
    local defaultColor = GetDefaultCategoryColor(category)
    config = config or self:GetConfig()
    local overrides = config and config.categoryColors
    local override = type(overrides) == "table" and overrides[category] or nil
    return type(override) == "table" and override or defaultColor
end

function MapEnhancement:SetCategoryColor(category, color, config)
    if not CATEGORY_KEYS[category] then return false end
    config = config or self:GetConfig()
    local defaultColor = GetDefaultCategoryColor(category)
    local normalized = CopyCategoryColor(color, defaultColor)
    if CategoryColorsEqual(normalized, defaultColor) then
        if type(config.categoryColors) == "table" then
            config.categoryColors[category] = nil
            PruneEmptyTable(config, "categoryColors")
        end
    else
        if type(config.categoryColors) ~= "table" then config.categoryColors = {} end
        config.categoryColors[category] = normalized
    end
    return true
end

function MapEnhancement:ResetCategories(config)
    config = config or self:GetConfig()
    config.categories = nil
    config.categoryColors = nil
    config.hideRxpTornadoPins = true
    return true
end

local function RefreshPrimaryProfessions()
    local professionAPI = YUI.API and YUI.API.Profession
    local learned = runtime.primaryProfessionIDs
    for skillLineID in pairs(learned) do learned[skillLineID] = nil end

    local count = 0
    if professionAPI and type(professionAPI.GetProfessions) == "function"
        and type(professionAPI.GetProfessionInfo) == "function" then
        local first, second = professionAPI.GetProfessions()
        local professionIndexes = { first, second }
        for index = 1, 2 do
            local professionIndex = professionIndexes[index]
            if professionIndex then
                local skillLineID = professionAPI.GetProfessionInfo(professionIndex)
                if type(skillLineID) == "number" and not learned[skillLineID] then
                    learned[skillLineID] = true
                    count = count + 1
                end
            end
        end
    end
    runtime.primaryProfessionCount = count
end

local function GetAutomaticProfessionScope()
    return runtime.primaryProfessionCount >= 2 and PROFESSION_SCOPE_LEARNED or PROFESSION_SCOPE_ALL
end

local function GetResolvedProfessionScope()
    local scope = MapEnhancement:GetConfig().professionScope
    return scope ~= "auto" and scope or GetAutomaticProfessionScope()
end

local function IsAllowedForProfession(entry, config)
    if entry.category ~= "profession" then
        return MapEnhancement:GetCategoryEnabled(entry.category, config)
    end

    local scope = GetResolvedProfessionScope()
    if scope == PROFESSION_SCOPE_NONE then return false end
    if scope == PROFESSION_SCOPE_ALL then return true end

    local skillLineIDs = entry.professionSkillLineIDs
    if type(skillLineIDs) ~= "table" then return false end
    if #skillLineIDs == 0 then return true end
    for index = 1, #skillLineIDs do
        if runtime.primaryProfessionIDs[skillLineIDs[index]] then return true end
    end
    return false
end

local function GetPlayerClassToken()
    local unitAPI = YUI.API and YUI.API.Unit
    if unitAPI and type(unitAPI.GetClassToken) == "function" then
        return unitAPI.GetClassToken("player")
    end
    return nil
end

local function IsAllowedForClass(entry, playerClass)
    return not entry.class or entry.class == playerClass
end

-- 只在地图/专业刷新时生成个性化文字，缩放时直接复用。
local function PreparePointLabel(entry, playerClass)
    entry.resolvedLabel = nil
    entry.resolvedTooltipTitle = nil
    entry.resolvedColor = nil
    if entry.trainerClasses then
        local matches = false
        for index = 1, #entry.trainerClasses do
            if entry.trainerClasses[index] == playerClass then matches = true; break end
        end
        if not matches then return false end
        entry.resolvedLabel = T("trainer.short." .. playerClass, playerClass)
        entry.resolvedTooltipTitle = T("category.trainer", "Class Trainers") .. " · " .. entry.resolvedLabel
        local unitAPI = YUI.API and YUI.API.Unit
        entry.resolvedColor = unitAPI and unitAPI.GetClassColor and unitAPI.GetClassColor(playerClass) or nil

    end
    return true
end

function MapEnhancement:IsCompactZoom()
    return YUI.IsRetail and runtime.compactZoom == true
end

function MapEnhancement:UpdateZoomMode(map)
    if not YUI.IsRetail then return false end
    local mapID = map:GetMapID()
    local rule = self.Data.zoomRules[mapID]
    local zoom = map.HasZoomLevels and map:HasZoomLevels() and map.GetCanvasZoomPercent
        and map:GetCanvasZoomPercent()
    local compact = false
    if rule and type(zoom) == "number" then
        if runtime.zoomMapID ~= mapID then
            compact = zoom < (rule.compactEnter + rule.detailEnter) * 0.5
        elseif runtime.compactZoom then
            compact = zoom < rule.detailEnter
        else
            compact = zoom <= rule.compactEnter
        end
    end
    local changed = compact ~= runtime.compactZoom
    runtime.zoomMapID, runtime.compactZoom = mapID, compact
    if changed then runtime.stats.zoomModeChanges = runtime.stats.zoomModeChanges + 1 end
    return changed
end

local function ClearPins(provider)
    if MapEnhancement.expandedPin then MapEnhancement.expandedPin:CloseExpansion(true) end
    if provider.displayPins then
        local map = provider:GetMap()
        if map and type(map.RemoveAllPinsByTemplate) == "function" then
            map:RemoveAllPinsByTemplate(PIN_TEMPLATE)
        end
    end
    provider.displayPins = nil
    runtime.stats.activePins = 0
end

function ProviderMixin:RemoveAllData()
    ClearPins(self)
    self.refreshedMapID, self.visiblePoints = nil, nil
    self.membership, self.signature, self.lastScale = nil, nil, nil
    self.stitchAPI, self.stitchedRegions, self.stitchedViewReady, self.stitchedFlights = nil, nil, nil, nil
end

local function DeferCombatRefresh(provider, mapID, hideMarkers)
    local security = YUI.API and YUI.API.Security
    local check = security and security.InCombatLockdown or InCombatLockdown
    if type(check) ~= "function" or check() ~= true then return false end
    -- Acquiring native map pins changes protected mouse passthrough attributes.
    -- Same-map pins can stay visible while a rebuild waits for combat to end.
    runtime.pendingCombatRefresh = true
    if provider.refreshedMapID and (provider.refreshedMapID ~= mapID or hideMarkers) then
        provider:RemoveAllData()
    end
    return true
end

function ProviderMixin:RenderPoints(projectedScale, projectedZoomPercent)
    local map = self:GetMap()
    if DeferCombatRefresh(self, map:GetMapID()) then return end
    if MapEnhancement.expandedPin then MapEnhancement.expandedPin:CloseExpansion() end
    if YUI.IsRetail then
        MapEnhancement:UpdateZoomMode(map)
        ClearPins(self)
        self.displayPins = {}
        for _, entry in ipairs(MapEnhancement:PrepareRetailTextEntries(self.visiblePoints or {}, map:GetMapID())) do
            entry.mapID, entry.dataProvider = map:GetMapID(), self
            self.displayPins[#self.displayPins + 1] = map:AcquirePin(PIN_TEMPLATE, entry)
        end
        runtime.stats.activePins = #self.displayPins
        return
    end
    local canvas = map.GetCanvas and map:GetCanvas()
    local scale = projectedScale or (map.GetCanvasScale and map:GetCanvasScale()) or 1
    local width = canvas and canvas.GetWidth and canvas:GetWidth() or 1000
    local height = canvas and canvas.GetHeight and canvas:GetHeight() or 668
    local groups,membership
    if MapEnhancement:GetConfig().displayMode == "icon" then
        local iconScale=MapEnhancement:GetIconLayoutScale(map, projectedZoomPercent)
        groups,membership=MapEnhancement:PrepareVisibleIconGroups(self.visiblePoints or {},width*scale/iconScale,height*scale/iconScale)
    else
        groups,membership=MapEnhancement:ClusterPoints(self.visiblePoints or {},width*scale,height*scale,self.membership)
    end
    local signature = {}
    for _, group in ipairs(groups) do
        for _, member in ipairs(group.members) do signature[#signature+1] = member.id end
        signature[#signature+1] = ";"
    end
    signature = table.concat(signature, ":")
    self.lastScale = scale
    if signature == self.signature then
        if MapEnhancement:GetConfig().displayMode == "icon" then
            for i,pin in ipairs(self.displayPins or {}) do
                pin.entry.x,pin.entry.y=groups[i].x,groups[i].y
                pin.entry.layoutX,pin.entry.layoutY=groups[i].layoutX,groups[i].layoutY
                pin:SetPosition(pin.entry.layoutX,pin.entry.layoutY)
            end
        end
        return
    end
    self.signature, self.membership = signature, membership
    MapEnhancement:HideMarkerMenu(true)
    ClearPins(self)
    self.displayPins = {}
    for _, group in ipairs(groups) do
        group.mapID, group.dataProvider = map:GetMapID(), self
        self.displayPins[#self.displayPins+1] = map:AcquirePin(PIN_TEMPLATE,group)
        runtime.stats.activePins = runtime.stats.activePins+1
    end
end

local function GetStitchedAPI()
    if not YUI.IsForever then return end
    local api = _G.OpenMapAPI
    if type(api) == "table" and api.provider == "OpenMapLiteCN"
        and type(api.IsStitched) == "function" and type(api.WorldFromMap) == "function"
        and type(api.MapFromWorld) == "function" and api.IsStitched() then
        return api
    end
end

local function GetStitchedRegions(api, hostID, records, maps)
    local regions = {}
    for id in pairs(records) do
        if maps[id] ~= false then
            local u1, v1 = api.WorldFromMap(id, 0, 0)
            local u2, v2 = api.WorldFromMap(id, 1, 1)
            if u1 and u2 then
                local left, top = api.MapFromWorld(hostID, u1, v1)
                local right, bottom = api.MapFromWorld(hostID, u2, v2)
                if left and right and left < right and top < bottom then
                    regions[#regions + 1] = { id = id, left = left, top = top, right = right, bottom = bottom }
                end
            end
        end
    end
    return regions
end

local function UpdateStitchedRegions(provider, map)
    local left, top, spanX, spanY, projectedScale, projectedZoomPercent
    local api = provider.stitchAPI
    if type(api.GetPendingViewport) == "function" then
        left, top, spanX, spanY, projectedScale, projectedZoomPercent = api.GetPendingViewport()
    end
    if left == nil then
        local canvas = map:GetCanvas()
        local scroll = map:GetCanvasContainer()
        local width, height = canvas:GetWidth(), canvas:GetHeight()
        local scale = map:GetCanvasScale()
        local viewWidth, viewHeight = scroll:GetWidth(), scroll:GetHeight()
        if width <= 0 or height <= 0 or scale <= 0 or viewWidth <= 0 or viewHeight <= 0 then return false end

        -- The cached view rect can still describe the preceding zoom.
        left, top = scroll:GetHorizontalScroll() / width, scroll:GetVerticalScroll() / height
        spanX, spanY = viewWidth / (width * scale), viewHeight / (height * scale)
    end
    if not (spanX > 0 and spanY > 0 and math.abs(left) < math.huge and math.abs(top) < math.huge) then return false end
    local changed = not provider.stitchedViewReady
    provider.stitchedViewReady = true
    for _, region in ipairs(provider.stitchedRegions) do
        -- Preload near the edge like other map icons. Keep service markers out of the distant overview.
        local margin = region.shown and 0.30 or 0.25
        local minSize = region.shown and 0.20 or 0.25
        local shown = (region.right - region.left >= spanX * minSize or region.bottom - region.top >= spanY * minSize)
            and region.right >= left - spanX * margin and region.left <= left + spanX * (1 + margin)
            and region.bottom >= top - spanY * margin and region.top <= top + spanY * (1 + margin)
        if shown ~= (region.shown == true) then
            region.shown = shown
            if not shown then region.points = nil end
            changed = true
        end
    end
    return changed, projectedScale, projectedZoomPercent
end

local function CollectMapPoints(mapID, config, playerClass, measure, region, hostID)
    if config.maps[mapID] == false then return end
    local data = MapEnhancement.Data
    local points = data:GetMapPoints(mapID, config.showOpposingFactionNPCs == true)
    if not points then return end
    local visible = {}
    local taxi = {}
    if C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
        local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
        if ok and type(nodes) == "table" then
            for _, node in ipairs(nodes) do taxi[node.nodeID] = node end
        end
    end
    for _, source in ipairs(points) do
        if data:IsValidPoint(source) and IsAllowedForClass(source, playerClass)
            and IsAllowedForProfession(source, config) and config.serviceFilters[source.typeID] ~= false then
            local point = source
            point.mapID = mapID
            if PreparePointLabel(point, playerClass) then
                point.displayMode = not YUI.IsRetail and point.taxiNodeID and "icon" or config.displayMode
                point.displayLabel = point.resolvedLabel or T(point.labelKey)
                if data:IsOpposingFaction(point.faction) then
                    point.opposingFactionLabel = T("faction." .. point.faction)
                    point.displayLabel = point.displayLabel .. " · " .. point.opposingFactionLabel
                end
                if point.taxiNodeID then
                    local node = taxi[point.taxiNodeID]
                    point.flightState = MapEnhancement:GetFlightState(point.taxiNodeID,node)
                    point.atlas = not point.opposingFactionLabel and node and node.atlasName or "TaxiNode_Neutral"
                    if point.flightState == "undiscovered" then point.atlas = "TaxiNode_Undiscovered" end
                end
                if point.displayMode == "text" then
                    if measure then measure:SetText(point.displayLabel) end
                    point.displayWidth = measure and measure:GetStringWidth()+8 or #point.displayLabel*config.fontSize/2+8
                    point.displayHeight = config.fontSize+6
                else point.displayWidth, point.displayHeight = config.iconSize+4, config.iconSize+4 end
                if region and mapID ~= hostID then
                    point.sourceX, point.sourceY = point.x, point.y
                    point.x = region.left + point.x * (region.right - region.left)
                    point.y = region.top + point.y * (region.bottom - region.top)
                end
                visible[#visible + 1] = point
            end
        end
    end
    return visible
end

function ProviderMixin:PrepareVisiblePoints(config, mapID)
    local map = self:GetMap()
    -- 跨启停复用测量对象，避免每次启用积累 FontString。
    if not runtime.measure and map.CreateFontString then
        runtime.measure = map:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        runtime.measure:Hide()
    end
    local measure = runtime.measure
    if measure then
        local font = GameFontNormalSmall and GameFontNormalSmall:GetFont() or STANDARD_TEXT_FONT
        measure:SetFont(font, config.fontSize, config.fontOutline)
    end
    local playerClass = GetPlayerClassToken()
    local points
    if self.stitchedViewReady then
        points = {}
        local flights = self.stitchedFlights or {}
        for nodeID in pairs(flights) do flights[nodeID] = nil end
        for _, region in ipairs(self.stitchedRegions) do
            if region.shown then
                region.points = region.points or CollectMapPoints(region.id, config, playerClass, measure, region, mapID) or {}
                for _, point in ipairs(region.points) do
                    points[#points + 1] = point
                    if point.taxiNodeID then flights[point.taxiNodeID] = true end
                end
            end
        end
        self.stitchedFlights = flights
    else
        points = CollectMapPoints(mapID, config, playerClass, measure)
    end
    self.visiblePoints = points
    if points then table.sort(points, function(a, b) return a.id < b.id end) end
end

function ProviderMixin:RefreshMarkers()
    local map = self:GetMap()
    if not (runtime.enabled and map and map:IsShown()) then return end
    local mapID = map:GetMapID()
    if not mapID then return end
    local data, config = MapEnhancement.Data, MapEnhancement:GetConfig()
    local api = GetStitchedAPI()
    if DeferCombatRefresh(self, mapID, config.markersHidden or (not api and config.maps[mapID] == false)) then return end
    runtime.pendingCombatRefresh = false
    MapEnhancement:HideMarkerMenu(true)
    self:RemoveAllData()
    self.stitchAPI = api
    if YUI.IsForever and data then
        data:LoadPlayerFactionPoints()
        if config.showOpposingFactionNPCs then data:LoadOpposingFactionPoints() end
    end
    runtime.stats.refreshes = runtime.stats.refreshes + 1
    if not config.markersHidden and data then
        local projectedScale, projectedZoomPercent
        if api then
            self.stitchedRegions = GetStitchedRegions(api, mapID, data.records or {}, config.maps)
            local _, scale, zoom = UpdateStitchedRegions(self, map)
            projectedScale, projectedZoomPercent = scale, zoom
        end
        self:PrepareVisiblePoints(config, mapID)
        if self.visiblePoints then self:RenderPoints(projectedScale, projectedZoomPercent) end
    end
    if not runtime.pendingCombatRefresh then self.refreshedMapID = mapID end
    SyncNativeFlights(true)
    SyncNativeFlights(false)
end

function ProviderMixin:RefreshAllData()
    -- 原生开图会接连调用地图变更、全量刷新和 OnShow。
    local map = self:GetMap()
    if map and self.refreshedMapID ~= map:GetMapID() then self:RefreshMarkers() end
end

function ProviderMixin:OnMapChanged() MapEnhancement:HideMarkerMenu(); self:RefreshMarkers() end
function ProviderMixin:OnShow() self:RefreshAllData() end
function ProviderMixin:OnHide()
    self:RemoveAllData()
    MapEnhancement:HideMarkerMenu()
end

function ProviderMixin:RefreshStitchedView(map)
    if not YUI.IsForever or not self.refreshedMapID or self.refreshedMapID ~= map:GetMapID() then return false end
    if self.stitchAPI ~= GetStitchedAPI() then
        self:RefreshMarkers()
        return true
    end
    if not self.stitchedRegions then return false end
    local changed, projectedScale, projectedZoomPercent = UpdateStitchedRegions(self, map)
    if not changed then return false, projectedScale, projectedZoomPercent end
    if not DeferCombatRefresh(self, self.refreshedMapID) then
        runtime.stats.refreshes = runtime.stats.refreshes + 1
        self:PrepareVisiblePoints(MapEnhancement:GetConfig(), self.refreshedMapID)
        self:RenderPoints(projectedScale, projectedZoomPercent)
        SyncNativeFlights(true)
        SyncNativeFlights(false)
    end
    return true
end

function ProviderMixin:OnCanvasPanChanged()
    if YUI.IsForever then self:RefreshStitchedView(self:GetMap()) end
end

function ProviderMixin:OnCanvasScaleChanged()
    local map = self:GetMap()
    if YUI.IsRetail then
        if MapEnhancement:UpdateZoomMode(map) then
            for _, pin in ipairs(self.displayPins or {}) do
                pin:ApplyZoomLabel()
                pin:ApplyZoomVisibility()
            end
        end
        return
    end
    local refreshed, projectedScale, projectedZoomPercent = self:RefreshStitchedView(map)
    if refreshed or not self.visiblePoints or self.refreshedMapID ~= map:GetMapID() then return end
    local scale = projectedScale or (map.GetCanvasScale and map:GetCanvasScale()) or 1
    if not self.lastScale or math.abs(scale/self.lastScale-1) >= 0.06 then
        self:RenderPoints(projectedScale, projectedZoomPercent)
    end
end

function ProviderMixin:OnCanvasSizeChanged()
    if YUI.IsRetail then self:OnCanvasScaleChanged(); return end
    local map = self:GetMap()
    local refreshed, projectedScale, projectedZoomPercent = self:RefreshStitchedView(map)
    -- SetMapID 可先触发尺寸回调，等新地图的数据准备好再做聚类。
    if refreshed or not self.visiblePoints or self.refreshedMapID ~= map:GetMapID() then return end
    self.signature = nil
    self:RenderPoints(projectedScale, projectedZoomPercent)
end

local function IsAltKeyDownSafe()
    local frameAPI = YUI.API and YUI.API.Frame
    return frameAPI and type(frameAPI.IsAltKeyDown) == "function" and frameAPI.IsAltKeyDown() == true
end

function MapEnhancement:GetQuickFilterState(target)
    target = target or {}
    local config = self:GetConfig()
    target.automaticScope = GetAutomaticProfessionScope()
    target.resolvedScope = GetResolvedProfessionScope()
    target.isAutomatic = config.professionScope == "auto"
    target.markersHidden, target.displayMode = config.markersHidden, config.displayMode
    target.primaryProfessionCount = runtime.primaryProfessionCount
    return target
end

function MapEnhancement:HideMarkerMenu(destinationOnly)
    if destinationOnly and not runtime.menuHasChoices then return end
    local menu = runtime.menu
    runtime.menu = nil
    runtime.menuHasChoices = nil
    if menu and Menu and Menu.GetManager():GetOpenMenu() == menu then menu:Close() end
end

local function MenuIcon(atlas, text)
    return "|A:" .. atlas .. ":16:16|a " .. text
end

local CATEGORY_ICONS = {
    travel = "FlightMasterFerry",
    service = "Banker",
    equipment = "Repair",
    collection = "VignetteLoot",
    trainer = "Class",
    special = "Object",
}

function MapEnhancement:ShowMarkerMenu(anchor, choices)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    self:HideMarkerMenu()
    local config = self:GetConfig()
    runtime.menuHasChoices = choices ~= nil
    runtime.menu = MenuUtil.CreateContextMenu(anchor or runtime.quickFilterButton, function(_, root)
        root:CreateTitle(T(choices and "menu.destination" or "menu.title"))
        if choices then
            for _, choice in ipairs(choices) do root:CreateButton(choice.text, choice.action) end
            return
        end
        local function apply(callback)
            return function() callback(); Refresh(); return MenuResponse.Refresh end
        end
        root:CreateCheckbox(T("menu.visible"), function() return not config.markersHidden end,
            apply(function() config.markersHidden = not config.markersHidden end))
        root:CreateDivider()
        if not YUI.IsRetail then
            root:CreateTitle(T("menu.display"))
            for _, mode in ipairs({"icon", "text"}) do
                local icon = mode == "icon" and "poi-islands-table" or "LevelUp-Icon-Book"
                root:CreateRadio(MenuIcon(icon,T("mode."..mode)), function() return config.displayMode == mode end,
                    apply(function() config.displayMode = mode end))
            end
            root:CreateDivider()
        end
        local categories = root:CreateButton(MenuIcon("poi-islands-table",T("menu.locations")))
        for _, category in ipairs(CATEGORY_ORDER) do
            categories:CreateCheckbox(MenuIcon(CATEGORY_ICONS[category],T("category."..category)),
                function() return self:GetCategoryEnabled(category,config) end,
                apply(function() self:SetCategoryEnabled(category,not self:GetCategoryEnabled(category,config),config) end))
        end
        if self:IsRXPCompatibilityAvailable() then
            categories:CreateCheckbox(MenuIcon("Object",T("settings.rxp_tornado_filter")),
                function() return config.hideRxpTornadoPins ~= false end,
                apply(function()
                    config.hideRxpTornadoPins = not (config.hideRxpTornadoPins ~= false)
                    self:RefreshRXPFilter(true)
                end))
        end
        categories:CreateDivider()
        categories:CreateTitle(T("menu.services"))
        for _, typeID in ipairs({"service.bank","service.auction","service.inn","travel.flight"}) do
            local definition = self.Data.types[typeID]
            if definition then
                categories:CreateCheckbox(MenuIcon(definition.atlas,T(definition.labelKey)),
                    function() return config.serviceFilters[typeID] ~= false end,
                    apply(function()
                        if config.serviceFilters[typeID] == false then config.serviceFilters[typeID] = nil
                        else config.serviceFilters[typeID] = false end
                    end))
            end
        end
        if self:NeedsFlightSync() then categories:CreateTitle(T("flight.sync_hint")) end
        local professions = root:CreateButton(MenuIcon("Profession",T("menu.professions")))
        for _, scope in ipairs({"auto","learned","all","none"}) do
            professions:CreateRadio(T("menu.scope."..scope),function() return config.professionScope == scope end,
                apply(function() config.professionScope = scope end))
        end
        root:CreateDivider()
        for _, sizeOption in ipairs({{key="fontSize",label="settings.font_size",min=8,max=24},{key="iconSize",label="settings.icon_size",min=10,max=32}}) do
            if not YUI.IsRetail or sizeOption.key == "fontSize" then
                local option = sizeOption
                local sizes = root:CreateButton(T(option.label)..": "..config[option.key])
                sizes:AddInitializer(function(button)
                    button.fontString:SetTextToFit(T(option.label)..": "..config[option.key])
                end)
                for value=option.min,option.max do
                    local size = value
                    sizes:CreateRadio(tostring(size),function() return config[option.key] == size end,
                        apply(function() config[option.key] = size end))
                end
            end
        end
        root:CreateDivider()
        root:CreateButton(T("menu.reset"),apply(function()
            config.displayMode=DEFAULTS.displayMode; config.professionScope=DEFAULTS.professionScope
            config.markersHidden=DEFAULTS.markersHidden
            config.fontSize=DEFAULTS.fontSize; config.iconSize=DEFAULTS.iconSize
            config.serviceFilters={}; config.categories=nil
            config.hideRxpTornadoPins=DEFAULTS.hideRxpTornadoPins
            self:RefreshRXPFilter(true)
        end))
        root:CreateButton(T("menu.settings"),function() self:HideMarkerMenu(); YUI.YMap:OpenSettings("markers") end)
    end)
end

function MapEnhancement:HandleQuickFilterClick(button)
    if button=="LeftButton" and IsAltKeyDownSafe() then YUI.YMap:OpenSettings("markers"); return end
    if button == "LeftButton" then
        self:HideMarkerMenu()
        local config = self:GetConfig()
        config.markersHidden = not config.markersHidden
        Refresh()
        return
    end
    if runtime.menu and Menu and Menu.GetManager():GetOpenMenu() == runtime.menu then self:HideMarkerMenu()
    else self:ShowMarkerMenu(runtime.quickFilterButton) end
end
function MapEnhancement:ShowQuickFilterTooltip(button)
    local leftClickAction = self:GetConfig().markersHidden and "tooltip.action.show" or "tooltip.action.hide"
    YUI.GUI.Tooltip:Show(button, {
        title = T("menu.title"),
        actions = {
            {button="LeftButton",text=T(leftClickAction)},
            {button="RightButton",text=T("tooltip.action.menu")},
        },
        settings = {button="LeftButton",modifiers={"ALT"}},
    })
end

local function GetQuickFilterAnchor(map)
    local canvas = type(map.GetCanvasContainer) == "function" and map:GetCanvasContainer() or map
    if YUI.IsForever then return "TOPRIGHT", canvas, "TOPRIGHT", -8, -8 end
    local nativeFilterBanner
    local overlayFrames = map.overlayFrames
    for index = 1, #(overlayFrames or {}) do
        local frame = overlayFrames[index]
        if frame and frame.FilterCounterBanner and frame.FilterCounter then
            nativeFilterBanner = frame.FilterCounterBanner
            break
        end
    end
    return nativeFilterBanner and "RIGHT" or "TOPRIGHT", nativeFilterBanner or canvas,
        nativeFilterBanner and "LEFT" or "TOPRIGHT", nativeFilterBanner and -4 or -164,
        nativeFilterBanner and 2 or 0
end

local function GetQuickFilterPlacement(map)
    local point, relativeFrame, relativePoint, x, y = GetQuickFilterAnchor(map)
    local config = MapEnhancement:GetConfig()
    return point, relativeFrame, relativePoint, x + config.buttonOffsetX, y + config.buttonOffsetY
end

function MapEnhancement:GetBelowQuickFilterAnchor(map)
    if runtime.quickFilterButton then return "TOP", runtime.quickFilterButton, "BOTTOM", 0, -2 end
    local point, relativeFrame, relativePoint, x, y = GetQuickFilterPlacement(map)
    return point, relativeFrame, relativePoint, x, y - 34
end

local function UpdateQuickFilterPosition()
    local button, map = runtime.quickFilterButton, runtime.map
    if not button or not map then return end
    local point, relativeFrame, relativePoint, x, y = GetQuickFilterPlacement(map)
    if runtime.buttonPoint == point and runtime.buttonRelativeFrame == relativeFrame
        and runtime.buttonRelativePoint == relativePoint and runtime.buttonX == x and runtime.buttonY == y then return end
    button:ClearAllPoints()
    button:SetPoint(point, relativeFrame, relativePoint, x, y)
    runtime.buttonPoint, runtime.buttonRelativeFrame, runtime.buttonRelativePoint = point, relativeFrame, relativePoint
    runtime.buttonX, runtime.buttonY = x, y
end

UpdateQuickFilterButton = function()
    local button = runtime.quickFilterButton
    if not button then return end
    button:SetShown(runtime.enabled)
    if not runtime.enabled then return end

    UpdateQuickFilterPosition()
    local state = MapEnhancement:GetQuickFilterState({})
    local color = { 1, 1, 1 }
    if button.Icon and type(button.Icon.SetVertexColor) == "function" then
        button.Icon:SetVertexColor(color[1], color[2], color[3])
    end
    if button.Icon and type(button.Icon.SetDesaturated) == "function" then
        button.Icon:SetDesaturated(state.markersHidden == true)
    end
    if type(button.SetAlpha) == "function" then
        button:SetAlpha(state.markersHidden and 0.72 or 1)
    end
end

local function EnsureQuickFilterButton(map)
    if runtime.quickFilterButton then
        UpdateQuickFilterButton()
        return true
    end
    if not (map and type(map.AddOverlayFrame) == "function") then return false end

    local button = map:AddOverlayFrame(
        QUICK_FILTER_TEMPLATE,
        "BUTTON",
        GetQuickFilterPlacement(map)
    )
    if not button then return false end
    runtime.quickFilterButton = button
    UpdateQuickFilterButton()
    if YUI.YMap.QuestObjectives then YUI.YMap.QuestObjectives:RefreshButtonAnchor() end
    return true
end

local function OnProfessionChanged()
    RefreshPrimaryProfessions()
    Refresh()
end

local function RegisterRuntimeEvents()
    if not (Event and type(Event.On) == "function") then return end
    if type(Event.OffOwner) == "function" then Event:OffOwner(runtime.eventOwner) end
    Event:On("TAXIMAP_OPENED", function() MapEnhancement:CaptureFlightKnowledge(); Refresh() end, runtime.eventOwner)
    Event:On("TAXI_NODE_STATUS_CHANGED", function()
        MapEnhancement:ForgetFlightNegatives()
        if runtime.map and runtime.map:IsShown() then Refresh() end
    end, runtime.eventOwner)
    Event:On("SKILL_LINES_CHANGED", OnProfessionChanged, runtime.eventOwner, {
        moduleId = "product:ymap:markers",
        traceName = "MapEnhancement:professions",
    })
    Event:On("ADDON_LOADED", function(_, name)
        if name ~= RXP_ADDON then return end
        MapEnhancement:RefreshRXPFilter(false)
        if MapEnhancement.RefreshCurrentModule then MapEnhancement:RefreshCurrentModule() end
    end, runtime.eventOwner, {
        moduleId = "product:ymap:markers",
        traceName = "MapEnhancement:rxp-load",
    })
    Event:On("PLAYER_ENTERING_WORLD", function()
        MapEnhancement:RefreshRXPFilter(true)
        if MapEnhancement.RefreshCurrentModule then MapEnhancement:RefreshCurrentModule() end
    end, runtime.eventOwner, {
        moduleId = "product:ymap:markers",
        traceName = "MapEnhancement:rxp-world",
    })
    Event:On("PLAYER_REGEN_ENABLED", function()
        if not runtime.pendingCombatRefresh then return end
        runtime.pendingCombatRefresh = false
        if runtime.enabled and runtime.provider and runtime.map and runtime.map:IsShown() then
            runtime.provider:RefreshMarkers()
        end
    end, runtime.eventOwner, { moduleId = "product:ymap:markers" })
end

local function DetachMap()
    MapEnhancement:HideMarkerMenu()
    SyncNativeFlights(true)
    if runtime.provider and runtime.provider.measure then runtime.provider.measure:Hide() end
    if runtime.map and runtime.provider and type(runtime.map.RemoveDataProvider) == "function" then
        runtime.map:RemoveDataProvider(runtime.provider)
    end
    runtime.provider = nil
    runtime.map = nil
    runtime.zoomMapID = nil
    runtime.compactZoom = false
    runtime.pendingCombatRefresh = false
    runtime.stats.providerAttached = false
    runtime.stats.activePins = 0
end

local function AttachMap(map)
    if not (runtime.enabled and map and type(map.AddDataProvider) == "function") then return false end
    if runtime.map == map and runtime.provider then return true end
    DetachMap()
    if not MapEnhancement:PreparePinMixin() then return false end
    if type(MapCanvasDataProviderMixin) ~= "table" or type(CreateFromMixins) ~= "function" then return false end

    runtime.map = map
    if not nativeFlightHooked and FlightPointPinMixin and hooksecurefunc then
        hooksecurefunc(FlightPointPinMixin,"OnAcquired",HideDuplicateFlight)
        nativeFlightHooked = true
    end
    runtime.provider = CreateFromMixins(MapCanvasDataProviderMixin, ProviderMixin)
    map:AddDataProvider(runtime.provider)
    EnsureQuickFilterButton(map)
    runtime.stats.providerAttached = true
    if map.IsShown and map:IsShown() then runtime.provider:RefreshAllData() end
    return true
end

local function OnAddonLoaded(_, addonName)
    if addonName == MAP_ADDON and _G.WorldMapFrame then
        AttachMap(_G.WorldMapFrame)
        if Event and Event.OffOwner then Event:OffOwner(runtime.addonOwner) end
    end
end

local function EnsureMap()
    if _G.WorldMapFrame then return AttachMap(_G.WorldMapFrame) end
    if Event and type(Event.On) == "function" then
        Event:OffOwner(runtime.addonOwner)
        Event:On("ADDON_LOADED", OnAddonLoaded, runtime.addonOwner, {
            moduleId = "product:ymap:markers",
            traceName = "MapEnhancement:world-map-load",
        })
    end
    return false
end

Refresh = function()
    if runtime.provider then runtime.provider:RefreshMarkers() end
    UpdateQuickFilterButton()
end

local function SetEnabled(enabled)
    runtime.enabled = enabled == true
    if runtime.enabled then
        RefreshPrimaryProfessions()
        RegisterRuntimeEvents()
        EnsureMap()
        UpdateQuickFilterButton()
    else
        local rxp = GetRXPAddon()
        if rxp then
            ApplyRXPTornadoFilter(rxp, false)
            if _G.WorldMapFrame then rxp:UpdateMap(true) end
        end
        if Event and Event.OffOwner then
            Event:OffOwner(runtime.addonOwner)
            Event:OffOwner(runtime.eventOwner)
        end
        DetachMap()
        UpdateQuickFilterButton()
        if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    end
end

function MapEnhancement:Enable()
    if runtime.enabled then return end
    self:ForgetFlightNegatives() -- 启用前可能在插件未运行时学会了新航点。
    runtime.normalizedConfig = nil
    SetEnabled(true)
    self:RefreshRXPFilter(true)
end

function MapEnhancement:Disable()
    if not runtime.enabled then return end
    SetEnabled(false)
    runtime.normalizedConfig = nil
end

function MapEnhancement:GetStats(target)
    target = target or {}
    target.enabled = runtime.enabled
    target.providerAttached = runtime.stats.providerAttached
    target.activePins = runtime.stats.activePins
    target.refreshes = runtime.stats.refreshes
    target.compactZoom = runtime.compactZoom
    target.zoomModeChanges = runtime.stats.zoomModeChanges
    target.pendingCombatRefresh = runtime.pendingCombatRefresh
    target.professionScope = GetResolvedProfessionScope()
    target.professionScopeAutomatic = self:GetConfig().professionScope == "auto"
    target.markersHidden = self:GetConfig().markersHidden
    target.quickFilterButton = runtime.quickFilterButton ~= nil
    target.primaryProfessionCount = runtime.primaryProfessionCount
    return target
end

-- 开发工具可在内存中预览自主采集的坐标；不会写配置或改写 MapData.lua。
function MapEnhancement:SetPointPreviewPosition(mapID, pointID, x, y)
    mapID = tonumber(mapID)
    x = tonumber(x)
    y = tonumber(y)
    if not mapID or type(pointID) ~= "string" or not x or not y then return false end
    if x ~= x or y ~= y then return false end

    if not self.Data or not self.Data:SetPointPosition(mapID,pointID,
        math.max(0,math.min(1,x)),math.max(0,math.min(1,y))) then return false end
    Refresh()
    return true
end

function MapEnhancement:GetOptions()
    local config = MapEnhancement:GetConfig()
    local options = {
        {type="row",children={
            {type="checkbox",label=T("mode.icon"),get=function() return config.displayMode=="icon" end,
                set=function(value) config.displayMode=value and "icon" or "text" end,onChange=Refresh},
            {type="slider",label=T("settings.icon_size"),width=230,min=10,max=32,step=1,
                get=function() return config.iconSize end,set=function(value) config.iconSize=value end,onChange=Refresh},
        }},
        {
            type = "row",
            children = {
                {
                    type = "slider",
                    label = T("settings.font_size", "Label Size"),
                    width = 230,
                    min = 8,
                    max = 24,
                    step = 1,
                    get = function() return config.fontSize end,
                    set = function(value) config.fontSize = tonumber(value) or DEFAULTS.fontSize end,
                    onChange = Refresh,
                },
                {
                    type = "checkbox",
                    label = T("settings.tooltips", "Show Tooltips"),
                    width = 230,
                    get = function() return config.showTooltips ~= false end,
                    set = function(value) config.showTooltips = value == true end,
                    onChange = Refresh,
                },
                {
                    type = "checkbox",
                    label = T("settings.waypoints", "Enable Waypoints"),
                    width = 230,
                    get = function() return config.enableWaypoints ~= false end,
                    set = function(value) config.enableWaypoints = value == true end,
                    onChange = Refresh,
                },
            },
        },
        {
            type = "row",
            children = {
                {
                    type = "slider", label = T("settings.button_offset_x", "Button X Offset"),
                    width = 230, min = -500, max = 500, step = 1, default = 0,
                    get = function() return config.buttonOffsetX end,
                    set = function(value) config.buttonOffsetX = NormalizeButtonOffset(value); UpdateQuickFilterPosition() end,
                },
                {
                    type = "slider", label = T("settings.button_offset_y", "Button Y Offset"),
                    width = 230, min = -500, max = 500, step = 1, default = 0,
                    get = function() return config.buttonOffsetY end,
                    set = function(value) config.buttonOffsetY = NormalizeButtonOffset(value); UpdateQuickFilterPosition() end,
                },
            },
        },
        {
            type = "divider",
            label = T("settings.categories", "Location Categories"),
            alignLeft = true,
            width = 620,
        },
    }

    if YUI.IsForever then
        local fields = options[2].children
        fields[#fields + 1] = {
            type = "checkbox", label = T("settings.opposing_faction_npcs"),
            tooltip = T("settings.opposing_faction_npcs_tooltip"),
            get = function() return config.showOpposingFactionNPCs end,
            set = function(value) config.showOpposingFactionNPCs = value == true end,
            onChange = Refresh,
        }
    end
    if YUI.IsRetail then table.remove(options, 1) end
    for index = 1, #CATEGORY_ORDER do
        local category = CATEGORY_ORDER[index]
        local defaultColor = CopyCategoryColor(nil, GetDefaultCategoryColor(category))
        local children = {
            {
                type = "checkbox",
                label = T("category." .. category, category),
                width = 190,
                default = true,
                get = function() return MapEnhancement:GetCategoryEnabled(category, config) end,
                set = function(value) MapEnhancement:SetCategoryEnabled(category, value == true, config) end,
                onChange = Refresh,
            },
            {
                type = "color",
                field = true,
                hasAlpha = false,
                width = 48,
                default = defaultColor,
                get = function()
                    return CopyCategoryColor(MapEnhancement:GetCategoryColor(category, config), defaultColor)
                end,
                set = function(value) MapEnhancement:SetCategoryColor(category, value, config) end,
                onChange = Refresh,
            },
        }
        if category == "trainer" then children[2] = nil end
        local row = {
            type = "row",
            markerCategory = category,
            gap = 14,
            children = children,
        }
        options[#options + 1] = row
    end
    if MapEnhancement:IsRXPCompatibilityAvailable() then
        options[#options + 1] = {
            type = "row",
            markerCategory = "rxp",
            gap = 14,
            children = {
                {
                    type = "checkbox",
                    label = T("settings.rxp_tornado_filter", "RXP Tornado Filter"),
                    width = 190,
                    default = true,
                    get = function() return config.hideRxpTornadoPins ~= false end,
                    set = function(value) config.hideRxpTornadoPins = value == true end,
                    onChange = function() MapEnhancement:RefreshRXPFilter(true) end,
                    tooltip = T("settings.rxp_tornado_filter_tooltip",
                        "Hide the fixed tornado spawn pins from the RestedXP Skyborne guide."),
                },
            },
        }
    end
    options[#options + 1] = {
        type = "row",
        children = {
            {
                type = "button",
                label = T("settings.restore_default", "Restore Default"),
                width = 130,
                onClick = function()
                    MapEnhancement:ResetCategories(config)
                    MapEnhancement:RefreshRXPFilter(true)
                    Refresh()
                    if self.RefreshCurrentModule then self:RefreshCurrentModule() end
                end,
            },
        },
    }
    return options
end

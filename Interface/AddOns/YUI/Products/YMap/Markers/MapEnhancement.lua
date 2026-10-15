local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.YMap or (YUI.IsRetail == false and not YUI.IsForever) then return end

local Event = YUI.Event
local MapEnhancement = YUI.YMap.Markers or {}
YUI.YMap.Markers = MapEnhancement

local MAP_ADDON = "Blizzard_WorldMap"
local PIN_TEMPLATE = "YUIMapMarkersPinTemplate"
local QUICK_FILTER_TEMPLATE = "YUIMapMarkersQuickFilterButtonTemplate"
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
    quickFilterButton = nil,
    primaryProfessionIDs = {},
    primaryProfessionCount = 0,
    normalizedConfig = nil,
    stats = { refreshes = 0, activePins = 0, providerAttached = false, zoomModeChanges = 0 },
}

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
        if node.nodeID and not node.isMapLayerTransition and node.state == current then hasCurrent = true; break end
    end
    if not hasCurrent then return end -- 空响应或非当前航线图不构成同步证据。
    local known = GetFlightKnowledge()
    local usable, blocked = {}, {}
    for _, node in ipairs(nodes) do
        if node.nodeID and not node.isMapLayerTransition then
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
    if not runtime.enabled then return end
    local map = pin.GetMap and pin:GetMap()
    if map ~= runtime.map then return end
    local config = MapEnhancement:GetConfig()
    local mapID = map:GetMapID()
    if config.maps[mapID] == false then return end
    if info and MapEnhancement.Data:HasFlight(mapID,info.nodeID) then
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

function ProviderMixin:RemoveAllData()
    if MapEnhancement.expandedPin then MapEnhancement.expandedPin:CloseExpansion(true) end
    local map = self:GetMap()
    if map and type(map.RemoveAllPinsByTemplate) == "function" then
        map:RemoveAllPinsByTemplate(PIN_TEMPLATE)
    end
    self.displayPins = nil
    runtime.stats.activePins = 0
end

function ProviderMixin:RenderPoints()
    if MapEnhancement.expandedPin then MapEnhancement.expandedPin:CloseExpansion() end
    local map = self:GetMap()
    if YUI.IsRetail then
        MapEnhancement:UpdateZoomMode(map)
        self:RemoveAllData()
        self.displayPins = {}
        for _, entry in ipairs(MapEnhancement:PrepareRetailTextEntries(self.visiblePoints or {}, map:GetMapID())) do
            entry.mapID, entry.dataProvider = map:GetMapID(), self
            self.displayPins[#self.displayPins + 1] = map:AcquirePin(PIN_TEMPLATE, entry)
        end
        runtime.stats.activePins = #self.displayPins
        return
    end
    local canvas = map.GetCanvas and map:GetCanvas()
    local scale = map.GetCanvasScale and map:GetCanvasScale() or 1
    local width = canvas and canvas.GetWidth and canvas:GetWidth() or 1000
    local height = canvas and canvas.GetHeight and canvas:GetHeight() or 668
    local groups,membership
    if MapEnhancement:GetConfig().displayMode == "icon" then
        local iconScale=MapEnhancement:GetIconLayoutScale(map)
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
    self:RemoveAllData()
    self.displayPins = {}
    for _, group in ipairs(groups) do
        group.mapID, group.dataProvider = map:GetMapID(), self
        self.displayPins[#self.displayPins+1] = map:AcquirePin(PIN_TEMPLATE,group)
        runtime.stats.activePins = runtime.stats.activePins+1
    end
end

function ProviderMixin:RefreshAllData()
    MapEnhancement:HideMarkerMenu(true)
    self:RemoveAllData()
    self.visiblePoints, self.membership, self.signature = {}, nil, nil
    if not runtime.enabled then return end
    local map = self:GetMap()
    local mapID = map and map:GetMapID()
    local data, config = MapEnhancement.Data, MapEnhancement:GetConfig()
    local playerClass = GetPlayerClassToken()
    SyncNativeFlights(true)
    SyncNativeFlights(false)
    runtime.stats.refreshes = runtime.stats.refreshes + 1
    if config.markersHidden or not data or config.maps[mapID] == false then return end
    local points = data:GetMapPoints(mapID)
    if not points then return end
    local taxi = {}
    if C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
        local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
        if ok and type(nodes) == "table" then
            for _, node in ipairs(nodes) do taxi[node.nodeID] = node end
        end
    end
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
    for _, source in ipairs(points) do
        if data:IsValidPoint(source) and IsAllowedForClass(source, playerClass)
            and IsAllowedForProfession(source, config) and config.serviceFilters[source.typeID] ~= false then
            local point = source
            point.mapID = mapID
            if PreparePointLabel(point, playerClass) then
                point.displayMode = not YUI.IsRetail and point.taxiNodeID and "icon" or config.displayMode
                point.displayLabel = point.resolvedLabel or T(point.labelKey)
                if point.taxiNodeID then
                    local node = taxi[point.taxiNodeID]
                    point.flightState = MapEnhancement:GetFlightState(point.taxiNodeID,node)
                    point.atlas = node and node.atlasName or "TaxiNode_Neutral"
                    if point.flightState == "undiscovered" then point.atlas = "TaxiNode_Undiscovered" end
                end
                if point.displayMode == "text" then
                    if measure then measure:SetText(point.displayLabel) end
                    point.displayWidth = measure and measure:GetStringWidth()+8 or #point.displayLabel*config.fontSize/2+8
                    point.displayHeight = config.fontSize+6
                else point.displayWidth, point.displayHeight = config.iconSize+4, config.iconSize+4 end
                self.visiblePoints[#self.visiblePoints+1] = point
            end
        end
    end
    table.sort(self.visiblePoints, function(a,b) return a.id < b.id end)
    self:RenderPoints()
end

function ProviderMixin:OnMapChanged() MapEnhancement:HideMarkerMenu(); self:RefreshAllData() end
function ProviderMixin:OnShow() self:RefreshAllData() end
function ProviderMixin:OnHide()
    self:RemoveAllData()
    self.visiblePoints, self.membership, self.signature = nil, nil, nil
    MapEnhancement:HideMarkerMenu()
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
    local scale = map.GetCanvasScale and map:GetCanvasScale() or 1
    if not self.lastScale or math.abs(scale/self.lastScale-1) >= 0.06 then self:RenderPoints() end
end

function ProviderMixin:OnCanvasSizeChanged()
    if YUI.IsRetail then self:OnCanvasScaleChanged(); return end
    self.signature = nil
    self:RenderPoints()
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

local function UpdateQuickFilterPosition()
    local button, map = runtime.quickFilterButton, runtime.map
    if not button or not map then return end
    local point, relativeFrame, relativePoint, x, y = GetQuickFilterAnchor(map)
    local config = MapEnhancement:GetConfig()
    x, y = x + config.buttonOffsetX, y + config.buttonOffsetY
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

    local anchorPoint, relativeFrame, relativePoint, offsetX, offsetY = GetQuickFilterAnchor(map)
    local config = MapEnhancement:GetConfig()
    offsetX, offsetY = offsetX + config.buttonOffsetX, offsetY + config.buttonOffsetY
    local button = map:AddOverlayFrame(
        QUICK_FILTER_TEMPLATE,
        "BUTTON",
        anchorPoint,
        relativeFrame,
        relativePoint,
        offsetX,
        offsetY
    )
    if not button then return false end
    runtime.quickFilterButton = button
    UpdateQuickFilterButton()
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
    if runtime.provider and runtime.enabled and runtime.map:IsShown() then runtime.provider:RefreshAllData() end
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
    options[#options + 1] = {
        type = "row",
        children = {
            {
                type = "button",
                label = T("settings.restore_default", "Restore Default"),
                width = 130,
                onClick = function()
                    MapEnhancement:ResetCategories(config)
                    Refresh()
                    if self.RefreshCurrentModule then self:RefreshCurrentModule() end
                end,
            },
        },
    }
    return options
end

local YUI = _G.YUI
local YMap = YUI and YUI.YMap
if not (YMap and YUI.IsForever) then return end

local Feature = {}
YMap.QuestObjectives = Feature

local Event, GUI = YUI.Event, YUI.GUI2
local System, Security, Quest = YUI.API.System, YUI.API.Security, YUI.API.Quest
local FrameAPI = YUI.API.Frame
local locale = YUI.Locale:Get("YMap")
local modeNames = {
    questie = locale["world_map.quest_objectives.detailed"],
    blizzard = locale["world_map.quest_objectives.simple"],
    auto = locale["world_map.quest_objectives.auto"],
    off = locale["world_map.quest_objectives.off"],
}
local modeDescriptions = {
    questie = locale["world_map.quest_objectives.detailed_description"],
    blizzard = locale["world_map.quest_objectives.simple_description"],
    auto = locale["world_map.quest_objectives.auto_description"],
}
local modeOrder = { "questie", "blizzard", "auto" }
local resumeMode = "auto"
local modeIcons = {
    questie = { texture = "Interface\\AddOns\\Questie\\Icons\\slay.blp", size = 18 },
    blizzard = {
        texture = "Interface\\Buttons\\AdventureGuideMicrobuttonAlert.blp",
        size = 20,
        cropStart = 5 / 32,
        cropEnd = 25 / 32,
    },
}
local routeEvents = { "WAYPOINT_CHANGED", "GUIDE_CHANGED", "POLESTAR_HIDDEN", "POLESTAR_PAUSED", "GUIDE_SHOWN" }
local trackingOwner = {}
local objectiveTypes = { monster = true, object = true, item = true, event = true }
local pointsPerBatch = 24
local watched = setmetatable({}, { __mode = "k" })
local boundMaps = setmetatable({}, { __mode = "k" })
local readyCallbacks = setmetatable({}, { __mode = "k" })
local hiddenIcons, extraQuests, dirtyQuests, drawing, freePins = {}, {}, {}, {}, {}
local queuedNotes, readyNotes = {}, {}
local enabled, map, button, menu, source, route, routeHandles, routeOff, pending
local buttonMode, manualMode, manualSettings
local appliedMode, trackedID, routeID, watchedID, focusedID, usingExtra, profile
local refilter, refreshExtra, trackingEventsActive
local previousPOI, previousPOITheme, writtenPOI
local Queue, Sync, OpenMap

local function GetMode()
    local mode = YMap:GetDB().worldMap.questObjectiveMode
    return modeNames[mode] and mode or "auto"
end

local buttonTooltip = {
    title = locale["world_map.quest_objectives.title"],
    content = function(body)
        local mode = GetMode()
        local label = modeNames[mode]
        if mode == "auto" and not focusedID then
            label = locale["world_map.quest_objectives.fallback"]:format(label, modeNames.blizzard)
        end
        body:AddLine(locale["world_map.quest_objectives.current"]:format(label))
        local description = modeDescriptions[mode]
        if description then
            body:AddSpace()
            body:AddLine(description, "secondary")
        end
    end,
    actions = {
        { button = "LeftButton", text = locale["world_map.quest_objectives.cycle"] },
        { button = "RightButton", text = locale["world_map.quest_objectives.menu"] },
    },
    settings = { button = "LeftButton", modifiers = { "ALT" } },
}

local function Ordinary(icon)
    return icon and not icon:IsForbidden() and not icon:IsProtected()
end

local function UpstreamData(icon)
    local data = icon and icon.data
    if icon and icon.miniMapIcon == false and type(data) == "table" and objectiveTypes[data.Type] then
        return data
    end
end

local function RestoreIcon(icon, data)
    hiddenIcons[icon] = nil
    if icon.data == data and icon.hidden and Ordinary(icon) and not icon:ShouldBeHidden() then
        icon:FakeShow()
    end
end

local function FilterIcon(icon)
    if not appliedMode or not enabled or not map:IsShown() then return end
    local data = UpstreamData(icon)
    if not data then return end
    if InCombatLockdown() then
        refilter = true
        return
    end
    if appliedMode == "questie" or (appliedMode == "auto" and data.Id == focusedID) then
        if hiddenIcons[icon] then RestoreIcon(icon, hiddenIcons[icon]) end
        return
    end
    if icon.hidden or not Ordinary(icon) then return end
    if not watched[icon] then
        watched[icon] = true
        hooksecurefunc(icon, "FakeShow", FilterIcon)
    end
    hiddenIcons[icon] = data
    icon:FakeHide()
end

local function FilterQuest(id)
    for _, name in pairs(source.map.questIdFrames[id] or {}) do
        FilterIcon(_G[name])
    end
end

local function ShowExtraTooltip(pin)
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText(pin.questName)
    if pin.objectiveText then GameTooltip:AddLine(pin.objectiveText, 1, 1, 1, true) end
    GameTooltip:Show()
end

local function HideExtraTooltip(pin)
    if GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
end

local function GetExtraIconScale()
    return 1
end

local function UpdateExtraGlow()
    -- Supplementary icons have no glow layer.
end

local function SetExtraVertexColor(texture, r, g, b, a)
    texture.r, texture.g, texture.b, texture.a = r, g, b, a or 1
    texture.SetBaseVertexColor(texture, r, g, b, texture.a)
end

local function ExtraPin()
    local pin = table.remove(freePins)
    if pin then return pin end
    pin = GUI:CreateFrame(UIParent, { width = 16, height = 16, mouse = true })
    -- The world-map provider also visits these frames for resize and hover.
    pin.miniMapIcon = false
    pin.GlowUpdate = UpdateExtraGlow
    pin.texture = pin:CreateTexture(nil, "ARTWORK")
    pin.texture:SetAllPoints()
    pin.texture.SetBaseVertexColor = pin.texture.SetVertexColor
    pin.texture.SetVertexColor = SetExtraVertexColor
    pin:SetScript("OnEnter", ShowExtraTooltip)
    pin:SetScript("OnLeave", HideExtraTooltip)
    return pin
end

local function DropExtra(id)
    local entry = extraQuests[id]
    if not entry then return end
    extraQuests[id] = nil
    drawing[id] = nil
    for _, pin in ipairs(entry) do
        source.pins:RemoveWorldMapIcon(Feature, pin)
        HideExtraTooltip(pin)
        pin:Hide()
        pin.questName, pin.objectiveText, pin.data = nil, nil, nil
        freePins[#freePins + 1] = pin
    end
end

local function VisitSpawn(entry)
    entry.visited = entry.visited + 1
    if entry.visited == pointsPerBatch then
        entry.visited = 0
        coroutine.yield()
    end
end

local function AddSpawnPin(entry, seen, style, texture, area, mapID, x, y)
    if not mapID or type(x) ~= "number" or type(y) ~= "number" or x < 0 or x > 100 or y < 0 or y > 100
        or (profile.hideUnexploredMapIcons and not source.map.utils.IsExplored(mapID, x, y)) then return false end
    local positions = seen[mapID] or {}
    seen[mapID] = positions
    local key = x .. "/" .. y
    if positions[key] then return false end
    positions[key] = true

    local pin = ExtraPin()
    local tooltip = style.ManualTooltipData
    pin.questName, pin.objectiveText = tooltip.Title, tooltip.Body[1]
    pin.AreaID, pin.UiMapID, pin.x, pin.y = area, mapID, x, y
    pin.data = style
    pin.texture:SetTexture(texture)
    local color = profile.questObjectiveColors and entry.quest.Color
    if color then pin.texture:SetVertexColor(color[1], color[2], color[3])
    else pin.texture:SetVertexColor(1, 1, 1) end
    local size = 16 * (profile.globalScale or 0.7)
    pin:SetSize(size, size)
    entry[#entry + 1] = pin
    source.pins:AddWorldMapIconMap(Feature, pin, mapID, x / 100, y / 100, _G.HBD_PINS_WORLDMAP_SHOW_WORLD)
    source.map.utils.SetDrawOrder(pin)
    return true
end

local function AddSpawns(entry, quest, objective, spawns)
    local seen = {}
    local questName = quest.name
    if type(questName) ~= "string" or questName == "" then questName = "#" .. quest.Id end
    local tooltip = { Title = questName, Body = { objective.Description }, disableShiftToRemove = true }
    local limit = profile.enableIconLimit and tonumber(profile.iconLimit) or 1500
    limit = math.min(limit or 1500, 1500)
    local count = 0
    for _, spawn in pairs(spawns) do
        local texture = source.addon.usedIcons[spawn.Icon]
        if texture then
            local style = {
                Id = quest.Id,
                Icon = spawn.Icon,
                Type = objective.Type,
                GetIconScale = GetExtraIconScale,
                ManualTooltipData = tooltip,
            }
            for area, points in pairs(spawn.Spawns) do
                local mapID = source.zones:GetUiMapIdByAreaId(area)
                local entrances
                for _, point in ipairs(points) do
                    if count >= limit then return end
                    VisitSpawn(entry)
                    local x, y = point[1], point[2]
                    if source.phasing.IsSpawnVisible(point[3]) then
                        if x == -1 and y == -1 then
                            -- Instance-only spawns use the outer entrance coordinates.
                            if entrances == nil then
                                local getEntrances = source.zones.GetDungeonLocation
                                entrances = type(getEntrances) == "function" and getEntrances(source.zones, area) or false
                            end
                            if type(entrances) == "table" then
                                for index, entrance in ipairs(entrances) do
                                    if count >= limit then return end
                                    if index > 1 then VisitSpawn(entry) end
                                    local entranceArea = entrance[1]
                                    local entranceMap = source.zones:GetUiMapIdByAreaId(entranceArea)
                                    if AddSpawnPin(entry, seen, style, texture, entranceArea, entranceMap, entrance[2], entrance[3]) then
                                        count = count + 1
                                    end
                                end
                            end
                        elseif AddSpawnPin(entry, seen, style, texture, area, mapID, x, y) then
                            count = count + 1
                        end
                    end
                end
            end
        end
    end
end

local function WantsExtra(id)
    return usingExtra and (appliedMode == "questie" or (appliedMode == "auto" and id == focusedID))
end

local function CanDrawExtra(quest, objective)
    return not (quest.HideIcons or objective.HideIcons or objective.Completed)
        and objectiveTypes[objective.Type] and type(objective.spawnList) == "table" and next(objective.spawnList)
end

local function GetExtraQuest(id)
    if not WantsExtra(id) then return end
    local acceptance = source.active.Get(id)
    local quest = acceptance and acceptance.quest
    if quest and quest:IsComplete() ~= 1 and source.quest:ShouldShowQuestNotes(id) then return quest end
end

local function DrawExtra(id)
    DropExtra(id)
    local quest = GetExtraQuest(id)
    if not quest then return end
    local entry = { quest = quest, objectives = {}, count = 0, visited = 0 }
    extraQuests[id] = entry
    for _, objectives in pairs({ quest.Objectives, quest.SpecialObjectives }) do
        for _, objective in pairs(objectives) do
            if CanDrawExtra(quest, objective) then
                entry.objectives[objective] = objective.spawnList
                entry.count = entry.count + 1
            end
        end
    end
    if next(entry.objectives) then
        drawing[id] = coroutine.create(function()
            for objective, spawns in pairs(entry.objectives) do AddSpawns(entry, quest, objective, spawns) end
        end)
    end
end

local function ContinueDrawing()
    local id, worker = next(drawing)
    if not worker then return end
    local ok, reason = coroutine.resume(worker)
    if not ok then
        DropExtra(id)
        geterrorhandler()(reason)
    elseif coroutine.status(worker) == "dead" then
        drawing[id] = nil
    end
    if next(drawing) then Queue() end
end

local function ExtraHasChanged(id)
    local quest = GetExtraQuest(id)
    local entry = extraQuests[id]
    if not quest then return entry ~= nil end
    if not entry or entry.quest ~= quest then return true end
    local count = 0
    for i = 1, 2 do
        for _, objective in pairs(i == 1 and quest.Objectives or quest.SpecialObjectives) do
            if CanDrawExtra(quest, objective) then
                if entry.objectives[objective] ~= objective.spawnList then return true end
                count = count + 1
            end
        end
    end
    return count ~= entry.count
end

local function OnQuestUpdated(id)
    if not enabled or not appliedMode or not map:IsShown()
        or type(id) ~= "number" or Security.IsSecretValue(id) then return end
    if id ~= trackedID and id ~= routeID and id ~= watchedID and not WantsExtra(id) and not extraQuests[id] then return end
    queuedNotes[id] = true
    Queue()
end

local function OnNotesVisibilityChanged()
    if usingExtra then refreshExtra = true end
    Queue()
end

local function OnQuestVisibilityChanged()
    if not usingExtra then return end
    if focusedID then
        OnQuestUpdated(focusedID)
    else
        for id in pairs(source.active.GetAll()) do OnQuestUpdated(id) end
    end
end

local function ReconcileQueuedNotes()
    for id in pairs(readyNotes) do
        readyNotes[id] = nil
        if not dirtyQuests[id] and ExtraHasChanged(id) then dirtyQuests[id] = true end
    end
    -- The notification can precede the timers that populate the cache.
    -- Defer these IDs through the next pass even when a refresh was already pending.
    for id in pairs(queuedNotes) do
        readyNotes[id] = true
        queuedNotes[id] = nil
    end
    if next(readyNotes) then Queue() end
end

local function RefreshNativeBlobs()
    if not map or not map:IsShown() or InCombatLockdown() then return end
    for pin in map:EnumeratePinsByTemplate("QuestBlobPinTemplate") do
        if pin:IsShown() then pin:Refresh() end
    end
end

local function RestorePOI()
    local original, theme, written = previousPOI, previousPOITheme, writtenPOI
    if not written then return end
    local current = System.GetCVarSafe("questPOI")
    if current == nil then return end
    local restored = false
    if current == written then
        local currentTheme = source.addon.db.profile.iconTheme
        if currentTheme ~= theme then
            -- A native theme can adopt the value already set by the map without writing the CVar.
            if currentTheme == "blizzard" then original = "1"
            elseif currentTheme == "questie" or currentTheme == "pfquest" then original = "0" end
        end
        if written ~= original then
            if not System.SetCVarSafe("questPOI", original) then return end
            restored = true
        end
    end
    previousPOI, previousPOITheme, writtenPOI = nil, nil, nil
    if restored then RefreshNativeBlobs() end
end

local function SetPOI(wanted)
    local current = System.GetCVarSafe("questPOI")
    if current ~= "0" and current ~= "1" then return false end
    if current == wanted then return true end
    if not System.SetCVarSafe("questPOI", wanted) then return false end
    if current ~= writtenPOI then
        previousPOI = current
        previousPOITheme = source.addon.db.profile.iconTheme
    end
    writtenPOI = wanted
    RefreshNativeBlobs()
    return true
end

local function SetRoute(addon)
    if addon == route then return end
    local oldOff, oldHandles = routeOff, routeHandles
    route, routeHandles, routeOff = addon, nil, nil
    if oldOff then
        for _, handle in ipairs(oldHandles) do pcall(oldOff, handle) end
    end
    if not addon then return end
    local handles = {}
    routeHandles, routeOff = handles, addon.Off
    local function OnRouteChanged()
        if routeHandles == handles then Queue() end
    end
    for _, event in ipairs(routeEvents) do handles[#handles + 1] = addon.On(event, OnRouteChanged) end
end

local function SetTrackingEvents(value)
    if trackingEventsActive == value then return end
    trackingEventsActive = value
    if value then
        Event:On("SUPER_TRACKING_CHANGED", Queue, trackingOwner)
        Event:On("QUEST_WATCH_LIST_CHANGED", Queue, trackingOwner)
    else
        Event:OffOwner(trackingOwner)
    end
end

local function GetRoute()
    local addon = _G.Polestar
    if System.IsAddOnLoaded("Polestar") and type(addon) == "table" and type(addon.On) == "function"
        and type(addon.Off) == "function" and type(addon.Nav) == "table"
        and type(addon.Nav.GetTarget) == "function" then
        return addon
    end
end

local function GetRouteTarget(addon)
    if not addon or (type(addon.Hidden) == "function" and addon.Hidden())
        or (type(addon.Paused) == "function" and addon.Paused()) then return end
    local target = addon.Nav.GetTarget()
    if type(target) ~= "table" then return end
    local id, kind = target.quest, target.kind
    if not Security.IsSecretValue(id) and type(id) == "number" and id > 0
        and type(kind) == "string" and kind ~= "" and kind ~= "accept" and kind ~= "turnin" then return id end
end

local function IsEligibleTarget(id)
    local acceptance = id and source.active.Get(id)
    return acceptance and acceptance.quest and acceptance.quest:IsComplete() ~= 1
end

local function GetCurrentTarget()
    trackedID = Quest and Quest.GetSuperTrackedQuestID and Quest.GetSuperTrackedQuestID() or nil
    routeID, watchedID = nil, nil
    if IsEligibleTarget(trackedID) then return trackedID end

    routeID = GetRouteTarget(route)
    if IsEligibleTarget(routeID) then return routeID end

    watchedID = Quest and Quest.GetSingleWatchedQuestID and Quest.GetSingleWatchedQuestID() or nil
    if IsEligibleTarget(watchedID) then return watchedID end
end

local function IsManualMode(mode)
    return mode == "questie" or mode == "blizzard"
end

local function MatchesNativeTheme(mode, config)
    local detailed = mode == "questie"
    return config.iconTheme == mode and config.enableObjectives == detailed
        and (detailed or System.GetCVarSafe("questPOI") == "1")
end

local function ResolveMode(config)
    local settings = YMap:GetDB().worldMap
    local mode = GetMode()
    if not IsManualMode(mode) or not source.executeTheme then
        manualMode, manualSettings = nil, nil
        return mode
    end

    if manualMode ~= mode or manualSettings ~= settings then
        if mode == "blizzard" then RestorePOI() end
        if not MatchesNativeTheme(mode, config) then
            local beforeTheme
            if mode == "questie" then
                RestorePOI()
                beforeTheme = System.GetCVarSafe("questPOI")
            end
            source.executeTheme(nil, mode)
            if beforeTheme == "0" or beforeTheme == "1" then
                local afterTheme = System.GetCVarSafe("questPOI")
                if (afterTheme == "0" or afterTheme == "1") and afterTheme ~= beforeTheme then
                    -- Own the preset's change even if enabling the native layer fails afterward.
                    previousPOI, previousPOITheme, writtenPOI = beforeTheme, config.iconTheme, afterTheme
                end
            end
            if source.optionsEngine then source.optionsEngine:RefreshStates() end
        end
    elseif not MatchesNativeTheme(mode, config) then
        -- Reflect a native settings change instead of writing over it again.
        local theme = config.iconTheme
        mode = IsManualMode(theme) and MatchesNativeTheme(theme, config) and theme or "off"
        settings.questObjectiveMode = mode
    end
    manualMode, manualSettings = mode, settings
    return mode
end

local function UpdateButton(mode, focusChanged)
    if not button then return end
    if buttonMode ~= mode then
        buttonMode = mode
        local isOff = mode == "off"
        local icon = modeIcons[isOff and resumeMode or mode]
        if icon then
            local start, finish = icon.cropStart or 0, icon.cropEnd or 1
            button.Icon:SetSize(icon.size, icon.size)
            button.Icon:SetTexture(icon.texture)
            button.Icon:SetTexCoord(start, finish, start, finish)
            button.Icon:SetDesaturated(isOff)
        else
            button.AutoIcon:SetDesaturated(isOff)
        end
        button.Icon:SetShown(icon ~= nil)
        button.AutoIcon:SetShown(icon == nil)
        buttonTooltip.actions[1].text = locale[isOff and "world_map.quest_objectives.resume"
            or "world_map.quest_objectives.cycle"]
        focusChanged = true
    end
    if focusChanged then GUI.Tooltip:Refresh(button) end
end

local function StopDisplay()
    appliedMode, trackedID, routeID, watchedID, focusedID = nil, nil, nil, nil, nil
    usingExtra, profile, refilter, refreshExtra = nil, nil, nil, nil
    for icon, data in pairs(hiddenIcons) do RestoreIcon(icon, data) end
    for id in pairs(extraQuests) do DropExtra(id) end
    wipe(dirtyQuests)
    wipe(queuedNotes)
    wipe(readyNotes)
    RestorePOI()
end

Sync = function()
    if InCombatLockdown() then return end
    if not enabled or not map or not map:IsShown() or not source then
        StopDisplay()
        return
    end

    local config = source.addon.db.profile
    local mode = ResolveMode(config)
    local currentOnly = mode == "auto"
    SetRoute(currentOnly and GetRoute() or nil)
    SetTrackingEvents(currentOnly)
    if mode == "off" then
        StopDisplay()
        UpdateButton(mode)
        return
    end
    local target
    if currentOnly then
        target = GetCurrentTarget()
    else
        trackedID, routeID, watchedID = nil, nil, nil
    end
    local extra = config.enabled and config.enableMapIcons and not config.enableObjectives or false
    local changed = mode ~= appliedMode
    if (currentOnly or mode == "questie" or not source.executeTheme) and not SetPOI("1") then return end

    local oldID = focusedID
    local rebuildExtra = changed or extra ~= usingExtra or config ~= profile or refreshExtra
    refreshExtra = nil
    appliedMode, focusedID, usingExtra, profile = mode, target, extra, config
    if changed or refilter then
        refilter = nil
        for id in pairs(source.map.questIdFrames) do FilterQuest(id) end
    elseif oldID ~= target then
        if oldID then FilterQuest(oldID) end
        if target then FilterQuest(target) end
    end
    if rebuildExtra then
        for id in pairs(extraQuests) do DropExtra(id) end
        if extra and mode == "questie" then
            for id in pairs(source.active.GetAll()) do dirtyQuests[id] = true end
        elseif target then
            dirtyQuests[target] = true
        end
    elseif oldID ~= target then
        if oldID then DropExtra(oldID) end
        if target then dirtyQuests[target] = true end
    end
    ReconcileQueuedNotes()
    for id in pairs(dirtyQuests) do
        dirtyQuests[id] = nil
        DrawExtra(id)
    end
    UpdateButton(mode, oldID ~= target)
    ContinueDrawing()
end

Queue = function()
    if pending or not enabled or not map or not map:IsShown() or InCombatLockdown() then return end
    pending = C_Timer.NewTimer(0, function()
        pending = nil
        Sync()
    end)
end

local function HasMethods(owner, ...)
    if type(owner) ~= "table" then return false end
    for index = 1, select("#", ...) do
        if type(owner[select(index, ...)]) ~= "function" then return false end
    end
    return true
end

local function BindSource()
    if source then return true end
    local addon, loader = _G.Questie, _G.QuestieLoader
    local api = type(addon) == "table" and addon.API
    if type(api) ~= "table" or not System.IsAddOnLoaded("Questie") then return false end
    if not api.isReady then
        if not readyCallbacks[api] and type(api.RegisterOnReady) == "function" then
            readyCallbacks[api] = true
            api.RegisterOnReady(function()
                if enabled and map and map:IsShown() then OpenMap(map) end
            end)
        end
        return false
    end
    local modules = type(loader) == "table" and loader._modules
    if type(modules) ~= "table" or type(addon.db) ~= "table" or type(addon.db.profile) ~= "table" then return false end
    local pins = modules.HBDPins or modules["Questie's HBDPins"]
    local quest, questMap, active = modules.QuestieQuest, modules.QuestieMap, modules.ActiveQuests
    local zones, phasing = modules.ZoneDB, modules.Phasing
    local options = modules.QuestieOptionsUtils
    local optionsEngine = modules.QuestieOptionsEngine
    local pool = modules.QuestieFramePool
    if not (HasMethods(pins, "AddWorldMapIconMap", "RemoveWorldMapIcon")
        and HasMethods(quest, "ShouldShowQuestNotes")
        and type(questMap) == "table" and type(questMap.questIdFrames) == "table"
        and HasMethods(questMap.utils, "IsExplored", "SetDrawOrder")
        and HasMethods(active, "Get", "GetAll")
        and HasMethods(zones, "GetUiMapIdByAreaId") and HasMethods(phasing, "IsSpawnVisible")
        and type(addon.usedIcons) == "table") then
        return false
    end
    source = { addon = addon, pins = pins, quest = quest, map = questMap, active = active, zones = zones, phasing = phasing }
    if HasMethods(options, "ExecuteTheme") then
        source.executeTheme = options.ExecuteTheme
        hooksecurefunc(options, "ExecuteTheme", Queue)
    end
    if HasMethods(optionsEngine, "RefreshStates") then source.optionsEngine = optionsEngine end
    hooksecurefunc(pins, "AddWorldMapIconMap", function(_, owner, icon)
        if owner == addon then FilterIcon(icon) end
    end)
    if HasMethods(pool, "UnloadFrame") then
        hooksecurefunc(pool, "UnloadFrame", function(_, icon)
            if type(icon) == "table" and not icon.data then hiddenIcons[icon] = nil end
        end)
    end
    if type(api.RegisterForQuestUpdates) == "function" then api.RegisterForQuestUpdates(OnQuestUpdated) end
    -- This method only schedules timer-driven coroutines. The objective methods
    -- that run inside those coroutines can yield and must stay unhooked.
    if type(quest.UpdateObjectiveNotes) == "function" then
        hooksecurefunc(quest, "UpdateObjectiveNotes", function(_, updatedQuest)
            OnQuestUpdated(type(updatedQuest) == "table" and updatedQuest.Id or updatedQuest)
        end)
    end
    if type(quest.ToggleNotes) == "function" then hooksecurefunc(quest, "ToggleNotes", OnNotesVisibilityChanged) end
    if type(quest.ToggleQuestNotes) == "function" then hooksecurefunc(quest, "ToggleQuestNotes", OnQuestVisibilityChanged) end
    if type(quest.SmoothReset) == "function" then hooksecurefunc(quest, "SmoothReset", Queue) end
    return true
end

local function SelectMode(mode)
    YMap:GetDB().worldMap.questObjectiveMode = mode
    if IsManualMode(mode) then manualMode = nil end
    Sync()
end

local function CycleMode()
    local current = GetMode()
    if current == "off" then
        SelectMode(resumeMode)
        return
    end
    for index, mode in ipairs(modeOrder) do
        if current == mode then
            SelectMode(modeOrder[index + 1] or modeOrder[1])
            return
        end
    end
end

local function CloseButtonMenu()
    if not menu then return end
    local isOpen = Menu.GetManager():GetOpenMenu() == menu
    if isOpen then menu:Close() end
    menu = nil
    return isOpen
end

function Feature:RefreshButtonAnchor()
    if not button then return end
    button:ClearAllPoints()
    button:SetPoint(YMap.Markers:GetBelowQuickFilterAnchor(map))
end

local function EnsureButton()
    if button then
        Feature:RefreshButtonAnchor()
        return
    end
    button = map:AddOverlayFrame("YUIMapRoundOverlayButtonTemplate", "BUTTON",
        YMap.Markers:GetBelowQuickFilterAnchor(map))
    -- The automatic atlas has fixed geometry and never inherits the bitmap crop.
    local autoIcon = button:CreateTexture(nil, "ARTWORK")
    autoIcon:SetPoint("CENTER", button.Background, "CENTER")
    autoIcon:SetSize(22, 22)
    autoIcon:SetAtlas("UI-QuestPoiRecurring-QuestNumber-SuperTracked", false, nil, true)
    autoIcon:Hide()
    button.AutoIcon = autoIcon
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnEnter", function(self) GUI.Tooltip:Show(self, buttonTooltip) end)
    button:SetScript("OnLeave", function(self) GUI.Tooltip:Hide(self) end)
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "LeftButton" and FrameAPI and type(FrameAPI.IsAltKeyDown) == "function"
            and FrameAPI.IsAltKeyDown() == true then
            CloseButtonMenu()
            GUI.Tooltip:Hide(self)
            YMap:OpenSettings("worldMap")
            return
        end
        if InCombatLockdown() then return end
        if mouseButton == "LeftButton" then
            CloseButtonMenu()
            CycleMode()
            if not GameTooltip:IsOwned(self) then GUI.Tooltip:Show(self, buttonTooltip) end
            return
        end
        if CloseButtonMenu() then return end
        GUI.Tooltip:Hide(self)
        menu = MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle(buttonTooltip.title)
            for _, mode in ipairs(modeOrder) do
                local choice = mode
                root:CreateRadio(modeNames[choice], function() return GetMode() == choice end,
                    function() SelectMode(choice) end)
            end
            root:CreateDivider()
            root:CreateRadio(locale["world_map.quest_objectives.disable"],
                function() return GetMode() == "off" end, function() SelectMode("off") end)
        end)
    end)
end

OpenMap = function(frame)
    if not enabled or map ~= frame or InCombatLockdown() or not BindSource() then return end
    EnsureButton()
    Sync()
    button:Show()
end

local function CloseMap(frame)
    if map ~= frame then return end
    if pending then pending:Cancel(); pending = nil end
    CloseButtonMenu()
    if button then
        GUI.Tooltip:Hide(button)
        button:Hide()
    end
    SetRoute(nil)
    SetTrackingEvents(false)
    Sync()
end

function Feature:GetStats(target)
    target.questObjectiveMode = appliedMode
    target.questObjectiveFocus = focusedID
    target.questObjectiveRefreshPending = pending ~= nil
    target.questObjectiveDrawing = next(drawing) ~= nil
    return target
end

local function Attach()
    map = _G.WorldMapFrame
    if not map then return end
    if not boundMaps[map] then
        boundMaps[map] = true
        map:HookScript("OnShow", OpenMap)
        map:HookScript("OnHide", function(frame)
            if enabled then CloseMap(frame) end
        end)
    end
    if map:IsShown() then OpenMap(map) end
end

local function OnRegen()
    if enabled and map and map:IsShown() then OpenMap(map)
    else Sync() end
    if not enabled and not writtenPOI then Event:OffOwner(Feature) end
end

function Feature:SetEnabled(value)
    if enabled == value then
        if enabled then Queue() end
        return
    end
    enabled = value
    Event:OffOwner(self)
    if not enabled then
        CloseMap(map)
        if InCombatLockdown() or writtenPOI then
            Event:On("PLAYER_REGEN_ENABLED", OnRegen, self)
            Event:On("PLAYER_LOGOUT", RestorePOI, self)
        end
        return
    end

    Event:On("ADDON_LOADED", function(_, name)
        if name == "Questie" or name == "Blizzard_WorldMap" then Attach()
        elseif name == "Polestar" then Queue() end
    end, self)
    Event:On("PLAYER_REGEN_ENABLED", OnRegen, self)
    Event:On("PLAYER_LOGOUT", RestorePOI, self)
    Event:On("CVAR_UPDATE", function(_, cvar)
        if appliedMode and cvar == "questPOI" then Queue() end
    end, self)
    Event:On("QUEST_REMOVED", function(_, id) OnQuestUpdated(id) end, self)
    Attach()
end

local _, addonTable = ...
local YUI = _G.YUI or addonTable

if not YUI or not YUI.IsRetail then return end

local ADDON_NAME = ...
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"

local Model = YUI.WorldEventTrackerModel or {}
YUI.WorldEventTrackerModel = Model

local function ClearArray(array)
    array = type(array) == "table" and array or {}
    for index = #array, 1, -1 do array[index] = nil end
    return array
end

local function ClearMap(map)
    map = type(map) == "table" and map or {}
    for key in pairs(map) do map[key] = nil end
    return map
end

local function NewResult(reuse)
    local result = type(reuse) == "table" and reuse or {}
    result.ongoing = ClearArray(result.ongoing)
    result.today = ClearArray(result.today)
    result.later = ClearArray(result.later)
    result.summary = ClearArray(result.summary)
    result.series = ClearArray(result.series)
    result._claimedOngoing = ClearArray(result._claimedOngoing)
    result._claimedToday = ClearArray(result._claimedToday)
    result._claimedLater = ClearArray(result._claimedLater)
    result._seenKeys = ClearMap(result._seenKeys)
    result._seenPois = ClearMap(result._seenPois)
    result._seriesByKey = ClearMap(result._seriesByKey)
    result._locationCache = ClearMap(result._locationCache)
    result._mapGroupByID = ClearMap(result._mapGroupByID)
    result._mapGroupPool = type(result._mapGroupPool) == "table" and result._mapGroupPool or {}
    result._mapGroupCount = 0
    result._scheduledWork = type(result._scheduledWork) == "table" and result._scheduledWork or {}
    result._scheduledWorkCount = 0
    for index = 1, #result._scheduledWork do
        local work = result._scheduledWork[index]
        if type(work) == "table" then
            work.event = nil
            work.location = nil
            work.mapGroup = nil
            work.eventID = nil
            work.active = nil
        end
    end
    result.total = 0
    result.ongoingCount = 0
    result.filteredSummaryCount = 0
    result.nextBoundary = nil
    return result
end

local function CopyEvent(event, location, ongoing)
    return {
        event = event,
        location = location,
        ongoing = ongoing == true,
        rewardsClaimed = event.rewardsClaimed,
        source = event.source,
        areaPoiID = event.areaPoiID,
        questID = event.questID,
        eventKey = event.eventKey,
        eventID = event.eventID,
        startTime = event.startTime,
        endTime = event.endTime,
        displayInfo = event.displayInfo or {},
    }
end

local function TrimWhitespace(value)
    if type(value) ~= "string" then return nil end
    return value:match("^%s*(.-)%s*$")
end

local function SplitSeriesName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local separatorStart = name:find(":", 1, true)
    local separatorLength = 1
    local fullWidthStart = name:find("：", 1, true)
    if fullWidthStart and (not separatorStart or fullWidthStart < separatorStart) then
        separatorStart = fullWidthStart
        separatorLength = #"："
    end
    if not separatorStart then return nil end

    local label = TrimWhitespace(name:sub(1, separatorStart - 1))
    local suffix = TrimWhitespace(name:sub(separatorStart + separatorLength))
    if not label or label == "" or not suffix or suffix == "" then return nil end

    return label, suffix
end

function Model.SplitSeriesName(name)
    return SplitSeriesName(name)
end

local function GetNameSeries(name, locale)
    local label, suffix = SplitSeriesName(name)
    if not label then return nil end

    locale = type(locale) == "string" and locale ~= "" and locale or "enUS"
    local identity = label:gsub("%s+", " "):lower()
    return "name:" .. locale .. ":" .. identity, label, suffix
end

function Model.GetNameSeries(name, locale)
    return GetNameSeries(name, locale)
end

local function GetSeriesKey(item, locale)
    if item.source == "worldBoss" then return "world-boss" end
    local location = item.location or {}
    local nameKey, nameLabel = GetNameSeries(location.name, locale)
    if nameKey then return nameKey, nameLabel end
    if type(item.eventID) == "number" and item.eventID >= 1 then
        return "event:" .. math.floor(item.eventID)
    end
    local atlas = item.displayInfo and item.displayInfo.overrideAtlas or location.atlasName
    if type(atlas) == "string" and atlas ~= "" then return "atlas:" .. atlas end
    if type(item.areaPoiID) == "number" then return "poi:" .. math.floor(item.areaPoiID) end
    return "unknown"
end

local function RegisterSeries(result, item, locale)
    local key, nameLabel = GetSeriesKey(item, locale)
    item.seriesKey = key
    local existing = result._seriesByKey[key]
    local location = item.location or {}
    local label = nameLabel or location.name
    if existing then
        if (type(existing.label) ~= "string" or existing.label == "") and type(label) == "string" then
            existing.label = label
        end
        return
    end
    local series = { key = key, label = label, source = item.source }
    result.series[#result.series + 1] = series
    result._seriesByKey[key] = series
end

local function AppendPartitioned(normal, claimed, item)
    if item.rewardsClaimed == true then
        claimed[#claimed + 1] = item
    else
        normal[#normal + 1] = item
    end
end

local function AppendClaimed(normal, claimed)
    for index = 1, #claimed do
        normal[#normal + 1] = claimed[index]
    end
end

local function RepartitionClaimed(normal, claimed)
    local writeIndex = 0
    local originalCount = #normal
    for index = 1, originalCount do
        local item = normal[index]
        if item.rewardsClaimed == true then
            claimed[#claimed + 1] = item
        else
            writeIndex = writeIndex + 1
            normal[writeIndex] = item
        end
    end
    for index = writeIndex + 1, originalCount do normal[index] = nil end
end

local function FilterClaimed(array)
    local writeIndex = 0
    local originalCount = #array
    for index = 1, originalCount do
        local item = array[index]
        if item.rewardsClaimed ~= true then
            writeIndex = writeIndex + 1
            array[writeIndex] = item
        end
    end
    for index = writeIndex + 1, originalCount do array[index] = nil end
end

local function SameLocalDay(timestamp, now, dateFunction)
    if type(timestamp) ~= "number" or type(now) ~= "number" then return false end
    dateFunction = type(dateFunction) == "function" and dateFunction or date
    local okNow, nowDate = pcall(dateFunction, "*t", now)
    local okEvent, eventDate = pcall(dateFunction, "*t", timestamp)
    if not okNow or not okEvent or type(nowDate) ~= "table" or type(eventDate) ~= "table" then
        return false
    end
    return nowDate.year == eventDate.year and nowDate.yday == eventDate.yday
end

local function TrackBoundary(result, timestamp, now)
    if type(timestamp) ~= "number" or timestamp <= now then return end
    if not result.nextBoundary or timestamp < result.nextBoundary then
        result.nextBoundary = timestamp
    end
end

local function ResolveLocation(resolver, areaPoiID)
    if type(resolver) ~= "function" then return nil end
    local ok, location = pcall(resolver, areaPoiID)
    if ok and type(location) == "table" then return location end
    return nil
end

local function ResolveLocationCached(result, resolver, areaPoiID)
    local cached = result._locationCache[areaPoiID]
    if cached ~= nil then return cached ~= false and cached or nil end
    local location = ResolveLocation(resolver, areaPoiID)
    result._locationCache[areaPoiID] = location or false
    return location
end

local function AcquireMapGroup(result, mapID, firstIndex)
    local group = result._mapGroupByID[mapID]
    if group then return group end

    local poolIndex = result._mapGroupCount + 1
    result._mapGroupCount = poolIndex
    group = result._mapGroupPool[poolIndex]
    if type(group) ~= "table" then
        group = {}
        result._mapGroupPool[poolIndex] = group
    end
    group.mapID = mapID
    group.firstIndex = firstIndex
    group.repeatedCount = 0
    group.poiCounts = ClearMap(group.poiCounts)
    group.repeatedPois = ClearMap(group.repeatedPois)
    result._mapGroupByID[mapID] = group
    return group
end

local function AcquireScheduledWork(result)
    local index = result._scheduledWorkCount + 1
    result._scheduledWorkCount = index
    local work = result._scheduledWork[index]
    if type(work) ~= "table" then
        work = {}
        result._scheduledWork[index] = work
    end
    return work
end

local function GetSafeMapID(location)
    if type(location) ~= "table" then return nil end
    local mapID = location.uiMapID or location.linkedUiMapID
    if type(mapID) ~= "number" or mapID < 1 or mapID ~= math.floor(mapID) then return nil end
    return mapID
end

local function FindDominantRotationGroup(result, limit)
    local dominant
    for index = 1, result._mapGroupCount do
        local group = result._mapGroupPool[index]
        local repeatedCount = 0
        for _, count in pairs(group.poiCounts) do
            if count >= 2 then repeatedCount = repeatedCount + count end
        end
        group.repeatedCount = repeatedCount
        if repeatedCount > limit and (not dominant
            or repeatedCount > dominant.repeatedCount
            or (repeatedCount == dominant.repeatedCount and group.firstIndex < dominant.firstIndex))
        then
            dominant = group
        end
    end
    return dominant
end

function Model.FormatClock(seconds, daysFormat)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local days = math.floor(seconds / 86400)
    local daySeconds = seconds % 86400
    local hours = math.floor(daySeconds / 3600)
    local minutes = math.floor((daySeconds % 3600) / 60)
    local remainingSeconds = daySeconds % 60
    if days > 0 then
        return string.format(daysFormat or "%dd %02d:%02d:%02d", days, hours, minutes, remainingSeconds)
    end
    if hours > 0 then return string.format("%02d:%02d:%02d", hours, minutes, remainingSeconds) end
    return string.format("%02d:%02d", minutes, remainingSeconds)
end

function Model.Build(snapshot, options, reuse)
    local result = NewResult(reuse)
    snapshot = type(snapshot) == "table" and snapshot or {}
    options = type(options) == "table" and options or {}

    local now = type(options.now) == "number" and options.now or (time and time() or 0)
    local showRewarded = options.showRewarded ~= false
    local summaryLimit = math.max(1, math.min(12, math.floor(tonumber(options.summaryLimit or options.summaryCount) or 3)))
    local scheduledLimit = math.max(1, math.floor(tonumber(options.scheduledLimit) or math.huge))
    local rotationLimit = math.max(1, math.floor(tonumber(options.rotationLimit) or 5))
    local imminentWindow = math.max(0, tonumber(options.imminentWindow) or 1800)
    local scheduledVisible = 0
    local locationResolver = options.locationResolver

    local ongoing = type(snapshot.ongoing) == "table" and snapshot.ongoing or {}
    for index = 1, #ongoing do
        local event = ongoing[index]
        if type(event) == "table" and event.areaPoiID then
            local item = CopyEvent(event, ResolveLocationCached(result, locationResolver, event.areaPoiID), true)
            item.group = "ongoing"
            result.ongoing[#result.ongoing + 1] = item
            if event.eventKey then result._seenKeys[event.eventKey] = item end
            result._seenPois[event.areaPoiID] = item
        end
    end

    local scheduled = type(snapshot.scheduled) == "table" and snapshot.scheduled or {}
    for index = 1, #scheduled do
        local event = scheduled[index]
        if type(event) == "table" and event.areaPoiID then
            local startTime = event.startTime
            local endTime = event.endTime
            local active = type(startTime) == "number" and type(endTime) == "number"
                and startTime <= now and now < endTime
            local expired = type(endTime) == "number" and endTime <= now

            TrackBoundary(result, startTime, now)
            TrackBoundary(result, endTime, now)
            if type(startTime) == "number" then
                TrackBoundary(result, startTime - imminentWindow, now)
            end

            if not expired then
                local location = ResolveLocationCached(result, locationResolver, event.areaPoiID)
                local work = AcquireScheduledWork(result)
                work.event = event
                work.location = location
                work.active = active
                work.mapGroup = nil

                local mapID = GetSafeMapID(location)
                if mapID then
                    local group = AcquireMapGroup(result, mapID, index)
                    group.poiCounts[event.areaPoiID] = (group.poiCounts[event.areaPoiID] or 0) + 1
                    work.mapGroup = group
                end
            end
        end
    end

    local dominantGroup = FindDominantRotationGroup(result, rotationLimit)
    local dominantVisible = 0
    if dominantGroup then
        for index = 1, result._scheduledWorkCount do
            local work = result._scheduledWork[index]
            if work.mapGroup == dominantGroup
                and dominantGroup.poiCounts[work.event.areaPoiID] >= 2
            then
                dominantGroup.repeatedPois[work.event.areaPoiID] = true
            end
        end
        for index = 1, #result.ongoing do
            if dominantGroup.repeatedPois[result.ongoing[index].areaPoiID] then
                dominantVisible = dominantVisible + 1
            end
        end
    end
    for index = 1, result._scheduledWorkCount do
        local work = result._scheduledWork[index]
        local event = work.event
        local repeatedInDominant = dominantGroup and work.mapGroup == dominantGroup
            and dominantGroup.poiCounts[work.event.areaPoiID] >= 2
        local include = true
        if repeatedInDominant then
            local mergedOngoing = work.active and (event.eventKey and result._seenKeys[event.eventKey]
                or result._seenPois[event.areaPoiID])
            if not mergedOngoing then
                if dominantVisible < rotationLimit then
                    dominantVisible = dominantVisible + 1
                else
                    include = false
                end
            end
        end

        if include then
            local startTime = event.startTime
            local endTime = event.endTime
            if work.active then
                local existing = event.eventKey and result._seenKeys[event.eventKey]
                    or result._seenPois[event.areaPoiID]
                if existing then
                    existing.group = "ongoing"
                    existing.eventKey = event.eventKey or existing.eventKey
                    existing.eventID = event.eventID or existing.eventID
                    existing.startTime = startTime or existing.startTime
                    existing.endTime = endTime or existing.endTime
                    existing.displayInfo = event.displayInfo or existing.displayInfo
                    if event.rewardsClaimed == true then existing.rewardsClaimed = true end
                    existing.scheduledEvent = event
                    if not existing.location then existing.location = work.location end
                    if event.eventKey then result._seenKeys[event.eventKey] = existing end
                else
                    local item = CopyEvent(event, work.location, true)
                    item.group = "ongoing"
                    result.ongoing[#result.ongoing + 1] = item
                    if event.eventKey then result._seenKeys[event.eventKey] = item end
                    result._seenPois[event.areaPoiID] = item
                end
            elseif scheduledVisible < scheduledLimit then
                scheduledVisible = scheduledVisible + 1
                local item = CopyEvent(event, work.location, false)
                if SameLocalDay(startTime, now, options.dateFunction) then
                    item.group = "today"
                    AppendPartitioned(result.today, result._claimedToday, item)
                else
                    item.group = "later"
                    AppendPartitioned(result.later, result._claimedLater, item)
                end
            end
        end
    end

    local worldBosses = type(options.worldBosses) == "table" and options.worldBosses or {}
    for index = 1, #worldBosses do
        local boss = worldBosses[index]
        if type(boss) == "table" and boss.questID then
            local item = CopyEvent(boss, boss.location, true)
            item.group = "ongoing"
            result.ongoing[#result.ongoing + 1] = item
            TrackBoundary(result, item.endTime, now)
        end
    end

    local groups = { result.ongoing, result.today, result.later }
    for groupIndex = 1, #groups do
        local group = groups[groupIndex]
        for index = 1, #group do RegisterSeries(result, group[index], options.seriesLocale) end
    end

    if showRewarded then
        RepartitionClaimed(result.ongoing, result._claimedOngoing)
        AppendClaimed(result.ongoing, result._claimedOngoing)
        AppendClaimed(result.today, result._claimedToday)
        AppendClaimed(result.later, result._claimedLater)
    else
        FilterClaimed(result.ongoing)
        ClearArray(result._claimedOngoing)
        ClearArray(result._claimedToday)
        ClearArray(result._claimedLater)
    end

    result.ongoingCount = #result.ongoing
    result.total = #result.ongoing + #result.today + #result.later

    local summarySeriesEnabled = type(options.summarySeriesEnabled) == "table"
        and options.summarySeriesEnabled or {}
    local function AppendSummaryItem(item)
        if #result.summary >= summaryLimit then return end
        if summarySeriesEnabled[item.seriesKey] == false then
            result.filteredSummaryCount = result.filteredSummaryCount + 1
            return
        end
        result.summary[#result.summary + 1] = item
    end

    for index = 1, #result.ongoing do
        local item = result.ongoing[index]
        if item.source == "worldBoss" then AppendSummaryItem(item) end
    end
    for groupIndex = 1, #groups do
        local group = groups[groupIndex]
        for index = 1, #group do
            if #result.summary >= summaryLimit then break end
            if group[index].source ~= "worldBoss" then AppendSummaryItem(group[index]) end
        end
        if #result.summary >= summaryLimit then break end
    end

    return result
end

Model.product = PRODUCT_ID

local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI then return end

local L = YUI.Locale and YUI.Locale:Get("MouseEnhancement") or {}
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or (_G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME] and _G.YUI_CORE_EMBED_STATE[ADDON_NAME].productId)
    or YUI.ProductId or "suite"

local PlayerTooltip = { product = PRODUCT_ID }
YUI._MouseEnhancementPlayerTooltip = PlayerTooltip

local RATING_CACHE_TTL = 5
local RATING_CACHE_MAX = 40
local MAP_CACHE_TTL = 300
local MAP_NAME_COLOR = { r = 1, g = 0.82, b = 0.1 }
local MUTED_COLOR = { r = 0.55, g = 0.55, b = 0.55 }
local GUILD_COLOR = { r = 0.25, g = 1, b = 0.25 }
local ALLIANCE_COLOR = { r = 0.25, g = 0.55, b = 1 }
local HORDE_COLOR = { r = 1, g = 0.25, b = 0.25 }

local State = {
    ratingCache = {},
    ratingCacheSize = 0,
    mapsTime = 0,
    maps = nil,
    shortNames = {},
}

local CONNECTOR_WORDS = {
    a = true,
    an = true,
    ["and"] = true,
    of = true,
    the = true,
    de = true,
    del = true,
    des = true,
    du = true,
    la = true,
    le = true,
    les = true,
    der = true,
    die = true,
    das = true,
    und = true,
    von = true,
    el = true,
    los = true,
    las = true,
}

local function T(key, fallback)
    if type(L) == "table" and L[key] then return L[key] end
    return fallback or key
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then return a, b, c, d, e, f end
    return nil
end

local function GetObjectField(object, key)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
    return nil
end

local function CallMethod(object, methodName, ...)
    local method = GetObjectField(object, methodName)
    if type(method) ~= "function" then return nil end
    return Call(method, object, ...)
end

local function IsSecretValue(value)
    local security = YUI.API and YUI.API.Security
    if security and type(security.IsSecretValue) == "function" then
        local ok, result = pcall(security.IsSecretValue, value)
        if ok then return result == true end
    end
    if type(_G.issecretvalue) == "function" then
        local ok, result = pcall(_G.issecretvalue, value)
        if ok then return result == true end
    end
    return false
end

local function ReadField(value, key)
    if type(value) ~= "table" or IsSecretValue(value) then return nil end
    local ok, result = pcall(function() return value[key] end)
    if not ok or IsSecretValue(result) then return nil end
    return result
end

local function SafeString(value)
    if IsSecretValue(value) or type(value) ~= "string" or value == "" then return nil end
    return value
end

local function SafeNumber(value)
    if value == nil or IsSecretValue(value) then return nil end
    local ok, result = pcall(tonumber, value)
    if not ok or IsSecretValue(result) then return nil end
    return result
end

local function GetClientLocale()
    local locale = YUI.Locale
    if locale and type(locale.GetClientLocale) == "function" then
        local ok, value = pcall(locale.GetClientLocale, locale)
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    if type(_G.GetLocale) == "function" then
        local ok, value = pcall(_G.GetLocale)
        if ok and type(value) == "string" and value ~= "" then return value end
    end
    return "enUS"
end

local CLIENT_LOCALE = GetClientLocale()
local IS_CHINESE_CLIENT = CLIENT_LOCALE == "zhCN" or CLIENT_LOCALE == "zhTW"
local CHINESE_SCORE_LABEL
local CHINESE_MOUNT_LABEL

local function GetTimeSafe()
    return SafeNumber(Call(_G.GetTime)) or 0
end

local function GetTooltipData(tooltip)
    local data = CallMethod(tooltip, "GetTooltipData")
    if type(data) == "table" and not IsSecretValue(data) then return data end
    return nil
end

local function ReadDataGUID(data)
    if data == nil then return nil, "missing" end
    if type(data) ~= "table" or IsSecretValue(data) then return nil, "unsafe" end

    local ok, value = pcall(function() return data.guid end)
    if not ok or IsSecretValue(value) then return nil, "unsafe" end
    if value == nil then return nil, "missing" end

    local guid = SafeString(value)
    if not guid then return nil, "unsafe" end
    return guid, "valid"
end

local function GetUnitGUIDSafe(unit)
    unit = SafeString(unit)
    if not unit then return nil end
    return SafeString(Call(_G.UnitGUID, unit))
end

local function TokenMatchesGUID(unit, guid)
    return SafeString(unit) ~= nil and SafeString(guid) ~= nil and GetUnitGUIDSafe(unit) == guid
end

local function ResolveLiteralTokenByGUID(guid)
    guid = SafeString(guid)
    if not guid then return nil end
    if TokenMatchesGUID("player", guid) then return "player" end

    if Call(_G.IsInRaid) == true then
        local count = SafeNumber(Call(_G.GetNumGroupMembers)) or 0
        for index = 1, count do
            local unit = "raid" .. index
            if TokenMatchesGUID(unit, guid) then return unit end
        end
    else
        local count = SafeNumber(Call(_G.GetNumSubgroupMembers)) or 0
        for index = 1, count do
            local unit = "party" .. index
            if TokenMatchesGUID(unit, guid) then return unit end
        end
    end

    local guidToken = SafeString(Call(_G.UnitTokenFromGUID, guid))
    if guidToken and TokenMatchesGUID(guidToken, guid) then return guidToken end
    if TokenMatchesGUID("mouseover", guid) then return "mouseover" end
    return nil
end

local function ResolveTooltipIdentity(tooltip, data)
    local callbackHasData = data ~= nil
    local sourceData = callbackHasData and data or GetTooltipData(tooltip)
    local guid, guidState = ReadDataGUID(sourceData)
    if guidState == "unsafe" or (callbackHasData and guidState ~= "valid") then return nil, nil end
    local _, tooltipUnit = CallMethod(tooltip, "GetUnit")
    tooltipUnit = SafeString(tooltipUnit)
    local tooltipGuid = GetUnitGUIDSafe(tooltipUnit)

    if not guid then guid = tooltipGuid end
    if not guid then return nil, nil end

    local unit
    if tooltipUnit and tooltipGuid == guid then
        unit = tooltipUnit
    else
        unit = ResolveLiteralTokenByGUID(guid)
    end
    if not unit or GetUnitGUIDSafe(unit) ~= guid then return nil, nil end
    local isPlayer = Call(_G.UnitIsPlayer, unit)
    if IsSecretValue(isPlayer) or isPlayer ~= true then return nil, nil end
    return guid, unit
end

local function IsForbidden(tooltip)
    return CallMethod(tooltip, "IsForbidden") == true
end

function PlayerTooltip.CanRefresh(tooltip)
    if YUI.IsRetail ~= true or tooltip ~= _G.GameTooltip then return false end
    if CallMethod(tooltip, "IsForbidden") ~= false or CallMethod(tooltip, "IsShown") ~= true then return false end
    -- Only rebuild a confirmed player tooltip out of combat; errors fail closed.
    if Call(_G.InCombatLockdown) ~= false then return false end
    local guid, unit = ResolveTooltipIdentity(tooltip)
    return guid ~= nil and unit ~= nil
end

local function StripMarkup(text)
    text = SafeString(text)
    if not text then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function GetTooltipName(tooltip)
    return SafeString(CallMethod(tooltip, "GetName"))
end

local function GetTooltipLines(tooltip)
    local name = GetTooltipName(tooltip)
    local count = SafeNumber(CallMethod(tooltip, "NumLines")) or 0
    local lines = {}
    if not name then return lines end

    for index = 1, count do
        local left = _G[name .. "TextLeft" .. index]
        local right = _G[name .. "TextRight" .. index]
        local leftText = SafeString(CallMethod(left, "GetText")) or ""
        local rightText = SafeString(CallMethod(right, "GetText")) or ""
        lines[#lines + 1] = {
            index = index,
            left = left,
            right = right,
            leftText = leftText,
            rightText = rightText,
            plainLeftText = StripMarkup(leftText),
        }
    end
    return lines
end

local function NormalizeLabel(text)
    return StripMarkup(text):gsub("[%s:：]+$", "")
end

local function GetChineseLabel(globalValue, localeKey, fallback)
    local text = SafeString(globalValue) or T(localeKey, fallback)
    text = NormalizeLabel(text)
    if text == "" then return nil end
    return text .. "："
end

local function LocalizeProviderLabels(lines)
    if not IS_CHINESE_CLIENT then return end

    if CHINESE_SCORE_LABEL == nil then
        CHINESE_SCORE_LABEL = GetChineseLabel(_G.DUNGEON_SCORE, "tooltip.mythic_score", "M+ Score:") or false
        CHINESE_MOUNT_LABEL = GetChineseLabel(_G.MOUNT, "tooltip.mount", "Mount:") or false
    end
    for _, line in ipairs(lines) do
        local plain = line.plainLeftText
        local replacement
        if plain == "M+ Score" or plain == "M+ Score:" or plain == "M+ Score：" then
            replacement = CHINESE_SCORE_LABEL ~= false and CHINESE_SCORE_LABEL or nil
        elseif plain == "Mount" or plain == "Mount:" or plain == "Mount：" then
            replacement = CHINESE_MOUNT_LABEL ~= false and CHINESE_MOUNT_LABEL or nil
        end

        local setText = replacement and GetObjectField(line.left, "SetText") or nil
        if type(setText) == "function" then
            if pcall(setText, line.left, replacement) then
                line.leftText = replacement
                line.plainLeftText = replacement
            end
        end
    end
end

local function GetLineSearchText(line)
    if line.searchText ~= nil then return line.searchRaw, line.searchText end
    local raw = tostring(line.leftText or "") .. " " .. tostring(line.rightText or "")
    line.searchRaw = raw
    line.searchText = StripMarkup(raw):lower()
    return raw, line.searchText
end

local function GetRGB(color, fallback)
    if color and type(GetObjectField(color, "GetRGB")) == "function" then
        local r, g, b = CallMethod(color, "GetRGB")
        if SafeNumber(r) and SafeNumber(g) and SafeNumber(b) then return r, g, b end
    end
    local r = color and SafeNumber(GetObjectField(color, "r"))
    local g = color and SafeNumber(GetObjectField(color, "g"))
    local b = color and SafeNumber(GetObjectField(color, "b"))
    if r and g and b then return r, g, b end
    if fallback then return GetRGB(fallback) end
    return 1, 1, 1
end

local function IsNeutralFontString(fontString)
    local r, g, b = CallMethod(fontString, "GetTextColor")
    r, g, b = SafeNumber(r), SafeNumber(g), SafeNumber(b)
    if not (r and g and b) then return false end
    return math.abs(r - g) <= 0.035 and math.abs(g - b) <= 0.035 and math.max(r, g, b) >= 0.45
end

local function SetColorIfNeutral(fontString, color)
    if not fontString or not IsNeutralFontString(fontString) then return false end
    local r, g, b = GetRGB(color)
    local method = GetObjectField(fontString, "SetTextColor")
    if type(method) ~= "function" then return false end
    return pcall(method, fontString, r, g, b) == true
end

local function GetUnitLevelLineIndex(tooltip)
    local data = GetTooltipData(tooltip)
    local dataLines = ReadField(data, "lines")
    local lineTypes = _G.Enum and _G.Enum.TooltipDataLineType
    local unitLevelType = type(lineTypes) == "table" and lineTypes.UnitLevel or nil
    if type(dataLines) ~= "table" or unitLevelType == nil or IsSecretValue(dataLines) then return nil end

    local result
    pcall(function()
        for index, lineData in ipairs(dataLines) do
            if ReadField(lineData, "type") == unitLevelType then
                result = SafeNumber(ReadField(lineData, "lineIndex")) or index
                break
            end
        end
    end)
    return result
end

local function ApplySemanticColors(tooltip, unit, lines)
    local className, classFile = Call(_G.UnitClass, unit)
    className = SafeString(className)
    classFile = SafeString(classFile)
    local classColor = classFile and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classFile] or nil
    if not classColor then return end

    if lines[1] then SetColorIfNeutral(lines[1].left, classColor) end

    local guildName = SafeString(Call(_G.GetGuildInfo, unit))
    local faction, localizedFaction = Call(_G.UnitFactionGroup, unit)
    faction = SafeString(faction)
    localizedFaction = SafeString(localizedFaction)
    local factionColor = faction == "Alliance" and ALLIANCE_COLOR or faction == "Horde" and HORDE_COLOR or nil
    local levelLineIndex = GetUnitLevelLineIndex(tooltip)
    local level = SafeNumber(Call(_G.UnitEffectiveLevel, unit)) or SafeNumber(Call(_G.UnitLevel, unit))
    local levelColor = level and Call(_G.GetCreatureDifficultyColor, level) or nil

    for _, line in ipairs(lines) do
        if line.index > 1 then
            local plain = line.plainLeftText or StripMarkup(line.leftText)
            if levelLineIndex and line.index == levelLineIndex and levelColor then
                SetColorIfNeutral(line.left, levelColor)
            elseif guildName and plain:find(guildName, 1, true) then
                SetColorIfNeutral(line.left, _G.GREEN_FONT_COLOR or GUILD_COLOR)
            elseif factionColor and ((localizedFaction and plain:find(localizedFaction, 1, true)) or plain:find(faction, 1, true)) then
                SetColorIfNeutral(line.left, factionColor)
            elseif className and plain:find(className, 1, true) then
                SetColorIfNeutral(line.left, classColor)
            end
        end
    end
end

local function FirstUTF8Characters(text, limit)
    local result = {}
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if char:match("%S") then
            result[#result + 1] = char
            if #result >= limit then break end
        end
    end
    return table.concat(result)
end

local function GetShortMapName(map)
    local mapID = map and SafeNumber(map.mapID)
    if mapID and State.shortNames[mapID] then return State.shortNames[mapID] end

    local name = map and SafeString(map.name) or ""
    local words = {}
    for word in name:gmatch("[^%s%-]+") do
        if not CONNECTOR_WORDS[word:lower()] then words[#words + 1] = word end
    end

    local short
    if #words >= 2 then
        local parts = {}
        for _, word in ipairs(words) do
            parts[#parts + 1] = FirstUTF8Characters(word:upper(), 1)
            if #parts >= 4 then break end
        end
        short = table.concat(parts)
    elseif #words == 1 and words[1]:find("[\128-\255]") then
        short = FirstUTF8Characters(words[1], 2)
    elseif #words == 1 then
        short = words[1]:upper():sub(1, 4)
    end

    if not short or short == "" then short = mapID and tostring(math.floor(mapID)) or "?" end
    if mapID then State.shortNames[mapID] = short end
    return short
end

local function GetScoreColor(score)
    local color = Call(_G.C_ChallengeMode and _G.C_ChallengeMode.GetDungeonScoreRarityColor, score)
    return color or _G.HIGHLIGHT_FONT_COLOR or MAP_NAME_COLOR
end

local function GetLevelColor(level)
    local api = YUI.API and YUI.API.Keystone
    local shared = api and Call(api.GetKeystoneLevelColor, level) or nil
    if shared then return shared end

    local quality
    if level >= 12 then
        quality = 5
    elseif level >= 9 then
        quality = 4
    elseif level >= 4 then
        quality = 3
    else
        quality = 2
    end
    return _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality] or MAP_NAME_COLOR
end

local function GetSpecificDungeonScoreColor(score)
    local api = YUI.API and YUI.API.Keystone
    local color = api and Call(api.GetSpecificDungeonScoreColor, score) or nil
    if color then return color end
    return score > 0 and (_G.HIGHLIGHT_FONT_COLOR or MAP_NAME_COLOR) or MUTED_COLOR
end

local function ColorByte(value)
    return math.floor(math.max(0, math.min(1, value or 0)) * 255 + 0.5)
end

local function ColorText(text, color)
    local r, g, b = GetRGB(color)
    return string.format("|cff%02x%02x%02x%s|r", ColorByte(r), ColorByte(g), ColorByte(b), tostring(text or ""))
end

local function GetRatingSummary(guid, unit)
    local now = GetTimeSafe()
    local cached = State.ratingCache[guid]
    if cached and now - cached.time < RATING_CACHE_TTL then
        return cached.summary ~= false and cached.summary or nil
    end
    if cached then
        State.ratingCache[guid] = nil
        State.ratingCacheSize = math.max(0, State.ratingCacheSize - 1)
    end

    local api = YUI.API and YUI.API.Keystone
    local summary = api and Call(api.GetPlayerRatingSummary, unit) or nil
    if type(summary) ~= "table" or IsSecretValue(summary) then summary = nil end

    if State.ratingCacheSize >= RATING_CACHE_MAX then
        local oldestGuid, oldestTime
        for cachedGuid, entry in pairs(State.ratingCache) do
            if oldestTime == nil or entry.time < oldestTime then
                oldestGuid, oldestTime = cachedGuid, entry.time
            end
        end
        if oldestGuid then
            State.ratingCache[oldestGuid] = nil
            State.ratingCacheSize = State.ratingCacheSize - 1
        end
    end

    State.ratingCache[guid] = { time = now, summary = summary or false }
    State.ratingCacheSize = State.ratingCacheSize + 1
    return summary
end

local function GetSeasonMaps()
    local now = GetTimeSafe()
    if type(State.maps) == "table" and now - State.mapsTime < MAP_CACHE_TTL then return State.maps end

    local api = YUI.API and YUI.API.Keystone
    local maps = api and Call(api.GetCurrentSeasonMaps) or nil
    if type(maps) ~= "table" or IsSecretValue(maps) then maps = {} end
    State.maps = maps
    State.mapsTime = now
    return maps
end

local function IsScoreLabel(text)
    local compact = StripMarkup(text):lower():gsub("%s+", "")
    return compact:find("m+score", 1, true) ~= nil
        or compact:find("mythic+score", 1, true) ~= nil
        or compact:find("mythicscore", 1, true) ~= nil
        or compact:find("大秘境评分", 1, true) ~= nil
        or compact:find("大秘境評分", 1, true) ~= nil
end

local function FindScoreLine(lines)
    for _, line in ipairs(lines) do
        if IsScoreLabel(line.leftText) then return line end
    end
    return nil
end

local function HasExistingDungeonBlock(lines, maps)
    local found = 0
    for _, map in ipairs(maps) do
        local name = SafeString(map.name)
        local short = GetShortMapName(map)
        local texture = map.texture and tostring(map.texture) or nil
        local matched = false
        for _, line in ipairs(lines) do
            local raw, plain = GetLineSearchText(line)
            if (name and plain:find(name:lower(), 1, true))
                or (short ~= "" and plain:find(short:lower(), 1, true))
                or (texture and raw:find(texture, 1, true)) then
                matched = true
                break
            end
        end
        if matched then
            found = found + 1
            if found >= 2 then return true end
        end
    end
    return false
end

local function FormatDungeonLevel(run)
    if type(run) ~= "table" or (SafeNumber(run.level) or 0) <= 0 then
        return "—", MUTED_COLOR
    end
    local level = math.floor(SafeNumber(run.level) or 0)
    local mapScore = SafeNumber(run.mapScore) or 0
    local roundedScore = mapScore > 0 and math.floor(mapScore + 0.5) or nil
    local levelText = ColorText("+" .. level, GetLevelColor(level))
    local scoreText = ColorText(roundedScore or "—", GetSpecificDungeonScoreColor(mapScore))
    local format = T("tooltip.mythic_run_format", "%s (%s)")
    local value = Call(string.format, format, levelText, scoreText)
    return value or (levelText .. " " .. scoreText), _G.HIGHLIGHT_FONT_COLOR or MAP_NAME_COLOR
end

local function AddMythicPlusInfo(tooltip, guid, unit, lines, scoreEnabled)
    local unitAPI = YUI.API and YUI.API.Unit
    local level = SafeNumber(Call(_G.UnitLevel, unit))
    local maxLevel = unitAPI and SafeNumber(Call(unitAPI.GetMaxPlayerLevel)) or nil
    if not level or not maxLevel or maxLevel <= 0 or level < maxLevel then return false end

    local summary = GetRatingSummary(guid, unit)
    if type(summary) ~= "table" then return false end

    local score = math.max(0, SafeNumber(summary.score) or 0)
    local addedScore = false
    if scoreEnabled then
        local scoreLine = FindScoreLine(lines)
        if scoreLine then
            SetColorIfNeutral(scoreLine.right, GetScoreColor(score))
        elseif type(GetObjectField(tooltip, "AddDoubleLine")) == "function" then
            if score > 0 then CallMethod(tooltip, "AddLine", " ") end
            local lr, lg, lb = GetRGB(_G.NORMAL_FONT_COLOR or MAP_NAME_COLOR)
            local rr, rg, rb = GetRGB(GetScoreColor(score))
            CallMethod(tooltip, "AddDoubleLine", T("tooltip.mythic_score", "M+ Score:"), tostring(math.floor(score)), lr, lg, lb, rr, rg, rb)
            addedScore = true
        end
    end

    if score <= 0 then return addedScore end

    local maps = GetSeasonMaps()
    if type(maps) ~= "table" or #maps == 0 or HasExistingDungeonBlock(lines, maps) then
        return addedScore
    end

    local runsByMap = {}
    local runs = ReadField(summary, "runs")
    if type(runs) == "table" and not IsSecretValue(runs) then
        pcall(function()
            for _, run in ipairs(runs) do
                local mapID = SafeNumber(ReadField(run, "mapID"))
                if mapID then runsByMap[math.floor(mapID)] = run end
            end
        end)
    end

    CallMethod(tooltip, "AddLine", " ")
    local nr, ng, nb = GetRGB(_G.NORMAL_FONT_COLOR or MAP_NAME_COLOR)
    for _, map in ipairs(maps) do
        local mapID = SafeNumber(map and map.mapID)
        local run = mapID and runsByMap[math.floor(mapID)] or nil
        local levelText, levelColor = FormatDungeonLevel(run)
        local lr, lg, lb = GetRGB(levelColor)
        CallMethod(tooltip, "AddDoubleLine", GetShortMapName(map), levelText, nr, ng, nb, lr, lg, lb)
    end
    return true
end

function PlayerTooltip.Process(tooltip, data, config, featureEnabled, mythicDisplayAllowed)
    if tooltip ~= _G.GameTooltip then return end
    if IsForbidden(tooltip) or featureEnabled ~= true or type(config) ~= "table" then
        return
    end
    if mythicDisplayAllowed == nil then mythicDisplayAllowed = featureEnabled end
    local colorEnabled = config.playerTooltipColorEnabled ~= false
    local mythicEnabled = YUI.IsRetail == true and config.playerTooltipMythicPlusEnabled ~= false
    if not colorEnabled and not mythicEnabled then
        return
    end

    local guid, unit = ResolveTooltipIdentity(tooltip, data)
    if not guid or not unit then
        return
    end

    local lines = GetTooltipLines(tooltip)
    LocalizeProviderLabels(lines)
    if colorEnabled then ApplySemanticColors(tooltip, unit, lines) end
    if mythicEnabled
        and mythicDisplayAllowed == true
    then
        AddMythicPlusInfo(tooltip, guid, unit, lines, config.playerTooltipMythicPlusScoreEnabled ~= false)
    end
end

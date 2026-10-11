local YUI = _G.YUI
if not YUI or not YUI.YMap or (not YUI.IsForever and YUI.IsRetail == false) then return end

local YMap = YUI.YMap
local GUI2 = YUI.GUI2
local Security = YUI.API and YUI.API.Security
local UnitAPI = YUI.API and YUI.API.Unit
local Event = YUI.Event

local ProgressBars = YMap.ProgressBars or {}
YMap.ProgressBars = ProgressBars

local DEFAULT_BAR_GAP = 1
local HALF_PI = math.pi * 0.5
local DEFAULT_MAP_SIZE = 175
local DEFAULT_EXPERIENCE_COLOR = { 0.58, 0, 0.55, 1 }
local DEFAULT_TRACK_COLOR = { 0, 0, 0, 1 }
local DEFAULT_BORDER_COLOR = { 0, 0, 0, 1 }

local REPUTATION_COLORS = {
    [1] = { 0.8, 0.3, 0.22, 1 },
    [2] = { 0.8, 0.3, 0.22, 1 },
    [3] = { 0.75, 0.27, 0, 1 },
    [4] = { 0.9, 0.7, 0, 1 },
    [5] = { 0.2, 1, 0.2, 1 },
    [6] = { 0, 1, 0.6, 1 },
    [7] = { 0, 1, 0.8, 1 },
    [8] = { 0, 1, 1, 1 },
}
local FRIENDSHIP_COLOR = { 0, 0.8, 0.6, 1 }
local SPECIAL_REPUTATION_COLOR = { 0, 0.6, 1, 1 }

local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local pcall = pcall
local string_format = string.format
local tonumber = tonumber
local tostring = tostring
local type = type

ProgressBars.active = ProgressBars.active == true
ProgressBars.eventSignature = nil
ProgressBars.appliedVisibility = ProgressBars.appliedVisibility or 0
ProgressBars.visibleCount = ProgressBars.visibleCount or 0
ProgressBars.valueUpdates = ProgressBars.valueUpdates or 0
ProgressBars.geometryChanges = ProgressBars.geometryChanges or 0
ProgressBars.experienceData = ProgressBars.experienceData or {}
ProgressBars.reputationData = ProgressBars.reputationData or {}
ProgressBars.geometry = ProgressBars.geometry or {
    width = DEFAULT_MAP_SIZE,
    height = DEFAULT_MAP_SIZE,
    offsetX = 0,
    offsetY = 0,
    mapSize = DEFAULT_MAP_SIZE,
    extra = 0,
}

local function T(key, fallback)
    if type(YMap.T) == "function" then
        return YMap:T(key, fallback)
    end
    return fallback or key
end

local function SetSharedStat(field, value)
    local stats = YMap.Stats
    if not stats then return end
    if stats.Set then
        stats:Set(field, value)
    elseif stats[field] ~= nil then
        stats[field] = value
    end
end

local function IncrementSharedStat(field, amount)
    local stats = YMap.Stats
    if not stats then return end
    if stats.Increment then
        stats:Increment(field, amount or 1)
    elseif type(stats[field]) == "number" then
        stats[field] = stats[field] + (amount or 1)
    end
end

local function IsSecret(value)
    if Security and type(Security.IsSecretValue) == "function" then
        return Security.IsSecretValue(value) == true
    end
    if type(_G.issecretvalue) == "function" then
        local ok, secret = pcall(_G.issecretvalue, value)
        return ok and secret == true
    end
    return false
end

local function ReadTableField(source, key)
    return source[key]
end

local function SafeField(source, key)
    if type(source) ~= "table" or IsSecret(source) then return nil end
    local ok, value = pcall(ReadTableField, source, key)
    if not ok or IsSecret(value) then return nil end
    return value
end

local function SafeNumber(value)
    if value == nil or IsSecret(value) then return nil end
    local ok, numberValue = pcall(tonumber, value)
    if not ok or numberValue == nil or IsSecret(numberValue) then return nil end
    return numberValue
end

local function SafeString(value)
    if value == nil or IsSecret(value) then return nil end
    local ok, text = pcall(tostring, value)
    if not ok or IsSecret(text) then return nil end
    return text
end

local function SafeBoolean(value)
    if value == nil or IsSecret(value) then return nil end
    return value == true
end

local function Clamp(value, minimum, maximum, fallback)
    value = SafeNumber(value)
    if value == nil then return fallback end
    return math_min(maximum, math_max(minimum, value))
end

local function CopyColor(target, source, fallback)
    target = target or {}
    source = type(source) == "table" and source or fallback
    fallback = fallback or DEFAULT_EXPERIENCE_COLOR
    target[1] = Clamp(source[1] or source.r, 0, 1, fallback[1])
    target[2] = Clamp(source[2] or source.g, 0, 1, fallback[2])
    target[3] = Clamp(source[3] or source.b, 0, 1, fallback[3])
    target[4] = Clamp(source[4] or source.a, 0, 1, fallback[4])
    return target
end

local function ResetData(data)
    data.visible = false
    data.value = 0
    data.maximum = 1
    data.percent = 0
    data.text = ""
    data.name = nil
    data.rank = nil
    data.reaction = nil
end

local function CallBoolean(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, value = pcall(func, ...)
    if not ok then return nil end
    return SafeBoolean(value)
end

local function CanShowExperienceBar()
    local gameRules = _G.GameRulesUtil
    if gameRules and type(gameRules.CanShowExperienceBar) == "function" then
        local shown = CallBoolean(gameRules.CanShowExperienceBar)
        if shown ~= nil then return shown end
    end

    local atMax = CallBoolean(_G.IsPlayerAtEffectiveMaxLevel)
    if atMax == true then return false end
    local disabled = CallBoolean(_G.IsXPUserDisabled)
    if disabled == true then return false end

    local rules = _G.C_GameRules
    local enum = _G.Enum and _G.Enum.GameRule
    if rules and type(rules.IsGameRuleActive) == "function"
        and enum and enum.ExperienceBarDisabled ~= nil then
        local ruleDisabled = CallBoolean(rules.IsGameRuleActive, enum.ExperienceBarDisabled)
        if ruleDisabled == true then return false end
    end

    if atMax == false then return true end
    local level
    if type(_G.UnitLevel) == "function" then
        local ok, value = pcall(_G.UnitLevel, "player")
        if ok then level = SafeNumber(value) end
    end
    local maximum = UnitAPI and type(UnitAPI.GetMaxPlayerLevel) == "function"
        and SafeNumber(UnitAPI.GetMaxPlayerLevel()) or nil
    return level ~= nil and maximum ~= nil and level < maximum
end

local function ReadPlayerLevel()
    if type(_G.UnitLevel) ~= "function" then return nil end
    local ok, value = pcall(_G.UnitLevel, "player")
    return ok and SafeNumber(value) or nil
end

local function UseBankedExperience(level)
    local active = CallBoolean(_G.GameLimitedMode_IsBankedXPActive)
    if active ~= true or level == nil
        or type(_G.GameLimitedMode_GetLevelLimit) ~= "function" then
        return false
    end
    local ok, value = pcall(_G.GameLimitedMode_GetLevelLimit)
    local limit = ok and SafeNumber(value) or nil
    return limit ~= nil and level >= limit
end

local function ReadExperience(data, config)
    ResetData(data)
    if not (config and config.experienceEnabled == true) or not CanShowExperienceBar() then
        return false
    end

    local level = ReadPlayerLevel()
    local currentFunc = UseBankedExperience(level) and _G.UnitTrialXP or _G.UnitXP
    if type(currentFunc) ~= "function" or type(_G.UnitXPMax) ~= "function" then
        return false
    end
    local currentOK, currentValue = pcall(currentFunc, "player")
    local maximumOK, maximumValue = pcall(_G.UnitXPMax, "player")
    local current = currentOK and SafeNumber(currentValue) or nil
    local maximum = maximumOK and SafeNumber(maximumValue) or nil
    if current == nil or maximum == nil or maximum <= 0 or level == nil then
        return false
    end

    current = math_min(math_max(current, 0), maximum)
    data.visible = true
    data.value = current
    data.maximum = maximum
    data.percent = current / maximum * 100
    data.level = level
    data.text = string_format(
        T("status_bars.experience_text", "等级 %d · %.1f%%"),
        math_floor(level + 0.5),
        data.percent
    )
    return true
end

local function ReadWatchedFactionData()
    local reputation = _G.C_Reputation
    if not reputation or type(reputation.GetWatchedFactionData) ~= "function" then
        return nil
    end
    local ok, data = pcall(reputation.GetWatchedFactionData)
    if not ok or type(data) ~= "table" or IsSecret(data) then return nil end
    return data
end

local function ReadReactionLabel(reaction)
    if reaction == nil or type(_G.GetText) ~= "function" then return "" end
    local gender = 2
    if type(_G.UnitSex) == "function" then
        local ok, value = pcall(_G.UnitSex, "player")
        local safe = ok and SafeNumber(value) or nil
        if safe ~= nil then gender = safe end
    end
    local ok, value = pcall(_G.GetText, "FACTION_STANDING_LABEL" .. tostring(reaction), gender)
    return ok and SafeString(value) or ""
end

local function ReadReputation(data, config)
    ResetData(data)
    if not (config and config.reputationEnabled == true) then return false end

    local watched = ReadWatchedFactionData()
    if not watched then return false end
    local factionID = SafeNumber(SafeField(watched, "factionID"))
    local name = SafeString(SafeField(watched, "name"))
    if not factionID or factionID <= 0 or not name or name == "" then return false end

    local reputation = _G.C_Reputation
    local reaction = SafeNumber(SafeField(watched, "reaction"))
    local current
    local maximum
    local rank = ""
    local color = REPUTATION_COLORS[reaction] or SPECIAL_REPUTATION_COLOR
    local isParagon = CallBoolean(
        reputation and reputation.IsFactionParagonForCurrentPlayer,
        factionID
    ) == true
    local isMajor = CallBoolean(reputation and reputation.IsMajorFaction, factionID) == true

    if isParagon and reputation and type(reputation.GetFactionParagonInfo) == "function" then
        local ok, value, threshold, _, rewardPending = pcall(
            reputation.GetFactionParagonInfo,
            factionID
        )
        current = ok and SafeNumber(value) or nil
        maximum = ok and SafeNumber(threshold) or nil
        if not current or not maximum or maximum <= 0 then return false end
        current = current % maximum
        if SafeBoolean(rewardPending) == true then current = maximum end
        rank = T("status_bars.rank.paragon", "巅峰")
        color = SPECIAL_REPUTATION_COLOR
    elseif isMajor and _G.C_MajorFactions
        and type(_G.C_MajorFactions.GetMajorFactionData) == "function" then
        local ok, majorData = pcall(_G.C_MajorFactions.GetMajorFactionData, factionID)
        if not ok or type(majorData) ~= "table" or IsSecret(majorData) then return false end
        maximum = SafeNumber(SafeField(majorData, "renownLevelThreshold"))
        local renownLevel = SafeNumber(SafeField(majorData, "renownLevel"))
        if not renownLevel then return false end
        if maximum == nil then
            local capped = CallBoolean(_G.C_MajorFactions.HasMaximumRenown, factionID)
            if capped ~= true then return false end
            current, maximum = 1, 1
        elseif maximum <= 0 then
            current, maximum = 1, 1
        else
            current = SafeNumber(SafeField(majorData, "renownReputationEarned"))
            if current == nil then return false end
        end
        rank = string_format(
            T("status_bars.rank.renown", "名望 %d"),
            math_floor(renownLevel + 0.5)
        )
        color = SPECIAL_REPUTATION_COLOR
    else
        local friendship
        local gossip = _G.C_GossipInfo
        if gossip and type(gossip.GetFriendshipReputation) == "function" then
            local ok, value = pcall(gossip.GetFriendshipReputation, factionID)
            if ok and type(value) == "table" and not IsSecret(value) then friendship = value end
        end
        local friendshipID = friendship and SafeNumber(SafeField(friendship, "friendshipFactionID"))
        if friendshipID and friendshipID > 0 then
            local nextThreshold = SafeNumber(SafeField(friendship, "nextThreshold"))
            local reactionThreshold = SafeNumber(SafeField(friendship, "reactionThreshold"))
            local standing = SafeNumber(SafeField(friendship, "standing"))
            rank = SafeString(SafeField(friendship, "reaction")) or ""
            if nextThreshold == nil then
                local ranks
                if type(gossip.GetFriendshipReputationRanks) == "function" then
                    local ok, value = pcall(gossip.GetFriendshipReputationRanks, factionID)
                    if ok and type(value) == "table" and not IsSecret(value) then ranks = value end
                end
                local currentLevel = ranks and SafeNumber(SafeField(ranks, "currentLevel"))
                local maxLevel = ranks and SafeNumber(SafeField(ranks, "maxLevel"))
                if not currentLevel or not maxLevel or currentLevel < maxLevel then return false end
                current, maximum = 1, 1
            elseif not reactionThreshold or not standing then
                return false
            elseif nextThreshold > reactionThreshold then
                current = standing - reactionThreshold
                maximum = nextThreshold - reactionThreshold
            else
                current = 1
                maximum = 1
            end
            color = FRIENDSHIP_COLOR
        else
            local currentStanding = SafeNumber(SafeField(watched, "currentStanding"))
            local currentThreshold = SafeNumber(SafeField(watched, "currentReactionThreshold"))
            local nextThreshold = SafeNumber(SafeField(watched, "nextReactionThreshold"))
            if reaction and reaction >= 8 and (not currentThreshold or not nextThreshold) then
                current = 1
                maximum = 1
            else
                if not currentStanding or not currentThreshold or not nextThreshold then return false end
                current = currentStanding - currentThreshold
                maximum = nextThreshold - currentThreshold
                if maximum <= 0 then
                    current = 1
                    maximum = 1
                end
            end
            rank = ReadReactionLabel(reaction)
            color = REPUTATION_COLORS[reaction] or SPECIAL_REPUTATION_COLOR
        end
    end

    if not current or not maximum or maximum <= 0 then return false end
    current = math_min(math_max(current, 0), maximum)
    data.visible = true
    data.value = current
    data.maximum = maximum
    data.percent = current / maximum * 100
    data.name = name
    data.rank = rank
    data.reaction = reaction
    data.color = CopyColor(data.color, color, SPECIAL_REPUTATION_COLOR)
    if rank ~= "" then
        data.text = string_format(
            T("status_bars.reputation_text", "%s · %s · %.1f%%"),
            name,
            rank,
            data.percent
        )
    else
        data.text = string_format(
            T("status_bars.reputation_text_no_rank", "%s · %.1f%%"),
            name,
            data.percent
        )
    end
    return true
end

local function ApplyBarVisual(visual, config, fillColor)
    if not (visual and GUI2 and GUI2.CompileStatusBarStyle and GUI2.ApplyStatusBarChrome) then
        return 0
    end
    local input = visual.styleInput
    input.textureId = config.texture
    input.fillColor = CopyColor(input.fillColor, fillColor, DEFAULT_EXPERIENCE_COLOR)
    input.trackColor = CopyColor(input.trackColor, config.backgroundColor, DEFAULT_TRACK_COLOR)
    input.borderColor = CopyColor(input.borderColor, config.borderColor, DEFAULT_BORDER_COLOR)
    visual.style = GUI2:CompileStatusBarStyle(input, visual.style)
    visual.style.borderThickness = config.borderWidth
    return GUI2:ApplyStatusBarChrome(visual.chrome, visual.style) or 0
end

local function RefreshTextVisibility(visual)
    if not (visual and visual.text and visual.host) then return end
    local visible = visual.host:IsShown()
        and (visual.textDisplay == "always" or visual.hovered == true)
    visual.text:SetShown(visible)
end

local function SetHovered(kind, hovered)
    local visual = kind == "experience" and ProgressBars.experienceBar or ProgressBars.reputationBar
    if not visual then return end
    visual.hovered = hovered == true
    RefreshTextVisibility(visual)
end

local function EnsureBar(kind, parent)
    local field = kind == "experience" and "experienceBar" or "reputationBar"
    local existing = ProgressBars[field]
    if existing then return existing end
    if not (parent and GUI2 and GUI2.CreateFrame and GUI2.CreateTexture and GUI2.CreateText) then
        return nil
    end

    local host = GUI2:CreateFrame(parent, {
        name = kind == "experience" and "YMapExperienceBar" or "YMapReputationBar",
        width = 1,
        height = 1,
        frameStrata = "MEDIUM",
        frameLevel = 55,
        mouse = true,
    })
    host:EnableMouse(true)
    local track = GUI2:CreateTexture(host, { layer = "BACKGROUND" })
    track:SetAllPoints(host)
    local statusBar = _G.CreateFrame("StatusBar", nil, host)
    statusBar:SetAllPoints(host)
    statusBar:SetFrameLevel(56)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0)
    statusBar:EnableMouse(false)
    local border = GUI2.EnsureStatusBarBorder and GUI2:EnsureStatusBarBorder(statusBar) or nil
    local textLayer = GUI2:CreateFrame(host, {
        width = 1,
        height = 1,
        frameStrata = "MEDIUM",
        frameLevel = 57,
        mouse = false,
    })
    textLayer:SetAllPoints(host)
    textLayer:EnableMouse(false)
    local text = GUI2:CreateText(textLayer, "", "font.size.sm", "color.text.primary")
    text:SetPoint("CENTER", textLayer, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetWordWrap(false)
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    text:Hide()

    local visual = {
        kind = kind,
        host = host,
        statusBar = statusBar,
        track = track,
        border = border,
        textLayer = textLayer,
        text = text,
        chrome = {
            statusBar = statusBar,
            track = track,
            border = border,
            pixelOwner = host,
        },
        styleInput = {
            fillColor = {},
            trackColor = {},
            borderColor = {},
        },
        style = {},
    }
    host:SetScript("OnEnter", function() SetHovered(kind, true) end)
    host:SetScript("OnLeave", function() SetHovered(kind, false) end)
    host.RefreshTheme = function()
        local db = YMap.GetDB and YMap:GetDB()
        local current = db and db.minimap and db.minimap.statusBars
        if not current then return end
        local data = kind == "experience" and ProgressBars.experienceData or ProgressBars.reputationData
        local color = kind == "experience" and current.experienceColor or data.color
        ApplyBarVisual(visual, current, color)
    end
    host.UpdatePixelScale = host.RefreshTheme
    host.UpdateGUI2PixelScale = host.RefreshTheme
    host:Hide()
    ProgressBars[field] = visual
    return visual
end

local function ApplyFont(visual, thickness, vertical, mapSize)
    local text = visual and visual.text
    if not text then return end
    local fontPath, _, fontFlags = text:GetFont()
    local fontSize = math_max(8, math_min(12, thickness - 2))
    if fontPath then text:SetFont(fontPath, fontSize, fontFlags or "OUTLINE") end
    text:SetSize(math_max(mapSize - 4, 1), math_max(thickness - 2, 1))
    if text.SetRotation then text:SetRotation(vertical and HALF_PI or 0) end
end

local function ApplyBarData(visual, data, config, fillColor, forceVisual)
    if not (visual and data and data.visible) then return 0 end
    local writes = 0
    visual.textDisplay = config.textDisplay == "always" and "always" or "hover"
    if visual.maximum ~= data.maximum then
        visual.statusBar:SetMinMaxValues(0, data.maximum)
        visual.maximum = data.maximum
        writes = writes + 1
    end
    if visual.value ~= data.value then
        visual.statusBar:SetValue(data.value)
        visual.value = data.value
        writes = writes + 1
    end
    if visual.currentText ~= data.text then
        visual.text:SetText(data.text)
        visual.currentText = data.text
        writes = writes + 1
    end
    local color = CopyColor(visual.lastFillColor, fillColor, DEFAULT_EXPERIENCE_COLOR)
    local previous = visual.appliedFillColor
    local colorChanged = not previous or previous[1] ~= color[1] or previous[2] ~= color[2]
        or previous[3] ~= color[3] or previous[4] ~= color[4]
    if colorChanged then
        visual.appliedFillColor = CopyColor(previous, color, DEFAULT_EXPERIENCE_COLOR)
    end
    if forceVisual or colorChanged then
        writes = writes + ApplyBarVisual(visual, config, color)
    end
    RefreshTextVisibility(visual)
    return writes
end

local function HideBar(visual)
    if not visual then return end
    visual.hovered = false
    if visual.text then visual.text:Hide() end
    visual.host:Hide()
end

local function GetVisibilityCode(experienceData, reputationData)
    local code = 0
    if experienceData.visible then code = code + 1 end
    if reputationData.visible then code = code + 2 end
    return code
end

function ProgressBars:CollectData(config)
    ReadExperience(self.experienceData, config)
    ReadReputation(self.reputationData, config)
    return GetVisibilityCode(self.experienceData, self.reputationData)
end

local function ConfigureEvents(self, config, active)
    local experience = active and config.experienceEnabled == true
    local reputation = active and config.reputationEnabled == true
    local signature = (experience and 1 or 0) + (reputation and 2 or 0)
    if self.eventSignature == signature then return end
    if Event and Event.OffOwner then Event:OffOwner(self) end
    self.eventSignature = signature
    SetSharedStat("progressBarEventsActive", signature > 0)
    if signature == 0 or not (Event and Event.On) then return end

    Event:On("PLAYER_ENTERING_WORLD", "OnProgressEvent", self)
    if experience then
        Event:On("PLAYER_XP_UPDATE", "OnProgressEvent", self)
        Event:On("PLAYER_TRIAL_XP_UPDATE", "OnProgressEvent", self, { unit = "player" })
        Event:On("PLAYER_LEVEL_UP", "OnProgressEvent", self)
        Event:On("UNIT_LEVEL", "OnProgressEvent", self, { unit = "player" })
        Event:On("ENABLE_XP_GAIN", "OnProgressEvent", self)
        Event:On("DISABLE_XP_GAIN", "OnProgressEvent", self)
        Event:On("UPDATE_EXPANSION_LEVEL", "OnProgressEvent", self)
        Event:On("PLAYER_MAX_LEVEL_UPDATE", "OnProgressEvent", self)
    end
    if reputation then
        Event:On("UPDATE_FACTION", "OnProgressEvent", self)
        Event:On("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "OnProgressEvent", self)
    end
end

local function ConfigureBarLayout(visual, anchor, point, relativePoint, x, y, width, height, vertical)
    visual.host:ClearAllPoints()
    visual.host:SetPoint(point, anchor, relativePoint, x, y)
    visual.host:SetSize(width, height)
    visual.statusBar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    ApplyFont(visual, vertical and width or height, vertical, vertical and height or width)
end

local function PositionVisibleBars(self, parent, anchor, config, mapSize)
    local thickness = config.thickness
    local gap = config.mapGap
    local barGap = Clamp(config.barGap, 0, 16, DEFAULT_BAR_GAP)
    local position = config.position
    local vertical = position == "left" or position == "right"
    local first
    local second
    if self.experienceData.visible then first = self.experienceBar end
    if self.reputationData.visible then
        if first then second = self.reputationBar else first = self.reputationBar end
    end

    if first then
        if position == "bottom" then
            ConfigureBarLayout(first, anchor, "TOPLEFT", "BOTTOMLEFT", 0, -gap, mapSize, thickness, false)
            if second then
                ConfigureBarLayout(second, first.host, "TOPLEFT", "BOTTOMLEFT", 0, -barGap, mapSize, thickness, false)
            end
        elseif position == "top" then
            ConfigureBarLayout(first, anchor, "BOTTOMLEFT", "TOPLEFT", 0, gap, mapSize, thickness, false)
            if second then
                ConfigureBarLayout(second, first.host, "BOTTOMLEFT", "TOPLEFT", 0, barGap, mapSize, thickness, false)
            end
        elseif position == "left" then
            ConfigureBarLayout(first, anchor, "TOPRIGHT", "TOPLEFT", -gap, 0, thickness, mapSize, true)
            if second then
                ConfigureBarLayout(second, first.host, "TOPRIGHT", "TOPLEFT", -barGap, 0, thickness, mapSize, true)
            end
        else
            ConfigureBarLayout(first, anchor, "TOPLEFT", "TOPRIGHT", gap, 0, thickness, mapSize, true)
            if second then
                ConfigureBarLayout(second, first.host, "TOPLEFT", "TOPRIGHT", barGap, 0, thickness, mapSize, true)
            end
        end
    end

    if self.experienceData.visible then self.experienceBar.host:Show() else HideBar(self.experienceBar) end
    if self.reputationData.visible then self.reputationBar.host:Show() else HideBar(self.reputationBar) end
end

local function ApplyGeometry(self, holder, anchor, mapSize, config, visibleCount, refreshLayout)
    local barGap = Clamp(config.barGap, 0, 16, DEFAULT_BAR_GAP)
    local extra = visibleCount > 0
        and config.mapGap + visibleCount * config.thickness + (visibleCount - 1) * barGap
        or 0
    local width = mapSize
    local height = mapSize
    local offsetX = 0
    local offsetY = 0
    if config.position == "bottom" then
        height = height + extra
        offsetY = -extra * 0.5
    elseif config.position == "top" then
        height = height + extra
        offsetY = extra * 0.5
    elseif config.position == "left" then
        width = width + extra
        offsetX = -extra * 0.5
    elseif config.position == "right" then
        width = width + extra
        offsetX = extra * 0.5
    end

    local geometry = self.geometry
    local changed = geometry.width ~= width or geometry.height ~= height
        or geometry.offsetX ~= offsetX or geometry.offsetY ~= offsetY
        or geometry.mapSize ~= mapSize or geometry.extra ~= extra
    geometry.width = width
    geometry.height = height
    geometry.offsetX = offsetX
    geometry.offsetY = offsetY
    geometry.mapSize = mapSize
    geometry.extra = extra

    holder:ClearAllPoints()
    holder:SetPoint("CENTER", anchor, "CENTER", offsetX, offsetY)
    holder:SetSize(width, height)
    if changed then
        self.geometryChanges = self.geometryChanges + 1
        IncrementSharedStat("progressBarGeometryChanges", 1)
        if refreshLayout and YUI.Layout and type(YUI.Layout.RefreshFrame) == "function" then
            YUI.Layout:RefreshFrame(YMap.LAYOUT_ID or "yui.product.ymap.minimap")
        end
    end
    return changed
end

function ProgressBars:Apply(holder, anchor, mapSize, minimapConfig, style)
    mapSize = Clamp(mapSize, 120, 400, DEFAULT_MAP_SIZE)
    local config = minimapConfig and minimapConfig.statusBars
    local enabled = style == "square" and type(config) == "table"
        and (config.experienceEnabled == true or config.reputationEnabled == true)
    if not config then
        config = {
            experienceEnabled = false,
            reputationEnabled = false,
            position = "bottom",
            thickness = 12,
            texture = "yui-g1",
            experienceColor = DEFAULT_EXPERIENCE_COLOR,
            borderWidth = 1,
            borderColor = DEFAULT_BORDER_COLOR,
            backgroundColor = DEFAULT_TRACK_COLOR,
            mapGap = 2,
            barGap = DEFAULT_BAR_GAP,
            textDisplay = "hover",
        }
    end

    self.active = enabled
    ConfigureEvents(self, config, enabled)
    if enabled then
        self:CollectData(config)
    else
        ResetData(self.experienceData)
        ResetData(self.reputationData)
    end

    local visibility = GetVisibilityCode(self.experienceData, self.reputationData)
    local visibleCount = (self.experienceData.visible and 1 or 0)
        + (self.reputationData.visible and 1 or 0)
    self.visibleCount = visibleCount
    SetSharedStat("progressBarsVisible", visibleCount)

    if enabled and visibleCount > 0 then
        local experienceBar = EnsureBar("experience", holder)
        local reputationBar = EnsureBar("reputation", holder)
        if not (experienceBar and reputationBar) then
            ResetData(self.experienceData)
            ResetData(self.reputationData)
            visibility = 0
            visibleCount = 0
            self.visibleCount = 0
            SetSharedStat("progressBarsVisible", 0)
        end
    end

    ApplyGeometry(self, holder, anchor, mapSize, config, visibleCount, true)
    if visibleCount > 0 then
        PositionVisibleBars(self, holder, anchor, config, mapSize)
        local writes = 0
        if self.experienceData.visible then
            writes = writes + ApplyBarData(
                self.experienceBar,
                self.experienceData,
                config,
                config.experienceColor,
                true
            )
        end
        if self.reputationData.visible then
            writes = writes + ApplyBarData(
                self.reputationBar,
                self.reputationData,
                config,
                self.reputationData.color,
                true
            )
        end
        if writes > 0 then
            self.valueUpdates = self.valueUpdates + 1
            IncrementSharedStat("progressBarValueUpdates", 1)
        end
    else
        HideBar(self.experienceBar)
        HideBar(self.reputationBar)
    end
    self.appliedVisibility = visibility
    return self.geometry
end

function ProgressBars:OnProgressEvent()
    if self.active ~= true then return end
    local db = YMap.GetDB and YMap:GetDB()
    local minimap = db and db.minimap
    local config = minimap and minimap.statusBars
    if not config or minimap.style ~= "square" then return end

    local visibility = self:CollectData(config)
    if visibility ~= self.appliedVisibility then
        local minimapModule = YMap.Minimap
        if minimapModule and type(minimapModule.Refresh) == "function" then
            minimapModule:Refresh("progress-bars-geometry")
        end
        return
    end

    local writes = 0
    if self.experienceData.visible then
        writes = writes + ApplyBarData(
            self.experienceBar,
            self.experienceData,
            config,
            config.experienceColor
        )
    end
    if self.reputationData.visible then
        writes = writes + ApplyBarData(
            self.reputationBar,
            self.reputationData,
            config,
            self.reputationData.color
        )
    end
    if writes > 0 then
        self.valueUpdates = self.valueUpdates + 1
        IncrementSharedStat("progressBarValueUpdates", 1)
    end
end

function ProgressBars:GetMoverBounds(mapSize)
    local geometry = self.geometry
    mapSize = Clamp(mapSize, 120, 400, geometry.mapSize or DEFAULT_MAP_SIZE)
    if geometry.mapSize ~= mapSize and geometry.extra == 0 then
        return mapSize, mapSize, 0, 0
    end
    return geometry.width, geometry.height, geometry.offsetX, geometry.offsetY
end

function ProgressBars:Disable(holder, anchor, mapSize)
    self.active = false
    ConfigureEvents(self, {
        experienceEnabled = false,
        reputationEnabled = false,
    }, false)
    ResetData(self.experienceData)
    ResetData(self.reputationData)
    HideBar(self.experienceBar)
    HideBar(self.reputationBar)
    self.appliedVisibility = 0
    self.visibleCount = 0
    SetSharedStat("progressBarsVisible", 0)
    if holder and anchor then
        ApplyGeometry(self, holder, anchor, Clamp(mapSize, 120, 400, DEFAULT_MAP_SIZE), {
            position = "bottom",
            thickness = 12,
            mapGap = 2,
        }, 0, false)
    end
    return true
end

function ProgressBars:GetStats(target)
    target = type(target) == "table" and target or {}
    target.progressBarsVisible = self.visibleCount
    target.progressBarValueUpdates = self.valueUpdates
    target.progressBarGeometryChanges = self.geometryChanges
    target.progressBarEventsActive = self.eventSignature ~= nil and self.eventSignature > 0
    target.progressBarExperienceVisible = self.experienceData.visible == true
    target.progressBarReputationVisible = self.reputationData.visible == true
    return target
end

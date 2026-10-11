local function CreateInstance(context)
local YUI = _G.YUI
local Events = context and context.events or YUI.Event
local YBar = YUI.YBar
local Module = YBar.Module:New(context and context.id or "Stats")
local Locale = YUI.Locale
local YBarL = Locale and Locale:Get("YBar") or {}
local PanelL = Locale and Locale:Get("CharacterStatsPanel") or {}
local CoreL = Locale and Locale:Get("Core") or YUI.L
local ItemAPI = YUI.API and YUI.API.Item or YUI.WOW_API
local PaperDollAPI = YUI.API and YUI.API.PaperDoll
local UnitAPI = YUI.API and YUI.API.Unit
local FrameAPI = YUI.API and YUI.API.Frame or YUI.WOW_API
local SecurityAPI = YUI.API and YUI.API.Security or YUI.WOW_API

local format = string.format
local floor = math.floor
local ipairs = ipairs
local type = type
local tonumber = tonumber

local DEFAULT_FONT = "默认"
local DEFAULT_SIZE = 14
local PLAYER_UNIT_FILTER = { unit = "player" }

local function T(key, fallback, ...)
    local value = YBarL[key]
    if not value or value == "" or value == key then value = fallback or key end
    if select("#", ...) > 0 then return format(value, ...) end
    return value
end

local function GetYBarDB()
    if context then return context:GetRoot() end
    if YUI.YBar and YUI.YBar.GetModuleRoot then return YUI.YBar:GetModuleRoot("Stats") end
    if YBar and YBar.EnsureDB then return YBar:EnsureDB() end
    local profile = YUI.DB and YUI.DB.GetProfile and YUI.DB:GetProfile("ybar")
    if type(profile) ~= "table" then return nil end
    if type(profile.YBar) ~= "table" then profile.YBar = {} end
    return profile.YBar
end

local function IsSecretValue(value)
    if value == nil then return false end
    if SecurityAPI and SecurityAPI.IsSecretValue then
        local ok, secret = pcall(SecurityAPI.IsSecretValue, value)
        if ok then return secret == true end
    end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if ok then return secret == true end
    end
    return false
end

local function SafeNumber(value)
    if IsSecretValue(value) then return nil end
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function GetMaxLevel()
    if UnitAPI and type(UnitAPI.GetMaxPlayerLevel) == "function" then
        return SafeNumber(UnitAPI.GetMaxPlayerLevel())
    end
    return nil
end

local function ReadAverageItemLevel()
    if PaperDollAPI and type(PaperDollAPI.ReadAverageItemLevel) == "function" then
        local info
        if context and Events.ReadData then info=Events:ReadData("stats-item-level",PaperDollAPI.ReadAverageItemLevel,"player")
        else info=PaperDollAPI.ReadAverageItemLevel("player") end
        if type(info) == "table" and info.available == true then
            local equipped = SafeNumber(info.equipped)
            if equipped then return equipped end
        end
    end
    return nil
end

local SLOTS = {
    1,  -- Head
    2,  -- Neck
    3,  -- Shoulder
    15, -- Back
    5,  -- Chest
    9,  -- Wrist
    10, -- Hands
    6,  -- Waist
    7,  -- Legs
    8,  -- Feet
    11, -- Finger1
    12, -- Finger2
    13, -- Trinket1
    14, -- Trinket2
    16, -- MainHand
    17, -- OffHand
    18, -- Ranged
}

local function GetItemLevel(link)
    if not link then return 0 end
    return ItemAPI.GetLevel(link) or 0
end

local roleCtxCache = {
    role = "DAMAGER",
    isTank = false,
    isHealer = false,
    isCaster = false,
    isRanged = false,
}

local function RGBToHex(r, g, b)
    r = r <= 1 and r >= 0 and r or 0
    g = g <= 1 and g >= 0 and g or 0
    b = b <= 1 and b >= 0 and b or 0
    return string.format("%02x%02x%02x", r*255, g*255, b*255)
end

-- 自定义明亮声望颜色
local CUSTOM_FACTION_COLORS = {
    [1] = {r = 0.8, g = 0.3, b = 0.22}, -- 仇恨 (明亮红)
    [2] = {r = 0.8, g = 0.3, b = 0.22}, -- 敌对
    [3] = {r = 0.75, g = 0.27, b = 0},  -- 冷淡
    [4] = {r = 0.9, g = 0.7, b = 0},    -- 中立 (明亮黄)
    [5] = {r = 0.2, g = 1.0, b = 0.2},  -- 友善 (明亮绿)
    [6] = {r = 0.0, g = 1.0, b = 0.6},  -- 尊敬 (青绿)
    [7] = {r = 0.0, g = 1.0, b = 0.8},  -- 崇敬 (亮青)
    [8] = {r = 0.0, g = 1.0, b = 1.0},  -- 崇拜 (天蓝)
}

-- UTF8 字符串安全截取函数 (按字符数截取)
local function UTF8Sub(str, numChars)
    if not str then return "" end
    local len = string.len(str)
    local left = len
    local count = 0
    local offset = 1
    local res = ""
    while left > 0 and count < numChars do
        local b = string.byte(str, offset)
        local charBytes = 1
        if b >= 240 then charBytes = 4
        elseif b >= 224 then charBytes = 3
        elseif b >= 192 then charBytes = 2
        end
        res = res .. string.sub(str, offset, offset + charBytes - 1)
        offset = offset + charBytes
        left = left - charBytes
        count = count + 1
    end
    return res
end

-- ============================================================================
--  时光服(Wrath)专用辅助函数
-- ============================================================================
local function HexToRGB(hex)
    local r = tonumber(string.sub(hex, 1, 2), 16) / 255
    local g = tonumber(string.sub(hex, 3, 4), 16) / 255
    local b = tonumber(string.sub(hex, 5, 6), 16) / 255
    return r, g, b
end

local function HasSpellIDBuff(spellID)
    if not spellID then return false end
    for i = 1, 40 do
        local _, _, _, _, _, _, _, _, _, spell = UnitBuff("player", i)
        if not spell then break end
        if spell == spellID then return true end
    end
    return false
end


local function GetWatchedReputationInfo()
    local name, rankText, cur, max, pct, r, g, b
    r, g, b = 0, 0.66, 1 -- 默认蓝色

    if C_Reputation and C_Reputation.GetWatchedFactionData then
        -- 正式服 10.0+
        local data = C_Reputation.GetWatchedFactionData()
        if data and data.factionID then
            name = data.name
            local factionID = data.factionID

            -- 声望优先级：Friendship -> Paragon -> Renown -> Base
            local isFriendship, isParagon, isRenown = false, false, false

            -- 1. 友谊声望 / 子声望 (最高优先级，包含地下堡和各种特殊子阵营)
            if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
                local success, repInfo = pcall(C_GossipInfo.GetFriendshipReputation, factionID)
                if success and type(repInfo) == "table" and repInfo.friendshipFactionID and repInfo.friendshipFactionID > 0 then
                    isFriendship = true
                    rankText = repInfo.reaction or ""
                    
                    if repInfo.nextThreshold and repInfo.reactionThreshold then
                        cur = repInfo.standing - repInfo.reactionThreshold
                        max = repInfo.nextThreshold - repInfo.reactionThreshold
                        if max == 0 then max = 1 cur = 1 end
                    else
                        -- 满级或者没有下一级
                        cur = 1
                        max = 1
                    end
                    
                    -- 友谊声望颜色 (蓝绿色)
                    r, g, b = 0, 0.8, 0.6
                end
            end

            -- 2. 巅峰声望 (Paragon)
            if not isFriendship and C_Reputation.IsFactionParagonForCurrentPlayer and C_Reputation.IsFactionParagonForCurrentPlayer(factionID) then
                local success, pVal, pThreshold, _, hasRewardPending = pcall(C_Reputation.GetFactionParagonInfo, factionID)
                if success and pVal and pThreshold and pThreshold > 0 then
                    isParagon = true
                    cur = pVal % pThreshold
                    max = pThreshold
                    rankText = "巅峰"
                    if hasRewardPending then
                        cur = max
                    end
                    -- 巅峰声望颜色 (深蓝色)
                    r, g, b = 0, 0.6, 1
                end
            end

            -- 3. 名望系统 (Renown)
            if not isFriendship and not isParagon and C_Reputation.IsMajorFaction and C_Reputation.IsMajorFaction(factionID) then
                if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
                    local success, majorData = pcall(C_MajorFactions.GetMajorFactionData, factionID)
                    if success and type(majorData) == "table" and majorData.renownLevel then
                        isRenown = true
                        rankText = "名望 " .. tostring(majorData.renownLevel)
                        cur = majorData.renownReputationEarned or 0
                        max = majorData.renownLevelThreshold or 1
                        -- 名望颜色 (蓝色)
                        r, g, b = 0, 0.6, 1
                    end
                end
            end

            -- 4. 普通声望 (Base Reaction)
            if not isFriendship and not isParagon and not isRenown then
                cur = data.currentStanding - data.currentReactionThreshold
                max = data.nextReactionThreshold - data.currentReactionThreshold
                
                local reaction = data.reaction
                local gender = UnitSex("player")
                rankText = GetText("FACTION_STANDING_LABEL"..reaction, gender) or ""
                
                if reaction == 8 and max == 0 then -- 满级崇拜
                    cur = 1 max = 1
                end
                
                -- 获取关系颜色 (使用自定义的明亮颜色)
                local color = CUSTOM_FACTION_COLORS[reaction] or FACTION_BAR_COLORS[reaction]
                if color then r, g, b = color.r, color.g, color.b end
            end
        end
    elseif GetWatchedFactionInfo then
        -- 经典服/怀旧服
        local fName, reaction, fMin, fMax, fValue = GetWatchedFactionInfo()
        if fName then
            name = fName
            cur = fValue - fMin
            max = fMax - fMin
            local gender = UnitSex("player")
            rankText = GetText("FACTION_STANDING_LABEL"..reaction, gender) or ""
            if reaction == 8 and max == 0 then
                cur = 1 max = 1
            end
            local color = CUSTOM_FACTION_COLORS[reaction] or FACTION_BAR_COLORS[reaction]
            if color then r, g, b = color.r, color.g, color.b end
        end
    end

    if name then
        if max and max > 0 then
            pct = (cur / max) * 100
        else
            pct = 100
        end
        return name, rankText, cur, max, pct, r, g, b
    end
    return nil
end

local function NormalizeFontValue(font, lsm)
    local fallback = YBar:ResolveFontPath(DEFAULT_FONT, STANDARD_TEXT_FONT, lsm)
    return YBar:ResolveFontPath(font or DEFAULT_FONT, fallback, lsm)
end

local function SetFontCached(fontString, path, size, flags)
    if not fontString then return end
    if fontString._yuiStatsFont == path
        and fontString._yuiStatsSize == size
        and fontString._yuiStatsFlags == flags
    then
        return
    end
    fontString:SetFont(path, size, flags)
    fontString._yuiStatsFont = path
    fontString._yuiStatsSize = size
    fontString._yuiStatsFlags = flags
end

local function SetTextIfChanged(fontString, value)
    value = value or ""
    if fontString._yuiStatsText == value then return false end
    fontString._yuiStatsText = value
    fontString:SetText(value)
    return true
end

local function IsPanelComponentEnabled()
    local Components = YUI.Components
    return Components and Components:IsEnabled("CharacterStatsPanel")
        and YUI.CharacterStatsPanel
        and type(YUI.CharacterStatsPanel.Toggle) == "function"
end

local function IsPanelComponentRegistered()
    local Components = YUI.Components
    return Components and type(Components.Get) == "function"
        and Components:Get("CharacterStatsPanel") ~= nil
end

function Module:EnsureSettings()
    local db = GetYBarDB()
    if type(db) ~= "table" then
        self.settings = self.settings or {}
    else
        if type(db.Stats) ~= "table" then db.Stats = {} end
        self.settings = db.Stats
    end
    if self.settings.barFont == nil then self.settings.barFont = DEFAULT_FONT end
    if self.settings.barFontSize == nil then self.settings.barFontSize = DEFAULT_SIZE end
    if self.settings.showExperience == nil then self.settings.showExperience = true end
    if self.settings.showReputation == nil then self.settings.showReputation = true end
    if self.settings.showItemLevel == nil then self.settings.showItemLevel = true end
    if self.settings.itemLevelPrecision ~= 1 and self.settings.itemLevelPrecision ~= 2 then
        self.settings.itemLevelPrecision = 0
    end
    return self.settings
end

function Module:ClearResolvedState()
    self.resolvedKind = nil
    self.resolvedText = ""
    self.resolvedProgress = nil
    self.resolvedRested = nil
    self.resolvedColorR = nil
    self.resolvedColorG = nil
    self.resolvedColorB = nil
end

function Module:ResolveExperience()
    local level = SafeNumber(UnitLevel("player"))
    local maximumLevel = GetMaxLevel()
    if not level or (maximumLevel and level >= maximumLevel) then return false end
    if type(UnitXP) ~= "function" or type(UnitXPMax) ~= "function" then return false end

    local current = SafeNumber(UnitXP("player"))
    local maximum = SafeNumber(UnitXPMax("player"))
    if not current or not maximum or maximum <= 0 then return false end

    local percent = math.max(0, math.min(100, current / maximum * 100))
    local rested = type(GetXPExhaustion) == "function" and SafeNumber(GetXPExhaustion()) or 0
    rested = rested or 0
    local restedPercent = math.max(0, rested / maximum * 100)

    self.resolvedKind = "experience"
    if restedPercent >= 1 then
        self.resolvedText = format("Lv. %d (%.0f%% |cff00aaff+%.0f%%|r)", level, percent, restedPercent)
    else
        self.resolvedText = format("Lv. %d (%.0f%%)", level, percent)
    end
    self.resolvedProgress = math.max(0, math.min(1, current / maximum))
    self.resolvedRested = math.max(0, math.min(1 - self.resolvedProgress, rested / maximum))
    return true
end

function Module:ResolveReputation()
    local name, rank, current, maximum, percent, r, g, b = GetWatchedReputationInfo()
    if not name then return false end

    local shortName = UTF8Sub(name, 6)
    local isFull = (percent or 0) >= 100 or not maximum or maximum <= 0
    if rank and rank ~= "" then
        local color = RGBToHex(r, g, b)
        if isFull then
            self.resolvedText = format("%s |cff%s%s|r", shortName, color, rank)
        else
            self.resolvedText = format("%s |cff%s%s|r (%.0f%%)", shortName, color, rank, percent or 0)
        end
    elseif isFull then
        self.resolvedText = shortName
    else
        self.resolvedText = format("%s (%.0f%%)", shortName, percent or 0)
    end

    self.resolvedKind = "reputation"
    if maximum and maximum > 0 then
        self.resolvedProgress = math.max(0, math.min(1, (current or 0) / maximum))
        self.resolvedRested = 0
        self.resolvedColorR, self.resolvedColorG, self.resolvedColorB = r, g, b
    end
    return true
end

function Module:FormatItemLevel(value)
    local precision = self.settings.itemLevelPrecision
    if precision == 1 then return format("%.1f", value) end
    if precision == 2 then return format("%.2f", value) end
    return format("%.0f", floor(value))
end

function Module:ResolveItemLevel()
    local equipped = ReadAverageItemLevel()
    if not equipped or equipped <= 0 then return false end
    self.resolvedKind = "itemLevel"
    self.resolvedText = "iLv. " .. self:FormatItemLevel(equipped)
    return true
end

function Module:ResolveBarState()
    self:EnsureSettings()
    self:ClearResolvedState()

    if self.settings.showExperience and self:ResolveExperience() then
    elseif self.settings.showReputation and self:ResolveReputation() then
    elseif self.settings.showItemLevel then
        self:ResolveItemLevel()
    end

    if YUI.IsRetail and self.settings.alwaysShowItemLevel and self.settings.showItemLevel
        and self.resolvedKind and self.resolvedKind ~= "itemLevel" then
        local equipped = ReadAverageItemLevel()
        if equipped and equipped > 0 then
            self.resolvedText = self.resolvedText .. " | iLv. " .. self:FormatItemLevel(equipped)
        end
    end
    self.stateDirty = false
    self.hasBarContent = self.resolvedKind ~= nil
    return self.hasBarContent
end

function Module:IsBarItemRenderable()
    if self.stateDirty or self.hasBarContent == nil then
        self:ResolveBarState()
    end
    return self.hasBarContent == true
end

function Module:StopPostCombatUpdate()
    if self.barItemPostCombatHandle and self.barItemPostCombatHandle.Cancel then
        self.barItemPostCombatHandle:Cancel()
    end
    self.barItemPostCombatHandle = nil
    self.barItemUpdatePendingInCombat = false
end

function Module:QueuePostCombatUpdate()
    self.barItemUpdatePendingInCombat = true
    if self.barItemPostCombatHandle or not (Events and Events.Once) then return end
    self.barItemPostCombatHandle = Events:Once("PLAYER_REGEN_ENABLED", function()
        self.barItemPostCombatHandle = nil
        if not self.barItemUpdatePendingInCombat then return end
        self.barItemUpdatePendingInCombat = false
        if self:IsRuntimeActive() then self:UpdateBarItem() end
    end, self)
end

function Module:IsRuntimeActive()
    return self._runtimeAttached
        and YBar
        and YBar.IsSubModuleEnabled
        and YBar:IsSubModuleEnabled(self.name)
end

function Module:RefreshEventSubscriptions()
    if not Events then return end
    self.eventOwner = self.eventOwner or { traceName = "YBar:ExperienceReputation" }
    self.eventOwner.OnBarEvent = self.eventOwner.OnBarEvent or function(_, event)
        Module:OnBarEvent(event)
    end
    Events:OffOwner(self.eventOwner)
    self.listenerCount = 0
    if not self._runtimeAttached then return end

    local function On(event, options)
        Events:On(event, "OnBarEvent", self.eventOwner, options)
        self.listenerCount = self.listenerCount + 1
    end

    if self.settings.showExperience then
        On("PLAYER_LEVEL_UP")
        On("PLAYER_XP_UPDATE")
        On("UPDATE_EXHAUSTION")
    end
    if self.settings.showReputation then
        On("UPDATE_FACTION")
        if YUI.IsRetail and C_Reputation and C_Reputation.GetWatchedFactionData then
            On("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
        end
    end
    if self.settings.showItemLevel then
        On("PLAYER_AVG_ITEM_LEVEL_UPDATE")
        On("PLAYER_EQUIPMENT_CHANGED")
    end
    if self.listenerCount > 0 then On("YUI_WORLD_READY") end
end

function Module:OnBarEvent()
    if not self:IsRuntimeActive() then return end
    self.stateDirty = true
    if not self.frame then
        local previousRenderable = self.hasBarContent == true
        self:ResolveBarState()
        if previousRenderable ~= self.hasBarContent and YBar.UpdateLayout then
            YBar:UpdateLayout()
        end
        return
    end
    self:UpdateBarItem()
end

function Module:OnInitialize()
    self:EnsureSettings()
    self.stateDirty = true
    self.listenerCount = 0
    self.barItemUpdatePendingInCombat = false
end

function Module:OnDBReload()
    self:EnsureSettings()
    self.stateDirty = true
    self:RefreshEventSubscriptions()
    self:UpdateBarItem()
end

function Module:AttachRuntime()
    self._runtimeAttached = true
    self:EnsureSettings()
    self.stateDirty = true
    self:RefreshEventSubscriptions()
    self:UpdateBarItem()
end

function Module:DetachRuntime()
    self._runtimeAttached = false
    if Events then
        if self.eventOwner then Events:OffOwner(self.eventOwner) end
        Events:OffOwner(self)
    end
    self.listenerCount = 0
    self:StopPostCombatUpdate()
    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self.frame then
        YUI.HideGameTooltip()
    end
    if self.frame then self.frame:Hide() end
end

function Module:ShowTooltip(frame)
    GameTooltip:SetOwner(frame, "ANCHOR_TOP")
    local level = SafeNumber(UnitLevel("player")) or 0
    local equipped = ReadAverageItemLevel()
    GameTooltip:AddDoubleLine(format("%s %d", LEVEL, level), T("stats.stat.ilvl", "装等") .. " " .. self:FormatItemLevel(equipped or 0))

    local maximumLevel = GetMaxLevel()
    if not maximumLevel or level < maximumLevel then
        local current = type(UnitXP) == "function" and SafeNumber(UnitXP("player")) or nil
        local maximum = type(UnitXPMax) == "function" and SafeNumber(UnitXPMax("player")) or nil
        if current and maximum and maximum > 0 then
            local percent = current / maximum * 100
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(format("%s: |cffffffff%s|r / |cffffffff%s|r (|cff00ff00%.1f%%|r)",
                T("stats.tooltip.experience", "经验"),
                BreakUpLargeNumbers(current),
                BreakUpLargeNumbers(maximum),
                percent
            ))
            local rested = type(GetXPExhaustion) == "function" and SafeNumber(GetXPExhaustion()) or 0
            if rested and rested > 0 then
                GameTooltip:AddLine(format("%s: |cff00aaff%s|r (|cff00aaff%.1f%%|r)",
                    T("stats.tooltip.rested", "双倍"),
                    BreakUpLargeNumbers(rested),
                    rested / maximum * 100
                ))
            end
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(T("stats.tooltip.equipped_items", "已装备物品:"))
    for _, slot in ipairs(SLOTS) do
        local link = ItemAPI.GetInventoryItemLink("player", slot)
        if link then
            local texture = ItemAPI.GetInventoryItemTexture("player", slot)
            local name = ItemAPI.GetName(link)
            local itemLevel = GetItemLevel(link)
            local quality = ItemAPI.GetInventoryItemQuality("player", slot)
            local r, g, b = 1, 1, 1
            if quality then r, g, b = ItemAPI.GetQualityColor(quality) end
            local icon = format("|T%s:14:14:0:0:64:64:4:60:4:60|t", texture)
            local left = format("%s |cff%02x%02x%02x%s|r |cffAAAAAA(%d)|r",
                icon, r * 255, g * 255, b * 255, name or "Unknown", itemLevel)
            local right = ""
            local current, maximum = ItemAPI.GetInventoryItemDurability(slot)
            if current and maximum and maximum > 0 then
                local percent = current / maximum * 100
                local dr, dg, db = 0, 1, 0
                if percent < 30 then
                    dr, dg, db = 1, 0.2, 0.2
                elseif percent < 60 then
                    dr, dg, db = 1, 0.8, 0.2
                end
                right = format("|cff%02x%02x%02x%d%%|r", dr * 255, dg * 255, db * 255, floor(percent))
            end
            GameTooltip:AddDoubleLine(left, right)
        end
    end

    local headerColor = CreateColor(1, 0.82, 0)
    local gold = "|c" .. headerColor:GenerateHexColor()
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(format("|cffffffff%s: |r%s%s|r",
        CoreL["common.left_click"], gold, T("stats.action.open_character", "打开角色面板")))
    if IsPanelComponentEnabled() then
        local title = YUI.F:GetGradientText(
            PanelL["stats.panel.title"] or "角色属性面板",
            { 0.84, 0.41, 1 },
            { 0.64, 0.21, 0.93 }
        )
        GameTooltip:AddLine(format("|cffffffff%s: |r%s%s|r",
            CoreL["common.right_click"],
            gold,
            T("stats.action.toggle_panel", "显示/隐藏 %s", title)
        ))
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(format("|cff808080%s: %s|r", CoreL["common.alt_left_click"], CoreL["common.open_settings"]))
    GameTooltip:Show()
end

function Module:CreateBarItem(parent)
    self.frame = YBar:CreateBarItem(parent, {
        variant = "bare",
        width = 80,
        height = 20,
        clickable = true,
        showIcon = false,
        text = false,
        value = false,
    })
    self.frame.statusText, self.frame.text = YBar:CreateStatusText(self.frame, {
        variant = "single",
        value = "",
        width = 80,
        height = 20,
        justifyH = "CENTER",
        colorKey = "color.ybar.text",
    })
    self.frame.text:ClearAllPoints()
    self.frame.text:SetPoint("CENTER", 0, 0)
    YBar:RegisterBarItemHoverText(self.frame, self.frame.text)

    self.frame.xpLine = YBar:CreateMiniProgressLine(self.frame, { height = 2 })
    self.frame.xpLine:SetPoint("TOPLEFT", self.frame.text, "BOTTOMLEFT", 0, 1)
    self.frame.xpLine:Hide()

    self.frame:SetScript("OnEnter", function(frame)
        if YBar.OnModuleEnter then YBar:OnModuleEnter(frame) end
        YBar:SetThemedTextAccent(frame.text)
        self:ShowTooltip(frame)
    end)
    self.frame:SetScript("OnLeave", function(frame)
        if YBar.OnModuleLeave then YBar:OnModuleLeave(frame) end
        YUI.HideGameTooltip()
        YBar:RestoreThemedTextColor(frame.text, "color.ybar.text")
    end)

    local actionHost = YBar:CreateActionHost(self.frame, {
        onEnter = function(_, owner)
            local script = owner:GetScript("OnEnter")
            if script then script(owner) end
        end,
        onLeave = function(_, owner)
            local script = owner:GetScript("OnLeave")
            if script then script(owner) end
        end,
    })
    if actionHost then
        actionHost:SetActions({
            -- 由安全动作转交原生按钮，避免插件 PostClick 的参数污染人物面板。
            left = YUI.IsForever and { kind = "click", clickbutton = _G.CharacterMicroButton } or {
                kind = "custom",
                onClick = function()
                    FrameAPI.ToggleCharacter("PaperDollFrame")
                end,
            },
            right = {
                kind = "custom",
                onClick = function()
                    if IsPanelComponentEnabled() then
                        YUI.CharacterStatsPanel:Toggle()
                    end
                end,
            },
            altLeft = {
                kind = "custom",
                onClick = function()
                    YUI:OpenYBarModuleSettings("Stats")
                end,
            },
        })
    end

    self.stateDirty = true
    self:UpdateBarItem(self.frame, parent)
    return self.frame
end

function Module:UpdateBarItem(_, parent)
    if not self.frame or not self.frame.text then return end
    local previousRenderable = self.hasBarContent == true
    self:ResolveBarState()

    local lsm = YUI.LSM or LibStub("LibSharedMedia-3.0")
    local globalDB = GetYBarDB() or {}
    local fontPath = NormalizeFontValue(self.settings.barFont, lsm)
    local fontSize = self.settings.barFontSize or DEFAULT_SIZE
    local flags = globalDB.fontFlags or (globalDB.fontOutline and "OUTLINE" or "")
    SetFontCached(self.frame.text, fontPath, fontSize, flags)
    if globalDB.fontShadow then
        if self.renderedFontShadow ~= true then
            self.frame.text:SetShadowColor(0, 0, 0, 1)
            self.frame.text:SetShadowOffset(1, -1)
            self.renderedFontShadow = true
        end
    elseif self.renderedFontShadow ~= false then
        self.frame.text:SetShadowOffset(0, 0)
        self.renderedFontShadow = false
    end

    if not self.hasBarContent then
        SetTextIfChanged(self.frame.text, "")
        if self.renderedProgressVisible ~= false then
            self.frame.xpLine:Hide()
            self.renderedProgressVisible = false
        end
        if self.renderedVisible ~= false then
            self.frame:Hide()
            self.renderedVisible = false
        end
    else
        SetTextIfChanged(self.frame.text, self.resolvedText)
        if self.renderedVisible ~= true then
            self.frame:Show()
            self.renderedVisible = true
        end
        if self.resolvedProgress then
            local lineWidth = self.frame.text:GetStringWidth()
            local rested = self.resolvedRested or 0
            if self.renderedProgressWidth ~= lineWidth then
                self.frame.xpLine:SetBarWidth(lineWidth)
                self.renderedProgressWidth = lineWidth
            end
            if self.renderedProgress ~= self.resolvedProgress or self.renderedRested ~= rested then
                self.frame.xpLine:SetValues(self.resolvedProgress, rested)
                self.renderedProgress = self.resolvedProgress
                self.renderedRested = rested
            end
            if self.resolvedColorR and self.frame.xpLine.SetStatusBarColor then
                self.frame.xpLine:SetStatusBarColor(self.resolvedColorR, self.resolvedColorG, self.resolvedColorB)
            end
            if self.renderedProgressVisible ~= true then
                self.frame.xpLine:Show()
                self.renderedProgressVisible = true
            end
        elseif self.renderedProgressVisible ~= false then
            self.frame.xpLine:Hide()
            self.renderedProgressVisible = false
        end
    end

    if parent then return end
    local targetWidth = self:GetWidth()
    local oldWidth = self.frame:GetWidth() or 0
    local renderableChanged = previousRenderable ~= self.hasBarContent
    if renderableChanged or math.abs(targetWidth - oldWidth) > 2 then
        if SecurityAPI.InCombatLockdown() then
            self:QueuePostCombatUpdate()
            return
        end
        self.frame:SetWidth(math.max(targetWidth, 1))
        if YBar.UpdateLayout then YBar:UpdateLayout() end
    end
end

function Module:GetWidth()
    if not self.hasBarContent or not self.frame or not self.frame.text then return 0 end
    return self.frame.text:GetStringWidth() + 10
end

function Module:GetOptions()
    local lsm = YUI.LSM or LibStub("LibSharedMedia-3.0")
    self:EnsureSettings()
    local fontOptions = {}
    local fontList = lsm:HashTable("font")
    for name, path in pairs(fontList) do
        if type(path) == "string" and path ~= "" then
            fontOptions[#fontOptions + 1] = { text = name, value = path }
        end
    end
    table.sort(fontOptions, function(a, b) return a.text < b.text end)

    local function ApplyDisplaySetting(key, value)
        self.settings[key] = value
        self.stateDirty = true
        self:RefreshEventSubscriptions()
        if self.frame then
            self:UpdateBarItem()
        else
            local previousRenderable = self.hasBarContent == true
            self:ResolveBarState()
            if previousRenderable ~= self.hasBarContent and YBar.UpdateLayout then
                YBar:UpdateLayout()
            end
        end
    end

    local options = {
        {
            type = "divider",
            width = 400,
            label = YBarL["ybar.settings.section.info_bar"] or "信息条",
            alignLeft = true,
        },
        {
            type = "row",
            children = {
                {
                    type = "checkbox",
                    label = YBarL["stats.settings.show_experience"] or "显示经验",
                    get = function() return self.settings.showExperience == true end,
                    set = function(value) ApplyDisplaySetting("showExperience", value) end,
                },
                {
                    type = "checkbox",
                    label = YBarL["stats.settings.show_reputation"] or "显示声望",
                    get = function() return self.settings.showReputation == true end,
                    set = function(value) ApplyDisplaySetting("showReputation", value) end,
                },
                {
                    type = "checkbox",
                    label = YBarL["stats.settings.show_item_level"] or "显示装等",
                    get = function() return self.settings.showItemLevel == true end,
                    set = function(value) ApplyDisplaySetting("showItemLevel", value) end,
                },
            },
        },
        {
            type = "row",
            children = {
                {
                    type = "dropdown",
                    label = CoreL["common.font"] or "字体",
                    inlineLabel = true,
                    width = 220,
                    labelWidth = 60,
                    controlWidth = 150,
                    options = fontOptions,
                    get = function() return NormalizeFontValue(self.settings.barFont, lsm) end,
                    set = function(value)
                        self.settings.barFont = value
                        self:UpdateBarItem()
                    end,
                },
                {
                    type = "slider",
                    label = CoreL["common.font_size"] or "字号",
                    inline = true,
                    inputWidth = 56,
                    width = 220,
                    min = 8,
                    max = 20,
                    step = 1,
                    get = function() return self.settings.barFontSize or DEFAULT_SIZE end,
                    set = function(value)
                        self.settings.barFontSize = value
                        self:UpdateBarItem()
                    end,
                },
            },
        },
    }

    table.insert(options, 3, {
        type = "dropdown",
        label = T("stats.settings.item_level_precision"),
        options = {
            { text = T("stats.settings.item_level_integer"), value = 0 },
            { text = T("stats.settings.item_level_one_decimal"), value = 1 },
            { text = T("stats.settings.item_level_two_decimals"), value = 2 },
        },
        get = function() return self.settings.itemLevelPrecision or 0 end,
        set = function(value) ApplyDisplaySetting("itemLevelPrecision", value) end,
    })

    if IsPanelComponentRegistered() then
        options[#options + 1] = {
            type = "row",
            children = {
                {
                    type = "button",
                    label = T("stats.settings.open_stats_panel", "前往属性面板"),
                    tooltip = T("stats.settings.open_stats_panel_tip", "打开角色属性面板的功能设置"),
                    width = 140,
                    onClick = function()
                        if YUI.Settings and type(YUI.Settings.OpenComponentFeature) == "function" then
                            YUI.Settings:OpenComponentFeature("CharacterStatsPanel")
                        end
                    end,
                },
            },
        }
    end

    if YUI.IsRetail then
        table.insert(options, 3, {
            type = "checkbox", label = YBarL["stats.settings.always_item_level"],
            get = function() return self.settings.alwaysShowItemLevel == true end,
            set = function(value) ApplyDisplaySetting("alwaysShowItemLevel", value) end,
        })
    end
    return options
end

if not context then
YBar:RegisterModule(Module, {
    id = "ybar.stats",
    parent = "ybar",
    product = "ybar",
    scope = "ybar",
    dependencies = { "ybar", "core.event", "core.api" },
    defaultEnabled = true,
})
end

Module.moduleType = "Stats"
Module.instanceContext = context
return Module
end

local YBar = _G.YUI.YBar
YBar.ModuleFactories = YBar.ModuleFactories or {}
YBar.ModuleFactories.Stats = CreateInstance
CreateInstance()

local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI then return end

local Components = YUI.Components
local GUI2 = YUI.GUI2
if not Components or not GUI2 then return end

local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"
local FEATURE_KEY = "CharacterStatsPanel"
local CONFIG_KEY = "CharacterStatsPanel_Config"
local MIGRATION_VERSION = 1
local Module = YUI.CharacterStatsPanel or {}
YUI.CharacterStatsPanel = Module

local L = YUI.L
local LC = YUI.Locale and YUI.Locale:Get("Core") or L
local YBarL = YUI.Locale and YUI.Locale:Get("CharacterStatsPanel") or {}
local API = YUI.WOW_API
local FrameAPI = YUI.API and YUI.API.Frame or API
local CombatAPI = YUI.API and YUI.API.Combat or API
local SecurityAPI = YUI.API and YUI.API.Security or API
local ItemAPI = YUI.API and YUI.API.Item or API
local TalentAPI = YUI.API and YUI.API.Talent or API
local UnitAPI = YUI.API and YUI.API.Unit or API
local PaperDollAPI = YUI.API and YUI.API.PaperDoll
local Animation = YUI.Animation
local PLAYER_UNIT_FILTER = { unit = "player" }

-- ============================================================================
--  缓存常用 Lua 与 WoW API
-- ============================================================================
local format = string.format
local floor = math.floor
local ipairs = ipairs
local pairs = pairs
local type = type
local tonumber = tonumber
local tostring = tostring
local wipe = table.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

-- ============================================================================
--  本地化（属性专用）
-- ============================================================================
local SL = {
    STAT_ILVL = "装等",
    STAT_STR = "力量",
    STAT_AGI = "敏捷",
    STAT_INT = "智力",
    STAT_STA = "耐力",
    STAT_CRIT = "爆击",
    STAT_HASTE = "急速",
    STAT_MASTERY = "精通",
    STAT_VERSATILITY = "全能",
    STAT_ARMOR = "护甲",
    STAT_DODGE = "躲闪",
    STAT_PARRY = "招架",
    STAT_BLOCK = "格挡",
    STAT_LEECH = "吸血",
    STAT_AVOIDANCE = "闪避",
    STAT_SPEED = "加速",
    STAT_MOVESPEED = "移速",
    STAT_STAGGER = "醉拳",
    STAT_MANAREGEN = "法回",
    STAT_SPIRIT = "精神",
    STAT_HIT = "命中",
    STAT_ATTACKPOWER = "攻强",
    STAT_SPELLPOWER = "法强",
    STAT_EXPERTISE = "精准",
    STAT_PVPPOWER = "PvP强度",
    STAT_PVPRESILIENCE = "韧性",
    STAT_RANGEDATTACKPOWER = "远攻",

    STAT_ILVL_TT = "你已装备物品的平均物品等级。",
    -- ... add more tooltips as needed
}

local STAT_LOCALE_KEYS = {
    STAT_ILVL = "ilvl",
    STAT_STR = "str",
    STAT_AGI = "agi",
    STAT_INT = "int",
    STAT_STA = "sta",
    STAT_CRIT = "crit",
    STAT_HASTE = "haste",
    STAT_MASTERY = "mastery",
    STAT_VERSATILITY = "versatility",
    STAT_ARMOR = "armor",
    STAT_DODGE = "dodge",
    STAT_PARRY = "parry",
    STAT_BLOCK = "block",
    STAT_LEECH = "leech",
    STAT_AVOIDANCE = "avoidance",
    STAT_SPEED = "speed",
    STAT_MOVESPEED = "movespeed",
    STAT_STAGGER = "stagger",
    STAT_MANAREGEN = "manaregen",
    STAT_SPIRIT = "spirit",
    STAT_HIT = "hit",
    STAT_ATTACKPOWER = "attack_power",
    STAT_SPELLPOWER = "spell_power",
    STAT_EXPERTISE = "expertise",
    STAT_PVPPOWER = "pvp_power",
    STAT_PVPRESILIENCE = "pvp_resilience",
    STAT_RANGEDATTACKPOWER = "ranged_attack_power",
}

-- Helper to get localized string
local function GetSL(key)
    local localeKey = STAT_LOCALE_KEYS[key] or key
    local fullKey = "stats.stat." .. localeKey
    local value = YBarL and YBarL[fullKey]
    if value and value ~= "" and value ~= fullKey then
        return value
    end
    return SL[key] or key
end

-- ============================================================================
--  常量与辅助函数
-- ============================================================================
local IS_CLASSIC = not YUI.IsRetail
local CR_CRIT = 9
local CR_HASTE = 18
local CR_MASTERY = 26
local CR_VERSATILITY = 29
local SECONDARY_RATING_CR = {
    crit = CR_CRIT,
    haste = CR_HASTE,
    mastery = CR_MASTERY,
    versatility = CR_VERSATILITY,
}
local SECONDARY_RATING_PREFIX_FORMAT = "%.0f · "
local function NormalizeSecondaryRatingFormat(value)
    if value == "PERCENT_FIRST" or value == "PERCENT_PARENS" then return value end
    return "RATING_FIRST"
end

local function GetSecondaryRatingFormat(percentFormat, displayFormat)
    if displayFormat == "PERCENT_FIRST" then return percentFormat .. " · %.0f" end
    if displayFormat == "PERCENT_PARENS" then return percentFormat .. " (%.0f)" end
    return SECONDARY_RATING_PREFIX_FORMAT .. percentFormat
end
local DEFAULT_FONT = "Fonts\\ARKai_T.ttf"
local DEFAULT_SIZE = 14
local DEFAULT_SPACING = 21
local DEFAULT_PRECISION = 0
local DEFAULT_PANEL_WIDTH = 128
local MIN_PANEL_WIDTH = 20
local MIN_SECONDARY_RATING_PANEL_WIDTH = 140
local DEFAULT_HORIZONTAL_MAX_WIDTH = 695
local MIN_HORIZONTAL_MAX_WIDTH = 100
local MAX_HORIZONTAL_MAX_WIDTH = 1000
local PANEL_REFRESH_INTERVAL = 0.5
local SPEED_UPDATE_INTERVAL = 1.0
local DEFAULT_SPEED_UPDATE_FREQ = SPEED_UPDATE_INTERVAL
local STATS_FADE_ANIMATION_OWNER = {}
local STATS_LAYOUT_ID = "ybar.stats.panel"
local DEFAULT_PANEL_POINT = "BOTTOM"
local DEFAULT_PANEL_RELATIVE_POINT = "BOTTOM"
local DEFAULT_PANEL_OFFSET_X = -455
local DEFAULT_PANEL_OFFSET_Y = 0
local PANEL_ORIENTATION_VERTICAL = "VERTICAL"
local PANEL_ORIENTATION_HORIZONTAL = "HORIZONTAL"
local HORIZONTAL_ALIGNMENT_LEFT = "LEFT"
local HORIZONTAL_ALIGNMENT_CENTER = "CENTER"
local HORIZONTAL_ALIGNMENT_RIGHT = "RIGHT"
local COLOR_STYLE_WHITE = "WHITE"
local COLOR_STYLE_LABEL_COLORED = "LABEL_COLORED"
local COLOR_STYLE_VALUE_COLORED = "VALUE_COLORED"
local COLOR_STYLE_BOTH_COLORED = "COLORED"
local DEFAULT_COLUMN_SPACING = 21
local HORIZONTAL_TEXT_GAP = 4
local HORIZONTAL_SIDE_PADDING = 0
local HORIZONTAL_TEXT_SAFETY_PADDING = 6
local SECRET_TEXT_FALLBACK_WIDTH = 32
local FONT_EFFECT_NONE = "NONE"
local FONT_EFFECT_OUTLINE = "OUTLINE"
local FONT_EFFECT_THICK = "THICK_OUTLINE"
local FONT_EFFECT_SHADOW = "SHADOW"
local FONT_EFFECT_OUTLINE_SHADOW = "OUTLINE_SHADOW"
local DEFAULT_FONT_EFFECT = FONT_EFFECT_OUTLINE_SHADOW
local VERSATILITY_DISPLAY_SINGLE = "SINGLE"
local VERSATILITY_DISPLAY_SPLIT = "SPLIT"
local VERSATILITY_SINGLE_FORMATS = {
    [0] = "%.0f%%",
    [1] = "%.1f%%",
    [2] = "%.2f%%",
}
local VERSATILITY_SPLIT_FORMATS = {
    [0] = "%.0f%%+%.0f%%",
    [1] = "%.1f%%+%.1f%%",
    [2] = "%.2f%%+%.2f%%",
}
local MAX_STATS_LINES = 14
if YUI and YUI.IsForever then MAX_STATS_LINES = 16 end

local function NormalizeVersatilityDisplayMode(value)
    return value == VERSATILITY_DISPLAY_SPLIT and VERSATILITY_DISPLAY_SPLIT or VERSATILITY_DISPLAY_SINGLE
end

local function SetWidthIfChanged(region, width)
    if not region or not region.SetWidth or region._yuiStatsWidth == width then return end
    region:SetWidth(width)
    region._yuiStatsWidth = width
end

local function SetHeightIfChanged(region, height)
    if not region or not region.SetHeight or region._yuiStatsHeight == height then return end
    region:SetHeight(height)
    region._yuiStatsHeight = height
end

local function SetSizeIfChanged(region, width, height)
    if not region or not region.SetSize then return end
    if region._yuiStatsWidth == width and region._yuiStatsHeight == height then return end
    region:SetSize(width, height)
    region._yuiStatsWidth = width
    region._yuiStatsHeight = height
end

local function SetScaleIfChanged(region, scale)
    if not region or not region.SetScale or region._yuiStatsScale == scale then return end
    region:SetScale(scale)
    region._yuiStatsScale = scale
end

local function SetShownIfChanged(region, shown)
    if not region or region._yuiStatsShown == shown then return end
    if shown then region:Show() else region:Hide() end
    region._yuiStatsShown = shown
end

local function IsSecretValue(value)
    if value == nil then return false end
    if SecurityAPI and SecurityAPI.IsSecretValue then
        local ok, secret = pcall(SecurityAPI.IsSecretValue, value)
        if ok then
            return secret == true
        end
    elseif issecretvalue then
        local ok, secret = pcall(issecretvalue, value)
        if ok then
            return secret == true
        end
    end
    return false
end

local function ReadSecondaryStatRating(statId)
    local ratingIndex = SECONDARY_RATING_CR[statId]
    if not YUI.IsRetail or not ratingIndex or type(GetCombatRating) ~= "function" then
        return nil, false
    end

    local ok, rating = pcall(GetCombatRating, ratingIndex)
    if not ok then return nil, false end

    local secret = IsSecretValue(rating)
    if secret then return rating, true end
    if rating == nil then return nil, false end
    return rating, false
end

local function GetPanelOrientation(settings)
    return settings and settings.panelOrientation == PANEL_ORIENTATION_HORIZONTAL and PANEL_ORIENTATION_HORIZONTAL or PANEL_ORIENTATION_VERTICAL
end

local function GetHorizontalMaxWidth(settings)
    local value = settings and tonumber(settings.horizontalMaxWidth)
    if not value then return DEFAULT_HORIZONTAL_MAX_WIDTH end
    return math.max(MIN_HORIZONTAL_MAX_WIDTH, math.min(MAX_HORIZONTAL_MAX_WIDTH, value))
end

local function NormalizeHorizontalAlignment(alignment)
    if alignment == HORIZONTAL_ALIGNMENT_LEFT or alignment == HORIZONTAL_ALIGNMENT_RIGHT then
        return alignment
    end
    return HORIZONTAL_ALIGNMENT_CENTER
end

local function GetStatsPanelWidth(settings)
    if GetPanelOrientation(settings) == PANEL_ORIENTATION_HORIZONTAL then
        return GetHorizontalMaxWidth(settings)
    end
    local minWidth = YUI.IsRetail and settings and settings.showSecondaryRating == true
        and MIN_SECONDARY_RATING_PANEL_WIDTH or MIN_PANEL_WIDTH
    return math.max(tonumber(settings and settings.panelWidth) or DEFAULT_PANEL_WIDTH, minWidth)
end

local function GetColumnSpacing(settings)
    local value = settings and tonumber(settings.columnSpacing)
    if not value then return DEFAULT_COLUMN_SPACING end
    if value < 0 then return 0 end
    return value
end

local function NormalizeColorStyle(style)
    if style == COLOR_STYLE_WHITE or style == COLOR_STYLE_LABEL_COLORED or style == COLOR_STYLE_VALUE_COLORED or style == COLOR_STYLE_BOTH_COLORED then
        return style
    end
    return COLOR_STYLE_BOTH_COLORED
end

local function NormalizeFontEffect(effect)
    if effect == FONT_EFFECT_NONE
        or effect == FONT_EFFECT_OUTLINE
        or effect == FONT_EFFECT_THICK
        or effect == FONT_EFFECT_SHADOW
        or effect == FONT_EFFECT_OUTLINE_SHADOW
    then
        return effect
    end
    return DEFAULT_FONT_EFFECT
end

local function GetFontFlagForEffect(effect)
    effect = NormalizeFontEffect(effect)
    if effect == FONT_EFFECT_THICK then
        return "THICKOUTLINE"
    end
    if effect == FONT_EFFECT_OUTLINE or effect == FONT_EFFECT_OUTLINE_SHADOW then
        return "OUTLINE"
    end
    return ""
end

local function ApplyFontEffect(fontString, effect)
    if not fontString then return end
    effect = NormalizeFontEffect(effect)
    if effect == FONT_EFFECT_SHADOW or effect == FONT_EFFECT_OUTLINE_SHADOW then
        fontString:SetShadowColor(0, 0, 0, 1)
        fontString:SetShadowOffset(1, -1)
    else
        fontString:SetShadowOffset(0, 0)
    end
end

local function SetLineTextWidth(text, width)
    if not text then return end
    if text.SetWordWrap and text._yuiStatsWordWrapDisabled ~= true then
        text:SetWordWrap(false)
        text._yuiStatsWordWrapDisabled = true
    end
    SetWidthIfChanged(text, math.max(width or 1, 1))
end

local function NormalizeSafeWidth(width, fallback)
    local numericWidth = tonumber(width)
    if not numericWidth then
        numericWidth = tonumber(fallback)
    end
    if not numericWidth then
        return nil
    end
    return math.max(math.ceil(numericWidth), 0)
end

local function SafeFontStringWidth(fontString, fallback)
    fallback = NormalizeSafeWidth(fallback, SECRET_TEXT_FALLBACK_WIDTH) or SECRET_TEXT_FALLBACK_WIDTH
    if not fontString or not fontString.GetStringWidth then return fallback end
    local cachedWidth = tonumber(fontString._yuiStatsLastSafeWidth)
    if fontString._yuiStatsTextIsSecret then
        return math.max(cachedWidth or 0, fallback)
    end

    local ok, width = pcall(fontString.GetStringWidth, fontString)
    if not ok or IsSecretValue(width) then
        return math.max(cachedWidth or 0, fallback)
    end

    local numericWidth = tonumber(width)
    if not numericWidth then
        return math.max(cachedWidth or 0, fallback)
    end

    numericWidth = math.max(math.ceil(numericWidth), 0)
    fontString._yuiStatsLastSafeWidth = numericWidth
    return numericWidth
end

local function RecordSafeFontStringWidth(fontString, fallback)
    if not fontString or fontString._yuiStatsTextIsSecret or not fontString.GetStringWidth then return end
    local ok, width = pcall(fontString.GetStringWidth, fontString)
    if not ok or IsSecretValue(width) then
        return
    end
    local numericWidth = tonumber(width)
    if numericWidth then
        fontString._yuiStatsLastSafeWidth = math.max(math.ceil(numericWidth), 0)
    end
end

local function SafeFontStringHeight(fontString, fallback)
    fallback = math.max(tonumber(fallback) or DEFAULT_SIZE, 1)
    if not fontString or not fontString.GetStringHeight or fontString._yuiStatsTextIsSecret then
        return fallback
    end

    local ok, height = pcall(fontString.GetStringHeight, fontString)
    if not ok or IsSecretValue(height) then return fallback end
    return math.max(tonumber(height) or fallback, 1)
end

local function ResetVerticalLine(line, width)
    line:ClearAllPoints()
    SetWidthIfChanged(line, width)
    SetLineTextWidth(line.label, width - 10)
    SetLineTextWidth(line.value, width - 10)
    line.label:ClearAllPoints()
    line.value:ClearAllPoints()
    line.label:SetJustifyH("LEFT")
    line.value:SetJustifyH("RIGHT")
end

local function BeginHorizontalLayout(frame, columnSpacing)
    local content = frame.contentFrame or frame
    SetScaleIfChanged(content, 1)
    local layout = frame._yuiStatsHorizontalLayout
    if not layout then
        layout = {}
        frame._yuiStatsHorizontalLayout = layout
    end
    layout.content = content
    layout.x = 0
    layout.width = 0
    layout.rowHeight = 1
    layout.count = 0
    layout.columnSpacing = math.max(tonumber(columnSpacing) or DEFAULT_COLUMN_SPACING, 0)
    return layout
end

local function EstimateTextWidth(fontSize, charCount, minWidth)
    fontSize = tonumber(fontSize) or DEFAULT_SIZE
    charCount = tonumber(charCount) or 4
    minWidth = tonumber(minWidth) or SECRET_TEXT_FALLBACK_WIDTH
    return math.max(math.ceil(fontSize * 0.56 * charCount + 6), minWidth)
end

local function EstimatePercentValueWidth(fontSize, precision)
    precision = tonumber(precision) or DEFAULT_PRECISION
    if precision < 0 then precision = 0 end
    local charCount = precision > 0 and (5 + precision) or 4
    return EstimateTextWidth(fontSize, charCount, 30)
end

local function EstimateMoveSpeedValueWidth(fontSize, precision)
    precision = tonumber(precision) or 0
    if precision < 1 then precision = 1 end
    return math.max(EstimatePercentValueWidth(fontSize, precision), EstimateTextWidth(fontSize, 4, 30))
end

local function GetStatValueFallbackWidth(statId, fontSize, precision, isPercent, isString, isMain)
    if isString then
        return EstimateTextWidth(fontSize, 8, 72)
    end
    if isPercent then
        if statId == "movespeed" then
            return EstimateMoveSpeedValueWidth(fontSize, precision)
        end
        return EstimatePercentValueWidth(fontSize, precision)
    end
    if statId == "health" or statId == "mana" then
        return EstimateTextWidth(fontSize, 6, 40)
    end
    if isMain then
        return EstimateTextWidth(fontSize, 5, 38)
    end
    if statId == "ilvl" then
        return EstimateTextWidth(fontSize, 4, 32)
    end
    return EstimateTextWidth(fontSize, 4, 32)
end

local function PlaceHorizontalLine(line, layout, lineHeight, valueFallbackWidth)
    lineHeight = math.max(lineHeight or 1, 1)

    -- Remove the previous pass' constraints before measuring natural text width.
    -- Otherwise WoW can report the already-truncated width and keep the ellipsis.
    if line.label.SetWordWrap then line.label:SetWordWrap(false) end
    if line.value.SetWordWrap then line.value:SetWordWrap(false) end
    if line.label.SetWidth then line.label:SetWidth(0) end
    if line.value.SetWidth then line.value:SetWidth(0) end

    local labelWidth = SafeFontStringWidth(line.label, SECRET_TEXT_FALLBACK_WIDTH)
    local valueFallback = valueFallbackWidth or line._yuiStatsValueFallbackWidth or (line.value and line.value._yuiStatsValueFallbackWidth) or SECRET_TEXT_FALLBACK_WIDTH
    local valueWidth = SafeFontStringWidth(line.value, valueFallback)
    local labelSlotWidth = labelWidth + HORIZONTAL_TEXT_SAFETY_PADDING
    local valueSlotWidth = valueWidth + HORIZONTAL_TEXT_SAFETY_PADDING
    local lineWidth = labelSlotWidth + valueSlotWidth + HORIZONTAL_SIDE_PADDING * 2 + HORIZONTAL_TEXT_GAP
    lineWidth = math.max(lineWidth, 1)

    if layout.count > 0 then
        layout.x = layout.x + layout.columnSpacing
    end

    line:ClearAllPoints()
    line:SetPoint("LEFT", layout.content, "LEFT", layout.x, 0)
    SetSizeIfChanged(line, lineWidth, lineHeight)

    SetLineTextWidth(line.label, labelSlotWidth)
    SetLineTextWidth(line.value, valueSlotWidth)
    line.label:ClearAllPoints()
    line.value:ClearAllPoints()
    line.label:SetPoint("LEFT", HORIZONTAL_SIDE_PADDING, 0)
    line.label:SetJustifyH("LEFT")
    line.value:SetPoint("LEFT", line.label, "RIGHT", HORIZONTAL_TEXT_GAP, 0)
    line.value:SetJustifyH("LEFT")

    layout.x = layout.x + lineWidth
    layout.width = layout.x
    layout.rowHeight = math.max(layout.rowHeight, lineHeight)
    layout.count = layout.count + 1
end

local function ApplyStatsPanelGeometry(frame, settings, orientation, horizontalLayout, verticalHeight)
    local content = frame.contentFrame or frame
    content:ClearAllPoints()

    if orientation == PANEL_ORIENTATION_HORIZONTAL then
        local maxWidth = GetHorizontalMaxWidth(settings)
        local naturalWidth = math.max(horizontalLayout and horizontalLayout.width or 0, 1)
        local naturalHeight = math.max(horizontalLayout and horizontalLayout.rowHeight or 0, 1)
        local scale = math.min(1, maxWidth / naturalWidth)
        local alignment = NormalizeHorizontalAlignment(settings and settings.horizontalAlignment)

        SetScaleIfChanged(content, scale)
        SetSizeIfChanged(content, naturalWidth, naturalHeight)
        content:SetPoint(alignment, frame, alignment, 0, 0)
        SetSizeIfChanged(frame, maxWidth, math.max(naturalHeight * scale, 1))
    else
        local panelWidth = GetStatsPanelWidth(settings)
        local panelHeight = math.max(tonumber(verticalHeight) or 0, 1)
        SetScaleIfChanged(content, 1)
        SetSizeIfChanged(content, panelWidth, panelHeight)
        content:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        SetSizeIfChanged(frame, panelWidth, panelHeight)
    end
end

local function YT(key, fallback, ...)
    local value = YBarL and YBarL[key]
    if not value or value == "" or value == key then value = fallback or key end
    if select("#", ...) > 0 then
        return string.format(value, ...)
    end
    return value
end

local function GetStatsPanelTitle()
    return YUI.F:GetGradientText(YT("stats.panel.title", "角色属性面板"), {0.84, 0.41, 1}, {0.64, 0.21, 0.93})
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

local function GetRoleContext()
    local role = "DAMAGER"
    local specIndex = nil

    if TalentAPI.GetSpecialization and TalentAPI.GetSpecializationInfo then
        specIndex = TalentAPI.GetSpecialization()
        if specIndex then
            local _, _, _, _, r = TalentAPI.GetSpecializationInfo(specIndex)
            role = r
        end
    end
    -- 经典版/其他版本的后备逻辑（如有需要）

    roleCtxCache.role = role
    roleCtxCache.isTank = (role == "TANK")
    roleCtxCache.isHealer = (role == "HEALER")
    roleCtxCache.isCaster = false -- Simplified for now, will improve
    roleCtxCache.isRanged = false

    -- 改进的施法者判断逻辑
    local _, classToken = UnitAPI.UnitClass("player")

    if classToken == "MAGE" or classToken == "WARLOCK" or classToken == "PRIEST" or classToken == "EVOKER" or (classToken == "DEMONHUNTER" and specIndex == 3) then
        roleCtxCache.isCaster = true
    elseif classToken == "DRUID" or classToken == "SHAMAN" or classToken == "PALADIN" then
        -- 检查主属性（智力 vs 力量/敏捷）
        local _, str = UnitStat("player", 1)
        local _, agi = UnitStat("player", 2)
        local _, int = UnitStat("player", 4)

        local isSecret = SecurityAPI.IsSecretValue(str) or SecurityAPI.IsSecretValue(agi) or SecurityAPI.IsSecretValue(int)

        if not isSecret then
            if (tonumber(int) or 0) > (tonumber(str) or 0) and (tonumber(int) or 0) > (tonumber(agi) or 0) then
                roleCtxCache.isCaster = true
            end
            roleCtxCache.lastIsCaster = roleCtxCache.isCaster
        else
            roleCtxCache.isCaster = roleCtxCache.lastIsCaster or false
        end
    end

    if classToken == "HUNTER" then
        roleCtxCache.isRanged = true
    end

    return roleCtxCache
end

local FOREVER_UNSUPPORTED_STATS = { mastery = true, versatility = true, leech = true, avoidance = true, speed = true, stagger = true }
local function IsStatAvailable(statId)
    if YUI.IsForever and FOREVER_UNSUPPORTED_STATS[statId] then return false end
    -- 简化的可用性检查
    if statId == "versatility" and IS_CLASSIC then return false end
    if statId == "mastery" and IS_CLASSIC then return false end
    return true
end

local function IsDefenseStat(statId)
    return (YUI.IsForever and statId == "armor") or statId == "dodge" or statId == "parry" or statId == "block" or statId == "stagger"
end

local function GetDefenseMode(settings)
    if settings and settings.defenseMode then
        return settings.defenseMode
    end
    if YUI.IsWrath and settings then
        return settings.otherMode or "ALWAYS"
    end
    return "ALWAYS"
end

local function GetMaxLevel()
    if YUI.IsRetail then return 90 end
    if YUI.IsWrath then return 80 end
    if YUI.IsMists then return 90 end
    return 60
end

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

local DEFAULT_STAT_COLORS = {
    -- 基础属性
    str = {1.00, 0.20, 0.20},  -- 力量: 红色
    agi = {0.20, 1.00, 0.20},  -- 敏捷: 绿色
    int = {0.20, 0.60, 1.00},  -- 智力: 蓝色
    sta = {1.00, 1.00, 1.00},  -- 耐力: 白色
    spirit = {0.40, 1.00, 0.80}, -- 精神: 亮青色

    -- 绿字属性
    crit = {1.00, 0.50, 0.00}, -- 爆击: 橙色 (火)
    haste = {1.00, 1.00, 0.00}, -- 急速: 黄色 (雷)
    mastery = {0.80, 0.40, 0.80}, -- 精通: 紫色 (奥术)
    versatility = {0.53, 0.53, 0.93}, -- 全能: 紫色 (通用)

    -- 防御属性
    armor = {0.80, 0.60, 0.40}, -- 护甲: 棕色
    dodge = {0.40, 0.80, 1.00}, -- 躲闪: 浅蓝
    parry = {1.00, 0.30, 0.30}, -- 招架: 浅红
    block = {0.60, 0.40, 0.80}, -- 格挡: 深紫
    stagger = {0.00, 1.00, 0.60}, -- 醉拳: 武僧绿

    -- 特殊属性
    leech = {0.20, 0.80, 0.20}, -- 吸血: 深绿 (生命)
    avoidance = {0.40, 0.80, 0.80}, -- 闪避: 青色
    speed = {0.88, 0.88, 0.88}, -- 加速: 白色
    movespeed = {1, 1, 1}, -- 移速: 青色
    manaregen = {0.20, 0.60, 1.00}, -- 法回: 蓝色

    -- 其他
    ilvl = {0.64, 0.21, 0.93}, -- 装等: 史诗品质 (紫色 #a335ee)
    hit = {0.50, 0.50, 0.50},
    spellhit = {0.50, 0.50, 0.50},
    attackpower = {1.00, 0.20, 0.20},
    spellpower = {0.80, 0.50, 1.00},
    attack_power = {1.00, 0.20, 0.20},
    ranged_attack_power = {1.00, 0.20, 0.20},
    spell_power = {0.80, 0.50, 1.00},
}

local function GetStatColor(statId)
    local color = DEFAULT_STAT_COLORS[statId]
    if color then
        return color[1], color[2], color[3]
    end
    return 1, 1, 1
end

local function ColorText(text, r, g, b)
    local function toByte(value)
        value = tonumber(value) or 1
        if value < 0 then value = 0 elseif value > 1 then value = 1 end
        return math.floor(value * 255 + 0.5)
    end

    return string.format("|cff%02x%02x%02x%s|r", toByte(r), toByte(g), toByte(b), text or "")
end

local function SetFontCached(fontString, fontPath, fontSize, fontFlag)
    if not fontString then return end
    if fontString._yuiStatsFontPath == fontPath and fontString._yuiStatsFontSize == fontSize and fontString._yuiStatsFontFlag == fontFlag then
        if fontString.GetFont then
            local currentFont, currentSize, currentFlag = fontString:GetFont()
            if currentFont == fontPath and tonumber(currentSize) == tonumber(fontSize) and (currentFlag or "") == (fontFlag or "") then
                return
            end
        else
            return
        end
    end

    fontString:SetFont(fontPath, fontSize, fontFlag)
    fontString._yuiStatsFontPath = fontPath
    fontString._yuiStatsFontSize = fontSize
    fontString._yuiStatsFontFlag = fontFlag
end

local function ApplyStatsFont(fontString, fontPath, fontSize, fontEffect)
    SetFontCached(fontString, fontPath, fontSize, GetFontFlagForEffect(fontEffect))
    ApplyFontEffect(fontString, fontEffect)
end

local function NormalizeFontValue(font, lsm)
    local fallback = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    if lsm and type(lsm.Fetch) == "function" then
        local defaultPath = lsm:Fetch("font", DEFAULT_FONT, true)
        if type(defaultPath) == "string" and defaultPath ~= "" then
            fallback = defaultPath
        end
        if type(font) == "string" and font ~= "" then
            if font:find("\\", 1, true) or font:find("/", 1, true) then
                return font
            end
            local resolved = lsm:Fetch("font", font, true)
            if type(resolved) == "string" and resolved ~= "" then
                return resolved
            end
        end
    elseif type(font) == "string" and font ~= "" then
        return font
    end
    return fallback
end

local function SetTextColorCached(fontString, r, g, b, a)
    if not fontString then return end
    a = a or 1
    if fontString._yuiStatsColorR == r and fontString._yuiStatsColorG == g and fontString._yuiStatsColorB == b and fontString._yuiStatsColorA == a then
        return
    end

    fontString:SetTextColor(r, g, b, a)
    fontString._yuiStatsColorR = r
    fontString._yuiStatsColorG = g
    fontString._yuiStatsColorB = b
    fontString._yuiStatsColorA = a
end

local function ApplyStatColorStyle(line, style, r, g, b)
    style = NormalizeColorStyle(style)
    r, g, b = r or 1, g or 1, b or 1

    local labelColored = style == COLOR_STYLE_LABEL_COLORED or style == COLOR_STYLE_BOTH_COLORED
    local valueColored = style == COLOR_STYLE_VALUE_COLORED or style == COLOR_STYLE_BOTH_COLORED

    if labelColored then
        SetTextColorCached(line.label, r, g, b)
    else
        SetTextColorCached(line.label, 1, 1, 1)
    end

    if valueColored then
        SetTextColorCached(line.value, r, g, b)
    else
        SetTextColorCached(line.value, 1, 1, 1)
    end
end

local function SetTextIfChanged(fontString, text, fallbackWidth)
    if not fontString then return end
    if fallbackWidth then
        fontString._yuiStatsValueFallbackWidth = NormalizeSafeWidth(fallbackWidth, SECRET_TEXT_FALLBACK_WIDTH)
    end

    text = text or ""
    if IsSecretValue(text) then
        fontString._yuiStatsTextIsSecret = true
        fontString:SetText(text)
        return
    end

    local currentText = nil
    if not fontString._yuiStatsTextIsSecret then
        currentText = fontString:GetText()
    end
    if fontString._yuiStatsTextIsSecret or IsSecretValue(currentText) or currentText ~= text then
        fontString:SetText(text)
    end
    fontString._yuiStatsTextIsSecret = false
    RecordSafeFontStringWidth(fontString, fallbackWidth)
end

local function SetSecretFormattedText(fontString, formatString, valueCount, firstValue, secondValue, thirdValue)
    if not fontString or not fontString.SetFormattedText then return end
    -- SimpleFontString:SetFormattedText is the native secret-text sink. Keep secret
    -- values out of Lua comparison, arithmetic, tostring, and string.format.
    fontString._yuiStatsTextIsSecret = true
    if valueCount == 3 then
        fontString:SetFormattedText(formatString, firstValue, secondValue, thirdValue)
    elseif valueCount == 2 then
        fontString:SetFormattedText(formatString, firstValue, secondValue)
    else
        fontString:SetFormattedText(formatString, firstValue)
    end
end

-- Convert restricted yards/second inside the native formatter, not in Lua.
-- One decimal, truncated with trailing zeros omitted. The tiny divisor adjustment
-- keeps exact boundaries such as 7 yd/s from becoming 99.9% through float error.
local SECRET_MOVEMENT_SPEED_OPTIONS = {
    breakpointData = {
        {
            breakpoint = 0,
            abbreviation = "%",
            abbreviationIsGlobal = false,
            significandDivisor = 7 / 1000 / (1 + 1e-11),
            fractionDivisor = 10,
        },
    },
}

local function SetSecretMovementSpeedText(fontString, yardsPerSec)
    fontString._yuiStatsTextIsSecret = true
    fontString:SetText(AbbreviateNumbers(yardsPerSec, SECRET_MOVEMENT_SPEED_OPTIONS))
end

local function SetVersatilitySecretText(
    fontString,
    precision,
    displayMode,
    ratingBonus,
    directBonus,
    secondaryRating,
    secondaryRatingIsSecret,
    secondaryRatingPrefix,
    secondaryRatingFormat
)
    local singleFormat = VERSATILITY_SINGLE_FORMATS[precision] or VERSATILITY_SINGLE_FORMATS[DEFAULT_PRECISION]
    if secondaryRatingFormat and secondaryRatingFormat ~= "RATING_FIRST"
        and (secondaryRatingPrefix or secondaryRatingIsSecret) then
        if NormalizeVersatilityDisplayMode(displayMode) == VERSATILITY_DISPLAY_SPLIT then
            local splitFormat = VERSATILITY_SPLIT_FORMATS[precision] or VERSATILITY_SPLIT_FORMATS[DEFAULT_PRECISION]
            SetSecretFormattedText(fontString, GetSecondaryRatingFormat(splitFormat, secondaryRatingFormat),
                3, ratingBonus, directBonus, secondaryRating)
        else
            SetSecretFormattedText(fontString, GetSecondaryRatingFormat(singleFormat, secondaryRatingFormat),
                2, ratingBonus, secondaryRating)
        end
        return
    end
    if NormalizeVersatilityDisplayMode(displayMode) == VERSATILITY_DISPLAY_SPLIT then
        local splitFormat = VERSATILITY_SPLIT_FORMATS[precision] or VERSATILITY_SPLIT_FORMATS[DEFAULT_PRECISION]
        if secondaryRatingPrefix then
            SetSecretFormattedText(fontString, secondaryRatingPrefix .. splitFormat, 2, ratingBonus, directBonus)
        elseif secondaryRatingIsSecret then
            SetSecretFormattedText(
                fontString,
                SECONDARY_RATING_PREFIX_FORMAT .. splitFormat,
                3,
                secondaryRating,
                ratingBonus,
                directBonus
            )
        else
            SetSecretFormattedText(fontString, splitFormat, 2, ratingBonus, directBonus)
        end
    else
        if secondaryRatingPrefix then
            SetSecretFormattedText(fontString, secondaryRatingPrefix .. singleFormat, 1, ratingBonus)
        elseif secondaryRatingIsSecret then
            SetSecretFormattedText(
                fontString,
                SECONDARY_RATING_PREFIX_FORMAT .. singleFormat,
                2,
                secondaryRating,
                ratingBonus
            )
        else
            SetSecretFormattedText(fontString, singleFormat, 1, ratingBonus)
        end
    end
end

-- ============================================================================
--  时光服(Wrath) 数据获取逻辑
-- ============================================================================
local function GetTalentTabPoints(tab)
    if not TalentAPI.GetTalentTabInfo then return 0 end
    return select(5, TalentAPI.GetTalentTabInfo(tab)) or 0
end

local function GetWrathPlayAs()
    local _, tplayerClass = UnitAPI.UnitClass('player')
    local num1 = GetTalentTabPoints(1)
    local num2 = GetTalentTabPoints(2)
    local num3 = GetTalentTabPoints(3)

    local usetalent = 1
    if num1 > num2 and num1 > num3 then usetalent = 1
    elseif num2 > num1 and num2 > num3 then usetalent = 2
    elseif num3 > num1 and num3 > num2 then usetalent = 3
    end

    local PlayAs = 1
    if HasSpellIDBuff(48263) and tplayerClass == "DEATHKNIGHT" then
        PlayAs = 4
    else
        PlayAs = 1
    end

    if tplayerClass == "DRUID" then
        if usetalent == 1 then PlayAs = 2
        elseif usetalent == 3 then PlayAs = 3
        elseif usetalent == 2 and GetShapeshiftFormID() == 8 then PlayAs = 4
        else PlayAs = 1 end
    elseif tplayerClass == "PALADIN" then
        if usetalent == 1 then PlayAs = 3
        elseif usetalent == 2 then PlayAs = 14
        else PlayAs = 1 end
    elseif tplayerClass == "SHAMAN" then
        if usetalent == 1 then PlayAs = 2
        elseif usetalent == 2 then PlayAs = 6
        else PlayAs = 3 end
    elseif tplayerClass == "PRIEST" then
        if usetalent == 3 then PlayAs = 2 else PlayAs = 3 end
    elseif tplayerClass == "WARRIOR" then
        if GetShapeshiftFormID() == 18 then PlayAs = 4 else PlayAs = 1 end
    elseif tplayerClass == "ROGUE" then
        PlayAs = 1
    elseif tplayerClass == "HUNTER" then
        PlayAs = 5
    elseif tplayerClass == "MAGE" or tplayerClass == "WARLOCK" then
        PlayAs = 2
    end

    return PlayAs, tplayerClass
end

local wrathStatsCache = {}
for i = 1, MAX_STATS_LINES do
    wrathStatsCache[i] = { color = {} }
end
local wrathStatsCount = 0

local function GetWrathStatsData(playAs, tplayerClass, shouldAddStat)
    wrathStatsCount = 0
    local stats = wrathStatsCache

    local function ShouldAdd(id)
        return not shouldAddStat or shouldAddStat(id)
    end

    local function addStat(id, label, val, isPercent, isString, isMain, hexColor)
        if not ShouldAdd(id) then return end

        wrathStatsCount = wrathStatsCount + 1
        local r, g, b = HexToRGB(hexColor or "ffffff")
        local t = stats[wrathStatsCount]
        t.id = id
        t.label = label
        t.val = val
        t.isPercent = isPercent
        t.isString = isString
        t.isMain = isMain
        t.color[1], t.color[2], t.color[3] = r, g, b
    end

    if playAs == 1 then -- Melee DPS
        if ShouldAdd("main") then
            local base, posBuff, negBuff = UnitAttackPower("player")
            addStat("main", GetSL("attack_power"), base + posBuff + negBuff, false, false, true, "ff3333")
        end
        if ShouldAdd("haste") then
            addStat("haste", GetSL("haste"), GetCombatRatingBonus(CR_HASTE_MELEE) or 0, true, false, false, "ffffcc")
        end
        if ShouldAdd("crit") then
            addStat("crit", GetSL("crit"), GetCritChance() or 0, true, false, false, "ffffcc")
        end
        if ShouldAdd("hit") then
            local hm = GetHitModifier() or 0
            local crb = GetCombatRatingBonus(CR_HIT_MELEE) or 0
            addStat("hit", GetSL("hit"), hm + crb, true, false, false, "ffffcc")
        end
        if ShouldAdd("arp") then
            addStat("arp", GetSL("arp"), GetArmorPenetration() or 0, true, false, false, "ffffcc")
        end
        if ShouldAdd("expertise") then
            addStat("expertise", GetSL("expertise"), GetExpertise() or 0, false, false, false, "ffffcc")
        end
        if ShouldAdd("speed") then
            local mainSpeed, offSpeed = UnitAttackSpeed("player")
            local speedStr = offSpeed and format("%.2f/%.2f", mainSpeed, offSpeed) or format("%.2f", mainSpeed)
            addStat("speed", GetSL("attack_speed"), speedStr, false, true, false, "ffff66")
        end

    elseif playAs == 2 then -- Cast DPS
        if ShouldAdd("main") then
            local SpellDamageFire = GetSpellBonusDamage(3) or 0
            local SpellDamageNature = GetSpellBonusDamage(4) or 0
            local SpellDamageFrost = GetSpellBonusDamage(5) or 0
            local SpellDamageShadow = GetSpellBonusDamage(6) or 0
            local SpellDamageArcane = GetSpellBonusDamage(7) or 0
            local SpellDamage = math.max(SpellDamageFire, SpellDamageNature, SpellDamageFrost, SpellDamageShadow, SpellDamageArcane)

            local spellSuffix = GetSL("spell_power")
            if SpellDamageFire == SpellDamageNature and SpellDamageNature == SpellDamageFrost and SpellDamageFrost == SpellDamageShadow and SpellDamageShadow == SpellDamageArcane then
                spellSuffix = GetSL("spell_power")
            elseif SpellDamage == SpellDamageFire then spellSuffix = GetSL("spell_fire")
            elseif SpellDamage == SpellDamageNature then spellSuffix = GetSL("spell_nature")
            elseif SpellDamage == SpellDamageFrost then spellSuffix = GetSL("spell_frost")
            elseif SpellDamage == SpellDamageShadow then spellSuffix = GetSL("spell_shadow")
            elseif SpellDamage == SpellDamageArcane then spellSuffix = GetSL("spell_arcane")
            end

            addStat("main", spellSuffix, SpellDamage, false, false, true, "ff3333")
        end
        if ShouldAdd("haste") then
            addStat("haste", GetSL("haste"), GetCombatRatingBonus(CR_HASTE_SPELL) or 0, true, false, false, "ffff66")
        end
        if ShouldAdd("crit") then
            addStat("crit", GetSL("crit"), GetSpellCritChance(7) or 0, true, false, false, "ffff66")
        end
        if ShouldAdd("hit") then
            local spellHit = (GetCombatRatingBonus(CR_HIT_SPELL) or 0)
            if HasSpellIDBuff(6562) or HasSpellIDBuff(28878) then spellHit = spellHit + 1 end
            addStat("hit", GetSL("hit"), spellHit, true, false, false, "ffff66")
        end
        if ShouldAdd("manaregen") then
            local baseRegen, castingRegen = GetManaRegen()
            local regenStr = format("%d/%d", (baseRegen or 0) * 5, (castingRegen or 0) * 5)
            addStat("manaregen", GetSL("manaregen"), regenStr, false, true, false, "0066cc")
        end
        -- addStat("health", "血量", UnitHealthMax("player") or 0, false, false, false, "ffff33")

    elseif playAs == 3 then -- Healer
        if ShouldAdd("main") then
            addStat("main", GetSL("healing_power"), GetSpellBonusHealing() or 0, false, false, true, "00ff00")
        end
        if ShouldAdd("haste") then
            addStat("haste", GetSL("haste"), GetCombatRatingBonus(CR_HASTE_SPELL) or 0, true, false, false, "ffff33")
        end
        if ShouldAdd("crit") then
            addStat("crit", GetSL("crit"), GetSpellCritChance(2) or 0, true, false, false, "ffffcc")
        end
        if ShouldAdd("hit") then
            local spellHit = (GetCombatRatingBonus(CR_HIT_SPELL) or 0)
            if HasSpellIDBuff(6562) or HasSpellIDBuff(28878) then spellHit = spellHit + 1 end
            addStat("hit", GetSL("hit"), spellHit, true, false, false, "ffff66")
        end
        if ShouldAdd("manaregen") then
            local baseRegen, castingRegen = GetManaRegen()
            local regenStr = format("%d/%d", (baseRegen or 0) * 5, (castingRegen or 0) * 5)
            addStat("manaregen", GetSL("manaregen"), regenStr, false, true, false, "0066cc")
        end
        if ShouldAdd("mana") then
            addStat("mana", GetSL("mana"), UnitPowerMax("player") or 0, false, false, false, "ffff33")
        end

    elseif playAs == 4 then -- Tank
        if ShouldAdd("main") then
            local _, effectiveArmor = UnitArmor("player")
            addStat("main", GetSL("armor"), effectiveArmor or 0, false, false, true, "0066cc")
        end
        if ShouldAdd("dodge") then
            addStat("dodge", GetSL("dodge"), GetDodgeChance() or 0, true, false, false, "ffffcc")
        end

        if ShouldAdd("parry") or ShouldAdd("ap") then
            local parry = GetParryChance() or 0
            if parry ~= 0 then
                addStat("parry", GetSL("parry"), parry, true, false, false, "cc99cc")
            elseif ShouldAdd("ap") then
                local base, posBuff, negBuff = UnitAttackPower("player")
                addStat("ap", GetSL("attack_power"), base + posBuff + negBuff, false, false, false, "ff3333")
            end
        end

        if ShouldAdd("block") or ShouldAdd("speed") or ShouldAdd("ap2") then
            local block = GetBlockChance() or 0
            if block ~= 0 then
                addStat("block", GetSL("block"), block, true, false, false, "ffff33")
            elseif tplayerClass == "DRUID" then
                if ShouldAdd("speed") then
                    addStat("speed", GetSL("attack_speed"), UnitAttackSpeed("player") or 0, false, false, false, "ffff66")
                end
            elseif ShouldAdd("ap2") then
                local base, posBuff, negBuff = UnitAttackPower("player")
                addStat("ap2", GetSL("attack_power"), base + posBuff + negBuff, false, false, false, "ff3333")
            end
        end

        if ShouldAdd("hit") then
            local hm = GetHitModifier() or 0
            local crb = GetCombatRatingBonus(CR_HIT_MELEE) or 0
            addStat("hit", GetSL("hit"), hm + crb, true, false, false, "ffffcc")
        end
        if ShouldAdd("expertise") then
            addStat("expertise", GetSL("expertise"), GetExpertise() or 0, false, false, false, "ffffcc")
        end
        if ShouldAdd("health") then
            addStat("health", GetSL("health"), UnitHealthMax("player") or 0, false, false, false, "ffff33")
        end

    elseif playAs == 14 then -- FQ
        if ShouldAdd("main") then
            local _, effectiveArmor = UnitArmor("player")
            local base, posBuff, negBuff = UnitAttackPower("player")
            local effective = base + posBuff + negBuff
            addStat("main", GetSL("armor_attack"), (effectiveArmor or 0).."/"..effective, false, true, true, "0066cc")
        end
        if ShouldAdd("dodge") then
            addStat("dodge", GetSL("dodge"), GetDodgeChance() or 0, true, false, false, "ffffcc")
        end
        if ShouldAdd("parry") then
            addStat("parry", GetSL("parry"), GetParryChance() or 0, true, false, false, "cc99cc")
        end
        if ShouldAdd("block") then
            addStat("block", GetSL("block"), GetBlockChance() or 0, true, false, false, "ffff33")
        end
        if ShouldAdd("hit") then
            local hm = GetHitModifier() or 0
            local crb = GetCombatRatingBonus(CR_HIT_MELEE) or 0
            addStat("hit", GetSL("hit"), hm + crb, true, false, false, "ffffcc")
        end
        if ShouldAdd("expertise") then
            addStat("expertise", GetSL("expertise"), GetExpertise() or 0, false, false, false, "ffffcc")
        end
        if ShouldAdd("health") then
            addStat("health", GetSL("health"), UnitHealthMax("player") or 0, false, false, false, "ffff33")
        end

    elseif playAs == 5 then -- Hunter
        if ShouldAdd("main") then
            local base, posBuff, negBuff = UnitRangedAttackPower("player")
            addStat("main", GetSL("attack_power"), base + posBuff + negBuff, false, false, true, "ff3333")
        end
        if ShouldAdd("haste") then
            addStat("haste", GetSL("haste"), GetCombatRatingBonus(CR_HASTE_RANGED) or 0, true, false, false, "ffffcc")
        end
        if ShouldAdd("crit") then
            addStat("crit", GetSL("crit"), GetRangedCritChance() or 0, true, false, false, "ffffcc")
        end
        if ShouldAdd("hit") then
            local hmr = GetHitModifier() or 0
            local crbr = GetCombatRatingBonus(CR_HIT_RANGED) or 0
            addStat("hit", GetSL("hit"), hmr + crbr, true, false, false, "ffffcc")
        end
        if ShouldAdd("arp") then
            addStat("arp", GetSL("arp"), GetArmorPenetration() or 0, true, false, false, "ffffcc")
        end
        if ShouldAdd("speed") then
            addStat("speed", GetSL("attack_speed"), UnitRangedDamage("player") or 0, false, false, false, "ffff66")
        end

    elseif playAs == 6 then -- Enhance Shaman
        if ShouldAdd("main") then
            local base, posBuff, negBuff = UnitAttackPower("player")
            local effective = base + posBuff + negBuff
            local SpellDamageFire = GetSpellBonusDamage(3) or 0
            local SpellDamageNature = GetSpellBonusDamage(4) or 0
            local SpellDamageFrost = GetSpellBonusDamage(5) or 0
            local SpellDamageShadow = GetSpellBonusDamage(6) or 0
            local SpellDamageArcane = GetSpellBonusDamage(7) or 0
            local SpellDamage = math.max(SpellDamageFire, SpellDamageNature, SpellDamageFrost, SpellDamageShadow, SpellDamageArcane)
            addStat("main", GetSL("attack_spell"), effective.."/"..SpellDamage, false, true, true, "ff3333")
        end
        if ShouldAdd("haste") then
            addStat("haste", GetSL("haste"), GetCombatRatingBonus(CR_HASTE_MELEE) or 0, true, false, false, "ffffcc")
        end
        if ShouldAdd("crit") then
            addStat("crit", GetSL("crit"), GetCritChance() or 0, true, false, false, "ffffcc")
        end
        if ShouldAdd("hit") then
            local spellHit = (GetCombatRatingBonus(CR_HIT_SPELL) or 0)
            if HasSpellIDBuff(6562) or HasSpellIDBuff(28878) then spellHit = spellHit + 1 end
            addStat("hit", GetSL("hit"), spellHit, true, false, false, "ffff66")
        end
        if ShouldAdd("arp") then
            addStat("arp", GetSL("arp"), GetArmorPenetration() or 0, true, false, false, "ffffcc")
        end
        if ShouldAdd("expertise") then
            addStat("expertise", GetSL("expertise"), GetExpertise() or 0, false, false, false, "ffffcc")
        end
        if ShouldAdd("speed") then
            local mainSpeed, offSpeed = UnitAttackSpeed("player")
            local speedStr = offSpeed and format("%.2f/%.2f", mainSpeed, offSpeed) or format("%.2f", mainSpeed)
            addStat("speed", GetSL("attack_speed"), speedStr, false, true, false, "ffff66")
        end
    end

    if ShouldAdd("ilvl") then
        local _, equipped = GetAverageItemLevel()
        if equipped and equipped > 0 then
            addStat("ilvl", GetSL("ilvl"), math.floor(equipped), false, false, false, "a335ee")
        end
    end
    if ShouldAdd("movespeed") then
        local MSpercent = math.floor(YUI.F:SafeNum(GetUnitSpeed("player"), 0) / 7 * 100 + 0.5)
        addStat("movespeed", GetSL("movespeed"), MSpercent, true, false, false, "00ffff")
    end

    return stats, wrathStatsCount
end

-- ============================================================================
--  属性定义
-- ============================================================================
local function ReadRetailSharedStat(statID, fallback)
    if YUI.IsForever then
        return PaperDollAPI and PaperDollAPI.ReadStat and PaperDollAPI.ReadStat(statID, "player") or nil
    end
    if YUI.IsRetail and PaperDollAPI and type(PaperDollAPI.ReadStat) == "function" then
        local value = PaperDollAPI.ReadStat(statID, "player")
        if value ~= nil then
            return value
        end
    end

    return fallback()
end

local STAT_DEFS = {
    ilvl = {
        labelKey = "ilvl",
        api = function()
            return ReadRetailSharedStat("ilvl", function()
                local overall, equipped = GetAverageItemLevel()
                local val = YUI.F:SafeNum(equipped or overall, 0)
                local isSecret = SecurityAPI.IsSecretValue(val)
                if isSecret then return val end
                return math.floor(val)
            end)
        end,
    },
    str = {
        labelKey = "str",
        category = "primary",
        api = function()
            return ReadRetailSharedStat("str", function()
                local _, s = UnitStat("player", 1)
                return s or 0
            end)
        end,
    },
    agi = {
        labelKey = "agi",
        category = "primary",
        api = function()
            return ReadRetailSharedStat("agi", function()
                local _, s = UnitStat("player", 2)
                return s or 0
            end)
        end,
    },
    int = {
        labelKey = "int",
        category = "primary",
        api = function()
            return ReadRetailSharedStat("int", function()
                local _, s = UnitStat("player", 4)
                return s or 0
            end)
        end,
    },
    sta = {
        labelKey = "sta",
        category = "primary",
        api = function()
            return ReadRetailSharedStat("sta", function()
                local _, s = UnitStat("player", 3)
                return s or 0
            end)
        end,
    },
    crit = {
        labelKey = "crit",
        percent = true,
        api = function()
            return ReadRetailSharedStat("crit", function() return GetCritChance() or 0 end)
        end,
    },
    haste = {
        labelKey = "haste",
        percent = true,
        api = function()
            return ReadRetailSharedStat("haste", function()
                if GetHaste then return GetHaste() or 0 end
                return UnitSpellHaste and UnitSpellHaste("player") or 0
            end)
        end,
    },
    mastery = {
        labelKey = "mastery",
        percent = true,
        api = function()
            return ReadRetailSharedStat("mastery", function() return GetMasteryEffect() or 0 end)
        end,
    },
    versatility = {
        labelKey = "versatility",
        percent = true,
        api = function()
            return ReadRetailSharedStat("versatility", function()
                local bonus1 = YUI.F:SafeNum(GetCombatRatingBonus(CR_VERSATILITY), 0)
                local bonus2 = YUI.F:SafeNum(GetVersatilityBonus and GetVersatilityBonus(CR_VERSATILITY) or 0, 0)
                local isSecret1 = SecurityAPI.IsSecretValue(bonus1)
                local isSecret2 = SecurityAPI.IsSecretValue(bonus2)
                if isSecret1 or isSecret2 then
                    return { isSecretCombo = true, v1 = bonus1, v2 = bonus2 }
                else
                    return bonus1 + bonus2
                end
            end)
        end,
    },
    leech = {
        labelKey = "leech",
        percent = true,
        api = function()
            return ReadRetailSharedStat("leech", function() return GetLifesteal and GetLifesteal() or 0 end)
        end,
    },
    avoidance = {
        labelKey = "avoidance",
        percent = true,
        api = function()
            return ReadRetailSharedStat("avoidance", function() return GetAvoidance and GetAvoidance() or 0 end)
        end,
    },
    speed = {
        labelKey = "speed",
        percent = true,
        api = function()
            return ReadRetailSharedStat("speed", function() return GetSpeed and GetSpeed() or 0 end)
        end,
    },
    movespeed = {
        labelKey = "movespeed",
        percent = true,
        api = function()
            if YUI.IsForever then
                if type(GetUnitSpeed) ~= "function" then return nil end
                local ok, value = pcall(GetUnitSpeed, "player")
                if not ok then return nil end
                if IsSecretValue(value) then return { isSecretSpeed = true, val = value } end
                if type(value) ~= "number" then return nil end
                return value / 7 * 100
            end
            local yardsPerSec = 0

            -- 1. 优先检查滑翔/驭龙术速度
            if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
                local isGliding, _, flightSpeed = C_PlayerInfo.GetGlidingInfo()
                if isGliding and type(flightSpeed) == "number" then
                    yardsPerSec = flightSpeed
                end
            end

            -- 2. 若未滑翔，使用标准 API
            if yardsPerSec == 0 and GetUnitSpeed then
                -- 检查是否在载具中
                local unit = (UnitInVehicle and UnitInVehicle("player")) and "vehicle" or "player"
                yardsPerSec = YUI.F:SafeNum(GetUnitSpeed(unit), 0)
            end

            local isSecret = SecurityAPI.IsSecretValue(yardsPerSec)
            if isSecret then
                return { isSecretSpeed = true, val = yardsPerSec }
            end

            -- 3. 基于基础跑速 (7码/秒) 计算百分比
            return (yardsPerSec / 7) * 100
        end,
    },
    dodge = {
        labelKey = "dodge",
        percent = true,
        api = function()
            return ReadRetailSharedStat("dodge", function() return GetDodgeChance() or 0 end)
        end,
    },
    parry = {
        labelKey = "parry",
        percent = true,
        api = function()
            return ReadRetailSharedStat("parry", function() return GetParryChance() or 0 end)
        end,
    },
    block = {
        labelKey = "block",
        percent = true,
        api = function()
            return ReadRetailSharedStat("block", function() return GetBlockChance() or 0 end)
        end,
    },
    stagger = {
        labelKey = "stagger",
        percent = true,
        api = function()
            return ReadRetailSharedStat("stagger", function()
                local _, classToken = UnitAPI.UnitClass("player")
                if classToken ~= "MONK" then return 0 end
                if C_PaperDollInfo and C_PaperDollInfo.GetStaggerPercentage then
                    return YUI.F:SafeNum(C_PaperDollInfo.GetStaggerPercentage("player"), 0)
                end
                if UnitStagger and UnitHealthMax then
                    local s = YUI.F:SafeNum(UnitStagger("player"), 0)
                    local m = YUI.F:SafeNum(UnitHealthMax("player"), 1)
                    local isSecret = SecurityAPI.IsSecretValue(s) or SecurityAPI.IsSecretValue(m)
                    if isSecret then return s end
                    if s and m and m > 0 then return (s / m) * 100 end
                end
                return 0
            end)
        end,
    },
}

-- 经典版特定调整
if IS_CLASSIC and not YUI.IsForever then
    STAT_DEFS.haste.api = function() return GetHaste and GetHaste() or 0 end
    -- 如有需要添加更多经典版属性
end

if YUI.IsForever then
    for _, id in ipairs({ "spirit", "hit", "expertise", "armor", "attack_power", "spell_power", "manaregen" }) do
        local statID = id
        STAT_DEFS[statID] = {
            labelKey = statID,
            percent = statID == "hit" or statID == "expertise",
            api = function() return ReadRetailSharedStat(statID) end,
        }
    end
end

local statDefLabelLocale

local function GetActiveLocaleKey()
    local Locale = YUI.Locale
    if Locale and Locale.Current then
        return Locale:Current()
    end
    return GetLocale and GetLocale() or "enUS"
end

local function RefreshStatDefLabels()
    local locale = GetActiveLocaleKey()
    if statDefLabelLocale == locale then
        return
    end

    for id, def in pairs(STAT_DEFS) do
        if def then
            def.label = GetSL(def.labelKey or id)
        end
    end
    statDefLabelLocale = locale
end

-- ============================================================================
--  模块逻辑
-- ============================================================================

local function IsUnsetFramePosition(pos)
    if type(pos) ~= "table" then
        return true
    end
    return (pos.point or "CENTER") == "CENTER" and (pos.x or 0) == 0 and (pos.y or 0) == 0
end

local function CopyConfigValue(value, seen)
    if type(value) ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return seen[value]
    end

    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[k] = CopyConfigValue(v, seen)
    end
    return copy
end

local function MaterializeConfigTable(parent, key)
    if type(parent) ~= "table" then
        return {}
    end

    local actual = rawget(parent, key)
    if type(actual) == "table" then
        return actual
    end

    actual = {}
    local inherited = parent[key]
    if type(inherited) == "table" then
        for k, v in pairs(inherited) do
            actual[k] = CopyConfigValue(v)
        end
    end
    parent[key] = actual
    return actual
end

local DEFAULT_CONFIG = {
    panelShown = true,
    font = DEFAULT_FONT,
    fontSize = DEFAULT_SIZE,
    panelWidth = DEFAULT_PANEL_WIDTH,
    spacing = DEFAULT_SPACING,
    columnSpacing = DEFAULT_COLUMN_SPACING,
    horizontalMaxWidth = DEFAULT_HORIZONTAL_MAX_WIDTH,
    horizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER,
    appearanceStyle = COLOR_STYLE_BOTH_COLORED,
    fontEffect = DEFAULT_FONT_EFFECT,
    panelOrientation = PANEL_ORIENTATION_VERTICAL,
    precision = DEFAULT_PRECISION,
    showSecondaryRating = false,
    versatilityDisplayMode = VERSATILITY_DISPLAY_SINGLE,
    speedUpdateFreq = DEFAULT_SPEED_UPDATE_FREQ,
    outOfCombatAlpha = 1,
    primaryMode = "ALWAYS",
    secondaryMode = "ALWAYS",
    defenseMode = "ALWAYS",
    otherMode = "HOVER",
    speedMode = "NEVER",
    ilvlMode = "HOVER",
    wrathMainScale = 2,
    wrathOtherScale = 1.2,
}

local PANEL_CONFIG_KEYS = {
    "framePosition",
    "font",
    "fontSize",
    "panelWidth",
    "spacing",
    "columnSpacing",
    "horizontalMaxWidth",
    "horizontalAlignment",
    "appearanceStyle",
    "fontEffect",
    "panelOrientation",
    "precision",
    "versatilityDisplayMode",
    "speedUpdateFreq",
    "outOfCombatAlpha",
    "primaryMode",
    "secondaryMode",
    "defenseMode",
    "otherMode",
    "speedMode",
    "ilvlMode",
    "wrathMainScale",
    "wrathOtherScale",
}

local function GetProductProfile()
    return YUI.DB and YUI.DB.GetProfile and YUI.DB:GetProfile(PRODUCT_ID) or nil
end

local function GetCurrentProfileName()
    local database = YUI.DB and YUI.DB.GetAceDB and YUI.DB:GetAceDB(PRODUCT_ID)
    return database and database.GetCurrentProfile and database:GetCurrentProfile() or "Default"
end

local function IsStatsOnBar(ybar)
    local modules = type(ybar) == "table" and ybar.modules
    if type(modules) ~= "table" then return true end
    for _, listName in ipairs({ "top", "bottom" }) do
        local list = modules[listName]
        if type(list) == "table" then
            for _, name in ipairs(list) do
                if name == "Stats" then return true end
            end
        end
    end
    return false
end

local function GetLegacyStatsPosition(profile)
    if type(profile) ~= "table" then return nil end
    if type(profile.StatsFramePosition) == "table" then
        return profile.StatsFramePosition
    end
    local database = YUI.DB and YUI.DB.GetAceDB and YUI.DB:GetAceDB(PRODUCT_ID)
    local store = database and database.sv and database.sv.ybarStatsFramePositions
    return type(store) == "table" and store[GetCurrentProfileName()] or nil
end

local function MigrateLegacyConfig(config, profile)
    if tonumber(config.migrationVersion) and config.migrationVersion >= MIGRATION_VERSION then
        return
    end

    if PRODUCT_ID == "suite" and type(profile) == "table" then
        local ybar = type(profile.YBar) == "table" and profile.YBar or nil
        local legacy = ybar and type(ybar.Stats) == "table" and ybar.Stats or nil
        if legacy then
            for _, key in ipairs(PANEL_CONFIG_KEYS) do
                if config[key] == nil and legacy[key] ~= nil then
                    config[key] = CopyConfigValue(legacy[key])
                end
            end
            if config.ilvlMode == nil and legacy.showIlvl ~= nil then
                config.ilvlMode = legacy.showIlvl == false and "NEVER" or "ALWAYS"
            end
        end

        local legacyPosition = GetLegacyStatsPosition(profile)
        if config.framePosition == nil and type(legacyPosition) == "table" then
            config.framePosition = CopyConfigValue(legacyPosition)
        end

        local legacyShown = profile.StatsPanelShown
        if legacyShown == nil and legacy then
            legacyShown = legacy.panelShown
        end
        if legacyShown == nil then legacyShown = true end
        local ybarEnabled = not ybar or ybar.enable ~= false
        config.panelShown = ybarEnabled and IsStatsOnBar(ybar) and legacyShown ~= false
    end

    config.migrationVersion = MIGRATION_VERSION
end

function Module:EnsureSettings()
    local profile = GetProductProfile()
    local store = Components:GetStore(PRODUCT_ID)
    if type(store) ~= "table" then
        self.settings = self.settings or CopyConfigValue(DEFAULT_CONFIG)
        return self.settings
    end
    if type(store[CONFIG_KEY]) ~= "table" then
        store[CONFIG_KEY] = {}
    end
    MigrateLegacyConfig(store[CONFIG_KEY], profile)
    self.settings = Components:EnsureConfig(CONFIG_KEY, DEFAULT_CONFIG, PRODUCT_ID) or store[CONFIG_KEY]
    self.settings.horizontalMaxWidth = GetHorizontalMaxWidth(self.settings)
    self.settings.horizontalAlignment = NormalizeHorizontalAlignment(self.settings.horizontalAlignment)
    self.settings.appearanceStyle = NormalizeColorStyle(self.settings.appearanceStyle)
    self.settings.fontEffect = NormalizeFontEffect(self.settings.fontEffect)
    if self.settings.panelOrientation ~= PANEL_ORIENTATION_HORIZONTAL then
        self.settings.panelOrientation = PANEL_ORIENTATION_VERTICAL
    end
    return self.settings
end

local function LegacyStatsPositionToPlacement(pos)
    if type(pos) ~= "table" or pos.userPlaced ~= true or IsUnsetFramePosition(pos) then
        return nil
    end
    local point = pos.point or "CENTER"
    return {
        anchor = {
            point = point,
            relative = "UIParent",
            relativePoint = pos.relativePoint or point,
        },
        offset = {
            x = pos.x or 0,
            y = pos.y or 0,
        },
    }
end

function Module:GetDefaultStatsPlacement()
    return {
        anchor = {
            point = DEFAULT_PANEL_POINT,
            relative = "UIParent",
            relativePoint = DEFAULT_PANEL_RELATIVE_POINT,
        },
        offset = { x = DEFAULT_PANEL_OFFSET_X, y = DEFAULT_PANEL_OFFSET_Y },
    }
end

function Module:ApplyLegacyStatsFramePosition()
    if not self.statsFrame then return end
    local pos = self.settings and self.settings.framePosition
    self.statsFrame:ClearAllPoints()
    if type(pos) == "table" and pos.userPlaced == true then
        self.statsFrame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or pos.point or "CENTER", pos.x or 0, pos.y or 0)
    else
        self.statsFrame:SetPoint(
            DEFAULT_PANEL_POINT,
            UIParent,
            DEFAULT_PANEL_RELATIVE_POINT,
            DEFAULT_PANEL_OFFSET_X,
            DEFAULT_PANEL_OFFSET_Y
        )
    end
end

function Module:GetStatsMoverBounds()
    local frame = self.statsFrame
    return GetStatsPanelWidth(self.settings), math.max(frame and frame:GetHeight() or 0, 1)
end

function Module:IsStatsLayoutEditing()
    local Layout = YUI.Layout
    return Layout and Layout.IsEditing and Layout:IsEditing() or false
end

function Module:RefreshStatsLayoutBounds(previousWidth, previousHeight)
    if not self:IsStatsLayoutEditing() then return end
    local frame = self.statsFrame
    if not frame then return end
    local width = frame:GetWidth() or 0
    local height = frame:GetHeight() or 0
    if math.abs(width - (previousWidth or 0)) < 0.01 and math.abs(height - (previousHeight or 0)) < 0.01 then
        return
    end
    if YUI.Layout.RefreshFrame then
        YUI.Layout:RefreshFrame(STATS_LAYOUT_ID)
    end
end

function Module:RegisterStatsLayout()
    local frame = self.statsFrame
    local Layout = YUI.Layout
    if not frame or not (Layout and Layout.RegisterFrame) then
        self:ApplyLegacyStatsFramePosition()
        return false
    end

    local hadLayoutPlacement = Layout.HasPlacement and Layout:HasPlacement(STATS_LAYOUT_ID) or false
    local entry = Layout:RegisterFrame(STATS_LAYOUT_ID, {
        frame = frame,
        title = YT("stats.panel.title", "角色属性面板"),
        category = "component",
        defaultPlacement = function()
            return self:GetDefaultStatsPlacement()
        end,
        movable = true,
        snap = true,
        anchorTargets = { "UIParent" },
        combatProtected = false,
        exactMoverBounds = true,
        getMoverBounds = function()
            return self:GetStatsMoverBounds()
        end,
        isEnabled = function()
            return self.enabled == true
        end,
        onEnterEditMode = function()
            self.layoutPreviewing = true
            if self.enabled then
                self:EnsureRuntime()
                self.statsFrame:Show()
                self:UpdateStatsPanel()
            end
        end,
        onExitEditMode = function()
            self.layoutPreviewing = false
            self:UpdateVisibility()
        end,
        openPluginSettings = function()
            if YUI.Settings and YUI.Settings.OpenComponentFeature then
                YUI.Settings:OpenComponentFeature(FEATURE_KEY)
            end
        end,
    })
    if not entry then return false end

    local legacyPlacement = LegacyStatsPositionToPlacement(self.settings and self.settings.framePosition)
    if legacyPlacement and not hadLayoutPlacement and Layout.SetPlacement then
        Layout:SetPlacement(STATS_LAYOUT_ID, legacyPlacement, true)
    end
    return true
end

function Module:IsRuntimeActive()
    return self.enabled == true
end

function Module:StopSpeedTicker()
    if self.speedTicker and self.speedTicker.Cancel then
        self.speedTicker:Cancel()
    end
    self.speedTicker = nil
    self.speedTickerInterval = nil
end

local function SpeedTickerCallback()
    local cpuWatchdog = YUI.CPUWatchdog
    local cpuStartedAt = cpuWatchdog and cpuWatchdog.timingActive and cpuWatchdog:BeginProbeTiming()
    if not Module:IsRuntimeActive() or not Module.statsFrame or not Module.statsFrame:IsShown() or not Module:UpdateSpeedLine() then
        Module:StopSpeedTicker()
    end
    if cpuStartedAt then cpuWatchdog:EndProbeTiming("component.character-stats-panel", cpuStartedAt) end
end

local cpuWatchdog = YUI.CPUWatchdog
if cpuWatchdog and cpuWatchdog.RegisterProbe then
    cpuWatchdog:RegisterProbe("component.character-stats-panel", {
        localeKey = "cpu_watch.probe.character_stats_panel",
        kind = "function",
        target = SpeedTickerCallback,
        snapshot = function()
            return {
                listeners = Module.dataListeners or 0,
                pendingRefresh = Module.pendingRefreshTimer ~= nil,
                speedTicker = Module.speedTicker ~= nil,
                panelShown = Module.statsFrame and Module.statsFrame:IsShown() or false,
            }
        end,
    })
end

function Module:GetSpeedUpdateInterval()
    local freq = self.settings and self.settings.speedUpdateFreq

    freq = tonumber(freq) or DEFAULT_SPEED_UPDATE_FREQ
    if freq < 0.1 then freq = 0.1 end
    return freq
end

function Module:UpdateSpeedLine()
    local f = self.statsFrame
    if not f or not f.speedLineValue or not f.speedFmtStr then
        return false
    end

    local def = STAT_DEFS.movespeed
    if not def or not def.api then
        return false
    end

    local rawVal = def.api()
    if IsSecretValue(rawVal) then
        SetSecretFormattedText(f.speedLineValue, f.speedFmtStr, 1, rawVal)
        return true
    end
    if type(rawVal) == "table" and rawVal.isSecretSpeed then
        SetSecretMovementSpeedText(f.speedLineValue, rawVal.val)
        return true
    end
    local val = YUI.F:SafeNum(rawVal, 0)
    local text = format(f.speedFmtStr, val)
    SetTextIfChanged(f.speedLineValue, text, f.speedLineValue._yuiStatsValueFallbackWidth)
    return true
end

function Module:RefreshSpeedTickerState()
    local f = self.statsFrame
    if not self:IsRuntimeActive() or not f or not f:IsShown() or not f.speedLineValue or not f.speedFmtStr then
        self:StopSpeedTicker()
        return
    end

    local interval = self:GetSpeedUpdateInterval()
    if self.speedTicker and self.speedTickerInterval == interval then
        return
    end

    self:StopSpeedTicker()
    self.speedTickerInterval = interval
    self:UpdateSpeedLine()

    if C_Timer and C_Timer.NewTicker then
        self.speedTicker = C_Timer.NewTicker(interval, SpeedTickerCallback)
    end
end

function Module:CancelPendingPanelRefresh()
    if self.pendingRefreshTimer and self.pendingRefreshTimer.Cancel then
        self.pendingRefreshTimer:Cancel()
    end
    self.pendingRefreshTimer = nil
end

function Module:RequestStatsPanelRefresh(immediate)
    local frame = self.statsFrame
    if not self.enabled or not frame or not frame:IsShown() then
        self:CancelPendingPanelRefresh()
        self:StopSpeedTicker()
        return
    end

    local now = CombatAPI.GetTime()
    local elapsed = now - (self.lastPanelRefreshAt or 0)
    if immediate or not (C_Timer and C_Timer.NewTimer) then
        self:CancelPendingPanelRefresh()
        self.lastPanelRefreshAt = now
        self:UpdateStatsPanel()
        return
    end
    if self.pendingRefreshTimer then return end

    -- Defer event reads until after dispatch, even when the throttle has elapsed.
    -- Aura notifications can precede the corresponding derived stat update.
    self.pendingRefreshTimer = C_Timer.NewTimer(math.max(0, PANEL_REFRESH_INTERVAL - elapsed), function()
        self.pendingRefreshTimer = nil
        if not self.enabled or not self.statsFrame or not self.statsFrame:IsShown() then
            self:StopSpeedTicker()
            return
        end
        self.lastPanelRefreshAt = CombatAPI.GetTime()
        self:UpdateStatsPanel()
    end)
end

function Module:OnDataEvent()
    self:RequestStatsPanelRefresh(false)
end

function Module:DetachDataEvents()
    if YUI.Event then
        YUI.Event:OffOwner(self.dataOwner)
    end
    self.dataListeners = 0
end

function Module:AttachDataEvents()
    if not (self.enabled and self.statsFrame and self.statsFrame:IsShown() and YUI.Event) then
        self:DetachDataEvents()
        return
    end

    self:DetachDataEvents()
    local function On(event, options)
        YUI.Event:On(event, "OnDataEvent", self.dataOwner, options)
        self.dataListeners = self.dataListeners + 1
    end
    On("YUI_WORLD_READY")
    On("PLAYER_LEVEL_UP")
    On("PLAYER_AVG_ITEM_LEVEL_UPDATE")
    On("UNIT_INVENTORY_CHANGED", PLAYER_UNIT_FILTER)
    On("UNIT_STATS", PLAYER_UNIT_FILTER)
    On("UNIT_RESISTANCES", PLAYER_UNIT_FILTER)
    On("UNIT_AURA", PLAYER_UNIT_FILTER)
    if YUI.IsRetail or YUI.IsForever then
        On("UNIT_SPELL_HASTE", PLAYER_UNIT_FILTER)
    end
    On("COMBAT_RATING_UPDATE")
    if not YUI.IsForever then
        On("MASTERY_UPDATE")
        On("SPEED_UPDATE")
        On("LIFESTEAL_UPDATE")
        On("AVOIDANCE_UPDATE")
    end
    On("PLAYER_REGEN_DISABLED")
    On("PLAYER_REGEN_ENABLED")
end

function Module:AttachLifecycleEvents()
    if not YUI.Event then return end
    YUI.Event:OffOwner(self.lifecycleOwner)
    self.lifecycleOwner.OnYChatStatsFade = function(_, _, hidden, duration)
        Module:SetYChatLinkedFadeHidden(hidden, duration)
    end
    YUI.Event:On("YUI_CHAT_STATS_FADE", "OnYChatStatsFade", self.lifecycleOwner)
    YUI.Event:Emit("YUI_CHAT_STATS_FADE_SYNC_REQUEST")
end

function Module:DetachLifecycleEvents()
    if YUI.Event then
        YUI.Event:OffOwner(self.lifecycleOwner)
    end
end

function Module:EnsureRuntime()
    if self.statsFrame then return end
    self:CreateStatsFrame()
    self.layoutPreviewing = true
    self:UpdateStatsPanel()
    self.layoutPreviewing = false
    self.statsFrame:Hide()
    self.prewarmed = true
end

function Module:UpdateVisibility()
    self:EnsureSettings()
    if self.enabled and (self.settings.panelShown ~= false or self.layoutPreviewing) then
        self:EnsureRuntime()
        local wasShown = self.statsFrame:IsShown()
        self.statsFrame:Show()
        if wasShown then self:RequestStatsPanelRefresh(true) end
    elseif self.statsFrame then
        self.statsFrame:Hide()
    end
end

function Module:SetPanelShown(shown)
    self:EnsureSettings()
    self.settings.panelShown = shown == true
    self:UpdateVisibility()
end

function Module:Toggle()
    if not (Components and Components:IsEnabled(FEATURE_KEY)) then
        return false
    end
    self:SetPanelShown(not (self.settings and self.settings.panelShown ~= false))
    return true
end

function Module:SetEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled and self.settings then
        self:UpdateVisibility()
        return
    end

    self.enabled = enabled
    if YUI.Layout and YUI.Layout.InvalidateAnchorProvider then
        YUI.Layout:InvalidateAnchorProvider(STATS_LAYOUT_ID)
    end
    self:EnsureSettings()
    if enabled then
        self.lifecycleOwner = self.lifecycleOwner or { traceName = "CharacterStatsPanel:lifecycle" }
        self.dataOwner = self.dataOwner or { traceName = "CharacterStatsPanel:data" }
        self.dataOwner.OnDataEvent = self.dataOwner.OnDataEvent or function()
            Module:OnDataEvent()
        end
        self:AttachLifecycleEvents()
        self:UpdateVisibility()
    else
        self:DetachDataEvents()
        self:DetachLifecycleEvents()
        self:CancelPendingPanelRefresh()
        self:StopSpeedTicker()
        if Animation and type(Animation.StopOwner) == "function" then
            Animation:StopOwner(STATS_FADE_ANIMATION_OWNER, false)
        end
        self.linkedFadeHidden = false
        self.linkedFadeFactor = 1
        self:ApplyLinkedFadeAlpha()
        if self.statsFrame then
            self.statsFrame:Hide()
        end
    end
end

function Module:OnProfileChanged()
    self:DetachDataEvents()
    self:CancelPendingPanelRefresh()
    self:StopSpeedTicker()
    if Animation and type(Animation.StopOwner) == "function" then
        Animation:StopOwner(STATS_FADE_ANIMATION_OWNER, false)
    end
    self.settings = nil
    self:EnsureSettings()
    self:SetEnabled(Components:IsEnabled(FEATURE_KEY))
    if self.statsFrame then
        self:RegisterStatsLayout()
    end
end

local function RegisterProfileCallbacks()
    if Module.profileCallbacksRegistered then return end
    local database = YUI.DB and YUI.DB.GetAceDB and YUI.DB:GetAceDB(PRODUCT_ID)
    if not (database and type(database.RegisterCallback) == "function") then return end
    Module.profileOwner = Module.profileOwner or {}
    Module.profileOwner.OnProfileChanged = Module.profileOwner.OnProfileChanged or function()
        Module:OnProfileChanged()
    end
    database.RegisterCallback(Module.profileOwner, "OnProfileChanged", "OnProfileChanged")
    database.RegisterCallback(Module.profileOwner, "OnProfileCopied", "OnProfileChanged")
    database.RegisterCallback(Module.profileOwner, "OnProfileReset", "OnProfileChanged")
    Module.profileCallbacksRegistered = true
end

local function CreateTextPairLine(parent, options)
    options = options or {}
    local line = GUI2:CreateFrame(parent)
    line:SetSize(options.width or DEFAULT_PANEL_WIDTH, options.height or DEFAULT_SPACING)
    line.label = GUI2:CreateText(line, "", "font.size.md", "color.text.primary")
    line.label:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.label:SetJustifyH("LEFT")
    line.value = GUI2:CreateText(line, "", "font.size.md", "color.text.primary")
    line.value:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    line.value:SetJustifyH("RIGHT")
    return line
end

function Module:ApplyLinkedFadeAlpha()
    local frame = self.statsFrame
    if not frame or type(frame.SetAlpha) ~= "function" then return end
    local baseAlpha = tonumber(self.statsBaseAlpha) or 1
    local linkedFactor = tonumber(self.linkedFadeFactor) or 1
    local alpha = baseAlpha * linkedFactor
    if frame._yuiStatsAlpha == alpha then return end
    frame:SetAlpha(alpha)
    frame._yuiStatsAlpha = alpha
end

function Module:SetYChatLinkedFadeHidden(hidden, duration)
    hidden = hidden == true
    self.linkedFadeHidden = hidden
    local target = hidden and 0 or 1
    local current = tonumber(self.linkedFadeFactor) or 1
    duration = tonumber(duration) or 0
    if duration < 0 then duration = 0 end

    if Animation and type(Animation.StopOwner) == "function" then
        Animation:StopOwner(STATS_FADE_ANIMATION_OWNER, false)
    end
    local frame = self.statsFrame
    local shown = frame and type(frame.IsShown) == "function" and frame:IsShown()
    if current ~= target
        and duration > 0
        and shown == true
        and Animation
        and type(Animation.Tween) == "function"
    then
        local handle = Animation:Tween({
            target = frame,
            owner = STATS_FADE_ANIMATION_OWNER,
            key = "ychat-linked-stats-fade",
            from = current,
            to = target,
            duration = duration,
            easing = "linear",
            onUpdate = function(value)
                self.linkedFadeFactor = value
                self:ApplyLinkedFadeAlpha()
            end,
            onFinished = function(_, _, finished)
                if finished then
                    self.linkedFadeFactor = target
                    self:ApplyLinkedFadeAlpha()
                end
            end,
        })
        if handle and handle.noop ~= true then return true end
    end
    self.linkedFadeFactor = target
    self:ApplyLinkedFadeAlpha()
    return true
end

function Module:OnYChatStatsFade(_, hidden, duration)
    self:SetYChatLinkedFadeHidden(hidden, duration)
end

-- ============================================================================
--  属性面板
-- ============================================================================

function Module:CreateStatsFrame()
    local f = GUI2:CreateFrame(UIParent, { name = "YBarStatsFrame" })
    f:SetSize(GetStatsPanelWidth(self.settings), 1)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()

    f:SetScript("OnEnter", function()
        self.isHovering = true
        self:UpdateStatsPanel()
    end)

    f:SetScript("OnLeave", function()
        self.isHovering = false
        self:UpdateStatsPanel()
    end)

    f:SetScript("OnShow", function()
        self:AttachDataEvents()
        self:RequestStatsPanelRefresh(true)
        self:RefreshSpeedTickerState()
    end)

    f:SetScript("OnHide", function()
        self:DetachDataEvents()
        self:CancelPendingPanelRefresh()
        self:StopSpeedTicker()
        if Animation and type(Animation.StopOwner) == "function" then
            Animation:StopOwner(STATS_FADE_ANIMATION_OWNER, false)
        end
    end)

    local content = GUI2:CreateFrame(f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    content:SetSize(GetStatsPanelWidth(self.settings), 1)
    if content.EnableMouse then content:EnableMouse(false) end
    f.contentFrame = content
    f.lines = {}
    self.statsCache = {}
    for i = 1, MAX_STATS_LINES do
        local line = CreateTextPairLine(content, { width = GetStatsPanelWidth(self.settings), height = 20 })
        line:Hide()
        line._yuiStatsShown = false
        f.lines[i] = line
        self.statsCache[i] = {}
    end

    self.statsFrame = f
    self:RegisterStatsLayout()
end

function Module:GetOptions(feature)
    local LSM = LibStub("LibSharedMedia-3.0")
    self:EnsureSettings()
    local Locale = YUI.Locale
    local YBarL = Locale and Locale:Get("CharacterStatsPanel") or {}
    local CoreL = Locale and Locale:Get("Core") or {}

    local fontList = LSM:HashTable("font")
    local fontOptions = {}
    local defaultFontPath = NormalizeFontValue(DEFAULT_FONT, LSM)
    local hasDefaultFont = false
    for name, path in pairs(fontList) do
        if type(path) == "string" and path ~= "" then
            if path == defaultFontPath then
                hasDefaultFont = true
            end
            table.insert(fontOptions, { text = name, value = path })
        end
    end
    if not hasDefaultFont then
        table.insert(fontOptions, { text = DEFAULT_FONT, value = defaultFontPath })
    end
    table.sort(fontOptions, function(a, b) return a.text < b.text end)

    local modeOptions = {
        { text = YBarL["ybar.settings.option.always"] or "Always", value = "ALWAYS" },
        { text = YBarL["ybar.settings.option.hover"] or "Hover", value = "HOVER" },
        { text = YBarL["ybar.settings.option.never"] or "Never", value = "NEVER" },
    }
    local versatilityDisplayOptions = {
        { text = YBarL["stats.option.versatility_single"] or "Single Value", value = VERSATILITY_DISPLAY_SINGLE },
        { text = YBarL["stats.option.versatility_split"] or "Split Values", value = VERSATILITY_DISPLAY_SPLIT },
    }

    local critLabel = YBarL["stats.stat.crit"] or "Crit"
    local critR, critG, critB = GetStatColor("crit")
    local function ColorStylePreview(labelColored, valueColored)
        local label = labelColored and ColorText(critLabel, critR, critG, critB) or ColorText(critLabel, 1, 1, 1)
        local value = valueColored and ColorText("20%", critR, critG, critB) or ColorText("20%", 1, 1, 1)
        return label .. " " .. value
    end
    local styleOptions = {
        { text = ColorStylePreview(false, false), value = COLOR_STYLE_WHITE },
        { text = ColorStylePreview(true, false), value = COLOR_STYLE_LABEL_COLORED },
        { text = ColorStylePreview(false, true), value = COLOR_STYLE_VALUE_COLORED },
        { text = ColorStylePreview(true, true), value = COLOR_STYLE_BOTH_COLORED },
    }
    local orientationOptions = {
        { text = YBarL["stats.option.vertical"] or "Vertical", value = PANEL_ORIENTATION_VERTICAL },
        { text = YBarL["stats.option.horizontal"] or "Horizontal", value = PANEL_ORIENTATION_HORIZONTAL },
    }
    local horizontalAlignmentOptions = {
        { text = YBarL["stats.option.align_center"] or "Center", value = HORIZONTAL_ALIGNMENT_CENTER },
        { text = YBarL["stats.option.align_left"] or "Left", value = HORIZONTAL_ALIGNMENT_LEFT },
        { text = YBarL["stats.option.align_right"] or "Right", value = HORIZONTAL_ALIGNMENT_RIGHT },
    }
    local fontEffectOptions
    if GUI2 and GUI2.Form and GUI2.Form.BuildFontOutlineOptions then
        fontEffectOptions = GUI2.Form:BuildFontOutlineOptions({
            values = {
                none = FONT_EFFECT_NONE,
                outline = FONT_EFFECT_OUTLINE,
                thick = FONT_EFFECT_THICK,
                shadow = FONT_EFFECT_SHADOW,
                outlineShadow = FONT_EFFECT_OUTLINE_SHADOW,
            },
        })
    else
        fontEffectOptions = {
            { text = "None", value = FONT_EFFECT_NONE },
            { text = "Outline", value = FONT_EFFECT_OUTLINE },
            { text = "Thick Outline", value = FONT_EFFECT_THICK },
            { text = "Shadow", value = FONT_EFFECT_SHADOW },
            { text = "Outline + Shadow", value = FONT_EFFECT_OUTLINE_SHADOW },
        }
    end
    local function StatsDivider(key, label)
        return {
            type = "divider",
            width = 400,
            label = label,
            alignLeft = true,
            collapsible = true,
            collapseKey = "component.character_stats_panel." .. key,
            collapsed = false,
        }
    end

    local options = {
        {
            type = "checkbox",
            label = YBarL["stats.settings.panel_shown"] or "显示属性面板",
            get = function() return self.settings.panelShown ~= false end,
            set = function(value)
                self:SetPanelShown(value == true)
            end,
        },
    }

    if YUI.IsWrath then
        table.insert(options, StatsDivider("wrath_only", YBarL["ybar.settings.section.wrath_only"] or "Wrath-only Settings"))
        table.insert(options, {
            type = "row",
            children = {
                {
                    type = "slider",
                    label = YBarL["stats.settings.main_attribute_scale"] or "Primary stat font scale",
                    inline = true,
                    inputWidth = 56,
                    width = 220,
                    min = 1.0, max = 3.0, step = 0.1,
                    get = function() return self.settings.wrathMainScale or 2.0 end,
                    set = function(value)
                        self.settings.wrathMainScale = value
                        self:UpdateStatsPanel()
                    end,
                },
                {
                    type = "slider",
                    label = YBarL["stats.settings.secondary_attribute_scale"] or "Secondary stat font scale",
                    inline = true,
                    inputWidth = 56,
                    width = 220,
                    min = 1.0, max = 3.0, step = 0.1,
                    get = function() return self.settings.wrathOtherScale or 1.2 end,
                    set = function(value)
                        self.settings.wrathOtherScale = value
                        self:UpdateStatsPanel()
                    end,
                },
            }
        })
    end

    local primaryLabel = YUI.IsWrath and (YBarL["stats.settings.primary_wrath"] or "Primary Stats (AP/SP/Armor)") or (YBarL["stats.settings.primary_retail"] or "Primary Stats (Str/Agi/Int/Stam)")
    local secondaryLabel = YUI.IsWrath and (YBarL["stats.settings.secondary_wrath"] or "Secondary Stats (Crit/Haste/Hit/Spirit/Armor Pen)") or (YBarL["stats.settings.secondary_retail"] or "Secondary Stats (Crit/Haste/Mastery/Vers)")
    local defenseLabel = YUI.IsWrath and (YBarL["stats.settings.defense_wrath"] or "Defense Stats (Dodge/Parry/Block)") or (YBarL["stats.settings.defense_retail"] or "Defense Stats (Dodge/Parry/Block/Stagger)")
    local otherLabel = YUI.IsWrath and (YBarL["stats.settings.other_wrath"] or "Other Stats (Attack Speed/MP5)") or (YBarL["stats.settings.other_retail"] or "Other Stats (Leech/Avoidance/Speed)")
    local primaryDetail = YUI.IsWrath and (YBarL["stats.settings.primary_wrath_detail"] or "Attack Power / Spell Power / Armor") or (YBarL["stats.settings.primary_retail_detail"] or "Strength / Agility / Intellect / Stamina")
    local secondaryDetail = YUI.IsWrath and (YBarL["stats.settings.secondary_wrath_detail"] or "Crit / Haste / Hit / Spirit / Armor Penetration") or (YBarL["stats.settings.secondary_retail_detail"] or "Crit / Haste / Mastery / Versatility")
    local defenseDetail = YUI.IsWrath and (YBarL["stats.settings.defense_wrath_detail"] or "Dodge / Parry / Block") or (YBarL["stats.settings.defense_retail_detail"] or "Dodge / Parry / Block / Stagger")
    local otherDetail = YUI.IsWrath and (YBarL["stats.settings.other_wrath_detail"] or "Attack Speed / MP5") or (YBarL["stats.settings.other_retail_detail"] or "Leech / Avoidance / Speed")

    if YUI.IsForever then
        primaryDetail = YBarL["stats.settings.primary_forever_detail"]
        secondaryDetail = YBarL["stats.settings.secondary_forever_detail"]
        defenseDetail = YBarL["stats.settings.defense_forever_detail"]
        otherDetail = YBarL["stats.settings.other_forever_detail"]
    end
    local displayModeOptions = {
        StatsDivider("display", YBarL["ybar.settings.section.stat_panel_display"] or "Stat Panel - Display"),
        {
            type = "row",
            children ={
                {
                    type = "dropdown",
                    label = YBarL["stats.settings.item_level"] or "Item Level",
                    width = 220,
                    options = modeOptions,
                    get = function()
                        if self.settings.ilvlMode then return self.settings.ilvlMode end
                        if self.settings.showIlvl == false then return "NEVER" end
                        return "ALWAYS"
                    end,
                    set = function(value)
                        self.settings.ilvlMode = value
                        self:UpdateStatsPanel()
                    end,
                },
                {
                    type = "dropdown",
                    label = primaryLabel,
                    tooltip = primaryDetail,
                    width = 220,
                    options = modeOptions,
                    get = function() return self.settings.primaryMode or "ALWAYS" end,
                    set = function(value)
                        self.settings.primaryMode = value
                        self:UpdateStatsPanel()
                    end,
                },
            }
        },

        {
            type = "row",
            children ={
                {
                    type = "dropdown",
                    label = secondaryLabel,
                    tooltip = secondaryDetail,
                    width = 220,
                    options = modeOptions,
                    get = function() return self.settings.secondaryMode or "ALWAYS" end,
                    set = function(value)
                        self.settings.secondaryMode = value
                        self:UpdateStatsPanel()
                    end,
                },
                {
                    type = "dropdown",
                    label = defenseLabel,
                    tooltip = defenseDetail,
                    width = 220,
                    options = modeOptions,
                    get = function() return GetDefenseMode(self.settings) end,
                    set = function(value)
                        self.settings.defenseMode = value
                        self:UpdateStatsPanel()
                    end,
                },
            }
        },

        {
            type = "row",
            children = {
                {
                    type = "dropdown",
                    label = otherLabel,
                    tooltip = otherDetail,
                    width = 220,
                    options = modeOptions,
                    get = function() return self.settings.otherMode or "ALWAYS" end,
                    set = function(value)
                        self.settings.otherMode = value
                        self:UpdateStatsPanel()
                    end,
                },
                {
                    type = "dropdown",
                    label = YBarL["stats.settings.movement_speed"] or "Movement Speed",
                    width = 220,
                    options = modeOptions,
                    get = function() return self.settings.speedMode or "ALWAYS" end,
                    set = function(value)
                        self.settings.speedMode = value
                        self:UpdateStatsPanel()
                    end,
                },
            }
        },
    }
    if YUI.IsRetail then
        table.insert(displayModeOptions, 4, {
            type = "row",
            children = {
                {
                    type = "dropdown",
                    label = YBarL["stats.settings.secondary_format"] or "Secondary Stat Format",
                    options = {
                        { value = "PERCENT_ONLY", text = "15%" },
                        { value = "RATING_FIRST", text = "999 · 15%" },
                        { value = "PERCENT_FIRST", text = "15% · 999" },
                        { value = "PERCENT_PARENS", text = "15% (999)" },
                    },
                    width = 220,
                    get = function()
                        return self.settings.showSecondaryRating == true
                            and NormalizeSecondaryRatingFormat(self.settings.secondaryRatingFormat) or "PERCENT_ONLY"
                    end,
                    set = function(value)
                        self.settings.showSecondaryRating = value ~= "PERCENT_ONLY"
                        self.settings.secondaryRatingFormat = NormalizeSecondaryRatingFormat(value)
                        self:UpdateStatsPanel()
                    end,
                },
                {
                    type = "dropdown",
                    label = YBarL["stats.settings.versatility_display"] or "Versatility Display",
                    tooltip = YBarL["stats.settings.versatility_display_tooltip"]
                        or "In restricted states, show one value or split rating-derived and direct bonuses. Outside restrictions, the accurate total is always shown.",
                    width = 220,
                    options = versatilityDisplayOptions,
                    get = function()
                        return NormalizeVersatilityDisplayMode(self.settings.versatilityDisplayMode)
                    end,
                    set = function(value)
                        self.settings.versatilityDisplayMode = NormalizeVersatilityDisplayMode(value)
                        self:UpdateStatsPanel()
                    end,
                },
            },
        })
    end
    for _, opt in ipairs(displayModeOptions) do
        table.insert(options, opt)
    end

    -- Component settings render inside a 465px scroll child with RenderConfig x=20,
    -- so keep this two-column grid at or below 435px to leave a right gutter.
    local STYLE_FORM_WIDTH = 435
    local STYLE_LABEL_WIDTH = 88
    local STYLE_LABEL_GAP = 6
    local STYLE_BODY_WIDTH = 118
    local STYLE_VALUE_WIDTH = 48
    local STYLE_VALUE_GAP = 10
    local STYLE_COLUMN_GAP = 11

    local function RefreshStatsSettingsPage()
        if feature and type(feature.RefreshCurrentModule) == "function" then
            feature:RefreshCurrentModule()
        end
    end

    local function UpdatePanelWidth(value)
        self.settings.panelWidth = value
        self:UpdateStatsPanel()
    end

    local function UpdateHorizontalMaxWidth(value)
        value = math.max(MIN_HORIZONTAL_MAX_WIDTH, math.min(MAX_HORIZONTAL_MAX_WIDTH, tonumber(value) or DEFAULT_HORIZONTAL_MAX_WIDTH))
        self.settings.horizontalMaxWidth = value
        self:UpdateStatsPanel()
    end

    local function RenderStyleFields(parent, x, y, width)
        if not (YUI.Settings and YUI.Settings.RenderAlignedFields) then
            return 0, 0
        end

        local availableWidth = width or STYLE_FORM_WIDTH
        if parent and parent.GetWidth then
            availableWidth = math.min(availableWidth, math.max((parent:GetWidth() or 0) - x - 10, 1))
        end

        local _, gridWidth, gridHeight = YUI.Settings:RenderAlignedFields(parent, {
            x = x,
            y = y,
            width = math.min(availableWidth, STYLE_FORM_WIDTH),
            columns = 2,
            columnGap = STYLE_COLUMN_GAP,
            labelWidth = STYLE_LABEL_WIDTH,
            labelGap = STYLE_LABEL_GAP,
            bodyWidth = STYLE_BODY_WIDTH,
            valueWidth = STYLE_VALUE_WIDTH,
            valueGap = STYLE_VALUE_GAP,
            minBodyWidth = STYLE_BODY_WIDTH,
            rowHeight = 32,
            rowGap = 10,
            fields = {
                {
                    type = "dropdown",
                    label = YBarL["stats.settings.appearance_style"] or "Color Style",
                    options = styleOptions,
                    get = function() return NormalizeColorStyle(self.settings.appearanceStyle) end,
                    set = function(value)
                        self.settings.appearanceStyle = NormalizeColorStyle(value)
                        self:UpdateStatsPanel()
                    end,
                },
                {
                    type = "dropdown",
                    label = YBarL["stats.settings.panel_orientation"] or "Layout",
                    options = orientationOptions,
                    get = function() return GetPanelOrientation(self.settings) end,
                    set = function(value)
                        local orientation = value == PANEL_ORIENTATION_HORIZONTAL and PANEL_ORIENTATION_HORIZONTAL or PANEL_ORIENTATION_VERTICAL
                        self.settings.panelOrientation = orientation
                        self:UpdateStatsPanel()
                        RefreshStatsSettingsPage()
                    end,
                },
                {
                    type = "dropdown",
                    label = CoreL["common.font"] or "Font",
                    options = fontOptions,
                    get = function() return NormalizeFontValue(self.settings.font, LSM) end,
                    set = function(value)
                        local fontValue = NormalizeFontValue(value, LSM)
                        self.settings.font = fontValue
                        self:UpdateStatsPanel()
                    end,
                },
                {
                    type = "slider",
                    label = CoreL["common.font_size"] or "Font Size",
                    min = 8, max = 20, step = 1,
                    get = function() return self.settings.fontSize or DEFAULT_SIZE end,
                    set = function(value)
                        self.settings.fontSize = value
                        self:UpdateStatsPanel()
                    end,
                },
                {
                    type = "dropdown",
                    label = YBarL["stats.settings.font_effect"] or "Outline/Shadow",
                    options = fontEffectOptions,
                    get = function() return NormalizeFontEffect(self.settings.fontEffect) end,
                    set = function(value)
                        local effect = NormalizeFontEffect(value)
                        self.settings.fontEffect = effect
                        self:UpdateStatsPanel()
                    end,
                },
                {
                    type = "slider",
                    label = YBarL["stats.settings.panel_width"] or "Panel Width",
                    min = MIN_PANEL_WIDTH, max = 1000, step = 1,
                    hidden = function() return GetPanelOrientation(self.settings) == PANEL_ORIENTATION_HORIZONTAL end,
                    get = function() return self.settings.panelWidth or DEFAULT_PANEL_WIDTH end,
                    set = UpdatePanelWidth,
                },
                {
                    type = "slider",
                    label = YBarL["stats.settings.row_spacing"] or "Row Spacing",
                    min = 0, max = 30, step = 1,
                    hidden = function() return GetPanelOrientation(self.settings) == PANEL_ORIENTATION_HORIZONTAL end,
                    get = function() return self.settings.spacing or DEFAULT_SPACING end,
                    set = function(value)
                        self.settings.spacing = value
                        self:UpdateStatsPanel()
                    end,
                },
                {
                    type = "slider",
                    label = YBarL["stats.settings.max_width"] or "Maximum Width",
                    min = MIN_HORIZONTAL_MAX_WIDTH, max = MAX_HORIZONTAL_MAX_WIDTH, step = 1,
                    hidden = function() return GetPanelOrientation(self.settings) ~= PANEL_ORIENTATION_HORIZONTAL end,
                    get = function() return GetHorizontalMaxWidth(self.settings) end,
                    set = UpdateHorizontalMaxWidth,
                },
                {
                    type = "dropdown",
                    label = YBarL["stats.settings.horizontal_alignment"] or "Alignment",
                    options = horizontalAlignmentOptions,
                    hidden = function() return GetPanelOrientation(self.settings) ~= PANEL_ORIENTATION_HORIZONTAL end,
                    get = function() return NormalizeHorizontalAlignment(self.settings.horizontalAlignment) end,
                    set = function(value)
                        local alignment = NormalizeHorizontalAlignment(value)
                        self.settings.horizontalAlignment = alignment
                        self:UpdateStatsPanel()
                    end,
                },
                {
                    type = "slider",
                    label = YBarL["stats.settings.column_spacing"] or "Column Spacing",
                    min = 0, max = 40, step = 1,
                    hidden = function() return GetPanelOrientation(self.settings) ~= PANEL_ORIENTATION_HORIZONTAL end,
                    get = function() return GetColumnSpacing(self.settings) end,
                    set = function(value)
                        self.settings.columnSpacing = value
                        self:UpdateStatsPanel()
                    end,
                },
                {
                    type = "dropdown",
                    label = YBarL["stats.settings.precision"] or "Decimal Places",
                    options = {
                        { text = "0", value = 0 },
                        { text = "1", value = 1 },
                        { text = "2", value = 2 },
                    },
                    get = function() return self.settings.precision or DEFAULT_PRECISION end,
                    set = function(value)
                        self.settings.precision = value
                        self:UpdateStatsPanel()
                    end,
                },
                {
                    type = "slider",
                    label = YBarL["stats.settings.speed_update_frequency"] or "Speed Interval",
                    min = 0.1, max = 1.0, step = 0.1,
                    get = function() return self.settings.speedUpdateFreq or DEFAULT_SPEED_UPDATE_FREQ end,
                    set = function(value)
                        self.settings.speedUpdateFreq = value
                        self:RefreshSpeedTickerState()
                    end,
                },
                {
                    type = "slider",
                    label = YBarL["stats.settings.out_of_combat_alpha"] or "OOC Alpha",
                    min = 0, max = 1, step = 0.05,
                    get = function() return self.settings.outOfCombatAlpha or 1.0 end,
                    set = function(value)
                        self.settings.outOfCombatAlpha = value
                        self:UpdateStatsPanel()
                    end,
                },
            },
        })

        return gridWidth, gridHeight
    end

    local commonOptions = {
        StatsDivider("style", YBarL["ybar.settings.section.stat_panel_style"] or "Stat Panel - Style"),
        {
            type = "custom",
            width = STYLE_FORM_WIDTH,
            render = RenderStyleFields,
        },
    }

    for _, opt in ipairs(commonOptions) do
        table.insert(options, opt)
    end

    return options
end

function Module:UpdateWrathStatsPanel()
    if not self.statsFrame then return end

    local f = self.statsFrame
    local previousWidth = f:GetWidth() or 0
    local previousHeight = f:GetHeight() or 0
    SetWidthIfChanged(f, GetStatsPanelWidth(self.settings))
    if f.contentFrame then SetScaleIfChanged(f.contentFrame, 1) end
    f.speedLineValue = nil
    f.speedFmtStr = nil

    local isHovering = self.isHovering or self.layoutPreviewing == true
    local function ShouldShow(mode)
        if mode == "ALWAYS" then return true end
        if mode == "NEVER" then return false end
        if mode == "HOVER" then return isHovering end
        return true
    end

    local primaryMode = self.settings.primaryMode or "ALWAYS"
    local secondaryMode = self.settings.secondaryMode or "ALWAYS"
    local otherMode = self.settings.otherMode or "ALWAYS"
    local defenseMode = GetDefenseMode(self.settings)
    local speedMode = self.settings.speedMode or "ALWAYS"
    local ilvlMode = self.settings.ilvlMode or (self.settings.showIlvl == false and "NEVER") or "ALWAYS"

    local function GetStatCategory(id)
        if id == "main" or id == "ap" or id == "ap2" or id == "health" or id == "mana" then return "primary" end
        if id == "haste" or id == "crit" or id == "hit" or id == "arp" or id == "expertise" then return "secondary" end
        if IsDefenseStat(id) then return "defense" end
        if id == "speed" or id == "manaregen" then return "other" end
        if id == "movespeed" then return "movespeed" end
        if id == "ilvl" then return "ilvl" end
        return "other"
    end

    local function ShouldShowStatId(id)
        local cat = GetStatCategory(id)
        if cat == "primary" then return ShouldShow(primaryMode) end
        if cat == "secondary" then return ShouldShow(secondaryMode) end
        if cat == "defense" then return ShouldShow(defenseMode) end
        if cat == "other" then return ShouldShow(otherMode) end
        if cat == "movespeed" then return ShouldShow(speedMode) end
        if cat == "ilvl" then return ShouldShow(ilvlMode) end
        return true
    end

    local PlayAs, tplayerClass = GetWrathPlayAs()
    local stats, statsCount = GetWrathStatsData(PlayAs, tplayerClass, ShouldShowStatId)

    local LSM = LibStub("LibSharedMedia-3.0")
    local fontPath = NormalizeFontValue(self.settings.font, LSM)
    local baseFontSize = self.settings.fontSize or DEFAULT_SIZE
    local fontEffect = NormalizeFontEffect(self.settings.fontEffect)
    local spacing = self.settings.spacing or DEFAULT_SPACING
    local columnSpacing = GetColumnSpacing(self.settings)

    local mainScale = self.settings.wrathMainScale or 2.0
    local otherScale = self.settings.wrathOtherScale or 1.2
    local precision = self.settings.precision or DEFAULT_PRECISION
    if type(precision) ~= "number" then precision = tonumber(precision) or DEFAULT_PRECISION end
    precision = math.floor(precision + 0.5)
    if precision < 0 then precision = 0 end

    local fmtStr = "%." .. precision .. "f%%"
    local speedFmtStr = "%.0f%%"

    local appearanceStyle = NormalizeColorStyle(self.settings.appearanceStyle)

    local orientation = GetPanelOrientation(self.settings)
    local horizontalLayout = orientation == PANEL_ORIENTATION_HORIZONTAL and BeginHorizontalLayout(f, columnSpacing) or nil
    local lineIndex = 0
    local yOffset = 0

    for i = 1, statsCount do
        local stat = stats[i]

        local cat = GetStatCategory(stat.id)
        local showStat = true
        if cat == "primary" then showStat = ShouldShow(primaryMode)
        elseif cat == "secondary" then showStat = ShouldShow(secondaryMode)
        elseif cat == "defense" then showStat = ShouldShow(defenseMode)
        elseif cat == "other" then showStat = ShouldShow(otherMode)
        elseif cat == "movespeed" then showStat = ShouldShow(speedMode)
        elseif cat == "ilvl" then showStat = ShouldShow(ilvlMode)
        end

        if showStat then
            lineIndex = lineIndex + 1
            local line = f.lines[lineIndex]

        SetShownIfChanged(line, true)

        local valFontSize = stat.isMain and (baseFontSize * mainScale) or (baseFontSize * otherScale)
        local lineHeight = math.max(20, valFontSize + 4)

        -- Apply font scaling
        ApplyStatsFont(line.label, fontPath, baseFontSize, fontEffect)
        ApplyStatsFont(line.value, fontPath, valFontSize, fontEffect)
        SetWidthIfChanged(line.value, 0)

        if orientation == PANEL_ORIENTATION_VERTICAL then
            ResetVerticalLine(line, f:GetWidth())
            line:SetPoint("TOPLEFT", 0, yOffset)
            SetHeightIfChanged(line, lineHeight)
            SetWidthIfChanged(line.value, 0)

            -- Set alignment based on main scale to keep bottom baselines aligned
            if stat.isMain and mainScale > 1.0 then
                -- For main stat with larger font, anchor label's BOTTOMLEFT to line's BOTTOMLEFT
                -- And value's BOTTOMRIGHT to line's BOTTOMRIGHT
                line.label:SetPoint("BOTTOMLEFT", 5, 2)
                line.value:SetPoint("BOTTOMRIGHT", -5, 0)
            else
                -- Default centered anchoring
                line.label:SetPoint("LEFT", 5, 0)
                line.value:SetPoint("RIGHT", -5, 0)
            end
        end

        local color = stat.color or DEFAULT_STAT_COLORS[stat.id]
        local r, g, b = 1, 1, 1
        if color then
            r, g, b = color[1], color[2], color[3]
        end
        ApplyStatColorStyle(line, appearanceStyle, r, g, b)

        SetTextIfChanged(line.label, stat.label)
        line.statId = stat.id

        -- Format value
        local valueText
        if stat.isPercent then
            if stat.id == "movespeed" then
                valueText = format(speedFmtStr, stat.val)
                f.speedLineValue = line.value
                f.speedFmtStr = speedFmtStr
            else
                valueText = format(fmtStr, stat.val)
            end
        elseif stat.isString then
            valueText = stat.val
        else
            valueText = format("%.0f", stat.val)
        end
        local valuePrecision = stat.id == "movespeed" and 0 or precision
        local valueFallbackWidth = orientation == PANEL_ORIENTATION_HORIZONTAL and GetStatValueFallbackWidth(stat.id, valFontSize, valuePrecision, stat.isPercent, stat.isString, stat.isMain) or nil
        SetTextIfChanged(line.value, valueText, valueFallbackWidth)

        if orientation == PANEL_ORIENTATION_HORIZONTAL then
            local horizontalLineHeight = math.max(
                SafeFontStringHeight(line.label, baseFontSize),
                SafeFontStringHeight(line.value, valFontSize)
            )
            PlaceHorizontalLine(line, horizontalLayout, horizontalLineHeight, valueFallbackWidth)
        elseif stat.isMain and mainScale > 1.0 then
            local leftPad, rightPad, gap = 5, 5, 8
            local labelWidth = SafeFontStringWidth(line.label, SECRET_TEXT_FALLBACK_WIDTH)
            local valueWidth = SafeFontStringWidth(line.value, SECRET_TEXT_FALLBACK_WIDTH)

            if leftPad + labelWidth + gap + valueWidth + rightPad > f:GetWidth() then
                line.value:ClearAllPoints()
                line.value:SetPoint("BOTTOMLEFT", line.label, "BOTTOMRIGHT", gap, -2)
                line.value:SetJustifyH("LEFT")
            end
        end

        if orientation == PANEL_ORIENTATION_VERTICAL then
            -- Adjust yOffset based on value font size to prevent overlapping
            -- local yStep = math.max(20, spacing)
            local yStep = spacing

            if stat.isMain then
                -- 主属性行下方增加一些额外间距，使其看起来不是挤在一起
                yStep = yStep + (spacing * 0.2)
            end

            yOffset = yOffset - yStep - 2
        end
        end
    end

    -- Hide unused lines
    for i = lineIndex + 1, #f.lines do
        SetShownIfChanged(f.lines[i], false)
    end

    ApplyStatsPanelGeometry(f, self.settings, orientation, horizontalLayout, math.abs(yOffset))
    self:RefreshStatsLayoutBounds(previousWidth, previousHeight)
    self:RefreshSpeedTickerState()
end

function Module:UpdateStatsPanel()
    if not self.statsFrame then return end

    local alpha = 1.0
    if not self.isHovering and not self.layoutPreviewing and not SecurityAPI.InCombatLockdown() then
        alpha = self.settings.outOfCombatAlpha or 1.0
    end
    self.statsBaseAlpha = alpha
    self:ApplyLinkedFadeAlpha()

    if YUI.IsWrath then
        self:UpdateWrathStatsPanel()
        return
    end

    RefreshStatDefLabels()

    local f = self.statsFrame
    local previousWidth = f:GetWidth() or 0
    local previousHeight = f:GetHeight() or 0
    SetWidthIfChanged(f, GetStatsPanelWidth(self.settings))
    if f.contentFrame then SetScaleIfChanged(f.contentFrame, 1) end
    f.speedLineValue = nil
    f.speedFmtStr = nil

    -- 更新字体
    local LSM = LibStub("LibSharedMedia-3.0")
    local fontPath = NormalizeFontValue(self.settings.font, LSM)
    local fontSize = self.settings.fontSize or DEFAULT_SIZE
    local fontEffect = NormalizeFontEffect(self.settings.fontEffect)
    local spacing = self.settings.spacing or DEFAULT_SPACING
    local columnSpacing = GetColumnSpacing(self.settings)
    local precision = self.settings.precision or DEFAULT_PRECISION
    -- Fix: Ensure precision is a valid integer to avoid "invalid option in format" error
    if type(precision) ~= "number" then precision = tonumber(precision) or DEFAULT_PRECISION end
    precision = math.floor(precision + 0.5) -- Round to nearest integer
    if precision < 0 then precision = 0 end -- Ensure non-negative

    local fmtStr = "%." .. precision .. "f%%"

    -- 移动速度强制使用整数精度
    local speedPrecision = 0
    local speedFmtStr = "%." .. speedPrecision .. "f%%"

    -- 获取显示设置
    local primaryMode = self.settings.primaryMode or "ALWAYS"
    local secondaryMode = self.settings.secondaryMode or "ALWAYS"
    local otherMode = self.settings.otherMode or "ALWAYS"
    local defenseMode = GetDefenseMode(self.settings)
    local speedMode = self.settings.speedMode or "ALWAYS"
    local ilvlMode = self.settings.ilvlMode or (self.settings.showIlvl == false and "NEVER") or "ALWAYS"
    local appearanceStyle = NormalizeColorStyle(self.settings.appearanceStyle)
    local showSecondaryRating = self.settings.showSecondaryRating == true
    local secondaryRatingFormat = NormalizeSecondaryRatingFormat(self.settings.secondaryRatingFormat)

    local isHovering = self.isHovering or self.layoutPreviewing == true

    -- 辅助函数：判断是否显示
    local function ShouldShow(mode)
        if mode == "ALWAYS" then return true end
        if mode == "NEVER" then return false end
        if mode == "HOVER" then return isHovering end
        return true
    end

    local showPrimaryStats = ShouldShow(primaryMode)
    local showSecondaryStats = ShouldShow(secondaryMode)
    local showOtherStats = ShouldShow(otherMode)
    local showDefenseStats = ShouldShow(defenseMode)
    local showSpeedStats = ShouldShow(speedMode)
    local showIlvlStats = ShouldShow(ilvlMode)

    -- 收集属性
    if not self.statsCache then self.statsCache = {} end
    local stats = self.statsCache
    local statsCount = 0
    local function addStatToCache(id, def)
        statsCount = statsCount + 1
        if not stats[statsCount] then stats[statsCount] = {} end
        stats[statsCount].id = id
        stats[statsCount].def = def
    end

    -- 装等优先
    if showIlvlStats then
        addStatToCache("ilvl", STAT_DEFS.ilvl)
    end

    local roleCtx
    local classToken
    if showPrimaryStats or showDefenseStats then
        roleCtx = GetRoleContext()
        _, classToken = UnitAPI.UnitClass("player")
    end

    if showPrimaryStats then
        -- 基于职业/专精确定主属性
        local primary = "str"
        if roleCtx.isCaster or roleCtx.isHealer then
            primary = "int"
        elseif roleCtx.isRanged then -- Hunter
            primary = "agi"
        elseif classToken == "ROGUE" or classToken == "DEMONHUNTER" or classToken == "MONK" or (classToken == "DRUID" and not roleCtx.isCaster) or (classToken == "SHAMAN" and not roleCtx.isCaster) then
            primary = "agi"
        end

        -- 添加相关主属性
        addStatToCache(primary, STAT_DEFS[primary])
        if YUI.IsForever then
            addStatToCache("sta", STAT_DEFS.sta)
            addStatToCache("spirit", STAT_DEFS.spirit)
        end
        -- 耐力默认隐藏（按要求）
    end

    -- 副属性
    if showSecondaryStats then
        addStatToCache("crit", STAT_DEFS.crit)
        addStatToCache("haste", STAT_DEFS.haste)
        if YUI.IsForever then
            addStatToCache("hit", STAT_DEFS.hit)
            addStatToCache("expertise", STAT_DEFS.expertise)
        else
            addStatToCache("mastery", STAT_DEFS.mastery)
            addStatToCache("versatility", STAT_DEFS.versatility)
        end
    end

    -- 其他
    if showOtherStats then
        if YUI.IsForever then
            addStatToCache("attack_power", STAT_DEFS.attack_power)
            addStatToCache("spell_power", STAT_DEFS.spell_power)
            addStatToCache("manaregen", STAT_DEFS.manaregen)
        else
            addStatToCache("leech", STAT_DEFS.leech)
            addStatToCache("avoidance", STAT_DEFS.avoidance)
            addStatToCache("speed", STAT_DEFS.speed)
        end
    end

    -- 防御（仅坦克或有相关属性）
    if showDefenseStats and (YUI.IsForever or (roleCtx and roleCtx.isTank)) then
        if YUI.IsForever then addStatToCache("armor", STAT_DEFS.armor) end
        addStatToCache("dodge", STAT_DEFS.dodge)
        addStatToCache("parry", STAT_DEFS.parry)
        addStatToCache("block", STAT_DEFS.block)
        addStatToCache("stagger", STAT_DEFS.stagger)
    end

    -- 移动速度
    if showSpeedStats then
        addStatToCache("movespeed", STAT_DEFS.movespeed)
    end

    local orientation = GetPanelOrientation(self.settings)
    local horizontalLayout = orientation == PANEL_ORIENTATION_HORIZONTAL and BeginHorizontalLayout(f, columnSpacing) or nil
    local lineIndex = 0
    local yOffset = 0

    for i = 1, statsCount do
        local stat = stats[i]
        if IsStatAvailable(stat.id) then
            local def = stat.def
            if def and def.api then
                -- 检查分类显示设置
                local showStat = true

                if stat.id == "ilvl" then
                    showStat = ShouldShow(ilvlMode)
                elseif stat.id == "str" or stat.id == "agi" or stat.id == "int" or stat.id == "sta" then
                    showStat = ShouldShow(primaryMode)
                elseif stat.id == "crit" or stat.id == "haste" or stat.id == "mastery" or stat.id == "versatility" then
                    showStat = ShouldShow(secondaryMode)
                elseif IsDefenseStat(stat.id) then
                    showStat = ShouldShow(defenseMode)
                elseif stat.id == "leech" or stat.id == "avoidance" or stat.id == "speed" or stat.id == "manaregen" then
                    showStat = ShouldShow(otherMode)
                elseif stat.id == "movespeed" then
                    showStat = ShouldShow(speedMode)
                end

                if showStat then
                    local rawVal = def.api()
                    local val = rawVal
                    local isSecret = false
                    local isSecretCombo = false
                    local isSecretSpeed = false

                    if IsSecretValue(rawVal) then
                        isSecret = true
                    elseif type(rawVal) == "table" then
                        if rawVal.isSecretCombo then
                            isSecretCombo = true
                            isSecret = true
                        elseif rawVal.isSecretSpeed then
                            isSecretSpeed = true
                            isSecret = true
                        end
                    else
                        val = YUI.F:SafeNum(rawVal, 0)
                    end

                    local show = true
                    if not isSecret then
                        if def.percent and val < 0.1 then show = false end
                    end
                    -- 强制显示某些关键属性，除非被上方分类逻辑隐藏
                    if stat.id == "str" or stat.id == "agi" or stat.id == "int" or stat.id == "movespeed" or stat.id == "ilvl" then show = true end
                    if YUI.IsForever and not isSecret and rawVal == nil then show = false end

                    if show then
                        lineIndex = lineIndex + 1
                        local line = f.lines[lineIndex]

                        SetShownIfChanged(line, true)

                        -- 更新字体以防改变
                        ApplyStatsFont(line.label, fontPath, fontSize, fontEffect)
                        ApplyStatsFont(line.value, fontPath, fontSize, fontEffect)
                        local lineHeight = math.max(20, fontSize + 4)

                        if orientation == PANEL_ORIENTATION_VERTICAL then
                            ResetVerticalLine(line, f:GetWidth())
                            line:SetPoint("TOPLEFT", 0, yOffset)
                            SetHeightIfChanged(line, lineHeight)
                            line.label:SetPoint("LEFT", 5, 0)
                            line.value:SetPoint("RIGHT", -5, 0)
                        end

                        local r, g, b = GetStatColor(stat.id)
                        ApplyStatColorStyle(line, appearanceStyle, r, g, b)

                        SetTextIfChanged(line.label, def.label)
                        line.statId = stat.id -- 存储 ID 用于更新
                        local secondaryRating
                        local secondaryRatingIsSecret = false
                        local secondaryRatingAvailable = false
                        local secondaryRatingPrefix
                        if showSecondaryRating and SECONDARY_RATING_CR[stat.id] then
                            secondaryRating, secondaryRatingIsSecret = ReadSecondaryStatRating(stat.id)
                            if secondaryRatingIsSecret then
                                secondaryRatingAvailable = true
                            elseif secondaryRating ~= nil then
                                secondaryRatingAvailable = true
                                secondaryRatingPrefix = format(SECONDARY_RATING_PREFIX_FORMAT, secondaryRating)
                            end
                        end

                        local valueText
                        local useSecretSink = isSecret or secondaryRatingIsSecret
                        if useSecretSink then
                            if isSecretCombo then
                                SetVersatilitySecretText(
                                    line.value,
                                    precision,
                                    self.settings.versatilityDisplayMode,
                                    rawVal.v1,
                                    rawVal.v2,
                                    secondaryRating,
                                    secondaryRatingIsSecret,
                                    secondaryRatingPrefix,
                                    secondaryRatingFormat
                                )
                            elseif isSecretSpeed then
                                SetSecretMovementSpeedText(line.value, rawVal.val)
                                f.speedFmtStr = "%.1f%%"
                                f.speedLineValue = line.value
                            elseif def.percent then
                                if secondaryRatingAvailable and secondaryRatingFormat ~= "RATING_FIRST" then
                                    SetSecretFormattedText(line.value, GetSecondaryRatingFormat(fmtStr, secondaryRatingFormat),
                                        2, rawVal, secondaryRating)
                                elseif secondaryRatingPrefix then
                                    SetSecretFormattedText(line.value, secondaryRatingPrefix .. fmtStr, 1, rawVal)
                                elseif secondaryRatingIsSecret then
                                    SetSecretFormattedText(
                                        line.value,
                                        SECONDARY_RATING_PREFIX_FORMAT .. fmtStr,
                                        2,
                                        secondaryRating,
                                        rawVal
                                    )
                                else
                                    SetSecretFormattedText(line.value, fmtStr, 1, rawVal)
                                end
                            else
                                SetSecretFormattedText(line.value, "%.0f", 1, rawVal)
                            end
                        elseif def.percent then
                            if stat.id == "movespeed" then
                                valueText = format(speedFmtStr, val)
                                f.speedFmtStr = speedFmtStr
                                f.speedLineValue = line.value
                            elseif secondaryRatingPrefix then
                                if secondaryRatingFormat == "RATING_FIRST" then
                                    valueText = secondaryRatingPrefix .. format(fmtStr, val)
                                else
                                    valueText = format(GetSecondaryRatingFormat(fmtStr, secondaryRatingFormat), val, secondaryRating)
                                end
                            else
                                valueText = format(fmtStr, val)
                            end
                        else
                            valueText = format("%.0f", val)
                        end
                        local valuePrecision = precision
                        if stat.id == "movespeed" then
                            valuePrecision = math.max(speedPrecision or 0, 1)
                        end
                        local isPrimaryValue = stat.id == "str" or stat.id == "agi" or stat.id == "int" or stat.id == "sta"
                        local valueFallbackWidth = orientation == PANEL_ORIENTATION_HORIZONTAL and GetStatValueFallbackWidth(stat.id, fontSize, valuePrecision, def.percent, false, isPrimaryValue) or nil
                        if valueFallbackWidth and secondaryRatingAvailable then
                            valueFallbackWidth = valueFallbackWidth + EstimateTextWidth(fontSize, 8, 54)
                        end
                        if not useSecretSink then
                            SetTextIfChanged(line.value, valueText, valueFallbackWidth)
                        else
                            line.value._yuiStatsValueFallbackWidth = NormalizeSafeWidth(valueFallbackWidth, SECRET_TEXT_FALLBACK_WIDTH)
                        end

                        if orientation == PANEL_ORIENTATION_HORIZONTAL then
                            local horizontalLineHeight = math.max(
                                SafeFontStringHeight(line.label, fontSize),
                                SafeFontStringHeight(line.value, fontSize)
                            )
                            PlaceHorizontalLine(line, horizontalLayout, horizontalLineHeight, valueFallbackWidth)
                        else
                            yOffset = yOffset - spacing
                        end
                    end
                end
            end
        end
    end

    -- 隐藏未使用行
    for i = lineIndex + 1, #f.lines do
        SetShownIfChanged(f.lines[i], false)
    end

    ApplyStatsPanelGeometry(f, self.settings, orientation, horizontalLayout, math.abs(yOffset))
    self:RefreshStatsLayoutBounds(previousWidth, previousHeight)
    self:RefreshSpeedTickerState()
end

local Feature = {
    product = PRODUCT_ID,
    storageKey = FEATURE_KEY,
    name = YBarL["feature.name"] or "属性面板",
    description = YBarL["feature.description"] or "显示可独立布局的角色属性面板。",
    tags = { "实用功能" },
    order = 307.5,
    default = true,
    settingsMode = "inline",
    sourceRoot = "Components\\CharacterStatsPanel",
    assetFolders = { "Components\\CharacterStatsPanel\\Media" },
    modSwitchImage = "modswitch\\characterstatspanel-bg.png",
    modSwitchImageCrop = false,
    versions = { "forever", "mainline", "wrath" },
    callback = function(enabled)
        Module:SetEnabled(enabled)
    end,
}

function Feature:GetOptions()
    return Module:GetOptions(self)
end

Components:RegisterFeature(FEATURE_KEY, Feature)

if YUI.Event and type(YUI.Event.Once) == "function" then
    YUI.Event:Once("YUI_DB_READY", RegisterProfileCallbacks, Module, {
        moduleId = "component:" .. FEATURE_KEY,
        traceName = "CharacterStatsPanel:profile-callbacks",
    })
else
    RegisterProfileCallbacks()
end


-- The feature definition survives business disable; no dynamic size is invented.
if YUI.Layout and YUI.Layout.RegisterAnchorProvider then
    YUI.Layout:RegisterAnchorProvider(STATS_LAYOUT_ID, {
        name = "YBarStatsFrame",
        getState = function()
            return Components.GetConfiguredEnableState
                and Components:GetConfiguredEnableState(FEATURE_KEY) or "unknown"
        end,
    })
end

local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.IsRetail then return end

local Tools = YUI.MythicPlusTools
if not Tools or not Tools.RegisterSubFeature then return end

local L = Tools.L or (YUI.Locale and YUI.Locale:Get("MythicPlusTools")) or nil
local SpellAPI = YUI.API and YUI.API.Spell
local SecurityAPI = YUI.API and YUI.API.Security
local UnitAPI = YUI.API and YUI.API.Unit
local cpuWatchdog = YUI.CPUWatchdog

local FIELD_WIDTH = 300
local FIELD_GAP = 14
local ICON_NAME_FONT_SIZE = 14
local ICON_LEVEL_FONT_SIZE = 24
local ICON_SCORE_FONT_SIZE = 14
local ICON_LEVEL_Y_OFFSET = -1
local OLD_ICON_NAME_FONT_SIZE = 18
local OLD_ICON_LEVEL_FONT_SIZE = 21
local OLD_ICON_SCORE_FONT_SIZE = 11
local OLD_ICON_LEVEL_Y_OFFSET = 1
local ICON_TEXT_DEFAULTS_VERSION = 2
local ICON_NAME_SIZE_MIN = 10
local ICON_NAME_SIZE_MAX = 24
local ICON_LEVEL_SIZE_MIN = 14
local ICON_LEVEL_SIZE_MAX = 32
local ICON_SCORE_SIZE_MIN = 8
local ICON_SCORE_SIZE_MAX = 20
local ICON_LEVEL_Y_OFFSET_MIN = -10
local ICON_LEVEL_Y_OFFSET_MAX = 10
local ICON_TEXT_HORIZONTAL_PADDING = 6
local SETTING_LABEL_WIDTH = 130
local SETTING_INPUT_WIDTH = 52
local CHALLENGES_ADDON = "Blizzard_ChallengesUI"
local SPEC_TOOLTIP_ICON_SIZE = 16
local SPEC_TOOLTIP_NATIVE_DIMENSION = 64
local SPEC_TOOLTIP_CUSTOM_DIMENSION = 512
local SPEC_TOOLTIP_NATIVE_CROP = { 4, 60, 4, 60 }
local DURATION_IN_TIME_COLOR = { r = 0.2, g = 1, b = 0.2 }
local DURATION_OVERTIME_COLOR = { r = 1, g = 0.25, b = 0.25 }
local DUNGEON_NAME_COLOR = { r = 1, g = 0.82, b = 0.1, a = 1 }
local SETTLED_REFRESH_DELAYS = { 0, 0.05 }
local PVE_STATS_PANEL_WIDTH = 300
local PVE_STATS_PANEL_GAP = 6
local PVE_STATS_PANEL_PADDING = 10
local PVE_STATS_HEADER_HEIGHT = 32
local PVE_STATS_FOOTER_HEIGHT = 34
local PVE_STATS_ROW_MIN_HEIGHT = 42
local PVE_STATS_ROW_MAX_HEIGHT = 50
local PVE_STATS_STATUS_WIDTH = 76
local PVE_STATS_MAX_RUNS = 8
local PVE_STATS_REFRESH_DELAYS = { 0, 0.05, 0.25 }
local PVE_STATS_DEV_WEEK_COUNTS = { 0, 1, 3, 5, 8, 11, 16, 32 }
local PVE_STATS_WEEKLY_COLORS = {
    low = { r = 0.2, g = 1, b = 0.2 },
    medium = { r = 0.25, g = 0.55, b = 1 },
    high = { r = 0.64, g = 0.21, b = 0.93 },
    max = { r = 1, g = 0.5, b = 0 },
}
local PVE_STATS_WHITE = { r = 1, g = 1, b = 1 }
local PVE_STATS_GRAY = { r = 0.55, g = 0.55, b = 0.55 }

local PVEEnhancement = {
    id = "pveEnhancement",
    order = 30,
    _statsPanelDataDirty = true,
    _statsPanelManuallyClosed = false,
    _statsPanelWasEligible = false,
    PartyKeystonePanel = {
        width = 168,
        minHeight = 48,
        padding = 8,
        rowHeight = 13,
        rowGap = 1,
        bottomPadding = 8,
        titleFontSize = 14,
        rowFontSize = 13,
        buttonWidth = 44,
        buttonHeight = 18,
        nameWidth = 62,
        rowTopOffset = 31,
        maxRows = 5,
        eventOwner = {},
    },
}

PVEEnhancement.RatingStats = {
    releaseEnabled = true,
    textColor = { r = 0.2, g = 1, b = 0.35 },
    scoreColor = { r = 1, g = 0.5, b = 0 },
    shortfallColor = { r = 0.78, g = 0.78, b = 0.78 },
    orangeGradientStart = { 1, 0.5, 0 },
    orangeGradientEnd = { 1, 0.84, 0 },
    purpleGradientStart = { 0.64, 0.21, 0.93 },
    purpleGradientEnd = { 0.9, 0.4, 1 },
    regionByID = {
        [1] = "us",
        [2] = "kr",
        [3] = "eu",
        [4] = "tw",
        [5] = "cn",
    },
    regionByName = {
        cn = "cn",
        china = "cn",
        tw = "tw",
        taiwan = "tw",
        kr = "kr",
        korea = "kr",
        eu = "eu",
        europe = "eu",
        us = "us",
        usa = "us",
    },
    milestoneKeys = {
        "keystoneMyth",
        "keystoneLegend",
        "keystoneHero",
        "allTimed20",
        "allTimed18",
        "allTimed15",
        "allTimed12",
        "allTimed10",
    },
}

PVEEnhancement.StatsPanel = {
    topRunLimit = 8,
    summaryHeight = 220,
    identityTopOffset = 6,
    identityBgTopOffset = 0,
    identityBgHeight = 96,
    summaryInfoInset = 8,
    summaryInfoTopInset = 6,
    summaryInfoBottomInset = 8,
    summaryRowTopOffset = 35,
    summaryLeftWidth = 132,
    summaryCurrencyWidth = 80,
    summaryColumnGap = 6,
    currencyRowTopOffset = 62,
    currencyRowInset = 6,
    playerIconSize = 22,
    playerSpecIconSize = 18,
    playerNameFontSize = 13,
    playerIlvlFontSize = 13,
    playerNameMaxWidth = 132,
    playerIlvlWidth = 58,
    playerIlvlGap = 6,
    currencyIconSize = 16,
    currencyIconPadding = 1,
    currencyIconTexCoord = { 0.08, 0.92, 0.08, 0.92 },
    summaryStatIconSize = 14,
    summaryStatLabelWidth = 58,
    summaryStatValueWidth = 42,
    summaryStatValueInset = 0,
    summaryStatRowHeight = 20,
    summaryStatGap = 3,
    summaryStatRowGap = 2,
    summaryLabelFontSize = 13,
    summaryValueFontSize = 14,
    currencyFontSize = 13,
    summaryText = PVE_STATS_WHITE,
    summaryMuted = PVE_STATS_GRAY,
    sectionTitle = { r = 0.73, g = 0.78, b = 0.91, a = 1 },
    summaryIconYOffset = 0,
    summaryStatIconYOffset = 1,
    currencyContentYOffset = -1,
    summaryAtlases = {
        vault = "GreatVault-32x32",
        season = "racing",
        week = "ChromieTime-32x32",
    },
    currencies = {
        { id = 3446, quality = 5, fallbackNameKey = "pve.stats.currency.myth", fallbackName = "神话纹章" },
        { id = 3445, quality = 4, fallbackNameKey = "pve.stats.currency.hero", fallbackName = "英雄纹章" },
        { id = 3444, quality = 3, fallbackNameKey = "pve.stats.currency.champion", fallbackName = "勇士纹章" },
    },
    vaultTitleTopOffset = 106,
    vaultTitleHeight = 14,
    vaultCardTopOffset = 124,
    vaultCardHeight = 30,
    vaultCardGap = 4,
    vaultRewardFontSize = 14,
    vaultTrackLabels = {
        [5] = { key = "pve.stats.vault.track.myth", fallback = "神话" },
        [4] = { key = "pve.stats.vault.track.hero", fallback = "英雄" },
        [3] = { key = "pve.stats.vault.track.champion", fallback = "勇士" },
    },
    vaultProgressHeight = 4,
    vaultProgressGap = 1,
    vaultProgressBaseAlpha = 0.55,
    topRunsTitleTopOffset = 158,
    topRunsTitleHeight = 16,
    topRunsTitleFontSize = 13,
    topRunsValuesTopOffset = 178,
    topRunsHeight = 20,
    topRunsSlotFontSize = 13,
    dungeonTitleTopOffset = 202,
    dungeonTitleHeight = 14,
    sectionTitleFontSize = 12,
    tileColumns = 2,
    tileGap = 4,
    tileMinHeight = 39,
    tileMaxHeight = 39,
    tileNameFontSize = 13,
    tileCountFontSize = 17,
    tileArtAlpha = 0.46,
    tileTintAlpha = 0.42,
    tooltipRunLimit = 25,
    tooltipRunsPerLine = 5,
    vaultDotColors = {
        empty = { r = 0.42, g = 0.48, b = 0.54 },
        low = { r = 0.1, g = 0.46, b = 0.95 },
        mid = { r = 0.64, g = 0.21, b = 0.93 },
        high = { r = 1, g = 0.5, b = 0 },
    },
    vaultProgressIncomplete = { r = 0, g = 0.44, b = 0.87, a = 1 },
    vaultProgressTrack = { r = 0.2, g = 0.22, b = 0.25, a = 0.92 },
    tileBg = { r = 0.03, g = 0.035, b = 0.045, a = 0.72 },
    topRunsBg = { r = 0.03, g = 0.035, b = 0.045, a = 0.38 },
    identityBgFill = { r = 0, g = 0, b = 0, a = 0.18 },
    identityBgBorder = { r = 0, g = 0, b = 0, a = 0.65 },
    identityDivider = { r = 0.3, g = 0.28, b = 0.27, a = 0.82 },
    identityDividerOffsets = { 32, 59 },
    tileBorder = { r = 0, g = 0, b = 0, a = 0.82 },
    tileDivider = { r = 1, g = 0.82, b = 0.1, a = 0.26 },
    tileBorderHover = { r = 1, g = 0.82, b = 0.1, a = 0.78 },
    tileDividerHover = { r = 1, g = 0.82, b = 0.1, a = 0.48 },
}

function PVEEnhancement.PartyKeystonePanel.SafeGetField(object, key)
    local objectType = type(object)
    if objectType ~= "table" and objectType ~= "userdata" then return nil end

    local ok, value = pcall(function()
        return object[key]
    end)
    if ok then return value end
    return nil
end

function PVEEnhancement.PartyKeystonePanel.SafeCallThirdParty(_, fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then
        return true, a, b, c, d
    end
    return false
end

function PVEEnhancement.PartyKeystonePanel.IsFrameLike(frame)
    local frameType = type(frame)
    return frameType == "table" or frameType == "userdata"
end

PVEEnhancement.defaults = {
    pveEnhancementEnabled = true,
    pveStatsPanelEnabled = true,
    pvePartyKeystonePanelEnabled = true,
    pveIconNameEnabled = true,
    pveIconLevelEnabled = true,
    pveIconScoreEnabled = true,
    pveRatingStatsEnabled = true,
    pveIconNameFontSize = ICON_NAME_FONT_SIZE,
    pveIconLevelFontSize = ICON_LEVEL_FONT_SIZE,
    pveIconScoreFontSize = ICON_SCORE_FONT_SIZE,
    pveIconLevelYOffset = ICON_LEVEL_Y_OFFSET,
    pveIconTextDefaultsVersion = ICON_TEXT_DEFAULTS_VERSION,
    pveTooltipEnabled = true,
    pveClickTeleportEnabled = true,
}

local featureActive = false
local runtimeActive = false
local hooksInstalled = false
local eventFrame
local statsPanel
local statsPanelDevData
local statsPanelRefreshToken = 0
local statsPanelEventsRegistered = false
local secureRefreshPending = false
local MarkSecureRefreshPending
local RefreshIconOverlay
local ShowPVEIconTooltip
local RefreshVisibleIconsNow
local QueueSettledVisibleIconRefresh
local EnsureIconShowHook
local RefreshStatsPanel
local QueueStatsPanelRefresh
local StatsPanelEventOwner = {}
local mapInfoCache = {}
local dungeonTeleportCache = {}

local StatsPanelAppearance = {
    fonts = setmetatable({}, { __mode = "k" }),
    fontStates = setmetatable({}, { __mode = "k" }),
    activeContext = nil,
}
PVEEnhancement.StatsPanel._appearance = StatsPanelAppearance

function PVEEnhancement.StatsPanel.RegisterSharedAppearanceConsumer()
    if PVEEnhancement.StatsPanel._sharedAppearanceConsumerRegistered then return true end
    local appearance = YUI.GUI2 and YUI.GUI2.WindowAppearance
    if not appearance or type(appearance.RegisterConsumer) ~= "function" then return false end

    appearance:RegisterConsumer(PVEEnhancement.StatsPanel, function()
        if runtimeActive and statsPanel then
            PVEEnhancement.StatsPanel.ApplySkin(statsPanel)
        end
    end)
    PVEEnhancement.StatsPanel._sharedAppearanceConsumerRegistered = true
    return true
end

function PVEEnhancement.StatsPanel.UnregisterSharedAppearanceConsumer()
    if not PVEEnhancement.StatsPanel._sharedAppearanceConsumerRegistered then return end
    local appearance = YUI.GUI2 and YUI.GUI2.WindowAppearance
    if appearance and type(appearance.UnregisterConsumer) == "function" then
        appearance:UnregisterConsumer(PVEEnhancement.StatsPanel)
    end
    if appearance and type(appearance.ReleaseExternalShell) == "function" and statsPanel then
        appearance:ReleaseExternalShell(statsPanel)
    end
    PVEEnhancement.StatsPanel._sharedAppearanceConsumerRegistered = false
end

local function ClearDungeonInfoCaches()
    mapInfoCache = {}
    dungeonTeleportCache = {}
end

local DUNGEON_TELEPORTS = {
    {
        mapID = 588,
        spellID = 1286812,
        short = { zhCN = "毒牙", zhTW = "毒牙", enUS = "FANG" },
        keywords = { "毒牙", "毒牙祭壇", "Altar of Fangs" },
    },
    {
        mapID = 587,
        spellID = 1286809,
        short = { zhCN = "密谋", zhTW = "兇殺", enUS = "MURD" },
        keywords = { "密谋", "谋杀", "兇殺", "Murder Row" },
    },
    {
        mapID = 586,
        spellID = 1286807,
        short = { zhCN = "纳洛", zhTW = "納羅", enUS = "NALO" },
        keywords = { "纳洛拉克", "納羅拉克", "Nalorakk" },
    },
    {
        mapID = 584,
        spellID = 1286801,
        short = { zhCN = "夺目", zhTW = "盲目", enUS = "VALE" },
        keywords = { "夺目", "致盲", "盲目", "Blinding Vale" },
    },
    {
        mapID = 585,
        spellID = 1286804,
        short = { zhCN = "虚痕", zhTW = "虛痕", enUS = "VOID" },
        keywords = { "虚痕", "虚空之痕", "虛無之痕", "Voidscar" },
    },
    {
        mapID = 249,
        spellID = 1286831,
        short = { zhCN = "诸王", zhTW = "諸王", enUS = "KR" },
        keywords = { "诸王", "諸王", "King's Rest", "Kings' Rest" },
    },
    {
        mapID = 399,
        spellID = 393256,
        short = { zhCN = "红玉", zhTW = "晶紅", enUS = "RLP" },
        keywords = { "红玉", "晶紅", "Ruby Life Pools" },
    },
    {
        mapID = 250,
        spellID = 1286828,
        short = { zhCN = "神庙", zhTW = "神廟", enUS = "TOS" },
        keywords = { "塞塔里斯", "瑟沙利斯", "Sethraliss" },
    },
    {
        spellID = 1254572,
        short = { zhCN = "魔导", zhTW = "博學者", enUS = "Magist" },
        keywords = { "魔导", "博學者", "Magist", "Magisters" },
    },
    {
        spellID = 1254400,
        short = { zhCN = "风行", zhTW = "風行者", enUS = "Windr" },
        keywords = { "风行", "風行", "Windrunner", "Windr" },
    },
    {
        spellID = 1254557,
        variants = { Horde = 159898, Alliance = 1254557 },
        short = { zhCN = "通天", zhTW = "擎天", enUS = "Skyreach" },
        keywords = { "通天", "擎天", "Skyreach" },
    },
    {
        spellID = 1254559,
        short = { zhCN = "洞窟", zhTW = "洞窟", enUS = "Cave" },
        keywords = { "洞窟", "Cave" },
    },
    {
        spellID = 1254555,
        short = { zhCN = "萨隆", zhTW = "薩倫", enUS = "Saron" },
        keywords = { "萨隆", "薩倫", "Saron" },
    },
    {
        spellID = 1254563,
        short = { zhCN = "节点", zhTW = "節點", enUS = "NPX" },
        keywords = { "节点", "節點", "奧核", "Nexus", "NPX" },
    },
    {
        spellID = 393273,
        short = { zhCN = "学院", zhTW = "學院", enUS = "Academy" },
        keywords = { "学院", "學院", "Academy" },
    },
    {
        spellID = 1254551,
        short = { zhCN = "执政", zhTW = "統御", enUS = "Seat" },
        keywords = { "执政", "執政", "統御", "Seat" },
    },
}

local DUNGEON_TELEPORTS_BY_MAP_ID = {}
for _, data in ipairs(DUNGEON_TELEPORTS) do
    if data.mapID then
        DUNGEON_TELEPORTS_BY_MAP_ID[data.mapID] = data
    end
end

local function T(key, fallback)
    if Tools.T then
        return Tools:T(key, fallback)
    end
    return (L and L[key]) or fallback or key
end

local function ClampNumber(value, minValue, maxValue, defaultValue)
    value = tonumber(value)
    if not value then value = defaultValue end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function MigrateIconTextDefault(db, key, oldValue, newValue)
    local value = tonumber(db[key])
    if db[key] == nil or value == oldValue then
        db[key] = newValue
    end
end

local function MigrateIconTextDefaults(db)
    if db.pveIconTextDefaultsVersion == ICON_TEXT_DEFAULTS_VERSION then return end

    MigrateIconTextDefault(db, "pveIconNameFontSize", OLD_ICON_NAME_FONT_SIZE, ICON_NAME_FONT_SIZE)
    MigrateIconTextDefault(db, "pveIconLevelFontSize", OLD_ICON_LEVEL_FONT_SIZE, ICON_LEVEL_FONT_SIZE)
    MigrateIconTextDefault(db, "pveIconScoreFontSize", OLD_ICON_SCORE_FONT_SIZE, ICON_SCORE_FONT_SIZE)
    MigrateIconTextDefault(db, "pveIconLevelYOffset", OLD_ICON_LEVEL_Y_OFFSET, ICON_LEVEL_Y_OFFSET)
    db.pveIconTextDefaultsVersion = ICON_TEXT_DEFAULTS_VERSION
end

local function NormalizeDB(db)
    if type(db) ~= "table" then db = PVEEnhancement.defaults end
    if db.pveEnhancementEnabled == nil then db.pveEnhancementEnabled = true else db.pveEnhancementEnabled = db.pveEnhancementEnabled == true end
    if db.pveStatsPanelEnabled == nil then db.pveStatsPanelEnabled = true else db.pveStatsPanelEnabled = db.pveStatsPanelEnabled == true end
    if db.pvePartyKeystonePanelEnabled == nil then db.pvePartyKeystonePanelEnabled = true else db.pvePartyKeystonePanelEnabled = db.pvePartyKeystonePanelEnabled == true end
    if db.pveIconNameEnabled == nil then db.pveIconNameEnabled = true else db.pveIconNameEnabled = db.pveIconNameEnabled == true end
    if db.pveIconLevelEnabled == nil then db.pveIconLevelEnabled = true else db.pveIconLevelEnabled = db.pveIconLevelEnabled == true end
    if db.pveIconScoreEnabled == nil then db.pveIconScoreEnabled = true else db.pveIconScoreEnabled = db.pveIconScoreEnabled == true end
    if db.pveRatingStatsEnabled == nil then db.pveRatingStatsEnabled = true else db.pveRatingStatsEnabled = db.pveRatingStatsEnabled == true end
    MigrateIconTextDefaults(db)
    db.pveIconNameFontSize = ClampNumber(db.pveIconNameFontSize, ICON_NAME_SIZE_MIN, ICON_NAME_SIZE_MAX, PVEEnhancement.defaults.pveIconNameFontSize)
    db.pveIconLevelFontSize = ClampNumber(db.pveIconLevelFontSize, ICON_LEVEL_SIZE_MIN, ICON_LEVEL_SIZE_MAX, PVEEnhancement.defaults.pveIconLevelFontSize)
    db.pveIconScoreFontSize = ClampNumber(db.pveIconScoreFontSize, ICON_SCORE_SIZE_MIN, ICON_SCORE_SIZE_MAX, PVEEnhancement.defaults.pveIconScoreFontSize)
    db.pveIconLevelYOffset = ClampNumber(db.pveIconLevelYOffset, ICON_LEVEL_Y_OFFSET_MIN, ICON_LEVEL_Y_OFFSET_MAX, PVEEnhancement.defaults.pveIconLevelYOffset)
    if db.pveTooltipEnabled == nil then db.pveTooltipEnabled = true else db.pveTooltipEnabled = db.pveTooltipEnabled == true end
    if db.pveClickTeleportEnabled == nil then db.pveClickTeleportEnabled = true else db.pveClickTeleportEnabled = db.pveClickTeleportEnabled == true end
    return db
end

local function GetDB(db)
    if type(db) ~= "table" and Tools.GetDB then
        db = Tools:GetDB()
    end
    return NormalizeDB(db)
end

local function IsRuntimeEnabled(db)
    db = GetDB(db)
    return featureActive and runtimeActive and db.pveEnhancementEnabled == true
end

local function GetFrameMapID(frame, mapInfo)
    if mapInfo and mapInfo.id then return mapInfo.id end
    if not frame then return nil end
    if frame.mapID then return frame.mapID end
    if frame.yuiPVEMapID then return frame.yuiPVEMapID end
    return frame.yuiPVEState and frame.yuiPVEState.mapID or nil
end

local function CacheFrameMapInfo(frame, mapInfo)
    if not (frame and mapInfo and mapInfo.id) then return end

    frame.yuiPVEMapID = mapInfo.id
    if mapInfo.name then
        frame.yuiPVECachedMapInfo = {
            id = mapInfo.id,
            name = mapInfo.name,
            timeLimit = tonumber(mapInfo.timeLimit) or 0,
        }
    end
end

local function GetCachedMapInfo(frame, mapID)
    local cached = frame and frame.yuiPVECachedMapInfo
    if cached and cached.id == mapID and cached.name then
        return cached
    end
    return nil
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if ok then return a, b, c, d, e end
    return nil
end

local function InCombatLockdownSafe()
    if SecurityAPI and SecurityAPI.InCombatLockdown then
        return SecurityAPI.InCombatLockdown() == true
    end
    if InCombatLockdown then
        return InCombatLockdown() == true
    end
    return false
end

local function Round(value)
    value = tonumber(value) or 0
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

local function GetLocaleKey()
    local locale = GetLocale and GetLocale() or "enUS"
    if locale == "zhCN" or locale == "zhTW" then return locale end
    return "enUS"
end

local function ColorText(text, color)
    text = tostring(text or "")
    if not color then return text end
    if color.WrapTextInColorCode then
        return color:WrapTextInColorCode(text)
    end

    local r = math.max(0, math.min(255, Round((color.r or 1) * 255)))
    local g = math.max(0, math.min(255, Round((color.g or 1) * 255)))
    local b = math.max(0, math.min(255, Round((color.b or 1) * 255)))
    return string.format("|cff%02x%02x%02x%s|r", r, g, b, text)
end

local function GetClassFileByID(classID)
    classID = tonumber(classID)
    if not classID then return nil end

    if UnitAPI and UnitAPI.GetClassInfoByID then
        local info = UnitAPI.GetClassInfoByID(classID)
        if info and info.classFile then return info.classFile end
    end

    if UnitAPI and UnitAPI.GetClassInfo then
        local info = UnitAPI.GetClassInfo(classID)
        if info and info.classFile then return info.classFile end
    end

    if GetClassInfo then
        local _, classFile = SafeCall(GetClassInfo, classID)
        if classFile then return classFile end
    end

    return nil
end

local function GetClassColorByFile(classFile)
    if not classFile then return nil end

    if UnitAPI and UnitAPI.GetClassColor then
        local color = UnitAPI.GetClassColor(classFile)
        if color then return color end
    end

    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    return colors and colors[classFile] or nil
end

local function GetClassColorByID(classID)
    return GetClassColorByFile(GetClassFileByID(classID))
end

local function ColorPlayerName(name, classID)
    local color = GetClassColorByID(classID)
    if not color then return name end
    return ColorText(name, color)
end

local function SetTextColor(fontString, color, fallback)
    if not fontString or not fontString.SetTextColor then return end
    color = color or fallback
    if color then
        fontString:SetTextColor(color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1, color.a or color[4] or 1)
    else
        fontString:SetTextColor(1, 1, 1, 1)
    end
end

function PVEEnhancement.StatsPanel.SetTextureColor(texture, color, fallback)
    if not texture or not texture.SetColorTexture then return end
    color = color or fallback or PVE_STATS_GRAY
    texture:SetColorTexture(color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1, color.a or color[4] or 1)
end

function PVEEnhancement.StatsPanel.SetTextureVertexColor(texture, color, fallback)
    if not texture then return end
    color = color or fallback or PVE_STATS_GRAY
    if texture.SetVertexColor then
        texture:SetVertexColor(color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1, color.a or color[4] or 1)
    elseif texture.SetColorTexture then
        texture:SetColorTexture(color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1, color.a or color[4] or 1)
    end
end

function PVEEnhancement.StatsPanel.GetPixelSize(region, desiredPixels)
    desiredPixels = desiredPixels or 1
    if PixelUtil and PixelUtil.GetPixelToUIUnitFactor and PixelUtil.GetNearestPixelSize and region and region.GetEffectiveScale then
        local scale = region:GetEffectiveScale()
        if scale and scale > 0 then
            local okFactor, uiUnitFactor = pcall(PixelUtil.GetPixelToUIUnitFactor)
            if okFactor and type(uiUnitFactor) == "number" and uiUnitFactor > 0 then
                local uiUnits = uiUnitFactor * desiredPixels / scale
                local okSize, size = pcall(PixelUtil.GetNearestPixelSize, uiUnits, scale, 1)
                if okSize and type(size) == "number" and size > 0 then
                    return size
                end
            end
        end
    end
    return ((YUI.GUI2 and YUI.GUI2.mult) or 1) * desiredPixels
end

function PVEEnhancement.StatsPanel.GetDotTexture()
    if not PVEEnhancement.StatsPanel.dotTexture then
        local assets = YUI.Assets
        PVEEnhancement.StatsPanel.dotTexture = assets and assets.Core and assets:Core("gui2\\glyphs\\layout-anchor-dot-16.tga") or "Interface\\COMMON\\Indicator-Gray"
    end
    return PVEEnhancement.StatsPanel.dotTexture
end

function PVEEnhancement.StatsPanel.GetPlayerClassFile()
    local classFile
    if UnitAPI and UnitAPI.UnitClass then
        _, classFile = SafeCall(UnitAPI.UnitClass, "player")
    elseif UnitClass then
        _, classFile = SafeCall(UnitClass, "player")
    end
    return classFile
end

function PVEEnhancement.StatsPanel.GetPlayerDisplayName()
    local name
    if UnitAPI and UnitAPI.UnitName then
        name = SafeCall(UnitAPI.UnitName, "player")
    elseif UnitName then
        name = SafeCall(UnitName, "player")
    end
    return name or (UNKNOWN or "")
end

function PVEEnhancement.StatsPanel.GetPlayerEquippedItemLevelText()
    if not GetAverageItemLevel then return "-" end
    local overall, equipped = SafeCall(GetAverageItemLevel)
    local value = tonumber(equipped) or tonumber(overall)
    if not value then return "-" end
    return tostring(Round(value))
end

function PVEEnhancement.StatsPanel.GetPlayerRaceData()
    local raceFile
    if UnitRace then
        _, raceFile = SafeCall(UnitRace, "player")
    end

    local gender
    if UnitSex then
        gender = SafeCall(UnitSex, "player")
    end

    if type(raceFile) ~= "string" or raceFile == "" then return nil end
    return {
        kind = "player",
        raceFile = raceFile,
        gender = gender,
    }
end

function PVEEnhancement.StatsPanel.GetPlayerRaceIconData()
    local data = PVEEnhancement.StatsPanel.GetPlayerRaceData()
    if not data then return nil end

    local icons = YUI.API and YUI.API.Icons
    if icons and icons.GetRaceIcon then
        return icons.GetRaceIcon(data.raceFile, data.gender)
    end
    return nil
end

function PVEEnhancement.StatsPanel.ApplyPlayerRaceIcon(target)
    local texture = target and (target.icon or target)
    local data = PVEEnhancement.StatsPanel.GetPlayerRaceData()
    if not target or not texture or not data or data.kind ~= "player" then
        if texture and texture.SetTexture then
            texture:SetTexture(nil)
        end
        if texture and texture.Hide and texture ~= target then
            texture:Hide()
        end
        if target and target.Hide then
            target:Hide()
        end
        return false
    end

    local icons = YUI.API and YUI.API.Icons
    local icon = data and icons and icons.GetRaceIcon and icons.GetRaceIcon(data.raceFile, data.gender)
    local applied = icon and icons.ApplyIcon and icons.ApplyIcon(texture, icon)
    if applied then
        if target.Show then target:Show() end
        if texture.Show then texture:Show() end
        return true
    end

    if texture.SetTexture then texture:SetTexture(nil) end
    if texture.Hide and texture ~= target then texture:Hide() end
    if target.Hide then target:Hide() end
    return false
end

function PVEEnhancement.StatsPanel.GetPlayerSpecIconData()
    local specIndex
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        specIndex = SafeCall(C_SpecializationInfo.GetSpecialization)
    elseif GetSpecialization then
        specIndex = SafeCall(GetSpecialization)
    end

    local specID, nativeIcon
    if specIndex then
        if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
            specID, _, _, nativeIcon = SafeCall(C_SpecializationInfo.GetSpecializationInfo, specIndex)
        elseif GetSpecializationInfo then
            specID, _, _, nativeIcon = SafeCall(GetSpecializationInfo, specIndex)
        end
    end

    local icons = YUI.API and YUI.API.Icons
    if icons and icons.GetSpecIcon then
        local iconData = icons.GetSpecIcon(specID)
        if iconData then return iconData end
    end
    if nativeIcon then
        return { texture = nativeIcon }
    end
    return nil
end

function PVEEnhancement.StatsPanel.ApplyIcon(texture, iconData)
    if not texture then return false end
    local icons = YUI.API and YUI.API.Icons
    local applied = icons and icons.ApplyIcon and icons.ApplyIcon(texture, iconData)
    if applied then
        texture:Show()
        return true
    end
    if type(iconData) == "table" then
        if iconData.atlas and texture.SetAtlas then
            texture:SetAtlas(iconData.atlas, false)
            if iconData.texCoord and texture.SetTexCoord then texture:SetTexCoord(unpack(iconData.texCoord)) end
            texture:Show()
            return true
        elseif iconData.texture ~= nil and texture.SetTexture then
            texture:SetTexture(iconData.texture)
            if iconData.texCoord and texture.SetTexCoord then
                texture:SetTexCoord(unpack(iconData.texCoord))
            elseif texture.SetTexCoord then
                texture:SetTexCoord(0, 1, 0, 1)
            end
            texture:Show()
            return true
        end
    end
    texture:Hide()
    return false
end

function PVEEnhancement.StatsPanel.GetVaultDotColor(level)
    level = tonumber(level) or 0
    if level >= 10 then return PVEEnhancement.StatsPanel.vaultDotColors.high end
    if level >= 2 then return PVEEnhancement.StatsPanel.vaultDotColors.mid end
    return PVEEnhancement.StatsPanel.vaultDotColors.low
end

function PVEEnhancement.StatsPanel.GetVaultRunQuality(level)
    level = tonumber(level) or 0
    if level >= 10 then return 5 end
    if level >= 6 then return 4 end
    if level >= 2 then return 3 end
    return nil
end

local function GetScoreColor(score)
    score = tonumber(score) or 0
    if score <= 0 then
        return LIGHTGRAY_FONT_COLOR or { r = 0.62, g = 0.62, b = 0.62 }
    end
    local keystone = YUI.API and YUI.API.Keystone
    if keystone and type(keystone.GetSpecificDungeonScoreColor) == "function" then
        local color = keystone.GetSpecificDungeonScoreColor(score)
        if color then return color end
    end
    if C_ChallengeMode and C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor then
        return SafeCall(C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor, score) or HIGHLIGHT_FONT_COLOR
    end
    return HIGHLIGHT_FONT_COLOR
end

local function GetLevelColor(level)
    level = tonumber(level) or 0
    local keystone = YUI.API and YUI.API.Keystone
    if keystone and type(keystone.GetKeystoneLevelColor) == "function" then
        local color = keystone.GetKeystoneLevelColor(level)
        if color then return color end
    end
    local qualityIndex
    if level >= 12 then
        qualityIndex = 5
    elseif level >= 9 then
        qualityIndex = 4
    elseif level >= 4 then
        qualityIndex = 3
    else
        qualityIndex = 2
    end

    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[qualityIndex]
    if color then return color end
    if qualityIndex == 5 then return { r = 1, g = 0.5, b = 0 } end
    if qualityIndex == 4 then return { r = 0.64, g = 0.21, b = 0.93 } end
    if qualityIndex == 3 then return { r = 0, g = 0.44, b = 0.87 } end
    return { r = 0.12, g = 1, b = 0 }
end

function PVEEnhancement.StatsPanel.GetQualityColor(qualityIndex)
    qualityIndex = tonumber(qualityIndex)
    local color = qualityIndex and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[qualityIndex]
    if color then return color end
    if qualityIndex == 5 then return { r = 1, g = 0.5, b = 0 } end
    if qualityIndex == 4 then return { r = 0.64, g = 0.21, b = 0.93 } end
    if qualityIndex == 3 then return { r = 0, g = 0.44, b = 0.87 } end
    return PVEEnhancement.StatsPanel.summaryText
end

function PVEEnhancement.StatsPanel.GetCurrencyAmountColor(config, quantity)
    quantity = tonumber(quantity) or 0
    if quantity <= 0 then
        return PVEEnhancement.StatsPanel.summaryMuted
    end
    return PVEEnhancement.StatsPanel.GetQualityColor(config and config.quality)
end

function PVEEnhancement.StatsPanel.GetVaultActivities()
    local thresholdType = Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Activities
    if not (thresholdType and C_WeeklyRewards and C_WeeklyRewards.GetActivities) then return nil end

    local activities = SafeCall(C_WeeklyRewards.GetActivities, thresholdType)
    if type(activities) ~= "table" or #activities == 0 then return nil end

    local result = {}
    for _, activity in ipairs(activities) do
        if type(activity) == "table" and (activity.type == nil or activity.type == thresholdType) then
            result[#result + 1] = activity
        end
    end
    table.sort(result, function(a, b)
        local thresholdA = tonumber(a and a.threshold) or math.huge
        local thresholdB = tonumber(b and b.threshold) or math.huge
        if thresholdA ~= thresholdB then return thresholdA < thresholdB end
        return (tonumber(a and a.index) or math.huge) < (tonumber(b and b.index) or math.huge)
    end)
    return result
end

function PVEEnhancement.StatsPanel.GetRewardTrackQuality(itemLink, tooltipData)
    if tooltipData == nil and itemLink and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        tooltipData = SafeCall(C_TooltipInfo.GetHyperlink, itemLink)
    end
    if type(tooltipData) ~= "table" or type(tooltipData.lines) ~= "table" then return nil end

    local upgradeLineType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemUpgradeLevel or 32
    for _, line in ipairs(tooltipData.lines) do
        local lineType = line and line.type
        if lineType == upgradeLineType then
            local leftText = type(line.leftText) == "string" and line.leftText or ""
            local rightText = type(line.rightText) == "string" and line.rightText or ""
            local text = leftText .. " " .. rightText
            local normalized = string.lower(text)
            if string.find(normalized, "神话", 1, true) or string.find(normalized, "神話", 1, true) or string.find(normalized, "myth", 1, true) then
                return 5
            end
            if string.find(normalized, "英雄", 1, true) or string.find(normalized, "hero", 1, true) then
                return 4
            end
            if string.find(normalized, "勇士", 1, true) or string.find(normalized, "champion", 1, true) then
                return 3
            end
        end
    end
    return nil
end

function PVEEnhancement.StatsPanel.GetVaultRewardInfo(activity)
    if type(activity) ~= "table" or not activity.id then return nil, nil, nil end
    if not (C_WeeklyRewards and C_WeeklyRewards.GetExampleRewardItemHyperlinks) then return nil, nil, nil end

    local itemLink = SafeCall(C_WeeklyRewards.GetExampleRewardItemHyperlinks, activity.id)
    if not itemLink then return nil, nil, nil end

    local itemLevel
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        itemLevel = SafeCall(C_Item.GetDetailedItemLevelInfo, itemLink)
    end
    return tonumber(itemLevel), PVEEnhancement.StatsPanel.GetRewardTrackQuality(itemLink), itemLink
end

function PVEEnhancement.StatsPanel.GetVaultIconAtlas(state)
    if state == "collect" then return "gficon-chest-evergreen-greatvault-collect" end
    if state == "complete" then return "gficon-chest-evergreen-greatvault-complete" end
    return "gficon-chest-evergreen-greatvault-incomplete"
end

function PVEEnhancement.StatsPanel.BuildVaultCards(weeklyCount, weeklyRuns, overrideProgress)
    weeklyCount = tonumber(weeklyCount) or 0
    weeklyRuns = type(weeklyRuns) == "table" and weeklyRuns or {}
    local activities = PVEEnhancement.StatsPanel.GetVaultActivities() or {}
    local defaults = { 1, 4, 8 }
    local cards = {}

    for index = 1, 3 do
        local activity = activities[index]
        local threshold = tonumber(activity and activity.threshold) or defaults[index]
        local progress = overrideProgress == true and weeklyCount or (tonumber(activity and activity.progress) or weeklyCount)
        local fallbackRun = weeklyRuns[math.min(math.max(threshold, 1), #weeklyRuns)]
        local level = tonumber(activity and activity.level) or tonumber(fallbackRun and fallbackRun.level)
        local unlocked = threshold > 0 and progress >= threshold
        local itemLevel, quality, itemLink = PVEEnhancement.StatsPanel.GetVaultRewardInfo(activity)
        local state = unlocked and "complete" or "incomplete"
        local hasClaimReward = overrideProgress ~= true and activity and type(activity.rewards) == "table" and #activity.rewards > 0
        if hasClaimReward then state = "collect" end
        cards[index] = {
            activity = activity,
            threshold = threshold,
            progress = progress,
            fraction = threshold > 0 and math.max(0, math.min(1, progress / threshold)) or 0,
            unlocked = unlocked,
            state = state,
            level = level,
            itemLevel = itemLevel,
            quality = quality,
            itemLink = itemLink,
        }
    end
    return cards
end

function PVEEnhancement.StatsPanel.BuildVaultProgressSegments(card, weeklyRuns)
    card = card or {}
    weeklyRuns = type(weeklyRuns) == "table" and weeklyRuns or {}
    local threshold = math.max(1, math.floor(tonumber(card.threshold) or 1))
    local sortedRuns = {}
    for _, run in ipairs(weeklyRuns) do
        if type(run) == "table" then
            sortedRuns[#sortedRuns + 1] = run
        end
    end
    table.sort(sortedRuns, function(a, b)
        local levelA = tonumber(a.level) or 0
        local levelB = tonumber(b.level) or 0
        if levelA ~= levelB then return levelA > levelB end
        local dateA = tonumber(a.dateValue) or 0
        local dateB = tonumber(b.dateValue) or 0
        if dateA ~= dateB then return dateA > dateB end
        return (tonumber(a.mapID) or 0) < (tonumber(b.mapID) or 0)
    end)

    local segments = {}
    for index = 1, threshold do
        local run = sortedRuns[index]
        segments[index] = {
            filled = run ~= nil,
            level = run and (tonumber(run.level) or 0) or nil,
            quality = run and PVEEnhancement.StatsPanel.GetVaultRunQuality(run.level) or nil,
        }
    end
    return segments
end

function PVEEnhancement.StatsPanel.GetVaultRewardParts(card)
    card = card or {}
    local itemLevel = tonumber(card.itemLevel)
    if itemLevel then
        local track = PVEEnhancement.StatsPanel.vaultTrackLabels[tonumber(card.quality)]
        return tostring(itemLevel), track and T(track.key, track.fallback) or ""
    end
    return "--", ""
end

function PVEEnhancement.StatsPanel.FormatVaultRewardText(card)
    local value, track = PVEEnhancement.StatsPanel.GetVaultRewardParts(card)
    return track ~= "" and (value .. " " .. track) or value
end

function PVEEnhancement.StatsPanel.BuildTopRunSlots(runs)
    runs = type(runs) == "table" and runs or {}
    local slots = {}
    for index = 1, PVEEnhancement.StatsPanel.topRunLimit do
        local run = runs[index]
        if run then
            slots[index] = {
                text = "+" .. tostring(tonumber(run.level) or 0),
                color = run.inTime == true and DURATION_IN_TIME_COLOR or DURATION_OVERTIME_COLOR,
            }
        else
            slots[index] = { text = "—", color = PVE_STATS_GRAY }
        end
    end
    return slots
end

function PVEEnhancement.StatsPanel.FormatTopRuns(runs)
    local parts = {}
    for index, slot in ipairs(PVEEnhancement.StatsPanel.BuildTopRunSlots(runs)) do
        parts[index] = ColorText(slot.text, slot.color)
    end
    return table.concat(parts, " ")
end

local function GetMapInfo(mapID)
    mapID = tonumber(mapID)
    if not (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and mapID) then return nil end
    local cached = mapInfoCache[mapID]
    if cached then return cached end

    local name, id, timeLimit, texture, backgroundTexture, journalMapID = SafeCall(C_ChallengeMode.GetMapUIInfo, mapID)
    if not name then return nil end
    local mapInfo = {
        name = name,
        id = id,
        timeLimit = tonumber(timeLimit) or 0,
        texture = texture,
        backgroundTexture = backgroundTexture,
        journalMapID = journalMapID,
    }
    mapInfoCache[mapID] = mapInfo
    return mapInfo
end

local function SelectBestRun(mapID)
    if not (C_MythicPlus and C_MythicPlus.GetSeasonBestForMap and mapID) then return nil end
    local inTimeInfo, overtimeInfo = SafeCall(C_MythicPlus.GetSeasonBestForMap, mapID)

    if inTimeInfo and overtimeInfo then
        local inTimeScore = tonumber(inTimeInfo.dungeonScore) or 0
        local overtimeScore = tonumber(overtimeInfo.dungeonScore) or 0
        if inTimeScore >= overtimeScore then
            return inTimeInfo, true
        end
        return overtimeInfo, false
    end

    if inTimeInfo then return inTimeInfo, true end
    if overtimeInfo then return overtimeInfo, false end
    return nil
end

local function GetDungeonScore(mapID, bestRun)
    local score
    if C_MythicPlus and C_MythicPlus.GetSeasonBestAffixScoreInfoForMap then
        local _, overallScore = SafeCall(C_MythicPlus.GetSeasonBestAffixScoreInfoForMap, mapID)
        score = tonumber(overallScore)
    end
    if not score and bestRun then
        score = tonumber(bestRun.dungeonScore)
    end
    return Round(score or 0)
end

local function ContainsKeyword(text, keyword)
    if type(text) ~= "string" or type(keyword) ~= "string" or keyword == "" then return false end
    if string.find(text, keyword, 1, true) then return true end
    return string.find(string.lower(text), string.lower(keyword), 1, true) ~= nil
end

local function FindDungeonTeleport(mapID, mapName)
    mapID = tonumber(mapID)
    if mapID and DUNGEON_TELEPORTS_BY_MAP_ID[mapID] then
        return DUNGEON_TELEPORTS_BY_MAP_ID[mapID]
    end
    if type(mapName) ~= "string" then return nil end
    local cached = dungeonTeleportCache[mapName]
    if cached ~= nil then
        return cached or nil
    end

    for _, data in ipairs(DUNGEON_TELEPORTS) do
        for _, keyword in ipairs(data.keywords) do
            if ContainsKeyword(mapName, keyword) then
                dungeonTeleportCache[mapName] = data
                return data
            end
        end
    end
    dungeonTeleportCache[mapName] = false
    return nil
end

local function GetShortName(mapName, dungeonData)
    if dungeonData and dungeonData.short then
        return dungeonData.short[GetLocaleKey()] or dungeonData.short.enUS or mapName
    end
    return mapName or ""
end

local function IsSpellKnownSafe(spellID)
    if SpellAPI and SpellAPI.IsKnown then
        return SpellAPI.IsKnown(spellID) == true
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(spellID) == true
    end
    if _G.IsSpellKnown then
        return _G.IsSpellKnown(spellID) == true
    end
    return false
end

local function ResolveKnownTeleportSpell(dungeonData)
    if not dungeonData then return nil end

    local variants = dungeonData.variants
    if variants then
        local faction = UnitFactionGroup and UnitFactionGroup("player") or ""
        local prefer = (faction == "Horde") and variants.Horde or variants.Alliance
        local fallback = (prefer == variants.Horde) and variants.Alliance or variants.Horde
        if prefer and IsSpellKnownSafe(prefer) then return prefer end
        if fallback and IsSpellKnownSafe(fallback) then return fallback end
    end

    if dungeonData.spellID and IsSpellKnownSafe(dungeonData.spellID) then
        return dungeonData.spellID
    end
    return nil
end

local function GetCooldownRemaining(spellID)
    if not spellID then return 0 end

    local info = SpellAPI and SpellAPI.GetCooldown and SpellAPI.GetCooldown(spellID) or nil
    if not info and C_Spell and C_Spell.GetSpellCooldown then
        info = SafeCall(C_Spell.GetSpellCooldown, spellID)
    end

    local startTime = tonumber(info and info.startTime) or 0
    local duration = tonumber(info and info.duration) or 0
    if (startTime <= 0 or duration <= 0) and GetSpellCooldown then
        local start, cooldownDuration = SafeCall(GetSpellCooldown, spellID)
        startTime = tonumber(start) or 0
        duration = tonumber(cooldownDuration) or 0
    end

    if startTime <= 0 or duration <= 2 then return 0 end

    local now = GetTime and GetTime() or 0
    return math.max(0, startTime + duration - now)
end

local function FormatDuration(seconds, forceHours)
    seconds = math.max(0, math.ceil(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if forceHours or hours > 0 then
        return string.format("%02d:%02d:%02d", hours, minutes, secs)
    end
    return string.format("%02d:%02d", minutes, secs)
end

local function FormatDate(dateInfo)
    if type(dateInfo) ~= "table" then return nil end
    local year = tonumber(dateInfo.year)
    local month = tonumber(dateInfo.month)
    local day = tonumber(dateInfo.day)
    local hour = tonumber(dateInfo.hour)
    local minute = tonumber(dateInfo.minute)
    if not (year and month and day and hour and minute) then return nil end
    if year >= 100 then year = year % 100 end
    return string.format("%02d/%02d/%02d %02d:%02d", year, month, day, hour, minute)
end

local function NormalizeName(name)
    if type(name) ~= "string" then return nil end
    if Ambiguate then
        name = Ambiguate(name, "short")
    end
    return name
end

local function GetNativeSpecIcon(specID)
    specID = tonumber(specID)
    if not specID then return nil end

    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoForSpecID then
        local _, _, _, icon = SafeCall(C_SpecializationInfo.GetSpecializationInfoForSpecID, specID)
        if icon then return icon end
    end

    if GetSpecializationInfoByID then
        local _, _, _, icon = SafeCall(GetSpecializationInfoByID, specID)
        if icon then return icon end
    end

    return nil
end

local function FormatTextureTag(texture, size, dimension, left, right, top, bottom)
    if texture == nil then return nil end
    return string.format("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t",
        tostring(texture), size, size, dimension, dimension, left, right, top, bottom)
end

local function FormatNativeSpecIconTag(texture)
    return FormatTextureTag(
        texture,
        SPEC_TOOLTIP_ICON_SIZE,
        SPEC_TOOLTIP_NATIVE_DIMENSION,
        SPEC_TOOLTIP_NATIVE_CROP[1],
        SPEC_TOOLTIP_NATIVE_CROP[2],
        SPEC_TOOLTIP_NATIVE_CROP[3],
        SPEC_TOOLTIP_NATIVE_CROP[4]
    )
end

local function GetCustomSpecIconPixels(texCoord)
    if type(texCoord) ~= "table" then return nil end

    local left = Round((tonumber(texCoord[1]) or 0) * SPEC_TOOLTIP_CUSTOM_DIMENSION)
    local right = Round((tonumber(texCoord[2]) or 0) * SPEC_TOOLTIP_CUSTOM_DIMENSION)
    local top = Round((tonumber(texCoord[3]) or 0) * SPEC_TOOLTIP_CUSTOM_DIMENSION)
    local bottom = Round((tonumber(texCoord[4]) or 0) * SPEC_TOOLTIP_CUSTOM_DIMENSION)
    if right <= left or bottom <= top then return nil end
    return left, right, top, bottom
end

local function FormatYUISpecIconTag(iconData)
    if type(iconData) ~= "table" then return nil end

    if iconData.custom == true and iconData.texture and iconData.texCoord then
        local left, right, top, bottom = GetCustomSpecIconPixels(iconData.texCoord)
        if left then
            return FormatTextureTag(iconData.texture, SPEC_TOOLTIP_ICON_SIZE, SPEC_TOOLTIP_CUSTOM_DIMENSION, left, right, top, bottom)
        end
    end

    if iconData.atlas then
        return string.format("|A:%s:%d:%d:0:0|a", tostring(iconData.atlas), SPEC_TOOLTIP_ICON_SIZE, SPEC_TOOLTIP_ICON_SIZE)
    end

    if iconData.texture then
        return FormatNativeSpecIconTag(iconData.texture)
    end

    return nil
end

local function GetSpecIconTag(specID)
    specID = tonumber(specID)
    if not specID then return nil end

    local icons = YUI.API and YUI.API.Icons
    if icons and icons.GetSpecIcon then
        local tag = FormatYUISpecIconTag(icons.GetSpecIcon(specID))
        if tag then return tag end
    end

    return FormatNativeSpecIconTag(GetNativeSpecIcon(specID))
end

local function BuildDungeonState(mapID, mapInfo)
    mapInfo = mapInfo or GetMapInfo(mapID)
    if not mapInfo or not mapInfo.name then return nil end

    local bestRun, completedInTime = SelectBestRun(mapID)
    local score = GetDungeonScore(mapID, bestRun)
    local dungeonData = FindDungeonTeleport(mapID, mapInfo.name)
    local teleportSpellID = ResolveKnownTeleportSpell(dungeonData)
    local teleportRemaining = GetCooldownRemaining(teleportSpellID)

    return {
        mapID = mapID,
        name = mapInfo.name,
        shortName = GetShortName(mapInfo.name, dungeonData),
        timeLimit = mapInfo.timeLimit or 0,
        bestRun = bestRun,
        completedInTime = completedInTime == true,
        level = bestRun and tonumber(bestRun.level) or 0,
        score = score,
        scoreColor = GetScoreColor(score),
        teleportSpellID = teleportSpellID,
        teleportRemaining = teleportRemaining,
    }
end

local function IsFrameVisible(frame)
    if not frame then return false end
    local isVisible = PVEEnhancement.PartyKeystonePanel.SafeGetField(frame, "IsVisible")
    if type(isVisible) == "function" then
        local ok, visible = pcall(isVisible, frame)
        if ok then return visible == true end
    end
    local isShown = PVEEnhancement.PartyKeystonePanel.SafeGetField(frame, "IsShown")
    if type(isShown) == "function" then
        local ok, shown = pcall(isShown, frame)
        if ok then return shown == true end
    end
    return true
end

function PVEEnhancement.RatingStats.GetData()
    if PVEEnhancement.RatingStats.releaseEnabled ~= true then return nil end
    local data = Tools and Tools.RatingStatsData
    if type(data) ~= "table" or type(data.regions) ~= "table" then return nil end
    if data.active ~= true then return nil end
    return data
end

function PVEEnhancement.RatingStats.GetCurrentRegionKey()
    local regionID = GetCurrentRegion and tonumber(SafeCall(GetCurrentRegion)) or nil
    local regionKey = regionID and PVEEnhancement.RatingStats.regionByID[regionID] or nil
    if regionKey then return regionKey end

    local regionName = GetCurrentRegionName and SafeCall(GetCurrentRegionName) or nil
    if type(regionName) ~= "string" or regionName == "" then return nil end
    regionName = string.lower(regionName)
    regionName = string.gsub(regionName, "%s+", "")
    return PVEEnhancement.RatingStats.regionByName[regionName]
end

function PVEEnhancement.RatingStats.GetRegionLabel(regionKey, regionData)
    if regionData and type(regionData.shortName) == "string" and regionData.shortName ~= "" then
        return regionData.shortName
    end
    if regionData and type(regionData.name) == "string" and regionData.name ~= "" then
        return regionData.name
    end
    return regionKey and string.upper(regionKey) or UNKNOWN or ""
end

function PVEEnhancement.RatingStats.GetOverallScore()
    local score
    if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
        score = SafeCall(C_ChallengeMode.GetOverallDungeonScore)
    end
    score = tonumber(score)
    if score then return Round(score) end

    local challengesFrame = _G.ChallengesFrame
    local scoreText = challengesFrame and challengesFrame.WeeklyInfo and challengesFrame.WeeklyInfo.Child and challengesFrame.WeeklyInfo.Child.DungeonScoreInfo and challengesFrame.WeeklyInfo.Child.DungeonScoreInfo.Score
    local text = scoreText and scoreText.GetText and scoreText:GetText() or nil
    if type(text) == "string" then
        text = string.gsub(text, "[^%d%.]", "")
        score = tonumber(text)
    end
    return Round(score or 0)
end

function PVEEnhancement.RatingStats.IsCurrentSeason(data)
    local snapshotSeasonID = tonumber(data and data.blizzardSeasonID) or 0
    if snapshotSeasonID <= 0 then return true end
    if not (C_MythicPlus and C_MythicPlus.GetCurrentSeason) then return false end

    local currentSeasonID = tonumber(SafeCall(C_MythicPlus.GetCurrentSeason)) or 0
    if currentSeasonID <= 0 then return false end
    return currentSeasonID == snapshotSeasonID
end

function PVEEnhancement.RatingStats.ClampTopPercent(value)
    value = tonumber(value)
    if not value then return nil end
    if value < 0.01 then return 0.01 end
    if value > 100 then return 100 end
    return value
end

function PVEEnhancement.RatingStats.EstimateTopPercent(score, regionData)
    score = tonumber(score) or 0
    local points = regionData and regionData.points
    if score <= 0 or type(points) ~= "table" or #points == 0 then return nil end

    local first = points[1]
    if first and tonumber(first.score) and score >= tonumber(first.score) then
        return PVEEnhancement.RatingStats.ClampTopPercent(first.topPercent)
    end

    for index = 1, #points - 1 do
        local upper = points[index]
        local lower = points[index + 1]
        local upperScore = tonumber(upper and upper.score)
        local lowerScore = tonumber(lower and lower.score)
        local upperPercent = tonumber(upper and upper.topPercent)
        local lowerPercent = tonumber(lower and lower.topPercent)
        if upperScore and lowerScore and upperPercent and lowerPercent and upperScore ~= lowerScore then
            if score <= upperScore and score >= lowerScore then
                local ratio = (upperScore - score) / (upperScore - lowerScore)
                return PVEEnhancement.RatingStats.ClampTopPercent(upperPercent + ((lowerPercent - upperPercent) * ratio))
            end
        end
    end

    local last = points[#points]
    local lastScore = tonumber(last and last.score)
    if lastScore and score >= lastScore then
        return PVEEnhancement.RatingStats.ClampTopPercent(last.topPercent)
    end
    return nil
end

function PVEEnhancement.RatingStats.BuildEstimate(score)
    score = tonumber(score) or 0
    if score <= 0 then return nil end

    local data = PVEEnhancement.RatingStats.GetData()
    if not data then return nil end
    if not PVEEnhancement.RatingStats.IsCurrentSeason(data) then return nil end

    local regionKey = PVEEnhancement.RatingStats.GetCurrentRegionKey()
    local regionData = regionKey and data.regions[regionKey] or nil
    if type(regionData) ~= "table" then return nil end

    local topPercent = PVEEnhancement.RatingStats.EstimateTopPercent(score, regionData)
    if not topPercent then return nil end

    return {
        score = score,
        topPercent = topPercent,
        data = data,
        regionKey = regionKey,
        regionData = regionData,
        regionLabel = PVEEnhancement.RatingStats.GetRegionLabel(regionKey, regionData),
    }
end

function PVEEnhancement.RatingStats.FormatTopPercent(topPercent)
    topPercent = PVEEnhancement.RatingStats.ClampTopPercent(topPercent)
    if not topPercent then return "" end
    return string.format(T("pve.rating.percent_short", "前 %.2f%%"), topPercent)
end

function PVEEnhancement.RatingStats.FormatScore(score)
    score = tonumber(score) or 0
    return tostring(Round(score))
end

function PVEEnhancement.RatingStats.FormatLargeNumber(value)
    value = tonumber(value) or 0
    if GetLocaleKey() == "enUS" then
        if value >= 1000000 then return string.format("%.1fM", value / 1000000) end
        if value >= 1000 then return string.format("%.1fK", value / 1000) end
    else
        if value >= 10000 then return string.format("%.1f万", value / 10000) end
    end
    return tostring(Round(value))
end

function PVEEnhancement.RatingStats.GradientText(text, startColor, endColor)
    local helper = YUI and YUI.F
    if helper and helper.GetGradientText then
        return helper:GetGradientText(text, startColor, endColor)
    end
    return text
end

function PVEEnhancement.RatingStats.FormatBrandName()
    return "|cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r"
end

function PVEEnhancement.RatingStats.FormatUpdatedAt(regionData)
    if type(regionData) ~= "table" then return nil end

    local updatedAtUnix = tonumber(regionData.updatedAtUnix)
    if updatedAtUnix and updatedAtUnix > 0 and date then
        local updatedAtText = SafeCall(date, "%Y-%m-%d %H:%M", updatedAtUnix)
        if type(updatedAtText) == "string" and updatedAtText ~= "" then
            return updatedAtText
        end
    end

    local updatedAtText = regionData.updatedAtText
    if type(updatedAtText) == "string" and updatedAtText ~= "" then
        return updatedAtText
    end

    updatedAtText = regionData.updatedAt
    if type(updatedAtText) == "string" and updatedAtText ~= "" then
        return updatedAtText
    end

    return nil
end

function PVEEnhancement.RatingStats.GetCutoffLabel(cutoff)
    if not cutoff then return "" end
    local key = cutoff.key
    if key == "top001" then return T("pve.rating.cutoff.top001", "前 0.1%") end
    if key == "top01" then return T("pve.rating.cutoff.top01", "前 1%") end
    if key == "top10" then return T("pve.rating.cutoff.top10", "前 10%") end
    if key == "top25" then return T("pve.rating.cutoff.top25", "前 25%") end
    if key == "top40" then return T("pve.rating.cutoff.top40", "前 40%") end
    if key == "top50" then return T("pve.rating.cutoff.top50", "前 50%") end
    if key == "top60" then return T("pve.rating.cutoff.top60", "前 60%") end
    if key == "keystoneMyth" then return T("pve.rating.cutoff.keystone_myth", "Keystone Myth") end
    if key == "keystoneLegend" then return T("pve.rating.cutoff.keystone_legend", "Keystone Legend") end
    if key == "keystoneHero" then return T("pve.rating.cutoff.keystone_hero", "Keystone Hero") end
    if type(key) == "string" and string.match(key, "^allTimed%d+$") then
        return string.format(T("pve.rating.cutoff.all_timed", "全限时 +%d"), tonumber(cutoff.level) or tonumber(string.match(key, "%d+")) or 0)
    end
    return cutoff.label or key or ""
end

function PVEEnhancement.RatingStats.GetCutoffLabelStyle(cutoff)
    if not cutoff then return nil end
    local key = cutoff.key
    if key == "top001" or key == "keystoneMyth" or key == "keystoneLegend" then
        return "orange"
    end
    if key == "top01" or key == "keystoneHero" then
        return "purple"
    end
    return nil
end

function PVEEnhancement.RatingStats.FormatCutoffLabel(cutoff)
    local label = PVEEnhancement.RatingStats.GetCutoffLabel(cutoff)
    local style = PVEEnhancement.RatingStats.GetCutoffLabelStyle(cutoff)
    if style == "orange" then
        return PVEEnhancement.RatingStats.GradientText(label, PVEEnhancement.RatingStats.orangeGradientStart, PVEEnhancement.RatingStats.orangeGradientEnd)
    end
    if style == "purple" then
        return PVEEnhancement.RatingStats.GradientText(label, PVEEnhancement.RatingStats.purpleGradientStart, PVEEnhancement.RatingStats.purpleGradientEnd)
    end
    return label
end

function PVEEnhancement.RatingStats.FindCutoff(items, key)
    if type(items) ~= "table" then return nil end
    for _, item in ipairs(items) do
        if item and item.key == key then return item end
    end
    return nil
end

function PVEEnhancement.RatingStats.AddCutoffTooltipLine(cutoff, currentScore)
    if not (cutoff and cutoff.score and GameTooltip) then return end
    local label = PVEEnhancement.RatingStats.FormatCutoffLabel(cutoff)
    local score = tonumber(cutoff.score) or 0
    local delta = score - (tonumber(currentScore) or 0)
    local leftText = string.format("%s (%s)", label, PVEEnhancement.RatingStats.FormatScore(score))
    local rightText, rightColor
    if delta > 0 then
        rightText = "-" .. tostring(math.max(1, Round(delta)))
        rightColor = PVEEnhancement.RatingStats.shortfallColor
    else
        rightText = T("pve.rating.tooltip_reached", "已达到")
        rightColor = GREEN_FONT_COLOR or DURATION_IN_TIME_COLOR or { r = 0.1, g = 1, b = 0.1 }
    end
    GameTooltip:AddDoubleLine(leftText, rightText, 1, 1, 1, rightColor.r or rightColor[1] or 1, rightColor.g or rightColor[2] or 1, rightColor.b or rightColor[3] or 1)
end

function PVEEnhancement.RatingStats.ShowTooltip(owner)
    local stats = owner and owner.yuiRatingStats
    if not (stats and GameTooltip) then return end

    local regionData = stats.regionData or {}
    local data = stats.data or {}
    local textColor = PVEEnhancement.RatingStats.textColor
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(T("pve.rating.tooltip_title", "大秘境评分统计"), DUNGEON_NAME_COLOR.r, DUNGEON_NAME_COLOR.g, DUNGEON_NAME_COLOR.b)
    GameTooltip:AddLine(" ")
    local scoreColor = PVEEnhancement.RatingStats.scoreColor
    GameTooltip:AddDoubleLine(T("pve.rating.tooltip_score", "当前评分"), PVEEnhancement.RatingStats.FormatScore(stats.score), 1, 1, 1, scoreColor.r, scoreColor.g, scoreColor.b)
    GameTooltip:AddDoubleLine(T("pve.rating.tooltip_percent", "地区排名估算"), PVEEnhancement.RatingStats.FormatTopPercent(stats.topPercent), 1, 1, 1, textColor.r, textColor.g, textColor.b)
    GameTooltip:AddDoubleLine(T("pve.rating.tooltip_region", "地区"), stats.regionLabel or "", 1, 1, 1, 1, 1, 1)
    if tonumber(regionData.totalPlayers) and regionData.totalPlayers > 0 then
        GameTooltip:AddDoubleLine(T("pve.rating.tooltip_population", "样本人数"), PVEEnhancement.RatingStats.FormatLargeNumber(regionData.totalPlayers), 1, 1, 1, 1, 1, 1)
    end
    local updatedAtText = PVEEnhancement.RatingStats.FormatUpdatedAt(regionData)
    if type(updatedAtText) == "string" and updatedAtText ~= "" then
        GameTooltip:AddDoubleLine(T("pve.rating.tooltip_updated", "更新时间"), updatedAtText, 1, 1, 1, 1, 1, 1)
    end

    local cutoffs = regionData.cutoffs or {}
    if type(cutoffs.percentiles) == "table" and #cutoffs.percentiles > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(T("pve.rating.tooltip_percentiles", "分位线"), DUNGEON_NAME_COLOR.r, DUNGEON_NAME_COLOR.g, DUNGEON_NAME_COLOR.b)
        for _, cutoff in ipairs(cutoffs.percentiles) do
            PVEEnhancement.RatingStats.AddCutoffTooltipLine(cutoff, stats.score)
        end
    end

    if type(cutoffs.milestones) == "table" and #cutoffs.milestones > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(T("pve.rating.tooltip_milestones", "参考分数线"), DUNGEON_NAME_COLOR.r, DUNGEON_NAME_COLOR.g, DUNGEON_NAME_COLOR.b)
        for _, key in ipairs(PVEEnhancement.RatingStats.milestoneKeys) do
            PVEEnhancement.RatingStats.AddCutoffTooltipLine(PVEEnhancement.RatingStats.FindCutoff(cutoffs.milestones, key), stats.score)
        end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format(T("pve.rating.tooltip_source", "数据来源：%s"), data.source or "Raider.IO"), PVE_STATS_GRAY.r, PVE_STATS_GRAY.g, PVE_STATS_GRAY.b, true)
    local warningColor = RED_FONT_COLOR or DURATION_OVERTIME_COLOR or { r = 1, g = 0.1, b = 0.1 }
    GameTooltip:AddLine(T("pve.rating.tooltip_estimated", "基于 Raider.IO 地区赛季快照估算，并非精确角色排名。"), warningColor.r or warningColor[1] or 1, warningColor.g or warningColor[2] or 0.1, warningColor.b or warningColor[3] or 0.1, true)
    GameTooltip:AddLine(string.format(T("pve.rating.tooltip_feature_source", "功能来源：%s"), PVEEnhancement.RatingStats.FormatBrandName()), 1, 1, 1, true)
    GameTooltip:Show()
end

function PVEEnhancement.RatingStats.HideTooltip(owner)
    if GameTooltip and owner and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then
        YUI.HideGameTooltip()
    end
end

function PVEEnhancement.RatingStats.GetScoreText(challengesFrame)
    local child = challengesFrame and challengesFrame.WeeklyInfo and challengesFrame.WeeklyInfo.Child
    local scoreInfo = child and child.DungeonScoreInfo
    return scoreInfo and scoreInfo.Score, scoreInfo
end

function PVEEnhancement.RatingStats.EnsureFrame(challengesFrame)
    challengesFrame = challengesFrame or _G.ChallengesFrame
    local scoreText, scoreInfo = PVEEnhancement.RatingStats.GetScoreText(challengesFrame)
    if not (scoreText and CreateFrame) then return nil end

    local parent = scoreInfo or (scoreText.GetParent and scoreText:GetParent()) or challengesFrame
    if not parent then return nil end

    local frame = PVEEnhancement.RatingStats.frame
    if not frame then
        frame = CreateFrame("Frame", "YUIPVERatingStatsFrame", parent)
        PVEEnhancement.RatingStats.frame = frame
        frame:SetSize(150, 18)
        frame:EnableMouse(true)
        frame.text = frame:CreateFontString(nil, "OVERLAY")
        frame.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
        frame.text:SetJustifyH("CENTER")
        if frame.text.SetJustifyV then frame.text:SetJustifyV("MIDDLE") end
        if frame.text.SetWordWrap then frame.text:SetWordWrap(false) end
        if frame.text.SetNonSpaceWrap then frame.text:SetNonSpaceWrap(false) end
        frame.text:SetShadowColor(0, 0, 0, 0.9)
        frame.text:SetShadowOffset(1, -1)
        frame.text:SetAllPoints()
        frame:SetScript("OnEnter", PVEEnhancement.RatingStats.ShowTooltip)
        frame:SetScript("OnLeave", PVEEnhancement.RatingStats.HideTooltip)
    elseif frame.GetParent and frame:GetParent() ~= parent and frame.SetParent then
        frame:SetParent(parent)
    end

    frame:ClearAllPoints()
    frame:SetPoint("TOP", scoreText, "BOTTOM", 0, -1)
    if parent.GetFrameLevel and frame.SetFrameLevel then
        frame:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
    end
    return frame
end

function PVEEnhancement.RatingStats.HideFrame()
    local frame = PVEEnhancement.RatingStats.frame
    if frame then
        PVEEnhancement.RatingStats.HideTooltip(frame)
        frame.yuiRatingStats = nil
        frame:Hide()
    end
end

function PVEEnhancement.RatingStats.RefreshDisplay(challengesFrame, db)
    db = GetDB(db)
    local frame = PVEEnhancement.RatingStats.EnsureFrame(challengesFrame)
    if not frame then return end

    if not IsRuntimeEnabled(db) or db.pveRatingStatsEnabled ~= true then
        PVEEnhancement.RatingStats.HideFrame()
        return
    end

    challengesFrame = challengesFrame or _G.ChallengesFrame
    if not IsFrameVisible(challengesFrame) then
        PVEEnhancement.RatingStats.HideFrame()
        return
    end

    local score = PVEEnhancement.RatingStats.GetOverallScore()
    local stats = PVEEnhancement.RatingStats.BuildEstimate(score)
    if not stats then
        PVEEnhancement.RatingStats.HideFrame()
        return
    end

    local textColor = PVEEnhancement.RatingStats.textColor
    frame.yuiRatingStats = stats
    frame.text:SetText(PVEEnhancement.RatingStats.FormatTopPercent(stats.topPercent))
    SetTextColor(frame.text, textColor)
    frame:Show()
end

local function GetWindToolsLFGListModule()
    local windTools = PVEEnhancement.PartyKeystonePanel.SafeGetField(_G.WindTools, 1)
    local getModule = PVEEnhancement.PartyKeystonePanel.SafeGetField(windTools, "GetModule")
    if not (windTools and type(getModule) == "function") then return nil end

    local ok, module = PVEEnhancement.PartyKeystonePanel.SafeCallThirdParty("WindTools:GetModule(LFGList)", getModule, windTools, "LFGList", true)
    if ok and type(module) == "table" then
        return module
    end
    return nil
end

local function FindWindToolsStatsAnchor()
    local module = GetWindToolsLFGListModule()
    local panel = PVEEnhancement.PartyKeystonePanel.SafeGetField(module, "RightPanel")
    local quickAccessPanel = PVEEnhancement.PartyKeystonePanel.SafeGetField(panel, "QuickAccessPanel")
    if panel and quickAccessPanel and IsFrameVisible(panel) and IsFrameVisible(quickAccessPanel) then
        return panel
    end
    return nil
end

local function RefreshStatsPanelAnchor(panel)
    local pveFrame = _G.PVEFrame
    if not (panel and pveFrame) then return end

    local activeAnchor = FindWindToolsStatsAnchor() or pveFrame
    panel:ClearAllPoints()
    panel:SetWidth(PVE_STATS_PANEL_WIDTH)
    panel:SetPoint("TOP", pveFrame, "TOP", 0, 0)
    panel:SetPoint("BOTTOM", pveFrame, "BOTTOM", 0, 0)
    panel:SetPoint("LEFT", activeAnchor, "RIGHT", PVE_STATS_PANEL_GAP, 0)
end

local function GetRunDateValue(dateInfo)
    if type(dateInfo) ~= "table" then return 0 end
    local year = tonumber(dateInfo.year) or 0
    if year > 0 and year < 100 then year = year + 2000 end
    local month = tonumber(dateInfo.month) or 0
    local day = tonumber(dateInfo.day) or 0
    local hour = tonumber(dateInfo.hour) or 0
    local minute = tonumber(dateInfo.minute) or 0
    local second = tonumber(dateInfo.second) or 0
    return (((((year * 100 + month) * 100 + day) * 100 + hour) * 100 + minute) * 100) + second
end

local function IsCountableRun(run)
    if type(run) ~= "table" then return false end
    return (tonumber(run.level) or 0) > 0 and tonumber(run.mapChallengeModeID) ~= nil
end

local function IsRunInTime(run, timeLimit)
    local duration = tonumber(run and run.durationSec) or 0
    timeLimit = tonumber(timeLimit) or 0
    if duration <= 0 or timeLimit <= 0 then return true end
    return duration <= timeLimit
end

function PVEEnhancement.GetWeeklyVaultLimit()
    local limit = 8
    if C_WeeklyRewards and C_WeeklyRewards.GetActivities and Enum and Enum.WeeklyRewardChestThresholdType then
        local activities = SafeCall(C_WeeklyRewards.GetActivities, Enum.WeeklyRewardChestThresholdType.Activities)
        if type(activities) == "table" then
            local maxThreshold = 0
            for _, activityInfo in ipairs(activities) do
                local threshold = tonumber(activityInfo and activityInfo.threshold) or 0
                if threshold > maxThreshold then maxThreshold = threshold end
            end
            if maxThreshold > 0 then limit = maxThreshold end
        end
    end
    return limit
end

local function CreateStatsMapRow(rows, rowsByMap, mapID)
    mapID = tonumber(mapID)
    if not mapID or rowsByMap[mapID] then return rowsByMap[mapID] end

    local mapInfo = GetMapInfo(mapID)
    if not mapInfo or not mapInfo.name then return nil end

    local dungeonData = FindDungeonTeleport(mapID, mapInfo.name)
    local row = {
        mapID = mapID,
        name = mapInfo.name,
        shortName = GetShortName(mapInfo.name, dungeonData),
        texture = mapInfo.texture,
        backgroundTexture = mapInfo.backgroundTexture,
        timeLimit = mapInfo.timeLimit or 0,
        weekRuns = {},
        seasonTotal = 0,
        seasonTimed = 0,
        seasonOvertime = 0,
        weekTotal = 0,
        weekTimed = 0,
        weekOvertime = 0,
    }
    rowsByMap[mapID] = row
    rows[#rows + 1] = row
    return row
end

local function SortStatsRuns(a, b)
    if a.level ~= b.level then return a.level > b.level end
    if a.dateValue ~= b.dateValue then return a.dateValue > b.dateValue end
    return (a.durationSec or 0) > (b.durationSec or 0)
end

local function AddStatsRunToRow(row, level, durationSec, dateValue, inTime, thisWeek)
    if not row then return end
    local runInTime = inTime == true

    row.seasonTotal = (tonumber(row.seasonTotal) or 0) + 1
    if runInTime then
        row.seasonTimed = (tonumber(row.seasonTimed) or 0) + 1
    else
        row.seasonOvertime = (tonumber(row.seasonOvertime) or 0) + 1
    end

    if thisWeek == true then
        row.weekTotal = (tonumber(row.weekTotal) or 0) + 1
        if runInTime then
            row.weekTimed = (tonumber(row.weekTimed) or 0) + 1
        else
            row.weekOvertime = (tonumber(row.weekOvertime) or 0) + 1
        end
        row.weekRuns[#row.weekRuns + 1] = {
            level = tonumber(level) or 0,
            durationSec = tonumber(durationSec) or 0,
            dateValue = tonumber(dateValue) or 0,
            inTime = runInTime,
            mapID = row.mapID,
            name = row.name,
            shortName = row.shortName,
        }
        return row.weekRuns[#row.weekRuns]
    end
end

local function SortStatsPanelRows(rows)
    for _, row in ipairs(rows or {}) do
        table.sort(row.weekRuns, SortStatsRuns)
    end
end

local function CreateStatsDevRandom(seed)
    seed = tonumber(seed)
    if not seed or seed <= 0 then
        seed = (time and time() or 1) + math.floor((GetTime and GetTime() or 0) * 1000)
    end
    seed = math.floor(seed) % 2147483647
    if seed <= 0 then seed = 1 end

    local initialSeed = seed
    local function random(minValue, maxValue)
        seed = (seed * 48271) % 2147483647
        local value = seed / 2147483647
        minValue = tonumber(minValue) or 0
        maxValue = tonumber(maxValue) or minValue
        if maxValue < minValue then
            minValue, maxValue = maxValue, minValue
        end
        return minValue + math.floor(value * (maxValue - minValue + 1))
    end

    return random, initialSeed
end

local function CreateStatsDevDuration(random, timeLimit, inTime)
    timeLimit = tonumber(timeLimit) or 0
    if timeLimit <= 0 then timeLimit = 1800 end

    if inTime then
        local minDuration = math.max(1, math.floor(timeLimit * 0.45))
        local maxDuration = math.max(minDuration, timeLimit - 1)
        return random(minDuration, maxDuration)
    end

    return random(timeLimit + 1, timeLimit + math.max(90, math.floor(timeLimit * 0.35)))
end

local function BuildStatsPanelDevData(seed, recordCount, requestedWeeklyCount)
    if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then
        return nil, "C_ChallengeMode.GetMapTable unavailable"
    end

    local mapTable = SafeCall(C_ChallengeMode.GetMapTable)
    if type(mapTable) ~= "table" or #mapTable == 0 then
        return nil, "challenge map table is empty"
    end

    local random, usedSeed = CreateStatsDevRandom(seed)
    local rows, rowsByMap = {}, {}
    local weeklyVaultRuns = {}
    local seasonCount, weeklyCount = 0, 0
    local startedAt = debugprofilestop and debugprofilestop() or nil

    requestedWeeklyCount = tonumber(requestedWeeklyCount)
    if requestedWeeklyCount ~= nil then
        requestedWeeklyCount = math.floor(ClampNumber(requestedWeeklyCount, 0, 100000, 0))
    end

    local function FinalizeWeeklyVaultRuns()
        table.sort(weeklyVaultRuns, function(a, b)
            if a.level ~= b.level then return a.level > b.level end
            if a.dateValue ~= b.dateValue then return a.dateValue > b.dateValue end
            return (tonumber(a.mapID) or 0) < (tonumber(b.mapID) or 0)
        end)

        local limit = math.max(PVEEnhancement.StatsPanel.topRunLimit, PVEEnhancement.GetWeeklyVaultLimit())
        for index = #weeklyVaultRuns, limit + 1, -1 do
            weeklyVaultRuns[index] = nil
        end
    end

    recordCount = tonumber(recordCount)
    if recordCount and recordCount > 0 then
        recordCount = math.floor(recordCount)
        for _, mapID in ipairs(mapTable) do
            CreateStatsMapRow(rows, rowsByMap, mapID)
        end

        for runIndex = 1, recordCount do
            local mapID = mapTable[random(1, #mapTable)]
            local row = CreateStatsMapRow(rows, rowsByMap, mapID)
            if row then
                local thisWeek = random(1, 100) <= 20
                local level = random(2, 22)
                local inTime = random(1, 100) <= 68
                local durationSec = CreateStatsDevDuration(random, row.timeLimit, inTime)
                local runData = AddStatsRunToRow(row, level, durationSec, runIndex, inTime, thisWeek)
                if runData then
                    weeklyVaultRuns[#weeklyVaultRuns + 1] = runData
                end
                seasonCount = seasonCount + 1
                if thisWeek then weeklyCount = weeklyCount + 1 end
            end
        end

        SortStatsPanelRows(rows)
        FinalizeWeeklyVaultRuns()
        return {
            rows = rows,
            seasonCount = seasonCount,
            weeklyCount = weeklyCount,
            weeklyVaultRuns = weeklyVaultRuns,
            seed = usedSeed,
            mapCount = #rows,
            recordCount = recordCount,
            buildMs = startedAt and (debugprofilestop() - startedAt) or nil,
        }
    end

    for _, mapID in ipairs(mapTable) do
        CreateStatsMapRow(rows, rowsByMap, mapID)
    end

    local requestedWeekRunsByMap
    if requestedWeeklyCount ~= nil and #rows > 0 then
        requestedWeekRunsByMap = {}
        local baseCount = math.floor(requestedWeeklyCount / #rows)
        local remainder = requestedWeeklyCount % #rows
        local startIndex = random(1, #rows)
        for offset = 0, #rows - 1 do
            local rowIndex = ((startIndex + offset - 1) % #rows) + 1
            requestedWeekRunsByMap[rowIndex] = baseCount + (offset < remainder and 1 or 0)
        end
    end

    for index, row in ipairs(rows) do
        if row then
            local patternIndex = ((index + random(0, #PVE_STATS_DEV_WEEK_COUNTS - 1) - 1) % #PVE_STATS_DEV_WEEK_COUNTS) + 1
            local weekRuns = requestedWeekRunsByMap and (requestedWeekRunsByMap[index] or 0) or (PVE_STATS_DEV_WEEK_COUNTS[patternIndex] or 0)
            local seasonRuns = weekRuns + random(0, 24)
            if seasonRuns <= 0 then seasonRuns = random(1, 4) end

            for runIndex = 1, seasonRuns do
                local thisWeek = runIndex <= weekRuns
                local level = random(2, 18)
                if runIndex == 1 and weekRuns > PVE_STATS_MAX_RUNS then
                    level = random(16, 22)
                end
                local inTime = random(1, 100) <= (thisWeek and 72 or 62)
                local durationSec = CreateStatsDevDuration(random, row.timeLimit, inTime)
                local dateValue = (index * 100000) + runIndex
                local runData = AddStatsRunToRow(row, level, durationSec, dateValue, inTime, thisWeek)
                if runData then
                    weeklyVaultRuns[#weeklyVaultRuns + 1] = runData
                end
            end

            seasonCount = seasonCount + row.seasonTotal
            weeklyCount = weeklyCount + row.weekTotal
        end
    end

    SortStatsPanelRows(rows)
    FinalizeWeeklyVaultRuns()
    return {
        rows = rows,
        seasonCount = seasonCount,
        weeklyCount = weeklyCount,
        weeklyVaultRuns = weeklyVaultRuns,
        seed = usedSeed,
        mapCount = #rows,
        recordCount = seasonCount,
        requestedWeeklyCount = requestedWeeklyCount,
        buildMs = startedAt and (debugprofilestop() - startedAt) or nil,
    }
end

local function PrintStatsDev(...)
    if YUI and type(YUI.Print) == "function" then
        YUI:Print(...)
    elseif print then
        print(...)
    end
end

local function BuildStatsPanelData()
    if statsPanelDevData and YUI.IsDev == true then
        return statsPanelDevData.rows, statsPanelDevData.seasonCount, statsPanelDevData.weeklyCount, statsPanelDevData.weeklyVaultRuns
    elseif statsPanelDevData and YUI.IsDev ~= true then
        statsPanelDevData = nil
        PVEEnhancement._statsPanelDataCache = nil
        PVEEnhancement._statsPanelDataDirty = true
    end

    local cached = PVEEnhancement._statsPanelDataCache
    if cached and PVEEnhancement._statsPanelDataDirty ~= true then
        return cached.rows, cached.seasonCount, cached.weeklyCount, cached.weeklyVaultRuns
    end

    local rows, rowsByMap = {}, {}
    if C_ChallengeMode and C_ChallengeMode.GetMapTable then
        local mapTable = SafeCall(C_ChallengeMode.GetMapTable)
        if type(mapTable) == "table" then
            for _, mapID in ipairs(mapTable) do
                CreateStatsMapRow(rows, rowsByMap, mapID)
            end
        end
    end

    local weeklyVaultRuns = {}
    local function FinalizeWeeklyVaultRuns()
        table.sort(weeklyVaultRuns, function(a, b)
            if a.level ~= b.level then return a.level > b.level end
            if a.dateValue ~= b.dateValue then return a.dateValue > b.dateValue end
            return (tonumber(a.mapID) or 0) < (tonumber(b.mapID) or 0)
        end)

        local limit = math.max(PVEEnhancement.StatsPanel.topRunLimit, PVEEnhancement.GetWeeklyVaultLimit())
        for index = #weeklyVaultRuns, limit + 1, -1 do
            weeklyVaultRuns[index] = nil
        end
    end

    local seasonCount, weeklyCount = 0, 0
    if C_MythicPlus and C_MythicPlus.GetRunHistory then
        local history = SafeCall(C_MythicPlus.GetRunHistory, true, true, true)
        if type(history) == "table" then
            for _, run in ipairs(history) do
                if IsCountableRun(run) then
                    local mapID = tonumber(run.mapChallengeModeID)
                    seasonCount = seasonCount + 1
                    if run.thisWeek == true then
                        weeklyCount = weeklyCount + 1
                    end

                    local row = CreateStatsMapRow(rows, rowsByMap, mapID)
                    if row then
                        local level = tonumber(run.level) or 0
                        local inTime = IsRunInTime(run, row.timeLimit)
                        local runData = AddStatsRunToRow(row, level, tonumber(run.durationSec) or 0, GetRunDateValue(run.completionDate), inTime, run.thisWeek == true)
                        if runData then
                            weeklyVaultRuns[#weeklyVaultRuns + 1] = runData
                        end
                    end
                end
            end
        end
    end

    SortStatsPanelRows(rows)
    FinalizeWeeklyVaultRuns()

    PVEEnhancement._statsPanelDataCache = {
        rows = rows,
        seasonCount = seasonCount,
        weeklyCount = weeklyCount,
        weeklyVaultRuns = weeklyVaultRuns,
    }
    PVEEnhancement._statsPanelDataDirty = false

    return rows, seasonCount, weeklyCount, weeklyVaultRuns
end

local function CreateStatsFontString(parent, size, flags, justifyH)
    local text = parent:CreateFontString(nil, "OVERLAY")
    local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    text:SetFont(fontPath, size, flags)
    text:SetJustifyH(justifyH or "LEFT")
    if text.SetJustifyV then text:SetJustifyV("MIDDLE") end
    if text.SetWordWrap then text:SetWordWrap(false) end
    if text.SetNonSpaceWrap then text:SetNonSpaceWrap(false) end
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -1)
    StatsPanelAppearance.fonts[text] = true
    StatsPanelAppearance.fontStates[text] = {
        path = fontPath,
        size = size,
        flags = flags or "",
    }
    if StatsPanelAppearance.ApplyFont then
        StatsPanelAppearance.ApplyFont(text)
    end
    return text
end

function PVEEnhancement.PartyKeystonePanel.GetAPI()
    return YUI.IsRetail and YUI.API and YUI.API.Keystone or nil
end

function PVEEnhancement.PartyKeystonePanel.GetUnitClassColor(unit)
    if not unit then return nil end

    local classFile
    if UnitAPI and UnitAPI.UnitClass then
        _, classFile = SafeCall(UnitAPI.UnitClass, unit)
    elseif UnitClass then
        _, classFile = SafeCall(UnitClass, unit)
    end
    return GetClassColorByFile(classFile)
end

function PVEEnhancement.PartyKeystonePanel.GetMapName(row)
    if not row then return nil end
    if type(row.mapName) == "string" and row.mapName ~= "" then
        return row.mapName
    end
    if row.mapID and tonumber(row.mapID) and tonumber(row.mapID) > 0 and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local mapName = SafeCall(C_ChallengeMode.GetMapUIInfo, row.mapID)
        if type(mapName) == "string" and mapName ~= "" then
            return mapName
        end
    end
    return nil
end

function PVEEnhancement.PartyKeystonePanel.GetDisplay(row)
    if not row or row.status ~= "ready" then
        return row and row.isPlayer and T("pve.keystone.no_keystone", "暂无钥石") or T("pve.keystone.loading", "获取中..."), PVE_STATS_GRAY
    end

    local mapName = PVEEnhancement.PartyKeystonePanel.GetMapName(row)
    local shortName = GetShortName(mapName, FindDungeonTeleport(row.mapID, mapName))
    if shortName == "" then shortName = mapName or (UNKNOWN or "") end
    return string.format("%s (%d)", shortName, tonumber(row.level) or 0), GetLevelColor(row.level)
end

function PVEEnhancement.PartyKeystonePanel.GetDungeonIconAnchor(challengesFrame)
    local icons = challengesFrame and challengesFrame.DungeonIcons
    if type(icons) ~= "table" then return nil end

    for index = #icons, 1, -1 do
        local icon = icons[index]
        if IsFrameVisible(icon) then
            return icon
        end
    end

    return nil
end

function PVEEnhancement.PartyKeystonePanel.IsGuildRecordAnchorCandidate(frame, challengesFrame)
    local state = PVEEnhancement.PartyKeystonePanel
    if not (state.IsFrameLike(frame) and frame ~= state.frame and challengesFrame) then return false end

    local getParent = state.SafeGetField(frame, "GetParent")
    if type(getParent) ~= "function" then return false end
    local parentOK, parent = state.SafeCallThirdParty("GuildRecordFrame:GetParent", getParent, frame)
    if not parentOK or parent ~= challengesFrame then return false end

    local entries = state.SafeGetField(frame, "entries")
    if type(entries) ~= "table" then return false end

    for index = 1, 4 do
        local entry = entries[index]
        if not state.IsFrameLike(entry) then return false end

        local getEntryParent = state.SafeGetField(entry, "GetParent")
        if type(getEntryParent) ~= "function" then return false end
        local entryParentOK, entryParent = state.SafeCallThirdParty("GuildRecordEntry:GetParent", getEntryParent, entry)
        if not entryParentOK or entryParent ~= frame then return false end

        if not state.IsFrameLike(state.SafeGetField(entry, "CharacterName")) then return false end
        if not state.IsFrameLike(state.SafeGetField(entry, "Level")) then return false end
    end

    return true
end

function PVEEnhancement.PartyKeystonePanel.GetGuildRecordAnchor(challengesFrame)
    local state = PVEEnhancement.PartyKeystonePanel
    if not challengesFrame then
        state.guildRecordAnchorFrame = nil
        return nil
    end

    local cachedFrame = state.guildRecordAnchorFrame
    if state.IsGuildRecordAnchorCandidate(cachedFrame, challengesFrame) then
        if IsFrameVisible(cachedFrame) then
            return cachedFrame
        end
        return nil
    end
    state.guildRecordAnchorFrame = nil

    local getChildren = state.SafeGetField(challengesFrame, "GetChildren")
    if type(getChildren) ~= "function" then return nil end

    local ok, children = pcall(function()
        return { getChildren(challengesFrame) }
    end)
    if not ok or type(children) ~= "table" then return nil end

    for _, child in ipairs(children) do
        if state.IsGuildRecordAnchorCandidate(child, challengesFrame) then
            state.guildRecordAnchorFrame = child
            if IsFrameVisible(child) then
                return child
            end
            return nil
        end
    end
    return nil
end

function PVEEnhancement.PartyKeystonePanel.GetDynamicHeight(rowCount)
    local state = PVEEnhancement.PartyKeystonePanel
    local count = math.min(math.max(tonumber(rowCount) or 0, 0), state.maxRows or 0)
    local gapTotal = count > 1 and ((count - 1) * (state.rowGap or 0)) or 0
    local rowTotal = count > 0 and ((count * (state.rowHeight or 0)) + gapTotal) or 0
    local height = (state.rowTopOffset or 0) + rowTotal + (state.bottomPadding or state.padding or 0)
    return math.max(state.minHeight or 0, height)
end

function PVEEnhancement.PartyKeystonePanel.RefreshAnchor(panel)
    local challengesFrame = _G.ChallengesFrame
    local pveFrame = _G.PVEFrame
    local parent = challengesFrame or pveFrame
    if not (panel and parent) then return end

    if panel.GetParent and panel:GetParent() ~= parent and panel.SetParent then
        panel:SetParent(parent)
    end
    if parent.GetFrameStrata and panel.SetFrameStrata then
        panel:SetFrameStrata(parent:GetFrameStrata())
    end
    if parent.GetFrameLevel and panel.SetFrameLevel then
        panel:SetFrameLevel((parent:GetFrameLevel() or 0) + 25)
    end

    local state = PVEEnhancement.PartyKeystonePanel
    local guildRecordAnchor = state.GetGuildRecordAnchor(challengesFrame)
    local iconAnchor = state.GetDungeonIconAnchor(challengesFrame)
    panel:ClearAllPoints()
    panel:SetSize(state.width, panel._yuiPartyKeystoneHeight or state.minHeight)
    if guildRecordAnchor then
        if guildRecordAnchor.GetFrameLevel and panel.GetFrameLevel and panel.SetFrameLevel then
            panel:SetFrameLevel(math.max(panel:GetFrameLevel() or 0, (guildRecordAnchor:GetFrameLevel() or 0) + 10))
        end
        panel:SetPoint("BOTTOMRIGHT", guildRecordAnchor, "TOPRIGHT", 0, 6)
    elseif iconAnchor then
        panel:SetPoint("BOTTOMRIGHT", iconAnchor, "TOPRIGHT", 0, 6)
    else
        local anchor = _G.ChallengesFrameInset or (challengesFrame and challengesFrame.Inset) or challengesFrame or parent
        panel:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -10, 92)
    end
end

function PVEEnhancement.PartyKeystonePanel.Create()
    local state = PVEEnhancement.PartyKeystonePanel
    local parent = _G.ChallengesFrame or _G.PVEFrame
    if state.frame then return state.frame end

    local GUI2 = YUI.GUI2
    if not (parent and GUI2 and GUI2.CreatePanel and GUI2.CreateFrame and GUI2.CreateText and GUI2.Form and GUI2.Form.CreateButton) then
        return nil
    end

    state.frame = GUI2:CreatePanel(parent, {
        name = "YUIPVEPartyKeystonePanel",
        width = state.width,
        height = state.minHeight,
        surface = "color.surface.window",
        border = "color.border.strong",
        shadow = true,
    })

    local panel = state.frame
    panel:SetSize(state.width, state.minHeight)
    panel:EnableMouse(true)

    panel.title = GUI2:CreateText(panel, T("pve.keystone.title", "队伍钥石"), state.titleFontSize, "color.text.accent", "LEFT")
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", state.padding, -7)
    panel.title:SetSize(state.width - (state.padding * 2) - state.buttonWidth - 6, 17)
    if panel.title.SetWordWrap then panel.title:SetWordWrap(false) end
    SetTextColor(panel.title, DUNGEON_NAME_COLOR)

    panel.sendButton = GUI2.Form:CreateButton(panel, {
        text = T("pve.keystone.send", "发送"),
        width = state.buttonWidth,
        height = state.buttonHeight,
        fontSizeKey = "font.size.sm",
        onClick = function()
            local api = PVEEnhancement.PartyKeystonePanel.GetAPI()
            if api and api.ReportPartyKeystones then
                api.ReportPartyKeystones()
            end
        end,
    })
    panel.sendButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -state.padding, -6)

    panel.rows = {}
    for index = 1, state.maxRows do
        local row = GUI2:CreateFrame(panel, {
            width = state.width - (state.padding * 2),
            height = state.rowHeight,
        })
        local yOffset = -state.rowTopOffset - ((index - 1) * (state.rowHeight + state.rowGap))
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", state.padding, yOffset)
        row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -state.padding, yOffset)

        row.nameText = GUI2:CreateText(row, "", state.rowFontSize, "color.text.primary", "LEFT")
        row.nameText:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.nameText:SetSize(state.nameWidth, state.rowHeight)
        if row.nameText.SetWordWrap then row.nameText:SetWordWrap(false) end
        if row.nameText.SetMaxLines then row.nameText:SetMaxLines(1) end

        row.keyText = GUI2:CreateText(row, "", state.rowFontSize, "color.text.secondary", "RIGHT")
        row.keyText:SetPoint("LEFT", row.nameText, "RIGHT", 5, 0)
        row.keyText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.keyText:SetHeight(state.rowHeight)
        if row.keyText.SetWordWrap then row.keyText:SetWordWrap(false) end
        if row.keyText.SetMaxLines then row.keyText:SetMaxLines(1) end

        panel.rows[index] = row
    end

    panel:Hide()
    return panel
end

function PVEEnhancement.PartyKeystonePanel.ShouldShow(db)
    db = GetDB(db)
    if not IsRuntimeEnabled(db) or db.pvePartyKeystonePanelEnabled ~= true then return false end
    if not PVEEnhancement.PartyKeystonePanel.GetAPI() then return false end
    return IsFrameVisible(_G.PVEFrame) and IsFrameVisible(_G.ChallengesFrame)
end

function PVEEnhancement.PartyKeystonePanel.RenderRow(row, rowData)
    if not row then return end
    if not rowData then
        row:Hide()
        return
    end

    row.nameText:SetText(rowData.name or "")
    SetTextColor(row.nameText, PVEEnhancement.PartyKeystonePanel.GetUnitClassColor(rowData.unit), PVE_STATS_WHITE)

    local keyText, keyColor = PVEEnhancement.PartyKeystonePanel.GetDisplay(rowData)
    row.keyText:SetText(keyText or "")
    SetTextColor(row.keyText, keyColor, PVE_STATS_GRAY)
    row:Show()
end

function PVEEnhancement.PartyKeystonePanel.GetWindToolsPartyKeystoneFrame()
    local module = GetWindToolsLFGListModule()
    local frame = PVEEnhancement.PartyKeystonePanel.SafeGetField(module, "PartyKeystoneFrame")
    if PVEEnhancement.PartyKeystonePanel.IsFrameLike(frame) then return frame end
    frame = PVEEnhancement.PartyKeystonePanel.SafeGetField(_G, "WTPartyKeystoneFrame")
    if PVEEnhancement.PartyKeystonePanel.IsFrameLike(frame) then return frame end
    return nil
end

function PVEEnhancement.PartyKeystonePanel.HideWindToolsPartyKeystoneFrame()
    local state = PVEEnhancement.PartyKeystonePanel
    if not IsFrameVisible(state.frame) then return false end

    local frame = state.GetWindToolsPartyKeystoneFrame()
    local hide = state.SafeGetField(frame, "Hide")
    if not (frame and type(hide) == "function") then return false end

    local visibleOK, visible
    local isShown = state.SafeGetField(frame, "IsShown")
    local isVisible = state.SafeGetField(frame, "IsVisible")
    if type(isShown) == "function" then
        visibleOK, visible = state.SafeCallThirdParty("WTPartyKeystoneFrame:IsShown", isShown, frame)
    elseif type(isVisible) == "function" then
        visibleOK, visible = state.SafeCallThirdParty("WTPartyKeystoneFrame:IsVisible", isVisible, frame)
    else
        return false
    end
    if not visibleOK or visible ~= true then return false end

    local hideOK = state.SafeCallThirdParty("WTPartyKeystoneFrame:Hide", hide, frame)
    return hideOK == true
end

function PVEEnhancement.PartyKeystonePanel.EnsureWindToolsHook()
    local state = PVEEnhancement.PartyKeystonePanel
    if state.windToolsHooked or type(hooksecurefunc) ~= "function" then return end

    local module = GetWindToolsLFGListModule()
    local update = state.SafeGetField(module, "UpdatePartyKeystoneFrame")
    if not (type(module) == "table" and type(update) == "function") then return end

    local ok = state.SafeCallThirdParty("WindTools:LFGList:UpdatePartyKeystoneFrame hook", hooksecurefunc, module, "UpdatePartyKeystoneFrame", function()
        PVEEnhancement.PartyKeystonePanel.HideWindToolsPartyKeystoneFrame()
    end)
    if ok then
        state.windToolsHooked = true
    end
end

function PVEEnhancement.PartyKeystonePanel.Refresh(db)
    local state = PVEEnhancement.PartyKeystonePanel
    local api = state.GetAPI()
    if not state.ShouldShow(db) then
        if state.frame then
            state.frame:Hide()
        end
        if api and api.Deactivate then
            api.Deactivate(PVEEnhancement)
        end
        return
    end

    local panel = state.Create()
    if not panel then return end

    if api and api.Activate then
        api.Activate(PVEEnhancement)
    end
    if api and api.RequestPartyKeystones and IsInGroup and IsInGroup() then
        api.RequestPartyKeystones()
    end

    local rows = api and api.GetPartyKeystoneRows and api.GetPartyKeystoneRows() or {}
    local rowCount = math.min(#rows, state.maxRows)
    local dynamicHeight = state.GetDynamicHeight(rowCount)
    panel._yuiPartyKeystoneHeight = dynamicHeight
    panel:SetSize(state.width, dynamicHeight)
    state.RefreshAnchor(panel)
    if panel.title then
        panel.title:SetText(T("pve.keystone.title", "队伍钥石"))
    end
    if panel.sendButton then
        panel.sendButton:SetText(T("pve.keystone.send", "发送"))
        if panel.sendButton.SetDisabled then
            panel.sendButton:SetDisabled(not (IsInGroup and IsInGroup() == true))
        end
    end

    for index = 1, state.maxRows do
        state.RenderRow(panel.rows and panel.rows[index], index <= rowCount and rows[index] or nil)
    end

    panel:Show()
    state.EnsureWindToolsHook()
    state.HideWindToolsPartyKeystoneFrame()
end

function PVEEnhancement.PartyKeystonePanel.RunQueuedRefresh()
    local state = PVEEnhancement.PartyKeystonePanel
    state.refreshScheduled = false
    state.refreshTimer = nil
    local rosterTransaction = state.refreshRosterTransaction == true
    state.refreshRosterTransaction = false
    local startedAt = cpuWatchdog and cpuWatchdog:BeginProbeTiming()
    state.Refresh()
    if startedAt then
        cpuWatchdog:EndProbeTiming(
            "component.mythic-plus-tools.party-keystone-refresh",
            startedAt,
            "MythicPlusTools party keystone refresh",
            nil,
            rosterTransaction and cpuWatchdog.ROSTER_TRANSACTION_GROUP_ID or nil,
            rosterTransaction and cpuWatchdog.ROSTER_TRANSACTION_LABEL or nil
        )
    end
end

function PVEEnhancement.PartyKeystonePanel.QueueRefresh()
    local state = PVEEnhancement.PartyKeystonePanel
    if state.refreshScheduled then return end
    state.refreshScheduled = true
    if C_Timer and C_Timer.NewTimer then
        state.refreshTimer = C_Timer.NewTimer(0, state.RunQueuedRefresh)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, state.RunQueuedRefresh)
    else
        state.RunQueuedRefresh()
    end
end

local function SetStatsRegionShown(region, shown)
    local regionType = type(region)
    if regionType ~= "table" and regionType ~= "userdata" then return end
    if type(region.Show) ~= "function" or type(region.Hide) ~= "function" then return end
    if shown then
        region:Show()
    else
        region:Hide()
    end
end

local function SetStatsPanelGUI2VisualsShown(panel, shown)
    if not panel then return end
    if panel.gui2Borders then
        for _, border in pairs(panel.gui2Borders) do
            if border then
                SetStatsRegionShown(border, shown)
            end
        end
    end
    if panel.borders then
        for _, border in ipairs(panel.borders) do
            SetStatsRegionShown(border, shown)
        end
    end
    SetStatsRegionShown(panel.gui2Shadow, shown)
end

local function EnsureNativeStatsPanelChrome(panel)
    if not panel then return false end
    if panel.nativeChrome then return true end
    if not (CreateFrame and NineSliceUtil and type(NineSliceUtil.ApplyLayoutByName) == "function") then return false end

    local ok, chrome = pcall(CreateFrame, "Frame", nil, panel, "NineSlicePanelTemplate")
    if not ok or not chrome then return false end

    chrome:SetAllPoints(panel)
    if chrome.SetFrameLevel and panel.GetFrameLevel then
        chrome:SetFrameLevel(math.max(0, (panel:GetFrameLevel() or 1) - 5))
    end
    NineSliceUtil.ApplyLayoutByName(chrome, "ButtonFrameTemplateNoPortrait")

    local bgTexture
    local GUI2 = YUI.GUI2
    if GUI2 and type(GUI2.CreateTexture) == "function" then
        bgTexture = GUI2:CreateTexture(chrome, {
            layer = "BACKGROUND",
            subLevel = -7,
            texture = "Interface\\FrameGeneral\\UI-Background-Rock",
        })
    else
        bgTexture = chrome:CreateTexture(nil, "BACKGROUND", nil, -7)
        bgTexture:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
    end
    bgTexture:SetPoint("TOPLEFT", chrome, "TOPLEFT", 6, -2)
    bgTexture:SetPoint("BOTTOMRIGHT", chrome, "BOTTOMRIGHT", -2, 2)
    bgTexture:SetHorizTile(true)
    bgTexture:SetVertTile(true)

    panel.nativeChrome = chrome
    panel.nativeChromeBg = bgTexture
    return true
end

local ApplyNativeStatsPanelBackdrop

function StatsPanelAppearance.ResolveLegacyContext()
    local appearance = YUI.GUI2 and YUI.GUI2.WindowAppearance
    if not appearance or type(appearance.Resolve) ~= "function" then return nil end
    local context = appearance:Resolve("auto", { blizzardWindow = "lfg" })
    return context and context.source == "ellesmere"
        and context.providerKind == "legacy" and context or nil
end

function StatsPanelAppearance.GetAccentColor()
    local appearance = YUI.GUI2 and YUI.GUI2.WindowAppearance
    if appearance and type(appearance.GetAccentColor) == "function" then
        return appearance:GetAccentColor(StatsPanelAppearance.activeContext)
    end
end

function StatsPanelAppearance.ApplyFont(fontString)
    local appearance = YUI.GUI2 and YUI.GUI2.WindowAppearance
    if appearance and type(appearance.ApplyFont) == "function" then
        return appearance:ApplyFont(fontString, StatsPanelAppearance.activeContext)
    end
    return false
end

function StatsPanelAppearance.RefreshFonts()
    for fontString in pairs(StatsPanelAppearance.fonts) do
        StatsPanelAppearance.ApplyFont(fontString)
    end
end

function StatsPanelAppearance.SetLegacyVisualsShown(panel, shown)
    if not panel then return end
    SetStatsRegionShown(panel.ellesmereLegacyBg, shown)
    SetStatsRegionShown(panel.ellesmereLegacyTopBar, shown)
    for _, border in ipairs(panel.ellesmereLegacyBorders or {}) do
        SetStatsRegionShown(border, shown)
    end
end

function StatsPanelAppearance.EnsureLegacyVisuals(panel)
    if not panel then return false end
    if panel.ellesmereLegacyBg then return true end
    if type(panel.CreateTexture) ~= "function" then return false end

    panel.ellesmereLegacyBg = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
    panel.ellesmereLegacyBg:SetAllPoints(panel)

    panel.ellesmereLegacyTopBar = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
    panel.ellesmereLegacyTopBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
    panel.ellesmereLegacyTopBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -1)
    panel.ellesmereLegacyTopBar:SetHeight(25)

    panel.ellesmereLegacyBorders = {}
    for index = 1, 4 do
        panel.ellesmereLegacyBorders[index] = panel:CreateTexture(nil, "OVERLAY", nil, 7)
    end
    local top, bottom, left, right = (unpack or table.unpack)(panel.ellesmereLegacyBorders)
    top:SetPoint("TOPLEFT", panel, "TOPLEFT")
    top:SetPoint("TOPRIGHT", panel, "TOPRIGHT")
    bottom:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT")
    left:SetPoint("TOPLEFT", panel, "TOPLEFT")
    left:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT")
    right:SetPoint("TOPRIGHT", panel, "TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT")
    return true
end

function StatsPanelAppearance.ApplyLegacyVisuals(panel, context)
    if not (StatsPanelAppearance.EnsureLegacyVisuals(panel) and context) then return false end
    local background = context.background
    local r = background and background[1] or context.bgR
    local g = background and background[2] or context.bgG
    local b = background and background[3] or context.bgB
    local a = background and background[4] or context.bgA
    if not (r and g and b and a) then return false end
    panel.ellesmereLegacyBg:SetColorTexture(r, g, b, a)
    panel.ellesmereLegacyTopBar:SetColorTexture(0, 0, 0, 0.34)
    local pixel = PVEEnhancement.StatsPanel.GetPixelSize(panel, 1)
    local top, bottom, left, right = (unpack or table.unpack)(panel.ellesmereLegacyBorders)
    top:SetHeight(pixel)
    bottom:SetHeight(pixel)
    left:SetWidth(pixel)
    right:SetWidth(pixel)
    for _, border in ipairs(panel.ellesmereLegacyBorders) do
        border:SetColorTexture(0.20, 0.20, 0.20, 1)
    end
    StatsPanelAppearance.SetLegacyVisualsShown(panel, true)
    return true
end

function StatsPanelAppearance.RefreshAccent(panel)
    if not panel then return end
    local r, g, b = StatsPanelAppearance.GetAccentColor()
    if panel.title and panel.title.SetTextColor then
        if r then
            panel.title:SetTextColor(r, g, b, 1)
        else
            SetTextColor(panel.title, DUNGEON_NAME_COLOR)
        end
    end

    for _, row in ipairs(panel.rows or {}) do
        if row.hover and row.hover.SetColorTexture then
            row.hover:SetColorTexture(r or 1, g or 0.82, b or 0.1, 0.12)
        end
        for _, line in ipairs({ row.borderTop, row.borderBottom, row.borderLeft, row.borderRight }) do
            if line and line.SetColorTexture then
                line:SetColorTexture(r or 1, g or 0.82, b or 0.1, 0.24)
            end
        end
    end
    for _, tile in ipairs(panel.tiles or {}) do
        if tile.hover and tile.hover.SetColorTexture then
            tile.hover:SetColorTexture(r or 1, g or 0.82, b or 0.1, 0.12)
        end
        PVEEnhancement.StatsPanel.SetTileBorderColor(
            tile,
            tile._yuiStatsHover == true and PVEEnhancement.StatsPanel.tileBorderHover or PVEEnhancement.StatsPanel.tileBorder,
            tile._yuiStatsHover == true and PVEEnhancement.StatsPanel.tileDividerHover or PVEEnhancement.StatsPanel.tileDivider
        )
    end
    PVEEnhancement.StatsPanel.RefreshProgressDivider(panel)
    PVEEnhancement.StatsPanel.RefreshFooterDivider(panel)
end

function StatsPanelAppearance.OnLooksChanged()
    if statsPanel and PVEEnhancement.StatsPanel.ApplySkin then
        PVEEnhancement.StatsPanel.ApplySkin(statsPanel)
    end
end

function StatsPanelAppearance.AcceptOfficial(facade)
    local appearance = YUI.GUI2 and YUI.GUI2.WindowAppearance
    if appearance and type(appearance.AcceptOfficial) == "function" then
        return appearance:AcceptOfficial(facade)
    end
end

function StatsPanelAppearance.RegisterOfficial()
    local appearance = YUI.GUI2 and YUI.GUI2.WindowAppearance
    if not appearance or type(appearance.Resolve) ~= "function" then return false end
    local context = appearance:Resolve("auto", { blizzardWindow = "lfg" })
    return context and context.source == "ellesmere" or false
end

local function SetNativeStatsPanelChromeShown(panel, shown)
    if not panel then return end
    if shown then
        EnsureNativeStatsPanelChrome(panel)
    end
    SetStatsRegionShown(panel.nativeChrome, shown)
end

local function RefreshStatsPanelLayout(panel, skinMode)
    if not panel then return end

    if panel.title then
        panel.title:ClearAllPoints()
        panel.title:SetPoint("TOPLEFT", PVE_STATS_PANEL_PADDING, -6)
        panel.title:SetPoint("TOPRIGHT", -PVE_STATS_PANEL_PADDING, -6)
        panel.title:SetHeight(20)
        if panel.title.SetFont then
            panel.title:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 15, "")
        end
        panel.title:SetShadowColor(0, 0, 0, 0)
        panel.title:SetShadowOffset(0, 0)
    end

    if panel.content then
        panel.content:ClearAllPoints()
        panel.content:SetPoint("TOPLEFT", PVE_STATS_PANEL_PADDING, -PVE_STATS_HEADER_HEIGHT)
        panel.content:SetPoint("RIGHT", panel, "RIGHT", -PVE_STATS_PANEL_PADDING, 0)
        panel.content:SetPoint("BOTTOM", panel, "BOTTOM", 0, PVE_STATS_PANEL_PADDING)
    end
end

ApplyNativeStatsPanelBackdrop = function(panel)
    if not (panel and panel.SetBackdrop) then return end
    panel:SetBackdrop({
        bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0.05, 0.05, 0.06, 0.88)
    panel:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
end

local function GetStatsPanelElvUI()
    local elvui = type(_G.ElvUI) == "table" and _G.ElvUI or nil
    local E = elvui and elvui[1]
    if type(E) == "table" and E.initialized then
        return E
    end
end

function StatsPanelAppearance.GetBaseSkinMode(panel)
    if panel and panel.SetTemplate and GetStatsPanelElvUI() then return "elvui" end
    return "native"
end

function StatsPanelAppearance.ApplySharedShell(panel, context)
    local appearance = YUI.GUI2 and YUI.GUI2.WindowAppearance
    if appearance and type(appearance.ApplyExternalShell) == "function" then
        return appearance:ApplyExternalShell(panel, context)
    end
    return false
end

function StatsPanelAppearance.GetSkinMode(panel)
    local appearance = YUI.GUI2 and YUI.GUI2.WindowAppearance
    if appearance and type(appearance.Resolve) == "function" then
        local context = appearance:Resolve("auto", { blizzardWindow = "lfg" })
        if context and (
            context.source == "ellesmere"
            or context.source == "elvui"
            or context.source == "ndui"
            or context.source == "native"
        ) then
            return context.source, context
        end
    end
    local legacyContext = StatsPanelAppearance.ResolveLegacyContext()
    if legacyContext then
        return "ellesmere", legacyContext
    end
    return StatsPanelAppearance.GetBaseSkinMode(panel), nil
end

function StatsPanelAppearance.GetFallbackSkinMode(panel)
    local appearance = YUI.GUI2 and YUI.GUI2.WindowAppearance
    if appearance and type(appearance.Resolve) == "function" then
        local context = appearance:Resolve("auto", { skip = { ellesmere = true }, blizzardWindow = "lfg" })
        if context then return context.source, context end
    end
    return StatsPanelAppearance.GetBaseSkinMode(panel), nil
end

function PVEEnhancement.StatsPanel.ApplySkin(panel)
    if not panel then return end

    local mode, provider = StatsPanelAppearance.GetSkinMode(panel)
    StatsPanelAppearance.activeContext = provider
    SetStatsPanelGUI2VisualsShown(panel, false)
    SetNativeStatsPanelChromeShown(panel, mode == "native")
    SetStatsRegionShown(panel.nduiBg, mode == "ndui")
    StatsPanelAppearance.SetLegacyVisualsShown(panel, false)

    if mode == "ellesmere" then
        if panel.SetBackdrop then panel:SetBackdrop(nil) end
        if provider and (provider.facade or provider.customShell == true) then
            local ok = StatsPanelAppearance.ApplySharedShell(panel, provider)
            if not ok then
                mode, provider = StatsPanelAppearance.GetFallbackSkinMode(panel)
            end
        elseif provider and provider.providerKind == "legacy"
            and not StatsPanelAppearance.ApplyLegacyVisuals(panel, provider)
        then
            mode, provider = StatsPanelAppearance.GetFallbackSkinMode(panel)
        end
        if mode ~= "ellesmere" then
            StatsPanelAppearance.activeContext = provider
            SetNativeStatsPanelChromeShown(panel, mode == "native")
            SetStatsRegionShown(panel.nduiBg, mode == "ndui")
        end
    end

    if mode == "elvui" then
        if panel.SetBackdrop then panel:SetBackdrop(nil) end
        pcall(panel.SetTemplate, panel, "Transparent")
    elseif mode == "ndui" then
        local ok, bg = StatsPanelAppearance.ApplySharedShell(panel, provider)
        if ok then
            panel.nduiBg = bg
        else
            mode, provider = StatsPanelAppearance.GetFallbackSkinMode(panel)
            StatsPanelAppearance.activeContext = provider
            if mode == "elvui" then
                if panel.SetBackdrop then panel:SetBackdrop(nil) end
                pcall(panel.SetTemplate, panel, "Transparent")
            else
                if EnsureNativeStatsPanelChrome(panel) then
                    if panel.SetBackdrop then panel:SetBackdrop(nil) end
                else
                    ApplyNativeStatsPanelBackdrop(panel)
                end
            end
        end
    else
        if EnsureNativeStatsPanelChrome(panel) then
            if panel.SetBackdrop then panel:SetBackdrop(nil) end
        else
            ApplyNativeStatsPanelBackdrop(panel)
        end
    end

    panel._yuiPVEStatsSkinMode = mode
    RefreshStatsPanelLayout(panel, mode)
    StatsPanelAppearance.RefreshFonts()
    StatsPanelAppearance.RefreshAccent(panel)
end

local UpdateStatsRowStatus

local function RefreshStatsRowTextLayout(row, hover)
    if not (row and row.header and row.nameText and row.statusText) then return end

    local nameWidth = 48
    if row.nameText.GetStringWidth then
        nameWidth = math.ceil((row.nameText:GetStringWidth() or 0) + 8)
    end
    nameWidth = ClampNumber(nameWidth, 44, hover and 96 or 132, 48)

    row.nameText:ClearAllPoints()
    row.nameText:SetPoint("TOPLEFT", row.header, "TOPLEFT", 0, 0)
    row.nameText:SetWidth(nameWidth)

    row.statusText:ClearAllPoints()
    if hover then
        row.statusText:SetPoint("TOPLEFT", row.nameText, "TOPRIGHT", 4, 0)
        row.statusText:SetPoint("TOPRIGHT", row.header, "TOPRIGHT", 0, 0)
        if row.header.GetWidth then
            local available = (row.header:GetWidth() or 0) - nameWidth - 4
            row.statusText:SetWidth(math.max(PVE_STATS_STATUS_WIDTH, available))
        end
        row.statusText:SetJustifyH("RIGHT")
    else
        row.statusText:SetPoint("TOPRIGHT", row.header, "TOPRIGHT", 0, 0)
        row.statusText:SetWidth(PVE_STATS_STATUS_WIDTH + 12)
        row.statusText:SetJustifyH("RIGHT")
    end
end

function PVEEnhancement.NormalizeStatsTextureSource(texture)
    if texture == nil or texture == 0 or texture == "" then return nil end
    return texture
end

function PVEEnhancement.SetStatsRowGradient(texture, leftAlpha, rightAlpha)
    if not texture then return end
    texture:SetColorTexture(0, 0, 0, math.max(leftAlpha or 0, rightAlpha or 0))
    if texture.SetGradientAlpha then
        local ok = pcall(texture.SetGradientAlpha, texture, "HORIZONTAL", 0, 0, 0, leftAlpha or 0, 0, 0, 0, rightAlpha or 0)
        if ok then return end
    end
    if texture.SetGradient and CreateColor then
        pcall(texture.SetGradient, texture, "HORIZONTAL", CreateColor(0, 0, 0, leftAlpha or 0), CreateColor(0, 0, 0, rightAlpha or 0))
    end
end

function PVEEnhancement.CreateStatsRowLine(parent)
    local line = parent:CreateTexture(nil, "BORDER")
    if line.SetSnapToPixelGrid then pcall(line.SetSnapToPixelGrid, line, false) end
    if line.SetTexelSnappingBias then pcall(line.SetTexelSnappingBias, line, 0) end
    line:SetColorTexture(1, 0.82, 0.1, 0.24)
    return line
end

function PVEEnhancement.LayoutStatsRowBackground(row)
    if not (row and row.bg) then return end

    local width = row.GetWidth and row:GetWidth() or 0
    if width <= 0 then
        width = PVE_STATS_PANEL_WIDTH - (PVE_STATS_PANEL_PADDING * 2)
    end

    local height = row.GetHeight and row:GetHeight() or 0
    if height <= 0 then height = PVE_STATS_ROW_MAX_HEIGHT end

    local aspect = row.bgAspect or 2
    local bgWidth = width
    local bgHeight = width / aspect
    if bgHeight < height then
        bgHeight = height
        bgWidth = height * aspect
    end

    row.bg:ClearAllPoints()
    row.bg:SetSize(math.ceil(bgWidth * 1.08), math.ceil(bgHeight * 1.08))
    row.bg:SetPoint("CENTER", row, "CENTER", 0, 0)
end

function PVEEnhancement.SetStatsRowBackground(row, rowData)
    if not (row and row.bg) then return end
    rowData = rowData or {}

    local tileTexture = PVEEnhancement.NormalizeStatsTextureSource(rowData.texture)
    local backgroundTexture = PVEEnhancement.NormalizeStatsTextureSource(rowData.backgroundTexture)
    local isTileArt = row.yuiStatsTileArt == true
    local texture
    local source
    if isTileArt then
        texture = tileTexture
        source = texture and "tile" or nil
        if not texture then
            texture = backgroundTexture
            source = texture and "background" or nil
        end
    else
        texture = backgroundTexture
        source = texture and "background" or nil
        if not texture then
            texture = tileTexture
            source = texture and "icon" or nil
        end
    end
    if not texture then
        texture = "Interface\\Icons\\INV_Misc_QuestionMark"
        source = "fallback"
    end

    local usesWideBackground = source == "background"
    local isIconFallback = source == "icon" or source == "fallback"

    row.bg:SetTexture(texture)
    if row.bg.SetTexCoord then
        if isIconFallback then
            row.bg:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            row.bg:SetTexCoord(0, 1, 0, 1)
        end
    end
    local alpha = source == "tile" and PVEEnhancement.StatsPanel.tileArtAlpha or (usesWideBackground and 0.34 or 0.2)
    row.bg:SetAlpha(alpha)
    row.yuiStatsBackgroundIsFallbackIcon = isIconFallback
    row.yuiStatsBackgroundUsesWideArt = usesWideBackground
    row.yuiStatsBackgroundSource = source
    row.bgAspect = usesWideBackground and 2 or 1
    PVEEnhancement.LayoutStatsRowBackground(row)
end

local function CreateStatsRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(PVE_STATS_ROW_MAX_HEIGHT)
    row:EnableMouse(true)
    if row.SetClipsChildren then row:SetClipsChildren(true) end

    row.bg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    row.bg:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    row.bg:SetAlpha(0.24)

    row.tint = row:CreateTexture(nil, "BACKGROUND", nil, -7)
    row.tint:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.tint:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.tint:SetColorTexture(0, 0, 0, 0.48)

    row.leftShade = row:CreateTexture(nil, "BACKGROUND", nil, -6)
    row.leftShade:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.leftShade:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.leftShade:SetWidth(112)
    PVEEnhancement.SetStatsRowGradient(row.leftShade, 0.38, 0.04)

    row.rightShade = row:CreateTexture(nil, "BACKGROUND", nil, -6)
    row.rightShade:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.rightShade:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.rightShade:SetWidth(118)
    PVEEnhancement.SetStatsRowGradient(row.rightShade, 0.02, 0.46)

    row.borderTop = PVEEnhancement.CreateStatsRowLine(row)
    row.borderTop:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.borderTop:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.borderTop:SetHeight(1)

    row.borderBottom = PVEEnhancement.CreateStatsRowLine(row)
    row.borderBottom:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.borderBottom:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.borderBottom:SetHeight(1)

    row.borderLeft = PVEEnhancement.CreateStatsRowLine(row)
    row.borderLeft:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.borderLeft:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.borderLeft:SetWidth(1)

    row.borderRight = PVEEnhancement.CreateStatsRowLine(row)
    row.borderRight:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.borderRight:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.borderRight:SetWidth(1)

    row.hover = row:CreateTexture(nil, "ARTWORK")
    row.hover:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.hover:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.hover:SetColorTexture(1, 0.82, 0.1, 0.12)
    row.hover:Hide()

    row.header = CreateFrame("Frame", nil, row)
    row.header:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -5)
    row.header:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
    row.header:SetHeight(18)

    row.nameText = CreateStatsFontString(row, 13, "OUTLINE", "LEFT")
    row.nameText:SetPoint("TOPLEFT", row.header, "TOPLEFT", 0, 0)
    row.nameText:SetWidth(92)
    row.nameText:SetHeight(18)
    SetTextColor(row.nameText, DUNGEON_NAME_COLOR)

    row.statusText = CreateStatsFontString(row, 13, "OUTLINE", "RIGHT")
    row.statusText:SetPoint("TOPRIGHT", row.header, "TOPRIGHT", 0, 0)
    row.statusText:SetWidth(PVE_STATS_STATUS_WIDTH + 12)
    row.statusText:SetHeight(18)

    row.levelText = CreateStatsFontString(row, 12, "OUTLINE", "LEFT")
    row.levelText:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 5)
    row.levelText:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 5)
    row.levelText:SetHeight(16)
    if row.levelText.SetJustifyV then row.levelText:SetJustifyV("BOTTOM") end

    row:SetScript("OnEnter", function(frame)
        frame._yuiStatsHover = true
        if frame.hover then frame.hover:Show() end
        if UpdateStatsRowStatus then
            UpdateStatsRowStatus(frame, frame.rowData, true)
        end
    end)
    row:SetScript("OnLeave", function(frame)
        frame._yuiStatsHover = false
        if frame.hover then frame.hover:Hide() end
        if UpdateStatsRowStatus then
            UpdateStatsRowStatus(frame, frame.rowData, false)
        end
    end)
    return row
end

local function EnsureStatsRows(panel, count)
    panel.rows = panel.rows or {}
    for index = #panel.rows + 1, count do
        panel.rows[index] = CreateStatsRow(panel.content)
    end
    for index, row in ipairs(panel.rows) do
        if index > count then
            row.rowData = nil
            row._yuiStatsHover = false
            if row.hover then row.hover:Hide() end
            row:Hide()
        end
    end
end

local function GetWeeklyCountColor(count)
    count = tonumber(count) or 0
    if count <= 0 then return PVE_STATS_GRAY end
    if count >= 32 then return PVE_STATS_WEEKLY_COLORS.max end
    if count >= 16 then return PVE_STATS_WEEKLY_COLORS.high end
    if count >= 8 then return PVE_STATS_WEEKLY_COLORS.medium end
    return PVE_STATS_WEEKLY_COLORS.low
end

function PVEEnhancement.StatsPanel.GetVaultCountColor(count)
    count = tonumber(count) or 0
    if count <= 0 then return PVE_STATS_GRAY end
    return GetWeeklyCountColor(count)
end

local function FormatStatsRunLevels(runs)
    if type(runs) ~= "table" or #runs == 0 then return "" end

    local parts = {}
    local displayCount = math.min(#runs, PVE_STATS_MAX_RUNS)
    for index = 1, displayCount do
        local run = runs[index]
        local color = run.inTime and DURATION_IN_TIME_COLOR or DURATION_OVERTIME_COLOR
        parts[#parts + 1] = ColorText("+" .. tostring(run.level or 0), color)
    end

    local overflow = #runs - displayCount
    if overflow > 0 then
        parts[#parts + 1] = ColorText("(+" .. tostring(overflow) .. ")", PVE_STATS_GRAY)
    end

    return table.concat(parts, " ")
end

local function FormatStatsRunCount(count)
    return string.format(T("pve.stats.run_count", "%d次"), tonumber(count) or 0)
end

function PVEEnhancement.StatsPanel.SetTileBorderColor(tile, color, dividerColor)
    if not tile then return end
    color = color or PVEEnhancement.StatsPanel.tileBorder
    local accentR, accentG, accentB = StatsPanelAppearance.GetAccentColor()
    local hoverBorder = color == PVEEnhancement.StatsPanel.tileBorderHover
    for _, line in ipairs(tile.borderLines or {}) do
        if accentR and hoverBorder and line.SetColorTexture then
            line:SetColorTexture(accentR, accentG, accentB, color.a or color[4] or 0.78)
        else
            PVEEnhancement.StatsPanel.SetTextureColor(line, color)
        end
    end
    if tile.divider then
        dividerColor = dividerColor or (color == PVEEnhancement.StatsPanel.tileBorderHover and PVEEnhancement.StatsPanel.tileDividerHover or PVEEnhancement.StatsPanel.tileDivider)
        if accentR and tile.divider.SetColorTexture then
            tile.divider:SetColorTexture(accentR, accentG, accentB, dividerColor.a or dividerColor[4] or 0.26)
        else
            PVEEnhancement.StatsPanel.SetTextureColor(tile.divider, dividerColor)
        end
    end
end

function PVEEnhancement.StatsPanel.UpdateTilePixelBorder(tile)
    if not tile then return end
    local size = PVEEnhancement.StatsPanel.GetPixelSize(tile, 1)
    if tile.borderTop then tile.borderTop:SetHeight(size) end
    if tile.borderBottom then tile.borderBottom:SetHeight(size) end
    if tile.borderLeft then tile.borderLeft:SetWidth(size) end
    if tile.borderRight then tile.borderRight:SetWidth(size) end
    if tile.divider then tile.divider:SetWidth(size) end
end

function PVEEnhancement.StatsPanel.FormatTooltipSummary(key, fallback, total, timed, overtime)
    return string.format(
        T(key, fallback),
        ColorText(total or 0, PVE_STATS_WHITE),
        ColorText(timed or 0, DURATION_IN_TIME_COLOR),
        ColorText(overtime or 0, DURATION_OVERTIME_COLOR)
    )
end

function PVEEnhancement.StatsPanel.GetRecentWeeklyRuns(rowData)
    local source = rowData and rowData.weekRuns
    if type(source) ~= "table" or #source == 0 then return nil end

    local runs = {}
    for index, run in ipairs(source) do
        runs[index] = run
    end
    table.sort(runs, function(a, b)
        local levelA = tonumber(a and a.level) or 0
        local levelB = tonumber(b and b.level) or 0
        if levelA ~= levelB then return levelA > levelB end
        local dateA = tonumber(a and a.dateValue) or 0
        local dateB = tonumber(b and b.dateValue) or 0
        if dateA ~= dateB then return dateA > dateB end
        return (tonumber(a and a.durationSec) or 0) < (tonumber(b and b.durationSec) or 0)
    end)
    return runs
end

function PVEEnhancement.StatsPanel.AddRecentRunsToTooltip(rowData)
    local runs = PVEEnhancement.StatsPanel.GetRecentWeeklyRuns(rowData)
    local total = runs and #runs or 0
    local displayCount = math.min(total, PVEEnhancement.StatsPanel.tooltipRunLimit)

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format(T("pve.stats.tooltip_recent_runs", "本周最佳%d场："), displayCount), DUNGEON_NAME_COLOR.r, DUNGEON_NAME_COLOR.g, DUNGEON_NAME_COLOR.b)
    if displayCount <= 0 then
        GameTooltip:AddLine(T("pve.stats.no_record", "无记录"), PVE_STATS_GRAY.r, PVE_STATS_GRAY.g, PVE_STATS_GRAY.b)
        return
    end

    local parts = {}
    for index = 1, displayCount do
        local run = runs[index]
        local color = run and run.inTime and DURATION_IN_TIME_COLOR or DURATION_OVERTIME_COLOR
        parts[#parts + 1] = ColorText("+" .. tostring(run and run.level or 0), color)
        if #parts >= PVEEnhancement.StatsPanel.tooltipRunsPerLine then
            GameTooltip:AddLine(table.concat(parts, " "), 1, 1, 1)
            parts = {}
        end
    end
    if #parts > 0 then
        GameTooltip:AddLine(table.concat(parts, " "), 1, 1, 1)
    end
    if total > displayCount then
        GameTooltip:AddLine("...", PVE_STATS_GRAY.r, PVE_STATS_GRAY.g, PVE_STATS_GRAY.b)
    end
end

function PVEEnhancement.StatsPanel.ShowTileTooltip(tile)
    if not (tile and tile.rowData and GameTooltip) then return end
    local rowData = tile.rowData
    local panel = tile.panel
    if panel then panel.activeTooltipOwner = tile end

    GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(rowData.shortName or rowData.name or "", DUNGEON_NAME_COLOR.r, DUNGEON_NAME_COLOR.g, DUNGEON_NAME_COLOR.b)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(PVEEnhancement.StatsPanel.FormatTooltipSummary("pve.stats.tooltip_season", "赛季：%s %s %s", rowData.seasonTotal, rowData.seasonTimed, rowData.seasonOvertime), 1, 1, 1)
    GameTooltip:AddLine(PVEEnhancement.StatsPanel.FormatTooltipSummary("pve.stats.tooltip_week", "本周：%s %s %s", rowData.weekTotal, rowData.weekTimed, rowData.weekOvertime), 1, 1, 1)
    PVEEnhancement.StatsPanel.AddRecentRunsToTooltip(rowData)
    GameTooltip:Show()
end

function PVEEnhancement.StatsPanel.CreateTile(parent)
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetHeight(PVEEnhancement.StatsPanel.tileMaxHeight)
    tile:EnableMouse(true)
    tile.yuiStatsTileArt = true
    if tile.SetClipsChildren then tile:SetClipsChildren(true) end

    tile.bg = tile:CreateTexture(nil, "BACKGROUND")
    tile.bg:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    tile.bg:SetAlpha(PVEEnhancement.StatsPanel.tileArtAlpha)

    tile.tint = tile:CreateTexture(nil, "BACKGROUND", nil, 1)
    tile.tint:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
    tile.tint:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 0, 0)
    tile.tint:SetColorTexture(0, 0, 0, PVEEnhancement.StatsPanel.tileTintAlpha)

    tile.leftShade = tile:CreateTexture(nil, "BACKGROUND", nil, 2)
    tile.leftShade:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
    tile.leftShade:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 0, 0)
    tile.leftShade:SetWidth(72)
    PVEEnhancement.SetStatsRowGradient(tile.leftShade, 0.48, 0.12)

    tile.rightShade = tile:CreateTexture(nil, "BACKGROUND", nil, 2)
    tile.rightShade:SetPoint("TOPRIGHT", tile, "TOPRIGHT", 0, 0)
    tile.rightShade:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 0, 0)
    tile.rightShade:SetWidth(64)
    PVEEnhancement.SetStatsRowGradient(tile.rightShade, 0.12, 0.36)

    tile.hover = tile:CreateTexture(nil, "ARTWORK")
    tile.hover:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
    tile.hover:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 0, 0)
    tile.hover:SetColorTexture(1, 0.82, 0.1, 0.12)
    tile.hover:Hide()

    tile.borderTop = PVEEnhancement.CreateStatsRowLine(tile)
    tile.borderTop:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
    tile.borderTop:SetPoint("TOPRIGHT", tile, "TOPRIGHT", 0, 0)
    tile.borderTop:SetHeight(1)

    tile.borderBottom = PVEEnhancement.CreateStatsRowLine(tile)
    tile.borderBottom:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 0, 0)
    tile.borderBottom:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 0, 0)
    tile.borderBottom:SetHeight(1)

    tile.borderLeft = PVEEnhancement.CreateStatsRowLine(tile)
    tile.borderLeft:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
    tile.borderLeft:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 0, 0)
    tile.borderLeft:SetWidth(1)

    tile.borderRight = PVEEnhancement.CreateStatsRowLine(tile)
    tile.borderRight:SetPoint("TOPRIGHT", tile, "TOPRIGHT", 0, 0)
    tile.borderRight:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 0, 0)
    tile.borderRight:SetWidth(1)

    tile.borderLines = { tile.borderTop, tile.borderBottom, tile.borderLeft, tile.borderRight }
    PVEEnhancement.StatsPanel.SetTileBorderColor(tile, PVEEnhancement.StatsPanel.tileBorder, PVEEnhancement.StatsPanel.tileDivider)
    PVEEnhancement.StatsPanel.UpdateTilePixelBorder(tile)

    tile.nameText = CreateStatsFontString(tile, PVEEnhancement.StatsPanel.tileNameFontSize, "OUTLINE", "LEFT")
    tile.nameText:SetPoint("LEFT", tile, "LEFT", 8, 0)
    tile.nameText:SetPoint("RIGHT", tile, "CENTER", 16, 0)
    tile.nameText:SetHeight(20)
    SetTextColor(tile.nameText, DUNGEON_NAME_COLOR)

    tile.countText = CreateStatsFontString(tile, PVEEnhancement.StatsPanel.tileCountFontSize, "OUTLINE", "RIGHT")
    tile.countText:SetPoint("LEFT", tile, "CENTER", 16, 0)
    tile.countText:SetPoint("RIGHT", tile, "RIGHT", -8, 0)
    tile.countText:SetHeight(24)

    tile:SetScript("OnEnter", function(frame)
        frame._yuiStatsHover = true
        if frame.hover then frame.hover:Show() end
        PVEEnhancement.StatsPanel.SetTileBorderColor(frame, PVEEnhancement.StatsPanel.tileBorderHover, PVEEnhancement.StatsPanel.tileDividerHover)
        PVEEnhancement.StatsPanel.ShowTileTooltip(frame)
    end)
    tile:SetScript("OnLeave", function(frame)
        frame._yuiStatsHover = false
        if frame.hover then frame.hover:Hide() end
        PVEEnhancement.StatsPanel.SetTileBorderColor(frame, PVEEnhancement.StatsPanel.tileBorder, PVEEnhancement.StatsPanel.tileDivider)
        if frame.panel then frame.panel.activeTooltipOwner = nil end
        if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(frame) then
            YUI.HideGameTooltip()
        end
    end)

    return tile
end

function PVEEnhancement.StatsPanel.EnsureTiles(panel, count)
    panel.tiles = panel.tiles or {}
    for index = #panel.tiles + 1, count do
        panel.tiles[index] = PVEEnhancement.StatsPanel.CreateTile(panel.tilesHost or panel.content)
        panel.tiles[index].panel = panel
    end
    for index, tile in ipairs(panel.tiles) do
        if index > count then
            tile.rowData = nil
            tile._yuiStatsHover = false
            if tile.hover then tile.hover:Hide() end
            tile:Hide()
        end
    end
end

local function FormatStatsRowHoverStatus(rowData)
    rowData = rowData or {}
    return string.format(
        T("pve.stats.row_hover", "%s %s %s | 总 %s %s %s"),
        rowData.weekTotal or 0,
        ColorText(rowData.weekTimed or 0, DURATION_IN_TIME_COLOR),
        ColorText(rowData.weekOvertime or 0, DURATION_OVERTIME_COLOR),
        rowData.seasonTotal or 0,
        ColorText(rowData.seasonTimed or 0, DURATION_IN_TIME_COLOR),
        ColorText(rowData.seasonOvertime or 0, DURATION_OVERTIME_COLOR)
    )
end

UpdateStatsRowStatus = function(row, rowData, hover)
    if not (row and row.statusText) then return end
    rowData = rowData or {}

    if row.statusText.SetFont then
        row.statusText:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    end
    RefreshStatsRowTextLayout(row, hover == true)

    if hover then
        row.statusText:SetText(FormatStatsRowHoverStatus(rowData))
        SetTextColor(row.statusText, PVE_STATS_WHITE)
        return
    end

    local weekTotal = tonumber(rowData.weekTotal) or 0
    if weekTotal <= 0 then
        row.statusText:SetText(T("pve.stats.no_record", "无记录"))
        SetTextColor(row.statusText, PVE_STATS_GRAY)
        return
    end

    row.statusText:SetText(FormatStatsRunCount(weekTotal))
    SetTextColor(row.statusText, PVE_STATS_WHITE)
end

local function RenderStatsPanelRows(panel, rows)
    local count = type(rows) == "table" and #rows or 0
    if panel.rows then
        for _, row in ipairs(panel.rows) do
            row:Hide()
        end
    end
    PVEEnhancement.StatsPanel.EnsureTiles(panel, count)
    if count <= 0 then return end

    local host = panel.tilesHost or panel.content
    if not host then return end

    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -PVEEnhancement.StatsPanel.summaryHeight)
    host:SetPoint("BOTTOMRIGHT", panel.content, "BOTTOMRIGHT", 0, 0)

    local width = host.GetWidth and host:GetWidth() or 0
    if width <= 0 then
        width = PVE_STATS_PANEL_WIDTH - (PVE_STATS_PANEL_PADDING * 2)
    end

    local available = host.GetHeight and host:GetHeight() or 0
    if available <= 0 then
        local contentHeight = panel.content and panel.content.GetHeight and panel.content:GetHeight() or 0
        if contentHeight <= 0 then
            local height = panel.GetHeight and panel:GetHeight() or 0
            contentHeight = math.max(0, height - PVE_STATS_HEADER_HEIGHT - (PVE_STATS_PANEL_PADDING * 2))
        end
        available = math.max(0, contentHeight - PVEEnhancement.StatsPanel.summaryHeight)
    end

    local columns = PVEEnhancement.StatsPanel.tileColumns
    local rowCount = math.ceil(count / columns)
    local tileWidth = math.floor((width - ((columns - 1) * PVEEnhancement.StatsPanel.tileGap)) / columns)
    local totalGap = math.max(0, rowCount - 1) * PVEEnhancement.StatsPanel.tileGap
    local tileHeight = math.floor(math.max(0, available - totalGap) / math.max(rowCount, 1))
    if tileHeight >= PVEEnhancement.StatsPanel.tileMinHeight then
        tileHeight = math.max(PVEEnhancement.StatsPanel.tileMinHeight, math.min(PVEEnhancement.StatsPanel.tileMaxHeight, tileHeight))
    else
        tileHeight = math.max(1, tileHeight)
    end

    for index, rowData in ipairs(rows) do
        local tile = panel.tiles[index]
        local column = (index - 1) % columns
        local tileRow = math.floor((index - 1) / columns)
        local yOffset = -(tileRow * (tileHeight + PVEEnhancement.StatsPanel.tileGap))
        tile:ClearAllPoints()
        if columns == 2 then
            local leftGap = math.floor(PVEEnhancement.StatsPanel.tileGap / 2)
            local rightGap = PVEEnhancement.StatsPanel.tileGap - leftGap
            if column == 0 then
                tile:SetPoint("TOPLEFT", host, "TOPLEFT", 0, yOffset)
                tile:SetPoint("TOPRIGHT", host, "TOP", -rightGap, yOffset)
            else
                tile:SetPoint("TOPLEFT", host, "TOP", leftGap, yOffset)
                tile:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, yOffset)
            end
            tile:SetWidth(tileWidth)
            tile:SetHeight(tileHeight)
        else
            tile:SetPoint("TOPLEFT", host, "TOPLEFT", column * (tileWidth + PVEEnhancement.StatsPanel.tileGap), yOffset)
            tile:SetSize(tileWidth, tileHeight)
        end
        tile:SetParent(host)
        tile:Show()

        tile.rowData = rowData
        if tile.hover then
            if tile._yuiStatsHover == true then
                tile.hover:Show()
            else
                tile.hover:Hide()
            end
        end
        PVEEnhancement.SetStatsRowBackground(tile, rowData)
        PVEEnhancement.StatsPanel.UpdateTilePixelBorder(tile)
        PVEEnhancement.StatsPanel.SetTileBorderColor(
            tile,
            tile._yuiStatsHover == true and PVEEnhancement.StatsPanel.tileBorderHover or PVEEnhancement.StatsPanel.tileBorder,
            tile._yuiStatsHover == true and PVEEnhancement.StatsPanel.tileDividerHover or PVEEnhancement.StatsPanel.tileDivider
        )
        tile.nameText:SetText(rowData.shortName or rowData.name or "")

        local weekTotal = tonumber(rowData.weekTotal) or 0
        tile.countText:SetText(tostring(weekTotal))
        SetTextColor(tile.countText, weekTotal > 0 and DURATION_IN_TIME_COLOR or PVE_STATS_GRAY)
    end
end

function PVEEnhancement.StatsPanel.LayoutPlayerLine(panel)
    if not (panel and panel.playerInfoFrame and panel.playerNameText) then return end

    local header = panel.playerHeaderFrame or panel.playerInfoFrame
    local raceIconSize = PVEEnhancement.StatsPanel.playerIconSize or 28
    local specIconSize = PVEEnhancement.StatsPanel.playerSpecIconSize or 18
    local iconYOffset = PVEEnhancement.StatsPanel.summaryIconYOffset or 0
    local headerHeight = 30
    local x = 0
    if panel.playerRaceIcon then
        panel.playerRaceIcon:ClearAllPoints()
        if panel.playerRaceIcon:IsShown() then
            panel.playerRaceIcon:SetPoint("LEFT", header, "LEFT", x, iconYOffset)
            x = x + raceIconSize + 5
        end
    end
    if panel.playerSpecIcon then
        panel.playerSpecIcon:ClearAllPoints()
        if panel.playerSpecIcon:IsShown() then
            panel.playerSpecIcon:SetPoint("LEFT", header, "LEFT", x, iconYOffset)
            x = x + specIconSize + 6
        end
    end

    local headerWidth = header.GetWidth and header:GetWidth() or 0
    if headerWidth <= 0 then
        headerWidth = PVE_STATS_PANEL_WIDTH - (PVE_STATS_PANEL_PADDING * 2) - (PVEEnhancement.StatsPanel.summaryInfoInset * 2)
    end

    local ilvlWidth = PVEEnhancement.StatsPanel.playerIlvlWidth or 58
    if panel.playerIlvlText then
        local measure = panel.playerIlvlText.GetUnboundedStringWidth or panel.playerIlvlText.GetStringWidth
        if measure then
            local measuredWidth = measure(panel.playerIlvlText)
            if type(measuredWidth) == "number" then
                ilvlWidth = math.max(ilvlWidth, math.ceil(measuredWidth))
            end
        end
    end
    local ilvlGap = PVEEnhancement.StatsPanel.playerIlvlGap or 8
    local nameMaxWidth = math.max(48, headerWidth - x - ilvlGap - ilvlWidth)
    nameMaxWidth = math.min(nameMaxWidth, PVEEnhancement.StatsPanel.playerNameMaxWidth or nameMaxWidth)
    local nameWidth = nameMaxWidth
    if panel.playerNameText.GetStringWidth then
        nameWidth = math.ceil(panel.playerNameText:GetStringWidth() or 0)
        nameWidth = math.max(24, math.min(nameMaxWidth, nameWidth))
    end

    panel.playerNameText:ClearAllPoints()
    panel.playerNameText:SetPoint("LEFT", header, "LEFT", x, 0)
    panel.playerNameText:SetSize(nameWidth, headerHeight)
    panel.playerNameText:SetJustifyH("LEFT")

    if panel.playerIlvlText then
        panel.playerIlvlText:ClearAllPoints()
        panel.playerIlvlText:SetPoint("LEFT", panel.playerNameText, "RIGHT", ilvlGap, 0)
        panel.playerIlvlText:SetSize(ilvlWidth, headerHeight)
        panel.playerIlvlText:SetJustifyH("LEFT")
        panel.playerIlvlText:Show()
    end
end

function PVEEnhancement.StatsPanel.RenderPlayerSummary(panel)
    if not (panel and panel.playerNameText) then return end
    local classFile = PVEEnhancement.StatsPanel.GetPlayerClassFile()
    local classColor = GetClassColorByFile(classFile)

    if panel.playerRaceIcon then
        PVEEnhancement.StatsPanel.ApplyPlayerRaceIcon(panel.playerRaceIcon)
    end
    if panel.playerSpecIcon then
        PVEEnhancement.StatsPanel.ApplyIcon(panel.playerSpecIcon, PVEEnhancement.StatsPanel.GetPlayerSpecIconData())
    end
    panel.playerNameText:SetText(PVEEnhancement.StatsPanel.GetPlayerDisplayName())
    SetTextColor(panel.playerNameText, classColor, PVEEnhancement.StatsPanel.summaryText)
    if panel.playerIlvlText then
        panel.playerIlvlText:SetText(string.format(T("pve.stats.player_ilvl", "iLv. %s"), PVEEnhancement.StatsPanel.GetPlayerEquippedItemLevelText()))
        SetTextColor(panel.playerIlvlText, PVEEnhancement.StatsPanel.summaryText)
    end
    PVEEnhancement.StatsPanel.LayoutPlayerLine(panel)
end

function PVEEnhancement.StatsPanel.RenderVaultDots(panel, weeklyVaultRuns, vaultCount)
    if not (panel and panel.vaultDots) then return end
    weeklyVaultRuns = weeklyVaultRuns or {}
    vaultCount = tonumber(vaultCount) or 0
    for index, dot in ipairs(panel.vaultDots) do
        local run = weeklyVaultRuns[index]
        if index <= vaultCount then
            PVEEnhancement.StatsPanel.SetTextureVertexColor(dot, PVEEnhancement.StatsPanel.GetVaultDotColor(run and run.level))
            dot:SetAlpha(1)
        else
            PVEEnhancement.StatsPanel.SetTextureVertexColor(dot, PVEEnhancement.StatsPanel.vaultDotColors.empty)
            dot:SetAlpha(0.75)
        end
    end
end

function PVEEnhancement.StatsPanel.EnsureVaultProgressSegments(card, count)
    if not (card and card.progressHost) then return end
    count = math.max(1, math.floor(tonumber(count) or 1))
    card.progressSegments = card.progressSegments or {}
    for index = #card.progressSegments + 1, count do
        local segment = card.progressHost:CreateTexture(nil, "BORDER")
        segment:SetHeight(PVEEnhancement.StatsPanel.vaultProgressHeight)
        card.progressSegments[index] = segment
    end
end

function PVEEnhancement.StatsPanel.LayoutVaultProgress(card)
    if not (card and card.progressHost and card.progressSegments) then return end
    local count = math.max(1, math.floor(tonumber(card.progressSegmentCount) or 1))
    PVEEnhancement.StatsPanel.EnsureVaultProgressSegments(card, count)

    local width = card.progressHost.GetWidth and card.progressHost:GetWidth() or 0
    if width <= 0 and card.GetWidth then width = math.max(0, card:GetWidth() - 2) end
    if width <= 0 then width = 84 end

    local pixelSize = PVEEnhancement.StatsPanel.GetPixelSize(card.progressHost, 1)
    if type(pixelSize) ~= "number" or pixelSize <= 0 then pixelSize = 1 end
    local widthPixels = math.max(count, math.floor((width / pixelSize) + 0.5))
    local gapPixels = math.max(1, math.floor(tonumber(PVEEnhancement.StatsPanel.vaultProgressGap) or 1))
    local availablePixels = math.max(count, widthPixels - (gapPixels * (count - 1)))
    local segmentPixels = math.max(1, math.floor(availablePixels / count))
    local usedPixels = (segmentPixels * count) + (gapPixels * (count - 1))
    local xOffsetPixels = math.max(0, math.floor((widthPixels - usedPixels) / 2))
    local segmentWidth = segmentPixels * pixelSize
    local gap = gapPixels * pixelSize
    local xOffset = xOffsetPixels * pixelSize

    for index, segment in ipairs(card.progressSegments) do
        if index <= count then
            segment:ClearAllPoints()
            segment:SetPoint("BOTTOMLEFT", card.progressHost, "BOTTOMLEFT", xOffset, 0)
            segment:SetSize(segmentWidth, PVEEnhancement.StatsPanel.vaultProgressHeight)
            segment:Show()
            xOffset = xOffset + segmentWidth + gap
        else
            segment:Hide()
        end
    end
end

function PVEEnhancement.StatsPanel.RenderVaultProgress(card, model, weeklyRuns)
    if not (card and card.progressHost) then return end
    local segments = PVEEnhancement.StatsPanel.BuildVaultProgressSegments(model, weeklyRuns)
    card.progressSegmentCount = #segments
    PVEEnhancement.StatsPanel.EnsureVaultProgressSegments(card, #segments)
    local finalSegment = segments[#segments]
    local baseColor = finalSegment and finalSegment.filled and finalSegment.quality
        and PVEEnhancement.StatsPanel.GetQualityColor(finalSegment.quality)
        or PVEEnhancement.StatsPanel.vaultProgressTrack
    if card.progressTrack then
        card.progressTrack:SetColorTexture(
            baseColor.r or baseColor[1] or 1,
            baseColor.g or baseColor[2] or 1,
            baseColor.b or baseColor[3] or 1,
            finalSegment and finalSegment.filled and PVEEnhancement.StatsPanel.vaultProgressBaseAlpha or (baseColor.a or baseColor[4] or 1)
        )
    end
    for index, segmentModel in ipairs(segments) do
        local texture = card.progressSegments[index]
        local color = segmentModel.filled
            and PVEEnhancement.StatsPanel.GetQualityColor(segmentModel.quality)
            or PVEEnhancement.StatsPanel.vaultProgressTrack
        PVEEnhancement.StatsPanel.SetTextureColor(texture, color)
    end
    PVEEnhancement.StatsPanel.LayoutVaultProgress(card)
end

function PVEEnhancement.StatsPanel.ApplyVaultIcon(texture, state)
    if not texture then return end
    local atlas = PVEEnhancement.StatsPanel.GetVaultIconAtlas(state)
    local applied = texture.SetAtlas and pcall(texture.SetAtlas, texture, atlas, false)
    if not applied and texture.SetTexture then
        texture:SetTexture("Interface\\Icons\\INV_Misc_TreasureChest05")
        if texture.SetTexCoord then texture:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    end
end

function PVEEnhancement.StatsPanel.CreateVaultCard(parent, panel)
    local card = CreateFrame("Frame", nil, parent)
    card:SetHeight(PVEEnhancement.StatsPanel.vaultCardHeight)
    card:EnableMouse(true)
    card.panel = panel

    card.background = card:CreateTexture(nil, "BACKGROUND")
    card.background:SetAllPoints()
    PVEEnhancement.StatsPanel.SetTextureColor(card.background, PVEEnhancement.StatsPanel.tileBg)

    card.borderTop = PVEEnhancement.CreateStatsRowLine(card)
    card.borderTop:SetPoint("TOPLEFT")
    card.borderTop:SetPoint("TOPRIGHT")
    card.borderTop:SetHeight(1)
    card.borderBottom = PVEEnhancement.CreateStatsRowLine(card)
    card.borderBottom:SetPoint("BOTTOMLEFT")
    card.borderBottom:SetPoint("BOTTOMRIGHT")
    card.borderBottom:SetHeight(1)
    card.borderLeft = PVEEnhancement.CreateStatsRowLine(card)
    card.borderLeft:SetPoint("TOPLEFT")
    card.borderLeft:SetPoint("BOTTOMLEFT")
    card.borderLeft:SetWidth(1)
    card.borderRight = PVEEnhancement.CreateStatsRowLine(card)
    card.borderRight:SetPoint("TOPRIGHT")
    card.borderRight:SetPoint("BOTTOMRIGHT")
    card.borderRight:SetWidth(1)
    card.borderLines = { card.borderTop, card.borderBottom, card.borderLeft, card.borderRight }

    card.rewardText = CreateStatsFontString(card, PVEEnhancement.StatsPanel.vaultRewardFontSize, "OUTLINE", "CENTER")
    card.rewardText:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 3, 5)
    card.rewardText:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -3, 5)
    card.rewardText:SetHeight(22)

    card.progressHost = CreateFrame("Frame", nil, card)
    card.progressHost:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 1, 1)
    card.progressHost:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -1, 1)
    card.progressHost:SetHeight(PVEEnhancement.StatsPanel.vaultProgressHeight)
    card.progressTrack = card.progressHost:CreateTexture(nil, "BACKGROUND")
    card.progressTrack:SetAllPoints(card.progressHost)
    PVEEnhancement.StatsPanel.SetTextureColor(card.progressTrack, PVEEnhancement.StatsPanel.vaultProgressTrack)
    card.progressSegments = {}
    card.progressSegmentCount = 1

    card:SetScript("OnSizeChanged", function(frame)
        PVEEnhancement.StatsPanel.LayoutVaultProgress(frame)
        PVEEnhancement.StatsPanel.UpdateTilePixelBorder(frame)
    end)
    card:SetScript("OnEnter", function(frame)
        PVEEnhancement.StatsPanel.SetTileBorderColor(frame, PVEEnhancement.StatsPanel.tileBorderHover)
        PVEEnhancement.StatsPanel.ShowVaultTooltip(frame)
    end)
    card:SetScript("OnLeave", function(frame)
        PVEEnhancement.StatsPanel.SetTileBorderColor(frame, PVEEnhancement.StatsPanel.tileBorder)
        PVEEnhancement.StatsPanel.HideVaultTooltip(frame)
    end)
    PVEEnhancement.StatsPanel.SetTileBorderColor(card, PVEEnhancement.StatsPanel.tileBorder)
    PVEEnhancement.StatsPanel.UpdateTilePixelBorder(card)
    return card
end

function PVEEnhancement.StatsPanel.LayoutVaultReward(card, value, suffix)
    if not (card and card.rewardText) then return end
    value = value or "--"
    suffix = suffix or ""
    card.rewardText:SetText(suffix ~= "" and (value .. " " .. suffix) or value)
    card.rewardText:SetJustifyH("CENTER")
end

function PVEEnhancement.StatsPanel.RenderVaultCards(panel, weeklyCount, weeklyRuns, overrideProgress)
    if not (panel and panel.vaultCards) then return end
    local models = PVEEnhancement.StatsPanel.BuildVaultCards(weeklyCount, weeklyRuns, overrideProgress)
    panel.vaultCardModels = models
    for index, card in ipairs(panel.vaultCards) do
        local model = models[index] or {}
        card.vaultCard = model
        local value, suffix
        if model.unlocked then
            value, suffix = PVEEnhancement.StatsPanel.GetVaultRewardParts(model)
        else
            value = string.format("%d/%d", math.min(tonumber(model.progress) or 0, tonumber(model.threshold) or 0), tonumber(model.threshold) or 0)
            suffix = ""
        end
        PVEEnhancement.StatsPanel.LayoutVaultReward(card, value, suffix)
        local rewardColor = model.unlocked and PVEEnhancement.StatsPanel.GetQualityColor(model.quality) or PVEEnhancement.StatsPanel.vaultProgressIncomplete
        SetTextColor(card.rewardText, rewardColor)
        PVEEnhancement.StatsPanel.RenderVaultProgress(card, model, weeklyRuns)
    end
end

function PVEEnhancement.StatsPanel.RenderTopRuns(panel, runs)
    if not (panel and panel.topRunSlots) then return end
    local models = PVEEnhancement.StatsPanel.BuildTopRunSlots(runs)
    for index, fontString in ipairs(panel.topRunSlots) do
        local model = models[index]
        fontString:SetText(model and model.text or "—")
        SetTextColor(fontString, model and model.color or PVE_STATS_GRAY)
    end
end

function PVEEnhancement.StatsPanel.ShowVaultTooltip(owner)
    local panel = owner and owner.panel
    if not (panel and GameTooltip) then return end

    panel.activeTooltipOwner = owner
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(T("pve.stats.weekly_vault_title", "本周低保"), DUNGEON_NAME_COLOR.r, DUNGEON_NAME_COLOR.g, DUNGEON_NAME_COLOR.b)
    local card = owner.vaultCard
    if card then
        GameTooltip:AddDoubleLine(
            string.format(T("pve.stats.vault.complete", "完成 %d 把"), tonumber(card.threshold) or 0),
            string.format("%d/%d", math.min(tonumber(card.progress) or 0, tonumber(card.threshold) or 0), tonumber(card.threshold) or 0),
            1, 1, 1,
            card.unlocked and DURATION_IN_TIME_COLOR.r or PVEEnhancement.StatsPanel.vaultProgressIncomplete.r,
            card.unlocked and DURATION_IN_TIME_COLOR.g or PVEEnhancement.StatsPanel.vaultProgressIncomplete.g,
            card.unlocked and DURATION_IN_TIME_COLOR.b or PVEEnhancement.StatsPanel.vaultProgressIncomplete.b
        )
        GameTooltip:AddDoubleLine(
            T("pve.stats.vault.reward", "奖励"),
            PVEEnhancement.StatsPanel.FormatVaultRewardText(card),
            1, 1, 1,
            (PVEEnhancement.StatsPanel.GetQualityColor(card.quality).r or 1),
            (PVEEnhancement.StatsPanel.GetQualityColor(card.quality).g or 1),
            (PVEEnhancement.StatsPanel.GetQualityColor(card.quality).b or 1)
        )
    end
    GameTooltip:AddLine(" ")

    local runs = panel.weeklyVaultRuns or {}
    if #runs > 0 then
        for _, run in ipairs(runs) do
            local level = tonumber(run.level) or 0
            local name = run.shortName or run.name or (run.mapID and tostring(run.mapID)) or (UNKNOWN or "")
            GameTooltip:AddLine(string.format("%s %s", ColorText("+" .. level, GetLevelColor(level)), name), 1, 1, 1)
        end
    else
        GameTooltip:AddLine(T("pve.stats.no_record", "无记录"), PVE_STATS_GRAY.r, PVE_STATS_GRAY.g, PVE_STATS_GRAY.b)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format(T("pve.stats.weekly_vault_total", "总计：%s"), ColorText(#runs, DURATION_IN_TIME_COLOR)), 1, 1, 1)
    GameTooltip:Show()
end

function PVEEnhancement.StatsPanel.HideVaultTooltip(owner)
    if owner and owner.panel then
        owner.panel.activeTooltipOwner = nil
    end
    if GameTooltip and owner and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then
        YUI.HideGameTooltip()
    end
end

function PVEEnhancement.StatsPanel.GetCoreLocaleText(key, fallback)
    local locale
    if YUI.Locale and YUI.Locale.Get then
        locale = YUI.Locale:Get("Core")
    end
    local value = locale and locale[key]
    if type(value) == "string" and value ~= "" and value ~= key then return value end
    return fallback or key
end

function PVEEnhancement.StatsPanel.FormatCurrencyAmount(amount)
    amount = tonumber(amount) or 0
    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(amount)
    end
    return tostring(amount)
end

function PVEEnhancement.StatsPanel.FormatCurrencyProgress(quantity, maxQuantity)
    local quantityText = PVEEnhancement.StatsPanel.FormatCurrencyAmount(quantity)
    maxQuantity = tonumber(maxQuantity)
    if maxQuantity and maxQuantity > 0 then
        local maximumText = "/" .. PVEEnhancement.StatsPanel.FormatCurrencyAmount(maxQuantity)
        return quantityText .. ColorText(maximumText, PVEEnhancement.StatsPanel.summaryMuted)
    end
    return quantityText
end

function PVEEnhancement.StatsPanel.GetCurrencyDisplayText(info, showLifetimeProgress)
    if type(info) ~= "table" then return "-" end
    if showLifetimeProgress == true and tonumber(info.totalEarned) ~= nil then
        return PVEEnhancement.StatsPanel.FormatCurrencyProgress(info.totalEarned, info.maxQuantity)
    end
    return PVEEnhancement.StatsPanel.FormatCurrencyAmount(info.quantity)
end

function PVEEnhancement.StatsPanel.ShowCurrencyTooltip(owner)
    if not (owner and GameTooltip) then return end
    local currencyID = owner.currencyID
    local info
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and currencyID then
        info = SafeCall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
    end

    local title = (info and info.name) or owner.fallbackName or tostring(currencyID or "")
    owner.panel.activeTooltipOwner = owner
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(title, DUNGEON_NAME_COLOR.r, DUNGEON_NAME_COLOR.g, DUNGEON_NAME_COLOR.b)
    if info and type(info.description) == "string" and info.description ~= "" then
        GameTooltip:AddLine(info.description, 1, 1, 1, true)
    end
    if info and tonumber(info.maxQuantity) and info.maxQuantity > 0 then
        GameTooltip:AddDoubleLine(
            PVEEnhancement.StatsPanel.GetCoreLocaleText("common.max", "上限") .. ":",
            PVEEnhancement.StatsPanel.FormatCurrencyAmount(info.maxQuantity),
            1, 1, 1, 1, 1, 1
        )
    end
    if info and tonumber(info.totalEarned) and info.totalEarned > 0 then
        GameTooltip:AddDoubleLine("总获取:", PVEEnhancement.StatsPanel.FormatCurrencyAmount(info.totalEarned), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:Show()
end

function PVEEnhancement.StatsPanel.HideCurrencyTooltip(owner)
    if owner and owner.panel then
        owner.panel.activeTooltipOwner = nil
    end
    if GameTooltip and owner and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then
        YUI.HideGameTooltip()
    end
end

function PVEEnhancement.StatsPanel.HideActiveTooltip(panel)
    if not panel then return end
    local owner = panel.activeTooltipOwner or panel.footerVaultHitbox or panel.closeButton
    if GameTooltip and owner and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then
        YUI.HideGameTooltip()
    end
    panel.activeTooltipOwner = nil
end

function PVEEnhancement.StatsPanel.ClosePanel(panel)
    if not panel then return end
    PVEEnhancement._statsPanelManuallyClosed = true
    PVEEnhancement.StatsPanel.HideActiveTooltip(panel)
    panel:Hide()
end

function PVEEnhancement.StatsPanel.CreateCloseButton(parent)
    local GUI2 = YUI.GUI2
    if not (parent and GUI2 and GUI2.CreateButtonFrame) then return nil end

    local iconSize = 14
    local button = GUI2:CreateButtonFrame(parent, { template = "BackdropTemplate" })
    button.panel = parent
    button:SetSize(16, 16)
    button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4)
    if button.SetFrameLevel and parent.GetFrameLevel then
        button:SetFrameLevel((parent:GetFrameLevel() or 0) + 20)
    end
    if button.SetBackdrop then
        button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        button:SetBackdropColor(0, 0, 0, 0)
    end

    local icon
    if GUI2.CreateTexture then
        icon = GUI2:CreateTexture(button, { layer = "ARTWORK" })
    else
        icon = button:CreateTexture(nil, "ARTWORK")
    end
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("CENTER")
    if icon.SetAtlas then
        icon:SetAtlas("uitools-icon-close")
    else
        icon:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    end
    icon:SetVertexColor(0.7, 0.7, 0.7)
    button.icon = icon

    button:SetScript("OnEnter", function(frame)
        if frame.icon then frame.icon:SetVertexColor(1, 1, 1) end
        if frame.SetBackdropColor then frame:SetBackdropColor(1, 0.2, 0.2, 0.5) end
        if frame.panel then frame.panel.activeTooltipOwner = frame end
        if GameTooltip then
            GameTooltip:SetOwner(frame, "ANCHOR_TOP")
            GameTooltip:SetText(PVEEnhancement.StatsPanel.GetCoreLocaleText("layout.action.close", "Close"))
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(frame)
        if frame.icon then frame.icon:SetVertexColor(0.7, 0.7, 0.7) end
        if frame.SetBackdropColor then frame:SetBackdropColor(0, 0, 0, 0) end
        PVEEnhancement.StatsPanel.HideActiveTooltip(frame.panel)
    end)
    button:SetScript("OnClick", function(frame)
        PVEEnhancement.StatsPanel.ClosePanel(frame.panel)
    end)
    return button
end

function PVEEnhancement.StatsPanel.GetSummaryTemplateLabel(key, fallback)
    local template = T(key, fallback)
    local label = template and template:match("^(.-)%%s")
    if label and label ~= "" then return label end
    return fallback and fallback:match("^(.-)%%s") or ""
end

function PVEEnhancement.StatsPanel.FormatSummaryLabel(atlas, label, iconSize)
    label = label or ""
    if type(atlas) ~= "string" or atlas == "" then return label end
    local size = iconSize or PVEEnhancement.StatsPanel.summaryStatIconSize or 14
    local yOffset = PVEEnhancement.StatsPanel.summaryStatIconYOffset or 0
    return string.format("|A:%s:%d:%d:0:%d|a %s", atlas, size, size, yOffset, label)
end

function PVEEnhancement.StatsPanel.LayoutSummaryStat(frame, label, value, defaultLabelWidth)
    if not (frame and label and value) then return end

    local align = frame.summaryAlign or "CENTER"
    if align == "ROW" then
        local labelWidth = frame.summaryLabelWidth or defaultLabelWidth or PVEEnhancement.StatsPanel.summaryStatLabelWidth
        local measureLabel = label.GetUnboundedStringWidth or label.GetStringWidth
        if measureLabel then
            labelWidth = math.max(18, math.ceil((measureLabel(label) or 0) + 2))
        end
        local valueWidth = frame.summaryValueWidth or PVEEnhancement.StatsPanel.summaryStatValueWidth
        local measureValue = value.GetUnboundedStringWidth or value.GetStringWidth
        if measureValue then
            valueWidth = math.max(valueWidth, math.ceil((measureValue(value) or 0) + 8))
        end
        local valueInset = frame.summaryValueInset or PVEEnhancement.StatsPanel.summaryStatValueInset or 0
        local rowHeight = frame.summaryRowHeight or PVEEnhancement.StatsPanel.summaryStatRowHeight
        local gap = frame.summaryGap or PVEEnhancement.StatsPanel.summaryStatGap or 3

        label:ClearAllPoints()
        label:SetPoint("LEFT", frame, "LEFT", valueInset, 0)
        label:SetSize(labelWidth, rowHeight)
        label:SetJustifyH("LEFT")

        value:ClearAllPoints()
        value:SetPoint("LEFT", label, "RIGHT", gap, 0)
        value:SetSize(valueWidth, rowHeight)
        value:SetJustifyH("LEFT")
        return
    end

    local labelWidth = defaultLabelWidth or 40
    local measureLabel = label.GetUnboundedStringWidth or label.GetStringWidth
    if measureLabel then
        local measuredLabelWidth = math.max(1, math.ceil(measureLabel(label) or 0))
        labelWidth = align == "CENTER" and measuredLabelWidth or math.max(labelWidth, measuredLabelWidth)
    end

    local measuredValueWidth = 0
    local measureValue = value.GetUnboundedStringWidth or value.GetStringWidth
    if measureValue then
        measuredValueWidth = math.max(1, math.ceil((measureValue(value) or 0) + 2))
    end
    local valueWidth
    if align == "CENTER" or align == "RIGHT" then
        valueWidth = math.max(1, measuredValueWidth)
    else
        valueWidth = math.max(42, measuredValueWidth)
    end

    local rowHeight = frame.summaryRowHeight or PVEEnhancement.StatsPanel.summaryStatRowHeight
    label:ClearAllPoints()
    label:SetSize(labelWidth, rowHeight)

    value:ClearAllPoints()
    value:SetSize(valueWidth, rowHeight)

    if align == "LEFT" then
        label:SetPoint("LEFT", frame, "LEFT", 0, 0)
        label:SetJustifyH("LEFT")
        value:SetPoint("LEFT", label, "RIGHT", 2, 0)
        value:SetJustifyH("LEFT")
    elseif align == "RIGHT" then
        value:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        value:SetJustifyH("RIGHT")
        label:SetPoint("RIGHT", value, "LEFT", -2, 0)
        label:SetJustifyH("RIGHT")
    else
        local totalWidth = labelWidth + valueWidth + 2
        local leftOffset = -(totalWidth / 2)
        label:SetPoint("LEFT", frame, "CENTER", leftOffset, 0)
        label:SetJustifyH("LEFT")
        value:SetPoint("LEFT", label, "RIGHT", 2, 0)
        value:SetJustifyH("LEFT")
    end
end

function PVEEnhancement.StatsPanel.SetSummaryStat(frame, label, value, labelText, valueText)
    if not (frame and label and value) then return end
    label:SetText(labelText or "")
    value:SetText(valueText or "")
    SetTextColor(label, PVEEnhancement.StatsPanel.summaryText)
    SetTextColor(value, PVEEnhancement.StatsPanel.summaryText)
    PVEEnhancement.StatsPanel.LayoutSummaryStat(frame, label, value, 40)
end

function PVEEnhancement.StatsPanel.LayoutCurrencyRow(row)
    if not (row and row.text) then return end
    local rowWidth = row.GetWidth and row:GetWidth() or PVEEnhancement.StatsPanel.summaryCurrencyWidth
    if rowWidth <= 0 then rowWidth = PVEEnhancement.StatsPanel.summaryCurrencyWidth end
    local rowHeight = PVEEnhancement.StatsPanel.summaryStatRowHeight
    local yOffset = PVEEnhancement.StatsPanel.currencyContentYOffset or 0
    local iconAnchor = row.iconSlot or row.iconAnchor or row.icon
    local iconShown = iconAnchor ~= nil and (not iconAnchor.IsShown or iconAnchor:IsShown())

    row.text:ClearAllPoints()
    if not iconShown then
        row.text:SetPoint("LEFT", row, "LEFT", 0, yOffset)
        row.text:SetPoint("RIGHT", row, "RIGHT", 0, yOffset)
        row.text:SetHeight(rowHeight)
        row.text:SetJustifyH("CENTER")
        return
    end

    local iconSize = PVEEnhancement.StatsPanel.currencyIconSize
    local gap = 4
    local textWidth = 16
    local measureText = row.text.GetUnboundedStringWidth or row.text.GetStringWidth
    if measureText then
        textWidth = math.max(textWidth, math.ceil(measureText(row.text) or 0))
    end
    textWidth = math.min(textWidth, math.max(16, rowWidth - iconSize - gap))
    local groupWidth = iconSize + gap + textWidth
    iconAnchor:ClearAllPoints()
    iconAnchor:SetPoint("LEFT", row, "CENTER", -(groupWidth / 2), yOffset)
    row.text:SetPoint("LEFT", iconAnchor, "RIGHT", gap, 0)
    row.text:SetSize(textWidth, rowHeight)
    row.text:SetJustifyH("LEFT")
end

function PVEEnhancement.StatsPanel.UpdateCurrencyRowText(row)
    if not (row and row.text) then return end
    local info = row.currencyInfo
    local quantity = info and tonumber(info.quantity) or nil
    local showLifetimeProgress = row.panel and row.panel.showCurrencyLifetimeProgress == true
    row.text:SetText(PVEEnhancement.StatsPanel.GetCurrencyDisplayText(info, showLifetimeProgress))
    SetTextColor(row.text, PVEEnhancement.StatsPanel.GetCurrencyAmountColor(row.currencyConfig, quantity))
    PVEEnhancement.StatsPanel.LayoutCurrencyRow(row)
end

function PVEEnhancement.StatsPanel.ToggleCurrencyDisplay(owner, button)
    if button and button ~= "LeftButton" then return end
    local row = owner and (owner.currencyRow or owner)
    local panel = owner and owner.panel or row and row.panel
    if not (panel and panel.summaryCurrencyRows) then return end
    panel.showCurrencyLifetimeProgress = panel.showCurrencyLifetimeProgress ~= true
    for _, currencyRow in ipairs(panel.summaryCurrencyRows) do
        PVEEnhancement.StatsPanel.UpdateCurrencyRowText(currencyRow)
    end
end

function PVEEnhancement.StatsPanel.UpdateCurrencyRows(panel)
    if not (panel and panel.summaryCurrencyRows) then return end
    for index, config in ipairs(PVEEnhancement.StatsPanel.currencies) do
        local row = panel.summaryCurrencyRows[index]
        if row then
            row.panel = panel
            local info
            if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                info = SafeCall(C_CurrencyInfo.GetCurrencyInfo, config.id)
            end

            row.currencyID = config.id
            row.currencyConfig = config
            row.currencyInfo = info
            row.fallbackName = T(config.fallbackNameKey, config.fallbackName)
            if row.hitbox then
                row.hitbox.currencyID = config.id
                row.hitbox.fallbackName = T(config.fallbackNameKey, config.fallbackName)
            end

            if info and info.iconFileID and row.icon then
                row.icon:SetTexture(info.iconFileID)
                if row.icon.SetTexCoord then
                    row.icon:SetTexCoord(unpack(PVEEnhancement.StatsPanel.currencyIconTexCoord))
                end
                if row.icon.SetVertexColor then row.icon:SetVertexColor(1, 1, 1, 1) end
                if row.iconSlot then row.iconSlot:Show() end
                row.icon:Show()
            elseif row.iconSlot then
                row.iconSlot:Hide()
            elseif row.icon then
                row.icon:Hide()
            end
            PVEEnhancement.StatsPanel.UpdateCurrencyRowText(row)
        end
    end
end

local function RenderStatsPanelFooter(panel, seasonCount, weeklyCount, weeklyVaultRuns)
    local seasonLabel = T("pve.stats.season", "赛季：")
    local weekLabel = T("pve.stats.this_week", "本周：")
    weeklyCount = tonumber(weeklyCount) or 0
    seasonCount = tonumber(seasonCount) or 0
    panel.weeklyCount = weeklyCount
    panel.weeklyVaultRuns = weeklyVaultRuns or {}

    PVEEnhancement.StatsPanel.RenderPlayerSummary(panel)
    PVEEnhancement.StatsPanel.SetSummaryStat(
        panel.summarySeasonFrame,
        panel.summarySeasonLabel,
        panel.summarySeasonText,
        PVEEnhancement.StatsPanel.FormatSummaryLabel(PVEEnhancement.StatsPanel.summaryAtlases.season, seasonLabel),
        ColorText(seasonCount, PVEEnhancement.StatsPanel.summaryText)
    )
    PVEEnhancement.StatsPanel.SetSummaryStat(
        panel.summaryWeekFrame,
        panel.summaryWeekLabel,
        panel.summaryWeekText,
        PVEEnhancement.StatsPanel.FormatSummaryLabel(PVEEnhancement.StatsPanel.summaryAtlases.week, weekLabel),
        ColorText(weeklyCount, GetWeeklyCountColor(weeklyCount))
    )
    PVEEnhancement.StatsPanel.UpdateCurrencyRows(panel)
    PVEEnhancement.StatsPanel.RenderVaultCards(panel, weeklyCount, weeklyVaultRuns, statsPanelDevData ~= nil and YUI.IsDev == true)
    PVEEnhancement.StatsPanel.RenderTopRuns(panel, weeklyVaultRuns)
    if panel.footerVaultHitbox then
        panel.footerVaultHitbox:EnableMouse(false)
    end
end

local function GetStatsDividerColor()
    local r, g, b = StatsPanelAppearance.GetAccentColor()
    if r then return r, g, b, 0.68 end
    return 1, 0.82, 0.1, 0.68
end

local function SetStatsDividerGradient(texture, r, g, b, leftAlpha, rightAlpha)
    if not texture then return end
    texture:SetColorTexture(r, g, b, math.max(leftAlpha or 0, rightAlpha or 0))
    if texture.SetGradientAlpha then
        local ok = pcall(texture.SetGradientAlpha, texture, "HORIZONTAL", r, g, b, leftAlpha or 0, r, g, b, rightAlpha or 0)
        if ok then return end
    end
    if texture.SetGradient and CreateColor then
        pcall(texture.SetGradient, texture, "HORIZONTAL", CreateColor(r, g, b, leftAlpha or 0), CreateColor(r, g, b, rightAlpha or 0))
    end
end

function PVEEnhancement.StatsPanel.RefreshProgressDivider(panel)
    if not (panel and panel.progressLineLeft and panel.progressLineRight) then return end
    local r, g, b, a = GetStatsDividerColor()
    a = a or 0.55
    SetStatsDividerGradient(panel.progressLineLeft, r, g, b, 0, a)
    SetStatsDividerGradient(panel.progressLineRight, r, g, b, a, 0)
end

function PVEEnhancement.StatsPanel.RefreshFooterDivider(panel)
    if not (panel and panel.footerLineLeft and panel.footerLineRight) then return end
    local r, g, b, a = GetStatsDividerColor()
    a = a or 0.55
    SetStatsDividerGradient(panel.footerLineLeft, r, g, b, 0, a)
    SetStatsDividerGradient(panel.footerLineRight, r, g, b, a, 0)
end

function PVEEnhancement.StatsPanel.CreateCurrencyRow(parent, panel)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(PVEEnhancement.StatsPanel.summaryCurrencyWidth, PVEEnhancement.StatsPanel.summaryStatRowHeight)
    row.panel = panel

    local iconAnchor
    local GUI2 = YUI.GUI2
    if GUI2 and GUI2.CreateIconSlot then
        local ok, iconSlot = pcall(GUI2.CreateIconSlot, GUI2, row, {
            size = PVEEnhancement.StatsPanel.currencyIconSize,
            variant = "surface",
            shape = "square",
            padding = PVEEnhancement.StatsPanel.currencyIconPadding,
        })
        if ok and iconSlot then
            row.iconSlot = iconSlot
            row.icon = iconSlot.icon
            iconAnchor = iconSlot
            iconSlot:SetPoint("LEFT", row, "LEFT", 0, PVEEnhancement.StatsPanel.summaryIconYOffset or 0)
            if iconSlot.EnableMouse then iconSlot:EnableMouse(false) end
        end
    end
    if not row.icon then
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(PVEEnhancement.StatsPanel.currencyIconSize, PVEEnhancement.StatsPanel.currencyIconSize)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, PVEEnhancement.StatsPanel.summaryIconYOffset or 0)
        iconAnchor = row.icon
    end
    row.iconAnchor = iconAnchor or row.icon
    if row.icon.SetTexCoord then
        row.icon:SetTexCoord(unpack(PVEEnhancement.StatsPanel.currencyIconTexCoord))
    end

    row.text = CreateStatsFontString(row, PVEEnhancement.StatsPanel.currencyFontSize, "", "LEFT")
    row.text:SetPoint("LEFT", iconAnchor or row.icon, "RIGHT", 4, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.text:SetHeight(PVEEnhancement.StatsPanel.summaryStatRowHeight)
    SetTextColor(row.text, PVEEnhancement.StatsPanel.summaryText)

    row.hitbox = CreateFrame("Frame", nil, row)
    row.hitbox.panel = panel
    row.hitbox.currencyRow = row
    row.hitbox:SetAllPoints(row)
    row.hitbox:EnableMouse(true)
    row.hitbox:SetScript("OnEnter", PVEEnhancement.StatsPanel.ShowCurrencyTooltip)
    row.hitbox:SetScript("OnLeave", PVEEnhancement.StatsPanel.HideCurrencyTooltip)
    row.hitbox:SetScript("OnMouseUp", PVEEnhancement.StatsPanel.ToggleCurrencyDisplay)
    return row
end

local function CreateStatsPanel()
    local pveFrame = _G.PVEFrame
    if statsPanel then
        PVEEnhancement.StatsPanel.RegisterSharedAppearanceConsumer()
        return statsPanel
    end
    if not (pveFrame and CreateFrame) then return nil end

    local GUI2 = YUI.GUI2
    if GUI2 and GUI2.CreatePanel then
        local ok, frame = pcall(GUI2.CreatePanel, GUI2, pveFrame, {
            name = "YUIPVEStatsPanel",
            width = PVE_STATS_PANEL_WIDTH,
            surface = "color.surface.window",
            border = "color.border.strong",
            shadow = true,
        })
        if ok and frame then
            statsPanel = frame
        end
    end

    if not statsPanel then
        statsPanel = CreateFrame("Frame", "YUIPVEStatsPanel", pveFrame, "BackdropTemplate")
        ApplyNativeStatsPanelBackdrop(statsPanel)
    end
    PVEEnhancement.StatsPanel.RegisterSharedAppearanceConsumer()

    statsPanel:SetWidth(PVE_STATS_PANEL_WIDTH)
    statsPanel:EnableMouse(false)
    if pveFrame.GetFrameStrata and statsPanel.SetFrameStrata then
        statsPanel:SetFrameStrata(pveFrame:GetFrameStrata())
    end
    if pveFrame.GetFrameLevel and statsPanel.SetFrameLevel then
        statsPanel:SetFrameLevel((pveFrame:GetFrameLevel() or 0) + 8)
    end

    statsPanel.title = CreateStatsFontString(statsPanel, 15, "", "CENTER")
    statsPanel.title:SetPoint("TOPLEFT", PVE_STATS_PANEL_PADDING, -6)
    statsPanel.title:SetPoint("TOPRIGHT", -PVE_STATS_PANEL_PADDING, -6)
    statsPanel.title:SetHeight(20)
    statsPanel.title:SetText(T("pve.stats.title", "本周大秘境统计"))
    SetTextColor(statsPanel.title, DUNGEON_NAME_COLOR)

    statsPanel.closeButton = PVEEnhancement.StatsPanel.CreateCloseButton(statsPanel)

    statsPanel.content = CreateFrame("Frame", nil, statsPanel)
    statsPanel.content:SetPoint("TOPLEFT", PVE_STATS_PANEL_PADDING, -PVE_STATS_HEADER_HEIGHT)
    statsPanel.content:SetPoint("RIGHT", statsPanel, "RIGHT", -PVE_STATS_PANEL_PADDING, 0)
    statsPanel.content:SetPoint("BOTTOM", statsPanel, "BOTTOM", 0, PVE_STATS_PANEL_PADDING)

    statsPanel.identityFrame = CreateFrame("Frame", nil, statsPanel.content)
    statsPanel.identityFrame:SetPoint("TOPLEFT", statsPanel.content, "TOPLEFT", 0, -PVEEnhancement.StatsPanel.identityTopOffset)
    statsPanel.identityFrame:SetPoint("TOPRIGHT", statsPanel.content, "TOPRIGHT", 0, -PVEEnhancement.StatsPanel.identityTopOffset)
    statsPanel.identityFrame:SetHeight(PVEEnhancement.StatsPanel.identityBgHeight)

    if GUI2 and GUI2.CreateFrame and GUI2.CreateTexture and GUI2.CreateBorder then
        statsPanel.identityBg = GUI2:CreateFrame(statsPanel.identityFrame, { template = "BackdropTemplate" })
        statsPanel.identityBg:SetPoint("TOPLEFT", statsPanel.identityFrame, "TOPLEFT", 0, PVEEnhancement.StatsPanel.identityBgTopOffset)
        statsPanel.identityBg:SetPoint("TOPRIGHT", statsPanel.identityFrame, "TOPRIGHT", 0, PVEEnhancement.StatsPanel.identityBgTopOffset)
        statsPanel.identityBg:SetHeight(PVEEnhancement.StatsPanel.identityBgHeight)
        if statsPanel.identityBg.EnableMouse then statsPanel.identityBg:EnableMouse(false) end

        statsPanel.identityBgFill = GUI2:CreateTexture(statsPanel.identityBg, { layer = "BACKGROUND" })
        statsPanel.identityBgFill:SetAllPoints()
        PVEEnhancement.StatsPanel.SetTextureColor(statsPanel.identityBgFill, PVEEnhancement.StatsPanel.identityBgFill)

        local border = PVEEnhancement.StatsPanel.identityBgBorder
        GUI2:CreateBorder(statsPanel.identityBg, border.r, border.g, border.b, border.a)
    end

    statsPanel.playerInfoFrame = CreateFrame("Frame", nil, statsPanel.identityFrame)
    statsPanel.playerInfoFrame:SetPoint("TOPLEFT", statsPanel.identityFrame, "TOPLEFT", PVEEnhancement.StatsPanel.summaryInfoInset, PVEEnhancement.StatsPanel.identityBgTopOffset - PVEEnhancement.StatsPanel.summaryInfoTopInset)
    statsPanel.playerInfoFrame:SetPoint("TOPRIGHT", statsPanel.identityFrame, "TOPRIGHT", -PVEEnhancement.StatsPanel.summaryInfoInset, PVEEnhancement.StatsPanel.identityBgTopOffset - PVEEnhancement.StatsPanel.summaryInfoTopInset)
    statsPanel.playerInfoFrame:SetHeight(PVEEnhancement.StatsPanel.identityBgHeight - PVEEnhancement.StatsPanel.summaryInfoTopInset - PVEEnhancement.StatsPanel.summaryInfoBottomInset)

    statsPanel.playerHeaderFrame = CreateFrame("Frame", nil, statsPanel.playerInfoFrame)
    statsPanel.playerHeaderFrame:SetPoint("TOPLEFT", statsPanel.playerInfoFrame, "TOPLEFT", 0, 0)
    statsPanel.playerHeaderFrame:SetPoint("TOPRIGHT", statsPanel.playerInfoFrame, "TOPRIGHT", 0, 0)
    statsPanel.playerHeaderFrame:SetHeight(30)

    if GUI2 and GUI2.CreateIconSlot then
        local ok, raceIcon = pcall(GUI2.CreateIconSlot, GUI2, statsPanel.playerHeaderFrame, {
            size = PVEEnhancement.StatsPanel.playerIconSize,
            variant = "bare",
            shape = "square",
            padding = 0,
        })
        if ok and raceIcon then
            statsPanel.playerRaceIcon = raceIcon
        end
    end
    if not statsPanel.playerRaceIcon then
        statsPanel.playerRaceIcon = statsPanel.playerHeaderFrame:CreateTexture(nil, "ARTWORK")
        statsPanel.playerRaceIcon:SetSize(PVEEnhancement.StatsPanel.playerIconSize, PVEEnhancement.StatsPanel.playerIconSize)
    end
    statsPanel.playerRaceIcon:Hide()

    statsPanel.playerSpecIcon = statsPanel.playerHeaderFrame:CreateTexture(nil, "ARTWORK")
    statsPanel.playerSpecIcon:SetSize(PVEEnhancement.StatsPanel.playerSpecIconSize, PVEEnhancement.StatsPanel.playerSpecIconSize)
    statsPanel.playerSpecIcon:Hide()

    statsPanel.playerNameText = CreateStatsFontString(statsPanel.playerInfoFrame, PVEEnhancement.StatsPanel.playerNameFontSize, "", "LEFT")
    statsPanel.playerNameText:SetHeight(30)

    statsPanel.playerIlvlText = CreateStatsFontString(statsPanel.playerInfoFrame, PVEEnhancement.StatsPanel.playerIlvlFontSize, "", "LEFT")
    statsPanel.playerIlvlText:SetHeight(30)

    statsPanel.summarySeasonFrame = CreateFrame("Frame", nil, statsPanel.playerInfoFrame)
    statsPanel.summarySeasonFrame:SetPoint("TOPRIGHT", statsPanel.playerInfoFrame, "TOPRIGHT", 0, -PVEEnhancement.StatsPanel.summaryRowTopOffset)
    statsPanel.summarySeasonFrame:SetSize(PVEEnhancement.StatsPanel.summaryLeftWidth, PVEEnhancement.StatsPanel.summaryStatRowHeight)
    statsPanel.summarySeasonFrame.summaryAlign = "CENTER"
    statsPanel.summarySeasonFrame.summaryLabelWidth = PVEEnhancement.StatsPanel.summaryStatLabelWidth
    statsPanel.summarySeasonFrame.summaryValueWidth = PVEEnhancement.StatsPanel.summaryStatValueWidth
    statsPanel.summarySeasonFrame.summaryValueInset = 2
    statsPanel.summarySeasonLabel = CreateStatsFontString(statsPanel.summarySeasonFrame, PVEEnhancement.StatsPanel.summaryLabelFontSize, "", "LEFT")
    statsPanel.summarySeasonText = CreateStatsFontString(statsPanel.summarySeasonFrame, PVEEnhancement.StatsPanel.summaryValueFontSize, "", "RIGHT")

    statsPanel.summaryWeekFrame = CreateFrame("Frame", nil, statsPanel.playerInfoFrame)
    statsPanel.summaryWeekFrame:SetPoint("TOPLEFT", statsPanel.playerInfoFrame, "TOPLEFT", 0, -PVEEnhancement.StatsPanel.summaryRowTopOffset)
    statsPanel.summaryWeekFrame:SetSize(PVEEnhancement.StatsPanel.summaryLeftWidth, PVEEnhancement.StatsPanel.summaryStatRowHeight)
    statsPanel.summaryWeekFrame.summaryAlign = "CENTER"
    statsPanel.summaryWeekFrame.summaryLabelWidth = PVEEnhancement.StatsPanel.summaryStatLabelWidth
    statsPanel.summaryWeekFrame.summaryValueWidth = PVEEnhancement.StatsPanel.summaryStatValueWidth
    statsPanel.summaryWeekFrame.summaryValueInset = 2
    statsPanel.summaryWeekLabel = CreateStatsFontString(statsPanel.summaryWeekFrame, PVEEnhancement.StatsPanel.summaryLabelFontSize, "", "LEFT")
    statsPanel.summaryWeekText = CreateStatsFontString(statsPanel.summaryWeekFrame, PVEEnhancement.StatsPanel.summaryValueFontSize, "", "RIGHT")

    statsPanel.summaryCurrencyRows = {}
    for index = 1, #PVEEnhancement.StatsPanel.currencies do
        local row = PVEEnhancement.StatsPanel.CreateCurrencyRow(statsPanel.playerInfoFrame, statsPanel)
        local xOffset = PVEEnhancement.StatsPanel.currencyRowInset + ((index - 1) * (PVEEnhancement.StatsPanel.summaryCurrencyWidth + PVEEnhancement.StatsPanel.summaryColumnGap))
        row:SetPoint("TOPLEFT", statsPanel.playerInfoFrame, "TOPLEFT", xOffset, -PVEEnhancement.StatsPanel.currencyRowTopOffset)
        statsPanel.summaryCurrencyRows[index] = row
    end

    statsPanel.identityDividers = {}
    local identityPixel = PVEEnhancement.StatsPanel.GetPixelSize(statsPanel.playerInfoFrame, 1)
    for index, yOffset in ipairs(PVEEnhancement.StatsPanel.identityDividerOffsets) do
        local divider = PVEEnhancement.CreateStatsRowLine(statsPanel.playerInfoFrame)
        divider:SetPoint("TOPLEFT", statsPanel.playerInfoFrame, "TOPLEFT", 0, -yOffset)
        divider:SetPoint("TOPRIGHT", statsPanel.playerInfoFrame, "TOPRIGHT", 0, -yOffset)
        divider:SetHeight(identityPixel)
        PVEEnhancement.StatsPanel.SetTextureColor(divider, PVEEnhancement.StatsPanel.identityDivider)
        statsPanel.identityDividers[index] = divider
    end

    statsPanel.identityVerticalDividers = {}
    local summaryDivider = PVEEnhancement.CreateStatsRowLine(statsPanel.playerInfoFrame)
    summaryDivider:SetPoint("TOP", statsPanel.playerInfoFrame, "TOP", 0, -PVEEnhancement.StatsPanel.summaryRowTopOffset)
    summaryDivider:SetPoint("BOTTOM", statsPanel.playerInfoFrame, "TOP", 0, -(PVEEnhancement.StatsPanel.summaryRowTopOffset + PVEEnhancement.StatsPanel.summaryStatRowHeight))
    summaryDivider:SetWidth(identityPixel)
    PVEEnhancement.StatsPanel.SetTextureColor(summaryDivider, PVEEnhancement.StatsPanel.identityDivider)
    statsPanel.identityVerticalDividers[1] = summaryDivider

    for index = 1, #PVEEnhancement.StatsPanel.currencies - 1 do
        local xOffset = PVEEnhancement.StatsPanel.currencyRowInset
            + (index * PVEEnhancement.StatsPanel.summaryCurrencyWidth)
            + ((index - 0.5) * PVEEnhancement.StatsPanel.summaryColumnGap)
        local divider = PVEEnhancement.CreateStatsRowLine(statsPanel.playerInfoFrame)
        divider:SetPoint("TOP", statsPanel.playerInfoFrame, "TOPLEFT", xOffset, -PVEEnhancement.StatsPanel.currencyRowTopOffset)
        divider:SetPoint("BOTTOM", statsPanel.playerInfoFrame, "TOPLEFT", xOffset, -(PVEEnhancement.StatsPanel.currencyRowTopOffset + PVEEnhancement.StatsPanel.summaryStatRowHeight))
        divider:SetWidth(identityPixel)
        PVEEnhancement.StatsPanel.SetTextureColor(divider, PVEEnhancement.StatsPanel.identityDivider)
        statsPanel.identityVerticalDividers[#statsPanel.identityVerticalDividers + 1] = divider
    end

    statsPanel.vaultTitle = CreateStatsFontString(statsPanel.content, PVEEnhancement.StatsPanel.sectionTitleFontSize, "OUTLINE", "LEFT")
    statsPanel.vaultTitle:SetPoint("TOPLEFT", statsPanel.content, "TOPLEFT", 0, -PVEEnhancement.StatsPanel.vaultTitleTopOffset)
    statsPanel.vaultTitle:SetPoint("TOPRIGHT", statsPanel.content, "TOPRIGHT", 0, -PVEEnhancement.StatsPanel.vaultTitleTopOffset)
    statsPanel.vaultTitle:SetHeight(PVEEnhancement.StatsPanel.vaultTitleHeight)
    statsPanel.vaultTitle:SetText(T("pve.stats.vault.header", "宏伟宝库"))
    SetTextColor(statsPanel.vaultTitle, PVEEnhancement.StatsPanel.sectionTitle)

    statsPanel.vaultCardsHost = CreateFrame("Frame", nil, statsPanel.content)
    statsPanel.vaultCardsHost:SetPoint("TOPLEFT", statsPanel.content, "TOPLEFT", 0, -PVEEnhancement.StatsPanel.vaultCardTopOffset)
    statsPanel.vaultCardsHost:SetPoint("TOPRIGHT", statsPanel.content, "TOPRIGHT", 0, -PVEEnhancement.StatsPanel.vaultCardTopOffset)
    statsPanel.vaultCardsHost:SetHeight(PVEEnhancement.StatsPanel.vaultCardHeight)

    statsPanel.vaultCards = {}
    local cardsWidth = PVE_STATS_PANEL_WIDTH - (PVE_STATS_PANEL_PADDING * 2)
    local cardWidth = math.floor((cardsWidth - (PVEEnhancement.StatsPanel.vaultCardGap * 2)) / 3)
    local cardsLeftInset = math.floor((cardsWidth - ((cardWidth * 3) + (PVEEnhancement.StatsPanel.vaultCardGap * 2))) / 2)
    for index = 1, 3 do
        local card = PVEEnhancement.StatsPanel.CreateVaultCard(statsPanel.vaultCardsHost, statsPanel)
        card:SetSize(cardWidth, PVEEnhancement.StatsPanel.vaultCardHeight)
        card:SetPoint("TOPLEFT", statsPanel.vaultCardsHost, "TOPLEFT", cardsLeftInset + ((index - 1) * (cardWidth + PVEEnhancement.StatsPanel.vaultCardGap)), 0)
        statsPanel.vaultCards[index] = card
    end

    statsPanel.topRunsTitle = CreateStatsFontString(statsPanel.content, PVEEnhancement.StatsPanel.topRunsTitleFontSize, "OUTLINE", "LEFT")
    statsPanel.topRunsTitle:SetPoint("TOPLEFT", statsPanel.content, "TOPLEFT", 0, -PVEEnhancement.StatsPanel.topRunsTitleTopOffset)
    statsPanel.topRunsTitle:SetPoint("TOPRIGHT", statsPanel.content, "TOPRIGHT", 0, -PVEEnhancement.StatsPanel.topRunsTitleTopOffset)
    statsPanel.topRunsTitle:SetHeight(PVEEnhancement.StatsPanel.topRunsTitleHeight)
    statsPanel.topRunsTitle:SetText(T("pve.stats.top_runs", "本周最佳"))
    SetTextColor(statsPanel.topRunsTitle, PVEEnhancement.StatsPanel.sectionTitle)

    statsPanel.topRunsFrame = CreateFrame("Frame", nil, statsPanel.content)
    statsPanel.topRunsFrame:SetPoint("TOPLEFT", statsPanel.content, "TOPLEFT", 0, -PVEEnhancement.StatsPanel.topRunsValuesTopOffset)
    statsPanel.topRunsFrame:SetPoint("TOPRIGHT", statsPanel.content, "TOPRIGHT", 0, -PVEEnhancement.StatsPanel.topRunsValuesTopOffset)
    statsPanel.topRunsFrame:SetHeight(PVEEnhancement.StatsPanel.topRunsHeight)
    statsPanel.topRunsFrame.background = statsPanel.topRunsFrame:CreateTexture(nil, "BACKGROUND")
    statsPanel.topRunsFrame.background:SetAllPoints()
    PVEEnhancement.StatsPanel.SetTextureColor(statsPanel.topRunsFrame.background, PVEEnhancement.StatsPanel.topRunsBg)
    statsPanel.topRunsFrame.borderTop = PVEEnhancement.CreateStatsRowLine(statsPanel.topRunsFrame)
    statsPanel.topRunsFrame.borderTop:SetPoint("TOPLEFT")
    statsPanel.topRunsFrame.borderTop:SetPoint("TOPRIGHT")
    statsPanel.topRunsFrame.borderBottom = PVEEnhancement.CreateStatsRowLine(statsPanel.topRunsFrame)
    statsPanel.topRunsFrame.borderBottom:SetPoint("BOTTOMLEFT")
    statsPanel.topRunsFrame.borderBottom:SetPoint("BOTTOMRIGHT")
    statsPanel.topRunsFrame.borderLeft = PVEEnhancement.CreateStatsRowLine(statsPanel.topRunsFrame)
    statsPanel.topRunsFrame.borderLeft:SetPoint("TOPLEFT")
    statsPanel.topRunsFrame.borderLeft:SetPoint("BOTTOMLEFT")
    statsPanel.topRunsFrame.borderRight = PVEEnhancement.CreateStatsRowLine(statsPanel.topRunsFrame)
    statsPanel.topRunsFrame.borderRight:SetPoint("TOPRIGHT")
    statsPanel.topRunsFrame.borderRight:SetPoint("BOTTOMRIGHT")
    statsPanel.topRunsFrame.borderLines = {
        statsPanel.topRunsFrame.borderTop,
        statsPanel.topRunsFrame.borderBottom,
        statsPanel.topRunsFrame.borderLeft,
        statsPanel.topRunsFrame.borderRight,
    }
    PVEEnhancement.StatsPanel.SetTileBorderColor(statsPanel.topRunsFrame, PVEEnhancement.StatsPanel.tileBorder)
    PVEEnhancement.StatsPanel.UpdateTilePixelBorder(statsPanel.topRunsFrame)

    statsPanel.topRunSlotsHost = CreateFrame("Frame", nil, statsPanel.topRunsFrame)
    statsPanel.topRunSlotsHost:SetAllPoints()
    statsPanel.topRunSlots = {}
    local topRunWidth = cardsWidth
    local topRunSlotWidth = math.floor(topRunWidth / PVEEnhancement.StatsPanel.topRunLimit)
    local topRunInset = math.floor((topRunWidth - (topRunSlotWidth * PVEEnhancement.StatsPanel.topRunLimit)) / 2)
    for index = 1, PVEEnhancement.StatsPanel.topRunLimit do
        local slot = CreateStatsFontString(statsPanel.topRunSlotsHost, PVEEnhancement.StatsPanel.topRunsSlotFontSize, "OUTLINE", "CENTER")
        slot:SetPoint("LEFT", statsPanel.topRunSlotsHost, "LEFT", topRunInset + ((index - 1) * topRunSlotWidth), 0)
        slot:SetSize(topRunSlotWidth, PVEEnhancement.StatsPanel.topRunsHeight)
        statsPanel.topRunSlots[index] = slot
    end

    statsPanel.dungeonTitle = CreateStatsFontString(statsPanel.content, PVEEnhancement.StatsPanel.sectionTitleFontSize, "OUTLINE", "LEFT")
    statsPanel.dungeonTitle:SetPoint("TOPLEFT", statsPanel.content, "TOPLEFT", 0, -PVEEnhancement.StatsPanel.dungeonTitleTopOffset)
    statsPanel.dungeonTitle:SetPoint("TOPRIGHT", statsPanel.content, "TOPRIGHT", 0, -PVEEnhancement.StatsPanel.dungeonTitleTopOffset)
    statsPanel.dungeonTitle:SetHeight(PVEEnhancement.StatsPanel.dungeonTitleHeight)
    statsPanel.dungeonTitle:SetText(T("pve.stats.weekly_dungeons", "本周副本"))
    SetTextColor(statsPanel.dungeonTitle, PVEEnhancement.StatsPanel.sectionTitle)

    statsPanel.tilesHost = CreateFrame("Frame", nil, statsPanel.content)
    statsPanel.tilesHost:SetPoint("TOPLEFT", statsPanel.content, "TOPLEFT", 0, -PVEEnhancement.StatsPanel.summaryHeight)
    statsPanel.tilesHost:SetPoint("BOTTOMRIGHT", statsPanel.content, "BOTTOMRIGHT", 0, 0)

    statsPanel.footer = CreateFrame("Frame", nil, statsPanel)
    statsPanel.footer:SetPoint("BOTTOMLEFT", PVE_STATS_PANEL_PADDING, 11)
    statsPanel.footer:SetPoint("BOTTOMRIGHT", -PVE_STATS_PANEL_PADDING, 11)
    statsPanel.footer:SetHeight(18)

    statsPanel.footerWeekText = CreateStatsFontString(statsPanel.footer, 13, "OUTLINE", "LEFT")
    statsPanel.footerWeekText:SetPoint("LEFT", statsPanel.footer, "LEFT", 0, 0)
    statsPanel.footerWeekText:SetSize(92, 18)

    statsPanel.footerVaultText = CreateStatsFontString(statsPanel.footer, 13, "OUTLINE", "CENTER")
    statsPanel.footerVaultText:SetPoint("CENTER", statsPanel.footer, "CENTER", 0, 0)
    statsPanel.footerVaultText:SetSize(88, 18)

    statsPanel.footerSeasonText = CreateStatsFontString(statsPanel.footer, 13, "OUTLINE", "RIGHT")
    statsPanel.footerSeasonText:SetPoint("RIGHT", statsPanel.footer, "RIGHT", 0, 0)
    statsPanel.footerSeasonText:SetSize(92, 18)

    statsPanel.footerVaultHitbox = CreateFrame("Frame", nil, statsPanel.footer)
    statsPanel.footerVaultHitbox.panel = statsPanel
    statsPanel.footerVaultHitbox:SetPoint("TOP", statsPanel.footerVaultText, "TOP", 0, 0)
    statsPanel.footerVaultHitbox:SetPoint("BOTTOM", statsPanel.footerVaultText, "BOTTOM", 0, 0)
    statsPanel.footerVaultHitbox:SetWidth(88)
    statsPanel.footerVaultHitbox:EnableMouse(false)
    statsPanel.footerVaultHitbox:SetScript("OnEnter", PVEEnhancement.StatsPanel.ShowVaultTooltip)
    statsPanel.footerVaultHitbox:SetScript("OnLeave", PVEEnhancement.StatsPanel.HideVaultTooltip)

    statsPanel.footerDivider = CreateFrame("Frame", nil, statsPanel)
    statsPanel.footerDivider:SetHeight(1)
    statsPanel.footerDivider:SetPoint("BOTTOMLEFT", statsPanel.footer, "TOPLEFT", 0, 6)
    statsPanel.footerDivider:SetPoint("BOTTOMRIGHT", statsPanel.footer, "TOPRIGHT", 0, 6)

    statsPanel.footerLineLeft = statsPanel.footerDivider:CreateTexture(nil, "BORDER")
    statsPanel.footerLineLeft:SetPoint("LEFT", statsPanel.footerDivider, "LEFT", 0, 0)
    statsPanel.footerLineLeft:SetPoint("RIGHT", statsPanel.footerDivider, "CENTER", 0, 0)
    statsPanel.footerLineLeft:SetHeight(1)

    statsPanel.footerLineRight = statsPanel.footerDivider:CreateTexture(nil, "BORDER")
    statsPanel.footerLineRight:SetPoint("LEFT", statsPanel.footerDivider, "CENTER", 0, 0)
    statsPanel.footerLineRight:SetPoint("RIGHT", statsPanel.footerDivider, "RIGHT", 0, 0)
    statsPanel.footerLineRight:SetHeight(1)
    PVEEnhancement.StatsPanel.RefreshFooterDivider(statsPanel)
    statsPanel.footer:Hide()
    statsPanel.footerDivider:Hide()

    PVEEnhancement.StatsPanel.ApplySkin(statsPanel)
    statsPanel:Hide()
    return statsPanel
end

local function ShouldShowStatsPanel(db)
    db = GetDB(db)
    if not IsRuntimeEnabled(db) or db.pveStatsPanelEnabled ~= true then return false end
    return IsFrameVisible(_G.PVEFrame) and IsFrameVisible(_G.ChallengesFrame)
end

RefreshStatsPanel = function(db)
    local eligible = ShouldShowStatsPanel(db)
    if eligible and not PVEEnhancement._statsPanelWasEligible then
        PVEEnhancement._statsPanelManuallyClosed = false
    end
    PVEEnhancement._statsPanelWasEligible = eligible == true

    if not eligible then
        if statsPanel then
            PVEEnhancement.StatsPanel.HideActiveTooltip(statsPanel)
            statsPanel:Hide()
        end
        return
    end

    local panel = CreateStatsPanel()
    if not panel then return end

    if PVEEnhancement._statsPanelManuallyClosed == true then
        PVEEnhancement.StatsPanel.HideActiveTooltip(panel)
        panel:Hide()
        return
    end

    RefreshStatsPanelAnchor(panel)
    local rows, seasonCount, weeklyCount, weeklyVaultRuns = BuildStatsPanelData()
    RenderStatsPanelRows(panel, rows)
    RenderStatsPanelFooter(panel, seasonCount, weeklyCount, weeklyVaultRuns)
    PVEEnhancement.StatsPanel.RefreshFooterDivider(panel)
    PVEEnhancement.StatsPanel.ApplySkin(panel)
    panel:Show()
end

QueueStatsPanelRefresh = function()
    statsPanelRefreshToken = statsPanelRefreshToken + 1
    local token = statsPanelRefreshToken

    local function run()
        if token ~= statsPanelRefreshToken then return end
        RefreshStatsPanel()
    end

    if C_Timer and C_Timer.After then
        for _, delay in ipairs(PVE_STATS_REFRESH_DELAYS) do
            C_Timer.After(delay, run)
        end
    else
        run()
    end
end

function PVEEnhancement.PartyKeystonePanel.OnEvent(event, addonName)
    if event == "ADDON_LOADED" and addonName ~= CHALLENGES_ADDON and addonName ~= "ElvUI_WindTools" and addonName ~= "WindTools" and addonName ~= "NDui" then
        return
    end
    if event == "GROUP_ROSTER_UPDATE" then
        PVEEnhancement.PartyKeystonePanel.refreshRosterTransaction = true
    end
    PVEEnhancement.PartyKeystonePanel.QueueRefresh()
end

function PVEEnhancement.PartyKeystonePanel.RegisterEvents()
    local state = PVEEnhancement.PartyKeystonePanel
    if state.eventsRegistered or not (YUI.Event and YUI.Event.On) then return end
    if YUI.Event.OffOwner then
        YUI.Event:OffOwner(state.eventOwner)
    end

    local events = {
        "ADDON_LOADED",
        "PLAYER_ENTERING_WORLD",
        "GROUP_ROSTER_UPDATE",
        "YUI_KEYSTONE_PARTY_UPDATED",
        "YUI_APPEARANCE_SKIN_OPTION_CHANGED",
    }
    for _, event in ipairs(events) do
        YUI.Event:On(event, PVEEnhancement.PartyKeystonePanel.OnEvent, state.eventOwner, {
            moduleId = "component:MythicPlusTools",
            traceName = "MythicPlusTools:PartyKeystonePanel:" .. event,
            throttle = event == "GROUP_ROSTER_UPDATE" and 0.1 or nil,
        })
    end
    state.eventsRegistered = true
end

function PVEEnhancement.PartyKeystonePanel.UnregisterEvents()
    local state = PVEEnhancement.PartyKeystonePanel
    if not state.eventsRegistered then return end
    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(state.eventOwner)
    end
    if state.refreshTimer and state.refreshTimer.Cancel then
        state.refreshTimer:Cancel()
    end
    state.refreshTimer = nil
    state.refreshScheduled = false
    state.refreshRosterTransaction = false
    state.eventsRegistered = false
end

local function OnStatsPanelEvent(event, addonName)
    if event == "ADDON_LOADED" then
        if addonName ~= CHALLENGES_ADDON and addonName ~= "EllesmereUI" and addonName ~= "EllesmereUIBlizzardSkin" and addonName ~= "ElvUI" and addonName ~= "ElvUI_WindTools" and addonName ~= "WindTools" and addonName ~= "NDui" then
            return
        end
        if addonName == CHALLENGES_ADDON then
            ClearDungeonInfoCaches()
            PVEEnhancement._statsPanelDataCache = nil
            PVEEnhancement._statsPanelDataDirty = true
        end
    elseif event == "YUI_APPEARANCE_SKIN_OPTION_CHANGED" then
        if statsPanel then
            PVEEnhancement.StatsPanel.ApplySkin(statsPanel)
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if statsPanel and statsPanel.IsShown and statsPanel:IsShown() then
            QueueStatsPanelRefresh()
        end
        return
    elseif event == "PLAYER_ENTERING_WORLD" or event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_MAPS_UPDATE" or event == "MYTHIC_PLUS_NEW_WEEKLY_RECORD" or event == "WEEKLY_REWARDS_UPDATE" then
        if event == "PLAYER_ENTERING_WORLD" or event == "CHALLENGE_MODE_MAPS_UPDATE" then
            ClearDungeonInfoCaches()
        end
        PVEEnhancement._statsPanelDataCache = nil
        PVEEnhancement._statsPanelDataDirty = true
    end

    QueueStatsPanelRefresh()
    PVEEnhancement.RatingStats.RefreshDisplay()
    PVEEnhancement.PartyKeystonePanel.QueueRefresh()
end

local function RegisterStatsPanelEvents()
    if statsPanelEventsRegistered or not (YUI.Event and YUI.Event.On) then return end
    if YUI.Event.OffOwner then
        YUI.Event:OffOwner(StatsPanelEventOwner)
    end

    local events = {
        "ADDON_LOADED",
        "PLAYER_ENTERING_WORLD",
        "CHALLENGE_MODE_COMPLETED",
        "CHALLENGE_MODE_MAPS_UPDATE",
        "MYTHIC_PLUS_NEW_WEEKLY_RECORD",
        "WEEKLY_REWARDS_UPDATE",
        "GET_ITEM_INFO_RECEIVED",
        "CURRENCY_DISPLAY_UPDATE",
        "YUI_APPEARANCE_SKIN_OPTION_CHANGED",
    }
    for _, event in ipairs(events) do
        YUI.Event:On(event, OnStatsPanelEvent, StatsPanelEventOwner, { moduleId = "component:MythicPlusTools" })
    end
    statsPanelEventsRegistered = true
end

local function UnregisterStatsPanelEvents()
    if not statsPanelEventsRegistered then return end
    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(StatsPanelEventOwner)
    end
    statsPanelEventsRegistered = false
end

local function CreateOverlayText(parent, size, justify)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
    text:SetJustifyH(justify or "CENTER")
    if text.SetJustifyV then text:SetJustifyV("MIDDLE") end
    if text.SetWordWrap then text:SetWordWrap(false) end
    if text.SetNonSpaceWrap then text:SetNonSpaceWrap(false) end
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -1)
    return text
end

local function SetOverlayFontSize(text, size)
    if not (text and text.SetFont) then return end
    local font, _, flags = text:GetFont()
    text:SetFont(font or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, flags or "OUTLINE")
end

local function ApplyOverlayFontSizes(overlay, db)
    if not overlay then return end
    db = GetDB(db)

    local nameSize = db.pveIconNameFontSize
    local levelSize = db.pveIconLevelFontSize
    local scoreSize = db.pveIconScoreFontSize

    if overlay.name then
        SetOverlayFontSize(overlay.name, nameSize)
        overlay.name:SetHeight(nameSize + 2)
    end
    if overlay.level then
        SetOverlayFontSize(overlay.level, levelSize)
        overlay.level:SetHeight(levelSize + 3)
    end
    if overlay.score then
        SetOverlayFontSize(overlay.score, scoreSize)
        overlay.score:SetHeight(scoreSize + 2)
    end
end

local function ApplyOverlayLayout(overlay, db)
    if not (overlay and overlay.host) then return end
    db = GetDB(db)

    local leftOffset = -ICON_TEXT_HORIZONTAL_PADDING
    local rightOffset = ICON_TEXT_HORIZONTAL_PADDING

    if overlay.name then
        overlay.name:ClearAllPoints()
        overlay.name:SetPoint("TOPLEFT", overlay.host, "TOPLEFT", leftOffset, -1)
        overlay.name:SetPoint("TOPRIGHT", overlay.host, "TOPRIGHT", rightOffset, -1)
    end
    if overlay.level then
        overlay.level:ClearAllPoints()
        overlay.level:SetPoint("LEFT", overlay.host, "LEFT", leftOffset, db.pveIconLevelYOffset)
        overlay.level:SetPoint("RIGHT", overlay.host, "RIGHT", rightOffset, db.pveIconLevelYOffset)
    end
    if overlay.score then
        overlay.score:ClearAllPoints()
        overlay.score:SetPoint("BOTTOMLEFT", overlay.host, "BOTTOMLEFT", leftOffset, 1)
        overlay.score:SetPoint("BOTTOMRIGHT", overlay.host, "BOTTOMRIGHT", rightOffset, 1)
    end
end

local function GetFrameLevelSafe(frame)
    return frame and frame.GetFrameLevel and frame:GetFrameLevel() or 0
end

local function MaxFrameLevel(current, frame)
    local level = GetFrameLevelSafe(frame)
    if level > current then return level end
    return current
end

local function GetIconLayerBase(frame)
    local baseLevel = GetFrameLevelSafe(frame)
    baseLevel = MaxFrameLevel(baseLevel, frame and frame.backdrop)
    baseLevel = MaxFrameLevel(baseLevel, frame and frame.Backdrop)

    local icon = frame and frame.Icon
    baseLevel = MaxFrameLevel(baseLevel, icon and icon.backdrop)
    baseLevel = MaxFrameLevel(baseLevel, icon and icon.Backdrop)
    return baseLevel
end

local function IsProtectedFrame(frame)
    if not frame or type(frame.IsProtected) ~= "function" then return false end
    local ok, protected = pcall(frame.IsProtected, frame)
    return ok and protected == true
end

local function SetFrameLevelIfUnprotected(frame, level)
    if not frame or not frame.SetFrameLevel then return end
    if IsProtectedFrame(frame) then return end
    frame:SetFrameLevel(level)
end

local function UpdateIconLayering(frame)
    if not frame then return end
    local baseLevel = GetIconLayerBase(frame)

    local host = frame.yuiPVEOverlayHost
    SetFrameLevelIfUnprotected(host, baseLevel + 30)
end

local function EnsureIconOverlay(frame)
    if frame.yuiPVEOverlay then
        UpdateIconLayering(frame)
        return frame.yuiPVEOverlay
    end
    if not frame or not frame.CreateFontString then return nil end

    local host = frame
    if CreateFrame then
        host = CreateFrame("Frame", nil, frame)
        host:SetAllPoints(frame)
        if host.EnableMouse then host:EnableMouse(false) end
        if host.SetFrameStrata and frame.GetFrameStrata then
            host:SetFrameStrata(frame:GetFrameStrata())
        end
        frame.yuiPVEOverlayHost = host
    end

    local overlay = {}
    overlay.host = host
    overlay.name = CreateOverlayText(host, ICON_NAME_FONT_SIZE, "CENTER")
    overlay.name:SetHeight(ICON_NAME_FONT_SIZE + 2)

    overlay.level = CreateOverlayText(host, ICON_LEVEL_FONT_SIZE, "CENTER")
    overlay.level:SetHeight(ICON_LEVEL_FONT_SIZE + 3)

    overlay.score = CreateOverlayText(host, ICON_SCORE_FONT_SIZE, "CENTER")
    overlay.score:SetHeight(ICON_SCORE_FONT_SIZE + 2)

    frame.yuiPVEOverlay = overlay
    ApplyOverlayFontSizes(overlay)
    ApplyOverlayLayout(overlay)
    UpdateIconLayering(frame)
    return overlay
end

local function HideIconOverlay(frame)
    local overlay = frame and frame.yuiPVEOverlay
    if not overlay then return end
    if overlay.name then overlay.name:Hide() end
    if overlay.level then overlay.level:Hide() end
    if overlay.score then overlay.score:Hide() end
end

local function EnsureNativeLevelGuard(frame)
    local levelText = frame and frame.HighestLevel
    if not (levelText and hooksecurefunc) then return end
    if levelText.yuiPVENativeLevelGuarded then return end

    levelText.yuiPVENativeLevelGuarded = true
    hooksecurefunc(levelText, "Show", function()
        if IsRuntimeEnabled() then
            levelText:Hide()
            if levelText.SetAlpha then
                levelText:SetAlpha(0)
            end
        end
    end)
end

local function SuppressNativeLevel(frame)
    local levelText = frame and frame.HighestLevel
    if not levelText then return end

    EnsureNativeLevelGuard(frame)
    levelText:Hide()
    if levelText.SetAlpha then
        levelText:SetAlpha(0)
    end
end

local function RestoreNativeLevel(frame)
    if not frame or not frame.HighestLevel then return end
    if frame.HighestLevel.SetAlpha then
        frame.HighestLevel:SetAlpha(1)
    end

    local state = frame.yuiPVEState
    local level = tonumber(state and state.level) or tonumber(frame.yuiPVELastNativeLevel) or 0
    if level > 0 then
        frame.HighestLevel:SetText(level)
        SetTextColor(frame.HighestLevel, state and state.scoreColor, HIGHLIGHT_FONT_COLOR)
        frame.HighestLevel:Show()
    else
        frame.HighestLevel:Hide()
    end
end

local function ClearSecureTeleportAction(button)
    if not button or not button.SetAttribute then return end
    button:SetAttribute("type", nil)
    button:SetAttribute("macrotext", nil)
    button:SetAttribute("spell", nil)
    button:SetAttribute("type1", nil)
    button:SetAttribute("macrotext1", nil)
    button:SetAttribute("spell1", nil)
end

local function GetTeleportSpellName(spellID)
    if not spellID then return nil end

    local name
    if SpellAPI and SpellAPI.GetName then
        name = SafeCall(SpellAPI.GetName, spellID)
        if name and name ~= "" then return name end
    end

    if C_Spell and C_Spell.GetSpellInfo then
        local info = SafeCall(C_Spell.GetSpellInfo, spellID)
        if type(info) == "table" and info.name and info.name ~= "" then
            return info.name
        end
    end

    if GetSpellInfo then
        name = SafeCall(GetSpellInfo, spellID)
        if name and name ~= "" then return name end
    end

    return nil
end

local function BuildTeleportMacroText(spellID)
    local spellName = GetTeleportSpellName(spellID)
    if not spellName then return nil end
    return "/cast " .. spellName
end

local function ApplySecureTeleportAction(button, state, db)
    if not button or not button.SetAttribute then return end
    ClearSecureTeleportAction(button)

    db = GetDB(db)
    if db.pveClickTeleportEnabled ~= true then return end
    if not (state and state.teleportSpellID) then return end
    if state.teleportRemaining and state.teleportRemaining > 0 then return end

    local macroText = BuildTeleportMacroText(state.teleportSpellID)
    if not macroText then return end

    button:SetAttribute("type1", "macro")
    button:SetAttribute("macrotext1", macroText)
end

local function EnsureSecureTeleportButton(frame)
    if not frame then return nil end
    if frame.yuiPVESecureButton then
        UpdateIconLayering(frame)
        return frame.yuiPVESecureButton
    end

    if not CreateFrame or InCombatLockdownSafe() then
        if MarkSecureRefreshPending then MarkSecureRefreshPending() else secureRefreshPending = true end
        return nil
    end

    local button = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
    button:SetAllPoints(frame)
    button:RegisterForClicks("AnyDown")
    button:SetAttribute("pressAndHoldAction", true)
    button.yuiPVEIconFrame = frame
    if button.EnableMouse then button:EnableMouse(true) end

    button:SetScript("PreClick", function(self, mouseButton)
        if mouseButton ~= "LeftButton" or InCombatLockdownSafe() then return end

        local owner = self.yuiPVEIconFrame or self:GetParent()
        local db = GetDB()
        local mapID = owner and (owner.mapID or (owner.yuiPVEState and owner.yuiPVEState.mapID))
        local state = mapID and BuildDungeonState(mapID) or nil
        if owner then owner.yuiPVEState = state end
        ApplySecureTeleportAction(self, state, db)
        if db.pveClickTeleportEnabled == true and state and state.teleportSpellID and state.teleportRemaining and state.teleportRemaining > 0 then
            local text = string.format(T("tooltip.pve_teleport_cooldown", "传送冷却中：%s"), FormatDuration(state.teleportRemaining, true))
            if YUI and type(YUI.Print) == "function" then
                YUI:Print(text)
            elseif print then
                print(text)
            end
        end
    end)

    button:SetScript("OnEnter", function(self)
        local owner = self.yuiPVEIconFrame or self:GetParent()
        local db = GetDB()
        if IsRuntimeEnabled(db) and db.pveTooltipEnabled == true then
            ShowPVEIconTooltip(owner)
        elseif owner and owner.OnEnter then
            owner:OnEnter()
        end
    end)

    button:SetScript("OnLeave", function()
        if GameTooltip then YUI.HideGameTooltip() end
    end)

    button:SetScript("PostClick", function(self)
        local owner = self.yuiPVEIconFrame or self:GetParent()
        local function RefreshAfterClick()
            if owner and RefreshIconOverlay and not InCombatLockdownSafe() then
                RefreshIconOverlay(owner)
            end
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(0.15, RefreshAfterClick)
        else
            RefreshAfterClick()
        end
    end)

    frame.yuiPVESecureButton = button
    UpdateIconLayering(frame)
    return button
end

local function RefreshSecureTeleportButton(frame, state, db)
    if not frame then return end
    db = GetDB(db)

    local runtimeEnabled = IsRuntimeEnabled(db)
    local shouldCaptureMouse = runtimeEnabled and (db.pveTooltipEnabled == true or db.pveClickTeleportEnabled == true)
    local button = frame.yuiPVESecureButton
    if not button and not shouldCaptureMouse then return end

    button = button or EnsureSecureTeleportButton(frame)
    if not button then return end
    UpdateIconLayering(frame)

    if InCombatLockdownSafe() then
        if MarkSecureRefreshPending then MarkSecureRefreshPending() else secureRefreshPending = true end
        return
    end

    ClearSecureTeleportAction(button)
    if shouldCaptureMouse then
        button:Show()
        if button.EnableMouse then button:EnableMouse(true) end
    else
        button:Hide()
        return
    end

    ApplySecureTeleportAction(button, state, db)
end

function RefreshIconOverlay(frame, mapInfo)
    if not frame then return end
    local db = GetDB()
    local runtimeEnabled = IsRuntimeEnabled(db)
    if runtimeEnabled then
        SuppressNativeLevel(frame)
    end

    local mapID = GetFrameMapID(frame, mapInfo)
    if not mapID then
        RefreshSecureTeleportButton(frame, nil, db)
        HideIconOverlay(frame)
        if runtimeEnabled then
            SuppressNativeLevel(frame)
        else
            RestoreNativeLevel(frame)
        end
        return
    end

    frame.yuiPVEMapID = mapID
    CacheFrameMapInfo(frame, mapInfo)

    local fullMapInfo
    if mapInfo and mapInfo.name then
        fullMapInfo = {
            id = mapID,
            name = mapInfo.name,
            timeLimit = tonumber(mapInfo.timeLimit) or 0,
        }
    else
        fullMapInfo = GetCachedMapInfo(frame, mapID)
    end

    local state = BuildDungeonState(mapID, fullMapInfo)
    frame.yuiPVEState = state
    frame.yuiPVELastNativeLevel = state and state.level or nil
    if not state then
        RefreshSecureTeleportButton(frame, nil, db)
        HideIconOverlay(frame)
        if runtimeEnabled then
            SuppressNativeLevel(frame)
        else
            RestoreNativeLevel(frame)
        end
        return
    end

    if not runtimeEnabled then
        RefreshSecureTeleportButton(frame, state, db)
        HideIconOverlay(frame)
        RestoreNativeLevel(frame)
        return
    end

    local overlay = EnsureIconOverlay(frame)
    if not overlay then return end
    ApplyOverlayFontSizes(overlay, db)
    ApplyOverlayLayout(overlay, db)
    if overlay.host then
        if overlay.host.SetAlpha then overlay.host:SetAlpha(1) end
        if overlay.host.Show then overlay.host:Show() end
    end

    SuppressNativeLevel(frame)

    if db.pveIconNameEnabled then
        overlay.name:SetText(state.shortName or state.name or "")
        SetTextColor(overlay.name, DUNGEON_NAME_COLOR, HIGHLIGHT_FONT_COLOR)
        if overlay.name.SetAlpha then overlay.name:SetAlpha(1) end
        overlay.name:Show()
    else
        overlay.name:Hide()
    end

    if db.pveIconLevelEnabled and state.level and state.level > 0 then
        overlay.level:SetText(tostring(state.level))
        SetTextColor(overlay.level, GetLevelColor(state.level), HIGHLIGHT_FONT_COLOR)
        if overlay.level.SetAlpha then overlay.level:SetAlpha(1) end
        overlay.level:Show()
    else
        overlay.level:Hide()
    end

    if db.pveIconScoreEnabled then
        overlay.score:SetText(tostring(state.score or 0))
        SetTextColor(overlay.score, state.scoreColor, HIGHLIGHT_FONT_COLOR)
        if overlay.score.SetAlpha then overlay.score:SetAlpha(1) end
        overlay.score:Show()
    else
        overlay.score:Hide()
    end

    RefreshSecureTeleportButton(frame, state, db)
end

local function AdjustSeasonBestLabel(challengesFrame, db)
    challengesFrame = challengesFrame or _G.ChallengesFrame
    local label = challengesFrame and challengesFrame.WeeklyInfo and challengesFrame.WeeklyInfo.Child and challengesFrame.WeeklyInfo.Child.SeasonBest
    local firstIcon = challengesFrame and challengesFrame.DungeonIcons and challengesFrame.DungeonIcons[1]
    if not label then return end

    db = GetDB(db)
    local runtimeEnabled = IsRuntimeEnabled(db)
    if label.GetFont and label.SetFont then
        if not label.yuiPVEOriginalFont then
            local font, size, flags = label:GetFont()
            label.yuiPVEOriginalFont = font or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
            label.yuiPVEOriginalFontSize = tonumber(size) or 12
            label.yuiPVEOriginalFontFlags = flags
        end

        local font = label.yuiPVEOriginalFont or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        local size = label.yuiPVEOriginalFontSize or 12
        local flags = label.yuiPVEOriginalFontFlags
        if runtimeEnabled then
            size = math.max(8, size - 4)
        end
        if label.yuiPVEAppliedSeasonBestFont ~= font
            or label.yuiPVEAppliedSeasonBestFontSize ~= size
            or label.yuiPVEAppliedSeasonBestFontFlags ~= flags then
            label:SetFont(font, size, flags)
            label.yuiPVEAppliedSeasonBestFont = font
            label.yuiPVEAppliedSeasonBestFontSize = size
            label.yuiPVEAppliedSeasonBestFontFlags = flags
        end
    end

    if not (firstIcon and label.ClearAllPoints and label.SetPoint) then return end
    local targetPoint = "TOPLEFT"
    local targetRelativePoint = "TOPLEFT"
    local targetX = 5
    local targetY = runtimeEnabled and 11 or 15
    if runtimeEnabled and db.pveIconNameEnabled == true then
        targetPoint = "BOTTOM"
        targetRelativePoint = "TOP"
        targetX = 0
        targetY = 1
    end

    local currentPoint, currentRelativeTo, currentRelativePoint, currentX, currentY
    if label.GetPoint then
        currentPoint, currentRelativeTo, currentRelativePoint, currentX, currentY = label:GetPoint(1)
    end
    if currentPoint ~= targetPoint
        or currentRelativeTo ~= firstIcon
        or currentRelativePoint ~= targetRelativePoint
        or (tonumber(currentX) or 0) ~= targetX
        or (tonumber(currentY) or 0) ~= targetY then
        label:ClearAllPoints()
        label:SetPoint(targetPoint, firstIcon, targetRelativePoint, targetX, targetY)
    end
end

function RefreshVisibleIconsNow(challengesFrame, skipSeasonBest)
    challengesFrame = challengesFrame or _G.ChallengesFrame
    local icons = challengesFrame and challengesFrame.DungeonIcons
    if type(icons) ~= "table" then
        if not skipSeasonBest then
            AdjustSeasonBestLabel(challengesFrame)
        end
        PVEEnhancement.RatingStats.RefreshDisplay(challengesFrame)
        RefreshStatsPanel()
        return
    end

    if not skipSeasonBest then
        AdjustSeasonBestLabel(challengesFrame)
    end
    PVEEnhancement.RatingStats.RefreshDisplay(challengesFrame)
    for _, frame in ipairs(icons) do
        EnsureIconShowHook(frame, challengesFrame)
        RefreshIconOverlay(frame)
    end
    RefreshStatsPanel()
end

local function IsChallengesFrameShown(challengesFrame)
    if not challengesFrame then return false end
    if challengesFrame.IsShown then
        return challengesFrame:IsShown() == true
    else
        return true
    end
end

local function GetChallengesFrameForIcon(frame)
    local parent = frame and frame.GetParent and frame:GetParent() or nil
    while parent do
        if parent.DungeonIcons then return parent end
        parent = parent.GetParent and parent:GetParent() or nil
    end
    return _G.ChallengesFrame
end

function EnsureIconShowHook(frame, challengesFrame)
    if not (frame and frame.HookScript) then return end
    if frame.yuiPVEOnShowHooked then return end

    frame.yuiPVEOnShowHooked = true
    frame:HookScript("OnShow", function(icon)
        if not IsRuntimeEnabled() then return end
        RefreshIconOverlay(icon)
        QueueSettledVisibleIconRefresh(challengesFrame or GetChallengesFrameForIcon(icon))
    end)
end

local function RunSettledVisibleIconRefresh(challengesFrame, token)
    if not challengesFrame then return end
    if challengesFrame.yuiPVESettledRefreshToken ~= token then return end
    if not IsChallengesFrameShown(challengesFrame) then return end
    RefreshVisibleIconsNow(challengesFrame)
end

function QueueSettledVisibleIconRefresh(challengesFrame)
    challengesFrame = challengesFrame or _G.ChallengesFrame
    if not (challengesFrame and C_Timer and C_Timer.After) then return end

    local token = (tonumber(challengesFrame.yuiPVESettledRefreshToken) or 0) + 1
    challengesFrame.yuiPVESettledRefreshToken = token

    for _, delay in ipairs(SETTLED_REFRESH_DELAYS) do
        C_Timer.After(delay, function()
            RunSettledVisibleIconRefresh(challengesFrame, token)
        end)
    end
end

local function EnsureChallengesFrameHooks()
    local challengesFrame = _G.ChallengesFrame
    if not challengesFrame or challengesFrame.yuiPVEFrameHooksInstalled then return end

    challengesFrame.yuiPVEFrameHooksInstalled = true
    if hooksecurefunc and type(challengesFrame.Update) == "function" then
        hooksecurefunc(challengesFrame, "Update", function(frame)
            AdjustSeasonBestLabel(frame or challengesFrame)
            QueueSettledVisibleIconRefresh(frame or challengesFrame)
            PVEEnhancement.PartyKeystonePanel.QueueRefresh()
        end)
    end

    if challengesFrame.HookScript then
        challengesFrame:HookScript("OnShow", function(frame)
            RefreshVisibleIconsNow(frame, true)
            QueueSettledVisibleIconRefresh(frame)
            PVEEnhancement.PartyKeystonePanel.QueueRefresh()
        end)
        challengesFrame:HookScript("OnHide", function()
            PVEEnhancement.PartyKeystonePanel.QueueRefresh()
        end)
    end
end

local function RefreshVisibleIcons()
    local challengesFrame = _G.ChallengesFrame
    EnsureChallengesFrameHooks()
    RefreshVisibleIconsNow(challengesFrame)
    QueueSettledVisibleIconRefresh(challengesFrame)
end

local function AddTooltipLine(formatKey, fallback, ...)
    if not GameTooltip then return end
    local text = string.format(T(formatKey, fallback), ...)
    GameTooltip:AddLine(text, 1, 1, 1)
end

local function AddDurationToTooltip(duration, limit)
    duration = tonumber(duration) or 0
    limit = tonumber(limit) or 0
    if duration <= 0 then return end

    if limit > 0 then
        local delta = duration - limit
        local overtime = delta > 0
        local sign = overtime and "+" or "-"
        local color = overtime and (RED_FONT_COLOR or DURATION_OVERTIME_COLOR) or (GREEN_FONT_COLOR or DURATION_IN_TIME_COLOR)
        local text = string.format("%s (%s%s)", FormatDuration(duration), sign, FormatDuration(math.abs(delta)))
        AddTooltipLine("tooltip.pve_duration", "耗时：%s", ColorText(text, color))
    else
        AddTooltipLine("tooltip.pve_duration", "耗时：%s", FormatDuration(duration))
    end
end

local function AddMembersToTooltip(bestRun)
    local members = bestRun and bestRun.members
    if type(members) ~= "table" or #members == 0 then return end

    local addedHeader = false
    for _, member in ipairs(members) do
        local name = NormalizeName(member and member.name)
        if name and name ~= "" then
            if not addedHeader then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(T("tooltip.pve_members", "通关队友："), 1, 0.82, 0.1)
                addedHeader = true
            end

            local icon = GetSpecIconTag(member.specID)
            local coloredName = ColorPlayerName(name, member.classID)
            if icon then
                GameTooltip:AddLine(string.format("%s %s", icon, coloredName), 1, 1, 1)
            else
                GameTooltip:AddLine(coloredName, 1, 1, 1)
            end
        end
    end
end

function ShowPVEIconTooltip(frame)
    if not (frame and GameTooltip) then return end
    local db = GetDB()
    if not IsRuntimeEnabled(db) or db.pveTooltipEnabled ~= true then return end

    local mapID = GetFrameMapID(frame)
    local state = BuildDungeonState(mapID, GetCachedMapInfo(frame, mapID))
    if not state then return end
    frame.yuiPVEState = state
    frame.yuiPVEMapID = state.mapID
    RefreshIconOverlay(frame, {
        id = state.mapID,
        name = state.name,
        timeLimit = state.timeLimit,
    })

    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:SetText(state.name or "", DUNGEON_NAME_COLOR.r, DUNGEON_NAME_COLOR.g, DUNGEON_NAME_COLOR.b)
    GameTooltip:AddLine(" ")
    AddTooltipLine("tooltip.pve_score", "评分：%s", ColorText(state.score or 0, state.scoreColor))

    if state.bestRun and state.level and state.level > 0 then
        AddTooltipLine("tooltip.pve_best", "最佳：%s层", tostring(state.level))

        AddDurationToTooltip(state.bestRun.durationSec, state.timeLimit)

        local dateText = FormatDate(state.bestRun.completionDate)
        if dateText then
            AddTooltipLine("tooltip.pve_date", "日期：%s", dateText)
        end

        AddMembersToTooltip(state.bestRun)
    else
        GameTooltip:AddLine(T("tooltip.pve_no_record", "最佳：无记录"), 1, 1, 1)
    end

    if db.pveClickTeleportEnabled == true and state.teleportSpellID then
        GameTooltip:AddLine(" ")
        if state.teleportRemaining and state.teleportRemaining > 0 then
            local color = RED_FONT_COLOR or DURATION_OVERTIME_COLOR
            GameTooltip:AddLine(string.format(T("tooltip.pve_teleport_cooldown", "传送冷却中：%s"), FormatDuration(state.teleportRemaining, true)), color.r or 1, color.g or 0.25, color.b or 0.25)
        else
            GameTooltip:AddLine(T("tooltip.pve_click_teleport", "点击传送"), 0.2, 1, 0.4)
        end
    end

    GameTooltip:Show()
end

local function OnIconSetUp(frame, mapInfo, isFirst)
    if frame then
        frame.yuiPVEIsFirst = isFirst == true
        EnsureIconShowHook(frame, GetChallengesFrameForIcon(frame))
        if IsRuntimeEnabled() then
            SuppressNativeLevel(frame)
        end
    end

    if mapInfo and mapInfo.id then
        local name, _, timeLimit = nil, nil, nil
        name, _, timeLimit = SafeCall(C_ChallengeMode and C_ChallengeMode.GetMapUIInfo, mapInfo.id)
        local enhancedMapInfo = {
            id = mapInfo.id,
            name = name or mapInfo.name,
            timeLimit = timeLimit or mapInfo.timeLimit,
        }
        CacheFrameMapInfo(frame, enhancedMapInfo)
        RefreshIconOverlay(frame, enhancedMapInfo)
    else
        RefreshIconOverlay(frame)
    end
end

local function InstallHooks()
    if hooksInstalled then return true end
    if not (hooksecurefunc and _G.ChallengesDungeonIconMixin and _G.ChallengesFrameMixin) then return false end
    if type(_G.ChallengesDungeonIconMixin.SetUp) ~= "function" or type(_G.ChallengesDungeonIconMixin.OnEnter) ~= "function" then return false end
    if type(_G.ChallengesFrameMixin.Update) ~= "function" then return false end

    hooksecurefunc(_G.ChallengesDungeonIconMixin, "SetUp", OnIconSetUp)
    hooksecurefunc(_G.ChallengesDungeonIconMixin, "OnEnter", ShowPVEIconTooltip)
    hooksecurefunc(_G.ChallengesFrameMixin, "Update", RefreshVisibleIcons)
    hooksInstalled = true
    RefreshVisibleIcons()
    return true
end

local function IsAddOnLoadedSafe(addonName)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(addonName) == true
    end
    if _G.IsAddOnLoaded then
        return _G.IsAddOnLoaded(addonName) == true
    end
    return false
end

local function EnsureEventFrame()
    if eventFrame or not CreateFrame then return eventFrame end
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event, addonName)
        if event == "ADDON_LOADED" and addonName == CHALLENGES_ADDON then
            if InstallHooks() and eventFrame then
                eventFrame:UnregisterEvent("ADDON_LOADED")
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            secureRefreshPending = false
            if eventFrame then
                eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            end
            RefreshVisibleIcons()
        end
    end)
    return eventFrame
end

MarkSecureRefreshPending = function()
    secureRefreshPending = true
    local frame = EnsureEventFrame()
    if frame then
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end

local function EnableRuntime()
    local wasActive = runtimeActive
    runtimeActive = true
    if not wasActive then
        PVEEnhancement._statsPanelDataCache = nil
        PVEEnhancement._statsPanelDataDirty = true
    end
    RegisterStatsPanelEvents()
    PVEEnhancement.PartyKeystonePanel.RegisterEvents()
    if InstallHooks() then
        QueueStatsPanelRefresh()
        PVEEnhancement.PartyKeystonePanel.QueueRefresh()
        return
    end

    local frame = EnsureEventFrame()
    if frame then
        frame:RegisterEvent("ADDON_LOADED")
    end

    if IsAddOnLoadedSafe(CHALLENGES_ADDON) then
        InstallHooks()
    end
    QueueStatsPanelRefresh()
    PVEEnhancement.PartyKeystonePanel.QueueRefresh()
end

local function DisableRuntime()
    runtimeActive = false
    PVEEnhancement.StatsPanel.UnregisterSharedAppearanceConsumer()
    UnregisterStatsPanelEvents()
    PVEEnhancement.PartyKeystonePanel.UnregisterEvents()
    if eventFrame then
        eventFrame:UnregisterEvent("ADDON_LOADED")
        eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    secureRefreshPending = false
    PVEEnhancement._statsPanelManuallyClosed = false
    PVEEnhancement._statsPanelWasEligible = false
    if statsPanel then
        PVEEnhancement.StatsPanel.HideActiveTooltip(statsPanel)
        statsPanel:Hide()
    end
    if PVEEnhancement.PartyKeystonePanel.frame then
        PVEEnhancement.PartyKeystonePanel.frame:Hide()
    end
    PVEEnhancement.RatingStats.HideFrame()
    local api = PVEEnhancement.PartyKeystonePanel.GetAPI()
    if api and api.Deactivate then
        api.Deactivate(PVEEnhancement)
    end
    RefreshVisibleIcons()
end

local function RefreshRuntime(db)
    if featureActive and GetDB(db).pveEnhancementEnabled == true then
        EnableRuntime()
        RefreshVisibleIcons()
    else
        DisableRuntime()
    end
end

function PVEEnhancement:NormalizeDB(db)
    return NormalizeDB(db)
end

function PVEEnhancement:RefreshRuntime(db)
    RefreshRuntime(db)
end

function PVEEnhancement:OnFeatureToggle(enable, db)
    featureActive = enable == true
    RefreshRuntime(db)
end

function PVEEnhancement:ClearDevStatsData(silent)
    local hadData = statsPanelDevData ~= nil
    statsPanelDevData = nil
    PVEEnhancement._statsPanelDataCache = nil
    PVEEnhancement._statsPanelDataDirty = true
    QueueStatsPanelRefresh()
    if hadData and not silent then
        PrintStatsDev("PVE stats fixture cleared.")
    end
    return hadData
end

function PVEEnhancement:HandleDevCommand(args)
    args = tostring(args or ""):match("^%s*(.-)%s*$") or ""
    local command, rest = args:match("^(%S+)%s*(.*)$")
    command = command and command:lower() or "help"
    rest = rest or ""
    if statsPanelDevData and YUI.IsDev ~= true then
        statsPanelDevData = nil
        PVEEnhancement._statsPanelDataCache = nil
        PVEEnhancement._statsPanelDataDirty = true
    end

    if command == "stress" then
        if YUI.IsDev ~= true then
            PrintStatsDev("Enable dev mode first: /yui dev on")
            return true
        end

        local countText, seedText = rest:match("^(%S*)%s*(%S*)")
        local count = math.floor(ClampNumber(tonumber(countText), 1, 100000, 5000))
        local seed = tonumber(seedText)
        local data, reason = BuildStatsPanelDevData(seed, count)
        if not data then
            PrintStatsDev("PVE stats stress fixture failed:", reason or "unknown")
            return true
        end

        statsPanelDevData = data
        QueueStatsPanelRefresh()
        PrintStatsDev("PVE stats stress enabled. Records:", data.recordCount, "Maps:", data.mapCount, "Week:", data.weeklyCount, "Season:", data.seasonCount, "Build:", string.format("%.2fms", data.buildMs or 0))
        return true
    elseif command == "week" or command == "weekly" then
        if YUI.IsDev ~= true then
            PrintStatsDev("Enable dev mode first: /yui dev on")
            return true
        end

        local countText, seedText = rest:match("^(%S*)%s*(%S*)")
        local weeklyCount = tonumber(countText)
        if weeklyCount == nil then
            PrintStatsDev("Usage: /yui dev pvestats week <count> [seed]")
            return true
        end
        weeklyCount = math.floor(ClampNumber(weeklyCount, 0, 100000, 0))
        local seed = tonumber(seedText)
        local data, reason = BuildStatsPanelDevData(seed, nil, weeklyCount)
        if not data then
            PrintStatsDev("PVE stats weekly fixture failed:", reason or "unknown")
            return true
        end

        statsPanelDevData = data
        QueueStatsPanelRefresh()
        PrintStatsDev("PVE stats weekly fixture enabled. Week:", data.weeklyCount, "Seed:", data.seed, "Maps:", data.mapCount, "Season:", data.seasonCount)
        return true
    elseif command == "random" or command == "generate" or command == "fill" then
        if YUI.IsDev ~= true then
            PrintStatsDev("Enable dev mode first: /yui dev on")
            return true
        end

        local seed = tonumber(rest:match("^(%S+)"))
        local data, reason = BuildStatsPanelDevData(seed)
        if not data then
            PrintStatsDev("PVE stats fixture failed:", reason or "unknown")
            return true
        end

        statsPanelDevData = data
        QueueStatsPanelRefresh()
        PrintStatsDev("PVE stats fixture enabled. Seed:", data.seed, "Maps:", data.mapCount, "Week:", data.weeklyCount, "Season:", data.seasonCount)
        return true
    elseif command == "clear" or command == "reset" or command == "off" then
        self:ClearDevStatsData()
        return true
    elseif command == "status" then
        if statsPanelDevData then
            PrintStatsDev("PVE stats fixture: on. Seed:", statsPanelDevData.seed, "Maps:", statsPanelDevData.mapCount, "Week:", statsPanelDevData.weeklyCount, "Season:", statsPanelDevData.seasonCount)
        else
            PrintStatsDev("PVE stats fixture: off.")
        end
        return true
    end

    PrintStatsDev("PVE stats dev commands:")
    PrintStatsDev("/yui dev pvestats stress [count] [seed]")
    PrintStatsDev("/yui dev pvestats random [seed]")
    PrintStatsDev("/yui dev pvestats week <count> [seed]")
    PrintStatsDev("/yui dev pvestats clear")
    PrintStatsDev("/yui dev pvestats status")
    return true
end

local function AddAlignedFieldGroup(options, label, fields, layout)
    layout = type(layout) == "table" and layout or {}
    if layout.hideDivider ~= true then
        options[#options + 1] = { type = "divider", label = label, alignLeft = true, width = 620 }
    end
    options[#options + 1] = {
        type = "custom",
        retainedFields = fields,
        width = 620,
        render = function(parent, x, y, width)
            local Settings = YUI.Settings
            if not (Settings and Settings.RenderAlignedFields) then
                return 620, 1
            end

            local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                x = x,
                y = y,
                width = math.min(width or 620, 620),
                columns = layout.columns or 2,
                labelPosition = layout.labelPosition or "top",
                columnGap = layout.columnGap or 24,
                labelWidth = layout.labelWidth or SETTING_LABEL_WIDTH,
                labelGap = layout.labelGap or 10,
                bodyWidth = layout.bodyWidth or (math.floor((620 - 24) / 2) - SETTING_LABEL_WIDTH - 10),
                valueWidth = layout.valueWidth or SETTING_INPUT_WIDTH,
                valueGap = layout.valueGap or 10,
                rowHeight = layout.rowHeight or 32,
                rowGap = layout.rowGap or 10,
                fields = fields,
            })
            return gridWidth, gridHeight
        end,
    }
end

function PVEEnhancement:BuildOptions(db)
    db = GetDB(db)

    local function Refresh()
        RefreshRuntime(db)
        RefreshVisibleIcons()
        PVEEnhancement.PartyKeystonePanel.Refresh(db)
    end

    local options = {}

    AddAlignedFieldGroup(options, T("settings.pve_enhancement", "PVE界面扩展"), {
        {
            type = "checkbox",
            label = T("settings.pve_enhancement_enabled", "启用 PVE 界面扩展"),
            get = function() return db.pveEnhancementEnabled == true end,
            settingsToggle = "pveEnhancement",
            searchKey = "settings.pve_enhancement_enabled",
            set = function(value)
                db.pveEnhancementEnabled = value == true
                Refresh()
            end,
        },
    }, { columns = 1, hideDivider = true })

    AddAlignedFieldGroup(options, T("settings.pve_content", "显示内容"), {
        {
            type = "checkbox",
            label = T("settings.pve_icon_name", "显示副本名"),
            get = function() return db.pveIconNameEnabled == true end,
            set = function(value)
                db.pveIconNameEnabled = value == true
                RefreshVisibleIcons()
            end,
        },
        {
            type = "checkbox",
            label = T("settings.pve_icon_level", "显示最高层数"),
            get = function() return db.pveIconLevelEnabled == true end,
            set = function(value)
                db.pveIconLevelEnabled = value == true
                RefreshVisibleIcons()
            end,
        },
        {
            type = "checkbox",
            label = T("settings.pve_icon_score", "显示分数"),
            get = function() return db.pveIconScoreEnabled == true end,
            set = function(value)
                db.pveIconScoreEnabled = value == true
                RefreshVisibleIcons()
            end,
        },
        {
            type = "checkbox",
            label = T("settings.pve_rating_stats", "显示评分排名估算"),
            disabled = PVEEnhancement.RatingStats.releaseEnabled ~= true,
            tooltip = PVEEnhancement.RatingStats.releaseEnabled ~= true and T("settings.pve_rating_stats_unavailable", "新赛季数据准备中。") or nil,
            get = function() return db.pveRatingStatsEnabled == true end,
            set = function(value)
                db.pveRatingStatsEnabled = value == true
                RefreshVisibleIcons()
            end,
        },
        {
            type = "checkbox",
            label = T("settings.pve_party_keystone_panel", "显示队伍钥石"),
            get = function() return db.pvePartyKeystonePanelEnabled == true end,
            set = function(value)
                db.pvePartyKeystonePanelEnabled = value == true
                PVEEnhancement.PartyKeystonePanel.Refresh(db)
            end,
        },
        {
            type = "checkbox",
            label = T("settings.pve_tooltip", "扩展鼠标提示"),
            get = function() return db.pveTooltipEnabled == true end,
            set = function(value)
                db.pveTooltipEnabled = value == true
                RefreshVisibleIcons()
            end,
        },
        {
            type = "checkbox",
            label = T("settings.pve_stats_panel", "显示本周大秘境统计面板"),
            get = function() return db.pveStatsPanelEnabled == true end,
            set = function(value)
                db.pveStatsPanelEnabled = value == true
                Refresh()
            end,
        },
    })

    AddAlignedFieldGroup(options, T("settings.pve_text", "文本样式"), {
        {
            type = "slider",
            label = T("settings.pve_icon_name_size", "副本名字号"),
            min = ICON_NAME_SIZE_MIN,
            max = ICON_NAME_SIZE_MAX,
            step = 1,
            get = function() return db.pveIconNameFontSize end,
            set = function(value)
                db.pveIconNameFontSize = ClampNumber(value, ICON_NAME_SIZE_MIN, ICON_NAME_SIZE_MAX, PVEEnhancement.defaults.pveIconNameFontSize)
                RefreshVisibleIcons()
            end,
        },
        {
            type = "slider",
            label = T("settings.pve_icon_level_size", "层数字号"),
            min = ICON_LEVEL_SIZE_MIN,
            max = ICON_LEVEL_SIZE_MAX,
            step = 1,
            get = function() return db.pveIconLevelFontSize end,
            set = function(value)
                db.pveIconLevelFontSize = ClampNumber(value, ICON_LEVEL_SIZE_MIN, ICON_LEVEL_SIZE_MAX, PVEEnhancement.defaults.pveIconLevelFontSize)
                RefreshVisibleIcons()
            end,
        },
        {
            type = "slider",
            label = T("settings.pve_icon_score_size", "分数字号"),
            min = ICON_SCORE_SIZE_MIN,
            max = ICON_SCORE_SIZE_MAX,
            step = 1,
            get = function() return db.pveIconScoreFontSize end,
            set = function(value)
                db.pveIconScoreFontSize = ClampNumber(value, ICON_SCORE_SIZE_MIN, ICON_SCORE_SIZE_MAX, PVEEnhancement.defaults.pveIconScoreFontSize)
                RefreshVisibleIcons()
            end,
        },
        {
            type = "slider",
            label = T("settings.pve_icon_level_offset_y", "层数Y偏移"),
            min = ICON_LEVEL_Y_OFFSET_MIN,
            max = ICON_LEVEL_Y_OFFSET_MAX,
            step = 1,
            get = function() return db.pveIconLevelYOffset end,
            set = function(value)
                db.pveIconLevelYOffset = ClampNumber(value, ICON_LEVEL_Y_OFFSET_MIN, ICON_LEVEL_Y_OFFSET_MAX, PVEEnhancement.defaults.pveIconLevelYOffset)
                RefreshVisibleIcons()
            end,
        },
    }, { labelWidth = 112, bodyWidth = 176 })

    AddAlignedFieldGroup(options, T("settings.pve_actions", "交互"), {
        {
            type = "checkbox",
            label = T("settings.pve_click_teleport", "点击图标传送"),
            get = function() return db.pveClickTeleportEnabled == true end,
            set = function(value)
                db.pveClickTeleportEnabled = value == true
                RefreshVisibleIcons()
            end,
        },
    }, { columns = 1 })

    return options
end

Tools.PVEEnhancement = PVEEnhancement
Tools:RegisterSubFeature(PVEEnhancement)

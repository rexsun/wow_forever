local YUI = _G.YUI
local YChat = YUI and YUI.YChat
if not YChat or (YUI.IsForever or YUI.IsRetail) ~= true then return end

local pairs = pairs
local tonumber = tonumber
local type = type
local floor = math.floor
local huge = math.huge
local match = string.match
local find = string.find
local lower = string.lower
local MAIN_WINDOW_MIN_WIDTH = 296
local MAIN_WINDOW_MAX_WIDTH = 800
local MAIN_WINDOW_MIN_HEIGHT = 120
local MAIN_WINDOW_MAX_HEIGHT = 800
local TAB_FONT_MIN_SIZE = 10
local TAB_FONT_MAX_SIZE = 16
local TAB_MIN_WIDTH = 48
local TAB_MAX_WIDTH = 160
local TAB_MIN_SPACING = 0
local TAB_MAX_SPACING = 16
local TAB_LEFT_INSET_MIN = 0
local TAB_LEFT_INSET_MAX = 32
local INPUT_HEIGHT_MIN = 20
local INPUT_HEIGHT_MAX = 48
local BORDER_MIN_WIDTH = 1
local BORDER_MAX_WIDTH = 4
local FADE_DELAY_MIN = 10
local FADE_DELAY_MAX = 600
local BODY_FONT_MIN_SIZE = 8
local BODY_FONT_MAX_SIZE = 32
local BODY_LINE_SPACING_MIN = 0
local BODY_LINE_SPACING_MAX = 8
local TIMESTAMP_GAP_MIN = 0
local TIMESTAMP_GAP_MAX = 18
local AUTO_INVITE_LIST_MAX = 32
local AUTO_INVITE_COOLDOWN_MIN = 1
local AUTO_INVITE_COOLDOWN_MAX = 300
local AUTO_INVITE_RATE_LIMIT_MIN = 1
local AUTO_INVITE_RATE_LIMIT_MAX = 20
local AUTO_INVITE_RATE_WINDOW_MIN = 1
local AUTO_INVITE_RATE_WINDOW_MAX = 60
local CHANNEL_ALIAS_MAX_BYTES = 48
local HISTORY_RESTORE_LIMIT_MIN = 10
local HISTORY_RESTORE_LIMIT_MAX = 200

local PRESETS = {
    clear = {
        backgroundAlpha = 0,
        borderStyle = "none",
        borderWidth = 1,
        tabStyle = "text",
        tabTextEffect = "outlineShadow",
        tabFontSize = 14,
        tabWidthMode = "auto",
        classColorTabs = true,
        classColorBorder = false,
        hideNativeButtons = true,
        inputPosition = "bottom",
        messageEffect = "softGlow",
    },
    deep = {
        backgroundAlpha = 0.76,
        borderStyle = "hairline",
        borderWidth = 1,
        tabStyle = "underline",
        tabTextEffect = "outlineShadow",
        tabFontSize = 14,
        tabWidthMode = "auto",
        classColorTabs = true,
        classColorBorder = false,
        hideNativeButtons = true,
        inputPosition = "bottom",
        messageEffect = "fade",
    },
}

local APPEARANCE_TABLES = {
    presets = PRESETS,
    validPresets = { clear = true, deep = true, custom = true },
    validFadeScopes = {
        all = true,
        outsideInstance = true,
        insideInstance = true,
        outOfCombat = true,
        solo = true,
    },
    validFadeStatsModes = {
        none = true,
        all = true,
        outOfCombat = true,
        inCombat = true,
    },
}
local VALID_BORDERS = { none = true, hairline = true }
local VALID_TAB_STYLES = {
    text = true,
    underline = true,
    block = true,
    darkUnderline = true,
}
local VALID_TAB_WIDTH_MODES = { auto = true, fixed = true }
local VALID_TAB_TEXT_EFFECTS = {
    none = true,
    shadow = true,
    outline = true,
    thick = true,
    outlineShadow = true,
}
local VALID_INPUT_POSITIONS = { top = true, bottom = true }
local VALID_TOOLTIP_ANCHORS = {
    ANCHOR_TOP = true,
    ANCHOR_BOTTOM = true,
    ANCHOR_TOPLEFT = true,
    ANCHOR_TOPRIGHT = true,
    ANCHOR_BOTTOMLEFT = true,
    ANCHOR_BOTTOMRIGHT = true,
    ANCHOR_LEFT = true,
    ANCHOR_RIGHT = true,
}
local VALID_MESSAGE_EFFECTS = { none = true, fade = true, softGlow = true }
local VALID_TIMESTAMP_FORMATS = { hms = true, hm = true }
local VALID_TIMESTAMP_LAYOUTS = { column = true, nativeInline = true }
local VALID_TYPOGRAPHY_OUTLINES = {
    none = true,
    outline = true,
    thick = true,
    shadow = true,
    outlineShadow = true,
}
local VALID_CHANNEL_NAME_STYLES = {
    native = true,
    compact = true,
    minimal = true,
    custom = true,
}
local VALID_PUBLIC_CHANNEL_FORMATS = {
    native = true,
    number = true,
    numberShort = true,
    short = true,
}
local VALID_CHANNEL_ALIAS_KEYS = {
    guild = true,
    officer = true,
    party = true,
    raid = true,
    raid_warning = true,
    instance = true,
    whisper = true,
    whisper_inform = true,
}
local VALID_AUTO_INVITE_MATCH_MODES = {
    exact = true,
    prefix = true,
    contains = true,
}
local VALID_HISTORY_LIMITS = {
    [500] = true,
    [1000] = true,
    [2000] = true,
    [5000] = true,
}
local VALID_CHAT_FRAME_LIMITS = {
    [50] = true,
    [100] = true,
    [200] = true,
    [300] = true,
    [500] = true,
    [1000] = true,
}
local RequestRefresh
local sharedMedia

local function ClampNumber(value, minimum, maximum, fallback)
    value = tonumber(value)
    if value == nil
        or value ~= value
        or value <= -huge
        or value >= huge
    then
        return fallback
    end
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function NormalizeColor(value, fallback)
    if type(value) ~= "table" then value = {} end
    value[1] = ClampNumber(value[1] or value.r, 0, 1, fallback[1])
    value[2] = ClampNumber(value[2] or value.g, 0, 1, fallback[2])
    value[3] = ClampNumber(value[3] or value.b, 0, 1, fallback[3])
    value[4] = ClampNumber(value[4] or value.a, 0, 1, fallback[4])
    value.r = nil
    value.g = nil
    value.b = nil
    value.a = nil
    return value
end

local function NormalizeEnum(value, allowed, fallback)
    return type(value) == "string" and allowed[value] == true and value or fallback
end

local function GetSharedMedia()
    if sharedMedia then return sharedMedia end
    local LibStub = _G.LibStub
    if type(LibStub) ~= "function" then return nil end
    local ok, media = pcall(LibStub, "LibSharedMedia-3.0", true)
    if ok and type(media) == "table" then sharedMedia = media end
    return sharedMedia
end

local function NormalizeMediaName(value)
    if type(value) ~= "string" then return nil end
    if value == ""
        or #value > 128
        or find(value, "[%c]")
        or match(value, "^%s*$")
    then
        return nil
    end

    local media = GetSharedMedia()
    if not media or type(media.Fetch) ~= "function" then return value end
    local exactOK, exactPath = pcall(media.Fetch, media, "font", value, true)
    if exactOK and type(exactPath) == "string" and exactPath ~= "" then return value end

    if type(media.List) ~= "function" then return value end
    local listOK, names = pcall(media.List, media, "font")
    if not listOK or type(names) ~= "table" then return value end
    local legacyKey = match(value, "^%s*(.-)%s*$")
    local recovered
    for index = 1, #names do
        local name = names[index]
        if type(name) == "string"
            and match(name, "^%s*(.-)%s*$") == legacyKey
        then
            if recovered and recovered ~= name then return value end
            recovered = name
        end
    end
    if recovered then return recovered end
    return value
end

local function NormalizeTextToken(value)
    if type(value) ~= "string" then return nil end
    value = match(value, "^%s*(.-)%s*$")
    if value == "" or #value > 128 or find(value, "[%c]") then return nil end
    return lower(value)
end

local function NormalizeTextList(value, fallback)
    if type(value) ~= "table" then value = fallback or {} end
    local normalized = {}
    local seen = {}
    for index = 1, #value do
        local token = NormalizeTextToken(value[index])
        if token and not seen[token] and #normalized < AUTO_INVITE_LIST_MAX then
            normalized[#normalized + 1] = token
            seen[token] = true
        end
    end
    return normalized
end

local function NormalizeChannelAlias(value)
    if type(value) ~= "string" then return nil end
    value = match(value, "^%s*(.-)%s*$")
    if value == ""
        or #value > CHANNEL_ALIAS_MAX_BYTES
        or find(value, "[%c%%|%[%]]")
    then
        return nil
    end
    return value
end

local function NormalizeChannelAliases(value)
    local normalized = {}
    if type(value) ~= "table" then return normalized end
    for key in pairs(VALID_CHANNEL_ALIAS_KEYS) do
        local alias = NormalizeChannelAlias(value[key])
        if alias then normalized[key] = alias end
    end
    return normalized
end

local function CopyValue(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do
        copy[CopyValue(key)] = CopyValue(child)
    end
    return copy
end

local function FillDefaults(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then return target end
    for key, defaultValue in pairs(defaults) do
        local value = target[key]
        if value == nil then
            target[key] = CopyValue(defaultValue)
        elseif type(value) == "table" and type(defaultValue) == "table" then
            FillDefaults(value, defaultValue)
        end
    end
    return target
end

local function NormalizeDB(db)
    if type(db.itemLinks) ~= "table" then db.itemLinks = {} end
    db.itemLinks.enabled = db.itemLinks.enabled == true
    db.itemLinks.cropIcons = db.itemLinks.cropIcons ~= false
    db.enabled = db.enabled == true
    if type(db.timestamp) ~= "table" then db.timestamp = {} end
    if db.timestamp.enabled == nil then db.timestamp.enabled = true end
    db.timestamp.enabled = db.timestamp.enabled == true
    local timestampDefaults = YChat.Defaults.timestamp
    db.timestamp.layout = NormalizeEnum(
        db.timestamp.layout,
        VALID_TIMESTAMP_LAYOUTS,
        timestampDefaults.layout
    )
    db.timestamp.format = NormalizeEnum(
        db.timestamp.format,
        VALID_TIMESTAMP_FORMATS,
        timestampDefaults.format
    )
    db.timestamp.color = NormalizeColor(db.timestamp.color, timestampDefaults.color)
    db.timestamp.nativeIndentedWrap = db.timestamp.nativeIndentedWrap == true
    db.timestamp.gap = floor(ClampNumber(
        db.timestamp.gap,
        TIMESTAMP_GAP_MIN,
        TIMESTAMP_GAP_MAX,
        timestampDefaults.gap
    ) + 0.5)

    if type(db.typography) ~= "table" then db.typography = {} end
    local typography = db.typography
    typography.font = NormalizeMediaName(typography.font)
    if typography.fontSize ~= nil then
        local fontSize = ClampNumber(
            typography.fontSize,
            BODY_FONT_MIN_SIZE,
            BODY_FONT_MAX_SIZE,
            nil
        )
        typography.fontSize = fontSize and floor(fontSize + 0.5) or nil
    end
    if typography.outline ~= nil then
        if typography.outline == "thickOutline" then
            typography.outline = "thick"
        end
        typography.outline = NormalizeEnum(
            typography.outline,
            VALID_TYPOGRAPHY_OUTLINES,
            nil
        )
    end
    if typography.lineSpacing ~= nil then
        local lineSpacing = ClampNumber(
            typography.lineSpacing,
            BODY_LINE_SPACING_MIN,
            BODY_LINE_SPACING_MAX,
            nil
        )
        typography.lineSpacing = lineSpacing and floor(lineSpacing + 0.5) or nil
    end

    if type(db.channelInput) ~= "table" then db.channelInput = {} end
    local channelDefaults = YChat.Defaults.channelInput
    db.channelInput.nameStyle = NormalizeEnum(
        db.channelInput.nameStyle,
        VALID_CHANNEL_NAME_STYLES,
        channelDefaults.nameStyle
    )
    if db.channelInput.nameStyle ~= "native" then
        db.channelInput.nameStyle = "native"
    end
    db.channelInput.publicFormat = NormalizeEnum(
        db.channelInput.publicFormat,
        VALID_PUBLIC_CHANNEL_FORMATS,
        channelDefaults.publicFormat
    )
    if db.channelInput.publicFormat == "number" then
        db.channelInput.publicFormat = "numberShort"
    end
    db.channelInput.customNames = NormalizeChannelAliases(db.channelInput.customNames)
    db.channelInput.showNumber = db.channelInput.publicFormat == "numberShort"
    db.channelInput.tabCycle = db.channelInput.tabCycle == true
    db.channelInput.hidePlayerRealm = db.channelInput.hidePlayerRealm == true

    if type(db.autoInvite) ~= "table" then db.autoInvite = {} end
    local autoInviteDefaults = YChat.Defaults.autoInvite
    local autoInvite = db.autoInvite
    autoInvite.enabled = autoInvite.enabled == true
    autoInvite.matchMode = NormalizeEnum(
        autoInvite.matchMode,
        VALID_AUTO_INVITE_MATCH_MODES,
        autoInviteDefaults.matchMode
    )
    autoInvite.keywords = NormalizeTextList(
        autoInvite.keywords,
        autoInviteDefaults.keywords
    )
    if #autoInvite.keywords == 0 then
        autoInvite.keywords = NormalizeTextList(autoInviteDefaults.keywords)
    end
    autoInvite.allowlist = NormalizeTextList(autoInvite.allowlist)
    autoInvite.denylist = NormalizeTextList(autoInvite.denylist)
    autoInvite.senderCooldown = floor(ClampNumber(
        autoInvite.senderCooldown,
        AUTO_INVITE_COOLDOWN_MIN,
        AUTO_INVITE_COOLDOWN_MAX,
        autoInviteDefaults.senderCooldown
    ) + 0.5)
    autoInvite.rateLimit = floor(ClampNumber(
        autoInvite.rateLimit,
        AUTO_INVITE_RATE_LIMIT_MIN,
        AUTO_INVITE_RATE_LIMIT_MAX,
        autoInviteDefaults.rateLimit
    ) + 0.5)
    autoInvite.rateWindow = floor(ClampNumber(
        autoInvite.rateWindow,
        AUTO_INVITE_RATE_WINDOW_MIN,
        AUTO_INVITE_RATE_WINDOW_MAX,
        autoInviteDefaults.rateWindow
    ) + 0.5)

    if type(db.history) ~= "table" then db.history = {} end
    local historyDefaults = YChat.Defaults.history
    db.history.enabled = db.history.enabled == true
    local frameLimit = floor(tonumber(db.history.frameLimit) or 0)
    db.history.frameLimit = VALID_CHAT_FRAME_LIMITS[frameLimit]
        and frameLimit
        or historyDefaults.frameLimit
    local historyLimit = floor(tonumber(db.history.limit) or 0)
    db.history.limit = VALID_HISTORY_LIMITS[historyLimit]
        and historyLimit
        or historyDefaults.limit
    db.history.restoreOnLogin = db.history.restoreOnLogin == true
    db.history.restoreLimit = floor(ClampNumber(
        db.history.restoreLimit,
        HISTORY_RESTORE_LIMIT_MIN,
        HISTORY_RESTORE_LIMIT_MAX,
        historyDefaults.restoreLimit
    ) + 0.5)
    if type(db.history.categories) ~= "table" then db.history.categories = {} end
    for key, defaultValue in pairs(historyDefaults.categories) do
        if type(db.history.categories[key]) ~= "boolean" then
            db.history.categories[key] = defaultValue == true
        end
    end

    local defaults = YChat.Defaults
    local appearanceDefaults = defaults.appearance
    if type(db.appearance) ~= "table" then db.appearance = {} end
    local appearance = db.appearance
    appearance.preset = NormalizeEnum(
        appearance.preset,
        APPEARANCE_TABLES.validPresets,
        appearanceDefaults.preset
    )
    local presetFallback = APPEARANCE_TABLES.presets[appearance.preset]
        or (appearance.preset == "custom" and APPEARANCE_TABLES.presets.clear)
        or APPEARANCE_TABLES.presets.deep
    appearance.backgroundAlpha = ClampNumber(
        appearance.backgroundAlpha,
        0,
        1,
        presetFallback.backgroundAlpha or appearanceDefaults.backgroundAlpha
    )
    appearance.backgroundColor = NormalizeColor(
        appearance.backgroundColor,
        appearanceDefaults.backgroundColor
    )
    local legacyAccentBorder = appearance.borderStyle == "accent"
    if legacyAccentBorder then appearance.borderStyle = "hairline" end
    appearance.borderStyle = NormalizeEnum(
        appearance.borderStyle,
        VALID_BORDERS,
        presetFallback.borderStyle or appearanceDefaults.borderStyle
    )
    appearance.borderWidth = floor(ClampNumber(
        legacyAccentBorder and 2 or appearance.borderWidth,
        BORDER_MIN_WIDTH,
        BORDER_MAX_WIDTH,
        appearanceDefaults.borderWidth
    ) + 0.5)
    appearance.borderColor = NormalizeColor(
        appearance.borderColor,
        appearanceDefaults.borderColor
    )
    appearance.classColorBorder = appearance.classColorBorder == true
    appearance.tabStyle = NormalizeEnum(
        appearance.tabStyle,
        VALID_TAB_STYLES,
        presetFallback.tabStyle or appearanceDefaults.tabStyle
    )
    appearance.tabTextEffect = NormalizeEnum(
        appearance.tabTextEffect,
        VALID_TAB_TEXT_EFFECTS,
        appearanceDefaults.tabTextEffect
    )
    if appearance.tabFontSize == 12
        and (appearance.preset == "clear" or appearance.preset == "deep")
    then
        appearance.tabFontSize = 14
    end
    appearance.tabFontSize = floor(ClampNumber(
        appearance.tabFontSize,
        TAB_FONT_MIN_SIZE,
        TAB_FONT_MAX_SIZE,
        appearanceDefaults.tabFontSize
    ) + 0.5)
    appearance.tabWidthMode = NormalizeEnum(
        appearance.tabWidthMode,
        VALID_TAB_WIDTH_MODES,
        appearanceDefaults.tabWidthMode
    )
    appearance.tabWidth = floor(ClampNumber(
        appearance.tabWidth,
        TAB_MIN_WIDTH,
        TAB_MAX_WIDTH,
        appearanceDefaults.tabWidth
    ) + 0.5)
    appearance.tabSpacing = floor(ClampNumber(
        appearance.tabSpacing,
        TAB_MIN_SPACING,
        TAB_MAX_SPACING,
        appearanceDefaults.tabSpacing
    ) + 0.5)
    appearance.tabLeftInset = floor(ClampNumber(
        appearance.tabLeftInset,
        TAB_LEFT_INSET_MIN,
        TAB_LEFT_INSET_MAX,
        appearanceDefaults.tabLeftInset
    ) + 0.5)
    appearance.classColorTabs = appearance.classColorTabs ~= false
    appearance.classColorWhisperNames = appearance.classColorWhisperNames ~= false
    appearance.tabColor = NormalizeColor(
        appearance.tabColor,
        appearanceDefaults.tabColor
    )
    appearance.hideNativeButtons = appearance.hideNativeButtons ~= false
    appearance.hideCombatLog = appearance.hideCombatLog == true
    appearance.fadeElements = appearance.fadeElements == true
    appearance.fadeScope = NormalizeEnum(
        appearance.fadeScope,
        APPEARANCE_TABLES.validFadeScopes,
        appearanceDefaults.fadeScope
    )
    appearance.fadeDelay = floor(ClampNumber(
        appearance.fadeDelay,
        FADE_DELAY_MIN,
        FADE_DELAY_MAX,
        appearanceDefaults.fadeDelay
    ) + 0.5)
    appearance.fadeChatBar = appearance.fadeChatBar == true
    appearance.fadeStatsMode = NormalizeEnum(
        appearance.fadeStatsMode,
        APPEARANCE_TABLES.validFadeStatsModes,
        appearanceDefaults.fadeStatsMode
    )
    appearance.inputPosition = NormalizeEnum(
        appearance.inputPosition,
        VALID_INPUT_POSITIONS,
        appearanceDefaults.inputPosition
    )
    appearance.inputHeight = floor(ClampNumber(
        appearance.inputHeight,
        INPUT_HEIGHT_MIN,
        INPUT_HEIGHT_MAX,
        appearanceDefaults.inputHeight
    ) + 0.5)
    local tooltipAnchor = appearance.tooltipAnchor
    if tooltipAnchor == "ANCHOR_CURSOR" then tooltipAnchor = "ANCHOR_RIGHT" end
    appearance.tooltipAnchor = NormalizeEnum(
        tooltipAnchor,
        VALID_TOOLTIP_ANCHORS,
        appearanceDefaults.tooltipAnchor
    )
    appearance.messageEffect = NormalizeEnum(
        appearance.messageEffect,
        VALID_MESSAGE_EFFECTS,
        presetFallback.messageEffect or appearanceDefaults.messageEffect
    )

    if type(db.layout) ~= "table" then db.layout = {} end
    local layout = db.layout
    if layout.mainWidth ~= nil then
        layout.mainWidth = ClampNumber(
            layout.mainWidth,
            MAIN_WINDOW_MIN_WIDTH,
            MAIN_WINDOW_MAX_WIDTH,
            nil
        )
        if layout.mainWidth ~= nil then
            layout.mainWidth = floor(layout.mainWidth + 0.5)
        end
    end
    if layout.mainHeight ~= nil then
        layout.mainHeight = ClampNumber(
            layout.mainHeight,
            MAIN_WINDOW_MIN_HEIGHT,
            MAIN_WINDOW_MAX_HEIGHT,
            nil
        )
        if layout.mainHeight ~= nil then
            layout.mainHeight = floor(layout.mainHeight + 0.5)
        end
    end

    return db
end

function YChat:CopyConfigValue(value)
    return CopyValue(value)
end

function YChat:MergeDefaults(db)
    return FillDefaults(db, self.Defaults)
end

function YChat:GetProfile()
    local db = YUI.DB
    if not (db and type(db.GetProfile) == "function") then return nil end
    return db:GetProfile(self.PRODUCT_ID)
end

function YChat:EnsureDB()
    local profile = self:GetProfile()
    if type(profile) ~= "table" then
        self.db = self.db or CopyValue(self.Defaults)
        return NormalizeDB(self.db)
    end
    if type(profile[self.STORAGE_KEY]) ~= "table" then
        profile[self.STORAGE_KEY] = {}
    end
    self.db = profile[self.STORAGE_KEY]
    local legacyChannelInput = self.db.channelInput
    local legacyAutoInvite = self.db.autoInvite
    local legacyAppearance = self.db.appearance
    local legacyPresetDefaults
    local legacyMissingPresetFields
    if type(legacyAppearance) == "table" then
        legacyPresetDefaults = APPEARANCE_TABLES.presets[legacyAppearance.preset]
        if legacyAppearance.preset == "custom" then
            legacyPresetDefaults = APPEARANCE_TABLES.presets.clear
        end
        if legacyPresetDefaults then
            legacyMissingPresetFields = {}
            for key in pairs(legacyPresetDefaults) do
                if legacyAppearance[key] == nil then
                    legacyMissingPresetFields[key] = true
                end
            end
        end
    end
    local needsPublicFormatMigration = type(legacyChannelInput) ~= "table"
        or legacyChannelInput.publicFormat == nil
    local needsInviteKeywordMigration = type(legacyAutoInvite) == "table"
        and type(legacyAutoInvite.keywords) == "table"
        and #legacyAutoInvite.keywords == 1
        and legacyAutoInvite.keywords[1] == "组我"
    self:MergeDefaults(self.db)
    if legacyMissingPresetFields then
        for key in pairs(legacyMissingPresetFields) do
            self.db.appearance[key] = legacyPresetDefaults[key]
        end
    end
    if needsPublicFormatMigration then
        local channelInput = self.db.channelInput
        if type(legacyChannelInput) ~= "table" then
            channelInput.publicFormat = self.Defaults.channelInput.publicFormat
        elseif channelInput.nameStyle == "native" and channelInput.showNumber ~= false then
            channelInput.publicFormat = "native"
        elseif channelInput.showNumber == false then
            channelInput.publicFormat = "native"
        else
            channelInput.publicFormat = "numberShort"
        end
    end
    if needsInviteKeywordMigration then
        self.db.autoInvite.keywords = { "123" }
    end
    return NormalizeDB(self.db)
end

function YChat:GetDB()
    return self:EnsureDB()
end

function YChat:IsEnabled()
    local db = self:GetDB()
    return db and db.enabled == true
end

function YChat:SetEnabled(enabled, fromLifecycle)
    local db = self:GetDB()
    if not db then return false end
    enabled = enabled == true
    db.enabled = enabled
    self.sessionEnabled = enabled
    if not fromLifecycle and YUI.Module and type(YUI.Module.SetEnabled) == "function" then
        return YUI.Module:SetEnabled(self.PRODUCT_ID, enabled)
    end
    return true
end

function YChat:IsTimestampEnabled()
    local db = self:GetDB()
    return db and db.timestamp and db.timestamp.enabled == true
end

function YChat:SetTimestampEnabled(enabled)
    return self:SetTimestampValue("enabled", enabled == true)
end

function YChat:GetTimestamp()
    local db = self:GetDB()
    return db and db.timestamp or nil
end

function YChat:GetTimestampValue(key)
    local timestamp = self:GetTimestamp()
    if not timestamp
        or (key ~= "enabled" and key ~= "layout" and key ~= "format"
            and key ~= "color" and key ~= "nativeIndentedWrap" and key ~= "gap")
    then
        return nil
    end
    return key == "color" and CopyValue(timestamp.color) or timestamp[key]
end

function YChat:SetTimestampValue(key, value)
    local db = self:GetDB()
    if not db or type(db.timestamp) ~= "table" then return false end
    local timestamp = db.timestamp
    if key == "enabled" or key == "nativeIndentedWrap" then
        if type(value) ~= "boolean" then return false, "invalid-timestamp-value" end
    elseif key == "layout" then
        if type(value) ~= "string" or VALID_TIMESTAMP_LAYOUTS[value] ~= true then
            return false, "invalid-timestamp-value"
        end
    elseif key == "format" then
        if type(value) ~= "string" or VALID_TIMESTAMP_FORMATS[value] ~= true then
            return false, "invalid-timestamp-value"
        end
    elseif key == "gap" then
        local number = tonumber(value)
        if number == nil or number ~= number or number <= -huge or number >= huge then
            return false, "invalid-timestamp-value"
        end
        value = floor(ClampNumber(
            number,
            TIMESTAMP_GAP_MIN,
            TIMESTAMP_GAP_MAX,
            timestamp.gap
        ) + 0.5)
    elseif key == "color" then
        if type(value) ~= "table" then return false, "invalid-timestamp-value" end
        value = NormalizeColor(value, timestamp.color)
    else
        return false, "unknown-timestamp-key"
    end
    local current = timestamp[key]
    local unchanged = current == value
    if key == "color" and type(current) == "table" then
        unchanged = current[1] == value[1]
            and current[2] == value[2]
            and current[3] == value[3]
            and current[4] == value[4]
    end
    if unchanged then return true, false end
    timestamp[key] = value
    local activeLayout = self.timestampLayoutAtLoad
    if key == "layout"
        or (activeLayout == "nativeInline"
            and (key == "enabled" or key == "format" or key == "color"))
    then
        return true, true, "reload-required"
    end
    return RequestRefresh("timestamp-" .. key), true
end

function YChat:GetAppearance()
    local db = self:GetDB()
    return db and db.appearance or nil
end

function YChat:GetLayout()
    local db = self:GetDB()
    return db and db.layout or nil
end

function YChat:GetTypography()
    local db = self:GetDB()
    local typography = db and db.typography or nil
    if typography and typography.font ~= nil then
        local normalized = NormalizeMediaName(typography.font)
        if normalized ~= nil then typography.font = normalized end
    end
    return typography
end

function YChat:NormalizeFontMediaName(value)
    return NormalizeMediaName(value)
end

function YChat:GetTypographyValue(key)
    local typography = self:GetTypography()
    if not typography
        or (key ~= "font" and key ~= "fontSize"
            and key ~= "outline" and key ~= "lineSpacing")
    then
        return nil
    end
    return typography[key]
end

function YChat:GetChannelInput()
    local db = self:GetDB()
    return db and db.channelInput or nil
end

function YChat:GetChannelInputValue(key)
    local channelInput = self:GetChannelInput()
    if not channelInput
        or (key ~= "nameStyle" and key ~= "publicFormat"
            and key ~= "showNumber" and key ~= "tabCycle" and key ~= "hidePlayerRealm")
    then
        return nil
    end
    return channelInput[key]
end

RequestRefresh = function(reason)
    if YUI.Module and type(YUI.Module.Refresh) == "function" then
        return YUI.Module:Refresh(YChat.PRODUCT_ID, reason or "appearance-config")
    end
    return true
end

function YChat:SetTypographyValue(key, value)
    local typography = self:GetTypography()
    if not typography then return false, "typography-db-unavailable" end
    if key == "font" then
        value = NormalizeMediaName(value)
        if value == nil then
            return false, "invalid-typography-value"
        end
    elseif key == "fontSize" then
        local number = tonumber(value)
        if number == nil or number ~= number or number <= -huge or number >= huge then
            return false, "invalid-typography-value"
        end
        value = floor(ClampNumber(
            number,
            BODY_FONT_MIN_SIZE,
            BODY_FONT_MAX_SIZE,
            BODY_FONT_MIN_SIZE
        ) + 0.5)
    elseif key == "outline" then
        if value == "thickOutline" then value = "thick" end
        if type(value) ~= "string" or VALID_TYPOGRAPHY_OUTLINES[value] ~= true then
            return false, "invalid-typography-value"
        end
    elseif key == "lineSpacing" then
        local number = tonumber(value)
        if number == nil or number ~= number or number <= -huge or number >= huge then
            return false, "invalid-typography-value"
        end
        value = floor(ClampNumber(
            number,
            BODY_LINE_SPACING_MIN,
            BODY_LINE_SPACING_MAX,
            BODY_LINE_SPACING_MIN
        ) + 0.5)
    else
        return false, "unknown-typography-key"
    end
    if typography[key] == value then return true, false end
    typography[key] = value
    return RequestRefresh("typography-" .. key), true
end

function YChat:SetItemLinksEnabled(value)
    if type(value) ~= "boolean" then return false, "invalid-item-links-value" end
    local db = self:GetDB()
    if db.itemLinks.enabled == value then return true, false end
    db.itemLinks.enabled = value
    return RequestRefresh("item-links"), true
end

function YChat:SetItemLinksCropIcons(value)
    if type(value) ~= "boolean" then return false, "invalid-item-links-value" end
    local db = self:GetDB()
    if db.itemLinks.cropIcons == value then return true, false end
    db.itemLinks.cropIcons = value
    return RequestRefresh("item-links-crop"), true
end

function YChat:ResetTypographyValue(key)
    local typography = self:GetTypography()
    if not typography then return false, "typography-db-unavailable" end
    if key ~= "font" and key ~= "fontSize" and key ~= "outline" and key ~= "lineSpacing" then
        return false, "unknown-typography-key"
    end
    if typography[key] == nil then return true, false end
    typography[key] = nil
    return RequestRefresh("typography-reset-" .. key), true
end

function YChat:SetChannelInputValue(key, value)
    local channelInput = self:GetChannelInput()
    if not channelInput then return false, "channel-input-db-unavailable" end
    if key == "nameStyle" then
        if value ~= "native" then
            return false, "invalid-channel-input-value"
        end
    elseif key == "publicFormat" then
        if value ~= "native" and value ~= "numberShort" and value ~= "short" then
            return false, "invalid-channel-input-value"
        end
    elseif key == "showNumber" or key == "tabCycle" or key == "hidePlayerRealm" then
        if type(value) ~= "boolean" then return false, "invalid-channel-input-value" end
    else
        return false, "unknown-channel-input-key"
    end
    if channelInput[key] == value then return true, false end
    channelInput[key] = value
    if key == "publicFormat" then
        channelInput.showNumber = value == "numberShort"
    elseif key == "showNumber" then
        channelInput.publicFormat = value and "numberShort" or "native"
    end
    return RequestRefresh("channel-input-" .. key), true
end

function YChat:GetChannelAliases()
    local channelInput = self:GetChannelInput()
    return CopyValue(channelInput and channelInput.customNames or {})
end

function YChat:SetChannelAliases(values)
    local channelInput = self:GetChannelInput()
    if not channelInput or type(values) ~= "table" then
        return false, "channel-input-db-unavailable"
    end
    local normalized = NormalizeChannelAliases(values)
    for key, value in pairs(values) do
        if VALID_CHANNEL_ALIAS_KEYS[key] == true
            and value ~= nil and value ~= ""
            and normalized[key] == nil
        then
            return false, "invalid-channel-alias"
        end
    end
    channelInput.customNames = normalized
    channelInput.nameStyle = "native"
    return RequestRefresh("channel-input-custom-names"), true
end

function YChat:ResetChannelAliases(style)
    local channelInput = self:GetChannelInput()
    if not channelInput then return false, "channel-input-db-unavailable" end
    channelInput.customNames = {}
    channelInput.nameStyle = "native"
    return RequestRefresh("channel-input-custom-reset"), true
end

function YChat:GetAutoInvite()
    local db = self:GetDB()
    return db and db.autoInvite or nil
end

function YChat:GetAutoInviteValue(key)
    local config = self:GetAutoInvite()
    if not config then return nil end
    if key == "keywords" or key == "allowlist" or key == "denylist" then
        return CopyValue(config[key])
    end
    if key ~= "enabled" and key ~= "matchMode"
        and key ~= "senderCooldown" and key ~= "rateLimit"
        and key ~= "rateWindow"
    then
        return nil
    end
    return config[key]
end

function YChat:SetAutoInviteValue(key, value)
    local config = self:GetAutoInvite()
    if not config then return false, "auto-invite-db-unavailable" end
    if key == "enabled" then
        if type(value) ~= "boolean" then return false, "invalid-auto-invite-value" end
    elseif key == "matchMode" then
        if type(value) ~= "string" or VALID_AUTO_INVITE_MATCH_MODES[value] ~= true then
            return false, "invalid-auto-invite-value"
        end
    elseif key == "senderCooldown" then
        value = floor(ClampNumber(
            value,
            AUTO_INVITE_COOLDOWN_MIN,
            AUTO_INVITE_COOLDOWN_MAX,
            config.senderCooldown
        ) + 0.5)
    elseif key == "rateLimit" then
        value = floor(ClampNumber(
            value,
            AUTO_INVITE_RATE_LIMIT_MIN,
            AUTO_INVITE_RATE_LIMIT_MAX,
            config.rateLimit
        ) + 0.5)
    elseif key == "rateWindow" then
        value = floor(ClampNumber(
            value,
            AUTO_INVITE_RATE_WINDOW_MIN,
            AUTO_INVITE_RATE_WINDOW_MAX,
            config.rateWindow
        ) + 0.5)
    else
        return false, "unknown-auto-invite-key"
    end
    if value == nil then return false, "invalid-auto-invite-value" end
    if config[key] == value then return true, false end
    config[key] = value
    return RequestRefresh("auto-invite-" .. key), true
end

local function ListsEqual(left, right)
    if #left ~= #right then return false end
    for index = 1, #left do
        if left[index] ~= right[index] then return false end
    end
    return true
end

function YChat:SetAutoInviteList(key, values)
    if key ~= "keywords" and key ~= "allowlist" and key ~= "denylist" then
        return false, "unknown-auto-invite-list"
    end
    local config = self:GetAutoInvite()
    if not config then return false, "auto-invite-db-unavailable" end
    local normalized = NormalizeTextList(values)
    if key == "keywords" and #normalized == 0 then
        return false, "auto-invite-keywords-empty"
    end
    if ListsEqual(config[key], normalized) then return true, false end
    config[key] = normalized
    return RequestRefresh("auto-invite-" .. key), true
end

function YChat:AddAutoInviteListValue(key, value)
    local config = self:GetAutoInvite()
    if not config or type(config[key]) ~= "table" then
        return false, "unknown-auto-invite-list"
    end
    local token = NormalizeTextToken(value)
    if not token then return false, "invalid-auto-invite-list-value" end
    local values = CopyValue(config[key])
    values[#values + 1] = token
    return self:SetAutoInviteList(key, values)
end

function YChat:RemoveAutoInviteListValue(key, value)
    local config = self:GetAutoInvite()
    if not config or type(config[key]) ~= "table" then
        return false, "unknown-auto-invite-list"
    end
    local token = NormalizeTextToken(value)
    if not token then return false, "invalid-auto-invite-list-value" end
    local values = {}
    for index = 1, #config[key] do
        local current = config[key][index]
        if current ~= token then values[#values + 1] = current end
    end
    return self:SetAutoInviteList(key, values)
end

function YChat:GetHistory()
    local db = self:GetDB()
    return db and db.history or nil
end

function YChat:GetHistoryValue(key)
    local history = self:GetHistory()
    if not history
        or (key ~= "enabled" and key ~= "frameLimit" and key ~= "limit"
            and key ~= "restoreOnLogin" and key ~= "restoreLimit")
    then
        return nil
    end
    return history[key]
end

function YChat:SetHistoryValue(key, value)
    local history = self:GetHistory()
    if not history then return false, "history-db-unavailable" end
    if key == "enabled" or key == "restoreOnLogin" then
        if type(value) ~= "boolean" then return false, "invalid-history-value" end
    elseif key == "frameLimit" then
        value = tonumber(value)
        value = value and floor(value) or nil
        if not value or VALID_CHAT_FRAME_LIMITS[value] ~= true then
            return false, "invalid-history-value"
        end
    elseif key == "limit" then
        value = tonumber(value)
        value = value and floor(value) or nil
        if not value or VALID_HISTORY_LIMITS[value] ~= true then
            return false, "invalid-history-value"
        end
    elseif key == "restoreLimit" then
        local number = tonumber(value)
        if number == nil
            or number ~= number
            or number <= -huge
            or number >= huge
        then
            return false, "invalid-history-value"
        end
        value = floor(ClampNumber(
            number,
            HISTORY_RESTORE_LIMIT_MIN,
            HISTORY_RESTORE_LIMIT_MAX,
            history.restoreLimit
        ) + 0.5)
    else
        return false, "unknown-history-key"
    end
    if history[key] == value then return true, false end
    history[key] = value
    return RequestRefresh("history-" .. key), true
end

function YChat:GetHistoryCategoryValue(key)
    local history = self:GetHistory()
    local categories = history and history.categories
    if type(categories) ~= "table"
        or type(self.Defaults.history.categories[key]) ~= "boolean"
    then
        return nil
    end
    return categories[key] == true
end

function YChat:SetHistoryCategoryValue(key, value)
    local history = self:GetHistory()
    if not history or type(history.categories) ~= "table" then
        return false, "history-db-unavailable"
    end
    if type(self.Defaults.history.categories[key]) ~= "boolean" or type(value) ~= "boolean" then
        return false, "invalid-history-category"
    end
    if history.categories[key] == value then return true, false end
    history.categories[key] = value
    return RequestRefresh("history-category-" .. key), true
end

function YChat:ApplyAppearancePreset(preset)
    local values = APPEARANCE_TABLES.presets[preset]
    if type(values) ~= "table" then return false, "invalid-preset" end
    local appearance = self:GetAppearance()
    if not appearance then return false, "appearance-db-unavailable" end

    local changed = appearance.preset ~= preset
    if not changed then
        for key, value in pairs(values) do
            if appearance[key] ~= value then
                changed = true
                break
            end
        end
    end
    if not changed then return true, false end
    for key, value in pairs(values) do
        appearance[key] = value
    end
    appearance.preset = preset
    return RequestRefresh("appearance-preset-" .. preset), true
end

function YChat:SelectAppearancePreset(preset)
    if preset == "custom" then
        local appearance = self:GetAppearance()
        if not appearance then return false, "appearance-db-unavailable" end
        if appearance.preset == "custom" then return true, false end
        appearance.preset = "custom"
        return RequestRefresh("appearance-preset-custom"), true
    end
    return self:ApplyAppearancePreset(preset)
end

function YChat:SetAppearanceValue(key, value)
    local appearance = self:GetAppearance()
    if not appearance then return false, "appearance-db-unavailable" end

    if key == "backgroundAlpha" then
        local number = tonumber(value)
        if number == nil
            or number ~= number
            or number <= -huge
            or number >= huge
        then
            return false, "invalid-appearance-value"
        end
        value = ClampNumber(value, 0, 1, appearance.backgroundAlpha)
    elseif key == "borderStyle" then
        if type(value) ~= "string" or VALID_BORDERS[value] ~= true then
            return false, "invalid-appearance-value"
        end
    elseif key == "borderWidth" then
        local number = tonumber(value)
        if number == nil
            or number ~= number
            or number <= -huge
            or number >= huge
        then
            return false, "invalid-appearance-value"
        end
        value = floor(ClampNumber(
            number,
            BORDER_MIN_WIDTH,
            BORDER_MAX_WIDTH,
            appearance.borderWidth
        ) + 0.5)
    elseif key == "tabStyle" then
        if type(value) ~= "string" or VALID_TAB_STYLES[value] ~= true then
            return false, "invalid-appearance-value"
        end
    elseif key == "tabWidthMode" then
        if type(value) ~= "string" or VALID_TAB_WIDTH_MODES[value] ~= true then
            return false, "invalid-appearance-value"
        end
    elseif key == "tabTextEffect" then
        if type(value) ~= "string" or VALID_TAB_TEXT_EFFECTS[value] ~= true then
            return false, "invalid-appearance-value"
        end
    elseif key == "tabFontSize"
        or key == "tabWidth"
        or key == "tabSpacing"
        or key == "tabLeftInset"
        or key == "inputHeight"
        or key == "fadeDelay"
    then
        local number = tonumber(value)
        if number == nil
            or number ~= number
            or number <= -huge
            or number >= huge
        then
            return false, "invalid-appearance-value"
        end
        local minimum = TAB_FONT_MIN_SIZE
        local maximum = TAB_FONT_MAX_SIZE
        if key == "tabWidth" then
            minimum = TAB_MIN_WIDTH
            maximum = TAB_MAX_WIDTH
        elseif key == "tabSpacing" then
            minimum = TAB_MIN_SPACING
            maximum = TAB_MAX_SPACING
        elseif key == "tabLeftInset" then
            minimum = TAB_LEFT_INSET_MIN
            maximum = TAB_LEFT_INSET_MAX
        elseif key == "inputHeight" then
            minimum = INPUT_HEIGHT_MIN
            maximum = INPUT_HEIGHT_MAX
        elseif key == "fadeDelay" then
            minimum = FADE_DELAY_MIN
            maximum = FADE_DELAY_MAX
        end
        value = floor(ClampNumber(
            number,
            minimum,
            maximum,
            appearance[key]
        ) + 0.5)
    elseif key == "inputPosition" then
        if type(value) ~= "string" or VALID_INPUT_POSITIONS[value] ~= true then
            return false, "invalid-appearance-value"
        end
    elseif key == "fadeScope" then
        if type(value) ~= "string"
            or APPEARANCE_TABLES.validFadeScopes[value] ~= true
        then
            return false, "invalid-appearance-value"
        end
    elseif key == "fadeStatsMode" then
        if type(value) ~= "string"
            or APPEARANCE_TABLES.validFadeStatsModes[value] ~= true
        then
            return false, "invalid-appearance-value"
        end
    elseif key == "tooltipAnchor" then
        if type(value) ~= "string" or VALID_TOOLTIP_ANCHORS[value] ~= true then
            return false, "invalid-appearance-value"
        end
    elseif key == "messageEffect" then
        if type(value) ~= "string" or VALID_MESSAGE_EFFECTS[value] ~= true then
            return false, "invalid-appearance-value"
        end
    elseif key == "classColorTabs"
        or key == "classColorBorder"
        or key == "classColorWhisperNames"
        or key == "hideNativeButtons"
        or key == "hideCombatLog"
        or key == "fadeElements"
        or key == "fadeChatBar"
    then
        if type(value) ~= "boolean" then return false, "invalid-appearance-value" end
    elseif key == "backgroundColor" or key == "borderColor" or key == "tabColor" then
        if type(value) ~= "table" then return false, "invalid-appearance-value" end
        value = NormalizeColor(value, appearance[key])
    else
        return false, "unknown-appearance-key"
    end

    local current = appearance[key]
    local unchanged = current == value
    if (key == "backgroundColor" or key == "borderColor" or key == "tabColor")
        and type(current) == "table"
        and type(value) == "table"
    then
        unchanged = current[1] == value[1]
            and current[2] == value[2]
            and current[3] == value[3]
            and current[4] == value[4]
    end
    if unchanged then return true, false end

    appearance[key] = value
    appearance.preset = "custom"
    return RequestRefresh("appearance-" .. key), true
end

function YChat:PreviewInputHeight(value)
    local appearance = self:GetAppearance()
    if not appearance then return false, "appearance-db-unavailable" end
    local number = tonumber(value)
    if number == nil
        or number ~= number
        or number <= -huge
        or number >= huge
    then
        return false, "invalid-appearance-value"
    end
    number = floor(ClampNumber(
        number,
        INPUT_HEIGHT_MIN,
        INPUT_HEIGHT_MAX,
        appearance.inputHeight
    ) + 0.5)
    appearance.inputHeight = number
    appearance.preset = "custom"
    local runtime = self.Appearance
    if runtime and type(runtime.PreviewInputHeight) == "function" then
        return runtime:PreviewInputHeight(number)
    end
    return true
end

function YChat:CommitInputHeight(value)
    local appearance = self:GetAppearance()
    if not appearance then return false, "appearance-db-unavailable" end
    local number = tonumber(value)
    if number == nil
        or number ~= number
        or number <= -huge
        or number >= huge
    then
        return false, "invalid-appearance-value"
    end
    appearance.inputHeight = floor(ClampNumber(
        number,
        INPUT_HEIGHT_MIN,
        INPUT_HEIGHT_MAX,
        appearance.inputHeight
    ) + 0.5)
    appearance.preset = "custom"
    return RequestRefresh("appearance-inputHeight"), true
end

function YChat:SetLayoutValue(key, value)
    local layout = self:GetLayout()
    if not layout then return false, "layout-db-unavailable" end
    local minimum
    local maximum
    if key == "mainWidth" then
        minimum = MAIN_WINDOW_MIN_WIDTH
        maximum = MAIN_WINDOW_MAX_WIDTH
    elseif key == "mainHeight" then
        minimum = MAIN_WINDOW_MIN_HEIGHT
        maximum = MAIN_WINDOW_MAX_HEIGHT
    else
        return false, "unknown-layout-key"
    end

    local number = tonumber(value)
    if number == nil
        or number ~= number
        or number <= -huge
        or number >= huge
    then
        return false, "invalid-layout-value"
    end
    number = floor(ClampNumber(number, minimum, maximum, minimum) + 0.5)
    if layout[key] == number then return true, false end
    layout[key] = number
    return RequestRefresh("layout-" .. key), true
end

YChat.MAIN_WINDOW_MIN_WIDTH = MAIN_WINDOW_MIN_WIDTH
YChat.MAIN_WINDOW_MAX_WIDTH = MAIN_WINDOW_MAX_WIDTH
YChat.MAIN_WINDOW_MIN_HEIGHT = MAIN_WINDOW_MIN_HEIGHT
YChat.MAIN_WINDOW_MAX_HEIGHT = MAIN_WINDOW_MAX_HEIGHT
YChat.BODY_FONT_MIN_SIZE = BODY_FONT_MIN_SIZE
YChat.BODY_FONT_MAX_SIZE = BODY_FONT_MAX_SIZE
YChat.BODY_LINE_SPACING_MIN = BODY_LINE_SPACING_MIN
YChat.BODY_LINE_SPACING_MAX = BODY_LINE_SPACING_MAX
YChat.TIMESTAMP_GAP_MIN = TIMESTAMP_GAP_MIN
YChat.TIMESTAMP_GAP_MAX = TIMESTAMP_GAP_MAX
YChat.TAB_MIN_WIDTH = TAB_MIN_WIDTH
YChat.TAB_MAX_WIDTH = TAB_MAX_WIDTH
YChat.TAB_MIN_SPACING = TAB_MIN_SPACING
YChat.TAB_MAX_SPACING = TAB_MAX_SPACING
YChat.TAB_LEFT_INSET_MIN = TAB_LEFT_INSET_MIN
YChat.TAB_LEFT_INSET_MAX = TAB_LEFT_INSET_MAX
YChat.INPUT_HEIGHT_MIN = INPUT_HEIGHT_MIN
YChat.INPUT_HEIGHT_MAX = INPUT_HEIGHT_MAX
YChat.FADE_DELAY_MIN = FADE_DELAY_MIN
YChat.FADE_DELAY_MAX = FADE_DELAY_MAX
YChat.HISTORY_RESTORE_LIMIT_MIN = HISTORY_RESTORE_LIMIT_MIN
YChat.HISTORY_RESTORE_LIMIT_MAX = HISTORY_RESTORE_LIMIT_MAX

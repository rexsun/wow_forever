local _, addonTable = ...
local YUI = _G.YUI
if not (YUI and YUI.FocusHelper) then
    YUI = addonTable
end
if not (YUI and YUI.FocusHelper and YUI.FocusHelper.RegisterSubFeature) then return end

local FocusHelper = YUI.FocusHelper
local SecurityAPI = (YUI.API and YUI.API.Security) or YUI.WOW_API or {}

local FocusAnnounce = {
    id = "focusAnnounce",
    order = 30,
}

FocusAnnounce.defaults = {
    focusAnnounceEnabled = false,
    focusAnnounceChannel = "GROUP",
    focusAnnounceTemplate = "我打断{markName}{mark}",
    focusAnnounceThrottle = 1,
}

local SETTINGS_WIDTH = 620
local FIELD_GAP = 16
local FIELD_WIDTH = math.floor((SETTINGS_WIDTH - FIELD_GAP) / 2)
local LABEL_WIDTH = 112
local LABEL_GAP = 10
local CONTROL_WIDTH = FIELD_WIDTH - LABEL_WIDTH - LABEL_GAP
local INPUT_WIDTH = 56

local VALID_CHANNELS = {
    SAY = true,
    YELL = true,
    GROUP = true,
}

local CHANNEL_OPTIONS = {
    { textKey = "settings.focus_announce_channel_group", value = "GROUP", fallback = "Party/Raid" },
    { textKey = "settings.focus_announce_channel_say", value = "SAY", fallback = "Say" },
    { textKey = "settings.focus_announce_channel_yell", value = "YELL", fallback = "Yell" },
}

local CHANNEL_COMMANDS = {
    RAID = "ra",
    PARTY = "p",
    SAY = "s",
    YELL = "y",
}

local MARK_NAMES = {
    [1] = "Star",
    [2] = "Circle",
    [3] = "Diamond",
    [4] = "Triangle",
    [5] = "Moon",
    [6] = "Square",
    [7] = "Cross",
    [8] = "Skull",
}

local featureActive = false
local runtimeActive = false

local function T(key, fallback)
    return FocusHelper:T(key, fallback)
end

local function Trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function SanitizeSingleLine(value)
    return Trim((value or ""):gsub("[%c]+", " "))
end

local function StripFocusNameTokens(value)
    value = SanitizeSingleLine(value)
    if value == "" then return "" end
    value = value:gsub("%s*{focusName}%s*", " ")
    value = value:gsub("%s*%%s%s*", " ")
    return Trim(value:gsub("%s%s+", " "))
end

local function SafeNumberValue(value)
    local safeNumber = SecurityAPI.SafeNumber or SecurityAPI.SafeNumberValue
    if safeNumber then
        return safeNumber(value)
    end
    if value == nil then return nil end
    if SecurityAPI.IsSecretValue and SecurityAPI.IsSecretValue(value) then
        return nil
    end

    local ok, numberValue = pcall(tonumber, value)
    if ok and numberValue ~= nil and not (SecurityAPI.IsSecretValue and SecurityAPI.IsSecretValue(numberValue)) then
        return numberValue
    end
    return nil
end

local function ClampMarker(value)
    value = SafeNumberValue(value)
    if not value then return 1 end
    value = math.floor(value + 0.5)
    if value < 1 then return 1 end
    if value > 8 then return 8 end
    return value
end

local function ClampThrottle(value)
    value = SafeNumberValue(value)
    if value == nil then value = FocusAnnounce.defaults.focusAnnounceThrottle end
    if value < 0 then return 0 end
    if value > 10 then return 10 end
    return value
end

local function NormalizeChannel(value)
    value = type(value) == "string" and value:upper() or nil
    if VALID_CHANNELS[value] then return value end
    return FocusAnnounce.defaults.focusAnnounceChannel
end

local function ResolveMacroCommand(db)
    local channel = NormalizeChannel(db and db.focusAnnounceChannel)
    if channel == "GROUP" then
        if IsInRaid and IsInRaid() then return CHANNEL_COMMANDS.RAID end
        if IsInGroup and IsInGroup() then return CHANNEL_COMMANDS.PARTY end
        return nil
    end
    return CHANNEL_COMMANDS[channel]
end

local function GetMarkerIndex(db)
    return ClampMarker(db and db.focusMarkerIndex)
end

local function BuildMessage(db)
    local template = StripFocusNameTokens(db and db.focusAnnounceTemplate)
    if template == "" then
        template = FocusAnnounce.defaults.focusAnnounceTemplate
    end

    local marker = GetMarkerIndex(db)
    local markName = T("raid_marker." .. marker, MARK_NAMES[marker] or MARK_NAMES[1])
    local markTag = "{rt" .. tostring(marker) .. "}"

    local message = template
    message = message:gsub("{markName}", function() return markName end)
    message = message:gsub("{mark}", function() return markTag end)
    return SanitizeSingleLine(message)
end

local function BuildMacroLine(db)
    if not featureActive or not runtimeActive or not (db and db.focusAnnounceEnabled == true) then return nil end
    local command = ResolveMacroCommand(db)
    if not command then return nil end
    local message = BuildMessage(db)
    if message == "" then return nil end
    return "/" .. command .. " " .. message
end

function FocusAnnounce:NormalizeDB(db)
    if type(db) ~= "table" then return db end
    db.focusAnnounceEnabled = db.focusAnnounceEnabled == true
    db.focusAnnounceChannel = NormalizeChannel(db.focusAnnounceChannel)
    db.focusAnnounceTemplate = StripFocusNameTokens(db.focusAnnounceTemplate)
    if db.focusAnnounceTemplate == "" then
        db.focusAnnounceTemplate = FocusAnnounce.defaults.focusAnnounceTemplate
    end
    db.focusAnnounceThrottle = ClampThrottle(db.focusAnnounceThrottle)
    return db
end

function FocusAnnounce:RefreshRuntime(db)
    db = self:NormalizeDB(db or FocusHelper:GetDB())
    runtimeActive = featureActive and db.focusAnnounceEnabled == true
end

function FocusAnnounce:BuildMacroLine(db)
    db = self:NormalizeDB(db or FocusHelper:GetDB())
    return BuildMacroLine(db)
end

function FocusHelper:GetFocusAnnounceMacroLine(db)
    return FocusAnnounce:BuildMacroLine(db)
end

function FocusAnnounce:OnFeatureToggle(enabled, db)
    featureActive = enabled == true
    self:RefreshRuntime(db)
    if featureActive and FocusHelper.RefreshSubFeatures then
        FocusHelper:RefreshSubFeatures(db)
    end
end

local function RefreshSubFeatures(db)
    FocusAnnounce:RefreshRuntime(db)
    if FocusHelper.RefreshSubFeatures then
        FocusHelper:RefreshSubFeatures(db)
    end
end

local function BuildChannelOptions()
    local options = {}
    for _, item in ipairs(CHANNEL_OPTIONS) do
        options[#options + 1] = {
            text = T(item.textKey, item.fallback),
            value = item.value,
        }
    end
    return options
end

local function AddAlignedFieldGroup(options, label, fields, layout)
    layout = type(layout) == "table" and layout or {}
    if layout.hideDivider ~= true then
        options[#options + 1] = { type = "divider", label = label, alignLeft = true, width = SETTINGS_WIDTH }
    end
    options[#options + 1] = {
        type = "custom",
        retainedFields = fields,
        width = SETTINGS_WIDTH,
        render = function(parent, x, y, width)
            local Settings = YUI.Settings
            if not (Settings and Settings.RenderAlignedFields) then
                return SETTINGS_WIDTH, 1
            end

            local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                x = x,
                y = y,
                width = math.min(width or SETTINGS_WIDTH, SETTINGS_WIDTH),
                columns = 2,
                labelPosition = layout.labelPosition or "top",
                columnGap = FIELD_GAP,
                labelWidth = LABEL_WIDTH,
                labelGap = LABEL_GAP,
                bodyWidth = CONTROL_WIDTH,
                valueWidth = INPUT_WIDTH,
                valueGap = LABEL_GAP,
                rowHeight = 32,
                rowGap = 10,
                fields = fields,
            })
            return gridWidth, gridHeight
        end,
    }
end

function FocusAnnounce:BuildOptions(db)
    db = self:NormalizeDB(db or FocusHelper:GetDB())

    local options = {}
    AddAlignedFieldGroup(options, T("settings.focus_announce", "Focus Announce"), {
        {
            type = "checkbox",
            label = T("settings.focus_announce_enable", "Announce on focus"),
            settingsToggle = "focusAnnounce",
            searchKey = "settings.focus_announce_enable",
            get = function() return db.focusAnnounceEnabled == true end,
            set = function(value)
                db.focusAnnounceEnabled = value == true
                RefreshSubFeatures(db)
            end,
        },
        {
            type = "dropdown",
            label = T("settings.focus_announce_channel", "Channel"),
            options = BuildChannelOptions,
            default = FocusAnnounce.defaults.focusAnnounceChannel,
            get = function() return db.focusAnnounceChannel end,
            set = function(value)
                db.focusAnnounceChannel = NormalizeChannel(value)
                RefreshSubFeatures(db)
            end,
        },
    }, { hideDivider = true })

    options[#options + 1] = {
            type = "editbox",
            label = T("settings.focus_announce_template", "Template"),
            rowWidth = SETTINGS_WIDTH,
            labelWidth = LABEL_WIDTH,
            controlWidth = SETTINGS_WIDTH - LABEL_WIDTH - LABEL_GAP,
            get = function() return db.focusAnnounceTemplate end,
            set = function(value)
                db.focusAnnounceTemplate = StripFocusNameTokens(value)
                if db.focusAnnounceTemplate == "" then
                    db.focusAnnounceTemplate = FocusAnnounce.defaults.focusAnnounceTemplate
                end
                RefreshSubFeatures(db)
            end,
        }
    options[#options + 1] = {
            type = "text",
            label = T("settings.focus_announce_tokens", "Tokens: {markName}, {mark}. Announcements use the reserved YUIQFocus macro; channel and template changes update that same macro instead of creating new macros."),
            width = SETTINGS_WIDTH,
            colorKey = "color.text.secondary",
            justify = "LEFT",
            wrap = true,
        }
    return options
end

FocusHelper:RegisterSubFeature(FocusAnnounce)

local ADDON_NAME, addonTable = ...
local YUI = _G.YUI
if not (YUI and YUI.Components) then
    YUI = addonTable
end
if not (YUI and YUI.Components) then return end

local Components = YUI.Components
local Assets = YUI.Assets
local GUI2 = YUI.GUI2
local UnitAPI = (YUI.API and YUI.API.Unit) or YUI.WOW_API or {}
local SpellAPI = (YUI.API and YUI.API.Spell) or YUI.WOW_API or {}
local TalentAPI = (YUI.API and YUI.API.Talent) or YUI.WOW_API or {}
local SecurityAPI = (YUI.API and YUI.API.Security) or YUI.WOW_API or {}
local L = YUI.Locale and YUI.Locale:Get("FocusHelper") or nil
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local FEATURE_KEY = "FocusHelper"
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"
local CONFIG_KEY = "FocusHelper_Config"
local LAYOUT_ID = "yui.component.focusHelper.interruptBar"
local MODULE_ID = "component:" .. FEATURE_KEY
local DEFAULT_SETTINGS_TAB = "interrupt"
local FALLBACK_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local FALLBACK_ICON = "Interface\\Icons\\Ability_Kick"

local MIN_WIDTH = 140
local MAX_WIDTH = 520
local MIN_HEIGHT = 12
local MAX_HEIGHT = 46
local DEFAULT_WIDTH = 350
local DEFAULT_HEIGHT = 36
local FIELD_GAP = 16
local SECTION_WIDTH = 620
local SETTINGS_TAB_WIDTH = SECTION_WIDTH
local FIELD_WIDTH = math.floor((SECTION_WIDTH - FIELD_GAP) / 2)
local LABEL_WIDTH = 112
local LABEL_GAP = 10
local CONTROL_WIDTH = FIELD_WIDTH - LABEL_WIDTH - LABEL_GAP
local INPUT_WIDTH = 56

local function ComponentPath(componentId, path)
    if Assets and Assets.Component then
        return Assets:Component(componentId, path)
    end
    return "Interface\\AddOns\\YUI\\Components\\" .. componentId .. "\\Media\\" .. path
end

local DEFAULT_COOLDOWN_COLOR = { 1, 0.278, 0.286, 1 }
local DEFAULT_READY_COLOR = { 1, 0.961, 0.071, 1 }
local DEFAULT_MARKER_COLOR = { 0.1, 1, 0.2, 1 }
local DEFAULT_TEXT_FONT = "default"
local DEFAULT_TIME_FONT_SIZE = 24
local DEFAULT_NAME_FONT_SIZE = 16
local DEFAULT_TEXT_OUTLINE_MODE = "outlineShadow"
local DEFAULT_CUSTOM_SOUND_PATH = ComponentPath(FEATURE_KEY, "焦点打断.ogg")
local LEGACY_DEFAULT_SOUND_PATHS = {
    ["interface\\addons\\yui\\media\\bundles\\voice-wyjj\\焦点打断.ogg"] = true,
    ["interface\\addons\\yui_novatoolbox\\coreembed\\media\\bundles\\voice-wyjj\\焦点打断.ogg"] = true,
    ["interface\\addons\\yui\\_novatoolbox\\coreembed\\media\\bundles\\voice-wyjj\\焦点打断.ogg"] = true,
}
local PREVIEW_TOTAL_SECONDS = 3.2
local PREVIEW_MARKER_ELAPSED = 2.15
local INTERRUPTIBILITY_GRACE_SECONDS = 0.12
local ALERT_DEDUP_SECONDS = 1
local CD_RUNTIME = {
    readinessRefresh = 0.1,
    readinessAt = 0,
    visualReadyValues = {},
    alertProbeInterval = 0.08,
    alertProbeGeneration = 0,
    alertProbeState = "unknown",
    alertProbeReason = "none",
    alertProbeSource = "none",
    alertProbeSpellID = nil,
    alertProbeEntry = nil,
    alertProbeCastKey = nil,
    alertProbeLastPollAt = 0,
    alertProbePreviousState = nil,
    alertProbeActive = false,
    alertSteelState = "unknown",
    alertSteelSource = "none",
    alertSteelReason = "none",
    alertSteelCastKey = nil,
    learnedCooldowns = {},
    learnMaxSeconds = 180,
    learnPollSeconds = 0.25,
    learnPendingSpellID = nil,
    learnPendingStartAt = nil,
    learnPendingGeneration = 0,
    learnPendingSawCooldown = false,
    learnTicker = nil,
}

local FocusHelper = YUI.FocusHelper or {}
YUI.FocusHelper = FocusHelper
FocusHelper.FEATURE_KEY = FEATURE_KEY
FocusHelper.PRODUCT_ID = PRODUCT_ID
FocusHelper.CONFIG_KEY = CONFIG_KEY
FocusHelper.L = L
FocusHelper.subFeatures = FocusHelper.subFeatures or {}
FocusHelper.subFeatureOrder = FocusHelper.subFeatureOrder or {}
FocusHelper.featureActive = FocusHelper.featureActive == true

local defaults = {
    interruptEnabled = true,
    width = DEFAULT_WIDTH,
    height = DEFAULT_HEIGHT,
    barTexture = " |cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r |CFFBA55D3G1|r",
    cooldownColor = DEFAULT_COOLDOWN_COLOR,
    readyColor = DEFAULT_READY_COLOR,
    markerColor = DEFAULT_MARKER_COLOR,
    uninterruptibleColor = { 0.608, 0.627, 0.62, 1 },
    textFont = DEFAULT_TEXT_FONT,
    timeFontSize = DEFAULT_TIME_FONT_SIZE,
    spellNameFontSize = DEFAULT_NAME_FONT_SIZE,
    targetNameFontSize = DEFAULT_NAME_FONT_SIZE,
    textOutlineMode = DEFAULT_TEXT_OUTLINE_MODE,
    soundMode = "custom",
    lsmSound = "None",
    customSoundPath = DEFAULT_CUSTOM_SOUND_PATH,
    soundChannel = "Master",
    unavailableDisplayMode = "hide",
    hideCooldownThreshold = 2.5,
}
FocusHelper.defaults = defaults

local activeSettingsTab = DEFAULT_SETTINGS_TAB

local SETTINGS_TABS = {
    { id = "interrupt", labelKey = "settings.tab_interrupt", fallback = "Focus Cast Bar" },
    { id = "quickFocus", labelKey = "settings.tab_quick_focus", fallback = "Quick Focus" },
    { id = "focusMarker", labelKey = "settings.tab_focus_marker", fallback = "Focus Marker" },
    { id = "focusAnnounce", labelKey = "settings.tab_focus_announce", fallback = "Focus Announce" },
}

local SOUND_CHANNELS = {
    { key = "channel.master", value = "Master", fallback = "Master" },
    { key = "channel.sfx", value = "SFX", fallback = "SFX" },
    { key = "channel.music", value = "Music", fallback = "Music" },
    { key = "channel.ambience", value = "Ambience", fallback = "Ambience" },
    { key = "channel.dialog", value = "Dialog", fallback = "Dialog" },
}

local VALID_SOUND_CHANNELS = {
    Master = true,
    SFX = true,
    Music = true,
    Ambience = true,
    Dialog = true,
}

local SOUND_MODE_OPTIONS = {
    { textKey = "settings.sound_mode_lsm", value = "lsm", fallback = "Sound library" },
    { textKey = "settings.sound_mode_custom", value = "custom", fallback = "Custom path" },
}

local VALID_TEXT_OUTLINE_MODES = {
    none = true,
    outline = true,
    thick = true,
    shadow = true,
    outlineShadow = true,
}

local INTERRUPT_SPELLS = {
    WARRIOR = {
        retailSpells = {
            { spellID = 6552 },
        },
        legacySpells = {
            { spellID = 6552 },
        },
    },
    PALADIN = {
        retailSpells = {
            { spellID = 96231 },
            { spellID = 31935 },
        },
        legacySpells = {
            { spellID = 31935 },
            { spellID = 96231 },
        },
    },
    HUNTER = {
        retailSpells = {
            { spellID = 147362 },
            { spellID = 187707 },
        },
        legacySpells = {
            { spellID = 187707 },
            { spellID = 147362 },
        },
    },
    ROGUE = {
        retailSpells = {
            { spellID = 1766 },
        },
        legacySpells = {
            { spellID = 1766 },
        },
    },
    PRIEST = {
        retailSpells = {
            { spellID = 15487 },
        },
        legacySpells = {
            { spellID = 15487 },
        },
    },
    DEATHKNIGHT = {
        retailSpells = {
            { spellID = 47528 },
        },
        legacySpells = {
            { spellID = 47528 },
        },
    },
    SHAMAN = {
        retailSpells = {
            { spellID = 57994 },
        },
        legacySpells = {
            { spellID = 57994 },
            { spellID = 49231 },
            { spellID = 49230 },
            { spellID = 25454 },
            { spellID = 10414 },
            { spellID = 10413 },
            { spellID = 10412 },
            { spellID = 8046 },
            { spellID = 8045 },
            { spellID = 8044 },
            { spellID = 8042 },
        },
    },
    MAGE = {
        retailSpells = {
            { spellID = 2139 },
        },
        legacySpells = {
            { spellID = 2139 },
        },
    },
    WARLOCK = {
        retailSpells = {
            { spellID = 89766 },
            { spellID = 119910 },
            { spellID = 132409 },
        },
        legacySpells = {
            { spellID = 19647 },
            { spellID = 89766 },
            { spellID = 132409 },
        },
    },
    MONK = {
        retailSpells = {
            { spellID = 116705 },
        },
        legacySpells = {
            { spellID = 116705 },
        },
    },
    DRUID = {
        retailSpells = {
            { spellID = 38675 },
            { spellID = 78675 },
            { spellID = 106839 },
        },
        legacySpells = {
            { spellID = 38675 },
            { spellID = 78675 },
            { spellID = 106839 },
        },
    },
    DEMONHUNTER = {
        retailSpells = {
            { spellID = 183752 },
        },
        legacySpells = {
            { spellID = 183752 },
        },
    },
    EVOKER = {
        retailSpells = {
            { spellID = 351338 },
        },
        legacySpells = {
            { spellID = 351338 },
        },
    },
}

-- Forever combines the existing candidates; the spellbook still decides which are usable.
-- Build once, outside the cast/cooldown event paths.
if YUI.IsForever then
    for _, classData in pairs(INTERRUPT_SPELLS) do
        local entries, seen = {}, {}
        for _, source in ipairs({ classData.retailSpells, classData.legacySpells }) do
            for _, entry in ipairs(source) do
                if not seen[entry.spellID] then
                    entries[#entries + 1] = entry
                    seen[entry.spellID] = true
                end
            end
        end
        classData.foreverSpells = entries
    end
end

local Widget = {}
local CastState = {}
local EventOwner = {}
local ProfileOwner = {}

local featureActive = false
local runtimeActive = false
local layoutPreviewActive = false
local layoutRegistered = false
local profileCallbacksRegistered = false
local activeDB
local currentInterrupt
local currentInterrupts = {}
local currentInterruptsVersion = 0
local interruptSpellIDs = {}
local settingsPreviewActive = false
local settingsRefreshQueued = false
local focusCastStartedAt = 0
local focusCastDisplayType
local lastAlertPlayedAt = 0
local lastAlertFocusGUID

local PREVIEW_CLASS_COLORS = {
    { 0.78, 0.61, 0.43, 1 },
    { 1.00, 0.49, 0.04, 1 },
    { 0.67, 0.83, 0.45, 1 },
    { 0.41, 0.80, 0.94, 1 },
    { 0.96, 0.55, 0.73, 1 },
    { 1.00, 0.96, 0.41, 1 },
    { 0.88, 0.88, 0.88, 1 },
    { 0.58, 0.51, 0.79, 1 },
    { 0.00, 0.44, 0.87, 1 },
    { 0.00, 1.00, 0.60, 1 },
    { 0.64, 0.19, 0.79, 1 },
    { 0.20, 0.58, 0.50, 1 },
    { 0.85, 0.33, 0.30, 1 },
}

local IsInterruptReady

local function T(key, fallback)
    return (L and L[key]) or fallback or key
end

local function CopyDefaultValue(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}
    for key, item in pairs(value) do
        result[key] = CopyDefaultValue(item)
    end
    return result
end

local function MergeDefaults(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then
        return
    end

    for key, value in pairs(source) do
        if target[key] == nil then
            target[key] = CopyDefaultValue(value)
        elseif type(target[key]) == "table" and type(value) == "table" then
            MergeDefaults(target[key], value)
        end
    end
end

local function SortSubFeatures(a, b)
    local left = FocusHelper.subFeatures[a]
    local right = FocusHelper.subFeatures[b]
    local leftOrder = left and left.order or 1000
    local rightOrder = right and right.order or 1000
    if leftOrder == rightOrder then
        return tostring(a) < tostring(b)
    end
    return leftOrder < rightOrder
end

local function FindSettingsTab(id)
    for _, tab in ipairs(SETTINGS_TABS) do
        if tab.id == id then
            return tab
        end
    end
    return nil
end

local function NormalizeSettingsTab(id)
    if FindSettingsTab(id) then
        return id
    end
    return DEFAULT_SETTINGS_TAB
end

function FocusHelper:T(key, fallback)
    return T(key, fallback)
end

function FocusHelper:IsEnabled()
    return self.featureActive == true
end

function FocusHelper:RegisterSubFeature(subFeature)
    if type(subFeature) ~= "table" or type(subFeature.id) ~= "string" or subFeature.id == "" then
        return false
    end

    local id = subFeature.id
    if not self.subFeatures[id] then
        self.subFeatureOrder[#self.subFeatureOrder + 1] = id
    end
    self.subFeatures[id] = subFeature
    table.sort(self.subFeatureOrder, SortSubFeatures)
    MergeDefaults(defaults, subFeature.defaults)

    if self.featureActive and subFeature.OnFeatureToggle and self.GetDB then
        subFeature:OnFeatureToggle(true, self:GetDB())
    end
    return true
end

function FocusHelper:RefreshSubFeatures(db)
    db = db or (self.GetDB and self:GetDB()) or defaults
    for _, id in ipairs(self.subFeatureOrder) do
        local subFeature = self.subFeatures[id]
        if subFeature and subFeature.RefreshRuntime then
            subFeature:RefreshRuntime(db)
        end
    end
end

function FocusHelper:ToggleSubFeatures(enabled, db)
    db = db or (self.GetDB and self:GetDB()) or defaults
    for _, id in ipairs(self.subFeatureOrder) do
        local subFeature = self.subFeatures[id]
        if subFeature and subFeature.OnFeatureToggle then
            subFeature:OnFeatureToggle(enabled == true, db)
        end
    end
end

local function ClampNumber(value, minValue, maxValue, fallback)
    value = tonumber(value)
    if value == nil then value = fallback end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function ClampUnit(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback or 1 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function NormalizeColor(value, fallback)
    fallback = fallback or { 1, 1, 1, 1 }
    local source = type(value) == "table" and value or fallback
    return {
        ClampUnit(source[1] or source.r, fallback[1] or fallback.r or 1),
        ClampUnit(source[2] or source.g, fallback[2] or fallback.g or 1),
        ClampUnit(source[3] or source.b, fallback[3] or fallback.b or 1),
        ClampUnit(source[4] or source.a, fallback[4] or fallback.a or 1),
    }
end

local function Trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function Round(value)
    value = tonumber(value) or 0
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

local function GetNow()
    return GetTime and GetTime() or 0
end

local function IsSecretValue(value)
    return SecurityAPI.IsSecretValue and SecurityAPI.IsSecretValue(value) == true
end

local function SafeRawValue(value)
    if IsSecretValue(value) or value == nil then
        return nil
    end
    return value
end

local function RawDisplayValue(value)
    if value == nil then
        return nil
    end
    return value
end

local function FirstRawDisplayValue(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if value ~= nil then
            return value
        end
    end
    return nil
end

local function SafeNumberValue(value)
    if IsSecretValue(value) or value == nil then
        return nil
    end

    local ok, numberValue = pcall(tonumber, value)
    if ok and not IsSecretValue(numberValue) and numberValue ~= nil then
        return numberValue
    end
    return nil
end

local function SafeBooleanValue(value, fallback)
    if IsSecretValue(value) or value == nil then
        return fallback
    end
    if value == false or value == 0 then
        return false
    end
    if value == true or value == 1 then
        return true
    end
    return value and true or false
end

function CD_RUNTIME:InvalidateReadiness()
    self.readinessAt = 0
    self.readinessKey = nil
    self.readinessReady = nil
    self.readinessEntry = nil
    self.readinessRemaining = nil
    self.readinessReason = nil
    self.readinessSource = nil
    self.readinessState = nil
    self.readinessVisualEntry = nil
    self.readinessVisualState = nil
    self.readinessVisualReadyValues = nil
    if self.visualReadyValues then
        for index = #self.visualReadyValues, 1, -1 do
            self.visualReadyValues[index] = nil
        end
    end
end

local function SafeTextValue(value)
    value = SafeRawValue(value)
    if type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

local function HasDisplayText(value)
    if value == nil then
        return false
    end
    if IsSecretValue(value) then
        return true
    end
    if type(value) == "string" then
        return value ~= ""
    end
    return true
end

local function ResetWidgetCachedDisplay()
    Widget.lastRemainingText = nil
    Widget.lastSpellText = nil
    Widget.lastTargetText = nil
    Widget.lastLabelsVisible = nil
    Widget.lastTimeFontSize = nil
    Widget.lastSpellNameFontSize = nil
    Widget.lastTargetNameFontSize = nil
    Widget.lastTextFont = nil
    Widget.lastTextFontPath = nil
    Widget.lastTextOutlineMode = nil
    Widget.lastTargetColor = nil
    Widget.lastAlpha = nil
end

local function SetCachedRemainingText(frame, text)
    if not (frame and frame.SetRemainingText) then return end
    if text == nil then text = "" end
    if IsSecretValue(text) or frame.gui2UsingNativeCountdown == true then
        Widget.lastRemainingText = nil
        frame:SetRemainingText(text)
        return
    end
    if Widget.lastRemainingText == text then return end
    Widget.lastRemainingText = text
    frame:SetRemainingText(text)
end

local function SetCachedAlpha(frame, alpha)
    if not (frame and frame.SetAlpha) then return end
    if Widget.lastAlpha == alpha then return end
    Widget.lastAlpha = alpha
    frame:SetAlpha(alpha)
end

function CD_RUNTIME:FirstDisplayTextValue(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if HasDisplayText(value) then
            return value
        end
    end
    return nil
end

local function SafeCastKeyPart(value, fallback)
    value = SafeRawValue(value)
    if value == nil then
        return fallback or ""
    end

    local ok, text = pcall(tostring, value)
    if ok and not IsSecretValue(text) then
        return text
    end
    return fallback or ""
end

local function MigrateLegacyEQoLQuickFocus(db)
    if type(db) ~= "table" or db._migratedEQoLShiftFocus == true then
        return
    end

    local eqolDB
    if Components and Components.EnsureConfig then
        eqolDB = Components:EnsureConfig("EQoLAdapter_Config", { enableShiftFocus = false }, PRODUCT_ID)
    end
    if type(eqolDB) == "table" and eqolDB.enableShiftFocus == true then
        db.quickFocusEnabled = true
        db.quickFocusModifier = "SHIFT"
        db.quickFocusClearBlank = true
        eqolDB.enableShiftFocus = false
    end
    db._migratedEQoLShiftFocus = true
end

local function MigrateLegacyDefaultSoundPath(path)
    if type(path) ~= "string" then
        return path
    end
    local normalized = string.lower(Trim(path):gsub("/", "\\"):gsub("\\+", "\\"))
    if LEGACY_DEFAULT_SOUND_PATHS[normalized] then
        return DEFAULT_CUSTOM_SOUND_PATH
    end
    return path
end

local function NormalizeDB(db)
    if type(db) ~= "table" then db = defaults end
    MigrateLegacyEQoLQuickFocus(db)
    db.interruptEnabled = db.interruptEnabled ~= false
    db.preview = nil
    db.width = ClampNumber(db.width, MIN_WIDTH, MAX_WIDTH, DEFAULT_WIDTH)
    db.height = ClampNumber(db.height, MIN_HEIGHT, MAX_HEIGHT, DEFAULT_HEIGHT)
    if type(db.barTexture) ~= "string" or db.barTexture == "" then
        db.barTexture = defaults.barTexture
    end
    db.cooldownColor = NormalizeColor(db.cooldownColor, DEFAULT_COOLDOWN_COLOR)
    db.readyColor = NormalizeColor(db.readyColor, DEFAULT_READY_COLOR)
    db.markerColor = NormalizeColor(db.markerColor, DEFAULT_MARKER_COLOR)
    db.uninterruptibleColor = NormalizeColor(db.uninterruptibleColor, defaults.uninterruptibleColor)
    if type(db.textFont) ~= "string" or db.textFont == "" then
        db.textFont = defaults.textFont
    end
    db.timeFontSize = ClampNumber(db.timeFontSize, 8, 24, DEFAULT_TIME_FONT_SIZE)
    db.spellNameFontSize = ClampNumber(db.spellNameFontSize, 8, 24, DEFAULT_NAME_FONT_SIZE)
    db.targetNameFontSize = ClampNumber(db.targetNameFontSize, 8, 24, DEFAULT_NAME_FONT_SIZE)
    if db.textOutlineMode == "outline_shadow" then
        db.textOutlineMode = "outlineShadow"
    end
    if not VALID_TEXT_OUTLINE_MODES[db.textOutlineMode] then
        db.textOutlineMode = defaults.textOutlineMode
    end
    if db.unavailableDisplayMode ~= "hide" and db.unavailableDisplayMode ~= "show" then
        db.unavailableDisplayMode = defaults.unavailableDisplayMode
    end
    db.hideCooldownThreshold = ClampNumber(db.hideCooldownThreshold, 0, 10, defaults.hideCooldownThreshold)
    if db.soundMode ~= "custom" then
        db.soundMode = "lsm"
    end
    if type(db.lsmSound) ~= "string" or db.lsmSound == "" then
        db.lsmSound = defaults.lsmSound
    end
    if type(db.customSoundPath) ~= "string" or Trim(db.customSoundPath) == "" then
        db.customSoundPath = defaults.customSoundPath
    else
        db.customSoundPath = MigrateLegacyDefaultSoundPath(db.customSoundPath)
    end
    if not VALID_SOUND_CHANNELS[db.soundChannel] then
        db.soundChannel = defaults.soundChannel
    end
    for _, id in ipairs(FocusHelper.subFeatureOrder) do
        local subFeature = FocusHelper.subFeatures[id]
        if subFeature and subFeature.NormalizeDB then
            subFeature:NormalizeDB(db)
        end
    end
    return db
end

local function GetDB()
    local db = Components.EnsureConfig and Components:EnsureConfig(CONFIG_KEY, defaults, PRODUCT_ID) or defaults
    activeDB = NormalizeDB(db)
    return activeDB
end

function FocusHelper:GetDB()
    return GetDB()
end

local function ToLayoutPlacement(point, relative, relativePoint, x, y)
    return {
        version = 1,
        anchor = {
            point = point or "CENTER",
            relative = relative or "UIParent",
            relativePoint = relativePoint or point or "CENTER",
        },
        offset = { x = Round(x), y = Round(y) },
    }
end

local function GetDefaultPlacement()
    return ToLayoutPlacement("CENTER", "UIParent", "CENTER", 0, 325)
end

local function ApplyDefaultPoint(frame)
    if not frame then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 325)
end

local function IsLayoutEditing()
    return YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing()
end

local function OpenFocusHelperSettings()
    if YUI.Settings and YUI.Settings.OpenComponentFeature then
        YUI.Settings:OpenComponentFeature(FEATURE_KEY)
        return true
    end
    return false
end

local function GetStatusBarTexture(db)
    db = db or activeDB or GetDB()
    if LSM and LSM.Fetch then
        local texture = LSM:Fetch("statusbar", db.barTexture, true)
        if texture then
            return texture
        end
        texture = LSM:Fetch("statusbar", defaults.barTexture, true)
        if texture then
            return texture
        end
    end
    return FALLBACK_TEXTURE
end

local function GetDefaultTextFontPath()
    if GUI2 and GUI2.GetFont then
        local path = GUI2:GetFont("font.family.body")
        if type(path) == "string" and path ~= "" then
            return path
        end
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

local function ResolveTextFontPath(fontName)
    if fontName ~= DEFAULT_TEXT_FONT and LSM and LSM.Fetch then
        local path = LSM:Fetch("font", fontName, true)
        if type(path) == "string" and path ~= "" then
            return path
        end
    end
    return nil
end

local function GetSpellTexture(spellID, fallback)
    spellID = SafeRawValue(spellID)
    if spellID and SpellAPI.GetTexture then
        local texture = SpellAPI.GetTexture(spellID)
        texture = SafeRawValue(texture)
        if texture then return texture end
    end
    return fallback or FALLBACK_ICON
end

local function RandomPreviewClassColor()
    local count = #PREVIEW_CLASS_COLORS
    if count <= 0 then return { 1, 1, 1, 1 } end
    return PREVIEW_CLASS_COLORS[math.random(count)]
end

local function GetCurrentBarColor(db)
    db = db or activeDB or GetDB()
    if CastState.preview then
        if (SafeNumberValue(CastState.elapsedSeconds) or 0) >= PREVIEW_MARKER_ELAPSED then
            return db.readyColor, "preview-ready", true, "preview", "preview"
        end
        return db.cooldownColor, "preview-cooldown", false, "preview", "preview"
    end
    if CastState.notInterruptibleKnown == true and CastState.notInterruptible == true then
        return db.uninterruptibleColor, "steel", false, "not-interruptible", "event"
    end
    local ready, _, _, reason, source = IsInterruptReady and IsInterruptReady()
    if ready == true then
        return db.readyColor, "ready", true, reason or "ready", source
    end
    if reason == "cooldown" or reason == "no-spell" or reason == "pet-unavailable" or reason == "unknown" or reason == "no-duration-object" or reason == "no-duration-state" or reason == "no-iszero" or reason == "no-remaining" then
        return db.cooldownColor, "cooldown", false, reason, source
    end
    return db.cooldownColor, "cooldown-unknown", ready, reason or "unknown", source
end

local function ApplyCastBarColor()
    local frame = Widget.frame
    if not (frame and frame.SetBarColor) then return end
    local db = activeDB or GetDB()
    local color, colorState = GetCurrentBarColor(db)
    Widget.currentBarColor = color
    frame:SetBarColor(color)
    local visualReadyValues = CD_RUNTIME.readinessVisualReadyValues
    local applied = false
    if not CastState.preview
        and CastState.active == true
        and visualReadyValues ~= nil
        and frame.SetBarColorFromCooldownState then
        applied = frame:SetBarColorFromCooldownState(visualReadyValues, db.readyColor, db.cooldownColor, CastState.visualNotInterruptibleRaw, db.uninterruptibleColor)
    end
    local allowVisualCondition = not applied
        and not CastState.preview
        and CastState.active == true
        and colorState ~= "steel"
        and colorState ~= "cooldown"
        and frame.SetBarColorFromBoolean
    if allowVisualCondition then
        applied = frame:SetBarColorFromBoolean(CastState.visualNotInterruptibleRaw, db.uninterruptibleColor, color)
        if not applied and frame.ClearBarColorCondition then
            frame:ClearBarColorCondition()
        end
    elseif not applied and frame.ClearBarColorCondition then
        frame:ClearBarColorCondition()
    end
end

local function ApplyCastBarTextAppearance(applySizes)
    local frame = Widget.frame
    if not frame then return end
    local db = activeDB or GetDB()
    if applySizes then
        if frame.SetTextFontPath and Widget.lastTextFont ~= db.textFont then
            local fontPath = ResolveTextFontPath(db.textFont)
            Widget.lastTextFont = db.textFont
            Widget.lastTextFontPath = fontPath
            frame:SetTextFontPath(fontPath)
        end
        if frame.SetTimeTextSize and Widget.lastTimeFontSize ~= db.timeFontSize then
            Widget.lastTimeFontSize = db.timeFontSize
            frame:SetTimeTextSize(db.timeFontSize)
        end
        if frame.SetSpellNameTextSize and Widget.lastSpellNameFontSize ~= db.spellNameFontSize then
            Widget.lastSpellNameFontSize = db.spellNameFontSize
            frame:SetSpellNameTextSize(db.spellNameFontSize)
        end
        if frame.SetTargetNameTextSize and Widget.lastTargetNameFontSize ~= db.targetNameFontSize then
            Widget.lastTargetNameFontSize = db.targetNameFontSize
            frame:SetTargetNameTextSize(db.targetNameFontSize)
        end
        if frame.SetTextOutlineMode and Widget.lastTextOutlineMode ~= db.textOutlineMode then
            Widget.lastTextOutlineMode = db.textOutlineMode
            frame:SetTextOutlineMode(db.textOutlineMode)
        end
    end
    local spellText
    local targetText
    local targetColor
    if CastState.preview then
        spellText = CastState.name or T("preview.spell_name", "Focus Cast")
        targetText = CastState.targetName or T("preview.target_name", "Target Name")
        targetColor = CastState.targetColor or PREVIEW_CLASS_COLORS[1]
    else
        spellText = RawDisplayValue(CastState.name)
        targetText = RawDisplayValue(CastState.targetName)
        targetColor = CastState.targetColor or "color.text.primary"
    end
    local hasSpellText = HasDisplayText(spellText)
    local hasTargetText = HasDisplayText(targetText)
    if spellText == nil then spellText = "" end
    if targetText == nil then targetText = "" end
    if frame.SetSpellNameText then
        if IsSecretValue(spellText) then
            Widget.lastSpellText = nil
            frame:SetSpellNameText(spellText)
        elseif Widget.lastSpellText ~= spellText then
            Widget.lastSpellText = spellText
            frame:SetSpellNameText(spellText)
        end
    end
    if frame.SetTargetNameText then
        if IsSecretValue(targetText) then
            Widget.lastTargetText = nil
            frame:SetTargetNameText(targetText)
        elseif Widget.lastTargetText ~= targetText then
            Widget.lastTargetText = targetText
            frame:SetTargetNameText(targetText)
        end
    end
    if frame.SetTargetNameColor then
        if type(targetColor) == "table" and not IsSecretValue(targetColor) then
            if Widget.lastTargetColor ~= targetColor then
                Widget.lastTargetColor = targetColor
                frame:SetTargetNameColor(targetColor)
            end
        else
            Widget.lastTargetColor = nil
            frame:SetTargetNameColor(targetColor)
        end
    end
    if frame.SetCastLabelsVisible then
        local labelsVisible = hasSpellText or hasTargetText
        if Widget.lastLabelsVisible ~= labelsVisible then
            Widget.lastLabelsVisible = labelsVisible
            frame:SetCastLabelsVisible(labelsVisible)
        end
    end
end

function FocusHelper_ApplyUnavailableVisibility()
    local frame = Widget.frame
    if not frame then return end

    SetCachedAlpha(frame, 1)
    if not CastState.active or CastState.preview then
        return
    end

    local db = activeDB or GetDB()
    local mode = db.unavailableDisplayMode or defaults.unavailableDisplayMode
    if mode ~= "hide" then
        return
    end

    if CastState.notInterruptibleKnown == true and CastState.notInterruptible == true then
        SetCachedAlpha(frame, 0)
        return
    elseif CastState.visualNotInterruptibleRaw ~= nil and frame.SetAlphaFromBoolean then
        Widget.lastAlpha = nil
        pcall(frame.SetAlphaFromBoolean, frame, CastState.visualNotInterruptibleRaw, 0, 1)
    end

    if CD_RUNTIME.alertProbeCastKey ~= CastState.castKey and CD_RUNTIME.RefreshAlertCooldownProbe then
        CD_RUNTIME:RefreshAlertCooldownProbe("hide-check")
    end

    local cdState = CD_RUNTIME.alertProbeState or "unknown"
    local entry = CD_RUNTIME.alertProbeEntry or currentInterrupt
    local threshold = ClampNumber(db.hideCooldownThreshold, 0, 10, defaults.hideCooldownThreshold)
    local estimatedRemaining = CD_RUNTIME:GetLearnedCooldownRemaining(entry)
    local learned = estimatedRemaining ~= nil

    if cdState == "cooldown" then
        if learned and estimatedRemaining > threshold then
            SetCachedAlpha(frame, 0)
        end
    end
end

local function RegisterLayout()
    local frame = Widget.frame
    if not frame then return end
    if not (YUI.Layout and YUI.Layout.RegisterFrame) then
        ApplyDefaultPoint(frame)
        return
    end
    if layoutRegistered then
        if YUI.Layout.RefreshFrame then
            YUI.Layout:RefreshFrame(LAYOUT_ID)
        end
        return
    end

    YUI.Layout:RegisterFrame(LAYOUT_ID, {
        frame = frame,
        title = T("layout.interrupt_bar", "Focus Interrupt Bar"),
        category = "component",
        defaultPlacement = GetDefaultPlacement,
        movable = true,
        snap = true,
        anchorTargets = { "UIParent" },
        minWidth = MIN_WIDTH,
        minHeight = MIN_HEIGHT,
        isEnabled = function()
            local db = activeDB or GetDB()
            return featureActive and db.interruptEnabled == true
        end,
        openPluginSettings = OpenFocusHelperSettings,
        onEnterEditMode = function()
            if not featureActive then return end
            layoutPreviewActive = true
            CastState.preview = true
            CastState.alerted = true
            FocusHelper_ShowPreview()
        end,
        onExitEditMode = function()
            layoutPreviewActive = false
            if settingsPreviewActive == true and featureActive then
                FocusHelper_ShowPreview()
            else
                CastState.preview = false
                FocusHelper_RefreshFocusCast("layout-exit")
            end
        end,
        onApply = function()
            FocusHelper_ApplyAppearance()
        end,
    })
    layoutRegistered = true
end

function FocusHelper_EnsureWidget()
    if Widget.frame then return Widget.frame end

    local db = activeDB or GetDB()
    local app = GUI2 and GUI2.Application
    local textFontPath = ResolveTextFontPath(db.textFont)
    local frame = app and app.CreateCastBar and app:CreateCastBar(UIParent, {
        barWidth = db.width,
        height = db.height,
        iconSize = db.height,
        fillTexture = GetStatusBarTexture(db),
        fillColor = GetCurrentBarColor(db),
        markerColor = db.markerColor,
        textFontPath = textFontPath,
        timeFontSize = db.timeFontSize,
        nameFontSize = db.spellNameFontSize,
        targetFontSize = db.targetNameFontSize,
        textOutlineMode = db.textOutlineMode,
        fallbackIcon = FALLBACK_ICON,
        value = 0,
    })
    if not frame then return nil end

    Widget.frame = frame
    Widget.progress = frame
    Widget.marker = frame.marker
    Widget.timeText = frame.timeText
    Widget.lastTextFont = db.textFont
    Widget.lastTextFontPath = textFontPath
    frame:Hide()

    RegisterLayout()
    FocusHelper_ApplyAppearance()
    return frame
end

local function StopOnUpdate()
    if Widget.frame and Widget.frame.SetScript then
        Widget.frame:SetScript("OnUpdate", nil)
    end
end

local function StartOnUpdate()
    local frame = FocusHelper_EnsureWidget()
    if frame and frame.SetScript then
        frame:SetScript("OnUpdate", FocusHelper_OnUpdate)
    end
end

local cpuWatchdog = YUI.CPUWatchdog
if cpuWatchdog and cpuWatchdog.RegisterProbe then
    cpuWatchdog:RegisterProbe("component.focus-helper", {
        localeKey = "cpu_watch.probe.focus_helper",
        kind = "frame",
        getTarget = function() return Widget.frame end,
        snapshot = function()
            return {
                running = Widget.frame and Widget.frame:GetScript("OnUpdate") == FocusHelper_OnUpdate or false,
                learning = CD_RUNTIME.learnTicker ~= nil,
            }
        end,
    })
    cpuWatchdog:RegisterProbe("component.focus-helper-learning", {
        localeKey = "cpu_watch.probe.focus_helper_learning",
        kind = "function",
        getTarget = function() return CD_RUNTIME.RefreshLearnedCooldownProbe end,
        snapshot = function() return { running = CD_RUNTIME.learnTicker ~= nil } end,
    })
end

local function HideWidget()
    StopOnUpdate()
    if CD_RUNTIME.ClearAlertCooldownProbe then
        CD_RUNTIME:ClearAlertCooldownProbe("hide")
    end
    ResetWidgetCachedDisplay()
    Widget.currentBarColor = nil
    if Widget.frame and Widget.frame.HideMarker then
        Widget.frame:HideMarker()
    elseif Widget.marker then
        Widget.marker:Hide()
    end
    if Widget.frame and Widget.frame.SetRemainingText then
        SetCachedRemainingText(Widget.frame, "")
    elseif Widget.timeText then
        Widget.timeText:SetText("")
    end
    if Widget.frame and Widget.frame.ClearCastDuration then
        Widget.frame:ClearCastDuration()
    end
    if Widget.frame then
        Widget.frame:SetAlpha(1)
        Widget.frame:Hide()
    end
    ResetWidgetCachedDisplay()
end

local function ResetCastState()
    if CD_RUNTIME.ClearAlertCooldownProbe then
        CD_RUNTIME:ClearAlertCooldownProbe("reset")
    end
    CastState.active = false
    CastState.preview = false
    CastState.name = nil
    CastState.targetName = nil
    CastState.targetColor = nil
    CastState.targetSource = nil
    CastState.targetColorSource = nil
    CastState.texture = nil
    CastState.spellID = nil
    CastState.castID = nil
    CastState.castKey = nil
    CastState.durationAppliedKey = nil
    CastState.nativeMarkerKey = nil
    CastState.usingNativeDuration = false
    CastState.isChannel = false
    CastState.startTimeMS = nil
    CastState.endTimeMS = nil
    CastState.durationObject = nil
    CastState.totalSeconds = nil
    CastState.elapsedSeconds = nil
    CastState.remainingSeconds = nil
    CastState.visualNotInterruptibleRaw = nil
    CastState.notInterruptibleKnown = false
    CastState.notInterruptible = false
    CastState.interruptibilityPending = false
    CastState.alerted = false
    CastState.previewStartedAt = nil
    focusCastStartedAt = 0
    focusCastDisplayType = nil
end

local function IsFocusExists()
    if UnitAPI.Exists then
        return UnitAPI.Exists("focus") == true
    end
    if UnitAPI.UnitExists then
        return UnitAPI.UnitExists("focus") == true
    end
    return UnitExists and UnitExists("focus") == true
end

local function IsUnitExists(unit)
    if UnitAPI.Exists then
        return UnitAPI.Exists(unit) == true
    end
    if UnitAPI.UnitExists then
        return UnitAPI.UnitExists(unit) == true
    end
    return UnitExists and UnitExists(unit) == true
end

local function GetFocusGUIDForAlert()
    if UnitAPI.UnitGUID then
        return SafeRawValue(UnitAPI.UnitGUID("focus"))
    end
    if UnitGUID then
        local ok, guid = pcall(UnitGUID, "focus")
        if ok then
            return SafeRawValue(guid)
        end
    end
    return nil
end

local function ResolveFocusHostilityForAlert()
    if not IsFocusExists() then
        return false, "no-focus"
    end

    local canAttack
    if UnitAPI.CanAttack then
        canAttack = SafeBooleanValue(UnitAPI.CanAttack("focus", "player"), nil)
    end
    if canAttack == true then
        return true, "hostile"
    end
    if canAttack == false then
        return false, "not-hostile"
    end

    local reaction
    if UnitAPI.Reaction then
        reaction = SafeNumberValue(UnitAPI.Reaction("focus", "player"))
    elseif UnitReaction then
        local ok, value = pcall(UnitReaction, "focus", "player")
        if ok then
            reaction = SafeNumberValue(value)
        end
    end
    if reaction then
        if reaction <= 4 then
            return true, "hostile-reaction"
        end
        return false, "not-hostile"
    end

    if UnitAPI.IsFriend and UnitAPI.IsFriend("focus", "player") == true then
        return false, "not-hostile"
    end

    return true, "hostility-unknown"
end

local function IsAlertDedupBlocked()
    local lastAt = SafeNumberValue(lastAlertPlayedAt)
    if not lastAt or lastAt <= 0 or (GetNow() - lastAt) >= ALERT_DEDUP_SECONDS then
        return false
    end

    local focusGUID = GetFocusGUIDForAlert()
    if focusGUID and lastAlertFocusGUID and focusGUID ~= lastAlertFocusGUID then
        return false
    end

    return true
end

local function GetUnitDisplayName(unit)
    if UnitAPI.GetDisplayNameInfo then
        local info = UnitAPI.GetDisplayNameInfo(unit)
        local displayName = CD_RUNTIME:FirstDisplayTextValue(
            info and info.displayNameRaw,
            info and info.displayName,
            info and info.nameRaw,
            info and info.name
        )
        if HasDisplayText(displayName) then
            return displayName
        end
    end

    local nameRaw, realmRaw
    if UnitAPI.UnitFullName then
        nameRaw, realmRaw = UnitAPI.UnitFullName(unit)
    end
    local name = SafeRawValue(nameRaw)
    local realm = SafeRawValue(realmRaw)
    if (type(name) ~= "string" or name == "") and UnitAPI.UnitName then
        nameRaw, realmRaw = UnitAPI.UnitName(unit)
    end
    name = SafeRawValue(nameRaw)
    realm = SafeRawValue(realmRaw)
    if type(name) ~= "string" or name == "" then
        return CD_RUNTIME:FirstDisplayTextValue(nameRaw)
    end
    if type(realm) == "string" and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function GetClassColorValue(classToken)
    classToken = SafeRawValue(classToken)
    if not (classToken and UnitAPI.GetClassColor) then return nil end
    local color = UnitAPI.GetClassColor(classToken)
    if not color then return nil end
    return {
        color.r or color[1] or 1,
        color.g or color[2] or 1,
        color.b or color[3] or 1,
        color.a or color[4] or 1,
    }
end

local function GetUnitClassToken(unit)
    if UnitAPI.GetClassToken then
        return SafeRawValue(UnitAPI.GetClassToken(unit))
    end
    if UnitAPI.UnitClass then
        local _, classToken = UnitAPI.UnitClass(unit)
        return SafeRawValue(classToken)
    end
    return nil
end

local function GetUnitClassColorValue(unit)
    if UnitAPI.GetUnitClassColor then
        local color = UnitAPI.GetUnitClassColor(unit)
        if color then
            return {
                color.r or color[1] or 1,
                color.g or color[2] or 1,
                color.b or color[3] or 1,
                color.a or color[4] or 1,
            }
        end
    end
    local classToken = GetUnitClassToken(unit)
    return GetClassColorValue(classToken)
end

function CD_RUNTIME:ResolveTargetColor(classToken, fallbackUnit)
    local color = GetClassColorValue(classToken)
    if color then
        return color, "spell-target"
    end
    color = GetUnitClassColorValue(fallbackUnit or "focustarget")
    if color then
        return color, "focustarget"
    end
    return "color.text.primary", "default"
end

local function ResolveFocusTargetDisplay(cast)
    if UnitAPI.GetSpellTargetInfo then
        local info = UnitAPI.GetSpellTargetInfo("focus")
        local name = CD_RUNTIME:FirstDisplayTextValue(
            info and info.displayNameRaw,
            info and info.displayName,
            info and info.nameRaw,
            info and info.name
        )
        if HasDisplayText(name) then
            local color, colorSource = CD_RUNTIME:ResolveTargetColor(info and info.classToken, "focustarget")
            return name, color, "spell-target", colorSource
        end
    end
    local castTargetName = CD_RUNTIME:FirstDisplayTextValue(
        cast and cast.targetNameRaw,
        cast and cast.displayTargetNameRaw,
        cast and cast.targetName
    )
    if HasDisplayText(castTargetName) then
        local color = SafeRawValue(cast and cast.targetColor)
        local colorSource = color and "cast" or nil
        if not color then
            color, colorSource = CD_RUNTIME:ResolveTargetColor(nil, "focustarget")
        end
        return castTargetName, color, "cast", colorSource
    end
    if not IsUnitExists("focustarget") then
        return nil, "color.text.primary", "none", "default"
    end
    local unitName = GetUnitDisplayName("focustarget")
    local color, colorSource = CD_RUNTIME:ResolveTargetColor(nil, "focustarget")
    local hasUnitName = HasDisplayText(unitName)
    local source = hasUnitName and "focustarget" or "none"
    return unitName, color, source, colorSource
end

local function GetCurrentSpecID()
    if not (TalentAPI.GetSpecialization and TalentAPI.GetSpecializationInfo) then
        return nil
    end
    local specIndex = TalentAPI.GetSpecialization()
    if not specIndex then return nil end
    local specID = TalentAPI.GetSpecializationInfo(specIndex)
    return SafeNumberValue(specID)
end

local function QuerySpellBookBoolean(funcName, spellID, extraArg)
    if not (C_SpellBook and C_SpellBook[funcName]) then
        return nil
    end

    local func = C_SpellBook[funcName]
    local spellBanks = Enum and Enum.SpellBookSpellBank
    local sawFalse = false

    if spellBanks then
        local playerBank = spellBanks.Player
        local petBank = spellBanks.Pet
        for index = 1, 2 do
            local bank = index == 1 and playerBank or petBank
            if bank ~= nil then
                local ok, known
                if extraArg ~= nil then
                    ok, known = pcall(func, spellID, bank, extraArg)
                else
                    ok, known = pcall(func, spellID, bank)
                end
                if ok then
                    known = SafeBooleanValue(known, nil)
                    if known == true then
                        return true
                    elseif known == false then
                        sawFalse = true
                    end
                end
            end
        end
        if sawFalse then
            return false
        end
        return nil
    end

    local ok, known = pcall(func, spellID)
    if ok then
        return SafeBooleanValue(known, nil)
    end
    return nil
end

local function HasSpellKnownAPI()
    return SpellAPI.IsKnownOrInSpellBook
        or SpellAPI.IsKnown
        or (C_SpellBook and (C_SpellBook.IsSpellInSpellBook or C_SpellBook.IsSpellKnownOrInSpellBook or C_SpellBook.IsSpellKnown or C_SpellBook.FindSpellBookSlotForSpell))
        or IsSpellKnown
end

local function GetSpellKnownState(spellID)
    if not spellID then return false, "missing-spell" end
    local hasAPI = HasSpellKnownAPI()
    if not hasAPI then return nil, "no-api" end
    local known = QuerySpellBookBoolean("IsSpellInSpellBook", spellID)
    if known ~= nil then return known, "IsSpellInSpellBook" end
    known = QuerySpellBookBoolean("IsSpellKnownOrInSpellBook", spellID, true)
    if known ~= nil then return known, "IsSpellKnownOrInSpellBook" end
    if SpellAPI.IsKnownOrInSpellBook then
        known = SafeBooleanValue(SpellAPI.IsKnownOrInSpellBook(spellID), nil)
        if known ~= nil then return known, "SpellAPI.IsKnownOrInSpellBook" end
    end
    if SpellAPI.IsKnown then
        known = SafeBooleanValue(SpellAPI.IsKnown(spellID), nil)
        if known ~= nil then return known, "SpellAPI.IsKnown" end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok
        ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok then
            known = SafeBooleanValue(known, nil)
            if known ~= nil then return known, "C_SpellBook.IsSpellKnown" end
        end
    end
    if C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell then
        local ok, slotIndex = pcall(C_SpellBook.FindSpellBookSlotForSpell, spellID, true, true, false, false)
        if ok and SafeNumberValue(slotIndex) then
            return true, "FindSpellBookSlotForSpell"
        end
    end
    if IsSpellKnown then
        local ok, known = pcall(IsSpellKnown, spellID)
        if ok then
            known = SafeBooleanValue(known, nil)
            if known ~= nil then return known, "IsSpellKnown" end
        end
    end
    return nil, "unknown"
end

local function IsSpellKnownSafe(spellID)
    local known = GetSpellKnownState(spellID)
    if known ~= nil then return known == true end
    return not HasSpellKnownAPI()
end

local function IsPetAvailable()
    if UnitAPI.Exists then
        return UnitAPI.Exists("pet") == true
    end
    if UnitAPI.UnitExists then
        return UnitAPI.UnitExists("pet") == true
    end
    return UnitExists and UnitExists("pet") == true
end

local function CountInterruptEntries(entries)
    if type(entries) ~= "table" then return 0 end
    local count = 0
    for _, entry in ipairs(entries) do
        if entry and entry.spellID then
            count = count + 1
        end
    end
    return count
end

local function AddInterruptCandidate(entry)
    if not (entry and entry.spellID) then return end
    interruptSpellIDs[entry.spellID] = entry
end

local function AddResolvedInterruptCandidate(list, entry)
    if not (list and entry and entry.spellID) then return end
    list[#list + 1] = entry
end

local function BuildInterruptCandidates(entries)
    if type(entries) ~= "table" then return nil, nil end
    local candidates = {}
    local unknownPlayerFallbacks = {}
    local noAPIFallbacks = {}
    for _, entry in ipairs(entries) do
        if entry and entry.spellID then
            AddInterruptCandidate(entry)
            if entry.pet then
                if IsPetAvailable() then
                    AddResolvedInterruptCandidate(candidates, entry)
                end
            else
                local known = GetSpellKnownState(entry.spellID)
                if known == true then
                    AddResolvedInterruptCandidate(candidates, entry)
                elseif known == nil then
                    if HasSpellKnownAPI() then
                        AddResolvedInterruptCandidate(unknownPlayerFallbacks, entry)
                    else
                        AddResolvedInterruptCandidate(noAPIFallbacks, entry)
                    end
                end
            end
        end
    end
    if #candidates == 0 then
        for _, entry in ipairs(unknownPlayerFallbacks) do
            AddResolvedInterruptCandidate(candidates, entry)
        end
    end
    if #candidates == 0 then
        for _, entry in ipairs(noAPIFallbacks) do
            AddResolvedInterruptCandidate(candidates, entry)
        end
    end
    return candidates[1], candidates
end

local function RebuildInterruptData(reason)
    reason = reason or "rebuild"
    if CD_RUNTIME.ClearAlertCooldownProbe then
        CD_RUNTIME:ClearAlertCooldownProbe("rebuild")
    end
    for spellID in pairs(interruptSpellIDs) do
        interruptSpellIDs[spellID] = nil
    end
    currentInterrupt = nil
    for index = #currentInterrupts, 1, -1 do
        currentInterrupts[index] = nil
    end
    currentInterruptsVersion = currentInterruptsVersion + 1
    CD_RUNTIME:InvalidateReadiness()

    local classToken = GetUnitClassToken("player")
    local classData = classToken and INTERRUPT_SPELLS[classToken] or nil
    if not classData then
        if CD_RUNTIME.ValidateLearnedCooldownAfterRebuild then
            CD_RUNTIME:ValidateLearnedCooldownAfterRebuild(reason, false)
        end
        return
    end

    local entries = (YUI.IsForever == true and classData.foreverSpells)
        or (YUI.IsRetail == true and classData.retailSpells) or classData.legacySpells
    currentInterrupt, currentInterrupts = BuildInterruptCandidates(entries)
    currentInterrupts = currentInterrupts or {}
    currentInterruptsVersion = currentInterruptsVersion + 1
    CD_RUNTIME:InvalidateReadiness()
    if CD_RUNTIME.ValidateLearnedCooldownAfterRebuild then
        CD_RUNTIME:ValidateLearnedCooldownAfterRebuild(reason, CD_RUNTIME:ShouldPreserveLearnedCooldownOnRebuild(reason))
    end
end

local function GetCooldownRemainingFromSpell(entry)
    if not (entry and entry.spellID and SpellAPI.GetCooldown) then
        return nil
    end
    local cd = SpellAPI.GetCooldown(entry.spellID)
    if type(cd) ~= "table" then
        return nil
    end
    local startTime = SafeNumberValue(cd.startTime)
    local duration = SafeNumberValue(cd.duration)
    if startTime == nil or duration == nil then
        return nil
    end
    local enabled = SafeBooleanValue(cd.isEnabled, true)
    if enabled == false then
        return nil
    end
    if startTime <= 0 or duration <= 1.5 then
        return 0
    end
    local remaining = startTime + duration - GetNow()
    if remaining > 0 then
        return remaining
    end
    return 0
end

local function GetInterruptCooldownState(entry)
    if not (entry and entry.spellID) then
        return {
            ready = nil,
            remainingSeconds = nil,
            durationObject = nil,
            reason = "no-spell",
            source = "none",
        }
    end

    if (YUI.IsRetail == true or YUI.IsForever == true) and SpellAPI.GetCooldownDurationState then
        local state = SpellAPI.GetCooldownDurationState(entry.spellID)
        if type(state) == "table" then
            return state
        end
        return {
            ready = nil,
            remainingSeconds = nil,
            durationObject = nil,
            reason = "no-duration-state",
            source = "duration-object",
        }
    end

    local remaining = SafeNumberValue(GetCooldownRemainingFromSpell(entry))
    if remaining == nil then
        return {
            ready = nil,
            remainingSeconds = nil,
            durationObject = nil,
            reason = "unknown",
            source = "spell-api",
        }
    end
    if remaining > 0 then
        return {
            ready = false,
            remainingSeconds = remaining,
            durationObject = nil,
            reason = "cooldown",
            source = "spell-api",
        }
    end
    return {
        ready = true,
        remainingSeconds = 0,
        durationObject = nil,
        reason = "ready",
        source = "spell-api",
    }
end

local function RefreshInterruptCooldownSnapshot()
    CD_RUNTIME:InvalidateReadiness()
end

function IsInterruptReady()
    local now = GetNow()
    local readinessKey = currentInterruptsVersion
    if CD_RUNTIME.readinessAt > 0
        and CD_RUNTIME.readinessKey == readinessKey
        and (now - CD_RUNTIME.readinessAt) < CD_RUNTIME.readinessRefresh then
        return CD_RUNTIME.readinessReady, CD_RUNTIME.readinessEntry, CD_RUNTIME.readinessRemaining, CD_RUNTIME.readinessReason, CD_RUNTIME.readinessSource, CD_RUNTIME.readinessState, CD_RUNTIME.readinessVisualEntry, CD_RUNTIME.readinessVisualState
    end

    local function StoreReadiness(ready, entry, remaining, reason, source, state, visualEntry, visualState)
        CD_RUNTIME.readinessAt = GetNow()
        CD_RUNTIME.readinessKey = readinessKey
        CD_RUNTIME.readinessReady = ready
        CD_RUNTIME.readinessEntry = entry
        CD_RUNTIME.readinessRemaining = remaining
        CD_RUNTIME.readinessReason = reason
        CD_RUNTIME.readinessSource = source
        CD_RUNTIME.readinessState = state
        CD_RUNTIME.readinessVisualEntry = visualEntry
        CD_RUNTIME.readinessVisualState = visualState
        CD_RUNTIME.readinessVisualReadyValues = (#CD_RUNTIME.visualReadyValues > 0 and CD_RUNTIME.visualReadyValues) or nil
        return ready, entry, remaining, reason, source, state, visualEntry, visualState
    end

    if type(currentInterrupts) ~= "table" or #currentInterrupts == 0 then
        return StoreReadiness(false, nil, nil, "no-spell", "none")
    end

    for index = #CD_RUNTIME.visualReadyValues, 1, -1 do
        CD_RUNTIME.visualReadyValues[index] = nil
    end

    local visualEntry, visualState
    local cooldownEntry, cooldownState, cooldownRemaining
    local unknownEntry, unknownState, unknownRemaining
    local unavailableEntry

    for _, entry in ipairs(currentInterrupts) do
        if entry and entry.spellID then
            if entry.pet and not IsPetAvailable() then
                unavailableEntry = unavailableEntry or entry
            else
                local state = GetInterruptCooldownState(entry)
                if state and state.durationObject and state.readyRaw ~= nil and not visualState then
                    visualEntry = entry
                    visualState = state
                end
                if state and state.durationObject and state.readyRaw ~= nil then
                    CD_RUNTIME.visualReadyValues[#CD_RUNTIME.visualReadyValues + 1] = state.readyRaw
                end
                local remaining = SafeNumberValue(state and state.remainingSeconds)
                local source = state and state.source or "unknown"
                if state and state.ready == true then
                    return StoreReadiness(true, entry, 0, "ready", source, state, visualEntry or entry, visualState or state)
                elseif state and state.ready == false then
                    if not cooldownEntry
                        or (remaining ~= nil and (cooldownRemaining == nil or remaining < cooldownRemaining)) then
                        cooldownEntry = entry
                        cooldownState = state
                        cooldownRemaining = remaining
                    end
                elseif not unknownEntry then
                    unknownEntry = entry
                    unknownState = state
                    unknownRemaining = remaining
                end
            end
        end
    end

    if cooldownEntry then
        return StoreReadiness(false, cooldownEntry, cooldownRemaining, "cooldown", cooldownState and cooldownState.source or "unknown", cooldownState, visualEntry, visualState)
    end
    if unknownEntry then
        return StoreReadiness(false, unknownEntry, unknownRemaining, "unknown", unknownState and unknownState.source or "unknown", unknownState, visualEntry, visualState)
    end
    if unavailableEntry then
        return StoreReadiness(false, unavailableEntry, nil, "pet-unavailable", "pet", nil, visualEntry, visualState)
    end
    return StoreReadiness(false, nil, nil, "no-spell", "none", nil, visualEntry, visualState)
end

function CD_RUNTIME:StopLearnedCooldownTicker()
    local ticker = self.learnTicker
    self.learnTicker = nil
    if ticker and ticker.Cancel then
        pcall(ticker.Cancel, ticker)
    end
end

function CD_RUNTIME:ClearLearnedCooldown(reason, clearLearned)
    local pendingSpellID = self.learnPendingSpellID
    self:StopLearnedCooldownTicker()
    self.learnPendingSpellID = nil
    self.learnPendingStartAt = nil
    self.learnPendingGeneration = (self.learnPendingGeneration or 0) + 1
    self.learnPendingSawCooldown = false
    if clearLearned ~= false then
        for spellID in pairs(self.learnedCooldowns) do
            self.learnedCooldowns[spellID] = nil
        end
    end
end

function CD_RUNTIME:IsCurrentInterruptSpellID(spellID)
    spellID = SafeNumberValue(spellID)
    return spellID ~= nil and interruptSpellIDs[spellID] ~= nil
end

function CD_RUNTIME:ShouldPreserveLearnedCooldownOnRebuild(reason)
    return reason == "SPELLS_CHANGED" or reason == "PLAYER_ENTERING_WORLD"
end

function CD_RUNTIME:ValidateLearnedCooldownAfterRebuild(reason, preserveValid)
    reason = reason or "rebuild"
    if preserveValid ~= true then
        self:ClearLearnedCooldown(reason, true)
        return
    end

    local pendingSpellID = self.learnPendingSpellID
    if pendingSpellID then
        if not self:IsCurrentInterruptSpellID(pendingSpellID) then
            self:ClearLearnedCooldown(tostring(reason) .. "-spell-missing", false)
        end
    end

    local learnedCooldowns = self.learnedCooldowns
    if type(learnedCooldowns) ~= "table" then return end
    for spellID in pairs(learnedCooldowns) do
        if not self:IsCurrentInterruptSpellID(spellID) then
            learnedCooldowns[spellID] = nil
        end
    end
end

function CD_RUNTIME:UpdateLearnedCooldownFromProbe(state, entry, trigger)
    local spellID = entry and entry.spellID or self.learnPendingSpellID
    if not (self.learnPendingSpellID and spellID and spellID == self.learnPendingSpellID and self.learnPendingStartAt) then
        return
    end

    local now = GetNow()
    local elapsed = now - self.learnPendingStartAt
    if elapsed > (self.learnMaxSeconds or 180) then
        self:ClearLearnedCooldown("timeout", false)
        return
    end

    if state == "cooldown" then
        if self.learnPendingSawCooldown ~= true then
            self.learnPendingSawCooldown = true
        end
        return
    end

    if state == "ready" then
        if self.learnPendingSawCooldown == true and elapsed > 0 then
            self.learnedCooldowns[spellID] = {
                duration = elapsed,
                learnedAt = now,
            }
            self:ClearLearnedCooldown("learned", false)
        end
        return
    end
end

local function RefreshLearnedCooldownProbeImpl(self, trigger)
    local spellID = self.learnPendingSpellID
    if not spellID then return end
    local entry = interruptSpellIDs[spellID]
    if not entry then
        self:ClearLearnedCooldown("spell-missing", true)
        return
    end

    local stateName = "unknown"
    if SpellAPI.GetCooldownProbeState then
        local state = SpellAPI.GetCooldownProbeState(spellID)
        if type(state) == "table" then
            if state.ready == true or state.state == "ready" then
                stateName = "ready"
            elseif state.ready == false or state.state == "cooldown" then
                stateName = "cooldown"
            end
        end
    else
        local ready = IsInterruptReady and IsInterruptReady()
        if ready == true then
            stateName = "ready"
        end
    end
    self:UpdateLearnedCooldownFromProbe(stateName, entry, trigger)
end

function CD_RUNTIME:RefreshLearnedCooldownProbe(trigger)
    local cpuWatchdog = YUI.CPUWatchdog
    local cpuStartedAt = cpuWatchdog and cpuWatchdog.timingActive and cpuWatchdog:BeginProbeTiming()
    RefreshLearnedCooldownProbeImpl(self, trigger)
    if cpuStartedAt then cpuWatchdog:EndProbeTiming("component.focus-helper-learning", cpuStartedAt) end
end

function CD_RUNTIME:StartLearnedCooldown(spellID, entry, trigger)
    spellID = SafeNumberValue(spellID)
    if not spellID then return end
    self:StopLearnedCooldownTicker()
    self.learnPendingSpellID = spellID
    self.learnPendingStartAt = GetNow()
    self.learnPendingGeneration = (self.learnPendingGeneration or 0) + 1
    self.learnPendingSawCooldown = false
    local generation = self.learnPendingGeneration

    if C_Timer and C_Timer.NewTicker then
        self.learnTicker = C_Timer.NewTicker(self.learnPollSeconds or 0.25, function()
            if CD_RUNTIME.learnPendingGeneration ~= generation then
                CD_RUNTIME:StopLearnedCooldownTicker()
                return
            end
            CD_RUNTIME:RefreshLearnedCooldownProbe("learn-tick")
        end)
    end
    self:RefreshLearnedCooldownProbe(trigger or "succeeded")
end

function CD_RUNTIME:GetLearnedCooldownRemaining(entry)
    local spellID = entry and entry.spellID
    if not spellID then
        return nil, nil, "no-spell"
    end
    local learned = self.learnedCooldowns[spellID]
    if not (learned and learned.duration) then
        return nil, nil, "not-learned"
    end
    if self.learnPendingSpellID ~= spellID or not self.learnPendingStartAt then
        return nil, learned.duration, "no-active-cd"
    end
    local remaining = learned.duration - (GetNow() - self.learnPendingStartAt)
    if remaining < 0 then remaining = 0 end
    return remaining, learned.duration, "learned"
end

function CD_RUNTIME:SetAlertSteelState(state, source, reason)
    state = state or "unknown"
    source = source or "none"
    reason = reason or state
    CD_RUNTIME.alertSteelState = state
    CD_RUNTIME.alertSteelSource = source
    CD_RUNTIME.alertSteelReason = reason
    CD_RUNTIME.alertSteelCastKey = CastState.castKey

end

function CD_RUNTIME:ClearAlertSteelState(reason)
    CD_RUNTIME.alertSteelState = "unknown"
    CD_RUNTIME.alertSteelSource = "none"
    CD_RUNTIME.alertSteelReason = reason or "clear"
    CD_RUNTIME.alertSteelCastKey = nil
end

function CD_RUNTIME:ClearAlertCooldownProbe(reason)
    CD_RUNTIME.alertProbeGeneration = (CD_RUNTIME.alertProbeGeneration or 0) + 1
    local generation = CD_RUNTIME.alertProbeGeneration
    if type(currentInterrupts) == "table" then
        for _, entry in ipairs(currentInterrupts) do
            if entry and entry.spellID and SpellAPI.ClearCooldownProbe then
                SpellAPI.ClearCooldownProbe(entry.spellID)
            end
        end
    end
    CD_RUNTIME.alertProbeState = "unknown"
    CD_RUNTIME.alertProbeReason = reason or "clear"
    CD_RUNTIME.alertProbeSource = "none"
    CD_RUNTIME.alertProbeSpellID = nil
    CD_RUNTIME.alertProbeEntry = nil
    CD_RUNTIME.alertProbeCastKey = nil
    CD_RUNTIME.alertProbeLastPollAt = 0
    CD_RUNTIME.alertProbePreviousState = nil
    CD_RUNTIME.alertProbeActive = false
    self:ClearAlertSteelState(reason or "clear")
end

function CD_RUNTIME:StoreAlertProbeState(state, entry, probeState, trigger, generation)
    state = state or "unknown"
    local previous = CD_RUNTIME.alertProbeState
    local castKey = CastState.castKey
    local reason = (probeState and probeState.reason) or state
    local source = (probeState and probeState.source) or "native-cooldown-probe"

    CD_RUNTIME.alertProbeGeneration = generation
    CD_RUNTIME.alertProbePreviousState = previous
    CD_RUNTIME.alertProbeState = state
    CD_RUNTIME.alertProbeReason = reason
    CD_RUNTIME.alertProbeSource = source
    CD_RUNTIME.alertProbeSpellID = entry and entry.spellID or nil
    CD_RUNTIME.alertProbeEntry = entry
    CD_RUNTIME.alertProbeCastKey = castKey
    CD_RUNTIME.alertProbeActive = state == "cooldown"

    self:UpdateLearnedCooldownFromProbe(state, entry, trigger)
end

function CD_RUNTIME:RefreshAlertCooldownProbe(trigger)
    CD_RUNTIME.alertProbeGeneration = (CD_RUNTIME.alertProbeGeneration or 0) + 1
    local generation = CD_RUNTIME.alertProbeGeneration
    CD_RUNTIME.alertProbeLastPollAt = GetNow()

    if type(currentInterrupts) ~= "table" or #currentInterrupts == 0 then
        self:StoreAlertProbeState("unknown", nil, { reason = "no-spell", source = "native-cooldown-probe" }, trigger, generation)
        return false, nil, nil, "no-spell", "native-cooldown-probe"
    end

    local cooldownEntry, cooldownState
    local unknownEntry, unknownState
    local unavailableEntry

    for _, entry in ipairs(currentInterrupts) do
        if entry and entry.spellID then
            if entry.pet and not IsPetAvailable() then
                unavailableEntry = unavailableEntry or entry
            elseif SpellAPI.GetCooldownProbeState then
                local state = SpellAPI.GetCooldownProbeState(entry.spellID)
                if type(state) == "table" then
                    if state.ready == true or state.state == "ready" then
                        self:StoreAlertProbeState("ready", entry, state, trigger, generation)
                        return true, entry, nil, "ready", state.source or "native-cooldown-probe"
                    elseif state.ready == false or state.state == "cooldown" then
                        cooldownEntry = cooldownEntry or entry
                        cooldownState = cooldownState or state
                    else
                        unknownEntry = unknownEntry or entry
                        unknownState = unknownState or state
                    end
                else
                    unknownEntry = unknownEntry or entry
                    unknownState = unknownState or { reason = "bad-state", source = "native-cooldown-probe" }
                end
            else
                local ready, readyEntry, remaining, reason, source = IsInterruptReady()
                local fallbackState = {
                    reason = reason or "fallback",
                    source = source or "fallback",
                    remainingSeconds = remaining,
                }
                self:StoreAlertProbeState(ready == true and "ready" or "unknown", readyEntry or entry, fallbackState, trigger, generation)
                return ready, readyEntry or entry, remaining, reason, source
            end
        end
    end

    if cooldownEntry then
        self:StoreAlertProbeState("cooldown", cooldownEntry, cooldownState, trigger, generation)
        return false, cooldownEntry, nil, "cooldown", (cooldownState and cooldownState.source) or "native-cooldown-probe"
    end
    if unknownEntry then
        self:StoreAlertProbeState("unknown", unknownEntry, unknownState, trigger, generation)
        return false, unknownEntry, nil, "unknown", (unknownState and unknownState.source) or "native-cooldown-probe"
    end
    if unavailableEntry then
        local state = { reason = "pet-unavailable", source = "pet" }
        self:StoreAlertProbeState("unknown", unavailableEntry, state, trigger, generation)
        return false, unavailableEntry, nil, "pet-unavailable", "pet"
    end

    self:StoreAlertProbeState("unknown", nil, { reason = "no-spell", source = "native-cooldown-probe" }, trigger, generation)
    return false, nil, nil, "no-spell", "native-cooldown-probe"
end

function CD_RUNTIME:IsInterruptReadyForAlert(trigger)
    local cachedState = CD_RUNTIME.alertProbeState
    if CD_RUNTIME.alertProbeCastKey == CastState.castKey
        and CD_RUNTIME.alertProbeSource ~= "none"
        and cachedState ~= nil then
        if cachedState == "ready" then
            return true, CD_RUNTIME.alertProbeEntry, nil, "ready", CD_RUNTIME.alertProbeSource
        end
        if (GetNow() - (CD_RUNTIME.alertProbeLastPollAt or 0)) < (CD_RUNTIME.alertProbeInterval or 0.08) then
            local reason = CD_RUNTIME.alertProbeReason
            if cachedState == "cooldown" then
                reason = "cooldown"
            end
            return false, CD_RUNTIME.alertProbeEntry, nil, reason or "unknown", CD_RUNTIME.alertProbeSource
        end
    end
    local ready, entry, remaining, reason, source = self:RefreshAlertCooldownProbe(trigger or "alert-check")
    if source == "native-cooldown-probe" then
        if ready == true then
            return true, entry, nil, "ready", source
        end
        if reason == "cooldown" then
            return false, entry, nil, "cooldown", source
        end
        return false, entry, nil, reason or "unknown", source
    end
    return ready, entry, remaining, reason, source
end

function CD_RUNTIME:PollAlertCooldownProbe(trigger)
    if CastState.preview or CastState.alerted or CastState.active ~= true then
        return
    end
    if CD_RUNTIME.alertProbeState ~= "cooldown" then
        return
    end
    local now = GetNow()
    if (now - (CD_RUNTIME.alertProbeLastPollAt or 0)) < (CD_RUNTIME.alertProbeInterval or 0.08) then
        return
    end
    CD_RUNTIME.alertProbeLastPollAt = now
    self:RefreshAlertCooldownProbe(trigger or "tick")
end

local function ResolveSoundPath(db)
    db = db or activeDB or GetDB()
    if db.soundMode == "custom" then
        local path = Trim(db.customSoundPath)
        if path ~= "" then
            return path
        end
        return nil
    end

    if LSM and LSM.Fetch and db.lsmSound ~= "None" then
        local path = LSM:Fetch("sound", db.lsmSound, true)
        if path and path ~= 1 then
            return path
        end
    end
    return nil
end

local function PlaySoundPath(path, channel)
    if type(PlaySoundFile) ~= "function" or type(path) ~= "string" or path == "" then
        return false, "invalid-path"
    end
    channel = VALID_SOUND_CHANNELS[channel] and channel or defaults.soundChannel

    local ok, willPlay = pcall(PlaySoundFile, path, channel)
    local primaryWillPlay = ok and SafeBooleanValue(willPlay, nil) or nil
    if ok and primaryWillPlay ~= false then
        return true, "ok", channel
    end
    if channel ~= "Master" then
        local fallbackOk, fallbackWillPlay = pcall(PlaySoundFile, path, "Master")
        local fallbackCanPlay = fallbackOk and SafeBooleanValue(fallbackWillPlay, nil) or nil
        local fallbackPlayed = fallbackOk and fallbackCanPlay ~= false
        if fallbackPlayed then
            return true, "ok-master-fallback", "Master"
        end
    end
    return false, "play-failed", channel
end

local function PlayConfiguredSound(isTest)
    local db = activeDB or GetDB()
    local path = ResolveSoundPath(db)
    local channel = VALID_SOUND_CHANNELS[db.soundChannel] and db.soundChannel or defaults.soundChannel
    if not path then
        if isTest and YUI.Print then
            YUI:Print(T("message.no_sound", "No sound selected."))
        end
        return false, "no-sound-path"
    end
    local played, reason = PlaySoundPath(path, channel)
    if not played then
        return false, reason or "play-failed"
    end
    return true
end

local function ResolveCastDisplayName(cast)
    if not cast then return nil end
    local rawName = FirstRawDisplayValue(cast.displayNameRaw, cast.nameRaw)
    if rawName ~= nil then
        return rawName
    end
    local displayName = SafeTextValue(cast.displayName)
    if displayName then
        return displayName
    end
    local name = SafeTextValue(cast.name)
    if name then
        return name
    end
    local spellID = SafeRawValue(cast.spellID)
    if spellID and SpellAPI.GetName then
        local spellName = SpellAPI.GetName(spellID)
        spellName = SafeTextValue(spellName)
        if spellName then
            return spellName
        end
    end
    return T("preview.spell_name", "Focus Cast")
end

local function BuildCastKey(cast)
    if not cast then return nil end
    local displayType = SafeRawValue(cast.displayType)
    local isChannel = SafeBooleanValue(cast.isChannel, false)
    return SafeCastKeyPart(cast.spellID, SafeCastKeyPart(cast.name, "unknown"))
        .. ":"
        .. SafeCastKeyPart(cast.castID)
        .. ":"
        .. SafeCastKeyPart(cast.startTimeMS, "0")
        .. ":"
        .. SafeCastKeyPart(cast.endTimeMS, "0")
        .. ":"
        .. SafeCastKeyPart(displayType or (isChannel and "channel" or "cast"))
        .. ":"
        .. SafeCastKeyPart(cast.eventStartedAt)
end

local function ApplyCastToState(cast)
    local castKey = BuildCastKey(cast)
    local isNewCast = castKey ~= CastState.castKey
    if isNewCast then
        CastState.alerted = false
        CastState.durationAppliedKey = nil
        CastState.nativeMarkerKey = nil
        CastState.usingNativeDuration = false
    end

    local targetName, targetColor, targetSource, targetColorSource = ResolveFocusTargetDisplay(cast)
    CastState.active = true
    CastState.preview = false
    CastState.name = ResolveCastDisplayName(cast)
    CastState.targetName = targetName
    CastState.targetColor = targetColor
    CastState.targetSource = targetSource
    CastState.targetColorSource = targetColorSource
    CastState.texture = FirstRawDisplayValue(cast.displayTextureRaw, cast.textureRaw, cast.displayTexture, cast.texture)
    CastState.spellID = SafeRawValue(cast.spellID)
    CastState.castID = SafeRawValue(cast.castID)
    CastState.castKey = castKey
    local displayType = SafeRawValue(cast.displayType)
    CastState.isChannel = displayType == "channel" or SafeBooleanValue(cast.isChannel, false) == true
    CastState.startTimeMS = SafeNumberValue(cast.startTimeMS)
    CastState.endTimeMS = SafeNumberValue(cast.endTimeMS)
    CastState.durationObject = SafeRawValue(cast.durationObject)
    CastState.totalSeconds = SafeNumberValue(cast.totalSeconds)
    CastState.elapsedSeconds = SafeNumberValue(cast.elapsedSeconds)
    CastState.remainingSeconds = SafeNumberValue(cast.remainingSeconds)
    CastState.visualNotInterruptibleRaw = FirstRawDisplayValue(cast.visualNotInterruptibleRaw, cast.notInterruptibleRaw)
    CastState.interruptibilityPending = SafeBooleanValue(cast.interruptibilityPending, false) == true
    if SafeBooleanValue(cast.notInterruptibleKnown, false) == true then
        CastState.notInterruptibleKnown = true
        CastState.notInterruptible = SafeBooleanValue(cast.notInterruptible, false) == true
        CastState.interruptibilityPending = false
    elseif isNewCast then
        CastState.notInterruptibleKnown = false
        CastState.notInterruptible = false
    end
end

local function RefreshFocusTargetDisplay()
    if not (CastState.active and not CastState.preview) then return end
    CastState.targetName, CastState.targetColor, CastState.targetSource, CastState.targetColorSource = ResolveFocusTargetDisplay()
    ApplyCastBarTextAppearance(false)
end

local function ApplyFocusEventHints(cast)
    if not cast then return nil end
    if focusCastStartedAt and focusCastStartedAt > 0 then
        cast.eventStartedAt = focusCastStartedAt
    end
    if focusCastDisplayType then
        cast.displayType = focusCastDisplayType
    end
    if SafeBooleanValue(cast.notInterruptibleKnown, false) ~= true
        and focusCastStartedAt
        and focusCastStartedAt > 0
        and (GetNow() - focusCastStartedAt) < INTERRUPTIBILITY_GRACE_SECONDS then
        cast.interruptibilityPending = true
    end
    return cast
end

function FocusHelper_ApplyAppearance()
    local frame = FocusHelper_EnsureWidget()
    if not frame then return end
    local db = activeDB or GetDB()
    local barWidth = db.width

    if frame.SetCastBarSize then
        frame:SetCastBarSize(barWidth, db.height)
    else
        frame:SetSize(barWidth + db.height, db.height)
    end
    if frame.SetBarTexture then
        frame:SetBarTexture(GetStatusBarTexture(db))
    end
    ApplyCastBarColor()
    if frame.SetMarkerColor then
        frame:SetMarkerColor(db.markerColor)
    end
    ApplyCastBarTextAppearance(true)
    if YUI.Layout and YUI.Layout.RefreshFrame then
        YUI.Layout:RefreshFrame(LAYOUT_ID)
    end
end

local function ReadDurationValue(durationObject, methodName)
    if durationObject == nil or type(methodName) ~= "string" then
        return nil
    end
    local ok, value = pcall(function()
        local method = durationObject[methodName]
        if type(method) ~= "function" then return nil end
        return method(durationObject)
    end)
    if ok and not IsSecretValue(value) and value ~= nil then
        local convertOK, numberValue = pcall(tonumber, value)
        if convertOK and not IsSecretValue(numberValue) then
            return numberValue
        end
    end
    return nil
end

local function UpdateCastClock()
    if CastState.preview then
        local now = GetNow()
        local elapsed = (now - (CastState.previewStartedAt or now)) % PREVIEW_TOTAL_SECONDS
        CastState.totalSeconds = PREVIEW_TOTAL_SECONDS
        CastState.elapsedSeconds = elapsed
        CastState.remainingSeconds = PREVIEW_TOTAL_SECONDS - elapsed
        return
    end

    if CastState.durationObject then
        local total = ReadDurationValue(CastState.durationObject, "GetTotalDuration")
        local remaining = ReadDurationValue(CastState.durationObject, "GetRemainingDuration")
        local elapsed = ReadDurationValue(CastState.durationObject, "GetElapsedDuration")
        if total and total >= 0 then
            CastState.totalSeconds = total
        end
        if remaining and remaining >= 0 then
            CastState.remainingSeconds = remaining
        end
        if elapsed and elapsed >= 0 then
            CastState.elapsedSeconds = elapsed
        end
        local stateTotal = SafeNumberValue(CastState.totalSeconds)
        local stateElapsed = SafeNumberValue(CastState.elapsedSeconds)
        local stateRemaining = SafeNumberValue(CastState.remainingSeconds)
        if stateTotal and not stateElapsed and stateRemaining then
            CastState.elapsedSeconds = math.max(0, stateTotal - stateRemaining)
        end
        stateTotal = SafeNumberValue(CastState.totalSeconds)
        stateElapsed = SafeNumberValue(CastState.elapsedSeconds)
        stateRemaining = SafeNumberValue(CastState.remainingSeconds)
        if stateTotal and not stateRemaining and stateElapsed then
            CastState.remainingSeconds = math.max(0, stateTotal - stateElapsed)
        end
        stateTotal = SafeNumberValue(CastState.totalSeconds)
        stateRemaining = SafeNumberValue(CastState.remainingSeconds)
        if stateTotal and stateTotal > 0 and stateRemaining then
            return
        end
    end

    local startTimeMS = SafeNumberValue(CastState.startTimeMS)
    local endTimeMS = SafeNumberValue(CastState.endTimeMS)
    if startTimeMS and endTimeMS and endTimeMS >= startTimeMS then
        local now = GetNow()
        CastState.totalSeconds = math.max(0, (endTimeMS - startTimeMS) / 1000)
        CastState.elapsedSeconds = math.max(0, now - (startTimeMS / 1000))
        CastState.remainingSeconds = math.max(0, (endTimeMS / 1000) - now)
    end
end

local function UpdateMarker()
    local frame = Widget.frame
    if not frame then
        if Widget.marker then Widget.marker:Hide() end
        CastState.nativeMarkerKey = nil
        return
    end

    local readyAtElapsed
    if CastState.preview then
        readyAtElapsed = PREVIEW_MARKER_ELAPSED
    else
        local _, entry, remaining, reason, source, cooldownState, visualEntry, visualState = IsInterruptReady()
        entry = visualEntry or entry
        cooldownState = visualState or cooldownState
        if not (entry and entry.spellID) then
            if frame.HideMarker then frame:HideMarker() end
            CastState.nativeMarkerKey = nil
            return
        end
        if CastState.notInterruptibleKnown == true and CastState.notInterruptible == true then
            if frame.HideMarker then frame:HideMarker() end
            CastState.nativeMarkerKey = nil
            return
        end
        remaining = SafeNumberValue(remaining)
        local visualReadyRaw = cooldownState and cooldownState.readyRaw
        local cooldownDurationObject = cooldownState and cooldownState.durationObject

        if CastState.durationObject and frame.SetNativeMarkerFromDurations and (cooldownDurationObject or SpellAPI.GetCooldownDurationObject) then
            cooldownDurationObject = cooldownDurationObject or SpellAPI.GetCooldownDurationObject(entry.spellID)
            if cooldownDurationObject then
                local nativeMarkerKey = tostring(CastState.castKey or "")
                    .. ":" .. tostring(entry.spellID or "")
                    .. ":" .. tostring(reason or "cooldown")
                    .. ":" .. tostring(source or "unknown")
                    .. ":" .. tostring(CastState.isChannel == true)
                if CastState.nativeMarkerKey == nativeMarkerKey and frame.RefreshNativeMarkerVisibility then
                    if frame:RefreshNativeMarkerVisibility(CastState.visualNotInterruptibleRaw, visualReadyRaw) then
                        return
                    end
                    CastState.nativeMarkerKey = nil
                end
                local nativeOK = frame:SetNativeMarkerFromDurations(CastState.durationObject, cooldownDurationObject, CastState.isChannel, CastState.visualNotInterruptibleRaw, visualReadyRaw)
                if nativeOK then
                    CastState.nativeMarkerKey = nativeMarkerKey
                    return
                end
                CastState.nativeMarkerKey = nil
            end
        end

        if not remaining or remaining <= 0 then
            if frame.HideMarker then frame:HideMarker() end
            CastState.nativeMarkerKey = nil
            return
        end
        local elapsedSeconds = SafeNumberValue(CastState.elapsedSeconds)
        if not elapsedSeconds or elapsedSeconds < 0 then
            if frame.HideMarker then frame:HideMarker() end
            CastState.nativeMarkerKey = nil
            return
        end
        readyAtElapsed = elapsedSeconds + remaining
    end

    local totalSeconds = SafeNumberValue(CastState.totalSeconds)
    if not (totalSeconds and totalSeconds > 0) then
        if frame.HideMarker then frame:HideMarker() end
        CastState.nativeMarkerKey = nil
        return
    end

    readyAtElapsed = SafeNumberValue(readyAtElapsed)
    if not readyAtElapsed or readyAtElapsed <= 0 or readyAtElapsed >= totalSeconds then
        if frame.HideMarker then frame:HideMarker() end
        CastState.nativeMarkerKey = nil
        return
    end

    local xPercent = readyAtElapsed / totalSeconds
    if CastState.isChannel then
        xPercent = 1 - xPercent
    end
    if xPercent <= 0 or xPercent >= 1 then
        if frame.HideMarker then frame:HideMarker() end
        CastState.nativeMarkerKey = nil
        return
    end

    if frame.SetMarkerPercent then
        CastState.nativeMarkerKey = nil
        frame:SetMarkerPercent(xPercent)
    end
end

local function IsRetailAssumedInterruptibleEnabled()
    return YUI.IsRetail == true
end

local function ResolveUninterruptibleProbeForAlert()
    CD_RUNTIME:SetAlertSteelState("unknown", "none", "disabled")
    return nil, "probe-unknown"
end

local function ResolveInterruptibilityForAlert()
    if CastState.notInterruptibleKnown == true then
        if CastState.notInterruptible == true then
            CD_RUNTIME:SetAlertSteelState("true", "safe", "true")
            return false, "not-interruptible"
        end
        CD_RUNTIME:SetAlertSteelState("false", "safe", "false")
        return true, "confirmed"
    end

    local blockedByProbe, probeReason = ResolveUninterruptibleProbeForAlert()
    if blockedByProbe == true then
        CastState.interruptibilityPending = false
        return false, probeReason or "probe-not-interruptible"
    end

    if IsRetailAssumedInterruptibleEnabled() then
        CastState.interruptibilityPending = false
        return true, "assumed-immediate"
    end

    if CastState.interruptibilityPending == true then
        if focusCastStartedAt and focusCastStartedAt > 0 and (GetNow() - focusCastStartedAt) < INTERRUPTIBILITY_GRACE_SECONDS then
            return nil, "waiting"
        end
        CastState.interruptibilityPending = false
    end

    return false, "unknown"
end

local function TryPlayAlert()
    if CastState.preview then
        return
    end
    if CastState.alerted then
        return
    end
    local db = activeDB or GetDB()
    if not featureActive then
        return
    end
    if not runtimeActive then
        return
    end
    if not CastState.active then
        return
    end
    if not IsFocusExists() then
        return
    end

    local hostile = ResolveFocusHostilityForAlert()
    if hostile ~= true then
        CastState.interruptibilityPending = false
        return
    end

    local interruptible = ResolveInterruptibilityForAlert()
    if interruptible ~= true then
        return
    end

    local ready = CD_RUNTIME:IsInterruptReadyForAlert("alert-check")
    if ready == true then
        if IsAlertDedupBlocked() then
            CastState.alerted = true
            return
        end

        local soundPath = ResolveSoundPath(db)
        if not soundPath then
            return
        end
        CastState.alerted = true
        local played = PlayConfiguredSound(false)
        if played then
            lastAlertPlayedAt = GetNow()
            lastAlertFocusGUID = GetFocusGUIDForAlert()
        end
    end
end

local function FormatRemainingText()
    local remaining = SafeNumberValue(CastState.remainingSeconds)
    if not remaining then
        return ""
    end
    return string.format("%.1f", math.max(0, remaining))
end

local function ApplyCastProgress(frame)
    if not frame then return end
    local nativeDuration = false
    if not CastState.preview and CastState.durationObject and frame.SetCastDuration then
        if CastState.durationAppliedKey ~= CastState.castKey then
            nativeDuration = frame:SetCastDuration(CastState.durationObject, CastState.isChannel) == true
            CastState.durationAppliedKey = CastState.castKey
            CastState.usingNativeDuration = nativeDuration
        else
            nativeDuration = CastState.usingNativeDuration == true
        end
    elseif frame.ClearCastDuration then
        frame:ClearCastDuration()
        CastState.durationAppliedKey = nil
        CastState.usingNativeDuration = false
    end

    if nativeDuration then
        return
    end

    if frame.SetCastProgress then
        frame:SetCastProgress(SafeNumberValue(CastState.elapsedSeconds) or 0, SafeNumberValue(CastState.totalSeconds) or 0, CastState.isChannel)
    end
end

local function RenderCastState()
    local frame = FocusHelper_EnsureWidget()
    if not frame then return end

    FocusHelper_ApplyAppearance()
    UpdateCastClock()
    ApplyCastBarColor()
    ApplyCastBarTextAppearance()

    if frame.SetSpellIcon then
        local iconTexture = RawDisplayValue(CastState.texture)
        if iconTexture == nil then
            iconTexture = GetSpellTexture(CastState.spellID, FALLBACK_ICON)
        end
        frame:SetSpellIcon(iconTexture)
    end
    ApplyCastProgress(frame)
    SetCachedRemainingText(frame, FormatRemainingText())

    UpdateMarker()
    frame:Show()
    StartOnUpdate()
    TryPlayAlert()
    FocusHelper_ApplyUnavailableVisibility()
end

function FocusHelper_ShowPreview()
    if not featureActive then return end
    local db = activeDB or GetDB()
    if db.interruptEnabled ~= true then return end

    ResetCastState()
    CastState.active = true
    CastState.preview = true
    CastState.alerted = true
    CastState.name = T("preview.spell_name", "Focus Cast")
    CastState.targetName = T("preview.target_name", "Target Name")
    CastState.targetColor = RandomPreviewClassColor()
    CastState.targetSource = "preview"
    CastState.targetColorSource = "preview"
    CastState.texture = FALLBACK_ICON
    CastState.spellID = nil
    CastState.isChannel = false
    CastState.notInterruptibleKnown = true
    CastState.notInterruptible = false
    CastState.previewStartedAt = GetNow()
    RenderCastState()
end

local function HideIfNoPreview()
    if featureActive and settingsPreviewActive == true then
        FocusHelper_ShowPreview()
    else
        ResetCastState()
        HideWidget()
    end
end

function FocusHelper_RefreshFocusCast()
    if not (featureActive and runtimeActive) then
        HideIfNoPreview()
        return
    end
    if layoutPreviewActive then
        FocusHelper_ShowPreview()
        return
    end
    if not IsFocusExists() then
        if settingsPreviewActive == true then
            FocusHelper_ShowPreview()
        else
            ResetCastState()
            HideWidget()
        end
        return
    end

    local cast = UnitAPI.GetCastInfo and UnitAPI.GetCastInfo("focus") or nil
    if not cast then
        if settingsPreviewActive == true then
            FocusHelper_ShowPreview()
        else
            ResetCastState()
            HideWidget()
        end
        return
    end
    ApplyFocusEventHints(cast)
    ApplyCastToState(cast)
    RenderCastState()
end

local function FocusHelperOnUpdateImpl()
    if not CastState.active then
        HideWidget()
        return
    end

    UpdateCastClock()
    local remainingSeconds = SafeNumberValue(CastState.remainingSeconds)
    if not CastState.preview and remainingSeconds and remainingSeconds <= 0 then
        FocusHelper_RefreshFocusCast("expired")
        return
    end

    local frame = Widget.frame
    ApplyCastProgress(frame)
    ApplyCastBarColor()
    ApplyCastBarTextAppearance()
    SetCachedRemainingText(frame, FormatRemainingText())
    UpdateMarker()
    CD_RUNTIME:PollAlertCooldownProbe("tick")
    TryPlayAlert()
    FocusHelper_ApplyUnavailableVisibility()
end

function FocusHelper_OnUpdate()
    local cpuWatchdog = YUI.CPUWatchdog
    local cpuStartedAt = cpuWatchdog and cpuWatchdog.timingActive and cpuWatchdog:BeginProbeTiming()
    FocusHelperOnUpdateImpl()
    if cpuStartedAt then cpuWatchdog:EndProbeTiming("component.focus-helper", cpuStartedAt) end
end

local function ExtractInterruptSpellID(...)
    for index = select("#", ...), 1, -1 do
        local value = SafeNumberValue(select(index, ...))
        if value and interruptSpellIDs[value] then
            return value
        end
    end
    return nil
end

local function OnInterruptSucceeded(event, ...)
    local spellID = ExtractInterruptSpellID(...)
    if spellID then
        local entry = interruptSpellIDs[spellID]
        CD_RUNTIME:InvalidateReadiness()
        CD_RUNTIME:StartLearnedCooldown(spellID, entry, "succeeded")
        CD_RUNTIME:RefreshAlertCooldownProbe("succeeded")
        if CastState.active then
            ApplyCastBarColor()
            UpdateMarker()
        end
    end
end

local function OnFocusCastEvent(event)
    if event == "UNIT_TARGET" then
        RefreshFocusTargetDisplay()
        return
    end
    if event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START" then
        focusCastStartedAt = GetNow()
        focusCastDisplayType = event == "UNIT_SPELLCAST_START" and "cast" or "channel"
        if CD_RUNTIME.ClearAlertCooldownProbe then
            CD_RUNTIME:ClearAlertCooldownProbe("new-cast")
        end
        CastState.alerted = false
        CastState.notInterruptibleKnown = false
        CastState.notInterruptible = false
        CastState.interruptibilityPending = true
        FocusHelper_RefreshFocusCast(event)
        return
    end
    if event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        if not CastState.active then
            FocusHelper_RefreshFocusCast(event)
            if not CastState.active then return end
        end
        CastState.notInterruptibleKnown = true
        CastState.notInterruptible = false
        CastState.interruptibilityPending = false
        RenderCastState()
        return
    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        if not CastState.active then
            FocusHelper_RefreshFocusCast(event)
            if not CastState.active then return end
        end
        CastState.notInterruptibleKnown = true
        CastState.notInterruptible = true
        CastState.interruptibilityPending = false
        RenderCastState()
        return
    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        HideIfNoPreview()
        return
    end

    FocusHelper_RefreshFocusCast(event)
end

local function OnRuntimeEvent(event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnInterruptSucceeded(event, ...)
        return
    end

    if event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "ACTIVE_TALENT_GROUP_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "SPELLS_CHANGED" then
        RebuildInterruptData(event)
        RefreshInterruptCooldownSnapshot()
        FocusHelper_RefreshFocusCast(event)
        return
    end

    if event == "PLAYER_FOCUS_CHANGED" then
        ResetCastState()
        FocusHelper_RefreshFocusCast(event)
        return
    end

    if event == "SPELL_UPDATE_COOLDOWN" then
        CD_RUNTIME:InvalidateReadiness()
        if CastState.active ~= true then
            return
        end
        RefreshInterruptCooldownSnapshot()
        ApplyCastBarColor()
        UpdateMarker()
        CD_RUNTIME:RefreshAlertCooldownProbe("spell-update")
        TryPlayAlert()
        return
    end

end

local function BindRuntimeEvents()
    if not (YUI.Event and YUI.Event.On) then return end
    YUI.Event:OffOwner(EventOwner)

    YUI.Event:On("UNIT_SPELLCAST_START", OnFocusCastEvent, EventOwner, { unit = "focus", moduleId = MODULE_ID })
    YUI.Event:On("UNIT_SPELLCAST_CHANNEL_START", OnFocusCastEvent, EventOwner, { unit = "focus", moduleId = MODULE_ID })
    YUI.Event:On("UNIT_SPELLCAST_CHANNEL_UPDATE", OnFocusCastEvent, EventOwner, { unit = "focus", moduleId = MODULE_ID })
    YUI.Event:On("UNIT_SPELLCAST_EMPOWER_START", OnFocusCastEvent, EventOwner, { unit = "focus", moduleId = MODULE_ID })
    YUI.Event:On("UNIT_SPELLCAST_EMPOWER_UPDATE", OnFocusCastEvent, EventOwner, { unit = "focus", moduleId = MODULE_ID })
    YUI.Event:On("UNIT_SPELLCAST_STOP", OnFocusCastEvent, EventOwner, { unit = "focus", moduleId = MODULE_ID })
    YUI.Event:On("UNIT_SPELLCAST_CHANNEL_STOP", OnFocusCastEvent, EventOwner, { unit = "focus", moduleId = MODULE_ID })
    YUI.Event:On("UNIT_SPELLCAST_EMPOWER_STOP", OnFocusCastEvent, EventOwner, { unit = "focus", moduleId = MODULE_ID })
    YUI.Event:On("UNIT_SPELLCAST_FAILED", OnFocusCastEvent, EventOwner, { unit = "focus", moduleId = MODULE_ID })
    YUI.Event:On("UNIT_SPELLCAST_INTERRUPTED", OnFocusCastEvent, EventOwner, { unit = "focus", moduleId = MODULE_ID })
    YUI.Event:On("UNIT_SPELLCAST_INTERRUPTIBLE", OnFocusCastEvent, EventOwner, { unit = "focus", moduleId = MODULE_ID })
    YUI.Event:On("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", OnFocusCastEvent, EventOwner, { unit = "focus", moduleId = MODULE_ID })
    YUI.Event:On("UNIT_TARGET", OnFocusCastEvent, EventOwner, { unit = "focus", moduleId = MODULE_ID })
    YUI.Event:On("UNIT_SPELLCAST_SUCCEEDED", OnRuntimeEvent, EventOwner, { units = { "player", "pet" }, moduleId = MODULE_ID })

    YUI.Event:On("PLAYER_ENTERING_WORLD", OnRuntimeEvent, EventOwner, { moduleId = MODULE_ID })
    YUI.Event:On("PLAYER_FOCUS_CHANGED", OnRuntimeEvent, EventOwner, { moduleId = MODULE_ID })
    YUI.Event:On("PLAYER_SPECIALIZATION_CHANGED", OnRuntimeEvent, EventOwner, { moduleId = MODULE_ID })
    YUI.Event:On("ACTIVE_TALENT_GROUP_CHANGED", OnRuntimeEvent, EventOwner, { moduleId = MODULE_ID })
    YUI.Event:On("PLAYER_TALENT_UPDATE", OnRuntimeEvent, EventOwner, { moduleId = MODULE_ID })
    YUI.Event:On("SPELLS_CHANGED", OnRuntimeEvent, EventOwner, { moduleId = MODULE_ID })
    YUI.Event:On("SPELL_UPDATE_COOLDOWN", OnRuntimeEvent, EventOwner, { moduleId = MODULE_ID })
end

local function EnableRuntime()
    if runtimeActive then
        FocusHelper_RefreshFocusCast("enable-refresh")
        return
    end
    runtimeActive = true
    RebuildInterruptData("enable")
    RefreshInterruptCooldownSnapshot()
    FocusHelper_EnsureWidget()
    BindRuntimeEvents()
    FocusHelper_RefreshFocusCast("enable")
end

local function DisableRuntime()
    runtimeActive = false
    layoutPreviewActive = false
    settingsPreviewActive = false
    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(EventOwner)
    end
    ResetCastState()
    lastAlertPlayedAt = 0
    lastAlertFocusGUID = nil
    CD_RUNTIME:InvalidateReadiness()
    if CD_RUNTIME.ClearLearnedCooldown then
        CD_RUNTIME:ClearLearnedCooldown("disable", true)
    end
    HideWidget()
end

local function RefreshRuntime()
    local db = GetDB()
    FocusHelper_EnsureWidget()
    FocusHelper_ApplyAppearance()
    if featureActive and db.interruptEnabled == true then
        EnableRuntime()
    else
        DisableRuntime()
    end
    if featureActive and db.interruptEnabled == true and settingsPreviewActive == true and (not CastState.active or CastState.preview) then
        FocusHelper_ShowPreview()
    elseif not runtimeActive then
        HideWidget()
    end
    if featureActive then
        FocusHelper:RefreshSubFeatures(db)
    end
end

local function RegisterProfileCallbacks()
    if profileCallbacksRegistered then return end
    if not (YUI.DB and YUI.DB.GetAceDB) then return end
    local db = YUI.DB:GetAceDB(PRODUCT_ID)
    if not (db and db.RegisterCallback) then return end
    db.RegisterCallback(ProfileOwner, "OnProfileChanged", "OnProfileChanged")
    db.RegisterCallback(ProfileOwner, "OnProfileCopied", "OnProfileChanged")
    db.RegisterCallback(ProfileOwner, "OnProfileReset", "OnProfileChanged")
    profileCallbacksRegistered = true
end

function ProfileOwner:OnProfileChanged()
    featureActive = Components.IsEnabled and Components:IsEnabled(FEATURE_KEY) or false
    FocusHelper.featureActive = featureActive == true
    FocusHelper:ToggleSubFeatures(false, GetDB())
    DisableRuntime()
    if featureActive then
        FocusHelper:ToggleSubFeatures(true, GetDB())
        RefreshRuntime()
    end
end

local function BuildSoundChannelOptions()
    local options = {}
    for _, item in ipairs(SOUND_CHANNELS) do
        options[#options + 1] = {
            text = T(item.key, item.fallback),
            value = item.value,
        }
    end
    return options
end

local function BuildSoundModeOptions()
    local options = {}
    for _, item in ipairs(SOUND_MODE_OPTIONS) do
        options[#options + 1] = {
            text = T(item.textKey, item.fallback),
            value = item.value,
        }
    end
    return options
end

local function BuildTextOutlineOptions()
    if GUI2 and GUI2.Form and GUI2.Form.BuildFontOutlineOptions then
        return GUI2.Form:BuildFontOutlineOptions()
    end
    return {
        { text = "None", value = "none" },
        { text = "Outline", value = "outline" },
        { text = "Thick Outline", value = "thick" },
        { text = "Shadow", value = "shadow" },
        { text = "Outline + Shadow", value = "outlineShadow" },
    }
end

local function OpenLayoutEditMode()
    FocusHelper_EnsureWidget()
    if YUI.Layout and YUI.Layout.OpenEditMode then
        YUI.Layout:OpenEditMode(FEATURE_KEY)
    end
end

local function RequestSettingsRefresh(feature)
    if settingsRefreshQueued then return end
    local refresh = feature and feature.RefreshCurrentModule
    if type(refresh) ~= "function" then return end
    settingsRefreshQueued = true
    local function Run()
        settingsRefreshQueued = false
        refresh()
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, Run)
    else
        Run()
    end
end

local function AddDivider(options, label)
    options[#options + 1] = { type = "divider", label = label, alignLeft = true, width = SECTION_WIDTH }
end

local function AddAlignedFields(options, fields, layout)
    layout = type(layout) == "table" and layout or {}
    options[#options + 1] = {
        type = "custom",
        retainedFields = fields,
        requires = layout.requires,
        width = SECTION_WIDTH,
        render = function(parent, x, y, width)
            local Settings = YUI.Settings
            if not (Settings and Settings.RenderAlignedFields) then
                return SECTION_WIDTH, 1
            end

            local _, gridWidth, gridHeight = Settings:RenderAlignedFields(parent, {
                x = x,
                y = y,
                width = math.min(width or SECTION_WIDTH, SECTION_WIDTH),
                columns = layout.columns or 2,
                labelPosition = layout.labelPosition or "top",
                columnGap = layout.columnGap or FIELD_GAP,
                labelWidth = layout.labelWidth or LABEL_WIDTH,
                labelGap = layout.labelGap or LABEL_GAP,
                bodyWidth = layout.bodyWidth or CONTROL_WIDTH,
                valueWidth = layout.valueWidth or INPUT_WIDTH,
                valueGap = layout.valueGap or LABEL_GAP,
                rowHeight = layout.rowHeight or 32,
                rowGap = layout.rowGap or 10,
                fields = fields,
            })
            return gridWidth, gridHeight
        end,
    }
end

local function AddAlignedFieldGroup(options, label, fields, layout)
    AddDivider(options, label)
    AddAlignedFields(options, fields, layout)
end

local function AddInterruptTopRow(options, enableField, buttons)
    local fields = { enableField }
    options[#options + 1] = {
        type = "custom",
        retainedFields = fields,
        keepWhenEmpty = true,
        width = SECTION_WIDTH,
        render = function(parent, x, y, width)
            local GUI2 = YUI.GUI2
            local Settings = YUI.Settings
            if not (GUI2 and GUI2.CreateFrame and GUI2.Form and GUI2.Form.CreateButton and Settings and Settings.RenderAlignedFields) then
                return SECTION_WIDTH, 1
            end

            local buttonGap = 8
            local buttonCount = #buttons
            local availableWidth = math.min(width or SECTION_WIDTH, SECTION_WIDTH)
            local buttonX = #fields > 0 and FIELD_WIDTH + FIELD_GAP or 0
            local buttonWidth = math.floor((availableWidth - buttonX - (buttonCount - 1) * buttonGap) / math.max(buttonCount, 1))
            local row = GUI2:CreateFrame(parent, {
                width = availableWidth,
                height = 32,
            })
            row:SetPoint("TOPLEFT", x, y)

            if #fields > 0 then Settings:RenderAlignedFields(row, {
                x = 0,
                y = 0,
                width = FIELD_WIDTH,
                columns = 1,
                columnGap = FIELD_GAP,
                labelWidth = LABEL_WIDTH,
                labelGap = LABEL_GAP,
                bodyWidth = CONTROL_WIDTH,
                valueWidth = INPUT_WIDTH,
                valueGap = LABEL_GAP,
                rowHeight = 32,
                rowGap = 10,
                fields = fields,
            }) end

            for index, buttonDef in ipairs(buttons) do
                local button = GUI2.Form:CreateButton(row, {
                    text = buttonDef.text,
                    width = buttonWidth,
                    height = 28,
                    fontSizeKey = "font.size.md",
                    tone = buttonDef.tone,
                    onClick = buttonDef.onClick,
                })
                if button.text and button.text.SetWidth then
                    button.text:SetWidth(math.max(buttonWidth - 8, 1))
                    button.text:SetWordWrap(false)
                end
                button:SetPoint("LEFT", row, "LEFT", buttonX + (index - 1) * (buttonWidth + buttonGap), 0)
            end

            return availableWidth, 32
        end,
    }
end

local function BuildInterruptOptions(feature)
    local db = GetDB()
    local function Refresh()
        RefreshRuntime()
    end

    local options = {}
    AddInterruptTopRow(options, {
        type = "checkbox",
        settingsToggle = "interrupt",
        searchKey = "settings.enable_interrupt",
        label = T("settings.enable_interrupt", "Enable"),
        get = function() return db.interruptEnabled == true end,
        set = function(value)
            db.interruptEnabled = value == true
            Refresh()
        end,
    }, {
        {
            text = settingsPreviewActive and T("settings.preview_stop", "Close preview") or T("settings.preview", "Preview cast bar"),
            onClick = function()
                settingsPreviewActive = not settingsPreviewActive
                Refresh()
                RequestSettingsRefresh(feature)
            end,
        },
        {
            text = T("settings.open_layout", "Edit Position"),
            onClick = OpenLayoutEditMode,
        },
        {
            text = T("settings.test_sound", "Test Sound"),
            onClick = function()
                PlayConfiguredSound(true)
            end,
        },
    })

    AddDivider(options, T("settings.visual", "Visual"))
    AddAlignedFields(options, {
        {
            type = "texture",
            label = T("settings.bar_texture", "Bar texture"),
            layoutPreset = "inlineSelector",
            default = defaults.barTexture,
            get = function() return db.barTexture end,
            set = function(value)
                db.barTexture = type(value) == "string" and value or defaults.barTexture
                Refresh()
            end,
        },
    })

    AddAlignedFields(options, {
        {
            type = "slider",
            label = T("settings.width", "Width"),
            min = MIN_WIDTH,
            max = MAX_WIDTH,
            step = 1,
            get = function() return db.width end,
            set = function(value)
                db.width = ClampNumber(value, MIN_WIDTH, MAX_WIDTH, DEFAULT_WIDTH)
                Refresh()
            end,
        },
        {
            type = "slider",
            label = T("settings.height", "Height"),
            min = MIN_HEIGHT,
            max = MAX_HEIGHT,
            step = 1,
            get = function() return db.height end,
            set = function(value)
                db.height = ClampNumber(value, MIN_HEIGHT, MAX_HEIGHT, DEFAULT_HEIGHT)
                Refresh()
            end,
        },
    })

    AddAlignedFields(options, {
        {
            type = "color",
            label = T("settings.uninterruptible_color", "Uninterruptible"),
            layoutPreset = "compactColor",
            hasAlpha = true,
            get = function() return db.uninterruptibleColor end,
            default = defaults.uninterruptibleColor,
            set = function(value)
                db.uninterruptibleColor = NormalizeColor(value, defaults.uninterruptibleColor)
                Refresh()
            end,
        },
        {
            type = "color",
            label = T("settings.cooldown_color", "Interrupt CD"),
            layoutPreset = "compactColor",
            hasAlpha = true,
            get = function() return db.cooldownColor end,
            default = DEFAULT_COOLDOWN_COLOR,
            set = function(value)
                db.cooldownColor = NormalizeColor(value, DEFAULT_COOLDOWN_COLOR)
                Refresh()
            end,
        },
        {
            type = "color",
            label = T("settings.ready_color", "Interrupt Ready"),
            layoutPreset = "compactColor",
            hasAlpha = true,
            get = function() return db.readyColor end,
            default = DEFAULT_READY_COLOR,
            set = function(value)
                db.readyColor = NormalizeColor(value, DEFAULT_READY_COLOR)
                Refresh()
            end,
        },
        {
            type = "color",
            label = T("settings.marker_color", "Ready Position"),
            layoutPreset = "compactColor",
            hasAlpha = true,
            get = function() return db.markerColor end,
            default = DEFAULT_MARKER_COLOR,
            set = function(value)
                db.markerColor = NormalizeColor(value, DEFAULT_MARKER_COLOR)
                Refresh()
            end,
        },
    })

    AddAlignedFieldGroup(options, T("settings.interrupt_text", "文字与状态"), {
        {
            type = "font",
            label = T("settings.text_font", "字体"),
            default = DEFAULT_TEXT_FONT,
            prependOptions = function()
                return {
                    {
                        text = T("settings.text_font_default", "默认"),
                        value = DEFAULT_TEXT_FONT,
                        fontPath = GetDefaultTextFontPath(),
                    },
                }
            end,
            get = function() return db.textFont end,
            set = function(value)
                db.textFont = type(value) == "string" and value ~= "" and value or DEFAULT_TEXT_FONT
                Widget.lastTextFont = nil
                Widget.lastTextFontPath = nil
                Refresh()
            end,
        },
        {
            type = "slider",
            label = T("settings.countdown_text_size", "Time text"),
            min = 8,
            max = 24,
            step = 1,
            get = function() return db.timeFontSize end,
            set = function(value)
                db.timeFontSize = ClampNumber(value, 8, 24, DEFAULT_TIME_FONT_SIZE)
                Refresh()
            end,
        },
        {
            type = "slider",
            label = T("settings.spell_name_text_size", "Spell text"),
            min = 8,
            max = 24,
            step = 1,
            get = function() return db.spellNameFontSize end,
            set = function(value)
                db.spellNameFontSize = ClampNumber(value, 8, 24, DEFAULT_NAME_FONT_SIZE)
                Refresh()
            end,
        },
        {
            type = "slider",
            label = T("settings.target_name_text_size", "Target text"),
            min = 8,
            max = 24,
            step = 1,
            get = function() return db.targetNameFontSize end,
            set = function(value)
                db.targetNameFontSize = ClampNumber(value, 8, 24, DEFAULT_NAME_FONT_SIZE)
                Refresh()
            end,
        },
        {
            type = "dropdown",
            label = T("settings.text_outline", "Text outline"),
            options = BuildTextOutlineOptions,
            default = defaults.textOutlineMode,
            get = function() return db.textOutlineMode end,
            set = function(value)
                db.textOutlineMode = VALID_TEXT_OUTLINE_MODES[value] and value or defaults.textOutlineMode
                Refresh()
            end,
        },
        {
            type = "dropdown",
            label = T("settings.unavailable_display", "When unavailable"),
            options = function()
                return {
                    { text = T("settings.unavailable_display_show", "Show cast bar"), value = "show" },
                    { text = T("settings.unavailable_display_hide", "Hide cast bar"), value = "hide" },
                }
            end,
            default = defaults.unavailableDisplayMode,
            get = function() return db.unavailableDisplayMode end,
            set = function(value)
                db.unavailableDisplayMode = (value == "show" or value == "hide") and value or defaults.unavailableDisplayMode
                Refresh()
            end,
        },
        {
            type = "slider",
            hidden = true,
            label = T("settings.hide_cd_threshold", "Interrupt CD Threshold"),
            min = 0,
            max = 10,
            step = 0.1,
            get = function() return db.hideCooldownThreshold end,
            set = function(value)
                db.hideCooldownThreshold = ClampNumber(value, 0, 10, defaults.hideCooldownThreshold)
                Refresh()
            end,
        },
    })

    AddAlignedFieldGroup(options, T("settings.sound", "Sound"), {
        {
            type = "dropdown",
            label = T("settings.sound_mode", "Sound source"),
            options = BuildSoundModeOptions,
            default = defaults.soundMode,
            get = function() return db.soundMode end,
            set = function(value)
                db.soundMode = value == "custom" and "custom" or "lsm"
                Refresh()
                RequestSettingsRefresh(feature)
            end,
        },
        {
            type = "dropdown",
            label = T("settings.sound_channel", "Sound channel"),
            options = BuildSoundChannelOptions,
            default = defaults.soundChannel,
            get = function() return db.soundChannel end,
            set = function(value)
                db.soundChannel = VALID_SOUND_CHANNELS[value] and value or defaults.soundChannel
            end,
        },
    })

    options[#options + 1] = {
        type = "sound",
        requires = function() return db.soundMode == "lsm" end,
        label = T("settings.lsm_sound", "Library sound"),
        inlineLabel = true,
        width = FIELD_WIDTH,
        labelWidth = LABEL_WIDTH,
        gap = LABEL_GAP,
        controlWidth = CONTROL_WIDTH,
        default = defaults.lsmSound,
        get = function() return db.lsmSound end,
        set = function(value)
            db.lsmSound = type(value) == "string" and value or defaults.lsmSound
        end,
    }
    AddAlignedFields(options, {
        {
            type = "editbox",
            label = T("settings.custom_sound_path", "Custom sound path"),
            span = "full",
            get = function() return db.customSoundPath end,
            set = function(value)
                db.customSoundPath = type(value) == "string" and value or ""
            end,
        },
    }, { columns = 1, requires = function() return db.soundMode == "custom" end })
    options[#options + 1] = {
        type = "text",
        requires = function() return db.soundMode == "custom" end,
        label = T("settings.custom_sound_path_example", "Example: Interface\\AddOns\\YourAddon\\Media\\alert.ogg"),
        width = SECTION_WIDTH,
        colorKey = "color.text.secondary",
    }

    return options
end

local function GetSubFeatureStates()
    local db = Components:CopyConfigSnapshot(CONFIG_KEY, defaults, PRODUCT_ID)
    if not db then return {} end
    local rows = {}
    local keys = { interrupt = "interruptEnabled", quickFocus = "quickFocusEnabled",
        focusMarker = "focusMarkerEnabled", focusAnnounce = "focusAnnounceEnabled" }
    for _, tab in ipairs(SETTINGS_TABS) do
        if tab.id == "interrupt" or FocusHelper.subFeatures[tab.id] then
            local row = { label = T(tab.labelKey, tab.fallback), enabled = db[keys[tab.id]] == true }
            if (tab.id == "focusMarker" or tab.id == "focusAnnounce") and db.quickFocusEnabled ~= true then
                row.requires = T("settings.tab_quick_focus", "Quick Focus")
            end
            rows[#rows + 1] = row
        end
    end
    return rows
end

local function GetOptions(feature)
    local db = GetDB()
    local sections = {}
    local coreLocale = YUI.Locale:Get("Core")
    for _, tab in ipairs(SETTINGS_TABS) do
        local subFeature = FocusHelper.subFeatures[tab.id]
        local options = tab.id == "interrupt" and BuildInterruptOptions(feature)
            or subFeature and subFeature.BuildOptions and subFeature:BuildOptions(db, feature)
            or { { type = "text", label = T("settings.feature_coming_soon", "This feature is coming soon.") } }
        local details, toggles = YUI.GUI2:SplitFeatureSettingsOptions(options)
        local section = { id = tab.id, label = T(tab.labelKey, tab.fallback),
            toggle = toggles[tab.id], options = details }
        if tab.id == "focusMarker" or tab.id == "focusAnnounce" then
            section.getNote = function()
                if db.quickFocusEnabled ~= true then
                    return string.format(coreLocale["settings.general.subfeature_requires"] or "Requires: %s",
                        T("settings.tab_quick_focus", "Quick Focus"))
                end
            end
        end
        sections[#sections + 1] = section
    end
    return YUI.GUI2:BuildFeatureSettingsLayout(feature, {
        sections = sections, selected = NormalizeSettingsTab(activeSettingsTab),
        onSelect = function(id, previous)
            if previous == "interrupt" then
                settingsPreviewActive = false
                if not layoutPreviewActive and CastState.preview then HideIfNoPreview() end
            end
            local previousFeature = FocusHelper.subFeatures[previous]
            if previousFeature and previousFeature.OnSettingsLeave then previousFeature:OnSettingsLeave(db) end
            activeSettingsTab = id
        end,
    })
end

local function ToggleFeature(enable)
    featureActive = enable == true
    FocusHelper.featureActive = featureActive
    RegisterProfileCallbacks()
    FocusHelper:ToggleSubFeatures(featureActive, GetDB())
    if featureActive then
        RefreshRuntime()
    else
        DisableRuntime()
    end
end

Components:RegisterFeature(FEATURE_KEY, {
    name = T("name", "Focus Helper"),
    description = T("description", "Shows a focus cast bar and plays an interrupt alert when your interrupt is ready."),
    default = false,
    settingsMode = "inline",
    product = PRODUCT_ID,
    storageKey = FEATURE_KEY,
    tags = { "战斗辅助" },
    sourceRoot = "Components\\FocusHelper",
    versions = { "forever", "mainline", "wrath" },
    callback = ToggleFeature,
    GetOptions = GetOptions,
    GetSubFeatureStates = GetSubFeatureStates,
    OnSettingsLeave = function()
        settingsPreviewActive = false
        if not layoutPreviewActive and CastState.preview then
            HideIfNoPreview()
        end
        for _, id in ipairs(FocusHelper.subFeatureOrder) do
            local subFeature = FocusHelper.subFeatures[id]
            if subFeature and subFeature.OnSettingsLeave then
                subFeature:OnSettingsLeave(GetDB())
            end
        end
    end,
})

if YUI.Event and YUI.Event.Once then
    YUI.Event:Once("YUI_DB_READY", function()
        RegisterProfileCallbacks()
    end, ProfileOwner, {
        moduleId = MODULE_ID,
        phase = "YUI_DB_READY",
    })
end

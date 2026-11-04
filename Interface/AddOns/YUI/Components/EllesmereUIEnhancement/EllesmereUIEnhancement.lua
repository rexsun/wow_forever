local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and (YUI.IsRetail == true or YUI.IsForever == true)) then return end

local Components = YUI.Components
if not Components then return end
if Components.features and Components.features.EllesmereUIEnhancement then return end

local Event = YUI.Event
local System = YUI.API and YUI.API.System
local GUI2 = YUI.GUI2
local Appearance = GUI2 and GUI2.WindowAppearance
local L = YUI.Locale and YUI.Locale:Get("EllesmereUIEnhancement") or {}

local FEATURE_KEY = "EllesmereUIEnhancement"
local CONFIG_KEY = "EllesmereUIEnhancement_Config"
local PRODUCT_ID = YUI.GetAddonProductId
    and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId
    or "suite"
local MODULE_ID = "component:" .. FEATURE_KEY
local WINDOW_BORDER_ATLAS = "AdventureMap_TopBorder"
local MAX_SOCIAL_TABS = 8
local FRIENDS_BACKGROUND_COLOR = { 0.03, 0.045, 0.05, 1 }
local COLOR_TOLERANCE = 0.012
local CLEAN_BORDER_COLOR = { 0.42, 0.45, 0.48, 0.90 }
local VISUAL_HOST_PREFIX = "YUI_EllesmereUIEnhancement_Host"
local MAIL_FILL_COLOR = { 0.02, 0.02, 0.02, 1 }
local MAIL_RIGHT_INSET = 8
local ALPHA_EPSILON = 0.001
local AUCTIONATOR_OWNER = "blizzard:auctionhouse:auctionator"

local PRESET_MODERN = "ellesmereModern"
local PRESET_CHARCOAL = "charcoalPilot"
local PRESET_YUI = "yuiBlueGray"
local PRESET_DEEP = "deepSeaGlass"
local PRESET_CRIMSON = "crimsonGlass"
local PRESET_SOLID = "solid"
local TAB_COLOR_AUTO = "auto"
local TAB_COLOR_CUSTOM = "custom"

local DEFAULT_MODERN_COLOR = { 0.16, 0.14, 0.12, 1 }
local DEFAULT_DEEP_COLOR = { 9 / 255, 24 / 255, 38 / 255, 1 }
local DEFAULT_CRIMSON_COLOR = { 42 / 255, 13 / 255, 18 / 255, 1 }
local DEFAULT_YUI_COLOR = { 0.098, 0.125, 0.150, 1 }
local DEFAULT_SOLID_COLOR = { 15 / 255, 28 / 255, 41 / 255, 1 }
local DEFAULT_TAB_COLOR = { 0.11, 0.09, 0.075, 0.94 }
local SETTINGS_FIELD_WIDTH = 220
local SETTINGS_FIELD_GAP = 16
local SETTINGS_LABEL_WIDTH = 80
local SETTINGS_CONTROL_GAP = 10
local SETTINGS_CONTROL_WIDTH = SETTINGS_FIELD_WIDTH - SETTINGS_LABEL_WIDTH - SETTINGS_CONTROL_GAP
local SETTINGS_VALUE_WIDTH = 48
local CHARACTER_DETAIL_FONT_BASE_SIZE = 10
local DEFAULT_CHARACTER_DETAIL_FONT_SIZE = 13
local CHARACTER_DETAIL_FONT_MIN_SIZE = 9
local CHARACTER_DETAIL_FONT_MAX_SIZE = 16
local CHARACTER_DETAIL_SCAN_LIMIT = 256
local DEFAULT_MERCHANT_ITEM_NAME_FONT_SIZE = 13
local MERCHANT_ITEM_NAME_FONT_MIN_SIZE = 9
local MERCHANT_ITEM_NAME_FONT_MAX_SIZE = 16
local TAB_TEXT_SELECTED_ALPHA = 1
local TAB_TEXT_INACTIVE_ALPHA = 0.5
local TAB_ACTIVE_HIGHLIGHT = { 1, 1, 1, 0.02 }
local AUCTIONATOR_TAB_HEIGHT_TRIM = 2
local DEFAULTS = {
    beautifySkinBackground = true,
    backgroundPreset = PRESET_YUI,
    pilotBasePreset = PRESET_MODERN,
    solidColor = DEFAULT_SOLID_COLOR,
    backgroundDarken = 0,
    backgroundTransparency = 0,
    simplifyWindowBorder = true,
    windowShadow = true,
    damageMeterMythicReset = true,
    damageMeterRaidPrompt = true,
    damageMeterDungeonPrompt = false,
    tabFontSize = 13,
    characterDetailFontSize = DEFAULT_CHARACTER_DETAIL_FONT_SIZE,
    merchantItemNameFontSize = DEFAULT_MERCHANT_ITEM_NAME_FONT_SIZE,
    abbreviateHotkeys = false,
    questTrackerScroll = false,
    hotkeyAliases = "",
    tabColorMode = TAB_COLOR_AUTO,
    tabColor = DEFAULT_TAB_COLOR,
    _migrationVersion = 0,
}

local runtime = {
    pilotPreset = PRESET_CHARCOAL,
    pilotTabStyle = {
        depth = 9 / 255, selectedLift = 8 / 255, hoverLift = 4 / 255,
        topAlpha = 0.07, selectedTopAlpha = 0.03, bottomAlpha = 0.32,
    },
    -- ESC 使用独立的近黑配色，不参与窗口配色和背景暗化。
    menuStyle = {
        panel = { top = { 16 / 255, 18 / 255, 22 / 255, 1 }, bottom = { 9 / 255, 10 / 255, 13 / 255, 1 } },
        border = { 56 / 255, 62 / 255, 72 / 255, 0.95 },
        button = {
            background = { top = { 36 / 255, 40 / 255, 46 / 255, 1 }, bottom = { 21 / 255, 24 / 255, 29 / 255, 1 } },
            border = { 61 / 255, 69 / 255, 79 / 255, 0.9 },
            topBorder = { 82 / 255, 93 / 255, 106 / 255, 0.95 },
            bottomBorder = { 43 / 255, 49 / 255, 58 / 255, 0.95 },
            textColor = { 0.87, 0.87, 0.88, 1 },
        },
        hover = {
            top = { 0.16, 0.48, 0.67, 0.16 }, bottom = { 0.08, 0.25, 0.36, 0.06 },
            edge = { 0.30, 0.72, 0.92, 0.70 },
        },
    },
    shellUnderlayLayers = { -8, -7, -6 },
    menuUnderlayLayers = { 0 },
    isForever = YUI.IsForever == true,
    foreverStatsBoxes = setmetatable({}, { __mode = "k" }),
    hotkeys = YUI._EllesmereUIHotkeys,
    questTrackerScroll = YUI._EllesmereUIQuestTrackerScroll,
    questAutomation = YUI._EllesmereUIQuestAutomation,
    enabled = false,
    config = nil,
    refreshScheduled = false,
    eventsAttached = false,
    overrideRegistered = false,
    characterApplyHooked = false,
    merchantUpdateHooked = false,
    friendsApplyHooked = false,
    stylesRefreshHooked = false,
    auctionShadowMembers = {},
    profileCallbacksRegistered = false,
    restorePending = false,
    visualHostSequence = 0,
}

local eventOwner = {}
local profileOwner = {}
local appearanceOverrideOwner = {}
local frameStates = setmetatable({}, { __mode = "k" })
local fontStates = setmetatable({}, { __mode = "k" })
local tabStates = setmetatable({}, { __mode = "k" })
local hookedFrames = setmetatable({}, { __mode = "k" })
local externalAlphaStates = setmetatable({}, { __mode = "k" })
local mailFillStates = setmetatable({}, { __mode = "k" })
local readyCheckRepairState = {}

local ScheduleRefresh
local DetachEvents
local RestoreReadyCheckRepair

local function T(key, fallback)
    local value = L[key]
    if value == nil or value == key then return fallback or key end
    return value
end

local function ClampNumber(value, minValue, maxValue, fallback)
    value = tonumber(value)
    if not value then return fallback end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function CopyColor(value, fallback)
    fallback = fallback or { 1, 1, 1, 1 }
    if type(value) ~= "table" then value = fallback end
    return {
        ClampNumber(value[1], 0, 1, fallback[1] or 1),
        ClampNumber(value[2], 0, 1, fallback[2] or 1),
        ClampNumber(value[3], 0, 1, fallback[3] or 1),
        ClampNumber(value[4], 0, 1, fallback[4] or 1),
    }
end

runtime.NormalizeDamageMeterConfig = function(db)
    local legacyEnabled = db.damageMeterSmartReset ~= false
    if db.damageMeterMythicReset == nil then db.damageMeterMythicReset = legacyEnabled end
    if db.damageMeterRaidPrompt == nil then db.damageMeterRaidPrompt = legacyEnabled end
    db.damageMeterMythicReset = db.damageMeterMythicReset ~= false
    db.damageMeterRaidPrompt = db.damageMeterRaidPrompt ~= false
    db.damageMeterDungeonPrompt = db.damageMeterDungeonPrompt == true
    db.damageMeterSmartReset = nil
end

local function NormalizeConfig(db)
    if type(db) ~= "table" then return DEFAULTS end
    db.beautifySkinBackground = db.beautifySkinBackground ~= false
    if db.backgroundPreset == "deepSeaStarSand" then db.backgroundPreset = PRESET_DEEP end
    if db.backgroundPreset == "crimsonForgedSteel" then db.backgroundPreset = PRESET_CRIMSON end
    if db.backgroundPreset ~= PRESET_MODERN
        and db.backgroundPreset ~= PRESET_DEEP
        and db.backgroundPreset ~= PRESET_CRIMSON
        and db.backgroundPreset ~= PRESET_SOLID
        and db.backgroundPreset ~= PRESET_YUI
        and db.backgroundPreset ~= runtime.pilotPreset
    then
        db.backgroundPreset = DEFAULTS.backgroundPreset
    end
    if db.pilotBasePreset ~= PRESET_DEEP and db.pilotBasePreset ~= PRESET_CRIMSON
        and db.pilotBasePreset ~= PRESET_SOLID and db.pilotBasePreset ~= PRESET_YUI then db.pilotBasePreset = PRESET_MODERN end
    db.solidColor = CopyColor(db.solidColor, DEFAULT_SOLID_COLOR)
    db.backgroundDarken = ClampNumber(db.backgroundDarken, 0, 0.60, 0)
    db.backgroundTransparency = ClampNumber(db.backgroundTransparency, 0, 1, 0)
    db.simplifyWindowBorder = db.simplifyWindowBorder == true
    db.windowShadow = db.windowShadow ~= false
    db.abbreviateHotkeys = db.abbreviateHotkeys == true
    db.questTrackerScroll = db.questTrackerScroll == true
    if type(db.hotkeyAliases) ~= "string" then db.hotkeyAliases = "" end
    runtime.NormalizeDamageMeterConfig(db)
    db.tabFontSize = math.floor(ClampNumber(db.tabFontSize, 9, 24, 13) + 0.5)
    db.characterDetailFontSize = math.floor(ClampNumber(db.characterDetailFontSize,
        CHARACTER_DETAIL_FONT_MIN_SIZE, CHARACTER_DETAIL_FONT_MAX_SIZE, DEFAULT_CHARACTER_DETAIL_FONT_SIZE) + 0.5)
    db.merchantItemNameFontSize = math.floor(ClampNumber(db.merchantItemNameFontSize,
        MERCHANT_ITEM_NAME_FONT_MIN_SIZE, MERCHANT_ITEM_NAME_FONT_MAX_SIZE,
        DEFAULT_MERCHANT_ITEM_NAME_FONT_SIZE) + 0.5)
    if db.tabColorMode ~= TAB_COLOR_CUSTOM then db.tabColorMode = TAB_COLOR_AUTO end
    db.tabColor = CopyColor(db.tabColor, DEFAULT_TAB_COLOR)
    return db
end

local function MigrateLegacyConfig(db)
    if type(db) ~= "table" then return end
    local version = tonumber(db._migrationVersion) or 0
    if version < 1 then
        local store = Components.GetStore and Components:GetStore(PRODUCT_ID)
        local utilityConfig = store and store.UtilityTools_Config
        local legacy = type(utilityConfig) == "table" and utilityConfig.ellesmereSkin or nil
        if type(legacy) == "table" and legacy.enabled == true then
            db.backgroundDarken = ClampNumber(legacy.backgroundDarken, 0, 0.60, db.backgroundDarken or 0)
            db.tabFontSize = math.floor(ClampNumber(legacy.tabFontSize, 9, 24, db.tabFontSize or 13) + 0.5)
            if Components.SetStoreValue then Components:SetStoreValue(FEATURE_KEY, true, PRODUCT_ID) end
        end
    end
    if version < 2 and db.removeCharacterModelBackdrop == nil then
        db.removeCharacterModelBackdrop = false
    end
    if version < 3 and db.removeCharacterModelBackdrop == true then
        db.simplifyWindowBorder = true
    end
    db._migrationVersion = 4
end

local function GetDB()
    local db = Components:EnsureConfig(CONFIG_KEY, nil, PRODUCT_ID)
    if type(db) ~= "table" then return DEFAULTS end
    -- 在填入新默认值前保留旧开关的关闭意愿。
    runtime.NormalizeDamageMeterConfig(db)
    Components:EnsureConfig(CONFIG_KEY, DEFAULTS, PRODUCT_ID)
    MigrateLegacyConfig(db)
    return NormalizeConfig(db)
end

local function IsForbidden(region)
    if not region or type(region.IsForbidden) ~= "function" then return false end
    local ok, forbidden = pcall(region.IsForbidden, region)
    return not ok or forbidden == true
end

local function IsSecretValue(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return not ok or secret == true
end

local function IsProtectedObject(object)
    if not object or type(object.IsProtected) ~= "function" then return false end
    local ok, protected = pcall(object.IsProtected, object)
    return not ok or protected == true
end

local function IsInCombat()
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, locked = pcall(InCombatLockdown)
    return not ok or locked == true
end

local function IsUnsafeExternalObject(object)
    if object == nil or IsSecretValue(object) or IsForbidden(object) then return true end
    return IsProtectedObject(object) and IsInCombat()
end

local function IsAddOnLoadedSafe(name)
    return System and type(System.IsAddOnLoadedSafe) == "function"
        and System.IsAddOnLoadedSafe(name) == true
end

local function GetWindowStyle(key)
    local provider = _G.EllesmereUI
    if type(provider) ~= "table" or type(provider.GetBlizzWindowStyle) ~= "function" then return nil end
    local ok, style = pcall(provider.GetBlizzWindowStyle, key)
    if not ok or (style ~= "eui" and style ~= "modern") then return nil end
    return style
end

local function GetDarken()
    return ClampNumber(runtime.config and runtime.config.backgroundDarken, 0, 0.60, 0)
end

local function GetBrightness()
    return 1 - GetDarken()
end

function runtime.GetPanelOpacity()
    return 1 - ClampNumber(runtime.config and runtime.config.backgroundTransparency, 0, 1, 0)
end

local function IsBackgroundBeautificationEnabled()
    return not runtime.config or runtime.config.beautifySkinBackground ~= false
end

local function GetTabFontSize()
    return math.floor(ClampNumber(runtime.config and runtime.config.tabFontSize, 9, 24, 13) + 0.5)
end

local function GetCharacterDetailFontSize()
    return math.floor(ClampNumber(runtime.config and runtime.config.characterDetailFontSize,
        CHARACTER_DETAIL_FONT_MIN_SIZE, CHARACTER_DETAIL_FONT_MAX_SIZE, DEFAULT_CHARACTER_DETAIL_FONT_SIZE) + 0.5)
end

local function GetMerchantItemNameFontSize()
    return math.floor(ClampNumber(runtime.config and runtime.config.merchantItemNameFontSize,
        MERCHANT_ITEM_NAME_FONT_MIN_SIZE, MERCHANT_ITEM_NAME_FONT_MAX_SIZE,
        DEFAULT_MERCHANT_ITEM_NAME_FONT_SIZE) + 0.5)
end

local function SetShown(region, shown)
    if not region then return end
    if shown then
        if type(region.Show) == "function" then pcall(region.Show, region) end
    elseif type(region.Hide) == "function" then
        pcall(region.Hide, region)
    end
end

local function IsObjectShown(object)
    if not object or type(object.IsShown) ~= "function" then return false end
    local ok, shown = pcall(object.IsShown, object)
    return ok and shown == true
end

local function SetTextureTiling(texture, enabled)
    if not texture then return end
    if type(texture.SetHorizTile) == "function" then pcall(texture.SetHorizTile, texture, enabled == true) end
    if type(texture.SetVertTile) == "function" then pcall(texture.SetVertTile, texture, enabled == true) end
end

local function SetTextureCoords(texture, coords)
    if not texture or type(texture.SetTexCoord) ~= "function" then return end
    coords = type(coords) == "table" and coords or { 0, 1, 0, 1 }
    pcall(texture.SetTexCoord, texture, coords[1] or 0, coords[2] or 1, coords[3] or 0, coords[4] or 1)
end

local function CreateTexture(frame, subLevel)
    if not frame or IsForbidden(frame) or type(frame.CreateTexture) ~= "function" then return nil end
    local ok, texture = pcall(frame.CreateTexture, frame, nil, "BACKGROUND", nil, subLevel)
    if not ok or not texture then return nil end
    if type(texture.SetAllPoints) == "function" then pcall(texture.SetAllPoints, texture, frame) end
    return texture
end

local function NextVisualHostName()
    for _ = 1, 128 do
        runtime.visualHostSequence = runtime.visualHostSequence + 1
        local name = VISUAL_HOST_PREFIX .. runtime.visualHostSequence
        if _G[name] == nil then return name end
    end
end

local function SyncVisualHost(frame, host)
    if not (frame and host) then return false end
    if type(host.SetAllPoints) == "function" then pcall(host.SetAllPoints, host, frame) end
    if type(frame.GetFrameStrata) == "function" and type(host.SetFrameStrata) == "function" then
        local ok, strata = pcall(frame.GetFrameStrata, frame)
        if ok and type(strata) == "string" and not IsSecretValue(strata) then
            pcall(host.SetFrameStrata, host, strata)
        end
    end
    if type(frame.GetFrameLevel) == "function" and type(host.SetFrameLevel) == "function" then
        local ok, level = pcall(frame.GetFrameLevel, frame)
        if ok and type(level) == "number" and not IsSecretValue(level) then
            pcall(host.SetFrameLevel, host, math.max(0, level))
        end
    end
    if type(host.EnableMouse) == "function" then pcall(host.EnableMouse, host, false) end
    SetShown(host, true)
    return true
end

local function EnsureVisualHost(frame, state)
    if not (frame and state) or IsUnsafeExternalObject(frame) then return nil end
    if state.visualHost then
        SyncVisualHost(frame, state.visualHost)
        return state.visualHost
    end
    if type(CreateFrame) ~= "function" then return nil end
    local hostName = NextVisualHostName()
    if not hostName then return nil end
    local ok, host = pcall(CreateFrame, "Frame", hostName, frame)
    if not ok or not host or _G[hostName] ~= host then return nil end
    state.visualHost = host
    state.visualHostName = hostName
    SyncVisualHost(frame, host)
    return host
end

local function EnsureFrameState(frame, owner, backgroundSubLevel)
    local state = frameStates[frame]
    if not state then
        state = { owner = owner, frame = frame }
        frameStates[frame] = state
    end
    state.owner, state.frame = owner, frame
    local host = EnsureVisualHost(frame, state)
    if host and not state.background then state.background = CreateTexture(host, backgroundSubLevel or -6) end
    return state
end

function runtime.GetBasePreset()
    local config = runtime.config or DEFAULTS
    return config.backgroundPreset == runtime.pilotPreset and config.pilotBasePreset or config.backgroundPreset
end

function runtime.IsPilotOwner(owner)
    return IsBackgroundBeautificationEnabled()
end

local function GetBackgroundColor()
    local preset = runtime.GetBasePreset()
    if preset == PRESET_SOLID then
        local color = CopyColor(runtime.config and runtime.config.solidColor, DEFAULT_SOLID_COLOR)
        color[4] = 1
        return color
    end
    if preset == PRESET_DEEP then return CopyColor(DEFAULT_DEEP_COLOR) end
    if preset == PRESET_CRIMSON then return CopyColor(DEFAULT_CRIMSON_COLOR) end
    if preset == PRESET_YUI then return CopyColor(DEFAULT_YUI_COLOR) end
    return CopyColor(DEFAULT_MODERN_COLOR)
end

function runtime.GetShellBaseColor()
    local preset = runtime.config.backgroundPreset
    if preset == runtime.pilotPreset then return { 32 / 255, 33 / 255, 37 / 255, 1 } end
    return GetBackgroundColor()
end

function runtime.GetShellBorderColor()
    local base = runtime.GetShellBaseColor()
    return { math.min(1, base[1] + 95.5 / 255), math.min(1, base[2] + 97 / 255),
        math.min(1, base[3] + 98.15 / 255), 0.8 }
end

local function RestoreExternalBackgrounds(state)
    local records = state and state.externalBackgrounds
    if type(records) ~= "table" then return end
    for index = 1, #records do
        local record = records[index]
        if record and record.region and not IsUnsafeExternalObject(record.region)
            and type(record.region.GetAlpha) == "function" and type(record.region.SetAlpha) == "function"
        then
            local ok, current = pcall(record.region.GetAlpha, record.region)
            if ok and type(current) == "number" and math.abs(current - (record.lastAppliedAlpha or 0)) <= ALPHA_EPSILON then
                pcall(record.region.SetAlpha, record.region, record.originalAlpha or 1)
            end
        end
    end
    state.externalBackgrounds = nil
    state.externalBackgroundLookup = nil
end

local function ReadRegionAlpha(region)
    if type(region.GetAlpha) ~= "function" then return 1 end
    local ok, alpha = pcall(region.GetAlpha, region)
    if not ok or type(alpha) ~= "number" then return 1 end
    return alpha
end

local function ApplyExternalAlpha(region, owner, alpha)
    if IsUnsafeExternalObject(region) or type(region.GetAlpha) ~= "function" or type(region.SetAlpha) ~= "function" then
        return false
    end
    local record = externalAlphaStates[region]
    if not record then
        record = { owner = owner, originalAlpha = ReadRegionAlpha(region) }
        externalAlphaStates[region] = record
    end
    record.owner = owner
    local current = ReadRegionAlpha(region)
    if math.abs(current - alpha) <= ALPHA_EPSILON then
        record.lastAppliedAlpha = alpha
        return true
    end
    local ok = pcall(region.SetAlpha, region, alpha)
    if ok then record.lastAppliedAlpha = alpha end
    return ok
end

local function RestoreExternalAlphaOwner(owner)
    for region, record in pairs(externalAlphaStates) do
        if record.owner == owner then
            if not IsUnsafeExternalObject(region) and type(region.GetAlpha) == "function" and type(region.SetAlpha) == "function" then
                local ok, current = pcall(region.GetAlpha, region)
                if ok and not IsSecretValue(current) and type(current) == "number"
                    and type(record.lastAppliedAlpha) == "number"
                    and math.abs(current - record.lastAppliedAlpha) <= ALPHA_EPSILON
                then
                    pcall(region.SetAlpha, region, record.originalAlpha or 1)
                end
            end
            externalAlphaStates[region] = nil
        end
    end
end

local function RestoreAllExternalAlpha()
    local owners = {}
    for _, record in pairs(externalAlphaStates) do owners[record.owner] = true end
    for owner in pairs(owners) do RestoreExternalAlphaOwner(owner) end
end

local textureFileIDs = {}

local function NormalizeTexturePath(path)
    if type(path) ~= "string" then return nil end
    return path:gsub("/", "\\"):lower()
end

local function GetTextureFileID(path)
    local cached = textureFileIDs[path]
    if cached ~= nil then return cached or nil end
    local getter = _G.GetFileIDFromPath
    if type(getter) == "function" then
        local ok, fileID = pcall(getter, path)
        if ok and type(fileID) == "number" and fileID > 0 then
            textureFileIDs[path] = fileID
            return fileID
        end
    end
    textureFileIDs[path] = false
    return nil
end

local function TextureMatchesFile(region, path)
    if not region or type(path) ~= "string" then return false end
    local expectedPath = NormalizeTexturePath(path)
    for _, methodName in ipairs({ "GetTextureFilePath", "GetTexture" }) do
        local method = region[methodName]
        if type(method) == "function" then
            local ok, value = pcall(method, region)
            if ok and NormalizeTexturePath(value) == expectedPath then return true end
        end
    end
    if type(region.GetTextureFileID) == "function" then
        local expectedFileID = GetTextureFileID(path)
        local ok, fileID = pcall(region.GetTextureFileID, region)
        if expectedFileID and ok and fileID == expectedFileID then return true end
    end
    return false
end

local function TextureMatchesAtlas(region, atlasName)
    if not region or type(atlasName) ~= "string" or type(region.GetAtlas) ~= "function" then return false end
    local ok, atlas = pcall(region.GetAtlas, region)
    return ok and not IsSecretValue(atlas) and atlas == atlasName
end

local function IsTextureRegion(region)
    if not region or IsForbidden(region) or type(region.IsObjectType) ~= "function" then return false end
    local ok, isTexture = pcall(region.IsObjectType, region, "Texture")
    return ok and isTexture == true
end

local function HasDrawLayer(region, expectedSubLevel, expectedLayer)
    if not region or type(region.GetDrawLayer) ~= "function" then return false end
    local ok, layer, subLevel = pcall(region.GetDrawLayer, region)
    return ok and not IsSecretValue(layer) and not IsSecretValue(subLevel)
        and layer == (expectedLayer or "BACKGROUND") and tonumber(subLevel) == expectedSubLevel
end

local function ReadColorTexture(region)
    if not region or type(region.GetColorTexture) ~= "function" then return nil end
    local ok, r, g, b, a = pcall(region.GetColorTexture, region)
    if not ok or IsSecretValue(r) or IsSecretValue(g) or IsSecretValue(b) or IsSecretValue(a)
        or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    return r, g, b, tonumber(a) or 1
end

local function ColorNear(r, g, b, expected, tolerance)
    tolerance = tonumber(tolerance) or COLOR_TOLERANCE
    return type(r) == "number" and type(g) == "number" and type(b) == "number"
        and math.abs(r - expected[1]) <= tolerance
        and math.abs(g - expected[2]) <= tolerance
        and math.abs(b - expected[3]) <= tolerance
end

local function IsSafePointValue(value)
    return not issecretvalue or not issecretvalue(value)
end

local function ReadRegionPoints(region)
    if not region or type(region.GetNumPoints) ~= "function" or type(region.GetPoint) ~= "function" then return nil end
    local countOK, count = pcall(region.GetNumPoints, region)
    if not countOK or IsSecretValue(count) or type(count) ~= "number" or count < 1 or count > 4 then return nil end
    local points = {}
    for index = 1, count do
        local ok, point, relativeTo, relativePoint, x, y = pcall(region.GetPoint, region, index)
        if not ok or not IsSafePointValue(point) or not IsSafePointValue(relativeTo)
            or not IsSafePointValue(relativePoint) or not IsSafePointValue(x) or not IsSafePointValue(y)
        then
            return nil
        end
        points[#points + 1] = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = tonumber(x) or 0,
            y = tonumber(y) or 0,
        }
    end
    return points
end

local function HasAnchor(points, point, relativeTo, relativePoint, x, y)
    if type(points) ~= "table" then return false end
    for index = 1, #points do
        local anchor = points[index]
        if anchor.point == point and anchor.relativeTo == relativeTo and anchor.relativePoint == relativePoint
            and math.abs(anchor.x - (x or 0)) <= 0.5 and math.abs(anchor.y - (y or 0)) <= 0.5
        then
            return true
        end
    end
    return false
end

local function PointsEqual(left, right)
    if type(left) ~= "table" or type(right) ~= "table" or #left ~= #right then return false end
    for index = 1, #left do
        local a, b = left[index], right[index]
        if a.point ~= b.point or a.relativeTo ~= b.relativeTo or a.relativePoint ~= b.relativePoint
            or math.abs((a.x or 0) - (b.x or 0)) > 0.01
            or math.abs((a.y or 0) - (b.y or 0)) > 0.01
        then
            return false
        end
    end
    return true
end

local function SetRegionPoints(region, points)
    if IsUnsafeExternalObject(region) or type(points) ~= "table"
        or type(region.ClearAllPoints) ~= "function" or type(region.SetPoint) ~= "function"
    then
        return false
    end
    if not pcall(region.ClearAllPoints, region) then return false end
    for index = 1, #points do
        local point = points[index]
        if not pcall(region.SetPoint, region, point.point, point.relativeTo, point.relativePoint, point.x, point.y) then
            return false
        end
    end
    return true
end

local function RestoreMailFillOwner(owner)
    for region, record in pairs(mailFillStates) do
        if record.owner == owner then
            local current = ReadRegionPoints(region)
            if current and PointsEqual(current, record.lastAppliedPoints) then
                SetRegionPoints(region, record.originalPoints)
            end
            mailFillStates[region] = nil
        end
    end
end

local function RestoreAllMailFills()
    local owners = {}
    for _, record in pairs(mailFillStates) do owners[record.owner] = true end
    for owner in pairs(owners) do RestoreMailFillOwner(owner) end
end

local function IsFullFrameRegion(region, frame)
    local points = ReadRegionPoints(region)
    return points and #points == 2
        and HasAnchor(points, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        and HasAnchor(points, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
end

function runtime.RestorePanelUnderlays(state)
    if state.opacityOwner then RestoreExternalAlphaOwner(state.opacityOwner) end
    state.opacityRegions = nil
end

function runtime.PreparePanelOpacity(frame, state, adapterKind)
    local alpha = runtime.GetPanelOpacity()
    local function fallback()
        runtime.RestorePanelUnderlays(state)
        return 1
    end
    if alpha == 1 or type(frame.GetRegions) ~= "function" then return fallback() end
    local ok, regions = pcall(function() return { frame:GetRegions() } end)
    if not ok or #regions > 64 then return fallback() end
    local candidates, layers = {}, {}
    local expectedLayers = adapterKind == "gameMenu" and runtime.menuUnderlayLayers or runtime.shellUnderlayLayers
    -- 只检查已接入窗口直属、全幅的背景层；内部面板、标题条和内容材质不参与。
    for _, region in ipairs(regions) do
        if region ~= state.background and region ~= state.directBackground
            and not IsUnsafeExternalObject(region) and IsTextureRegion(region) then
            local layer
            for _, subLevel in ipairs(expectedLayers) do
                if HasDrawLayer(region, subLevel) then layer = subLevel; break end
            end
            if layer then
                local points = ReadRegionPoints(region)
                if not points then return fallback() end
                if #points == 2 and HasAnchor(points, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                    and HasAnchor(points, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0) then
                    if layers[layer] then return fallback() end
                    layers[layer] = region
                    candidates[#candidates + 1] = region
                end
            end
        end
    end
    local previous, changed = state.opacityRegions, false
    if previous then
        changed = #previous ~= #candidates
        for index, region in ipairs(previous) do
            if candidates[index] ~= region then changed = true; break end
        end
    end
    if changed then runtime.RestorePanelUnderlays(state) end
    state.opacityOwner = state.opacityOwner or {}
    state.opacityRegions = candidates
    for _, region in ipairs(candidates) do
        if type(region.GetAlpha) ~= "function" then return fallback() end
        local alphaOK, current = pcall(region.GetAlpha, region)
        if not alphaOK or IsSecretValue(current) or type(current) ~= "number" then return fallback() end
        if not ApplyExternalAlpha(region, state.opacityOwner, 0) then return fallback() end
    end
    return alpha
end

local function IsLegacyFriendsBackground(region, frame)
    if not IsTextureRegion(region) or not HasDrawLayer(region, -8) or not IsFullFrameRegion(region, frame) then
        return false
    end
    local r, g, b = ReadColorTexture(region)
    return ColorNear(r, g, b, FRIENDS_BACKGROUND_COLOR)
end

local function IsLegacyFriendsTabBar(region, frame)
    if not IsTextureRegion(region) or not HasDrawLayer(region, -7) then return false end
    local r, g, b = ReadColorTexture(region)
    if not ColorNear(r, g, b, FRIENDS_BACKGROUND_COLOR) then return false end
    local firstTab = _G.FriendsFrameTab1
    local points = ReadRegionPoints(region)
    return firstTab and points and #points == 3
        and HasAnchor(points, "TOPLEFT", frame, "BOTTOMLEFT", 0, 2)
        and HasAnchor(points, "TOPRIGHT", frame, "BOTTOMRIGHT", 0, 2)
        and HasAnchor(points, "BOTTOM", firstTab, "BOTTOM", 0, 0)
end

local function SuppressExternalRegions(state, candidates)
    state.externalBackgrounds = state.externalBackgrounds or {}
    state.externalBackgroundLookup = state.externalBackgroundLookup or {}
    for index = 1, #candidates do
        local region = candidates[index]
        if not state.externalBackgroundLookup[region] then
            local record = { region = region, originalAlpha = ReadRegionAlpha(region) }
            state.externalBackgroundLookup[region] = record
            state.externalBackgrounds[#state.externalBackgrounds + 1] = record
        end
        local record = state.externalBackgroundLookup[region]
        if not IsUnsafeExternalObject(region) and type(region.SetAlpha) == "function"
            and pcall(region.SetAlpha, region, 0)
        then
            record.lastAppliedAlpha = 0
        end
    end
end

function runtime.IsFriendsTabBar(region, frame)
    local firstTab, lastTab = _G.FriendsFrameTab1, _G.FriendsFrameTab4
    if IsUnsafeExternalObject(region) or IsUnsafeExternalObject(firstTab) or IsUnsafeExternalObject(lastTab)
        or not IsTextureRegion(region) or not HasDrawLayer(region, -8) or type(region.GetParent) ~= "function"
    then return false end
    local ok, parent = pcall(region.GetParent, region)
    if not ok or IsSecretValue(parent) or parent ~= firstTab then return false end
    local points = ReadRegionPoints(region)
    return points and #points == 2
        and HasAnchor(points, "TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
        and HasAnchor(points, "BOTTOMRIGHT", lastTab, "BOTTOMRIGHT", 0, 0)
end

local function TrySuppressExternalBackgrounds(frame, state, adapterKind)
    if adapterKind ~= "legacyFriends" or not frame or not state or type(frame.GetRegions) ~= "function" then
        RestoreExternalBackgrounds(state)
        return false
    end
    local ok, regions = pcall(function() return { frame:GetRegions() } end)
    if not ok or type(regions) ~= "table" then return false end

    local backgrounds, tabBars = {}, {}
    for index = 1, #regions do
        local region = regions[index]
        if not IsUnsafeExternalObject(region) and region ~= state.background then
            if IsLegacyFriendsBackground(region, frame) then backgrounds[#backgrounds + 1] = region end
            if IsLegacyFriendsTabBar(region, frame) then tabBars[#tabBars + 1] = region end
        end
    end

    local firstTab = _G.FriendsFrameTab1
    local relocated = false
    if not IsUnsafeExternalObject(firstTab) and type(firstTab.GetRegions) == "function" then
        local tabsOK, regions = pcall(function() return { firstTab:GetRegions() } end)
        if not tabsOK or #regions > 32 then
            RestoreExternalBackgrounds(state)
            return false
        end
        for index = 1, #regions do
            if runtime.IsFriendsTabBar(regions[index], frame) then
                tabBars[#tabBars + 1] = regions[index]
                relocated = true
            end
        end
    end
    -- 新背景条以所属 Tab、绘制层和跨四个 Tab 的锚点确认，不依赖可配置的颜色。
    if #tabBars ~= 1 or (not relocated and #backgrounds ~= 1) then
        RestoreExternalBackgrounds(state)
        return false
    end
    SuppressExternalRegions(state, { tabBars[1] })
    return true
end

local function SetCleanBorderShown(state, shown)
    local borders = state and state.cleanBorders
    if type(borders) ~= "table" then return end
    for index = 1, #borders do SetShown(borders[index], shown) end
end

local function RestoreWindowBorder(state)
    local record = state and state.windowBorderAtlas
    if record and record.region and not IsUnsafeExternalObject(record.region)
        and type(record.region.GetAlpha) == "function" and type(record.region.SetAlpha) == "function"
    then
        local ok, current = pcall(record.region.GetAlpha, record.region)
        if ok and type(current) == "number" and math.abs(current - (record.lastAppliedAlpha or 0)) <= ALPHA_EPSILON then
            pcall(record.region.SetAlpha, record.region, record.originalAlpha or 1)
        end
    end
    if state then
        state.windowBorderAtlas = nil
        SetCleanBorderShown(state, false)
    end
end

local function FindWindowBorderAtlas(frame, maxDepth)
    if not frame or type(frame.GetChildren) ~= "function" then return nil end
    local childrenOK, children = pcall(function() return { frame:GetChildren() } end)
    if not childrenOK or (maxDepth and #children > 64) then return nil end
    local matches = {}
    local function Scan(child, parent, depth)
        if not IsUnsafeExternalObject(child) and IsFullFrameRegion(child, parent) and type(child.GetRegions) == "function" then
            local regionsOK, regions = pcall(function() return { child:GetRegions() } end)
            if not regionsOK or (maxDepth and #regions > 32) then return false end
            if regionsOK then
                for regionIndex = 1, #regions do
                    local region = regions[regionIndex]
                    if not IsUnsafeExternalObject(region) and IsTextureRegion(region) and HasDrawLayer(region, 7, "OVERLAY")
                        and IsFullFrameRegion(region, child) and TextureMatchesAtlas(region, WINDOW_BORDER_ATLAS)
                    then
                        matches[#matches + 1] = { region = region, host = child }
                    end
                end
            end
            if depth < (maxDepth or 1) and type(child.GetChildren) == "function" then
                local nestedOK, nested = pcall(function() return { child:GetChildren() } end)
                if not nestedOK or #nested > 64 then return false end
                for index = 1, #nested do
                    if not Scan(nested[index], child, depth + 1) then return false end
                end
            end
        end
        return true
    end
    for childIndex = 1, #children do
        if not Scan(children[childIndex], frame, 1) then return nil end
    end
    return #matches == 1 and matches[1] or nil
end

local function PrepareBorderTexture(texture)
    if not texture then return end
    if GUI2 and type(GUI2.ApplyTexturePixelPolicy) == "function" then
        pcall(GUI2.ApplyTexturePixelPolicy, GUI2, texture)
    else
        if type(texture.SetSnapToPixelGrid) == "function" then pcall(texture.SetSnapToPixelGrid, texture, false) end
        if type(texture.SetTexelSnappingBias) == "function" then pcall(texture.SetTexelSnappingBias, texture, 0) end
    end
end

local function GetBorderPixel(host)
    if GUI2 and type(GUI2.GetPixelSize) == "function" then
        local ok, pixel = pcall(GUI2.GetPixelSize, GUI2, host, 1, 1)
        if ok and type(pixel) == "number" and pixel > 0 then return pixel end
    end
    return GUI2 and tonumber(GUI2.mult) or 1
end

local function CreateBorderLine(host)
    if not host or type(host.CreateTexture) ~= "function" then return nil end
    local ok, texture = pcall(host.CreateTexture, host, nil, "OVERLAY", nil, 7)
    if not ok or not texture then return nil end
    PrepareBorderTexture(texture)
    if type(texture.SetColorTexture) == "function" then
        pcall(texture.SetColorTexture, texture,
            CLEAN_BORDER_COLOR[1], CLEAN_BORDER_COLOR[2], CLEAN_BORDER_COLOR[3], CLEAN_BORDER_COLOR[4])
    end
    return texture
end

local function EnsureCleanBorder(host, state)
    if state.cleanBorderHost ~= host then
        SetCleanBorderShown(state, false)
        state.cleanBorderHost = host
        state.cleanBorders = nil
    end
    if state.cleanBorders then
        SetCleanBorderShown(state, true)
        return true
    end

    local top, bottom, left, right = CreateBorderLine(host), CreateBorderLine(host), CreateBorderLine(host), CreateBorderLine(host)
    if not (top and bottom and left and right) then
        for _, texture in ipairs({ top, bottom, left, right }) do SetShown(texture, false) end
        return false
    end
    local pixel = GetBorderPixel(host)
    pcall(top.SetPoint, top, "TOPLEFT", host, "TOPLEFT", 0, 0)
    pcall(top.SetPoint, top, "TOPRIGHT", host, "TOPRIGHT", 0, 0)
    pcall(top.SetHeight, top, pixel)
    pcall(bottom.SetPoint, bottom, "BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
    pcall(bottom.SetPoint, bottom, "BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    pcall(bottom.SetHeight, bottom, pixel)
    pcall(left.SetPoint, left, "TOPLEFT", host, "TOPLEFT", 0, 0)
    pcall(left.SetPoint, left, "BOTTOMLEFT", host, "BOTTOMLEFT", 0, 0)
    pcall(left.SetWidth, left, pixel)
    pcall(right.SetPoint, right, "TOPRIGHT", host, "TOPRIGHT", 0, 0)
    pcall(right.SetPoint, right, "BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    pcall(right.SetWidth, right, pixel)
    state.cleanBorders = { top, bottom, left, right }
    SetCleanBorderShown(state, true)
    return true
end

local function ApplyWindowBorder(frame, state, maxDepth)
    if not (runtime.config and runtime.config.simplifyWindowBorder == true) then
        RestoreWindowBorder(state)
        return false
    end
    local match = FindWindowBorderAtlas(frame, maxDepth)
    if not match then
        RestoreWindowBorder(state)
        return false
    end
    local record = state.windowBorderAtlas
    if not record or record.region ~= match.region then
        RestoreWindowBorder(state)
        record = { region = match.region, originalAlpha = ReadRegionAlpha(match.region), host = match.host }
        state.windowBorderAtlas = record
    end
    if IsUnsafeExternalObject(match.region) or type(match.region.SetAlpha) ~= "function"
        or not EnsureCleanBorder(match.host, state)
    then
        RestoreWindowBorder(state)
        return false
    end
    local ok = pcall(match.region.SetAlpha, match.region, 0)
    local pilot = runtime.IsPilotOwner(state.owner)
    if pilot or state.pilotBorder then
        local color = pilot and runtime.GetShellBorderColor() or CLEAN_BORDER_COLOR
        for _, line in ipairs(state.cleanBorders or {}) do
            pcall(line.SetColorTexture, line, color[1], color[2], color[3], color[4])
        end
        state.pilotBorder = pilot
    end
    if ok then record.lastAppliedAlpha = 0 else RestoreWindowBorder(state) end
    return ok
end

local function GetDarkenedBackgroundColor()
    local color = GetBackgroundColor()
    local brightness = GetBrightness()
    return { color[1] * brightness, color[2] * brightness, color[3] * brightness, color[4] }
end

function runtime.GetPilotFinish(titleHeight)
    local brightness = GetBrightness()
    local base = runtime.GetShellBaseColor()
    local function color(r, g, b)
        return { math.min(1, base[1] + r / 255) * brightness,
            math.min(1, base[2] + g / 255) * brightness,
            math.min(1, base[3] + b / 255) * brightness, 1 }
    end
    local background = { top = color(9, 8, 8), bottom = color(0, 0, 0) }
    background.top[4], background.bottom[4] = runtime.GetPanelOpacity(), runtime.GetPanelOpacity()
    return {
        background = background,
        title = { top = color(13, 13, 13), bottom = color(4, 5, 5) },
        titleHeight = titleHeight,
        shadowSize = runtime.config.windowShadow ~= false and 4 or nil,
        shadowColor = { 0, 0, 0, 0.3 },
        border = runtime.config.simplifyWindowBorder == true and runtime.GetShellBorderColor() or nil,
    }
end

function runtime.GetGameMenuFinish()
    local style = runtime.menuStyle
    return {
        background = { top = CopyColor(style.panel.top), bottom = CopyColor(style.panel.bottom) },
        shadowSize = runtime.config.windowShadow ~= false and 4 or nil,
        shadowColor = { 0, 0, 0, 0.3 },
        border = runtime.config.simplifyWindowBorder == true and style.border or nil,
    }
end

function runtime.PaintFinishGradient(texture, top, bottom)
    if not texture then return end
    pcall(texture.SetColorTexture, texture, 1, 1, 1, 1)
    if type(texture.SetGradientAlpha) == "function" and pcall(texture.SetGradientAlpha, texture, "VERTICAL",
        bottom[1], bottom[2], bottom[3], bottom[4], top[1], top[2], top[3], top[4]) then return end
    if type(texture.SetGradient) == "function" and type(CreateColor) == "function" and pcall(function()
        texture:SetGradient("VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], bottom[4]),
            CreateColor(top[1], top[2], top[3], top[4]))
    end) then return end
    pcall(texture.SetColorTexture, texture, top[1], top[2], top[3], top[4])
end

-- 直接纹理沿用现有边缘贴图的八片坐标，不向受保护窗口添加子 frame。
runtime.directShadowPieces = {
    { "BOTTOMRIGHT", "TOPLEFT", nil, nil, { 0.5078125, 0.6171875, 0.0625, 0.9375 } },
    { "BOTTOMLEFT", "TOPRIGHT", nil, nil, { 0.6328125, 0.7421875, 0.0625, 0.9375 } },
    { "TOPRIGHT", "BOTTOMLEFT", nil, nil, { 0.7578125, 0.8671875, 0.0625, 0.9375 } },
    { "TOPLEFT", "BOTTOMRIGHT", nil, nil, { 0.8828125, 0.9921875, 0.0625, 0.9375 } },
    { "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT",
        { 0.2578125, 0.9375, 0.3671875, 0.9375, 0.2578125, 0.0625, 0.3671875, 0.0625 } },
    { "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT",
        { 0.3828125, 0.9375, 0.4921875, 0.9375, 0.3828125, 0.0625, 0.4921875, 0.0625 } },
    { "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT", { 0.0078125, 0.1171875, 0.0625, 0.9375 } },
    { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", { 0.1328125, 0.2421875, 0.0625, 0.9375 } },
}

function runtime.HideDirectShellFinish(state)
    local finish = state and state.directFinish
    if not finish then return end
    SetShown(finish.title, false)
    for _, texture in pairs(finish.shadows) do SetShown(texture, false) end
end

function runtime.ApplyDirectShellFinish(frame, state, finish, background)
    if not finish then runtime.HideDirectShellFinish(state); return end
    local unpackValues = unpack or table.unpack
    local visual = state.directFinish
    if not visual then
        visual = { shadows = {} }
        state.directFinish = visual
    end
    runtime.PaintFinishGradient(background, finish.background.top, finish.background.bottom)
    if not visual.title then
        local ok, title = pcall(frame.CreateTexture, frame, nil, "BORDER", nil, -8)
        if ok then visual.title = title; PrepareBorderTexture(title) end
    end
    if visual.title then
        local pixel = GetBorderPixel(frame)
        visual.title:ClearAllPoints()
        visual.title:SetPoint("TOPLEFT", frame, "TOPLEFT", pixel, -pixel)
        visual.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pixel, -pixel)
        visual.title:SetHeight(finish.titleHeight - pixel)
        runtime.PaintFinishGradient(visual.title, finish.title.top, finish.title.bottom)
        SetShown(visual.title, true)
    end
    if not finish.shadowSize then
        for _, texture in ipairs(visual.shadows) do SetShown(texture, false) end
        return
    end
    local assets = YUI.Assets
    if not (assets and type(assets.Core) == "function") then return end
    local path, size = assets:Core("images\\GlowTex.tga"), GetBorderPixel(frame) * finish.shadowSize
    for index, piece in ipairs(runtime.directShadowPieces) do
        local texture = visual.shadows[index]
        if not texture then
            texture = CreateTexture(frame, -8)
            visual.shadows[index] = texture
            PrepareBorderTexture(texture)
        end
        if texture then
            texture:ClearAllPoints()
            texture:SetPoint(piece[1], frame, piece[2], 0, 0)
            if piece[3] then texture:SetPoint(piece[3], frame, piece[4], 0, 0) end
            if index <= 4 or index >= 7 then texture:SetWidth(size) end
            if index <= 6 then texture:SetHeight(size) end
            texture:SetTexture(path)
            texture:SetTexCoord(unpackValues(piece[5]))
            texture:SetVertexColor(unpackValues(finish.shadowColor))
            SetShown(texture, true)
        end
    end
end

local function ApplyFrameBackground(frame, owner, adapterKind, directVisual)
    local state
    if directVisual then
        if IsUnsafeExternalObject(frame) then return nil end
        state = frameStates[frame]
        if not state then
            state = { owner = owner, frame = frame }
            frameStates[frame] = state
        end
        state.owner, state.frame = owner, frame
        if not state.directBackground then state.directBackground = CreateTexture(frame, -6) end
    else
        -- 菜单原底板位于 BACKGROUND/0；渐变只提高一个子层，仍在文字、Logo 和按钮之下。
        state = EnsureFrameState(frame, owner, adapterKind == "gameMenu" and 1 or -6)
    end
    local background = directVisual and state and state.directBackground or state and state.background
    if not (state and background) then return nil end
    if not IsBackgroundBeautificationEnabled() then
        runtime.HideDirectShellFinish(state)
        runtime.RestorePanelUnderlays(state)
        RestoreExternalBackgrounds(state)
        SetShown(background, false)
        SetShown(state.visualHost, false)
        if Appearance and type(Appearance.ApplyShellFinish) == "function" and state.visualHost then
            Appearance:ApplyShellFinish(state.visualHost, nil)
        end
        return state
    end
    if adapterKind == "legacyFriends" then
        TrySuppressExternalBackgrounds(frame, state, adapterKind)
    else
        RestoreExternalBackgrounds(state)
    end

    SetTextureTiling(background, false)
    SetTextureCoords(background)

    local color = GetDarkenedBackgroundColor()
    if type(background.SetColorTexture) ~= "function"
        or not pcall(background.SetColorTexture, background, color[1], color[2], color[3], 1)
    then
        SetShown(background, false)
        return state
    end
    if type(background.SetVertexColor) == "function" then pcall(background.SetVertexColor, background, 1, 1, 1, 1) end
    if type(background.SetAlpha) == "function" then pcall(background.SetAlpha, background, 1) end
    local finish = adapterKind == "gameMenu" and runtime.GetGameMenuFinish()
        or runtime.IsPilotOwner(owner)
        and runtime.GetPilotFinish(owner == "character" and not runtime.isForever and 50 or 25) or nil
    if finish then
        local alpha = runtime.PreparePanelOpacity(frame, state, adapterKind)
        finish.background.top[4], finish.background.bottom[4] = alpha, alpha
    end
    if directVisual then
        runtime.ApplyDirectShellFinish(frame, state, finish, background)
    elseif Appearance and type(Appearance.ApplyShellFinish) == "function" and state.visualHost then
        state.finish = Appearance:ApplyShellFinish(state.visualHost, finish, background)
    end
    SetShown(background, true)
    SetShown(state.visualHost, true)
    return state
end

local function GetTabColor()
    if runtime.config and runtime.config.tabColorMode == TAB_COLOR_CUSTOM then
        return CopyColor(runtime.config.tabColor, DEFAULT_TAB_COLOR)
    end
    local base = GetBackgroundColor()
    local factor = GetBrightness() * 0.78
    return { base[1] * factor, base[2] * factor, base[3] * factor, 0.94 }
end

local function RestoreFontString(fontString)
    local state = fontStates[fontString]
    if not state or IsUnsafeExternalObject(fontString)
        or type(fontString.GetFont) ~= "function" or type(fontString.SetFont) ~= "function"
    then
        return
    end
    local ok, path, size, flags = pcall(fontString.GetFont, fontString)
    if ok and not IsSecretValue(path) and not IsSecretValue(size) and not IsSecretValue(flags)
        and path == state.lastPath and size == state.lastSize and (flags or "") == (state.lastFlags or "") then
        pcall(fontString.SetFont, fontString, state.path, state.size, state.flags)
    end
    if state.color and state.lastColor and type(fontString.GetTextColor) == "function"
        and type(fontString.SetTextColor) == "function"
    then
        local colorOK, r, g, b, a = pcall(fontString.GetTextColor, fontString)
        local last = state.lastColor
        if colorOK and type(r) == "number" and type(g) == "number" and type(b) == "number"
            and math.abs(r - last[1]) <= ALPHA_EPSILON
            and math.abs(g - last[2]) <= ALPHA_EPSILON
            and math.abs(b - last[3]) <= ALPHA_EPSILON
            and math.abs((a or 1) - last[4]) <= ALPHA_EPSILON
        then
            pcall(fontString.SetTextColor, fontString,
                state.color[1], state.color[2], state.color[3], state.color[4])
        end
    end
    local wordWrapGetter = fontString.CanWordWrap or fontString.GetWordWrap
    if state.wordWrapCaptured and state.lastWordWrap ~= nil
        and type(wordWrapGetter) == "function" and type(fontString.SetWordWrap) == "function"
    then
        local wrapOK, current = pcall(wordWrapGetter, fontString)
        if wrapOK and (current == true) == state.lastWordWrap then
            pcall(fontString.SetWordWrap, fontString, state.wordWrap)
        end
    end
    if state.maxLinesCaptured and state.lastMaxLines ~= nil
        and type(fontString.GetMaxLines) == "function" and type(fontString.SetMaxLines) == "function"
    then
        local linesOK, current = pcall(fontString.GetMaxLines, fontString)
        if linesOK and current == state.lastMaxLines then
            pcall(fontString.SetMaxLines, fontString, state.maxLines)
        end
    end
    if state.merchantOriginalPoints and state.merchantLastAppliedPoints then
        local current = ReadRegionPoints(fontString)
        if current and PointsEqual(current, state.merchantLastAppliedPoints) then
            SetRegionPoints(fontString, state.merchantOriginalPoints)
        end
    end
end

local function ApplyFontString(fontString, owner, requestedSize)
    if IsUnsafeExternalObject(fontString)
        or type(fontString.GetFont) ~= "function" or type(fontString.SetFont) ~= "function"
    then
        return
    end
    local state = fontStates[fontString]
    if not state then
        local ok, path, size, flags = pcall(fontString.GetFont, fontString)
        if not ok or type(path) ~= "string" or path == "" or type(size) ~= "number" then return end
        state = { owner = owner, path = path, size = size, flags = flags or "" }
        if type(fontString.GetTextColor) == "function" then
            local colorOK, r, g, b, a = pcall(fontString.GetTextColor, fontString)
            if colorOK and type(r) == "number" and type(g) == "number" and type(b) == "number" then
                state.color = { r, g, b, type(a) == "number" and a or 1 }
            end
        end
        fontStates[fontString] = state
    else
        state.owner = owner
    end
    local size = math.floor(ClampNumber(requestedSize, 6, 32, GetTabFontSize()) + 0.5)
    if pcall(fontString.SetFont, fontString, state.path, size, state.flags) then
        state.lastPath, state.lastSize, state.lastFlags = state.path, size, state.flags
    end
end

local function ApplyCharacterDetailFontString(fontString, owner)
    if IsUnsafeExternalObject(fontString) or type(fontString.GetFont) ~= "function" then return end
    local state = fontStates[fontString]
    local originalSize = state and state.size
    if type(originalSize) ~= "number" then
        local ok, _, size = pcall(fontString.GetFont, fontString)
        if not ok or type(size) ~= "number" then return end
        originalSize = size
    end
    local offset = GetCharacterDetailFontSize() - CHARACTER_DETAIL_FONT_BASE_SIZE
    ApplyFontString(fontString, owner, originalSize + offset)
end

function runtime.ApplyForeverStatFont(fontString, requestedSize)
    if IsUnsafeExternalObject(fontString) or type(fontString.GetFont) ~= "function" then return end
    local ok, path, size, flags = pcall(fontString.GetFont, fontString)
    if not ok or IsSecretValue(path) or IsSecretValue(size) or IsSecretValue(flags)
        or type(path) ~= "string" or type(size) ~= "number" then return end
    local state = fontStates[fontString]
    if state and (path ~= state.lastPath or size ~= state.lastSize or (flags or "") ~= state.lastFlags) then
        fontStates[fontString] = nil
    end
    if size ~= requestedSize then ApplyFontString(fontString, "character", requestedSize) end
end

function runtime.ApplyForeverStat(frame)
    if not runtime.enabled or IsInCombat() or IsUnsafeExternalObject(frame)
        or not IsAddOnLoadedSafe("EllesmereUIBlizzardSkin") or not GetWindowStyle("charsheet")
    then return end
    local size = GetCharacterDetailFontSize()
    runtime.ApplyForeverStatFont(frame.Title, size + 1)
    runtime.ApplyForeverStatFont(frame.Label, size)
    runtime.ApplyForeverStatFont(frame.Value, size)
end

function runtime.OnForeverStatInitialized(_, frame)
    runtime.ApplyForeverStat(frame)
end

function runtime.DetachForeverStats()
    for box, event in pairs(runtime.foreverStatsBoxes) do
        if pcall(box.UnregisterCallback, box, event, runtime) then
            runtime.foreverStatsBoxes[box] = nil
        end
    end
end

function runtime.ApplyForeverStats()
    local event = ScrollBoxListMixin and ScrollBoxListMixin.Event and ScrollBoxListMixin.Event.OnInitializedFrame
    for _, name in ipairs({ "CharacterStatsPaneScrollBox", "CharacterStatsPanePetScrollBox" }) do
        local pane = _G[name]
        local box = pane and not IsUnsafeExternalObject(pane) and pane.ScrollBox
        if box and not IsUnsafeExternalObject(box) then
            if event and not runtime.foreverStatsBoxes[box] and type(box.RegisterCallback) == "function"
                and type(box.UnregisterCallback) == "function"
                and pcall(box.RegisterCallback, box, event, runtime.OnForeverStatInitialized, runtime)
            then runtime.foreverStatsBoxes[box] = event end
            if type(box.ForEachFrame) == "function" then pcall(box.ForEachFrame, box, runtime.ApplyForeverStat) end
        end
    end
end

local function ApplyCharacterDetailFonts(owner)
    if runtime.isForever then
        runtime.ApplyForeverStats()
        return
    end
    local roots = {
        _G.EUI_CharSheet_Stats,
        _G.EUI_CharSheet_Titles,
        _G.EUI_CharSheet_Equipment,
        _G.EUI_CharSheet_ScrollFrame,
    }
    local seen = {}
    local scanned = 0

    local function Scan(object)
        if not object or seen[object] or scanned >= CHARACTER_DETAIL_SCAN_LIMIT
            or IsUnsafeExternalObject(object)
        then
            return
        end
        seen[object] = true
        scanned = scanned + 1

        if type(object.IsObjectType) == "function" then
            local ok, isFontString = pcall(object.IsObjectType, object, "FontString")
            if ok and isFontString then
                ApplyCharacterDetailFontString(object, owner)
                return
            end
        end

        if type(object.GetRegions) == "function" then
            local regions = { pcall(object.GetRegions, object) }
            if table.remove(regions, 1) then
                for index = 1, #regions do Scan(regions[index]) end
            end
        end
        if type(object.GetChildren) == "function" then
            local children = { pcall(object.GetChildren, object) }
            if table.remove(children, 1) then
                for index = 1, #children do Scan(children[index]) end
            end
        end
        if type(object.GetScrollChild) == "function" then
            local ok, scrollChild = pcall(object.GetScrollChild, object)
            if ok then Scan(scrollChild) end
        end
    end

    for index = 1, #roots do Scan(roots[index]) end
end

local function ApplyMerchantItemNameFonts(owner, frame)
    local seen = {}
    local function ApplyGridLayout(fontString)
        local state = fontStates[fontString]
        if not state then return end
        if not state.merchantLayoutCaptured then
            state.merchantLayoutCaptured = true
            local wordWrapGetter = fontString.CanWordWrap or fontString.GetWordWrap
            if type(wordWrapGetter) == "function" and type(fontString.SetWordWrap) == "function" then
                local wrapOK, wordWrap = pcall(wordWrapGetter, fontString)
                if wrapOK then
                    state.wordWrapCaptured = true
                    state.wordWrap = wordWrap == true
                end
            end
            if type(fontString.GetMaxLines) == "function" and type(fontString.SetMaxLines) == "function" then
                local linesOK, maxLines = pcall(fontString.GetMaxLines, fontString)
                if linesOK and type(maxLines) == "number" then
                    state.maxLinesCaptured = true
                    state.maxLines = maxLines
                end
            end
            state.merchantOriginalPoints = ReadRegionPoints(fontString)
        end
        if type(fontString.SetWordWrap) == "function" and pcall(fontString.SetWordWrap, fontString, true) then
            state.lastWordWrap = true
        end
        if type(fontString.SetMaxLines) == "function" and pcall(fontString.SetMaxLines, fontString, 2) then
            state.lastMaxLines = 2
        end
        local current = ReadRegionPoints(fontString)
        if current and state.merchantLastAppliedPoints
            and not PointsEqual(current, state.merchantLastAppliedPoints)
        then
            state.merchantOriginalPoints = current
        end
        local originalPoints = state.merchantOriginalPoints
        if originalPoints and type(fontString.GetNumLines) == "function" then
            local linesOK, lineCount = pcall(fontString.GetNumLines, fontString)
            if linesOK and type(lineCount) == "number" then
                local applied = {}
                local offsetY = lineCount > 1 and -3 or 0
                for index = 1, #originalPoints do
                    local point = originalPoints[index]
                    applied[index] = {
                        point = point.point,
                        relativeTo = point.relativeTo,
                        relativePoint = point.relativePoint,
                        x = point.x,
                        y = point.y + offsetY,
                    }
                end
                if current and PointsEqual(current, applied) then
                    state.merchantLastAppliedPoints = current
                elseif SetRegionPoints(fontString, applied) then
                    state.merchantLastAppliedPoints = ReadRegionPoints(fontString)
                end
            end
        end
    end
    local function ApplyItem(item, gridLayout)
        if IsUnsafeExternalObject(item) or seen[item] then return end
        seen[item] = true
        local fontString = item.Name
        if not fontString and type(item.GetName) == "function" then
            local ok, name = pcall(item.GetName, item)
            if ok and type(name) == "string" then fontString = _G[name .. "Name"] end
        end
        ApplyFontString(fontString, owner, GetMerchantItemNameFontSize())
        if gridLayout and fontString then ApplyGridLayout(fontString) end
    end

    for index = 1, 20 do ApplyItem(_G["MerchantItem" .. index], true) end
    ApplyItem(_G.MerchantBuyBackItem, true)

    local scrollFrame = frame and frame.wSkinScrollFrame
    local rows = scrollFrame and scrollFrame.rows
    if type(rows) == "table" then
        for index = 1, #rows do ApplyItem(rows[index], false) end
    end
end

local function ApplyAuctionatorTabText(fontString, owner, selected)
    local alpha = selected and TAB_TEXT_SELECTED_ALPHA or TAB_TEXT_INACTIVE_ALPHA
    if not fontString or IsUnsafeExternalObject(fontString) or type(fontString.SetTextColor) ~= "function" then return end
    ApplyFontString(fontString, owner)
    local state = fontStates[fontString]
    if state and pcall(fontString.SetTextColor, fontString, 1, 1, 1, alpha) then
        state.lastColor = { 1, 1, 1, alpha }
    end
end

local function GetPrimaryTabFontString(tab)
    if tab and tab.Text then return tab.Text end
    if tab and type(tab.GetFontString) == "function" then
        local ok, fontString = pcall(tab.GetFontString, tab)
        if ok then return fontString end
    end
end

local function EnsureAuctionatorLabel(tab, owner, state)
    local nativeLabel = GetPrimaryTabFontString(tab)
    if not nativeLabel or IsUnsafeExternalObject(nativeLabel) then return nil end
    ApplyFontString(nativeLabel, owner)
    local nativeState = fontStates[nativeLabel]
    if nativeState and type(nativeLabel.SetTextColor) == "function"
        and pcall(nativeLabel.SetTextColor, nativeLabel, 0, 0, 0, 0)
    then
        nativeState.lastColor = { 0, 0, 0, 0 }
    end

    local label = state.label
    if not label then
        if type(tab.CreateFontString) ~= "function" then return nil end
        local ok, created = pcall(tab.CreateFontString, tab, nil, "OVERLAY")
        if not ok or not created then return nil end
        label = created
        state.label = label
        if type(nativeLabel.GetFont) == "function" and type(label.SetFont) == "function" then
            local fontOK, path, _, flags = pcall(nativeLabel.GetFont, nativeLabel)
            if fontOK and type(path) == "string" and path ~= "" then
                pcall(label.SetFont, label, path, GetTabFontSize(), flags or "")
            end
        end
        if type(label.SetPoint) == "function" then pcall(label.SetPoint, label, "CENTER", tab, "CENTER", 0, 0) end
        if type(label.SetJustifyH) == "function" then pcall(label.SetJustifyH, label, "CENTER") end
        if type(label.SetWordWrap) == "function" then pcall(label.SetWordWrap, label, false) end
    end

    local text
    if type(nativeLabel.GetText) == "function" then
        local ok, value = pcall(nativeLabel.GetText, nativeLabel)
        if ok and not IsSecretValue(value) then text = value end
    end
    if text == nil and type(tab.GetText) == "function" then
        local ok, value = pcall(tab.GetText, tab)
        if ok and not IsSecretValue(value) then text = value end
    end
    if text ~= nil and type(label.SetText) == "function" then pcall(label.SetText, label, text) end
    SetShown(label, true)
    return label
end

local function ApplyAuctionatorTabGeometry(tab, state)
    if not tab or not state or type(tab.GetHeight) ~= "function" or type(tab.SetHeight) ~= "function" then return end
    local ok, current = pcall(tab.GetHeight, tab)
    if not ok or type(current) ~= "number" or IsSecretValue(current) or current <= AUCTIONATOR_TAB_HEIGHT_TRIM then return end
    if not state.originalHeight then
        state.originalHeight = current
    elseif state.lastAppliedHeight and math.abs(current - state.lastAppliedHeight) > ALPHA_EPSILON
        and math.abs(current - state.originalHeight) > ALPHA_EPSILON
    then
        state.originalHeight = current
    end
    local target = state.originalHeight - AUCTIONATOR_TAB_HEIGHT_TRIM
    if math.abs(current - target) <= ALPHA_EPSILON or pcall(tab.SetHeight, tab, target) then
        state.lastAppliedHeight = target
    end
end

local function RestoreTabGeometry(state)
    local tab = state and state.tab
    if IsUnsafeExternalObject(tab) then return end
    if state.originalHeight and state.lastAppliedHeight
        and type(tab.GetHeight) == "function" and type(tab.SetHeight) == "function"
    then
        local ok, current = pcall(tab.GetHeight, tab)
        if ok and not IsSecretValue(current) and type(current) == "number"
            and math.abs(current - state.lastAppliedHeight) <= ALPHA_EPSILON
        then pcall(tab.SetHeight, tab, state.originalHeight) end
    end
    if state.originalWidth and state.lastAppliedWidth
        and type(tab.GetWidth) == "function" and type(tab.SetWidth) == "function"
    then
        local ok, current = pcall(tab.GetWidth, tab)
        if ok and not IsSecretValue(current) and type(current) == "number"
            and math.abs(current - state.lastAppliedWidth) <= ALPHA_EPSILON
        then pcall(tab.SetWidth, tab, state.originalWidth) end
    end
    state.lastAppliedHeight, state.lastAppliedWidth = nil, nil
end

local function EnsureTabBackground(tab, owner)
    local state = tabStates[tab]
    if not state then
        state = { owner = owner, background = CreateTexture(tab, 7) }
        tabStates[tab] = state
    end
    state.owner = owner
    return state.background
end

local function HookRefreshScript(object, script)
    if IsUnsafeExternalObject(object) or type(object.HookScript) ~= "function" then return false end
    local hooks = hookedFrames[object]
    if not hooks then
        hooks = {}
        hookedFrames[object] = hooks
    end
    if hooks[script] then return true end
    local ok = pcall(object.HookScript, object, script, function()
        if runtime.enabled then ScheduleRefresh() end
    end)
    if ok then hooks[script] = true end
    return ok
end

local function HookRefreshMethod(object, method)
    if IsUnsafeExternalObject(object) or type(method) ~= "string"
        or type(object[method]) ~= "function" or type(hooksecurefunc) ~= "function"
    then
        return false
    end
    local hooks = hookedFrames[object]
    if not hooks then
        hooks = {}
        hookedFrames[object] = hooks
    end
    local hookKey = "method:" .. method
    if hooks[hookKey] then return true end
    local ok = pcall(hooksecurefunc, object, method, function()
        if runtime.enabled then ScheduleRefresh() end
    end)
    if ok then hooks[hookKey] = true end
    return ok
end

local function EnsureTabRefreshHooks(tab)
    HookRefreshScript(tab, "OnShow")
    HookRefreshScript(tab, "OnClick")
end

function runtime.IsPilotTab(tab, owner)
    return runtime.IsPilotOwner(owner) and tabStates[tab] and tabStates[tab].shellFrame ~= nil
end

function runtime.HidePilotTabFinish(state)
    state.pilotActive, state.pilotHovered = false, nil
    if state.pilotUnderlays then
        for region, record in pairs(state.pilotUnderlays) do
            if PointsEqual(ReadRegionPoints(region), record.lastAppliedPoints) then
                SetRegionPoints(region, record.originalPoints)
            end
        end
        state.pilotUnderlays = nil
    end
    local finish = state.pilotFinish
    if not finish then return end
    SetShown(finish.fill, false)
    SetShown(finish.top, false)
    SetShown(finish.bottom, false)
end

function runtime.PaintPilotTab(tab, state)
    if not (runtime.enabled and state.pilotActive) or IsUnsafeExternalObject(tab) then return end
    local finish, style = state.pilotFinish, runtime.pilotTabStyle
    local selected = false
    if type(tab.IsEnabled) == "function" then
        local ok, enabled = pcall(tab.IsEnabled, tab)
        if ok and not IsSecretValue(enabled) then selected = enabled == false end
    end
    local custom = runtime.config.tabColorMode == TAB_COLOR_CUSTOM
    local base = custom and GetTabColor() or runtime.GetShellBaseColor()
    if not custom then
        for index = 1, 3 do base[index] = math.min(1, base[index] + 2 / 255) end
    end
    local brightness = custom and 1 or GetBrightness()
    local lift = selected and style.selectedLift or state.pilotHovered and style.hoverLift or 0
    local top, bottom = {}, {}
    for index = 1, 3 do
        top[index] = math.min(1, (base[index] + lift) * brightness)
        bottom[index] = math.max(0, top[index] - style.depth * brightness)
    end
    top[4], bottom[4] = base[4], base[4]
    local fill = finish.fill
    if fill then
        runtime.PaintFinishGradient(fill, top, bottom)
        SetShown(state.background, false)
        SetShown(fill, true)
    end
    local pixel = GetBorderPixel(tab)
    for _, edge in ipairs({ finish.top, finish.bottom }) do
        if type(edge.SetHeight) == "function" then pcall(edge.SetHeight, edge, pixel) end
        SetShown(edge, true)
    end
    if finish.top then
        pcall(finish.top.SetColorTexture, finish.top, 1, 1, 1,
            selected and style.selectedTopAlpha or style.topAlpha)
    end
    if finish.bottom then pcall(finish.bottom.SetColorTexture, finish.bottom, 0, 0, 0, style.bottomAlpha) end
end

function runtime.ApplyPilotTabFinish(tab, state, active, visualOnly)
    if not active then runtime.HidePilotTabFinish(state); return end
    if not state.pilotFinish then
        local finish = { fill = CreateTexture(tab, 7) }
        PrepareBorderTexture(finish.fill)
        for _, key in ipairs({ "top", "bottom" }) do
            local ok, edge = pcall(tab.CreateTexture, tab, nil, "BORDER", nil, 7)
            if ok and edge then
                PrepareBorderTexture(edge)
                local point = key == "top" and "TOP" or "BOTTOM"
                edge:SetPoint(point .. "LEFT", tab, point .. "LEFT", 0, 0)
                edge:SetPoint(point .. "RIGHT", tab, point .. "RIGHT", 0, 0)
                finish[key] = edge
            end
        end
        state.pilotFinish = finish
    end
    local finish = state.pilotFinish
    local window = state.shellFrame
    local topInset = 0
    if not IsUnsafeExternalObject(window) and type(tab.GetTop) == "function"
        and type(window.GetBottom) == "function" and type(tab.GetEffectiveScale) == "function"
        and type(window.GetEffectiveScale) == "function"
    then
        local ok, tabTop, windowBottom, tabScale, windowScale, tabBottom = pcall(function()
            local bottom
            if type(tab.GetBottom) == "function" then bottom = tab:GetBottom() end
            return tab:GetTop(), window:GetBottom(), tab:GetEffectiveScale(), window:GetEffectiveScale(), bottom
        end)
        if ok and not IsSecretValue(tabTop) and not IsSecretValue(windowBottom)
            and not IsSecretValue(tabScale) and not IsSecretValue(windowScale)
            and type(tabTop) == "number" and type(windowBottom) == "number"
            and type(tabScale) == "number" and type(windowScale) == "number"
            and tabScale > 0 and windowScale > 0
        then
            if not IsSecretValue(tabBottom) and type(tabBottom) == "number"
                and tabBottom >= windowBottom * windowScale / tabScale
            then
                -- 布局或版本把主标签放在窗口内部时，保留其原有材质。
                runtime.HidePilotTabFinish(state)
                return
            end
            -- 原生 Tab 可与窗口底部重叠；只裁掉装饰越过接缝的部分。
            topInset = math.max(0, tabTop - windowBottom * windowScale / tabScale)
        end
    end
    local fillPoints = {
        { point = "TOPLEFT", relativeTo = tab, relativePoint = "TOPLEFT", x = 0, y = -topInset },
        { point = "BOTTOMRIGHT", relativeTo = tab, relativePoint = "BOTTOMRIGHT", x = 0, y = 0 },
    }
    if type(tab.GetRegions) == "function" then
        local ok, regions = pcall(function() return { tab:GetRegions() } end)
        if ok then
            for index = 1, #regions do
                local region = regions[index]
                local record = state.pilotUnderlays and state.pilotUnderlays[region]
                local matches = false
                if not record and region ~= state.background and region ~= state.activeHighlight
                    and region ~= finish.fill and region ~= finish.top and region ~= finish.bottom
                    and IsTextureRegion(region)
                    and IsFullFrameRegion(region, tab)
                then
                    -- 只处理整块底板和选中高光；客户端没有 GetColorTexture 接口。
                    matches = HasDrawLayer(region, 0) or HasDrawLayer(region, -6, "ARTWORK")
                end
                if record or matches then
                    local current = ReadRegionPoints(region)
                    if current then
                        state.pilotUnderlays = state.pilotUnderlays or {}
                        record = record or { originalPoints = current }
                        if record.lastAppliedPoints and not PointsEqual(current, record.lastAppliedPoints) then
                            record.originalPoints = current
                        end
                        state.pilotUnderlays[region] = record
                        -- 原底板和选中高光也裁到接缝，保留原颜色与显示状态。
                        if SetRegionPoints(region, fillPoints) then record.lastAppliedPoints = fillPoints end
                    end
                end
            end
        end
    end
    if finish.fill then SetRegionPoints(finish.fill, fillPoints) end
    if finish.top then
        finish.top:ClearAllPoints()
        finish.top:SetPoint("TOPLEFT", finish.fill or tab, "TOPLEFT", 0, finish.fill and 0 or -topInset)
        finish.top:SetPoint("TOPRIGHT", finish.fill or tab, "TOPRIGHT", 0, finish.fill and 0 or -topInset)
    end
    state.pilotActive = true
    if not visualOnly and not state.pilotHooked and type(tab.HookScript) == "function" then
        for _, script in ipairs({ "OnEnter", "OnLeave", "OnEnable", "OnDisable", "OnHide" }) do
            pcall(tab.HookScript, tab, script, function()
                if not (runtime.enabled and state.pilotActive) then return end
                if script == "OnEnter" then state.pilotHovered = true
                elseif script == "OnLeave" or script == "OnHide" then state.pilotHovered = false end
                if script == "OnHide" then return end
                runtime.PaintPilotTab(tab, state)
            end)
        end
        state.pilotHooked = true
    end
    runtime.PaintPilotTab(tab, state)
end

local function ApplyTab(tab, owner, shellFrame)
    if IsUnsafeExternalObject(tab) then return end
    EnsureTabRefreshHooks(tab)
    local background = EnsureTabBackground(tab, owner)
    tabStates[tab].shellFrame = shellFrame
    local color = GetTabColor()
    if background and type(background.SetColorTexture) == "function" then
        pcall(background.SetColorTexture, background, color[1], color[2], color[3], color[4])
        SetShown(background, true)
    end
    runtime.ApplyPilotTabFinish(tab, tabStates[tab], runtime.IsPilotTab(tab, owner))

    local seen = {}
    local function Apply(fontString)
        if fontString and not seen[fontString] then
            seen[fontString] = true
            ApplyFontString(fontString, owner)
        end
    end
    if type(tab.GetFontString) == "function" then
        local ok, fontString = pcall(tab.GetFontString, tab)
        if ok then Apply(fontString) end
    end
    Apply(tab.Text)
    Apply(tab.Label)
    if type(tab.GetRegions) == "function" then
        local regions = { tab:GetRegions() }
        for index = 1, #regions do
            local region = regions[index]
            if region and type(region.IsObjectType) == "function" then
                local ok, isFontString = pcall(region.IsObjectType, region, "FontString")
                if ok and isFontString then Apply(region) end
            end
        end
    end
end

local function RestoreOwner(owner)
    if owner == "character" then runtime.DetachForeverStats() end
    for _, state in pairs(frameStates) do
        if state.owner == owner and not IsUnsafeExternalObject(state.frame) then
            runtime.RestorePanelUnderlays(state)
            runtime.HideDirectShellFinish(state)
            SetShown(state.visualHost, false)
            SetShown(state.background, false)
            SetShown(state.directBackground, false)
            SetShown(state.finish and state.finish.title, false)
            SetShown(state.finish and state.finish.shadow, false)
            if Appearance and state.visualHost and type(Appearance.ApplyShellFinish) == "function" then
                Appearance:ApplyShellFinish(state.visualHost, nil)
            end
            RestoreExternalBackgrounds(state)
            RestoreWindowBorder(state)
            if state.menuButton then
                SetShown(state.menuButtonHover, false)
                SetShown(state.menuButtonHoverEdge, false)
                RestoreExternalAlphaOwner(state)
            end
        end
    end
    for _, state in pairs(tabStates) do
        if state.owner == owner then
            runtime.HidePilotTabFinish(state)
            SetShown(state.background, false)
            SetShown(state.underline, false)
            SetShown(state.activeHighlight, false)
            SetShown(state.label, false)
            RestoreTabGeometry(state)
        end
    end
    for fontString, state in pairs(fontStates) do
        if state.owner == owner then
            RestoreFontString(fontString)
            fontStates[fontString] = nil
        end
    end
    RestoreExternalAlphaOwner(owner)
    RestoreMailFillOwner(owner)
end

local function RestoreAll()
    runtime.DetachForeverStats()
    if runtime.ClearAuctionShadow then runtime.ClearAuctionShadow() end
    for _, state in pairs(frameStates) do
        if not IsUnsafeExternalObject(state.frame) then
            runtime.HideDirectShellFinish(state)
            SetShown(state.visualHost, false)
            SetShown(state.background, false)
            SetShown(state.directBackground, false)
            SetShown(state.menuButtonHover, false)
            SetShown(state.menuButtonHoverEdge, false)
            SetShown(state.finish and state.finish.title, false)
            SetShown(state.finish and state.finish.shadow, false)
            if Appearance and state.visualHost and type(Appearance.ApplyShellFinish) == "function" then
                Appearance:ApplyShellFinish(state.visualHost, nil)
            end
            RestoreExternalBackgrounds(state)
            RestoreWindowBorder(state)
        end
    end
    for _, state in pairs(tabStates) do
        runtime.HidePilotTabFinish(state)
        SetShown(state.background, false)
        SetShown(state.underline, false)
        SetShown(state.activeHighlight, false)
        SetShown(state.label, false)
        RestoreTabGeometry(state)
    end
    for fontString in pairs(fontStates) do
        RestoreFontString(fontString)
        fontStates[fontString] = nil
    end
    RestoreAllExternalAlpha()
    RestoreAllMailFills()
    if RestoreReadyCheckRepair then RestoreReadyCheckRepair() end
end

local function ApplyNamedTabs(prefix, count, owner, shellFrame)
    for index = 1, count do ApplyTab(_G[prefix .. index], owner, shellFrame) end
end

local function ApplyTabSystem(tabSystem, owner, shellFrame)
    if IsUnsafeExternalObject(tabSystem) then return end
    if type(tabSystem.GetTabButton) == "function" then
        for index = 1, MAX_SOCIAL_TABS do
            local ok, tab = pcall(tabSystem.GetTabButton, tabSystem, index)
            if ok and tab then ApplyTab(tab, owner, shellFrame) end
        end
        return
    end
    if type(tabSystem.GetChildren) == "function" then
        local children = { tabSystem:GetChildren() }
        local limit = math.min(#children, MAX_SOCIAL_TABS)
        for index = 1, limit do ApplyTab(children[index], owner, shellFrame) end
    end
end

local function HookFrameOnShow(frame)
    HookRefreshScript(frame, "OnShow")
end

local function ReadObjectField(object, key)
    return object[key]
end

local function ResolveObjectPath(root, path)
    if not root or type(path) ~= "string" or path == "" then return nil end
    local current = root
    for key in path:gmatch("[^.]+") do
        local ok, value = pcall(ReadObjectField, current, key)
        if not ok or value == nil then return nil end
        current = value
    end
    return current
end

local function ApplyTabPaths(root, paths, owner, shellFrame)
    if type(paths) ~= "table" then return end
    for index = 1, #paths do ApplyTab(ResolveObjectPath(root, paths[index]), owner, shellFrame) end
end

local function ApplyTabSystemPaths(root, paths, owner, shellFrame)
    if type(paths) ~= "table" then return end
    for index = 1, #paths do ApplyTabSystem(ResolveObjectPath(root, paths[index]), owner, shellFrame) end
end

local function ApplyCollectionsFix(owner)
    local wardrobe = _G.WardrobeCollectionFrame
    local items = wardrobe and wardrobe.ItemsCollectionFrame
    if not items then return end
    HookRefreshScript(items, "OnShow")
    for _, region in ipairs({ items.Bg, items.BackgroundTile }) do
        if IsTextureRegion(region) then ApplyExternalAlpha(region, owner, 0) end
    end
end

local function FindMailFill(editBox)
    if IsUnsafeExternalObject(editBox) or type(editBox.GetRegions) ~= "function" then return nil end
    local ok, regions = pcall(function() return { editBox:GetRegions() } end)
    if not ok then return nil end
    local matches = {}
    for index = 1, #regions do
        local region = regions[index]
        if IsTextureRegion(region) and (IsFullFrameRegion(region, editBox) or mailFillStates[region] ~= nil) then
            local layerOK, layer = pcall(region.GetDrawLayer, region)
            local r, g, b = ReadColorTexture(region)
            if layerOK and layer == "BACKGROUND" and ColorNear(r, g, b, MAIL_FILL_COLOR, 0.002) then
                matches[#matches + 1] = region
            end
        end
    end
    return #matches == 1 and matches[1] or nil
end

local function ReadRight(region)
    if IsUnsafeExternalObject(region) or type(region.GetRight) ~= "function" then return nil end
    local ok, value = pcall(region.GetRight, region)
    if not ok or type(value) ~= "number" or IsSecretValue(value) then return nil end
    return value
end

local function ApplyMailFix(owner, mailFrame)
    local editBox = _G.SendMailSubjectEditBox
    local fill = FindMailFill(editBox)
    if not fill then
        RestoreMailFillOwner(owner)
        return
    end
    local frameRight, editRight = ReadRight(mailFrame), ReadRight(editBox)
    if not (frameRight and editRight) then return end
    local overflow = editRight - (frameRight - MAIL_RIGHT_INSET)
    if overflow <= 0.5 then
        RestoreMailFillOwner(owner)
        return
    end
    local record = mailFillStates[fill]
    if not record then
        local originalPoints = ReadRegionPoints(fill)
        if not originalPoints then return end
        record = { owner = owner, originalPoints = originalPoints }
        mailFillStates[fill] = record
    end
    record.owner = owner
    local applied = {
        { point = "TOPLEFT", relativeTo = editBox, relativePoint = "TOPLEFT", x = 0, y = 0 },
        { point = "BOTTOMRIGHT", relativeTo = editBox, relativePoint = "BOTTOMRIGHT", x = -overflow, y = 0 },
    }
    local current = ReadRegionPoints(fill)
    if current and PointsEqual(current, applied) then
        record.lastAppliedPoints = current
    elseif SetRegionPoints(fill, applied) then
        record.lastAppliedPoints = ReadRegionPoints(fill)
    end
end

local AUCTIONATOR_TAB_NAMES = {
    "AuctionatorTabs_Shopping",
    "AuctionatorTabs_Selling",
    "AuctionatorTabs_Cancelling",
    "AuctionatorTabs_Auctionator",
}

local function IsButtonObject(object)
    if IsUnsafeExternalObject(object) or type(object.IsObjectType) ~= "function" then return false end
    local ok, isButton = pcall(object.IsObjectType, object, "Button")
    return ok and isButton == true
end

local function IsDescendantOf(object, ancestor, maxDepth)
    local current = object
    for _ = 1, maxDepth or 4 do
        if current == ancestor then return true end
        if not current or type(current.GetParent) ~= "function" then return false end
        local ok, parent = pcall(current.GetParent, current)
        if not ok or IsSecretValue(parent) then return false end
        current = parent
    end
    return current == ancestor
end

local function TableContainsIdentity(items, target)
    if type(items) ~= "table" then return false end
    for index = 1, #items do
        if items[index] == target then return true end
    end
    return false
end

local function GetAccentColor()
    local provider = _G.EllesmereUI
    local color = type(provider) == "table" and provider.ELLESMERE_GREEN or nil
    local r, g, b = color and color.r, color and color.g, color and color.b
    if type(r) == "number" and type(g) == "number" and type(b) == "number"
        and not IsSecretValue(r) and not IsSecretValue(g) and not IsSecretValue(b)
    then
        return r, g, b
    end
    return 0.047, 0.824, 0.616
end

local function ApplyAuctionatorTab(tab, owner)
    local state = tabStates[tab]
    if type(tab.GetRegions) == "function" then
        local ok, regions = pcall(function() return { tab:GetRegions() } end)
        if ok then
            for index = 1, #regions do
                local region = regions[index]
                if IsTextureRegion(region) and (not state or (region ~= state.background
                    and region ~= state.underline and region ~= state.activeHighlight
                    and (not state.pilotFinish or (region ~= state.pilotFinish.fill
                        and region ~= state.pilotFinish.top and region ~= state.pilotFinish.bottom))))
                then
                    ApplyExternalAlpha(region, owner, 0)
                end
            end
        end
    end
    ApplyTab(tab, owner, _G.AuctionHouseFrame)
    state = tabStates[tab]
    if not state then return end
    state.tab = tab
    ApplyAuctionatorTabGeometry(tab, state)
    if not state.activeHighlight and type(tab.CreateTexture) == "function" then
        local ok, highlight = pcall(tab.CreateTexture, tab, nil, "ARTWORK", nil, -6)
        if ok and highlight then
            if type(highlight.SetAllPoints) == "function" then pcall(highlight.SetAllPoints, highlight, tab) end
            if type(highlight.SetColorTexture) == "function" then
                pcall(highlight.SetColorTexture, highlight,
                    TAB_ACTIVE_HIGHLIGHT[1], TAB_ACTIVE_HIGHLIGHT[2],
                    TAB_ACTIVE_HIGHLIGHT[3], TAB_ACTIVE_HIGHLIGHT[4])
            end
            if type(highlight.SetBlendMode) == "function" then pcall(highlight.SetBlendMode, highlight, "ADD") end
            state.activeHighlight = highlight
        end
    end
    if state.activeHighlight and type(state.activeHighlight.SetAllPoints) == "function" then
        local target = state.pilotActive and state.pilotFinish and state.pilotFinish.fill or tab
        pcall(state.activeHighlight.SetAllPoints, state.activeHighlight, target)
    end
    if not state.underline and type(tab.CreateTexture) == "function" then
        local ok, underline = pcall(tab.CreateTexture, tab, nil, "OVERLAY", nil, 6)
        if ok and underline then
            local r, g, b = GetAccentColor()
            if type(underline.SetColorTexture) == "function" then pcall(underline.SetColorTexture, underline, r, g, b, 1) end
            if type(underline.SetPoint) == "function" then
                pcall(underline.SetPoint, underline, "BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
                pcall(underline.SetPoint, underline, "BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
            end
            if type(underline.SetHeight) == "function" then pcall(underline.SetHeight, underline, GetBorderPixel(tab)) end
            state.underline = underline
        end
    end
    HookRefreshScript(tab, "OnEnable")
    HookRefreshScript(tab, "OnDisable")
    local selected = false
    if type(tab.IsEnabled) == "function" then
        local ok, enabled = pcall(tab.IsEnabled, tab)
        if ok and not IsSecretValue(enabled) then selected = enabled == false end
    end
    local label = EnsureAuctionatorLabel(tab, owner, state)
    ApplyAuctionatorTabText(label, owner, selected)
    SetShown(state.activeHighlight, selected)
    SetShown(state.underline, selected)
end

local function ApplyAuctionatorFix(_, auctionFrame)
    local owner = AUCTIONATOR_OWNER
    local container = _G.AuctionatorAHTabsContainer
    local containerTabs = container and container.Tabs
    local tabs = {}
    if type(containerTabs) ~= "table" then
        RestoreOwner(owner)
        return
    end
    for index = 1, #AUCTIONATOR_TAB_NAMES do
        local tab = _G[AUCTIONATOR_TAB_NAMES[index]]
        if not IsButtonObject(tab) or not TableContainsIdentity(containerTabs, tab)
            or not IsDescendantOf(tab, auctionFrame, 4)
        then
            RestoreOwner(owner)
            return
        end
        tabs[index] = tab
    end
    for index = 1, #tabs do ApplyAuctionatorTab(tabs[index], owner) end
end

local function ApplyAchievementRefreshHooks()
    local comparison = _G.AchievementFrameComparison
    HookRefreshScript(comparison, "OnShow")
    HookRefreshScript(comparison, "OnHide")
end

local function ApplyHousingTabs(owner, frame)
    local content = ResolveObjectPath(frame, "HouseInfoContent.ContentFrame")
    ApplyTabSystem(content and content.TabSystem, owner)
    HookRefreshMethod(content, "UpdateTabs")
end

local function ApplyProfessionsTabs(owner, frame)
    local specPage = frame and frame.SpecPage
    local pool = specPage and specPage.tabsPool
    if pool and type(pool.EnumerateActive) == "function" then
        pcall(function()
            for tab in pool:EnumerateActive() do
                if IsButtonObject(tab) then ApplyTab(tab, owner) end
            end
        end)
    end
    HookRefreshMethod(specPage, "UpdateTabs")

    local ordersPage = frame and frame.OrdersPage
    local browse = ordersPage and ordersPage.BrowseFrame
    for _, key in ipairs({ "PublicOrdersButton", "NpcOrdersButton", "GuildOrdersButton", "PersonalOrdersButton" }) do
        local tab = browse and browse[key]
        if IsButtonObject(tab) then ApplyTab(tab, owner) end
    end
    HookRefreshMethod(ordersPage, "SetCraftingOrderType")
end

local function ApplyTransmogTabs(owner, frame)
    local headers = ResolveObjectPath(frame, "WardrobeCollection.TabHeaders")
    if IsUnsafeExternalObject(headers) or type(headers.GetChildren) ~= "function" then return end
    local ok, children = pcall(function() return { headers:GetChildren() } end)
    if not ok then return end
    local limit = math.min(#children, MAX_SOCIAL_TABS)
    for index = 1, limit do
        if IsButtonObject(children[index]) then ApplyTab(children[index], owner) end
    end
    HookRefreshScript(headers, "OnShow")
end

local function ApplyCraftOrderTabs(owner, frame)
    local tabs = frame and frame.Tabs
    if type(tabs) ~= "table" then return end
    local limit = math.min(#tabs, MAX_SOCIAL_TABS)
    for index = 1, limit do
        if IsButtonObject(tabs[index]) then ApplyTab(tabs[index], owner, frame) end
    end
end

local function ApplyPlayerChoiceRefreshHooks(_, frame)
    HookRefreshMethod(frame, "SetupFrame")
    HookRefreshMethod(frame, "SetupOptions")
    HookRefreshMethod(frame, "SetupOptionsAsGrid")
end

RestoreReadyCheckRepair = function()
    local listener = readyCheckRepairState.listener
    if readyCheckRepairState.forced == true and IsObjectShown(listener) then SetShown(listener, false) end
    readyCheckRepairState.listener = nil
    readyCheckRepairState.forced = false
end

local function ApplyReadyCheckRepair(_, frame)
    HookRefreshScript(frame, "OnHide")
    if not IsObjectShown(frame) then
        readyCheckRepairState.listener = nil
        readyCheckRepairState.forced = false
        return
    end

    local listener = _G.ReadyCheckListenerFrame
    if not listener then return end
    local initiatedByPlayer = false
    if frame.initiator and type(UnitIsUnit) == "function" then
        local ok, sameUnit = pcall(UnitIsUnit, "player", frame.initiator)
        initiatedByPlayer = ok and sameUnit == true
    end
    if IsObjectShown(listener) then
        if not initiatedByPlayer then
            readyCheckRepairState.listener = nil
            readyCheckRepairState.forced = false
        end
        return
    end

    SetShown(listener, true)
    if IsObjectShown(listener) then
        readyCheckRepairState.listener = listener
        readyCheckRepairState.forced = true
    end
end

local WINDOW_ADAPTERS = {
    {
        owner = "blizzard:collections",
        styleKey = "collections",
        addon = "Blizzard_Collections",
        frameName = "CollectionsJournal",
        tabPaths = { "MountsTab", "PetsTab", "ToysTab", "HeirloomsTab", "WardrobeTab", "WarbandScenesTab" },
        innerGlobalTabPaths = { "WardrobeCollectionFrame.ItemsTab", "WardrobeCollectionFrame.SetsTab" },
        postApply = ApplyCollectionsFix,
    },
    {
        owner = "blizzard:playerspells",
        styleKey = "playerspells",
        addon = "Blizzard_PlayerSpells",
        frameName = "PlayerSpellsFrame",
        tabSystemPaths = { "TabSystem" },
        innerTabSystemPaths = { "SpellBookFrame.CategoryTabSystem" },
    },
    {
        owner = "blizzard:adventureguide",
        styleKey = "adventureguide",
        addon = "Blizzard_EncounterJournal",
        frameName = "EncounterJournal",
        tabPaths = {
            "JourneysTab", "MonthlyActivitiesTab", "suggestTab", "dungeonsTab",
            "raidsTab", "LootJournalTab", "TutorialsTab",
        },
    },
    {
        owner = "blizzard:worldmap",
        styleKey = "worldmap",
        addon = "Blizzard_WorldMap",
        frameName = "WorldMapFrame",
    },
    {
        owner = "blizzard:merchant",
        styleKey = "merchant",
        frameName = "MerchantFrame",
        globalTabPaths = { "MerchantFrameTab1", "MerchantFrameTab2" },
        postApply = ApplyMerchantItemNameFonts,
    },
    {
        owner = "blizzard:trade",
        styleKey = "trade",
        frameName = "TradeFrame",
    },
    {
        owner = "blizzard:loot",
        styleKey = "loot",
        frameName = "LootFrame",
    },
    {
        owner = "blizzard:loothistory",
        styleKey = "loothistory",
        frameName = "GroupLootHistoryFrame",
        deferUntilShown = true,
    },
    {
        owner = "blizzard:gossip",
        styleKey = "gossip",
        frameName = "GossipFrame",
    },
    {
        owner = "blizzard:quest",
        styleKey = "quest",
        frameName = "QuestFrame",
    },
    {
        owner = "blizzard:mail",
        styleKey = "mail",
        addon = "Blizzard_MailFrame",
        frameName = "MailFrame",
        globalTabPaths = { "MailFrameTab1", "MailFrameTab2" },
        postApply = ApplyMailFix,
    },
    {
        owner = "blizzard:auctionhouse",
        styleKey = "auctionhouse",
        addon = "Blizzard_AuctionHouseUI",
        frameName = "AuctionHouseFrame",
        globalTabPaths = {
            "AuctionHouseFrameBuyTab", "AuctionHouseFrameSellTab", "AuctionHouseFrameAuctionsTab",
        },
        innerGlobalTabPaths = {
            "AuctionHouseFrameAuctionsFrameAuctionsTab", "AuctionHouseFrameAuctionsFrameBidsTab",
        },
        postApply = ApplyAuctionatorFix,
        postRestore = function() RestoreOwner(AUCTIONATOR_OWNER) end,
    },
    {
        owner = "blizzard:achievements",
        styleKey = "achievements",
        addon = "Blizzard_AchievementUI",
        frameName = "AchievementFrame",
        globalTabPaths = { "AchievementFrameTab1", "AchievementFrameTab2", "AchievementFrameTab3" },
        postApply = ApplyAchievementRefreshHooks,
    },
    {
        owner = "blizzard:inspect",
        styleKey = "inspect",
        addon = "Blizzard_InspectUI",
        frameName = "InspectFrame",
        globalTabPaths = { "InspectFrameTab1", "InspectFrameTab2", "InspectFrameTab3" },
    },
    {
        owner = "blizzard:readycheck",
        styleKey = "readycheck",
        frameName = "ReadyCheckFrame",
        skipShell = true,
        postApply = ApplyReadyCheckRepair,
        postRestore = RestoreReadyCheckRepair,
    },
    {
        owner = "blizzard:guild",
        styleKey = "guild",
        addon = "Blizzard_Communities",
        frameName = "CommunitiesFrame",
    },
    {
        owner = "blizzard:calendar",
        styleKey = "calendar",
        addon = "Blizzard_Calendar",
        frameName = "CalendarFrame",
    },
    {
        owner = "blizzard:calendar:holiday",
        styleKey = "calendar",
        addon = "Blizzard_Calendar",
        frameName = "CalendarViewHolidayFrame",
    },
    {
        owner = "blizzard:calendar:create-event",
        styleKey = "calendar",
        addon = "Blizzard_Calendar",
        frameName = "CalendarCreateEventFrame",
    },
    {
        owner = "blizzard:calendar:event-picker",
        styleKey = "calendar",
        addon = "Blizzard_Calendar",
        frameName = "CalendarEventPickerFrame",
    },
    {
        owner = "blizzard:dressup",
        styleKey = "dressup",
        frameName = "DressUpFrame",
    },
    {
        owner = "blizzard:macros",
        styleKey = "macros",
        addon = "Blizzard_MacroUI",
        frameName = "MacroFrame",
        globalTabPaths = { "MacroFrameTab1", "MacroFrameTab2" },
    },
    {
        owner = "blizzard:settings",
        styleKey = "settings",
        frameName = "SettingsPanel",
        innerTabPaths = { "GameTab", "AddOnsTab" },
    },
    {
        owner = "blizzard:addonlist",
        styleKey = "addonlist",
        frameName = "AddonList",
    },
    {
        owner = "blizzard:professionsbook",
        styleKey = "professionsbook",
        addon = "Blizzard_ProfessionsBook",
        frameName = "ProfessionsBookFrame",
    },
    {
        owner = "blizzard:professionsbook:archaeology",
        styleKey = "professionsbook",
        addon = "Blizzard_ArchaeologyUI",
        frameName = "ArchaeologyFrame",
    },
    {
        owner = "blizzard:housing",
        styleKey = "housing",
        addon = "Blizzard_HousingDashboard",
        frameName = "HousingDashboardFrame",
        postApply = ApplyHousingTabs,
    },
    {
        owner = "blizzard:professions",
        styleKey = "professions",
        addon = "Blizzard_Professions",
        frameName = "ProfessionsFrame",
        tabSystemPaths = { "TabSystem" },
        postApply = ApplyProfessionsTabs,
    },
    {
        owner = "blizzard:inspectrecipe",
        styleKey = "inspectrecipe",
        addon = "Blizzard_Professions",
        frameName = "InspectRecipeFrame",
    },
    {
        owner = "blizzard:transmog",
        styleKey = "transmog",
        addon = "Blizzard_Transmog",
        frameName = "TransmogFrame",
        postApply = ApplyTransmogTabs,
    },
    {
        owner = "blizzard:craftorders",
        styleKey = "craftorders",
        addon = "Blizzard_ProfessionsCustomerOrders",
        frameName = "ProfessionsCustomerOrdersFrame",
        postApply = ApplyCraftOrderTabs,
    },
    {
        owner = "blizzard:trainer",
        styleKey = "trainer",
        addon = "Blizzard_TrainerUI",
        frameName = "ClassTrainerFrame",
    },
    {
        owner = "blizzard:catalyst",
        styleKey = "catalyst",
        addon = "Blizzard_ItemInteractionUI",
        frameName = "ItemInteractionFrame",
    },
    {
        owner = "blizzard:socket",
        styleKey = "socket",
        addon = "Blizzard_ItemSocketingUI",
        frameName = "ItemSocketingFrame",
    },
    {
        owner = "blizzard:itemupgrade",
        styleKey = "itemupgrade",
        addon = "Blizzard_ItemUpgradeUI",
        frameName = "ItemUpgradeFrame",
    },
    {
        owner = "blizzard:delves",
        styleKey = "delves",
        addon = "Blizzard_DelvesCompanionConfiguration",
        frameName = "DelvesCompanionConfigurationFrame",
    },
    {
        owner = "blizzard:delves:abilities",
        styleKey = "delves",
        addon = "Blizzard_DelvesCompanionConfiguration",
        frameName = "DelvesCompanionAbilityListFrame",
    },
    {
        owner = "blizzard:queuestatus",
        styleKey = "queuestatus",
        addon = "Blizzard_QueueStatusFrame",
        frameName = "QueueStatusFrame",
        deferUntilShown = true,
    },
    {
        owner = "blizzard:playerchoice",
        styleKey = "playerchoice",
        addon = "Blizzard_PlayerChoice",
        frameName = "PlayerChoiceFrame",
        deferUntilShown = true,
        postApply = ApplyPlayerChoiceRefreshHooks,
    },
}

runtime.ApplyProtectedLFGAdapter = function()
    local frame = _G.PVEFrame
    if runtime.isForever then frame = _G.LFGParentFrame end
    local addon = runtime.isForever and "Blizzard_GroupFinder_VanillaStyle" or "Blizzard_GroupFinder"
    if not frame or IsUnsafeExternalObject(frame)
        or not IsAddOnLoadedSafe("EllesmereUIBlizzardSkin")
        or not IsAddOnLoadedSafe(addon)
        or not GetWindowStyle("lfg")
    then
        RestoreOwner("blizzard:lfg")
        return
    end

    local state = ApplyFrameBackground(frame, "blizzard:lfg", "protected-visual", true)
    if state then ApplyWindowBorder(frame, state) end
    local tabPrefix = runtime.isForever and "LFGParentFrameTab" or "PVEFrameTab"
    for index = 1, (runtime.isForever and 3 or 4) do
        local tab = _G[tabPrefix .. index]
        if not IsUnsafeExternalObject(tab) then
            local background = EnsureTabBackground(tab, "blizzard:lfg")
            local color = GetTabColor()
            if background and type(background.SetColorTexture) == "function" then
                pcall(background.SetColorTexture, background, color[1], color[2], color[3], color[4])
                SetShown(background, true)
            end

            local state = tabStates[tab]
            state.shellFrame = frame
            runtime.ApplyPilotTabFinish(tab, state, runtime.IsPilotTab(tab, "blizzard:lfg"), true)

            local nativeLabel
            if type(tab.GetFontString) == "function" then
                local ok, fontString = pcall(tab.GetFontString, tab)
                if ok then nativeLabel = fontString end
            end
            if type(tab.GetRegions) == "function" then
                local regions = { pcall(tab.GetRegions, tab) }
                if table.remove(regions, 1) then
                    for regionIndex = 1, #regions do
                        local region = regions[regionIndex]
                        if region and region ~= nativeLabel and type(region.IsObjectType) == "function" then
                            local ok, isFontString = pcall(region.IsObjectType, region, "FontString")
                            if ok and isFontString then ApplyFontString(region, "blizzard:lfg") end
                        end
                    end
                end
            end
        end
    end
end

local function ApplyWindowAdapter(adapter)
    local owner = adapter.owner
    local frame = _G[adapter.frameName]
    HookFrameOnShow(frame)
    if frame and IsUnsafeExternalObject(frame) then return end
    if not frame or not IsAddOnLoadedSafe("EllesmereUIBlizzardSkin")
        or (adapter.addon and not IsAddOnLoadedSafe(adapter.addon))
        or not GetWindowStyle(adapter.styleKey)
    then
        RestoreOwner(owner)
        if type(adapter.postRestore) == "function" then adapter.postRestore() end
        return
    end
    if adapter.deferUntilShown == true and not IsObjectShown(frame) then return end

    if adapter.skipShell ~= true then
        local state = ApplyFrameBackground(frame, owner, "shell")
        if state then ApplyWindowBorder(frame, state) end
    end
    ApplyTabPaths(frame, adapter.tabPaths, owner, frame)
    ApplyTabPaths(_G, adapter.globalTabPaths, owner, frame)
    ApplyTabSystemPaths(frame, adapter.tabSystemPaths, owner, frame)
    ApplyTabPaths(frame, adapter.innerTabPaths, owner)
    ApplyTabPaths(_G, adapter.innerGlobalTabPaths, owner)
    ApplyTabSystemPaths(frame, adapter.innerTabSystemPaths, owner)
    if type(adapter.postApply) == "function" then adapter.postApply(owner, frame) end
end

local function IsSocialUIActive()
    local api = _G.C_SocialUI
    if not (api and type(api.IsSystemEnabled) == "function") then return false end
    local ok, active = pcall(api.IsSystemEnabled)
    return ok and active == true
end

local function ApplyCharacter()
    local frame = _G.CharacterFrame
    HookFrameOnShow(frame)
    if frame and IsUnsafeExternalObject(frame) then return end
    if not (not IsUnsafeExternalObject(frame) and IsAddOnLoadedSafe("EllesmereUIBlizzardSkin") and GetWindowStyle("charsheet")) then
        RestoreOwner("character")
        return
    end
    local state = ApplyFrameBackground(frame, "character", "shell")
    if state then ApplyWindowBorder(frame, state) end
    ApplyNamedTabs("CharacterFrameTab", 3, "character", frame)
    ApplyCharacterDetailFonts("character")
end

function runtime.ApplyFriendsSubTabs(frame)
    local list = _G.FriendsListFrame
    if IsUnsafeExternalObject(frame) or IsUnsafeExternalObject(list) or type(frame.GetChildren) ~= "function" then return end
    local ok, children = pcall(function() return { frame:GetChildren() } end)
    if not ok or #children > 64 then return end
    local candidates, tabs = {}, {}
    for index = 1, #children do
        local child = children[index]
        if not IsUnsafeExternalObject(child) and type(child.IsObjectType) == "function" then
            local buttonOK, isButton = pcall(child.IsObjectType, child, "Button")
            local labelOK, label = pcall(function() return child._label end)
            if buttonOK and not IsSecretValue(isButton) and isButton == true and labelOK and not IsSecretValue(label)
                and (type(label) == "table" or type(label) == "userdata") and not IsUnsafeExternalObject(label)
                and type(label.IsObjectType) == "function"
            then
                local fontOK, isFont = pcall(label.IsObjectType, label, "FontString")
                local points, labelPoints = ReadRegionPoints(child), ReadRegionPoints(label)
                if fontOK and not IsSecretValue(isFont) and isFont == true and points and #points == 1 and labelPoints and #labelPoints == 1
                    and HasAnchor(labelPoints, "LEFT", child, "LEFT", 0, 0)
                then candidates[#candidates + 1] = { tab = child, label = label, points = points } end
            end
        end
    end
    -- 只接受已知首项及顺次锚定的子标签；同位置出现多个候选时保持原外观。
    local previous = list
    for index = 1, MAX_SOCIAL_TABS + 1 do
        local match
        for _, candidate in ipairs(candidates) do
            local anchor = index == 1
                and HasAnchor(candidate.points, "TOPLEFT", list, "TOPLEFT", 15, -70)
                or index > 1 and HasAnchor(candidate.points, "LEFT", previous, "RIGHT", 20, 0)
            if anchor then
                if match then return end
                match = candidate
            end
        end
        if not match then break end
        if index > MAX_SOCIAL_TABS then return end
        tabs[#tabs + 1], previous = match, match.tab
    end
    if #tabs < 2 then return end
    for _, candidate in ipairs(tabs) do
        local tab, label = candidate.tab, candidate.label
        ApplyTab(tab, "friends")
        if type(tab.GetWidth) == "function" and type(tab.SetWidth) == "function" and type(label.GetStringWidth) == "function" then
            local widthOK, width = pcall(tab.GetWidth, tab)
            local textOK, textWidth = pcall(label.GetStringWidth, label)
            if widthOK and textOK and not IsSecretValue(width) and not IsSecretValue(textWidth)
                and type(width) == "number" and type(textWidth) == "number" and width > 0 and textWidth > 0
            then
                local state = tabStates[tab]
                state.tab, state.originalWidth = tab, width
                if math.abs(width - textWidth) <= ALPHA_EPSILON or pcall(tab.SetWidth, tab, textWidth) then
                    state.lastAppliedWidth = textWidth
                end
            end
        end
    end
end

local function ApplyFriends()
    RestoreOwner("friends")
    if IsSocialUIActive() then
        local frame = _G.SocialUIFrame
        HookFrameOnShow(frame)
        if frame and IsUnsafeExternalObject(frame) then return end
        if not (not IsUnsafeExternalObject(frame) and IsAddOnLoadedSafe("EllesmereUIBlizzardSkin") and GetWindowStyle("socialui")) then return end
        local state = ApplyFrameBackground(frame, "friends", "shell")
        if state then ApplyWindowBorder(frame, state) end
        local header = _G.FriendsTabHeader or frame.FriendsTabHeader
        ApplyTabSystem(header and header.TabSystem, "friends")
        return
    end

    local frame = _G.FriendsFrame
    HookFrameOnShow(frame)
    if frame and IsUnsafeExternalObject(frame) then return end
    if runtime.isForever then
        if not (not IsUnsafeExternalObject(frame) and IsAddOnLoadedSafe("EllesmereUIBlizzardSkin")
            and GetWindowStyle("socialui")) then return end
        local state = ApplyFrameBackground(frame, "friends", "shell")
        if state then ApplyWindowBorder(frame, state) end
        local header = frame.FriendsTabHeader or _G.FriendsTabHeader
        ApplyTabSystem(header and header.TabSystem, "friends")
        ApplyNamedTabs("FriendsFrameTab", 4, "friends", frame)
        return
    end
    if not (not IsUnsafeExternalObject(frame) and IsAddOnLoadedSafe("EllesmereUIFriends") and type(_G._EFR_ApplyFriends) == "function") then return end
    local state = ApplyFrameBackground(frame, "friends", "legacyFriends")
    if state then ApplyWindowBorder(frame, state, 2) end
    ApplyNamedTabs("FriendsFrameTab", 4, "friends", frame)
    runtime.ApplyFriendsSubTabs(frame)
end

local function CopyContext(context)
    local copy = {}
    for key, value in pairs(context or {}) do copy[key] = value end
    return copy
end

local function BuildEnhancedContext(context, options)
    if not runtime.enabled or type(context) ~= "table" or context.source ~= "ellesmere" then return nil end
    local enhanced = CopyContext(context)
    if runtime.config and runtime.config.simplifyWindowBorder == true then
        enhanced.border = CopyColor(CLEAN_BORDER_COLOR)
        enhanced.cleanBorderAtlas = WINDOW_BORDER_ATLAS
    end
    if not IsBackgroundBeautificationEnabled() then return enhanced end

    enhanced.customShell = true
    enhanced.providerKind = "yui-enhanced"
    enhanced.texture = nil
    enhanced.textureMode = nil
    enhanced.textureCoords = nil
    enhanced.textureAspect = nil
    enhanced.textureColor = nil
    enhanced.textureTile = nil
    enhanced.overlayTexture = nil
    enhanced.overlayColor = nil
    enhanced.overlayTile = nil
    enhanced.overlay = nil
    enhanced.stripe = nil
    enhanced.background = GetDarkenedBackgroundColor()
    enhanced.background[4] = 1
    enhanced.topBar = { 0, 0, 0, 0.20 }
    enhanced.contentShade = { 0, 0, 0, 0.08 }
    options = options or {}
    enhanced.shellFinish = runtime.GetPilotFinish(options.shellHeaderHeight or 25)
    if options.noTopBar == true then enhanced.shellFinish.title = nil end
    return enhanced
end

local function RegisterAppearanceOverride()
    if runtime.overrideRegistered or not Appearance
        or type(Appearance.RegisterContextOverride) ~= "function"
    then
        return
    end
    runtime.overrideRegistered = Appearance:RegisterContextOverride(appearanceOverrideOwner, 100, function(context, _, options)
        return BuildEnhancedContext(context, options)
    end) == true
end

local function UnregisterAppearanceOverride()
    if not runtime.overrideRegistered then return end
    runtime.overrideRegistered = false
    if Appearance and type(Appearance.UnregisterContextOverride) == "function" then
        Appearance:UnregisterContextOverride(appearanceOverrideOwner)
    end
end

local function RefreshSharedAppearance()
    if Appearance and type(Appearance.RefreshAll) == "function" then Appearance:RefreshAll() end
end

function runtime.ClearAuctionShadow()
    if Appearance and type(Appearance.SetShellShadowLayout) == "function" then
        for _, frame in ipairs(runtime.auctionShadowMembers) do Appearance:SetShellShadowLayout(frame) end
    end
    runtime.auctionShadowMembers = {}
end

function runtime.UpdateAuctionShadow()
    runtime.ClearAuctionShadow()
    if not (Appearance and type(Appearance.SetShellShadowLayout) == "function"
        and type(Appearance.GetContext) == "function") then return end
    local auction, helper = _G.AuctionHouseFrame, YUI.AuctionHelperFrame
    if IsUnsafeExternalObject(helper) then return end
    local settings, tracker = helper.settingsFrame, helper.recipeTracker and helper.recipeTracker.panel
    for _, panel in pairs({ helper = helper, settings = settings, tracker = tracker }) do
        HookRefreshScript(panel, "OnShow")
        HookRefreshScript(panel, "OnHide")
        HookRefreshMethod(panel, "SetPoint")
    end
    local rootState = auction and frameStates[auction]
    if not (runtime.IsPilotOwner() and rootState and rootState.finish and rootState.finish.shadowSize
        and not IsUnsafeExternalObject(auction) and auction:IsShown()) then return end
    local root, parent = rootState.visualHost, auction
    local members = { root }
    local function Include(panel)
        if IsUnsafeExternalObject(panel) or not panel:IsShown() then return false end
        local context, points = Appearance:GetContext(panel), ReadRegionPoints(panel)
        if not (context and context.source == "ellesmere" and context.shellFinish
            and points and #points == 2
            and HasAnchor(points, "TOPLEFT", parent, "TOPRIGHT", 2, 0)
            and HasAnchor(points, "BOTTOMLEFT", parent, "BOTTOMRIGHT", 2, 0)) then return false end
        members[#members + 1], parent = panel, panel
        return true
    end
    if Include(helper) then
        if not Include(settings) then Include(tracker) end
    end
    if #members < 2 then return end
    runtime.auctionShadowMembers = members
    Appearance:SetShellShadowLayout(root, parent)
    for index = 2, #members do Appearance:SetShellShadowLayout(members[index], nil, true) end
end

function runtime.CanStyleGameMenu()
    local provider, db = _G.EllesmereUI, _G.EllesmereUIDB
    if not (runtime.enabled and IsBackgroundBeautificationEnabled() and type(provider) == "table"
        and IsAddOnLoadedSafe("EllesmereUIBlizzardSkin")) or (db and db.reskinGameMenu == false) then return false end
    if type(provider.BlizzSkinPadStandDown) == "function" then
        local ok, standDown = pcall(provider.BlizzSkinPadStandDown)
        if not ok or IsSecretValue(standDown) or standDown then return false end
    end
    return true
end

function runtime.GetGameMenuButtonFinish()
    local style = runtime.menuStyle.button
    return {
        background = { top = CopyColor(style.background.top), bottom = CopyColor(style.background.bottom) },
        border = CopyColor(style.border), topBorder = CopyColor(style.topBorder),
        bottomBorder = CopyColor(style.bottomBorder), textColor = CopyColor(style.textColor),
    }
end

function runtime.ApplyGameMenuButtonHighlight(inset, state)
    local button = inset:GetParent()
    if type(button.CreateTexture) ~= "function" then return end
    -- 原生 HIGHLIGHT 层负责悬停及禁用状态，不添加脚本钩子或逐帧刷新。
    if not state.menuButtonHover then
        local ok, texture = pcall(button.CreateTexture, button, nil, "HIGHLIGHT", nil, 1)
        if not ok or not texture then return end
        state.menuButtonHover = texture
        texture:SetAllPoints(inset)
        runtime.PaintFinishGradient(texture, runtime.menuStyle.hover.top, runtime.menuStyle.hover.bottom)
    end
    if not state.menuButtonHoverEdge then
        local ok, texture = pcall(button.CreateTexture, button, nil, "HIGHLIGHT", nil, 2)
        if not ok or not texture then return end
        state.menuButtonHoverEdge = texture
        texture:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, 0)
        texture:SetPoint("TOPRIGHT", inset, "TOPRIGHT", 0, 0)
        texture:SetHeight(GetBorderPixel(button))
        local color = runtime.menuStyle.hover.edge
        texture:SetColorTexture(color[1], color[2], color[3], color[4])
    end
    SetShown(state.menuButtonHover, true)
    SetShown(state.menuButtonHoverEdge, true)
end

-- 只识别菜单直属按钮的既有 2px 内层底板，不接触按钮池或 provider 私有表。
function runtime.IsGameMenuButtonInset(inset)
    if IsUnsafeExternalObject(inset) or type(inset.GetParent) ~= "function" then return false end
    local ok, button = pcall(inset.GetParent, inset)
    if not ok or IsUnsafeExternalObject(button) or type(button.GetParent) ~= "function"
        or type(button.IsObjectType) ~= "function" then return false end
    local parentOK, parent = pcall(button.GetParent, button)
    local typeOK, isButton = pcall(button.IsObjectType, button, "Button")
    if not parentOK or IsSecretValue(parent) or parent ~= _G.GameMenuFrame
        or not typeOK or IsSecretValue(isButton) or not isButton then return false end
    local points = ReadRegionPoints(inset)
    if not points or #points ~= 2 or not HasAnchor(points, "TOPLEFT", button, "TOPLEFT", 2, -2)
        or not HasAnchor(points, "BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
        or type(inset.GetRegions) ~= "function" then return false end
    local regionsOK, regions = pcall(function() return { inset:GetRegions() } end)
    if not regionsOK or #regions > 16 then return false end
    local count = 0
    for _, region in ipairs(regions) do
        if not IsUnsafeExternalObject(region) and IsTextureRegion(region) and HasDrawLayer(region, -6)
            and IsFullFrameRegion(region, inset) then count = count + 1 end
    end
    return count == 1
end

function runtime.PaintGameMenuButton(inset, border)
    if IsInCombat() or not runtime.CanStyleGameMenu() or not runtime.IsGameMenuButtonInset(inset) then return end
    local state = frameStates[inset]
    if not state then
        state = { frame = inset, owner = "blizzard:gamemenu", menuButton = true }
        frameStates[inset] = state
    end
    if border then state.menuButtonBorder = border end
    if not state.menuButtonBorder then return end
    if not state.directBackground then
        state.directBackground = CreateTexture(inset, -5)
        if not state.directBackground then return end
        state.directBackground:SetAllPoints(inset)
    end
    if not EnsureCleanBorder(inset, state) then return end
    local finish = runtime.menuButtonFinish
    if not finish then return end
    ApplyExternalAlpha(state.menuButtonBorder, state, 0)
    if state.menuButtonFinish ~= finish or not IsObjectShown(state.directBackground) then
        runtime.PaintFinishGradient(state.directBackground, finish.background.top, finish.background.bottom)
        for index, line in ipairs(state.cleanBorders) do
            local color = index == 1 and finish.topBorder or index == 2 and finish.bottomBorder or finish.border
            line:SetColorTexture(color[1], color[2], color[3], color[4])
        end
        state.menuButtonFinish = finish
    end
    SetShown(state.directBackground, true)
    runtime.ApplyGameMenuButtonHighlight(inset, state)
end

function runtime.RefreshGameMenuButtons(menu, provider)
    -- 设置切换时覆盖已显示的按钮；新建/复用的按钮由既有边框绘制回调接入。
    for inset, state in pairs(frameStates) do
        if state.menuButton and not IsUnsafeExternalObject(inset) and not runtime.IsGameMenuButtonInset(inset) then
            SetShown(state.directBackground, false)
            SetShown(state.menuButtonHover, false)
            SetShown(state.menuButtonHoverEdge, false)
            SetCleanBorderShown(state, false)
            RestoreExternalAlphaOwner(state)
        end
    end
    if type(menu.GetChildren) ~= "function" then return end
    local ok, children = pcall(function() return { menu:GetChildren() } end)
    if not ok or #children > 64 then return end
    for _, button in ipairs(children) do
        if not IsUnsafeExternalObject(button) and type(button.GetChildren) == "function" then
            local childOK, insets = pcall(function() return { button:GetChildren() } end)
            if childOK and #insets <= 16 then
                for _, inset in ipairs(insets) do
                    if runtime.IsGameMenuButtonInset(inset) then
                        local state = frameStates[inset]
                        if not (state and state.menuButtonBorder) then
                            pcall(provider._applyBlizzardConfiguredBorder, inset, "popupMenuButton", 1)
                        end
                        runtime.PaintGameMenuButton(inset)
                    end
                end
            end
        end
    end
end

function runtime.ApplyGameMenu()
    local frame, provider, owner = _G.GameMenuFrame, _G.EllesmereUI, "blizzard:gamemenu"
    if not runtime.CanStyleGameMenu() or IsUnsafeExternalObject(frame)
        or type(provider._applyBlizzardConfiguredBorder) ~= "function"
        or type(provider.ApplyBorderStyle) ~= "function" then RestoreOwner(owner); return end
    local state = ApplyFrameBackground(frame, owner, "gameMenu")
    if not state then return end
    runtime.menuButtonFinish = runtime.GetGameMenuButtonFinish()
    -- 从已确认的绘制调用捕获外框及按钮边框，状态保存在外部弱键表。
    if not runtime.menuCaptureHooked then
        runtime.menuCaptureHooked = pcall(hooksecurefunc, provider, "ApplyBorderStyle", function(border)
            if not runtime.enabled or IsUnsafeExternalObject(border) or type(border.GetParent) ~= "function" then return end
            local ok, parent = pcall(border.GetParent, border)
            if not ok or IsSecretValue(parent) then return end
            if runtime.menuBorderProbe and parent == _G.GameMenuFrame and IsFullFrameRegion(border, parent) then
                local current = frameStates[parent]
                if current then current.menuBorder = border end
            elseif runtime.CanStyleGameMenu() and runtime.IsGameMenuButtonInset(parent)
                and IsFullFrameRegion(border, parent) then
                runtime.PaintGameMenuButton(parent, border)
            end
        end)
    end
    if not runtime.menuStyleHooked then
        runtime.menuStyleHooked = pcall(hooksecurefunc, provider, "_applyBlizzardConfiguredBorder", function(menu, prefix)
            if runtime.menuBorderProbe or menu ~= _G.GameMenuFrame or prefix ~= "popupMenu" then return end
            local current = frameStates[menu]
            if runtime.CanStyleGameMenu() and current and runtime.config.simplifyWindowBorder then
                ApplyExternalAlpha(current.menuBorder, owner, 0)
            end
            if runtime.enabled then ScheduleRefresh() end
        end)
    end
    if not state.menuBorder and runtime.menuCaptureHooked then
        runtime.menuBorderProbe = true
        pcall(provider._applyBlizzardConfiguredBorder, frame, "popupMenu", 1)
        runtime.menuBorderProbe = false
    end
    if runtime.config.simplifyWindowBorder and state.menuBorder and EnsureCleanBorder(state.visualHost, state) then
        ApplyExternalAlpha(state.menuBorder, owner, 0)
        local color = runtime.menuStyle.border
        for _, line in ipairs(state.cleanBorders) do pcall(line.SetColorTexture, line, color[1], color[2], color[3], color[4]) end
    else
        RestoreExternalAlphaOwner(owner)
        SetCleanBorderShown(state, false)
    end
    if runtime.menuCaptureHooked then runtime.RefreshGameMenuButtons(frame, provider) end
end

local function TryAttachHooks()
    local provider = _G.EllesmereUI
    if type(hooksecurefunc) ~= "function" then return end
    if type(provider) == "table" then
        if not runtime.characterApplyHooked and type(provider.ApplyThemedCharacterSheet) == "function" then
            runtime.characterApplyHooked = pcall(hooksecurefunc, provider, "ApplyThemedCharacterSheet", ScheduleRefresh)
        end
        if not runtime.stylesRefreshHooked and type(provider._WSkinRefreshStyles) == "function" then
            runtime.stylesRefreshHooked = pcall(hooksecurefunc, provider, "_WSkinRefreshStyles", ScheduleRefresh)
        end
    end
    if not runtime.merchantUpdateHooked and type(_G.MerchantFrame_Update) == "function" then
        runtime.merchantUpdateHooked = pcall(hooksecurefunc, "MerchantFrame_Update", ScheduleRefresh)
    end
    if not runtime.friendsApplyHooked and type(_G._EFR_ApplyFriends) == "function" then
        runtime.friendsApplyHooked = pcall(hooksecurefunc, "_EFR_ApplyFriends", ScheduleRefresh)
    end
end

local function ApplyAll()
    if not runtime.enabled then return end
    if IsInCombat() then return end
    if type(_G.EllesmereUI) ~= "table" then
        RestoreAll()
        return
    end
    TryAttachHooks()
    local ok = pcall(ApplyCharacter)
    if not ok then RestoreOwner("character") end
    ok = pcall(ApplyFriends)
    if not ok then RestoreOwner("friends") end
    ok = pcall(runtime.ApplyProtectedLFGAdapter)
    if not ok then RestoreOwner("blizzard:lfg") end
    ok = pcall(runtime.ApplyGameMenu)
    if not ok then RestoreOwner("blizzard:gamemenu") end
    for index = 1, #WINDOW_ADAPTERS do
        local adapter = WINDOW_ADAPTERS[index]
        ok = pcall(ApplyWindowAdapter, adapter)
        if not ok then
            RestoreOwner(adapter.owner)
            if type(adapter.postRestore) == "function" then pcall(adapter.postRestore) end
        end
    end
    runtime.UpdateAuctionShadow()
end

ScheduleRefresh = function()
    if runtime.refreshScheduled or not runtime.enabled then return end
    runtime.refreshScheduled = true
    local function Run()
        runtime.refreshScheduled = false
        ApplyAll()
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, Run)
    else
        Run()
    end
end

local RELEVANT_ADDONS = {
    EllesmereUI = true,
    EllesmereUIBlizzardSkin = true,
    EllesmereUIFriends = true,
    Blizzard_CharacterUI = true,
    Blizzard_GameMenu = true,
    Blizzard_FriendsFrame = true,
    Blizzard_SocialUI = true,
    Blizzard_Collections = true,
    Blizzard_PlayerSpells = true,
    Blizzard_EncounterJournal = true,
    Blizzard_GroupFinder = true,
    Blizzard_GroupFinder_VanillaStyle = runtime.isForever,
    Blizzard_WorldMap = true,
    Blizzard_MailFrame = true,
    Blizzard_AuctionHouseUI = true,
    Blizzard_AchievementUI = true,
    Blizzard_InspectUI = true,
    Blizzard_Communities = true,
    Blizzard_Calendar = true,
    Blizzard_MacroUI = true,
    Blizzard_ProfessionsBook = true,
    Blizzard_ArchaeologyUI = true,
    Blizzard_HousingDashboard = true,
    Blizzard_Professions = true,
    Blizzard_Transmog = true,
    Blizzard_ProfessionsCustomerOrders = true,
    Blizzard_TrainerUI = true,
    Blizzard_ItemInteractionUI = true,
    Blizzard_ItemSocketingUI = true,
    Blizzard_ItemUpgradeUI = true,
    Blizzard_DelvesCompanionConfiguration = true,
    Blizzard_QueueStatusFrame = true,
    Blizzard_PlayerChoice = true,
    Auctionator = true,
}

runtime.CanSmartResetDamageMeter = function()
    return runtime.enabled
        and runtime.config
        and IsAddOnLoadedSafe("EllesmereUIDamageMeters")
        and type(_G.C_DamageMeter) == "table"
        and type(_G.C_DamageMeter.ResetAllCombatSessions) == "function"
end

runtime.ResetDamageMeter = function(messageKey, fallback)
    if not runtime.CanSmartResetDamageMeter() then return false end
    local ok = pcall(_G.C_DamageMeter.ResetAllCombatSessions)
    if not ok then return false end
    if type(YUI.Print) == "function" then
        YUI:Print(T(messageKey, fallback))
    end
    return true
end

runtime.HideDamageMeterPrompt = function()
    local Settings = YUI.Settings
    if Settings and type(Settings.HideConfirmPopup) == "function" then
        Settings:HideConfirmPopup(eventOwner)
    end
end

eventOwner.OnDamageMeterWorldReady = function(_, isInitialLogin, isReloadingUi)
    runtime.HideDamageMeterPrompt()
    if not runtime.CanSmartResetDamageMeter() then return end
    if type(_G.IsInInstance) ~= "function" then return end

    local ok, inInstance, instanceType = pcall(_G.IsInInstance)
    if not ok or IsSecretValue(inInstance) or IsSecretValue(instanceType) then return end
    if inInstance ~= true then return end
    local promptKey
    if instanceType == "raid" then
        promptKey = "damageMeterRaidPrompt"
    elseif runtime.isForever and instanceType == "party" then
        promptKey = "damageMeterDungeonPrompt"
    end
    if runtime.lastDamageMeterInstanceType ~= instanceType then
        runtime.lastDamageMeterMapID, runtime.lastDamageMeterDifficulty = nil, nil
        runtime.lastDamageMeterInstanceType = instanceType
    end
    if not promptKey then return end
    if type(_G.GetInstanceInfo) ~= "function" then return end
    local infoOK, _, _, difficultyID, _, _, _, _, mapID = pcall(_G.GetInstanceInfo)
    if not infoOK or IsSecretValue(mapID) or IsSecretValue(difficultyID)
        or type(mapID) ~= "number" or type(difficultyID) ~= "number" then return end
    if runtime.lastDamageMeterMapID == mapID and runtime.lastDamageMeterDifficulty == difficultyID then return end
    if isInitialLogin or isReloadingUi then
        runtime.lastDamageMeterMapID, runtime.lastDamageMeterDifficulty = mapID, difficultyID
        return
    end
    if runtime.config[promptKey] == false then return end

    local Settings = YUI.Settings
    if not (Settings and type(Settings.ShowConfirmPopup) == "function") then return end
    runtime.lastDamageMeterMapID, runtime.lastDamageMeterDifficulty = mapID, difficultyID
    Settings:ShowConfirmPopup(
        T("confirm.damage_meter_reset.message", "Reset all damage meter data?"),
        function()
            if runtime.config[promptKey] == false then return end
            runtime.ResetDamageMeter("message.damage_meter_reset.success", "Damage meter data reset.")
        end,
        {
            owner = eventOwner,
            titleText = T("confirm.damage_meter_reset.title", "Reset Damage Meter"),
            acceptText = T("confirm.damage_meter_reset.accept", "Reset"),
            acceptTone = "danger",
            offsetY = 120,
            scrimAlpha = 0,
            noteText = T("confirm.damage_meter_reset.note", "You can disable this in YUI Toolbox - EllesmereUI Enhancement."),
        }
    )
end

eventOwner.OnChallengeModeStart = function()
    if runtime.isForever then return end
    runtime.HideDamageMeterPrompt()
    if not runtime.config or runtime.config.damageMeterMythicReset == false then return end
    runtime.ResetDamageMeter("message.damage_meter_reset.mythic_success", "Mythic Keystone started; damage meter data reset.")
end

local function AttachEvents()
    if runtime.eventsAttached or not (Event and type(Event.On) == "function") then return end
    runtime.eventsAttached = true
    Event:On("ADDON_LOADED", function(_, addonName)
        if RELEVANT_ADDONS[addonName] then
            TryAttachHooks()
            ScheduleRefresh()
        end
    end, eventOwner, { moduleId = MODULE_ID, traceName = "EllesmereUIEnhancement:ADDON_LOADED" })
    Event:On("PLAYER_REGEN_ENABLED", function()
        if runtime.restorePending then
            runtime.restorePending = false
            RestoreAll()
            if not runtime.enabled then DetachEvents() end
        elseif runtime.enabled then
            ScheduleRefresh()
        end
    end, eventOwner, {
        moduleId = MODULE_ID,
        traceName = "EllesmereUIEnhancement:PLAYER_REGEN_ENABLED",
    })
    Event:On("YUI_WORLD_READY", eventOwner.OnDamageMeterWorldReady, eventOwner, {
        moduleId = MODULE_ID,
        traceName = "EllesmereUIEnhancement:damage-meter-world-ready",
    })
    if not runtime.isForever then
        Event:On("CHALLENGE_MODE_START", eventOwner.OnChallengeModeStart, eventOwner, {
            moduleId = MODULE_ID,
            traceName = "EllesmereUIEnhancement:damage-meter-challenge-start",
        })
    end
end

DetachEvents = function()
    if not runtime.eventsAttached then return end
    runtime.eventsAttached = false
    if Event and type(Event.OffOwner) == "function" then Event:OffOwner(eventOwner) end
end

local Enhancement = {}
YUI._EllesmereUIEnhancement = Enhancement

-- ESC 按钮使用固定配色；自有快捷按钮独立沿用 GUI2。
function Enhancement:GetGameMenuButtonFinish()
    if not runtime.CanStyleGameMenu() then return nil end
    return runtime.GetGameMenuButtonFinish()
end

function Enhancement:IsAvailable()
    if type(_G.EllesmereUI) == "table" then return true end
    return System and type(System.DoesAddOnExist) == "function"
        and System.DoesAddOnExist("EllesmereUI") == true
end

function Enhancement:GetFriendsSkinStats()
    local stats = {
        enabled = runtime.enabled, pendingRefresh = runtime.refreshScheduled, restorePending = runtime.restorePending,
        ownedFonts = 0, ownedTabs = 0, suppressedRegions = 0, cleanBorder = false,
    }
    for _, state in pairs(fontStates) do
        if state.owner == "friends" then stats.ownedFonts = stats.ownedFonts + 1 end
    end
    for _, state in pairs(tabStates) do
        if state.owner == "friends" and state.background and IsObjectShown(state.background) then
            stats.ownedTabs = stats.ownedTabs + 1
        end
    end
    for _, state in pairs(frameStates) do
        if state.owner == "friends" then
            stats.suppressedRegions = stats.suppressedRegions + #(state.externalBackgrounds or {})
            stats.cleanBorder = stats.cleanBorder or state.windowBorderAtlas ~= nil
        end
    end
    return stats
end

function Enhancement:SetEnabled(value, config)
    runtime.config = NormalizeConfig(type(config) == "table" and config or runtime.config or GetDB())
    local enabled = value == true
    if runtime.hotkeys then runtime.hotkeys:SetEnabled(enabled, runtime.config) end
    if runtime.questTrackerScroll then runtime.questTrackerScroll:SetEnabled(enabled, runtime.config) end
    if runtime.questAutomation then runtime.questAutomation:SetEnabled(enabled) end
    if runtime.enabled == enabled then
        if enabled then
            RegisterAppearanceOverride()
            RefreshSharedAppearance()
            ScheduleRefresh()
        end
        return
    end

    runtime.enabled = enabled
    if enabled then
        runtime.restorePending = false
        RegisterAppearanceOverride()
        if Appearance and type(Appearance.RegisterConsumer) == "function" then
            Appearance:RegisterConsumer(appearanceOverrideOwner, function() if runtime.enabled then ScheduleRefresh() end end)
        end
        AttachEvents()
        TryAttachHooks()
        ScheduleRefresh()
    else
        runtime.HideDamageMeterPrompt()
        runtime.DetachForeverStats()
        runtime.refreshScheduled = false
        if Appearance and type(Appearance.UnregisterConsumer) == "function" then
            Appearance:UnregisterConsumer(appearanceOverrideOwner)
        end
        if IsInCombat() then
            runtime.restorePending = true
        else
            RestoreAll()
            DetachEvents()
        end
        UnregisterAppearanceOverride()
    end
end

function Enhancement:Refresh(config)
    runtime.config = NormalizeConfig(type(config) == "table" and config or GetDB())
    if runtime.hotkeys then runtime.hotkeys:SetEnabled(runtime.enabled, runtime.config) end
    if runtime.questTrackerScroll then runtime.questTrackerScroll:SetEnabled(runtime.enabled, runtime.config) end
    if runtime.questAutomation then runtime.questAutomation:SetEnabled(runtime.enabled) end
    if not runtime.enabled then return end
    RefreshSharedAppearance()
    ScheduleRefresh()
end

local featureEnabled = false

local function ToggleFeature(enabled)
    featureEnabled = enabled == true
    Enhancement:SetEnabled(featureEnabled, GetDB())
end

local function RefreshSettings(feature, rebuild)
    Enhancement:Refresh(GetDB())
    if rebuild and feature and type(feature.RefreshCurrentModule) == "function" then
        feature:RefreshCurrentModule()
    end
end

local Feature = {
    name = T("feature.name", "EllesmereUI 增强"),
    description = T("feature.description", "增强 EllesmereUI 窗口与动作条快捷键显示，同步 YUI 工具窗口外观，并提供伤害统计智能重置。"),
    default = true,
    product = PRODUCT_ID,
    storageKey = FEATURE_KEY,
    settingsMode = "inline",
    versions = { "mainline", "forever" },
    callback = ToggleFeature,
}

function Feature:IsVisible()
    return IsAddOnLoadedSafe("EllesmereUI")
end

function Feature:GetOptions()
    local db = GetDB()
    local options = {
        {
            type = "divider",
            label = T("settings.section.blizzard_plus", "暴雪界面美化+"),
            alignLeft = true,
            width = 456,
        },
        {
            type = "row",
            gap = SETTINGS_FIELD_GAP,
            children = {
                {
                    type = "checkbox",
                    label = T("settings.beautify_skin_background", "皮肤背景美化"),
                    tooltip = T("settings.beautify_skin_background.tooltip", "使用本组件的背景风格替换 EllesmereUI 窗口背景。"),
                    width = SETTINGS_FIELD_WIDTH,
                    get = function() return db.beautifySkinBackground ~= false end,
                    set = function(value)
                        db.beautifySkinBackground = value == true
                        RefreshSettings(self, true)
                    end,
                },
                {
                    type = "checkbox",
                    label = T("settings.simplify_window_border", "移除窗口边框内侧暗影"),
                    tooltip = T("settings.simplify_window_border.tooltip", "隐藏 EllesmereUI 带内侧暗影的边框材质，并替换为简洁的 1px 边框；无法安全识别时不执行。"),
                    width = SETTINGS_FIELD_WIDTH,
                    get = function() return db.simplifyWindowBorder == true end,
                    set = function(value)
                        db.simplifyWindowBorder = value == true
                        RefreshSettings(self)
                    end,
                },
            },
        },
        {
            type = "row",
            gap = SETTINGS_FIELD_GAP,
            children = {
                {
                    type = "checkbox",
                    label = T("settings.window_shadow", "窗口阴影"),
                    tooltip = T("settings.window_shadow.tooltip", "显示 4px、强度 0.3 的窗口外阴影；关闭仅移除外阴影。拍卖行与展开的附属面板共用外圈阴影。"),
                    width = SETTINGS_FIELD_WIDTH,
                    disabled = db.beautifySkinBackground == false,
                    get = function() return db.windowShadow ~= false end,
                    set = function(value)
                        db.windowShadow = value == true
                        RefreshSettings(self)
                    end,
                },
                {
                    type = "slider",
                    label = T("settings.background_transparency", "面板透明度"),
                    tooltip = T("settings.background_transparency.tooltip", "0 为不透明，100 为完全透明；仅调整主体背景。"),
                    inline = true,
                    width = SETTINGS_FIELD_WIDTH,
                    labelWidth = SETTINGS_LABEL_WIDTH,
                    gap = SETTINGS_CONTROL_GAP,
                    inputWidth = SETTINGS_VALUE_WIDTH,
                    min = 0,
                    max = 100,
                    step = 5,
                    disabled = db.beautifySkinBackground == false,
                    get = function() return math.floor(db.backgroundTransparency * 100 + 0.5) end,
                    set = function(value)
                        db.backgroundTransparency = ClampNumber(value, 0, 100, 0) / 100
                        RefreshSettings(self)
                    end,
                },
            },
        },
        {
            type = "row",
            gap = SETTINGS_FIELD_GAP,
            hidden = function() return db.beautifySkinBackground == false end,
            children = {
                {
                    type = "dropdown",
                    label = T("settings.background_preset", "背景风格"),
                    inlineLabel = true,
                    width = SETTINGS_FIELD_WIDTH,
                    labelWidth = SETTINGS_LABEL_WIDTH,
                    gap = SETTINGS_CONTROL_GAP,
                    controlWidth = SETTINGS_CONTROL_WIDTH,
                    options = {
                        { text = T("settings.background_preset.modern", "石墨"), value = PRESET_MODERN },
                        { text = T("settings.background_preset.pilot", "炭灰"), value = PRESET_CHARCOAL },
                        { text = T("settings.background_preset.yui", "蓝灰"), value = PRESET_YUI },
                        { text = T("settings.background_preset.deep_glass", "深海"), value = PRESET_DEEP },
                        { text = T("settings.background_preset.crimson_glass", "暗红"), value = PRESET_CRIMSON },
                        { text = T("settings.background_preset.solid", "自定义"), value = PRESET_SOLID },
                    },
                    default = DEFAULTS.backgroundPreset,
                    get = function() return db.backgroundPreset end,
                    set = function(value)
                        if value == runtime.pilotPreset and db.backgroundPreset ~= runtime.pilotPreset then
                            db.pilotBasePreset = db.backgroundPreset
                        end
                        db.backgroundPreset = value
                        NormalizeConfig(db)
                        RefreshSettings(self, true)
                    end,
                },
                {
                    type = "slider",
                    label = T("settings.background_darken", "背景暗化"),
                    tooltip = T("settings.background_darken.tooltip", "数值越低，背景越明亮。"),
                    inline = true,
                    width = SETTINGS_FIELD_WIDTH,
                    labelWidth = SETTINGS_LABEL_WIDTH,
                    gap = SETTINGS_CONTROL_GAP,
                    inputWidth = SETTINGS_VALUE_WIDTH,
                    min = 0,
                    max = 60,
                    step = 5,
                    get = function() return math.floor(db.backgroundDarken * 100 + 0.5) end,
                    set = function(value)
                        db.backgroundDarken = ClampNumber(value, 0, 60, 0) / 100
                        RefreshSettings(self)
                    end,
                },
            },
        },
        {
            type = "row",
            gap = SETTINGS_FIELD_GAP,
            hidden = function()
                return db.beautifySkinBackground == false or db.backgroundPreset ~= PRESET_SOLID
            end,
            children = {
                {
                    type = "color",
                    label = T("settings.background_color", "背景颜色"),
                    inlineLabel = true,
                    field = true,
                    width = SETTINGS_FIELD_WIDTH,
                    labelWidth = SETTINGS_LABEL_WIDTH,
                    gap = SETTINGS_CONTROL_GAP,
                    controlWidth = SETTINGS_CONTROL_WIDTH,
                    hasAlpha = false,
                    default = DEFAULT_SOLID_COLOR,
                    get = function() return db.solidColor end,
                    set = function(value)
                        db.solidColor = CopyColor(value, DEFAULT_SOLID_COLOR)
                        RefreshSettings(self)
                    end,
                },
            },
        },
        {
            type = "row",
            gap = SETTINGS_FIELD_GAP,
            children = {
                {
                    type = "slider",
                    label = T("settings.tab_font_size", "Tab 字号"),
                    inline = true,
                    width = SETTINGS_FIELD_WIDTH,
                    labelWidth = SETTINGS_LABEL_WIDTH,
                    gap = SETTINGS_CONTROL_GAP,
                    inputWidth = SETTINGS_VALUE_WIDTH,
                    min = 9,
                    max = 24,
                    step = 1,
                    fontStyleSource="tabFontSize", get = function() return db.tabFontSize end,
                    set = function(value)
                        db.tabFontSize = math.floor(ClampNumber(value, 9, 24, 13) + 0.5)
                        RefreshSettings(self)
                    end,
                },
                {
                    type = "dropdown",
                    label = T("settings.tab_color_mode", "Tab 颜色"),
                    inlineLabel = true,
                    width = SETTINGS_FIELD_WIDTH,
                    labelWidth = SETTINGS_LABEL_WIDTH,
                    gap = SETTINGS_CONTROL_GAP,
                    controlWidth = SETTINGS_CONTROL_WIDTH,
                    options = {
                        { text = T("settings.tab_color_mode.auto", "自动匹配背景"), value = TAB_COLOR_AUTO },
                        { text = T("settings.tab_color_mode.custom", "自定义"), value = TAB_COLOR_CUSTOM },
                    },
                    default = TAB_COLOR_AUTO,
                    get = function() return db.tabColorMode end,
                    set = function(value)
                        db.tabColorMode = value == TAB_COLOR_CUSTOM and TAB_COLOR_CUSTOM or TAB_COLOR_AUTO
                        RefreshSettings(self, true)
                    end,
                },
            },
        },
        {
            type = "row",
            gap = SETTINGS_FIELD_GAP,
            hidden = function() return db.tabColorMode ~= TAB_COLOR_CUSTOM end,
            children = {
                {
                    type = "color",
                    label = T("settings.tab_color", "Tab 背景色"),
                    inlineLabel = true,
                    field = true,
                    width = SETTINGS_FIELD_WIDTH,
                    labelWidth = SETTINGS_LABEL_WIDTH,
                    gap = SETTINGS_CONTROL_GAP,
                    controlWidth = SETTINGS_CONTROL_WIDTH,
                    hasAlpha = true,
                    default = DEFAULT_TAB_COLOR,
                    get = function() return db.tabColor end,
                    set = function(value)
                        db.tabColor = CopyColor(value, DEFAULT_TAB_COLOR)
                        RefreshSettings(self)
                    end,
                },
            },
        },
        {
            type = "row",
            gap = SETTINGS_FIELD_GAP,
            children = {
                {
                    type = "slider",
                    label = T("settings.character_detail_font_size", "角色面板字号"),
                    tooltip = T("settings.character_detail_font_size.tooltip", "调整角色面板顶部页签和右侧属性文字；分类标题会自动大一号。"),
                    inline = false,
                    width = SETTINGS_FIELD_WIDTH,
                    inputWidth = SETTINGS_VALUE_WIDTH,
                    min = CHARACTER_DETAIL_FONT_MIN_SIZE,
                    max = CHARACTER_DETAIL_FONT_MAX_SIZE,
                    step = 1,
                    fontStyleSource="characterDetailFontSize", get = function() return db.characterDetailFontSize end,
                    set = function(value)
                        db.characterDetailFontSize = math.floor(ClampNumber(value,
                            CHARACTER_DETAIL_FONT_MIN_SIZE, CHARACTER_DETAIL_FONT_MAX_SIZE,
                            DEFAULT_CHARACTER_DETAIL_FONT_SIZE) + 0.5)
                        RefreshSettings(self)
                    end,
                },
                {
                    type = "slider",
                    label = T("settings.merchant_item_name_font_size", "商人商品名字号"),
                    tooltip = T("settings.merchant_item_name_font_size.tooltip", "调整商人列表、网格和购回页的商品名称字号。"),
                    inline = false,
                    width = SETTINGS_FIELD_WIDTH,
                    inputWidth = SETTINGS_VALUE_WIDTH,
                    min = MERCHANT_ITEM_NAME_FONT_MIN_SIZE,
                    max = MERCHANT_ITEM_NAME_FONT_MAX_SIZE,
                    step = 1,
                    fontStyleSource="merchantItemNameFontSize", get = function() return db.merchantItemNameFontSize end,
                    set = function(value)
                        db.merchantItemNameFontSize = math.floor(ClampNumber(value,
                            MERCHANT_ITEM_NAME_FONT_MIN_SIZE, MERCHANT_ITEM_NAME_FONT_MAX_SIZE,
                            DEFAULT_MERCHANT_ITEM_NAME_FONT_SIZE) + 0.5)
                        RefreshSettings(self)
                    end,
                },
            },
        },
        {
            type = "divider",
            label = T("settings.section.action_bars", "动作条"),
            alignLeft = true,
            width = 456,
        },
        {
            type = "checkbox",
            label = T("settings.hotkeys.enabled", "快捷键缩写"),
            tooltip = T("settings.hotkeys.enabled.tooltip", "缩写动作条上的主键名称，保留修饰键；仅改变显示文字。"),
            width = 456,
            get = function() return db.abbreviateHotkeys == true end,
            set = function(value)
                db.abbreviateHotkeys = value == true
                RefreshSettings(self, true)
            end,
        },
        {
            type = "text",
            label = T("settings.hotkeys.defaults", "默认：HOME=HO；END=EN；INSERT=IN；DELETE=DE；PAGE UP=PU；PAGE DOWN=PD；MwU=MU；MwD=MD。"),
            width = 456,
            colorKey = "color.text.secondary",
            hidden = function() return db.abbreviateHotkeys ~= true end,
        },
        {
            type = "editbox",
            label = T("settings.hotkeys.aliases", "自定义缩写"),
            tooltip = T("settings.hotkeys.aliases.tooltip", "用分号分隔规则，例如 HOME=HM; END=E。主键名称不含修饰键，缩写为 1–2 个英文字母或数字。与默认表合并，同名键覆盖，其余默认项保留；留空使用默认表，点击应用保存。"),
            width = 456,
            hidden = function() return db.abbreviateHotkeys ~= true end,
            get = function() return runtime.hotkeyDraft or db.hotkeyAliases end,
            set = function(value) runtime.hotkeyDraft = value end,
        },
        {
            type = "button",
            label = T("settings.hotkeys.apply", "应用缩写表"),
            width = 120,
            hidden = function() return db.abbreviateHotkeys ~= true end,
            onClick = function()
                local value = runtime.hotkeyDraft or db.hotkeyAliases
                local parsed, errorIndex
                if runtime.hotkeys then parsed, errorIndex = runtime.hotkeys:ParseAliases(value) end
                if not parsed then
                    if type(YUI.Print) == "function" then
                        YUI:Print(string.format(T("message.hotkeys.invalid", "快捷键缩写第 %d 条规则无效；请使用 主键=缩写，缩写为 1–2 个英文字母或数字。"), errorIndex or 0))
                    end
                    return
                end
                db.hotkeyAliases, runtime.hotkeyDraft = value, nil
                RefreshSettings(self, true)
            end,
        },
        {
            type = "text",
            label = T("settings.hotkeys.unavailable", "当前无法接入 EllesmereUI Action Bars，继续使用原快捷键显示。请确认该插件已启用；更新插件后可重载界面再试。"),
            width = 456,
            colorKey = "color.text.secondary",
            hidden = function()
                if db.abbreviateHotkeys ~= true or not runtime.hotkeys then return true end
                local status = runtime.hotkeys:GetStats().status
                return status ~= "missing" and status ~= "unsupported" and status ~= "invalid"
            end,
        },
        {
            type = "divider",
            label = T("settings.section.damage_meter", "伤害统计"),
            alignLeft = true,
            width = 456,
        },
        {
            type = "row",
            gap = SETTINGS_FIELD_GAP,
            children = {
                {
                    type = "checkbox",
                    label = T("settings.damage_meter.mythic_reset", "大秘境开始自动重置"),
                    hidden = function() return runtime.isForever end,
                    tooltip = T("settings.damage_meter.mythic_reset.tooltip", "大秘境开始时自动清空全部伤害统计，不弹框。"),
                    width = SETTINGS_FIELD_WIDTH,
                    get = function() return db.damageMeterMythicReset ~= false end,
                    set = function(value)
                        db.damageMeterMythicReset = value == true
                        RefreshSettings(self)
                    end,
                },
                {
                    type = "checkbox",
                    label = T("settings.damage_meter.raid_prompt", "进入团本时询问重置"),
                    width = SETTINGS_FIELD_WIDTH,
                    get = function() return db.damageMeterRaidPrompt ~= false end,
                    set = function(value)
                        db.damageMeterRaidPrompt = value == true
                        RefreshSettings(self)
                    end,
                },
                {
                    type = "checkbox",
                    label = T("settings.damage_meter.dungeon_prompt", "进入副本时询问重置（非团本）"),
                    hidden = function() return not runtime.isForever end,
                    width = SETTINGS_FIELD_WIDTH,
                    get = function() return db.damageMeterDungeonPrompt == true end,
                    set = function(value)
                        db.damageMeterDungeonPrompt = value == true
                        RefreshSettings(self)
                    end,
                },
            },
        },
    }
    if runtime.isForever then
        options[#options + 1] = {
            type = "divider",
            label = T("settings.section.quest_tracker", "任务追踪器"),
            alignLeft = true,
            width = 456,
        }
        options[#options + 1] = {
            type = "checkbox",
            label = T("settings.quest_tracker.scroll", "任务追踪器滚轮滚动"),
            tooltip = T("settings.quest_tracker.scroll.tooltip", "任务超出显示范围时用滚轮浏览，保留原生任务按钮和外观。启用时自动打开任务图标，关闭后保留。位置与高度在暴雪编辑模式中调整；战斗中暂停滚动，关闭后脱战恢复。"),
            width = 456,
            get = function() return db.questTrackerScroll == true end,
            set = function(value)
                db.questTrackerScroll = value == true
                RefreshSettings(self)
            end,
        }
    end
    if GUI2 and GUI2.FontStyle and GUI2.FontStyle.MergeOptions then
        GUI2.FontStyle:MergeOptions(options, {{key="native_text:tabs",label=T("settings.tab_font_size", "Tab 字号"),sources={"tabFontSize"}},{key="native_text:character",label=T("settings.character_detail_font_size", "角色面板字号"),sources={"characterDetailFontSize"}},{key="native_text:merchant",label=T("settings.merchant_item_name_font_size", "商人商品名字号"),sources={"merchantItemNameFontSize"}}})
    end
    return options
end

function profileOwner:OnProfileChanged()
    runtime.hotkeyDraft = nil
    featureEnabled = Components.IsEnabled and Components:IsEnabled(FEATURE_KEY) or false
    Enhancement:SetEnabled(featureEnabled, GetDB())
end

local function RegisterProfileCallbacks()
    if runtime.profileCallbacksRegistered then return end
    if not (YUI.DB and type(YUI.DB.GetAceDB) == "function") then return end
    local db = YUI.DB:GetAceDB(PRODUCT_ID)
    if not (db and type(db.RegisterCallback) == "function") then return end
    db.RegisterCallback(profileOwner, "OnProfileChanged", "OnProfileChanged")
    db.RegisterCallback(profileOwner, "OnProfileCopied", "OnProfileChanged")
    db.RegisterCallback(profileOwner, "OnProfileReset", "OnProfileChanged")
    runtime.profileCallbacksRegistered = true
end

GetDB()
Components:RegisterFeature(FEATURE_KEY, Feature)

if Event and type(Event.Once) == "function" then
    Event:Once("YUI_DB_READY", RegisterProfileCallbacks, profileOwner, {
        moduleId = MODULE_ID,
        traceName = "EllesmereUIEnhancement:profile-callbacks",
    })
end

if GUI2 and GUI2.FontStyle and GUI2.FontStyle.RegisterConfig then
    GUI2.FontStyle:RegisterConfig("native_text", {
        label=function() return Feature.name end,
        get=function() return GUI2.FontStyle.ComponentConfig(PRODUCT_ID,CONFIG_KEY) end,
        refresh=function(db) if runtime.enabled then Enhancement:Refresh(db) end end,
        targets={{id="tabs",label=function() return T("settings.tab_font_size", "Tab 字号") end,fields={size="tabFontSize"},defaults=DEFAULTS,minSize=9,maxSize=24},{id="character",label=function() return T("settings.character_detail_font_size", "角色面板字号") end,fields={size="characterDetailFontSize"},defaults=DEFAULTS,minSize=CHARACTER_DETAIL_FONT_MIN_SIZE,maxSize=CHARACTER_DETAIL_FONT_MAX_SIZE},{id="merchant",label=function() return T("settings.merchant_item_name_font_size", "商人商品名字号") end,fields={size="merchantItemNameFontSize"},defaults=DEFAULTS,minSize=MERCHANT_ITEM_NAME_FONT_MIN_SIZE,maxSize=MERCHANT_ITEM_NAME_FONT_MAX_SIZE}},
    })
end

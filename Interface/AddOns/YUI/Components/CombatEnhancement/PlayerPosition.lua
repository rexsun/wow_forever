local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and (YUI.IsRetail or YUI.IsWrath or YUI.IsForever)) then return end

local CombatEnhancement = YUI.CombatEnhancement
if not (CombatEnhancement and CombatEnhancement.RegisterSubFeature) then return end

local CombatAPI = YUI.API and YUI.API.Combat
local SpellAPI = YUI.API and YUI.API.Spell
local UnitAPI = YUI.API and YUI.API.Unit
local GUI2 = YUI.GUI2
local Icons = YUI.API and YUI.API.Icons
local Assets = YUI.Assets

local PlayerPosition = {
    id = "playerPosition",
    order = 10,
}

local DEFAULT_TEXTURE = "waypoint_map_pin_tracked"
local FALLBACK_TEXTURE = "snowflake"
local DEFAULT_TEXTURE_VERSION = 2
local DEFAULT_SIZE = 36
local DEFAULT_COLOR = { 1, 1, 1, 1 }
local DEFAULT_ROTATION_SPEED = 1
local DEFAULT_OFFSET_X = 0
local DEFAULT_OFFSET_Y = -20
local DEFAULT_VISIBILITY_MODE = "combat"
local DEFAULT_RANGE_COLOR_ENABLED = false
local DEFAULT_IN_RANGE_COLOR = { 1, 1, 1, 1 }
local DEFAULT_OUT_OF_RANGE_COLOR = { 1, 0, 0, 1 }
local DEFAULT_SPEC_FILTER_ENABLED = false
local MIN_SIZE = 16
local MAX_SIZE = 240
local MIN_OFFSET = -200
local MAX_OFFSET = 200
local MIN_ROTATION_SPEED = 0
local MAX_ROTATION_SPEED = 3
local MIN_RANGE_SPELL_ID = 1
local MAX_RANGE_SPELL_ID = 9999999
local RANGE_CHECK_INTERVAL = 0.1
local RANGE_SPELL_CACHE_OWNER = "combat-enhancement-player-position"
local SECTION_WIDTH = 620
local COLUMN_GAP = 24
local COLUMN_WIDTH = math.floor((SECTION_WIDTH - COLUMN_GAP) / 2)
local LABEL_WIDTH = 112
local LABEL_GAP = 10
local BODY_WIDTH = COLUMN_WIDTH - LABEL_WIDTH - LABEL_GAP
local INPUT_WIDTH = 52
local VALUE_GAP = 10
local RUNTIME_FRAME_STRATA = "LOW"
local RUNTIME_FRAME_LEVEL = 1
local BASE_ROTATION_SPEED = 1.2
local DEFAULT_ROTATION = 0
local TWO_PI = math.pi * 2
local ASSET_TEXTURE_ROOT = "player-position\\"
local SETTINGS_PREVIEW_WIDTH = 220
local SETTINGS_PREVIEW_HEIGHT = 220
local SETTINGS_PREVIEW_MAX_TEXTURE_SIZE = 168
local ICON_SCOPE_ID = "settings"
local SPEC_DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local RANGE_SPELL_PANEL_WIDTH = 540
local RANGE_SPELL_PANEL_HEIGHT = 330
local RANGE_SPELL_PANEL_INSET = 12
local RANGE_SPELL_PANEL_GAP = 3
local RANGE_SPELL_TOP_ACTION_HEIGHT = 24
local RANGE_SPELL_CELL_HEIGHT = 28
local RANGE_SPELL_GRID_COLUMNS = 3
local RANGE_SPELL_ICON_SIZE = 24
local RANGE_SPELL_EDIT_WIDTH = 132
local RANGE_SPELL_EDIT_HEIGHT = 22
local RANGE_SPELL_CELL_INSET_X = 0
local RANGE_SPELL_ICON_EDIT_GAP = 5
local RANGE_SPELL_DISPLAY_ICON_SIZE = 18
local RANGE_SPELL_EDIT_TEXT_INSET = 8

local VISIBILITY_OPTIONS = {
    { textKey = "settings.player_position_visibility_always", fallback = "始终显示", value = "always" },
    { textKey = "settings.player_position_visibility_combat", fallback = "战斗中", value = "combat" },
    { textKey = "settings.player_position_visibility_instance_combat", fallback = "副本战斗中", value = "instance_combat" },
    { textKey = "settings.player_position_visibility_instance", fallback = "副本中", value = "instance" },
}

local VALID_VISIBILITY_MODES = {
    always = true,
    combat = true,
    instance_combat = true,
    instance = true,
}

local SPEC_RANGE_BY_ID = {
    [62] = 40, [63] = 40, [64] = 40,
    [65] = 40, [66] = 5, [70] = 5,
    [71] = 5, [72] = 5, [73] = 5,
    [102] = 40, [103] = 5, [104] = 5, [105] = 40,
    [250] = 5, [251] = 5, [252] = 5,
    [253] = 40, [254] = 40, [255] = 5,
    [256] = 40, [257] = 40, [258] = 40,
    [259] = 5, [260] = 5, [261] = 5,
    [262] = 40, [263] = 5, [264] = 40,
    [265] = 40, [266] = 40, [267] = 40,
    [268] = 5, [269] = 5, [270] = 40,
    [577] = 5, [581] = 5,
    [1467] = 25, [1468] = 25, [1473] = 25,
    [1480] = 40,
}

PlayerPosition.defaults = {
    playerPositionEnabled = true,
    playerPositionTexture = DEFAULT_TEXTURE,
    playerPositionTextureDefaultVersion = DEFAULT_TEXTURE_VERSION,
    playerPositionSize = DEFAULT_SIZE,
    playerPositionColor = DEFAULT_COLOR,
    playerPositionRotationSpeed = DEFAULT_ROTATION_SPEED,
    playerPositionOffsetX = DEFAULT_OFFSET_X,
    playerPositionOffsetY = DEFAULT_OFFSET_Y,
    playerPositionVisibilityMode = DEFAULT_VISIBILITY_MODE,
    playerPositionRangeColorEnabled = DEFAULT_RANGE_COLOR_ENABLED,
    playerPositionRangeSpellIDs = {},
    playerPositionRangeSpellIDsMigrated = false,
    playerPositionInRangeColor = DEFAULT_IN_RANGE_COLOR,
    playerPositionOutOfRangeColor = DEFAULT_OUT_OF_RANGE_COLOR,
    playerPositionSpecFilterEnabled = DEFAULT_SPEC_FILTER_ENABLED,
    playerPositionSpecFilter = {},
}

local TEXTURE_OPTIONS = {
    {
        key = "waypoint_map_pin_tracked",
        labelKey = "texture.waypoint_map_pin_tracked",
        fallback = "追踪标记",
        sourceType = "atlas",
        atlas = "Waypoint-MapPin-Minimap-Tracked",
        blendMode = "BLEND",
    },
    {
        key = "builtin_cross",
        labelKey = "texture.builtin_cross",
        fallback = "十字",
        sourceType = "asset",
        assetPath = ASSET_TEXTURE_ROOT .. "cross.tga",
        blendMode = "BLEND",
    },
    {
        key = "builtin_cross_circle",
        labelKey = "texture.builtin_cross_circle",
        fallback = "带圈十字",
        sourceType = "asset",
        assetPath = ASSET_TEXTURE_ROOT .. "cross-circle.tga",
        blendMode = "BLEND",
    },
    {
        key = "builtin_triangle",
        labelKey = "texture.builtin_triangle",
        fallback = "三角",
        sourceType = "asset",
        assetPath = ASSET_TEXTURE_ROOT .. "triangle.tga",
        blendMode = "BLEND",
    },
    {
        key = "builtin_triangle_circle",
        labelKey = "texture.builtin_triangle_circle",
        fallback = "带圈三角",
        sourceType = "asset",
        assetPath = ASSET_TEXTURE_ROOT .. "triangle-circle.tga",
        blendMode = "BLEND",
    },
    {
        key = "builtin_dot",
        labelKey = "texture.builtin_dot",
        fallback = "圆点",
        sourceType = "asset",
        assetPath = ASSET_TEXTURE_ROOT .. "dot.tga",
        blendMode = "BLEND",
    },
    {
        key = "builtin_diamond",
        labelKey = "texture.builtin_diamond",
        fallback = "菱形",
        sourceType = "asset",
        assetPath = ASSET_TEXTURE_ROOT .. "diamond.tga",
        blendMode = "BLEND",
    },
    {
        key = "snowflake",
        labelKey = "texture.snowflake",
        fallback = "雪花",
        sourceType = "fileID",
        fileID = 166386,
        blendMode = "ADD",
    },
    {
        key = "star",
        labelKey = "texture.star",
        fallback = "五角星",
        sourceType = "fileID",
        fileID = 241049,
        blendMode = "ADD",
    },
}

local TEXTURE_OPTIONS_BY_KEY = {}
for _, option in ipairs(TEXTURE_OPTIONS) do
    TEXTURE_OPTIONS_BY_KEY[option.key] = option
end

local featureActive = false
local combatActive = false
local eventsRegistered = false
local eventFrame
local markerFrame
local markerTexture
local activeTextureKey
local currentRotation = DEFAULT_ROTATION
local activeRotationSpeed = DEFAULT_ROTATION_SPEED
local activeRuntimeDB
local activeRangeColorConfigured = false
local runtimeRangeElapsed = RANGE_CHECK_INTERVAL
local lastTextureFailureKey
local settingsLivePreviewActive = false
local settingsPreviewFrame
local settingsPreviewTexture
local settingsPreviewRotation = DEFAULT_ROTATION
local settingsPreviewSpeed = 0
local cachedRangeSpellID
local cachedRangeSpellName
local cachedRangeSpellIconID
local cachedRangeSpellIcon
local rangeSpellPanel
local rangeSpellPanelOwner
local rangeSpellPanelAnchor
local CloseRangeSpellPanel
local currentSpecKeyCacheDirty = true
local cachedCurrentSpecKey
local EventOwner = {}
PlayerPosition.rangeSpellStateScratch = PlayerPosition.rangeSpellStateScratch or {}

local EVENT_NAMES = {
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE",
    "CHARACTER_POINTS_CHANGED",
    "ACTIVE_TALENT_GROUP_CHANGED",
    "ACTIVE_COMBAT_CONFIG_CHANGED",
}
if YUI.IsForever then EVENT_NAMES[#EVENT_NAMES + 1] = "TRAIT_CONFIG_UPDATED" end

local function T(key, fallback)
    if CombatEnhancement.T then
        return CombatEnhancement:T(key, fallback)
    end
    return fallback or key
end

local function BuildArmorLabels()
    return {
        cloth = T("armor.cloth", "布甲"),
        leather = T("armor.leather", "皮甲"),
        mail = T("armor.mail", "锁甲"),
        plate = T("armor.plate", "板甲"),
    }
end

local function GetRangeSpellEditWidth()
    return RANGE_SPELL_EDIT_WIDTH
end

local function GetRangeSpellSpecDisplayName(spec)
    if not spec then return "" end
    if spec.displayName and spec.displayName ~= "" then
        return spec.displayName
    end

    if YUI.Locale and YUI.Locale.GetSpecializationName then
        return YUI.Locale:GetSpecializationName(spec.specID, spec.name)
    end
    return spec.name or tostring(spec.specID or "")
end

local function GetRangeSpellSpecGroups()
    local Settings = YUI.Settings
    if not (Settings and Settings.GetSpecSelectionGroups) then
        return {}
    end

    local ok, groups = pcall(Settings.GetSpecSelectionGroups, Settings, {
        armorLabels = BuildArmorLabels(),
    })
    if ok and type(groups) == "table" then
        return groups
    end
    return {}
end

local function ClampNumber(value, minValue, maxValue, fallback)
    value = tonumber(value)
    if value == nil then value = fallback end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function ClampColorComponent(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function NormalizeColorValue(value)
    if type(value) ~= "table" then
        value = DEFAULT_COLOR
    end
    return {
        ClampColorComponent(value[1] or value.r, DEFAULT_COLOR[1]),
        ClampColorComponent(value[2] or value.g, DEFAULT_COLOR[2]),
        ClampColorComponent(value[3] or value.b, DEFAULT_COLOR[3]),
        ClampColorComponent(value[4] or value.a, DEFAULT_COLOR[4]),
    }
end

local function NormalizeColorWithDefault(value, defaultColor)
    if type(defaultColor) ~= "table" then
        defaultColor = DEFAULT_COLOR
    end
    if type(value) ~= "table" then
        value = defaultColor
    end
    return {
        ClampColorComponent(value[1] or value.r, defaultColor[1]),
        ClampColorComponent(value[2] or value.g, defaultColor[2]),
        ClampColorComponent(value[3] or value.b, defaultColor[3]),
        ClampColorComponent(value[4] or value.a, defaultColor[4]),
    }
end

local function NormalizeSpellID(value)
    if value == nil or value == "" then
        return nil
    end
    value = tonumber(value)
    if not value then
        return nil
    end
    value = math.floor(value + 0.5)
    if value < MIN_RANGE_SPELL_ID or value > MAX_RANGE_SPELL_ID then
        return nil
    end
    return value
end

local function NormalizeRangeSpellIDMap(value)
    local result = {}
    if type(value) == "table" then
        for key, spellID in pairs(value) do
            local normalized = NormalizeSpellID(spellID)
            if type(key) == "string" and key ~= "" and normalized then
                result[key] = normalized
            end
        end
    end
    return result
end

local function TrimText(value)
    value = tostring(value or "")
    if strtrim then
        return strtrim(value)
    end
    return value:match("^%s*(.-)%s*$") or ""
end

local function GetRangeSpellAPI()
    return SpellAPI or (YUI.API and YUI.API.Spell) or YUI.WOW_API
end

local function RememberRangeSpellName(spellID, name)
    if type(name) == "string" and name ~= "" then
        cachedRangeSpellID = spellID
        cachedRangeSpellName = name
        return name
    end
    return nil
end

local function RememberRangeSpellIcon(spellID, icon)
    if icon then
        cachedRangeSpellIconID = spellID
        cachedRangeSpellIcon = icon
        return icon
    end
    return nil
end

local function ReadSpellNameFromInfo(info)
    if type(info) == "table" then
        return info.name
    elseif type(info) == "string" and info ~= "" then
        return info
    end
    return nil
end

local function ReadSpellIconFromInfo(info)
    if type(info) == "table" then
        return info.originalIconID or info.iconID or info.icon or info.texture
    end
    return nil
end

local function GetSpellDisplayName(spellID)
    spellID = NormalizeSpellID(spellID)
    if not spellID then
        return nil
    end
    if cachedRangeSpellID == spellID and cachedRangeSpellName then
        return cachedRangeSpellName
    end

    local spell = GetRangeSpellAPI()
    if spell then
        if spell.GetName then
            local ok, name = pcall(spell.GetName, spellID)
            if ok and type(name) == "string" and name ~= "" then
                return RememberRangeSpellName(spellID, name)
            end
        end
        if spell.GetInfo then
            local ok, info = pcall(spell.GetInfo, spellID)
            local name = ok and ReadSpellNameFromInfo(info) or nil
            if name and name ~= "" then
                return RememberRangeSpellName(spellID, name)
            end
        end
    end

    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        local name = ok and ReadSpellNameFromInfo(info) or nil
        if name and name ~= "" then
            return RememberRangeSpellName(spellID, name)
        end
    end

    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and type(name) == "string" and name ~= "" then
            return RememberRangeSpellName(spellID, name)
        end
    end

    return nil
end

local function GetSpellDisplayIcon(spellID)
    spellID = NormalizeSpellID(spellID)
    if not spellID then
        return nil
    end
    local spell = GetRangeSpellAPI()
    if spell then
        if spell.GetInfo then
            local ok, info = pcall(spell.GetInfo, spellID)
            local icon = ok and ReadSpellIconFromInfo(info) or nil
            if icon then
                return RememberRangeSpellIcon(spellID, icon)
            end
        end
        if cachedRangeSpellIconID == spellID and cachedRangeSpellIcon then
            return cachedRangeSpellIcon
        end
        if spell.GetTexture then
            local ok, icon = pcall(spell.GetTexture, spellID)
            if ok and icon then
                return RememberRangeSpellIcon(spellID, icon)
            end
        end
        if spell.GetSpellIcon then
            local ok, icon = pcall(spell.GetSpellIcon, spellID)
            if ok and icon then
                return RememberRangeSpellIcon(spellID, icon)
            end
        end
    elseif cachedRangeSpellIconID == spellID and cachedRangeSpellIcon then
        return cachedRangeSpellIcon
    end

    if C_Spell and C_Spell.GetSpellTexture then
        local ok, icon = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and icon then
            return RememberRangeSpellIcon(spellID, icon)
        end
    end

    if GetSpellTexture then
        local ok, icon = pcall(GetSpellTexture, spellID)
        if ok and icon then
            return RememberRangeSpellIcon(spellID, icon)
        end
    end

    return nil
end

local function InvalidateCurrentSpecCache()
    currentSpecKeyCacheDirty = true
end

local function NormalizeVisibilityMode(value)
    if VALID_VISIBILITY_MODES[value] then
        return value
    end
    return DEFAULT_VISIBILITY_MODE
end

local function NormalizeSpecFilter(value)
    local result = {}
    if type(value) == "table" then
        for key, enabled in pairs(value) do
            if type(key) == "string" and key ~= "" and enabled == false then
                result[key] = false
            end
        end
    end
    return result
end

local function GetColorComponents(db)
    local color = NormalizeColorValue(db and db.playerPositionColor)
    return color[1], color[2], color[3], color[4]
end

local function IsAtlasInfoAvailable(atlas)
    if type(atlas) ~= "string" or atlas == "" then
        return false
    end
    if C_Texture and C_Texture.GetAtlasInfo then
        local ok, info = pcall(C_Texture.GetAtlasInfo, atlas)
        return ok and info ~= nil
    end
    return true
end

local function IsTextureOptionAvailable(option)
    if type(option) ~= "table" then
        return false
    end
    if option.sourceType == "atlas" then
        return IsAtlasInfoAvailable(option.atlas)
    elseif option.sourceType == "asset" then
        return type(option.assetPath) == "string" and option.assetPath ~= ""
    end
    return option.fileID ~= nil
end

local function ResolveDefaultTextureKey()
    local defaultOption = TEXTURE_OPTIONS_BY_KEY[DEFAULT_TEXTURE]
    if IsTextureOptionAvailable(defaultOption) then
        return DEFAULT_TEXTURE
    end
    return FALLBACK_TEXTURE
end

local function NormalizeTextureKey(value)
    local option = type(value) == "string" and TEXTURE_OPTIONS_BY_KEY[value]
    if option and IsTextureOptionAvailable(option) then
        return value
    end
    return ResolveDefaultTextureKey()
end

local function TryMigrateLegacyRangeSpellID(db)
    if type(db) ~= "table" then return end

    db.playerPositionRangeSpellIDs = NormalizeRangeSpellIDMap(db.playerPositionRangeSpellIDs)
    if db.playerPositionRangeSpellIDsMigrated == true then
        db.playerPositionRangeSpellID = nil
        return
    end

    local legacySpellID = NormalizeSpellID(db.playerPositionRangeSpellID)
    if not legacySpellID then
        db.playerPositionRangeSpellIDsMigrated = true
        db.playerPositionRangeSpellID = nil
        return
    end

    local migratedCount = 0
    for _, group in ipairs(GetRangeSpellSpecGroups()) do
        for _, spec in ipairs(group.specs or {}) do
            local key = spec and spec.key
            if type(key) == "string" and key ~= "" then
                if db.playerPositionRangeSpellIDs[key] == nil then
                    db.playerPositionRangeSpellIDs[key] = legacySpellID
                end
                migratedCount = migratedCount + 1
            end
        end
    end

    if migratedCount > 0 then
        db.playerPositionRangeSpellIDsMigrated = true
        db.playerPositionRangeSpellID = nil
    end
end

function PlayerPosition:NormalizeDB(db)
    if type(db) ~= "table" then db = self.defaults end
    local legacyRotate = db.playerPositionRotate
    local textureDefaultVersion = tonumber(db.playerPositionTextureDefaultVersion) or 1
    if textureDefaultVersion < DEFAULT_TEXTURE_VERSION and db.playerPositionTexture == FALLBACK_TEXTURE then
        db.playerPositionTexture = DEFAULT_TEXTURE
    end
    db.playerPositionTextureDefaultVersion = DEFAULT_TEXTURE_VERSION
    db.playerPositionEnabled = db.playerPositionEnabled ~= false
    db.playerPositionTexture = NormalizeTextureKey(db.playerPositionTexture)
    db.playerPositionSize = ClampNumber(db.playerPositionSize, MIN_SIZE, MAX_SIZE, DEFAULT_SIZE)
    db.playerPositionColor = NormalizeColorValue(db.playerPositionColor)
    db.playerPositionRotationSpeed = ClampNumber(db.playerPositionRotationSpeed, MIN_ROTATION_SPEED, MAX_ROTATION_SPEED, DEFAULT_ROTATION_SPEED)
    db.playerPositionOffsetX = ClampNumber(db.playerPositionOffsetX, MIN_OFFSET, MAX_OFFSET, DEFAULT_OFFSET_X)
    db.playerPositionOffsetY = ClampNumber(db.playerPositionOffsetY, MIN_OFFSET, MAX_OFFSET, DEFAULT_OFFSET_Y)
    db.playerPositionVisibilityMode = NormalizeVisibilityMode(db.playerPositionVisibilityMode)
    db.playerPositionRangeColorEnabled = db.playerPositionRangeColorEnabled == true
    TryMigrateLegacyRangeSpellID(db)
    db.playerPositionInRangeColor = NormalizeColorWithDefault(db.playerPositionInRangeColor, DEFAULT_IN_RANGE_COLOR)
    db.playerPositionOutOfRangeColor = NormalizeColorWithDefault(db.playerPositionOutOfRangeColor, DEFAULT_OUT_OF_RANGE_COLOR)
    db.playerPositionSpecFilterEnabled = db.playerPositionSpecFilterEnabled == true
    db.playerPositionSpecFilter = NormalizeSpecFilter(db.playerPositionSpecFilter)
    if legacyRotate == false then
        db.playerPositionRotationSpeed = 0
    end
    db.playerPositionRotate = nil
    return db
end

local function GetDB(db)
    if type(db) ~= "table" and CombatEnhancement.GetDB then
        db = CombatEnhancement:GetDB()
    end
    return PlayerPosition:NormalizeDB(db)
end

local function BuildTextureOptions()
    local items = {}
    for _, option in ipairs(TEXTURE_OPTIONS) do
        if IsTextureOptionAvailable(option) then
            items[#items + 1] = {
                text = T(option.labelKey, option.fallback),
                value = option.key,
            }
        end
    end
    return items
end

local function BuildVisibilityOptions()
    local items = {}
    for _, option in ipairs(VISIBILITY_OPTIONS) do
        items[#items + 1] = {
            text = T(option.textKey, option.fallback),
            value = option.value,
        }
    end
    return items
end

local function IsPlayerInCombat()
    local api = CombatAPI or (YUI.API and YUI.API.Combat)
    if api and api.UnitAffectingCombat then
        return api.UnitAffectingCombat("player") == true
    end
    if UnitAffectingCombat then
        return UnitAffectingCombat("player") == true
    end
    if api and api.InCombatLockdown then
        return api.InCombatLockdown() == true
    end
    if InCombatLockdown then
        return InCombatLockdown() == true
    end
    return false
end

local function IsPlayerInSupportedInstance()
    if not IsInInstance then
        return false
    end
    local ok, inInstance, instanceType = pcall(IsInInstance)
    if not ok then
        return false
    end
    return inInstance == true and (instanceType == "party" or instanceType == "raid")
end

local function GetPlayerClassToken()
    local api = UnitAPI or (YUI.API and YUI.API.Unit) or YUI.WOW_API
    local _, classToken
    if api and api.UnitClass then
        _, classToken = api.UnitClass("player")
    elseif UnitClass then
        _, classToken = UnitClass("player")
    end
    return classToken
end

local function BuildSpecKey(classToken, specID)
    if not classToken or not specID then return nil end
    return tostring(classToken) .. ":" .. tostring(specID)
end

local function GetCurrentSpecKey()
    if not currentSpecKeyCacheDirty then
        return cachedCurrentSpecKey
    end

    local Settings = YUI.Settings
    if Settings and Settings.GetCurrentSpecSelectionKey then
        local key = Settings:GetCurrentSpecSelectionKey()
        if key then
            cachedCurrentSpecKey = key
            currentSpecKeyCacheDirty = false
            return cachedCurrentSpecKey
        end
    end

    local talent = YUI.API and YUI.API.Talent or YUI.WOW_API
    local classToken = GetPlayerClassToken()
    if talent and (talent.GetCurrentConfigurationSpecializationInfo or talent.GetCurrentSpecializationInfo) then
        local specInfo = (talent.GetCurrentConfigurationSpecializationInfo or talent.GetCurrentSpecializationInfo)()
        if specInfo and specInfo.specID then
            cachedCurrentSpecKey = BuildSpecKey(specInfo.classFile or classToken, specInfo.specID)
            currentSpecKeyCacheDirty = false
            return cachedCurrentSpecKey
        end
    end
    cachedCurrentSpecKey = nil
    currentSpecKeyCacheDirty = false
    return nil
end

local function IsCurrentSpecAllowed(db)
    if type(db) ~= "table" then
        db = GetDB(db)
    end
    if db.playerPositionSpecFilterEnabled ~= true then
        return true
    end
    local key = GetCurrentSpecKey()
    if not key then
        return true
    end
    return db.playerPositionSpecFilter[key] ~= false
end

local function IsVisibilityModeActive(db)
    if type(db) ~= "table" then
        db = GetDB(db)
    end
    local mode = db.playerPositionVisibilityMode
    if mode == "always" then
        return true
    elseif mode == "instance" then
        return IsPlayerInSupportedInstance()
    elseif mode == "instance_combat" then
        return combatActive == true and IsPlayerInSupportedInstance()
    end
    return combatActive == true
end

local function UnitExistsCompat(unit)
    local api = UnitAPI or (YUI.API and YUI.API.Unit) or YUI.WOW_API
    if api and api.UnitExists then
        return api.UnitExists(unit) == true
    end
    if UnitExists then
        return UnitExists(unit) == true
    end
    return false
end

function PlayerPosition.ClearRangeSpellState(state)
    if type(state) ~= "table" then
        return {}
    end
    for key in pairs(state) do
        state[key] = nil
    end
    return state
end

local function NormalizeRangeCheckResult(value)
    if value == true or value == 1 then
        return true
    elseif value == false or value == 0 then
        return false
    end
    return nil
end

function PlayerPosition.HasRangeSpellAdapter()
    local spell = GetRangeSpellAPI()
    return spell and spell.IsInRange ~= nil
end

function PlayerPosition.CallRangeSpellHasRange(spell, spellID)
    return spell.HasRange(spellID)
end

function PlayerPosition.CallRangeSpellIsInRange(spell, spellID, unit)
    return spell.IsInRange(spellID, unit)
end

function PlayerPosition.ReadRangeSpellHasRange(spellID)
    spellID = NormalizeSpellID(spellID)
    if not spellID then
        return nil
    end
    local spell = GetRangeSpellAPI()
    if not spell then
        return nil
    end

    local ok, result
    if not spell.HasRange then
        return nil
    end
    ok, result = pcall(PlayerPosition.CallRangeSpellHasRange, spell, spellID)
    if not ok then
        return nil
    end
    return NormalizeRangeCheckResult(result)
end

function PlayerPosition.ReadRangeSpellInRange(spellID, unit)
    spellID = NormalizeSpellID(spellID)
    if not spellID then
        return nil
    end
    local spell = GetRangeSpellAPI()
    if not spell then
        return nil
    end

    local ok, result
    unit = unit or "target"
    if not spell.IsInRange then
        return nil
    end
    ok, result = pcall(PlayerPosition.CallRangeSpellIsInRange, spell, spellID, unit)
    if not ok then
        return nil
    end
    return NormalizeRangeCheckResult(result)
end

function PlayerPosition.ResolveCurrentRangeSpell(db, unit, state)
    if type(db) ~= "table" then
        db = GetDB(db)
    end
    state = PlayerPosition.ClearRangeSpellState(state or {})
    state.enabled = db.playerPositionRangeColorEnabled == true
    state.unit = unit or "target"
    state.specKey = GetCurrentSpecKey()
    if not state.specKey then
        state.reason = "no-spec"
        return state
    end

    local spellIDs = type(db.playerPositionRangeSpellIDs) == "table" and db.playerPositionRangeSpellIDs or nil
    state.spellID = NormalizeSpellID(spellIDs and spellIDs[state.specKey])
    if not state.spellID then
        state.reason = "unset"
        return state
    end

    state.spellName = GetSpellDisplayName(state.spellID)
    state.icon = GetSpellDisplayIcon(state.spellID)
    state.hasRange = PlayerPosition.ReadRangeSpellHasRange(state.spellID)
    if state.hasRange == false then
        state.reason = "no-range"
        return state
    end
    if not state.enabled then
        state.reason = "disabled"
        return state
    end
    if not UnitExistsCompat(state.unit) then
        state.reason = "no-target"
        return state
    end

    state.inRange = PlayerPosition.ReadRangeSpellInRange(state.spellID, state.unit)
    if state.inRange == true then
        state.reason = "in-range"
    elseif state.inRange == false then
        state.reason = "out-of-range"
    else
        state.reason = "range-unavailable"
    end
    return state
end

local function IsRangeColorConfigured(db)
    local state = PlayerPosition.ResolveCurrentRangeSpell(db, "target", PlayerPosition.rangeSpellStateScratch)
    if state.enabled ~= true or not state.spellID or not UnitExistsCompat("target") then
        return false
    end
    if state.hasRange == false then
        return false
    end
    return PlayerPosition.HasRangeSpellAdapter() == true
end

local function ResolveRuntimeColor(db)
    if type(db) ~= "table" then
        db = GetDB(db)
    end
    local state = PlayerPosition.ResolveCurrentRangeSpell(db, "target", PlayerPosition.rangeSpellStateScratch)
    if state.inRange == true then
        return db.playerPositionInRangeColor
    elseif state.inRange == false then
        return db.playerPositionOutOfRangeColor
    end
    return db.playerPositionColor
end

local function ApplyRuntimeColor(db)
    if not (markerTexture and markerTexture.SetVertexColor) then return end
    local color = NormalizeColorValue(ResolveRuntimeColor(db))
    markerTexture:SetVertexColor(color[1], color[2], color[3], color[4])
end

local function ApplyRuntimeFrameLayer(frame)
    if not frame then return end
    if frame.SetFrameStrata then
        frame:SetFrameStrata(RUNTIME_FRAME_STRATA)
    end
    if frame.SetFrameLevel then
        frame:SetFrameLevel(RUNTIME_FRAME_LEVEL)
    end
end

local function ResetRuntimeTextureRotation()
    currentRotation = DEFAULT_ROTATION
    if markerTexture and markerTexture.SetRotation then
        pcall(markerTexture.SetRotation, markerTexture, currentRotation)
    end
end

local function StopRuntimeUpdates()
    if markerFrame and markerFrame.SetScript then
        markerFrame:SetScript("OnUpdate", nil)
    end
    activeRuntimeDB = nil
    activeRangeColorConfigured = false
    runtimeRangeElapsed = RANGE_CHECK_INTERVAL
end

local cpuWatchdog = YUI.CPUWatchdog
local function OnRuntimeUpdate(frame, elapsed)
    local cpuStartedAt = cpuWatchdog and cpuWatchdog.timingActive and cpuWatchdog:BeginProbeTiming()
    elapsed = tonumber(elapsed) or 0

    if activeRotationSpeed > 0 then
        currentRotation = (currentRotation + elapsed * BASE_ROTATION_SPEED * activeRotationSpeed) % TWO_PI
        if markerTexture and markerTexture.SetRotation then
            markerTexture:SetRotation(currentRotation)
        end
    end

    if activeRangeColorConfigured then
        runtimeRangeElapsed = runtimeRangeElapsed + elapsed
        if runtimeRangeElapsed >= RANGE_CHECK_INTERVAL then
            runtimeRangeElapsed = 0
            local db = activeRuntimeDB or GetDB()
            ApplyRuntimeColor(db)
        end
    end
    if cpuStartedAt then cpuWatchdog:EndProbeTiming("component.player-position", cpuStartedAt) end
end

local function UpdateRuntimeUpdateState(db)
    if not (markerFrame and markerFrame.SetScript) then return end
    db = GetDB(db)
    activeRotationSpeed = db.playerPositionRotationSpeed or DEFAULT_ROTATION_SPEED
    if activeRotationSpeed <= 0 then
        ResetRuntimeTextureRotation()
    end
    activeRuntimeDB = db
    activeRangeColorConfigured = IsRangeColorConfigured(db)
    runtimeRangeElapsed = RANGE_CHECK_INTERVAL

    if (markerFrame.IsShown and markerFrame:IsShown()) and (activeRotationSpeed > 0 or activeRangeColorConfigured) then
        markerFrame:SetScript("OnUpdate", OnRuntimeUpdate)
    else
        StopRuntimeUpdates()
    end
end

if cpuWatchdog and cpuWatchdog.RegisterProbe then
    cpuWatchdog:RegisterProbe("component.player-position", {
        localeKey = "cpu_watch.probe.player_position",
        kind = "frame",
        getTarget = function() return markerFrame end,
        snapshot = function()
            return {
                running = markerFrame and markerFrame:GetScript("OnUpdate") == OnRuntimeUpdate or false,
                rotationSpeed = activeRotationSpeed or 0,
                rangeColor = activeRangeColorConfigured == true,
            }
        end,
    })
end

local function DebugTextureFailure(option, reason)
    local key = option and option.key or "unknown"
    if lastTextureFailureKey == key then return end
    lastTextureFailureKey = key
    if YUI.Debug then
        YUI:Debug("CombatEnhancement | PlayerPosition texture failed | " .. tostring(key) .. " | " .. tostring(reason))
    end
end

local function ResolveTextureOption(db)
    db = GetDB(db)
    return TEXTURE_OPTIONS_BY_KEY[db.playerPositionTexture] or TEXTURE_OPTIONS_BY_KEY[ResolveDefaultTextureKey()] or TEXTURE_OPTIONS_BY_KEY[FALLBACK_TEXTURE]
end

local function ResolveAssetTexturePath(option)
    if not (option and option.assetPath) then
        return nil
    end
    local assets = Assets or YUI.Assets
    if assets and assets.Component then
        return assets:Component("CombatEnhancement", option.assetPath)
    end
    return nil
end

local function ApplyTextureSource(texture, option)
    if not (texture and option) then
        return false, "missing texture source"
    end

    if option.sourceType == "atlas" then
        if not texture.SetAtlas then
            return false, "SetAtlas unavailable"
        end
        if not IsAtlasInfoAvailable(option.atlas) then
            return false, "atlas unavailable"
        end
        local ok, reason = pcall(texture.SetAtlas, texture, option.atlas, false)
        if not ok then
            return false, reason
        end
        return true
    end

    if option.sourceType == "asset" then
        if not texture.SetTexture then
            return false, "SetTexture unavailable"
        end
        local path = ResolveAssetTexturePath(option)
        if not path then
            return false, "asset path unavailable"
        end
        local ok, reason = pcall(texture.SetTexture, texture, path)
        if not ok then
            return false, reason
        end
        if texture.SetTexCoord then
            texture:SetTexCoord(0, 1, 0, 1)
        end
        return true
    end

    if not texture.SetTexture then
        return false, "SetTexture unavailable"
    end
    local ok, reason = pcall(texture.SetTexture, texture, option.fileID)
    if not ok then
        return false, reason
    end
    if texture.SetTexCoord then
        texture:SetTexCoord(0, 1, 0, 1)
    end
    return true
end

local function ApplyTextureSourceWithFallback(texture, option)
    local fallbackKey = ResolveDefaultTextureKey()
    option = option or TEXTURE_OPTIONS_BY_KEY[fallbackKey] or TEXTURE_OPTIONS_BY_KEY[FALLBACK_TEXTURE]
    local ok, reason = ApplyTextureSource(texture, option)
    if ok then
        lastTextureFailureKey = nil
        return option
    end

    DebugTextureFailure(option, reason)
    if option.key == fallbackKey then
        return nil
    end

    local fallbackOption = TEXTURE_OPTIONS_BY_KEY[fallbackKey] or TEXTURE_OPTIONS_BY_KEY[FALLBACK_TEXTURE]
    ok, reason = ApplyTextureSource(texture, fallbackOption)
    if ok then
        return fallbackOption
    end
    DebugTextureFailure(fallbackOption, reason)
    return nil
end

local function ApplyTextureCommon(texture, db, option)
    if not texture then return end
    db = GetDB(db)
    if texture.SetVertexColor then
        texture:SetVertexColor(GetColorComponents(db))
    end
    if texture.SetBlendMode then
        texture:SetBlendMode((option and option.blendMode) or "ADD")
    end
end

local function EnsureFrame()
    if markerFrame then
        return markerFrame
    end

    if not (CreateFrame and UIParent) then
        return nil
    end

    markerFrame = CreateFrame("Frame", "YUI_CombatEnhancement_PlayerPositionFrame", UIParent)
    markerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    markerFrame:SetSize(DEFAULT_SIZE, DEFAULT_SIZE)
    ApplyRuntimeFrameLayer(markerFrame)
    markerFrame:EnableMouse(false)

    markerTexture = markerFrame:CreateTexture(nil, "ARTWORK")
    markerTexture:SetAllPoints(markerFrame)
    if markerTexture.SetTexCoord then
        markerTexture:SetTexCoord(0, 1, 0, 1)
    end
    if markerTexture.SetBlendMode then
        markerTexture:SetBlendMode("ADD")
    end

    markerFrame:Hide()
    return markerFrame
end

local function ApplyTexture(db)
    local frame = EnsureFrame()
    if not (frame and markerTexture) then return end

    db = GetDB(db)
    local option = ResolveTextureOption(db)
    local appliedOption = TEXTURE_OPTIONS_BY_KEY[activeTextureKey]
    if activeTextureKey ~= option.key then
        appliedOption = ApplyTextureSourceWithFallback(markerTexture, option)
        activeTextureKey = appliedOption and appliedOption.key or nil
    end

    ApplyTextureCommon(markerTexture, db, appliedOption or option)
    if markerFrame and markerFrame.IsShown and markerFrame:IsShown() then
        ApplyRuntimeColor(db)
    end
end

local function ApplyPosition(db)
    local frame = EnsureFrame()
    if not (frame and UIParent) then return end
    db = GetDB(db)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", db.playerPositionOffsetX, db.playerPositionOffsetY)
end

local function ApplySize(db)
    local frame = EnsureFrame()
    if not frame then return end
    db = GetDB(db)
    frame:SetSize(db.playerPositionSize, db.playerPositionSize)
end

local function UpdateRuntimeState(db)
    local frame = EnsureFrame()
    if not frame then return end
    db = GetDB(db)
    ApplyRuntimeColor(db)
    UpdateRuntimeUpdateState(db)
end

local function ShowMarker(db)
    local frame = EnsureFrame()
    if not frame then return end
    ApplyRuntimeFrameLayer(frame)
    db = GetDB(db)
    ApplyPosition(db)
    ApplySize(db)
    ApplyTexture(db)
    frame:Show()
    UpdateRuntimeState(db)
end

local function HideMarker()
    StopRuntimeUpdates()
    ResetRuntimeTextureRotation()
    if markerFrame then
        ApplyRuntimeFrameLayer(markerFrame)
        markerFrame:Hide()
    end
end

local function ShouldShowMarker(db)
    db = GetDB(db)
    if db.playerPositionEnabled ~= true then
        return false
    end
    if settingsLivePreviewActive then
        return true
    end
    return featureActive and IsVisibilityModeActive(db) and IsCurrentSpecAllowed(db)
end

local function StopSettingsPreview()
    if settingsPreviewFrame and settingsPreviewFrame.SetScript then
        settingsPreviewFrame:SetScript("OnUpdate", nil)
    end
    if settingsPreviewTexture and settingsPreviewTexture.SetRotation then
        pcall(settingsPreviewTexture.SetRotation, settingsPreviewTexture, DEFAULT_ROTATION)
    end
    settingsPreviewFrame = nil
    settingsPreviewTexture = nil
    settingsPreviewRotation = DEFAULT_ROTATION
    settingsPreviewSpeed = 0
end

local function StopAllSettingsPreviews(_, _, reason)
    StopSettingsPreview()
    if reason and reason.replacing then
        return
    end
    settingsLivePreviewActive = false
    PlayerPosition:RefreshRuntime()
end

local function OnSettingsPreviewUpdate(frame, elapsed)
    if not settingsPreviewTexture then return end
    settingsPreviewRotation = (settingsPreviewRotation + (tonumber(elapsed) or 0) * BASE_ROTATION_SPEED * settingsPreviewSpeed) % TWO_PI
    if settingsPreviewTexture.SetRotation then
        settingsPreviewTexture:SetRotation(settingsPreviewRotation)
    end
end

local function RenderSettingsPreview(parent, context, db)
    if not (parent and GUI2 and GUI2.CreateFrame and GUI2.CreateTexture) then
        return
    end

    StopSettingsPreview()
    db = GetDB(db)

    local availableWidth = context and context.width or (SETTINGS_PREVIEW_WIDTH - 24)
    local availableHeight = context and context.height or (SETTINGS_PREVIEW_HEIGHT - 50)
    local textureSize = math.min(db.playerPositionSize, SETTINGS_PREVIEW_MAX_TEXTURE_SIZE, availableWidth or SETTINGS_PREVIEW_MAX_TEXTURE_SIZE, availableHeight or SETTINGS_PREVIEW_MAX_TEXTURE_SIZE)
    textureSize = math.max(textureSize, MIN_SIZE)

    local frame = GUI2:CreateFrame(parent, {
        width = textureSize,
        height = textureSize,
    })
    frame:SetPoint("CENTER", parent, "CENTER", 0, 0)

    local texture = GUI2:CreateTexture(frame, { layer = "ARTWORK" })
    texture:SetAllPoints(frame)

    local option = ResolveTextureOption(db)
    local appliedOption = ApplyTextureSourceWithFallback(texture, option)
    ApplyTextureCommon(texture, db, appliedOption or option)

    settingsPreviewFrame = frame
    settingsPreviewTexture = texture
    settingsPreviewRotation = DEFAULT_ROTATION
    settingsPreviewSpeed = db.playerPositionRotationSpeed or 0

    if settingsPreviewSpeed > 0 then
        frame:SetScript("OnUpdate", OnSettingsPreviewUpdate)
    elseif texture.SetRotation then
        texture:SetRotation(DEFAULT_ROTATION)
    end
end

function PlayerPosition:RefreshSettingsPreview(db)
    local Settings = YUI.Settings
    db = GetDB(db)

    if not (Settings and Settings.ShowRightPreview) then
        settingsLivePreviewActive = true
        self:RefreshRuntime(db)
        return
    end

    Settings:ShowRightPreview(self, {
        title = T("settings.player_position_preview", "预览"),
        width = SETTINGS_PREVIEW_WIDTH,
        height = SETTINGS_PREVIEW_HEIGHT,
        render = function(parent, context)
            RenderSettingsPreview(parent, context, db)
        end,
        onClear = StopAllSettingsPreviews,
    })
    settingsLivePreviewActive = true
    self:RefreshRuntime(db)
end

function PlayerPosition:ClearSettingsPreview()
    settingsLivePreviewActive = false
    local Settings = YUI.Settings
    if Settings and Settings.ClearRightPreview then
        Settings:ClearRightPreview(self)
    else
        StopSettingsPreview()
    end
end

function PlayerPosition:RefreshRuntime(db)
    db = GetDB(db)
    if not ShouldShowMarker(db) then
        HideMarker()
        return
    end
    ShowMarker(db)
end

local function OnCombatStateEvent(eventOrSelf, maybeEvent)
    local eventName = type(eventOrSelf) == "string" and eventOrSelf or maybeEvent
    InvalidateCurrentSpecCache()
    if eventName == "PLAYER_REGEN_DISABLED" then
        combatActive = true
        PlayerPosition:RefreshRuntime()
    elseif eventName == "PLAYER_REGEN_ENABLED" then
        combatActive = false
        PlayerPosition:RefreshRuntime()
    else
        combatActive = IsPlayerInCombat()
        PlayerPosition:RefreshRuntime()
    end
end

local function AttachEvents()
    if eventsRegistered then return end

    if YUI.Event and YUI.Event.On then
        for _, eventName in ipairs(EVENT_NAMES) do
            YUI.Event:On(eventName, OnCombatStateEvent, EventOwner, {
                traceName = "CombatEnhancement:PlayerPosition:" .. eventName,
                moduleId = "component:CombatEnhancement",
            })
        end
        eventsRegistered = "eventbus"
        return
    end

    if CreateFrame then
        eventFrame = eventFrame or CreateFrame("Frame")
        for _, eventName in ipairs(EVENT_NAMES) do
            pcall(eventFrame.RegisterEvent, eventFrame, eventName)
        end
        eventFrame:SetScript("OnEvent", OnCombatStateEvent)
        eventsRegistered = "frame"
    end
end

local function DetachEvents()
    if eventsRegistered == "eventbus" and YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(EventOwner)
    elseif eventsRegistered == "frame" and eventFrame then
        for _, eventName in ipairs(EVENT_NAMES) do
            pcall(eventFrame.UnregisterEvent, eventFrame, eventName)
        end
        eventFrame:SetScript("OnEvent", nil)
    end
    eventsRegistered = false
end

function PlayerPosition:OnFeatureToggle(enabled, db)
    featureActive = enabled == true
    if featureActive then
        combatActive = IsPlayerInCombat()
        AttachEvents()
        self:RefreshRuntime(db)
    else
        combatActive = false
        if CloseRangeSpellPanel then CloseRangeSpellPanel() end
        self:ReleaseRangeSpellNameCache()
        DetachEvents()
        self:RefreshRuntime(db)
    end
end

local function AddAlignedFieldRow(options, fields)
    options[#options + 1] = {
        type = "custom",
        retainedFields = fields,
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
                columns = 1,
                labelPosition = "top",
                columnGap = COLUMN_GAP,
                labelWidth = LABEL_WIDTH,
                labelGap = LABEL_GAP,
                bodyWidth = BODY_WIDTH,
                valueWidth = INPUT_WIDTH,
                valueGap = VALUE_GAP,
                rowHeight = 32,
                rowGap = 10,
                fields = fields,
            })
            return gridWidth, gridHeight
        end,
    }
end

local function AddAlignedFieldGroup(options, label, fields)
    options[#options + 1] = { type = "divider", label = label, alignLeft = true, width = SECTION_WIDTH }
    options[#options + 1] = {
        type = "custom",
        retainedFields = fields,
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
                columns = 2,
                labelPosition = "top",
                columnGap = COLUMN_GAP,
                labelWidth = LABEL_WIDTH,
                labelGap = LABEL_GAP,
                bodyWidth = BODY_WIDTH,
                valueWidth = INPUT_WIDTH,
                valueGap = VALUE_GAP,
                rowHeight = 32,
                rowGap = 10,
                fields = fields,
            })
            return gridWidth, gridHeight
        end,
    }
end

local function FormatSpecSummary(selected, total)
    return string.format(T("settings.player_position_spec_summary", "%d/%d 专精"), selected or 0, total or 0)
end

local function FormatRangeSpellIDsSummary(selected, total)
    return string.format(T("settings.player_position_range_spell_ids_summary", "已设置 %d/%d 专精"), selected or 0, total or 0)
end

local function CountRangeSpellIDs(groups, valueTable)
    local configured = 0
    local total = 0
    valueTable = type(valueTable) == "table" and valueTable or {}
    for _, group in ipairs(groups or {}) do
        for _, spec in ipairs(group.specs or {}) do
            local key = spec and spec.key
            if type(key) == "string" and key ~= "" then
                total = total + 1
                if NormalizeSpellID(valueTable[key]) then
                    configured = configured + 1
                end
            end
        end
    end
    return configured, total
end

local function SetRangeSpellInputTextColor(editbox, colorKey, fallback)
    if not editbox then return end
    local r, g, b, a
    if GUI2 and GUI2.GetColor then
        r, g, b, a = GUI2:GetColor(colorKey, fallback)
    elseif type(fallback) == "table" then
        r, g, b, a = fallback[1], fallback[2], fallback[3], fallback[4] or 1
    end
    editbox:SetTextColor(r or 1, g or 1, b or 1, a or 1)
end

local function FormatRangeSpellIconTag(icon)
    if not icon then
        return nil
    end

    local iconText = tostring(icon)
    if iconText == "" then
        return nil
    end

    return string.format("|T%s:%d:%d:0:0:64:64:4:60:4:60|t ", iconText, RANGE_SPELL_DISPLAY_ICON_SIZE, RANGE_SPELL_DISPLAY_ICON_SIZE)
end

local function FormatRangeSpellInputText(spellID)
    spellID = NormalizeSpellID(spellID)
    if not spellID then
        return "", false
    end

    local spellName = GetSpellDisplayName(spellID)
    if spellName and spellName ~= "" then
        local iconTag = FormatRangeSpellIconTag(GetSpellDisplayIcon(spellID))
        if iconTag then
            return string.format("%s%s(%d)", iconTag, spellName, spellID), false
        end

        return string.format("%s(%d)", spellName, spellID), false
    end

    return string.format(T("settings.player_position_unknown_spell_format", "未知技能（%d）"), spellID), true, nil
end

local function ExtractRangeSpellInputID(text)
    text = TrimText(text)
    if text == "" then
        return nil, true, false
    end

    local spellID = text:match("^%d+$")
        or text:match("|Hspell:(%d+)")
        or text:match("spell:(%d+)")
        or text:match("%((%d+)%)")
        or text:match("（(%d+)）")
    spellID = NormalizeSpellID(spellID)
    if spellID then
        return spellID, false, false
    end

    local identifier = TrimText(text:gsub("|T.-|t%s*", ""))
    if identifier ~= "" then
        local function NormalizeLookupName(value)
            value = TrimText(value)
            value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            value = value:gsub("%s*%b()$", ""):gsub("%s*（.-）$", "")
            if strlower then
                return strlower(value)
            end
            return string.lower(value)
        end

        local expectedName = NormalizeLookupName(identifier)
        local function AcceptResolvedSpellID(resolvedSpellID)
            local resolvedID = NormalizeSpellID(resolvedSpellID)
            if not resolvedID then
                return nil
            end
            if NormalizeLookupName(GetSpellDisplayName(resolvedID)) == expectedName then
                return resolvedID
            end
            return nil
        end

        local spell = GetRangeSpellAPI()
        if spell and spell.EnsureNameCache then
            pcall(spell.EnsureNameCache)
        end

        if spell and spell.ResolveNameFromCache then
            local ok, cachedSpellID, cachedIcon, cachedName = pcall(spell.ResolveNameFromCache, identifier)
            spellID = ok and NormalizeSpellID(cachedSpellID) or nil
            if spellID and NormalizeLookupName(cachedName or identifier) == expectedName then
                return spellID, false, false
            end
        end

        local cacheStatus
        if spell and spell.GetNameCacheStatus then
            local ok, status = pcall(spell.GetNameCacheStatus)
            cacheStatus = ok and status or nil
        end
        if cacheStatus and cacheStatus.available ~= false and cacheStatus.complete ~= true and cacheStatus.error == nil then
            return nil, false, true, "cache-building"
        end

        if spell and spell.GetIDForIdentifier then
            local ok, resolvedSpellID = pcall(spell.GetIDForIdentifier, identifier)
            spellID = ok and AcceptResolvedSpellID(resolvedSpellID) or nil
            if spellID then
                return spellID, false, false
            end
        end

        if C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
            local ok, resolvedSpellID = pcall(C_Spell.GetSpellIDForSpellIdentifier, identifier)
            spellID = ok and AcceptResolvedSpellID(resolvedSpellID) or nil
            if spellID then
                return spellID, false, false
            end
        end

        if spell and spell.GetInfo then
            local ok, info = pcall(spell.GetInfo, identifier)
            if ok and type(info) == "table" then
                spellID = AcceptResolvedSpellID(info.spellID or info.spellId or info.id)
                if spellID then
                    return spellID, false, false
                end
            end
        end

        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, identifier)
            if ok and type(info) == "table" then
                spellID = AcceptResolvedSpellID(info.spellID or info.spellId or info.id)
                if spellID then
                    return spellID, false, false
                end
            end
        end

        if GetSpellInfo then
            local ok, name, subText, iconID, castTime, minRange, maxRange, resolvedSpellID = pcall(GetSpellInfo, identifier)
            spellID = ok and name and AcceptResolvedSpellID(resolvedSpellID) or nil
            if spellID then
                return spellID, false, false
            end
        end
    end

    return nil, false, true
end

local function ConfigureRangeSpellEdit(editbox, getSpellID, setSpellID, onCommit)
    if not editbox then return end

    editbox:SetJustifyH("LEFT")
    if editbox.SetMaxLetters then
        editbox:SetMaxLetters(160)
    end
    if editbox.SetTextInsets then
        editbox:SetTextInsets(RANGE_SPELL_EDIT_TEXT_INSET, RANGE_SPELL_EDIT_TEXT_INSET, 0, 0)
    end

    local function ReadSpellID()
        return NormalizeSpellID(getSpellID and getSpellID())
    end

    local isSettingText = false
    local originalRefreshTheme = editbox.RefreshTheme

    local function ApplyDisplayColor()
        local _, isUnknown = FormatRangeSpellInputText(ReadSpellID())
        if isUnknown then
            SetRangeSpellInputTextColor(editbox, "color.state.error", { 1, 0.2, 0.2, 1 })
        else
            SetRangeSpellInputTextColor(editbox, "color.text.primary", { 1, 1, 1, 1 })
        end
    end

    local function Display()
        local text = FormatRangeSpellInputText(ReadSpellID())
        isSettingText = true
        editbox:SetText(text)
        if editbox.HighlightText then
            editbox:HighlightText(0, 0)
        end
        if editbox.SetCursorPosition then
            editbox:SetCursorPosition(0)
        end
        isSettingText = false
        ApplyDisplayColor()
    end

    local function Commit()
        if isSettingText then
            return
        end

        local spellID, isEmpty, isInvalid, invalidReason = ExtractRangeSpellInputID(editbox:GetText())
        if isEmpty or spellID then
            if setSpellID then setSpellID(spellID) end
            if onCommit then onCommit(spellID) end
        elseif isInvalid then
            isSettingText = true
            editbox:SetText(TrimText(editbox:GetText()))
            if editbox.HighlightText then
                editbox:HighlightText(0, 0)
            end
            if editbox.SetCursorPosition then
                editbox:SetCursorPosition(0)
            end
            isSettingText = false
            if invalidReason == "cache-building" then
                SetRangeSpellInputTextColor(editbox, "color.state.warning", { 1, 0.82, 0.2, 1 })
                if rangeSpellPanel and PlayerPosition.RefreshRangeSpellNameCacheStatus then
                    PlayerPosition:RefreshRangeSpellNameCacheStatus(rangeSpellPanel)
                end
            else
                SetRangeSpellInputTextColor(editbox, "color.state.error", { 1, 0.2, 0.2, 1 })
            end
            return
        end
        Display()
    end

    editbox.RefreshRangeSpellDisplay = Display
    editbox.CommitRangeSpellValue = Commit

    editbox.RefreshTheme = function(frame)
        if originalRefreshTheme then
            originalRefreshTheme(frame)
        end
        ApplyDisplayColor()
    end

    editbox:SetScript("OnEditFocusGained", function(self)
        if self.gui2Bg and GUI2 and GUI2.SetBorderColor then
            GUI2:SetBorderColor(self.gui2Bg, "color.border.focus")
        end
        isSettingText = true
        local spellID = ReadSpellID()
        self:SetText(spellID and tostring(spellID) or "")
        isSettingText = false
        SetRangeSpellInputTextColor(self, "color.text.primary", { 1, 1, 1, 1 })
        if self.HighlightText then
            self:HighlightText()
        end
    end)

    editbox:SetScript("OnEditFocusLost", function(self)
        if self.gui2Bg and GUI2 and GUI2.SetBorderColor then
            GUI2:SetBorderColor(self.gui2Bg, "color.border.default")
        end
        Commit()
    end)

    editbox:SetScript("OnEnterPressed", function(self)
        Commit()
        self:ClearFocus()
    end)

    editbox:SetScript("OnEscapePressed", function(self)
        Display()
        self:ClearFocus()
    end)

    editbox:SetScript("OnTextChanged", function(self)
        if isSettingText then
            return
        end
        SetRangeSpellInputTextColor(self, "color.text.primary", { 1, 1, 1, 1 })
    end)

    Display()
end

local function ClearRangeSpellContent(parent)
    if not parent then return end
    local Settings = YUI.Settings
    if Settings and Settings.ClearConfig then
        Settings:ClearConfig(parent)
        return
    end

    if parent.GetChildren then
        local children = { parent:GetChildren() }
        for _, child in ipairs(children) do
            child:Hide()
            child:SetParent(nil)
        end
    end
    if parent.GetRegions then
        local regions = { parent:GetRegions() }
        for _, region in ipairs(regions) do
            if region.Hide then region:Hide() end
            if region.SetParent then region:SetParent(nil) end
        end
    end
end

function PlayerPosition:SetRangeSpellNameCachePriority(priority)
    local spell = GetRangeSpellAPI()
    if spell and spell.SetNameCachePriority then
        pcall(spell.SetNameCachePriority, priority)
    end
end

function PlayerPosition:AcquireRangeSpellNameCache()
    local spell = GetRangeSpellAPI()
    if not spell then return nil end
    if spell.AcquireNameCacheOwner then
        pcall(spell.AcquireNameCacheOwner, RANGE_SPELL_CACHE_OWNER, { priority = "interactive" })
        self.rangeSpellNameCacheOwned = true
    end
    if spell.EnsureNameCache then
        local ok, status = pcall(spell.EnsureNameCache, {
            reason = "player-position-panel",
            priority = "interactive",
        })
        return ok and status or nil
    end
    return nil
end

function PlayerPosition:ReleaseRangeSpellNameCache()
    if self.rangeSpellNameCacheOwned ~= true then return end
    self.rangeSpellNameCacheOwned = false
    local spell = GetRangeSpellAPI()
    if spell and spell.ReleaseNameCacheOwner then
        pcall(spell.ReleaseNameCacheOwner, RANGE_SPELL_CACHE_OWNER, {
            delay = 60,
            reason = "player-position-panel-close",
        })
    end
end

function PlayerPosition:ApplyRangeSpellPanelLayer(panel, anchor)
    if not panel then return end

    local baseLevel = 100
    local function IncludeLevel(frame)
        local frameType = type(frame)
        if (frameType == "table" or frameType == "userdata") and frame.GetFrameLevel then
            local ok, level = pcall(frame.GetFrameLevel, frame)
            level = ok and tonumber(level) or nil
            if level and level > baseLevel then
                baseLevel = level
            end
        end
    end

    local elements = YUI.Settings and YUI.Settings.Elements
    if type(elements) == "table" then
        for _, frame in pairs(elements) do
            IncludeLevel(frame)
        end
    end

    local current = anchor
    local depth = 0
    while current and depth < 12 do
        IncludeLevel(current)
        current = current.GetParent and current:GetParent() or nil
        depth = depth + 1
    end

    local panelLevel = baseLevel + 20
    if panelLevel > 120 then
        panelLevel = 120
    end

    if panel.SetFrameStrata then panel:SetFrameStrata("FULLSCREEN_DIALOG") end
    if panel.SetFrameLevel then panel:SetFrameLevel(panelLevel) end
    if panel.blocker then
        if panel.blocker.SetFrameStrata then panel.blocker:SetFrameStrata("FULLSCREEN_DIALOG") end
        if panel.blocker.SetFrameLevel then panel.blocker:SetFrameLevel(panelLevel - 1) end
    end
end

function PlayerPosition.CommitRangeSpellPanelEdits()
    local panel = rangeSpellPanel
    local edits = panel and panel.rangeSpellEdits
    if type(edits) ~= "table" then
        return
    end
    for _, editbox in ipairs(edits) do
        if editbox and editbox.CommitRangeSpellValue then
            editbox.CommitRangeSpellValue()
        end
    end
end

CloseRangeSpellPanel = function(owner)
    if owner ~= nil and rangeSpellPanelOwner ~= owner then
        return false
    end

    local panel = rangeSpellPanel
    if panel then
        PlayerPosition.CommitRangeSpellPanelEdits()
        panel:SetScript("OnUpdate", nil)
        if panel.blocker then panel.blocker:Hide() end
        if panel.content then
            ClearRangeSpellContent(panel.content)
        end
        panel.rangeSpellEdits = nil
        panel:Hide()
    end
    PlayerPosition:ReleaseRangeSpellNameCache()
    if rangeSpellPanelAnchor and rangeSpellPanelAnchor.arrow and GUI2 and GUI2.SetDropdownGlyphColor then
        GUI2:SetDropdownGlyphColor(rangeSpellPanelAnchor.arrow, "color.accent.primary")
    end
    rangeSpellPanelOwner = nil
    rangeSpellPanelAnchor = nil
    return true
end

function PlayerPosition:RefreshRangeSpellNameCacheStatus(panel)
    if not panel then return nil end

    local spell = GetRangeSpellAPI()
    local status
    if spell and spell.GetNameCacheStatus then
        local ok, value = pcall(spell.GetNameCacheStatus)
        status = ok and value or nil
    end

    local progress = status and status.progress or 0
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end

    local text
    if not status or status.available == false then
        text = T("settings.player_position_spell_cache_waiting", "技能索引：等待设置数据库。")
    elseif status.error == "cache-overflow-guard" then
        text = string.format(T("settings.player_position_spell_cache_guard_format", "技能索引保护停止：%d 个名称，%d 条记录"), status.nameCount or 0, status.recordCount or 0)
    elseif status.complete then
        text = string.format(T("settings.player_position_spell_cache_ready_format", "技能索引已就绪：%d 个名称"), status.nameCount or 0)
    elseif status.paused then
        text = string.format(T("settings.player_position_spell_cache_paused_format", "技能索引暂停：战斗中（ID %d，%d 个名称）"), status.currentID or 0, status.nameCount or 0)
    elseif status.building then
        text = string.format(T("settings.player_position_spell_cache_building_format", "正在建立技能索引：%d%%（ID %d，%d 个名称）"), math.floor(progress * 100 + 0.5), status.currentID or 0, status.nameCount or 0)
    else
        text = T("settings.player_position_spell_cache_waiting", "技能索引：等待启动。")
    end

    if panel.cacheStatusText then
        if panel.cacheStatusText.SetShown then
            panel.cacheStatusText:SetShown(not (status and status.complete == true))
        end
        panel.cacheStatusText:SetText(text)
    end
    if panel.cacheProgressBar and panel.cacheProgressBar.SetValue then
        if panel.cacheProgressBar.SetShown then
            panel.cacheProgressBar:SetShown(not (status and status.complete == true))
        end
        if not (status and status.complete == true) then
            panel.cacheProgressBar:SetValue(progress, true)
        end
    end

    return status
end

local function EnsureRangeSpellPanel()
    if rangeSpellPanel then
        return rangeSpellPanel
    end
    if not (GUI2 and GUI2.CreatePanel and GUI2.CreateFrame and GUI2.CreateText and GUI2.CreateScrollFrame and GUI2.Form and GUI2.Form.CreateButton and UIParent) then
        return nil
    end

    local panel = GUI2:CreatePanel(UIParent, {
        name = "YUI_CombatEnhancement_PlayerPositionRangeSpellPanel",
        width = RANGE_SPELL_PANEL_WIDTH,
        height = RANGE_SPELL_PANEL_HEIGHT,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(120)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()

    local blocker = GUI2:CreateFrame(UIParent, {
        type = "Button",
        frameStrata = "FULLSCREEN_DIALOG",
        frameLevel = 119,
        allPoints = true,
        mouse = true,
        hidden = true,
    })
    blocker:SetScript("OnClick", function()
        CloseRangeSpellPanel()
    end)
    panel.blocker = blocker

    local title = GUI2:CreateText(panel, "", "font.size.md", "color.text.heading")
    title:SetPoint("TOPLEFT", RANGE_SPELL_PANEL_INSET, -10)
    title:SetPoint("TOPRIGHT", -RANGE_SPELL_PANEL_INSET - 104, -10)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    panel.title = title

    local clearAllButton = GUI2.Form:CreateButton(panel, {
        text = T("settings.player_position_clear_all_spell_ids", "清空全部"),
        width = 96,
        height = RANGE_SPELL_TOP_ACTION_HEIGHT,
        onClick = function(self)
            if self.rangeSpellClearHandler then
                self.rangeSpellClearHandler()
            end
        end,
    })
    clearAllButton:SetPoint("TOPRIGHT", -RANGE_SPELL_PANEL_INSET - 22, -8)
    panel.clearAllButton = clearAllButton

    local cacheStatusText = GUI2:CreateText(panel, "", "font.size.sm", "color.text.secondary")
    cacheStatusText:SetPoint("TOPLEFT", RANGE_SPELL_PANEL_INSET, -32)
    cacheStatusText:SetPoint("TOPRIGHT", -RANGE_SPELL_PANEL_INSET - 22, -32)
    cacheStatusText:SetJustifyH("LEFT")
    cacheStatusText:SetWordWrap(false)
    panel.cacheStatusText = cacheStatusText

    if GUI2.Data and GUI2.Data.CreateProgressBar then
        local cacheProgressBar = GUI2.Data:CreateProgressBar(panel, {
            width = RANGE_SPELL_PANEL_WIDTH - RANGE_SPELL_PANEL_INSET * 2 - 22,
            height = 8,
            value = 0,
        })
        cacheProgressBar:SetPoint("TOPLEFT", RANGE_SPELL_PANEL_INSET, -52)
        panel.cacheProgressBar = cacheProgressBar
    end

    local scroll = GUI2:CreateScrollFrame(panel, {
        template = "UIPanelScrollFrameTemplate",
    })
    scroll:SetPoint("TOPLEFT", RANGE_SPELL_PANEL_INSET, -66)
    scroll:SetPoint("BOTTOMRIGHT", -RANGE_SPELL_PANEL_INSET, RANGE_SPELL_PANEL_INSET)
    panel.scrollFrame = scroll
    panel.content = scroll.child

    panel:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        PlayerPosition:ReleaseRangeSpellNameCache()
        if self.blocker then self.blocker:Hide() end
    end)

    rangeSpellPanel = panel
    return panel
end

local function GetRangeSpellClassColor(classInfo)
    if not classInfo then return 1, 1, 1, 1 end
    local api = UnitAPI or (YUI.API and YUI.API.Unit) or YUI.WOW_API
    local color = api and api.GetClassColor and api.GetClassColor(classInfo.token)
    if color then
        return color.r or 1, color.g or 1, color.b or 1, 1
    elseif RAID_CLASS_COLORS and RAID_CLASS_COLORS[classInfo.token] then
        local fallback = RAID_CLASS_COLORS[classInfo.token]
        return fallback.r or 1, fallback.g or 1, fallback.b or 1, 1
    end
    return 1, 1, 1, 1
end

local function ApplyRangeSpellSpecIcon(iconSlot, spec)
    if not (iconSlot and spec) then return end
    if spec.iconTexCoord and iconSlot.icon and iconSlot.icon.SetTexCoord then
        iconSlot.icon:SetTexCoord(unpack(spec.iconTexCoord))
    end
    if spec.specID and Icons and Icons.GetScopedSpecIcon and Icons.ApplyIcon then
        local iconData = Icons.GetScopedSpecIcon(spec.specID, spec.icon, ICON_SCOPE_ID)
        if iconData then
            local texture = iconSlot.icon or iconSlot
            Icons.ApplyIcon(texture, iconData)
            if iconData.kind == "spec" and iconData.custom ~= true and not iconData.atlas and Icons.GetNativeSpecTexCoord then
                texture:SetTexCoord(unpack(Icons.GetNativeSpecTexCoord()))
            end
        end
    end
end

local function GetRangeSpellSpecTooltipText(spec)
    if not spec then return "" end
    local specName = GetRangeSpellSpecDisplayName(spec)
    local classInfo = spec.classInfo
    local className = classInfo and YUI.Locale and YUI.Locale.GetClassName
        and YUI.Locale:GetClassName(
            classInfo.classFile or classInfo.token,
            classInfo.className or classInfo.name
        ) or classInfo and (classInfo.className or classInfo.name) or ""
    if className and className ~= "" then
        return className .. " - " .. (specName or "")
    end
    return specName or ""
end

local function AttachRangeSpellSpecTooltip(frame, spec)
    if not (frame and frame.SetScript and GameTooltip) then return end
    if frame.EnableMouse then frame:EnableMouse(true) end
    frame:SetScript("OnEnter", function(self)
        local text = GetRangeSpellSpecTooltipText(spec)
        if text == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, GetRangeSpellClassColor(spec and spec.classInfo))
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        if YUI.HideGameTooltip then
            YUI.HideGameTooltip()
        else
            GameTooltip:Hide()
        end
    end)
end

local function RenderRangeSpellCell(parent, x, y, width, spec, db, refresh)
    local frame = GUI2:CreateFrame(parent, {
        width = width,
        height = RANGE_SPELL_CELL_HEIGHT,
    })
    frame:SetPoint("TOPLEFT", x, y)

    local icon = GUI2:CreateIconSlot(frame, {
        size = RANGE_SPELL_ICON_SIZE,
        icon = (spec and spec.icon) or SPEC_DEFAULT_ICON,
        texCoords = spec and spec.iconTexCoord,
        shape = "square",
        variant = "bare",
        padding = 0,
    })
    icon:SetPoint("LEFT", frame, "LEFT", RANGE_SPELL_CELL_INSET_X, 0)
    ApplyRangeSpellSpecIcon(icon, spec)
    AttachRangeSpellSpecTooltip(icon, spec)

    local editWidth = GetRangeSpellEditWidth()
    local editbox = GUI2.Form:CreateEditBox(frame, {
        width = editWidth,
        height = RANGE_SPELL_EDIT_HEIGHT,
        autoFocus = false,
    })
    editbox:SetPoint("LEFT", icon, "RIGHT", RANGE_SPELL_ICON_EDIT_GAP, 0)

    local key = spec and spec.key
    ConfigureRangeSpellEdit(
        editbox,
        function()
            local values = type(db.playerPositionRangeSpellIDs) == "table" and db.playerPositionRangeSpellIDs or {}
            return values[key]
        end,
        function(value)
            if not key then return end
            db.playerPositionRangeSpellIDs = NormalizeRangeSpellIDMap(db.playerPositionRangeSpellIDs)
            if value then
                db.playerPositionRangeSpellIDs[key] = value
            else
                db.playerPositionRangeSpellIDs[key] = nil
            end
            UpdateRuntimeState(db)
        end,
        refresh
    )

    return frame, editbox
end

local function RenderRangeSpellPanel(anchor, db, groups)
    local panel = EnsureRangeSpellPanel()
    if not panel then return end
    if YUI.Settings and YUI.Settings.SyncOwnedWindowScale then
        YUI.Settings:SyncOwnedWindowScale(panel, anchor)
    end

    db = GetDB(db)
    groups = groups or GetRangeSpellSpecGroups()
    panel:SetSize(RANGE_SPELL_PANEL_WIDTH, RANGE_SPELL_PANEL_HEIGHT)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    PlayerPosition:ApplyRangeSpellPanelLayer(panel, anchor)
    if panel.title then
        panel.title:SetText(T("settings.player_position_range_spell_ids_title", "技能 ID"))
    end
    if panel.blocker then
        panel.blocker:Show()
    end
    if panel.content then
        ClearRangeSpellContent(panel.content)
    end

    local content = panel.content
    if not content then return end
    local cacheStatus = PlayerPosition:AcquireRangeSpellNameCache()

    local innerWidth = RANGE_SPELL_PANEL_WIDTH - RANGE_SPELL_PANEL_INSET * 2 - 22
    local cellWidth = math.floor((innerWidth - (RANGE_SPELL_GRID_COLUMNS - 1) * RANGE_SPELL_PANEL_GAP) / RANGE_SPELL_GRID_COLUMNS)
    local visibleGridWidth = (RANGE_SPELL_GRID_COLUMNS - 1) * (cellWidth + RANGE_SPELL_PANEL_GAP)
        + RANGE_SPELL_ICON_SIZE + RANGE_SPELL_ICON_EDIT_GAP + GetRangeSpellEditWidth()
    if visibleGridWidth > innerWidth then
        visibleGridWidth = innerWidth
    end
    cacheStatus = cacheStatus or (PlayerPosition.RefreshRangeSpellNameCacheStatus and PlayerPosition:RefreshRangeSpellNameCacheStatus(panel))
    local cacheStatusVisible = not (cacheStatus and cacheStatus.complete == true)
    local contentY = 0
    local renderedEdits = {}
    local RefreshAll

    if panel.clearAllButton then
        panel.clearAllButton:ClearAllPoints()
        panel.clearAllButton:SetPoint("TOPLEFT", panel, "TOPLEFT", RANGE_SPELL_PANEL_INSET + visibleGridWidth - 96, -8)
        panel.clearAllButton.rangeSpellClearHandler = function()
            db.playerPositionRangeSpellIDs = {}
            UpdateRuntimeState(db)
            if RefreshAll then RefreshAll() end
        end
    end
    if panel.cacheStatusText then
        panel.cacheStatusText:ClearAllPoints()
        panel.cacheStatusText:SetPoint("TOPLEFT", RANGE_SPELL_PANEL_INSET, -32)
        panel.cacheStatusText:SetWidth(visibleGridWidth)
    end
    if panel.cacheProgressBar then
        panel.cacheProgressBar:ClearAllPoints()
        if panel.cacheProgressBar.SetBarSize then
            panel.cacheProgressBar:SetBarSize(visibleGridWidth, 8)
        else
            panel.cacheProgressBar:SetSize(visibleGridWidth, 8)
        end
        panel.cacheProgressBar:SetPoint("TOPLEFT", RANGE_SPELL_PANEL_INSET, -52)
    end
    if panel.scrollFrame then
        panel.scrollFrame:ClearAllPoints()
        panel.scrollFrame:SetPoint("TOPLEFT", RANGE_SPELL_PANEL_INSET, cacheStatusVisible and -66 or -38)
        panel.scrollFrame:SetPoint("BOTTOMRIGHT", -RANGE_SPELL_PANEL_INSET, RANGE_SPELL_PANEL_INSET)
    end

    local specs = {}
    for _, group in ipairs(groups or {}) do
        for _, spec in ipairs(group.specs or {}) do
            specs[#specs + 1] = spec
        end
    end

    if #specs > 0 then
        for index, spec in ipairs(specs) do
            local col = (index - 1) % RANGE_SPELL_GRID_COLUMNS
            local row = math.floor((index - 1) / RANGE_SPELL_GRID_COLUMNS)
            local x = col * (cellWidth + RANGE_SPELL_PANEL_GAP)
            local y = contentY - row * (RANGE_SPELL_CELL_HEIGHT + RANGE_SPELL_PANEL_GAP)
            local _, edit = RenderRangeSpellCell(content, x, y, cellWidth, spec, db, function()
                if RefreshAll then RefreshAll() end
            end)
            if edit then
                renderedEdits[#renderedEdits + 1] = edit
            end
        end

        local rows = math.max(math.ceil(#specs / RANGE_SPELL_GRID_COLUMNS), 1)
        contentY = contentY - rows * (RANGE_SPELL_CELL_HEIGHT + RANGE_SPELL_PANEL_GAP)
    else
        local empty = GUI2:CreateText(content, T("settings.player_position_range_spell_ids_empty", "暂无可配置专精。"), "font.size.md", "color.text.secondary")
        empty:SetPoint("TOPLEFT", 0, contentY)
        empty:SetWidth(innerWidth)
        empty:SetJustifyH("LEFT")
        empty:SetWordWrap(true)
        contentY = contentY - 36
    end

    RefreshAll = function()
        db.playerPositionRangeSpellIDs = NormalizeRangeSpellIDMap(db.playerPositionRangeSpellIDs)
        if anchor.Refresh then
            anchor:Refresh()
        end
        for _, edit in ipairs(renderedEdits) do
            if edit.RefreshRangeSpellDisplay then
                edit:RefreshRangeSpellDisplay()
            end
        end
    end

    panel.rangeSpellEdits = renderedEdits
    content:SetSize(innerWidth, math.max(math.abs(contentY) + 12, RANGE_SPELL_PANEL_HEIGHT - (cacheStatusVisible and 82 or 54)))
    if panel.scrollFrame and panel.scrollFrame.SetVerticalScroll then
        panel.scrollFrame:SetVerticalScroll(0)
    end

    rangeSpellPanelOwner = anchor
    rangeSpellPanelAnchor = anchor
    if cacheStatus and (cacheStatus.complete or cacheStatus.error) then
        panel:SetScript("OnUpdate", nil)
    else
        panel.cacheStatusElapsed = 1
        panel:SetScript("OnUpdate", function(self, elapsed)
            self.cacheStatusElapsed = (self.cacheStatusElapsed or 0) + (elapsed or 0)
            if self.cacheStatusElapsed >= 0.15 then
                self.cacheStatusElapsed = 0
                local status = PlayerPosition.RefreshRangeSpellNameCacheStatus and PlayerPosition:RefreshRangeSpellNameCacheStatus(self)
                if status and status.complete then
                    if self.cacheStatusText and self.cacheStatusText.SetShown then
                        self.cacheStatusText:SetShown(false)
                    end
                    if self.cacheProgressBar and self.cacheProgressBar.SetShown then
                        self.cacheProgressBar:SetShown(false)
                    end
                    if self.scrollFrame then
                        self.scrollFrame:ClearAllPoints()
                        self.scrollFrame:SetPoint("TOPLEFT", RANGE_SPELL_PANEL_INSET, -38)
                        self.scrollFrame:SetPoint("BOTTOMRIGHT", -RANGE_SPELL_PANEL_INSET, RANGE_SPELL_PANEL_INSET)
                    end
                    self:SetScript("OnUpdate", nil)
                elseif status and status.error then
                    self:SetScript("OnUpdate", nil)
                end
            end
        end)
    end
    panel:Show()
    if anchor.arrow and GUI2 and GUI2.SetDropdownGlyphColor then
        GUI2:SetDropdownGlyphColor(anchor.arrow, "color.text.accent")
    end
    RefreshAll()
end

function PlayerPosition.GetRangeSpellStateStatusText(state)
    local reason = state and state.reason
    if reason == "unset" then
        return T("settings.player_position_range_spell_current_unset", "当前专精未设置技能 ID")
    elseif reason == "no-spec" then
        return T("settings.player_position_range_spell_no_spec", "当前专精不可用")
    elseif reason == "disabled" then
        return T("settings.player_position_range_spell_disabled", "距离变色未启用")
    elseif reason == "no-target" then
        return T("settings.player_position_range_spell_no_target", "当前无目标")
    elseif reason == "no-range" then
        return T("settings.player_position_range_spell_no_range", "该技能不能检查射程")
    elseif reason == "range-unavailable" then
        if state and not state.spellName and not state.icon then
            return T("settings.player_position_range_spell_invalid_or_unavailable", "技能 ID 无效或射程检查暂不可用")
        end
        return T("settings.player_position_range_spell_range_unavailable", "射程检查暂不可用")
    elseif reason == "in-range" or reason == "out-of-range" then
        return T("settings.player_position_range_spell_range_ready", "射程检查可用")
    end
    return T("settings.player_position_range_spell_unknown_status", "当前状态未知")
end

function PlayerPosition.GetRangeSpellStateBorderKey(state)
    local reason = state and state.reason
    if reason == "in-range" then
        return "color.state.success"
    elseif reason == "out-of-range" or reason == "no-target" then
        return "color.state.warning"
    elseif reason == "range-unavailable" then
        if state and not state.spellName and not state.icon then
            return "color.state.error"
        end
        return "color.state.warning"
    elseif reason == "no-range" then
        return "color.state.error"
    end
    return "color.border.default"
end

function PlayerPosition.EnsureRangeSpellDropdownDisplay(button)
    if not (button and GUI2) then return end
    if not button.rangeSpellIcon and GUI2.CreateIcon then
        button.rangeSpellIcon = GUI2:CreateIcon(button, {
            icon = SPEC_DEFAULT_ICON,
            fallbackIcon = SPEC_DEFAULT_ICON,
            size = RANGE_SPELL_DISPLAY_ICON_SIZE,
            allowTiny = true,
        })
    end
    if button.rangeSpellIcon then
        button.rangeSpellIcon:ClearAllPoints()
        button.rangeSpellIcon:SetPoint("LEFT", 8, 0)
    end
    if button.text then
        button.text:ClearAllPoints()
        if button.rangeSpellIcon then
            button.text:SetPoint("LEFT", button.rangeSpellIcon, "RIGHT", 6, 0)
        else
            button.text:SetPoint("LEFT", 8, 0)
        end
        button.text:SetPoint("RIGHT", -24, 0)
        button.text:SetJustifyH("LEFT")
    end
end

function PlayerPosition.RefreshRangeSpellDropdownDisplay(button, db, groups)
    if not button then return end
    PlayerPosition.EnsureRangeSpellDropdownDisplay(button)
    db = GetDB(db)
    db.playerPositionRangeSpellIDs = NormalizeRangeSpellIDMap(db.playerPositionRangeSpellIDs)

    local state = PlayerPosition.ResolveCurrentRangeSpell(db, "target", PlayerPosition.rangeSpellStateScratch)
    local configured, total = CountRangeSpellIDs(groups, db.playerPositionRangeSpellIDs)
    local icon = state.icon or SPEC_DEFAULT_ICON
    local hasSpellID = state.spellID ~= nil

    if button.rangeSpellIcon then
        if GUI2 and GUI2.SetIconTexture then
            GUI2:SetIconTexture(button.rangeSpellIcon, icon, SPEC_DEFAULT_ICON)
        else
            button.rangeSpellIcon:SetTexture(icon)
        end
        if button.rangeSpellIcon.SetDesaturated then
            button.rangeSpellIcon:SetDesaturated(not hasSpellID or state.reason == "no-range" or state.reason == "range-unavailable")
        end
        button.rangeSpellIcon:SetAlpha(hasSpellID and 1 or 0.65)
    end
    if button.text then
        button.text:SetText(hasSpellID and tostring(state.spellID) or "")
        if GUI2 and GUI2.SetTextColorKey then
            GUI2:SetTextColorKey(button.text, hasSpellID and "color.text.primary" or "color.text.muted")
        end
    end

    button.rangeSpellBorderKey = PlayerPosition.GetRangeSpellStateBorderKey(state)
    if button.bg and GUI2 and GUI2.SetBorderColor then
        GUI2:SetBorderColor(button.bg, button.rangeSpellBorderKey)
    end

    if hasSpellID then
        local spellName = state.spellName or T("settings.player_position_range_spell_unknown_spell", "未知技能")
        button.rangeSpellTooltipTitle = spellName .. "  ID: " .. tostring(state.spellID)
    else
        button.rangeSpellTooltipTitle = T("settings.player_position_range_spell_current_unset", "当前专精未设置技能 ID")
    end
    button.rangeSpellTooltipStatus = PlayerPosition.GetRangeSpellStateStatusText(state)
    button.rangeSpellTooltipSummary = FormatRangeSpellIDsSummary(configured, total)
end

function PlayerPosition.ShowRangeSpellDropdownTooltip(button)
    if not (button and GameTooltip) then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(button.rangeSpellTooltipTitle or T("settings.player_position_range_spell_ids_title", "技能 ID"), 1, 0.82, 0, true)
    if button.rangeSpellTooltipStatus then
        GameTooltip:AddLine(button.rangeSpellTooltipStatus, 0.82, 0.87, 0.94, true)
    end
    if button.rangeSpellTooltipSummary then
        GameTooltip:AddLine(button.rangeSpellTooltipSummary, 0.65, 0.70, 0.78, true)
    end
    GameTooltip:Show()
end

function PlayerPosition.HideRangeSpellDropdownTooltip()
    if GameTooltip then
        if YUI.HideGameTooltip then
            YUI.HideGameTooltip()
        else
            GameTooltip:Hide()
        end
    end
end

local function RenderRangeSpellDropdown(parent, controlItem, bodyWidth)
    if not (GUI2 and GUI2.CreateButtonFrame and GUI2.SkinDropdownButton and GUI2.Form) then
        return GUI2 and GUI2.CreateFrame and GUI2:CreateFrame(parent, { width = bodyWidth, height = 1 }) or nil
    end

    local db = controlItem and controlItem.db or nil
    db = GetDB(db)
    local width = bodyWidth or BODY_WIDTH
    local height = 26
    local button = GUI2:CreateButtonFrame(parent, { template = "BackdropTemplate", width = width, height = height })
    button.width = width
    button.height = height
    GUI2:SkinDropdownButton(button)
    PlayerPosition.EnsureRangeSpellDropdownDisplay(button)

    local groups = GetRangeSpellSpecGroups()

    function button:Refresh()
        groups = GetRangeSpellSpecGroups()
        PlayerPosition.RefreshRangeSpellDropdownDisplay(self, db, groups)
    end

    button:SetScript("OnEnter", function(self)
        if self.bg and GUI2 and GUI2.SetBorderColor then
            GUI2:SetBorderColor(self.bg, "color.border.accent")
        end
        if self.arrow and GUI2 and GUI2.SetDropdownGlyphColor then
            GUI2:SetDropdownGlyphColor(self.arrow, "color.text.accent")
        end
        PlayerPosition.ShowRangeSpellDropdownTooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        if self.bg and GUI2 and GUI2.SetBorderColor then
            GUI2:SetBorderColor(self.bg, self.rangeSpellBorderKey or "color.border.default")
        end
        if self.arrow and GUI2 and GUI2.SetDropdownGlyphColor then
            local open = rangeSpellPanel and rangeSpellPanel:IsShown() and rangeSpellPanelOwner == self
            GUI2:SetDropdownGlyphColor(self.arrow, open and "color.text.accent" or "color.accent.primary")
        end
        PlayerPosition.HideRangeSpellDropdownTooltip()
    end)

    button:SetScript("OnMouseUp", function(self)
        if self.gui2Disabled then return end
        if rangeSpellPanel and rangeSpellPanel:IsShown() and rangeSpellPanelOwner == self then
            CloseRangeSpellPanel(self)
            return
        end
        self:Refresh()
        RenderRangeSpellPanel(self, db, groups)
    end)
    button:SetScript("OnHide", function(self)
        CloseRangeSpellPanel(self)
    end)

    button:Refresh()
    return button
end

function PlayerPosition:BuildOptions(db)
    db = GetDB(db)
    local options = {}

    AddAlignedFieldRow(options, {
        {
            type = "checkbox",
            label = T("settings.enable_player_position", "启用玩家定位"),
            get = function() return db.playerPositionEnabled end,
            settingsToggle = "playerPosition",
            searchKey = "settings.enable_player_position",
            set = function(value)
                db.playerPositionEnabled = value == true
                PlayerPosition:RefreshRuntime(db)
            end,
        },
    })

    AddAlignedFieldGroup(options, T("settings.player_position_visual", "视觉"), {
        {
            type = "dropdown",
            label = T("settings.player_position_texture", "材质"),
            layoutPreset = "inlineSelector",
            options = BuildTextureOptions(),
            default = ResolveDefaultTextureKey(),
            get = function() return db.playerPositionTexture end,
            set = function(value)
                db.playerPositionTexture = NormalizeTextureKey(value)
                activeTextureKey = nil
                PlayerPosition:RefreshRuntime(db)
                PlayerPosition:RefreshSettingsPreview(db)
            end,
        },
        {
            type = "color",
            label = T("settings.player_position_color", "颜色"),
            layoutPreset = "compactColor",
            default = DEFAULT_COLOR,
            hasAlpha = true,
            get = function() return db.playerPositionColor end,
            set = function(value)
                db.playerPositionColor = NormalizeColorValue(value)
                ApplyTexture(db)
                UpdateRuntimeState(db)
                PlayerPosition:RefreshSettingsPreview(db)
            end,
        },
        {
            type = "slider",
            label = T("settings.player_position_size", "尺寸"),
            min = MIN_SIZE,
            max = MAX_SIZE,
            step = 1,
            get = function() return db.playerPositionSize end,
            set = function(value)
                db.playerPositionSize = ClampNumber(value, MIN_SIZE, MAX_SIZE, DEFAULT_SIZE)
                ApplySize(db)
                PlayerPosition:RefreshSettingsPreview(db)
            end,
        },
        {
            type = "slider",
            label = T("settings.player_position_rotation_speed", "旋转速度"),
            min = MIN_ROTATION_SPEED,
            max = MAX_ROTATION_SPEED,
            step = 0.1,
            precision = 1,
            get = function() return db.playerPositionRotationSpeed end,
            set = function(value)
                db.playerPositionRotationSpeed = ClampNumber(value, MIN_ROTATION_SPEED, MAX_ROTATION_SPEED, DEFAULT_ROTATION_SPEED)
                UpdateRuntimeState(db)
                PlayerPosition:RefreshSettingsPreview(db)
            end,
        },
    })

    AddAlignedFieldGroup(options, T("settings.player_position_position", "位置"), {
        {
            type = "slider",
            label = T("settings.player_position_offset_x", "X 偏移"),
            min = MIN_OFFSET,
            max = MAX_OFFSET,
            step = 1,
            get = function() return db.playerPositionOffsetX end,
            set = function(value)
                db.playerPositionOffsetX = ClampNumber(value, MIN_OFFSET, MAX_OFFSET, DEFAULT_OFFSET_X)
                ApplyPosition(db)
                PlayerPosition:RefreshSettingsPreview(db)
            end,
        },
        {
            type = "slider",
            label = T("settings.player_position_offset_y", "Y 偏移"),
            min = MIN_OFFSET,
            max = MAX_OFFSET,
            step = 1,
            get = function() return db.playerPositionOffsetY end,
            set = function(value)
                db.playerPositionOffsetY = ClampNumber(value, MIN_OFFSET, MAX_OFFSET, DEFAULT_OFFSET_Y)
                ApplyPosition(db)
                PlayerPosition:RefreshSettingsPreview(db)
            end,
        },
    })

    AddAlignedFieldGroup(options, T("settings.player_position_range", "施法距离"), {
        {
            type = "switch",
            label = T("settings.player_position_range_color_enabled", "距离变色"),
            get = function() return db.playerPositionRangeColorEnabled end,
            set = function(value)
                db.playerPositionRangeColorEnabled = value == true
                UpdateRuntimeState(db)
                PlayerPosition:RefreshRuntime(db)
            end,
        },
        {
            type = "custom",
            label = T("settings.player_position_range_spell_id", "技能 ID"),
            span = "full",
            db = db,
            render = function(parent, controlItem, bodyWidth)
                controlItem.db = db
                return RenderRangeSpellDropdown(parent, controlItem, bodyWidth)
            end,
        },
        {
            type = "color",
            label = T("settings.player_position_in_range_color", "射程内颜色"),
            layoutPreset = "compactColor",
            default = DEFAULT_IN_RANGE_COLOR,
            hasAlpha = true,
            get = function() return db.playerPositionInRangeColor end,
            set = function(value)
                db.playerPositionInRangeColor = NormalizeColorWithDefault(value, DEFAULT_IN_RANGE_COLOR)
                UpdateRuntimeState(db)
            end,
        },
        {
            type = "color",
            label = T("settings.player_position_out_of_range_color", "超出颜色"),
            layoutPreset = "compactColor",
            default = DEFAULT_OUT_OF_RANGE_COLOR,
            hasAlpha = true,
            get = function() return db.playerPositionOutOfRangeColor end,
            set = function(value)
                db.playerPositionOutOfRangeColor = NormalizeColorWithDefault(value, DEFAULT_OUT_OF_RANGE_COLOR)
                UpdateRuntimeState(db)
            end,
        },
    })

    AddAlignedFieldGroup(options, T("settings.player_position_conditions", "生效条件"), {
        {
            type = "dropdown",
            label = T("settings.player_position_visibility_mode", "生效场景"),
            span = "full",
            options = BuildVisibilityOptions(),
            default = DEFAULT_VISIBILITY_MODE,
            get = function() return db.playerPositionVisibilityMode end,
            set = function(value)
                db.playerPositionVisibilityMode = NormalizeVisibilityMode(value)
                PlayerPosition:RefreshRuntime(db)
            end,
        },
        {
            type = "switch",
            label = T("settings.player_position_spec_filter_enabled", "启用专精"),
            get = function() return db.playerPositionSpecFilterEnabled end,
            set = function(value)
                db.playerPositionSpecFilterEnabled = value == true
                PlayerPosition:RefreshRuntime(db)
            end,
        },
        {
            type = "specMultiSelect",
            label = T("settings.player_position_specs", "专精"),
            span = "full",
            owner = PlayerPosition,
            panelTitle = T("settings.player_position_specs", "专精"),
            armorLabels = BuildArmorLabels(),
            summaryFormatter = FormatSpecSummary,
            selectAllText = T("settings.player_position_select_all_specs", "全选"),
            clearText = T("settings.player_position_clear_specs", "清空"),
            defaultSelected = true,
            get = function() return db.playerPositionSpecFilter end,
            set = function(value)
                if type(value) == "table" then
                    db.playerPositionSpecFilter = value
                end
            end,
            onChange = function()
                PlayerPosition:RefreshRuntime(db)
            end,
        },
    })

    return options
end

function PlayerPosition:OnSettingsLeave(db)
    CloseRangeSpellPanel()
    self:ClearSettingsPreview()
    self:RefreshRuntime(db)
end

local function PrintRangeSpellPresetLine(line)
    if YUI.Print then
        YUI:Print(line)
    elseif print then
        print(line)
    end
end

local function FormatRangeSpellPresetEntry(specName, specID, range)
    return string.format("%s(%d)=阈值%d码", specName or tostring(specID), specID or 0, tonumber(range) or 0)
end

local function GetRangePresetClassInfos()
    local api = UnitAPI or (YUI.API and YUI.API.Unit) or YUI.WOW_API
    local classInfos = {}
    local count = api and api.GetNumClasses and api.GetNumClasses() or GetNumClasses and GetNumClasses() or 0
    for index = 1, count do
        local info
        if api and api.GetClassInfo then
            info = api.GetClassInfo(index)
        elseif GetClassInfo then
            local className, classFile, classID = GetClassInfo(index)
            info = { className = className, classFile = classFile, classID = classID }
        end
        if type(info) == "table" then
            classInfos[#classInfos + 1] = info
        end
    end
    return classInfos
end

local function GetRangePresetSpecsForClass(classInfo)
    local talent = YUI.API and YUI.API.Talent or YUI.WOW_API
    if not (talent and (talent.GetClassConfigurationSpecializations or talent.GetClassSpecializations)) then
        return {}
    end

    local ok, specs = pcall((talent.GetClassConfigurationSpecializations or talent.GetClassSpecializations), classInfo)
    if ok and type(specs) == "table" then
        return specs
    end
    return {}
end

local function PrintRangeSpellPresetFallback()
    local specIDs = {}
    for specID in pairs(SPEC_RANGE_BY_ID) do
        specIDs[#specIDs + 1] = specID
    end
    table.sort(specIDs)

    local parts = {}
    for _, specID in ipairs(specIDs) do
        parts[#parts + 1] = FormatRangeSpellPresetEntry(tostring(specID), specID, SPEC_RANGE_BY_ID[specID])
    end

    if #parts > 0 then
        PrintRangeSpellPresetLine("专精：" .. table.concat(parts, "，"))
    end
end

local function PrintRangeSpellPresets()
    local printed = false
    for _, classInfo in ipairs(GetRangePresetClassInfos()) do
        local parts = {}
        for _, specInfo in ipairs(GetRangePresetSpecsForClass(classInfo)) do
            local specID = tonumber(specInfo and specInfo.specID)
            local range = specID and SPEC_RANGE_BY_ID[specID]
            if range then
                parts[#parts + 1] = FormatRangeSpellPresetEntry(specInfo.name, specID, range)
            end
        end
        if #parts > 0 then
            local className = YUI.Locale and YUI.Locale.GetClassName
                and YUI.Locale:GetClassName(
                    classInfo.classFile,
                    classInfo.className or classInfo.name
                )
                or classInfo.className or classInfo.name
                or classInfo.classFile or tostring(classInfo.classID or "")
            PrintRangeSpellPresetLine(className .. "：" .. table.concat(parts, "，"))
            printed = true
        end
    end

    if not printed then
        PrintRangeSpellPresetFallback()
    end
end

local function HandleRangeSpellSlashCommand(msg)
    local text = TrimText(msg):lower()
    if text == "ce range-spells" or text == "combatenhancement range-spells" or text == "combat-enhancement range-spells" then
        PrintRangeSpellPresets()
        return true
    end
    return false
end

local function RegisterRangeSpellSlashCommand()
    if PlayerPosition.rangeSpellSlashRegistered then
        return
    end
    PlayerPosition.rangeSpellSlashRegistered = true

    local previousSlashHandler = YUI.HandleSlashCommand
    function YUI:HandleSlashCommand(msg)
        if HandleRangeSpellSlashCommand(msg) then
            return true
        end
        if previousSlashHandler then
            return previousSlashHandler(self, msg)
        end
        return false
    end
end

RegisterRangeSpellSlashCommand()

CombatEnhancement.PlayerPosition = PlayerPosition
CombatEnhancement:RegisterSubFeature(PlayerPosition)

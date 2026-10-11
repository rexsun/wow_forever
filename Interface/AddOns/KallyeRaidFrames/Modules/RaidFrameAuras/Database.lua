local addonName, ns = ...
local l = ns.I18N;

-- * avoid conflict override
if ns.CONFLICT then return; end

local RaidFrameAuras = ns.RaidFrameAuras
if not RaidFrameAuras then return end

local DEFAULTS = ns.DEFAULTS or {}
local Constants = ns.Constants or {}
local State = ns.State or {}
local Util = ns.Util or {}
local VALID_AURA_FRAME_STRATA = Constants.VALID_AURA_FRAME_STRATA or {}
local VALID_AURA_ANCHOR_TARGETS = Constants.VALID_AURA_ANCHOR_TARGETS or {}
local VALID_AURA_ANCHORS = Constants.ANCHOR_FACTORS or {}
local MAX_PRIVATE_AURA_SLOTS = Constants.MAX_PRIVATE_AURA_SLOTS or 4
local DB_VERSION = ns.DB_VERSION or 1403
local DEFAULT_PROFILE_NAME = "Default"
local IMPORTED_PROFILE_NAME = "Imported"
local PROFILE_NAME_MAX_BYTES = 48
local EXPORT_PREFIX = "RFA_PROFILE"
local EXPORT_VERSION = "1"
local EXPORT_MODE_COMPRESSED_CBOR = "CBORZ"
local EXPORT_MODE_CBOR = "CBOR"

local LAYOUT_ONLY_OPTIONS = {
    masqueEnabled = true,
    previewWidth = true,
    previewHeight = true,
    auraAnchorTarget = true,
    showObjectiveCarriers = true,
    objectiveCarrierSize = true,
    objectiveCarrierAnchor = true,
    objectiveCarrierOffsetX = true,
    objectiveCarrierOffsetY = true,
    buffAutoScale = true,
    buffAutoScaleMinSize = true,
    buffAutoScaleMaxSize = true,
    debuffAutoScale = true,
    debuffAutoScaleMinSize = true,
    debuffAutoScaleMaxSize = true,
    bossDebuffsEnabled = true,
    privateAuraMax = true,
    privateAuraScale = true,
    privateAuraAnchor = true,
    privateAuraGrowth = true,
    privateAuraWrap = true,
    privateAuraOffsetX = true,
    privateAuraOffsetY = true,
}

local PASSIVE_OPTIONS = {
    debugMode = true,
    perfMode = true,
}

local function ClampOption(db, key, minValue, maxValue)
    db[key] = Util.Clamp(db[key], minValue, maxValue, DEFAULTS[key])
end

local function T(text, ...)
    return Util.T and Util.T(text, ...) or text
end

local function TrimString(value)
    value = tostring(value or "")
    if strtrim then
        return strtrim(value)
    end
    return value:match("^%s*(.-)%s*$") or ""
end

local function SanitizeProfileName(name)
    name = TrimString(name)
    name = name:gsub("[%c]", "")
    if name == "" then
        return nil
    end
    if #name > PROFILE_NAME_MAX_BYTES then
        name = name:sub(1, PROFILE_NAME_MAX_BYTES)
    end
    return name
end

local function CopyValue(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in pairs(value) do
        copy[key] = CopyValue(child)
    end
    return copy
end

local function CopyProfileOptions(source, destination)
    destination = destination or {}
    if type(source) ~= "table" then
        return destination, 0
    end

    local copied = 0
    for key in pairs(DEFAULTS) do
        if key ~= "dbVersion" and source[key] ~= nil then
            destination[key] = CopyValue(source[key])
            copied = copied + 1
        end
    end
    destination.dbVersion = tonumber(source.dbVersion) or destination.dbVersion or 0
    return destination, copied
end

local function HasSavedProfileOptions(source)
    if type(source) ~= "table" then
        return false
    end
    for key in pairs(DEFAULTS) do
        if key ~= "dbVersion" and source[key] ~= nil then
            return true
        end
    end
    return false
end

local function BuildExportProfile(source)
    local profile = {}
    for key in pairs(DEFAULTS) do
        if key ~= "dbVersion" then
            if type(source) == "table" and source[key] ~= nil then
                profile[key] = CopyValue(source[key])
            else
                profile[key] = CopyValue(DEFAULTS[key])
            end
        end
    end
    profile.dbVersion = DB_VERSION
    return profile
end

local function SortProfileNames(left, right)
    return tostring(left):lower() < tostring(right):lower()
end

local ClampAutoScaleOptions
local ClampPrivateAuraOptions
local ClampObjectiveCarrierOptions

local VALID_GROWTH_DIRECTIONS = {
    LEFT_UP = true,
    LEFT_DOWN = true,
    RIGHT_UP = true,
    RIGHT_DOWN = true,
    UP_LEFT = true,
    UP_RIGHT = true,
    DOWN_LEFT = true,
    DOWN_RIGHT = true,
    CENTER_UP = true,
    CENTER_DOWN = true,
    CENTER_LEFT = true,
    CENTER_RIGHT = true,
}

local function GetAuraPrefix(auraTypeOrPrefix)
    if auraTypeOrPrefix == "BUFF" or auraTypeOrPrefix == "buff" then
        return "buff"
    elseif auraTypeOrPrefix == "DEBUFF" or auraTypeOrPrefix == "debuff" then
        return "debuff"
    end
    return nil
end

local function IsObjectiveCarrierOption(key)
    return key == "showObjectiveCarriers"
        or key == "objectiveCarrierSize"
        or key == "objectiveCarrierAnchor"
        or key == "objectiveCarrierOffsetX"
        or key == "objectiveCarrierOffsetY"
end

local OBSOLETE_SAVED_VARIABLE_KEYS = {
    buffScale = true,
    debuffScale = true,
    buffBlacklist = true,
    debuffBlacklist = true,
    blacklistBuffs = true,
    blacklistDebuffs = true,
    blacklistedBuffs = true,
    blacklistedDebuffs = true,
    buffBlacklistEnabled = true,
    debuffBlacklistEnabled = true,
    hiddenBuffs = true,
    hiddenDebuffs = true,
    directDebuffFilterRaidHideInCombat = true,
    directBuffHideLongInCombat = true,
    directBuffHideLongInCombatThreshold = true,
    directBuffHideLongThreshold = true,
}

local function RemoveObsoleteKeys(db)
    for key in pairs(OBSOLETE_SAVED_VARIABLE_KEYS) do
        db[key] = nil
    end
end

local LEGACY_PRIVATE_AURA_DEFAULTS = {
    privateAuraMax = 4,
    privateAuraScale = 1,
    privateAuraAnchor = "BOTTOMLEFT",
    privateAuraGrowth = "RIGHT_UP",
    privateAuraWrap = 3,
    privateAuraOffsetX = -17,
    privateAuraOffsetY = -17,
}

local LEGACY_OBJECTIVE_CARRIER_DEFAULTS = {
    objectiveCarrierSize = 22,
    objectiveCarrierAnchor = "CENTER",
    objectiveCarrierOffsetX = 0,
    objectiveCarrierOffsetY = 0,
}

local function HasLegacyPrivateAuraDefaults(db)
    return tonumber(db.privateAuraMax) == LEGACY_PRIVATE_AURA_DEFAULTS.privateAuraMax
        and tonumber(db.privateAuraScale) == LEGACY_PRIVATE_AURA_DEFAULTS.privateAuraScale
        and db.privateAuraAnchor == LEGACY_PRIVATE_AURA_DEFAULTS.privateAuraAnchor
        and db.privateAuraGrowth == LEGACY_PRIVATE_AURA_DEFAULTS.privateAuraGrowth
        and tonumber(db.privateAuraWrap) == LEGACY_PRIVATE_AURA_DEFAULTS.privateAuraWrap
        and tonumber(db.privateAuraOffsetX) == LEGACY_PRIVATE_AURA_DEFAULTS.privateAuraOffsetX
        and tonumber(db.privateAuraOffsetY) == LEGACY_PRIVATE_AURA_DEFAULTS.privateAuraOffsetY
end

local function HasLegacyObjectiveCarrierDefaults(db)
    return tonumber(db.objectiveCarrierSize) == LEGACY_OBJECTIVE_CARRIER_DEFAULTS.objectiveCarrierSize
        and db.objectiveCarrierAnchor == LEGACY_OBJECTIVE_CARRIER_DEFAULTS.objectiveCarrierAnchor
        and tonumber(db.objectiveCarrierOffsetX) == LEGACY_OBJECTIVE_CARRIER_DEFAULTS.objectiveCarrierOffsetX
        and tonumber(db.objectiveCarrierOffsetY) == LEGACY_OBJECTIVE_CARRIER_DEFAULTS.objectiveCarrierOffsetY
end

function RaidFrameAuras:MigrateDatabase(db)
    if type(db) ~= "table" then return end
    local previousVersion = tonumber(db.dbVersion) or 0

    -- Split the old single "Hide long buffs in combat" option into:
    --   Hide long buffs / Only in combat
    -- Preserve existing user intent before deleting the obsolete keys.
    if db.directBuffHideLong == nil and db.directBuffHideLongInCombat ~= nil then
        db.directBuffHideLong = db.directBuffHideLongInCombat == true
    end
    if db.directBuffHideLongOnlyInCombat == nil then
        if db.directBuffHideLongInCombat ~= nil then
            db.directBuffHideLongOnlyInCombat = true
        else
            db.directBuffHideLongOnlyInCombat = DEFAULTS.directBuffHideLongOnlyInCombat == true
        end
    end

    -- DB 1302: encounter debuffs are too important to miss when Blizzard has
    -- not tagged them with one of the narrower raid-frame categories.
    if previousVersion < 1302 then
        db.directDebuffShowAll = true
    end

    -- DB 1303: move untouched boss-debuff overlay profiles to the new defaults.
    if previousVersion < 1303 and HasLegacyPrivateAuraDefaults(db) then
        db.privateAuraMax = DEFAULTS.privateAuraMax
        db.privateAuraScale = DEFAULTS.privateAuraScale
        db.privateAuraAnchor = DEFAULTS.privateAuraAnchor
        db.privateAuraGrowth = DEFAULTS.privateAuraGrowth
        db.privateAuraWrap = DEFAULTS.privateAuraWrap
        db.privateAuraOffsetX = DEFAULTS.privateAuraOffsetX
        db.privateAuraOffsetY = DEFAULTS.privateAuraOffsetY
    end

    -- DB 1402: move untouched battleground objective icons to the buff corner.
    if previousVersion < 1402 and HasLegacyObjectiveCarrierDefaults(db) then
        db.objectiveCarrierSize = DEFAULTS.objectiveCarrierSize
        db.objectiveCarrierAnchor = DEFAULTS.objectiveCarrierAnchor
        db.objectiveCarrierOffsetX = DEFAULTS.objectiveCarrierOffsetX
        db.objectiveCarrierOffsetY = DEFAULTS.objectiveCarrierOffsetY
    end

    -- DB 1403: Masque skinning is opt-in for existing and new profiles.
    if previousVersion < 1403 and db.masqueEnabled == nil then
        db.masqueEnabled = DEFAULTS.masqueEnabled == true
    end

    -- Release cleanup: remove legacy keys and removed combat toggles.
    RemoveObsoleteKeys(db)

    db.dbVersion = DB_VERSION
end

function RaidFrameAuras:NormalizeProfile(profile)
    if type(profile) ~= "table" then return end

    self:MigrateDatabase(profile)
    Util.CopyDefaults(DEFAULTS, profile)
    profile.dbVersion = DB_VERSION

    if not VALID_AURA_FRAME_STRATA[profile.auraFrameStrata] then
        profile.auraFrameStrata = DEFAULTS.auraFrameStrata
    end
    if not VALID_AURA_ANCHOR_TARGETS[profile.auraAnchorTarget] then
        profile.auraAnchorTarget = DEFAULTS.auraAnchorTarget
    end
    ClampOption(profile, "previewWidth", Constants.PREVIEW_WIDTH_MIN or 72, Constants.PREVIEW_WIDTH_MAX or 144)
    ClampOption(profile, "previewHeight", Constants.PREVIEW_HEIGHT_MIN or 36, Constants.PREVIEW_HEIGHT_MAX or 72)
    ClampOption(profile, "thresholdExpiringSoon", 1, 60)
    ClampOption(profile, "thresholdShortDuration", 5, 300)
    ClampOption(profile, "thresholdLongDuration", 60, 3600)
    ClampOption(profile, "thresholdTransitionOffset", -2, 2)
    ClampPrivateAuraOptions(profile)
    ClampObjectiveCarrierOptions(profile)
    ClampAutoScaleOptions(profile, "buff")
    ClampAutoScaleOptions(profile, "debuff")
    profile.masqueEnabled = profile.masqueEnabled == true
end

local function GetFirstProfileName(profiles)
    local names = {}
    for name in pairs(profiles or {}) do
        names[#names + 1] = name
    end
    table.sort(names, SortProfileNames)
    return names[1]
end

local function MakeUniqueProfileName(profiles, baseName)
    baseName = SanitizeProfileName(baseName) or IMPORTED_PROFILE_NAME
    if not profiles[baseName] then
        return baseName
    end

    local index = 2
    while true do
        local suffix = " " .. tostring(index)
        local maxBaseBytes = PROFILE_NAME_MAX_BYTES - #suffix
        local candidateBase = baseName
        if #candidateBase > maxBaseBytes then
            candidateBase = candidateBase:sub(1, maxBaseBytes)
        end
        local candidate = candidateBase .. suffix
        if not profiles[candidate] then
            return candidate
        end
        index = index + 1
    end
end

function RaidFrameAuras:SyncActiveProfileToRoot()
    local root = self.dbRoot
    local profile = self.db
    if type(root) ~= "table" or type(profile) ~= "table" then return end

    for key in pairs(DEFAULTS) do
        root[key] = CopyValue(profile[key])
    end
    root.dbVersion = DB_VERSION
    root.activeProfile = self.activeProfileName or root.activeProfile or DEFAULT_PROFILE_NAME
end

function RaidFrameAuras:EnsureProfileDatabase(root)
    if type(root) ~= "table" then return end

    self:MigrateDatabase(root)

    -- DB 1400: keep the old flat saved-variable keys mirrored for downgrade
    -- tolerance, but route runtime settings through named profiles.
    local profiles = type(root.profiles) == "table" and root.profiles or nil
    local activeName = SanitizeProfileName(root.activeProfile)

    if not profiles then
        profiles = {}
        local profile = {}
        if HasSavedProfileOptions(root) then
            CopyProfileOptions(root, profile)
        end
        profiles[activeName or DEFAULT_PROFILE_NAME] = profile
        root.profiles = profiles
        activeName = activeName or DEFAULT_PROFILE_NAME
    end

    if not activeName or type(profiles[activeName]) ~= "table" then
        activeName = GetFirstProfileName(profiles) or DEFAULT_PROFILE_NAME
    end
    if type(profiles[activeName]) ~= "table" then
        profiles[activeName] = {}
    end

    for name, profile in pairs(profiles) do
        if type(profile) == "table" then
            self:NormalizeProfile(profile)
        else
            profiles[name] = nil
        end
    end

    if type(profiles[activeName]) ~= "table" then
        activeName = GetFirstProfileName(profiles) or DEFAULT_PROFILE_NAME
        profiles[activeName] = profiles[activeName] or {}
        self:NormalizeProfile(profiles[activeName])
    end

    root.activeProfile = activeName
    root.dbVersion = DB_VERSION
    self.dbRoot = root
    self.activeProfileName = activeName
    self.db = profiles[activeName]
    self:SyncActiveProfileToRoot()
end

ClampAutoScaleOptions = function(db, prefix)
    ClampOption(db, prefix .. "AutoScaleMinSize", 4, 80)
    ClampOption(db, prefix .. "AutoScaleMaxSize", 4, 120)
    if db[prefix .. "AutoScaleMaxSize"] < db[prefix .. "AutoScaleMinSize"] then
        db[prefix .. "AutoScaleMaxSize"] = db[prefix .. "AutoScaleMinSize"]
    end
    db[prefix .. "AutoScale"] = db[prefix .. "AutoScale"] == true
end

ClampPrivateAuraOptions = function(db)
    ClampOption(db, "privateAuraMax", 1, MAX_PRIVATE_AURA_SLOTS)
    ClampOption(db, "privateAuraScale", Constants.CATEGORY_SCALE_MIN or 0.5, Constants.CATEGORY_SCALE_MAX or 2)
    ClampOption(db, "privateAuraWrap", 1, MAX_PRIVATE_AURA_SLOTS)
    db.privateAuraMax = math.floor((tonumber(db.privateAuraMax) or DEFAULTS.privateAuraMax or MAX_PRIVATE_AURA_SLOTS) + 0.5)
    db.privateAuraWrap = math.floor((tonumber(db.privateAuraWrap) or DEFAULTS.privateAuraWrap or 1) + 0.5)
    ClampOption(db, "privateAuraOffsetX", -120, 120)
    ClampOption(db, "privateAuraOffsetY", -120, 120)
    if not VALID_AURA_ANCHORS[db.privateAuraAnchor] then
        db.privateAuraAnchor = DEFAULTS.privateAuraAnchor
    end
    if not VALID_GROWTH_DIRECTIONS[db.privateAuraGrowth] then
        db.privateAuraGrowth = DEFAULTS.privateAuraGrowth
    end
end

ClampObjectiveCarrierOptions = function(db)
    db.showObjectiveCarriers = db.showObjectiveCarriers == true
    ClampOption(db, "objectiveCarrierSize", 8, 80)
    ClampOption(db, "objectiveCarrierOffsetX", -120, 120)
    ClampOption(db, "objectiveCarrierOffsetY", -120, 120)
    if not VALID_AURA_ANCHORS[db.objectiveCarrierAnchor] then
        db.objectiveCarrierAnchor = DEFAULTS.objectiveCarrierAnchor
    end
end

function RaidFrameAuras:InitializeDatabase()
    RaidFrameAurasDB = type(RaidFrameAurasDB) == "table" and RaidFrameAurasDB or {}
    self:EnsureProfileDatabase(RaidFrameAurasDB)
end

function RaidFrameAuras:GetOption(key)
    if self.db and self.db[key] ~= nil then
        return self.db[key]
    end
    return DEFAULTS[key]
end

function RaidFrameAuras:SetOption(key, value)
    if not self.db then self:InitializeDatabase() end
    if key == "auraFrameStrata" and not VALID_AURA_FRAME_STRATA[value] then
        value = DEFAULTS.auraFrameStrata
    elseif key == "auraAnchorTarget" and not VALID_AURA_ANCHOR_TARGETS[value] then
        value = DEFAULTS.auraAnchorTarget
    elseif key == "previewWidth" then
        value = Util.Clamp(value, Constants.PREVIEW_WIDTH_MIN or 72, Constants.PREVIEW_WIDTH_MAX or 144, DEFAULTS.previewWidth)
    elseif key == "previewHeight" then
        value = Util.Clamp(value, Constants.PREVIEW_HEIGHT_MIN or 36, Constants.PREVIEW_HEIGHT_MAX or 72, DEFAULTS.previewHeight)
    elseif key == "thresholdExpiringSoon" then
        value = Util.Clamp(value, 1, 60, DEFAULTS.thresholdExpiringSoon)
    elseif key == "thresholdShortDuration" then
        value = Util.Clamp(value, 5, 300, DEFAULTS.thresholdShortDuration)
    elseif key == "thresholdLongDuration" then
        value = Util.Clamp(value, 60, 3600, DEFAULTS.thresholdLongDuration)
    elseif key == "thresholdTransitionOffset" then
        value = Util.Clamp(value, -2, 2, DEFAULTS.thresholdTransitionOffset)
    elseif key == "directBuffHideLong" or key == "directBuffHideLongOnlyInCombat" or key == "directBuffFilterRaidHideInCombat" or key == "bossDebuffsEnabled" or key == "showObjectiveCarriers" or key == "masqueEnabled" then
        value = value == true
    elseif key == "objectiveCarrierAnchor" then
        if not VALID_AURA_ANCHORS[value] then
            value = DEFAULTS.objectiveCarrierAnchor
        end
    elseif key == "objectiveCarrierSize" then
        value = Util.Clamp(value, 8, 80, DEFAULTS.objectiveCarrierSize)
    elseif key == "objectiveCarrierOffsetX" or key == "objectiveCarrierOffsetY" then
        value = Util.Clamp(value, -120, 120, DEFAULTS[key])
    elseif key == "privateAuraAnchor" then
        if not VALID_AURA_ANCHORS[value] then
            value = DEFAULTS.privateAuraAnchor
        end
    elseif key == "privateAuraGrowth" then
        if not VALID_GROWTH_DIRECTIONS[value] then
            value = DEFAULTS.privateAuraGrowth
        end
    elseif key == "privateAuraMax" then
        value = math.floor(Util.Clamp(value, 1, MAX_PRIVATE_AURA_SLOTS, DEFAULTS.privateAuraMax) + 0.5)
    elseif key == "privateAuraScale" then
        value = Util.Clamp(value, Constants.CATEGORY_SCALE_MIN or 0.5, Constants.CATEGORY_SCALE_MAX or 2, DEFAULTS.privateAuraScale)
    elseif key == "privateAuraWrap" then
        value = math.floor(Util.Clamp(value, 1, MAX_PRIVATE_AURA_SLOTS, DEFAULTS.privateAuraWrap) + 0.5)
    elseif key == "privateAuraOffsetX" or key == "privateAuraOffsetY" then
        value = Util.Clamp(value, -120, 120, DEFAULTS[key])
    elseif key == "buffAutoScaleMinSize" or key == "debuffAutoScaleMinSize" then
        value = Util.Clamp(value, 4, 80, DEFAULTS[key])
    elseif key == "buffAutoScaleMaxSize" or key == "debuffAutoScaleMaxSize" then
        value = Util.Clamp(value, 4, 120, DEFAULTS[key])
    elseif key == "buffAutoScale" or key == "debuffAutoScale" then
        value = value == true
    end
    self.db[key] = value

    local prefix = key and key:match("^(buff)AutoScale") or key and key:match("^(debuff)AutoScale")
    if prefix then
        ClampAutoScaleOptions(self.db, prefix)
    end
    self:SyncActiveProfileToRoot()
    if IsObjectiveCarrierOption(key) and self.MarkObjectiveCarriersDirty then
        self:MarkObjectiveCarriersDirty()
    end
    if key == "masqueEnabled" and self.ApplyMasqueEnabledState then
        self:ApplyMasqueEnabledState()
    end

    if PASSIVE_OPTIONS[key] then
        if self.RefreshOptionControls then self:RefreshOptionControls() end
        return
    end

    self:ApplySettings(not LAYOUT_ONLY_OPTIONS[key])
end

function RaidFrameAuras:SetAuraAutoScaleEnabled(auraTypeOrPrefix, enabled)
    if not self.db then self:InitializeDatabase() end
    local prefix = GetAuraPrefix(auraTypeOrPrefix)
    if not prefix then return end

    self.db[prefix .. "AutoScale"] = enabled == true
    ClampAutoScaleOptions(self.db, prefix)
    self:SyncActiveProfileToRoot()
    self:ApplySettings(false)
end

function RaidFrameAuras:ResetOptions()
    if not self.db then self:InitializeDatabase() end
    wipe(self.db)
    Util.CopyDefaults(DEFAULTS, self.db)
    self.db.dbVersion = DB_VERSION
    self:SyncActiveProfileToRoot()
    if self.ApplyMasqueEnabledState then
        self:ApplyMasqueEnabledState()
    end
    self:ApplySettings(true)
end

local RESET_PROFILE_POPUP = "RFA_RESET_PROFILE_CONFIRM"

function RaidFrameAuras:RequestResetOptions()
    local profileName = self:GetActiveProfileName()

    if StaticPopupDialogs and not StaticPopupDialogs[RESET_PROFILE_POPUP] then
        StaticPopupDialogs[RESET_PROFILE_POPUP] = {
            text = T("Reset profile '%s' to defaults? All settings in this profile will be permanently replaced."),
            button1 = T("Reset"),
            button2 = T("Cancel"),
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function(_, confirmedProfileName)
                if RaidFrameAuras:GetActiveProfileName() ~= confirmedProfileName then
                    return
                end
                RaidFrameAuras:ResetOptions()
                if Util.PrintMessage then
                    Util.PrintMessage(T("Profile reset to defaults: %s.", confirmedProfileName))
                end
            end,
        }
    end

    if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs[RESET_PROFILE_POPUP] then
        StaticPopup_Show(RESET_PROFILE_POPUP, profileName, nil, profileName)
    elseif Util.PrintMessage then
        Util.PrintMessage(T("Could not open the confirmation popup; the profile was not reset."))
    end
end

function RaidFrameAuras:GetActiveProfileName()
    if not self.dbRoot then self:InitializeDatabase() end
    return self.activeProfileName or DEFAULT_PROFILE_NAME
end

function RaidFrameAuras:GetProfileNames()
    if not self.dbRoot then self:InitializeDatabase() end
    local names = {}
    local profiles = self.dbRoot and self.dbRoot.profiles
    for name, profile in pairs(type(profiles) == "table" and profiles or {}) do
        if type(profile) == "table" then
            names[#names + 1] = name
        end
    end
    table.sort(names, SortProfileNames)
    return names
end

function RaidFrameAuras:SetActiveProfile(name)
    if not self.dbRoot then self:InitializeDatabase() end
    name = SanitizeProfileName(name)
    local profiles = self.dbRoot and self.dbRoot.profiles
    if not name or type(profiles) ~= "table" or type(profiles[name]) ~= "table" then
        return false, T("Profile not found.")
    end
    if self.activeProfileName == name then
        return true
    end

    self.activeProfileName = name
    self.dbRoot.activeProfile = name
    self.db = profiles[name]
    self:NormalizeProfile(self.db)
    self:SyncActiveProfileToRoot()
    if self.ApplyMasqueEnabledState then
        self:ApplyMasqueEnabledState()
    end
    self:ApplySettings(true)
    return true, T("Profile switched: %s.", name)
end

function RaidFrameAuras:CreateProfile(name)
    if not self.dbRoot then self:InitializeDatabase() end
    name = SanitizeProfileName(name)
    if not name then
        return false, T("Enter a profile name.")
    end

    local profiles = self.dbRoot.profiles
    if type(profiles) ~= "table" then
        self:EnsureProfileDatabase(self.dbRoot)
        profiles = self.dbRoot.profiles
    end
    if profiles[name] then
        return false, T("Profile already exists.")
    end

    local profile = {}
    CopyProfileOptions(self.db or DEFAULTS, profile)
    self:NormalizeProfile(profile)
    profiles[name] = profile
    self:SetActiveProfile(name)
    return true, T("Profile created: %s.", name)
end

function RaidFrameAuras:DeleteProfile(name)
    if not self.dbRoot then self:InitializeDatabase() end
    name = SanitizeProfileName(name or self.activeProfileName)
    local profiles = self.dbRoot and self.dbRoot.profiles
    if not name or type(profiles) ~= "table" or type(profiles[name]) ~= "table" then
        return false, T("Profile not found.")
    end

    local count = 0
    for _, profile in pairs(profiles) do
        if type(profile) == "table" then
            count = count + 1
        end
    end
    if count <= 1 then
        return false, T("Cannot delete the only profile.")
    end

    profiles[name] = nil
    if self.activeProfileName == name then
        local nextName = GetFirstProfileName(profiles)
        self.activeProfileName = nextName
        self.dbRoot.activeProfile = nextName
        self.db = profiles[nextName]
        self:SyncActiveProfileToRoot()
        self:ApplySettings(true)
    end
    return true, T("Profile deleted: %s.", name)
end

local DELETE_PROFILE_POPUP = "RFA_DELETE_PROFILE_CONFIRM"

function RaidFrameAuras:RequestDeleteProfile(name)
    name = SanitizeProfileName(name or self.activeProfileName)
    if not name then return end

    if StaticPopupDialogs and not StaticPopupDialogs[DELETE_PROFILE_POPUP] then
        StaticPopupDialogs[DELETE_PROFILE_POPUP] = {
            text = T("Delete profile '%s'?"),
            button1 = T("Delete"),
            button2 = T("Cancel"),
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function(_, profileName)
                local ok, message = RaidFrameAuras:DeleteProfile(profileName)
                if message and Util.PrintMessage then
                    Util.PrintMessage(message)
                elseif not ok and Util.PrintMessage then
                    Util.PrintMessage(T("Profile delete failed."))
                end
            end,
        }
    end

    if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs[DELETE_PROFILE_POPUP] then
        StaticPopup_Show(DELETE_PROFILE_POPUP, name, nil, name)
    elseif Util.PrintMessage then
        Util.PrintMessage(T("Could not open the confirmation popup; the profile was not deleted."))
    end
end

function RaidFrameAuras:ExportProfileString(name)
    if not self.dbRoot then self:InitializeDatabase() end
    local profileName = SanitizeProfileName(name or self.activeProfileName) or self.activeProfileName or DEFAULT_PROFILE_NAME
    local profile = self.db
    if self.dbRoot and self.dbRoot.profiles and self.dbRoot.profiles[profileName] then
        profile = self.dbRoot.profiles[profileName]
    end

    if not C_EncodingUtil
        or not C_EncodingUtil.SerializeCBOR
        or not C_EncodingUtil.EncodeBase64 then
        return nil, T("Profile export requires WoW's EncodingUtil API.")
    end

    local payload = {
        addon = addonName,
        format = tonumber(EXPORT_VERSION),
        dbVersion = DB_VERSION,
        name = profileName,
        profile = BuildExportProfile(profile),
    }

    local ok, serialized = pcall(C_EncodingUtil.SerializeCBOR, payload)
    if not ok or type(serialized) ~= "string" then
        return nil, T("Profile export failed.")
    end

    local mode = EXPORT_MODE_CBOR
    local data = serialized
    if C_EncodingUtil.CompressString then
        local compressedOk, compressed = pcall(C_EncodingUtil.CompressString, serialized)
        if compressedOk and type(compressed) == "string" and compressed ~= "" then
            mode = EXPORT_MODE_COMPRESSED_CBOR
            data = compressed
        end
    end

    local encodedOk, encoded = pcall(C_EncodingUtil.EncodeBase64, data)
    if not encodedOk or type(encoded) ~= "string" or encoded == "" then
        return nil, T("Profile export failed.")
    end

    return EXPORT_PREFIX .. ":" .. EXPORT_VERSION .. ":" .. mode .. ":" .. encoded
end

function RaidFrameAuras:ImportProfileString(text, desiredName)
    if not self.dbRoot then self:InitializeDatabase() end

    text = TrimString(text):gsub("%s+", "")
    local version, mode, encoded = text:match("^" .. EXPORT_PREFIX .. ":(%d+):([%w_]+):(.+)$")
    if version ~= EXPORT_VERSION or (mode ~= EXPORT_MODE_COMPRESSED_CBOR and mode ~= EXPORT_MODE_CBOR) then
        if version and version ~= EXPORT_VERSION then
            return false, T("Unsupported profile string version.")
        end
        return false, T("Invalid profile string.")
    end

    if not C_EncodingUtil
        or not C_EncodingUtil.DecodeBase64
        or not C_EncodingUtil.DeserializeCBOR then
        return false, T("Profile import requires WoW's EncodingUtil API.")
    end

    local decodedOk, data = pcall(C_EncodingUtil.DecodeBase64, encoded)
    if not decodedOk or type(data) ~= "string" then
        return false, T("Invalid profile string.")
    end

    if mode == EXPORT_MODE_COMPRESSED_CBOR then
        if not C_EncodingUtil.DecompressString then
            return false, T("Profile import requires WoW's EncodingUtil API.")
        end
        local decompressedOk, decompressed = pcall(C_EncodingUtil.DecompressString, data)
        if not decompressedOk or type(decompressed) ~= "string" then
            return false, T("Invalid profile string.")
        end
        data = decompressed
    end

    local payloadOk, payload = pcall(C_EncodingUtil.DeserializeCBOR, data)
    if not payloadOk or type(payload) ~= "table" then
        return false, T("Invalid profile string.")
    end

    local source = type(payload.profile) == "table" and payload.profile or payload
    local profile = {}
    local _, copied = CopyProfileOptions(source, profile)
    if copied <= 0 then
        return false, T("No profile data found.")
    end

    local profiles = self.dbRoot.profiles
    local importedName = SanitizeProfileName(desiredName) or SanitizeProfileName(payload.name) or IMPORTED_PROFILE_NAME
    local profileName = MakeUniqueProfileName(profiles, importedName)
    self:NormalizeProfile(profile)
    profiles[profileName] = profile
    self:SetActiveProfile(profileName)
    return true, T("Profile imported: %s.", profileName)
end

function RaidFrameAuras:ApplySettings(rebuildData)
    if rebuildData then
        State.layoutVersion = (State.layoutVersion or 0) + 1
        self:InvalidateAuraData()
    end
    self:ScheduleRefreshBurst("settings")
    if self.RefreshOptionControls then self:RefreshOptionControls() end
    if self.RefreshPreview then self:RefreshPreview() end
end

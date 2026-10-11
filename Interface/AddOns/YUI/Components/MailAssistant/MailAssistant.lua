local ADDON_NAME = ...
local YUI = _G.YUI
if not (YUI and YUI.Components and YUI.Locale) then return end

local Components = YUI.Components
local Event = YUI.Event
local GUI2 = YUI.GUI2
local Appearance = GUI2 and GUI2.WindowAppearance
local Settings = YUI.Settings
local API = YUI.API or {}
local Social = API.Social or YUI.WOW_API or {}
local UnitAPI = API.Unit or YUI.WOW_API or {}
local Security = API.Security or YUI.WOW_API or {}
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or (_G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME]
        and _G.YUI_CORE_EMBED_STATE[ADDON_NAME].productId)
    or YUI.ProductId or "suite"
local L = YUI.Locale:Get("MailAssistant")

local FEATURE_KEY = "MailAssistant"
local CONFIG_KEY = "MailAssistant_Config"
local STORE_KEY = "MailAssistant"
local STORE_SCHEMA_VERSION = 3
local PERSONAL_DATA_SCHEMA_VERSION = 2
local MAIL_ADDON = "Blizzard_MailFrame"
local PANEL_LAYOUT_ID = "mailassistant.contacts"
local PAGE_SIZE = 14
local PANEL_WIDTH = 190
local ROW_GAP = 2
local COMPACT_TAB_WIDTH = PANEL_WIDTH - 6
local COMPACT_ROW_WIDTH = PANEL_WIDTH - 16
local INSET_CONTENT_WIDTH = PANEL_WIDTH - 20
local HEADER_BUTTON_SIZE = 16
local HEADER_ICON_SIZE = 14
local PAGER_BUTTON_SIZE = 16
local FOOTER_HEIGHT = 24
local LIST_FOOTER_GAP = 6
local EDITOR_WIDTH = 380
local EDITOR_HEIGHT = 540
local EDITOR_PAGE_SIZE = 8
local RECENT_RECIPIENT_LIMIT = 5

local LAYOUT_COMPACT = "compact"
local LAYOUT_INSET = "inset"
local PANEL_LAYOUTS = {
    [LAYOUT_COMPACT] = {
        tabX = 3, tabY = -28, tabWidth = COMPACT_TAB_WIDTH,
        rowX = 8, rowY = -64, rowWidth = COMPACT_ROW_WIDTH, rowHeight = 22,
        emptyInset = 12, emptyY = -86, footerInset = 8,
    },
    [LAYOUT_INSET] = {
        tabX = 10, tabY = -30, tabWidth = INSET_CONTENT_WIDTH,
        rowX = 10, rowY = -68, rowWidth = INSET_CONTENT_WIDTH, rowHeight = 24,
        emptyInset = 16, emptyY = -90, footerInset = 10,
    },
}

local CATEGORY_ALTS = "alts"
local CATEGORY_FRIENDS = "friends"
local CATEGORY_GUILD = "guild"
local CATEGORY_FAVORITES = "favorites"

local VALID_CATEGORIES = {
    [CATEGORY_ALTS] = true,
    [CATEGORY_FRIENDS] = true,
    [CATEGORY_GUILD] = true,
    [CATEGORY_FAVORITES] = true,
}

local DEFAULTS = {
    defaultCategory = CATEGORY_ALTS,
    autoTrackAlts = true,
    themeStyle = "auto",
}

local MailAssistant = YUI.MailAssistant or {}
YUI.MailAssistant = MailAssistant

local runtime = MailAssistant.runtime or {
    enabled = false,
    eventsAttached = false,
    category = CATEGORY_ALTS,
    page = 1,
    cache = {},
    dirty = {
        [CATEGORY_ALTS] = true,
        [CATEGORY_FRIENDS] = true,
        [CATEGORY_GUILD] = true,
        [CATEGORY_FAVORITES] = true,
    },
    refreshToken = 0,
    guildRosterRequested = false,
    characterRegistered = false,
    personalDataCleaned = false,
    temporarilyClosed = false,
}
MailAssistant.runtime = runtime
runtime.temporarilyClosed = runtime.temporarilyClosed == true
runtime.recentRecipients = runtime.recentRecipients or {}

local eventOwner = MailAssistant.eventOwner or { traceName = "MailAssistant.Runtime" }
MailAssistant.eventOwner = eventOwner
local bootstrapOwner = MailAssistant.bootstrapOwner or { traceName = "MailAssistant.Bootstrap" }
MailAssistant.bootstrapOwner = bootstrapOwner
local profileOwner = MailAssistant.profileOwner or {}
MailAssistant.profileOwner = profileOwner

local type = type
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local pcall = pcall
local select = select
local math_ceil = math.ceil
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local string_lower = string.lower
local string_gsub = string.gsub
local string_match = string.match
local string_format = string.format
local table_sort = table.sort
local table_insert = table.insert
local table_remove = table.remove

local function T(key, fallback)
    return L[key] or fallback or key
end

local function NonEmptyString(value)
    if type(Security.IsSecretValue) == "function" and Security.IsSecretValue(value) == true then
        return nil
    end
    if type(value) == "string" and value ~= "" then
        return value
    end
end

local function NormalizeRealm(value)
    value = NonEmptyString(value)
    if not value then return nil end
    return string_gsub(value, "%s+", "")
end

local function SplitNameRealm(value)
    value = NonEmptyString(value)
    if not value then return nil, nil end
    local name, realm = string_match(value, "^(.+)%-(.+)$")
    return name or value, NormalizeRealm(realm)
end

local function GetCurrentRealm()
    if type(UnitAPI.GetNormalizedRealmName) == "function" then
        local realm = UnitAPI.GetNormalizedRealmName()
        if NonEmptyString(realm) then return NormalizeRealm(realm) end
    end
    if type(_G.GetNormalizedRealmName) == "function" then
        local ok, realm = pcall(_G.GetNormalizedRealmName)
        if ok and NonEmptyString(realm) then return NormalizeRealm(realm) end
    end
    if type(_G.GetRealmName) == "function" then
        local ok, realm = pcall(_G.GetRealmName)
        if ok and NonEmptyString(realm) then return NormalizeRealm(realm) end
    end
end

local function ContactKey(name, realm)
    name = NonEmptyString(name)
    realm = NormalizeRealm(realm)
    if not name or not realm then return nil end
    return string_lower(name) .. "-" .. string_lower(realm)
end

local function NormalizeCategory(value)
    if VALID_CATEGORIES[value] then return value end
    return CATEGORY_ALTS
end

local function NormalizePersonalCategory(value)
    if value == CATEGORY_ALTS or value == CATEGORY_FAVORITES then return value end
    return CATEGORY_FAVORITES
end

local function NormalizeThemeStyle(value)
    if value == "native" or value == "dark" then return value end
    return "auto"
end

local function GetConfig()
    local config = Components:EnsureConfig(CONFIG_KEY, DEFAULTS, PRODUCT_ID)
    if type(config) ~= "table" then return DEFAULTS end
    config.defaultCategory = NormalizeCategory(config.defaultCategory)
    config.autoTrackAlts = config.autoTrackAlts ~= false
    config.themeStyle = NormalizeThemeStyle(config.themeStyle)
    return config
end

local function GetPersonalStore(create)
    if not (YUI.DB and type(YUI.DB.GetGlobal) == "function") then return nil end
    local global = YUI.DB:GetGlobal(PRODUCT_ID)
    if type(global) ~= "table" then return nil end

    local store = global[STORE_KEY]
    if type(store) ~= "table" then
        if create == false then return nil end
        store = {}
        global[STORE_KEY] = store
    end
    if type(store.characters) ~= "table" then store.characters = {} end
    if type(store.favorites) ~= "table" then store.favorites = {} end
    local previousSchema = tonumber(store.schemaVersion) or 0
    if previousSchema < STORE_SCHEMA_VERSION then
        for _, collection in ipairs({ store.characters, store.favorites }) do
            for _, entry in pairs(collection) do
                if type(entry) == "table" and entry.manuallyAdded == nil
                    and entry.classFile == nil and entry.faction == nil then
                    entry.manuallyAdded = true
                end
            end
        end
    end
    store.schemaVersion = STORE_SCHEMA_VERSION
    return store
end

local function GetCurrentIdentity()
    local name, realm
    local classFile
    if type(UnitAPI.GetDisplayNameInfo) == "function" then
        local info = UnitAPI.GetDisplayNameInfo("player")
        if type(info) == "table" then
            name, realm = SplitNameRealm(info.displayName or info.name)
            realm = NormalizeRealm(info.realm) or realm
            classFile = NonEmptyString(info.classToken)
        end
    end
    if not NonEmptyString(name) and type(UnitAPI.UnitFullName) == "function" then
        name, realm = UnitAPI.UnitFullName("player")
    elseif not NonEmptyString(name) and type(_G.UnitFullName) == "function" then
        local ok
        ok, name, realm = pcall(_G.UnitFullName, "player")
        if not ok then name, realm = nil, nil end
    end
    if not NonEmptyString(name) and type(_G.UnitName) == "function" then
        name = _G.UnitName("player")
    end
    realm = NormalizeRealm(realm) or GetCurrentRealm()
    if not NonEmptyString(name) or not realm then return nil end

    local className
    if type(_G.UnitClass) == "function" then
        local rawClassName, rawClassFile = _G.UnitClass("player")
        className = NonEmptyString(rawClassName)
        classFile = classFile or NonEmptyString(rawClassFile)
    end
    local faction
    if type(_G.UnitFactionGroup) == "function" then
        faction = _G.UnitFactionGroup("player")
    end
    return {
        name = name,
        realm = realm,
        className = className,
        classFile = classFile,
        faction = faction,
        key = ContactKey(name, realm),
    }
end

local function IsCurrentCharacter(contact)
    local current = GetCurrentIdentity()
    return current and contact and contact.key == current.key or false
end

local classFileByLocalizedName
local function GetClassFile(className)
    if not NonEmptyString(className) then return nil end
    if not classFileByLocalizedName then
        classFileByLocalizedName = {}
        for classFile, localized in pairs(_G.LOCALIZED_CLASS_NAMES_MALE or {}) do
            if NonEmptyString(localized) then classFileByLocalizedName[localized] = classFile end
        end
        for classFile, localized in pairs(_G.LOCALIZED_CLASS_NAMES_FEMALE or {}) do
            if NonEmptyString(localized) then classFileByLocalizedName[localized] = classFile end
        end
    end
    return classFileByLocalizedName[className]
end

local manualClassOptions
local manualClassFiles
local function GetManualClassOptions()
    if manualClassOptions then return manualClassOptions end
    manualClassOptions = {
        { text = T("value.none", "Not specified"), value = "" },
    }
    manualClassFiles = {}

    local infos = type(UnitAPI.GetClassInfos) == "function" and UnitAPI.GetClassInfos() or nil
    if type(infos) == "table" then
        for _, info in ipairs(infos) do
            local classFile = type(info) == "table" and NonEmptyString(info.classFile) or nil
            if classFile and not manualClassFiles[classFile] then
                manualClassFiles[classFile] = true
                manualClassOptions[#manualClassOptions + 1] = {
                    text = NonEmptyString(info.className) or classFile,
                    value = classFile,
                }
            end
        end
    end

    if #manualClassOptions == 1 then
        local pending = {}
        for classFile, className in pairs(_G.LOCALIZED_CLASS_NAMES_MALE or {}) do
            if NonEmptyString(classFile) and NonEmptyString(className) then
                pending[#pending + 1] = { text = className, value = classFile }
            end
        end
        table_sort(pending, function(left, right) return left.text < right.text end)
        for _, option in ipairs(pending) do
            if not manualClassFiles[option.value] then
                manualClassFiles[option.value] = true
                manualClassOptions[#manualClassOptions + 1] = option
            end
        end
    end
    return manualClassOptions
end

local function NormalizeManualMetadata(metadata)
    if type(metadata) ~= "table" then return nil, nil end
    local classFile = NonEmptyString(metadata.classFile)
    local faction = NonEmptyString(metadata.faction)
    GetManualClassOptions()
    if classFile and not manualClassFiles[classFile] then return nil, nil, "invalid_metadata" end
    if faction and faction ~= "Alliance" and faction ~= "Horde" then
        return nil, nil, "invalid_metadata"
    end
    return classFile, faction
end

local manualFactionOptions
local function GetManualFactionOptions()
    if not manualFactionOptions then
        manualFactionOptions = {
            { text = T("value.none", "Not specified"), value = "" },
            { text = T("faction.alliance", "Alliance"), value = "Alliance" },
            { text = T("faction.horde", "Horde"), value = "Horde" },
        }
    end
    return manualFactionOptions
end

local function NewContact(name, realm, options)
    local explicitRealm = realm
    name, realm = SplitNameRealm(name)
    realm = realm or NormalizeRealm(explicitRealm) or NormalizeRealm(options and options.realm) or GetCurrentRealm()
    local key = ContactKey(name, realm)
    if not key then return nil end
    return {
        key = key,
        name = name,
        realm = realm,
        classFile = options and options.classFile,
        className = options and options.className,
        faction = options and options.faction,
        manuallyAdded = options and options.manuallyAdded == true or nil,
        sortOrder = options and options.sortOrder,
        bnetName = options and options.bnetName,
        source = options and options.source,
    }
end

local function ApplyAutomaticMetadata(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then return false end
    local changed = false
    for _, field in ipairs({ "classFile", "faction" }) do
        if source[field] ~= nil and target[field] ~= source[field] then
            target[field] = source[field]
            changed = true
        end
    end
    if target.manuallyAdded == true then
        target.manuallyAdded = nil
        changed = true
    end
    return changed
end

local function SyncAutomaticContactMetadata(contact)
    if not contact or not contact.key
        or (contact.source ~= CATEGORY_FRIENDS and contact.source ~= CATEGORY_GUILD) then return false end
    local store = GetPersonalStore(false)
    if not store then return false end
    local charactersChanged = ApplyAutomaticMetadata(store.characters[contact.key], contact)
    local favoritesChanged = ApplyAutomaticMetadata(store.favorites[contact.key], contact)
    if charactersChanged then runtime.dirty[CATEGORY_ALTS] = true end
    if favoritesChanged then runtime.dirty[CATEGORY_FAVORITES] = true end
    return charactersChanged or favoritesChanged
end

local function AddUniqueContact(list, seen, contact)
    if not contact or not contact.key or IsCurrentCharacter(contact) then return false end
    SyncAutomaticContactMetadata(contact)
    if seen[contact.key] then return false end
    seen[contact.key] = true
    list[#list + 1] = contact
    return true
end

local function NormalizeSortOrder(value)
    if type(value) == "number" and value >= 1 and value < math.huge and value == math_floor(value) then
        return value
    end
end

local function SortContacts(list)
    table_sort(list, function(left, right)
        local leftOrder = NormalizeSortOrder(left.sortOrder) or math.huge
        local rightOrder = NormalizeSortOrder(right.sortOrder) or math.huge
        if leftOrder ~= rightOrder then return leftOrder < rightOrder end
        local leftName = string_lower(left.name or "")
        local rightName = string_lower(right.name or "")
        if leftName ~= rightName then return leftName < rightName end
        local leftRealm = string_lower(left.realm or "")
        local rightRealm = string_lower(right.realm or "")
        if leftRealm ~= rightRealm then return leftRealm < rightRealm end
        return (left.key or "") < (right.key or "")
    end)
    return list
end

function MailAssistant:RegisterCurrentCharacter()
    if runtime.characterRegistered or runtime.personalDataCleaned then return false end
    local config = GetConfig()
    if config.autoTrackAlts ~= true then return false end
    local identity = GetCurrentIdentity()
    if not identity or not identity.key then return false end
    local store = GetPersonalStore(true)
    if not store then return false end

    local previous = store.characters[identity.key]
    store.characters[identity.key] = {
        name = identity.name,
        realm = identity.realm,
        classFile = identity.classFile,
        faction = identity.faction,
        sortOrder = type(previous) == "table" and previous.sortOrder or nil,
    }
    if ApplyAutomaticMetadata(store.favorites[identity.key], identity) then
        self:Invalidate(CATEGORY_FAVORITES)
    end
    runtime.characterRegistered = true
    self:Invalidate(CATEGORY_ALTS)
    return true
end

function MailAssistant:BuildAlts()
    local list, seen = {}, {}
    local store = GetPersonalStore(false)
    for _, entry in pairs(store and store.characters or {}) do
        if type(entry) == "table" then
            AddUniqueContact(list, seen, NewContact(entry.name, entry.realm, {
                classFile = entry.classFile,
                faction = entry.faction,
                manuallyAdded = entry.manuallyAdded,
                source = CATEGORY_ALTS,
                sortOrder = entry.sortOrder,
            }))
        end
    end
    return SortContacts(list)
end

local function GetCurrentFaction()
    local current = GetCurrentIdentity()
    return current and current.faction or nil
end

local function IsRetailWowGameAccount(info)
    if type(info) ~= "table" or info.isOnline ~= true then return false end
    local client = info.clientProgram
    local wowClient = _G.BNET_CLIENT_WOW
    if client ~= "WoW" and (wowClient == nil or client ~= wowClient) then return false end
    local mainline = _G.WOW_PROJECT_MAINLINE or 1
    if info.wowProjectID ~= nil and info.wowProjectID ~= mainline then return false end
    return true
end

local function AddBattleNetGameAccount(list, seen, info, accountName, faction)
    if not IsRetailWowGameAccount(info) then return end
    if faction and NonEmptyString(info.factionName) and info.factionName ~= faction then return end
    AddUniqueContact(list, seen, NewContact(info.characterName, info.realmName, {
        className = info.className,
        classFile = GetClassFile(info.className),
        faction = info.factionName or faction,
        bnetName = accountName,
        source = CATEGORY_FRIENDS,
    }))
end

function MailAssistant:BuildFriends()
    local list, seen = {}, {}
    local faction = GetCurrentFaction()
    local friendCount = type(Social.GetNumFriends) == "function" and Social.GetNumFriends() or 0
    for index = 1, tonumber(friendCount) or 0 do
        local info = type(Social.GetFriendInfoByIndex) == "function" and Social.GetFriendInfoByIndex(index) or nil
        if info and (info.connected == true or info.online == true) then
            AddUniqueContact(list, seen, NewContact(info.name, nil, {
                className = info.className,
                classFile = GetClassFile(info.className),
                faction = faction,
                source = CATEGORY_FRIENDS,
            }))
        end
    end

    local bnetCount = 0
    if type(Social.GetBNNumFriends) == "function" then
        bnetCount = select(1, Social.GetBNNumFriends()) or 0
    end
    for friendIndex = 1, tonumber(bnetCount) or 0 do
        local accountInfo = type(Social.GetBNFriendAccountInfo) == "function"
            and Social.GetBNFriendAccountInfo(friendIndex) or nil
        local accountName = accountInfo and (accountInfo.accountName or accountInfo.battleTag)
        local gameAccountCount
        if _G.C_BattleNet and type(_G.C_BattleNet.GetFriendNumGameAccounts) == "function" then
            local ok, count = pcall(_G.C_BattleNet.GetFriendNumGameAccounts, friendIndex)
            if ok then gameAccountCount = tonumber(count) or 0 end
        end
        if gameAccountCount and gameAccountCount > 0
            and _G.C_BattleNet and type(_G.C_BattleNet.GetFriendGameAccountInfo) == "function" then
            for gameIndex = 1, gameAccountCount do
                local ok, gameInfo = pcall(_G.C_BattleNet.GetFriendGameAccountInfo, friendIndex, gameIndex)
                if ok then AddBattleNetGameAccount(list, seen, gameInfo, accountName, faction) end
            end
        elseif accountInfo then
            AddBattleNetGameAccount(list, seen, accountInfo.gameAccountInfo, accountName, faction)
        end
    end
    return SortContacts(list)
end

function MailAssistant:RequestGuildRoster()
    if runtime.guildRosterRequested then return false end
    runtime.guildRosterRequested = true
    if type(API.GuildRoster) == "function" then
        pcall(API.GuildRoster)
        return true
    end
    if _G.C_GuildInfo and type(_G.C_GuildInfo.GuildRoster) == "function" then
        pcall(_G.C_GuildInfo.GuildRoster)
        return true
    end
    return false
end

function MailAssistant:BuildGuild()
    local list, seen = {}, {}
    if type(_G.IsInGuild) == "function" then
        local ok, inGuild = pcall(_G.IsInGuild)
        if not ok or inGuild ~= true then return list end
    end
    self:RequestGuildRoster()
    local getCount = type(API.GetNumGuildMembers) == "function" and API.GetNumGuildMembers
        or (type(_G.GetNumGuildMembers) == "function" and _G.GetNumGuildMembers) or nil
    local count = 0
    if getCount then
        local ok, value = pcall(getCount)
        if ok then count = tonumber(value) or 0 end
    end
    local getInfo = type(API.GetGuildRosterInfo) == "function" and API.GetGuildRosterInfo
        or (type(_G.GetGuildRosterInfo) == "function" and _G.GetGuildRosterInfo) or nil
    for index = 1, tonumber(count) or 0 do
        local fullName, _, _, _, className, _, _, _, _, _, classFile
        if getInfo then
            local ok
            ok, fullName, _, _, _, className, _, _, _, _, _, classFile = pcall(getInfo, index)
            if not ok then fullName, className, classFile = nil, nil, nil end
        end
        AddUniqueContact(list, seen, NewContact(fullName, nil, {
            className = className,
            classFile = classFile or GetClassFile(className),
            source = CATEGORY_GUILD,
        }))
    end
    return SortContacts(list)
end

function MailAssistant:BuildFavorites()
    local list, seen = {}, {}
    local store = GetPersonalStore(false)
    for _, entry in pairs(store and store.favorites or {}) do
        if type(entry) == "table" then
            AddUniqueContact(list, seen, NewContact(entry.name, entry.realm, {
                classFile = entry.classFile,
                faction = entry.faction,
                manuallyAdded = entry.manuallyAdded,
                source = CATEGORY_FAVORITES,
                sortOrder = entry.sortOrder,
            }))
        end
    end
    return SortContacts(list)
end

function MailAssistant:IsFavorite(contact)
    local store = GetPersonalStore(false)
    return store and contact and contact.key and store.favorites[contact.key] ~= nil or false
end

function MailAssistant:SetFavorite(contact, favorite)
    if type(contact) ~= "table" or not contact.key then return false end
    local store = GetPersonalStore(true)
    if not store then return false end
    if favorite == true then
        local previous = store.favorites[contact.key]
        store.favorites[contact.key] = {
            name = contact.name,
            realm = contact.realm,
            classFile = contact.classFile,
            faction = contact.faction,
            sortOrder = type(previous) == "table" and previous.sortOrder or nil,
        }
    else
        store.favorites[contact.key] = nil
    end
    self:Invalidate(CATEGORY_FAVORITES)
    return true
end

local function CopyContactMetadata(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then return target end
    for _, field in ipairs({ "classFile", "faction" }) do
        if target[field] == nil and source[field] ~= nil then target[field] = source[field] end
    end
    return target
end

function MailAssistant:RecordSentRecipient(value)
    value = NonEmptyString(value)
    if not value then return false end
    local contact = NewContact(string_match(value, "^%s*(.-)%s*$"))
    if not contact or not NonEmptyString(contact.name) or not NonEmptyString(contact.realm)
        or #contact.name > 64 or #contact.realm > 128 or string_match(contact.name, "%s")
        or IsCurrentCharacter(contact) then return false end

    local store = GetPersonalStore(false)
    if store then
        CopyContactMetadata(contact, store.characters[contact.key])
        CopyContactMetadata(contact, store.favorites[contact.key])
    end
    local recent = runtime.recentRecipients
    for index = #recent, 1, -1 do
        if recent[index].key == contact.key then
            CopyContactMetadata(contact, recent[index])
            table_remove(recent, index)
        end
    end
    table_insert(recent, 1, contact)
    if #recent > RECENT_RECIPIENT_LIMIT then table_remove(recent) end
    local editor = runtime.contactEditor
    if editor and editor:IsShown() then self:RefreshContactEditor() end
    return true
end

function MailAssistant:AddPersonalContact(category, value, metadata)
    if category ~= CATEGORY_ALTS and category ~= CATEGORY_FAVORITES then
        return nil, "invalid_category"
    end
    category = NormalizePersonalCategory(category)
    value = NonEmptyString(value)
    if not value then return nil, "invalid" end
    value = string_match(value, "^%s*(.-)%s*$")
    local contact = NewContact(value, nil, { source = category })
    if not contact or not NonEmptyString(contact.name) or not NonEmptyString(contact.realm)
        or #contact.name > 64 or #contact.realm > 128 or string_match(contact.name, "%s") then
        return nil, "invalid"
    end
    if IsCurrentCharacter(contact) then return nil, "current_character" end
    local classFile, faction, metadataCode = NormalizeManualMetadata(metadata)
    if metadataCode then return nil, metadataCode end

    local store = GetPersonalStore(true)
    if not store then return nil, "store_unavailable" end
    local collection = category == CATEGORY_ALTS and store.characters or store.favorites
    if collection[contact.key] ~= nil then return nil, "duplicate" end

    local entry = {
        name = contact.name,
        realm = contact.realm,
        classFile = classFile,
        faction = faction,
        manuallyAdded = true,
    }
    local other = category == CATEGORY_ALTS and store.favorites or store.characters
    CopyContactMetadata(entry, other[contact.key])
    collection[contact.key] = entry
    contact.classFile = entry.classFile
    contact.faction = entry.faction
    contact.manuallyAdded = true
    self:Invalidate(category)
    self:RefreshNow(true)
    return contact
end

function MailAssistant:RemovePersonalContact(category, contact)
    if category ~= CATEGORY_ALTS and category ~= CATEGORY_FAVORITES then return false end
    category = NormalizePersonalCategory(category)
    if type(contact) ~= "table" or not contact.key then return false end
    local store = GetPersonalStore(false)
    local collection = store and (category == CATEGORY_ALTS and store.characters or store.favorites)
    if type(collection) ~= "table" or collection[contact.key] == nil then return false end
    collection[contact.key] = nil
    self:Invalidate(category)
    self:RefreshNow(true)
    return true
end

function MailAssistant:MovePersonalContact(category, contact, direction)
    if (category ~= CATEGORY_ALTS and category ~= CATEGORY_FAVORITES)
        or (direction ~= -1 and direction ~= 1) or type(contact) ~= "table" then return false end
    local contacts = self:GetContacts(category)
    local neighbor
    for index, entry in ipairs(contacts) do
        if entry.key == contact.key then
            neighbor = contacts[index + direction]
            break
        end
    end
    if not neighbor then return false end
    local store = GetPersonalStore(false)
    local collection = store and (category == CATEGORY_ALTS and store.characters or store.favorites)
    local target = collection and collection[contact.key]
    local adjacent = collection and collection[neighbor.key]
    if type(target) ~= "table" or type(adjacent) ~= "table" then return false end

    -- 保留当前角色在账号顺序中的位置，再交换相邻的可见角色。
    local ordered = {}
    for _, entry in pairs(collection) do
        if type(entry) == "table" then
            local saved = NewContact(entry.name, entry.realm, { sortOrder = entry.sortOrder })
            if saved then
                saved.personalEntry = entry
                ordered[#ordered + 1] = saved
            end
        end
    end
    for index, saved in ipairs(SortContacts(ordered)) do saved.personalEntry.sortOrder = index end
    target.sortOrder, adjacent.sortOrder = adjacent.sortOrder, target.sortOrder
    self:RevealPersonalContact(category, contact.key)
    return true
end

function MailAssistant:RefreshRecentRecipientMetadata()
    local recent = runtime.recentRecipients
    if #recent == 0 then return end
    local store = GetPersonalStore(false)
    if store then
        for _, contact in ipairs(recent) do
            CopyContactMetadata(contact, store.characters[contact.key])
            CopyContactMetadata(contact, store.favorites[contact.key])
        end
    end
    for _, category in ipairs({ CATEGORY_FRIENDS, CATEGORY_GUILD }) do
        for _, source in ipairs(self:GetContacts(category)) do
            for _, contact in ipairs(recent) do
                if contact.key == source.key then ApplyAutomaticMetadata(contact, source) end
            end
        end
    end
end

function MailAssistant:Invalidate(category)
    if category then
        runtime.dirty[NormalizeCategory(category)] = true
    else
        for key in pairs(VALID_CATEGORIES) do runtime.dirty[key] = true end
    end
end

function MailAssistant:GetContacts(category)
    category = NormalizeCategory(category)
    if runtime.dirty[category] or type(runtime.cache[category]) ~= "table" then
        local list
        if category == CATEGORY_ALTS then
            list = self:BuildAlts()
        elseif category == CATEGORY_FRIENDS then
            list = self:BuildFriends()
        elseif category == CATEGORY_GUILD then
            list = self:BuildGuild()
        else
            list = self:BuildFavorites()
        end
        runtime.cache[category] = list
        runtime.dirty[category] = nil
    end
    return runtime.cache[category]
end

function MailAssistant:FormatRecipient(contact)
    if type(contact) ~= "table" or not NonEmptyString(contact.name) then return nil end
    local currentRealm = GetCurrentRealm()
    local contactRealm = NormalizeRealm(contact.realm)
    if currentRealm and contactRealm and string_lower(contactRealm) == string_lower(currentRealm) then return contact.name end
    if NonEmptyString(contact.realm) then return contact.name .. "-" .. contact.realm end
    return contact.name
end

local function GetClassColor(classFile)
    local color = classFile and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classFile]
    if not color and classFile and _G.C_ClassColor and type(_G.C_ClassColor.GetClassColor) == "function" then
        local ok, result = pcall(_G.C_ClassColor.GetClassColor, classFile)
        if ok then color = result end
    end
    if not color then return 1, 1, 1 end
    if type(color.GetRGB) == "function" then return color:GetRGB() end
    return color.r or 1, color.g or 1, color.b or 1
end

local function GetClassDisplayName(contact)
    if NonEmptyString(contact.className) then return contact.className end
    if contact.classFile then
        return (_G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[contact.classFile])
            or contact.classFile
    end
end

local function GetFactionDisplayName(faction)
    if faction == "Horde" then return T("faction.horde", "Horde") end
    if faction == "Alliance" then return T("faction.alliance", "Alliance") end
    return faction
end

local function GetColorRGB(color, fallbackR, fallbackG, fallbackB)
    if type(color) == "table" then
        if type(color.GetRGB) == "function" then return color:GetRGB() end
        return color.r or fallbackR, color.g or fallbackG, color.b or fallbackB
    end
    return fallbackR, fallbackG, fallbackB
end

local function GetFactionColor(faction)
    local color
    if faction == "Horde" then
        color = _G.PLAYER_FACTION_COLOR_HORDE
            or (_G.PLAYER_FACTION_COLORS and _G.PLAYER_FACTION_COLORS[0])
        return GetColorRGB(color, 0.90, 0.05, 0.07)
    end
    if faction == "Alliance" then
        color = _G.PLAYER_FACTION_COLOR_ALLIANCE
            or (_G.PLAYER_FACTION_COLORS and _G.PLAYER_FACTION_COLORS[1])
        return GetColorRGB(color, 0.29, 0.33, 0.91)
    end
    return 1, 1, 1
end

local function ColorText(value, r, g, b)
    local function Byte(channel)
        return math_min(255, math_max(0, math.floor((tonumber(channel) or 1) * 255 + 0.5)))
    end
    return string_format("|cff%02x%02x%02x%s|r", Byte(r), Byte(g), Byte(b), tostring(value or ""))
end

function MailAssistant:ShowContactTooltip(button)
    local contact = button and button.contact
    local tooltip = _G.GameTooltip
    if not contact or not tooltip then return end
    tooltip:SetOwner(button, "ANCHOR_RIGHT")
    tooltip:ClearLines()
    local r, g, b = GetClassColor(contact.classFile)
    tooltip:SetText(contact.name or "", r, g, b)
    if contact.manuallyAdded == true then
        tooltip:AddLine(T("tooltip.manual_unverified", "This character was added manually and has not been verified."),
            1, 0.15, 0.15, true)
    end
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(T("tooltip.realm", "Realm"), contact.realm or T("value.unknown", "Unknown"), 1, 1, 1, 1, 1, 1)
    local className = GetClassDisplayName(contact)
    if className then tooltip:AddDoubleLine(T("tooltip.class", "Class"), className, 1, 1, 1, r, g, b) end
    local faction = GetFactionDisplayName(contact.faction)
    if faction then
        local fr, fg, fb = GetFactionColor(contact.faction)
        tooltip:AddDoubleLine(T("tooltip.faction", "Faction"), faction, 1, 1, 1, fr, fg, fb)
    end
    if contact.bnetName then
        local br, bg, bb = GetColorRGB(_G.FRIENDS_BNET_NAME_COLOR or _G.BATTLENET_FONT_COLOR, 0.51, 0.773, 1)
        tooltip:AddDoubleLine(T("tooltip.bnet", "Battle.net"), contact.bnetName, 1, 1, 1, br, bg, bb)
    end
    local wr, wg, wb = GetColorRGB(_G.HIGHLIGHT_FONT_COLOR, 1, 1, 1)
    local ar, ag, ab = GetColorRGB(_G.NORMAL_FONT_COLOR, 1, 0.82, 0)
    tooltip:AddLine(" ")
    tooltip:AddLine(ColorText(T("tooltip.left_click_label", "Left-click:"), wr, wg, wb)
        .. " " .. ColorText(T("tooltip.fill_recipient", "Fill recipient"), ar, ag, ab), 1, 1, 1)
    local rightAction = contact.source == CATEGORY_ALTS
        and T("tooltip.manage_contact", "Manage contact")
        or (self:IsFavorite(contact)
            and T("tooltip.remove_favorite", "Remove from favorites")
            or T("tooltip.add_favorite", "Add to favorites"))
    tooltip:AddLine(ColorText(T("tooltip.right_click_label", "Right-click:"), wr, wg, wb)
        .. " " .. ColorText(rightAction, ar, ag, ab), 1, 1, 1)
    tooltip:Show()
end

function MailAssistant:HideContactTooltip()
    if _G.GameTooltip then _G.GameTooltip:Hide() end
end

local function HideSharedTooltip()
    if type(YUI.HideGameTooltip) == "function" then
        YUI.HideGameTooltip()
    elseif _G.GameTooltip then
        _G.GameTooltip:Hide()
    end
end

local function SetColorTable(target, r, g, b, a)
    target[1], target[2], target[3], target[4] = r, g, b, a == nil and 1 or a
end

local function CreateChromeIconButton(parent, options)
    options = options or {}
    local button = GUI2:CreateButtonFrame(parent, { template = "BackdropTemplate" })
    local size = options.size or HEADER_BUTTON_SIZE
    button:SetSize(size, size)
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    button:SetBackdropColor(0, 0, 0, 0)

    local icon
    if options.plusStyle then
        local pixel = type(GUI2.GetPixelSize) == "function"
            and GUI2:GetPixelSize(button, 1, 1) or (GUI2.mult or 1)
        local horizontal = GUI2:CreateTexture(button, { layer = "ARTWORK" })
        horizontal:SetColorTexture(1, 1, 1, 1)
        horizontal:SetSize(10, pixel)
        horizontal:SetPoint("CENTER")
        local vertical = GUI2:CreateTexture(button, { layer = "ARTWORK" })
        vertical:SetColorTexture(1, 1, 1, 1)
        vertical:SetSize(pixel, 10)
        vertical:SetPoint("CENTER")
        icon = {
            plusStyle = true,
            horizontal = horizontal,
            vertical = vertical,
        }
        function icon:SetVertexColor(r, g, b, a)
            self.vertexColor = { r, g, b, a }
            self.horizontal:SetVertexColor(r, g, b, a)
            self.vertical:SetVertexColor(r, g, b, a)
        end
    else
        icon = GUI2:CreateTexture(button, { layer = "ARTWORK" })
        icon:SetSize(options.iconSize or HEADER_ICON_SIZE, options.iconSize or HEADER_ICON_SIZE)
        icon:SetPoint("CENTER")
        icon:SetAtlas(options.atlas)
        if options.rotation then icon:SetRotation(options.rotation) end
    end
    button.icon = icon
    button.gui2Disabled = false
    button.gui2Accent = { 1, 0.82, 0, 1 }

    local function Paint(owner, state)
        if owner.gui2Disabled then
            icon:SetVertexColor(0.3, 0.3, 0.3, 1)
            owner:SetBackdropColor(0, 0, 0, 0)
        elseif state == "hover" then
            if options.closeStyle then
                icon:SetVertexColor(1, 1, 1, 1)
                owner:SetBackdropColor(1, 0.2, 0.2, 0.5)
            elseif options.hoverWhite then
                icon:SetVertexColor(1, 1, 1, 1)
                owner:SetBackdropColor(0.2, 0.2, 0.2, 0.5)
            else
                icon:SetVertexColor(owner.gui2Accent[1], owner.gui2Accent[2], owner.gui2Accent[3], 1)
                owner:SetBackdropColor(0.2, 0.2, 0.2, 0.5)
            end
        else
            icon:SetVertexColor(0.7, 0.7, 0.7, 1)
            owner:SetBackdropColor(0, 0, 0, 0)
        end
    end

    function button:SetAccent(r, g, b)
        SetColorTable(self.gui2Accent, r, g, b, 1)
        Paint(self, "normal")
    end

    function button:SetDisabled(disabled)
        self.gui2Disabled = disabled == true
        if self.EnableMouse then self:EnableMouse(not self.gui2Disabled) end
        Paint(self, "normal")
    end

    button:SetScript("OnEnter", function(owner)
        Paint(owner, "hover")
        if owner.gui2Disabled or not options.tooltip or not _G.GameTooltip then return end
        _G.GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        _G.GameTooltip:SetText(options.tooltip)
        _G.GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(owner)
        Paint(owner, "normal")
        HideSharedTooltip()
    end)
    button:SetScript("OnClick", function(owner, mouseButton)
        if owner.gui2Disabled or type(options.onClick) ~= "function" then return end
        options.onClick(owner, mouseButton)
    end)
    Paint(button, "normal")
    return button
end

local function SetEditorFeedback(message, colorKey)
    local editor = runtime.contactEditor
    if not (editor and editor.feedback) then return end
    editor.feedback:SetText(message or "")
    if GUI2 and type(GUI2.GetColor) == "function" then
        local r, g, b = GUI2:GetColor(colorKey or "color.text.secondary")
        editor.feedback:SetTextColor(r or 1, g or 1, b or 1, 1)
    end
end

local function GetContactEditorPageSize(category)
    local count = category == CATEGORY_FAVORITES and #runtime.recentRecipients or 0
    local height = count > 0 and (34 + math_ceil(count / 2) * 24) or 0
    return EDITOR_PAGE_SIZE - math_ceil(height / 28), height, count
end

function MailAssistant:AddRecentFavorite(contact)
    if not contact or self:IsFavorite(contact) or not self:SetFavorite(contact, true) then return false end
    HideSharedTooltip()
    SetEditorFeedback(T("editor.added_favorite", "Favorite added"), "color.state.success")
    self:RevealPersonalContact(CATEGORY_FAVORITES, contact.key)
    return true
end

function MailAssistant:ToggleRecentFavorite(contact)
    if not self:IsFavorite(contact) then return self:AddRecentFavorite(contact) end
    if not self:RemovePersonalContact(CATEGORY_FAVORITES, contact) then return false end
    HideSharedTooltip()
    SetEditorFeedback(T("editor.removed", "Contact removed"), "color.text.secondary")
    self:RefreshContactEditor()
    return true
end

function MailAssistant:RefreshContactEditor()
    local editor = runtime.contactEditor
    if not editor then return false end
    local category = NormalizePersonalCategory(editor.category)
    if category == CATEGORY_FAVORITES then self:RefreshRecentRecipientMetadata() end
    local recent = runtime.recentRecipients
    local pageSize, recentHeight, recentCount = GetContactEditorPageSize(category)
    editor.recentLabel:SetShown(recentCount > 0)
    for index, button in ipairs(editor.recentButtons) do
        local contact = index <= recentCount and recent[index] or nil
        button.contact = contact
        if contact then
            local favorite = self:IsFavorite(contact)
            button:SetText((favorite and T("editor.recent_saved", "Saved") .. " " or "")
                .. self:FormatRecipient(contact))
            button:SetDisabled(false)
            button:SetTextColor(GetClassColor(contact.classFile))
            button:Show()
        else
            button:SetText("")
            button:Hide()
        end
    end
    editor.pageSize = pageSize
    editor.saved:ClearAllPoints()
    editor.saved:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -245 - recentHeight)
    editor.empty:ClearAllPoints()
    editor.empty:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -295 - recentHeight)
    editor.empty:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -16, -295 - recentHeight)
    local contacts = self:GetContacts(category)
    local pageCount = math_max(1, math_ceil(#contacts / pageSize))
    editor.page = math_min(math_max(tonumber(editor.page) or 1, 1), pageCount)
    local startIndex = ((editor.page - 1) * pageSize) + 1

    for rowIndex = 1, EDITOR_PAGE_SIZE do
        local row = editor.rows[rowIndex]
        local contact = rowIndex <= pageSize and contacts[startIndex + rowIndex - 1] or nil
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -271 - recentHeight - ((rowIndex - 1) * 28))
        row.contact = contact
        row.remove.contact = contact
        row.moveUp:SetShown(contact ~= nil and #contacts > 1)
        row.moveDown:SetShown(contact ~= nil and #contacts > 1)
        row.moveUp:SetDisabled(not contact or startIndex + rowIndex - 1 == 1)
        row.moveDown:SetDisabled(not contact or startIndex + rowIndex - 1 == #contacts)
        if contact then
            row.name:SetText((contact.name or "") .. (contact.realm and "-" .. contact.realm or ""))
            row.name:SetTextColor(GetClassColor(contact.classFile))
            row:Show()
        else
            row.name:SetText("")
            row:Hide()
        end
    end

    local empty = #contacts == 0
    editor.empty:SetText(category == CATEGORY_ALTS
        and T("editor.empty_alts", "No saved alts")
        or T("editor.empty_favorites", "No saved favorites"))
    editor.empty:SetShown(empty)
    editor.pageText:SetText(string_format("%d / %d", editor.page, pageCount))
    editor.previous:SetDisabled(editor.page <= 1)
    editor.next:SetDisabled(editor.page >= pageCount)
    return true
end

function MailAssistant:SetContactEditorCategory(category)
    local editor = runtime.contactEditor
    if not editor then return false end
    HideSharedTooltip()
    editor.category = NormalizePersonalCategory(category)
    editor.page = 1
    if editor.tabs and editor.tabs.SetValue then editor.tabs:SetValue(editor.category, true) end
    SetEditorFeedback("")
    return self:RefreshContactEditor()
end

function MailAssistant:SetContactEditorPage(page)
    local editor = runtime.contactEditor
    if not editor then return false end
    editor.page = tonumber(page) or 1
    return self:RefreshContactEditor()
end

function MailAssistant:RevealPersonalContact(category, key)
    category = NormalizePersonalCategory(category)
    self:Invalidate(category)
    local contacts = self:GetContacts(category)
    local index = 1
    for contactIndex, contact in ipairs(contacts) do
        if contact.key == key then
            index = contactIndex
            break
        end
    end
    runtime.category = category
    runtime.page = math_floor((index - 1) / math_min(math_max(tonumber(runtime.pageSize) or PAGE_SIZE, 1), PAGE_SIZE)) + 1
    if runtime.tabs and runtime.tabs.SetValue then runtime.tabs:SetValue(category, true) end
    self:RefreshNow(true)

    local editor = runtime.contactEditor
    if editor then
        editor.category = category
        editor.page = math_floor((index - 1) / GetContactEditorPageSize(category)) + 1
        if editor.tabs and editor.tabs.SetValue then editor.tabs:SetValue(category, true) end
        self:RefreshContactEditor()
    end
    return true
end

function MailAssistant:CommitContactEditor()
    local editor = runtime.contactEditor
    if not (editor and editor.input) then return false end
    local contact, code = self:AddPersonalContact(editor.category, editor.input:GetText(), {
        classFile = editor.classDropdown and editor.classDropdown:GetValue() or nil,
        faction = editor.factionDropdown and editor.factionDropdown:GetValue() or nil,
    })
    if not contact then
        local message = code == "duplicate" and T("editor.error.duplicate", "This contact already exists")
            or code == "current_character" and T("editor.error.current_character", "The current character cannot be added")
            or T("editor.error.invalid", "Enter a valid character name")
        SetEditorFeedback(message, "color.state.error")
        return false
    end

    editor.input:SetText("")
    if editor.classDropdown then editor.classDropdown:SetValue("", true) end
    if editor.factionDropdown then editor.factionDropdown:SetValue("", true) end
    SetEditorFeedback(editor.category == CATEGORY_ALTS
        and T("editor.added_alt", "Alt added")
        or T("editor.added_favorite", "Favorite added"), "color.state.success")
    self:RevealPersonalContact(editor.category, contact.key)
    if editor.input.SetFocus then editor.input:SetFocus() end
    return true
end

function MailAssistant:HideContactEditor()
    local editor = runtime.contactEditor
    if not editor then return false end
    if editor.input and editor.input.ClearFocus then editor.input:ClearFocus() end
    HideSharedTooltip()
    editor:Hide()
    return true
end

function MailAssistant:ConstructContactEditor()
    if runtime.contactEditor then return runtime.contactEditor end
    if not (_G.UIParent and GUI2 and GUI2.Form and GUI2.Form.CreateEditBox
        and GUI2.Form.CreateUnderlineTabs and GUI2.Form.CreateDropdown
        and GUI2.Form.CreateButton) then return nil end

    local editor = GUI2:CreateFrame(_G.UIParent, {
        width = EDITOR_WIDTH,
        height = EDITOR_HEIGHT,
    })
    editor:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
    if editor.SetFrameStrata then editor:SetFrameStrata("DIALOG") end
    if editor.SetFrameLevel then editor:SetFrameLevel(200) end
    if editor.SetToplevel then editor:SetToplevel(true) end
    editor:EnableMouse(true)
    editor:SetScript("OnMouseDown", function(owner) owner:Raise() end)
    if editor.SetClampedToScreen then editor:SetClampedToScreen(true) end
    runtime.contactEditor = editor

    local title = GUI2:CreateText(editor, T("editor.title", "Manage Contacts"), "font.size.lg", "color.text.heading")
    title:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -14)
    editor.title = title

    local close = CreateChromeIconButton(editor, {
        atlas = "uitools-icon-close",
        tooltip = T("editor.close", "Close"),
        closeStyle = true,
        onClick = function() MailAssistant:HideContactEditor() end,
    })
    close:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -10, -10)
    editor.close = close

    editor.tabIndicatorColor = { 1, 0.82, 0, 1 }
    editor.tabHoverColor = { 1, 0.82, 0, 1 }
    local tabs = GUI2.Form:CreateUnderlineTabs(editor, {
        width = EDITOR_WIDTH - 32,
        height = 32,
        value = CATEGORY_ALTS,
        showBaseline = true,
        equalWidth = true,
        gap = 0,
        fontSizeKey = 12,
        indicatorColor = editor.tabIndicatorColor,
        hoverColor = editor.tabHoverColor,
        items = {
            { text = T("category.alts", "Alts"), value = CATEGORY_ALTS },
            { text = T("category.favorites", "Favorites"), value = CATEGORY_FAVORITES },
        },
        onChange = function(_, value) MailAssistant:SetContactEditorCategory(value) end,
    })
    tabs:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -44)
    editor.tabs = tabs

    local inputLabel = GUI2:CreateText(editor, T("editor.character", "Character"), "font.size.sm", "color.text.secondary")
    inputLabel:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -84)
    editor.inputLabel = inputLabel

    local input = GUI2.Form:CreateEditBox(editor, {
        width = EDITOR_WIDTH - 126,
        height = 28,
        text = "",
        autoFocus = false,
        tooltip = T("editor.input_hint", "Use Name for this realm or Name-Realm for another realm"),
    })
    input:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -104)
    editor.input = input

    local add = GUI2.Form:CreateButton(editor, {
        text = T("editor.add", "Add"),
        width = 86,
        height = 28,
        tone = "accent",
        onClick = function() MailAssistant:CommitContactEditor() end,
    })
    add:SetPoint("LEFT", input, "RIGHT", 8, 0)
    editor.add = add

    local hint = GUI2:CreateText(editor, T("editor.input_hint", "Use Name for this realm or Name-Realm for another realm"),
        "font.size.sm", "color.text.muted")
    hint:SetPoint("TOPLEFT", input, "BOTTOMLEFT", 0, -6)
    hint:SetWidth(EDITOR_WIDTH - 32)
    hint:SetWordWrap(true)
    editor.hint = hint

    local metadataWidth = math_floor((EDITOR_WIDTH - 44) / 2)
    local classLabel = GUI2:CreateText(editor, T("editor.class", "Class"), "font.size.sm", "color.text.secondary")
    classLabel:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -158)
    editor.classLabel = classLabel

    local factionLabel = GUI2:CreateText(editor, T("editor.faction", "Faction"), "font.size.sm", "color.text.secondary")
    factionLabel:SetPoint("TOPLEFT", editor, "TOPLEFT", 28 + metadataWidth, -158)
    editor.factionLabel = factionLabel

    local classDropdown = GUI2.Form:CreateDropdown(editor, {
        width = metadataWidth,
        height = 28,
        value = "",
        options = GetManualClassOptions(),
    })
    classDropdown:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -178)
    editor.classDropdown = classDropdown

    local factionDropdown = GUI2.Form:CreateDropdown(editor, {
        width = metadataWidth,
        height = 28,
        value = "",
        options = GetManualFactionOptions(),
    })
    factionDropdown:SetPoint("TOPLEFT", editor, "TOPLEFT", 28 + metadataWidth, -178)
    editor.factionDropdown = factionDropdown

    local feedback = GUI2:CreateText(editor, "", "font.size.sm", "color.text.secondary")
    feedback:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -219)
    feedback:SetWidth(EDITOR_WIDTH - 32)
    feedback:SetWordWrap(false)
    editor.feedback = feedback

    local recentLabel = GUI2:CreateText(editor, T("editor.recent", "Sent this session"),
        "font.size.sm", "color.text.secondary")
    recentLabel:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -245)
    editor.recentLabel = recentLabel
    editor.recentButtons = {}
    for index = 1, RECENT_RECIPIENT_LIMIT do
        local button = GUI2.Form:CreateButton(editor, {
            width = math_floor((EDITOR_WIDTH - 40) / 2),
            height = 22,
            fontSizeKey = "font.size.sm",
            tone = "default",
            relief = "hairline",
            onClick = function(owner) MailAssistant:ToggleRecentFavorite(owner.contact) end,
        })
        button:SetPoint("TOPLEFT", editor, "TOPLEFT",
            16 + ((index - 1) % 2) * 178, -269 - math_floor((index - 1) / 2) * 24)
        button:HookScript("OnEnter", function(owner)
            local contact, tooltip = owner.contact, _G.GameTooltip
            if not contact or not tooltip then return end
            tooltip:SetOwner(owner, "ANCHOR_RIGHT")
            tooltip:SetText(contact.name .. "-" .. contact.realm, GetClassColor(contact.classFile))
            tooltip:AddLine(MailAssistant:IsFavorite(contact)
                and T("tooltip.remove_favorite", "Remove from favorites")
                or T("tooltip.add_favorite", "Add to favorites"), 1, 1, 1)
            tooltip:Show()
        end)
        button:HookScript("OnLeave", HideSharedTooltip)
        button:Hide()
        editor.recentButtons[index] = button
    end

    local saved = GUI2:CreateText(editor, T("editor.saved", "Saved Contacts"), "font.size.md", "color.text.primary")
    saved:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -245)
    editor.saved = saved

    editor.rows = {}
    for index = 1, EDITOR_PAGE_SIZE do
        local row = GUI2:CreateFrame(editor, { width = EDITOR_WIDTH - 32, height = 26 })
        row:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -271 - ((index - 1) * 28))
        local name = GUI2:CreateText(row, "", "font.size.md", "color.text.primary")
        name:SetPoint("LEFT", row, "LEFT", 4, 0)
        name:SetPoint("RIGHT", row, "RIGHT", -126, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        row.name = name
        local moveUp = CreateChromeIconButton(row, {
            atlas = "uitools-icon-chevron-left",
            rotation = -math.pi / 2,
            size = 20,
            iconSize = 12,
            tooltip = T("editor.move_up", "Move up"),
            onClick = function()
                HideSharedTooltip()
                if MailAssistant:MovePersonalContact(editor.category, row.contact, -1) then
                    SetEditorFeedback(T("editor.order_saved", "Order saved"), "color.state.success")
                end
            end,
        })
        moveUp:SetPoint("RIGHT", row, "RIGHT", -100, 0)
        row.moveUp = moveUp
        local moveDown = CreateChromeIconButton(row, {
            atlas = "uitools-icon-chevron-left",
            rotation = math.pi / 2,
            size = 20,
            iconSize = 12,
            tooltip = T("editor.move_down", "Move down"),
            onClick = function()
                HideSharedTooltip()
                if MailAssistant:MovePersonalContact(editor.category, row.contact, 1) then
                    SetEditorFeedback(T("editor.order_saved", "Order saved"), "color.state.success")
                end
            end,
        })
        moveDown:SetPoint("RIGHT", row, "RIGHT", -76, 0)
        row.moveDown = moveDown
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(owner)
            local contact, tooltip = owner.contact, _G.GameTooltip
            if not contact or not tooltip then return end
            tooltip:SetOwner(owner, "ANCHOR_RIGHT")
            tooltip:SetText(contact.name .. "-" .. contact.realm, GetClassColor(contact.classFile))
            tooltip:Show()
        end)
        row:SetScript("OnLeave", HideSharedTooltip)
        local remove = GUI2.Form:CreateButton(row, {
            text = T("editor.remove", "Remove"),
            width = 68,
            height = 24,
            tone = "default",
            relief = "hairline",
            onClick = function(button)
                local contact = button.contact
                if contact and MailAssistant:RemovePersonalContact(editor.category, contact) then
                    SetEditorFeedback(T("editor.removed", "Contact removed"), "color.text.secondary")
                    MailAssistant:RefreshContactEditor()
                end
            end,
        })
        remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.remove = remove
        row:Hide()
        editor.rows[index] = row
    end

    local empty = GUI2:CreateText(editor, "", "font.size.md", "color.text.muted", "CENTER")
    empty:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -295)
    empty:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -16, -295)
    empty:SetJustifyH("CENTER")
    editor.empty = empty

    local previous = CreateChromeIconButton(editor, {
        atlas = "uitools-icon-chevron-left",
        size = 24,
        iconSize = HEADER_ICON_SIZE,
        onClick = function() MailAssistant:SetContactEditorPage((editor.page or 1) - 1) end,
    })
    previous:SetPoint("BOTTOMLEFT", editor, "BOTTOMLEFT", 16, 12)
    editor.previous = previous

    local pageText = GUI2:CreateText(editor, "1 / 1", "font.size.sm", "color.text.secondary", "CENTER")
    pageText:SetSize(72, 24)
    pageText:SetPoint("BOTTOM", editor, "BOTTOM", 0, 12)
    pageText:SetJustifyH("CENTER")
    editor.pageText = pageText

    local nextButton = CreateChromeIconButton(editor, {
        atlas = "uitools-icon-chevron-right",
        size = 24,
        iconSize = HEADER_ICON_SIZE,
        onClick = function() MailAssistant:SetContactEditorPage((editor.page or 1) + 1) end,
    })
    nextButton:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -16, 12)
    editor.next = nextButton

    input:SetScript("OnEnterPressed", function() MailAssistant:CommitContactEditor() end)
    input:SetScript("OnEscapePressed", function() MailAssistant:HideContactEditor() end)
    editor:HookScript("OnHide", function()
        if input.ClearFocus then input:ClearFocus() end
        HideSharedTooltip()
    end)
    if type(GUI2.EnableEscapeClose) == "function" then
        GUI2:EnableEscapeClose(editor, function() MailAssistant:HideContactEditor() end)
    end
    if Appearance and type(Appearance.Register) == "function" then
        Appearance:Register(editor, {
            blizzardWindow = "mail",
            themeProvider = function() return NormalizeThemeStyle(GetConfig().themeStyle) end,
            heading = title,
            role = "dialog",
            onRefresh = function(owner, context)
                MailAssistant:ApplyContactEditorAppearance(owner, context)
            end,
        })
    elseif GUI2.ApplyBackdrop then
        GUI2:ApplyBackdrop(editor, "color.surface.popup")
        if GUI2.CreateBorder then GUI2:CreateBorder(editor, "color.popup.border") end
    end
    editor:Hide()
    return editor
end

function MailAssistant:ShowContactEditor(category)
    local editor = self:ConstructContactEditor()
    if not editor then return false end
    if category ~= CATEGORY_ALTS and category ~= CATEGORY_FAVORITES then
        category = runtime.category == CATEGORY_ALTS and CATEGORY_ALTS or CATEGORY_FAVORITES
    end
    editor:Show()
    editor:Raise()
    self:SetContactEditorCategory(category)
    if editor.input then
        editor.input:SetText("")
        if editor.input.SetFocus then editor.input:SetFocus() end
    end
    if editor.classDropdown then editor.classDropdown:SetValue("", true) end
    if editor.factionDropdown then editor.factionDropdown:SetValue("", true) end
    SetEditorFeedback("")
    return true
end

function MailAssistant:ShowContactMenu(button)
    local contact = button and button.contact
    local menu = _G.MenuUtil
    if not contact or not (menu and type(menu.CreateContextMenu) == "function") then return false end
    local title = self:FormatRecipient(contact) or contact.name
    local favorite = self:IsFavorite(contact)
    local ok = pcall(menu.CreateContextMenu, button, function(_, root)
        root:CreateTitle(title)
        if favorite then
            root:CreateButton(T("menu.remove_favorite", "Remove from Favorites"), function()
                MailAssistant:SetFavorite(contact, false)
                MailAssistant:RefreshNow(true)
            end)
        else
            root:CreateButton(T("menu.add_favorite", "Add to Favorites"), function()
                MailAssistant:SetFavorite(contact, true)
                MailAssistant:RefreshNow(true)
            end)
        end
        if contact.source == CATEGORY_ALTS then
            root:CreateButton(T("menu.remove_alt", "Remove from Alts"), function()
                MailAssistant:RemovePersonalContact(CATEGORY_ALTS, contact)
                MailAssistant:RefreshContactEditor()
            end)
        end
    end)
    return ok
end

function MailAssistant:HandleRowClick(button, mouseButton)
    local contact = button and button.contact
    if not contact then return end
    if mouseButton == "RightButton" then
        self:ShowContactMenu(button)
        return
    end
    local editBox = _G.SendMailNameEditBox
    local recipient = self:FormatRecipient(contact)
    if recipient and editBox and type(editBox.SetText) == "function" then editBox:SetText(recipient) end
end

function MailAssistant:SetPage(page)
    local contacts = self:GetContacts(runtime.category)
    local pageSize = math_min(math_max(tonumber(runtime.pageSize) or PAGE_SIZE, 1), PAGE_SIZE)
    local pageCount = math_max(1, math_ceil(#contacts / pageSize))
    runtime.page = math_min(math_max(tonumber(page) or 1, 1), pageCount)
    self:RefreshRows(contacts, pageCount)
end

function MailAssistant:ChangeCategory(category, useDefault)
    local config = GetConfig()
    runtime.category = NormalizeCategory(useDefault and config.defaultCategory or category)
    runtime.page = 1
    if runtime.tabs and runtime.tabs.SetValue then runtime.tabs:SetValue(runtime.category, true) end
    self:RefreshNow(true)
end

function MailAssistant:RefreshRows(contacts, pageCount)
    if not runtime.panel then return end
    contacts = contacts or self:GetContacts(runtime.category)
    local pageSize = math_min(math_max(tonumber(runtime.pageSize) or PAGE_SIZE, 1), PAGE_SIZE)
    pageCount = pageCount or math_max(1, math_ceil(#contacts / pageSize))
    runtime.page = math_min(math_max(runtime.page, 1), pageCount)
    local startIndex = ((runtime.page - 1) * pageSize) + 1
    for rowIndex = 1, PAGE_SIZE do
        local row = runtime.rows[rowIndex]
        local contact = rowIndex <= pageSize and contacts[startIndex + rowIndex - 1] or nil
        row.contact = contact
        if contact then
            row.nameText:SetText(contact.name or "")
            row.nameText:SetTextColor(GetClassColor(contact.classFile))
            row.favoriteIcon:SetShown(runtime.category ~= CATEGORY_FAVORITES and self:IsFavorite(contact))
            row:Show()
        else
            row.nameText:SetText("")
            row.favoriteIcon:Hide()
            row:Hide()
        end
    end
    local empty = #contacts == 0
    if empty then
        runtime.emptyText:SetText(runtime.category == CATEGORY_ALTS
            and T("state.empty_alts", "No saved alts")
            or runtime.category == CATEGORY_FAVORITES
                and T("state.empty_favorites", "No saved favorites")
                or T("state.empty", "No contacts"))
    end
    runtime.emptyText:SetShown(empty)
    local editable = runtime.category == CATEGORY_ALTS or runtime.category == CATEGORY_FAVORITES
    runtime.emptyAddButton:SetText(runtime.category == CATEGORY_ALTS
        and T("editor.add_alt", "Add Alt") or T("editor.add_favorite", "Add Favorite"))
    runtime.emptyAddButton:SetShown(empty and editable)
    runtime.pageText:SetText(string.format("%d / %d", runtime.page, pageCount))
    runtime.previousButton:SetDisabled(runtime.page <= 1)
    runtime.nextButton:SetDisabled(runtime.page >= pageCount)
end

function MailAssistant:RefreshNow(force)
    if not runtime.enabled or not runtime.panel then return false end
    if force ~= true and runtime.panel.IsVisible and not runtime.panel:IsVisible() then return false end
    self:RefreshRows(self:GetContacts(runtime.category))
    return true
end

function MailAssistant:ScheduleRefresh(category)
    if category then self:Invalidate(category) end
    if not runtime.enabled or runtime.category ~= category then return false end
    runtime.refreshToken = runtime.refreshToken + 1
    local token = runtime.refreshToken
    if runtime.refreshTimer then return true end
    if _G.C_Timer and type(_G.C_Timer.NewTimer) == "function" then
        runtime.refreshTimer = _G.C_Timer.NewTimer(0, function()
            runtime.refreshTimer = nil
            if token <= runtime.refreshToken then MailAssistant:RefreshNow(false) end
        end)
    else
        self:RefreshNow(false)
    end
    return true
end

local function IsAddOnLoaded(addonName)
    if _G.C_AddOns and type(_G.C_AddOns.IsAddOnLoaded) == "function" then
        return _G.C_AddOns.IsAddOnLoaded(addonName)
    end
    return type(_G.IsAddOnLoaded) == "function" and _G.IsAddOnLoaded(addonName) or false
end

function MailAssistant:ApplyPanelVisibility()
    if not runtime.panel then return false end
    local sendMailShown = not (_G.SendMailFrame and type(_G.SendMailFrame.IsShown) == "function")
        or _G.SendMailFrame:IsShown()
    local shown = runtime.enabled and sendMailShown and runtime.temporarilyClosed ~= true
    runtime.panel:SetShown(shown)
    if shown then self:RefreshNow(true) end
    return shown
end

function MailAssistant:RefreshAppearance()
    if not (Appearance and type(Appearance.Refresh) == "function") then return false end
    local refreshed = false
    for _, frame in ipairs({ runtime.panel, runtime.contactEditor }) do
        if frame then
            Appearance:Refresh(frame)
            refreshed = true
        end
    end
    return refreshed
end

function MailAssistant:OpenSettings()
    local settings = YUI.Settings or Settings
    if settings and type(settings.OpenComponentFeature) == "function" then
        local ok = pcall(settings.OpenComponentFeature, settings, FEATURE_KEY)
        if ok then return true end
    end
    if Components and type(Components.OpenFeatureSettings) == "function" then
        local ok = pcall(Components.OpenFeatureSettings, Components, FEATURE_KEY)
        if ok then return true end
    end
    return false
end

function MailAssistant:CloseForMailSession()
    runtime.temporarilyClosed = true
    self:StopPanelDrag(true)
    self:HideContactTooltip()
    self:HideContactEditor()
    if runtime.panel then runtime.panel:Hide() end
    return true
end

local function DefaultPanelPlacement()
    return {
        version = 2,
        anchor = { point = "TOPLEFT", relative = "MailFrame", relativePoint = "TOPRIGHT" },
        offset = { x = 6, y = 0 },
    }
end

function MailAssistant:RegisterPanelLayout()
    local panel, layout = runtime.panel, YUI.Layout
    if not (panel and layout and type(layout.RegisterFrame) == "function") then return false end
    if runtime.panelLayout == layout then
        if layout.RefreshFrame then layout:RefreshFrame(PANEL_LAYOUT_ID) end
        return true
    end
    local entry = layout:RegisterFrame(PANEL_LAYOUT_ID, {
        frame = panel,
        title = T("title.short", "Mail Assistant"),
        category = "component",
        editModeCategory = "communication",
        defaultPlacement = DefaultPanelPlacement,
        movable = true,
        snap = true,
        anchorTargets = { "UIParent" },
        lateAnchorTargets = { "MailFrame" },
        isEnabled = function()
            return runtime.enabled and runtime.temporarilyClosed ~= true
                and _G.SendMailFrame and _G.SendMailFrame:IsVisible()
        end,
        openPluginSettings = function() MailAssistant:OpenSettings() end,
    })
    if not entry then return false end
    runtime.panelLayout = layout
    return true
end

function MailAssistant:SyncPanelSize()
    local panel, mailFrame = runtime.panel, _G.MailFrame
    local height = mailFrame and mailFrame:GetHeight()
    if not panel or type(height) ~= "number" or height <= 0 or panel:GetHeight() == height then return false end
    panel:SetHeight(height)
    local layout = YUI.Layout
    if runtime.panelLayout == layout and layout and layout.RefreshFrame and not runtime.panelDragging then
        layout:RefreshFrame(PANEL_LAYOUT_ID)
    end
    return true
end

function MailAssistant:StartPanelDrag()
    local panel, layout = runtime.panel, YUI.Layout
    if runtime.panelDragging or not runtime.enabled or not panel or not panel:IsShown()
        or not (layout and layout.BeginDirectDrag) then return false end
    HideSharedTooltip()
    if not self:RegisterPanelLayout() then return false end
    if layout:BeginDirectDrag(PANEL_LAYOUT_ID, { snap = false }) ~= true then return false end
    runtime.panelDragging = true
    runtime.panelDragLayout = layout
    return true
end

function MailAssistant:StopPanelDrag(cancel)
    if not runtime.panelDragging then return false end
    local layout = runtime.panelDragLayout
    runtime.panelDragging = false
    runtime.panelDragLayout = nil
    return layout and layout:EndDirectDrag(cancel) or false
end

local function UsesInsetLayout(context)
    if type(context) ~= "table" then return false end
    if context.source == "native" then return true end
    return context.source == "ellesmere"
        and context.providerKind == "official"
        and context.customShell ~= true
end

local function GetPanelAccent(context)
    if Appearance and type(Appearance.GetAccentColor) == "function" then
        local ok, r, g, b = pcall(Appearance.GetAccentColor, Appearance, context)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    if context and context.source == "native" then
        return GetColorRGB(_G.NORMAL_FONT_COLOR, 1, 0.82, 0)
    end
    if GUI2 and type(GUI2.GetColor) == "function" then
        local ok, r, g, b = pcall(GUI2.GetColor, GUI2, "color.text.accent")
        if ok and type(r) == "number" then return r, g, b end
    end
    return 1, 0.82, 0
end

local function LayoutEqualTabs(tabs, width)
    if not tabs then return end
    tabs:SetWidth(width)
    local buttons = tabs.buttons
    if type(buttons) ~= "table" or #buttons == 0 then return end
    local previousBoundary = 0
    for index, button in ipairs(buttons) do
        local boundary = math_floor(((index * width) / #buttons) + 0.5)
        local buttonWidth = boundary - previousBoundary
        button:SetSize(buttonWidth, 32)
        button:ClearAllPoints()
        button:SetPoint("LEFT", tabs, "LEFT", previousBoundary, 0)
        if tabs.gui2UnderlineTabStarts then tabs.gui2UnderlineTabStarts[index] = previousBoundary end
        if tabs.gui2UnderlineTabEnds then tabs.gui2UnderlineTabEnds[index] = boundary end
        button.gui2UnderlineTabWidth = buttonWidth
        previousBoundary = boundary
    end
    tabs.contentWidth = width
end

local function CalculatePageSize(layout)
    local height = runtime.panel and type(runtime.panel.GetHeight) == "function"
        and tonumber(runtime.panel:GetHeight()) or nil
    if not height or height <= 0 then return PAGE_SIZE end
    local listTop = -layout.rowY
    local footerTop = height - layout.footerInset - FOOTER_HEIGHT
    local available = footerTop - LIST_FOOTER_GAP - listTop
    return math_min(PAGE_SIZE, math_max(1,
        math_floor((available + ROW_GAP) / (layout.rowHeight + ROW_GAP))))
end

function MailAssistant:ApplyPanelLayout(layoutID, force)
    local layout = PANEL_LAYOUTS[layoutID] or PANEL_LAYOUTS[LAYOUT_COMPACT]
    if runtime.layoutProfile == layoutID and force ~= true then return false end
    local previousPageSize = math_min(math_max(tonumber(runtime.pageSize) or PAGE_SIZE, 1), PAGE_SIZE)
    local firstVisibleIndex = ((runtime.page - 1) * previousPageSize) + 1
    local nextPageSize = CalculatePageSize(layout)
    local pageSizeChanged = previousPageSize ~= nextPageSize
    runtime.layoutProfile = layoutID
    runtime.pageSize = nextPageSize
    if pageSizeChanged then
        runtime.page = math_floor((firstVisibleIndex - 1) / nextPageSize) + 1
    end

    runtime.tabs:ClearAllPoints()
    runtime.tabs:SetPoint("TOPLEFT", runtime.panel, "TOPLEFT", layout.tabX, layout.tabY)
    LayoutEqualTabs(runtime.tabs, layout.tabWidth)

    for index, row in ipairs(runtime.rows) do
        row:SetSize(layout.rowWidth, layout.rowHeight)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", runtime.panel, "TOPLEFT", layout.rowX,
            layout.rowY - ((index - 1) * (layout.rowHeight + ROW_GAP)))
    end

    runtime.emptyText:ClearAllPoints()
    runtime.emptyText:SetPoint("TOPLEFT", runtime.panel, "TOPLEFT", layout.emptyInset, layout.emptyY)
    runtime.emptyText:SetPoint("TOPRIGHT", runtime.panel, "TOPRIGHT", -layout.emptyInset, layout.emptyY)

    runtime.footer:ClearAllPoints()
    runtime.footer:SetPoint("BOTTOMLEFT", runtime.panel, "BOTTOMLEFT", layout.footerInset, layout.footerInset)
    runtime.footer:SetPoint("BOTTOMRIGHT", runtime.panel, "BOTTOMRIGHT", -layout.footerInset, layout.footerInset)
    runtime.footer:SetHeight(FOOTER_HEIGHT)
    return true, pageSizeChanged
end

function MailAssistant:ApplyPanelAppearance(_, context)
    local layoutID = UsesInsetLayout(context) and LAYOUT_INSET or LAYOUT_COMPACT
    local _, pageSizeChanged = self:ApplyPanelLayout(layoutID)

    local r, g, b = GetPanelAccent(context)
    SetColorTable(runtime.tabIndicatorColor, r, g, b, 1)
    SetColorTable(runtime.tabHoverColor, r, g, b, 1)
    if runtime.tabs.RefreshTheme then runtime.tabs:RefreshTheme() end

    if runtime.title then
        if Appearance and type(Appearance.ApplyFont) == "function" then
            Appearance:ApplyFont(runtime.title, context)
        end
        runtime.title:SetTextColor(r, g, b, 1)
    end

    if Appearance and type(Appearance.ApplyFont) == "function" then
        for _, button in ipairs(runtime.tabs.buttons or {}) do
            Appearance:ApplyFont(button.text, context)
        end
        Appearance:ApplyFont(runtime.emptyText, context)
        Appearance:ApplyFont(runtime.pageText, context)
        for _, row in ipairs(runtime.rows) do Appearance:ApplyFont(row.nameText, context) end
    end

    for _, row in ipairs(runtime.rows) do
        row.gui2MailAccent = row.gui2MailAccent or { 1, 0.82, 0, 1 }
        SetColorTable(row.gui2MailAccent, r, g, b, 1)
        row.gui2HoverBorderToken = row.gui2MailAccent
        row.gui2PressedBorderToken = row.gui2MailAccent
        if row.RefreshTheme then row:RefreshTheme() end
    end
    runtime.addContactButton:SetAccent(r, g, b)
    runtime.previousButton:SetAccent(r, g, b)
    runtime.nextButton:SetAccent(r, g, b)
    if pageSizeChanged and runtime.enabled then self:RefreshNow(true) end
end

function MailAssistant:ApplyContactEditorAppearance(_, context)
    local editor = runtime.contactEditor
    if not editor then return false end
    local r, g, b = GetPanelAccent(context)
    SetColorTable(editor.tabIndicatorColor, r, g, b, 1)
    SetColorTable(editor.tabHoverColor, r, g, b, 1)
    if editor.tabs and editor.tabs.RefreshTheme then editor.tabs:RefreshTheme() end
    if editor.title then editor.title:SetTextColor(r, g, b, 1) end
    if editor.add and editor.add.SetTextColor then editor.add:SetTextColor(r, g, b, 1) end
    if editor.previous then editor.previous:SetAccent(r, g, b) end
    if editor.next then editor.next:SetAccent(r, g, b) end
    for _, row in ipairs(editor.rows or {}) do
        row.moveUp:SetAccent(r, g, b)
        row.moveDown:SetAccent(r, g, b)
    end

    if Appearance and type(Appearance.ApplyFont) == "function" then
        for _, region in ipairs({
            editor.title, editor.inputLabel, editor.hint, editor.classLabel, editor.factionLabel,
            editor.feedback, editor.saved, editor.empty, editor.pageText, editor.recentLabel,
            editor.add and editor.add.text,
            editor.classDropdown and editor.classDropdown.text,
            editor.factionDropdown and editor.factionDropdown.text,
        }) do
            Appearance:ApplyFont(region, context)
        end
        for _, button in ipairs(editor.tabs and editor.tabs.buttons or {}) do
            Appearance:ApplyFont(button.text, context)
        end
        for _, row in ipairs(editor.rows or {}) do
            Appearance:ApplyFont(row.name, context)
            if row.remove then Appearance:ApplyFont(row.remove.text, context) end
        end
        for _, button in ipairs(editor.recentButtons or {}) do
            Appearance:ApplyFont(button.text, context)
        end
    end
    return true
end

function MailAssistant:ConstructUI()
    if runtime.panel then return runtime.panel end
    if not (GUI2 and GUI2.Form and _G.MailFrame and _G.SendMailFrame) then return nil end

    local panel = GUI2:CreateFrame(_G.SendMailFrame, {
        width = PANEL_WIDTH,
    })
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", _G.MailFrame, "TOPRIGHT", 6, 0)
    panel:SetWidth(PANEL_WIDTH)
    panel:SetHeight(_G.MailFrame:GetHeight())
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        MailAssistant:SetPage(runtime.page + (delta > 0 and -1 or 1))
    end)
    panel:SetScript("OnShow", function()
        MailAssistant:SyncPanelSize()
        MailAssistant:RegisterPanelLayout()
        MailAssistant:ApplyPanelLayout(runtime.layoutProfile or LAYOUT_COMPACT, true)
        MailAssistant:RefreshNow(true)
    end)
    panel:SetScript("OnHide", function()
        MailAssistant:StopPanelDrag(true)
        HideSharedTooltip()
    end)
    runtime.panel = panel

    local dragHandle = GUI2:CreateFrame(panel, { width = PANEL_WIDTH - 74, height = 22 })
    dragHandle:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -2)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function() MailAssistant:StartPanelDrag() end)
    dragHandle:SetScript("OnDragStop", function() MailAssistant:StopPanelDrag(false) end)
    dragHandle:SetScript("OnEnter", function(owner)
        if not _G.GameTooltip then return end
        _G.GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        _G.GameTooltip:SetText(T("tooltip.move_panel", "Drag the title to move the contact list"))
        _G.GameTooltip:Show()
    end)
    dragHandle:SetScript("OnLeave", HideSharedTooltip)
    runtime.dragHandle = dragHandle

    local title = GUI2:CreateText(panel, T("title.short", "Mail Assistant"), 14, "color.text.accent", "CENTER")
    title:SetPoint("TOP", panel, "TOP", 0, -5)
    title:SetWidth(PANEL_WIDTH - 52)
    title:SetJustifyH("CENTER")
    runtime.title = title

    local addContactButton = CreateChromeIconButton(panel, {
        plusStyle = true,
        tooltip = T("tooltip.add_contact", "Add or manage contacts"),
        onClick = function() MailAssistant:ShowContactEditor(runtime.category) end,
    })
    addContactButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
    runtime.addContactButton = addContactButton

    local closeButton = CreateChromeIconButton(panel, {
        atlas = "uitools-icon-close",
        tooltip = T("tooltip.close_panel", "Close for this mail session"),
        closeStyle = true,
        onClick = function() MailAssistant:CloseForMailSession() end,
    })
    closeButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
    runtime.closeButton = closeButton

    local settingsButton = CreateChromeIconButton(panel, {
        atlas = "Warfronts-BaseMapIcons-Empty-Workshop-Minimap",
        iconSize = HEADER_ICON_SIZE + 2,
        tooltip = T("tooltip.settings", "Settings"),
        hoverWhite = true,
        onClick = function() MailAssistant:OpenSettings() end,
    })
    settingsButton:SetPoint("RIGHT", closeButton, "LEFT", -4, 0)
    runtime.settingsButton = settingsButton

    runtime.tabIndicatorColor = runtime.tabIndicatorColor or { 1, 0.82, 0, 1 }
    runtime.tabHoverColor = runtime.tabHoverColor or { 1, 0.82, 0, 1 }

    local tabs = GUI2.Form:CreateUnderlineTabs(panel, {
        width = COMPACT_TAB_WIDTH,
        height = 32,
        value = runtime.category,
        showBaseline = true,
        equalWidth = true,
        gap = 0,
        fontSizeKey = 12,
        indicatorColor = runtime.tabIndicatorColor,
        hoverColor = runtime.tabHoverColor,
        items = {
            { text = T("category.alts", "Alts"), value = CATEGORY_ALTS },
            { text = T("category.friends", "Online"), value = CATEGORY_FRIENDS },
            { text = T("category.guild", "Guild"), value = CATEGORY_GUILD },
            { text = T("category.favorites", "Favorites"), value = CATEGORY_FAVORITES },
        },
        onChange = function(_, value)
            MailAssistant:ChangeCategory(value)
        end,
    })
    runtime.tabs = tabs

    runtime.rows = {}
    for index = 1, PAGE_SIZE do
        local row = GUI2.Form:CreateButton(panel, {
            text = "",
            width = COMPACT_ROW_WIDTH,
            height = 22,
            tone = "default",
            contentAlign = "left",
            justifyH = "LEFT",
            textLeftPadding = 8,
            onClick = function(button, mouseButton)
                MailAssistant:HandleRowClick(button, mouseButton)
            end,
        })
        if row.text then row.text:Hide() end
        local favoriteIcon = GUI2:CreateText(row, "♥", 12, "color.state.warning", "RIGHT")
        favoriteIcon:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        favoriteIcon:SetWidth(14)
        favoriteIcon:SetJustifyH("RIGHT")
        favoriteIcon:Hide()
        row.favoriteIcon = favoriteIcon
        local nameText = GUI2:CreateText(row, "", "font.size.md", "color.text.primary", "LEFT")
        nameText.gui2ColorKey = nil
        nameText.gui2ColorFallback = nil
        nameText:SetPoint("LEFT", row, "LEFT", 8, 0)
        nameText:SetPoint("RIGHT", favoriteIcon, "LEFT", -4, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        row.nameText = nameText
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:HookScript("OnEnter", function(button) MailAssistant:ShowContactTooltip(button) end)
        row:HookScript("OnLeave", function() MailAssistant:HideContactTooltip() end)
        row:Hide()
        runtime.rows[index] = row
    end

    local emptyText = GUI2:CreateText(panel, T("state.empty", "No contacts"), "font.size.md", "color.text.muted", "CENTER")
    emptyText:SetJustifyH("CENTER")
    runtime.emptyText = emptyText

    local emptyAddButton = GUI2.Form:CreateButton(panel, {
        text = T("editor.add_alt", "Add Alt"),
        width = 118,
        height = 24,
        tone = "default",
        relief = "hairline",
        onClick = function() MailAssistant:ShowContactEditor(runtime.category) end,
    })
    emptyAddButton:SetPoint("TOP", emptyText, "BOTTOM", 0, -10)
    emptyAddButton:Hide()
    runtime.emptyAddButton = emptyAddButton

    local footer = GUI2:CreateFrame(panel, { height = FOOTER_HEIGHT })
    runtime.footer = footer

    local previousButton = CreateChromeIconButton(footer, {
        atlas = "uitools-icon-chevron-left",
        size = PAGER_BUTTON_SIZE,
        iconSize = HEADER_ICON_SIZE,
        onClick = function() MailAssistant:SetPage(runtime.page - 1) end,
    })
    previousButton:SetPoint("LEFT", footer, "LEFT", 0, 0)
    runtime.previousButton = previousButton

    local pageText = GUI2:CreateText(footer, "1 / 1", "font.size.sm", "color.text.secondary", "CENTER")
    pageText:SetSize(72, FOOTER_HEIGHT)
    pageText:SetPoint("CENTER", footer, "CENTER", 0, 0)
    pageText:SetJustifyH("CENTER")
    runtime.pageText = pageText

    local nextButton = CreateChromeIconButton(footer, {
        atlas = "uitools-icon-chevron-right",
        size = PAGER_BUTTON_SIZE,
        iconSize = HEADER_ICON_SIZE,
        onClick = function() MailAssistant:SetPage(runtime.page + 1) end,
    })
    nextButton:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
    runtime.nextButton = nextButton

    runtime.layoutProfile = nil
    runtime.pageSize = PAGE_SIZE
    panel:HookScript("OnSizeChanged", function()
        if runtime.layouting or not runtime.tabs then return end
        runtime.layouting = true
        local _, pageSizeChanged = MailAssistant:ApplyPanelLayout(
            runtime.layoutProfile or LAYOUT_COMPACT,
            true
        )
        runtime.layouting = false
        if pageSizeChanged and runtime.enabled then MailAssistant:RefreshNow(true) end
    end)

    if Appearance and type(Appearance.Register) == "function" then
        Appearance:Register(panel, {
            blizzardWindow = "mail",
            themeProvider = function() return NormalizeThemeStyle(GetConfig().themeStyle) end,
            heading = title,
            role = "mail-assistant",
            onRefresh = function(owner, context)
                MailAssistant:ApplyPanelAppearance(owner, context)
            end,
        })
    else
        self:ApplyPanelAppearance(panel, { source = "dark" })
    end

    _G.SendMailFrame:HookScript("OnShow", function()
        if not runtime.enabled then return end
        runtime.temporarilyClosed = false
        MailAssistant:SyncPanelSize()
        MailAssistant:RegisterPanelLayout()
        MailAssistant:Invalidate(CATEGORY_FRIENDS)
        MailAssistant:Invalidate(CATEGORY_GUILD)
        MailAssistant:ApplyPanelVisibility()
    end)
    _G.MailFrame:HookScript("OnSizeChanged", function()
        if runtime.enabled then MailAssistant:SyncPanelSize() end
    end)
    self:RegisterPanelLayout()
    self:ChangeCategory(nil, true)
    self:ApplyPanelVisibility()
    return panel
end

function MailAssistant:EnsureUI()
    if runtime.panel then return runtime.panel end
    if IsAddOnLoaded(MAIL_ADDON) then return self:ConstructUI() end
    return nil
end

local function OnAddonLoaded(_, addonName)
    if addonName == MAIL_ADDON then MailAssistant:ConstructUI() end
end

local function OnFriendUpdate()
    MailAssistant:ScheduleRefresh(CATEGORY_FRIENDS)
end

local function OnGuildUpdate(event)
    if event == "PLAYER_GUILD_UPDATE" then runtime.guildRosterRequested = false end
    MailAssistant:ScheduleRefresh(CATEGORY_GUILD)
end

local function OnPlayerLogin()
    runtime.recentRecipients = {}
    runtime.pendingRecipient = nil
    MailAssistant:RegisterCurrentCharacter()
end

local function OnSendMail(recipient)
    if runtime.enabled then runtime.pendingRecipient = NonEmptyString(recipient) end
end

local function OnMailSendSuccess()
    local recipient = runtime.pendingRecipient
    runtime.pendingRecipient = nil
    if recipient then MailAssistant:RecordSentRecipient(recipient) end
end

local function OnMailSendCancelled()
    runtime.pendingRecipient = nil
end

function MailAssistant:AttachEvents()
    if runtime.eventsAttached or not Event then return false end
    if not runtime.sendMailHooked and type(Security.SafeHook) == "function" then
        runtime.sendMailHooked = Security.SafeHook("MailAssistant:SendMail", _G, "SendMail", OnSendMail)
    end
    Event:On("ADDON_LOADED", OnAddonLoaded, eventOwner)
    Event:On("PLAYER_LOGIN", OnPlayerLogin, eventOwner)
    Event:On("MAIL_SEND_SUCCESS", OnMailSendSuccess, eventOwner)
    Event:On("MAIL_FAILED", OnMailSendCancelled, eventOwner)
    Event:On("MAIL_CLOSED", OnMailSendCancelled, eventOwner)
    Event:On("FRIENDLIST_UPDATE", OnFriendUpdate, eventOwner, { debounce = 0.05 })
    Event:On("BN_FRIEND_ACCOUNT_ONLINE", OnFriendUpdate, eventOwner, { debounce = 0.05 })
    Event:On("BN_FRIEND_ACCOUNT_OFFLINE", OnFriendUpdate, eventOwner, { debounce = 0.05 })
    Event:On("BN_FRIEND_INFO_CHANGED", OnFriendUpdate, eventOwner, { debounce = 0.05 })
    Event:On("BN_FRIEND_TOON_ONLINE", OnFriendUpdate, eventOwner, { debounce = 0.05 })
    Event:On("BN_FRIEND_TOON_OFFLINE", OnFriendUpdate, eventOwner, { debounce = 0.05 })
    Event:On("GUILD_ROSTER_UPDATE", OnGuildUpdate, eventOwner, { debounce = 0.05 })
    Event:On("PLAYER_GUILD_UPDATE", OnGuildUpdate, eventOwner, { debounce = 0.05 })
    runtime.eventsAttached = true
    return true
end

function MailAssistant:DetachEvents()
    if Event and type(Event.OffOwner) == "function" then Event:OffOwner(eventOwner) end
    runtime.eventsAttached = false
    runtime.refreshToken = runtime.refreshToken + 1
    if runtime.refreshTimer and runtime.refreshTimer.Cancel then runtime.refreshTimer:Cancel() end
    runtime.refreshTimer = nil
    runtime.pendingRecipient = nil
    return true
end

function MailAssistant:SetEnabled(enabled)
    enabled = enabled == true
    if runtime.enabled == enabled and ((enabled and runtime.eventsAttached) or not enabled) then
        if enabled then
            self:ApplyPanelVisibility()
        else
            self:HideContactEditor()
        end
        return false
    end
    runtime.enabled = enabled
    if enabled then
        self:AttachEvents()
        self:RegisterCurrentCharacter()
        local panelExisted = runtime.panel ~= nil
        self:EnsureUI()
        if panelExisted then
            self:SyncPanelSize()
            self:RegisterPanelLayout()
        end
        if panelExisted then self:RefreshAppearance() end
        self:ApplyPanelVisibility()
    else
        self:StopPanelDrag(true)
        self:DetachEvents()
        self:HideContactTooltip()
        self:HideContactEditor()
        if runtime.panel then runtime.panel:Hide() end
    end
    return true
end

function MailAssistant:ApplyProfile()
    self:StopPanelDrag(true)
    local enabled = Components:IsEnabled(FEATURE_KEY)
    self:SetEnabled(enabled)
    if enabled then
        self:RegisterPanelLayout()
        runtime.category = NormalizeCategory(GetConfig().defaultCategory)
        runtime.page = 1
        self:Invalidate()
        self:RefreshAppearance()
        self:ApplyPanelVisibility()
    end
end

function profileOwner:OnProfileChanged()
    MailAssistant:ApplyProfile()
end

local function RegisterProfileCallbacks()
    if runtime.profileCallbacksRegistered or not (YUI.DB and type(YUI.DB.GetAceDB) == "function") then return false end
    local database = YUI.DB:GetAceDB(PRODUCT_ID)
    if not (database and type(database.RegisterCallback) == "function") then return false end
    database.RegisterCallback(profileOwner, "OnProfileChanged", "OnProfileChanged")
    database.RegisterCallback(profileOwner, "OnProfileCopied", "OnProfileChanged")
    database.RegisterCallback(profileOwner, "OnProfileReset", "OnProfileChanged")
    runtime.profileCallbacksRegistered = true
    return true
end

function MailAssistant:ClearPersonalData(silent)
    local store = GetPersonalStore(true)
    if not store then return false end
    store.characters = {}
    store.favorites = {}
    store.schemaVersion = STORE_SCHEMA_VERSION
    runtime.personalDataCleaned = true
    runtime.characterRegistered = false
    runtime.cache = {}
    self:Invalidate()
    self:RefreshNow(true)
    self:RefreshContactEditor()
    if silent ~= true and YUI.Print then YUI:Print(T("clean.complete", "Mail Assistant personal data cleared.")) end
    return true
end

function MailAssistant:ConfirmClearPersonalData()
    if not (Settings and type(Settings.ShowConfirmPopup) == "function") then return false end
    Settings:ShowConfirmPopup(
        T("confirm.clear_data.message", "Clear all saved alts and favorites? Other settings are kept."),
        function() MailAssistant:ClearPersonalData(false) end,
        {
            titleText = T("confirm.clear_data.title", "Clear Mail Assistant Data"),
            acceptText = T("confirm.clear_data.accept", "Clear Data"),
            acceptTone = "danger",
            cancelTone = "default",
        }
    )
    return true
end

local PERSONAL_FIELDS = { "name", "realm", "classFile", "faction", "manuallyAdded", "sortOrder" }
local PERSONAL_MERGE_FIELDS = { "name", "realm", "classFile", "faction", "sortOrder" }

local function CopyPersonalEntry(entry)
    if type(entry) ~= "table" then return nil end
    local result = {}
    for _, field in ipairs(PERSONAL_FIELDS) do result[field] = entry[field] end
    return result
end

local function CopyPersonalStore(store)
    local result = {
        schemaVersion = STORE_SCHEMA_VERSION,
        characters = {},
        favorites = {},
    }
    for key, entry in pairs(store and store.characters or {}) do
        result.characters[key] = CopyPersonalEntry(entry)
    end
    for key, entry in pairs(store and store.favorites or {}) do
        result.favorites[key] = CopyPersonalEntry(entry)
    end
    return result
end

local function NormalizePersonalEntry(entry)
    if type(entry) ~= "table" then return nil, "invalid_personal_data" end
    for field in pairs(entry) do
        if field ~= "name" and field ~= "realm" and field ~= "classFile"
            and field ~= "faction" and field ~= "manuallyAdded" and field ~= "sortOrder" then
            return nil, "invalid_personal_data"
        end
    end
    local name, embeddedRealm = SplitNameRealm(entry.name)
    name = NonEmptyString(name)
    local realm = NormalizeRealm(entry.realm) or embeddedRealm
    if not name or #name > 64 or not realm or #realm > 128 then return nil, "invalid_personal_data" end
    local classFile = NonEmptyString(entry.classFile)
    if classFile and (#classFile > 24 or not classFile:match("^[A-Z]+$")) then
        return nil, "invalid_personal_data"
    end
    local faction = NonEmptyString(entry.faction)
    if faction ~= nil and faction ~= "Horde" and faction ~= "Alliance" then
        return nil, "invalid_personal_data"
    end
    if entry.manuallyAdded ~= nil and type(entry.manuallyAdded) ~= "boolean" then
        return nil, "invalid_personal_data"
    end
    if entry.sortOrder ~= nil and not NormalizeSortOrder(entry.sortOrder) then
        return nil, "invalid_personal_data"
    end
    return {
        name = name,
        realm = realm,
        classFile = classFile,
        faction = faction,
        manuallyAdded = entry.manuallyAdded == true and true or nil,
        sortOrder = entry.sortOrder,
    }, ContactKey(name, realm)
end

local function MergeMissingFields(target, source)
    for _, field in ipairs(PERSONAL_MERGE_FIELDS) do
        if target[field] == nil and source[field] ~= nil then target[field] = source[field] end
    end
    return target
end

function MailAssistant:NormalizePersonalData(value)
    if type(value) ~= "table" or type(value.characters) ~= "table" or type(value.favorites) ~= "table" then
        return nil, "invalid_personal_data"
    end
    for field in pairs(value) do
        if field ~= "characters" and field ~= "favorites" then return nil, "invalid_personal_data" end
    end
    local result = { characters = {}, favorites = {} }
    for _, collection in ipairs({ "characters", "favorites" }) do
        local pending = {}
        for sourceKey, entry in pairs(value[collection]) do
            pending[#pending + 1] = { sourceKey = tostring(sourceKey), entry = entry }
        end
        table_sort(pending, function(left, right) return left.sourceKey < right.sourceKey end)
        for _, item in ipairs(pending) do
            local normalized, key = NormalizePersonalEntry(item.entry)
            if not normalized then return nil, key end
            if result[collection][key] then
                MergeMissingFields(result[collection][key], normalized)
            else
                result[collection][key] = normalized
            end
        end
    end
    return result
end

function MailAssistant:CapturePersonalData()
    local store = GetPersonalStore(false)
    local copy = CopyPersonalStore(store)
    local data = {
        characters = copy.characters,
        favorites = copy.favorites,
    }
    return self:NormalizePersonalData(data)
end

function MailAssistant:SnapshotPersonalData()
    if not (YUI.DB and type(YUI.DB.GetGlobal) == "function") then return nil, "global_unavailable" end
    local global = YUI.DB:GetGlobal(PRODUCT_ID)
    if type(global) ~= "table" then return nil, "global_unavailable" end
    return {
        present = type(global[STORE_KEY]) == "table",
        data = type(global[STORE_KEY]) == "table" and CopyPersonalStore(global[STORE_KEY]) or nil,
    }
end

function MailAssistant:RefreshPersonalData()
    runtime.cache = {}
    self:Invalidate()
    self:RefreshNow(true)
    if runtime.contactEditor and runtime.contactEditor:IsShown() then self:RefreshContactEditor() end
    return true
end

function MailAssistant:ApplyPersonalData(data)
    local normalized, code = self:NormalizePersonalData(data)
    if not normalized then return nil, code end
    local store = GetPersonalStore(true)
    if not store then return nil, "global_unavailable" end
    for _, collection in ipairs({ "characters", "favorites" }) do
        for key, imported in pairs(normalized[collection]) do
            if type(store[collection][key]) == "table" then
                MergeMissingFields(store[collection][key], imported)
            else
                store[collection][key] = CopyPersonalEntry(imported)
            end
        end
    end
    store.schemaVersion = STORE_SCHEMA_VERSION
    return self:RefreshPersonalData()
end

function MailAssistant:RestorePersonalData(snapshot)
    if type(snapshot) ~= "table" or not (YUI.DB and type(YUI.DB.GetGlobal) == "function") then
        return nil, "global_unavailable"
    end
    local global = YUI.DB:GetGlobal(PRODUCT_ID)
    if type(global) ~= "table" then return nil, "global_unavailable" end
    global[STORE_KEY] = snapshot.present and CopyPersonalStore(snapshot.data) or nil
    return self:RefreshPersonalData()
end

local Feature = {
    product = PRODUCT_ID,
    storageKey = FEATURE_KEY,
    name = T("feature.name", "Mail Assistant"),
    description = T("feature.description", "Adds account characters, online friends, guild members, and favorites beside the send-mail frame."),
    tags = { "交易社交" },
    order = 404,
    default = true,
    settingsMode = "inline",
    sourceRoot = "Components\\MailAssistant",
    assetFolders = { "Components\\MailAssistant\\Media" },
    modSwitchImage = "modswitch\\mailassistant-bg.png",
    modSwitchImageCrop = false,
    versions = { "mainline" },
    transfer = {
        personalData = {
            schemaVersion = PERSONAL_DATA_SCHEMA_VERSION,
            capture = function() return MailAssistant:CapturePersonalData() end,
            normalize = function(data) return MailAssistant:NormalizePersonalData(data) end,
            snapshot = function() return MailAssistant:SnapshotPersonalData() end,
            apply = function(data) return MailAssistant:ApplyPersonalData(data) end,
            restore = function(snapshot) return MailAssistant:RestorePersonalData(snapshot) end,
        },
        refresh = function() return MailAssistant:RefreshPersonalData() end,
    },
    callback = function(enabled) MailAssistant:SetEnabled(enabled) end,
}

function Feature:GetOptions()
    local config = GetConfig()
    return {
        {
            type = "row",
            gap = 24,
            children = {
                {
                    type = "dropdown",
                    label = T("settings.default_category", "Default Category"),
                    width = 220,
                    options = {
                        { text = T("category.alts", "Alts"), value = CATEGORY_ALTS },
                        { text = T("category.friends", "Online Friends"), value = CATEGORY_FRIENDS },
                        { text = T("category.guild", "Guild"), value = CATEGORY_GUILD },
                        { text = T("category.favorites", "Favorites"), value = CATEGORY_FAVORITES },
                    },
                    get = function() return NormalizeCategory(config.defaultCategory) end,
                    set = function(value)
                        config.defaultCategory = NormalizeCategory(value)
                        MailAssistant:ChangeCategory(nil, true)
                    end,
                },
                {
                    type = "checkbox",
                    label = T("settings.auto_track_alts", "Automatically Record Alts"),
                    tooltip = T("settings.auto_track_alts_tooltip", "Record the current character when logging in."),
                    width = 260,
                    get = function() return config.autoTrackAlts == true end,
                    set = function(value) config.autoTrackAlts = value == true end,
                },
            },
        },
        {
            type = "row",
            gap = 24,
            children = {
                {
                    type = "dropdown",
                    label = T("settings.theme_style", "Skin Style"),
                    width = 220,
                    options = {
                        { text = T("settings.theme.auto", "Auto"), value = "auto" },
                        { text = T("settings.theme.native", "Native"), value = "native" },
                        { text = T("settings.theme.modern", "Modern"), value = "dark" },
                    },
                    default = "auto",
                    get = function() return NormalizeThemeStyle(config.themeStyle) end,
                    set = function(value) config.themeStyle = NormalizeThemeStyle(value) end,
                    onChange = function() MailAssistant:RefreshAppearance() end,
                },
                {
                    type = "button",
                    label = T("settings.manage_contacts", "Manage Contacts"),
                    width = 180,
                    tone = "accent",
                    onClick = function() MailAssistant:ShowContactEditor() end,
                },
            },
        },
        {
            type = "row",
            children = {
                {
                    type = "button",
                    label = T("settings.clear_data", "Clear All Data"),
                    width = 180,
                    tone = "danger",
                    onClick = function() MailAssistant:ConfirmClearPersonalData() end,
                },
            },
        },
        {
            type = "text",
            label = T("settings.favorite_hint", "Use the contact manager to add or remove alts and favorites."),
            colorKey = "color.text.secondary",
        },
    }
end

Components:RegisterFeature(FEATURE_KEY, Feature)

if not RegisterProfileCallbacks() and Event then
    Event:Once("YUI_DB_READY", function()
        RegisterProfileCallbacks()
    end, bootstrapOwner)
end

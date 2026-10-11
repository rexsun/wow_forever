local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.Components then return end

local Components = YUI.Components
local GUI2 = YUI.GUI2
local Event = YUI.Event
local Security = (YUI.API and YUI.API.Security) or YUI.WOW_API or {}
local Social = (YUI.API and YUI.API.Social) or YUI.WOW_API or {}
local UnitAPI = (YUI.API and YUI.API.Unit) or YUI.WOW_API or {}
local Icons = (YUI.API and YUI.API.Icons) or (YUI.WOW_API and YUI.WOW_API.Icons) or {}
local L = YUI.Locale and YUI.Locale:Get("WhisperManager") or {}

local FEATURE_KEY = "WhisperManager"
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or (_G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME] and _G.YUI_CORE_EMBED_STATE[ADDON_NAME].productId)
    or YUI.ProductId or "suite"
local STORAGE_KEY = "WhisperManager"
local CONFIG_KEY = "WhisperManager_Config"
local LIST_WINDOW_WIDTH = 300
local DETAIL_WINDOW_WIDTH = 650
local DETAIL_WINDOW_GAP = 2
local ROW_COUNT = 9
local LIST_PANEL_WIDTH = 272
local LIST_ROW_WIDTH = 256
local LIST_ROW_ICON_LEFT = 8
local LIST_ROW_ICON_SIZE = 16
local LIST_ROW_TEXT_GAP = 6
local LIST_ROW_UNREAD_WIDTH = 34
local LIST_ROW_UNREAD_DOT_WIDTH = 12
local LIST_ROW_FAVORITE_WIDTH = 16
local LIST_ROW_RIGHT_PADDING = 8
local LIST_ROW_COLUMN_GAP = 4
local LIST_FILTER_LABEL_WIDTH = 40
local LIST_FILTER_DROPDOWN_WIDTH = 110
local LIST_UNREAD_SUMMARY_WIDTH = 78
local DEFAULT_MAX_MESSAGES = 500
local DEFAULT_MAX_CONVERSATIONS = 80
local WINDOW_MIN_WIDTH = LIST_WINDOW_WIDTH
local WINDOW_HEIGHT = 420
local LIST_WINDOW_X_OFFSET = -330
local ACTION_BUTTON_WIDTH = 78
local ACTION_BUTTON_GAP = 6
local CLOSE_BUTTON_SIZE = 16
local MESSAGE_PANEL_PADDING = 8
local MESSAGE_SCROLLBAR_INSET = 24
local MESSAGE_ROW_SPACING = 3
local MESSAGE_MIN_ROW_HEIGHT = 16
local MESSAGE_DIVIDER_HEIGHT = 22
local MESSAGE_SEPARATOR_WIDTH = 2
local MESSAGE_SEPARATOR_GAP = 6
local MESSAGE_BODY_GAP = 8
local MESSAGE_SCROLL_STEP = 32
local COPY_EDIT_INSET = 8
local COPY_EDIT_LINE_HEIGHT = 18
local HOVER_HIDE_DELAY = 0.22
local TITLE_ICON_SIZE = 16
local TITLE_GAP = 5
local TITLE_STATUS_WIDTH = 62
local TITLE_RELATION_WIDTH = 82
local TITLE_RIGHT_RESERVED = TITLE_RELATION_WIDTH + 10
local TIMESTAMP_SAMPLE = "[00/00 00:00:00]"
local TIMESTAMP_COLOR = { r = 0.56, g = 0.56, b = 0.596 }
local INCOMING_MESSAGE_COLOR = { r = 1.00, g = 0.48, b = 0.88 }
local OUTGOING_MESSAGE_COLOR = { r = 0.42, g = 0.72, b = 1.00 }
local DIVIDER_COLOR = { r = 1.00, g = 0.23, b = 0.31 }
local BNET_NAME_COLOR = { r = 0.20, g = 0.68, b = 1.00, a = 1 }
local GM_NAME_COLOR = { r = 0.35, g = 0.85, b = 1.00, a = 1 }
local UNREAD_DOT_COLOR = { r = 1.00, g = 0.18, b = 0.18, a = 1 }
local UNREAD_ROW_BG_COLOR = { r = 0.20, g = 0.78, b = 0.34, a = 0.16 }
local FRIEND_TAG_COLOR = { r = 0.36, g = 0.95, b = 0.42 }
local STRANGER_TAG_COLOR = { r = 1.00, g = 0.56, b = 0.12 }
local SELF_TAG_COLOR = { r = 1.00, g = 1.00, b = 1.00 }
local ONLINE_STATUS_COLOR = { r = 0.30, g = 1.00, b = 0.35 }
local OFFLINE_STATUS_COLOR = { r = 0.65, g = 0.68, b = 0.76 }

local tinsert = table.insert
local tremove = table.remove
local table_concat = table.concat
local wipe = wipe
local format = string.format
local date = date
local time = time
local strsub = string.sub
local strfind = string.find
local strmatch = string.match
local strbyte = string.byte
local strchar = string.char
local gsub = string.gsub
local ipairs = ipairs
local pairs = pairs
local select = select
local type = type
local tonumber = tonumber
local pcall = pcall
local unpack = unpack or table.unpack

local ChatFrame_OnHyperlinkShow = _G.ChatFrame_OnHyperlinkShow
local ChatFrame_GetMessageEventFilters = _G.ChatFrame_GetMessageEventFilters
local DEFAULT_CHAT_FRAME = _G.DEFAULT_CHAT_FRAME
local SetItemRef = _G.SetItemRef

local GMChatFrame_IsGM = _G.GMChatFrame_IsGM

local defaults = {
    historyEnabled = true,
    sound = true,
    soundSelection = { kind = "native" },
    applyFilters = true,
    receiveOnly = false,
    timestamp = true,
    showRealm = true,
    foreignOnly = true,
    gradient = {
        enabled = false,
    },
    window = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = LIST_WINDOW_X_OFFSET,
        y = 0,
        width = LIST_WINDOW_WIDTH,
        height = WINDOW_HEIGHT,
    },
}

local function NewRuntimeCache()
    return setmetatable({}, { __mode = "k" })
end

local Manager = YUI.WhisperManager or {}
YUI.WhisperManager = Manager
local soundOwner = {}
local soundOptions = { nativeSound = "TELL_MESSAGE", defaultChannel = "Master" }
local function PlayNotification(db)
    if YUI.NotificationSound then
        -- Arrival payloads (including restricted values) never enter sound services.
        Manager.soundSerial = (Manager.soundSerial or 0) + 1
        return YUI.NotificationSound:Play(soundOwner, tostring(Manager.soundSerial), db.soundSelection, soundOptions)
    end
end
local function CancelNotifications()
    if YUI.NotificationSound then YUI.NotificationSound:CancelOwner(soundOwner) end
end
Manager.callbacks = Manager.callbacks or {}
Manager.currentPage = Manager.currentPage or 1
Manager.listTab = Manager.listTab or "messages"
Manager.listFilter = Manager.listFilter or (Manager.listTab == "favorites" and "favorites" or "all")
Manager.unfavoritedVisibleKeys = Manager.unfavoritedVisibleKeys or {}
Manager.featureEnabled = Manager.featureEnabled == true
Manager.enabled = Manager.enabled == true
Manager.testSequence = Manager.testSequence or 0
Manager.headerCache = Manager.headerCache or NewRuntimeCache()
Manager.messageCache = Manager.messageCache or NewRuntimeCache()
Manager.playerInfoCache = Manager.playerInfoCache or {}
Manager.pendingWhoNames = Manager.pendingWhoNames or {}
Manager.pendingWhoLookup = Manager.pendingWhoLookup or {}
Manager.pendingWhoQueryLookup = Manager.pendingWhoQueryLookup or {}
Manager.whoQueue = Manager.whoQueue or {}
Manager.whoQueued = Manager.whoQueued or {}
Manager.whoCooldown = Manager.whoCooldown or {}
Manager.selectionLocked = Manager.selectionLocked == true
Manager.hoverHideToken = Manager.hoverHideToken or 0

local TEST_CLASSES = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "DRUID", "HUNTER", "PALADIN", "SHAMAN", "WARLOCK", "DEMONHUNTER", "EVOKER", "MONK", "DEATHKNIGHT" }
Manager.testRaces = Manager.testRaces or {
    { raceFile = "Human", gender = 2 },
    { raceFile = "Dwarf", gender = 3 },
    { raceFile = "NightElf", gender = 2 },
    { raceFile = "Gnome", gender = 3 },
    { raceFile = "Draenei", gender = 2 },
    { raceFile = "Orc", gender = 3 },
    { raceFile = "Scourge", gender = 2 },
    { raceFile = "Tauren", gender = 3 },
    { raceFile = "Troll", gender = 2 },
    { raceFile = "BloodElf", gender = 3 },
}
local FAVORITE_MARK = "♥"
local UNREAD_MARK = "●"
local STORAGE_VERSION = 2
local STORAGE_PREFIX = "YWM1:"
local STORAGE_FALLBACK_PREFIX = "YWM0:"
local STORAGE_COMPRESSION_CONFIG = { level = 1 }
local PLAYER_INFO_CACHE_TTL = 300
local WHO_QUERY_COOLDOWN = 60
local WHO_QUERY_THROTTLE = 5
local WHO_PENDING_TTL = 45
local PRIVATE_FIELDS = {
    key = "encodedKey",
    name = "encodedName",
    displayName = "encodedDisplayName",
    battleTag = "encodedBattleTag",
    bnAccountName = "encodedBNAccountName",
}
local CONTROL_FIELDS = {
    "kind",
    "class",
    "protected",
    "new",
    "unreadCount",
    "firstUnreadIndex",
}

local function T(key)
    return (L and L[key]) or key
end

local function FormatLocale(key, ...)
    local text = T(key)
    if select("#", ...) == 0 then
        return text
    end

    local ok, result = pcall(format, text, ...)
    if ok then
        return result
    end

    return text
end

local function ColorByte(value)
    value = tonumber(value) or 1
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    return math.floor((value * 255) + 0.5)
end

local function ColorText(text, color)
    if not color then
        return text or ""
    end

    return format("|cff%02x%02x%02x%s|r", ColorByte(color.r), ColorByte(color.g), ColorByte(color.b), text or "")
end

local function NormalizeColor(color)
    if not color then
        return nil
    end

    if type(color) == "table" then
        if color.GetRGB then
            local r, g, b = color:GetRGB()
            return { r = r or 1, g = g or 1, b = b or 1, a = color.a or 1 }
        end
        if color.r or color.g or color.b then
            return { r = color.r or 1, g = color.g or 1, b = color.b or 1, a = color.a or 1 }
        end
        if color[1] or color[2] or color[3] then
            return { r = color[1] or 1, g = color[2] or 1, b = color[3] or 1, a = color[4] or 1 }
        end
    end

    return nil
end

local function IsSecretValue(value)
    if Security and Security.IsSecretValue and Security.IsSecretValue(value) then
        return true
    end

    if type(_G.issecretvalue) == "function" then
        local ok, result = pcall(_G.issecretvalue, value)
        return ok and result == true
    end

    return false
end

local function HasAnySecretValue(...)
    if type(_G.hasanysecretvalues) == "function" then
        local ok, result = pcall(_G.hasanysecretvalues, ...)
        if ok and result then
            return true
        end
    end

    for i = 1, select("#", ...) do
        if IsSecretValue(select(i, ...)) then
            return true
        end
    end

    return false
end

local function GetRealm()
    local realm = UnitAPI.GetNormalizedRealmName and UnitAPI.GetNormalizedRealmName()
    if type(realm) == "string" and realm ~= "" then
        return realm
    end

    realm = UnitAPI.GetRealmName and UnitAPI.GetRealmName()
    if type(realm) == "string" and realm ~= "" then
        return (gsub(realm, "%s+", ""))
    end

    return nil
end

function Manager:ParseNameRealm(value)
    if type(value) ~= "string" then
        return nil, nil
    end

    local name, realm = strmatch(value, "^([^%-]+)%-(.+)$")
    return name or value, realm
end

function Manager:GetNormalizedRealm()
    if type(self.normalizedRealm) == "string" and self.normalizedRealm ~= "" then
        return self.normalizedRealm
    end

    local realm = GetRealm()
    if type(realm) == "string" and realm ~= "" then
        self.normalizedRealm = realm
    end
    return self.normalizedRealm
end

function Manager:NormalizePlayerFullName(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end

    local _, realm = self:ParseNameRealm(value)
    if type(realm) == "string" and realm ~= "" then
        return value
    end

    realm = self:GetNormalizedRealm()
    if type(realm) == "string" and realm ~= "" then
        return value .. "-" .. realm
    end
    return value
end

local ResolveBNRuntimeInfo
local GetDB
local FindConversation
local TrimHistory

local function GetPlayerInfoByGUIDSafe(guid)
    if type(guid) ~= "string" or guid == "" or not UnitAPI.GetPlayerInfoByGUID then
        return nil
    end

    return UnitAPI.GetPlayerInfoByGUID(guid)
end

local function GetClassByGUID(guid)
    local info = GetPlayerInfoByGUIDSafe(guid)
    return info and info.classFile or nil
end

local function NonEmptyString(value)
    if type(value) == "string" and value ~= "" then
        return value
    end
end

function Manager:NormalizePlayerIdentity(data)
    if type(data) ~= "table" or data.kind ~= "player" then
        return false
    end

    local name = NonEmptyString(data.name)
    if not name and type(data.key) == "string" then
        name = strmatch(data.key, "^player:(.+)$")
    end

    local fullName = self:NormalizePlayerFullName(name)
    if not fullName then
        return false
    end

    local oldKey = data.key
    local key = "player:" .. fullName
    local changed = data.name ~= fullName or data.key ~= key
    data.name = fullName
    data.key = key
    if changed then
        if oldKey and Manager.selectedKey == oldKey then
            Manager.selectedKey = key
        end
        if oldKey and Manager.pendingUnreadDividerKey == oldKey then
            Manager.pendingUnreadDividerKey = key
        end
    end
    return changed
end

local function IsBattleTag(value)
    return type(value) == "string" and strmatch(value, "^.+#%d+$") ~= nil
end

local function GetBattleTagName(value)
    if not IsBattleTag(value) then
        return nil
    end
    return strmatch(value, "^(.+)#%d+$")
end

local function NormalizeStoredBNIdentity(data)
    if type(data) ~= "table" then
        return
    end
    if data.class == "BN" then
        data.kind = "bn"
    end
    if data.kind ~= "bn" then
        return
    end

    local battleTag = (IsBattleTag(data.battleTag) and data.battleTag)
        or (IsBattleTag(data.name) and data.name)
    if battleTag then
        data.battleTag = battleTag
        data.name = battleTag
        data.key = "bn:" .. battleTag
        return
    end

    if type(data.name) ~= "string" or data.name == "" then
        data.name = NonEmptyString(data.bnAccountName)
            or NonEmptyString(data.displayName)
            or (type(data.key) == "string" and strmatch(data.key, "^bn:(.+)$"))
    end
    if (type(data.key) ~= "string" or data.key == "") and data.name then
        data.key = "bn:" .. data.name
    end
end

local function GetDeflate()
    if not LibStub or not LibStub.GetLibrary then
        return nil
    end

    local ok, lib = pcall(LibStub.GetLibrary, LibStub, "LibDeflate", true)
    if ok then
        return lib
    end
end

local function HexByte(value)
    return format("%02x", value)
end

local function EncodeFallback(text)
    local parts = {}
    for index = 1, #text do
        local byte = strbyte(text, index) or 0
        parts[index] = HexByte((byte + ((index * 73 + 41) % 251)) % 256)
    end
    return STORAGE_FALLBACK_PREFIX .. table_concat(parts, "")
end

local function DecodeFallback(payload)
    if type(payload) ~= "string" then
        return nil
    end

    local parts = {}
    local partIndex = 1
    for index = 1, #payload, 2 do
        local hex = strsub(payload, index, index + 1)
        local byte = tonumber(hex, 16)
        if not byte then
            return nil
        end
        parts[partIndex] = strchar((byte - ((partIndex * 73 + 41) % 251)) % 256)
        partIndex = partIndex + 1
    end

    return table_concat(parts, "")
end

local function EncodePrivateString(value)
    if type(value) ~= "string" then
        return nil
    end

    local deflate = GetDeflate()
    if deflate and deflate.CompressDeflate and deflate.EncodeForPrint then
        local ok, compressed = pcall(deflate.CompressDeflate, deflate, value, STORAGE_COMPRESSION_CONFIG)
        if ok and type(compressed) == "string" then
            local encodedOk, encoded = pcall(deflate.EncodeForPrint, deflate, compressed)
            if encodedOk and type(encoded) == "string" then
                return STORAGE_PREFIX .. encoded
            end
        end
    end

    return EncodeFallback(value)
end

local function DecodePrivateString(value)
    if type(value) ~= "string" then
        return nil
    end

    if strsub(value, 1, #STORAGE_PREFIX) == STORAGE_PREFIX then
        local deflate = GetDeflate()
        if not deflate or not deflate.DecodeForPrint or not deflate.DecompressDeflate then
            return nil
        end

        local payload = strsub(value, #STORAGE_PREFIX + 1)
        local ok, compressed = pcall(deflate.DecodeForPrint, deflate, payload)
        if ok and type(compressed) == "string" then
            local decompressedOk, decompressed = pcall(deflate.DecompressDeflate, deflate, compressed)
            if decompressedOk and type(decompressed) == "string" then
                return decompressed
            end
        end
        return nil
    end

    if strsub(value, 1, #STORAGE_FALLBACK_PREFIX) == STORAGE_FALLBACK_PREFIX then
        return DecodeFallback(strsub(value, #STORAGE_FALLBACK_PREFIX + 1))
    end

    return value
end

local function EncodePrivateValue(value)
    local valueType = type(value)
    if valueType ~= "string" and valueType ~= "number" then
        return nil, nil
    end

    return EncodePrivateString(tostring(value)), valueType == "number" and "number" or nil
end

local function DecodePrivateValue(encoded, legacy, valueType)
    local value
    if encoded ~= nil then
        value = DecodePrivateString(encoded)
    elseif type(legacy) == "string" then
        value = legacy
    elseif type(legacy) == "number" then
        value = legacy
    end

    if valueType == "number" and value ~= nil then
        return tonumber(value) or value
    end
    return value
end

local function EncodeStoredMessage(message)
    local stored = {
        time = message and message.time or nil,
        inform = message and message.inform and true or nil,
        receiptOrder = message and message.receiptOrder or nil,
    }
    if message and message.text ~= nil then
        stored.encodedText = EncodePrivateString(tostring(message.text))
    end
    if message and message.conversationKey then
        stored.encodedConversationKey = EncodePrivateString(message.conversationKey)
    end
    return stored
end

local function DecodeStoredMessage(message)
    if type(message) ~= "table" then
        return nil
    end

    return {
        text = DecodePrivateValue(message.encodedText, message.text) or "",
        time = message.time,
        inform = message.inform and true or nil,
        receiptOrder = tonumber(message.receiptOrder),
        conversationKey = DecodePrivateString(message.encodedConversationKey),
    }
end

local function SyncStoredControl(data)
    local stored = data and data._store
    if type(stored) ~= "table" then
        return
    end

    stored.storageVersion = STORAGE_VERSION
    for _, field in ipairs(CONTROL_FIELDS) do
        stored[field] = data[field]
    end
    stored.online = nil
end

local function SyncStoredIdentity(data)
    local stored = data and data._store
    if type(stored) ~= "table" then
        return
    end

    stored.storageVersion = STORAGE_VERSION
    for field, storedField in pairs(PRIVATE_FIELDS) do
        local encoded, valueType = EncodePrivateValue(data[field])
        stored[storedField] = encoded
        stored[storedField .. "Type"] = valueType
        stored[field] = nil
    end
    stored.encodedBnid = nil
    stored.encodedBnidType = nil
    stored.bnid = nil
    SyncStoredControl(data)
end

local function SyncStoredMessages(data)
    local stored = data and data._store
    if type(stored) ~= "table" then
        return
    end

    stored.storageVersion = STORAGE_VERSION
    stored.messages = {}
    stored.encodedMessages = nil
    for _, message in ipairs(data.messages or {}) do
        tinsert(stored.messages, EncodeStoredMessage(message))
    end
end

local function EncodeStoredConversation(data)
    local stored = {
        storageVersion = STORAGE_VERSION,
        messages = {},
    }
    data._store = stored
    SyncStoredIdentity(data)
    SyncStoredMessages(data)
    return stored
end

local function ResetRuntimeCaches()
    Manager.headerCache = NewRuntimeCache()
    Manager.messageCache = NewRuntimeCache()
    Manager.playerInfoCache = {}
    Manager.pendingWhoNames = {}
    Manager.pendingWhoLookup = {}
    Manager.pendingWhoQueryLookup = {}
    Manager.whoQueue = {}
    Manager.whoQueued = {}
    Manager.whoCooldown = {}
end

local function GetStoreToken(store)
    if type(store) ~= "table" then
        return nil
    end
    return store.encodedKey or store.key
end

local function HasLegacyIdentity(store)
    if type(store) ~= "table" then
        return false
    end

    for field in pairs(PRIVATE_FIELDS) do
        if store[field] ~= nil then
            return true
        end
    end
    if store.bnid ~= nil or store.encodedBnid ~= nil then
        return true
    end
    return false
end

local function StoredMessagesNeedMigration(store, storedMessages)
    if type(store) ~= "table" then
        return false
    end
    if store.encodedMessages ~= nil then
        return true
    end
    if type(storedMessages) ~= "table" then
        return false
    end

    for _, message in ipairs(storedMessages) do
        if type(message) == "table" and message.text ~= nil then
            return true
        end
    end
    return false
end

local function DecodeStoredHeader(stored)
    if type(stored) ~= "table" then
        return nil
    end

    local data = {}
    for field, storedField in pairs(PRIVATE_FIELDS) do
        data[field] = DecodePrivateValue(stored[storedField], stored[field], stored[storedField .. "Type"])
    end
    for _, field in ipairs(CONTROL_FIELDS) do
        data[field] = stored[field]
    end
    NormalizeStoredBNIdentity(data)
    if type(data.key) ~= "string" or data.key == "" then
        return nil
    end

    data._store = stored
    return data
end

local function EnsureRuntimeHeader(stored)
    if type(stored) ~= "table" then
        return nil
    end

    if type(Manager.headerCache) ~= "table" then
        Manager.headerCache = NewRuntimeCache()
    end

    local data = Manager.headerCache[stored]
    if data then
        return data
    end

    data = DecodeStoredHeader(stored)
    if not data then
        return nil
    end

    Manager.headerCache[stored] = data
    if stored.storageVersion ~= STORAGE_VERSION or HasLegacyIdentity(stored) then
        SyncStoredIdentity(data)
    end

    return data
end

local function EnsureRuntimeMessages(dataOrStore)
    local stored = type(dataOrStore) == "table" and (dataOrStore._store or dataOrStore) or nil
    if type(stored) ~= "table" then
        return nil
    end

    if type(Manager.messageCache) ~= "table" then
        Manager.messageCache = NewRuntimeCache()
    end

    local data = Manager.headerCache and Manager.headerCache[stored] or nil
    if not data then
        data = EnsureRuntimeHeader(stored)
    end
    if not data then
        return nil
    end

    local messages = Manager.messageCache[stored]
    if not messages then
        messages = {}
        local storedMessages = stored.messages or stored.encodedMessages
        if type(storedMessages) == "table" then
            for _, message in ipairs(storedMessages) do
                local decoded = DecodeStoredMessage(message)
                if decoded then
                    tinsert(messages, decoded)
                end
            end
        end
        Manager.messageCache[stored] = messages
        if StoredMessagesNeedMigration(stored, storedMessages) then
            data.messages = messages
            SyncStoredMessages(data)
        end
    end

    data.messages = messages
    return messages
end

local function GetLatestRuntimeMessage(dataOrStore)
    local stored = type(dataOrStore) == "table" and (dataOrStore._store or dataOrStore) or nil
    if type(stored) ~= "table" then
        return nil
    end

    local cached = Manager.messageCache and Manager.messageCache[stored]
    if cached and cached[#cached] then
        return cached[#cached]
    end

    local storedMessages = stored.messages or stored.encodedMessages
    if type(storedMessages) ~= "table" then
        return nil
    end

    return DecodeStoredMessage(storedMessages[#storedMessages])
end

local function InsertConversation(db, index, data)
    if not db or not data then
        return
    end

    if type(db.history) ~= "table" then
        db.history = {}
    end

    local stored = data._store or EncodeStoredConversation(data)
    data._store = stored
    if type(Manager.headerCache) ~= "table" then
        Manager.headerCache = NewRuntimeCache()
    end
    Manager.headerCache[stored] = data
    if index then
        tinsert(db.history, index, stored)
    else
        tinsert(db.history, stored)
    end
    return stored
end

local function RemoveConversationAt(db, index)
    if not db or not index then
        return nil
    end

    if type(db.history) ~= "table" then
        return nil
    end

    local stored = tremove(db.history, index)
    if not stored then
        return nil
    end

    local data = Manager.headerCache and Manager.headerCache[stored] or nil
    if Manager.headerCache then
        Manager.headerCache[stored] = nil
    end
    if Manager.messageCache then
        Manager.messageCache[stored] = nil
    end

    return data
end

function Manager:RemoveUnprotectedConversations(db)
    local history = db and db.history
    if type(history) ~= "table" then
        return false
    end

    local removed = false
    for index = #history, 1, -1 do
        local stored = history[index]
        if type(stored) ~= "table" or not stored.protected then
            local token = GetStoreToken(stored)
            if token and Manager.unfavoritedVisibleKeys then
                Manager.unfavoritedVisibleKeys[token] = nil
            end
            RemoveConversationAt(db, index)
            removed = true
        end
    end
    return removed
end

function Manager:SyncStoredConversation(stored)
    if type(stored) ~= "table" then
        return
    end

    local data = Manager.headerCache and Manager.headerCache[stored] or EnsureRuntimeHeader(stored)
    if not data then
        return
    end

    SyncStoredIdentity(data)

    local messages = Manager.messageCache and Manager.messageCache[stored] or nil
    if messages then
        data.messages = messages
        SyncStoredMessages(data)
    end
end

local function AddStoredMessage(data, message)
    local stored = data and data._store
    if type(stored) ~= "table" then
        return
    end

    if type(stored.messages) ~= "table" then
        stored.messages = {}
    end
    stored.storageVersion = STORAGE_VERSION
    stored.encodedMessages = nil
    local encoded = EncodeStoredMessage(message)
    tinsert(stored.messages, encoded)
    return encoded
end

do
local historyDefaults = {
    saveMessages = true,
    maxMessages = DEFAULT_MAX_MESSAGES,
    maxConversations = DEFAULT_MAX_CONVERSATIONS,
}

local HISTORY_MIGRATION_KEY = "profileHistoryToGlobalV1"
local HISTORY_FIELDS = {
    history = true,
    saveMessages = true,
    maxMessages = true,
    maxConversations = true,
}

local DB_PROXY_META = {
    __index = function(proxy, key)
        local source = HISTORY_FIELDS[key] and rawget(proxy, "_historyStore") or rawget(proxy, "_config")
        if source then
            return source[key]
        end
        return nil
    end,
    __newindex = function(proxy, key, value)
        local source = HISTORY_FIELDS[key] and rawget(proxy, "_historyStore") or rawget(proxy, "_config")
        if source then
            source[key] = value
        else
            rawset(proxy, key, value)
        end
    end,
}

local function HasLegacyHistoryConfig(config)
    if type(config) ~= "table" then
        return false
    end
    return config.history ~= nil
        or config.saveMessages ~= nil
        or config.maxMessages ~= nil
        or config.maxConversations ~= nil
end

local function CopyLegacyHistorySetting(store, config, key)
    if type(store) ~= "table" or type(config) ~= "table" then
        return
    end
    if store[key] == nil and config[key] ~= nil then
        store[key] = config[key]
    end
end

local function MessageIdentity(message)
    if type(message) ~= "table" then
        return nil
    end
    return tostring(message.inform and 1 or 0) .. "\31"
        .. tostring(message.time or "") .. "\31"
        .. tostring(message.text or "")
end

local function MergeRuntimeMessages(targetData, sourceData, store)
    if not targetData or not sourceData or targetData._store == sourceData._store then
        return false
    end

    local targetMessages = EnsureRuntimeMessages(targetData)
    local sourceMessages = EnsureRuntimeMessages(sourceData)
    if type(targetMessages) ~= "table" or type(sourceMessages) ~= "table" then
        return false
    end

    local changed
    local seen = {}
    for _, message in ipairs(targetMessages) do
        local key = MessageIdentity(message)
        if key then
            seen[key] = true
        end
    end
    for _, message in ipairs(sourceMessages) do
        local key = MessageIdentity(message)
        if key and not seen[key] then
            tinsert(targetMessages, message)
            seen[key] = true
            changed = true
        end
    end
    if changed then
        table.sort(targetMessages, function(a, b)
            local at = tonumber(a and a.time) or 0
            local bt = tonumber(b and b.time) or 0
            if at == bt then
                return tostring(a and a.text or "") < tostring(b and b.text or "")
            end
            return at < bt
        end)
        local maxMessages = tonumber(store and store.maxMessages) or DEFAULT_MAX_MESSAGES
        while #targetMessages > maxMessages do
            tremove(targetMessages, 1)
        end
        SyncStoredMessages(targetData)
    end
    return changed
end

local function MergeStoredConversation(store, stored)
    if type(store) ~= "table" or type(stored) ~= "table" then
        return false
    end

    local data = EnsureRuntimeHeader(stored)
    if not data or type(data.key) ~= "string" then
        return false
    end

    local index, existing = FindConversation and FindConversation(store, data.key)
    if not existing then
        InsertConversation(store, nil, data)
        return true
    end

    local changed = MergeRuntimeMessages(existing, data, store)
    if data.protected and not existing.protected then
        existing.protected = true
        changed = true
    end
    if data.new and not existing.new then
        existing.new = true
        changed = true
    end
    if (tonumber(data.unreadCount) or 0) > (tonumber(existing.unreadCount) or 0) then
        existing.unreadCount = data.unreadCount
        changed = true
    end
    if data.firstUnreadIndex and (not existing.firstUnreadIndex or data.firstUnreadIndex < existing.firstUnreadIndex) then
        existing.firstUnreadIndex = data.firstUnreadIndex
        changed = true
    end
    if changed then
        SyncStoredControl(existing)
    end
    return changed, index
end

local function GetStoredLatestTime(stored)
    local latest = GetLatestRuntimeMessage(stored)
    return tonumber(latest and latest.time) or 0
end

local function SortHistoryByLatest(store)
    if type(store) ~= "table" or type(store.history) ~= "table" then
        return
    end
    table.sort(store.history, function(a, b)
        return GetStoredLatestTime(a) > GetStoredLatestTime(b)
    end)
end

local function MergeConversationState(targetData, sourceData, store)
    if not targetData or not sourceData or targetData == sourceData then
        return false
    end

    local changed = MergeRuntimeMessages(targetData, sourceData, store)
    if sourceData.protected and not targetData.protected then
        targetData.protected = true
        changed = true
    end
    if sourceData.new and not targetData.new then
        targetData.new = true
        changed = true
    end
    if (tonumber(sourceData.unreadCount) or 0) > (tonumber(targetData.unreadCount) or 0) then
        targetData.unreadCount = sourceData.unreadCount
        changed = true
    end
    if sourceData.firstUnreadIndex and (not targetData.firstUnreadIndex or sourceData.firstUnreadIndex < targetData.firstUnreadIndex) then
        targetData.firstUnreadIndex = sourceData.firstUnreadIndex
        changed = true
    end
    if (not targetData.class or targetData.class == "") and sourceData.class then
        targetData.class = sourceData.class
        changed = true
    end
    if changed then
        SyncStoredControl(targetData)
    end
    return changed
end

local function NormalizePlayerHistory(store)
    local history = store and store.history
    if type(history) ~= "table" then
        return false
    end

    local changed
    local seen = {}
    local index = 1
    while index <= #history do
        local stored = history[index]
        local data = EnsureRuntimeHeader(stored)
        if data and Manager:NormalizePlayerIdentity(data) then
            SyncStoredIdentity(data)
            changed = true
        end

        local key = data and data.key
        local target = key and seen[key]
        if target and target ~= data then
            MergeConversationState(target, data, store)
            if Manager.selectedStore == data._store then
                Manager.selectedKey = target.key
                Manager.selectedStore = target._store
                Manager.selectedToken = GetStoreToken(target._store)
            end
            if Manager.pendingUnreadDividerToken == GetStoreToken(data._store) then
                Manager.pendingUnreadDividerKey = target.key
                Manager.pendingUnreadDividerToken = GetStoreToken(target._store)
            end
            RemoveConversationAt(store, index)
            changed = true
        else
            if key then
                seen[key] = data
            end
            index = index + 1
        end
    end

    if changed then
        SortHistoryByLatest(store)
    end
    return changed == true
end

local function MigrateLegacyConfigHistory(config, store, copySettings)
    if type(config) ~= "table" or type(store) ~= "table" or not HasLegacyHistoryConfig(config) then
        return false
    end

    if copySettings then
        CopyLegacyHistorySetting(store, config, "saveMessages")
        CopyLegacyHistorySetting(store, config, "maxMessages")
        CopyLegacyHistorySetting(store, config, "maxConversations")
    end

    local changed
    if type(config.history) == "table" then
        for _, stored in ipairs(config.history) do
            if MergeStoredConversation(store, stored) then
                changed = true
            end
        end
    end

    config.history = nil
    config.saveMessages = nil
    config.maxMessages = nil
    config.maxConversations = nil
    return changed
end

local function GetProductAceDB()
    if YUI.DB and YUI.DB.GetAceDB then
        return YUI.DB:GetAceDB(PRODUCT_ID)
    end
end

local function MigrateAllLegacyProfileHistory(store, activeConfig)
    if type(store) ~= "table" then
        return
    end

    MigrateLegacyConfigHistory(activeConfig, store, true)

    local aceDB = GetProductAceDB()
    local sv = aceDB and aceDB.sv
    local profiles = type(sv) == "table" and sv.profiles or nil
    if type(profiles) == "table" then
        for _, profile in pairs(profiles) do
            local components = type(profile) == "table" and profile.Components or nil
            local config = type(components) == "table" and components[CONFIG_KEY] or nil
            if config ~= activeConfig then
                MigrateLegacyConfigHistory(config, store, false)
            end
        end
    end

    SortHistoryByLatest(store)
end

local function ApplyHistoryDefaults(store)
    if type(store.history) ~= "table" then
        store.history = {}
    end
    if store.saveMessages == nil then
        store.saveMessages = historyDefaults.saveMessages
    end
    if store.maxMessages == nil then
        store.maxMessages = historyDefaults.maxMessages
    end
    if store.maxConversations == nil then
        store.maxConversations = historyDefaults.maxConversations
    end
end

local function GetHistoryStore(config)
    local global = YUI.DB and YUI.DB.GetGlobal and YUI.DB:GetGlobal(PRODUCT_ID)
    if type(global) ~= "table" then
        return nil
    end

    if type(global[STORAGE_KEY]) ~= "table" then
        global[STORAGE_KEY] = {}
    end
    local store = global[STORAGE_KEY]
    if type(store.history) ~= "table" then
        store.history = {}
    end
    if type(store._migrations) ~= "table" then
        store._migrations = {}
    end

    if store._migrations[HISTORY_MIGRATION_KEY] then
        if MigrateLegacyConfigHistory(config, store, false) then
            SortHistoryByLatest(store)
        end
    else
        MigrateAllLegacyProfileHistory(store, config)
        store._migrations[HISTORY_MIGRATION_KEY] = true
    end

    ApplyHistoryDefaults(store)
    if not Manager.messageOrderInitialized then
        local maximum = Manager.nextMessageOrder or time() * 1000000
        for _, stored in ipairs(store.history) do
            local messages = type(stored) == "table" and stored.messages
            if type(messages) == "table" then
                for _, message in ipairs(messages) do
                    local order = type(message) == "table" and tonumber(message.receiptOrder)
                    if order and order < math.huge and order > maximum then maximum = order end
                end
            end
        end
        Manager.nextMessageOrder = maximum
        Manager.messageOrderInitialized = true
    end
    NormalizePlayerHistory(store)
    if TrimHistory and not Manager.deferredBatch then
        TrimHistory(store)
    end
    return store
end

local function GetDBView(config, historyStore)
    if type(config) ~= "table" or type(historyStore) ~= "table" then
        return nil
    end

    local proxy = Manager.dbProxy
    if type(proxy) ~= "table" then
        proxy = {}
        Manager.dbProxy = proxy
    end
    rawset(proxy, "_config", config)
    rawset(proxy, "_historyStore", historyStore)
    if getmetatable(proxy) ~= DB_PROXY_META then
        setmetatable(proxy, DB_PROXY_META)
    end
    return proxy
end

GetDB = function()
    local config = Components:EnsureConfig(CONFIG_KEY, defaults, PRODUCT_ID)
    if type(config) ~= "table" then
        return nil
    end

    local historyStore = GetHistoryStore(config)
    if type(historyStore) ~= "table" then
        return nil
    end

    if type(config.window) ~= "table" then
        config.window = {}
    end
    if (tonumber(config.window.width) or 0) > (LIST_WINDOW_WIDTH + 80) then
        local oldX = tonumber(config.window.x) or 0
        config.window.x = oldX + LIST_WINDOW_X_OFFSET
        config.window.width = LIST_WINDOW_WIDTH
        config.window.height = WINDOW_HEIGHT
    end

    local function ensureWindow(key, fallback, minWidth)
        if type(config[key]) ~= "table" then
            config[key] = {}
        end
        for setting, value in pairs(fallback) do
            if config[key][setting] == nil then
                config[key][setting] = value
            end
        end
        local width = tonumber(config[key].width) or fallback.width or minWidth
        if width < minWidth then
            width = minWidth
        end
        config[key].width = width
        config[key].height = tonumber(config[key].height) or fallback.height or WINDOW_HEIGHT
    end

    ensureWindow("window", defaults.window, LIST_WINDOW_WIDTH)

    return GetDBView(config, historyStore)
end
end

local function FireCompat(eventName, ...)
    local callbacks = Manager.callbacks and Manager.callbacks[eventName]
    if callbacks then
        for _, callback in ipairs(callbacks) do
            pcall(callback, ...)
        end
    end
end

local function BroadcastUpdate()
    if Manager.deferredBatch then
        Manager.deferredChanged = true
        return
    end
    local listShown = Manager.listFrame and Manager.listFrame:IsShown()
    local detailShown = Manager.detailFrame and Manager.detailFrame:IsShown()
    if listShown or detailShown then
        Manager:RefreshFrame()
    end

    FireCompat("OnListUpdate")
    if Event and Event.Emit then
        Event:Emit("YUI_WHISPER_MANAGER_UPDATE")
    end
end

function Manager:RegisterEventCallback(eventName, callback)
    if type(eventName) ~= "string" or type(callback) ~= "function" then
        return
    end

    self.callbacks[eventName] = self.callbacks[eventName] or {}
    for _, existing in ipairs(self.callbacks[eventName]) do
        if existing == callback then
            return
        end
    end
    tinsert(self.callbacks[eventName], callback)
end

function Manager:IsEnabled()
    return self.enabled == true
end

function Manager:NormalizeRealmToken(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end

    value = gsub(value, "%s+", "")
    value = gsub(value, "%-", "")
    if value == "" then
        return nil
    end
    return string.lower(value)
end

function Manager:IsSameRealm(left, right)
    local leftToken = self:NormalizeRealmToken(left)
    local rightToken = self:NormalizeRealmToken(right)
    return leftToken ~= nil and rightToken ~= nil and leftToken == rightToken
end

local GetUnreadCount
local GetTotalUnreadCount

function Manager:GetDisplayName(dataOrName, forceRealm)
    local db = GetDB()
    local data = type(dataOrName) == "table" and dataOrName or nil
    local value = data and data.name or dataOrName

    if data and data.kind == "bn" then
        local ignoredID, accountName, battleTag
        if ResolveBNRuntimeInfo then
            ignoredID, accountName, battleTag = ResolveBNRuntimeInfo(data)
        end
        return accountName or battleTag or data.battleTag or value
    end

    if type(value) ~= "string" then
        return nil
    end
    if forceRealm then
        return value
    end

    local name, realm = self:ParseNameRealm(value)
    if data and self:IsSelfConversation(data) then
        return name
    end
    if db and db.showRealm then
        if db.foreignOnly and realm and self:IsSameRealm(realm, self:GetNormalizedRealm()) then
            return name
        end
        return value
    end

    return name
end

function Manager:IsConversationVisible(data)
    if not data then
        return false
    end

    local store = type(data) == "table" and (data._store or data) or nil
    local token = GetStoreToken(store)
    local filter = self:GetListFilter()
    if filter == "favorites" then
        return data.protected == true or (token and self.unfavoritedVisibleKeys and self.unfavoritedVisibleKeys[token] == true)
    elseif filter == "unread" then
        return GetUnreadCount(data) > 0
            or (token and self.pendingUnreadDividerToken == token)
            or (data.key and self.pendingUnreadDividerKey == data.key)
    end

    return true
end

function Manager:GetVisibleHistory(db)
    local visible = {}
    if not db then
        return visible
    end

    for _, stored in ipairs(db.history or {}) do
        if self:IsConversationVisible(stored) then
            tinsert(visible, stored)
        end
    end

    return visible
end

function Manager:GetListFilter()
    local filter = self.listFilter
    if filter == "all" or filter == "unread" or filter == "favorites" then
        return filter
    end
    return self.listTab == "favorites" and "favorites" or "all"
end

function Manager:SetListFilter(filter)
    if filter ~= "unread" and filter ~= "favorites" then
        filter = "all"
    end
    if self:GetListFilter() == filter then
        return
    end

    wipe(self.unfavoritedVisibleKeys)
    self.listFilter = filter
    self.listTab = filter == "favorites" and "favorites" or "messages"
    self.currentPage = 1
    self:RefreshFrame()
end

function Manager:SetListTab(tab)
    self:SetListFilter(tab == "favorites" and "favorites" or "all")
end

function Manager:RefreshListTabs()
    local frame = self.listFrame or self.frame
    local db = GetDB()
    if not frame then return end

    local totalUnread = GetTotalUnreadCount(db)
    local filter = self:GetListFilter()
    if frame.listFilterDropdown and frame.listFilterDropdown.SetValue and frame.listFilterDropdown:GetValue() ~= filter then
        frame.listFilterDropdown:SetValue(filter, true)
    end
    if frame.unreadSummaryText then
        frame.unreadSummaryText:SetText(FormatLocale("list.unread_count", totalUnread))
    end
end

function Manager:IsSelfConversation(data)
    if not data or data.kind ~= "player" or type(data.name) ~= "string" then
        return false
    end

    local playerName, playerRealm
    if UnitAPI.UnitFullName then
        playerName, playerRealm = UnitAPI.UnitFullName("player")
    end
    if (not playerName or playerName == "") and UnitAPI.UnitName then
        playerName = UnitAPI.UnitName("player")
    end
    if type(playerName) ~= "string" or playerName == "" then
        return false
    end

    if type(playerRealm) == "string" and playerRealm ~= "" then
        playerRealm = gsub(playerRealm, "%s+", "")
    else
        playerRealm = self:GetNormalizedRealm()
    end

    local name, realm = self:ParseNameRealm(data.name)
    if name ~= playerName then
        return false
    end

    return not realm or not playerRealm or self:IsSameRealm(realm, playerRealm)
end

function Manager:IsFriendConversation(data)
    if not data then
        return false
    end
    if data.kind == "bn" then
        return true
    end
    if data.kind ~= "player" then
        return false
    end

    local fullName = data.name or self:GetDisplayName(data, true)
    return Social.FindFriendInfo and Social.FindFriendInfo(fullName) ~= nil
end

function Manager:GetNewMessage()
    local db = GetDB()
    if not db then return nil end

    for _, stored in ipairs(db.history or {}) do
        if stored.new then
            local data = EnsureRuntimeHeader(stored)
            local latest = GetLatestRuntimeMessage(stored)
            if data then
                return self:GetDisplayName(data), data.class, latest and latest.text, latest and latest.time
            end
        end
    end
end

function Manager:GetNewNames()
    local db = GetDB()
    local names = {}
    if not db then return names end

    for _, stored in ipairs(db.history or {}) do
        if stored.new then
            local data = EnsureRuntimeHeader(stored)
            if data then
                tinsert(names, self:GetDisplayName(data))
            end
        end
    end

    return names
end

function Manager:AddTooltipText(tooltip)
    if not tooltip then return end

    local names = self:GetNewNames()
    if names[1] then
        tooltip:AddLine(T("tooltip.unread"), 1, 1, 1, true)
        for _, name in ipairs(names) do
            tooltip:AddLine(name, 0, 1, 0, true)
        end
    else
        tooltip:AddLine(T("tooltip.none"), 1, 1, 1, true)
    end
end

Manager._ClearConversationUnread = function(data, options)
    if type(data) ~= "table" then
        return false
    end

    local runtime = data._store and data or EnsureRuntimeHeader(data)
    if runtime and Manager.deferredQueue then
        Manager.deferredReadAt = Manager.deferredReadAt or {}
        Manager.deferredReadAt[runtime.key] = Manager.nextMessageOrder or 0
    end
    if not runtime then
        local changed = data.new ~= nil or data.unreadCount ~= nil or data.firstUnreadIndex ~= nil
        data.new = nil
        data.unreadCount = nil
        data.firstUnreadIndex = nil
        return changed
    end

    local changed = runtime.new ~= nil or runtime.unreadCount ~= nil or runtime.firstUnreadIndex ~= nil
    runtime.new = nil
    runtime.unreadCount = nil
    runtime.firstUnreadIndex = nil
    if changed then
        SyncStoredControl(runtime)
    end

    if not (options and options.keepDivider) then
        local token = GetStoreToken(runtime._store)
        if Manager.pendingUnreadDividerKey == runtime.key or (token and Manager.pendingUnreadDividerToken == token) then
            Manager.pendingUnreadDividerKey = nil
            Manager.pendingUnreadDividerToken = nil
            Manager.pendingUnreadDividerIndex = nil
            changed = true
        end
    end

    return changed
end

function Manager:ClearAllNews()
    local db = GetDB()
    if not db then return end

    for _, stored in ipairs(db.history or {}) do
        Manager._ClearConversationUnread(stored)
    end
    self.pendingUnreadDividerKey = nil
    self.pendingUnreadDividerToken = nil
    self.pendingUnreadDividerIndex = nil
    BroadcastUpdate()
end

function Manager:ConfirmClearAllNews()
    local function accept()
        Manager:ClearAllNews()
    end

    local Settings = YUI.Settings
    if Settings and Settings.ShowConfirmPopup then
        Settings:ShowConfirmPopup(T("confirm.mark_all_read.message"), accept, {
            titleText = T("confirm.mark_all_read.title"),
            acceptText = T("confirm.mark_all_read.accept"),
            acceptTone = "success",
            cancelTone = "default",
        })
        if Settings.ConfirmFrame and Settings.ConfirmFrame.title and GUI2 and GUI2.SetTextColorKey then
            GUI2:SetTextColorKey(Settings.ConfirmFrame.title, "color.text.heading")
        end
        return
    end
end

function Manager:OpenSettings()
    if YUI.Settings and YUI.Settings.OpenComponentFeature then
        YUI.Settings:OpenComponentFeature(FEATURE_KEY)
    elseif YUI.Components and YUI.Components.OpenFeatureSettings then
        YUI.Components:OpenFeatureSettings(FEATURE_KEY)
    end
end

function Manager:ConfirmClearHistory()
    local function accept()
        Manager:Clear()
    end

    local Settings = YUI.Settings
    if Settings and Settings.ShowConfirmPopup then
        Settings:ShowConfirmPopup(T("confirm.clear_history.message"), accept, {
            titleText = T("confirm.clear_history.title"),
            acceptText = T("confirm.clear_history.accept"),
            acceptTone = "danger",
            cancelTone = "default",
        })
        return
    end
end

FindConversation = function(db, key)
    if not db or type(key) ~= "string" then
        return nil, nil
    end

    local encodedKey = EncodePrivateString(key)
    for index, stored in ipairs(db.history or {}) do
        local data = EnsureRuntimeHeader(stored)
        if data then
            if stored.encodedKey == encodedKey or stored.key == key or data.key == key then
                return index, data
            end
        end
    end
end

GetUnreadCount = function(data)
    if not data then
        return 0
    end

    local count = tonumber(data.unreadCount) or 0
    if count > 0 then
        return count
    end

    return data.new and 1 or 0
end

GetTotalUnreadCount = function(db)
    local total = 0
    if not db then
        return total
    end

    for _, stored in ipairs(db.history or {}) do
        total = total + GetUnreadCount(stored)
    end

    return total
end

function Manager:FindConversation(key)
    return FindConversation(GetDB(), key)
end

local function RemoveConversation(db, key)
    local index = FindConversation(db, key)
    if index then
        RemoveConversationAt(db, index)
        return true
    end
end

function Manager:Delete(key)
    local db = GetDB()
    if not db then return end

    local index, data = FindConversation(db, key or self.selectedKey)
    if index and data and not data.protected then
        if self.deferredQueue then
            self.deferredDeleted = self.deferredDeleted or {}
            self.deferredDeleted[data.key] = self.nextMessageOrder or 0
        end
        local token = GetStoreToken(data._store)
        local wasSelected = self.selectedKey == data.key or self.selectedStore == data._store
        local nextKey

        if wasSelected then
            local visibleHistory = self:GetVisibleHistory(db)
            local visibleIndex
            for i, stored in ipairs(visibleHistory) do
                if stored == data._store or GetStoreToken(stored) == token then
                    visibleIndex = i
                    break
                end
            end

            if visibleIndex then
                local candidate = visibleHistory[visibleIndex + 1] or visibleHistory[visibleIndex - 1]
                local candidateData = candidate and EnsureRuntimeHeader(candidate)
                nextKey = candidateData and candidateData.key
            end
        end

        RemoveConversationAt(db, index)
        if token and self.unfavoritedVisibleKeys then
            self.unfavoritedVisibleKeys[token] = nil
        end
        if wasSelected then
            self:ClearCurrentSelection()
            self:HideCopyEditBox(true)
            if nextKey and FindConversation(db, nextKey) then
                self:SelectConversation(nextKey, true)
            else
                self:HideDetailWindow()
            end
        end
        BroadcastUpdate()
    end
end

function Manager:Clear()
    self:StopDeferredWhispers(true)
    local db = GetDB()
    if not db then return end

    db.history = {}
    ResetRuntimeCaches()
    wipe(self.unfavoritedVisibleKeys)
    self:HideCopyEditBox(true)
    self:ClearCurrentSelection()
    if self.detailFrame and self.detailFrame:IsShown() then
        self:HideWindowWithFade(self.detailFrame, "whisper-manager-detail-slide")
    end
    BroadcastUpdate()
end

TrimHistory = function(db)
    local maxConversations = tonumber(db.maxConversations) or DEFAULT_MAX_CONVERSATIONS
    local history = db and db.history or {}
    while #history > maxConversations do
        local removed = false
        for index = #history, 1, -1 do
            if not history[index].protected then
                RemoveConversationAt(db, index)
                history = db and db.history or {}
                removed = true
                break
            end
        end
        if not removed then
            break
        end
    end
end

local function GetBNInfoByIndex(index)
    local info = Social.GetBNFriendInfoByIndex and Social.GetBNFriendInfoByIndex(index)
    if info then
        return info.bnetID, info.accountName, info.battleTag, info.online, info.friendIndex
    end
end

local function GetBNInfoByID(id)
    local info = Social.GetBNFriendInfoByID and Social.GetBNFriendInfoByID(id)
    if info then
        return info.bnetID or id, info.accountName, info.battleTag, info.online, info.friendIndex
    end
end

ResolveBNRuntimeInfo = function(dataOrTag)
    local battleTag, legacyID
    if type(dataOrTag) == "table" then
        battleTag = (IsBattleTag(dataOrTag.battleTag) and dataOrTag.battleTag)
            or (IsBattleTag(dataOrTag.name) and dataOrTag.name)
        legacyID = dataOrTag.bnid
    elseif IsBattleTag(dataOrTag) then
        battleTag = dataOrTag
    end
    if not battleTag and legacyID then
        local id, accountName, tag, online, friendIndex = GetBNInfoByID(legacyID)
        if id or accountName or tag then
            if type(dataOrTag) == "table" then
                dataOrTag.bnid = id or dataOrTag.bnid
                dataOrTag.bnAccountName = accountName or dataOrTag.bnAccountName
                dataOrTag.battleTag = tag or dataOrTag.battleTag
                dataOrTag.online = online
                dataOrTag.presenceExpiresAt = time() + PLAYER_INFO_CACHE_TTL
            end
            return id, accountName, tag, online, friendIndex
        end
    end

    if not battleTag or not Social.FindBNFriendInfo then
        return nil
    end

    local info = Social.FindBNFriendInfo(battleTag)
    if info then
        if type(dataOrTag) == "table" then
            dataOrTag.bnid = info.bnetID or dataOrTag.bnid
            dataOrTag.bnAccountName = info.accountName or dataOrTag.bnAccountName
            dataOrTag.battleTag = info.battleTag or dataOrTag.battleTag
            dataOrTag.online = info.online
            dataOrTag.presenceExpiresAt = time() + PLAYER_INFO_CACHE_TTL
        end
        return info.bnetID, info.accountName, info.battleTag, info.online, info.friendIndex
    end

    return nil, nil, battleTag
end

local function BuildIdentity(name, class, bnid, resolvedBNInfo)
    if class == "BN" then
        local info = resolvedBNInfo or Social.ResolveWhisperFriend(name, bnid)
        if not info then return nil end
        local accountID, accountName, battleTag, online = info.bnetID, info.accountName, info.battleTag, info.online
        local stableName = battleTag
        return {
            key = "bn:" .. stableName,
            name = stableName,
            displayName = accountName or GetBattleTagName(battleTag) or stableName,
            battleTag = battleTag,
            bnAccountName = accountName,
            bnid = accountID,
            online = online,
            kind = "bn",
            class = "BN",
        }
    end

    if class == "GM" then
        return {
            key = "gm:" .. name,
            name = name,
            kind = "gm",
            class = "GM",
        }
    end

    local fullName = Manager:NormalizePlayerFullName(name)
    if not fullName then
        return nil
    end

    return {
        key = "player:" .. fullName,
        name = fullName,
        kind = "player",
        class = class,
    }
end

local function NormalizeLookupName(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end

    local name, realm = Manager:ParseNameRealm(value)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    if type(realm) == "string" and realm ~= "" then
        return string.lower(name .. "-" .. gsub(realm, "%s+", ""))
    end
    return string.lower(name)
end

local function GetConversationLookupName(data)
    if not data or data.kind ~= "player" then
        return nil
    end
    return data.name or Manager:GetDisplayName(data, true)
end

local function GetWhoQueryName(value)
    if type(value) == "table" then
        value = GetConversationLookupName(value)
    end
    if type(value) ~= "string" or value == "" then
        return nil
    end

    local name = Manager:ParseNameRealm(value)
    return NonEmptyString(name) or value
end

local function NormalizeShortLookupName(value)
    local name = GetWhoQueryName(value)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return string.lower(name)
end

local function ClearPendingWho(pending)
    if type(pending) ~= "table" then
        return
    end

    if pending.key and Manager.pendingWhoLookup then
        Manager.pendingWhoLookup[pending.key] = nil
    end
    if pending.name and Manager.pendingWhoNames then
        Manager.pendingWhoNames[pending.name] = nil
    end
    if pending.queryName and Manager.pendingWhoNames and Manager.pendingWhoNames[pending.queryName] == pending then
        Manager.pendingWhoNames[pending.queryName] = nil
    end
    if pending.queryKey and Manager.pendingWhoQueryLookup and Manager.pendingWhoQueryLookup[pending.queryKey] == pending then
        Manager.pendingWhoQueryLookup[pending.queryKey] = nil
    end
end

local function RegisterPendingWho(pending)
    if type(pending) ~= "table" then
        return nil
    end

    pending.key = pending.key or NormalizeLookupName(pending.name)
    pending.queryName = pending.queryName or GetWhoQueryName(pending.name)
    pending.queryKey = pending.queryKey or NormalizeShortLookupName(pending.queryName)
    if not pending.key or not pending.name or not pending.queryName or not pending.queryKey then
        return nil
    end

    Manager.pendingWhoLookup[pending.key] = pending
    Manager.pendingWhoNames[pending.name] = pending
    Manager.pendingWhoQueryLookup[pending.queryKey] = pending
    return pending
end

local function PendingMatchesWhoInfo(pending, info)
    if type(pending) ~= "table" or type(info) ~= "table" or not NonEmptyString(info.fullName) then
        return false
    end

    local infoKey = NormalizeLookupName(info.fullName)
    local pendingKey = pending.key or NormalizeLookupName(pending.name)
    if infoKey and pendingKey and infoKey == pendingKey then
        return true
    end

    local _, infoRealm = Manager:ParseNameRealm(info.fullName)
    local _, pendingRealm = Manager:ParseNameRealm(pending.name)
    if infoRealm and pendingRealm then
        return false
    end

    local infoQueryKey = NormalizeShortLookupName(info.fullName)
    return infoQueryKey and pending.queryKey and infoQueryKey == pending.queryKey
end

local function GetPendingWhoForInfo(manager, info)
    if type(manager) ~= "table" or type(info) ~= "table" then
        return nil
    end

    local fullKey = NormalizeLookupName(info.fullName)
    local pending = fullKey and manager.pendingWhoLookup and manager.pendingWhoLookup[fullKey]
    if PendingMatchesWhoInfo(pending, info) then
        return pending
    end

    local queryKey = NormalizeShortLookupName(info.fullName)
    pending = queryKey and manager.pendingWhoQueryLookup and manager.pendingWhoQueryLookup[queryKey]
    if PendingMatchesWhoInfo(pending, info) then
        return pending
    end

    return nil
end

local function CopyPlayerInfo(info)
    if type(info) ~= "table" then
        return nil
    end

    local now = time()
    local raceFile = info.raceFile
    if not raceFile and info.raceName and UnitAPI.GetRaceInfoByName then
        local raceInfo = UnitAPI.GetRaceInfoByName(info.raceName)
        raceFile = raceInfo and raceInfo.clientFileString
    end
    return {
        fullName = info.fullName or info.name,
        classFile = info.classFile or info.class,
        className = info.className or info.localizedClass,
        raceFile = raceFile,
        raceName = info.raceName or info.localizedRace,
        level = tonumber(info.level),
        gender = tonumber(info.gender or info.sex),
        online = info.online,
        updatedAt = now,
        expiresAt = now + PLAYER_INFO_CACHE_TTL,
    }
end

local function CachePlayerInfo(name, info)
    local key = NormalizeLookupName(name or (info and (info.fullName or info.name)))
    if not key then
        return nil
    end

    local copy = CopyPlayerInfo(info)
    if not copy then
        return nil
    end

    Manager.playerInfoCache = Manager.playerInfoCache or {}
    Manager.playerInfoCache[key] = copy
    return copy
end

local function GetCachedPlayerInfo(name)
    local key = NormalizeLookupName(name)
    local cache = key and Manager.playerInfoCache and Manager.playerInfoCache[key] or nil
    if not cache then
        return nil
    end

    if tonumber(cache.expiresAt) and cache.expiresAt < time() then
        Manager.playerInfoCache[key] = nil
        return nil
    end

    return cache
end

local function GetTestPlayerInfo(data)
    if YUI.IsDev ~= true or not data or data.kind ~= "player" then
        return nil
    end

    local name = GetConversationLookupName(data)
    local shortName = GetWhoQueryName(name)
    local prefix = FormatLocale("dev.player_prefix")
    if not shortName or type(prefix) ~= "string" or prefix == "" or strsub(shortName, 1, #prefix) ~= prefix then
        return nil
    end

    local hash = 0
    for index = 1, #shortName do
        hash = (hash + ((strbyte(shortName, index) or 0) * index)) % 9973
    end

    local races = Manager.testRaces or {}
    if #races == 0 then
        return nil
    end
    local race = races[(hash % #races) + 1]
    local maxLevel = UnitAPI.GetMaxPlayerLevel and UnitAPI.GetMaxPlayerLevel() or nil
    local levelBase = tonumber(maxLevel) or 80
    local level = math.max(1, levelBase - ((hash % 9) + 1))
    return {
        fullName = name,
        classFile = data.class,
        raceFile = race and race.raceFile,
        gender = race and race.gender,
        level = level,
        online = (hash % 4) ~= 0,
    }
end

local function ApplyPlayerInfo(data, info, persistClass)
    if not data or data.kind ~= "player" or type(info) ~= "table" then
        return false
    end

    local changed
    local classFile = NonEmptyString(info.classFile)
    if classFile and data.class ~= classFile then
        data.class = classFile
        changed = true
    end

    local raceFile = NonEmptyString(info.raceFile)
    if not raceFile and info.raceName and UnitAPI.GetRaceInfoByName then
        local raceInfo = UnitAPI.GetRaceInfoByName(info.raceName)
        raceFile = raceInfo and NonEmptyString(raceInfo.clientFileString)
    end
    if raceFile and data.raceFile ~= raceFile then
        data.raceFile = raceFile
        changed = true
    end

    local raceName = NonEmptyString(info.raceName)
    if raceName and data.raceName ~= raceName then
        data.raceName = raceName
        changed = true
    end

    local gender = tonumber(info.gender or info.sex)
    if gender and data.gender ~= gender then
        data.gender = gender
        changed = true
    end

    local level = tonumber(info.level)
    if level and level > 0 and data.level ~= level then
        data.level = level
        changed = true
    end

    if info.online ~= nil then
        local online = info.online == true
        if data.online ~= online then
            data.online = online
            changed = true
        end
        data.presenceExpiresAt = time() + PLAYER_INFO_CACHE_TTL
    end

    if changed and persistClass then
        SyncStoredControl(data)
    end

    return changed == true
end

function Manager:GetCachedConversationInfo(data)
    local name = GetConversationLookupName(data)
    return name and GetCachedPlayerInfo(name) or nil
end

function Manager:GetKnownPresence(data)
    if not data then
        return nil
    end

    if data.kind == "bn" then
        local _, _, _, online = ResolveBNRuntimeInfo(data)
        if online ~= nil then
            return online == true
        end
        return nil
    end

    if data.kind ~= "player" then
        return nil
    end

    local name = GetConversationLookupName(data)
    local friendInfo = Social.FindFriendInfo and Social.FindFriendInfo(name)
    if friendInfo then
        data.online = friendInfo.online == true
        data.presenceExpiresAt = time() + PLAYER_INFO_CACHE_TTL
        return data.online
    end

    local cached = GetCachedPlayerInfo(name)
    if cached and cached.online ~= nil then
        return cached.online == true
    end

    if data.online ~= nil and tonumber(data.presenceExpiresAt) and data.presenceExpiresAt >= time() then
        return data.online == true
    end

    return nil
end

function Manager:CanInviteConversation(data)
    if not data or data.kind == "gm" or self:IsSelfConversation(data) then
        return false
    end

    if data.kind == "bn" then
        local bnetID, _, _, online, friendIndex = ResolveBNRuntimeInfo(data)
        return online == true and (bnetID ~= nil or friendIndex ~= nil)
    end

    if data.kind == "player" then
        local online = self:GetKnownPresence(data)
        return online ~= false
    end

    return false
end

function Manager:ApplyWhoInfo(info)
    if type(info) ~= "table" or not NonEmptyString(info.fullName) then
        return false
    end

    local changed
    CachePlayerInfo(info.fullName, info)

    local db = GetDB()
    if type(db) ~= "table" or type(db.history) ~= "table" then
        return false
    end

    local pending = GetPendingWhoForInfo(self, info)
    if pending then
        local data
        if pending.conversationKey then
            _, data = FindConversation(db, pending.conversationKey)
        end
        if not data and pending.key then
            for _, stored in ipairs(db.history) do
                local candidate = EnsureRuntimeHeader(stored)
                if candidate and candidate.kind == "player" and NormalizeLookupName(GetConversationLookupName(candidate)) == pending.key then
                    data = candidate
                    break
                end
            end
        end

        ClearPendingWho(pending)
        if data and data.kind == "player" then
            local lookupName = GetConversationLookupName(data)
            if lookupName then
                CachePlayerInfo(lookupName, info)
            end
            return ApplyPlayerInfo(data, info, true) == true
        end
        return false
    end

    local exactMatches = {}
    local shortMatches = {}
    local infoKey = NormalizeLookupName(info.fullName)
    local infoShortKey = NormalizeShortLookupName(info.fullName)
    for _, stored in ipairs(db.history) do
        local data = EnsureRuntimeHeader(stored)
        if data and data.kind == "player" then
            local lookupName = GetConversationLookupName(data)
            local lookupKey = NormalizeLookupName(lookupName)
            if infoKey and lookupKey and infoKey == lookupKey then
                exactMatches[#exactMatches + 1] = data
            elseif infoShortKey and NormalizeShortLookupName(lookupName) == infoShortKey then
                shortMatches[#shortMatches + 1] = data
            end
        end
    end

    local targets = exactMatches
    if #targets == 0 and #shortMatches == 1 then
        targets = shortMatches
    end

    for _, data in ipairs(targets) do
        local lookupName = GetConversationLookupName(data)
        if lookupName then
            CachePlayerInfo(lookupName, info)
        end
        if ApplyPlayerInfo(data, info, true) then
            changed = true
        end
    end

    return changed == true
end

function Manager:CleanupPendingWho()
    local now = time()
    for key, pending in pairs(self.pendingWhoLookup or {}) do
        if type(pending) ~= "table" then
            self.pendingWhoLookup[key] = nil
        elseif (tonumber(pending.expiresAt) or 0) < now then
            ClearPendingWho(pending)
        end
    end
end

function Manager:ClearManualWhoPending()
    for key, pending in pairs(self.pendingWhoLookup or {}) do
        if type(pending) ~= "table" then
            self.pendingWhoLookup[key] = nil
        elseif pending.manual then
            ClearPendingWho(pending)
        end
    end
end

function Manager:QueueSilentWho(data)
    if not data or data.kind ~= "player" or not Social.CanSendSilentWho or not Social.CanSendSilentWho() then
        return false
    end

    local name = GetConversationLookupName(data)
    local key = NormalizeLookupName(name)
    local queryName = GetWhoQueryName(name)
    local queryKey = NormalizeShortLookupName(queryName)
    if not key or not queryName or not queryKey then
        return false
    end

    local cached = GetCachedPlayerInfo(name)
    if cached then
        ApplyPlayerInfo(data, cached, true)
        return true
    end

    local now = time()
    local pending = self.pendingWhoLookup and self.pendingWhoLookup[key]
    if type(pending) == "table" and (tonumber(pending.expiresAt) or 0) > now then
        return false
    end
    if self.whoQueued[key] or (tonumber(self.whoCooldown[key]) or 0) > now then
        return false
    end

    self.whoQueued[key] = true
    tinsert(self.whoQueue, { key = key, name = name, queryName = queryName, queryKey = queryKey, conversationKey = data.key })
    self:ScheduleWhoQueue()
    return true
end

function Manager:ScheduleWhoQueue()
    if self.whoQueueTimer then
        return
    end

    local delay = math.max(0, (tonumber(self.nextWhoQueryAt) or 0) - time())
    if _G.C_Timer and _G.C_Timer.After and delay > 0 then
        self.whoQueueTimer = true
        _G.C_Timer.After(delay, function()
            Manager.whoQueueTimer = nil
            Manager:ProcessWhoQueue()
        end)
    else
        self:ProcessWhoQueue()
    end
end

function Manager:ProcessWhoQueue()
    if not self:IsEnabled() or type(self.whoQueue) ~= "table" or #self.whoQueue == 0 then
        return
    end

    if not Social.CanSendSilentWho or not Social.CanSendSilentWho() then
        wipe(self.whoQueue)
        wipe(self.whoQueued)
        self.whoQueueTimer = nil
        return
    end

    local now = time()
    if (tonumber(self.nextWhoQueryAt) or 0) > now then
        self:ScheduleWhoQueue()
        return
    end

    local item = tremove(self.whoQueue, 1)
    if not item or not item.key or not item.name then
        self:ProcessWhoQueue()
        return
    end

    self.whoQueued[item.key] = nil
    local pending = RegisterPendingWho({
        key = item.key,
        name = item.name,
        queryName = item.queryName,
        queryKey = item.queryKey,
        conversationKey = item.conversationKey,
        silent = true,
        expiresAt = now + WHO_PENDING_TTL,
    })
    self.nextWhoQueryAt = now + WHO_QUERY_THROTTLE

    local ok = pending and Social.SendWhoExact and Social.SendWhoExact(item.queryName or item.name, { silent = true, origin = "unknown" })
    if not ok then
        ClearPendingWho(pending)
        self.whoCooldown[item.key] = now + WHO_QUERY_COOLDOWN
    end

    if #self.whoQueue > 0 then
        self:ScheduleWhoQueue()
    end
end

function Manager:PrimeConversationInfo(data, allowWho)
    if not data then
        return
    end

    if data.kind == "bn" then
        ResolveBNRuntimeInfo(data)
        return
    end

    if data.kind ~= "player" then
        return
    end

    local name = GetConversationLookupName(data)
    local friendInfo = Social.FindFriendInfo and Social.FindFriendInfo(name)
    if friendInfo then
        ApplyPlayerInfo(data, friendInfo, false)
    end

    local testInfo = GetTestPlayerInfo(data)
    if testInfo then
        CachePlayerInfo(name, testInfo)
        ApplyPlayerInfo(data, testInfo, true)
        return
    end

    local cached = GetCachedPlayerInfo(name)
    if cached then
        ApplyPlayerInfo(data, cached, true)
        return
    end

    if allowWho and (not data.class or not data.raceFile or not data.level) then
        self:QueueSilentWho(data)
    end
end

function Manager:WHO_LIST_UPDATE()
    self:CleanupPendingWho()

    local results = Social.GetWhoResults and Social.GetWhoResults() or {}
    local changed
    for _, info in ipairs(results) do
        if self:ApplyWhoInfo(info) then
            changed = true
        end
    end
    self:ClearManualWhoPending()

    if changed then
        BroadcastUpdate()
    else
        local data = self:GetSelectedConversation()
        if data then
            self:RefreshConversationTitle(data)
        end
    end
end

local function ShouldFilterIncoming(eventName, ...)
    local db = GetDB()
    if not db or not db.applyFilters then
        return false
    end

    if ChatFrame_GetMessageEventFilters then
        local filters = ChatFrame_GetMessageEventFilters(eventName)
        if type(filters) == "table" then
            for _, callback in ipairs(filters) do
                if type(callback) == "function" then
                    local ok, filtered = pcall(callback, DEFAULT_CHAT_FRAME, eventName, ...)
                    if ok and filtered then
                        return true
                    end
                end
            end
        end
    elseif _G.ChatFrameUtil and _G.ChatFrameUtil.ProcessMessageEventFilters then
        local ok, filtered = pcall(_G.ChatFrameUtil.ProcessMessageEventFilters, DEFAULT_CHAT_FRAME, eventName, ...)
        if ok and filtered then
            return true
        end
    end

    return false
end

function Manager:ProcessChatMessage(name, class, text, inform, bnid, playerInfo, deferred, resolvedBNInfo)
    if HasAnySecretValue(name, class, text, bnid) then
        return
    end
    if type(text) ~= "string" or type(name) ~= "string" then
        return
    end

    local db = GetDB()
    if not db then
        return
    end

    local identity = BuildIdentity(name, class, bnid, resolvedBNInfo)
    if not identity then
        if class == "BN" and not deferred then
            self:DeferIdentityWhisper(name, text, inform, bnid)
        end
        return
    end
    if deferred and self.deferredDeleted and (self.deferredDeleted[identity.key] or 0) >= deferred.receiptOrder then
        return
    end
    if not deferred then self.nextMessageOrder = (self.nextMessageOrder or time() * 1000000) + 1 end
    if identity.kind == "player" and type(playerInfo) == "table" then
        if playerInfo.classFile then
            identity.class = playerInfo.classFile
        end
        identity.raceFile = playerInfo.raceFile
        identity.raceName = playerInfo.localizedRace or playerInfo.raceName
        identity.gender = playerInfo.gender or playerInfo.sex
        CachePlayerInfo(identity.name, identity)
    end

    local index, data = FindConversation(db, identity.key)
    if index then
        if index > 1 then
            local stored = data._store
            tremove(db.history, index)
            tinsert(db.history, 1, stored)
        end
        if identity.kind == "bn" then
            data.displayName = nil
            data.battleTag = nil
            data.bnAccountName = nil
            data.bnid = nil
            data.online = nil
        end
        for key, value in pairs(identity) do
            if value ~= nil then
                data[key] = value
            end
        end
        SyncStoredIdentity(data)
        if StoredMessagesNeedMigration(data._store, data._store and (data._store.messages or data._store.encodedMessages)) then
            EnsureRuntimeMessages(data)
        end
    else
        data = identity
        data.messages = {}
        InsertConversation(db, 1, data)
    end

    local storedMessages = data._store and data._store.messages
    local messageIndex = (type(storedMessages) == "table" and #storedMessages or 0) + 1
    local insertIndex = messageIndex
    local alreadyRead = deferred and self.deferredReadAt and (self.deferredReadAt[data.key] or 0) >= deferred.receiptOrder
    if deferred then
        local messages = EnsureRuntimeMessages(data)
        for i, previous in ipairs(messages) do
            local later = previous.time > deferred.time or (previous.time == deferred.time
                and (previous.receiptOrder or 0) > deferred.receiptOrder)
            if later and insertIndex == messageIndex then insertIndex = i end
            if previous.inform and later then alreadyRead = true end
        end
        if data.firstUnreadIndex and insertIndex <= data.firstUnreadIndex then
            data.firstUnreadIndex = data.firstUnreadIndex + 1
        end
        if self.pendingUnreadDividerKey == data.key and self.pendingUnreadDividerIndex
            and insertIndex <= self.pendingUnreadDividerIndex then
            self.pendingUnreadDividerIndex = self.pendingUnreadDividerIndex + 1
        end
        messageIndex = insertIndex
    end
    local token = GetStoreToken(data._store)
    local isActiveSelected = not inform
        and self.detailFrame
        and self.detailFrame:IsShown()
        and self.selectedKey == data.key

    if deferred and (inform or alreadyRead) then
        -- 历史发出消息不能清掉后来消息的未读状态。
    elseif inform then
        Manager._ClearConversationUnread(data)
    elseif isActiveSelected then
        data.received = true
        if self.pendingUnreadDividerKey ~= data.key or not tonumber(self.pendingUnreadDividerIndex) then
            self.pendingUnreadDividerKey = data.key
            self.pendingUnreadDividerToken = token
            self.pendingUnreadDividerIndex = messageIndex
        end
    else
        local currentUnread = GetUnreadCount(data)
        data.new = true
        data.received = true
        data.unreadCount = currentUnread + 1
        if deferred and tonumber(data.firstUnreadIndex) then
            data.firstUnreadIndex = math.min(data.firstUnreadIndex, insertIndex)
        elseif not tonumber(data.firstUnreadIndex) then
            data.firstUnreadIndex = currentUnread > 0 and math.max(1, messageIndex - currentUnread) or messageIndex
        end
    end

    local message = {
        text = text,
        time = deferred and deferred.time or time(),
        inform = inform and true or nil,
        receiptOrder = deferred and deferred.receiptOrder or self.nextMessageOrder,
        conversationKey = identity.key,
    }
    local cachedMessages = Manager.messageCache and Manager.messageCache[data._store]
    if cachedMessages then
        tinsert(cachedMessages, message)
        data.messages = cachedMessages
    elseif data.messages then
        tinsert(data.messages, message)
    end
    AddStoredMessage(data, message)
    storedMessages = data._store and data._store.messages
    if deferred and insertIndex < #storedMessages then
        tinsert(storedMessages, insertIndex, tremove(storedMessages))
        local messages = cachedMessages or data.messages
        if messages then tinsert(messages, insertIndex, tremove(messages)) end
    end
    if deferred then
        deferred.committed = true
        self.deferredChanged = true
    end

    local maxMessages = tonumber(db.maxMessages) or DEFAULT_MAX_MESSAGES
    while type(storedMessages) == "table" and #storedMessages > maxMessages do
        tremove(storedMessages, 1)
        if cachedMessages then
            tremove(cachedMessages, 1)
        elseif data.messages then
            tremove(data.messages, 1)
        end
        if data.firstUnreadIndex then
            data.firstUnreadIndex = math.max(1, data.firstUnreadIndex - 1)
        end
        if data.unreadCount and data.unreadCount > #storedMessages then
            data.unreadCount = #storedMessages
        end
    end
    SyncStoredControl(data)

    if not self.deferredBatch then TrimHistory(db) end

    if not deferred and not inform and db.sound then PlayNotification(db) end

    FireCompat("OnNewMessage", data.name, data.class, text, inform)
    BroadcastUpdate()
    return true
end

-- Deferred whisper recovery: only ordinary values live in this session queue.
do
    local LIMIT, BATCH, RETRIES = 2000, 20, 60
    local function Count(manager, key)
        manager.deferredStats = manager.deferredStats or {}
        manager.deferredStats[key] = (manager.deferredStats[key] or 0) + 1
    end

    function Manager:StopDeferredWhispers(clear, preserveCompleted)
        if self.deferredTimer then self.deferredTimer:Cancel(); self.deferredTimer = nil end
        if clear then
            self.deferredQueue = nil
            self.deferredSeen = nil
            self.deferredReadAt = nil
            self.deferredDeleted = nil
            if not preserveCompleted then
                self.deferredCompleted = nil
                self.deferredCompletedOrder = nil
            end
        end
    end

    function Manager:ScheduleDeferredWhispers()
        if self.deferredTimer or not self.enabled or not self.deferredQueue or #self.deferredQueue == 0 then return end
        if _G.C_Timer and _G.C_Timer.NewTimer then
            local timer
            timer = _G.C_Timer.NewTimer(1, function()
                if self.deferredTimer ~= timer then return end
                self.deferredTimer = nil
                local ok = pcall(self.FlushDeferredWhispers, self)
                if not ok then
                    self.deferredBatch = nil
                    Count(self, "errors")
                end
                self:ScheduleDeferredWhispers()
            end)
            self.deferredTimer = timer
        end
    end

    function Manager:DeferIdentityWhisper(name, text, inform, bnid)
        if not self.enabled or not (_G.C_Timer and _G.C_Timer.NewTimer) then
            Count(self, "unsupported")
            return
        end
        local queue = self.deferredQueue or {}
        if #queue >= LIMIT then Count(self, "overflow"); return end
        self.deferredQueue = queue
        self.nextMessageOrder = (self.nextMessageOrder or time() * 1000000) + 1
        local key = "identity:" .. self.nextMessageOrder
        queue[#queue + 1] = { key = key, readable = true,
            event = inform and "CHAT_MSG_BN_WHISPER_INFORM" or "CHAT_MSG_BN_WHISPER",
            time = time(), receiptOrder = self.nextMessageOrder, attempts = 0,
            args = { [1] = text, [2] = name, [13] = bnid } }
        self.deferredSeen = self.deferredSeen or {}
        self.deferredSeen[key] = true
        Count(self, "queued")
        self:ScheduleDeferredWhispers()
        local db = GetDB()
        if not inform and db and db.sound then PlayNotification(db) end
    end

    function Manager:DeferWhisper(eventName, ...)
        local lineID = select(11, ...)
        local validID = not IsSecretValue(lineID) and type(lineID) == "number"
            and lineID > 0 and lineID < math.huge and lineID == math.floor(lineID)
        local key = validID and (eventName .. ":" .. lineID)
        if key and self.deferredSeen and self.deferredSeen[key] then return true end
        if key and self.deferredCompleted and self.deferredCompleted[key] then return true end
        if not HasAnySecretValue(...) then return false end
        if not validID or not YUI.IsRetail or not Social.SupportsChatHistoryRecovery
            or not Social.SupportsChatHistoryRecovery() or not (_G.C_Timer and _G.C_Timer.NewTimer) then
            Count(self, "unsupported")
            return true
        end
        local queue = self.deferredQueue or {}
        self.deferredQueue = queue
        if #queue >= LIMIT then Count(self, "overflow"); return true end
        -- 不保存附带的 secret、表或未使用参数；过滤器只接收重建后的普通参数。
        local args = {}
        for i = 1, 17 do
            local value = select(i, ...)
            if not IsSecretValue(value) and (type(value) == "string" or type(value) == "number" or type(value) == "boolean") then
                args[i] = value
            end
        end
        self.nextMessageOrder = (self.nextMessageOrder or time() * 1000000) + 1
        queue[#queue + 1] = { key = key, event = eventName, lineID = lineID, time = time(),
            receiptOrder = self.nextMessageOrder, args = args, attempts = 0 }
        self.deferredSeen = self.deferredSeen or {}
        self.deferredSeen[key] = true
        Count(self, "queued")
        self:ScheduleDeferredWhispers()
        return true
    end

    function Manager:RecoverDeferredWhisper(entry)
        if entry.committed then return true, "saved" end
        local line, reason
        if entry.readable then
            line = { text = entry.args[1], name = entry.args[2] }
        else
            line, reason = Social.ReadChatHistoryLine(entry.lineID)
        end
        if not line then return false, reason end
        local args = entry.args
        -- 若当时已有可读身份，补取结果必须与其一致，避免消息编号错配。
        if args[2] and args[2] ~= "" and args[2] ~= line.name then return false, "identityMismatch" end
        local bn = entry.event == "CHAT_MSG_BN_WHISPER" or entry.event == "CHAT_MSG_BN_WHISPER_INFORM"
        local inform = entry.event == "CHAT_MSG_WHISPER_INFORM" or entry.event == "CHAT_MSG_BN_WHISPER_INFORM"
        local name, class, bnid, playerInfo, resolvedBNInfo = line.name
        if bn then
            local ok, info = pcall(Social.ResolveWhisperFriend, name, args[13])
            if not ok or not info or HasAnySecretValue(info.battleTag, info.bnetID) or not IsBattleTag(info.battleTag) then
                return false, "identity"
            end
            name, class, bnid = info.battleTag, "BN", info.bnetID
            resolvedBNInfo = info
        elseif args[6] == "GM" or args[6] == "DEV" then
            class = "GM"
        else
            playerInfo = GetPlayerInfoByGUIDSafe(line.guid)
            class = playerInfo and playerInfo.classFile
        end
        -- 保留收到事件时的身份，重试时不得将其替换为后续查询结果。
        if not bn and not inform then
            if args[16] then return true end
            local filterArgs = {}
            for i = 1, 17 do filterArgs[i] = args[i] end
            filterArgs[1], filterArgs[2], filterArgs[12] = line.text, line.name, line.guid
            if class ~= "GM" and ShouldFilterIncoming(entry.event, unpack(filterArgs, 1, 17)) then return true end
        end
        local saved = self:ProcessChatMessage(name, class, line.text, inform, bnid, playerInfo, entry, resolvedBNInfo)
        return true, saved and "saved" or "filtered"
    end

    function Manager:FlushDeferredWhispers()
        local queue = self.deferredQueue
        if not self.enabled or not queue or #queue == 0 then return end
        local locked = Social.IsChatHistoryLocked()
        self.deferredBatch = true
        local processed = math.min(BATCH, #queue)
        for _ = 1, processed do
            local entry = tremove(queue, 1)
            local ok, done, reason
            if locked and not entry.readable then
                ok, done, reason = true, false, "locked"
            else
                ok, done, reason = pcall(self.RecoverDeferredWhisper, self, entry)
            end
            if ok and done then
                Count(self, reason or "filtered")
                self.deferredSeen[entry.key] = nil
                self.deferredCompleted = self.deferredCompleted or {}
                self.deferredCompletedOrder = self.deferredCompletedOrder or {}
                self.deferredCompleted[entry.key] = true
                tinsert(self.deferredCompletedOrder, entry.key)
                if #self.deferredCompletedOrder > LIMIT then
                    self.deferredCompleted[tremove(self.deferredCompletedOrder, 1)] = nil
                end
            else
                if not ok or reason ~= "locked" then entry.attempts = entry.attempts + 1 end
                self.deferredStats.lastFailure = ok and reason or "error"
                if entry.attempts < RETRIES then
                    queue[#queue + 1] = entry
                else
                    Count(self, "failed")
                    self.deferredSeen[entry.key] = nil
                end
            end
        end
        self.deferredBatch = nil
        if self.deferredChanged then
            self.deferredChanged = nil
            -- 使用本批写入的存储视图，排序前不能再次触发 GetDB 的历史裁剪。
            local db = self.dbProxy
            if db then
                table.sort(db.history, function(a, b)
                    local left, right = GetLatestRuntimeMessage(a), GetLatestRuntimeMessage(b)
                    if left and right and left.time == right.time then
                        return (left.receiptOrder or 0) > (right.receiptOrder or 0)
                    end
                    return (left and left.time or 0) > (right and right.time or 0)
                end)
                TrimHistory(db)
            end
            BroadcastUpdate()
        end
        if #queue == 0 then self:StopDeferredWhispers(true, true) end
    end

    function Manager:GetDeferredWhisperStatus()
        local result = { pending = self.deferredQueue and #self.deferredQueue or 0,
            timerActive = self.deferredTimer ~= nil }
        for key, value in pairs(self.deferredStats or {}) do result[key] = value end
        return result
    end
end

function Manager:CHAT_MSG_WHISPER(eventName, ...)
    if self:DeferWhisper(eventName, ...) then return end

    local text, name, _, _, _, flag, _, _, _, _, _, guid, _, _, _, hide = ...
    if hide then return end

    local class, playerInfo
    if flag == "GM" or flag == "DEV" then
        class = "GM"
    else
        if ShouldFilterIncoming(eventName, ...) then
            return
        end

        playerInfo = GetPlayerInfoByGUIDSafe(guid)
        class = playerInfo and playerInfo.classFile or GetClassByGUID(guid)
    end

    self:ProcessChatMessage(name, class, text, nil, nil, playerInfo)
end

function Manager:CHAT_MSG_WHISPER_INFORM(eventName, ...)
    if self:DeferWhisper(eventName, ...) then return end

    local text, name, _, _, _, flag, _, _, _, _, _, guid = ...
    local class, playerInfo
    if flag == "GM" or flag == "DEV" or (GMChatFrame_IsGM and GMChatFrame_IsGM(name)) then
        class = "GM"
    else
        playerInfo = GetPlayerInfoByGUIDSafe(guid)
        class = playerInfo and playerInfo.classFile or GetClassByGUID(guid)
    end

    self:ProcessChatMessage(name, class, text, true, nil, playerInfo)
end

function Manager:CHAT_MSG_BN_WHISPER(eventName, ...)
    if self:DeferWhisper(eventName, ...) then return end

    local text, name = ...
    local bnid = select(13, ...)
    self:ProcessChatMessage(name, "BN", text, nil, bnid)
end

function Manager:CHAT_MSG_BN_WHISPER_INFORM(eventName, ...)
    if self:DeferWhisper(eventName, ...) then return end

    local text, name = ...
    local bnid = select(13, ...)
    self:ProcessChatMessage(name, "BN", text, true, bnid)
end

function Manager:PLAYER_LOGOUT()
    local db = GetDB()
    if not db then
        return
    end

    if not db.saveMessages and type(db.history) == "table" then
        for _, stored in ipairs(db.history) do
            if type(stored) == "table" and stored.protected then
                self:SyncStoredConversation(stored)
            end
        end
        self:RemoveUnprotectedConversations(db)
        return
    end

    for _, data in pairs(self.headerCache or {}) do
        SyncStoredIdentity(data)
    end
    for stored, messages in pairs(self.messageCache or {}) do
        local data = self.headerCache and self.headerCache[stored] or { _store = stored }
        data.messages = messages
        SyncStoredMessages(data)
    end
end

local function SaveWindowPosition(frame, key)
    if not frame then return end
    key = key or "window"
    local db = GetDB()
    if not db then return end
    if type(db[key]) ~= "table" then
        db[key] = {}
    end

    local point, _, relativePoint, x, y = frame:GetPoint(1)
    db[key].point = point or "CENTER"
    db[key].relativePoint = relativePoint or "CENTER"
    db[key].x = x or 0
    db[key].y = y or 0
    if frame.GetWidth then
        db[key].width = frame:GetWidth()
    end
    if frame.GetHeight then
        db[key].height = frame:GetHeight()
    end
end

local function RestoreWindowPosition(frame, key, fallback)
    if not frame then return end
    key = key or "window"
    local db = GetDB()
    local pos = db and db[key] or fallback or defaults.window

    frame:ClearAllPoints()
    frame:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x or 0, pos.y or 0)
end

local function FormatTimestamp(timestamp)
    return date("%m/%d %H:%M:%S", timestamp or time())
end

local function SetTextColor(text, key)
    if GUI2 and GUI2.SetTextColorKey then
        GUI2:SetTextColorKey(text, key)
    end
end

local function RemoveLastUTF8Char(text)
    local length = text and #text or 0
    if length <= 0 then
        return ""
    end

    local index = length
    while index > 1 do
        local byte = strbyte(text, index)
        if not byte or byte < 128 or byte > 191 then
            break
        end
        index = index - 1
    end

    return strsub(text, 1, index - 1)
end

local function SetFontStringTextToWidth(fontString, text, maxWidth)
    if not fontString then
        return
    end

    text = text or ""
    maxWidth = math.max(8, tonumber(maxWidth) or 8)
    if fontString.SetWidth then
        fontString:SetWidth(maxWidth)
    end
    if fontString.SetWordWrap then
        fontString:SetWordWrap(false)
    end
    if fontString.SetNonSpaceWrap then
        fontString:SetNonSpaceWrap(false)
    end
    if fontString.SetMaxLines then
        fontString:SetMaxLines(1)
    end

    fontString:SetText(text)
    if not fontString.GetStringWidth or (fontString:GetStringWidth() or 0) <= maxWidth then
        return fontString.GetStringWidth and math.min(maxWidth, math.ceil(fontString:GetStringWidth() or 0)) or maxWidth
    end

    local ellipsis = "..."
    local trimmed = text
    while trimmed ~= "" do
        trimmed = RemoveLastUTF8Char(trimmed)
        local candidate = trimmed .. ellipsis
        fontString:SetText(candidate)
        if (fontString:GetStringWidth() or 0) <= maxWidth then
            return math.min(maxWidth, math.ceil(fontString:GetStringWidth() or 0))
        end
    end

    fontString:SetText(ellipsis)
    return fontString.GetStringWidth and math.min(maxWidth, math.ceil(fontString:GetStringWidth() or 0)) or maxWidth
end

local function SetFontStringColor(fontString, color)
    if fontString and color and fontString.SetTextColor then
        fontString:SetTextColor(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
    end
end

local function SetTextureColor(texture, color)
    if not texture or not color then return end
    if texture.SetColorTexture then
        texture:SetColorTexture(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
    elseif texture.SetVertexColor then
        texture:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
    end
end

local function SetTextureGradient(texture, color, startAlpha, endAlpha)
    if not texture or not color then return end

    local r, g, b = color.r or 1, color.g or 1, color.b or 1
    if texture.SetGradient and CreateColor then
        texture:SetColorTexture(1, 1, 1, 1)
        texture:SetGradient("HORIZONTAL", CreateColor(r, g, b, startAlpha or 0), CreateColor(r, g, b, endAlpha or 1))
    elseif texture.SetGradientAlpha then
        texture:SetGradientAlpha("HORIZONTAL", r, g, b, startAlpha or 0, r, g, b, endAlpha or 1)
    elseif texture.SetColorTexture then
        texture:SetColorTexture(r, g, b, math.max(startAlpha or 0, endAlpha or 1))
    elseif texture.SetVertexColor then
        texture:SetVertexColor(r, g, b, math.max(startAlpha or 0, endAlpha or 1))
    end
end

local TOOLTIP_LINK_TYPES = {
    achievement = true,
    azessence = true,
    battlepet = true,
    conduit = true,
    currency = true,
    enchant = true,
    glyph = true,
    instancelock = true,
    item = true,
    journal = true,
    keystone = true,
    mawpower = true,
    mount = true,
    quest = true,
    spell = true,
    talent = true,
    trade = true,
    transmogappearance = true,
    transmogillusion = true,
    transmogset = true,
    unit = true,
}

local function IsTooltipHyperlink(linkData)
    if type(linkData) ~= "string" then
        return false
    end

    local linkType = linkData:match("^([^:]+)")
    return linkType and TOOLTIP_LINK_TYPES[linkType] == true
end

local function ConfigureHyperlinks(frame)
    if not frame then return end
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(true)
    end
    if frame.SetMouseMotionEnabled then
        frame:SetMouseMotionEnabled(true)
    end
    local supportsHyperlinks = frame.SetHyperlinksEnabled ~= nil
    if supportsHyperlinks then
        frame:SetHyperlinksEnabled(true)
    end
    if frame.SetHyperlinkPropagateToParent then
        frame:SetHyperlinkPropagateToParent(true)
    end
end

local function CreateManagerCloseButton(parent, onClick)
    if not GUI2 or not GUI2.CreateCloseButton or not parent then
        return nil
    end

    local close = GUI2:CreateCloseButton(parent, onClick)
    if not close then
        return nil
    end

    close:SetSize(CLOSE_BUTTON_SIZE, CLOSE_BUTTON_SIZE)
    if close.SetFrameLevel and parent.GetFrameLevel then
        close:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
    end
    if close.RefreshTheme then
        close:RefreshTheme()
    end
    if close.UpdateGUI2PixelScale then
        close:UpdateGUI2PixelScale()
    elseif close.UpdatePixelScale then
        close:UpdatePixelScale()
    end
    if close.gui2Borders then
        for _, texture in pairs(close.gui2Borders) do
            local valueType = type(texture)
            if valueType == "table" or valueType == "userdata" then
                if texture.SetSnapToPixelGrid then
                    texture:SetSnapToPixelGrid(true)
                end
                if texture.SetTexelSnappingBias then
                    texture:SetTexelSnappingBias(0)
                end
            end
        end
    end

    close:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(T("action.close"))
        GameTooltip:Show()
    end)
    close:HookScript("OnLeave", function()
        if GameTooltip then
            YUI.HideGameTooltip()
        end
    end)

    return close
end

function Manager:RegisterSpecialFrame(frame)
    local name = frame and frame.GetName and frame:GetName()
    if type(name) ~= "string" or name == "" or type(_G.UISpecialFrames) ~= "table" then
        return
    end

    for _, existingName in ipairs(_G.UISpecialFrames) do
        if existingName == name then
            return
        end
    end
    tinsert(_G.UISpecialFrames, name)
end

function Manager:CreateSettingsButton(parent, onClick)
    if not GUI2 or not parent then
        return nil
    end

    local opts = {
        size = 18,
        tooltip = T("button.settings"),
        tooltipAnchor = "ANCHOR_RIGHT",
        onClick = onClick,
    }
    if YUI.IsWrath then
        opts.atlas = "glues-characterSelect-icon-notify-inProgress-hover"
    end

    local button
    if GUI2.CreateBlizzardIconButton then
        button = GUI2:CreateBlizzardIconButton(parent, opts)
    end
    if not button and GUI2.CreateIconButton then
        opts.icon = "Interface\\Icons\\INV_Misc_Gear_01"
        opts.texCoords = { 0.12, 0.88, 0.12, 0.88 }
        opts.padding = 0
        opts.surface = "color.control.bg"
        opts.border = "color.border.subtle"
        button = GUI2:CreateIconButton(parent, opts)
    end
    if button and button.SetFrameLevel and parent.GetFrameLevel then
        button:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
    end
    return button
end

function Manager:CreateMessageHyperlinkHandler(parent)
    if not parent then
        return nil
    end

    local frame = self.detailFrame
    if frame and frame.messageHyperlinkHandler then
        return frame.messageHyperlinkHandler
    end

    local handler = parent
    if handler.SetHyperlinksEnabled then
        handler:SetHyperlinksEnabled(true)
    end
    if handler.SetHyperlinkPropagateToParent then
        handler:SetHyperlinkPropagateToParent(false)
    end
    handler.editBox = _G.ChatFrame1EditBox or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
    handler:SetScript("OnHyperlinkEnter", function(self, linkData)
        if not GameTooltip or not IsTooltipHyperlink(linkData) then
            return
        end

        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, linkData)
        if ok then
            GameTooltip:Show()
        else
            YUI.HideGameTooltip()
        end
    end)
    handler:SetScript("OnHyperlinkLeave", function()
        if GameTooltip then
            YUI.HideGameTooltip()
        end
    end)
    handler:SetScript("OnHyperlinkClick", function(self, linkData, linkText, button, ...)
        if ChatFrame_OnHyperlinkShow then
            local ok = pcall(ChatFrame_OnHyperlinkShow, self, linkData, linkText, button, ...)
            if ok then
                return
            end
        end
        if SetItemRef then
            pcall(SetItemRef, linkData, linkText, button, self)
        end
    end)

    if frame then
        frame.messageHyperlinkHandler = handler
    end
    return handler
end

function Manager:ApplyConversationListIcon(texture, data)
    if not texture or not data then
        return
    end

    if texture.SetTexCoord then
        texture:SetTexCoord(0, 1, 0, 1)
    end

    if data.class == "GM" or data.kind == "gm" then
        texture:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-Blizz")
        if texture.SetTexCoord then
            texture:SetTexCoord(0.18, 0.82, 0, 1)
        end
        texture:Show()
        return
    end

    if data.class == "BN" or data.kind == "bn" then
        texture:SetTexture("Interface\\FriendsFrame\\Battlenet-Portrait")
        texture:Show()
        return
    end

    local icon = Icons.GetClassIcon and Icons.GetClassIcon(data.class)
    if icon and Icons.ApplyIcon and Icons.ApplyIcon(texture, icon) then
        texture:Show()
    else
        texture:SetTexture(nil)
        texture:Hide()
    end
end

function Manager:ApplyConversationRaceIcon(target, data)
    local texture = target and (target.icon or target)
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

    local icon = Icons.GetRaceIcon and Icons.GetRaceIcon(data.raceFile, data.gender)
    if icon and Icons.ApplyIcon and Icons.ApplyIcon(texture, icon) then
        if target.Show then
            target:Show()
        end
        if texture.Show then
            texture:Show()
        end
        return true
    end

    if texture.SetTexture then
        texture:SetTexture(nil)
    end
    if texture.Hide and texture ~= target then
        texture:Hide()
    end
    if target.Hide then
        target:Hide()
    end
    return false
end

function Manager:GetConversationLevelTagText(data)
    if not data or data.kind ~= "player" then
        return nil
    end

    local level = tonumber(data.level)
    if level and level > 0 then
        return "[" .. FormatLocale("conversation.level", level) .. "]"
    end

    return nil
end

function Manager:GetConversationNameColor(data)
    if not data then
        return nil
    end

    if data.class == "GM" or data.kind == "gm" then
        return GM_NAME_COLOR
    end

    if data.class == "BN" or data.kind == "bn" then
        return BNET_NAME_COLOR
    end

    local class = data.class
    local classColors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
    return NormalizeColor(classColors and class and classColors[class])
end

function Manager:SetNameFontStringColor(fontString, data)
    if not fontString then
        return
    end

    local color = self:GetConversationNameColor(data)
    if color then
        SetFontStringColor(fontString, color)
    else
        SetTextColor(fontString, "color.text.primary")
    end
end

function Manager:SetRowUnreadVisual(row, hasUnread)
    if not row then
        return
    end

    hasUnread = hasUnread and true or false

    if row.unreadBg then
        row.unreadBg:ClearAllPoints()
        row.unreadBg:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.unreadBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        if GUI2 and GUI2.ApplyTexturePixelPolicy then
            GUI2:ApplyTexturePixelPolicy(row.unreadBg, { snapToPixelGrid = false, texelSnappingBias = 0 })
        end
        SetTextureColor(row.unreadBg, UNREAD_ROW_BG_COLOR)
        if hasUnread then
            row.unreadBg:Show()
        else
            row.unreadBg:Hide()
        end
    end

    if row.unreadDot then
        row.unreadDot:SetText(UNREAD_MARK)
        SetFontStringColor(row.unreadDot, UNREAD_DOT_COLOR)
        if hasUnread then
            row.unreadDot:Show()
        else
            row.unreadDot:Hide()
        end
    end
end

function Manager:IsRowCurrent(row)
    return row
        and row.key
        and (row.key == self.selectedKey or row.store == self.selectedStore)
end

function Manager:ApplyRowSelectionVisual(row, selected)
    if not row then
        return
    end

    selected = selected and true or false
    if selected and self.selectionLocked and row.SetState then
        row:SetState("locked")
    elseif row.SetSelected then
        row:SetSelected(selected)
    elseif row.SetState then
        row:SetState(selected and "selected" or "normal")
    end
end

function Manager:SetRowName(row, data, unreadCount)
    if not row or not data then
        return
    end

    self:PrimeConversationInfo(data, false)

    if row.typeIcon then
        self:ApplyConversationListIcon(row.typeIcon, data)
    end

    if row.favoriteIcon then
        if data.protected then
            row.favoriteIcon:SetText(FAVORITE_MARK)
            row.favoriteIcon:Show()
        else
            row.favoriteIcon:SetText("")
            row.favoriteIcon:Hide()
        end
    end

    local hasUnread = (tonumber(unreadCount) or 0) > 0
    if row.unreadText then
        row.unreadText:SetText("")
        row.unreadText:Hide()
    end
    self:SetRowUnreadVisual(row, hasUnread)

    local nameText = row.nameText or row.text
    if nameText then
        local rowWidth = row.GetWidth and (row:GetWidth() or 0) or 0
        if rowWidth <= 1 then
            rowWidth = LIST_ROW_WIDTH
        end
        local nameWidth = rowWidth
            - LIST_ROW_ICON_LEFT
            - LIST_ROW_ICON_SIZE
            - LIST_ROW_TEXT_GAP
            - LIST_ROW_COLUMN_GAP
            - LIST_ROW_UNREAD_DOT_WIDTH
            - LIST_ROW_COLUMN_GAP
            - LIST_ROW_FAVORITE_WIDTH
            - LIST_ROW_RIGHT_PADDING
        local actualNameWidth = SetFontStringTextToWidth(nameText, self:GetDisplayName(data) or "", nameWidth) or nameWidth
        nameText:SetWidth(math.max(1, actualNameWidth))
        self:SetNameFontStringColor(nameText, data)
        nameText:Show()
        if row.unreadDot then
            row.unreadDot:ClearAllPoints()
            row.unreadDot:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
        end
    end
end

function Manager:RefreshConversationTitle(data)
    local frame = self.detailFrame
    if not frame then return end

    local prefix = frame.conversationTitlePrefix
    local raceIcon = frame.conversationTitleRaceIcon
    local icon = frame.conversationTitleIcon
    local name = frame.conversationTitleName
    local suffix = frame.conversationTitleSuffix
    local levelTag = frame.conversationLevelTag
    local statusTag = frame.conversationStatusTag
    if not prefix or not icon or not name or not suffix then
        return
    end

    if not data then
        prefix:Hide()
        if raceIcon then raceIcon:Hide() end
        icon:Hide()
        name:Hide()
        suffix:Hide()
        if levelTag then levelTag:Hide() end
        if statusTag then statusTag:Hide() end
        return
    end

    self:PrimeConversationInfo(data, true)

    prefix:SetText(T("conversation.title_prefix"))
    suffix:SetText(T("conversation.title_suffix"))
    local hasRaceIcon = raceIcon and self:ApplyConversationRaceIcon(raceIcon, data)
    self:ApplyConversationListIcon(icon, data)
    icon:ClearAllPoints()
    if hasRaceIcon then
        icon:SetPoint("LEFT", raceIcon, "RIGHT", TITLE_GAP, 0)
    else
        icon:SetPoint("LEFT", prefix, "RIGHT", TITLE_GAP, 0)
    end
    name:ClearAllPoints()
    name:SetPoint("LEFT", icon, "RIGHT", TITLE_GAP, 0)

    prefix:Show()
    name:Show()
    if (suffix:GetText() or "") ~= "" then
        suffix:Show()
    else
        suffix:Hide()
    end

    local levelText = levelTag and self:GetConversationLevelTagText(data)
    if levelTag and levelText then
        levelTag:SetText(levelText)
        SetTextColor(levelTag, "color.text.secondary")
        levelTag:Show()
    elseif levelTag then
        levelTag:SetText("")
        levelTag:Hide()
    end

    if statusTag then
        local online = self:GetKnownPresence(data)
        if online == true then
            statusTag:SetText(T("conversation.online"))
            SetFontStringColor(statusTag, ONLINE_STATUS_COLOR)
            statusTag:Show()
        elseif online == false then
            statusTag:SetText(T("conversation.offline"))
            SetFontStringColor(statusTag, OFFLINE_STATUS_COLOR)
            statusTag:Show()
        else
            statusTag:SetText("")
            statusTag:Hide()
        end
    end

    local panelWidth = frame.messagePanel and frame.messagePanel.GetWidth and (frame.messagePanel:GetWidth() or 0) or 0
    if panelWidth <= 1 and frame.GetWidth then
        panelWidth = (frame:GetWidth() or DETAIL_WINDOW_WIDTH) - 28
    end
    local prefixWidth = prefix.GetStringWidth and math.ceil(prefix:GetStringWidth() or 0) or 12
    local suffixWidth = suffix.GetStringWidth and math.ceil(suffix:GetStringWidth() or 0) or 36
    prefix:SetWidth(math.max(1, prefixWidth))
    suffix:SetWidth(math.max(1, suffixWidth))

    local tagWidth = 0
    if levelTag and levelTag:IsShown() then
        local width = levelTag.GetStringWidth and math.ceil(levelTag:GetStringWidth() or 0) or TITLE_STATUS_WIDTH
        width = math.max(1, width + 2)
        levelTag:SetWidth(width)
        tagWidth = tagWidth + TITLE_GAP + width
    end
    if statusTag and statusTag:IsShown() then
        local width = statusTag.GetStringWidth and math.ceil(statusTag:GetStringWidth() or 0) or TITLE_STATUS_WIDTH
        width = math.max(1, width + 2)
        statusTag:SetWidth(width)
        tagWidth = tagWidth + TITLE_GAP + width
    end

    local titleWidth = panelWidth - MESSAGE_PANEL_PADDING - MESSAGE_SCROLLBAR_INSET - TITLE_RIGHT_RESERVED
    local iconWidth = TITLE_ICON_SIZE + TITLE_GAP
    if hasRaceIcon then
        iconWidth = iconWidth + TITLE_ICON_SIZE + TITLE_GAP
    end
    local nameWidth = titleWidth - prefixWidth - TITLE_GAP - iconWidth - suffixWidth - tagWidth
    nameWidth = math.max(48, math.floor(nameWidth))
    local actualNameWidth = SetFontStringTextToWidth(name, self:GetDisplayName(data) or "", nameWidth) or nameWidth
    name:SetWidth(math.max(1, actualNameWidth))
    self:SetNameFontStringColor(name, data)

    if levelTag then
        levelTag:ClearAllPoints()
        levelTag:SetPoint("LEFT", suffix, "RIGHT", TITLE_GAP, 0)
    end
    if statusTag then
        statusTag:ClearAllPoints()
        if levelTag and levelTag:IsShown() then
            statusTag:SetPoint("LEFT", levelTag, "RIGHT", TITLE_GAP, 0)
        else
            statusTag:SetPoint("LEFT", suffix, "RIGHT", TITLE_GAP, 0)
        end
        statusTag:SetJustifyH("LEFT")
    end
end

function Manager:GetSelectedConversation()
    if self.selectedStore then
        local data = EnsureRuntimeHeader(self.selectedStore)
        if data then
            return data
        end
    end

    local db = GetDB()
    local _, data = FindConversation(db, self.selectedKey)
    if data then
        self.selectedStore = data._store
        self.selectedToken = GetStoreToken(data._store)
    end
    return data
end

function Manager:GetConversationFullName(data)
    if not data then
        return ""
    end

    if data.kind == "bn" then
        local ignoredID, ignoredName, battleTag
        if ResolveBNRuntimeInfo then
            ignoredID, ignoredName, battleTag = ResolveBNRuntimeInfo(data)
        end
        return battleTag or data.battleTag or data.name or ""
    end

    return data.name or self:GetDisplayName(data, true) or self:GetDisplayName(data) or ""
end

function Manager:BuildExportText(data)
    local lines = {}
    local messages = data and EnsureRuntimeMessages(data)
    if type(messages) ~= "table" then
        return ""
    end

    for _, message in ipairs(messages) do
        local direction = message.inform and T("message.to") or T("message.from")
        tinsert(lines, format("[%s] %s: %s", FormatTimestamp(message.time), direction, message.text or ""))
    end

    return table_concat(lines, "\n")
end

function Manager:RefreshCopyEditBoxLayout()
    local frame = self.detailFrame
    local scrollFrame = frame and frame.copyScrollFrame
    local editBox = frame and frame.copyEditBox
    if not scrollFrame or not editBox then
        return
    end

    local width = scrollFrame.GetWidth and (scrollFrame:GetWidth() or 0) or 0
    if width <= 1 and frame.copyPanel and frame.copyPanel.GetWidth then
        width = (frame.copyPanel:GetWidth() or 0) - MESSAGE_SCROLLBAR_INSET - (COPY_EDIT_INSET * 2)
    end
    width = math.max(32, math.floor(width))
    editBox:SetWidth(width)

    local lineCount = 1
    if editBox.GetNumLines then
        lineCount = tonumber(editBox:GetNumLines()) or lineCount
    end
    if lineCount <= 1 and editBox.GetText then
        local text = editBox:GetText() or ""
        local _, newLineCount = gsub(text, "\n", "")
        lineCount = math.max(lineCount, (tonumber(newLineCount) or 0) + 1)
    end

    local lineHeight = COPY_EDIT_LINE_HEIGHT
    if editBox.GetFont then
        local _, fontHeight = editBox:GetFont()
        fontHeight = tonumber(fontHeight)
        if fontHeight then
            lineHeight = math.max(lineHeight, math.ceil(fontHeight + 4))
        end
    end

    local viewportHeight = scrollFrame.GetHeight and (scrollFrame:GetHeight() or 0) or 0
    local height = math.max(viewportHeight, (lineCount * lineHeight) + (COPY_EDIT_INSET * 2))
    editBox:SetHeight(math.max(1, math.floor(height)))

    if scrollFrame.UpdateScrollChildRect then
        scrollFrame:UpdateScrollChildRect()
    end
    if scrollFrame.gui2ScrollBar and scrollFrame.gui2ScrollBar.UpdateVisualThumb then
        scrollFrame.gui2ScrollBar:UpdateVisualThumb()
    end
end

function Manager:ShowCopyEditBox(text)
    local frame = self.detailFrame
    local editBox = frame and frame.copyEditBox
    if not editBox then
        return
    end

    if frame.messageScrollFrame then
        frame.messageScrollFrame:Hide()
    end
    if frame.emptyText then
        frame.emptyText:Hide()
    end

    if frame.copyPanel then
        frame.copyPanel:Show()
    end
    if frame.copyScrollFrame then
        frame.copyScrollFrame:Show()
        if frame.copyScrollFrame.SetVerticalScroll then
            frame.copyScrollFrame:SetVerticalScroll(0)
        end
    end
    editBox:SetText(text or "")
    editBox:Show()
    self:RefreshCopyEditBoxLayout()
    if editBox.SetCursorPosition then
        editBox:SetCursorPosition(0)
    end
    if editBox.HighlightText then
        editBox:HighlightText(0, -1)
    end
    if editBox.SetFocus then
        editBox:SetFocus()
    end
end

function Manager:HideCopyEditBox(skipRefresh)
    local frame = self.detailFrame
    local editBox = frame and frame.copyEditBox
    local copyPanel = frame and frame.copyPanel
    local copyScrollFrame = frame and frame.copyScrollFrame
    local isShown = (copyPanel and copyPanel:IsShown()) or (editBox and editBox:IsShown())
    if not editBox or not isShown or self.hidingCopyEditBox then
        return
    end

    self.hidingCopyEditBox = true
    editBox:Hide()
    if editBox.ClearFocus then
        editBox:ClearFocus()
    end
    if copyScrollFrame then
        copyScrollFrame:Hide()
    end
    if copyPanel then
        copyPanel:Hide()
    end
    if frame.messageScrollFrame then
        frame.messageScrollFrame:Show()
    end
    self.hidingCopyEditBox = nil

    if not skipRefresh then
        self:RefreshMessages()
    end
end

function Manager:PreviewConversation(key)
    if self.selectionLocked then
        return
    end

    self:SelectConversation(key, true, false)
end

function Manager:ToggleConversationLock(key)
    if not key then
        return
    end

    if self.selectionLocked and self.selectedKey == key then
        self.selectionLocked = false
        self:CancelHoverHide()
        self:RefreshList()
        return
    end

    self:SelectConversation(key, true, true)
end

function Manager:HideContextMenu()
    if self.contextMenu then
        self.contextMenu:Hide()
    end
end

function Manager:ShowNativeConversationMenu(data)
    if not data or not Social then
        return false
    end

    if data.kind == "bn" then
        local bnetID, accountName, battleTag, online
        if ResolveBNRuntimeInfo then
            bnetID, accountName, battleTag, online = ResolveBNRuntimeInfo(data)
        end
        local target = accountName or data.bnAccountName or data.displayName or data.name
        if Social.ShowBNetDropdown and target then
            local ok = Social.ShowBNetDropdown(target, {
                connected = online ~= false,
                bnetID = bnetID,
                battleTag = battleTag or data.battleTag,
            })
            if ok then
                return true
            end
        end
        return false
    end

    local name = GetConversationLookupName(data) or data.name
    if Social.ShowPlayerDropdown and name then
        local ok = Social.ShowPlayerDropdown(name, {
            connected = self:GetKnownPresence(data) ~= false,
            guid = data.guid,
        })
        if ok then
            return true
        end
    end

    return false
end

function Manager:ShowFallbackContextMenu(anchor, data)
    if not GUI2 or not GUI2.Form or not anchor or not data then
        return
    end

    local items = {
        { text = T("action.reply"), action = function() Manager:ReplySelected() end },
    }
    if data.kind == "player" then
        tinsert(items, { text = T("action.who"), action = function() Manager:WhoSelected() end })
    end
    tinsert(items, { text = T("action.invite"), disabled = not self:CanInviteConversation(data), action = function() Manager:InviteSelected() end })
    tinsert(items, { text = T("action.copy_name"), action = function() Manager:CopySelectedName() end })
    tinsert(items, { text = T("action.export_log"), action = function() Manager:ExportSelectedLog() end })
    tinsert(items, { text = T("action.delete"), disabled = data.protected, action = function() Manager:Delete() end })

    local menu = self.contextMenu
    if not menu then
        menu = GUI2:CreateFrame(UIParent, {
            name = "YUI_WhisperManagerContextMenu",
            template = "BackdropTemplate",
            surface = "color.surface.popup",
            border = "color.popup.border",
            shadow = true,
            shadowKey = "shadow.popup.size",
            mouse = true,
            hidden = true,
            frameStrata = "TOOLTIP",
        })
        self.contextMenu = menu
        menu.buttons = {}
        self:RegisterSpecialFrame(menu)
    end

    local width = 128
    local rowHeight = 24
    local padding = 8
    menu:SetSize(width + (padding * 2), (#items * (rowHeight + 4)) + (padding * 2) - 4)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)

    for index, item in ipairs(items) do
        local itemData = item
        local button = menu.buttons[index]
        if not button then
            button = GUI2.Form:CreateButton(menu, {
                width = width,
                height = rowHeight,
                tone = "default",
            })
            menu.buttons[index] = button
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", padding, -(padding + ((index - 1) * (rowHeight + 4))))
        if button.SetText then
            button:SetText(item.text)
        elseif button.text then
            button.text:SetText(item.text)
        end
        if button.SetDisabled then
            button:SetDisabled(itemData.disabled and true or false)
        end
        button:SetScript("OnClick", function()
            if itemData.disabled then
                return
            end
            Manager:HideContextMenu()
            itemData.action()
        end)
        button:Show()
    end
    for index = #items + 1, #(menu.buttons or {}) do
        menu.buttons[index]:Hide()
    end
    menu:Show()
end

function Manager:OpenConversationContextMenu(row)
    if not row or not row.key then
        return
    end

    self:SelectConversation(row.key, true, false)
    local data = self:GetSelectedConversation()
    if not data then
        return
    end

    self:CancelHoverHide()
    if self:ShowNativeConversationMenu(data) then
        self:HideContextMenu()
        return
    end
    self:ShowFallbackContextMenu(row, data)
end

function Manager:ReplyConversationFromRow(row)
    if not row or not row.key then
        return
    end

    self:HideContextMenu()
    self:SelectConversation(row.key, true, false)
    self:ReplySelected()
end

function Manager:HandleRowClick(row, button)
    if button == "RightButton" then
        self:OpenConversationContextMenu(row)
    elseif button == "LeftButton" or button == nil then
        self:ReplyConversationFromRow(row)
    end
end

function Manager:HandleRowEnter(row)
    if not row or not row.key then
        return
    end

    if self.selectionLocked then
        if self:IsRowCurrent(row) then
            self:ApplyRowSelectionVisual(row, true)
        end
        return
    end

    self:PreviewConversation(row.key)
end

function Manager:HandleRowLeave(row)
    if not row then
        return
    end

    if self.selectionLocked then
        if self:IsRowCurrent(row) then
            self:ApplyRowSelectionVisual(row, true)
        end
        return
    end

    if self:IsRowCurrent(row) then
        self:ScheduleHoverHide()
    end
end

function Manager:SelectConversation(key, openDetail, locked)
    local db = GetDB()
    local _, data = FindConversation(db, key)
    if not data then
        self:ClearCurrentSelection()
        self:RefreshFrame()
        return
    end

    local previousKey = self.selectedKey
    if previousKey and previousKey ~= data.key then
        self:HideCopyEditBox(true)
        self.pendingUnreadDividerKey = nil
        self.pendingUnreadDividerToken = nil
        self.pendingUnreadDividerIndex = nil
    end

    self.selectedKey = data.key
    self.selectedStore = data._store
    self.selectedToken = GetStoreToken(data._store)
    self.selectionLocked = locked ~= false
    self:CancelHoverHide()
    if openDetail ~= false then
        self:ShowDetailWindow()
    end
    local hadNew = data.new
    if hadNew then
        local unreadCount = GetUnreadCount(data)
        self.pendingUnreadDividerKey = data.key
        self.pendingUnreadDividerToken = self.selectedToken
        local storedMessages = data._store and (data._store.messages or data._store.encodedMessages)
        local messageCount = type(storedMessages) == "table" and #storedMessages or 0
        self.pendingUnreadDividerIndex = tonumber(data.firstUnreadIndex) or math.max(1, (messageCount - unreadCount) + 1)
    end
    local clearedUnread = Manager._ClearConversationUnread(data, { keepDivider = true })
    if hadNew or clearedUnread then
        BroadcastUpdate()
    else
        self:RefreshFrame()
    end
end

function Manager:GetListPageInfo()
    local db = GetDB()
    if not db then
        return nil, 1, 1, 1, 0, {}
    end

    local visibleHistory = self:GetVisibleHistory(db)
    local totalItems = #visibleHistory
    local totalPages = math.max(1, math.ceil(totalItems / ROW_COUNT))
    local currentPage = tonumber(self.currentPage) or 1
    if currentPage < 1 then currentPage = 1 end
    if currentPage > totalPages then currentPage = totalPages end
    self.currentPage = currentPage

    local offset = ((currentPage - 1) * ROW_COUNT) + 1
    return db, currentPage, totalPages, offset, totalItems, visibleHistory
end

function Manager:SetListPage(page)
    local _, currentPage, totalPages = self:GetListPageInfo()
    local nextPage = tonumber(page) or currentPage or 1
    if nextPage < 1 then nextPage = 1 end
    if nextPage > totalPages then nextPage = totalPages end

    if nextPage ~= self.currentPage then
        self.currentPage = nextPage
        self:RefreshList()
    elseif self.listFrame or self.frame then
        self:RefreshListPager()
    end
end

function Manager:ScrollList(delta)
    self:SetListPage((self.currentPage or 1) + (tonumber(delta) or 0))
end

function Manager:RefreshListPager()
    local frame = self.listFrame or self.frame
    if not frame then return end

    local _, currentPage, totalPages = self:GetListPageInfo()
    self:RefreshListTabs()
    if frame.pageText then
        frame.pageText:SetText(format("%d/%d", currentPage, totalPages))
    end
    if frame.prevButton then
        frame.prevButton:SetDisabled(currentPage <= 1)
    end
    if frame.nextButton then
        frame.nextButton:SetDisabled(currentPage >= totalPages)
    end
end

function Manager:GetRandomTestMessage(baseKey, sequence)
    local key = math.random(1, 2) == 2 and (baseKey .. "_long") or baseKey
    local message = FormatLocale(key, sequence)
    if message == key then
        message = FormatLocale(baseKey, sequence)
    end
    return message
end

function Manager:AddTestNewConversation()
    self.testSequence = (self.testSequence or 0) + 1
    local db = GetDB()
    local prefix = FormatLocale("dev.player_prefix")
    local class = TEST_CLASSES[math.random(1, #TEST_CLASSES)] or "MAGE"
    local name = prefix .. math.random(1000, 9999)
    for _ = 1, 10 do
        local identity = BuildIdentity(name, class)
        if not FindConversation(db, identity and identity.key) then
            break
        end
        name = prefix .. math.random(1000, 9999) .. self.testSequence
    end
    local message = self:GetRandomTestMessage("dev.message.new_incoming", self.testSequence)
    self:ProcessChatMessage(name, class, message, false)
end

function Manager:AddTestMessageToSelected()
    local data = self:GetSelectedConversation()
    if not data then
        self:AddTestNewConversation()
        return
    end

    self.testSequence = (self.testSequence or 0) + 1
    local inform = math.random(1, 2) == 2
    local messageKey = inform and "dev.message.current_outgoing" or "dev.message.current_incoming"
    local message = self:GetRandomTestMessage(messageKey, self.testSequence)
    self:ProcessChatMessage(data.name, data.class, message, inform, data.bnid)
end

function Manager:RefreshDevTools()
    local frame = self.detailFrame
    if not frame or not frame.devNewButton or not frame.devCurrentButton then
        return
    end

    if YUI.IsDev == true then
        frame.devNewButton:Show()
        frame.devCurrentButton:Show()
    else
        frame.devNewButton:Hide()
        frame.devCurrentButton:Hide()
    end
end

function Manager:GetMessageTimestampWidth()
    local frame = self.detailFrame
    if not frame then
        return 112
    end

    local sizer = frame.timestampSizer
    if not sizer and frame.messageScrollChild and frame.messageScrollChild.CreateFontString then
        sizer = frame.messageScrollChild:CreateFontString(nil, "BACKGROUND")
        sizer:Hide()
        frame.timestampSizer = sizer
    end
    if not sizer then
        return 112
    end

    if ChatFontNormal and sizer.SetFontObject then
        sizer:SetFontObject(ChatFontNormal)
    end
    if sizer.SetText then
        sizer:SetText(TIMESTAMP_SAMPLE)
    end

    local width = 112
    if sizer.GetUnboundedStringWidth then
        width = sizer:GetUnboundedStringWidth()
    elseif sizer.GetStringWidth then
        width = sizer:GetStringWidth()
    end
    return math.ceil((tonumber(width) or 112) + 2)
end

function Manager:AcquireMessageRow(index)
    local frame = self.detailFrame
    local parent = frame and frame.messageScrollChild
    if not frame or not parent or not GUI2 then
        return nil
    end

    frame.messageRows = frame.messageRows or {}
    local row = frame.messageRows[index]
    if row then
        row:Show()
        return row
    end

    row = GUI2:CreateFrame(parent, {
        width = 1,
        height = MESSAGE_MIN_ROW_HEIGHT,
        mouse = true,
    })
    ConfigureHyperlinks(row)

    local timestamp = row:CreateFontString(nil, "ARTWORK")
    timestamp:SetJustifyH("LEFT")
    timestamp:SetJustifyV("TOP")
    if ChatFontNormal then
        timestamp:SetFontObject(ChatFontNormal)
    end
    row.timestampText = timestamp

    local separator = row:CreateTexture(nil, "ARTWORK")
    separator:SetTexture("Interface\\Buttons\\WHITE8x8")
    SetTextureColor(separator, TIMESTAMP_COLOR)
    row.separatorBar = separator

    local body = row:CreateFontString(nil, "ARTWORK")
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetWordWrap(true)
    body:SetNonSpaceWrap(true)
    if body.SetIndentedWordWrap then
        body:SetIndentedWordWrap(false)
    end
    if ChatFontNormal then
        body:SetFontObject(ChatFontNormal)
    end
    ConfigureHyperlinks(body)
    row.bodyText = body

    frame.messageRows[index] = row
    return row
end

function Manager:LayoutMessageRow(row, message, yOffset, contentWidth)
    if not row or not message then
        return 0
    end

    local db = GetDB()
    local showTimestamp = not db or db.timestamp ~= false
    local timestampWidth = showTimestamp and self:GetMessageTimestampWidth() or 0
    local separatorX = timestampWidth + MESSAGE_SEPARATOR_GAP
    local bodyLeft = showTimestamp and (separatorX + MESSAGE_SEPARATOR_WIDTH + MESSAGE_BODY_GAP) or 0
    local bodyWidth = math.max(24, (tonumber(contentWidth) or 1) - bodyLeft - 2)
    local color = message.inform and OUTGOING_MESSAGE_COLOR or INCOMING_MESSAGE_COLOR
    local prefix = message.inform and T("message.to") or T("message.from")

    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", 0, -yOffset)
    row:SetPoint("TOPRIGHT", row:GetParent(), "TOPRIGHT", 0, -yOffset)
    row:SetWidth(contentWidth)

    local body = row.bodyText
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", row, "TOPLEFT", bodyLeft, 0)
    body:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, 0)
    body:SetWidth(bodyWidth)
    body:SetText(format("%s: %s", prefix, message.text or ""))
    SetFontStringColor(body, color)
    body:Show()

    local bodyHeight = MESSAGE_MIN_ROW_HEIGHT
    if body.GetStringHeight then
        bodyHeight = math.ceil(tonumber(body:GetStringHeight()) or bodyHeight)
    elseif body.GetHeight then
        bodyHeight = math.ceil(tonumber(body:GetHeight()) or bodyHeight)
    end
    local rowHeight = math.max(MESSAGE_MIN_ROW_HEIGHT, bodyHeight)
    row:SetHeight(rowHeight)

    if showTimestamp then
        local timestamp = row.timestampText
        timestamp:ClearAllPoints()
        timestamp:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        timestamp:SetWidth(timestampWidth)
        timestamp:SetText("[" .. FormatTimestamp(message.time) .. "]")
        SetFontStringColor(timestamp, TIMESTAMP_COLOR)
        timestamp:Show()

        local separator = row.separatorBar
        separator:ClearAllPoints()
        separator:SetPoint("TOPLEFT", row, "TOPLEFT", separatorX, 0)
        separator:SetSize(MESSAGE_SEPARATOR_WIDTH, rowHeight)
        SetTextureColor(separator, TIMESTAMP_COLOR)
        separator:Show()
    else
        row.timestampText:Hide()
        row.separatorBar:Hide()
    end

    row:Show()
    return rowHeight
end

function Manager:AcquireMessageDivider(index)
    local frame = self.detailFrame
    local parent = frame and frame.messageScrollChild
    if not frame or not parent or not GUI2 then
        return nil
    end

    frame.messageDividers = frame.messageDividers or {}
    local divider = frame.messageDividers[index]
    if divider then
        divider:Show()
        return divider
    end

    divider = GUI2:CreateFrame(parent, {
        width = 1,
        height = MESSAGE_DIVIDER_HEIGHT,
    })

    local leftLine = divider:CreateTexture(nil, "ARTWORK")
    leftLine:SetTexture("Interface\\Buttons\\WHITE8x8")
    SetTextureColor(leftLine, DIVIDER_COLOR)
    divider.leftLine = leftLine

    local rightLine = divider:CreateTexture(nil, "ARTWORK")
    rightLine:SetTexture("Interface\\Buttons\\WHITE8x8")
    SetTextureColor(rightLine, DIVIDER_COLOR)
    divider.rightLine = rightLine

    local label = divider:CreateFontString(nil, "ARTWORK")
    label:SetJustifyH("CENTER")
    label:SetJustifyV("MIDDLE")
    if ChatFontNormal then
        label:SetFontObject(ChatFontNormal)
    end
    SetFontStringColor(label, DIVIDER_COLOR)
    divider.label = label

    frame.messageDividers[index] = divider
    return divider
end

function Manager:LayoutMessageDivider(divider, yOffset, contentWidth)
    if not divider then
        return 0
    end

    divider:ClearAllPoints()
    divider:SetPoint("TOPLEFT", divider:GetParent(), "TOPLEFT", 0, -yOffset)
    divider:SetPoint("TOPRIGHT", divider:GetParent(), "TOPRIGHT", 0, -yOffset)
    divider:SetWidth(contentWidth)
    divider:SetHeight(MESSAGE_DIVIDER_HEIGHT)

    local label = divider.label
    label:ClearAllPoints()
    label:SetPoint("CENTER", divider, "CENTER", 0, 0)
    label:SetText(T("message.new_divider"))
    SetFontStringColor(label, DIVIDER_COLOR)
    label:Show()

    local lineInset = 20
    divider.leftLine:ClearAllPoints()
    divider.leftLine:SetPoint("LEFT", divider, "LEFT", lineInset, 0)
    divider.leftLine:SetPoint("RIGHT", label, "LEFT", -10, 0)
    divider.leftLine:SetHeight(1)
    SetTextureGradient(divider.leftLine, DIVIDER_COLOR, 0.08, 0.88)
    divider.leftLine:Show()

    divider.rightLine:ClearAllPoints()
    divider.rightLine:SetPoint("LEFT", label, "RIGHT", 10, 0)
    divider.rightLine:SetPoint("RIGHT", divider, "RIGHT", -lineInset, 0)
    divider.rightLine:SetHeight(1)
    SetTextureGradient(divider.rightLine, DIVIDER_COLOR, 0.88, 0.08)
    divider.rightLine:Show()

    divider:Show()
    return MESSAGE_DIVIDER_HEIGHT
end

function Manager:RefreshMessageScrollRange(contentHeight)
    local frame = self.detailFrame
    if not frame or not frame.messageScrollFrame or not frame.messageScrollChild then
        return
    end

    local scrollFrame = frame.messageScrollFrame
    local child = frame.messageScrollChild
    local viewportHeight = scrollFrame.GetHeight and (scrollFrame:GetHeight() or 0) or 0
    local height = math.max(MESSAGE_MIN_ROW_HEIGHT, tonumber(contentHeight) or 0, viewportHeight)
    child:SetHeight(height)

    if scrollFrame.UpdateScrollChildRect then
        scrollFrame:UpdateScrollChildRect()
    end
    if scrollFrame.SetVerticalScroll then
        local maxScroll = math.max(0, height - viewportHeight)
        if scrollFrame.GetVerticalScrollRange then
            maxScroll = math.max(maxScroll, tonumber(scrollFrame:GetVerticalScrollRange()) or 0)
        end
        scrollFrame:SetVerticalScroll(maxScroll)
    end
end

function Manager:ShowWindowWithSlide(frame, from, key)
    if not frame then return end

    if frame:IsShown() then
        frame:Show()
        return
    end

    if GUI2 and GUI2.SlideIn then
        local handle = GUI2:SlideIn(frame, {
            owner = self,
            key = key or "whisper-manager-slide",
            from = from,
            distance = 26,
            duration = 0.18,
            easing = "outCubic",
        })
        if not handle and not frame:IsShown() then
            frame:Show()
        end
    else
        frame:Show()
    end
end

function Manager:HideWindowWithFade(frame, key)
    if not frame or not frame:IsShown() then
        return
    end

    if GUI2 and GUI2.FadeOut then
        local handle = GUI2:FadeOut(frame, {
            owner = self,
            key = key or "whisper-manager-slide",
            hide = true,
            duration = 0.14,
            easing = "sineOut",
        })
        if handle then
            return
        end
    end

    frame:Hide()
end

function Manager:CancelHoverHide()
    self.hoverHideToken = (tonumber(self.hoverHideToken) or 0) + 1
end

function Manager:IsPreviewMouseInside()
    local listFrame = self.listFrame or self.frame
    local detailFrame = self.detailFrame
    local frames = {
        listFrame and listFrame.listPanel,
        detailFrame,
        detailFrame and detailFrame.messagePanel,
        detailFrame and detailFrame.messageScrollFrame,
        detailFrame and detailFrame.copyPanel,
        detailFrame and detailFrame.copyScrollFrame,
    }

    for _, frame in ipairs(frames) do
        if frame and frame.IsShown and frame:IsShown() and frame.IsMouseOver and frame:IsMouseOver() then
            return true
        end
    end
    return false
end

function Manager:HandlePreviewKeepAliveEnter()
    if not self.selectionLocked then
        self:CancelHoverHide()
    end
end

function Manager:HandlePreviewKeepAliveLeave()
    if not self.selectionLocked then
        self:ScheduleHoverHide()
    end
end

function Manager:WirePreviewKeepAlive(frame)
    if not frame or not frame.HookScript or frame.yuiWhisperPreviewKeepAlive then
        return
    end

    frame.yuiWhisperPreviewKeepAlive = true
    frame:HookScript("OnEnter", function()
        Manager:HandlePreviewKeepAliveEnter()
    end)
    frame:HookScript("OnLeave", function()
        Manager:HandlePreviewKeepAliveLeave()
    end)
end

function Manager:ScheduleHoverHide()
    if self.selectionLocked then
        return
    end

    local token = (tonumber(self.hoverHideToken) or 0) + 1
    self.hoverHideToken = token

    local function hidePreview()
        if Manager.hoverHideToken ~= token or Manager.selectionLocked then
            return
        end
        if Manager:IsPreviewMouseInside() then
            return
        end
        Manager:HideDetailWindow()
    end

    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(HOVER_HIDE_DELAY, hidePreview)
    else
        hidePreview()
    end
end

function Manager:StartWindowDrag()
    local frame = self.listFrame or self.frame
    if frame and frame.StartMoving then
        frame:StartMoving()
    end
end

function Manager:StopWindowDrag()
    local frame = self.listFrame or self.frame
    if not frame then
        return
    end

    if frame.StopMovingOrSizing then
        frame:StopMovingOrSizing()
    end
    SaveWindowPosition(frame, "window")
    self:AnchorDetailFrame()
end

function Manager:WireWindowDrag(frame)
    if not frame or not frame.RegisterForDrag then
        return
    end

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        Manager:StartWindowDrag()
    end)
    frame:SetScript("OnDragStop", function()
        Manager:StopWindowDrag()
    end)
end

function Manager:ClearCurrentSelection()
    self.selectedKey = nil
    self.selectedStore = nil
    self.selectedToken = nil
    self.selectionLocked = false
    self.hoverHideToken = (tonumber(self.hoverHideToken) or 0) + 1
    self.pendingUnreadDividerKey = nil
    self.pendingUnreadDividerToken = nil
    self.pendingUnreadDividerIndex = nil
end

function Manager:HideDetailWindow()
    self:HideCopyEditBox(true)
    self:ClearCurrentSelection()
    self:RefreshList()
    self:HideWindowWithFade(self.detailFrame, "whisper-manager-detail-slide")
end

function Manager:HideListWindow()
    self:ClearCurrentSelection()
    self:RefreshList()
    if self.detailFrame and self.detailFrame:IsShown() then
        self:HideDetailWindow()
    end
    self:HideWindowWithFade(self.listFrame or self.frame, "whisper-manager-list-slide")
end

function Manager:AnchorDetailFrame()
    local detailFrame = self.detailFrame
    if not detailFrame then
        return
    end

    local listFrame = self:CreateListFrame()
    if not listFrame then
        return
    end

    detailFrame:ClearAllPoints()
    detailFrame:SetPoint("TOPLEFT", listFrame, "TOPRIGHT", DETAIL_WINDOW_GAP, 0)
end

function Manager:CreateListFrame()
    if self.listFrame or not GUI2 then
        return self.listFrame
    end

    local db = GetDB()
    local width = (db and db.window and db.window.width) or defaults.window.width
    local height = (db and db.window and db.window.height) or defaults.window.height
    local frame = GUI2:CreateFrame(UIParent, {
        name = "YUI_WhisperManagerListFrame",
        template = "BackdropTemplate",
        width = width,
        height = height,
        surface = "color.surface.panel",
        border = "color.border.default",
        shadow = true,
        mouse = true,
        movable = true,
        clamped = true,
        hidden = true,
        frameStrata = "DIALOG",
    })
    self.listFrame = frame
    self.frame = frame

    self:WireWindowDrag(frame)
    self:RegisterSpecialFrame(frame)
    frame:SetScript("OnShow", function()
        Manager:RefreshList()
        Manager:RefreshDevTools()
    end)
    frame:SetScript("OnHide", function()
        Manager:HideContextMenu()
        if Manager.detailFrame and Manager.detailFrame:IsShown() then
            Manager:HideDetailWindow()
        end
        Manager:ClearCurrentSelection()
        wipe(Manager.unfavoritedVisibleKeys)
    end)

    local title = GUI2:CreateText(frame, T("window.title"), "font.size.lg", "color.text.heading")
    title:SetPoint("TOPLEFT", 16, -14)
    frame.title = title

    local close = CreateManagerCloseButton(frame, function()
        Manager:HideListWindow()
    end)
    close:SetPoint("TOPRIGHT", -14, -14)
    frame.closeButton = close

    local settingsIcon = self:CreateSettingsButton(frame, function()
        Manager:OpenSettings()
    end)
    if settingsIcon then
        settingsIcon:SetPoint("RIGHT", close, "LEFT", -8, 0)
        frame.settingsButton = settingsIcon
    end

    local listPanel = GUI2:CreateFrame(frame, {
        template = "BackdropTemplate",
        width = LIST_PANEL_WIDTH,
        surface = "color.surface.raised",
        border = "color.border.subtle",
        mouse = true,
    })
    listPanel:SetPoint("TOPLEFT", 14, -76)
    listPanel:SetPoint("BOTTOMLEFT", 14, 54)
    listPanel:SetScript("OnMouseWheel", function(_, delta)
        Manager:ScrollList(delta > 0 and -1 or 1)
    end)
    frame.listPanel = listPanel
    self:WirePreviewKeepAlive(listPanel)

    local filterLabel = GUI2:CreateText(frame, T("filter.label"), "font.size.sm", "color.text.secondary")
    filterLabel:SetSize(LIST_FILTER_LABEL_WIDTH, 24)
    filterLabel:SetJustifyH("LEFT")
    filterLabel:SetPoint("BOTTOMLEFT", listPanel, "TOPLEFT", 0, 6)
    frame.listFilterLabel = filterLabel

    local filterDropdown = GUI2.Form:CreateDropdown(frame, {
        width = LIST_FILTER_DROPDOWN_WIDTH,
        height = 24,
        value = self:GetListFilter(),
        options = function()
            return {
                { text = T("filter.all"), value = "all" },
                { text = T("filter.unread"), value = "unread" },
                { text = T("filter.favorites"), value = "favorites" },
            }
        end,
        onChange = function(_, value)
            Manager:SetListFilter(value)
        end,
    })
    filterDropdown:SetPoint("LEFT", filterLabel, "RIGHT", 2, 0)
    frame.listFilterDropdown = filterDropdown

    local unreadSummary = GUI2:CreateText(frame, "", "font.size.sm", "color.text.secondary")
    unreadSummary:SetSize(LIST_UNREAD_SUMMARY_WIDTH, 24)
    unreadSummary:SetJustifyH("RIGHT")
    unreadSummary:SetPoint("BOTTOMRIGHT", listPanel, "TOPRIGHT", 0, 6)
    frame.unreadSummaryText = unreadSummary

    frame.rows = {}
    for i = 1, ROW_COUNT do
        local row = GUI2.Form:CreateButton(listPanel, {
            text = "",
            width = LIST_ROW_WIDTH,
            height = 28,
            tone = "default",
            onClick = function(button, mouseButton)
                Manager:HandleRowClick(button, mouseButton)
            end,
        })
        if row.RegisterForClicks then
            row:RegisterForClicks("AnyUp")
        end
        row:SetPoint("TOPLEFT", 8, -8 - ((i - 1) * 31))
        if row.HookScript then
            row:HookScript("OnEnter", function(button)
                Manager:HandleRowEnter(button)
            end)
            row:HookScript("OnLeave", function(button)
                Manager:HandleRowLeave(button)
            end)
            row:HookScript("OnMouseUp", function(button)
                if Manager.selectionLocked and Manager:IsRowCurrent(button) then
                    Manager:ApplyRowSelectionVisual(button, true)
                end
            end)
        end
        local unreadBg = row:CreateTexture(nil, "BORDER")
        unreadBg:SetPoint("TOPLEFT", 0, 0)
        unreadBg:SetPoint("BOTTOMRIGHT", 0, 0)
        if GUI2.ApplyTexturePixelPolicy then
            GUI2:ApplyTexturePixelPolicy(unreadBg, { snapToPixelGrid = false, texelSnappingBias = 0 })
        end
        SetTextureColor(unreadBg, UNREAD_ROW_BG_COLOR)
        unreadBg:Hide()
        row.unreadBg = unreadBg

        local typeIcon = row:CreateTexture(nil, "ARTWORK")
        typeIcon:SetSize(LIST_ROW_ICON_SIZE, LIST_ROW_ICON_SIZE)
        typeIcon:SetPoint("LEFT", LIST_ROW_ICON_LEFT, 0)
        typeIcon:Hide()
        row.typeIcon = typeIcon

        local nameText = GUI2:CreateText(row, "", "font.size.md", "color.text.primary")
        nameText:SetPoint("LEFT", typeIcon, "RIGHT", LIST_ROW_TEXT_GAP, 0)
        nameText:SetJustifyH("LEFT")
        if nameText.SetWordWrap then
            nameText:SetWordWrap(false)
        end
        if nameText.SetNonSpaceWrap then
            nameText:SetNonSpaceWrap(false)
        end
        if nameText.SetMaxLines then
            nameText:SetMaxLines(1)
        end
        row.nameText = nameText

        local unreadDot = GUI2:CreateText(row, "", "font.size.sm", "color.state.danger")
        unreadDot:SetSize(LIST_ROW_UNREAD_DOT_WIDTH, 18)
        unreadDot:SetJustifyH("CENTER")
        unreadDot:Hide()
        row.unreadDot = unreadDot

        local favoriteIcon = GUI2:CreateText(row, "", "font.size.sm", "color.state.warning")
        favoriteIcon:SetSize(LIST_ROW_FAVORITE_WIDTH, 18)
        favoriteIcon:SetPoint("RIGHT", -LIST_ROW_RIGHT_PADDING, 0)
        favoriteIcon:SetJustifyH("CENTER")
        favoriteIcon:Hide()
        row.favoriteIcon = favoriteIcon

        local unreadText = GUI2:CreateText(row, "", "font.size.sm", "color.state.warning")
        unreadText:SetSize(LIST_ROW_UNREAD_WIDTH, 18)
        unreadText:SetPoint("RIGHT", favoriteIcon, "LEFT", -LIST_ROW_COLUMN_GAP, 0)
        unreadText:SetJustifyH("RIGHT")
        unreadText:Hide()
        row.unreadText = unreadText

        if row.text then
            row.text:ClearAllPoints()
            row.text:SetText("")
            row.text:Hide()
        end
        frame.rows[i] = row
    end

    local prev = GUI2.Form:CreateButton(frame, {
        text = "<",
        width = 32,
        height = 24,
        tone = "default",
        onClick = function()
            Manager:ScrollList(-1)
        end,
    })
    prev:SetPoint("BOTTOMLEFT", listPanel, "BOTTOMLEFT", 0, -32)
    frame.prevButton = prev

    local pageText = GUI2:CreateText(frame, "1/1", "font.size.sm", "color.text.secondary")
    pageText:SetSize(44, 24)
    pageText:SetJustifyH("CENTER")
    pageText:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    frame.pageText = pageText

    local next = GUI2.Form:CreateButton(frame, {
        text = ">",
        width = 32,
        height = 24,
        tone = "default",
        onClick = function()
            Manager:ScrollList(1)
        end,
    })
    next:SetPoint("LEFT", pageText, "RIGHT", 4, 0)
    frame.nextButton = next

    local clearUnread = GUI2.Form:CreateButton(frame, {
        text = T("button.mark_all_read"),
        width = 86,
        height = 24,
        tone = "default",
        onClick = function()
            Manager:ConfirmClearAllNews()
        end,
    })
    clearUnread:SetPoint("LEFT", next, "RIGHT", 8, 0)
    frame.clearUnreadButton = clearUnread

    local clearHistory = GUI2.Form:CreateButton(frame, {
        text = T("button.clear_history"),
        width = 56,
        height = 24,
        tone = "danger",
        onClick = function()
            Manager:ConfirmClearHistory()
        end,
    })
    clearHistory:SetPoint("LEFT", clearUnread, "RIGHT", 6, 0)
    frame.clearHistoryButton = clearHistory

    RestoreWindowPosition(frame, "window", defaults.window)
    return frame
end

function Manager:CreateDetailFrame()
    if self.detailFrame or not GUI2 then
        return self.detailFrame
    end

    local frame = GUI2:CreateFrame(UIParent, {
        name = "YUI_WhisperManagerDetailFrame",
        template = "BackdropTemplate",
        width = DETAIL_WINDOW_WIDTH,
        height = WINDOW_HEIGHT,
        surface = "color.surface.panel",
        border = "color.border.default",
        shadow = true,
        mouse = true,
        clamped = true,
        hidden = true,
        frameStrata = "DIALOG",
    })
    self.detailFrame = frame
    self:WireWindowDrag(frame)
    self:WirePreviewKeepAlive(frame)
    self:RegisterSpecialFrame(frame)

    frame:SetScript("OnShow", function()
        Manager:RefreshMessages()
        Manager:RefreshDevTools()
    end)
    frame:SetScript("OnHide", function()
        Manager:HideContextMenu()
        Manager:HideCopyEditBox(true)
        Manager:ClearCurrentSelection()
        Manager:RefreshList()
    end)

    local close = CreateManagerCloseButton(frame, function()
        Manager:HideDetailWindow()
    end)
    close:SetPoint("TOPRIGHT", -14, -14)
    frame.closeButton = close
    self:WirePreviewKeepAlive(close)

    local messagePanel = GUI2:CreateFrame(frame, {
        template = "BackdropTemplate",
        surface = "color.surface.raised",
        border = "color.border.subtle",
        mouse = true,
    })
    messagePanel:SetPoint("TOPLEFT", 14, -76)
    messagePanel:SetPoint("BOTTOMRIGHT", -14, 54)
    ConfigureHyperlinks(messagePanel)
    frame.messagePanel = messagePanel
    self:WirePreviewKeepAlive(messagePanel)

    local messageHyperlinkHandler = self:CreateMessageHyperlinkHandler(messagePanel) or messagePanel
    frame.messageHyperlinkHandler = messageHyperlinkHandler

    local conversationTitlePrefix = GUI2:CreateText(frame, "", "font.size.md", "color.text.heading")
    conversationTitlePrefix:SetHeight(24)
    conversationTitlePrefix:SetPoint("BOTTOMLEFT", messagePanel, "TOPLEFT", 0, 6)
    conversationTitlePrefix:SetJustifyH("LEFT")
    frame.conversationTitlePrefix = conversationTitlePrefix

    local conversationTitleRaceIcon = GUI2:CreateIconSlot(frame, {
        size = TITLE_ICON_SIZE,
        variant = "bare",
        shape = "square",
        padding = 0,
    })
    conversationTitleRaceIcon:SetPoint("LEFT", conversationTitlePrefix, "RIGHT", TITLE_GAP, 0)
    conversationTitleRaceIcon:Hide()
    frame.conversationTitleRaceIcon = conversationTitleRaceIcon

    local conversationTitleIcon = frame:CreateTexture(nil, "ARTWORK")
    conversationTitleIcon:SetSize(TITLE_ICON_SIZE, TITLE_ICON_SIZE)
    conversationTitleIcon:SetPoint("LEFT", conversationTitleRaceIcon, "RIGHT", TITLE_GAP, 0)
    conversationTitleIcon:Hide()
    frame.conversationTitleIcon = conversationTitleIcon

    local conversationTitleName = GUI2:CreateText(frame, "", "font.size.md", "color.text.heading")
    conversationTitleName:SetHeight(24)
    conversationTitleName:SetPoint("LEFT", conversationTitleIcon, "RIGHT", TITLE_GAP, 0)
    conversationTitleName:SetJustifyH("LEFT")
    if conversationTitleName.SetWordWrap then
        conversationTitleName:SetWordWrap(false)
    end
    if conversationTitleName.SetNonSpaceWrap then
        conversationTitleName:SetNonSpaceWrap(false)
    end
    if conversationTitleName.SetMaxLines then
        conversationTitleName:SetMaxLines(1)
    end
    frame.conversationTitleName = conversationTitleName

    local conversationTitleSuffix = GUI2:CreateText(frame, "", "font.size.md", "color.text.heading")
    conversationTitleSuffix:SetHeight(24)
    conversationTitleSuffix:SetPoint("LEFT", conversationTitleName, "RIGHT", 2, 0)
    conversationTitleSuffix:SetJustifyH("LEFT")
    frame.conversationTitleSuffix = conversationTitleSuffix

    local conversationLevelTag = GUI2:CreateText(frame, "", "font.size.sm", "color.text.secondary")
    conversationLevelTag:SetSize(TITLE_STATUS_WIDTH, 24)
    conversationLevelTag:SetPoint("LEFT", conversationTitleSuffix, "RIGHT", TITLE_GAP, 0)
    conversationLevelTag:SetJustifyH("LEFT")
    conversationLevelTag:Hide()
    frame.conversationLevelTag = conversationLevelTag

    local conversationStatusTag = GUI2:CreateText(frame, "", "font.size.sm", "color.text.secondary")
    conversationStatusTag:SetSize(TITLE_STATUS_WIDTH, 24)
    conversationStatusTag:SetPoint("LEFT", conversationLevelTag, "RIGHT", TITLE_GAP, 0)
    conversationStatusTag:SetJustifyH("LEFT")
    conversationStatusTag:Hide()
    frame.conversationStatusTag = conversationStatusTag

    local conversationTag = GUI2:CreateText(frame, "", "font.size.sm", "color.state.warning")
    conversationTag:SetSize(TITLE_RELATION_WIDTH, 24)
    conversationTag:SetPoint("BOTTOMRIGHT", messagePanel, "TOPRIGHT", 0, 6)
    conversationTag:SetJustifyH("RIGHT")
    frame.conversationTag = conversationTag

    local messageScrollFrame = GUI2:CreateScrollFrame(messagePanel, {
        name = "YUI_WhisperManagerMessageScrollFrame",
        childName = "YUI_WhisperManagerMessageScrollChild",
        mouseWheel = true,
    })
    if GUI2.SkinScrollBar then
        GUI2:SkinScrollBar(messageScrollFrame)
    end
    messageScrollFrame:SetPoint("TOPLEFT", MESSAGE_PANEL_PADDING, -MESSAGE_PANEL_PADDING)
    messageScrollFrame:SetPoint("BOTTOMRIGHT", -MESSAGE_SCROLLBAR_INSET, MESSAGE_PANEL_PADDING)
    messageScrollFrame:EnableMouseWheel(true)
    messageScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self.GetVerticalScroll and self:GetVerticalScroll() or 0
        local maxScroll = self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
        local nextScroll = current - ((tonumber(delta) or 0) * MESSAGE_SCROLL_STEP)
        if nextScroll < 0 then nextScroll = 0 end
        if nextScroll > maxScroll then nextScroll = maxScroll end
        if self.SetVerticalScroll then
            self:SetVerticalScroll(nextScroll)
        end
    end)
    ConfigureHyperlinks(messageScrollFrame)
    frame.messageScrollFrame = messageScrollFrame
    frame.messageFrame = messageScrollFrame
    self:WirePreviewKeepAlive(messageScrollFrame)

    local messageScrollChild = messageScrollFrame.child or messageScrollFrame.scrollChild
    if messageScrollChild then
        messageScrollChild:SetSize(1, 1)
        ConfigureHyperlinks(messageScrollChild)
        self:WirePreviewKeepAlive(messageScrollChild)
    end
    frame.messageScrollChild = messageScrollChild
    frame.messageRows = {}

    local empty = GUI2:CreateText(frame, T("window.empty"), "font.size.md", "color.text.secondary")
    empty:SetPoint("CENTER", messagePanel, "CENTER")
    frame.emptyText = empty

    local copyPanel = GUI2:CreatePanel(messagePanel, {
        surface = "color.control.bg",
        border = "color.border.focus",
    })
    copyPanel:SetPoint("TOPLEFT", MESSAGE_PANEL_PADDING, -MESSAGE_PANEL_PADDING)
    copyPanel:SetPoint("BOTTOMRIGHT", -MESSAGE_PANEL_PADDING, MESSAGE_PANEL_PADDING)
    copyPanel:SetFrameLevel(messagePanel:GetFrameLevel() + 20)
    if copyPanel.SetClipsChildren then
        copyPanel:SetClipsChildren(true)
    end
    copyPanel:Hide()
    frame.copyPanel = copyPanel
    self:WirePreviewKeepAlive(copyPanel)

    local copyScrollFrame = GUI2:CreateScrollFrame(copyPanel, {
        name = "YUI_WhisperManagerCopyScrollFrame",
        child = false,
        mouseWheel = true,
    })
    copyScrollFrame:SetPoint("TOPLEFT", COPY_EDIT_INSET, -COPY_EDIT_INSET)
    copyScrollFrame:SetPoint("BOTTOMRIGHT", -MESSAGE_SCROLLBAR_INSET, COPY_EDIT_INSET)
    copyScrollFrame:SetFrameLevel(copyPanel:GetFrameLevel() + 2)
    copyScrollFrame:EnableMouseWheel(true)
    copyScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self.GetVerticalScroll and (self:GetVerticalScroll() or 0) or 0
        local maxScroll = self.GetVerticalScrollRange and (self:GetVerticalScrollRange() or 0) or 0
        local nextScroll = current - ((tonumber(delta) or 0) * MESSAGE_SCROLL_STEP)
        if nextScroll < 0 then nextScroll = 0 end
        if nextScroll > maxScroll then nextScroll = maxScroll end
        if self.SetVerticalScroll then
            self:SetVerticalScroll(nextScroll)
        end
    end)
    if copyScrollFrame.HookScript then
        copyScrollFrame:HookScript("OnSizeChanged", function()
            Manager:RefreshCopyEditBoxLayout()
        end)
    end
    copyScrollFrame:Hide()
    frame.copyScrollFrame = copyScrollFrame
    self:WirePreviewKeepAlive(copyScrollFrame)

    local copyEditBox = CreateFrame("EditBox", nil, copyScrollFrame)
    copyEditBox:SetMultiLine(true)
    copyEditBox:SetAutoFocus(false)
    copyEditBox:SetFont(GUI2:GetFont("font.family.body"), GUI2:GetMetric("font.size.md", 13), "")
    copyEditBox:SetTextColor(GUI2:GetColor("color.text.primary"))
    copyEditBox:SetTextInsets(0, 0, 0, 0)
    copyEditBox:SetJustifyH("LEFT")
    if copyEditBox.SetJustifyV then
        copyEditBox:SetJustifyV("TOP")
    end
    copyEditBox:SetScript("OnEditFocusLost", function()
        Manager:HideCopyEditBox()
    end)
    copyEditBox:SetScript("OnEscapePressed", function()
        Manager:HideCopyEditBox()
    end)
    copyEditBox:SetScript("OnTextChanged", function()
        Manager:RefreshCopyEditBoxLayout()
    end)
    function copyEditBox:RefreshTheme()
        self:SetTextColor(GUI2:GetColor("color.text.primary"))
    end
    GUI2:RegisterThemeObject(copyEditBox)
    copyEditBox:SetSize(1, 1)
    copyEditBox:Hide()
    copyScrollFrame:SetScrollChild(copyEditBox)
    frame.copyEditBox = copyEditBox
    self:WirePreviewKeepAlive(copyEditBox)

    local protect = GUI2.Form:CreateCheckbox(frame, {
        text = T("window.favorite"),
        width = 100,
        onClick = function(button, checked)
            local data = Manager:GetSelectedConversation()
            if data then
                data.protected = checked and true or nil
                SyncStoredControl(data)
                local token = GetStoreToken(data._store)
                if token and Manager.unfavoritedVisibleKeys then
                    if checked then
                        Manager.unfavoritedVisibleKeys[token] = nil
                    elseif Manager:GetListFilter() == "favorites" then
                        Manager.unfavoritedVisibleKeys[token] = true
                    end
                end
                BroadcastUpdate()
            end
        end,
    })
    protect:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 22)
    frame.protectCheck = protect
    self:WirePreviewKeepAlive(protect)

    local reply = GUI2.Form:CreateButton(frame, {
        text = T("action.reply"),
        width = ACTION_BUTTON_WIDTH,
        height = 28,
        onClick = function()
            Manager:ReplySelected()
        end,
    })
    frame.replyButton = reply
    self:WirePreviewKeepAlive(reply)

    local invite = GUI2.Form:CreateButton(frame, {
        text = T("action.invite"),
        width = ACTION_BUTTON_WIDTH,
        height = 28,
        tone = "default",
        onClick = function()
            Manager:InviteSelected()
        end,
    })
    frame.inviteButton = invite
    self:WirePreviewKeepAlive(invite)

    local who = GUI2.Form:CreateButton(frame, {
        text = T("action.who"),
        width = ACTION_BUTTON_WIDTH,
        height = 28,
        tone = "default",
        onClick = function()
            Manager:WhoSelected()
        end,
    })
    frame.whoButton = who
    self:WirePreviewKeepAlive(who)

    local copyName = GUI2.Form:CreateButton(frame, {
        text = T("action.copy_name"),
        width = ACTION_BUTTON_WIDTH,
        height = 28,
        tone = "default",
        onClick = function()
            Manager:CopySelectedName()
        end,
    })
    frame.copyNameButton = copyName
    self:WirePreviewKeepAlive(copyName)

    local exportLog = GUI2.Form:CreateButton(frame, {
        text = T("action.export_log"),
        width = ACTION_BUTTON_WIDTH,
        height = 28,
        tone = "default",
        onClick = function()
            Manager:ExportSelectedLog()
        end,
    })
    frame.exportLogButton = exportLog
    self:WirePreviewKeepAlive(exportLog)

    local delete = GUI2.Form:CreateButton(frame, {
        text = T("action.delete"),
        width = ACTION_BUTTON_WIDTH,
        height = 28,
        tone = "default",
        onClick = function()
            Manager:Delete()
        end,
    })
    delete:SetPoint("BOTTOMRIGHT", messagePanel, "BOTTOMRIGHT", 0, -32)
    exportLog:SetPoint("RIGHT", delete, "LEFT", -ACTION_BUTTON_GAP, 0)
    copyName:SetPoint("RIGHT", exportLog, "LEFT", -ACTION_BUTTON_GAP, 0)
    who:SetPoint("RIGHT", copyName, "LEFT", -ACTION_BUTTON_GAP, 0)
    invite:SetPoint("RIGHT", who, "LEFT", -ACTION_BUTTON_GAP, 0)
    reply:SetPoint("RIGHT", invite, "LEFT", -ACTION_BUTTON_GAP, 0)
    frame.deleteButton = delete
    self:WirePreviewKeepAlive(delete)

    local devNew = GUI2.Form:CreateButton(frame, {
        text = T("dev.new_player"),
        width = 150,
        height = 24,
        tone = "warning",
        onClick = function()
            Manager:AddTestNewConversation()
        end,
    })
    devNew:SetFrameLevel(frame:GetFrameLevel() + 20)
    devNew:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 28, 6)
    frame.devNewButton = devNew

    local devCurrent = GUI2.Form:CreateButton(frame, {
        text = T("dev.current_player"),
        width = 178,
        height = 24,
        tone = "warning",
        onClick = function()
            Manager:AddTestMessageToSelected()
        end,
    })
    devCurrent:SetFrameLevel(frame:GetFrameLevel() + 20)
    devCurrent:SetPoint("LEFT", devNew, "RIGHT", 10, 0)
    frame.devCurrentButton = devCurrent

    self:AnchorDetailFrame()
    self:RefreshDevTools()
    return frame
end

function Manager:CreateFrame()
    return self:CreateListFrame()
end

function Manager:ShowListWindow()
    local frame = self:CreateListFrame()
    if not frame then return end
    if not frame:IsShown() then
        self:ClearCurrentSelection()
    end
    self:ShowWindowWithSlide(frame, "bottom", "whisper-manager-list-slide")
end

function Manager:ShowDetailWindow()
    local frame = self:CreateDetailFrame()
    if not frame then return end
    self:AnchorDetailFrame()
    self:ShowWindowWithSlide(frame, "left", "whisper-manager-detail-slide")
end

function Manager:RefreshList()
    local frame = self.listFrame or self.frame
    local db, _, _, offset, _, visibleHistory = self:GetListPageInfo()
    if not frame or not db then return end

    if self.selectedKey and not FindConversation(db, self.selectedKey) then
        self:ClearCurrentSelection()
    end
    if self.selectedKey or self.selectedStore then
        local selectedVisible = false
        for _, stored in ipairs(visibleHistory) do
            if stored == self.selectedStore or GetStoreToken(stored) == self.selectedToken then
                selectedVisible = true
                break
            end
        end
        if not selectedVisible then
            self:ClearCurrentSelection()
        end
    end

    for i, row in ipairs(frame.rows) do
        local stored = visibleHistory[offset + i - 1]
        local data = stored and EnsureRuntimeHeader(stored)
        if data then
            local unreadCount = GetUnreadCount(stored)
            row.key = data.key
            row.store = stored
            row:Show()
            self:ApplyRowSelectionVisual(row, stored == self.selectedStore or data.key == self.selectedKey)
            self:SetRowName(row, data, unreadCount)
        else
            row.key = nil
            row.store = nil
            row:SetText("")
            self:ApplyRowSelectionVisual(row, false)
            if row.nameText then
                row.nameText:SetText("")
                row.nameText:Hide()
            end
            if row.typeIcon then
                row.typeIcon:SetTexture(nil)
                row.typeIcon:Hide()
            end
            self:SetRowUnreadVisual(row, false)
            if row.unreadText then
                row.unreadText:SetText("")
                row.unreadText:Hide()
            end
            if row.favoriteIcon then
                row.favoriteIcon:SetText("")
                row.favoriteIcon:Hide()
            end
            row:Hide()
        end
    end

    self:RefreshListPager()
end

function Manager:RefreshMessages()
    local frame = self.detailFrame
    local db = GetDB()
    if not frame or not db then return end
    self:HideCopyEditBox(true)

    local _, data = FindConversation(db, self.selectedKey)
    local scrollFrame = frame.messageScrollFrame
    local scrollChild = frame.messageScrollChild
    if not scrollFrame or not scrollChild then return end

    local rows = frame.messageRows or {}
    for _, row in ipairs(rows) do
        row:Hide()
    end
    local dividers = frame.messageDividers or {}
    for _, divider in ipairs(dividers) do
        divider:Hide()
    end

    if not data then
        frame.emptyText:SetText(#(db.history or {}) == 0 and T("window.empty") or T("window.select"))
        frame.emptyText:Show()
        self:RefreshConversationTitle(nil)
        if frame.conversationTag then
            frame.conversationTag:Hide()
        end
        if frame.conversationLevelTag then
            frame.conversationLevelTag:Hide()
        end
        if frame.conversationStatusTag then
            frame.conversationStatusTag:Hide()
        end
        frame.protectCheck:SetChecked(false, true)
        frame.replyButton:SetDisabled(true)
        frame.whoButton:SetDisabled(true)
        frame.inviteButton:SetDisabled(true)
        frame.copyNameButton:SetDisabled(true)
        frame.exportLogButton:SetDisabled(true)
        frame.deleteButton:SetDisabled(true)
        self:RefreshMessageScrollRange(1)
        return
    end

    self.selectedStore = data._store
    self.selectedToken = GetStoreToken(data._store)
    local messages = EnsureRuntimeMessages(data) or {}

    self:RefreshConversationTitle(data)
    if frame.conversationTag then
        local isSelf = self:IsSelfConversation(data)
        local isFriend = not isSelf and self:IsFriendConversation(data)
        if isSelf then
            frame.conversationTag:SetText(T("conversation.self_tag"))
            SetFontStringColor(frame.conversationTag, SELF_TAG_COLOR)
        elseif isFriend then
            frame.conversationTag:SetText(T("conversation.friend_tag"))
            SetFontStringColor(frame.conversationTag, FRIEND_TAG_COLOR)
        else
            frame.conversationTag:SetText(T("conversation.stranger_tag"))
            SetFontStringColor(frame.conversationTag, STRANGER_TAG_COLOR)
        end
        frame.conversationTag:Show()
    end
    frame.protectCheck:SetChecked(data.protected, true)
    frame.replyButton:SetDisabled(false)
    local playerActionsDisabled = data.kind ~= "player"
    frame.whoButton:SetDisabled(playerActionsDisabled)
    frame.inviteButton:SetDisabled(not self:CanInviteConversation(data))
    frame.copyNameButton:SetDisabled(false)
    frame.exportLogButton:SetDisabled(false)
    frame.deleteButton:SetDisabled(data.protected)

    local contentWidth = scrollFrame.GetWidth and (scrollFrame:GetWidth() or 0) or 0
    if contentWidth <= 1 and frame.messagePanel and frame.messagePanel.GetWidth then
        contentWidth = (frame.messagePanel:GetWidth() or 0) - (MESSAGE_PANEL_PADDING * 2) - MESSAGE_SCROLLBAR_INSET
    end
    contentWidth = math.max(1, math.floor(contentWidth))
    scrollChild:SetWidth(contentWidth)

    local dividerMessageIndex
    if self.pendingUnreadDividerKey == data.key or self.pendingUnreadDividerToken == self.selectedToken then
        dividerMessageIndex = tonumber(self.pendingUnreadDividerIndex)
    elseif data.new then
        dividerMessageIndex = tonumber(data.firstUnreadIndex)
    end

    local items = {}
    local dividerAdded = false
    for messageIndex, message in ipairs(messages) do
        if not (db.receiveOnly and message.inform) then
            if dividerMessageIndex and not dividerAdded and messageIndex >= dividerMessageIndex then
                tinsert(items, { kind = "divider" })
                dividerAdded = true
            end
            tinsert(items, { kind = "message", message = message })
        end
    end

    if #items == 0 then
        frame.emptyText:SetText(T("window.empty"))
        frame.emptyText:Show()
    else
        frame.emptyText:Hide()
    end

    local rowIndex = 0
    local dividerIndex = 0
    local totalHeight = 0
    for index, item in ipairs(items) do
        if item.kind == "divider" then
            dividerIndex = dividerIndex + 1
            item.frame = self:AcquireMessageDivider(dividerIndex)
            item.height = self:LayoutMessageDivider(item.frame, 0, contentWidth)
        else
            rowIndex = rowIndex + 1
            item.frame = self:AcquireMessageRow(rowIndex)
            item.height = self:LayoutMessageRow(item.frame, item.message, 0, contentWidth)
        end

        totalHeight = totalHeight + (item.height or MESSAGE_MIN_ROW_HEIGHT)
        if index < #items then
            totalHeight = totalHeight + MESSAGE_ROW_SPACING
        end
    end

    for index = rowIndex + 1, #rows do
        rows[index]:Hide()
    end
    for index = dividerIndex + 1, #dividers do
        dividers[index]:Hide()
    end

    local viewportHeight = scrollFrame.GetHeight and (scrollFrame:GetHeight() or 0) or 0
    if viewportHeight <= 1 and frame.messagePanel and frame.messagePanel.GetHeight then
        viewportHeight = (frame.messagePanel:GetHeight() or 0) - (MESSAGE_PANEL_PADDING * 2)
    end

    local topOffset = 0
    if totalHeight > 0 and viewportHeight > totalHeight then
        topOffset = viewportHeight - totalHeight
    end

    local yOffset = topOffset
    for _, item in ipairs(items) do
        if item.kind == "divider" then
            item.height = self:LayoutMessageDivider(item.frame, yOffset, contentWidth)
        else
            item.height = self:LayoutMessageRow(item.frame, item.message, yOffset, contentWidth)
        end
        yOffset = yOffset + (item.height or MESSAGE_MIN_ROW_HEIGHT) + MESSAGE_ROW_SPACING
    end

    local contentHeight = #items > 0 and math.max(1, yOffset - MESSAGE_ROW_SPACING) or 1
    self:RefreshMessageScrollRange(contentHeight)

end

function Manager:RefreshFrame()
    self:RefreshList()
    self:RefreshMessages()
    self:RefreshDevTools()
end

function Manager:ToggleFrame()
    if not self:IsEnabled() then
        return
    end

    local frame = self:CreateListFrame()
    if not frame then return end

    if frame:IsShown() then
        self:HideListWindow()
    else
        self:ShowListWindow()
    end
end

function Manager:ReplySelected()
    local data = self:GetSelectedConversation()
    if not data then return end

    if data.kind == "bn" then
        local ignoredID, accountName
        if ResolveBNRuntimeInfo then
            ignoredID, accountName = ResolveBNRuntimeInfo(data)
        end
        local target = accountName
        if not target and not (IsBattleTag(data.battleTag) or IsBattleTag(data.name)) then
            target = data.bnAccountName or data.displayName or data.name
        end
        if Social.SendBNetTell and target then
            Social.SendBNetTell(target)
        end
        return
    end

    if Social.SendTell then
        Social.SendTell(data.name)
    end
end

function Manager:WhoSelected()
    local data = self:GetSelectedConversation()
    if data and data.kind == "player" and Social.SendWhoExact then
        local name = GetConversationLookupName(data)
        local key = NormalizeLookupName(name)
        local queryName = GetWhoQueryName(name)
        local queryKey = NormalizeShortLookupName(queryName)
        if not key or not queryName or not queryKey then
            return
        end

        local pending = RegisterPendingWho({
            key = key,
            name = name,
            queryName = queryName,
            queryKey = queryKey,
            conversationKey = data.key,
            manual = true,
            expiresAt = time() + WHO_PENDING_TTL,
        })
        local ok = pending and Social.SendWhoExact(queryName, { manual = true, origin = "chat", showUi = false })
        if not ok then
            ClearPendingWho(pending)
        end
    end
end

function Manager:InviteSelected()
    local data = self:GetSelectedConversation()
    if not data then return end

    if not self:CanInviteConversation(data) then
        return
    end

    if data.kind == "player" and Social.InviteUnit then
        Social.InviteUnit(data.name)
    elseif data.kind == "bn" then
        local bnetID, ignoredName, ignoredTag, ignoredOnline, friendIndex
        if ResolveBNRuntimeInfo then
            bnetID, ignoredName, ignoredTag, ignoredOnline, friendIndex = ResolveBNRuntimeInfo(data)
        end
        if Social.InviteBNet then
            Social.InviteBNet(friendIndex, bnetID)
        end
    end
end

function Manager:CopySelectedName()
    local data = self:GetSelectedConversation()
    if not data then return end

    self:ShowCopyEditBox(self:GetConversationFullName(data))
end

function Manager:ExportSelectedLog()
    local data = self:GetSelectedConversation()
    if not data then return end

    self:ShowCopyEditBox(self:BuildExportText(data))
end

function Manager:AttachEvents()
    if self.eventsAttached or not Event then
        return
    end

    Event:On("CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER", self, { moduleId = "component:" .. FEATURE_KEY })
    Event:On("CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_WHISPER_INFORM", self, { moduleId = "component:" .. FEATURE_KEY })
    Event:On("CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER", self, { moduleId = "component:" .. FEATURE_KEY })
    Event:On("CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER_INFORM", self, { moduleId = "component:" .. FEATURE_KEY })
    Event:On("PLAYER_LOGOUT", "PLAYER_LOGOUT", self, { moduleId = "component:" .. FEATURE_KEY })
    Event:On("WHO_LIST_UPDATE", "WHO_LIST_UPDATE", self, { moduleId = "component:" .. FEATURE_KEY })
    Event:On("FRIENDLIST_UPDATE", function()
        BroadcastUpdate()
    end, self, { moduleId = "component:" .. FEATURE_KEY, throttle = 0.5 })
    Event:On("BN_FRIEND_ACCOUNT_ONLINE", function()
        BroadcastUpdate()
    end, self, { moduleId = "component:" .. FEATURE_KEY, throttle = 0.5 })
    Event:On("BN_FRIEND_ACCOUNT_OFFLINE", function()
        BroadcastUpdate()
    end, self, { moduleId = "component:" .. FEATURE_KEY, throttle = 0.5 })
    Event:On("BN_FRIEND_INFO_CHANGED", function()
        BroadcastUpdate()
    end, self, { moduleId = "component:" .. FEATURE_KEY, throttle = 0.5 })
    self.eventsAttached = true
end

function Manager:DetachEvents()
    self:StopDeferredWhispers(true)
    if Event and Event.OffOwner then
        Event:OffOwner(self)
    end
    wipe(self.whoQueue)
    wipe(self.whoQueued)
    wipe(self.pendingWhoLookup)
    wipe(self.pendingWhoNames)
    wipe(self.pendingWhoQueryLookup)
    self.whoQueueTimer = nil
    self.eventsAttached = false
end

-- Sound observes arrival only; history recovery must never replay notifications.
local soundAttached = false
local function OnIncomingSound(eventName, ...)
    local db = GetDB()
    if not Manager.featureEnabled or not db or not db.sound then return end
    local hide = select(16, ...)
    if IsSecretValue(hide) or hide then return end
    local restricted = HasAnySecretValue(...)
    -- Readable history messages already notify after the existing filter/store path.
    if not restricted and Manager.enabled then return end
    -- Do not pass restricted payloads to Lua filters. Arrival itself is public.
    if not restricted and ShouldFilterIncoming(eventName, ...) then return end
    PlayNotification(db)
end

function Manager:RefreshSoundRuntime()
    CancelNotifications()
    local db = GetDB()
    local active = self.featureEnabled == true and db and db.sound == true
    active = active == true
    if active == soundAttached or not Event then return end
    soundAttached = active
    if active then
        Event:On("CHAT_MSG_WHISPER", OnIncomingSound, soundOwner, { moduleId = "component:" .. FEATURE_KEY })
        Event:On("CHAT_MSG_BN_WHISPER", OnIncomingSound, soundOwner, { moduleId = "component:" .. FEATURE_KEY })
    else
        Event:OffOwner(soundOwner)
    end
end

function Manager:RefreshHistoryRuntime()
    self:RefreshSoundRuntime()
    local db = GetDB()
    local enabled = self.featureEnabled == true and db and db.historyEnabled == true
    enabled = enabled == true
    if self.enabled == enabled then
        if enabled then
            self:AttachEvents()
        end
        BroadcastUpdate()
        return
    end

    self.enabled = enabled
    if enabled then
        self:AttachEvents()
        BroadcastUpdate()
    else
        self:DetachEvents()
        if YUI.Animation and YUI.Animation.StopOwner then
            YUI.Animation:StopOwner(self)
        end
        if self.listFrame then
            self.listFrame:Hide()
        end
        if self.detailFrame then
            self.detailFrame:Hide()
        end
        BroadcastUpdate()
    end
end

local profileCallbacksRegistered = false
local function RegisterProfileCallbacks()
    if profileCallbacksRegistered or not (YUI.DB and YUI.DB.GetAceDB) then return end
    local db = YUI.DB:GetAceDB(PRODUCT_ID)
    if not (db and type(db.RegisterCallback) == "function") then return end
    for _, event in ipairs({ "OnProfileChanged", "OnProfileCopied", "OnProfileReset" }) do
        db.RegisterCallback(Manager, event, "OnProfileChanged")
    end
    profileCallbacksRegistered = true
end

function Manager:OnProfileChanged()
    self.featureEnabled = Components.IsEnabled and Components:IsEnabled(FEATURE_KEY) or false
    self:RefreshHistoryRuntime()
end

local function ToggleFeature(enabled)
    RegisterProfileCallbacks()
    Manager.featureEnabled = enabled == true
    Manager:RefreshHistoryRuntime()
end

local function GetOptions(feature)
    feature = feature or (Components.features and Components.features[FEATURE_KEY])
    local db = GetDB()
    local foreignField
    local groups = {
        { label = T("settings.group_history"), fields = {
            {
                type = "checkbox", label = T("settings.history_enabled"),
                get = function() return db.historyEnabled == true end,
                set = function(value)
                    db.historyEnabled = value == true
                    Manager:RefreshHistoryRuntime()
                end,
            },
            {
                type = "checkbox", label = T("settings.apply_filters"),
                tooltip = T("settings.apply_filters_tooltip"),
                get = function() return db.applyFilters end,
                set = function(value) db.applyFilters = value == true end,
            },
            {
                type = "checkbox", label = T("settings.save"),
                get = function() return db.saveMessages end,
                set = function(value) db.saveMessages = value == true end,
            },
        } },
        { label = T("settings.group_sound"), fields = {
            {
                type = "checkbox", label = T("settings.sound"), span = "full",
                tooltip = T("settings.sound_tooltip"),
                get = function() return db.sound end,
                set = function(value)
                    db.sound = value == true
                    Manager:RefreshSoundRuntime()
                end,
            },
            {
                type = "notificationSound", label = T("settings.sound_selection"), span = "full",
                nativeSound = soundOptions.nativeSound, defaultChannel = soundOptions.defaultChannel,
                height = 32,
                get = function() return db.soundSelection end,
                set = function(value)
                    local selection = YUI.NotificationSound:NormalizeSelection(value)
                    if selection then
                        CancelNotifications()
                        db.soundSelection = selection
                    end
                end,
            },
        } },
        { label = T("settings.group_display"), fields = {
            {
                type = "checkbox", label = T("settings.receive_only"),
                get = function() return db.receiveOnly end,
                set = function(value) db.receiveOnly = value == true; Manager:RefreshFrame() end,
            },
            {
                type = "checkbox", label = T("settings.timestamp"),
                get = function() return db.timestamp end,
                set = function(value) db.timestamp = value == true; Manager:RefreshFrame() end,
            },
            {
                type = "checkbox", label = T("settings.show_realm"),
                get = function() return db.showRealm end,
                set = function(value)
                    db.showRealm = value == true
                    BroadcastUpdate()
                    foreignField.disabled = db.showRealm ~= true
                    if foreignField.widget then foreignField.widget:SetDisabled(foreignField.disabled) end
                    if foreignField.labelRegion then
                        YUI.GUI2:SetTextColorKey(foreignField.labelRegion,
                            foreignField.disabled and "color.text.disabled" or "color.text.primary")
                    end
                end,
            },
            {
                type = "checkbox", label = T("settings.foreign_only"),
                disabled = db.showRealm ~= true,
                get = function() return db.foreignOnly end,
                set = function(value) db.foreignOnly = value == true; BroadcastUpdate() end,
            },
        } },
    }
    foreignField = groups[3].fields[4]
    if YUI.WhisperGradient and YUI.WhisperGradient.BuildSettingsFields then
        groups[#groups + 1] = {
            label = T("settings.gradient_enabled"),
            fields = YUI.WhisperGradient:BuildSettingsFields(feature),
        }
    end
    local fields = {}
    for _, group in ipairs(groups) do
        for _, field in ipairs(group.fields) do fields[#fields + 1] = field end
    end
    return { {
        type = "custom", retainedFields = fields,
        render = function(parent, x, y, width)
            local GUI2, Settings = YUI.GUI2, YUI.Settings
            local page = GUI2:CreateFrame(parent, { width = width, height = 1 })
            page:SetPoint("TOPLEFT", x, y)
            local rendered, building = {}, true
            local function Layout()
                local cursor = 0
                for index, group in ipairs(rendered) do
                    group.divider:ClearAllPoints()
                    group.divider:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -cursor)
                    group.form:ClearAllPoints()
                    group.form:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -cursor - 28)
                    cursor = cursor + 28 + group.form:GetHeight() + (index < #rendered and 24 or 0)
                end
                page:SetHeight(math.max(1, cursor))
                if not building then
                    -- RenderConfig adds its trailing row gap and bottom inset.
                    local contentHeight = math.abs(y) + page:GetHeight() + 35
                    parent:SetHeight(contentHeight)
                    if parent.yuiConfigAfterRender then parent.yuiConfigAfterRender(parent, contentHeight) end
                    if parent:IsVisible() and Settings.RefreshCurrentModuleScroll then
                        Settings:RefreshCurrentModuleScroll(false)
                    end
                end
            end
            for _, group in ipairs(groups) do
                local divider = GUI2:CreateDivider(page, {
                    label = group.label, width = width, height = 20, alignLeft = true,
                })
                local form = Settings:RenderAlignedFields(page, {
                    fields = group.fields, width = width, columns = 2, labelPosition = "top",
                    columnGap = 24, rowGap = 10, rowHeight = 32,
                })
                rendered[#rendered + 1] = { divider = divider, form = form }
                form:HookScript("OnSizeChanged", function() if not building then Layout() end end)
            end
            Layout()
            building = false
            return width, page:GetHeight()
        end,
    } }
end

Components:RegisterFeature(FEATURE_KEY, {
    name = T("name"),
    description = T("description"),
    product = PRODUCT_ID,
    default = true,
    settingsMode = "inline",
    callback = ToggleFeature,
    GetOptions = GetOptions,
    GetSettingsTitleAction = function()
        return { actions = {
            { getText = function() return T("button.open") end, height = 32,
                onClick = function() Manager:ToggleFrame() end },
            { getText = function() return T("button.mark_all_read") end, height = 32, tone = "default",
                onClick = function() Manager:ConfirmClearAllNews() end },
            { getText = function() return T("confirm.clear_history.title") end, height = 32, tone = "danger",
                onClick = function() Manager:ConfirmClearHistory() end },
        } }
    end,
})

RegisterProfileCallbacks()
if not profileCallbacksRegistered and Event and Event.Once then
    Event:Once("YUI_DB_READY", RegisterProfileCallbacks, Manager, { moduleId = "component:" .. FEATURE_KEY })
end

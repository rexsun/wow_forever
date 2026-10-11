local YUI = _G.YUI
local YChat = YUI and YUI.YChat
if not YChat or (YUI.IsForever or YUI.IsRetail) ~= true then return end

local Adapter = YChat.Adapter
local ItemLinks = { enabled = false, cacheCount = 0, cacheHits = 0, queries = 0, failures = 0 }
YChat.ItemLinks = ItemLinks
local type, pairs, pcall = type, pairs, pcall
local find, match, gsub, format, sub = string.find, string.match, string.gsub, string.format, string.sub
local floor, tonumber = math.floor, tonumber
local CACHE_LIMIT, PENDING_LIMIT = 256, 64
local cache, keys, pending, installed = {}, {}, {}, {}
local cursor, pendingCount = 1, 0
local activeText
local cropIcons = true
local EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_LOOT", "CHAT_MSG_TRADESKILLS",
}
local ARMOR_SLOTS = {
    INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true,
    INVTYPE_ROBE = true, INVTYPE_WRIST = true, INVTYPE_HAND = true,
    INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true,
}
local locale = _G.GetLocale and _G.GetLocale() or "enUS"
local L = YUI.Locale and YUI.Locale:Get("YChat") or {}
local SHORT_SLOTS = {
    INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true,
    INVTYPE_WRIST = true, INVTYPE_HAND = true, INVTYPE_WAIST = true,
    INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_CLOAK = true,
    INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true,
    INVTYPE_HOLDABLE = true, INVTYPE_SHIELD = true, INVTYPE_WEAPONOFFHAND = true,
}
local separator = (locale == "zhCN" or locale == "zhTW") and "" or " "
local levelPattern = _G.ITEM_LEVEL and ("^" .. gsub(_G.ITEM_LEVEL, "%%d", "(%%d+)"))
local altPattern = _G.ITEM_LEVEL_ALT and ("^" .. gsub(gsub(gsub(
    _G.ITEM_LEVEL_ALT, "%(", "%%("), "%)", "%%)"), "%%d", "(%%d+)"))

local function Safe(value)
    return Adapter:IsExplicitlySafeValue(value) == true
end

local function Text(value)
    return Safe(value) and type(value) == "string" and value ~= ""
end

local function Icon(texture, crop)
    if not Safe(texture) or (type(texture) ~= "number" and type(texture) ~= "string") then return "" end
    -- Height zero follows the font; normalized 8% inset matches GUI2 CreateIcon.
    if crop and cropIcons then return format("|T%s:0:0:0:1:100:100:8:92:8:92|t", texture) end
    return format("|T%s:0:0:0:1|t", texture)
end

local function ParseLevel(text)
    if not Text(text) then return nil end
    local first, second
    if altPattern then first, second = match(text, altPattern) end
    local value = tonumber(second or first or (levelPattern and match(text, levelPattern)))
    if value and value >= 0 then return floor(value) end
end

local function ClearCache()
    for key in pairs(cache) do cache[key] = nil end
    for index in pairs(keys) do keys[index] = nil end
    cursor, ItemLinks.cacheCount = 1, 0
end

function ItemLinks:OnItemData(_, itemID)
    if not Safe(itemID) or not pending[itemID] then return end
    pending[itemID] = nil
    pendingCount = pendingCount - 1
    for _, entry in pairs(cache) do
        if entry.itemID == itemID then entry.expires = 0 end
    end
end

local function RequestData(itemID, now)
    local api = _G.C_Item
    if not itemID or not api or not api.RequestLoadItemDataByID then return end
    for id, expires in pairs(pending) do
        if expires <= now then pending[id] = nil; pendingCount = pendingCount - 1 end
    end
    if pending[itemID] or pendingCount >= PENDING_LIMIT then return end
    pending[itemID] = now + 5
    pendingCount = pendingCount + 1
    if not pcall(api.RequestLoadItemDataByID, itemID) then
        pending[itemID] = nil
        pendingCount = pendingCount - 1
    end
end

local function ReadItem(payload, now)
    local api = _G.C_Item
    local itemID, _, subType, equipLoc, texture, classID = api.GetItemInfoInstant(payload)
    if not Safe(itemID) then return nil end
    local entry = { itemID = itemID, icon = Icon(texture, true), expires = now + 1 }
    if Safe(classID) and Text(equipLoc) then
        if classID == 2 then
            if Text(subType) then entry.slot = subType end
        elseif classID == 4 then
            local slotID = equipLoc == "INVTYPE_ROBE" and "INVTYPE_CHEST" or equipLoc
            local slot = _G[slotID]
            if (locale == "zhCN" or locale == "zhTW") and SHORT_SLOTS[slotID] then
                local short = L["item_links.slot." .. slotID]
                if Text(short) and short ~= "item_links.slot." .. slotID then slot = short end
            end
            if Text(slot) then
                entry.slot = ARMOR_SLOTS[equipLoc] and Text(subType)
                    and (subType .. separator .. slot) or slot
            end
        end
    end
    local equipment = Safe(classID) and (classID == 2 or classID == 4)
    local data = equipment and _G.C_TooltipInfo.GetHyperlink(payload, nil, nil, true) or nil
    local ready = itemID ~= nil
    if equipment then
        local displayedLevel
        ready = Safe(data) and type(data) == "table" and Safe(data.lines) and type(data.lines) == "table"
        if ready then
            local first = data.lines[1]
            ready = Safe(first) and type(first) == "table" and Text(first.leftText)
                and first.leftText ~= _G.RETRIEVING_ITEM_INFO
            local sockets, socketCount = "", 0
            for index = 1, math.min(#data.lines, 128) do
                local line = data.lines[index]
                if Safe(line) and type(line) == "table" then
                    displayedLevel = displayedLevel or ParseLevel(line.leftText) or ParseLevel(line.rightText)
                    local gem = Safe(line.gemIcon) and line.gemIcon
                    if gem and socketCount < 8 then
                        sockets = sockets .. Icon(gem, true)
                        socketCount = socketCount + 1
                    elseif socketCount < 8 and Text(line.socketType) and match(line.socketType, "^[%w_]+$") then
                        sockets = sockets .. Icon("Interface\\ItemSocketingFrame\\UI-EmptySocket-" .. line.socketType, false)
                        socketCount = socketCount + 1
                    end
                end
            end
            entry.sockets = sockets
        end
        -- Forever tooltips may omit item level. Only query on a cache miss/expiry.
        if YUI.IsForever and displayedLevel == nil and type(api.GetDetailedItemLevelInfo) == "function" then
            local ok, value = pcall(api.GetDetailedItemLevelInfo, payload)
            if ok and Safe(value) and type(value) == "number" and value > 0 and value < math.huge then
                displayedLevel = floor(value)
            end
        end
        entry.level = displayedLevel and displayedLevel > (YUI.IsForever and 0 or 1) and displayedLevel or nil
        ready = ready and displayedLevel ~= nil
    end
    if ready then entry.expires = now + 60 else RequestData(itemID or tonumber(match(payload, "^item:(%d+)")), now) end
    return entry
end

local function ReplaceLink(position, link, payload, label)
    local now = _G.GetTime()
    local entry = cache[payload]
    -- Already formatted by this module: do not duplicate the surrounding textures.
    if entry and label == entry.renderedLabel and (
        (entry.icon and entry.icon ~= "" and sub(activeText, position - #entry.icon, position - 1) == entry.icon)
        or (entry.renderedLabel ~= entry.originalLabel)
    ) then return link end
    if not entry or entry.expires <= now then
        ItemLinks.queries = ItemLinks.queries + 1
        local ok, result = pcall(ReadItem, payload, now)
        if not ok or not result then
            ItemLinks.failures = ItemLinks.failures + 1
            result = { expires = now + 1 }
        end
        if not entry then
            local old = keys[cursor]
            if old then cache[old] = nil else ItemLinks.cacheCount = ItemLinks.cacheCount + 1 end
            keys[cursor] = payload
            cursor = cursor % CACHE_LIMIT + 1
        end
        entry = result
        cache[payload] = entry
    else
        ItemLinks.cacheHits = ItemLinks.cacheHits + 1
    end
    if entry.originalLabel == label and entry.renderedLink then return entry.renderedLink end
    local rendered = (entry.slot and (entry.slot .. ":") or "") .. label
        .. (entry.level and ("(" .. entry.level .. ")") or "")
    entry.originalLabel, entry.renderedLabel = label, rendered
    entry.renderedLink = (entry.icon or "") .. "|H" .. payload .. "|h[" .. rendered .. "]|h" .. (entry.sockets or "")
    return entry.renderedLink
end

function ItemLinks:Transform(text)
    if not self.enabled or not Safe(text) or type(text) ~= "string" then return text end
    if not find(text, "|Hitem:", 1, true) then return text end
    local previous = activeText
    activeText = text
    local ok, result = pcall(gsub, text, "()(|H(item:%d+:[^|]-)|h%[(.-)%]|h)", ReplaceLink)
    activeText = previous
    if ok then return result end
    self.failures = self.failures + 1
    return text
end

local function Filter(_, event, text, ...)
    return false, ItemLinks:Transform(text), ...
end

function ItemLinks:SetEnabled(runtimeEnabled)
    local db = YChat:GetDB()
    local newCropIcons = not db.itemLinks or db.itemLinks.cropIcons ~= false
    if cropIcons ~= newCropIcons then
        cropIcons = newCropIcons
        ClearCache()
    end
    local shouldEnable = runtimeEnabled == true and db.itemLinks and db.itemLinks.enabled == true
    self.enabled = false
    local util = _G.ChatFrameUtil
    -- Reappend after SafeMessage on a configuration refresh so history always captures raw text.
    for event in pairs(installed) do
        if not util or not util.RemoveMessageEventFilter or not pcall(util.RemoveMessageEventFilter, event, Filter) then
            return false, "item-links-filter-remove-failed"
        end
        installed[event] = nil
    end
    self.filterInstalled = false
    if YUI.Event then YUI.Event:OffOwner(self) end
    for id in pairs(pending) do pending[id] = nil end
    pendingCount = 0
    if not shouldEnable then ClearCache(); return true end
    if not util or not util.AddMessageEventFilter or not util.RemoveMessageEventFilter
        or not _G.C_Item or not _G.C_Item.GetItemInfoInstant
        or not _G.C_TooltipInfo or not _G.C_TooltipInfo.GetHyperlink then
        return false, "item-links-api-unavailable"
    end
    for _, event in ipairs(EVENTS) do
        if not pcall(util.AddMessageEventFilter, event, Filter) then
            self:SetEnabled(false)
            return false, "item-links-filter-install-failed"
        end
        installed[event] = true
        self.filterInstalled = true
    end
    if YUI.Event then YUI.Event:On("ITEM_DATA_LOAD_RESULT", "OnItemData", self) end
    self.enabled = true
    return true
end

function ItemLinks:GetRuntimeGauges(target)
    target.itemLinksCache = self.cacheCount
    target.itemLinksPending = pendingCount
    target.itemLinksQueries = self.queries
    target.itemLinksCacheHits = self.cacheHits
    target.itemLinksFailures = self.failures
    local count = 0
    for _ in pairs(installed) do count = count + 1 end
    target.itemLinksFilters = count
    return target
end

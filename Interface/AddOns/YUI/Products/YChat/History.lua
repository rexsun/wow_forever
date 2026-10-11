local YUI = _G.YUI
local YChat = YUI and YUI.YChat
if not YChat or (YUI.IsForever or YUI.IsRetail) ~= true then return end

local History = {}
YChat.HistoryRuntime = History

local System = YUI.API and YUI.API.System
local Unit = YUI.API and YUI.API.Unit
local Adapter = YChat.Adapter
local L = YUI.Locale and YUI.Locale:Get("YChat") or {}
local concat = table.concat
local floor = math.floor
local type = type

local HISTORY_SCHEMA = 2
local currentStore
local currentCharacterKey
local snapshotLines = {}
local replaySlots = {}
local replayTexts = {}
local activeCategories = {}
local originalFrameLimits = setmetatable({}, { __mode = "k" })
local frameLimitApplyOK = true
local frameLimitApplyReason

local EVENT_CATEGORIES = {
    CHAT_MSG_SAY = "player",
    CHAT_MSG_YELL = "player",
    CHAT_MSG_EMOTE = "player",
    CHAT_MSG_TEXT_EMOTE = "player",
    CHAT_MSG_GUILD = "guild",
    CHAT_MSG_OFFICER = "guild",
    CHAT_MSG_PARTY = "group",
    CHAT_MSG_PARTY_LEADER = "group",
    CHAT_MSG_RAID = "group",
    CHAT_MSG_RAID_LEADER = "group",
    CHAT_MSG_RAID_WARNING = "group",
    CHAT_MSG_INSTANCE_CHAT = "group",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "group",
    CHAT_MSG_CHANNEL = "channel",
    CHAT_MSG_COMMUNITIES_CHANNEL = "channel",
    CHAT_MSG_WHISPER = "whisper",
    CHAT_MSG_WHISPER_INFORM = "whisper",
    CHAT_MSG_BN_WHISPER = "whisper",
    CHAT_MSG_BN_WHISPER_INFORM = "whisper",
    YCHAT_PRINT = "output",
    CHAT_MSG_SYSTEM = "system",
    CHAT_MSG_LOOT = "rewards",
    CHAT_MSG_CURRENCY = "rewards",
    CHAT_MSG_MONEY = "rewards",
    CHAT_MSG_ACHIEVEMENT = "achievement",
    CHAT_MSG_GUILD_ACHIEVEMENT = "achievement",
}
local CATEGORY_KEYS = {
    "player",
    "guild",
    "group",
    "channel",
    "whisper",
    "output",
    "system",
    "rewards",
    "achievement",
}
local REPLAY_CATEGORIES = {
    player = true,
    guild = true,
    group = true,
    channel = true,
    whisper = true,
}

History.runtimeEnabled = false
History.configEnabled = false
History.lastReason = "not-started"
History.recordedMessages = 0
History.recordBypasses = 0
History.replayedMessages = 0
History.loginReplayDone = false
History.loginReplayPending = false

local function T(key, fallback)
    local value = L[key]
    return type(value) == "string" and value ~= "" and value or fallback
end

local function StatIncrement(field, amount)
    local stats = YChat.Stats
    if stats and stats.Increment then stats:Increment(field, amount) end
end

local function ClearSnapshotLines()
    for index = #snapshotLines, 1, -1 do snapshotLines[index] = nil end
end

local function ClearReplaySlots()
    for index = #replaySlots, 1, -1 do replaySlots[index] = nil end
    for index = #replayTexts, 1, -1 do replayTexts[index] = nil end
end

local function ReadCharacterKey()
    if not Unit or type(Unit.GetDisplayNameInfo) ~= "function" then return nil end
    local ok, info = pcall(Unit.GetDisplayNameInfo, "player")
    if not ok or type(info) ~= "table"
        or type(info.nameRaw) ~= "string"
        or info.nameRaw == ""
    then
        return nil
    end
    local realm = info.realm
    if type(realm) ~= "string" or realm == "" then
        realm = type(Unit.GetNormalizedRealmName) == "function"
            and Unit.GetNormalizedRealmName()
            or nil
    end
    if type(realm) ~= "string" or realm == "" then
        realm = type(Unit.GetRealmName) == "function" and Unit.GetRealmName() or nil
    end
    if type(realm) ~= "string" or realm == "" then return nil end
    return info.nameRaw .. "-" .. realm
end

local function GetHistoryRoot(create)
    local db = YUI.DB
    if not db or type(db.GetGlobal) ~= "function"
        or (type(db.IsReady) == "function" and db:IsReady() ~= true)
    then
        return nil
    end
    local ok, global = pcall(db.GetGlobal, db, YChat.PRODUCT_ID)
    if not ok or type(global) ~= "table" then return nil end
    if type(global.historyByCharacter) ~= "table" then
        if not create then return nil end
        global.historyByCharacter = {}
    end
    return global.historyByCharacter
end

function History:GetCharacterKey()
    return ReadCharacterKey()
end

local function RingIndex(start, offset, limit)
    return ((start - 1 + offset) % limit) + 1
end

local function NormalizeStore(store, targetLimit)
    if type(store) ~= "table" then store = {} end
    if store.schema == 1 and type(store.slots) == "table" then
        store.schema = HISTORY_SCHEMA
    elseif store.schema ~= HISTORY_SCHEMA or type(store.slots) ~= "table" then
        store.schema = HISTORY_SCHEMA
        store.head = 1
        store.count = 0
        store.limit = targetLimit
        store.slots = {}
        return store
    end

    local oldLimit = floor(tonumber(store.limit) or targetLimit)
    if oldLimit < 1 then oldLimit = targetLimit end
    local oldCount = floor(tonumber(store.count) or 0)
    if oldCount < 0 then oldCount = 0 end
    if oldCount > oldLimit then oldCount = oldLimit end
    local oldHead = floor(tonumber(store.head) or 1)
    if oldHead < 1 or oldHead > oldLimit then oldHead = 1 end

    if oldLimit ~= targetLimit then
        local keep = oldCount < targetLimit and oldCount or targetLimit
        local oldest = oldCount < oldLimit and 1 or oldHead
        local skip = oldCount - keep
        local slots = {}
        for index = 1, keep do
            local sourceIndex = RingIndex(oldest, skip + index - 1, oldLimit)
            slots[index] = store.slots[sourceIndex]
        end
        store.slots = slots
        store.limit = targetLimit
        store.count = keep
        store.head = keep < targetLimit and keep + 1 or 1
        return store
    end

    store.limit = targetLimit
    store.count = oldCount
    store.head = oldHead
    return store
end

function History:WantsEvent(event)
    local category = EVENT_CATEGORIES[event]
    if not category then return false end
    return activeCategories[category] == true
end

function History:WantsReplayEvent(event)
    local category = EVENT_CATEGORIES[event]
    if not category or REPLAY_CATEGORIES[category] ~= true then return false end
    return activeCategories[category] == true
end

function History:RefreshStore()
    local config = YChat:GetHistory()
    self.configEnabled = config and config.enabled == true or false
    local categories = config and config.categories
    for index = 1, #CATEGORY_KEYS do
        local key = CATEGORY_KEYS[index]
        activeCategories[key] = type(categories) == "table" and categories[key] == true
    end
    currentCharacterKey = ReadCharacterKey()
    if not currentCharacterKey then
        currentStore = nil
        return false, "history-character-key-unavailable"
    end
    local root = GetHistoryRoot(self.configEnabled)
    if not root then
        currentStore = nil
        if not self.configEnabled then return true end
        return false, "history-global-db-unavailable"
    end
    local store = root[currentCharacterKey]
    if type(store) ~= "table" and not self.configEnabled then
        currentStore = nil
        return true
    end
    store = NormalizeStore(store, config and config.limit or 2000)
    root[currentCharacterKey] = store
    currentStore = store
    return true
end

local function ApplyFrameLimit(frame)
    if not History.runtimeEnabled or not Adapter then return true end
    local config = YChat:GetHistory()
    local target = config and config.frameLimit or 200
    local current, readReason = Adapter:ReadMaxLines(frame)
    if current == nil then return false, readReason end
    if originalFrameLimits[frame] == nil then originalFrameLimits[frame] = current end
    if current == target then return true end
    return Adapter:WriteMaxLines(frame, target, false)
end

local function ApplyDiscoveredFrameLimit(frame)
    local ok, reason = ApplyFrameLimit(frame)
    if not ok then
        frameLimitApplyOK = false
        frameLimitApplyReason = reason
    end
end

function History:RefreshFrameLimits()
    if not self.runtimeEnabled or not Adapter then return true end
    frameLimitApplyOK = true
    frameLimitApplyReason = nil
    Adapter:ForEachSupportedFrame(ApplyDiscoveredFrameLimit)
    return frameLimitApplyOK, frameLimitApplyReason
end

function History:RestoreFrameLimits()
    if not Adapter then return true end
    local restored = true
    local lastReason
    for frame, original in pairs(originalFrameLimits) do
        local current = Adapter:ReadMaxLines(frame)
        if current == original then
            originalFrameLimits[frame] = nil
        else
            local ok, reason = Adapter:WriteMaxLines(frame, original, true)
            if ok then
                originalFrameLimits[frame] = nil
            else
                restored = false
                lastReason = reason
            end
        end
    end
    return restored, lastReason
end

local function Bypass(reason)
    History.lastReason = reason
    History.recordBypasses = History.recordBypasses + 1
    StatIncrement("historyBypasses")
    return false, reason
end

function History:ProcessMessage(
    event,
    text,
    sender,
    languageName,
    channelName,
    playerName2,
    specialFlags,
    zoneChannelID,
    channelIndex,
    channelBaseName,
    senderGUID,
    bnSenderID,
    bnDisplayName
)
    if not self.runtimeEnabled or not self.configEnabled then
        return Bypass("history-disabled")
    end
    if not self:WantsEvent(event) then return Bypass("history-event-bypassed") end
    if type(text) ~= "string" or text == "" then
        return Bypass("history-text-invalid")
    end
    local store = currentStore
    if not store then
        local ready, reason = self:RefreshStore()
        if not ready then return Bypass(reason) end
        store = currentStore
    end

    local index = store.head
    local slot = store.slots[index]
    if type(slot) ~= "table" then
        slot = {}
        store.slots[index] = slot
    end
    slot.epoch = System and System.GetServerTime and System.GetServerTime() or 0
    slot.event = event
    slot.sender = type(sender) == "string" and sender or ""
    slot.text = text
    slot.languageName = type(languageName) == "string" and languageName or nil
    slot.channelName = type(channelName) == "string" and channelName or nil
    slot.playerName2 = type(playerName2) == "string" and playerName2 or nil
    slot.specialFlags = type(specialFlags) == "string" and specialFlags or nil
    slot.zoneChannelID = type(zoneChannelID) == "number" and zoneChannelID or nil
    slot.channelIndex = type(channelIndex) == "number" and channelIndex or nil
    slot.channelBaseName = type(channelBaseName) == "string" and channelBaseName or nil
    slot.senderGUID = type(senderGUID) == "string" and senderGUID or nil
    slot.bnSenderID = type(bnSenderID) == "number" and bnSenderID or nil
    slot.bnDisplayName = type(bnDisplayName) == "string" and bnDisplayName or nil
    slot.bnBattleTag = nil
    if (event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM")
        and Adapter and type(Adapter.ReadHistoryBattleTag) == "function" then
        slot.bnBattleTag = Adapter:ReadHistoryBattleTag(bnSenderID)
    end
    store.head = index < store.limit and index + 1 or 1
    if store.count < store.limit then store.count = store.count + 1 end
    self.recordedMessages = self.recordedMessages + 1
    self.lastReason = "history-recorded"
    StatIncrement("historyRecordedMessages")
    return true
end

local function BuildSnapshot(store, viewer)
    ClearSnapshotLines()
    if not store or store.count < 1 then
        snapshotLines[1] = T("settings.records.empty", "暂无聊天记录。")
        return concat(snapshotLines, "\n")
    end
    local timestamp = YChat:GetTimestamp()
    local pattern = timestamp and timestamp.format == "hm" and "%H:%M" or "%H:%M:%S"
    local oldest = store.count < store.limit and 1 or store.head
    for offset = 0, store.count - 1 do
        local slot = store.slots[RingIndex(oldest, offset, store.limit)]
        if type(slot) == "table" and type(slot.text) == "string"
            and History:WantsEvent(slot.event)
        then
            local timeText = System and System.FormatDate
                and System.FormatDate(pattern, slot.epoch)
                or nil
            local text = Adapter and Adapter.FormatHistoricalMessage
                and Adapter:FormatHistoricalMessage(
                    slot,
                    T("settings.records.channel_fallback", "Channel")
                )
                or nil
            local red, green, blue
            if text ~= nil and Adapter and type(Adapter.ReadHistoricalMessageColor) == "function" then
                red, green, blue = Adapter:ReadHistoricalMessageColor(slot.event)
            end
            text = viewer:PrepareExportText(text, red, green, blue)
            if text ~= nil then
                snapshotLines[#snapshotLines + 1] = timeText and (timeText .. " " .. text) or text
            end
        end
    end
    if #snapshotLines == 0 then
        snapshotLines[1] = T("settings.records.empty", "暂无聊天记录。")
    end
    return concat(snapshotLines, "\n")
end

function History:OpenHistorySnapshot()
    if not currentStore then self:RefreshStore() end
    local viewer = YChat.CopyViewer
    if not viewer
        or type(viewer.OpenTextSnapshot) ~= "function"
        or type(viewer.PrepareExportText) ~= "function"
    then
        return false, "history-viewer-unavailable"
    end
    local text = BuildSnapshot(currentStore, viewer)
    local opened, reason = viewer:OpenTextSnapshot(
        T("settings.records.snapshot_title", "聊天记录"),
        text
    )
    ClearSnapshotLines()
    self.lastReason = opened and "history-snapshot-open" or reason
    return opened, reason
end

local function FormatReplaySlot(slot, bnetLookup, frame)
    local text = Adapter:FormatHistoricalMessage(
        slot,
        T("settings.records.channel_fallback", "Channel"),
        true,
        bnetLookup,
        frame
    )
    if type(text) ~= "string" or text == "" then return nil end
    if YChat.ItemLinks then text = YChat.ItemLinks:Transform(text) end
    return text
end

local function ReplaySlot(frame, slot, text)
    local shadow = YChat.Shadow
    local timestamp = YChat:GetTimestamp()
    local activeLayout = YChat.timestampLayoutAtLoad
        or (timestamp and timestamp.layout)
        or "column"
    local timestampEnabled = YChat.timestampEnabledAtLoad
    if timestampEnabled == nil then
        timestampEnabled = timestamp and timestamp.enabled == true
    end
    if timestampEnabled and activeLayout == "nativeInline"
        and shadow and type(shadow.FormatHistoricalInlineTimestamp) == "function"
    then
        local prefix = shadow:FormatHistoricalInlineTimestamp(slot.epoch)
        if type(prefix) == "string" and prefix ~= "" then
            text = prefix .. " " .. text
        end
    elseif timestampEnabled and activeLayout == "column"
        and shadow and type(shadow.SetNextHistoricalTimestamp) == "function"
    then
        shadow:SetNextHistoricalTimestamp(frame, slot.epoch)
    end

    local red, green, blue = Adapter:ReadHistoricalMessageColor(slot.event)
    local ok = pcall(frame.BackFillMessage, frame, text, red, green, blue)
    if shadow and type(shadow.ClearNextHistoricalTimestamp) == "function" then
        shadow:ClearNextHistoricalTimestamp(frame)
    end
    return ok
end

local function ReplaySeparator(frame)
    local text = T(
        "history.replay.separator",
        "---------- 以上为历史消息 ----------"
    )
    if type(text) ~= "string" or text == "" then return false end
    return pcall(frame.BackFillMessage, frame, text, 0.5, 0.58, 0.66)
end

function History:ReplayOnLogin(initialLogin, reloadingUI)
    if self.loginReplayDone then return true, false end
    if initialLogin ~= true and reloadingUI ~= true then
        return true, false
    end
    local config = YChat:GetHistory()
    if not self.runtimeEnabled
        or not config
        or config.enabled ~= true
        or config.restoreOnLogin ~= true
    then
        self.loginReplayDone = true
        self.loginReplayPending = false
        self.lastReason = "history-login-replay-disabled"
        return true, false
    end
    if not Adapter or type(Adapter.GetRestrictionState) ~= "function"
        or Adapter:GetRestrictionState() ~= "OPEN"
    then
        self.loginReplayPending = true
        self.lastReason = "history-login-replay-restriction-pending"
        return true, false
    end
    self.loginReplayPending = false
    if not currentStore then
        local ready, reason = self:RefreshStore()
        if not ready then return false, reason end
    end
    local store = currentStore
    if not store or store.count < 1 then
        self.loginReplayDone = true
        self.lastReason = "history-login-replay-empty"
        return true, false
    end

    local frame = Adapter:FindFrame("ChatFrame1")
    if not frame or type(frame.BackFillMessage) ~= "function" then
        return false, "history-login-replay-frame-unavailable"
    end
    local target = floor(tonumber(config.restoreLimit) or 0)
    local frameLimit = floor(tonumber(config.frameLimit) or target)
    if target > frameLimit then target = frameLimit end
    if target < 1 then
        self.loginReplayDone = true
        return true, false
    end

    ClearReplaySlots()
    local bnetLookup
    local bnetLookupRead = false
    local oldest = store.count < store.limit and 1 or store.head
    for offset = store.count - 1, 0, -1 do
        local slot = store.slots[RingIndex(oldest, offset, store.limit)]
        if type(slot) == "table"
            and type(slot.text) == "string"
            and self:WantsReplayEvent(slot.event)
        then
            if not bnetLookupRead and (slot.event == "CHAT_MSG_BN_WHISPER"
                or slot.event == "CHAT_MSG_BN_WHISPER_INFORM") then
                bnetLookupRead = true
                bnetLookup = Adapter.BuildHistoryBNetLookup and Adapter:BuildHistoryBNetLookup()
            end
            local text = FormatReplaySlot(slot, bnetLookup, frame)
            if text then
                local index = #replaySlots + 1
                replaySlots[index] = slot
                replayTexts[index] = text
            end
            if #replaySlots >= target then break end
        end
    end

    local replayed = 0
    if #replaySlots > 0 and not ReplaySeparator(frame) then
        ClearReplaySlots()
        if Adapter:GetRestrictionState() ~= "OPEN" then
            self.loginReplayPending = true
            self.lastReason = "history-login-replay-restriction-pending"
            return true, false
        end
        return false, "history-login-replay-separator-failed"
    end
    for index = 1, #replaySlots do
        if ReplaySlot(frame, replaySlots[index], replayTexts[index]) then
            replayed = replayed + 1
        end
    end
    ClearReplaySlots()
    self.loginReplayDone = true
    self.replayedMessages = self.replayedMessages + replayed
    self.lastReason = replayed > 0
        and "history-login-replayed"
        or "history-login-replay-no-safe-records"
    if replayed > 0 then StatIncrement("historyReplayedMessages", replayed) end
    return true, replayed
end

function History:OnRestrictionStateChanged(state)
    if state ~= "OPEN" or self.loginReplayPending ~= true then return true end
    return self:ReplayOnLogin(true, false)
end

function History:ClearCharacterHistory()
    local input = YChat.ChannelInput
    if input and type(input.ClearInputHistory) == "function" then
        local cleared, reason = input:ClearInputHistory(false)
        if not cleared then return false, reason end
    end
    if not currentStore then
        local ready, reason = self:RefreshStore()
        if not ready then return false, reason end
        if not currentStore then return true end
    end
    for index in pairs(currentStore.slots) do currentStore.slots[index] = nil end
    currentStore.head = 1
    currentStore.count = 0
    self.lastReason = "history-cleared"
    StatIncrement("historyClearOperations")
    return true
end

function History:GetCount()
    return currentStore and currentStore.count or 0
end

function History:GetCharacterCount()
    local root = GetHistoryRoot(false)
    if not root then return 0 end
    local count = 0
    for _, store in pairs(root) do
        if type(store) == "table" and floor(tonumber(store.count) or 0) > 0 then
            count = count + 1
        end
    end
    return count
end

function History:ClearAllHistory(deferRecreate)
    local input = YChat.ChannelInput
    if input and type(input.ClearInputHistory) == "function" then
        local cleared, reason = input:ClearInputHistory(true)
        if not cleared then return false, reason end
    end
    local root = GetHistoryRoot(true)
    if not root then return false, "history-global-db-unavailable" end
    for characterKey in pairs(root) do root[characterKey] = nil end
    currentStore = nil
    if deferRecreate ~= true then
        local ready, reason = self:RefreshStore()
        if not ready then return false, reason end
    end
    self.lastReason = "history-all-cleared"
    StatIncrement("historyClearOperations")
    return true
end

function History:SetEnabled(enabled, reason)
    local nextEnabled = enabled == true
    if not nextEnabled then
        local restored, restoreReason = self:RestoreFrameLimits()
        if not restored then return false, restoreReason end
    end
    self.runtimeEnabled = nextEnabled
    if self.runtimeEnabled then
        local storeReady, storeReason = self:RefreshStore()
        local frameReady, frameReason = self:RefreshFrameLimits()
        if not frameReady then return false, frameReason end
        if not storeReady then
            self.lastReason = storeReason
            return true
        end
    end
    self.lastReason = reason
        or (self.runtimeEnabled and "history-runtime-enabled" or "history-runtime-disabled")
    return true
end

function History:OnConfigChanged()
    local ready, reason = self:RefreshStore()
    if not ready then return false, reason end
    return self:RefreshFrameLimits()
end

function History:OnFrameDiscovered(frame, valid)
    if valid ~= true or not self.runtimeEnabled then return true end
    return ApplyFrameLimit(frame)
end

function History:GetRuntimeGauges(target)
    target = target or {}
    target.historyRuntimeEnabled = self.runtimeEnabled == true
    target.historyConfigEnabled = self.configEnabled == true
    target.historyStoredMessages = self:GetCount()
    target.historyRecordedMessages = self.recordedMessages
    target.historyReplayedMessages = self.replayedMessages
    target.historyBypasses = self.recordBypasses
    target.historyLoginReplayPending = self.loginReplayPending == true
    return target
end

function YChat:OpenHistorySnapshot()
    return History:OpenHistorySnapshot()
end

function YChat:ClearCharacterHistory()
    return History:ClearCharacterHistory()
end

function YChat:ClearAllHistory(deferRecreate)
    return History:ClearAllHistory(deferRecreate)
end

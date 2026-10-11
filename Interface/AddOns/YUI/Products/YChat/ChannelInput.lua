local YUI = _G.YUI
local YChat = YUI and YUI.YChat
if not YChat or (YUI.IsForever or YUI.IsRetail) ~= true then return end

local Adapter = YChat.Adapter
local ChatInput = YUI.API and YUI.API.ChatInput
local System = YUI.API and YUI.API.System
local ChannelInput = {}
YChat.ChannelInput = ChannelInput
ChannelInput.restorePending = false

local GetChannelList = _G.GetChannelList
local IsAltKeyDown = _G.IsAltKeyDown
local IsSecureCmd = _G.IsSecureCmd
local hooksecurefunc = _G.hooksecurefunc
local pcall = pcall
local type = type
local floor = math.floor
local find = string.find
local sub = string.sub
local gsub = string.gsub
local match = string.match
local lower = string.lower
local pairs = pairs
local strtrim = _G.strtrim

local publicById = {}
local pendingByFrame = setmetatable({}, { __mode = "k" })
local dirtyFrameSet = setmetatable({}, { __mode = "k" })
local dirtyFrames = {}
local arrowStateByFrame = setmetatable({}, { __mode = "k" })
local arrowFrameByEditBox = setmetatable({}, { __mode = "k" })
local arrowModeHooked = setmetatable({}, { __mode = "k" })
local inputHistoryByFrame = setmetatable({}, { __mode = "k" })
local inputFrameByEditBox = setmetatable({}, { __mode = "k" })
local inputHistoryHooks = setmetatable({}, { __mode = "k" })
local installedFormatting = false
local installedSenderFilter = false
local installedTab = false
local installedFilterEvents = {}
local publicFormattingEnabled = false
local activePublicFormat = "native"
local queuedCount = 0
local dirtyFrameCount = 0
local activeTransformState
local activeTransformOutput
local activeTransformLineID
local activeTransformEvent
local activeTransformReplacement
local activeTransformChannelID
local arrowScanGeneration = 0
local arrowScanFailed = false
local arrowModeLastFailure = "none"
local INPUT_HISTORY_LIMIT = 32
local INPUT_HISTORY_TTL = 900
local inputHistoryGlobal
local inputHistoryCharacterKey
local MAX_PENDING_MESSAGES = 64
local MAX_OWNED_MESSAGES = 1000
local MAX_PREFIX_START = 80
local MAX_PREFIX_END = 512
local PUBLIC_EVENT = "CHAT_MSG_CHANNEL"
local COMMUNITY_EVENT = "CHAT_MSG_COMMUNITIES_CHANNEL"
local BNET_OUTGOING_EVENT = "CHAT_MSG_BN_WHISPER_INFORM"
local FILTER_EVENTS = {
    PUBLIC_EVENT,
    COMMUNITY_EVENT,
    BNET_OUTGOING_EVENT,
}
local clientLocale = type(_G.GetLocale) == "function" and _G.GetLocale() or nil
local compactChineseSeparator = clientLocale == "zhCN" or clientLocale == "zhTW"
local SEPARATOR_EVENTS = {
    CHAT_MSG_CHANNEL = true, CHAT_MSG_COMMUNITIES_CHANNEL = true,
    CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true,
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true, CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER = true, CHAT_MSG_BN_WHISPER_INFORM = true,
}
local separatorSuffixes = {}
if compactChineseSeparator then
    for event in pairs(SEPARATOR_EVENTS) do
        local template = _G["CHAT_" .. sub(event, 10) .. "_GET"]
        if Adapter:IsExplicitlySafeValue(template) == true and type(template) == "string"
            and match(template, "：[ \t]+$") then
            separatorSuffixes[event] = match(template, "%%s([^%%]*)$")
            if separatorSuffixes[event] and event ~= PUBLIC_EVENT
                and event ~= COMMUNITY_EVENT and event ~= BNET_OUTGOING_EVENT then
                FILTER_EVENTS[#FILTER_EVENTS + 1] = event
            end
        end
    end
end

ChannelInput.enabled = false

local PLAYER_NAME_EVENTS = {
    CHAT_MSG_SAY = true, CHAT_MSG_YELL = true,
    CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true,
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_CHANNEL = true, CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_COMMUNITIES_CHANNEL = true,
    CHAT_MSG_EMOTE = true, CHAT_MSG_TEXT_EMOTE = true,
    CHAT_MSG_ACHIEVEMENT = true, CHAT_MSG_GUILD_ACHIEVEMENT = true,
}

function ChannelInput:FormatPlayerDisplayName(event, decoratedName, senderName, senderGUID)
    if not self.enabled or Adapter:GetRestrictionState() ~= "OPEN" then return decoratedName end
    local config = YChat:GetChannelInput()
    if not config or config.hidePlayerRealm ~= true then return decoratedName end
    if Adapter:IsExplicitlySafeValue(event) ~= true or type(event) ~= "string"
        or not PLAYER_NAME_EVENTS[event]
        or Adapter:IsExplicitlySafeValue(decoratedName) ~= true or type(decoratedName) ~= "string"
        or Adapter:IsExplicitlySafeValue(senderName) ~= true or type(senderName) ~= "string"
    then return decoratedName end
    if event == "CHAT_MSG_COMMUNITIES_CHANNEL" and
        (Adapter:IsExplicitlySafeValue(senderGUID) ~= true or type(senderGUID) ~= "string"
            or not match(senderGUID, "^Player%-")) then return decoratedName end
    local shortName = match(senderName, "^([^%s%c|:%-]+)%-[^%s%c|:]+$")
    if not shortName then return decoratedName end
    -- 只接受可确认属于发送者的姓名标签；不扫描正文、链接或未知装饰。
    local plain = gsub(gsub(decoratedName, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
    if plain ~= senderName and plain ~= "[" .. senderName .. "]" then return decoratedName end
    local first, last = find(decoratedName, senderName, 1, true)
    if not first then return decoratedName end
    return sub(decoratedName, 1, first - 1) .. shortName .. sub(decoratedName, last + 1)
end

local function PlayerRealmSenderFilter(event, decoratedName, _, senderName, _, _, _, _, _, _, _, _, _, senderGUID)
    return ChannelInput:FormatPlayerDisplayName(event, decoratedName, senderName, senderGUID)
end

local function UpdateSenderFilter(enable)
    if installedSenderFilter == enable then return true end
    local util = _G.ChatFrameUtil
    local callback = type(util) == "table" and
        (enable and util.AddSenderNameFilter or util.RemoveSenderNameFilter)
    if type(callback) ~= "function" then return false, "player-realm-filter-api-unavailable" end
    if not pcall(callback, PlayerRealmSenderFilter) then return false, "player-realm-filter-failed" end
    installedSenderFilter = enable
    return true
end

local function StatIncrement(field)
    local stats = YChat.Stats
    if stats and stats.Increment then stats:Increment(field) end
end

local function StatSet(field, value)
    local stats = YChat.Stats
    if stats and stats.Set then stats:Set(field, value) end
end

local function IsWorldChannelName(name)
    return name == "大脚世界频道" or name == "大腳世界頻道"
end

local function CompactPublicName(name)
    if type(name) ~= "string" or name == "" then return nil end
    return gsub(name, "%s+%-%s+.*$", "")
end

local function FormatPublicChannelName(id, baseName, format)
    if type(id) ~= "number" or id < 1 or floor(id) ~= id then return nil end
    local compact = CompactPublicName(baseName)
    if type(compact) ~= "string" or compact == "" then return nil end
    if IsWorldChannelName(compact) then compact = "世界" end
    if format == "short" then return compact end
    return tostring(id) .. ". " .. compact
end

local function RemoveHistoricalChannelLinks(template)
    return (gsub(template, "|Hchannel:[^|]-|h(.-)|h", "%1"))
end

function ChannelInput:RefreshCache()
    publicById = {}
    publicFormattingEnabled = false
    activePublicFormat = "native"
    local config = YChat:GetChannelInput()
    if not self.enabled or not config or config.publicFormat == "native" then
        StatSet("channelCacheEntries", 0)
        return true
    end
    activePublicFormat = config.publicFormat
    if type(GetChannelList) ~= "function" then
        StatSet("channelCacheEntries", 0)
        return false, "channel-list-api-unavailable"
    end
    local values = { pcall(GetChannelList) }
    if values[1] ~= true or (#values - 1) % 3 ~= 0 then
        StatSet("channelCacheEntries", 0)
        return false, "channel-list-read-failed"
    end
    local count = 0
    for index = 2, #values, 3 do
        local id = values[index]
        local name = values[index + 1]
        local disabled = values[index + 2]
        if Adapter:IsExplicitlySafeValue(id) ~= true
            or Adapter:IsExplicitlySafeValue(name) ~= true
            or Adapter:IsExplicitlySafeValue(disabled) ~= true
        then
            publicById = {}
            StatSet("channelCacheEntries", 0)
            return false, "channel-list-value-unsafe"
        end
        if type(id) == "number" and id >= 1 and floor(id) == id
            and type(name) == "string" and name ~= ""
            and disabled ~= true
        then
            local formatted = FormatPublicChannelName(id, name, activePublicFormat)
            if formatted then
                publicById[id] = formatted
                count = count + 1
            end
        end
    end
    publicFormattingEnabled = true
    StatSet("channelCacheEntries", count)
    return true
end

function ChannelInput:ResolveHistoricalChannelName(rawName, channelIndex, baseName, fallback)
    if not self.enabled or Adapter:GetRestrictionState() ~= "OPEN" then return nil end
    if Adapter:IsExplicitlySafeValue(channelIndex) ~= true
        or Adapter:IsExplicitlySafeValue(rawName) ~= true
        or Adapter:IsExplicitlySafeValue(baseName) ~= true then return nil end
    local index = tonumber(channelIndex)
    if index ~= nil and (index < 1 or floor(index) ~= index) then return nil end
    local source = type(rawName) == "string" and rawName ~= "" and rawName
        or type(baseName) == "string" and baseName ~= "" and baseName
        or nil
    if source and Adapter:IsExplicitlySafeValue(source) == true then
        -- 历史频道编号只属于旧会话，不能用当前编号缓存替换其身份。
        local config = YChat:GetChannelInput()
        local format = config and config.publicFormat
        if format == "numberShort" or format == "short" then
            local rawID, rawBase = match(source, "^(%d+)%. (.*)$")
            local savedBase = type(baseName) == "string" and baseName ~= "" and baseName
                or rawBase or source
            local formatted = FormatPublicChannelName(index or tonumber(rawID), savedBase, format)
            if formatted then return formatted end
        end
        local util = _G.ChatFrameUtil
        if type(util) == "table" and type(util.ResolvePrefixedChannelName) == "function" then
            local ok, resolved = pcall(util.ResolvePrefixedChannelName, source)
            if ok and type(resolved) == "string" and resolved ~= ""
                and Adapter:IsExplicitlySafeValue(resolved) == true
            then
                return resolved
            end
        end
        return source
    end
    return type(fallback) == "string" and fallback ~= "" and fallback or nil
end

function ChannelInput:ResolveHistoricalFormatKey(chatType)
    if not self.enabled or Adapter:GetRestrictionState() ~= "OPEN"
        or type(chatType) ~= "string"
        or Adapter:IsExplicitlySafeValue(chatType) ~= true
    then
        return nil
    end
    local native = _G["CHAT_" .. chatType .. "_GET"]
    if type(native) == "string" and native ~= ""
        and Adapter:IsExplicitlySafeValue(native) == true
    then
        local template = RemoveHistoricalChannelLinks(native)
        if compactChineseSeparator and SEPARATOR_EVENTS["CHAT_MSG_" .. chatType] then
            template = gsub(template, "：[ \t]+$", "：")
        end
        return template
    end
    return nil
end

local function ResolvePublicReplacement(channelID, rawName)
    if type(channelID) ~= "number"
        or Adapter:IsExplicitlySafeValue(channelID) ~= true
        or channelID < 1
        or floor(channelID) ~= channelID
    then
        return nil
    end
    local cached = publicById[channelID]
    if type(cached) == "string" and cached ~= "" then return cached end
    if type(rawName) ~= "string"
        or rawName == ""
        or Adapter:IsExplicitlySafeValue(rawName) ~= true
    then
        return nil
    end
    local _, _, rawID, baseName = find(rawName, "^(%d+)%. (.*)$")
    if tonumber(rawID) ~= channelID then return nil end
    return FormatPublicChannelName(channelID, baseName, activePublicFormat)
end

local function GetFramePending(frame)
    local state = pendingByFrame[frame]
    if state then return state end
    state = {
        events = {},
        replacements = {},
        channelIDs = {},
        count = 0,
        reconcile = false,
        ownedEvents = {},
        ownedReplacements = {},
        ownedChannelIDs = {},
        ownedOrder = {},
        ownedHead = 1,
        ownedCount = 0,
    }
    pendingByFrame[frame] = state
    return state
end

local function PrimeTransformFrame(frame)
    GetFramePending(frame)
end

local function RefreshTransformGauges()
    StatSet("channelTransformQueueDepth", queuedCount)
    StatSet("channelTransformDirtyFrames", dirtyFrameCount)
end

local function MarkFrameDirty(frame)
    if dirtyFrameSet[frame] then return true end
    dirtyFrameSet[frame] = true
    dirtyFrameCount = dirtyFrameCount + 1
    dirtyFrames[dirtyFrameCount] = frame
    local enabled, reason = Adapter:SetChannelDeferredDriverEnabled(true)
    if enabled then
        RefreshTransformGauges()
        return true
    end
    dirtyFrames[dirtyFrameCount] = nil
    dirtyFrameCount = dirtyFrameCount - 1
    dirtyFrameSet[frame] = nil
    StatSet("channelTransformLastFailure", reason or "channel-driver-enable-failed")
    RefreshTransformGauges()
    return false
end

local function QueueMessage(frame, event, lineID, replacement, channelID)
    local state = pendingByFrame[frame]
    if not state then
        StatIncrement("channelTransformQueueDrops")
        StatSet("channelTransformLastFailure", "channel-transform-frame-unprimed")
        return false
    end
    if state.events[lineID] == nil then
        if queuedCount >= MAX_PENDING_MESSAGES then
            StatIncrement("channelTransformQueueDrops")
            StatSet("channelTransformLastFailure", "channel-transform-queue-full")
            return false
        end
        state.count = state.count + 1
        queuedCount = queuedCount + 1
    end
    state.events[lineID] = event
    state.replacements[lineID] = replacement
    state.channelIDs[lineID] = channelID
    if MarkFrameDirty(frame) then
        RefreshTransformGauges()
        return true
    end
    state.events[lineID] = nil
    state.replacements[lineID] = nil
    state.channelIDs[lineID] = nil
    state.count = state.count - 1
    queuedCount = queuedCount - 1
    StatIncrement("channelTransformQueueDrops")
    RefreshTransformGauges()
    return false
end

local function ChannelMessageFilter(frame, event,
    arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10,
    arg11, arg12, arg13, arg14)
    StatIncrement("filterCalls")
    if not ChannelInput.enabled
        or Adapter:GetRestrictionState() ~= "OPEN"
    then
        StatIncrement("filterBypasses")
        StatIncrement("channelTransformBypasses")
        return false
    end
    if type(event) ~= "string"
        or Adapter:IsExplicitlySafeValue(event) ~= true
    then
        StatIncrement("filterBypasses")
        StatIncrement("channelTransformBypasses")
        return false
    end

    if separatorSuffixes[event]
        and Adapter:IsExplicitlySafeValue(frame) == true
        and Adapter:IsTrustedSupportedFrame(frame) == true
        and Adapter:IsExplicitlySafeValue(arg11) == true and type(arg11) == "number"
        and arg11 > 0 and floor(arg11) == arg11
        and Adapter:IsExplicitlySafeValue(arg1) == true and type(arg1) == "string" then
        QueueMessage(frame, event, arg11, "", 0)
    end

    if event == PUBLIC_EVENT or event == COMMUNITY_EVENT then
        if publicFormattingEnabled ~= true
            or Adapter:IsExplicitlySafeValue(frame) ~= true
            or Adapter:IsTrustedSupportedFrame(frame) ~= true
            or type(arg11) ~= "number"
            or Adapter:IsExplicitlySafeValue(arg11) ~= true
            or arg11 < 1
            or floor(arg11) ~= arg11
            or type(arg8) ~= "number"
            or Adapter:IsExplicitlySafeValue(arg8) ~= true
            or arg8 < 1
            or floor(arg8) ~= arg8
            or type(arg4) ~= "string"
            or Adapter:IsExplicitlySafeValue(arg4) ~= true
        then
            StatIncrement("filterBypasses")
            StatIncrement("channelTransformBypasses")
            return false
        end
        local replacement = ResolvePublicReplacement(arg8, arg4)
        if not replacement then
            StatIncrement("filterBypasses")
            StatIncrement("channelTransformBypasses")
            return false
        end
        if not QueueMessage(frame, event, arg11, replacement, arg8) then
            StatIncrement("filterBypasses")
            StatIncrement("channelTransformBypasses")
        end
        return false
    end

    if event == BNET_OUTGOING_EVENT then
        local accountID = Adapter:ResolveBNetAccountID(arg2, arg13)
        if not accountID then
            StatIncrement("filterBypasses")
            return false
        end
        if accountID == arg13 then return false end
        return false,
            arg1, arg2, arg3, arg4, arg5, arg6, arg7,
            arg8, arg9, arg10, arg11, arg12, accountID, arg14
    end

    StatIncrement("filterBypasses")
    return false
end

local function ReadEventArg(eventArgs, index)
    return eventArgs[index]
end

local function ResolveTransformSpec(state, event, eventArgs)
    local lineOK, lineID = pcall(ReadEventArg, eventArgs, 11)
    if not lineOK
        or type(lineID) ~= "number"
        or Adapter:IsExplicitlySafeValue(lineID) ~= true
        or lineID < 1
        or floor(lineID) ~= lineID
    then
        return nil
    end

    local replacement
    local channelID
    if state.events[lineID] == event then
        replacement = state.replacements[lineID]
        channelID = state.channelIDs[lineID]
    elseif state.reconcile and state.ownedEvents[lineID] == event then
        replacement = state.ownedReplacements[lineID]
        channelID = state.ownedChannelIDs[lineID]
    else
        return nil
    end
    if replacement == "" and channelID == 0 and compactChineseSeparator then
        return lineID, replacement, channelID
    end
    if type(replacement) ~= "string" or replacement == ""
        or type(channelID) ~= "number"
        or channelID < 1
        or floor(channelID) ~= channelID
    then
        return nil
    end
    return lineID, replacement, channelID
end

local function HasSafeLeadingTimestamp(message, startIndex)
    if startIndex == 1 then return true end
    local leading = sub(message, 1, startIndex - 1)
    return find(leading, "^|c%x%x%x%x%x%x%x%x[^|]*|r%s*$") ~= nil
end

local function TransformPublicPrefix(message, replacement, channelID)
    local marker = "|Hchannel:channel:" .. channelID .. "|h["
    local startIndex, markerEnd = find(message, marker, 1, true)
    if not startIndex
        or startIndex > MAX_PREFIX_START
        or not HasSafeLeadingTimestamp(message, startIndex)
    then
        return nil
    end
    local labelEnd, prefixEnd = find(message, "]|h", markerEnd + 1, true)
    if not labelEnd or prefixEnd > MAX_PREFIX_END then return nil end
    return sub(message, 1, markerEnd) .. replacement .. sub(message, labelEnd)
end

local function RecordOwnedTransform(state, lineID, event, replacement, channelID)
    if state.ownedEvents[lineID] == nil then
        local slot
        if state.ownedCount < MAX_OWNED_MESSAGES then
            state.ownedCount = state.ownedCount + 1
            slot = state.ownedCount
        else
            slot = state.ownedHead
            local evicted = state.ownedOrder[slot]
            state.ownedEvents[evicted] = nil
            state.ownedReplacements[evicted] = nil
            state.ownedChannelIDs[evicted] = nil
            state.ownedHead = (state.ownedHead % MAX_OWNED_MESSAGES) + 1
        end
        state.ownedOrder[slot] = lineID
    end
    state.ownedEvents[lineID] = event
    state.ownedReplacements[lineID] = replacement
    state.ownedChannelIDs[lineID] = channelID
end

local function ShouldTransformMessage(message, r, g, b,
    infoID, accessID, typeID, event, eventArgs)
    activeTransformOutput = nil
    activeTransformLineID = nil
    if Adapter:GetRestrictionState() ~= "OPEN" then return false end
    local state = activeTransformState
    if not state
        or type(message) ~= "string"
        or Adapter:IsExplicitlySafeValue(message) ~= true
        or type(event) ~= "string"
        or Adapter:IsExplicitlySafeValue(event) ~= true
        or type(eventArgs) ~= "table"
        or Adapter:IsExplicitlySafeValue(eventArgs) ~= true
    then
        StatIncrement("channelTransformBypasses")
        return false
    end
    local lineID, replacement, channelID = ResolveTransformSpec(state, event, eventArgs)
    if not lineID then return false end
    local output = channelID > 0 and TransformPublicPrefix(message, replacement, channelID) or message
    output = output or message
    if compactChineseSeparator and SEPARATOR_EVENTS[event] then
        local bodyOK, body = pcall(ReadEventArg, eventArgs, 1)
        local template = _G["CHAT_" .. sub(event, 10) .. "_GET"]
        if bodyOK and Adapter:IsExplicitlySafeValue(body) == true and type(body) == "string" and body ~= ""
            and Adapter:IsExplicitlySafeValue(template) == true and type(template) == "string" then
            local spaces = match(template, "：([ \t]+)$")
            local suffix = match(template, "%%s([^%%]*)$")
            if spaces and suffix and sub(output, -#body) == body then
                local headerEnd = #output - #body
                if headerEnd >= #suffix and sub(output, headerEnd - #suffix + 1, headerEnd) == suffix then
                    output = sub(output, 1, headerEnd - #spaces) .. body
                end
            end
        end
    end
    if type(output) ~= "string"
        or output == message
        or Adapter:IsExplicitlySafeValue(output) ~= true
    then
        StatIncrement("channelTransformBypasses")
        return false
    end
    activeTransformOutput = output
    activeTransformLineID = lineID
    activeTransformEvent = event
    activeTransformReplacement = replacement
    activeTransformChannelID = channelID
    return true
end

local function ApplyTransformedMessage(message, r, g, b, ...)
    if Adapter:GetRestrictionState() ~= "OPEN" or not activeTransformOutput then
        return message, r, g, b, ...
    end
    RecordOwnedTransform(
        activeTransformState,
        activeTransformLineID,
        activeTransformEvent,
        activeTransformReplacement,
        activeTransformChannelID
    )
    StatIncrement("channelTransforms")
    return activeTransformOutput, r, g, b, ...
end

local function ClearPendingState(state)
    if not state then return end
    for lineID in pairs(state.events) do
        state.events[lineID] = nil
        state.replacements[lineID] = nil
        state.channelIDs[lineID] = nil
    end
    queuedCount = queuedCount - state.count
    if queuedCount < 0 then queuedCount = 0 end
    state.count = 0
    state.reconcile = false
end

local function ClearTransformQueue()
    for _, state in pairs(pendingByFrame) do ClearPendingState(state) end
    for index = 1, dirtyFrameCount do dirtyFrames[index] = nil end
    dirtyFrameSet = setmetatable({}, { __mode = "k" })
    dirtyFrameCount = 0
    queuedCount = 0
    activeTransformState = nil
    activeTransformOutput = nil
    activeTransformLineID = nil
    Adapter:SetChannelDeferredDriverEnabled(false)
    RefreshTransformGauges()
end

local function ResetTransformState()
    ClearTransformQueue()
    pendingByFrame = setmetatable({}, { __mode = "k" })
end

local function DrainChannelTransforms(abortReason)
    if abortReason ~= nil then
        StatSet("channelTransformLastFailure", abortReason)
        ClearTransformQueue()
        return
    end
    if not ChannelInput.enabled or Adapter:GetRestrictionState() ~= "OPEN" then
        ClearTransformQueue()
        return
    end
    local count = dirtyFrameCount
    dirtyFrameCount = 0
    for index = 1, count do
        local frame = dirtyFrames[index]
        dirtyFrames[index] = nil
        dirtyFrameSet[frame] = nil
        local state = pendingByFrame[frame]
        if state and (state.count > 0 or state.reconcile) then
            activeTransformState = state
            local transformed, reason = Adapter:TransformChannelMessages(
                frame,
                ShouldTransformMessage,
                ApplyTransformedMessage
            )
            activeTransformState = nil
            activeTransformOutput = nil
            activeTransformLineID = nil
            if not transformed then
                StatSet("channelTransformLastFailure", reason or "channel-transform-failed")
            end
            ClearPendingState(state)
        end
    end
    Adapter:SetChannelDeferredDriverEnabled(false)
    RefreshTransformGauges()
end

local function OnExternalTransform(frame)
    if not ChannelInput.enabled
        or publicFormattingEnabled ~= true
        or Adapter:GetRestrictionState() ~= "OPEN"
        or Adapter:IsTrustedSupportedFrame(frame) ~= true
    then
        return
    end
    local state = pendingByFrame[frame]
    if not state or state.ownedCount < 1 then return end
    state.reconcile = true
    if MarkFrameDirty(frame) then
        StatIncrement("channelTransformExternalReconciles")
    else
        state.reconcile = false
    end
end

local function IsExplicitlySafe(value)
    return type(Adapter.IsExplicitlySafeValue) == "function"
        and Adapter:IsExplicitlySafeValue(value) == true
end

local function ReadSafeMethod(object, callback, key)
    if type(callback) ~= "function" then return nil, false end
    local ok, value
    if key == nil then
        ok, value = pcall(callback, object)
    else
        ok, value = pcall(callback, object, key)
    end
    if not ok or not IsExplicitlySafe(value) then return nil, false end
    return value, true
end

local function ReadSafeBoolean(callback, argument)
    if type(callback) ~= "function" then return false, true end
    local ok, value
    if argument == nil then
        ok, value = pcall(callback)
    else
        ok, value = pcall(callback, argument)
    end
    if not ok or not IsExplicitlySafe(value) or type(value) ~= "boolean" then
        return nil, false
    end
    return value, true
end

local function ReadSafeEditBox(editBox)
    if not IsExplicitlySafe(editBox)
        or (type(editBox) ~= "table" and type(editBox) ~= "userdata")
        or type(editBox.GetText) ~= "function"
        or type(editBox.GetAttribute) ~= "function"
    then
        return false
    end

    local text, textSafe = ReadSafeMethod(editBox, editBox.GetText)
    if not textSafe or type(text) ~= "string" or sub(text, 1, 1) == "/" then
        return false
    end

    local chatType, typeSafe = ReadSafeMethod(editBox, editBox.GetAttribute, "chatType")
    if not typeSafe or type(chatType) ~= "string" or chatType == "" then
        return false
    end

    local channelTarget, channelSafe = ReadSafeMethod(
        editBox,
        editBox.GetAttribute,
        "channelTarget"
    )
    if not channelSafe then return false end

    local tellTarget, tellSafe = ReadSafeMethod(
        editBox,
        editBox.GetAttribute,
        "tellTarget"
    )
    if not tellSafe then return false end

    return true, chatType, channelTarget, tellTarget
end

local function ReadArrowMode(editBox)
    local value, safe = ReadSafeMethod(editBox, editBox.GetAltArrowKeyMode)
    if not safe or type(value) ~= "boolean" then
        return nil, "arrow-mode-read-failed"
    end
    return value
end

local function CanWriteArrowMode(editBox, restoring)
    if not restoring then
        local restrictionOK, restriction = pcall(Adapter.GetRestrictionState, Adapter)
        if not restrictionOK or not IsExplicitlySafe(restriction)
            or (restriction ~= "OPEN" and restriction ~= "PAUSED")
        then
            return false, "arrow-mode-restriction-unavailable"
        end
    end
    local protectedOK, allowed = pcall(Adapter.CanCallProtected, Adapter, editBox)
    if not protectedOK or allowed ~= true then
        return false, "arrow-mode-protected-denied"
    end
    return true
end

local function WriteArrowMode(editBox, value)
    if type(editBox.SetAltArrowKeyMode) ~= "function"
        or not pcall(editBox.SetAltArrowKeyMode, editBox, value)
    then
        return false, "arrow-mode-write-failed"
    end
    local applied, reason = ReadArrowMode(editBox)
    if applied ~= value then
        return false, reason or "arrow-mode-readback-failed"
    end
    return true
end

local RefreshArrowModeStats

local function ArrowModeChanged(editBox)
    if not ChannelInput.enabled or ChannelInput.restorePending == true then return end
    local frame = arrowFrameByEditBox[editBox]
    local state = frame and arrowStateByFrame[frame]
    if not state or state.editBox ~= editBox then return end
    local current, readReason = ReadArrowMode(editBox)
    if current ~= true then
        if current == nil then
            arrowModeLastFailure = readReason
            RefreshArrowModeStats()
        end
        return
    end
    local allowed, reason = CanWriteArrowMode(editBox, false)
    if not allowed then
        arrowModeLastFailure = reason
        RefreshArrowModeStats()
        return
    end
    local applied, applyReason = WriteArrowMode(editBox, false)
    if not applied then
        arrowModeLastFailure = applyReason
        RefreshArrowModeStats()
        return
    end
    state.applied = true
    arrowModeLastFailure = "none"
    RefreshArrowModeStats()
end

local function InstallArrowModeHook(frame, editBox)
    if arrowModeHooked[editBox] ~= true then
        if type(hooksecurefunc) ~= "function"
            or not pcall(hooksecurefunc, editBox, "SetAltArrowKeyMode", ArrowModeChanged)
        then
            return false, "arrow-mode-hook-failed"
        end
        arrowModeHooked[editBox] = true
    end
    arrowFrameByEditBox[editBox] = frame
    return true
end

RefreshArrowModeStats = function(target)
    local managed = 0
    local pending = 0
    for _, state in pairs(arrowStateByFrame) do
        if state.applied == true then managed = managed + 1 end
        if state.restorePending == true then pending = pending + 1 end
    end
    if target then
        target.arrowModeManagedEditBoxes = managed
        target.arrowModePendingRestores = pending
        target.arrowModeLastFailure = arrowModeLastFailure
    end
    StatSet("arrowModeManagedEditBoxes", managed)
    StatSet("arrowModePendingRestores", pending)
    StatSet("arrowModeLastFailure", arrowModeLastFailure)
    return managed, pending
end

local EXCLUDED_HISTORY_COMMANDS = {
    ["/outfit"] = true,
    ["/m"] = true,
    ["/macro"] = true,
}

local function NormalizeInputLine(line)
    if not IsExplicitlySafe(line) or type(line) ~= "string" then return nil end
    local ok, message = pcall(strtrim, line)
    if not ok or not IsExplicitlySafe(message) or type(message) ~= "string"
        or message == "" or #message > 4096 or find(message, "|K", 1, true)
    then
        return nil
    end
    local command = match(message, "^/%w+")
    if command then
        command = lower(command)
        if EXCLUDED_HISTORY_COMMANDS[command] or type(IsSecureCmd) ~= "function" then return nil end
        local secureOK, secure = pcall(IsSecureCmd, command)
        if not secureOK or not IsExplicitlySafe(secure) or secure == true then return nil end
    end
    return message
end

local function InputHistoryTime()
    local getter = System and System.GetServerTime
    if type(getter) ~= "function" then return nil end
    local ok, epoch = pcall(getter)
    if not ok or not IsExplicitlySafe(epoch) or type(epoch) ~= "number"
        or epoch <= 0 or epoch >= math.huge or epoch ~= floor(epoch)
    then
        return nil
    end
    return epoch
end

local function IsInputWindowKey(key)
    if type(key) ~= "string" then return false end
    local id = tonumber(match(key, "^ChatFrame(%d+)$"))
    return id ~= nil and id >= 1 and id <= 10 and id ~= 2
end

-- 仅在生命周期冷路径校验磁盘内容；发送时只压缩最多 32 个已校验记录。
local function PruneInputWindow(records, now, validate)
    local kept = 0
    for index = 1, INPUT_HISTORY_LIMIT do
        local entry = records[index]
        local epoch = type(entry) == "table" and entry.epoch
        if now and IsExplicitlySafe(epoch) and type(epoch) == "number"
            and epoch > 0 and epoch <= now and now - epoch <= INPUT_HISTORY_TTL
            and epoch == floor(epoch)
        then
            local text = entry.text
            if validate then text = NormalizeInputLine(text) end
            if type(text) == "string" then
                entry.text = text
                kept = kept + 1
                records[kept] = entry
            end
        end
    end
    for key in pairs(records) do
        if type(key) ~= "number" or key < 1 or key > kept or key ~= floor(key) then
            records[key] = nil
        end
    end
    return kept
end

function ChannelInput:PruneSavedInputHistory()
    local root = inputHistoryGlobal and inputHistoryGlobal.inputHistoryByCharacter
    if type(root) ~= "table" then return end
    local now = InputHistoryTime()
    for characterKey, windows in pairs(root) do
        if type(characterKey) ~= "string" or type(windows) ~= "table" then
            root[characterKey] = nil
        else
            for windowKey, records in pairs(windows) do
                if not IsInputWindowKey(windowKey) or type(records) ~= "table"
                    or PruneInputWindow(records, now, true) == 0
                then
                    windows[windowKey] = nil
                end
            end
            if next(windows) == nil then root[characterKey] = nil end
        end
    end
end

function ChannelInput:InitializeInputHistory()
    if not inputHistoryGlobal then
        local db = YUI.DB
        if not db or type(db.GetGlobal) ~= "function"
            or (type(db.IsReady) == "function" and db:IsReady() ~= true)
        then
            return false, "input-history-db-unavailable"
        end
        local ok, global = pcall(db.GetGlobal, db, YChat.PRODUCT_ID)
        if not ok or type(global) ~= "table" then return false, "input-history-db-unavailable" end
        inputHistoryGlobal = global
        if type(global.inputHistoryByCharacter) ~= "table" then global.inputHistoryByCharacter = {} end
        self:PruneSavedInputHistory()
    end
    if not inputHistoryCharacterKey then
        local history = YChat.HistoryRuntime
        local key = history and type(history.GetCharacterKey) == "function" and history:GetCharacterKey()
        if IsExplicitlySafe(key) and type(key) == "string" and key ~= "" then
            inputHistoryCharacterKey = key
        end
    end
    return inputHistoryCharacterKey ~= nil
end

local function SavedInputWindow(state, create)
    if not inputHistoryGlobal or not inputHistoryCharacterKey or not state.windowKey then return nil end
    local root = inputHistoryGlobal.inputHistoryByCharacter
    local windows = root[inputHistoryCharacterKey]
    if not windows and create then windows = {}; root[inputHistoryCharacterKey] = windows end
    if not windows then return nil end
    local records = windows[state.windowKey]
    if not records and create then records = {}; windows[state.windowKey] = records end
    return records
end

local function SaveInputLine(state, message)
    local now = InputHistoryTime()
    if not now then return end
    local records = SavedInputWindow(state, true)
    if not records then return end
    local count = PruneInputWindow(records, now, false)
    if count > 0 and records[count].text == message then
        records[count].epoch = now
        return
    end
    local entry
    if count == INPUT_HISTORY_LIMIT then
        entry = records[1]
        for index = 1, count - 1 do records[index] = records[index + 1] end
    else
        count = count + 1
        entry = {}
    end
    entry.text, entry.epoch = message, now
    records[count] = entry
end

function ChannelInput:ClearInputHistory(allCharacters)
    self:InitializeInputHistory()
    if not inputHistoryGlobal then return false, "input-history-db-unavailable" end
    local root = inputHistoryGlobal.inputHistoryByCharacter
    if allCharacters then
        for key in pairs(root) do root[key] = nil end
    elseif inputHistoryCharacterKey then
        root[inputHistoryCharacterKey] = nil
    else
        return false, "input-history-character-unavailable"
    end
    for _, state in pairs(inputHistoryByFrame) do
        for key in pairs(state.lines) do state.lines[key] = nil end
        state.head, state.count, state.index = 1, 0, 0
    end
    return true
end

local function ResolveInputHistory(editBox)
    local frame = inputFrameByEditBox[editBox]
    local state = frame and inputHistoryByFrame[frame]
    if not state or state.editBox ~= editBox then return nil end
    return state
end

local function InputHistoryLineAdded(editBox, line)
    if not ChannelInput.enabled or ChannelInput.restorePending == true
        or not IsExplicitlySafe(line) or type(line) ~= "string"
    then
        return
    end
    local state = ResolveInputHistory(editBox)
    if not state then return end
    local message = NormalizeInputLine(line)
    if not message then return end
    SaveInputLine(state, message)

    local count = state.count
    if count > 0 then
        local lastSlot = ((state.head + count - 2) % INPUT_HISTORY_LIMIT) + 1
        if state.lines[lastSlot] == message then
            state.index = 0
            return
        end
    end
    if count < INPUT_HISTORY_LIMIT then
        local slot = ((state.head + count - 1) % INPUT_HISTORY_LIMIT) + 1
        state.lines[slot] = message
        state.count = count + 1
    else
        state.lines[state.head] = message
        state.head = (state.head % INPUT_HISTORY_LIMIT) + 1
    end
    state.index = 0
end

local function InputHistoryKeyDown(editBox, key)
    if not ChannelInput.enabled or ChannelInput.restorePending == true
        or not IsExplicitlySafe(key) or (key ~= "UP" and key ~= "DOWN")
    then
        return
    end
    local altDown, altSafe = ReadSafeBoolean(IsAltKeyDown)
    if not altSafe or altDown then return end
    local restrictionOK, restriction = pcall(Adapter.GetRestrictionState, Adapter)
    if not restrictionOK or not IsExplicitlySafe(restriction) or restriction ~= "OPEN" then
        return
    end
    local allowed = CanWriteArrowMode(editBox, false)
    if not allowed then return end
    local state = ResolveInputHistory(editBox)
    local count = state and state.count or 0
    if count == 0 or type(editBox.SetText) ~= "function" then return end

    if key == "UP" then
        if state.index < count then state.index = state.index + 1 end
    else
        state.index = state.index - 1
        if state.index < 1 then state.index = 0 end
    end
    local logicalIndex = count - state.index + 1
    local slot = ((state.head + logicalIndex - 2) % INPUT_HISTORY_LIMIT) + 1
    local text = state.index == 0 and "" or state.lines[slot]
    if not IsExplicitlySafe(text) or type(text) ~= "string"
        or not pcall(editBox.SetText, editBox, text)
    then
        arrowModeLastFailure = "input-history-write-failed"
        RefreshArrowModeStats()
    end
end

local function InputHistoryFocusLost(editBox)
    local state = ResolveInputHistory(editBox)
    if state then state.index = 0 end
end

local function InstallInputHistoryHooks(frame, editBox)
    local hooks = inputHistoryHooks[editBox]
    if not hooks then
        hooks = {}
        inputHistoryHooks[editBox] = hooks
    end
    if hooks.addHistory ~= true then
        if type(editBox.AddHistoryLine) ~= "function"
            or type(hooksecurefunc) ~= "function"
            or not pcall(hooksecurefunc, editBox, "AddHistoryLine", InputHistoryLineAdded)
        then
            return false, "input-history-add-hook-failed"
        end
        hooks.addHistory = true
    end
    if hooks.keyDown ~= true then
        if type(editBox.HookScript) ~= "function"
            or not pcall(editBox.HookScript, editBox, "OnKeyDown", InputHistoryKeyDown)
        then
            return false, "input-history-key-hook-failed"
        end
        hooks.keyDown = true
    end
    if hooks.focusLost ~= true then
        if not pcall(editBox.HookScript, editBox, "OnEditFocusLost", InputHistoryFocusLost) then
            return false, "input-history-focus-hook-failed"
        end
        hooks.focusLost = true
    end
    local state = inputHistoryByFrame[frame]
    if not state then
        state = { lines = {}, head = 1, count = 0, index = 0 }
        inputHistoryByFrame[frame] = state
    end
    if not state.loaded and ChannelInput:InitializeInputHistory() then
        local name, safe = ReadSafeMethod(frame, frame.GetName)
        state.windowKey = safe and IsInputWindowKey(name) and name or nil
        local records = SavedInputWindow(state, false)
        local count = records and PruneInputWindow(records, InputHistoryTime(), true) or 0
        -- 初始化可能晚于首条在线输入，已有会话内容优先，不回灌覆盖。
        if state.count == 0 then
            for index = 1, count do state.lines[index] = records[index].text end
            state.count = count
        end
        state.loaded = true
    end
    state.editBox = editBox
    inputFrameByEditBox[editBox] = frame
    return true
end

local function RestoreArrowState(frame, state)
    if not state then return true end
    local editBox = state.editBox
    if arrowFrameByEditBox[editBox] == frame then arrowFrameByEditBox[editBox] = nil end
    if inputFrameByEditBox[editBox] == frame then inputFrameByEditBox[editBox] = nil end
    local allowed, reason = CanWriteArrowMode(editBox, true)
    if not allowed then
        state.restorePending = true
        arrowModeLastFailure = reason
        RefreshArrowModeStats()
        return false, reason
    end
    local current, readReason = ReadArrowMode(editBox)
    if current == nil then
        state.restorePending = true
        arrowModeLastFailure = readReason
        RefreshArrowModeStats()
        return false, readReason
    end
    if current ~= state.originalMode and current == false then
        local restored, restoreReason = WriteArrowMode(editBox, state.originalMode)
        if not restored then
            state.restorePending = true
            arrowModeLastFailure = restoreReason
            RefreshArrowModeStats()
            return false, restoreReason
        end
    end
    state.restorePending = false
    state.applied = false
    if arrowStateByFrame[frame] == state then arrowStateByFrame[frame] = nil end
    RefreshArrowModeStats()
    return true
end

local function ReconcileArrowFrame(frame)
    if not ChannelInput.enabled then return true end
    local targetsOK, targets, targetReason = pcall(Adapter.GetAppearanceTargets, Adapter, frame)
    local editBox = targetsOK and type(targets) == "table" and targets.editBox or nil
    if not editBox
        or type(editBox.GetAltArrowKeyMode) ~= "function"
        or type(editBox.SetAltArrowKeyMode) ~= "function"
    then
        local reason = targetReason or "arrow-mode-editbox-unavailable"
        arrowScanFailed = true
        arrowModeLastFailure = reason
        RefreshArrowModeStats()
        return false, reason
    end
    local allowed, reason = CanWriteArrowMode(editBox, false)
    if not allowed then
        arrowScanFailed = true
        arrowModeLastFailure = reason
        RefreshArrowModeStats()
        return false, reason
    end

    local state = arrowStateByFrame[frame]
    if state and state.editBox ~= editBox then
        local restored, restoreReason = RestoreArrowState(frame, state)
        if not restored then
            arrowScanFailed = true
            return false, restoreReason
        end
        state = nil
    end
    if not state then
        local originalMode, readReason = ReadArrowMode(editBox)
        if originalMode == nil then
            arrowScanFailed = true
            arrowModeLastFailure = readReason
            RefreshArrowModeStats()
            return false, readReason
        end
        state = {
            editBox = editBox,
            originalMode = originalMode,
            applied = false,
            restorePending = false,
            seenGeneration = arrowScanGeneration,
        }
        arrowStateByFrame[frame] = state
    else
        state.seenGeneration = arrowScanGeneration
    end

    local hookOK, hookReason = InstallArrowModeHook(frame, editBox)
    if not hookOK then
        arrowScanFailed = true
        arrowModeLastFailure = hookReason
        RefreshArrowModeStats()
        return false, hookReason
    end
    local historyOK, historyReason = InstallInputHistoryHooks(frame, editBox)
    if not historyOK then
        arrowScanFailed = true
        arrowModeLastFailure = historyReason
        RefreshArrowModeStats()
        return false, historyReason
    end
    local current, readReason = ReadArrowMode(editBox)
    if current == nil then
        arrowScanFailed = true
        arrowModeLastFailure = readReason
        RefreshArrowModeStats()
        return false, readReason
    end
    if current ~= false then
        local applied, applyReason = WriteArrowMode(editBox, false)
        if not applied then
            arrowScanFailed = true
            arrowModeLastFailure = applyReason
            RefreshArrowModeStats()
            return false, applyReason
        end
    end
    state.applied = true
    state.restorePending = false
    RefreshArrowModeStats()
    return true
end

local function ReconcileAllArrowModes()
    if not ChannelInput.enabled then return true end
    local restrictionOK, restriction = pcall(Adapter.GetRestrictionState, Adapter)
    if not restrictionOK or not IsExplicitlySafe(restriction)
        or (restriction ~= "OPEN" and restriction ~= "PAUSED")
    then
        arrowModeLastFailure = "arrow-mode-restriction-unavailable"
        RefreshArrowModeStats()
        return true
    end

    arrowScanGeneration = arrowScanGeneration + 1
    local generation = arrowScanGeneration
    arrowScanFailed = false
    Adapter:ForEachSupportedFrame(ReconcileArrowFrame)
    local allRestored = true
    for frame, state in pairs(arrowStateByFrame) do
        if state.seenGeneration ~= generation then
            local restored = RestoreArrowState(frame, state)
            if not restored then allRestored = false end
        end
    end
    if allRestored and not arrowScanFailed then arrowModeLastFailure = "none" end
    RefreshArrowModeStats()
    return allRestored and not arrowScanFailed
end

local function RestoreAllArrowModes()
    local restored = true
    local reason
    for frame, state in pairs(arrowStateByFrame) do
        local stateRestored, stateReason = RestoreArrowState(frame, state)
        if not stateRestored then
            restored = false
            reason = reason or stateReason
        end
    end
    if restored then arrowModeLastFailure = "none" end
    RefreshArrowModeStats()
    return restored, reason
end

local function RetryPendingRestores()
    if ChannelInput.restorePending ~= true then return true end
    local arrowsRestored, arrowReason = RestoreAllArrowModes()
    local senderRestored, senderReason = UpdateSenderFilter(false)
    ChannelInput.restorePending = arrowsRestored ~= true or senderRestored ~= true
    if ChannelInput.restorePending then
        return false, arrowReason or senderReason
    end
    if YChat.lifecycleDisablePending
        and type(YChat.OnChannelInputRestoreConfirmed) == "function"
    then
        local confirmationOK, confirmed, confirmationReason =
            pcall(YChat.OnChannelInputRestoreConfirmed, YChat)
        if not confirmationOK then
            arrowModeLastFailure = "arrow-mode-restore-confirmation-failed"
            RefreshArrowModeStats()
            return false, arrowModeLastFailure
        end
        return confirmed ~= false, confirmationReason
    end
    return true
end

local function InstallFormatting()
    if installedFormatting then return true end
    local util = _G.ChatFrameUtil
    local addFilter = type(util) == "table" and util.AddMessageEventFilter or nil
    local removeFilter = type(util) == "table" and util.RemoveMessageEventFilter or nil
    if type(addFilter) ~= "function" or type(removeFilter) ~= "function" then
        return false, "channel-filter-api-unavailable"
    end
    local callbackOK, callbackReason = Adapter:SetChannelDeferredCallback(
        DrainChannelTransforms
    )
    if not callbackOK then return false, callbackReason end
    local transformOK, transformReason = Adapter:SetChannelTransformCallback(
        OnExternalTransform
    )
    if not transformOK then
        Adapter:SetChannelDeferredCallback(nil)
        return false, transformReason
    end
    for index = 1, #FILTER_EVENTS do
        local event = FILTER_EVENTS[index]
        if not pcall(addFilter, event, ChannelMessageFilter) then
            for installedIndex = #installedFilterEvents, 1, -1 do
                pcall(removeFilter, installedFilterEvents[installedIndex], ChannelMessageFilter)
                installedFilterEvents[installedIndex] = nil
            end
            Adapter:SetChannelTransformCallback(nil)
            Adapter:SetChannelDeferredCallback(nil)
            return false, "channel-filter-install-failed"
        end
        installedFilterEvents[#installedFilterEvents + 1] = event
    end
    installedFormatting = true
    StatSet("channelFilterInstalled", true)
    StatSet("channelFormatWrappersInstalled", false)
    return true
end

local function RemoveFormatting()
    Adapter:SetChannelDeferredDriverEnabled(false)
    ResetTransformState()
    Adapter:SetChannelTransformCallback(nil)
    Adapter:SetChannelDeferredCallback(nil)
    if not installedFormatting then return true end
    local util = _G.ChatFrameUtil
    local removeFilter = type(util) == "table" and util.RemoveMessageEventFilter or nil
    local removed = type(removeFilter) == "function"
    if removed then
        for index = #installedFilterEvents, 1, -1 do
            if not pcall(removeFilter, installedFilterEvents[index], ChannelMessageFilter) then
                removed = false
            end
            installedFilterEvents[index] = nil
        end
    end
    installedFormatting = false
    StatSet("channelFilterInstalled", false)
    StatSet("channelFormatWrappersInstalled", false)
    if not removed then return false, "channel-filter-remove-failed" end
    return true
end

local function InstallTab()
    if not ChatInput then return false, "chat-input-api-unavailable" end
    if not installedTab then
        local registered, reason = ChatInput.RegisterTabOwner("ychat", 200)
        if not registered then return false, reason end
        installedTab = true
    end
    local config = YChat:GetChannelInput()
    local updated, reason = ChatInput.SetTabOwnerState("ychat", {
        claimed = true,
        enabled = config and config.tabCycle == true,
    })
    if not updated then
        ChatInput.UnregisterTabOwner("ychat")
        installedTab = false
        return false, reason
    end
    StatSet("tabHookInstalled", true)
    return true
end

local function RemoveTab()
    if not installedTab then return true end
    local removed, reason = ChatInput.UnregisterTabOwner("ychat")
    if not removed and reason ~= "unknown_owner" then return false, reason end
    installedTab = false
    StatSet("tabHookInstalled", false)
    return true
end

function ChannelInput:SetEnabled(enabled)
    enabled = enabled == true
    if enabled then
        if self.restorePending == true then
            return false, "channel-input-restore-pending"
        end
        self.enabled = true
        ChatInput.ResetSuspendedEditBoxes()
        local formatOK, formatReason = InstallFormatting()
        if not formatOK then
            self.enabled = false
            return false, formatReason
        end
        local tabOK, tabReason = InstallTab()
        if not tabOK then
            RemoveFormatting()
            self.enabled = false
            return false, tabReason
        end
        local cacheOK, cacheReason = self:RefreshCache()
        local config = YChat:GetChannelInput()
        local senderOK, senderReason = UpdateSenderFilter(config and config.hidePlayerRealm == true or false)
        if not senderOK then return false, senderReason end
        Adapter:ForEachSupportedFrame(PrimeTransformFrame)
        StatSet("channelTransformLastFailure", "none")
        ReconcileAllArrowModes()
        return cacheOK, cacheReason
    end
    self:PruneSavedInputHistory()
    self.enabled = false
    local senderOK, senderReason = UpdateSenderFilter(false)
    local formatOK, formatReason = RemoveFormatting()
    local tabOK, tabReason = RemoveTab()
    local arrowOK, arrowReason = RestoreAllArrowModes()
    self.restorePending = arrowOK ~= true or senderOK ~= true
    inputFrameByEditBox = setmetatable({}, { __mode = "k" })
    inputHistoryByFrame = setmetatable({}, { __mode = "k" })
    if ChatInput then ChatInput.ResetSuspendedEditBoxes() end
    publicById = {}
    publicFormattingEnabled = false
    activePublicFormat = "native"
    StatSet("channelCacheEntries", 0)
    if not formatOK then return false, formatReason end
    if not senderOK then return false, senderReason end
    if not tabOK then return false, tabReason end
    if not arrowOK then return false, arrowReason end
    return true
end

function ChannelInput:OnChannelsChanged()
    local refreshed, reason = self:RefreshCache()
    if publicFormattingEnabled ~= true then ClearTransformQueue() end
    return refreshed, reason
end

function ChannelInput:OnFrameDiscovered(frame, valid)
    if self.restorePending == true then return RetryPendingRestores() end
    if not self.enabled then return true end
    if ChatInput then ChatInput.ResetSuspendedEditBoxes() end
    if valid == true then
        PrimeTransformFrame(frame)
        return ReconcileArrowFrame(frame)
    end
    return RestoreArrowState(frame, arrowStateByFrame[frame])
end

function ChannelInput:OnWindowsChanged()
    if self.restorePending == true then return RetryPendingRestores() end
    if ChatInput then ChatInput.ResetSuspendedEditBoxes() end
    return ReconcileAllArrowModes()
end

function ChannelInput:OnRestrictionStateChanged(state)
    if state ~= "OPEN" then ClearTransformQueue() end
    if self.restorePending == true then
        if state == "OPEN" then return RetryPendingRestores() end
        return true
    end
    if not self.enabled then return true end
    if state ~= "OPEN" and state ~= "PAUSED" then return true end
    return ReconcileAllArrowModes()
end

function ChannelInput:GetRuntimeGauges(target)
    target = target or {}
    target.channelFilterInstalled = installedFormatting
    target.playerRealmSenderFilterInstalled = installedSenderFilter
    target.channelFormatWrappersInstalled = false
    target.channelTransformQueueDepth = queuedCount
    target.channelTransformDirtyFrames = dirtyFrameCount
    target.channelLinkTakeoverReady = false
    target.tabHookInstalled = installedTab
    RefreshArrowModeStats(target)
    return target
end

local YUI = _G.YUI
local YChat = YUI and YUI.YChat
if not YChat or (YUI.IsForever or YUI.IsRetail) ~= true then return end

local Adapter = YChat.Adapter
local Security = YUI.API and YUI.API.Security
local SafeMessage = {}
YChat.SafeMessage = SafeMessage

local ChatFrameUtil = _G.ChatFrameUtil
local pcall = pcall
local type = type
local concat = table.concat
local select = select

local QUEUE_CAPACITY = 64
local DRAIN_PER_FRAME = 16
local DEDUPE_CAPACITY = 128

local HISTORY_EVENTS = {
    CHAT_MSG_SAY = true,
    CHAT_MSG_YELL = true,
    CHAT_MSG_EMOTE = true,
    CHAT_MSG_TEXT_EMOTE = true,
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_INSTANCE_CHAT = true,
    CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_GUILD = true,
    CHAT_MSG_OFFICER = true,
    CHAT_MSG_CHANNEL = true,
    CHAT_MSG_COMMUNITIES_CHANNEL = true,
    CHAT_MSG_WHISPER = true,
    CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER = true,
    CHAT_MSG_BN_WHISPER_INFORM = true,
    CHAT_MSG_SYSTEM = true,
    CHAT_MSG_LOOT = true,
    CHAT_MSG_CURRENCY = true,
    CHAT_MSG_MONEY = true,
    CHAT_MSG_ACHIEVEMENT = true,
    CHAT_MSG_GUILD_ACHIEVEMENT = true,
}

local FILTER_EVENTS = {
    "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER",
    "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_SAY",
    "CHAT_MSG_YELL",
    "CHAT_MSG_EMOTE",
    "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER",
    "CHAT_MSG_CHANNEL",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
    "CHAT_MSG_SYSTEM",
    "CHAT_MSG_LOOT",
    "CHAT_MSG_CURRENCY",
    "CHAT_MSG_MONEY",
    "CHAT_MSG_ACHIEVEMENT",
    "CHAT_MSG_GUILD_ACHIEVEMENT",
}

local queue = {}
for index = 1, QUEUE_CAPACITY do queue[index] = {} end
local queueHead = 1
local queueTail = 1
local queueCount = 0

local dedupeIDs = {}
local dedupeMap = {}
local dedupeCursor = 1
local installedEvents = {}
local autoInterest = false
local historyInterest = false
local yuiPrintCaptureInstalled = false
local printParts = {}

SafeMessage.enabled = false
SafeMessage.lastReason = "not-started"
SafeMessage.filterCalls = 0
SafeMessage.filterBypasses = 0
SafeMessage.queueDrops = 0
SafeMessage.drainedMessages = 0

local function StatIncrement(field)
    local stats = YChat.Stats
    if stats and stats.Increment then stats:Increment(field) end
end

local function IsSecret(value)
    if not Security or type(Security.IsSecretValue) ~= "function" then return true end
    return Security.IsSecretValue(value) == true
end

local function IsSafeOptionalScalar(value)
    if value == nil then return true end
    if IsSecret(value) then return false end
    local valueType = type(value)
    return valueType == "string" or valueType == "number" or valueType == "boolean"
end

local function RememberLineID(lineID)
    if dedupeMap[lineID] then return false end
    local previous = dedupeIDs[dedupeCursor]
    if previous ~= nil then dedupeMap[previous] = nil end
    dedupeIDs[dedupeCursor] = lineID
    dedupeMap[lineID] = true
    dedupeCursor = dedupeCursor < DEDUPE_CAPACITY and dedupeCursor + 1 or 1
    return true
end

local function QueueMessage(
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
    lineID,
    guid,
    bnSenderID,
    bnDisplayName,
    allowAutomation
)
    if queueCount >= QUEUE_CAPACITY then
        SafeMessage.queueDrops = SafeMessage.queueDrops + 1
        StatIncrement("safeMessageQueueDrops")
        return false
    end
    local slot = queue[queueTail]
    slot.event = event
    slot.text = text
    slot.sender = sender
    slot.languageName = languageName
    slot.channelName = channelName
    slot.playerName2 = playerName2
    slot.specialFlags = specialFlags
    slot.zoneChannelID = zoneChannelID
    slot.channelIndex = channelIndex
    slot.channelBaseName = channelBaseName
    slot.lineID = lineID
    slot.guid = guid
    slot.bnSenderID = bnSenderID
    slot.bnDisplayName = bnDisplayName
    slot.allowAutomation = allowAutomation == true
    queueTail = queueTail < QUEUE_CAPACITY and queueTail + 1 or 1
    queueCount = queueCount + 1
    local scheduled = Adapter:SetMessageDeferredDriverEnabled(true)
    if not scheduled then
        queueTail = queueTail > 1 and queueTail - 1 or QUEUE_CAPACITY
        queueCount = queueCount - 1
        slot.event = nil
        slot.text = nil
        slot.sender = nil
        slot.languageName = nil
        slot.channelName = nil
        slot.playerName2 = nil
        slot.specialFlags = nil
        slot.zoneChannelID = nil
        slot.channelIndex = nil
        slot.channelBaseName = nil
        slot.lineID = nil
        slot.guid = nil
        slot.bnSenderID = nil
        slot.bnDisplayName = nil
        slot.allowAutomation = nil
        SafeMessage.queueDrops = SafeMessage.queueDrops + 1
        StatIncrement("safeMessageQueueDrops")
        return false
    end
    return true
end

local function SafeMessageFilter(
    chatFrame,
    event,
    arg1,
    arg2,
    arg3,
    arg4,
    arg5,
    arg6,
    arg7,
    arg8,
    arg9,
    arg10,
    arg11,
    arg12,
    arg13,
    arg14
)
    SafeMessage.filterCalls = SafeMessage.filterCalls + 1
    StatIncrement("safeMessageFilterCalls")
    local history = YChat.HistoryRuntime
    local historyWanted = historyInterest and HISTORY_EVENTS[event] == true
        and history and history.WantsEvent
        and history:WantsEvent(event)
    local automationWanted = autoInterest
        and (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER")
    local restriction = Adapter:GetRestrictionState()
    local allowHistory = historyWanted
        and (restriction == "OPEN" or restriction == "PAUSED")
    local allowAutomation = automationWanted and restriction == "OPEN"
    if not SafeMessage.enabled or (not allowHistory and not allowAutomation)
        or IsSecret(arg1)
        or IsSecret(arg2)
        or IsSecret(arg6)
        or IsSecret(arg11)
        or IsSecret(arg12)
        or IsSecret(arg13)
        or not IsSafeOptionalScalar(arg3)
        or not IsSafeOptionalScalar(arg4)
        or not IsSafeOptionalScalar(arg5)
        or not IsSafeOptionalScalar(arg7)
        or not IsSafeOptionalScalar(arg8)
        or not IsSafeOptionalScalar(arg9)
        or not IsSafeOptionalScalar(arg14)
        or type(arg1) ~= "string"
        or type(arg2) ~= "string"
        or type(arg11) ~= "number"
        or arg11 <= 0
    then
        SafeMessage.filterBypasses = SafeMessage.filterBypasses + 1
        StatIncrement("safeMessageFilterBypasses")
        return false
    end
    if not RememberLineID(arg11) then
        SafeMessage.filterBypasses = SafeMessage.filterBypasses + 1
        StatIncrement("safeMessageDuplicateBypasses")
        return false
    end
    QueueMessage(
        event,
        arg1,
        arg2,
        arg3,
        arg4,
        arg5,
        arg6,
        arg7,
        arg8,
        arg9,
        arg11,
        arg12,
        arg13,
        (event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM")
            and arg2 or nil,
        allowAutomation
    )
    return false
end

local function ClearQueue()
    for index = 1, QUEUE_CAPACITY do
        local slot = queue[index]
        slot.event = nil
        slot.text = nil
        slot.sender = nil
        slot.languageName = nil
        slot.channelName = nil
        slot.playerName2 = nil
        slot.specialFlags = nil
        slot.zoneChannelID = nil
        slot.channelIndex = nil
        slot.channelBaseName = nil
        slot.lineID = nil
        slot.guid = nil
        slot.bnSenderID = nil
        slot.bnDisplayName = nil
        slot.allowAutomation = nil
    end
    queueHead = 1
    queueTail = 1
    queueCount = 0
end

local function ClearDedupe()
    for index = 1, DEDUPE_CAPACITY do
        local lineID = dedupeIDs[index]
        if lineID ~= nil then dedupeMap[lineID] = nil end
        dedupeIDs[index] = nil
    end
    dedupeCursor = 1
end

local function DeferredStep()
    local processed = 0
    while queueCount > 0 and processed < DRAIN_PER_FRAME do
        local slot = queue[queueHead]
        local event = slot.event
        local text = slot.text
        local sender = slot.sender
        local languageName = slot.languageName
        local channelName = slot.channelName
        local playerName2 = slot.playerName2
        local specialFlags = slot.specialFlags
        local zoneChannelID = slot.zoneChannelID
        local channelIndex = slot.channelIndex
        local channelBaseName = slot.channelBaseName
        local guid = slot.guid
        local bnSenderID = slot.bnSenderID
        local bnDisplayName = slot.bnDisplayName
        local allowAutomation = slot.allowAutomation

        slot.event = nil
        slot.text = nil
        slot.sender = nil
        slot.languageName = nil
        slot.channelName = nil
        slot.playerName2 = nil
        slot.specialFlags = nil
        slot.zoneChannelID = nil
        slot.channelIndex = nil
        slot.channelBaseName = nil
        slot.lineID = nil
        slot.guid = nil
        slot.bnSenderID = nil
        slot.bnDisplayName = nil
        slot.allowAutomation = nil
        queueHead = queueHead < QUEUE_CAPACITY and queueHead + 1 or 1
        queueCount = queueCount - 1
        processed = processed + 1

        if historyInterest and HISTORY_EVENTS[event] == true then
            local history = YChat.HistoryRuntime
            if history and type(history.ProcessMessage) == "function"
                and history:WantsEvent(event)
            then
                pcall(
                    history.ProcessMessage,
                    history,
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
                    guid,
                    bnSenderID,
                    bnDisplayName
                )
            end
        end
        if allowAutomation
            and (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER")
        then
            local autoInvite = YChat.AutoInvite
            if autoInvite and type(autoInvite.ProcessMessage) == "function" then
                pcall(
                    autoInvite.ProcessMessage,
                    autoInvite,
                    event,
                    text,
                    sender,
                    specialFlags,
                    guid,
                    bnSenderID
                )
            end
        end
    end
    SafeMessage.drainedMessages = SafeMessage.drainedMessages + processed
    if processed > 0 then StatIncrement("safeMessageDrainFrames") end
    if queueCount == 0 then Adapter:SetMessageDeferredDriverEnabled(false) end
end

local function WantsEvent(event)
    local history = YChat.HistoryRuntime
    return autoInterest
        and (event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER")
        or historyInterest and HISTORY_EVENTS[event] == true
            and history and type(history.WantsEvent) == "function"
            and history:WantsEvent(event)
end

local function ReconcileFilters()
    ChatFrameUtil = _G.ChatFrameUtil
    local anyWanted = false
    for index = 1, #FILTER_EVENTS do
        if WantsEvent(FILTER_EVENTS[index]) then
            anyWanted = true
            break
        end
    end
    if not anyWanted then
        local anyInstalled = false
        for index = 1, #FILTER_EVENTS do
            if installedEvents[FILTER_EVENTS[index]] then
                anyInstalled = true
                break
            end
        end
        if not anyInstalled then return true end
    end
    if type(ChatFrameUtil) ~= "table"
        or type(ChatFrameUtil.AddMessageEventFilter) ~= "function"
        or type(ChatFrameUtil.RemoveMessageEventFilter) ~= "function"
    then
        return false, "safe-message-filter-api-unavailable"
    end
    for index = 1, #FILTER_EVENTS do
        local event = FILTER_EVENTS[index]
        local wanted = WantsEvent(event)
        if wanted and not installedEvents[event] then
            local ok = pcall(
                ChatFrameUtil.AddMessageEventFilter,
                event,
                SafeMessageFilter
            )
            if not ok then return false, "safe-message-filter-install-failed" end
            installedEvents[event] = true
        elseif not wanted and installedEvents[event] then
            local ok = pcall(
                ChatFrameUtil.RemoveMessageEventFilter,
                event,
                SafeMessageFilter
            )
            if not ok then return false, "safe-message-filter-remove-failed" end
            installedEvents[event] = nil
        end
    end
    return true
end

local function RemoveFilters()
    local anyInstalled = false
    for index = 1, #FILTER_EVENTS do
        if installedEvents[FILTER_EVENTS[index]] then
            anyInstalled = true
            break
        end
    end
    if not anyInstalled then return true end
    if type(ChatFrameUtil) ~= "table"
        or type(ChatFrameUtil.RemoveMessageEventFilter) ~= "function"
    then
        return false, "safe-message-filter-remove-api-unavailable"
    end
    local removed = true
    for index = 1, #FILTER_EVENTS do
        local event = FILTER_EVENTS[index]
        if installedEvents[event] then
            if pcall(
                ChatFrameUtil.RemoveMessageEventFilter,
                event,
                SafeMessageFilter
            ) then
                installedEvents[event] = nil
            else
                removed = false
            end
        end
    end
    return removed, removed and nil or "safe-message-filter-remove-failed"
end

local function ClearPrintParts(count)
    for index = 1, count do printParts[index] = nil end
end

local function CaptureYUIPrint(...)
    local history = YChat.HistoryRuntime
    if not SafeMessage.enabled or not historyInterest
        or not history or type(history.ProcessMessage) ~= "function"
        or not history:WantsEvent("YCHAT_PRINT")
        or Adapter:GetRestrictionState() ~= "OPEN"
    then
        return
    end
    local count = select("#", ...)
    if count < 1 then return end
    for index = 1, count do
        local value = select(index, ...)
        if IsSecret(value) then
            ClearPrintParts(index - 1)
            return
        end
        local ok, rendered = pcall(tostring, value)
        if not ok or type(rendered) ~= "string"
            or Adapter:IsExplicitlySafeValue(rendered) ~= true
        then
            ClearPrintParts(index - 1)
            return
        end
        printParts[index] = rendered
    end
    local text = concat(printParts, " ", 1, count)
    ClearPrintParts(count)
    if text ~= "" then history:ProcessMessage("YCHAT_PRINT", text, "") end
end

local function ResolvePrintTimestamp()
    local shadow = YChat.Shadow
    if not shadow or type(shadow.GetNativePrintTimestamp) ~= "function" then return nil end
    return shadow:GetNativePrintTimestamp()
end

local function ReconcileYUIPrintCapture()
    local history = YChat.HistoryRuntime
    local captureWanted = SafeMessage.enabled and historyInterest
        and history and type(history.WantsEvent) == "function"
        and history:WantsEvent("YCHAT_PRINT")
    local shadow = YChat.Shadow
    local prefixWanted = SafeMessage.enabled
        and shadow and type(shadow.IsNativePrintTimestampActive) == "function"
        and shadow:IsNativePrintTimestampActive()
    if captureWanted or prefixWanted then
        local installed, reason = Adapter:InstallYUIPrintWrapper(
            captureWanted and CaptureYUIPrint or nil,
            prefixWanted and ResolvePrintTimestamp or nil
        )
        if not installed then return false, reason end
        yuiPrintCaptureInstalled = true
        return true
    end
    if not yuiPrintCaptureInstalled then return true end
    local removed, reason = Adapter:RemoveYUIPrintWrapper()
    if removed then yuiPrintCaptureInstalled = false end
    return removed, reason
end

function SafeMessage:RefreshInterests()
    autoInterest = YChat:GetAutoInviteValue("enabled") == true
    historyInterest = YChat:GetHistoryValue("enabled") == true
    if YChat.AutoInvite and type(YChat.AutoInvite.OnConfigChanged) == "function" then
        YChat.AutoInvite:OnConfigChanged()
    end
    if YChat.HistoryRuntime and type(YChat.HistoryRuntime.OnConfigChanged) == "function" then
        YChat.HistoryRuntime:OnConfigChanged()
    end
    if self.enabled then
        local filtersOK, filterReason = ReconcileFilters()
        if not filtersOK then return false, filterReason end
        return ReconcileYUIPrintCapture()
    end
    return true
end

function SafeMessage:SetEnabled(enabled, reason)
    enabled = enabled == true
    if enabled then
        local callbackOK, callbackReason =
            Adapter:SetMessageDeferredCallback(DeferredStep)
        if not callbackOK then return false, callbackReason end
        self.enabled = true
        local refreshed, refreshReason = self:RefreshInterests()
        if not refreshed then
            self.enabled = false
            RemoveFilters()
            Adapter:SetMessageDeferredCallback(nil)
            return false, refreshReason
        end
    else
        self.enabled = false
        autoInterest = false
        historyInterest = false
        local driverStopped, driverReason =
            Adapter:SetMessageDeferredDriverEnabled(false)
        if not driverStopped then return false, driverReason end
        ClearQueue()
        ClearDedupe()
        local removed, removeReason = RemoveFilters()
        local printRemoved, printReason = ReconcileYUIPrintCapture()
        local callbackCleared, callbackReason =
            Adapter:SetMessageDeferredCallback(nil)
        if not removed then return false, removeReason end
        if not printRemoved then return false, printReason end
        if not callbackCleared then return false, callbackReason end
    end
    self.lastReason = reason
        or (enabled and "safe-message-enabled" or "safe-message-disabled")
    return true
end

function SafeMessage:GetRuntimeGauges(target)
    target = target or {}
    local installed = 0
    for index = 1, #FILTER_EVENTS do
        if installedEvents[FILTER_EVENTS[index]] then installed = installed + 1 end
    end
    target.safeMessageEnabled = self.enabled == true
    target.safeMessageFilters = installed
    target.safeMessageQueueDepth = queueCount
    target.safeMessageQueueDrops = self.queueDrops
    target.safeMessageFilterCalls = self.filterCalls
    target.safeMessageFilterBypasses = self.filterBypasses
    target.safeMessageDrained = self.drainedMessages
    return target
end

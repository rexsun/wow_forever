local YUI = _G.YUI
local YChat = YUI and YUI.YChat
if not YChat or (YUI.IsForever or YUI.IsRetail) ~= true then return end

local AutoInvite = {}
YChat.AutoInvite = AutoInvite

local Social = YUI.API and YUI.API.Social
local System = YUI.API and YUI.API.System
local lower = string.lower
local match = string.match
local find = string.find
local type = type

local keywordCache = {}
local allowCache = {}
local denyCache = {}
local senderIndex = {}
local senderNames = {}
local senderTimes = {}
local senderCursor = 1
local globalAttemptTimes = {}
local globalAttemptCursor = 1
local MAX_TRACKED_SENDERS = 64
local MAX_GLOBAL_ATTEMPTS = 20

AutoInvite.runtimeEnabled = false
AutoInvite.configEnabled = false
AutoInvite.lastReason = "not-started"
AutoInvite.inviteAttempts = 0
AutoInvite.inviteSuccesses = 0
AutoInvite.inviteBypasses = 0

local function StatIncrement(field)
    local stats = YChat.Stats
    if stats and stats.Increment then stats:Increment(field) end
end

local function Normalize(value)
    if type(value) ~= "string" then return nil end
    value = match(value, "^%s*(.-)%s*$")
    if value == "" then return nil end
    return lower(value)
end

local function ShortName(value)
    return value and match(value, "^([^-]+)") or nil
end

local function CacheList(target, values)
    for key in pairs(target) do target[key] = nil end
    if type(values) ~= "table" then return end
    for index = 1, #values do
        local value = Normalize(values[index])
        if value then target[value] = true end
    end
end

function AutoInvite:RefreshConfig()
    local config = YChat:GetAutoInvite()
    if not config then
        self.configEnabled = false
        return false, "auto-invite-config-unavailable"
    end
    self.configEnabled = config.enabled == true
    for index = #keywordCache, 1, -1 do keywordCache[index] = nil end
    for index = 1, #(config.keywords or {}) do
        local keyword = Normalize(config.keywords[index])
        if keyword then keywordCache[#keywordCache + 1] = keyword end
    end
    CacheList(allowCache, config.allowlist)
    CacheList(denyCache, config.denylist)
    return true
end

local function MatchesList(cache, ...)
    for index = 1, select("#", ...) do
        local value = Normalize(select(index, ...))
        if value and (cache[value] or cache[ShortName(value)]) then return true end
    end
    return false
end

local function HasAllowEntries()
    return next(allowCache) ~= nil
end

local function MatchesKeyword(text, mode)
    text = Normalize(text)
    if not text then return false end
    for index = 1, #keywordCache do
        local keyword = keywordCache[index]
        if mode == "exact" then
            if text == keyword then return true end
        elseif mode == "prefix" then
            if text:sub(1, #keyword) == keyword then return true end
        elseif find(text, keyword, 1, true) then
            return true
        end
    end
    return false
end

local function ReadNow()
    local value = System and System.GetTime and System.GetTime()
    return type(value) == "number" and value or 0
end

local function SenderOnCooldown(senderKey, now, cooldown)
    local index = senderIndex[senderKey]
    local last = index and senderTimes[index]
    return type(last) == "number" and now - last < cooldown
end

local function RememberSender(senderKey, now)
    local index = senderIndex[senderKey]
    if not index then
        index = senderCursor
        local old = senderNames[index]
        if old then senderIndex[old] = nil end
        senderNames[index] = senderKey
        senderIndex[senderKey] = index
        senderCursor = senderCursor < MAX_TRACKED_SENDERS and senderCursor + 1 or 1
    end
    senderTimes[index] = now
end

local function GlobalRateLimited(now, limit, window)
    local count = 0
    for index = 1, MAX_GLOBAL_ATTEMPTS do
        local timestamp = globalAttemptTimes[index]
        if type(timestamp) == "number" and now - timestamp < window then
            count = count + 1
        end
    end
    return count >= limit
end

local function RememberGlobalAttempt(now)
    globalAttemptTimes[globalAttemptCursor] = now
    globalAttemptCursor = globalAttemptCursor < MAX_GLOBAL_ATTEMPTS
        and globalAttemptCursor + 1
        or 1
end

local function Bypass(reason)
    AutoInvite.lastReason = reason
    AutoInvite.inviteBypasses = AutoInvite.inviteBypasses + 1
    StatIncrement("autoInviteBypasses")
    return false, reason
end

function AutoInvite:ProcessMessage(
    event,
    text,
    sender,
    specialFlags,
    _,
    bnSenderID
)
    if not self.runtimeEnabled or not self.configEnabled then
        return Bypass("auto-invite-disabled")
    end
    if event ~= "CHAT_MSG_WHISPER" and event ~= "CHAT_MSG_BN_WHISPER" then
        return Bypass("auto-invite-event-bypassed")
    end
    if specialFlags == "GM" or specialFlags == "DEV" then
        return Bypass("auto-invite-privileged-sender")
    end

    local config = YChat:GetAutoInvite()
    local senderKey = Normalize(sender)
    if not config or not senderKey or not MatchesKeyword(text, config.matchMode) then
        return Bypass("auto-invite-no-match")
    end

    local bnInfo
    if event == "CHAT_MSG_BN_WHISPER" then
        if not Social or type(Social.GetBNFriendInfoByID) ~= "function"
            or type(bnSenderID) ~= "number"
        then
            return Bypass("auto-invite-bnet-identity-unavailable")
        end
        bnInfo = Social.GetBNFriendInfoByID(bnSenderID)
        if type(bnInfo) ~= "table" then
            return Bypass("auto-invite-bnet-identity-unavailable")
        end
    end

    local accountName = bnInfo and bnInfo.accountName
    local battleTag = bnInfo and bnInfo.battleTag
    if MatchesList(denyCache, senderKey, accountName, battleTag) then
        return Bypass("auto-invite-denied")
    end
    if HasAllowEntries()
        and not MatchesList(allowCache, senderKey, accountName, battleTag)
    then
        return Bypass("auto-invite-not-allowed")
    end

    local now = ReadNow()
    if SenderOnCooldown(senderKey, now, config.senderCooldown) then
        return Bypass("auto-invite-sender-cooldown")
    end
    if GlobalRateLimited(now, config.rateLimit, config.rateWindow) then
        return Bypass("auto-invite-rate-limited")
    end
    if not Social or type(Social.GetInviteEligibility) ~= "function" then
        return Bypass("auto-invite-eligibility-unavailable")
    end
    local eligible, eligibilityReason = Social.GetInviteEligibility()
    if eligible ~= true then
        return Bypass("auto-invite-" .. (eligibilityReason or "ineligible"))
    end

    RememberSender(senderKey, now)
    RememberGlobalAttempt(now)
    self.inviteAttempts = self.inviteAttempts + 1
    StatIncrement("autoInviteAttempts")

    local invited, inviteReason
    if event == "CHAT_MSG_BN_WHISPER" then
        if type(Social.InviteBNet) ~= "function" then
            return Bypass("auto-invite-bnet-api-unavailable")
        end
        invited, inviteReason = Social.InviteBNet(
            bnInfo.friendIndex,
            bnInfo.bnetID or bnSenderID
        )
    else
        if type(Social.InviteUnit) ~= "function" then
            return Bypass("auto-invite-unit-api-unavailable")
        end
        invited, inviteReason = Social.InviteUnit(sender)
    end
    if invited == true then
        self.inviteSuccesses = self.inviteSuccesses + 1
        self.lastReason = "auto-invite-sent"
        StatIncrement("autoInviteSuccesses")
        return true
    end
    return Bypass(inviteReason or "auto-invite-call-failed")
end

function AutoInvite:SetEnabled(enabled, reason)
    self.runtimeEnabled = enabled == true
    if self.runtimeEnabled then self:RefreshConfig() end
    self.lastReason = reason
        or (self.runtimeEnabled and "auto-invite-runtime-enabled"
            or "auto-invite-runtime-disabled")
    return true
end

function AutoInvite:OnConfigChanged()
    return self:RefreshConfig()
end

function AutoInvite:GetRuntimeGauges(target)
    target = target or {}
    target.autoInviteRuntimeEnabled = self.runtimeEnabled == true
    target.autoInviteConfigEnabled = self.configEnabled == true
    target.autoInviteAttempts = self.inviteAttempts
    target.autoInviteSuccesses = self.inviteSuccesses
    target.autoInviteBypasses = self.inviteBypasses
    return target
end

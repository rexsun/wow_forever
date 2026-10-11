local YUI = _G.YUI
local YChat = YUI and YUI.YChat
if not YChat or (YUI.IsForever or YUI.IsRetail) ~= true then return end

local Adapter = YChat.Adapter
local WhisperNameColor = {}
YChat.WhisperNameColor = WhisperNameColor

local pcall = pcall
local type = type

WhisperNameColor.runtimeEnabled = false
WhisperNameColor.enabled = false
WhisperNameColor.filterInstalled = false
WhisperNameColor.filterCalls = 0
WhisperNameColor.filterBypasses = 0
WhisperNameColor.coloredNames = 0
WhisperNameColor.lastFailure = "none"

local function SenderNameFilter(
    event,
    decoratedPlayerName,
    _,
    senderName,
    _,
    _,
    _,
    _,
    _,
    _,
    _,
    _,
    _,
    senderGUID,
    bnSenderID
)
    if Adapter:GetRestrictionState() ~= "OPEN" then return decoratedPlayerName end
    if WhisperNameColor.enabled ~= true then return decoratedPlayerName end
    if Adapter:IsExplicitlySafeValue(event) ~= true or type(event) ~= "string" then
        return decoratedPlayerName
    end
    if event ~= "CHAT_MSG_WHISPER"
        and event ~= "CHAT_MSG_WHISPER_INFORM"
        and event ~= "CHAT_MSG_BN_WHISPER"
        and event ~= "CHAT_MSG_BN_WHISPER_INFORM"
    then
        return decoratedPlayerName
    end

    WhisperNameColor.filterCalls = WhisperNameColor.filterCalls + 1
    local colored, reason = Adapter:ColorWhisperName(
        event,
        decoratedPlayerName,
        senderName,
        senderGUID,
        bnSenderID
    )
    if reason == "colored" then
        WhisperNameColor.coloredNames = WhisperNameColor.coloredNames + 1
        return colored
    end
    WhisperNameColor.filterBypasses = WhisperNameColor.filterBypasses + 1
    return decoratedPlayerName
end

local function RemoveFilter()
    if WhisperNameColor.filterInstalled ~= true then return true end
    local util = _G.ChatFrameUtil
    local remove = type(util) == "table" and util.RemoveSenderNameFilter or nil
    if type(remove) ~= "function" then
        return false, "whisper-name-filter-remove-api-unavailable"
    end
    if not pcall(remove, SenderNameFilter) then
        return false, "whisper-name-filter-remove-failed"
    end
    WhisperNameColor.filterInstalled = false
    return true
end

local function InstallFilter()
    if WhisperNameColor.filterInstalled == true then return true end
    local util = _G.ChatFrameUtil
    local add = type(util) == "table" and util.AddSenderNameFilter or nil
    if type(add) ~= "function" then
        return false, "whisper-name-filter-api-unavailable"
    end
    if not pcall(add, SenderNameFilter) then
        return false, "whisper-name-filter-install-failed"
    end
    WhisperNameColor.filterInstalled = true
    return true
end

function WhisperNameColor:SetEnabled(enabled, reason)
    self.runtimeEnabled = enabled == true
    local appearance = YChat.GetAppearance and YChat:GetAppearance() or nil
    local configured = type(appearance) == "table"
        and appearance.classColorWhisperNames ~= false
    local shouldEnable = self.runtimeEnabled and configured

    if not shouldEnable then
        self.enabled = false
        local removed, removeReason = RemoveFilter()
        self.lastFailure = removeReason or "none"
        return removed, removeReason
    end

    local cacheReady, cacheReason = Adapter:RefreshWhisperClassColorCache()
    if not cacheReady then
        self.enabled = false
        self.lastFailure = cacheReason
        return false, cacheReason
    end
    local installed, installReason = InstallFilter()
    self.enabled = installed == true
    self.lastFailure = installReason or "none"
    return installed, installReason
end

function WhisperNameColor:GetRuntimeGauges(target)
    target = target or {}
    target.whisperNameColorRuntimeEnabled = self.runtimeEnabled == true
    target.whisperNameColorEnabled = self.enabled == true
    target.whisperNameColorFilterInstalled = self.filterInstalled == true
    target.whisperNameColorFilterCalls = self.filterCalls
    target.whisperNameColorFilterBypasses = self.filterBypasses
    target.whisperNameColorColoredNames = self.coloredNames
    target.whisperNameColorLastFailure = self.lastFailure or "none"
    return target
end

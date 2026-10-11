local YUI = _G.YUI
if not YUI or not YUI.YChat then return end

local YChat = YUI.YChat
local Adapter = {}
YChat.Adapter = Adapter

local inputReplyCallback
local inputReplyHooks = setmetatable({}, { __mode = "k" })

local CreateFrame = _G.CreateFrame
local CreateFontFamily = _G.CreateFontFamily
local hooksecurefunc = _G.hooksecurefunc
local issecretvalue = _G.issecretvalue
local EventRegistry = _G.EventRegistry
local GameTooltip = _G.GameTooltip
local floor = math.floor
local huge = math.huge
local abs = math.abs
local max = math.max
local find = string.find
local gsub = string.gsub
local gmatch = string.gmatch
local lower = string.lower
local concat = table.concat
local format = string.format
local sub = string.sub
local sort = table.sort
local pcall = pcall
local type = type
local error = error
local CallYUIPrintWithLeadingPrefix = YUI.API and YUI.API.Print
    and YUI.API.Print.CallWithLeadingPrefix

local MAX_EXACT_INTEGER = 9007199254740991
local INSERT_MODE_TOP = _G.SCROLLING_MESSAGE_FRAME_INSERT_MODE_TOP or 1
local INSERT_MODE_BOTTOM = _G.SCROLLING_MESSAGE_FRAME_INSERT_MODE_BOTTOM or 2
local TIMESTAMP_FONT_HEIGHT_TOLERANCE = 0.01
local MAX_DEFERRED_DRIVER_FRAMES = 8
local CHAT_FONT_ALPHABETS = {
    "roman",
    "russian",
    "korean",
    "simplifiedchinese",
    "traditionalchinese",
}
local nextChatFontFamilyId = 0

local frameStates = setmetatable({}, { __mode = "k" })
local maxLinesWriteSuppressed = setmetatable({}, { __mode = "k" })
local channelTransformSuppressed = setmetatable({}, { __mode = "k" })
local lineHookStates = setmetatable({}, { __mode = "k" })
local lineShownStates = setmetatable({}, { __mode = "k" })
local lineOverlayByLine = setmetatable({}, { __mode = "k" })
local lineAlphaSetterByLine = setmetatable({}, { __mode = "k" })
local trustedFrames = setmetatable({}, { __mode = "k" })
local temporaryTypographyFrames = setmetatable({}, { __mode = "k" })
local tooltipOwnerByFrame = setmetatable({}, { __mode = "k" })
local ReconcileDeferredDriver
local floatingHookInstalled = false
local openWindowHookInstalled = false
local temporaryWindowHookInstalled = false
local closeWindowHookInstalled = false
local nativeFontSizeHookInstalled = false
local yuiPrintOriginal
local yuiPrintCaptureCallback
local yuiPrintPrefixCallback
local yuiPrintWrapperInstalled = false
local yuiPrintCaptureBusy = false
local yuiPrintPrefixBusy = false
local clientBackend
local validRestrictionStates = {
    OPEN = true,
    PAUSED = true,
    UNKNOWN = true,
    UNSUPPORTED = true,
}

Adapter.enabled = false
Adapter.lineSyncEnabled = false
Adapter.displaySyncEnabled = false
Adapter.callbacks = nil
Adapter.restrictionState = "UNKNOWN"
Adapter.listenerCount = 0
Adapter.messageHookCount = 0
Adapter.clientFlavor = nil
Adapter.clientBackendConflict = false
Adapter.deferredDriverEnabled = false
Adapter.messageDeferredDriverEnabled = false
Adapter.messageDeferredCallback = nil
Adapter.channelDeferredDriverEnabled = false
Adapter.channelDeferredCallback = nil
Adapter.channelTransformCallback = nil
Adapter.deferredDriverInstalled = false
Adapter.deferredDriverCleanupFailed = false
Adapter.deferredDriverRunFrames = 0
Adapter.tooltipEnabled = false
Adapter.tooltipAnchor = "ANCHOR_RIGHT"
Adapter.tooltipListenerCount = 0
Adapter.activeTooltipFrame = nil
Adapter.tooltipCleanupPending = false
Adapter.tooltipCleanupReason = nil

local VALID_TOOLTIP_ANCHORS = {
    ANCHOR_TOP = true,
    ANCHOR_BOTTOM = true,
    ANCHOR_TOPLEFT = true,
    ANCHOR_TOPRIGHT = true,
    ANCHOR_BOTTOMLEFT = true,
    ANCHOR_BOTTOMRIGHT = true,
    ANCHOR_LEFT = true,
    ANCHOR_RIGHT = true,
}
local TOOLTIP_LINK_CLEARANCE = 8

local function IsTooltipInteractionState(state)
    return state == "OPEN" or state == "PAUSED"
end

local GLOBAL_CHAT_BUTTON_NAMES = {
    "ChatFrameMenuButton",
    "ChatFrameChannelButton",
    "ChatFrameToggleVoiceDeafenButton",
    "ChatFrameToggleVoiceMuteButton",
    "TextToSpeechButton",
    "TextToSpeechButtonFrame",
    "QuickJoinToastButton",
}
local APPEARANCE_TAB_KEYS = {
    "Left",
    "Right",
    "Middle",
    "ActiveLeft",
    "ActiveMiddle",
    "ActiveRight",
    "glow",
    "HighlightLeft",
    "HighlightMiddle",
    "HighlightRight",
}
local APPEARANCE_FRAME_REGION_SUFFIXES = {
    "TopLeftTexture",
    "BottomLeftTexture",
    "TopRightTexture",
    "BottomRightTexture",
    "LeftTexture",
    "RightTexture",
    "BottomTexture",
    "TopTexture",
}

local function StatIncrement(field, amount)
    local stats = YChat.Stats
    if stats and stats.Increment then stats:Increment(field, amount) end
end

local function StatSet(field, value)
    local stats = YChat.Stats
    if stats and stats.Set then stats:Set(field, value) end
end

local function RecordPermanentHook(state)
    if state then state.hookCount = (state.hookCount or 0) + 1 end
    Adapter.messageHookCount = Adapter.messageHookCount + 1
    StatSet("messageHooks", Adapter.messageHookCount)
end

local function ReportCallbackFailure(callbacks, name)
    StatIncrement("adapterMismatches")
    local errorCallback = callbacks and callbacks.onError
    if name ~= "onError" and type(errorCallback) == "function" then pcall(errorCallback, name) end
end

local function Dispatch(name, ...)
    if not Adapter.enabled then return false end
    local callbacks = Adapter.callbacks
    local callback = callbacks and callbacks[name]
    if type(callback) ~= "function" then return false end
    local ok = pcall(callback, ...)
    if not ok then
        ReportCallbackFailure(callbacks, name)
    end
    return ok
end

local function DispatchAdd(callback, frame)
    local callbacks = Adapter.callbacks
    if type(callback) ~= "function" then return false end
    local ok = pcall(callback, frame)
    if not ok then ReportCallbackFailure(callbacks, "onAdd") end
    return ok
end

local function DeferredDriverOnUpdate()
    if not Adapter.enabled or not Adapter.deferredDriverInstalled then return end
    Adapter.deferredDriverRunFrames = Adapter.deferredDriverRunFrames + 1
    if Adapter.deferredDriverRunFrames > MAX_DEFERRED_DRIVER_FRAMES then
        local channelCallback = Adapter.channelDeferredDriverEnabled
            and Adapter.channelDeferredCallback
        Adapter.deferredDriverEnabled = false
        Adapter.messageDeferredDriverEnabled = false
        Adapter.channelDeferredDriverEnabled = false
        StatIncrement("adapterMismatches")
        if type(channelCallback) == "function"
            and not pcall(channelCallback, "deferred-driver-fused")
        then
            ReportCallbackFailure(Adapter.callbacks, "onChannelDeferred")
        end
        if Adapter.deferredDriverCleanupFailed ~= true then
            ReconcileDeferredDriver(Adapter)
        end
        return
    end
    local cpuWatchdog = YUI.CPUWatchdog
    local cpuStartedAt = cpuWatchdog and cpuWatchdog.timingActive and cpuWatchdog:BeginProbeTiming()
    local callbacks = Adapter.callbacks
    if Adapter.deferredDriverEnabled then
        local callback = callbacks and callbacks.onDeferred
        if type(callback) ~= "function" then
            Adapter:SetDeferredDriverEnabled(false)
            ReportCallbackFailure(callbacks, "onDeferred")
        else
            local ok = pcall(callback)
            if not ok then
                Adapter:SetDeferredDriverEnabled(false)
                ReportCallbackFailure(callbacks, "onDeferred")
            end
        end
    end
    if Adapter.messageDeferredDriverEnabled then
        local callback = Adapter.messageDeferredCallback
        if type(callback) ~= "function" then
            Adapter:SetMessageDeferredDriverEnabled(false)
            ReportCallbackFailure(callbacks, "onMessageDeferred")
        else
            local ok = pcall(callback)
            if not ok then
                Adapter:SetMessageDeferredDriverEnabled(false)
                ReportCallbackFailure(callbacks, "onMessageDeferred")
            end
        end
    end
    if Adapter.channelDeferredDriverEnabled then
        local callback = Adapter.channelDeferredCallback
        if type(callback) ~= "function" then
            Adapter:SetChannelDeferredDriverEnabled(false)
            ReportCallbackFailure(callbacks, "onChannelDeferred")
        else
            local ok = pcall(callback)
            if not ok then
                Adapter:SetChannelDeferredDriverEnabled(false)
                ReportCallbackFailure(callbacks, "onChannelDeferred")
            end
        end
    end
    if Adapter.deferredDriverCleanupFailed ~= true then
        ReconcileDeferredDriver(Adapter)
    end
    if cpuStartedAt then cpuWatchdog:EndProbeTiming("product.ychat-driver", cpuStartedAt) end
end

local function DispatchLineAlpha(line, value)
    local callbacks = Adapter.callbacks
    local callback = callbacks and callbacks.onLineAlpha
    if type(callback) ~= "function" then return false end
    local ok = pcall(callback, line, value)
    if not ok then ReportCallbackFailure(callbacks, "onLineAlpha") end
    return ok
end

local function DispatchLineShow(line)
    local callbacks = Adapter.callbacks
    local callback = callbacks and callbacks.onLineShow
    if type(callback) ~= "function" then return false end
    local ok = pcall(callback, line)
    if not ok then ReportCallbackFailure(callbacks, "onLineShow") end
    return ok
end

local function SetRestrictionState(state)
    if validRestrictionStates[state] ~= true then state = "UNKNOWN" end
    if Adapter.restrictionState == state then
        StatSet("restrictionState", state)
        return state
    end
    Adapter.restrictionState = state
    StatSet("restrictionState", state)
    StatIncrement("restrictionTransitions")
    if state ~= "OPEN" and Adapter.ClearHyperlinkTooltip then
        Adapter:ClearHyperlinkTooltip()
    end
    Dispatch("onRestriction", state)
    return state
end

local function UpdateListenerGauge()
    StatSet(
        "listeners",
        (Adapter.listenerCount or 0)
            + (Adapter.tooltipListenerCount or 0)
            + (YChat.lifecycleListenerCount or 0)
    )
end

function Adapter:SetClientBackend(backend)
    if self.clientBackendConflict then return false, "client-backend-conflict" end
    if type(backend) ~= "table" then return false, "client-backend-invalid" end
    if backend.flavor ~= "mainline" and backend.flavor ~= "forever" and backend.flavor ~= "wrath" then
        return false, "client-backend-flavor-invalid"
    end
    if type(backend.CanCallProtected) ~= "function"
        or type(backend.ReadRestrictionState) ~= "function"
        or type(backend.RegisterEvents) ~= "function"
        or type(backend.HandleEvent) ~= "function"
    then
        return false, "client-backend-contract-invalid"
    end
    if clientBackend and clientBackend ~= backend then
        clientBackend = nil
        self.clientFlavor = nil
        self.clientBackendConflict = true
        SetRestrictionState("UNKNOWN")
        return false, "client-backend-conflict"
    end

    clientBackend = backend
    self.clientFlavor = backend.flavor
    return true
end

function Adapter:GetClientFlavor()
    return self.clientFlavor
end

local function YChatYUIPrintWrapper(owner, ...)
    local original = yuiPrintOriginal
    local prefix
    local prefixCallback = yuiPrintPrefixCallback
    if Adapter.enabled and not yuiPrintPrefixBusy and type(prefixCallback) == "function" then
        yuiPrintPrefixBusy = true
        local ok, value = pcall(prefixCallback)
        yuiPrintPrefixBusy = false
        if ok and type(value) == "string" and value ~= ""
            and type(Adapter.IsExplicitlySafeValue) == "function"
            and Adapter:IsExplicitlySafeValue(value) == true
        then
            prefix = value
        end
    end
    if type(original) == "function" then
        if prefix and type(CallYUIPrintWithLeadingPrefix) == "function" then
            CallYUIPrintWithLeadingPrefix(original, owner, prefix, ...)
        else
            original(owner, ...)
        end
    end
    local callback = yuiPrintCaptureCallback
    if not Adapter.enabled or yuiPrintCaptureBusy or type(callback) ~= "function" then return end
    yuiPrintCaptureBusy = true
    pcall(callback, ...)
    yuiPrintCaptureBusy = false
end

function Adapter:InstallYUIPrintWrapper(callback, prefixCallback)
    if (self.clientFlavor ~= "mainline" and self.clientFlavor ~= "forever") then return false, "yui-print-wrapper-mainline-only" end
    if callback ~= nil and type(callback) ~= "function" then
        return false, "yui-print-wrapper-callback-invalid"
    end
    if prefixCallback ~= nil and type(prefixCallback) ~= "function" then
        return false, "yui-print-prefix-callback-invalid"
    end
    if callback == nil and prefixCallback == nil then
        return false, "yui-print-wrapper-callback-missing"
    end
    yuiPrintCaptureCallback = callback
    yuiPrintPrefixCallback = prefixCallback
    if yuiPrintWrapperInstalled then
        if YUI.Print == yuiPrintOriginal then YUI.Print = YChatYUIPrintWrapper end
        return true
    end
    if type(YUI.Print) ~= "function" then
        yuiPrintCaptureCallback = nil
        yuiPrintPrefixCallback = nil
        return false, "yui-print-api-unavailable"
    end
    yuiPrintOriginal = YUI.Print
    YUI.Print = YChatYUIPrintWrapper
    if YUI.Print ~= YChatYUIPrintWrapper then
        yuiPrintOriginal = nil
        yuiPrintCaptureCallback = nil
        yuiPrintPrefixCallback = nil
        return false, "yui-print-wrapper-install-unconfirmed"
    end
    yuiPrintWrapperInstalled = true
    return true
end

function Adapter:RemoveYUIPrintWrapper()
    yuiPrintCaptureCallback = nil
    yuiPrintPrefixCallback = nil
    if not yuiPrintWrapperInstalled then return true end
    if YUI.Print == YChatYUIPrintWrapper then
        YUI.Print = yuiPrintOriginal
        if YUI.Print ~= yuiPrintOriginal then
            return false, "yui-print-wrapper-restore-unconfirmed"
        end
        yuiPrintWrapperInstalled = false
        yuiPrintOriginal = nil
        return true
    end
    return true, "yui-print-wrapper-owner-changed"
end

local RAW_HISTORY_EVENTS = {
    CHAT_MSG_SYSTEM = true,
    CHAT_MSG_LOOT = true,
    CHAT_MSG_CURRENCY = true,
    CHAT_MSG_MONEY = true,
}

local PLAYER_CLASS_TOKENS = {
    "WARRIOR",
    "PALADIN",
    "HUNTER",
    "ROGUE",
    "PRIEST",
    "DEATHKNIGHT",
    "SHAMAN",
    "MAGE",
    "WARLOCK",
    "MONK",
    "DRUID",
    "DEMONHUNTER",
    "EVOKER",
}
local whisperClassColorHexByToken = {}

local WHISPER_NAME_COLOR_EVENTS = {
    CHAT_MSG_WHISPER = false,
    CHAT_MSG_WHISPER_INFORM = false,
    CHAT_MSG_BN_WHISPER = true,
    CHAT_MSG_BN_WHISPER_INFORM = true,
}

function Adapter:ResolvePlayerClassTokenByGUID(guid)
    if self:IsExplicitlySafeValue(guid) ~= true
        or type(guid) ~= "string" or guid == ""
        or type(_G.GetPlayerInfoByGUID) ~= "function"
    then
        return nil, "player-guid-unavailable"
    end
    local ok, _, classToken = pcall(_G.GetPlayerInfoByGUID, guid)
    if not ok or self:IsExplicitlySafeValue(classToken) ~= true
        or type(classToken) ~= "string" or classToken == ""
    then
        return nil, "player-class-unavailable"
    end
    return classToken
end

function Adapter:RefreshWhisperClassColorCache()
    local unitAPI = YUI.API and YUI.API.Unit
    local getColor = unitAPI and unitAPI.GetClassColor
    if type(getColor) ~= "function" then return false, "class-color-api-unavailable" end

    for index = 1, #PLAYER_CLASS_TOKENS do
        local classToken = PLAYER_CLASS_TOKENS[index]
        local colorOK, color = pcall(getColor, classToken)
        local colorHex
        if colorOK and self:IsExplicitlySafeValue(color) == true
            and type(color) == "table"
        then
            local r, g, b = color.r, color.g, color.b
            if self:IsExplicitlySafeValue(r) == true
                and self:IsExplicitlySafeValue(g) == true
                and self:IsExplicitlySafeValue(b) == true
                and type(r) == "number" and type(g) == "number" and type(b) == "number"
                and r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1
                and r == r and g == g and b == b
            then
                colorHex = format(
                    "ff%02x%02x%02x",
                    floor(r * 255 + 0.5),
                    floor(g * 255 + 0.5),
                    floor(b * 255 + 0.5)
                )
            end
        end
        whisperClassColorHexByToken[classToken] = colorHex
    end
    return true
end

function Adapter:WrapNameWithClassColor(name, classToken)
    if self:IsExplicitlySafeValue(name) ~= true
        or type(name) ~= "string" or name == ""
        or self:IsExplicitlySafeValue(classToken) ~= true
        or type(classToken) ~= "string" or classToken == ""
    then
        return name, "class-color-input-unsafe"
    end
    if find(name, "|c", 1, true) or find(name, "|C", 1, true) then
        return name, "class-color-already-present"
    end

    local colorHex = whisperClassColorHexByToken[classToken]
    if type(colorHex) ~= "string" or colorHex == ""
        or self:IsExplicitlySafeValue(colorHex) ~= true
    then
        return name, "class-color-unavailable"
    end
    return "|c" .. colorHex .. name .. "|r", "colored"
end

function Adapter:ColorWhisperName(event, decoratedName, senderName, senderGUID, bnSenderID)
    if (self.clientFlavor ~= "mainline" and self.clientFlavor ~= "forever") then
        return decoratedName, "whisper-name-color-mainline-only"
    end
    if self:IsExplicitlySafeValue(event) ~= true
        or type(event) ~= "string"
        or WHISPER_NAME_COLOR_EVENTS[event] == nil
        or self:IsExplicitlySafeValue(decoratedName) ~= true
        or type(decoratedName) ~= "string"
    then
        return decoratedName, "whisper-name-color-event-unsafe"
    end

    local classToken = self:ResolvePlayerClassTokenByGUID(senderGUID)
    if classToken == nil and WHISPER_NAME_COLOR_EVENTS[event] == true then
        local accountID = self:ResolveBNetAccountID(senderName, bnSenderID)
        local backend = clientBackend
        local resolveCurrent = backend and backend.ResolveCurrentBNetClassToken
        if accountID ~= nil and type(resolveCurrent) == "function" then
            local ok, resolved = pcall(resolveCurrent, backend, accountID)
            if ok and type(resolved) == "string"
                and self:IsExplicitlySafeValue(resolved) == true
            then
                classToken = resolved
            end
        end
    end
    if classToken == nil then return decoratedName, "whisper-name-class-unresolved" end
    return self:WrapNameWithClassColor(decoratedName, classToken)
end

local function ValidateHistoricalTemplate(template)
    local remainder, placeholders = gsub(template, "%%[%d%$%.%-]*s", "")
    if placeholders < 1 or placeholders > 2 then return false end
    remainder = gsub(remainder, "%%%%", "")
    return not remainder:find("%%", 1, true)
end

local function DispatchInputReply(lastTargetGetter)
    if not Adapter.enabled or not inputReplyCallback then return end
    local util = _G.ChatFrameUtil
    if type(util) ~= "table" or type(util.GetActiveWindow) ~= "function" then return end
    if lastTargetGetter then
        local getter = util[lastTargetGetter]
        if type(getter) ~= "function" then return end
        local ok, target = pcall(getter)
        if not ok or Adapter:IsExplicitlySafeValue(target) ~= true
            or type(target) ~= "string" or target == ""
        then
            return
        end
    end
    local ok, editBox = pcall(util.GetActiveWindow)
    if ok and Adapter:IsExplicitlySafeValue(editBox) == true and editBox ~= nil then
        inputReplyCallback(editBox)
    end
end

local function IsPlayerLinkName(name)
    if name:find("[%c|:%[%]]") then return false end
    if Adapter.clientFlavor == "forever" then
        return name ~= "" and not name:find("^ ") and not name:find(" $")
            and not name:find("  ", 1, true)
    end
    return not name:find("%s")
end

local function RepairForeverTell(name, text, chatFrame)
    if Adapter.clientFlavor ~= "forever" or not Adapter.enabled or not inputReplyCallback then return end
    if Adapter:IsExplicitlySafeValue(name) ~= true or type(name) ~= "string"
        or not name:find(" ", 1, true) or not IsPlayerLinkName(name)
        or Adapter:IsExplicitlySafeValue(text) ~= true or type(text) ~= "string"
        or Adapter:IsExplicitlySafeValue(chatFrame) ~= true then return end
    local restriction = Adapter:GetRestrictionState()
    if restriction ~= "OPEN" and restriction ~= "PAUSED" then return end
    local util = _G.ChatFrameUtil
    if type(util) ~= "table" or type(util.ChooseBoxForSend) ~= "function"
        or type(util.ActivateChat) ~= "function" then return end
    local ok, editBox = pcall(util.ChooseBoxForSend, chatFrame)
    if not ok or Adapter:IsExplicitlySafeValue(editBox) ~= true or editBox == nil
        or Adapter:CanCallProtected(editBox) ~= true
        or type(editBox.SetTellTarget) ~= "function" or type(editBox.SetChatType) ~= "function"
        or type(editBox.SetText) ~= "function" or type(editBox.UpdateHeader) ~= "function" then return end
    -- OpenChat may defer its slash text until OnUpdate. Cancel only this request's pending text.
    if Adapter:IsExplicitlySafeValue(editBox.setText) ~= true
        or Adapter:IsExplicitlySafeValue(editBox.text) ~= true then return end
    if editBox.setText == 1 then
        if type(_G.SLASH_WHISPER1) ~= "string"
            or editBox.text ~= string.format("%s %s %s", _G.SLASH_WHISPER1, name, text) then return end
        editBox.setText = 0
        editBox.text = text
    end
    -- Activate first: showing a hidden native input resets its chat type.
    util.ActivateChat(editBox)
    editBox:SetTellTarget(name)
    editBox:SetChatType("WHISPER")
    editBox:SetText(text)
    editBox:UpdateHeader()
end

local function InputTellRequestedHook(name, text, chatFrame)
    RepairForeverTell(name, text, chatFrame)
    DispatchInputReply()
end

local function InputReplyRequestedHook()
    DispatchInputReply()
end

local function InputLastTellRequestedHook()
    DispatchInputReply("GetLastTellTarget")
end

local function InputLastToldRequestedHook()
    DispatchInputReply("GetLastToldTarget")
end

local INPUT_REPLY_HOOKS = {
    SendTellWithMessage = InputTellRequestedHook,
    SendBNetTell = InputReplyRequestedHook,
    ReplyTell = InputLastTellRequestedHook,
    ReplyTell2 = InputLastToldRequestedHook,
}

function Adapter:SetInputReplyCallback(callback)
    if callback == nil then inputReplyCallback = nil; return true end
    if (self.clientFlavor ~= "mainline" and self.clientFlavor ~= "forever") or type(callback) ~= "function" then return false end
    local util = _G.ChatFrameUtil
    if type(util) ~= "table" or type(util.GetActiveWindow) ~= "function"
        or type(util.ActivateChat) ~= "function" or type(hooksecurefunc) ~= "function"
    then
        return false, "input-reply-api-unavailable"
    end
    local hooks = inputReplyHooks[util]
    if not hooks then hooks = {}; inputReplyHooks[util] = hooks end
    for method, hook in pairs(INPUT_REPLY_HOOKS) do
        if type(util[method]) ~= "function" then return false, "input-reply-api-unavailable" end
        if not hooks[method] then
            if not pcall(hooksecurefunc, util, method, hook) then return false, "input-reply-hook-failed" end
            hooks[method] = true
        end
    end
    inputReplyCallback = callback
    return true
end

function Adapter:ActivateInputForReply(editBox)
    if (self.clientFlavor ~= "mainline" and self.clientFlavor ~= "forever") or not self.enabled then return false end
    local restriction = self:GetRestrictionState()
    if restriction ~= "OPEN" and restriction ~= "PAUSED" then return false end
    if self:CanCallProtected(editBox) ~= true then return false end
    local util = _G.ChatFrameUtil
    if type(util) ~= "table" or type(util.ActivateChat) ~= "function" then return false end
    -- 原生回复可能只改写当前输入框的目标；使用原生激活入口补齐焦点生命周期。
    return pcall(util.ActivateChat, editBox)
end

function Adapter:ReadHistoryBattleTag(accountID)
    if (self.clientFlavor ~= "mainline" and self.clientFlavor ~= "forever") or self.clientBackendConflict then return nil end
    local callback = clientBackend and clientBackend.ReadHistoryBattleTag
    if type(callback) ~= "function" then return nil end
    local ok, tag = pcall(callback, clientBackend, accountID)
    if ok and self:IsExplicitlySafeValue(tag) == true and type(tag) == "string" then return tag end
end

function Adapter:BuildHistoryBNetLookup()
    if (self.clientFlavor ~= "mainline" and self.clientFlavor ~= "forever") or self.clientBackendConflict then return nil end
    local callback = clientBackend and clientBackend.BuildHistoryBNetLookup
    if type(callback) ~= "function" then return nil end
    local ok, lookup = pcall(callback, clientBackend)
    if ok and type(lookup) == "table" then return lookup end
end

local function ReadReplayLanguage(frame, event)
    if event == "CHAT_MSG_SAY" or event == "CHAT_MSG_YELL" then return frame.alternativeDefaultLanguage end
    return frame.defaultLanguage
end

function Adapter:FormatHistoricalMessage(slot, channelFallback, linkSender, bnetLookup, replayFrame)
    if (self.clientFlavor ~= "mainline" and self.clientFlavor ~= "forever") then return nil, "history-format-mainline-only" end
    if type(slot) ~= "table"
        or type(slot.event) ~= "string"
        or type(slot.text) ~= "string"
        or self:IsExplicitlySafeValue(slot.event) ~= true
        or self:IsExplicitlySafeValue(slot.text) ~= true
        or slot.text == ""
    then
        return nil, "history-format-record-invalid"
    end
    local event = slot.event
    local languageHeader = ""
    if linkSender == true and replayFrame and self:IsExplicitlySafeValue(slot.languageName) == true
        and type(slot.languageName) == "string" and slot.languageName ~= "" then
        local ok, defaultLanguage = pcall(ReadReplayLanguage, replayFrame, event)
        if ok and self:IsExplicitlySafeValue(defaultLanguage) == true
            and type(defaultLanguage) == "string" and defaultLanguage ~= ""
            and slot.languageName ~= defaultLanguage then
            languageHeader = "[" .. slot.languageName .. "] "
        end
    end
    if event == "YCHAT_PRINT" then
        return gsub(slot.text, "\t", " ")
    end
    if RAW_HISTORY_EVENTS[event] then return slot.text end

    if self:IsExplicitlySafeValue(slot.sender) ~= true
        or self:IsExplicitlySafeValue(slot.playerName2) ~= true
        or self:IsExplicitlySafeValue(slot.bnDisplayName) ~= true then
        return nil, "history-format-sender-unsafe"
    end
    local sender = type(slot.sender) == "string" and slot.sender or ""
    if sender == "" and type(slot.playerName2) == "string" then sender = slot.playerName2 end
    if (event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM")
        and type(slot.bnDisplayName) == "string" and slot.bnDisplayName ~= ""
    then
        sender = slot.bnDisplayName
    end
    -- Protected Battle.net display tokens belong to the current session only.
    if (event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM")
        and sender:find("|K", 1, true) then
        local tag = slot.bnBattleTag
        local safeTag = self:IsExplicitlySafeValue(tag) == true and type(tag) == "string"
            and tag:match("^[^#%s%c|:]+#%d+$") and tag
        local account = safeTag and type(bnetLookup) == "table" and bnetLookup[safeTag]
        sender = type(account) == "table" and account.name
            or (safeTag and safeTag:match("^([^#]+)#")) or "Battle.net"
    end
    if self:IsExplicitlySafeValue(sender) ~= true then
        return nil, "history-format-sender-unsafe"
    end
    local playerName = sender
    local nameFormatter = YChat.ChannelInput
    if nameFormatter and type(nameFormatter.FormatPlayerDisplayName) == "function" then
        sender = nameFormatter:FormatPlayerDisplayName(event, sender, playerName, slot.senderGUID)
    end
    if sender ~= "" then
        local classToken = self:ResolvePlayerClassTokenByGUID(slot.senderGUID)
        if classToken ~= nil then sender = self:WrapNameWithClassColor(sender, classToken) end
    end
    -- 与原生保持一致：普通消息的括号属于链接显示文字，表情不加括号。
    if linkSender == true and sender ~= ""
        and (languageHeader ~= "" or (event ~= "CHAT_MSG_EMOTE" and event ~= "CHAT_MSG_TEXT_EMOTE")) then
        sender = "[" .. sender .. "]"
    end
    local isBNet = event == "CHAT_MSG_BN_WHISPER" or event == "CHAT_MSG_BN_WHISPER_INFORM"
    local tag = slot.bnBattleTag
    local account = linkSender == true and isBNet and type(bnetLookup) == "table"
        and self:IsExplicitlySafeValue(tag) == true and type(tag) == "string" and bnetLookup[tag]
    -- 回填使用当前身份；旧消息编号归零，旧战网编号不参与匹配。
    if type(account) == "table" then
        sender = "|HBNplayer:" .. account.name .. ":" .. account.accountID
            .. ":0:BN_WHISPER:" .. account.name .. "|h" .. sender .. "|h"
    elseif linkSender == true and playerName ~= ""
        and event ~= "CHAT_MSG_BN_WHISPER" and event ~= "CHAT_MSG_BN_WHISPER_INFORM"
        and IsPlayerLinkName(playerName)
    then
        sender = "|Hplayer:" .. playerName .. "|h" .. sender .. "|h"
    end
    if self:IsExplicitlySafeValue(slot.specialFlags) == true
        and type(slot.specialFlags) == "string" and slot.specialFlags ~= ""
    then
        local flag = _G["CHAT_FLAG_" .. slot.specialFlags]
        if type(flag) == "string" and self:IsExplicitlySafeValue(flag) == true then
            sender = flag .. sender
        end
    end
    if event == "CHAT_MSG_TEXT_EMOTE" and languageHeader == "" then
        if linkSender == true and playerName ~= "" then
            local first, last = slot.text:find(playerName, 1, true)
            if first then return sub(slot.text, 1, first - 1) .. sender .. sub(slot.text, last + 1) end
        end
        return slot.text
    end
    if event == "CHAT_MSG_ACHIEVEMENT" or event == "CHAT_MSG_GUILD_ACHIEVEMENT" then
        if sender == "" then return nil, "history-format-sender-missing" end
        local first, last = slot.text:find("%s", 1, true)
        if first then return sub(slot.text, 1, first - 1) .. sender .. sub(slot.text, last + 1) end
        return nil, "history-format-achievement-template-invalid"
    end

    local subtype = sub(event, 10)
    local channelInput = YChat.ChannelInput
    local template = channelInput and type(channelInput.ResolveHistoricalFormatKey) == "function"
        and channelInput:ResolveHistoricalFormatKey(subtype)
        or nil
    if type(template) ~= "string" or template == ""
        or self:IsExplicitlySafeValue(template) ~= true
        or ValidateHistoricalTemplate(template) ~= true
    then
        return nil, "history-format-template-invalid"
    end
    local escapedText = gsub(languageHeader .. slot.text, "%%", "%%%%")
    local formattedOK, message = pcall(format, template .. escapedText, sender, sender)
    if not formattedOK or type(message) ~= "string" or message == "" then
        return nil, "history-format-placeholder-mismatch"
    end

    if event == "CHAT_MSG_CHANNEL" or event == "CHAT_MSG_COMMUNITIES_CHANNEL" then
        local channelName
        if channelInput and type(channelInput.ResolveHistoricalChannelName) == "function" then
            channelName = channelInput:ResolveHistoricalChannelName(
                slot.channelName,
                slot.channelIndex,
                slot.channelBaseName,
                channelFallback
            )
        end
        if type(channelName) ~= "string" or channelName == ""
            or self:IsExplicitlySafeValue(channelName) ~= true
        then
            return nil, "history-format-channel-invalid"
        end
        message = "[" .. channelName .. "] " .. message
    end
    return message
end

local function DisplayRefreshedHook(frame)
    if not Adapter.enabled or not Adapter.displaySyncEnabled then return end
    local state = frameStates[frame]
    if not state or not state.ready then return end
    Dispatch("onDisplay", frame)
end

local function LayoutRefreshedHook(frame)
    if not Adapter.enabled then return end
    local state = frameStates[frame]
    if not state or not state.ready then return end
    Dispatch("onLayout", frame)
end

local function AddMessageHook(frame)
    if not Adapter.enabled
        or ((Adapter.clientFlavor == "mainline" or Adapter.clientFlavor == "forever")
            and Adapter.restrictionState ~= "OPEN")
    then
        return
    end
    local state = frameStates[frame]
    if not state or not state.ready or state.supported ~= true then return end
    DispatchAdd(state.addCallback, frame)
end

local function BackfillMessageHook(frame)
    if not Adapter.enabled then return end
    local state = frameStates[frame]
    if not state or not state.ready or state.supported ~= true then return end
    local callbacks = Adapter.callbacks
    if callbacks and type(callbacks.onBackfill) == "function" then
        Dispatch("onBackfill", frame)
    else
        Dispatch("onAdd", frame, "back")
    end
end

local function ClearMessagesHook(frame)
    if not Adapter.enabled then return end
    local state = frameStates[frame]
    if not state or not state.ready or state.supported ~= true then return end
    Dispatch("onInvalidate", frame, "CLEAR")
end

local function RemoveMessagesHook(frame)
    if not Adapter.enabled then return end
    local state = frameStates[frame]
    if not state or not state.ready or state.supported ~= true then return end
    Dispatch("onInvalidate", frame, "REMOVE")
end

local function TransformMessagesHook(frame)
    if not Adapter.enabled or Adapter.restrictionState ~= "OPEN" then return end
    local state = frameStates[frame]
    if not state or not state.ready or state.supported ~= true then return end
    Dispatch("onInvalidate", frame, "TRANSFORM")
    if channelTransformSuppressed[frame] == true then return end
    local callback = Adapter.channelTransformCallback
    if type(callback) == "function" and not pcall(callback, frame) then
        ReportCallbackFailure(Adapter.callbacks, "onChannelTransform")
    end
end

local function MaxLinesHook(frame)
    if not Adapter.enabled then return end
    if maxLinesWriteSuppressed[frame] == true then return end
    local state = frameStates[frame]
    if not state or not state.ready or state.supported ~= true then return end
    Dispatch("onInvalidate", frame, "MAX_LINES")
end

local function CopyHoverEnterHook(frame)
    if not Adapter.enabled then return end
    local state = frameStates[frame]
    if not state or not state.ready or state.supported ~= true then return end
    local callback = state.copyHoverEnterCallback
    if type(callback) == "function" and not pcall(callback, frame) then
        ReportCallbackFailure(Adapter.callbacks, "onCopyHoverEnter")
    end
end

local function CopyHoverLeaveHook(frame)
    if not Adapter.enabled then return end
    local state = frameStates[frame]
    if not state or not state.ready or state.supported ~= true then return end
    local callback = state.copyHoverLeaveCallback
    if type(callback) == "function" and not pcall(callback, frame) then
        ReportCallbackFailure(Adapter.callbacks, "onCopyHoverLeave")
    end
end

local function InteractionHoverHook(frame, hovered)
    if not Adapter.enabled then return end
    local state = frameStates[frame]
    if not state or not state.ready or state.supported ~= true then return end
    local callback = state.interactionHoverCallback
    if type(callback) == "function"
        and not pcall(callback, frame, hovered == true)
    then
        ReportCallbackFailure(Adapter.callbacks, "onInteractionHover")
    end
end

local function LineAlphaHook(line, value)
    if not Adapter.lineSyncEnabled then return end
    local overlay = lineOverlayByLine[line]
    local setter = lineAlphaSetterByLine[line]
    if not overlay or type(setter) ~= "function" then return end
    if not pcall(setter, overlay, value) then
        ReportCallbackFailure(Adapter.callbacks, "onLineAlpha")
    end
end

local function LineShowHook(line)
    if not Adapter.lineSyncEnabled then return end
    if lineShownStates[line] == true then return end
    lineShownStates[line] = true
    DispatchLineShow(line)
end

local function LineHideHook(line)
    if not Adapter.lineSyncEnabled then return end
    if lineShownStates[line] == false then return end
    lineShownStates[line] = false
    Dispatch("onLineHide", line)
end

local function RegisterDiscoveredFrame(frame)
    Adapter:RegisterFrame(frame)
end

local function FloatingFrameLoadedHook(frame)
    if not Adapter.enabled then return end
    trustedFrames[frame] = true
    Adapter:RegisterFrame(frame)
end

local function OpenWindowCompletedHook()
    if not Adapter.enabled then return end
    Adapter:ForEachFrame(RegisterDiscoveredFrame)
    Dispatch("onWindowsChanged", "FCF_OpenNewWindow")
end

local function FindTemporaryTypographyFrame(chatType, chatTarget)
    if Adapter:IsExplicitlySafeValue(chatType) ~= true
        or type(chatType) ~= "string"
    then
        return nil
    end
    if chatTarget ~= nil and Adapter:IsExplicitlySafeValue(chatTarget) ~= true then
        return nil
    end

    local names = _G.CHAT_FRAMES
    if type(names) ~= "table" then return nil end
    for _, name in pairs(names) do
        local frame = type(name) == "string" and _G[name]
        if frame
            and Adapter:IsExplicitlySafeValue(frame) == true
            and Adapter:IsExplicitlySafeValue(frame.isTemporary) == true
            and Adapter:IsExplicitlySafeValue(frame.inUse) == true
            and Adapter:IsExplicitlySafeValue(frame.chatType) == true
            and Adapter:IsExplicitlySafeValue(frame.chatTarget) == true
            and frame.isTemporary == true
            and frame.inUse == true
            and frame.chatType == chatType
            and frame.chatTarget == chatTarget
        then
            local prepared, reason = Adapter:PrepareTypographyFrame(frame)
            if prepared and reason == "temporary-whisper-typography-frame" then
                return frame
            end
        end
    end
    return nil
end

local function TemporaryWindowCompletedHook(chatType, chatTarget)
    if not Adapter.enabled then return end
    local frame = FindTemporaryTypographyFrame(chatType, chatTarget)
    if frame then
        Dispatch(
            "onTemporaryTypography",
            frame,
            true,
            "FCF_OpenTemporaryWindow"
        )
    end
end

local function CloseWindowCompletedHook(frame, fallback)
    if not Adapter.enabled then return end
    local closedFrame = fallback or frame
    if closedFrame and temporaryTypographyFrames[closedFrame] == true then
        temporaryTypographyFrames[closedFrame] = nil
        Dispatch("onTemporaryTypography", closedFrame, false, "FCF_Close")
        return
    end

    if closedFrame ~= nil then return end
    for candidate in pairs(temporaryTypographyFrames) do
        if Adapter:IsExplicitlySafeValue(candidate.inUse) == true
            and candidate.inUse ~= true
        then
            temporaryTypographyFrames[candidate] = nil
            Dispatch("onTemporaryTypography", candidate, false, "FCF_Close")
        end
    end
end

local function NativeFontSizeCompletedHook(_, chatFrame)
    if not Adapter.enabled then return end
    local frame = chatFrame
    if frame == nil then
        local getCurrent = _G.FCF_GetCurrentChatFrame
        if type(getCurrent) ~= "function" then return end
        local ok, current = pcall(getCurrent)
        if not ok then return end
        frame = current
    end
    local fontSize = Adapter:ReadStoredChatWindowFontSize(frame)
    if fontSize == nil then return end
    Dispatch("onNativeFontSizeChanged", frame, fontSize)
end

local function EnsureWindowLifecycleHooks()
    if type(hooksecurefunc) ~= "function" then return false end
    if not floatingHookInstalled then
        local mixin = _G.FloatingChatFrameMixin
        if type(mixin) == "table" and type(mixin.OnLoad) == "function" then
            local ok = pcall(hooksecurefunc, mixin, "OnLoad", FloatingFrameLoadedHook)
            floatingHookInstalled = ok == true
            if floatingHookInstalled then RecordPermanentHook() end
        end
    end
    if not openWindowHookInstalled and type(_G.FCF_OpenNewWindow) == "function" then
        local ok = pcall(
            hooksecurefunc,
            "FCF_OpenNewWindow",
            OpenWindowCompletedHook
        )
        openWindowHookInstalled = ok == true
        if openWindowHookInstalled then RecordPermanentHook() end
    end
    if not temporaryWindowHookInstalled
        and type(_G.FCF_OpenTemporaryWindow) == "function"
    then
        local ok = pcall(
            hooksecurefunc,
            "FCF_OpenTemporaryWindow",
            TemporaryWindowCompletedHook
        )
        temporaryWindowHookInstalled = ok == true
        if temporaryWindowHookInstalled then RecordPermanentHook() end
    end
    if not closeWindowHookInstalled and type(_G.FCF_Close) == "function" then
        local ok = pcall(hooksecurefunc, "FCF_Close", CloseWindowCompletedHook)
        closeWindowHookInstalled = ok == true
        if closeWindowHookInstalled then RecordPermanentHook() end
    end
    if (Adapter.clientFlavor == "mainline" or Adapter.clientFlavor == "forever")
        and not nativeFontSizeHookInstalled
        and type(_G.FCF_SetChatWindowFontSize) == "function"
    then
        local ok = pcall(
            hooksecurefunc,
            "FCF_SetChatWindowFontSize",
            NativeFontSizeCompletedHook
        )
        nativeFontSizeHookInstalled = ok == true
        if nativeFontSizeHookInstalled then RecordPermanentHook() end
    end
    return floatingHookInstalled and openWindowHookInstalled
end

local function AdapterEventHook(_, event, arg1, arg2)
    if not Adapter.enabled then return end
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_ChatFrameBase" or arg1 == "Blizzard_ChatFrame" then
            EnsureWindowLifecycleHooks()
            Adapter:ForEachFrame(RegisterDiscoveredFrame)
            Dispatch("onWindowsChanged", event)
        elseif arg1 == "Blizzard_CombatLog" then
            Dispatch("onWindowsChanged", "Blizzard_CombatLog")
        end
        return
    end
    if event == "UPDATE_CHAT_WINDOWS"
        or event == "UPDATE_FLOATING_CHAT_WINDOWS"
    then
        EnsureWindowLifecycleHooks()
        Adapter:ForEachFrame(RegisterDiscoveredFrame)
        Dispatch("onWindowsChanged", event)
        return
    end
    if event == "CHANNEL_UI_UPDATE" or event == "CHANNEL_COUNT_UPDATE" then
        Dispatch("onChannelsChanged", event)
        return
    end

    local backend = clientBackend
    local callback = backend and backend.HandleEvent
    if type(callback) ~= "function" then
        SetRestrictionState("UNKNOWN")
        return
    end
    local ok, handled, state = pcall(callback, backend, event, arg1, arg2)
    if not ok then
        SetRestrictionState("UNKNOWN")
        return
    end
    if handled ~= true then return end
    if state == "REFRESH" then
        Adapter:RefreshRestrictionState()
    else
        SetRestrictionState(state)
    end
end

local function InstallMethodHook(frame, methodName, callback)
    if type(hooksecurefunc) ~= "function" or type(frame[methodName]) ~= "function" then return false end
    return pcall(hooksecurefunc, frame, methodName, callback)
end

local function EnsureDisplayCallback(state, frame)
    if state.display then return true end
    local ok = pcall(frame.AddOnDisplayRefreshedCallback, frame, DisplayRefreshedHook)
    if ok then
        state.display = true
        RecordPermanentHook(state)
    end
    return ok
end

local function EnsureMethodHook(state, frame, stateKey, methodName, callback, optional)
    if state[stateKey] then return true end
    if type(frame[methodName]) ~= "function" then
        if optional then
            state[stateKey] = "unsupported"
            return true
        end
        return false
    end
    local ok = InstallMethodHook(frame, methodName, callback)
    if ok then
        state[stateKey] = true
        RecordPermanentHook(state)
    end
    return ok
end

function Adapter:ValidateFrame(frame)
    if frame == nil then return false, "missing-frame" end

    local isScrollingMessageFrame = _G.IsScrollingMessageFrame
    if type(isScrollingMessageFrame) ~= "function" then return false, "missing-native-frame-validator" end
    local ok, scrolling = pcall(isScrollingMessageFrame, frame)
    scrolling = ok and scrolling == true
    if not scrolling then return false, "not-scrolling-message-frame" end
    if type(frame.visibleLines) ~= "table" then return false, "missing-visible-lines" end
    if type(frame.historyBuffer) ~= "table" then return false, "missing-history-buffer" end
    if type(frame.historyBuffer.GetEntryAtIndex) ~= "function" then return false, "missing-history-entry-api" end
    if type(frame.AddOnDisplayRefreshedCallback) ~= "function" then return false, "missing-display-callback" end
    if type(frame.RefreshLayout) ~= "function" then return false, "missing-layout-refresh" end
    if type(frame.AddMessage) ~= "function" then return false, "missing-add-message" end
    if type(frame.GetNumMessages) ~= "function" then return false, "missing-message-count" end
    if type(frame.GetScrollOffset) ~= "function" then return false, "missing-scroll-offset" end
    if type(frame.GetMaxLines) ~= "function" then return false, "missing-max-lines" end
    if type(frame.GetSpacing) ~= "function" then return false, "missing-spacing" end
    if type(frame.GetIndentedWordWrap) ~= "function" then return false, "missing-indent-read" end
    if type(frame.GetInsertMode) ~= "function" then return false, "missing-insert-mode" end
    if type(frame.SetIndentedWordWrap) ~= "function" then return false, "missing-indent-api" end
    if type(frame.MarkLayoutDirty) ~= "function" then return false, "missing-layout-dirty" end
    return true
end

function Adapter:ClassifyFrame(frame)
    if self.clientBackendConflict or not clientBackend then
        return false, "client-backend-unavailable"
    end
    local callback = clientBackend.ClassifyFrame
    if type(callback) ~= "function" then
        if self.clientFlavor == "wrath" then return true, "legacy-supported-frame" end
        return false, "permanent-frame-classifier-unavailable"
    end
    local ok, supported, reason = pcall(callback, clientBackend, frame)
    if not ok or type(supported) ~= "boolean" then
        return false, "permanent-frame-classification-failed"
    end
    if supported ~= true then return false, reason or "unsupported-chat-frame" end
    return true, reason
end

function Adapter:ClassifyTypographyFrame(frame)
    if self.clientBackendConflict or not clientBackend then
        return false, "client-backend-unavailable"
    end
    local callback = clientBackend.ClassifyTypographyFrame
    if type(callback) ~= "function" then
        callback = clientBackend.ClassifyFrame
    end
    if type(callback) ~= "function" then
        return false, "typography-frame-classifier-unavailable"
    end
    local ok, supported, reason = pcall(callback, clientBackend, frame)
    if not ok or type(supported) ~= "boolean" then
        return false, "typography-frame-classifier-failed"
    end
    return supported, reason
end

function Adapter:PrepareTypographyFrame(frame)
    if not self.enabled then return false, "adapter-disabled" end
    trustedFrames[frame] = true
    local valid, validReason = self:ValidateFrame(frame)
    if not valid then return false, validReason end
    local supported, reason = self:ClassifyTypographyFrame(frame)
    if not supported then return false, reason end
    local state = frameStates[frame]
    if not state then
        state = { ready = false, supported = false }
        frameStates[frame] = state
    end
    state.typographyReady = true
    state.typographyTemporary = reason == "temporary-whisper-typography-frame"
    if state.typographyTemporary then
        temporaryTypographyFrames[frame] = true
    end
    return true, reason
end

function Adapter:RegisterFrame(frame)
    if not trustedFrames[frame] then return false, "untrusted-chat-frame" end
    local existing = frameStates[frame]
    local valid, reason = self:ValidateFrame(frame)
    if not valid then
        existing = existing or { ready = false }
        frameStates[frame] = existing
        existing.supported = false
        existing.classification = reason
        StatIncrement("adapterMismatches")
        Dispatch("onFrame", frame, false, reason)
        return false, reason
    end

    local supported, classification = self:ClassifyFrame(frame)
    if not supported then
        existing = existing or { ready = false }
        frameStates[frame] = existing
        existing.supported = false
        existing.classification = classification
        Dispatch("onFrame", frame, false, classification)
        return false, classification
    end

    if existing and existing.ready then
        if self.displaySyncEnabled and not EnsureDisplayCallback(existing, frame) then
            existing.supported = false
            existing.classification = "display-hook-install-failed"
            return false, existing.classification
        end
        existing.supported = true
        existing.classification = classification
        existing.addCallback = self.callbacks and self.callbacks.onAdd
        Dispatch("onFrame", frame, true, classification)
        return true, false
    end

    local state = existing or { ready = false }
    frameStates[frame] = state
    state.frame = frame
    state.visibleLines = frame.visibleLines
    state.historyBuffer = frame.historyBuffer
    state.historyGetter = frame.historyBuffer.GetEntryAtIndex
    state.scrollGetter = frame.GetScrollOffset
    state.addCallback = self.callbacks and self.callbacks.onAdd
    state.supported = true
    state.classification = classification

    local displayOK = not self.displaySyncEnabled
        or EnsureDisplayCallback(state, frame)
    local layoutOK = EnsureMethodHook(state, frame, "layout", "RefreshLayout", LayoutRefreshedHook, false)
    local addOK = EnsureMethodHook(state, frame, "add", "AddMessage", AddMessageHook, false)
    local backfillOK = EnsureMethodHook(state, frame, "backfill", "BackFillMessage", BackfillMessageHook, true)
    local clearOK = EnsureMethodHook(state, frame, "clear", "Clear", ClearMessagesHook, true)
    local removeOK = EnsureMethodHook(state, frame, "remove", "RemoveMessagesByPredicate", RemoveMessagesHook, true)
    local transformOK = EnsureMethodHook(state, frame, "transform", "TransformMessages", TransformMessagesHook, true)
    local maxLinesOK = EnsureMethodHook(state, frame, "maxLines", "SetMaxLines", MaxLinesHook, true)

    if not (displayOK and layoutOK and addOK and backfillOK and clearOK and removeOK and transformOK and maxLinesOK) then
        state.supported = false
        state.classification = "hook-install-failed"
        StatIncrement("adapterMismatches")
        Dispatch("onFrame", frame, false, "hook-install-failed")
        return false, "hook-install-failed"
    end

    state.ready = true
    Dispatch("onFrame", frame, true)
    return true, true
end

local function IsVisualRegionSupported(region)
    return region ~= nil
        and type(region.GetAlpha) == "function"
        and type(region.SetAlpha) == "function"
end

local function AppendRegion(target, region)
    if not IsVisualRegionSupported(region) then return false end
    target[#target + 1] = region
    return true
end

local function AppendTabRegion(target, region)
    if not AppendRegion(target, region)
        or type(region.GetTexture) ~= "function"
        or type(region.SetTexture) ~= "function"
        or type(region.SetColorTexture) ~= "function"
    then
        return false
    end
    return true
end

local function AppendTabFlashRegion(target, frameName)
    local flash = _G[frameName .. "TabFlash"]
    if flash == nil
        or type(flash.GetNumRegions) ~= "function"
        or type(flash.GetRegions) ~= "function"
    then
        return false
    end
    local countOK, count = pcall(flash.GetNumRegions, flash)
    if not countOK
        or Adapter:IsExplicitlySafeValue(count) ~= true
        or type(count) ~= "number"
        or count ~= 1
    then
        return false
    end
    local regionOK, region = pcall(flash.GetRegions, flash)
    return regionOK and AppendTabRegion(target, region)
end

local function AppendButtonTextures(target, button)
    if button == nil then return false end
    local initialCount = #target
    local getters = {
        "GetNormalTexture",
        "GetPushedTexture",
        "GetHighlightTexture",
        "GetDisabledTexture",
    }
    for index = 1, #getters do
        local callback = button[getters[index]]
        if type(callback) ~= "function" then return false end
        local ok, region = pcall(callback, button)
        if not ok then return false end
        if region ~= nil and not AppendRegion(target, region) then return false end
    end
    return #target > initialCount
end

local function AppendOptionalButtonTextures(target, button)
    if button == nil then return true end
    local initialCount = #target
    if AppendButtonTextures(target, button) then return true end
    for index = #target, initialCount + 1, -1 do target[index] = nil end
    return true
end

local function IsButtonObjectSupported(button)
    return button ~= nil
        and type(button.IsShown) == "function"
        and type(button.Show) == "function"
        and type(button.Hide) == "function"
        and type(button.GetAlpha) == "function"
        and type(button.SetAlpha) == "function"
        and type(button.IsMouseEnabled) == "function"
        and type(button.EnableMouse) == "function"
end

local function AppendButtonObject(target, button)
    if button == nil then return true end
    if not IsButtonObjectSupported(button) then
        return false
    end
    target[#target + 1] = button
    return true
end

local function IsEditBoxSupported(editBox)
    return editBox ~= nil
        and type(editBox.GetNumPoints) == "function"
        and type(editBox.GetPoint) == "function"
        and type(editBox.ClearAllPoints) == "function"
        and type(editBox.SetPoint) == "function"
end

local function IsInputLanguageButtonSupported(button)
    return button ~= nil
        and type(button.CreateTexture) == "function"
        and type(button.HookScript) == "function"
        and type(button.GetNormalTexture) == "function"
        and type(button.GetFontString) == "function"
        and type(button.SetText) == "function"
end

local function BuildEditBoxRegions(editBox)
    local regions = {}
    if not editBox then return regions end

    local editBoxName
    if type(editBox.GetName) == "function" then
        local ok, value = pcall(editBox.GetName, editBox)
        if ok and type(value) == "string" and value ~= "" then
            editBoxName = value
        end
    end

    if editBoxName then
        AppendRegion(regions, _G[editBoxName .. "Left"])
        AppendRegion(regions, _G[editBoxName .. "Mid"])
        AppendRegion(regions, _G[editBoxName .. "Right"])
    end
    AppendRegion(regions, editBox.focusLeft)
    AppendRegion(regions, editBox.focusMid)
    AppendRegion(regions, editBox.focusRight)
    return regions
end

local function BuildAppearanceTargets(frame)
    local getName = frame and frame.GetName
    if type(getName) ~= "function" then return nil, "appearance-frame-name-api-missing" end
    local nameOK, frameName = pcall(getName, frame)
    if not nameOK or type(frameName) ~= "string" or frameName == "" then
        return nil, "appearance-frame-name-invalid"
    end

    local tab = _G[frameName .. "Tab"]
    local editBox = frame.editBox
    local editBoxSource = editBox
    local buttonFrame = frame.buttonFrame
    local resizeButton = frame.ResizeButton
    local scrollBar = frame.ScrollBar
    local scrollToBottomButton = frame.ScrollToBottomButton
    local minimizeButton = buttonFrame and buttonFrame.minimizeButton
    local tabText = tab and tab.Text
    if not tab
        or not tabText
        or not frame.Background
    then
        return nil, "appearance-native-structure-mismatch"
    end
    if type(tabText.GetTextColor) ~= "function"
        or type(tabText.SetTextColor) ~= "function"
        or type(frame.CreateTexture) ~= "function"
        or type(tab.CreateTexture) ~= "function"
        or type(tab.GetPushedTextOffset) ~= "function"
        or type(tab.SetPushedTextOffset) ~= "function"
        or type(tab.HookScript) ~= "function"
    then
        return nil, "appearance-native-api-mismatch"
    end
    if not IsEditBoxSupported(editBox) then editBox = nil end
    local editBoxRegions = BuildEditBoxRegions(editBox)
    local inputLanguageButtonSource = editBox
        and _G[frameName .. "EditBoxLanguage"]
        or nil
    local inputLanguageButton = IsInputLanguageButtonSupported(inputLanguageButtonSource)
        and inputLanguageButtonSource
        or nil

    local tabRegions = {}
    for index = 1, #APPEARANCE_TAB_KEYS do
        if not AppendTabRegion(tabRegions, tab[APPEARANCE_TAB_KEYS[index]]) then
            return nil, "appearance-tab-region-mismatch"
        end
    end
    if not AppendTabFlashRegion(tabRegions, frameName) then
        return nil, "appearance-tab-flash-region-mismatch"
    end

    local frameRegions = {}
    local frameRegionBySuffix = {}
    local frameRegionSourcesBySuffix = {}
    if not AppendRegion(frameRegions, frame.Background) then
        return nil, "appearance-frame-background-mismatch"
    end
    for index = 1, #APPEARANCE_FRAME_REGION_SUFFIXES do
        local suffix = APPEARANCE_FRAME_REGION_SUFFIXES[index]
        local region = _G[frameName .. suffix]
        frameRegionSourcesBySuffix[suffix] = region
        if region and AppendRegion(frameRegions, region) then
            frameRegionBySuffix[suffix] = region
        end
    end

    local buttonRegions = {}
    local buttonObjects = {}
    local buttonFrameName = frameName .. "ButtonFrame"
    local buttonRegionBySuffix = {}
    local buttonRegionSourcesBySuffix = {}
    local buttonBackgroundSource = buttonFrame and buttonFrame.Background
    local buttonBackground = buttonBackgroundSource
    if buttonBackground then
        if not AppendRegion(buttonRegions, buttonBackground) then
            buttonBackground = nil
        end
    end
    for index = 1, #APPEARANCE_FRAME_REGION_SUFFIXES do
        local suffix = APPEARANCE_FRAME_REGION_SUFFIXES[index]
        local region = _G[buttonFrameName .. suffix]
        buttonRegionSourcesBySuffix[suffix] = region
        if region and AppendRegion(buttonRegions, region) then
            buttonRegionBySuffix[suffix] = region
        end
    end
    local buttonWindowRegionCount = #buttonRegions
    if frameName == "ChatFrame1" then
        AppendOptionalButtonTextures(buttonRegions, resizeButton)
    end
    AppendOptionalButtonTextures(buttonRegions, scrollToBottomButton)
    AppendOptionalButtonTextures(buttonRegions, minimizeButton)
    AppendButtonObject(buttonObjects, buttonFrame)
    if frameName == "ChatFrame1" then AppendButtonObject(buttonObjects, resizeButton) end
    AppendButtonObject(buttonObjects, scrollToBottomButton)
    AppendButtonObject(buttonObjects, minimizeButton)
    if scrollToBottomButton and scrollToBottomButton.Flash then
        AppendRegion(buttonRegions, scrollToBottomButton.Flash)
    end
    local scrollObjects = {}
    AppendButtonObject(scrollObjects, scrollBar)
    if frameName == "ChatFrame1" then
        for index = 1, #GLOBAL_CHAT_BUTTON_NAMES do
            local button = _G[GLOBAL_CHAT_BUTTON_NAMES[index]]
            AppendButtonObject(buttonObjects, button)
        end
    end

    return {
        frame = frame,
        frameName = frameName,
        background = frame.Background,
        tab = tab,
        tabText = tabText,
        editBox = editBox,
        editBoxSource = editBoxSource,
        editBoxCapable = editBox ~= nil,
        editBoxRegions = editBoxRegions,
        inputLanguageButtonSource = inputLanguageButtonSource,
        inputLanguageButton = inputLanguageButton,
        inputLanguageButtonCapable = inputLanguageButton ~= nil,
        buttonFrame = buttonFrame,
        buttonFrameCapable = IsButtonObjectSupported(buttonFrame),
        buttonBackgroundSource = buttonBackgroundSource,
        buttonBackground = buttonBackground,
        resizeButton = resizeButton,
        resizeButtonCapable = IsButtonObjectSupported(resizeButton),
        scrollBar = scrollBar,
        scrollBarCapable = IsButtonObjectSupported(scrollBar),
        scrollToBottomButton = scrollToBottomButton,
        scrollToBottomButtonCapable = IsButtonObjectSupported(scrollToBottomButton),
        minimizeButton = minimizeButton,
        minimizeButtonCapable = IsButtonObjectSupported(minimizeButton),
        frameRegions = frameRegions,
        frameRegionBySuffix = frameRegionBySuffix,
        frameRegionSourcesBySuffix = frameRegionSourcesBySuffix,
        tabRegions = tabRegions,
        buttonRegions = buttonRegions,
        buttonRegionBySuffix = buttonRegionBySuffix,
        buttonRegionSourcesBySuffix = buttonRegionSourcesBySuffix,
        buttonWindowRegionCount = buttonWindowRegionCount,
        buttonObjects = buttonObjects,
        scrollObjects = scrollObjects,
    }
end

local function AppearanceTabTargetsMatch(frame, targets)
    if type(targets) ~= "table" or frame ~= targets.frame then return false end
    local frameName = targets.frameName
    if type(frameName) ~= "string" or frameName == "" then
        local getName = frame and frame.GetName
        local ok
        ok, frameName = type(getName) == "function" and pcall(getName, frame)
        if not ok or type(frameName) ~= "string" or frameName == "" then return false end
    end
    local tab = _G[frameName .. "Tab"]
    if tab ~= targets.tab or (tab and tab.Text) ~= targets.tabText then return false end
    local regions = targets.tabRegions
    if type(regions) ~= "table" then return false end
    for index = 1, #APPEARANCE_TAB_KEYS do
        if regions[index] ~= tab[APPEARANCE_TAB_KEYS[index]] then return false end
    end
    local flash = _G[frameName .. "TabFlash"]
    if flash == nil
        or type(flash.GetNumRegions) ~= "function"
        or type(flash.GetRegions) ~= "function"
    then
        return false
    end
    local countOK, count = pcall(flash.GetNumRegions, flash)
    local regionOK, flashRegion = pcall(flash.GetRegions, flash)
    return countOK
        and regionOK
        and count == 1
        and regions[#APPEARANCE_TAB_KEYS + 1] == flashRegion
end

function Adapter:AppearanceTargetsMatch(frame, targets)
    if not self.enabled
        or trustedFrames[frame] ~= true
        or type(targets) ~= "table"
        or frame ~= targets.frame
        or frame.Background ~= targets.background
        or frame.editBox ~= targets.editBoxSource
        or IsEditBoxSupported(frame.editBox) ~= targets.editBoxCapable
        or _G[targets.frameName .. "EditBoxLanguage"] ~= targets.inputLanguageButtonSource
        or IsInputLanguageButtonSupported(targets.inputLanguageButtonSource)
            ~= targets.inputLanguageButtonCapable
        or frame.buttonFrame ~= targets.buttonFrame
        or IsButtonObjectSupported(frame.buttonFrame) ~= targets.buttonFrameCapable
        or (frame.buttonFrame and frame.buttonFrame.Background)
            ~= targets.buttonBackgroundSource
        or IsVisualRegionSupported(frame.buttonFrame and frame.buttonFrame.Background)
            ~= (targets.buttonBackground ~= nil)
        or frame.ResizeButton ~= targets.resizeButton
        or IsButtonObjectSupported(frame.ResizeButton) ~= targets.resizeButtonCapable
        or frame.ScrollBar ~= targets.scrollBar
        or IsButtonObjectSupported(frame.ScrollBar) ~= targets.scrollBarCapable
        or frame.ScrollToBottomButton ~= targets.scrollToBottomButton
        or IsButtonObjectSupported(frame.ScrollToBottomButton)
            ~= targets.scrollToBottomButtonCapable
        or (frame.buttonFrame and frame.buttonFrame.minimizeButton) ~= targets.minimizeButton
        or IsButtonObjectSupported(frame.buttonFrame and frame.buttonFrame.minimizeButton)
            ~= targets.minimizeButtonCapable
        or not AppearanceTabTargetsMatch(frame, targets)
    then
        return false
    end
    local frameRegions = targets.frameRegions
    local buttonRegions = targets.buttonRegions
    if type(frameRegions) ~= "table"
        or type(buttonRegions) ~= "table"
        or frameRegions[1] ~= frame.Background
    then
        return false
    end
    local frameName = targets.frameName
    local buttonFrameName = frameName .. "ButtonFrame"
    local frameRegionBySuffix = targets.frameRegionBySuffix or {}
    local buttonRegionBySuffix = targets.buttonRegionBySuffix or {}
    local frameRegionSourcesBySuffix = targets.frameRegionSourcesBySuffix or {}
    local buttonRegionSourcesBySuffix = targets.buttonRegionSourcesBySuffix or {}
    for index = 1, #APPEARANCE_FRAME_REGION_SUFFIXES do
        local suffix = APPEARANCE_FRAME_REGION_SUFFIXES[index]
        local frameRegion = _G[frameName .. suffix]
        local buttonRegion = _G[buttonFrameName .. suffix]
        if frameRegionSourcesBySuffix[suffix] ~= frameRegion
            or buttonRegionSourcesBySuffix[suffix] ~= buttonRegion
            or IsVisualRegionSupported(frameRegion)
                ~= (frameRegionBySuffix[suffix] ~= nil)
            or IsVisualRegionSupported(buttonRegion)
                ~= (buttonRegionBySuffix[suffix] ~= nil)
        then
            return false
        end
    end
    return true
end

function Adapter:AppearanceTabTargetsMatch(frame, targets)
    if not self.enabled or trustedFrames[frame] ~= true then return false end
    return AppearanceTabTargetsMatch(frame, targets)
end

function Adapter:InvalidateAppearanceTargets(frame, expected)
    local state = frameStates[frame]
    if not state then return false, "appearance-frame-state-missing" end
    if expected ~= nil and state.appearanceTargets ~= expected then
        return false, "appearance-target-generation-mismatch"
    end
    state.appearanceTargets = nil
    return true
end

local function BuildAppearanceTabTargets(frame)
    local getName = frame and frame.GetName
    if type(getName) ~= "function" then return nil, "appearance-tab-frame-name-api-missing" end
    local nameOK, frameName = pcall(getName, frame)
    if not nameOK or type(frameName) ~= "string" or frameName == "" then
        return nil, "appearance-tab-frame-name-invalid"
    end
    local tab = _G[frameName .. "Tab"]
    local tabText = tab and tab.Text
    if not tab
        or not tabText
        or type(tab.CreateTexture) ~= "function"
        or type(tab.GetPushedTextOffset) ~= "function"
        or type(tab.SetPushedTextOffset) ~= "function"
        or type(tab.HookScript) ~= "function"
        or type(tabText.GetTextColor) ~= "function"
        or type(tabText.SetTextColor) ~= "function"
    then
        return nil, "appearance-tab-native-structure-mismatch"
    end
    local tabRegions = {}
    for index = 1, #APPEARANCE_TAB_KEYS do
        if not AppendTabRegion(tabRegions, tab[APPEARANCE_TAB_KEYS[index]]) then
            return nil, "appearance-tab-region-mismatch"
        end
    end
    if not AppendTabFlashRegion(tabRegions, frameName) then
        return nil, "appearance-tab-flash-region-mismatch"
    end
    return {
        frame = frame,
        tab = tab,
        tabText = tabText,
        tabRegions = tabRegions,
    }
end

function Adapter:GetAppearanceTargets(frame)
    if not self.enabled or trustedFrames[frame] ~= true then
        return nil, "untrusted-chat-frame"
    end
    local supported, classification = self:ClassifyFrame(frame)
    if supported ~= true then
        return nil, classification or "unsupported-chat-frame"
    end
    local state = frameStates[frame]
    if not state then
        state = { ready = false }
        frameStates[frame] = state
    end
    if state.appearanceTargets then return state.appearanceTargets end

    local targets, reason = BuildAppearanceTargets(frame)
    if not targets then return nil, reason end
    state.appearanceTargets = targets
    return targets
end

function Adapter:ReadInputLanguageLabel(frame, editBox)
    if not self.enabled or trustedFrames[frame] ~= true then
        return nil, "input-language-frame-untrusted"
    end
    local targets, reason = self:GetAppearanceTargets(frame)
    if not targets or targets.editBox ~= editBox
        or not targets.inputLanguageButton
        or type(editBox.GetInputLanguage) ~= "function"
    then
        return nil, reason or "input-language-target-mismatch"
    end
    local ok, language = pcall(editBox.GetInputLanguage, editBox)
    if not ok or self:IsExplicitlySafeValue(language) ~= true
        or type(language) ~= "string" or language == "" or #language > 32
    then
        return nil, "input-language-value-invalid"
    end
    local label = _G["INPUT_" .. language]
    if self:IsExplicitlySafeValue(label) ~= true
        or type(label) ~= "string" or label == "" or #label > 16
    then
        return nil, "input-language-label-invalid"
    end
    return label
end

function Adapter:ReadInputChatColor(frame, editBox)
    if not self.enabled or trustedFrames[frame] ~= true then
        return nil, "input-color-frame-untrusted"
    end
    local targets, reason = self:GetAppearanceTargets(frame)
    if not targets or targets.editBox ~= editBox
        or type(editBox.GetTextColor) ~= "function"
    then
        return nil, reason or "input-color-target-mismatch"
    end
    local colorOK, r, g, b = pcall(editBox.GetTextColor, editBox)
    if not colorOK
        or self:IsExplicitlySafeValue(r) ~= true
        or self:IsExplicitlySafeValue(g) ~= true
        or self:IsExplicitlySafeValue(b) ~= true
        or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number"
        or not (r > -huge and r < huge)
        or not (g > -huge and g < huge)
        or not (b > -huge and b < huge)
        or r < 0 or r > 1 or g < 0 or g > 1 or b < 0 or b > 1
    then
        return nil, "input-color-value-invalid"
    end
    return r, g, b
end

function Adapter:ReadInputLanguageButtonOverhang(frame, editBox, button)
    if not self.enabled or trustedFrames[frame] ~= true then
        return nil, "input-language-geometry-frame-untrusted"
    end
    local targets, reason = self:GetAppearanceTargets(frame)
    if not targets or targets.editBox ~= editBox
        or targets.inputLanguageButton ~= button
        or type(editBox.GetRight) ~= "function"
        or type(button.GetRight) ~= "function"
    then
        return nil, reason or "input-language-geometry-target-mismatch"
    end
    local editOK, editRight = pcall(editBox.GetRight, editBox)
    local buttonOK, buttonRight = pcall(button.GetRight, button)
    if not editOK or not buttonOK
        or self:IsExplicitlySafeValue(editRight) ~= true
        or self:IsExplicitlySafeValue(buttonRight) ~= true
        or type(editRight) ~= "number" or type(buttonRight) ~= "number"
        or not (editRight > -huge and editRight < huge)
        or not (buttonRight > -huge and buttonRight < huge)
    then
        return nil, "input-language-geometry-invalid"
    end
    local overhang = buttonRight - editRight
    if overhang < -64 or overhang > 64 then
        return nil, "input-language-overhang-invalid"
    end
    return overhang
end

function Adapter:IsAppearanceFrameSupported(frame)
    if not self.enabled or trustedFrames[frame] ~= true then return false end
    local backend = clientBackend
    local classifier = backend and backend.ClassifyFrame
    if type(classifier) ~= "function" then return false end
    local ok, supported = pcall(classifier, backend, frame)
    return ok and supported == true
end

function Adapter:GetAppearanceTabTargets(frame)
    if not self.enabled or trustedFrames[frame] ~= true then
        return nil, "untrusted-chat-frame"
    end
    local backend = clientBackend
    local classifier = backend and backend.ClassifyAppearanceTab
    if type(classifier) ~= "function" then
        return nil, "appearance-tab-classifier-unavailable"
    end
    local ok, supported = pcall(classifier, backend, frame)
    if not ok or supported ~= true then
        return nil, "unsupported-appearance-tab"
    end
    return BuildAppearanceTabTargets(frame)
end

function Adapter:GetDockOverflowTargets()
    if not self.enabled then return nil, "adapter-disabled" end
    if (self.clientFlavor ~= "mainline" and self.clientFlavor ~= "forever") then
        return nil, "dock-overflow-mainline-only"
    end
    local dock = _G.GeneralDockManager
    local button = dock and dock.overflowButton
    local list = button and button.list
    if not dock
        or not button
        or not list
        or type(button.GetNormalTexture) ~= "function"
        or type(button.GetHighlightTexture) ~= "function"
        or type(button.HookScript) ~= "function"
        or type(button.CreateTexture) ~= "function"
        or not list.NineSlice
        or type(list.GetBackdropColor) ~= "function"
        or type(list.SetBackdropColor) ~= "function"
        or type(list.GetBackdropBorderColor) ~= "function"
        or type(list.SetBackdropBorderColor) ~= "function"
        or type(list.HookScript) ~= "function"
        or type(list.CreateTexture) ~= "function"
        or type(list.GetFrameStrata) ~= "function"
        or type(list.SetFrameStrata) ~= "function"
        or type(list.GetFrameLevel) ~= "function"
        or type(list.SetFrameLevel) ~= "function"
        or type(list.buttons) ~= "table"
    then
        return nil, "dock-overflow-structure-mismatch"
    end
    local normal = button:GetNormalTexture()
    local highlight = button:GetHighlightTexture()
    if not IsVisualRegionSupported(normal) or not IsVisualRegionSupported(highlight) then
        return nil, "dock-overflow-texture-mismatch"
    end
    return {
        dock = dock,
        button = button,
        list = list,
        nineSlice = list.NineSlice,
        normalTexture = normal,
        highlightTexture = highlight,
    }
end

function Adapter:GetCombatLogTargets()
    if not self.enabled then return nil, "adapter-disabled" end
    local frame = _G.ChatFrame2
    local backend = clientBackend
    local classifier = backend and backend.ClassifyCombatLogFrame
    if type(classifier) ~= "function" then
        return nil, "combat-log-classifier-unavailable"
    end
    if frame then trustedFrames[frame] = true end
    local ok, supported, reason = pcall(classifier, backend, frame)
    if not ok or supported ~= true then
        return nil, reason or "combat-log-unsupported"
    end
    if self:IsExplicitlySafeValue(frame) ~= true
        or self:CanCallProtected(frame) ~= true
    then
        return nil, "combat-log-frame-unsafe"
    end

    local tab = _G.ChatFrame2Tab
    local tabText = tab and tab.Text
    local quickBar = _G.CombatLogQuickButtonFrame_Custom
    local scrollBar = frame.ScrollBar
    local buttonFrame = frame.buttonFrame
    local resizeButton = frame.ResizeButton
    local scrollToBottomButton = frame.ScrollToBottomButton
    local dock = _G.GeneralDockManager
    local primaryTab = _G.ChatFrame1Tab
    local dockScrollFrame = dock and dock.scrollFrame
    local overflowButton = dock and dock.overflowButton
    local filterButton = quickBar and quickBar.AdditionalFilterButton
        or _G.CombatLogQuickButtonFrame_CustomAdditionalFilterButton
    local progress = quickBar and quickBar.ProgressBar
        or _G.CombatLogQuickButtonFrame_CustomProgressBar
    if not tab
        or not tabText
        or not quickBar
        or not IsButtonObjectSupported(scrollBar)
        or not IsButtonObjectSupported(buttonFrame)
        or not IsButtonObjectSupported(resizeButton)
        or not IsButtonObjectSupported(scrollToBottomButton)
        or not filterButton
        or type(frame.CreateTexture) ~= "function"
        or type(quickBar.CreateTexture) ~= "function"
        or type(frame.IsShown) ~= "function"
        or type(frame.Show) ~= "function"
        or type(frame.Hide) ~= "function"
        or type(tab.IsShown) ~= "function"
        or type(tabText.GetAlpha) ~= "function"
        or type(tabText.SetAlpha) ~= "function"
        or type(tabText.SetIgnoreParentAlpha) ~= "function"
        or type(quickBar.IsShown) ~= "function"
        or type(quickBar.GetHeight) ~= "function"
        or type(quickBar.GetNumPoints) ~= "function"
        or type(quickBar.GetPoint) ~= "function"
        or type(quickBar.ClearAllPoints) ~= "function"
        or type(quickBar.SetPoint) ~= "function"
        or not dock
        or dock.primary ~= _G.ChatFrame1
        or not primaryTab
        or not dockScrollFrame
        or not overflowButton
        or type(dockScrollFrame.GetNumPoints) ~= "function"
        or type(dockScrollFrame.GetPoint) ~= "function"
        or type(dockScrollFrame.ClearAllPoints) ~= "function"
        or type(dockScrollFrame.SetPoint) ~= "function"
        or type(overflowButton.IsShown) ~= "function"
    then
        return nil, "combat-log-target-structure-mismatch"
    end

    local frameRegions = {}
    if not AppendRegion(frameRegions, frame.Background) then
        return nil, "combat-log-background-mismatch"
    end
    local suffixes = {
        "TopLeftTexture",
        "BottomLeftTexture",
        "TopRightTexture",
        "BottomRightTexture",
        "LeftTexture",
        "RightTexture",
        "BottomTexture",
        "TopTexture",
    }
    for index = 1, #suffixes do
        if not AppendRegion(frameRegions, _G["ChatFrame2" .. suffixes[index]]) then
            return nil, "combat-log-border-mismatch"
        end
    end

    local quickRegions = {}
    local quickTexture = quickBar.Texture
        or _G.CombatLogQuickButtonFrame_CustomTexture
    if not AppendRegion(quickRegions, quickTexture)
        or not AppendButtonTextures(quickRegions, filterButton)
    then
        return nil, "combat-log-filter-texture-mismatch"
    end

    return {
        frame = frame,
        background = frame.Background,
        tab = tab,
        tabText = tabText,
        quickBar = quickBar,
        scrollBar = scrollBar,
        buttonFrame = buttonFrame,
        resizeButton = resizeButton,
        scrollToBottomButton = scrollToBottomButton,
        dock = dock,
        primaryTab = primaryTab,
        dockScrollFrame = dockScrollFrame,
        overflowButton = overflowButton,
        filterButton = filterButton,
        progress = progress,
        frameRegions = frameRegions,
        quickRegions = quickRegions,
    }
end

function Adapter:InstallCombatLogLifecycleHooks(
    targets,
    callback,
    visualCallback
)
    if type(targets) ~= "table"
        or type(callback) ~= "function"
        or type(visualCallback) ~= "function"
        or type(hooksecurefunc) ~= "function"
        or type(_G.FCF_FadeInChatFrame) ~= "function"
        or type(_G.FCF_FadeOutChatFrame) ~= "function"
        or type(_G.FCF_SetWindowAlpha) ~= "function"
        or targets.frame ~= _G.ChatFrame2
        or targets.tab ~= _G.ChatFrame2Tab
        or targets.tabText ~= _G.ChatFrame2Tab.Text
        or targets.quickBar ~= _G.CombatLogQuickButtonFrame_Custom
        or targets.scrollBar ~= _G.ChatFrame2.ScrollBar
        or targets.buttonFrame ~= _G.ChatFrame2.buttonFrame
        or targets.resizeButton ~= _G.ChatFrame2.ResizeButton
        or targets.scrollToBottomButton ~= _G.ChatFrame2.ScrollToBottomButton
        or targets.dock ~= _G.GeneralDockManager
        or targets.primaryTab ~= _G.ChatFrame1Tab
        or targets.dockScrollFrame ~= _G.GeneralDockManager.scrollFrame
        or targets.overflowButton ~= _G.GeneralDockManager.overflowButton
        or type(targets.frame.HookScript) ~= "function"
        or type(targets.tab.HookScript) ~= "function"
        or type(targets.quickBar.SetAlpha) ~= "function"
        or type(targets.quickBar.HookScript) ~= "function"
        or type(targets.scrollBar.HookScript) ~= "function"
        or type(targets.buttonFrame.HookScript) ~= "function"
        or type(targets.resizeButton.HookScript) ~= "function"
        or type(targets.scrollToBottomButton.HookScript) ~= "function"
    then
        return false, "combat-log-hook-structure-mismatch"
    end
    local ok = pcall(targets.frame.HookScript, targets.frame, "OnShow", callback)
        and pcall(targets.tab.HookScript, targets.tab, "OnShow", callback)
        and pcall(targets.quickBar.HookScript, targets.quickBar, "OnShow", callback)
        and pcall(targets.scrollBar.HookScript, targets.scrollBar, "OnShow", callback)
        and pcall(targets.buttonFrame.HookScript, targets.buttonFrame, "OnShow", callback)
        and pcall(targets.resizeButton.HookScript, targets.resizeButton, "OnShow", callback)
        and pcall(targets.scrollToBottomButton.HookScript, targets.scrollToBottomButton, "OnShow", callback)
        and pcall(hooksecurefunc, targets.scrollBar, "SetAlpha", callback)
        and pcall(hooksecurefunc, targets.buttonFrame, "SetAlpha", callback)
        and pcall(hooksecurefunc, targets.resizeButton, "SetAlpha", callback)
        and pcall(hooksecurefunc, targets.scrollToBottomButton, "SetAlpha", callback)
        and pcall(hooksecurefunc, targets.quickBar, "SetAlpha", visualCallback)
        and pcall(hooksecurefunc, "FCF_FadeInChatFrame", visualCallback)
        and pcall(hooksecurefunc, "FCF_FadeOutChatFrame", visualCallback)
        and pcall(hooksecurefunc, "FCF_SetWindowAlpha", visualCallback)
    return ok, ok and nil or "combat-log-hook-install-failed"
end

function Adapter:InstallCombatLogDockHooks(
    targets,
    tabColorCallback,
    dockCallback
)
    if type(targets) ~= "table"
        or type(tabColorCallback) ~= "function"
        or type(dockCallback) ~= "function"
        or type(hooksecurefunc) ~= "function"
        or type(_G.FCFTab_UpdateColors) ~= "function"
        or type(_G.FCFDock_UpdateTabs) ~= "function"
        or targets.frame ~= _G.ChatFrame2
        or targets.tab ~= _G.ChatFrame2Tab
        or targets.dock ~= _G.GeneralDockManager
    then
        return false, "combat-log-dock-hook-structure-mismatch"
    end
    local ok = pcall(hooksecurefunc, "FCFTab_UpdateColors", tabColorCallback)
        and pcall(hooksecurefunc, "FCFDock_UpdateTabs", dockCallback)
    return ok, ok and nil or "combat-log-dock-hook-install-failed"
end

function Adapter:InstallCombatLogQuickButtonHook(callback)
    if type(callback) ~= "function"
        or type(hooksecurefunc) ~= "function"
        or type(_G.Blizzard_CombatLog_Update_QuickButtons) ~= "function"
    then
        return false, "combat-log-quick-hook-unavailable"
    end
    local ok = pcall(
        hooksecurefunc,
        "Blizzard_CombatLog_Update_QuickButtons",
        callback
    )
    return ok, ok and nil or "combat-log-quick-hook-install-failed"
end

function Adapter:ApplyMainLayoutRect(frame, holder, width, height)
    if frame ~= _G.ChatFrame1
        or not self:IsTrustedSupportedFrame(frame)
        or holder == nil
        or type(holder.GetLeft) ~= "function"
        or type(holder.GetBottom) ~= "function"
        or type(width) ~= "number"
        or type(height) ~= "number"
        or not (width > 0 and width < huge)
        or not (height > 0 and height < huge)
    then
        return false, "layout-rect-structure-mismatch"
    end
    if self:CanCallProtected(frame) ~= true then
        return false, "layout-main-frame-protected"
    end

    local clearPoints = frame.ClearAllPointsBase
    local setPoint = frame.SetPointBase
    if type(clearPoints) ~= "function" or type(setPoint) ~= "function" then
        return false, "layout-base-anchor-api-missing"
    end

    local leftOK, left = pcall(holder.GetLeft, holder)
    local bottomOK, bottom = pcall(holder.GetBottom, holder)
    if not leftOK
        or not bottomOK
        or self:IsExplicitlySafeValue(left) ~= true
        or self:IsExplicitlySafeValue(bottom) ~= true
        or type(left) ~= "number"
        or type(bottom) ~= "number"
        or not (left > -huge and left < huge)
        or not (bottom > -huge and bottom < huge)
    then
        return false, "layout-holder-rect-invalid"
    end

    local ok = pcall(clearPoints, frame)
    if ok then
        ok = pcall(
            setPoint,
            frame,
            "BOTTOMLEFT",
            _G.UIParent,
            "BOTTOMLEFT",
            left,
            bottom
        )
    end
    if ok then
        ok = pcall(
            setPoint,
            frame,
            "TOPRIGHT",
            _G.UIParent,
            "BOTTOMLEFT",
            left + width,
            bottom + height
        )
    end
    if not ok then return false, "layout-rect-write-failed" end

    local countOK, count = pcall(frame.GetNumPoints, frame)
    local firstOK, firstPoint, firstRelativeTo, firstRelativePoint, firstX, firstY =
        pcall(frame.GetPoint, frame, 1)
    local secondOK, secondPoint, secondRelativeTo, secondRelativePoint, secondX, secondY =
        pcall(frame.GetPoint, frame, 2)
    local tolerance = 0.01
    local gui = YUI.GUI
    if gui and type(gui.GetPixelSize) == "function" then
        local pixelOK, pixel = pcall(gui.GetPixelSize, gui, frame, 1, 1)
        if pixelOK
            and self:IsExplicitlySafeValue(pixel) == true
            and type(pixel) == "number"
            and pixel > 0
            and pixel < huge
        then
            tolerance = pixel
        end
    end
    local function PointMatches(
        point,
        relativeTo,
        relativePoint,
        x,
        y,
        expectedPoint,
        expectedX,
        expectedY
    )
        return self:IsExplicitlySafeValue(point) == true
            and self:IsExplicitlySafeValue(relativeTo) == true
            and self:IsExplicitlySafeValue(relativePoint) == true
            and self:IsExplicitlySafeValue(x) == true
            and self:IsExplicitlySafeValue(y) == true
            and point == expectedPoint
            and relativeTo == _G.UIParent
            and relativePoint == "BOTTOMLEFT"
            and type(x) == "number"
            and type(y) == "number"
            and abs(x - expectedX) <= tolerance
            and abs(y - expectedY) <= tolerance
    end
    local firstBottom = firstOK and PointMatches(
        firstPoint,
        firstRelativeTo,
        firstRelativePoint,
        firstX,
        firstY,
        "BOTTOMLEFT",
        left,
        bottom
    )
    local firstTop = firstOK and PointMatches(
        firstPoint,
        firstRelativeTo,
        firstRelativePoint,
        firstX,
        firstY,
        "TOPRIGHT",
        left + width,
        bottom + height
    )
    local secondBottom = secondOK and PointMatches(
        secondPoint,
        secondRelativeTo,
        secondRelativePoint,
        secondX,
        secondY,
        "BOTTOMLEFT",
        left,
        bottom
    )
    local secondTop = secondOK and PointMatches(
        secondPoint,
        secondRelativeTo,
        secondRelativePoint,
        secondX,
        secondY,
        "TOPRIGHT",
        left + width,
        bottom + height
    )
    if not countOK
        or self:IsExplicitlySafeValue(count) ~= true
        or count ~= 2
        or not ((firstBottom and secondTop) or (firstTop and secondBottom))
    then
        return false, "layout-rect-readback-mismatch"
    end
    return true
end

function Adapter:InstallMainLayoutHooks(frame, holder, callback)
    local editModeManager = _G.EditModeManagerFrame
    if type(callback) ~= "function"
        or frame ~= _G.ChatFrame1
        or not self:IsTrustedSupportedFrame(frame)
        or holder == nil
        or type(holder.SetPoint) ~= "function"
        or type(frame.ApplySystemAnchor) ~= "function"
        or editModeManager == nil
        or type(editModeManager.UpdateLayoutInfo) ~= "function"
        or type(editModeManager.HookScript) ~= "function"
        or type(hooksecurefunc) ~= "function"
    then
        return false, "layout-hook-structure-mismatch"
    end

    local function HolderLayoutChanged()
        callback(frame, "holder")
    end

    local function EditModeLayoutChanged()
        callback(frame, "edit-mode")
    end

    local function EditModeShown()
        callback(frame, "edit-mode-show")
    end

    local ok = pcall(hooksecurefunc, holder, "SetPoint", HolderLayoutChanged)
        and pcall(hooksecurefunc, frame, "ApplySystemAnchor", EditModeLayoutChanged)
        and pcall(
            hooksecurefunc,
            editModeManager,
            "UpdateLayoutInfo",
            EditModeLayoutChanged
        )
        and pcall(editModeManager.HookScript, editModeManager, "OnShow", EditModeShown)
    return ok, ok and nil or "layout-hook-install-failed"
end

function Adapter:ResolveAppearanceTabFrame(tab)
    if not self.enabled or self:IsExplicitlySafeValue(tab) ~= true then
        return nil, "unsafe-appearance-tab"
    end
    local names = _G.CHAT_FRAMES
    local backend = clientBackend
    local classifier = backend and backend.ClassifyAppearanceTab
    if type(names) ~= "table" or type(classifier) ~= "function" then
        return nil, "appearance-tab-resolver-unavailable"
    end

    for index = 1, #names do
        local frameName = names[index]
        if self:IsExplicitlySafeValue(frameName) == true
            and type(frameName) == "string"
            and frameName ~= ""
        then
            local candidateTab = _G[frameName .. "Tab"]
            if self:IsExplicitlySafeValue(candidateTab) == true
                and candidateTab == tab
            then
                local frame = _G[frameName]
                if self:IsExplicitlySafeValue(frame) ~= true then
                    return nil, "unsafe-appearance-tab-frame"
                end
                trustedFrames[frame] = true
                local ok, supported, reason = pcall(classifier, backend, frame)
                if not ok or supported ~= true then
                    return nil, reason or "unsupported-appearance-tab"
                end
                return frame
            end
        end
    end
    return nil, "unsupported-appearance-tab"
end

function Adapter:IsAppearanceTabSelected(frame)
    if not self.enabled or trustedFrames[frame] ~= true then
        return nil, "untrusted-chat-frame"
    end
    local backend = clientBackend
    local classifier = backend and backend.ClassifyAppearanceTab
    local reader = backend and backend.IsAppearanceTabSelected
    if type(classifier) ~= "function" or type(reader) ~= "function" then
        return nil, "appearance-tab-selection-unavailable"
    end
    local classifyOK, supported = pcall(classifier, backend, frame)
    if not classifyOK or supported ~= true then
        return nil, "unsupported-appearance-tab"
    end
    local readOK, selected, reason = pcall(reader, backend, frame)
    if not readOK
        or self:IsExplicitlySafeValue(selected) ~= true
        or type(selected) ~= "boolean"
    then
        return nil, reason or "appearance-tab-selection-unsafe"
    end
    return selected
end

function Adapter:IsTrustedSupportedFrame(frame)
    if not self.enabled or trustedFrames[frame] ~= true then return false end
    local state = frameStates[frame]
    return state ~= nil and state.ready == true and state.supported == true
end

function Adapter:ResolveAppearanceFrameByID(id)
    if not self.enabled
        or self:IsExplicitlySafeValue(id) ~= true
        or type(id) ~= "number"
        or id < 1
        or id > 32
        or floor(id) ~= id
        or type(_G.FCF_GetChatFrameByID) ~= "function"
    then
        return nil, "appearance-frame-id-invalid"
    end
    local ok, frame = pcall(_G.FCF_GetChatFrameByID, id)
    if not ok or self:IsExplicitlySafeValue(frame) ~= true or frame == nil then
        return nil, "appearance-frame-id-unresolved"
    end
    trustedFrames[frame] = true
    local registered, reason = self:RegisterFrame(frame)
    if not registered then return nil, reason end
    return frame
end

function Adapter:ForEachGlobalChatButton(callback)
    if not self.enabled or type(callback) ~= "function" then return 0 end
    local count = 0
    for index = 1, #GLOBAL_CHAT_BUTTON_NAMES do
        local button = _G[GLOBAL_CHAT_BUTTON_NAMES[index]]
        if button ~= nil then
            local probe = {}
            if AppendButtonObject(probe, button) then
                count = count + 1
                callback(button)
            end
        end
    end
    return count
end

function Adapter:ForEachFrame(callback)
    if type(callback) ~= "function" then return 0 end
    local names = _G.CHAT_FRAMES
    if type(names) ~= "table" then return 0 end

    local count = 0
    for index = 1, #names do
        local frame = _G[names[index]]
        if frame then
            trustedFrames[frame] = true
            count = count + 1
            callback(frame)
        end
    end
    return count
end

function Adapter:ForEachSupportedFrame(callback)
    if type(callback) ~= "function" then return 0 end
    local names = _G.CHAT_FRAMES
    if type(names) ~= "table" then return 0 end

    local count = 0
    for index = 1, #names do
        local frame = _G[names[index]]
        if frame then
            trustedFrames[frame] = true
            local registered = self:RegisterFrame(frame)
            if registered then
                count = count + 1
                callback(frame)
            end
        end
    end
    return count
end

function Adapter:ForEachTypographyFrame(callback)
    if not self.enabled or type(callback) ~= "function" then return 0 end
    local names = _G.CHAT_FRAMES
    if type(names) ~= "table" then return 0 end

    local count = 0
    for index = 1, #names do
        local frame = _G[names[index]]
        if frame then
            local prepared = self:PrepareTypographyFrame(frame)
            if prepared then
                count = count + 1
                callback(frame)
            end
        end
    end
    return count
end

function Adapter:ForEachAppearanceFrame(callback)
    if not self.enabled or type(callback) ~= "function" then return 0 end
    local names = _G.CHAT_FRAMES
    local backend = clientBackend
    local classifier = backend and backend.ClassifyFrame
    if type(names) ~= "table" or type(classifier) ~= "function" then return 0 end

    local count = 0
    for index = 1, #names do
        local frame = _G[names[index]]
        if frame then
            trustedFrames[frame] = true
            local ok, supported = pcall(classifier, backend, frame)
            if ok and supported == true then
                count = count + 1
                callback(frame)
            end
        end
    end
    return count
end

function Adapter:ForEachAppearanceTab(callback)
    if type(callback) ~= "function" then return 0 end
    local names = _G.CHAT_FRAMES
    local backend = clientBackend
    local classifier = backend and backend.ClassifyAppearanceTab
    if type(names) ~= "table" or type(classifier) ~= "function" then return 0 end

    local count = 0
    for index = 1, #names do
        local frame = _G[names[index]]
        if frame then
            trustedFrames[frame] = true
            local ok, supported = pcall(classifier, backend, frame)
            if ok and supported == true then
                count = count + 1
                callback(frame)
            end
        end
    end
    return count
end

function Adapter:GetVisibleEntry(frame, index)
    local lines = frame and frame.visibleLines
    local line = lines and lines[index]
    return line and line.messageInfo or nil
end

function Adapter:GetVisibleLine(frame, index)
    local lines = frame and frame.visibleLines
    return lines and lines[index] or nil
end

function Adapter:GetHistoryEntry(frame, index)
    local buffer = frame and frame.historyBuffer
    local getter = buffer and buffer.GetEntryAtIndex
    if type(getter) ~= "function" then return nil end
    local ok, entry = pcall(getter, buffer, index)
    if not ok then return nil end
    return entry
end

function Adapter:GetHistoryEntryInCallback(frame, index)
    if not self.enabled or trustedFrames[frame] ~= true then return nil end
    local state = frameStates[frame]
    if not state or not state.ready then return nil end
    local buffer = state.historyBuffer
    local getter = state.historyGetter
    if frame.historyBuffer ~= buffer
        or buffer.GetEntryAtIndex ~= getter
        or type(getter) ~= "function"
    then
        error("ychat-native-callback-signature-changed")
    end
    return getter(buffer, index)
end

function Adapter:GetHistoryCursor(frame)
    if not self.enabled or trustedFrames[frame] ~= true then return nil end
    local state = frameStates[frame]
    if not state or not state.ready or state.frame ~= frame then return nil end
    return state
end

function Adapter:GetHistoryEntryFromCursorInCallback(frame, cursor, index)
    if not self.enabled
        or not cursor
        or cursor.ready ~= true
        or cursor.frame ~= frame
    then
        return nil
    end
    local buffer = cursor.historyBuffer
    local getter = cursor.historyGetter
    if frame.historyBuffer ~= buffer
        or buffer.GetEntryAtIndex ~= getter
        or type(getter) ~= "function"
    then
        error("ychat-native-callback-signature-changed")
    end
    return getter(buffer, index)
end

function Adapter:VisitDisplayEntriesInCallback(frame, offset, visitor, context)
    if not self.enabled or trustedFrames[frame] ~= true then
        return nil, 0, "untrusted-chat-frame"
    end
    local state = frameStates[frame]
    if not state or not state.ready then return nil, 0, "frame-not-ready" end
    local lines = state.visibleLines
    local buffer = state.historyBuffer
    local getter = state.historyGetter
    if frame.visibleLines ~= lines
        or frame.historyBuffer ~= buffer
        or buffer.GetEntryAtIndex ~= getter
        or type(getter) ~= "function"
    then
        error("ychat-native-callback-signature-changed")
    end
    if visitor ~= nil and type(visitor) ~= "function" then
        error("ychat-display-visitor-invalid")
    end

    local lineCount = #lines
    local comparisons = 0
    for index = 1, lineCount do
        local line = lines[index]
        local visibleEntry = line and line.messageInfo or nil
        local bufferIndex = index + offset
        local historyEntry = getter(buffer, bufferIndex)
        if visibleEntry ~= nil or historyEntry ~= nil then
            comparisons = comparisons + 1
            if visibleEntry ~= historyEntry then
                return nil, comparisons, "identity-mismatch"
            end
        end
        if visitor then
            local visited, reason =
                visitor(context, index, line, visibleEntry, bufferIndex)
            if visited ~= true then
                return nil, comparisons, reason or "display-visitor-failed"
            end
        end
    end
    return lineCount, comparisons
end

function Adapter:GetProbeDisplayLinesInCallback(frame)
    if not self.enabled or trustedFrames[frame] ~= true then
        return nil, 0, "untrusted-chat-frame"
    end
    local state = frameStates[frame]
    if not state or not state.ready then return nil, 0, "frame-not-ready" end
    local lines = state.visibleLines
    local buffer = state.historyBuffer
    local getter = state.historyGetter
    if frame.visibleLines ~= lines
        or frame.historyBuffer ~= buffer
        or buffer.GetEntryAtIndex ~= getter
        or type(getter) ~= "function"
    then
        error("ychat-native-callback-signature-changed")
    end
    return lines, #lines
end

function Adapter:VisitProbeEntriesInCallback(frame, offset, visitor, context)
    local lines, lineCount, lineReason =
        self:GetProbeDisplayLinesInCallback(frame)
    if not lines then return nil, 0, lineReason end
    if type(visitor) ~= "function" then
        error("ychat-probe-visitor-invalid")
    end

    local comparisons = 0
    for index = 1, lineCount do
        local line = lines[index]
        local visibleEntry = line and line.messageInfo or nil
        if visibleEntry ~= nil then comparisons = comparisons + 1 end
        local visited, reason =
            visitor(context, index, line, visibleEntry, index + offset)
        if visited ~= true then
            return nil, comparisons, reason or "display-visitor-failed"
        end
    end
    return lineCount, comparisons
end

local function ValidateFiniteNumber(value)
    if type(value) ~= "number" then return nil, "type-mismatch" end
    if not (value > -huge and value < huge) then return nil, "out-of-range" end
    return value
end

function Adapter:ReadHistoricalMessageColor(event)
    if (self.clientFlavor ~= "mainline" and self.clientFlavor ~= "forever") or type(event) ~= "string"
        or sub(event, 1, 9) ~= "CHAT_MSG_"
        or self:IsExplicitlySafeValue(event) ~= true
    then
        return nil
    end
    local info = type(_G.ChatTypeInfo) == "table" and _G.ChatTypeInfo[sub(event, 10)] or nil
    if type(info) ~= "table" then return nil end
    local red = ValidateFiniteNumber(info.r)
    local green = ValidateFiniteNumber(info.g)
    local blue = ValidateFiniteNumber(info.b)
    if red == nil or green == nil or blue == nil
        or red < 0 or red > 1 or green < 0 or green > 1 or blue < 0 or blue > 1
    then
        return nil
    end
    return red, green, blue
end

local function ValidatePositiveFiniteNumber(value)
    local number, reason = ValidateFiniteNumber(value)
    if number == nil then return nil, reason end
    if number <= 0 then return nil, "out-of-range" end
    return number
end

local function CallIsSecret(callback, value)
    return callback(value) == true
end

local function IsSecretValue(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(CallIsSecret, issecretvalue, value)
    return not ok or secret == true
end

local function IsExplicitlySafeValue(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(CallIsSecret, issecretvalue, value)
    return ok and secret == false
end

function Adapter:IsExplicitlySafeValue(value)
    return IsExplicitlySafeValue(value)
end

function Adapter:IsObjectMouseOver(object)
    local callback = object and object.IsMouseOver
    if type(callback) ~= "function" then return false, "mouse-over-api-missing" end
    local ok, value = pcall(callback, object)
    if not ok
        or IsExplicitlySafeValue(value) ~= true
        or type(value) ~= "boolean"
    then
        return false, "mouse-over-read-unsafe"
    end
    return value
end

local function ReadHistoricalTimestamp(entry)
    return entry.timestamp
end

function Adapter:ReadHistoricalEntrySample(frame, index)
    if not self.enabled or trustedFrames[frame] ~= true then
        return nil, nil, "historical-entry-untrusted-frame"
    end
    local state = frameStates[frame]
    if not state or state.ready ~= true or state.supported ~= true then
        return nil, nil, "historical-entry-unsupported-frame"
    end
    if type(index) ~= "number" or index < 1 or floor(index) ~= index then
        return nil, nil, "historical-entry-index-invalid"
    end

    local entry = self:GetHistoryEntry(frame, index)
    if entry == nil or not IsExplicitlySafeValue(entry) then
        return nil, nil, "historical-entry-unavailable"
    end
    local timestampOK, timestamp = pcall(ReadHistoricalTimestamp, entry)
    if not timestampOK
        or not IsExplicitlySafeValue(timestamp)
        or type(timestamp) ~= "number"
        or not (timestamp >= 0 and timestamp < huge)
    then
        return entry, nil, "historical-timestamp-unavailable"
    end
    return entry, timestamp
end

local function HideOwnedTooltip(frame)
    local tooltip = GameTooltip
    local expectedOwner = tooltipOwnerByFrame[frame]
    if not tooltip or Adapter.activeTooltipFrame ~= frame or expectedOwner == nil then
        return true
    end

    local getOwner = tooltip.GetOwner
    if type(getOwner) ~= "function" or type(tooltip.Hide) ~= "function" then
        return false, "tooltip-cleanup-api-missing"
    end
    local ownerOK, owner = pcall(getOwner, tooltip)
    if not ownerOK or not IsExplicitlySafeValue(owner) then
        return false, "tooltip-owner-read-failed"
    end
    if owner == expectedOwner and not pcall(tooltip.Hide, tooltip) then
        return false, "tooltip-hide-failed"
    end
    tooltipOwnerByFrame[frame] = nil
    Adapter.activeTooltipFrame = nil
    Adapter.tooltipCleanupPending = false
    Adapter.tooltipCleanupReason = nil
    return true
end

local function RecordTooltipCleanupFailure(reason)
    Adapter.tooltipCleanupPending = true
    Adapter.tooltipCleanupReason = reason or "tooltip-cleanup-failed"
end

local function HyperlinkEnter(
    _,
    frame,
    link,
    _,
    region,
    boundsLeft,
    boundsBottom,
    boundsWidth,
    boundsHeight
)
    if not Adapter.tooltipEnabled
        or not IsTooltipInteractionState(Adapter.restrictionState)
        or not Adapter:IsTrustedSupportedFrame(frame)
        or not IsExplicitlySafeValue(link)
        or type(link) ~= "string"
        or find(link, "^item:") ~= 1
    then
        return
    end

    local anchor = Adapter.tooltipAnchor
    if VALID_TOOLTIP_ANCHORS[anchor] ~= true then return end
    if not IsExplicitlySafeValue(region)
        or not IsExplicitlySafeValue(boundsLeft)
        or not IsExplicitlySafeValue(boundsBottom)
        or not IsExplicitlySafeValue(boundsWidth)
        or not IsExplicitlySafeValue(boundsHeight)
        or type(boundsLeft) ~= "number"
        or type(boundsBottom) ~= "number"
        or type(boundsWidth) ~= "number"
        or type(boundsHeight) ~= "number"
        or boundsLeft ~= boundsLeft
        or boundsBottom ~= boundsBottom
        or boundsWidth <= 0
        or boundsHeight <= 0
    then
        return
    end

    local centerX = boundsLeft + boundsWidth * 0.5
    local centerY = boundsBottom + boundsHeight * 0.5
    local point
    local x
    local y
    if anchor == "ANCHOR_TOP" then
        point, x, y = "BOTTOM", centerX, boundsBottom + boundsHeight + TOOLTIP_LINK_CLEARANCE
    elseif anchor == "ANCHOR_BOTTOM" then
        point, x, y = "TOP", centerX, boundsBottom - TOOLTIP_LINK_CLEARANCE
    elseif anchor == "ANCHOR_LEFT" then
        point, x, y = "RIGHT", boundsLeft - TOOLTIP_LINK_CLEARANCE, centerY
    elseif anchor == "ANCHOR_RIGHT" then
        point, x, y = "LEFT", boundsLeft + boundsWidth + TOOLTIP_LINK_CLEARANCE, centerY
    elseif anchor == "ANCHOR_TOPLEFT" then
        point, x, y = "BOTTOMRIGHT", boundsLeft - TOOLTIP_LINK_CLEARANCE,
            boundsBottom + boundsHeight + TOOLTIP_LINK_CLEARANCE
    elseif anchor == "ANCHOR_TOPRIGHT" then
        point, x, y = "BOTTOMLEFT", boundsLeft + boundsWidth + TOOLTIP_LINK_CLEARANCE,
            boundsBottom + boundsHeight + TOOLTIP_LINK_CLEARANCE
    elseif anchor == "ANCHOR_BOTTOMLEFT" then
        point, x, y = "TOPRIGHT", boundsLeft - TOOLTIP_LINK_CLEARANCE,
            boundsBottom - TOOLTIP_LINK_CLEARANCE
    else
        point, x, y = "TOPLEFT", boundsLeft + boundsWidth + TOOLTIP_LINK_CLEARANCE,
            boundsBottom - TOOLTIP_LINK_CLEARANCE
    end

    local tooltip = GameTooltip
    if not tooltip
        or type(tooltip.SetOwner) ~= "function"
        or type(tooltip.ClearAllPoints) ~= "function"
        or type(tooltip.SetPoint) ~= "function"
        or type(tooltip.SetHyperlink) ~= "function"
    then
        return
    end

    local frameAllowed = Adapter:CanCallProtected(frame)
    local regionAllowed = Adapter:CanCallProtected(region)
    local tooltipAllowed = Adapter:CanCallProtected(tooltip)
    if frameAllowed ~= true or regionAllowed ~= true or tooltipAllowed ~= true then return end
    local previousFrame = Adapter.activeTooltipFrame
    if previousFrame and previousFrame ~= frame then
        local hidden, hideReason = HideOwnedTooltip(previousFrame)
        if not hidden then
            RecordTooltipCleanupFailure(hideReason)
            return
        end
    end
    tooltipOwnerByFrame[frame] = region
    Adapter.activeTooltipFrame = frame
    if not pcall(tooltip.SetOwner, tooltip, region, "ANCHOR_PRESERVE")
        or not pcall(tooltip.ClearAllPoints, tooltip)
        or not pcall(tooltip.SetPoint, tooltip, point, region, "BOTTOMLEFT", x, y)
    then
        local hidden, hideReason = HideOwnedTooltip(frame)
        if not hidden then RecordTooltipCleanupFailure(hideReason) end
        return
    end
    if not pcall(tooltip.SetHyperlink, tooltip, link) then
        local hidden, hideReason = HideOwnedTooltip(frame)
        if not hidden then RecordTooltipCleanupFailure(hideReason) end
    end
end

local function HyperlinkLeave(_, frame)
    local hidden, hideReason = HideOwnedTooltip(frame)
    if not hidden then RecordTooltipCleanupFailure(hideReason) end
end

function Adapter:SetHyperlinkTooltipEnabled(enabled, anchor)
    enabled = enabled == true
    if anchor ~= nil then
        if type(anchor) ~= "string" or VALID_TOOLTIP_ANCHORS[anchor] ~= true then
            return false, "tooltip-anchor-invalid"
        end
        self.tooltipAnchor = anchor
    end

    if not enabled then
        self.tooltipEnabled = false
        local cleanupReason
        local activeFrame = self.activeTooltipFrame
        if activeFrame then
            local hidden, hideReason = HideOwnedTooltip(activeFrame)
            if not hidden then cleanupReason = hideReason end
        end
        local registry = EventRegistry
        if self.tooltipListenerCount > 0 then
            if not registry or type(registry.UnregisterCallback) ~= "function" then
                RecordTooltipCleanupFailure(
                    cleanupReason or "tooltip-registry-cleanup-api-missing"
                )
                return false, "tooltip-registry-cleanup-api-missing"
            end
            local enterOK = pcall(
                registry.UnregisterCallback,
                registry,
                "ChatFrame.OnHyperlinkEnter",
                self
            )
            local leaveOK = pcall(
                registry.UnregisterCallback,
                registry,
                "ChatFrame.OnHyperlinkLeave",
                self
            )
            if not enterOK or not leaveOK then
                cleanupReason = cleanupReason or "tooltip-listener-cleanup-failed"
            else
                self.tooltipListenerCount = 0
            end
        end
        UpdateListenerGauge()
        if cleanupReason then
            RecordTooltipCleanupFailure(cleanupReason)
            return false, cleanupReason
        end
        self.tooltipCleanupPending = false
        self.tooltipCleanupReason = nil
        return true
    end

    if not self.enabled then return false, "adapter-disabled" end
    if self.tooltipCleanupPending then
        return false, self.tooltipCleanupReason or "tooltip-cleanup-pending"
    end
    if self.tooltipEnabled and self.tooltipListenerCount == 2 then return true end
    local registry = EventRegistry
    if not registry
        or type(registry.RegisterCallback) ~= "function"
        or type(registry.UnregisterCallback) ~= "function"
    then
        return false, "tooltip-registry-unavailable"
    end

    local enterOK = pcall(
        registry.RegisterCallback,
        registry,
        "ChatFrame.OnHyperlinkEnter",
        HyperlinkEnter,
        self
    )
    if not enterOK then return false, "tooltip-enter-listener-failed" end
    self.tooltipListenerCount = 1
    UpdateListenerGauge()
    local leaveOK = pcall(
        registry.RegisterCallback,
        registry,
        "ChatFrame.OnHyperlinkLeave",
        HyperlinkLeave,
        self
    )
    if not leaveOK then
        local rollbackOK = pcall(
            registry.UnregisterCallback,
            registry,
            "ChatFrame.OnHyperlinkEnter",
            self
        )
        if rollbackOK then
            self.tooltipListenerCount = 0
            UpdateListenerGauge()
            return false, "tooltip-leave-listener-failed"
        end
        RecordTooltipCleanupFailure("tooltip-listener-rollback-failed")
        return false, "tooltip-listener-rollback-failed"
    end
    self.tooltipEnabled = true
    self.tooltipListenerCount = 2
    UpdateListenerGauge()
    return true
end

function Adapter:ClearHyperlinkTooltip(frame)
    local hidden
    local reason
    if frame ~= nil then
        hidden, reason = HideOwnedTooltip(frame)
    else
        local activeFrame = self.activeTooltipFrame
        if activeFrame then
            hidden, reason = HideOwnedTooltip(activeFrame)
        else
            hidden = true
        end
    end
    if not hidden then RecordTooltipCleanupFailure(reason) end
    return hidden, reason
end

local function NormalizeFontFile(value)
    if type(value) ~= "string" or value == "" then return nil end
    return lower((gsub(value, "/", "\\")))
end

local function NormalizeFontFlags(value)
    if type(value) ~= "string" then return nil end
    local tokens = {}
    for token in gmatch(value, "[^,%s]+") do
        tokens[#tokens + 1] = string.upper(token)
    end
    sort(tokens)
    return concat(tokens, ",")
end

local function CallAndValidateTimestampFontStyle(callback, frame)
    local fontFile, height, flags = callback(frame)
    if IsSecretValue(fontFile) or IsSecretValue(height) or IsSecretValue(flags) then return nil end
    local normalizedFontFile = NormalizeFontFile(fontFile)
    if normalizedFontFile == nil then return nil end
    local validHeight, reason = ValidatePositiveFiniteNumber(height)
    if validHeight == nil then return nil, nil, nil, reason end
    if type(flags) ~= "string" then return nil, nil, nil, "flags-type-mismatch" end
    return fontFile, validHeight, flags, normalizedFontFile
end

function Adapter:ReadTimestampFontStyle(frame)
    local callback = frame and frame.GetFont
    if type(callback) ~= "function" then
        return nil, nil, nil, "timestamp-font-source-unavailable"
    end

    local ok, fontFile, height, flags = pcall(CallAndValidateTimestampFontStyle, callback, frame)
    if not ok or fontFile == nil then
        return nil, nil, nil, "timestamp-font-style-read-or-validation-failed"
    end
    return fontFile, height, flags
end

function Adapter:ReadTimestampFontObject(frame)
    local valid, validReason = self:ValidateFrame(frame)
    if not valid then return nil, validReason end
    local callback = frame and frame.GetFontObject
    if type(callback) ~= "function" then
        return nil, "timestamp-font-object-source-unavailable"
    end
    local ok, fontObject = pcall(callback, frame)
    if not ok
        or fontObject == nil
        or IsSecretValue(fontObject)
        or type(fontObject.GetFont) ~= "function"
    then
        return nil, "timestamp-font-object-read-or-validation-failed"
    end
    return fontObject
end

local function FailChatTypography(reason)
    return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, reason
end

function Adapter:ReadChatTypography(frame)
    local valid, validReason = self:ValidateFrame(frame)
    if not valid then return FailChatTypography(validReason) end
    local fontFile, fontHeight, fontFlags, fontReason = self:ReadTimestampFontStyle(frame)
    if fontFile == nil then return FailChatTypography(fontReason) end
    local getSpacing = frame.GetSpacing
    local getShadowColor = frame.GetShadowColor
    local getShadowOffset = frame.GetShadowOffset
    if type(getSpacing) ~= "function"
        or type(getShadowColor) ~= "function"
        or type(getShadowOffset) ~= "function"
    then
        return FailChatTypography("chat-typography-read-api-missing")
    end
    local spacingOK, spacing = pcall(getSpacing, frame)
    if not spacingOK or IsSecretValue(spacing) then
        return FailChatTypography("chat-spacing-read-failed")
    end
    spacing = ValidateFiniteNumber(spacing)
    if spacing == nil or spacing < 0 then
        return FailChatTypography("chat-spacing-invalid")
    end
    local colorOK, r, g, b, a = pcall(getShadowColor, frame)
    local offsetOK, x, y = pcall(getShadowOffset, frame)
    if not colorOK or not offsetOK
        or IsSecretValue(r) or IsSecretValue(g)
        or IsSecretValue(b) or IsSecretValue(a)
        or IsSecretValue(x) or IsSecretValue(y)
    then
        return FailChatTypography("chat-shadow-read-failed")
    end
    r = ValidateFiniteNumber(r)
    g = ValidateFiniteNumber(g)
    b = ValidateFiniteNumber(b)
    a = ValidateFiniteNumber(a)
    x = ValidateFiniteNumber(x)
    y = ValidateFiniteNumber(y)
    if r == nil or g == nil or b == nil or a == nil or x == nil or y == nil
        or r < 0 or r > 1 or g < 0 or g > 1
        or b < 0 or b > 1 or a < 0 or a > 1
    then
        return FailChatTypography("chat-shadow-invalid")
    end
    return fontFile, fontHeight, fontFlags, spacing, r, g, b, a, x, y
end

local function ReadChatFontMember(fontObject, alphabet)
    local getter = fontObject and fontObject.GetFontObjectForAlphabet
    if type(getter) ~= "function" then
        return nil, "chat-font-family-member-api-missing"
    end
    local objectOK, member = pcall(getter, fontObject, alphabet)
    if not objectOK
        or member == nil
        or IsSecretValue(member)
        or type(member.GetFont) ~= "function"
        or type(member.GetShadowColor) ~= "function"
        or type(member.GetShadowOffset) ~= "function"
    then
        return nil, "chat-font-family-member-invalid"
    end
    local fontOK, file, height, flags = pcall(member.GetFont, member)
    local colorOK, r, g, b, a = pcall(member.GetShadowColor, member)
    local offsetOK, x, y = pcall(member.GetShadowOffset, member)
    if not fontOK or not colorOK or not offsetOK
        or IsSecretValue(file) or IsSecretValue(height) or IsSecretValue(flags)
        or IsSecretValue(r) or IsSecretValue(g) or IsSecretValue(b)
        or IsSecretValue(a) or IsSecretValue(x) or IsSecretValue(y)
    then
        return nil, "chat-font-family-member-read-failed"
    end
    height = ValidatePositiveFiniteNumber(height)
    r = ValidateFiniteNumber(r)
    g = ValidateFiniteNumber(g)
    b = ValidateFiniteNumber(b)
    a = ValidateFiniteNumber(a)
    x = ValidateFiniteNumber(x)
    y = ValidateFiniteNumber(y)
    if NormalizeFontFile(file) == nil
        or height == nil
        or type(flags) ~= "string"
        or r == nil or r < 0 or r > 1
        or g == nil or g < 0 or g > 1
        or b == nil or b < 0 or b > 1
        or a == nil or a < 0 or a > 1
        or x == nil or y == nil
    then
        return nil, "chat-font-family-member-style-invalid"
    end
    return {
        object = member,
        file = file,
        height = height,
        flags = flags,
        shadowR = r,
        shadowG = g,
        shadowB = b,
        shadowA = a,
        shadowX = x,
        shadowY = y,
    }
end

function Adapter:CaptureChatTypographySnapshot(frame)
    local fontFile, fontHeight, fontFlags, spacing,
        shadowR, shadowG, shadowB, shadowA, shadowX, shadowY, reason =
        self:ReadChatTypography(frame)
    if fontFile == nil then return nil, reason end
    local fontObject, fontObjectReason = self:ReadTimestampFontObject(frame)
    if fontObject == nil then return nil, fontObjectReason end
    local members = {}
    for index = 1, #CHAT_FONT_ALPHABETS do
        local alphabet = CHAT_FONT_ALPHABETS[index]
        local member, memberReason = ReadChatFontMember(fontObject, alphabet)
        if member == nil then return nil, memberReason end
        members[alphabet] = member
    end
    return {
        fontObject = fontObject,
        fontFile = fontFile,
        fontHeight = fontHeight,
        fontFlags = fontFlags,
        spacing = spacing,
        shadowR = shadowR,
        shadowG = shadowG,
        shadowB = shadowB,
        shadowA = shadowA,
        shadowX = shadowX,
        shadowY = shadowY,
        members = members,
    }
end

function Adapter:ReadStoredChatWindowFontSize(frame)
    if (self.clientFlavor ~= "mainline" and self.clientFlavor ~= "forever") then
        return nil, "chat-window-font-size-mainline-only"
    end
    local supported, classification = self:ClassifyTypographyFrame(frame)
    if not supported then return nil, classification end
    if classification == "temporary-whisper-typography-frame" then
        return nil, "temporary-chat-window-has-no-stored-font-size"
    end
    if type(frame.GetID) ~= "function" then
        return nil, "chat-window-id-api-missing"
    end
    local idOK, id = pcall(frame.GetID, frame)
    if not idOK
        or self:IsExplicitlySafeValue(id) ~= true
        or type(id) ~= "number"
        or id < 1
        or id > MAX_EXACT_INTEGER
        or floor(id) ~= id
    then
        return nil, "chat-window-id-invalid"
    end
    local getInfo = _G.FCF_GetChatWindowInfo
    if type(getInfo) ~= "function" then
        return nil, "chat-window-info-api-missing"
    end
    local readOK, _, fontSize = pcall(getInfo, id)
    if not readOK or self:IsExplicitlySafeValue(fontSize) ~= true then
        return nil, "chat-window-font-size-read-unsafe"
    end
    fontSize = ValidatePositiveFiniteNumber(fontSize)
    if fontSize == nil then return nil, "chat-window-font-size-invalid" end
    return fontSize
end

local function EnsureManagedChatFontFamily(frame, snapshot)
    local state = frameStates[frame]
    if not state or (state.ready ~= true and state.typographyReady ~= true) then
        return nil, "chat-font-family-frame-unregistered"
    end
    if state.chatFontFamily then return state.chatFontFamily end
    if type(CreateFontFamily) ~= "function" then
        return nil, "chat-font-family-create-api-missing"
    end
    if type(snapshot) ~= "table" or type(snapshot.members) ~= "table" then
        return nil, "chat-font-family-snapshot-invalid"
    end
    local definitions = {}
    for index = 1, #CHAT_FONT_ALPHABETS do
        local alphabet = CHAT_FONT_ALPHABETS[index]
        local member = snapshot.members[alphabet]
        if type(member) ~= "table"
            or NormalizeFontFile(member.file) == nil
            or ValidatePositiveFiniteNumber(member.height) == nil
            or type(member.flags) ~= "string"
        then
            return nil, "chat-font-family-snapshot-member-invalid"
        end
        definitions[index] = {
            alphabet = alphabet,
            file = member.file,
            height = member.height,
            flags = member.flags,
        }
    end
    nextChatFontFamilyId = nextChatFontFamilyId + 1
    local name = "YUI_YChatFontFamily" .. nextChatFontFamilyId
    local created, family = pcall(CreateFontFamily, name, definitions)
    if not created
        or family == nil
        or IsSecretValue(family)
        or type(family.GetFontObjectForAlphabet) ~= "function"
    then
        return nil, "chat-font-family-create-failed"
    end
    for index = 1, #CHAT_FONT_ALPHABETS do
        local member = ReadChatFontMember(family, CHAT_FONT_ALPHABETS[index])
        if member == nil then return nil, "chat-font-family-created-member-invalid" end
    end
    state.chatFontFamily = family
    state.chatFontFamilyName = name
    return family
end

function Adapter:ApplyChatTypographyFamily(
    frame,
    snapshot,
    fontFile,
    fontHeight,
    fontFlags,
    spacing,
    shadowR,
    shadowG,
    shadowB,
    shadowA,
    shadowX,
    shadowY
)
    local valid, validReason = self:ValidateFrame(frame)
    if not valid then return false, validReason end
    local allowed, protectedReason = self:CanCallProtected(frame)
    if not allowed then return false, protectedReason end
    if type(snapshot) ~= "table" or type(snapshot.members) ~= "table" then
        return false, "chat-font-family-snapshot-invalid"
    end
    local normalizedFile
    if fontFile ~= nil then
        normalizedFile = NormalizeFontFile(fontFile)
        if normalizedFile == nil then return false, "chat-font-family-file-invalid" end
    end
    local height = ValidatePositiveFiniteNumber(fontHeight)
    local normalizedFlags = NormalizeFontFlags(fontFlags)
    local lineSpacing = ValidateFiniteNumber(spacing)
    shadowR = ValidateFiniteNumber(shadowR)
    shadowG = ValidateFiniteNumber(shadowG)
    shadowB = ValidateFiniteNumber(shadowB)
    shadowA = ValidateFiniteNumber(shadowA)
    shadowX = ValidateFiniteNumber(shadowX)
    shadowY = ValidateFiniteNumber(shadowY)
    if height == nil or normalizedFlags == nil
        or lineSpacing == nil or lineSpacing < 0
        or shadowR == nil or shadowR < 0 or shadowR > 1
        or shadowG == nil or shadowG < 0 or shadowG > 1
        or shadowB == nil or shadowB < 0 or shadowB > 1
        or shadowA == nil or shadowA < 0 or shadowA > 1
        or shadowX == nil or shadowY == nil
    then
        return false, "chat-font-family-value-invalid"
    end
    if type(frame.SetFontObject) ~= "function"
        or type(frame.GetFontObject) ~= "function"
        or type(frame.SetSpacing) ~= "function"
        or type(frame.MarkLayoutDirty) ~= "function"
        or type(frame.MarkDisplayDirty) ~= "function"
    then
        return false, "chat-font-family-write-api-missing"
    end

    local family, familyReason = EnsureManagedChatFontFamily(frame, snapshot)
    if not family then return false, familyReason end
    for index = 1, #CHAT_FONT_ALPHABETS do
        local alphabet = CHAT_FONT_ALPHABETS[index]
        local source = snapshot.members[alphabet]
        local memberOK, member = pcall(family.GetFontObjectForAlphabet, family, alphabet)
        local targetFile = fontFile or (source and source.file)
        if not memberOK or member == nil
            or type(member.SetFont) ~= "function"
            or type(member.SetShadowColor) ~= "function"
            or type(member.SetShadowOffset) ~= "function"
            or NormalizeFontFile(targetFile) == nil
        then
            return false, "chat-font-family-member-write-api-missing"
        end
        local setOK, setResult = pcall(member.SetFont, member, targetFile, height, fontFlags)
        if not setOK or setResult == false then
            return false, "chat-font-family-member-font-write-failed"
        end
        if not pcall(
            member.SetShadowColor,
            member,
            shadowR,
            shadowG,
            shadowB,
            shadowA
        ) then
            return false, "chat-font-family-member-shadow-write-failed"
        end
        if not pcall(member.SetShadowOffset, member, shadowX, shadowY) then
            return false, "chat-font-family-member-shadow-write-failed"
        end
    end

    if not pcall(frame.SetFontObject, frame, family) then
        return false, "chat-font-family-object-write-failed"
    end
    if not pcall(frame.SetSpacing, frame, lineSpacing) then
        return false, "chat-font-family-spacing-write-failed"
    end
    if not pcall(frame.MarkLayoutDirty, frame)
        or not pcall(frame.MarkDisplayDirty, frame)
    then
        return false, "chat-font-family-refresh-failed"
    end
    local objectOK, actualObject = pcall(frame.GetFontObject, frame)
    if not objectOK
        or actualObject == nil
        or IsSecretValue(actualObject)
        or type(actualObject.GetFontObjectForAlphabet) ~= "function"
    then
        return false, "chat-font-family-object-unconfirmed"
    end
    local spacingOK, actualSpacing = pcall(frame.GetSpacing, frame)
    actualSpacing = spacingOK and ValidateFiniteNumber(actualSpacing) or nil
    if actualSpacing == nil
        or actualSpacing < lineSpacing - TIMESTAMP_FONT_HEIGHT_TOLERANCE
        or actualSpacing > lineSpacing + TIMESTAMP_FONT_HEIGHT_TOLERANCE
    then
        return false, "chat-font-family-spacing-unconfirmed"
    end
    for index = 1, #CHAT_FONT_ALPHABETS do
        local alphabet = CHAT_FONT_ALPHABETS[index]
        local expectedFile = fontFile or snapshot.members[alphabet].file
        local actual, actualReason = ReadChatFontMember(actualObject, alphabet)
        if actual == nil
            or NormalizeFontFile(actual.file) ~= NormalizeFontFile(expectedFile)
            or actual.height < height - TIMESTAMP_FONT_HEIGHT_TOLERANCE
            or actual.height > height + TIMESTAMP_FONT_HEIGHT_TOLERANCE
            or NormalizeFontFlags(actual.flags) ~= normalizedFlags
            or actual.shadowR ~= shadowR or actual.shadowG ~= shadowG
            or actual.shadowB ~= shadowB or actual.shadowA ~= shadowA
            or actual.shadowX ~= shadowX or actual.shadowY ~= shadowY
        then
            return false, actualReason or "chat-font-family-member-unconfirmed"
        end
    end
    return true, actualObject
end

local function ChatFontFamilyMatchesSnapshot(fontObject, snapshot)
    if fontObject == nil or IsSecretValue(fontObject)
        or type(snapshot) ~= "table" or type(snapshot.members) ~= "table"
    then
        return false
    end
    for index = 1, #CHAT_FONT_ALPHABETS do
        local alphabet = CHAT_FONT_ALPHABETS[index]
        local expected = snapshot.members[alphabet]
        local actual = ReadChatFontMember(fontObject, alphabet)
        if type(expected) ~= "table" or actual == nil
            or NormalizeFontFile(actual.file) ~= NormalizeFontFile(expected.file)
            or actual.height < expected.height - TIMESTAMP_FONT_HEIGHT_TOLERANCE
            or actual.height > expected.height + TIMESTAMP_FONT_HEIGHT_TOLERANCE
            or NormalizeFontFlags(actual.flags) ~= NormalizeFontFlags(expected.flags)
            or actual.shadowR ~= expected.shadowR
            or actual.shadowG ~= expected.shadowG
            or actual.shadowB ~= expected.shadowB
            or actual.shadowA ~= expected.shadowA
            or actual.shadowX ~= expected.shadowX
            or actual.shadowY ~= expected.shadowY
        then
            return false
        end
    end
    return true
end

function Adapter:RestoreChatTypographySnapshot(frame, snapshot, nativeFontSize)
    local valid, validReason = self:ValidateFrame(frame)
    if not valid then return false, validReason end
    local allowed, protectedReason = self:CanCallProtected(frame)
    if not allowed then return false, protectedReason end
    local restoreFontSize
    if nativeFontSize ~= nil then
        restoreFontSize = ValidatePositiveFiniteNumber(nativeFontSize)
        if restoreFontSize == nil then
            return false, "chat-font-family-restore-size-invalid"
        end
    end
    if type(snapshot) ~= "table"
        or snapshot.fontObject == nil
        or IsSecretValue(snapshot.fontObject)
        or ValidateFiniteNumber(snapshot.spacing) == nil
        or (restoreFontSize ~= nil
            and (NormalizeFontFile(snapshot.fontFile) == nil
                or type(snapshot.fontFlags) ~= "string"
                or type(frame.SetFont) ~= "function"
                or type(frame.GetFont) ~= "function"))
        or type(frame.SetFontObject) ~= "function"
        or type(frame.GetFontObject) ~= "function"
        or type(frame.SetSpacing) ~= "function"
        or type(frame.MarkLayoutDirty) ~= "function"
        or type(frame.MarkDisplayDirty) ~= "function"
    then
        return false, "chat-font-family-restore-snapshot-invalid"
    end
    if not pcall(frame.SetFontObject, frame, snapshot.fontObject)
        or (restoreFontSize ~= nil
            and not pcall(
                frame.SetFont,
                frame,
                snapshot.fontFile,
                restoreFontSize,
                snapshot.fontFlags
            ))
        or not pcall(frame.SetSpacing, frame, snapshot.spacing)
        or not pcall(frame.MarkLayoutDirty, frame)
        or not pcall(frame.MarkDisplayDirty, frame)
    then
        return false, "chat-font-family-restore-write-failed"
    end
    local objectOK, actualObject = pcall(frame.GetFontObject, frame)
    local spacingOK, actualSpacing = pcall(frame.GetSpacing, frame)
    actualSpacing = spacingOK and ValidateFiniteNumber(actualSpacing) or nil
    local fontOK = true
    if restoreFontSize ~= nil then
        local actualFile, actualHeight, actualFlags
        fontOK, actualFile, actualHeight, actualFlags = pcall(frame.GetFont, frame)
        actualHeight = fontOK and ValidatePositiveFiniteNumber(actualHeight) or nil
        fontOK = fontOK
            and NormalizeFontFile(actualFile) == NormalizeFontFile(snapshot.fontFile)
            and actualHeight ~= nil
            and actualHeight >= restoreFontSize - TIMESTAMP_FONT_HEIGHT_TOLERANCE
            and actualHeight <= restoreFontSize + TIMESTAMP_FONT_HEIGHT_TOLERANCE
            and NormalizeFontFlags(actualFlags) == NormalizeFontFlags(snapshot.fontFlags)
    end
    if not objectOK or actualSpacing == nil
        or not fontOK
        or actualSpacing < snapshot.spacing - TIMESTAMP_FONT_HEIGHT_TOLERANCE
        or actualSpacing > snapshot.spacing + TIMESTAMP_FONT_HEIGHT_TOLERANCE
    then
        return false, "chat-font-family-restore-unconfirmed"
    end
    if actualObject ~= snapshot.fontObject
        and not ChatFontFamilyMatchesSnapshot(actualObject, snapshot)
    then
        return false, "chat-font-family-restore-unconfirmed"
    end
    return true
end

function Adapter:ReadTimestampTextStyle(frame)
    local fontFile, fontHeight, fontFlags, reason = self:ReadTimestampFontStyle(frame)
    if fontFile == nil then
        return nil, nil, nil, nil, nil, nil, nil, nil, nil, reason
    end
    local getShadowColor = frame and frame.GetShadowColor
    local getShadowOffset = frame and frame.GetShadowOffset
    if type(getShadowColor) ~= "function" or type(getShadowOffset) ~= "function" then
        return fontFile, fontHeight, fontFlags, 0, 0, 0, 0, 0, 0
    end
    local colorOK, r, g, b, a = pcall(getShadowColor, frame)
    local offsetOK, x, y = pcall(getShadowOffset, frame)
    if not colorOK or not offsetOK
        or IsSecretValue(r) or IsSecretValue(g)
        or IsSecretValue(b) or IsSecretValue(a)
        or IsSecretValue(x) or IsSecretValue(y)
    then
        return nil, nil, nil, nil, nil, nil, nil, nil, nil,
            "timestamp-shadow-style-read-failed"
    end
    r = ValidateFiniteNumber(r)
    g = ValidateFiniteNumber(g)
    b = ValidateFiniteNumber(b)
    a = ValidateFiniteNumber(a)
    x = ValidateFiniteNumber(x)
    y = ValidateFiniteNumber(y)
    if r == nil or g == nil or b == nil or a == nil or x == nil or y == nil
        or r < 0 or r > 1 or g < 0 or g > 1
        or b < 0 or b > 1 or a < 0 or a > 1
    then
        return nil, nil, nil, nil, nil, nil, nil, nil, nil,
            "timestamp-shadow-style-invalid"
    end
    return fontFile, fontHeight, fontFlags, r, g, b, a, x, y
end

function Adapter:ReadSystemTimestampFormat()
    local system = YUI.API and YUI.API.System
    local callback = system and system.GetCVarSafe
    if type(callback) ~= "function" then
        return nil, "system-timestamp-read-api-missing"
    end
    local ok, value = pcall(callback, "showTimestamps")
    if not ok or IsSecretValue(value) or type(value) ~= "string" or value == "" then
        return nil, "system-timestamp-read-failed"
    end
    return value
end

function Adapter:SetSystemTimestampFormat(value)
    if IsSecretValue(value) or type(value) ~= "string" or value == "" then
        return false, "system-timestamp-value-invalid"
    end
    local system = YUI.API and YUI.API.System
    local callback = system and system.SetCVarSafe
    if type(callback) ~= "function" then
        return false, "system-timestamp-write-api-missing"
    end
    local ok, applied = pcall(callback, "showTimestamps", value)
    if not ok or applied ~= true then
        return false, "system-timestamp-write-failed"
    end
    local actual, readReason = self:ReadSystemTimestampFormat()
    if actual ~= value then
        return false, readReason or "system-timestamp-write-unconfirmed"
    end
    return true
end

function Adapter:InstallChatTypographyHooks(frame, fontCallback, spacingCallback)
    local prepared = self:PrepareTypographyFrame(frame)
    local state = frameStates[frame]
    if not prepared
        or not state
        or (state.ready ~= true and state.typographyReady ~= true)
    then
        return false, "chat-typography-frame-unregistered"
    end
    if state.typographyTemporary == true then
        return false, "chat-typography-temporary-hooks-disabled"
    end
    if type(fontCallback) ~= "function" or type(spacingCallback) ~= "function" then
        return false, "chat-typography-hook-invalid"
    end
    if not EnsureMethodHook(
        state,
        frame,
        "typographyFont",
        "SetFont",
        fontCallback,
        false
    ) then
        return false, "chat-font-hook-failed"
    end
    if not EnsureMethodHook(
        state,
        frame,
        "typographyFontObject",
        "SetFontObject",
        fontCallback,
        false
    ) then
        return false, "chat-font-object-hook-failed"
    end
    if not EnsureMethodHook(
        state,
        frame,
        "typographySpacing",
        "SetSpacing",
        spacingCallback,
        false
    ) then
        return false, "chat-spacing-hook-failed"
    end
    if not EnsureMethodHook(
        state,
        frame,
        "typographyShadowColor",
        "SetShadowColor",
        fontCallback,
        false
    ) then
        return false, "chat-shadow-color-hook-failed"
    end
    if not EnsureMethodHook(
        state,
        frame,
        "typographyShadowOffset",
        "SetShadowOffset",
        fontCallback,
        false
    ) then
        return false, "chat-shadow-offset-hook-failed"
    end
    return true
end

function Adapter:InstallCopyHoverHooks(frame, enterCallback, leaveCallback)
    local state = frameStates[frame]
    if not self.enabled or not state or not state.ready or state.supported ~= true then
        return false, "copy-hover-frame-unregistered"
    end
    if type(enterCallback) ~= "function" or type(leaveCallback) ~= "function" then
        return false, "copy-hover-callback-invalid"
    end
    if type(frame.HookScript) ~= "function" then
        return false, "copy-hover-hook-api-missing"
    end

    state.copyHoverEnterCallback = enterCallback
    state.copyHoverLeaveCallback = leaveCallback
    if not state.copyHoverEnterHook then
        local ok = pcall(frame.HookScript, frame, "OnEnter", CopyHoverEnterHook)
        if not ok then return false, "copy-hover-enter-hook-failed" end
        state.copyHoverEnterHook = true
        RecordPermanentHook(state)
    end
    if not state.copyHoverLeaveHook then
        local ok = pcall(frame.HookScript, frame, "OnLeave", CopyHoverLeaveHook)
        if not ok then return false, "copy-hover-leave-hook-failed" end
        state.copyHoverLeaveHook = true
        RecordPermanentHook(state)
    end
    return true
end

function Adapter:InstallInteractionHoverProxy(frame, callback)
    local state = frameStates[frame]
    if temporaryTypographyFrames[frame] == true
        or (state and state.typographyTemporary == true)
    then
        return false, "interaction-hover-temporary-frame"
    end
    if not self.enabled
        or trustedFrames[frame] ~= true
        or not state
        or not state.ready
        or state.supported ~= true
    then
        return false, "interaction-hover-frame-unregistered"
    end
    if type(callback) ~= "function" then
        return false, "interaction-hover-callback-invalid"
    end

    state.interactionHoverCallback = callback
    return true
end

function Adapter:ScrollChatFrameToBottom(frame)
    local valid, validReason = self:ValidateFrame(frame)
    if not valid then return false, validReason end
    local allowed, protectedReason = self:CanCallProtected(frame)
    if not allowed then return false, protectedReason end
    local callback = frame and frame.ScrollToBottom
    if type(callback) ~= "function" then
        return false, "chat-scroll-bottom-api-missing"
    end
    local ok = pcall(callback, frame)
    if not ok then return false, "chat-scroll-bottom-failed" end
    return true
end

function Adapter:ApplyChatTypography(
    frame,
    fontFile,
    fontHeight,
    fontFlags,
    spacing,
    shadowR,
    shadowG,
    shadowB,
    shadowA,
    shadowX,
    shadowY
)
    local valid, validReason = self:ValidateFrame(frame)
    if not valid then return false, validReason end
    local allowed, protectedReason = self:CanCallProtected(frame)
    if not allowed then return false, protectedReason end
    if type(frame.SetFont) ~= "function"
        or type(frame.SetSpacing) ~= "function"
        or type(frame.SetShadowColor) ~= "function"
        or type(frame.SetShadowOffset) ~= "function"
        or type(frame.MarkLayoutDirty) ~= "function"
        or type(frame.MarkDisplayDirty) ~= "function"
    then
        return false, "chat-typography-write-api-missing"
    end
    local normalized = NormalizeFontFile(fontFile)
    local height = ValidatePositiveFiniteNumber(fontHeight)
    local lineSpacing = ValidateFiniteNumber(spacing)
    shadowR = ValidateFiniteNumber(shadowR)
    shadowG = ValidateFiniteNumber(shadowG)
    shadowB = ValidateFiniteNumber(shadowB)
    shadowA = ValidateFiniteNumber(shadowA)
    shadowX = ValidateFiniteNumber(shadowX)
    shadowY = ValidateFiniteNumber(shadowY)
    local normalizedFlags = NormalizeFontFlags(fontFlags)
    if normalized == nil or height == nil or normalizedFlags == nil
        or lineSpacing == nil or lineSpacing < 0
        or shadowR == nil or shadowR < 0 or shadowR > 1
        or shadowG == nil or shadowG < 0 or shadowG > 1
        or shadowB == nil or shadowB < 0 or shadowB > 1
        or shadowA == nil or shadowA < 0 or shadowA > 1
        or shadowX == nil or shadowY == nil
    then
        return false, "chat-typography-value-invalid"
    end
    local fontOK, fontResult = pcall(frame.SetFont, frame, fontFile, height, fontFlags)
    if not fontOK or fontResult == false then return false, "chat-font-write-failed" end
    if not pcall(frame.SetSpacing, frame, lineSpacing) then
        return false, "chat-spacing-write-failed"
    end
    if not pcall(
        frame.SetShadowColor,
        frame,
        shadowR,
        shadowG,
        shadowB,
        shadowA
    ) then
        return false, "chat-shadow-color-write-failed"
    end
    if not pcall(frame.SetShadowOffset, frame, shadowX, shadowY) then
        return false, "chat-shadow-offset-write-failed"
    end
    if not pcall(frame.MarkLayoutDirty, frame) then
        return false, "chat-typography-layout-refresh-failed"
    end
    if not pcall(frame.MarkDisplayDirty, frame) then
        return false, "chat-typography-display-refresh-failed"
    end
    local actualFile, actualHeight, actualFlags, actualSpacing,
        actualR, actualG, actualB, actualA, actualX, actualY =
        self:ReadChatTypography(frame)
    if actualFile == nil or actualHeight == nil or actualSpacing == nil
        or NormalizeFontFile(actualFile) ~= normalized
        or actualHeight < height - TIMESTAMP_FONT_HEIGHT_TOLERANCE
        or actualHeight > height + TIMESTAMP_FONT_HEIGHT_TOLERANCE
        or NormalizeFontFlags(actualFlags) ~= normalizedFlags
        or actualSpacing < lineSpacing - TIMESTAMP_FONT_HEIGHT_TOLERANCE
        or actualSpacing > lineSpacing + TIMESTAMP_FONT_HEIGHT_TOLERANCE
        or actualR ~= shadowR or actualG ~= shadowG
        or actualB ~= shadowB or actualA ~= shadowA
        or actualX ~= shadowX or actualY ~= shadowY
    then
        return false, "chat-typography-readback-unconfirmed"
    end
    return true
end

local function CallAndValidateTimestampFontReadback(
    callback,
    overlay,
    expectedFontFile,
    expectedHeight,
    expectedFlags
)
    local fontFile, height, flags = callback(overlay)
    if IsSecretValue(fontFile) or IsSecretValue(height) or IsSecretValue(flags) then return nil end
    local normalized = NormalizeFontFile(fontFile)
    if normalized == nil or normalized ~= expectedFontFile then return nil end

    local validHeight = ValidatePositiveFiniteNumber(height)
    if validHeight == nil
        or validHeight < expectedHeight - TIMESTAMP_FONT_HEIGHT_TOLERANCE
        or validHeight > expectedHeight + TIMESTAMP_FONT_HEIGHT_TOLERANCE
    then
        return nil
    end
    if type(flags) ~= "string" or flags ~= expectedFlags then return nil end
    return true
end

local function ValidateNonNegativeInteger(value)
    local number, reason = ValidateFiniteNumber(value)
    if number == nil then return nil, reason end
    if number < 0 or number > MAX_EXACT_INTEGER or floor(number) ~= number then
        return nil, "out-of-range"
    end
    return number
end

local function ValidatePositiveInteger(value)
    local number, reason = ValidateNonNegativeInteger(value)
    if number == nil then return nil, reason end
    if number < 1 then return nil, "out-of-range" end
    return number
end

local function ValidateBoolean(value)
    if type(value) ~= "boolean" then return nil, "type-mismatch" end
    if value == true then return true end
    if value == false then return false end
    return nil, "out-of-range"
end

local function ValidateInsertMode(value)
    local mode, reason = ValidatePositiveInteger(value)
    if mode == nil then return nil, reason end
    if mode == INSERT_MODE_TOP then return true end
    if mode == INSERT_MODE_BOTTOM then return false end
    return nil, "out-of-range"
end

local function CallAndValidate(callback, frame, validator)
    return validator(callback(frame))
end

local function ReadMethod(frame, methodName, validator, reason)
    local callback = frame and frame[methodName]
    if type(callback) ~= "function" then return nil, "missing-" .. reason end
    local ok, value, validationReason = pcall(CallAndValidate, callback, frame, validator)
    if not ok then return nil, reason .. "-read-or-validation-failed" end
    if value == nil then return nil, reason .. "-" .. (validationReason or "invalid") end
    return value
end

local function ReadSafeRect(region, reason)
    local callback = region and region.GetRect
    if type(callback) ~= "function" then return nil, "missing-" .. reason end
    local ok, left, bottom, width, height = pcall(callback, region)
    if not ok
        or Adapter:IsExplicitlySafeValue(left) ~= true
        or Adapter:IsExplicitlySafeValue(bottom) ~= true
        or Adapter:IsExplicitlySafeValue(width) ~= true
        or Adapter:IsExplicitlySafeValue(height) ~= true
        or ValidateFiniteNumber(left) == nil
        or ValidateFiniteNumber(bottom) == nil
        or ValidatePositiveFiniteNumber(width) == nil
        or ValidatePositiveFiniteNumber(height) == nil
    then
        return nil, reason .. "-invalid"
    end
    return left, bottom, left + width, bottom + height
end

function Adapter:ReadAppearanceTabDocked(frame)
    if not self.enabled or trustedFrames[frame] ~= true then
        return nil, "untrusted-chat-frame"
    end
    local backend = clientBackend
    local reader = backend and backend.IsAppearanceTabDocked
    if type(reader) ~= "function" then
        return nil, "appearance-tab-dock-reader-unavailable"
    end
    local ok, docked, reason = pcall(reader, backend, frame)
    if not ok
        or self:IsExplicitlySafeValue(docked) ~= true
        or type(docked) ~= "boolean"
    then
        return nil, reason or "appearance-tab-dock-state-unsafe"
    end
    return docked
end

function Adapter:ReconcileAppearanceTabWidth(frame, tabWidth)
    local docked, dockReason = self:ReadAppearanceTabDocked(frame)
    if type(docked) ~= "boolean" then return false, dockReason end
    if docked then return true, "appearance-tab-width-native-dock" end

    local targets, targetReason = self:GetAppearanceTabTargets(frame)
    if not targets then return false, targetReason end
    local tab = targets.tab
    local tabText = targets.tabText
    if self:CanCallProtected(frame) ~= true
        or self:CanCallProtected(tab) ~= true
        or self:CanCallProtected(tabText) ~= true
    then
        return false, "appearance-tab-resize-protected"
    end

    local padding = tab.sizePadding
    if padding == nil then
        padding = 0
    elseif self:IsExplicitlySafeValue(padding) ~= true
        or ValidateFiniteNumber(padding) == nil
    then
        return false, "appearance-tab-size-padding-invalid"
    end
    if tabWidth ~= nil then
        if self:IsExplicitlySafeValue(tabWidth) ~= true
            or ValidatePositiveFiniteNumber(tabWidth) == nil
            or tabWidth <= 20
        then
            return false, "appearance-tab-width-invalid"
        end
        local textWidth = tabWidth - 20 - padding
        if textWidth < 1 then textWidth = 1 end
        if not pcall(tabText.SetWidth, tabText, textWidth)
            or not pcall(tab.SetWidth, tab, tabWidth)
        then
            return false, "appearance-tab-resize-failed"
        end
        return true, "appearance-tab-width-fixed"
    end

    local resize = _G.PanelTemplates_TabResize
    if type(resize) ~= "function" then
        return false, "appearance-tab-resize-api-unavailable"
    end
    if not pcall(resize, tab, padding) then
        return false, "appearance-tab-resize-failed"
    end
    return true, "appearance-tab-width-reconciled"
end

function Adapter:ReadAppearanceTabWidth(tab)
    if not self.enabled
        or (self.clientFlavor ~= "mainline" and self.clientFlavor ~= "forever")
        or tab == nil
        or self:IsExplicitlySafeValue(tab) ~= true
        or type(tab.GetWidth) ~= "function"
    then
        return nil, "appearance-tab-width-read-unavailable"
    end
    local ok, width = pcall(tab.GetWidth, tab)
    if not ok
        or self:IsExplicitlySafeValue(width) ~= true
        or ValidatePositiveFiniteNumber(width) == nil
    then
        return nil, "appearance-tab-width-read-invalid"
    end
    return width
end

function Adapter:ReadAppearanceTabTextMetrics(tabText)
    if not self.enabled
        or (self.clientFlavor ~= "mainline" and self.clientFlavor ~= "forever")
        or self:IsExplicitlySafeValue(tabText) ~= true
        or self:CanCallProtected(tabText) ~= true
    then
        return nil, "appearance-tab-text-metrics-unsafe"
    end
    local readWidth = tabText.GetUnboundedStringWidth or tabText.GetStringWidth
    if type(readWidth) ~= "function"
        or type(tabText.GetStringHeight) ~= "function"
        or type(tabText.GetWidth) ~= "function"
    then
        return nil, "appearance-tab-text-metrics-api-missing"
    end

    local widthOK, unboundedWidth = pcall(readWidth, tabText)
    local heightOK, stringHeight = pcall(tabText.GetStringHeight, tabText)
    local regionOK, regionWidth = pcall(tabText.GetWidth, tabText)
    if not widthOK
        or not heightOK
        or not regionOK
        or self:IsExplicitlySafeValue(unboundedWidth) ~= true
        or self:IsExplicitlySafeValue(stringHeight) ~= true
        or self:IsExplicitlySafeValue(regionWidth) ~= true
        or ValidatePositiveFiniteNumber(unboundedWidth) == nil
        or ValidatePositiveFiniteNumber(stringHeight) == nil
        or ValidatePositiveFiniteNumber(regionWidth) == nil
    then
        return nil, "appearance-tab-text-metrics-invalid"
    end
    return math.min(unboundedWidth, regionWidth), stringHeight, regionWidth
end

function Adapter:CollapseCombatLogDockSlot(targets, tabSpacing)
    if not self.enabled
        or (self.clientFlavor ~= "mainline" and self.clientFlavor ~= "forever")
        or type(targets) ~= "table"
        or targets.frame ~= _G.ChatFrame2
        or targets.tab ~= _G.ChatFrame2Tab
        or targets.dock ~= _G.GeneralDockManager
        or targets.primaryTab ~= _G.ChatFrame1Tab
        or targets.dockScrollFrame ~= _G.GeneralDockManager.scrollFrame
        or targets.overflowButton ~= _G.GeneralDockManager.overflowButton
        or self:CanCallProtected(targets.dockScrollFrame) ~= true
    then
        return false, "combat-log-dock-slot-unsafe"
    end

    local shownOK, overflowShown = pcall(
        targets.overflowButton.IsShown,
        targets.overflowButton
    )
    if not shownOK
        or self:IsExplicitlySafeValue(overflowShown) ~= true
        or type(overflowShown) ~= "boolean"
    then
        return false, "combat-log-dock-overflow-state-unsafe"
    end

    tabSpacing = tabSpacing or 0
    if self:IsExplicitlySafeValue(tabSpacing) ~= true
        or ValidateFiniteNumber(tabSpacing) == nil
        or tabSpacing < 0
    then
        return false, "combat-log-dock-spacing-invalid"
    end

    local scrollFrame = targets.dockScrollFrame
    local rightAnchor = overflowShown and targets.overflowButton or targets.dock
    local rightPoint = overflowShown and "BOTTOMLEFT" or "BOTTOMRIGHT"
    local rightX = overflowShown and -5 or 0
    local rightY = overflowShown and 0 or -1
    local ok = pcall(scrollFrame.ClearAllPoints, scrollFrame)
        and pcall(
            scrollFrame.SetPoint,
            scrollFrame,
            "LEFT",
            targets.primaryTab,
            "RIGHT",
            tabSpacing,
            0
        )
        and pcall(
            scrollFrame.SetPoint,
            scrollFrame,
            "BOTTOMRIGHT",
            rightAnchor,
            rightPoint,
            rightX,
            rightY
        )
    return ok, ok and nil or "combat-log-dock-slot-collapse-failed"
end

function Adapter:RestoreCombatLogDockSlot(targets)
    if (self.clientFlavor ~= "mainline" and self.clientFlavor ~= "forever")
        or type(targets) ~= "table"
        or targets.dock ~= _G.GeneralDockManager
        or type(_G.FCFDock_UpdateTabs) ~= "function"
        or self:CanCallProtected(targets.dockScrollFrame) ~= true
    then
        return false, "combat-log-dock-slot-restore-unsafe"
    end
    local ok = pcall(_G.FCFDock_UpdateTabs, targets.dock, true)
    return ok, ok and nil or "combat-log-dock-slot-restore-failed"
end

function Adapter:ReconcileAppearanceDockTabWidths(
    tabWidth,
    tabWidthMode,
    tabSpacing,
    tabLeftInset,
    hideCombatLog,
    skipNativeRefresh
)
    if not self.enabled then return false, "adapter-disabled" end
    local backend = clientBackend
    local reconcile = backend and backend.ReconcileAppearanceDockTabWidths
    if type(reconcile) ~= "function" then
        return false, "appearance-dock-tab-reconcile-unavailable"
    end
    local ok, reconciled, reason = pcall(
        reconcile,
        backend,
        tabWidth,
        tabWidthMode,
        tabSpacing,
        tabLeftInset,
        hideCombatLog,
        skipNativeRefresh
    )
    if not ok or reconciled ~= true then
        return false, reason or "appearance-dock-tab-reconcile-failed"
    end
    return true
end

local function ReadLayoutEnvelopeLimits(bodyWidth, bodyHeight)
    local viewportWidth = ReadMethod(
        _G.UIParent,
        "GetWidth",
        ValidatePositiveFiniteNumber,
        "layout-envelope-viewport-width"
    )
    local viewportHeight = ReadMethod(
        _G.UIParent,
        "GetHeight",
        ValidatePositiveFiniteNumber,
        "layout-envelope-viewport-height"
    )
    return viewportWidth or max(bodyWidth * 4, 2048),
        viewportHeight or max(bodyHeight * 4, 2048)
end

local function IsOptionalEnvelopeRectPlausible(
    left,
    bottom,
    right,
    top,
    bodyCenterX,
    bodyCenterY,
    limitX,
    limitY
)
    local width = right - left
    local height = top - bottom
    return ValidatePositiveFiniteNumber(width) ~= nil
        and ValidatePositiveFiniteNumber(height) ~= nil
        and width <= limitX
        and height <= limitY
        and abs(((left + right) * 0.5) - bodyCenterX) <= limitX
        and abs(((bottom + top) * 0.5) - bodyCenterY) <= limitY
end

local function IsLayoutEnvelopePlausible(
    width,
    height,
    offsetX,
    offsetY,
    limitX,
    limitY
)
    return ValidatePositiveFiniteNumber(width) ~= nil
        and ValidatePositiveFiniteNumber(height) ~= nil
        and ValidateFiniteNumber(offsetX) ~= nil
        and ValidateFiniteNumber(offsetY) ~= nil
        and width <= limitX
        and height <= limitY
        and abs(offsetX) <= limitX
        and abs(offsetY) <= limitY
end

function Adapter:MeasureMainLayoutEnvelope(frame, holder, inputVisualInset)
    if not self.enabled
        or frame ~= _G.ChatFrame1
        or holder == nil
        or not self:IsTrustedSupportedFrame(frame)
    then
        return nil, "layout-envelope-main-frame-invalid"
    end
    if self:CanCallProtected(frame) ~= true
        or self:IsExplicitlySafeValue(holder) ~= true
    then
        return nil, "layout-envelope-main-frame-unsafe"
    end

    local targets, targetReason = self:GetAppearanceTargets(frame)
    if not targets then return nil, targetReason end
    local left, bottom, right, top = ReadSafeRect(
        targets.background,
        "layout-envelope-background"
    )
    if left == nil then return nil, bottom end
    local bodyLeft = left
    local bodyBottom = bottom
    local bodyRight = right
    local bodyTop = top
    local bodyWidth = right - left
    local bodyHeight = top - bottom
    local bodyCenterX = (left + right) * 0.5
    local bodyCenterY = (bottom + top) * 0.5
    local limitX, limitY = ReadLayoutEnvelopeLimits(bodyWidth, bodyHeight)
    local screenLeft = left
    local screenRight = right

    inputVisualInset = ValidateFiniteNumber(inputVisualInset) or 0
    if inputVisualInset < 0 or inputVisualInset > 32 then
        return nil, "layout-envelope-input-inset-invalid"
    end
    local editBox = targets.editBox
    if editBox and type(editBox.GetRect) == "function" then
        local inputLeft, inputBottom, inputRight, inputTop = ReadSafeRect(
            editBox,
            "layout-envelope-input"
        )
        if inputLeft ~= nil then
            local visualBottom = inputBottom + inputVisualInset
            local visualTop = inputTop - inputVisualInset
            if visualBottom < visualTop
                and IsOptionalEnvelopeRectPlausible(
                    inputLeft,
                    visualBottom,
                    inputRight,
                    visualTop,
                    bodyCenterX,
                    bodyCenterY,
                    limitX,
                    limitY
                )
            then
                if visualBottom < bottom then bottom = visualBottom end
                if visualTop > top then top = visualTop end
            end
        end
    end

    local names = _G.CHAT_FRAMES
    local backend = clientBackend
    local classifier = backend and backend.ClassifyAppearanceTab
    if type(names) ~= "table" or type(classifier) ~= "function" then
        return nil, "layout-envelope-tab-enumerator-unavailable"
    end
    for index = 1, #names do
        local frameName = names[index]
        if self:IsExplicitlySafeValue(frameName) == true
            and type(frameName) == "string"
            and frameName ~= ""
        then
            local candidate = _G[frameName]
            if candidate ~= nil then
                trustedFrames[candidate] = true
                local classifyOK, supported = pcall(classifier, backend, candidate)
                if classifyOK and supported == true then
                    local docked, dockReason = self:ReadAppearanceTabDocked(candidate)
                    if type(docked) == "boolean" and docked then
                        local tabTargets, tabReason = self:GetAppearanceTabTargets(candidate)
                        if tabTargets then
                            local shown = ReadMethod(
                                tabTargets.tab,
                                "IsShown",
                                ValidateBoolean,
                                "layout-envelope-tab-shown"
                            )
                            if shown == true then
                            local tabLeft, tabBottom, tabRight, tabTop = ReadSafeRect(
                                tabTargets.tab,
                                "layout-envelope-tab"
                            )
                                if tabLeft ~= nil
                                    and IsOptionalEnvelopeRectPlausible(
                                        tabLeft,
                                        tabBottom,
                                        tabRight,
                                        tabTop,
                                        bodyCenterX,
                                        bodyCenterY,
                                        limitX,
                                        limitY
                                    )
                                then
                                    if tabLeft < screenLeft then screenLeft = tabLeft end
                                    if tabBottom < bottom then bottom = tabBottom end
                                    if tabRight > screenRight then screenRight = tabRight end
                                    if tabTop > top then top = tabTop end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local centerOK, holderX, holderY = pcall(holder.GetCenter, holder)
    if not centerOK
        or self:IsExplicitlySafeValue(holderX) ~= true
        or self:IsExplicitlySafeValue(holderY) ~= true
        or ValidateFiniteNumber(holderX) == nil
        or ValidateFiniteNumber(holderY) == nil
    then
        return nil, "layout-envelope-holder-center-invalid"
    end
    local width = right - left
    local height = top - bottom
    local screenWidth = screenRight - screenLeft
    local offsetX = ((left + right) * 0.5) - holderX
    local offsetY = ((bottom + top) * 0.5) - holderY
    local screenOffsetX = ((screenLeft + screenRight) * 0.5) - holderX
    if not IsLayoutEnvelopePlausible(
            width,
            height,
            offsetX,
            offsetY,
            limitX,
            limitY
        )
        or not IsLayoutEnvelopePlausible(
            screenWidth,
            height,
            screenOffsetX,
            offsetY,
            limitX,
            limitY
        )
    then
        return bodyWidth, bodyHeight,
            ((bodyLeft + bodyRight) * 0.5) - holderX,
            ((bodyBottom + bodyTop) * 0.5) - holderY,
            bodyWidth, bodyHeight,
            ((bodyLeft + bodyRight) * 0.5) - holderX,
            ((bodyBottom + bodyTop) * 0.5) - holderY
    end
    return width, height, offsetX, offsetY,
        screenWidth, height, screenOffsetX, offsetY
end

local function CallMessageInfo(callback, frame, index)
    return callback(frame, index)
end

function Adapter:ReadNumMessages(frame)
    return ReadMethod(frame, "GetNumMessages", ValidateNonNegativeInteger, "message-count")
end

function Adapter:ReadCopyMessageForExplicitExport(frame, index)
    if not self.enabled or trustedFrames[frame] ~= true then
        return nil, "copy-untrusted-chat-frame"
    end
    local restriction = self:GetRestrictionState()
    if restriction ~= "OPEN" and restriction ~= "PAUSED" then
        return nil, "copy-restriction-not-open"
    end
    local state = frameStates[frame]
    if not state or state.ready ~= true or state.supported ~= true then
        return nil, "copy-unsupported-chat-frame"
    end
    local allowed, protectedReason = self:CanCallProtected(frame)
    if allowed ~= true then return nil, protectedReason or "copy-frame-protected" end
    if type(index) ~= "number"
        or index < 1
        or floor(index) ~= index
    then
        return nil, "copy-message-index-invalid"
    end
    local callback = frame.GetMessageInfo
    if type(callback) ~= "function" then return nil, "copy-message-api-missing" end
    local ok, text, red, green, blue = pcall(CallMessageInfo, callback, frame, index)
    if not ok
        or self:IsExplicitlySafeValue(text) ~= true
        or type(text) ~= "string"
        or text:find("|K", 1, true) ~= nil
    then
        return nil, "copy-message-unsafe"
    end
    local colorsMissing = red == nil and green == nil and blue == nil
    if not colorsMissing and (
        self:IsExplicitlySafeValue(red) ~= true
        or self:IsExplicitlySafeValue(green) ~= true
        or self:IsExplicitlySafeValue(blue) ~= true
        or type(red) ~= "number"
        or type(green) ~= "number"
        or type(blue) ~= "number"
        or red < 0 or red > 1
        or green < 0 or green > 1
        or blue < 0 or blue > 1
        or red ~= red or green ~= green or blue ~= blue
    ) then
        return nil, "copy-message-unsafe"
    end
    return text, red, green, blue
end

function Adapter:ReadScrollOffset(frame)
    return ReadMethod(frame, "GetScrollOffset", ValidateNonNegativeInteger, "scroll-offset")
end

function Adapter:ReadScrollOffsetInCallback(frame)
    if not self.enabled or trustedFrames[frame] ~= true then
        return nil, "untrusted-chat-frame"
    end
    local state = frameStates[frame]
    if not state or not state.ready then return nil, "frame-not-ready" end
    local getter = state.scrollGetter
    if frame.GetScrollOffset ~= getter or type(getter) ~= "function" then
        error("ychat-native-callback-signature-changed")
    end
    local offset, reason = ValidateNonNegativeInteger(getter(frame))
    if offset == nil then return nil, "scroll-offset-" .. (reason or "invalid") end
    return offset
end

function Adapter:ReadMaxLines(frame)
    return ReadMethod(frame, "GetMaxLines", ValidatePositiveInteger, "max-lines")
end

function Adapter:WriteMaxLines(frame, value, suppressInvalidation)
    if not self.enabled or trustedFrames[frame] ~= true then
        return false, "untrusted-chat-frame"
    end
    value = ValidatePositiveInteger(value)
    if value == nil then return false, "max-lines-invalid" end
    local callback = frame and frame.SetMaxLines
    if type(callback) ~= "function" then return false, "missing-max-lines-write" end

    if suppressInvalidation == true then maxLinesWriteSuppressed[frame] = true end
    local ok = pcall(callback, frame, value)
    maxLinesWriteSuppressed[frame] = nil
    if not ok then return false, "max-lines-write-failed" end
    local actual, readReason = self:ReadMaxLines(frame)
    if actual == nil then return false, readReason end
    if actual ~= value then return false, "max-lines-write-unconfirmed" end
    return true
end

function Adapter:ReadSpacing(frame)
    return ReadMethod(frame, "GetSpacing", ValidateFiniteNumber, "spacing")
end

function Adapter:ReadIndentedWordWrap(frame)
    return ReadMethod(frame, "GetIndentedWordWrap", ValidateBoolean, "indent")
end

function Adapter:ReadInsertModeTop(frame)
    return ReadMethod(frame, "GetInsertMode", ValidateInsertMode, "insert-mode")
end

function Adapter:GetNumMessages(frame)
    return self:ReadNumMessages(frame) or 0
end

function Adapter:GetScrollOffset(frame)
    return self:ReadScrollOffset(frame) or 0
end

function Adapter:GetMaxLines(frame)
    return self:ReadMaxLines(frame) or 128
end

function Adapter:GetNumVisibleLines(frame)
    local lines = frame and frame.visibleLines
    return type(lines) == "table" and #lines or 0
end

function Adapter:GetSpacing(frame)
    return self:ReadSpacing(frame) or 0
end

function Adapter:GetIndentedWordWrap(frame)
    local value = self:ReadIndentedWordWrap(frame)
    if value == nil then return true end
    return value
end

function Adapter:CanCallProtected(object)
    if object == nil then return false, "protected-object-missing" end
    if self.clientBackendConflict then return false, "client-backend-conflict" end
    local backend = clientBackend
    local callback = backend and backend.CanCallProtected
    if type(callback) ~= "function" then return false, "client-backend-unavailable" end

    local ok, allowed, reason = pcall(callback, backend, object)
    if not ok then return false, "protected-check-error" end
    if allowed ~= true then return false, reason or "protected-write-denied" end
    return true
end

function Adapter:ResolveBNetAccountID(name, candidateID)
    if (self.clientFlavor ~= "mainline" and self.clientFlavor ~= "forever") then
        return nil, "bnet-account-resolution-mainline-only"
    end
    if self.clientBackendConflict then
        return nil, "client-backend-conflict"
    end
    local backend = clientBackend
    local callback = backend and backend.ResolveBNetAccountID
    if type(callback) ~= "function" then
        return nil, "bnet-account-resolution-unavailable"
    end
    local ok, accountID, reason = pcall(callback, backend, name, candidateID)
    if not ok then return nil, "bnet-account-resolution-error" end
    if accountID == nil then return nil, reason end
    if type(accountID) ~= "number"
        or accountID < 1
        or floor(accountID) ~= accountID
        or self:IsExplicitlySafeValue(accountID) ~= true
    then
        return nil, "bnet-account-resolution-invalid"
    end
    return accountID
end

function Adapter:ReadInstanceState()
    if self.clientBackendConflict then
        return nil, nil, "client-backend-conflict"
    end
    local backend = clientBackend
    local callback = backend and backend.ReadInstanceState
    if type(callback) ~= "function" then
        return nil, nil, "instance-state-backend-unavailable"
    end
    local ok, inInstance, instanceType, reason = pcall(callback, backend)
    if not ok then return nil, nil, "instance-state-read-error" end
    if type(inInstance) ~= "boolean" or type(instanceType) ~= "string" then
        return nil, nil, reason or "instance-state-invalid"
    end
    return inInstance, instanceType, nil
end

function Adapter:PreflightVisibleLayout(frame)
    local lines = frame and frame.visibleLines
    if type(lines) ~= "table" then return false, "missing-visible-lines" end
    if type(frame.GetWidth) ~= "function" then
        return false, "visible-frame-width-api-missing"
    end

    for index = 1, #lines do
        local line = lines[index]
        if not line
            or type(line.ClearAllPoints) ~= "function"
            or type(line.SetPoint) ~= "function"
            or type(line.SetWidth) ~= "function"
        then
            return false, "visible-line-write-api-missing"
        end
        local allowed, reason = self:CanCallProtected(line)
        if not allowed then return false, reason end
    end
    return true
end

function Adapter:ApplyVisibleLayout(
    frame,
    bodyInset,
    rightInset,
    spacing,
    topInsert,
    verticalInset
)
    local allowed, reason = self:PreflightVisibleLayout(frame)
    if not allowed then return false, reason end
    verticalInset = verticalInset or 0
    bodyInset = ValidateFiniteNumber(bodyInset)
    rightInset = ValidateFiniteNumber(rightInset)
    spacing = ValidateFiniteNumber(spacing)
    verticalInset = ValidateFiniteNumber(verticalInset)
    if bodyInset == nil or bodyInset < 0
        or rightInset == nil or rightInset < 0
        or spacing == nil or spacing < 0
        or verticalInset == nil
        or verticalInset < 0
        or verticalInset > 16
    then
        return false, "visible-line-vertical-inset-invalid"
    end

    local widthOK, frameWidth = pcall(frame.GetWidth, frame)
    if not widthOK or IsSecretValue(frameWidth) then
        return false, "visible-frame-width-read-failed"
    end
    frameWidth = ValidatePositiveFiniteNumber(frameWidth)
    if frameWidth == nil then return false, "visible-frame-width-invalid" end
    local lineWidth = frameWidth - bodyInset - rightInset
    if lineWidth < 1 then return false, "visible-line-width-invalid" end
    local gui = YUI.GUI
    if gui and type(gui.GetPixelSize) == "function" then
        local pixelOK, pixel = pcall(gui.GetPixelSize, gui, frame, 1, 1)
        pixel = pixelOK and ValidatePositiveFiniteNumber(pixel) or nil
        if pixel then lineWidth = floor(lineWidth / pixel + 0.5) * pixel end
    end
    if lineWidth < 1 then return false, "visible-line-width-invalid" end

    local lines = frame.visibleLines
    local previous
    for index = 1, #lines do
        local line = lines[index]
        local ok = pcall(line.ClearAllPoints, line)
        if not ok then return false, "native-line-clear-failed" end

        if previous then
            if topInsert then
                ok = pcall(line.SetPoint, line, "TOPLEFT", previous, "BOTTOMLEFT", 0, -spacing)
            else
                ok = pcall(line.SetPoint, line, "BOTTOMLEFT", previous, "TOPLEFT", 0, spacing)
            end
        elseif topInsert then
            ok = pcall(
                line.SetPoint,
                line,
                "TOPLEFT",
                frame,
                "TOPLEFT",
                bodyInset,
                -verticalInset
            )
        else
            ok = pcall(
                line.SetPoint,
                line,
                "BOTTOMLEFT",
                frame,
                "BOTTOMLEFT",
                bodyInset,
                verticalInset
            )
        end
        if not ok then return false, "native-line-anchor-failed" end

        ok = pcall(line.SetWidth, line, lineWidth)
        if not ok then return false, "native-line-width-write-failed" end
        previous = line
    end
    return true
end

function Adapter:PreflightTimestampOverlays(overlays, count)
    if type(overlays) ~= "table" then return false, "timestamp-overlays-missing" end
    for index = 1, count do
        local overlay = overlays[index]
        if not overlay or type(overlay.ClearAllPoints) ~= "function" or type(overlay.SetPoint) ~= "function" then
            return false, "timestamp-overlay-write-api-missing"
        end
        local allowed, reason = self:CanCallProtected(overlay)
        if not allowed then return false, reason end
    end
    return true
end

function Adapter:SetIndentedWordWrap(frame, enabled)
    local callback = frame and frame.SetIndentedWordWrap
    if type(callback) ~= "function" then return false, "missing-indent-api" end
    local allowed, reason = self:CanCallProtected(frame)
    if not allowed then return false, reason end
    local ok = pcall(callback, frame, enabled == true)
    if not ok then return false, "indent-write-failed" end
    return true
end

function Adapter:RequestNativeLayout(frame)
    local callback = frame and frame.MarkLayoutDirty
    if type(callback) ~= "function" then return false, "missing-layout-dirty" end
    local allowed, reason = self:CanCallProtected(frame)
    if not allowed then return false, reason end
    local ok = pcall(callback, frame)
    if not ok then return false, "layout-request-failed" end
    return true
end

function Adapter:RestoreNativeLayout(frame, originalIndent)
    return self:SetIndentedWordWrap(frame, originalIndent ~= false)
end

function Adapter:AllocateOverlayHost(frame)
    if type(CreateFrame) ~= "function" then return nil, "frame-api-unavailable" end
    local allowed, reason = self:CanCallProtected(frame)
    if not allowed then return nil, reason end

    local created, host = pcall(CreateFrame, "Frame", nil, frame)
    if not created or not host then return nil, "overlay-host-create-failed" end
    return host
end

function Adapter:ConfigureOverlayHost(host, frame)
    if not host then return false, "overlay-host-missing" end
    if type(host.Hide) ~= "function"
        or type(host.SetClipsChildren) ~= "function"
        or type(host.ClearAllPoints) ~= "function"
        or type(host.SetAllPoints) ~= "function"
    then
        return false, "overlay-host-write-api-missing"
    end

    local allowed, reason = self:CanCallProtected(frame)
    if not allowed then return false, reason end
    allowed, reason = self:CanCallProtected(host)
    if not allowed then return false, reason end

    local hidden = pcall(host.Hide, host)
    if not hidden then return false, "overlay-host-hide-failed" end
    local shown, shownReason = ReadMethod(host, "IsShown", ValidateBoolean, "overlay-host-shown")
    if shown == nil then return false, shownReason end
    if shown ~= false then return false, "overlay-host-hide-unconfirmed" end
    local clipped = pcall(host.SetClipsChildren, host, true)
    if not clipped then return false, "overlay-host-clipping-failed" end
    local cleared = pcall(host.ClearAllPoints, host)
    if not cleared then return false, "overlay-host-clear-failed" end
    local anchored = pcall(host.SetAllPoints, host, frame)
    if not anchored then return false, "overlay-host-anchor-failed" end
    return true
end

function Adapter:IsolateOverlayHost(host)
    return self:SetOverlayHostShown(host, false)
end

function Adapter:AllocateTimestampOverlay(host)
    local allowed, reason = self:CanCallProtected(host)
    if not allowed then return nil, reason end
    local callback = host and host.CreateFontString
    if type(callback) ~= "function" then return nil, "font-string-api-unavailable" end

    local created, overlay = pcall(callback, host, nil, "OVERLAY")
    if not created or not overlay then return nil, "timestamp-overlay-create-failed" end
    return overlay
end

function Adapter:ConfigureTimestampOverlayFont(
    overlay,
    fontFile,
    fontHeight,
    fontFlags,
    shadowR,
    shadowG,
    shadowB,
    shadowA,
    shadowX,
    shadowY
)
    if not overlay then return false, "timestamp-overlay-missing" end
    local setFont = overlay.SetFont
    if type(setFont) ~= "function" then return false, "timestamp-overlay-font-api-missing" end
    local getFont = overlay.GetFont
    if type(getFont) ~= "function" then return false, "timestamp-overlay-font-readback-api-missing" end

    local allowed, reason = self:CanCallProtected(overlay)
    if not allowed then return false, reason end

    local normalizedFontFile = NormalizeFontFile(fontFile)
    local validHeight = ValidatePositiveFiniteNumber(fontHeight)
    if normalizedFontFile == nil or validHeight == nil or type(fontFlags) ~= "string" then
        return false, "timestamp-font-style-invalid"
    end

    local hasShadowStyle = shadowR ~= nil
        or shadowG ~= nil
        or shadowB ~= nil
        or shadowA ~= nil
        or shadowX ~= nil
        or shadowY ~= nil
    if hasShadowStyle then
        if type(overlay.SetShadowColor) ~= "function"
            or type(overlay.GetShadowColor) ~= "function"
            or type(overlay.SetShadowOffset) ~= "function"
            or type(overlay.GetShadowOffset) ~= "function"
        then
            return false, "timestamp-overlay-shadow-api-missing"
        end
        shadowR = ValidateFiniteNumber(shadowR)
        shadowG = ValidateFiniteNumber(shadowG)
        shadowB = ValidateFiniteNumber(shadowB)
        shadowA = ValidateFiniteNumber(shadowA)
        shadowX = ValidateFiniteNumber(shadowX)
        shadowY = ValidateFiniteNumber(shadowY)
        if shadowR == nil or shadowR < 0 or shadowR > 1
            or shadowG == nil or shadowG < 0 or shadowG > 1
            or shadowB == nil or shadowB < 0 or shadowB > 1
            or shadowA == nil or shadowA < 0 or shadowA > 1
            or shadowX == nil or shadowY == nil
        then
            return false, "timestamp-shadow-style-invalid"
        end
    end

    local fontSet, applied = pcall(setFont, overlay, fontFile, validHeight, fontFlags)
    if not fontSet or applied == false then return false, "timestamp-overlay-font-failed" end

    local readbackOK, confirmed = pcall(
        CallAndValidateTimestampFontReadback,
        getFont,
        overlay,
        normalizedFontFile,
        validHeight,
        fontFlags
    )
    if not readbackOK or confirmed ~= true then
        return false, "timestamp-overlay-font-unconfirmed"
    end
    if hasShadowStyle then
        if not pcall(overlay.SetShadowColor, overlay, shadowR, shadowG, shadowB, shadowA)
            or not pcall(overlay.SetShadowOffset, overlay, shadowX, shadowY)
        then
            return false, "timestamp-overlay-shadow-failed"
        end
        local colorOK, actualR, actualG, actualB, actualA =
            pcall(overlay.GetShadowColor, overlay)
        local offsetOK, actualX, actualY = pcall(overlay.GetShadowOffset, overlay)
        if not colorOK or not offsetOK
            or IsSecretValue(actualR) or IsSecretValue(actualG)
            or IsSecretValue(actualB) or IsSecretValue(actualA)
            or IsSecretValue(actualX) or IsSecretValue(actualY)
            or actualR ~= shadowR or actualG ~= shadowG
            or actualB ~= shadowB or actualA ~= shadowA
            or actualX ~= shadowX or actualY ~= shadowY
        then
            return false, "timestamp-overlay-shadow-unconfirmed"
        end
    end
    return true
end

function Adapter:ConfigureTimestampOverlayFontObject(overlay, fontObject)
    if not overlay then return false, "timestamp-overlay-missing" end
    if fontObject == nil
        or IsSecretValue(fontObject)
        or type(fontObject.GetFont) ~= "function"
    then
        return false, "timestamp-font-object-invalid"
    end
    local setFontObject = overlay.SetFontObject
    local getFontObject = overlay.GetFontObject
    if type(setFontObject) ~= "function" or type(getFontObject) ~= "function" then
        return false, "timestamp-overlay-font-object-api-missing"
    end
    local allowed, reason = self:CanCallProtected(overlay)
    if not allowed then return false, reason end
    if not pcall(setFontObject, overlay, fontObject) then
        return false, "timestamp-overlay-font-object-failed"
    end
    local readbackOK, confirmed = pcall(getFontObject, overlay)
    if not readbackOK
        or confirmed == nil
        or IsSecretValue(confirmed)
        or confirmed ~= fontObject
    then
        return false, "timestamp-overlay-font-object-unconfirmed"
    end
    return true
end

function Adapter:MeasureTimestampOverlayWidth(overlay, sample)
    if not overlay then return nil, "timestamp-overlay-missing" end
    if type(sample) ~= "string" or sample == "" then
        return nil, "timestamp-overlay-sample-invalid"
    end
    if type(overlay.SetText) ~= "function"
        or type(overlay.GetUnboundedStringWidth) ~= "function"
    then
        return nil, "timestamp-overlay-measure-api-missing"
    end

    local allowed, reason = self:CanCallProtected(overlay)
    if not allowed then return nil, reason end
    if not pcall(overlay.SetText, overlay, sample) then
        return nil, "timestamp-overlay-sample-text-failed"
    end
    return ReadMethod(
        overlay,
        "GetUnboundedStringWidth",
        ValidatePositiveFiniteNumber,
        "timestamp-overlay-sample-width"
    )
end

function Adapter:ConfigureTimestampOverlay(overlay, width, color, placeholder)
    if not overlay then return false, "timestamp-overlay-missing" end
    if type(overlay.Hide) ~= "function"
        or type(overlay.SetWidth) ~= "function"
        or type(overlay.SetJustifyH) ~= "function"
        or type(overlay.SetWordWrap) ~= "function"
        or type(overlay.SetTextColor) ~= "function"
        or type(overlay.SetText) ~= "function"
    then
        return false, "timestamp-overlay-configure-api-missing"
    end

    local allowed, reason = self:CanCallProtected(overlay)
    if not allowed then return false, reason end

    local hidden, hideReason = self:HideOverlay(overlay)
    if not hidden then return false, hideReason end
    local widthOK = pcall(overlay.SetWidth, overlay, width)
    if not widthOK then return false, "timestamp-overlay-width-failed" end
    if not pcall(overlay.SetJustifyH, overlay, "LEFT") then
        return false, "timestamp-overlay-justify-failed"
    end
    if not pcall(overlay.SetWordWrap, overlay, false) then
        return false, "timestamp-overlay-wrap-failed"
    end
    if type(color) ~= "table" then
        color = { 0.62, 0.72, 0.82, 0.95 }
    end
    local red = ValidateFiniteNumber(color[1])
    local green = ValidateFiniteNumber(color[2])
    local blue = ValidateFiniteNumber(color[3])
    local alpha = ValidateFiniteNumber(color[4])
    if red == nil or green == nil or blue == nil or alpha == nil
        or red < 0 or red > 1 or green < 0 or green > 1
        or blue < 0 or blue > 1 or alpha < 0 or alpha > 1
    then
        return false, "timestamp-overlay-color-invalid"
    end
    if not pcall(overlay.SetTextColor, overlay, red, green, blue, alpha) then
        return false, "timestamp-overlay-color-failed"
    end
    if type(placeholder) ~= "string" then placeholder = "--:--:--" end
    if not pcall(overlay.SetText, overlay, placeholder) then
        return false, "timestamp-overlay-text-failed"
    end
    return true
end

function Adapter:IsolateTimestampOverlay(overlay)
    return self:HideOverlay(overlay)
end

function Adapter:AnchorTimestampOverlay(overlay, line, width, gap)
    local allowed, reason = self:CanCallProtected(overlay)
    if not allowed then return false, reason end
    local validWidth = ValidatePositiveFiniteNumber(width)
    local validGap = ValidateFiniteNumber(gap)
    if validWidth == nil or validGap == nil or validGap < 0 then
        return false, "timestamp-overlay-anchor-metrics-invalid"
    end

    local ok = pcall(overlay.ClearAllPoints, overlay)
    if not ok then return false, "timestamp-overlay-clear-failed" end
    ok = pcall(
        overlay.SetPoint,
        overlay,
        "TOPLEFT",
        line,
        "TOPLEFT",
        -(validWidth + validGap),
        0
    )
    if not ok then return false, "timestamp-overlay-anchor-failed" end
    if not pcall(overlay.SetAlpha, overlay, 1) then return false, "timestamp-overlay-alpha-failed" end
    return self:HideOverlay(overlay)
end

function Adapter:SetOverlayHostShown(host, shown)
    local allowed, reason = self:CanCallProtected(host)
    if not allowed then return false, reason end
    local callback = shown and host.Show or host.Hide
    if type(callback) ~= "function" then return false, "overlay-host-visibility-api-missing" end
    if not pcall(callback, host) then return false, "overlay-host-visibility-failed" end
    local actual, actualReason = ReadMethod(host, "IsShown", ValidateBoolean, "overlay-host-shown")
    if actual == nil then return false, actualReason end
    if actual ~= (shown == true) then return false, "overlay-host-visibility-unconfirmed" end
    return true
end

function Adapter:SetOverlayAlpha(overlay, value)
    if not overlay or type(overlay.SetAlpha) ~= "function" then
        return false, "timestamp-overlay-alpha-api-missing"
    end
    if not pcall(overlay.SetAlpha, overlay, value) then
        return false, "timestamp-overlay-alpha-failed"
    end
    return true
end

function Adapter:SetOverlayAlphaInCallback(overlay, value)
    local callback = overlay and overlay.SetAlpha
    if type(callback) ~= "function" then
        return false, "timestamp-overlay-alpha-api-missing"
    end
    callback(overlay, value)
    return true
end

function Adapter:SetOverlayTextInCallback(overlay, value)
    local callback = overlay and overlay.SetText
    if type(callback) ~= "function" then
        return false, "timestamp-overlay-text-api-missing"
    end
    callback(overlay, value)
    return true
end

function Adapter:SetLineSyncEnabled(enabled)
    enabled = enabled == true
    if enabled and not self.enabled then return false, "adapter-disabled" end
    self.lineSyncEnabled = enabled
    return true
end

function Adapter:SetDisplaySyncEnabled(enabled)
    enabled = enabled == true
    if enabled and not self.enabled then return false, "adapter-disabled" end
    self.displaySyncEnabled = enabled
    if not enabled then return true end
    for frame, state in pairs(frameStates) do
        if state.ready == true
            and state.supported == true
            and not EnsureDisplayCallback(state, frame)
        then
            self.displaySyncEnabled = false
            return false, "display-hook-install-failed"
        end
    end
    return true
end

function Adapter:ReadMonotonicTime()
    local callback = _G.GetTime
    if type(callback) ~= "function" then
        return nil, "monotonic-time-api-missing"
    end
    local ok, value = pcall(callback)
    if not ok
        or type(value) ~= "number"
        or value < 0
        or not (value > -math.huge and value < math.huge)
    then
        return nil, "monotonic-time-invalid"
    end
    return value
end

function Adapter:CreateOneShotTimer(delay, callback)
    local timerAPI = _G.C_Timer
    local newTimer = timerAPI and timerAPI.NewTimer
    if type(newTimer) ~= "function" or type(callback) ~= "function" then
        return nil, "one-shot-timer-api-missing"
    end
    if type(delay) ~= "number"
        or delay < 0
        or not (delay > -math.huge and delay < math.huge)
    then
        return nil, "one-shot-timer-delay-invalid"
    end
    local ok, timer = pcall(newTimer, delay, callback)
    if not ok or timer == nil or type(timer.Cancel) ~= "function" then
        return nil, "one-shot-timer-create-failed"
    end
    return timer
end

function Adapter:CancelOneShotTimer(timer)
    if timer == nil then return true end
    local cancel = timer.Cancel
    if type(cancel) ~= "function" then
        return false, "one-shot-timer-cancel-api-missing"
    end
    if not pcall(cancel, timer) then
        return false, "one-shot-timer-cancel-failed"
    end
    return true
end

ReconcileDeferredDriver = function(self)
    local frame = self.eventFrame
    local setScript = frame and frame.SetScript
    if type(setScript) ~= "function" then return false, "deferred-driver-api-missing" end

    local requested = self.deferredDriverEnabled == true
        or self.messageDeferredDriverEnabled == true
        or self.channelDeferredDriverEnabled == true
    if requested then
        if self.deferredDriverInstalled then
            self.deferredDriverCleanupFailed = false
            return true
        end
        if not pcall(setScript, frame, "OnUpdate", DeferredDriverOnUpdate) then
            return false, "deferred-driver-script-failed"
        end
        self.deferredDriverInstalled = true
        self.deferredDriverCleanupFailed = false
        self.deferredDriverRunFrames = 0
        return true
    end

    if not self.deferredDriverInstalled then
        self.deferredDriverCleanupFailed = false
        return true
    end
    if not pcall(setScript, frame, "OnUpdate", nil) then
        self.deferredDriverCleanupFailed = true
        return false, "deferred-driver-script-failed"
    end
    self.deferredDriverInstalled = false
    self.deferredDriverCleanupFailed = false
    return true
end

function Adapter:SetDeferredDriverEnabled(enabled)
    enabled = enabled == true
    if enabled and not self.enabled then return false, "adapter-disabled" end
    local previous = self.deferredDriverEnabled
    self.deferredDriverEnabled = enabled
    local reconciled, reason = ReconcileDeferredDriver(self)
    if not reconciled and enabled then self.deferredDriverEnabled = previous end
    return reconciled, reason
end

function Adapter:SetMessageDeferredCallback(callback)
    if callback ~= nil and type(callback) ~= "function" then
        return false, "message-deferred-callback-invalid"
    end
    self.messageDeferredCallback = callback
    if callback == nil and self.messageDeferredDriverEnabled then
        self.messageDeferredDriverEnabled = false
        return ReconcileDeferredDriver(self)
    end
    return true
end

function Adapter:SetMessageDeferredDriverEnabled(enabled)
    enabled = enabled == true
    if enabled and not self.enabled then return false, "adapter-disabled" end
    if enabled and type(self.messageDeferredCallback) ~= "function" then
        return false, "message-deferred-callback-missing"
    end
    local previous = self.messageDeferredDriverEnabled
    self.messageDeferredDriverEnabled = enabled
    local reconciled, reason = ReconcileDeferredDriver(self)
    if not reconciled and enabled then self.messageDeferredDriverEnabled = previous end
    return reconciled, reason
end

function Adapter:SetChannelDeferredCallback(callback)
    if callback ~= nil and type(callback) ~= "function" then
        return false, "channel-deferred-callback-invalid"
    end
    self.channelDeferredCallback = callback
    if callback == nil and self.channelDeferredDriverEnabled then
        self.channelDeferredDriverEnabled = false
        return ReconcileDeferredDriver(self)
    end
    return true
end

function Adapter:SetChannelDeferredDriverEnabled(enabled)
    enabled = enabled == true
    if enabled and not self.enabled then return false, "adapter-disabled" end
    if enabled and type(self.channelDeferredCallback) ~= "function" then
        return false, "channel-deferred-callback-missing"
    end
    local previous = self.channelDeferredDriverEnabled
    self.channelDeferredDriverEnabled = enabled
    local reconciled, reason = ReconcileDeferredDriver(self)
    if not reconciled and enabled then self.channelDeferredDriverEnabled = previous end
    return reconciled, reason
end

function Adapter:SetChannelTransformCallback(callback)
    if callback ~= nil and type(callback) ~= "function" then
        return false, "channel-transform-callback-invalid"
    end
    self.channelTransformCallback = callback
    return true
end

function Adapter:TransformChannelMessages(frame, predicate, transformer)
    if (self.clientFlavor ~= "mainline" and self.clientFlavor ~= "forever") then
        return false, "channel-transform-mainline-only"
    end
    if not self.enabled or self.restrictionState ~= "OPEN" then
        return false, "channel-transform-restricted"
    end
    if not self:IsTrustedSupportedFrame(frame) then
        return false, "channel-transform-untrusted-frame"
    end
    if type(predicate) ~= "function" or type(transformer) ~= "function" then
        return false, "channel-transform-callback-invalid"
    end
    local transform = frame and frame.TransformMessages
    if type(transform) ~= "function" then
        return false, "channel-transform-api-unavailable"
    end
    channelTransformSuppressed[frame] = true
    local ok = pcall(transform, frame, predicate, transformer)
    channelTransformSuppressed[frame] = nil
    if not ok then return false, "channel-transform-failed" end
    return true
end

function Adapter:IsDeferredDriverEnabled()
    return self.deferredDriverInstalled == true
end

function Adapter:HasDeferredDriverCleanupFailure()
    return self.deferredDriverCleanupFailed == true
end

function Adapter:ShowOverlay(overlay)
    if not overlay or type(overlay.Show) ~= "function" then
        return false, "timestamp-overlay-show-api-missing"
    end
    if not pcall(overlay.Show, overlay) then return false, "timestamp-overlay-show-failed" end
    local shown, shownReason = ReadMethod(overlay, "IsShown", ValidateBoolean, "timestamp-overlay-shown")
    if shown == nil then return false, shownReason end
    if shown ~= true then return false, "timestamp-overlay-show-unconfirmed" end
    return true
end

function Adapter:HideOverlay(overlay)
    if not overlay or type(overlay.Hide) ~= "function" then
        return false, "timestamp-overlay-hide-api-missing"
    end
    if not pcall(overlay.Hide, overlay) then return false, "timestamp-overlay-hide-failed" end
    local shown, shownReason = ReadMethod(overlay, "IsShown", ValidateBoolean, "timestamp-overlay-shown")
    if shown == nil then return false, shownReason end
    if shown ~= false then return false, "timestamp-overlay-hide-unconfirmed" end
    return true
end

function Adapter:IsInsertModeTop(frame)
    return self:ReadInsertModeTop(frame) == true
end

function Adapter:EnsureVisibleLineHooks(frame)
    local lines = frame and frame.visibleLines
    if type(lines) ~= "table" then return false, "missing-visible-lines" end
    if type(hooksecurefunc) ~= "function" then return false, "fade-hook-unsupported" end

    for index = 1, #lines do
        local line = lines[index]
        if line then
            local state = lineHookStates[line] or 0
            if state % 2 < 1 then
                local ok = pcall(hooksecurefunc, line, "SetAlpha", LineAlphaHook)
                if not ok then return false, "fade-hook-unsupported" end
                state = state + 1
                lineHookStates[line] = state
                RecordPermanentHook()
            end
            if state % 4 < 2 then
                local ok = pcall(hooksecurefunc, line, "Show", LineShowHook)
                if not ok then return false, "fade-hook-unsupported" end
                state = state + 2
                lineHookStates[line] = state
                RecordPermanentHook()
            end
            if state < 4 then
                local ok = pcall(hooksecurefunc, line, "Hide", LineHideHook)
                if not ok then return false, "fade-hook-unsupported" end
                state = state + 4
                lineHookStates[line] = state
                RecordPermanentHook()
            end
        end
    end
    return true
end

function Adapter:BindVisibleLineOverlay(line, overlay)
    if not self.enabled
        or not line
        or not overlay
        or type(overlay.SetAlpha) ~= "function"
        or (lineHookStates[line] or 0) % 2 < 1
    then
        return false, "visible-line-overlay-binding-invalid"
    end
    lineOverlayByLine[line] = overlay
    lineAlphaSetterByLine[line] = overlay.SetAlpha
    return true
end

function Adapter:UnbindVisibleLineOverlay(line, overlay)
    if not line then return false end
    local current = lineOverlayByLine[line]
    if overlay ~= nil and current ~= overlay then
        return false, "visible-line-overlay-binding-mismatch"
    end
    lineOverlayByLine[line] = nil
    lineAlphaSetterByLine[line] = nil
    return true
end

function Adapter:ResetVisibleLineSyncStates(frame)
    local state = frameStates[frame]
    local lines = state and state.visibleLines
    if not self.enabled
        or trustedFrames[frame] ~= true
        or not state
        or not state.ready
        or frame.visibleLines ~= lines
        or type(lines) ~= "table"
    then
        return false, "visible-line-sync-state-unavailable"
    end
    for index = 1, #lines do
        lineShownStates[lines[index]] = nil
    end
    return true
end

function Adapter:FindFrame(name)
    if type(name) ~= "string" or name == "" then name = "ChatFrame1" end
    local frame = _G[name]
    if not frame or not trustedFrames[frame] then return nil end
    local valid = self:ValidateFrame(frame)
    if not valid then return nil end
    local state = frameStates[frame]
    if not state or not state.ready then
        local registered = self:RegisterFrame(frame)
        if not registered then return nil end
    end
    return frame
end

function Adapter:GetRestrictionState()
    return self.restrictionState
end

function Adapter:RefreshRestrictionState()
    if self.clientBackendConflict then return SetRestrictionState("UNKNOWN") end
    local backend = clientBackend
    local callback = backend and backend.ReadRestrictionState
    if type(callback) ~= "function" then return SetRestrictionState("UNKNOWN") end

    local ok, state = pcall(callback, backend)
    if not ok then return SetRestrictionState("UNKNOWN") end
    return SetRestrictionState(state)
end

function Adapter:Enable(callbacks)
    if self.clientBackendConflict or not clientBackend then
        SetRestrictionState("UNKNOWN")
        return false, self.clientBackendConflict and "client-backend-conflict" or "client-backend-unavailable"
    end
    if type(CreateFrame) ~= "function" then return false, "frame-api-unavailable" end

    self.lineSyncEnabled = false
    self.displaySyncEnabled = false
    self.deferredDriverEnabled = false
    self.messageDeferredDriverEnabled = false
    self.messageDeferredCallback = nil
    self.channelDeferredDriverEnabled = false
    self.channelDeferredCallback = nil
    self.channelTransformCallback = nil
    self.deferredDriverInstalled = false
    self.deferredDriverCleanupFailed = false
    self.callbacks = callbacks
    self.enabled = true
    self:RefreshWhisperClassColorCache()

    if not self.eventFrame then self.eventFrame = CreateFrame("Frame", "YUI_YChat_AdapterEventFrame") end
    self.eventFrame:SetScript("OnUpdate", nil)
    self.eventFrame:SetScript("OnEvent", AdapterEventHook)
    self.eventFrame:UnregisterAllEvents()
    self.eventFrame:RegisterEvent("UPDATE_CHAT_WINDOWS")
    self.eventFrame:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
    self.eventFrame:RegisterEvent("ADDON_LOADED")
    self.eventFrame:RegisterEvent("CHANNEL_UI_UPDATE")
    self.eventFrame:RegisterEvent("CHANNEL_COUNT_UPDATE")

    local registered, clientListenerCount = pcall(clientBackend.RegisterEvents, clientBackend, self.eventFrame)
    if not registered
        or type(clientListenerCount) ~= "number"
        or clientListenerCount < 0
        or floor(clientListenerCount) ~= clientListenerCount
    then
        self.eventFrame:UnregisterAllEvents()
        self.eventFrame:SetScript("OnUpdate", nil)
        self.eventFrame:SetScript("OnEvent", nil)
        self.callbacks = nil
        self.enabled = false
        self.lineSyncEnabled = false
        self.deferredDriverEnabled = false
        self.messageDeferredDriverEnabled = false
        self.messageDeferredCallback = nil
        self.channelDeferredDriverEnabled = false
        self.channelDeferredCallback = nil
        self.channelTransformCallback = nil
        self.deferredDriverInstalled = false
        self.deferredDriverCleanupFailed = false
        self.deferredDriverRunFrames = 0
        self.listenerCount = 0
        SetRestrictionState("UNKNOWN")
        return false, "client-event-registration-failed"
    end

    local listenerCount = 3 + clientListenerCount
    self.listenerCount = listenerCount
    UpdateListenerGauge()

    EnsureWindowLifecycleHooks()

    self:RefreshRestrictionState()
    self:ForEachFrame(RegisterDiscoveredFrame)
    return true
end

function Adapter:Disable()
    local tooltipDisabled, tooltipReason = self:SetHyperlinkTooltipEnabled(false)
    if not tooltipDisabled then return false, tooltipReason end
    inputReplyCallback = nil
    self.lineSyncEnabled = false
    self.displaySyncEnabled = false
    self.deferredDriverEnabled = false
    self.messageDeferredDriverEnabled = false
    self.messageDeferredCallback = nil
    self.channelDeferredDriverEnabled = false
    self.channelDeferredCallback = nil
    self.channelTransformCallback = nil
    for frame in pairs(temporaryTypographyFrames) do
        temporaryTypographyFrames[frame] = nil
    end
    if self.eventFrame then
        local unregister = self.eventFrame.UnregisterAllEvents
        local setScript = self.eventFrame.SetScript
        if type(unregister) ~= "function" or type(setScript) ~= "function" then
            return false, "event-frame-cleanup-api-missing"
        end
        if not pcall(unregister, self.eventFrame) then
            return false, "event-frame-unregister-failed"
        end
        if not pcall(setScript, self.eventFrame, "OnUpdate", nil) then
            self.deferredDriverCleanupFailed = true
            return false, "event-frame-driver-clear-failed"
        end
        self.deferredDriverInstalled = false
        self.deferredDriverCleanupFailed = false
        if not pcall(setScript, self.eventFrame, "OnEvent", nil) then
            return false, "event-frame-script-clear-failed"
        end
    end
    self.deferredDriverEnabled = false
    self.messageDeferredDriverEnabled = false
    self.messageDeferredCallback = nil
    self.channelDeferredDriverEnabled = false
    self.channelDeferredCallback = nil
    self.channelTransformCallback = nil
    self.deferredDriverInstalled = false
    self.deferredDriverCleanupFailed = false
    self.deferredDriverRunFrames = 0
    self.enabled = false
    self.callbacks = nil
    self.listenerCount = 0
    UpdateListenerGauge()
    return true
end

function Adapter:IsEnabled()
    return self.enabled == true
end

function Adapter:GetRuntimeGauges(target)
    target = target or {}
    local supported = 0
    local bypassed = 0
    for _, state in pairs(frameStates) do
        if state.supported == true then
            supported = supported + 1
        elseif state.classification ~= nil then
            bypassed = bypassed + 1
        end
    end
    target.listeners = (self.listenerCount or 0) + (self.tooltipListenerCount or 0)
    target.messageHooks = self.messageHookCount or 0
    target.restrictionState = self.restrictionState or "UNKNOWN"
    target.supportedFrames = supported
    target.bypassedFrames = bypassed
    target.tooltipCleanupPending = self.tooltipCleanupPending and 1 or 0
    target.channelLinkTakeoverFrames = 0
    target.channelLinkHoverDrivers = 0
    target.deferredDriverInstalled = self.deferredDriverInstalled == true
    target.deferredDriverRestoreRequested = self.deferredDriverEnabled == true
    target.deferredDriverMessageRequested = self.messageDeferredDriverEnabled == true
    target.deferredDriverChannelRequested = self.channelDeferredDriverEnabled == true
    target.deferredDriverRunFrames = self.deferredDriverRunFrames or 0
    target.deferredDriverCleanupFailed = self.deferredDriverCleanupFailed == true
    return target
end

local cpuWatchdog = YUI.CPUWatchdog
if cpuWatchdog and cpuWatchdog.RegisterProbe then
    cpuWatchdog:RegisterProbe("product.ychat-driver", {
        localeKey = "cpu_watch.probe.ychat_driver",
        kind = "frame",
        getTarget = function() return Adapter.eventFrame end,
        snapshot = function()
            local target = Adapter:GetRuntimeGauges({})
            target.running = Adapter.deferredDriverInstalled == true
                or Adapter.deferredDriverEnabled == true
            return target
        end,
        activityFields = { "listeners", "messageHooks", "tooltipCleanupPending" },
    })
end

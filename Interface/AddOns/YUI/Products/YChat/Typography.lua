local YUI = _G.YUI
local YChat = YUI and YUI.YChat
if not YChat or (YUI.IsForever or YUI.IsRetail) ~= true then return end

local Adapter = YChat.Adapter
if not Adapter then return end

local Typography = {}
YChat.Typography = Typography

local LibStub = _G.LibStub
local LSM = type(LibStub) == "function" and LibStub("LibSharedMedia-3.0", true) or nil
local pairs = pairs
local pcall = pcall
local type = type
local upper = string.upper
local gmatch = string.gmatch
local concat = table.concat

local states = setmetatable({}, { __mode = "k" })
local TEMPORARY_TYPOGRAPHY_CLASS = "temporary-whisper-typography-frame"

Typography.enabled = false
Typography.lastFailure = "none"

local function StatIncrement(field)
    local stats = YChat.Stats
    if stats and stats.Increment then stats:Increment(field) end
end

local function StatSet(field, value)
    local stats = YChat.Stats
    if stats and stats.Set then stats:Set(field, value) end
end

local function StripOutlineFlags(flags)
    if type(flags) ~= "string" then return "" end
    local values = {}
    for token in gmatch(flags, "[^,%s]+") do
        local normalized = upper(token)
        if normalized ~= "OUTLINE" and normalized ~= "THICKOUTLINE" then
            values[#values + 1] = token
        end
    end
    return concat(values, ",")
end

local function ResolveFlags(original, outline)
    if outline == nil then return original end
    local base = StripOutlineFlags(original)
    local flag
    if outline == "outline" or outline == "outlineShadow" then
        flag = "OUTLINE"
    elseif outline == "thick" then
        flag = "THICKOUTLINE"
    end
    if not flag then return base end
    return base ~= "" and (base .. "," .. flag) or flag
end

local function ResolveShadow(state, outline)
    if outline == nil then
        return state.originalShadowR,
            state.originalShadowG,
            state.originalShadowB,
            state.originalShadowA,
            state.originalShadowX,
            state.originalShadowY
    end
    if outline == "shadow" or outline == "outlineShadow" then
        return 0, 0, 0, 1, 1, -1
    end
    return 0, 0, 0, 0, 0, 0
end

local function ResolveFont(mediaName)
    if mediaName == nil then return nil end
    if type(YChat.NormalizeFontMediaName) == "function" then
        mediaName = YChat:NormalizeFontMediaName(mediaName)
    end
    if mediaName == nil then return nil end
    if not LSM and type(LibStub) == "function" then
        local ok, media = pcall(LibStub, "LibSharedMedia-3.0", true)
        if ok then LSM = media end
    end
    if not LSM or type(LSM.Fetch) ~= "function" then return nil end
    local ok, fontFile = pcall(LSM.Fetch, LSM, "font", mediaName, true)
    if not ok or type(fontFile) ~= "string" or fontFile == "" then return nil end
    return fontFile
end

local ApplyFrame
local RefreshTimestampStyle
local RestoreState

local function IsTypographyFrame(frame)
    local classifier = Adapter.ClassifyTypographyFrame
    if type(classifier) == "function" then
        local supported, reason = classifier(Adapter, frame)
        return supported == true, reason
    end
    return Adapter:IsTrustedSupportedFrame(frame) == true,
        "ordinary-supported-chat-frame"
end

local function CaptureOriginalState(frame, state)
    local snapshot, reason = Adapter:CaptureChatTypographySnapshot(frame)
    if snapshot == nil then return false, reason end
    state.originalSnapshot = snapshot
    state.originalFont = snapshot.fontFile
    state.originalSize = snapshot.fontHeight
    state.originalFlags = snapshot.fontFlags
    state.originalSpacing = snapshot.spacing
    state.originalShadowR = snapshot.shadowR
    state.originalShadowG = snapshot.shadowG
    state.originalShadowB = snapshot.shadowB
    state.originalShadowA = snapshot.shadowA
    state.originalShadowX = snapshot.shadowX
    state.originalShadowY = snapshot.shadowY
    state.nativeFontSizeChanged = false
    state.eligible = true
    return true
end

local function FontChanged(frame)
    local state = states[frame]
    if not Typography.enabled or not state or state.writing
        or state.temporary == true
    then
        return
    end
    local supported = IsTypographyFrame(frame)
    if not supported then
        RestoreState(frame, state)
        return
    end
    local snapshot = Adapter:CaptureChatTypographySnapshot(frame)
    if snapshot == nil then
        Typography.lastFailure = "native-font-refresh-read-failed"
        StatIncrement("typographyDomainFailures")
        return
    end
    if snapshot.fontObject ~= state.appliedFontObject then
        state.originalSnapshot = snapshot
        state.originalFont = snapshot.fontFile
        state.originalSize = snapshot.fontHeight
        state.originalFlags = snapshot.fontFlags
        state.originalSpacing = snapshot.spacing
        state.originalShadowR = snapshot.shadowR
        state.originalShadowG = snapshot.shadowG
        state.originalShadowB = snapshot.shadowB
        state.originalShadowA = snapshot.shadowA
        state.originalShadowX = snapshot.shadowX
        state.originalShadowY = snapshot.shadowY
        state.nativeFontSizeChanged = false
    end
    local applied = ApplyFrame(frame, state, "native-font-refresh")
    if applied and RefreshTimestampStyle then
        RefreshTimestampStyle("native-font-refresh")
    end
end

local function SpacingChanged(frame)
    local state = states[frame]
    if not Typography.enabled or not state or state.writing
        or state.temporary == true
    then
        return
    end
    local supported = IsTypographyFrame(frame)
    if not supported then
        RestoreState(frame, state)
        return
    end
    local spacing = Adapter:ReadSpacing(frame)
    if spacing == nil then
        Typography.lastFailure = "native-spacing-refresh-read-failed"
        StatIncrement("typographyDomainFailures")
        return
    end
    state.originalSpacing = spacing
    if state.originalSnapshot then state.originalSnapshot.spacing = spacing end
    ApplyFrame(frame, state, "native-spacing-refresh")
end

local function EnsureState(frame)
    local supported, classification = IsTypographyFrame(frame)
    if not supported then return nil, classification end
    local temporary = classification == TEMPORARY_TYPOGRAPHY_CLASS
    local state = states[frame]
    if not state then
        state = {
            writing = false,
            managed = false,
            eligible = false,
        }
        states[frame] = state
    end
    state.temporary = temporary
    if state.eligible ~= true then
        local captured, captureReason = CaptureOriginalState(frame, state)
        if not captured then return nil, captureReason end
    end
    if not temporary and not state.hooked then
        local hooked = Adapter:InstallChatTypographyHooks(
            frame,
            FontChanged,
            SpacingChanged
        )
        if not hooked then
            state.eligible = false
            return nil, "chat-typography-hook-failed"
        end
        state.hooked = true
    end
    return state
end

RestoreState = function(frame, state)
    if not state or state.managed ~= true then
        if state then
            state.eligible = false
            state.temporary = false
        end
        return true
    end
    state.writing = true
    local restored, reason = Adapter:RestoreChatTypographySnapshot(
        frame,
        state.originalSnapshot,
        state.nativeFontSizeChanged and state.originalSize or nil
    )
    state.writing = false
    if not restored then return false, reason end
    state.managed = false
    state.eligible = false
    state.temporary = false
    state.appliedFont = nil
    state.appliedSize = nil
    state.appliedFlags = nil
    state.appliedFontObject = nil
    return true
end

RefreshTimestampStyle = function(reason)
    local shadow = YChat.Shadow
    if shadow
        and shadow.enabled == true
        and type(shadow.RefreshTimestampConfiguration) == "function"
    then
        shadow:RefreshTimestampConfiguration(reason or "typography-style-refresh")
    end
end

ApplyFrame = function(frame, state, reason)
    if not Typography.enabled then return true end
    local restriction = Adapter:GetRestrictionState()
    if restriction ~= "OPEN" and restriction ~= "PAUSED" then
        Typography.retryPending = true
        return true, "restriction-paused"
    end
    state = state or EnsureState(frame)
    if not state then return false, "chat-typography-state-unavailable" end
    local config = YChat:GetTypography()
    if not config then return false, "typography-db-unavailable" end
    local fontFile = ResolveFont(config.font)
    local fontSize = config.fontSize or state.originalSize
    local fontFlags = ResolveFlags(state.originalFlags, config.outline)
    local shadowR, shadowG, shadowB, shadowA, shadowX, shadowY =
        ResolveShadow(state, config.outline)
    local spacing = config.lineSpacing
    if spacing == nil then spacing = state.originalSpacing end
    state.writing = true
    local applied, applyResult = Adapter:ApplyChatTypographyFamily(
        frame,
        state.originalSnapshot,
        fontFile,
        fontSize,
        fontFlags,
        spacing,
        shadowR,
        shadowG,
        shadowB,
        shadowA,
        shadowX,
        shadowY
    )
    state.writing = false
    if not applied then
        Typography.lastFailure = applyResult or reason or "chat-typography-apply-failed"
        Typography.retryPending = true
        StatIncrement("typographyDomainFailures")
        state.writing = true
        local restored = Adapter:RestoreChatTypographySnapshot(
            frame,
            state.originalSnapshot,
            state.nativeFontSizeChanged and state.originalSize or nil
        )
        state.writing = false
        state.managed = restored ~= true
        if not restored then StatIncrement("typographyRestoreFailures") end
        return false, Typography.lastFailure
    end
    state.managed = true
    state.appliedFont = fontFile or state.originalFont
    state.appliedFontObject = applyResult
    state.appliedSize = fontSize
    state.appliedFlags = fontFlags
    state.appliedShadowR = shadowR
    state.appliedShadowG = shadowG
    state.appliedShadowB = shadowB
    state.appliedShadowA = shadowA
    state.appliedShadowX = shadowX
    state.appliedShadowY = shadowY
    StatIncrement("typographyWrites")
    return true
end

local function ApplySupportedFrame(frame)
    local state, reason = EnsureState(frame)
    if not state then
        Typography.lastFailure = reason or "chat-typography-capture-failed"
        Typography.retryPending = true
        StatIncrement("typographyDomainFailures")
        return
    end
    ApplyFrame(frame, state, "chat-typography-refresh")
end

local function RestoreUnsupportedFrames()
    for frame, state in pairs(states) do
        local supported = IsTypographyFrame(frame)
        if not supported and state.eligible == true then
            local restored, reason = RestoreState(frame, state)
            if not restored then
                Typography.lastFailure = reason or "chat-typography-restore-failed"
                StatIncrement("typographyRestoreFailures")
            end
        end
    end
end

local function RefreshGauge()
    local managed = 0
    for _, state in pairs(states) do
        if state.managed then managed = managed + 1 end
    end
    StatSet("typographyManagedFrames", managed)
    return managed
end

function Typography:RefreshAll(reason)
    if not self.enabled then return true end
    self.lastFailure = "none"
    self.retryPending = false
    RestoreUnsupportedFrames()
    local iterator = Adapter.ForEachTypographyFrame
        or Adapter.ForEachSupportedFrame
    iterator(Adapter, ApplySupportedFrame)
    RefreshGauge()
    RefreshTimestampStyle(reason or "typography-refresh")
    return self.lastFailure == "none", self.lastFailure
end

function Typography:ReadAppliedTextStyle(frame)
    local state = states[frame]
    if not self.enabled or not state or state.managed ~= true
        or state.appliedFont == nil or state.appliedSize == nil
        or state.appliedFlags == nil
    then
        return nil, nil, nil, nil, nil, nil, nil, nil, nil,
            "typography-applied-style-unavailable"
    end
    return state.appliedFont,
        state.appliedSize,
        state.appliedFlags,
        state.appliedShadowR,
        state.appliedShadowG,
        state.appliedShadowB,
        state.appliedShadowA,
        state.appliedShadowX,
        state.appliedShadowY
end

function Typography:OnFrameDiscovered(frame, valid)
    if not self.enabled then return true end
    local supported, classification = IsTypographyFrame(frame)
    if not supported then
        local state = states[frame]
        local restored, restoreReason = RestoreState(frame, state)
        RefreshGauge()
        return restored, restoreReason or classification
    end
    local state, reason = EnsureState(frame)
    local applied, applyReason
    if state then
        applied, applyReason = ApplyFrame(frame, state, "frame-discovered")
    end
    RefreshGauge()
    if applied then RefreshTimestampStyle(classification or "frame-discovered") end
    return applied == true, applyReason or reason
end

function Typography:OnWindowsChanged(reason)
    return self:RefreshAll(reason or "windows-changed")
end

function Typography:OnNativeFontSizeChanged(frame, fontSize)
    if not self.enabled then return true end
    if type(fontSize) ~= "number"
        or fontSize ~= fontSize
        or fontSize <= 0
        or fontSize >= math.huge
    then
        return false, "native-font-size-invalid"
    end
    local state = states[frame]
    if not state or state.writing or state.temporary == true then return true end
    local supported, classification = IsTypographyFrame(frame)
    if not supported or classification == TEMPORARY_TYPOGRAPHY_CLASS then
        return true, classification
    end
    state.originalSize = fontSize
    state.nativeFontSizeChanged = true
    local applied, applyReason = ApplyFrame(
        frame,
        state,
        "native-font-size-changed"
    )
    if applied then RefreshTimestampStyle("native-font-size-changed") end
    return applied == true, applyReason
end

function Typography:OnTemporaryFrameChanged(frame, active, reason)
    if active == true then
        if not self.enabled then return true end
        local supported, classification = IsTypographyFrame(frame)
        if not supported or classification ~= TEMPORARY_TYPOGRAPHY_CLASS then
            return true, classification or "temporary-typography-frame-unsupported"
        end
        local state, stateReason = EnsureState(frame)
        if not state then
            self.lastFailure = stateReason or "temporary-typography-capture-failed"
            StatIncrement("typographyDomainFailures")
            return false, self.lastFailure
        end
        local applied, applyReason = ApplyFrame(
            frame,
            state,
            reason or "temporary-typography-opened"
        )
        RefreshGauge()
        return applied == true, applyReason
    end

    local state = states[frame]
    if not state then return true end
    local restored, restoreReason = RestoreState(frame, state)
    RefreshGauge()
    if not restored then
        self.lastFailure = restoreReason or "temporary-typography-restore-failed"
        StatIncrement("typographyRestoreFailures")
        return false, self.lastFailure
    end
    return true
end

function Typography:SetEnabled(enabled, reason)
    enabled = enabled == true
    if self.enabled == enabled then
        return enabled and self:RefreshAll(reason) or true
    end
    if enabled then
        self.enabled = true
        return self:RefreshAll(reason or "typography-enabled")
    end

    local firstReason
    for frame, state in pairs(states) do
        if state.managed then
            local restored, restoreReason = RestoreState(frame, state)
            if not restored and not firstReason then
                firstReason = restoreReason or "chat-typography-restore-failed"
                StatIncrement("typographyRestoreFailures")
            end
        end
    end
    RefreshGauge()
    if firstReason then
        self.lastFailure = firstReason
        return false, firstReason
    end
    self.enabled = false
    self.retryPending = false
    self.lastFailure = reason or "typography-disabled"
    return true
end

function Typography:HasPendingVisualRetry()
    return self.enabled == true and self.retryPending == true
end

function Typography:GetRuntimeGauges(target)
    target = target or {}
    target.typographyManagedFrames = RefreshGauge()
    target.typographyEnabled = self.enabled == true
    target.typographyLastFailure = self.lastFailure or "none"
    return target
end

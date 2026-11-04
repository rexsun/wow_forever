local YUI = _G.YUI
local YChat = YUI and YUI.YChat
if not YChat or (YUI.IsForever or YUI.IsRetail) ~= true then return end

local Adapter = YChat.Adapter
if not Adapter then return end

local Typography = {}
YChat.Typography = Typography

local LSM
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

local function ResolveFlags(original, outline, monochrome)
    if outline == nil and monochrome == nil then return original end
    local base = outline == nil and (original or "") or StripOutlineFlags(original)
    if monochrome ~= nil then
        local values = {}
        for token in gmatch(base, "[^,%s]+") do
            if upper(token) ~= "MONOCHROME" then values[#values + 1] = token end
        end
        if monochrome then values[#values + 1] = "MONOCHROME" end
        base = concat(values, ",")
    end
    local flag
    if outline == "outline" or outline == "outlineShadow" then
        flag = "OUTLINE"
    elseif outline == "thick" then
        flag = "THICKOUTLINE"
    end
    if not flag then return base end
    return base ~= "" and (base .. "," .. flag) or flag
end

local function ResolveShadow(state, outline, shadow)
    if shadow == "inherit" or (shadow == nil and outline == nil) then
        return state.originalShadowR,
            state.originalShadowG,
            state.originalShadowB,
            state.originalShadowA,
            state.originalShadowX,
            state.originalShadowY
    end
    if shadow == true or (shadow == nil and (outline == "shadow" or outline == "outlineShadow")) then
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
    if mediaName:find("\\", 1, true) or mediaName:find("/", 1, true) then return mediaName end
    if not LSM then
        local LibStub = _G.LibStub
        if type(LibStub) == "table" and type(LibStub.GetLibrary) == "function" then
            local ok, media = pcall(LibStub.GetLibrary, LibStub, "LibSharedMedia-3.0", true)
            if ok and type(media) == "table" then LSM = media end
        end
    end
    if not LSM or type(LSM.Fetch) ~= "function" then return nil end
    local ok, fontFile = pcall(LSM.Fetch, LSM, "font", mediaName, true)
    if not ok or type(fontFile) ~= "string" or fontFile == "" then return nil end
    return fontFile
end

function Typography:ResolveFont(mediaName)
    return ResolveFont(mediaName)
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
    local fontSize = not state.temporary and Adapter:ReadStoredChatWindowFontSize(frame) or state.originalSize
    fontSize = fontSize or state.originalSize
    if fontSize ~= state.originalSize then
        state.originalSize, state.nativeFontSizeChanged = fontSize, true
    end
    local fontFlags = ResolveFlags(state.originalFlags, config.outline, config.monochrome)
    local shadowR, shadowG, shadowB, shadowA, shadowX, shadowY =
        ResolveShadow(state, config.outline, config.shadow)
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

-- Only settings, copy transactions and legacy handoff enumerate native sizes.
-- Snapshots contain stable window IDs and numbers, never frame references.
function Typography:CaptureNativeSizes()
    return Adapter:CaptureChatWindowFontSizes()
end

function Typography:WriteNativeSizes(values)
    local before, reason, frames = self:CaptureNativeSizes()
    if not before then return false, reason end
    for id in pairs(before) do if values[id] == nil then return false, "stale" end end
    for id, size in pairs(values) do
        if not frames[id] then return false, "stale" end
        if type(size) ~= "number" or size ~= size or size <= 0 or size >= math.huge then return false, "invalid" end
    end
    local changed, order = {}, {}
    for id in pairs(values) do order[#order+1] = id end
    table.sort(order)
    local function Write(id, size)
        local frame, state = frames[id], states[frames[id]]
        if state then state.writing = true end
        local ok, applied, code = pcall(Adapter.WriteStoredChatWindowFontSize, Adapter, frame, size)
        if state then
            state.writing = false
            if ok and applied then state.originalSize, state.nativeFontSizeChanged = size, true end
        end
        return ok and applied == true, code
    end
    self.writingSizes = true
    for _, id in ipairs(order) do
        local size = values[id]
        if size ~= before[id] then
            changed[#changed+1] = id
            local ok, code = Write(id, size)
            if not ok then
                local restored = true
                for index = #changed, 1, -1 do
                    local rollbackID = changed[index]
                    if not Write(rollbackID, before[rollbackID]) then restored = false end
                end
                self.writingSizes = nil
                return false, restored and (code or "failed") or "rollback_failed"
            end
        end
    end
    self.writingSizes = nil
    return true
end

function Typography:SetNativeSize(size)
    local sizes, reason = self:CaptureNativeSizes()
    if not sizes then return false, reason end
    for id in pairs(sizes) do sizes[id] = size end
    return self:WriteNativeSizes(sizes)
end

function Typography:RefreshAll(reason)
    if not self.enabled then return true end
    self.lastFailure = "none"
    self.retryPending = false
    local config = YChat:GetTypography()
    if config and config.fontSize ~= nil then
        -- Preserve legacy appearance once, then yield permanently to native windows.
        local applied, code = self:SetNativeSize(config.fontSize)
        if not applied then
            self.lastFailure, self.retryPending = code or "failed", true
            return false, self.lastFailure
        end
        config.fontSize = nil
    end
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
    local style = YUI.GUI2 and YUI.GUI2.FontStyle
    if style and style.RefreshExternal and not self.writingSizes then style:RefreshExternal("ychat:body") end
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

local Style = YUI.GUI2 and YUI.GUI2.FontStyle
if Style then
    local fields = {font="font",size="fontSize",outline="outline",shadow="shadow",monochrome="monochrome"}
    local tabFields = {font="tabFont",size="tabFontSize",outline="tabTextEffect",shadow="tabShadow",monochrome="tabMonochrome"}
    local L = YUI.Locale and YUI.Locale:Get("YChat") or {}
    local function ReadStyle(config)
        -- A sample for the editor only. Runtime still resolves native values per window.
        local state = _G.ChatFrame1 and states[_G.ChatFrame1]
        if not state then
            local snapshot = _G.ChatFrame1 and Adapter:CaptureChatTypographySnapshot(_G.ChatFrame1) or {}
            snapshot = snapshot or {}
            state = {originalFont=snapshot.fontFile, originalSize=snapshot.fontHeight, originalFlags=snapshot.fontFlags,
                originalShadowR=snapshot.shadowR,originalShadowG=snapshot.shadowG,originalShadowB=snapshot.shadowB,
                originalShadowA=snapshot.shadowA,originalShadowX=snapshot.shadowX,originalShadowY=snapshot.shadowY}
        end
        local _,_,_,alpha,x,y = ResolveShadow(state, config.outline, config.shadow)
        local result = Style.Decode(ResolveFlags(state.originalFlags, config.outline, config.monochrome),
            (alpha or 0)>0 and ((x or 0)~=0 or (y or 0)~=0))
        result.font = ResolveFont(config.font) or state.originalFont or STANDARD_TEXT_FONT
        result.size = config.fontSize
        if result.size == nil then
            local sizes = Typography:CaptureNativeSizes()
            for _, size in pairs(sizes or {}) do
                if result.size and result.size ~= size then result.size = nil; break end
                result.size = size
            end
        end
        return result
    end
    Style:Register("ychat", function()
        local profile = YChat:GetProfile()
        local db = profile and profile[YChat.STORAGE_KEY] or not profile and YChat.db
        local config = db and db.typography
        if type(config) ~= "table" then return end
        local appearance = db.appearance
        local group = {label=L["settings.title"] or "Chat"}
        group.current = function()
            local current = YChat:GetProfile()
            local root = current and current[YChat.STORAGE_KEY] or not current and YChat.db
            return current==profile and root==db and root.typography==config and root.appearance==appearance
        end
        local target = {id="body",label=L["settings.section.message_text"] or "Message text",
            capabilities={font=true,size=true,outline=true,shadow=true,monochrome=true},
            minSize=YChat.BODY_FONT_MIN_SIZE,maxSize=YChat.BODY_FONT_MAX_SIZE,
            sizePlaceholder=L["settings.typography.per_window"],
            fontOptions={{text=L["settings.native"] or "Follow native",value="__native"}},
            read=function() return ReadStyle(config) end,
            parent=function(attribute) return ReadStyle({})[attribute] end}
        local tabs = {id="tabs",label=L["settings.appearance.tab_text"] or "Tab text",
            capabilities={font=true,size=true,outline=true,shadow=true,monochrome=true},
            minSize=YChat.TAB_FONT_MIN_SIZE,maxSize=YChat.TAB_FONT_MAX_SIZE,
            fontOptionsPosition="last",
            fontOptions=function()
                return {{text=L["settings.native"] or "Follow native",value="__native",
                    fontPath=YChat.Appearance:ReadTabFontStyle(YChat.Defaults.appearance).font}}
            end,
            read=function() return YChat.Appearance:ReadTabFontStyle(appearance) end,
            parent=function(attribute) return YChat.Appearance:ReadTabFontStyle(YChat.Defaults.appearance)[attribute] end}
        group.targets={target}
        if appearance and YChat.Appearance and YChat.Appearance.ReadTabFontStyle then group.targets[2]=tabs end
        group.snapshot=function(id)
            local snapshot={}
            if id=="tabs" then
                for _,field in pairs(tabFields) do snapshot[field]=appearance[field] end
                snapshot.preset=appearance.preset
                return snapshot
            end
            for _, field in pairs(fields) do snapshot[field]=config[field] end
            snapshot.nativeSizes=Typography:CaptureNativeSizes()
            return snapshot
        end
        local function Refresh()
            if YUI.Module and YUI.Module.Refresh then return YUI.Module:Refresh(YChat.PRODUCT_ID,"font-style") end
            return Typography:RefreshAll("font-style")
        end
        group.restore=function(snapshots, attributes)
            if not group.current() then return false,"stale" end
            for id in pairs(snapshots) do if id~="body" and id~="tabs" then return false,"stale" end end
            if snapshots.body then
                if (not attributes or attributes.size) and snapshots.body.nativeSizes then
                    local ok, code=Typography:WriteNativeSizes(snapshots.body.nativeSizes)
                    if not ok then return false,code end
                end
                for attribute, field in pairs(fields) do
                    if not attributes or attributes[attribute] then config[field]=snapshots.body[field] end
                end
            end
            if snapshots.tabs then
                for attribute,field in pairs(tabFields) do
                    if not attributes or attributes[attribute] then appearance[field]=snapshots.tabs[field] end
                end
                -- Outline edits may separate the legacy combined shadow setting.
                if not attributes or attributes.outline then appearance.tabShadow=snapshots.tabs.tabShadow end
                appearance.preset=snapshots.tabs.preset
            end
            return Refresh()
        end
        group.apply=function(changes)
            if not group.current() then return false,"stale" end
            for id, patch in pairs(changes) do
                if id~="body" and id~="tabs" then return false,"stale" end
                if next(patch.values or {}) then
                    local attributes={}
                    for attribute in pairs(patch.values) do attributes[attribute]=true end
                    local ok,code=Style.Validate(id=="tabs" and tabs or target,patch.values,attributes)
                    if not ok then return false,code end
                    local font=patch.values.font
                    if font and font~="__native" and not YChat:NormalizeFontMediaName(font) then return false,"invalid" end
                end
            end
            local patch=changes.body
            local values,reset=patch and patch.values or {},patch and patch.reset or {}
            if values.size then
                local ok,code=Typography:SetNativeSize(values.size)
                if not ok then return false,code end
                config.fontSize=nil
            end
            -- Legacy outline also controlled shadow. Separate it only on an explicit edit.
            if (values.outline or reset.outline) and config.shadow==nil then
                config.shadow=config.outline==nil and "inherit" or config.outline=="shadow" or config.outline=="outlineShadow"
            end
            for attribute,value in pairs(values) do
                if attribute=="font" then config.font=value~="__native" and YChat:NormalizeFontMediaName(value) or nil
                elseif attribute=="outline" then config.outline=value=="NONE" and "none" or value=="OUTLINE" and "outline" or "thick"
                elseif attribute~="size" and fields[attribute] then config[fields[attribute]]=value end
            end
            for attribute in pairs(reset) do if fields[attribute] then config[fields[attribute]]=nil end end
            if reset.shadow and config.outline~=nil then config.shadow="inherit" end
            patch=changes.tabs
            if patch then
                values,reset=patch.values or {},patch.reset or {}
                if (values.outline or reset.outline) and appearance.tabShadow==nil then
                    appearance.tabShadow=appearance.tabTextEffect=="shadow" or appearance.tabTextEffect=="outlineShadow"
                end
                for attribute,value in pairs(values) do
                    if attribute=="font" then appearance.tabFont=value~="__native" and YChat:NormalizeFontMediaName(value) or nil
                    elseif attribute=="outline" then appearance.tabTextEffect=value=="NONE" and "none" or value=="OUTLINE" and "outline" or "thick"
                    elseif tabFields[attribute] then appearance[tabFields[attribute]]=value end
                end
                for attribute in pairs(reset) do
                    if tabFields[attribute] then appearance[tabFields[attribute]]=YChat.Defaults.appearance[tabFields[attribute]] end
                end
                if reset.shadow and not reset.outline then
                    local effect=YChat.Defaults.appearance.tabTextEffect
                    appearance.tabShadow=effect=="shadow" or effect=="outlineShadow"
                end
                appearance.preset="custom"
            end
            return Refresh()
        end
        return group
    end)
end

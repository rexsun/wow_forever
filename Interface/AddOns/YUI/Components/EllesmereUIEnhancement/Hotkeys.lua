local _, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and YUI.IsRetail == true and YUI.Components) then return end
if YUI._EllesmereUIHotkeys then return end

local Security = YUI.API and YUI.API.Security
local System = YUI.API and YUI.API.System
local Event = YUI.Event
local Hotkeys = { enabled = false, status = "disabled", writes = 0, restores = 0, failures = 0 }
YUI._EllesmereUIHotkeys = Hotkeys

local DEFAULT_ALIASES = { HOME = "HO", END = "EN", INSERT = "IN", DELETE = "DE", PAGEUP = "PU", PAGEDOWN = "PD", MWU = "MU", MWD = "MD" }
local MAX_BARS, MAX_BUTTONS_PER_BAR = 16, 24
local fontStates = setmetatable({}, { __mode = "k" })
local fontOwners = setmetatable({}, { __mode = "kv" })
local providerHooks = setmetatable({}, { __mode = "k" })
local aliases = DEFAULT_ALIASES
local currentProvider, currentBars
local pendingTimer
local scanSequence = 0
local Discover

local function IsSecret(value)
    return Security and Security.IsSecretValue and Security.IsSecretValue(value) == true
end

local function CanRead(object)
    if IsSecret(object) or type(object) ~= "table" then return false end
    return not (Security and Security.CanAccessTable and Security.CanAccessTable(object) == false)
end

local function ReadField(object, key)
    return object[key]
end

local function Field(object, key)
    if not CanRead(object) then return nil, false end
    local ok, value = pcall(ReadField, object, key)
    if ok and not IsSecret(value) then return value, true end
    return nil, false
end

local function ReadText(font)
    local method = Field(font, "GetText")
    if type(method) ~= "function" then return nil end
    local ok, text = pcall(method, font)
    if ok and not IsSecret(text) and type(text) == "string" then return text end
end

local function IsFont(font)
    if not CanRead(font) then return false end
    local forbidden = Field(font, "IsForbidden")
    if type(forbidden) == "function" then
        local ok, value = pcall(forbidden, font)
        if not ok or IsSecret(value) or value then return false end
    end
    local method = Field(font, "IsObjectType")
    if type(method) ~= "function" then return false end
    local ok, value = pcall(method, font, "FontString")
    return ok and not IsSecret(value) and value == true and type(Field(font, "SetText")) == "function"
end

local function Ownership(font)
    local button = fontOwners[font]
    if button == nil then return false, true end
    if not CanRead(button) then return false, false end
    local current, readable = Field(button, "HotKey")
    if not readable then return false, false end
    if current ~= font then return false, true end
    if not IsFont(font) then return false, false end
    return true, true
end

local function IsOwned(font)
    local state = fontStates[font]
    return state ~= nil and state.active == true and Ownership(font) == true
end

local function ReadBinding(font)
    local command = Field(fontOwners[font], "commandName")
    if type(command) ~= "string" or type(GetBindingKey) ~= "function" then return nil, false end
    local ok, key = pcall(GetBindingKey, command)
    if ok and not IsSecret(key) and (key == nil or type(key) == "string") then return key, true end
    return nil, false
end

-- 规则只在配置变化时解析；热路径使用编译后的表，不执行用户输入。
function Hotkeys:ParseAliases(text)
    if IsSecret(text) or type(text) ~= "string" or #text > 2048 then return nil, 0 end
    local result = {}
    for key, value in pairs(DEFAULT_ALIASES) do result[key] = value end
    local index = 0
    for entry in text:gmatch("[^;\r\n]+") do
        if entry:find("%S") then
            index = index + 1
            if index > 64 then return nil, index end
            local key, value = entry:match("^%s*([^=]+)%s*=%s*([^=]+)%s*$")
            if not key then return nil, index end
            key = key:gsub("%s+", ""):upper()
            value = value:match("^%s*(.-)%s*$")
            if #key > 32 or not key:match("^[A-Z0-9%+%-%./%*]+$")
                or #value < 1 or #value > 2 or not value:match("^[A-Za-z0-9]+$") then
                return nil, index
            end
            result[key] = value
        end
    end
    return result
end

local function FormatText(text)
    if text == "" or text:find("|", 1, true) then return text end
    local upper = text:upper()
    local replacement = aliases[upper:gsub("%s+", "")]
    if replacement then return replacement end
    -- 修饰键保留 EUI 当前写入的顺序与大小写，只缩写完整主键。
    for index = 1, math.min(4, #text - 1) do
        local modifier = upper:sub(index, index)
        if modifier ~= "C" and modifier ~= "A" and modifier ~= "S" and modifier ~= "M" then break end
        replacement = aliases[(upper:sub(index + 1):gsub("%s+", ""))]
        if replacement then return text:sub(1, index) .. replacement end
    end
    return text
end

local function ClearSource(state)
    state.source, state.output, state.binding, state.bindingKnown = nil, nil, nil, nil
end

local function WriteText(font, state, text)
    state.writing = true
    local ok = Security.SafeMethod("EllesmereUIEnhancement:hotkey-text", font, "SetText", text)
    state.writing = false
    if ok then Hotkeys.writes = Hotkeys.writes + 1 else Hotkeys.failures = Hotkeys.failures + 1 end
    return ok
end

local function OnTextWritten(font, text, reapply)
    if not Hotkeys.enabled or not currentProvider then return end
    local state = fontStates[font]
    if not state or state.writing or not IsOwned(font) then return end
    if IsSecret(text) or type(text) ~= "string" or #text > 256 then
        ClearSource(state)
        return
    end
    local source = text
    -- 布局可能重新写入 GetText() 的结果；保留缩写前的源文本，避免二次映射。
    -- 实际改绑到上次输出时，通过 commandName 的绑定变化辨别新源文本。
    if state.output ~= nil and text == state.output and ReadBinding(font) == state.binding then
        source = state.source
    end
    local output = FormatText(source)
    if output == source then
        ClearSource(state)
    else
        state.source, state.output = source, output
        state.binding, state.bindingKnown = ReadBinding(font)
    end
    if (output ~= text or reapply) and ReadText(font) ~= output then
        if not WriteText(font, state, output) then ClearSource(state) end
    end
end

local function RestoreFont(font, state)
    if state.source == nil then return true end
    local owned, readable = Ownership(font)
    if not readable then return false end
    if owned then
        if state.bindingKnown then
            local binding, bindingKnown = ReadBinding(font)
            if not bindingKnown then return false end
            if binding ~= state.binding then
                ClearSource(state)
                return true
            end
        end
        local text = ReadText(font)
        if text == nil then return false end
        if text == state.output then
            if not WriteText(font, state, state.source) then return false end
            Hotkeys.restores = Hotkeys.restores + 1
        end
    end
    ClearSource(state)
    return true
end

local function RestoreAll()
    local pending = false
    for font, state in pairs(fontStates) do
        if not RestoreFont(font, state) then pending = true end
    end
    return pending
end

local function ReconcileFonts(barKey)
    for font, state in pairs(fontStates) do
        if (barKey == nil or state.barKey == barKey) and state.seen ~= scanSequence then
            state.active = false
            local _, readable = Ownership(font)
            if readable and RestoreFont(font, state) then
                fontOwners[font] = nil
            end
        end
    end
end

-- 只有此适配边界读取第三方内部注册表；无法识别时停止接入，不猜测全局按钮。
local function ResolveProvider()
    if not (System and System.IsAddOnLoadedSafe and System.IsAddOnLoadedSafe("EllesmereUIActionBars")) then
        return nil, nil, "missing"
    end
    local registry = Field(_G.EllesmereUI, "_ModuleNS")
    local namespace = Field(registry, "EllesmereUIActionBars")
    local provider, bars = Field(namespace, "EAB"), Field(namespace, "barButtons")
    if not CanRead(provider) or not CanRead(bars) or type(Field(provider, "ApplyFontsForBar")) ~= "function" then
        return nil, nil, "unsupported"
    end
    local count = 0
    for key, buttons in pairs(bars) do
        count = count + 1
        if count > MAX_BARS or IsSecret(key) or type(key) ~= "string" or not CanRead(buttons) then
            return nil, nil, "unsupported"
        end
        local buttonCount = 0
        for index in pairs(buttons) do
            buttonCount = buttonCount + 1
            if buttonCount > MAX_BUTTONS_PER_BAR or IsSecret(index) or type(index) ~= "number"
                or index < 1 or index > MAX_BUTTONS_PER_BAR or index % 1 ~= 0 then
                return nil, nil, "unsupported"
            end
        end
    end
    return provider, bars
end

local function AttachBar(buttons, barKey)
    local attached = 0
    for index = 1, MAX_BUTTONS_PER_BAR do
        local button = Field(buttons, index)
        local font = Field(button, "HotKey")
        if IsFont(font) then
            local state = fontStates[font]
            if not state then
                state = {}
                fontStates[font] = state
            end
            fontOwners[font] = button
            state.active = true
            state.seen, state.barKey = scanSequence, barKey
            local method = Field(font, "SetText")
            if state.method ~= method then
                if Security.SafeHook("EllesmereUIEnhancement:hotkey-write", font, "SetText", OnTextWritten) then
                    state.method = Field(font, "SetText")
                else
                    Hotkeys.failures = Hotkeys.failures + 1
                    state.method = nil
                    return nil
                end
            end
            if state.method then
                attached = attached + 1
                local text = ReadText(font)
                if text then OnTextWritten(font, text) end
            end
        end
    end
    return attached
end

local function OnBarApplied(provider, barKey)
    if not Hotkeys.enabled then return end
    if currentProvider and provider ~= currentProvider then return end
    if Security.InCombatLockdown() then Hotkeys.deferred = true; return end
    local resolved, bars, reason = ResolveProvider()
    if resolved ~= provider or not bars then
        currentProvider, currentBars = nil, nil
        Hotkeys.status = reason or "unsupported"
        RestoreAll()
        return
    end
    currentProvider, currentBars = resolved, bars
    scanSequence = scanSequence + 1
    local attached = AttachBar(Field(bars, barKey), barKey)
    if attached == nil then
        currentProvider, currentBars = nil, nil
        Hotkeys.status = "unsupported"
        RestoreAll()
    else
        ReconcileFonts(barKey)
        if attached > 0 then Hotkeys.status = "ready" end
    end
end

Discover = function()
    if not Hotkeys.enabled then return end
    if Security.InCombatLockdown() then
        Hotkeys.deferred, Hotkeys.status = true, "combat"
        return
    end
    Hotkeys.deferred = false
    local provider, bars, reason = ResolveProvider()
    if not provider then
        currentProvider, currentBars = nil, nil
        Hotkeys.status = reason
        RestoreAll()
        return
    end
    if currentProvider ~= provider or currentBars ~= bars then RestoreAll() end
    currentProvider, currentBars = provider, bars
    local method = Field(provider, "ApplyFontsForBar")
    if providerHooks[provider] ~= method then
        if not Security.SafeHook("EllesmereUIEnhancement:hotkey-bar", provider, "ApplyFontsForBar", OnBarApplied) then
            currentProvider, currentBars = nil, nil
            Hotkeys.status, Hotkeys.failures = "unsupported", Hotkeys.failures + 1
            RestoreAll()
            return
        end
        providerHooks[provider] = Field(provider, "ApplyFontsForBar")
    end
    local attached, hasButtons = 0, false
    scanSequence = scanSequence + 1
    for barKey, buttons in pairs(bars) do
        if next(buttons) ~= nil then hasButtons = true end
        local count = AttachBar(buttons, barKey)
        if count == nil then
            currentProvider, currentBars = nil, nil
            Hotkeys.status = "unsupported"
            RestoreAll()
            return
        end
        attached = attached + count
    end
    ReconcileFonts()
    Hotkeys.status = attached > 0 and "ready" or (hasButtons and "unsupported" or "waiting")
    if Hotkeys.status == "unsupported" then currentProvider, currentBars = nil, nil end
end

local function CancelPending()
    if pendingTimer then pendingTimer:Cancel(); pendingTimer = nil end
end

local function RunPending()
    pendingTimer = nil
    Discover()
end

local function QueueDiscovery()
    if not Hotkeys.enabled or pendingTimer then return end
    if C_Timer and type(C_Timer.NewTimer) == "function" then
        pendingTimer = C_Timer.NewTimer(0, RunPending)
    else
        Discover()
    end
end

function Hotkeys:OnAddonLoaded(_, addonName)
    if addonName == "EllesmereUI" or addonName == "EllesmereUIActionBars" then QueueDiscovery() end
end

function Hotkeys:OnRegenEnabled()
    if self.enabled then
        if self.deferred then Discover() end
    elseif self.restorePending then
        self.restorePending = RestoreAll()
        if not self.restorePending then
            Event:OffOwner(self)
            self.listeners = 0
        end
    end
end

function Hotkeys:SetEnabled(enabled, config)
    enabled = enabled == true and type(config) == "table" and config.abbreviateHotkeys == true
    if not enabled then
        if not self.enabled and self.status == "disabled" and not self.restorePending then return end
        self.enabled, self.deferred, self.status = false, false, "disabled"
        CancelPending()
        if self.listeners and self.listeners > 0 and Event and Event.OffOwner then Event:OffOwner(self) end
        self.listeners = 0
        self.restorePending = RestoreAll()
        currentProvider, currentBars = nil, nil
        if self.restorePending and Event and Event.On then
            Event:On("PLAYER_REGEN_ENABLED", "OnRegenEnabled", self, { moduleId = "component:EllesmereUIEnhancement" })
            self.listeners = 1
        end
        return
    end
    if not (Security and Security.SafeHook and Security.SafeMethod and Security.InCombatLockdown
        and Event and Event.On and Event.OffOwner) then
        self.status = "unsupported"
        return
    end
    local parsed, errorIndex = self:ParseAliases(config.hotkeyAliases or "")
    if not parsed then
        self:SetEnabled(false, config)
        self.status, self.errorIndex = "invalid", errorIndex
        return
    end
    aliases = parsed
    self.errorIndex = nil
    if not self.enabled then
        if self.listeners and self.listeners > 0 then Event:OffOwner(self) end
        self.restorePending = false
        self.enabled = true
        Event:On("ADDON_LOADED", "OnAddonLoaded", self, { moduleId = "component:EllesmereUIEnhancement" })
        Event:On("YUI_LOGIN_READY", QueueDiscovery, self, { moduleId = "component:EllesmereUIEnhancement" })
        Event:On("PLAYER_REGEN_ENABLED", "OnRegenEnabled", self, { moduleId = "component:EllesmereUIEnhancement" })
        self.listeners = 3
    end
    -- 更新规则必须从源文本重新计算，不能对当前缩写再次截断。
    for font, state in pairs(fontStates) do
        if state.source ~= nil and IsOwned(font) and ReadText(font) == state.output then
            OnTextWritten(font, state.source, true)
        end
    end
    Discover()
    QueueDiscovery()
end

function Hotkeys:GetStats()
    local physicalHooks, activeHooks, ownedFonts = 0, 0, 0
    for font, state in pairs(fontStates) do
        if state.method then physicalHooks = physicalHooks + 1 end
        if IsOwned(font) then
            if state.source ~= nil then ownedFonts = ownedFonts + 1 end
            if state.method and self.enabled and currentProvider then activeHooks = activeHooks + 1 end
        end
    end
    return {
        enabled = self.enabled, status = self.status, errorIndex = self.errorIndex,
        restorePending = self.restorePending == true,
        pendingTimers = pendingTimer and 1 or 0, deferred = self.deferred == true,
        listeners = self.listeners or 0, physicalHooks = physicalHooks,
        activeHooks = activeHooks,
        ownedFonts = ownedFonts, writes = self.writes, restores = self.restores, failures = self.failures,
    }
end

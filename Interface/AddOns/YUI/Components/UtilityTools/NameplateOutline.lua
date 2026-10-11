local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and YUI.Components and (YUI.IsRetail or YUI.IsForever)) then return end

local Security = YUI.API and YUI.API.Security or {}
local Event = YUI.Event
local Feature = { enabled = false, pending = false, writes = 0, restores = 0, failures = 0 }
YUI.UtilityToolsNameplateOutline = Feature

local fontNames = { "SystemFont_NamePlate", "SystemFont_NamePlate_Outlined" }
local fontStates = setmetatable({}, { __mode = "k" })

local function InCombat()
    return Security.InCombatLockdown and Security.InCombatLockdown() == true
end

local function HasOutline(flags)
    for flag in flags:gmatch("[^,%s]+") do
        if flag == "OUTLINE" or flag == "THICKOUTLINE" then return true end
    end
    return false
end

local function ReadFont(font)
    if not Security.SafeMethod then return end
    local ok, file, size, flags = Security.SafeMethod("UtilityTools:ReadNameplateFont", font, "GetFont")
    if not ok then
        Feature.failures = Feature.failures + 1
        return
    end
    if type(file) ~= "string" or file == "" or type(size) ~= "number" or size <= 0 then return end
    if flags == nil then flags = "" end
    if type(flags) ~= "string" then return end
    return file, size, flags
end

local function ClearOwnership(state)
    state.restoreFlags = nil
    state.appliedFile = nil
    state.appliedSize = nil
    state.appliedFlags = nil
end

local function OwnsCurrentFont(state, file, size, flags)
    return state.restoreFlags ~= nil and file == state.appliedFile
        and size == state.appliedSize and flags == state.appliedFlags
end

local function WriteFont(font, state, file, size, flags)
    state.writeFile, state.writeSize, state.outlineWritesDuringCall = file, size, 0
    state.writing = true
    local ok, result = Security.SafeMethod("UtilityTools:WriteNameplateFont", font, "SetFont", file, size, flags)
    local externallyOutlined = state.outlineWritesDuringCall > 1
    state.writing = false
    state.writeFile, state.writeSize, state.outlineWritesDuringCall = nil, nil, nil
    if not ok or result == false then
        Feature.failures = Feature.failures + 1
        return false
    end
    return true, externallyOutlined
end

local function ApplyOutline(font, state, file, size, flags)
    if HasOutline(flags) then return end
    if InCombat() then
        Feature.pending = true
        return
    end
    local desired = flags == "" and "OUTLINE" or flags .. ", OUTLINE"
    local written, externallyOutlined = WriteFont(font, state, file, size, desired)
    if not written then return end
    local appliedFile, appliedSize, appliedFlags = ReadFont(font)
    if appliedFile ~= file or appliedSize ~= size or not appliedFlags or not HasOutline(appliedFlags) then
        Feature.failures = Feature.failures + 1
        return
    end
    Feature.writes = Feature.writes + 1
    if externallyOutlined then
        ClearOwnership(state)
        return
    end
    state.restoreFlags = flags
    state.appliedFile = appliedFile
    state.appliedSize = appliedSize
    state.appliedFlags = appliedFlags
end

local function OnFontSet(font, requestedFile, requestedSize, requestedFlags)
    local state = fontStates[font]
    if not Feature.enabled or not state then return end
    if state.writing then
        -- 自身写入产生一次通知；同一字体的额外描边写入交由外部拥有。
        if requestedFile == state.writeFile and requestedSize == state.writeSize
            and type(requestedFlags) == "string" and HasOutline(requestedFlags) then
            state.outlineWritesDuringCall = state.outlineWritesDuringCall + 1
        end
        return
    end
    local file, size, flags = ReadFont(font)
    if not file then return end
    -- 外部成功设置了自己的描边后，YUI 不再拥有这次字体样式。
    local acceptedOutline = file == requestedFile and size == requestedSize
        and type(requestedFlags) == "string" and HasOutline(requestedFlags) and HasOutline(flags)
    if acceptedOutline or not OwnsCurrentFont(state, file, size, flags) then
        ClearOwnership(state)
    end
    ApplyOutline(font, state, file, size, flags)
end

function Feature:Refresh()
    if not self.enabled then return end
    self.pending = false
    self.awaitingFonts = false
    for _, name in ipairs(fontNames) do
        local font = _G[name]
        if not font then
            self.awaitingFonts = true
        elseif type(font.GetFont) == "function" and type(font.SetFont) == "function" then
            local state = fontStates[font]
            if not state then
                state = {}
                fontStates[font] = state
                if Security.SafeHook then
                    state.hooked = Security.SafeHook("UtilityTools:NameplateFontUpdated", font, "SetFont", OnFontSet) == true
                end
                if not state.hooked then self.failures = self.failures + 1 end
            end
            if state.hooked then
                local file, size, flags = ReadFont(font)
                if file then
                    if not OwnsCurrentFont(state, file, size, flags) then ClearOwnership(state) end
                    ApplyOutline(font, state, file, size, flags)
                else
                    self.awaitingFonts = true
                end
            end
        end
    end
end

local function RestoreFonts()
    Feature.pending = false
    for font, state in pairs(fontStates) do
        if state.restoreFlags ~= nil then
            local file, size, flags = ReadFont(font)
            if not OwnsCurrentFont(state, file, size, flags) then
                ClearOwnership(state)
            elseif InCombat() then
                Feature.pending = true
            else
                local restored = WriteFont(font, state, file, size, state.restoreFlags)
                if restored then
                    local restoredFile, restoredSize, restoredFlags = ReadFont(font)
                    if restoredFile == file and restoredSize == size and restoredFlags == state.restoreFlags then
                        Feature.restores = Feature.restores + 1
                    else
                        Feature.failures = Feature.failures + 1
                    end
                end
                ClearOwnership(state)
            end
        end
    end
end

function Feature:OnPlayerRegenEnabled()
    if not self.pending or InCombat() then return end
    if self.enabled then
        self:Refresh()
    else
        RestoreFonts()
        if not self.pending then
            Event:OffOwner(self)
            self.listeners = 0
        end
    end
end

function Feature:OnAddonLoaded()
    if self.awaitingFonts then self:Refresh() end
end

function Feature:Enable()
    if self.enabled then return end
    if not (Event and Event.On and Event.OffOwner and Security.SafeMethod
        and Security.SafeHook and Security.InCombatLockdown) then return end
    Event:OffOwner(self)
    self.enabled = true
    Event:On("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled", self)
    Event:On("YUI_LOGIN_READY", "Refresh", self)
    Event:On("ADDON_LOADED", "OnAddonLoaded", self)
    self.listeners = 3
    self:Refresh()
end

function Feature:Disable()
    if not self.enabled then return end
    self.enabled = false
    self.awaitingFonts = false
    Event:OffOwner(self)
    self.listeners = 0
    RestoreFonts()
    -- 安全后置 hook 留在本次会话；禁用后回调立即返回。
    if self.pending then
        Event:On("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled", self)
        self.listeners = 1
    end
end

function Feature:GetStats()
    local hooks, ownedFonts = 0, 0
    for _, state in pairs(fontStates) do
        if state.hooked then hooks = hooks + 1 end
        if state.restoreFlags ~= nil then ownedFonts = ownedFonts + 1 end
    end
    return {
        enabled = self.enabled,
        pending = self.pending,
        listeners = self.listeners or 0,
        physicalHooks = hooks,
        activeHooks = self.enabled and hooks or 0,
        ownedFonts = ownedFonts,
        writes = self.writes,
        restores = self.restores,
        failures = self.failures,
    }
end

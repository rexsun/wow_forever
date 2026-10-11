local YUI = _G.YUI
local function GetYBarDB()
    if YUI.YBar and YUI.YBar.GetModuleRoot then return YUI.YBar:GetModuleRoot("MicroMenu") end
    if YUI.YBar and YUI.YBar.EnsureDB then
        return YUI.YBar:EnsureDB()
    end
    local profile = YUI.DB and YUI.DB.GetProfile and YUI.DB:GetProfile("ybar")
    if type(profile) ~= "table" then
        return nil
    end
    if type(profile.YBar) ~= "table" then
        profile.YBar = {}
    end
    return profile.YBar
end
local YBar = YUI.YBar
local GUI2 = YUI.GUI2
local Assets = YUI.Assets
local API = YUI.WOW_API
local FrameAPI = YUI.API and YUI.API.Frame or API
local CombatAPI = YUI.API and YUI.API.Combat or API
local SecurityAPI = YUI.API and YUI.API.Security or API
local SystemAPI = YUI.API and YUI.API.System or API
local Locale = YUI.Locale
local L = Locale and Locale:Get("YBar") or {}
local LC = Locale and Locale:Get("Core") or {}
local Module = YBar.Module:New("MicroMenu")

local DEFAULT_SIZE = 14
local ICON_SIZE_PLUS = 8
local DEFAULT_SPACING = -2
local AUDIO_SYNC_NOTIFICATION_SETTLE_DELAY = 3
local AUDIO_SYNC_EVENT_COALESCE_DELAY = 0.2
local DEFAULT_FONT = STANDARD_TEXT_FONT
local ICON_PATH = Assets:Product("ybar", "micromenu\\")
local VOLUME_ICON = ICON_PATH .. "Volume.png"
local VOLUME_MUTE_ICON = ICON_PATH .. "VolumeMute.png"

local VOLUME_CVARS = {
    { key = "master", labelKey = "micromenu.volume.master_volume", fallback = "主音量", cvar = "Sound_MasterVolume" },
    { key = "music", labelKey = "micromenu.volume.music_volume", fallback = "音乐", cvar = "Sound_MusicVolume" },
    { key = "sfx", labelKey = "micromenu.volume.sfx_volume", fallback = "效果", cvar = "Sound_SFXVolume" },
    { key = "ambience", labelKey = "micromenu.volume.ambience_volume", fallback = "环境音", cvar = "Sound_AmbienceVolume" },
    { key = "dialog", labelKey = "micromenu.volume.dialog_volume", fallback = "对话", cvar = "Sound_DialogVolume" },
}

-- 配置常量（颜色与布局）
local CONFIG = {
    -- Colors
    HEADER_TEXT_COLOR = {r = 1, g = 0.82, b = 0},
    SUBHEADER_TEXT_COLOR = {r = 0, g = 0.6, b = 1},
    -- BNET_NAME_COLOR = {r = 0, g = 0.6, b = 1}, -- |cff0099ff
    BNET_NAME_COLOR = {r = 0.51, g = 0.77, b = 1}, -- |cff82c5ff|
    WOW_NAME_COLOR = {r = 1, g = 0.82, b = 0},
    INACTIVE_ZONE_COLOR = {r = 0.6, g = 0.6, b = 0.6}, -- Grey
    ACTIVE_ZONE_COLOR = {r = 0.3, g = 1, b = 0.3}, -- Greenish
    FOOTER_TEXT_COLOR = {r = 0.5, g = 0.5, b = 0.5},

    -- Layout
    TOOLTIP_WIDTH = 420,
    TOOLTIP_RIGHT_TEXT_WIDTH = 132,
    SCROLL_HEIGHT = 400, -- Max height
    BUTTON_HEIGHT = 22,

    -- Fonts
    FONT_SIZE_HEADER = 16,
    -- FONT_SIZE_NORMAL = 13, -- Deprecated, use DB setting
    FONT_SIZE_SMALL = 11,

    -- Icons
    TEXTURE_ONLINE = "Interface\\FriendsFrame\\StatusIcon-Online",
    TEXTURE_AFK = "Interface\\FriendsFrame\\StatusIcon-Away",
    TEXTURE_DND = "Interface\\FriendsFrame\\StatusIcon-DnD",
    TEXTURE_OFFLINE = "Interface\\FriendsFrame\\StatusIcon-Offline"
}

local BINDING_MAP = {
    ["游戏菜单"] = "TOGGLEGAMEMENU",
    ["公会与社区"] = "TOGGLEGUILDTAB",
    ["好友"] = "TOGGLESOCIAL",
    ["队伍查找器"] = "TOGGLEGROUPFINDER",
    ["角色"] = "TOGGLECHARACTER0",
    ["法术书和专业"] = "TOGGLESPELLBOOK",
    ["成就"] = "TOGGLEACHIEVEMENT",
    ["传承"] = "TOGGLELEGACYSYSTEM",
    ["任务"] = "TOGGLEQUESTLOG",
    ["藏品"] = "TOGGLECOLLECTIONS",
    ["冒险指南"] = "TOGGLEENCOUNTERJOURNAL",
    ["家宅"] = "TOGGLEHOUSINGDASHBOARD",
    ["PVP"] = "TOGGLECHARACTER4",
    ["YUI设置"] = "YUI_TOGGLE",
    ["ElvUI"] = "ELVUI_TOGGLE",
    ["NDUI"] = "NDUI_TOGGLE",
}

local interactiveTooltip
local volumePanel

local function AudioSyncOwnerOnEvent(owner, event, ...)
    owner.module:OnAudioSyncEvent(event, ...)
end

local function T(key, fallback)
    local value = L and L[key]
    if value and value ~= "" and value ~= key then return value end
    return fallback or key
end

local function EnsureModuleDB()
    local ybarDB = GetYBarDB()
    if type(ybarDB) ~= "table" then
        return nil
    end

    if type(ybarDB.MicroMenu) ~= "table" then
        ybarDB.MicroMenu = {}
    end

    local db = ybarDB.MicroMenu
    if db.size == nil then db.size = DEFAULT_SIZE end
    if db.spacing == nil then db.spacing = DEFAULT_SPACING end
    if db.widthMode == nil then db.widthMode = "AUTO" end
    if db.fixedWidth == nil then db.fixedWidth = 300 end
    if db.alignment == nil then db.alignment = "CENTER" end
    if db.autoSyncAudioOutput == nil then db.autoSyncAudioOutput = false end
    if type(db.buttons) ~= "table" then db.buttons = {} end

    return db
end

local function IsMicroMenuReady(frame)
    return not Module._hasError and frame and frame == Module.frame and
        not frame.ybarErrorPlaceholder and not frame.errorText and
        type(Module.buttons) == "table"
end

local function IsMicroMenuButtonReady(btn)
    return IsMicroMenuReady(Module.frame) and btn and btn.GetParent and btn:GetParent()
end

local function GetButtonDisplayName(config)
    if not config then return "" end
    return config.displayName or config.name or ""
end

function Module:OnInitialize()
    self.frame = nil
    self.parent = nil
    self.buttons = {}
    self.audioSyncGeneration = 0
    self.audioSyncPending = false
    self.audioSyncInProgress = false
    self.audioSyncRuntimeActive = false
    self.audioSyncAttemptCount = 0
    self.audioSyncFailureCount = 0
    self.audioSyncRequestCount = 0
    self.audioSyncMergedCount = 0
    self.audioSyncSuppressedCount = 0
    self.audioSyncStartupSkipCount = 0
    self.audioSyncNotificationsArmed = false
    self.audioSyncNotificationArmPending = false
    self.audioSyncNotificationGeneration = 0
    self.audioSyncOwner = {
        module = self,
        OnEvent = AudioSyncOwnerOnEvent,
    }
    EnsureModuleDB()
end

function Module:RegisterButtonEvents()
    if not self.buttons then
        return
    end

    for _, btn in ipairs(self.buttons) do
        local config = btn.config
        if config and config.events then
            YUI.Event:OffOwner(btn)
            for _, event in ipairs(config.events) do
                YUI.Event:On(event, "OnYBarMicroMenuEvent", btn)
            end
        end
    end
end

function Module:UnregisterButtonEvents()
    if not self.buttons then
        return
    end

    for _, btn in ipairs(self.buttons) do
        YUI.Event:OffOwner(btn)
        btn.updatePending = false
    end
end

function Module:AttachRuntime()
    if self._hasError then return end

    self._runtimeAttached = true

    if IsMicroMenuReady(self.frame) then
        self:RegisterButtonEvents()
        self.frame:Show()
        self:UpdateBarItem(self.frame, self.parent)
        if self.RefreshAudioSyncRuntime then
            self:RefreshAudioSyncRuntime()
        end
    end
end

function Module:DetachRuntime()
    self._runtimeAttached = false
    if self.StopAudioSyncRuntime then
        self:StopAudioSyncRuntime()
    end
    self:UnregisterButtonEvents()

    if interactiveTooltip then
        interactiveTooltip.owner = nil
        interactiveTooltip:Hide()
    end

    if volumePanel then
        volumePanel.owner = nil
        volumePanel:Hide()
    end

    if GameTooltip then
        YUI.HideGameTooltip()
    end

    if self.frame then
        self.frame:Hide()
    end
end

-- 数据辅助函数

local ENGLISH_CLASS_NAMES = {}

-- 初始化职业名称映射（本地化 -> 英文键）
do
    for i = 1, API.GetNumClasses and API.GetNumClasses() or 30 do
        local info = API.GetClassInfo(i)
        if info and info.classFile and info.className then
            ENGLISH_CLASS_NAMES[info.className] = info.classFile
        end
    end
end

local function GetClassColor(classFilename)
    if not classFilename then return CreateColor and CreateColor(0.5, 0.5, 0.5) or {WrapTextInColorCode = function(_, text) return "|cff808080"..text.."|r" end} end

    -- 尝试将本地化名称映射为英文键
    local englishClass = ENGLISH_CLASS_NAMES[classFilename] or classFilename
    englishClass = string.upper(englishClass)

    local color = API.GetClassColor(englishClass)
    if color then return color end
    return CreateColor and CreateColor(0.5, 0.5, 0.5) or {WrapTextInColorCode = function(_, text) return "|cff808080"..text.."|r" end}
end

local function FormatName(name, classFilename)
    local color = GetClassColor(classFilename)
    return color:WrapTextInColorCode(name)
end

local function SafeCall(func, bindingKey, allowInCombat, ...)
    if not func then return end
    if not allowInCombat and SecurityAPI.InCombatLockdown() then
        print(
            "|cffFF0000" .. T("micromenu.message.combat_blocked", "战斗中无法执行此操作，请使用快捷键") .. "|r |cffffff00" ..
                (bindingKey or "") .. "|r")
        return
    end
    func(...)
end

local function GetAccentColor()
    if GUI2 and GUI2.GetColor then
        return GUI2:GetColor("color.baritem.hoverText", { 1, 0.82, 0, 1 })
    end
    return 1, 0.82, 0, 1
end

local function RefreshButtonAvailability(btn)
    local condition = btn.config.isEnabled
    if not condition then return true end
    local enabled = condition() == true
    btn.ybarActionEnabled = enabled
    return enabled
end

local function SetButtonIconTexture(btn, texture, atlas)
    if not btn then return end

    if btn.iconSlot then
        YBar:SetIconSlotTexture(btn.iconSlot, texture, atlas)
    elseif btn.icon then
        if atlas then
            btn.icon:SetTexture(nil)
            btn.icon:SetAtlas(atlas)
            btn.icon:SetDesaturated(false)
            btn.icon:SetBlendMode("ADD")
        else
            btn.icon:SetTexture(texture)
            btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.icon:SetBlendMode("BLEND")
        end
        btn.icon:SetVertexColor(1, 1, 1)
    end
end

local function IsSoundEnabled()
    local value = SystemAPI.GetCVar and SystemAPI.GetCVar("Sound_EnableAllSound")
    if value == nil then return true end
    if SystemAPI.GetCVarBool then
        return SystemAPI.GetCVarBool("Sound_EnableAllSound")
    end
    return value == true or value == 1 or value == "1" or value == "true"
end

local function SetSoundEnabled(enabled)
    if SystemAPI.SetCVar then
        SystemAPI.SetCVar("Sound_EnableAllSound", enabled and 1 or 0)
    elseif SetCVar then
        SetCVar("Sound_EnableAllSound", enabled and 1 or 0)
    end
end

local function GetVolumePercent(cvar)
    local value = SystemAPI.GetCVarNumber and SystemAPI.GetCVarNumber(cvar) or
        (SystemAPI.GetCVar and tonumber(SystemAPI.GetCVar(cvar))) or 0
    if not value then value = 0 end
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    return math.floor(value * 100 + 0.5)
end

local function SetVolumePercent(cvar, value)
    value = tonumber(value) or 0
    if value < 0 then value = 0 end
    if value > 100 then value = 100 end
    local cvarValue = string.format("%.2f", value / 100)
    if SystemAPI.SetCVar then
        SystemAPI.SetCVar(cvar, cvarValue)
    elseif SetCVar then
        SetCVar(cvar, cvarValue)
    end
end

local function GetAudioOutputOptions()
    local options = SystemAPI.GetAudioOutputDeviceOptions and
        SystemAPI.GetAudioOutputDeviceOptions() or {}
    if #options > 0 then return options end

    return {
        {
            text = T("micromenu.volume.output_unavailable", "不可用"),
            value = SystemAPI.GetAudioOutputDeviceIndex and
                SystemAPI.GetAudioOutputDeviceIndex() or 0,
        }
    }
end

local function HasAudioOutputOptions()
    local options = SystemAPI.GetAudioOutputDeviceOptions and
        SystemAPI.GetAudioOutputDeviceOptions() or {}
    return #options > 0
end

local function HasAudioSettings()
    if SystemAPI.CanOpenAudioSettings then
        return SystemAPI.CanOpenAudioSettings()
    end
    return SystemAPI.OpenAudioSettings and Settings and Settings.OpenToCategory and
        Settings.AUDIO_CATEGORY_ID
end

local function IsYUISuiteLoaded()
    if YUI.CoreMode == "suite" then
        return true
    end

    if SystemAPI.IsAddOnLoadedSafe then
        return SystemAPI.IsAddOnLoadedSafe("YUI")
    end

    if SystemAPI.IsAddOnLoaded then
        return SystemAPI.IsAddOnLoaded("YUI")
    end

    return false
end

local function RefreshVolumeButton(btn)
    local icon = IsSoundEnabled() and VOLUME_ICON or VOLUME_MUTE_ICON
    SetButtonIconTexture(btn, icon)
end

local function RefreshVolumePanel()
    local panel = volumePanel
    if not panel then return end

    local enabled = IsSoundEnabled()

    if panel.enableCheckbox then
        panel.enableCheckbox:SetChecked(enabled, true)
    end

    if panel.autoSyncCheckbox then
        local db = EnsureModuleDB()
        panel.autoSyncCheckbox:SetChecked(db and db.autoSyncAudioOutput == true, true)
    end

    if panel.outputDropdown then
        panel.outputDropdown:SetValue(
            SystemAPI.GetAudioOutputDeviceIndex and
                SystemAPI.GetAudioOutputDeviceIndex() or 0,
            true
        )
        panel.outputDropdown:SetDisabled((not enabled) or not HasAudioOutputOptions())
    end

    if panel.volumeSliders then
        for _, item in ipairs(VOLUME_CVARS) do
            local slider = panel.volumeSliders[item.key]
            if slider then
                slider:SetValue(GetVolumePercent(item.cvar), true)
                slider:SetDisabled(not enabled)
            end
        end
    end

    local showMore = HasAudioSettings()
    if panel.moreButton then
        if showMore then
            panel.moreButton:Show()
        else
            panel.moreButton:Hide()
        end
    end

    panel:SetHeight(showMore and 331 or 297)
end

local function IsVolumeButtonEnabled(db)
    return db and type(db.buttons) == "table" and db.buttons.Volume ~= false
end

local function IsAudioSyncEffective()
    local db = EnsureModuleDB()
    return Module._runtimeAttached == true and IsMicroMenuReady(Module.frame) and
        db and db.autoSyncAudioOutput == true and IsVolumeButtonEnabled(db)
end

function Module:PrintAudioSyncResult(success)
    YUI:Print(L[success and "micromenu.volume.sync_success_chat" or "micromenu.volume.sync_failed_chat"])
    return true
end

function Module:StopAudioSyncRuntime()
    self.audioSyncGeneration = (self.audioSyncGeneration or 0) + 1
    self.audioSyncNotificationGeneration = (self.audioSyncNotificationGeneration or 0) + 1
    self.audioSyncPending = false
    if self.audioSyncTimer then self.audioSyncTimer:Cancel(); self.audioSyncTimer = nil end
    self.audioSyncShouldNotify = false
    self.audioSyncInProgress = false
    self.audioSyncRuntimeActive = false
    self.audioSyncNotificationsArmed = false
    self.audioSyncNotificationArmPending = false
    if self.audioSyncOwner and YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(self.audioSyncOwner)
    end
end

function Module:PerformAudioOutputSync(notify)
    if not IsAudioSyncEffective() or self.audioSyncInProgress then
        return false
    end

    self.audioSyncInProgress = true
    local now = SystemAPI.GetTimePreciseSec and SystemAPI.GetTimePreciseSec() or
        SystemAPI.GetTime and SystemAPI.GetTime() or
        (GetTime and GetTime()) or 0
    self.audioSyncSuppressUntil = now + 0.5

    self.audioSyncAttemptCount = (self.audioSyncAttemptCount or 0) + 1
    local success = SystemAPI.SyncAudioOutputToSystemDefault and
        SystemAPI.SyncAudioOutputToSystemDefault() or false
    if not success then
        self.audioSyncFailureCount = (self.audioSyncFailureCount or 0) + 1
    end
    -- The native restart may itself block longer than the suppression window.
    -- Start the asynchronous echo guard after it returns, not before it starts.
    local finished = SystemAPI.GetTimePreciseSec and SystemAPI.GetTimePreciseSec() or
        SystemAPI.GetTime and SystemAPI.GetTime() or (GetTime and GetTime()) or now
    self.audioSyncSuppressUntil = finished + 0.5
    self.audioSyncInProgress = false
    RefreshVolumePanel()

    if notify then
        self:PrintAudioSyncResult(success)
    end
    return success
end

function Module:ScheduleAudioSyncNotificationArm()
    if self.audioSyncNotificationsArmed or self.audioSyncNotificationArmPending then
        return
    end

    if not (C_Timer and C_Timer.After) then
        self.audioSyncNotificationsArmed = true
        return
    end

    self.audioSyncNotificationArmPending = true
    self.audioSyncNotificationGeneration = (self.audioSyncNotificationGeneration or 0) + 1
    local generation = self.audioSyncNotificationGeneration
    C_Timer.After(AUDIO_SYNC_NOTIFICATION_SETTLE_DELAY, function()
        if Module.audioSyncNotificationGeneration ~= generation then
            return
        end
        Module.audioSyncNotificationArmPending = false
        if Module.audioSyncRuntimeActive then
            Module.audioSyncNotificationsArmed = true
        end
    end)
end

function Module:QueueAudioOutputSync(notify, delay)
    if not IsAudioSyncEffective() or self.audioSyncInProgress then
        return false
    end

    self.audioSyncRequestCount = (self.audioSyncRequestCount or 0) + 1
    self.audioSyncShouldNotify = self.audioSyncShouldNotify or notify == true
    if self.audioSyncPending then
        self.audioSyncMergedCount = (self.audioSyncMergedCount or 0) + 1
        return true
    end

    self.audioSyncPending = true
    local generation = self.audioSyncGeneration or 0
    local function RunSync()
        if Module.audioSyncGeneration ~= generation then
            return
        end
        Module.audioSyncTimer = nil
        Module.audioSyncPending = false
        local shouldNotify = Module.audioSyncShouldNotify == true
        Module.audioSyncShouldNotify = false
        Module:PerformAudioOutputSync(shouldNotify)
    end

    if C_Timer and C_Timer.NewTimer then
        self.audioSyncTimer = C_Timer.NewTimer(delay or 0, RunSync)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(delay or 0, RunSync)
    else
        RunSync()
    end
    return true
end

function Module:OnAudioSyncEvent(event, cvarName)
    if not IsAudioSyncEffective() then
        return
    end

    if event == "CVAR_UPDATE" then
        if string.lower(tostring(cvarName or "")) ~= "sound_outputdriverindex" then
            return
        end
        local index = SystemAPI.GetAudioOutputDeviceIndex and
            SystemAPI.GetAudioOutputDeviceIndex() or 0
        if tonumber(index) ~= 0 then
            self:SetAutoSyncAudioOutput(false)
        end
        return
    end

    if event == "SOUND_DEVICE_UPDATE" or
        event == "VOICE_CHAT_OUTPUT_DEVICES_UPDATED" then
        local now = SystemAPI.GetTimePreciseSec and SystemAPI.GetTimePreciseSec() or
            SystemAPI.GetTime and SystemAPI.GetTime() or
            (GetTime and GetTime()) or 0
        if self.audioSyncInProgress or now < (self.audioSyncSuppressUntil or 0) then
            self.audioSyncSuppressedCount = (self.audioSyncSuppressedCount or 0) + 1
            return
        end
        local notify = self.audioSyncNotificationsArmed == true
        self:QueueAudioOutputSync(notify, AUDIO_SYNC_EVENT_COALESCE_DELAY)
        if not notify then
            self:ScheduleAudioSyncNotificationArm()
        end
    end
end

function Module:RefreshAudioSyncRuntime(syncNow)
    if not IsAudioSyncEffective() then
        if self.audioSyncRuntimeActive then
            self:StopAudioSyncRuntime()
        end
        return false
    end

    local newlyActive = not self.audioSyncRuntimeActive
    if newlyActive then
        local owner = self.audioSyncOwner
        self.audioSyncOwner = owner
        self.audioSyncRuntimeActive = true
        if YUI.Event and YUI.Event.On then
            YUI.Event:On("SOUND_DEVICE_UPDATE", "OnEvent", owner)
            YUI.Event:On("VOICE_CHAT_OUTPUT_DEVICES_UPDATED", "OnEvent", owner)
            YUI.Event:On("CVAR_UPDATE", "OnEvent", owner)
        end
    end

    if syncNow then
        self.audioSyncNotificationGeneration = (self.audioSyncNotificationGeneration or 0) + 1
        self.audioSyncNotificationArmPending = false
        self.audioSyncNotificationsArmed = true
    end

    if newlyActive and not syncNow then
        local index = SystemAPI.GetAudioOutputDeviceIndex and SystemAPI.GetAudioOutputDeviceIndex()
        if not (issecretvalue and issecretvalue(index)) and index == 0 then
            -- Reloading the UI does not require reinitializing the sound engine.
            -- Device invalidations and explicit manual sync still force a sync.
            self.audioSyncStartupSkipCount = (self.audioSyncStartupSkipCount or 0) + 1
            self:ScheduleAudioSyncNotificationArm()
            return true
        end
    end
    if newlyActive or syncNow then
        self:QueueAudioOutputSync(syncNow == true)
    end
    return true
end

function Module:SetAutoSyncAudioOutput(enabled)
    local db = EnsureModuleDB()
    if not db then return false end
    db.autoSyncAudioOutput = enabled == true
    RefreshVolumePanel()
    if enabled then
        self:RefreshAudioSyncRuntime(true)
    else
        self:StopAudioSyncRuntime()
    end
    return true
end

function Module:SelectAudioOutputDevice(value)
    self:SetAutoSyncAudioOutput(false)
    local success
    if SystemAPI.SetAudioOutputDeviceIndex then
        success = SystemAPI.SetAudioOutputDeviceIndex(value)
    elseif SystemAPI.SetCVar then
        success = SystemAPI.SetCVar("Sound_OutputDriverIndex", value)
    else
        success = false
    end
    RefreshVolumePanel()
    return success
end

local function CreateVolumePanel()
    if volumePanel then return volumePanel end

    local f = GUI2:CreatePanel(UIParent, {
        name = "YBarMicroMenuVolumePanel",
        width = 300,
        height = 331,
        surface = "color.surface.popup",
        border = "color.popup.border",
        nativeFrameBorder = true,
        nativeFrameBorderStyle = "tooltip",
        shadow = true,
        shadowKey = "shadow.popup.size",
    })
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f.volumeSliders = {}

    f.title = YBar:CreateThemedText(f, {
        text = T("micromenu.volume.panel_title", "快捷音量"),
        fontPath = GameFontNormal:GetFont(),
        fontSize = CONFIG.FONT_SIZE_HEADER,
        fontFlags = "OUTLINE",
        colorKey = "color.ybar.tooltip.header",
        fallback = { CONFIG.HEADER_TEXT_COLOR.r, CONFIG.HEADER_TEXT_COLOR.g, CONFIG.HEADER_TEXT_COLOR.b, 1 },
    })
    f.title:SetPoint("TOPLEFT", 14, -10)

    local labelWidth = 76
    local controlX = 92
    local controlWidth = 178
    local rowHeight = 28
    local rowY = -40

    local function CreateRow(labelText)
        local row = GUI2:CreateFrame(f, { width = 276, height = rowHeight })
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 12, rowY)
        rowY = rowY - 31

        local label = GUI2:CreateText(row, labelText, "font.size.md", "color.text.primary", "LEFT")
        label:SetPoint("LEFT", 0, 0)
        label:SetWidth(labelWidth)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        row.label = label
        return row
    end

    do
        local row = CreateRow(T("micromenu.volume.enable_sound", "开启声效"))
        local checkbox = GUI2.Form:CreateCheckbox(row, {
            label = "",
            width = 28,
            get = IsSoundEnabled,
            set = function(value)
                SetSoundEnabled(value)
                RefreshVolumeButton(f.owner)
                RefreshVolumePanel()
            end,
        })
        checkbox:SetPoint("LEFT", row, "LEFT", controlX, 0)
        f.enableCheckbox = checkbox
    end

    do
        local row = CreateRow(T("micromenu.volume.auto_sync_output", "自动同步"))
        local checkbox = GUI2.Form:CreateCheckbox(row, {
            label = "",
            width = 28,
            get = function()
                local db = EnsureModuleDB()
                return db and db.autoSyncAudioOutput == true
            end,
            set = function(value)
                Module:SetAutoSyncAudioOutput(value)
            end,
        })
        checkbox:SetPoint("LEFT", row, "LEFT", controlX, 0)
        f.autoSyncCheckbox = checkbox
    end

    do
        local row = CreateRow(T("micromenu.volume.output_device", "输出设备"))
        local dropdown = GUI2.Form:CreateDropdown(row, {
            width = controlWidth,
            options = GetAudioOutputOptions,
            get = function()
                return SystemAPI.GetAudioOutputDeviceIndex and
                    SystemAPI.GetAudioOutputDeviceIndex() or 0
            end,
            set = function(value)
                Module:SelectAudioOutputDevice(value)
            end,
            placeholder = T("micromenu.volume.output_unavailable", "不可用"),
        })
        dropdown:SetPoint("LEFT", row, "LEFT", controlX, 0)
        f.outputDropdown = dropdown
    end

    for _, item in ipairs(VOLUME_CVARS) do
        local row = CreateRow(T(item.labelKey, item.fallback))
        local slider = GUI2.Form:CreateSlider(row, {
            width = controlWidth,
            inline = true,
            inputWidth = 42,
            min = 0,
            max = 100,
            step = 1,
            get = function()
                return GetVolumePercent(item.cvar)
            end,
            set = function(value)
                SetVolumePercent(item.cvar, value)
            end,
        })
        slider:SetPoint("LEFT", row, "LEFT", controlX, 0)
        f.volumeSliders[item.key] = slider
    end

    f.moreButton = GUI2.Form:CreateButton(f, {
        text = T("micromenu.volume.more_settings", "更多设置"),
        width = 120,
        height = 24,
        onClick = function()
            if SystemAPI.OpenAudioSettings and SystemAPI.OpenAudioSettings() then
                f:Hide()
            end
        end,
    })
    f.moreButton:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)

    local function VolumePanelOnUpdate(self, elapsed)
        if not Module._runtimeAttached then
            self:Hide()
            return
        end

        self.timer = (self.timer or 0) + elapsed
        if self.timer <= 0.05 then return end
        self.timer = 0

        local dropdownShown = GUI2.DropdownFrame and GUI2.DropdownFrame:IsShown()
        local overPanel = self:IsMouseOver()
        local overOwner = self.owner and self.owner:IsMouseOver()
        if dropdownShown or overPanel or overOwner then
            self.fadeTimer = 0
            return
        end

        self.fadeTimer = (self.fadeTimer or 0) + 0.05
        if self.fadeTimer > 0.2 then
            self:Hide()
        end
    end
    f:SetScript("OnUpdate", VolumePanelOnUpdate)
    f:SetScript("OnShow", function(self)
        self:SetScript("OnUpdate", VolumePanelOnUpdate)
    end)

    f:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        self.owner = nil
        if GUI2.DropdownFrame and GUI2.DropdownFrame:IsShown() then
            GUI2.DropdownFrame:Hide()
        end
    end)

    volumePanel = f
    return f
end

local function ToggleVolumePanel(owner)
    if not Module._runtimeAttached then return end
    if volumePanel and volumePanel:IsShown() and volumePanel.owner == owner then
        volumePanel:Hide()
        return
    end

    if interactiveTooltip then
        interactiveTooltip.owner = nil
        interactiveTooltip:Hide()
    end
    if GameTooltip then
        YUI.HideGameTooltip()
    end

    local panel = CreateVolumePanel()
    panel.owner = owner
    panel.fadeTimer = 0
    RefreshVolumePanel()

    panel:ClearAllPoints()
    if owner:GetBottom() > GetScreenHeight() / 2 then
        panel:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -5)
    else
        panel:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 5)
    end
    panel:Show()
end

local function GetOnlineGuildMembers()
    local members = {}
    local numTotal = API.GetNumGuildMembers()

    for i = 1, numTotal do
        local name, rankName, rankIndex, level, classDisplayName, zone,
              publicNote, officerNote, isOnline, status, class,
              achievementPoints, achievementRank, isMobile, canSoR, repStanding,
              guid = API.GetGuildRosterInfo(i)

        if isOnline then
            local fullName = name
            name = string.gsub(name, "%-.+", "")
            table.insert(members, {
                name = name,
                fullName = fullName,
                rank = rankName,
                rankIndex = rankIndex,
                level = level,
                class = class,
                zone = zone,
                status = status,
                guid = guid
            })
        end
    end

    table.sort(members, function(a, b)
        if a.rankIndex ~= b.rankIndex then
            return (a.rankIndex or 999) < (b.rankIndex or 999)
        end

        if a.level ~= b.level then return (a.level or 0) > (b.level or 0) end

        if a.class ~= b.class then
            return (a.class or "") < (b.class or "")
        end

        return (a.name or "") < (b.name or "")
    end)

    return members
end

local function GetOnlineFriends()
    local friends = {}

    local numWoW = API.GetNumFriends()
    for i = 1, numWoW do
        local info = API.GetFriendInfoByIndex(i)

        if info and info.connected then
            local status = CONFIG.TEXTURE_ONLINE
            if info.afk then
                status = CONFIG.TEXTURE_AFK
            elseif info.dnd then
                status = CONFIG.TEXTURE_DND
            end

            table.insert(friends, {
                type = "WoW",
                name = info.name,
                level = info.level,
                class = info.className,
                zone = info.area,
                statusTexture = status,
                guid = info.guid,
                notes = info.notes,
                game = "WoW"
            })
        end
    end

    local numBNet, _ = API.BNGetNumFriends()
    for i = 1, numBNet do
        local accountInfo = API.BNGetFriendAccountInfo(i)
        if accountInfo then
            local accountName = accountInfo.accountName
            local battleTag = accountInfo.battleTag
            local isAFK = accountInfo.isAFK
            local isDND = accountInfo.isDND
            local note = accountInfo.note
            local gameAccountInfo = accountInfo.gameAccountInfo

            if gameAccountInfo and gameAccountInfo.isOnline then
                local charName = gameAccountInfo.characterName
                local client = gameAccountInfo.clientProgram
                local class = gameAccountInfo.className or "?"
                local zoneName = gameAccountInfo.areaName
                local level = gameAccountInfo.characterLevel
                local gameText = gameAccountInfo.richPresence or ""
                local isGameAFK = gameAccountInfo.isGameAFK
                local isGameBusy = gameAccountInfo.isGameBusy
                local wowProjectID = gameAccountInfo.wowProjectID
                local isMobile = gameAccountInfo.isWowMobile
                local factionName = gameAccountInfo.factionName or "?"

                local status = CONFIG.TEXTURE_ONLINE
                if isAFK or isGameAFK then
                    status = CONFIG.TEXTURE_AFK
                elseif isDND or isGameBusy then
                    status = CONFIG.TEXTURE_DND
                end

                if client == BNET_CLIENT_WOW then
                    if wowProjectID == WOW_PROJECT_60 then
                        gameText = EXPANSION_NAME0
                    elseif wowProjectID == WOW_PROJECT_CATA then
                        gameText = EXPANSION_NAME3
                    elseif wowProjectID == WOW_PROJECT_ID then
                        gameText = zoneName or gameText
                    end
                elseif client == "App" or client == "BSAp" then
                    gameText = "Battle.net"
                end

                if isMobile then gameText = "APP" end

                table.insert(friends, {
                    type = "BNet",
                    name = accountName,
                    charName = charName,
                    level = level,
                    class = class,
                    zone = gameText,
                    statusTexture = status,
                    client = client,
                    faction = factionName,
                    wowProjectID = wowProjectID,
                    bnetID = accountInfo.bnetAccountID,
                    gameAccountID = gameAccountInfo.gameAccountID,
                    guid = gameAccountInfo.playerGuid,
                    battleTag = battleTag,
                    game = client,
                    isMobile = isMobile
                })
            end
        end
    end

    local myFaction = API.UnitFactionGroup("player")

    local function GetFriendScore(data)
        if data.type == "WoW" then return 5 end

        if data.isMobile or data.client == "App" or data.client == "BSAp" then
            return 1
        end

        if data.client == BNET_CLIENT_WOW then
            if data.wowProjectID == WOW_PROJECT_ID then
                return 4
            else
                return 3
            end
        end

        if data.client and data.client ~= "" then return 2 end

        return 1
    end

    table.sort(friends, function(a, b)
        local scoreA = GetFriendScore(a)
        local scoreB = GetFriendScore(b)

        if scoreA ~= scoreB then return scoreA > scoreB end

        if scoreA == 4 then
            local aFac = a.faction or (a.type == "WoW" and myFaction)
            local bFac = b.faction or (b.type == "WoW" and myFaction)

            if aFac ~= bFac then
                if aFac == myFaction then return true end
                if bFac == myFaction then return false end
                return (aFac or "") < (bFac or "")
            end
        end

        return (a.name or "") < (b.name or "")
    end)

    return friends
end

-- 交互式 Tooltip 实现

local function CreateInteractiveTooltip()
    if interactiveTooltip then return interactiveTooltip end

    local f = GUI2:CreateFrame(UIParent, { name = "YUIMicroMenuInteractiveTooltip", template = "BackdropTemplate" })
    f:SetClampedToScreen(true)
    f:SetFrameStrata("TOOLTIP")

    GUI2:CreateBackdrop(f, {
        surface = "color.surface.popup",
        border = "color.popup.border",
        nativeFrameBorder = true,
        nativeFrameBorderStyle = "tooltip",
    })

    local db = EnsureModuleDB() or {}
    local fontSize = db.size or DEFAULT_SIZE

    -- 标题
    f.header = YBar:CreateThemedText(f, {
        fontPath = GameFontNormal:GetFont(),
        fontSize = CONFIG.FONT_SIZE_HEADER,
        fontFlags = "OUTLINE",
        colorKey = "color.ybar.tooltip.header",
        fallback = { CONFIG.HEADER_TEXT_COLOR.r, CONFIG.HEADER_TEXT_COLOR.g, CONFIG.HEADER_TEXT_COLOR.b, 1 },
    })
    f.header:SetPoint("TOPLEFT", 15, -10)

    -- 副标题（在线人数）
    f.subHeader = YBar:CreateThemedText(f, {
        fontPath = GameFontHighlightSmall:GetFont(),
        fontSize = fontSize,
        fontFlags = "OUTLINE",
        colorKey = "color.ybar.tooltip.subheader",
        fallback = { CONFIG.SUBHEADER_TEXT_COLOR.r, CONFIG.SUBHEADER_TEXT_COLOR.g, CONFIG.SUBHEADER_TEXT_COLOR.b, 1 },
    })
    f.subHeader:SetPoint("TOPRIGHT", -15, -10)

    -- 页脚（说明）
    f.footer = YBar:CreateThemedText(f, {
        fontPath = GameFontHighlightSmall:GetFont(),
        fontSize = fontSize,
        fontFlags = "OUTLINE",
        colorKey = "color.ybar.text",
        fallback = { 1, 1, 1, 1 },
    })
    f.footer:SetPoint("BOTTOM", 0, 5)

    local headerColor = CreateColor(CONFIG.HEADER_TEXT_COLOR.r,
                                    CONFIG.HEADER_TEXT_COLOR.g,
                                    CONFIG.HEADER_TEXT_COLOR.b)
    local headerHex = headerColor:GenerateHexColor()
    local white = "|cffffffff"
    local gold = "|c" .. headerHex

    f.footer:SetText(format(
                         "%s%s: |r%s%s|r | %s%s: |r%s%s|r",
                         white, LC["common.right_click"], gold, T("micromenu.tooltip.whisper", "密语"),
                         white, LC["common.alt_left_click"], gold, T("micromenu.tooltip.invite", "邀请")))

    -- 滚动框架
    f.scrollFrame = GUI2:CreateScrollFrame(f, { template = false, child = false })
    f.scrollFrame:SetPoint("TOPLEFT", 10, -30)
    f.scrollFrame:SetPoint("BOTTOMRIGHT", -10, 25) -- Leave space for footer
    f.scrollFrame:SetClipsChildren(true) -- Force clipping

    f.content = GUI2:CreateFrame(f.scrollFrame)
    f.scrollFrame:SetScrollChild(f.content)

    -- 鼠标滚轮处理
    f:EnableMouseWheel(true)
    f.scrollFrame:EnableMouseWheel(true) -- Also enable on ScrollFrame just in case

    local function OnMouseWheel(self, delta)
        local current = f.scrollFrame:GetVerticalScroll()
        local maxScroll = f.scrollFrame:GetVerticalScrollRange()
        local new = current - (delta * 20)
        if new < 0 then new = 0 end
        if new > maxScroll then new = maxScroll end
        f.scrollFrame:SetVerticalScroll(new)
    end

    f:SetScript("OnMouseWheel", OnMouseWheel)
    f.scrollFrame:SetScript("OnMouseWheel", OnMouseWheel)

    -- 自动隐藏逻辑
    local function InteractiveTooltipOnUpdate(self, elapsed)
        if not Module._runtimeAttached then
            self:Hide()
            return
        end

        self.timer = (self.timer or 0) + elapsed
        if self.timer > 0.05 then -- Faster check for responsiveness
            self.timer = 0

            local isOverTooltip = self:IsMouseOver()
            local isOverOwner = self.owner and self.owner:IsMouseOver()

            if isOverTooltip or isOverOwner then
                self.fadeTimer = 0
                self:SetAlpha(1)
            else
                -- Grace period before hiding
                self.fadeTimer = (self.fadeTimer or 0) + 0.05
                if self.fadeTimer > 0.15 then -- 150ms buffer
                    self:Hide()
                end
            end
        end
    end
    f:SetScript("OnUpdate", InteractiveTooltipOnUpdate)
    f:SetScript("OnShow", function(self)
        self:SetScript("OnUpdate", InteractiveTooltipOnUpdate)
    end)
    f:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        self.owner = nil
    end)

    f.lines = {}
    interactiveTooltip = f
    return f
end

local function GetLineButton(tooltip, index)
    local db = EnsureModuleDB() or {}
    local fontSize = db.size or DEFAULT_SIZE

    if not tooltip.lines[index] then
        local btn = GUI2:CreateButtonFrame(tooltip.content)
        btn:SetHeight(CONFIG.BUTTON_HEIGHT)
        btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        btn.hoverBg = GUI2:CreateTexture(btn, "color.control.hover", "BACKGROUND")
        btn.hoverBg:SetAllPoints(btn)
        btn.hoverBg:SetAlpha(0.42)
        btn.hoverBg:Hide()
        btn.SetLineHover = function(self, hovered)
            if hovered then
                GUI2:SetTexturePaintKey(self.hoverBg, "color.control.hover")
                self.hoverBg:Show()
            else
                self.hoverBg:Hide()
            end
        end

        -- 状态图标
        btn.statusIconSlot, btn.statusIcon = YBar:CreateIconSlot(btn, {
            size = 16,
            variant = "bare",
            shape = "square",
            padding = 0,
        })
        local statusIconFrame = btn.statusIconSlot or btn.statusIcon
        statusIconFrame:SetPoint("LEFT", 5, 0)

        -- 左侧：文本（名称）
        btn.textLeftFrame = GUI2:CreateFrame(btn)
        btn.textLeftFrame:SetPoint("LEFT", statusIconFrame, "RIGHT", 5, 0)
        btn.textLeftFrame:SetHeight(CONFIG.BUTTON_HEIGHT)
        local _, textLeft = YBar:CreateStatusText(btn.textLeftFrame, {
            single = true,
            justifyH = "LEFT",
            colorKey = "color.ybar.text",
        })
        btn.textLeft = textLeft
        btn.textLeft:SetFont(GameFontHighlightSmall:GetFont(),
                             fontSize, "OUTLINE")
        btn.textLeft:SetJustifyH("LEFT")
        btn.textLeft:SetWordWrap(false)

        -- 游戏图标
        btn.gameIconSlot, btn.gameIcon = YBar:CreateIconSlot(btn, {
            size = 16,
            variant = "bare",
            shape = "square",
            padding = 0,
        })
        local gameIconFrame = btn.gameIconSlot or btn.gameIcon
        gameIconFrame:SetPoint("RIGHT", -5, 0)

        -- 右侧：文本（信息）
        btn.textRightFrame = GUI2:CreateFrame(btn)
        btn.textRightFrame:SetPoint("RIGHT", gameIconFrame, "LEFT", -5, 0)
        btn.textRightFrame:SetSize(CONFIG.TOOLTIP_RIGHT_TEXT_WIDTH,
                                   CONFIG.BUTTON_HEIGHT)
        btn.textLeftFrame:SetPoint("RIGHT", btn.textRightFrame, "LEFT", -6, 0)
        local _, textRight = YBar:CreateStatusText(btn.textRightFrame, {
            single = true,
            justifyH = "RIGHT",
            colorKey = "color.ybar.text",
        })
        btn.textRight = textRight
        btn.textRight:SetFont(GameFontHighlightSmall:GetFont(),
                              fontSize, "OUTLINE")
        btn.textRight:SetJustifyH("RIGHT")
        btn.textRight:SetWordWrap(false)

        tooltip.lines[index] = btn
    end

    -- 确保复用时更新字体大小
    local btn = tooltip.lines[index]
    local fontLeft, _, flagsLeft = btn.textLeft:GetFont()
    if select(2, btn.textLeft:GetFont()) ~= fontSize then
         btn.textLeft:SetFont(fontLeft, fontSize, flagsLeft)
         btn.textRight:SetFont(fontLeft, fontSize, flagsLeft)
    end

    return tooltip.lines[index]
end

local function ShowInteractiveTooltip(owner, type)
    if not Module._runtimeAttached then
        return
    end

    local tooltip = CreateInteractiveTooltip()
    tooltip.owner = owner

    tooltip:ClearAllPoints()
    if owner:GetBottom() > GetScreenHeight() / 2 then
        tooltip:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -5)
    else
        tooltip:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 5)
    end

    local dataList = {}
    local title = ""
    local countStr = ""
    local bindingAction = ""

    if type == "Guild" then
        dataList = GetOnlineGuildMembers()
        local numTotal, numOnline, numOnlineAndMobile = API.GetNumGuildMembers()
        local effectiveOnline =
            (numOnlineAndMobile and numOnlineAndMobile > 0) and
                numOnlineAndMobile or numOnline

        local guildName = API.GetGuildInfo("player") or T("micromenu.tooltip.no_guild", "无公会")
        title = guildName
        countStr = format("%d/%d", effectiveOnline, numTotal)
        bindingAction = "TOGGLEGUILDTAB"

        YBar:SetThemedTextColor(tooltip.header, "color.ybar.tooltip.header",
                                { CONFIG.HEADER_TEXT_COLOR.r, CONFIG.HEADER_TEXT_COLOR.g, CONFIG.HEADER_TEXT_COLOR.b, 1 })
        YBar:SetThemedTextColor(tooltip.subHeader,
                                "color.ybar.tooltip.subheader",
                                { CONFIG.SUBHEADER_TEXT_COLOR.r, CONFIG.SUBHEADER_TEXT_COLOR.g, CONFIG.SUBHEADER_TEXT_COLOR.b, 1 })

    elseif type == "Friends" then
        dataList = GetOnlineFriends()
        local numFriends = API.GetNumFriends()
        local onlineFriends = API.GetNumOnlineFriends()
        local numBNet, onlineBNet = API.BNGetNumFriends()

        local totalOnline = onlineFriends + onlineBNet
        local totalFriends = numFriends + numBNet

        title = T("micromenu.tooltip.friends_title", "好友列表")
        countStr = format("%d/%d", totalOnline, totalFriends)
        bindingAction = "TOGGLESOCIAL"

        YBar:SetThemedTextColor(tooltip.header, "color.ybar.tooltip.header",
                                { CONFIG.HEADER_TEXT_COLOR.r, CONFIG.HEADER_TEXT_COLOR.g, CONFIG.HEADER_TEXT_COLOR.b, 1 })
        YBar:SetThemedTextColor(tooltip.subHeader,
                                "color.ybar.tooltip.subheader",
                                { CONFIG.SUBHEADER_TEXT_COLOR.r, CONFIG.SUBHEADER_TEXT_COLOR.g, CONFIG.SUBHEADER_TEXT_COLOR.b, 1 })
    end

    if bindingAction then
        local key = API.GetBindingKey(bindingAction)
        if key then
            title = title ..
                        format("|cffffffff (%s)|r", API.GetBindingText(key))
        end
    end

    tooltip.header:SetText(title)
    tooltip.subHeader:SetText(countStr)

    for _, btn in pairs(tooltip.lines) do btn:Hide() end

    local contentHeight = 0
    local maxWidth = CONFIG.TOOLTIP_WIDTH

    for i, data in ipairs(dataList) do
        local btn = GetLineButton(tooltip, i)
        btn:Show()
        btn:SetLineHover(false)
        btn:SetPoint("TOPLEFT", 0, -((i - 1) * CONFIG.BUTTON_HEIGHT))
        btn:SetWidth(maxWidth)

        local leftText = ""
        local rightText = ""

        if type == "Guild" then
            local levelColor = API.GetQuestDifficultyColor(data.level or 1)
            local levelHex = CreateColor(levelColor.r, levelColor.g,
                                         levelColor.b):GenerateHexColor()

            leftText = format("|c%s%s|r %s |cff888888(%s)|r", levelHex,
                              data.level or "??",
                              FormatName(data.name, data.class), data.rank)

            local zoneColor = (data.zone == API.GetRealZoneText()) and
                                  "|cff40ff40" or "|cffffffff"
            rightText = zoneColor .. (data.zone or "") .. "|r"

            btn.textLeft:SetText(leftText)
            btn.textRight:SetText(rightText)
            if btn.statusIconSlot then btn.statusIconSlot:Hide() else btn.statusIcon:Hide() end
            if btn.gameIconSlot then btn.gameIconSlot:Hide() else btn.gameIcon:Hide() end

        elseif type == "Friends" then
            if data.statusTexture then
                btn.statusIcon:SetTexture(data.statusTexture)
                if btn.statusIconSlot then btn.statusIconSlot:Show() else btn.statusIcon:Show() end
            else
                if btn.statusIconSlot then btn.statusIconSlot:Hide() else btn.statusIcon:Hide() end
            end

            local nameText = ""
            local infoText = ""
            local zoneColorHex = CreateColor(CONFIG.INACTIVE_ZONE_COLOR.r,
                                             CONFIG.INACTIVE_ZONE_COLOR.g,
                                             CONFIG.INACTIVE_ZONE_COLOR.b):GenerateHexColor()

            if data.type == "BNet" then
                local bnetColor = CreateColor(CONFIG.BNET_NAME_COLOR.r,
                                              CONFIG.BNET_NAME_COLOR.g,
                                              CONFIG.BNET_NAME_COLOR.b)
                nameText = bnetColor:WrapTextInColorCode(data.name)

                if data.charName then
                    local charNameText = data.charName
                    if data.client == BNET_CLIENT_WOW and data.wowProjectID ==
                        WOW_PROJECT_ID then
                        charNameText = FormatName(data.charName, data.class)

                        if data.zone == API.GetRealZoneText() then
                            zoneColorHex = CreateColor(
                                               CONFIG.ACTIVE_ZONE_COLOR.r,
                                               CONFIG.ACTIVE_ZONE_COLOR.g,
                                               CONFIG.ACTIVE_ZONE_COLOR.b):GenerateHexColor()
                        end
                    else
                        charNameText = "|cff888888" .. data.charName .. "|r"
                    end
                    nameText = nameText .. " (" .. charNameText .. ")"
                end

                infoText = "|c" .. zoneColorHex .. (data.zone or "") .. "|r"

                if data.client == BNET_CLIENT_WOW then
                    if data.faction == "Alliance" then
                        btn.gameIcon:SetTexture(
                            "Interface\\FriendsFrame\\PlusManz-Alliance")
                    elseif data.faction == "Horde" then
                        btn.gameIcon:SetTexture(
                            "Interface\\FriendsFrame\\PlusManz-Horde")
                    else
                        btn.gameIcon:SetTexture(
                            "Interface\\FriendsFrame\\PlusManz-Horde")
                    end
                else
                    local texture = API.GetTitleIconTexture(data.client,
                                                            Enum.TitleIconVersion
                                                                .Small,
                                                            function(success,
                                                                     texture)
                        if success then
                            btn.gameIcon:SetTexture(texture)
                            if btn.gameIconSlot then btn.gameIconSlot:Show() else btn.gameIcon:Show() end
                        end
                    end)
                    if texture then
                        btn.gameIcon:SetTexture(texture)
                    end
                end
                if btn.gameIconSlot then btn.gameIconSlot:Show() else btn.gameIcon:Show() end

            else
                local levelColor = API.GetQuestDifficultyColor(data.level or 1)
                local levelHex = CreateColor(levelColor.r, levelColor.g,
                                             levelColor.b):GenerateHexColor()

                nameText = format("|c%s%s|r %s", levelHex, data.level or "??",
                                  FormatName(data.name, data.class))

                infoText = "|c" .. zoneColorHex .. (data.zone or "") .. "|r"

                -- 为游戏好友显示魔兽图标
                btn.gameIcon:SetTexture("Interface\\FriendsFrame\\PlusManz-Horde")
                if myFaction == "Alliance" then
                    btn.gameIcon:SetTexture(
                        "Interface\\FriendsFrame\\PlusManz-Alliance")
                end
                if btn.gameIconSlot then btn.gameIconSlot:Show() else btn.gameIcon:Show() end
            end

            btn.textLeft:SetText(nameText)
            btn.textRight:SetText(infoText)
        end

        btn.ybarOnClick = function(self, button)
            if button == "RightButton" then
                -- YUI:Debug("RightClick, " .. data.name, data.type)
                if type == "Friends" and data.type == "BNet" then
                    API.SendBNetTell(data.name)
                else
                    API.SendTell(data.name)
                end
            elseif button == "LeftButton" and FrameAPI.IsAltKeyDown() then
                if data.game == "WoW" or type == "Guild" or data.type == "WoW" then
                    if data.type == "BNet" then
                        -- FriendsFrame_InviteOrRequestToJoin(data.guid, data.bnetID)
                        FriendsFrame_InviteOrRequestToJoin(data.guid, data.gameAccountID)
                    else
                        API.InviteUnit(data.fullName)
                    end
                end
            end
        end
        if not btn.actionHost then
            YBar:CreateActionHost(btn, {
                secure = false,
                onEnter = function(_, owner)
                    if owner and owner.SetLineHover then owner:SetLineHover(true) end
                end,
                onLeave = function(_, owner)
                    if owner and owner.SetLineHover then owner:SetLineHover(false) end
                end,
            })
        elseif btn.actionHost then
            btn.actionHost.ybarOnEnter = function(_, owner)
                if owner and owner.SetLineHover then owner:SetLineHover(true) end
            end
            btn.actionHost.ybarOnLeave = function(_, owner)
                if owner and owner.SetLineHover then owner:SetLineHover(false) end
            end
        end
        if btn.actionHost then
            btn.actionHost:SetActions({
                right = {
                    kind = "custom",
                    onClick = function(_, _, owner)
                        owner:ybarOnClick("RightButton")
                    end,
                },
                altLeft = {
                    kind = "custom",
                    onClick = function(_, _, owner)
                        owner:ybarOnClick("LeftButton")
                    end,
                },
            })
        end

        contentHeight = contentHeight + CONFIG.BUTTON_HEIGHT
    end

    tooltip.content:SetSize(maxWidth, contentHeight)

    local chromeHeight = 65

    local totalHeight = 0
    if contentHeight + chromeHeight > CONFIG.SCROLL_HEIGHT then
        totalHeight = CONFIG.SCROLL_HEIGHT
    else
        totalHeight = contentHeight + chromeHeight
    end

    tooltip:SetSize(maxWidth + 20, totalHeight)
    tooltip:Show()
end

-- 按钮创建

local function CreateButton(parent, config)
    local db = EnsureModuleDB() or {}
    local btn = GUI2:CreateButtonFrame(parent)

    -- 保存配置引用
    btn.config = config

    -- 初始尺寸在 UpdateMicroMenu 中处理
    local size = DEFAULT_SIZE
    local iconSize = size + ICON_SIZE_PLUS

    btn:SetSize(iconSize, iconSize)

    -- name
    btn.name = config.name

    -- 纯文本按钮处理 (YUI设置, ElvUI, NDUI)
    if config.textOnly then
        -- Text only
        btn.text = YBar:CreateThemedText(btn, {
            text = config.text or config.name,
            fontPath = YBar:ResolveFontPath(db.font, DEFAULT_FONT),
            fontSize = size,
            fontFlags = "",
            colorKey = "color.ybar.text",
            fallback = { 1, 1, 1, 1 },
            shadow = true,
        })
        btn.text:SetPoint("CENTER", 0, 0)

        -- Underline
        btn.line = YBar:CreateThemedTexture(btn, {
            layer = "ARTWORK",
            colorKey = "color.ybar.micromenu.underline",
            fallback = { 1, 1, 1, 1 },
            colorMode = "solid",
        })
        btn.line:SetHeight(2)
        btn.line:SetPoint("TOPLEFT", btn.text, "BOTTOMLEFT", 0, 1)
        btn.line:SetPoint("TOPRIGHT", btn.text, "BOTTOMRIGHT", 0, 1)
    else
        btn.iconSlot, btn.icon = YBar:CreateIconSlot(btn, {
            size = iconSize,
            icon = config.icon,
            variant = "bare",
            shape = "rounded",
            padding = 0,
        })
        if btn.iconSlot then
            btn.iconSlot:SetPoint("LEFT", 0, 0)
            YBar:SetIconSlotTexture(btn.iconSlot, config.icon, config.atlas, config.texCoord)
        elseif btn.icon then
            btn.icon:SetPoint("LEFT", 0, 0)
            if config.atlas then
                btn.icon:SetAtlas(config.atlas)
                btn.icon:SetDesaturated(false)
                btn.icon:SetVertexColor(1, 1, 1)
                btn.icon:SetBlendMode("ADD")
            else
                btn.icon:SetTexture(config.icon)
                if config.texCoord then
                    btn.icon:SetTexCoord(unpack(config.texCoord))
                else
                    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            end
        end
    end

    -- 文本（数字）- 仅适用于带计数的标准按钮
    if config.showCount and config.name ~= "YUI设置" then
        btn.text = YBar:CreateThemedText(btn, {
            fontPath = YBar:ResolveFontPath(db.font, DEFAULT_FONT),
            fontSize = size,
            fontFlags = "",
            colorKey = "color.ybar.text",
            fallback = { 1, 1, 1, 1 },
            justifyH = "LEFT",
            shadow = true,
        })
        btn.text:SetPoint("LEFT", btn.iconSlot or btn.icon, "RIGHT", 2, 0)
        btn.text:SetJustifyH("LEFT")
    end

    -- 动态宽度更新函数
    function btn:UpdateWidth(skipLayoutUpdate)
        if not IsMicroMenuButtonReady(self) then return end

        local db = EnsureModuleDB() or {}
        local size = db.size or DEFAULT_SIZE
        local iconSize = size + ICON_SIZE_PLUS

        local width = iconSize

        if config.textOnly then
             -- Update Font Size
             if self.text then
                 self.text:SetFont(YBar:ResolveFontPath(db.font, DEFAULT_FONT), size, "")
                 width = self.text:GetStringWidth() + 8
             end
        else
            local showCount = true
            if db.showCount ~= nil then showCount = db.showCount end

            if config.showCount and self.text then
                if showCount then
                    self.text:Show()
                    local textWidth = self.text:GetStringWidth()
                    if textWidth > 0 then
                        width = width + textWidth + 4 -- 2px padding + 2px extra
                    end
                else
                    self.text:Hide()
                end
            end
        end

        -- 方案2：仅宽度变化时触发
        if math.abs(self:GetWidth() - width) < 0.1 then
            return
        end

        self:SetWidth(width)

        -- 通知父级更新布局
        if not skipLayoutUpdate and parent.NotifySizeChanged then
            parent:NotifySizeChanged()
        end
    end

    -- SetText 包装器以自动更新宽度
    function btn:SetCountText(text, skipLayoutUpdate)
        if not self.text then return end

        -- 防止无限循环：检查文本是否实际改变
        local currentText = self.text:GetText()
        if currentText == text or (text == nil and currentText == "") then
            return
        end

        self.text:SetText(text)
        self:UpdateWidth(skipLayoutUpdate)
    end

    -- 绑定按键
    local bindingKey = ""
    local action = BINDING_MAP[config.name]
    if action then
        if action == "YUI_TOGGLE" then
            bindingKey = "/yui"
        elseif action == "ELVUI_TOGGLE" then
            bindingKey = "/elvui"
        elseif action == "NDUI_TOGGLE" then
            bindingKey = "/ndui"
        else
            bindingKey = GetBindingKey(action)
        end
    end

    -- 点击动作
    -- btn:RegisterForClicks("AnyUp")
    btn.ybarOnClick = function(self, button)
        if not Module._runtimeAttached or Module._hasError or not IsMicroMenuButtonReady(self) then
            return
        end
        if not RefreshButtonAvailability(self) then return end
        if config.isEnabled and action then bindingKey = GetBindingKey(action) end

        if button == "LeftButton" then
            if FrameAPI.IsShiftKeyDown() then
                SafeCall(config.shiftLeftFunc, bindingKey, config.allowInCombat)
            else
                SafeCall(config.leftFunc, bindingKey, config.allowInCombat, self)
            end
        elseif button == "RightButton" then
            SafeCall(config.rightFunc, bindingKey, config.allowInCombat, self)
        end
    end

    -- GetWidth
    function btn:GetCalculatedWidth() return self:GetWidth() end

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        if not Module._runtimeAttached or Module._hasError or not IsMicroMenuButtonReady(self) then
            return
        end
        RefreshButtonAvailability(self)
        if config.isEnabled and action then bindingKey = GetBindingKey(action) end

        -- 悬停效果
        if self.iconSlot then
            YBar:SetIconSlotState(self.iconSlot, "hover")
        end
        local r, g, b, a = GetAccentColor()
        if self.icon then
            self.icon:SetVertexColor(r, g, b, a or 1)
            if config.atlas then
                self.icon:SetBlendMode("BLEND") -- 悬停时恢复正常颜色混合
            end
        end
        if self.line then
             YBar:SetThemedTextureColor(self.line, "color.baritem.hoverText", { 1, 0.82, 0, 1 })
             if self.text then YBar:SetThemedTextAccent(self.text) end
        end

        if config.useInteractiveTooltip then
            ShowInteractiveTooltip(self, config.useInteractiveTooltip)
            -- return -- Remove return to ensure YBar logic executes
        end

        local tooltipAnchor = "ANCHOR_TOP"
        local bar = Module.parent

        if not config.useInteractiveTooltip then -- Only show GameTooltip if not interactive
            if bar and bar:GetBottom() > GetScreenHeight() / 2 then
                tooltipAnchor = "ANCHOR_BOTTOM"
            end

            GameTooltip:SetOwner(self, tooltipAnchor)

            -- 计算颜色
            local r, g, b = CONFIG.HEADER_TEXT_COLOR.r, CONFIG.HEADER_TEXT_COLOR.g,
                            CONFIG.HEADER_TEXT_COLOR.b
            local headerColor = CreateColor(r, g, b)
            local headerHex = headerColor:GenerateHexColor()
            local white = "|cffffffff"
            local gold = "|c" .. headerHex

            -- Binding Key
            local bindingSuffix = ""
            if bindingKey and bindingKey ~= "" then
                local text = bindingKey
                if bindingKey ~= "/yui" then
                     text = API.GetBindingText(bindingKey)
                end
                if text and text ~= "" then
                    bindingSuffix = format("|cffffffff (%s)|r", text)
                end
            end

            -- 支持自定义 Tooltip 渲染
            if self.ybarActionEnabled == false then
                GameTooltip:AddLine(GetButtonDisplayName(config) .. bindingSuffix, r, g, b)
                if config.disabledTooltip then
                    GameTooltip:AddLine(config.disabledTooltip(), 1, 0.2, 0.2, true)
                end
            elseif config.tooltipFunc then
                config.tooltipFunc(GameTooltip)
            else
                GameTooltip:AddLine(GetButtonDisplayName(config) .. bindingSuffix, r, g, b)
                if config.infoFunc then
                    local info = config.infoFunc()
                    if info then
                        GameTooltip:AddLine(info, 1, 0.82, 0)
                    end
                end

                GameTooltip:AddLine(" ")

                if config.leftFunc then
                    GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.left_click"], gold,
                                               (config.leftName or "Open")))
                end
                if config.rightFunc then
                    GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.right_click"], gold,
                                               (config.rightName or LC["common.none"] or "None")))
                end
                if config.shiftLeftFunc then
                    GameTooltip:AddLine(format("%sShift + %s: |r%s%s|r", white, LC["common.left_click"],
                                               gold, (config.shiftLeftName or LC["common.none"] or "None")))
                end
                if config.altLeftName then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(format("|cff808080%s: %s|r", LC["common.alt_left_click"], config.altLeftName))
                end
            end

            GameTooltip:Show()
        end

        -- 触发 YBar 模块显示逻辑
        -- 使用 self.hostModuleFrame (即 module.frame)
        if YBar and YBar.OnModuleEnter and self.hostModuleFrame then
             YBar:OnModuleEnter(self.hostModuleFrame)
        end
    end)

    btn:SetScript("OnLeave", function(self)
        if Module._hasError or not IsMicroMenuButtonReady(self) then
            return
        end

        -- 重置悬停效果
        if self.iconSlot then
            YBar:SetIconSlotState(self.iconSlot, "normal")
        end
        if self.icon then
            self.icon:SetVertexColor(1, 1, 1)
            if config.atlas then
                self.icon:SetBlendMode("ADD")
            end
        end
        if self.line then
             YBar:SetThemedTextureColor(self.line, "color.ybar.micromenu.underline", { 1, 1, 1, 1 })
             if self.text then YBar:RestoreThemedTextColor(self.text, "color.ybar.text") end
        end

        if not config.useInteractiveTooltip then YUI.HideGameTooltip() end
        -- 如果使用交互式 Tooltip，不要在这里隐藏它。
        -- Tooltip 自己的 OnUpdate 脚本会处理当鼠标离开按钮和 tooltip 时的自动隐藏。

        -- 触发 YBar 模块显示逻辑
        -- 使用 self.hostModuleFrame (即 module.frame)
        if YBar and YBar.OnModuleLeave and self.hostModuleFrame then
             YBar:OnModuleLeave(self.hostModuleFrame)
        end
    end)

    -- 初始尺寸
    YBar:CreateActionHost(btn, {
        secure = false,
        onEnter = function(_, owner)
            local script = owner:GetScript("OnEnter")
            if script then script(owner) end
        end,
        onLeave = function(_, owner)
            local script = owner:GetScript("OnLeave")
            if script then script(owner) end
        end,
    })
    if btn.actionHost then
        btn.actionHost:SetActions({
            left = {
                kind = "custom",
                onClick = function(_, _, owner)
                    owner:ybarOnClick("LeftButton")
                end,
            },
            right = {
                kind = "custom",
                onClick = function(_, _, owner)
                    owner:ybarOnClick("RightButton")
                end,
            },
            shiftLeft = {
                kind = "custom",
                onClick = function(_, _, owner)
                    owner:ybarOnClick("LeftButton")
                end,
            },
        })
    end

    btn:UpdateWidth(true) -- 初始化时跳过布局更新以避免递归

    -- 附加更新方法
    -- if config.updateFunc then
    btn.Update = function(self, skipLayout)
        if config.updateFunc then
            config.updateFunc(self, skipLayout)
        end
        -- 同时更新宽度以防文本改变
        self:UpdateWidth(skipLayout)
    end
    -- end

    return btn
end

-- 按钮定义
local function GetButtons()
    local MSTONE_NAME = YUI.F:GetGradientText(T("meetingstone.tooltip.title", "集合石"), {0.84, 0.41, 1}, {0.64, 0.21, 0.93})
    local buttons = {
        {
            name = "游戏菜单",
            displayName = T("micromenu.button.game_menu", "游戏菜单"),
            icon = ICON_PATH .. "MainMenu.png",
            leftName = T("micromenu.action.main_menu", "主菜单"),
            leftFunc = function()
                FrameAPI.ToggleGameMenu()
            end,
            rightName = T("micromenu.action.reload_ui", "重载界面"),
            rightFunc = function() FrameAPI.ReloadUI() end
        }, {
            name = "公会与社区",
            displayName = T("micromenu.button.guild_communities", "公会与社区"),
            icon = ICON_PATH .. "Guild.png",
            -- TODO FIXME
            -- icon = Assets:Core("images\\icons\\ycolor\\settings_256.png"),
            showCount = true,
            useInteractiveTooltip = "Guild",
            leftName = T("micromenu.action.guild_panel", "公会面板"),
            leftFunc = function() API.ToggleGuildFrame() end,
            updateFunc = function(btn, skipLayoutUpdate)
                local _, numOnline, numOnlineAndMobile =
                    API.GetNumGuildMembers()
                local effectiveOnline = (numOnlineAndMobile and
                                            numOnlineAndMobile > 0) and
                                            numOnlineAndMobile or numOnline
                btn:SetCountText(effectiveOnline or "", skipLayoutUpdate)
            end,
            events = {"GUILD_ROSTER_UPDATE"}
        }, {
            name = "好友",
            displayName = T("micromenu.button.friends", "好友"),
            icon = ICON_PATH .. "Social.png",
            showCount = true,
            useInteractiveTooltip = "Friends",
            leftName = T("micromenu.action.friends_list", "好友列表"),
            leftFunc = function() API.ToggleFriendsFrame() end,
            updateFunc = function(btn, skipLayoutUpdate)
                local onlineFriends = API.GetNumOnlineFriends()
                local _, onlineBNet = API.BNGetNumFriends()

                btn:SetCountText(onlineFriends + onlineBNet, skipLayoutUpdate)
            end,
            events = {
                "FRIENDLIST_UPDATE", "BN_FRIEND_LIST_SIZE_CHANGED",
                "BN_FRIEND_INFO_CHANGED", "BN_CONNECTED", "BN_DISCONNECTED",
                "YUI_WORLD_READY"
            }
        }, {
            name = "队伍查找器",
            displayName = T("micromenu.button.group_finder", "队伍查找器"),
            icon = ICON_PATH .. "LFD.png",
            leftName = T("micromenu.action.finder", "查找器"),
            leftFunc = function() FrameAPI.TogglePVEFrame() end,
            rightName = MSTONE_NAME,
            rightFunc = function()
                if not (YBar and YBar.OpenMeetingHorn and YBar:OpenMeetingHorn()) then
                    YUI:Print(T("micromenu.message.meeting_stone_missing", "集合石插件可能未加载"))
                end
            end
        }, {
            name = "角色",
            displayName = T("micromenu.button.character", "角色"),
            icon = ICON_PATH .. "Character.png",
            leftName = T("micromenu.action.character_panel", "角色面板"),
            leftFunc = function()
                FrameAPI.ToggleCharacter("PaperDollFrame")
            end
        }, {
            name = "法术书和专业",
            displayName = T("micromenu.button.spellbook_professions", "法术书和专业"),
            icon = ICON_PATH .. "PlayerSpells.png",
            leftName = T("micromenu.action.spellbook", "法术书"),
            leftFunc = function() FrameAPI.ToggleSpellBook() end,
            rightName = T("micromenu.action.professions", "专业技能书"),
            rightFunc = function() ToggleProfessionsBook() end
        }, {
            name = "成就",
            displayName = T("micromenu.button.achievements", "成就"),
            icon = ICON_PATH .. "Achievement.png",
            leftName = T("micromenu.action.achievements", "成就"),
            leftFunc = function() FrameAPI.ToggleAchievementFrame() end
        }, {
            name = "传承",
            displayName = T("micromenu.button.legacy", "传承"),
            icon = ICON_PATH .. "Legacy.png",
            texCoord = {0, 1, 0, 1},
            leftName = T("micromenu.button.legacy", "传承"),
            leftFunc = function() FrameAPI.ToggleLegacySystemUI() end,
            initCondition = function() return YUI.IsForever end,
            isEnabled = function() return FrameAPI.IsLegacySystemUnlocked() end,
            disabledTooltip = function()
                return LEGACY_MICRO_BUTTON_LOCKED_TOOLTIP or
                    T("micromenu.legacy.locked", "首个角色达到25级后解锁此功能。")
            end,
            updateFunc = RefreshButtonAvailability,
            events = {"YUI_WORLD_READY", "ACHIEVEMENT_EARNED", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED"},
        }, {
            name = "任务",
            displayName = T("micromenu.button.quests", "任务"),
            icon = ICON_PATH .. "QuestLog.png",
            leftName = T("micromenu.action.quest_log", "任务日志"),
            leftFunc = function() FrameAPI.ToggleQuestLog() end
        }, {
            name = "藏品",
            displayName = T("micromenu.button.collections", "藏品"),
            icon = ICON_PATH .. "Collections.png",
            leftName = T("micromenu.action.warband_collections", "战团藏品"),
            leftFunc = function() FrameAPI.ToggleCollectionsJournal() end,
            rightName = T("micromenu.action.random_favorite_mount", "随机偏好坐骑"),
            rightFunc = function() C_MountJournal.SummonByID(0) end
        }, {
            name = "冒险指南",
            displayName = T("micromenu.button.adventure_guide", "冒险指南"),
            icon = ICON_PATH .. "EJ.png",
            leftName = T("micromenu.action.adventure_guide", "冒险指南"),
            leftFunc = function() FrameAPI.ToggleEncounterJournal() end,
            rightName = T("micromenu.action.great_vault", "宏伟宝库"),
            rightFunc = function()
                if not WeeklyRewards_ShowUI then
                     SystemAPI.LoadAddOn("Blizzard_WeeklyRewards")
                end

                if WeeklyRewardsFrame and WeeklyRewardsFrame:IsShown() then
                    WeeklyRewardsFrame:Hide()
                elseif WeeklyRewards_ShowUI then
                     WeeklyRewards_ShowUI()
                end
            end,
            initCondition = function() return YUI.IsRetail end,
        }, {
            name = "家宅", -- Housing placeholder
            displayName = T("micromenu.button.housing", "家宅"),
            icon = ICON_PATH .. "Housing.png",
            leftName = T("micromenu.action.housing", "家宅"),
            leftFunc = function()
                if HousingFramesUtil and
                    HousingFramesUtil.ToggleHousingDashboard then
                    HousingFramesUtil.ToggleHousingDashboard()
                end
            end,
            initCondition = function() return YUI.IsRetail end,
        }, {
            name = "Volume",
            displayName = T("micromenu.volume.name", "音量"),
            icon = VOLUME_ICON,
            leftName = T("micromenu.volume.action.open_panel", "快捷音量"),
            rightName = T("micromenu.volume.action.toggle_mute", "静音/恢复"),
            allowInCombat = true,
            leftFunc = function(btn)
                ToggleVolumePanel(btn)
            end,
            rightFunc = function(btn)
                SetSoundEnabled(not IsSoundEnabled())
                RefreshVolumeButton(btn)
                RefreshVolumePanel()
            end,
            updateFunc = function(btn)
                RefreshVolumeButton(btn)
            end,
            events = {"CVAR_UPDATE", "YUI_WORLD_READY"}
        }, {
            name = "PVP",
            displayName = "PVP",
            -- atlas = API.UnitFactionGroup("player") == "Alliance" and "communities-create-button-wow-alliance" or "communities-create-button-wow-horde",
            textOnly = true,
            text = "PVP",
            leftName = T("micromenu.action.pvp", "PVP"),
            leftFunc = function()
                FrameAPI.TogglePVPUI()
            end,
            initCondition = function() return YUI.IsWrath end,
        }, {
            name = "ElvUI",
            displayName = "ElvUI",
            textOnly = true,
            text = "ElvUI",
            leftName = T("micromenu.action.elvui_settings", "ElvUI 设置"),
            leftFunc = function() API.RunSlashCmd("/elvui") end,
            initCondition = function() return SystemAPI.IsAddOnLoaded("ElvUI") end,
            defaultOff = true
        }, {
            name = "NDUI",
            displayName = "NDUI",
            textOnly = true,
            text = "NDUI",
            leftName = T("micromenu.action.ndui_console", "NDUI 控制台"),
            leftFunc = function()
                if NDuiGUI then
                    if NDuiGUI:IsShown() then
                        NDuiGUI:Hide()
                    else
                        NDuiGUI:Show()
                    end
                else
                    if not GameMenuFrame:IsShown() then
                        FrameAPI.ToggleGameMenu()
                    end

                    local found = false
                    if GameMenuFrame.buttonPool then
                        for button in GameMenuFrame.buttonPool:EnumerateActive() do
                            if button:GetText() and string.find(button:GetText(), "NDui") then
                                button:Click()
                                found = true
                                break
                            end
                        end
                    end

                    if not found then
                        if GameMenuFrame:IsShown() then
                            FrameAPI.ToggleGameMenu()
                        end
                        print(T("micromenu.message.ndui_settings_missing", "|cff0080ffNDui|r: 未在游戏菜单中找到设置按钮，请手动打开 ESC 菜单。"))
                    end
                end
            end,
            initCondition = function() return SystemAPI.IsAddOnLoaded("NDui") end,
            defaultOff = true
        }, {
            name = "YUI设置",
            displayName = "YUI",
            textOnly = true, -- Text only mode
            text = "YUI",
            icon = nil, -- Custom handling
            leftName = T("micromenu.action.yui_settings_panel", "YUI设置面板"),
            altLeftName = T("micromenu.action.open_micromenu_settings", "打开微菜单设置"),
            leftFunc = function()
                if FrameAPI.IsAltKeyDown() then
                    if YUI.OpenYBarModuleSettings then
                        YUI:OpenYBarModuleSettings("MicroMenu")
                    end
                elseif YUI.Settings and YUI.Settings.Toggle then
                    YUI.Settings:Toggle()
                end
            end,
            initCondition = IsYUISuiteLoaded,
        }
    }
    return buttons
end

function Module:UpdateMicroMenu(skipLayout)
    if not IsMicroMenuReady(self.frame) then return end

    local db = EnsureModuleDB()
    if not db then return end
    local size = db.size or DEFAULT_SIZE
    local iconSize = size + ICON_SIZE_PLUS
    local spacing = db.spacing or DEFAULT_SPACING
    local font = db.font
    local fontPath = YBar:ResolveFontPath(font, DEFAULT_FONT)

    -- New settings
    local widthMode = db.widthMode or "AUTO"
    local fixedWidth = db.fixedWidth or 300
    local alignment = db.alignment or "CENTER"

    -- 1. Calculate total visible content width
    local visibleButtons = {}
    local totalContentWidth = 0

    for _, btn in ipairs(self.buttons) do
        local isEnabled = true
        local userSetting = db.buttons[btn.name]

        if userSetting == nil then
            if btn.config.defaultOff then isEnabled = false end
        elseif userSetting == false then
            isEnabled = false
        end

        if isEnabled then
            table.insert(visibleButtons, btn)

            btn:Show()
            if btn.config.isEnabled then RefreshButtonAvailability(btn) end

            -- 更新样式
            btn:SetHeight(iconSize)

            if btn.iconSlot then
                btn.iconSlot:SetSize(iconSize, iconSize)
                if btn.iconSlot.UpdateGUI2PixelScale then
                    btn.iconSlot:UpdateGUI2PixelScale()
                end
            elseif btn.icon then
                btn.icon:SetSize(iconSize, iconSize)
            end

            if btn.text then
                local globalDB = GetYBarDB() or {}
                local fontFlag = globalDB.fontFlags or (globalDB.fontOutline and "OUTLINE" or "")

                btn.text:SetFont(fontPath, size, fontFlag)

                if globalDB.fontShadow then
                    btn.text:SetShadowColor(0, 0, 0, 1)
                    btn.text:SetShadowOffset(1, -1)
                else
                    btn.text:SetShadowOffset(0, 0)
                end
            end

            -- 更新宽度
            btn:UpdateWidth(true)

            totalContentWidth = totalContentWidth + btn:GetWidth() + spacing
        else
            btn:Hide()
        end
    end

    self:RefreshAudioSyncRuntime()

    if #visibleButtons > 0 then
        totalContentWidth = totalContentWidth - spacing
    else
        totalContentWidth = 10
    end

    -- 2. Determine container width
    local containerWidth = totalContentWidth
    if widthMode == "FIXED" then
        containerWidth = fixedWidth
    end

    -- 3. Calculate start offset
    local startOffset = 0
    if widthMode == "FIXED" then
        if alignment == "CENTER" then
            startOffset = (containerWidth - totalContentWidth) / 2
        elseif alignment == "RIGHT" then
            startOffset = containerWidth - totalContentWidth
        end
    end

    -- 4. Position buttons
    local prev = nil
    for i, btn in ipairs(visibleButtons) do
        btn:ClearAllPoints()
        if i == 1 then
            btn:SetPoint("LEFT", self.frame, "LEFT", startOffset, 0)
        else
            btn:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
        end
        prev = btn
    end

    if self.frame then
        if not SecurityAPI.InCombatLockdown() then
            self.frame:SetWidth(containerWidth)
            self.frame:SetHeight(iconSize)
        end

        -- 容器更新布局逻辑
        if self.frame.UpdateLayout then
            -- 布局更新逻辑
        end
    end

    if not skipLayout and YBar and YBar.UpdateLayout then
        YBar:UpdateLayout()
    end
end

function Module:CreateBarItem(parent)
    local container = YBar:CreateBarItem(parent, {
        variant = "bare",
        width = 10,
        height = DEFAULT_SIZE + ICON_SIZE_PLUS,
        showIcon = false,
        text = false,
        value = false,
    })

    local buttons = GetButtons()
    local prev = nil
    local totalWidth = 0

    self.buttons = {}

    -- 容器布局更新
    function container:UpdateLayout()
        if not IsMicroMenuReady(self) then return end
        Module:UpdateMicroMenu(true)
    end

    function container:NotifySizeChanged()
        if Module._hasError or self ~= Module.frame or self.ybarErrorPlaceholder then return end

        -- 方案1：防抖动
        if self.layoutPending then return end
        self.layoutPending = true
        C_Timer.After(1.0, function()
            if not Module._runtimeAttached or Module._hasError or self ~= Module.frame or self.ybarErrorPlaceholder then
                self.layoutPending = false
                return
            end

            self.layoutPending = false
            if YUI.YBar and YUI.YBar.UpdateLayout then
                YUI.YBar:UpdateLayout()
            end
        end)
    end

    for _, config in ipairs(buttons) do
        -- Check init condition
        if not config.initCondition or config.initCondition() then
            local btn = CreateButton(container, config)
            -- 定位在 UpdateMicroMenu 中处理

            if config.events then
                btn.OnYBarMicroMenuEvent = function(self, event)
                    if not Module._runtimeAttached or Module._hasError or not IsMicroMenuButtonReady(self) then
                        return
                    end

                    -- 避免处理隐藏或无效框架的事件
                    if not self:IsVisible() then return end

                    -- 节流更新以避免频繁重算布局
                    if not self.updatePending then
                        self.updatePending = true
                        C_Timer.After(1.0, function()
                            if not Module._runtimeAttached or Module._hasError or not IsMicroMenuButtonReady(self) then
                                self.updatePending = false
                                return
                            end

                            if self:IsVisible() then
                                 -- Update data
                                 if self.Update then self:Update(false) end
                            end
                            self.updatePending = false
                        end)
                    end
                end

                -- 初始更新
                if btn.Update then
                     btn:Update(true)
                end
            end

            table.insert(self.buttons, btn)
        end
    end

    -- 初始布局
    container.buttons = self.buttons

    self.frame = container
    if self._runtimeAttached or (YBar and YBar.IsSubModuleEnabled and YBar:IsSubModuleEnabled(self.name)) then
        self:RegisterButtonEvents()
    end

    self:UpdateBarItem(container, parent)

    return container
end

function Module:UpdateBarItem(frame, parent)
    if parent then self.parent = parent end
    if not frame then frame = self.frame end
    if not IsMicroMenuReady(frame) then return end

    -- 请求数据刷新（带节流）
    if not self.lastGuildRosterUpdate or (CombatAPI.GetTime() - self.lastGuildRosterUpdate > 15) then
        API.GuildRoster()
        self.lastGuildRosterUpdate = CombatAPI.GetTime()
    end

    for _, btn in ipairs(self.buttons) do
        btn.parent = self.parent
        btn.hostModuleFrame = self.frame -- 绑定模块框架用于 YBar 事件
        if btn.Update and btn:IsVisible() then
            btn:Update(false) -- 强制立即更新
        end
    end

    self:UpdateMicroMenu(true)
end

function Module:UpdateButtonsPositions()
    self:UpdateMicroMenu(true)
end

function Module:GetWidth()
    if IsMicroMenuReady(self.frame) then
        return self.frame:GetWidth()
    end
    return 10
end

function Module:GetOptions()
    local S = YUI.Settings
    local LSM = LibStub("LibSharedMedia-3.0")

    local fontList = LSM:HashTable("font")
    local fontOptions = {}
    local defaultFont = nil
    for name, path in pairs(fontList) do
        table.insert(fontOptions, { text = name, value = path })
        if name == "默认" then defaultFont = path end
    end
    table.sort(fontOptions, function(a, b) return a.text < b.text end)

    -- Helper to safely access/set DB
    local function GetDB()
        local ybarDB = GetYBarDB()
        if type(ybarDB) ~= "table" then
            return {}
        end
        if not ybarDB.MicroMenu then ybarDB.MicroMenu = {} end
        return ybarDB.MicroMenu
    end

    local options = {

        {
            type = "dropdown",
            label = LC["common.font"] or "Font",
            width = 220,
            default = defaultFont,
            options = fontOptions,
            get = function() return GetDB().font or defaultFont end,
            set = function(val)
                GetDB().font = val
                Module:UpdateMicroMenu()
            end
        },
        {
            type = "slider",
            label = LC["common.size"] or "Size",
            inline = true,
            inputWidth = 56,
            width = 220,
            min = 10, max = 32, step = 1,
            get = function() return GetDB().size or DEFAULT_SIZE end,
            set = function(val)
                GetDB().size = val
                Module:UpdateMicroMenu()
            end
        },
        {
            type = "slider",
            label = T("ybar.settings.option.icon_spacing", "Icon Spacing"),
            inline = true,
            inputWidth = 56,
            width = 220,
            min = -5, max = 20, step = 1,
            get = function() return GetDB().spacing or DEFAULT_SPACING end,
            set = function(val)
                GetDB().spacing = val
                Module:UpdateMicroMenu()
            end
        },
        {
            type = "divider",
            label = T("ybar.settings.section.width_mode", "Width Mode"),
            width = 400,
            alignLeft = true,
        },
        {
            type = "dropdown",
            label = T("ybar.settings.option.width_mode", "Width Mode"),
            width = 220,
            options = {
                { text = T("ybar.settings.option.auto", "Auto"), value = "AUTO" },
                { text = T("ybar.settings.option.fixed", "Fixed"), value = "FIXED" },
            },
            default = "AUTO",
            get = function() return GetDB().widthMode or "AUTO" end,
            set = function(val)
                GetDB().widthMode = val
                Module:UpdateMicroMenu()

                -- Refresh settings UI
                if YUI.YBar and YUI.YBar.SettingsButtons then
                    local btn = YUI.YBar.SettingsButtons["MicroMenu"]
                    if btn and btn:IsVisible() and btn.isSelected then
                        btn:Click()
                    end
                end
            end
        },
        {
            type = "slider",
            label = T("ybar.settings.option.fixed_width", "Fixed Width"),
            inline = true,
            inputWidth = 56,
            width = 220,
            min = 100, max = 1000, step = 1,
            default = 300,
            hidden = function() return (GetDB().widthMode or "AUTO") ~= "FIXED" end,
            get = function() return GetDB().fixedWidth or 300 end,
            set = function(val)
                GetDB().fixedWidth = val
                Module:UpdateMicroMenu()
            end
        },
        {
            type = "dropdown",
            label = T("ybar.settings.option.alignment", "Alignment"),
            width = 220,
            options = {
                { text = LC["common.left"] or "Left", value = "LEFT" },
                { text = LC["common.center"] or "Center", value = "CENTER" },
                { text = LC["common.right"] or "Right", value = "RIGHT" },
            },
            default = "CENTER",
            hidden = function() return (GetDB().widthMode or "AUTO") ~= "FIXED" end,
            get = function() return GetDB().alignment or "CENTER" end,
            set = function(val)
                GetDB().alignment = val
                Module:UpdateMicroMenu()
            end
        },
        {
            type = "divider",
            label = T("ybar.settings.section.menu_buttons", "Menu Buttons"),
            width = 400,
            alignLeft = true,
        }
    }

    -- 添加每个按钮的开关
    local buttons = GetButtons()
    local currentRow
    local itemIndex = 0
    for _, config in ipairs(buttons) do
        -- Skip if initCondition not met
        if not config.initCondition or config.initCondition() then
            if itemIndex % 3 == 0 then
                currentRow = { type = "row", children = {} }
                table.insert(options, currentRow)
            end

            table.insert(currentRow.children, {
                type = "checkbox",
                label = GetButtonDisplayName(config),
                width = 120, -- Compact width
                get = function()
                    local db = GetDB()
                    if db.buttons and db.buttons[config.name] ~= nil then
                        return db.buttons[config.name]
                    end
                    return not config.defaultOff -- Handle defaultOff
                end,
                set = function(val)
                    local db = GetDB()
                    if not db.buttons then db.buttons = {} end
                    db.buttons[config.name] = val
                    Module:UpdateMicroMenu()
                end
            })
            itemIndex = itemIndex + 1
        end
    end

    table.insert(options, {
        type = "checkbox",
        label = T("micromenu.option.show_social_counts", "Show guild/friend counts"),
        width = 200,
        get = function()
            local val = GetDB().showCount
            if val ~= nil then return val end
            return true
        end,
        set = function(val)
            GetDB().showCount = val
            Module:UpdateMicroMenu()
        end
    })

    return options
end

YBar:RegisterModule(Module, {
    id = "ybar.micromenu",
    parent = "ybar",
    product = "ybar",
    scope = "ybar",
    dependencies = {"ybar", "core.api", "gui"},
    defaultEnabled = true,
})

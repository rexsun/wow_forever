local _, YUI = ...
local Assets = YUI.Assets

YUI.ELV = {}

local E = YUI.ELV

E.isInitialized = false

-- ElvUI tab frames include transparent side padding; negative spacing keeps visible tabs continuous.
local CHARACTER_TAB_GAP = -20
local characterTabHooksReady = false
local characterTabEventFrame

local function SafePoint(frame, ...)
    if not frame then return end
    if type(frame.Point) == "function" then
        frame:Point(...)
    elseif type(frame.SetPoint) == "function" then
        frame:SetPoint(...)
    end
end

local function AddCharacterTab(tabs, tab)
    if tab then
        tabs[#tabs + 1] = tab
    end
end

local function FixCharacterTabs()
    local CharacterFrame = _G.CharacterFrame
    if not CharacterFrame then
        return
    end

    if not _G.CharacterFrameTab1 or not _G.CharacterFrameTab3 then
        return
    end

    local tabs = {}
    AddCharacterTab(tabs, _G.CharacterFrameTab1)
    if HasPetUI and HasPetUI() then
        AddCharacterTab(tabs, _G.CharacterFrameTab2)
    end
    AddCharacterTab(tabs, _G.CharacterFrameTab3)
    AddCharacterTab(tabs, _G.CharacterFrameTab4)
    AddCharacterTab(tabs, _G.CharacterFrameTab5)

    local lastTab
    for index, tab in ipairs(tabs) do
        tab:ClearAllPoints()
        if index == 1 then
            SafePoint(tab, "TOPLEFT", CharacterFrame, "BOTTOMLEFT", 1, 76)
        else
            SafePoint(tab, "TOPLEFT", lastTab, "TOPRIGHT", CHARACTER_TAB_GAP, 0)
        end
        lastTab = tab
    end
end

local function QueueCharacterTabFix()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            FixCharacterTabs()
        end)
    else
        FixCharacterTabs()
    end
end

local function SafeHookGlobalFunction(name, callback)
    if type(hooksecurefunc) ~= "function" or type(_G[name]) ~= "function" then
        return false
    end

    local ok = pcall(hooksecurefunc, name, callback)
    if not ok then
        return false
    end

    return true
end

local function HookCharacterTabFixes()
    if characterTabHooksReady then
        return
    end
    characterTabHooksReady = true

    if _G.CharacterFrame and _G.CharacterFrame.HookScript then
        _G.CharacterFrame:HookScript("OnShow", function()
            FixCharacterTabs()
        end)
    end

    SafeHookGlobalFunction("PetPaperDollFrame_UpdateIsAvailable", function()
        FixCharacterTabs()
    end)
    SafeHookGlobalFunction("PetPaperDollFrame_UpdateTabs", function()
        FixCharacterTabs()
    end)

    characterTabEventFrame = CreateFrame and CreateFrame("Frame")
    if characterTabEventFrame then
        characterTabEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        characterTabEventFrame:RegisterEvent("PET_UI_UPDATE")
        characterTabEventFrame:RegisterEvent("PET_BAR_UPDATE")
        characterTabEventFrame:RegisterEvent("PET_UI_CLOSE")
        characterTabEventFrame:RegisterEvent("UNIT_PET")
        characterTabEventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
        characterTabEventFrame:SetScript("OnEvent", function(_, event, unit)
            if event == "UNIT_PET" and unit ~= "player" then
                return
            end
            QueueCharacterTabFix()
        end)
    end

    FixCharacterTabs()
    if C_Timer and C_Timer.After then
        C_Timer.After(1, function()
            FixCharacterTabs()
        end)
    end
end

function E:Init()
    self:InitVehicleLeaveButton()
    self.isInitialized = true
    YUI.Event:Emit("ElvUI_Initialized")
    E:GetProfile()
    YUI:Debug("ElvUI.init() ... done", E.currentProfile)

    -- Fix Bugs

    -- 修复：武器附魔一直显示
    if _G["TemporaryEnchantFrame"] then _G["TemporaryEnchantFrame"]:Hide() end

    -- 修复：宠物Tab和声望Tab的重合
    -- ElvUI Wrath 只在皮肤初始化时重排一次；这里在宠物状态和角色面板显示时重复兜底。
    HookCharacterTabFixes()

    -- 修复2026-04-09
    local ElvUI = _G.ElvUI
    local elvE = ElvUI and unpack(ElvUI)
    if elvE and elvE.private and elvE.private.actionbar and elvE.private.actionbar.enable then
        if _G["SocialsMicroButton"] then
            _G["SocialsMicroButton"]:Hide()
        end

        if _G["PVPMicroButton"] then
            _G["PVPMicroButton"]:Hide()
        end

        if _G["LFGMicroButton"] then
            _G["LFGMicroButton"]:Hide()
        end

        if _G["MicroMenu"] then
            _G["MicroMenu"]:Hide()
        end
    end
end

-- 美化ElvUI丑陋的离开载具
function E:InitVehicleLeaveButton()
    if not _G["MainMenuBarVehicleLeaveButton"] then return end

    local btn = _G["MainMenuBarVehicleLeaveButton"]
    local icon = Assets:Core("images\\icons\\leave_vehicle.tga")

    local normal = btn:GetNormalTexture()

    if normal then
        normal:SetTexture(icon)
        normal:ClearAllPoints()
        normal:SetPoint("CENTER")
    end

    local pushed = btn:GetPushedTexture()
    if pushed then
        pushed:SetTexture(icon)
        pushed:ClearAllPoints()
        pushed:SetPoint("CENTER")
    end

    local disabled = btn:GetDisabledTexture()

    if disabled then
        disabled:SetTexture(icon)
        disabled:ClearAllPoints()
        disabled:SetPoint("CENTER")
    end

    local SCALE = 1

    btn:HookScript("OnSizeChanged", function(self, width, height)
        local w, h = width * SCALE, height * SCALE
        if normal then
            normal:SetSize(w, h)
            normal:SetTexCoord(0, 1, 0, 1)
        end
        if pushed then
            pushed:SetSize(w, h)
            pushed:SetTexCoord(0, 1, 0, 1)
        end
        if disabled then
            disabled:SetSize(w, h)
            disabled:SetTexCoord(0, 1, 0, 1)
        end
    end)
end

function E:GetProfile()
    if not _G.ElvUI then return end
    local core = _G.ElvUI[1]
    if not core or not core.data then return end
    if type(core.data.GetCurrentProfile) ~= "function" then return end
    local profile = core.data:GetCurrentProfile()
    E.currentProfile = profile
    return profile
end

function E:SetProfile(profile)
    if not _G.ElvUI then return end
    local core = _G.ElvUI[1]
    if not core or not core.data then return end

    -- 获取当前实际配置，防止本地缓存 E.currentProfile 过期
    local current
    if type(core.data.GetCurrentProfile) == "function" then
        current = core.data:GetCurrentProfile()
    end

    -- 判断是否是当前配置
    if current == profile then
        E.currentProfile = current
        return
    end

    -- AceDB-3.0 使用 SetProfile
    if type(core.data.SetProfile) == "function" then
        core.data:SetProfile(profile)
    elseif type(core.data.SetCurrentProfile) == "function" then
        core.data:SetCurrentProfile(profile)
    else
        return
    end

    E.currentProfile = profile
end

-- 获取玩家框架宽度
function E:GetPlayerWidth() return ElvUF_Player and ElvUF_Player:GetWidth() end

-- 获取玩家框架x偏移 (从Mover获取配置的偏移量)
function E:GetPlayerXOffset()
    local mover = _G["ElvUF_PlayerMover"]
    if mover then
        local _, _, _, x, _ = mover:GetPoint()
        return x
    end
    return 0
end

-- 特殊字体的原始注册挂钩可能被共享库升级替换，在适配侧按需补齐刷新。
do
    local FONT_EVENT = "LibSharedMedia_Registered"
    local FontRefresh = {}

    local function GetSharedMedia()
        local engine = _G.ElvUI
        local core = type(engine) == "table" and engine[1]
        if type(core) ~= "table" then return end
        local libs = core.Libs
        local media = type(libs) == "table" and libs.LSM
        if type(media) == "table" then return core, media end
    end

    local function RefreshCombatFont(key, beforeWorld)
        local core, media = GetSharedMedia()
        -- 加载期已有 private 配置即可刷新；等待 Initialized 可能错过原生字体的启动阶段。
        if not core or (not beforeWorld and core.Initialized ~= true) then return false end
        local private = core.private
        local general = type(private) == "table" and private.general
        if type(general) ~= "table" or general.replaceCombatFont ~= true then return false end
        local selected = general.dmgfont
        if type(selected) ~= "string" or selected == "" or (key and key ~= selected) then return false end
        if type(media.IsValid) ~= "function" or type(media.Fetch) ~= "function" then return false end
        if media:IsValid("font", selected) ~= true then return false end
        local path = media:Fetch("font", selected, true)
        if type(path) ~= "string" or path == "" or path == _G.DAMAGE_TEXT_FONT then return false end
        if type(core.UpdateBlizzardSpecialFonts) ~= "function" then return false end
        core:UpdateBlizzardSpecialFonts()
        return _G.DAMAGE_TEXT_FONT == path
    end

    local function RegisterFontCallback(owner)
        local _, media = GetSharedMedia()
        if not media or type(media.RegisterCallback) ~= "function" or type(media.UnregisterCallback) ~= "function" then return end
        -- 提前记录来源，注册中途抛错时停用仍能尝试清理。
        owner.sharedMedia = media
        media.RegisterCallback(owner, FONT_EVENT, "OnFontRegistered")
    end

    local function UnregisterFontCallback(owner)
        local media = owner.sharedMedia
        owner.sharedMedia = nil
        if type(media) == "table" and type(media.UnregisterCallback) == "function" then
            media.UnregisterCallback(owner, FONT_EVENT)
        end
    end

    function FontRefresh:Refresh(key, beforeWorld)
        if self.refreshing or (not beforeWorld and (not self.enabled or not self.worldReady)) then return end
        -- 整个外部边界受保护，包含字段访问、共享库查询和刷新方法内部。
        self.refreshing = true
        local ok, refreshed = pcall(RefreshCombatFont, key, beforeWorld)
        self.refreshing = false
        self.lastError = not ok and refreshed or nil
        if beforeWorld then self.startupError = self.lastError end
        if ok and refreshed then
            self.refreshCount = (self.refreshCount or 0) + 1
            self.lastPhase = beforeWorld and "startup" or "world"
            if beforeWorld then self.startupRefreshCount = (self.startupRefreshCount or 0) + 1 end
        end
    end

    function FontRefresh:OnRegister()
        -- 本组件晚于本包字体注册、早于 PLAYER_LOGIN 加载，先纠正启动时的回退路径。
        self:Refresh(nil, true)
    end

    function FontRefresh:OnFontRegistered(_, mediaType, key)
        if mediaType == "font" and type(key) == "string" then
            self:Refresh(key)
        end
    end

    function FontRefresh:OnWorldReady()
        if not self.enabled or self.worldReady then return end
        self.worldReady = true
        local ok, err = pcall(RegisterFontCallback, self)
        self.registrationError = not ok and err or nil
        self:Refresh()
    end

    function FontRefresh:OnEnable()
        if self.enabled then return end
        self.enabled = true
        if YUI.Lifecycle and YUI.Lifecycle:IsReady("YUI_WORLD_READY") then
            self:OnWorldReady()
        else
            -- 覆盖组件加载后、登录前才注册所选字体的情况。
            self:Refresh(nil, true)
            YUI.Event:Once("YUI_WORLD_READY", "OnWorldReady", self)
        end
    end

    function FontRefresh:OnDisable()
        self.enabled = false
        self.worldReady = false
        YUI.Event:OffOwner(self)
        pcall(UnregisterFontCallback, self)
    end

    if YUI.IsWrath and YUI.Module and YUI.Event then
        YUI.Module:Register({
            id = "WrathElvUI.FontRefresh",
            owner = FontRefresh,
            dependencies = { "core.event" },
            OnRegister = "OnRegister",
            OnEnable = "OnEnable",
            OnDisable = "OnDisable",
        })
    end
end

E:Init()

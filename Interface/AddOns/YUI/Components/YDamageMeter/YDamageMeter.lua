local _, YUI = ...
local LSM = LibStub("LibSharedMedia-3.0")
local Icons = YUI.API and YUI.API.Icons
local External = YUI.API and YUI.API.External
local LC = YUI.Locale and YUI.Locale:Get("Core")
local L = YUI.Locale and YUI.Locale:Get("YDamageMeter")
local ICON_SCOPE_ID = "ydamage_meter"

local function T(key, fallback)
    local value = L and L[key]
    if value == nil or value == key then return fallback or key end
    return value
end

if Icons and Icons.RegisterIconScope then
    Icons.RegisterIconScope({
        id = ICON_SCOPE_ID,
        name = T("feature.name", "YUI 伤害统计"),
        nameKey = "settings.appearance.scope.ydamage_meter",
        tooltipKey = "settings.appearance.scope.ydamage_meter.tooltip",
        order = 10,
        default = true,
    })
end

YUI.YDamageMeter = {}
local YDM = YUI.YDamageMeter
YDM.runtimeYielded = false

-- 默认配置
local CONFIG = {
    enabled = true,
    texture = " |cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r |CFFBA55D3Solid|r",
    font = "默认",
    fontFlag = "OUTLINE",
    fontShadow = true,
    gradient = true,
    headerStyle = "Dark",
    edgeMode = true,
    bgStyle = "Transparent",
    barBgStyle = "Dark",
    fade = "ALL",
    snap = true,
    snapDirection = "VERTICAL",
    resetMode = "Smart",
    fadeMinAlpha = 0,
    fadeMaxAlpha = 1,
    fadeDuration = 0.3,
}

local Cache = {
    Fonts = setmetatable({}, { __mode = "k" }),
    States = setmetatable({}, { __mode = "k" }), -- 新增：用于安全存储框架状态
}

-- 辅助函数：安全地获取/初始化框架的自定义状态
local function GetState(f)
    if not f then return {} end
    local s = Cache.States[f]
    if not s then
        s = {}
        Cache.States[f] = s
    end
    return s
end

local function CallGetter(frame, method)
    local getter = frame and frame[method]
    if type(getter) ~= "function" then return nil end

    local ok, result = pcall(getter, frame)
    if ok then return result end
    return nil
end

local function GetMinimizeContainer(win)
    return CallGetter(win, "GetMinimizeContainer") or (win and win.MinimizeContainer) or win
end

local function GetHeader(win)
    return CallGetter(win, "GetHeader") or (win and win.Header)
end

local function GetBackground(win)
    local container = GetMinimizeContainer(win)
    return CallGetter(win, "GetBackground") or (container and container.Background) or (win and win.Background)
end

local function GetScrollBox(win)
    local container = GetMinimizeContainer(win)
    return CallGetter(win, "GetScrollBox") or (container and container.ScrollBox) or (win and win.ScrollBox)
end

local function GetScrollBar(win)
    local container = GetMinimizeContainer(win)
    return CallGetter(win, "GetScrollBar") or (container and container.ScrollBar) or (win and win.ScrollBar)
end

local function GetLocalPlayerEntry(win)
    local container = GetMinimizeContainer(win)
    return CallGetter(win, "GetLocalPlayerEntry") or (container and container.LocalPlayerEntry) or (win and win.LocalPlayerEntry)
end

local function GetResizeButton(win)
    local container = GetMinimizeContainer(win)
    return CallGetter(win, "GetResizeButton") or (container and container.ResizeButton) or (win and win.ResizeButton) or (win and win.ResizeGrip)
end

local function GetDamageMeterTypeDropdown(win)
    return CallGetter(win, "GetDamageMeterTypeDropdown") or (win and win.DamageMeterTypeDropdown)
end

local function GetSessionDropdown(win)
    return CallGetter(win, "GetSessionDropdown") or (win and win.SessionDropdown)
end

local function GetSettingsDropdown(win)
    return CallGetter(win, "GetSettingsDropdown") or (win and win.SettingsDropdown)
end

local function GetSourceWindow(win)
    return CallGetter(win, "GetSourceWindow") or (GetMinimizeContainer(win) and GetMinimizeContainer(win).SourceWindow)
end

local function GetEntryStatusBar(entry)
    return CallGetter(entry, "GetStatusBar") or (entry and entry.StatusBar)
end

local function GetEntryBackground(entry)
    return CallGetter(entry, "GetBackground") or (GetEntryStatusBar(entry) and GetEntryStatusBar(entry).Background)
end

local function GetEntryBackgroundEdge(entry)
    return CallGetter(entry, "GetBackgroundEdge") or (GetEntryStatusBar(entry) and GetEntryStatusBar(entry).BackgroundEdge)
end

local function GetEntryName(entry)
    return CallGetter(entry, "GetName") or (GetEntryStatusBar(entry) and GetEntryStatusBar(entry).Name) or (entry and entry.Name)
end

local function GetEntryValue(entry)
    return CallGetter(entry, "GetValue") or (GetEntryStatusBar(entry) and GetEntryStatusBar(entry).Value) or (entry and (entry.Value or entry.Amount or entry.Dps))
end

local function GetEntryIcon(entry)
    local icon = CallGetter(entry, "GetIcon")
    if icon then return icon end

    local iconFrame = entry and (entry.IconFrame or entry.Icon)
    if not iconFrame then return nil end
    return iconFrame.Icon or (iconFrame.IsObjectType and iconFrame:IsObjectType("Texture") and iconFrame)
end

local function GetRootDB()
    if YUI.DB and YUI.DB.GetProfile then
        local profile = YUI.DB:GetProfile(YUI.ProductId or "suite")
        if type(profile) == "table" then
            return profile
        end
    end
    return nil
end

function YDM:EnsureDB()
    local root = GetRootDB()
    if type(root) ~= "table" then
        return self.db
    end

    if type(root.YDamageMeter) ~= "table" then
        root.YDamageMeter = {}
    end
    for k, v in pairs(CONFIG) do
        if root.YDamageMeter[k] == nil then
            root.YDamageMeter[k] = v
        end
    end
    self.db = root.YDamageMeter
    return self.db
end

function YDM:Init()
    local function OnInitEvent(event, arg1)
        if event == "YUI_DB_READY" then
            self:EnsureDB()
            self:SetupResetLogic()
        end

        if (event == "ADDON_LOADED" and arg1 == "Blizzard_DamageMeter") or 
           (event == "YUI_LOGIN_READY" and C_AddOns.IsAddOnLoaded("Blizzard_DamageMeter")) then
            
            if not self.db then
                self:EnsureDB()
                self:SetupResetLogic()
            end
            
            C_Timer.After(0.1, function() self:Activate("addon-ready") end)
        end
    end

    YUI.Event:On("YUI_DB_READY", OnInitEvent, self, { priority = 0 })
    YUI.Event:On("ADDON_LOADED", OnInitEvent, self)
    YUI.Event:On("YUI_LOGIN_READY", OnInitEvent, self, { priority = 0 })
    YUI.Event:On("YUI_EXTERNAL_STATE_CHANGED", function()
        self:RefreshConflictState({ force = true })
    end, self, { moduleId = "component:YDamageMeter" })
    YUI.Event:On("YUI_APPEARANCE_ICON_SET_CHANGED", function()
        if self.RefreshAppearance then
            self:RefreshAppearance("icon-set")
        end
    end, self)
    YUI.Event:On("YUI_APPEARANCE_ICON_SCOPE_CHANGED", function(_, scopeID)
        if scopeID == ICON_SCOPE_ID and self.RefreshAppearance then
            self:RefreshAppearance("icon-scope")
        end
    end, self)
    self:RefreshConflictState()
end

function YDM:RefreshConflictState(options)
    local db = self:EnsureDB()
    local snapshot
    if type(External) == "table" and type(External.ResolveCapability) == "function" then
        local ok, value = pcall(
            External.ResolveCapability,
            External,
            "ui.damage_meter.controller",
            options
        )
        if ok and type(value) == "table" then snapshot = value end
    end
    local active = snapshot and snapshot.status == "active"
    local blocked = not snapshot or snapshot.status ~= "inactive"
    self.runtimeYielded = blocked == true
    if active and db and db.enabled then
        if YUI.Yield then
            YUI.Yield:Set("damage_meter", snapshot.controller, {
                status = "active",
                matches = snapshot.matches,
                enabled = true,
            })
        end
        if self.resetFrame and YUI.Event then YUI.Event:OffOwner(self.resetFrame) end
        local meter = _G.DamageMeter
        if meter and type(meter.RefreshLayout) == "function" then
            pcall(meter.RefreshLayout, meter)
        end
        return true
    end
    if YUI.Yield then YUI.Yield:Clear("damage_meter") end
    if db and db.enabled and snapshot and snapshot.status == "inactive" then
        self:SetupResetLogic()
        self:Activate("conflict-cleared")
    end
    return blocked
end

function YDM:Activate(reason)
    local db = self:EnsureDB()
    if not _G.DamageMeter then
        return
    end
    if not db or not db.enabled or self.runtimeYielded then
        return
    end

    if not self.hooked then
        if DamageMeterMixin then
            hooksecurefunc(DamageMeterMixin, "SetupSessionWindow", function(_, _, windowData)
                local win = windowData and windowData.sessionWindow
                if win then
                    self:StyleSessionWindow(win, "SetupSessionWindow")
                    self:RearrangeWindows()
                end
            end)
            
            hooksecurefunc(DamageMeterMixin, "RefreshLayout", function(meterSelf)
                C_Timer.After(0, function()
                    meterSelf:ForEachSessionWindow(function(w) self:StyleSessionWindow(w, "RefreshLayout") end)
                    self:RearrangeWindows()
                end)
            end)
            
            hooksecurefunc(DamageMeterMixin, "HideSessionWindow", function()
                C_Timer.After(0.1, function() self:RearrangeWindows() end)
            end)
        else
            hooksecurefunc(_G.DamageMeter, "SetupSessionWindow", function(_, _, windowData)
                local win = windowData and windowData.sessionWindow
                if win then
                    self:StyleSessionWindow(win, "SetupSessionWindow")
                    self:RearrangeWindows()
                end
            end)
            
            hooksecurefunc(_G.DamageMeter, "RefreshLayout", function()
                C_Timer.After(0, function()
                    _G.DamageMeter:ForEachSessionWindow(function(w) self:StyleSessionWindow(w, "RefreshLayout") end)
                    self:RearrangeWindows()
                end)
            end)
            
            hooksecurefunc(_G.DamageMeter, "HideSessionWindow", function()
                C_Timer.After(0.1, function() self:RearrangeWindows() end)
            end)
        end

        if DamageMeterSessionWindowMixin then
            hooksecurefunc(DamageMeterSessionWindowMixin, "Refresh", function(win)
                C_Timer.After(0, function() self:StyleSessionWindow(win, "SessionWindow.Refresh") end)
            end)
            hooksecurefunc(DamageMeterSessionWindowMixin, "InitEntry", function(_, frame)
                self:StyleBar(frame)
            end)
        end

        if DamageMeterSourceWindowMixin then
            hooksecurefunc(DamageMeterSourceWindowMixin, "Refresh", function(win)
                C_Timer.After(0, function() self:StyleSourceWindow(win, "SourceWindow.Refresh") end)
            end)
        end
        
        if DamageMeterEntryMixin then
            hooksecurefunc(DamageMeterEntryMixin, "Init", function(frame)
                self:StyleBar(frame)
            end)
            hooksecurefunc(DamageMeterEntryMixin, "UpdateStatusBarColor", function(frame)
                self:StyleBar(frame)
            end)
            hooksecurefunc(DamageMeterEntryMixin, "UpdateStyle", function(frame)
                self:StyleBar(frame)
            end)
            
            hooksecurefunc(DamageMeterEntryMixin, "UpdateIcon", function(frame)
                local t = GetEntryIcon(frame)
                if t then
                    local nid = frame.specIconID or frame.iconFileID
                    self:UpdateIconTexture(t, nid)
                end
            end)
        end

        self.hooked = true
    end

    self:RefreshAppearance(reason or "activate")

    if self.db.snap then
        self:RearrangeWindows()
        C_Timer.After(2.0, function() self:RearrangeWindows() end)
    end
end

function YDM:GetResources()
    local db = self:EnsureDB() or CONFIG
    local tex = LSM:Fetch("statusbar", db.texture) or "Interface\\TargetingFrame\\UI-StatusBar"
    local font = LSM:Fetch("font", db.font) or STANDARD_TEXT_FONT
    return tex, font
end

function YDM:ColorizeBar(bar, classFile)
    local db = self:EnsureDB()
    if not db then return end
    local tex = bar:GetStatusBarTexture()
    if not tex or not classFile then return end
    
    local c = C_ClassColor.GetClassColor(classFile)
    if not c then return end
    
    if not db.gradient then
        tex:SetVertexColor(c.r, c.g, c.b, 1)
        return 
    end
    
    local minC = CreateColor(c.r * 0.6, c.g * 0.6, c.b * 0.6, 1)
    local maxC = CreateColor(c.r, c.g, c.b, 1)
    tex:SetGradient("HORIZONTAL", minC, maxC)
end

function YDM:UpdateIconTexture(tex, fileID)
    if not tex then return end
    if fileID ~= nil then
        tex.__yuiOriginalIconTexture = fileID
    end
    if Icons and Icons.IsIconScopeEnabled and not Icons.IsIconScopeEnabled(ICON_SCOPE_ID) then
        local original = fileID or tex.__yuiOriginalIconTexture
        if original ~= nil then
            tex:SetTexture(original)
        end
        tex:SetTexCoord(0, 1, 0, 1)
        return
    end

    local icon = Icons and Icons.GetSpecIconByNativeTexture and Icons.GetSpecIconByNativeTexture(fileID)
    if icon and Icons.ApplyIcon then
        Icons.ApplyIcon(tex, icon)
    end
end

function YDM:FindFontStrings(entry)
    if Cache.Fonts[entry] then return Cache.Fonts[entry] end
    
    local list = {}
    local function add(obj)
        if obj and obj.GetFont then table.insert(list, obj) end
    end
    
    add(GetEntryName(entry))
    add(GetEntryValue(entry))
    add(entry.Name)
    add(entry.Amount)
    add(entry.Dps)
    
    local statusBar = GetEntryStatusBar(entry)
    if statusBar and statusBar.GetRegions then
        for _, r in ipairs({statusBar:GetRegions()}) do
            if r:IsObjectType("FontString") then add(r) end
        end
    end

    if entry.GetRegions then
        for _, r in ipairs({entry:GetRegions()}) do
            if r:IsObjectType("FontString") then add(r) end
        end
    end
    
    -- 去重
    local unique = {}
    local result = {}
    for _, f in ipairs(list) do
        if not unique[f] then
            unique[f] = true
            table.insert(result, f)
        end
    end
    
    Cache.Fonts[entry] = result
    return result
end

function YDM:StyleBar(entry)
    if not entry or self.runtimeYielded then return end
    local db = self:EnsureDB()
    if not db or not db.enabled then return end
    local tex, font = self:GetResources()
    local statusBar = GetEntryStatusBar(entry)

    -- 1. 进度条
    if statusBar then
        statusBar:SetStatusBarTexture(tex)
        
        local alpha = (db.barBgStyle == "Transparent") and 0 or 1
        local backgroundEdge = GetEntryBackgroundEdge(entry)
        local background = GetEntryBackground(entry)
        if backgroundEdge then backgroundEdge:SetAlpha(alpha) end
        if background then background:SetAlpha(alpha) end
        
        local classFile = entry.classFilename or entry.unitClassFilename
        if classFile then
            self:ColorizeBar(statusBar, classFile)
        end
    end

    -- 2. 字体
    for _, fs in ipairs(self:FindFontStrings(entry)) do
        local _, size = fs:GetFont()
        fs:SetFont(font, size or 12, db.fontFlag)
        if db.fontShadow then
            fs:SetShadowOffset(1, -1)
            fs:SetShadowColor(0, 0, 0, 1)
        else
            fs:SetShadowOffset(0, 0)
        end
    end

    -- 3. 图标
    local iconTex = GetEntryIcon(entry)
    if iconTex then
        local fid = entry.specIconID or entry.iconFileID 
        self:UpdateIconTexture(iconTex, fid)
    end
end

function YDM:StyleSourceWindow(win, reason, stats)
    if not win or self.runtimeYielded then return end

    local background = GetBackground(win)
    local db = self:EnsureDB()
    if background and db then
        if db.bgStyle == "Transparent" then
            background:SetAlpha(0)
        elseif db.bgStyle == "Dark" then
            background:SetAlpha(1)
            background:SetColorTexture(0, 0, 0, 0.6)
        end
    end

    local scrollBox = GetScrollBox(win)
    if scrollBox and scrollBox.ForEachFrame then
        scrollBox:ForEachFrame(function(frame)
            self:StyleBar(frame)
            if stats then stats.sourceBars = stats.sourceBars + 1 end
        end)
    end
end

function YDM:StyleSessionWindow(win, reason, stats)
    if not win or self.runtimeYielded then return end

    self:StyleFrame(win)

    if win.ForEachEntryFrame then
        local ok = pcall(function()
            win:ForEachEntryFrame(function(frame)
                self:StyleBar(frame)
                if stats then stats.bars = stats.bars + 1 end
            end)
        end)
        if not ok then
            local scrollBox = GetScrollBox(win)
            if scrollBox and scrollBox.ForEachFrame then
                scrollBox:ForEachFrame(function(frame)
                    self:StyleBar(frame)
                    if stats then stats.bars = stats.bars + 1 end
                end)
            end
        end
    else
        local scrollBox = GetScrollBox(win)
        if scrollBox and scrollBox.ForEachFrame then
            scrollBox:ForEachFrame(function(frame)
                self:StyleBar(frame)
                if stats then stats.bars = stats.bars + 1 end
            end)
        end
    end

    local localPlayerEntry = GetLocalPlayerEntry(win)
    if localPlayerEntry then
        self:StyleBar(localPlayerEntry)
        if stats then stats.localBars = stats.localBars + 1 end
    end

    self:StyleSourceWindow(GetSourceWindow(win), reason, stats)
end

function YDM:RefreshAppearance(reason, noRetry)
    if self.runtimeYielded then return end
    local db = self:EnsureDB()
    if not _G.DamageMeter or not _G.DamageMeter.ForEachSessionWindow then
        return
    end
    if not db or not db.enabled then
        return
    end

    if not self.hooked then
        self:Activate("refresh-install:" .. tostring(reason))
        return
    end

    local stats = { windows = 0, bars = 0, localBars = 0, sourceBars = 0 }
    _G.DamageMeter:ForEachSessionWindow(function(win)
        stats.windows = stats.windows + 1
        self:StyleSessionWindow(win, reason, stats)
    end)

    if not noRetry then
        C_Timer.After(0, function() self:RefreshAppearance(tostring(reason) .. ":after0", true) end)
        C_Timer.After(0.2, function() self:RefreshAppearance(tostring(reason) .. ":after0.2", true) end)
    end
end

function YDM:SetupResetLogic()
    self:EnsureDB()
    -- 如果全局禁用，则不执行任何逻辑
    if not self.db or not self.db.enabled or self.runtimeYielded then
        if self.resetFrame then YUI.Event:OffOwner(self.resetFrame) end
        return 
    end

    if not self.resetFrame then
        local f = {}
        f.module = self
        self.resetFrame = f
        
        function f:OnResetEvent(event, ...)
            -- 运行时检查最新的 resetMode
            local module = self.module
            local db = module and module.db
            if not db or not db.enabled then return end

            local mode = db.resetMode or "Smart"
            if mode == "Never" then return end
            
            if event == "YUI_WORLD_READY" then
                local isLogin, isReload = ...
                if isLogin or isReload then return end
                
                local inInstance, instanceType = IsInInstance()
                if inInstance and (instanceType == "party" or instanceType == "raid") then
                    if mode == "Smart" then
                        local Settings = YUI.Settings
                        if Settings and Settings.ShowConfirmPopup then
                            Settings:ShowConfirmPopup(
                                LC["settings.confirm.ydamage_reset.message"],
                                function()
                                    if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
                                        pcall(C_DamageMeter.ResetAllCombatSessions)
                                        YUI:Print(T("runtime.reset", "数据已重置"))
                                    end
                                end,
                                {
                                    titleText = LC["settings.confirm.ydamage_reset.title"],
                                    acceptText = LC["settings.confirm.ydamage_reset.accept"],
                                    acceptTone = "danger",
                                }
                            )
                        end
                    end
                end
                
            elseif event == "CHALLENGE_MODE_START" then
                if (mode == "Smart" or mode == "Combat") and C_DamageMeter then
                    pcall(C_DamageMeter.ResetAllCombatSessions)
                    YUI:Print(T("runtime.mythic_reset", "大秘境开始，数据已重置"))
                end
                
            elseif event == "PLAYER_REGEN_DISABLED" then
                if mode == "Combat" and C_DamageMeter then
                    pcall(C_DamageMeter.ResetAllCombatSessions)
                end
            end
        end
    end
    
    -- 始终更新事件注册状态
    YUI.Event:OffOwner(self.resetFrame)
    YUI.Event:On("YUI_WORLD_READY", "OnResetEvent", self.resetFrame)
    YUI.Event:On("CHALLENGE_MODE_START", "OnResetEvent", self.resetFrame)
    YUI.Event:On("PLAYER_REGEN_DISABLED", "OnResetEvent", self.resetFrame)
end

local function SetBtnStyle(btn, gray, r, g, b, a)
    if not btn then return end
    if btn.GetNormalTexture and btn:GetNormalTexture() then
        local t = btn:GetNormalTexture()
        t:SetDesaturated(gray)
        if r then t:SetVertexColor(r, g, b) end
        if a then t:SetAlpha(a) end
    end
    for _, reg in pairs({btn:GetRegions()}) do
        if reg:GetObjectType() == "Texture" then
            reg:SetDesaturated(gray)
            if r then reg:SetVertexColor(r, g, b) end
            if a then reg:SetAlpha(a) end
        end
    end
end

function YDM:StyleButton(btn)
    if not btn or self.runtimeYielded then return end
    local db = self:EnsureDB()
    local s = db and db.headerStyle or "Dark"
    
    if s == "Blizzard" then
        SetBtnStyle(btn, false, 1, 1, 1, 1)
    elseif s == "Transparent" then
        SetBtnStyle(btn, false, 0, 0, 0, 0)
    elseif s == "Dark" then
        SetBtnStyle(btn, true, 0.5, 0.5, 0.5, 1)
    end

    if not GetState(btn).hookedHover then
        btn:HookScript("OnEnter", function(button)
            if YDM.runtimeYielded then return end
            local db = YDM.db
            local st = db and db.headerStyle or "Dark"
            if st == "Dark" then SetBtnStyle(button, true, 0.8, 0.8, 0.8, 1)
            elseif st == "Transparent" then SetBtnStyle(button, false, 1, 1, 1, 1) end
        end)
        btn:HookScript("OnLeave", function(button)
            if YDM.runtimeYielded then return end
            local db = YDM.db
            local st = db and db.headerStyle or "Dark"
            if st == "Dark" then SetBtnStyle(button, true, 0.5, 0.5, 0.5, 1)
            elseif st == "Transparent" then SetBtnStyle(button, false, 0, 0, 0, 0) end
        end)
        GetState(btn).hookedHover = true
    end
end

function YDM:ApplyEdgeMode(win)
    if not win then return end

    if 1 == 1 then return end -- TODO: 有问题强制关闭
    
    if self.db.edgeMode then
        -- 隐藏滚动条
        local scrollBar = GetScrollBar(win)
        if scrollBar then
            scrollBar:SetAlpha(0)
            scrollBar:SetWidth(1)
            scrollBar:EnableMouse(false)
        end
        
        -- 调整布局 (不向上顶，仅右侧贴边)
        local sb = GetScrollBox(win)
        if sb then
            local header = GetHeader(win)
            
            sb:ClearAllPoints()
            if header then
                sb:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            else
                sb:SetPoint("TOPLEFT", win, "TOPLEFT", 0, -20)
            end
            sb:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
        end
    else
        -- 恢复滚动条
        local scrollBar = GetScrollBar(win)
        if scrollBar then
            scrollBar:SetAlpha(1)
            scrollBar:SetWidth(20)
            scrollBar:EnableMouse(true)
        end
    end
end

function YDM:StyleFrame(win)
    if not win or self.runtimeYielded then return end
    local db = self:EnsureDB()
    if not db then return end
    
    self:ApplyEdgeMode(win)

    -- 1. 标题栏
    local header = GetHeader(win)
    if header and win.GetRegions then
        local h = header
        local hs = db.headerStyle
        
        if h.bg then h.bg:Hide() end
        
        if hs == "Transparent" then
            h:SetDesaturated(false)
            h:SetVertexColor(1, 1, 1, 1)
            for _, r in ipairs({win:GetRegions()}) do
                if r:IsObjectType("Texture") then r:SetAlpha(0) end
            end
        elseif hs == "Dark" then
            for _, r in ipairs({win:GetRegions()}) do
                if r:IsObjectType("Texture") then r:SetAlpha(1) end
            end
            h:SetDesaturated(true)
            h:SetVertexColor(0.15, 0.15, 0.15, 1)
        elseif hs == "Blizzard" then
            for _, r in ipairs({win:GetRegions()}) do
                if r:IsObjectType("Texture") then r:SetAlpha(1) end
            end
            h:SetDesaturated(false)
            h:SetVertexColor(1, 1, 1, 1)
        end

        h:SetAlpha((db.fade or "NONE") == "NONE" and 1 or db.fadeMinAlpha)
        
        local _, font = self:GetResources()
        for _, r in ipairs({win:GetRegions()}) do
            if r:IsObjectType("FontString") then
                local _, size = r:GetFont()
                r:SetFont(font, size, db.fontFlag)
            end
        end
    end

    -- 2. 列表背景
    local scrollBox = GetScrollBox(win)
    if scrollBox then
        local background = GetBackground(win)
        if db.bgStyle == "Transparent" then
             if background then background:SetAlpha(0) end
        elseif db.bgStyle == "Dark" then
             if background then
                background:SetAlpha(1)
                background:SetColorTexture(0, 0, 0, 0.6)
             end
        end
    end
    
    if db.fade then self:InitFade(win) end

    if win.GetChildren then
        for _, c in ipairs({win:GetChildren()}) do
            if c:IsObjectType("Button") then self:StyleButton(c) end
        end
    end
end

local function RunAnim(ag, val, f)
    local state = GetState(ag)
    local a = state.alphaAnim
    a:SetFromAlpha(f:GetAlpha())
    a:SetToAlpha(val)
    state.targetAlpha = val
    ag:Play()
end

local function NewAnim(f)
    local state = GetState(f)
    if state.fadeAnim then return state.fadeAnim end
    local ag = f:CreateAnimationGroup()
    ag:SetLooping("NONE")
    local a = ag:CreateAnimation("Alpha")
    a:SetDuration(YDM.db.fadeDuration or 0.25)
    a:SetSmoothing("OUT")
    
    GetState(ag).alphaAnim = a
    
    ag:SetScript("OnFinished", function()
        local target = a:GetToAlpha()
        if target then f:SetAlpha(target) end
    end)

    state.fadeAnim = ag
    return ag
end

local function FadeHeader(win, val, immediate)
    local header = GetHeader(win)
    if not header then return end
    local mode = YDM.db.fade or "ALL"
    local list = {}

    if mode == "ALL" then
        table.insert(list, header)
        table.insert(list, GetDamageMeterTypeDropdown(win))
        table.insert(list, GetSessionDropdown(win))
        table.insert(list, GetSettingsDropdown(win))
    elseif mode == "HEADER" then
        table.insert(list, header)
        table.insert(list, GetSessionDropdown(win))
        table.insert(list, GetSettingsDropdown(win))
        
        local t = GetDamageMeterTypeDropdown(win)
        if t then
            t:SetAlpha(1)
            if t.Arrow then table.insert(list, t.Arrow) end
            for _, r in ipairs({t:GetRegions()}) do
                if r:GetObjectType() == "Texture" then table.insert(list, r) end
            end
            for _, c in ipairs({t:GetChildren()}) do
                if c:GetObjectType() ~= "FontString" then table.insert(list, c) end
            end
        end
    end
    
    if #list == 0 then return end

    if not immediate then
        local checkObj = list[1]
        local ag = GetState(checkObj).fadeAnim or NewAnim(checkObj)
        
        local isPlaying = ag:IsPlaying()
        local curTarget = GetState(ag).targetAlpha
        
        if isPlaying and curTarget == val then return end
        if not isPlaying and math.abs(checkObj:GetAlpha() - val) < 0.01 then return end
    end

    for _, o in ipairs(list) do
        if o then
            local state = GetState(o)
            if immediate then
                if state.fadeAnim and state.fadeAnim:IsPlaying() then state.fadeAnim:Stop() end
                o:SetAlpha(val)
                if state.fadeAnim then GetState(state.fadeAnim).targetAlpha = val end
            else
                local ag = NewAnim(o)
                if ag:IsPlaying() then ag:Stop() end
                RunAnim(ag, val, o)
            end
        end
    end
end

function YDM:InitFade(win)
    if self.runtimeYielded or not GetHeader(win) then return end
    local state = GetState(win)
    
    if self.db.fade == "NONE" then 
        if state.fadeHooked then
             FadeHeader(win, 1, true)
        end
        return 
    end

    -- 强制初始透明度
    C_Timer.After(0.1, function()
        FadeHeader(win, self.db.fadeMinAlpha, true)
    end)
    
    if state.fadeHooked then return end

    win:HookScript("OnEnter", function()
        local s = GetState(win)
        if s.fadeTmr then s.fadeTmr:Cancel(); s.fadeTmr = nil end
        FadeHeader(win, self.db.fadeMaxAlpha)
    end)
    
    win:HookScript("OnLeave", function()
        local s = GetState(win)
        if s.fadeTmr then s.fadeTmr:Cancel() end
        s.fadeTmr = C_Timer.NewTimer(0.1, function()
            if not win:IsMouseOver() then
                FadeHeader(win, self.db.fadeMinAlpha)
            end
            s.fadeTmr = nil
        end)
    end)
    
    state.fadeHooked = true
end

function YDM:AttachWindow(cur, tar, dir, spacing)
    if not cur or not tar or not tar:IsShown() then return end
    
    local resizeButton = GetResizeButton(cur)
    if resizeButton then resizeButton:Hide() end
    
    cur:ClearAllPoints()
    cur:SetWidth(tar:GetWidth())
    cur:SetHeight(tar:GetHeight())
    
    spacing = spacing or self.db.snapSpacing or 1
    
    if dir == "TOP" then
        cur:SetPoint("BOTTOMLEFT", tar, "TOPLEFT", 0, spacing)
        cur:SetPoint("BOTTOMRIGHT", tar, "TOPRIGHT", 0, spacing)
    elseif dir == "BOTTOM" then
        cur:SetPoint("TOPLEFT", tar, "BOTTOMLEFT", 0, -spacing)
        cur:SetPoint("TOPRIGHT", tar, "BOTTOMRIGHT", 0, -spacing)
    elseif dir == "LEFT" then
        cur:SetPoint("TOPRIGHT", tar, "TOPLEFT", -spacing, 0)
        cur:SetPoint("BOTTOMRIGHT", tar, "BOTTOMLEFT", -spacing, 0)
    elseif dir == "RIGHT" then
        cur:SetPoint("TOPLEFT", tar, "TOPRIGHT", spacing, 0)
        cur:SetPoint("BOTTOMLEFT", tar, "BOTTOMRIGHT", spacing, 0)
    end
end

function YDM:RearrangeWindows()
    if self.runtimeYielded or not self.db.snap then return end
    local w1 = _G["DamageMeterSessionWindow1"]
    if not w1 or not w1:IsShown() then return end
    
    local wins = {w1}
    for i = 2, 5 do
        local w = _G["DamageMeterSessionWindow"..i]
        if w and w:IsShown() then table.insert(wins, w) end
    end
    if #wins <= 1 then return end
    
    local cx, cy = w1:GetCenter()
    if not cx then return end
    local sw, sh = GetScreenWidth(), GetScreenHeight()
    local q = (cy > sh/2 and "TOP" or "BOTTOM") .. (cx < sw/2 and "LEFT" or "RIGHT")
    
    local vDir = (q:find("TOP")) and "BOTTOM" or "TOP"
    local hDir = (q:find("LEFT")) and "RIGHT" or "LEFT"
    
    local mode = self.db.snapDirection or "VERTICAL"
    local spacing = self.db.snapSpacing or 1
    
    if self.db.edgeMode then spacing = 0 end

    if mode == "VERTICAL" then
        for i = 2, #wins do self:AttachWindow(wins[i], wins[i-1], vDir, spacing) end
    elseif mode == "HORIZONTAL" then
        for i = 2, #wins do self:AttachWindow(wins[i], wins[i-1], hDir, spacing) end
    elseif mode == "L_VERT" then
        if wins[2] then self:AttachWindow(wins[2], wins[1], vDir, spacing) end
        if wins[3] then self:AttachWindow(wins[3], wins[1], hDir, spacing) end
    elseif mode == "L_HORIZ" then
        if wins[2] then self:AttachWindow(wins[2], wins[1], hDir, spacing) end
        if wins[3] then self:AttachWindow(wins[3], wins[1], vDir, spacing) end
    end
end

YDM:Init()

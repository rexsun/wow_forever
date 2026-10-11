local function CreateInstance(context)
local YUI = _G.YUI
local Events = context and context.events or YUI.Event
local function GetYBarDB()
    if context then return context:GetRoot() end
    if YUI.YBar and YUI.YBar.GetModuleRoot then return YUI.YBar:GetModuleRoot("Clock") end
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
local Module = YBar.Module:New(context and context.id or "Clock")
local LegacyAPI = YUI.WOW_API
local CombatAPI = (YUI.API and YUI.API.Combat) or LegacyAPI
local SecurityAPI = (YUI.API and YUI.API.Security) or LegacyAPI
local UnitAPI = (YUI.API and YUI.API.Unit) or LegacyAPI
local L = YUI.Locale:Get("YBar")
local LC = YUI.Locale:Get("Core")
local LSM = LibStub("LibSharedMedia-3.0")

local FLASH_SPEED = 1 -- 冒号闪烁速度
local FLASH_MIN_ALPHA = 0.2 -- 冒号闪烁透明度下限 (0-1)
local CLOCK_TICK_INTERVAL = 1
local CLOCK_FLASH_FALLBACK_INTERVAL = 1 / 30
local CLOCK_FLASH_ANIMATION_DURATION = 1 / FLASH_SPEED

-- 默认字体设置
local DEFAULT_SIZE = 21
local DEFAULT_FONT = STANDARD_TEXT_FONT
local DEFAULT_COMBAT_TIME_COLOR = {1, 1, 1, 1}
local DEFAULT_COMBAT_TIME_SCENE = "all"
local CLOCK_DEFAULT_TEXT_COLOR = { 1, 1, 1, 1 }
local EnsureClockDB

local function GetPlayerClassColor()
    local _, classFile = UnitAPI.UnitClass("player")
    local color = UnitAPI.GetClassColor(classFile)
    if color then
        return color.r or 1, color.g or 1, color.b or 1, color.a or 1
    end
    return 1, 0.82, 0, 1
end

local function ResolveFont(font)
    -- Explicit paths must not be looked up as media names or globally overridden.
    if type(font) == "string" and (font:find("\\", 1, true) or font:find("/", 1, true)) then
        return YBar:ResolveFontPath(font, DEFAULT_FONT)
    end
    if font and font ~= "" then
        local fontPath = LSM:Fetch("font", font, true)
        if fontPath then
            return YBar:ResolveFontPath(fontPath, DEFAULT_FONT)
        end
    end

    return DEFAULT_FONT
end

local function GetDefaultFontKey()
    return (LSM.GetDefault and LSM:GetDefault("font")) or DEFAULT_FONT
end

local function NormalizeFontKey(font)
    if not font or font == "" then
        return GetDefaultFontKey()
    end

    if LSM:IsValid("font", font) then
        return font
    end

    if type(font) == "string" then
        local fontList = LSM:HashTable("font") or {}
        for name, path in pairs(fontList) do
            if path == font then
                return name
            end
        end
    end

    return font
end

local function BuildFontOptions()
    local fontList = LSM:HashTable("font") or {}
    local fontOptions = {}
    for name, path in pairs(fontList) do
        table.insert(fontOptions, {
            text = YUI.Locale and YUI.Locale.GetFontDisplayName
                and YUI.Locale:GetFontDisplayName(name)
                or name,
            value = name,
            render = function(btn)
                if btn and btn.text and path then
                    btn.text:SetFont(path, GUI2.Fonts.size_normal)
                end
            end,
        })
    end
    table.sort(fontOptions, function(a, b) return a.text < b.text end)

    if #fontOptions == 0 then
        fontOptions[1] = { text = LC["common.default"] or "Default", value = DEFAULT_FONT }
    end

    return fontOptions
end

local function GetClockFont(db)
    db = db or EnsureClockDB()
    -- Rendering may fall back, but must never overwrite the user's selection.
    return db.font or GetDefaultFontKey()
end

local function ApplyFont(fontString, font, size, flag)
    if not fontString then return end

    local fontPath = ResolveFont(font)
    local fontFlag = flag ~= "" and flag or nil
    local ok, applied = pcall(fontString.SetFont, fontString, fontPath, size, fontFlag)

    if (not ok or not applied) and fontPath ~= DEFAULT_FONT then
        fontString:SetFont(DEFAULT_FONT, size, fontFlag)
    end
end

local function ApplyTextStyle(fontString, font, size, globalDB)
    if not fontString then return end

    local fontFlag = globalDB and (globalDB.fontFlags or (globalDB.fontOutline and "OUTLINE" or "")) or nil
    ApplyFont(fontString, font, size, fontFlag)

    if globalDB and globalDB.fontShadow then
        fontString:SetShadowColor(0, 0, 0, 1)
        fontString:SetShadowOffset(1, -1)
    else
        fontString:SetShadowColor(0, 0, 0, 0)
        fontString:SetShadowOffset(0, 0)
    end
end

function EnsureClockDB()
    local ybarDB = GetYBarDB()
    if type(ybarDB) ~= "table" then
        return {}
    end
    ybarDB.Clock = ybarDB.Clock or {}
    return ybarDB.Clock
end

local function GetColorValue(color, fallback)
    color = type(color) == "table" and color or fallback
    return color[1] or color.r or fallback[1],
           color[2] or color.g or fallback[2],
           color[3] or color.b or fallback[3],
           color[4] or color.a or fallback[4] or 1
end

local function RefreshClockLayout()
    if Module.frame then
        Module:UpdateBarItem(Module.frame, Module.parent)
    end

    if not YUI.YBar then return end
    if SecurityAPI.InCombatLockdown and SecurityAPI.InCombatLockdown() then
        if YUI.YBar.UpdateLayout then YUI.YBar:UpdateLayout() end
        return
    end

    if YUI.YBar.UpdateLayoutImmediate then
        YUI.YBar:UpdateLayoutImmediate()
    elseif YUI.YBar.UpdateLayout then
        YUI.YBar:UpdateLayout()
    end
end

local function IsClockFlashEnabled()
    local db = GetYBarDB()
    return db and db.Clock and db.Clock.flash and true or false
end

local function StopClockTicker()
    if Module.clockTicker and Module.clockTicker.Cancel then
        Module.clockTicker:Cancel()
    end
    Module.clockTicker = nil
end

local function ClockTickerCallback()
    local cpuWatchdog = YUI.CPUWatchdog
    local cpuStartedAt = cpuWatchdog and cpuWatchdog.timingActive and cpuWatchdog:BeginProbeTiming()
    if Module.content then
        Module:UpdateTimeText(Module.content)
    end
    if cpuStartedAt then cpuWatchdog:EndProbeTiming("product.ybar-clock", cpuStartedAt) end
end

local cpuWatchdog = YUI.CPUWatchdog
if not context and cpuWatchdog and cpuWatchdog.RegisterProbe then
    cpuWatchdog:RegisterProbe("product.ybar-clock", {
        localeKey = "cpu_watch.probe.ybar_clock",
        kind = "function",
        target = ClockTickerCallback,
        snapshot = function() return { running = Module.clockTicker ~= nil } end,
    })
end

local function StartClockTicker()
    if Module.clockTicker or not Module.content or not (C_Timer and C_Timer.NewTicker) then
        return
    end

    if context and context.events then
        Module.clockTicker = context.events:EverySecond(ClockTickerCallback, Module)
    else
        Module.clockTicker = C_Timer.NewTicker(CLOCK_TICK_INTERVAL, ClockTickerCallback)
    end
end

local function ClockFlashFallbackOnUpdate(content, elapsed)
    if not content.clockFlashEnabled then
        content:SetScript("OnUpdate", nil)
        if content.textSep then content.textSep:SetAlpha(1) end
        return
    end

    content.flashTimer = (content.flashTimer or 0) + elapsed
    if content.flashTimer < CLOCK_FLASH_FALLBACK_INTERVAL then
        return
    end

    content.flashTimer = 0
    if content.textSep then
        local sinVal = (math.sin(CombatAPI.GetTime() * FLASH_SPEED) + 1) / 2
        local alpha = sinVal * (1 - FLASH_MIN_ALPHA) + FLASH_MIN_ALPHA
        content.textSep:SetAlpha(alpha)
    end
end

local function StopClockFlashDriver(content)
    if not content then return end

    content.clockFlashEnabled = false
    content.flashTimer = nil
    content:SetScript("OnUpdate", nil)

    if content.clockFlashGroup and content.clockFlashGroup.Stop then
        content.clockFlashGroup:Stop()
    end

    if content.textSep then
        content.textSep:SetAlpha(1)
    end
end

local function StartNativeClockFlash(content)
    local textSep = content and content.textSep
    if not textSep or type(textSep.CreateAnimationGroup) ~= "function" then
        return false
    end

    local group = content.clockFlashGroup
    if not group then
        local ok, createdGroup = pcall(textSep.CreateAnimationGroup, textSep)
        if not ok or not createdGroup or type(createdGroup.CreateAnimation) ~= "function" then
            return false
        end

        group = createdGroup
        if group.SetLooping then
            group:SetLooping("REPEAT")
        end

        local okFadeOut, fadeOut = pcall(group.CreateAnimation, group, "Alpha")
        local okFadeIn, fadeIn = pcall(group.CreateAnimation, group, "Alpha")
        if not okFadeOut or not fadeOut or not okFadeIn or not fadeIn then
            if group.Stop then group:Stop() end
            return false
        end

        fadeOut:SetOrder(1)
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(FLASH_MIN_ALPHA)
        fadeOut:SetDuration(CLOCK_FLASH_ANIMATION_DURATION)

        fadeIn:SetOrder(2)
        fadeIn:SetFromAlpha(FLASH_MIN_ALPHA)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(CLOCK_FLASH_ANIMATION_DURATION)

        content.clockFlashGroup = group
    end

    textSep:SetAlpha(1)
    if group.Stop then group:Stop() end
    if group.Play then group:Play() end
    return true
end

local function StartClockFlashDriver(content)
    StopClockFlashDriver(content)
    if not content or not IsClockFlashEnabled() then
        return
    end

    content.clockFlashEnabled = true
    if StartNativeClockFlash(content) then
        return
    end

    content:SetScript("OnUpdate", ClockFlashFallbackOnUpdate)
end

function Module:OnInitialize()
    self.frame = nil
    self.content = nil
    self.parent = nil
    self.clockTicker = nil
    self.combatStartTime = nil
    self.inCombatTimeMode = false
    self.combatTimeSceneMatched = false
end

function Module:OnLifecycleInitialize()
    if not self._ybarInitialized then
        self:OnInitialize()
        self._ybarInitialized = true
    end
end

function Module:IsCombatTimeEnabled(db)
    return not db or db.autoCombatTime ~= false
end

function Module:ShouldShowCombatTime(db)
    return self:IsCombatTimeEnabled(db) and self.inCombatTimeMode and self.combatStartTime and self.combatTimeSceneMatched
end

function Module:UpdateCombatTimeScene(db)
    db = db or (GetYBarDB() and GetYBarDB().Clock) or {}
    local scene = db.combatTimeScene or DEFAULT_COMBAT_TIME_SCENE

    if scene == "group" then
        self.combatTimeSceneMatched = IsInGroup and IsInGroup() or false
    elseif scene == "instance" then
        local inInstance = IsInInstance and IsInInstance()
        self.combatTimeSceneMatched = inInstance and true or false
    else
        self.combatTimeSceneMatched = true
    end
end

function Module:ApplyTextColors(content, db)
    if not content then return end
    db = db or (GetYBarDB() and GetYBarDB().Clock) or {}

    if self:ShouldShowCombatTime(db) then
        local r, g, b, a = GetColorValue(db.combatTimeColor, DEFAULT_COMBAT_TIME_COLOR)
        YBar:SetThemedTextRawColor(content.textH, r, g, b, a)
        YBar:SetThemedTextRawColor(content.textSep, r, g, b, a)
        YBar:SetThemedTextRawColor(content.textM, r, g, b, a)
        return
    end

    YBar:SetThemedTextRawColor(content.textH, 1, 1, 1, 1)
    YBar:SetThemedTextRawColor(content.textM, 1, 1, 1, 1)

    if db.colonClassColor then
        YBar:SetThemedTextRawColor(content.textSep, GetPlayerClassColor())
    else
        YBar:SetThemedTextColor(content.textSep, "color.ybar.text", CLOCK_DEFAULT_TEXT_COLOR)
    end
end

function Module:StartCombatTimer()
    self:UpdateCombatTimeScene()
    self.combatStartTime = CombatAPI.GetTime()
    self.inCombatTimeMode = true
    self:UpdateTimeText()
end

function Module:StopCombatTimer()
    self.combatStartTime = nil
    self.inCombatTimeMode = false
    self.combatTimeSceneMatched = false
    self:UpdateTimeText()
end

function Module:SyncCombatState()
    if SecurityAPI.InCombatLockdown() then
        if not self.inCombatTimeMode or not self.combatStartTime then
            self:StartCombatTimer()
        end
    elseif self.inCombatTimeMode or self.combatStartTime then
        self:StopCombatTimer()
    else
        self:UpdateTimeText()
    end
end

function Module:OnClockEvent(event, ...)
    local content = self.content
    if event == "UPDATE_INSTANCE_INFO" and content and GameTooltip:GetOwner() == content then
        local onEnter = content:GetScript("OnEnter")
        if onEnter then onEnter(content) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        self:StartCombatTimer()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:StopCombatTimer()
    elseif event == "YUI_WORLD_READY" then
        self:SyncCombatState()
    end
end

function Module:AttachRuntime()
    self._runtimeAttached = true

    if Events and not self.eventsAttached then
        Events:OffOwner(self)
        Events:On("UPDATE_INSTANCE_INFO", "OnClockEvent", self)
        Events:On("YUI_WORLD_READY", "OnClockEvent", self)
        Events:On("PLAYER_REGEN_DISABLED", "OnClockEvent", self)
        Events:On("PLAYER_REGEN_ENABLED", "OnClockEvent", self)
        self.eventsAttached = true
    end

    if self.content then
        self.updateAttached = false
        self:RefreshRuntime(true)
    end

    self:SyncCombatState()
end

function Module:DetachRuntime()
    self._runtimeAttached = false
    StopClockTicker()

    if Events then
        Events:OffOwner(self)
    end

    self.eventsAttached = false
    self.updateAttached = false
    self.combatStartTime = nil
    self.inCombatTimeMode = false
    self.combatTimeSceneMatched = false

    if self.content then
        if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self.content then
            YUI.HideGameTooltip()
        end
        StopClockFlashDriver(self.content)
        self.content.timer = nil
        self.content.isHovering = false
    end

    if self.frame then
        self.frame:Hide()
    end
end

function Module:OnLifecycleEnable()
    self:AttachRuntime()
    if self.frame then
        self.frame:Show()
        self:UpdateBarItem(self.frame, self.parent)
    end
end

function Module:OnLifecycleDisable()
    self:DetachRuntime()
end

function Module:OnLifecycleProfileChanged()
    if YUI.YBar and YUI.YBar:IsSubModuleEnabled(self.name) then
        self:AttachRuntime()
        self:UpdateBarItem(self.frame, self.parent)
    else
        self:DetachRuntime()
    end
end

function Module:OnLifecycleConfigChanged()
    self:UpdateBarItem(self.frame, self.parent)
end

function Module:OnLifecycleLayoutChanged()
    if YUI.YBar and YUI.YBar:IsSubModuleEnabled(self.name) then
        self:AttachRuntime()
    else
        self:DetachRuntime()
    end
end

function Module:CreateBarItem(parent)
    -- YUI:Debug("Clock:CreateBarItem")

    -- 主框架：仅用于布局占位，不接收鼠标事件
    local frame = YBar:CreateBarItem(parent, {
        variant = "bare",
        width = 50,
        height = 20,
        showIcon = false,
        text = false,
        value = false,
    })
    
    -- 内容框架：承载文本和交互
    local content = GUI2:CreateButtonFrame(frame)
    content:SetSize(50, 20)
    
    content:SetScript("OnEnter", function(self)
        self.isHovering = true

        -- 请求最新的副本进度信息 (防抖：10秒内只请求一次)
        local now = CombatAPI.GetTime()
        if not self.lastRaidInfoRequest or (now - self.lastRaidInfoRequest) > 10 then
            self.lastRaidInfoRequest = now
            RequestRaidInfo()
        end

        local db = GetYBarDB() and GetYBarDB().Clock or {}
        if Module:ShouldShowCombatTime(db) then
            Module:ApplyTextColors(self, db)
        else
            YBar:SetThemedTextAccent(self.textH)
            YBar:SetThemedTextAccent(self.textM)
            YBar:SetThemedTextAccent(self.textSep)
        end

        local tooltipAnchor = "ANCHOR_TOP"
        -- 使用 content 的屏幕位置判断
        if self:GetBottom() > GetScreenHeight() / 2 then
            tooltipAnchor = "ANCHOR_BOTTOM"
        end
        
        GameTooltip:SetOwner(self, tooltipAnchor)
        GameTooltip:AddLine(L["clock.tooltip.title"])
        GameTooltip:AddLine(" ")
        
        local localHour, localMinute = GetGameTime()
        GameTooltip:AddDoubleLine(L["clock.tooltip.server_time"], format("%02d:%02d", localHour, localMinute), 1, 1, 1, 1, 0.82, 0)
        GameTooltip:AddDoubleLine(L["clock.tooltip.local_time"], date("%H:%M"), 1, 1, 1, 1, 0.82, 0)
        
        -- 添加副本进度列表
        local numSaved = GetNumSavedInstances()
        if numSaved > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["clock.tooltip.saved_instances"])
            
            for i = 1, numSaved do
                local name, id, reset, difficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
                
                if (isRaid or difficulty == 23 or difficulty == 24 or difficulty == 2) and (locked or extended) then -- 只显示团队副本(或史诗地下城)且已锁定/延长的
                    local r, g, b = 1, 1, 1
                    
                    if extended then 
                        r, g, b = 0.3, 1, 0.3 -- 延长显示绿色
                    elseif locked then
                        r, g, b = 1, 0.3, 0.3 -- 锁定显示红色
                    end

                    local progressText = ""
                    local difficultyTag = ""
                    
                    if difficultyName then
                        -- 尝试提取难度首字母 (例如 "Heroic" -> "H", "Mythic" -> "M")
                        -- 注意：GetSavedInstanceInfo 返回的 difficultyName 已经是本地化字符串，所以我们最好用 difficulty ID 或手动映射
                        -- 简单处理：如果是 23/24/2 (Mythic/Heroic/Normal)，手动添加
                        
                        -- Difficulty IDs:
                        -- 1: Normal (5)
                        -- 2: Heroic (5)
                        -- 3: 10 Player
                        -- 4: 25 Player
                        -- 5: 10 Player (Heroic)
                        -- 6: 25 Player (Heroic)
                        -- 7: LFR
                        -- 9: 40 Player
                        -- 11: Heroic Scenario
                        -- 12: Normal Scenario
                        -- 14: Normal (Raid)
                        -- 15: Heroic (Raid)
                        -- 16: Mythic (Raid)
                        -- 17: LFR
                        -- 23: Mythic (5)
                        -- 24: Timewalking
                        -- 33: Timewalking Raid
                        
                        -- 颜色值参考物品品质: 史诗(橙色 ffaf60), 英雄(紫色 a335ee), 普通(绿色 1eff00), 随机(白色 ffffff)
                        if difficulty == 16 or difficulty == 23 then
                            difficultyTag = "|cffff8000(" .. L["clock.difficulty.mythic"] .. ")|r"
                        elseif difficulty == 15 or difficulty == 2 or difficulty == 5 or difficulty == 6 then
                            difficultyTag = "|cffa335ee(" .. L["clock.difficulty.heroic"] .. ")|r"
                        elseif difficulty == 14 or difficulty == 1 or difficulty == 3 or difficulty == 4 then
                            difficultyTag = "|cff1eff00(" .. L["clock.difficulty.normal"] .. ")|r"
                        elseif difficulty == 7 or difficulty == 17 then
                            difficultyTag = "|cffffffff(" .. L["clock.difficulty.lfr"] .. ")|r"
                        else
                            difficultyTag = format("(%s)", difficultyName)
                        end
                    end

                    if encounterProgress and numEncounters and numEncounters > 0 then
                         progressText = format(" %d/%d", encounterProgress, numEncounters)
                    end
                    
                    local resetText = ""
                    if reset and reset > 0 then
                        local days = math.floor(reset / 86400)
                        local hours = math.floor((reset % 86400) / 3600)
                        if days > 0 then
                            resetText = format(L["clock.reset.days_hours"], days, hours)
                        else
                            resetText = format(L["clock.reset.hours"], hours)
                        end
                    end

                    GameTooltip:AddDoubleLine(difficultyTag .. " " .. name .. progressText, resetText, r, g, b, 1, 1, 1)
                end
            end
        end

        local headerColor = CreateColor(1, 0.82, 0)
        local headerHex = headerColor:GenerateHexColor()
        local white = "|cffffffff"
        local gold = "|c" .. headerHex
        
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.left_click"], gold, L["clock.tooltip.open_calendar"]))
        GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.right_click"], gold, L["clock.tooltip.open_clock"]))
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff808080" .. LC["common.alt_left_click"] .. ": " .. LC["common.open_settings"] .. "|r")
        
        GameTooltip:Show()
    end)
    
    content:SetScript("OnLeave", function(self)
        self.isHovering = false
        YUI.HideGameTooltip()
        YBar:RestoreThemedTextColor(self.textH)
        YBar:RestoreThemedTextColor(self.textM)
        YBar:RestoreThemedTextColor(self.textSep)
        Module:UpdateTimeText(self)
    end)
    
    -- 点击与鼠标事件由 ActionHost 覆盖，content 只承载文本和 OnUpdate。
    local actionHost = YBar:CreateActionHost(content, {
        onEnter = function(_, owner)
            local script = owner:GetScript("OnEnter")
            if script then script(owner) end
        end,
        onLeave = function(_, owner)
            local script = owner:GetScript("OnLeave")
            if script then script(owner) end
        end,
    })
    if actionHost then
        actionHost:SetActions({
            left = {
                kind = "custom",
                onClick = function()
                    if SecurityAPI.InCombatLockdown() then return end
                    if ToggleCalendar then
                        pcall(ToggleCalendar)
                    end
                end,
            },
            right = {
                kind = "custom",
                onClick = function()
                    if ToggleTimeManager then
                        ToggleTimeManager()
                    elseif TimeManager_Toggle then
                        TimeManager_Toggle()
                    end
                end,
            },
            altLeft = {
                kind = "custom",
                onClick = function()
                    YUI:OpenYBarModuleSettings(Module.name)
                end,
            },
        })
    end

    content.statusSep, content.textSep = YBar:CreateStatusText(content, {
        variant = "single",
        value = ":",
        width = 8,
        height = 20,
        justifyH = "CENTER",
        colorKey = "color.ybar.text",
    })
    local textSep = content.textSep
    textSep:ClearAllPoints()
    textSep:SetPoint("CENTER", 0, 0)
    textSep:SetText(":")

    content.statusH, content.textH = YBar:CreateStatusText(content, {
        variant = "single",
        value = "",
        width = 24,
        height = 20,
        justifyH = "RIGHT",
        colorKey = "color.ybar.text",
    })
    local textH = content.textH
    textH:ClearAllPoints()
    textH:SetPoint("RIGHT", textSep, "LEFT", 0, 0)

    content.statusM, content.textM = YBar:CreateStatusText(content, {
        variant = "single",
        value = "",
        width = 24,
        height = 20,
        justifyH = "LEFT",
        colorKey = "color.ybar.text",
    })
    local textM = content.textM
    textM:ClearAllPoints()
    textM:SetPoint("LEFT", textSep, "RIGHT", 0, 0)
    
    -- 方便内部访问
    content.textH = textH
    content.textSep = textSep
    content.textM = textM
    
    -- 兼容旧引用 (外部可能通过 Module.frame 访问)
    frame.content = content
    frame.textH = textH
    frame.textSep = textSep
    frame.textM = textM
    frame.text = textH 
    
    self.frame = frame -- 保存引用
    self.content = content
    self.parent = parent
    
    if not YUI.YBar or YUI.YBar:IsSubModuleEnabled(self.name) then
        self:AttachRuntime()
    end
    
    -- 初始更新
    self:UpdateBarItem(frame, parent)
    
    return frame
end

function Module:UpdateTimeText(frameOrContent)
    -- 兼容传入 frame 或 content
    local content = frameOrContent
    if content and content.content then content = content.content end -- 如果传入的是 frame
    if not content then 
        if self.content then content = self.content
        elseif self.frame and self.frame.content then content = self.frame.content 
        else return end
    end
    
    local db = GetYBarDB() and GetYBarDB().Clock or {}
    if self:ShouldShowCombatTime(db) then
        local elapsed = math.floor(CombatAPI.GetTime() - self.combatStartTime)
        if elapsed < 0 then elapsed = 0 end

        local hours = math.floor(elapsed / 3600)
        local minutes = math.floor((elapsed % 3600) / 60)
        local seconds = elapsed % 60

        if hours > 0 then
            if content.textH then content.textH:SetText(format("%d:%02d", hours, minutes)) end
        else
            if content.textH then content.textH:SetText(format("%02d", minutes)) end
        end

        if content.textM then content.textM:SetText(format("%02d", seconds)) end
        if not content.isHovering then self:ApplyTextColors(content, db) end
        return
    end

    local useLocal = db.useLocalTime -- 默认 false (服务器时间)
    local use24 = db.use24Hour ~= false -- 默认 true
    
    local hour, minute
    
    if useLocal then
        local t
        if context and Events.ReadData then t=Events:ReadData("clock-local",date,"*t") else t=date("*t") end
        hour = t.hour
        minute = t.min
    else
        if context and Events.ReadData then hour,minute=Events:ReadData("clock-server",GetGameTime)
        else hour,minute=GetGameTime() end
    end
    
    local textH = hour
    local textM = minute
    
    if not use24 then
        if hour >= 12 then
            if hour > 12 then hour = hour - 12 end
        else
            if hour == 0 then hour = 12 end
        end
        textH = hour
    end
    
    if content.textH then content.textH:SetText(format("%02d", textH)) end
    if content.textM then content.textM:SetText(format("%02d", textM)) end
    if not content.isHovering then self:ApplyTextColors(content, db) end
end

function Module:UpdateBarItem(frame, parent)
    if parent then self.parent = parent end

    if not frame then frame = self.frame end
    if not frame then return end
    
    local content = frame.content
    if not content then return end
    
    -- 获取配置
    local db = GetYBarDB() and GetYBarDB().Clock or {}
    local font = GetClockFont(db)
    local size = db.fontSize or DEFAULT_SIZE
    
    local globalDB = (GetYBarDB()) or {}
    local vPadding = db.vPadding or 0
    
    ApplyTextStyle(content.textH, font, size, globalDB)
    ApplyTextStyle(content.textSep, font, size, globalDB)

    -- 旧版时钟自行限制屏幕边缘；实例布局已负责定位，不能再次按条高补偿。
    if not context and YUI.YBar and parent then
        local barHeight = parent:GetHeight()
        local textHeight = content.textSep:GetStringHeight() or size
        
        if parent == YUI.YBar.topFrame then
            -- 顶部条：限制向上偏移 (Screen Top)
            local maxPadding = (barHeight / 2) - (textHeight / 2)
            if vPadding > maxPadding then vPadding = maxPadding end
        elseif parent == YUI.YBar.bottomFrame then
            -- 底部条：限制向下偏移 (Screen Bottom)
            local minPadding = (textHeight / 2) - (barHeight / 2)
            if vPadding < minPadding then vPadding = minPadding end
        end
    end

    -- 应用 vPadding 到 content (相对于 frame)
    content:ClearAllPoints()
    content:SetPoint("CENTER", frame, "CENTER", 0, vPadding)
    
    -- textSep 在 content 中居中
    content.textSep:ClearAllPoints()
    content.textSep:SetPoint("CENTER", 0, 0)
    
    ApplyTextStyle(content.textM, font, size, globalDB)
    
    self:ApplyTextColors(content, db)
    
    -- 立即更新时间
    -- 预计算固定宽度
    if not self.dummyText then
        self.dummyText = GUI2:CreateText(content, "", "font.size.sm", "color.ybar.text")
    end
    ApplyFont(self.dummyText, font, size, "OUTLINE")
    self.dummyText:SetText("88:88")
    local widthH = self.dummyText:GetStringWidth()

    self.dummyText:SetText("88")
    local widthM = self.dummyText:GetStringWidth()
    
    self.dummyText:SetText(":")
    local widthSep = self.dummyText:GetStringWidth()
    
    widthH = math.ceil(widthH or 0) + 2
    widthM = math.ceil(widthM or 0) + 2
    widthSep = math.ceil(widthSep or 0) + 2
    self.fixedWidth = widthH + widthSep + widthM + 2

    content.textH:SetWidth(widthH)
    content.textH:SetJustifyH("RIGHT")
    content.textSep:SetWidth(widthSep)
    content.textSep:SetJustifyH("CENTER")
    content.textM:SetWidth(widthM)
    content.textM:SetJustifyH("LEFT")
    
    self.dummyText:Hide()
    
    -- 更新 content 尺寸以匹配内容 (宽度)
    content:SetWidth(self.fixedWidth)
    self:UpdateTimeText(content)
    if self._runtimeAttached then
        self:RefreshRuntime(true)
    end
    content:SetHeight(size)
end

function Module:GetWidth()
    local db = GetYBarDB() and GetYBarDB().Clock or {}
    local padding = db.padding or 0
    
    if self.fixedWidth then
        return self.fixedWidth + (padding * 2)
    end
    
    if self.content and self.content.textH and self.content.textSep and self.content.textM then
        return self.content.textH:GetStringWidth() + self.content.textSep:GetStringWidth() + self.content.textM:GetStringWidth() + (padding * 2)
    end
    return 50 -- 默认宽度
end

function Module:Update()
    self:UpdateBarItem()
end

function Module:RefreshRuntime(skipTimeUpdate)
    if not self._runtimeAttached then
        StopClockTicker()
        StopClockFlashDriver(self.content)
        return
    end

    StartClockTicker()
    StartClockFlashDriver(self.content)

    if not skipTimeUpdate then
        self:UpdateTimeText()
    end
end

if not context then
YBar:RegisterModule(Module, {
    id = "ybar.clock",
    parent = "ybar",
    product = "ybar",
    scope = "ybar",
    dependencies = {"ybar", "core.event", "core.api", "core.locale"},
    defaultEnabled = true,
})
end

function Module:GetOptions()
    local S = YUI.Settings

    local fontOptions = BuildFontOptions()
    local defaultFont = NormalizeFontKey(GetDefaultFontKey())

    local function BinaryChoice(label, leftText, rightText, defaultValue, getValue, setValue)
        return {
            type = "binarychoice",
            label = label,
            inlineLabel = true,
            width = 220,
            labelWidth = 90,
            controlWidth = 120,
            values = {
                { text = leftText, value = false },
                { text = rightText, value = true },
            },
            default = defaultValue,
            get = getValue,
            set = setValue,
        }
    end

    local function InlineSwitch(label, defaultValue, getValue, setValue)
        return {
            type = "switch",
            label = label,
            inlineLabel = true,
            width = 220,
            labelWidth = 90,
            controlWidth = 60,
            leftText = LC["common.off"],
            rightText = LC["common.on"],
            default = defaultValue,
            get = getValue,
            set = setValue,
        }
    end
    
    local options = {
        {
            type = "row",
            children = {
                {
                    type = "dropdown",
                    label = LC["common.font"],
                    inlineLabel = true,
                    width = 220,
                    labelWidth = 90,
                    controlWidth = 120,
                    default = defaultFont,
                    options = fontOptions,
                    get = function()
                        return NormalizeFontKey(GetClockFont(EnsureClockDB()))
                    end,
                    set = function(val)
                        EnsureClockDB().font = NormalizeFontKey(val)
                        RefreshClockLayout()
                    end
                },
                {
                    type = "slider",
                    label = LC["common.font_size"],
                    inline = true,
                    inputWidth = 56,
                    labelWidth = 90,
                    width = 220,
                    min = 8, max = 64, step = 1,
                    get = function() return EnsureClockDB().fontSize or DEFAULT_SIZE end,
                    set = function(val)
                        EnsureClockDB().fontSize = val
                        RefreshClockLayout()
                    end
                },
            }
        },
        {
            type = "row",
            children = {
                {
                    type = "slider",
                    label = LC["common.horizontal_padding"],
                    inline = true,
                    inputWidth = 56,
                    labelWidth = 90,
                    width = 220,
                    min = 0, max = 500, step = 1,
                    get = function() return GetYBarDB().Clock and GetYBarDB().Clock.padding or 0 end,
                    set = function(val)
                        if not GetYBarDB().Clock then GetYBarDB().Clock = {} end
                        GetYBarDB().Clock.padding = val
                        if YUI.YBar then YUI.YBar:UpdateLayout() end
                    end
                },
                {
                    type = "slider",
                    label = L["clock.option.text_vertical_offset"],
                    tooltip = L["clock.option.text_vertical_offset_help"],
                    inline = true,
                    inputWidth = 56,
                    labelWidth = 90,
                    width = 220,
                    min = -200, max = 200, step = 1,
                    get = function() return GetYBarDB().Clock and GetYBarDB().Clock.vPadding or 0 end,
                    set = function(val)
                        if not GetYBarDB().Clock then GetYBarDB().Clock = {} end
                        GetYBarDB().Clock.vPadding = val
                        if YUI.YBar then YUI.YBar:UpdateLayout() end
                    end
                }
            }
        },
        { type = "space", height = 20 },
        {type = "row", children = {
            InlineSwitch(
                L["clock.option.colon_flash"],
                false,
                function()
                    if GetYBarDB().Clock and GetYBarDB().Clock.flash ~= nil then
                        return GetYBarDB().Clock.flash
                    end
                    return false 
                end,
                function(val)
                    if not GetYBarDB().Clock then GetYBarDB().Clock = {} end
                    GetYBarDB().Clock.flash = val
                    Module:RefreshRuntime()
                end
            ),
            InlineSwitch(
                L["clock.option.colon_class_color"],
                false,
                function()
                    if GetYBarDB().Clock and GetYBarDB().Clock.colonClassColor ~= nil then
                        return GetYBarDB().Clock.colonClassColor
                    end
                    return false 
                end,
                function(val)
                    if not GetYBarDB().Clock then GetYBarDB().Clock = {} end
                    GetYBarDB().Clock.colonClassColor = val
                    if YUI.YBar then YUI.YBar:UpdateLayout() end
                end
            ),
        }},
        {type = "row", children = {
            BinaryChoice(
                L["clock.option.time_format"],
                "12H",
                "24H",
                true,
                function()
                    if GetYBarDB().Clock and GetYBarDB().Clock.use24Hour ~= nil then
                        return GetYBarDB().Clock.use24Hour
                    end
                    return true
                end,
                function(val)
                    if not GetYBarDB().Clock then GetYBarDB().Clock = {} end
                    GetYBarDB().Clock.use24Hour = val
                    if YUI.YBar then YUI.YBar:UpdateLayout() end
                end
            ),
            BinaryChoice(
                L["clock.option.time_source"],
                L["clock.option.server"],
                L["clock.option.local"],
                false,
                function()
                    if GetYBarDB().Clock and GetYBarDB().Clock.useLocalTime ~= nil then
                        return GetYBarDB().Clock.useLocalTime
                    end
                    return false
                end,
                function(val)
                    if not GetYBarDB().Clock then GetYBarDB().Clock = {} end
                    GetYBarDB().Clock.useLocalTime = val
                    if YUI.YBar then YUI.YBar:UpdateLayout() end
                end
            ),
        }},
        {
            type = "divider",
            label = L["clock.option.combat_time"],
            width = 400,
            alignLeft = true,
        },
        {type = "row", children = {
            InlineSwitch(
                L["clock.option.combat_time"],
                true,
                function()
                    if GetYBarDB().Clock and GetYBarDB().Clock.autoCombatTime ~= nil then
                        return GetYBarDB().Clock.autoCombatTime
                    end
                    return true
                end,
                function(val)
                    EnsureClockDB().autoCombatTime = val
                    Module:UpdateTimeText()
                end
            ),
            {
                type = "color",
                label = L["clock.option.combat_time_color"],
                width = 180,
                hasAlpha = true,
                default = DEFAULT_COMBAT_TIME_COLOR,
                get = function()
                    return GetYBarDB().Clock and GetYBarDB().Clock.combatTimeColor or DEFAULT_COMBAT_TIME_COLOR
                end,
                set = function(val)
                    EnsureClockDB().combatTimeColor = val
                    Module:UpdateTimeText()
                end
            },
        }},
        {
            type = "dropdown",
            label = L["clock.option.combat_time_scene"],
            inlineLabel = true,
            width = 220,
            labelWidth = 90,
            controlWidth = 120,
            default = DEFAULT_COMBAT_TIME_SCENE,
            options = {
                { text = L["clock.option.scene_all"], value = "all" },
                { text = L["clock.option.scene_group"], value = "group" },
                { text = L["clock.option.scene_instance"], value = "instance" },
            },
            get = function()
                return GetYBarDB().Clock and GetYBarDB().Clock.combatTimeScene or DEFAULT_COMBAT_TIME_SCENE
            end,
            set = function(val)
                local db = EnsureClockDB()
                db.combatTimeScene = val or DEFAULT_COMBAT_TIME_SCENE
                if Module.inCombatTimeMode then
                    Module:UpdateCombatTimeScene(db)
                end
                Module:UpdateTimeText()
            end
        }
    }
    return options
end

Module.moduleType = "Clock"
Module.instanceContext = context
return Module
end

local YBar = _G.YUI.YBar
YBar.ModuleFactories = YBar.ModuleFactories or {}
YBar.ModuleFactories.Clock = CreateInstance
CreateInstance()

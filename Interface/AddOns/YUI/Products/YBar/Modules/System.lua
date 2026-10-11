local YUI = _G.YUI
local function GetYBarDB()
    if YUI.YBar and YUI.YBar.GetModuleRoot then return YUI.YBar:GetModuleRoot("System") end
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
local API = YUI.WOW_API
local SystemAPI = YUI.API and YUI.API.System or API
local UnitAPI = YUI.API and YUI.API.Unit or API
local FrameAPI = YUI.API and YUI.API.Frame or API
local CombatAPI = YUI.API and YUI.API.Combat or API
local LSM = LibStub("LibSharedMedia-3.0")
local Module = YBar.Module:New("System")
local L = YUI.Locale:Get("YBar")
local LS = YUI.Locale:Get("SystemMetrics")
local LC = YUI.Locale:Get("Core")

-- 常量与配置
local UPDATE_INTERVAL = 1.0
local DEFAULT_SIZE = 14
local DEFAULT_SPACING = 5
local DEFAULT_CPU_SPIKE_THRESHOLD_MS = 10
local DEFAULT_FONT = STANDARD_TEXT_FONT
local SPELL_QUEUE_WINDOW_CVAR = "SpellQueueWindow"
local VALID_CPU_SPIKE_THRESHOLDS = {
    [1] = true,
    [5] = true,
    [10] = true,
    [50] = true,
}
-- 颜色默认值
local COLOR_SMOOTH = YUI.SystemMetrics.Display.Defaults.colorSmooth          -- 流畅 (白色)
local COLOR_LAG    = YUI.SystemMetrics.Display.Defaults.colorLag -- 卡顿 (黄色)
local COLOR_BAD    = YUI.SystemMetrics.Display.Defaults.colorBad -- PPT (红色)

-- 显示风格常量
local STYLE_STANDARD = "STANDARD"   -- 标准 (A): 数值 + 单位 (120 fps)

local function EnsureModuleDB()
    local ybarDB = GetYBarDB()
    if type(ybarDB) ~= "table" then
        return nil
    end

    if type(ybarDB.System) ~= "table" then
        ybarDB.System = {}
    end

    local db = ybarDB.System
    if db.displayStyle == nil then db.displayStyle = STYLE_STANDARD end
    if db.size == nil then db.size = DEFAULT_SIZE end
    if db.spacing == nil then db.spacing = DEFAULT_SPACING end
    if db.enableTolerance == nil then db.enableTolerance = true end
    if db.attachToClock == nil then db.attachToClock = "NONE" end
    if db.attachPadding == nil then db.attachPadding = 2 end
    if type(db.mergeAddonFamilies) ~= "boolean" then db.mergeAddonFamilies = true end
    local threshold = tonumber(db.cpuSpikeThresholdMs)
    if not VALID_CPU_SPIKE_THRESHOLDS[threshold] then
        threshold = DEFAULT_CPU_SPIKE_THRESHOLD_MS
    end
    db.cpuSpikeThresholdMs = threshold
    if db.colorSmooth == nil then db.colorSmooth = COLOR_SMOOTH end
    if db.colorLag == nil then db.colorLag = COLOR_LAG end
    if db.colorBad == nil then db.colorBad = COLOR_BAD end

    YUI.SystemMetrics.Display:Normalize(db)
    Module.db = db
    return db
end

local function GetSystemDB()
    if type(Module.db) == "table" then
        return Module.db
    end
    return EnsureModuleDB() or {}
end

local function IsSystemReady(frame)
    return not Module._hasError and frame and frame == Module.frame and
        not frame.ybarErrorPlaceholder and not frame.errorText and
        Module.content and type(Module.buttons) == "table"
end

local function SystemOnUpdate(frame, elapsed)
    if not IsSystemReady(frame) then return end

    frame.timer = (frame.timer or 0) + elapsed
    if frame.timer > UPDATE_INTERVAL then
        frame.timer = 0
        Module:RefreshRuntimeValues(false)
    end
end

-- 辅助函数

local function GetSystemCVar(name)
    if SystemAPI and SystemAPI.GetCVar then
        return SystemAPI.GetCVar(name)
    end

    if GetCVar then
        return GetCVar(name)
    end

    return nil
end

local function SetSystemCVar(name, value)
    if SystemAPI and SystemAPI.SetCVar then
        return SystemAPI.SetCVar(name, value)
    end

    if SetCVar then
        SetCVar(name, value)
        return true
    end

    return false
end

local function GetSpellQueueWindowValue()
    local value
    if C_Spell and C_Spell.GetSpellQueueWindow then
        local ok, result = pcall(C_Spell.GetSpellQueueWindow)
        if ok then value = result end
    end

    if value == nil then
        value = GetSystemCVar(SPELL_QUEUE_WINDOW_CVAR)
    end

    return tostring(value or 0)
end

local function IsSpellQueueWindowCVar(name)
    return type(name) == "string" and name:lower() == SPELL_QUEUE_WINDOW_CVAR:lower()
end

local function OpenLagToleranceSettings()
    if YUI.Settings and YUI.Settings.OpenComponentFeature then
        YUI.Settings:OpenComponentFeature("LagTolerance")
    elseif YUI.Components and YUI.Components.OpenFeatureSettings then
        YUI.Components:OpenFeatureSettings("LagTolerance")
    end
end

local function GetLagToleranceTooltipSummary()
    local feature = YUI.Components and YUI.Components.features and YUI.Components.features.LagTolerance
    if not feature or not feature.GetTooltipSummary then return nil end

    local ok, summary = pcall(feature.GetTooltipSummary, feature)
    if ok and type(summary) == "string" and summary ~= "" then return summary end
    return nil
end

local function GetFormattedText(style, value, metricType, isHovered, classColorHex, db)
    return YUI.SystemMetrics.Display:FormatText(style,metricType,value,db,
        isHovered and classColorHex or nil)
end

-- 系统 Tooltip 逻辑

local function GetHoverColorHex()
    if GUI2 and GUI2.GetColor then
        local r, g, b = GUI2:GetColor("color.baritem.hoverText", { 1, 0.82, 0, 1 })
        return CreateColor(r, g, b):GenerateHexColor()
    end
    return "ffffd100"
end

local function ApplyButtonText(btn, text, forceLayout)
    if not btn or not btn.text then return end

    if forceLayout or btn.renderedText ~= text then
        btn.text:SetText(text)
        btn.renderedText = text
    end

    if forceLayout or btn.renderedHeight == nil then
        local height = btn.text:GetStringHeight()
        if forceLayout or btn.renderedHeight ~= height then
            btn:SetHeight(height)
            btn.renderedHeight = height
        end
    end
end

local function RenderMetricButton(btn, metricType, value, forceLayout)
    if not btn or not btn.text then return end

    local style = Module.displayStyle or STYLE_STANDARD
    local hovered = btn.isHovered == true
    local hoverColorHex = Module.hoverColorHex or GetHoverColorHex()
    local db = Module.displayDB or GetSystemDB()

    if forceLayout or btn.renderedValue ~= value or btn.renderedMetricType ~= metricType or
        btn.renderedStyle ~= style or btn.renderedHovered ~= hovered or
        btn.renderedHoverColorHex ~= hoverColorHex then
        local text = GetFormattedText(style, value, metricType, hovered, hoverColorHex, db)
        ApplyButtonText(btn, text, forceLayout)
        btn.renderedValue = value
        btn.renderedMetricType = metricType
        btn.renderedStyle = style
        btn.renderedHovered = hovered
        btn.renderedHoverColorHex = hoverColorHex
    end
end

local function ClearButtonRenderState(btn)
    if not btn then return end

    btn.renderedText = nil
    btn.renderedHeight = nil
    btn.renderedValue = nil
    btn.renderedMetricType = nil
    btn.renderedStyle = nil
    btn.renderedHovered = nil
    btn.renderedHoverColorHex = nil
end

local metrics = assert(YUI.SystemMetrics, "SystemMetrics load order"):Bind(Module, {
    getConfig = GetSystemDB,
    isReady = IsSystemReady,
    probePrefix = "product.ybar",
    pinnedName = "YUI_OrbitInfoBar_SystemPinnedTooltip",
    openSettings = function() YUI:OpenYBarModuleSettings("System") end,
    onEnter = function(frame) if YBar.OnModuleEnter then YBar:OnModuleEnter(frame) end end,
    onLeave = function(frame) if YBar.OnModuleLeave then YBar:OnModuleLeave(frame) end end,
    createMetricButton = function(parent, metric)
        local btn = GUI2:CreateButtonFrame(parent)
        btn.statusText, btn.text = YBar:CreateStatusText(btn, {
            variant = "single", value = "", width = metric == "FPS" and 36 or 48,
            height = DEFAULT_SIZE + 6, justifyH = "CENTER", colorKey = "color.ybar.text",
        })
        btn.text:ClearAllPoints()
        btn.text:SetPoint("CENTER", 0, 0)
        local db = GetSystemDB()
        btn.text:SetFont(Module.displayFontPath or YBar:ResolveFontPath(db.font, DEFAULT_FONT, LSM),
            Module.displaySize or db.size or DEFAULT_SIZE, "")
        return btn
    end,
    renderMetric = RenderMetricButton,
    installActions = function(btn)
        btn.ybarOnClick = btn.metricOnClick
        YBar:CreateActionHost(btn, {
            secure = false,
            onEnter = function(_, owner) local fn = owner:GetScript("OnEnter"); if fn then fn(owner) end end,
            onLeave = function(_, owner) local fn = owner:GetScript("OnLeave"); if fn then fn(owner) end end,
        })
        if btn.actionHost then
            local function click(_, _, owner) owner:metricOnClick("LeftButton") end
            local function right(_, _, owner) owner:metricOnClick("RightButton") end
            btn.actionHost:SetActions({
                left = { kind = "custom", onClick = click },
                shiftLeft = { kind = "custom", onClick = click },
                altLeft = { kind = "custom", onClick = click },
                right = { kind = "custom", onClick = right },
                shiftRight = { kind = "custom", onClick = right },
            })
        end
    end,
})
local RestoreCPUCountResetState = metrics.RestoreCPUCountResetState
local CancelUsageRefresh = metrics.CancelUsageRefresh
local ClearUsageTooltipCache = metrics.ClearUsageTooltipCache
local ResetUsageGameTooltipLayout = metrics.ResetUsageGameTooltipLayout
local SystemRuntimeTickerCallback = metrics.SystemRuntimeTickerCallback

-- 模块实现

function Module:OnInitialize()
    self.db = EnsureModuleDB() or {}
    RestoreCPUCountResetState()
    
    self.frame = nil
    self.content = nil
    self.buttons = {}
    self.pinnedTooltipFrame = nil
    self.pinnedTooltipTicker = nil
    self.showMemory = false -- 默认状态逻辑：false 表示“尽可能显示 CPU”，true 表示“强制显示内存”
    self.loginTime = CombatAPI.GetTime()
    
    local _, class = UnitAPI.UnitClass("player")
    local color = UnitAPI.GetClassColor(class)
    self.classColorHex = color and color:GenerateHexColor() or "ffffffff"
    
    EnsureModuleDB()
    self:RefreshDisplayCache(self.db)
end

function Module:RefreshDisplayCache(db, ybarDB, fontPath, size)
    db = db or GetSystemDB()
    ybarDB = ybarDB or GetYBarDB() or {}

    self.displayDB = db
    self.displayStyle = db.displayStyle or STYLE_STANDARD
    self.displayFontPath = fontPath or YBar:ResolveFontPath(db.font, DEFAULT_FONT, LSM)
    self.displaySize = size or db.size or DEFAULT_SIZE
    self.displayFontFlag = ybarDB.fontFlags or (ybarDB.fontOutline and "OUTLINE" or "")
    self.displayFontShadow = ybarDB.fontShadow == true
    self.hoverColorHex = GetHoverColorHex()
end

function Module:RefreshRuntimeValues(force)
    if not IsSystemReady(self.frame) then return end

    local buttons = self.buttons
    local fpsButton = buttons and buttons[1]
    if fpsButton and fpsButton.Update then
        fpsButton:Update(force == true)
    end

    local latencyButton = buttons and buttons[2]
    if latencyButton and latencyButton.Update then
        latencyButton:Update(force == true)
    end
end

function Module:RefreshToleranceButton(force)
    if not IsSystemReady(self.frame) then return end

    local btn = self.buttons and self.buttons[3]
    if not btn then return end

    if btn.Update then btn:Update(force == true) end

    if force and GameTooltip and GameTooltip.GetOwner then
        local owner = GameTooltip:GetOwner()
        if owner == btn and btn.RefreshTooltip then
            btn:RefreshTooltip()
        end
    end
end

function Module:OnCVarUpdate(event, cvarName)
    if not IsSystemReady(self.frame) then return end

    if IsSpellQueueWindowCVar(cvarName) then
        self:RefreshToleranceButton(true)
    end
end

function Module:AttachRuntime()
    if not IsSystemReady(self.frame) then return end

    if self.runtimeTicker and self.runtimeTicker.Cancel then
        self.runtimeTicker:Cancel()
    end
    self.runtimeTicker = nil

    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        self.frame.timer = nil
    end

    if C_Timer and C_Timer.NewTicker then
        self.runtimeTicker = C_Timer.NewTicker(UPDATE_INTERVAL, SystemRuntimeTickerCallback)
    elseif self.frame then
        self.frame:SetScript("OnUpdate", SystemOnUpdate)
    end

    if YUI.Event and not self.cvarUpdateHandle then
        self.cvarUpdateHandle = YUI.Event:On("CVAR_UPDATE", "OnCVarUpdate", self)
    end
    if YUI.Event and not self.addonLoadedHandle then
        self.addonLoadedHandle = YUI.Event:On("ADDON_LOADED", "OnAddonLoaded", self)
    end

    self:RefreshRuntimeValues(true)
    self:RefreshToleranceButton(true)
end

function Module:DetachRuntime()
    self:HidePinnedTooltip(true)

    if self.runtimeTicker and self.runtimeTicker.Cancel then
        self.runtimeTicker:Cancel()
    end
    self.runtimeTicker = nil

    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        self.frame.timer = nil
    end

    if YUI.Event and self.cvarUpdateHandle then
        YUI.Event:Off(self.cvarUpdateHandle)
        self.cvarUpdateHandle = nil
    end
    if YUI.Event and self.addonLoadedHandle then
        YUI.Event:Off(self.addonLoadedHandle)
        self.addonLoadedHandle = nil
    end

    CancelUsageRefresh()
    self.usageTooltipOwner = nil

    if GameTooltip and GameTooltip.GetOwner then
        local owner = GameTooltip:GetOwner()
        if owner then
            if owner == self.frame or owner == self.content then
                ResetUsageGameTooltipLayout()
                YUI.HideGameTooltip()
            elseif self.buttons then
                for _, btn in ipairs(self.buttons) do
                    if owner == btn or owner == btn.actionHost then
                        ResetUsageGameTooltipLayout()
                        YUI.HideGameTooltip()
                        break
                    end
                end
            end
        end
    end

    if self.buttons then
        for _, btn in ipairs(self.buttons) do
            if btn.SetScript then
                btn:SetScript("OnUpdate", nil)
            end
            btn.timer = nil
            btn.tooltipUpdateTimer = nil
            btn.lastShiftState = nil
            btn.isHovered = false
            ClearButtonRenderState(btn)
        end
    end
    ClearUsageTooltipCache()

    self._attachRetryCount = 0
    self._attachRetryPending = false

    if self.content and self.frame then
        self.content:SetParent(self.frame)
        self.content:ClearAllPoints()
        self.content:SetAllPoints(self.frame)
        self.content:Hide()
    end
end

function Module:CreateBarItem(parent)
    local container = YBar:CreateBarItem(parent, {
        variant = "bare",
        width = 10,
        height = 20,
        showIcon = false,
        text = false,
        value = false,
    })

    -- 创建内容框架 (用于承载按钮和文本)
    -- 当吸附到 Clock 时，这个 content 会被 reparent 到 Clock 模块
    local content = GUI2:CreateFrame(container)
    content:SetAllPoints(container)

    local buttons = {
        self:CreateFPSButton(content),
        self:CreateLatencyButton(content),
        self:CreateToleranceButton(content)
    }
    
    self.content = content
    self.buttons = buttons

    self.frame = container
    if not YUI.YBar or YUI.YBar:IsSubModuleEnabled(self.name) then
        self:AttachRuntime()
    end
    self:UpdateBarItem(container, parent)
    
    return container
end

function Module:UpdateButtons(force)
    if not IsSystemReady(self.frame) then return end

    if force ~= true then
        self:RefreshRuntimeValues(false)
        return
    end

    for _, btn in ipairs(self.buttons) do
        if btn.Update then btn:Update(true) end
    end
end

function Module:UpdateLayout(noDefer)
    if not IsSystemReady(self.frame) then return end
    
    local db = EnsureModuleDB()
    if not db then return end
    local spacing = db.spacing or DEFAULT_SPACING
    
    -- 检查吸附状态
    local isAttached = db.attachToClock and db.attachToClock ~= "NONE"
    if not isAttached then
        self._attachRetryCount = 0
        self._attachRetryPending = false
        self.content:Show()
    end
    
    local totalWidth = 0
    local visibleCount = 0
    
    -- 1. 计算总宽度
    for _, btn in ipairs(self.buttons) do
        if btn:IsShown() then
            local btnWidth = btn:GetWidth()
            totalWidth = totalWidth + btnWidth
            if visibleCount > 0 then
                totalWidth = totalWidth + spacing
            end
            visibleCount = visibleCount + 1
        end
    end
    
    -- 最小宽度
    if totalWidth == 0 then totalWidth = 10 end
    
    -- 2. 处理吸附逻辑
    local currentX = 0

    if isAttached then
        if not noDefer then
            local cm = YBar:GetModule("Clock")
            local cf = cm and cm.frame
            local ca = nil
            if cf and cf.textSep then
                ca = cf.textSep
            elseif cm and cm.content and cm.content.textSep then
                ca = cm.content.textSep
            end
            if cf and cf:IsShown() and ca then
                noDefer = true
            end
        end
        if not noDefer then
            if self._attachRetryPending then return end
            self._attachRetryPending = true
            self.frame:SetWidth(0.001)
            self.frame:Show()
            self.content:Hide()
            C_Timer.After(0, function()
                if not IsSystemReady(Module.frame) then return end
                local ybarDB = GetYBarDB()
                local sysDb = ybarDB and ybarDB.System
                if not sysDb or not sysDb.attachToClock or sysDb.attachToClock == "NONE" then
                    Module._attachRetryCount = 0
                    Module._attachRetryPending = false
                    Module.content:Show()
                    return
                end
                Module._attachRetryPending = false
                Module:UpdateLayout(true)
            end)
            return
        end

        local clockModule = YBar:GetModule("Clock")
        -- 吸附到 Clock 模块的时间文本部分 (textSep) 以确保居中
        local clockFrame = clockModule and clockModule.frame
        local clockAnchor = nil
        if clockFrame and clockFrame.textSep then
            clockAnchor = clockFrame.textSep
        elseif clockModule and clockModule.content and clockModule.content.textSep then
            clockAnchor = clockModule.content.textSep
        end

        if clockFrame and clockFrame:IsShown() and clockAnchor then
            self.content:Show()
            -- 重新挂载 content 到 Clock
            self.content:SetParent(clockFrame)
            self.content:ClearAllPoints()
            
            local attachPadding = db.attachPadding or 2

            -- 设置吸附点，吸附到时间文本的中心
            if db.attachToClock == "TOP" then
                self.content:SetPoint("BOTTOM", clockAnchor, "TOP", 0, attachPadding)
            elseif db.attachToClock == "BOTTOM" then
                self.content:SetPoint("TOP", clockAnchor, "BOTTOM", 0, -attachPadding)
            end
            
            -- 设置 content 尺寸
            self.content:SetSize(totalWidth, 20)
            -- 强制显示 (忽略 YBar 父级透明度控制)
            self.content:SetAlpha(1)
            
            -- 将主框架(占位符)宽度设为极小值，以便在 YBar 布局中不占位但保持链接
            self.frame:SetWidth(0.001)
            self.frame:Show()
            
            -- 居中对齐起始点
            currentX = -totalWidth / 2
            self._attachRetryCount = 0
            self._attachRetryPending = false
        else
            local clockOnBar = YBar.IsModuleOnBar and YBar:IsModuleOnBar("Clock")
            if clockOnBar then
                self._attachRetryCount = (self._attachRetryCount or 0) + 1
                if self._attachRetryCount <= 5 then
                    self.frame:SetWidth(0.001)
                    self.frame:Show()
                    self.content:Hide()
                    C_Timer.After(0, function()
                        if not IsSystemReady(Module.frame) then return end
                        local ybarDB = GetYBarDB()
                        local sysDb = ybarDB and ybarDB.System
                        if not sysDb or not sysDb.attachToClock or sysDb.attachToClock == "NONE" then
                            Module._attachRetryCount = 0
                            Module._attachRetryPending = false
                            Module.content:Show()
                            return
                        end
                        Module:UpdateLayout(true)
                    end)
                    return
                end
            end

            isAttached = false
            self._attachRetryCount = 0
            self._attachRetryPending = false
            self.content:Show()
        end
    end
    
    if not isAttached then
        -- 正常模式：挂载回主框架
        self.content:SetParent(self.frame)
        self.content:ClearAllPoints()
        self.content:SetAllPoints(self.frame)
        self.content:SetAlpha(1) -- 恢复默认，继承父级透明度
        
        if math.abs(self.frame:GetWidth() - totalWidth) > 0.1 then
            self.frame:SetWidth(totalWidth)
        end
    end
    
    -- 3. 布局按钮
    local prev = nil
    for _, btn in ipairs(self.buttons) do
        if btn:IsShown() then
            btn:ClearAllPoints()
            if isAttached then
                -- 居中布局 (基于 content 中心)
                btn:SetPoint("LEFT", self.content, "CENTER", currentX, 0)
                currentX = currentX + btn:GetWidth() + spacing
            else
                -- 默认左对齐
                if prev then
                    btn:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
                else
                    btn:SetPoint("LEFT", self.content, "LEFT", 0, 0)
                end
            end
            prev = btn
        end
    end
end

function Module:UpdateBarItem(frame, parent)
    if parent then self.parent = parent end
    if not frame then frame = self.frame end
    if not IsSystemReady(frame) then return end
    
    local db = EnsureModuleDB()
    if not db then return end
    local ybarDB = GetYBarDB() or {}
    local size = db.size or DEFAULT_SIZE
    local font = db.font
    local fontPath = YBar:ResolveFontPath(font, DEFAULT_FONT, LSM)
    local style = db.displayStyle or STYLE_STANDARD
    self:RefreshDisplayCache(db, ybarDB, fontPath, size)
    
    -- 计算固定布局的最大宽度 (使用 content 创建 FontString)
    if not self.dummyText then
        self.dummyText = GUI2:CreateText(self.content, "", "font.size.sm", "color.ybar.text")
        self.dummyText:Hide()
    end
    self.dummyText:SetFont(fontPath, size, "")
    
    -- 用三位数值预计算固定宽度，避免共享格式化将前导零压缩成一位。
    -- 使用 GetFormattedText 生成测试文本，状态参数传 nil
    local dummyVal = 888
    
    self.dummyText:SetText(GetFormattedText(style, dummyVal, "FPS", nil, nil, db))
    local fpsWidth = self.dummyText:GetStringWidth() + 2
    
    self.dummyText:SetText(GetFormattedText(style, dummyVal, "LATENCY", nil, nil, db))
    local latencyWidth = self.dummyText:GetStringWidth() + 2
    
    self.dummyText:SetText(GetFormattedText(style, dummyVal, "TOLERANCE", nil, nil, db))
    local toleranceWidth = self.dummyText:GetStringWidth() + 2

    -- 更新按钮样式
    local fontFlag = self.displayFontFlag or ""
    local fontShadow = self.displayFontShadow == true
    -- Apply every metric font before invoking any metric update callback.
    for _, btn in ipairs(self.buttons) do
        if btn.text then
            btn.text:SetFont(fontPath, size, fontFlag)
            
            if fontShadow then
                btn.text:SetShadowColor(0, 0, 0, 1)
                btn.text:SetShadowOffset(1, -1)
            else
                btn.text:SetShadowOffset(0, 0)
            end
            -- 固定宽度的文本居中
            btn.text:ClearAllPoints()
            btn.text:SetPoint("CENTER", 0, 0)
            ClearButtonRenderState(btn)
        end
    end

    for i, btn in ipairs(self.buttons) do
        -- 应用固定宽度
        if i == 1 then btn:SetWidth(fpsWidth)
        elseif i == 2 then btn:SetWidth(latencyWidth)
        elseif i == 3 then btn:SetWidth(toleranceWidth)
        end
        
        -- 触发更新以根据新字体大小刷新宽度
        if btn.Update then btn:Update(true) end
    end
    
    -- 容限可见性
    local enableTolerance = db.enableTolerance
    if enableTolerance == nil then enableTolerance = true end
    
    if self.buttons[3] then
        if enableTolerance then
            self.buttons[3]:Show()
        else
            self.buttons[3]:Hide()
        end
    end
    
    self:UpdateLayout()
end

function Module:GetWidth()
    if IsSystemReady(self.frame) then return self.frame:GetWidth() end
    return 100
end

-- 按钮创建器

function Module:CreateToleranceButton(parent)
    local btn = GUI2:CreateButtonFrame(parent)

    btn.statusText, btn.text = YBar:CreateStatusText(btn, {
        variant = "single",
        value = "",
        width = 48,
        height = DEFAULT_SIZE + 6,
        justifyH = "CENTER",
        colorKey = "color.ybar.text",
    })
    local text = btn.text
    text:ClearAllPoints()
    text:SetPoint("CENTER", 0, 0)
    
    -- 确保字体被初始化
    local db = GetSystemDB()
    local fontPath = Module.displayFontPath or YBar:ResolveFontPath(db.font, DEFAULT_FONT, LSM)
    local size = Module.displaySize or db.size or DEFAULT_SIZE
    text:SetFont(fontPath, size, "")
    
    btn.Update = function(self, force)
        if not IsSystemReady(Module.frame) or not self.text then return end

        if force or self.needsRefresh or self.lastValue == nil then
            local tolerance = GetSpellQueueWindowValue()
            self.lastValue = tolerance
            self.needsRefresh = false
            RenderMetricButton(self, "TOLERANCE", tolerance, force == true)
            return
        end

        RenderMetricButton(self, "TOLERANCE", self.lastValue or 0, force == true)
    end

    btn.needsRefresh = true
    btn:Update()
    
    -- btn:RegisterForClicks("AnyUp")
    -- btn:SetScript("OnClick", function(self, button)
    --     if button == "LeftButton" then
    --         if IsAltKeyDown() then
    --             YUI:OpenYBarModuleSettings("System")
    --             return
    --         end
    --         if YUI.Settings and YUI.Settings.Toggle then
    --              YUI.Settings:Toggle() 
                 
    --              if YUI.Settings.modules then
    --                  for _, mod in ipairs(YUI.Settings.modules) do
    --                      if mod.name == "延迟容限" then
    --                          YUI.Settings:SelectModule(mod)
    --                          break
    --                      end
    --                  end
    --              end
    --         end
    --     end
    -- end)
    
    btn.RefreshTooltip = function(self)
        if not IsSystemReady(Module.frame) then return end

        local tooltipAnchor = "ANCHOR_TOP"
        local yOffset = 20
        if self:GetBottom() > GetScreenHeight() / 2 then
            tooltipAnchor = "ANCHOR_BOTTOM"
            yOffset = -20
        end
        ResetUsageGameTooltipLayout()
        GameTooltip:SetOwner(self, tooltipAnchor, 0, yOffset)
        GameTooltip:ClearLines()
        local headerColor = CreateColor(1, 0.82, 0)
        local headerHex = headerColor:GenerateHexColor()
        local white = "|cffffffff"
        local gold = "|c" .. headerHex

        GameTooltip:AddDoubleLine(LS["system.tooltip.spell_queue_window"], GetSpellQueueWindowValue() .. " ms", 1, 0.82, 0, 0, 0.8, 1)
        GameTooltip:AddLine(" ")
        local lagToleranceSummary = GetLagToleranceTooltipSummary()
        if lagToleranceSummary then
            GameTooltip:AddLine(lagToleranceSummary, 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(format("%s%s: |r%s%s|r", white, LC["common.left_click"], gold, LS["system.action.open_lag_tolerance_settings"]))
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(format("|cff808080%s: %s|r", LC["common.alt_left_click"], LC["common.open_settings"]))
        GameTooltip:Show()
    end

    btn:SetScript("OnEnter", function(self)
        if not IsSystemReady(Module.frame) then return end

        if YBar and YBar.OnModuleEnter and Module.frame then YBar:OnModuleEnter(Module.frame) end
        self.isHovered = true
        self.needsRefresh = true
        if self.Update then self:Update() end
        self:RefreshTooltip()
    end)

    btn:SetScript("OnLeave", function(self)
        if not IsSystemReady(Module.frame) then return end

        if YBar and YBar.OnModuleLeave and Module.frame then YBar:OnModuleLeave(Module.frame) end
        self.isHovered = false
        self.needsRefresh = true
        if self.Update then self:Update() end
        YUI.HideGameTooltip()
    end)

    YBar:BindButtonActions(btn, {
        left = {
            kind = "custom",
            onClick = function()
                OpenLagToleranceSettings()
            end,
        },
        altLeft = {
            kind = "custom",
            onClick = function()
                YUI:OpenYBarModuleSettings("System")
            end,
        },
    }, {
        secure = false,
    })

    return btn
end

YBar:RegisterModule(Module, {
    id = "ybar.system",
    parent = "ybar",
    product = "ybar",
    scope = "ybar",
    dependencies = {"ybar", "core.api", "core.locale"},
    defaultEnabled = true,
})

function Module:GetOptions()
    local S = YUI.Settings
    local LSM = LibStub("LibSharedMedia-3.0")
    
    -- 准备字体选项
    local fontList = LSM:HashTable("font")
    local fontOptions = {}
    local defaultFont = nil
    for name, path in pairs(fontList) do
        table.insert(fontOptions, { text = name, value = path })
        if name == "默认" then defaultFont = path end
    end
    table.sort(fontOptions, function(a, b) return a.text < b.text end)

    local function GetDB()
        return EnsureModuleDB() or {}
    end

    local function RefreshSystemVisuals(forceLayout)
        if not IsSystemReady(Module.frame) then return end

        if forceLayout and Module.UpdateBarItem then
            Module:UpdateBarItem(Module.frame, Module.frame and Module.frame:GetParent())
        else
            Module:RefreshDisplayCache(GetDB())
            Module:UpdateButtons(true)
        end
    end

    local function RefreshCPUUsageTooltip()
        ClearUsageTooltipCache()
        Module:RefreshPinnedTooltip(true)
    end

    local displayFields=YUI.SystemMetrics.Display:BuildFields(GetDB,function(key)
        local layout=key=="displayStyle"
        RefreshSystemVisuals(layout)
        if layout and YUI.YBar then YUI.YBar:UpdateLayout() end
    end)
    local options = {
        displayFields[1],
        -- 第二行：字体、尺寸、间距
        {
            type = "dropdown",
            label = LC["common.font"],
            width = 220,
            default = defaultFont,
            options = fontOptions,
            get = function()
                return GetDB().font or defaultFont
            end,
            set = function(val)
                GetDB().font = val
                RefreshSystemVisuals(true)
                if YUI.YBar then YUI.YBar:UpdateLayout() end
            end
        },
        {
            type = "slider",
            label = LC["common.size"],
            inline = true,
            inputWidth = 56,
            width = 220,
            min = 10, max = 32, step = 1,
            get = function() return GetDB().size or DEFAULT_SIZE end,
            set = function(val)
                GetDB().size = val
                RefreshSystemVisuals(true)
                if YUI.YBar then YUI.YBar:UpdateLayout() end
            end
        },
        {
            type = "slider",
            label = LC["common.spacing"],
            inline = true,
            inputWidth = 56,
            width = 220,
            min = 0, max = 50, step = 1,
            get = function() return GetDB().spacing or DEFAULT_SPACING end,
            set = function(val)
                GetDB().spacing = val
                RefreshSystemVisuals(true)
                if YUI.YBar then YUI.YBar:UpdateLayout() end
            end
        },
        -- 第三行：吸附到时间、吸附间距 (紫色文本)
        {
            type = "dropdown",
            label = "|cffa335ee" .. L["system.option.attach_to_clock"] .. "|r",
            width = 220,
            default = "NONE",
            options = {
                { text = LC["common.none"], value = "NONE" },
                { text = LC["common.bottom"], value = "BOTTOM" },
                { text = LC["common.top"], value = "TOP" },
            },
            get = function() return GetDB().attachToClock or "NONE" end,
            set = function(val)
                GetDB().attachToClock = val
                RefreshSystemVisuals(true)
                if YUI.YBar then YUI.YBar:UpdateLayout() end
                -- 强制刷新当前模块的设置界面以更新隐藏状态
                if YUI.YBar and YUI.YBar.SettingsButtons and YUI.YBar.SettingsButtons["System"] then
                    YUI.YBar.SettingsButtons["System"]:Click()
                end
            end
        },
        {
            type = "slider",
            label = "|cffa335ee" .. L["system.option.attach_padding"] .. "|r",
            inline = true,
            inputWidth = 56,
            width = 220,
            min = 0, max = 50, step = 1,
            default = 2,
            hidden = function()
                local db = GetDB()
                return not db.attachToClock or db.attachToClock == "NONE"
            end,
            get = function() return GetDB().attachPadding or 2 end,
            set = function(val)
                GetDB().attachPadding = val
                RefreshSystemVisuals(true)
                if YUI.YBar then YUI.YBar:UpdateLayout() end
            end
        },
        -- 第四行：延迟容限
        {
            type = "checkbox",
            label = L["system.option.show_tolerance"],
            default = true,
            get = function() 
                 if GetDB().enableTolerance ~= nil then
                    return GetDB().enableTolerance
                 end
                 return true
            end,
            set = function(val)
                GetDB().enableTolerance = val
                RefreshSystemVisuals(true)
                if YUI.YBar then YUI.YBar:UpdateLayout() end
            end
        },
        {
            type = "divider",
            label = L["system.option.cpu_diagnostics"],
            alignLeft = true,
            width = 400,
        },
        {
            type = "checkbox",
            label = L["system.option.merge_addon_families"],
            default = true,
            get = function()
                return GetDB().mergeAddonFamilies ~= false
            end,
            set = function(val)
                GetDB().mergeAddonFamilies = val == true
                RefreshCPUUsageTooltip()
            end,
        },
        {
            type = "dropdown",
            label = L["system.option.cpu_spike_threshold"],
            width = 220,
            default = DEFAULT_CPU_SPIKE_THRESHOLD_MS,
            hidden = function()
                return YUI.IsRetail ~= true
            end,
            options = {
                { text = format(L["system.option.cpu_spike_threshold_value"], 1), value = 1 },
                { text = format(L["system.option.cpu_spike_threshold_value"], 5), value = 5 },
                { text = format(L["system.option.cpu_spike_threshold_value"], 10), value = 10 },
                { text = format(L["system.option.cpu_spike_threshold_value"], 50), value = 50 },
            },
            get = function()
                local value = tonumber(GetDB().cpuSpikeThresholdMs)
                return VALID_CPU_SPIKE_THRESHOLDS[value]
                    and value
                    or DEFAULT_CPU_SPIKE_THRESHOLD_MS
            end,
            set = function(val)
                val = tonumber(val)
                GetDB().cpuSpikeThresholdMs = VALID_CPU_SPIKE_THRESHOLDS[val]
                    and val
                    or DEFAULT_CPU_SPIKE_THRESHOLD_MS
                RefreshCPUUsageTooltip()
            end,
        },
        {
            type="divider",label=LS["system.option.value_colors"],alignLeft=true,width=400,
        },
    }
    for index=2,#displayFields do options[#options+1]=displayFields[index] end

    return options
end

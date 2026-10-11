local YUI = _G.YUI
local YMap = YUI and YUI.YMap
if not YMap then return end

local Widget = { active = false, writes = 0, layouts = 0, buttons = {} }
YMap.MetricsWidget = Widget
local GUI2 = YUI.GUI2
local metricConfig = { mergeAddonFamilies = true, cpuSpikeThresholdMs = 10 }

local function GetConfig()
    local db = YMap:GetDB()
    return db.minimap.squareAppearance.metrics, db.minimap.squareAppearance, db.minimap
end

local function Ready()
    local minimap = YMap.Minimap
    return Widget.active and minimap.active and minimap.appliedStyle == "square"
        and not minimap.editModeActive and _G.Minimap and _G.Minimap:IsShown()
end

function Widget:Stop()
    self.active = false
    YMap.CoordinateDriver:SetMetricsActive(false)
    if self.service then self.service:Stop() end
    if self.frame then self.frame:Hide() end
    if self.addonHandle then YUI.Event:Off(self.addonHandle); self.addonHandle = nil end
end

function Widget:Reflow()
    local config, appearance = self.config, self.appearance
    local owner = YMap.Minimap
    local fps, latency = self.buttons[1], self.buttons[2]
    local showFPS, showLatency = config.showFPS, config.showLatency
    local width = (showFPS and fps:GetWidth() or 0) + (showLatency and latency:GetWidth() or 0)
        + (showFPS and showLatency and (config.spacing or 12) or 0)
    local height = math.max(config.fontSize+2,showFPS and fps:GetHeight() or 0,showLatency and latency:GetHeight() or 0)
    local point,x,y = YMap.TextComponents:Placement(appearance, "metrics", owner)
    if width ~= self.lastWidth or height ~= self.lastHeight or x ~= self.lastX or y ~= self.lastY or point ~= self.lastPosition then
        self.frame:SetSize(width, height)
        self.frame:ClearAllPoints()
        self.frame:SetPoint(point, owner.border, point, x, y)
        fps:ClearAllPoints()
        fps:SetPoint("LEFT", self.frame, "LEFT", 0, 0)
        latency:ClearAllPoints()
        latency:SetPoint("RIGHT", self.frame, "RIGHT", 0, 0)
        self.separator:ClearAllPoints()
        self.separator:SetPoint("CENTER", fps, "RIGHT", (config.spacing or 12) / 2, 0)
        self.lastWidth, self.lastHeight, self.lastX, self.lastY, self.lastPosition = width, height, x, y, point
        self.layouts = self.layouts + 1
    end
    if showFPS and showLatency then self.separator:Show() else self.separator:Hide() end
    if showFPS then fps:Show() else fps:Hide() end
    if showLatency then latency:Show() else latency:Hide() end
end

local function RenderMetric(btn, metric, value, force)
    if value == btn.renderedValue and not force then return end
    btn.renderedValue = value
    local config = Widget.config
    local text=YUI.SystemMetrics.Display:FormatText(config.displayStyle,metric,value,config,nil,config.fontSize+2)
    if text ~= btn.renderedText then
        btn.text:SetText(text)
        btn.renderedText=text
        Widget.writes=Widget.writes+1
    end
    local width = math.ceil(btn.text:GetStringWidth())
    local height=btn.text.GetStringHeight and btn.text:GetStringHeight() or config.fontSize+2
    height=math.max(config.fontSize+2,height)
    if btn:GetWidth() ~= width or btn:GetHeight() ~= height then btn:SetSize(width,height) end
    Widget:Reflow()
end

function Widget:RefreshRuntimeValues(force)
    if not Ready() then return end
    local config = self.config
    if config.showFPS then self.buttons[1]:Update(force) end
    if config.showLatency then self.buttons[2]:Update(force) end
end

function Widget:UpdateButtons(force)
    self:RefreshRuntimeValues(force)
end

function Widget.Update()
    local config = Widget.config
    if not Ready() or not config or not config.enabled or (not config.showFPS and not config.showLatency) then
        Widget:Stop(); return
    end
    Widget:RefreshRuntimeValues(false)
end

local function CreateMetricButton(parent)
    local btn = GUI2:CreateButtonFrame(parent)
    btn:SetSize(1, 13)
    btn.text = GUI2:CreateText(btn, "", "font.size.sm", "color.text.primary")
    btn.text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.text:SetWordWrap(false)
    return btn
end

function Widget:EnsureVisuals()
    if self.frame then return end
    self.frame = GUI2:CreateFrame(YMap.Minimap.border, { kind = "YMapSystemMetrics", mouse = false })
    self.content = self.frame
    self.frame:Hide()
    self.separator = GUI2:CreateText(self.frame, "·", "font.size.sm", "color.text.primary")
    self.service = YUI.SystemMetrics:Bind(self, {
        getConfig = function() return metricConfig end,
        isReady = Ready,
        probePrefix = "product.ymap-metrics",
        cpuProbeLocaleKey = "cpu_watch.probe.ymap_metrics_cpu_panel",
        systemProbeLocaleKey = "cpu_watch.probe.ymap_metrics_system",
        pinnedProbeLocaleKey = "cpu_watch.probe.ymap_metrics_pinned",
        pinnedName = "YUI_YMap_SystemPinnedTooltip",
        openSettings = function() YMap:OpenSettings("minimap") end,
        createMetricButton = CreateMetricButton,
        renderMetric = RenderMetric,
        onEnter = function() Widget:Refresh() end,
        onLeave = function() Widget:Refresh() end,
        installActions = function(btn)
            btn:SetScript("OnClick", function(self, button) self:metricOnClick(button) end)
        end,
    })
    self.buttons[1] = self:CreateFPSButton(self.frame)
    self.buttons[2] = self:CreateLatencyButton(self.frame)
    self.service.RestoreCPUCountResetState()
    self.loginTime = YUI.API.Combat.GetTime()
end

function Widget:Refresh()
    local owner = YMap.Minimap
    local config, appearance, minimapConfig = GetConfig()
    self.config, self.appearance = config, appearance
    local hovered = owner.minimapHovered or (self.frame and self.frame:IsMouseOver())
    if owner.active ~= true or owner.appliedStyle ~= "square" or minimapConfig.style ~= "square"
        or not owner.border or owner.editModeActive
        or not _G.Minimap or not _G.Minimap:IsShown() or not config.enabled
        or (not config.showFPS and not config.showLatency)
        or (config.displayMode == "hover" and not hovered) then self:Stop(); return end
    self:EnsureVisuals()
    local wasActive = self.active
    self.active = true
    self.frame:Show()
    YMap.TextComponents:Apply(self.buttons[1].text, config, nil, false)
    YMap.TextComponents:Apply(self.buttons[2].text, config, nil, false)
    YMap.TextComponents:Apply(self.separator, config, nil, false)
    local flagsChanged = self.showFPS ~= config.showFPS or self.showLatency ~= config.showLatency
    if flagsChanged and self.service then self.service:Stop() end
    self.showFPS, self.showLatency = config.showFPS, config.showLatency
    -- Configuration refreshes may change formatting or threshold colors at the same reading.
    self:RefreshRuntimeValues(true)
    self:Reflow()
    YMap.CoordinateDriver:RegisterMetricsConsumer(self.Update)
    YMap.CoordinateDriver:SetMetricsActive(true)
    if YUI.Event and not self.addonHandle then
        self.addonHandle = YUI.Event:On("ADDON_LOADED", "OnAddonLoaded", self)
    end
end

function Widget:GetStats(target)
    target.minimapMetricsActive = self.active
    target.minimapMetricsWrites, target.minimapMetricsLayouts = self.writes, self.layouts
    local service = self.service and self.service.GetStats()
    target.minimapMetricsTooltipRefreshPending = service and service.refreshPending or false
    target.minimapMetricsPinnedShown = service and service.pinnedShown or false
    return target
end

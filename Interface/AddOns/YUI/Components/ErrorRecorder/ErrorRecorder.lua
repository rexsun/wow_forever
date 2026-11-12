local addonName = ...
local YUI = _G.YUI
if addonName ~= "YUI" or not YUI then return end
local GUI, S = YUI.GUI, YUI.Settings
local L = YUI.Locale:Get("ErrorRecorder")
local Report = YUI.ErrorReport
local TOOLTIP_ACTIONS = { "left_click", "right_click", "reload", "clear_hint", "drag" }
local tooltipLayouts, tooltipHooks = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local function ResetTooltipLayout(tip)
    local lines = tooltipLayouts[tip]
    if not lines then return end
    tooltipLayouts[tip] = nil
    for _, line in ipairs(lines) do
        line:SetWidth(0)
        if line.SetMaxLines then line:SetMaxLines(0) end
    end
    tip:SetMinimumWidth(0, false)
end
local function ExpandTooltip(tip)
    if not tip.SetMinimumWidth or not tip.HookScript then return end
    if not tooltipHooks[tip] then
        tip:HookScript("OnTooltipCleared", ResetTooltipLayout)
        tip:HookScript("OnHide", ResetTooltipLayout)
        tooltipHooks[tip] = true
    end
    ResetTooltipLayout(tip)
    tooltipLayouts[tip] = {}
    tip:SetMinimumWidth(460, true)
end
local E = { active = false, icons = {}, refreshes = 0 }
YUI.ErrorRecorder = E
YUI.Assets:RegisterComponentRoot("ErrorRecorder", "Interface\\AddOns\\" .. addonName .. "\\Components\\ErrorRecorder\\Media")

function E:GetCollector() return _G.YUI_ErrorCollector end
function E:GetConfig()
    if not YUI.DB:IsReady() then return nil end
    local global = YUI.DB:GetGlobal("suite")
    if not global then return nil end
    if type(global.ErrorRecorder) ~= "table" then global.ErrorRecorder = {} end
    local config = global.ErrorRecorder
    if config.enabled == nil then config.enabled = true end
    if config.minimap == nil then config.minimap = true end
    if type(config.angle) ~= "number" then config.angle = 225 end
    return config
end
function E:HasExternalViewer()
    local viewer = _G.BugSack
    return type(viewer) == "table" and viewer.healthCheck == true and type(viewer.OpenSack) == "function"
end
function E:IsEnabled()
    local config, collector = self:GetConfig(), self:GetCollector()
    return self.active and config and config.enabled ~= false and not self:HasExternalViewer()
        and collector and collector.current ~= nil and collector.provider ~= nil or false
end
function E:GetCount()
    local collector = self:GetCollector()
    return collector and collector:GetCount() or 0
end
function E:GetIcon()
    return YUI.Assets:Component("ErrorRecorder", self:GetCount() > 0 and "bag-red.tga" or "bag-green.tga")
end
function E:Tooltip(tip)
    ResetTooltipLayout(tip)
    tip:AddLine(Report:Tint("color.tooltip.heading", L["name"]))
    if self:HasExternalViewer() then
        tip:AddLine(Report:Tint("color.tooltip.warning", L["viewer.yield"]), 1, 1, 1, true)
        tip:AddLine(Report:Tint("color.tooltip.action", L["right_click"]), 1, 1, 1, true)
        return
    end
    local collector = self:GetCollector()
    local saved = collector and (collector.GetSavedCount and collector:GetSavedCount() or collector.retainedRecords) or 0
    tip:AddLine(Report:Tint("color.tooltip.secondary", L["count"]:format(self:GetCount(), saved or 0)))
    if not collector or not collector.provider then
        tip:AddLine(collector and collector.conflict and L["conflict"]:format(collector.conflict) or L["missing"], 1, .6, .3, true)
    else
        if collector:GetCount() > 0 then ExpandTooltip(tip) end
        if collector.provider.IsPaused and collector.provider:IsPaused() then tip:AddLine(L["paused"], 1, .6, .3, true) end
        for number, item in ipairs(Report:Recent(collector.current.records, 9)) do
            tip:AddLine(Report:TooltipLine(item.record, number), 1, 1, 1, true)
            if tooltipLayouts[tip] and tip.GetLeftLine and tip.NumLines then
                local line = tip:GetLeftLine(tip:NumLines())
                if line then
                    line:SetWidth(440)
                    if line.SetMaxLines then line:SetMaxLines(2) end
                    local lines = tooltipLayouts[tip]; lines[#lines + 1] = line
                end
            end
        end
        tip:AddLine(" ")
        for _, action in ipairs(TOOLTIP_ACTIONS) do
            local key, label = L[action]:match("^(.-)：%s*(.*)$")
            local separator = key and "：" or ": "
            if not key then key, label = L[action]:match("^(.-):%s*(.*)$") end
            tip:AddLine(key and (Report:Tint("color.tooltip.warning", key .. separator) .. Report:Tint("color.tooltip.settings", label))
                or Report:Tint("color.tooltip.action", L[action]), 1, 1, 1, false)
        end
    end
end
function E:Click(anchor, button)
    if button == "RightButton" then self:OpenSettings(anchor)
    elseif button ~= "LeftButton" then return
    elseif IsShiftKeyDown() then ReloadUI()
    elseif IsAltKeyDown() then
        local collector = self:GetCollector()
        if not collector then return end
        collector:ClearHistory()
        self.selectedSession, self.selectedRecord, self.copyAll = collector.current, nil, false
        if self.pendingRefresh then self.pendingRefresh:Cancel(); self.pendingRefresh = nil end
        self:RefreshView(true)
    elseif self:IsEnabled() then self:Toggle() end
end
function E:CreateIcon(parent, size, name)
    local button = GUI:CreateButtonFrame(parent, { name = name, width = size, height = size })
    button.icon = GUI:CreateTexture(button, { texture = self:GetIcon(), layer = "ARTWORK" })
    button.icon:SetAllPoints(button)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT"); GameTooltip:ClearLines(); E:Tooltip(GameTooltip); GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() YUI.HideGameTooltip() end)
    button:SetScript("OnHide", function(owner)
        if GameTooltip:GetOwner() == owner then YUI.HideGameTooltip() end
    end)
    self.icons[#self.icons + 1] = button.icon
    return button
end

function E:PositionMinimap()
    local button, config = self.minimap, self:GetConfig()
    if not button or not config then return end
    local angle = math.rad(config.angle % 360)
    local x, y = math.cos(angle), math.sin(angle)
    local shape = type(_G.GetMinimapShape) == "function" and _G.GetMinimapShape() or "ROUND"
    -- Circular and square minimaps are the supported layout shapes.
    if shape == "SQUARE" then
        local scale = 1 / math.max(math.abs(x), math.abs(y))
        x, y = x * scale, y * scale
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * (Minimap:GetWidth() / 2 + 7), y * (Minimap:GetHeight() / 2 + 7))
end
function E:StopDrag()
    if self.minimap then self.minimap:SetScript("OnUpdate", nil); self.minimap.dragging = nil end
end
function E:EnsureMinimap()
    if self.minimap or not Minimap then return end
    local button = self:CreateIcon(Minimap, 30, "YUIErrorRecorderMinimap")
    self.minimap = button
    button.yuiDrawerBorderless = true
    button:SetFrameStrata("MEDIUM"); button:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnMouseDown", function(owner) if not owner.dragging then owner.wasDragged = nil end end)
    button:SetScript("OnClick", function(owner, mouse) if not owner.wasDragged then E:Click(owner, mouse) end; owner.wasDragged = nil end)
    button:SetScript("OnDragStart", function(owner)
        owner.dragging, owner.wasDragged = true, true
        owner:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local config = E:GetConfig()
            if config and mx and my then
                config.angle = math.deg(math.atan2(y / scale - my, x / scale - mx)) % 360
                E:PositionMinimap()
            end
        end)
    end)
    button:SetScript("OnDragStop", function() E:StopDrag() end)
    button:HookScript("OnHide", function() E:StopDrag() end)
    Minimap:HookScript("OnSizeChanged", function() if E.active then E:PositionMinimap() end end)
    self:PositionMinimap()
end
function E:AttachSettingsEntry()
    local elements = S and S.Elements
    local scale = elements and elements.scaleControl
    if not scale or self.settingsEntry then return end
    scale.slider:SetWidth(math.max(60, scale.slider:GetWidth() - 34))
    local entry = self:CreateIcon(elements.nav, 28)
    entry.icon:ClearAllPoints(); entry.icon:SetSize(20, 20); entry.icon:SetPoint("CENTER")
    self.settingsEntry = entry
    entry:SetPoint("BOTTOMRIGHT", -8, 4)
    entry:SetScript("OnClick", function(owner) E:OpenSettings(owner) end)
    elements.frame:HookScript("OnHide", function() if E.popup then E.popup:Hide() end end)
end
function E:OpenSettings(anchor)
    if not self.active then return end
    if not self.popup then
        local popup = GUI:CreatePanel(UIParent, { width = 316, height = 206,
            surface = "color.surface.popup", border = "color.popup.border", shadow = true })
        self.popup = popup
        popup:SetFrameStrata("FULLSCREEN_DIALOG"); popup:SetClampedToScreen(true); popup:EnableMouse(true)
        local title = GUI:CreateText(popup, L["name"], "font.size.lg", "color.text.heading")
        title:SetPoint("TOPLEFT", 14, -12)
        local close = GUI.Form:CreateButton(popup, { text = "×", width = 24, height = 24, onClick = function() popup:Hide() end })
        close:SetPoint("TOPRIGHT", -8, -8)
        self.enableControl = GUI.Form:CreateCheckbox(popup, { text = L["enable"], width = 280,
            get = function() return E:GetConfig().enabled ~= false end,
            set = function(value) E:GetConfig().enabled = value == true; E:RefreshState() end })
        self.enableControl:SetPoint("TOPLEFT", 14, -46)
        self.minimapControl = GUI.Form:CreateCheckbox(popup, { text = L["minimap"], width = 280,
            get = function() return E:GetConfig().minimap ~= false end,
            set = function(value) E:GetConfig().minimap = value == true; E:RefreshState() end })
        self.minimapControl:SetPoint("TOPLEFT", 14, -78)
        local note = GUI:CreateText(popup, L["capture_note"], "font.size.sm", "color.text.secondary")
        self.captureNote = note
        note:SetPoint("TOPLEFT", 14, -116); note:SetWidth(288); note:SetWordWrap(true)
        self.openButton = GUI.Form:CreateButton(popup, { text = L["view"], width = 130, height = 28,
            onClick = function() popup:Hide(); E:Open() end })
        self.openButton:SetPoint("BOTTOMRIGHT", -14, 12)
        GUI:EnableEscapeClose(popup, function() popup:Hide() end)
        popup:Hide()
    end
    self.popup:ClearAllPoints()
    self.popup:SetPoint("BOTTOMLEFT", anchor or self.settingsEntry or UIParent, "TOPLEFT", 0, 8)
    self.enableControl:SetValue(self:GetConfig().enabled ~= false, true)
    self.minimapControl:SetValue(self:GetConfig().minimap ~= false, true)
    self:RefreshState()
    self.popup:Show()
end
function E:RefreshState()
    if not self.active then return end
    self:EnsureMinimap()
    local config = self:GetConfig()
    local enabled, count, external = self:IsEnabled(), self:GetCount(), self:HasExternalViewer()
    local visible = enabled and config.minimap ~= false
    if self.minimap and self.displayVisible ~= visible then self.minimap:SetShown(visible) end
    if not enabled and self.window then self.window:Hide() end
    if self.openButton then self.openButton:SetDisabled(not enabled) end
    if self.captureNote then
        local text = external and L["viewer.yield"] or L["capture_note"]
        if self.captureNote:GetText() ~= text then self.captureNote:SetText(text) end
    end
    local iconPath = self:GetIcon()
    if self.displayIcon ~= iconPath then
        for _, icon in ipairs(self.icons) do icon:SetTexture(iconPath) end
        self.displayIcon = iconPath
    end
    local changed = self.displayEnabled ~= enabled or self.displayCount ~= count or self.displayExternal ~= external
    self.displayEnabled, self.displayCount, self.displayVisible = enabled, count, visible
    self.displayExternal = external
    if changed then YUI.Event:Emit("YUI_ERROR_RECORDER_CHANGED") end
end
function E:OnCollectorChanged()
    if not self.active then return end
    self:RefreshState()
    local tooltipOwner = GameTooltip and GameTooltip:GetOwner()
    if tooltipOwner and (tooltipOwner == self.minimap or tooltipOwner == self.settingsEntry) then
        GameTooltip:ClearLines(); self:Tooltip(GameTooltip); GameTooltip:Show()
    end
    if self.window and self.window:IsShown() and not self.pendingRefresh then
        self.pendingRefresh = C_Timer.NewTimer(.15, function()
            E.pendingRefresh = nil
            if E.window:IsShown() then E:RefreshView(false) end
        end)
    end
end
function E:OnSettingsVisible(_, visible)
    if visible then self:AttachSettingsEntry(); self:RefreshState() end
end
function E:OnViewerAddonLoaded(_, name)
    if name == "BugSack" then self:OnCollectorChanged() end
end
function E:GetStats()
    return { active = self.active, listeners = self.active and 1 or 0,
        timers = self.pendingRefresh and 1 or 0, idleTickers = 0, refreshes = self.refreshes,
        rows = self.rows and #self.rows or 0, dragging = self.minimap and self.minimap.dragging == true or false }
end
YUI.Module:Register({ id = "suite.errorrecorder", owner = E, product = "suite",
    dependencies = { "core.db", "core.event", "core.locale" },
    OnEnable = function()
        E.active = true; E:GetConfig()
        local collector = E:GetCollector()
        if collector then collector:Subscribe(E, E.OnCollectorChanged) end
        YUI.Event:On("YUI_SETTINGS_VISIBILITY_CHANGED", "OnSettingsVisible", E)
        YUI.Event:On("ADDON_LOADED", "OnViewerAddonLoaded", E)
        E:AttachSettingsEntry(); E:RefreshState()
        if E.settingsEntry then E.settingsEntry:Show() end
    end,
    OnDisable = function()
        E.active = false
        E.displayEnabled, E.displayVisible, E.displayExternal = nil, nil, nil
        local collector = E:GetCollector()
        if collector then collector:Unsubscribe(E) end
        YUI.Event:OffOwner(E); E:StopDrag()
        if E.pendingRefresh then E.pendingRefresh:Cancel(); E.pendingRefresh = nil end
        for _, key in ipairs({ "window", "popup", "minimap", "confirm", "moreMenu" }) do if E[key] then E[key]:Hide() end end
        if E.settingsEntry then E.settingsEntry:Hide() end
        if GameTooltip and tooltipLayouts[GameTooltip] then YUI.HideGameTooltip(); ResetTooltipLayout(GameTooltip) end
        YUI.Event:Emit("YUI_ERROR_RECORDER_CHANGED")
    end,
})

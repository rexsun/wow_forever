local _, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and YUI.IsForever == true and YUI.Components) then return end
if YUI._EllesmereUIQuestAutomation then return end

local Components, Event, GUI = YUI.Components, YUI.Event, YUI.GUI2
local Security, System = YUI.API.Security, YUI.API.System
local L = YUI.Locale and YUI.Locale:Get("EllesmereUIEnhancement") or {}
local Control = { enabled = false, failures = 0, writes = 0, status = "disabled", listeners = 0, mode = "none" }
YUI._EllesmereUIQuestAutomation = Control
local button, pendingTimer, hovered, applying, tooltipMeasure
local layout, painted = {}, {}
local hooked = setmetatable({}, { __mode = "k" })
local observers, operationFailures = {}, {}
local Refresh, Queue, ShowTooltip

local function T(key, fallback) return L[key] or fallback or key end
local function Boolean(value)
    local result = Security.SafeBoolean(value)
    if result == nil then error("unsupported-interface", 0) end
    return result
end
local function Table(value)
    if Security.IsSecretValue(value) or type(value) ~= "table"
        or (Security.CanAccessTable and not Security.CanAccessTable(value)) then error("unsupported-interface", 0) end
    return value
end
local function Feature() return Table(Table(Components.features).AutoGossip) end

local providers = {
    { id = "YUI", label = function() return T("quest_automation.yui", "YUI 工具箱") end,
        access = function(value)
            local feature = Feature()
            if value ~= nil then
                if type(feature.SetQuestAutomationEnabled) ~= "function" then error("unsupported-interface", 0) end
                if feature:SetQuestAutomationEnabled(value) ~= true then error("operation-failed", 0) end
            end
            local active, accept, turnIn = feature:GetQuestAutomationState()
            return Boolean(accept), Boolean(turnIn), Boolean(active)
        end },
    { id = "RXPGuides", label = function() return "RXP" end,
        access = function(value)
            local ace = LibStub:GetLibrary("AceAddon-3.0", true)
            local addon = Table(ace:GetAddon("RXPGuides", true))
            local profile = Table(Table(addon.settings).profile)
            local active = Boolean(addon:IsEnabled())
            Boolean(profile.enableQuestAutomation)
            if value ~= nil then profile.enableQuestAutomation = value end
            local enabled = Boolean(profile.enableQuestAutomation)
            return enabled, enabled, active
        end },
    { id = "Polestar", label = function() return "Polestar" end,
        access = function(value)
            local addon = Table(_G.Polestar)
            if type(addon.Get) ~= "function" or type(addon.Set) ~= "function" then error("unsupported-interface", 0) end
            Boolean(addon.Get("behavior.autoAccept")); Boolean(addon.Get("behavior.autoTurnin"))
            if value ~= nil then
                addon.Set("behavior.autoAccept", value)
                addon.Set("behavior.autoTurnin", value)
            end
            return Boolean(addon.Get("behavior.autoAccept")), Boolean(addon.Get("behavior.autoTurnin")), true
        end },
    { id = "Questie", label = function() return "Questie" end,
        access = function(value)
            local profile = Table(Table(Table(_G.Questie).db).profile)
            local accept = Table(profile.autoAccept)
            Boolean(accept.enabled); Boolean(profile.autocomplete)
            if value ~= nil then accept.enabled, profile.autocomplete = value, value end
            return Boolean(accept.enabled), Boolean(profile.autocomplete), true
        end },
}

local function Loaded(provider)
    if provider.id == "YUI" then return Components.features and Components.features.AutoGossip ~= nil end
    return Boolean(System.IsAddOnLoaded(provider.id))
end

function Control:ReadState()
    local result = { rows = {}, anyOn = false, unknown = false, failed = false }
    for _, provider in ipairs(providers) do
        -- 加载检测、链式字段访问、方法查找和返回值检查均在保护范围内。
        local detected, loaded = pcall(Loaded, provider)
        if not detected or loaded then
            local row = { id = provider.id, label = provider.label(), failed = operationFailures[provider.id] == true }
            local ok, accept, turnIn, active = false
            if detected then ok, accept, turnIn, active = pcall(provider.access) end
            if ok then
                row.accept, row.turnIn, row.active = accept, turnIn, active
                result.anyOn = result.anyOn or (active and (accept or turnIn))
            else
                row.unknown, result.unknown = true, true
            end
            result.failed = result.failed or row.failed
            result.rows[#result.rows + 1] = row
        end
    end
    return result
end

function Control:Apply(enabled)
    if applying or not self.enabled or Security.InCombatLockdown() then return false end
    applying = true
    local success = true
    for _, provider in ipairs(providers) do
        local detected, loaded = pcall(Loaded, provider)
        operationFailures[provider.id] = nil
        if not detected then operationFailures[provider.id], success = true, false
        elseif loaded then
            local wanted = enabled == true and provider.id == "YUI"
            local ok = pcall(provider.access, wanted)
            -- 单独回读，不用 pcall 成功代替设置生效，也不让一家失败中断其余来源。
            local readOK, accept, turnIn, active = pcall(provider.access)
            if not ok or not readOK or accept ~= wanted or turnIn ~= wanted or (wanted and not active) then
                operationFailures[provider.id], success = true, false
                self.failures = self.failures + 1
            end
            self.writes = self.writes + 1
        end
    end
    applying = false
    Refresh()
    return success
end

local function HideTooltip()
    if button and GUI.Tooltip then GUI.Tooltip:Hide(button) end
    hovered = false
end

local function StateText(value) return value and T("quest_automation.on", "开启") or T("quest_automation.off", "关闭") end
local function TooltipColumns()
    if not tooltipMeasure then
        tooltipMeasure = GUI:CreateText(button, "", "font.size.md", "color.text.primary")
        tooltipMeasure:Hide()
    end
    local fontSource = _G.GameTooltipTextRight3 or _G.GameTooltipText
    if fontSource then tooltipMeasure:SetFont(fontSource:GetFont()) end
    local function Width(text)
        tooltipMeasure:SetText(text)
        return tooltipMeasure:GetStringWidth()
    end
    local accept, turnIn = T("quest_automation.accept", "自动接取"), T("quest_automation.turn_in", "自动交付")
    local valueWidth = math.max(Width(StateText(true)), Width(StateText(false)))
    local acceptWidth, turnInWidth = math.max(Width(accept), valueWidth), math.max(Width(turnIn), valueWidth)
    local spaceWidth = math.max(Width("x x") - Width("xx"), 1)
    local function Cell(text, tone, width)
        -- 原生提示只有左右两列；按实际字体宽度补齐右列中的两个状态，兼容中英文比例字体。
        local padding = math.max(0, math.floor((width - Width(text)) / spaceWidth + 0.5))
        return string.rep(" ", padding) .. GUI.Tooltip:ColorText(text, tone)
    end
    local function Row(left, leftTone, right, rightTone)
        return string.format(T("quest_automation.row", "%s    %s"),
            Cell(left, leftTone, acceptWidth), Cell(right, rightTone, turnInWidth))
    end
    return Row, Row(accept, "secondary", turnIn, "secondary")
end
ShowTooltip = function()
    if not (button and GUI.Tooltip) then return end
    local state = Control:ReadState()
    local columns, headings = TooltipColumns()
    GUI.Tooltip:Show(button, {
        title = T("quest_automation.title", "自动交接"),
        content = function(body)
            body:AddDoubleLine(T("quest_automation.plugin", "插件"), headings, "secondary", "secondary")
            for _, row in ipairs(state.rows) do
                local text, tone = nil, "body"
                if row.unknown then text, tone = T("quest_automation.unknown", "状态未知／接口未适配"), "warning"
                elseif not row.active then text, tone = T("quest_automation.inactive", "组件已停用"), "secondary"
                else text = columns(StateText(row.accept), row.accept and "success" or "secondary",
                    StateText(row.turnIn), row.turnIn and "success" or "secondary") end
                body:AddDoubleLine(row.label, text, "body", tone)
                if row.failed then body:AddDoubleLine("", T("quest_automation.failed", "操作失败"), "body", "requirement") end
            end
            body:AddSpace()
            body:AddLine(T("quest_automation.rules", "仍遵循任务筛选、奖励及按键设置。"), "secondary")
            if Security.InCombatLockdown() then body:AddLine(T("quest_automation.combat", "战斗中暂停操作。"), "secondary") end
        end,
        actions = { { keyTone = "secondary", text = (state.anyOn or state.unknown)
            and T("quest_automation.disable", "关闭全部自动交接") or T("quest_automation.enable", "仅开启 YUI 自动交接") } },
        settings = { button = "RightButton", keyTone = "secondary", text = T("quest_automation.settings", "打开 YUI 交接设置") },
    })
end

local function PaintState()
    if not button then return end
    local state = Control:ReadState()
    local checked, warning = state.anyOn or state.unknown, state.unknown or state.failed
    if painted.checked ~= checked then button:SetChecked(checked, true); painted.checked = checked end
    if painted.warning ~= warning then button.unknownMark:SetShown(warning); painted.warning = warning end
    if hovered then ShowTooltip() end
end

local function Click(_, mouseButton)
    if not Control.enabled or Security.InCombatLockdown() or not button:IsVisible()
        or Security.SafeNumber(button:GetEffectiveAlpha()) <= 0 or EditModeManagerFrame:IsEditModeActive() then return end
    if mouseButton == "RightButton" then
        HideTooltip()
        if Components.OpenFeatureSettings then Components:OpenFeatureSettings("AutoGossip") end
    elseif mouseButton == "LeftButton" then
        local state = Control:ReadState()
        Control:Apply(not (state.anyOn or state.unknown))
    end
end

local function Run(callback, ...)
    local ok = pcall(callback, ...)
    if not ok then
        Control.failures, Control.status = Control.failures + 1, "unavailable"
        if button then Security.SafeMethod("quest-automation:hide", button, "Hide") end
    end
end

local function Hook(object, method)
    if not object or type(object[method]) ~= "function" then return end
    local methods = hooked[object]
    if not methods then methods = {}; hooked[object] = methods end
    if methods[method] then return end
    if Security.SafeHook("quest-automation:" .. method, object, method, function() if Control.enabled then Queue() end end) then
        methods[method] = true
    end
end

local function ReleaseObserver(slot)
    local entry = observers[slot]
    if not entry then return true end
    entry.active = false
    local ok = pcall(entry.unregister, entry.cleanup)
    if ok then observers[slot] = nil else Control.failures = Control.failures + 1 end
    return ok
end

local function Observe(slot, object, register, unregister)
    local previous = observers[slot]
    if previous and previous.object == object and previous.active then return end
    if previous and not ReleaseObserver(slot) then return end
    local entry = { object = object, unregister = unregister, active = true }
    observers[slot] = entry
    local ok, cleanup = pcall(register, function()
        if entry.active and Control.enabled then Run(Queue) end
    end)
    entry.cleanup = cleanup
    if not ok then
        entry.cleanup = nil
        Control.failures = Control.failures + 1
        ReleaseObserver(slot)
    end
end

local function ObserveProviders()
    -- 注册与注销也在保护范围内；回调只合并一次刷新，禁用后无活动。
    pcall(function()
        if System.IsAddOnLoaded("Polestar") ~= true then return end
        local addon = Table(_G.Polestar)
        if type(addon.On) == "function" and type(addon.Off) == "function" then
            Observe("Polestar", addon, function(callback)
                return addon.On("SETTING_CHANGED", callback)
            end, function(handle) addon.Off(handle) end)
        end
    end)
    pcall(function()
        local registry = LibStub:GetLibrary("AceConfigRegistry-3.0", true)
        if registry then
            Observe("config", registry, function(callback)
                registry.RegisterCallback(Control, "ConfigTableChange", callback)
            end, function() registry.UnregisterAllCallbacks(Control) end)
        end
        local dialog = LibStub:GetLibrary("AceConfigDialog-3.0", true)
        Hook(dialog, "Close")
    end)
    pcall(function()
        if System.IsAddOnLoaded("Questie") ~= true then return end
        local db = Table(_G.Questie).db
        if db and type(db.RegisterCallback) == "function" and type(db.UnregisterAllCallbacks) == "function" then
            Observe("Questie", db, function(callback)
                for _, name in ipairs({ "OnProfileChanged", "OnProfileCopied", "OnProfileReset" }) do
                    db.RegisterCallback(Control, name, callback)
                end
            end, function() db.UnregisterAllCallbacks(Control) end)
        end
    end)
    pcall(function()
        if System.IsAddOnLoaded("RXPGuides") ~= true then return end
        local addon = LibStub:GetLibrary("AceAddon-3.0", true):GetAddon("RXPGuides", true)
        Hook(addon.settings, "RefreshProfile")
        Hook(addon.settings, "CopyProfile")
        Hook(addon.settings, "ResetProfile")
    end)
end

local function CustomTrackerEnabled()
    if _G.EUI_CustomQuestTracker ~= nil then return true end
    local provider = _G.EllesmereUIQuestTracker
    if type(provider) ~= "table" then return false end
    local cfg = provider.Cfg
    if type(cfg) ~= "function" then return false end
    local ok, value = pcall(cfg, "customTracker")
    return ok and not Security.IsSecretValue(value) and value == true
end

local function CustomHeader(frame)
    if not frame then return nil end
    -- Forever 的 GetChildren 返回多个 frame；标准客户端返回单个 table，两种都兼容。
    local packed = { pcall(frame.GetChildren, frame) }
    if not packed[1] then return nil end
    for index = 2, #packed do
        local child = packed[index]
        if type(child) == "table" and child[1] ~= nil and not child.text then
            for nested = 1, #child do
                local candidate = child[nested]
                if candidate and candidate.text and candidate.toggle and candidate.count then return candidate end
            end
        elseif child and child.text and child.toggle and child.count then
            return child
        end
    end
end

local function Layout()
    local provider = Table(_G.EllesmereUIQuestTracker)
    local custom = CustomTrackerEnabled()
    Control.mode = custom and "eui-custom" or "native"
    Hook(provider, "UpdateVisibility"); Hook(provider, "SkinHeader"); Hook(provider, "InitCustom")
    local tracker, module, header
    if custom then
        tracker = _G.EUI_CustomQuestTracker
        header = CustomHeader(tracker)
        if not (tracker and header) then
            Control.status, Control.mode = "waiting-custom-tracker", "eui-custom"
            if button then button:Hide(); HideTooltip() end
            return
        end
    else
        tracker, module = _G.ObjectiveTrackerFrame, _G.QuestObjectiveTracker
        header = module and module.Header
        if not (tracker and header) then
            Control.status, Control.mode = "waiting-tracker", "native"
            if button then button:Hide(); HideTooltip() end
            return
        end
    end
    for _, method in ipairs({ "Show", "Hide", "SetAlpha", "OnEditModeEnter", "OnEditModeExit" }) do Hook(tracker, method) end
    for _, method in ipairs({ "Show", "Hide", "SetSize", "SetWidth" }) do Hook(header, method) end
    local visible = provider.Cfg("enabled") ~= false and tracker:IsVisible() and header:IsVisible()
        and Security.SafeNumber(tracker:GetEffectiveAlpha()) > 0
        and not EditModeManagerFrame:IsEditModeActive() and not Security.InCombatLockdown()
    if not visible then
        if button then button:Hide(); HideTooltip() end
        Control.status = "hidden"
        return
    end
    if not button then
        button = GUI.Form:CreateCheckbox(header, { text = T("quest_automation.label", "交接"), width = 64, height = 20, checked = false })
        button.box:ClearAllPoints(); button.box:SetPoint("RIGHT", button, "RIGHT", 0, 0); button.box:SetSize(14, 14)
        button.text:ClearAllPoints(); button.text:SetPoint("LEFT", button, "LEFT", 0, 0); button.text:SetWidth(46)
        button.text:SetJustifyH("RIGHT")
        button.unknownMark = GUI:CreateText(button.box, "?", "font.size.sm", "color.text.primary")
        button.unknownMark:SetAllPoints(button.box)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnClick", function(...) Run(Click, ...) end)
        local enter, leave = button:GetScript("OnEnter"), button:GetScript("OnLeave")
        button:SetScript("OnEnter", function(self) Run(function()
            if not self:IsVisible() or Security.SafeNumber(self:GetEffectiveAlpha()) <= 0 then return end
            if enter then enter(self) end
            hovered = true; PaintState()
        end) end)
        button:SetScript("OnLeave", function(self) Run(function() if leave then leave(self) end; HideTooltip() end) end)
        button:SetScript("OnHide", HideTooltip)
        button:Hide()
    end
    if button:GetParent() ~= header then button:SetParent(header); layout.anchor = nil end
    local anchor, side, offset, minimize
    if custom then
        if header.count then
            anchor, side, offset = header.count, "LEFT", -16
        elseif header.text then
            anchor, side, offset = header.text, "RIGHT", 8
        else
            anchor, side, offset = header, "RIGHT", -8
        end
    else
        minimize = header.MinimizeButton
        anchor, side, offset = minimize or header, minimize and "LEFT" or "RIGHT", -8
    end
    if layout.anchor ~= anchor or layout.side ~= side or layout.offset ~= offset then
        button:ClearAllPoints()
        button:SetPoint("RIGHT", anchor, side, offset, 0)
        layout.anchor, layout.side, layout.offset = anchor, side, offset
    end
    -- 独立子按钮位于原生整行折叠命中区上方；不改写或转发原生点击。
    local level = math.max(header:GetFrameLevel(), minimize and minimize:GetFrameLevel() or 0) + 3
    if button:GetFrameLevel() ~= level then button:SetFrameLevel(level) end
    local fontSource = custom and header.text or header.Text
    if fontSource then
        local font, size, flags = fontSource:GetFont()
        if font and Security.SafeNumber(size) and (layout.font ~= font or layout.size ~= size or layout.flags ~= flags) then
            button.text:SetFont(font, size, flags)
            layout.font, layout.size, layout.flags = font, size, flags
        end
    end
    if not button:IsShown() then button:Show() end
    Control.status = "ready"
    PaintState()
end

Refresh = function()
    if not Control.enabled then return end
    ObserveProviders()
    if _G.EllesmereUIQuestTracker then Run(Layout)
    else Control.status = "waiting-provider"; if button then button:Hide(); HideTooltip() end end
end

local function RunPending() pendingTimer = nil; Refresh() end
Queue = function()
    if Control.enabled and not pendingTimer and not applying then pendingTimer = C_Timer.NewTimer(0, RunPending) end
end

function Control:OnEvent(event, addonName)
    if event == "ADDON_LOADED" and addonName ~= "EllesmereUIQuestTracker" and addonName ~= "Blizzard_ObjectiveTracker"
        and addonName ~= "Polestar" and addonName ~= "RXPGuides" and addonName ~= "Questie" then return end
    Queue()
end

function Control:SetEnabled(enabled)
    if enabled == true then
        if not self.enabled then
            self.enabled = true
            for _, event in ipairs({ "ADDON_LOADED", "YUI_LOGIN_READY", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "YUI_QUEST_AUTOMATION_CHANGED" }) do
                Event:On(event, "OnEvent", self, { moduleId = "component:EllesmereUIEnhancement" })
            end
            self.listeners = 5
        end
        Queue()
    else
        self.enabled, self.status, self.listeners = false, "disabled", 0
        Event:OffOwner(self)
        if pendingTimer then pendingTimer:Cancel(); pendingTimer = nil end
        for slot in pairs(observers) do ReleaseObserver(slot) end
        if button then Security.SafeMethod("quest-automation:hide", button, "Hide"); HideTooltip() end
    end
end

function Control:GetStats()
    return { enabled = self.enabled, mode = self.mode or "none", status = self.status, listeners = self.listeners,
        pendingTimers = pendingTimer and 1 or 0, failures = self.failures, writes = self.writes,
        shown = button and button:IsShown() or false }
end

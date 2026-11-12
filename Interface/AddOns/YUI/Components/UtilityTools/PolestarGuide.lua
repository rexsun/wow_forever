local _, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and YUI.IsForever and YUI.Components) or YUI.UtilityToolsPolestarGuide then return end

local Event, GUI = YUI.Event, YUI.GUI2
local Unpack = unpack or table.unpack
local System, Security = YUI.API.System, YUI.API.Security
local Visibility = YUI.API.Visibility
local L, CoreL = YUI.Locale:Get("UtilityTools"), YUI.Locale:Get("Core")
local Feature = { enabled = false, attached = false, listeners = 0, failures = 0, toggles = 0, scalePercent = 100 }
YUI.UtilityToolsPolestarGuide = Feature
local button, badge, badgeText, binding
local manualHidden = false
local instanceHandled, autoChanging = false, false
local restoreBinding
local Sync, Stop, Run
local bindings = setmetatable({}, { __mode = "k" })
local expandedTip, collapsedTip

local function Ordinary(frame)
    return frame and type(frame.IsForbidden) == "function" and Security.SafeBoolean(frame:IsForbidden()) == false
        and type(frame.IsProtected) == "function" and Security.SafeBoolean(frame:IsProtected()) == false
end

-- 每次接入只检查一次所需接口；后续操作直接使用当前绑定。
local function FindTarget()
    if System.IsAddOnLoaded("Polestar") ~= true then return nil, "waiting" end
    local addon = _G.Polestar
    local guide = addon and addon.UI and addon.UI.GuideFrame
    local frame, parts = guide and guide.frame, guide and guide.parts
    if not (frame and parts) then return nil, "waiting" end
    if (addon.Hidden or addon.SetHidden or addon.ToggleHidden)
        and not (type(addon.Hidden) == "function" and type(addon.SetHidden) == "function"
            and type(addon.ToggleHidden) == "function" and Security.SafeBoolean(addon.Hidden()) ~= nil) then
        return nil, "unsupported-interface"
    end
    if not (type(addon.Get) == "function" and type(addon.Set) == "function"
        and type(addon.On) == "function" and type(addon.Off) == "function"
        and addon.Bindings and type(addon.Bindings.Toggle) == "function" and type(guide.Layout) == "function"
        and addon.Theme and type(addon.Theme.Wash) == "function" and type(addon.Theme.Color) == "function"
        and Security.SafeBoolean(addon.Get("ui.shown")) ~= nil
        and Ordinary(frame) and Ordinary(parts.nav) and Ordinary(guide.menuButton)
        and parts.nav.Title and type(parts.nav.Title.GetWidth) == "function") then return nil, "unsupported-interface" end
    return addon, guide
end

local function PaintButton()
    if not (button and binding) then return end
    local theme = binding.theme
    button.hover:SetColorTexture(theme.Wash("hover"))
    button.icon:SetColorTexture(theme.Color(button.hover:IsShown() and "iconHover" or "icon"))
end

local function HideTip(control)
    if GUI.Tooltip then GUI.Tooltip:Hide(control) end
    if control == button then
        if button.hover then button.hover:Hide() end
        PaintButton()
    end
    if control == badge and badgeText then GUI:SetTextColorKey(badgeText, "color.text.primary") end
end

local function HideControls()
    if button then button:Hide(); HideTip(button) end
    if badge then badge:Hide(); HideTip(badge) end
end

local function Unsubscribe()
    if not binding then return end
    for _, handle in ipairs(binding.handles) do binding.off(handle) end
    binding.handles = {}
end

local function Detach()
    local previous = binding
    binding = nil
    Feature.attached, Feature.pending, manualHidden = false, false, false
    instanceHandled, autoChanging, restoreBinding = false, false, nil
    HideControls()
    if not previous then return end
    if previous.guide.Layout == previous.wrapper then previous.guide.Layout = previous.originalLayout end
    -- 仅恢复仍由本扩展占用的锚点；不覆盖后来其他扩展接管的位置。
    local point, relative, relativePoint = previous.menu:GetPoint(1)
    if point == "RIGHT" and relative == button and relativePoint == "LEFT" then
        previous.menu:ClearAllPoints()
        previous.menu:SetPoint(Unpack(previous.menuPoint))
    end
    bindings[previous.frame] = nil
    button:SetScript("OnShow", nil)
    button:SetScript("OnHide", nil)
    button:SetParent(_G.UIParent)
    previous.originalLayout()
end

function Feature:FinishDisable()
    if Security.InCombatLockdown() then return end
    Event:OffOwner(self)
    self.listeners = 0
    Run(Detach)
end

function Feature:Disable()
    self.enabled, self.attached = false, false
    instanceHandled, autoChanging, restoreBinding = false, false, nil
    Event:OffOwner(self)
    self.listeners = 0
    Unsubscribe()
    HideControls()
    if binding and Security.InCombatLockdown() then
        self.pending = true
        Event:On("PLAYER_REGEN_ENABLED", "FinishDisable", self)
        self.listeners = 1
    else
        Run(Detach)
    end
end

Stop = function(reason)
    Feature.blockedReason = reason
    Feature:Disable()
end

Run = function(fn, ...)
    local ok = pcall(fn, ...)
    if not ok then
        Feature.failures = Feature.failures + 1
        Stop("interface-error")
    end
end

local function PlaceChrome()
    local current = binding
    if not (Feature.enabled and Feature.attached and current) then return end
    -- 原有右侧控件都锚定菜单；挪动菜单即可整组留出一个按钮位。
    local title = current.nav.Title
    title:SetWidth(math.max(1, title:GetWidth() - button:GetWidth()))
end

Sync = function()
    if not (Feature.enabled and Feature.attached and binding) then return end
    PaintButton()
    local frame = binding.frame
    local hidden = binding.hidden and Security.SafeBoolean(binding.hidden()) == true
    if frame:IsShown() and not hidden then manualHidden = false end
    local scale = Security.SafeNumber(frame:GetEffectiveScale())
    local parentScale = Security.SafeNumber(_G.UIParent:GetEffectiveScale())
    if not (scale and parentScale and parentScale > 0) then Stop("unsupported-scale"); return end
    local value = scale / parentScale * Feature.scalePercent / 100
    if badge:GetScale() ~= value then badge:SetScale(value) end
    local corner = Security.SafeBoolean(binding.get("ui.growUp")) == true and "BOTTOMLEFT" or "TOPLEFT"
    badge:ClearAllPoints()
    badge:SetPoint(corner, frame, corner, 0, 0)
    badge:SetFrameStrata(frame:GetFrameStrata())
    -- 原生临时隐藏不生成标签；显式收起（含本扩展进本收起）保留恢复入口。
    badge:SetShown(hidden or (not frame:IsShown() and (manualHidden or Security.SafeBoolean(binding.get("ui.shown")) == false)))
end

local function ContentShown()
    if binding.hidden then return Security.SafeBoolean(binding.hidden()) == false end
    return Security.SafeBoolean(binding.get("ui.shown")) == true
end

local function SetAutoShown(shown)
    -- 原生副本隐藏后调用开关可能反向展开；使用官方设置接口明确目标状态。
    autoChanging = true
    if binding.setHidden then binding.setHidden(not shown) else binding.set("ui.shown", shown) end
    autoChanging = false
    Feature.toggles = Feature.toggles + 1
    Sync()
end

local function OnClick(_, mouseButton)
    if mouseButton ~= "LeftButton" or not Feature.enabled or not Feature.attached then return end
    Run(function()
        restoreBinding = nil
        if binding.hidden and Security.SafeBoolean(binding.hidden()) == false
            and (manualHidden or Security.SafeBoolean(binding.get("ui.shown")) == false) then
            binding.toggleFrame()
        else
            binding.toggle()
        end
        Feature.toggles = Feature.toggles + 1
        Sync()
    end)
end

local function OnEnter(control)
    if binding and type(binding.guide.HoverIn) == "function" then Run(binding.guide.HoverIn) end
    if control == button then
        button.hover:Show()
        PaintButton()
    end
    if control == badge then GUI:SetTextColorKey(badgeText, "color.badge.orange.hover") end
    if GUI.Tooltip then GUI.Tooltip:Show(control, control == badge and collapsedTip or expandedTip) end
end

local function EnsureControls()
    if button then return end
    button = GUI:CreateButtonFrame(_G.UIParent, { hidden = true, width = 24, height = 24, clicks = "LeftButtonUp" })
    button.hover = GUI:CreateTexture(button, { layer = "BACKGROUND" })
    button.hover:SetAllPoints(button)
    button.hover:Hide()
    button.icon = GUI:CreateTexture(button, { width = 12, height = 2 })
    button.icon:SetPoint("CENTER")
    badge = GUI:CreateButtonFrame(_G.UIParent, { hidden = true, height = 30, clicks = "LeftButtonUp", clamped = true })
    local icon = GUI:CreateTexture(badge, { layer = "ARTWORK", width = 24, height = 24 })
    icon:SetTexture("Interface\\AddOns\\Polestar\\Media\\UI\\logo")
    icon:SetPoint("LEFT", badge, "LEFT", 4, 0)
    badgeText = GUI:CreateText(badge, L["route_guide.label"], "font.size.md", "color.text.primary", "LEFT")
    GUI:ApplyFontAppearance(badgeText, { size = GUI:GetMetric("font.size.md", 13), outline = "outlineShadow" })
    badgeText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    badge:SetWidth(38 + badgeText:GetStringWidth())
    local footer = { text = "\n" .. string.format(L["route_guide.settings"], CoreL["settings.nav.toolbox"], L["name"]), tone = "secondary" }
    expandedTip = { title = "Polestar", subtitle = "YUI", footer = footer,
        actions = { { button = "LeftButton", text = L["route_guide.hide"] } } }
    collapsedTip = { title = "Polestar", subtitle = "YUI", footer = footer,
        actions = { { button = "LeftButton", text = L["route_guide.show"] } } }
    for _, control in ipairs({ button, badge }) do
        control:SetScript("OnClick", OnClick)
        control:SetScript("OnEnter", OnEnter)
        control:SetScript("OnLeave", HideTip)
    end
    badge:SetScript("OnHide", HideTip)
end

local function Attach(addon, guide)
    EnsureControls()
    local frame, menu, nav = guide.frame, guide.menuButton, guide.parts.nav
    if menu:GetNumPoints() ~= 1 then Stop("unsupported-anchor"); return end
    local point = { menu:GetPoint(1) }
    if point[1] ~= "RIGHT" or point[2] ~= nav or point[3] ~= "RIGHT" then Stop("unsupported-anchor"); return end
    local current = { theme = addon.Theme, guide = guide, frame = frame, menu = menu, nav = nav,
        menuPoint = point, originalLayout = guide.Layout, toggle = addon.ToggleHidden or addon.Bindings.Toggle,
        toggleFrame = addon.Bindings.Toggle, hidden = addon.Hidden, setHidden = addon.SetHidden,
        get = addon.Get, set = addon.Set, off = addon.Off, handles = {} }
    current.wrapper = function(...)
        current.originalLayout(...)
        if binding == current then Run(PlaceChrome) end
    end
    binding, bindings[frame] = current, current
    expandedTip.actions[1].text = L[current.hidden and "polestar_guide.hide" or "route_guide.hide"]
    collapsedTip.actions[1].text = L[current.hidden and "polestar_guide.show" or "route_guide.show"]
    button:SetParent(nav)
    button:ClearAllPoints()
    button:SetPoint(Unpack(point))
    button:SetFrameLevel(menu:GetFrameLevel() + 1)
    menu:ClearAllPoints()
    menu:SetPoint("RIGHT", button, "LEFT", 0, 0)
    button:SetScript("OnShow", function() Run(Sync) end)
    button:SetScript("OnHide", function(control) HideTip(control); Run(Sync) end)
    guide.Layout = current.wrapper
    current.handles[1] = addon.On("SETTING_CHANGED", function(path)
        if not autoChanging and (path == "" or path == "ui" or path == "ui.shown") then restoreBinding = nil end
        if path == "" or path == "ui" or (type(path) == "string" and path:sub(1, 3) == "ui.") then Run(Sync) end
    end)
    current.handles[2] = addon.On("TOGGLE_FRAME", function()
        restoreBinding = nil
        manualHidden = not frame:IsShown()
        Run(Sync)
    end)
    if current.hidden then
        current.hiddenState = Security.SafeBoolean(current.hidden())
        current.handles[3] = addon.On("POLESTAR_HIDDEN", function()
            local hidden = Security.SafeBoolean(current.hidden())
            if not autoChanging and hidden ~= current.hiddenState then restoreBinding = nil end
            current.hiddenState = hidden
            Run(Sync)
        end)
    end
    Feature.attached, Feature.pending = true, false
    button:Show()
    guide.Layout()
    Sync()
end

local function RefreshInstance()
    if not (Feature.enabled and Feature.attached and binding and Visibility and type(Visibility.Read) == "function") then return end
    local inInstance = Security.SafeBoolean(Visibility.Read("instance"))
    if inInstance == false then
        instanceHandled = false
        local previous = restoreBinding
        -- 恢复前释放归属，避免设置回调或重复通知再次展开。
        restoreBinding = nil
        if previous ~= binding then return end
        if not ContentShown() then SetAutoShown(true) end
        return
    end
    if inInstance ~= true or instanceHandled then return end
    instanceHandled = true
    if ContentShown() then
        restoreBinding = binding
        SetAutoShown(false)
    end
end

function Feature:Refresh()
    Run(function()
        if not self.enabled then return end
        if self.attached then Sync(); RefreshInstance(); return end
        if Security.InCombatLockdown() then self.pending = true; return end
        if binding then Detach() end
        local addon, guide = FindTarget()
        if addon then Attach(addon, guide); RefreshInstance() elseif guide ~= "waiting" then Stop(guide) end
    end)
end

function Feature:OnAddonLoaded(_, name)
    if name == "Polestar" then self:Refresh() end
end

function Feature:SetScale(value)
    value = Security.SafeNumber(value) or 100
    if value ~= value then value = 100 end
    value = math.floor(math.max(50, math.min(200, value)) + 0.5)
    if self.scalePercent == value then return end
    self.scalePercent = value
    Run(Sync)
end

function Feature:Enable()
    if self.enabled or self.blockedReason then return end
    self.enabled = true
    Event:OffOwner(self)
    Event:On("ADDON_LOADED", "OnAddonLoaded", self)
    Event:On("YUI_LOGIN_READY", "Refresh", self)
    Event:On("PLAYER_ENTERING_WORLD", "Refresh", self)
    Event:On("PLAYER_REGEN_ENABLED", "Refresh", self)
    self.listeners = 4
    self:Refresh()
end

function Feature:GetStats()
    return { enabled = self.enabled, attached = self.attached, listeners = self.listeners,
        pending = self.pending == true, failures = self.failures, toggles = self.toggles,
        blockedReason = self.blockedReason, allocatedButtons = button and 2 or 0, idleTickers = 0 }
end

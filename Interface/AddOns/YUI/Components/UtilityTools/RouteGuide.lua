local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and YUI.Components) or YUI.UtilityToolsRouteGuide then return end

local Event, GUI2 = YUI.Event, YUI.GUI2
local System = YUI.API and YUI.API.System
local Security = YUI.API and YUI.API.Security
local Visibility = YUI.API and YUI.API.Visibility
local L = YUI.Locale and YUI.Locale:Get("UtilityTools") or {}
local CoreL = YUI.Locale and YUI.Locale:Get("Core") or {}
local TARGET_ADDON = "RXPGuides"
-- 与 Core/Functions.lua 中 YUI:Print 的品牌配色一致。
local SOURCE_LABEL = "|cFFFF00FFY|r|cFFFF6666U|r|cFFFF9900I|r"
local Feature = { enabled = false, attached = false, listeners = 0, failures = 0, toggles = 0, scalePercent = 100 }
YUI.UtilityToolsRouteGuide = Feature

local bindings = setmetatable({}, { __mode = "k" })
local overlay, badge, badgeIcon, badgeClassIcon, badgeText, logoHighlight
local badgeHovered = false
local dragging, suppressClick = false, false
local instanceHandled = false
local restoreProfile
local expandedTooltip, collapsedTooltip

local function IsOrdinaryFrame(frame)
    return frame and type(frame.IsForbidden) == "function" and not frame:IsForbidden()
        and type(frame.IsProtected) == "function" and not frame:IsProtected()
end

-- 整个外部读取边界由 Run 保护；未知版本或对象结构不尝试推断。
local function ReadTarget()
    if System.IsAddOnLoaded(TARGET_ADDON) ~= true then return nil, "waiting" end
    local version = Security.SafeString(System.GetAddOnMetadata(TARGET_ADDON, "Version"))
    if version ~= "v4.11.23" and version ~= "4.11.23" then return nil, "unsupported-version" end
    local stub = _G.LibStub
    if not (stub and type(stub.GetLibrary) == "function") then return nil, "missing-library" end
    local ace = stub:GetLibrary("AceAddon-3.0", true)
    if not (ace and type(ace.GetAddon) == "function") then return nil, "missing-library" end
    local addon = ace:GetAddon(TARGET_ADDON, true)
    local settings = addon and addon.settings
    if not (settings and type(settings.profile) == "table") then return nil, "waiting" end
    local profile = settings.profile
    if type(settings.ToggleActive) ~= "function" or Security.SafeBoolean(profile.showEnabled) == nil
        or (profile.hideGuideWindow ~= nil and Security.SafeBoolean(profile.hideGuideWindow) == nil)
        or not (addon.v2 and type(addon.v2.IsGuideWindowEnabled) == "function") then return nil, "unsupported-interface" end
    local v2Enabled = addon.v2:IsGuideWindowEnabled()
    -- 原接口用 and 链返回状态；未开启测试功能时 nil 也表示旧版。
    if Security.IsSecretValue(v2Enabled) or (v2Enabled ~= nil and v2Enabled ~= false) then
        return nil, "unsupported-interface"
    end
    local frame = addon.RXPFrame
    local guide = frame and frame.GuideName
    local icon = guide and guide.icon
    if frame ~= _G.RXPFrame or not IsOrdinaryFrame(frame) or not IsOrdinaryFrame(guide)
        or guide:GetParent() ~= frame or not (icon and type(icon.GetObjectType) == "function")
        or icon:GetObjectType() ~= "Texture" or icon:GetParent() ~= guide
        or type(guide:GetScript("OnMouseDown")) ~= "function"
        or type(guide:GetScript("OnMouseUp")) ~= "function" then return nil, "unsupported-frame" end
    local binding = bindings[frame]
    if Feature.attached and (Feature.frame ~= frame or not binding or binding.addon ~= addon
        or binding.settings ~= settings or binding.toggle ~= settings.ToggleActive
        or binding.guide ~= guide or binding.icon ~= icon
        or binding.mouseDown ~= guide:GetScript("OnMouseDown")
        or binding.mouseUp ~= guide:GetScript("OnMouseUp")) then return nil, "changed-interface" end
    return addon
end

local function HideTooltip(owner)
    if owner == badge and badgeHovered then
        badgeHovered = false
        pcall(GUI2.SetTextColorKey, GUI2, badgeText, "color.text.primary")
    end
    if owner and GUI2 and GUI2.Tooltip then pcall(GUI2.Tooltip.Hide, GUI2.Tooltip, owner) end
end

local function EndDrag()
    if not dragging then return end
    dragging = false
    local binding = Feature.frame and bindings[Feature.frame]
    if not binding then return end
    -- 只结束本扩展发起的拖动；不恢复或改写外部脚本。
    local ok = pcall(function()
        if not IsOrdinaryFrame(Feature.frame) then return end
        if IsOrdinaryFrame(binding.guide) and binding.guide:GetScript("OnMouseUp") == binding.mouseUp then
            binding.mouseUp(binding.guide, "LeftButton")
        else
            Feature.frame:StopMovingOrSizing()
        end
    end)
    if not ok then
        pcall(function()
            if IsOrdinaryFrame(Feature.frame) then Feature.frame:StopMovingOrSizing() end
        end)
    end
end

local function Detach()
    Feature.attached = false
    EndDrag()
    suppressClick = false
    restoreProfile = nil
    if Event and Event.OffOwner then Event:OffOwner(Feature) end
    Feature.listeners, Feature.pending = 0, false
    for _, control in ipairs({ overlay, badge }) do
        HideTooltip(control)
        pcall(function()
            control:SetScript("OnShow", nil)
            control:SetScript("OnHide", nil)
            control:SetScript("OnClick", nil)
            control:SetScript("OnEnter", nil)
            control:SetScript("OnLeave", nil)
            control:SetScript("OnMouseDown", nil)
            control:SetScript("OnDragStart", nil)
            control:SetScript("OnDragStop", nil)
            control:Hide()
        end)
    end
    if Feature.frame then bindings[Feature.frame] = nil end
    Feature.frame = nil
end

local function Stop(reason)
    Feature.blockedReason = reason
    Detach()
end

local function Run(callback, ...)
    if not Feature.enabled or Feature.blockedReason then return end
    local ok = pcall(callback, ...)
    if not ok then
        Feature.failures = Feature.failures + 1
        Stop("error")
    end
end

local function Sync()
    if not Feature.attached then return end
    local addon, reason = ReadTarget()
    if not addon then Stop(reason); return end
    local profile = addon.settings.profile
    -- 原入口切换或配置文件变化会撤销自动恢复；Alt+Z 等父级隐藏不改变此状态。
    if restoreProfile and (profile ~= restoreProfile or profile.showEnabled ~= false
        or profile.hideGuideWindow == true) then restoreProfile = nil end
    local visible = profile.showEnabled == false and profile.hideGuideWindow ~= true
    local scale = Security.SafeNumber(addon.RXPFrame:GetEffectiveScale())
    local parentScale = Security.SafeNumber(_G.UIParent:GetEffectiveScale())
    local texture = addon.RXPFrame.GuideName.icon:GetTexture()
    if not scale or not parentScale or scale <= 0 or parentScale <= 0
        or Security.IsSecretValue(texture) or (type(texture) ~= "string" and type(texture) ~= "number") then
        Stop("unsupported-visual"); return
    end
    local badgeScale = scale / parentScale * (Feature.scalePercent / 100)
    if Feature.badgeScale ~= badgeScale then
        Feature.badgeScale = badgeScale
        badge:SetScale(Feature.badgeScale)
    end
    if Feature.iconTexture ~= texture then
        Feature.iconTexture = texture
        badgeIcon:SetTexture(texture)
        logoHighlight:SetTexture(texture)
    end
    local classIcon = addon.RXPFrame.GuideName.classIcon
    local classTexture = classIcon and classIcon:GetTexture()
    if Security.IsSecretValue(classTexture) then Stop("unsupported-visual"); return end
    if classTexture ~= nil and type(classTexture) ~= "string" and type(classTexture) ~= "number" then
        Stop("unsupported-visual"); return
    end
    if Feature.classTexture ~= classTexture then
        Feature.classTexture = classTexture
        badgeClassIcon:SetTexture(classTexture)
    end
    if badgeClassIcon:IsShown() ~= (classTexture ~= nil) then badgeClassIcon:SetShown(classTexture ~= nil) end
    if badge:IsShown() ~= visible then badge:SetShown(visible) end
end

local function OnVisibilityChanged()
    Run(Sync)
end

local function Toggle()
    local addon, reason = ReadTarget()
    if not addon then Stop(reason); return end
    HideTooltip(overlay)
    HideTooltip(badge)
    -- 与官方小地图左键完全相同，包括箭头、计时器及路线运行状态。
    addon.settings.ToggleActive()
    Feature.toggles = Feature.toggles + 1
    Sync()
end

local function OnClick(control, button)
    if button ~= "LeftButton" then return end
    if control == overlay and suppressClick then suppressClick = false; return end
    restoreProfile = nil
    Run(Toggle)
end

local function OnMouseDown()
    suppressClick = false
end

local function StartDrag()
    local addon, reason = ReadTarget()
    if not addon then Stop(reason); return end
    local binding = bindings[addon.RXPFrame]
    suppressClick, dragging = true, true
    HideTooltip(overlay)
    binding.mouseDown(binding.guide, "LeftButton")
end

local function OnDragStart()
    Run(StartDrag)
end

local function OnDragStop()
    Run(EndDrag)
end

local function ShowTooltip(control)
    local addon, reason = ReadTarget()
    if not addon then Stop(reason); return end
    if control == badge and not badgeHovered then
        badgeHovered = true
        GUI2:SetTextColorKey(badgeText, "color.badge.orange.hover")
    end
    if GUI2.Tooltip then GUI2.Tooltip:Show(control, control == badge and collapsedTooltip or expandedTooltip) end
end

local function OnEnter(control)
    Run(ShowTooltip, control)
end

local function EnsureControls(addon)
    local frame, guide = addon.RXPFrame, addon.RXPFrame.GuideName
    if not overlay then
        overlay = GUI2:CreateButtonFrame(_G.UIParent, { hidden = true, clicks = "LeftButtonUp" })
        badge = GUI2:CreateButtonFrame(_G.UIParent, { hidden = true, clicks = "LeftButtonUp", height = 30, clamped = true })
        badgeIcon = GUI2:CreateTexture(badge, { layer = "ARTWORK", width = 24, height = 24 })
        badgeIcon:SetPoint("LEFT", badge, "LEFT", 4, 0)
        badgeClassIcon = GUI2:CreateTexture(badge, { layer = "OVERLAY", width = 14, height = 14 })
        badgeClassIcon:SetPoint("BOTTOMRIGHT", badgeIcon, "BOTTOMRIGHT", 1, 0)
        badgeText = GUI2:CreateText(badge, L["route_guide.label"], "font.size.md", "color.text.primary", "LEFT")
        GUI2:ApplyFontAppearance(badgeText, { size = GUI2:GetMetric("font.size.md", 13), outline = "outlineShadow" })
        badgeText:SetPoint("LEFT", badgeIcon, "RIGHT", 5, 0)
        badge:SetWidth(38 + badgeText:GetStringWidth())
        -- 原生悬停层只叠加图标轮廓，不改原插件纹理，也不产生矩形底色。
        logoHighlight = GUI2:CreateTexture(overlay, { layer = "HIGHLIGHT" })
        logoHighlight:SetAllPoints(overlay)
        logoHighlight:SetBlendMode("ADD")
        logoHighlight:SetAlpha(0.25)
        local footer = { text = "\n" .. string.format(L["route_guide.settings"],
            CoreL["settings.nav.toolbox"], L["name"]), tone = "secondary" }
        expandedTooltip = {
            title = L["route_guide.label"], subtitle = SOURCE_LABEL,
            actions = { { button = "LeftButton", text = L["route_guide.hide"] } },
            footer = footer,
        }
        collapsedTooltip = {
            title = L["route_guide.label"], subtitle = SOURCE_LABEL,
            actions = { { button = "LeftButton", text = L["route_guide.show"] } },
            footer = footer,
        }
    end
    if type(overlay.SetPassThroughButtons) ~= "function" then Stop("missing-passthrough"); return end
    bindings[frame] = {
        addon = addon, settings = addon.settings, toggle = addon.settings.ToggleActive,
        guide = guide, icon = guide.icon,
        mouseDown = guide:GetScript("OnMouseDown"), mouseUp = guide:GetScript("OnMouseUp"),
    }
    Feature.frame = frame
    overlay:SetParent(guide)
    overlay:ClearAllPoints()
    overlay:SetAllPoints(guide.icon)
    overlay:SetFrameLevel(guide:GetFrameLevel() + 2)
    overlay:SetPassThroughButtons("RightButton", "MiddleButton")
    overlay:RegisterForDrag("LeftButton")
    badge:ClearAllPoints()
    badge:SetPoint("LEFT", guide.icon, "LEFT", 0, 0)
    badge:SetFrameStrata(frame:GetFrameStrata())
    for _, control in ipairs({ overlay, badge }) do
        control:SetScript("OnClick", OnClick)
        control:SetScript("OnEnter", OnEnter)
        control:SetScript("OnLeave", HideTooltip)
        control:SetScript("OnHide", HideTooltip)
    end
    overlay:SetScript("OnMouseDown", OnMouseDown)
    overlay:SetScript("OnDragStart", OnDragStart)
    overlay:SetScript("OnDragStop", OnDragStop)
    overlay:SetScript("OnShow", OnVisibilityChanged)
    overlay:SetScript("OnHide", function(control) HideTooltip(control); OnVisibilityChanged() end)
    Feature.attached, Feature.pending = true, false
    overlay:Show()
    Sync()
end

local function TryAttach()
    if Feature.attached then Sync(); return end
    if Security.InCombatLockdown() then Feature.pending = true; return end
    local addon, reason = ReadTarget()
    if not addon then
        if reason ~= "waiting" then Stop(reason) end
        return
    end
    EnsureControls(addon)
end

local function Refresh()
    TryAttach()
    if not (Visibility and type(Visibility.Read) == "function") then return end
    local inInstance = Security.SafeBoolean(Visibility.Read("instance"))
    if inInstance == false then
        instanceHandled = false
        local profile = restoreProfile
        -- 先清理本次自动收起的归属，防止官方回调或重复事件再次恢复。
        restoreProfile = nil
        if not profile or not Feature.attached then return end
        local addon, reason = ReadTarget()
        if not addon then Stop(reason); return end
        if addon.settings.profile == profile and profile.showEnabled == false
            and profile.hideGuideWindow ~= true then Toggle() end
        return
    end
    if inInstance ~= true or instanceHandled or not Feature.attached then return end
    local addon, reason = ReadTarget()
    if not addon then Stop(reason); return end
    -- 接入成功后才消费本次进入；先标记，避免官方切换回调或重复事件再次触发。
    instanceHandled = true
    local profile = addon.settings.profile
    if profile.showEnabled == true and profile.hideGuideWindow ~= true then
        restoreProfile = profile
        Toggle()
    end
end

function Feature:Refresh()
    Run(Refresh)
end

function Feature:SetScale(value)
    local scale = Security and Security.SafeNumber and Security.SafeNumber(value) or 100
    if scale ~= scale then scale = 100 end
    scale = math.floor(math.max(50, math.min(200, scale)) + 0.5)
    if self.scalePercent == scale then return end
    self.scalePercent = scale
    Run(Sync)
end

function Feature:OnAddonLoaded(_, name)
    if name == TARGET_ADDON then self:Refresh() end
end

function Feature:Enable()
    if self.enabled or self.blockedReason then return end
    if not (Event and Event.On and Event.OffOwner and GUI2 and GUI2.CreateButtonFrame
        and GUI2.ApplyFontAppearance and GUI2.GetMetric
        and System and System.IsAddOnLoaded and System.GetAddOnMetadata and Security
        and Security.SafeString and Security.SafeBoolean and Security.SafeNumber
        and Security.IsSecretValue and Security.InCombatLockdown) then return end
    self.enabled = true
    Event:On("ADDON_LOADED", "OnAddonLoaded", self)
    Event:On("YUI_LOGIN_READY", "Refresh", self)
    Event:On("PLAYER_ENTERING_WORLD", "Refresh", self)
    Event:On("PLAYER_REGEN_ENABLED", "Refresh", self)
    self.listeners = 4
    self:Refresh()
end

function Feature:Disable()
    self.enabled = false
    Detach()
end

function Feature:GetStats()
    return {
        enabled = self.enabled, attached = self.attached, pending = self.pending == true,
        listeners = self.listeners, blockedReason = self.blockedReason,
        allocatedButtons = (overlay and 1 or 0) + (badge and 1 or 0), failures = self.failures, toggles = self.toggles,
    }
end

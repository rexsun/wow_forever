local _, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.IsForever then return end

local GUI2, Event = YUI.GUI2, YUI.Event
local Security = YUI.API and YUI.API.Security
local FrameAPI = YUI.API and YUI.API.Frame
local System = YUI.API and YUI.API.System
if not GUI2 or not Event or not Security then return end

local Locale = YUI.Locale and YUI.Locale:Get("CharacterEquipmentInfo") or {}
local Tabs = { active = false }
YUI.CharacterEquipmentTabsForever = Tabs
local hosts = setmetatable({}, { __mode = "k" })
local restoreOwner = {}
local accentHooks = setmetatable({}, { __mode = "k" })
local tabBackground = { .068, .056, .052 }
local tabAtlasBodyHeight = {
    ["uiframe-tab-left"] = 29, ["_uiframe-tab-center"] = 29, ["uiframe-tab-right"] = 29,
    ["uiframe-activetab-left"] = 35, ["_uiframe-activetab-center"] = 35, ["uiframe-activetab-right"] = 35,
}
local tabTemplate, nextButtonID, triedAuctionUI
nextButtonID = 0
local names = {
    PaperDollFrame = "character", InspectPaperDollFrame = "character",
    ReputationFrame = "reputation", SkillsFrame = "skills",
    PVPRankFrame = "honor", InspectPVPFrame = "honor",
    TokenFrame = "currency", StatisticsFrame = "statistics", InspectGuildFrame = "guild",
}

local function InCombat()
    return Security.InCombatLockdown and Security.InCombatLockdown()
end

local function RequestRefresh()
    if Tabs.active and Tabs.requestRefresh then Tabs.requestRefresh() end
end

local function ResolveSkin()
    local provider = _G.EllesmereUI
    if not provider or type(provider.GetBlizzWindowStyle) ~= "function" then return end
    local ok, style = pcall(provider.GetBlizzWindowStyle, "charsheet")
    if not ok or (style ~= "eui" and style ~= "modern") then return end
    local r, g, b = provider.DEFAULT_ACCENT_R or .51, provider.DEFAULT_ACCENT_G or .784, provider.DEFAULT_ACCENT_B or 1
    if type(provider.GetAccentColor) == "function" then
        local read, ar, ag, ab = pcall(provider.GetAccentColor)
        if read and type(ar) == "number" and type(ag) == "number" and type(ab) == "number" then r, g, b = ar, ag, ab end
    end
    if Tabs.accentR ~= r or Tabs.accentG ~= g or Tabs.accentB ~= b then
        Tabs.accentR, Tabs.accentG, Tabs.accentB = r, g, b
        Tabs.accentRevision = (Tabs.accentRevision or 0) + 1
    end
    if not accentHooks[provider] and type(_G.hooksecurefunc) == "function" and type(provider.ApplyAccentColorLive) == "function" then
        accentHooks[provider] = true
        _G.hooksecurefunc(provider, "ApplyAccentColorLive", RequestRefresh)
    end
    local pixel = (provider.PanelPP and provider.PanelPP.mult) or GUI2.mult or 1
    if type(pixel) ~= "number" or pixel <= 0 then pixel = GUI2.mult or 1 end
    return provider, pixel
end

local Paint
local function SyncNativeLabel(button)
    local shown = button.skinActive ~= true
    if button.label:IsShown() ~= shown then button.label:SetShown(shown) end
end

local function BuildSkin(button)
    local skin = {}
    skin.background = GUI2:CreateTexture(button, { layer = "BACKGROUND" })
    skin.background:SetAllPoints()
    skin.background:SetColorTexture(tabBackground[1], tabBackground[2], tabBackground[3], 1)
    skin.wash = GUI2:CreateTexture(button, { layer = "ARTWORK" })
    skin.wash:SetAllPoints()
    skin.wash:SetBlendMode("ADD")
    skin.underline = GUI2:CreateTexture(button, { layer = "OVERLAY", subLevel = 6 })
    skin.underline:SetPoint("BOTTOMLEFT")
    skin.underline:SetPoint("BOTTOMRIGHT")
    skin.label = GUI2:CreateText(button, "", 12, "color.text.primary", "CENTER")
    skin.label.gui2ColorKey = nil
    skin.label:SetWordWrap(false)
    skin.label:SetPoint("CENTER")
    skin.enter = function() button.hovered = true; Paint(button) end
    skin.leave = function() button.hovered = false; Paint(button) end
    skin.hide = function() button.hovered = false end
    button.skin = skin
    return skin
end

local function ApplySkin(button, provider, pixel)
    local active = provider ~= nil
    if button.skinActive == active and button.skinProvider == provider and (not active or button.skinPixel == pixel) then return end
    button.skinActive, button.skinProvider, button.paintedSkin = active, provider, nil
    button.skinPixel = pixel
    button.hovered = false
    for _, art in ipairs(button.nativeArt) do art.texture:SetAlpha(active and 0 or art.alpha) end
    button.label:SetAlpha(active and 0 or button.nativeLabelAlpha)
    if active then
        local skin = button.skin or BuildSkin(button)
        if type(provider.ApplyModuleFont) == "function" then
            local _, size = button.label:GetFont()
            pcall(provider.ApplyModuleFont, skin.label, nil, size or 12, "blizzardSkin")
        end
        if provider.PanelPP and type(provider.PanelPP.DisablePixelSnap) == "function" then
            pcall(provider.PanelPP.DisablePixelSnap, skin.underline)
        end
        skin.underline:SetHeight(pixel)
        skin.background:Show(); skin.label:Show()
        button:SetScript("OnEnter", skin.enter)
        button:SetScript("OnLeave", skin.leave)
        button:SetScript("OnHide", skin.hide)
    else
        if button.skin then for _, part in ipairs({ "background", "wash", "underline", "label" }) do button.skin[part]:Hide() end end
        button:SetScript("OnEnter", nil)
        button:SetScript("OnLeave", nil)
    end
end

Paint = function(button)
    local selected = button.selected == true
    local enabled = not InCombat() and (not button.native.IsEnabled or button.native:IsEnabled())
    local changed = button.paintedSelected ~= selected or button.paintedEnabled ~= enabled
    if changed then
        button.paintedSelected, button.paintedEnabled = selected, enabled
        if selected then _G.PanelTemplates_SelectTab(button)
        else _G.PanelTemplates_DeselectTab(button) end
        if not enabled then button:Disable() end
        button:SetAlpha(1)
    end
    -- 按钮的字体状态与皮肤文字独立，显式隐藏原生文字以避免双份渲染。
    SyncNativeLabel(button)
    if button.skinActive and (changed or button.paintedSkin ~= true or button.paintedHover ~= button.hovered
        or button.paintedAccent ~= Tabs.accentRevision) then
        local skin = button.skin
        skin.label:SetTextColor(1, 1, 1, not enabled and .25 or ((selected or button.hovered) and 1 or .5))
        skin.wash:SetColorTexture(1, 1, 1, button.hovered and .05 or .02)
        skin.wash:SetShown(selected or button.hovered == true)
        skin.underline:SetColorTexture(Tabs.accentR, Tabs.accentG, Tabs.accentB, enabled and 1 or .4)
        skin.underline:SetShown(selected)
        button.paintedSkin, button.paintedHover, button.paintedAccent = true, button.hovered, Tabs.accentRevision
    end
end

local function ResolveTemplate()
    if tabTemplate then return tabTemplate end
    if not FrameAPI or not FrameAPI.GetXMLTemplateInfo or type(_G.PanelTemplates_TabResize) ~= "function"
        or type(_G.PanelTemplates_SelectTab) ~= "function" or type(_G.PanelTemplates_DeselectTab) ~= "function" then return end
    for _, candidate in ipairs({ "AuctionTabTemplate", "AuctionHouseFrameTabTemplate" }) do
        if FrameAPI.GetXMLTemplateInfo(candidate) then tabTemplate = candidate; return candidate end
    end
    if not triedAuctionUI and System and System.LoadAddOn then
        triedAuctionUI = true
        for _, name in ipairs({ "Blizzard_AuctionUI", "Blizzard_AuctionHouseUI" }) do
            if System.DoesAddOnExist and System.DoesAddOnExist(name) then
                pcall(System.LoadAddOn, name)
                for _, candidate in ipairs({ "AuctionTabTemplate", "AuctionHouseFrameTabTemplate" }) do
                    if FrameAPI.GetXMLTemplateInfo(candidate) then tabTemplate = candidate; return candidate end
                end
            end
        end
    end
    for _, candidate in ipairs({ "CharacterFrameTabButtonTemplate", "PanelTabButtonTemplate" }) do
        if FrameAPI.GetXMLTemplateInfo(candidate) then tabTemplate = candidate; return candidate end
    end
end

local function CropTabShadow(texture)
    local bodyHeight = tabAtlasBodyHeight[texture:GetAtlas()]
    if not bodyHeight then return end
    -- 图集原图是标签本体加 7 行阴影，裁剪比例不取决于当前控件高度。
    texture:SetTexCoord(0, 1, 0, bodyHeight / (bodyHeight + 7))
    texture:SetHeight(bodyHeight)
end

local function BuildButton(state, native)
    nextButtonID = nextButtonID + 1
    local name = "YUIEquipmentBottomTab" .. nextButtonID
    local button = GUI2:CreateButtonFrame(state.row, { name = name,
        template = tabTemplate, clicks = "LeftButtonUp" })
    -- 原生模板只负责美术；移除它与角色／拍卖行窗口的事件和切页耦合。
    button:UnregisterAllEvents()
    button:SetScript("OnEvent", nil)
    button:SetScript("OnShow", nil)
    button:SetScript("OnEnter", nil)
    button:SetScript("OnLeave", nil)
    -- 两类模板分别使用单张控件高亮或三段 HIGHLIGHT 纹理；保留原生选中图层。
    local highlight = button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
    for _, part in ipairs({ "LeftHighlight", "MiddleHighlight", "RightHighlight" }) do
        local texture = button[part]
        if texture then texture:SetAlpha(0) end
    end
    button.native = native
    button.label = button:GetFontString()
    button.Text = button.Text or button.label
    for _, part in ipairs({ "Left", "Middle", "Right" }) do
        button[part] = button[part] or _G[name .. part]
        local active = button[part .. "Active"] or button[part .. "Disabled"] or _G[name .. part .. "Disabled"]
        button[part .. "Active"], button[part .. "Disabled"] = active, active
    end
    button.nativeArt, button.nativeLabelAlpha = {}, button.label:GetAlpha()
    for _, part in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive" }) do
        local texture = button[part]
        if texture then
            CropTabShadow(texture)
            button.nativeArt[#button.nativeArt + 1] = { texture = texture, alpha = texture:GetAlpha() }
        end
    end
    button.label:SetWordWrap(false)
    button:SetScript("OnClick", function()
        if not Tabs.active or not state.applied or InCombat() or not native:IsShown()
            or (native.IsEnabled and not native:IsEnabled()) then return end
        -- 由原生入口处理切页、声音及条件；不复制角色或观察窗口的切页逻辑。
        native:OnMouseUp("LeftButton", true)
        RequestRefresh()
    end)
    if type(_G.hooksecurefunc) == "function" and type(native.SetChecked) == "function" then
        _G.hooksecurefunc(native, "SetChecked", function(_, checked)
            button.selected = checked == true
            if Tabs.active and state.applied then Paint(button); RequestRefresh() end
        end)
    end
    -- 原生容器隐藏后，子项的条件变化不一定触发 OnShow / OnHide。
    if type(_G.hooksecurefunc) == "function" then
        for _, method in ipairs({ "Show", "Hide", "SetShown" }) do
            if type(native[method]) == "function" then _G.hooksecurefunc(native, method, RequestRefresh) end
        end
    end
    if type(native.HookScript) == "function" then
        native:HookScript("OnShow", RequestRefresh)
        native:HookScript("OnHide", RequestRefresh)
    end
    state.buttons[native] = button
    return button
end

local function Restore(state)
    if state.row then state.row:Hide() end
    if state.applied and not InCombat() then
        state.applied = false
        state.native:SetShown(state.wasShown)
    end
end

local function UpdateHost(host, provider, pixel)
    if not host or not host:IsShown() then return end
    local native = host.ModeTabs
    if not native or not native.Tabs or #native.Tabs == 0 then return end
    local state = hosts[host]
    if state and state.native ~= native then Restore(state); state = nil end
    -- 未识别的客户端入口保留整组原生导航，避免丢失条件页签。
    for _, tab in ipairs(native.Tabs) do
        if type(tab.OnMouseUp) ~= "function" or type(tab.GetID) ~= "function" then
            if state then Restore(state) end
            return
        end
    end
    if not ResolveTemplate() then if state then Restore(state) end; return end
    if not state then
        if not native:IsShown() then return end
        state = { native = native, buttons = {} }
        state.row = GUI2:CreateFrame(host, { height = 35, hidden = true })
        state.row:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 8, 2)
        state.row:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", -8, 2)
        hosts[host] = state
    end
    if not state.applied then
        state.wasShown = native:IsShown()
        if not state.wasShown then return end
        state.applied = true
    end
    native:Hide()
    local count = 0
    for _, tab in ipairs(native.Tabs) do if tab:IsShown() then count = count + 1 end end
    local overlap = provider and -pixel or ((tabTemplate == "AuctionTabTemplate" or tabTemplate == "CharacterFrameTabButtonTemplate") and 15 or 0)
    local previous, totalWidth = nil, -math.max(0, count - 1) * overlap
    -- 仅在补建按钮时隐藏父层，避免普通属性刷新中断当前悬停。
    for _, tab in ipairs(native.Tabs) do if not state.buttons[tab] then state.row:Hide(); break end end
    for _, button in pairs(state.buttons) do button.present = false end
    for _, tab in ipairs(native.Tabs) do
        local button = state.buttons[tab] or BuildButton(state, tab)
        if tab:IsShown() then
            button.present = true
            local frameName = tab.frameName or (host == _G.InspectFrame
                and _G.INSPECTFRAME_SUBFRAMES and _G.INSPECTFRAME_SUBFRAMES[tab:GetID()])
            local key = names[frameName]
            -- 原生键盘快捷键、条件回退和外部调用也会更新 SetChecked。
            button.selected = tab.SelectedTexture and tab.SelectedTexture:IsShown()
                or (not tab.SelectedTexture and host.selectedTab == tab:GetID())
            ApplySkin(button, provider, pixel)
            Paint(button)
            local label = (key and Locale["tabs." .. key]) or tab.tooltipText or tostring(tab:GetID())
            if button.displayText ~= label then
                button:SetText(label)
                _G.PanelTemplates_TabResize(button, 0, nil, 36, 88)
                button.displayText, button.naturalWidth, button.fittedWidth = label, button:GetWidth(), nil
            end
            if button.skinActive and button.skin.text ~= label then
                button.skin.label:SetText(label)
                button.skin.text = label
            end
            totalWidth = totalWidth + button.naturalWidth
            if not button.anchored or button.previous ~= previous or button.overlap ~= overlap then
                button:ClearAllPoints()
                if previous then button:SetPoint("LEFT", previous, "RIGHT", -overlap, 0)
                else button:SetPoint("TOPLEFT", state.row, "TOPLEFT") end
                button.previous, button.anchored, button.overlap = previous, true, overlap
            end
            button:Show()
            previous = button
        end
    end
    local fitted = totalWidth > host:GetWidth() - 16
        and (host:GetWidth() - 16 + math.max(0, count - 1) * overlap) / math.max(1, count) or nil
    for _, button in pairs(state.buttons) do
        if button.present and button.fittedWidth ~= fitted then
            _G.PanelTemplates_TabResize(button, 0, fitted, 36, 88)
            button.fittedWidth = fitted
        end
        if button.present and button.skinActive and button.skin.width ~= button:GetWidth() then
            button.skin.width = button:GetWidth()
            button.skin.label:SetWidth(math.max(1, button:GetWidth() - 12))
        end
        if button.present then SyncNativeLabel(button) end
    end
    for _, button in pairs(state.buttons) do if not button.present then button:Hide() end end
    state.row:SetShown(count > 0)
end

function Tabs:Refresh(enabled, requestRefresh)
    self.requestRefresh = requestRefresh
    if enabled == false then self:Stop(); return end
    self.active = true
    Event:OffOwner(restoreOwner)
    if InCombat() then return end
    local provider, pixel = ResolveSkin()
    UpdateHost(_G.CharacterFrame, provider, pixel)
    UpdateHost(_G.InspectFrame, provider, pixel)
end

function Tabs:CombatChanged()
    for _, state in pairs(hosts) do
        if state.applied then for _, button in pairs(state.buttons) do Paint(button) end end
    end
end

function Tabs:Stop()
    self.active = false
    self.requestRefresh = nil
    Event:OffOwner(restoreOwner)
    local pending = false
    for _, state in pairs(hosts) do
        Restore(state)
        pending = pending or state.applied
    end
    if pending then
        Event:Once("PLAYER_REGEN_ENABLED", function()
            if self.active then return end
            for _, state in pairs(hosts) do Restore(state) end
        end, restoreOwner)
    end
end

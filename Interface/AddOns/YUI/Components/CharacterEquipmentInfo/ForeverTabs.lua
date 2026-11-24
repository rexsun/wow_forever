local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
local Native = YUI and YUI.NativeInterface
if not (YUI and YUI.IsForever and Native and Native.IS_SUITE) or Native.ApplyCharacterBottomTabs then return end
if YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite") ~= "suite" then return end

local GUI2, Event = YUI.GUI2, YUI.Event
local Security = YUI.API and YUI.API.Security
local FrameAPI = YUI.API and YUI.API.Frame
local System = YUI.API and YUI.API.System
if not GUI2 or not Event or not Security then return end

local Locale = YUI.Locale and YUI.Locale:Get("CharacterEquipmentInfo") or {}
local Tabs = { active = false }
local hosts = setmetatable({}, { __mode = "k" })
local owner, regenOwner = {}, {}
local eventOptions = { moduleId = Native.MODULE_ID }
local accentHooks = setmetatable({}, { __mode = "k" })
local layoutHooks = setmetatable({}, { __mode = "k" })
local frameHooks = setmetatable({}, { __mode = "k" })
local RequestRefresh
local Unpack = unpack or table.unpack
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
    else
        if button.skin then for _, part in ipairs({ "background", "wash", "underline", "label" }) do button.skin[part]:Hide() end end
    end
end

Paint = function(button)
    local selected = button.selected == true
    local enabled = not button.native.IsEnabled or button.native:IsEnabled()
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
    local button = GUI2:CreateButtonFrame(state.row, { name = name, template = tabTemplate, clicks = "LeftButtonUp" })
    button:EnableMouse(false)
    -- 原生模板只负责美术；移除它与角色／拍卖行窗口的事件和切页耦合。
    button:UnregisterAllEvents()
    button:SetScript("OnEvent", nil)
    button:SetScript("OnShow", nil)
    button:SetScript("OnEnter", nil)
    button:SetScript("OnLeave", nil)
    button:SetScript("OnClick", nil)
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
    if type(_G.hooksecurefunc) == "function" and type(native.SetChecked) == "function" then
        _G.hooksecurefunc(native, "SetChecked", function(_, checked)
            checked = checked == true
            if not button.originalPoints or button.selected == checked then return end
            button.selected = checked
            Paint(button)
            Tabs.layoutChanged = true
            RequestRefresh()
        end)
    end
    if type(native.HookScript) == "function" then
        local function SyncVisibility()
            if not button.originalPoints then return end
            button.hovered = false
            button:SetShown(state.native:IsShown() and native:IsShown())
            Paint(button)
            Tabs.layoutChanged = true
            RequestRefresh()
        end
        native:HookScript("OnShow", SyncVisibility)
        native:HookScript("OnHide", SyncVisibility)
        native:HookScript("OnEnter", function()
            if not button.originalPoints then return end
            local tooltip = _G.GetAppropriateTooltip and _G.GetAppropriateTooltip()
            if tooltip and tooltip:IsOwned(native) then Security.HideTooltip(tooltip) end
            button.hovered = true
            Paint(button)
        end)
        native:HookScript("OnLeave", function()
            if not button.originalPoints then return end
            button.hovered = false
            Paint(button)
        end)
    end
    state.buttons[native] = button
    return button
end

local function AnchorNativeTab(button)
    local native = button.native
    local count = native:GetNumPoints()
    if button.originalPoints and count == 2 then
        local _, first = native:GetPoint(1)
        local _, second = native:GetPoint(2)
        if first == button and second == button then return end
    end

    local points = {}
    for index = 1, count do
        local point, relative, relativePoint, x, y = native:GetPoint(index)
        if relative ~= button then points[#points + 1] = { point, relative, relativePoint, x, y } end
    end
    if not button.originalPoints then
        button.originalAlpha = native:GetAlpha()
        native:SetAlpha(0)
    end
    if #points > 0 or not button.originalPoints then button.originalPoints = points end
    -- 保留父级和原生鼠标脚本，命中区域跟随同一份底部标签外观。
    native:ClearAllPoints()
    native:SetAllPoints(button)
end

local function AppliedCorner(native, index, button)
    local point, relative, relativePoint, x, y = native:GetPoint(index)
    local secret = Security.IsSecretValue
    if secret and (secret(point) or secret(relative) or secret(relativePoint) or secret(x) or secret(y)) then return end
    if relative == button and point == relativePoint and x == 0 and y == 0 then return point end
end

local function RestoreNativeTab(button)
    local points = button.originalPoints
    if not points then return end
    button.originalPoints, button.hovered = nil, false
    local native = button.native
    if native:GetNumPoints() == 2 then
        local a, b = AppliedCorner(native, 1, button), AppliedCorner(native, 2, button)
        if (a == "TOPLEFT" and b == "BOTTOMRIGHT") or (a == "BOTTOMRIGHT" and b == "TOPLEFT") then
            native:ClearAllPoints()
            for _, point in ipairs(points) do native:SetPoint(Unpack(point, 1, 5)) end
        end
    end
    if native:GetAlpha() == 0 then native:SetAlpha(button.originalAlpha) end
end

local function Restore(state)
    if not state.applied or InCombat() then return end
    state.applied = false
    Tabs.layoutChanged = true
    for _, button in pairs(state.buttons) do RestoreNativeTab(button) end
    state.row:Hide()
end

local function LayoutButton(state, button, previous, overlap)
    if not button.anchored or button.previous ~= previous or button.overlap ~= overlap then
        button:ClearAllPoints()
        if previous then button:SetPoint("LEFT", previous, "RIGHT", -overlap, 0)
        else button:SetPoint("TOPLEFT", state.row, "TOPLEFT") end
        button.previous, button.anchored, button.overlap = previous, true, overlap
    end
end

local function HookFrame(frame, sizeChanged)
    if not frame or frameHooks[frame] or type(frame.HookScript) ~= "function" then return end
    frameHooks[frame] = true
    frame:HookScript("OnShow", RequestRefresh)
    frame:HookScript(sizeChanged and "OnSizeChanged" or "OnHide", RequestRefresh)
end

local function UpdateHost(host, provider, pixel)
    if not host then return end
    if Native.GetWindowEnhancementController and
        Native:GetWindowEnhancementController(host == _G.CharacterFrame and "character" or "inspect") then
        local state = hosts[host]
        if state then Restore(state) end
        return
    end
    local native = host.ModeTabs
    HookFrame(host, true)
    HookFrame(native, false)
    local state = hosts[host]
    if state and state.native ~= native then Restore(state); hosts[host] = nil; state = nil end
    if not native or not native.Tabs or #native.Tabs == 0 then
        if state then Restore(state) end
        return
    end
    local shown = host:IsShown()
    local hostWidth = host:GetWidth()
    -- 角色面板首次显示才会应用展开或收起后的宽度。
    if not shown and host == _G.CharacterFrame and type(host.IsRightPaneCollapsed) == "function" then
        local width = host:IsRightPaneCollapsed() and _G.CHARACTER_FRAME_COLLAPSED_WIDTH or _G.CHARACTER_FRAME_WIDTH
        hostWidth = width or hostWidth
    end
    -- 脱战时也准备尚未打开的面板，首次在战斗中打开即可使用同一排标签。
    if state and state.applied and not shown and not state.layoutDirty and state.hostWidth == hostWidth
        and state.provider == provider and state.pixel == pixel and state.accentRevision == Tabs.accentRevision then return end
    if hostWidth <= 16 then return end
    -- 未识别的客户端入口保留整组原生导航，避免丢失条件页签。
    for _, tab in ipairs(native.Tabs) do
        if type(tab.OnMouseUp) ~= "function" or type(tab.GetID) ~= "function"
            or type(tab.GetNumPoints) ~= "function" or (tab.IsProtected and tab:IsProtected()) then
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
    if not state.applied and not native:IsShown() then return end
    if not layoutHooks[host] and type(_G.hooksecurefunc) == "function" then
        local method = host == _G.CharacterFrame and "UpdateTabLayout" or "InitializeModeTabLayout"
        if type(host[method]) == "function" then
            layoutHooks[host] = true
            _G.hooksecurefunc(host, method, function()
                local current = hosts[host]
                if not current or not current.applied then return end
                current.layoutDirty = true
                RequestRefresh()
            end)
        end
    end
    if not state.applied or state.layoutDirty then Tabs.layoutChanged = true end
    state.applied = true
    local count = 0
    for _, tab in ipairs(native.Tabs) do if tab:IsShown() then count = count + 1 end end
    local overlap = provider and -pixel or ((tabTemplate == "AuctionTabTemplate" or tabTemplate == "CharacterFrameTabButtonTemplate") and 15 or 0)
    local previous, totalWidth = nil, -math.max(0, count - 1) * overlap
    -- 仅在补建按钮时隐藏父层，避免普通属性刷新中断当前悬停。
    for _, tab in ipairs(native.Tabs) do if not state.buttons[tab] then state.row:Hide(); break end end
    for _, button in pairs(state.buttons) do button.present = false end
    for _, tab in ipairs(native.Tabs) do
        local button = state.buttons[tab] or BuildButton(state, tab)
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
        if tab:IsShown() then
            totalWidth = totalWidth + button.naturalWidth
            LayoutButton(state, button, previous, overlap)
            previous = button
        end
    end
    local fitted = totalWidth > hostWidth - 16
        and (hostWidth - 16 + math.max(0, count - 1) * overlap) / math.max(1, count) or nil
    for _, tab in ipairs(native.Tabs) do
        local button = state.buttons[tab]
        local shown = tab:IsShown()
        if not shown then
            -- 条件标签可以在战斗中出现，预先放到当前可见标签末尾。
            LayoutButton(state, button, previous, overlap)
            previous = button
        end
        if button.fittedWidth ~= fitted then
            _G.PanelTemplates_TabResize(button, 0, fitted, 36, 88)
            button.fittedWidth = fitted
        end
        if button.skinActive and button.skin.width ~= button:GetWidth() then
            button.skin.width = button:GetWidth()
            button.skin.label:SetWidth(math.max(1, button:GetWidth() - 12))
        end
        SyncNativeLabel(button)
        AnchorNativeTab(button)
        local visible = shown and native:IsShown()
        if button:IsShown() ~= visible then button:SetShown(visible) end
    end
    for _, button in pairs(state.buttons) do
        if not button.present then
            RestoreNativeTab(button)
            button:Hide()
        end
    end
    state.layoutDirty = false
    state.hostWidth = hostWidth
    state.provider, state.pixel, state.accentRevision = provider, pixel, Tabs.accentRevision
    if not state.row:IsShown() then state.row:Show() end
end

local function NotifyLayoutChanged()
    if not Tabs.layoutChanged then return end
    Tabs.layoutChanged = false
    Event:Emit("YUI_CHARACTER_BOTTOM_TABS_CHANGED")
end

local Refresh
local function OnRegen()
    Tabs.waitingForRegen = false
    if Tabs.active then
        Refresh()
    else
        for _, state in pairs(hosts) do Restore(state) end
        NotifyLayoutChanged()
    end
end

local function WaitForRegen()
    if Tabs.waitingForRegen then return end
    Tabs.waitingForRegen = true
    Event:Once("PLAYER_REGEN_ENABLED", OnRegen, regenOwner, eventOptions)
end

Refresh = function()
    if not Tabs.active or Tabs.refreshing then return end
    if InCombat() then WaitForRegen(); return end
    Tabs.refreshing = true
    local provider, pixel = ResolveSkin()
    UpdateHost(_G.CharacterFrame, provider, pixel)
    UpdateHost(_G.InspectFrame, provider, pixel)
    Tabs.refreshing = false
    NotifyLayoutChanged()
end

local function RunRefresh()
    Tabs.timer = nil
    Refresh()
end

RequestRefresh = function()
    if not Tabs.active or Tabs.refreshing or Tabs.timer then return end
    if InCombat() then WaitForRegen(); return end
    Tabs.timer = C_Timer.NewTimer(0, RunRefresh)
end

local function OnAddonLoaded(_, addon)
    if addon == "Blizzard_UIPanels_Game" or addon == "Blizzard_InspectUI" then RequestRefresh() end
end

local function Stop()
    if Tabs.active then
        Tabs.active = false
        Event:OffOwner(owner)
        if Tabs.timer then Tabs.timer:Cancel(); Tabs.timer = nil end
    end
    local pending = false
    for _, state in pairs(hosts) do
        Restore(state)
        pending = pending or state.applied
    end
    if pending then
        WaitForRegen()
    elseif Tabs.waitingForRegen then
        Event:OffOwner(regenOwner)
        Tabs.waitingForRegen = false
    end
    NotifyLayoutChanged()
end

function Native:ApplyCharacterBottomTabs(enabled)
    if enabled ~= true then Stop(); return end
    if not Tabs.active then
        Tabs.active = true
        Event:On("ADDON_LOADED", OnAddonLoaded, owner, eventOptions)
        if not (YUI.Lifecycle and YUI.Lifecycle:IsReady("YUI_WORLD_READY")) then
            Event:Once("YUI_WORLD_READY", RequestRefresh, owner, eventOptions)
        end
    end
    if Tabs.timer then Tabs.timer:Cancel(); Tabs.timer = nil end
    Refresh()
end

function Native:IsCharacterBottomTabsApplied(host)
    local state = host and hosts[host]
    return state ~= nil and state.applied == true and not state.layoutDirty and state.native == host.ModeTabs
end

local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local GUI2 = YUI.GUI2
local DesignerUI = YHUD.DesignerUI
local Designer = YHUD.Designer
local View = YHUD.View
if not (GUI2 and GUI2.Form and DesignerUI and Designer and View) then return end

local function T(key, fallback)
    return YHUD:T(key, fallback)
end

local SKYRIDING_GROUP_ID = YHUD.GROUP_IDS and YHUD.GROUP_IDS.SKYRIDING
    or "group:system:skyriding"
local SUPPORTS_SKYRIDING = not (YHUD.Client and YHUD.Client.skyriding == false)
local SKYRIDING_GEOMETRY_FIELDS = {
    width = true, speedHeight = true, vigorHeight = true, secondWindHeight = true,
    rowGap = true, pipGap = true, resourceHeight = true, iconSize = true, ringThickness = true,
    cooldownStyle = true, cooldownBarHeight = true,
}

local function ThemeColor(key)
    return { GUI2:GetColor(key) }
end

local function CooldownTabName()
    local skyriding = YHUD.Skyriding
    return skyriding and skyriding.GetCooldownSpellName and skyriding:GetCooldownSpellName()
        or T("skyriding.settings.cooldown_ability", "技能冷却")
end

function DesignerUI:ApplySkyridingPreview(appearanceOnly)
    local session = Designer:GetSession()
    local skyriding = YHUD.Skyriding
    if not (session and View.designMode and self.designerMode == "skyriding"
        and skyriding and skyriding.ApplySettings) then
        return self:ApplyPreview()
    end
    local profile = Designer.GetPresentationProfile
        and Designer:GetPresentationProfile() or Designer:GetProfile()
    if not skyriding:ApplySettings(profile, true, appearanceOnly == true) then return false end
    if appearanceOnly ~= true then
        local synced = skyriding:SyncConfigurationActivity()
        if synced == nil then return false end
        if View.RefreshDesignProjectionAnchors then View:RefreshDesignProjectionAnchors() end
    end
    return true
end

function DesignerUI:RefreshSkyridingSettingsPanel()
    local panel = self.skyridingSettingsPanel
    if not panel then return false end
    local profile = Designer.GetPresentationProfile
        and Designer:GetPresentationProfile() or Designer:GetProfile()
    local settings = YHUD.GetSkyridingSettings
        and YHUD:GetSkyridingSettings(profile) or {}
    local styleId = "halo"
    local styleSettings = settings.styles and settings.styles[styleId] or {}
    self.skyridingSettingsRefreshing = true
    panel.enabled:SetValue(settings.enabled == true, true)
    panel.styleSelector:SetValue(styleId, true)
    panel.styleSelector:Hide()
    panel.width:SetValue(tonumber(styleSettings.width) or 287, true)
    panel.cooldownStyle:SetValue(styleSettings.cooldownStyle or "right", true)
    panel.speedHeight:SetValue(tonumber(styleSettings.speedHeight) or 16, true)
    panel.rowGap:SetValue(tonumber(styleSettings.rowGap) or 1, true)
    panel.pipGap:SetValue(tonumber(styleSettings.pipGap) or 2, true)
    panel.resourceHeight:SetValue(
        tonumber(styleSettings.resourceHeight) or 8,
        true
    )
    panel.iconSize:SetValue(tonumber(styleSettings.iconSize) or 48, true)
    panel.ringThickness:SetValue(
        tonumber(styleSettings.ringThickness) or 4,
        true
    )
    panel.vigorHeight:SetValue(tonumber(styleSettings.vigorHeight) or 9, true)
    panel.secondWindHeight:SetValue(
        tonumber(styleSettings.secondWindHeight) or 9,
        true
    )
    panel.vigorColor:SetValue(
        styleSettings.vigorColor or { 0.10, 0.88, 0.64, 1 },
        true
    )
    panel.secondWindColor:SetValue(
        styleSettings.secondWindColor or { 1.00, 0.76, 0.18, 1 },
        true
    )
    panel.speedFont:SetTarget("yhud:skyriding/speedText")
    panel.cooldownBarTextFont:SetTarget("yhud:skyriding/cooldownBarText")
    for _, field in ipairs({ "cooldownBarHeight", "cooldownBarTexture", "cooldownBarColor",
        "cooldownBarBackgroundColor", "cooldownBarBorder", "cooldownBarText" }) do
        panel[field]:SetValue(styleSettings[field], true)
    end
    panel.cooldownBarBorderColor:SetValue(type(styleSettings.cooldownBarBorderColor) == "table"
        and styleSettings.cooldownBarBorderColor or ThemeColor("color.border.subtle"), true)
    panel.fillTexture:SetValue(styleSettings.fillTexture or "solid", true)
    panel.border:SetValue(styleSettings.border or 1, true)
    panel.speedText:SetValue(styleSettings.speedText ~= false, true)
    for _, field in ipairs({ "speedColor", "thrillColor", "backgroundColor", "emptyColor" }) do
        panel[field]:SetValue(styleSettings[field], true)
    end
    panel.borderColor:SetValue(type(styleSettings.borderColor) == "table"
        and styleSettings.borderColor or ThemeColor("color.border.subtle"), true)
    local horizon = styleId == "horizon"
    panel.resourceHeight:SetShown(horizon)
    panel.iconSize:SetShown(horizon)
    panel.ringThicknessLabel:SetShown(horizon)
    panel.ringThickness:SetShown(horizon)
    panel.vigorHeight:SetShown(not horizon)
    panel.secondWindHeight:SetShown(not horizon)
    local extraHeight = horizon and 38 or 0
    panel:SetHeight(540 + extraHeight)
    local barMode = styleSettings.cooldownStyle == "bar"
    local page = panel.page or "layout"
    local abilityName = CooldownTabName()
    if panel.tabItems[4].text ~= abilityName then
        panel.tabItems[4].text = abilityName
        panel.tabs:SetItems(panel.tabItems, page)
    end
    panel.tabs:SetValue(page, true)
    for id, controls in pairs(panel.pages) do
        for index = 1, #controls do controls[index]:SetShown(id == page) end
    end
    for _, control in ipairs(panel.cooldownBarControls) do
        control:SetShown(page == "cooldown" and barMode)
    end
    self.skyridingSettingsRefreshing = false
    return true
end

function DesignerUI:EnsureSkyridingSettingsPanel()
    if not SUPPORTS_SKYRIDING then return nil end
    if self.skyridingSettingsPanel then return self.skyridingSettingsPanel end
    local panel = GUI2:CreatePanel(_G.UIParent, {
        width = 360,
        height = 578,
        surface = "color.surface.panel",
        border = "color.border.default",
    })
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(430)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:Hide()

    panel.dragHandle = GUI2:CreateFrame(panel, {
        width = 324,
        height = 34,
        mouse = true,
    })
    panel.dragHandle:SetPoint("TOP", panel, "TOP", 0, -8)
    panel.dragHandle:RegisterForDrag("LeftButton")
    panel.dragHandle:SetScript("OnDragStart", function()
        if DesignerUI.active then
            DesignerUI.manualPanel = true
            panel:StartMoving()
        end
    end)
    panel.dragHandle:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
    end)
    local lastHeaderClick = 0
    panel.dragHandle:SetScript("OnMouseUp", function(_, button)
        if button and button ~= "LeftButton" then return end
        local now = _G.GetTime and _G.GetTime() or 0
        if now - lastHeaderClick <= 0.35 then
            DesignerUI.manualPanel = false
            if DesignerUI.PositionSkyridingSettingsPanel then
                DesignerUI:PositionSkyridingSettingsPanel(true)
            end
            lastHeaderClick = 0
        else
            lastHeaderClick = now
        end
    end)

    panel.title = GUI2:CreateText(
        panel.dragHandle,
        T("skyriding.settings.title", "驭龙术设置"),
        "font.size.lg",
        "color.text.primary",
        "LEFT"
    )
    panel.title:SetPoint("LEFT", panel.dragHandle, "LEFT", 2, 0)

    panel.enabledLabel = GUI2:CreateText(
        panel,
        T("skyriding.settings.enabled", "启用"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    panel.enabledLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -58)
    panel.enabled = GUI2.Form:CreateSwitch(panel, {
        width = 64,
        height = 24,
        value = false,
        set = function(value)
            if DesignerUI.skyridingSettingsRefreshing then return end
            if Designer:SetSkyridingSettings({ enabled = value == true }) then
                DesignerUI:ApplySkyridingPreview(false)
                DesignerUI:RefreshSkyridingSettingsPanel()
            end
        end,
    })
    panel.enabled:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -52)

    panel.styleSelector = GUI2.Form:CreateSegmentedControl(panel, {
        width = 324,
        height = 28,
        value = "horizon",
        items = {
            {
                text = T("skyriding.style.horizon", "横贯式"),
                value = "horizon",
            },
            {
                text = T("skyriding.style.halo", "堆叠式"),
                value = "halo",
            },
        },
        set = function(value)
            if DesignerUI.skyridingSettingsRefreshing then return end
            if Designer:SetSkyridingSettings({ style = value }) then
                DesignerUI:ApplySkyridingPreview(false)
                DesignerUI:RefreshSkyridingSettingsPanel()
                if DesignerUI.PositionSkyridingSettingsPanel then
                    DesignerUI:PositionSkyridingSettingsPanel(false)
                end
            end
        end,
    })
    panel.styleSelector:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -52)
    panel.styleSelector:Hide()

    local function SetDraftSetting(patch)
        if DesignerUI.skyridingSettingsRefreshing then return end
        local styleId = "halo"
        local settings = Designer:SetSkyridingStyleSettings(styleId, patch)
        if not settings then return end
        local appearanceOnly = true
        for field in pairs(patch) do
            if SKYRIDING_GEOMETRY_FIELDS[field] then appearanceOnly = false; break end
        end
        DesignerUI:ApplySkyridingPreview(appearanceOnly)
        DesignerUI:RefreshSkyridingSettingsPanel()
    end

    local fieldWidth, labelWidth, columnGap = 324, 118, 10
    local controlOffset = labelWidth + columnGap
    local controlWidth = fieldWidth - controlOffset
    local rowHeight, rowStep, firstRowTop = 30, 38, 140
    local function PlaceRow(control, row, label)
        local centerY = -firstRowTop - (row - 1) * rowStep - rowHeight / 2
        control:ClearAllPoints()
        control:SetPoint("LEFT", panel, "TOPLEFT", 18 + (label and controlOffset or 0), centerY)
        if label then
            label:SetWidth(labelWidth)
            label:SetWordWrap(false)
            label:ClearAllPoints()
            label:SetPoint("LEFT", panel, "TOPLEFT", 18, centerY)
        end
        return control
    end

    local function CreateSettingSlider(field, label, minimum, maximum, step)
        local control = GUI2.Form:CreateSlider(panel, {
            width = fieldWidth,
            inline = true,
            label = label,
            labelWidth = controlOffset,
            inputWidth = 56,
            min = minimum,
            max = maximum,
            step = step,
            precision = 0,
            set = function(value)
                local patch = {}
                patch[field] = tonumber(value)
                SetDraftSetting(patch)
            end,
        })
        panel[field] = control
        return control
    end

    PlaceRow(CreateSettingSlider(
        "width",
        T("skyriding.settings.width", "宽度"),
        180,
        720,
        5
    ), 1)
    PlaceRow(CreateSettingSlider(
        "speedHeight",
        T("skyriding.settings.speed_height", "速度条高度"),
        8,
        40,
        1
    ), 2)
    CreateSettingSlider(
        "resourceHeight",
        T("skyriding.settings.resource_height", "资源高度"),
        4,
        28,
        1
    ):SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -170)
    CreateSettingSlider(
        "iconSize",
        T("skyriding.settings.icon_size", "中央图标尺寸"),
        28,
        96,
        1
    ):SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -208)
    PlaceRow(CreateSettingSlider(
        "vigorHeight",
        T("skyriding.settings.vigor_height", "精力高度"),
        4,
        28,
        1
    ), 3)
    PlaceRow(CreateSettingSlider(
        "secondWindHeight",
        T("skyriding.settings.second_wind_height", "复苏之风高度"),
        4,
        28,
        1
    ), 4)

    panel.ringThicknessLabel = GUI2:CreateText(
        panel,
        T("skyriding.settings.ring_thickness", "圆环粗细"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    panel.ringThicknessLabel:SetWidth(118)
    panel.ringThicknessLabel:SetPoint(
        "LEFT",
        panel,
        "TOPLEFT",
        18,
        -261
    )

    panel.ringThickness = GUI2.Form:CreateDropdown(panel, {
        width = 196,
        height = 30,
        options = {
            { text = "4", value = 4 },
            { text = "8", value = 8 },
            { text = "14", value = 14 },
        },
        set = function(value)
            SetDraftSetting({ ringThickness = tonumber(value) })
        end,
    })
    panel.ringThickness:SetPoint("TOPLEFT", panel, "TOPLEFT", 146, -246)

    PlaceRow(CreateSettingSlider(
        "rowGap",
        T("skyriding.settings.row_gap", "行间距"),
        0,
        16,
        1
    ), 5)
    PlaceRow(CreateSettingSlider(
        "pipGap",
        T("skyriding.settings.pip_gap", "格子间距"),
        0,
        12,
        1
    ), 6)

    panel.speedFontLabel = GUI2:CreateText(
        panel,
        T("skyriding.settings.speed_font", "速度文字字体"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    panel.speedFont = GUI2.Form:CreateFontStyle(panel, {key="yhud:skyriding/speedText", width=controlWidth})
    PlaceRow(panel.speedFont, 2, panel.speedFontLabel)

    panel.pages = {
        layout = { panel.width, panel.speedHeight, panel.vigorHeight, panel.secondWindHeight,
            panel.rowGap, panel.pipGap },
        appearance = {},
        text = { panel.speedFontLabel, panel.speedFont },
        cooldown = {},
    }
    panel.page = "layout"
    panel.tabItems = {
        { text = T("designer.page.layout", "布局"), value = "layout" },
        { text = T("designer.page.appearance", "外观"), value = "appearance" },
        { text = T("designer.page.text", "文字"), value = "text" },
        { text = CooldownTabName(), value = "cooldown" },
    }
    panel.tabs = GUI2.Form:CreateUnderlineTabs(panel, {
        width = 324, height = 30, equalWidth = true, gap = 8, showBaseline = true,
        overflow = "scroll", contentAlignment = "CENTER",
        value = panel.page,
        items = panel.tabItems,
        set = function(value)
            panel.page = value
            DesignerUI:RefreshSkyridingSettingsPanel()
        end,
    })
    panel.tabs:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -94)

    local function Keep(page, control)
        local controls = panel.pages[page]
        controls[#controls + 1] = control
        return control
    end
    panel.cooldownStyleLabel = Keep("cooldown", GUI2:CreateText(panel,
        T("skyriding.settings.ability_style", "显示样式"),
        "font.size.md", "color.text.primary", "LEFT"))
    panel.cooldownStyle = Keep("cooldown", GUI2.Form:CreateDropdown(panel, {
        width = controlWidth, height = rowHeight, value = "right",
        options = {
            { text = T("skyriding.cooldown.left", "图标在左侧"), value = "left" },
            { text = T("skyriding.cooldown.right", "图标在右侧"), value = "right" },
            { text = T("skyriding.cooldown.bar", "进度条"), value = "bar" },
        },
        set = function(value) SetDraftSetting({ cooldownStyle = value }) end,
    }))
    PlaceRow(panel.cooldownStyle, 1, panel.cooldownStyleLabel)
    local textureLabel = Keep("appearance", GUI2:CreateText(panel,
        T("designer.appearance.texture", "条材质"), "font.size.md", "color.text.primary", "LEFT"))
    panel.fillTexture = Keep("appearance", YUI.Settings:CreateTextureSelector(panel, {
        width = controlWidth, height = rowHeight,
        get = function()
            local profile = Designer.GetPresentationProfile
                and Designer:GetPresentationProfile() or Designer:GetProfile()
            return YHUD:GetSkyridingSettings(profile).styles.halo.fillTexture
        end,
        set = function(value) SetDraftSetting({ fillTexture = value }) end,
    }))
    PlaceRow(panel.fillTexture, 1, textureLabel)
    PlaceRow(Keep("appearance", CreateSettingSlider("border",
        T("designer.appearance.border", "边框"), 0, 12, 1)), 2)

    local function CreateColor(field, label, page, row, defaultToken)
        local control = GUI2.Form:CreateColorPicker(panel, {
            width = fieldWidth, height = rowHeight, label = label,
            labelWidth = labelWidth, gap = columnGap,
            field = false, hasAlpha = true,
            set = function(value)
                local patch = {}; patch[field] = value; SetDraftSetting(patch)
            end,
            getDefault = function()
                if defaultToken then return ThemeColor(defaultToken) end
                return YHUD:GetDefaultSkyridingStyleSettings("halo")[field]
            end,
        })
        panel[field] = Keep(page, control)
        PlaceRow(control, row)
    end
    CreateColor("speedColor", T("skyriding.settings.speed_color", "速度颜色"), "appearance", 3)
    CreateColor("thrillColor", T("skyriding.settings.thrill_color", "高速颜色"), "appearance", 4)
    CreateColor("vigorColor", T("skyriding.settings.vigor_color", "精力颜色"), "appearance", 5)
    CreateColor("secondWindColor", T("skyriding.settings.second_wind_color", "复苏之风颜色"), "appearance", 6)
    CreateColor("backgroundColor", T("skyriding.settings.speed_background", "速度背景"), "appearance", 7)
    CreateColor("emptyColor", T("skyriding.settings.resource_background", "资源背景"), "appearance", 8)
    CreateColor("borderColor", T("designer.appearance.border_color", "边框颜色"),
        "appearance", 9, "color.border.subtle")
    local speedTextLabel = Keep("text", GUI2:CreateText(panel,
        T("skyriding.settings.speed_text", "显示速度文字"), "font.size.md", "color.text.primary", "LEFT"))
    panel.speedText = Keep("text", GUI2.Form:CreateSwitch(panel, {
        width = 64, height = 24,
        set = function(value) SetDraftSetting({ speedText = value == true }) end,
    }))
    PlaceRow(panel.speedText, 1, speedTextLabel)

    PlaceRow(Keep("cooldown", CreateSettingSlider("cooldownBarHeight",
        T("skyriding.settings.cooldown_bar_height", "高度"), 4, 40, 1)), 2)
    local cooldownTextureLabel = Keep("cooldown", GUI2:CreateText(panel,
        T("designer.appearance.texture", "条材质"), "font.size.md", "color.text.primary", "LEFT"))
    panel.cooldownBarTexture = Keep("cooldown", YUI.Settings:CreateTextureSelector(panel, {
        width = controlWidth, height = rowHeight,
        get = function()
            local profile = Designer.GetPresentationProfile
                and Designer:GetPresentationProfile() or Designer:GetProfile()
            return YHUD:GetSkyridingSettings(profile).styles.halo.cooldownBarTexture
        end,
        set = function(value) SetDraftSetting({ cooldownBarTexture = value }) end,
    }))
    PlaceRow(panel.cooldownBarTexture, 3, cooldownTextureLabel)
    CreateColor("cooldownBarColor", T("skyriding.settings.cooldown_bar_color", "填充颜色"), "cooldown", 4)
    CreateColor("cooldownBarBackgroundColor", T("skyriding.settings.cooldown_bar_background", "背景颜色"), "cooldown", 5)
    PlaceRow(Keep("cooldown", CreateSettingSlider("cooldownBarBorder",
        T("designer.appearance.border", "边框"), 0, 12, 1)), 6)
    CreateColor("cooldownBarBorderColor", T("designer.appearance.border_color", "边框颜色"),
        "cooldown", 7, "color.border.subtle")
    local cooldownTextLabel = Keep("cooldown", GUI2:CreateText(panel,
        T("skyriding.settings.cooldown_bar_text", "显示倒计时"), "font.size.md", "color.text.primary", "LEFT"))
    panel.cooldownBarText = Keep("cooldown", GUI2.Form:CreateSwitch(panel, {
        width = 64, height = 24,
        set = function(value) SetDraftSetting({ cooldownBarText = value == true }) end,
    }))
    PlaceRow(panel.cooldownBarText, 8, cooldownTextLabel)
    local cooldownFontLabel = Keep("cooldown", GUI2:CreateText(panel,
        T("skyriding.settings.cooldown_font", "倒计时字体"), "font.size.md", "color.text.primary", "LEFT"))
    panel.cooldownBarTextFont = Keep("cooldown", GUI2.Form:CreateFontStyle(panel, {
        key = "yhud:skyriding/cooldownBarText", width = controlWidth,
    }))
    PlaceRow(panel.cooldownBarTextFont, 9, cooldownFontLabel)
    panel.cooldownBarControls = {
        panel.cooldownBarHeight, cooldownTextureLabel, panel.cooldownBarTexture,
        panel.cooldownBarColor, panel.cooldownBarBackgroundColor, panel.cooldownBarBorder,
        panel.cooldownBarBorderColor, cooldownTextLabel, panel.cooldownBarText,
        cooldownFontLabel, panel.cooldownBarTextFont,
    }

    panel.resetSettings = GUI2.Form:CreateButton(panel, {
        text = T("skyriding.settings.reset", "恢复默认设置"),
        width = 144,
        height = 30,
        onClick = function()
            local styleId = "halo"
            local defaults = YHUD:GetDefaultSkyridingStyleSettings(styleId)
            if Designer:SetSkyridingStyleSettings(styleId, defaults) then
                DesignerUI:ApplySkyridingPreview(false)
                DesignerUI:RefreshSkyridingSettingsPanel()
            end
        end,
    })
    panel.resetSettings:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 18, 16)

    self.skyridingSettingsPanel = panel
    if self.PositionSkyridingSettingsPanel then
        self:PositionSkyridingSettingsPanel(false)
    end
    return panel
end

function View:SetDesignerSurfaceVisible(visible)
    visible = visible ~= false
    if self.designerSurfaceVisible == visible then return false end
    self.designerSurfaceVisible = visible
    if visible then
        if self.ProjectAllGroupVisibility then
            self:ProjectAllGroupVisibility()
        end
        if self.designMode and self.RefreshDesignModePresentation then
            self:RefreshDesignModePresentation(true, true, true)
        end
    else
        for _, runtime in pairs(self.groups or {}) do
            if runtime.frame then runtime.frame:Hide() end
            if runtime.designHeader then runtime.designHeader:Hide() end
            if runtime.designMover then runtime.designMover:Hide() end
            if runtime.designOutline then runtime.designOutline:Hide() end
        end
        if self.ProjectAllGroupVisibility then
            self:ProjectAllGroupVisibility()
        end
    end
    return true
end

function DesignerUI:EnsureModeSwitcher()
    if not SUPPORTS_SKYRIDING then return nil end
    if self.modeSwitcher then return self.modeSwitcher end
    local tabs = GUI2.Form:CreateUnderlineTabs(_G.UIParent, {
        name = "YUI_YHUD_DesignerModeSwitcher",
        width = 320,
        height = 34,
        gap = 24,
        minItemWidth = 112,
        equalWidth = true,
        contentAlignment = "CENTER",
        showBaseline = true,
        indicatorHeight = 3,
        value = self.designerMode or "cooldown",
        items = {
            {
                text = "|A:Tormentors-Event:18:18|a " .. T("designer.mode.non_skyriding", "非驭龙术"),
                value = "cooldown",
            },
            {
                text = "|A:dragon-rostrum:18:18|a " .. T("designer.mode.skyriding", "驭龙术"),
                value = "skyriding",
            },
        },
        set = function(value)
            DesignerUI:SetDesignerMode(value)
        end,
    })
    tabs:SetPoint("TOP", self.toolbar, "BOTTOM", 0, -6)
    tabs:SetFrameStrata("FULLSCREEN_DIALOG")
    tabs:SetFrameLevel(430)
    tabs:Hide()
    self.modeSwitcher = tabs
    self.designerMode = self.designerMode or "cooldown"
    return tabs
end

function DesignerUI:SyncDesignerModePresentation()
    local mode = SUPPORTS_SKYRIDING and self.designerMode == "skyriding"
        and "skyriding" or "cooldown"
    self.designerMode = mode
    local skyriding = YHUD.Skyriding
    if self.modeSwitcher and self.modeSwitcher.SetValue then
        self.modeSwitcher:SetValue(mode, true)
    end
    if View.SetDesignerSkyridingState then
        View:SetDesignerSkyridingState(mode == "skyriding")
    end
    if mode == "skyriding" then
        self:HideMonitorPicker()
        self:HideGlowEditor()
        if self.HideSpecializationPicker then self:HideSpecializationPicker() end
        if self.panel then self.panel:Hide() end
        local settingsPanel = self:EnsureSkyridingSettingsPanel()
        self:RefreshSkyridingSettingsPanel()
        settingsPanel:Show()
        if self.PositionSkyridingSettingsPanel then
            self:PositionSkyridingSettingsPanel(false)
        end
        if skyriding and skyriding.SetDesignerPreview then
            skyriding:SetDesignerPreview(true)
        end
        if View.SetDesignSelection then
            View:SetDesignSelection(SKYRIDING_GROUP_ID, nil)
        end
    else
        if self.skyridingSettingsPanel then
            self.skyridingSettingsPanel:Hide()
        end
        if skyriding and skyriding.SetDesignerPreview then
            skyriding:SetDesignerPreview(false)
        end
        local session = Designer:GetSession()
        if View.SetDesignSelection then
            View:SetDesignSelection(
                session and session.selectedGroupId or nil,
                session and session.selectedMonitorId or nil
            )
        end
        if self.panel and session and session.selectedGroupId then
            self.panel:Show()
        end
    end
    return true
end

function DesignerUI:SetDesignerMode(mode)
    mode = SUPPORTS_SKYRIDING and mode == "skyriding" and "skyriding" or "cooldown"
    if self.designerMode == mode then
        return self:SyncDesignerModePresentation()
    end
    self.designerMode = mode
    self.manualPanel = false
    if self.StopResourceValuePreview then
        self:StopResourceValuePreview(true, false)
    end
    self:SyncDesignerModePresentation()
    if self.active then
        self:ApplyPreview()
        if mode == "cooldown" then self:Refresh(false, false) end
    end
    return true
end

function DesignerUI:SelectRuntimeGroup(groupId)
    if not SUPPORTS_SKYRIDING then return false end
    if groupId ~= SKYRIDING_GROUP_ID then return false end
    if self.designerMode ~= "skyriding" then
        self:SetDesignerMode("skyriding")
    end
    self:HideMonitorPicker()
    self:HideGlowEditor()
    if self.panel then self.panel:Hide() end
    local settingsPanel = self:EnsureSkyridingSettingsPanel()
    self:RefreshSkyridingSettingsPanel()
    settingsPanel:Show()
    if self.PositionSkyridingSettingsPanel then
        self:PositionSkyridingSettingsPanel(false)
    end
    if View.SetDesignSelection then
        View:SetDesignSelection(SKYRIDING_GROUP_ID, nil)
    end
    return true
end

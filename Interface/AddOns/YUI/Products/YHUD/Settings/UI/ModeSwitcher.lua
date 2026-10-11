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
    panel.speedFont:SetValue(styleSettings.speedFont or "default", true)
    panel.speedFontSize:SetValue(
        tonumber(styleSettings.speedFontSize) or 12,
        true
    )
    local horizon = styleId == "horizon"
    panel.resourceHeight:SetShown(horizon)
    panel.iconSize:SetShown(horizon)
    panel.ringThicknessLabel:SetShown(horizon)
    panel.ringThickness:SetShown(horizon)
    panel.vigorHeight:SetShown(not horizon)
    panel.secondWindHeight:SetShown(not horizon)
    local extraHeight = horizon and 38 or 0
    panel:SetHeight(540 + extraHeight)
    local function Position(control, y)
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -y)
    end
    Position(panel.rowGap, 246 + extraHeight)
    Position(panel.pipGap, 284 + extraHeight)
    Position(panel.vigorColor, 326 + extraHeight)
    Position(panel.secondWindColor, 366 + extraHeight)
    Position(panel.speedFontLabel, 410 + extraHeight)
    Position(panel.speedFontSizeLabel, 410 + extraHeight)
    panel.speedFontSizeLabel:ClearAllPoints()
    panel.speedFontSizeLabel:SetPoint(
        "TOPLEFT",
        panel,
        "TOPLEFT",
        234,
        -(410 + extraHeight)
    )
    Position(panel.speedFont, 428 + extraHeight)
    panel.speedFontSize:ClearAllPoints()
    panel.speedFontSize:SetPoint(
        "TOPLEFT",
        panel,
        "TOPLEFT",
        234,
        -(428 + extraHeight)
    )
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
                DesignerUI:ApplyPreview()
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
                DesignerUI:ApplyPreview()
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
        local profile = Designer.GetPresentationProfile
            and Designer:GetPresentationProfile() or Designer:GetProfile()
        local current = YHUD:GetSkyridingSettings(profile)
        local styleId = "halo"
        local settings = Designer:SetSkyridingStyleSettings(styleId, patch)
        if not settings then return end
        DesignerUI:ApplyPreview()
        DesignerUI:RefreshSkyridingSettingsPanel()
    end

    local function CreateSettingSlider(field, label, minimum, maximum, step)
        local control = GUI2.Form:CreateSlider(panel, {
            width = 324,
            inline = true,
            label = label,
            labelWidth = 118,
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

    CreateSettingSlider(
        "width",
        T("skyriding.settings.width", "宽度"),
        180,
        720,
        5
    ):SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -94)
    CreateSettingSlider(
        "speedHeight",
        T("skyriding.settings.speed_height", "速度条高度"),
        8,
        40,
        1
    ):SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -132)
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
    CreateSettingSlider(
        "vigorHeight",
        T("skyriding.settings.vigor_height", "精力高度"),
        4,
        28,
        1
    ):SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -170)
    CreateSettingSlider(
        "secondWindHeight",
        T("skyriding.settings.second_wind_height", "复苏之风高度"),
        4,
        28,
        1
    ):SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -208)

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

    CreateSettingSlider(
        "rowGap",
        T("skyriding.settings.row_gap", "行间距"),
        0,
        16,
        1
    ):SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -284)
    CreateSettingSlider(
        "pipGap",
        T("skyriding.settings.pip_gap", "格子间距"),
        0,
        12,
        1
    ):SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -322)

    panel.vigorColor = GUI2.Form:CreateColorPicker(panel, {
        width = 324,
        height = 30,
        label = T("skyriding.settings.vigor_color", "精力颜色"),
        labelWidth = 118,
        field = true,
        hasAlpha = true,
        set = function(value) SetDraftSetting({ vigorColor = value }) end,
        getDefault = function() return YHUD:GetDefaultSkyridingStyleSettings("halo").vigorColor end,
    })
    panel.vigorColor:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -364)

    panel.secondWindColor = GUI2.Form:CreateColorPicker(panel, {
        getDefault = function() return YHUD:GetDefaultSkyridingStyleSettings("halo").secondWindColor end,
        width = 324,
        height = 30,
        label = T("skyriding.settings.second_wind_color", "复苏之风颜色"),
        labelWidth = 118,
        field = true,
        hasAlpha = true,
        set = function(value)
            SetDraftSetting({ secondWindColor = value })
        end,
    })
    panel.secondWindColor:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -404)

    panel.speedFontLabel = GUI2:CreateText(
        panel,
        T("skyriding.settings.speed_font", "速度文字字体"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    panel.speedFontLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -448)
    panel.speedFontSizeLabel = GUI2:CreateText(
        panel,
        T("skyriding.settings.speed_font_size", "字号"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    panel.speedFontSizeLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 234, -448)

    panel.speedFont = GUI2.Form:CreateLSMFontDropdown(panel, {
        width = 206,
        height = 30,
        prependOptions = function()
            return {
                {
                    text = T("designer.font.default", "默认"),
                    value = "default",
                },
            }
        end,
        set = function(value) SetDraftSetting({ speedFont = value }) end,
    })
    panel.speedFont:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -466)

    local fontSizeOptions = {}
    local fontSizes = { 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32 }
    for index = 1, #fontSizes do
        local value = fontSizes[index]
        fontSizeOptions[index] = { text = tostring(value), value = value }
    end
    panel.speedFontSize = GUI2.Form:CreateDropdown(panel, {
        width = 108,
        height = 30,
        options = fontSizeOptions,
        set = function(value) SetDraftSetting({ speedFontSize = value }) end,
    })
    panel.speedFontSize:SetPoint("TOPLEFT", panel, "TOPLEFT", 234, -466)

    panel.resetSettings = GUI2.Form:CreateButton(panel, {
        text = T("skyriding.settings.reset", "恢复默认设置"),
        width = 144,
        height = 30,
        onClick = function()
            local profile = Designer.GetPresentationProfile
                and Designer:GetPresentationProfile() or Designer:GetProfile()
            local current = YHUD:GetSkyridingSettings(profile)
            local styleId = "halo"
            local defaults = YHUD:GetDefaultSkyridingStyleSettings(styleId)
            if Designer:SetSkyridingStyleSettings(styleId, defaults) then
                DesignerUI:ApplyPreview()
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

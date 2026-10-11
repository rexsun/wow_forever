local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local DesignerUI = YHUD and YHUD.DesignerUI
local I = DesignerUI and DesignerUI._internal
if not I then return end

local GUI2 = I.GUI2
local S = I.S
local Designer = I.Designer
local Catalog = I.Catalog
local ResourceCatalog = I.ResourceCatalog
local Glow = I.Glow
local QUESTION_ICON = I.QUESTION_ICON
local T = I.T
local TC = I.TC or I.T
local CelestialSeries = S and S.CelestialSeries

local function CoreAsset(path)
    local assets = YUI.Assets
    if assets and assets.Core then return assets:Core(path) end
    return "Interface\\AddOns\\YUI\\Media\\Core\\" .. path
end
local function ProductAsset(path)
    local assets = YUI.Assets
    if assets and assets.Product then return assets:Product("yhud", path) end
    return "Interface\\AddOns\\" .. (YUI.AddonName or "YUI")
        .. "\\Products\\YHUD\\Media\\" .. path
end
local InCombat = I.InCombat
local Print = I.Print
local GroupName = I.GroupName
local GroupTypeName = I.GroupTypeName
local CountList = I.CountList
local MONITOR_LAYOUTS = I.MONITOR_LAYOUTS
local CanAddMonitor = I.CanAddMonitor
local SetShown = I.SetShown
local BuildDirectionOptions = I.BuildDirectionOptions
local BuildAlignmentOptions = I.BuildAlignmentOptions
local BuildRowDirectionOptions = I.BuildRowDirectionOptions
local BuildOrientationOptions = I.BuildOrientationOptions
local BuildResourceFillDirectionOptions = I.BuildResourceFillDirectionOptions
local BuildIconPositionOptions = I.BuildIconPositionOptions
local BuildShapeOptions = I.BuildShapeOptions
local BuildBorderOptions = I.BuildBorderOptions
local BuildFontOptions = I.BuildFontOptions
local BuildOutlineOptions = I.BuildOutlineOptions
local BuildTextPositionOptions = I.BuildTextPositionOptions
local BuildNameTextPositionOptions = I.BuildNameTextPositionOptions
local BuildNumberOptions = I.BuildNumberOptions
local BuildGlowTriggerOptions = I.BuildGlowTriggerOptions
local BuildGlowStyleOptions = I.BuildGlowStyleOptions
local BuildGlowControlLabels = I.BuildGlowControlLabels
local MonitorActionText = I.MonitorActionText
local IsMonitorPickerFolder = I.IsMonitorPickerFolder
local MonitorName = I.MonitorName
local RESOURCE_MENU_WIDTH = 220
local RESOURCE_PRESET_ROW_COUNT = YUI.IsForever == true and 8 or 5

local function BuildLayoutModeOptions()
    return {
        {
            text = T("designer.layout.mode.auto", "自动布局"),
            value = "auto",
        },
        {
            text = T("designer.layout.mode.fixed", "固定位置"),
            value = "fixed",
        },
    }
end

function DesignerUI:GetFixedLayoutReasonText(reason)
    if reason == YHUD.FILTERED_AURA_FIXED_REASON_PERSISTENT_MEMBER then
        return T(
            "designer.monitor.visibility_fixed_reason_persistent",
            "本组包含“始终显示”项目"
        )
    end
    if reason == YHUD.FILTERED_AURA_FIXED_REASON_NON_FLOW_MEMBER then
        return T(
            "designer.monitor.visibility_fixed_reason_non_flow",
            "本组包含不参与光环动态补位的监控"
        )
    end
    if reason == YHUD.FILTERED_AURA_FIXED_REASON_SCOPE_MISMATCH then
        return T(
            "designer.monitor.visibility_fixed_reason_scope",
            "本组包含不同目标或过滤范围的光环"
        )
    end
    if reason == YHUD.FILTERED_AURA_FIXED_REASON_UNSUPPORTED_LAYOUT then
        return T(
            "designer.monitor.visibility_fixed_reason_layout",
            "当前分组样式不支持光环动态补位"
        )
    end
    if reason == YHUD.FILTERED_AURA_FIXED_REASON_CONFIGURED_LAYOUT then
        return T(
            "designer.monitor.visibility_fixed_reason_configured",
            "本组的排列方式由你设置为“固定位置”"
        )
    end
    return T(
        "designer.monitor.visibility_fixed_reason_other",
        "本组包含无法动态补位的监控"
    )
end

local function BuildDisplayLayerOptions()
    local options = {}
    for value = 1, 10 do
        local suffix = value == 1
            and T("designer.layout.display_layer.lowest", "最低")
            or (value == 5
                and T("designer.layout.display_layer.standard", "标准")
                or (value == 10
                    and T("designer.layout.display_layer.highest", "最高")
                    or nil))
        options[#options + 1] = {
            text = suffix and (tostring(value) .. " · " .. suffix)
                or tostring(value),
            value = value,
        }
    end
    return options
end

local function ProjectResourceDisplayOrder(profile, groupId, presets)
    presets = ResourceCatalog:GetDisplayPresets(YHUD:GetResourceProfile(profile, groupId), presets)
    local layout = profile and YHUD:GetResourceGroupLayout(profile, groupId)
    local reversed = layout ~= nil
        and (layout.direction == "up" or layout.direction == "left")
    if type(presets) ~= "table" or not reversed then return presets end
    local projected = {}
    for index = #presets, 1, -1 do
        projected[#projected + 1] = presets[index]
    end
    return projected, true
end
I.ProjectResourceDisplayOrder = ProjectResourceDisplayOrder

function DesignerUI:EnsureUI()
    if self._legacyDetailsBuilt then return true end
    if not (GUI2.CreateFrame and GUI2.CreatePanel and GUI2.CreateText
        and GUI2.CreateTexture and GUI2.SetTexturePaintKey
        and GUI2.CreateScrollFrame and GUI2.CreateAccordion
        and GUI2.Form.CreateGlowOptions and GUI2.CreateCloseButton
        and GUI2.Data and GUI2.Data.CreateTag) then
        return nil, "gui-unavailable"
    end
    local coreAlreadyBuilt = self._legacyCoreBuilt == true

    local dimmer, toolbar, title, profileDropdown, contentButton
    local layoutButton, finishButton, cancelButton, panel, dragHandle
    local panelTitle, inspectorTypeBadge, inspectorCloseButton
    local groupSelectorLabel, groupDropdown, newGroupButton
    local inspectorScroll, inspectorScrollChild, groupBody, monitorBody
    local inspectorAccordion, groupHeading, groupNameInput, groupNameLabel
    local fixedNameBadge, groupSummary, enableLabel, enableSwitch
    local unavailablePreviewLabel, unavailablePreviewSwitch, restoreButton

    if not self._legacyCoreBuilt then
    dimmer = GUI2:CreateFrame(UIParent, {
        name = "YUI_YHUD_DesignerDimmer",
        allPoints = true,
        strata = "HIGH",
        level = 900,
        mouse = false,
        hidden = true,
    })
    local shade = GUI2:CreateTexture(dimmer, nil, "BACKGROUND")
    GUI2:SetTexturePaintKey(shade, "color.overlay.shadow")
    shade:SetAllPoints(dimmer)
    if dimmer.EnableKeyboard then dimmer:EnableKeyboard(true) end
    if dimmer.SetPropagateKeyboardInput then
        dimmer:SetPropagateKeyboardInput(true)
    end
    dimmer:SetScript("OnKeyDown", function(frame, key)
        if key ~= "ESCAPE" then return end
        if not InCombat() and frame.SetPropagateKeyboardInput then
            frame:SetPropagateKeyboardInput(false)
        end
        DesignerUI:HandleEscape()
    end)
    dimmer:SetScript("OnShow", function(frame)
        if not InCombat() and frame.SetPropagateKeyboardInput then
            frame:SetPropagateKeyboardInput(true)
        end
    end)

    self:CreateDesignerToolbar()
    toolbar, title = self.toolbar, self.toolbarTitle
    profileDropdown, layoutButton = self.profileDropdown, self.layoutButton
    finishButton, cancelButton = self.finishButton, self.cancelButton
    panel = GUI2:CreatePanel(UIParent, {
        name = "YUI_YHUD_DesignerInspector",
        width = 360,
        height = 780,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetFrameLevel(400)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    if panel.SetClampedToScreen then panel:SetClampedToScreen(true) end
    panel:Hide()

    dragHandle = GUI2:CreateFrame(panel, {
        width = 332,
        height = 34,
        mouse = true,
    })
    dragHandle:SetPoint("TOP", panel, "TOP", 0, -8)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        if DesignerUI.active then
            DesignerUI.manualPanel = true
            panel:StartMoving()
        end
    end)
    dragHandle:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
    end)
    local lastHeaderClick = 0
    dragHandle:SetScript("OnMouseUp", function(_, button)
        if button and button ~= "LeftButton" then return end
        local now = GetTime and GetTime() or 0
        if now - lastHeaderClick <= 0.35 then
            DesignerUI.manualPanel = false
            DesignerUI.inspectorDockRequested = true
            DesignerUI:PositionInspector(true)
            lastHeaderClick = 0
        else
            lastHeaderClick = now
        end
    end)

    panelTitle = GUI2:CreateText(
        dragHandle,
        "",
        "font.size.lg",
        "color.text.heading",
        "LEFT"
    )
    panelTitle:SetPoint("LEFT", 2, 0)

    inspectorTypeBadge = GUI2.Data:CreateTag(
        dragHandle,
        T("designer.type.icons", "图标组"),
        "accent"
    )
    if inspectorTypeBadge then
        inspectorTypeBadge:SetPoint("LEFT", panelTitle, "RIGHT", 8, 0)
    end

    inspectorCloseButton = GUI2:CreateCloseButton(
        dragHandle,
        function()
            DesignerUI:CloseInspector()
        end
    )
    inspectorCloseButton:SetPoint("RIGHT", dragHandle, "RIGHT", -2, 0)

    groupSelectorLabel = GUI2:CreateText(
        panel,
        T("designer.group_label", "分组"),
        "font.size.sm",
        "color.text.primary",
        "LEFT"
    )
    groupSelectorLabel:SetPoint("TOPLEFT", 16, -60)

    groupDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 270,
        height = 30,
        options = function()
            return DesignerUI:BuildGroupOptions()
        end,
        get = function()
            local session = Designer:GetSession()
            return session and session.selectedGroupId
        end,
        set = function(value)
            if value == "__yhud_create_group__" then
                DesignerUI:ShowNewGroupDialog()
                local session = Designer:GetSession()
                if session and groupDropdown.SetValue then
                    groupDropdown:SetValue(session.selectedGroupId, true)
                end
                return
            end
            DesignerUI:SelectGroup(value)
        end,
    })
    groupDropdown:SetPoint("TOPLEFT", 74, -52)

    newGroupButton = GUI2.Form:CreateButton(panel, {
        text = "+",
        width = 34,
        height = 30,
        tone = "warning",
        onClick = function()
            DesignerUI:ShowNewGroupDialog()
        end,
    })
    newGroupButton:SetPoint("LEFT", groupDropdown, "RIGHT", 8, 0)
    newGroupButton:Hide()

    inspectorScroll = GUI2:CreateScrollFrame(panel, {
        width = 328,
        height = 660,
        childWidth = 328,
        childHeight = 1,
        mouseWheel = true,
    })
    inspectorScroll:SetPoint("TOPLEFT", 16, -94)
    inspectorScroll:SetPoint("BOTTOMRIGHT", -16, 16)
    inspectorScrollChild = inspectorScroll.child
    groupBody = GUI2:CreateFrame(inspectorScrollChild, {
        width = 328,
        height = 590,
    })
    monitorBody = GUI2:CreateFrame(inspectorScrollChild, {
        width = 328,
        height = 184,
    })
    inspectorAccordion = GUI2:CreateAccordion(inspectorScrollChild, {
        width = 328,
        headerHeight = 42,
        gap = 8,
        activeId = "group",
        allowNone = true,
        onActiveChanged = function(sectionId)
            DesignerUI.inspectorSection = sectionId
            if DesignerUI.SyncDesignCooldownTextPreview then
                DesignerUI:SyncDesignCooldownTextPreview(
                    sectionId == "group"
                )
            end
            if DesignerUI.active and DesignerUI.PositionInspector then
                DesignerUI:PositionInspector(false)
            end
        end,
        onHeightChanged = function(height)
            inspectorScrollChild:SetHeight(math.max(1, height))
            local screenHeight = UIParent and UIParent.GetHeight
                and UIParent:GetHeight() or 900
            local maximum = math.max(360, screenHeight - 158)
            panel:SetHeight(math.max(218, math.min(780, 126 + height, maximum)))
            if DesignerUI.active and DesignerUI.PositionInspector then
                DesignerUI:PositionInspector(false)
            end
        end,
    })
    inspectorAccordion:SetPoint("TOPLEFT", inspectorScrollChild, "TOPLEFT", 0, 0)
    inspectorAccordion:AddSection(
        "group",
        T("designer.group_settings", "组设置"),
        groupBody
    )
    inspectorAccordion:AddSection(
        "monitor",
        T("designer.monitor_settings", "单个监控"),
        monitorBody
    )

    groupHeading = GUI2:CreateText(
        panel,
        "",
        "font.size.xl",
        "color.text.heading",
        "LEFT"
    )
    groupHeading:SetPoint("TOPLEFT", 16, -98)
    groupHeading:SetPoint("TOPRIGHT", -16, -98)
    groupHeading:SetWordWrap(false)

    groupNameInput = GUI2.Form:CreateEditBox(panel, {
        width = 328,
        height = 30,
        autoFocus = false,
        onFocusLost = function(control)
            DesignerUI:RenameSelectedGroup(control:GetText())
        end,
    })
    groupNameInput:SetPoint("TOPLEFT", 16, -90)
    groupNameInput:SetScript("OnEnterPressed", function(control)
        if control.ClearFocus then control:ClearFocus() end
    end)
    groupNameInput:SetScript("OnEscapePressed", function(control)
        local session = Designer:GetSession()
        local profile = Designer:GetProfile()
        local group = session and profile and profile.groups
            and profile.groups.items[session.selectedGroupId]
        if group and control.SetValue then
            control:SetValue(GroupName(group), true)
        end
        if control.ClearFocus then control:ClearFocus() end
    end)
    groupNameInput:Hide()

    groupNameLabel = GUI2:CreateText(
        panel,
        T("designer.group_name", "名称"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    groupNameLabel:SetPoint("TOPLEFT", 16, -90)

    fixedNameBadge = GUI2:CreateText(
        panel,
        T("designer.fixed", "固定"),
        "font.size.sm",
        "color.text.secondary",
        "RIGHT"
    )
    fixedNameBadge:SetPoint("RIGHT", groupNameInput, "RIGHT", -8, 0)

    groupSummary = GUI2:CreateText(
        panel,
        "",
        "font.size.md",
        "color.text.secondary",
        "LEFT"
    )
    groupSummary:SetPoint("TOPLEFT", 16, -128)
    groupSummary:SetPoint("TOPRIGHT", -16, -128)
    groupSummary:SetWordWrap(false)

    enableLabel = GUI2:CreateText(
        panel,
        T("designer.group_enabled", "启用分组"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    enableLabel:SetPoint("TOPLEFT", 16, -174)
    enableLabel:SetWidth(108)

    enableSwitch = GUI2.Form:CreateSwitch(panel, {
        width = 48,
        height = 24,
        get = function()
            local session = Designer:GetSession()
            local profile = Designer:GetProfile()
            local group = session and profile and profile.groups
                and profile.groups.items[session.selectedGroupId]
            return group and group.enabled == true or false
        end,
        set = function(value)
            DesignerUI:SetSelectedGroupEnabled(value == true)
        end,
    })
    enableSwitch:SetPoint("TOPLEFT", panel, "TOPLEFT", 126, -168)

    unavailablePreviewLabel = GUI2:CreateText(
        panel,
        T("designer.group_show_unavailable", "显示不可用（仅预览）"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    unavailablePreviewLabel:SetWidth(240)

    unavailablePreviewSwitch = GUI2.Form:CreateSwitch(panel, {
        width = 48,
        height = 24,
        get = function()
            local session = Designer:GetSession()
            local profile = Designer:GetProfile()
            local group = session and profile and profile.groups
                and profile.groups.items[session.selectedGroupId]
            return group
                and group.showUnavailablePreview ~= false or false
        end,
        set = function(value)
            DesignerUI:SetSelectedGroupUnavailablePreview(value == true)
        end,
    })

    restoreButton = GUI2.Form:CreateButton(panel, {
        text = TC("common.compact.restore", "恢复"),
        tooltip = T("designer.restore", "恢复暴雪冷却"),
        icon = CoreAsset("gui2\\icons\\settings\\rotate-ccw.png"),
        iconSize = 16,
        contentAlign = "center",
        width = 158,
        height = 30,
        tone = "default",
        onClick = function()
            DesignerUI:RequestDefaultRestore()
        end,
    })
    restoreButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -164)

    self.dimmer = dimmer
    self.toolbar = toolbar
    self.toolbarTitle = title
    self.contentButton = contentButton
    self.layoutButton = layoutButton
    self.finishButton = finishButton
    self.cancelButton = cancelButton
    self.panel = panel
    self.dragHandle = dragHandle
    self.panelTitle = panelTitle
    self.inspectorTypeBadge = inspectorTypeBadge
    self.inspectorCloseButton = inspectorCloseButton
    self.groupSelectorLabel = groupSelectorLabel
    self.profileDropdown = profileDropdown
    self.groupDropdown = groupDropdown
    self.newGroupButton = newGroupButton
    self.groupHeading = groupHeading
    self.groupNameInput = groupNameInput
    self.groupNameLabel = groupNameLabel
    self.fixedNameBadge = fixedNameBadge
    self.groupSummary = groupSummary
    self.enableSwitch = enableSwitch
    self.enableLabel = enableLabel
    self.unavailablePreviewLabel = unavailablePreviewLabel
    self.unavailablePreviewSwitch = unavailablePreviewSwitch
    self.restoreButton = restoreButton
    self.inspectorScroll = inspectorScroll
    self.inspectorScrollChild = inspectorScrollChild
    self.inspectorAccordion = inspectorAccordion
    self.groupInspectorBody = groupBody
    self.monitorInspectorBody = monitorBody
    self._legacyCoreBuilt = true
    else
        dimmer = self.dimmer
        toolbar = self.toolbar
        title = self.toolbarTitle
        contentButton = self.contentButton
        layoutButton = self.layoutButton
        finishButton = self.finishButton
        cancelButton = self.cancelButton
        panel = self.panel
        dragHandle = self.dragHandle
        panelTitle = self.panelTitle
        inspectorTypeBadge = self.inspectorTypeBadge
        inspectorCloseButton = self.inspectorCloseButton
        groupSelectorLabel = self.groupSelectorLabel
        profileDropdown = self.profileDropdown
        groupDropdown = self.groupDropdown
        newGroupButton = self.newGroupButton
        groupHeading = self.groupHeading
        groupNameInput = self.groupNameInput
        groupNameLabel = self.groupNameLabel
        fixedNameBadge = self.fixedNameBadge
        groupSummary = self.groupSummary
        enableSwitch = self.enableSwitch
        enableLabel = self.enableLabel
        unavailablePreviewLabel = self.unavailablePreviewLabel
        unavailablePreviewSwitch = self.unavailablePreviewSwitch
        restoreButton = self.restoreButton
        inspectorScroll = self.inspectorScroll
        inspectorScrollChild = self.inspectorScrollChild
        inspectorAccordion = self.inspectorAccordion
        groupBody = self.groupInspectorBody
        monitorBody = self.monitorInspectorBody
    end
    if self._legacyCoreOnly then return true end

    local iconSettingsMode = GUI2.Form:CreateSegmentedControl(panel, {
        width = 328,
        height = 28,
        items = {
            {
                text = T("designer.icon_tab.group", "分组"),
                value = "layout",
            },
            {
                text = T("designer.icon_tab.text", "文字"),
                value = "text",
            },
        },
        value = "layout",
        set = function(value)
            DesignerUI:ShowIconSettingsPage(value, true)
        end,
    })
    iconSettingsMode:SetPoint("TOPLEFT", 16, -204)

    local layoutModeLabel = GUI2:CreateText(
        panel,
        T("designer.layout.mode", "排列方式"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    layoutModeLabel:SetPoint("TOPLEFT", 16, -246)

    local layoutModeDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 206,
        height = 30,
        tooltip = T(
            "designer.layout.mode.tooltip",
            "自动布局会收紧空位；固定位置会保留预览中的槽位。"
        ),
        options = BuildLayoutModeOptions,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            DesignerUI:SetSelectedGroupLayoutMode(value)
        end,
    })
    layoutModeDropdown:SetPoint("TOPLEFT", 16, -264)

    local layoutModeOverrideInfo = GUI2.Form:CreateIconButton(panel, {
        size = 26,
        icon = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
        tone = "warning",
    })
    layoutModeOverrideInfo:SetPoint(
        "LEFT", layoutModeDropdown, "RIGHT", 8, 0
    )
    layoutModeOverrideInfo:SetScript("OnEnter", function(control)
        if not GameTooltip then return end
        local configuredText = control.yhudConfiguredLayoutMode == "fixed"
            and T("designer.layout.mode.fixed", "固定位置")
            or T("designer.layout.mode.auto", "自动布局")
        GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
        GameTooltip:SetText(string.format(
            T(
                "designer.layout.mode_forced_tooltip",
                "该分组当前必须使用固定位置。原因：%s。已保存的排列方式仍为“%s”；条件解除后将继续使用该设置。"
            ),
            DesignerUI:GetFixedLayoutReasonText(
                control.yhudLayoutModeOverrideReason
            ),
            configuredText
        ), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    layoutModeOverrideInfo:SetScript("OnLeave", function()
        YUI.HideGameTooltip()
    end)
    layoutModeOverrideInfo:Hide()

    local displayLayerLabel = GUI2:CreateText(
        panel,
        T("designer.layout.display_layer", "显示层级"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    displayLayerLabel:SetPoint("TOPLEFT", 202, -246)

    local displayLayerDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 176,
        height = 30,
        tooltip = T(
            "designer.layout.display_layer.tooltip",
            "只控制 YHUD 分组之间的遮挡；数值越大越靠上。"
        ),
        options = BuildDisplayLayerOptions,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            DesignerUI:SetSelectedGroupDisplayLayer(value)
        end,
    })
    displayLayerDropdown:SetPoint("TOPLEFT", 202, -264)

    local directionLabel = GUI2:CreateText(
        panel,
        T("designer.layout.wrap_mode", "对齐与换行"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    directionLabel:SetPoint("TOPLEFT", 16, -246)

    local rowDirectionLabel = GUI2:CreateText(
        panel,
        T("designer.layout.row_direction", "图标顺序"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    rowDirectionLabel:SetPoint("TOPLEFT", 232, -308)
    rowDirectionLabel:Hide()

    local iconSizeLabel = GUI2:CreateText(
        panel,
        T("designer.layout.icon_size", "图标尺寸"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    iconSizeLabel:SetPoint("TOPLEFT", 232, -246)

    local directionDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 206,
        height = 30,
        options = function()
            return DesignerUI:BuildCurrentDirectionOptions()
        end,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            DesignerUI:SetSelectedGroupWrapMode(value)
        end,
    })
    directionDropdown:SetPoint("TOPLEFT", 16, -264)

    local rowDirectionDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 112,
        height = 30,
        options = BuildRowDirectionOptions,
        set = function(value)
            DesignerUI:SetSelectedGroupIconLayout("rowDirection", value)
        end,
    })
    rowDirectionDropdown:SetPoint("TOPLEFT", 232, -326)
    rowDirectionDropdown:Hide()

    local iconAlignment = {}
    iconAlignment.label = GUI2:CreateText(
        panel, T("designer.layout.icon_alignment", "排列对齐"),
        "font.size.sm", "color.text.secondary", "LEFT"
    )
    iconAlignment.label:SetPoint("TOPLEFT", 16, -300)
    iconAlignment.dropdown = GUI2.Form:CreateDropdown(panel, {
        width = 206,
        height = 30,
        options = I.BuildIconAlignmentOptions,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            DesignerUI:SetSelectedGroupIconLayout("alignment", value)
        end,
    })
    iconAlignment.dropdown:SetPoint("TOPLEFT", 16, -320)
    iconAlignment.label:Hide()
    iconAlignment.dropdown:Hide()

    local iconSizeDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 112,
        height = 30,
        options = function()
            return DesignerUI:BuildPrimarySizeOptions()
        end,
        set = function(value)
            DesignerUI:SetSelectedGroupPrimarySize(value)
        end,
    })
    iconSizeDropdown:SetPoint("TOPLEFT", 232, -264)

    local spacingLabel = GUI2:CreateText(
        panel,
        T("designer.layout.spacing", "间距"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    spacingLabel:SetPoint("TOPLEFT", 16, -308)

    local maxPerLineLabel = GUI2:CreateText(
        panel,
        T("designer.layout.max_per_line", "每行 / 列数量"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    maxPerLineLabel:SetPoint("TOPLEFT", 124, -308)

    local secondarySizeLabel = GUI2:CreateText(
        panel,
        T("designer.layout.height", "高度"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    secondarySizeLabel:SetPoint("TOPLEFT", 232, -308)

    local spacingDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 98,
        height = 30,
        options = BuildNumberOptions({
            0, 2, 4, 6, 8, 10, 12, 16, 20, 24, 32,
        }),
        set = function(value)
            DesignerUI:SetSelectedGroupLayout("spacing", value)
        end,
    })
    spacingDropdown:SetPoint("TOPLEFT", 16, -326)

    local maxPerLineDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 98,
        height = 30,
        options = BuildNumberOptions({
            1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 16, 20,
        }),
        set = function(value)
            DesignerUI:SetSelectedGroupLayout("maxPerLine", value)
        end,
    })
    maxPerLineDropdown:SetPoint("TOPLEFT", 124, -326)

    local secondarySizeDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 112,
        height = 30,
        options = function()
            if DesignerUI.settingsLayoutType == "rings" then
                return BuildNumberOptions({
                    2, 4, 6, 8, 10, 12, 16, 20, 24, 32, 40, 48,
                })
            end
            return BuildNumberOptions({
                12, 16, 20, 24, 28, 32, 40, 48, 64, 80, 120,
                160, 200, 256, 320, 352,
            })
        end,
        set = function(value)
            if DesignerUI.settingsLayoutType == "bars" then
                DesignerUI:SetSelectedGroupDurationLayout("height", value)
            end
        end,
    })
    secondarySizeDropdown:SetPoint("TOPLEFT", 232, -326)

    local orientationLabel = GUI2:CreateText(
        panel,
        T("designer.layout.orientation", "进度方向"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    orientationLabel:SetPoint("TOPLEFT", 16, -370)

    local iconPositionLabel = GUI2:CreateText(
        panel,
        T("designer.layout.icon_position", "图标位置"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    iconPositionLabel:SetPoint("TOPLEFT", 124, -370)

    local iconGapLabel = GUI2:CreateText(
        panel,
        T("designer.layout.icon_gap", "图标间距"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    iconGapLabel:SetPoint("TOPLEFT", 232, -370)

    local orientationDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 98,
        height = 30,
        options = I.BuildDurationDirectionOptions,
        set = function(value)
            DesignerUI:SetSelectedGroupDurationOrientation(value)
        end,
    })
    orientationDropdown:SetPoint("TOPLEFT", 16, -388)

    local iconPositionDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 98,
        height = 30,
        options = BuildIconPositionOptions,
        set = function(value)
            DesignerUI:SetSelectedGroupDurationLayout(
                "iconPosition",
                value
            )
        end,
    })
    iconPositionDropdown:SetPoint("TOPLEFT", 124, -388)

    local iconGapDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 112,
        height = 30,
        options = BuildNumberOptions({
            0, 2, 4, 6, 8, 10, 12, 16, 20, 24, 32,
        }),
        set = function(value)
            DesignerUI:SetSelectedGroupDurationLayout("iconGap", value)
        end,
    })
    iconGapDropdown:SetPoint("TOPLEFT", 232, -388)

    local shapeLabel = GUI2:CreateText(
        panel,
        T("designer.appearance.shape", "图标形状"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    shapeLabel:SetPoint("TOPLEFT", 16, -246)

    local borderLabel = GUI2:CreateText(
        panel,
        T("designer.appearance.border", "边框"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    borderLabel:SetPoint("TOPLEFT", 236, -246)

    local shapeDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 210,
        height = 30,
        options = BuildShapeOptions,
        set = function(value)
            DesignerUI:SetSelectedGroupStyle("iconShape", value)
        end,
    })
    shapeDropdown:SetPoint("TOPLEFT", 16, -264)

    local borderDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 108,
        height = 30,
        options = BuildBorderOptions,
        set = function(value)
            DesignerUI:SetSelectedGroupStyle("iconBorder", value)
        end,
    })
    borderDropdown:SetPoint("TOPLEFT", 236, -264)

    local fillColorLabel = GUI2:CreateText(
        panel,
        T("designer.appearance.fill_color", "填充颜色"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    fillColorLabel:SetPoint("TOPLEFT", 16, -308)

    local fillColorPicker = GUI2.Form:CreateColorPicker(panel, {
        width = 328,
        height = 30,
        field = true,
        hasAlpha = true,
        set = function(value)
            DesignerUI:SetSelectedGroupDurationStyle(
                "fillColor",
                value
            )
        end,
    })
    fillColorPicker:SetPoint("TOPLEFT", 16, -326)

    local zoomLabel = GUI2:CreateText(
        panel,
        T("designer.appearance.zoom", "图标缩放"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    local zoomDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 328,
        height = 30,
        options = BuildNumberOptions({
            0, 0.04, 0.08, 0.12, 0.16, 0.20, 0.24,
        }),
        set = function(value)
            DesignerUI:SetSelectedGroupStyle("iconZoom", value)
        end,
    })

    local iconBackgroundLabel = GUI2:CreateText(
        panel,
        T("designer.appearance.background", "图标背景"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    local iconBackgroundPicker = GUI2.Form:CreateColorPicker(panel, {
        width = 160,
        height = 30,
        field = true,
        hasAlpha = true,
        set = function(value)
            DesignerUI:SetSelectedGroupStyle(
                "iconBackgroundColor",
                value
            )
        end,
    })
    local iconBorderColorLabel = GUI2:CreateText(
        panel,
        T("designer.appearance.border_color", "边框颜色"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    local iconBorderColorPicker = GUI2.Form:CreateColorPicker(panel, {
        width = 160,
        height = 30,
        field = true,
        hasAlpha = true,
        set = function(value)
            DesignerUI:SetSelectedGroupBorderColor(value)
        end,
    })

    local fillTextureLabel = GUI2:CreateText(
        panel,
        T("designer.appearance.texture", "条材质"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    local fillTextureDropdown = S:CreateTextureSelector(panel, {
        width = 160,
        height = 30,
        get = function() return "yui-g1" end,
        set = function(value)
            DesignerUI:SetSelectedGroupDurationStyle(
                "fillTexture",
                value
            )
        end,
    })
    local trackColorLabel = GUI2:CreateText(
        panel,
        T("designer.appearance.track_color", "轨道颜色"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    local trackColorPicker = GUI2.Form:CreateColorPicker(panel, {
        width = 160,
        height = 30,
        field = true,
        hasAlpha = true,
        set = function(value)
            DesignerUI:SetSelectedGroupTrackColor(value)
        end,
    })
    local showDurationIconLabel = GUI2:CreateText(
        panel,
        T("designer.appearance.show_icon", "显示图标"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    local showDurationIconSwitch = GUI2.Form:CreateSwitch(panel, {
        width = 42,
        height = 22,
        set = function(value)
            DesignerUI:SetSelectedGroupDurationStyle(
                "showIcon",
                value == true
            )
        end,
    })
    local durationSmoothProgressLabel = GUI2:CreateText(
        panel,
        T("designer.appearance.smooth_progress", "平滑进度"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    local durationSmoothProgressSwitch = GUI2.Form:CreateSwitch(panel, {
        width = 42,
        height = 22,
        set = function(value)
            DesignerUI:SetSelectedGroupDurationStyle(
                "smoothProgress",
                value == true
            )
        end,
    })

    local ringThicknessLabel = GUI2:CreateText(
        panel,
        T("designer.ring.thickness", "圆环粗细"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    local ringThicknessDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 98,
        height = 30,
        options = function()
            return {
                { text = T("designer.ring.width_thin", "细"), value = 4 },
                { text = T("designer.ring.width_standard", "标准"), value = 8 },
                { text = T("designer.ring.width_thick", "粗"), value = 14 },
                { text = T("designer.ring.width_heavy", "特粗"), value = 22 },
            }
        end,
        set = function(value)
            DesignerUI:SetSelectedGroupDurationStyle(
                "ringThickness",
                value
            )
        end,
    })
    local ringProgressDirectionLabel = GUI2:CreateText(
        panel,
        T("designer.ring.progress_direction", "旋转方向"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    local ringProgressDirectionDropdown =
        GUI2.Form:CreateDropdown(panel, {
            width = 106,
            height = 30,
            options = function()
                return {
                    {
                        text = T("designer.ring.clockwise", "顺时针"),
                        value = "clockwise",
                    },
                    {
                        text = T(
                            "designer.ring.counterclockwise",
                            "逆时针"
                        ),
                        value = "counterclockwise",
                    },
                }
            end,
            set = function(value)
                DesignerUI:SetSelectedGroupDurationStyle(
                    "ringDirection",
                    value
                )
            end,
        })
    local ringStartLabel = GUI2:CreateText(
        panel,
        T("designer.ring.start", "起点"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    local ringStartDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 106,
        height = 30,
        options = function()
            return {
                {
                    text = T("designer.text_position.top", "上方"),
                    value = "top",
                },
                {
                    text = T("designer.text_position.right", "右侧"),
                    value = "right",
                },
                {
                    text = T("designer.text_position.bottom", "下方"),
                    value = "bottom",
                },
                {
                    text = T("designer.text_position.left", "左侧"),
                    value = "left",
                },
            }
        end,
        set = function(value)
            DesignerUI:SetSelectedGroupDurationStyle(
                "ringStart",
                value
            )
        end,
    })

    local iconTextTargetMode = GUI2.Form:CreateSegmentedControl(panel, {
        width = 328,
        height = 28,
        items = {
            {
                text = T("designer.text_target.cooldown", "冷却时间"),
                value = "cooldown",
            },
            {
                text = T("designer.text_target.count", "层数/充能"),
                value = "count",
            },
        },
        value = "cooldown",
        set = function(value)
            DesignerUI:SetDurationTextTarget(value)
        end,
    })
    iconTextTargetMode:SetPoint("TOPLEFT", 16, -240)

    local durationTextTargetMode = GUI2.Form:CreateSegmentedControl(panel, {
        width = 328,
        height = 28,
        items = {
            {
                text = T("designer.text_target.duration", "持续时间"),
                value = "cooldown",
            },
            {
                text = T("designer.text_target.name", "名称"),
                value = "name",
            },
            {
                text = T("designer.text_target.count", "层数/充能"),
                value = "count",
            },
        },
        value = "cooldown",
        set = function(value)
            DesignerUI:SetDurationTextTarget(value)
        end,
    })
    durationTextTargetMode:SetPoint("TOPLEFT", 16, -240)

    local cooldownTextLabel = GUI2:CreateText(
        panel,
        T("designer.text.enabled", "冷却时间"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    cooldownTextLabel:SetPoint("TOPLEFT", 16, -290)

    local cooldownTextSwitch = GUI2.Form:CreateSwitch(panel, {
        width = 42,
        height = 22,
        set = function(value)
            DesignerUI:SetSelectedGroupTextStyle(
                "",
                value == true
            )
        end,
    })
    cooldownTextSwitch:SetPoint("TOPLEFT", 74, -284)

    local fontLabel = GUI2:CreateText(
        panel,
        T("designer.text.font", "字体"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    fontLabel:SetPoint("TOPLEFT", 124, -290)

    local textSizeLabel = GUI2:CreateText(
        panel,
        T("designer.text.size", "字号"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    textSizeLabel:SetPoint("TOPLEFT", 232, -290)

    local fontDropdown = GUI2.Form:CreateLSMFontDropdown(panel, {
        width = 98,
        height = 30,
        prependOptions = BuildFontOptions,
        set = function(value)
            DesignerUI:SetSelectedGroupTextStyle("Font", value)
        end,
    })
    fontDropdown:SetPoint("TOPLEFT", 124, -308)

    local textSizeDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 112,
        height = 30,
        options = BuildNumberOptions({
            8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32,
        }),
        set = function(value)
            DesignerUI:SetSelectedGroupTextStyle("Size", value)
        end,
    })
    textSizeDropdown:SetPoint("TOPLEFT", 232, -308)

    local outlineLabel = GUI2:CreateText(
        panel,
        T("designer.text.outline", "描边"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    outlineLabel:SetPoint("TOPLEFT", 16, -352)

    local textPositionLabel = GUI2:CreateText(
        panel,
        T("designer.text.position", "位置"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    textPositionLabel:SetPoint("TOPLEFT", 124, -352)

    local textColorLabel = GUI2:CreateText(
        panel,
        T("designer.text.color", "颜色"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    textColorLabel:SetPoint("TOPLEFT", 232, -352)

    local outlineDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 98,
        height = 30,
        options = BuildOutlineOptions,
        set = function(value)
            DesignerUI:SetSelectedGroupTextStyle("Outline", value)
        end,
    })
    outlineDropdown:SetPoint("TOPLEFT", 16, -370)

    local textPositionDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 98,
        menuWidth = 220,
        height = 30,
        options = function()
            return DesignerUI:BuildCurrentTextPositionOptions()
        end,
        set = function(value)
            DesignerUI:SetSelectedGroupTextStyle("Position", value)
        end,
    })
    textPositionDropdown:SetPoint("TOPLEFT", 124, -370)

    local textColorPicker = GUI2.Form:CreateColorPicker(panel, {
        width = 112,
        height = 30,
        field = true,
        hasAlpha = true,
        set = function(value)
            DesignerUI:SetSelectedGroupTextStyle("Color", value)
        end,
    })
    textColorPicker:SetPoint("TOPLEFT", 232, -370)

    local textOffsetXSlider = GUI2.Form:CreateSlider(panel, {
        width = 156,
        inline = true,
        label = TC("common.offset_x", "X 偏移"),
        labelWidth = 54,
        inputWidth = 42,
        min = -64,
        max = 64,
        step = 1,
        set = function(value)
            DesignerUI:SetSelectedGroupTextStyle("OffsetX", value)
        end,
    })
    textOffsetXSlider:SetPoint("TOPLEFT", 16, -414)

    local textOffsetYSlider = GUI2.Form:CreateSlider(panel, {
        width = 156,
        inline = true,
        label = TC("common.offset_y", "Y 偏移"),
        labelWidth = 54,
        inputWidth = 42,
        min = -64,
        max = 64,
        step = 1,
        set = function(value)
            DesignerUI:SetSelectedGroupTextStyle("OffsetY", value)
        end,
    })
    textOffsetYSlider:SetPoint("TOPLEFT", 188, -414)

    local nameFormatLabel = GUI2:CreateText(
        panel,
        T("designer.text.name_format", "名称格式"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    nameFormatLabel:SetPoint("TOPLEFT", 16, -458)

    local nameFormatInput = GUI2.Form:CreateEditBox(panel, {
        width = 328,
        height = 30,
        autoFocus = false,
        onFocusLost = function(control)
            DesignerUI:SetSelectedGroupDurationStyle(
                "nameTextFormat",
                control:GetText()
            )
        end,
    })
    nameFormatInput:SetPoint("TOPLEFT", 16, -476)
    nameFormatInput:SetScript("OnEnterPressed", function(control)
        if control.ClearFocus then control:ClearFocus() end
    end)

    local resourceClassLabel = GUI2:CreateText(
        panel,
        T("designer.resource.class", "职业"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceClassLabel:SetPoint("TOPLEFT", 16, -246)

    local resourceSpecLabel = GUI2:CreateText(
        panel,
        T("designer.resource.spec", "专精"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceSpecLabel:SetPoint("TOPLEFT", 184, -246)

    local resourceClassDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 160,
        height = 30,
        options = function()
            return DesignerUI:BuildResourceClassOptions()
        end,
        set = function(value)
            DesignerUI:SetResourcePreviewClass(value)
        end,
    })
    resourceClassDropdown:SetPoint("TOPLEFT", 16, -264)

    local resourceSpecDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 160,
        height = 30,
        options = function()
            return DesignerUI:BuildResourceSpecOptions()
        end,
        set = function(value)
            DesignerUI:SetResourcePreviewSpec(value)
        end,
    })
    resourceSpecDropdown:SetPoint("TOPLEFT", 184, -264)

    local resourceFormLabel = GUI2:CreateText(
        panel,
        T("designer.resource.form", "形态"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceFormLabel:SetPoint("TOPLEFT", 16, -310)

    local resourceFormDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 328,
        height = 30,
        options = function()
            return DesignerUI:BuildResourceFormOptions()
        end,
        set = function(value)
            DesignerUI:SetResourcePreviewForm(value)
        end,
    })
    resourceFormDropdown:SetPoint("TOPLEFT", 16, -328)

    local resourceOverrideStatus = GUI2:CreateText(
        panel,
        "",
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceOverrideStatus:SetPoint("TOPLEFT", 16, -372)

    local resourceResetFormButton = GUI2.Form:CreateButton(panel, {
        text = T("designer.resource.restore_default", "恢复默认"),
        width = 96,
        height = 24,
        tone = "default",
        onClick = function()
            DesignerUI:ResetResourceFormOverride()
        end,
    })
    resourceResetFormButton:SetPoint("TOPRIGHT", -16, -366)

    local resourceFormHelp = GUI2:CreateText(
        panel,
        T(
            "designer.resource.form_help",
            "仅影响所选专精和形态；未自定义时使用默认矩阵。"
        ),
        "font.size.sm",
        "color.text.muted",
        "LEFT"
    )
    resourceFormHelp:SetPoint("TOPLEFT", 16, -398)
    resourceFormHelp:SetWidth(328)

    local resourcePresetLabel = GUI2:CreateText(
        panel,
        T("designer.resource.form_presets", "形态资源"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourcePresetLabel:SetPoint("TOPLEFT", 16, -310)

    local resourcePresetRows = {}
    for index = 1, RESOURCE_PRESET_ROW_COUNT do
        local row = GUI2:CreateFrame(panel, {
            width = 328,
            height = 28,
            hidden = true,
        })
        row:SetPoint("TOPLEFT", 16, -326 - ((index - 1) * 28))
        local label = GUI2:CreateText(
            row,
            "",
            "font.size.md",
            "color.text.primary",
            "LEFT"
        )
        local swatch = GUI2:CreateTexture(row, nil, "ARTWORK")
        swatch:SetSize(12, 12)
        swatch:SetPoint("LEFT", 2, 0)
        label:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
        label:SetPoint("RIGHT", -166, 0)
        label:SetWordWrap(false)
        local toggle = GUI2.Form:CreateSwitch(row, {
            width = 84,
            height = 22,
            set = function(value)
                if row.resourceId then
                    DesignerUI:SetResourcePresetEnabled(
                        row.resourceId,
                        value == true
                    )
                end
            end,
        })
        toggle:SetPoint("RIGHT", -2, 0)
        local moveDown = GUI2.Form:CreateButton(row, {
            text = "",
            microIcon = "arrow-big-down",
            iconSize = 16,
            iconGap = 0,
            contentAlign = "center",
            tooltip = T("designer.monitor.move_down", "下移"),
            width = 24,
            height = 22,
            tone = "default",
            onClick = function()
                if row.resourceId then
                    DesignerUI:ReorderResourcePreset(row.resourceId, 1)
                end
            end,
        })
        moveDown:SetPoint("RIGHT", toggle, "LEFT", -4, 0)
        local moveUp = GUI2.Form:CreateButton(row, {
            text = "",
            microIcon = "arrow-big-up",
            iconSize = 16,
            iconGap = 0,
            contentAlign = "center",
            tooltip = T("designer.monitor.move_up", "上移"),
            width = 24,
            height = 22,
            tone = "default",
            onClick = function()
                if row.resourceId then
                    DesignerUI:ReorderResourcePreset(row.resourceId, -1)
                end
            end,
        })
        moveUp:SetPoint("RIGHT", moveDown, "LEFT", -4, 0)
        row.label = label
        row.swatch = swatch
        row.toggle = toggle
        row.moveUp = moveUp
        row.moveDown = moveDown
        resourcePresetRows[index] = row
    end

    local resourceWidthLabel = GUI2:CreateText(
        panel,
        T("designer.resource.width", "宽度"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceWidthLabel:SetPoint("TOPLEFT", 16, -414)
    local resourceHeightLabel = GUI2:CreateText(
        panel,
        T("designer.resource.height", "高度"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceHeightLabel:SetPoint("TOPLEFT", 128, -414)
    local resourceSpacingLabel = GUI2:CreateText(
        panel,
        T("designer.layout.spacing", "间距"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceSpacingLabel:SetPoint("TOPLEFT", 240, -414)

    local resourceWidthDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 104,
        height = 30,
        options = BuildNumberOptions({
            120, 160, 180, 220, 260, 290, 320, 360, 420, 520, 640,
        }),
        set = function(value)
            DesignerUI:SetSelectedGroupResourceLayout("width", value)
        end,
    })
    resourceWidthDropdown:SetPoint("TOPLEFT", 16, -432)
    local resourceHeightDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 104,
        height = 30,
        options = BuildNumberOptions({
            8, 12, 16, 20, 24, 28, 32, 40, 48, 64, 80,
        }),
        set = function(value)
            DesignerUI:SetSelectedGroupResourceLayout("height", value)
        end,
    })
    resourceHeightDropdown:SetPoint("TOPLEFT", 128, -432)
    local resourceSpacingDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 104,
        height = 30,
        options = BuildNumberOptions({
            0, 2, 4, 6, 8, 10, 12, 16, 20, 24, 32,
        }),
        set = function(value)
            DesignerUI:SetSelectedGroupResourceLayout("spacing", value)
        end,
    })
    resourceSpacingDropdown:SetPoint("TOPLEFT", 240, -432)

    local resourceDirectionLabel = GUI2:CreateText(
        panel,
        T("designer.layout.direction", "生长方向"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceDirectionLabel:SetPoint("TOPLEFT", 16, -476)
    local resourceAlignmentLabel = GUI2:CreateText(
        panel,
        T("designer.layout.alignment", "对齐方式"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceAlignmentLabel:SetPoint("TOPLEFT", 184, -476)

    local resourceDirectionDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 160,
        height = 30,
        options = BuildDirectionOptions,
        set = function(value)
            DesignerUI:SetSelectedGroupResourceLayout("direction", value)
        end,
    })
    resourceDirectionDropdown:SetPoint("TOPLEFT", 16, -494)
    local resourceAlignmentDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 160,
        height = 30,
        options = BuildAlignmentOptions,
        set = function(value)
            DesignerUI:SetSelectedGroupResourceLayout("alignment", value)
        end,
    })
    resourceAlignmentDropdown:SetPoint("TOPLEFT", 184, -494)

    local resourceOrientationLabel = GUI2:CreateText(
        panel,
        T("designer.resource.orientation", "资源方向"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceOrientationLabel:SetPoint("TOPLEFT", 16, -538)
    local resourceFillDirectionLabel = GUI2:CreateText(
        panel,
        T("designer.resource.fill_direction", "填充方向"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceFillDirectionLabel:SetPoint("TOPLEFT", 184, -538)

    local resourceOrientationDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 160,
        height = 30,
        options = BuildOrientationOptions,
        set = function(value)
            DesignerUI:SetSelectedGroupResourceLayout("orientation", value)
        end,
    })
    resourceOrientationDropdown:SetPoint("TOPLEFT", 16, -556)
    local resourceFillDirectionDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 160,
        height = 30,
        options = BuildResourceFillDirectionOptions,
        set = function(value)
            DesignerUI:SetSelectedGroupResourceLayout("fillDirection", value)
        end,
    })
    resourceFillDirectionDropdown:SetPoint("TOPLEFT", 184, -556)

    local resourceBorderLabel = GUI2:CreateText(
        panel,
        T("designer.appearance.border", "边框"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceBorderLabel:SetPoint("TOPLEFT", 16, -414)
    local resourceBackgroundLabel = GUI2:CreateText(
        panel,
        T("designer.resource.background", "背景颜色"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceBackgroundLabel:SetPoint("TOPLEFT", 184, -414)
    local resourceBorderDropdown = GUI2.Form:CreateSlider(panel, {
        width = 160,
        inline = true,
        inputWidth = 42,
        min = 0,
        max = 12,
        step = 1,
        set = function(value)
            if DesignerUI.SetSelectedGroupResourceBorderThickness then
                return DesignerUI:SetSelectedGroupResourceBorderThickness(value)
            end
            DesignerUI:SetSelectedGroupResourceStyle("border", value)
        end,
    })
    resourceBorderDropdown:SetPoint("TOPLEFT", 16, -432)
    local resourceBackgroundPicker = GUI2.Form:CreateColorPicker(panel, {
        width = 160,
        field = true,
        hasAlpha = true,
        set = function(value)
            DesignerUI:SetSelectedGroupResourceStyle(
                "backgroundColor",
                value
            )
        end,
    })
    resourceBackgroundPicker:SetPoint("TOPLEFT", 184, -432)

    local resourceTextureLabel = GUI2:CreateText(
        panel,
        T("designer.appearance.texture", "条材质"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    local resourceTextureDropdown = S:CreateTextureSelector(panel, {
        width = 160,
        menuWidth = RESOURCE_MENU_WIDTH,
        get = function() return "yui-g1" end,
        set = function(value)
            DesignerUI:SetSelectedGroupResourceStyle(
                "fillTexture",
                value
            )
        end,
    })
    local resourceFillModeLabel = GUI2:CreateText(
        panel,
        T("designer.resource.fill_mode", "填充颜色"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    local resourceFillModeDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 160,
        menuWidth = RESOURCE_MENU_WIDTH,
        options = function()
            return {
                {
                    text = T("designer.resource.resource_color", "资源色"),
                    value = "resource",
                },
                {
                    text = T("designer.resource.custom_color", "自定义"),
                    value = "custom",
                },
            }
        end,
        set = function(value)
            DesignerUI:SetSelectedGroupResourceStyle(
                "fillColorMode",
                value
            )
        end,
    })
    local resourceFillColorLabel = GUI2:CreateText(
        panel,
        T("designer.appearance.fill_color", "填充颜色"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    local resourceFillColorPicker = GUI2.Form:CreateColorPicker(panel, {
        width = 160,
        field = true,
        hasAlpha = true,
        set = function(value)
            DesignerUI:SetSelectedGroupResourceStyle(
                "fillColor",
                value
            )
        end,
    })
    local resourceBorderColorLabel = GUI2:CreateText(
        panel,
        T("designer.appearance.border_color", "边框颜色"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    local resourceBorderColorPicker =
        GUI2.Form:CreateColorPicker(panel, {
            width = 160,
            field = true,
            hasAlpha = true,
            set = function(value)
                DesignerUI:SetSelectedGroupResourceStyle(
                    "borderColor",
                    value
                )
            end,
        })
    local resourceSmoothProgressLabel = GUI2:CreateText(
        panel,
        T("designer.appearance.smooth_progress", "平滑进度"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    local resourceSmoothProgressSwitch = GUI2.Form:CreateSwitch(panel, {
        width = 42,
        height = 22,
        set = function(value)
            DesignerUI:SetSelectedGroupResourceStyle(
                "smoothProgress",
                value == true
            )
        end,
    })

    local resourceNameLabel = GUI2:CreateText(
        panel,
        T("designer.resource.show_name", "显示名称"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceNameLabel:SetPoint("TOPLEFT", 16, -414)
    local resourceNameSwitch = GUI2.Form:CreateSwitch(panel, {
        width = 42,
        height = 22,
        set = function(value)
            DesignerUI:SetSelectedGroupResourceStyle(
                "nameText",
                value == true
            )
        end,
    })
    resourceNameSwitch:SetPoint("TOPLEFT", 84, -408)
    local resourceValueLabel = GUI2:CreateText(
        panel,
        T("designer.resource.show_value", "显示数值"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceValueLabel:SetPoint("TOPLEFT", 184, -414)
    local resourceValueSwitch = GUI2.Form:CreateSwitch(panel, {
        width = 42,
        height = 22,
        set = function(value)
            DesignerUI:SetSelectedGroupResourceStyle(
                "valueText",
                value == true
            )
        end,
    })
    resourceValueSwitch:SetPoint("TOPLEFT", 252, -408)

    local resourceFontLabel = GUI2:CreateText(
        panel,
        T("designer.text.font", "字体"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceFontLabel:SetPoint("TOPLEFT", 16, -458)
    local resourceTextSizeLabel = GUI2:CreateText(
        panel,
        T("designer.text.size", "字号"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceTextSizeLabel:SetPoint("TOPLEFT", 184, -458)
    local resourceFontDropdown = GUI2.Form:CreateLSMFontDropdown(panel, {
        width = 160,
        menuWidth = RESOURCE_MENU_WIDTH,
        prependOptions = BuildFontOptions,
        set = function(value)
            DesignerUI:SetSelectedGroupResourceStyle("textFont", value)
        end,
    })
    resourceFontDropdown:SetPoint("TOPLEFT", 16, -476)
    local resourceTextSizeDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 160,
        options = BuildNumberOptions({
            8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32,
        }),
        set = function(value)
            DesignerUI:SetSelectedGroupResourceStyle("textSize", value)
        end,
    })
    resourceTextSizeDropdown:SetPoint("TOPLEFT", 184, -476)

    local resourceOutlineLabel = GUI2:CreateText(
        panel,
        T("designer.text.outline", "描边"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceOutlineLabel:SetPoint("TOPLEFT", 16, -520)
    local resourceTextColorLabel = GUI2:CreateText(
        panel,
        T("designer.text.color", "颜色"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    resourceTextColorLabel:SetPoint("TOPLEFT", 184, -520)
    local resourceOutlineDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 160,
        menuWidth = RESOURCE_MENU_WIDTH,
        options = BuildOutlineOptions,
        set = function(value)
            DesignerUI:SetSelectedGroupResourceStyle("textOutline", value)
        end,
    })
    resourceOutlineDropdown:SetPoint("TOPLEFT", 16, -538)
    local resourceTextColorPicker = GUI2.Form:CreateColorPicker(panel, {
        width = 160,
        field = true,
        hasAlpha = true,
        set = function(value)
            DesignerUI:SetSelectedGroupResourceStyle("textColor", value)
        end,
    })
    resourceTextColorPicker:SetPoint("TOPLEFT", 184, -538)

    local statusText = self.statusText or GUI2:CreateText(
        panel, "", "font.size.md", "color.text.secondary", "LEFT"
    )
    statusText:SetPoint("TOPLEFT", 16, -472)
    statusText:SetPoint("TOPRIGHT", -16, -472)
    statusText:SetHeight(32)
    statusText:SetWordWrap(true)

    local monitorHeading = GUI2:CreateText(
        panel,
        T("designer.monitor_none", "选择一个监控"),
        "font.size.lg",
        "color.text.heading",
        "LEFT"
    )
    monitorHeading:SetPoint("TOPLEFT", 16, -512)
    monitorHeading:SetPoint("TOPRIGHT", -16, -512)
    monitorHeading:SetWordWrap(false)

    local monitorGroupLabel = GUI2:CreateText(
        panel,
        T("designer.move_group", "移动到分组"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    monitorGroupLabel:SetPoint("TOPLEFT", 16, -548)

    local monitorGroupDropdown = GUI2.Form:CreateDropdown(panel, {
        width = 328,
        height = 30,
        options = function()
            return DesignerUI:BuildMonitorTargetOptions()
        end,
        get = function()
            local monitor = Designer:GetSelectedMonitor()
            return monitor and monitor.groupId
        end,
        set = function(value)
            DesignerUI:MoveSelectedMonitor(value)
        end,
    })
    monitorGroupDropdown:SetPoint("TOPLEFT", 16, -566)

    local moveUpButton = GUI2.Form:CreateButton(panel, {
        text = "",
        microIcon = "arrow-big-up",
        iconSize = 16,
        iconGap = 0,
        contentAlign = "center",
        tooltip = T("designer.monitor.move_up", "上移"),
        width = 72,
        height = 30,
        tone = "default",
        onClick = function()
            DesignerUI:ReorderSelectedMonitor(-1)
        end,
    })
    moveUpButton:SetPoint("TOPLEFT", 16, -608)

    local moveDownButton = GUI2.Form:CreateButton(panel, {
        text = "",
        microIcon = "arrow-big-down",
        iconSize = 16,
        iconGap = 0,
        contentAlign = "center",
        tooltip = T("designer.monitor.move_down", "下移"),
        width = 72,
        height = 30,
        tone = "default",
        onClick = function()
            DesignerUI:ReorderSelectedMonitor(1)
        end,
    })
    moveDownButton:SetPoint("LEFT", moveUpButton, "RIGHT", 8, 0)

    local removeMonitorButton = GUI2.Form:CreateButton(panel, {
        text = TC("common.delete", "删除"),
        icon = CoreAsset("gui2\\icons\\settings\\trash-2.png"),
        iconSize = 16,
        contentAlign = "center",
        width = 168,
        height = 30,
        tone = "danger",
        onClick = function()
            DesignerUI:RemoveSelectedMonitor()
        end,
    })
    removeMonitorButton:SetPoint("LEFT", moveDownButton, "RIGHT", 8, 0)

    local monitorGlowButton = GUI2.Form:CreateButton(panel, {
        text = T("designer.glow.open", "发光设置"),
        width = 328,
        height = 30,
        tone = "default",
        onClick = function()
            DesignerUI:OpenGlowEditor()
        end,
    })
    monitorGlowButton:SetPoint("TOPLEFT", 16, -648)
    monitorGlowButton:Hide()

    local deleteGroupButton = self.deleteGroupButton
        or GUI2.Form:CreateButton(panel, {
            text = T("designer.delete_group", "删除分组"),
            width = 328,
            height = 30,
            tone = "danger",
            onClick = function()
                DesignerUI:DeleteSelectedGroup()
            end,
        })
    deleteGroupButton:SetPoint("BOTTOMLEFT", 16, 58)
    deleteGroupButton:Hide()

    local addMonitorButton = GUI2.Form:CreateButton(panel, {
        text = T("designer.add_cooldown.short", "+ 冷却"),
        tooltip = T("designer.add_cooldown", "添加技能/物品"),
        width = 160,
        height = 34,
        tone = "warning",
        onClick = function()
            DesignerUI:OpenMonitorPicker(nil, "cooldown")
        end,
    })
    addMonitorButton:SetPoint("BOTTOMLEFT", 16, 16)

    local addBuffButton = GUI2.Form:CreateButton(panel, {
        text = T("designer.add_buff.short", "+ 光环"),
        tooltip = T("designer.add_buff", "添加光环"),
        width = 160,
        height = 34,
        tone = "warning",
        onClick = function()
            DesignerUI:OpenMonitorPicker(nil, "buff")
        end,
    })
    addBuffButton:SetPoint("LEFT", addMonitorButton, "RIGHT", 8, 0)

    local glowEditor = GUI2:CreatePanel(UIParent, {
        name = "YUI_YHUD_DesignerGlowEditor",
        width = 390,
        height = 480,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    glowEditor:SetFrameStrata("FULLSCREEN_DIALOG")
    glowEditor:SetFrameLevel(430)
    glowEditor:EnableMouse(true)
    if glowEditor.SetClampedToScreen then
        glowEditor:SetClampedToScreen(true)
    end
    glowEditor:Hide()

    local glowTitle = GUI2:CreateText(
        glowEditor,
        T("designer.glow.title", "发光设置"),
        "font.size.xl",
        "color.text.heading",
        "LEFT"
    )
    glowTitle:SetPoint("TOPLEFT", 16, -18)
    glowTitle:SetPoint("TOPRIGHT", -54, -18)
    glowTitle:SetWordWrap(false)

    local glowClose = GUI2.Form:CreateButton(glowEditor, {
        text = "×",
        width = 30,
        height = 30,
        tone = "default",
        onClick = function()
            DesignerUI:HideGlowEditor()
        end,
    })
    glowClose:SetPoint("TOPRIGHT", -14, -12)

    local glowEnabledLabel = GUI2:CreateText(
        glowEditor,
        T("designer.glow.enabled", "启用发光"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    glowEnabledLabel:SetPoint("TOPLEFT", 18, -66)

    local glowEnabledSwitch = GUI2.Form:CreateSwitch(glowEditor, {
        width = 48,
        height = 24,
        set = function(value)
            DesignerUI:SetSelectedMonitorGlowEnabled(value == true)
        end,
    })
    glowEnabledSwitch:SetPoint("TOPRIGHT", -18, -60)

    local glowTriggerLabel = GUI2:CreateText(
        glowEditor,
        T("designer.glow.trigger", "触发时机"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    glowTriggerLabel:SetPoint("TOPLEFT", 18, -112)

    local glowTriggerDropdown = GUI2.Form:CreateDropdown(glowEditor, {
        width = 354,
        height = 30,
        options = BuildGlowTriggerOptions,
        set = function(value)
            DesignerUI:SetSelectedMonitorGlowTrigger(value)
        end,
    })
    glowTriggerDropdown:SetPoint("TOPLEFT", 18, -130)

    local glowCombatLabel = GUI2:CreateText(
        glowEditor,
        T("designer.glow.combat_only", "仅战斗中"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    glowCombatLabel:SetPoint("TOPLEFT", 18, -180)

    local glowCombatSwitch = GUI2.Form:CreateSwitch(glowEditor, {
        width = 48,
        height = 24,
        set = function(value)
            DesignerUI:SetSelectedMonitorGlowCombatOnly(value == true)
        end,
    })
    glowCombatSwitch:SetPoint("TOPRIGHT", -18, -174)

    local glowAppearanceLabel = GUI2:CreateText(
        glowEditor,
        T("designer.glow.appearance", "发光外观"),
        "font.size.md",
        "color.text.heading",
        "LEFT"
    )
    glowAppearanceLabel:SetPoint("TOPLEFT", 18, -224)

    local glowDone = GUI2.Form:CreateButton(glowEditor, {
        text = T("designer.glow.done", "完成"),
        width = 354,
        height = 34,
        tone = "warning",
        onClick = function()
            DesignerUI:HideGlowEditor()
        end,
    })
    glowDone:SetPoint("BOTTOMLEFT", 18, 16)

    if type(self.EnsureDesignerDialogs) ~= "function" then
        return nil, "designer-dialogs-unavailable"
    end
    local dialogsReady, dialogsCode = self:EnsureDesignerDialogs()
    if not dialogsReady then return nil, dialogsCode end
    local blocker = self.dialogBlocker
    local switchDialog = self.switchDialog
    local cancelDialog = self.cancelDialog

    self.dimmer = dimmer
    self.toolbar = toolbar
    self.toolbarTitle = title
    self.contentButton = contentButton
    self.layoutButton = layoutButton
    self.finishButton = finishButton
    self.cancelButton = cancelButton
    self.panel = panel
    self.dragHandle = dragHandle
    self.panelTitle = panelTitle
    self.inspectorTypeBadge = inspectorTypeBadge
    self.inspectorCloseButton = inspectorCloseButton
    self.groupSelectorLabel = groupSelectorLabel
    self.profileDropdown = profileDropdown
    self.groupDropdown = groupDropdown
    self.newGroupButton = newGroupButton
    self.groupHeading = groupHeading
    self.groupNameInput = groupNameInput
    self.groupNameLabel = groupNameLabel
    self.fixedNameBadge = fixedNameBadge
    self.groupSummary = groupSummary
    self.enableSwitch = enableSwitch
    self.enableLabel = enableLabel
    self.unavailablePreviewLabel = unavailablePreviewLabel
    self.unavailablePreviewSwitch = unavailablePreviewSwitch
    self.restoreButton = restoreButton
    self.iconSettingsMode = iconSettingsMode
    self.layoutModeLabel = layoutModeLabel
    self.layoutModeDropdown = layoutModeDropdown
    self.layoutModeOverrideInfo = layoutModeOverrideInfo
    self.displayLayerLabel = displayLayerLabel
    self.displayLayerDropdown = displayLayerDropdown
    self.layoutModeControls = {
        layoutModeLabel,
        layoutModeDropdown,
        layoutModeOverrideInfo,
        displayLayerLabel,
        displayLayerDropdown,
    }
    self.iconLayoutControls = {
        iconAlignment.label,
        iconAlignment.dropdown,
        directionLabel,
        iconSizeLabel,
        rowDirectionLabel,
        directionDropdown,
        iconSizeDropdown,
        rowDirectionDropdown,
        spacingLabel,
        maxPerLineLabel,
        spacingDropdown,
        maxPerLineDropdown,
    }
    self.durationLayoutControls = {
        directionLabel,
        iconSizeLabel,
        directionDropdown,
        iconSizeDropdown,
        spacingLabel,
        maxPerLineLabel,
        secondarySizeLabel,
        spacingDropdown,
        maxPerLineDropdown,
        secondarySizeDropdown,
    }
    self.barLayoutControls = {
        orientationLabel,
        iconPositionLabel,
        iconGapLabel,
        orientationDropdown,
        iconPositionDropdown,
        iconGapDropdown,
    }
    self.iconAppearanceControls = {
        shapeLabel,
        borderLabel,
        shapeDropdown,
        borderDropdown,
        zoomLabel,
        zoomDropdown,
        iconBackgroundLabel,
        iconBackgroundPicker,
        iconBorderColorLabel,
        iconBorderColorPicker,
    }
    self.durationAppearanceControls = {
        fillColorLabel,
        fillColorPicker,
        fillTextureLabel,
        fillTextureDropdown,
        trackColorLabel,
        trackColorPicker,
        showDurationIconLabel,
        showDurationIconSwitch,
        durationSmoothProgressLabel,
        durationSmoothProgressSwitch,
    }
    self.ringAppearanceControls = {
        ringThicknessLabel,
        ringThicknessDropdown,
        ringProgressDirectionLabel,
        ringProgressDirectionDropdown,
        ringStartLabel,
        ringStartDropdown,
    }
    self.iconTextControls = {
        cooldownTextLabel,
        cooldownTextSwitch,
        fontLabel,
        textSizeLabel,
        fontDropdown,
        textSizeDropdown,
        outlineLabel,
        textPositionLabel,
        textColorLabel,
        outlineDropdown,
        textPositionDropdown,
        textColorPicker,
        textOffsetXSlider,
        textOffsetYSlider,
    }
    self.iconTextTargetControls = {
        iconTextTargetMode,
    }
    self.durationTextControls = {
        durationTextTargetMode,
    }
    self.durationNameControls = {
        nameFormatLabel,
        nameFormatInput,
    }
    self.resourceBaseControls = {
        resourceClassLabel,
        resourceSpecLabel,
        resourceClassDropdown,
        resourceSpecDropdown,
        resourceFormLabel,
        resourceFormDropdown,
        resourceOverrideStatus,
        resourceResetFormButton,
        resourceFormHelp,
        resourcePresetLabel,
    }
    self.resourceLayoutControls = {
        resourceWidthLabel,
        resourceHeightLabel,
        resourceSpacingLabel,
        resourceWidthDropdown,
        resourceHeightDropdown,
        resourceSpacingDropdown,
        resourceDirectionLabel,
        resourceAlignmentLabel,
        resourceDirectionDropdown,
        resourceAlignmentDropdown,
        resourceOrientationLabel,
        resourceFillDirectionLabel,
        resourceOrientationDropdown,
        resourceFillDirectionDropdown,
    }
    self.resourceAppearanceControls = {
        resourceBorderLabel,
        resourceBackgroundLabel,
        resourceBorderDropdown,
        resourceBackgroundPicker,
        resourceTextureLabel,
        resourceTextureDropdown,
        resourceFillModeLabel,
        resourceFillModeDropdown,
        resourceFillColorLabel,
        resourceFillColorPicker,
        resourceBorderColorLabel,
        resourceBorderColorPicker,
        resourceSmoothProgressLabel,
        resourceSmoothProgressSwitch,
    }
    self.resourceTextControls = {
        resourceNameLabel,
        resourceNameSwitch,
        resourceValueLabel,
        resourceValueSwitch,
        resourceFontLabel,
        resourceTextSizeLabel,
        resourceFontDropdown,
        resourceTextSizeDropdown,
        resourceOutlineLabel,
        resourceTextColorLabel,
        resourceOutlineDropdown,
        resourceTextColorPicker,
    }
    self.resourceClassDropdown = resourceClassDropdown
    self.resourceSpecDropdown = resourceSpecDropdown
    self.resourceFormLabel = resourceFormLabel
    self.resourceFormDropdown = resourceFormDropdown
    self.resourceOverrideStatus = resourceOverrideStatus
    self.resourceResetFormButton = resourceResetFormButton
    self.resourceFormHelp = resourceFormHelp
    self.resourcePresetLabel = resourcePresetLabel
    self.resourcePresetRows = resourcePresetRows
    self.resourceWidthDropdown = resourceWidthDropdown
    self.resourceHeightDropdown = resourceHeightDropdown
    self.resourceSpacingDropdown = resourceSpacingDropdown
    self.resourceDirectionDropdown = resourceDirectionDropdown
    self.resourceAlignmentDropdown = resourceAlignmentDropdown
    self.resourceOrientationDropdown = resourceOrientationDropdown
    self.resourceFillDirectionDropdown = resourceFillDirectionDropdown
    self.resourceBorderDropdown = resourceBorderDropdown
    self.resourceBackgroundPicker = resourceBackgroundPicker
    self.resourceBorderLabel = resourceBorderLabel
    self.resourceBackgroundLabel = resourceBackgroundLabel
    self.resourceTextureDropdown = resourceTextureDropdown
    self.resourceFillModeDropdown = resourceFillModeDropdown
    self.resourceFillColorPicker = resourceFillColorPicker
    self.resourceBorderColorPicker = resourceBorderColorPicker
    self.resourceSmoothProgressLabel = resourceSmoothProgressLabel
    self.resourceSmoothProgressSwitch = resourceSmoothProgressSwitch
    self.resourceNameSwitch = resourceNameSwitch
    self.resourceValueSwitch = resourceValueSwitch
    self.resourceFontDropdown = resourceFontDropdown
    self.resourceTextSizeDropdown = resourceTextSizeDropdown
    self.resourceOutlineDropdown = resourceOutlineDropdown
    self.resourceTextColorPicker = resourceTextColorPicker
    self.directionDropdown = directionDropdown
    self.directionLabel = directionLabel
    self.iconAlignmentLabel = iconAlignment.label
    self.iconAlignmentDropdown = iconAlignment.dropdown
    self.rowDirectionDropdown = rowDirectionDropdown
    self.rowDirectionLabel = rowDirectionLabel
    self.iconSizeDropdown = iconSizeDropdown
    self.iconSizeLabel = iconSizeLabel
    self.spacingDropdown = spacingDropdown
    self.spacingLabel = spacingLabel
    self.maxPerLineDropdown = maxPerLineDropdown
    self.maxPerLineLabel = maxPerLineLabel
    self.secondarySizeLabel = secondarySizeLabel
    self.secondarySizeDropdown = secondarySizeDropdown
    self.orientationDropdown = orientationDropdown
    self.orientationLabel = orientationLabel
    self.iconPositionDropdown = iconPositionDropdown
    self.iconPositionLabel = iconPositionLabel
    self.iconGapDropdown = iconGapDropdown
    self.iconGapLabel = iconGapLabel
    self.shapeDropdown = shapeDropdown
    self.shapeLabel = shapeLabel
    self.borderDropdown = borderDropdown
    self.borderLabel = borderLabel
    self.fillColorPicker = fillColorPicker
    self.fillColorLabel = fillColorLabel
    self.zoomLabel = zoomLabel
    self.zoomDropdown = zoomDropdown
    self.iconBackgroundLabel = iconBackgroundLabel
    self.iconBackgroundPicker = iconBackgroundPicker
    self.iconBorderColorLabel = iconBorderColorLabel
    self.iconBorderColorPicker = iconBorderColorPicker
    self.fillTextureLabel = fillTextureLabel
    self.fillTextureDropdown = fillTextureDropdown
    self.trackColorLabel = trackColorLabel
    self.trackColorPicker = trackColorPicker
    self.showDurationIconLabel = showDurationIconLabel
    self.showDurationIconSwitch = showDurationIconSwitch
    self.durationSmoothProgressLabel = durationSmoothProgressLabel
    self.durationSmoothProgressSwitch = durationSmoothProgressSwitch
    self.ringThicknessDropdown = ringThicknessDropdown
    self.ringThicknessLabel = ringThicknessLabel
    self.ringProgressDirectionDropdown =
        ringProgressDirectionDropdown
    self.ringProgressDirectionLabel =
        ringProgressDirectionLabel
    self.ringStartDropdown = ringStartDropdown
    self.ringStartLabel = ringStartLabel
    self.resourceTextureLabel = resourceTextureLabel
    self.resourceFillModeLabel = resourceFillModeLabel
    self.resourceFillColorLabel = resourceFillColorLabel
    self.resourceBorderColorLabel = resourceBorderColorLabel
    self.iconTextTargetMode = iconTextTargetMode
    self.durationTextTargetMode = durationTextTargetMode
    self.textOffsetXSlider = textOffsetXSlider
    self.textOffsetYSlider = textOffsetYSlider
    self.cooldownTextSwitch = cooldownTextSwitch
    self.cooldownTextLabel = cooldownTextLabel
    self.fontDropdown = fontDropdown
    self.textSizeDropdown = textSizeDropdown
    self.outlineDropdown = outlineDropdown
    self.textPositionDropdown = textPositionDropdown
    self.textColorPicker = textColorPicker
    self.nameFormatInput = nameFormatInput
    self.statusText = statusText
    self.monitorHeading = monitorHeading
    self.monitorGroupLabel = monitorGroupLabel
    self.monitorGroupDropdown = monitorGroupDropdown
    self.moveUpButton = moveUpButton
    self.moveDownButton = moveDownButton
    self.removeMonitorButton = removeMonitorButton
    self.monitorGlowButton = monitorGlowButton
    self.deleteGroupButton = deleteGroupButton
    self.addMonitorButton = addMonitorButton
    self.addBuffButton = addBuffButton
    self.glowEditor = glowEditor
    self.glowTitle = glowTitle
    self.glowEnabledLabel = glowEnabledLabel
    self.glowEnabledSwitch = glowEnabledSwitch
    self.glowTriggerLabel = glowTriggerLabel
    self.glowTriggerDropdown = glowTriggerDropdown
    self.glowCombatLabel = glowCombatLabel
    self.glowCombatSwitch = glowCombatSwitch
    self.glowAppearanceLabel = glowAppearanceLabel
    self.glowDone = glowDone
    self.glowAppearanceExpanded = false
    self.dialogBlocker = blocker
    self.switchDialog = switchDialog
    self.cancelDialog = cancelDialog

    local function AppendControls(target, controls)
        for index = 1, #controls do
            target[#target + 1] = controls[index]
        end
    end

    local groupSectionControls = {
        groupHeading,
        groupNameInput,
        groupNameLabel,
        fixedNameBadge,
        groupSummary,
        enableLabel,
        enableSwitch,
        unavailablePreviewLabel,
        unavailablePreviewSwitch,
        restoreButton,
        iconSettingsMode,
        statusText,
        deleteGroupButton,
        addMonitorButton,
        addBuffButton,
    }
    AppendControls(groupSectionControls, self.layoutModeControls)
    AppendControls(groupSectionControls, self.iconLayoutControls)
    AppendControls(groupSectionControls, self.durationLayoutControls)
    AppendControls(groupSectionControls, self.barLayoutControls)
    AppendControls(groupSectionControls, self.iconAppearanceControls)
    AppendControls(groupSectionControls, self.durationAppearanceControls)
    AppendControls(groupSectionControls, self.ringAppearanceControls)
    AppendControls(groupSectionControls, self.iconTextControls)
    AppendControls(groupSectionControls, self.iconTextTargetControls)
    AppendControls(groupSectionControls, self.durationTextControls)
    AppendControls(groupSectionControls, self.durationNameControls)
    AppendControls(groupSectionControls, self.resourceBaseControls)
    AppendControls(groupSectionControls, resourcePresetRows)
    AppendControls(groupSectionControls, self.resourceLayoutControls)
    AppendControls(groupSectionControls, self.resourceAppearanceControls)
    AppendControls(groupSectionControls, self.resourceTextControls)

    local monitorSectionControls = {
        monitorHeading,
        monitorGroupLabel,
        monitorGroupDropdown,
        moveUpButton,
        moveDownButton,
        removeMonitorButton,
        monitorGlowButton,
    }

    local function MoveControls(controls, body, offsetX, offsetY, excluded)
        local seen = {}
        for index = 1, #controls do
            local control = controls[index]
            if control and not seen[control]
                and not (excluded and excluded[control]) then
                seen[control] = true
                local anchors = {}
                local count = control.GetNumPoints and control:GetNumPoints() or 0
                if count == 0 and control.GetPoint then count = 1 end
                for pointIndex = 1, count do
                    local point, relative, relativePoint, x, y =
                        control:GetPoint(pointIndex)
                    if point then
                        if relative == panel or relative == nil then
                            relative = body
                            x = (x or 0) + offsetX
                            y = (y or 0) + offsetY
                        end
                        anchors[#anchors + 1] = {
                            point,
                            relative,
                            relativePoint,
                            x,
                            y,
                        }
                    end
                end
                if control.SetParent then control:SetParent(body) end
                if #anchors > 0 and control.ClearAllPoints then
                    control:ClearAllPoints()
                    for anchorIndex = 1, #anchors do
                        control:SetPoint(unpack(anchors[anchorIndex]))
                    end
                end
            end
        end
    end

    local preservedCoreControls
    if coreAlreadyBuilt then
        -- V2 already owns these controls through its page roots. Reparenting
        -- them while lazily constructing the remaining detail controls makes
        -- the currently visible General page escape its hidden page root for
        -- one presentation pass.
        preservedCoreControls = {
            [groupHeading] = true,
            [groupNameInput] = true,
            [groupNameLabel] = true,
            [fixedNameBadge] = true,
            [groupSummary] = true,
            [enableLabel] = true,
            [enableSwitch] = true,
            [unavailablePreviewLabel] = true,
            [unavailablePreviewSwitch] = true,
            [restoreButton] = true,
        }
    end
    MoveControls(
        groupSectionControls,
        groupBody,
        -16,
        90,
        preservedCoreControls
    )
    MoveControls(monitorSectionControls, monitorBody, -16, 512)
    deleteGroupButton:ClearAllPoints()
    deleteGroupButton:SetPoint("BOTTOMLEFT", groupBody, "BOTTOMLEFT", 0, 42)
    addMonitorButton:ClearAllPoints()
    addMonitorButton:SetPoint("BOTTOMLEFT", groupBody, "BOTTOMLEFT", 0, 0)
    addBuffButton:ClearAllPoints()
    addBuffButton:SetPoint("BOTTOMRIGHT", groupBody, "BOTTOMRIGHT", 0, 0)
    statusText:ClearAllPoints()
    statusText:SetPoint("BOTTOMLEFT", groupBody, "BOTTOMLEFT", 0, 84)
    statusText:SetPoint("BOTTOMRIGHT", groupBody, "BOTTOMRIGHT", 0, 84)
    iconSettingsMode:ClearAllPoints()
    iconSettingsMode:SetPoint("TOPLEFT", groupBody, "TOPLEFT", 0, -8)
    if not coreAlreadyBuilt then
        unavailablePreviewLabel:ClearAllPoints()
        unavailablePreviewLabel:SetPoint(
            "BOTTOMLEFT",
            groupBody,
            "BOTTOMLEFT",
            0,
            126
        )
        unavailablePreviewSwitch:ClearAllPoints()
        unavailablePreviewSwitch:SetPoint(
            "BOTTOMRIGHT",
            groupBody,
            "BOTTOMRIGHT",
            0,
            121
        )
        enableLabel:ClearAllPoints()
        enableLabel:SetPoint("TOPLEFT", groupBody, "TOPLEFT", 0, -52)
        enableSwitch:ClearAllPoints()
        enableSwitch:SetPoint("TOPLEFT", groupBody, "TOPLEFT", 88, -47)
        restoreButton:ClearAllPoints()
        restoreButton:SetPoint("TOPRIGHT", groupBody, "TOPRIGHT", 0, -43)
        groupNameLabel:ClearAllPoints()
        groupNameLabel:SetPoint("TOPLEFT", groupBody, "TOPLEFT", 0, -88)
        groupNameInput:ClearAllPoints()
        groupNameInput:SetPoint("TOPLEFT", groupBody, "TOPLEFT", 0, -106)
        fixedNameBadge:ClearAllPoints()
        fixedNameBadge:SetPoint("RIGHT", groupNameInput, "RIGHT", -8, 0)
        groupSummary:Hide()
        groupHeading:Hide()
    end

    self.inspectorScroll = inspectorScroll
    self.inspectorScrollChild = inspectorScrollChild
    self.inspectorAccordion = inspectorAccordion
    self.groupInspectorBody = groupBody
    self.monitorInspectorBody = monitorBody
    self.groupSectionControls = groupSectionControls
    self.monitorSectionControls = monitorSectionControls

    if UIParent and UIParent.HookScript then
        UIParent:HookScript("OnSizeChanged", function()
            if DesignerUI.active then
                DesignerUI:PositionInspector(false)
                DesignerUI:PositionMonitorPicker()
                DesignerUI:PositionGlowEditor()
            end
        end)
    end
    self._legacyDetailsBuilt = true
    return true
end

function DesignerUI:SelectMonitor(monitorId)
    self:HideMonitorPicker()
    self:HideGlowEditor()
    local monitor, code = Designer:SelectMonitor(monitorId)
    if not monitor then
        self:SetStatus(T("designer.error_select_monitor", "无法选择该监控。"))
        return nil, code
    end
    self.inspectorSection = "monitor"
    self.manualPanel = false
    if self.panel then self.panel:Show() end
    self:Refresh(true, false)
    return monitor
end

function DesignerUI:MoveSelectedMonitor(groupId)
    local monitor, code = Designer:GetSelectedMonitor()
    if not monitor then
        self:SetStatus(T("designer.error_select_monitor", "请先选择一个监控。"))
        return nil, code
    end
    if monitor.groupId == groupId then return monitor end

    monitor, code = Designer:MoveMonitor(monitor.id, groupId)
    if not monitor then
        self:SetMutationError(
            code,
            "designer.error_monitor",
            "无法移动该监控。"
        )
        return nil, code
    end
    self.manualPanel = false
    self:RefreshAfterStructuralMutation(true)
    self:SetStatus(T("designer.status_monitor_moved", "监控已移动到当前分组。"))
    return monitor
end

function DesignerUI:ReorderSelectedMonitor(
    delta,
    targetIndex,
    targetLane,
    placement
)
    local monitor, code = Designer:GetSelectedMonitor()
    if not monitor then
        self:SetStatus(T("designer.error_select_monitor", "请先选择一个监控。"))
        return nil, code
    end
    local profile = Designer:GetProfile()
    local group = profile and profile.groups and profile.groups.items
        and profile.groups.items[monitor.groupId]
    if not group then return nil, "group-not-found" end

    if type(placement) == "table" then
        monitor, code = Designer:ReorderMonitorRelative(
            monitor.id,
            placement
        )
        if not monitor then
            self:SetStatus(T("designer.error_reorder", "无法调整监控顺序。"))
            return nil, code
        end
        self:RefreshAfterStructuralMutation(false)
        self:SetStatus(T("designer.status_monitor_reordered", "监控顺序已更新。"))
        return monitor
    end

    local laneByMonitor = rawget(profile, "_yhudLaneByMonitor") or {}
    local currentLane = laneByMonitor[monitor.id]
    if monitor.contentScope == YHUD.CONTENT_SCOPE_SHARED then
        if currentLane ~= YHUD.CONTENT_LANE_BEFORE then
            currentLane = YHUD.CONTENT_LANE_AFTER
        end
    else
        currentLane = YHUD.CONTENT_LANE_SPEC
    end
    targetLane = targetLane or currentLane
    local laneCount = 0
    local currentLaneIndex
    for index = 1, #group.monitors do
        local candidateId = group.monitors[index]
        local candidate = profile.monitors[candidateId]
        local lane = laneByMonitor[candidateId]
        if candidate and candidate.contentScope == YHUD.CONTENT_SCOPE_SHARED then
            lane = lane == YHUD.CONTENT_LANE_BEFORE
                and YHUD.CONTENT_LANE_BEFORE or YHUD.CONTENT_LANE_AFTER
        else
            lane = YHUD.CONTENT_LANE_SPEC
        end
        if lane == targetLane then
            laneCount = laneCount + 1
            if candidateId == monitor.id then currentLaneIndex = laneCount end
        end
    end
    targetIndex = tonumber(targetIndex)
    if not targetIndex then
        targetIndex = (currentLaneIndex or 1) + (tonumber(delta) or 0)
    end
    local maxIndex = laneCount + (currentLane == targetLane and 0 or 1)
    targetIndex = math.max(1, math.min(math.max(1, maxIndex), targetIndex))
    if targetLane == currentLane and targetIndex == currentLaneIndex then
        return monitor
    end

    monitor, code = Designer:ReorderMonitor(
        monitor.id,
        targetLane,
        targetIndex
    )
    if not monitor then
        self:SetStatus(T("designer.error_reorder", "无法调整监控顺序。"))
        return nil, code
    end
    self:RefreshAfterStructuralMutation(false)
    self:SetStatus(T("designer.status_monitor_reordered", "监控顺序已更新。"))
    return monitor
end

function DesignerUI:RemoveSelectedMonitor(allSpecializations)
    local monitor, code = Designer:GetSelectedMonitor()
    if not monitor then
        self:SetStatus(T("designer.error_select_monitor", "请先选择一个监控。"))
        return nil, code
    end
    local removed
    self:HideGlowEditor()
    removed, code = Designer:RemoveMonitor(monitor.id, allSpecializations)
    if not removed then
        self:SetMutationError(
            code,
            "designer.error_remove",
            "无法移除该监控。"
        )
        return nil, code
    end
    self.inspectorSection = "group"
    self:RefreshAfterStructuralMutation(false)
    self:SetStatus(T("designer.status_monitor_removed", "监控已移除。"))
    return true
end

function DesignerUI:Refresh(animate, rebuildPreview)
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    if not (session and profile) then return false end
    local groups = profile.groups and profile.groups.items or {}
    local group = groups[session.selectedGroupId]
    if not group then return false end
    local monitor = session.selectedMonitorId
        and profile.monitors[session.selectedMonitorId]
    local resourceClassFile
    local resourceSpecID
    local resourceFormKey
    local resourcePresets
    if group.layout == "resource" and ResourceCatalog then
        resourceClassFile, resourceSpecID, resourceFormKey =
            Designer:GetResourcePreviewContext()
        resourcePresets = resourceFormKey
            and ResourceCatalog:GetFormPresets(
                YHUD:GetResourceProfile(profile, session.selectedGroupId),
                resourceClassFile,
                resourceSpecID,
                resourceFormKey
            )
            or ResourceCatalog:GetPresets(
                YHUD:GetResourceProfile(profile, session.selectedGroupId),
                resourceClassFile,
                resourceSpecID
            )
    end

    if self.profileDropdown and self.profileDropdown.SetValue then
        if not self.profileDropdown.GetValue
            or self.profileDropdown:GetValue() ~= session.setId then
            self.profileDropdown:SetValue(session.setId, true)
        end
    end
    if self.groupDropdown and self.groupDropdown.SetValue then
        self.groupDropdown:SetValue(session.selectedGroupId, true)
    end
    if self.inspectorAccordion then
        local monitorVisible = monitor ~= nil and group.layout ~= "resource"
        self.inspectorAccordion:SetSectionTitle(
            "group",
            T("designer.group_settings", "组设置") .. " · " .. GroupName(group)
        )
        self.inspectorAccordion:SetSectionTitle(
            "monitor",
            monitor and MonitorName(profile, monitor)
                or T("designer.monitor_settings", "单个监控")
        )
        self.inspectorAccordion:SetSectionContentHeight("group", 500)
        self.inspectorAccordion:SetSectionContentHeight("monitor", 184)
        self.inspectorAccordion:SetSectionVisible("monitor", monitorVisible)
        if monitorVisible then
            if self.inspectorSection ~= "group"
                and self.inspectorSection ~= "monitor"
                and self.inspectorSection ~= nil then
                self.inspectorSection = "monitor"
            end
        elseif self.inspectorSection == "monitor" then
            self.inspectorSection = "group"
        end
        self.inspectorAccordion:SetActive(self.inspectorSection, true)
    end
    self.groupHeading:Hide()
    self.groupNameInput:SetValue(GroupName(group), true)
    self.groupNameInput:Show()
    self.groupNameLabel:Show()
    if self.groupNameInput.SetDisabled then
        self.groupNameInput:SetDisabled(group.fixedName == true)
    end
    SetShown(self.fixedNameBadge, group.fixedName == true)
    if self.panelTitle then
        self.panelTitle:SetText(GroupName(group))
    end
    if self.inspectorTypeBadge then
        self.inspectorTypeBadge:SetText(GroupTypeName(group))
    end
    local groupItemCount = CountList(group.monitors)
    if resourcePresets then
        groupItemCount = 0
        for index = 1, #resourcePresets do
            if resourcePresets[index].enabled then
                groupItemCount = groupItemCount + 1
            end
        end
    end
    self.groupSummary:SetText(string.format(
        group.layout == "resource"
            and T("designer.resource_summary", "%s · %d 个资源")
            or T("designer.group_summary", "%s · %d 个监控"),
        GroupTypeName(group),
        groupItemCount
    ))
    self.enableSwitch:SetValue(group.enabled == true, true)
    if self.enableSwitch.SetDisabled then
        self.enableSwitch:SetDisabled(group.fixedEnabled == true)
    end
    self.unavailablePreviewSwitch:SetValue(
        group.showUnavailablePreview ~= false,
        true
    )
    SetShown(self.unavailablePreviewLabel, group.layout ~= "resource")
    SetShown(self.unavailablePreviewSwitch, group.layout ~= "resource")
    if YHUD.DEFAULT_CATEGORY_BY_GROUP[session.selectedGroupId] then
        self.restoreButton:Show()
    else
        self.restoreButton:Hide()
    end
    local showGroupSettings = MONITOR_LAYOUTS[group.layout] == true
        or group.layout == "resource"
    self.settingsLayoutType = group.layout
    self.durationTextTarget = self.durationTextTarget or "cooldown"
    if group.layout == "icons"
        and self.durationTextTarget == "name" then
        self.durationTextTarget = "cooldown"
    end
    SetShown(self.iconSettingsMode, showGroupSettings)
    if showGroupSettings then
        local groupLayout
        local groupStyle
        if group.layout == "resource" then
            groupLayout = YHUD:GetResourceGroupLayout(
                profile,
                session.selectedGroupId
            )
            groupStyle = YHUD:GetResourceGroupStyle(
                profile,
                session.selectedGroupId
            )
            resourcePresets = ProjectResourceDisplayOrder(
                profile,
                session.selectedGroupId,
                resourcePresets
            )
            self.iconSettingsMode:SetValue(
                self.iconSettingsPage or "layout",
                true
            )
            self.resourceClassDropdown:SetValue(
                resourceClassFile,
                true
            )
            self.resourceSpecDropdown:SetValue(
                resourceSpecID,
                true
            )
            SetShown(self.resourceFormLabel, resourceFormKey ~= nil)
            SetShown(self.resourceFormDropdown, resourceFormKey ~= nil)
            SetShown(self.resourceOverrideStatus, resourceFormKey ~= nil)
            SetShown(self.resourceResetFormButton, resourceFormKey ~= nil)
            SetShown(self.resourceFormHelp, resourceFormKey ~= nil)
            if resourceFormKey then
                self.resourceFormDropdown:SetValue(resourceFormKey, true)
                local customized = ResourceCatalog:IsFormCustomized(
                    profile,
                    resourceClassFile,
                    resourceSpecID,
                    resourceFormKey
                )
                self.resourceOverrideStatus:SetText(customized
                    and T("designer.resource.customized", "已自定义")
                    or T("designer.resource.default", "默认矩阵"))
                self.resourceResetFormButton:SetDisabled(not customized)
                self.resourcePresetLabel:SetText(T(
                    "designer.resource.form_presets",
                    "形态资源"
                ))
            else
                self.resourcePresetLabel:SetText(T(
                    "designer.resource.presets",
                    "显示资源"
                ))
            end
            for index = 1, #self.resourcePresetRows do
                local row = self.resourcePresetRows[index]
                local preset = resourcePresets and resourcePresets[index]
                if preset then
                    row.resourceId = preset.id
                    row.label:SetText(T(preset.nameKey, preset.id))
                    local effectiveStyle = YHUD:GetEffectiveResourceStyle(
                        profile,
                        session.selectedGroupId,
                        preset.id,
                        resourceSpecID
                    )
                    local color = effectiveStyle.fillColor or preset.color
                    row.swatch:SetColorTexture(
                        color.r or color[1] or 1,
                        color.g or color[2] or 1,
                        color.b or color[3] or 1,
                        color.a == nil
                            and (color[4] == nil and 1 or color[4])
                            or color.a
                    )
                    row.toggle:SetValue(preset.enabled == true, true)
                    if row.moveUp.SetDisabled then
                        row.moveUp:SetDisabled(index == 1)
                        row.moveDown:SetDisabled(index == #resourcePresets)
                    end
                    row:Show()
                else
                    row.resourceId = nil
                    row:Hide()
                end
            end
            self.resourceWidthDropdown:SetValue(groupLayout.width, true)
            self.resourceHeightDropdown:SetValue(groupLayout.height, true)
            self.resourceSpacingDropdown:SetValue(groupLayout.spacing, true)
            self.resourceDirectionDropdown:SetValue(
                groupLayout.direction,
                true
            )
            self.resourceAlignmentDropdown:SetValue(
                groupLayout.alignment,
                true
            )
            self.resourceOrientationDropdown:SetValue(
                groupLayout.orientation,
                true
            )
            self.resourceFillDirectionDropdown:SetValue(
                groupLayout.fillDirection,
                true
            )
            self.resourceBorderDropdown:SetValue(groupStyle.border, true)
            self.resourceBackgroundPicker:SetValue(
                groupStyle.backgroundColor,
                true
            )
            self.resourceTextureDropdown:SetValue(
                groupStyle.fillTexture,
                true
            )
            self.resourceFillModeDropdown:SetValue(
                groupStyle.fillColorMode,
                true
            )
            self.resourceFillColorPicker:SetValue(
                groupStyle.fillColor,
                true
            )
            self.resourceBorderColorPicker:SetValue(
                groupStyle.borderColor,
                true
            )
            self.resourceSmoothProgressSwitch:SetValue(
                groupStyle.smoothProgress == true,
                true
            )
            self.resourceNameSwitch:SetValue(
                groupStyle.nameText == true,
                true
            )
            self.resourceValueSwitch:SetValue(
                groupStyle.valueText == true,
                true
            )
            self.resourceFontDropdown:SetValue(
                groupStyle.textFont,
                true
            )
            self.resourceTextSizeDropdown:SetValue(
                groupStyle.textSize,
                true
            )
            self.resourceOutlineDropdown:SetValue(
                groupStyle.textOutline,
                true
            )
            self.resourceTextColorPicker:SetValue(
                groupStyle.textColor,
                true
            )
        elseif group.layout == "icons" then
            groupLayout = YHUD:GetIconGroupLayout(
                profile,
                session.selectedGroupId
            )
            groupStyle = YHUD:GetIconGroupStyle(
                profile,
                session.selectedGroupId
            )
            self.iconSizeLabel:SetText(
                T("designer.layout.icon_size", "图标尺寸")
            )
        else
            groupLayout = YHUD:GetDurationGroupLayout(
                profile,
                session.selectedGroupId,
                group.layout
            )
            groupStyle = YHUD:GetDurationGroupStyle(
                profile,
                session.selectedGroupId
            )
            self.iconSizeLabel:SetText(group.layout == "rings"
                and T("designer.layout.diameter", "圆环直径")
                or T("designer.layout.width", "进度条宽度"))
            self.secondarySizeLabel:SetText(
                T("designer.layout.height", "进度条高度")
            )
        end
        if group.layout ~= "resource" then
            self.directionLabel:SetText(group.layout == "icons"
                and T("designer.layout.wrap_direction", "换行方向")
                or T("designer.layout.wrap_mode", "对齐与换行"))
            self.iconSettingsMode:SetValue(
                self.iconSettingsPage or "layout",
                true
            )
            self.directionDropdown:SetValue(
                group.layout == "icons" and groupLayout.wrapDirection
                    or group.layout == "rings"
                    and (groupLayout.direction == "outward"
                        or groupLayout.direction == "inward")
                    and groupLayout.direction
                    or (tostring(groupLayout.alignment)
                        .. "-"
                        .. tostring(groupLayout.wrapDirection)),
                true
            )
            if group.layout == "icons" then
                self:RefreshIconAlignment(groupLayout)
                self.rowDirectionDropdown:SetValue(
                    groupLayout.rowDirection,
                    true
                )
            end
            self.iconSizeDropdown:SetValue(
                group.layout == "icons" and groupLayout.iconSize
                    or (group.layout == "rings" and groupLayout.diameter
                        or groupLayout.width),
                true
            )
            self.spacingDropdown:SetValue(groupLayout.columnSpacing, true)
            self.maxPerLineDropdown:SetValue(groupLayout.maxPerLine, true)
            if group.layout ~= "icons" then
                if group.layout == "bars" then
                    self.secondarySizeDropdown:SetValue(
                        groupLayout.height,
                        true
                    )
                end
                if group.layout == "bars" then
                    self.orientationDropdown:SetValue(
                        groupLayout.orientation .. "-"
                            .. (groupLayout.fillDirection or "forward"),
                        true
                    )
                    self.iconPositionDropdown:SetValue(
                        groupLayout.iconPosition,
                        true
                    )
                    self.iconGapDropdown:SetValue(
                        groupLayout.iconGap,
                        true
                    )
                end
                self.fillColorPicker:SetValue(groupStyle.fillColor, true)
                self.showDurationIconSwitch:SetValue(
                    groupStyle.showIcon ~= false,
                    true
                )
                self.durationSmoothProgressSwitch:SetValue(
                    groupStyle.smoothProgress == true,
                    true
                )
                self.fillTextureDropdown:SetValue(
                    groupStyle.fillTexture,
                    true
                )
                self.trackColorPicker:SetValue(
                    group.layout == "rings"
                        and groupStyle.ringTrackColor
                        or groupStyle.trackColor,
                    true
                )
                if group.layout == "rings" then
                    self.ringThicknessDropdown:SetValue(
                        groupStyle.ringThickness,
                        true
                    )
                    self.ringProgressDirectionDropdown:SetValue(
                        groupStyle.ringDirection,
                        true
                    )
                    self.ringStartDropdown:SetValue(
                        groupStyle.ringStart,
                        true
                    )
                end
                self.durationTextTargetMode:SetValue(
                    self.durationTextTarget,
                    true
                )
                self.nameFormatInput:SetValue(
                    groupStyle.nameTextFormat,
                    true
                )
            end
            self.shapeDropdown:SetValue(groupStyle.iconShape, true)
            self.borderDropdown:SetValue(groupStyle.iconBorder, true)
            self.zoomDropdown:SetValue(groupStyle.iconZoom, true)
            self.iconBackgroundPicker:SetValue(
                groupStyle.iconBackgroundColor,
                true
            )
            self.iconBorderColorPicker:SetValue(
                groupStyle.iconBorderColor,
                true
            )
            if group.layout == "icons" then
                self.iconTextTargetMode:SetValue(
                    self.durationTextTarget,
                    true
                )
            end
            local textPrefix = self.durationTextTarget == "count"
                and "countText"
                or (group.layout ~= "icons"
                    and self.durationTextTarget == "name"
                    and "nameText"
                    or (group.layout ~= "icons"
                        and "timeText" or "cooldownText"))
            self.cooldownTextLabel:SetText(
                textPrefix == "nameText"
                    and T("designer.text.name_enabled", "显示名称")
                    or (textPrefix == "countText"
                        and T(
                            "designer.text.count_enabled",
                            "显示层数/充能"
                        )
                        or (textPrefix == "timeText"
                            and T(
                                "designer.text.duration_enabled",
                                "持续时间"
                            )
                            or T("designer.text.enabled", "冷却时间")))
            )
            self.cooldownTextSwitch:SetValue(
                groupStyle[textPrefix] == true,
                true
            )
            self.fontDropdown:SetValue(
                groupStyle[textPrefix .. "Font"],
                true
            )
            self.textSizeDropdown:SetValue(
                groupStyle[textPrefix .. "Size"],
                true
            )
            self.outlineDropdown:SetValue(
                groupStyle[textPrefix .. "Outline"],
                true
            )
            self.textPositionDropdown:SetValue(
                groupStyle[
                    textPrefix
                        .. (group.layout == "bars" and "Anchor" or "Position")
                ],
                true
            )
            self.textColorPicker:SetValue(
                groupStyle[textPrefix .. "Color"],
                true
            )
            self.textOffsetXSlider:SetValue(
                groupStyle[textPrefix .. "OffsetX"] or 0,
                true
            )
            self.textOffsetYSlider:SetValue(
                groupStyle[textPrefix .. "OffsetY"] or 0,
                true
            )
        end
    end
    self:ShowIconSettingsPage(
        self.iconSettingsPage or "layout",
        showGroupSettings
    )
    if group.layout == "rings" then
        self.secondarySizeLabel:Hide()
        self.secondarySizeDropdown:Hide()
    end
    local appearanceTop = group.layout == "bars" and -332 or -270
    local function Place(control, point, relativePoint, x, y)
        if not control then return end
        control:ClearAllPoints()
        control:SetPoint(
            point or "TOPLEFT",
            self.groupInspectorBody,
            relativePoint or point or "TOPLEFT",
            x or 0,
            y or 0
        )
    end
    Place(self.shapeLabel, "TOPLEFT", "TOPLEFT", 0, appearanceTop)
    Place(self.shapeDropdown, "TOPLEFT", "TOPLEFT", 0, appearanceTop - 18)
    self.shapeDropdown:SetWidth(328)
    Place(self.borderLabel, "TOPLEFT", "TOPLEFT", 0, appearanceTop - 62)
    Place(self.borderDropdown, "TOPLEFT", "TOPLEFT", 0, appearanceTop - 80)
    self.borderDropdown:SetWidth(160)
    Place(self.zoomLabel, "TOPLEFT", "TOPLEFT", 168, appearanceTop - 62)
    Place(self.zoomDropdown, "TOPLEFT", "TOPLEFT", 168, appearanceTop - 80)
    self.zoomDropdown:SetWidth(160)
    Place(
        self.iconBackgroundLabel,
        "TOPLEFT",
        "TOPLEFT",
        0,
        appearanceTop - 124
    )
    Place(
        self.iconBackgroundPicker,
        "TOPLEFT",
        "TOPLEFT",
        0,
        appearanceTop - 142
    )
    Place(
        self.iconBorderColorLabel,
        "TOPLEFT",
        "TOPLEFT",
        168,
        appearanceTop - 124
    )
    Place(
        self.iconBorderColorPicker,
        "TOPLEFT",
        "TOPLEFT",
        168,
        appearanceTop - 142
    )
    Place(
        self.showDurationIconLabel,
        "TOPLEFT",
        "TOPLEFT",
        0,
        appearanceTop - 186
    )
    Place(
        self.showDurationIconSwitch,
        "TOPLEFT",
        "TOPLEFT",
        88,
        appearanceTop - 181
    )
    Place(self.fillColorLabel, "TOPLEFT", "TOPLEFT", 0, appearanceTop - 230)
    Place(self.fillColorPicker, "TOPLEFT", "TOPLEFT", 0, appearanceTop - 248)
    Place(
        self.fillTextureLabel,
        "TOPLEFT",
        "TOPLEFT",
        0,
        appearanceTop - 292
    )
    Place(
        self.fillTextureDropdown,
        "TOPLEFT",
        "TOPLEFT",
        0,
        appearanceTop - 310
    )
    Place(
        self.trackColorLabel,
        "TOPLEFT",
        "TOPLEFT",
        168,
        appearanceTop - 292
    )
    Place(
        self.trackColorPicker,
        "TOPLEFT",
        "TOPLEFT",
        168,
        appearanceTop - 310
    )
    Place(
        self.ringThicknessLabel,
        "TOPLEFT",
        "TOPLEFT",
        0,
        appearanceTop - 354
    )
    Place(
        self.ringThicknessDropdown,
        "TOPLEFT",
        "TOPLEFT",
        0,
        appearanceTop - 372
    )
    Place(
        self.ringProgressDirectionLabel,
        "TOPLEFT",
        "TOPLEFT",
        106,
        appearanceTop - 354
    )
    Place(
        self.ringProgressDirectionDropdown,
        "TOPLEFT",
        "TOPLEFT",
        106,
        appearanceTop - 372
    )
    Place(
        self.ringStartLabel,
        "TOPLEFT",
        "TOPLEFT",
        220,
        appearanceTop - 354
    )
    Place(
        self.ringStartDropdown,
        "TOPLEFT",
        "TOPLEFT",
        220,
        appearanceTop - 372
    )
    local resourceAppearanceTop = -510
    Place(
        self.resourceBorderLabel,
        "TOPLEFT",
        "TOPLEFT",
        0,
        resourceAppearanceTop
    )
    Place(
        self.resourceBorderDropdown,
        "TOPLEFT",
        "TOPLEFT",
        0,
        resourceAppearanceTop - 18
    )
    Place(
        self.resourceBackgroundLabel,
        "TOPLEFT",
        "TOPLEFT",
        168,
        resourceAppearanceTop
    )
    Place(
        self.resourceBackgroundPicker,
        "TOPLEFT",
        "TOPLEFT",
        168,
        resourceAppearanceTop - 18
    )
    Place(
        self.resourceTextureLabel,
        "TOPLEFT",
        "TOPLEFT",
        0,
        resourceAppearanceTop - 62
    )
    Place(
        self.resourceTextureDropdown,
        "TOPLEFT",
        "TOPLEFT",
        0,
        resourceAppearanceTop - 80
    )
    Place(
        self.resourceFillModeLabel,
        "TOPLEFT",
        "TOPLEFT",
        168,
        resourceAppearanceTop - 62
    )
    Place(
        self.resourceFillModeDropdown,
        "TOPLEFT",
        "TOPLEFT",
        168,
        resourceAppearanceTop - 80
    )
    Place(
        self.resourceFillColorLabel,
        "TOPLEFT",
        "TOPLEFT",
        0,
        resourceAppearanceTop - 124
    )
    Place(
        self.resourceFillColorPicker,
        "TOPLEFT",
        "TOPLEFT",
        0,
        resourceAppearanceTop - 142
    )
    Place(
        self.resourceBorderColorLabel,
        "TOPLEFT",
        "TOPLEFT",
        168,
        resourceAppearanceTop - 124
    )
    Place(
        self.resourceBorderColorPicker,
        "TOPLEFT",
        "TOPLEFT",
        168,
        resourceAppearanceTop - 142
    )
    local page = self.iconSettingsPage or "layout"
    local contentHeight
    if page == "text" then
        contentHeight = group.layout == "resource" and 620 or 560
    elseif group.layout == "resource" then
        contentHeight = 820
    elseif group.layout == "bars" then
        contentHeight = 740
    elseif group.layout == "rings" then
        contentHeight = 770
    else
        contentHeight = 560
    end
    self.groupInspectorBody:SetHeight(contentHeight)
    self.inspectorAccordion:SetSectionContentHeight(
        "group",
        contentHeight
    )
    local isResourceGroup = group.layout == "resource"
    SetShown(self.statusText, not isResourceGroup)
    if group.fixedDelete == true then
        self.deleteGroupButton:Hide()
    else
        self.deleteGroupButton:Show()
        self.deleteGroupButton:SetDisabled(CountList(group.monitors) > 0)
    end
    if CanAddMonitor(group) then
        local capabilities = YHUD:GetGroupAddCapabilities(group)
        SetShown(self.addMonitorButton, capabilities.cooldown)
        SetShown(self.addBuffButton, capabilities.buff)
    else
        self.addMonitorButton:Hide()
        self.addBuffButton:Hide()
        self:HideMonitorPicker()
    end
    if isResourceGroup then
        self.monitorHeading:Hide()
        self.monitorGroupLabel:Hide()
        self.monitorGroupDropdown:Hide()
        self.moveUpButton:Hide()
        self.moveDownButton:Hide()
        self.removeMonitorButton:Hide()
        self.monitorGlowButton:Hide()
    elseif monitor then
        self.monitorHeading:SetText(MonitorName(profile, monitor))
        self.monitorHeading:Show()
        self.monitorGroupLabel:Show()
        self.monitorGroupDropdown:Show()
        self.monitorGroupDropdown:SetValue(monitor.groupId, true)
        self.moveUpButton:Show()
        self.moveDownButton:Show()
        self.removeMonitorButton:Show()
        if Glow and Glow.SupportsMonitor
            and Glow:SupportsMonitor(profile, monitor) then
            self.monitorGlowButton:SetText(
                type(monitor.glow) == "table"
                    and type(monitor.glow.rules) == "table"
                    and #monitor.glow.rules > 0
                    and T(
                        "designer.glow.open_enabled",
                        "发光设置 · 已启用"
                    )
                    or T("designer.glow.open", "发光设置")
            )
            self.monitorGlowButton:Show()
        else
            self.monitorGlowButton:Hide()
            if self.glowEditor and self.glowEditor:IsShown() then
                self:HideGlowEditor()
            end
        end
        local laneByMonitor = rawget(profile, "_yhudLaneByMonitor") or {}
        local monitorLane = laneByMonitor[monitor.id]
        if monitor.contentScope == YHUD.CONTENT_SCOPE_SHARED then
            monitorLane = monitorLane == YHUD.CONTENT_LANE_BEFORE
                and YHUD.CONTENT_LANE_BEFORE or YHUD.CONTENT_LANE_AFTER
        else
            monitorLane = YHUD.CONTENT_LANE_SPEC
        end
        local laneIndex = 0
        local laneCount = 0
        for index = 1, #group.monitors do
            local candidateId = group.monitors[index]
            local candidate = profile.monitors[candidateId]
            local candidateLane = laneByMonitor[candidateId]
            if candidate
                and candidate.contentScope == YHUD.CONTENT_SCOPE_SHARED then
                candidateLane = candidateLane == YHUD.CONTENT_LANE_BEFORE
                    and YHUD.CONTENT_LANE_BEFORE or YHUD.CONTENT_LANE_AFTER
            else
                candidateLane = YHUD.CONTENT_LANE_SPEC
            end
            if candidateLane == monitorLane then
                laneCount = laneCount + 1
                if candidateId == monitor.id then laneIndex = laneCount end
            end
        end
        local atFirst = laneIndex <= 1
        local atLast = laneIndex >= laneCount
        self.moveUpButton:SetDisabled(atFirst)
        self.moveDownButton:SetDisabled(atLast)
    else
        self.monitorHeading:SetText(
            T("designer.monitor_none", "选择一个监控")
        )
        self.monitorHeading:Show()
        self.monitorGroupLabel:Hide()
        self.monitorGroupDropdown:Hide()
        self.moveUpButton:Hide()
        self.moveDownButton:Hide()
        self.removeMonitorButton:Hide()
        self.monitorGlowButton:Hide()
        if self.glowEditor and self.glowEditor:IsShown() then
            self:HideGlowEditor()
        end
    end
    self:SetStatus(self:IsSessionDirty()
        and T("designer.status_dirty", "当前配置有未保存修改。")
        or T("designer.status_clean", "当前配置已保存。"))

    if rebuildPreview == false then
        self:RefreshSelectionPreview()
    else
        self:ApplyPreview()
    end
    self:PositionInspector(animate)
    self:PositionMonitorPicker()
    self:RefreshGlowEditor(false)
    self:PositionGlowEditor()
    return true
end

function DesignerUI:RenameSelectedGroup(name)
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local group = session and profile and profile.groups
        and profile.groups.items[session.selectedGroupId]
    if not group then return false end
    if GroupName(group) == name then return true end

    local renamed, code =
        Designer:RenameGroup(session.selectedGroupId, name)
    if not renamed then
        self:SetStatus(code == "fixed-name"
            and T("designer.error_fixed_name", "默认分组不能改名。")
            or T("designer.error_rename_group", "无法修改分组名称。"))
        self:Refresh(false)
        return false
    end
    self:Refresh(false)
    local LayoutBridge = YHUD.LayoutBridge
    if LayoutBridge and LayoutBridge.Sync then
        LayoutBridge:Sync(profile)
    end
    self:SetStatus(T("designer.status_group_renamed", "分组名称已更新。"))
    return true
end

function DesignerUI:DeleteSelectedGroup()
    self:HideMonitorPicker()
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local group = session and profile and profile.groups
        and profile.groups.items[session.selectedGroupId]
    if not group then return false end
    local message
    if CountList(group.monitors) > 0 then
        message = T("designer.error_group_not_empty", "请先移除或移动分组中的监控。")
    else
        local deleted, code = Designer:DeleteGroup(session.selectedGroupId)
        if not deleted then
            if code == "fixed-delete" then
                message = T("designer.error_fixed_delete", "默认分组不能删除。")
            elseif code == "group-not-empty" and group.layout == "resource" then
                message = T(
                    "designer.error_resource_group_not_empty",
                    "请先在监控页关闭该分组在所有职业、专精和形态中启用的资源，再删除分组。"
                )
            elseif code == "group-not-empty" then
                message = T(
                    "designer.error_group_not_empty",
                    "请先移除或移动所有职业专精中的监控。"
                )
            else
                message = T("designer.error_delete_group", "无法删除分组。")
            end
        end
    end
    if message then
        self:SetStatus(message)
        if S and S.ShowConfirmPopup then
            S:ShowConfirmPopup(message, nil, {
                owner = self,
                ownerFrame = self.panel,
                dismissWithOwner = true,
                titleText = T("designer.error_delete_group", "无法删除分组。"),
                buttons = { { text = TC("common.confirm", "确定") } },
            })
        else
            Print(message)
        end
        return false
    end
    self.manualPanel = false
    self.inspectorSection = "group"
    self:ApplyPreview()
    self:CloseInspector()
    self:SetStatus(T("designer.status_group_deleted", "分组已删除。"))
    return true
end

function DesignerUI:SelectGroup(groupId)
    self:HideMonitorPicker()
    self:HideGlowEditor()
    local group, code = Designer:SelectGroup(groupId)
    if not group then
        self:SetStatus(T("designer.error_group", "无法选择分组：") .. tostring(code))
        return false
    end
    self.inspectorSection = "group"
    self.manualPanel = false
    if self.panel then self.panel:Show() end
    return self:Refresh(true, false)
end

function DesignerUI:SetSelectedGroupEnabled(enabled)
    local session = Designer:GetSession()
    if not session then return false end
    local ok, code = Designer:SetGroupEnabled(session.selectedGroupId, enabled)
    if not ok then
        self:Refresh(false)
        if code == "fixed-enabled" then
            self:SetStatus(T(
                "designer.error_fixed_enabled",
                "重要技能分组不能停用。"
            ))
        else
            self:SetMutationError(
                code,
                "designer.error_update",
                "无法修改分组。"
            )
        end
        return false
    end
    self:Refresh(false)
    return true
end

function DesignerUI:SetSelectedGroupUnavailablePreview(enabled)
    local session = Designer:GetSession()
    if not session then return false end
    local ok, code = Designer:SetGroupUnavailablePreview(
        session.selectedGroupId,
        enabled
    )
    if not ok then
        self:SetStatus(
            T("designer.error_update", "无法修改分组。")
                .. (code and (" " .. tostring(code)) or "")
        )
        self:Refresh(false)
        return false
    end
    self:Refresh(false)
    return true
end

function DesignerUI:SetResourcePreviewClass(classFile)
    local resolved, specID = Designer:SetResourcePreviewClass(classFile)
    if not resolved then
        self:SetStatus(T(
            "designer.error_resource_class",
            "无法切换资源预览职业。"
        ))
        return false
    end
    self.resourceStyleResourceId = nil
    self.manualPanel = false
    self:Refresh(true)
    return resolved, specID
end

function DesignerUI:SetResourcePreviewSpec(specID)
    local spec = Designer:SetResourcePreviewSpec(specID)
    if not spec then
        self:SetStatus(T(
            "designer.error_resource_spec",
            "无法切换资源预览专精。"
        ))
        return false
    end
    self.resourceStyleResourceId = nil
    self:Refresh(false)
    return spec
end

function DesignerUI:SetResourcePreviewForm(formKey)
    local resolved = Designer:SetResourcePreviewForm(formKey)
    if not resolved then
        self:SetStatus(T(
            "designer.error_resource_form",
            "无法切换资源预览形态。"
        ))
        return false
    end
    self.resourceStyleResourceId = nil
    self:Refresh(false)
    return resolved
end

function DesignerUI:ResetResourceFormOverride()
    local reset, code = Designer:ResetResourceFormOverride()
    if not reset then
        self:SetStatus(T(
            "designer.error_resource_form_reset",
            "无法恢复形态资源默认值。"
        ) .. (code and (" " .. tostring(code)) or ""))
        return false
    end
    self:Refresh(false)
    self:SetStatus(T(
        "designer.status_resource_form_reset",
        "已恢复默认形态资源。"
    ))
    return true
end

function DesignerUI:SetResourcePresetEnabled(resourceId, enabled)
    local changed, code =
        Designer:SetResourcePresetEnabled(resourceId, enabled)
    if not changed then
        self:SetStatus(T(
            "designer.error_resource_preset",
            "无法修改专精资源。"
        ) .. (code and (" " .. tostring(code)) or ""))
        self:Refresh(false)
        return false
    end
    self:Refresh(false)
    return true
end

function DesignerUI:ReorderResourcePreset(
    resourceId,
    delta,
    targetIndex,
    enabledOnly
)
    if targetIndex == nil then
        local profile = Designer:GetProfile()
        local session = Designer:GetSession()
        local classFile, specID, formKey =
            Designer:GetResourcePreviewContext()
        local presets = {}
        if profile then
            presets = formKey and ResourceCatalog:GetFormPresets(
                YHUD:GetResourceProfile(profile, session.selectedGroupId),
                classFile,
                specID,
                formKey
            ) or ResourceCatalog:GetPresets(YHUD:GetResourceProfile(profile, session.selectedGroupId), classFile, specID)
        end
        local projected, reversed = ProjectResourceDisplayOrder(
            profile,
            session and session.selectedGroupId,
            presets
        )
        for index = 1, #projected do
            if projected[index].id == resourceId then
                local projectedTarget = math.max(
                    1,
                    math.min(#projected, index + (tonumber(delta) or 0))
                )
                targetIndex = reversed
                    and (#projected - projectedTarget + 1)
                    or projectedTarget
                break
            end
        end
    end
    local order, code = Designer:MoveResourcePreset(
        resourceId,
        targetIndex,
        enabledOnly
    )
    if not order then
        self:SetStatus(T(
            "designer.error_resource_reorder",
            "无法调整资源条顺序。"
        ) .. (code and (" " .. tostring(code)) or ""))
        self:Refresh(false)
        return nil, code
    end
    self:Refresh(false)
    self:SetStatus(T(
        "designer.status_resource_reordered",
        "资源条顺序已更新。"
    ))
    return order
end

function DesignerUI:SetSelectedGroupResourceLayout(field, value)
    local session = Designer:GetSession()
    if not session then return false end
    local layout, code = Designer:SetGroupResourceLayout(
        session.selectedGroupId,
        {
            [field] = value,
        }
    )
    if not layout then
        self:SetStatus(T(
            "designer.error_resource_layout",
            "无法修改资源条布局。"
        ) .. (code and (" " .. tostring(code)) or ""))
        self:Refresh(false)
        return false
    end
    self:Refresh(false)
    return layout
end

function DesignerUI:SetSelectedGroupLayoutMode(value)
    local session = Designer:GetSession()
    if not session then return false end
    local changed, code = Designer:SetGroupLayoutMode(
        session.selectedGroupId,
        value
    )
    if not changed then
        self:SetStatus(
            T("designer.error_layout_update", "无法修改分组布局。")
                .. (code and (" " .. tostring(code)) or "")
        )
        self:Refresh(false, false)
        return false
    end
    self:ApplyPreview()
    self:Refresh(false, false)
    self:SetStatus(T("designer.status_layout_updated", "分组布局已更新。"))
    return true
end

function DesignerUI:SetSelectedGroupDisplayLayer(value)
    local session = Designer:GetSession()
    if not session then return false end
    local changed, code = Designer:SetGroupDisplayLayer(
        session.selectedGroupId,
        value
    )
    if not changed then
        self:SetStatus(
            T("designer.error_display_layer_update", "无法修改分组显示层级。")
                .. (code and (" " .. tostring(code)) or "")
        )
        self:Refresh(false, false)
        return false
    end
    self:ApplyPreview()
    self:Refresh(false, false)
    self:SetStatus(T(
        "designer.status_display_layer_updated",
        "分组显示层级已更新。"
    ))
    return true
end

function DesignerUI:SetSelectedGroupResourceStyle(field, value)
    local session = Designer:GetSession()
    if not session then return false end
    local patch = {
        [field] = value,
    }
    if field == "fillColor" then
        patch.fillColorMode = "custom"
    end
    local style, code = Designer:SetGroupResourceStyle(
        session.selectedGroupId,
        patch
    )
    if not style then
        self:SetStatus(T(
            "designer.error_resource_style",
            "无法修改资源条外观。"
        ) .. (code and (" " .. tostring(code)) or ""))
        self:Refresh(false)
        return false
    end
    self:Refresh(false)
    return style
end

function DesignerUI:SetSelectedGroupLayout(field, value)
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local group = session and profile and profile.groups
        and profile.groups.items[session.selectedGroupId]
    if not group then return false end
    if group.layout == "icons" then
        return self:SetSelectedGroupIconLayout(field, value)
    end
    return self:SetSelectedGroupDurationLayout(field, value)
end

function DesignerUI:SetSelectedGroupWrapMode(value)
    if type(value) ~= "string" then return false end
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local group = session and profile and profile.groups
        and profile.groups.items[session.selectedGroupId]
    if not group then return false end
    if group.layout == "icons" and (value == "up" or value == "down") then
        return self:SetSelectedGroupIconLayout("wrapDirection", value)
    end
    if group.layout == "rings"
        and (value == "outward" or value == "inward") then
        return self:SetSelectedGroupDurationLayout("direction", value)
    end
    local alignment, wrapDirection = value:match("^(%a+)%-(%a+)$")
    if (alignment ~= "start"
            and alignment ~= "center"
            and alignment ~= "end")
        or (wrapDirection ~= "up" and wrapDirection ~= "down") then
        return false
    end
    local patch = {
        alignment = alignment,
        wrapDirection = wrapDirection,
    }
    local layout, code
    if group.layout == "icons" then
        layout, code = Designer:SetGroupIconLayout(
            session.selectedGroupId,
            patch
        )
    else
        if group.layout == "rings" then patch.direction = "grid" end
        layout, code = Designer:SetGroupDurationLayout(
            session.selectedGroupId,
            patch
        )
    end
    if not layout then
        self:SetStatus(
            T("designer.error_layout_update", "无法修改分组布局。")
                .. (code and (" " .. tostring(code)) or "")
        )
        self:Refresh(false)
        return false
    end
    self:Refresh(false)
    return layout
end

function DesignerUI:SetSelectedGroupStyle(field, value)
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local group = session and profile and profile.groups
        and profile.groups.items[session.selectedGroupId]
    if not group then return false end
    if group.layout == "icons" then
        return self:SetSelectedGroupIconStyle(field, value)
    end
    return self:SetSelectedGroupDurationStyle(field, value)
end

function DesignerUI:SetSelectedGroupPrimarySize(value)
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local group = session and profile and profile.groups
        and profile.groups.items[session.selectedGroupId]
    if not group then return false end
    if group.layout == "icons" then
        return self:SetSelectedGroupIconLayout("iconSize", value)
    end
    return self:SetSelectedGroupDurationLayout(
        group.layout == "rings" and "diameter" or "width",
        value
    )
end

function DesignerUI:SetSelectedGroupIconLayout(field, value)
    local session = Designer:GetSession()
    if not session then return false end
    local patch = field == "spacing" and {
        columnSpacing = value,
        rowSpacing = value,
    } or {
        [field] = value,
    }
    local layout, code = Designer:SetGroupIconLayout(
        session.selectedGroupId,
        patch
    )
    if not layout then
        self:SetStatus(
            T("designer.error_layout_update", "无法修改图标组布局。")
                .. (code and (" " .. tostring(code)) or "")
        )
        self:Refresh(false)
        return false
    end
    self:Refresh(false)
    self:SetStatus(
        T("designer.status_layout_updated", "图标组布局已更新。")
    )
    return layout
end

function DesignerUI:SetSelectedGroupDurationLayout(field, value)
    local session = Designer:GetSession()
    if not session then return false end
    local patch = field == "spacing" and {
        columnSpacing = value,
        rowSpacing = value,
    } or {
        [field] = value,
    }
    local layout, code = Designer:SetGroupDurationLayout(
        session.selectedGroupId,
        patch
    )
    if not layout then
        self:SetStatus(
            T("designer.error_duration_layout_update",
                "无法修改进度条或圆环布局。")
                .. (code and (" " .. tostring(code)) or "")
        )
        self:Refresh(false)
        return false
    end
    self:Refresh(false)
    self:SetStatus(
        T("designer.status_duration_layout_updated",
            "显示组布局已更新。")
    )
    return layout
end

function DesignerUI:SetSelectedGroupDurationOrientation(value)
    local session = Designer:GetSession()
    if not session then return false end
    local result, code = Designer:SetGroupDurationOrientation(
        session.selectedGroupId,
        value
    )
    if not result then
        self:SetStatus(
            T("designer.error_duration_layout_update",
                "无法修改进度条或圆环布局。")
                .. (code and (" " .. tostring(code)) or "")
        )
        self:Refresh(false)
        return false
    end
    self:Refresh(false)
    self:SetStatus(
        T("designer.status_duration_layout_updated",
            "显示组布局已更新。")
    )
    return result
end

function DesignerUI:SetSelectedGroupIconStyle(field, value)
    local session = Designer:GetSession()
    if not session then return false end
    local style, code = Designer:SetGroupIconStyle(
        session.selectedGroupId,
        {
            [field] = value,
        }
    )
    if not style then
        self:SetStatus(
            T("designer.error_style_update", "无法修改图标组外观。")
                .. (code and (" " .. tostring(code)) or "")
        )
        self:Refresh(false)
        return false
    end
    self:Refresh(false)
    self:SetStatus(
        T("designer.status_style_updated", "图标组外观已更新。")
    )
    return style
end

function DesignerUI:SetSelectedGroupDurationStyle(field, value)
    local session = Designer:GetSession()
    if not session then return false end
    local style, code = Designer:SetGroupDurationStyle(
        session.selectedGroupId,
        {
            [field] = value,
        }
    )
    if not style then
        self:SetStatus(
            T("designer.error_duration_style_update",
                "无法修改进度条或圆环外观。")
                .. (code and (" " .. tostring(code)) or "")
        )
        self:Refresh(false)
        return false
    end
    self:Refresh(false)
    self:SetStatus(
        T("designer.status_duration_style_updated",
            "显示组外观已更新。")
    )
    return style
end

function DesignerUI:SetSelectedGroupBorderColor(value)
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local group = session and profile and profile.groups
        and profile.groups.items[session.selectedGroupId]
    if not group then return false end
    if group.layout == "icons" then
        return self:SetSelectedGroupIconStyle(
            "iconBorderColor",
            value
        )
    end
    local patch = {
        iconBorderColor = value,
        borderColor = value,
    }
    if group.layout == "rings" then
        patch.ringBorderColor = value
    end
    local style, code = Designer:SetGroupDurationStyle(
        session.selectedGroupId,
        patch
    )
    if not style then
        self:SetStatus(
            T("designer.error_duration_style_update",
                "无法修改进度条或圆环外观。")
                .. (code and (" " .. tostring(code)) or "")
        )
        self:Refresh(false)
        return false
    end
    self:Refresh(false)
    return style
end

function DesignerUI:SetSelectedGroupTrackColor(value)
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local group = session and profile and profile.groups
        and profile.groups.items[session.selectedGroupId]
    if not group or group.layout == "icons" then return false end
    local field = group.layout == "rings"
        and "ringTrackColor" or "trackColor"
    return self:SetSelectedGroupDurationStyle(field, value)
end

function DesignerUI:SetDurationTextTarget(target)
    if target ~= "name" and target ~= "count" then
        target = "cooldown"
    end
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local group = session and profile and profile.groups
        and profile.groups.items[session.selectedGroupId]
    if group and group.layout == "icons" and target == "name" then
        target = "cooldown"
    end
    if self.durationTextTarget == target then return true end
    self.durationTextTarget = target
    return self:Refresh(false)
end

function DesignerUI:SetSelectedGroupTextStyle(suffix, value)
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local group = session and profile and profile.groups
        and profile.groups.items[session.selectedGroupId]
    if not group then return false end
    if group.layout == "icons"
        and self.durationTextTarget == "name" then
        return false
    end
    local prefix = self.durationTextTarget == "keybind"
        and group.layout == "icons" and "keybindText"
        or self.durationTextTarget == "count"
        and "countText"
        or (group.layout ~= "icons"
            and self.durationTextTarget == "name"
            and "nameText"
            or (group.layout ~= "icons"
                and "timeText" or "cooldownText"))
    if suffix == "Position" and group.layout == "bars" then
        suffix = "Anchor"
    end
    return self:SetSelectedGroupStyle(prefix .. (suffix or ""), value)
end

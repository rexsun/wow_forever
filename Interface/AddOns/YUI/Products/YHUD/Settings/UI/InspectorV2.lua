local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local GUI2 = YUI.GUI2
local Designer = YHUD.Designer
local DesignerUI = YHUD.DesignerUI
local I = DesignerUI and DesignerUI._internal
if not (GUI2 and GUI2.Form and Designer and DesignerUI and I) then return end

local BuildInspectorFoundation = DesignerUI.EnsureUI
local BaseSelectGroup = DesignerUI.SelectGroup
local BaseSelectMonitor = DesignerUI.SelectMonitor
local BaseRemoveSelectedMonitor = DesignerUI.RemoveSelectedMonitor
local BaseReorderSelectedMonitor = DesignerUI.ReorderSelectedMonitor
local BaseHideWorkspace = DesignerUI.HideWorkspace
local BasePositionInspector = DesignerUI.PositionInspector
local BaseSetSelectedGroupTextStyle = DesignerUI.SetSelectedGroupTextStyle
local BaseSetSelectedGroupResourceStyle =
    DesignerUI.SetSelectedGroupResourceStyle

local GroupName = I.GroupName
local GroupTypeName = I.GroupTypeName
local MonitorName = I.MonitorName
local EntryIcon = I.EntryIcon
local CountList = I.CountList
local TC = I.TC
local S = I.S
local ResourceCatalog = I.ResourceCatalog
local MonitorCatalog = YHUD.MonitorCatalog
local UnitAPI = YUI.API and YUI.API.Unit or YUI.WOW_API
local BuildFontOptions = I.BuildFontOptions
local BuildOutlineOptions = I.BuildOutlineOptions
local BuildBorderOptions = I.BuildBorderOptions
local BuildGlowStyleOptions = I.BuildGlowStyleOptions
local BuildNativeGlowStyleOptions = I.BuildNativeGlowStyleOptions
local ProjectResourceDisplayOrder = I.ProjectResourceDisplayOrder
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local SOURCE_BADGE_WARNING =
    "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"
local EQUIPMENT_AURA_BUNDLE_KIND =
    YHUD.EQUIPMENT_AURA_BUNDLE_KIND or "equipmentAura"

function I.ResourceColorDefault(field, child)
    return function()
        local id = DesignerUI.resourceStyleResourceId
        if not id then return nil end
        local defaults = YHUD:NormalizeResourceSetting({}, id)
        local value = defaults and defaults[field]
        if child then return value and value[child] end
        return value
    end
end

local function FinishOpenColorPicker(action)
    local picker = GUI2 and GUI2.ColorPicker
    return picker and picker:Close(action or "cancel") or false
end

local PANEL_WIDTH = 400
local PANEL_PADDING = 16
local CONTENT_WIDTH = PANEL_WIDTH - (PANEL_PADDING * 2)
local COLUMN_GAP = 16
local COLUMN_WIDTH = (CONTENT_WIDTH - COLUMN_GAP) / 2
local SECOND_COLUMN_X = COLUMN_WIDTH + COLUMN_GAP
local FIELD_LABEL_WIDTH = 104
local FIELD_CONTROL_WIDTH = CONTENT_WIDTH - FIELD_LABEL_WIDTH
local COMPACT_LABEL_WIDTH = 56
local COMPACT_CONTROL_WIDTH = COLUMN_WIDTH - COMPACT_LABEL_WIDTH
local RESOURCE_LABEL_HEIGHT = 18
local RESOURCE_CONTROL_OFFSET = 20
local RESOURCE_MENU_WIDTH = 220
local RefreshResourceSlots
local SWITCH_WIDTH = 42
local SWITCH_X = CONTENT_WIDTH - SWITCH_WIDTH - 10
local COLUMN_SWITCH_X = COLUMN_WIDTH - SWITCH_WIDTH - 10
local RESOURCE_COMMON_SWITCH_WIDTH = 84
local NEW_GROUP_WIDTH = 96
local GROUP_SELECTOR_GAP = 8
local GROUP_SELECTOR_WIDTH =
    CONTENT_WIDTH - NEW_GROUP_WIDTH - GROUP_SELECTOR_GAP
local PAGE_SIZE = 8
local MONITOR_ROW_WIDTH = CONTENT_WIDTH
local MONITOR_ICON_GAP = 6
local MONITOR_ICON_SIZE = 36
local MONITOR_IDENTITY_ICON_SIZE = 50
local MONITOR_ROW_CONTENT_WIDTH =
    (PAGE_SIZE * MONITOR_ICON_SIZE)
        + ((PAGE_SIZE - 1) * MONITOR_ICON_GAP)
local MONITOR_ROW_X = (MONITOR_ROW_WIDTH - MONITOR_ROW_CONTENT_WIDTH) / 2
local MONITOR_PAGER_Y = -(MONITOR_ICON_SIZE + 12)
local MONITOR_ACTION_HEIGHT = 34
local MONITOR_ACTION_GAP = 16
local MONITOR_SIDE_CONTROL_WIDTH = 88
local MONITOR_SIDE_CONTROL_HEIGHT = 28
local MONITOR_LIST_PANEL_HEIGHT = 76
local MONITOR_DETAIL_PANEL_HEIGHT = 152
local MONITOR_PANEL_GAP = 8
local MONITOR_EFFECTS_ACTION_WIDTH = 80
local MONITOR_EFFECTS_ACTION_HEIGHT = MONITOR_IDENTITY_ICON_SIZE
local MONITOR_SOUND_UI = {
    actionGap = 4,
    actionHeight = (MONITOR_EFFECTS_ACTION_HEIGHT - 4) / 2,
    dividerY = -52,
    addRuleY = -82,
    firstRuleY = -120,
    ruleHeight = 44,
    ruleGap = 8,
}
local MONITOR_REMOVE_ACTION_WIDTH = 72
local MONITOR_REORDER_ACTION_WIDTH = 28
local MONITOR_REORDER_ACTION_GAP = 4
local MONITOR_MOVE_LABEL_WIDTH = 60
local MONITOR_MOVE_LABEL_GAP = 6
local MONITOR_DETAIL_ACTION_GAP = 8
local MONITOR_DETAIL_HORIZONTAL_PADDING = 10
local MONITOR_HEADER_ACTION_WIDTH = 104
local MONITOR_HEADER_ACTION_HEIGHT = 30
local MONITOR_HEADER_ACTION_GAP = 6
local MONITOR_GLOBAL_ROW_HEIGHT = 38
local MONITOR_GLOBAL_PANEL_HEIGHT = 200
local MONITOR_GLOW_DROPDOWN_WIDTH = 178
local MONITOR_GLOW_GEAR_SIZE = 28
local MONITOR_GLOW_RULE_HEIGHT = 104
local MONITOR_GLOW_RULE_GAP = 8
local MONITOR_MOVE_ACTION_WIDTH = CONTENT_WIDTH
    - (MONITOR_DETAIL_HORIZONTAL_PADDING * 2)
    - MONITOR_REMOVE_ACTION_WIDTH
    - (MONITOR_REORDER_ACTION_WIDTH * 2)
    - MONITOR_REORDER_ACTION_GAP
    - MONITOR_MOVE_LABEL_WIDTH
    - MONITOR_MOVE_LABEL_GAP
    - (MONITOR_DETAIL_ACTION_GAP * 2)
local RESOURCE_PREVIEW_SECONDS = 5
local RESOURCE_PREVIEW_HOLD_SECONDS = 2
local CLASS_ARMOR_ORDER = {
    PRIEST = 1, MAGE = 1, WARLOCK = 1,
    DEMONHUNTER = 2, DRUID = 2, MONK = 2, ROGUE = 2,
    EVOKER = 3, HUNTER = 3, SHAMAN = 3,
    DEATHKNIGHT = 4, PALADIN = 4, WARRIOR = 4,
}

local function T(key, fallback)
    return YHUD:T(key, fallback)
end

function DesignerUI:AddResourcePreviewStat(field, amount)
    local Stats = YHUD.Stats
    if Stats and Stats.Add then Stats:Add(field, amount) end
end

local function SetShown(control, shown)
    if not control then return end
    if shown then control:Show() else control:Hide() end
end

local function SetStandardTextSize(control)
    if not (control and control.SetFont and GUI2.GetFont and GUI2.GetMetric) then
        return
    end
    control:SetFont(
        GUI2:GetFont("font.family.body"),
        GUI2:GetMetric("font.size.md", 13)
    )
end

local function FinishGlowMutation(result, code)
    if code then
        DesignerUI:SetMutationError(
            code,
            "designer.error_update",
            T("designer.error_update", "Unable to update the monitor.")
        )
        return false
    end
    DesignerUI:ApplyPreview()
    DesignerUI:Refresh(false, false)
    return result ~= false
end

local function FindOptionText(options, value, fallback)
    for index = 1, #(options or {}) do
        local option = options[index]
        if option.value == value then return option.text end
    end
    return fallback or tostring(value or "")
end

local function NativeGlowStyleValue(config)
    if type(config) == "table" and config.mode == "disabled" then
        return "disabled"
    end
    if type(config) ~= "table" or config.mode ~= "custom" then
        return "default"
    end
    local appearance = type(config.appearance) == "table"
        and config.appearance or nil
    return appearance and appearance.style or "pixel"
end

local function NativeGlowStyleText(config)
    local value = NativeGlowStyleValue(config)
    return FindOptionText(
        BuildNativeGlowStyleOptions and BuildNativeGlowStyleOptions() or {},
        value,
        value
    )
end

function I.BuildAuraActivationStyleOptions()
    local options = BuildNativeGlowStyleOptions(false)
    options[1].text = T("designer.monitor.activation_gold", "金色遮罩")
    return options
end

local GLOW_CONDITION_TEXT = {
    ["self-ready"] = { "designer.glow.self_ready", "Skill Ready" },
    ["self-cooldown"] = {
        "designer.glow.self_cooldown",
        "Skill Cooling Down",
    },
    ["aura-present"] = { "designer.glow.aura_present", "Aura Present" },
    ["aura-missing"] = { "designer.glow.aura_missing", "Aura Missing" },
    ["aura-stacks"] = { "designer.glow.aura_stacks", "Aura Stacks" },
    ["condition-met"] = { "designer.glow.timer_active", "Timer Active" },
}

local function GlowConditionText(conditionType, capabilities)
    if capabilities and capabilities.labelKind == "transform" then return T("designer.extra.threshold_met", "Transform reached reminder time") end
    if capabilities and capabilities.labelKind == "item" then
        if conditionType == "self-ready" then
            return T("designer.glow.item_ready", "Item Ready")
        elseif conditionType == "self-cooldown" then
            return T("designer.glow.item_cooldown", "Item Cooling Down")
        end
    end
    local definition = GLOW_CONDITION_TEXT[conditionType]
    return definition and T(definition[1], definition[2])
        or tostring(conditionType or "")
end

function I.SoundConditionText(conditionType, capabilities)
    if capabilities and capabilities.labelKind == "item" then
        if conditionType == "self-ready" then
            return T("designer.sound.item_ready", "Item Cooldown Finished")
        elseif conditionType == "self-cooldown" then
            return T("designer.sound.item_cooldown", "Item Cooldown Started")
        end
    end
    if conditionType == "self-ready" then
        return T("designer.sound.self_ready", "Cooldown Finished")
    elseif conditionType == "self-cooldown" then
        return T("designer.sound.self_cooldown", "Cooldown Started")
    elseif conditionType == "aura-present" then
        return T("designer.sound.aura_present", "Aura Gained")
    elseif conditionType == "aura-missing" then
        return T("designer.sound.aura_missing", "Aura Lost")
    elseif conditionType == "condition-met" then
        return T("designer.sound.timer_started", "Timer Started")
    elseif conditionType == "timer-ended" then
        return T("designer.sound.timer_ended", "Timer Ended")
    end
    return tostring(conditionType or "")
end

local function SelectedGlowContext()
    local profile = Designer:GetProfile()
    local monitor = Designer:GetSelectedMonitor()
    local capabilities = profile and monitor
        and YHUD:GetMonitorGlowCapabilities(profile, monitor) or nil
    return profile, monitor, capabilities
end

function I.SelectedSoundContext()
    local profile = Designer:GetProfile()
    local monitor = Designer:GetSelectedMonitor()
    local capabilities = profile and monitor
        and YHUD:GetMonitorSoundCapabilities(profile, monitor) or nil
    return profile, monitor, capabilities
end

function I.CopySelectedSoundRules(monitor)
    local config = YHUD:CopyValue(
        type(monitor) == "table" and monitor.sound or nil
    )
    if type(config) ~= "table" then config = {} end
    if type(config.rules) ~= "table" then config.rules = {} end
    return config
end

function I.BuildSoundOptions(currentKey)
    local options = {
        { value = "__none", text = TC("common.none", "无") },
    }
    local service = YUI.Sound
    local sounds = service and service.GetSoundOptions
        and service:GetSoundOptions() or {}
    local hasCurrent = currentKey == nil
    for index = 1, #sounds do
        options[#options + 1] = sounds[index]
        if sounds[index].value == currentKey then hasCurrent = true end
    end
    if not hasCurrent then
        options[#options + 1] = {
            value = currentKey,
            text = tostring(currentKey) .. T(
                "designer.sound.missing_in_pack",
                " (missing from current pack)"
            ),
        }
    end
    return options
end

local function CopySelectedGlowRules(monitor)
    local config = YHUD:CopyValue(
        type(monitor) == "table" and monitor.glow or nil
    )
    if type(config) ~= "table" then config = {} end
    if type(config.rules) ~= "table" then config.rules = {} end
    return config
end

local function PromoteLegacyFormText(self)
    local seen = {}
    for _, controls in ipairs({
        {
            self.groupNameLabel,
            self.enableLabel,
            self.unavailablePreviewLabel,
        },
        self.groupSectionControls or {},
        self.monitorSectionControls or {},
    }) do
        for index = 1, #controls do
            local control = controls[index]
            if control and not seen[control] then
                seen[control] = true
                local objectType = control.GetObjectType
                    and control:GetObjectType() or nil
                if objectType == "FontString" then
                    SetStandardTextSize(control)
                    if GUI2.SetTextColorKey then
                        GUI2:SetTextColorKey(control, "color.text.primary")
                    elseif control.SetTextColor and GUI2.GetColor then
                        control:SetTextColor(
                            GUI2:GetColor("color.text.primary")
                        )
                    end
                end
            end
        end
    end
end

local function Place(control, parent, x, y, width)
    if not control then return end
    control:ClearAllPoints()
    control:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 0, y or 0)
    if width and control.SetWidth then
        control:SetWidth(width)
        if control.chipBg and control.chipBg.SetWidth then
            control.chipBg:SetWidth(width)
            if control.chipBg.UpdateGUI2PixelLayout then
                control.chipBg:UpdateGUI2PixelLayout()
            end
        end
    end
end

local function HideControls(controls, seen)
    seen = seen or {}
    for index = 1, #(controls or {}) do
        local control = controls[index]
        if control and not seen[control] then
            seen[control] = true
            control:Hide()
        end
    end
    return seen
end

local function ShowControls(controls)
    for index = 1, #(controls or {}) do
        local control = controls[index]
        if control then control:Show() end
    end
end

local function HideAppearancePageVariants(self)
    local seen = {}
    HideControls(self.iconAppearanceControls, seen)
    HideControls(self.durationAppearanceControls, seen)
    HideControls(self.ringAppearanceControls, seen)
    HideControls(self.resourceAppearanceControls, seen)
    HideControls(self.resourceV2Controls, seen)
    for _, control in ipairs({
        self.v2Sliders and self.v2Sliders.iconZoom,
        self.cooldownBlingLabel,
        self.cooldownBlingSwitch,
        self.cooldownSwipeLabel,
        self.cooldownSwipeSwitch,
        self.chargeRecoveryControl,
        self.cooldownGCDLabel,
        self.cooldownGCDSwitch,
        self.iconShadowLabel,
        self.iconShadowSwitch,
        self.iconShadowColorLabel,
        self.iconShadowColorPicker,
        self.pandemicGlowDivider,
        self.pandemicGlowLabel,
        self.pandemicGlowSwitch,
    }) do
        if control and not seen[control] then
            seen[control] = true
            control:Hide()
        end
    end
end

local function HideMonitorEffectsPage(self)
    -- Optional controls leave holes in this list; ipairs would stop early.
    for _, control in pairs({
        self.skillAuraGlobalDivider,
        self.skillAuraGlobalPanel,
        self.skillAuraGlobalLabel,
        self.skillAuraGlobalSwitch,
        self.skillAuraOverrideCount,
        self.skillAuraClearOverrides,
        self.skillAuraItemDivider,
        self.skillAuraOverrideLabel,
        self.skillAuraOverrideStatus,
        self.skillAuraOverrideDropdown,
        self.monitorVisibilityLabel,
        self.monitorVisibilityDropdown,
        self.monitorVisibilityLayoutInfo,
        self.monitorEffectsTitle,
        self.monitorEffectsBack,
        self.monitorSelectedEffectsDivider,
        self.monitorAuraHighlightLabel,
        self.monitorAuraHighlightDropdown,
        self.monitorInactiveDesaturateLabel,
        self.monitorInactiveDesaturateDropdown,
        self.monitorAppearanceSwipeLabel,
        self.monitorAppearanceSwipe,
        self.monitorResetEffects,
        self.monitorGlowDivider,
        self.monitorAssistedLabel,
        self.monitorAssistedDropdown,
        self.monitorNativeLabel,
        self.monitorNativeDropdown,
        self.monitorNativeGear,
        self.monitorNativeCombatLabel,
        self.monitorNativeCombat,
        self.monitorGlowRulesDivider,
        self.monitorGlowRuleCount,
        self.monitorGlowPriorityText,
        self.monitorGlowAuraWarning,
        self.monitorGlowAddRule,
    }) do
        if control then control:Hide() end
    end
    for _, row in ipairs(self.monitorGlowRules or {}) do row:Hide() end
    self.monitorResetIncludesSwipe = false
    for _, row in ipairs(self.monitorGlobalEffectRows or {}) do
        if row.label then row.label:Hide() end
        if row.count then row.count:Hide() end
        if row.switch then row.switch:Hide() end
        if row.clear then row.clear:Hide() end
        if row.clearDisabledTooltip then row.clearDisabledTooltip:Hide() end
    end
end

function I.HideMonitorSoundPage(self)
    for _, control in pairs({
        self.monitorSoundTitle,
        self.monitorSoundBack,
        self.monitorSoundRulesDivider,
        self.monitorSoundRuleCount,
        self.monitorSoundAddRule,
    }) do
        if control then control:Hide() end
    end
    for _, row in ipairs(self.monitorSoundRules or {}) do row:Hide() end
end

local function HideMonitorDetailVariants(self)
    if YHUD.ClassExtra then YHUD.ClassExtra:HideSettings(self) end
    HideControls(self.monitorStackThresholdControls)
    HideControls(self.monitorBarProgressControls)
    HideMonitorEffectsPage(self)
    I.HideMonitorSoundPage(self)
    if self.bundleEditor then self.bundleEditor:Hide() end
    if self.equipmentTriggerNotice then
        self.equipmentTriggerNotice:Hide()
    end
    for _, control in ipairs({
        self.monitorGlowButton,
        self.monitorSoundButton,
        self.monitorReplicationButton,
        self.monitorAppearanceDivider,
        self.monitorAppearanceFillLabel,
        self.monitorAppearanceFill,
        self.monitorAppearanceTrackLabel,
        self.monitorAppearanceTrack,
        self.monitorAppearanceSwipeLabel,
        self.monitorAppearanceSwipe,
        self.monitorResetAppearance,
    }) do
        if control then control:Hide() end
    end
end

local GROUP_PAGE_KEYS = { "common", "layout", "appearance", "text" }
local V2_PAGE_KEYS = { "common", "layout", "appearance", "text", "monitor" }

local function EnsureV2PageRoots(self)
    if self.v2PageRoots then return self.v2PageRoots end
    local body = self.groupInspectorBody
    local roots = { monitor = self.monitorInspectorBody }
    roots.resourceMonitor = GUI2:CreateFrame(body, { mouse = false, hidden = true })
    roots.resourceMonitor:SetAllPoints(body)
    roots.resourceMonitor:Hide()
    for index = 1, #GROUP_PAGE_KEYS do
        local page = GROUP_PAGE_KEYS[index]
        local root = GUI2:CreateFrame(body, {
            mouse = false,
            hidden = true,
        })
        root:SetAllPoints(body)
        root:Hide()
        roots[page] = root
    end
    self.v2PageRoots = roots
    return roots
end

local function AdoptV2PageControl(root, control)
    if not (root and control and control.SetParent) then return end
    if control.GetParent and control:GetParent() == root then return end
    -- Visibility ownership only: existing anchors remain relative to the
    -- original inspector body, so reparenting cannot change page geometry.
    control:SetParent(root)
end

local function AdoptV2PageControls(root, controls, seen)
    if not (root and controls) then return end
    local valueType = type(controls)
    if valueType ~= "table" and valueType ~= "userdata" then return end
    seen = seen or {}
    if seen[controls] then return end
    seen[controls] = true
    if controls.SetParent then
        AdoptV2PageControl(root, controls)
        return
    end
    if valueType ~= "table" then return end
    for _, control in pairs(controls) do
        AdoptV2PageControls(root, control, seen)
    end
end

local function AssignV2PageParents(self)
    local roots = EnsureV2PageRoots(self)
    local pageControls = {
        common = {
            self.groupNameLabel,
            self.groupNameInput,
            self.fixedNameBadge,
            self.enableLabel,
            self.enableSwitch,
            self.unavailablePreviewLabel,
            self.unavailablePreviewSwitch,
            self.tooltipLabel,
            self.tooltipSwitch,
            self.visibilityPageControls,
            self.commonMaintenance,
        },
        layout = {
            self.layoutModeControls,
            self.iconLayoutControls,
            self.durationLayoutControls,
            self.barLayoutControls,
            self.resourceLayoutControls,
            self.v2Sliders and {
                self.v2Sliders.iconSize,
                self.v2Sliders.barWidth,
                self.v2Sliders.ringDiameter,
                self.v2Sliders.ringStep,
                self.v2Sliders.columnSpacing,
                self.v2Sliders.rowSpacing,
                self.v2Sliders.iconColumnSpacing,
                self.v2Sliders.iconRowSpacing,
                self.v2Sliders.itemOffset,
                self.v2Sliders.maxPerLine,
                self.v2Sliders.barHeight,
                self.v2Sliders.iconGap,
                self.v2Sliders.resourceWidth,
                self.v2Sliders.resourceMinWidth,
                self.v2Sliders.resourceHeight,
                self.v2Sliders.resourceSpacing,
            } or nil,
        },
        appearance = {
            self.iconAppearanceControls,
            self.durationAppearanceControls,
            self.ringAppearanceControls,
            self.resourceAppearanceControls,
            self.resourceV2Appearance,
            self.v2Sliders and self.v2Sliders.iconZoom or nil,
            self.cooldownBlingLabel,
            self.cooldownBlingSwitch,
            self.cooldownSwipeLabel,
            self.cooldownSwipeSwitch,
            self.chargeRecoveryControl,
            self.cooldownGCDLabel,
            self.cooldownGCDSwitch,
            self.iconShadowLabel,
            self.iconShadowSwitch,
            self.iconShadowColorLabel,
            self.iconShadowColorPicker,
            self.pandemicGlowDivider,
            self.pandemicGlowLabel,
            self.pandemicGlowSwitch,
        },
        text = {
            self.iconTextControls,
            self.iconTextTargetControls,
            self.durationTextControls,
            self.durationNameControls,
            self.resourceTextControls,
            self.resourceV2Text,
            self.textRows,
            self.resourceTextRows,
            self.resourceTextSettingsButton,
            self.textEditorTitle,
            self.textEditorBack,
            self.keybindTextControls,
            self.keybindOverrideRows,
            self.v2Sliders and {
                self.v2Sliders.textSize,
                self.v2Sliders.textOffsetX,
                self.v2Sliders.textOffsetY,
                self.v2Sliders.resourceTextSize,
            } or nil,
        },
        -- These controls are monitor-page actions even though the base
        -- builder initially places them in the shared group body.
        monitor = {
            self.addMonitorButton,
            self.addBuffButton,
        },
    }
    AdoptV2PageControls(roots.common, pageControls.common)
    if self.restoreButton and self.commonMaintenance then
        AdoptV2PageControl(self.commonMaintenance, self.restoreButton)
    end
    if self.deleteGroupButton and self.commonMaintenance then
        AdoptV2PageControl(self.commonMaintenance, self.deleteGroupButton)
    end

    AdoptV2PageControls(roots.layout, pageControls.layout)
    AdoptV2PageControls(roots.appearance, pageControls.appearance)
    AdoptV2PageControls(roots.text, pageControls.text)
    AdoptV2PageControls(roots.monitor, pageControls.monitor)
    AdoptV2PageControls(roots.resourceMonitor, { self.resourceBaseControls, self.resourcePresetRows })
end

local function HideV2PageRoots(self)
    for _, root in pairs(self.v2PageRoots or {}) do
        if root and root.Hide then root:Hide() end
    end
end

local function ActivateV2Page(self, page)
    local roots = EnsureV2PageRoots(self)
    for index = 1, #V2_PAGE_KEYS do
        local pageKey = V2_PAGE_KEYS[index]
        SetShown(roots[pageKey], pageKey == page)
    end
    local profile, session = Designer:GetProfile(), Designer:GetSession()
    local group = profile and session and profile.groups.items[session.selectedGroupId]
    SetShown(roots.resourceMonitor, page == "monitor" and group and group.layout == "resource")
    self.propertyPage = page
end

local function SyncV2PropertyTabs(self, page, monitorDisabled)
    local tabs = self.propertyTabs
    self.propertyPage = page
    if not tabs then return end

    if monitorDisabled then
        -- Leave Monitor silently before disabling it. UnderlineTabs otherwise
        -- commits its fallback selection and re-enters the page refresh.
        tabs:SetValue(page, true)
        tabs:SetItemDisabled("monitor", true)
        return
    end

    -- Monitor must be enabled before it can become the selected page.
    tabs:SetItemDisabled("monitor", false)
    tabs:SetValue(page, true)
end

local function SetDisabled(control, disabled)
    if not control then return end
    if control.SetDisabled then
        control:SetDisabled(disabled == true)
    elseif disabled and control.Disable then
        control:Disable()
    elseif not disabled and control.Enable then
        control:Enable()
    end
end

local function SetTextStyleControlsDisabled(self, disabled)
    for _, control in ipairs({
        self.fontDropdown,
        self.outlineDropdown,
        self.textPositionDropdown,
        self.textColorPicker,
        self.v2Sliders.textSize,
        self.v2Sliders.textOffsetX,
        self.v2Sliders.textOffsetY,
    }) do
        SetDisabled(control, disabled)
    end
end

local function AddSectionHeading(parent, text, icon, onToggle)
    local divider = GUI2:CreateDivider(parent, {
        width = CONTENT_WIDTH,
        height = 22,
        label = text,
        alignLeft = true,
        collapsible = onToggle ~= nil,
        collapsed = onToggle ~= nil,
        onToggle = onToggle,
    })
    if icon then
        local leading = GUI2:CreateIcon(divider, {
            icon = icon,
            crop = true,
            size = 16,
        })
        leading:SetPoint("LEFT", divider, "LEFT", 0, 0)
        divider.gui2LeadingIcon = leading
        if divider.gui2DividerText then
            divider.gui2DividerText:ClearAllPoints()
            divider.gui2DividerText:SetPoint("LEFT", divider, "LEFT", 24, 0)
        end
    end
    divider:Hide()
    return divider
end

local function SettingsIcon(name)
    return GUI2.GetSettingsIcon and GUI2:GetSettingsIcon(name)
        or QUESTION_ICON
end

local function SelectedContext()
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local selectedMonitorId = session and (
        session.selectedMonitorId or session.selectedPreviewMonitorId
    )
    if session and session.staticPreview == true then
        profile = Designer:GetPresentationProfile() or profile
    end
    local group = session and profile and profile.groups
        and profile.groups.items[session.selectedGroupId]
    local monitor = selectedMonitorId and profile
        and profile.monitors[selectedMonitorId]
    return session, profile, group, monitor
end

local function MonitorLane(profile, monitor)
    if not monitor then return nil end
    if monitor.contentScope ~= YHUD.CONTENT_SCOPE_SHARED then
        return YHUD.CONTENT_LANE_SPEC
    end
    local laneByMonitor = rawget(profile or {}, "_yhudLaneByMonitor") or {}
    return laneByMonitor[monitor.id] == YHUD.CONTENT_LANE_BEFORE
        and YHUD.CONTENT_LANE_BEFORE or YHUD.CONTENT_LANE_AFTER
end

local function ResolveV2ReorderOperation(
    profile,
    group,
    monitor,
    delta,
    specialState
)
    delta = tonumber(delta)
    if delta ~= -1 and delta ~= 1 then return nil end
    if not (profile and group and monitor and group.monitors) then return nil end

    local visualIndex
    local laneCounts = {
        [YHUD.CONTENT_LANE_BEFORE] = 0,
        [YHUD.CONTENT_LANE_SPEC] = 0,
        [YHUD.CONTENT_LANE_AFTER] = 0,
    }
    local laneIndexes = {}
    for index = 1, #group.monitors do
        local candidateId = group.monitors[index]
        local candidate = profile.monitors[candidateId]
        local lane = MonitorLane(profile, candidate)
        if lane then
            laneCounts[lane] = laneCounts[lane] + 1
            laneIndexes[candidateId] = laneCounts[lane]
        end
        if candidateId == monitor.id then visualIndex = index end
    end
    local adjacentId = visualIndex and group.monitors[visualIndex + delta]
    local adjacent = adjacentId and profile.monitors[adjacentId]
    if not adjacent then return nil end

    local state = specialState or (YHUD.GetSpecialMonitorGroupState
        and YHUD:GetSpecialMonitorGroupState(profile, group, true))
    if state and state.segmented == true then
        local monitorEntry = profile.entries[monitor.entryKey]
        local adjacentEntry = profile.entries[adjacent.entryKey]
        local monitorSpecial = YHUD:IsFilteredAuraLayoutMonitor(
            monitorEntry,
            monitor,
            true
        )
        local adjacentSpecial = YHUD:IsFilteredAuraLayoutMonitor(
            adjacentEntry,
            adjacent,
            true
        )
        if monitorSpecial ~= adjacentSpecial then
            return nil, "special-overflow-region"
        end
    end

    local lane = MonitorLane(profile, monitor)
    local adjacentLane = MonitorLane(profile, adjacent)
    if lane == adjacentLane then
        return {
            monitorId = monitor.id,
            selectedMonitorId = monitor.id,
            targetLane = lane,
            targetIndex = laneIndexes[monitor.id] + delta,
        }
    end

    if lane == YHUD.CONTENT_LANE_BEFORE and delta == 1 then
        return {
            monitorId = monitor.id,
            selectedMonitorId = monitor.id,
            targetLane = YHUD.CONTENT_LANE_AFTER,
            targetIndex = adjacentLane == YHUD.CONTENT_LANE_AFTER
                and (laneIndexes[adjacent.id] + 1) or 1,
        }
    end
    if lane == YHUD.CONTENT_LANE_AFTER and delta == -1 then
        return {
            monitorId = monitor.id,
            selectedMonitorId = monitor.id,
            targetLane = YHUD.CONTENT_LANE_BEFORE,
            targetIndex = adjacentLane == YHUD.CONTENT_LANE_BEFORE
                and laneIndexes[adjacent.id]
                or (laneCounts[YHUD.CONTENT_LANE_BEFORE] + 1),
        }
    end
    if lane == YHUD.CONTENT_LANE_SPEC
        and adjacentLane == YHUD.CONTENT_LANE_BEFORE
        and delta == -1 then
        return {
            monitorId = adjacent.id,
            selectedMonitorId = monitor.id,
            targetLane = YHUD.CONTENT_LANE_AFTER,
            targetIndex = 1,
        }
    end
    if lane == YHUD.CONTENT_LANE_SPEC
        and adjacentLane == YHUD.CONTENT_LANE_AFTER
        and delta == 1 then
        return {
            monitorId = adjacent.id,
            selectedMonitorId = monitor.id,
            targetLane = YHUD.CONTENT_LANE_BEFORE,
            targetIndex = laneCounts[YHUD.CONTENT_LANE_BEFORE] + 1,
        }
    end
    return nil
end

local function EntryTypeText(entry)
    if type(entry) ~= "table" then return "-" end
    local semantic = YHUD:GetEntrySemantic(entry)
    return semantic == "buff"
        and T("designer.monitor.type_buff", "光环监控")
        or (semantic == "resource"
            and T("designer.monitor.type_resource", "资源监控")
            or T("designer.monitor.type_cooldown", "冷却监控"))
end

local function EntryTypeBadgeText(entry)
    if type(entry) ~= "table" then return "-" end
    local semantic = YHUD:GetEntrySemantic(entry)
    return semantic == "buff"
        and T("designer.monitor.type_buff_short", "光环")
        or (semantic == "resource"
            and T("designer.monitor.type_resource_short", "资源")
            or T("designer.monitor.type_cooldown_short", "冷却"))
end

local function BloodlustBadgeText(entry)
    if type(entry) ~= "table"
        or (entry.sourceIdentity ~= "bloodlust"
            and entry.sourceIdentity ~= "bloodlust-heroism") then
        return nil
    end
    local faction = YHUD:GetPlayerFactionToken()
    if faction == "Horde" then
        return T("designer.bundle.short.bloodlust_horde", "嗜血")
    end
    return T("designer.bundle.short.bloodlust_alliance", "英勇")
end

local function EntryIdentityValue(entry)
    if type(entry) ~= "table" then return nil end
    return entry.overrideSpellId
        or entry.spellId
        or entry.itemId
        or entry.slotId or entry.slotID
        or entry.cooldownID
end

local function EntryIdentity(entry)
    local value = EntryIdentityValue(entry)
    local text = tostring(value or "-")
    if type(entry) == "table"
        and entry.sourceType == YHUD.CAST_BUFF_TIMER_SOURCE_TYPE
        and type(entry.durationSeconds) == "number" then
        local duration = entry.durationSeconds
        local durationText = duration % 1 == 0
            and tostring(math.floor(duration))
            or tostring(duration)
        text = string.format("%s (%ss)", text, durationText)
    end
    return text
end

local function MonitorSourceText(entry)
    if type(entry) == "table" and entry.origin == "official-cdm" then
        return T("designer.monitor.source.native", "原生"), 0, 0.68, 1, 1
    end
    if type(entry) == "table"
        and (entry.origin == "preset" or entry.presetKey ~= nil) then
        return T("designer.monitor.source.preset", "预设"), 1, 0.50, 0, 1
    end
    local r, g, b, a = GUI2:GetColor(
        "color.text.primary",
        { 1, 1, 1, 1 }
    )
    return T("designer.monitor.source.custom", "自定义"), r, g, b, a
end

local function MonitorStatusText(entry, availability)
    if availability == "unavailable" then
        return T("designer.monitor.status.unavailable", "当前专精不可用")
    end
    if availability == "ineligible" then
        if YUI.IsForever == true and entry and entry.sourceType == "yhud.ammo-count" then
            return T("monitor.ammo.unsupported", "弹药监控不适用于当前角色")
        end
        return T("designer.monitor.status.ineligible", "不适用于当前专精")
    end
    if type(entry) == "table" and entry.conflict ~= nil then
        return T("designer.monitor.status.conflict", "监控来源存在冲突")
    end
    if type(entry) == "table" and entry.verificationStatus == "candidate" then
        return T(
            "designer.verification.candidate_tooltip",
            "套装效果候选，尚未经过实战验证。"
        )
    end
    if type(entry) == "table" and entry.warning ~= nil then
        return type(entry.warning) == "string" and entry.warning
            or T("designer.monitor.status.warning", "监控状态需要注意")
    end
    return T("designer.monitor.status.available", "可用")
end

local function HasExceptionalMonitorStatus(entry, availability)
    return type(entry) == "table"
        and (entry.verificationStatus == "candidate"
            or entry.warning ~= nil
            or entry.conflict ~= nil)
end

local function HasMonitorDetailStatus(entry, availability)
    return availability == "unavailable"
        or availability == "ineligible"
        or HasExceptionalMonitorStatus(entry, availability)
end

local function ApplyMonitorWarningBadge(badge, entry, availability)
    if not badge then return false end
    badge:SetTexture(nil)
    badge:SetTexCoord(0, 1, 0, 1)
    if HasExceptionalMonitorStatus(entry, availability) then
        badge:SetTexture(SOURCE_BADGE_WARNING)
        badge:Show()
        return true
    end
    badge:Hide()
    return false
end

local function ShowMonitorBrowserTooltip(control)
    local entry = control and control.yhudEntry
    if not (entry and GameTooltip) then return end
    if DesignerUI.ShowForeverSealTooltip
        and DesignerUI:ShowForeverSealTooltip(control, entry) then return end
    GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    GameTooltip:SetText(control.yhudMonitorName or "-", 1, 1, 1)
    if GameTooltip.AddLine then
        local sourceText, sourceR, sourceG, sourceB = MonitorSourceText(entry)
        GameTooltip:AddLine(string.format(
            T("designer.monitor.source_format", "来源：%s"),
            sourceText
        ), sourceR, sourceG, sourceB)
        if control.yhudSpecialMonitor == true then
            local specialR, specialG, specialB = GUI2:GetColor(
                "color.state.warning"
            )
            GameTooltip:AddLine(T(
                "designer.monitor.special_tooltip",
                "“特殊”表示该监控使用受限布局通道；\n可以紧凑补位，但只能在同类区域内调整顺序。"
            ), specialR, specialG, specialB, true)
        end
        local available = control.yhudAvailability ~= "unavailable"
            and control.yhudAvailability ~= "ineligible"
            and entry.conflict == nil
        local availabilityText = available
            and T("designer.monitor.status.available", "可用")
            or T("designer.monitor.status.unavailable_short", "不可用")
        local statusR, statusG, statusB = GUI2:GetColor(
            available and "color.state.success" or "color.state.danger"
        )
        GameTooltip:AddLine(string.format(
            T("designer.monitor.status_format", "状态：%s"),
            availabilityText
        ), statusR, statusG, statusB, true)
        if entry.verificationStatus == "candidate"
            or entry.warning ~= nil
            or entry.conflict ~= nil then
            local reasonR, reasonG, reasonB = GUI2:GetColor(
                entry.conflict ~= nil
                    and "color.state.danger" or "color.state.warning"
            )
            GameTooltip:AddLine(
                MonitorStatusText(entry, control.yhudAvailability),
                reasonR,
                reasonG,
                reasonB,
                true
            )
        end
        if control.yhudCacheOnlyPreview == true
            and entry.origin == "official-cdm" then
            GameTooltip:AddLine(" ")
            local cacheR, cacheG, cacheB = GUI2:GetColor(
                "color.state.danger",
                { 0.90, 0.18, 0.22, 1 }
            )
            GameTooltip:AddLine(T(
                "designer.monitor.native_cache_history_warning",
                "当前数据来自历史缓存，实际以切换到该专精后为准。"
            ), cacheR, cacheG, cacheB, true)
        end
    end
    GameTooltip:Show()
end

local function SetIntrinsicTextWidth(label, maxWidth, fallbackWidth)
    if not label then return end
    local width
    if label.GetUnboundedStringWidth then
        width = label:GetUnboundedStringWidth()
    elseif label.GetStringWidth then
        width = label:GetStringWidth()
    end
    width = tonumber(width) or fallbackWidth or 1
    label:SetWidth(math.max(1, math.min(width + 1, maxWidth or width + 1)))
end

local function ApplySolidMonitorButton(button, surfaceToken, borderToken)
    if not button then return end
    button.yhudSolidSurfaceToken = surfaceToken
    button.yhudSolidBorderToken = borderToken or surfaceToken
    local function Paint(frame, hovered, pressed)
        if frame.SetBackdropColor then
            frame:SetBackdropColor(GUI2:GetColor(frame.yhudSolidSurfaceToken))
        end
        GUI2:SetBorderColor(
            frame,
            pressed and "color.border.strong"
                or (hovered and "color.text.primary"
                    or frame.yhudSolidBorderToken)
        )
        frame:SetAlpha(frame.gui2Disabled and 0.48
            or (pressed and 0.88 or 1))
        if frame.SetTextColor then
            frame:SetTextColor(GUI2:GetColor("color.badge.text"))
        end
        if frame.icon and frame.icon.SetVertexColor then
            frame.icon:SetVertexColor(GUI2:GetColor("color.badge.text"))
        end
    end
    if not button.yhudSolidConfigured then
        button.yhudSolidConfigured = true
        GUI2.Form:SetButtonRelief(button, "hairline")
        local baseRefreshTheme = button.RefreshTheme
        button.RefreshTheme = function(frame)
            if baseRefreshTheme then baseRefreshTheme(frame) end
            Paint(frame, frame:IsMouseOver() and not frame.gui2Disabled, false)
        end
        if button.HookScript then
            button:HookScript("OnEnter", function(frame)
                if not frame.gui2Disabled then Paint(frame, true, false) end
            end)
            button:HookScript("OnLeave", function(frame)
                Paint(frame, false, false)
            end)
            button:HookScript("OnMouseDown", function(frame)
                if not frame.gui2Disabled then Paint(frame, true, true) end
            end)
            button:HookScript("OnMouseUp", function(frame)
                Paint(
                    frame,
                    frame:IsMouseOver() and not frame.gui2Disabled,
                    false
                )
            end)
        end
    end
    Paint(button, false, false)
end

I.ApplySolidMonitorButton = ApplySolidMonitorButton

local function SetMonitorTypeText(label, entry)
    if not label then return end
    local semantic = type(entry) == "table" and YHUD:GetEntrySemantic(entry)
    local color = semantic == "buff" and "color.badge.purple"
        or (semantic == "resource" and "color.badge.orange"
            or "color.badge.green")
    GUI2:SetTextColorKey(label, color)
    label:SetText(EntryTypeBadgeText(entry))
end

local function CreateSlider(
    parent,
    label,
    minimum,
    maximum,
    step,
    precision,
    set,
    width,
    labelWidth,
    inputWidth,
    labelFontSizeKey,
    labelColorKey,
    tooltip
)
    return GUI2.Form:CreateSlider(parent, {
        width = width or CONTENT_WIDTH,
        inline = true,
        label = label,
        labelWidth = labelWidth or FIELD_LABEL_WIDTH,
        inputWidth = inputWidth or 52,
        min = minimum,
        max = maximum,
        step = step,
        precision = precision,
        labelFontSizeKey = labelFontSizeKey,
        labelColorKey = labelColorKey,
        tooltip = tooltip,
        set = set,
        onCommit = function()
            DesignerUI:CommitV2SliderPreview()
        end,
    })
end

local function TextStylePrefix(group, target)
    if target == "keybind" then return "keybindText" end
    if target == "count" then return "countText" end
    if group.layout ~= "icons" and target == "name" then
        return "nameText"
    end
    return group.layout == "icons" and "cooldownText" or "timeText"
end

function DesignerUI:SetChargeRecoveryDisplay(value)
    if self.v2Refreshing then return end
    local session = Designer:GetSession()
    if not session then return false end
    local style, code = Designer:SetGroupIconStyle(session.selectedGroupId, {
        chargeRecoveryDisplay = value or "hideSwipeOnly",
    })
    if not style then
        self:SetStatus(T("designer.error_style_update", "无法修改图标组外观。")
            .. (code and (" " .. tostring(code)) or ""))
        self:Refresh(false)
        return false
    end
    -- Keep the owner visible while editing the popup; the draft remains authoritative.
    if not self:PreviewSelectedGroup() then self:ApplyPreview() end
    self:SetStatus(T("designer.status_style_updated", "图标组外观已更新。"))
    return style
end

function DesignerUI:PreviewSelectedGroup()
    local session, profile, group = SelectedContext()
    local View = YHUD.View
    local groupId = session and session.selectedGroupId
    local projection = View and View.designProjection
    if not (profile and group and View and View.active and projection
        and View.RefreshDesignProjectionGroup) then
        return false
    end

    self:SyncResourcePreviewContext()
    local projectionContext = YHUD.BuildMonitorLayoutProjectionContext
        and YHUD:BuildMonitorLayoutProjectionContext(profile, true) or nil
    if not View:RefreshDesignProjectionGroup(
        profile,
        groupId,
        projectionContext
    ) then return false end
    if View.SetDesignCooldownPreviewGroup then
        local textTarget = self.propertyPage == "text"
            and (self.textEditorTarget or "all") or nil
        View:SetDesignCooldownPreviewGroup(
            textTarget and groupId or nil,
            textTarget
        )
    end
    if self.propertyPage == "text" and projection.byMonitor then
        for _, slot in pairs(projection.byMonitor) do
            if slot._yhudGroupId == groupId then
                if View.EnsureDesignTextPreview then
                    View:EnsureDesignTextPreview(slot)
                end
                if View.ApplyDesignTextPreview then
                    View:ApplyDesignTextPreview(slot)
                end
            end
        end
    end
    if self.ReapplyResourceValuePreview then
        self:ReapplyResourceValuePreview()
    end

    return true
end

function DesignerUI:ApplyV2SliderPatch(kind, field, value)
    local session, _, group = SelectedContext()
    if not (session and group) then return false end
    local setter
    local patchField = field
    if kind == "layout" then
        setter = group.layout == "icons"
            and Designer.SetGroupIconLayout
            or Designer.SetGroupDurationLayout
    elseif kind == "iconLayout" then
        setter = Designer.SetGroupIconLayout
    elseif kind == "durationLayout" then
        setter = Designer.SetGroupDurationLayout
    elseif kind == "iconStyle" then
        setter = Designer.SetGroupIconStyle
    elseif kind == "style" then
        setter = group.layout == "icons"
            and Designer.SetGroupIconStyle
            or Designer.SetGroupDurationStyle
    elseif kind == "durationStyle" then
        setter = Designer.SetGroupDurationStyle
    elseif kind == "resourceLayout" then
        setter = Designer.SetGroupResourceLayout
    elseif kind == "resourceStyle" then
        setter = Designer.SetGroupResourceStyle
    elseif kind == "textStyle" then
        setter = group.layout == "icons"
            and Designer.SetGroupIconStyle
            or Designer.SetGroupDurationStyle
        patchField = TextStylePrefix(group, self.durationTextTarget)
            .. (field or "")
    end
    if not setter then return false end
    local result = setter(Designer, session.selectedGroupId, {
        [patchField] = value,
    })
    if not result then return false end
    self.v2SliderPreviewDirty = true
    self:PreviewSelectedGroup()
    if kind == "resourceStyle" and RefreshResourceSlots then
        RefreshResourceSlots(nil)
    end
    return result
end

function DesignerUI:CommitV2SliderPreview()
    if not self.v2SliderPreviewDirty then return false end
    self.v2SliderPreviewDirty = nil
    local _, _, group = SelectedContext()
    if group and group.layout == "resource" then
        return self:PreviewSelectedGroup()
    end
    return self:ApplyPreview()
end

function DesignerUI:RefreshDesignerGeometry()
    if not (self.toolbar and self.panel and UIParent) then return end
    local screenHeight = UIParent:GetHeight() or 1080
    if self.LayoutToolbar then self:LayoutToolbar() end
    self.panel:SetWidth(PANEL_WIDTH)
    self.fixedPanelHeight = math.max(
        540,
        math.min(680, screenHeight - 126)
    )
    self.panel:SetHeight(self.fixedPanelHeight)
end

function DesignerUI:PositionInspector(animate)
    if self.v2Built then self:RefreshDesignerGeometry() end
    return BasePositionInspector(self, animate)
end

function DesignerUI:CaptureCooldownSettingsLayer(frame)
    if not frame or self.cooldownSettingsLayer then return end
    self.cooldownSettingsLayer = {
        frame = frame,
        strata = frame.GetFrameStrata and frame:GetFrameStrata(),
        level = frame.GetFrameLevel and frame:GetFrameLevel(),
    }
end

function DesignerUI:ElevateCooldownSettings(frame)
    if not (self.active and frame) then return end
    self:CaptureCooldownSettingsLayer(frame)
    if frame.SetFrameStrata then frame:SetFrameStrata("DIALOG") end
    local center = YUI.Settings and YUI.Settings.SoundCenter
    local host = center and center.designerWindow
    if host and host:IsShown() then
        if frame.SetFrameStrata then frame:SetFrameStrata(host:GetFrameStrata()) end
        if frame.SetFrameLevel then frame:SetFrameLevel(host:GetFrameLevel() + 100) end
    end
end

function DesignerUI:RestoreCooldownSettingsLayer()
    local state = self.cooldownSettingsLayer
    if not state then return end
    local frame = state.frame
    if frame then
        if state.strata and frame.SetFrameStrata then
            frame:SetFrameStrata(state.strata)
        end
        if state.level and frame.SetFrameLevel then frame:SetFrameLevel(state.level) end
    end
    self.cooldownSettingsLayer = nil
end

function DesignerUI:OpenBlizzardCooldownSettings()
    local system = YUI.API and YUI.API.System
    if system and system.LoadAddOn then
        system.LoadAddOn("Blizzard_CooldownViewer")
    end
    local frame = _G.CooldownViewerSettings
    if not frame then
        self:SetStatus(T(
            "designer.error_blizzard_cooldown_settings",
            "无法打开暴雪冷却设置。"
        ))
        return false
    end
    if frame.HookScript and not self.cooldownSettingsHooked then
        self.cooldownSettingsHooked = true
        frame:HookScript("OnShow", function(control)
            DesignerUI:ElevateCooldownSettings(control)
            if DesignerUI.monitorPicker
                and DesignerUI.monitorPicker:IsShown() then
                DesignerUI:SetMonitorPickerBlocked(true)
            end
        end)
        frame:HookScript("OnHide", function()
            DesignerUI:RestoreCooldownSettingsLayer()
            if DesignerUI.monitorPicker
                and DesignerUI.monitorPicker:IsShown() then
                DesignerUI:SynchronizeMonitorPickerFromBlizzard()
            else
                DesignerUI:SetMonitorPickerBlocked(false)
            end
        end)
    end
    self:ElevateCooldownSettings(frame)
    local security = YUI.API and YUI.API.Security
    if security and security.SecureCallMethod then
        security.SecureCallMethod(frame, "ShowUIPanel")
    elseif frame.ShowUIPanel then
        frame:ShowUIPanel()
    else
        frame:Show()
    end
    return true
end

local function BuildToolbar(self)
    self:EnsureSpecializationToolbar()
    self:LayoutToolbar()
end
local function BuildPageShell(self)
    if self.propertyTabs then return end

    self.inspectorScroll:Hide()
    if self.inspectorScroll.EnableMouseWheel then
        self.inspectorScroll:EnableMouseWheel(false)
    end
    if self.inspectorAccordion then self.inspectorAccordion:Hide() end
    self.legacyInspectorAccordion = self.inspectorAccordion
    self.inspectorAccordion = {
        SetSectionTitle = function() end,
        SetSectionContentHeight = function() end,
        SetSectionVisible = function() end,
        SetActive = function() end,
    }

    local panel = self.panel
    local body = self.groupInspectorBody
    if self.dragHandle then self.dragHandle:SetWidth(PANEL_WIDTH - 28) end
    body:SetParent(panel)
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, -146)
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PANEL_PADDING, PANEL_PADDING)
    body:SetWidth(CONTENT_WIDTH)

    local monitorBody = self.monitorInspectorBody
    monitorBody:SetParent(panel)
    monitorBody:ClearAllPoints()
    monitorBody:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, -146)
    monitorBody:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PANEL_PADDING, PANEL_PADDING)
    monitorBody:SetWidth(CONTENT_WIDTH)
    EnsureV2PageRoots(self)

    if not self.statusText then
        self.statusText = GUI2:CreateText(
            body, "", "font.size.md", "color.text.secondary", "LEFT"
        )
        self.statusText:SetHeight(32)
        self.statusText:SetWordWrap(true)
        self.statusText:Hide()
    end
    if not self.levelDisplayNotice then
        local notice = GUI2:CreateFrame(panel, {
            width = PANEL_WIDTH,
            height = 24,
            mouse = false,
            hidden = true,
        })
        notice:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, 10)
        notice.text = GUI2:CreateText(
            notice, "", "font.size.md", "color.badge.orange", "LEFT"
        )
        notice.text:SetPoint("TOPLEFT", notice, "TOPLEFT", 0, 0)
        notice.text:SetWidth(PANEL_WIDTH)
        notice.text:SetWordWrap(true)
        self.levelDisplayNotice = notice
        panel:HookScript("OnShow", function()
            DesignerUI:RefreshLevelDisplayNotice()
        end)
        panel:HookScript("OnHide", function()
            DesignerUI:ResetInspectorBinding()
            DesignerUI:RefreshLevelDisplayNotice()
        end)
    end
    if not self.specialOverflowNotice then
        local notice = GUI2:CreateFrame(panel, {
            width = PANEL_WIDTH,
            height = 24,
            mouse = false,
            hidden = true,
        })
        notice:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, 10)
        notice.text = GUI2:CreateText(
            notice,
            T(
                "designer.special_overflow.notice",
                "本组包含“特殊”监控，且混排图标超过一行。"
            ),
            "font.size.md",
            "color.badge.orange",
            "LEFT"
        )
        notice.text:SetPoint("LEFT", notice, "LEFT", 0, 0)
        notice.text:SetWidth(PANEL_WIDTH - 104)
        notice.text:SetHeight(24)
        notice.text:SetWordWrap(false)
        local link = GUI2:CreateFrame(notice, {
            width = 100,
            height = 24,
            mouse = true,
        })
        link:SetPoint("LEFT", notice.text, "RIGHT", 4, 0)
        link.text = GUI2:CreateText(
            link,
            T("designer.special_overflow.learn_more", "<查看更多>"),
            "font.size.md",
            "color.state.success",
            "LEFT"
        )
        link.text:SetAllPoints(link)
        link.text:SetWordWrap(false)
        link:HookScript("OnEnter", function(control)
            if not GameTooltip then return end
            GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
            GameTooltip:SetText(T(
                "designer.special_overflow.tooltip",
                "“特殊”监控使用暴雪受限布局通道。运行时会紧凑补入普通区域最后一行的剩余位置，其余图标排列在换行方向一侧。设计模式展示全部配置，因此位置可能与运行时不同。特殊监控与其他监控仍只能在各自区域内调整顺序。"
            ), 1, 0.55, 0.12, 1, true)
            GameTooltip:Show()
        end)
        link:HookScript("OnLeave", function()
            YUI.HideGameTooltip()
        end)
        notice.link = link
        self.specialOverflowNotice = notice
    end
    if not self.deleteGroupButton then
        self.deleteGroupButton = GUI2.Form:CreateButton(body, {
            text = T("designer.delete_group", "删除分组"),
            width = 144,
            height = 30,
            tone = "danger",
            onClick = function()
                DesignerUI:DeleteSelectedGroup()
            end,
        })
        self.deleteGroupButton:Hide()
    end

    self.groupSelectorLabel:Hide()
    self.groupDropdown:ClearAllPoints()
    self.groupDropdown:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, -52)
    self.groupDropdown:SetWidth(GROUP_SELECTOR_WIDTH)
    self.newGroupButton:ClearAllPoints()
    self.newGroupButton:SetPoint("LEFT", self.groupDropdown, "RIGHT", GROUP_SELECTOR_GAP, 0)
    self.newGroupButton:SetWidth(NEW_GROUP_WIDTH)
    self.newGroupButton:SetText(T("designer.add_group", "添加分组"))
    ApplySolidMonitorButton(
        self.newGroupButton,
        "color.badge.orange",
        "color.state.warning"
    )
    self.newGroupButton:Show()

    local tabs = GUI2.Form:CreateUnderlineTabs(panel, {
        width = CONTENT_WIDTH,
        height = 34,
        gap = 8,
        minItemWidth = 60,
        equalWidth = true,
        showBaseline = true,
        value = "common",
        items = {
            { text = T("designer.page.common", "常规"), value = "common" },
            { text = T("designer.page.layout", "布局"), value = "layout" },
            { text = T("designer.page.appearance", "外观"), value = "appearance" },
            { text = T("designer.page.text", "文字"), value = "text" },
            { text = T("designer.page.monitor", "监控"), value = "monitor" },
        },
        set = function(value)
            DesignerUI:SetPropertyPage(value)
        end,
    })
    tabs:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, -98)
    self.propertyTabs = tabs
    self.propertyPage = self.propertyPage or "common"

    local maintenance = GUI2:CreatePanel(body, {
        width = CONTENT_WIDTH,
        height = 50,
        surface = "color.surface.panel",
        border = "color.border.default",
    })
    local maintenanceLabel = GUI2:CreateText(
        maintenance,
        T("designer.maintenance", "维护"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    maintenanceLabel:SetPoint("LEFT", maintenance, "LEFT", 14, 0)
    maintenanceLabel:SetWordWrap(false)
    maintenance:Hide()
    self.commonMaintenance = maintenance
    self.commonMaintenanceLabel = maintenanceLabel

    local tooltipLabel = GUI2:CreateText(
        body,
        T("designer.group_tooltips", "鼠标提示"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    local tooltipSwitch = GUI2.Form:CreateSwitch(body, {
        width = SWITCH_WIDTH,
        height = 22,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            local session = Designer:GetSession()
            if session and Designer:SetGroupTooltip(
                session.selectedGroupId,
                value == true
            ) then
                DesignerUI:ApplyPreview()
            end
        end,
    })
    tooltipLabel:Hide()
    tooltipSwitch:Hide()
    self.tooltipLabel = tooltipLabel
    self.tooltipSwitch = tooltipSwitch

    local visibilityLabel = GUI2:CreateText(
        body,
        T("designer.group_visibility", "显示规则"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    local visibilityEditor = GUI2.Form:CreateVisibilityRuleEditor(body, {
        width = CONTENT_WIDTH,
        popupWidth = 320,
        set = function(rule, _, editor)
            if DesignerUI.v2Refreshing then return end
            local groupId = editor and editor:GetContext()
            if groupId and Designer:SetGroupVisibility(groupId, rule) then
                DesignerUI:ApplyPreview()
                DesignerUI:SetStatus(DesignerUI:IsSessionDirty()
                    and T("designer.status_dirty", "当前配置有未保存修改。")
                    or T("designer.status_clean", "当前配置已保存。"))
            end
        end,
    })
    visibilityLabel:SetHeight(30)
    if visibilityLabel.SetJustifyV then visibilityLabel:SetJustifyV("MIDDLE") end
    visibilityLabel:Hide()
    visibilityEditor:Hide()
    self.visibilityRuleLabel = visibilityLabel
    self.visibilityRuleEditor = visibilityEditor
    self.visibilityPageControls = {
        visibilityLabel,
        visibilityEditor,
    }

    local cooldownBlingLabel = GUI2:CreateText(
        body,
        T("designer.appearance.cooldown_bling", "冷却完成闪光"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    local cooldownBlingSwitch = GUI2.Form:CreateSwitch(body, {
        width = SWITCH_WIDTH,
        height = 22,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            DesignerUI:SetSelectedGroupIconStyle(
                "cooldownBling",
                value == true
            )
        end,
    })
    cooldownBlingLabel:Hide()
    cooldownBlingSwitch:Hide()
    self.cooldownBlingLabel = cooldownBlingLabel
    self.cooldownBlingSwitch = cooldownBlingSwitch

    local cooldownSwipeLabel = GUI2:CreateText(
        body,
        T("designer.appearance.cooldown_swipe", "冷却旋转"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    local cooldownSwipeSwitch = GUI2.Form:CreateSwitch(body, {
        width = SWITCH_WIDTH,
        height = 22,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            DesignerUI:SetSelectedGroupIconStyle(
                "cooldownSwipe",
                value == true
            )
        end,
    })
    cooldownSwipeLabel:Hide()
    cooldownSwipeSwitch:Hide()
    self.cooldownSwipeLabel = cooldownSwipeLabel
    self.cooldownSwipeSwitch = cooldownSwipeSwitch
    self.MonitorHelp:Bind(cooldownSwipeLabel, "cooldownSwipe", "group")

    self.chargeRecoveryControl = GUI2.Form:CreateChargeRecoveryControl(body, {
        width = CONTENT_WIDTH,
        set = function(value)
            DesignerUI:SetChargeRecoveryDisplay(value)
        end,
    })
    self.chargeRecoveryControl:Hide()

    self.cooldownGCDLabel = GUI2:CreateText(
        body,
        T("designer.appearance.cooldown_gcd", "公共冷却"),
        "font.size.md", "color.text.primary", "LEFT"
    )
    self.cooldownGCDSwitch = GUI2.Form:CreateSwitch(body, {
        width = SWITCH_WIDTH,
        height = 22,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            DesignerUI:SetSelectedGroupIconStyle("cooldownGCD", value == true)
        end,
    })
    self.cooldownGCDLabel:Hide()
    self.cooldownGCDSwitch:Hide()

    self.iconShadowLabel = GUI2:CreateText(
        body, T("designer.appearance.icon_shadow", "图标阴影"),
        "font.size.md", "color.text.primary", "LEFT"
    )
    self.iconShadowSwitch = GUI2.Form:CreateSwitch(body, {
        width = SWITCH_WIDTH, height = 22,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            DesignerUI:SetSelectedGroupIconStyle("iconShadow", value == true)
        end,
    })
    self.iconShadowColorLabel = GUI2:CreateText(
        body, T("designer.appearance.shadow_color", "阴影颜色"),
        "font.size.md", "color.text.primary", "LEFT"
    )
    self.iconShadowColorPicker = GUI2.Form:CreateColorPicker(body, {
        width = COLUMN_WIDTH, height = 30, field = true, hasAlpha = true,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            DesignerUI:SetSelectedGroupIconStyle("iconShadowColor", value)
        end,
    })
    self.iconShadowLabel:Hide()
    self.iconShadowSwitch:Hide()
    self.iconShadowColorLabel:Hide()
    self.iconShadowColorPicker:Hide()

    local pandemicDivider = AddSectionHeading(
        body,
        T("designer.appearance.pandemic_global", "当前方案全局设置")
    )
    local pandemicLabel = GUI2:CreateText(
        body,
        T("designer.appearance.pandemic_glow", "DOT 刷新提示"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    local pandemicSwitch = GUI2.Form:CreateSwitch(body, {
        width = SWITCH_WIDTH,
        height = 22,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            if Designer:SetPandemicGlow(value == true) ~= nil then
                DesignerUI:ApplyPreview()
            end
        end,
    })
    pandemicDivider:Hide()
    pandemicLabel:Hide()
    pandemicSwitch:Hide()
    self.pandemicGlowDivider = pandemicDivider
    self.pandemicGlowLabel = pandemicLabel
    self.pandemicGlowSwitch = pandemicSwitch
end

local function SetV2InspectorScrollActive(self, enabled, targetBody)
    local scroll = self.inspectorScroll
    local child = self.inspectorScrollChild
    local body = targetBody or self.groupInspectorBody
    if not (scroll and child and body) then return end
    enabled = enabled == true
    local previousBody = self.v2InspectorScrollBody
    if previousBody and previousBody ~= body then
        previousBody:SetParent(self.panel)
        previousBody:ClearAllPoints()
        previousBody:SetPoint(
            "TOPLEFT", self.panel, "TOPLEFT", PANEL_PADDING, -146
        )
        previousBody:SetPoint(
            "BOTTOMRIGHT", self.panel, "BOTTOMRIGHT", -PANEL_PADDING, PANEL_PADDING
        )
    end
    if enabled then
        local wasActive = self.v2InspectorScrollActive == true
        self.v2InspectorScrollActive = true
        scroll:SetParent(self.panel)
        scroll:ClearAllPoints()
        scroll:SetPoint(
            "TOPLEFT",
            self.panel,
            "TOPLEFT",
            PANEL_PADDING,
            -146
        )
        scroll:SetPoint(
            "BOTTOMRIGHT",
            self.panel,
            "BOTTOMRIGHT",
            -PANEL_PADDING,
            PANEL_PADDING
        )
        child:SetWidth(CONTENT_WIDTH)
        body:SetParent(child)
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
        body:SetWidth(CONTENT_WIDTH)
        self.v2InspectorScrollBody = body
        if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true) end
        scroll:Show()
        if not wasActive and scroll.SetVerticalScroll then
            scroll:SetVerticalScroll(0)
        end
        return
    end
    self.v2InspectorScrollActive = false
    self.v2InspectorScrollBody = nil
    scroll:Hide()
    if scroll.EnableMouseWheel then scroll:EnableMouseWheel(false) end
    body:SetParent(self.panel)
    body:ClearAllPoints()
    body:SetPoint(
        "TOPLEFT",
        self.panel,
        "TOPLEFT",
        PANEL_PADDING,
        -146
    )
    body:SetPoint(
        "BOTTOMRIGHT",
        self.panel,
        "BOTTOMRIGHT",
        -PANEL_PADDING,
        PANEL_PADDING
    )
    body:SetWidth(CONTENT_WIDTH)
end

local function SetV2InspectorScrollContentHeight(self, height)
    if self.v2InspectorScrollActive ~= true then return end
    height = math.max(1, tonumber(height) or 1)
    self.v2InspectorContentHeight = height
    local body = self.v2InspectorScrollBody or self.groupInspectorBody
    body:SetHeight(height)
    self.inspectorScrollChild:SetHeight(height)
    local viewportHeight = self.inspectorScroll.GetHeight
        and self.inspectorScroll:GetHeight() or 0
    local overflow = height > (viewportHeight + 1)
    local scrollBar = self.inspectorScroll.gui2ScrollBar
        or self.inspectorScroll.ScrollBar
    if scrollBar and scrollBar.SetShown then
        scrollBar:SetShown(overflow)
    elseif scrollBar then
        if overflow then scrollBar:Show() else scrollBar:Hide() end
    end
    if self.inspectorScroll.EnableMouseWheel then
        self.inspectorScroll:EnableMouseWheel(overflow)
    end
    if not overflow
        and self.inspectorScroll.SetVerticalScroll then
        self.inspectorScroll:SetVerticalScroll(0)
    end
    if self.inspectorScroll.UpdateScrollChildRect then
        self.inspectorScroll:UpdateScrollChildRect()
    end
end

local function BuildNumericSliders(self)
    if self.v2Sliders then return end
    local body = self.groupInspectorBody
    local sliders = {}
    if I.BuildBarWidthUI then I.BuildBarWidthUI(self, COLUMN_WIDTH) end
    sliders.iconSize = CreateSlider(
        body, T("designer.layout.icon_size", "图标尺寸"), 24, 96, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("iconLayout", "iconSize", value) end
    )
    sliders.barWidth = CreateSlider(
        body, T("designer.layout.width", "总长度"), 48, 832, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("durationLayout", "width", value) end
    )
    sliders.ringDiameter = CreateSlider(
        body, T("designer.layout.diameter", "圆环直径"), 24, 160, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("durationLayout", "diameter", value) end
    )
    sliders.ringStep = CreateSlider(
        body, T("designer.layout.ring_step", "环径差"), 2, 48, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("durationLayout", "ringStep", value) end
    )
    sliders.columnSpacing = CreateSlider(
        body, T("designer.layout.column_spacing", "列间距"), 0, 32, 1, 0,
        function(value)
            DesignerUI:ApplyV2SliderPatch("layout", "columnSpacing", value)
        end
    )
    sliders.rowSpacing = CreateSlider(
        body, T("designer.layout.row_spacing", "行间距"), 0, 32, 1, 0,
        function(value)
            DesignerUI:ApplyV2SliderPatch("layout", "rowSpacing", value)
        end
    )
    sliders.maxPerLine = CreateSlider(
        body, T("designer.layout.max_per_line", "每行 / 列数量"), 1, 40, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("layout", "maxPerLine", value) end
    )
    sliders.iconColumnSpacing = CreateSlider(
        body, T("designer.layout.column_spacing", "列间距"), -32, 32, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("iconLayout", "columnSpacing", value) end
    )
    sliders.iconRowSpacing = CreateSlider(
        body, T("designer.layout.row_spacing", "行间距"), -32, 32, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("iconLayout", "rowSpacing", value) end
    )
    sliders.itemOffset = CreateSlider(
        body, T("designer.layout.item_offset", "逐项偏移"), -64, 64, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("iconLayout", "itemOffset", value) end,
        nil, nil, nil, nil, nil, T("designer.layout.item_offset_tip")
    )
    sliders.barHeight = CreateSlider(
        body, T("designer.layout.height", "总厚度"), 2, 128, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("durationLayout", "height", value) end
    )
    sliders.iconGap = CreateSlider(
        body, T("designer.layout.icon_gap", "图标间距"), 0, 32, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("durationLayout", "iconGap", value) end
    )
    sliders.iconZoom = CreateSlider(
        body, T("designer.appearance.zoom", "图标缩放"), 0, 0.24, 0.01, 2,
        function(value) DesignerUI:ApplyV2SliderPatch("style", "iconZoom", value) end
    )
    sliders.textSize = CreateSlider(
        body, T("designer.text.size", "字号"), 8, 32, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("textStyle", "Size", value) end,
        COLUMN_WIDTH, COMPACT_LABEL_WIDTH, 42
    )
    sliders.textOffsetX = CreateSlider(
        body, TC("common.offset_x", "X 偏移"), -64, 64, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("textStyle", "OffsetX", value) end,
        COLUMN_WIDTH, COMPACT_LABEL_WIDTH, 42
    )
    sliders.textOffsetY = CreateSlider(
        body, TC("common.offset_y", "Y 偏移"), -64, 64, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("textStyle", "OffsetY", value) end,
        COLUMN_WIDTH, COMPACT_LABEL_WIDTH, 42
    )
    sliders.resourceWidth = CreateSlider(
        body, T("designer.resource.width", "资源条宽度"), 48, 640, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("resourceLayout", "width", value) end
    )
    sliders.resourceMinWidth = CreateSlider(
        body, T("designer.resource.min_width", "最小宽度"), 48, 640, 1, 0,
        function(value)
            DesignerUI:ApplyV2SliderPatch(
                "resourceLayout",
                "minWidth",
                value
            )
        end
    )
    sliders.resourceHeight = CreateSlider(
        body, T("designer.resource.height", "资源条高度"), 2, 128, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("resourceLayout", "height", value) end
    )
    sliders.resourceSpacing = CreateSlider(
        body, T("designer.resource.spacing", "资源条间距"), -12, 32, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("resourceLayout", "spacing", value) end
    )
    sliders.resourceTextSize = CreateSlider(
        body, nil, 8, 32, 1, 0,
        function(value) DesignerUI:ApplyV2SliderPatch("resourceStyle", "textSize", value) end,
        COLUMN_WIDTH, nil, 52
    )
    local resourceWidthModeLabel = GUI2:CreateText(
        body,
        T("designer.resource.width_mode", "宽度模式"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    local resourceWidthModeDropdown = GUI2.Form:CreateDropdown(body, {
        width = COLUMN_WIDTH,
        height = 30,
        options = function()
            return {
                {
                    value = "auto",
                    text = T("designer.resource.width_auto", "自动"),
                },
                {
                    value = "fixed",
                    text = T("designer.resource.width_fixed", "固定"),
                },
            }
        end,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            local result = DesignerUI:ApplyV2SliderPatch(
                "resourceLayout",
                "widthMode",
                value
            )
            if result then DesignerUI:Refresh(false, false) end
        end,
    })
    resourceWidthModeLabel:Hide()
    resourceWidthModeDropdown:Hide()
    self.resourceLayoutControls[#self.resourceLayoutControls + 1] =
        resourceWidthModeLabel
    self.resourceLayoutControls[#self.resourceLayoutControls + 1] =
        resourceWidthModeDropdown
    self.resourceWidthModeLabel = resourceWidthModeLabel
    self.resourceWidthModeDropdown = resourceWidthModeDropdown
    for _, slider in pairs(sliders) do slider:Hide() end
    self.v2Sliders = sliders
end

local function BuildMonitorBrowser(self)
    if self.monitorBrowser then return end
    local body = self.monitorInspectorBody
    ApplySolidMonitorButton(
        self.addMonitorButton,
        "color.badge.green",
        "color.state.success"
    )
    ApplySolidMonitorButton(
        self.addBuffButton,
        "color.badge.purple",
        "color.badge.purple"
    )
    ApplySolidMonitorButton(
        self.removeMonitorButton,
        "color.state.danger",
        "color.state.danger"
    )
    local globalDivider = AddSectionHeading(
        body,
        T("designer.monitor.skill_aura_global", "全局"),
        136243,
        function(collapsed)
            DesignerUI.monitorGlobalCollapsed = collapsed
            DesignerUI:Refresh(false, false)
        end
    )
    local globalPanel = GUI2:CreatePanel(body, {
        width = CONTENT_WIDTH,
        height = MONITOR_GLOBAL_PANEL_HEIGHT,
        surface = "color.surface.panel",
        border = "color.border.default",
    })
    local globalEffectDefinitions = {
        {
            key = "auraTimer",
            field = "skillAuraDisplay",
            text = T("designer.monitor.skill_aura_display", "技能光环计时"),
        },
        {
            key = "auraHighlight",
            field = "skillAuraHighlight",
            text = T("designer.monitor.aura_highlight", "激活提示"),
        },
        {
            key = "inactiveDesaturate",
            field = "inactiveDesaturate",
            text = T("designer.monitor.inactive_desaturate", "非激活褪色"),
        },
    }
    local globalEffectRows = {}
    for index = 1, #globalEffectDefinitions do
        local definition = globalEffectDefinitions[index]
        local effectKey = definition.key
        local profileField = definition.field
        local row = {
            key = effectKey,
            field = profileField,
        }
        row.label = GUI2:CreateText(
            globalPanel,
            definition.text,
            "font.size.md",
            "color.text.primary",
            "LEFT"
        )
        row.label:SetPoint(
            "TOPLEFT",
            globalPanel,
            "TOPLEFT",
            12,
            -12 - ((index - 1) * MONITOR_GLOBAL_ROW_HEIGHT)
        )
        row.count = GUI2:CreateText(
            globalPanel,
            "(0)",
            "font.size.sm",
            "color.text.secondary",
            "LEFT"
        )
        row.count:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
        self.MonitorHelp:Bind(row.label, effectKey, "global")
        row.switch = GUI2.Form:CreateSwitch(globalPanel, {
            width = 48,
            tooltip = effectKey == "assistedHighlight" and T("designer.monitor.assisted_highlight_tip") or nil,
            height = MONITOR_SIDE_CONTROL_HEIGHT,
            set = function(value)
                if DesignerUI.v2Refreshing then return end
                local result
                if effectKey == "auraTimer" then
                    result = Designer:SetSkillAuraDisplay(value == true)
                else
                    result = Designer:SetGlobalMonitorStateEffect(
                        effectKey,
                        value == true
                    )
                end
                if result ~= nil then
                    DesignerUI:ApplyPreview()
                    DesignerUI:Refresh(false, false)
                end
            end,
        })
        row.switch:SetPoint(
            "TOPRIGHT",
            globalPanel,
            "TOPRIGHT",
            -40,
            -6 - ((index - 1) * MONITOR_GLOBAL_ROW_HEIGHT)
        )
        if effectKey == "auraHighlight" then
            row.style = GUI2.Form:CreateDropdown(globalPanel, {
                width = 100, height = MONITOR_SIDE_CONTROL_HEIGHT,
                options = I.BuildAuraActivationStyleOptions,
                set = function(value)
                    if DesignerUI.v2Refreshing then return end
                    local current = YHUD:CopyValue(YHUD:GetAuraActivationStyle(Designer:GetProfile()))
                    current.mode = value == "default" and "default" or "custom"
                    current.appearance = value ~= "default"
                        and (current.appearance or YHUD:GetDefaultMonitorGlowAppearance()) or nil
                    if current.appearance then current.appearance.style = value end
                    FinishGlowMutation(Designer:SetAuraActivationStyle(current))
                end,
            })
            row.style:SetPoint("TOPRIGHT", globalPanel, "TOPRIGHT", -126,
                -6 - ((index - 1) * MONITOR_GLOBAL_ROW_HEIGHT))
            row.gear = GUI2.Form:CreateIconButton(globalPanel, {
                size = 26, icon = SettingsIcon("settings"),
                tooltip = T("designer.glow.edit_appearance", "Edit glow appearance"),
                onClick = function() DesignerUI:OpenGlowAppearanceEditor("global-activation") end,
            })
            row.gear:SetPoint("TOPRIGHT", globalPanel, "TOPRIGHT", -94,
                -7 - ((index - 1) * MONITOR_GLOBAL_ROW_HEIGHT))
        end
        row.clear = GUI2.Form:CreateIconButton(globalPanel, {
            size = 26,
            icon = SettingsIcon("rotate-ccw"),
            tooltip = T(
                "designer.monitor.clear_overrides_tooltip",
                "清除该设置的所有单项覆盖，使监控重新跟随全局设置。"
            ),
            onClick = function()
                local count = Designer:ClearMonitorStateEffectOverrides(effectKey)
                if count and count > 0 then
                    DesignerUI:ApplyPreview()
                    DesignerUI:Refresh(false, false)
                end
            end,
        })
        row.clear:SetPoint(
            "TOPRIGHT",
            globalPanel,
            "TOPRIGHT",
            -8,
            -7 - ((index - 1) * MONITOR_GLOBAL_ROW_HEIGHT)
        )
        row.clearDisabledTooltip = GUI2:CreateButtonFrame(globalPanel, {
            width = 26,
            height = 26,
            mouse = true,
            hidden = true,
            onClick = function(control)
                if (control.overrideCount or 0) <= 0 then return end
                local count = Designer:ClearMonitorStateEffectOverrides(
                    control.effectKey
                )
                if count and count > 0 then
                    DesignerUI:ApplyPreview()
                    DesignerUI:Refresh(false, false)
                end
            end,
        })
        row.clearDisabledTooltip.effectKey = effectKey
        row.clearDisabledTooltip:SetAllPoints(row.clear)
        if row.clearDisabledTooltip.SetFrameLevel
            and row.clear.GetFrameLevel then
            row.clearDisabledTooltip:SetFrameLevel(row.clear:GetFrameLevel() + 5)
        end
        row.clearDisabledTooltip:SetScript("OnEnter", function(control)
            if not GameTooltip then return end
            GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
            GameTooltip:SetText(
                T(
                    "designer.monitor.clear_overrides_tooltip",
                    "清除该设置的所有单项覆盖，使监控重新跟随全局设置。"
                ),
                1,
                1,
                1,
                1,
                true
            )
            GameTooltip:Show()
        end)
        row.clearDisabledTooltip:SetScript("OnLeave", function()
            YUI.HideGameTooltip()
        end)
        globalEffectRows[index] = row
    end
    local globalNativeLabel = GUI2:CreateText(
        globalPanel,
        T("designer.glow.native_proc", "Native Proc Glow"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    globalNativeLabel:SetPoint("TOPLEFT", globalPanel, "TOPLEFT", 12, -130 - (MONITOR_GLOBAL_PANEL_HEIGHT - 200))
    local globalNativeDropdown = GUI2.Form:CreateDropdown(globalPanel, {
        width = MONITOR_GLOW_DROPDOWN_WIDTH,
        height = MONITOR_SIDE_CONTROL_HEIGHT,
        options = BuildNativeGlowStyleOptions,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            local profile = Designer:GetProfile()
            local current = YHUD:CopyValue(
                profile and profile.style
                    and profile.style.nativeProcGlow or {}
            )
            if value == "default" or value == "disabled" then
                current.mode = value
                current.appearance = nil
            else
                current.mode = "custom"
                current.appearance = type(current.appearance) == "table"
                    and current.appearance
                    or YHUD:GetDefaultMonitorGlowAppearance()
                current.appearance.style = value
            end
            FinishGlowMutation(Designer:SetNativeProcGlow(current))
        end,
    })
    globalNativeDropdown:SetPoint(
        "TOPRIGHT",
        globalPanel,
        "TOPRIGHT",
        -(MONITOR_GLOW_GEAR_SIZE + 14),
        -120 - (MONITOR_GLOBAL_PANEL_HEIGHT - 200)
    )
    local globalNativeGear = GUI2.Form:CreateIconButton(globalPanel, {
        size = MONITOR_GLOW_GEAR_SIZE,
        icon = SettingsIcon("settings"),
        tooltip = T("designer.glow.edit_appearance", "Edit glow appearance"),
        onClick = function()
            DesignerUI:OpenGlowAppearanceEditor("global-native")
        end,
    })
    globalNativeGear:SetPoint("TOPRIGHT", globalPanel, "TOPRIGHT", -8, -120 - (MONITOR_GLOBAL_PANEL_HEIGHT - 200))
    local globalNativeCombatLabel = GUI2:CreateText(
        globalPanel,
        T("designer.glow.native_combat_only", "Native Glow Combat Only"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    globalNativeCombatLabel:SetPoint(
        "TOPLEFT",
        globalPanel,
        "TOPLEFT",
        12,
        -168 - (MONITOR_GLOBAL_PANEL_HEIGHT - 200)
    )
    local globalNativeCombat = GUI2.Form:CreateSwitch(globalPanel, {
        width = 48,
        height = MONITOR_SIDE_CONTROL_HEIGHT,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            local profile = Designer:GetProfile()
            local current = YHUD:CopyValue(
                profile and profile.style
                    and profile.style.nativeProcGlow or {}
            )
            current.combatOnly = value == true and true or nil
            FinishGlowMutation(Designer:SetNativeProcGlow(current))
        end,
    })
    globalNativeCombat:SetPoint(
        "TOPRIGHT",
        globalPanel,
        "TOPRIGHT",
        -8,
        -158 - (MONITOR_GLOBAL_PANEL_HEIGHT - 200)
    )
    local summary = GUI2:CreateText(
        body,
        "",
        "font.size.md",
        "color.text.secondary",
        "LEFT"
    )
    summary:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -10)
    summary:SetHeight(30)
    summary:SetWordWrap(false)

    summary.nativePreviewStatus = GUI2:CreateFrame(body, {
        width = CONTENT_WIDTH,
        height = 18,
        mouse = true,
        hidden = true,
    })
    summary.nativePreviewStatus:SetPoint(
        "TOPLEFT", body, "TOPLEFT", 0, -46
    )
    summary.nativePreviewStatus.text = GUI2:CreateText(
        summary.nativePreviewStatus,
        T(
            "designer.monitor.native_cache_missing",
            "暴雪监控尚无缓存"
        ),
        "font.size.sm",
        "color.text.accent",
        "LEFT"
    )
    summary.nativePreviewStatus.text:SetAllPoints(
        summary.nativePreviewStatus
    )
    summary.nativePreviewStatus:HookScript("OnEnter", function(control)
        if not GameTooltip then return end
        GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
        GameTooltip:SetText(T(
            "designer.monitor.native_cache_missing_tooltip",
            "切换到该专精后自动记录。预设和自定义监控仍可编辑。"
        ), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    summary.nativePreviewStatus:HookScript("OnLeave", function()
        YUI.HideGameTooltip()
    end)

    local browser = GUI2:CreateFrame(body, {
        width = MONITOR_ROW_WIDTH,
        height = MONITOR_LIST_PANEL_HEIGHT
            + MONITOR_PANEL_GAP
            + MONITOR_DETAIL_PANEL_HEIGHT,
    })
    browser:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -44)
    browser.buttons = {}

    local listPanel = GUI2:CreatePanel(browser, {
        width = CONTENT_WIDTH,
        height = MONITOR_LIST_PANEL_HEIGHT,
        surface = "color.surface.panel",
        border = "color.border.default",
    })
    listPanel:SetPoint("TOPLEFT", browser, "TOPLEFT", 0, 0)

    for index = 1, PAGE_SIZE do
        local button = GUI2:CreateIconSlot(listPanel, {
            size = MONITOR_ICON_SIZE,
            icon = QUESTION_ICON,
            crop = true,
            variant = "bare",
            shape = "square",
            border = "thin",
            selectedBorderColor = "color.state.warning",
            hoverBorderColor = "color.state.warning",
            onClick = function(control)
                if control.monitorId then DesignerUI:SelectMonitor(control.monitorId) end
            end,
        })
        button:SetPoint(
            "TOPLEFT",
            listPanel,
            "TOPLEFT",
            MONITOR_ROW_X
                + ((index - 1) * (MONITOR_ICON_SIZE + MONITOR_ICON_GAP)),
            -8
        )
        button.bundleLabelBackdrop = GUI2:CreatePanel(button, {
            width = MONITOR_ICON_SIZE - 2,
            height = 13,
            surface = "color.surface.popup",
            border = false,
        })
        button.bundleLabelBackdrop:SetPoint(
            "BOTTOM",
            button,
            "BOTTOM",
            0,
            1
        )
        if button.bundleLabelBackdrop.EnableMouse then
            button.bundleLabelBackdrop:EnableMouse(false)
        end
        button.bundleLabel = GUI2:CreateText(
            button.bundleLabelBackdrop,
            "",
            "font.size.sm",
            "color.text.primary",
            "CENTER"
        )
        button.bundleLabel:SetPoint(
            "CENTER",
            button.bundleLabelBackdrop,
            "CENTER",
            0,
            0
        )
        button.bundleLabel:SetWidth(MONITOR_ICON_SIZE - 4)
        button.bundleLabel:SetWordWrap(false)
        button.bundleLabelBackdrop:Hide()
        button.bundleLabel:Hide()
        button.sourceBadge = GUI2:CreateIcon(button, {
            icon = SOURCE_BADGE_WARNING,
            size = 16,
            crop = false,
            layer = "OVERLAY",
            subLevel = 7,
        })
        button.sourceBadge:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
        button.sourceBadge:Hide()
        button:HookScript("OnEnter", ShowMonitorBrowserTooltip)
        button:HookScript("OnLeave", function()
            YUI.HideGameTooltip()
        end)
        browser.buttons[index] = button
    end

    local previous = GUI2.Form:CreateButton(listPanel, {
        text = "<",
        width = 22,
        height = 20,
        textLeftPadding = 2,
        textRightPadding = 2,
        onClick = function()
            DesignerUI.monitorPage = math.max(1, (DesignerUI.monitorPage or 1) - 1)
            DesignerUI:RefreshMonitorBrowser()
        end,
    })
    previous:SetPoint("TOPRIGHT", listPanel, "TOP", -30, MONITOR_PAGER_Y)
    local pageText = GUI2:CreateText(
        listPanel, "1 / 1", "font.size.md", "color.text.secondary", "CENTER"
    )
    pageText:SetPoint("TOP", listPanel, "TOP", 0, MONITOR_PAGER_Y - 4)
    local nextButton = GUI2.Form:CreateButton(listPanel, {
        text = ">",
        width = 22,
        height = 20,
        textLeftPadding = 2,
        textRightPadding = 2,
        onClick = function()
            DesignerUI.monitorPage = (DesignerUI.monitorPage or 1) + 1
            DesignerUI:RefreshMonitorBrowser()
        end,
    })
    nextButton:SetPoint("TOPLEFT", listPanel, "TOP", 30, MONITOR_PAGER_Y)

    local detailPanel = GUI2:CreatePanel(browser, {
        width = CONTENT_WIDTH,
        height = MONITOR_DETAIL_PANEL_HEIGHT,
        surface = "color.surface.panel",
        border = "color.border.default",
    })
    detailPanel:SetPoint(
        "TOPLEFT",
        listPanel,
        "BOTTOMLEFT",
        0,
        -MONITOR_PANEL_GAP
    )

    local identityIcon = GUI2:CreateIconSlot(detailPanel, {
        size = MONITOR_IDENTITY_ICON_SIZE,
        icon = QUESTION_ICON,
        crop = true,
        variant = "bare",
        shape = "square",
        border = "thin",
    })
    identityIcon:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 12, -14)
    identityIcon:HookScript("OnEnter", function(control)
        local entry = control.yhudEntry
        if not (entry and GameTooltip) then return end
        if DesignerUI.ShowForeverSealTooltip
            and DesignerUI:ShowForeverSealTooltip(control, entry) then return end
        GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
        if GameTooltip.ClearLines then GameTooltip:ClearLines() end
        local shown
        local itemId = tonumber(
            entry.itemId or entry.itemID or entry.currentItemId
        )
        local slotId = tonumber(entry.slotId or entry.slotID)
        local spellId = tonumber(
            entry.overrideSpellId or entry.spellId or entry.displaySpellID
        )
        if slotId and GameTooltip.SetInventoryItem then
            shown = pcall(
                GameTooltip.SetInventoryItem,
                GameTooltip,
                "player",
                slotId
            )
        elseif itemId and GameTooltip.SetItemByID then
            shown = pcall(GameTooltip.SetItemByID, GameTooltip, itemId)
        elseif spellId and GameTooltip.SetSpellByID then
            shown = pcall(GameTooltip.SetSpellByID, GameTooltip, spellId)
        end
        if not shown then
            GameTooltip:SetText(
                entry.name or entry.label or "-",
                1,
                1,
                1,
                1,
                true
            )
        end
        GameTooltip:Show()
    end)
    identityIcon:HookScript("OnLeave", function()
        YUI.HideGameTooltip()
    end)
    local identityTitle = GUI2:CreateText(
        detailPanel, "-", "font.size.md", "color.text.heading", "LEFT"
    )
    identityTitle:SetPoint("TOPLEFT", identityIcon, "TOPRIGHT", 10, 0)
    identityTitle:SetWidth(150)
    local identityType = GUI2:CreateText(
        detailPanel, "-", "font.size.sm", "color.badge.green", "LEFT"
    )
    identityType:SetPoint("LEFT", identityIcon, "RIGHT", 10, 0)
    identityType:SetWidth(150)
    local identityOrigin = GUI2:CreateText(
        detailPanel, "", "font.size.sm", "color.text.muted", "LEFT"
    )
    identityOrigin:SetPoint("LEFT", identityType, "RIGHT", 5, 0)
    identityOrigin:SetWidth(120)
    identityOrigin:SetWordWrap(false)
    identityOrigin:Hide()
    identityType:SetWidth(52)
    local identitySpecial = GUI2:CreateFrame(detailPanel, {
        width = 48,
        height = 18,
        mouse = true,
        hidden = true,
    })
    identitySpecial:SetPoint("LEFT", identityOrigin, "RIGHT", 5, 0)
    identitySpecial.text = GUI2:CreateText(
        identitySpecial,
        T("designer.monitor.special_short", "特殊"),
        "font.size.sm",
        "color.badge.green",
        "LEFT"
    )
    identitySpecial.text:SetAllPoints(identitySpecial)
    identitySpecial:HookScript("OnEnter", function(control)
        if not GameTooltip then return end
        GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
        GameTooltip:SetText(T(
            "designer.monitor.special_tooltip",
            "“特殊”表示该监控使用受限布局通道；\n可以紧凑补位，但只能在同类区域内调整顺序。"
        ), 1, 0.55, 0.12, 1, true)
        GameTooltip:Show()
    end)
    identitySpecial:HookScript("OnLeave", function()
        YUI.HideGameTooltip()
    end)
    local identityPreviewNotice = GUI2:CreateFrame(detailPanel, {
        width = 116,
        height = 46,
        mouse = true,
        hidden = true,
    })
    identityPreviewNotice:SetPoint(
        "TOPRIGHT", detailPanel, "TOPRIGHT", -12, -12
    )
    identityPreviewNotice.text = GUI2:CreateText(
        identityPreviewNotice,
        T(
            "designer.monitor.native_readonly_preview",
            "非当前专精\n仅预览"
        ),
        "font.size.md",
        "color.text.accent",
        "RIGHT"
    )
    identityPreviewNotice.text:SetAllPoints(identityPreviewNotice)
    identityPreviewNotice:HookScript("OnEnter", function(control)
        if not GameTooltip then return end
        GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
        GameTooltip:SetText(T(
            "designer.monitor.native_readonly_preview_tooltip",
            "非当前专精中的暴雪原生监控仅供预览，不能修改。"
        ), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    identityPreviewNotice:HookScript("OnLeave", function()
        YUI.HideGameTooltip()
    end)
    local identityIdLabel = GUI2:CreateText(
        detailPanel,
        T("designer.monitor.id", "ID") .. ":",
        "font.size.md",
        "color.tooltip.id.label",
        "LEFT"
    )
    identityIdLabel:SetPoint("BOTTOMLEFT", identityIcon, "BOTTOMRIGHT", 10, 0)
    local identityDetail = GUI2:CreateText(
        detailPanel, "-", "font.size.md", "color.tooltip.id.value", "LEFT"
    )
    identityDetail:SetPoint("LEFT", identityIdLabel, "RIGHT", 6, 0)
    identityDetail:SetWidth(82)

    local identityEdit = GUI2:CreateIconButton(detailPanel, {
        size = 24,
        icon = SettingsIcon("pencil"),
        padding = 4,
        tooltip = T("designer.monitor.edit_id", "修改监控 ID"),
        onClick = function()
            DesignerUI:BeginMonitorIdentityEdit()
        end,
    })
    identityEdit:SetPoint("LEFT", identityDetail, "RIGHT", 6, 0)

    local identityWarning = GUI2:CreateText(
        detailPanel, "", "font.size.sm", "color.text.warning", "LEFT"
    )
    identityWarning:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 12, -76)
    identityWarning:SetWidth(CONTENT_WIDTH - 24)
    identityWarning:SetHeight(28)
    identityWarning:SetWordWrap(true)
    identityWarning:Hide()

    local identityInput = GUI2.Form:CreateEditBox(detailPanel, {
        width = 112,
        height = 28,
        autoFocus = false,
    })
    identityInput:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 72, -36)
    if identityInput.SetNumeric then identityInput:SetNumeric(true) end
    if identityInput.SetMaxLetters then identityInput:SetMaxLetters(10) end
    identityInput:SetScript("OnTextChanged", function(control, userInput)
        if userInput then
            DesignerUI:PreviewMonitorIdentityEdit(control:GetText())
        end
    end)
    identityInput:SetScript("OnEnterPressed", function()
        DesignerUI:ConfirmMonitorIdentityEdit()
    end)
    identityInput:SetScript("OnEscapePressed", function()
        DesignerUI:CancelMonitorIdentityEdit()
    end)
    identityInput:Hide()

    local identityDurationLabel = GUI2:CreateText(
        detailPanel,
        T("designer.duration_seconds", "持续时间（秒）"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    identityDurationLabel:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 72, -80)
    identityDurationLabel:SetWidth(104)
    identityDurationLabel:SetWordWrap(false)
    identityDurationLabel:Hide()
    local identityDurationInput = GUI2.Form:CreateEditBox(detailPanel, {
        width = 76,
        height = 28,
        autoFocus = false,
    })
    identityDurationInput:SetPoint(
        "TOPLEFT",
        detailPanel,
        "TOPLEFT",
        180,
        -74
    )
    if identityDurationInput.SetMaxLetters then
        identityDurationInput:SetMaxLetters(8)
    end
    identityDurationInput:Hide()

    local identityConfirm = GUI2:CreateIconButton(detailPanel, {
        size = 24,
        icon = SettingsIcon("check"),
        padding = 4,
        tooltip = TC("common.confirm", "确定"),
        onClick = function()
            DesignerUI:ConfirmMonitorIdentityEdit()
        end,
    })
    identityConfirm:SetPoint("LEFT", identityInput, "RIGHT", 6, 0)
    identityConfirm:Hide()
    local identityCancel = GUI2:CreateIconButton(detailPanel, {
        size = 24,
        icon = SettingsIcon("x"),
        padding = 4,
        tooltip = TC("common.cancel", "取消"),
        onClick = function()
            DesignerUI:CancelMonitorIdentityEdit()
        end,
    })
    identityCancel:SetPoint("LEFT", identityConfirm, "RIGHT", 4, 0)
    identityCancel:Hide()

    self.removeMonitorButton:SetScript("OnClick", function()
        DesignerUI:RequestRemoveSelectedMonitor()
    end)

    local emptyState = GUI2:CreatePanel(browser, {
        width = CONTENT_WIDTH,
        height = MONITOR_LIST_PANEL_HEIGHT
            + MONITOR_PANEL_GAP
            + MONITOR_DETAIL_PANEL_HEIGHT,
        surface = "color.surface.panel",
        border = "color.border.default",
    })
    emptyState:SetPoint("TOPLEFT", browser, "TOPLEFT", 0, 0)
    local emptyTitle = GUI2:CreateText(
        emptyState,
        T("designer.monitor.empty_title", "暂无监控"),
        "font.size.lg",
        "color.text.heading",
        "CENTER"
    )
    emptyTitle:SetPoint("CENTER", emptyState, "CENTER", 0, 12)
    local emptyHint = GUI2:CreateText(
        emptyState,
        T("designer.monitor.empty_hint", "使用下方按钮添加技能、物品或光环。"),
        "font.size.md",
        "color.text.secondary",
        "CENTER"
    )
    emptyHint:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -10)
    emptyState:Hide()

    local equipmentTriggerNotice = GUI2:CreatePanel(body, {
        width = CONTENT_WIDTH,
        height = 148,
        surface = "color.surface.sunken",
        border = "color.state.warning",
        hidden = true,
    })
    equipmentTriggerNotice.text = GUI2:CreateText(
        equipmentTriggerNotice,
        "",
        "font.size.md",
        "color.text.warning",
        "LEFT"
    )
    equipmentTriggerNotice.text:SetPoint(
        "TOPLEFT",
        equipmentTriggerNotice,
        "TOPLEFT",
        12,
        -12
    )
    equipmentTriggerNotice.text:SetWidth(CONTENT_WIDTH - 24)
    equipmentTriggerNotice.action = GUI2.Form:CreateButton(
        equipmentTriggerNotice,
        {
            text = T(
                "designer.equipment_trigger.open_settings",
                "打开暴雪冷却设置"
            ),
            width = CONTENT_WIDTH - 24,
            height = 30,
            onClick = function()
                DesignerUI:OpenBlizzardCooldownSettings()
            end,
        }
    )
    equipmentTriggerNotice.action:SetPoint(
        "BOTTOMLEFT",
        equipmentTriggerNotice,
        "BOTTOMLEFT",
        12,
        10
    )
    equipmentTriggerNotice:Hide()

    local bundleEditor = GUI2:CreatePanel(body, {
        width = CONTENT_WIDTH,
        height = 552,
        surface = "color.surface.panel",
        border = "color.border.default",
        hidden = true,
    })
    bundleEditor:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -166)
    bundleEditor:Hide()
    local bundleInnerWidth = CONTENT_WIDTH - 20
    local bundleDropdownGap = 8
    local bundleDropdownWidth =
        (bundleInnerWidth - bundleDropdownGap) / 2

    local function ReadBundleContexts()
        if not bundleEditor.bundleKind then return {}, nil end
        local contexts, selected = Designer:GetSpellBundleContexts(
            bundleEditor.bundleKind
        )
        return contexts or {}, selected
    end

    local bundleClassContext = GUI2.Form:CreateDropdown(bundleEditor, {
        width = bundleDropdownWidth,
        height = 30,
        options = function()
            local contexts = ReadBundleContexts()
            local options = {}
            local seen = {}
            local Icons = YUI.API and YUI.API.Icons
            for index = 1, #(contexts or {}) do
                local context = contexts[index]
                if context.classFile and not seen[context.classFile] then
                    seen[context.classFile] = true
                    options[#options + 1] = {
                        text = context.className or context.classFile,
                        value = context.classFile,
                        iconData = Icons and Icons.GetClassIcon
                            and Icons.GetClassIcon(context.classFile) or nil,
                        iconSize = 20,
                    }
                end
            end
            return options
        end,
        set = function(value)
            if DesignerUI.v2Refreshing
                or not bundleEditor.bundleKind
                or bundleEditor.bundleKind == "racial" then
                return
            end
            local contexts = ReadBundleContexts()
            local selectedContext
            for index = 1, #contexts do
                if contexts[index].classFile == value then
                    selectedContext = contexts[index]
                    break
                end
            end
            if selectedContext and Designer:SetSpellBundleContext(
                bundleEditor.bundleKind,
                selectedContext.value
            ) then
                DesignerUI:Refresh(false, false)
            end
        end,
    })
    bundleClassContext:SetPoint(
        "TOPLEFT",
        bundleEditor,
        "TOPLEFT",
        10,
        -10
    )

    local bundleSpecContext = GUI2.Form:CreateSpecDropdown(bundleEditor, {
        width = bundleDropdownWidth,
        height = 30,
        specs = function()
            local contexts, selected = ReadBundleContexts()
            local selectedClass = selected and selected:match("^([^:]+):")
            local options = {}
            for index = 1, #contexts do
                local context = contexts[index]
                if context.classFile == selectedClass then
                    options[#options + 1] = {
                        text = context.specName,
                        name = context.specName,
                        value = context.value,
                        specID = context.specID,
                        specIndex = context.specIndex,
                        classFile = context.classFile,
                        icon = context.icon,
                    }
                end
            end
            return options
        end,
        set = function(value)
            if DesignerUI.v2Refreshing
                or not bundleEditor.bundleKind
                or bundleEditor.bundleKind == "racial" then
                return
            end
            if Designer:SetSpellBundleContext(
                bundleEditor.bundleKind,
                value
            ) then
                DesignerUI:Refresh(false, false)
            end
        end,
    })
    bundleSpecContext:SetPoint(
        "TOPLEFT",
        bundleClassContext,
        "TOPRIGHT",
        bundleDropdownGap,
        0
    )

    local bundleRaceContext = GUI2.Form:CreateRaceDropdown(bundleEditor, {
        width = bundleInnerWidth,
        height = 30,
        races = function()
            local contexts = ReadBundleContexts()
            local options = {}
            for index = 1, #contexts do
                local context = contexts[index]
                options[index] = {
                    text = context.text,
                    name = context.text,
                    value = context.value,
                    raceID = context.raceID,
                    raceFile = context.raceFile,
                }
            end
            return options
        end,
        set = function(value)
            if DesignerUI.v2Refreshing
                or bundleEditor.bundleKind ~= "racial" then
                return
            end
            if Designer:SetSpellBundleContext("racial", value) then
                DesignerUI:Refresh(false, false)
            end
        end,
    })
    bundleRaceContext:SetPoint(
        "TOPLEFT",
        bundleEditor,
        "TOPLEFT",
        10,
        -10
    )
    bundleEditor.classContext = bundleClassContext
    bundleEditor.specContext = bundleSpecContext
    bundleEditor.raceContext = bundleRaceContext
    bundleEditor.context = bundleSpecContext
    bundleEditor.rows = {}
    for index = 1, 32 do
        local row = GUI2:CreatePanel(bundleEditor, {
            width = bundleInnerWidth,
            height = 34,
            surface = "color.surface.sunken",
            border = "color.border.subtle",
        })
        row:SetPoint("TOPLEFT", 10, -48 - ((index - 1) * 38))
        row.icon = GUI2:CreateIconSlot(row, {
            size = 26,
            icon = QUESTION_ICON,
            crop = true,
            shape = "square",
            border = "thin",
        })
        row.icon:SetPoint("LEFT", 6, 0)
        row.icon:HookScript("OnEnter", function(control)
            if not (row.tooltipSpellID and GameTooltip) then return end
            GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
            if GameTooltip.SetSpellByID then
                pcall(
                    GameTooltip.SetSpellByID,
                    GameTooltip,
                    row.tooltipSpellID
                )
            else
                GameTooltip:SetText(row.label:GetText() or "-")
            end
            GameTooltip:Show()
        end)
        row.icon:HookScript("OnLeave", function()
            YUI.HideGameTooltip()
        end)
        row.label = GUI2:CreateText(
            row,
            "",
            "font.size.md",
            "color.text.primary",
            "LEFT"
        )
        row.label:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
        row.label:SetWidth(174)
        row.switch = GUI2.Form:CreateSwitch(row, {
            width = 42,
            height = 22,
            set = function(value)
                if DesignerUI.v2Refreshing
                    or not row.spellID
                    or not row.bundleKind then
                    return
                end
                local ok, code = Designer:SetSpellBundleEnabled(
                    row.bundleKind,
                    row.spellID,
                    value == true
                )
                if ok then
                    DesignerUI:ApplyPreview()
                    DesignerUI:Refresh(false, false)
                else
                    DesignerUI:SetMutationError(
                        code,
                        "designer.error_update",
                        "无法修改监控。"
                    )
                end
            end,
        })
        row.switch:SetPoint("RIGHT", -8, 0)
        row.moveDown = GUI2.Form:CreateButton(row, {
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
                if row.spellID and row.bundleKind and row.bundleIndex then
                    local order = Designer:MoveSpellBundleSpell(
                        row.bundleKind,
                        row.spellID,
                        row.bundleIndex + 1
                    )
                    if order then
                        DesignerUI:ApplyPreview()
                        DesignerUI:Refresh(false, false)
                    end
                end
            end,
        })
        row.moveDown:SetPoint("RIGHT", row.switch, "LEFT", -4, 0)
        row.moveUp = GUI2.Form:CreateButton(row, {
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
                if row.spellID and row.bundleKind and row.bundleIndex then
                    local order = Designer:MoveSpellBundleSpell(
                        row.bundleKind,
                        row.spellID,
                        row.bundleIndex - 1
                    )
                    if order then
                        DesignerUI:ApplyPreview()
                        DesignerUI:Refresh(false, false)
                    end
                end
            end,
        })
        row.moveUp:SetPoint("RIGHT", row.moveDown, "LEFT", -4, 0)
        row:Hide()
        bundleEditor.rows[index] = row
    end

    browser.previous = previous
    browser.next = nextButton
    browser.pageText = pageText
    browser.identityIcon = identityIcon
    browser.identityTitle = identityTitle
    browser.identityType = identityType
    browser.identityOrigin = identityOrigin
    browser.identitySpecial = identitySpecial
    browser.identityPreviewNotice = identityPreviewNotice
    browser.identityWarning = identityWarning
    browser.identityIdLabel = identityIdLabel
    browser.identityDetail = identityDetail
    browser.identityEdit = identityEdit
    browser.identityInput = identityInput
    browser.identityDurationLabel = identityDurationLabel
    browser.identityDurationInput = identityDurationInput
    browser.identityConfirm = identityConfirm
    browser.identityCancel = identityCancel
    browser.summary = summary
    browser.nativePreviewStatus = summary.nativePreviewStatus
    browser.listPanel = listPanel
    browser.detailPanel = detailPanel
    browser.emptyState = emptyState
    local auraOverrideLabel = GUI2:CreateText(
        body,
        T("designer.monitor.aura_timer", "技能光环计时"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    local auraOverrideStatus = GUI2:CreateText(
        body, "", "font.size.md", "color.text.warning", "RIGHT"
    )
    local auraOverride = GUI2.Form:CreateDropdown(body, {
        width = CONTENT_WIDTH,
        height = 30,
        options = function()
            local profile = Designer:GetProfile()
            local enabled = not (profile and profile.cdm
                and profile.cdm.skillAuraDisplay == false)
            return {
                {
                    value = "inherit",
                    text = enabled
                        and T("designer.monitor.skill_aura_inherit_on", "使用全局设置：开启")
                        or T("designer.monitor.skill_aura_inherit_off", "使用全局设置：关闭"),
                },
                { value = "enabled", text = T("designer.monitor.skill_aura_on", "单项开启") },
                { value = "disabled", text = T("designer.monitor.skill_aura_off", "单项关闭") },
            }
        end,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            local override
            if value == "enabled" then
                override = true
            elseif value == "disabled" then
                override = false
            elseif value ~= "inherit" then
                return
            end
            if Designer:SetMonitorSkillAuraDisplayOverride(nil, override) ~= nil then
                DesignerUI:ApplyPreview()
                DesignerUI:Refresh(false, false)
            end
        end,
    })
    local visibilityLabel = GUI2:CreateText(
        body,
        T("designer.monitor.visibility_mode", "显示模式"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    local visibilityDropdown = GUI2.Form:CreateDropdown(body, {
        width = CONTENT_WIDTH,
        height = 30,
        options = function()
            return {
                {
                    value = "active",
                    text = T("designer.monitor.visibility_active", "激活显示"),
                },
                {
                    value = "always",
                    text = T("designer.monitor.visibility_always", "始终显示"),
                },
            }
        end,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            if Designer:SetMonitorVisibilityMode(nil, value) ~= nil then
                DesignerUI:ApplyPreview()
                DesignerUI:Refresh(false, false)
            end
        end,
    })
    local visibilityLayoutInfo = GUI2.Form:CreateIconButton(body, {
        size = 26,
        icon = SettingsIcon("info"),
    })
    visibilityLayoutInfo:SetScript("OnEnter", function(control)
        if not GameTooltip then return end
        local reason = control and control.yhudProjectionReason
        local reasonText = DesignerUI:GetFixedLayoutReasonText(reason)
        GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
        GameTooltip:SetText(string.format(
            T(
                "designer.monitor.visibility_fixed_tooltip",
                "当前分组的排列方式为“固定位置”。原因：%s。是否来自原生监控不影响此判断；“激活显示”的项目未激活时会隐藏，但会保留位置。"
            ),
            reasonText
        ), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    visibilityLayoutInfo:SetScript("OnLeave", function()
        YUI.HideGameTooltip()
    end)
    visibilityLayoutInfo:Hide()
    local effectsButton = GUI2.Form:CreateButton(body, {
        text = TC("common.compact.display", "显示"),
        tooltip = T("designer.monitor.display_settings", "显示设置"),
        width = MONITOR_EFFECTS_ACTION_WIDTH,
        height = MONITOR_EFFECTS_ACTION_HEIGHT,
        onClick = function()
            DesignerUI:CancelMonitorIdentityEdit(true)
            DesignerUI.monitorSoundEditing = false
            DesignerUI.monitorEffectsEditing = true
            DesignerUI:Refresh(false, false)
        end,
    })
    ApplySolidMonitorButton(
        effectsButton,
        "color.badge.orange",
        "color.state.warning"
    )
    local soundButton = GUI2.Form:CreateButton(body, {
        text = TC("common.compact.sound", "声音"),
        tooltip = T("designer.monitor.sound_settings", "声音设置"),
        width = MONITOR_EFFECTS_ACTION_WIDTH,
        height = MONITOR_SOUND_UI.actionHeight,
        onClick = function()
            DesignerUI:CancelMonitorIdentityEdit(true)
            DesignerUI.monitorEffectsEditing = false
            DesignerUI.monitorSoundEditing = true
            DesignerUI:Refresh(false, false)
        end,
    })
    ApplySolidMonitorButton(
        soundButton,
        "color.badge.purple",
        "color.badge.purple"
    )
    local replicationButton = GUI2.Form:CreateButton(body, {
        text = T("designer.replication.open.short", "复制"),
        tooltip = T("designer.replication.open", "复制 / 同步"),
        width = MONITOR_EFFECTS_ACTION_WIDTH,
        height = MONITOR_SOUND_UI.actionHeight,
        onClick = function()
            DesignerUI:CancelMonitorIdentityEdit(true)
            local opened, code = DesignerUI:ShowReplicationDialog()
            if not opened then
                DesignerUI:SetStatus(T(
                    "designer.replication.unavailable",
                    "该监控不能复制或同步。"
                ) .. " (" .. tostring(code or "unknown") .. ")")
            end
        end,
    })
    ApplySolidMonitorButton(
        replicationButton,
        "color.badge.green",
        "color.state.success"
    )
    local effectsTitle = GUI2:CreateText(
        body,
        T("designer.monitor.display_settings", "显示设置"),
        "font.size.lg",
        "color.text.heading",
        "LEFT"
    )
    local effectsBack = GUI2.Form:CreateButton(body, {
        text = TC("common.back", "返回"),
        width = 68,
        height = 30,
        onClick = function()
            HideMonitorEffectsPage(DesignerUI)
            DesignerUI.monitorEffectsEditing = false
            DesignerUI:Refresh(false, false)
        end,
    })
    local soundTitle = GUI2:CreateText(
        body,
        T("designer.sound.title", "声音设置"),
        "font.size.lg",
        "color.text.heading",
        "LEFT"
    )
    local soundBack = GUI2.Form:CreateButton(body, {
        text = TC("common.back", "返回"),
        width = 68,
        height = 30,
        onClick = function()
            I.HideMonitorSoundPage(DesignerUI)
            DesignerUI.monitorSoundEditing = false
            DesignerUI:Refresh(false, false)
        end,
    })
    local soundRulesDivider = AddSectionHeading(
        body,
        T("designer.sound.rules", "声音规则")
    )
    local soundRuleCount = GUI2:CreateText(
        body,
        "0/0",
        "font.size.md",
        "color.text.secondary",
        "LEFT"
    )
    local soundRules = {}
    for index = 1, 2 do
        local row = GUI2:CreatePanel(body, {
            width = CONTENT_WIDTH,
            height = MONITOR_SOUND_UI.ruleHeight,
            surface = "color.surface.panel",
            border = "color.border.default",
            hidden = true,
        })
        row.index = index
        row.condition = GUI2.Form:CreateDropdown(row, {
            width = 116,
            height = 28,
            options = function()
                local _, _, capabilities = I.SelectedSoundContext()
                local options = {}
                for conditionIndex = 1,
                    #(capabilities and capabilities.conditions or {}) do
                    local conditionType =
                        capabilities.conditions[conditionIndex]
                    options[#options + 1] = {
                        value = conditionType,
                        text = I.SoundConditionText(conditionType, capabilities),
                    }
                end
                return options
            end,
            set = function(value)
                if DesignerUI.v2Refreshing then return end
                local _, monitor = I.SelectedSoundContext()
                if not monitor then return end
                local config = I.CopySelectedSoundRules(monitor)
                local rule = config.rules[row.index]
                if not rule then return end
                local oldType = rule.condition and rule.condition.type
                if value == oldType then return end
                for otherIndex = 1, #config.rules do
                    if otherIndex ~= row.index then
                        local other = config.rules[otherIndex]
                        if other.condition
                            and other.condition.type == value then
                            other.condition = { type = oldType }
                            break
                        end
                    end
                end
                rule.condition = { type = value }
                FinishGlowMutation(
                    Designer:SetMonitorSound(monitor.id, config)
                )
            end,
        })
        row.condition:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.sound = GUI2.SoundPicker:CreateSelector(row, {
            width = 142,
            height = 28,
            allowNone = true,
            get = function()
                local _, monitor = I.SelectedSoundContext()
                local rule = monitor and monitor.sound
                    and monitor.sound.rules
                    and monitor.sound.rules[row.index]
                return rule and rule.sound or nil
            end,
            set = function(value)
                if DesignerUI.v2Refreshing then return end
                local _, monitor = I.SelectedSoundContext()
                if not monitor then return end
                local config = I.CopySelectedSoundRules(monitor)
                local rule = config.rules[row.index]
                if not rule then return end
                rule.sound = value
                FinishGlowMutation(
                    Designer:SetMonitorSound(monitor.id, config)
                )
            end,
        })
        row.sound:SetPoint("LEFT", row.condition, "RIGHT", 6, 0)
        row.preview = GUI2.Form:CreateButton(row, {
            text = T("designer.sound.preview", "试听"),
            width = 52,
            height = 28,
            onClick = function()
                local _, monitor = I.SelectedSoundContext()
                local rule = monitor and monitor.sound
                    and monitor.sound.rules
                    and monitor.sound.rules[row.index]
                local key = rule and rule.sound
                if key and YUI.Sound and YUI.Sound.Play then
                    YUI.Sound:Play(key, nil, 0)
                end
            end,
        })
        row.preview:SetPoint("LEFT", row.sound, "RIGHT", 6, 0)
        row.delete = GUI2.Form:CreateIconButton(row, {
            size = 26,
            icon = SettingsIcon("trash-2"),
            tooltip = T("designer.sound.delete_rule", "删除声音规则"),
            onClick = function()
                local _, monitor = I.SelectedSoundContext()
                if not monitor then return end
                local config = I.CopySelectedSoundRules(monitor)
                table.remove(config.rules, row.index)
                FinishGlowMutation(
                    Designer:SetMonitorSound(
                        monitor.id,
                        #config.rules > 0 and config or nil
                    )
                )
            end,
        })
        row.delete:SetPoint("LEFT", row.preview, "RIGHT", 4, 0)
        soundRules[index] = row
    end
    local soundAddRule = GUI2.Form:CreateButton(body, {
        text = T("designer.sound.add_rule", "+ 添加规则"),
        width = 104,
        height = 30,
        onClick = function()
            local _, monitor, capabilities = I.SelectedSoundContext()
            if not (monitor and capabilities) then return end
            local config = I.CopySelectedSoundRules(monitor)
            local used = {}
            for ruleIndex = 1, #config.rules do
                local condition = config.rules[ruleIndex].condition
                if condition then used[condition.type] = true end
            end
            local conditionType
            for conditionIndex = 1, #(capabilities.conditions or {}) do
                local candidate = capabilities.conditions[conditionIndex]
                if not used[candidate] then
                    conditionType = candidate
                    break
                end
            end
            if not conditionType then return end
            config.rules[#config.rules + 1] = {
                condition = { type = conditionType },
            }
            FinishGlowMutation(
                Designer:SetMonitorSound(monitor.id, config)
            )
        end,
    })
    local selectedEffectsDivider = AddSectionHeading(
        body,
        "-",
        QUESTION_ICON
    )
    local auraHighlightLabel = GUI2:CreateText(
        body,
        T("designer.monitor.aura_highlight", "激活提示"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    local inactiveDesaturateLabel = GUI2:CreateText(
        body,
        T("designer.monitor.inactive_desaturate", "非激活褪色"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    local function EffectOptions(key)
        local _, selectedProfile = SelectedContext()
        local globalField = key == "auraHighlight"
            and "skillAuraHighlight" or key == "assistedHighlight"
                and "assistedHighlight" or "inactiveDesaturate"
        local cdm = selectedProfile and selectedProfile.cdm
        local effective = key == "assistedHighlight" and YHUD:GetConsolePreference("assistedHighlight")
            or key ~= "assistedHighlight" and not (type(cdm) == "table" and cdm[globalField] == false)
        return {
            {
                value = "inherit",
                text = effective
                    and T("designer.monitor.effect_default_on", "使用全局设置：开启")
                    or T("designer.monitor.effect_default_off", "使用全局设置：关闭"),
            },
            {
                value = "enabled",
                text = T("designer.monitor.effect_on", "开启"),
            },
            {
                value = "disabled",
                text = T("designer.monitor.effect_off", "关闭"),
            },
        }
    end
    local function CreateEffectDropdown(key)
        return GUI2.Form:CreateDropdown(body, {
            width = CONTENT_WIDTH,
            tooltip = key == "assistedHighlight" and T("designer.monitor.assisted_highlight_tip") or nil,
            height = 30,
            options = function()
                return EffectOptions(key)
            end,
            set = function(value)
                if DesignerUI.v2Refreshing then return end
                local override
                if value == "enabled" then
                    override = true
                elseif value == "disabled" then
                    override = false
                elseif value ~= "inherit" then
                    return
                end
                if Designer:SetMonitorStateEffect(nil, key, override) ~= nil then
                    DesignerUI:ApplyPreview()
                    DesignerUI:Refresh(false, false)
                end
            end,
        })
    end
    local auraHighlightDropdown = CreateEffectDropdown("auraHighlight")
    local inactiveDesaturateDropdown =
        CreateEffectDropdown("inactiveDesaturate")
    local resetEffects = GUI2.Form:CreateButton(body, {
        text = T("designer.monitor.reset_effects", "恢复单项默认"),
        width = CONTENT_WIDTH,
        height = 32,
        onClick = function()
            local effectsResult = Designer:ResetMonitorStateEffects()
            local swipeResult
            if DesignerUI.monitorResetIncludesSwipe then
                swipeResult = Designer:SetMonitorAppearanceOverride(nil, {
                    cooldownSwipeMode = "inherit",
                })
            end
            if effectsResult ~= nil or swipeResult ~= nil then
                DesignerUI:ApplyPreview()
                DesignerUI:Refresh(false, false)
            end
        end,
    })
    local monitorGlowDivider = AddSectionHeading(
        body,
        T("designer.glow.section", "Glow")
    )
    local monitorAssistedLabel = GUI2:CreateText(
        body, T("designer.monitor.assisted_highlight", "辅助提示"),
        "font.size.md", "color.text.primary", "LEFT"
    )
    local monitorAssistedDropdown = CreateEffectDropdown("assistedHighlight")
    local monitorNativeLabel = GUI2:CreateText(
        body,
        T("designer.glow.native_proc", "Native Proc Glow"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    local function MonitorNativeOptions()
        local profile = Designer:GetProfile()
        local global = profile and profile.style
            and profile.style.nativeProcGlow or nil
        local options = {
            {
                value = "inherit",
                text = string.format(
                    T(
                        "designer.glow.native_inherit",
                        "Use Global Setting: %s"
                    ),
                    NativeGlowStyleText(global)
                ),
            },
        }
        local nativeOptions = BuildNativeGlowStyleOptions()
        for index = 1, #nativeOptions do
            options[#options + 1] = nativeOptions[index]
        end
        return options
    end
    local monitorNativeDropdown = GUI2.Form:CreateDropdown(body, {
        width = MONITOR_GLOW_DROPDOWN_WIDTH,
        height = MONITOR_SIDE_CONTROL_HEIGHT,
        options = MonitorNativeOptions,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            local profile, monitor = SelectedGlowContext()
            if not (profile and monitor) then return end
            if value == "inherit" then
                return FinishGlowMutation(
                    Designer:SetMonitorNativeProcGlowOverride(
                        monitor.id,
                        nil
                    )
                )
            end
            local current = YHUD:CopyValue(
                monitor.nativeProcGlowOverride
                    or YHUD:GetEffectiveNativeProcGlow(profile, monitor)
            )
            if value == "default" or value == "disabled" then
                current.mode = value
                current.appearance = nil
            else
                current.mode = "custom"
                current.appearance = type(current.appearance) == "table"
                    and current.appearance
                    or YHUD:GetDefaultMonitorGlowAppearance()
                current.appearance.style = value
            end
            FinishGlowMutation(
                Designer:SetMonitorNativeProcGlowOverride(
                    monitor.id,
                    current
                )
            )
        end,
    })
    local monitorNativeGear = GUI2.Form:CreateIconButton(body, {
        size = MONITOR_GLOW_GEAR_SIZE,
        icon = SettingsIcon("settings"),
        tooltip = T("designer.glow.edit_appearance", "Edit glow appearance"),
        onClick = function()
            DesignerUI:OpenGlowAppearanceEditor("monitor-native")
        end,
    })
    local monitorNativeCombatLabel = GUI2:CreateText(
        body,
        T("designer.glow.native_combat_only", "Native Glow Combat Only"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    local monitorNativeCombat = GUI2.Form:CreateSwitch(body, {
        width = 48,
        height = MONITOR_SIDE_CONTROL_HEIGHT,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            local profile, monitor = SelectedGlowContext()
            if not (profile and monitor) then return end
            local current = YHUD:CopyValue(
                monitor.nativeProcGlowOverride
                    or YHUD:GetEffectiveNativeProcGlow(profile, monitor)
            )
            current.combatOnly = value == true and true or nil
            FinishGlowMutation(
                Designer:SetMonitorNativeProcGlowOverride(
                    monitor.id,
                    current
                )
            )
        end,
    })
    local monitorGlowRulesDivider = AddSectionHeading(
        body,
        T("designer.glow.rules", "Custom Glow Rules")
    )
    local monitorGlowRuleCount = GUI2:CreateText(
        body,
        "0/2",
        "font.size.md",
        "color.text.secondary",
        "RIGHT"
    )
    local monitorGlowRules = {}
    self.monitorGlowPriorityText = GUI2:CreateText(body,
        T("designer.glow.priority", "Top to bottom: only the first matching rule glows."),
        "font.size.sm", "color.text.secondary", "LEFT")
    self.monitorGlowPriorityText:SetWidth(CONTENT_WIDTH)
    self.monitorGlowPriorityText:SetHeight(30)
    self.monitorGlowPriorityText:Hide()
    for index = 1, YHUD.MAX_MONITOR_GLOW_RULES do
        local row = GUI2:CreatePanel(body, {
            width = CONTENT_WIDTH,
            height = MONITOR_GLOW_RULE_HEIGHT,
            surface = "color.surface.panel",
            border = "color.border.default",
            hidden = true,
        })
        row.index = index
        row.title = GUI2:CreateText(
            row,
            string.format(
                T("designer.glow.rule_title", "Custom Glow Rule %d"),
                index
            ),
            "font.size.md",
            "color.text.heading",
            "LEFT"
        )
        row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -10)
        row.title:SetWidth(CONTENT_WIDTH - 146)
        row.delete = GUI2.Form:CreateIconButton(row, {
            size = 24,
            icon = SettingsIcon("trash-2"),
            tooltip = T("designer.glow.delete_rule", "Delete this glow rule"),
            onClick = function()
                local _, monitor = SelectedGlowContext()
                if not monitor then return end
                FinishOpenColorPicker("cancel")
                DesignerUI:HideGlowEditor()
                local config = CopySelectedGlowRules(monitor)
                table.remove(config.rules, row.index)
                FinishGlowMutation(
                    Designer:SetMonitorGlow(
                        monitor.id,
                        #config.rules > 0 and config or nil
                    )
                )
            end,
        })
        row.delete:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -6)
        row.down = GUI2.Form:CreateButton(row, {
            width = 24, height = 24, text = "↓", tone = "default",
            tooltip = T("designer.glow.move_down", "Move down (lower priority)"),
            onClick = function()
                FinishOpenColorPicker("cancel")
                DesignerUI:MoveGlowRule(row.index, 1)
            end,
        })
        row.down:SetPoint("RIGHT", row.delete, "LEFT", -4, 0)
        row.up = GUI2.Form:CreateButton(row, {
            width = 24, height = 24, text = "↑", tone = "default",
            tooltip = T("designer.glow.move_up", "Move up (higher priority)"),
            onClick = function()
                FinishOpenColorPicker("cancel")
                DesignerUI:MoveGlowRule(row.index, -1)
            end,
        })
        row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)
        local function FinishColorPreview()
            local view = YHUD.View
            if view and view.SetDesignGlowPreview then
                view:SetDesignGlowPreview(nil, nil, nil)
            end
            DesignerUI:SyncGlowAppearancePreview()
        end
        row.color = GUI2.Form:CreateColorPicker(row, {
            width = 28, height = 24, hasAlpha = true,
            getDefault = function() return YHUD:GetDefaultMonitorGlowAppearance().color end,
            preview = function(value)
                if DesignerUI.v2Refreshing then return end
                local _, monitor = SelectedGlowContext()
                if not monitor or monitor.id ~= row.stackMonitorId then return end
                local rule = monitor.glow and monitor.glow.rules
                    and monitor.glow.rules[row.index]
                local view = YHUD.View
                if not (rule and view and view.SetDesignGlowPreview) then return end
                local appearance = YHUD:CopyValue(rule.appearance)
                appearance.color = YHUD:CopyValue(value)
                view:SetDesignGlowPreview(monitor.id, monitor.groupId, appearance)
            end,
            commit = function(value)
                FinishColorPreview()
                if DesignerUI.v2Refreshing then return end
                local _, monitor = SelectedGlowContext()
                if not monitor or monitor.id ~= row.stackMonitorId then return end
                local config = CopySelectedGlowRules(monitor)
                local rule = config.rules[row.index]
                if not rule then return end
                rule.appearance.color = YHUD:CopyValue(value)
                if FinishGlowMutation(Designer:SetMonitorGlow(monitor.id, config)) then
                    DesignerUI:RefreshGlowEditor(true)
                end
            end,
            cancel = FinishColorPreview,
        })
        row.color:SetPoint("RIGHT", row.up, "LEFT", -8, 0)
        row.condition = GUI2.Form:CreateDropdown(row, {
            width = 158,
            height = 28,
            options = function()
                local _, monitor, capabilities = SelectedGlowContext()
                local rules = monitor and monitor.glow
                    and monitor.glow.rules or {}
                local options = {}
                for conditionIndex = 1,
                    #(capabilities and capabilities.conditions or {}) do
                    local conditionType =
                        capabilities.conditions[conditionIndex]
                    if YHUD:CanAddGlowCondition(rules, conditionType, row.index) then
                        options[#options + 1] = {
                            value = conditionType,
                            text = GlowConditionText(conditionType, capabilities),
                        }
                    end
                end
                return options
            end,
            set = function(value)
                if DesignerUI.v2Refreshing then return end
                local _, monitor = SelectedGlowContext()
                if not monitor then return end
                local config = CopySelectedGlowRules(monitor)
                local rule = config.rules[row.index]
                if not rule then return end
                if rule.condition and rule.condition.type == value then return end
                rule.condition = value == "aura-stacks"
                    and YHUD:GetNextAuraStackCondition(config.rules, row.index) or { type = value }
                FinishGlowMutation(
                    Designer:SetMonitorGlow(monitor.id, config)
                )
            end,
        })
        row.condition:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -38)
        row.condition:HookScript("OnEnter", function(control)
            if control:GetValue() == "aura-stacks" and GameTooltip then
                GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
                GameTooltip:SetText(T("designer.glow.stack_priority_tooltip",
                    "Rules are checked from top to bottom. Only the first matching rule glows; use the arrows to change priority."),
                    1, 1, 1, 1, true)
                GameTooltip:Show()
                return
            end
            if control:GetValue() ~= "self-ready" or not GameTooltip then
                return
            end
            GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
            local _, _, capabilities = SelectedGlowContext()
            local itemReady = capabilities
                and capabilities.labelKind == "item"
            GameTooltip:SetText(
                T(
                    itemReady and "designer.glow.item_ready_tooltip"
                        or "designer.glow.self_ready_tooltip",
                    itemReady
                        and "Ready means the item is owned and has no active cooldown."
                        or "Ready means the spell has no active cooldown and no charge is currently recovering."
                ),
                1,
                1,
                1,
                1,
                true
            )
            GameTooltip:Show()
        end)
        row.style = GUI2.Form:CreateDropdown(row, {
            width = 148,
            height = 28,
            options = BuildGlowStyleOptions,
            set = function(value)
                if DesignerUI.v2Refreshing then return end
                local _, monitor = SelectedGlowContext()
                if not monitor then return end
                local config = CopySelectedGlowRules(monitor)
                local rule = config.rules[row.index]
                if not rule then return end
                rule.appearance = type(rule.appearance) == "table"
                    and rule.appearance
                    or YHUD:GetDefaultMonitorGlowAppearance()
                rule.appearance.style = value
                if FinishGlowMutation(Designer:SetMonitorGlow(monitor.id, config)) then
                    DesignerUI:RefreshGlowEditor(true)
                end
            end,
        })
        row.style:SetPoint("LEFT", row.condition, "RIGHT", 8, 0)
        row.gear = GUI2.Form:CreateIconButton(row, {
            size = MONITOR_GLOW_GEAR_SIZE,
            icon = SettingsIcon("settings"),
            tooltip = T("designer.glow.edit_appearance", "Edit glow appearance"),
            onClick = function()
                DesignerUI:OpenGlowAppearanceEditor("rule", row.index)
            end,
        })
        row.gear:SetPoint("LEFT", row.style, "RIGHT", 6, 0)
        row.stackLabel = GUI2:CreateText(row,
            T("designer.glow.stack_threshold", "Stacks (1–100)"),
            "font.size.md", "color.text.primary", "LEFT")
        row.stackLabel:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -80)
        row.stackOperator = GUI2.Form:CreateDropdown(row, {
            width = 64, height = 26,
            options = {
                { value = "lt", text = "<" }, { value = "lte", text = "≤" },
                { value = "eq", text = "=" }, { value = "gte", text = "≥" },
                { value = "gt", text = ">" },
            },
            set = function(value)
                if DesignerUI.v2Refreshing then return end
                local _, monitor = SelectedGlowContext()
                if not monitor then return end
                local config = CopySelectedGlowRules(monitor)
                local rule = config.rules[row.index]
                if not (rule and rule.condition.type == "aura-stacks") then return end
                rule.condition.operator = value
                FinishGlowMutation(Designer:SetMonitorGlow(monitor.id, config))
            end,
        })
        row.stackOperator:SetPoint("TOPLEFT", row, "TOPLEFT", 176, -72)
        row.stackValue = GUI2.Form:CreateEditBox(row, {
            width = 110, height = 26, autoFocus = false,
        })
        row.stackValue:SetPoint("LEFT", row.stackOperator, "RIGHT", 8, 0)
        row.stackValue:SetNumeric(true)
        row.stackValue:SetMaxLetters(3)
        local function CommitStackValue(input)
            if DesignerUI.v2Refreshing then return end
            local _, monitor = SelectedGlowContext()
            if not monitor or monitor.id ~= row.stackMonitorId then return end
            local config = CopySelectedGlowRules(monitor)
            local rule = config.rules[row.index]
            if not (rule and rule.condition.type == "aura-stacks") then return end
            local value = tonumber(input:GetText())
            if not value or value < 1 or value > 100 or value ~= math.floor(value) then
                input:SetText(tostring(rule.condition.value))
                return
            end
            if value == rule.condition.value then return end
            rule.condition.value = value
            FinishGlowMutation(Designer:SetMonitorGlow(monitor.id, config))
        end
        row.stackValue:SetScript("OnEnterPressed", function(input)
            CommitStackValue(input)
            input:ClearFocus()
        end)
        row.stackValue:HookScript("OnEditFocusLost", CommitStackValue)
        row.combatLabel = GUI2:CreateText(
            row,
            T("designer.glow.combat_only", "Combat Only"),
            "font.size.md",
            "color.text.primary",
            "LEFT"
        )
        row.combatLabel:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 8)
        row.combat = GUI2.Form:CreateSwitch(row, {
            width = 48,
            height = 26,
            set = function(value)
                if DesignerUI.v2Refreshing then return end
                local _, monitor = SelectedGlowContext()
                if not monitor then return end
                local config = CopySelectedGlowRules(monitor)
                local rule = config.rules[row.index]
                if not rule then return end
                rule.combatOnly = value == true and true or nil
                FinishGlowMutation(
                    Designer:SetMonitorGlow(monitor.id, config)
                )
            end,
        })
        row.combat:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 4)
        monitorGlowRules[index] = row
    end
    local monitorGlowAuraWarning = GUI2:CreatePanel(body, {
        width = CONTENT_WIDTH,
        height = 46,
        surface = "color.surface.sunken",
        border = "color.state.warning",
        hidden = true,
    })
    monitorGlowAuraWarning.text = GUI2:CreateText(
        monitorGlowAuraWarning,
        T(
            "designer.glow.aura_missing_requires_always",
            "Aura Missing requires Always Show."
        ),
        "font.size.md",
        "color.text.warning",
        "LEFT"
    )
    monitorGlowAuraWarning.text:SetPoint(
        "LEFT",
        monitorGlowAuraWarning,
        "LEFT",
        10,
        0
    )
    monitorGlowAuraWarning.text:SetWidth(214)
    monitorGlowAuraWarning.action = GUI2.Form:CreateButton(
        monitorGlowAuraWarning,
        {
            text = T("designer.glow.set_always", "Set to Always Show"),
            width = 132,
            height = 28,
            onClick = function()
                local _, monitor = SelectedGlowContext()
                if not monitor then return end
                FinishGlowMutation(
                    Designer:SetMonitorVisibilityMode(
                        monitor.id,
                        "always"
                    )
                )
            end,
        }
    )
    monitorGlowAuraWarning.action:SetPoint(
        "RIGHT",
        monitorGlowAuraWarning,
        "RIGHT",
        -8,
        0
    )
    local monitorGlowAddRule = GUI2.Form:CreateButton(body, {
        text = T("designer.glow.add_rule", "+ New Custom Glow Rule"),
        width = CONTENT_WIDTH,
        height = 32,
        onClick = function()
            local _, monitor, capabilities = SelectedGlowContext()
            if not (monitor and capabilities) then return end
            local config = CopySelectedGlowRules(monitor)
            if #config.rules >= YHUD:GetMonitorGlowRuleLimit(capabilities) then return end
            local conditionType
            for index = 1, #config.rules do
                if config.rules[index].condition.type == "aura-stacks" then
                    conditionType = "aura-stacks"
                    break
                end
            end
            for conditionIndex = 1, #(capabilities.conditions or {}) do
                if conditionType then break end
                local candidate = capabilities.conditions[conditionIndex]
                if YHUD:CanAddGlowCondition(config.rules, candidate) then
                    conditionType = candidate
                    break
                end
            end
            if not conditionType then return end
            config.rules[#config.rules + 1] = {
                condition = conditionType == "aura-stacks"
                    and YHUD:GetNextAuraStackCondition(config.rules)
                    or { type = conditionType },
                appearance = YHUD:GetDefaultMonitorGlowAppearance(),
            }
            config.rules[#config.rules].appearance.style = "pixel"
            FinishGlowMutation(
                Designer:SetMonitorGlow(monitor.id, config)
            )
        end,
    })
    local appearanceDivider = AddSectionHeading(
        body,
        T("designer.monitor.appearance_override", "外观覆盖")
    )
    local appearanceFillLabel = GUI2:CreateText(
        body,
        T("designer.appearance.fill_color", "填充颜色"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    local appearanceTrackLabel = GUI2:CreateText(
        body,
        T("designer.appearance.track_color", "轨道颜色"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    local appearanceSwipeLabel = GUI2:CreateText(
        body,
        T("designer.monitor.cooldown_swipe", "冷却旋转"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    local appearanceSwipe = GUI2.Form:CreateDropdown(body, {
        width = CONTENT_WIDTH,
        height = 30,
        options = function()
            return {
                {
                    value = "inherit",
                    text = T("designer.monitor.swipe_inherit", "跟随分组"),
                },
                {
                    value = "disabled",
                    text = T("designer.monitor.swipe_disabled", "关闭"),
                },
                {
                    value = "forward",
                    text = T("designer.monitor.swipe_forward", "正向"),
                },
                {
                    value = "reverse",
                    text = T("designer.monitor.swipe_reverse", "反向"),
                },
            }
        end,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            if Designer:SetMonitorAppearanceOverride(nil, {
                cooldownSwipeMode = value,
            }) ~= nil then
                DesignerUI:ApplyPreview()
                DesignerUI:Refresh(false, false)
            end
        end,
    })
    local function SelectedMonitorId()
        local session = Designer:GetSession()
        return session and session.selectedMonitorId
    end
    local function ResolveMonitorAppearanceTarget(control)
        local monitorId = control and control._yhudMonitorAppearanceTarget
            or SelectedMonitorId()
        if control and monitorId then
            control._yhudMonitorAppearanceTarget = monitorId
        end
        return monitorId
    end
    local function ReapplyMonitorAppearance(monitorId, appearanceOverride)
        local View = YHUD.View
        if monitorId and View and View.ReapplyMonitorVisual then
            return View:ReapplyMonitorVisual(monitorId, appearanceOverride)
        end
        return false
    end
    local function FinishMonitorAppearanceSession(
        control,
        monitorId,
        appearanceOverride
    )
        if control then control._yhudMonitorAppearanceTarget = nil end
        ReapplyMonitorAppearance(monitorId, appearanceOverride)
        DesignerUI:Refresh(false, false)
    end
    local function SetMonitorAppearanceColor(field, value, control)
        if DesignerUI.v2Refreshing then return end
        local monitorId = ResolveMonitorAppearanceTarget(control)
        if not monitorId then return false end
        local appearanceOverride = Designer:SetMonitorAppearanceOverride(monitorId, {
            [field] = value,
        })
        local changed = appearanceOverride ~= nil
        if changed then
            FinishMonitorAppearanceSession(
                control,
                monitorId,
                appearanceOverride
            )
        elseif control then
            control._yhudMonitorAppearanceTarget = nil
        end
        return changed
    end
    local function PreviewMonitorAppearanceColor(field, value, control)
        local monitorId = ResolveMonitorAppearanceTarget(control)
        local View = YHUD.View
        if monitorId and View and View.PreviewMonitorColor then
            return View:PreviewMonitorColor(monitorId, field, value)
        end
        return false
    end
    local function CancelMonitorAppearanceColor(field, value, control)
        local monitorId = ResolveMonitorAppearanceTarget(control)
        PreviewMonitorAppearanceColor(field, value, control)
        FinishMonitorAppearanceSession(control, monitorId)
    end
    local function BindMonitorAppearanceTarget(control)
        if not (control and control.HookScript) then return end
        control:HookScript("OnClick", function(frame)
            if frame._yhudMonitorAppearanceTarget == nil then
                frame._yhudMonitorAppearanceTarget = SelectedMonitorId()
            end
        end)
    end
    local appearanceFill = GUI2.Form:CreateColorPicker(body, {
        width = COLUMN_WIDTH,
        field = true,
        hasAlpha = true,
        preview = function(value, control)
            PreviewMonitorAppearanceColor("fillColor", value, control)
        end,
        commit = function(value, control)
            SetMonitorAppearanceColor("fillColor", value, control)
        end,
        cancel = function(value, control)
            CancelMonitorAppearanceColor("fillColor", value, control)
        end,
    })
    BindMonitorAppearanceTarget(appearanceFill)
    local appearanceTrack = GUI2.Form:CreateColorPicker(body, {
        width = COLUMN_WIDTH,
        field = true,
        hasAlpha = true,
        preview = function(value, control)
            PreviewMonitorAppearanceColor("trackColor", value, control)
        end,
        commit = function(value, control)
            SetMonitorAppearanceColor("trackColor", value, control)
        end,
        cancel = function(value, control)
            CancelMonitorAppearanceColor("trackColor", value, control)
        end,
    })
    BindMonitorAppearanceTarget(appearanceTrack)
    if I.BuildBarProgressUI then
        I.BuildBarProgressUI(self, CONTENT_WIDTH, {
            resolveTarget = ResolveMonitorAppearanceTarget,
            bindTarget = BindMonitorAppearanceTarget,
            reapply = ReapplyMonitorAppearance,
            finish = FinishMonitorAppearanceSession,
        })
    end
    local thresholdControls, thresholdUI = {}, { rows = {} }
    local function KeepThreshold(control)
        thresholdControls[#thresholdControls + 1] = control
        control:Hide()
        return control
    end
    local function ThresholdLabel(key, fallback)
        return KeepThreshold(GUI2:CreateText(body, T(key, fallback),
            "font.size.md", "color.text.primary", "LEFT"))
    end
    local function SetBarThreshold(field, name, value, control, deferRefresh)
        if DesignerUI.v2Refreshing then return end
        local monitorId = deferRefresh and SelectedMonitorId() or ResolveMonitorAppearanceTarget(control)
        local profile = Designer:GetProfile()
        local monitor = profile and profile.monitors[monitorId]
        if not monitor then return end
        local policy = YHUD:NormalizeBarStackThresholds(
            monitor.appearanceOverride and monitor.appearanceOverride.stackThresholds)
        if field then policy[field][name] = value else policy[name] = value end
        local appearance, code = Designer:SetMonitorAppearanceOverride(monitorId, { stackThresholds = policy })
        if code == "overlapping-bar-thresholds" then
            thresholdUI.info:SetText(T("designer.bar.threshold_overlap", "低阈值必须小于高阈值。"))
        end
        if appearance then
            if deferRefresh then
                ReapplyMonitorAppearance(monitorId, appearance)
                return
            end
            FinishMonitorAppearanceSession(control, monitorId, appearance)
        end
        if control then control._yhudMonitorAppearanceTarget = nil end
    end
    thresholdUI.label = ThresholdLabel("designer.bar.thresholds", "阈值变色")
    thresholdUI.info = KeepThreshold(GUI2:CreateText(body, "", "font.size.sm", "color.text.secondary", "LEFT"))
    thresholdUI.info:SetWordWrap(true)
    thresholdUI.enabled = KeepThreshold(GUI2.Form:CreateSwitch(body, {
        width = COLUMN_WIDTH - FIELD_LABEL_WIDTH - 8,
        height = 26,
        set = function(value) SetBarThreshold(nil, "enabled", value == true) end,
    }))
    for _, field in ipairs({ "low", "high" }) do
        local key = field
        local row = {}
        row.label = ThresholdLabel("designer.resource.threshold_" .. key .. "_enabled",
            key == "low" and "低阈值" or "高阈值")
        row.label:SetText(T("designer.resource.threshold_" .. key .. "_enabled",
            key == "low" and "低阈值" or "高阈值") .. (key == "low" and " ≤" or " ≥"))
        row.enabled = KeepThreshold(GUI2.Form:CreateSwitch(body, {
            width = SWITCH_WIDTH,
            set = function(value) SetBarThreshold(key, "enabled", value == true) end,
        }))
        row.value = KeepThreshold(GUI2.Form:CreateSlider(body, {
            width = CONTENT_WIDTH - 246, inline = true, inputWidth = 44,
            min = 0, max = 100, step = 1, precision = 0,
            set = function(value) SetBarThreshold(key, "value", value, row.value, true) end,
            onCommit = function()
                DesignerUI:Refresh(false, false)
            end,
        }))
        row.color = KeepThreshold(GUI2.Form:CreateColorPicker(body, {
            getDefault = function() return YHUD:NormalizeBarStackThresholds({})[key].color end,
            width = 44, field = true, hasAlpha = true,
            commit = function(value, control) SetBarThreshold(key, "color", value, control) end,
        }))
        BindMonitorAppearanceTarget(row.color)
        thresholdUI.rows[key] = row
    end
    self.monitorStackThresholdControls = thresholdControls
    self.monitorStackThresholdUI = thresholdUI
    local resetAppearance = GUI2.Form:CreateButton(body, {
        text = T("designer.glow.reset", "恢复"),
        width = COLUMN_WIDTH - FIELD_LABEL_WIDTH - 8,
        height = 26,
        onClick = function()
            if Designer:ResetMonitorAppearanceOverride() ~= nil then
                DesignerUI:ApplyPreview()
                DesignerUI:Refresh(false, false)
            end
        end,
    })
    self.skillAuraGlobalDivider = globalDivider
    self.skillAuraGlobalPanel = globalPanel
    self.skillAuraGlobalLabel = globalEffectRows[1].label
    self.skillAuraGlobalSwitch = globalEffectRows[1].switch
    self.monitorGlobalEffectRows = globalEffectRows
    self.skillAuraOverrideCount = globalEffectRows[1].count
    self.skillAuraClearOverrides = globalEffectRows[1].clear
    self.monitorGlobalNativeLabel = globalNativeLabel
    self.monitorGlobalNativeDropdown = globalNativeDropdown
    self.monitorGlobalNativeGear = globalNativeGear
    self.monitorGlobalNativeCombatLabel = globalNativeCombatLabel
    self.monitorGlobalNativeCombat = globalNativeCombat
    self.MonitorHelp:Bind(globalNativeLabel, "nativeProc", "global")
    self.MonitorHelp:Bind(globalNativeCombatLabel, "nativeCombat", "global")
    self.MonitorHelp:Bind(auraOverrideLabel, "auraTimer", "single")
    self.MonitorHelp:Bind(auraHighlightLabel, "auraHighlight", "single")
    self.MonitorHelp:Bind(inactiveDesaturateLabel, "inactiveDesaturate", "single")
    self.MonitorHelp:Bind(monitorNativeLabel, "nativeProc", "single")
    self.MonitorHelp:Bind(monitorNativeCombatLabel, "nativeCombat", "single")
    self.MonitorHelp:Bind(appearanceSwipeLabel, "cooldownSwipe", "single")
    self.skillAuraItemDivider = nil
    self.skillAuraOverrideLabel = auraOverrideLabel
    self.skillAuraOverrideStatus = auraOverrideStatus
    self.skillAuraOverrideDropdown = auraOverride
    self.monitorVisibilityLabel = visibilityLabel
    self.monitorVisibilityDropdown = visibilityDropdown
    self.monitorVisibilityLayoutInfo = visibilityLayoutInfo
    self.monitorEffectsButton = effectsButton
    self.monitorSoundButton = soundButton
    self.monitorReplicationButton = replicationButton
    self.monitorEffectsTitle = effectsTitle
    self.monitorEffectsBack = effectsBack
    self.monitorSoundTitle = soundTitle
    self.monitorSoundBack = soundBack
    self.monitorSoundRulesDivider = soundRulesDivider
    self.monitorSoundRuleCount = soundRuleCount
    self.monitorSoundRules = soundRules
    self.monitorSoundAddRule = soundAddRule
    self.monitorSelectedEffectsDivider = selectedEffectsDivider
    self.monitorAuraHighlightLabel = auraHighlightLabel
    self.monitorAuraHighlightDropdown = auraHighlightDropdown
    self.monitorInactiveDesaturateLabel = inactiveDesaturateLabel
    self.monitorInactiveDesaturateDropdown = inactiveDesaturateDropdown
    self.monitorResetEffects = resetEffects
    self.monitorGlowDivider = monitorGlowDivider
    self.monitorAssistedLabel = monitorAssistedLabel
    self.monitorAssistedDropdown = monitorAssistedDropdown
    self.monitorNativeLabel = monitorNativeLabel
    self.monitorNativeDropdown = monitorNativeDropdown
    self.monitorNativeGear = monitorNativeGear
    self.monitorNativeCombatLabel = monitorNativeCombatLabel
    self.monitorNativeCombat = monitorNativeCombat
    self.monitorGlowRulesDivider = monitorGlowRulesDivider
    self.monitorGlowRuleCount = monitorGlowRuleCount
    self.monitorGlowRules = monitorGlowRules
    self.monitorGlowAuraWarning = monitorGlowAuraWarning
    self.monitorGlowAddRule = monitorGlowAddRule
    self.monitorAppearanceDivider = appearanceDivider
    self.monitorAppearanceFillLabel = appearanceFillLabel
    self.monitorAppearanceFill = appearanceFill
    self.monitorAppearanceTrackLabel = appearanceTrackLabel
    self.monitorAppearanceTrack = appearanceTrack
    self.monitorAppearanceSwipeLabel = appearanceSwipeLabel
    self.monitorAppearanceSwipe = appearanceSwipe
    self.monitorResetAppearance = resetAppearance
    self.monitorBrowser = browser
    self.equipmentTriggerNotice = equipmentTriggerNotice
    self.bundleEditor = bundleEditor
    self.racialEditor = bundleEditor
end

local function BuildTextEditor(self)
    if self.textRows then return end
    local body = self.groupInspectorBody
    local definitions = {
        { target = "cooldown", text = T("designer.text_target.cooldown", "冷却时间") },
        { target = "name", text = T("designer.text_target.name", "名称") },
        { target = "count", text = T("designer.text_target.count", "层数/充能") },
        { target = "keybind", text = T("designer.keybind.title", "按键文本") },
    }
    local rows = {}
    for index = 1, #definitions do
        local definition = definitions[index]
        local row = GUI2:CreatePanel(body, {
            width = CONTENT_WIDTH,
            height = 46,
            surface = "color.surface.panel",
            border = "color.border.default",
        })
        row.target = definition.target
        row.defaultLabel = definition.text
        row.label = GUI2:CreateText(
            row, definition.text, "font.size.md", "color.text.primary", "LEFT"
        )
        row:SetHeight(definition.target == "keybind" and 116 or 82)
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -18)
        row.label:SetWidth(CONTENT_WIDTH - 236)
        row.label:SetWordWrap(true)
        local rightWidth, halfWidth = 204, 96
        local rightX = CONTENT_WIDTH - rightWidth - 8
        if definition.target == "keybind" then
            row.mode = GUI2.Form:CreateDropdown(row, {
                width = rightWidth, height = 28, menuWidth = rightWidth,
                options = function()
                    return {
                        { text = T("designer.keybind.mode.off", "关闭"), value = "off" },
                        { text = T("designer.keybind.mode.auto", "自动识别"), value = "auto" },
                        { text = T("designer.keybind.mode.manual", "手动填写"), value = "manual" },
                    }
                end,
                set = function(value)
                    local session = Designer:GetSession()
                    if not session then return end
                    if Designer:SetGroupIconStyle(session.selectedGroupId, {keybindTextMode=value}) then
                        DesignerUI:ApplyPreview()
                        DesignerUI:Refresh(false, false)
                    end
                end,
            })
            row.mode:SetPoint("TOPLEFT", row, "TOPLEFT", rightX, -8)
            row.settings = GUI2.Form:CreateButton(row, {
                text = TC("common.settings", "设置"), width = 56, height = 28,
                onClick = function()
                    DesignerUI.durationTextTarget = "keybind"
                    DesignerUI.textEditorTarget = "keybind"
                    DesignerUI:SyncDesignCooldownTextPreview("keybind")
                    DesignerUI:Refresh(false, false)
                end,
            })
            row.settings:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -8)
        else
            row.switch = GUI2.Form:CreateSwitch(row, {
                width = halfWidth, height = 28,
                set = function(value)
                    DesignerUI.durationTextTarget = definition.target
                    DesignerUI:SetSelectedGroupTextStyle("", value == true)
                end,
            })
            row.switch:SetPoint("TOPLEFT", row, "TOPLEFT", rightX, -8)
        end
        row.position = GUI2.Form:CreateDropdown(row, {
            width = definition.target == "keybind" and rightWidth or halfWidth,
            height = 28, menuWidth = 220,
            options = function()
                local previous = DesignerUI.durationTextTarget
                DesignerUI.durationTextTarget = definition.target
                local options = DesignerUI:BuildCurrentTextPositionOptions()
                DesignerUI.durationTextTarget = previous
                return options
            end,
            set = function(value)
                DesignerUI.durationTextTarget = definition.target
                DesignerUI:SetSelectedGroupTextStyle("Position", value)
            end,
        })
        row.position:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, definition.target == "keybind" and -42 or -8)
        row.font = GUI2.Form:CreateFontStyle(row, {key="yhud:unbound", width=rightWidth})
        row.font:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, definition.target == "keybind" and -76 or -42)
        row:Hide()
        rows[index] = row
    end

    local resourceNameRow = GUI2:CreatePanel(body, {
        width = CONTENT_WIDTH,
        height = 46,
        surface = "color.surface.panel",
        border = "color.border.default",
    })
    resourceNameRow.label = GUI2:CreateText(
        resourceNameRow,
        T("designer.resource.show_name", "名称"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    resourceNameRow.label:SetPoint("LEFT", resourceNameRow, "LEFT", 14, 0)
    resourceNameRow.switch = GUI2.Form:CreateSwitch(resourceNameRow, {
        width = 42,
        height = 22,
        set = function(value)
            DesignerUI:SetSelectedGroupResourceStyle("nameText", value == true)
        end,
    })
    resourceNameRow.switch:SetPoint("RIGHT", resourceNameRow, "RIGHT", -14, 0)
    resourceNameRow:Hide()

    local resourceValueRow = GUI2:CreatePanel(body, {
        width = CONTENT_WIDTH,
        height = 46,
        surface = "color.surface.panel",
        border = "color.border.default",
    })
    resourceValueRow.label = GUI2:CreateText(
        resourceValueRow,
        T("designer.resource.show_value", "数值"),
        "font.size.md",
        "color.text.primary",
        "LEFT"
    )
    resourceValueRow.label:SetPoint("LEFT", resourceValueRow, "LEFT", 14, 0)
    resourceValueRow.switch = GUI2.Form:CreateSwitch(resourceValueRow, {
        width = 42,
        height = 22,
        set = function(value)
            DesignerUI:SetSelectedGroupResourceStyle("valueText", value == true)
        end,
    })
    resourceValueRow.switch:SetPoint("RIGHT", resourceValueRow, "RIGHT", -14, 0)
    resourceValueRow:Hide()

    local resourceSettings = GUI2.Form:CreateButton(body, {
        text = T("designer.text.shared_settings", "设置文字样式"),
        width = CONTENT_WIDTH,
        height = 32,
        onClick = function()
            DesignerUI.textEditorTarget = "resource"
            DesignerUI:SyncDesignCooldownTextPreview(nil)
            DesignerUI:Refresh(false, false)
        end,
    })
    resourceSettings:Hide()

    local editorTitle = GUI2:CreateText(
        body, "", "font.size.lg", "color.text.heading", "LEFT"
    )
    editorTitle:Hide()
    local editorBack = GUI2.Form:CreateButton(body, {
        text = TC("common.back", "返回"),
        width = 68,
        height = 28,
        onClick = function()
            DesignerUI.textEditorTarget = nil
            DesignerUI:SyncDesignCooldownTextPreview("all")
            DesignerUI:Refresh(false, false)
        end,
    })
    editorBack:Hide()

    local keybindSource = AddSectionHeading(
        body,
        T("designer.keybind.source", "文本来源")
    )
    local keybindModeLabel = GUI2:CreateText(
        body,
        T("designer.keybind.display_mode", "显示模式"),
        "font.size.sm",
        "color.text.secondary",
        "LEFT"
    )
    local keybindMode = GUI2.Form:CreateDropdown(body, {
        width = CONTENT_WIDTH - 82,
        options = function()
            return {
                { text = T("designer.keybind.mode.off", "关闭"), value = "off" },
                { text = T("designer.keybind.mode.auto", "自动识别"), value = "auto" },
                { text = T("designer.keybind.mode.manual", "手动填写"), value = "manual" },
            }
        end,
        set = function(value)
            local session = Designer:GetSession()
            if not session then return end
            if Designer:SetGroupIconStyle(
                session.selectedGroupId,
                { keybindTextMode = value }
            ) then
                DesignerUI:ApplyPreview()
                DesignerUI:Refresh(false, false)
            end
        end,
    })
    local keybindSummary = GUI2:CreateText(
        body, "", "font.size.sm", "color.state.success", "LEFT"
    )
    local keybindStyle = AddSectionHeading(
        body,
        T("designer.keybind.style", "文字样式")
    )
    local keybindOverrides = AddSectionHeading(
        body,
        T("designer.keybind.overrides", "单项覆盖")
    )
    local keybindCount = GUI2:CreateText(
        body, "", "font.size.sm", "color.text.secondary", "RIGHT"
    )
    local keybindFilter = GUI2.Form:CreateDropdown(body, {
        width = 104,
        options = function()
            return {
                { text = T("designer.keybind.filter.all", "全部"), value = "all" },
                { text = T("designer.keybind.filter.missing", "未识别"), value = "missing" },
                { text = T("designer.keybind.filter.manual", "已手动"), value = "manual" },
            }
        end,
        set = function(value)
            DesignerUI.keybindTextFilter = value
            DesignerUI:Refresh(false, false)
        end,
    })
    local clearKeybindOverrides = GUI2.Form:CreateButton(body, {
        text = T("designer.keybind.clear_manual", "清除手动填写"),
        width = 132,
        height = 28,
        tone = "danger",
        onClick = function()
            local session = Designer:GetSession()
            if not session then return end
            if Designer:SetGroupIconStyle(
                session.selectedGroupId,
                { keybindTextOverrides = {} }
            ) then
                DesignerUI:ApplyPreview()
                DesignerUI:Refresh(false, false)
            end
        end,
    })
    local keybindControls = {
        keybindSource, keybindModeLabel, keybindMode, keybindSummary,
        keybindStyle, keybindOverrides, keybindCount, keybindFilter,
        clearKeybindOverrides,
    }
    HideControls(keybindControls)

    self.keybindFont = GUI2.Form:CreateFontStyle(body, {key="yhud:unbound", width=CONTENT_WIDTH - 82})
    self.keybindFont:Hide()
    keybindControls[#keybindControls+1] = self.keybindFont
    self.textRows = rows
    self.resourceTextRows = { resourceNameRow, resourceValueRow }
    self.resourceTextSettingsButton = resourceSettings
    self.textEditorTitle = editorTitle
    self.textEditorBack = editorBack
    self.keybindTextControls = keybindControls
    self.keybindSourceDivider = keybindSource
    self.keybindModeLabel = keybindModeLabel
    self.keybindModeDropdown = keybindMode
    self.keybindSummary = keybindSummary
    self.keybindStyleDivider = keybindStyle
    self.keybindOverridesDivider = keybindOverrides
    self.keybindOverrideCount = keybindCount
    self.keybindFilterDropdown = keybindFilter
    self.keybindClearOverrides = clearKeybindOverrides
    self.keybindOverrideRows = {}
end

local function BuildResourceStyleContextKey(classFile, specID, formKey, groupId)
    if YHUD.ResourceManager then return tostring(groupId or "") end
    return (groupId and (tostring(groupId) .. ":") or "") .. tostring(classFile or "") .. ":" .. tostring(specID or "")
        .. ":" .. tostring(formKey or "")
end

local function BuildResourceOptions()
    local classFile, specID, formKey = Designer:GetResourcePreviewContext()
    local profile = Designer:GetProfile()
    local session = Designer:GetSession()
    if profile and session and profile.groups.items[session.selectedGroupId]
        and profile.groups.items[session.selectedGroupId].contentPolicy == "cast-only" then
        return { { text = T("resource.player_cast", "玩家施法条"), value = "cast" } }
    end
    local options = {}
    if YHUD.ResourceManager then
        local labels = I.BuildResourceDisplayLabels()
        for _, preset in ipairs(Designer:GetManagedResourceStyles()) do
            local id = preset.styleResourceId or preset.id
            local setting = YHUD:GetResourceSetting(profile, id, session.selectedGroupId)
            local label = labels[id]
            options[#options + 1] = { value = id, text = label.text,
                onEnter = function(owner) I.ShowResourceLabelTooltip(owner, label) end,
                onLeave = I.HideResourceLabelTooltip,
                texture = "Interface\\Buttons\\WHITE8X8", iconSize = 12, iconColor = setting.fillColor or preset.color }
        end
        return options
    end
    local seen = {}
    local function Append(resourceId)
        if seen[resourceId] then return end
        local definition = ResourceCatalog and ResourceCatalog.GetDefinition
            and ResourceCatalog:GetDefinition(resourceId)
        if not definition then return end
        seen[resourceId] = true
        local setting = profile and YHUD:GetResourceSetting(profile, resourceId, Designer:GetSession().selectedGroupId)
        local color = setting and setting.fillColor or definition.color
        options[#options + 1] = {
            text = T(definition.nameKey, definition.id),
            value = definition.id,
            texture = "Interface\\Buttons\\WHITE8X8",
            iconSize = 12,
            iconColor = color,
        }
    end
    local function AppendPreset(specClassFile, presetSpecID)
        local ids = ResourceCatalog and ResourceCatalog.GetPresetIds
            and ResourceCatalog:GetPresetIds(specClassFile, presetSpecID) or {}
        for index = 1, #ids do Append(ids[index]) end
    end

    -- 通用玩家条固定在菜单顶部；不改变实际资源的混排顺序。
    Append("health")
    Append("cast")
    if formKey and ResourceCatalog and ResourceCatalog.GetFormPresets then
        local formPresets = ResourceCatalog:GetFormPresets(
            profile,
            classFile,
            specID,
            formKey
        )
        for index = 1, #formPresets do
            Append(formPresets[index].id)
        end
    end

    -- 当前形态优先，其次是当前专精和职业其他专精，最后补齐目录。
    AppendPreset(classFile, specID)
    local specs = ResourceCatalog and ResourceCatalog.GetSpecializations
        and ResourceCatalog:GetSpecializations(classFile) or {}
    for index = 1, #specs do
        local current = specs[index]
        if current.specID ~= specID then
            AppendPreset(classFile, current.specID)
        end
    end
    local definitionIds = ResourceCatalog and ResourceCatalog.GetDefinitionIds
        and ResourceCatalog:GetDefinitionIds() or {}
    for index = 1, #definitionIds do Append(definitionIds[index]) end
    return options
end

local function CurrentResourceDefinition()
    return ResourceCatalog and ResourceCatalog.GetDefinition
        and ResourceCatalog:GetDefinition(DesignerUI.resourceStyleResourceId, Designer:GetProfile(), Designer:GetSession().selectedGroupId)
        or nil
end

local function ResourcePositionOptions()
    local _, profile, group = SelectedContext()
    local layout = profile and group
        and YHUD:GetResourceGroupLayout(profile, group.id) or {}
    if layout.orientation == "vertical" then
        return {
            { text = T("designer.resource.position.bottom", "下"), value = "start" },
            { text = T("designer.resource.position.center", "居中"), value = "center" },
            { text = T("designer.resource.position.top", "上"), value = "end" },
        }
    end
    return {
        { text = T("designer.resource.position.left", "左"), value = "start" },
        { text = T("designer.resource.position.center", "居中"), value = "center" },
        { text = T("designer.resource.position.right", "右"), value = "end" },
    }
end

local function ResourceFormatOptions()
    local definition = CurrentResourceDefinition()
    local id = definition and definition.id
    local kind = definition and definition.provider and definition.provider.kind
    local options = { { text = T("designer.resource.format.none", "无"), value = "none" } }
    local function Add(key, fallback, value)
        options[#options + 1] = { text = T(key, fallback), value = value }
    end
    if kind == "aura-duration" or kind == "swing-timer" or kind == "monitor-time" or kind == "global-cooldown" then
        Add("designer.resource.format.duration", "剩余时间", "duration")
    elseif id == "stagger" or id == "ignorePain" then
        Add("designer.resource.format.percent", "百分比", "percent")
        Add("designer.resource.format.percent_sign", "百分比%", "percentSign")
    elseif definition and definition.valueKind == "discrete" or id == "ironfur" then
        Add("designer.resource.format.count", "数值 · 3", "value")
        if id ~= "runes" and id ~= "ironfur" then
            Add("designer.resource.format.value_max", "当前 / 上限：3 / 5", "valueMax")
            options[#options].text = options[#options].text .. " · 3 / 5"
        end
        if id == "essence" or id == "soulShards" then
            options[2].text = T("designer.resource.format.partial", "含恢复进度：3.4")
            Add("designer.resource.format.whole", "完整点数：3", "whole")
        end
    else
        Add("designer.resource.format.percent", "百分比", "percent")
        Add("designer.resource.format.percent_sign", "百分比%", "percentSign")
        Add("designer.resource.format.value", "数值", "value")
        Add("designer.resource.format.value_max", "当前 / 上限：60 / 120", "valueMax")
        options[#options].text = options[#options].text .. " · 60 / 120"
        Add("designer.resource.format.value_percent", "数值 | 百分比", "valuePercent")
        Add("designer.resource.format.percent_value", "百分比 | 数值", "percentValue")
        Add("designer.resource.format.value_percent_paren", "数值（百分比）", "valuePercentParen")
    end
    if kind == "absorb" then Add("designer.resource.format.duration", "剩余时间", "duration") end
    return options
end

local function ResourceDisplayModeOptions()
    return {
        { text = T("designer.resource.display_mode.bar", "连续条"), value = "bar" },
        { text = T("designer.resource.display_mode.divided", "分隔条"), value = "divided" },
        { text = T("designer.resource.display_mode.cells", "矩形格"), value = "cells" },
        { text = T("designer.resource.display_mode.dots", "几何资源点"), value = "dots" },
        { text = T("designer.resource.display_mode.native", "原生资源点"), value = "nativePoints" },
    }
end

function I.ResourcePointShapeOptions()
    return {
        { text = T("designer.resource.point_shape.circle", "圆形"), value = "circle" },
        { text = T("designer.resource.point_shape.square", "方形"), value = "square" },
        { text = T("designer.resource.point_shape.diamond", "菱形"), value = "diamond" },
        { text = T("designer.resource.point_shape.star", "五角星"), value = "star" },
    }
end

function I.ResourceNativePointOptions()
    local result = {}
    for _, entry in ipairs({ { "auto", "自动匹配" }, { "arcane", "奥术充能" }, { "essence", "精华" },
        { "rogue", "潜行者连击点" }, { "druid", "德鲁伊连击点" }, { "chi", "真气" },
        { "holy", "神圣能量" }, { "shards", "灵魂碎片" }, { "runeBlood", "符文 · 鲜血" },
        { "runeFrost", "符文 · 冰霜" }, { "runeUnholy", "符文 · 邪恶" } }) do
        result[#result + 1] = { value = entry[1], text = T("designer.resource.native_point." .. entry[1], entry[2]) }
    end
    return result
end

local function ResourceVisibilityModeOptions()
    return {
        {
            text = T("designer.resource.visibility.always", "始终显示"),
            value = "always",
        },
        {
            text = T("designer.resource.visibility.nonzero", "非零时显示"),
            value = "nonzero",
        },
        {
            text = T(
                "designer.resource.visibility.nonzero_or_combat",
                "非零或战斗时显示"
            ),
            value = "nonzeroOrCombat",
        },
    }
end

local function SetResourceThreshold(resourceId, side, field, value)
    local profile = Designer:GetProfile()
    local setting = profile and YHUD:GetResourceSetting(profile, resourceId, Designer:GetSession().selectedGroupId)
    if not (setting and type(setting.thresholds) == "table") then
        return false
    end
    local thresholds = YHUD:CopyValue(setting.thresholds)
    thresholds[side] = type(thresholds[side]) == "table"
        and thresholds[side] or {}
    thresholds[side][field] = value
    return Designer:SetResourceSetting(resourceId, { thresholds = thresholds })
end

function DesignerUI:SetResourceThresholdMode(resourceId, mode)
    local setting = YHUD:GetResourceSetting(Designer:GetProfile(), resourceId, Designer:GetSession().selectedGroupId)
    if not setting or setting.thresholdMode == mode then return false end
    local thresholds = YHUD:CopyValue(setting.thresholds)
    local saved = setting.thresholdValues and setting.thresholdValues[mode]
    if not saved then return false end
    thresholds.low.value, thresholds.high.value = saved.low, saved.high
    return Designer:SetResourceSetting(resourceId, { thresholdMode = mode, thresholds = thresholds })
end

RefreshResourceSlots = function(resourceId)
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local groupId = session and session.selectedGroupId
    local View = YHUD.View
    local projection = View and View.designProjection
    local groups = projection and projection.groups or View and View.groups
    local slots = projection and projection.byMonitor or View and View.byMonitor
    local desiredMonitors = projection
        and projection.desiredMonitors or View and View.desiredMonitors
    local runtime = groupId and groups and groups[groupId]
    if not (runtime and View.ConfigureSlot and slots and desiredMonitors) then
        return false
    end
    runtime.resourceProfile = profile
    local refreshed = false
    for _, slot in pairs(slots) do
        local monitor = slot and slot._yhudMonitorId
            and desiredMonitors[slot._yhudMonitorId]
        local preset = monitor and monitor._yhudResource
        if slot._yhudGroupId == groupId
            and preset and (resourceId == nil or preset.id == resourceId) then
            View:ConfigureSlot(slot, runtime, monitor)
            if View.InvalidateDesignResourcePreviewAppearance then
                View:InvalidateDesignResourcePreviewAppearance(slot)
            end
            refreshed = true
        end
    end
    return refreshed
end

local function RefreshResourceMutation(result, refreshControls)
    if not result then return false end
    if not DesignerUI:PreviewSelectedGroup() then return false end
    DesignerUI:AddResourcePreviewStat("resourcePreviewGroupRefreshes", 1)
    DesignerUI:AddResourcePreviewStat("resourcePreviewFullRefreshAvoided", 1)
    if DesignerUI.ReapplyResourceValuePreview then
        DesignerUI:ReapplyResourceValuePreview()
    end
    if refreshControls ~= false then
        DesignerUI:Refresh(false, false)
    end
    return result
end

local function RefreshResourceSliderMutation(result, resourceId, relayout)
    if not result then return false end
    DesignerUI.v2SliderPreviewDirty = true
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local View = YHUD.View
    local groupId = session and session.selectedGroupId
    if not (profile and groupId and View
        and View.RefreshDesignProjectionResources
        and View:RefreshDesignProjectionResources(
            profile,
            groupId,
            resourceId,
            relayout == true
        )) then
        DesignerUI:PreviewSelectedGroup()
    end
    if DesignerUI.ReapplyResourceValuePreview then
        DesignerUI:ReapplyResourceValuePreview()
    end
    return result
end

local function PreviewSelectedResourceColor(field, value, finish)
    local session = Designer:GetSession()
    local groupId = session and session.selectedGroupId
    local View = YHUD.View
    if groupId and View and View.PreviewResourceColor then
        return View:PreviewResourceColor(
            groupId,
            DesignerUI.resourceStyleResourceId,
            field,
            value,
            finish
        )
    end
    return false
end

local function BindResourceColorPicker(control, field, commit)
    if not (control and control.SetColorLifecycle) then return control end
    control:SetColorLifecycle(
        function(value)
            PreviewSelectedResourceColor(field, value)
        end,
        function(value)
            commit(value)
            -- The projection owns a resolved style snapshot. Replace it once
            -- after commit; pointer movement only paints the selected slot.
            DesignerUI:PreviewSelectedGroup()
        end,
        function(originalValue)
            PreviewSelectedResourceColor(field, originalValue, true)
        end
    )
    return control
end

local function BindAdoptedColorPickers(self)
    if self.v2ColorLifecyclesBound then return end
    local function SelectedGroup()
        local session = Designer:GetSession()
        local profile = Designer:GetProfile()
        local groupId = session and session.selectedGroupId
        local group = groupId and profile and profile.groups
            and profile.groups.items[groupId]
        return groupId, group
    end
    local function Preview(field, value)
        local groupId = SelectedGroup()
        local View = YHUD.View
        if field == "textColor" and groupId then
            if View and View.PreviewGroupTextColor then
                View:PreviewGroupTextColor(
                    groupId,
                    self.durationTextTarget,
                    value
                )
            end
            if not (View and View.designProjection) then
                local NativeBridge = YHUD.NativeBridge
                if NativeBridge and NativeBridge.PreviewGroupTextColor then
                    NativeBridge:PreviewGroupTextColor(
                        groupId,
                        self.durationTextTarget,
                        value
                    )
                end
            end
        elseif groupId and View and View.PreviewGroupColor then
            View:PreviewGroupColor(groupId, field, value)
        end
    end
    local function Bind(control, field, commit)
        if not (control and control.SetColorLifecycle) then return end
        control:SetColorLifecycle(
            function(value) Preview(field, value) end,
            commit,
            function(value) Preview(field, value) end
        )
    end
    Bind(self.fillColorPicker, "fillColor", function(value)
        local groupId = SelectedGroup()
        if groupId then
            Designer:SetGroupDurationStyle(groupId, { fillColor = value })
        end
    end)
    Bind(self.trackColorPicker, "trackColor", function(value)
        local groupId, group = SelectedGroup()
        if groupId and group then
            Designer:SetGroupDurationStyle(groupId, {
                [group.layout == "rings"
                    and "ringTrackColor" or "trackColor"] = value,
            })
        end
    end)
    Bind(self.iconBackgroundPicker, "iconBackground", function(value)
        local groupId = SelectedGroup()
        if groupId then
            Designer:SetGroupIconStyle(
                groupId,
                { iconBackgroundColor = value }
            )
        end
    end)
    Bind(self.iconShadowColorPicker, "iconShadow", function(value)
        local groupId, group = SelectedGroup()
        if groupId and group and group.layout == "icons" then
            Designer:SetGroupIconStyle(groupId, { iconShadowColor = value })
        end
    end)
    Bind(self.iconBorderColorPicker, "iconBorder", function(value)
        local groupId, group = SelectedGroup()
        if not (groupId and group) then return end
        if group.layout == "icons" then
            Designer:SetGroupIconStyle(
                groupId,
                { iconBorderColor = value }
            )
        else
            local patch = {
                iconBorderColor = value,
                borderColor = value,
            }
            if group.layout == "rings" then
                patch.ringBorderColor = value
            end
            Designer:SetGroupDurationStyle(groupId, patch)
        end
    end)
    Bind(self.textColorPicker, "textColor", function(value)
        local groupId, group = SelectedGroup()
        if not (groupId and group) then return end
        local prefix = self.durationTextTarget == "count"
            and "countText"
            or (group.layout ~= "icons"
                and self.durationTextTarget == "name"
                and "nameText"
                or (group.layout ~= "icons"
                    and "timeText" or "cooldownText"))
        local patch = { [prefix .. "Color"] = value }
        if group.layout == "icons" then
            Designer:SetGroupIconStyle(groupId, patch)
        else
            Designer:SetGroupDurationStyle(groupId, patch)
        end
        Preview("textColor", value)
    end)
    local function BindResource(control, field)
        Bind(control, field, function(value)
            local groupId = SelectedGroup()
            if not groupId then return end
            local patch = { [field] = value }
            if field == "fillColor" then
                patch.fillColorMode = "custom"
            end
            Designer:SetGroupResourceStyle(groupId, patch)
        end)
    end
    BindResource(self.resourceBackgroundPicker, "backgroundColor")
    BindResource(self.resourceFillColorPicker, "fillColor")
    BindResource(self.resourceBorderColorPicker, "borderColor")
    BindResource(self.resourceTextColorPicker, "textColor")
    self.v2ColorLifecyclesBound = true
end

function DesignerUI:SetSelectedGroupResourceBorderThickness(value)
    local session = Designer:GetSession()
    if not session then return false end
    local result = Designer:SetGroupResourceStyle(
        session.selectedGroupId,
        { border = value }
    )
    return RefreshResourceSliderMutation(result, nil)
end

local function NewResourceTextLabel(parent, text)
    local label = GUI2:CreateText(
        parent, text, "font.size.md", "color.text.primary", "LEFT"
    )
    label:SetWidth(COLUMN_WIDTH)
    label:SetHeight(RESOURCE_LABEL_HEIGHT)
    label:SetJustifyH("LEFT")
    if label.SetJustifyV then label:SetJustifyV("MIDDLE") end
    label:SetWordWrap(false)
    label:Hide()
    return label
end

local function NewResourceLabel(parent, key, fallback)
    return NewResourceTextLabel(parent, T(key, fallback))
end

local function PlaceResourceField(label, control, parent, x, y)
    if label then
        if label.SetFont and GUI2.GetFont and GUI2.GetMetric then
            label:SetFont(
                GUI2:GetFont("font.family.body"),
                GUI2:GetMetric("font.size.md", 13)
            )
        end
        if GUI2.SetTextColorKey then
            GUI2:SetTextColorKey(label, "color.text.primary")
        end
        label:SetHeight(RESOURCE_LABEL_HEIGHT)
        label:SetJustifyH("LEFT")
        if label.SetJustifyV then label:SetJustifyV("MIDDLE") end
        label:SetWordWrap(false)
    end
    Place(label, parent, x, y, COLUMN_WIDTH)
    Place(control, parent, x, y - RESOURCE_CONTROL_OFFSET, COLUMN_WIDTH)
end

local function PlaceResourceFieldWithHelp(label, help, control, parent, x, y)
    PlaceResourceField(label, control, parent, x, y)
    local labelWidth = label and label.GetStringWidth
        and label:GetStringWidth() or 28
    local helpHeight = help and help.GetHeight and help:GetHeight() or 20
    Place(
        help,
        parent,
        (x or 0) + math.min(labelWidth + 6, COLUMN_WIDTH - 20),
        (y or 0) + ((helpHeight - RESOURCE_LABEL_HEIGHT) / 2)
    )
    help:Show()
end

do
local RESOURCE_APPEARANCE_CONTROL_WIDTH = 72
local RESOURCE_APPEARANCE_CONTROL_HEIGHT = 24
local RESOURCE_APPEARANCE_ROW_GAP = 10

local function CommitResourceAppearanceSlider()
    DesignerUI:CommitV2SliderPreview()
end

local function ResourceAppearanceTextWidth(text)
    if type(text) ~= "table" and type(text) ~= "userdata" then return 0 end
    local measure = text.GetUnboundedStringWidth or text.GetStringWidth
    return measure and measure(text) or 0
end

local function ResourceAppearanceSelectWidth(field)
    local control, text = field[2], field[2] and field[2].text
    if field[3] == "compactSelect" and control.SetTextInsets then control:SetTextInsets(4, 18) end
    local width = ResourceAppearanceTextWidth(text)
    if field[5] and text and type(text) ~= "string" and text.GetText and text.SetText then
        local original = text:GetText()
        for _, option in ipairs(field[5]) do
            text:SetText(" " .. (option.selectionText or option.text or tostring(option.value or "")))
            width = math.max(width, ResourceAppearanceTextWidth(text))
        end
        text:SetText(original)
    end
    return width + (control.gui2DropdownTextPadding or (control.gui2HasSelectionIcon and 56 or 36))
end

local function MeasureResourceAppearanceField(field, availableWidth)
    local label, control, kind, help = field[1], field[2], field[3], field[4]
    SetStandardTextSize(label)
    local labelWidth = ResourceAppearanceTextWidth(label)
    if help then labelWidth = labelWidth + 20 end
    local width = RESOURCE_APPEARANCE_CONTROL_WIDTH
    if kind == "fullSelect" then
        width = availableWidth - (COLUMN_WIDTH - RESOURCE_APPEARANCE_CONTROL_WIDTH)
    elseif kind == "compactSelect" then
        ResourceAppearanceSelectWidth(field)
        if availableWidth > COLUMN_WIDTH then width = availableWidth - (COLUMN_WIDTH - RESOURCE_APPEARANCE_CONTROL_WIDTH) end
    elseif kind == "select" or kind == "wide" then
        width = kind == "wide" and availableWidth or math.max(96, math.min(availableWidth, ResourceAppearanceSelectWidth(field)))
    elseif kind == "button" then return availableWidth, RESOURCE_APPEARANCE_CONTROL_HEIGHT, false end
    local above = kind == "wide" or labelWidth + 8 + width > availableWidth
    return width, above and (RESOURCE_LABEL_HEIGHT + 4 + RESOURCE_APPEARANCE_CONTROL_HEIGHT)
        or RESOURCE_APPEARANCE_CONTROL_HEIGHT, above
end

local function PlaceResourceAppearanceField(parent, field, x, y, availableWidth)
    local label, control, kind, help = field[1], field[2], field[3], field[4]
    local width, height, above = MeasureResourceAppearanceField(field, availableWidth)
    if kind == "button" then
        Place(control, parent, x, y, width)
        control:Show()
        return height
    end
    if kind == "number" and control.SetCompactMode then
        control:SetCompactMode(true, width, CommitResourceAppearanceSlider)
    end
    if kind == "switch" then
        control.width = width
        control.height = RESOURCE_APPEARANCE_CONTROL_HEIGHT
        if control.thumb then control.thumb:SetHeight(RESOURCE_APPEARANCE_CONTROL_HEIGHT - 6) end
    end
    control:SetHeight(RESOURCE_APPEARANCE_CONTROL_HEIGHT)
    local controlY = above and (y - RESOURCE_LABEL_HEIGHT - 4) or y
    if label then
        label:SetHeight(RESOURCE_LABEL_HEIGHT)
        label:SetWordWrap(false)
        Place(label, parent, x, above and y or (y - 3), above and availableWidth or availableWidth - width - 8)
        label:Show()
    end
    Place(control, parent, x + availableWidth - width, controlY, width)
    if control.chipBg then
        control.chipBg:SetHeight(RESOURCE_APPEARANCE_CONTROL_HEIGHT)
        if control.chipBg.UpdateGUI2PixelLayout then control.chipBg:UpdateGUI2PixelLayout() end
    end
    if kind == "switch" and control.GetValue then
        control:SetValue(control:GetValue(), { silent = true, force = true })
    end
    control:Show()
    if help then
        local textWidth = ResourceAppearanceTextWidth(label)
        Place(help, parent, x + textWidth + 3, y - 2)
        help:Show()
    end
    return height
end

function I.PlaceResourceAppearanceRow(parent, y, left, right)
    if not left then left, right = right, nil end
    if not left then return y end
    local function NeedsFullWidth(field)
        if not field then return false end
        if field[3] == "fullSelect" then return true end
        if field[3] == "compactSelect" then
            local _, _, above = MeasureResourceAppearanceField(field, COLUMN_WIDTH)
            return above or ResourceAppearanceSelectWidth(field) > RESOURCE_APPEARANCE_CONTROL_WIDTH
        end
        if field[3] == "select" then
            local _, _, above = MeasureResourceAppearanceField(field, COLUMN_WIDTH)
            return above
        end
        local text = field and field[2] and field[2].text
        return field[3] == "wide"
            and ResourceAppearanceTextWidth(text) + 36 > COLUMN_WIDTH
    end
    if NeedsFullWidth(left) or NeedsFullWidth(right) then
        if left then
            y = y - PlaceResourceAppearanceField(parent, left, 0, y,
                NeedsFullWidth(left) and CONTENT_WIDTH or COLUMN_WIDTH) - RESOURCE_APPEARANCE_ROW_GAP
        end
        if right then
            y = y - PlaceResourceAppearanceField(parent, right, 0, y,
                NeedsFullWidth(right) and CONTENT_WIDTH or COLUMN_WIDTH) - RESOURCE_APPEARANCE_ROW_GAP
        end
        return y
    end
    local leftHeight = left and PlaceResourceAppearanceField(parent, left, 0, y, COLUMN_WIDTH) or 0
    local rightHeight = right and PlaceResourceAppearanceField(parent, right, SECOND_COLUMN_X, y, COLUMN_WIDTH) or 0
    return y - math.max(leftHeight, rightHeight) - RESOURCE_APPEARANCE_ROW_GAP
end

end

local function ResourceUsesSpec(profile, resourceId, classFile, specID)
    local available, enabled = false, false
    local manager = YHUD.ResourceManager
    if not manager then
        enabled = ResourceCatalog:IsPresetEnabled(profile, classFile, specID, resourceId)
        return enabled, enabled
    end
    -- Read the same group memberships as the monitor page, without resolving live sources.
    local forms = ResourceCatalog:GetFormOptions(classFile, specID)
    for formIndex = 1, math.max(1, #forms) do
        local formKey = forms[formIndex] and forms[formIndex].key
        local items = ResourceCatalog:GetDisplayPresets(profile, manager:GetItems(profile, classFile, specID, formKey))
        for _, item in ipairs(items) do
            if (item.styleResourceId or item.id) == resourceId then
                available = true
                enabled = enabled or item.enabled == true
                break
            end
        end
    end
    return available, enabled
end

function I.AppendResourceSpecializations(resourceId, profile, groupId)
    if not (GameTooltip and resourceId and profile and groupId) then return end
    local scoped = YHUD:GetResourceProfile(profile, groupId)
    local rows = {}
    local classes = ResourceCatalog:GetClasses()
    for classIndex = 1, #classes do
        local classInfo = classes[classIndex]
        local classFile = classInfo.classFile
        local specs = ResourceCatalog:GetSpecializations(classFile)
        for specIndex = 1, #specs do
            local spec = specs[specIndex]
            local available, enabled = ResourceUsesSpec(scoped, resourceId, classFile, spec.specID)
            if available then
                rows[#rows + 1] = {
                    classFile = classFile,
                    classID = classInfo.classID or 999,
                    specID = spec.specID,
                    specIndex = spec.specIndex or specIndex,
                    name = YUI.Locale and YUI.Locale.GetSpecializationName
                        and YUI.Locale:GetSpecializationName(spec.specID, spec.name or tostring(spec.specID))
                        or spec.name or tostring(spec.specID),
                    enabled = enabled,
                }
            end
        end
    end
    table.sort(rows, function(left, right)
        local leftArmor = CLASS_ARMOR_ORDER[left.classFile] or 99
        local rightArmor = CLASS_ARMOR_ORDER[right.classFile] or 99
        if leftArmor ~= rightArmor then return leftArmor < rightArmor end
        if left.classID ~= right.classID then
            return left.classID < right.classID
        end
        return left.specIndex < right.specIndex
    end)

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(
        T("designer.resource.specializations", "对应专精"),
        1,
        1,
        1
    )
    for index = 1, #rows do
        local row = rows[index]
        if row.enabled then
            local color = UnitAPI and UnitAPI.GetClassColor
                and UnitAPI.GetClassColor(row.classFile) or nil
            GameTooltip:AddLine(
                row.name,
                color and color.r or 1,
                color and color.g or 1,
                color and color.b or 1
            )
        else
            GameTooltip:AddLine(row.name, 0.45, 0.45, 0.45)
        end
    end
    if #rows == 0 then
        GameTooltip:AddLine(
            T("designer.resource.no_specializations", "没有对应专精"),
            0.45,
            0.45,
            0.45
        )
    end
end

local function ShowResourceSpecializationTooltip(owner)
    if not (GameTooltip and owner) then return end
    local resourceId = DesignerUI.resourceStyleResourceId
    local profile, session = Designer:GetProfile(), Designer:GetSession()
    if not (profile and session) then return end
    local definition = resourceId and ResourceCatalog
        and ResourceCatalog.GetDefinition
        and ResourceCatalog:GetDefinition(resourceId, profile, session.selectedGroupId) or nil
    if not definition then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(definition.name or T(definition.nameKey, definition.id), 1, 0.82, 0)
    if definition.descriptionKey then
        GameTooltip:AddLine(T(definition.descriptionKey, ""), 0.78, 0.82, 0.88, true)
    end
    I.AppendResourceSpecializations(resourceId, profile, session.selectedGroupId)
    GameTooltip:Show()
end

local function CreateResourceHelpButton(parent)
    local button = GUI2:CreateBareMicroIconButton(parent, {
        size = 18,
        microIcon = "info",
        microIconSize = 16,
        microIconMaxSize = 14,
        microIconMinPhysicalPixels = 12,
        colorKey = "color.text.secondary",
        hoverColorKey = "color.text.primary",
    })
    button:HookScript("OnEnter", ShowResourceSpecializationTooltip)
    button:HookScript("OnLeave", function()
        if GameTooltip then YUI.HideGameTooltip() end
    end)
    return button
end

local function PlaceResourceSwitch(label, control, parent, x, y)
    PlaceResourceField(label, nil, parent, x, y)
    Place(control, parent, x, y - RESOURCE_CONTROL_OFFSET, SWITCH_WIDTH)
end

local function RestoreResourceGlobalStyle(scope)
    local session = Designer:GetSession()
    local defaults = YHUD.Defaults
        and YHUD.Defaults.profile
        and YHUD.Defaults.profile.style
        and YHUD.Defaults.profile.style.groups
        and YHUD.Defaults.profile.style.groups[YHUD.GROUP_IDS.RESOURCES]
    if not (session and defaults) then return false end
    local fields = scope == "text" and {
        "textFont", "textSize", "textOutline", "textColor",
    } or {
        "border", "borderColor", "fillTexture", "backgroundColor",
        "smoothProgress",
    }
    local patch = {}
    for index = 1, #fields do
        local field = fields[index]
        patch[field] = YHUD:CopyValue(defaults[field])
    end
    return RefreshResourceMutation(
        Designer:SetGroupResourceStyle(session.selectedGroupId, patch)
    )
end

function I.RefreshPlayerCastOptions(self, profile, group, page, y)
    self.playerCastPages = self.playerCastPages or {}
    local ui = self.playerCastPages[page]
    if not ui then
        ui = { controls = {} }
        self.playerCastPages[page] = ui
        local root = EnsureV2PageRoots(self)[page == "monitor" and "resourceMonitor" or page]
        local function Keep(control)
            ui.controls[#ui.controls + 1] = control
            control:Hide()
            return control
        end
        local function Patch(field, value, refreshControls)
            if self.v2Refreshing then return end
            local session = Designer:GetSession()
            if not session then return end
            local patch
            if field == "textPosition" or field == "textOffsetX" or field == "textOffsetY" then
                patch = { [field] = value }
            else
                local cast = YHUD:CopyValue(YHUD:GetResourceSetting(Designer:GetProfile(), "cast", session.selectedGroupId).cast)
                if (field == "nameSize" or field == "progressSize") and value == false then cast[field] = nil
                else cast[field] = value end
                patch = { cast = cast }
            end
            local result = Designer:SetResourceSetting("cast", patch)
            local size = field == "nameSize" or field == "progressSize"
            if result and size then
                ui.sizeGlobal:SetValue(value == false, true)
            end
            if not refreshControls and (field == "iconGap" or (size and value ~= false) or field:find("Offset", 1, true)) then
                RefreshResourceSliderMutation(result, "cast")
            else
                RefreshResourceMutation(result)
            end
        end
        local function Switch(field, key, fallback)
            ui[field .. "Label"] = Keep(NewResourceLabel(root, key, fallback))
            ui[field] = Keep(GUI2.Form:CreateSwitch(root, { width = SWITCH_WIDTH,
                tooltip = field == "progress" and YUI.IsRetail and T("player_cast.progress_tip", "普通施法和引导使用所选计时格式，蓄力显示阶段。") or nil,
                set = function(value) Patch(field, value == true) end }))
        end
        if page == "monitor" then
            ui.source = Keep(NewResourceLabel(root, "player_cast.source", "施法来源：玩家自身"))
        elseif page == "appearance" then
            ui.idleLabel = Keep(NewResourceLabel(root, "player_cast.idle", "未施法时"))
            ui.idle = Keep(GUI2.Form:CreateDropdown(root, { width = COLUMN_WIDTH, options = {
                { text = T("player_cast.reserve", "占位"), value = "reserve" },
                { text = T("player_cast.collapse", "不占位"), value = "collapse" },
            }, set = function(value) Patch("idle", value) end }))
            ui.nativeLabel = Keep(NewResourceLabel(root, "player_cast.hide_native", "隐藏原生施法条"))
            ui.native = Keep(GUI2.Form:CreateSwitch(root, { width = SWITCH_WIDTH,
                tooltip = T("player_cast.native_tip", "当前方案共用；停用全部 Halo 玩家施法条后，恢复原生显示。"),
                set = function(value)
                    if self.v2Refreshing or self.busyKind or not ui.native:IsShown() then return end
                    local session = Designer:GetSession()
                    if not session or session ~= ui.nativeSession or session.setId ~= ui.nativeSetId then return end
                    if Designer:SetPlayerCastSettings({ hideNative = value == true }) then
                        self:Refresh(false, false)
                    end
                end,
            }))
            ui.native:HookScript("OnHide", function() ui.nativeSession, ui.nativeSetId = nil, nil end)
            Switch("icon", "player_cast.icon", "显示图标")
            ui.iconSideLabel = Keep(NewResourceLabel(root, "player_cast.icon_side", "图标位置"))
            ui.iconSide = Keep(GUI2.Form:CreateDropdown(root, { width = COLUMN_WIDTH, options = {
                { text = T("player_cast.inside_left", "内部左侧"), value = "left" },
                { text = T("player_cast.inside_right", "内部右侧"), value = "right" },
                { text = T("player_cast.outside_left", "外部左侧"), value = "outside-left" },
                { text = T("player_cast.outside_right", "外部右侧"), value = "outside-right" },
            }, set = function(value) Patch("iconSide", value) end }))
            ui.iconGapLabel = Keep(NewResourceLabel(root, "player_cast.icon_gap", "图标间距"))
            ui.iconGap = Keep(CreateSlider(root, nil, 0, 12, 1, 0, function(value) Patch("iconGap", value) end, COLUMN_WIDTH))
        else
            ui.target = "name"
            local function Prefix() return ui.target == "name" and "name" or "text" end
            local function SizeField() return ui.target == "name" and "nameSize" or "progressSize" end
            ui.targetPicker = Keep(GUI2.Form:CreateSegmentedControl(root, {
                width = CONTENT_WIDTH - SWITCH_WIDTH - 12,
                items = {
                    { text = T("player_cast.name", "法术名称"), value = "name" },
                    { text = T("player_cast.progress", "施法进度"), value = "progress" },
                },
                set = function(value)
                    if self.v2Refreshing or ui.target == value then return end
                    ui.target = value
                    self:Refresh(false, false)
                end,
            }))
            ui.enabledOptions = {
                width = SWITCH_WIDTH,
                tooltip = T("player_cast.name", "法术名称"),
                set = function(value) Patch(ui.target, value == true) end,
            }
            ui.enabled = Keep(GUI2.Form:CreateSwitch(root, ui.enabledOptions))
            ui.timeFormatLabel = Keep(NewResourceLabel(root, "player_cast.time_format", "计时格式"))
            ui.timeFormat = Keep(GUI2.Form:CreateDropdown(root, { width = COLUMN_WIDTH, options = {
                { text = T("player_cast.time_remaining", "剩余时间"), value = "remaining" },
                { text = T("player_cast.time_elapsed", "已过时间"), value = "elapsed" },
                { text = T("player_cast.time_remaining_total", "剩余 / 总计"), value = "remainingTotal" },
                { text = T("player_cast.time_elapsed_total", "已过 / 总计"), value = "elapsedTotal" },
            }, set = function(value) Patch("timeFormat", value) end }))
            ui.positionLabel = Keep(NewResourceLabel(root, "designer.resource.position", "位置"))
            ui.position = Keep(GUI2.Form:CreateDropdown(root, {
                width = COLUMN_WIDTH, options = ResourcePositionOptions,
                set = function(value) Patch(Prefix() .. "Position", value) end,
            }))
            ui.sizeLabel = Keep(NewResourceLabel(root, "designer.text.size", "字号"))
            ui.size = Keep(CreateSlider(root, nil, 8, 32, 1, 12,
                function(value) Patch(SizeField(), value) end, COLUMN_WIDTH))
            ui.sizeGlobal = Keep(GUI2.Form:CreateCheckbox(root, {
                width = 104, height = 20,
                text = T("player_cast.follow_global", "跟随全局"),
                tooltip = T("player_cast.name_size_reset", "跟随全局字号"),
                set = function(value)
                    if value == true then Patch(SizeField(), false, true)
                    else Patch(SizeField(), ui.size:GetValue(), true) end
                end,
            }))
            for _, axis in ipairs({ "X", "Y" }) do
                ui["offset" .. axis .. "Label"] = Keep(NewResourceTextLabel(root,
                    TC("common.offset_" .. axis:lower(), axis .. " 偏移")))
                ui["offset" .. axis] = Keep(CreateSlider(root, nil, -64, 64, 1, 0,
                    function(value) Patch(Prefix() .. "Offset" .. axis, value) end, COLUMN_WIDTH))
            end
        end
    end
    local setting = YHUD:GetResourceSetting(profile, "cast", group.id)
    local cast = setting.cast
    ShowControls(ui.controls)
    local body = self.groupInspectorBody
    if page == "monitor" then
        ui.source:SetShown(group.contentPolicy == "cast-only")
        if group.contentPolicy == "cast-only" then
            Place(ui.source, body, 0, y, CONTENT_WIDTH)
            y = y - 40
        end
        return y
    elseif page == "appearance" then
        PlaceResourceSwitch(ui.iconLabel, ui.icon, body, 0, y)
        PlaceResourceField(ui.iconSideLabel, ui.iconSide, body, SECOND_COLUMN_X, y)
        PlaceResourceField(ui.iconGapLabel, ui.iconGap, body, 0, y - 64)
        ui.icon:SetValue(cast.icon, true)
        ui.iconSide:SetValue(cast.iconSide, true)
        ui.iconGap:SetValue(cast.iconGap, true)
        ui.nativeSession = Designer:GetSession()
        ui.nativeSetId = ui.nativeSession and ui.nativeSession.setId
        ui.native:SetValue(profile.playerCast and profile.playerCast.hideNative == true, true)
        SetDisabled(ui.iconSide, not cast.icon)
        SetDisabled(ui.iconGap, not cast.icon)
        return y - 128
    else
        local name = ui.target == "name"
        local text, prefix = name and cast or setting, name and "name" or "text"
        Place(ui.targetPicker, body, 0, y, CONTENT_WIDTH - SWITCH_WIDTH - 12)
        Place(ui.enabled, body, CONTENT_WIDTH - SWITCH_WIDTH, y, SWITCH_WIDTH)
        ui.targetPicker:SetValue(ui.target, true)
        ui.enabled:SetValue(cast[ui.target], true)
        ui.enabledOptions.tooltip = name and T("player_cast.name", "法术名称")
            or (YUI.IsRetail and T("player_cast.progress_tip", "普通施法和引导使用所选计时格式，蓄力显示阶段。")
                or T("player_cast.progress", "施法进度"))
        y = y - 40
        ui.timeFormatLabel:SetShown(not name)
        ui.timeFormat:SetShown(not name)
        if not name then
            PlaceResourceField(ui.timeFormatLabel, ui.timeFormat, body, 0, y)
            ui.timeFormat:SetValue(cast.timeFormat or "remaining", true)
            SetDisabled(ui.timeFormat, not cast.progress)
            y = y - 64
        end
        PlaceResourceField(ui.positionLabel, ui.position, body, 0, y)
        PlaceResourceField(ui.sizeLabel, ui.size, body, SECOND_COLUMN_X, y)
        ui.sizeLabel:SetWidth(COLUMN_WIDTH - 112)
        Place(ui.sizeGlobal, body, CONTENT_WIDTH - 104, y + 1, 104)
        local style = YHUD:GetEffectiveResourceStyle(profile, group.id, "cast")
        local size = cast[name and "nameSize" or "progressSize"]
        ui.size:SetValue(size or style.textSize, true)
        ui.sizeGlobal:SetValue(size == nil, true)
        SetDisabled(ui.size, not cast[ui.target])
        SetDisabled(ui.sizeGlobal, not cast[ui.target])
        ui.position:SetValue(text[prefix .. "Position"] or (name and "start" or "end"), true)
        SetDisabled(ui.position, not cast[ui.target])
        for index, axis in ipairs({ "X", "Y" }) do
            PlaceResourceField(ui["offset" .. axis .. "Label"], ui["offset" .. axis], body,
                (index - 1) * SECOND_COLUMN_X, y - 64)
            ui["offset" .. axis]:SetValue(text[prefix .. "Offset" .. axis] or 0, true)
            SetDisabled(ui["offset" .. axis], not cast[ui.target])
        end
        return y - 128
    end
end

function I.BuildRangedWindupControls(body, keep)
    local ui = { controls = {} }
    local function Keep(control)
        ui.controls[#ui.controls + 1] = control
        return keep(control)
    end
    local function Set(field, value)
        if DesignerUI.v2Refreshing or DesignerUI.resourceStyleResourceId ~= "swingRanged" then return end
        local session = Designer:GetSession()
        local setting = YHUD:GetResourceSetting(Designer:GetProfile(), "swingRanged", session.selectedGroupId)
        local windup = YHUD:CopyValue(setting.rangedWindup)
        windup[field] = value
        return Designer:SetResourceSetting("swingRanged", { rangedWindup = windup })
    end
    ui.heading = Keep(AddSectionHeading(body, T("designer.resource.windup_title", "射击停步提示")))
    ui.colorLabel = Keep(NewResourceLabel(body, "designer.resource.windup_color", "停步提示颜色"))
    ui.color = Keep(GUI2.Form:CreateColorPicker(body, {
        getDefault = I.ResourceColorDefault("rangedWindup", "color"),
        width = COLUMN_WIDTH, field = true, hasAlpha = true,
        set = function(value) RefreshResourceMutation(Set("color", value), false) end,
    }))
    BindResourceColorPicker(ui.color, "windup", function(value) Set("color", value) end)
    ui.enabledLabel = Keep(NewResourceLabel(body, "designer.resource.windup_marker", "停步刻线"))
    ui.enabled = Keep(GUI2.Form:CreateSwitch(body, {
        width = SWITCH_WIDTH,
        set = function(value) RefreshResourceMutation(Set("markerEnabled", value == true)) end,
    }))
    ui.markerColorLabel = Keep(NewResourceLabel(body, "designer.resource.windup_marker_color", "刻线颜色"))
    ui.markerColor = Keep(GUI2.Form:CreateColorPicker(body, {
        getDefault = I.ResourceColorDefault("rangedWindup", "markerColor"),
        width = COLUMN_WIDTH, field = true, hasAlpha = true,
        set = function(value) RefreshResourceMutation(Set("markerColor", value), false) end,
    }))
    BindResourceColorPicker(ui.markerColor, "thresholdMarker", function(value) Set("markerColor", value) end)
    ui.thicknessLabel = Keep(NewResourceLabel(body, "designer.resource.windup_marker_thickness", "刻线粗细"))
    ui.thickness = Keep(GUI2.Form:CreateSlider(body, {
        width = COLUMN_WIDTH - 48, inline = true, inputWidth = 42,
        min = 1, max = 4, step = 1,
        set = function(value) RefreshResourceSliderMutation(Set("markerThickness", value), "swingRanged") end,
    }))
    ui.help = Keep(NewResourceLabel(body, "designer.resource.windup_help",
        "剩余 0.5 秒时整条进度变色，刻线标记该区间起点。"))
    ui.help:SetWordWrap(true)
    return ui
end

local function BuildResourceEditors(self)
    if self.resourceV2Controls then return end
    local body = self.groupInspectorBody
    local controls = {}
    local function Keep(control)
        controls[#controls + 1] = control
        if control.Hide then control:Hide() end
        return control
    end
    local textGlobalDivider = AddSectionHeading(
        body, T("designer.resource.global_settings", "全局设置")
    )
    local textItemDivider = AddSectionHeading(
        body, T("designer.resource.item_settings", "单项设置")
    )
    local appearanceGlobalDivider = AddSectionHeading(
        body, T("designer.resource.global_settings", "全局设置")
    )
    local appearanceItemDivider = AddSectionHeading(
        body, T("designer.resource.item_settings", "单项设置")
    )
    Keep(textGlobalDivider); Keep(textItemDivider)
    Keep(appearanceGlobalDivider); Keep(appearanceItemDivider)

    local function ResourceSelector()
        return GUI2.Form:CreateDropdown(body, {
            width = COLUMN_WIDTH,
            menuWidth = RESOURCE_MENU_WIDTH,
            options = BuildResourceOptions,
            set = function(value)
                DesignerUI:SelectResourceStyleResource(value)
            end,
        })
    end
    local textResourceLabel = Keep(NewResourceLabel(
        body, "designer.resource.resource", "资源"
    ))
    local textResourceHelp = Keep(CreateResourceHelpButton(body))
    local textResource = Keep(ResourceSelector())
    local textOverrideLabel = Keep(NewResourceLabel(
        body, "designer.resource.override_global", "覆盖全局"
    ))
    local textOverride = Keep(GUI2.Form:CreateSwitch(body, {
        width = SWITCH_WIDTH,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            RefreshResourceMutation(Designer:SetResourceTextOverride(
                DesignerUI.resourceStyleResourceId,
                value == true
            ))
        end,
    }))
    local itemFontLabel = Keep(NewResourceLabel(body, "designer.text.font", "字体"))
    local itemFont = Keep(GUI2.Form:CreateLSMFontDropdown(body, {
        width = COLUMN_WIDTH,
        menuWidth = RESOURCE_MENU_WIDTH,
        prependOptions = BuildFontOptions,
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceTextOverride(
                DesignerUI.resourceStyleResourceId, true, { textFont = value }
            ), false)
        end,
    }))
    local itemOutlineLabel = Keep(NewResourceLabel(body, "designer.text.outline", "描边"))
    local itemOutline = Keep(GUI2.Form:CreateDropdown(body, {
        width = COLUMN_WIDTH,
        menuWidth = RESOURCE_MENU_WIDTH,
        options = BuildOutlineOptions,
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceTextOverride(
                DesignerUI.resourceStyleResourceId, true, { textOutline = value }
            ), false)
        end,
    }))
    local itemSizeLabel = Keep(NewResourceLabel(body, "designer.text.size", "字号"))
    local itemSize = Keep(CreateSlider(
        body, nil, 8, 32, 1, 0,
        function(value)
            local resourceId = DesignerUI.resourceStyleResourceId
            RefreshResourceSliderMutation(
                Designer:SetResourceTextOverride(
                    resourceId, true, { textSize = value }
                ),
                resourceId
            )
        end,
        COLUMN_WIDTH, nil, 52
    ))
    local itemColorLabel = Keep(NewResourceLabel(body, "designer.text.color", "颜色"))
    local itemColor = Keep(GUI2.Form:CreateColorPicker(body, {
        width = COLUMN_WIDTH,
        field = true,
        hasAlpha = true,
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceTextOverride(
                DesignerUI.resourceStyleResourceId, true, { textColor = value }
            ), false)
        end,
    }))
    local positionLabel = Keep(NewResourceLabel(
        body, "designer.resource.position", "位置"
    ))
    local position = Keep(GUI2.Form:CreateDropdown(body, {
        width = COLUMN_WIDTH,
        menuWidth = RESOURCE_MENU_WIDTH,
        options = ResourcePositionOptions,
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceSetting(
                DesignerUI.resourceStyleResourceId, { textPosition = value }
            ), false)
        end,
    }))
    local offsetXLabel = Keep(NewResourceTextLabel(
        body, TC("common.offset_x", "X 偏移")
    ))
    local offsetX = Keep(CreateSlider(
        body, nil, -64, 64, 1, 0,
        function(value)
            local resourceId = DesignerUI.resourceStyleResourceId
            RefreshResourceSliderMutation(
                Designer:SetResourceSetting(
                    resourceId, { textOffsetX = value }
                ),
                resourceId
            )
        end,
        COLUMN_WIDTH, nil, 52
    ))
    local offsetYLabel = Keep(NewResourceTextLabel(
        body, TC("common.offset_y", "Y 偏移")
    ))
    local offsetY = Keep(CreateSlider(
        body, nil, -64, 64, 1, 0,
        function(value)
            local resourceId = DesignerUI.resourceStyleResourceId
            RefreshResourceSliderMutation(
                Designer:SetResourceSetting(
                    resourceId, { textOffsetY = value }
                ),
                resourceId
            )
        end,
        COLUMN_WIDTH, nil, 52
    ))
    local abbreviateLabel = Keep(NewResourceLabel(body,
        "designer.resource.abbreviate_values", "数字缩写"))
    local abbreviate = Keep(GUI2.Form:CreateSwitch(body, {
        width = SWITCH_WIDTH,
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceSetting(
                DesignerUI.resourceStyleResourceId, { abbreviateValues = value == true }
            ), false)
        end,
    }))
    local formatLabel = Keep(NewResourceLabel(
        body, "designer.resource.value_format", "数值显示"
    ))
    local format = Keep(GUI2.Form:CreateDropdown(body, {
        width = COLUMN_WIDTH,
        menuWidth = RESOURCE_MENU_WIDTH,
        options = ResourceFormatOptions,
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceSetting(
                DesignerUI.resourceStyleResourceId,
                value == "none"
                    and { valueText = false }
                    or { valueText = true, valueFormat = value }
            ), true)
        end,
    }))

    local text1Heading = Keep(AddSectionHeading(body, T("designer.resource.text1", "文本1")))
    local second = { heading = Keep(AddSectionHeading(body, T("designer.resource.text2", "文本2"))) }
    local function SetSecond(patch, slider)
        local id = DesignerUI.resourceStyleResourceId
        local session = Designer:GetSession()
        local setting = YHUD:GetResourceSetting(session.draft.profile, id, Designer:GetSession().selectedGroupId)
        local value = YHUD:CopyValue(setting.text2)
        for key, child in pairs(patch) do value[key] = child end
        local changed = Designer:SetResourceSetting(id, { text2 = value })
        if slider then RefreshResourceSliderMutation(changed, id)
        else RefreshResourceMutation(changed, true) end
    end
    second.formatLabel = Keep(NewResourceLabel(body, "designer.resource.value_format", "数值显示"))
    second.format = Keep(GUI2.Form:CreateDropdown(body, {
        width = COLUMN_WIDTH, menuWidth = RESOURCE_MENU_WIDTH, options = ResourceFormatOptions,
        set = function(value) SetSecond(value == "none" and { valueText = false }
            or { valueText = true, valueFormat = value }) end,
    }))
    second.positionLabel = Keep(NewResourceLabel(body, "designer.resource.position", "位置"))
    second.position = Keep(GUI2.Form:CreateDropdown(body, {
        width = COLUMN_WIDTH, menuWidth = RESOURCE_MENU_WIDTH, options = ResourcePositionOptions,
        set = function(value) SetSecond({ textPosition = value }) end,
    }))
    for _, axis in ipairs({ "X", "Y" }) do
        local key = "offset" .. axis
        second[key .. "Label"] = Keep(NewResourceTextLabel(body,
            TC("common.offset_" .. string.lower(axis), axis .. " 偏移")))
        second[key] = Keep(CreateSlider(body, nil, -64, 64, 1, 0,
            function(value) SetSecond({ ["textOffset" .. axis] = value }, true) end,
            COLUMN_WIDTH, nil, 52))
    end
    local overlap = Keep(NewResourceLabel(body, "designer.resource.text_overlap",
        "两个文本的位置相同，显示可能重叠。"))
    overlap:SetWidth(CONTENT_WIDTH)
    overlap:SetHeight(36)
    overlap:SetWordWrap(true)

    local appearanceResourceLabel = Keep(NewResourceLabel(
        body, "designer.resource.resource", "资源"
    ))
    local appearanceResourceHelp = Keep(CreateResourceHelpButton(body))
    local appearanceResource = Keep(ResourceSelector())
    local itemFillDirectionLabel = Keep(NewResourceLabel(body, "designer.resource.fill_direction", "填充方向"))
    local itemFillDirection = Keep(GUI2.Form:CreateDropdown(body, {
        width = COLUMN_WIDTH, menuWidth = RESOURCE_MENU_WIDTH,
        options = function()
            local options = I.BuildResourceFillDirectionOptions()
            table.insert(options, 1, {text=T("designer.resource.fill_inherit", "跟随分组"),value="inherit"})
            return options
        end,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            RefreshResourceMutation(Designer:SetResourceSetting(DesignerUI.resourceStyleResourceId,
                {fillDirection=value ~= "inherit" and value or false}))
        end,
    }))
    local appearanceOverrideLabel = Keep(NewResourceLabel(
        body, "designer.resource.override_global", "覆盖全局"
    ))
    local appearanceOverride = Keep(GUI2.Form:CreateSwitch(body, {
        width = SWITCH_WIDTH,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            RefreshResourceMutation(Designer:SetResourceAppearanceOverride(
                DesignerUI.resourceStyleResourceId,
                value == true
            ))
        end,
    }))
    local itemBorderLabel = Keep(NewResourceLabel(body, "designer.appearance.border", "边框"))
    local itemBorder = Keep(GUI2.Form:CreateSlider(body, {
        width = COLUMN_WIDTH,
        inline = true,
        inputWidth = 42,
        min = 0,
        max = 12,
        step = 1,
        set = function(value)
            RefreshResourceSliderMutation(Designer:SetResourceAppearanceOverride(
                DesignerUI.resourceStyleResourceId, true, { border = value }
            ), DesignerUI.resourceStyleResourceId)
        end,
    }))
    local itemBackgroundLabel = Keep(NewResourceLabel(body, "designer.resource.background", "背景颜色"))
    local itemBackground = Keep(GUI2.Form:CreateColorPicker(body, {
        width = COLUMN_WIDTH, field = true, hasAlpha = true,
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceAppearanceOverride(
                DesignerUI.resourceStyleResourceId, true, { backgroundColor = value }
            ), false)
        end,
    }))
    local itemTextureLabel = Keep(NewResourceLabel(body, "designer.appearance.texture", "条材质"))
    local itemTexture = Keep(S:CreateTextureSelector(body, {
        width = COLUMN_WIDTH,
        menuWidth = RESOURCE_MENU_WIDTH,
        get = function() return "yui-g1" end,
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceAppearanceOverride(
                DesignerUI.resourceStyleResourceId, true, { fillTexture = value }
            ), false)
        end,
    }))
    local itemFillModeLabel = Keep(NewResourceLabel(body, "designer.resource.fill_mode", "填充颜色"))
    local itemFillMode = Keep(GUI2.Form:CreateDropdown(body, {
        width = COLUMN_WIDTH,
        menuWidth = RESOURCE_MENU_WIDTH,
        options = function()
            return {
                { text = T("designer.resource.resource_color", "资源色"), value = "resource" },
                { text = T("designer.resource.custom_color", "自定义"), value = "custom" },
            }
        end,
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceAppearanceOverride(
                DesignerUI.resourceStyleResourceId, true, { fillColorMode = value }
            ))
        end,
    }))
    local itemFillColorLabel = Keep(NewResourceLabel(body, "designer.appearance.fill_color", "填充颜色"))
    local itemFillColor = Keep(GUI2.Form:CreateColorPicker(body, {
        getDefault = I.ResourceColorDefault("fillColor"),
        width = COLUMN_WIDTH, field = true, hasAlpha = true,
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceSetting(
                DesignerUI.resourceStyleResourceId,
                { fillColor = value }
            ), false)
        end,
    }))
    local heightOverrideLabel = Keep(NewResourceLabel(
        body, "designer.resource.height_override", "覆盖高度"
    ))
    local heightOverride = Keep(GUI2.Form:CreateSwitch(body, {
        width = SWITCH_WIDTH,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            local profile = Designer:GetProfile()
            local session = Designer:GetSession()
            local layout = profile and session
                and YHUD:GetResourceGroupLayout(
                    profile,
                    session.selectedGroupId
                ) or nil
            RefreshResourceMutation(Designer:SetResourceSetting(
                DesignerUI.resourceStyleResourceId,
                {
                    heightOverride = value == true
                        and (layout and layout.height or 16)
                        or false,
                }
            ))
        end,
    }))
    local itemHeightLabel = Keep(NewResourceLabel(
        body, "designer.resource.item_height", "单项高度"
    ))
    local itemHeight = Keep(GUI2.Form:CreateSlider(body, {
        width = COLUMN_WIDTH,
        inline = true,
        inputWidth = 42,
        min = 1,
        max = 160,
        step = 1,
        set = function(value)
            local resourceId = DesignerUI.resourceStyleResourceId
            RefreshResourceSliderMutation(Designer:SetResourceSetting(
                resourceId,
                { heightOverride = value }
            ), resourceId, true)
        end,
    }))
    local function SetRuneColor(key, value)
        local resourceId = DesignerUI.resourceStyleResourceId
        local profile = Designer:GetProfile()
        local setting = profile and YHUD:GetResourceSetting(profile, resourceId, Designer:GetSession().selectedGroupId)
        local colors = setting and YHUD:CopyValue(setting.runeColors) or {}
        colors[key] = value
        return Designer:SetResourceSetting(
            resourceId,
            { runeColors = colors }
        )
    end
    local runeBloodColorLabel = Keep(NewResourceLabel(
        body, "designer.resource.rune_color_blood", "鲜血符文颜色"
    ))
    local runeBloodColor = Keep(GUI2.Form:CreateColorPicker(body, {
        getDefault = I.ResourceColorDefault("runeColors", "blood"),
        width = COLUMN_WIDTH, field = true, hasAlpha = true,
        set = function(value) SetRuneColor("blood", value) end,
    }))
    local runeFrostColorLabel = Keep(NewResourceLabel(
        body, "designer.resource.rune_color_frost", "冰霜符文颜色"
    ))
    local runeFrostColor = Keep(GUI2.Form:CreateColorPicker(body, {
        getDefault = I.ResourceColorDefault("runeColors", "frost"),
        width = COLUMN_WIDTH, field = true, hasAlpha = true,
        set = function(value) SetRuneColor("frost", value) end,
    }))
    local runeUnholyColorLabel = Keep(NewResourceLabel(
        body, "designer.resource.rune_color_unholy", "邪恶符文颜色"
    ))
    local runeUnholyColor = Keep(GUI2.Form:CreateColorPicker(body, {
        getDefault = I.ResourceColorDefault("runeColors", "unholy"),
        width = COLUMN_WIDTH, field = true, hasAlpha = true,
        set = function(value) SetRuneColor("unholy", value) end,
    }))
    local runeCooldownTextModeLabel = Keep(NewResourceLabel(
        body, "designer.resource.rune_cooldown_text_mode", "符文倒计时"
    ))
    local runeCooldownTextMode = Keep(GUI2.Form:CreateDropdown(body, {
        width = COLUMN_WIDTH,
        options = {
            { text = T("designer.resource.rune_text.all", "全部显示"), value = "all" },
            { text = T("designer.resource.rune_text.none", "全部关闭"), value = "none" },
            { text = T("designer.resource.rune_text.shortest", "只显示最短倒计时"), value = "shortest" },
        },
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceSetting(
                DesignerUI.resourceStyleResourceId, { runeCooldownTextMode = value }
            ), false)
        end,
    }))
    local runeCooldownTextSizeLabel = Keep(NewResourceLabel(
        body,
        "designer.resource.rune_cooldown_text_size",
        "符文冷却字号"
    ))
    local runeCooldownTextSize = Keep(CreateSlider(
        body, nil, 8, 32, 1, 0,
        function(value)
            local resourceId = DesignerUI.resourceStyleResourceId
            RefreshResourceSliderMutation(Designer:SetResourceSetting(
                resourceId,
                { runeCooldownTextSize = value }
            ), resourceId)
        end,
        COLUMN_WIDTH, nil, 52
    ))
    local itemBorderColorLabel = Keep(NewResourceLabel(body, "designer.appearance.border_color", "边框颜色"))
    local itemBorderColor = Keep(GUI2.Form:CreateColorPicker(body, {
        width = COLUMN_WIDTH, field = true, hasAlpha = true,
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceAppearanceOverride(
                DesignerUI.resourceStyleResourceId, true, { borderColor = value }
            ), false)
        end,
    }))
    local visibilityModeLabel = Keep(NewResourceLabel(
        body, "designer.resource.visibility", "显示条件"
    ))
    local visibilityMode = Keep(GUI2.Form:CreateDropdown(body, {
        width = COLUMN_WIDTH,
        menuWidth = CONTENT_WIDTH,
        options = ResourceVisibilityModeOptions,
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceSetting(
                DesignerUI.resourceStyleResourceId,
                { visibilityMode = value }
            ))
        end,
    }))
    local displayModeLabel = Keep(NewResourceLabel(
        body, "designer.resource.display_mode", "显示模式"
    ))
    local displayMode = Keep(GUI2.Form:CreateDropdown(body, {
        width = COLUMN_WIDTH,
        menuWidth = RESOURCE_MENU_WIDTH,
        options = ResourceDisplayModeOptions,
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceSetting(
                DesignerUI.resourceStyleResourceId,
                { displayMode = value }
            ))
        end,
    }))
    local segmentSpacingLabel = Keep(NewResourceLabel(
        body, "designer.resource.segment_spacing", "最小格间距"
    ))
    local inverseFillLabel = Keep(NewResourceLabel(
        body, "designer.resource.inverse_fill", "反向填充"
    ))
    local inverseFill = Keep(GUI2.Form:CreateSwitch(body, {
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceSetting(
                DesignerUI.resourceStyleResourceId, { inverseFill = value == true }
            ))
        end,
    }))
    local segmentSpacing = Keep(GUI2.Form:CreateSlider(body, {
        width = COLUMN_WIDTH, inline = true, inputWidth = 42,
        min = -5, max = 32, step = 1,
        set = function(value)
            local resourceId = DesignerUI.resourceStyleResourceId
            RefreshResourceSliderMutation(Designer:SetResourceSetting(
                resourceId, { segmentSpacing = value }
            ), resourceId, true)
        end,
    }))
    local dotSpacingLabel = Keep(NewResourceLabel(
        body, "designer.resource.dot_spacing", "点间距"
    ))
    local dotSpacing = Keep(GUI2.Form:CreateSlider(body, {
        width = COLUMN_WIDTH, inline = true, inputWidth = 42,
        min = 0, max = 100, step = 1,
        set = function(value)
            local resourceId = DesignerUI.resourceStyleResourceId
            RefreshResourceSliderMutation(Designer:SetResourceSetting(
                resourceId, { segmentSpacing = value }
            ), resourceId, true)
        end,
    }))
    local pointControls = {}
    pointControls.shapeLabel = Keep(NewResourceLabel(body, "designer.resource.point_shape", "形状"))
    pointControls.shape = Keep(GUI2.Form:CreateDropdown(body, {
        width = COLUMN_WIDTH, menuWidth = RESOURCE_MENU_WIDTH, options = I.ResourcePointShapeOptions,
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceSetting(
                DesignerUI.resourceStyleResourceId, { pointShape = value }))
        end,
    }))
    pointControls.nativeLabel = Keep(NewResourceLabel(body, "designer.resource.native_point", "原生样式"))
    pointControls.native = Keep(GUI2.Form:CreateDropdown(body, {
        width = COLUMN_WIDTH, menuWidth = RESOURCE_MENU_WIDTH, options = I.ResourceNativePointOptions,
        tooltip = T("designer.resource.native_point_help", "只改变外观；点数、上限和恢复进度来自当前资源。"),
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceSetting(
                DesignerUI.resourceStyleResourceId, { nativePointStyle = value }))
        end,
    }))
    pointControls.unavailable = Keep(NewResourceLabel(body, "designer.resource.native_point_unavailable",
        "当前客户端缺少此原生外观，暂用圆形。"))
    pointControls.unavailable:SetWordWrap(true)
    local dividerThicknessLabel = Keep(NewResourceLabel(
        body, "designer.resource.divider_thickness", "分隔线粗细"
    ))
    local dividerThickness = Keep(GUI2.Form:CreateSlider(body, {
        width = COLUMN_WIDTH - 48, inline = true, inputWidth = 42,
        min = 1, max = 4, step = 1,
        set = function(value)
            local resourceId = DesignerUI.resourceStyleResourceId
            RefreshResourceSliderMutation(Designer:SetResourceSetting(
                resourceId, { dividerThickness = value }
            ), resourceId)
        end,
    }))
    local dividerColorLabel = Keep(NewResourceLabel(
        body, "designer.resource.divider_color", "分隔线颜色"
    ))
    local dividerColor = Keep(GUI2.Form:CreateColorPicker(body, {
        getDefault = I.ResourceColorDefault("dividerColor"),
        width = 40, field = false, hasAlpha = true,
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceSetting(
                DesignerUI.resourceStyleResourceId,
                { dividerColor = value }
            ), false)
        end,
    }))
    local thresholdDivider = Keep(AddSectionHeading(
        body, T("designer.resource.threshold_settings", "阈值设置")
    ))
    local thresholdColorEnabledLabel = Keep(NewResourceLabel(
        body, "designer.resource.threshold_color_enabled", "阈值变色"
    ))
    local thresholdColorEnabled = Keep(GUI2.Form:CreateSwitch(body, {
        width = SWITCH_WIDTH,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            RefreshResourceMutation(Designer:SetResourceSetting(
                DesignerUI.resourceStyleResourceId,
                { thresholdColorEnabled = value == true }
            ))
        end,
    }))
    local thresholdMarkerEnabledLabel = Keep(NewResourceLabel(
        body, "designer.resource.threshold_marker_enabled", "阈值刻线"
    ))
    local thresholdMarkerEnabled = Keep(GUI2.Form:CreateSwitch(body, {
        width = SWITCH_WIDTH,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            RefreshResourceMutation(Designer:SetResourceSetting(
                DesignerUI.resourceStyleResourceId,
                { thresholdMarkerEnabled = value == true }
            ))
        end,
    }))
    local lowEnabledLabel = Keep(NewResourceLabel(
        body, "designer.resource.threshold_low_enabled", "低阈值"
    ))
    local lowEnabled = Keep(GUI2.Form:CreateSwitch(body, {
        width = SWITCH_WIDTH,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            RefreshResourceMutation(SetResourceThreshold(
                DesignerUI.resourceStyleResourceId,
                "low", "enabled", value == true
            ))
        end,
    }))
    local highEnabledLabel = Keep(NewResourceLabel(
        body, "designer.resource.threshold_high_enabled", "高阈值"
    ))
    local highEnabled = Keep(GUI2.Form:CreateSwitch(body, {
        width = SWITCH_WIDTH,
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            RefreshResourceMutation(SetResourceThreshold(
                DesignerUI.resourceStyleResourceId,
                "high", "enabled", value == true
            ))
        end,
    }))
    local lowValueLabel = Keep(NewResourceLabel(
        body, "designer.resource.threshold_low_percent", "低阈值（%）"
    ))
    local highValueLabel = Keep(NewResourceLabel(
        body, "designer.resource.threshold_high_percent", "高阈值（%）"
    ))
    local function ThresholdValueSlider(side, maximum)
        return Keep(GUI2.Form:CreateSlider(body, {
            width = COLUMN_WIDTH - 48, inline = true, inputWidth = 42,
            min = 0, max = maximum, step = 1,
            set = function(value)
                local resourceId = DesignerUI.resourceStyleResourceId
                RefreshResourceSliderMutation(SetResourceThreshold(
                    resourceId, side, "value", value
                ), resourceId)
            end,
        }))
    end
    local lowPercent = ThresholdValueSlider("low", 100)
    local highPercent = ThresholdValueSlider("high", 100)
    local lowCount = ThresholdValueSlider("low", 20)
    local highCount = ThresholdValueSlider("high", 25)
    local thresholdModeLabel = Keep(NewResourceLabel(
        body, "designer.resource.threshold_mode", "阈值依据"
    ))
    local thresholdMode = Keep(GUI2.Form:CreateDropdown(body, {
        width = COLUMN_WIDTH,
        options = {
            { text = T("designer.resource.threshold_mode.percent", "百分比"), value = "percent" },
            { text = T("designer.resource.threshold_mode.value", "数值"), value = "value" },
        },
        set = function(value)
            if DesignerUI.v2Refreshing then return end
            RefreshResourceMutation(DesignerUI:SetResourceThresholdMode(DesignerUI.resourceStyleResourceId, value))
        end,
    }))
    local function ThresholdValueInput(side)
        local function Commit(input)
            if DesignerUI.v2Refreshing or not input._thresholdResourceId then return end
            local resourceId = input._thresholdResourceId
            input._thresholdResourceId = nil
            local profile = input._thresholdProfile
            input._thresholdProfile = nil
            if Designer:GetProfile() ~= profile then return end
            local setting = YHUD:GetResourceSetting(Designer:GetProfile(), resourceId, Designer:GetSession().selectedGroupId)
            local value = tonumber(input:GetText())
            if setting and setting.thresholdMode == "value" and value and value == value
                and value >= 0 and value <= 1000000000 then
                RefreshResourceMutation(SetResourceThreshold(resourceId, side, "value", math.floor(value)))
            end
            setting = YHUD:GetResourceSetting(Designer:GetProfile(), resourceId, Designer:GetSession().selectedGroupId)
            if setting then input:SetValue(setting.thresholds[side].value, true) end
        end
        local input = Keep(GUI2.Form:CreateEditBox(body, {
            width = COLUMN_WIDTH,
            tooltip = T("designer.resource.threshold_value_hint", "固定资源数值；上限变化不会修改设定。超过当前上限的刻线暂不显示。"),
            onFocusGained = function(control)
                control._thresholdResourceId = DesignerUI.resourceStyleResourceId
                control._thresholdProfile = Designer:GetProfile()
            end,
            onFocusLost = Commit,
        }))
        input:SetScript("OnEnterPressed", function(control) control:ClearFocus() end)
        input:SetScript("OnEscapePressed", function(control)
            control._thresholdResourceId = nil
            control._thresholdProfile = nil
            local setting = YHUD:GetResourceSetting(Designer:GetProfile(), DesignerUI.resourceStyleResourceId, Designer:GetSession().selectedGroupId)
            control:SetValue(setting.thresholds[side].value, true)
            control:ClearFocus()
        end)
        return input
    end
    local lowAbsolute = ThresholdValueInput("low")
    local highAbsolute = ThresholdValueInput("high")
    local lowColorLabel = Keep(NewResourceLabel(
        body, "designer.resource.threshold_low_color", "低区间颜色"
    ))
    local lowColor = Keep(GUI2.Form:CreateColorPicker(body, {
        getDefault = function()
            local threshold = I.ResourceColorDefault("thresholds", "low")()
            return threshold and threshold.color
        end,
        width = COLUMN_WIDTH, field = true, hasAlpha = true,
        set = function(value)
            RefreshResourceMutation(SetResourceThreshold(
                DesignerUI.resourceStyleResourceId,
                "low", "color", value
            ), false)
        end,
    }))
    local highColorLabel = Keep(NewResourceLabel(
        body, "designer.resource.threshold_high_color", "高区间颜色"
    ))
    local highColor = Keep(GUI2.Form:CreateColorPicker(body, {
        getDefault = function()
            local threshold = I.ResourceColorDefault("thresholds", "high")()
            return threshold and threshold.color
        end,
        width = COLUMN_WIDTH, field = true, hasAlpha = true,
        set = function(value)
            RefreshResourceMutation(SetResourceThreshold(
                DesignerUI.resourceStyleResourceId,
                "high", "color", value
            ), false)
        end,
    }))
    local thresholdMarkerThicknessLabel = Keep(NewResourceLabel(
        body, "designer.resource.threshold_marker_thickness", "刻线粗细"
    ))
    local thresholdMarkerThickness = Keep(GUI2.Form:CreateSlider(body, {
        width = COLUMN_WIDTH, inline = true, inputWidth = 42,
        min = 1, max = 4, step = 1,
        set = function(value)
            local resourceId = DesignerUI.resourceStyleResourceId
            RefreshResourceSliderMutation(Designer:SetResourceSetting(
                resourceId, { thresholdMarkerThickness = value }
            ), resourceId)
        end,
    }))
    local thresholdMarkerColorLabel = Keep(NewResourceLabel(
        body, "designer.resource.threshold_marker_color", "刻线颜色"
    ))
    local thresholdMarkerColor = Keep(GUI2.Form:CreateColorPicker(body, {
        getDefault = I.ResourceColorDefault("thresholdMarkerColor"),
        width = COLUMN_WIDTH, field = true, hasAlpha = true,
        set = function(value)
            RefreshResourceMutation(Designer:SetResourceSetting(
                DesignerUI.resourceStyleResourceId,
                { thresholdMarkerColor = value }
            ), false)
        end,
    }))
    BindResourceColorPicker(itemColor, "text", function(value)
        Designer:SetResourceTextOverride(
            DesignerUI.resourceStyleResourceId,
            true,
            { textColor = value }
        )
    end)
    BindResourceColorPicker(itemBackground, "background", function(value)
        Designer:SetResourceAppearanceOverride(
            DesignerUI.resourceStyleResourceId,
            true,
            { backgroundColor = value }
        )
    end)
    BindResourceColorPicker(itemFillColor, "fill", function(value)
        Designer:SetResourceSetting(
            DesignerUI.resourceStyleResourceId,
            { fillColor = value }
        )
    end)
    BindResourceColorPicker(runeBloodColor, "fill", function(value)
        SetRuneColor("blood", value)
    end)
    BindResourceColorPicker(runeFrostColor, "fill", function(value)
        SetRuneColor("frost", value)
    end)
    BindResourceColorPicker(runeUnholyColor, "fill", function(value)
        SetRuneColor("unholy", value)
    end)
    BindResourceColorPicker(itemBorderColor, "border", function(value)
        Designer:SetResourceAppearanceOverride(
            DesignerUI.resourceStyleResourceId,
            true,
            { borderColor = value }
        )
    end)
    BindResourceColorPicker(dividerColor, "divider", function(value)
        Designer:SetResourceSetting(
            DesignerUI.resourceStyleResourceId,
            { dividerColor = value }
        )
    end)
    BindResourceColorPicker(lowColor, "thresholdLow", function(value)
        SetResourceThreshold(
            DesignerUI.resourceStyleResourceId,
            "low",
            "color",
            value
        )
    end)
    BindResourceColorPicker(highColor, "thresholdHigh", function(value)
        SetResourceThreshold(
            DesignerUI.resourceStyleResourceId,
            "high",
            "color",
            value
        )
    end)
    BindResourceColorPicker(
        thresholdMarkerColor,
        "thresholdMarker",
        function(value)
            Designer:SetResourceSetting(
                DesignerUI.resourceStyleResourceId,
                { thresholdMarkerColor = value }
            )
        end
    )
    local textRestoreDefaults = Keep(GUI2.Form:CreateButton(body, {
        text = T("designer.resource.restore_global_defaults", "恢复全局设置默认值"),
        width = COLUMN_WIDTH,
        height = 24,
        onClick = function() RestoreResourceGlobalStyle("text") end,
    }))
    local appearanceRestoreDefaults = Keep(GUI2.Form:CreateButton(body, {
        text = T("designer.resource.restore_global_defaults", "恢复全局设置默认值"),
        width = COLUMN_WIDTH,
        height = 24,
        onClick = function() RestoreResourceGlobalStyle("appearance") end,
    }))

    self.resourceV2Controls = controls
    self.resourceV2Text = {
        globalFont = Keep(GUI2.Form:CreateFontStyle(body, {key="yhud:unbound", width=CONTENT_WIDTH})),
        itemFont = Keep(GUI2.Form:CreateFontStyle(body, {key="yhud:unbound", width=CONTENT_WIDTH})),
        text1Heading = text1Heading, second = second, overlap = overlap,
        globalDivider = textGlobalDivider,
        itemDivider = textItemDivider,
        resourceLabel = textResourceLabel, resourceHelp = textResourceHelp,
        resource = textResource,
        overrideLabel = textOverrideLabel, override = textOverride,
        fontLabel = itemFontLabel, font = itemFont,
        outlineLabel = itemOutlineLabel, outline = itemOutline,
        sizeLabel = itemSizeLabel, size = itemSize,
        colorLabel = itemColorLabel, color = itemColor,
        positionLabel = positionLabel, position = position,
        offsetXLabel = offsetXLabel, offsetX = offsetX,
        offsetYLabel = offsetYLabel, offsetY = offsetY,
        formatLabel = formatLabel, format = format,
        abbreviateLabel = abbreviateLabel, abbreviate = abbreviate,
        restoreDefaults = textRestoreDefaults,
    }
    self.resourceV2Appearance = {
        windup = I.BuildRangedWindupControls(body, Keep),
        globalDivider = appearanceGlobalDivider,
        itemDivider = appearanceItemDivider,
        resourceLabel = appearanceResourceLabel,
        resourceHelp = appearanceResourceHelp,
        resource = appearanceResource,
        overrideLabel = appearanceOverrideLabel, override = appearanceOverride,
        borderLabel = itemBorderLabel, border = itemBorder,
        backgroundLabel = itemBackgroundLabel, background = itemBackground,
        textureLabel = itemTextureLabel, texture = itemTexture,
        fillModeLabel = itemFillModeLabel, fillMode = itemFillMode,
        fillColorLabel = itemFillColorLabel, fillColor = itemFillColor,
        fillDirectionLabel = itemFillDirectionLabel, fillDirection = itemFillDirection,
        heightOverrideLabel = heightOverrideLabel,
        heightOverride = heightOverride,
        heightLabel = itemHeightLabel,
        height = itemHeight,
        runeBloodColorLabel = runeBloodColorLabel,
        runeBloodColor = runeBloodColor,
        runeFrostColorLabel = runeFrostColorLabel,
        runeFrostColor = runeFrostColor,
        runeUnholyColorLabel = runeUnholyColorLabel,
        runeUnholyColor = runeUnholyColor,
        runeCooldownTextModeLabel = runeCooldownTextModeLabel,
        runeCooldownTextMode = runeCooldownTextMode,
        runeCooldownTextSizeLabel = runeCooldownTextSizeLabel,
        runeCooldownTextSize = runeCooldownTextSize,
        borderColorLabel = itemBorderColorLabel, borderColor = itemBorderColor,
        visibilityModeLabel = visibilityModeLabel,
        visibilityMode = visibilityMode,
        displayModeLabel = displayModeLabel, displayMode = displayMode,
        inverseFillLabel = inverseFillLabel, inverseFill = inverseFill,
        segmentSpacingLabel = segmentSpacingLabel, segmentSpacing = segmentSpacing,
        dotSpacingLabel = dotSpacingLabel, dotSpacing = dotSpacing,
        pointShapeLabel = pointControls.shapeLabel, pointShape = pointControls.shape,
        nativePointLabel = pointControls.nativeLabel, nativePoint = pointControls.native,
        nativePointUnavailable = pointControls.unavailable,
        dividerThicknessLabel = dividerThicknessLabel,
        dividerThickness = dividerThickness,
        dividerColorLabel = dividerColorLabel, dividerColor = dividerColor,
        thresholdDivider = thresholdDivider,
        thresholdColorEnabledLabel = thresholdColorEnabledLabel,
        thresholdColorEnabled = thresholdColorEnabled,
        thresholdMarkerEnabledLabel = thresholdMarkerEnabledLabel,
        thresholdMarkerEnabled = thresholdMarkerEnabled,
        lowEnabledLabel = lowEnabledLabel, lowEnabled = lowEnabled,
        highEnabledLabel = highEnabledLabel, highEnabled = highEnabled,
        lowValueLabel = lowValueLabel, highValueLabel = highValueLabel,
        lowPercent = lowPercent, highPercent = highPercent,
        lowCount = lowCount, highCount = highCount,
        lowAbsolute = lowAbsolute, highAbsolute = highAbsolute,
        thresholdModeLabel = thresholdModeLabel, thresholdMode = thresholdMode,
        lowColorLabel = lowColorLabel, lowColor = lowColor,
        highColorLabel = highColorLabel, highColor = highColor,
        thresholdMarkerThicknessLabel = thresholdMarkerThicknessLabel,
        thresholdMarkerThickness = thresholdMarkerThickness,
        thresholdMarkerColorLabel = thresholdMarkerColorLabel,
        thresholdMarkerColor = thresholdMarkerColor,
        restoreDefaults = appearanceRestoreDefaults,
    }
end

local function BuildV2(self)
    if self.v2Built then return end
    self.v2Built = true
    BuildToolbar(self)
    BuildPageShell(self)
    if self.groupSummary then self.groupSummary:Hide() end
    PromoteLegacyFormText(self)
    self:RefreshDesignerGeometry()
end

local function EnsureV2PageBuilt(self, page, group)
    local needsDetails = page ~= "common"
        or (group and group.layout == "resource")
    if needsDetails and self._legacyDetailsBuilt ~= true then
        local ok, code = BuildInspectorFoundation(self)
        if not ok then return nil, code end
        -- The detail controls are built lazily, after BuildV2's initial style
        -- promotion.  Promote the newly created labels as well so adopted
        -- fields match native V2 slider labels in size and color.
        PromoteLegacyFormText(self)
        BindAdoptedColorPickers(self)
    end
    if page == "layout" or page == "appearance" or page == "text" then
        BuildNumericSliders(self)
    end
    if page == "monitor" and group and group.layout ~= "resource" then
        BuildMonitorBrowser(self)
    elseif page == "text" then
        if group and group.layout == "resource" then
            BuildResourceEditors(self)
        else
            BuildTextEditor(self)
        end
    elseif page == "appearance" and group and group.layout == "resource" then
        BuildResourceEditors(self)
    end
    return true
end

function DesignerUI:EnsureUIShell()
    if self._legacyCoreBuilt and self.v2Built then return true end
    self._legacyCoreOnly = true
    local ok, code = BuildInspectorFoundation(self)
    self._legacyCoreOnly = nil
    if not ok then return ok, code end
    BuildV2(self)
    return true
end

function DesignerUI:EnsureUICurrentPage()
    local ok, code = self:EnsureUIShell()
    if not ok then return ok, code end
    local _, _, group = SelectedContext()
    ok, code = EnsureV2PageBuilt(
        self,
        self.propertyPage or "common",
        group
    )
    if ok == nil then return nil, code end
    return true
end

function DesignerUI:EnsureUI()
    local ok, code = self:EnsureUICurrentPage()
    if not ok then return ok, code end
    return true
end

function DesignerUI:StopResourceValuePreview(clearFocus, refreshPreview)
    if clearFocus == true then self.resourceSpecialPreview = nil end
    local Animation = YUI.Animation
    local owner = self.resourceValuePreviewOwner
    local hadPreview = self.resourceValuePreviewResourceId ~= nil
        or self.resourceValuePreviewHandle ~= nil
        or self.resourceValuePreviewHoldTimer ~= nil
    self.resourceValuePreviewGeneration =
        (self.resourceValuePreviewGeneration or 0) + 1
    if owner and Animation and Animation.StopOwner then
        Animation:StopOwner(owner, false)
    end
    self.resourceValuePreviewHandle = nil
    local holdTimer = self.resourceValuePreviewHoldTimer
    if holdTimer and holdTimer.Cancel then holdTimer:Cancel() end
    self.resourceValuePreviewHoldTimer = nil
    self.resourceValuePreviewLastStep = nil
    self.resourceValuePreviewResourceId = nil
    self.resourceValuePreviewProgress = nil
    if hadPreview then
        DesignerUI:AddResourcePreviewStat("resourcePreviewCleanups", 1)
    end

    local View = YHUD.View
    local focusChanged = clearFocus == true
        and View
        and View.SetResourceStylePreviewResource
        and View:SetResourceStylePreviewResource(nil, true)
    if focusChanged and refreshPreview == true and self.active then
        self:PreviewSelectedGroup()
        DesignerUI:AddResourcePreviewStat("resourcePreviewGroupRefreshes", 1)
        DesignerUI:AddResourcePreviewStat("resourcePreviewFullRefreshAvoided", 1)
    end
    return focusChanged == true
end

local function ResourceValuePreviewIsCurrent(resourceId)
    local _, _, group = SelectedContext()
    return DesignerUI.active == true
        and group and group.layout == "resource"
        and DesignerUI.resourceValuePreviewResourceId == resourceId
        and DesignerUI.resourceStyleResourceId == resourceId
        and (DesignerUI.propertyPage == "text"
            or DesignerUI.propertyPage == "appearance")
end

function DesignerUI:ReapplyResourceValuePreview()
    local resourceId = self.resourceValuePreviewResourceId
    local progress = self.resourceValuePreviewProgress
    local View = YHUD.View
    if not (resourceId and progress ~= nil
        and View and View.SetDesignResourceValuePreview
        and ResourceValuePreviewIsCurrent(resourceId)) then
        return false
    end
    local special = self.resourceSpecialPreview
    if View.RefreshDesignResourceCountdown then
        local applied, countdown = View:RefreshDesignResourceCountdown(resourceId,View.resourceStylePreviewGroupId)
        if countdown then return applied, true end
    end
    return View:SetDesignResourceValuePreview(resourceId, progress,
        special and special.resourceId == resourceId and special.mode == "manual" and special.value or nil,
        View.resourceStylePreviewGroupId)
end

function DesignerUI:StartResourceValuePreview(resourceId)
    local _, _, group = SelectedContext()
    local page = self.propertyPage
    if not (self.active and group and group.layout == "resource"
        and (page == "text" or page == "appearance" or page == "layout")
        and resourceId) then
        return false
    end

    local View = YHUD.View
    local Animation = YUI.Animation
    if not (View and View.SetResourceStylePreviewResource
        and View.SetDesignResourceValuePreview) then
        return false
    end

    local focusChanged = View:SetResourceStylePreviewResource(resourceId, true, group.id)
    if focusChanged then
        if not self:PreviewSelectedGroup() then
            View:SetResourceStylePreviewResource(nil, true)
            return false
        end
        DesignerUI:AddResourcePreviewStat("resourcePreviewGroupRefreshes", 1)
        DesignerUI:AddResourcePreviewStat("resourcePreviewFullRefreshAvoided", 1)
    end

    self:StopResourceValuePreview(false, false)
    if not self.resourceValuePreviewOwner then
        self.resourceValuePreviewOwner = {}
    end
    self.resourceValuePreviewResourceId = resourceId
    self.resourceValuePreviewProgress = 0
    local _, countdown = self:ReapplyResourceValuePreview()
    if countdown then return true end
    if self.resourceSpecialPreview and self.resourceSpecialPreview.resourceId == resourceId
        and self.resourceSpecialPreview.mode == "manual" then return true end
    if not (Animation and Animation.Tween and Animation.StopOwner) then
        return true
    end

    local owner = self.resourceValuePreviewOwner
    local generation = self.resourceValuePreviewGeneration
    local PlayRamp
    PlayRamp = function()
        if DesignerUI.resourceValuePreviewGeneration ~= generation
            or not ResourceValuePreviewIsCurrent(resourceId) then
            return
        end
        DesignerUI:AddResourcePreviewStat("resourcePreviewLoops", 1)
        DesignerUI.resourceValuePreviewProgress = 0
        DesignerUI.resourceValuePreviewLastStep = 0
        DesignerUI:ReapplyResourceValuePreview()
        DesignerUI.resourceValuePreviewHandle = Animation:Tween({
            owner = owner,
            target = DesignerUI.panel,
            key = "yhud-resource-value-preview",
            from = 0,
            to = 1,
            duration = RESOURCE_PREVIEW_SECONDS,
            easing = "linear",
            onUpdate = function(progress)
                DesignerUI:AddResourcePreviewStat(
                    "resourcePreviewAnimationFrames",
                    1
                )
                if DesignerUI.resourceValuePreviewGeneration == generation
                    and ResourceValuePreviewIsCurrent(resourceId) then
                    local step = math.min(
                        150,
                        math.floor(
                            (progress * 150) + 0.00001
                        )
                    )
                    if step == DesignerUI.resourceValuePreviewLastStep then
                        DesignerUI:AddResourcePreviewStat(
                            "resourcePreviewFrameSkips",
                            1
                        )
                        return
                    end
                    DesignerUI.resourceValuePreviewLastStep = step
                    DesignerUI.resourceValuePreviewProgress = progress
                    DesignerUI:ReapplyResourceValuePreview()
                end
            end,
            onFinished = function(_, _, finished)
                if DesignerUI.resourceValuePreviewGeneration == generation then
                    DesignerUI.resourceValuePreviewHandle = nil
                end
                if not finished
                    or DesignerUI.resourceValuePreviewGeneration ~= generation
                    or not ResourceValuePreviewIsCurrent(resourceId) then
                    return
                end
                DesignerUI.resourceValuePreviewProgress = 1
                DesignerUI:ReapplyResourceValuePreview()
                local timerAPI = _G.C_Timer
                if not (timerAPI and timerAPI.NewTimer) then return end
                DesignerUI:AddResourcePreviewStat(
                    "resourcePreviewHoldTimers",
                    1
                )
                DesignerUI.resourceValuePreviewHoldTimer = timerAPI.NewTimer(
                    RESOURCE_PREVIEW_HOLD_SECONDS,
                    function()
                        DesignerUI.resourceValuePreviewHoldTimer = nil
                        if DesignerUI.resourceValuePreviewGeneration == generation
                            and ResourceValuePreviewIsCurrent(resourceId) then
                            PlayRamp()
                        end
                    end
                )
            end,
        })
    end
    PlayRamp()
    return true
end

function DesignerUI:SelectResourceStyleResource(resourceId)
    if YHUD.ResourceManager then
        local found = false
        for _, option in ipairs(BuildResourceOptions()) do if option.value == resourceId then found = true break end end
        if not found then return false end
    end
    local definition = resourceId and ResourceCatalog
        and ResourceCatalog.GetDefinition
        and ResourceCatalog:GetDefinition(resourceId, Designer:GetProfile(), Designer:GetSession().selectedGroupId) or nil
    if not definition then return false end
    self.resourceStyleResourceId = definition.id
    if self.active then self:Refresh(false, false) end
    return self:StartResourceValuePreview(definition.id)
end

function DesignerUI:SelectResourceBar(groupId, resourceId)
    local definition = resourceId and ResourceCatalog
        and ResourceCatalog.GetDefinition
        and ResourceCatalog:GetDefinition(resourceId, Designer:GetProfile(), Designer:GetSession().selectedGroupId) or nil
    local profile = Designer:GetProfile()
    local configuredGroup = profile and profile.groups and profile.groups.items
        and profile.groups.items[groupId]
    if not definition or not configuredGroup
        or configuredGroup.layout ~= "resource" then
        return false
    end

    self:CancelMonitorIdentityEdit(true)
    self:HideMonitorPicker()
    self:HideGlowEditor()
    local group = Designer:SelectGroup(groupId)
    if not group then return false end

    self.propertyPage = "appearance"
    self.inspectorSection = "group"
    self.iconSettingsPage = "layout"
    self.monitorPage = 1
    HideMonitorEffectsPage(self)
    I.HideMonitorSoundPage(self)
    self.monitorEffectsEditing = false
    self.monitorSoundEditing = false
    self.textEditorTarget = nil
    local classFile, specID, formKey = Designer:GetResourcePreviewContext()
    self.resourceStyleSession = Designer:GetSession()
    self.resourceStyleContextKey = BuildResourceStyleContextKey(
        classFile,
        specID,
        formKey,
        Designer:GetSession().selectedGroupId
    )
    self.resourceStyleResourceId = definition.id
    self.manualPanel = false
    if self.panel then self.panel:Show() end
    local refreshed = self:Refresh(true, false)
    if refreshed then self:StartResourceValuePreview(definition.id) end
    return refreshed == true
end

function DesignerUI:SetPropertyPage(page)
    if page ~= "common" and page ~= "layout" and page ~= "appearance"
        and page ~= "text" and page ~= "monitor" then
        page = "common"
    end
    local previousPage = self.propertyPage
    if self.visibilityRuleEditor and self.visibilityRuleEditor.ClosePanel then
        self.visibilityRuleEditor:ClosePanel()
    end
    local _, _, group = SelectedContext()
    local resourceStylePage = group and group.layout == "resource"
        and (page == "text" or page == "appearance")
    local previousResourceStylePage = group and group.layout == "resource"
        and (previousPage == "text" or previousPage == "appearance" or previousPage == "layout")
    if not resourceStylePage then
        self:StopResourceValuePreview(true, self.active == true)
    end

    self.propertyPage = page
    self.inspectorSection = page == "monitor" and "monitor" or "group"
    self.iconSettingsPage = page == "text" and "text" or "layout"
    if self.propertyTabs and self.propertyTabs.SetValue then
        self.propertyTabs:SetValue(page, true)
    end
    self:SyncDesignCooldownTextPreview(
        page == "text" and "all" or nil
    )
    if self.active then self:Refresh(false, false) end
    if resourceStylePage and self.resourceStyleResourceId then
        self:StartResourceValuePreview(self.resourceStyleResourceId)
    end
end

function DesignerUI:ShowIconSettingsPage(page, enabled)
    if self.v2Refreshing then
        self.iconSettingsPage = page == "text" and "text" or "layout"
        return true
    end
    self:SetPropertyPage(page == "text" and "text" or "layout")
end

local function ResolveMonitorIdentityPreview(descriptor, value)
    value = tonumber(value)
    if not descriptor or not value or value <= 0 or value % 1 ~= 0 then
        return nil, nil
    end
    if descriptor.kind == "item" then
        local itemAPI = YUI.API and YUI.API.Item
        local info = itemAPI and itemAPI.GetInfo and itemAPI.GetInfo(value)
        local name = info and info.name
            or (itemAPI and itemAPI.GetName and itemAPI.GetName(value))
        local icon = info and info.texture
            or (itemAPI and itemAPI.GetIcon and itemAPI.GetIcon(value))
        return name, icon
    end
    local spellAPI = YUI.API and YUI.API.Spell
    local info = spellAPI and spellAPI.GetInfo and spellAPI.GetInfo(value)
    local name = info and info.name
        or (spellAPI and spellAPI.GetName and spellAPI.GetName(value))
    local icon = info and (info.iconID or info.originalIconID)
        or (spellAPI and spellAPI.GetTexture and spellAPI.GetTexture(value))
    return name, icon
end

function DesignerUI:BeginMonitorIdentityEdit()
    local descriptor = Designer:GetEditableMonitorIdentity()
    if not descriptor then return end
    self.monitorIdentityEditing = true
    self.monitorIdentityDescriptor = descriptor
    local input = self.monitorBrowser and self.monitorBrowser.identityInput
    if input then
        input:SetText(tostring(descriptor.value or ""))
        if input.SetFocus then input:SetFocus() end
        if input.HighlightText then input:HighlightText() end
    end
    local durationInput = self.monitorBrowser
        and self.monitorBrowser.identityDurationInput
    if durationInput then
        durationInput:SetText(descriptor.durationSeconds
            and tostring(descriptor.durationSeconds) or "")
    end
    self:RefreshMonitorBrowser()
end

function DesignerUI:PreviewMonitorIdentityEdit(value)
    if not self.monitorIdentityEditing then return end
    local browser = self.monitorBrowser
    local descriptor = self.monitorIdentityDescriptor
    local name, icon = ResolveMonitorIdentityPreview(descriptor, value)
    browser.identityTitle:SetText(
        name or T("designer.monitor.identity_not_found", "未找到对应内容")
    )
    SetIntrinsicTextWidth(browser.identityTitle, 150, 150)
    browser.identityIcon:SetIcon(icon or QUESTION_ICON)
end

function DesignerUI:CancelMonitorIdentityEdit(skipRefresh)
    self.monitorIdentityEditing = false
    self.monitorIdentityDescriptor = nil
    local input = self.monitorBrowser and self.monitorBrowser.identityInput
    if input and input.ClearFocus then input:ClearFocus() end
    local durationInput = self.monitorBrowser
        and self.monitorBrowser.identityDurationInput
    if durationInput and durationInput.ClearFocus then
        durationInput:ClearFocus()
    end
    if not skipRefresh then self:RefreshMonitorBrowser() end
end

function DesignerUI:ConfirmMonitorIdentityEdit()
    if not self.monitorIdentityEditing then return end
    local input = self.monitorBrowser and self.monitorBrowser.identityInput
    local durationInput = self.monitorBrowser
        and self.monitorBrowser.identityDurationInput
    local result, code = Designer:ReplaceMonitorIdentity(
        nil,
        input and input:GetText() or nil,
        durationInput and durationInput:GetText() or nil
    )
    if not result then
        if code == "claim-projection-unavailable" then
            self:SetMutationError(
                code,
                "designer.error_monitor_identity_update",
                "无法修改监控 ID。"
            )
            return nil, code
        end
        local messages = {
            ["invalid-monitor-id"] = T(
                "designer.error_monitor_identity_invalid",
                "请输入有效的监控 ID。"
            ),
            ["monitor-identity-readonly"] = T(
                "designer.error_monitor_identity_readonly",
                "该监控不能修改 ID。"
            ),
            ["monitor-identity-conflict"] = T(
                "designer.error_monitor_identity_conflict",
                "该监控已存在。"
            ),
            ["official-aura-not-found"] = T(
                "designer.error_monitor_identity_not_found",
                "未在当前光环目录中找到该监控。"
            ),
            ["invalid-buff-duration"] = T(
                "designer.error_monitor_duration_invalid",
                "请输入 0.1–3600 秒之间的持续时间。"
            ),
        }
        self:SetStatus(messages[code] or T(
            "designer.error_monitor_identity_update",
            "无法修改监控 ID。"
        ))
        return
    end
    self:CancelMonitorIdentityEdit(true)
    self:SetStatus(T(
        "designer.status_monitor_identity_updated",
        "监控 ID 已更新。"
    ))
    self:ApplyPreview()
    self:RefreshMonitorPicker()
    self:Refresh(false, false)
end

function DesignerUI:IsMonitorListEntryHidden(profile, entry)
    if YUI.IsForever == true and entry and entry.sourceType == "yhud.ammo-count" then
        return false
    end
    local availability = entry and YHUD:EvaluateEntryAvailability(
        entry,
        rawget(profile, "_yhudSpecKey")
    ) or "available"
    return availability == "ineligible"
end

function DesignerUI:RefreshMonitorBrowser()
    local browser = self.monitorBrowser
    if not browser then return end
    local session, profile, group, monitor = SelectedContext()
    local claimedSources = MonitorCatalog
        and MonitorCatalog.GetClaimedCooldownSources
        and MonitorCatalog:GetClaimedCooldownSources(profile) or {}
    local function IsBrowserMonitorVisible(candidate, entry)
        return candidate ~= nil
            and YHUD:IsOfficialEntryRenderable(entry)
            and not self:IsMonitorListEntryHidden(profile, entry)
            and not YHUD:IsOfficialEntryClaimed(
                entry,
                claimedSources,
                candidate.id
            )
    end
    local rawIds = group and group.monitors or {}
    local ids = {}
    for index = 1, #rawIds do
        local monitorId = rawIds[index]
        local candidate = profile and profile.monitors[monitorId]
        local entry = candidate and profile.entries[candidate.entryKey]
        if IsBrowserMonitorVisible(candidate, entry) then
            ids[#ids + 1] = monitorId
        end
    end
    local browserMonitor = monitor
    local browserEntry = browserMonitor
        and profile.entries[browserMonitor.entryKey]
    if browserMonitor
        and not IsBrowserMonitorVisible(browserMonitor, browserEntry) then
        browserMonitor = nil
    end
    local pageCount = math.max(1, math.ceil(#ids / PAGE_SIZE))
    local selectedIndex
    for index = 1, #ids do
        if ids[index] == (browserMonitor and browserMonitor.id) then
            selectedIndex = index
            break
        end
    end
    local selectedMonitorId = browserMonitor and browserMonitor.id or nil
    if selectedIndex and (browser.selectedMonitorId ~= selectedMonitorId
        or self.monitorFollowSelection == true) then
        self.monitorPage = math.ceil(selectedIndex / PAGE_SIZE)
    end
    browser.selectedMonitorId = selectedMonitorId
    self.monitorPage = math.max(1, math.min(pageCount, self.monitorPage or 1))
    local startIndex = ((self.monitorPage - 1) * PAGE_SIZE) + 1
    local appearance = group and (
        group.layout == "icons"
            and YHUD:GetIconGroupStyle(profile, group.id)
            or YHUD:GetDurationGroupStyle(profile, group.id)
    ) or nil

    local monitorSummary = Designer:GetGroupMonitorSummary(group and group.id)
    local previewState = Designer:GetNativePreviewState()
    local showMissingCache = previewState
        and previewState.staticPreview == true
        and previewState.cacheAvailable ~= true
    SetShown(browser.nativePreviewStatus, showMissingCache)
    browser:ClearAllPoints()
    browser:SetPoint(
        "TOPLEFT",
        self.monitorInspectorBody,
        "TOPLEFT",
        0,
        showMissingCache and -66 or -44
    )
    browser.previewStatusOffset = showMissingCache and 22 or 0

    for slot = 1, PAGE_SIZE do
        local button = browser.buttons[slot]
        local orderIndex = startIndex + slot - 1
        local monitorId = ids[orderIndex]
        local candidate = monitorId and profile.monitors[monitorId]
        local entry = candidate and profile.entries[candidate.entryKey]
        button.monitorId = monitorId
        if candidate then
            button:SetIcon(EntryIcon(entry))
            if appearance and button.SetIconAppearance then
                button:SetIconAppearance({
                    size = MONITOR_ICON_SIZE,
                    shape = "square",
                    border = "thin",
                    zoom = appearance.iconZoom,
                })
            end
            button:Show()
            button:SetSelected(candidate == browserMonitor)
            local availability = entry
                and YHUD:EvaluateEntryAvailability(
                    entry,
                    rawget(profile, "_yhudSpecKey")
                ) or "available"
            local unavailable = availability == "unavailable"
                or availability == "ineligible"
            if button.icon and button.icon.SetDesaturated then
                button.icon:SetDesaturated(unavailable)
            end
            if button.icon and button.icon.SetAlpha then
                button.icon:SetAlpha(unavailable and 0.45 or 1)
            end
            button.yhudEntry = entry
            button.yhudMonitorName = MonitorName(profile, candidate)
            button.yhudAvailability = availability
            button.yhudCacheOnlyPreview =
                candidate._yhudCacheOnlyPreview == true
            button.yhudSpecialMonitor =
                YHUD:IsFilteredAuraLayoutMonitor(entry, candidate, true) == true
            ApplyMonitorWarningBadge(button.sourceBadge, entry, availability)
            local bundleKind = entry and entry.bundleKind
            if not bundleKind and entry
                and entry.sourceType == "racial-bundle" then
                bundleKind = "racial"
            end
            local shortLabel = YHUD.ClassExtra and YHUD.ClassExtra:SettingsLabel(entry)
                or YHUD.GetEntryPresetLabel
                    and YHUD:GetEntryPresetLabel(entry)
                or bundleKind == "defensive"
                    and T("designer.bundle.short.defensive", "防御")
                or bundleKind == "externalBuff"
                    and T("designer.bundle.short.external_buffs", "外部增益")
                or bundleKind == "interruptControl"
                    and T("designer.bundle.short.interrupt_control", "断控")
                or bundleKind == "racial"
                    and T("designer.bundle.short.racial", "种族")
                or bundleKind == (YHUD.EQUIPMENT_AURA_BUNDLE_KIND
                    or "equipmentAura")
                    and T("designer.bundle.short.trinket", "饰品")
                or BloodlustBadgeText(entry)
                or button.yhudSpecialMonitor
                    and T("designer.monitor.special_badge", "特殊")
            local showShortLabel = type(shortLabel) == "string"
                and shortLabel ~= ""
            if button.bundleLabel then
                button.bundleLabel:SetText(shortLabel or "")
                SetShown(button.bundleLabel, showShortLabel)
            end
            if button.bundleLabelBackdrop then
                SetShown(button.bundleLabelBackdrop, showShortLabel)
            end
        else
            button.yhudEntry = nil
            button.yhudMonitorName = nil
            button.yhudAvailability = nil
            button.yhudCacheOnlyPreview = nil
            button.yhudSpecialMonitor = nil
            ApplyMonitorWarningBadge(button.sourceBadge, nil, nil)
            if button.bundleLabel then button.bundleLabel:Hide() end
            if button.bundleLabelBackdrop then
                button.bundleLabelBackdrop:Hide()
            end
            button:Hide()
        end
    end

    local hasMonitors = #ids > 0
    local hasPages = #ids > PAGE_SIZE
    SetShown(browser.emptyState, not hasMonitors)
    SetShown(browser.listPanel, hasMonitors)
    SetShown(browser.detailPanel, hasMonitors and browserMonitor ~= nil)
    SetShown(browser.previous, hasPages)
    SetShown(browser.pageText, hasPages)
    SetShown(browser.next, hasPages)
    SetShown(browser.identityIcon, hasMonitors and browserMonitor ~= nil)
    SetShown(browser.identityTitle, hasMonitors and browserMonitor ~= nil)
    SetShown(browser.identityType, hasMonitors and browserMonitor ~= nil)
    SetShown(browser.summary, true)
    browser.summary:SetText(string.format(
        T(
            "designer.monitor.summary_multispec.short",
            "本专精 %d/%d · 其他 %d"
        ),
        monitorSummary and monitorSummary.currentAvailable or 0,
        monitorSummary and monitorSummary.currentTotal or #ids,
        monitorSummary and monitorSummary.otherTotal or 0
    ))
    browser.pageText:SetText(self.monitorPage .. " / " .. pageCount)
    browser.previous:SetDisabled(self.monitorPage <= 1)
    browser.next:SetDisabled(self.monitorPage >= pageCount)
    if browserMonitor then
        local entry = profile.entries[browserMonitor.entryKey]
        local officialCDM = entry and entry.origin == "official-cdm"
        local availability = entry
            and YHUD:EvaluateEntryAvailability(
                entry,
                rawget(profile, "_yhudSpecKey")
            ) or "available"
        browser.identityIcon:SetIcon(EntryIcon(entry))
        browser.identityIcon.yhudEntry = entry
        if appearance and browser.identityIcon.SetIconAppearance then
            browser.identityIcon:SetIconAppearance({
                size = MONITOR_IDENTITY_ICON_SIZE,
                shape = "square",
                border = "thin",
                zoom = appearance.iconZoom,
            })
        end
        SetMonitorTypeText(browser.identityType, entry)
        local descriptor = Designer:GetEditableMonitorIdentity(
            browserMonitor.id
        )
        local editing = self.monitorIdentityEditing == true
            and self.monitorIdentityDescriptor ~= nil
        local sourceText, sourceR, sourceG, sourceB, sourceA =
            MonitorSourceText(entry)
        browser.identityOrigin:SetText(sourceText)
        local specialMonitor = YHUD:IsFilteredAuraLayoutMonitor(
            entry,
            browserMonitor,
            true
        ) == true
        local fixedSourceColor = entry.origin == "official-cdm"
            or entry.origin == "preset"
            or entry.presetKey ~= nil
        if fixedSourceColor and browser.identityOrigin.SetTextColor then
            browser.identityOrigin.gui2ColorKey = nil
            browser.identityOrigin:SetTextColor(
                sourceR,
                sourceG,
                sourceB,
                sourceA
            )
        elseif not fixedSourceColor then
            GUI2:SetTextColorKey(
                browser.identityOrigin,
                "color.text.primary"
            )
        end
        SetIntrinsicTextWidth(browser.identityType, 72, 44)
        SetIntrinsicTextWidth(browser.identityOrigin, 76, 44)
        local exceptional = HasMonitorDetailStatus(entry, availability)
        browser.identityWarning:SetText(
            exceptional and MonitorStatusText(entry, availability) or ""
        )
        GUI2:SetTextColorKey(
            browser.identityWarning,
            (availability == "unavailable"
                or availability == "ineligible"
                or entry.conflict ~= nil)
                and "color.state.danger" or "color.state.warning"
        )
        SetShown(browser.identityOrigin, not editing)
        SetShown(browser.identitySpecial, specialMonitor and not editing)
        SetShown(
            browser.identityPreviewNotice,
            not editing
                and browserMonitor._yhudCacheOnlyPreview == true
                and entry.origin == "official-cdm"
        )
        SetShown(browser.identityWarning, exceptional and not editing)
        SetShown(browser.identityType, not editing)
        SetShown(browser.identityIdLabel, not editing)
        SetShown(browser.identityDetail, not editing)
        SetShown(
            browser.identityEdit,
            not editing and not officialCDM and descriptor ~= nil
        )
        SetShown(browser.identityInput, editing)
        SetShown(browser.identityConfirm, editing)
        SetShown(browser.identityCancel, editing)
        local editingDuration = editing
            and self.monitorIdentityDescriptor.durationSeconds ~= nil
        SetShown(browser.identityDurationLabel, editingDuration)
        SetShown(browser.identityDurationInput, editingDuration)
        if not editing then
            browser.identityTitle:SetText(MonitorName(profile, browserMonitor))
            SetIntrinsicTextWidth(
                browser.identityTitle,
                150,
                150
            )
            browser.identityDetail:SetText(EntryIdentity(entry))
            SetIntrinsicTextWidth(browser.identityDetail, 116, 82)
            browser.identityEdit:ClearAllPoints()
            browser.identityEdit:SetPoint(
                "LEFT",
                browser.identityDetail,
                "RIGHT",
                6,
                0
            )
        end
    else
        SetShown(browser.identityOrigin, false)
        SetShown(browser.identitySpecial, false)
        SetShown(browser.identityPreviewNotice, false)
        SetShown(browser.identityWarning, false)
        SetShown(browser.identityIdLabel, false)
        SetShown(browser.identityDetail, false)
        SetShown(browser.identityEdit, false)
        SetShown(browser.identityInput, false)
        SetShown(browser.identityConfirm, false)
        SetShown(browser.identityCancel, false)
        SetShown(browser.identityDurationLabel, false)
        SetShown(browser.identityDurationInput, false)
    end
end

local function HideAllPageControls(self)
    for _, page in pairs(self.playerCastPages or {}) do HideControls(page.controls) end
    HideControls(self.monitorStackThresholdControls)
    HideControls(self.monitorBarProgressControls)
    HideControls(self.barWidthControls)
    if self.visibilityRuleEditor and self.visibilityRuleEditor.ClosePanel then
        self.visibilityRuleEditor:ClosePanel()
    end
    HideV2PageRoots(self)
    local seen = {}
    HideControls(self.groupSectionControls, seen)
    HideControls(self.resourceLayoutControls, seen)
    HideControls(self.monitorSectionControls, seen)
    HideControls(self.visibilityPageControls, seen)
    for _, slider in pairs(self.v2Sliders or {}) do slider:Hide() end
    for _, row in pairs(self.textRows or {}) do row:Hide() end
    for _, row in pairs(self.resourceTextRows or {}) do row:Hide() end
    for _, row in pairs(self.keybindOverrideRows or {}) do row:Hide() end
    HideControls(self.keybindTextControls, seen)
    HideControls(self.resourceV2Controls, seen)
    if self.resourceTextSettingsButton then
        self.resourceTextSettingsButton:Hide()
    end
    if self.textEditorTitle then self.textEditorTitle:Hide() end
    if self.textEditorBack then self.textEditorBack:Hide() end
    if self.cooldownBlingLabel then self.cooldownBlingLabel:Hide() end
    if self.cooldownBlingSwitch then self.cooldownBlingSwitch:Hide() end
    if self.cooldownSwipeLabel then self.cooldownSwipeLabel:Hide() end
    if self.cooldownSwipeSwitch then self.cooldownSwipeSwitch:Hide() end
    if self.chargeRecoveryControl then self.chargeRecoveryControl:Hide() end
    if self.cooldownGCDLabel then self.cooldownGCDLabel:Hide() end
    if self.cooldownGCDSwitch then self.cooldownGCDSwitch:Hide() end
    if self.pandemicGlowDivider then self.pandemicGlowDivider:Hide() end
    if self.pandemicGlowLabel then self.pandemicGlowLabel:Hide() end
    if self.pandemicGlowSwitch then self.pandemicGlowSwitch:Hide() end
    if self.commonMaintenance then self.commonMaintenance:Hide() end
    if self.tooltipLabel then self.tooltipLabel:Hide() end
    if self.tooltipSwitch then self.tooltipSwitch:Hide() end
    if self.racialEditor then self.racialEditor:Hide() end
    HideMonitorEffectsPage(self)
    I.HideMonitorSoundPage(self)
    for _, control in ipairs({
        self.monitorEffectsButton,
        self.monitorSoundButton,
        self.monitorReplicationButton,
        self.monitorAppearanceDivider,
        self.monitorAppearanceFillLabel,
        self.monitorAppearanceFill,
        self.monitorAppearanceTrackLabel,
        self.monitorAppearanceTrack,
        self.monitorResetAppearance,
    }) do
        if control then control:Hide() end
    end
    if self.monitorBrowser then
        self.monitorBrowser:Hide()
        if self.monitorBrowser.summary then
            self.monitorBrowser.summary:Hide()
        end
        if self.monitorBrowser.nativePreviewStatus then
            self.monitorBrowser.nativePreviewStatus:Hide()
        end
    end
    self.groupInspectorBody:Hide()
    self.monitorInspectorBody:Hide()
    if self.iconSettingsMode then
        self.iconSettingsMode:Hide()
    end
end

local function PlaceAddActions(self, body, group)
    if group.layout == "resource" then return 1 end
    local capabilities = YHUD:GetGroupAddCapabilities(group)
    local contentBottom = math.max(0, tonumber(self.monitorContentBottom) or 0)
    local viewportHeight = self.inspectorScroll
        and self.inspectorScroll.GetHeight
        and self.inspectorScroll:GetHeight() or 0
    if viewportHeight <= 1 and self.panel and self.panel.GetHeight then
        viewportHeight = math.max(1, self.panel:GetHeight() - 162)
    end
    local actionTop
    if contentBottom + MONITOR_ACTION_GAP + MONITOR_ACTION_HEIGHT
        <= viewportHeight then
        actionTop = viewportHeight - MONITOR_ACTION_HEIGHT
    else
        actionTop = contentBottom + MONITOR_ACTION_GAP
    end
    if capabilities and capabilities.cooldown then
        if self.addMonitorButton.SetParent then
            self.addMonitorButton:SetParent(body)
        end
        self.addMonitorButton:Show()
        self.addMonitorButton:ClearAllPoints()
        self.addMonitorButton:SetPoint(
            "TOPLEFT",
            body,
            "TOPLEFT",
            0,
            -actionTop
        )
        self.addMonitorButton:SetWidth(
            capabilities.buff and COLUMN_WIDTH or CONTENT_WIDTH
        )
    end
    if capabilities and capabilities.buff then
        if self.addBuffButton.SetParent then
            self.addBuffButton:SetParent(body)
        end
        self.addBuffButton:Show()
        self.addBuffButton:ClearAllPoints()
        self.addBuffButton:SetPoint(
            "TOPRIGHT",
            body,
            "TOPRIGHT",
            0,
            -actionTop
        )
        self.addBuffButton:SetWidth(
            capabilities.cooldown and COLUMN_WIDTH or CONTENT_WIDTH
        )
    end
    return math.max(
        viewportHeight,
        actionTop + MONITOR_ACTION_HEIGHT
    )
end

local function RefreshResourceCommonData(self, profile, group)
    if not (group.layout == "resource" and ResourceCatalog) then return 0 end
    local classFile, specID, formKey = Designer:GetResourcePreviewContext()
    local presets = formKey and ResourceCatalog:GetFormPresets(
        YHUD:GetResourceProfile(profile, group.id),
        classFile,
        specID,
        formKey
    ) or ResourceCatalog:GetPresets(YHUD:GetResourceProfile(profile, group.id), classFile, specID)
    presets = ProjectResourceDisplayOrder(profile, group.id, presets)
    self.resourceClassDropdown:SetValue(classFile, true)
    self.resourceSpecDropdown:SetValue(specID, true)
    self.resourceFormVisible = formKey ~= nil
    if formKey then
        self.resourceFormDropdown:SetValue(formKey, true)
        local customized = ResourceCatalog:IsFormCustomized(
            YHUD:GetResourceProfile(profile, group.id),
            classFile,
            specID,
            formKey
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
    local enabledCount = 0
    local resourceUsage = Designer:GetResourcePresetUsage()
    self:EnsureResourcePresetRows(#presets)
    for index = 1, #self.resourcePresetRows do
        local row = self.resourcePresetRows[index]
        local preset = presets and presets[index]
        if preset then
            row.resourceId = preset.id
            row.label:SetText(T(preset.nameKey, preset.id))
            local effectiveStyle = YHUD:GetEffectiveResourceStyle(
                profile,
                group.id,
                preset.styleResourceId or preset.id,
                specID
            )
            local color = effectiveStyle.fillColor or preset.color
            row.swatch:SetColorTexture(
                color.r or color[1] or 1,
                color.g or color[2] or 1,
                color.b or color[3] or 1,
                color.a == nil and (color[4] == nil and 1 or color[4])
                    or color.a
            )
            row.toggle:SetValue(preset.enabled == true, true)
            I.RefreshResourceSharingRow(row, preset, resourceUsage, CONTENT_WIDTH)
            row.moveUp:SetDisabled(index == 1)
            row.moveDown:SetDisabled(index == #presets)
            if preset.enabled then enabledCount = enabledCount + 1 end
        else
            row.resourceId = nil
            row:Hide()
        end
    end
    return enabledCount
end

function I.RefreshResourceMonitorPage(self, profile, group)
    local body = self.groupInspectorBody
    body:Show()
    if group.contentPolicy == "cast-only" then
        HideControls(self.resourceBaseControls)
        HideControls(self.resourcePresetRows)
        SetShown(self.resourceEmptyGroupHint, false)
        local bottom = I.RefreshPlayerCastOptions(self, profile, group, "monitor", -4)
        SetV2InspectorScrollContentHeight(self, -bottom + 24)
        return
    end
    local contentBottom
    RefreshResourceCommonData(self, profile, group)
    ShowControls(self.resourceBaseControls)
    Place(self.resourceBaseControls[1], body, 0, -0)
    Place(self.resourceBaseControls[2], body, SECOND_COLUMN_X, -0)
    Place(self.resourceBaseControls[3], body, 0, -20, COLUMN_WIDTH)
    Place(self.resourceBaseControls[4], body, SECOND_COLUMN_X, -20, COLUMN_WIDTH)
    local y
    if self.resourceFormVisible then
        SetShown(self.resourceBaseControls[5], true)
        SetShown(self.resourceBaseControls[6], true)
        SetShown(self.resourceBaseControls[7], true)
        SetShown(self.resourceBaseControls[8], true)
        SetShown(self.resourceBaseControls[9], true)
        Place(self.resourceBaseControls[5], body, 0, -68)
        Place(self.resourceBaseControls[6], body, 0, -88, CONTENT_WIDTH)
        Place(self.resourceBaseControls[7], body, 0, -136, COLUMN_WIDTH)
        Place(
            self.resourceBaseControls[8],
            body,
            CONTENT_WIDTH - 96,
            -130,
            96
        )
        Place(self.resourceBaseControls[9], body, 0, -164, CONTENT_WIDTH)
        Place(self.resourceBaseControls[10], body, 0, -202)
        y = -224
    else
        for index = 5, 9 do
            SetShown(self.resourceBaseControls[index], false)
        end
        Place(self.resourceBaseControls[10], body, 0, -68)
        y = -90
    end
    for index = 1, #(self.resourcePresetRows or {}) do
        local row = self.resourcePresetRows[index]
        if row.resourceId then
            if row.toggle and row.toggle.SetWidth then
                row.toggle:SetWidth(RESOURCE_COMMON_SWITCH_WIDTH)
            end
            Place(row, body, 0, y, CONTENT_WIDTH)
            row:Show()
            y = y - 36
        end
    end
    contentBottom = -y
    local emptyDefault = YHUD:GetResourceConfig(profile, group.id).selectionDefault == "none"
    if emptyDefault and not self.resourceEmptyGroupHint then
        self.resourceEmptyGroupHint = GUI2:CreateText(EnsureV2PageRoots(self).resourceMonitor,
            T("designer.resource.empty_group_hint", "新建资源组：所有专精的资源默认关闭。"),
            "font.size.sm", "color.text.secondary", "LEFT")
    end
    SetShown(self.resourceEmptyGroupHint, emptyDefault)
    if emptyDefault then Place(self.resourceEmptyGroupHint, body, 0, -contentBottom - 8, CONTENT_WIDTH) end
    SetV2InspectorScrollContentHeight(self, contentBottom + (emptyDefault and 56 or 24))
end

local function RefreshCommonPage(self, group)
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local body = self.groupInspectorBody
    body:Show()
    SetShown(self.groupNameLabel, true)
    SetShown(self.groupNameInput, true)
    SetShown(self.fixedNameBadge, group.fixedName == true)
    SetShown(self.enableLabel, true)
    SetShown(self.enableSwitch, true)
    SetShown(self.unavailablePreviewLabel, group.layout ~= "resource")
    SetShown(self.unavailablePreviewSwitch, group.layout ~= "resource")
    SetShown(self.tooltipLabel, group.layout ~= "resource")
    SetShown(self.tooltipSwitch, group.layout ~= "resource")
    self.tooltipSwitch:SetValue(group.showTooltip ~= false, true)
    SetShown(self.visibilityRuleLabel, true)
    SetShown(self.visibilityRuleEditor, true)
    self.visibilityRuleEditor:SetContext(group.id)
    self.visibilityRuleEditor:SetValue(group.visibility, true)
    self.visibilityRuleEditor:RefreshCapabilities()

    local enableWidth = group.layout == "resource"
        and RESOURCE_COMMON_SWITCH_WIDTH or 48
    local enableX = CONTENT_WIDTH - enableWidth - 10
    if self.enableSwitch.SetWidth then self.enableSwitch:SetWidth(enableWidth) end

    Place(self.groupNameLabel, body, 0, -4)
    Place(self.groupNameInput, body, 0, -24, CONTENT_WIDTH)
    Place(self.enableLabel, body, 0, -76, enableX - 12)
    if self.enableLabel.SetWordWrap then self.enableLabel:SetWordWrap(false) end
    Place(
        self.enableSwitch,
        body,
        enableX,
        -72
    )
    Place(self.unavailablePreviewLabel, body, 0, -122, SWITCH_X - 12)
    if self.unavailablePreviewLabel.SetWordWrap then
        self.unavailablePreviewLabel:SetWordWrap(false)
    end
    Place(self.unavailablePreviewSwitch, body, SWITCH_X, -118)
    Place(self.tooltipLabel, body, 0, -166, SWITCH_X - 12)
    if self.tooltipLabel.SetWordWrap then self.tooltipLabel:SetWordWrap(false) end
    Place(self.tooltipSwitch, body, SWITCH_X, -162)

    local visibilityTop = group.layout == "resource" and 122 or 210
    local contentBottom = visibilityTop + self.visibilityRuleEditor:GetHeight()

    Place(self.visibilityRuleLabel, body, 0, -visibilityTop, CONTENT_WIDTH)
    Place(self.visibilityRuleEditor, body, 0, -visibilityTop - 32, CONTENT_WIDTH)
    contentBottom = visibilityTop + 32 + self.visibilityRuleEditor:GetHeight()
    SetV2InspectorScrollContentHeight(
        self,
        contentBottom + 70
    )

    local canRestore = session
        and YHUD.DEFAULT_CATEGORY_BY_GROUP[session.selectedGroupId] ~= nil
    local canDelete = group.fixedDelete ~= true
    SetShown(self.restoreButton, canRestore)
    SetShown(self.deleteGroupButton, canDelete)
    SetShown(self.commonMaintenance, canRestore or canDelete)
    if canRestore or canDelete then
        if self.commonMaintenance.SetParent then
            self.commonMaintenance:SetParent(
                self.v2PageRoots and self.v2PageRoots.common or body
            )
        end
        self.commonMaintenance:ClearAllPoints()
        self.commonMaintenance:SetPoint(
            "BOTTOMLEFT",
            body,
            "BOTTOMLEFT",
            0,
            0
        )
        self.commonMaintenance:SetWidth(CONTENT_WIDTH)
        self.commonMaintenance:Show()
    end
    if canRestore then
        self.restoreButton:ClearAllPoints()
        if canDelete then
            self.restoreButton:SetPoint(
                "RIGHT", self.deleteGroupButton, "LEFT", -8, 0
            )
            self.restoreButton:SetWidth(104)
        else
            self.restoreButton:SetPoint(
                "RIGHT", self.commonMaintenance, "RIGHT", -8, 0
            )
            self.restoreButton:SetWidth(150)
        end
    end
    if canDelete then
        self.deleteGroupButton:Show()
        self.deleteGroupButton:ClearAllPoints()
        self.deleteGroupButton:SetPoint("RIGHT", self.commonMaintenance, "RIGHT", -8, 0)
        self.deleteGroupButton:SetWidth(136)
    end
    if canRestore or canDelete then
        local firstAction = canRestore and self.restoreButton or self.deleteGroupButton
        self.commonMaintenanceLabel:ClearAllPoints()
        self.commonMaintenanceLabel:SetPoint("LEFT", self.commonMaintenance, "LEFT", 14, 0)
        self.commonMaintenanceLabel:SetPoint("RIGHT", firstAction, "LEFT", -8, 0)
    end
end

function I.EnsureHandLayoutControls(self)
    if YUI.IsForever ~= true or self.resourceHandControls then return end
    local parent = EnsureV2PageRoots(self).layout
    local controls = {}
    local function Field(field, key, fallback, options)
        local label = GUI2:CreateText(parent, T(key, fallback), "font.size.sm", "color.text.secondary", "LEFT")
        local dropdown = GUI2.Form:CreateDropdown(parent, {
            width = CONTENT_WIDTH, height = 30, options = options,
            set = function(value)
                if DesignerUI.v2Refreshing then return end
                DesignerUI:ApplyV2SliderPatch("resourceLayout", field, value)
                DesignerUI:Refresh(false, false)
            end,
        })
        controls[#controls + 1], controls[#controls + 2] = label, dropdown
        self.resourceLayoutControls[#self.resourceLayoutControls + 1] = label
        self.resourceLayoutControls[#self.resourceLayoutControls + 1] = dropdown
        return dropdown
    end
    local function IsVertical()
        local profile, session = Designer:GetProfile(), Designer:GetSession()
        return profile and session
            and YHUD:GetResourceGroupLayout(profile, session.selectedGroupId).orientation == "vertical"
    end
    self.resourceHandPairDropdown = Field("handPairMode", "designer.resource.hand_layout", "主副手排列", function()
        local vertical = IsVertical()
        return {
            { value = "stacked", text = vertical and T("designer.resource.hand_separate", "两条独立") or T("designer.resource.hand_stacked", "上下两条") },
            { value = "split", text = vertical and T("designer.resource.hand_split_vertical", "单列上下各半") or T("designer.resource.hand_split", "单行左右各半") },
        }
    end)
    local function directions()
        local vertical = IsVertical()
        return {
            { value = "forward", text = vertical and T("designer.resource.fill_up", "向上增长 ↑") or T("designer.resource.fill_right", "向右增长 →") },
            { value = "reverse", text = vertical and T("designer.resource.fill_down", "向下增长 ↓") or T("designer.resource.fill_left", "向左增长 ←") },
        }
    end
    self.resourceMainHandDirection = Field("mainHandFillDirection", "designer.resource.main_hand_direction", "主手进度方向", directions)
    self.resourceOffHandDirection = Field("offHandFillDirection", "designer.resource.off_hand_direction", "副手进度方向", directions)
    self.resourceHandControls = controls
end

local function RefreshLayoutPage(self, profile, group)
    local body = self.groupInspectorBody
    local sliders = self.v2Sliders
    body:Show()
    ShowControls(self.layoutModeControls)
    local effectiveLayoutMode, configuredLayoutMode, overrideReason
    if YHUD.GetEffectiveGroupLayoutMode then
        effectiveLayoutMode, configuredLayoutMode, overrideReason =
            YHUD:GetEffectiveGroupLayoutMode(profile, group, true)
    else
        configuredLayoutMode = group.layoutMode == "fixed" and "fixed" or "auto"
        effectiveLayoutMode = configuredLayoutMode
    end
    local layoutModeForced = overrideReason ~= nil
    self.layoutModeDropdown:SetValue(effectiveLayoutMode, true)
    self.displayLayerDropdown:SetValue(group.displayLayer or 5, true)
    Place(self.layoutModeLabel, body, 0, -8, FIELD_LABEL_WIDTH)
    Place(
        self.layoutModeDropdown,
        body,
        FIELD_LABEL_WIDTH,
        0,
        FIELD_CONTROL_WIDTH
    )
    self.layoutModeDropdown:SetWidth(
        layoutModeForced and FIELD_CONTROL_WIDTH - 34 or FIELD_CONTROL_WIDTH
    )
    SetDisabled(self.layoutModeDropdown, layoutModeForced)
    self.layoutModeOverrideInfo.yhudConfiguredLayoutMode =
        configuredLayoutMode
    self.layoutModeOverrideInfo.yhudLayoutModeOverrideReason =
        overrideReason
    if layoutModeForced then
        self.layoutModeOverrideInfo:ClearAllPoints()
        self.layoutModeOverrideInfo:SetPoint(
            "LEFT", self.layoutModeDropdown, "RIGHT", 8, 0
        )
        self.layoutModeOverrideInfo:Show()
    else
        self.layoutModeOverrideInfo:Hide()
    end
    Place(self.displayLayerLabel, body, 0, -48, FIELD_LABEL_WIDTH)
    Place(
        self.displayLayerDropdown,
        body,
        FIELD_LABEL_WIDTH,
        -40,
        FIELD_CONTROL_WIDTH
    )
    if group.layout == "resource" then
        local layout = YHUD:GetResourceGroupLayout(profile, group.id)
        local vertical = layout.orientation == "vertical"
        sliders.resourceWidth.label:SetText(vertical and T("designer.resource.length", "长度") or T("designer.resource.width", "宽度"))
        sliders.resourceMinWidth.label:SetText(vertical and T("designer.resource.min_length", "最小长度") or T("designer.resource.min_width", "最小宽度"))
        sliders.resourceHeight.label:SetText(vertical and T("designer.resource.thickness", "粗细") or T("designer.resource.height", "高度"))
        self.resourceWidthModeLabel:SetText(vertical and T("designer.resource.length_mode", "长度模式") or T("designer.resource.width_mode", "宽度模式"))
        self.resourceWidthModeDropdown:SetValue(layout.widthMode, true)
        sliders.resourceWidth:SetValue(layout.width, true)
        sliders.resourceMinWidth:SetValue(layout.minWidth, true)
        sliders.resourceHeight:SetValue(layout.height, true)
        sliders.resourceSpacing:SetValue(layout.spacing, true)
        self.resourceDirectionDropdown:SetValue(layout.direction, true)
        self.resourceAlignmentDropdown:SetValue(layout.alignment, true)
        self.resourceOrientationDropdown:SetValue(layout.orientation, true)
        self.resourceFillDirectionDropdown:SetValue(
            layout.fillDirection,
            true
        )
        if group.contentPolicy == "cast-only" then
            HideControls(self.layoutModeControls)
            HideControls(self.resourceLayoutControls)
            HideControls(self.resourceHandControls)
            ShowControls({ self.displayLayerLabel, self.displayLayerDropdown,
                self.resourceWidthModeLabel, self.resourceWidthModeDropdown })
            Place(self.displayLayerLabel, body, 0, -8, FIELD_LABEL_WIDTH)
            Place(self.displayLayerDropdown, body, FIELD_LABEL_WIDTH, 0, FIELD_CONTROL_WIDTH)
            Place(self.resourceWidthModeLabel, body, 0, -48, FIELD_LABEL_WIDTH)
            Place(self.resourceWidthModeDropdown, body, FIELD_LABEL_WIDTH, -40, FIELD_CONTROL_WIDTH)
            local widthSlider = layout.widthMode == "auto" and sliders.resourceMinWidth or sliders.resourceWidth
            sliders.resourceWidth:Hide()
            sliders.resourceMinWidth:Hide()
            sliders.resourceSpacing:Hide()
            Place(widthSlider, body, 0, -82)
            Place(sliders.resourceHeight, body, 0, -122)
            widthSlider:Show()
            sliders.resourceHeight:Show()
            ShowControls({ self.resourceLayoutControls[11], self.resourceLayoutControls[13],
                self.resourceLayoutControls[12], self.resourceLayoutControls[14] })
            PlaceResourceField(self.resourceLayoutControls[11], self.resourceLayoutControls[13], body, 0, -176)
            PlaceResourceField(self.resourceLayoutControls[12], self.resourceLayoutControls[14], body, SECOND_COLUMN_X, -176)
            SetV2InspectorScrollContentHeight(self, 252)
            return
        end
        I.EnsureHandLayoutControls(self)
        Place(self.resourceWidthModeLabel, body, 0, -88, FIELD_LABEL_WIDTH)
        Place(
            self.resourceWidthModeDropdown,
            body,
            FIELD_LABEL_WIDTH,
            -80,
            FIELD_CONTROL_WIDTH
        )
        local widthSlider = layout.widthMode == "auto"
            and sliders.resourceMinWidth or sliders.resourceWidth
        Place(widthSlider, body, 0, -122)
        Place(sliders.resourceHeight, body, 0, -162)
        Place(sliders.resourceSpacing, body, 0, -202)
        sliders.resourceWidth:Hide()
        sliders.resourceMinWidth:Hide()
        widthSlider:Show()
        sliders.resourceHeight:Show()
        sliders.resourceSpacing:Show()
        ShowControls(self.resourceLayoutControls)
        for index = 1, 6 do self.resourceLayoutControls[index]:Hide() end
        Place(self.resourceLayoutControls[7], body, 0, -256)
        Place(self.resourceLayoutControls[8], body, SECOND_COLUMN_X, -256)
        Place(self.resourceLayoutControls[9], body, 0, -276, COLUMN_WIDTH)
        Place(self.resourceLayoutControls[10], body, SECOND_COLUMN_X, -276, COLUMN_WIDTH)
        PlaceResourceField(self.resourceLayoutControls[11], self.resourceLayoutControls[13], body, 0, -328)
        PlaceResourceField(self.resourceLayoutControls[12], self.resourceLayoutControls[14], body, SECOND_COLUMN_X, -328)
        if self.resourceHandControls then
            self.resourceHandPairDropdown:SetValue(layout.handPairMode, true)
            self.resourceMainHandDirection:SetValue(layout.mainHandFillDirection, true)
            self.resourceOffHandDirection:SetValue(layout.offHandFillDirection, true)
            local controls = self.resourceHandControls
            Place(controls[1], body, 0, -400)
            Place(controls[2], body, 0, -420, CONTENT_WIDTH)
            Place(controls[3], body, 0, -476)
            Place(controls[4], body, 0, -496, COLUMN_WIDTH)
            Place(controls[5], body, SECOND_COLUMN_X, -476)
            Place(controls[6], body, SECOND_COLUMN_X, -496, COLUMN_WIDTH)
            SetV2InspectorScrollContentHeight(self, 548)
        else
            SetV2InspectorScrollContentHeight(self, 402)
        end
        return
    end

    local layout = group.layout == "icons"
        and YHUD:GetIconGroupLayout(profile, group.id)
        or YHUD:GetDurationGroupLayout(profile, group.id, group.layout)
    local verticalBar = group.layout == "bars"
        and layout.orientation == "vertical"
    local columnIcons = group.layout == "icons" and layout.fillMode == "columns"
    if self.directionDropdown and self.directionDropdown.RefreshOptions then
        self.directionDropdown:RefreshOptions()
    end
    self.directionDropdown:SetValue(
        group.layout == "icons" and (columnIcons and layout.rowDirection or layout.wrapDirection)
            or group.layout == "rings"
            and (layout.direction == "outward" or layout.direction == "inward")
            and layout.direction
            or (tostring(layout.alignment)
                .. "-" .. tostring(layout.wrapDirection)),
        true
    )
    local iconLayout = group.layout == "icons"
    self.directionLabel:SetText(iconLayout
        and (columnIcons and T("designer.layout.wrap_column_direction", "换列方向")
            or T("designer.layout.wrap_direction", "换行方向"))
        or T("designer.layout.wrap_mode", "对齐与换行"))
    if iconLayout then
        self.fillModeDropdown:SetValue(layout.fillMode or "rows", true)
        Place(self.fillModeLabel, body, 0, -88)
        Place(self.fillModeDropdown, body, FIELD_LABEL_WIDTH, -80, FIELD_CONTROL_WIDTH)
        self:RefreshIconAlignment(layout)
        Place(self.iconAlignmentLabel, body, 0, -128)
        Place(self.iconAlignmentDropdown, body, FIELD_LABEL_WIDTH, -120, FIELD_CONTROL_WIDTH)
        if self.rowDirectionDropdown.RefreshOptions then self.rowDirectionDropdown:RefreshOptions() end
        self.rowDirectionDropdown:SetValue(columnIcons and layout.wrapDirection or layout.rowDirection, true)
        Place(self.rowDirectionLabel, body, 0, -168)
        Place(
            self.rowDirectionDropdown,
            body,
            FIELD_LABEL_WIDTH,
            -160,
            FIELD_CONTROL_WIDTH
        )
    end
    ShowControls(group.layout == "icons"
        and self.iconLayoutControls or self.durationLayoutControls)
    self.iconSizeLabel:Hide()
    self.iconSizeDropdown:Hide()
    self.spacingLabel:Hide()
    self.spacingDropdown:Hide()
    self.maxPerLineLabel:Hide()
    self.maxPerLineDropdown:Hide()
    self.secondarySizeLabel:Hide()
    self.secondarySizeDropdown:Hide()

    Place(self.directionLabel, body, 0, iconLayout and -208 or -88)
    Place(
        self.directionDropdown,
        body,
        FIELD_LABEL_WIDTH,
        iconLayout and -200 or -80,
        FIELD_CONTROL_WIDTH
    )
    local primary = group.layout == "icons" and sliders.iconSize
        or (group.layout == "rings" and sliders.ringDiameter or sliders.barWidth)
    primary:SetValue(group.layout == "icons" and layout.iconSize
        or (group.layout == "rings" and layout.diameter or layout.width), true)
    local columnSpacingSlider = iconLayout and sliders.iconColumnSpacing or sliders.columnSpacing
    local rowSpacingSlider = iconLayout and sliders.iconRowSpacing or sliders.rowSpacing
    columnSpacingSlider:SetValue(layout.columnSpacing, true)
    rowSpacingSlider:SetValue(layout.rowSpacing, true)
    sliders.maxPerLine:SetValue(layout.maxPerLine, true)
    if sliders.maxPerLine.label then
        sliders.maxPerLine.label:SetText((verticalBar or columnIcons)
            and T("designer.layout.max_per_column", "每列数量")
            or T("designer.layout.max_per_row", "每行数量"))
    end
    Place(primary, body, 0, iconLayout and -242 or -122)
    primary:Show()
    local concentric = group.layout == "rings"
        and (layout.direction == "outward" or layout.direction == "inward")
    if concentric then
        sliders.ringStep:SetValue(layout.ringStep, true)
        Place(sliders.ringStep, body, 0, -162)
        sliders.ringStep:Show()
    else
        local gridStartY = iconLayout and -282 or -162
        Place(columnSpacingSlider, body, 0, gridStartY)
        Place(rowSpacingSlider, body, 0, gridStartY - 40)
        Place(sliders.maxPerLine, body, 0, gridStartY - 80)
        columnSpacingSlider:Show()
        rowSpacingSlider:Show()
        sliders.maxPerLine:Show()
    end

    if iconLayout then
        sliders.itemOffset:SetValue(layout.itemOffset or 0, true)
        sliders.itemOffset.label:SetText(columnIcons
            and T("designer.layout.item_offset_x", "逐项偏移（X）")
            or T("designer.layout.item_offset_y", "逐项偏移（Y）"))
        Place(sliders.itemOffset, body, 0, -402)
        sliders.itemOffset:Show()
        SetV2InspectorScrollContentHeight(self, 460)
    end
    if group.layout == "bars" then
        sliders.barHeight:SetValue(layout.height, true)
        sliders.iconGap:SetValue(layout.iconGap, true)
        self.orientationDropdown:SetValue(
            layout.orientation .. "-" .. (layout.fillDirection or "forward"), true
        )
        self.iconPositionDropdown:SetValue(layout.iconPosition, true)
        Place(sliders.barHeight, body, 0, -282)
        Place(sliders.iconGap, body, 0, -322)
        sliders.barHeight:Show()
        sliders.iconGap:Show()
        ShowControls(self.barLayoutControls)
        self.iconGapLabel:Hide()
        self.iconGapDropdown:Hide()
        Place(self.orientationLabel, body, 0, -374)
        Place(self.iconPositionLabel, body, SECOND_COLUMN_X, -374)
        Place(self.orientationDropdown, body, 0, -394, COLUMN_WIDTH)
        Place(self.iconPositionDropdown, body, SECOND_COLUMN_X, -394, COLUMN_WIDTH)
        if I.PlaceBarWidthUI then I.PlaceBarWidthUI(self, group, layout, COLUMN_WIDTH, SECOND_COLUMN_X) end
        if sliders.barWidth.label then
            sliders.barWidth.label:SetText(layout.widthMode == "auto" and layout.orientation ~= "vertical"
                and T("designer.bar.width_fallback", "回退宽度") or T("designer.layout.width", "总长度"))
        end
        SetV2InspectorScrollContentHeight(self, layout.orientation == "vertical" and 440 or 510)
    end
end

local function EnsureResourceStyleSelection(self, profile)
    local options = BuildResourceOptions()
    local session = Designer:GetSession()
    local classFile, specID, formKey = Designer:GetResourcePreviewContext()
    local contextKey = BuildResourceStyleContextKey(classFile, specID, formKey, session.selectedGroupId)
    if self.resourceStyleSession ~= session
        or self.resourceStyleContextKey ~= contextKey then
        self.resourceStyleSession = session
        self.resourceStyleContextKey = contextKey
        self.resourceStyleResourceId = nil
    end
    local selected = self.resourceStyleResourceId
    local found = false
    for index = 1, #options do
        if options[index].value == selected then found = true break end
    end
    if not found then
        selected = options[1] and options[1].value or nil

    end
    self.resourceStyleResourceId = selected
    return selected, selected and YHUD:GetResourceSetting(profile, selected, Designer:GetSession().selectedGroupId) or nil
end

I.EnsureResourceStyleSelection = EnsureResourceStyleSelection
I.BuildResourceOptions = BuildResourceOptions
I.SetResourceContentHeight = SetV2InspectorScrollContentHeight

local function SetControlValue(control, value)
    if control and control.SetValue then
        control:SetValue(value, control.RefreshOptions and { silent = true, force = true } or true)
    end
end

local function PlaceSection(divider, body, y)
    Place(divider, body, 0, y, CONTENT_WIDTH)
    divider:Show()
end

-- Resource-specific editors are optional extensions; ordinary resources keep
-- the shared editor and lifecycle. Extension controls join the shared hide list.
DesignerUI.resourceAppearanceExtensions = DesignerUI.resourceAppearanceExtensions or {}
DesignerUI.resourceAppearanceExtensions.severity = {
    Refresh = function(_, self, body, ui, setting, y)
        local extra = self.resourceSeverityControls
        local function Keep(control)
            self.resourceV2Controls[#self.resourceV2Controls + 1] = control
            return control
        end
        if not extra then
            extra = {}
            self.resourceSeverityControls = extra
            extra.ceilingLabel = Keep(NewResourceLabel(body, "designer.resource.fill_ceiling", "填满上限（%）"))
            extra.ceiling = Keep(GUI2.Form:CreateSlider(body, {
                width = COLUMN_WIDTH - 48, inline = true, inputWidth = 42,
                min = 1, max = 500, step = 1,
                set = function(value)
                    if self.v2Refreshing then return end
                    local id = self.resourceStyleResourceId
                    RefreshResourceSliderMutation(Designer:SetResourceSetting(id, { fillCeilingPercent = value }), id, true)
                end,
            }))
            extra.previewLabel = Keep(NewResourceLabel(body, "designer.resource.severity_preview", "醉拳预览"))
            extra.previewMode = Keep(GUI2.Form:CreateDropdown(body, {
                width = COLUMN_WIDTH,
                options = {
                    { text = T("designer.resource.preview_auto", "自动演示"), value = "auto" },
                    { text = T("designer.resource.preview_manual", "手动指定"), value = "manual" },
                },
                set = function(mode)
                    if self.v2Refreshing then return end
                    local state = self.resourceSpecialPreview or { value = 150 }
                    state.resourceId, state.mode = self.resourceStyleResourceId, mode
                    self.resourceSpecialPreview = state
                    self:StartResourceValuePreview(state.resourceId)
                    self:Refresh(false, false)
                end,
            }))
            extra.valueLabel = Keep(NewResourceLabel(body, "designer.resource.preview_percent", "预览醉拳（%）"))
            extra.value = Keep(GUI2.Form:CreateSlider(body, {
                width = COLUMN_WIDTH - 48, inline = true, inputWidth = 42,
                min = 0, max = 600, step = 1,
                set = function(value)
                    if self.v2Refreshing then return end
                    self.resourceSpecialPreview = { resourceId = self.resourceStyleResourceId, mode = "manual", value = value }
                    self:StartResourceValuePreview(self.resourceStyleResourceId)
                end,
            }))
            extra.reset = Keep(GUI2.Form:CreateButton(body, {
                text = T("designer.resource.severity_reset", "恢复醉拳默认设置"), width = COLUMN_WIDTH, height = 24,
                onClick = function()
                    local id = self.resourceStyleResourceId
                    local defaults = YHUD:NormalizeResourceSetting({}, id)
                    RefreshResourceMutation(Designer:SetResourceSetting(id, {
                        fillColor = defaults.fillColor, thresholds = defaults.thresholds,
                        thresholdColorEnabled = true, thresholdMarkerEnabled = false,
                        fillCeilingPercent = 100,
                    }))
                end,
            }))
        end
        HideControls({ ui.fillColorLabel, ui.fillColor, ui.lowEnabledLabel, ui.lowEnabled,
            ui.highEnabledLabel, ui.highEnabled, ui.thresholdModeLabel, ui.thresholdMode,
            ui.lowPercent, ui.highPercent, ui.lowAbsolute, ui.highAbsolute, ui.lowCount, ui.highCount,
            ui.lowValueLabel, ui.highValueLabel, ui.lowColorLabel, ui.lowColor, ui.highColorLabel, ui.highColor,
            ui.thresholdMarkerColorLabel, ui.thresholdMarkerColor, ui.thresholdMarkerThicknessLabel, ui.thresholdMarkerThickness })
        ShowControls({ extra.ceilingLabel, extra.ceiling, extra.previewLabel, extra.previewMode,
            extra.valueLabel, extra.value, extra.reset })
        extra.ceiling:SetValue(setting.fillCeilingPercent, true)
        ui.thresholdColorEnabledLabel:SetText(T("designer.resource.severity_colors", "醉拳变色"))
        y = I.PlaceResourceAppearanceRow(body, y - 88,
            { extra.ceilingLabel, extra.ceiling, "number" })
        if setting.thresholdColorEnabled or setting.thresholdMarkerEnabled then
            ui.lowValueLabel:SetText(T("designer.resource.severity_medium_start", "中度起点（%）"))
            ui.highValueLabel:SetText(T("designer.resource.severity_heavy_start", "重度起点（%）"))
            y = I.PlaceResourceAppearanceRow(body, y,
                { ui.lowValueLabel, ui.lowPercent, "number" },
                { ui.highValueLabel, ui.highPercent, "number" })
        end
        ui.fillColorLabel:SetText(setting.thresholdColorEnabled
            and T("designer.resource.severity_light_color", "轻度颜色")
            or T("designer.resource.fixed_color", "固定颜色"))
        if setting.thresholdColorEnabled then
            ui.lowColorLabel:SetText(T("designer.resource.severity_medium_color", "中度颜色"))
            ui.highColorLabel:SetText(T("designer.resource.severity_heavy_color", "重度颜色"))
        end
        y = I.PlaceResourceAppearanceRow(body, y,
            { ui.fillColorLabel, ui.fillColor, "color" },
            setting.thresholdColorEnabled and { ui.lowColorLabel, ui.lowColor, "color" } or nil)
        if setting.thresholdColorEnabled then
            y = I.PlaceResourceAppearanceRow(body, y,
                { ui.highColorLabel, ui.highColor, "color" })
        end
        if setting.thresholdMarkerEnabled then
            y = I.PlaceResourceAppearanceRow(body, y,
                { ui.thresholdMarkerThicknessLabel, ui.thresholdMarkerThickness, "number" },
                { ui.thresholdMarkerColorLabel, ui.thresholdMarkerColor, "color" })
        end
        local state = self.resourceSpecialPreview
        local manual = state and state.resourceId == self.resourceStyleResourceId and state.mode == "manual"
        SetControlValue(extra.previewMode, manual and "manual" or "auto")
        extra.value:SetValue(state and state.value or 150, true)
        SetDisabled(extra.value, not manual)
        if not manual then HideControls({ extra.valueLabel, extra.value }) end
        y = I.PlaceResourceAppearanceRow(body, y,
            { extra.previewLabel, extra.previewMode, "wide" },
            manual and { extra.valueLabel, extra.value, "number" } or nil)
        y = I.PlaceResourceAppearanceRow(body, y, { nil, extra.reset, "button" })
        return y
    end,
}

local function RefreshResourceAppearancePage(self, profile, group)
    if self.resourceV2Appearance and self.resourceV2Appearance.windup then
        HideControls(self.resourceV2Appearance.windup.controls)
    end
    local body = self.groupInspectorBody
    local ui = self.resourceV2Appearance
    local vertical = YHUD:GetResourceGroupLayout(profile, group.id).orientation == "vertical"
    ui.heightOverrideLabel:SetText(vertical and T("designer.resource.thickness_override", "覆盖粗细") or T("designer.resource.height_override", "覆盖高度"))
    ui.heightLabel:SetText(vertical and T("designer.resource.item_thickness", "单项粗细") or T("designer.resource.item_height", "单项高度"))
    ui.fillColorLabel:SetText(T("designer.resource.fill_color", "填充颜色"))
    ui.lowColorLabel:SetText(T("designer.resource.threshold_low_color", "低区间颜色"))
    ui.highColorLabel:SetText(T("designer.resource.threshold_high_color", "高区间颜色"))
    ui.thresholdColorEnabledLabel:SetText(T("designer.resource.threshold_color_enabled", "阈值变色"))
    local style = YHUD:GetResourceGroupStyle(profile, group.id)
    local resourceId, setting = EnsureResourceStyleSelection(self, profile)
    if not resourceId and self.ShowEmptyResourceSelection then return self:ShowEmptyResourceSelection("appearance") end
    if resourceId == "cast" then
        for _, control in ipairs({ self.resourceBorderDropdown, ui.height }) do
            if control.gui2CompactSlider then control:SetCompactMode(false) end
        end
        ui.fillColorLabel:SetText(T("player_cast.color", "普通施法颜色"))
        local mixed = group.contentPolicy ~= "cast-only"
        local y = mixed and -32 or -4
        if mixed then PlaceSection(ui.globalDivider, body, -4) end
        local global = self.resourceAppearanceControls
        local rows = {
            { global[1], global[3], global[2], global[4] },
            { global[5], global[6], global[11], global[12] },
        }
        for _, row in ipairs(rows) do
            ShowControls(row)
            PlaceResourceField(row[1], row[2], body, 0, y)
            PlaceResourceField(row[3], row[4], body, SECOND_COLUMN_X, y)
            y = y - 64
        end
        self.resourceBorderDropdown:SetValue(style.border, true)
        self.resourceBackgroundPicker:SetValue(style.backgroundColor, true)
        self.resourceTextureDropdown:SetValue(style.fillTexture, true)
        self.resourceBorderColorPicker:SetValue(style.borderColor, true)
        if mixed then
            PlaceSection(ui.itemDivider, body, y)
            y = y - 28
            ShowControls({ ui.resourceLabel, ui.resource })
            ui.resource:SetValue("cast", true)
            y = I.PlaceResourceAppearanceRow(body, y,
                { ui.resourceLabel, ui.resource, "fullSelect" })
        end
        y = I.RefreshPlayerCastOptions(self, profile, group, "appearance", y)
        ShowControls({ ui.fillColorLabel, ui.fillColor })
        PlaceResourceField(ui.fillColorLabel, ui.fillColor, body, SECOND_COLUMN_X, y + 64)
        ui.fillColor:SetValue(setting.fillColor, true)
        if group.contentPolicy ~= "cast-only" then
            ShowControls({ ui.heightOverrideLabel, ui.heightOverride, ui.heightLabel, ui.height })
            PlaceResourceSwitch(ui.heightOverrideLabel, ui.heightOverride, body, 0, y)
            PlaceResourceField(ui.heightLabel, ui.height, body, SECOND_COLUMN_X, y)
            local heightOverridden = setting.heightOverride ~= nil
            ui.heightOverride:SetValue(heightOverridden, true)
            ui.height:SetValue(setting.heightOverride or YHUD:GetResourceGroupLayout(profile, group.id).height, true)
            SetDisabled(ui.height, not heightOverridden)
            y = y - 64
        end
        local castUI = self.playerCastPages.appearance
        PlaceResourceField(castUI.idleLabel, castUI.idle, body, 0, y)
        PlaceResourceSwitch(castUI.nativeLabel, castUI.native, body, SECOND_COLUMN_X, y)
        castUI.idle:SetValue(setting.cast.idle, true)
        y = y - 64
        SetV2InspectorScrollContentHeight(self, -y + 24)
        return
    end
    local override = setting and setting.appearanceOverride
    local effective = override or style
    self.resourceBorderDropdown:SetValue(style.border, true)
    self.resourceBackgroundPicker:SetValue(style.backgroundColor, true)
    self.resourceTextureDropdown:SetValue(style.fillTexture, true)
    self.resourceBorderColorPicker:SetValue(style.borderColor, true)
    self.resourceSmoothProgressSwitch:SetValue(
        style.smoothProgress == true,
        true
    )
    local appearanceOptions = {
        ui.fillDirectionLabel, ui.fillDirection,
        ui.visibilityModeLabel, ui.visibilityMode,
        ui.displayModeLabel, ui.displayMode,
        ui.inverseFillLabel, ui.inverseFill,
        ui.heightOverrideLabel, ui.heightOverride,
        ui.heightLabel, ui.height,
        ui.segmentSpacingLabel, ui.segmentSpacing,
        ui.dotSpacingLabel, ui.dotSpacing,
        ui.pointShapeLabel, ui.pointShape, ui.nativePointLabel, ui.nativePoint, ui.nativePointUnavailable,
        ui.dividerThicknessLabel, ui.dividerThickness,
        ui.dividerColorLabel, ui.dividerColor,
        ui.thresholdDivider,
        ui.thresholdColorEnabledLabel, ui.thresholdColorEnabled,
        ui.thresholdMarkerEnabledLabel, ui.thresholdMarkerEnabled,
        ui.lowEnabledLabel, ui.lowEnabled,
        ui.highEnabledLabel, ui.highEnabled,
        ui.lowValueLabel, ui.highValueLabel,
        ui.lowPercent, ui.highPercent, ui.lowCount, ui.highCount,
        ui.lowAbsolute, ui.highAbsolute, ui.thresholdModeLabel, ui.thresholdMode,
        ui.lowColorLabel, ui.lowColor,
        ui.highColorLabel, ui.highColor,
        ui.thresholdMarkerThicknessLabel, ui.thresholdMarkerThickness,
        ui.thresholdMarkerColorLabel, ui.thresholdMarkerColor,
        ui.runeBloodColorLabel, ui.runeBloodColor,
        ui.runeFrostColorLabel, ui.runeFrostColor,
        ui.runeUnholyColorLabel, ui.runeUnholyColor,
        ui.runeCooldownTextSizeLabel, ui.runeCooldownTextSize,
        ui.runeCooldownTextModeLabel, ui.runeCooldownTextMode,
    }
    HideControls(appearanceOptions)
    ShowControls(self.resourceAppearanceControls)
    local global = self.resourceAppearanceControls
    global[7]:Hide()
    global[8]:Hide()
    global[9]:Hide()
    global[10]:Hide()
    PlaceSection(ui.globalDivider, body, -4)
    local y = -32
    y = I.PlaceResourceAppearanceRow(body, y,
        { global[5], global[6], "select" },
        { self.resourceSmoothProgressLabel, self.resourceSmoothProgressSwitch, "switch" })
    y = I.PlaceResourceAppearanceRow(body, y,
        { global[2], global[4], "color" }, { global[11], global[12], "color" })
    y = I.PlaceResourceAppearanceRow(body, y,
        { global[1], global[3], "number" }, { nil, ui.restoreDefaults, "button" })
    PlaceSection(ui.itemDivider, body, y - 4)
    y = y - 32

    local definition = resourceId and ResourceCatalog
        and ResourceCatalog.GetDefinition
        and ResourceCatalog:GetDefinition(resourceId, profile, group.id) or nil
    local discrete = definition and definition.valueKind == "discrete"
    local heightOverridden = setting and setting.heightOverride ~= nil
    local groupLayout = YHUD:GetResourceGroupLayout(profile, group.id)
    local displayMode = setting and setting.displayMode or "bar"
    local nativePoints = displayMode == "nativePoints"
    local thresholdMarkerSupported = displayMode ~= "cells" and displayMode ~= "dots" and not nativePoints
    local thresholdColorEnabled = setting and setting.thresholdColorEnabled == true
    local thresholdMarkerEnabled = thresholdMarkerSupported and setting and setting.thresholdMarkerEnabled == true
    local thresholds = setting and setting.thresholds or {}
    local low, high = thresholds.low or {}, thresholds.high or {}
    local runes = resourceId == "runes"
    local inverse = not nativePoints and YHUD:IsResourceInverseFillSupported(definition, setting)
    SetControlValue(ui.resource, resourceId)
    SetControlValue(ui.visibilityMode, setting and setting.visibilityMode or "always")
    SetControlValue(ui.fillDirection, setting and setting.fillDirection or "inherit")
    SetControlValue(ui.displayMode, displayMode)
    SetControlValue(ui.texture, effective.fillTexture)
    ui.fillModeLabel:Hide()
    ui.fillMode:Hide()
    y = I.PlaceResourceAppearanceRow(body, y,
        { ui.resourceLabel, ui.resource, "fullSelect", ui.resourceHelp })
    local fillField = not nativePoints and (runes and { ui.runeBloodColorLabel, ui.runeBloodColor, "color" }
        or { ui.fillColorLabel, ui.fillColor, "color" }) or nil
    y = I.PlaceResourceAppearanceRow(body, y,
        discrete and { ui.displayModeLabel, ui.displayMode, "compactSelect", nil, ResourceDisplayModeOptions() } or fillField,
        discrete and fillField or nil)
    if discrete and displayMode == "divided" then
        y = I.PlaceResourceAppearanceRow(body, y,
            { ui.dividerThicknessLabel, ui.dividerThickness, "number" },
            { ui.dividerColorLabel, ui.dividerColor, "color" })
    elseif discrete and displayMode == "dots" then
        y = I.PlaceResourceAppearanceRow(body, y,
            { ui.pointShapeLabel, ui.pointShape, "compactSelect", nil, I.ResourcePointShapeOptions() },
            { ui.dotSpacingLabel, ui.dotSpacing, "number" })
    elseif discrete and nativePoints then
        y = I.PlaceResourceAppearanceRow(body, y,
            { ui.nativePointLabel, ui.nativePoint, "fullSelect" })
        y = I.PlaceResourceAppearanceRow(body, y,
            { ui.dotSpacingLabel, ui.dotSpacing, "number" })
        local classFile, specID = Designer:GetResourcePreviewContext()
        local selected = YHUD:ResolveNativeResourcePointStyle(setting, { id = resourceId, classFile = classFile, specID = specID })
        if not (GUI2.ResourcePoints and GUI2.ResourcePoints:GetNativeStyle(selected)) then
            Place(ui.nativePointUnavailable, body, 0, y, CONTENT_WIDTH)
            ui.nativePointUnavailable:SetHeight(36)
            ui.nativePointUnavailable:Show()
            y = y - 40
        end
    elseif discrete and displayMode == "cells" then
        y = I.PlaceResourceAppearanceRow(body, y,
            { ui.segmentSpacingLabel, ui.segmentSpacing, "number" })
    end
    y = I.PlaceResourceAppearanceRow(body, y,
        { ui.visibilityModeLabel, ui.visibilityMode, "fullSelect" })
    y = I.PlaceResourceAppearanceRow(body, y,
        { ui.fillDirectionLabel, ui.fillDirection, "fullSelect" })
    y = I.PlaceResourceAppearanceRow(body, y,
        { ui.heightOverrideLabel, ui.heightOverride, "switch" },
        { ui.heightLabel, ui.height, "number" })
    SetDisabled(ui.height, not heightOverridden)
    if not nativePoints then
        y = I.PlaceResourceAppearanceRow(body, y,
            { ui.overrideLabel, ui.override, "switch" },
            inverse and { ui.inverseFillLabel, ui.inverseFill, "switch" } or nil)
    else ui.overrideLabel:Hide(); ui.override:Hide() end
    local itemOptions = {
        ui.borderLabel, ui.border, ui.backgroundLabel, ui.background,
        ui.textureLabel, ui.texture, ui.borderColorLabel, ui.borderColor,
    }
    if override and not nativePoints then
        y = I.PlaceResourceAppearanceRow(body, y,
            { ui.textureLabel, ui.texture, "select" }, { ui.backgroundLabel, ui.background, "color" })
        y = I.PlaceResourceAppearanceRow(body, y,
            { ui.borderLabel, ui.border, "number" }, { ui.borderColorLabel, ui.borderColor, "color" })
    else HideControls(itemOptions) end
    if runes then
        HideControls({ ui.fillColorLabel, ui.fillColor })
        if not nativePoints then
            y = I.PlaceResourceAppearanceRow(body, y,
                { ui.runeFrostColorLabel, ui.runeFrostColor, "color" },
                { ui.runeUnholyColorLabel, ui.runeUnholyColor, "color" })
        end
        y = I.PlaceResourceAppearanceRow(body, y,
            { ui.runeCooldownTextModeLabel, ui.runeCooldownTextMode, "select" },
            { ui.runeCooldownTextSizeLabel, ui.runeCooldownTextSize, "number" })
    end
    local extensionY = y
    local nextY = y
    if resourceId == "swingRanged" and setting.rangedWindup then
        local windup, controls = setting.rangedWindup, ui.windup
        PlaceSection(controls.heading, body, y)
        nextY = I.PlaceResourceAppearanceRow(body, y - 28,
            { controls.colorLabel, controls.color, "color" },
            { controls.enabledLabel, controls.enabled, "switch" })
        if windup.markerEnabled then
            nextY = I.PlaceResourceAppearanceRow(body, nextY,
                { controls.markerColorLabel, controls.markerColor, "color" },
                { controls.thicknessLabel, controls.thickness, "number" })
        end
        Place(controls.help, body, 0, nextY, CONTENT_WIDTH)
        controls.help:SetHeight(36)
        controls.help:Show()
        nextY = nextY - 40
        SetControlValue(controls.color, windup.color)
        SetControlValue(controls.markerColor, windup.markerColor)
        controls.enabled:SetValue(windup.markerEnabled, true)
        controls.thickness:SetValue(windup.markerThickness, true)
    elseif not nativePoints then
        PlaceSection(ui.thresholdDivider, body, y)
        nextY = y - 28
        nextY = I.PlaceResourceAppearanceRow(body, nextY,
            { ui.thresholdColorEnabledLabel, ui.thresholdColorEnabled, "switch" },
            thresholdMarkerSupported and { ui.thresholdMarkerEnabledLabel, ui.thresholdMarkerEnabled, "switch" } or nil)
        if thresholdColorEnabled or thresholdMarkerEnabled then
            local selectable = YHUD:IsResourceThresholdModeSelectable(definition)
            local absolute = selectable and setting.thresholdMode == "value"
            if selectable then
                SetControlValue(ui.thresholdMode, setting.thresholdMode)
                nextY = I.PlaceResourceAppearanceRow(body, nextY,
                    { ui.thresholdModeLabel, ui.thresholdMode, "select" })
            end
            ui.lowValueLabel:SetText(discrete
                and T("designer.resource.threshold_low_count", "低阈值（层）")
                or absolute and T("designer.resource.threshold_low_value", "低阈值（数值）")
                or T("designer.resource.threshold_low_percent", "低阈值（%）"))
            ui.highValueLabel:SetText(discrete
                and T("designer.resource.threshold_high_count", "高阈值（层）")
                or absolute and T("designer.resource.threshold_high_value", "高阈值（数值）")
                or T("designer.resource.threshold_high_percent", "高阈值（%）"))
            local lowValue = discrete and ui.lowCount or absolute and ui.lowAbsolute or ui.lowPercent
            local highValue = discrete and ui.highCount or absolute and ui.highAbsolute or ui.highPercent
            nextY = I.PlaceResourceAppearanceRow(body, nextY,
                { ui.lowEnabledLabel, ui.lowEnabled, "switch" },
                { ui.highEnabledLabel, ui.highEnabled, "switch" })
            nextY = I.PlaceResourceAppearanceRow(body, nextY,
                { ui.lowValueLabel, lowValue, "number" }, { ui.highValueLabel, highValue, "number" })
            if thresholdColorEnabled then
                nextY = I.PlaceResourceAppearanceRow(body, nextY,
                    { ui.lowColorLabel, ui.lowColor, "color" }, { ui.highColorLabel, ui.highColor, "color" })
            end
            if thresholdMarkerEnabled then
                nextY = I.PlaceResourceAppearanceRow(body, nextY,
                    { ui.thresholdMarkerThicknessLabel, ui.thresholdMarkerThickness, "number" },
                    { ui.thresholdMarkerColorLabel, ui.thresholdMarkerColor, "color" })
            end
        end
    end
    local extension = not nativePoints and definition and self.resourceAppearanceExtensions[definition.appearanceExtension]
    if extension then nextY = extension:Refresh(self, body, ui, setting, extensionY) end
    SetControlValue(ui.resource, resourceId)
    ui.override:SetValue(setting and setting.appearanceOverride ~= nil, true)
    ui.heightOverride:SetValue(heightOverridden, true)
    ui.height:SetValue(
        heightOverridden and setting.heightOverride or groupLayout.height,
        true
    )
    SetControlValue(ui.border, effective.border)
    SetControlValue(ui.background, effective.backgroundColor)
    SetControlValue(ui.texture, effective.fillTexture)
    SetControlValue(ui.fillColor, setting and setting.fillColor)
    local runeColors = setting and setting.runeColors or {}
    SetControlValue(ui.runeBloodColor, runeColors.blood)
    SetControlValue(ui.runeFrostColor, runeColors.frost)
    SetControlValue(ui.runeUnholyColor, runeColors.unholy)
    if ui.runeCooldownTextMode then
        SetControlValue(ui.runeCooldownTextMode, setting and setting.runeCooldownTextMode or "all")
    end
    if ui.runeCooldownTextSize then
        ui.runeCooldownTextSize:SetValue(
            setting and setting.runeCooldownTextSize or 12,
            true
        )
    end
    SetControlValue(ui.borderColor, effective.borderColor)
    SetControlValue(
        ui.visibilityMode,
        setting and setting.visibilityMode or "always"
    )
    SetControlValue(ui.displayMode, displayMode)
    ui.inverseFill:SetValue(setting and setting.inverseFill == true, true)
    ui.segmentSpacing:SetValue(setting and setting.segmentSpacing or 2, true)
    ui.dotSpacing:SetValue(math.max(0, setting and setting.segmentSpacing or 2), true)
    SetControlValue(ui.pointShape, setting and setting.pointShape or "circle")
    SetControlValue(ui.nativePoint, setting and setting.nativePointStyle or "auto")
    ui.dividerThickness:SetValue(
        setting and setting.dividerThickness or 1,
        true
    )
    SetControlValue(ui.dividerColor, setting and setting.dividerColor)
    ui.thresholdColorEnabled:SetValue(thresholdColorEnabled, true)
    ui.thresholdMarkerEnabled:SetValue(thresholdMarkerEnabled, true)
    ui.lowEnabled:SetValue(low.enabled == true, true)
    ui.highEnabled:SetValue(high.enabled == true, true)
    ui.lowPercent:SetValue(low.value or 30, true)
    ui.highPercent:SetValue(high.value or 70, true)
    ui.lowCount:SetValue(low.value or 1, true)
    ui.highCount:SetValue(high.value or 1, true)
    ui.lowAbsolute:SetValue(low.value or 30, true)
    ui.highAbsolute:SetValue(high.value or 70, true)
    SetControlValue(ui.lowColor, low.color)
    SetControlValue(ui.highColor, high.color)
    ui.thresholdMarkerThickness:SetValue(
        setting and setting.thresholdMarkerThickness or 1,
        true
    )
    SetControlValue(
        ui.thresholdMarkerColor,
        setting and setting.thresholdMarkerColor
    )
    local contentBottom = nextY
    SetV2InspectorScrollContentHeight(self, -contentBottom + 24)
end

local function RefreshAppearancePage(self, profile, group)
    local body = self.groupInspectorBody
    HideAppearancePageVariants(self)
    body:Show()
    if group.layout == "resource" then
        return RefreshResourceAppearancePage(self, profile, group)
    end

    local style = group.layout == "icons"
        and YHUD:GetIconGroupStyle(profile, group.id)
        or YHUD:GetDurationGroupStyle(profile, group.id)
    if group.layout == "rings" then
        ShowControls(self.durationAppearanceControls)
        ShowControls(self.ringAppearanceControls)
        self.showDurationIconLabel:Hide()
        self.showDurationIconSwitch:Hide()
        self.durationSmoothProgressLabel:Hide()
        self.durationSmoothProgressSwitch:Hide()
        self.fillTextureLabel:Hide()
        self.fillTextureDropdown:Hide()
        self.fillColorPicker:SetValue(style.fillColor, true)
        self.trackColorPicker:SetValue(style.ringTrackColor, true)
        Place(self.fillColorLabel, body, 0, -8)
        Place(self.trackColorLabel, body, SECOND_COLUMN_X, -8)
        Place(self.fillColorPicker, body, 0, -28, COLUMN_WIDTH)
        Place(self.trackColorPicker, body, SECOND_COLUMN_X, -28, COLUMN_WIDTH)
        self.ringThicknessDropdown:SetValue(style.ringThickness, true)
        self.ringProgressDirectionDropdown:SetValue(
            style.ringDirection,
            true
        )
        self.ringStartDropdown:SetValue(style.ringStart, true)
        Place(self.ringThicknessLabel, body, 0, -72)
        Place(self.ringProgressDirectionLabel, body, SECOND_COLUMN_X, -72)
        Place(self.ringThicknessDropdown, body, 0, -92, COLUMN_WIDTH)
        Place(
            self.ringProgressDirectionDropdown,
            body,
            SECOND_COLUMN_X,
            -92,
            COLUMN_WIDTH
        )
        Place(self.ringStartLabel, body, 0, -136)
        Place(self.ringStartDropdown, body, 0, -156, COLUMN_WIDTH)
        return
    end
    ShowControls(self.iconAppearanceControls)
    for _, control in ipairs({ self.borderDropdown, self.zoomLabel, self.zoomDropdown,
        self.iconBackgroundLabel, self.iconBackgroundPicker, self.iconBorderColorLabel, self.iconBorderColorPicker,
        self.iconShadowLabel, self.iconShadowSwitch, self.iconShadowColorLabel, self.iconShadowColorPicker }) do control:Hide() end
    self.v2Sliders.iconZoom:Hide()
    self.shapeDropdown:SetValue(style.skinId, true)
    self.borderLabel:Hide()
    Place(self.shapeLabel, body, 0, -8)
    Place(self.shapeDropdown, body, 146, 0, CONTENT_WIDTH - 146 - 10)
    if group.layout == "icons" then
        self.cooldownSwipeSwitch:SetValue(style.cooldownSwipe ~= false, true)
        Place(self.cooldownSwipeLabel, body, 0, -48)
        Place(self.cooldownSwipeSwitch, body, SWITCH_X, -44)
        self.cooldownSwipeLabel:Show()
        self.cooldownSwipeSwitch:Show()
        self.chargeRecoveryControl:SetValue(style.chargeRecoveryDisplay or "hideSwipeOnly", true)
        self.chargeRecoveryControl:SetPresentationLimits(style.cooldownSwipe ~= false, style.cooldownText ~= false)
        self.chargeRecoveryControl:SetPreviewStyle(GUI2.IconSkins:ApplyRecipe(YHUD:CopyValue(style), "Halo"))
        Place(self.chargeRecoveryControl, body, 0, -77, CONTENT_WIDTH)
        self.chargeRecoveryControl:Show()
        self.cooldownGCDSwitch:SetValue(style.cooldownGCD ~= false, true)
        Place(self.cooldownGCDLabel, body, 0, -124)
        Place(self.cooldownGCDSwitch, body, SWITCH_X, -120)
        self.cooldownGCDLabel:Show()
        self.cooldownGCDSwitch:Show()
        self.cooldownBlingSwitch:SetValue(style.cooldownBling == true, true)
        Place(self.cooldownBlingLabel, body, 0, -162)
        Place(self.cooldownBlingSwitch, body, SWITCH_X, -158)
        self.cooldownBlingLabel:Show()
        self.cooldownBlingSwitch:Show()
        self.pandemicGlowSwitch:SetValue(
            not (profile.style and profile.style.pandemicGlow == false),
            true
        )
        Place(self.pandemicGlowDivider, body, 0, -208, CONTENT_WIDTH)
        Place(self.pandemicGlowLabel, body, 0, -246)
        Place(self.pandemicGlowSwitch, body, SWITCH_X, -242)
        self.pandemicGlowDivider:Show()
        self.pandemicGlowLabel:Show()
        self.pandemicGlowSwitch:Show()
        SetV2InspectorScrollContentHeight(self, 288)
    else
        ShowControls(self.durationAppearanceControls)
        self.showDurationIconSwitch:SetValue(style.showIcon ~= false, true)
        self.durationSmoothProgressSwitch:SetValue(
            style.smoothProgress == true,
            true
        )
        self.fillColorPicker:SetValue(style.fillColor, true)
        self.trackColorPicker:SetValue(style.trackColor, true)
        self.fillTextureDropdown:SetValue(style.fillTexture, true)
        Place(self.showDurationIconLabel, body, 0, -80)
        Place(self.showDurationIconSwitch, body, COLUMN_SWITCH_X, -76)
        Place(
            self.durationSmoothProgressLabel,
            body,
            SECOND_COLUMN_X,
            -80
        )
        Place(
            self.durationSmoothProgressSwitch,
            body,
            SECOND_COLUMN_X + COLUMN_SWITCH_X,
            -76
        )
        Place(self.fillColorLabel, body, 0, -120)
        Place(self.trackColorLabel, body, SECOND_COLUMN_X, -120)
        Place(self.fillColorPicker, body, 0, -140, COLUMN_WIDTH)
        Place(self.trackColorPicker, body, SECOND_COLUMN_X, -140, COLUMN_WIDTH)
        Place(self.fillTextureLabel, body, 0, -182)
        Place(self.fillTextureDropdown, body, 0, -202, CONTENT_WIDTH)
        self.pandemicGlowSwitch:SetValue(
            not (profile.style and profile.style.pandemicGlow == false),
            true
        )
        Place(self.pandemicGlowDivider, body, 0, -254, CONTENT_WIDTH)
        Place(self.pandemicGlowLabel, body, 0, -292)
        Place(self.pandemicGlowSwitch, body, SWITCH_X, -288)
        self.pandemicGlowDivider:Show()
        self.pandemicGlowLabel:Show()
        self.pandemicGlowSwitch:Show()
    end
end

local function CommitKeybindOverride(self, row, value)
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local groupId = session and session.selectedGroupId
    local style = profile and groupId
        and YHUD:GetIconGroupStyle(profile, groupId)
    local service = YHUD.KeybindText
    if not (style and row and row.targetKey and service) then return false end
    if row.override == nil and value == row.displayValue
        and row.inputEdited ~= true then
        return false
    end
    value = service:Sanitize(value) or ""
    if row.override ~= nil and value == row.override then return false end
    local overrides = YHUD:CopyValue(style.keybindTextOverrides or {})
    overrides[row.targetKey] = value
    if not Designer:SetGroupIconStyle(groupId, {
        keybindTextOverrides = overrides,
    }) then
        return false
    end
    row.override = value
    row.inputEdited = nil
    self:ApplyPreview()
    self:Refresh(false, false)
    return true
end

local function RestoreKeybindOverride(self, row)
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local groupId = session and session.selectedGroupId
    local style = profile and groupId
        and YHUD:GetIconGroupStyle(profile, groupId)
    if not (style and row and row.targetKey
        and style.keybindTextOverrides[row.targetKey] ~= nil) then
        return false
    end
    local overrides = YHUD:CopyValue(style.keybindTextOverrides)
    overrides[row.targetKey] = nil
    if not Designer:SetGroupIconStyle(groupId, {
        keybindTextOverrides = overrides,
    }) then
        return false
    end
    self:ApplyPreview()
    self:Refresh(false, false)
    return true
end

local function EnsureKeybindOverrideRow(self, index)
    local row = self.keybindOverrideRows[index]
    if row then return row end
    local body = self.groupInspectorBody
    row = GUI2:CreatePanel(body, {
        width = CONTENT_WIDTH,
        height = 56,
        surface = "color.surface.panel",
        border = "color.border.default",
    })
    row.icon = GUI2:CreateIcon(row, {
        icon = QUESTION_ICON,
        size = 36,
    })
    row.icon:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.name = GUI2:CreateText(
        row, "", "font.size.md", "color.text.primary", "LEFT"
    )
    row.name:SetPoint("BOTTOMLEFT", row, "LEFT", 54, 2)
    row.name:SetWidth(170)
    row.name:SetWordWrap(false)
    row.status = GUI2:CreateText(
        row, "", "font.size.sm", "color.text.secondary", "LEFT"
    )
    row.status:SetPoint("TOPLEFT", row, "LEFT", 54, -2)
    row.status:SetWidth(170)
    row.status:SetWordWrap(false)
    row.restore = GUI2.Form:CreateIconButton(row, {
        size = 30,
        icon = SettingsIcon("rotate-ccw"),
        tooltip = T(
            "designer.keybind.restore_auto",
            "恢复自动识别"
        ),
        onClick = function()
            RestoreKeybindOverride(DesignerUI, row)
        end,
    })
    row.restore:SetPoint("RIGHT", row, "RIGHT", -104, 0)
    row.input = GUI2.Form:CreateEditBox(row, {
        width = 90,
        height = 30,
    })
    row.input:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.input:SetScript("OnEnterPressed", function(input)
        CommitKeybindOverride(DesignerUI, row, input:GetText())
        input:ClearFocus()
    end)
    row.input:SetScript("OnTextChanged", function(input)
        if input.gui2SettingText then return end
        row.inputEdited = true
    end)
    row.input:SetScript("OnEditFocusLost", function(input)
        if input.gui2Bg then
            GUI2:SetBorderColor(input.gui2Bg, "color.border.default")
        end
        CommitKeybindOverride(DesignerUI, row, input:GetText())
    end)
    row.input:SetScript("OnEscapePressed", function(input)
        input:SetValue(row.displayValue or "", true)
        row.inputEdited = nil
        input:ClearFocus()
    end)
    row:Hide()
    self.keybindOverrideRows[index] = row
    return row
end

local function RefreshKeybindEditor(self, profile, group, style)
    local body = self.groupInspectorBody
    local service = YHUD.KeybindText
    local rows = service and service:BuildRows(profile, group.id) or {}
    local recognized, manual = 0, 0
    for index = 1, #rows do
        if rows[index].automatic then recognized = recognized + 1 end
        if rows[index].override ~= nil then manual = manual + 1 end
    end
    ShowControls(self.keybindTextControls)
    self.keybindModeDropdown:SetValue(style.keybindTextMode, true)
    self.keybindSummary:SetText(string.format(
        T("designer.keybind.summary", "已识别 %d / %d · %d 项覆盖"),
        recognized,
        #rows,
        manual
    ))
    self.keybindTextFilter = self.keybindTextFilter or "all"
    self.keybindFilterDropdown:SetValue(self.keybindTextFilter, true)
    self.keybindOverrideCount:SetText(string.format(
        T("designer.keybind.item_count", "%d 项"), #rows
    ))
    SetDisabled(self.keybindClearOverrides, manual == 0)

    self.textEditorTitle:SetText(T("designer.keybind.title", "按键文本"))
    Place(self.textEditorTitle, body, 0, -8)
    Place(self.textEditorBack, body, CONTENT_WIDTH - 68, -4, 68)
    self.textEditorTitle:Show()
    self.textEditorBack:Show()
    Place(self.keybindSourceDivider, body, 0, -44, CONTENT_WIDTH)
    Place(self.keybindModeLabel, body, 0, -80)
    Place(self.keybindModeDropdown, body, 82, -72, CONTENT_WIDTH - 82)
    Place(self.keybindSummary, body, 82, -108, CONTENT_WIDTH - 82)
    Place(self.keybindStyleDivider, body, 0, -138, CONTENT_WIDTH)

    self.keybindFont:SetTarget(YHUD.FontStyle:Key(group.id, "keybindText"))
    Place(self.keybindFont, body, 82, -174, CONTENT_WIDTH - 82)
    self.keybindFont:Show()
    self.textPositionDropdown:SetValue(style.keybindTextPosition, true)
    Place(self.iconTextControls[8], body, 0, -220)
    Place(self.textPositionDropdown, body, 82, -212, CONTENT_WIDTH - 82)
    self.iconTextControls[8]:Show()
    self.textPositionDropdown:Show()
    Place(self.keybindOverridesDivider, body, 0, -258, CONTENT_WIDTH)
    Place(self.keybindOverrideCount, body, CONTENT_WIDTH - 170, -290, 56)
    Place(self.keybindFilterDropdown, body, CONTENT_WIDTH - 104, -282, 104)
    local visibleIndex = 0
    for index = 1, #rows do
        local data = rows[index]
        local visible = self.keybindTextFilter == "all"
            or (self.keybindTextFilter == "missing" and not data.automatic)
            or (self.keybindTextFilter == "manual" and data.override ~= nil)
        if visible then
            visibleIndex = visibleIndex + 1
            local row = EnsureKeybindOverrideRow(self, visibleIndex)
            row.targetKey = data.targetKey
            row.override = data.override
            row.displayValue = data.effective or ""
            local icon = data.icon or EntryIcon(data.entry) or QUESTION_ICON
            if GUI2.SetIconTexture then
                GUI2:SetIconTexture(row.icon, icon, QUESTION_ICON)
            elseif row.icon.SetIcon then
                row.icon:SetIcon(icon)
            elseif row.icon.SetTexture then
                row.icon:SetTexture(icon)
            end
            row.name:SetText(data.name)
            local status
            if data.override ~= nil then
                status = data.override == ""
                    and T("designer.keybind.status.hidden", "手动 · 隐藏")
                    or string.format(
                        T("designer.keybind.status.manual", "手动 · %s"),
                        data.override
                    )
            elseif style.keybindTextMode == "manual" then
                status = T(
                    "designer.keybind.status.hidden",
                    "手动 · 隐藏"
                )
            else
                status = data.automatic
                    and string.format(
                        T("designer.keybind.status.auto", "自动 · %s"),
                        data.automatic
                    )
                    or T("designer.keybind.status.missing", "自动 · 未识别")
            end
            row.status:SetText(status)
            row.input:SetValue(row.displayValue, true)
            row.inputEdited = nil
            SetDisabled(row.restore, data.override == nil)
            if row.restore.EnableMouse then
                row.restore:EnableMouse(data.override ~= nil)
            end
            Place(row, body, 0, -318 - ((visibleIndex - 1) * 64), CONTENT_WIDTH)
            row:Show()
        end
    end
    for index = visibleIndex + 1, #self.keybindOverrideRows do
        self.keybindOverrideRows[index]:Hide()
    end
    local footerY = -318 - (visibleIndex * 64)
    Place(self.keybindClearOverrides, body, CONTENT_WIDTH - 132, footerY, 132)
    SetV2InspectorScrollContentHeight(self, -footerY + 48)
end

local function RefreshTextPage(self, profile, group)
    local body = self.groupInspectorBody
    body:Show()
    local editing = self.textEditorTarget == "keybind" and group.layout == "icons"
    if not editing then self.textEditorTarget = nil end
    if group.layout == "resource" then
        local id = EnsureResourceStyleSelection(self, profile)
        if not id and self.ShowEmptyResourceSelection then return self:ShowEmptyResourceSelection("text") end
        if id == "cast" then
            local ui = self.resourceV2Text
            local mixed = group.contentPolicy ~= "cast-only"
            local y = mixed and -32 or -4
            if mixed then PlaceSection(ui.globalDivider, body, -4) end
            local style = YHUD:GetResourceGroupStyle(profile, group.id)
            ui.globalFont:SetTarget(YHUD.FontStyle:Key(group.id, "text"))
            Place(ui.globalFont, body, 0, y, CONTENT_WIDTH)
            ui.globalFont:Show()
            y = y - 48
            if mixed then
                PlaceSection(ui.itemDivider, body, y)
                y = y - 28
                ShowControls({ ui.resourceLabel, ui.resource })
                PlaceResourceField(ui.resourceLabel, ui.resource, body, 0, y)
                ui.resource:SetValue("cast", true)
                y = y - 64
            end
            y = I.RefreshPlayerCastOptions(self, profile, group, "text", y)
            SetV2InspectorScrollContentHeight(self, -y + 24)
            return
        end
    end
    if group.layout == "resource" then
        local style = YHUD:GetResourceGroupStyle(profile, group.id)
        self.textEditorTarget = nil
        local ui = self.resourceV2Text
        local resourceId, setting = EnsureResourceStyleSelection(self, profile)
        local override = setting and setting.textOverride
        local effective = override or style
        PlaceSection(ui.globalDivider, body, -4)
        ui.globalFont:SetTarget(YHUD.FontStyle:Key(group.id, "text"))
        Place(ui.globalFont, body, 0, -32, CONTENT_WIDTH)
        ui.globalFont:Show()
        PlaceSection(ui.itemDivider, body, -88)
        ShowControls({
            ui.resourceLabel, ui.resourceHelp, ui.resource,
            ui.overrideLabel, ui.override,
            ui.positionLabel, ui.position,
            ui.offsetXLabel, ui.offsetX, ui.offsetYLabel, ui.offsetY,
            ui.formatLabel, ui.format,
            ui.abbreviateLabel, ui.abbreviate,
        })
        PlaceResourceFieldWithHelp(
            ui.resourceLabel, ui.resourceHelp, ui.resource, body, 0, -116
        )
        PlaceResourceSwitch(
            ui.overrideLabel, ui.override, body, SECOND_COLUMN_X, -116
        )

        local definition = resourceId and ResourceCatalog
            and ResourceCatalog.GetDefinition
            and ResourceCatalog:GetDefinition(resourceId, profile, group.id) or nil
        local nextY = -176
        if override then
            ui.itemFont:SetTarget(YHUD.FontStyle:Key(group.id, "text", resourceId))
            Place(ui.itemFont, body, 0, nextY, CONTENT_WIDTH)
            ui.itemFont:Show()
            nextY = nextY - 44
        else
            ui.itemFont:Hide()
        end

        local numericText = definition and definition.valueKind == "continuous"
            and (not definition.provider or definition.provider.kind == "unit-power")
        if numericText then
            PlaceResourceSwitch(ui.abbreviateLabel, ui.abbreviate, body, 0, nextY)
            ui.abbreviate:SetValue(setting and setting.abbreviateValues == true, true)
            nextY = nextY - 60
        else
            HideControls({ ui.abbreviateLabel, ui.abbreviate })
        end
        for index = 1, 2 do
            local editor = index == 1 and ui or ui.second
            local text = index == 1 and setting or setting.text2
            PlaceSection(index == 1 and ui.text1Heading or editor.heading, body, nextY)
            nextY = nextY - 28
            ShowControls({ editor.formatLabel, editor.format })
            PlaceResourceField(editor.formatLabel, editor.format, body, 0, nextY)
            SetControlValue(editor.format, text.valueText == false and "none" or text.valueFormat)
            if text.valueText ~= false then
                ShowControls({ editor.positionLabel, editor.position, editor.offsetXLabel,
                    editor.offsetX, editor.offsetYLabel, editor.offsetY })
                PlaceResourceField(editor.positionLabel, editor.position, body, SECOND_COLUMN_X, nextY)
                SetControlValue(editor.position, text.textPosition)
                nextY = nextY - 60
                PlaceResourceField(editor.offsetXLabel, editor.offsetX, body, 0, nextY)
                PlaceResourceField(editor.offsetYLabel, editor.offsetY, body, SECOND_COLUMN_X, nextY)
                editor.offsetX:SetValue(text.textOffsetX, true)
                editor.offsetY:SetValue(text.textOffsetY, true)
            else
                HideControls({ editor.positionLabel, editor.position, editor.offsetXLabel,
                    editor.offsetX, editor.offsetYLabel, editor.offsetY })
            end
            nextY = nextY - 60
        end
        local secondText = setting.text2
        if setting.valueText and secondText.valueText
            and setting.textPosition == secondText.textPosition
            and setting.textOffsetX == secondText.textOffsetX and setting.textOffsetY == secondText.textOffsetY then
            Place(ui.overlap, body, 0, nextY, CONTENT_WIDTH)
            ui.overlap:Show()
            nextY = nextY - 40
        else ui.overlap:Hide() end

        SetControlValue(ui.resource, resourceId)
        ui.override:SetValue(override ~= nil, true)
        SetControlValue(ui.font, effective.textFont)
        SetControlValue(ui.outline, effective.textOutline)
        ui.size:SetValue(effective.textSize, true)
        SetControlValue(ui.color, effective.textColor)
        SetControlValue(ui.position, setting and setting.textPosition or "center")
        ui.offsetX:SetValue(setting and setting.textOffsetX or 0, true)
        ui.offsetY:SetValue(setting and setting.textOffsetY or 0, true)
        SetControlValue(
            ui.format,
            setting and setting.valueText == false
                and "none"
                or (setting and setting.valueFormat or "percent")
        )
        SetV2InspectorScrollContentHeight(self, -nextY + 24)
        return
    end

    local style = group.layout == "icons"
        and YHUD:GetIconGroupStyle(profile, group.id)
        or YHUD:GetDurationGroupStyle(profile, group.id)
    local durationLayout = group.layout ~= "icons"
        and YHUD:GetDurationGroupLayout(profile, group.id, group.layout)
        or nil
    local verticalNameUnavailable = group.layout == "bars"
        and durationLayout and durationLayout.orientation == "vertical"
    if verticalNameUnavailable and self.textEditorTarget == "name" then
        self.textEditorTarget = nil
        self.durationTextTarget = "cooldown"
        editing = false
    end
    if not editing then
        local targets = group.layout == "icons"
            and { "cooldown", "count", "keybind" }
            or { "cooldown", "name", "count" }
        local rowByTarget = {}
        for _, row in ipairs(self.textRows) do rowByTarget[row.target] = row end
        local nextY = -8
        for index = 1, #targets do
            local target = targets[index]
            local row = rowByTarget[target]
            local prefix = TextStylePrefix(group, target)
            if target == "keybind" then
                row.mode:SetValue(style.keybindTextMode, true)
            else
                row.switch:SetValue(style[prefix] == true, true)
            end
            local unavailable = target == "name"
                and verticalNameUnavailable == true
            SetDisabled(row.switch or row.mode, unavailable)
            SetDisabled(row.position, unavailable)
            SetDisabled(row.font, unavailable)
            row.position:SetValue(style[prefix .. (group.layout == "bars" and "Anchor" or "Position")], true)
            row.font:SetTarget(YHUD.FontStyle:Key(group.id, prefix))
            if row.settings then
                local manual = style.keybindTextMode == "manual"
                row.settings:SetShown(manual)
                row.mode:SetWidth(manual and 136 or 204)
            end
            local label = target == "cooldown"
                and group.layout ~= "icons"
                and T("designer.text_target.duration", "持续时间")
                or row.defaultLabel
            row.label:SetText(
                unavailable
                    and T(
                        "designer.text.name_vertical_unavailable",
                        "名称（纵向不可用）"
                    )
                    or label
            )
            Place(row, body, 0, nextY, CONTENT_WIDTH)
            nextY = nextY - row:GetHeight() - 12
            row:Show()
        end
        if group.layout ~= "icons" and not verticalNameUnavailable then
            ShowControls(self.durationNameControls)
            self.nameFormatInput:SetValue(style.nameTextFormat, true)
            PlaceResourceField(self.durationNameControls[1], self.nameFormatInput, body, 0, nextY)
            self.nameFormatInput:SetWidth(CONTENT_WIDTH)
            nextY = nextY - 64
        end
        SetV2InspectorScrollContentHeight(self, -nextY + 12)
        return
    end

    if self.textEditorTarget == "keybind" and group.layout == "icons" then
        self.durationTextTarget = "keybind"
        RefreshKeybindEditor(self, profile, group, style)
        return
    end


end

local function ShowMonitorGlobalSettings(self, profile, glowCapabilities, group)
    local collapsed = self.monitorGlobalCollapsed ~= false
    self.skillAuraGlobalDivider:Show()
    Place(self.skillAuraGlobalDivider, self.monitorInspectorBody, 0, -48)
    if self.skillAuraGlobalDivider.SetCollapsed then
        self.skillAuraGlobalDivider:SetCollapsed(collapsed, true)
    end
    SetShown(self.skillAuraGlobalPanel, not collapsed)
    if collapsed then return -86 end
    local showNativeGlow = not (group and group.layout == "rings")
    local panelHeight = MONITOR_GLOBAL_PANEL_HEIGHT - (showNativeGlow and 0 or 80)
    self.skillAuraGlobalPanel:SetHeight(panelHeight)
    SetShown(self.monitorGlobalNativeLabel, showNativeGlow)
    SetShown(self.monitorGlobalNativeDropdown, showNativeGlow)
    SetShown(self.monitorGlobalNativeGear, showNativeGlow)
    SetShown(self.monitorGlobalNativeCombatLabel, showNativeGlow)
    SetShown(self.monitorGlobalNativeCombat, showNativeGlow)
    Place(self.skillAuraGlobalPanel, self.monitorInspectorBody, 0, -76, CONTENT_WIDTH)
    for _, row in ipairs(self.monitorGlobalEffectRows or {}) do
        row.label:Show()
        row.count:Show()
        row.switch:Show()
        row.clear:Show()
        local enabled = not (profile and profile.cdm
            and profile.cdm[row.field] == false)
        row.switch:SetValue(enabled, true)
        if row.style then
            local styleValue = NativeGlowStyleValue(YHUD:GetAuraActivationStyle(profile))
            row.style:SetValue(styleValue, true)
            row.style:Show()
            row.gear:Show()
            SetDisabled(row.gear, styleValue == "default")
        end
        local count = Designer:CountMonitorStateEffectOverrides(row.key) or 0
        row.count:SetText(count > 0 and string.format(
            T("designer.monitor.override_count", "(%d)"), count
        ) or "")
        row.overrideCount = count
        row.clearDisabledTooltip.overrideCount = count
        row.clear:SetDisabled(count == 0)
        if row.clear.EnableMouse then row.clear:EnableMouse(false) end
        SetShown(row.clearDisabledTooltip, true)
    end
    local native = profile and profile.style
        and profile.style.nativeProcGlow or nil
    if self.monitorGlobalNativeDropdown.RefreshOptions then
        self.monitorGlobalNativeDropdown:RefreshOptions()
    end
    self.monitorGlobalNativeDropdown:SetValue(
        NativeGlowStyleValue(native),
        true
    )
    self.monitorGlobalNativeCombat:SetValue(
        native and native.combatOnly == true,
        true
    )
    SetDisabled(self.monitorGlobalNativeCombat, NativeGlowStyleValue(native) == "disabled")
    SetDisabled(
        self.monitorGlobalNativeGear,
        NativeGlowStyleValue(native) == "default"
            or NativeGlowStyleValue(native) == "disabled"
    )
    return -(76 + panelHeight + 14)
end

function I.PlaceMonitorSoundSettings(
    self,
    body,
    profile,
    monitor,
    capabilities
)
    self.monitorSoundTitle:Show()
    self.monitorSoundBack:Show()
    Place(self.monitorSoundTitle, body, 0, -4, CONTENT_WIDTH - 80)
    Place(self.monitorSoundBack, body, CONTENT_WIDTH - 68, -4, 68)

    self.monitorSoundRulesDivider:Show()
    self.monitorSoundRuleCount:Show()
    Place(
        self.monitorSoundRulesDivider,
        body,
        0,
        MONITOR_SOUND_UI.dividerY,
        CONTENT_WIDTH
    )
    Place(
        self.monitorSoundRuleCount,
        body,
        0,
        MONITOR_SOUND_UI.addRuleY - 6,
        56
    )
    local rules = type(monitor.sound) == "table"
        and type(monitor.sound.rules) == "table"
        and monitor.sound.rules or {}
    local ruleLimit = math.min(2, #(capabilities.conditions or {}))
    self.monitorSoundRuleCount:SetText(string.format(
        "%d/%d",
        #rules,
        ruleLimit
    ))
    self.monitorSoundAddRule:Hide()
    if #rules < ruleLimit then
        Place(
            self.monitorSoundAddRule,
            body,
            CONTENT_WIDTH - 104,
            MONITOR_SOUND_UI.addRuleY,
            104
        )
        self.monitorSoundAddRule:Show()
    end

    local y = MONITOR_SOUND_UI.firstRuleY
    for index = 1, #self.monitorSoundRules do
        local row = self.monitorSoundRules[index]
        local rule = rules[index]
        if rule then
            row.index = index
            if row.condition.RefreshOptions then
                row.condition:RefreshOptions()
            end
            row.condition:SetValue(
                rule.condition and rule.condition.type,
                true
            )
            row.sound:SetValue(rule.sound, true)
            local soundChoice = rule.sound and YUI.Sound
                and YUI.Sound.GetSoundChoice
                and YUI.Sound:GetSoundChoice(rule.sound) or nil
            SetDisabled(
                row.preview,
                rule.sound == nil
                    or soundChoice and soundChoice.available == false
            )
            Place(row, body, 0, y, CONTENT_WIDTH)
            row:Show()
            y = y - MONITOR_SOUND_UI.ruleHeight - MONITOR_SOUND_UI.ruleGap
        else
            row:Hide()
        end
    end
    SetV2InspectorScrollContentHeight(self, math.max(430, -y + 32))
end

function I.PlaceMonitorGlowSettings(
    self,
    body,
    profile,
    monitor,
    capabilities,
    y
)
    if not capabilities then return y end
    Place(self.monitorGlowDivider, body, 0, y - 4, CONTENT_WIDTH)
    self.monitorGlowDivider:Show()
    y = y - 40

    local entry = profile.entries and profile.entries[monitor.entryKey]
    if monitor.view == "icon" and YHUD:CanConfigureAssistedHighlight(entry) then
        self.monitorAssistedLabel:Show()
        self.monitorAssistedDropdown:Show()
        Place(self.monitorAssistedLabel, body, 0, y - 5, FIELD_LABEL_WIDTH)
        Place(self.monitorAssistedDropdown, body, FIELD_LABEL_WIDTH, y, FIELD_CONTROL_WIDTH)
        self.monitorAssistedDropdown:RefreshOptions()
        local override = monitor.stateEffects and monitor.stateEffects.assistedHighlight
        self.monitorAssistedDropdown:SetValue(override == true and "enabled"
            or override == false and "disabled" or "inherit", true)
        y = y - 42
    end

    if capabilities.nativeProc == true then
        local override = type(monitor.nativeProcGlowOverride) == "table"
            and monitor.nativeProcGlowOverride or nil
        local effective = YHUD:GetEffectiveNativeProcGlow(profile, monitor)
        self.monitorNativeLabel:Show()
        self.monitorNativeDropdown:Show()
        self.monitorNativeGear:Show()
        Place(self.monitorNativeLabel, body, 0, y - 5, FIELD_LABEL_WIDTH)
        Place(
            self.monitorNativeDropdown,
            body,
            FIELD_LABEL_WIDTH,
            y,
            FIELD_CONTROL_WIDTH - MONITOR_GLOW_GEAR_SIZE - 8
        )
        Place(
            self.monitorNativeGear,
            body,
            CONTENT_WIDTH - MONITOR_GLOW_GEAR_SIZE,
            y,
            MONITOR_GLOW_GEAR_SIZE
        )
        if self.monitorNativeDropdown.RefreshOptions then
            self.monitorNativeDropdown:RefreshOptions()
        end
        self.monitorNativeDropdown:SetValue(
            override and NativeGlowStyleValue(override) or "inherit",
            true
        )
        SetDisabled(
            self.monitorNativeGear,
            not override or NativeGlowStyleValue(override) == "default"
                or NativeGlowStyleValue(override) == "disabled"
        )
        y = y - 42
        self.monitorNativeCombatLabel:Show()
        self.monitorNativeCombat:Show()
        Place(self.monitorNativeCombatLabel, body, 0, y - 5)
        Place(
            self.monitorNativeCombat,
            body,
            CONTENT_WIDTH - 48,
            y,
            48
        )
        self.monitorNativeCombat:SetValue(
            (override or effective).combatOnly == true,
            true
        )
        SetDisabled(self.monitorNativeCombat,
            override == nil or NativeGlowStyleValue(override) == "disabled")
        y = y - 46
    end

    Place(self.monitorGlowRulesDivider, body, 0, y - 4, CONTENT_WIDTH)
    Place(
        self.monitorGlowRuleCount,
        body,
        CONTENT_WIDTH - 56,
        y - 5,
        56
    )
    self.monitorGlowRulesDivider:Show()
    self.monitorGlowRuleCount:Show()
    local rules = type(monitor.glow) == "table"
        and type(monitor.glow.rules) == "table"
        and monitor.glow.rules or {}
    local ruleLimit = YHUD:GetMonitorGlowRuleLimit(capabilities)
    self.monitorGlowRuleCount:SetText(string.format("%d/%d", #rules, ruleLimit))
    y = y - 40
    Place(self.monitorGlowPriorityText, body, 0, y, CONTENT_WIDTH)
    self.monitorGlowPriorityText:Show()
    y = y - 36
    local hasMissingRule = false
    for index = 1, #self.monitorGlowRules do
        local row = self.monitorGlowRules[index]
        local rule = rules[index]
        if rule then
            row.index = index
            row.title:SetText(string.format(
                T("designer.glow.rule_title", "Custom Glow Rule %d"),
                index
            ))
            if row.condition.RefreshOptions then row.condition:RefreshOptions() end
            local conditionType = rule.condition and rule.condition.type
            row.condition:SetValue(conditionType, true)
            local stacks = conditionType == "aura-stacks"
            row.stackMonitorId = monitor.id
            SetDisabled(row.up, index == 1)
            SetDisabled(row.down, index == #rules)
            row.color:SetValue(rule.appearance.color, true)
            SetDisabled(row.color, rule.appearance.style == "none")
            row.stackLabel:SetShown(stacks)
            row.stackOperator:SetShown(stacks)
            row.stackValue:SetShown(stacks)
            local rowHeight = MONITOR_GLOW_RULE_HEIGHT + (stacks and 36 or 0)
            row:SetHeight(rowHeight)
            if stacks then
                row.stackOperator:SetValue(rule.condition.operator, true)
                row.stackValue:SetText(tostring(rule.condition.value))
            end
            if row.style.RefreshOptions then row.style:RefreshOptions() end
            row.style:SetValue(
                rule.appearance and rule.appearance.style or "pixel",
                true
            )
            row.combat:SetValue(rule.combatOnly == true, true)
            Place(row, body, 0, y, CONTENT_WIDTH)
            row:Show()
            y = y - rowHeight - MONITOR_GLOW_RULE_GAP
            if conditionType == "aura-missing" then
                hasMissingRule = true
            end
        else
            row:Hide()
        end
    end

    if hasMissingRule and monitor.visibilityMode ~= "always" then
        Place(self.monitorGlowAuraWarning, body, 0, y, CONTENT_WIDTH)
        self.monitorGlowAuraWarning:Show()
        y = y - 46 - MONITOR_GLOW_RULE_GAP
    end
    self.monitorGlowAddRule:Hide()
    local canAddRule = false
    if #rules < ruleLimit then
        for index = 1, #(capabilities.conditions or {}) do
            if YHUD:CanAddGlowCondition(rules, capabilities.conditions[index]) then
                canAddRule = true
                break
            end
        end
    end
    if canAddRule then
        Place(self.monitorGlowAddRule, body, 0, y, CONTENT_WIDTH)
        self.monitorGlowAddRule:Show()
        y = y - 40
    end
    return y
end

local function PlacePresetDetails(self, panel, entry, monitor, editable)
    local extra = YHUD.ClassExtra
    local description = extra and extra:Description(entry)
    if not description then return 112 end
    if not self.classExtraDescription then
        self.classExtraDescription = GUI2:CreateText(panel, "", "font.size.md", "color.text.secondary", "LEFT")
        self.classExtraDescription:SetWordWrap(true)
        self.classExtraParameters = GUI2:CreateText(panel, T("designer.extra.parameters"),
            "font.size.md", "color.text.heading", "LEFT")
    end
    local text = self.classExtraDescription
    local top = self.monitorBrowser.identityWarning:IsShown() and 112 or 88
    text:SetText(description)
    Place(text, panel, 12, -top, CONTENT_WIDTH - 24)
    text:SetHeight(0)
    local height = math.max(20, math.ceil(text:GetStringHeight()))
    text:SetHeight(height)
    text:Show()
    local y = top + height + 14
    if entry.presetId == "devourer-transform" then
        Place(self.classExtraParameters, panel, 12, -y, CONTENT_WIDTH - 24)
        self.classExtraParameters:Show()
        y = y + 30
        local labelWidth = math.min(168, math.floor((CONTENT_WIDTH - 24) * 0.48))
        local controlWidth = CONTENT_WIDTH - 24 - labelWidth
        if not self.classExtraSettings then
            self.classExtraSettings = {}
            for _, definition in ipairs({ { "alertSecond", 1, 90 }, { "endedHideDelay", 0, 30 } }) do
                local field = definition[1]
                local row = { label = GUI2:CreateText(panel, T("designer.extra." .. field),
                    "font.size.md", "color.text.primary", "LEFT") }
                row.control = GUI2.Form:CreateSlider(panel, {
                    width = controlWidth, inline = true, inputWidth = 56,
                    min = definition[2], max = definition[3], step = 1, precision = 0,
                    set = function(value)
                        local id = self.classExtraMonitorId
                        if not id or self.v2Refreshing then return end
                        if Designer:SetClassExtraSettings(id, { [field] = value }) then
                            if DesignerUI:PreviewSelectedGroup() then
                                DesignerUI.v2SliderPreviewDirty = true
                            else
                                DesignerUI:ApplyPreview()
                            end
                            local profile = Designer:GetProfile()
                            local selected = profile and profile.monitors[id]
                            local current = selected and profile.entries[selected.entryKey]
                            self.classExtraDescription:SetText(extra:Description(current) or "")
                        end
                    end,
                    onCommit = function() DesignerUI:CommitV2SliderPreview() end,
                })
                self.classExtraSettings[#self.classExtraSettings + 1] = row
            end
        end
        self.classExtraMonitorId = monitor.id
        local alert, delay, progress = extra:Settings(entry)
        for index, row in ipairs(self.classExtraSettings) do
            Place(row.label, panel, 12, -y - 6, labelWidth - 8)
            Place(row.control, panel, 12 + labelWidth, -y, controlWidth)
            row.control:SetValue(index == 1 and alert or delay, true)
            SetDisabled(row.control, not editable)
            row.label:Show()
            row.control:Show()
            y = y + 36
        end
        if monitor.view == "icon" then
            if not self.classExtraProgressSwitch then
                self.classExtraProgressLabel = GUI2:CreateText(panel, T("designer.extra.showIconProgress"),
                    "font.size.md", "color.text.primary", "LEFT")
                self.classExtraProgressSwitch = GUI2.Form:CreateSwitch(panel, {
                    width = 72, set = function(value)
                        local id = self.classExtraMonitorId
                        if not id or self.v2Refreshing then return end
                        if Designer:SetClassExtraSettings(id, { showIconProgress = value }) then DesignerUI:ApplyPreview() end
                    end,
                })
            end
            Place(self.classExtraProgressLabel, panel, 12, -y - 6, CONTENT_WIDTH - 108)
            Place(self.classExtraProgressSwitch, panel, CONTENT_WIDTH - 84, -y, 72)
            self.classExtraProgressSwitch:SetValue(progress, true)
            SetDisabled(self.classExtraProgressSwitch, not editable)
            self.classExtraProgressLabel:Show()
            self.classExtraProgressSwitch:Show()
            y = y + 36
        end
    elseif entry.presetId == "brewmaster-elixir" then
        if not self.classExtraReadyDropdown then
            self.classExtraReadyLabel = GUI2:CreateText(panel, T("designer.extra.readyVisibility"),
                "font.size.md", "color.text.primary", "LEFT")
            self.classExtraReadyDropdown = GUI2.Form:CreateDropdown(panel, {
                width = CONTENT_WIDTH - 24, height = 30,
                options = function()
                    return {
                        { value = "group", text = T("designer.extra.readyVisibility.group") },
                        { value = "combat", text = T("designer.extra.readyVisibility.combat") },
                        { value = "instance", text = T("designer.extra.readyVisibility.instance") },
                    }
                end,
                set = function(value)
                    local id = self.classExtraMonitorId
                    if not id or self.v2Refreshing then return end
                    if Designer:SetClassExtraSettings(id, { readyVisibility = value }) then DesignerUI:ApplyPreview() end
                end,
            })
        end
        self.classExtraMonitorId = monitor.id
        local _, _, _, ready = extra:Settings(entry)
        Place(self.classExtraReadyLabel, panel, 12, -y, CONTENT_WIDTH - 24)
        Place(self.classExtraReadyDropdown, panel, 12, -y - 26, CONTENT_WIDTH - 24)
        self.classExtraReadyDropdown:SetValue(ready, true)
        SetDisabled(self.classExtraReadyDropdown, not editable)
        self.classExtraReadyLabel:Show()
        self.classExtraReadyDropdown:Show()
        y = y + 68
    end
    return y + 8
end
I.PlacePresetDetails = PlacePresetDetails

local function PlaceMonitorAppearanceOverride(
    self,
    body,
    profile,
    group,
    monitor,
    top
)
    if not monitor or (group.layout ~= "bars" and group.layout ~= "rings") then
        return top
    end
    local override = type(monitor.appearanceOverride) == "table"
        and monitor.appearanceOverride or nil
    local style = YHUD:GetDurationGroupStyle(profile, group.id)
    local effective = override or style
    Place(self.monitorAppearanceDivider, body, 0, -top, CONTENT_WIDTH)
    Place(self.monitorAppearanceFillLabel, body, 0, -top - 35, FIELD_LABEL_WIDTH)
    Place(
        self.monitorAppearanceTrackLabel,
        body,
        SECOND_COLUMN_X,
        -top - 35,
        FIELD_LABEL_WIDTH
    )
    Place(
        self.monitorAppearanceFill,
        body,
        FIELD_LABEL_WIDTH + 8,
        -top - 30,
        COLUMN_WIDTH - FIELD_LABEL_WIDTH - 8
    )
    Place(
        self.monitorAppearanceTrack,
        body,
        SECOND_COLUMN_X + FIELD_LABEL_WIDTH + 8,
        -top - 30,
        COLUMN_WIDTH - FIELD_LABEL_WIDTH - 8
    )
    self.monitorAppearanceDivider:Show()
    self.monitorAppearanceFillLabel:Show()
    self.monitorAppearanceFill:Show()
    self.monitorAppearanceTrackLabel:Show()
    self.monitorAppearanceTrack:Show()
    self.monitorResetAppearance:Show()
    self.monitorAppearanceFill:SetValue(effective.fillColor or style.fillColor, true)
    self.monitorAppearanceTrack:SetValue(
        effective.trackColor or effective.ringTrackColor or style.trackColor or style.ringTrackColor,
        true
    )
    self.monitorResetAppearance:SetDisabled(override == nil
        or not (override.fillColor or override.trackColor or override.stackThresholds or override.rechargeColor))
    local actionTop = top + 66
    if group.layout == "bars" and I.PlaceBarRechargeAppearanceUI then
        actionTop = I.PlaceBarRechargeAppearanceUI(self, monitor, style, actionTop, CONTENT_WIDTH)
    end
    Place(self.monitorResetAppearance, body, SECOND_COLUMN_X + FIELD_LABEL_WIDTH + 8,
        -actionTop, COLUMN_WIDTH - FIELD_LABEL_WIDTH - 8)
    local nextTop = actionTop + 34
    local entry = profile.entries[monitor.entryKey]
    local ui = self.monitorStackThresholdUI
    if ui and YHUD:CanUseBarStackThresholds(entry, monitor) then
        local policy = YHUD:NormalizeBarStackThresholds(override and override.stackThresholds)
        ui.label:Show()
        ui.enabled:Show()
        Place(ui.label, body, 0, -actionTop - 5, FIELD_LABEL_WIDTH)
        Place(ui.enabled, body, FIELD_LABEL_WIDTH + 8, -actionTop, COLUMN_WIDTH - FIELD_LABEL_WIDTH - 8)
        ui.enabled:SetValue(policy.enabled, true)
        local basis, unit, warning = I.GetBarThresholdInfo(entry, monitor, policy)
        ui.info:SetText(basis .. (warning and ("\n" .. warning) or ""))
        ui.info:Show()
        Place(ui.info, body, 0, -nextTop, CONTENT_WIDTH)
        local infoHeight = math.max(22, math.ceil(ui.info:GetStringHeight()))
        ui.info:SetHeight(infoHeight)
        nextTop = nextTop + infoHeight + 4
        if policy.enabled then
            for _, key in ipairs({ "low", "high" }) do
                local row = ui.rows[key]
                row.label:SetText(unit .. (key == "low" and " ≤" or " ≥"))
                row.label:Show()
                row.enabled:Show()
                row.value:Show()
                row.color:Show()
                Place(row.label, body, 0, -nextTop - 5, 128)
                Place(row.enabled, body, 136, -nextTop, SWITCH_WIDTH)
                Place(row.value, body, 190, -nextTop, CONTENT_WIDTH - 246)
                Place(row.color, body, CONTENT_WIDTH - 44, -nextTop, 44)
                row.enabled:SetValue(policy[key].enabled, true)
                row.value:SetValue(policy[key].value, true)
                row.color:SetValue(policy[key].color, true)
                SetDisabled(row.value, not policy[key].enabled)
                SetDisabled(row.color, not policy[key].enabled)
                nextTop = nextTop + 32
            end
        end
    end
    return nextTop + 6
end

local function PlaceMonitorMaintenance(self, body, contentBottom)
    local session = Designer:GetSession()
    local canRestore = session
        and YHUD.DEFAULT_CATEGORY_BY_GROUP[session.selectedGroupId] ~= nil
    if not canRestore then return contentBottom end
    if self.commonMaintenance.SetParent then
        self.commonMaintenance:SetParent(body)
    end
    if self.restoreButton.SetParent then
        self.restoreButton:SetParent(self.commonMaintenance)
    end
    self.commonMaintenanceLabel:Show()
    self.commonMaintenance:Show()
    self.deleteGroupButton:Hide()
    self.restoreButton:Show()
    self.restoreButton:ClearAllPoints()
    self.restoreButton:SetPoint(
        "RIGHT",
        self.commonMaintenance,
        "RIGHT",
        -8,
        0
    )
    self.restoreButton:SetWidth(150)
    self.commonMaintenanceLabel:ClearAllPoints()
    self.commonMaintenanceLabel:SetPoint("LEFT", self.commonMaintenance, "LEFT", 14, 0)
    self.commonMaintenanceLabel:SetPoint("RIGHT", self.restoreButton, "LEFT", -8, 0)
    local viewportHeight = self.inspectorScroll:GetHeight() or 0
    local top = math.max(contentBottom + MONITOR_PANEL_GAP, viewportHeight - 50)
    Place(self.commonMaintenance, body, 0, -top, CONTENT_WIDTH)
    return top + 50
end

local function PlaceMonitorHeaderActions(self, body, group)
    local capabilities = YHUD:GetGroupAddCapabilities(group)
    local cooldown = capabilities and capabilities.cooldown
    local aura = capabilities and capabilities.buff
    local actionCount = (cooldown and 1 or 0) + (aura and 1 or 0)
    local actionWidth = actionCount * MONITOR_HEADER_ACTION_WIDTH
        + math.max(actionCount - 1, 0) * MONITOR_HEADER_ACTION_GAP
    local summary = self.monitorBrowser and self.monitorBrowser.summary
    if summary then
        summary:SetWidth(math.max(96, CONTENT_WIDTH - actionWidth
            - (actionCount > 0 and 12 or 0)))
    end
    if cooldown then
        if self.addMonitorButton.SetParent then
            self.addMonitorButton:SetParent(body)
        end
        self.addMonitorButton:Show()
        self.addMonitorButton:SetWidth(MONITOR_HEADER_ACTION_WIDTH)
        self.addMonitorButton:SetHeight(MONITOR_HEADER_ACTION_HEIGHT)
        self.addMonitorButton:ClearAllPoints()
        self.addMonitorButton:SetPoint(
            "TOPRIGHT",
            body,
            "TOPRIGHT",
            aura and -(MONITOR_HEADER_ACTION_WIDTH + MONITOR_HEADER_ACTION_GAP) or 0,
            -4
        )
    end
    if aura then
        if self.addBuffButton.SetParent then self.addBuffButton:SetParent(body) end
        self.addBuffButton:Show()
        self.addBuffButton:SetWidth(MONITOR_HEADER_ACTION_WIDTH)
        self.addBuffButton:SetHeight(MONITOR_HEADER_ACTION_HEIGHT)
        self.addBuffButton:ClearAllPoints()
        self.addBuffButton:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -4)
    end
end

local function RefreshMonitorPage(self, group, monitor)
    if group.layout == "resource" then
        return I.RefreshResourceMonitorPage(self, Designer:GetProfile(), group)
    end
    local body = self.monitorInspectorBody
    body:Show()
    HideMonitorDetailVariants(self)
    local session = Designer:GetSession()
    local profile = session and session.staticPreview == true
        and Designer:GetPresentationProfile() or Designer:GetProfile()
    if not monitor and group.monitors and group.monitors[1] then
        local firstVisible
        for index = 1, #group.monitors do
            local monitorId = group.monitors[index]
            local candidate = profile.monitors[monitorId]
            local candidateEntry = candidate and profile.entries
                and profile.entries[candidate.entryKey]
            if candidate
                and not DesignerUI:IsMonitorListEntryHidden(
                    profile,
                    candidateEntry
                ) then
                firstVisible = monitorId
                break
            end
        end
        if firstVisible then
            Designer:SelectMonitor(firstVisible)
            return self:Refresh(false, false)
        end
    end

    local entry = monitor and profile and profile.entries
        and profile.entries[monitor.entryKey]
    local monitorEditable = monitor
        and Designer:GetMonitorAccess(monitor.id) == true or false
    local supportsAura = entry and YHUD:CanConfigureSkillAuraDisplay(entry)
    local supportsPersistent = entry and YHUD:SupportsPersistentDisplay(entry)
    local supportsEffects = entry and YHUD:CanConfigureMonitorStateEffects(entry)
    local supportsSwipe = group.layout == "icons"
    local supportsAppearance = monitorEditable and (group.layout == "bars"
        or group.layout == "rings")
    local glowCapabilities = monitor
        and YHUD:GetMonitorGlowCapabilities(profile, monitor) or nil
    -- Independent reminders are edited through the global sound center.
    local soundCapabilities = nil
    local supportsSettings = monitorEditable and (supportsEffects
        or supportsSwipe or glowCapabilities ~= nil)
    if not monitorEditable then
        self.monitorEffectsEditing = false
        self.monitorSoundEditing = false
        soundCapabilities = nil
    end

    if self.monitorSoundEditing and soundCapabilities then
        self:CancelMonitorIdentityEdit(true)
        I.PlaceMonitorSoundSettings(
            self,
            body,
            profile,
            monitor,
            soundCapabilities
        )
        return
    end
    if self.monitorSoundEditing then self.monitorSoundEditing = false end

    if self.monitorEffectsEditing and supportsSettings then
        self:CancelMonitorIdentityEdit(true)
        self.monitorEffectsTitle:Show()
        self.monitorEffectsBack:Show()
        Place(self.monitorEffectsTitle, body, 0, -4, CONTENT_WIDTH - 80)
        Place(self.monitorEffectsBack, body, CONTENT_WIDTH - 68, -4, 68)
        local selectedTop = ShowMonitorGlobalSettings(self, profile, glowCapabilities, group)

        self.monitorSelectedEffectsDivider:Show()
        Place(
            self.monitorSelectedEffectsDivider,
            body,
            0,
            selectedTop,
            CONTENT_WIDTH
        )
        if self.monitorSelectedEffectsDivider.gui2DividerText then
            self.monitorSelectedEffectsDivider.gui2DividerText:SetText(
                MonitorName(profile, monitor)
            )
        end
        if self.monitorSelectedEffectsDivider.gui2LeadingIcon then
            GUI2:SetIconTexture(
                self.monitorSelectedEffectsDivider.gui2LeadingIcon,
                EntryIcon(entry),
                QUESTION_ICON
            )
        end

        local effects = type(monitor.stateEffects) == "table"
            and monitor.stateEffects or {}
        local appearance = type(monitor.appearanceOverride) == "table"
            and monitor.appearanceOverride or {}
        local y = selectedTop - 36
        local function PlaceEffect(label, control)
            label:Show()
            control:Show()
            Place(label, body, 0, y - 6, FIELD_LABEL_WIDTH)
            Place(control, body, FIELD_LABEL_WIDTH, y, FIELD_CONTROL_WIDTH)
            y = y - 44
        end
        if supportsEffects then
            if supportsPersistent then
                local projectionStrategy, projectionReason
                if YHUD.GetFilteredAuraProjectionStrategy then
                    projectionStrategy, projectionReason =
                        YHUD:GetFilteredAuraProjectionStrategy(profile, monitor)
                end
                local mixedFixed = projectionStrategy ==
                    YHUD.FILTERED_AURA_LAYOUT_MIXED_FIXED
                PlaceEffect(self.monitorVisibilityLabel, self.monitorVisibilityDropdown)
                self.monitorVisibilityDropdown:SetWidth(
                    mixedFixed and FIELD_CONTROL_WIDTH - 34
                        or FIELD_CONTROL_WIDTH
                )
                SetDisabled(self.monitorVisibilityDropdown, false)
                self.monitorVisibilityDropdown:SetValue(
                    monitor.visibilityMode == "always" and "always" or "active",
                    true
                )
                self.monitorVisibilityLayoutInfo.yhudProjectionReason =
                    projectionReason
                if mixedFixed then
                    self.monitorVisibilityLayoutInfo:ClearAllPoints()
                    self.monitorVisibilityLayoutInfo:SetPoint(
                        "LEFT",
                        self.monitorVisibilityDropdown,
                        "RIGHT",
                        8,
                        0
                    )
                    self.monitorVisibilityLayoutInfo:Show()
                end
            end
            if supportsAura then
                PlaceEffect(self.skillAuraOverrideLabel, self.skillAuraOverrideDropdown)
                if self.skillAuraOverrideDropdown.RefreshOptions then
                    self.skillAuraOverrideDropdown:RefreshOptions()
                end
                self.skillAuraOverrideDropdown:SetValue(
                    effects.auraTimer == nil and "inherit"
                        or (effects.auraTimer and "enabled" or "disabled"),
                    true
                )
                PlaceEffect(
                    self.monitorAuraHighlightLabel,
                    self.monitorAuraHighlightDropdown
                )
                if self.monitorAuraHighlightDropdown.RefreshOptions then
                    self.monitorAuraHighlightDropdown:RefreshOptions()
                end
                self.monitorAuraHighlightDropdown:SetValue(
                    effects.auraHighlight == nil and "inherit"
                        or (effects.auraHighlight and "enabled" or "disabled"),
                    true
                )
            end
            PlaceEffect(
                self.monitorInactiveDesaturateLabel,
                self.monitorInactiveDesaturateDropdown
            )
            if self.monitorInactiveDesaturateDropdown.RefreshOptions then
                self.monitorInactiveDesaturateDropdown:RefreshOptions()
            end
            self.monitorInactiveDesaturateDropdown:SetValue(
                effects.inactiveDesaturate == nil and "inherit"
                    or (effects.inactiveDesaturate and "enabled" or "disabled"),
                true
            )
        end
        if supportsSwipe then
            PlaceEffect(
                self.monitorAppearanceSwipeLabel,
                self.monitorAppearanceSwipe
            )
            if self.monitorAppearanceSwipe.RefreshOptions then
                self.monitorAppearanceSwipe:RefreshOptions()
            end
            self.monitorAppearanceSwipe:SetValue(
                appearance.cooldownSwipeMode or "inherit",
                true
            )
        end
        self.monitorResetIncludesSwipe = supportsSwipe
        if supportsEffects or supportsSwipe then
            Place(self.monitorResetEffects, body, 0, y - 4, CONTENT_WIDTH)
            self.monitorResetEffects:SetDisabled(
                next(effects) == nil
                    and not (supportsSwipe and appearance.cooldownSwipeMode)
            )
            self.monitorResetEffects:Show()
            y = y - 52
        end
        y = I.PlaceMonitorGlowSettings(
            self,
            body,
            profile,
            monitor,
            glowCapabilities,
            y
        )
        SetV2InspectorScrollContentHeight(self, math.max(430, -y + 48))
        return
    end
    if self.monitorEffectsEditing then self.monitorEffectsEditing = false end

    self.monitorBrowser.detailPanel:SetHeight(MONITOR_DETAIL_PANEL_HEIGHT)
    self.monitorBrowser:SetHeight(MONITOR_LIST_PANEL_HEIGHT + MONITOR_PANEL_GAP + MONITOR_DETAIL_PANEL_HEIGHT)
    self.monitorBrowser:Show()
    self.monitorBrowser.summary:ClearAllPoints()
    self.monitorBrowser.summary:SetPoint(
        "TOPLEFT", body, "TOPLEFT", 0, -7
    )
    self.monitorBrowser.summary:SetHeight(36)
    self:RefreshMonitorBrowser()
    PlaceMonitorHeaderActions(self, body, group)
    self.monitorContentBottom = 44
        + (self.monitorBrowser.previewStatusOffset or 0)
        + MONITOR_LIST_PANEL_HEIGHT
        + MONITOR_PANEL_GAP
        + MONITOR_DETAIL_PANEL_HEIGHT

    if not monitor then
        self.monitorContentBottom = PlaceMonitorMaintenance(
            self,
            body,
            self.monitorContentBottom
        )
        SetV2InspectorScrollContentHeight(self, self.monitorContentBottom)
        return
    end

    local detailPanel = self.monitorBrowser.detailPanel
    local bundleKind = entry and entry.bundleKind
    if not bundleKind and entry and entry.sourceType == "racial-bundle" then
        bundleKind = "racial"
    end
    for _, control in ipairs({
        self.monitorEffectsButton,
        self.monitorSoundButton,
        self.monitorReplicationButton,
        self.monitorGroupDropdown,
        self.removeMonitorButton,
        self.monitorGroupLabel,
        self.moveUpButton,
        self.moveDownButton,
    }) do
        if control.SetParent then control:SetParent(detailPanel) end
        if control.SetFrameLevel and detailPanel.GetFrameLevel then
            control:SetFrameLevel(detailPanel:GetFrameLevel() + 2)
        end
    end

    local actionTop = PlacePresetDetails(self, detailPanel, entry, monitor, monitorEditable)
    local detailHeight = math.max(MONITOR_DETAIL_PANEL_HEIGHT, actionTop + 40)
    detailPanel:SetHeight(detailHeight)
    self.monitorBrowser:SetHeight(MONITOR_LIST_PANEL_HEIGHT + MONITOR_PANEL_GAP + detailHeight)
    self.monitorContentBottom = self.monitorContentBottom + detailHeight - MONITOR_DETAIL_PANEL_HEIGHT
    local actionY = -actionTop
    self.monitorHeading:Hide()
    self.removeMonitorButton:Show()
    Place(
        self.removeMonitorButton,
        detailPanel,
        MONITOR_DETAIL_HORIZONTAL_PADDING,
        actionY,
        MONITOR_REMOVE_ACTION_WIDTH
    )
    self.removeMonitorButton:SetHeight(MONITOR_SIDE_CONTROL_HEIGHT)
    self.removeMonitorButton:SetDisabled(not monitorEditable)

    local reorderX = MONITOR_DETAIL_HORIZONTAL_PADDING
        + MONITOR_REMOVE_ACTION_WIDTH
        + MONITOR_DETAIL_ACTION_GAP
    self.moveUpButton:Show()
    Place(
        self.moveUpButton,
        detailPanel,
        reorderX,
        actionY,
        MONITOR_REORDER_ACTION_WIDTH
    )
    self.moveUpButton:SetHeight(MONITOR_SIDE_CONTROL_HEIGHT)
    self.moveDownButton:Show()
    Place(
        self.moveDownButton,
        detailPanel,
        reorderX + MONITOR_REORDER_ACTION_WIDTH
            + MONITOR_REORDER_ACTION_GAP,
        actionY,
        MONITOR_REORDER_ACTION_WIDTH
    )
    self.moveDownButton:SetHeight(MONITOR_SIDE_CONTROL_HEIGHT)
    local specialState = YHUD.GetSpecialMonitorGroupState
        and YHUD:GetSpecialMonitorGroupState(profile, group, true)
    self.v2SpecialOverflowState = specialState
    self.v2SpecialOverflowGroupId = group.id
    self.moveUpButton:SetDisabled(not monitorEditable
        or ResolveV2ReorderOperation(
            profile,
            group,
            monitor,
            -1,
            specialState
        ) == nil)
    self.moveDownButton:SetDisabled(not monitorEditable
        or ResolveV2ReorderOperation(
            profile,
            group,
            monitor,
            1,
            specialState
        ) == nil)

    self.monitorGroupLabel:SetText(T("designer.monitor.move_to", "分组："))
    self.monitorGroupDropdown:SetValue(monitor.groupId, { silent = true, force = true })
    self.monitorGroupDropdown:Show()
    SetDisabled(self.monitorGroupDropdown, not monitorEditable)
    self.monitorGroupLabel:Show()
    local dropdownX = reorderX
        + (MONITOR_REORDER_ACTION_WIDTH * 2)
        + MONITOR_REORDER_ACTION_GAP
        + MONITOR_DETAIL_ACTION_GAP
        + MONITOR_MOVE_LABEL_WIDTH
        + MONITOR_MOVE_LABEL_GAP
    Place(
        self.monitorGroupDropdown,
        detailPanel,
        dropdownX,
        actionY,
        MONITOR_MOVE_ACTION_WIDTH
    )
    self.monitorGroupLabel:ClearAllPoints()
    self.monitorGroupLabel:SetPoint(
        "RIGHT",
        self.monitorGroupDropdown,
        "LEFT",
        -MONITOR_MOVE_LABEL_GAP,
        0
    )
    self.monitorGroupLabel:SetWidth(MONITOR_MOVE_LABEL_WIDTH)
    if self.monitorGroupLabel.SetWordWrap then
        self.monitorGroupLabel:SetWordWrap(false)
    end
    if self.monitorGroupLabel.SetJustifyH then
        self.monitorGroupLabel:SetJustifyH("RIGHT")
    end

    local session = Designer:GetSession()
    local canReplicate = false
    if entry and entry.origin ~= "official-cdm" and session then
        canReplicate = YHUD:CanCrossSpecOperate(
            "copy",
            entry,
            session.runtimeSpecKey,
            session.viewSpecKey
        ) == true
    end
    SetShown(self.monitorEffectsButton, supportsSettings)
    SetShown(self.monitorSoundButton, soundCapabilities ~= nil)
    SetShown(self.monitorReplicationButton, canReplicate)
    if supportsSettings or soundCapabilities or canReplicate then
        local actionX = CONTENT_WIDTH
            - MONITOR_DETAIL_HORIZONTAL_PADDING
            - MONITOR_EFFECTS_ACTION_WIDTH
        local actionIndex = 0
        local function PlaceAction(control, shown)
            if not shown then return end
            Place(
                control,
                detailPanel,
                actionX,
                -14 - (actionIndex * (
                    MONITOR_SOUND_UI.actionHeight
                    + MONITOR_SOUND_UI.actionGap
                )),
                MONITOR_EFFECTS_ACTION_WIDTH
            )
            control:SetHeight(MONITOR_SOUND_UI.actionHeight)
            actionIndex = actionIndex + 1
        end
        PlaceAction(self.monitorEffectsButton, supportsSettings)
        PlaceAction(self.monitorSoundButton, soundCapabilities ~= nil)
        PlaceAction(self.monitorReplicationButton, canReplicate)
    end

    local contentBottom = self.monitorContentBottom
    if I.PlaceBarProgressUI then
        contentBottom = I.PlaceBarProgressUI(self, group, monitor, contentBottom + 12, CONTENT_WIDTH)
    end
    if supportsAppearance then
        contentBottom = PlaceMonitorAppearanceOverride(
            self,
            body,
            profile,
            group,
            monitor,
            contentBottom + 12
        )
    end
    if self.monitorGlowButton:IsShown() then
        local glowTop = contentBottom + 12
        Place(self.monitorGlowButton, body, 0, -glowTop, CONTENT_WIDTH)
        contentBottom = glowTop + 38
    end
    if bundleKind == EQUIPMENT_AURA_BUNDLE_KIND then
        local projection = Designer:GetEquipmentTriggerProjection() or {}
        local passiveState = {}
        local activeIssueBySlot = {}
        for index = 1, #projection do
            local record = projection[index]
            local slot = tonumber(record.equipSlot)
            if slot == 13 or slot == 14 then
                if record.kind == "missing-active-timer" then
                    activeIssueBySlot[slot] = true
                elseif record.kind == "missing-official-config" then
                    local priority = record.reason == "not-configured" and 2
                        or 1
                    local previous = passiveState[slot]
                    if not previous or priority > previous.priority then
                        passiveState[slot] = {
                            priority = priority,
                            reason = record.reason,
                        }
                    end
                end
            end
        end
        local messages = {}
        if #projection == 0 then
            local itemAPI = YUI.API and YUI.API.Item
            local equipped = itemAPI and itemAPI.GetInventoryItemID
                and (itemAPI.GetInventoryItemID("player", 13)
                    or itemAPI.GetInventoryItemID("player", 14))
            messages[1] = equipped and T(
                "designer.equipment_trigger.no_effect",
                "当前饰品没有可识别的增益效果；装备可监控的饰品后自动显示。"
            ) or T(
                "designer.equipment_trigger.empty_slots",
                "尚未装备饰品；装备可监控的饰品后自动显示增益图标。"
            )
        end
        for slot = 13, 14 do
            local displaySlot = slot - 12
            if activeIssueBySlot[slot] then
                messages[#messages + 1] = string.format(T(
                    "designer.equipment_trigger.active_duration_unavailable",
                    "饰品栏 %d 无法解析主动效果持续时间，暂时无法建立主动计时。"
                ), displaySlot)
            end
            local state = passiveState[slot]
            if state then
                if state.reason == "not-configured" then
                    messages[#messages + 1] = string.format(T(
                        "designer.equipment_trigger.not_configured",
                        "饰品栏 %d 的增益尚未加入暴雪‘追踪的增益效果’，被动触发暂时无法显示。"
                    ), displaySlot)
                else
                    messages[#messages + 1] = string.format(T(
                        "designer.equipment_trigger.unavailable",
                        "饰品栏 %d 的暴雪被动增益当前不可用，暂时无法监控。"
                    ), displaySlot)
                end
            end
        end
        if #messages > 0 and self.equipmentTriggerNotice then
            local noticeTop = contentBottom + 12
            self.equipmentTriggerNotice.text:SetText(
                table.concat(messages, "\n")
            )
            self.equipmentTriggerNotice:SetHeight(#projection > 0 and 148 or 96)
            Place(
                self.equipmentTriggerNotice,
                body,
                0,
                -noticeTop,
                CONTENT_WIDTH
            )
            self.equipmentTriggerNotice:Show()
            self.equipmentTriggerNotice.action:SetShown(#projection > 0)
            contentBottom = noticeTop + (#projection > 0 and 148 or 96)
        end
    elseif bundleKind then
        local _, options = Designer:GetSpellBundleOptions(bundleKind)
        local editor = self.bundleEditor or self.racialEditor
        local bundleTop = contentBottom + 12
        editor:ClearAllPoints()
        editor:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -bundleTop)
        editor.bundleKind = bundleKind
        local _, selectedContext = Designer:GetSpellBundleContexts(bundleKind)
        local rowTop = bundleKind == "externalBuff" and 164 or 48
        local externalLimit = bundleKind == "externalBuff"
            and YHUD.MonitorCatalog:GetExternalBuffLimit(entry) or 0
        if bundleKind == "externalBuff" then
            if not editor.externalHelp then
                editor.externalHelp = GUI2:CreateText(editor, "", "font.size.sm", "color.text.secondary", "LEFT")
                editor.externalHelp:SetPoint("TOPLEFT", 10, -10)
                editor.externalHelp:SetWidth(CONTENT_WIDTH - 20)
                editor.externalHelp:SetHeight(32)
                editor.externalHelp:SetWordWrap(true)
                editor.externalMembers = GUI2:CreateText(editor, "", "font.size.md", "color.text.primary", "LEFT")
                editor.externalMembers:SetPoint("TOPLEFT", 10, -138)
                editor.externalMembers:SetWidth(CONTENT_WIDTH - 20)
                editor.externalLimit = GUI2.Form:CreateDropdown(editor, {
                    width = CONTENT_WIDTH - 20, inline = true,
                    label = T("designer.external_buffs.max_display", "最大显示数量"),
                    labelWidth = FIELD_LABEL_WIDTH,
                    options = function()
                        local values = {{ value = 0, text = T("designer.external_buffs.unlimited", "不限") }}
                        for count = 1, #(YUI.HelpfulBuffs and YUI.HelpfulBuffs.entries or {}) do
                            values[#values + 1] = { value = count, text = tostring(count) }
                        end
                        return values
                    end,
                    set = function(value)
                        if DesignerUI.v2Refreshing then return end
                        local ok, code = Designer:SetExternalBuffLimit(value)
                        if ok then
                            DesignerUI:ApplyPreview()
                            DesignerUI:Refresh(false, false)
                        else
                            DesignerUI:SetMutationError(code, "designer.error_update", "无法修改监控。")
                        end
                    end,
                })
                editor.externalLimit:SetPoint("TOPLEFT", 10, -46)
                editor.externalLimitHint = GUI2:CreateText(editor, "", "font.size.sm", "color.text.secondary", "LEFT")
                editor.externalLimitHint:SetPoint("TOPLEFT", 10, -84)
                editor.externalLimitHint:SetWidth(CONTENT_WIDTH - 20)
                editor.externalLimitHint:SetHeight(44)
                editor.externalLimitHint:SetWordWrap(true)
            end
            local enabledCount = 0
            for _, option in ipairs(options or {}) do
                if option.enabled ~= false then enabledCount = enabledCount + 1 end
            end
            editor.externalHelp:SetText(T("designer.picker.bundle.external_buffs_summary", "监控自己获得的外部增益，仅显示他人提供的效果。"))
            editor.externalLimit:SetValue(externalLimit, true)
            editor.externalLimitHint:SetText(externalLimit > 0
                and T("designer.external_buffs.limit_hint", "按暴雪默认排序独立成段显示；成员顺序暂不生效。预览仅为示例。")
                or T("designer.external_buffs.unlimited_hint", "不限数量，按下方成员顺序排列。"))
            editor.externalMembers:SetText(string.format(T("designer.external_buffs.members", "合集成员（已开启 %d / %d 项）"), enabledCount, #(options or {})))
        end
        SetShown(editor.externalHelp, bundleKind == "externalBuff")
        SetShown(editor.externalMembers, bundleKind == "externalBuff")
        SetShown(editor.externalLimit, bundleKind == "externalBuff")
        SetShown(editor.externalLimitHint, bundleKind == "externalBuff")
        if bundleKind == "externalBuff" then
            editor.classContext:Hide()
            editor.specContext:Hide()
            editor.raceContext:Hide()
        elseif bundleKind == "racial" then
            editor.classContext:Hide()
            editor.specContext:Hide()
            editor.raceContext:Show()
            if editor.raceContext.RefreshOptions then
                editor.raceContext:RefreshOptions()
            end
            if selectedContext then
                editor.raceContext:SetValue(selectedContext, true)
            end
        else
            editor.raceContext:Hide()
            editor.classContext:Show()
            editor.specContext:Show()
            if editor.classContext.RefreshOptions then
                editor.classContext:RefreshOptions()
            end
            if editor.specContext.RefreshOptions then
                editor.specContext:RefreshOptions()
            end
            if selectedContext then
                editor.classContext:SetValue(
                    selectedContext:match("^([^:]+):"),
                    true
                )
                editor.specContext:SetValue(selectedContext, true)
            end
        end
        editor:Show()
        local optionCount = #(options or {})
        for index = 1, #(editor.rows or {}) do
            local row = editor.rows[index]
            local option = options and options[index]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 10, -rowTop - ((index - 1) * 38))
            if option then
                row.spellID = option.spellID
                row.tooltipSpellID = option.runtimeSpellID or option.spellID
                row.bundleKind = bundleKind
                row.bundleIndex = index
                row.icon:SetIcon(option.icon or QUESTION_ICON)
                row.label:SetText(string.format(
                    "%s (%d)",
                    option.name or tostring(option.spellID),
                    row.tooltipSpellID
                ))
                row.switch:SetValue(option.enabled ~= false, true)
                row.moveUp:SetDisabled(externalLimit > 0 or index == 1)
                row.moveDown:SetDisabled(externalLimit > 0 or index == optionCount)
                row:Show()
            else
                row.spellID = nil
                row.tooltipSpellID = nil
                row.bundleKind = nil
                row.bundleIndex = nil
                row:Hide()
            end
        end
        local editorHeight = rowTop + 6 + (math.max(optionCount, 1) * 38)
        editor:SetHeight(editorHeight)
        contentBottom = bundleTop + editorHeight
    end
    self.monitorContentBottom = contentBottom
    contentBottom = PlaceMonitorMaintenance(self, body, contentBottom)
    self.monitorContentBottom = contentBottom
    SetV2InspectorScrollContentHeight(self, math.max(300, contentBottom))
end

function DesignerUI:ApplyV2PageLayout()
    local _, profile, group, monitor = SelectedContext()
    if not (profile and group) then return end
    local page = self.propertyPage or "common"
    SyncV2PropertyTabs(self, page, false)
    EnsureV2PageBuilt(self, page, group)
    AssignV2PageParents(self)
    HideAllPageControls(self)
    local monitorScroll = page == "monitor" and group.layout ~= "resource"
    local groupScroll = (page == "monitor" and group.layout == "resource") or page == "common"
        or (page == "layout" and (group.layout == "resource" or group.layout == "bars" or group.layout == "icons"))
        or (page == "appearance" and (group.layout == "resource" or group.layout == "icons" or group.layout == "bars"))
        or (page == "text" and (group.layout == "resource" or self.textEditorTarget == "keybind"))
    SetV2InspectorScrollActive(
        self,
        monitorScroll or groupScroll,
        monitorScroll and self.monitorInspectorBody or self.groupInspectorBody
    )
    if not monitorScroll then
        self.monitorInspectorBody:ClearAllPoints()
        self.monitorInspectorBody:SetPoint(
            "TOPLEFT", self.panel, "TOPLEFT", PANEL_PADDING, -146
        )
        self.monitorInspectorBody:SetPoint(
            "BOTTOMRIGHT", self.panel, "BOTTOMRIGHT", -PANEL_PADDING, PANEL_PADDING
        )
    end
    self:SyncDesignCooldownTextPreview(
        page == "text" and "all" or nil
    )
    self.statusText:Hide()

    if group.layout == "resource" and (page == "layout" or page == "appearance" or page == "text") then
        EnsureResourceStyleSelection(self, profile)
    end
    if page == "common" then
        RefreshCommonPage(self, group)
    elseif page == "layout" then
        RefreshLayoutPage(self, profile, group)
    elseif page == "appearance" then
        RefreshAppearancePage(self, profile, group)
    elseif page == "text" then
        RefreshTextPage(self, profile, group)
    else
        RefreshMonitorPage(self, group, monitor)
    end
    if page ~= "monitor" then
        HideControls(self.resourceBaseControls)
        HideControls(self.resourcePresetRows)
    end
    if self.RefreshResourcePageSelection then self:RefreshResourcePageSelection(profile, group, page) end
    if self.RefreshBarShadowControls then self:RefreshBarShadowControls(profile, group, page) end
    ActivateV2Page(self, page)
end

function DesignerUI:ResetInspectorBinding()
    if YHUD.KeybindResolver then YHUD.KeybindResolver:SetPreviewDemand(self, false) end
    if self.MonitorHelp then self.MonitorHelp:Hide() end
    if GUI2.FontStyle then GUI2.FontStyle:CloseForProvider("yhud") end
    local anchor = GUI2.DropdownFrame and GUI2.DropdownFrame.anchor
    while anchor do
        if anchor == self.panel then
            GUI2:CloseDropdown(false)
            break
        end
        anchor = anchor.GetParent and anchor:GetParent()
    end
    self.inspectorBindingContext = nil
end

function DesignerUI:BeginV2CorePageRefresh()
    if self.MonitorHelp then self.MonitorHelp:Hide() end
    self.v2SpecialOverflowState = nil
    self.v2SpecialOverflowGroupId = nil
    local session, profile, group = SelectedContext()
    if not (session and profile and group) then
        self:ResetInspectorBinding()
        return false
    end
    local binding = self.inspectorBindingContext
    if not binding or binding.session ~= session or binding.profile ~= profile
        or binding.groupId ~= group.id or binding.monitorId ~= session.selectedMonitorId then
        self:ResetInspectorBinding()
        self.inspectorBindingContext = {
            session = session, profile = profile, groupId = group.id, monitorId = session.selectedMonitorId,
        }
    end
    self:RefreshDesignerGeometry()
    self.iconSettingsPage = self.propertyPage == "text" and "text" or "layout"
    self.v2Refreshing = true
    self.v2CoreRefreshContext = {
        session = session,
        profile = profile,
        group = group,
    }
    if YHUD.KeybindResolver then
        YHUD.KeybindResolver:SetPreviewDemand(self,
            self.propertyPage == "text" and self.textEditorTarget == "keybind"
                and group.layout == "icons")
    end
    return true
end

function DesignerUI:SyncV2CorePageHeader()
    local context = self.v2CoreRefreshContext
    if not context then return false end
    local session = context.session
    local group = context.group
    if self.profileDropdown and self.profileDropdown.SetValue then
        self.profileDropdown:SetValue(session.setId, true)
    end
    if self.groupDropdown and self.groupDropdown.SetValue then
        self.groupDropdown:SetValue(session.selectedGroupId, { silent = true, force = true })
    end
    self.groupNameInput:SetValue(GroupName(group), true)
    if self.groupNameInput.SetDisabled then
        self.groupNameInput:SetDisabled(group.fixedName == true)
    end
    self.enableSwitch:SetValue(group.enabled == true, true)
    if self.enableSwitch.SetDisabled then
        self.enableSwitch:SetDisabled(group.fixedEnabled == true)
    end
    self.unavailablePreviewSwitch:SetValue(
        group.showUnavailablePreview ~= false,
        true
    )
    self.settingsLayoutType = group.layout
    self.durationTextTarget = self.durationTextTarget or "cooldown"
    if group.layout == "icons" and self.durationTextTarget == "name" then
        self.durationTextTarget = "cooldown"
    end
    if self.panelTitle then
        self.panelTitle:SetText(T("designer.group_settings", "分组设置"))
    end
    if self.inspectorTypeBadge and self.inspectorTypeBadge.SetText then
        self.inspectorTypeBadge:SetText(GroupTypeName(group))
    end
    if self.groupSummary then self.groupSummary:Hide() end
    return true
end

function DesignerUI:RefreshLevelDisplayNotice(group)
    local notice = self.levelDisplayNotice
    if not notice then return false end
    if not group then
        local _, _, selectedGroup = SelectedContext()
        group = selectedGroup
    end
    local shown = self.active == true and self.panel and self.panel:IsShown()
        and YHUD.IsGroupLevelRestricted and YHUD:IsGroupLevelRestricted(group) or false
    if shown then
        local caption = string.format(T(
            "designer.level_display.notice",
            "该分组在角色低于 %d 级时不会显示。"
        ), YHUD:GetResourceOnlyBelowLevel())
        if notice.caption ~= caption then
            notice.caption = caption
            notice.text:SetText(caption)
            notice.text:SetHeight(0)
            local height = math.max(24, notice.text:GetStringHeight())
            notice.text:SetHeight(height)
            notice:SetHeight(height)
        end
    end
    if notice:IsShown() ~= shown then SetShown(notice, shown) end
    if self.specialOverflowNotice and self.levelNoticeStacked ~= shown then
        self.levelNoticeStacked = shown
        self.specialOverflowNotice:ClearAllPoints()
        if shown then
            self.specialOverflowNotice:SetPoint("BOTTOMLEFT", notice, "TOPLEFT", 0, 4)
        else
            self.specialOverflowNotice:SetPoint("BOTTOMLEFT", self.panel, "TOPLEFT", 0, 10)
        end
    end
    return shown
end

function DesignerUI:SyncV2CorePageNotice()
    local context = self.v2CoreRefreshContext
    if not context then return false end
    local profile = context.profile
    local group = context.group
    self:RefreshLevelDisplayNotice(group)
    if self.specialOverflowNotice then
        local specialState = self.v2SpecialOverflowGroupId == group.id
            and self.v2SpecialOverflowState or nil
        if not specialState and YHUD.GetSpecialMonitorGroupState then
            specialState = YHUD:GetSpecialMonitorGroupState(profile, group, true)
        end
        SetShown(
            self.specialOverflowNotice,
            specialState and specialState.segmented == true or false
        )
    end
    return true
end

function DesignerUI:LayoutV2CorePageRefresh()
    self:ApplyV2PageLayout()
    return true
end

function DesignerUI:FinishV2CorePageRefresh(animate, rebuildPreview)
    self.v2CoreRefreshContext = nil
    self.v2Refreshing = false
    self:SetStatus(self:IsSessionDirty()
        and T("designer.status_dirty", "当前配置有未保存修改。")
        or T("designer.status_clean", "当前配置已保存。"))
    if rebuildPreview == false then
        self:RefreshSelectionPreview()
    else
        self:ApplyPreview()
    end
    self:PositionInspector(animate)
    self:RefreshGlowEditor(false)
    self:PositionGlowEditor()
    return true
end

local function RefreshV2CorePage(self, animate, rebuildPreview)
    if not self:BeginV2CorePageRefresh() then return false end
    self:SyncV2CorePageHeader()
    self:SyncV2CorePageNotice()
    self:LayoutV2CorePageRefresh()
    return self:FinishV2CorePageRefresh(animate, rebuildPreview)
end

function DesignerUI:BeginStagedInspectorRefresh(animate, rebuildPreview)
    if self.stagedInspectorRefresh then
        return nil, "staged-refresh-active"
    end
    if self.designerMode == "skyriding" then
        local ready, code = self:Refresh(animate, rebuildPreview)
        if not ready then return ready, code end
        self.stagedInspectorRefresh = { skip = true }
        return true
    end
    local ready = self:BeginV2CorePageRefresh()
    if not ready then return false, "missing-selection" end
    local session = Designer:GetSession()
    local groupId = session and session.selectedGroupId
    local projectionRuntime = YHUD.View and YHUD.View.designProjection
        and YHUD.View.designProjection.groups
        and YHUD.View.designProjection.groups[groupId]
    if projectionRuntime then
        self.v2SpecialOverflowGroupId = groupId
        self.v2SpecialOverflowState =
            projectionRuntime.filteredAuraProjectionState
    end
    self.stagedInspectorRefresh = {
        animate = animate,
        rebuildPreview = rebuildPreview,
    }
    return true
end

function DesignerUI:LayoutStagedInspectorRefresh()
    local staged = self.stagedInspectorRefresh
    if not staged then
        return nil, "staged-refresh-missing"
    end
    if staged.skip == true then return true end
    return self:LayoutV2CorePageRefresh()
end

function DesignerUI:SyncStagedInspectorHeader()
    local staged = self.stagedInspectorRefresh
    if not staged then return nil, "staged-refresh-missing" end
    if staged.skip == true then return true end
    return self:SyncV2CorePageHeader()
end

function DesignerUI:SyncStagedInspectorNotice()
    local staged = self.stagedInspectorRefresh
    if not staged then return nil, "staged-refresh-missing" end
    if staged.skip == true then return true end
    return self:SyncV2CorePageNotice()
end

function DesignerUI:FinishStagedInspectorRefresh()
    local staged = self.stagedInspectorRefresh
    if not staged then return nil, "staged-refresh-missing" end
    self.stagedInspectorRefresh = nil
    if staged.skip == true then return true end
    return self:FinishV2CorePageRefresh(
        staged.animate,
        staged.rebuildPreview
    )
end

function DesignerUI:AbortStagedInspectorRefresh()
    self.stagedInspectorRefresh = nil
    self.v2CoreRefreshContext = nil
    self.v2Refreshing = false
    return true
end

function DesignerUI:Refresh(animate, rebuildPreview)
    if not self.v2Built then
        local ready, code = self:EnsureUI()
        if not ready then return ready, code end
    end
    if self.designerMode == "skyriding" then
        self:RefreshDesignerGeometry()
        if self.panel then self.panel:Hide() end
        if self.SyncDesignerModePresentation then
            self:SyncDesignerModePresentation()
        end
        return true
    end
    return RefreshV2CorePage(self, animate, rebuildPreview)
end

function DesignerUI:SelectGroup(groupId)
    FinishOpenColorPicker()
    if self.visibilityRuleEditor then
        self.visibilityRuleEditor:ClosePanel()
    end
    self:CancelMonitorIdentityEdit(true)
    self:StopResourceValuePreview(true, false)
    local profile = Designer:GetProfile()
    local group = profile and profile.groups and profile.groups.items
        and profile.groups.items[groupId]
    self.propertyPage = group
        and group.layout ~= "resource"
        and CountList(group.monitors) == 0
        and "monitor" or "common"
    self.monitorPage = 1
    HideMonitorEffectsPage(self)
    I.HideMonitorSoundPage(self)
    self.monitorEffectsEditing = false
    self.monitorSoundEditing = false
    self.textEditorTarget = nil
    return BaseSelectGroup(self, groupId)
end

function DesignerUI:SelectMonitor(monitorId)
    FinishOpenColorPicker()
    self:CancelMonitorIdentityEdit(true)
    self:StopResourceValuePreview(true, false)
    self.propertyPage = "monitor"
    HideMonitorEffectsPage(self)
    I.HideMonitorSoundPage(self)
    self.monitorEffectsEditing = false
    self.monitorSoundEditing = false
    return BaseSelectMonitor(self, monitorId)
end

function DesignerUI:SetSelectedGroupTextStyle(suffix, value)
    local result = BaseSetSelectedGroupTextStyle(self, suffix, value)
    if result and self.v2Built then self:PreviewSelectedGroup() end
    return result
end

function DesignerUI:SetSelectedGroupResourceStyle(field, value)
    local result = BaseSetSelectedGroupResourceStyle(self, field, value)
    if result and self.v2Built then
        self:PreviewSelectedGroup()
        DesignerUI:AddResourcePreviewStat("resourcePreviewGroupRefreshes", 1)
        DesignerUI:AddResourcePreviewStat("resourcePreviewFullRefreshAvoided", 1)
    end
    return result
end

function DesignerUI:HideMonitorDeleteConfirm()
    local frame = S and S.ConfirmFrame
    if frame and frame.confirmOwner == self then
        frame:Hide()
        frame.confirmOwner = nil
    end
end

function DesignerUI:RequestRemoveSelectedMonitor(options)
    local session, profile, _, monitor = SelectedContext()
    if not (session and profile and monitor) then return false end
    local entry = profile.entries and profile.entries[monitor.entryKey]
    local canDeleteAll = entry and entry.origin ~= "official-cdm"
        and monitor.contentScope ~= YHUD.CONTENT_SCOPE_SHARED
    if not canDeleteAll and session.suppressMonitorDeleteConfirm == true then
        return self:RemoveSelectedMonitor()
    end
    if not (type(options) == "table" and options.keepPicker == true) then
        self:HideMonitorPicker()
    end
    self:HideGlowEditor()
    self:HideNewGroupDialog()
    self:HideSwitchDialog()
    self:HideCancelDialog()
    if not (S and S.ShowConfirmPopup) then return false end
    local monitorName = MonitorName(profile, monitor)
    monitorName = tostring(monitorName or ""):gsub("|", "||")
    local accentHex = GUI2.Colors_Hex and GUI2.Colors_Hex.text_highlight
        or "ffffd100"
    S:ShowConfirmPopup(
        string.format(
            T(
                "designer.monitor.delete_confirm",
                "确定删除监控“%s”吗？"
            ),
            "|c" .. accentHex .. monitorName .. "|r"
        ),
        function(checked)
            DesignerUI:ConfirmRemoveSelectedMonitor(
                not canDeleteAll and checked, canDeleteAll and checked)
        end,
        {
            owner = self,
            titleText = T(
                "designer.monitor.delete_confirm_title",
                "删除监控"
            ),
            acceptText = TC("common.delete", "删除"),
            acceptTone = "danger",
            acceptRelief = "hairline",
            checkboxText = canDeleteAll and T(
                "designer.monitor.delete_all_specs",
                "从所有专精删除"
            ) or T(
                "designer.monitor.delete_confirm_session",
                "本轮不再提示"
            ),
            onCancel = function()
                DesignerUI.monitorPickerKeepOpenDelete = nil
                DesignerUI:HideMonitorDeleteConfirm()
            end,
        }
    )
    return true
end

function DesignerUI:ConfirmRemoveSelectedMonitor(suppress, allSpecializations)
    local session = Designer:GetSession()
    if session and suppress == true then
        session.suppressMonitorDeleteConfirm = true
    end
    self:HideMonitorDeleteConfirm()
    return self:RemoveSelectedMonitor(allSpecializations)
end

function DesignerUI:ReorderSelectedMonitor(
    delta,
    targetIndex,
    targetLane,
    placement
)
    if targetIndex == nil and targetLane == nil
        and (delta == -1 or delta == 1) then
        local _, profile, group, selected = SelectedContext()
        if not selected then
            self:SetStatus(T(
                "designer.error_select_monitor",
                "请先选择一个监控。"
            ))
            return nil, "monitor-not-found"
        end
        local operation, operationCode = ResolveV2ReorderOperation(
            profile,
            group,
            selected,
            delta
        )
        if not operation then
            if operationCode == "special-overflow-region" then
                self:SetStatus(T(
                    "designer.error.special_overflow_region",
                    "特殊监控与其他监控只能在各自区域内调整顺序。"
                ))
            end
            return selected
        end

        self.monitorFollowSelection = true
        local moved, code = Designer:ReorderMonitor(
            operation.monitorId,
            operation.targetLane,
            operation.targetIndex
        )
        if moved and operation.selectedMonitorId ~= moved.id then
            Designer:SelectMonitor(operation.selectedMonitorId)
        end
        if moved then
            self:RefreshAfterStructuralMutation(false)
            self:SetStatus(T(
                "designer.status_monitor_reordered",
                "监控顺序已更新。"
            ))
        else
            self:SetStatus(T(
                "designer.error_reorder",
                "无法调整监控顺序。"
            ))
        end
        self.monitorFollowSelection = nil
        if not moved then return nil, code end
        return Designer:GetSelectedMonitor()
    end
    self.monitorFollowSelection = true
    local monitor, code = BaseReorderSelectedMonitor(
        self,
        delta,
        targetIndex,
        targetLane,
        placement
    )
    self.monitorFollowSelection = nil
    if not monitor and code == "special-overflow-region" then
        self:SetStatus(T(
            "designer.error.special_overflow_region",
            "特殊监控与其他监控只能在各自区域内调整顺序。"
        ))
    end
    return monitor, code
end

function DesignerUI:RemoveSelectedMonitor(allSpecializations)
    self:CancelMonitorIdentityEdit(true)
    HideMonitorEffectsPage(self)
    I.HideMonitorSoundPage(self)
    self.monitorEffectsEditing = false
    self.monitorSoundEditing = false
    local _, profile, group, monitor = SelectedContext()
    local nextId
    if profile and group and monitor then
        for index = 1, #group.monitors do
            if group.monitors[index] == monitor.id then
                nextId = group.monitors[index + 1] or group.monitors[index - 1]
                break
            end
        end
    end
    local ok, code = BaseRemoveSelectedMonitor(self, allSpecializations)
    if not ok then return ok, code end
    profile = Designer:GetProfile()
    if self.monitorPickerKeepOpenDelete then
        self.monitorPickerKeepOpenDelete = nil
        self:ClearMonitorPickerOverlay()
    end
    self:RefreshMonitorPicker()
    if nextId and profile.monitors[nextId] then
        Designer:SelectMonitor(nextId)
        self.propertyPage = "monitor"
        self:Refresh(false, false)
    else
        self.propertyPage = "common"
        self:Refresh(false, false)
    end
    return true
end

function DesignerUI:HideWorkspace()
    self:ResetInspectorBinding()
    self:HideMonitorDeleteConfirm()
    self:CancelMonitorIdentityEdit(true)
    self:StopResourceValuePreview(true, false)
    self:RestoreCooldownSettingsLayer()
    self:HideMonitorPicker()
    return BaseHideWorkspace(self)
end

function DesignerUI:ShowWorkspace()
    self.inspectorDockRequested = true
    if self.RegisterSpecializationToolbarEvents then
        self:RegisterSpecializationToolbarEvents()
    end
    if self.RefreshSpecializationToolbar then
        self:RefreshSpecializationToolbar()
    end
    -- Keep the inspector hidden until V2 has adopted, hidden and laid out the
    -- complete foundation tree. This prevents the first rendered frame after
    -- /reload from ever exposing the foundation's construction geometry.
    if self.dimmer then self.dimmer:Show() end
    if self.toolbar then self.toolbar:Show() end
    if self.EnsureModeSwitcher then
        local switcher = self:EnsureModeSwitcher()
        if switcher then switcher:Show() end
    end
    local session = Designer:GetSession()
    local result = true
    if session and session.selectedGroupId then
        if self.panel then self.panel:Hide() end
        result = self:Refresh(false)
        if self.panel then self.panel:Show() end
    elseif self.panel then
        self.panel:Hide()
    end
    local frame = _G.CooldownViewerSettings
    if frame and frame.IsShown and frame:IsShown() then
        self:ElevateCooldownSettings(frame)
    end
    if self.SyncDesignerModePresentation then
        self:SyncDesignerModePresentation()
    end
    return result
end

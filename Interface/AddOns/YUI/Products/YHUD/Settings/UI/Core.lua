local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local GUI2 = YUI.GUI2
local S = YUI.Settings
local Designer = YHUD.Designer
local Catalog = YHUD.ConfigCatalog
local ResourceCatalog = YHUD.ResourceCatalog
local Glow = YHUD.Glow
if not (GUI2 and GUI2.Form and S and Designer and Catalog) then return end

local DesignerUI = {
    active = false,
    source = nil,
    previewOwnsView = false,
    pendingSwitchSetId = nil,
    layoutListener = nil,
    restoreConfirmToken = nil,
    monitorPickerRows = {},
    inspectorSection = "group",
}
YHUD.DesignerUI = DesignerUI

local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local GROUP_LAYOUT_MICRO_ICONS = {
    icons = "image",
    bars = "chart-bar-big",
    rings = "circle",
    resource = "rectangle-ellipsis",
}

local function GetGroupLayoutIcon(layout)
    local iconName = GROUP_LAYOUT_MICRO_ICONS[layout]
        or GROUP_LAYOUT_MICRO_ICONS.icons
    return GUI2.GetSettingsMicroIcon
        and GUI2:GetSettingsMicroIcon(iconName, 16) or nil
end

local function T(key, fallback)
    return YHUD:T(key, fallback)
end

local CoreLocale = YUI.Locale and YUI.Locale.Get
    and YUI.Locale:Get("Core") or {}

local function TC(key, fallback)
    local value = CoreLocale and CoreLocale[key]
    return type(value) == "string" and value or fallback
end

local function InCombat()
    local Combat = YUI.API and YUI.API.Combat
    return Combat and Combat.InCombatLockdown
        and Combat.InCombatLockdown() == true
        or false
end

local function Print(message)
    if not message or message == "" then return end
    if YUI.Print then
        YUI:Print(message)
    else
        print(message)
    end
end

local function GroupName(group)
    if type(group) ~= "table" then return "-" end
    if group.nameKey then
        return T(group.nameKey, group.name or group.id or "-")
    end
    return group.name or group.id or "-"
end

local function GroupTypeName(group)
    if group and group.contentPolicy == "cast-only" then return T("resource.player_cast", "玩家施法条") end
    local layout = group and group.layout
    if layout == "bars" then
        return T("designer.type.bars", "进度条组")
    end
    if layout == "rings" then
        return T("designer.type.rings", "圆环组")
    end
    if layout == "resource" then
        return T("designer.type.resource", "资源条")
    end
    return T("designer.type.icons", "图标组")
end

local function CountList(values)
    return type(values) == "table" and #values or 0
end

local MONITOR_LAYOUTS = {
    icons = true,
    bars = true,
    rings = true,
}

local function CanAddMonitor(group)
    if type(group) ~= "table"
        or MONITOR_LAYOUTS[group.layout] ~= true then
        return false
    end
    local capabilities = YHUD:GetGroupAddCapabilities(group)
    return capabilities.cooldown or capabilities.buff
end

local function SetShown(control, shown)
    if not control then return end
    if shown then
        control:Show()
    else
        control:Hide()
    end
end

local function BuildDirectionOptions()
    return {
        {
            text = T("designer.direction.right", "向右"),
            value = "right",
        },
        {
            text = T("designer.direction.left", "向左"),
            value = "left",
        },
        {
            text = T("designer.direction.down", "向下"),
            value = "down",
        },
        {
            text = T("designer.direction.up", "向上"),
            value = "up",
        },
    }
end

local function BuildAlignmentOptions()
    return {
        {
            text = T("designer.alignment.center", "居中"),
            value = "center",
        },
        {
            text = T("designer.alignment.start", "起点"),
            value = "start",
        },
        {
            text = T("designer.alignment.end", "终点"),
            value = "end",
        },
    }
end

local function BuildRowDirectionOptions()
    return {
        {
            text = T("designer.row_direction.right", "从左到右"),
            value = "right",
        },
        {
            text = T("designer.row_direction.left", "从右到左"),
            value = "left",
        },
    }
end

local function BuildIconAlignmentOptions()
    return {
        { text = T("designer.icon_alignment.left", "左对齐"), value = "start" },
        { text = T("designer.alignment.center", "居中"), value = "center" },
        { text = T("designer.icon_alignment.right", "右对齐"), value = "end" },
    }
end

function DesignerUI:RefreshIconAlignment(layout)
    if not self.iconAlignmentDropdown then return end
    self.iconAlignmentDropdown:SetValue(layout.alignment, true)
end

local function BuildWrapLayoutOptions(vertical)
    local alignments = vertical and {
        { id = "center", key = "designer.wrap.center", fallback = "居中" },
        { id = "start", key = "designer.wrap.top", fallback = "顶部" },
        { id = "end", key = "designer.wrap.bottom", fallback = "底部" },
    } or {
        { id = "center", key = "designer.wrap.center", fallback = "居中" },
        { id = "start", key = "designer.wrap.left", fallback = "靠左" },
        { id = "end", key = "designer.wrap.right", fallback = "靠右" },
    }
    local directions = vertical and {
        { id = "down", key = "designer.direction.right", fallback = "向右" },
        { id = "up", key = "designer.direction.left", fallback = "向左" },
    } or {
        { id = "down", key = "designer.direction.down", fallback = "向下" },
        { id = "up", key = "designer.direction.up", fallback = "向上" },
    }
    local options = {}
    for directionIndex = 1, #directions do
        local direction = directions[directionIndex]
        for alignmentIndex = 1, #alignments do
            local alignment = alignments[alignmentIndex]
            options[#options + 1] = {
                text = T(alignment.key, alignment.fallback)
                    .. " · "
                    .. T(direction.key, direction.fallback),
                value = alignment.id .. "-" .. direction.id,
            }
        end
    end
    return options
end

local function BuildOrientationOptions()
    return {
        {
            text = T("designer.orientation.horizontal", "横向"),
            value = "horizontal",
        },
        {
            text = T("designer.orientation.vertical", "纵向"),
            value = "vertical",
        },
    }
end

local function BuildDurationDirectionOptions()
    return {
        { text = T("designer.progress.right", "横向 · 向右增加"), value = "horizontal-forward" },
        { text = T("designer.progress.left", "横向 · 向左增加"), value = "horizontal-reverse" },
        { text = T("designer.progress.up", "纵向 · 向上增加"), value = "vertical-forward" },
        { text = T("designer.progress.down", "纵向 · 向下增加"), value = "vertical-reverse" },
    }
end

local function BuildResourceFillDirectionOptions()
    return {
        {
            text = T("designer.resource.fill_forward", "正向"),
            value = "forward",
        },
        {
            text = T("designer.resource.fill_reverse", "反向"),
            value = "reverse",
        },
    }
end

local function BuildIconPositionOptions()
    return {
        {
            text = T("designer.icon_position.left", "左侧"),
            value = "left",
        },
        {
            text = T("designer.icon_position.right", "右侧"),
            value = "right",
        },
        {
            text = T("designer.icon_position.top", "顶部"),
            value = "top",
        },
        {
            text = T("designer.icon_position.bottom", "底部"),
            value = "bottom",
        },
        {
            text = T("designer.icon_position.center", "居中"),
            value = "center",
        },
    }
end

local function BuildShapeOptions()
    return {
        {
            text = TC("common.shape.square", "直角方形"),
            value = "square",
        },
        {
            text = TC("common.shape.rounded_square", "圆角方形"),
            value = "roundedSquare",
        },
        {
            text = TC("common.shape.flat_square", "直角扁平"),
            value = "flatSquare",
        },
        {
            text = TC("common.shape.flat_rounded", "圆角扁平"),
            value = "flatRounded",
        },
        {
            text = TC("common.shape.wide_square", "直角微扁"),
            value = "wideSquare",
        },
        {
            text = TC("common.shape.wide_rounded", "圆角微扁"),
            value = "wideRounded",
        },
        {
            text = TC("common.shape.circle", "圆形"),
            value = "circle",
        },
    }
end

local function BuildBorderOptions()
    return {
        {
            text = T("designer.border.none", "无"),
            value = "none",
        },
        {
            text = T("designer.border.thin", "细"),
            value = "thin",
        },
        {
            text = T("designer.border.medium", "中"),
            value = "medium",
        },
        {
            text = T("designer.border.thick", "粗"),
            value = "thick",
        },
        {
            text = T("designer.border.extra_thick", "特粗"),
            value = "extraThick",
        },
    }
end

local function BuildFontOptions()
    return {
        {
            text = T("designer.font.default", "默认字体"),
            value = "default",
        },
        {
            text = T("designer.font.chat", "聊天字体"),
            value = "chat",
        },
        {
            text = T("designer.font.damage", "伤害数字"),
            value = "damage",
        },
    }
end

local function BuildOutlineOptions()
    if GUI2.Form.BuildFontOutlineOptions then
        return GUI2.Form:BuildFontOutlineOptions()
    end
    return {
        {
            text = T("designer.outline.none", "无"),
            value = "none",
        },
        {
            text = T("designer.outline.normal", "描边"),
            value = "outline",
        },
        {
            text = T("designer.outline.thick", "粗描边"),
            value = "thick",
        },
        {
            text = T("designer.outline.shadow", "阴影"),
            value = "shadow",
        },
        {
            text = T("designer.outline.outline_shadow", "描边+阴影"),
            value = "outlineShadow",
        },
    }
end

local function BuildTextPositionOptions()
    return {
        {
            text = T("designer.text_position.center", "居中"),
            value = "center",
        },
        {
            text = T("designer.text_position.top", "顶部"),
            value = "top",
        },
        {
            text = T("designer.text_position.bottom", "底部"),
            value = "bottom",
        },
        {
            text = T("designer.text_position.left", "左侧"),
            value = "left",
        },
        {
            text = T("designer.text_position.right", "右侧"),
            value = "right",
        },
        {
            text = T("designer.text_position.top_left", "左上"),
            value = "top-left",
        },
        {
            text = T("designer.text_position.bottom_left", "左下"),
            value = "bottom-left",
        },
        {
            text = T("designer.text_position.top_right", "右上"),
            value = "top-right",
        },
        {
            text = T("designer.text_position.bottom_right", "右下"),
            value = "bottom-right",
        },
    }
end

local function BuildBarTextAnchorOptions(includeIcon)
    local options = {}
    local function Add(key, fallback, value)
        options[#options + 1] = {
            text = T("designer.text_anchor." .. key, fallback),
            value = value,
        }
    end
    if includeIcon then
        Add("icon_top_left", "图标内左上", "icon-top-left")
        Add("icon_top", "图标内上", "icon-top")
        Add("icon_top_right", "图标内右上", "icon-top-right")
        Add("icon_left", "图标内左", "icon-left")
        Add("icon_center", "图标内中", "icon-center")
        Add("icon_right", "图标内右", "icon-right")
        Add("icon_bottom_left", "图标内左下", "icon-bottom-left")
        Add("icon_bottom", "图标内下", "icon-bottom")
        Add("icon_bottom_right", "图标内右下", "icon-bottom-right")
    end
    Add("bar_left", "条内左", "bar-left")
    Add("bar_center", "条内中", "bar-center")
    Add("bar_right", "条内右", "bar-right")
    Add("bar_top", "条内上", "bar-top")
    Add("bar_bottom", "条内下", "bar-bottom")
    Add("bar_top_left", "条内左上", "bar-top-left")
    Add("bar_top_right", "条内右上", "bar-top-right")
    Add("bar_bottom_left", "条内左下", "bar-bottom-left")
    Add("bar_bottom_right", "条内右下", "bar-bottom-right")
    Add("bar_outside_left", "条外左", "bar-outside-left")
    Add("bar_outside_right", "条外右", "bar-outside-right")
    Add("bar_outside_top", "条外上", "bar-outside-top")
    Add("bar_outside_bottom", "条外下", "bar-outside-bottom")
    return options
end

local function BuildNumberOptions(values)
    local options = {}
    for index = 1, #values do
        local value = values[index]
        options[index] = {
            text = tostring(value),
            value = value,
        }
    end
    return options
end

local function BuildGlowTriggerOptions()
    return {
        {
            text = T("designer.glow.self_ready", "技能可用"),
            value = "self-ready",
        },
        {
            text = T(
                "designer.glow.self_cooldown",
                "技能冷却中"
            ),
            value = "self-cooldown",
        },
    }
end

local function BuildGlowStyleOptions()
    return {
        {
            text = T("designer.glow.style.pixel", "像素线段"),
            value = "pixel",
        },
        {
            text = T("designer.glow.style.button", "按钮发光"),
            value = "button",
        },
        {
            text = T("designer.glow.style.autocast", "自动施法"),
            value = "autocast",
        },
        {
            text = T("designer.glow.style.proc", "触发发光"),
            value = "proc",
        },
        {
            text = T("designer.glow.style.pulse", "脉冲发光"),
            value = "pulse",
        },
    }
end

local function BuildNativeGlowStyleOptions()
    local options = {
        {
            text = T("designer.glow.style.default", "无"),
            value = "default",
        },
    }
    local custom = BuildGlowStyleOptions()
    for index = 1, #custom do options[#options + 1] = custom[index] end
    return options
end

local function BuildGlowControlLabels()
    return {
        params = T("designer.glow.params", "发光参数"),
        type = T("designer.glow.type", "类型"),
        color = T("designer.glow.color", "颜色"),
        size = T("designer.glow.size", "尺寸"),
        lines = T("designer.glow.lines", "线段数量"),
        thickness = T("designer.glow.thickness", "线段粗细"),
        speed = T("designer.glow.speed", "速度"),
        alpha = T("designer.glow.alpha", "透明度"),
        offsetX = T("designer.glow.offset_x", "横向扩展"),
        offsetY = T("designer.glow.offset_y", "纵向扩展"),
        reset = T("designer.glow.reset", "重置"),
    }
end

local function MonitorActionText(status)
    if status == "add" then
        return T("designer.action.add", "添加")
    end
    if status == "move" then
        return T("designer.action.move", "移动")
    end
    if status == "current" then
        return T("designer.action.current", "已添加")
    end
    if status == "expand" then
        return T("designer.action.expand", "展开")
    end
    if status == "collapse" then
        return T("designer.action.collapse", "收起")
    end
    return T("designer.action.unavailable", "不可用")
end

local function IsMonitorPickerFolder(option)
    return option
        and (
            option.kind == "item-folder"
            or option.kind == "racial-folder"
        )
end

local function MonitorName(profile, monitor)
    local entry = monitor and profile and profile.entries
        and profile.entries[monitor.entryKey]
    local slotId = entry and tonumber(entry.slotId or entry.slotID)
    if slotId then
        return string.format(
            T("designer.slot_name", "饰品栏 %d"),
            slotId
        )
    end
    return YHUD:GetEntryDisplayName(
        entry,
        monitor and (monitor.entryKey or monitor.id)
            or T("designer.monitor_none", "选择一个监控")
    )
end

local function EntryIcon(entry)
    if type(entry) ~= "table" then return QUESTION_ICON end
    if entry.sourceType == "racial-bundle" or entry.bundleKind == "racial" then
        local catalog = YHUD.MonitorCatalog
        return catalog and catalog.GetPlayerRacialPreviewIcon
            and catalog:GetPlayerRacialPreviewIcon() or QUESTION_ICON
    end
    if YHUD.Ammo and entry.sourceType == YHUD.Ammo.SOURCE_TYPE then
        return YHUD.Ammo:GetPreviewIcon()
    end
    local slotId = tonumber(entry.slotId or entry.slotID)
    local itemAPI = YUI.API and YUI.API.Item
    if slotId and itemAPI and itemAPI.GetInventoryItemTexture then
        local icon = itemAPI.GetInventoryItemTexture("player", slotId)
        if icon then return icon end
    end
    local hasDemonicHealthstone
    local hasClassicHealthstone
    for index = 1, #(type(entry.itemIds) == "table" and entry.itemIds or {}) do
        local itemID = tonumber(entry.itemIds[index])
        if itemID == 224464 then
            hasDemonicHealthstone = true
        elseif itemID == 5512 then
            hasClassicHealthstone = true
        end
    end
    if hasDemonicHealthstone and hasClassicHealthstone and itemAPI then
        local count = itemAPI.GetCount
            and tonumber(itemAPI.GetCount(224464, false, true)) or 0
        local displayItemID = count > 0 and 224464 or 5512
        local icon = itemAPI.GetIcon and itemAPI.GetIcon(displayItemID)
        if icon then return icon end
    end
    return entry.icon or QUESTION_ICON
end

function DesignerUI:SetStatus(message)
    if self.statusText then
        self.statusText:SetText(message or "")
    end
end

function DesignerUI:SetMutationError(code, fallbackKey, fallback)
    if code == "claim-projection-unavailable" then
        self:SetStatus(T(
            "designer.error_claim_projection",
            "暂时无法同步暴雪冷却监控，请关闭设置后重试或 /reload。"
        ))
        return
    end
    self:SetStatus(T(fallbackKey, fallback))
end

function DesignerUI:SyncDesignCooldownTextPreview(target)
    local View = YHUD.View
    if not (View and View.SetDesignCooldownPreviewGroup) then
        return false
    end
    local groupId
    if target == true then target = "cooldown" end
    if target ~= "all" and target ~= "cooldown"
        and target ~= "name" and target ~= "count" then
        target = nil
    end
    if target
        and self.inspectorSection == "group"
        and self.iconSettingsPage == "text" then
        local session = Designer:GetSession()
        groupId = session and session.selectedGroupId or nil
    end
    return View:SetDesignCooldownPreviewGroup(groupId, target)
end

function DesignerUI:ShowIconSettingsPage(page, enabled)
    if page ~= "text" then
        page = "layout"
    end
    self.iconSettingsPage = page
    self:SyncDesignCooldownTextPreview(enabled == true)
    local controlGroups = {
        self.iconLayoutControls,
        self.durationLayoutControls,
        self.barLayoutControls,
        self.iconAppearanceControls,
        self.durationAppearanceControls,
        self.ringAppearanceControls,
        self.iconTextControls,
        self.iconTextTargetControls,
        self.durationTextControls,
        self.durationNameControls,
        self.resourceBaseControls,
        self.resourcePresetRows,
        self.resourceLayoutControls,
        self.resourceAppearanceControls,
        self.resourceTextControls,
    }
    for groupIndex = 1, #controlGroups do
        local controls = controlGroups[groupIndex]
        for index = 1, #(controls or {}) do
            SetShown(controls[index], false)
        end
    end
    if enabled ~= true then return end

    local function ShowControls(controls)
        for index = 1, #(controls or {}) do
            SetShown(controls[index], true)
        end
    end

    local layoutType = self.settingsLayoutType
    if layoutType == "resource" then
        ShowControls(self.resourceBaseControls)
        for index = 1, #(self.resourcePresetRows or {}) do
            local row = self.resourcePresetRows[index]
            SetShown(row, row.resourceId ~= nil)
        end
        if page == "text" then
            ShowControls(self.resourceTextControls)
        else
            ShowControls(self.resourceLayoutControls)
            ShowControls(self.resourceAppearanceControls)
        end
        return
    end
    local isDuration = layoutType == "bars" or layoutType == "rings"
    if page == "layout" then
        ShowControls(isDuration
            and self.durationLayoutControls or self.iconLayoutControls)
        ShowControls(self.iconAppearanceControls)
        if layoutType == "bars" then
            ShowControls(self.barLayoutControls)
        end
        if isDuration then
            ShowControls(self.durationAppearanceControls)
        end
        if layoutType == "rings" then
            ShowControls(self.ringAppearanceControls)
        end
    else
        ShowControls(self.iconTextControls)
        ShowControls(isDuration
            and self.durationTextControls or self.iconTextTargetControls)
        if isDuration and self.durationTextTarget == "name" then
            ShowControls(self.durationNameControls)
        end
    end
end

function DesignerUI:BuildCurrentDirectionOptions()
    if self.settingsLayoutType == "icons" then
        return {
            { text = T("designer.direction.up", "向上"), value = "up" },
            { text = T("designer.direction.down", "向下"), value = "down" },
        }
    end
    local vertical = false
    if self.settingsLayoutType == "bars" then
        local session = Designer:GetSession()
        local profile = Designer:GetProfile()
        local groupId = session and session.selectedGroupId
        local group = groupId and profile and profile.groups
            and profile.groups.items[groupId]
        local layout = group and YHUD:GetDurationGroupLayout(
            profile,
            groupId,
            group.layout
        )
        vertical = layout and layout.orientation == "vertical" or false
    end
    local options = BuildWrapLayoutOptions(vertical)
    if self.settingsLayoutType == "rings" then
        options[#options + 1] = {
            text = T("designer.direction.outward", "同心向外"),
            value = "outward",
        }
        options[#options + 1] = {
            text = T("designer.direction.inward", "同心向内"),
            value = "inward",
        }
    end
    return options
end

function DesignerUI:BuildPrimarySizeOptions()
    if self.settingsLayoutType == "bars" then
        return BuildNumberOptions({
            120, 160, 180, 220, 244, 260, 300, 360, 420, 520,
            640, 720, 832,
        })
    end
    if self.settingsLayoutType == "rings" then
        return BuildNumberOptions({
            24, 32, 40, 46, 52, 60, 72, 84, 96, 120, 160,
        })
    end
    return BuildNumberOptions({
        28, 32, 36, 42, 46, 52, 60, 72, 84, 96,
    })
end

function DesignerUI:BuildCurrentTextPositionOptions()
    local session = Designer:GetSession()
    local profile = Designer:GetProfile()
    local groupId = session and session.selectedGroupId
    local group = groupId and profile and profile.groups
        and profile.groups.items[groupId]
    if group and group.layout == "bars" then
        local style = YHUD:GetDurationGroupStyle(
            profile,
            groupId
        )
        return BuildBarTextAnchorOptions(
            self.durationTextTarget == "count"
                and (not style or style.showIcon ~= false)
        )
    end
    return BuildTextPositionOptions()
end

function DesignerUI:BuildProfileOptions()
    local rows = Catalog:List()
    local options = {}
    if type(rows) ~= "table" then return options end
    local successHex
    if GUI2.GetColor then
        local r, g, b = GUI2:GetColor(
            "color.state.success",
            { 0.21, 0.75, 0.38, 1 }
        )
        successHex = string.format(
            "%02x%02x%02x",
            math.floor((r or 1) * 255 + 0.5),
            math.floor((g or 1) * 255 + 0.5),
            math.floor((b or 1) * 255 + 0.5)
        )
    end
    successHex = successHex or "36bf61"
    local currentSuffix = T("designer.config_current", "（当前）")
    for index = 1, #rows do
        local row = rows[index]
        if row.set then
            local name = row.set.name or row.set.id
            if row.active == true then
                name = name .. "|cff" .. successHex
                    .. currentSuffix .. "|r"
            end
            options[#options + 1] = {
                text = name,
                selectionText = name,
                value = row.set.id,
            }
        end
    end
    return options
end

function DesignerUI:BuildMonitorTargetOptions()
    local groups = Designer:ListMonitorTargets()
    local options = {}
    if type(groups) ~= "table" then return options end
    for index = 1, #groups do
        local group = groups[index]
        local name = GroupName(group)
        local disabled = group.enabled == false
        if disabled then name = "|cff7f8790" .. name .. "|r" end
        local option = {
            text = name,
            value = group.id,
            render = disabled and function(button)
                if button and button.text then
                    GUI2:SetTextColorKey(button.text, "color.text.disabled")
                end
            end or nil,
        }
        local icon = GetGroupLayoutIcon(group.layout)
        if icon then
            option.texture = icon.texture
            option.texCoords = icon.texCoords
            option.iconSize = icon.size or 16
        end
        options[#options + 1] = option
    end
    return options
end

function DesignerUI:BuildGroupOptions()
    local profile = Designer:GetProfile()
    local groups = profile and profile.groups
    local order = groups and groups.order or {}
    local items = groups and groups.items or {}
    local options = {}
    for index = 1, #order do
        local groupId = order[index]
        local group = items[groupId]
        if group then
            local icon = GetGroupLayoutIcon(group.layout)
            local name = GroupName(group)
            local disabled = group.enabled == false
            if disabled then name = "|cff7f8790" .. name .. "|r" end
            local option = {
                text = name,
                value = groupId,
                render = disabled and function(button)
                    if button and button.text then
                        GUI2:SetTextColorKey(button.text, "color.text.disabled")
                    end
                end or nil,
            }
            if icon then
                option.texture = icon.texture
                option.texCoords = icon.texCoords
                option.iconSize = icon.size or 16
            end
            options[#options + 1] = option
        end
    end
    options[#options + 1] = {
        text = T("designer.new_group_action", "＋ 新建分组…"),
        value = "__yhud_create_group__",
    }
    return options
end

function DesignerUI:BuildResourceClassOptions()
    local options = {}
    if not (ResourceCatalog and ResourceCatalog.GetClasses) then
        return options
    end
    local classes = ResourceCatalog:GetClasses()
    local Icons = YUI.API and YUI.API.Icons
    for index = 1, #classes do
        local info = classes[index]
        if type(info.classFile) == "string" then
            local option = {
                text = YUI.Locale and YUI.Locale.GetClassName
                    and YUI.Locale:GetClassName(info.classFile, info.className or info.name or info.classFile)
                    or info.className or info.name or info.classFile,
                value = info.classFile,
            }
            if Icons and Icons.GetClassIcon then
                option.iconData = Icons.GetClassIcon(info.classFile)
                local coords = option.iconData and option.iconData.texCoord
                if coords then
                    local insetX = (coords[2] - coords[1]) * 0.05
                    local insetY = (coords[4] - coords[3]) * 0.05
                    option.texCoords = {
                        coords[1] + insetX,
                        coords[2] - insetX,
                        coords[3] + insetY,
                        coords[4] - insetY,
                    }
                end
                option.iconSize = 20
            end
            options[#options + 1] = option
        end
    end
    return options
end

function DesignerUI:BuildResourceSpecOptions()
    local options = {}
    if not (ResourceCatalog and ResourceCatalog.GetSpecializations) then
        return options
    end
    local classFile = Designer:GetResourcePreviewContext()
    local specs = ResourceCatalog:GetSpecializations(classFile)
    local Icons = YUI.API and YUI.API.Icons
    for index = 1, #specs do
        local info = specs[index]
        if info.specID then
            local option = {
                text = YUI.Locale and YUI.Locale.GetSpecializationName
                    and YUI.Locale:GetSpecializationName(info.specID, info.name or tostring(info.specID))
                    or info.name or tostring(info.specID),
                value = info.specID,
            }
            if Icons and Icons.GetScopedSpecIcon then
                option.iconData = Icons.GetScopedSpecIcon(
                    info.specID,
                    info.icon,
                    "settings"
                )
                if option.iconData and option.iconData.custom ~= true then
                    option.texCoords = { 0.08, 0.92, 0.08, 0.92 }
                end
                option.iconSize = 20
            elseif info.icon then
                option.icon = info.icon
                option.texCoords = { 0.08, 0.92, 0.08, 0.92 }
                option.iconSize = 20
            end
            options[#options + 1] = option
        end
    end
    return options
end

function DesignerUI:BuildResourceFormOptions()
    local options = {}
    if not (ResourceCatalog and ResourceCatalog.GetFormOptions) then
        return options
    end
    local classFile, specID = Designer:GetResourcePreviewContext()
    local forms = ResourceCatalog:GetFormOptions(classFile, specID)
    for index = 1, #forms do
        local form = forms[index]
        options[#options + 1] = {
            text = T(form.nameKey, form.key),
            value = form.key,
        }
    end
    return options
end

function DesignerUI:BuildNewGroupName()
    local profile = Designer:GetProfile()
    local items = profile and profile.groups and profile.groups.items or {}
    local used = {}
    for _, group in pairs(items) do
        used[GroupName(group)] = true
    end
    for index = 1, 999 do
        local name = string.format(
            T("designer.new_group_name", "新分组 %d"),
            index
        )
        if not used[name] then return name end
    end
    return string.format(
        T("designer.new_group_name", "新分组 %d"),
        1000
    )
end

function DesignerUI:ClearRestoreConfirm(hideOwned)
    local frame = self.restoreConfirmFrame
    local ownsFrame = self.restoreConfirmToken ~= nil
        and frame ~= nil
        and S.ConfirmFrame == frame
        and frame.onAccept == self.restoreConfirmAccept
        and frame.onCancel == self.restoreConfirmCancel
    if ownsFrame then
        if hideOwned == true and frame.IsShown and frame:IsShown() then
            frame:Hide()
        end
        frame.onAccept = nil
        frame.onCancel = nil
    end
    self.restoreConfirmToken = nil
    self.restoreConfirmFrame = nil
    self.restoreConfirmAccept = nil
    self.restoreConfirmCancel = nil
end


DesignerUI._internal = {
    GUI2 = GUI2,
    S = S,
    Designer = Designer,
    Catalog = Catalog,
    ResourceCatalog = ResourceCatalog,
    Glow = Glow,
    QUESTION_ICON = QUESTION_ICON,
    T = T,
    TC = TC,
    InCombat = InCombat,
    Print = Print,
    GroupName = GroupName,
    GroupTypeName = GroupTypeName,
    CountList = CountList,
    MONITOR_LAYOUTS = MONITOR_LAYOUTS,
    CanAddMonitor = CanAddMonitor,
    SetShown = SetShown,
    BuildDirectionOptions = BuildDirectionOptions,
    BuildAlignmentOptions = BuildAlignmentOptions,
    BuildIconAlignmentOptions = BuildIconAlignmentOptions,
    BuildRowDirectionOptions = BuildRowDirectionOptions,
    BuildWrapLayoutOptions = BuildWrapLayoutOptions,
    BuildOrientationOptions = BuildOrientationOptions,
    BuildDurationDirectionOptions = BuildDurationDirectionOptions,
    BuildResourceFillDirectionOptions = BuildResourceFillDirectionOptions,
    BuildIconPositionOptions = BuildIconPositionOptions,
    BuildShapeOptions = BuildShapeOptions,
    BuildBorderOptions = BuildBorderOptions,
    BuildFontOptions = BuildFontOptions,
    BuildOutlineOptions = BuildOutlineOptions,
    BuildTextPositionOptions = BuildTextPositionOptions,
    BuildNameTextPositionOptions = BuildNameTextPositionOptions,
    BuildNumberOptions = BuildNumberOptions,
    BuildGlowTriggerOptions = BuildGlowTriggerOptions,
    BuildGlowStyleOptions = BuildGlowStyleOptions,
    BuildNativeGlowStyleOptions = BuildNativeGlowStyleOptions,
    BuildGlowControlLabels = BuildGlowControlLabels,
    MonitorActionText = MonitorActionText,
    IsMonitorPickerFolder = IsMonitorPickerFolder,
    MonitorName = MonitorName,
    EntryIcon = EntryIcon,
}

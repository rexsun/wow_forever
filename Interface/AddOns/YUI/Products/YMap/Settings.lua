local YUI = _G.YUI
local YMap = YUI and YUI.YMap
local S = YUI and YUI.Settings
local GUI2 = YUI and YUI.GUI2
if not (YMap and S and S.RegisterModule) then return end
local LC = YUI.Locale:Get("Core")

local SETTINGS_ICON = 1064187
local MODULE_PAGE_LAYOUT = S.ModulePageLayout
    or { insetX = 20, titleTop = 20 }
local PAGE_INSET = MODULE_PAGE_LAYOUT.insetX
local SECTION_GAP = 18
local SECTION_HEADER_HEIGHT = 34
local SECTION_DIVIDER_GAP = 12
local NOTICE_GAP = 14
local BUTTON_LIST_WIDTH = 132
local BUTTON_LIST_GAP = 12
local BUTTON_LIST_ROW_HEIGHT = 30
local BUTTON_LIST_ROW_GAP = 5
local SPECIAL_LABEL_GRADIENT_START = { 0.84, 0.41, 1 }
local SPECIAL_LABEL_GRADIENT_END = { 0.64, 0.21, 0.93 }
local activeTab = "minimap"
local pageContext
local settingsActive = false
local selectedSquareElement = "drawer"
local Render
local ApplyLiveButtonPreview
local textPreview
local UpdateTextPreview
local componentGroupSelections = {text="clock",buttons="drawer"}

local TEXT_COMPONENT_KEYS = { clock=true, coordinates=true, metrics=true, zoneName=true }
local BUTTON_SETTINGS_ORDER = {
    "clock", "coordinates", "metrics", "zoneName",
    "drawer",
    "expansion",
    "tracking",
    "calendar",
    "mail",
    "crafting",
    "queue",
    "difficulty",
}

local NATIVE_BUTTON_SETTINGS_ORDER = {
    "drawer",
    "queue",
}

local function ResolveSelectedButtonSetting(minimap)
    if YUI.IsForever and selectedSquareElement == "diel" then return "diel" end
    if minimap and minimap.style == "square" then
        return selectedSquareElement
    end
    return selectedSquareElement == "queue" and "queue" or "drawer"
end

local function T(key, fallback)
    return YMap:T(key, fallback)
end

if YUI.IsForever then
    BUTTON_SETTINGS_ORDER[#BUTTON_SETTINGS_ORDER + 1] = "diel"
    NATIVE_BUTTON_SETTINGS_ORDER[#NATIVE_BUTTON_SETTINGS_ORDER + 1] = "diel"
end

local function DB()
    return YMap:GetDB()
end

local function Refresh(reason)
    YMap:Refresh(reason or "settings")
    if ApplyLiveButtonPreview then ApplyLiveButtonPreview() end
    if UpdateTextPreview then UpdateTextPreview() end
end

local function Rerender(parent)
    if not (parent and S.ClearConfig and Render) then return end
    S:ClearConfig(parent)
    Render(parent)
end

local function Check(parent, labelKey, get, set, reason, structural, label)
    return {
        type = "checkbox",
        id = labelKey,
        searchKey = labelKey,
        label = label or T(labelKey),
        get = get,
        set = function(value)
            set(value == true)
            Refresh(reason)
        end,
        onChange = structural and function()
            Rerender(parent)
        end or nil,
    }
end

local function Slider(labelKey, minimum, maximum, step, get, set, reason)
    return {
        type = "slider",
        searchKey = labelKey, label = T(labelKey),
        min = minimum,
        max = maximum,
        step = step,
        get = get,
        set = function(value)
            set(value)
            Refresh(reason)
        end,
    }
end

local function ButtonOffsetSlider(axis, get, set, reason)
    local field = Slider(
        axis == "x" and "settings.minimap.button_offset_x" or "settings.minimap.button_offset_y",
        -100,
        100,
        1,
        get,
        set,
        reason
    )
    field.tooltip = T("settings.minimap.button_offset_tooltip")
    return field
end

local function CopyColor(value, fallback)
    value = type(value) == "table" and value or fallback
    return {
        tonumber(value[1] or value.r) or fallback[1],
        tonumber(value[2] or value.g) or fallback[2],
        tonumber(value[3] or value.b) or fallback[3],
        tonumber(value[4] or value.a) or fallback[4],
    }
end

local function Color(labelKey, default, get, set, reason)
    return {
        type = "color",
        searchKey = labelKey, label = T(labelKey),
        field = true,
        hasAlpha = true,
        default = default,
        get = get,
        set = function(value)
            set(CopyColor(value, default))
            Refresh(reason)
        end,
    }
end

local function Texture(labelKey, get, set, reason)
    return {
        type = "texture",
        searchKey = labelKey, label = T(labelKey),
        get = get,
        set = function(value)
            set(value)
            Refresh(reason)
        end,
    }
end

local function Dropdown(parent, labelKey, options, get, set, reason, structural)
    return {
        type = "dropdown",
        searchKey = labelKey, label = T(labelKey),
        options = options,
        get = get,
        set = function(value)
            set(value)
            Refresh(reason)
        end,
        onChange = structural and function()
            Rerender(parent)
        end or nil,
    }
end

local function Action(labelKey, textKey, onClick, microIcon)
    return {
        type = "button",
        searchKey = labelKey, label = T(labelKey),
        text = T(textKey),
        microIcon = microIcon,
        tone = "default",
        onClick = onClick,
    }
end

local function GetLayout(width)
    local innerWidth = math.max(width, 320)
    local columns = innerWidth >= 620 and 2 or 1
    local columnGap = 24
    local labelWidth = 154
    local labelGap = 10
    local bodyWidth
    if columns == 2 then
        bodyWidth = math.floor((innerWidth - columnGap) / 2) - labelWidth - labelGap
    else
        bodyWidth = innerWidth - labelWidth - labelGap
    end
    return {
        innerWidth = innerWidth,
        columns = columns,
        columnGap = columnGap,
        labelWidth = labelWidth,
        labelGap = labelGap,
        bodyWidth = math.max(bodyWidth, 122),
    }
end

local function CreateSectionDivider(parent, width)
    local divider = GUI2:CreateDivider(parent, {
        width = width,
        height = 1,
    })
    divider.ymapSectionDivider = true
    return divider
end

local function RenderCard(parent, x, y, width, titleKey, iconName, fields, fieldGroups)
    local layout = GetLayout(width)
    local panel = GUI2:CreateFrame(parent, {
        width = width,
        height = 100,
    })
    panel:SetPoint("TOPLEFT", x, y)
    panel.ymapFlatSection = true

    local headerHeight = titleKey and SECTION_HEADER_HEIGHT or 0
    if titleKey then
        local icon = GUI2:CreateMicroIcon(panel, {
            iconName = iconName or "settings",
            size = 20,
            maxSize = 20,
            point = "TOPLEFT",
            relativePoint = "TOPLEFT",
            x = 0,
            y = -4,
        })
        local title = GUI2:CreateText(panel, T(titleKey), "font.size.md", "color.text.heading")
        title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        title:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
        title:SetJustifyH("LEFT")
        title:SetWordWrap(false)
        panel.ymapSectionTitleSizeKey = "font.size.md"

    end

    local fieldsHeight = 0
    local groups = fieldGroups or {
        {
            fields = fields,
            columns = layout.columns,
        },
    }
    for index, group in ipairs(groups) do
        local columns = math.min(group.columns or layout.columns, layout.columns)
        local bodyWidth = layout.bodyWidth
        if columns == 1 then
            bodyWidth = math.max(layout.innerWidth - layout.labelWidth - layout.labelGap, 122)
        end
        local _, _, groupHeight = S:RenderAlignedFields(panel, {
            fields = group.fields,
            x = 0,
            y = -headerHeight - fieldsHeight,
            width = layout.innerWidth,
            columns = columns,
            labelWidth = layout.labelWidth,
            labelGap = layout.labelGap,
            bodyWidth = bodyWidth,
            valueWidth = 54,
            valueGap = 8,
            rowHeight = 32,
            rowGap = 10,
            columnGap = layout.columnGap,
            minBodyWidth = 122,
        })
        fieldsHeight = fieldsHeight + (groupHeight or 0)
        if index < #groups then fieldsHeight = fieldsHeight + 10 end
    end

    local divider = CreateSectionDivider(panel, width)
    divider:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -headerHeight - fieldsHeight - SECTION_DIVIDER_GAP)
    local height = headerHeight + fieldsHeight + SECTION_DIVIDER_GAP + 1
    panel:SetHeight(height)
    return y - height - SECTION_GAP
end

local function RenderNotice(parent, x, y, width, text, warning)
    local panel = GUI2:CreatePanel(parent, {
        width = width,
        height = 62,
        surface = "color.surface.raised",
        border = "color.border.default",
    })
    panel:SetPoint("TOPLEFT", x, y)

    local icon = GUI2:CreateMicroIcon(panel, {
        iconName = warning and "eye-off" or "shield",
        size = 20,
        maxSize = 20,
        point = "LEFT",
        relativePoint = "LEFT",
        x = 14,
        y = 0,
    })
    local message = GUI2:CreateText(panel, text, "font.size.md", warning and "color.state.warning" or "color.text.secondary")
    message:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    message:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
    message:SetJustifyH("LEFT")
    message:SetWordWrap(true)
    return y - 62 - NOTICE_GAP
end

local function ButtonSettingLabel(key)
    local label = T("settings.minimap.square_element." .. key)
    if key == "drawer" and YUI.F and type(YUI.F.GetGradientText) == "function" then
        return YUI.F:GetGradientText(label, SPECIAL_LABEL_GRADIENT_START, SPECIAL_LABEL_GRADIENT_END)
    end
    return label
end

local function AnchorOptions()
    return {
        { text = T("settings.option.top_left"), value = "TOPLEFT" },
        { text = T("settings.option.top_right"), value = "TOPRIGHT" },
        { text = T("settings.option.bottom_left"), value = "BOTTOMLEFT" },
        { text = T("settings.option.bottom_right"), value = "BOTTOMRIGHT" },
    }
end

local function ZoneNameModeOptions()
    return {
        { text = T("settings.option.clock_never"), value = "never" },
        { text = T("settings.option.zone_name_hover"), value = "hover" },
        { text = T("settings.option.zone_name_always"), value = "always" },
    }
end

local function ClockModeOptions()
    return {
        { text = T("settings.option.clock_never"), value = "never" },
        { text = T("settings.option.clock_always"), value = "always" },
        { text = T("settings.option.clock_hover"), value = "hover" },
    }
end

local function ClockPositionOptions()
    return {
        { text = T("settings.option.top_left"), value = "TOPLEFT" },
        { text = T("settings.option.top_center"), value = "TOP" },
        { text = T("settings.option.top_right"), value = "TOPRIGHT" },
        { text = T("settings.option.left_center"), value = "LEFT" },
        { text = T("settings.option.center"), value = "CENTER" },
        { text = T("settings.option.right_center"), value = "RIGHT" },
        { text = T("settings.option.bottom_left"), value = "BOTTOMLEFT" },
        { text = T("settings.option.bottom_center"), value = "BOTTOM" },
        { text = T("settings.option.bottom_right"), value = "BOTTOMRIGHT" },
    }
end

local function CoordinateDisplayModeOptions()
    return {
        { text = T("settings.option.coordinate_always"), value = "always" },
        { text = T("settings.option.coordinate_hover"), value = "hover" },
    }
end

local function CoordinatePositionOptions() return ClockPositionOptions() end

local function StatusBarPositionOptions()
    return {
        { text = T("settings.option.position_bottom"), value = "bottom" },
        { text = T("settings.option.position_top"), value = "top" },
        { text = T("settings.option.position_left"), value = "left" },
        { text = T("settings.option.position_right"), value = "right" },
    }
end

local function StatusBarTextDisplayOptions()
    return {
        { text = T("settings.option.status_bar_text_hover"), value = "hover" },
        { text = T("settings.option.status_bar_text_always"), value = "always" },
    }
end

local function ClearLiveButtonPreview()
    textPreview=nil
    if YMap.Minimap and type(YMap.Minimap.ClearSettingsPreview) == "function" then
        YMap.Minimap:ClearSettingsPreview()
    end
    if YMap.ButtonDrawer and type(YMap.ButtonDrawer.SetSettingsPreview) == "function" then
        YMap.ButtonDrawer:SetSettingsPreview(false)
    end
end

local settingsPreviewRoot
local function EnsureSettingsPreviewRootLifecycle()
    local root = _G.YUI_SettingsFrame
    if not (root and root.HookScript) or settingsPreviewRoot == root then return end

    settingsPreviewRoot = root
    root:HookScript("OnHide", ClearLiveButtonPreview)
    root:HookScript("OnShow", function()
        if ApplyLiveButtonPreview then ApplyLiveButtonPreview() end
    end)
end

ApplyLiveButtonPreview = function()
    local db = DB()
    local minimap = db and db.minimap
    if not settingsActive or activeTab ~= "minimap" or not minimap or minimap.enabled ~= true then
        ClearLiveButtonPreview()
        return
    end

    local selectedKey = ResolveSelectedButtonSetting(minimap)
    if selectedKey == "drawer" then
        if YMap.Minimap and type(YMap.Minimap.ClearSettingsPreview) == "function" then
            YMap.Minimap:ClearSettingsPreview()
        end
        if YMap.ButtonDrawer and type(YMap.ButtonDrawer.SetSettingsPreview) == "function" then
            YMap.ButtonDrawer:SetSettingsPreview(DB().buttonDrawer.enabled == true)
        end
        return
    end

    if YMap.ButtonDrawer and type(YMap.ButtonDrawer.SetSettingsPreview) == "function" then
        YMap.ButtonDrawer:SetSettingsPreview(false)
    end
    if selectedKey == "queue" then
        if YMap.Minimap and type(YMap.Minimap.SetSettingsPreview) == "function" then
            YMap.Minimap:SetSettingsPreview("queue")
        end
        return
    end
    local elements = type(minimap.squareElements) == "table" and minimap.squareElements or {}
    local element = type(elements[selectedKey]) == "table" and elements[selectedKey] or nil
    local previewKey = element and element.hidden ~= true and selectedKey or nil
    if YMap.Minimap and type(YMap.Minimap.SetSettingsPreview) == "function" then
        YMap.Minimap:SetSettingsPreview(previewKey)
    end
end

local function BuildQueueButtonFields(parent, queue)
    local enabledField = Check(parent, "settings.minimap.queue_enabled", function()
        return queue.customLayout == true
    end, function(value)
        queue.customLayout = value
    end, "minimap-queue-layout", true)
    enabledField.tooltip = T("settings.minimap.queue_enabled_tooltip")
    local fields = { enabledField }
    if queue.customLayout ~= true then return fields end

    fields[#fields + 1] = Dropdown(parent, "settings.minimap.square_element_anchor", AnchorOptions(), function()
        return queue.anchor
    end, function(value)
        queue.anchor = value
    end, "minimap-queue-anchor")
    local sizeField = Slider("settings.minimap.queue_size", 8, 64, 1, function()
        return tonumber(queue.size) or 32
    end, function(value)
        queue.size = math.floor((tonumber(value) or 32) + 0.5)
    end, "minimap-queue-size")
    sizeField.id = "settings.minimap.queue_size"
    sizeField.label = LC["common.size"] or "Size"
    fields[#fields + 1] = sizeField
    fields[#fields + 1] = ButtonOffsetSlider("x", function()
        return queue.offsetX
    end, function(value)
        queue.offsetX = value
    end, "minimap-queue-offset")
    fields[#fields + 1] = ButtonOffsetSlider("y", function()
        return queue.offsetY
    end, function(value)
        queue.offsetY = value
    end, "minimap-queue-offset")
    return fields
end

local function BuildNativeButtonFields(parent, minimap, drawer)
    local elements = minimap.squareElements or {}
    local selected = elements[selectedSquareElement] or {}
    local collectedByDrawer = selectedSquareElement == "expansion"
        and type(drawer) == "table"
        and drawer.enabled == true
    local hiddenField = Check(parent, "settings.minimap.square_element_hidden", function()
        return selected.hidden == true
    end, function(value)
        selected.hidden = value
    end, "minimap-square-element-visibility", collectedByDrawer or selectedSquareElement == "tracking")
    if selectedSquareElement == "expansion" then
        hiddenField.tooltip = T("settings.minimap.expansion_hidden_tooltip")
    end
    local fields = {
        hiddenField,
    }
    if YUI.IsForever and selectedSquareElement == "diel" and minimap.style ~= "square" then
        return fields
    end
    if collectedByDrawer then
        if selected.hidden ~= true then
            fields[#fields + 1] = {
                type = "text",
                label = T("settings.minimap.expansion_collected"),
                colorKey = "color.state.success",
            }
        end
        return fields
    end
    fields[#fields + 1] = Dropdown(parent, "settings.minimap.square_element_anchor", AnchorOptions(), function()
        return selected.anchor
    end, function(value)
        selected.anchor = value
    end, "minimap-square-element-layout")
    fields[#fields + 1] = Slider("settings.minimap.square_element_scale", 0.5, 2, 0.05, function()
        return selected.scale
    end, function(value)
        selected.scale = value
    end, "minimap-square-element-layout")
    fields[#fields + 1] = ButtonOffsetSlider("x", function()
        return selected.offsetX
    end, function(value)
        selected.offsetX = value
    end, "minimap-square-element-layout")
    fields[#fields + 1] = ButtonOffsetSlider("y", function()
        return selected.offsetY
    end, function(value)
        selected.offsetY = value
    end, "minimap-square-element-layout")
    if selectedSquareElement == "difficulty" then
        fields[#fields + 1] = Dropdown(parent, "settings.minimap.difficulty_text_style", {
            { text = T("settings.option.difficulty_en"), value = "en" },
            { text = T("settings.option.difficulty_zh"), value = "zh" },
        }, function()
            return selected.textStyle == "zh" and "zh" or "en"
        end, function(value)
            selected.textStyle = value == "zh" and "zh" or "en"
        end, "minimap-difficulty-text-style", true)
    end
    if selectedSquareElement == "tracking" then
        fields[#fields + 1] = Check(parent, "settings.minimap.tracking_right_click", function()
            return selected.rightClickOpen ~= false
        end, function(value)
            selected.rightClickOpen = value
        end, "minimap-tracking-right-click", true)
        local hintField = Check(parent, "settings.minimap.tracking_right_click_hint", function()
            return selected.rightClickHint == true
        end, function(value)
            selected.rightClickHint = value
        end, "minimap-tracking-right-click-hint")
        hintField.disabled = selected.hidden ~= true or selected.rightClickOpen == false
        fields[#fields + 1] = hintField
    end
    return fields
end

local function BuildDrawerButtonFields(parent, drawer)
    local triggerHiddenByMode = drawer.enabled == true and drawer.expandMode == "hoverPanel"
    local fields = {
        Check(parent, "settings.button_drawer.enabled", function()
            return drawer.enabled == true
        end, function(value)
            drawer.enabled = value
        end, "button-drawer-enabled", true),
    }
    if drawer.enabled == true then
        if not triggerHiddenByMode then
            fields[#fields + 1] = Dropdown(parent, "settings.minimap.square_element_anchor", {
                { text = T("settings.option.top_left"), value = "topLeft" },
                { text = T("settings.option.top_right"), value = "topRight" },
                { text = T("settings.option.bottom_left"), value = "bottomLeft" },
                { text = T("settings.option.bottom_right"), value = "bottomRight" },
            }, function()
                return drawer.triggerPosition
            end, function(value)
                drawer.triggerPosition = value
            end, "button-drawer-layout")
            fields[#fields + 1] = Slider("settings.minimap.square_element_scale", 0.5, 2, 0.05, function()
                return (tonumber(drawer.triggerSize) or 20) / 20
            end, function(value)
                drawer.triggerSize = math.floor((tonumber(value) or 1) * 20 + 0.5)
            end, "button-drawer-layout")
            fields[#fields + 1] = ButtonOffsetSlider("x", function()
                return drawer.triggerOffsetX
            end, function(value)
                drawer.triggerOffsetX = value
            end, "button-drawer-layout")
            fields[#fields + 1] = ButtonOffsetSlider("y", function()
                return drawer.triggerOffsetY
            end, function(value)
                drawer.triggerOffsetY = value
            end, "button-drawer-layout")
        end
        fields[#fields + 1] = Dropdown(parent, "settings.button_drawer.expand_mode", {
            { text = T("settings.option.hover_icon"), value = "hoverIcon" },
            { text = T("settings.option.hover_panel"), value = "hoverPanel" },
            { text = T("settings.option.click"), value = "click" },
        }, function()
            return drawer.expandMode
        end, function(value)
            drawer.expandMode = value
        end, "button-drawer-behavior", true)
        fields[#fields + 1] = Dropdown(parent, "settings.button_drawer.layout_direction", {
            { text = T("settings.option.right_down"), value = "rightDown" },
            { text = T("settings.option.left_down"), value = "leftDown" },
            { text = T("settings.option.right_up"), value = "rightUp" },
            { text = T("settings.option.left_up"), value = "leftUp" },
            { text = T("settings.option.down_right"), value = "downRight" },
            { text = T("settings.option.down_left"), value = "downLeft" },
            { text = T("settings.option.up_right"), value = "upRight" },
            { text = T("settings.option.up_left"), value = "upLeft" },
        }, function()
            return drawer.layoutDirection
        end, function(value)
            drawer.layoutDirection = value
        end, "button-drawer-layout", true)
        local vertical = drawer.layoutDirection == "downRight"
            or drawer.layoutDirection == "downLeft"
            or drawer.layoutDirection == "upRight"
            or drawer.layoutDirection == "upLeft"
        fields[#fields + 1] = Slider(
            vertical and "settings.button_drawer.items_per_column" or "settings.button_drawer.items_per_row",
            1,
            16,
            1,
            function()
                return drawer.itemsPerLine
            end,
            function(value)
                drawer.itemsPerLine = value
            end,
            "button-drawer-layout"
        )
        fields[#fields + 1] = Dropdown(parent, "settings.button_drawer.background", {
            { text = T("settings.option.none"), value = "none" },
            { text = T("settings.option.solid"), value = "solid" },
            { text = T("settings.option.transparent"), value = "transparent" },
        }, function()
            return drawer.panelBackground
        end, function(value)
            drawer.panelBackground = value
        end, "button-drawer-layout")
        fields[#fields + 1] = Slider("settings.button_drawer.panel_padding", 0, 16, 1, function()
            return drawer.panelPadding
        end, function(value)
            drawer.panelPadding = value
        end, "button-drawer-layout")
        fields[#fields + 1] = Slider("settings.button_drawer.icon_size", 16, 64, 1, function()
            return drawer.iconSize
        end, function(value)
            drawer.iconSize = value
        end, "button-drawer-layout")
        fields[#fields + 1] = Slider("settings.button_drawer.spacing_x", 0, 24, 1, function()
            return drawer.spacingX
        end, function(value)
            drawer.spacingX = value
        end, "button-drawer-layout")
        fields[#fields + 1] = Slider("settings.button_drawer.spacing_y", 0, 24, 1, function()
            return drawer.spacingY
        end, function(value)
            drawer.spacingY = value
        end, "button-drawer-layout")
    end
    return fields, triggerHiddenByMode and T("settings.button_drawer.hover_panel_trigger_hidden") or nil
end

local function RenderDifficultyStylePreview(parent, x, y, width, textStyle)
    local styles = YMap.Minimap and YMap.Minimap.DIFFICULTY_PREVIEW_STYLES
    if type(styles) ~= "table" or #styles == 0 then return 0 end

    textStyle = textStyle == "zh" and "zh" or "en"
    local columns = width >= 520 and 4 or 3
    local rows = math.ceil(#styles / columns)
    local height = 42 + rows * 32
    local preview = GUI2:CreateFrame(parent, {
        width = width,
        height = height,
    })
    preview:SetPoint("TOPLEFT", x, y)
    preview.ymapDifficultyStylePreview = true
    preview.ymapFlatPreview = true
    preview.ymapDifficultyStyleLabels = {}
    preview.ymapDifficultyStyleMeanings = {}

    local titleText = T("settings.minimap.difficulty_preview_title")
    local title = GUI2:CreateText(preview, titleText, "font.size.md", "color.text.heading")
    title:SetPoint("TOPLEFT", preview, "TOPLEFT", 10, -8)
    title:SetPoint("RIGHT", preview, "RIGHT", -10, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    preview.ymapDifficultyStyleTitle = titleText

    local cellWidth = math.floor((width - 20) / columns)
    for index, style in ipairs(styles) do
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local left = 10 + column * cellWidth
        local top = -35 - row * 32
        local label = YMap.Minimap:GetDifficultyStyleLabel(
            style.id,
            textStyle,
            8,
            style.sampleGroupSize
        )
        local meaning = T("difficulty.meaning." .. style.id)

        local code = GUI2:CreateText(preview, label, "font.size.lg", "color.text.primary")
        YMap.Minimap:ApplyDifficultyTextStyle(code)
        code:SetPoint("TOPLEFT", preview, "TOPLEFT", left, top)
        code:SetWidth(54)
        code:SetJustifyH("CENTER")
        code:SetWordWrap(false)
        code:SetTextColor(style.red, style.green, style.blue, 1)

        local description = GUI2:CreateText(preview, meaning, "font.size.sm", "color.text.secondary")
        description:SetPoint("LEFT", code, "RIGHT", 6, 0)
        description:SetWidth(cellWidth - 64)
        description:SetJustifyH("LEFT")
        description:SetWordWrap(false)

        preview.ymapDifficultyStyleLabels[index] = label
        preview.ymapDifficultyStyleMeanings[index] = meaning
    end
    return height
end

local function BuildTextComponentFields(parent, appearance, key)
    local config = key == "clock" and appearance.clock or key == "zoneName" and appearance.zoneName or appearance[key]
    local fields = {}
    local prefix = "settings.minimap."
    local reason = "minimap-text-" .. key
    local enabled
    if key == "clock" then
        fields[1] = Dropdown(parent, prefix .. "clock_display", ClockModeOptions(),
            function() return appearance.clockMode end, function(v) appearance.clockMode=v end, reason, true)
        enabled = appearance.clockMode ~= "never"
    elseif key == "zoneName" then
        fields[1] = Dropdown(parent, prefix .. "zone_name_display", ZoneNameModeOptions(),
            function() return appearance.zoneNameMode end, function(v) appearance.zoneNameMode=v end, reason, true)
        enabled = appearance.zoneNameMode ~= "never"
    else
        local enabledKey = key == "coordinates" and "coordinates_enabled" or "metrics_enabled"
        fields[1] = Check(parent, prefix .. enabledKey, function() return config.enabled end,
            function(v) config.enabled=v end, reason, true)
        enabled = config.enabled
    end
    if not enabled then return fields end
    if key == "metrics" then
        fields[#fields+1] = Check(parent, prefix .. "metrics_fps", function() return config.showFPS end,
            function(v) config.showFPS=v end, reason)
        fields[#fields+1] = Check(parent, prefix .. "metrics_latency", function() return config.showLatency end,
            function(v) config.showLatency=v end, reason)
    end
    if key == "metrics" or key == "coordinates" then
        fields[#fields+1] = Dropdown(parent, prefix .. key .. "_display", CoordinateDisplayModeOptions(),
            function() return config.displayMode end, function(v) config.displayMode=v end, reason)
    end
    if key == "metrics" then
        if config.colorMode == nil then config.colorMode=config.customColor and "fixed" or "threshold" end
        local display=YUI.SystemMetrics.Display
        display:Normalize(config)
        local presentationFields=display:BuildFields(function() return config end, function(changedKey)
            config.customColor=config.colorMode=="fixed"
            Refresh(reason)
            if changedKey=="colorMode" then Rerender(parent) end
        end, {allowColorMode=true,hasAlpha=true})
        for _,field in ipairs(presentationFields) do fields[#fields+1]=field end
    end
    fields[#fields+1] = {
        type="font", searchKey=prefix .. "text_font", label=T(prefix .. "text_font"),
        prependOptions={{text=T(prefix .. "text_inherit"), value="inherit"}},
        get=function() return config.font or "inherit" end,
        set=function(v) config.font=v; Refresh(reason) end,
    }
    local sizeKey = key == "zoneName" and "zone_name_font_size"
        or key == "clock" and "text_font_size" or key .. "_font_size"
    local sizeField = Slider(prefix .. sizeKey, key == "clock" and 0 or 8, 24, 1,
        function() return key == "zoneName" and appearance.zoneNameFontSize or config.fontSize end,
        function(v) if key == "zoneName" then appearance.zoneNameFontSize=v else config.fontSize=v end end, reason)
    if key == "clock" then sizeField.tooltip=T(prefix .. "text_clock_size_hint") end
    fields[#fields+1] = sizeField
    fields[#fields+1] = Dropdown(parent, prefix .. "text_outline", GUI2.Form:BuildFontOutlineOptions({
        prependOptions={{text=T(prefix .. "text_inherit"),value="inherit"}},
    }), function() return YMap.TextComponents:GetOutlineSelection(config) end, function(v)
        config.outline=v
        config.shadow=v=="inherit" and "inherit" or "off"
    end, reason)
    if key ~= "metrics" then
        fields[#fields+1] = Check(parent, prefix .. "text_custom_color", function() return config.customColor end,
            function(v) config.customColor=v end, reason, true)
        if config.customColor then
            fields[#fields+1] = Color(prefix .. "text_color", {1,1,1,1},
                function() return config.color end, function(v) config.color=v end, reason)
        end
    end
    fields[#fields+1] = Dropdown(parent, prefix .. "text_layout", {
        {text=T(prefix .. "text_layout_auto"),value="auto"}, {text=T(prefix .. "text_layout_custom"),value="custom"},
    }, function() return config.layoutMode end, function(v) config.layoutMode=v end, reason, true)
    local positionKey = key == "clock" and "clock_position" or key == "zoneName" and "text_position" or key .. "_position"
    fields[#fields+1] = Dropdown(parent, prefix .. positionKey, ClockPositionOptions(),
        function() return key == "clock" and appearance.clockPosition or config.position end,
        function(v) if key == "clock" then appearance.clockPosition=v else config.position=v end end, reason)
    local offsetPrefix=config.layoutMode=="custom" and "offset" or "autoOffset"
    for _, axis in ipairs({"X","Y"}) do
        local field=Slider(prefix .. "text_offset_" .. axis:lower(), -200, 200, 1,
            function() return config[offsetPrefix .. axis] or 0 end, function(v) config[offsetPrefix .. axis]=v end, reason)
        field.tooltip=T(prefix .. "text_offset_hint")
        fields[#fields+1]=field
    end
    if key == "metrics" then
        fields[#fields+1] = Slider(prefix .. "text_spacing",8,32,1,
            function() return config.spacing end, function(v) config.spacing=v end, reason)
    end
    fields[#fields+1] = Action(prefix .. "text_reset", prefix .. "text_reset", function()
        local defaults=YMap.Defaults.minimap.squareAppearance
        local source=defaults[key]
        for _, name in ipairs({"font","fontSize","outline","shadow","customColor","color","layoutMode",
            "position","offsetX","offsetY","autoOffsetX","autoOffsetY","spacing","fpsColor","latencyColor"}) do
            if source[name] ~= nil then config[name]=YMap:CopyValue(source[name]) end
        end
        if key=="clock" then appearance.clockPosition=defaults.clockPosition end
        if key=="zoneName" then appearance.zoneNameFontSize=defaults.zoneNameFontSize end
        if key=="metrics" then
            for _,name in ipairs({"displayStyle","fpsBadBelow","fpsSmoothFrom","latencySmoothBelow",
                "latencyBadFrom","colorSmooth","colorLag","colorBad"}) do config[name]=YMap:CopyValue(source[name]) end
            config.colorMode="threshold"
        end
        Refresh(reason); Rerender(parent)
    end)
    return fields
end

local function RenderTextComponentPreview(parent, x, y, width, appearance, key)
    local sample=GUI2:CreateText(parent, T("settings.minimap.text_preview"), "font.size.sm", "color.text.muted")
    sample:SetPoint("TOPLEFT",x,y)
    local config=key=="clock" and appearance.clock or key=="zoneName" and appearance.zoneName or appearance[key]
    local samples=key=="metrics" and {"120 FPS", "35 ms"}
        or {key=="clock" and "12:34" or key=="coordinates" and "48.2, 36.7" or T("settings.minimap.text_zone_sample")}
    local previous
    textPreview={appearance=appearance,key=key,texts={},x=x,y=y-25}
    for index,value in ipairs(samples) do
        local text=GUI2:CreateText(parent,value,"font.size.md","color.text.primary")
        if previous then text:SetPoint("LEFT",previous,"RIGHT",config.spacing or 12,0)
        else text:SetPoint("TOPLEFT",x,y-25) end
        if YMap.TextComponents then
            local color
            if key=="metrics" then color=false end
            YMap.TextComponents:Apply(text,config,key=="zoneName" and appearance.zoneNameFontSize or nil,color)
        end
        previous=text
        textPreview.texts[index]=text
    end
    UpdateTextPreview()
    return 64
end

UpdateTextPreview = function()
    if not textPreview or not YMap.TextComponents then return end
    local appearance,key = textPreview.appearance,textPreview.key
    local config=key=="clock" and appearance.clock or key=="zoneName" and appearance.zoneName or appearance[key]
    for index,text in ipairs(textPreview.texts) do
        local color
        if key=="metrics" then color=false end
        YMap.TextComponents:Apply(text,config,key=="zoneName" and appearance.zoneNameFontSize or nil,color)
        if key=="metrics" then
            text:SetText(YUI.SystemMetrics.Display:FormatText(config.displayStyle,index==1 and "FPS" or "LATENCY",
                index==1 and 120 or 35,config,nil,config.fontSize+2))
            local shown=index==1 and config.showFPS or index==2 and config.showLatency
            if shown then text:Show() else text:Hide() end
            text:ClearAllPoints()
            if index==2 and config.showFPS then
                text:SetPoint("LEFT",textPreview.texts[1],"RIGHT",config.spacing or 12,0)
            else
                text:SetPoint("TOPLEFT",textPreview.x,textPreview.y)
            end
        end
    end
end

local function RenderButtonSettingsCard(parent, x, y, width, minimap, drawer)
    textPreview=nil
    local squareMode = minimap.style == "square"
    local buttonOrder = squareMode and BUTTON_SETTINGS_ORDER or NATIVE_BUTTON_SETTINGS_ORDER
    local selectedKey = ResolveSelectedButtonSetting(minimap)
    local panel = GUI2:CreateFrame(parent, {
        width = width,
        height = 100,
    })
    panel:SetPoint("TOPLEFT", x, y)
    panel.ymapFlatSection = true

    local icon = GUI2:CreateMicroIcon(panel, {
        iconName = "panels-top-left",
        size = 20,
        maxSize = 20,
        point = "TOPLEFT",
        relativePoint = "TOPLEFT",
        x = 0,
        y = -4,
    })
    local title = GUI2:CreateText(panel, T("settings.section.minimap_square_elements"), "font.size.md", "color.text.heading")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    panel.ymapSectionTitleSizeKey = "font.size.md"

    local contentWidth = width
    local listWidth = math.min(BUTTON_LIST_WIDTH, math.floor(contentWidth * 0.22))
    local rightWidth = contentWidth - listWidth - BUTTON_LIST_GAP
    local list = GUI2:CreateFrame(panel,{width=listWidth,height=390})
    list:SetPoint("TOPLEFT",0,-SECTION_HEADER_HEIGHT)
    local selectedGroup=TEXT_COMPONENT_KEYS[selectedKey] and "text" or "buttons"
    local listY=8
    if squareMode then
        componentGroupSelections[selectedGroup]=selectedKey
        for index,group in ipairs({"text","buttons"}) do
            local tab=GUI2.Form:CreateButton(list,{
                width=(listWidth-20)/2,height=26,fontSizeKey="font.size.sm",
                text=T(group=="text" and "settings.minimap.group_text_short" or "settings.minimap.group_buttons_short"),
                tooltip=T(group=="text" and "settings.minimap.text_group" or "settings.minimap.button_group"),
                state=selectedGroup==group and "selected" or "normal",
                onClick=function()
                    selectedSquareElement=componentGroupSelections[group]
                    Rerender(parent)
                    ApplyLiveButtonPreview()
                end,
            })
            tab:SetPoint("TOPLEFT",8+(index-1)*(listWidth-12)/2,-8)
            tab.ymapComponentGroup=group
        end
        listY=46
    end

    for index = 1, #buttonOrder do
        local key = buttonOrder[index]
        if not squareMode or (TEXT_COMPONENT_KEYS[key] and "text" or "buttons")==selectedGroup then
            local button = GUI2.Form:CreateButton(list, {
                width = listWidth - 16,
                height = BUTTON_LIST_ROW_HEIGHT,
                text = ButtonSettingLabel(key),
                tone = "default",
                state = selectedKey == key and "selected" or "normal",
                contentAlign = "left",
                justifyH = "LEFT",
                onClick = function()
                    selectedSquareElement = key
                    Rerender(parent)
                    ApplyLiveButtonPreview()
                end,
            })
            button:SetPoint("TOPLEFT", 8, -listY)
            listY=listY+BUTTON_LIST_ROW_HEIGHT+BUTTON_LIST_ROW_GAP
            button.ymapButtonSettingKey = key
        end
    end

    local rightScroll=GUI2:CreateScrollFrame(panel,{autoHide=true,width=rightWidth,height=390,
        childWidth=rightWidth-16,childHeight=390})
    rightScroll:SetPoint("TOPLEFT",list,"TOPRIGHT",BUTTON_LIST_GAP,0)
    local right=rightScroll.child

    local fields
    local drawerNotice
    if TEXT_COMPONENT_KEYS[selectedKey] then
        fields=BuildTextComponentFields(parent,minimap.squareAppearance,selectedKey)
    elseif selectedKey == "drawer" then
        fields, drawerNotice = BuildDrawerButtonFields(parent, drawer)
    elseif selectedKey == "queue" then
        fields = BuildQueueButtonFields(parent, minimap.queue)
    else
        fields = BuildNativeButtonFields(parent, minimap, drawer)
    end
    local primaryFields = { fields[1] }
    local trackingFields = selectedKey == "tracking" and { fields[#fields - 1], fields[#fields] } or nil
    local detailFields = {}
    for index = 2, #fields - (trackingFields and 2 or 0) do
        detailFields[#detailFields + 1] = fields[index]
    end
    local rightInsetLeft = 12
    local rightInsetRight = 20
    local rightInnerWidth = rightWidth - 16 - rightInsetLeft - rightInsetRight
    local columns = rightInnerWidth >= 452 and 2 or 1
    local columnGap = 16
    local columnWidth = math.floor((rightInnerWidth - (columns - 1) * columnGap) / columns)
    local labelWidth = columns == 2 and 96 or math.min(146, math.floor(columnWidth * 0.42))
    local labelGap = 8
    local bodyWidth = columnWidth - labelWidth - labelGap
    local valueWidth = 48
    local valueGap = 6
    local minimumBodyWidth = 60 + valueGap + valueWidth
    local rowHeight = 32
    local rowGap = 10
    local fixedContentHeight = 390
    panel.ymapComponentNavigation=list
    panel.ymapComponentNavigationContentHeight=listY+8
    panel.ymapComponentDetailScroll=rightScroll
    local verticalDivider = GUI2:CreateTexture(panel, {
        layer = "ARTWORK",
    })
    GUI2:SetTexturePaintKey(verticalDivider, "color.border.subtle")
    verticalDivider:SetWidth(
        GUI2.GetPixelSize and GUI2:GetPixelSize(verticalDivider, 1, 1) or 1
    )
    verticalDivider:SetPoint("TOP", list, "TOPRIGHT", math.floor(BUTTON_LIST_GAP / 2), 0)
    verticalDivider:SetPoint("BOTTOM", list, "BOTTOMRIGHT", math.floor(BUTTON_LIST_GAP / 2), 0)
    panel.ymapButtonSettingsCard = true
    panel.ymapButtonSettingsContentHeight = fixedContentHeight
    panel.ymapButtonSettingsDivider = verticalDivider
    list.ymapButtonSettingsList = true
    right.ymapButtonSettingsDetails = true
    local _, _, primaryHeight = S:RenderAlignedFields(right, {
        fields = primaryFields,
        x = rightInsetLeft,
        y = -12,
        width = rightInnerWidth,
        columns = 1,
        columnWidth = columnWidth,
        labelWidth = labelWidth,
        labelGap = labelGap,
        bodyWidth = bodyWidth,
        valueWidth = valueWidth,
        valueGap = valueGap,
        rowHeight = rowHeight,
        rowGap = rowGap,
        columnGap = columnGap,
        minBodyWidth = minimumBodyWidth,
    })
    local fieldsHeight = primaryHeight or 0
    if drawerNotice then
        local notice = GUI2:CreateText(right, drawerNotice, "font.size.md", "color.text.secondary")
        notice:SetPoint("TOPLEFT", right, "TOPLEFT", rightInsetLeft, -12 - fieldsHeight - rowGap)
        notice:SetWidth(rightInnerWidth)
        notice:SetJustifyH("LEFT")
        notice:SetWordWrap(false)
        notice.ymapDrawerHoverPanelNotice = true
        right.ymapDrawerHoverPanelNotice = notice
        fieldsHeight = fieldsHeight + rowGap + rowHeight
    end
    if #detailFields > 0 then
        local _, _, detailHeight = S:RenderAlignedFields(right, {
            fields = detailFields,
            x = rightInsetLeft,
            y = -12 - fieldsHeight - rowGap,
            width = rightInnerWidth,
            columns = columns,
            columnWidth = columnWidth,
            labelWidth = labelWidth,
            labelGap = labelGap,
            bodyWidth = bodyWidth,
            valueWidth = valueWidth,
            valueGap = valueGap,
            rowHeight = rowHeight,
            rowGap = rowGap,
            columnGap = columnGap,
            minBodyWidth = minimumBodyWidth,
        })
        fieldsHeight = fieldsHeight + rowGap + (detailHeight or 0)
    end

    if trackingFields then
        local _, _, trackingHeight = S:RenderAlignedFields(right, {
            fields = trackingFields,
            x = rightInsetLeft,
            y = -12 - fieldsHeight - rowGap,
            width = rightInnerWidth,
            columns = 1,
            columnWidth = columnWidth,
            labelWidth = labelWidth,
            labelGap = labelGap,
            bodyWidth = bodyWidth,
            valueWidth = valueWidth,
            valueGap = valueGap,
            rowHeight = rowHeight,
            rowGap = rowGap,
            minBodyWidth = minimumBodyWidth,
        })
        fieldsHeight = fieldsHeight + rowGap + (trackingHeight or 0)
    end
    if selectedKey == "difficulty" then
        local difficulty = minimap.squareElements and minimap.squareElements.difficulty or nil
        local previewHeight = RenderDifficultyStylePreview(
            right,
            rightInsetLeft,
            -12 - fieldsHeight - rowGap,
            rightInnerWidth,
            difficulty and difficulty.textStyle
        )
        if previewHeight > 0 then
            fieldsHeight = fieldsHeight + rowGap + previewHeight
        end
    end

    if TEXT_COMPONENT_KEYS[selectedKey] then
        fieldsHeight=fieldsHeight+rowGap+RenderTextComponentPreview(right,rightInsetLeft,-12-fieldsHeight-rowGap,
            rightInnerWidth,minimap.squareAppearance,selectedKey)
    end
    right:SetHeight(math.max(fixedContentHeight,fieldsHeight+24))
    local divider = CreateSectionDivider(panel, width)
    divider:SetPoint(
        "TOPLEFT",
        panel,
        "TOPLEFT",
        0,
        -SECTION_HEADER_HEIGHT - fixedContentHeight - SECTION_DIVIDER_GAP
    )
    local height = SECTION_HEADER_HEIGHT + fixedContentHeight + SECTION_DIVIDER_GAP + 1
    panel:SetHeight(height)
    return y - height - SECTION_GAP
end

local function RenderMinimapTab(parent, x, y, width)
    local db = DB()
    local minimap = db.minimap
    local belowWidget = minimap.belowWidget
    local drawer = db.buttonDrawer
    local conflictReason = YMap:GetMinimapConflictReason()
    local rawConflict = YMap.Minimap and YMap.Minimap.GetConflictReason and YMap.Minimap:GetConflictReason()

    if minimap.enabled == true and (rawConflict == "MinimapParent" or rawConflict == "GetMinimapShape") then
        local controller = YMap.Minimap.GetConflictController
            and YMap.Minimap:GetConflictController()
        local notice = GUI2:CreateText(
            parent,
            S:FormatYieldNotice("minimap", controller),
            "font.size.md",
            "color.text.primary"
        )
        notice:SetPoint("TOPLEFT", x, y)
        notice:SetWidth(width)
        notice:SetJustifyH("LEFT")
        notice:SetWordWrap(true)
        return y - math.max(notice:GetStringHeight() or 20, 20) - NOTICE_GAP, true
    end

    if minimap.enabled == true and rawConflict == "ExternalMinimap" then
        local controller = YMap.Minimap.GetConflictController
            and YMap.Minimap:GetConflictController()
        local notice = GUI2:CreateText(
            parent,
            S:FormatYieldNotice("minimap", controller),
            "font.size.md",
            "color.text.primary"
        )
        notice:SetPoint("TOPLEFT", x, y)
        notice:SetWidth(width)
        notice:SetJustifyH("LEFT")
        notice:SetWordWrap(true)
        return y - math.max(notice:GetStringHeight() or 20, 20) - NOTICE_GAP, true
    end

    if minimap.enabled == true and conflictReason then
        y = RenderNotice(parent, x, y, width, T("settings.conflict") .. ": " .. conflictReason, true)
    end

    local enabledField = Check(parent, "settings.minimap.enabled", function()
        return minimap.enabled == true
    end, function(value)
        minimap.enabled = value
    end, "minimap-enabled", true, LC["common.enable"])
    local detailFields = {}
    if minimap.enabled == true then
        detailFields[#detailFields + 1] = Dropdown(parent, "settings.minimap.style", {
            { text = T("settings.option.native"), value = "native" },
            { text = T("settings.option.square"), value = "square" },
        }, function()
            return minimap.style
        end, function(value)
            minimap.style = value == "native" and "native" or "square"
        end, "minimap-style", true)
        detailFields[#detailFields + 1] = Slider("settings.minimap.size", 120, 400, 1, function()
            return minimap.size
        end, function(value)
            minimap.size = value
        end, "minimap-size")
    end
    local basicGroups = {
        {
            fields = { enabledField },
            columns = 1,
        },
    }
    if #detailFields > 0 then
        basicGroups[#basicGroups + 1] = {
            fields = detailFields,
            columns = 2,
        }
    end
    y = RenderCard(parent, x, y, width, nil, nil, nil, basicGroups)

    if minimap.enabled ~= true then
        return y
    end

    if minimap.style == "native" then
        local appearance = minimap.nativeAppearance
        y = RenderCard(parent, x, y, width, "settings.section.minimap_native", "eye", {
            Check(parent, "settings.minimap.hide_zoom", function()
                return minimap.hideZoomButtons == true
            end, function(value)
                minimap.hideZoomButtons = value
            end, "minimap-zoom-buttons"),
            Dropdown(parent, "settings.minimap.zone_alignment", {
                { text = T("settings.option.native"), value = "native" },
                { text = T("settings.option.center"), value = "center" },
            }, function()
                return minimap.zoneTextAlignment
            end, function(value)
                minimap.zoneTextAlignment = value == "center" and "center" or "native"
            end, "minimap-zone-alignment"),
            Check(parent, "settings.minimap.hide_clock", function()
                return appearance.hideClock ~= false
            end, function(value)
                appearance.hideClock = value
            end, "minimap-native-clock"),
            Check(parent, "settings.minimap.hide_calendar", function()
                return appearance.hideCalendar == true
            end, function(value)
                appearance.hideCalendar = value
            end, "minimap-native-calendar"),
            Slider("settings.minimap.zone_name_font_size", 8, 24, 1, function()
                return appearance.zoneNameFontSize
            end, function(value)
                appearance.zoneNameFontSize = value
            end, "minimap-native-zone-font-size"),
        })

    else
        local appearance = minimap.squareAppearance
        local defaultBorderColor = { 0.22, 0.26, 0.32, 1 }
        local fields = {
            Slider("settings.minimap.border_width", 0, 8, 1, function()
                return appearance.borderWidth
            end, function(value)
                appearance.borderWidth = value
            end, "minimap-square-border"),
            Color("settings.minimap.border_color", defaultBorderColor, function()
                return appearance.borderColor
            end, function(value)
                appearance.borderColor = value
            end, "minimap-square-border"),
        }
        y = RenderCard(
            parent,
            x,
            y,
            width,
            "settings.section.minimap_square_appearance",
            "paintbrush",
            fields
        )

        local statusBars = minimap.statusBars
        local defaultExperienceColor = { 0.58, 0, 0.55, 1 }
        local defaultStatusBarColor = { 0, 0, 0, 1 }
        y = RenderCard(
            parent,
            x,
            y,
            width,
            "settings.section.minimap_status_bars",
            "chart-bar-big",
            nil,
            {
                {
                    fields = {
                        Check(parent, "settings.minimap.status_bars_experience", function()
                            return statusBars.experienceEnabled == true
                        end, function(value)
                            statusBars.experienceEnabled = value
                        end, "minimap-status-bars-enabled"),
                        Check(parent, "settings.minimap.status_bars_reputation", function()
                            return statusBars.reputationEnabled == true
                        end, function(value)
                            statusBars.reputationEnabled = value
                        end, "minimap-status-bars-enabled"),
                    },
                    columns = 2,
                },
                {
                    fields = {
                        Dropdown(parent, "settings.minimap.status_bars_position", StatusBarPositionOptions(), function()
                            return statusBars.position
                        end, function(value)
                            if value == "top" or value == "left" or value == "right" then
                                statusBars.position = value
                            else
                                statusBars.position = "bottom"
                            end
                        end, "minimap-status-bars-layout"),
                        Slider("settings.minimap.status_bars_thickness", 8, 32, 1, function()
                            return statusBars.thickness
                        end, function(value)
                            statusBars.thickness = value
                        end, "minimap-status-bars-layout"),
                    },
                    columns = 2,
                },
                {
                    fields = {
                        Texture("settings.minimap.status_bars_texture", function()
                            return statusBars.texture
                        end, function(value)
                            statusBars.texture = value
                        end, "minimap-status-bars-appearance"),
                        Color("settings.minimap.status_bars_background_color", defaultStatusBarColor, function()
                            return statusBars.backgroundColor
                        end, function(value)
                            statusBars.backgroundColor = value
                        end, "minimap-status-bars-appearance"),
                    },
                    columns = 2,
                },
                {
                    fields = {
                        Color("settings.minimap.status_bars_experience_color", defaultExperienceColor, function()
                            return statusBars.experienceColor
                        end, function(value)
                            statusBars.experienceColor = value
                        end, "minimap-status-bars-appearance"),
                        Color("settings.minimap.status_bars_border_color", defaultStatusBarColor, function()
                            return statusBars.borderColor
                        end, function(value)
                            statusBars.borderColor = value
                        end, "minimap-status-bars-appearance"),
                    },
                    columns = 2,
                },
                {
                    fields = {
                        Slider("settings.minimap.status_bars_border_width", 0, 4, 1, function()
                            return statusBars.borderWidth
                        end, function(value)
                            statusBars.borderWidth = value
                        end, "minimap-status-bars-appearance"),
                        Dropdown(parent, "settings.minimap.status_bars_text_display", StatusBarTextDisplayOptions(), function()
                            return statusBars.textDisplay
                        end, function(value)
                            statusBars.textDisplay = value == "always" and "always" or "hover"
                        end, "minimap-status-bars-appearance"),
                    },
                    columns = 2,
                },
                {
                    fields = {
                        Slider("settings.minimap.status_bars_map_gap", 0, 16, 1, function()
                            return statusBars.mapGap
                        end, function(value)
                            statusBars.mapGap = value
                        end, "minimap-status-bars-layout"),
                        Slider("settings.minimap.status_bars_bar_gap", 0, 16, 1, function()
                            return statusBars.barGap
                        end, function(value)
                            statusBars.barGap = value
                        end, "minimap-status-bars-layout"),
                    },
                    columns = 2,
                },
            }
        )
    end

    y = RenderButtonSettingsCard(parent, x, y, width, minimap, drawer)

    local belowWidgetField = Slider("settings.minimap.below_widget_width", 120, 500, 1, function()
        return belowWidget.width
    end, function(value)
        belowWidget.width = value
    end, "minimap-below-widget")
    belowWidgetField.tooltip = T("settings.minimap.below_widget_width_tooltip")
    y = RenderCard(parent, x, y, width, "settings.section.minimap_widgets", "move-down", {
        belowWidgetField,
    })

    return y
end

local function RenderWorldMapTab(parent, x, y, width)
    local worldMap = DB().worldMap
    y = RenderCard(parent, x, y, width, nil, nil, {
        Check(parent, "settings.world_map.enabled", function()
            return worldMap.enabled == true
        end, function(value)
            worldMap.enabled = value
        end, "world-map-enabled", true, LC["common.enable"]),
    })
    if worldMap.enabled ~= true then
        return y
    end

    local windowFields = {
        Slider("settings.world_map.scale", 0.5, 2, 0.05, function()
            return worldMap.scale
        end, function(value)
            worldMap.scale = value
        end, "world-map-scale"),
        Check(parent, "settings.world_map.remember_position", function()
            return worldMap.rememberPosition == true
        end, function(value)
            worldMap.rememberPosition = value
        end, "world-map-position"),
        Action("settings.actions", "settings.world_map.reset_position", function()
            worldMap.position = nil
            if YMap.WorldMap and YMap.WorldMap.ResetPosition then
                YMap.WorldMap:ResetPosition()
            else
                Refresh("world-map-reset-position")
            end
        end, "settings"),
    }
    windowFields[#windowFields + 1] = Check(parent, "settings.world_map.fade_when_moving", function()
        return worldMap.fadeWhenMoving == true
    end, function(value)
        worldMap.fadeWhenMoving = value
    end, "world-map-movement-fade", true)
    if worldMap.fadeWhenMoving then
        windowFields[#windowFields + 1] = Slider("settings.world_map.moving_opacity", 10, 100, 1, function()
            return math.floor((worldMap.movingAlpha or 0.8) * 100 + 0.5)
        end, function(value)
            worldMap.movingAlpha = value / 100
        end, "world-map-moving-opacity")
    end
    y = RenderCard(parent, x, y, width, "settings.section.world_map_window", "panels-top-left", windowFields)

    if YMap.MapReveal then
        local reveal = worldMap.reveal
        local fields = {
            Check(parent, "settings.world_map.reveal", function() return reveal.enabled end,
                function(value) reveal.enabled = value end, "map-reveal", true),
        }
        if reveal.enabled then
            fields[#fields + 1] = Check(parent, "settings.world_map.reveal_tint",
                function() return reveal.tint end, function(value) reveal.tint = value end, "map-reveal-tint", true)
            if reveal.tint then
                fields[#fields + 1] = Color("settings.world_map.reveal_color", YMap.Defaults.worldMap.reveal.color,
                    function() return reveal.color end, function(value) reveal.color = value end, "map-reveal-color")
            end
        end
        y = RenderCard(parent, x, y, width, "settings.section.world_map_reveal", "eye", fields)
    end

    local line = worldMap.directionLine
    local lineFields = {
        Check(parent, "settings.world_map.direction_line",
            function() return line.enabled end, function(value) line.enabled = value end, "direction-line", true),
    }
    if line.enabled then
        lineFields[#lineFields + 1] = Dropdown(parent, "settings.world_map.direction_style", {
            { text = T("settings.option.line_solid"), value = "solid" },
            { text = T("settings.option.line_dashed"), value = "dashed" },
        }, function() return line.style end, function(value) line.style = value end, "direction-line", true)
        lineFields[#lineFields + 1] = Color("settings.world_map.direction_color", YMap.Defaults.worldMap.directionLine.color,
            function() return line.color end, function(value) line.color = value end, "direction-line")
        if line.style == "solid" then
            lineFields[#lineFields + 1] = Slider("settings.world_map.direction_thickness", 1, 6, 1,
                function() return line.thickness end, function(value) line.thickness = value end, "direction-line")
        else
            lineFields[#lineFields + 1] = Slider("settings.world_map.direction_dot_size", 1, 6, 1,
                function() return line.dotSize end, function(value) line.dotSize = value end, "direction-line")
            lineFields[#lineFields + 1] = Slider("settings.world_map.direction_dot_spacing", 4, 32, 1,
                function() return line.dotSpacing end, function(value) line.dotSpacing = value end, "direction-line")
        end
    end
    y = RenderCard(parent, x, y, width, "settings.section.world_map_direction", "footprints", lineFields)

    return RenderCard(parent, x, y, width, "settings.section.world_map_coordinates", "footprints", {
        Check(parent, "settings.world_map.player_coordinates", function()
            return worldMap.coordinates.player == true
        end, function(value)
            worldMap.coordinates.player = value
        end, "world-map-player-coordinates"),
        Check(parent, "settings.world_map.cursor_coordinates", function()
            return worldMap.coordinates.cursor == true
        end, function(value)
            worldMap.coordinates.cursor = value
        end, "world-map-cursor-coordinates"),
    })
end

local function RenderMarkerCategories(parent, x, y, width, options)
    local layout = GetLayout(width)
    if layout.columns == 2 then
        width = math.floor((layout.innerWidth - layout.columnGap) / 2)
    end
    local panel = GUI2:CreateFrame(parent, { width = width, height = 280 })
    panel:SetPoint("TOPLEFT", x, y)
    local title = GUI2:CreateText(panel, T("settings.markers.categories"), "font.size.md", "color.text.heading")
    title:SetPoint("TOPLEFT", 0, 0)
    local resetOption = options[#options].children[1]
    local reset = GUI2.Form:CreateButton(panel, {
        text = resetOption.label, width = 104, height = 26,
        tooltip = T("settings.markers.reset_tooltip"), onClick = resetOption.onClick,
    })
    reset:SetPoint("TOPRIGHT", 0, 4)

    local showX, colorX = width - 160, width - 48
    local function Header(key, position, centered)
        local text = GUI2:CreateText(panel, T(key), "font.size.md", "color.text.muted")
        text:SetPoint(centered and "TOP" or "TOPLEFT", panel, "TOPLEFT", position, -38)
    end
    Header("settings.markers.category", 0)
    Header("settings.markers.show", showX, true)
    Header("settings.markers.color", colorX, true)
    local divider = CreateSectionDivider(panel, width)
    divider:SetPoint("TOPLEFT", 0, -64)

    local rowY = -72
    for _, option in ipairs(options) do
        local children = option.children
        if option.markerCategory and children and children[1] then
            local visible, color = children[1], children[2]
            local label = GUI2:CreateText(panel, visible.label, "font.size.md", "color.text.primary")
            label:SetPoint("LEFT", panel, "TOPLEFT", 0, rowY - 13)
            local picker
            if color then
                picker = GUI2.Form:CreateColorPicker(panel, {
                    width = 32, height = 26, field = true, hasAlpha = false,
                    get = color.get, set = color.set, default = color.default,
                    onChange = color.onChange, tooltip = T("settings.markers.color_tooltip"),
                })
                picker:SetPoint("TOPLEFT", colorX - 16, rowY)
            end
            local function UpdateRow()
                local alpha = visible.get() and 1 or 0.45
                label:SetAlpha(alpha)
                if picker then picker:SetAlpha(alpha) end
            end
            local checkbox = GUI2.Form:CreateCheckbox(panel, {
                width = 18, height = 26, get = visible.get, set = visible.set,
                tooltip = visible.label,
                onChange = function()
                    if visible.onChange then visible.onChange() end
                    UpdateRow()
                end,
            })
            checkbox:SetPoint("TOPLEFT", showX - 9, rowY)
            UpdateRow()
            rowY = rowY - 38
        end
    end
    panel:SetHeight(-rowY + 4)
    return y + rowY - SECTION_GAP
end

local function RenderMarkersTab(parent, x, y, width)
    if not YMap.Markers then return y end
    local markers = DB().markers
    y = RenderCard(parent, x, y, width, nil, nil, {
        Check(parent, "settings.markers.enabled", function() return markers.enabled == true end,
            function(value) markers.enabled = value end, "markers-enabled", true, LC["common.enable"]),
    })
    if markers.enabled ~= true then return y end
    local options = YMap.Markers:GetOptions()
    local fields = {}
    for _, option in ipairs(options) do
        if option.type == "divider" then break end
        for _, field in ipairs(option.children or {}) do
            field.width = nil
            fields[#fields + 1] = field
        end
    end
    y = RenderCard(parent, x, y, width, "settings.markers.options", "settings", fields)
    YMap.Markers.RefreshCurrentModule = function() Rerender(parent) end
    return RenderMarkerCategories(parent, x, y, width, options)
end

local function RenderWorldEventsTab(parent, x, y, width)
    local events = YMap.WorldEvents
    if not events then return y end
    local config = DB().worldEvents
    y = RenderCard(parent, x, y, width, nil, nil, {
        Check(parent, "settings.world_events.enabled", function() return config.enabled == true end,
            function(value) config.enabled = value end, "world-events-enabled", true, LC["common.enable"]),
    })
    if config.enabled ~= true then return y end
    events.RefreshCurrentModule = function() Rerender(parent) end
    local options = events:GetOptions()
    local layoutFields, seriesFields = {}, {}
    for index, option in ipairs(options) do
        if option.children then
            local fields = index <= 2 and layoutFields or seriesFields
            for _, field in ipairs(option.children) do
                field.width, field.labelWidth, field.inputWidth, field.inline = nil, nil, nil, nil
                fields[#fields + 1] = field
            end
        end
    end
    y = RenderCard(parent, x, y, width, "settings.world_events.layout", "settings", layoutFields)
    y = RenderCard(parent, x, y, width, "settings.world_events.series", "settings", seriesFields)
    local credit = options[#options]
    if credit and credit.type == "text" then
        local text = GUI2:CreateText(parent, credit.label, "font.size.sm", "color.text.muted")
        text:SetPoint("TOPLEFT", x, y)
        text:SetWidth(width)
        text:SetWordWrap(true)
        y = y - 44
    end
    return y
end

function YMap:SetSettingsTab(tab)
    if tab == "minimap" or tab == "worldMap" or (tab == "markers" and self.Markers) or (tab == "worldEvents" and self.WorldEvents) then activeTab = tab end
end

function YMap:OnSettingsLeave()
    settingsActive = false
    if self.Markers then self.Markers.RefreshCurrentModule = nil end
    if self.WorldEvents then self.WorldEvents.RefreshCurrentModule = nil end
    ClearLiveButtonPreview()
end

function YMap:RenderSettings(parent, context)
    pageContext = context
    Render(parent)
end

Render = function(parent)
    settingsActive = true
    if YMap.WorldEvents then YMap.WorldEvents.RefreshCurrentModule = nil end
    if not (
        GUI2
        and GUI2.Form
        and GUI2.Form.CreateUnderlineTabs
        and GUI2.CreateFrame
        and GUI2.CreatePanel
        and GUI2.CreateDivider
        and GUI2.CreateTexture
        and GUI2.SetTexturePaintKey
        and GUI2.CreateMicroIcon
        and S.RenderAlignedFields
    ) then
        if S.RenderConfig then
            S:RenderConfig(parent, {
                { type = "header", label = T("settings.title") },
                { type = "text", label = T("settings.gui_unavailable"), colorKey = "color.state.warning" },
            })
        end
        return
    end

    EnsureSettingsPreviewRootLifecycle()
    if parent.HookScript and not parent.ymapLivePreviewHooked then
        parent.ymapLivePreviewHooked = true
        parent:HookScript("OnHide", function() YMap:OnSettingsLeave() end)
        parent:HookScript("OnShow", function()
            if not YMap.Host or YMap.Host.settingsMode == "navigation" then settingsActive = true end
            if ApplyLiveButtonPreview then ApplyLiveButtonPreview() end
        end)
    end

    local parentWidth = parent:GetWidth() or 0
    local width = parentWidth > (PAGE_INSET * 2) and (parentWidth - (PAGE_INSET * 2)) or 700

    if pageContext and pageContext.renderTitle then
        pageContext.renderTitle(parent, PAGE_INSET, -MODULE_PAGE_LAYOUT.titleTop, width)
    else
        local title = GUI2:CreateText(parent, T("settings.title"), "font.size.title", "color.text.heading")
        title:SetPoint("TOPLEFT", PAGE_INSET, -MODULE_PAGE_LAYOUT.titleTop)
    end

    local tabItems = {
        { text = T("settings.tab.minimap"), value = "minimap" },
        { text = T("settings.tab.world_map"), value = "worldMap" },
    }
    if YMap.Markers then
        tabItems[#tabItems + 1] = { text = T("settings.tab.markers"), value = "markers" }
    end
    if YMap.WorldEvents then
        tabItems[#tabItems + 1] = { text = T("settings.tab.world_events"), value = "worldEvents" }
    end
    local tabs = GUI2.Form:CreateUnderlineTabs(parent, {
        width = width,
        value = activeTab,
        fontSizeKey = "font.size.lg",
        showBaseline = true,
        baselineHeight = 1,
        baselineColorKey = "color.border.subtle",
        indicatorHeight = 2,
        indicatorColorKey = "color.text.accent",
        items = tabItems,
        onChange = function(_, value)
            activeTab = (value == "worldMap" or (value == "markers" and YMap.Markers) or (value == "worldEvents" and YMap.WorldEvents)) and value or "minimap"
            if activeTab ~= "minimap" then ClearLiveButtonPreview() end
            Rerender(parent)
        end,
    })
    tabs:SetPoint("TOPLEFT", PAGE_INSET, -60)

    local description = GUI2:CreateText(parent, T("settings.description." .. activeTab), "font.size.md", "color.text.muted")
    description:SetPoint("TOPLEFT", PAGE_INSET, -100)
    description:SetWidth(width)
    description:SetJustifyH("LEFT")
    description:SetWordWrap(true)
    local y = -100 - math.max(description:GetStringHeight() or 20, 20) - 16
    if activeTab == "worldEvents" then
        y = RenderWorldEventsTab(parent, PAGE_INSET, y, width)
    elseif activeTab == "markers" then
        y = RenderMarkersTab(parent, PAGE_INSET, y, width)
    elseif activeTab == "worldMap" then
        y = RenderWorldMapTab(parent, PAGE_INSET, y, width)
    else
        local yielded
        y, yielded = RenderMinimapTab(parent, PAGE_INSET, y, width)
        if yielded then
            ClearLiveButtonPreview()
        else
            ApplyLiveButtonPreview()
        end
    end

    parent:SetHeight(math.max(320, math.abs(y) + 6))
    if S.RefreshCurrentModuleScroll then
        S:RefreshCurrentModuleScroll(false)
    end
end

if not YMap.Host or YMap.Host.settingsMode == "navigation" then
S:RegisterModule("YMap", SETTINGS_ICON, function(parent) YMap:RenderSettings(parent) end, {
    id = YMap.SETTINGS_ENTRY,
    product = YMap.PRODUCT_ID,
    scope = YMap.PRODUCT_ID,
    titleKey = "settings.title",
    titleNamespace = "YMap",
    navTitleKey = "settings.nav",
    navTitleNamespace = "YMap",
    navToggle = { moduleId = YMap.PRODUCT_ID },
})

end

if S.Search then
    S.Search:RegisterRoute(YMap.SETTINGS_ENTRY or "ymap.settings", function(tab) YMap:SetSettingsTab(tab) end)
end

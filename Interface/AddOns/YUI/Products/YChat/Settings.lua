local YUI = _G.YUI
local YChat = YUI and YUI.YChat
local S = YUI and YUI.Settings
if not (YChat and (YUI.IsForever or YUI.IsRetail) == true and S and S.RegisterModule and S.RenderConfig) then return end

local L = YUI.Locale and YUI.Locale:Get("YChat") or {}
local GUI2 = YUI.GUI2
local type = type
local tinsert = table.insert
local floor = math.floor
local ceil = math.ceil
local max = math.max
local min = math.min
local activePage = "appearance"
local Render
local ChannelInput
local SETTINGS_WIDTH = 760
local COLUMN_GAP = 24
local LABEL_WIDTH = 154
local LABEL_GAP = 10
local CONTROL_WIDTH = 246
local VALUE_WIDTH = 56
local ROW_HEIGHT = 32
local ROW_GAP = 10
local HISTORY_ACTION_WIDTH = 220
local CARD_HEADER_HEIGHT = 32
local CARD_SECTION_GAP = 18
local CARD_CONTENT_GAP = 10
local CARD_DIVIDER_GAP = 12
local CARD_RIGHT_INSET = 20

local ALIGNED_FIELD_TYPES = {
    checkbox = true,
    color = true,
    dropdown = true,
    editbox = true,
    font = true,
    slider = true,
    switch = true,
}

local function T(key, fallback)
    local value = L[key]
    return type(value) == "string" and value ~= "" and value or fallback
end

local function Rerender(parent)
    if not (parent and S.ClearConfig and Render) then return end
    S:ClearConfig(parent)
    Render(parent)
end

local function Appearance()
    return YChat:GetAppearance()
end

local function Layout()
    return YChat:GetLayout()
end

local function Timestamp()
    return YChat:GetTimestamp()
end

local function Typography()
    return YChat:GetTypography()
end

ChannelInput = function()
    return YChat:GetChannelInput()
end

local function AutoInvite()
    return YChat:GetAutoInvite()
end

local function History()
    return YChat:GetHistory()
end

local function BuildNativeFontOptions()
    return {
        { text = T("settings.native", "Native"), value = "__native" },
    }
end

local function BuildOutlineOptions(includeNative)
    local prepend = includeNative and BuildNativeFontOptions() or nil
    if GUI2.Form.BuildFontOutlineOptions then
        return GUI2.Form:BuildFontOutlineOptions({
            prependOptions = prepend,
        })
    end
    local options = prepend or {}
    options[#options + 1] = { text = T("settings.outline.none", "None"), value = "none" }
    options[#options + 1] = { text = T("settings.outline.normal", "Outline"), value = "outline" }
    options[#options + 1] = { text = T("settings.outline.thick", "Thick Outline"), value = "thick" }
    options[#options + 1] = { text = T("settings.outline.shadow", "Shadow"), value = "shadow" }
    options[#options + 1] = {
        searchKey = "settings.outline.outline_shadow",
        text = T("settings.outline.outline_shadow", "Outline + Shadow"),
        value = "outlineShadow",
    }
    return options
end

local function ManualField(parent, item)
    local originalOnChange = item.onChange
    item.onChange = function(widget, value)
        if originalOnChange then originalOnChange(widget, value) end
        local picker = GUI2.ColorPicker
        if picker and (picker.owner == widget or picker.closingOwner == widget)
            and picker:DeferRefresh(parent, function() Rerender(parent) end) then return end
        Rerender(parent)
    end
    return item
end

local function AddSection(options, key, fallback)
    options[#options + 1] = {
        type = "ychatSection",
        label = T(key, fallback),
        sectionKey = key,
        iconName = "settings",
    }
end

local function GetCardLayout(width)
    local innerWidth = max(tonumber(width) or SETTINGS_WIDTH, 320)
    local columns = innerWidth >= 620 and 2 or 1
    local bodyWidth
    if columns == 2 then
        bodyWidth = floor((innerWidth - COLUMN_GAP) / 2) - LABEL_WIDTH - LABEL_GAP
    else
        bodyWidth = innerWidth - LABEL_WIDTH - LABEL_GAP
    end
    return innerWidth, columns, max(bodyWidth, 122)
end

local function GetAvailableCardWidth(container, x, width)
    local availableWidth = tonumber(width)
    if container and type(container.GetWidth) == "function" then
        local containerWidth = tonumber(container:GetWidth()) or 0
        local remainingWidth = containerWidth
            - (tonumber(x) or 0)
            - CARD_RIGHT_INSET
        if remainingWidth > 0 then
            availableWidth = availableWidth
                and min(availableWidth, remainingWidth)
                or remainingWidth
        end
    end
    return max(availableWidth or SETTINGS_WIDTH, 320)
end

local function BuildCardItem(section)
    return {
        type = "custom",
        ychatFlatSection = true,
        ychatSectionKey = section.sectionKey,
        ychatSectionFields = section.items,
        render = function(container, x, y, width)
            if not (GUI2 and GUI2.CreateFrame and GUI2.CreateText
                and S and S.RenderAlignedFields)
            then
                return width, 0
            end
            local availableWidth, responsiveColumns, bodyWidth = GetCardLayout(
                GetAvailableCardWidth(container, x, width)
            )
            local panel = GUI2:CreateFrame(container, {
                width = availableWidth,
                height = 100,
            })
            panel:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)
            panel.ychatFlatSection = true
            panel.ychatSectionKey = section.sectionKey

            local icon
            if GUI2.CreateMicroIcon then
                icon = GUI2:CreateMicroIcon(panel, {
                    iconName = section.iconName or "settings",
                    size = 20,
                    maxSize = 20,
                    point = "TOPLEFT",
                    relativePoint = "TOPLEFT",
                    x = 0,
                    y = -4,
                })
            end
            local title = GUI2:CreateText(
                panel,
                section.label,
                "font.size.md",
                "color.text.heading"
            )
            if icon then
                title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            else
                title:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
            end
            title:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
            title:SetJustifyH("LEFT")
            title:SetWordWrap(false)

            local cursor = CARD_HEADER_HEIGHT
            local pending = {}
            local function FlushFields(columns)
                if #pending == 0 then return end
                local useColumns = min(columns or responsiveColumns, responsiveColumns)
                local useBodyWidth = bodyWidth
                if useColumns == 1 then
                    useBodyWidth = max(availableWidth - LABEL_WIDTH - LABEL_GAP, 122)
                end
                local _, _, height = S:RenderAlignedFields(panel, {
                    x = 0,
                    y = -cursor,
                    width = availableWidth,
                    columns = useColumns,
                    columnGap = COLUMN_GAP,
                    labelWidth = LABEL_WIDTH,
                    labelGap = LABEL_GAP,
                    bodyWidth = useBodyWidth,
                    valueWidth = VALUE_WIDTH,
                    valueGap = LABEL_GAP,
                    rowHeight = ROW_HEIGHT,
                    rowGap = ROW_GAP,
                    minBodyWidth = 122,
                    fields = pending,
                })
                cursor = cursor + (height or 0) + CARD_CONTENT_GAP
                pending = {}
            end

            for index = 1, #section.items do
                local item = section.items[index]
                if ALIGNED_FIELD_TYPES[item.type] then
                    local columns = tonumber(item.ychatColumns)
                    if columns then
                        FlushFields()
                        pending[1] = item
                        FlushFields(columns)
                    else
                        pending[#pending + 1] = item
                    end
                else
                    FlushFields()
                    if item.type == "custom" and type(item.render) == "function" then
                        local _, height = item.render(panel, 0, -cursor, availableWidth)
                        cursor = cursor + max(tonumber(height) or 0, 1) + CARD_CONTENT_GAP
                    end
                end
            end
            FlushFields()
            cursor = max(CARD_HEADER_HEIGHT, cursor - CARD_CONTENT_GAP)

            local divider = GUI2.CreateDivider and GUI2:CreateDivider(panel, {
                width = availableWidth,
                height = 1,
            }) or nil
            if divider then
                divider:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -cursor - CARD_DIVIDER_GAP)
            end
            local height = cursor + CARD_DIVIDER_GAP + (divider and 1 or 0)
            panel:SetHeight(height)
            return availableWidth, height + CARD_SECTION_GAP
        end,
    }
end

local function ApplyCardSectionLayout(options)
    local rendered = {}
    local section
    local function FlushSection()
        if not section then return end
        rendered[#rendered + 1] = BuildCardItem(section)
        section = nil
    end
    for index = 1, #options do
        local item = options[index]
        if item.type == "ychatSection" then
            FlushSection()
            section = {
                label = item.label,
                sectionKey = item.sectionKey,
                iconName = item.iconName,
                items = {},
            }
        elseif section then
            section.items[#section.items + 1] = item
        else
            rendered[#rendered + 1] = item
        end
    end
    FlushSection()
    return rendered
end

local function BuildPageNavigation(parent)
    return {
        type = "custom",
        render = function(container, x, y, width)
            if not (GUI2 and GUI2.Form and GUI2.Form.CreateUnderlineTabs) then
                return width, 0
            end
            local tabs = GUI2.Form:CreateUnderlineTabs(container, {
                width = width,
                value = activePage,
                gap = 24,
                itemPaddingX = 8,
                fontSizeKey = "font.size.lg",
                showBaseline = true,
                baselineHeight = 1,
                baselineColorKey = "color.border.subtle",
                indicatorHeight = 2,
                indicatorColorKey = "color.text.accent",
                overflow = "scroll",
                contentAlignment = "LEFT",
                items = {
                    { text = T("settings.page.appearance", "Appearance"), value = "appearance" },
                    { text = T("settings.page.layout", "Layout"), value = "layout" },
                    {
                        searchKey = "settings.page.channel_input",
                        text = T("settings.page.channel_input", "Channels and input"),
                        value = "channelInput",
                    },
                    { text = T("settings.page.rules", "Rules"), value = "rules" },
                    { text = T("settings.page.records", "History"), value = "records" },
                },
                onChange = function(_, value)
                    activePage = value == "layout" and "layout"
                        or value == "channelInput" and "channelInput"
                        or value == "rules" and "rules"
                        or value == "records" and "records"
                        or "appearance"
                    Rerender(parent)
                end,
            })
            tabs:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)
            return width, 36
        end,
    }
end

local function BuildAppearanceOptions(parent, options)
    local appearance = Appearance()
    AddSection(options, "settings.section.window_background", "Window background")
    options[#options + 1] = {
        type = "dropdown",
        searchKey = "settings.appearance.preset",
        label = T("settings.appearance.preset", "Preset"),
        width = CONTROL_WIDTH,
        options = {
            { text = T("settings.preset.clear", "Clear"), value = "clear" },
            { text = T("settings.preset.deep", "Deep"), value = "deep" },
            { text = T("settings.preset.custom", "Custom"), value = "custom" },
        },
        get = function()
            return Appearance().preset
        end,
        set = function(value)
            YChat:SelectAppearancePreset(value)
        end,
        onChange = function()
            Rerender(parent)
        end,
    }
    options[#options + 1] = ManualField(parent, {
        type = "slider",
        searchKey = "settings.appearance.background_alpha",
        label = T("settings.appearance.background_alpha", "Background opacity"),
        min = 0,
        max = 100,
        step = 5,
        precision = 0,
        instantUpdate = false,
        get = function()
            return floor((Appearance().backgroundAlpha or 0) * 100 + 0.5)
        end,
        set = function(value)
            YChat:SetAppearanceValue("backgroundAlpha", (value or 0) / 100)
        end,
    })
    options[#options + 1] = ManualField(parent, {
        type = "color",
        field = true,
        hasAlpha = false,
        searchKey = "settings.appearance.background_color",
        label = T("settings.appearance.background_color", "Background color"),
        default = YChat.Defaults.appearance.backgroundColor,
        get = function()
            return Appearance().backgroundColor
        end,
        set = function(value)
            YChat:SetAppearanceValue("backgroundColor", value)
        end,
    })
    options[#options + 1] = ManualField(parent, {
        type = "dropdown",
        searchKey = "settings.appearance.border",
        label = T("settings.appearance.border", "Border"),
        width = CONTROL_WIDTH,
        options = {
            { text = T("settings.border.none", "None"), value = "none" },
            { text = T("settings.border.hairline", "Hairline"), value = "hairline" },
        },
        get = function()
            return Appearance().borderStyle
        end,
        set = function(value)
            YChat:SetAppearanceValue("borderStyle", value)
        end,
        onChange = function()
            Rerender(parent)
        end,
    })
    if appearance.borderStyle ~= "none" then
        options[#options + 1] = ManualField(parent, {
            type = "slider",
            searchKey = "settings.appearance.border_width",
            label = T("settings.appearance.border_width", "Border width"),
            min = 1,
            max = 4,
            step = 1,
            precision = 0,
            instantUpdate = false,
            get = function()
                return Appearance().borderWidth or 1
            end,
            set = function(value)
                YChat:SetAppearanceValue("borderWidth", value)
            end,
        })
        options[#options + 1] = ManualField(parent, {
            type = "checkbox",
            labelPosition = "left",
            label = T(
                "settings.appearance.class_color_border",
                "Use class color for border"
            ),
            get = function()
                return Appearance().classColorBorder == true
            end,
            set = function(value)
                YChat:SetAppearanceValue("classColorBorder", value == true)
            end,
            onChange = function()
                Rerender(parent)
            end,
        })
        if appearance.classColorBorder ~= true then
            options[#options + 1] = ManualField(parent, {
                type = "color",
                field = true,
                hasAlpha = true,
                searchKey = "settings.appearance.border_color",
                label = T("settings.appearance.border_color", "Border color"),
                default = YChat.Defaults.appearance.borderColor,
                get = function()
                    return Appearance().borderColor
                end,
                set = function(value)
                    YChat:SetAppearanceValue("borderColor", value)
                end,
            })
        end
    end
    AddSection(options, "settings.section.tabs", "Tabs")
    options[#options + 1] = ManualField(parent, {
        type = "dropdown",
        searchKey = "settings.appearance.tab_style",
        label = T("settings.appearance.tab_style", "Tab style"),
        width = CONTROL_WIDTH,
        options = {
            { text = T("settings.tab.text", "Minimal text"), value = "text" },
            {
                searchKey = "settings.tab.underline",
                text = T("settings.tab.underline", "Accent underline"),
                value = "underline",
            },
            { text = T("settings.tab.block", "Accent block"), value = "block" },
            {
                searchKey = "settings.tab.dark_underline",
                text = T("settings.tab.dark_underline", "Dark underline"),
                value = "darkUnderline",
            },
        },
        get = function()
            return Appearance().tabStyle
        end,
        set = function(value)
            YChat:SetAppearanceValue("tabStyle", value)
        end,
    })
    options[#options + 1] = ManualField(parent, {
        type = "dropdown",
        searchKey = "settings.appearance.tab_text_effect",
        label = T("settings.appearance.tab_text_effect", "Title text effect"),
        width = CONTROL_WIDTH,
        options = BuildOutlineOptions(false),
        get = function()
            return Appearance().tabTextEffect
        end,
        set = function(value)
            YChat:SetAppearanceValue("tabTextEffect", value)
        end,
    })
    options[#options + 1] = ManualField(parent, {
        type = "slider",
        searchKey = "settings.appearance.tab_font_size",
        label = T("settings.appearance.tab_font_size", "Tab text size"),
        min = 10,
        max = 16,
        step = 1,
        precision = 0,
        instantUpdate = false,
        get = function()
            return Appearance().tabFontSize
        end,
        set = function(value)
            YChat:SetAppearanceValue("tabFontSize", value)
        end,
    })
    options[#options + 1] = ManualField(parent, {
        type = "dropdown",
        searchKey = "settings.appearance.tab_width_mode",
        label = T("settings.appearance.tab_width_mode", "Tab width mode"),
        width = CONTROL_WIDTH,
        options = {
            { text = T("settings.tab_width.auto", "Automatic"), value = "auto" },
            { text = T("settings.tab_width.fixed", "Fixed"), value = "fixed" },
        },
        get = function()
            return Appearance().tabWidthMode
        end,
        set = function(value)
            YChat:SetAppearanceValue("tabWidthMode", value)
        end,
        onChange = function()
            Rerender(parent)
        end,
    })
    if appearance.tabWidthMode == "fixed" then
        options[#options + 1] = ManualField(parent, {
            type = "slider",
            searchKey = "settings.appearance.tab_width",
            label = T("settings.appearance.tab_width", "Tab width"),
            min = YChat.TAB_MIN_WIDTH or 48,
            max = YChat.TAB_MAX_WIDTH or 160,
            step = 1,
            precision = 0,
            instantUpdate = false,
            get = function()
                return Appearance().tabWidth
            end,
            set = function(value)
                YChat:SetAppearanceValue("tabWidth", value)
            end,
        })
    end
    options[#options + 1] = ManualField(parent, {
        type = "slider",
        searchKey = "settings.appearance.tab_spacing",
        label = T("settings.appearance.tab_spacing", "Tab spacing"),
        min = YChat.TAB_MIN_SPACING or 0,
        max = YChat.TAB_MAX_SPACING or 16,
        step = 1,
        precision = 0,
        instantUpdate = false,
        get = function()
            return Appearance().tabSpacing
        end,
        set = function(value)
            YChat:SetAppearanceValue("tabSpacing", value)
        end,
    })
    options[#options + 1] = ManualField(parent, {
        type = "slider",
        searchKey = "settings.appearance.tab_left_inset",
        label = T("settings.appearance.tab_left_inset", "First tab left inset"),
        min = YChat.TAB_LEFT_INSET_MIN or 0,
        max = YChat.TAB_LEFT_INSET_MAX or 32,
        step = 1,
        precision = 0,
        instantUpdate = false,
        get = function()
            return Appearance().tabLeftInset
        end,
        set = function(value)
            YChat:SetAppearanceValue("tabLeftInset", value)
        end,
    })
    options[#options + 1] = ManualField(parent, {
        type = "checkbox",
        labelPosition = "left",
        searchKey = "settings.appearance.class_color_tabs",
        label = T("settings.appearance.class_color_tabs", "Use class color for tabs"),
        get = function()
            return Appearance().classColorTabs == true
        end,
        set = function(value)
            YChat:SetAppearanceValue("classColorTabs", value == true)
        end,
        onChange = function()
            Rerender(parent)
        end,
    })
    if appearance.classColorTabs ~= true then
        options[#options + 1] = ManualField(parent, {
            type = "color",
            field = true,
            hasAlpha = false,
            searchKey = "settings.appearance.tab_color",
            label = T("settings.appearance.tab_color", "Tab color"),
            default = YChat.Defaults.appearance.tabColor,
            get = function()
                return Appearance().tabColor
            end,
            set = function(value)
                YChat:SetAppearanceValue("tabColor", value)
            end,
        })
    end
    AddSection(options, "settings.section.interface_behavior", "Interface behavior")
    options[#options + 1] = ManualField(parent, {
        type = "checkbox",
        labelPosition = "left",
        label = T(
            "settings.appearance.class_color_whisper_names",
            "Use class color for whisper names"
        ),
        get = function()
            return Appearance().classColorWhisperNames == true
        end,
        set = function(value)
            YChat:SetAppearanceValue("classColorWhisperNames", value == true)
        end,
    })
    options[#options + 1] = ManualField(parent, {
        type = "checkbox",
        labelPosition = "left",
        searchKey = "settings.appearance.hide_native_buttons",
        label = T("settings.appearance.hide_native_buttons", "Hide native button visuals"),
        get = function()
            return Appearance().hideNativeButtons == true
        end,
        set = function(value)
            YChat:SetAppearanceValue("hideNativeButtons", value == true)
        end,
    })
    options[#options + 1] = ManualField(parent, {
        type = "checkbox",
        labelPosition = "left",
        searchKey = "settings.appearance.hide_combat_log",
        label = T("settings.appearance.hide_combat_log", "Hide combat log window"),
        get = function()
            return Appearance().hideCombatLog == true
        end,
        set = function(value)
            YChat:SetAppearanceValue("hideCombatLog", value == true)
        end,
    })
    options[#options + 1] = ManualField(parent, {
        type = "dropdown",
        searchKey = "settings.appearance.message_effect",
        label = T("settings.appearance.message_effect", "Message effect"),
        width = CONTROL_WIDTH,
        options = {
            { text = T("settings.effect.none", "Off"), value = "none" },
            { text = T("settings.effect.fade", "Fade"), value = "fade" },
            { text = T("settings.effect.soft_glow", "Soft glow"), value = "softGlow" },
        },
        get = function()
            return Appearance().messageEffect
        end,
        set = function(value)
            YChat:SetAppearanceValue("messageEffect", value)
        end,
    })
    options[#options + 1] = ManualField(parent, {
        type = "dropdown",
        searchKey = "settings.appearance.tooltip_anchor",
        label = T("settings.appearance.tooltip_anchor", "Link tooltip position"),
        width = CONTROL_WIDTH,
        options = {
            { text = T("settings.tooltip.top", "Above"), value = "ANCHOR_TOP" },
            { text = T("settings.tooltip.bottom", "Below"), value = "ANCHOR_BOTTOM" },
            { text = T("settings.tooltip.top_left", "Top left"), value = "ANCHOR_TOPLEFT" },
            { text = T("settings.tooltip.top_right", "Top right"), value = "ANCHOR_TOPRIGHT" },
            { text = T("settings.tooltip.bottom_left", "Bottom left"), value = "ANCHOR_BOTTOMLEFT" },
            { text = T("settings.tooltip.bottom_right", "Bottom right"), value = "ANCHOR_BOTTOMRIGHT" },
            { text = T("settings.tooltip.left", "Left"), value = "ANCHOR_LEFT" },
            { text = T("settings.tooltip.right", "Right"), value = "ANCHOR_RIGHT" },
        },
        get = function()
            return Appearance().tooltipAnchor
        end,
        set = function(value)
            YChat:SetAppearanceValue("tooltipAnchor", value)
        end,
    })
    AddSection(options, "settings.section.full_fade", "Full fade")
    local fadeToggle = ManualField(parent, {
        type = "checkbox",
        labelPosition = "left",
        searchKey = "settings.appearance.fade_elements",
        label = T("settings.appearance.fade_elements", "Fully fade chat controls"),
        get = function()
            return Appearance().fadeElements == true
        end,
        set = function(value)
            YChat:SetAppearanceValue("fadeElements", value == true)
        end,
        onChange = function()
            Rerender(parent)
        end,
    })
    fadeToggle.ychatColumns = 1
    options[#options + 1] = fadeToggle
    if appearance.fadeElements == true then
        options[#options + 1] = ManualField(parent, {
            type = "dropdown",
            searchKey = "settings.appearance.fade_scope",
            label = T("settings.appearance.fade_scope", "Effective scope"),
            width = CONTROL_WIDTH,
            options = {
                { text = T("settings.fade_scope.all", "Everywhere"), value = "all" },
                {
                    searchKey = "settings.fade_scope.outside_instance",
                    text = T("settings.fade_scope.outside_instance", "Outside instances"),
                    value = "outsideInstance",
                },
                {
                    searchKey = "settings.fade_scope.inside_instance",
                    text = T("settings.fade_scope.inside_instance", "Inside instances"),
                    value = "insideInstance",
                },
                {
                    searchKey = "settings.fade_scope.out_of_combat",
                    text = T("settings.fade_scope.out_of_combat", "Out of combat"),
                    value = "outOfCombat",
                },
                {
                    searchKey = "settings.fade_scope.solo",
                    text = T("settings.fade_scope.solo", "Solo"),
                    value = "solo",
                },
            },
            get = function()
                return Appearance().fadeScope or "solo"
            end,
            set = function(value)
                YChat:SetAppearanceValue("fadeScope", value)
            end,
        })
        options[#options + 1] = ManualField(parent, {
            type = "slider",
            searchKey = "settings.appearance.fade_delay",
            label = T("settings.appearance.fade_delay", "Fade delay (seconds)"),
            min = YChat.FADE_DELAY_MIN or 10,
            max = YChat.FADE_DELAY_MAX or 600,
            step = 10,
            precision = 0,
            instantUpdate = false,
            get = function()
                return Appearance().fadeDelay or 120
            end,
            set = function(value)
                YChat:SetAppearanceValue("fadeDelay", value)
            end,
        })
        options[#options + 1] = ManualField(parent, {
            type = "checkbox",
            labelPosition = "left",
            searchKey = "settings.appearance.fade_chat_bar",
            label = T("settings.appearance.fade_chat_bar", "Fade Chat Bar together"),
            get = function()
                return Appearance().fadeChatBar == true
            end,
            set = function(value)
                YChat:SetAppearanceValue("fadeChatBar", value == true)
            end,
        })
        options[#options + 1] = ManualField(parent, {
            type = "dropdown",
            searchKey = "settings.appearance.fade_stats",
            label = T("settings.appearance.fade_stats", "Fade stats panel together"),
            width = CONTROL_WIDTH,
            options = {
                { text = T("settings.fade_stats.none", "Do not link"), value = "none" },
                { text = T("settings.fade_stats.all", "Always link"), value = "all" },
                {
                    searchKey = "settings.fade_stats.out_of_combat",
                    text = T("settings.fade_stats.out_of_combat", "Link only out of combat"),
                    value = "outOfCombat",
                },
                {
                    searchKey = "settings.fade_stats.in_combat",
                    text = T("settings.fade_stats.in_combat", "Link only in combat"),
                    value = "inCombat",
                },
            },
            get = function()
                return Appearance().fadeStatsMode or "none"
            end,
            set = function(value)
                YChat:SetAppearanceValue("fadeStatsMode", value)
            end,
        })
    end
end

local function BuildLayoutOptions(parent, options)
    AddSection(options, "settings.section.message_text", "Message text")
    options[#options + 1] = ManualField(parent, {
        type = "font",
        searchKey = "settings.typography.font",
        label = T("settings.typography.font", "Font"),
        width = CONTROL_WIDTH,
        prependOptions = BuildNativeFontOptions,
        previewSelectedFont = false,
        get = function()
            return Typography().font or "__native"
        end,
        set = function(value)
            if value == "__native" then
                YChat:ResetTypographyValue("font")
            else
                YChat:SetTypographyValue("font", value)
            end
        end,
    })
    options[#options + 1] = ManualField(parent, {
        type = "checkbox",
        labelPosition = "left",
        searchKey = "settings.typography.custom_size",
        label = T("settings.typography.custom_size", "Override message size"),
        get = function()
            return Typography().fontSize ~= nil
        end,
        set = function(value)
            if value == true then
                YChat:SetTypographyValue("fontSize", 14)
            else
                YChat:ResetTypographyValue("fontSize")
            end
        end,
    })
    if Typography().fontSize ~= nil then
        options[#options + 1] = {
            type = "slider",
            searchKey = "settings.typography.font_size",
            label = T("settings.typography.font_size", "Message size"),
            min = YChat.BODY_FONT_MIN_SIZE,
            max = YChat.BODY_FONT_MAX_SIZE,
            step = 1,
            precision = 0,
            instantUpdate = false,
            get = function()
                return Typography().fontSize
            end,
            set = function(value)
                YChat:SetTypographyValue("fontSize", value)
            end,
        }
    end
    options[#options + 1] = ManualField(parent, {
        type = "dropdown",
        searchKey = "settings.typography.outline",
        label = T("settings.typography.outline", "Outline"),
        width = CONTROL_WIDTH,
        options = BuildOutlineOptions(true),
        get = function()
            return Typography().outline or "__native"
        end,
        set = function(value)
            if value == "__native" then
                YChat:ResetTypographyValue("outline")
            else
                YChat:SetTypographyValue("outline", value)
            end
        end,
    })
    options[#options + 1] = ManualField(parent, {
        type = "checkbox",
        labelPosition = "left",
        searchKey = "settings.typography.custom_spacing",
        label = T("settings.typography.custom_spacing", "Override line spacing"),
        get = function()
            return Typography().lineSpacing ~= nil
        end,
        set = function(value)
            if value == true then
                YChat:SetTypographyValue("lineSpacing", 0)
            else
                YChat:ResetTypographyValue("lineSpacing")
            end
        end,
    })
    if Typography().lineSpacing ~= nil then
        options[#options + 1] = {
            type = "slider",
            searchKey = "settings.typography.line_spacing",
            label = T("settings.typography.line_spacing", "Line spacing"),
            min = YChat.BODY_LINE_SPACING_MIN,
            max = YChat.BODY_LINE_SPACING_MAX,
            step = 1,
            precision = 0,
            instantUpdate = false,
            get = function()
                return Typography().lineSpacing
            end,
            set = function(value)
                YChat:SetTypographyValue("lineSpacing", value)
            end,
        }
    end
    AddSection(options, "settings.section.timestamp", "Timestamp")
    options[#options + 1] = {
        type = "checkbox",
        labelPosition = "left",
        searchKey = "settings.timestamp.enabled",
        label = T("settings.timestamp.enabled", "Show timestamps"),
        get = function()
            return YChat:IsTimestampEnabled()
        end,
        set = function(value)
            local _, changed, detail = YChat:SetTimestampEnabled(value == true)
            if changed and detail == "reload-required" and S.ShowReload then S:ShowReload() end
        end,
    }
    options[#options + 1] = ManualField(parent, {
        type = "dropdown",
        searchKey = "settings.timestamp.layout",
        label = T("settings.timestamp.layout", "Wrap style"),
        width = CONTROL_WIDTH,
        options = {
            {
                searchKey = "settings.timestamp.layout.column",
                text = T("settings.timestamp.layout.column", "Independent timestamp column"),
                value = "column",
            },
            {
                searchKey = "settings.timestamp.layout.native_inline",
                text = T("settings.timestamp.layout.native_inline", "Wrap below timestamp (native)"),
                value = "nativeInline",
            },
        },
        get = function()
            return Timestamp().layout
        end,
        set = function(value)
            local _, changed, detail = YChat:SetTimestampValue("layout", value)
            if changed and detail == "reload-required" and S.ShowReload then S:ShowReload() end
        end,
        onChange = function()
            Rerender(parent)
        end,
    })
    options[#options + 1] = ManualField(parent, {
        type = "dropdown",
        searchKey = "settings.timestamp.format",
        label = T("settings.timestamp.format", "Time format"),
        width = CONTROL_WIDTH,
        options = {
            { text = "HH:mm:ss", value = "hms" },
            { text = "HH:mm", value = "hm" },
        },
        get = function()
            return Timestamp().format
        end,
        set = function(value)
            local _, changed, detail = YChat:SetTimestampValue("format", value)
            if changed and detail == "reload-required" and S.ShowReload then S:ShowReload() end
        end,
    })
    local nativeInline = Timestamp().layout == "nativeInline"
    if nativeInline then
        options[#options + 1] = {
            type = "checkbox",
            labelPosition = "left",
            searchKey = "settings.timestamp.native_indent",
            label = T("settings.timestamp.native_indent", "Indent wrapped lines"),
            tooltip = T(
                "settings.timestamp.native_indent.tooltip",
                "Uses Blizzard's fixed continuation-line indent. This applies immediately."
            ),
            get = function()
                return Timestamp().nativeIndentedWrap == true
            end,
            set = function(value)
                YChat:SetTimestampValue("nativeIndentedWrap", value == true)
            end,
        }
    end
    options[#options + 1] = {
        type = "color",
        field = true,
        hasAlpha = not nativeInline,
        searchKey = "settings.timestamp.color",
        label = T("settings.timestamp.color", "Timestamp color"),
        default = YChat.Defaults.timestamp.color,
        get = function()
            return Timestamp().color
        end,
        set = function(value)
            local _, changed, detail = YChat:SetTimestampValue("color", value)
            if changed and detail == "reload-required" and S.ShowReload then S:ShowReload() end
        end,
    }
    if not nativeInline then
        options[#options + 1] = {
            type = "slider",
            searchKey = "settings.timestamp.gap",
            label = T("settings.timestamp.gap", "Timestamp gap"),
            min = YChat.TIMESTAMP_GAP_MIN,
            max = YChat.TIMESTAMP_GAP_MAX,
            step = 1,
            precision = 0,
            instantUpdate = false,
            get = function()
                return Timestamp().gap
            end,
            set = function(value)
                YChat:SetTimestampValue("gap", value)
            end,
        }
    end
    AddSection(options, "settings.section.window_size", "Window size")
    options[#options + 1] = {
        type = "slider",
        searchKey = "settings.layout.main_width",
        label = T("settings.layout.main_width", "Main chat width"),
        min = YChat.MAIN_WINDOW_MIN_WIDTH,
        max = YChat.MAIN_WINDOW_MAX_WIDTH,
        step = 1,
        precision = 0,
        instantUpdate = true,
        get = function()
            return Layout().mainWidth or 430
        end,
        set = function(value)
            YChat:SetLayoutValue("mainWidth", value)
        end,
    }
    options[#options + 1] = {
        type = "slider",
        searchKey = "settings.layout.main_height",
        label = T("settings.layout.main_height", "Main chat height"),
        min = YChat.MAIN_WINDOW_MIN_HEIGHT,
        max = YChat.MAIN_WINDOW_MAX_HEIGHT,
        step = 1,
        precision = 0,
        instantUpdate = true,
        get = function()
            return Layout().mainHeight or 180
        end,
        set = function(value)
            YChat:SetLayoutValue("mainHeight", value)
        end,
    }
end

local function BuildChannelInputOptions(parent, options)
    AddSection(options, "settings.section.item_links", "Item links")
    options[#options + 1] = {
        type = "checkbox",
        labelPosition = "left",
        searchKey = "settings.item_links.enabled",
        label = T("settings.item_links.enabled", "Enhance item links"),
        get = function() return YChat:GetDB().itemLinks.enabled == true end,
        set = function(value) YChat:SetItemLinksEnabled(value == true) end,
    }
    options[#options + 1] = {
        type = "checkbox",
        labelPosition = "left",
        searchKey = "settings.item_links.crop_icons",
        label = T("settings.item_links.crop_icons", "Zoom and crop icons"),
        get = function() return YChat:GetDB().itemLinks.cropIcons ~= false end,
        set = function(value) YChat:SetItemLinksCropIcons(value == true) end,
    }
    AddSection(options, "settings.section.channel_display", "Channel display")
    options[#options + 1] = {
        type = "checkbox",
        labelPosition = "left",
        searchKey = "settings.channel.hide_player_realm",
        label = T("settings.channel.hide_player_realm", "Hide player realm names"),
        get = function() return ChannelInput().hidePlayerRealm == true end,
        set = function(value) YChat:SetChannelInputValue("hidePlayerRealm", value == true) end,
    }
    options[#options + 1] = {
        type = "dropdown",
        searchKey = "settings.channel.public_format",
        label = T("settings.channel.public_format", "Public channels"),
        width = CONTROL_WIDTH,
        options = {
            { text = T("settings.channel.public.native", "Native full name"), value = "native" },
            { text = T("settings.channel.public.number_short", "Number + short name"), value = "numberShort" },
            { text = T("settings.channel.public.short", "Short name only"), value = "short" },
        },
        get = function() return ChannelInput().publicFormat or "numberShort" end,
        set = function(value) YChat:SetChannelInputValue("publicFormat", value) end,
    }
    AddSection(options, "settings.section.input", "Input box")
    options[#options + 1] = {
        type = "checkbox",
        labelPosition = "left",
        searchKey = "settings.channel.tab_cycle",
        label = T("settings.channel.tab_cycle", "Use Tab / Shift+Tab to cycle chat targets"),
        get = function()
            return ChannelInput().tabCycle == true
        end,
        set = function(value)
            YChat:SetChannelInputValue("tabCycle", value == true)
        end,
    }
    options[#options + 1] = ManualField(parent, {
        type = "dropdown",
        searchKey = "settings.layout.input_position",
        label = T("settings.layout.input_position", "Input position"),
        width = CONTROL_WIDTH,
        options = {
            { text = T("settings.input.top", "Above chat window"), value = "top" },
            { text = T("settings.input.bottom", "Below chat window"), value = "bottom" },
        },
        get = function()
            return Appearance().inputPosition
        end,
        set = function(value)
            YChat:SetAppearanceValue("inputPosition", value)
        end,
    })
    options[#options + 1] = ManualField(parent, {
        type = "slider",
        searchKey = "settings.layout.input_height",
        label = T("settings.layout.input_height", "Input height"),
        min = YChat.INPUT_HEIGHT_MIN or 20,
        max = YChat.INPUT_HEIGHT_MAX or 48,
        step = 1,
        precision = 0,
        instantUpdate = true,
        get = function()
            return Appearance().inputHeight
        end,
        set = function(value)
            YChat:PreviewInputHeight(value)
        end,
        onCommit = function(_, value)
            YChat:CommitInputHeight(value)
        end,
    })
end

local function BuildListEditor(parent, key, labelKey, labelFallback, placeholderKey, placeholderFallback)
    return {
        type = "custom",
        render = function(container, x, y, width)
            if not (GUI2 and GUI2.Form and GUI2.Form.CreateEditBox and GUI2.Form.CreateButton) then
                return width, 0
            end
            local values = AutoInvite()[key] or {}
            local label = GUI2:CreateText(
                container,
                T(labelKey, labelFallback),
                "font.size.md",
                "color.text.primary"
            )
            label:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)

            local input = GUI2.Form:CreateEditBox(container, {
                width = 320,
                height = 26,
                text = "",
                autoFocus = false,
                tooltip = T(placeholderKey, placeholderFallback),
            })
            input:SetPoint("TOPLEFT", container, "TOPLEFT", x, y - 24)
            local add = GUI2.Form:CreateButton(container, {
                searchKey = "settings.rules.list_add",
                text = T("settings.rules.list_add", "Add"),
                width = 92,
                height = 26,
                tone = "accent",
                onClick = function()
                    local value = input:GetText()
                    if type(value) == "string" and value ~= "" then
                        YChat:AddAutoInviteListValue(key, value)
                        Rerender(parent)
                    end
                end,
            })
            add:SetPoint("LEFT", input, "RIGHT", 10, 0)

            local rowY = y - 58
            local availableWidth = max(120, min(width, SETTINGS_WIDTH))
            local cursorX = 0
            local row = 0
            for index = 1, #values do
                local value = values[index]
                local remove = GUI2.Form:CreateButton(container, {
                    text = value .. "  ×",
                    width = 64,
                    height = 24,
                    tone = "default",
                    relief = "hairline",
                    tooltip = T("settings.rules.list_remove", "Click to remove"),
                    onClick = function()
                        YChat:RemoveAutoInviteListValue(key, value)
                        Rerender(parent)
                    end,
                })
                local measuredWidth = 0
                if remove.text and remove.text.GetUnboundedStringWidth then
                    local ok, result = pcall(remove.text.GetUnboundedStringWidth, remove.text)
                    if ok and type(result) == "number" then measuredWidth = result end
                elseif remove.text and remove.text.GetStringWidth then
                    local ok, result = pcall(remove.text.GetStringWidth, remove.text)
                    if ok and type(result) == "number" then measuredWidth = result end
                end
                local buttonWidth = min(220, max(64, ceil(measuredWidth + 24)))
                if cursorX > 0 and cursorX + buttonWidth > availableWidth then
                    row = row + 1
                    cursorX = 0
                end
                remove:SetWidth(buttonWidth)
                remove:SetPoint(
                    "TOPLEFT",
                    container,
                    "TOPLEFT",
                    x + cursorX,
                    rowY - row * 28
                )
                cursorX = cursorX + buttonWidth + 8
            end
            local rows = #values > 0 and row + 1 or 0
            return width, 58 + rows * 28
        end,
    }
end

local function BuildRulesOptions(parent, options)
    AddSection(options, "settings.section.auto_invite", "Auto invite")
    options[#options + 1] = {
        type = "checkbox",
        labelPosition = "left",
        searchKey = "settings.rules.auto_invite_enabled",
        label = T("settings.rules.auto_invite_enabled", "Enable auto invite"),
        get = function()
            return AutoInvite().enabled == true
        end,
        set = function(value)
            YChat:SetAutoInviteValue("enabled", value == true)
            Rerender(parent)
        end,
    }
    options[#options].ychatColumns = 1
    if AutoInvite().enabled ~= true then return end
    options[#options + 1] = {
        type = "dropdown",
        searchKey = "settings.rules.match_mode",
        label = T("settings.rules.match_mode", "Match mode"),
        width = CONTROL_WIDTH,
        options = {
            { text = T("settings.rules.exact", "Exact"), value = "exact" },
            { text = T("settings.rules.prefix", "Prefix"), value = "prefix" },
            { text = T("settings.rules.contains", "Contains"), value = "contains" },
        },
        get = function() return AutoInvite().matchMode end,
        set = function(value) YChat:SetAutoInviteValue("matchMode", value) end,
    }
    options[#options + 1] = BuildListEditor(
        parent,
        "keywords",
        "settings.rules.invite_keywords",
        "Invite keywords",
        "settings.rules.keyword_placeholder",
        "Enter one keyword"
    )
    options[#options + 1] = BuildListEditor(
        parent,
        "allowlist",
        "settings.rules.allowlist",
        "Allowlist",
        "settings.rules.name_placeholder",
        "Character name or BattleTag"
    )
    options[#options + 1] = BuildListEditor(
        parent,
        "denylist",
        "settings.rules.denylist",
        "Denylist",
        "settings.rules.name_placeholder",
        "Character name or BattleTag"
    )
    AddSection(options, "settings.section.rate_limits", "Rate-limit protection")
    options[#options + 1] = {
        type = "slider",
        searchKey = "settings.rules.sender_cooldown",
        label = T("settings.rules.sender_cooldown", "Sender cooldown"),
        min = 1,
        max = 60,
        step = 1,
        precision = 0,
        instantUpdate = false,
        get = function() return AutoInvite().senderCooldown end,
        set = function(value) YChat:SetAutoInviteValue("senderCooldown", value) end,
    }
    options[#options + 1] = {
        type = "slider",
        searchKey = "settings.rules.rate_limit",
        label = T("settings.rules.rate_limit", "Global invite limit"),
        min = 1,
        max = 20,
        step = 1,
        precision = 0,
        instantUpdate = false,
        get = function() return AutoInvite().rateLimit end,
        set = function(value) YChat:SetAutoInviteValue("rateLimit", value) end,
    }
    options[#options + 1] = {
        type = "slider",
        searchKey = "settings.rules.rate_window",
        label = T("settings.rules.rate_window", "Rate window"),
        min = 1,
        max = 60,
        step = 1,
        precision = 0,
        instantUpdate = false,
        get = function() return AutoInvite().rateWindow end,
        set = function(value) YChat:SetAutoInviteValue("rateWindow", value) end,
    }
end

local function BuildHistoryAction(parent, options)
    return {
        type = "custom",
        ychatHistoryAction = true,
        render = function(container, x, y, width)
            if not (GUI2 and GUI2.Form and GUI2.Form.CreateButton) then
                return width, 0
            end
            local button = GUI2.Form:CreateButton(container, {
                text = options.label,
                width = HISTORY_ACTION_WIDTH,
                height = 30,
                tone = options.tone,
                onClick = options.onClick,
            })
            button:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)
            if S.Search then S.Search:Bind(options, button) end
            if options.status and options.status ~= "" then
                local status = GUI2:CreateText(
                    container,
                    options.status,
                    "font.size.md",
                    "color.text.muted"
                )
                status:SetPoint("LEFT", button, "RIGHT", 16, 0)
                status:SetWidth(max(1, min(width or SETTINGS_WIDTH, SETTINGS_WIDTH)
                    - HISTORY_ACTION_WIDTH - 16))
                status:SetJustifyH("LEFT")
                status:SetWordWrap(false)
            end
            return min(width or SETTINGS_WIDTH, SETTINGS_WIDTH), 30
        end,
    }
end

local function BuildRecordsOptions(parent, options)
    local historyRuntime = YChat.HistoryRuntime
    local storedCount = historyRuntime
        and historyRuntime.GetCount
        and historyRuntime:GetCount()
        or 0
    local storedCharacterCount = historyRuntime
        and historyRuntime.GetCharacterCount
        and historyRuntime:GetCharacterCount()
        or 0
    AddSection(options, "settings.section.local_history", "Local history")
    options[#options + 1] = {
        type = "checkbox",
        labelPosition = "left",
        searchKey = "settings.records.retain",
        label = T("settings.records.retain", "Keep limited chat history"),
        get = function() return History().enabled == true end,
        set = function(value)
            YChat:SetHistoryValue("enabled", value == true)
            Rerender(parent)
        end,
    }
    options[#options].ychatColumns = 1
    options[#options + 1] = {
        type = "dropdown",
        searchKey = "settings.records.frame_limit",
        label = T("settings.records.frame_limit", "Chat window limit"),
        width = CONTROL_WIDTH,
        options = {
            { text = "50", value = 50 },
            { text = "100", value = 100 },
            { text = "200", value = 200 },
            { text = "300", value = 300 },
            { text = "500", value = 500 },
            { text = "1,000", value = 1000 },
        },
        get = function() return History().frameLimit end,
        set = function(value) YChat:SetHistoryValue("frameLimit", value) end,
    }
    options[#options + 1] = {
        type = "dropdown",
        searchKey = "settings.records.local_limit",
        label = T("settings.records.local_limit", "History record limit"),
        width = CONTROL_WIDTH,
        options = {
            { text = "500", value = 500 },
            { text = "1,000", value = 1000 },
            { text = "2,000", value = 2000 },
            { text = "5,000", value = 5000 },
        },
        get = function() return History().limit end,
        set = function(value) YChat:SetHistoryValue("limit", value) end,
    }
    if History().enabled == true then
        options[#options + 1] = {
            type = "checkbox",
            labelPosition = "left",
            searchKey = "settings.records.restore_on_login",
            label = T("settings.records.restore_on_login", "Restore history after login"),
            get = function() return History().restoreOnLogin == true end,
            set = function(value)
                YChat:SetHistoryValue("restoreOnLogin", value == true)
                Rerender(parent)
            end,
        }
        if History().restoreOnLogin == true then
            options[#options + 1] = {
                type = "slider",
                searchKey = "settings.records.restore_limit",
                label = T("settings.records.restore_limit", "Messages restored after login"),
                min = YChat.HISTORY_RESTORE_LIMIT_MIN or 10,
                max = YChat.HISTORY_RESTORE_LIMIT_MAX or 200,
                step = 10,
                precision = 0,
                instantUpdate = false,
                get = function() return History().restoreLimit end,
                set = function(value) YChat:SetHistoryValue("restoreLimit", value) end,
            }
        end
        AddSection(options, "settings.section.history_categories", "Recorded content")
        local categoryFields = {
            { "player", "settings.records.category.player", "Player chat" },
            { "guild", "settings.records.category.guild", "Guild and officer" },
            { "group", "settings.records.category.group", "Party, raid and instance" },
            { "channel", "settings.records.category.channel", "Public and community channels" },
            { "whisper", "settings.records.category.whisper", "Whispers" },
            { "output", "settings.records.category.output", "YUI and debug output" },
            { "system", "settings.records.category.system", "System messages" },
            { "rewards", "settings.records.category.rewards", "Loot and currency" },
            { "achievement", "settings.records.category.achievement", "Achievements" },
        }
        for index = 1, #categoryFields do
            local definition = categoryFields[index]
            local key = definition[1]
            options[#options + 1] = {
                type = "checkbox",
                labelPosition = "left",
                label = T(definition[2], definition[3]),
                get = function() return YChat:GetHistoryCategoryValue(key) == true end,
                set = function(value)
                    YChat:SetHistoryCategoryValue(key, value == true)
                end,
            }
        end
    end
    AddSection(options, "settings.section.history_actions", "History actions")
    options[#options + 1] = BuildHistoryAction(parent, {
        searchKey = "settings.records.open",
        label = T("settings.records.open", "Open chat history"),
        onClick = function()
            YChat:OpenHistorySnapshot()
        end,
    })
    options[#options + 1] = BuildHistoryAction(parent, {
        searchKey = "settings.records.clear",
        label = T("settings.records.clear", "Clear this character's history"),
        tone = "danger",
        status = storedCount > 0 and string.format(
            T("settings.records.saved_messages", "Saved: %d messages"),
            storedCount
        ) or nil,
        onClick = function()
            local function Clear()
                YChat:ClearCharacterHistory()
                Rerender(parent)
            end
            if S.ShowConfirmPopup then
                S:ShowConfirmPopup(
                    T(
                        "settings.records.clear_confirm",
                        "Clear only this character's saved YChat history? Blizzard chat windows are not affected."
                    ),
                    Clear,
                    {
                        titleText = T("settings.records.clear_confirm_title", "Clear chat history"),
                        acceptTone = "danger",
                    }
                )
            else
                Clear()
            end
        end,
    })
    options[#options + 1] = BuildHistoryAction(parent, {
        searchKey = "settings.records.clear_all",
        label = T("settings.records.clear_all", "Clear all characters' history"),
        tone = "danger",
        status = storedCharacterCount > 0 and string.format(
            T("settings.records.saved_characters", "Saved: %d characters"),
            storedCharacterCount
        ) or nil,
        onClick = function()
            local function Clear()
                YChat:ClearAllHistory()
                Rerender(parent)
            end
            if S.ShowConfirmPopup then
                S:ShowConfirmPopup(
                    T(
                        "settings.records.clear_all_confirm",
                        "Clear saved YChat history for all characters? Blizzard chat windows are not affected."
                    ),
                    Clear,
                    {
                        titleText = T("settings.records.clear_all_confirm_title", "Clear all chat history"),
                        acceptTone = "danger",
                    }
                )
            else
                Clear()
            end
        end,
    })
end

Render = function(parent)
    local controller, yielded = YChat.GetYieldController and YChat:GetYieldController()
    if not yielded and YChat.ConflictGuard and type(YChat.ConflictGuard.Check) == "function" then
        local conflict = YChat.ConflictGuard:Check()
        if type(conflict) == "table" and conflict.blocked == true
            and conflict.status == "active" then
            controller, yielded = conflict.controller, true
        end
    end
    if yielded then
        S:RenderConfig(parent, {
            { type = "text", label = S:FormatYieldNotice("chat", controller), colorKey = "color.text.primary" },
        })
        return
    end
    local options = {
        {
            type = "header",
            searchKey = "settings.title",
            label = T("settings.title", "Chat"),
        },
        BuildPageNavigation(parent),
        { type = "space", height = 8 },
    }
    if activePage == "layout" then
        BuildLayoutOptions(parent, options)
    elseif activePage == "channelInput" then
        BuildChannelInputOptions(parent, options)
    elseif activePage == "rules" then
        BuildRulesOptions(parent, options)
    elseif activePage == "records" then
        BuildRecordsOptions(parent, options)
    else
        BuildAppearanceOptions(parent, options)
    end
    S:RenderConfig(parent, ApplyCardSectionLayout(options))
end

local function EnsureNavigationEntry()
    local order = S.ModuleOrder
    if type(order) ~= "table" then return end

    for index = 1, #order do
        if order[index] == YChat.SETTINGS_ENTRY then
            return
        end
    end

    for index = 1, #order do
        if order[index] == "suite.settings.sound" or order[index] == "settings.appearance" then
            tinsert(order, index, YChat.SETTINGS_ENTRY)
            return
        end
    end

    tinsert(order, YChat.SETTINGS_ENTRY)
end

EnsureNavigationEntry()

S:RegisterModule("YChat", 2056011, Render, {
    id = YChat.SETTINGS_ENTRY,
    product = YChat.PRODUCT_ID,
    scope = YChat.PRODUCT_ID,
    titleKey = "settings.title",
    titleNamespace = "YChat",
    navTitleKey = "settings.nav",
    navTitleNamespace = "YChat",
    navToggle = { moduleId = YChat.PRODUCT_ID },
})

if S.Search then
    S.Search:RegisterRoute(YChat.SETTINGS_ENTRY, function(page)
        if page == "appearance" or page == "layout" or page == "channelInput" or page == "rules" or page == "records" then
            activePage = page
        end
    end)
end

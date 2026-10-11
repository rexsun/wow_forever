local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local S = YUI and YUI.Settings
local GUI2 = YUI and YUI.GUI2
local Assets = YUI and YUI.Assets
if not (YHUD and S and S.RegisterModule and GUI2 and GUI2.Form) then
    return
end

local CelestialSeries = S.CelestialSeries
local SETTINGS_ICON = CelestialSeries
    and CelestialSeries:GetIcon("yhud", 128)
    or ("Interface\\AddOns\\" .. (YUI.AddonName or "YUI")
        .. "\\Products\\YHUD\\Media\\icons"
        .. "\\logo_128.png")
local ASTROLABE_TEXTURE = Assets and Assets.Product
    and Assets:Product("yhud", "settings\\yhud-cooldown-astrolabe.png")
    or ("Interface\\AddOns\\" .. (YUI.AddonName or "YUI")
        .. "\\Products\\YHUD\\Media\\settings\\yhud-cooldown-astrolabe.png")

local OVERVIEW_HEIGHT = 260
local CONFIG_NAME_WIDTH = 720
local CONFIG_NAME_HEIGHT = 36
local ACTION_HEIGHT = 52

local function T(key, fallback)
    return YHUD:T(key, fallback)
end

local function PrintDesignerOpenError(code, detail)
    local message = T(
        "designer.error_open",
        "Halo 监控台：无法打开设计界面："
    ) .. tostring(code or "designer-ui-unavailable")
    if detail ~= nil and tostring(detail) ~= "" then
        message = message .. " (" .. tostring(detail) .. ")"
    end
    if YUI.Print then
        YUI:Print(message)
    else
        print(message)
    end
end

local function PrintConfigSetOpenError(code, detail)
    local message = T(
        "settings.config_sets_error_open",
        "Halo 监控台：无法打开配置方案："
    ) .. tostring(code or "config-sets-unavailable")
    if detail ~= nil and tostring(detail) ~= "" then
        message = message .. " (" .. tostring(detail) .. ")"
    end
    if YUI.Print then YUI:Print(message) else print(message) end
end

local function CountMap(values)
    if type(values) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(values) do
        count = count + 1
    end
    return count
end

local function FormatAssignment(assignment)
    assignment = type(assignment) == "table" and assignment or {}
    local mode = assignment.mode or "none"
    if mode == "specs" then
        return string.format(
            T("settings.assignment.specs", "指定专精（%d）"),
            #(assignment.specKeys or {})
        )
    end
    if mode == "default" or mode == "all" then
        return T("settings.assignment.default", "默认")
    end
    return T("settings.assignment.none", "无")
end

local function SummarizeProfile(profile)
    profile = type(profile) == "table" and profile or {}
    return {
        monitorCount = CountMap(profile.monitors),
        groupCount = CountMap(profile.groups and profile.groups.items),
        resourceEnabled = YHUD:HasEnabledResourceGroup(profile),
    }
end

local function GetOverviewSummary()
    local selected
    local detail
    local catalog = YHUD.ConfigCatalog
    if catalog then
        local rows = catalog:List()
        if type(rows) == "table" then
            selected = rows[1]
            for index = 1, #rows do
                if rows[index].active then
                    selected = rows[index]
                    break
                end
            end
            local setId = selected and selected.set and selected.set.id
            if setId then detail = catalog:Get(setId) end
        end
    end

    local source = type(detail) == "table" and detail or selected or {}
    local summary = type(detail) == "table" and detail.summary or nil
    if type(summary) ~= "table" then
        summary = SummarizeProfile(YHUD:GetActiveProfile(false))
    end
    return {
        name = source.set and source.set.name or "-",
        assignmentText = FormatAssignment(source.assignment),
        monitorCount = tonumber(summary.monitorCount) or 0,
        groupCount = tonumber(summary.groupCount) or 0,
        resourcesEnabled = summary.resourceEnabled == true,
    }
end

local function CreateThemeSurface(parent, width, height)
    local surface = GUI2:CreateFrame(parent, {
        template = "BackdropTemplate",
        width = width,
        height = height,
        surface = "color.control.bg",
        border = "color.border.default",
        radiusKey = "layout.radius.control",
    })
    surface.gui2Surface = "color.control.bg"
    surface.RefreshTheme = function(frame)
        GUI2:RefreshPrimitive(frame)
    end
    GUI2:RegisterThemeObject(surface)
    return surface
end

local function CreateDivider(parent, width)
    local divider = GUI2:CreateTexture(parent, { layer = "ARTWORK" })
    divider:SetTexture("Interface\\Buttons\\WHITE8x8")
    divider:SetSize(width, 1)
    GUI2:SetTexturePaintKey(divider, "color.border.subtle")
    return divider
end

local function CreateStatistic(parent, text, width)
    local label = GUI2:CreateText(
        parent,
        text,
        "font.size.md",
        "color.text.secondary",
        "LEFT"
    )
    label:SetWidth(width)
    label:SetWordWrap(false)
    return label
end

local function CreateActionCard(parent, options)
    local button = GUI2.Form:CreateButton(parent, {
        text = "",
        width = options.width,
        height = options.height,
        tone = options.primary and "warning" or "default",
        onClick = options.onClick,
    })
    local colorKey = options.primary and "color.badge.orange"
        or "color.accent.primary"
    local icon = GUI2:CreateMicroIcon(button, {
        iconName = options.icon,
        size = 24,
        point = "TOPLEFT",
        relativePoint = "TOPLEFT",
        x = 16,
        y = options.primary and -20 or -12,
        colorKey = colorKey,
    })
    icon.gui2ColorKey = colorKey
    icon.RefreshTheme = function(region)
        region:SetVertexColor(GUI2:GetColor(region.gui2ColorKey))
    end
    GUI2:RegisterThemeObject(icon)
    local title = GUI2:CreateText(button, options.title,
        "font.size.lg", options.primary and "color.text.heading"
            or "color.text.primary", "LEFT")
    title:SetPoint("TOPLEFT", button, "TOPLEFT", 52,
        options.primary and -20 or -10)
    title:SetWidth(options.width - 88)
    title:SetWordWrap(false)
    local description = GUI2:CreateText(button, options.description,
        "font.size.sm", "color.text.secondary", "LEFT")
    description:SetPoint("TOPLEFT", button, "TOPLEFT",
        options.primary and 20 or 52, options.primary and -60 or -34)
    description:SetWidth(options.width - (options.primary and 40 or 68))
    description:SetWordWrap(true)
    local arrow = GUI2:CreateText(button, "›", "font.size.lg",
        "color.text.secondary", "RIGHT")
    arrow:SetPoint("TOPRIGHT", button, "TOPRIGHT", -16, -12)
    return button
end

local function RenderOverview(
    container,
    x,
    y,
    availableWidth,
    settingsParent,
    activeConfigName,
    monitorCount,
    groupCount,
    resourcesText,
    assignmentText
)
    local contentWidth = math.min(tonumber(availableWidth) or 900, 900)
    local overview = GUI2:CreateFrame(container, {
        width = contentWidth,
        height = OVERVIEW_HEIGHT,
    })
    overview:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)

    -- Keep decoration inside the measured page so it cannot extend scroll bounds.
    local ornament = GUI2:CreateTexture(container, { layer = "BACKGROUND" })
    ornament:SetTexture(ASTROLABE_TEXTURE)
    ornament:SetSize(420, 420)
    ornament:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -20, 20)
    ornament:SetBlendMode("ADD")
    ornament:SetAlpha(0.10)

    local currentLabel = GUI2:CreateText(
        overview,
        T("settings.current_config", "当前配置"),
        "font.size.lg",
        "color.text.heading",
        "LEFT"
    )
    currentLabel:SetPoint("TOPLEFT", overview, "TOPLEFT", 0, 0)
    currentLabel:SetWordWrap(false)

    local nameWidth = math.min(CONFIG_NAME_WIDTH, contentWidth)
    local nameSurface = CreateThemeSurface(
        overview,
        nameWidth,
        CONFIG_NAME_HEIGHT
    )
    nameSurface:SetPoint("TOPLEFT", currentLabel, "BOTTOMLEFT", 0, -10)

    local nameText = GUI2:CreateText(
        nameSurface,
        activeConfigName,
        "font.size.lg",
        "color.text.primary",
        "LEFT"
    )
    nameText:SetPoint("LEFT", nameSurface, "LEFT", 12, 0)
    nameText:SetWidth(nameWidth - 24)
    nameText:SetWordWrap(false)

    local statsDivider = CreateDivider(overview, nameWidth)
    statsDivider:SetPoint("TOPLEFT", nameSurface, "BOTTOMLEFT", 0, -14)

    local stats = {
        {
            text = string.format(
                T("settings.status.monitors", "监控：%d"),
                monitorCount
            ),
            width = 128,
        },
        {
            text = string.format(
                T("settings.status.groups", "分组：%d"),
                groupCount
            ),
            width = 128,
        },
        { text = resourcesText, width = 184 },
        {
            text = string.format(
                T("settings.status.assignment", "应用范围：%s"),
                assignmentText
            ),
            width = nameWidth - 440,
        },
    }

    local statX = 0
    for index = 1, #stats do
        local stat = stats[index]
        local label = CreateStatistic(overview, stat.text, stat.width)
        label:SetPoint(
            "TOPLEFT",
            statsDivider,
            "BOTTOMLEFT",
            statX,
            -20
        )
        statX = statX + stat.width
        if index < #stats then
            local separator = CreateDivider(overview, 24)
            separator:ClearAllPoints()
            separator:SetSize(1, 24)
            separator:SetPoint(
                "TOPLEFT",
                statsDivider,
                "BOTTOMLEFT",
                statX - 16,
                -14
            )
        end
    end

    local actionWidth = (nameWidth - 10) / 2
    local configButton = CreateActionCard(overview, {
        title = T("settings.config_sets_entry", "配置方案"),
        description = T("settings.config_sets_caption", "管理、导入和分享方案"),
        icon = "panels-top-left",
        width = actionWidth,
        height = ACTION_HEIGHT,
        onClick = function()
            if YHUD.ConfigSets then
                local opened, code, detail =
                    YHUD.ConfigSets:Open(settingsParent)
                if not opened then PrintConfigSetOpenError(code, detail) end
            else
                PrintConfigSetOpenError("config-sets-unavailable")
            end
        end,
    })
    configButton:SetPoint("TOPLEFT", statsDivider, "BOTTOMLEFT", actionWidth + 10, -52)

    local designButton = CreateActionCard(overview, {
        title = T("settings.design_card", "监控设计"),
        description = T("settings.design_caption", "调整分组、布局与样式"),
        icon = "paintbrush",
        width = actionWidth,
        height = ACTION_HEIGHT * 2 + 10,
        primary = true,
        onClick = function()
            if not (YHUD.DesignerUI and YHUD.DesignerUI.Open) then
                PrintDesignerOpenError("designer-ui-unavailable")
                return
            end
            YHUD.DesignerUI:Open("settings")
        end,
    })
    designButton:SetPoint("TOPLEFT", statsDivider, "BOTTOMLEFT", 0, -52)

    local blizzardButton = CreateActionCard(overview, {
        title = T("settings.blizzard_card", "暴雪冷却"),
        description = T("settings.blizzard_caption", "选择需要追踪的技能"),
        icon = "settings",
        width = actionWidth,
        height = ACTION_HEIGHT,
        onClick = function()
            if YHUD.DesignerUI
                and YHUD.DesignerUI.OpenBlizzardCooldownSettings then
                YHUD.DesignerUI:OpenBlizzardCooldownSettings()
            end
        end,
    })
    blizzardButton:SetPoint("TOPLEFT", configButton, "BOTTOMLEFT", 0, -10)

    if S.Search then
        S.Search:Bind({ searchKey = "settings.config_sets_entry" }, configButton)
        S.Search:Bind({ searchKey = "settings.enter_designer" }, designButton)
        S.Search:Bind({ searchKey = "designer.blizzard_cooldown_settings" }, blizzardButton)
    end
    return contentWidth, OVERVIEW_HEIGHT
end

local function Render(parent)
    local controller, yielded = YHUD.GetYieldController
        and YHUD:GetYieldController()
    if yielded then
        S:RenderConfig(parent, {
            {
                type = "text",
                label = S:FormatYieldNotice("cooldown", controller),
                colorKey = "color.text.primary",
            },
        })
        return
    end
    local summary = GetOverviewSummary()
    local resourcesText = summary.resourcesEnabled
        and T("settings.status.resources_enabled", "资源条：启用")
        or T("settings.status.resources_disabled", "资源条：停用")

    local config = {
        {
            type = "header",
            label = CelestialSeries
                and CelestialSeries:GetTitle(
                    "yhud",
                    T("product.brand_suffix", "Monitor")
                )
                or T("settings.title", "Halo Monitor"),
        },
    }
    if YHUD:IsInitialSpecialization() then
        config[#config + 1] = {
            type = "text",
            label = T(
                "settings.status.initial_specialization",
                "未获得正式专精，仅运行当前可用资源条"
            ),
            colorKey = "color.text.warning",
        }
    end
    config[#config + 1] = {
            type = "custom",
            render = function(container, x, y, width)
                return RenderOverview(
                    container,
                    x,
                    y,
                    width,
                    parent,
                    summary.name,
                    summary.monitorCount,
                    summary.groupCount,
                    resourcesText,
                    summary.assignmentText
                )
            end,
        }
    config[#config + 1] = {
        type = "header",
        searchKey = "settings.global",
        label = T("settings.global", "全局设置"),
    }
    local leftConfig = { {
        type = "checkbox",
        rowHeight = 32,
        rowGap = 10,
        searchKey = "settings.auto_hide_personal_resource",
        text = T("settings.auto_hide_personal_resource", "自动隐藏系统个人资源"),
        tooltip = T("settings.auto_hide_personal_resource.tooltip",
            "监控台及其资源条启用时，自动隐藏系统个人资源；关闭后恢复接管前的设置。"),
        get = function() return YHUD:GetConsolePreference("autoHidePersonalResource") end,
        set = function(value) YHUD:SetConsolePreference("autoHidePersonalResource", value) end,
    }, {
        type = "checkbox",
        rowHeight = 32,
        rowGap = 10,
        searchKey = "settings.sound_enabled",
        disabled = YHUD.Client and YHUD.Client.soundReminders == false,
        text = T("settings.sound_enabled", "监控台声音全局开关"),
        tooltip = T("settings.sound_enabled.tooltip",
            "控制全部监控声音提醒，不修改各监控的声音规则。"),
        get = function() return YHUD:GetConsolePreference("soundEnabled") end,
        set = function(value) YHUD:SetConsolePreference("soundEnabled", value) end,
    } }
    local rightConfig = { {
        type = "slider",
        searchKey = "settings.resource_only_below_level",
        label = T("settings.low_level_hide", "低等级时隐藏"),
        labelWidth = 120,
        controlWidth = 154,
        valueWidth = 56,
        gap = 10,
        rowWidth = 350,
        rowHeight = 32,
        rowGap = 10,
        tooltip = T("settings.resource_only_below_level.tooltip",
            "角色低于所设等级时，隐藏所选范围的分组；达到该等级后恢复原有显示规则。0 表示关闭。账号内所有角色共用，设计和布局编辑仍可预览全部分组，不影响声音提醒。"),
        min = 0,
        max = YHUD:GetLevelDisplayMaximum(),
        step = 1,
        default = 10,
        get = function() return YHUD:GetResourceOnlyBelowLevel() end,
        set = function(value) YHUD:SetResourceOnlyBelowLevel(value) end,
    }, {
        type = "dropdown",
        inlineLabel = true,
        label = T("settings.low_level_hide_scope", "隐藏范围"),
        searchKey = "settings.low_level_hide_scope",
        labelWidth = 120,
        controlWidth = 220,
        rowWidth = 350,
        gap = 10,
        rowHeight = 32,
        rowGap = 10,
        tooltip = T("settings.low_level_hide_scope.tooltip",
            "原生分组指重要技能、效能技能、增益效果和状态栏，按分组身份判断。选择所有分组时，系统个人资源恢复接管前状态；达到阈值后恢复自动隐藏。"),
        options = {
            { value = "all", text = T("settings.low_level_hide_scope.all", "所有分组") },
            { value = "non-resource", text = T("settings.low_level_hide_scope.non_resource", "资源条以外所有分组") },
            { value = "native", text = T("settings.low_level_hide_scope.native", "仅隐藏原生分组") },
        },
        get = function() return YHUD:GetLowLevelHideScope() end,
        set = function(value) YHUD:SetLowLevelHideScope(value) end,
    } }
    config[#config + 1] = {
        type = "custom",
        render = function(container, x, y, availableWidth)
            local width = math.min(CONFIG_NAME_WIDTH, availableWidth)
            local gap = 20
            local rightWidth = 350
            local leftWidth = width - rightWidth - gap
            local pageLayout = S.ModulePageLayout
            local insetX = pageLayout and pageLayout.insetX or 20
            local titleTop = pageLayout and pageLayout.titleTop or 20
            local left = GUI2:CreateFrame(container, { width = leftWidth + insetX * 2 })
            local right = GUI2:CreateFrame(container, { width = rightWidth + insetX * 2 })
            -- Nested standard forms supply their own insets; align their content to this block.
            left:SetPoint("TOPLEFT", container, "TOPLEFT", x - insetX, y + titleTop)
            right:SetPoint("TOPLEFT", container, "TOPLEFT", x + leftWidth + gap - insetX, y + titleTop)
            S:RenderConfig(left, leftConfig)
            S:RenderConfig(right, rightConfig)
            return width, math.max(left:GetHeight(), right:GetHeight()) - titleTop - 20
        end,
    }
    S:RenderConfig(parent, config)
    if YHUD.IS_STANDALONE and S.CreateProductHeaderMinimapButton then
        local button = S:CreateProductHeaderMinimapButton(parent, YHUD.PRODUCT_ID, { size = 24 })
        if button then button:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -20, -18) end
    end
end

S:RegisterModule("Halo Monitor", SETTINGS_ICON, Render, {
    id = YHUD.SETTINGS_ENTRY,
    product = YHUD.PRODUCT_ID,
    scope = YHUD.PRODUCT_ID,
    titleKey = "settings.title",
    titleNamespace = "YHUD",
    navTitleKey = "settings.nav",
    navTitleNamespace = "YHUD",
    navIconCrop = false,
    navIconSize = CelestialSeries and CelestialSeries.NAV_ICON_SIZE or 26,
    navToggle = not YHUD.IS_STANDALONE and { moduleId = YHUD.PRODUCT_ID } or nil,
})

local ADDON_NAME = ...
local YUI = _G.YUI
local S = YUI.Settings
local GUI2 = YUI.GUI2
local Components = YUI.Components
local Assets = YUI.Assets
local LC = YUI.Locale:Get("Core")
local CelestialSeries = S.CelestialSeries
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or (_G.YUI_CORE_EMBED_STATE and _G.YUI_CORE_EMBED_STATE[ADDON_NAME] and _G.YUI_CORE_EMBED_STATE[ADDON_NAME].productId)
    or YUI.ProductId or "suite"
local MODULE_ICON = CelestialSeries
    and CelestialSeries:GetIcon("toolbox", 128)
    or 132594

local MODULE_NAME = "组件管理"
local TAG_ALL = "全部"
local TAG_INTERFACE = "界面与兼容"
local currentTag = TAG_ALL
local currentView = "list"
local renderTarget
local moduleTarget
local activeSettingsFeature
local currentSettingsComponent
local resetToListOnNextShow = false

local MODULE_PAGE_LAYOUT = S.ModulePageLayout
    or { insetX = 20, titleTop = 20 }
local PAGE_INSET = MODULE_PAGE_LAYOUT.insetX
local PAGE_TITLE_TOP = MODULE_PAGE_LAYOUT.titleTop
local PAGE_TABS_TOP = 46
local PAGE_LIST_TOP = 68
local TOOLBOX_CARD_HEIGHT = 70
local TOOLBOX_ROW_GAP = 8

local RenderList, RenderSettings

-- Each module container owns its finite views. Build hidden, bind, then reveal.
local function SelectView(key, retained)
    local views = moduleTarget.yuiToolboxViews
    if not views then views = {}; moduleTarget.yuiToolboxViews = views end
    local page = views[key]
    if not page then
        page = GUI2:CreateFrame(moduleTarget)
        page:Hide()
        page:SetPoint("TOPLEFT", 0, 0)
        if retained then page.yuiRetainedBindings = {} end
        page.yuiConfigAfterRender = function(content, height)
            if renderTarget == content and moduleTarget then moduleTarget:SetHeight(height) end
        end
        views[key] = page
    end
    -- A core module refresh may detach children while retaining this owner.
    if page.GetParent and page:GetParent() ~= moduleTarget then
        page:Hide()
        page:SetParent(moduleTarget)
        page:ClearAllPoints()
        page:SetPoint("TOPLEFT", 0, 0)
    end
    page:SetWidth(moduleTarget:GetWidth())
    renderTarget = page
    return page
end

local function RevealView()
    for _, page in pairs(moduleTarget.yuiToolboxViews) do
        if page ~= renderTarget then page:Hide() end
    end
    moduleTarget:SetHeight(renderTarget:GetHeight())
    renderTarget:Show()
end

local function GetText(key, fallback)
    return LC[key] or fallback or key
end

local TAG_TEXT_KEYS = {
    ["全部"] = "settings.general.tag.all",
    ["实用功能"] = "settings.general.tag.utility",
    ["交易社交"] = "settings.general.tag.social",
    ["界面与兼容"] = "settings.general.tag.interface",
    ["美化皮肤"] = "settings.general.tag.skin",
    ["战斗辅助"] = "settings.general.tag.combat",
    ["系统修正"] = "settings.general.tag.system",
    ["插件适配"] = "settings.general.tag.adapter",
}

local TAG_TOOLTIP_KEYS = {
    ["全部"] = "settings.general.tag.all.tooltip",
    ["实用功能"] = "settings.general.tag.utility.tooltip",
    ["交易社交"] = "settings.general.tag.social.tooltip",
    ["界面与兼容"] = "settings.general.tag.interface.tooltip",
    ["战斗辅助"] = "settings.general.tag.combat.tooltip",
}

local CATEGORY_ORDER = {
    TAG_ALL,
    "实用功能",
    "交易社交",
    "战斗辅助",
    TAG_INTERFACE,
}

local CATEGORY_SOURCE_TAGS = {
    ["实用功能"] = { ["实用功能"] = true },
    ["交易社交"] = { ["交易社交"] = true },
    [TAG_INTERFACE] = {
        ["插件适配"] = true,
        ["美化皮肤"] = true,
        ["系统修正"] = true,
    },
    ["战斗辅助"] = { ["战斗辅助"] = true },
}

local function GetTagText(tag)
    return GetText(TAG_TEXT_KEYS[tag], tag)
end

local function RefreshCurrentModuleScroll(resetScroll)
    if S.RefreshCurrentModuleScroll and renderTarget and (not renderTarget.IsShown or renderTarget:IsShown()) then
        S:RefreshCurrentModuleScroll(resetScroll)
    end
end

local function RenderSettingsTitle(parent, x, y, width, title, onBack, asideText, action)
    local frameWidth = width or 620
    local frame = GUI2:CreateFrame(parent, { width = frameWidth, height = 34 })
    frame:SetPoint("TOPLEFT", x, y)

    local back = GUI2.Form:CreateButton(frame, {
        text = GetText("settings.back", "返回"),
        width = 80,
        onClick = onBack,
    })
    back:SetPoint("LEFT", frame, "LEFT", 0, 0)

    local text = GUI2:CreateText(frame, title or "", GUI2.Fonts.size_title, "color.text.heading")
    text:SetFont(GUI2.Fonts.header, GUI2.Fonts.size_title, "OUTLINE")
    text:SetPoint("LEFT", back, "RIGHT", 30, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)

    if action then
        local actions = action.actions or { action, action.secondary }
        local count = #actions
        for index = 1, count do
            local current = actions[index]
            local button = GUI2.Form:CreateButton(frame, {
                text = current.getText(), width = 100,
                height = current.height, tone = current.tone,
                tooltip = current.tooltip,
                onClick = function(widget)
                    current.onClick()
                    widget:SetText(current.getText())
                end,
            })
            button:SetPoint("RIGHT", frame, "RIGHT", -(count - index) * 108, 0)
            if current.bind then current.bind(button) end
        end
        text:SetWidth(math.max(frameWidth - 230 - (count - 1) * 108, 80))
    elseif type(asideText) == "string" and asideText ~= "" then
        local asideWidth = math.min(260, math.max(frameWidth - 280, 120))
        text:SetWidth(math.max(frameWidth - 110 - asideWidth - 20, 80))
        local aside = GUI2:CreateText(frame, asideText, "font.size.sm", "color.text.secondary", "RIGHT")
        aside:SetWidth(asideWidth)
        aside:SetJustifyH("RIGHT")
        aside:SetWordWrap(false)
        aside:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    end

    return frameWidth, 34
end

local function SelectComponentModule()
    if S.Open then
        S:Open({ scope = PRODUCT_ID })
    end

    for _, module in ipairs(S.modules or {}) do
        if module.name == MODULE_NAME then
            S:SelectModule(module)
            return module
        end
    end
end

local function BuildComponentTooltip(component)
    local description = component and component.description or ""
    if Components and Components.GetDescription then
        description = Components:GetDescription(component) or ""
    end
    local rows, failed
    if Components and Components.GetSubFeatureStates then
        rows, failed = Components:GetSubFeatureStates(component)
    end
    local enabled = Components:IsEnabled(component)
    local lines = { { text = " " }, { text = description, colorKey = "color.text.primary" } }
    if failed then
        lines[#lines + 1] = { text = " " }
        lines[#lines + 1] = { text = GetText("settings.general.summary_unavailable", "子功能状态暂不可用"), colorKey = "color.state.warning" }
    end
    rows = rows or {}
    local function AddGroup(shared)
        local added = false
        for _, row in ipairs(rows) do
            if (row.independent == true) == shared then
                if not added then
                    lines[#lines + 1] = { text = " " }
                    local heading = shared and GetText("settings.general.subfeature_shared", "共享功能")
                        or GetText("settings.general.subfeatures", "子功能")
                    if not shared and not enabled then
                        local r, g, b = GUI2:GetColor("color.state.error")
                        heading = heading .. string.format(" |cff%02x%02x%02x%s|r",
                            math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5),
                            GetText("settings.general.subfeatures_disabled_suffix", "（已禁用）"))
                    end
                    lines[#lines + 1] = { text = heading, colorKey = "color.state.warning" }
                    added = true
                end
                local active = shared or enabled
                lines[#lines + 1] = {
                    text = row.label,
                    right = row.enabled == true and GetText("settings.general.subfeature_on", "开启")
                        or row.enabled == false and GetText("settings.general.subfeature_off", "关闭")
                        or GetText("settings.general.subfeature_unknown", "未知"),
                    colorKey = active and "color.text.primary" or "color.text.secondary",
                    rightColorKey = not active and "color.text.secondary"
                        or row.enabled == true and (row.requires and "color.state.warning" or "color.state.success")
                        or row.enabled == false and "color.text.secondary" or "color.state.warning",
                }
                if row.enabled and row.requires then
                    lines[#lines + 1] = {
                        text = "  " .. string.format(GetText("settings.general.subfeature_requires", "需开启：%s"), row.requires),
                        colorKey = active and "color.state.warning" or "color.text.primary",
                    }
                end
            end
        end
        if added and (shared or not enabled) then
            lines[#lines + 1] = { text = shared
                and GetText("settings.general.subfeatures_independent", "不受组件开关影响。")
                or GetText("settings.general.subfeatures_disabled", "启用组件后，按以上配置生效。"),
                colorKey = "color.text.primary" }
        end
    end
    AddGroup(false)
    AddGroup(true)
    local r, g, b = GUI2:GetColor("color.text.accent")
    local actionColor = string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
    local action = enabled and GetText("settings.general.action_disable", "禁用组件")
        or GetText("settings.general.action_enable", "开启组件")
    local footer = {
        string.format(GetText("settings.general.left_click", "左键：%s"), actionColor .. action .. "|r"),
    }
    if (component.settingsMode or "toggleOnly") ~= "toggleOnly" then
        footer[#footer + 1] = string.format(GetText("settings.general.right_click", "右键：%s"),
            actionColor .. GetText("settings.general.action_settings", "打开设置") .. "|r")
    end
    return {
        footer = footer,
        status = enabled and GetText("settings.general.on", "已开启") or GetText("settings.general.off", "已禁用"),
        statusColorKey = enabled and "color.state.success" or "color.state.error",
        lines = lines,
    }
end

local function GetComponentName(component)
    if Components and Components.GetDisplayName then
        return Components:GetDisplayName(component)
    end
    return component and (component.displayName or component.name or component.id) or ""
end

local function GetToolboxComponentName(component)
    if Components and Components.GetToolboxDisplayName then
        return Components:GetToolboxDisplayName(component)
    end
    return GetComponentName(component)
end

local function ResolveComponentModSwitchImage(component)
    if not component then return nil end
    local image = component.modSwitchImage or component.modSwitchTexture
    if type(image) ~= "string" or image == "" then
        return nil
    end
    if image:match("^Interface[/\\]") then
        return image
    end
    if Assets and Assets.Component and component.id then
        return Assets:Component(component.id, image)
    end
    return image
end

local function GetComponentEffectiveState(component)
    if Components and Components.GetEffectiveState then
        return Components:GetEffectiveState(component)
    end
    return { effective = true }
end

local function IsComponentIneffective(component)
    if not (Components and Components.IsEnabled and Components:IsEnabled(component)) then
        return false, nil
    end
    local state = GetComponentEffectiveState(component)
    return state and state.effective == false, state
end

local function ConfirmBetaComponentEnable(component, commit)
    if type(commit) ~= "function" then
        return false
    end
    if S.ShowConfirmPopup then
        S:ShowConfirmPopup(GetText("settings.general.beta.confirm_message", "这是一个测试版组件，可能存在 BUG。如有问题，欢迎在 QQ 群上报错误信息。"), function()
            commit()
        end, {
            titleText = GetText("settings.general.beta.confirm_title", "测试版组件"),
            acceptText = GetText("settings.general.beta.confirm_accept", "继续开启"),
            cancelText = GetText("common.cancel", "取消"),
            acceptWidth = 110,
            cancelWidth = 100,
            acceptTone = "warning",
        })
        return true
    end
    commit()
    return true
end

local function OpenComponentSettings(component)
    if not component then return end
    if component.settingsMode == "external" then
        if component.openSettings then
            component:openSettings()
        end
        return
    end
    RenderSettings(component)
end

local function CallFeatureHook(feature, hookName)
    local hook = feature and feature[hookName]
    if type(hook) ~= "function" then return end

    local ok, err = pcall(hook, feature)
    if not ok then
        print("|cffff0000YUI Component Error:|r " .. tostring(feature.name or feature.id or "Unknown") .. " - " .. tostring(err))
    end
end

local function LeaveActiveSettings()
    if not activeSettingsFeature then return end

    local feature = activeSettingsFeature
    activeSettingsFeature = nil
    CallFeatureHook(feature, "OnSettingsLeave")
    if S.ClearRightPreview then
        S:ClearRightPreview()
    end
end

local function EnterSettings(component)
    local feature = component and (component.feature or component)
    if not feature or activeSettingsFeature == feature then return end

    LeaveActiveSettings()
    currentSettingsComponent = component
    activeSettingsFeature = feature
    CallFeatureHook(feature, "OnSettingsEnter")
end

local function ShouldShowComponent(component)
    if not component or (component.kind == "product" and component.toolboxManaged ~= true) then return false end
    local feature = component.feature or component
    local isVisible = feature and feature.IsVisible
    if type(isVisible) ~= "function" then return true end
    local ok, visible = pcall(isVisible, feature)
    return ok and visible ~= false
end

local function ComponentMatchesCategory(component, category)
    if category == TAG_ALL then return true end

    local sourceTags = CATEGORY_SOURCE_TAGS[category]
    if not sourceTags then return false end
    for _, tag in ipairs(component.tags or {}) do
        if sourceTags[tag] then
            return true
        end
    end
    return false
end

local function GetComponentList(category)
    local source = Components and Components:GetAll() or {}
    local list = {}
    for _, component in ipairs(source) do
        if ComponentMatchesCategory(component, category) and ShouldShowComponent(component) then
            list[#list + 1] = component
        end
    end
    return list
end

local function GetVisibleTags()
    local tags = { TAG_ALL }
    for index = 2, #CATEGORY_ORDER do
        local tag = CATEGORY_ORDER[index]
        if #GetComponentList(tag) > 0 then
            tags[#tags + 1] = tag
        end
    end
    return tags
end

local function EnsureCurrentTag(tags)
    for _, tag in ipairs(tags) do
        if tag == currentTag then
            return
        end
    end
    currentTag = tags[1] or TAG_ALL
end

local function RenderTagFilters(parent, x, y, width, tags)
    local availableWidth = width or 600
    local items = {}
    for _, tag in ipairs(tags) do
        local text = GetTagText(tag)
        local tooltipKey = TAG_TOOLTIP_KEYS[tag]
        items[#items + 1] = {
            text = text,
            value = tag,
            tooltip = tooltipKey and GetText(tooltipKey, text) or text,
        }
    end

    if parent.yuiToolboxTabs then
        parent.yuiToolboxTabs:SetItems(items, currentTag, availableWidth)
        return parent.yuiToolboxTabs
    end
    local tabs = GUI2.Form:CreateUnderlineTabs(parent, {
        width = availableWidth,
        value = currentTag,
        overflow = "scroll",
        contentAlignment = "CENTER",
        fontSizeKey = "font.size.lg",
        showBaseline = true,
        baselineHeight = 1,
        baselineColorKey = "color.border.subtle",
        indicatorHeight = 2,
        indicatorColorKey = "color.text.accent",
        items = items,
        onChange = function(_, value)
            currentTag = value or TAG_ALL
            RenderList()
        end,
    })
    tabs:SetPoint("TOPLEFT", x, y)
    parent.yuiToolboxTabs = tabs
    return tabs
end

RenderList = function()
    if not moduleTarget then return end
    SelectView("list")
    LeaveActiveSettings()
    if S.ClearRightPreview then
        S:ClearRightPreview()
    end
    currentSettingsComponent = nil
    currentView = "list"
    resetToListOnNextShow = false

    local tags = GetVisibleTags()
    EnsureCurrentTag(tags)

    local targetWidth = renderTarget:GetWidth() or 0
    if targetWidth < 360 then targetWidth = 700 end
    local pageWidth = math.max(targetWidth - (PAGE_INSET * 2), 320)
    local pageTitle = CelestialSeries
        and CelestialSeries:GetTitle(
            "toolbox",
            GetText("settings.brand_suffix.toolbox", "Toolbox")
        )
        or GetText("settings.general.title.nova", "Nova Toolbox")
    local title = renderTarget.yuiToolboxTitle
    if not title then
        title = GUI2:CreateText(renderTarget, pageTitle, "font.size.title", "color.text.heading")
        renderTarget.yuiToolboxTitle = title
    end
    title:SetText(pageTitle)
    title:SetPoint("TOPLEFT", PAGE_INSET, -PAGE_TITLE_TOP)
    if S.CreateProductHeaderMinimapButton and not renderTarget.yuiHeaderButtonCreated then
        renderTarget.yuiHeaderButtonCreated = true
        local minimapButton = S:CreateProductHeaderMinimapButton(renderTarget, PRODUCT_ID, { size = 24 })
        if minimapButton then
            minimapButton:SetPoint("TOPRIGHT", renderTarget, "TOPRIGHT", -20, -18)
        end
    end
    RenderTagFilters(renderTarget, PAGE_INSET, -PAGE_TABS_TOP, pageWidth, tags)

    local listContent = renderTarget.yuiListContent
    if not listContent then
        listContent = GUI2:CreateFrame(renderTarget)
        listContent.cards = {}
        renderTarget.yuiListContent = listContent
    end
    listContent:SetPoint("TOPLEFT", 0, -PAGE_LIST_TOP)
    listContent:SetWidth(targetWidth)

    local config = {}

    local list = GetComponentList(currentTag)
    if #list == 0 then
        config[#config + 1] = {
            type = "text",
            label = GetText("settings.general.empty", "当前标签下没有可显示组件。"),
            colorKey = "color.text.muted",
        }
    else
        local row = { type = "row", gap = 12, rowGap = TOOLBOX_ROW_GAP, children = {} }
        for _, component in ipairs(list) do
            local mode = component.settingsMode or "toggleOnly"
            local item = {
                type = "mod-switch",
                retainedId = component.id,
                label = GetToolboxComponentName(component),
                text = "",
                tooltip = function() return BuildComponentTooltip(component) end,
                showTags = false,
                width = 160,
                height = TOOLBOX_CARD_HEIGHT,
                image = ResolveComponentModSwitchImage(component),
                imageCrop = component.modSwitchImageCrop,
                imageTexCoords = component.modSwitchImageTexCoords,
                imageInset = component.modSwitchImageInset,
                settingsButtonSize = 22,
                settingsButtonPadding = 1,
                settingsButtonMicroIconSize = 20,
                default = component.defaultEnabled ~= false,
                onLabel = GetText("settings.general.on", "已开启"),
                offLabel = GetText("settings.general.off", "已禁用"),
                isBeta = component.isBeta == true,
                betaLabel = GetText("settings.general.beta.label", "测试版"),
                get = function()
                    return Components:IsEnabled(component)
                end,
                set = function(value)
                    Components:SetEnabled(component, value)
                end,
                getEffectiveState = function()
                    return GetComponentEffectiveState(component)
                end,
            }

            if component.isBeta == true then
                item.confirmEnable = function(frame, commit)
                    return ConfirmBetaComponentEnable(component, commit)
                end
            end

            if mode ~= "toggleOnly" then
                item.settingsClick = function()
                    OpenComponentSettings(component)
                end
                item.settingsTooltip = mode == "external"
                    and GetText("settings.general.external_settings", "打开独立设置页")
                    or GetText("settings.generic_settings", "设置")
            end

            row.children[#row.children + 1] = item
            if #row.children == 4 then
                config[#config + 1] = row
                row = { type = "row", gap = 12, rowGap = TOOLBOX_ROW_GAP, children = {} }
            end
        end
        if #row.children > 0 then
            config[#config + 1] = row
        end
    end

    -- Cards survive category changes; only the visible layout is recomputed.
    for _, card in pairs(listContent.cards) do card:Hide() end
    -- Preserve the toolbox's original four-card rows, independent of scroll width.
    local columns = 4
    local index = 0
    for _, row in ipairs(config) do
        for _, item in ipairs(row.children or {}) do
            local card = listContent.cards[item.retainedId]
            if not card then
                card = GUI2.Application:CreateModSwitch(listContent, item)
                card.yuiToolboxItem = item
                listContent.cards[item.retainedId] = card
            end
            local binding = card.yuiToolboxItem
            if binding ~= item then
                for key in pairs(binding) do binding[key] = nil end
                for key, value in pairs(item) do binding[key] = value end
            end
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", PAGE_INSET + (index % columns) * 172,
                -PAGE_TITLE_TOP - math.floor(index / columns) * (TOOLBOX_CARD_HEIGHT + TOOLBOX_ROW_GAP))
            card:SetValue(item.get(), true)
            if S.Search then S.Search:Bind(item, card) end
            card:Show()
            index = index + 1
        end
    end
    if index == 0 then
        if not listContent.emptyText then
            listContent.emptyText = GUI2:CreateText(listContent,
                GetText("settings.general.empty", "当前标签下没有可显示组件。"), "font.size.md", "color.text.muted")
            listContent.emptyText:SetPoint("TOPLEFT", PAGE_INSET, -PAGE_TITLE_TOP)
        end
        listContent.emptyText:Show()
    elseif listContent.emptyText then listContent.emptyText:Hide() end
    listContent:SetHeight(PAGE_TITLE_TOP + math.max(1, math.ceil(index / columns))
        * (TOOLBOX_CARD_HEIGHT + TOOLBOX_ROW_GAP) + 20)
    renderTarget:SetHeight(PAGE_LIST_TOP + listContent:GetHeight())
    RevealView()
    RefreshCurrentModuleScroll(true)
end

local function GetComponentOptions(component)
    local feature = component.feature or component
    local getOptions = component.GetOptions or feature.GetOptions
    if type(getOptions) ~= "function" then
        return nil
    end

    local ok, options = pcall(getOptions, feature)
    if ok then
        return options
    end

    print("|cffff0000YUI Component Error:|r " .. tostring(GetComponentName(component) or component.id) .. " - " .. tostring(options))
    return nil
end

RenderSettings = function(component, isRefresh)
    if not moduleTarget or not component then return end
    local feature = component.feature or component
    local cacheKey = feature.GetReusableSettingsKey and feature:GetReusableSettingsKey()
    if IsComponentIneffective(component) then cacheKey = nil end
    local page = SelectView(cacheKey and (component.id .. ":" .. cacheKey) or "transient", cacheKey ~= nil)
    currentSettingsComponent = component
    if not isRefresh then
        EnterSettings(component)
    end
    if not cacheKey then S:ClearConfig(renderTarget) end
    currentView = "settings"
    feature.RefreshCurrentModule = function()
        if currentView == "settings" then
            local target = renderTarget
            local picker = GUI2.ColorPicker
            if picker and picker:DeferRefresh(target, function()
                if renderTarget == target and currentView == "settings" and currentSettingsComponent == component then
                    RenderSettings(component, true)
                end
            end) then return end
            RenderSettings(component, true)
        end
    end
    component.RefreshCurrentModule = feature.RefreshCurrentModule

    if type(component.RenderSettings) == "function" then
        component:RenderSettings(renderTarget, {
            renderTitle = function(parent, x, y, width)
                return RenderSettingsTitle(parent, x, y, width, GetComponentName(component), RenderList)
            end,
        })
        RevealView()
        RefreshCurrentModuleScroll(not isRefresh)
        return
    end

    local config = {
        {
            type = "custom",
            render = function(parent, x, y, width)
                local titleAside = component.settingsTitleAside or feature.settingsTitleAside
                local action = feature.GetSettingsTitleAction and feature:GetSettingsTitleAction()
                return RenderSettingsTitle(parent, x, y, width, GetComponentName(component), RenderList, titleAside, action)
            end,
        },
        { type = "space", height = 5 },
    }

    local ineffective, state = IsComponentIneffective(component)
    if ineffective then
        if S.ClearRightPreview then
            S:ClearRightPreview()
        end
        if state.kind == "yield" then
            S:RenderConfig(renderTarget, {
                {
                    type = "text",
                    label = S:FormatYieldNotice(
                        state.featureKey or component.id,
                        state.controller,
                        state.featureLabel or GetComponentName(component)
                    ),
                    colorKey = "color.text.primary",
                },
            })
            RevealView()
            RefreshCurrentModuleScroll(not isRefresh)
            return
        end
        config[#config + 1] = {
            type = "text",
            label = state.reason or GetText("component.inactive", "该组件当前未生效。"),
            colorKey = (state.tone == "danger" or state.tone == "error") and "color.state.danger" or "color.state.warning",
        }
        S:RenderConfig(renderTarget, config)
        RevealView()
        RefreshCurrentModuleScroll(not isRefresh)
        return
    end

    local options = GetComponentOptions(component)
    if options then
        for _, opt in ipairs(options) do
            config[#config + 1] = opt
        end
    else
        config[#config + 1] = { type = "text", label = GetText("component.no_options", "该组件没有可配置选项。"), colorKey = "color.text.muted" }
    end

    if cacheKey and page.yuiSettingsBuilt then
        local ok, code = GUI2.Form:RefreshRetainedValues(page, config)
        if not ok then error("Reusable settings: " .. tostring(code)) end
    else
        S:RenderConfig(page, config)
        if cacheKey then page.yuiSettingsBuilt = true end
    end
    if cacheKey and feature.RefreshReusableSettings then feature:RefreshReusableSettings(page) end
    RevealView()
    RefreshCurrentModuleScroll(not isRefresh)
end

local function Render(parent)
    moduleTarget = parent
    if parent and parent.HookScript and not parent.yuiGeneralLifecycleHooked then
        parent.yuiGeneralLifecycleHooked = true
        parent:HookScript("OnHide", function()
            if currentView == "settings" then
                resetToListOnNextShow = true
            end
            LeaveActiveSettings()
            for _, page in pairs(parent.yuiToolboxViews or {}) do page:Hide() end
            if S.ClearRightPreview then
                S:ClearRightPreview()
            end
        end)
        parent:HookScript("OnShow", function()
            if resetToListOnNextShow then
                RenderList()
            elseif currentView == "settings" and currentSettingsComponent and not activeSettingsFeature then
                RenderSettings(currentSettingsComponent)
            else
                RenderList()
            end
        end)
    end
    RenderList()
end

function S:OpenComponentFeature(key, searchNavigation)
    local component = Components and Components:Get(key)
    if not component and YUI.Components and YUI.Components.features and YUI.Components.features[key] then
        component = { id = key, feature = YUI.Components.features[key], displayName = YUI.Components.features[key].name, GetOptions = YUI.Components.features[key].GetOptions }
    end
    if not component then return end

    -- Search already selected the toolbox; avoid an uncancellable delayed page switch.
    if searchNavigation then
        if not S:IsOpen() then return end
        if component.settingsMode == "external" then
            OpenComponentSettings(component)
        elseif component.RenderSettings or component.GetOptions or (component.feature and component.feature.GetOptions) then
            RenderSettings(component, currentView == "settings" and currentSettingsComponent == component)
        else
            RenderList()
        end
        return
    end

    C_Timer.After(0.05, function()
        SelectComponentModule()
        C_Timer.After(0.05, function()
            if component.settingsMode == "external" then
                OpenComponentSettings(component)
            elseif component.RenderSettings or component.GetOptions or (component.feature and component.feature.GetOptions) then
                RenderSettings(component)
            else
                RenderList()
            end
        end)
    end)
end

function S:OpenYBoxFeature(key)
    return S:OpenComponentFeature(key)
end

if YUI.Components then
    function YUI.Components:OpenFeatureSettings(key)
        S:OpenComponentFeature(key)
    end
end

MODULE_NAME = GetText("settings.modules.general", MODULE_NAME)

S:RegisterModule(MODULE_NAME, MODULE_ICON, Render, {
    id = PRODUCT_ID ~= "suite" and (PRODUCT_ID .. ".settings") or "suite.settings.general",
    product = PRODUCT_ID,
    scope = PRODUCT_ID,
    titleKey = "settings.modules.general",
    navTitleKey = "settings.nav.toolbox",
    navIconCrop = false,
    navIconSize = CelestialSeries and CelestialSeries.NAV_ICON_SIZE or 26,
    navToggle = {
        get = function()
            if YUI.Components and YUI.Components.IsToolboxEnabled then
                return YUI.Components:IsToolboxEnabled(PRODUCT_ID)
            end
            return true
        end,
        set = function(_, enabled)
            if YUI.Components and YUI.Components.SetToolboxEnabled then
                return YUI.Components:SetToolboxEnabled(enabled == true, PRODUCT_ID)
            end
            return false
        end,
    },
})

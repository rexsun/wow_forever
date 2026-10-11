local YUI = _G.YUI
local S = YUI.Settings
local GUI2 = YUI.GUI2
local LC = YUI.Locale:Get("Core")
local UnitAPI = YUI.API and YUI.API.Unit or YUI.WOW_API or {}
local TalentAPI = YUI.API and YUI.API.Talent or YUI.WOW_API or {}

local MODULE_NAME = "主题外观"
local MODULE_ICON = 134334
local activeTab = "skin"
local activePluginSkinTab = "elvui"
local Render

local SPEC_PREVIEW_COLUMNS = 3
local SPEC_PREVIEW_GAP = 10
local SPEC_PREVIEW_CELL_HEIGHT = 40
local SPEC_PREVIEW_ICON_SIZE = 26
local SPEC_PREVIEW_HEADER_HEIGHT = 32
local SPEC_PREVIEW_BOTTOM_PADDING = 12
local ICON_SELECTOR_HEIGHT = 32
local ICON_SELECTOR_TOP_GAP = 18
local ICON_TAB_SECTION_GAP = 16
local MODULE_PAGE_LAYOUT = S.ModulePageLayout
    or { insetX = 20, titleTop = 20 }
local PAGE_INSET = MODULE_PAGE_LAYOUT.insetX
local PAGE_TITLE_TOP = MODULE_PAGE_LAYOUT.titleTop
local PAGE_TABS_TOP = 46
local SECTION_HEADER_HEIGHT = 32
local SECTION_BOTTOM_PADDING = 12

local SKIN_SCOPE_OPTIONS = {
    {
        key = "elvUI",
        labelKey = "settings.appearance.skins.elvui",
        tooltipKey = "settings.appearance.skins.elvui.tooltip",
        default = false,
    },
    {
        key = "eqolUnitFrames",
        labelKey = "settings.appearance.skins.eqol",
        tooltipKey = "settings.appearance.skins.eqol.tooltip",
        default = false,
        retailOnly = true,
    },
    {
        key = "ndui",
        labelKey = "settings.appearance.skins.ndui",
        tooltipKey = "settings.appearance.skins.ndui.tooltip",
        default = false,
        retailOnly = true,
    },
}

local SKIN_EFFECT_OPTIONS = {
    {
        key = "shadow",
        labelKey = "settings.appearance.skins.shadow",
        tooltipKey = "settings.appearance.skins.shadow.tooltip",
        default = true,
    },
    {
        key = "noise",
        labelKey = "settings.appearance.skins.noise",
        tooltipKey = "settings.appearance.skins.noise.tooltip",
        default = true,
    },
    {
        key = "lightMode",
        labelKey = "settings.appearance.skins.light_mode",
        tooltipKey = "settings.appearance.skins.light_mode.tooltip",
        default = false,
    },
    {
        key = "eqolPowerBorder",
        labelKey = "settings.appearance.skins.eqol_power_border",
        tooltipKey = "settings.appearance.skins.eqol_power_border.tooltip",
        default = false,
        retailOnly = true,
    },
    {
        key = "nduiUnitFrameTextShadow",
        labelKey = "settings.appearance.skins.ndui_text_shadow",
        tooltipKey = "settings.appearance.skins.ndui_text_shadow.tooltip",
        default = true,
        retailOnly = true,
    },
}

local PLUGIN_SKIN_TABS = {
    {
        key = "elvui",
        labelKey = "settings.appearance.plugin_skins.tab.elvui",
        scopeOptions = { SKIN_SCOPE_OPTIONS[1] },
        effectOptions = { SKIN_EFFECT_OPTIONS[2], SKIN_EFFECT_OPTIONS[3] },
    },
    {
        key = "eqol",
        labelKey = "settings.appearance.plugin_skins.tab.eqol",
        scopeOptions = { SKIN_SCOPE_OPTIONS[2] },
        effectOptions = { SKIN_EFFECT_OPTIONS[3], SKIN_EFFECT_OPTIONS[4] },
        retailOnly = true,
    },
    {
        key = "ndui",
        labelKey = "settings.appearance.plugin_skins.tab.ndui",
        scopeOptions = { SKIN_SCOPE_OPTIONS[3] },
        effectOptions = { SKIN_EFFECT_OPTIONS[3], SKIN_EFFECT_OPTIONS[5] },
        retailOnly = true,
    },
}

local ARMOR_GROUPS = {
    { labelKey = "settings.appearance.armor.cloth", classes = { "MAGE", "PRIEST", "WARLOCK" } },
    { labelKey = "settings.appearance.armor.leather", classes = { "DEMONHUNTER", "MONK", "ROGUE", "DRUID" } },
    { labelKey = "settings.appearance.armor.mail", classes = { "EVOKER", "HUNTER", "SHAMAN" } },
    { labelKey = "settings.appearance.armor.plate", classes = { "DEATHKNIGHT", "PALADIN", "WARRIOR" } },
}

local function GetSelectedPresetId()
    if not GUI2 or not GUI2.Appearance then
        return "midnight"
    end

    local db = GUI2.Appearance.GetDB and GUI2.Appearance:GetDB() or nil
    local presetId = db and db.basePreset or GUI2.activePresetId or "midnight"
    return GUI2.ResolvePresetId and GUI2:ResolvePresetId(presetId) or presetId
end

local function ClearAndRender(parent)
    if S.ClearConfig then
        S:ClearConfig(parent)
    end
end

local function CreateFlatSection(parent, width, height, label)
    local section = GUI2:CreateFrame(parent, {
        width = width,
        height = height,
    })
    section.gui2FlatSection = true

    local title = GUI2:CreateText(section, label or "", "font.size.md", "color.text.heading")
    title:SetPoint("TOPLEFT", 0, -4)

    local divider = GUI2:CreateDivider(section, {
        width = width,
        height = 1,
    })
    divider:SetPoint("BOTTOMLEFT", section, "BOTTOMLEFT", 0, 0)
    section.gui2SectionDivider = divider

    if S.Search then S.Search:Bind({ label = label }, section) end
    return section
end

local function CreatePreview(parent, width)
    local panel = CreateFlatSection(parent, width, 174, LC["settings.appearance.preview_title"])

    local samplePanel = GUI2:CreatePanel(panel, {
        width = 176,
        height = 72,
        surface = "color.surface.panel",
        border = "color.border.default",
    })
    samplePanel:SetPoint("TOPLEFT", 14, -SECTION_HEADER_HEIGHT)
    GUI2:CreateText(samplePanel, LC["settings.appearance.preview_panel"], "font.size.md", "color.text.primary"):SetPoint("CENTER")

    local popupPanel = GUI2:CreatePanel(panel, {
        width = 176,
        height = 72,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    popupPanel:SetPoint("LEFT", samplePanel, "RIGHT", 14, 0)
    GUI2:CreateText(popupPanel, LC["settings.appearance.preview_popup"], "font.size.md", "color.text.accent"):SetPoint("CENTER")

    local tooltipPanel = GUI2:CreatePanel(panel, {
        width = width - 410,
        height = 72,
        surface = "color.surface.popup",
        border = "color.popup.border",
        nativeFrameBorder = true,
        nativeFrameBorderStyle = "tooltip",
        shadow = true,
    })
    tooltipPanel:SetPoint("LEFT", popupPanel, "RIGHT", 14, 0)

    -- Native tooltip borders render on a child frame above the panel fill.
    local tooltipContentLevel = tooltipPanel:GetFrameLevel() + 2
    if tooltipPanel.gui2NativeBorder and tooltipPanel.gui2NativeBorder.GetFrameLevel then
        tooltipContentLevel = tooltipPanel.gui2NativeBorder:GetFrameLevel() + 1
    elseif tooltipPanel.gui2NativeFallbackBorder and tooltipPanel.gui2NativeFallbackBorder.GetFrameLevel then
        tooltipContentLevel = tooltipPanel.gui2NativeFallbackBorder:GetFrameLevel() + 1
    end
    local tooltipContent = GUI2:CreateFrame(tooltipPanel, {
        allPoints = true,
        frameLevel = tooltipContentLevel,
    })
    GUI2:CreateText(tooltipContent, LC["settings.appearance.preview_tooltip"], "font.size.md", "color.text.primary"):SetPoint("CENTER")

    local normal = GUI2.Form:CreateButton(panel, {
        width = 132,
        text = LC["settings.appearance.preview_button"],
    })
    normal:SetPoint("TOPLEFT", samplePanel, "BOTTOMLEFT", 0, -18)

    local selected = GUI2.Form:CreateButton(panel, {
        width = 132,
        text = LC["settings.appearance.preview_selected"],
        state = "selected",
    })
    selected:SetPoint("LEFT", normal, "RIGHT", 12, 0)

    local accent = GUI2:CreateSwatch(panel, LC["settings.appearance.preview_accent"], "color.accent.primary", 156, 38)
    accent:SetPoint("LEFT", selected, "RIGHT", 18, 0)

    local border = GUI2:CreateSwatch(panel, LC["settings.appearance.preview_border"], "color.border.default", 156, 38)
    border:SetPoint("LEFT", accent, "RIGHT", 12, 0)

    return panel
end

local function CreateSettingsBackgroundSection(parent, anchor, width)
    local section = CreateFlatSection(
        parent,
        width,
        86,
        LC["settings.appearance.background_title"]
    )
    section:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)

    local Appearance = GUI2.Appearance
    local selector = GUI2.Form:CreateSegmentedControl(section, {
        width = 310,
        value = Appearance:GetSettingsBackgroundMode(),
        items = {
            {
                text = LC["settings.appearance.background.artwork"],
                value = "artwork",
            },
            {
                text = LC["settings.appearance.background.solid"],
                value = "solid",
            },
        },
        onChange = function(_, value)
            Appearance:SetSettingsBackgroundMode(value)
        end,
    })
    selector:SetPoint("TOPLEFT", section, "TOPLEFT", 14, -44)

    return section
end

local function RefreshPresetCard(card)
    if not card then return end

    local surface = card.gui2Disabled and "color.control.disabled" or (card.gui2Selected and "color.control.active" or "color.surface.panel")
    local border = card.gui2Disabled and "color.border.subtle" or (card.gui2Selected and "color.border.accent" or "color.border.default")
    local text = card.gui2Disabled and "color.text.disabled" or (card.gui2Selected and "color.text.accent" or "color.text.primary")
    local marker = card.gui2Disabled and "color.border.subtle" or (card.gui2Selected and "color.accent.primary" or "color.border.default")

    card.gui2Surface = surface
    GUI2:ApplyBackdrop(card, surface)
    GUI2:SetBorderColor(card, border)
    if card.title then
        GUI2:SetTextColorKey(card.title, text)
    end
    if card.marker then
        GUI2:SetTexturePaintKey(card.marker, marker)
    end
end

local function CreatePresetCard(parent, opts)
    opts = opts or {}

    local card = GUI2:CreateButtonFrame(parent, {
        width = opts.width,
        height = opts.height or 76,
        template = "BackdropTemplate",
        surface = "color.surface.panel",
        border = "color.border.default",
        shadow = true,
    })
    card.gui2Selected = opts.selected and true or false
    card.gui2Disabled = opts.disabled and true or false

    local title = GUI2:CreateText(card, opts.text or "", "font.size.md", "color.text.primary")
    title:SetPoint("CENTER", 0, 4)
    title:SetWidth((opts.width or 180) - 20)
    title:SetJustifyH("CENTER")
    title:SetWordWrap(false)
    card.title = title

    local marker = GUI2:CreateTexture(card, { layer = "ARTWORK" })
    marker:SetHeight(2)
    marker:SetPoint("BOTTOMLEFT", 12, 10)
    marker:SetPoint("BOTTOMRIGHT", -12, 10)
    card.marker = marker

    if card.gui2Disabled then
        card:EnableMouse(false)
    else
        card:SetScript("OnEnter", function(self)
            if self.gui2Selected then return end
            self.gui2Surface = "color.control.hover"
            GUI2:ApplyBackdrop(self, "color.control.hover")
            GUI2:SetBorderColor(self, "color.border.accent")
            if self.title then GUI2:SetTextColorKey(self.title, "color.text.accent") end
        end)
        card:SetScript("OnLeave", function(self)
            RefreshPresetCard(self)
        end)
        card:SetScript("OnClick", opts.onClick)
    end

    card.RefreshTheme = RefreshPresetCard
    GUI2:RegisterThemeObject(card)
    RefreshPresetCard(card)
    return card
end

local function GetIconSetDisplayName(set)
    if not set then return "" end
    if set.nameKey then
        local name = LC[set.nameKey]
        if type(name) == "string" and name ~= "" and name ~= set.nameKey then
            return name
        end
    end
    return set.name or set.id or ""
end

local function GetIconScopeDisplayName(scope)
    if not scope then return "" end
    if scope.nameKey then
        local name = LC[scope.nameKey]
        if type(name) == "string" and name ~= "" and name ~= scope.nameKey then
            return name
        end
    end
    return scope.name or scope.id or ""
end

local function GetIconScopeTooltip(scope)
    if not scope then return nil end
    if scope.tooltipKey then
        local tooltip = LC[scope.tooltipKey]
        if type(tooltip) == "string" and tooltip ~= "" and tooltip ~= scope.tooltipKey then
            return tooltip
        end
    end
    return scope.tooltip
end

local function GetPlayerClassToken()
    local _
    local classToken
    if UnitAPI.UnitClass then
        _, classToken = UnitAPI.UnitClass("player")
    elseif UnitClass then
        _, classToken = UnitClass("player")
    end
    return classToken or "UNKNOWN"
end

local function GetClassInfoMap()
    local map = {}
    local count = UnitAPI.GetNumClasses and UnitAPI.GetNumClasses() or GetNumClasses and GetNumClasses() or 0

    for index = 1, count do
        local info
        if UnitAPI.GetClassInfo then
            info = UnitAPI.GetClassInfo(index)
        elseif GetClassInfo then
            local className, classFile, classID = GetClassInfo(index)
            info = { className = className, classFile = classFile, classID = classID }
        end

        if type(info) == "table" and info.classFile then
            map[info.classFile] = {
                token = info.classFile,
                name = YUI.Locale and YUI.Locale.GetClassName
                    and YUI.Locale:GetClassName(info.classFile, info.className or info.classFile)
                    or info.className or info.classFile,
                classID = info.classID or info.id or index,
            }
        end
    end

    if not next(map) then
        local className, classToken, classID
        if UnitAPI.UnitClass then
            className, classToken, classID = UnitAPI.UnitClass("player")
        elseif UnitClass then
            className, classToken, classID = UnitClass("player")
        end
        if classToken then
            map[classToken] = {
                token = classToken,
                name = YUI.Locale and YUI.Locale.GetClassName
                    and YUI.Locale:GetClassName(classToken, className or classToken)
                    or className or classToken,
                classID = classID,
            }
        end
    end

    return map
end

local function GetNumSpecsForClass(classID)
    if C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID then
        return C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
    elseif GetNumSpecializationsForClassID then
        return GetNumSpecializationsForClassID(classID) or 0
    end
    return 0
end

local function GetSpecsForClass(classInfo)
    local specs = {}
    if classInfo and classInfo.classID and GetSpecializationInfoForClassID then
        local sex = UnitSex and UnitSex("player") or nil
        local count = GetNumSpecsForClass(classInfo.classID)
        for index = 1, count do
            local specID, specName, _, specIcon = GetSpecializationInfoForClassID(classInfo.classID, index, sex)
            if specID then
                specs[#specs + 1] = {
                    specID = specID,
                    name = YUI.Locale and YUI.Locale.GetSpecializationName
                        and YUI.Locale:GetSpecializationName(specID, specName or tostring(specID))
                        or specName or tostring(specID),
                    nativeIcon = specIcon,
                    classInfo = classInfo,
                }
            end
        end
    end

    if #specs == 0 and classInfo and classInfo.token == GetPlayerClassToken() then
        local count = TalentAPI.GetNumSpecializations and TalentAPI.GetNumSpecializations() or GetNumSpecializations and GetNumSpecializations() or 0
        for index = 1, count do
            local specID, specName, specIcon
            if TalentAPI.GetSpecializationInfo then
                specID, specName, _, specIcon = TalentAPI.GetSpecializationInfo(index)
            elseif GetSpecializationInfo then
                specID, specName, _, specIcon = GetSpecializationInfo(index)
            end
            specID = specID or index
            specs[#specs + 1] = {
                specID = specID,
                name = YUI.Locale and YUI.Locale.GetSpecializationName
                    and YUI.Locale:GetSpecializationName(specID, specName or tostring(specID))
                    or specName or tostring(specID),
                nativeIcon = specIcon,
                useNativeIcon = specIcon ~= nil,
                classInfo = classInfo,
            }
        end
    end

    return specs
end

local function GetSpecPreviewGroups()
    local classMap = GetClassInfoMap()
    local groups = {}
    for _, group in ipairs(ARMOR_GROUPS) do
        local result = {
            label = LC[group.labelKey],
            entries = {},
        }
        for _, token in ipairs(group.classes) do
            local classInfo = classMap[token]
            if classInfo then
                local specs = GetSpecsForClass(classInfo)
                for _, spec in ipairs(specs) do
                    result.entries[#result.entries + 1] = spec
                end
            end
        end
        if #result.entries > 0 then
            groups[#groups + 1] = result
        end
    end
    return groups
end

local function GetClassColor(classInfo)
    if not classInfo then return 1, 1, 1, 1 end
    local color = UnitAPI.GetClassColor and UnitAPI.GetClassColor(classInfo.token)
    if color then
        return color.r or 1, color.g or 1, color.b or 1, 1
    elseif RAID_CLASS_COLORS and RAID_CLASS_COLORS[classInfo.token] then
        color = RAID_CLASS_COLORS[classInfo.token]
        return color.r or 1, color.g or 1, color.b or 1, 1
    end
    return 1, 1, 1, 1
end

local function CreateTabs(parent, width)
    local items = {
        { text = LC["settings.appearance.tab.skin"], value = "skin" },
        { text = LC["settings.appearance.tab.icons"], value = "icons" },
    }
    if not YUI.IsForever then
        items[#items + 1] = { text = LC["settings.appearance.tab.plugin_skins"], value = "pluginSkins" }
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
        items = items,
        onChange = function(_, value)
            activeTab = value or "skin"
            ClearAndRender(parent)
            Render(parent)
        end,
    })
    tabs:SetPoint("TOPLEFT", PAGE_INSET, -PAGE_TABS_TOP)
    return tabs
end

local function GetSkinRuntime()
    return YUI.Appearance and YUI.Appearance.Skins or YUI.Skins
end

local function GetVisibleSkinOptions(options)
    local visibleOptions = {}
    for _, option in ipairs(options) do
        if not option.retailOnly or YUI.IsRetail then
            visibleOptions[#visibleOptions + 1] = option
        end
    end
    return visibleOptions
end

local function GetVisiblePluginSkinTabs()
    local visibleTabs = {}
    local activeIsVisible = false
    for _, tab in ipairs(PLUGIN_SKIN_TABS) do
        if not tab.retailOnly or YUI.IsRetail then
            visibleTabs[#visibleTabs + 1] = tab
            if tab.key == activePluginSkinTab then
                activeIsVisible = true
            end
        end
    end

    if not activeIsVisible and visibleTabs[1] then
        activePluginSkinTab = visibleTabs[1].key
    end

    return visibleTabs
end

local function GetPluginSkinTabConfig(key)
    for _, tab in ipairs(PLUGIN_SKIN_TABS) do
        if tab.key == key then
            return tab
        end
    end
end

local function CreateSkinOptionCheckbox(parent, option, width, Skins, labelKey)
    return GUI2.Form:CreateCheckbox(parent, {
        width = width,
        text = LC[labelKey or option.labelKey] or option.key,
        tooltip = option.tooltipKey and LC[option.tooltipKey] or nil,
        get = function()
            return Skins.GetOption(option.key, option.default) == true
        end,
        set = function(value)
            Skins.SetOption(option.key, value)
        end,
        onChange = function()
            if S.ShowReload then
                S:ShowReload()
            end
        end,
    })
end

local function RenderPluginSkinTabSelector(parent, anchor, width, tabs)
    local items = {}
    for _, tab in ipairs(tabs) do
        items[#items + 1] = {
            text = LC[tab.labelKey],
            value = tab.key,
        }
    end

    local selector = GUI2.Form:CreateSegmentedControl(parent, {
        width = math.min(width, math.max(190, #items * 190)),
        value = activePluginSkinTab,
        items = items,
        onChange = function(_, value)
            activePluginSkinTab = value or "elvui"
            ClearAndRender(parent)
            Render(parent)
        end,
    })
    selector:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -18)
    return selector
end

local function RenderPluginSkinOptionsPanel(parent, anchor, width, tabConfig)
    local Skins = GetSkinRuntime()
    if not Skins or not Skins.GetOption or not Skins.SetOption then
        return anchor, 0
    end

    local scopeOptions = GetVisibleSkinOptions(tabConfig.scopeOptions or {})
    local effectOptions = GetVisibleSkinOptions(tabConfig.effectOptions or {})
    if #scopeOptions == 0 and #effectOptions == 0 then
        return anchor, 0
    end

    local inset = 16
    local rowHeight = 34
    local enableOption = scopeOptions[1]
    local rows = {}
    if enableOption then
        rows[#rows + 1] = {
            option = enableOption,
            labelKey = "settings.appearance.plugin_skins.enable",
        }
    end
    for _, option in ipairs(effectOptions) do
        rows[#rows + 1] = { option = option }
    end
    local height = SECTION_HEADER_HEIGHT + (#rows * rowHeight) + SECTION_BOTTOM_PADDING

    local panel = CreateFlatSection(parent, width, height, LC["settings.appearance.tab.plugin_skins"])
    panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -18)

    for index, row in ipairs(rows) do
        local checkbox = CreateSkinOptionCheckbox(panel, row.option, width - (inset * 2), Skins, row.labelKey)
        checkbox:SetPoint("TOPLEFT", inset, -SECTION_HEADER_HEIGHT - ((index - 1) * rowHeight))
    end

    return panel, height
end

local function RenderPluginSkinTab(parent, tabs, width)
    local visibleTabs = GetVisiblePluginSkinTabs()
    if #visibleTabs == 0 then
        local warning = GUI2:CreateText(parent, LC["settings.appearance.plugin_skins_unavailable"], "font.size.md", "color.state.warning")
        warning:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -22)
        warning:SetWidth(width)
        warning:SetWordWrap(true)
        parent:SetHeight(180)
        return
    end

    local pluginTabs = RenderPluginSkinTabSelector(parent, tabs, width, visibleTabs)
    local tabConfig = GetPluginSkinTabConfig(activePluginSkinTab) or visibleTabs[1]
    local _, panelHeight = RenderPluginSkinOptionsPanel(parent, pluginTabs, width, tabConfig)
    parent:SetHeight(math.max(240, panelHeight + 116))
end

local function RenderSkinTab(parent, tabs, width)
    local selectedPresetId = GetSelectedPresetId()

    local presets = CreateFlatSection(parent, width, 122, LC["settings.appearance.preset_title"])
    presets:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -18)

    local cardCount = 5
    local cardGap = 10
    local cardInset = 14
    local cardWidth = math.floor((width - (cardInset * 2) - ((cardCount - 1) * cardGap)) / cardCount)
    if cardWidth < 112 then
        cardWidth = 112
    end

    local presetList = GUI2:GetPresets()
    for i, preset in ipairs(presetList) do
        local card = CreatePresetCard(presets, {
            width = cardWidth,
            text = GUI2:GetPresetDisplayName(preset),
            selected = preset.id == selectedPresetId,
            onClick = function()
                GUI2.Appearance:SetBasePreset(preset.id, true)
                ClearAndRender(parent)
                Render(parent)
            end,
        })
        card:SetPoint("TOPLEFT", cardInset + ((i - 1) * (cardWidth + cardGap)), -SECTION_HEADER_HEIGHT)
    end

    local placeholderCount = cardCount - #presetList
    for i = 1, placeholderCount do
        local slot = #presetList + i
        local comingSoon = CreatePresetCard(presets, {
            width = cardWidth,
            text = LC["settings.appearance.preset.coming_soon"],
            disabled = true,
        })
        comingSoon:SetPoint("TOPLEFT", cardInset + ((slot - 1) * (cardWidth + cardGap)), -SECTION_HEADER_HEIGHT)
    end

    local preview = CreatePreview(parent, width)
    preview:SetPoint("TOPLEFT", presets, "BOTTOMLEFT", 0, -16)
    CreateSettingsBackgroundSection(parent, preview, width)

    parent:SetHeight(548)
end

local function RenderSpecPreviewCell(parent, x, y, width, entry, Icons)
    local frame = GUI2:CreatePanel(parent, {
        width = width,
        height = SPEC_PREVIEW_CELL_HEIGHT,
        surface = "color.surface.panel",
        border = "color.border.subtle",
    })
    frame:SetPoint("TOPLEFT", x, y)

    local iconBg = GUI2:CreatePanel(frame, {
        width = SPEC_PREVIEW_ICON_SIZE,
        height = SPEC_PREVIEW_ICON_SIZE,
        surface = "color.control.bg",
        border = "color.border.subtle",
    })
    iconBg:SetPoint("LEFT", frame, "LEFT", 10, 0)

    local texture = iconBg:CreateTexture(nil, "ARTWORK")
    texture:SetPoint("TOPLEFT", 2, -2)
    texture:SetPoint("BOTTOMRIGHT", -2, 2)
    local icon
    if entry.useNativeIcon and entry.nativeIcon and Icons and Icons.GetSpecIconByNativeTexture then
        icon = Icons.GetSpecIconByNativeTexture(entry.nativeIcon)
    elseif Icons and Icons.GetSpecIcon then
        icon = Icons.GetSpecIcon(entry.specID)
    end
    if icon and Icons.ApplyIcon then
        Icons.ApplyIcon(texture, icon)
        if icon.kind == "spec" and icon.custom ~= true and not icon.atlas and Icons.GetNativeSpecTexCoord then
            texture:SetTexCoord(unpack(Icons.GetNativeSpecTexCoord()))
        end
    else
        texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        texture:SetTexCoord(0, 1, 0, 1)
    end

    local label = GUI2:CreateText(frame, (entry.classInfo.name or entry.classInfo.token or "") .. " · " .. (entry.name or ""), "font.size.md", "color.text.primary")
    label:SetPoint("LEFT", iconBg, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetTextColor(GetClassColor(entry.classInfo))

    return frame
end

local function RenderSpecPreviewGroup(parent, group, y, width, Icons)
    local title = GUI2:CreateText(parent, group.label or "", "font.size.md", "color.text.accent")
    title:SetPoint("TOPLEFT", 14, y)

    local gridWidth = width - 28
    local cellWidth = math.floor((gridWidth - ((SPEC_PREVIEW_COLUMNS - 1) * SPEC_PREVIEW_GAP)) / SPEC_PREVIEW_COLUMNS)
    local startY = y - 26

    for index, entry in ipairs(group.entries) do
        local row = math.floor((index - 1) / SPEC_PREVIEW_COLUMNS)
        local col = (index - 1) % SPEC_PREVIEW_COLUMNS
        RenderSpecPreviewCell(
            parent,
            14 + (col * (cellWidth + SPEC_PREVIEW_GAP)),
            startY - (row * (SPEC_PREVIEW_CELL_HEIGHT + SPEC_PREVIEW_GAP)),
            cellWidth,
            entry,
            Icons
        )
    end

    local rows = math.ceil(#group.entries / SPEC_PREVIEW_COLUMNS)
    return 26 + (rows * SPEC_PREVIEW_CELL_HEIGHT) + ((rows - 1) * SPEC_PREVIEW_GAP)
end

local function GetSpecPreviewContentHeight(groups)
    if not groups or #groups == 0 then
        return 60
    end

    local height = 0
    for index, group in ipairs(groups) do
        local rows = math.ceil(#group.entries / SPEC_PREVIEW_COLUMNS)
        height = height + 26 + (rows * SPEC_PREVIEW_CELL_HEIGHT) + ((rows - 1) * SPEC_PREVIEW_GAP)
        if index < #groups then
            height = height + 14
        end
    end
    return height
end

local function RenderSpecPreview(parent, anchor, width, Icons)
    local groups = GetSpecPreviewGroups()
    local previewHeight = SPEC_PREVIEW_HEADER_HEIGHT + GetSpecPreviewContentHeight(groups) + SPEC_PREVIEW_BOTTOM_PADDING
    local panel = CreateFlatSection(parent, width, previewHeight, LC["settings.appearance.preview_all_specs"])
    panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -ICON_TAB_SECTION_GAP)

    if #groups == 0 then
        local empty = GUI2:CreateText(panel, LC["settings.appearance.icons_empty"], "font.size.md", "color.text.secondary")
        empty:SetPoint("TOPLEFT", 14, -SPEC_PREVIEW_HEADER_HEIGHT)
        empty:SetWidth(width - 28)
        empty:SetWordWrap(true)
        return panel, previewHeight
    end

    local y = -SPEC_PREVIEW_HEADER_HEIGHT
    for index, group in ipairs(groups) do
        local used = RenderSpecPreviewGroup(panel, group, y, width, Icons)
        y = y - used
        if index < #groups then
            y = y - 14
        end
    end

    return panel, previewHeight
end

local function RenderIconScopePanel(parent, anchor, width, Icons)
    if not Icons or not Icons.GetIconScopes then
        return anchor, 0
    end

    local scopes = Icons.GetIconScopes()
    if #scopes == 0 then
        return anchor, 0
    end

    local panel = CreateFlatSection(parent, width, 94, LC["settings.appearance.scope_title"])
    panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -ICON_TAB_SECTION_GAP)

    local columns = 3
    local gap = 14
    local inset = 14
    local controlWidth = math.floor((width - (inset * 2) - ((columns - 1) * gap)) / columns)
    if controlWidth < 160 then controlWidth = 160 end

    for index, scope in ipairs(scopes) do
        local scopeID = scope.id
        local scopeName = GetIconScopeDisplayName(scope)
        local scopeTooltip = GetIconScopeTooltip(scope)
        local row = math.floor((index - 1) / columns)
        local col = (index - 1) % columns
        local checkbox = GUI2.Form:CreateCheckbox(panel, {
            width = controlWidth,
            text = scopeName,
            tooltip = scopeTooltip,
            get = function()
                if Icons.IsIconScopeEnabled then
                    return Icons.IsIconScopeEnabled(scopeID)
                end
                return true
            end,
            set = function(value)
                if Icons.SetIconScopeEnabled then
                    Icons.SetIconScopeEnabled(scopeID, value)
                end
            end,
        })
        checkbox:SetPoint("TOPLEFT", inset + (col * (controlWidth + gap)), -SECTION_HEADER_HEIGHT - (row * 34))
    end

    local rows = math.ceil(#scopes / columns)
    local height = SECTION_HEADER_HEIGHT + (rows * 34) + SECTION_BOTTOM_PADDING
    panel:SetHeight(height)
    return panel, height
end

local function RenderIconTab(parent, tabs, width)
    local Icons = YUI.API and YUI.API.Icons
    if not Icons or not Icons.GetIconSets then
        local warning = GUI2:CreateText(parent, LC["settings.appearance.icons_unavailable"], "font.size.md", "color.state.warning")
        warning:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -22)
        warning:SetWidth(width)
        warning:SetWordWrap(true)
        parent:SetHeight(180)
        return
    end

    local iconSets = Icons.GetIconSets()
    local selectedId = Icons.GetActiveIconSetID and Icons.GetActiveIconSetID() or "blizzard"

    local selector = GUI2:CreateFrame(parent, {
        width = width,
        height = ICON_SELECTOR_HEIGHT,
    })
    selector:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -ICON_SELECTOR_TOP_GAP)

    local label = GUI2:CreateText(selector, LC["settings.appearance.icons_select_label"], "font.size.lg", "color.text.heading")
    label:SetPoint("LEFT", selector, "LEFT", 14, 0)
    label:SetWidth(110)
    label:SetJustifyH("LEFT")

    local options = {}
    for _, set in ipairs(iconSets) do
        options[#options + 1] = {
            text = GetIconSetDisplayName(set),
            value = set.id,
        }
    end

    local dropdown = GUI2.Form:CreateDropdown(selector, {
        width = 260,
        options = options,
        get = function()
            return Icons.GetActiveIconSetID and Icons.GetActiveIconSetID() or selectedId
        end,
        set = function(value)
            if Icons.SetActiveIconSetID then
                Icons.SetActiveIconSetID(value)
            end
        end,
        onChange = function()
            ClearAndRender(parent)
            Render(parent)
        end,
    })
    dropdown:SetPoint("LEFT", label, "RIGHT", 10, 0)

    local scopePanel, scopeHeight = RenderIconScopePanel(parent, selector, width, Icons)
    local _, previewHeight = RenderSpecPreview(parent, scopePanel, width, Icons)
    parent:SetHeight(math.max(300, ICON_SELECTOR_HEIGHT + scopeHeight + previewHeight + 146))
end

Render = function(parent)
    if not GUI2 or not GUI2.Appearance or not GUI2.Form or not GUI2.Form.CreateUnderlineTabs then
        S:RenderConfig(parent, {
            { type = "header", label = LC["settings.appearance.title"] },
            { type = "text", label = LC["settings.appearance.unavailable"], colorKey = "color.state.warning" },
        })
        return
    end

    local width = parent:GetWidth()
    if not width or width < 620 then
        width = 700
    else
        width = width - 40
    end

    local title = GUI2:CreateText(parent, LC["settings.appearance.title"], "font.size.title", "color.text.heading")
    title:SetPoint("TOPLEFT", PAGE_INSET, -PAGE_TITLE_TOP)

    local tabs = CreateTabs(parent, width)
    if S.Search and S.Search.pending then S.Search:Bind({ label = LC["settings.appearance.tab." .. (activeTab == "pluginSkins" and "plugin_skins" or activeTab)] }, tabs) end
    if activeTab == "icons" then
        RenderIconTab(parent, tabs, width)
    elseif activeTab == "pluginSkins" then
        RenderPluginSkinTab(parent, tabs, width)
    else
        RenderSkinTab(parent, tabs, width)
    end

    if S.RefreshCurrentModuleScroll then
        S:RefreshCurrentModuleScroll(false)
    end
end

S:RegisterModule(MODULE_NAME, MODULE_ICON, Render, {
    id = "settings.appearance",
    product = "suite",
    scope = "core",
    titleKey = "settings.modules.appearance",
})

if S.Search then
    S.Search:RegisterRoute("settings.appearance", function(tab)
        if tab == "skin" or tab == "icons" or (tab == "pluginSkins" and not YUI.IsForever) then activeTab = tab end
    end)
end

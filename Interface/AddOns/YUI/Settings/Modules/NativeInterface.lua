local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not (YUI and YUI.Settings) then return end

local PRODUCT_ID = YUI.GetAddonProductId
    and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or (YUI.CoreMode == "suite" and "suite" or YUI.ProductId or "suite")
local IS_SUITE = PRODUCT_ID == "suite" and YUI.CoreMode == "suite"
local IS_ORBIT = PRODUCT_ID == "ybar" and YUI.IsRetail == true
if YUI.IsMists == true or not (IS_SUITE or IS_ORBIT) then return end

local S = YUI.Settings
local GUI = YUI.GUI2
local L = YUI.Locale and YUI.Locale:Get("NativeInterface") or {}
local SETTINGS_MODULE_ID = IS_SUITE and "suite.settings.native_interface" or "ybar.settings.native_interface"
local settingsLayout = {}
local activeSection

local function GetNative()
    return YUI.NativeInterface
end

local function T(key, fallback)
    return L[key] or fallback or key
end

local function Checkbox(key, textKey, tooltipKey)
    return {
        type = "checkbox",
        text = T(textKey),
        searchKey = textKey,
        tooltip = tooltipKey and T(tooltipKey) or nil,
        width = 280,
        get = function()
            local native = GetNative()
            return native and native:GetConfig()[key] == true or false
        end,
        set = function(value)
            local native = GetNative()
            if native then native:SetOption(key, value) end
        end,
    }
end

local function WidgetOption(key, textKey, tooltipKey, availability)
    if availability == nil then
        local native = GetNative()
        availability = native and native.GetSettingsAvailability and native:GetSettingsAvailability(key) or nil
    end
    if availability and availability.controller and S.FormatYieldNotice then
        return {
            type = "text",
            label = S:FormatYieldNotice("native_interface", availability.controller),
            colorKey = "color.text.primary",
            width = 280,
        }
    end
    local option = Checkbox(key, textKey, tooltipKey)
    option.disabled = availability and availability.disabled == true or false
    if availability and availability.tooltip then option.tooltip = availability.tooltip end
    return option
end

local function AddWindowSettings(config, native)
    if not (native and native.GetWindowMovementConfig) then return end
    local function Refresh()
        if S.RefreshSelectedModule then S:RefreshSelectedModule() end
    end
    local function Option(key, kind, label, options)
        return {
            type = kind, text = T(label), label = kind == "dropdown" and T(label) or nil,
            searchKey = label, options = options,
            get = function() return native:GetWindowMovementConfig()[key] end,
            set = function(value) native:SetWindowMovementOption(key, value); Refresh() end,
        }
    end
    local modes = {
        { text = T("windows.memory.session"), value = "session" },
        { text = T("windows.memory.permanent"), value = "permanent" },
    }
    config[#config + 1] = { type = "divider", label = T("windows.title"), width = 620, alignLeft = true }
    config[#config + 1] = Option("enabled", "checkbox", "windows.enabled")
    if not native:GetWindowMovementConfig().enabled then return end
    local fields = {
        Option("positionMode", "dropdown", "windows.position_memory", {
            { text = T("windows.memory.off"), value = "off" }, modes[1], modes[2],
        }),
        Option("scaleMode", "dropdown", "windows.scale_memory", modes),
        Option("requireShift", "checkbox", "windows.require_shift"),
    }
    local reset = { type = "button", label = T("windows.reset_all"), searchKey = "windows.reset_all",
        onClick = function() native:ResetAllWindowMovement(); Refresh() end }
    config[#config + 1] = {
        type = "custom",
        retainedFields = { fields[1], fields[2], fields[3], reset },
        render = function(parent, x, y, width)
            local controlWidth = math.min(150, math.floor(width * 0.55))
            local controlHeight = GUI:GetMetric("layout.form.rowHeight", 32)
            local gap = GUI:GetMetric("layout.form.rowGap", 10)
            for index = 1, 2 do
                fields[index].layoutPreset = "inlineSelector"
                fields[index].controlWidth = controlWidth
                fields[index].height = controlHeight
            end
            local _, formWidth, formHeight = S:RenderAlignedFields(parent, {
                x = x, y = y, width = width, columns = 1, labelPosition = "top", fields = fields,
            })
            local button = GUI.Form:CreateButton(parent, {
                text = reset.label, width = controlWidth, height = controlHeight, onClick = reset.onClick,
            })
            button:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + formWidth, y - formHeight - gap)
            if S.Search then S.Search:Bind(reset, button) end
            return formWidth, formHeight + gap + controlHeight
        end,
    }
end

local function BuildVisibilityOptions(native)
    local bagControl = Checkbox("manageBagsBar", "bags.enabled", "bags.enabled.tooltip")
    bagControl.set = function(value)
        local native = GetNative()
        if native then native:SetOption("manageBagsBar", value) end
        if S.RefreshSelectedModule then S:RefreshSelectedModule() end
    end
    local bagsEnabled = native and native:GetConfig().manageBagsBar == true or false
    local trackingBars = Checkbox("hideStatusTrackingBars", "hide.status_tracking_bars")
    local microMenu = Checkbox("hideMicroMenu", "hide.micro_menu")
    local bagMode = {
        type = "dropdown", label = T("bags.visibility"), searchKey = "bags.visibility", width = 280,
        disabled = not bagsEnabled,
        inlineLabel = true, labelWidth = 100, tooltip = T("bags.visibility.tooltip"),
        options = {
            { text = T("bags.visibility.auto"), value = "auto" },
            { text = T("bags.visibility.hide"), value = "hide" },
            { text = T("bags.visibility.show"), value = "show" },
        },
        get = function() local native = GetNative(); return native and native:GetConfig().bagsBarVisibility or "auto" end,
        set = function(value) local native = GetNative(); if native then native:SetOption("bagsBarVisibility", value) end end,
    }

    if IS_ORBIT or not (YUI.IsForever or YUI.IsRetail) then
        return {
            { type = "row", gap = 16, children = { trackingBars, microMenu } },
            { type = "row", gap = 16, children = { bagControl, bagMode } },
        }
    end
    local config = { trackingBars, microMenu }
    if YUI.IsForever == true then
        config[#config + 1] = Checkbox("hideRaidManager", "hide.raid_manager", "hide.raid_manager.tooltip")
    end
    config[#config + 1] = bagControl
    config[#config + 1] = bagMode
    return config
end

local function BuildRetailLayoutOptions(native)
    local topAvailability = native and native.GetSettingsAvailability
        and native:GetSettingsAvailability("manageTopCenterWidget") or nil
    local powerAvailability = native and native.GetSettingsAvailability
        and native:GetSettingsAvailability("managePowerBarWidget") or nil
    if topAvailability and powerAvailability and topAvailability.controller
        and topAvailability.controller == powerAvailability.controller and S.FormatYieldNotice then
        return {
            {
                type = "text",
                label = S:FormatYieldNotice("native_interface", topAvailability.controller),
                colorKey = "color.text.primary",
                width = 576,
            },
        }
    end
    local options = {
        WidgetOption("manageTopCenterWidget", "manage.top_center_widget", "manage.top_center_widget.tooltip", topAvailability),
        WidgetOption("managePowerBarWidget", "manage.power_bar_widget", "manage.power_bar_widget.tooltip", powerAvailability),
    }
    if IS_ORBIT then return { { type = "row", gap = 16, children = options } } end
    return options
end

local function AddOptions(config, options)
    for _, option in ipairs(options) do config[#config + 1] = option end
end

local function RefreshingCheckbox(key, label, tooltip)
    local field = Checkbox(key, label, tooltip)
    field.onChange = function()
        if S.RefreshSelectedModule then S:RefreshSelectedModule() end
    end
    return field
end

local function EnhancementNote(text)
    return {
        type = "custom",
        render = function(parent, x, y, width)
            local panel = parent.nativeEnhancementNote
            if not panel then
                panel = GUI:CreatePanel(parent, { surface = "color.surface.sunken", border = "color.border.subtle" })
                panel.title = GUI:CreateText(panel, T("enhancement.notes"), "font.size.sm", "color.text.primary", "LEFT")
                panel.body = GUI:CreateText(panel, "", "font.size.md", "color.text.secondary", "LEFT")
                panel.title:SetPoint("TOPLEFT", 12, -10)
                panel.body:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
                panel.body:SetWordWrap(true)
                panel.body:SetNonSpaceWrap(true)
                parent.nativeEnhancementNote = panel
            end
            panel:SetParent(parent)
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", x, y)
            panel:SetWidth(width)
            panel.body:SetWidth(math.max(1, width - 24))
            panel.body:SetText(text)
            panel:Show()
            local height = math.ceil(panel.title:GetStringHeight() + panel.body:GetStringHeight()) + 24
            panel:SetHeight(height)
            return width, height, panel
        end,
    }
end

local function EnhancementOptions(master, settingsLabel, fields, help, controlled)
    local enabled = master.get() and not controlled
    local options = {
        master,
        { type = "divider", label = T(settingsLabel), alignLeft = true, width = 620 },
    }
    for _, field in ipairs(fields) do
        field.disabled = not enabled or field.disabled
        options[#options + 1] = field
    end
    options[#options + 1] = EnhancementNote(help)
    return options
end

local function Render(parent)
    local native = GetNative()
    local visibility = BuildVisibilityOptions(native)
    local config = { { type = "header", label = T("name", "暴雪界面") } }
    if IS_ORBIT or not (YUI.IsForever or YUI.IsRetail) then
        local visibilityKey = IS_ORBIT and "section.visibility" or "section.element_visibility"
        config[#config + 1] = { type = "divider", label = T(visibilityKey), searchKey = visibilityKey, width = 620, alignLeft = true }
        AddOptions(config, visibility)
        if IS_ORBIT then
            config[#config + 1] = { type = "divider", label = T("section.layout"), width = 620, alignLeft = true }
            AddOptions(config, BuildRetailLayoutOptions(native))
            config[#config + 1] = { type = "divider", label = T("section.enhancements"), width = 620, alignLeft = true }
            config[#config + 1] = { type = "row", gap = 16, children = {
                Checkbox("hideBuffCollapseButton", "hide.buff_collapse", "hide.buff_collapse.tooltip"),
                Checkbox("suppressSupertrackTutorial", "tutorial.supertrack", "tutorial.supertrack.tooltip"),
            } }
        end
        S:RenderConfig(parent, config)
        return
    end

    local sections = {}
    local function Section(id, labelKey, group, options)
        local label = T(labelKey)
        table.insert(options, 1, { type = "header", label = label, searchKey = labelKey })
        sections[#sections + 1] = { id = id, label = label, group = T(group), options = options }
    end
    if YUI.IsForever == true then
        local function Controller(window)
            return native and native.GetWindowEnhancementController and native:GetWindowEnhancementController(window)
        end
        local friendsOwner, characterOwner, inspectOwner = Controller("friends"), Controller("character"), Controller("inspect")
        local friendsHelp = friendsOwner and T("social.skin_active"):format(friendsOwner) or T("social.notes")
        local characterHelp = {}
        if characterOwner then characterHelp[#characterHelp + 1] = T("character.skin_active"):format(characterOwner) end
        if inspectOwner then characterHelp[#characterHelp + 1] = T("character.inspect_skin_active"):format(inspectOwner) end
        if not characterOwner and not inspectOwner then characterHelp[1] = T("character.bottom_tabs.help") end
        local compact = RefreshingCheckbox("socialListCompact", "social.compact", "social.compact.help")
        Section("friends", "section.friends", "section.enhancements", EnhancementOptions(
            RefreshingCheckbox("friendsEnhancementEnabled", "social.enabled", "enhancement.enabled.help"), "social.list_settings", {
            compact,
            { type = "slider", label = T("social.font_size"), searchKey = "social.font_size",
                min = 11, max = 18, step = 1, default = 14, width = 200, instantUpdate = true,
                disabled = not compact.get(),
                get = function() return native and native:GetConfig().socialFontSize or 14 end,
                set = function(size) if native then native:SetOption("socialFontSize", size) end end },
            Checkbox("currentGameFirst", "social.current_game_first", "social.current_game_first.help"),
        }, friendsHelp, friendsOwner))
        Section("character", "section.character", "section.enhancements", EnhancementOptions(
            RefreshingCheckbox("characterEnhancementEnabled", "character.enabled", "enhancement.enabled.help"), "character.navigation", {
            Checkbox("characterBottomTabs", "character.bottom_tabs", "character.bottom_tabs.tooltip"),
        }, table.concat(characterHelp, "\n"), characterOwner and inspectOwner))
    else
        visibility[#visibility + 1] = Checkbox("hideBuffCollapseButton", "hide.buff_collapse", "hide.buff_collapse.tooltip")
    end
    Section("visibility", "section.element_visibility", "section.general", visibility)
    if YUI.IsForever == true then
        local layout = {}
        AddWindowSettings(layout, native)
        layout[#layout + 1] = { type = "divider", label = T("section.system_messages"), width = 620, alignLeft = true }
        layout[#layout + 1] = Checkbox("manageErrorMessages", "manage.error_messages", "manage.error_messages.tooltip")
        Section("layout", "section.window_layout", "section.general", layout)
        Section("quests", "section.quest_help", "section.general", {
            Checkbox("questLootSparkles", "quest.sparkles", "quest.sparkles.tooltip"),
        })
        Section("beta", "section.beta", "section.general", {
            Checkbox("compactBetaReporter", "beta.compact_reporter", "beta.compact_reporter.tooltip"),
        })
    else
        Section("layout", "section.window_layout", "section.general", BuildRetailLayoutOptions(native))
        Section("quests", "section.quest_help", "section.general", {
            Checkbox("suppressSupertrackTutorial", "tutorial.supertrack", "tutorial.supertrack.tooltip"),
        })
    end
    AddOptions(config, GUI:BuildFeatureSettingsLayout(settingsLayout, {
        sections = sections, selected = activeSection,
        compactNavigation = true, detailTopInset = 10,
        onSelect = function(id) activeSection = id end,
    }))
    S:RenderConfig(parent, config)
end

S:RegisterModule(IS_SUITE and T("name", "暴雪界面") or "Blizzard UI", "Interface\\Icons\\INV_Misc_Gear_01", Render, {
    id = SETTINGS_MODULE_ID,
    product = PRODUCT_ID,
    scope = PRODUCT_ID,
    titleKey = "name",
    titleNamespace = "NativeInterface",
    navTitleKey = "name",
    navTitleNamespace = "NativeInterface",
    suiteOnly = IS_SUITE,
})

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
local L = YUI.Locale and YUI.Locale:Get("NativeInterface") or {}
local SETTINGS_MODULE_ID = IS_SUITE and "suite.settings.native_interface" or "ybar.settings.native_interface"

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

local function AddWindowSettings(config)
    local native = GetNative()
    if not (native and native.GetWindowMovementConfig) then return end
    local function Refresh()
        if S.RefreshSelectedModule then S:RefreshSelectedModule() end
    end
    local function Option(key, kind, label, options)
        return {
            type = kind, text = T(label), label = T(label), width = 280, options = options,
            inlineLabel = kind == "dropdown", labelWidth = 80,
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
    config[#config + 1] = { type = "row", gap = 16, children = {
        Option("positionMode", "dropdown", "windows.position_memory", {
            { text = T("windows.memory.off"), value = "off" }, modes[1], modes[2],
        }),
        Option("scaleMode", "dropdown", "windows.scale_memory", modes),
    } }
    config[#config + 1] = { type = "row", gap = 16, children = {
        Option("requireShift", "checkbox", "windows.require_shift"),
        { type = "button", label = T("windows.reset_all"), width = 280,
            onClick = function() native:ResetAllWindowMovement(); Refresh() end },
    } }
end

local function Render(parent)
    local config = {
        { type = "header", label = T("name", "暴雪界面") },
        { type = "divider", label = T("section.visibility"), width = 620, alignLeft = true },
        {
            type = "row", gap = 16,
            children = {
                Checkbox("hideStatusTrackingBars", "hide.status_tracking_bars"),
                Checkbox("hideMicroMenu", "hide.micro_menu"),
            },
        },
        {
            type = "row", gap = 16,
            children = { {
                type = "dropdown", label = T("bags.visibility"), width = 280,
                inlineLabel = true, labelWidth = 100, tooltip = T("bags.visibility.tooltip"),
                options = {
                    { text = T("bags.visibility.auto"), value = "auto" },
                    { text = T("bags.visibility.hide"), value = "hide" },
                    { text = T("bags.visibility.show"), value = "show" },
                },
                get = function() local native = GetNative(); return native and native:GetConfig().bagsBarVisibility or "auto" end,
                set = function(value) local native = GetNative(); if native then native:SetOption("bagsBarVisibility", value) end end,
            } },
        },
    }

    if YUI.IsRetail == true then
        local native = GetNative()
        local topAvailability = native and native.GetSettingsAvailability
            and native:GetSettingsAvailability("manageTopCenterWidget") or nil
        local powerAvailability = native and native.GetSettingsAvailability
            and native:GetSettingsAvailability("managePowerBarWidget") or nil
        local layoutChildren
        if topAvailability and powerAvailability
            and topAvailability.controller
            and topAvailability.controller == powerAvailability.controller
            and S.FormatYieldNotice
        then
            layoutChildren = {
                {
                    type = "text",
                    label = S:FormatYieldNotice("native_interface", topAvailability.controller),
                    colorKey = "color.text.primary",
                    width = 576,
                },
            }
        else
            layoutChildren = {
                WidgetOption("manageTopCenterWidget", "manage.top_center_widget", "manage.top_center_widget.tooltip", topAvailability),
                WidgetOption("managePowerBarWidget", "manage.power_bar_widget", "manage.power_bar_widget.tooltip", powerAvailability),
            }
        end
        config[#config + 1] = { type = "divider", label = T("section.layout"), width = 620, alignLeft = true }
        config[#config + 1] = {
            type = "row", gap = 16,
            children = layoutChildren,
        }
        config[#config + 1] = { type = "divider", label = T("section.enhancements"), width = 620, alignLeft = true }
        config[#config + 1] = {
            type = "row", gap = 16,
            children = {
                Checkbox("hideBuffCollapseButton", "hide.buff_collapse", "hide.buff_collapse.tooltip"),
                Checkbox("suppressSupertrackTutorial", "tutorial.supertrack", "tutorial.supertrack.tooltip"),
            },
        }
    end

    if YUI.IsForever == true then
        AddWindowSettings(config)
        config[#config + 1] = { type = "divider", label = T("section.beta"), width = 620, alignLeft = true }
        config[#config + 1] = Checkbox("compactBetaReporter", "beta.compact_reporter", "beta.compact_reporter.tooltip")
        config[#config + 1] = Checkbox("fixBagSortButton", "beta.fix_bag_sort", "beta.fix_bag_sort.tooltip")
    end

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

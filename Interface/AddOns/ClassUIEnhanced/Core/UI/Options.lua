
--[[
    Option panel parts are inside the folder Options
--]]

local _
---@type string, private
local addonName, private = ...

---@type detailsframework
local framework = _G["DetailsFramework"]

local L = private.L
local LibSharedMedia = LibStub("LibSharedMedia-3.0")
local orangeFontTemplate = framework:GetTemplate("font", private.UIDefaults.presets.fontHeader)

---@class private : table
---@field Options options

---@class options : table
---@field IsOptionsPanelOpen fun(): boolean
---@field OpenOptionsPanel fun(tabIndex: number?, componentName: string?)
---@field CloseOptionsPanel fun()
---@field ToggleOptionsPanel fun()
---@field GetOptionsPanelFrame fun(): frame
---@field CreateOptionsFrame fun(): frame
---@field TRACKERS_TAB_INDEX number
---@field TRACKING_TAB_INDEX number
---@field GetSpellColor fun(settings: table|nil, spellID: number): number[]|nil
---@field SetSpellColor fun(settings: table, spellID: number, r: number, g: number, b: number, a: number|nil)
---@field ClearSpellColor fun(settings: table, spellID: number)
---@field GetSpellBorder fun(settings: table|nil, spellID: number): number[]|nil
---@field SetSpellBorder fun(settings: table, spellID: number, r: number, g: number, b: number, a: number|nil)
---@field ClearSpellBorder fun(settings: table, spellID: number)
---@field GetMissingGlow fun(settings: table|nil, spellID: number): number[]|nil
---@field SetMissingGlow fun(settings: table, spellID: number, r: number, g: number, b: number, a: number|nil)
---@field ClearMissingGlow fun(settings: table, spellID: number)
---@field IsExcluded fun(settings: table|nil, listKey: string, spellID: number): boolean
---@field SetExcluded fun(settings: table, listKey: string, spellID: number, excluded: boolean)
---@field GetAuraUnit fun(settings: table|nil, spellID: number): "both"|"player"|"target"
---@field SetAuraUnit fun(settings: table, spellID: number, unit: "both"|"player"|"target")

---@type options
---@diagnostic disable-next-line: missing-fields
local options = {}
private.Options = options
options.TRACKERS_TAB_INDEX = 2
options.TRACKING_TAB_INDEX = 4

local frameName = "CUE_OptionsPanel"
local optionsFrame

---Assigned inside CreateOptionsFrame; used by OpenOptionsPanel to switch tabs.
---@type fun(index: number)?
local selectTabFn

---Assigned inside buildTrackersTab; used by OpenOptionsPanel to select a tracker.
---@type fun(componentName: string)?
local selectTrackerComponentFn

---Assigned inside buildTrackersTab; used by layout widgets to refresh sibling dropdowns.
---@type table?
local trackersLeftCol
---@type table?
local trackersRightCol

---All column frames that received BuildMenu / SetAsOptionsPanel.
---Populated by build*Tab functions; refreshed after profile import.
---@type frame[]
local optionsPanelColumns = {}

---Refresh all BuildMenu option panels so widgets re-read profile values.
local function refreshBuildMenuColumns()
    for _, col in ipairs(optionsPanelColumns) do
        if col.RefreshOptions then col:RefreshOptions() end
    end
end

private.Options.RefreshAll = refreshBuildMenuColumns

local DROPDOWN_MAX_MENU_HEIGHT = 200

---Clear stale lockdown from pooled switch widgets after BuildMenuVolatile.
---DF's onWidgetSetInUse fails to clear switch lockdown because it checks
---the Blizzard Button's IsEnabled() (always true) instead of the DF
---lockdown flag.  This leaves switches locked from a prior panel build.
---After clearing, RefreshOptions re-applies children_follow_enabled state.
---@param col frame
local function resetSwitchPool(col)
    if not col.widget_list_by_type or not col.widget_list_by_type.switch then return end
    for _, switch in ipairs(col.widget_list_by_type.switch) do
        if rawget(switch, "lockdown") then
            switch:Enable()
        end
    end
    if col.RefreshOptions then col:RefreshOptions() end
end

---Cap the open-menu height of every dropdown in a BuildMenu column so lists
---don't extend past the visible scroll area.
---@param col frame
local function limitDropdownMenuHeight(col)
    if not col.widget_list_by_type or not col.widget_list_by_type.dropdown then return end
    for _, dropdown in ipairs(col.widget_list_by_type.dropdown) do
        dropdown:SetMenuSize(nil, DROPDOWN_MAX_MENU_HEIGHT)
    end
end

---Measures the actual rendered bottom extent of a column's children
---(distance in pixels from the column's top edge to its lowest visible
---child's bottom edge). Used to anchor appended sub-sections dynamically
---so the gap doesn't depend on overestimating from widget counts.
---@param col frame
---@return number
local function measureColumnHeight(col)
    if not col then return 0 end
    local colTop = col:GetTop()
    if not colTop then return 0 end
    local maxDistance = 0
    -- Regions as well as children: a BuildMenu label is a FontString on the
    -- panel, not a child frame, so a column ending in one measures short and
    -- whatever anchors below it lands on top of the text.
    local function extend(obj)
        if obj:IsShown() then
            local bottom = obj:GetBottom()
            if bottom then
                local distance = colTop - bottom
                if distance > maxDistance then maxDistance = distance end
            end
        end
    end
    for _, child in ipairs({col:GetChildren()}) do extend(child) end
    for _, region in ipairs({col:GetRegions()}) do
        -- An empty FontString is invisible but still anchored where the last
        -- build left it: ClearOptionsPanel blanks a pooled widget's hasLabel
        -- without hiding it, so a taller previous component would otherwise
        -- drag the measure far past the visible bottom.
        if not (region.GetText and (region:GetText() or "") == "") then
            extend(region)
        end
    end
    return maxDistance
end

function private.Options.IsOptionsPanelOpen()
    return optionsFrame and optionsFrame:IsShown() or false
end

---Open the panel, optionally on a tab and a component.  `componentName` is a
---Trackers-tab component, or, with the Tracking tab's index, the tracker or
---"AdditionalFrame_<id>" whose section the Tracking tab expands and scrolls to.
---@param tabIndex number|nil
---@param componentName string|nil
function private.Options.OpenOptionsPanel(tabIndex, componentName)
    if not optionsFrame then
        private.Options.CreateOptionsFrame()
    end
    optionsFrame:Show()
    if tabIndex and selectTabFn then
        selectTabFn(tabIndex)
    end
    if componentName then
        if tabIndex == options.TRACKING_TAB_INDEX then
            private.TrackingTab.FocusSection(componentName)
        elseif selectTrackerComponentFn then
            selectTrackerComponentFn(componentName)
        end
    end
end

function private.Options.CloseOptionsPanel()
    if optionsFrame then
        optionsFrame:Hide()
    end
end

function private.Options.ToggleOptionsPanel()
    if optionsFrame and optionsFrame:IsShown() then
        private.Options.CloseOptionsPanel()
    else
        private.Options.OpenOptionsPanel()
    end
end

function private.Options.GetOptionsPanelFrame()
    return optionsFrame
end


local uiParent = _G["UIParent"]
---@cast uiParent frame

---Re-apply a global icon/bar chrome setting everywhere: icon_border, bar_border,
---icon_zoom, icon_aspect_ratio, icon_overrides.
---The aura trackers style and texture their buttons only on the dirty-restyle
---path, so the fontsDirty bridge is what carries such a change onto live buttons
---— same contract as the font setters (patterns.md "fontsDirty").  A plain
---RefreshAllComponents leaves every buff-icon button untouched until a /reload.
---The reset lands before Anchor.Refresh so only this pass runs the per-child
---styling.
local function refreshGlobalChrome()
    private.fontsDirty = true
    private.ComponentManager.RefreshAllComponents()
    private.fontsDirty = false
    private.Anchor.Refresh()
end

-- Transient state for the "Change All Fonts" controls (not saved to profile).
local bulkFontFace = "2002"
local bulkFontSize = 12
local bulkFontFlags = "OUTLINE"
local bulkFontColor = {1, 1, 1, 1}
local bulkShadowColor = {0, 0, 0, 1}
local bulkShadowOffsetX = 1
local bulkShadowOffsetY = -1

-- Transient state for the "Change All Textures" controls (not saved to profile).
local bulkTexture = ""

---Refresh secondary resources so color changes take effect immediately.
local function applyResourceColors()
    private.SecondaryResources.Refresh()
end

---Apply the current profile colors to all existing cast bar objects.
local function applyCastBarColors()
    for _, unitId in ipairs({"player", "target", "focus"}) do
        local bar = private.CastBar.GetCastBar(unitId)
        if bar then
            private.CastBar.ApplyColors(bar)
        end
    end
end

---Helper: build a DF BuildMenu color entry backed by any profile table.
---One generic body for every colour picker in the addon; the four wrappers
---below only bind the container table, the apply callback and the disable rule.
---@param getTable fun(): table  returns the table holding the color under `key`
---@param key string  key in that table
---@param name string  display label
---@param desc string  tooltip description
---@param apply fun()  re-applies the changed color to live frames
---@param disableif? fun(): boolean  greys the widget out when it returns true
---@return table  BuildMenu widget definition
local function colorEntry(getTable, key, name, desc, apply, disableif)
    return {
        type = "color",
        name = name,
        desc = desc,
        get = function()
            local c = getTable()[key]
            return {private.Util.Color(c)}
        end,
        set = function(_, r, g, b, a)
            getTable()[key] = {r, g, b, a}
            apply()
        end,
        disableif = disableif,
    }
end

local function castBarColorTable() return private.profile.castbar_colors end
local function primaryPowerColorTable() return private.profile.primary_resource_colors.power_colors end
local function resourceClassColorTable() return private.profile.resource_colors.class_colors end
local function secondarySettingsTable() return private.profile.components.SecondaryResources end

---Color entry for a `castbar_colors` key (e.g. "casting").
local function castBarColorEntry(profileKey, name, desc)
    return colorEntry(castBarColorTable, profileKey, name, desc, applyCastBarColors)
end

---Color entry for a `primary_resource_colors.power_colors` key (e.g. "MANA").
---Disabled unless the user opted into per-power overrides.
local function primaryColorEntry(powerKey, name, desc)
    return colorEntry(primaryPowerColorTable, powerKey, name, desc,
        function() private.PrimaryResources.Refresh() end,
        function() return not private.profile.primary_resource_colors.override_colors end)
end

---Color entry for a `resource_colors.class_colors` key (e.g. "WARRIOR").
---Disabled while the user has opted into class colors -- the per-class override
---has nothing left to change in that state.
local function resourceColorEntry(classKey, name, desc)
    return colorEntry(resourceClassColorTable, classKey, name, desc, applyResourceColors,
        function() return private.profile.resource_colors.use_class_color end)
end

---Color entry for a SecondaryResources component key (e.g. "fire_blast_color").
local function secondaryColorEntry(settingKey, name, desc)
    return colorEntry(secondarySettingsTable, settingKey, name, desc, applyResourceColors)
end

---Build the Colors tab content inside panel using DF:BuildMenu.
---Contains all color customization options (cast bar, health gradient, resource colors, border colors).
---@param panel frame
local function buildColorsTab(panel)
    local options_text_template = framework:GetTemplate("font", private.UIDefaults.presets.font)
    local options_dropdown_template = framework:GetTemplate("dropdown", private.UIDefaults.presets.dropdown)
    local options_switch_template = framework:GetTemplate("switch", private.UIDefaults.presets.checkbox)
    local options_slider_template = framework:GetTemplate("slider", private.UIDefaults.presets.slider)
    local options_button_template = framework:GetTemplate("button", private.UIDefaults.presets.button)

    -- Column 1: Cast Bar Colors + Health Gradient
    local col1_options = {
        {type = "label", get = function() return L["CASTBAR_COLORS_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},
        {
            type = "toggle",
            name = L["COLOR_USE_CLASS_COLOR"],
            desc = L["COLOR_USE_CLASS_COLOR_DESC"],
            get = function() return private.profile.castbar_colors.use_class_color end,
            set = function(_, _, value)
                private.profile.castbar_colors.use_class_color = value
                applyCastBarColors()
            end,
        },

        castBarColorEntry("casting", L["COLOR_CASTING"], L["COLOR_CASTING_DESC"]),
        castBarColorEntry("channeling", L["COLOR_CHANNELING"], L["COLOR_CHANNELING_DESC"]),
        castBarColorEntry("finished", L["COLOR_FINISHED"], L["COLOR_FINISHED_DESC"]),
        castBarColorEntry("non_interruptible", L["COLOR_NON_INTERRUPTIBLE"], L["COLOR_NON_INTERRUPTIBLE_DESC"]),
        castBarColorEntry("interrupted", L["COLOR_INTERRUPTED"], L["COLOR_INTERRUPTED_DESC"]),
        castBarColorEntry("important", L["COLOR_IMPORTANT"], L["COLOR_IMPORTANT_DESC"]),
        castBarColorEntry("empowered", L["COLOR_EMPOWERED"], L["COLOR_EMPOWERED_DESC"]),
        castBarColorEntry("instant_cast", L["COLOR_INSTANT_CAST"], L["COLOR_INSTANT_CAST_DESC"]),
        castBarColorEntry("background", L["COLOR_BACKGROUND"], L["COLOR_BACKGROUND_DESC"]),
        {
            type = "select",
            name = L["COLOR_BACKGROUND_TEXTURE"],
            desc = L["COLOR_BACKGROUND_TEXTURE_DESC"],
            get = function() return private.profile.castbar_colors.background_texture end,
            set = function(_, _, value)
                private.profile.castbar_colors.background_texture = value
                applyCastBarColors()
            end,
            values = function()
                local cb = function(_, _, value)
                    private.profile.castbar_colors.background_texture = value
                    applyCastBarColors()
                end
                local t = {{label = L["SETTING_TEXTURE_DEFAULT"], value = "", onclick = cb}}
                for _, key in ipairs(LibSharedMedia:List("statusbar") or {}) do
                    t[#t + 1] = {label = key, value = key, onclick = cb}
                end
                return t
            end,
        },

        {type = "blank"},

        {type = "label", get = function() return L["HEALTH_GRADIENT_COLORS_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "color",
            name = L["HEALTH_GRADIENT_LOW"],
            desc = L["HEALTH_GRADIENT_LOW_DESC"],
            get = function()
                local c = private.profile.health_gradient_colors.low
                return {c[1], c[2], c[3], c[4]}
            end,
            set = function(_, r, g, b, a)
                private.profile.health_gradient_colors.low = {r, g, b, a}
                private.PlayerHealthBar.InvalidateGradientCurve()
                private.PlayerHealthBar.Refresh()
            end,
        },
        {
            type = "color",
            name = L["HEALTH_GRADIENT_MID"],
            desc = L["HEALTH_GRADIENT_MID_DESC"],
            get = function()
                local c = private.profile.health_gradient_colors.mid
                return {c[1], c[2], c[3], c[4]}
            end,
            set = function(_, r, g, b, a)
                private.profile.health_gradient_colors.mid = {r, g, b, a}
                private.PlayerHealthBar.InvalidateGradientCurve()
                private.PlayerHealthBar.Refresh()
            end,
        },
        {
            type = "color",
            name = L["HEALTH_GRADIENT_FULL"],
            desc = L["HEALTH_GRADIENT_FULL_DESC"],
            get = function()
                local c = private.profile.health_gradient_colors.full
                return {c[1], c[2], c[3], c[4]}
            end,
            set = function(_, r, g, b, a)
                private.profile.health_gradient_colors.full = {r, g, b, a}
                private.PlayerHealthBar.InvalidateGradientCurve()
                private.PlayerHealthBar.Refresh()
            end,
        },

        {type = "blank"},

        {
            type = "color",
            name = L["BG_COLOR_HEALTH"],
            desc = L["BG_COLOR_HEALTH_DESC"],
            get = function()
                local c = private.profile.components.PlayerHealthBar.background_color
                return {c[1], c[2], c[3], c[4]}
            end,
            set = function(_, r, g, b, a)
                private.profile.components.PlayerHealthBar.background_color = {r, g, b, a}
                private.PlayerHealthBar.Refresh()
            end,
        },
    }
    col1_options.always_boxfirst = true

    -- Column 2: Primary Resource Colors
    local col2_options = {
        {type = "label", get = function() return L["PRIMARY_RESOURCE_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "toggle",
            name = L["PRIMARY_OVERRIDE_COLOR"],
            desc = L["PRIMARY_OVERRIDE_COLOR_DESC"],
            get = function() return not private.profile.primary_resource_colors.override_colors end,
            set = function(_, _, value)
                private.profile.primary_resource_colors.override_colors = not value
                private.PrimaryResources.Refresh()
            end,
        },

        primaryColorEntry("MANA", L["POWER_MANA"], L["POWER_MANA_DESC"]),
        primaryColorEntry("RAGE", L["POWER_RAGE"], L["POWER_RAGE_DESC"]),
        primaryColorEntry("FOCUS", L["POWER_FOCUS"], L["POWER_FOCUS_DESC"]),
        primaryColorEntry("ENERGY", L["POWER_ENERGY"], L["POWER_ENERGY_DESC"]),
        primaryColorEntry("RUNIC_POWER", L["POWER_RUNIC_POWER"], L["POWER_RUNIC_POWER_DESC"]),
        primaryColorEntry("INSANITY", L["POWER_INSANITY"], L["POWER_INSANITY_DESC"]),
        primaryColorEntry("FURY", L["POWER_FURY"], L["POWER_FURY_DESC"]),
        primaryColorEntry("PAIN", L["POWER_PAIN"], L["POWER_PAIN_DESC"]),
        primaryColorEntry("LUNAR_POWER", L["POWER_LUNAR_POWER"], L["POWER_LUNAR_POWER_DESC"]),
        primaryColorEntry("MAELSTROM", L["POWER_MAELSTROM"], L["POWER_MAELSTROM_DESC"]),

        {type = "blank"},

        {
            type = "color",
            name = L["BG_COLOR_PRIMARY"],
            desc = L["BG_COLOR_PRIMARY_DESC"],
            get = function()
                local c = private.profile.components.PrimaryResources.background_color
                return {c[1], c[2], c[3], c[4]}
            end,
            set = function(_, r, g, b, a)
                private.profile.components.PrimaryResources.background_color = {r, g, b, a}
                private.PrimaryResources.Refresh()
            end,
        },
    }
    col2_options.always_boxfirst = true

    -- Column 3: Secondary Resource Colors + Border Colors
    local col3_options = {
        {type = "label", get = function() return L["RESOURCE_COLORS_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "toggle",
            name = L["USE_CLASS_COLOR"],
            desc = L["USE_CLASS_COLOR_DESC"],
            get = function() return private.profile.resource_colors.use_class_color end,
            set = function(_, _, value)
                private.profile.resource_colors.use_class_color = value
                applyResourceColors()
            end,
        },

        resourceColorEntry("ROGUE", L["CLASS_ROGUE"], L["CLASS_ROGUE_DESC"]),
        resourceColorEntry("DRUID", L["CLASS_DRUID"], L["CLASS_DRUID_DESC"]),
        resourceColorEntry("PALADIN", L["CLASS_PALADIN"], L["CLASS_PALADIN_DESC"]),
        resourceColorEntry("MONK", L["CLASS_MONK"], L["CLASS_MONK_DESC"]),
        resourceColorEntry("WARLOCK", L["CLASS_WARLOCK"], L["CLASS_WARLOCK_DESC"]),
        resourceColorEntry("MAGE", L["CLASS_MAGE"], L["CLASS_MAGE_DESC"]),
        resourceColorEntry("EVOKER", L["CLASS_EVOKER"], L["CLASS_EVOKER_DESC"]),
        resourceColorEntry("DEATHKNIGHT", L["CLASS_DEATHKNIGHT"], L["CLASS_DEATHKNIGHT_DESC"]),

        {type = "blank"},

        secondaryColorEntry("dk_blood_color", L["SETTING_DK_BLOOD_COLOR"], L["SETTING_DK_BLOOD_COLOR_DESC"]),
        secondaryColorEntry("dk_frost_color", L["SETTING_DK_FROST_COLOR"], L["SETTING_DK_FROST_COLOR_DESC"]),
        secondaryColorEntry("dk_unholy_color", L["SETTING_DK_UNHOLY_COLOR"], L["SETTING_DK_UNHOLY_COLOR_DESC"]),

        {type = "blank"},

        secondaryColorEntry("stagger_color_light", L["SETTING_STAGGER_COLOR_LIGHT"], L["SETTING_STAGGER_COLOR_LIGHT_DESC"]),
        secondaryColorEntry("stagger_color_moderate", L["SETTING_STAGGER_COLOR_MODERATE"], L["SETTING_STAGGER_COLOR_MODERATE_DESC"]),
        secondaryColorEntry("stagger_color_heavy", L["SETTING_STAGGER_COLOR_HEAVY"], L["SETTING_STAGGER_COLOR_HEAVY_DESC"]),

        {type = "blank"},

        {
            type = "toggle",
            name = L["SETTING_STATIC_BG"],
            desc = L["SETTING_STATIC_BG_DESC"],
            get = function()
                return private.profile.components.SecondaryResources.use_static_background
            end,
            set = function(_, _, v)
                private.profile.components.SecondaryResources.use_static_background = v
                applyResourceColors()
            end,
        },
        {
            type = "color",
            name = L["BG_COLOR_SECONDARY"],
            desc = L["BG_COLOR_SECONDARY_DESC"],
            get = function()
                local c = private.profile.components.SecondaryResources.background_color
                return {c[1], c[2], c[3], c[4]}
            end,
            set = function(_, r, g, b, a)
                private.profile.components.SecondaryResources.background_color = {r, g, b, a}
                applyResourceColors()
            end,
        },

    }
    col3_options.always_boxfirst = true

    -- Column 4: Special secondary resource colors
    local col4_options = {
        {type = "label", get = function() return L["RESOURCE_CUSTOM_COLORS_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        secondaryColorEntry("charged_combo_color", L["SETTING_CHARGED_COMBO_COLOR"], L["SETTING_CHARGED_COMBO_COLOR_DESC"]),
        secondaryColorEntry("fire_blast_color", L["SETTING_FIRE_BLAST_COLOR"], L["SETTING_FIRE_BLAST_COLOR_DESC"]),
        secondaryColorEntry("marksman_aimed_shot_color", L["SETTING_MARKSMAN_AIMED_SHOT_COLOR"], L["SETTING_MARKSMAN_AIMED_SHOT_COLOR_DESC"]),
        secondaryColorEntry("discipline_radiance_color", L["SETTING_DISCIPLINE_RADIANCE_COLOR"], L["SETTING_DISCIPLINE_RADIANCE_COLOR_DESC"]),
        secondaryColorEntry("marksman_lock_and_load_color", L["SETTING_MARKSMAN_LOCK_AND_LOAD_COLOR"], L["SETTING_MARKSMAN_LOCK_AND_LOAD_COLOR_DESC"]),
        secondaryColorEntry("fury_whirlwind_color", L["SETTING_FURY_WHIRLWIND_COLOR"], L["SETTING_FURY_WHIRLWIND_COLOR_DESC"]),
        secondaryColorEntry("arms_sweeping_strikes_color", L["SETTING_ARMS_SWEEPING_STRIKES_COLOR"], L["SETTING_ARMS_SWEEPING_STRIKES_COLOR_DESC"]),
        secondaryColorEntry("mage_shatter_color", L["SETTING_MAGE_SHATTER_COLOR"], L["SETTING_MAGE_SHATTER_COLOR_DESC"]),
        secondaryColorEntry("warlock_wild_imps_color", L["SETTING_WARLOCK_WILD_IMPS_COLOR"], L["SETTING_WARLOCK_WILD_IMPS_COLOR_DESC"]),
        secondaryColorEntry("mage_arcane_salvo_color", L["SETTING_MAGE_ARCANE_SALVO_COLOR"], L["SETTING_MAGE_ARCANE_SALVO_COLOR_DESC"]),
        secondaryColorEntry("evoker_unbound_flame_color", L["SETTING_EVOKER_UNBOUND_FLAME_COLOR"], L["SETTING_EVOKER_UNBOUND_FLAME_COLOR_DESC"]),
        secondaryColorEntry("evoker_unbound_flame_expiry_color", L["SETTING_EVOKER_UNBOUND_FLAME_EXPIRY_COLOR"], L["SETTING_EVOKER_UNBOUND_FLAME_EXPIRY_COLOR_DESC"]),
        secondaryColorEntry("dh_nearby_souls_color", L["SETTING_DH_NEARBY_SOULS_COLOR"], L["SETTING_DH_NEARBY_SOULS_COLOR_DESC"]),
        secondaryColorEntry("dh_art_of_glaive_color", L["SETTING_DH_ART_OF_GLAIVE_COLOR"], L["SETTING_DH_ART_OF_GLAIVE_COLOR_DESC"]),
        secondaryColorEntry("protection_ignore_pain_color", L["SETTING_PROTECTION_IGNORE_PAIN_COLOR"], L["SETTING_PROTECTION_IGNORE_PAIN_COLOR_DESC"]),
        secondaryColorEntry("survival_tots_color", L["SETTING_SURVIVAL_TOTS_COLOR"], L["SETTING_SURVIVAL_TOTS_COLOR_DESC"]),
        secondaryColorEntry("frost_icicles_color", L["SETTING_FROST_ICICLES_COLOR"], L["SETTING_FROST_ICICLES_COLOR_DESC"]),
        secondaryColorEntry("guardian_ironfur_color", L["SETTING_GUARDIAN_IRONFUR_COLOR"], L["SETTING_GUARDIAN_IRONFUR_COLOR_DESC"]),
        secondaryColorEntry("enhancement_mw_color", L["SETTING_ENHANCEMENT_MW_COLOR"], L["SETTING_ENHANCEMENT_MW_COLOR_DESC"]),
        {
            type = "color",
            name = L["SETTING_ENHANCEMENT_MW_THRESHOLD_COLOR"],
            desc = L["SETTING_ENHANCEMENT_MW_THRESHOLD_COLOR_DESC"],
            get = function()
                local c = private.profile.components.SecondaryResources.enhancement_mw_threshold_color
                return {private.Util.Color(c)}
            end,
            set = function(_, r, g, b, a)
                private.profile.components.SecondaryResources.enhancement_mw_threshold_color = {r, g, b, a}
                applyResourceColors()
            end,
            disableif = function() return not private.profile.components.SecondaryResources.enhancement_mw_threshold end,
        },
        secondaryColorEntry("rogue_coup_de_grace_color", L["SETTING_ROGUE_CDG_COLOR"], L["SETTING_ROGUE_CDG_COLOR_DESC"]),
        secondaryColorEntry("soul_frag_veng_color", L["SETTING_SOUL_FRAG_VENG_COLOR"], L["SETTING_SOUL_FRAG_VENG_COLOR_DESC"]),
        secondaryColorEntry("soul_frag_dev_color", L["SETTING_SOUL_FRAG_DEV_COLOR"], L["SETTING_SOUL_FRAG_DEV_COLOR_DESC"]),
        secondaryColorEntry("vitality_color", L["SETTING_VITALITY_COLOR"], L["SETTING_VITALITY_COLOR_DESC"]),
        secondaryColorEntry("mistweaver_teachings_color", L["SETTING_MISTWEAVER_TEACHINGS_COLOR"], L["SETTING_MISTWEAVER_TEACHINGS_COLOR_DESC"]),

        {type = "blank"},

        secondaryColorEntry("vigor_color", L["SETTING_VIGOR_COLOR"], L["SETTING_VIGOR_COLOR_DESC"]),
        secondaryColorEntry("vigor_thrill_color", L["SETTING_VIGOR_THRILL_COLOR"], L["SETTING_VIGOR_THRILL_COLOR_DESC"]),
    }
    col4_options.always_boxfirst = true

    -- Description text at the top of the Colors tab
    local description = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    description:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)
    description:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    description:SetWordWrap(true)
    description:SetNonSpaceWrap(true)
    description:SetJustifyH("LEFT")
    description:SetText(L["COLORS_TAB_DESCRIPTION"])
    description:SetTextColor(0.8, 0.8, 0.8)

    local colorColumns = private.UIDefaults.colorColumns

    -- The columns scroll below the description: the longest one outgrew the panel.
    -- -30 on the right leaves room for the scroll bar, which sits outside the frame.
    local scrollFrame = framework:CreateCanvasScrollBox(panel, nil, frameName .. "ColorsScrollFrame")
    scrollFrame:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, colorColumns.startYOffset)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 5)
    local scrollChild = scrollFrame.child
    scrollChild:SetWidth(colorColumns.columnSpacing * 3 + colorColumns.columnWidth)

    local col1 = CreateFrame("Frame", frameName .. "ColorsCol1", scrollChild)
    col1:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", colorColumns.startXOffset, 0)
    col1:SetSize(colorColumns.columnWidth, colorColumns.columnHeight)

    local col2 = CreateFrame("Frame", frameName .. "ColorsCol2", scrollChild)
    col2:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", colorColumns.columnSpacing, 0)
    col2:SetSize(colorColumns.columnWidth, colorColumns.columnHeight)

    local col3 = CreateFrame("Frame", frameName .. "ColorsCol3", scrollChild)
    col3:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", colorColumns.columnSpacing * 2, 0)
    col3:SetSize(colorColumns.columnWidth, colorColumns.columnHeight)

    local col4 = CreateFrame("Frame", frameName .. "ColorsCol4", scrollChild)
    col4:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", colorColumns.columnSpacing * 3, 0)
    col4:SetSize(colorColumns.columnWidth, colorColumns.columnHeight)

    -- BuildMenu opens a new sub-column once a column passes `height`, which is what
    -- pushed the last column off the right edge; never reach it, the scroll box
    -- takes the overflow.
    local noWrapHeight = 10000
    framework:BuildMenu(col1, col1_options, 0, 0, noWrapHeight, false, options_text_template, options_dropdown_template, options_switch_template, true, options_slider_template, options_button_template, refreshBuildMenuColumns)
    framework:BuildMenu(col2, col2_options, 0, 0, noWrapHeight, false, options_text_template, options_dropdown_template, options_switch_template, true, options_slider_template, options_button_template, refreshBuildMenuColumns)
    framework:BuildMenu(col3, col3_options, 0, 0, noWrapHeight, false, options_text_template, options_dropdown_template, options_switch_template, true, options_slider_template, options_button_template, refreshBuildMenuColumns)
    framework:BuildMenu(col4, col4_options, 0, 0, noWrapHeight, false, options_text_template, options_dropdown_template, options_switch_template, true, options_slider_template, options_button_template, refreshBuildMenuColumns)

    -- Content height exists only once laid out, so fit the scroll range on show.
    scrollFrame:HookScript("OnShow", function()
        C_Timer.After(0, function()
            scrollChild:SetHeight(math.max(measureColumnHeight(col1), measureColumnHeight(col2), measureColumnHeight(col3), measureColumnHeight(col4)) + 20)
        end)
    end)

    limitDropdownMenuHeight(col1)
    limitDropdownMenuHeight(col2)
    limitDropdownMenuHeight(col3)
    limitDropdownMenuHeight(col4)

    optionsPanelColumns[#optionsPanelColumns + 1] = col1
    optionsPanelColumns[#optionsPanelColumns + 1] = col2
    optionsPanelColumns[#optionsPanelColumns + 1] = col3
    optionsPanelColumns[#optionsPanelColumns + 1] = col4
end

---Build the General tab content inside panel using DF:BuildMenu.
---@param panel frame
local function buildGeneralTab(panel)
    local options_text_template = framework:GetTemplate("font", private.UIDefaults.presets.font)
    local options_dropdown_template = framework:GetTemplate("dropdown", private.UIDefaults.presets.dropdown)
    local options_switch_template = framework:GetTemplate("switch", private.UIDefaults.presets.checkbox)
    local options_slider_template = framework:GetTemplate("slider", private.UIDefaults.presets.slider)
    local options_button_template = framework:GetTemplate("button", private.UIDefaults.presets.button)

    -- Every CDM widget is hidden on a client without Blizzard's Cooldown Manager
    -- (MoP Classic): it has nothing to fetch, alert, show or sync.
    local noCDM = not private.compat.HasCooldownManager()

    -- Column 1: CDM settings + Icon settings + Border settings + Minimap
    local col1_options = {
        {type = "label", get = function() return L["CDM_SECTION_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color, hidden = noCDM},

        {
            type = "toggle",
            hidden = noCDM,
            name = L["CDM_AUTO_FETCH_TOGGLE"],
            desc = L["CDM_AUTO_FETCH_DESC"],
            get = function() return private.profile.cdm_auto_fetch end,
            set = function(_, _, value)
                private.profile.cdm_auto_fetch = value
                private.Callback.Trigger("OnCDMSpellsChanged")
            end,
        },

        {
            type = "toggle",
            hidden = noCDM,
            name = L["CDM_ALERTS_TOGGLE"],
            desc = L["CDM_ALERTS_DESC"],
            get = function() return private.profile.cdm_alerts end,
            set = function(_, _, value)
                private.profile.cdm_alerts = value
                -- Registrations, not Rebuild: the master switch is read by
                -- applyAuraRegistrations and is invisible to the rebuild's own
                -- change detection, so a plain Rebuild would skip the tail.
                private.CDMAlerts.RebuildRegistrations()
            end,
        },

        {
            -- Blizzard's own viewer is the only source of an alert on the player's
            -- debuff on the target (Core/CDMDataSource.lua, needsViewerChildren),
            -- so this turns the CDM on and hides it.  EnsureEnabled settles both;
            -- the viewers' OnShow/OnHide hooks then rebuild CDMAlerts.
            type = "toggle",
            hidden = noCDM,
            name = L["CDM_TARGET_SOUNDS_TOGGLE"],
            desc = L["CDM_TARGET_SOUNDS_DESC"],
            get = function() return private.profile.cdm_target_sounds end,
            set = function(_, _, value)
                private.profile.cdm_target_sounds = value
                private.CDMDataSource.EnsureEnabled()
            end,
        },

        {
            -- CHARACTER-scoped, not profile: it describes this character's addon
            -- environment rather than a layout, so it survives a profile switch
            -- and never travels in an export (Core/CDMDataSource.lua,
            -- suppressionAllowed).  Ticked means the viewers really are hidden,
            -- read from the gate itself: the answer (cdm_hidden) and the
            -- cdm_target_sounds option can each put them there.  Reading the
            -- opt-out alone showed it ticked on every character that never
            -- answered the prompt, with nothing hidden.  Ticking records the
            -- answer too, but grants no CVar write: it hides, it does not turn
            -- the CDM off.  Unticking keeps the answer so the prompt stays quiet.
            type = "toggle",
            hidden = noCDM,
            name = L["CDM_SUPPRESS_VIEWERS_TOGGLE"],
            desc = L["CDM_SUPPRESS_VIEWERS_DESC"],
            get = function() return private.CDMDataSource.IsSuppressing() end,
            set = function(_, _, value)
                if not private.charDB then return end
                if value then private.charDB.cdm_hidden = true end
                private.charDB.cdm_no_suppress = (not value) or nil
                -- Re-derives the gate and settles the viewers either way; a plain
                -- SyncViewerSuppression would not, since `suppressing` itself has
                -- to change.
                private.CDMDataSource.EnsureEnabled()
            end,
        },

        {type = "blank", hidden = noCDM},

        {type = "label", get = function() return L["ICON_ZOOM_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "toggle",
            name = L["ICON_ZOOM_ENABLED"],
            desc = framework:AddTextureToText(L["ICON_ZOOM_ENABLED_DESC"] .. "\n\n", framework:CreateTextureInfo([[Interface/AddOns/ClassUIEnhanced/Assets/Textures/OptionsTooltips/tooltips.png]], 275*0.7, 113*0.7, 0, 275/1024, 0, 115/1024, 1024, 1024), false, true),
            get = function() return private.profile.icon_zoom end,
            set = function(_, _, value)
                private.profile.icon_zoom = value
                refreshGlobalChrome()
            end,
        },

        {
            type = "toggle",
            name = L["ICON_ASPECT_RATIO"],
            desc = L["ICON_ASPECT_RATIO_DESC"],
            get = function() return private.profile.icon_aspect_ratio end,
            set = function(_, _, value)
                private.profile.icon_aspect_ratio = value
                refreshGlobalChrome()
            end,
        },

        {type = "blank"},

        {type = "label", get = function() return L["BAR_BORDER_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "toggle",
            name = L["BAR_BORDER_ENABLED"],
            desc = L["BAR_BORDER_ENABLED_DESC"],
            get = function() return private.profile.bar_border.enabled end,
            set = function(_, _, value)
                private.profile.bar_border.enabled = value
                refreshGlobalChrome()
            end,
            children_follow_enabled = true,
            childrenids = {"bar_border_color", "bar_border_inside", "bar_border_size"},
        },

        {
            type = "color",
            id = "bar_border_color",
            name = L["BAR_BORDER_COLOR"],
            desc = L["BAR_BORDER_COLOR_DESC"],
            get = function()
                local c = private.profile.bar_border.color
                return {c[1], c[2], c[3], c[4]}
            end,
            set = function(_, r, g, b, a)
                private.profile.bar_border.color = {r, g, b, a}
                refreshGlobalChrome()
            end,
        },

        {
            type = "toggle",
            id = "bar_border_inside",
            name = L["BAR_BORDER_INSIDE"],
            desc = L["BAR_BORDER_INSIDE_DESC"],
            get = function() return private.profile.bar_border.inside end,
            set = function(_, _, value)
                private.profile.bar_border.inside = value
                refreshGlobalChrome()
            end,
        },

        {
            type = "range",
            id = "bar_border_size",
            name = L["BORDER_SIZE"],
            desc = L["BORDER_SIZE_DESC"],
            min = 1,
            max = 5,
            step = 1,
            get = function() return private.profile.bar_border.size end,
            set = function(_, _, value)
                private.profile.bar_border.size = value
                refreshGlobalChrome()
            end,
        },

        {type = "blank"},

        {type = "label", get = function() return L["ICON_BORDER_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "toggle",
            name = L["ICON_BORDER_ENABLED"],
            desc = L["ICON_BORDER_ENABLED_DESC"],
            get = function() return private.profile.icon_border.enabled end,
            set = function(_, _, value)
                private.profile.icon_border.enabled = value
                refreshGlobalChrome()
            end,
            children_follow_enabled = true,
            childrenids = {"icon_border_color", "icon_border_inside", "icon_border_size"},
        },

        {
            type = "color",
            id = "icon_border_color",
            name = L["ICON_BORDER_COLOR"],
            desc = L["ICON_BORDER_COLOR_DESC"],
            get = function()
                local c = private.profile.icon_border.color
                return {c[1], c[2], c[3], c[4]}
            end,
            set = function(_, r, g, b, a)
                private.profile.icon_border.color = {r, g, b, a}
                refreshGlobalChrome()
            end,
        },

        {
            type = "toggle",
            id = "icon_border_inside",
            name = L["ICON_BORDER_INSIDE"],
            desc = L["ICON_BORDER_INSIDE_DESC"],
            get = function() return private.profile.icon_border.inside end,
            set = function(_, _, value)
                private.profile.icon_border.inside = value
                refreshGlobalChrome()
            end,
        },

        {
            type = "range",
            id = "icon_border_size",
            name = L["BORDER_SIZE"],
            desc = L["BORDER_SIZE_DESC"],
            min = 1,
            max = 5,
            step = 1,
            get = function() return private.profile.icon_border.size end,
            set = function(_, _, value)
                private.profile.icon_border.size = value
                refreshGlobalChrome()
            end,
        },

        {type = "blank"},

        {type = "label", get = function() return L["SECTION_TOOLTIP"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        -- Blizzard's own account-wide CVar. Deliberately NOT mirrored into a
        -- profile key: the client already persists it, so a stored copy would
        -- only add a drift bug when the CVar is changed outside our panel.
        -- Guard-written per patterns.md (SetCVar always fires CVAR_UPDATE).
        {
            type = "toggle",
            name = L["TOOLTIP_AURA_SPELL_IDS"],
            desc = L["TOOLTIP_AURA_SPELL_IDS_DESC"],
            get = function() return C_CVar.GetCVar("tooltipShowAuraSpellIDs") == "1" end,
            set = function(_, _, value)
                local want = value and "1" or "0"
                if C_CVar.GetCVar("tooltipShowAuraSpellIDs") ~= want then
                    C_CVar.SetCVar("tooltipShowAuraSpellIDs", want)
                end
            end,
        },

    }
    col1_options.always_boxfirst = true

    -- Column 2: Button press + Class tweaks + Minimap + Debug
    local col2_options = {
        {type = "label", get = function() return L["BUTTON_PRESS_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "toggle",
            name = L["BUTTON_PRESS_ENABLED"],
            desc = L["BUTTON_PRESS_ENABLED_DESC"],
            get = function() return private.profile.button_press.enabled end,
            set = function(_, _, value)
                private.profile.button_press.enabled = value
            end,
        },

        {type = "blank"},

        {type = "label", get = function() return L["CLASS_TWEAKS_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "toggle",
            name = L["ARCANE_MANA_BAR"],
            desc = L["ARCANE_MANA_BAR_DESC"],
            get = function() return private.profile.arcane_mana_bar end,
            set = function(_, _, value)
                private.profile.arcane_mana_bar = value
                private.PrimaryResources.Refresh()
                private.Anchor.OnComponentStateChange()
            end,
        },

        {
            type = "toggle",
            name = L["AUG_EBON_MIGHT_BAR"],
            desc = L["AUG_EBON_MIGHT_BAR_DESC"],
            get = function() return private.profile.augmentation_ebon_might end,
            set = function(_, _, value)
                private.profile.augmentation_ebon_might = value
                private.PrimaryResources.Refresh()
                private.Anchor.OnComponentStateChange()
            end,
        },

        {
            type = "toggle",
            name = L["AUG_EBON_MIGHT_SHOW_STAT"],
            desc = L["AUG_EBON_MIGHT_SHOW_STAT_DESC"],
            get = function() return private.profile.augmentation_ebon_might_show_stat end,
            set = function(_, _, value)
                private.profile.augmentation_ebon_might_show_stat = value
                private.PrimaryResources.Refresh()
            end,
        },

        {
            type = "color",
            name = L["AUG_EBON_MIGHT_CRIT_COLOR_VALUE"],
            desc = L["AUG_EBON_MIGHT_CRIT_COLOR_VALUE_DESC"],
            get = function()
                local c = private.profile.augmentation_ebon_might_crit_color_value
                return {c[1], c[2], c[3], c[4]}
            end,
            set = function(_, r, g, b, a)
                private.profile.augmentation_ebon_might_crit_color_value = {r, g, b, a}
                private.PrimaryResources.Refresh()
            end,
            disableif = function() return not private.PrimaryResources.IsCritDetectionAvailable() end,
        },

        {
            type = "toggle",
            name = L["AUG_EBON_MIGHT_CRIT_GLOW"],
            desc = L["AUG_EBON_MIGHT_CRIT_GLOW_DESC"],
            get = function() return private.profile.augmentation_ebon_might_crit_glow end,
            set = function(_, _, value)
                private.profile.augmentation_ebon_might_crit_glow = value
                private.PrimaryResources.Refresh()
            end,
            disableif = function() return not private.PrimaryResources.IsCritDetectionAvailable() end,
        },

        {
            type = "toggle",
            name = L["AUG_EBON_MIGHT_DOUBLE_TIME_TEXT"],
            desc = L["AUG_EBON_MIGHT_DOUBLE_TIME_TEXT_DESC"],
            get = function() return private.profile.augmentation_ebon_might_double_time_text end,
            set = function(_, _, value)
                private.profile.augmentation_ebon_might_double_time_text = value
                private.PrimaryResources.Refresh()
            end,
            disableif = function() return not private.PrimaryResources.IsCritDetectionAvailable() end,
        },

        {
            type = "toggle",
            name = L["AUG_EBON_MIGHT_LIVE_UPDATE"],
            desc = L["AUG_EBON_MIGHT_LIVE_UPDATE_DESC"],
            get = function() return private.profile.augmentation_ebon_might_live_update end,
            set = function(_, _, value)
                private.profile.augmentation_ebon_might_live_update = value
                private.PrimaryResources.Refresh()
            end,
        },

        {
            type = "toggle",
            name = L["AUG_EBON_MIGHT_SHOW_DUPLICATES"],
            desc = L["AUG_EBON_MIGHT_SHOW_DUPLICATES_DESC"],
            get = function() return private.profile.augmentation_ebon_might_show_duplicates end,
            set = function(_, _, value)
                private.profile.augmentation_ebon_might_show_duplicates = value
                private.PrimaryResources.Refresh()
            end,
        },

        {type = "blank"},

        {type = "label", get = function() return L["MINIMAP_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "toggle",
            name = L["MINIMAP_SHOW"],
            desc = L["MINIMAP_SHOW_DESC"],
            get = function() return not private.public.db.global.minimap.hide end,
            set = function(_, _, value)
                private.public.db.global.minimap.hide = not value
                if value then
                    private.libDBIcon:Show("ClassUIEnhanced")
                else
                    private.libDBIcon:Hide("ClassUIEnhanced")
                end
            end,
        },

        {type = "blank"},

        {type = "label", get = function() return L["DEBUG_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "toggle",
            name = L["DEBUG_ENABLED"],
            desc = L["DEBUG_ENABLED_DESC"],
            get = function() return private.profile.debug_mode end,
            set = function(_, _, value)
                private.SetDebugMode(value)
            end,
        },
    }
    col2_options.always_boxfirst = true

    -- Column 3: Bulk editors + Layout sync
    local col3_options = {
        {type = "label", get = function() return L["CHANGE_ALL_FONTS_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "selectfont",
            name = L["SETTING_FONT"],
            desc = L["SETTING_FONT_DESC"],
            get = function() return bulkFontFace end,
            set = function(_, _, value)
                bulkFontFace = value
            end,
        },

        {
            type = "range",
            name = L["SETTING_FONT_SIZE"],
            desc = L["SETTING_FONT_SIZE_DESC"],
            min = 6,
            max = 32,
            step = 1,
            get = function() return bulkFontSize end,
            set = function(_, _, value)
                bulkFontSize = value
            end,
        },

        {
            type = "selectoutline",
            name = L["SETTING_FONT_OUTLINE"],
            desc = L["SETTING_FONT_OUTLINE_DESC"],
            get = function() return bulkFontFlags end,
            set = function(_, _, value)
                bulkFontFlags = value
                if value ~= "" and value ~= "NONE" then
                    bulkShadowColor = {0, 0, 0, 1}
                    bulkShadowOffsetX = 1
                    bulkShadowOffsetY = -1
                end
            end,
        },

        {
            type = "color",
            name = L["SETTING_FONT_COLOR"],
            desc = L["SETTING_FONT_COLOR_DESC"],
            boxfirst = true,
            get = function()
                return bulkFontColor[1], bulkFontColor[2], bulkFontColor[3], bulkFontColor[4]
            end,
            set = function(_, r, g, b, a)
                bulkFontColor = {r, g, b, a}
            end,
        },

        {
            type = "color",
            name = L["SETTING_FONT_SHADOW_COLOR"],
            desc = L["SETTING_FONT_SHADOW_COLOR_DESC"],
            boxfirst = true,
            get = function()
                return bulkShadowColor[1], bulkShadowColor[2], bulkShadowColor[3], bulkShadowColor[4]
            end,
            set = function(_, r, g, b, a)
                bulkShadowColor = {r, g, b, a}
            end,
            disableif = function()
                return bulkFontFlags ~= "" and bulkFontFlags ~= "NONE"
            end,
        },

        {
            type = "range",
            name = L["SETTING_FONT_SHADOW_OFFSET_X"],
            desc = L["SETTING_FONT_SHADOW_OFFSET_X_DESC"],
            min = -5,
            max = 5,
            step = 1,
            get = function() return bulkShadowOffsetX end,
            set = function(_, _, value)
                bulkShadowOffsetX = value
            end,
            disableif = function()
                return bulkFontFlags ~= "" and bulkFontFlags ~= "NONE"
            end,
        },

        {
            type = "range",
            name = L["SETTING_FONT_SHADOW_OFFSET_Y"],
            desc = L["SETTING_FONT_SHADOW_OFFSET_Y_DESC"],
            min = -5,
            max = 5,
            step = 1,
            get = function() return bulkShadowOffsetY end,
            set = function(_, _, value)
                bulkShadowOffsetY = value
            end,
            disableif = function()
                return bulkFontFlags ~= "" and bulkFontFlags ~= "NONE"
            end,
        },

        {
            type = "execute",
            name = L["CHANGE_ALL_FONTS_APPLY"],
            desc = L["CHANGE_ALL_FONTS_APPLY_DESC"],
            func = function()
                local fontFields = {
                    {"PlayerCastBar", "cast_name_font"},
                    {"PlayerCastBar", "cast_time_font"},
                    {"TargetCastBar", "cast_name_font"},
                    {"TargetCastBar", "cast_time_font"},
                    {"FocusCastBar", "cast_name_font"},
                    {"FocusCastBar", "cast_time_font"},
                    {"PrimaryResources", "value_font"},
                    {"SecondaryResources", "value_font"},
                    {"PlayerHealthBar", "value_font"},
                    {"CooldownTracker", "timer_font"},
                    {"CooldownTracker", "stacks_font"},
                    {"CooldownTracker", "keybind_font"},
                    {"BuffTracker", "timer_font"},
                    {"BuffTracker", "stacks_font"},
                    {"UtilitiesTracker", "timer_font"},
                    {"UtilitiesTracker", "stacks_font"},
                    {"UtilitiesTracker", "keybind_font"},
                    {"BuffTrackerBars", "name_font"},
                    {"BuffTrackerBars", "duration_font"},
                    {"BuffTrackerBars", "stacks_font"},
                    {"ConsumableTracker", "count_font"},
                    {"ConsumableTracker", "duration_font"},
                    {"ConsumableTracker", "keybind_font"},
                    {"ConsumableBuffTracker", "count_font"},
                    {"ConsumableBuffTracker", "duration_font"},
                    {"RaidBuffTracker", "duration_font"},
                    {"OutboundBuffTracker", "name_font"},
                    {"OutboundBuffTracker", "duration_font"},
                    {"OutboundBuffTracker", "stacks_font"},
                    {"TrinketTracker", "duration_font"},
                    {"TrinketTracker", "keybind_font"},
                    {"RacialTracker", "duration_font"},
                    {"RacialTracker", "keybind_font"},
                    {"GlobalCooldown", "duration_font"},
                    {"GlobalCooldown", "spell_name_font"},
                }

                for _, entry in ipairs(fontFields) do
                    local compSettings = private.profile.components[entry[1]]
                    if compSettings and compSettings[entry[2]] then
                        compSettings[entry[2]].font_face = bulkFontFace
                        compSettings[entry[2]].font_size = bulkFontSize
                        compSettings[entry[2]].font_flags = bulkFontFlags
                        compSettings[entry[2]].font_color = {bulkFontColor[1], bulkFontColor[2], bulkFontColor[3], bulkFontColor[4]}
                        compSettings[entry[2]].shadow_color = {bulkShadowColor[1], bulkShadowColor[2], bulkShadowColor[3], bulkShadowColor[4]}
                        compSettings[entry[2]].shadow_offset_x = bulkShadowOffsetX
                        compSettings[entry[2]].shadow_offset_y = bulkShadowOffsetY
                    end
                end

                -- Apply to Additional Frame font settings
                local afFontKeys = {
                    spells = {"timer_font", "stacks_font", "keybind_font"},
                    buffs = {"timer_font", "stacks_font"},
                    bar = {"name_font", "duration_font", "stacks_font"},
                }
                for _, afSettings in pairs(private.profile.additional_frames) do
                    local keys = afFontKeys[afSettings.frame_type] or {}
                    for _, fk in ipairs(keys) do
                        local ft = afSettings[fk]
                        if ft then
                            ft.font_face = bulkFontFace
                            ft.font_size = bulkFontSize
                            ft.font_flags = bulkFontFlags
                            ft.font_color = {bulkFontColor[1], bulkFontColor[2], bulkFontColor[3], bulkFontColor[4]}
                            ft.shadow_color = {bulkShadowColor[1], bulkShadowColor[2], bulkShadowColor[3], bulkShadowColor[4]}
                            ft.shadow_offset_x = bulkShadowOffsetX
                            ft.shadow_offset_y = bulkShadowOffsetY
                        end
                    end
                end

                private.ComponentManager.RefreshAllComponents()
                private.Anchor.Refresh()
                refreshBuildMenuColumns()
                private.print(L["CHANGE_ALL_FONTS_APPLIED"])
            end,
        },

        {type = "blank"},

        {type = "label", get = function() return L["CHANGE_ALL_TEXTURES_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "selectstatusbartexture",
            name = L["SETTING_TEXTURE"],
            desc = L["SETTING_TEXTURE_DESC"],
            get = function() return bulkTexture end,
            set = function(_, _, value)
                bulkTexture = value
            end,
        },

        {
            type = "execute",
            name = L["CHANGE_ALL_TEXTURES_APPLY"],
            desc = L["CHANGE_ALL_TEXTURES_APPLY_DESC"],
            func = function()
                local textureComponents = {
                    "PlayerCastBar",
                    "TargetCastBar",
                    "FocusCastBar",
                    "GlobalCooldown",
                    "PlayerHealthBar",
                    "PrimaryResources",
                    "SecondaryResources",
                }

                for _, compName in ipairs(textureComponents) do
                    local compSettings = private.profile.components[compName]
                    if compSettings and compSettings.texture ~= nil then
                        compSettings.texture = bulkTexture
                    end
                end

                private.ComponentManager.RefreshAllComponents()
                private.Anchor.Refresh()
                private.print(L["CHANGE_ALL_TEXTURES_APPLIED"])
            end,
        },

        {type = "blank", hidden = noCDM},

        {type = "label", get = function() return L["LAYOUT_SYNC_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color, hidden = noCDM},

        {
            type = "toggle",
            hidden = noCDM,
            name = L["LAYOUT_SYNC_ENABLED"],
            desc = L["LAYOUT_SYNC_ENABLED_DESC"],
            get = function() return private.profile.cooldown_layout_sync end,
            set = function(_, _, value)
                private.profile.cooldown_layout_sync = value
                if not value then
                    StaticPopup_Show("CLASSUIENHANCED_CLEAR_LAYOUTS")
                end
            end,
        },

        {
            type = "execute",
            hidden = noCDM,
            name = L["LAYOUT_SYNC_SAVE"],
            desc = L["LAYOUT_SYNC_SAVE_DESC"],
            func = function()
                private.CooldownLayoutSync.SaveCurrentLayout()
            end,
        },

        {
            type = "execute",
            hidden = noCDM,
            name = L["LAYOUT_SYNC_CLEAR"],
            desc = L["LAYOUT_SYNC_CLEAR_DESC"],
            func = function()
                private.CooldownLayoutSync.ClearStoredLayouts()
            end,
        },
    }
    col3_options.always_boxfirst = true

    -- Description text at the top of the General tab
    local description = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    description:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)
    description:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    description:SetWordWrap(true)
    description:SetNonSpaceWrap(true)
    description:SetJustifyH("LEFT")
    description:SetText(L["GENERAL_TAB_DESCRIPTION"])
    description:SetTextColor(0.8, 0.8, 0.8)

    -- Each column gets its own parent frame so BuildMenu widget names ($parentWidget1, etc.)
    -- don't collide across columns. Anchored relative to the description FontString so
    -- word-wrap height is resolved by layout.
    local col1 = CreateFrame("Frame", frameName .. "GeneralCol1", panel)
    col1:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -15)
    col1:SetSize(220, 500)

    local col2 = CreateFrame("Frame", frameName .. "GeneralCol2", panel)
    col2:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 240, -15)
    col2:SetSize(220, 500)

    local col3 = CreateFrame("Frame", frameName .. "GeneralCol3", panel)
    col3:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 480, -15)
    col3:SetSize(220, 500)

    framework:BuildMenu(col1, col1_options, 0, 0, 500, false, options_text_template, options_dropdown_template, options_switch_template, true, options_slider_template, options_button_template, refreshBuildMenuColumns)
    framework:BuildMenu(col2, col2_options, 0, 0, 500, false, options_text_template, options_dropdown_template, options_switch_template, true, options_slider_template, options_button_template, refreshBuildMenuColumns)
    framework:BuildMenu(col3, col3_options, 0, 0, 500, false, options_text_template, options_dropdown_template, options_switch_template, true, options_slider_template, options_button_template, refreshBuildMenuColumns)

    limitDropdownMenuHeight(col1)
    limitDropdownMenuHeight(col2)
    limitDropdownMenuHeight(col3)

    optionsPanelColumns[#optionsPanelColumns + 1] = col1
    optionsPanelColumns[#optionsPanelColumns + 1] = col2
    optionsPanelColumns[#optionsPanelColumns + 1] = col3
end

---Dropdown options for the 9 standard WoW anchor points (all "inside" style).
local FONT_ANCHOR_OPTIONS = {
    {label = "Top Left",     value = "TOPLEFT"},
    {label = "Top",          value = "TOP"},
    {label = "Top Right",    value = "TOPRIGHT"},
    {label = "Left",         value = "LEFT"},
    {label = "Center",       value = "CENTER"},
    {label = "Right",        value = "RIGHT"},
    {label = "Bottom Left",  value = "BOTTOMLEFT"},
    {label = "Bottom",       value = "BOTTOM"},
    {label = "Bottom Right", value = "BOTTOMRIGHT"},
}

---Build position widgets (anchor dropdown + X/Y offset sliders) for a font profile key.
---@param componentKey string
---@param fontKey string
---@param refreshFn function
---@param disableif? function
---@return table[]
local function fontPositionWidgets(componentKey, fontKey, refreshFn, disableif)
    return {
        {
            type = "select",
            name = L["SETTING_FONT_ANCHOR"],
            desc = L["SETTING_FONT_ANCHOR_DESC"],
            values = function()
                local t = {}
                for _, opt in ipairs(FONT_ANCHOR_OPTIONS) do
                    t[#t + 1] = {label = opt.label, value = opt.value, onclick = function(_, _, value)
                        private.profile.components[componentKey][fontKey].anchor_point = value
                        refreshFn()
                    end}
                end
                return t
            end,
            get = function() return private.profile.components[componentKey][fontKey].anchor_point end,
            set = function(_, _, value)
                private.profile.components[componentKey][fontKey].anchor_point = value
                refreshFn()
            end,
            disableif = disableif,
        },

        {
            type = "range",
            name = L["SETTING_FONT_OFFSET_X"],
            desc = L["SETTING_FONT_OFFSET_X_DESC"],
            min = -50,
            max = 50,
            step = 1,
            get = function() return private.profile.components[componentKey][fontKey].offset_x or 0 end,
            set = function(_, _, value)
                private.profile.components[componentKey][fontKey].offset_x = value
                refreshFn()
            end,
            disableif = disableif,
        },

        {
            type = "range",
            name = L["SETTING_FONT_OFFSET_Y"],
            desc = L["SETTING_FONT_OFFSET_Y_DESC"],
            min = -50,
            max = 50,
            step = 1,
            get = function() return private.profile.components[componentKey][fontKey].offset_y or 0 end,
            set = function(_, _, value)
                private.profile.components[componentKey][fontKey].offset_y = value
                refreshFn()
            end,
            disableif = disableif,
        },
    }
end

---Build a sub-header + font/size/outline triple for a single font profile key.
---When hasPosition is true, also appends anchor/offset controls.
---@param componentKey string  e.g. "PlayerCastBar"
---@param fontKey string  e.g. "cast_name_font"
---@param headerLabel string  e.g. L["SETTING_CAST_NAME_TEXT"]
---@param maxSize number  maximum slider value (24 for bars, 32 for icons)
---@param refreshFn function  called after each change
---@param hasPosition? boolean  when true, append anchor point + offset controls
---@return table[]  array of DF:BuildMenu widget definitions
local function fontGroupWidgets(componentKey, fontKey, headerLabel, maxSize, refreshFn, hasPosition)
    local widgets = {
        {type = "label", get = function() return headerLabel end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "selectfont",
            name = L["SETTING_FONT"],
            desc = L["SETTING_FONT_DESC"],
            get = function() return private.profile.components[componentKey][fontKey].font_face end,
            set = function(_, _, value)
                private.profile.components[componentKey][fontKey].font_face = value
                refreshFn()
            end,
        },

        {
            type = "range",
            name = L["SETTING_FONT_SIZE"],
            desc = L["SETTING_FONT_SIZE_DESC"],
            min = 6,
            max = maxSize,
            step = 1,
            get = function() return private.profile.components[componentKey][fontKey].font_size end,
            set = function(_, _, value)
                private.profile.components[componentKey][fontKey].font_size = value
                refreshFn()
            end,
        },

        {
            type = "selectoutline",
            name = L["SETTING_FONT_OUTLINE"],
            desc = L["SETTING_FONT_OUTLINE_DESC"],
            get = function() return private.profile.components[componentKey][fontKey].font_flags end,
            set = function(_, _, value)
                private.profile.components[componentKey][fontKey].font_flags = value
                if value ~= "" and value ~= "NONE" then
                    private.profile.components[componentKey][fontKey].shadow_color = {0, 0, 0, 1}
                    private.profile.components[componentKey][fontKey].shadow_offset_x = 1
                    private.profile.components[componentKey][fontKey].shadow_offset_y = -1
                end
                refreshFn()
            end,
        },

        {
            type = "color",
            name = L["SETTING_FONT_COLOR"],
            desc = L["SETTING_FONT_COLOR_DESC"],
            boxfirst = true,
            get = function()
                local c = private.profile.components[componentKey][fontKey].font_color or {1, 1, 1, 1}
                return private.Util.Color(c)
            end,
            set = function(_, r, g, b, a)
                private.profile.components[componentKey][fontKey].font_color = {r, g, b, a}
                refreshFn()
            end,
        },

        {
            type = "color",
            name = L["SETTING_FONT_SHADOW_COLOR"],
            desc = L["SETTING_FONT_SHADOW_COLOR_DESC"],
            boxfirst = true,
            get = function()
                local c = private.profile.components[componentKey][fontKey].shadow_color or {0, 0, 0, 1}
                return private.Util.Color(c)
            end,
            set = function(_, r, g, b, a)
                private.profile.components[componentKey][fontKey].shadow_color = {r, g, b, a}
                refreshFn()
            end,
            disableif = function()
                local flags = private.profile.components[componentKey][fontKey].font_flags
                return flags ~= "" and flags ~= "NONE"
            end,
        },

        {
            type = "range",
            name = L["SETTING_FONT_SHADOW_OFFSET_X"],
            desc = L["SETTING_FONT_SHADOW_OFFSET_X_DESC"],
            min = -5,
            max = 5,
            step = 1,
            get = function() return private.profile.components[componentKey][fontKey].shadow_offset_x or 1 end,
            set = function(_, _, value)
                private.profile.components[componentKey][fontKey].shadow_offset_x = value
                refreshFn()
            end,
            disableif = function()
                local flags = private.profile.components[componentKey][fontKey].font_flags
                return flags ~= "" and flags ~= "NONE"
            end,
        },

        {
            type = "range",
            name = L["SETTING_FONT_SHADOW_OFFSET_Y"],
            desc = L["SETTING_FONT_SHADOW_OFFSET_Y_DESC"],
            min = -5,
            max = 5,
            step = 1,
            get = function() return private.profile.components[componentKey][fontKey].shadow_offset_y or -1 end,
            set = function(_, _, value)
                private.profile.components[componentKey][fontKey].shadow_offset_y = value
                refreshFn()
            end,
            disableif = function()
                local flags = private.profile.components[componentKey][fontKey].font_flags
                return flags ~= "" and flags ~= "NONE"
            end,
        },
    }

    if hasPosition then
        for _, w in ipairs(fontPositionWidgets(componentKey, fontKey, refreshFn)) do
            widgets[#widgets + 1] = w
        end
    end

    return widgets
end

---Build font controls for keybind text display with position controls.
---The font/position controls are disabled when the keybind toggle (in EditMode) is off.
---@param componentKey string  profile component key (e.g. "CooldownTracker")
---@param headerLabel string  label shown above the controls
---@param maxSize number  max font size for the slider
---@param refreshFn function  called when settings change
---@return table[]
local function keybindFontGroupWidgets(componentKey, headerLabel, maxSize, refreshFn)
    local disableWhenOff = function()
        return not private.profile.components[componentKey].keybind_font.enabled
    end
    local widgets = {
        {type = "label", get = function() return headerLabel end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "selectfont",
            name = L["SETTING_FONT"],
            desc = L["SETTING_FONT_DESC"],
            get = function() return private.profile.components[componentKey].keybind_font.font_face end,
            set = function(_, _, value)
                private.profile.components[componentKey].keybind_font.font_face = value
                refreshFn()
            end,
            disableif = disableWhenOff,
        },

        {
            type = "range",
            name = L["SETTING_FONT_SIZE"],
            desc = L["SETTING_FONT_SIZE_DESC"],
            min = 6,
            max = maxSize,
            step = 1,
            get = function() return private.profile.components[componentKey].keybind_font.font_size end,
            set = function(_, _, value)
                private.profile.components[componentKey].keybind_font.font_size = value
                refreshFn()
            end,
            disableif = disableWhenOff,
        },

        {
            type = "selectoutline",
            name = L["SETTING_FONT_OUTLINE"],
            desc = L["SETTING_FONT_OUTLINE_DESC"],
            get = function() return private.profile.components[componentKey].keybind_font.font_flags end,
            set = function(_, _, value)
                private.profile.components[componentKey].keybind_font.font_flags = value
                if value ~= "" and value ~= "NONE" then
                    private.profile.components[componentKey].keybind_font.shadow_color = {0, 0, 0, 1}
                    private.profile.components[componentKey].keybind_font.shadow_offset_x = 1
                    private.profile.components[componentKey].keybind_font.shadow_offset_y = -1
                end
                refreshFn()
            end,
            disableif = disableWhenOff,
        },

        {
            type = "color",
            name = L["SETTING_FONT_COLOR"],
            desc = L["SETTING_FONT_COLOR_DESC"],
            boxfirst = true,
            get = function()
                local c = private.profile.components[componentKey].keybind_font.font_color or {1, 1, 1, 1}
                return private.Util.Color(c)
            end,
            set = function(_, r, g, b, a)
                private.profile.components[componentKey].keybind_font.font_color = {r, g, b, a}
                refreshFn()
            end,
            disableif = disableWhenOff,
        },

        {
            type = "color",
            name = L["SETTING_FONT_SHADOW_COLOR"],
            desc = L["SETTING_FONT_SHADOW_COLOR_DESC"],
            boxfirst = true,
            get = function()
                local c = private.profile.components[componentKey].keybind_font.shadow_color or {0, 0, 0, 1}
                return private.Util.Color(c)
            end,
            set = function(_, r, g, b, a)
                private.profile.components[componentKey].keybind_font.shadow_color = {r, g, b, a}
                refreshFn()
            end,
            disableif = function()
                if disableWhenOff() then return true end
                local flags = private.profile.components[componentKey].keybind_font.font_flags
                return flags ~= "" and flags ~= "NONE"
            end,
        },

        {
            type = "range",
            name = L["SETTING_FONT_SHADOW_OFFSET_X"],
            desc = L["SETTING_FONT_SHADOW_OFFSET_X_DESC"],
            min = -5,
            max = 5,
            step = 1,
            get = function() return private.profile.components[componentKey].keybind_font.shadow_offset_x or 1 end,
            set = function(_, _, value)
                private.profile.components[componentKey].keybind_font.shadow_offset_x = value
                refreshFn()
            end,
            disableif = function()
                if disableWhenOff() then return true end
                local flags = private.profile.components[componentKey].keybind_font.font_flags
                return flags ~= "" and flags ~= "NONE"
            end,
        },

        {
            type = "range",
            name = L["SETTING_FONT_SHADOW_OFFSET_Y"],
            desc = L["SETTING_FONT_SHADOW_OFFSET_Y_DESC"],
            min = -5,
            max = 5,
            step = 1,
            get = function() return private.profile.components[componentKey].keybind_font.shadow_offset_y or -1 end,
            set = function(_, _, value)
                private.profile.components[componentKey].keybind_font.shadow_offset_y = value
                refreshFn()
            end,
            disableif = function()
                if disableWhenOff() then return true end
                local flags = private.profile.components[componentKey].keybind_font.font_flags
                return flags ~= "" and flags ~= "NONE"
            end,
        },
    }

    for _, w in ipairs(fontPositionWidgets(componentKey, "keybind_font", refreshFn, disableWhenOff)) do
        widgets[#widgets + 1] = w
    end

    return widgets
end

---Append all entries from a widget array into a target options table.
---@param target table  the column options table to append to
---@param widgets table[]  array of widget definitions from fontGroupWidgets
local function appendWidgets(target, widgets)
    for _, w in ipairs(widgets) do
        target[#target + 1] = w
    end
end

-- ============================================================================
-- Shared data tables mirrored from EditMode.lua for the Trackers tab.
-- These drive per-component widget visibility and slider bounds.
-- ============================================================================

---Width slider bounds per component.
---@type table<string, {widthMin:number, widthMax:number}>
local trackerWidthConfig = {
    CooldownTracker = {widthMin = 20, widthMax = 1000},
    BuffTracker = {widthMin = 20, widthMax = 1000},
    BuffTrackerBars = {widthMin = 100, widthMax = 1000},
    OutboundBuffTracker = {widthMin = 100, widthMax = 1000},
    UtilitiesTracker = {widthMin = 20, widthMax = 1000},
    PlayerCastBar = {widthMin = 20, widthMax = 1000},
    TargetCastBar = {widthMin = 20, widthMax = 1000},
    FocusCastBar = {widthMin = 20, widthMax = 1000},
    GlobalCooldown = {widthMin = 20, widthMax = 1000},
    PrimaryResources = {widthMin = 20, widthMax = 1000},
    PlayerHealthBar = {widthMin = 20, widthMax = 1000},
    SecondaryResources = {widthMin = 20, widthMax = 1000},
}

---Height slider bounds per component.
---@type table<string, {heightMin:number, heightMax:number}>
local trackerHeightConfig = {
    CooldownTracker = {heightMin = 25, heightMax = 600},
    BuffTracker = {heightMin = 25, heightMax = 600},
    BuffTrackerBars = {heightMin = 25, heightMax = 300},
    OutboundBuffTracker = {heightMin = 25, heightMax = 300},
    UtilitiesTracker = {heightMin = 25, heightMax = 600},
    PlayerCastBar = {heightMin = 5, heightMax = 50},
    TargetCastBar = {heightMin = 5, heightMax = 50},
    FocusCastBar = {heightMin = 5, heightMax = 50},
    GlobalCooldown = {heightMin = 3, heightMax = 50},
    PrimaryResources = {heightMin = 5, heightMax = 50},
    PlayerHealthBar = {heightMin = 5, heightMax = 50},
    SecondaryResources = {heightMin = 5, heightMax = 50},
}

---Components whose frame height is driven by their icon layout.
---@type table<string, boolean>
local trackerViewerComponents = {
    CooldownTracker = true,
    BuffTracker = true,
    UtilitiesTracker = true,
}

---Components whose frame dimensions are driven by bar layout.
---@type table<string, boolean>
local trackerBarComponents = {
    BuffTrackerBars = true,
    OutboundBuffTracker = true,
}

---Components that support the Auto-Hide setting.
---@type table<string, boolean>
local trackerAutoHideComponents = {
    PrimaryResources = true,
    ConsumableTracker = true,
}

---Width % slider bounds for components that support relative sizing.
---@type table<string, {min:number, max:number}>
local trackerWidthPctConfig = {
    PlayerCastBar = {min = 25, max = 200},
    TargetCastBar = {min = 25, max = 200},
    FocusCastBar = {min = 25, max = 200},
    GlobalCooldown = {min = 25, max = 200},
    PrimaryResources = {min = 50, max = 200},
    PlayerHealthBar = {min = 50, max = 200},
    SecondaryResources = {min = 50, max = 200},
    BuffTracker = {min = 25, max = 200},
    UtilitiesTracker = {min = 25, max = 200},
    OutboundBuffTracker = {min = 25, max = 200},
    BuffTrackerBars = {min = 25, max = 200},
}

---Human-readable display names shown in the Trackers tab sidebar.
---@type table<string, string>
local trackerDisplayNames = {
    CooldownTracker = L["COMP_COOLDOWN_TRACKER"],
    TrinketTracker = L["COMP_TRINKET_TRACKER"],
    RacialTracker = L["COMP_RACIAL_TRACKER"],
    ConsumableTracker = L["COMP_CONSUMABLE_TRACKER"],
    ConsumableBuffTracker = L["COMP_CONSUMABLE_BUFF_TRACKER"],
    RaidBuffTracker = L["COMP_RAID_BUFF_TRACKER"],
    OutboundBuffTracker = L["COMP_OUTBOUND_BUFF_TRACKER"],
    BuffTracker = L["COMP_BUFF_TRACKER"],
    BuffTrackerBars = L["COMP_BUFF_TRACKER_BARS"],
    UtilitiesTracker = L["COMP_UTILITIES_TRACKER"],
    PlayerCastBar = L["COMP_PLAYER_CAST_BAR"],
    TargetCastBar = L["COMP_TARGET_CAST_BAR"],
    FocusCastBar = L["COMP_FOCUS_CAST_BAR"],
    GlobalCooldown = L["COMP_GLOBAL_COOLDOWN"],
    PrimaryResources = L["COMP_PRIMARY_RESOURCES"],
    PlayerHealthBar = L["COMP_PLAYER_HEALTH_BAR"],
    SecondaryResources = L["COMP_SECONDARY_RESOURCES"],
}

---Resolve a human-readable display name for any component (including additional frames).
---@param compName string
---@return string
local function resolveDisplayName(compName)
    local cached = trackerDisplayNames[compName]
    if cached then return cached end
    local comp = private.ComponentManager.GetComponent(compName)
    if comp then
        local s = comp.GetSettings and comp.GetSettings()
        if s and s.name then return s.name end
    end
    return compName
end

-- ============================================================================
-- Shared widget builder functions for the Trackers tab.
-- Each returns an array of DF BuildMenu widget definitions.
-- ============================================================================

---Build the anchor-parent dropdown values (mirrors EditMode.lua anchorParentValues).
---@param componentName string
---@return table[]
local function buildAnchorParentValues(componentName)
    local values = {{label = L["ANCHOR_NONE"], value = "none"}}
    -- Additional frames can follow the mouse cursor as an anchor mode.
    local comp = private.ComponentManager.GetComponent(componentName)
    local compSettings = comp and comp.GetSettings and comp.GetSettings()
    if compSettings and compSettings.frame_type then
        values[#values + 1] = {label = L["ANCHOR_CURSOR"], value = "cursor"}
    end
    local iAmSecure = private.Anchor.secureClickComponents[componentName]
    for _, other in ipairs(private.ComponentManager.GetAllComponents()) do
        local otherName = other.GetComponentName()
        if otherName ~= componentName and not private.Anchor.nonAnchorable[otherName] then
            -- Prevent cross-chain anchoring between secure and non-secure components.
            local otherSettings = other.GetSettings and other.GetSettings()
            local otherCursorFollow = otherSettings and otherSettings.anchor_profile
                and otherSettings.anchor_profile.anchor_parent == "cursor"
            local otherSecure = private.Anchor.secureClickComponents[otherName]
            local crossChain = (iAmSecure and not otherSecure) or (not iAmSecure and otherSecure)
            if not otherCursorFollow and not crossChain then
                values[#values + 1] = {
                    label = resolveDisplayName(otherName),
                    value = otherName,
                }
            end
        end
    end
    for frameKey, info in pairs(private.externalAnchors) do
        values[#values + 1] = {
            label = info.displayName,
            value = frameKey,
        }
    end
    return values
end

local anchorSideValues = {
    {label = L["ANCHOR_BOTTOM"], value = "bottom"},
    {label = L["ANCHOR_TOP"], value = "top"},
    {label = L["ANCHOR_LEFT"], value = "left"},
    {label = L["ANCHOR_RIGHT"], value = "right"},
    {label = L["ANCHOR_TOPLEFT"], value = "topleft"},
    {label = L["ANCHOR_TOPRIGHT"], value = "topright"},
    {label = L["ANCHOR_BOTTOMLEFT"], value = "bottomleft"},
    {label = L["ANCHOR_BOTTOMRIGHT"], value = "bottomright"},
}

local anchorPointValues = {
    {label = L["ANCHOR_CENTER"], value = "CENTER"},
    {label = L["ANCHOR_TOP"], value = "TOP"},
    {label = L["ANCHOR_BOTTOM"], value = "BOTTOM"},
    {label = L["ANCHOR_LEFT"], value = "LEFT"},
    {label = L["ANCHOR_RIGHT"], value = "RIGHT"},
    {label = L["ANCHOR_TOPLEFT"], value = "TOPLEFT"},
    {label = L["ANCHOR_TOPRIGHT"], value = "TOPRIGHT"},
    {label = L["ANCHOR_BOTTOMLEFT"], value = "BOTTOMLEFT"},
    {label = L["ANCHOR_BOTTOMRIGHT"], value = "BOTTOMRIGHT"},
}

---Build enabled toggle + visibility dropdown widgets.
---@param componentName string
---@param component component
---@return table[]
local function buildEnabledVisibilityWidgets(componentName, component)
    local widgets = {
        {
            type = "toggle",
            name = L["SETTING_ENABLED"],
            desc = L["SETTING_ENABLED_DESC"],
            get = function() return component.GetSettings().enabled end,
            set = function(_, _, value)
                if value then
                    private.ComponentManager.EnableComponent(componentName)
                else
                    private.ComponentManager.DisableComponent(componentName)
                end
            end,
        },
    }

    -- Mirror toggle: route icons to CooldownTracker (right below enabled)
    if componentName == "TrinketTracker" then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_ROUTE_TRINKETS"],
            desc = L["SETTING_ROUTE_TRINKETS_DESC"],
            get = function()
                local ct = private.profile.components.CooldownTracker
                return ct and ct.route_trinkets or false
            end,
            set = function(_, _, value)
                local ct = private.profile.components.CooldownTracker
                if ct then
                    ct.route_trinkets = value
                    component.Refresh()
                    if private.CooldownTracker then private.CooldownTracker.Refresh() end
                    private.Anchor.Refresh()
                end
            end,
        }
    elseif componentName == "ConsumableTracker" then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_ROUTE_COMBAT_POTIONS"],
            desc = L["SETTING_ROUTE_COMBAT_POTIONS_DESC"],
            get = function()
                local ct = private.profile.components.CooldownTracker
                return ct and ct.route_combat_potions or false
            end,
            set = function(_, _, value)
                local ct = private.profile.components.CooldownTracker
                if ct then
                    ct.route_combat_potions = value
                    component.Refresh()
                    if private.CooldownTracker then private.CooldownTracker.Refresh() end
                    private.Anchor.Refresh()
                end
            end,
        }
    end

    widgets[#widgets + 1] = {
        type = "select",
        name = L["SETTING_VISIBILITY"],
        desc = L["SETTING_VISIBILITY_DESC"],
        get = function()
            local vis = component.GetSettings().visibility or "inherit"
            if vis == "hide_when_mounted" then return "auto"
            elseif vis == "only_in_combat" then return "always" end
            return vis
        end,
        set = function(_, _, value)
            component.GetSettings().visibility = value
            private.Anchor.InvalidateTargetRuleCache()
            private.ComponentManager.RefreshAllComponents()
            private.Anchor.Refresh()
        end,
        values = function()
            local onclick = function(_, _, value)
                component.GetSettings().visibility = value
                -- The rule scan skips a "hidden" component's rules.
                private.Anchor.InvalidateTargetRuleCache()
                private.ComponentManager.RefreshAllComponents()
                private.Anchor.Refresh()
            end
            return {
                {label = L["VISIBILITY_INHERIT"], value = "inherit", onclick = onclick},
                {label = L["VISIBILITY_ALWAYS"], value = "always", onclick = onclick},
                {label = L["VISIBILITY_AUTO"], value = "auto", onclick = onclick},
                {label = L["VISIBILITY_HIDDEN"], value = "hidden", onclick = onclick},
            }
        end,
    }
    widgets[#widgets + 1] = {
        type = "range",
        name = L["SETTING_OPACITY"],
        desc = L["SETTING_OPACITY_DESC"],
        min = 10,
        max = 100,
        step = 5,
        get = function() return math.floor((component.GetSettings().alpha or 1) * 100 + 0.5) end,
        set = function(_, _, value)
            component.GetSettings().alpha = value / 100
            private.ComponentManager.RefreshAllComponents()
            private.Anchor.Refresh()
        end,
    }
    widgets[#widgets + 1] = {
        type = "select",
        name = L["SETTING_FRAME_STRATA"],
        desc = L["SETTING_FRAME_STRATA_DESC"],
        get = function() return component.GetSettings().frame_strata or "inherit" end,
        set = function(_, _, value)
            component.GetSettings().frame_strata = (value == "inherit") and nil or value
            private.Anchor.Refresh()
        end,
        values = function()
            local onclick = function(_, _, value)
                component.GetSettings().frame_strata = (value == "inherit") and nil or value
                private.Anchor.Refresh()
            end
            return {
                {label = L["FRAME_STRATA_INHERIT"], value = "inherit", onclick = onclick},
                {label = "BACKGROUND", value = "BACKGROUND", onclick = onclick},
                {label = "LOW", value = "LOW", onclick = onclick},
                {label = "MEDIUM", value = "MEDIUM", onclick = onclick},
                {label = "HIGH", value = "HIGH", onclick = onclick},
                {label = "DIALOG", value = "DIALOG", onclick = onclick},
                {label = "FULLSCREEN", value = "FULLSCREEN", onclick = onclick},
                {label = "FULLSCREEN_DIALOG", value = "FULLSCREEN_DIALOG", onclick = onclick},
                {label = "TOOLTIP", value = "TOOLTIP", onclick = onclick},
            }
        end,
    }

    -- Visibility rule dropdowns: per-condition Off/Hide/Fade selects.
    local ruleConditions = {
        {key = "mounted", name = L["VISIBILITY_RULE_MOUNTED"], desc = L["VISIBILITY_RULE_MOUNTED_DESC"]},
        {key = "out_of_combat", name = L["VISIBILITY_RULE_OUT_OF_COMBAT"], desc = L["VISIBILITY_RULE_OUT_OF_COMBAT_DESC"]},
        {key = "no_target", name = L["VISIBILITY_RULE_NO_TARGET"], desc = L["VISIBILITY_RULE_NO_TARGET_DESC"]},
    }
    for _, cond in ipairs(ruleConditions) do
        local ruleOnclick = function(_, _, value)
            local settings = component.GetSettings()
            if not settings.visibility_rules then
                settings.visibility_rules = {fade_alpha = 30}
            end
            settings.visibility_rules[cond.key] = value == "off" and false or value
            private.Anchor.InvalidateTargetRuleCache()
            private.ComponentManager.RefreshAllComponents()
            private.Anchor.Refresh()
        end
        widgets[#widgets + 1] = {
            type = "select",
            name = cond.name,
            desc = cond.desc,
            get = function()
                local rules = component.GetSettings().visibility_rules
                return (rules and rules[cond.key]) or "off"
            end,
            set = function(_, _, value) ruleOnclick(nil, nil, value) end,
            values = function()
                return {
                    {label = L["VISIBILITY_RULE_OFF"], value = "off", onclick = ruleOnclick},
                    {label = L["VISIBILITY_RULE_HIDE"], value = "hide", onclick = ruleOnclick},
                    {label = L["VISIBILITY_RULE_FADE"], value = "fade", onclick = ruleOnclick},
                }
            end,
        }
    end

    -- Fade Opacity slider: controls transparency when a fade rule is active.
    widgets[#widgets + 1] = {
        type = "range",
        name = L["VISIBILITY_FADE_OPACITY"],
        desc = L["VISIBILITY_FADE_OPACITY_DESC"],
        min = 10,
        max = 90,
        step = 5,
        get = function()
            local rules = component.GetSettings().visibility_rules
            return (rules and rules.fade_alpha) or 30
        end,
        set = function(_, _, value)
            local settings = component.GetSettings()
            if not settings.visibility_rules then
                settings.visibility_rules = {fade_alpha = 30}
            end
            settings.visibility_rules.fade_alpha = value
            private.Anchor.Refresh()
        end,
        disableif = function()
            local rules = component.GetSettings().visibility_rules
            if not rules then return true end
            return rules.mounted ~= "fade" and rules.out_of_combat ~= "fade" and rules.no_target ~= "fade"
        end,
    }

    if trackerAutoHideComponents[componentName] then
        local autoHideKey = componentName == "ConsumableTracker"
            and "consumable_auto_hide" or "auto_hide"
        local autoHideDesc = componentName == "ConsumableTracker"
            and L["AUTO_HIDE_MANA_POTIONS_DESC"]
            or L["AUTO_HIDE_EDIT_DESC"]
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["AUTO_HIDE"],
            desc = autoHideDesc,
            get = function() return private.profile[autoHideKey] end,
            set = function(_, _, value)
                private.profile[autoHideKey] = value
                private.ComponentManager.RefreshAllComponents()
                private.Anchor.Refresh()
            end,
        }

        if componentName == "PrimaryResources" then
            widgets[#widgets + 1] = {
                type = "toggle",
                name = L["PALADIN_MANA_BAR"],
                desc = L["PALADIN_MANA_BAR_DESC"],
                get = function() return private.profile.paladin_mana_bar end,
                set = function(_, _, value)
                    private.profile.paladin_mana_bar = value
                    private.PrimaryResources.Refresh()
                    private.Anchor.OnComponentStateChange()
                end,
            }
            widgets[#widgets + 1] = {
                type = "toggle",
                name = L["EVOKER_MANA_BAR"],
                desc = L["EVOKER_MANA_BAR_DESC"],
                get = function() return private.profile.evoker_mana_bar end,
                set = function(_, _, value)
                    private.profile.evoker_mana_bar = value
                    private.PrimaryResources.Refresh()
                    private.Anchor.OnComponentStateChange()
                end,
            }
            widgets[#widgets + 1] = {
                type = "toggle",
                name = L["DRUID_MANA_BAR"],
                desc = L["DRUID_MANA_BAR_DESC"],
                get = function() return private.profile.druid_mana_bar end,
                set = function(_, _, value)
                    private.profile.druid_mana_bar = value
                    private.PrimaryResources.Refresh()
                    private.Anchor.OnComponentStateChange()
                end,
            }
            widgets[#widgets + 1] = {
                type = "toggle",
                name = L["SHAMAN_MANA_BAR"],
                desc = L["SHAMAN_MANA_BAR_DESC"],
                get = function() return private.profile.shaman_mana_bar end,
                set = function(_, _, value)
                    private.profile.shaman_mana_bar = value
                    private.PrimaryResources.Refresh()
                    private.Anchor.OnComponentStateChange()
                end,
            }
            widgets[#widgets + 1] = {
                type = "toggle",
                name = L["BALANCE_MANA_BAR"],
                desc = L["BALANCE_MANA_BAR_DESC"],
                get = function() return private.profile.balance_mana_bar end,
                set = function(_, _, value)
                    private.profile.balance_mana_bar = value
                    private.PrimaryResources.Refresh()
                    private.Anchor.OnComponentStateChange()
                end,
            }
            widgets[#widgets + 1] = {
                type = "toggle",
                name = L["PRIEST_MANA_BAR"],
                desc = L["PRIEST_MANA_BAR_DESC"],
                get = function() return private.profile.priest_mana_bar end,
                set = function(_, _, value)
                    private.profile.priest_mana_bar = value
                    private.PrimaryResources.Refresh()
                    private.Anchor.OnComponentStateChange()
                end,
            }
        end
    end

    return widgets
end

---Build tooltip section widgets (mode + anchor) prefixed with an orange header.
---Returns an empty table for components whose profile does not define tooltip_mode.
---@param component component
---@return table[]
local function buildTooltipWidgets(component)
    if component.GetSettings().tooltip_mode == nil then return {} end
    local widgets = {
        {type = "label", get = function() return L["SECTION_TOOLTIP"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},
    }
    widgets[#widgets + 1] = {
        type = "select",
        name = L["TOOLTIP_MODE"],
        desc = L["TOOLTIP_MODE_DESC"],
        get = function() return component.GetSettings().tooltip_mode or "off" end,
        set = function(_, _, value)
            component.GetSettings().tooltip_mode = value
            if private.Tooltip then private.Tooltip.RefreshAll() end
        end,
        values = function()
            local onclick = function(_, _, value)
                component.GetSettings().tooltip_mode = value
                if private.Tooltip then private.Tooltip.RefreshAll() end
            end
            return {
                {label = L["TOOLTIP_MODE_ALWAYS"], value = "always", onclick = onclick},
                {label = L["TOOLTIP_MODE_OUT_OF_COMBAT"], value = "out_of_combat", onclick = onclick},
                {label = L["TOOLTIP_MODE_OFF"], value = "off", onclick = onclick},
            }
        end,
    }
    widgets[#widgets + 1] = {
        type = "select",
        name = L["TOOLTIP_ANCHOR"],
        desc = L["TOOLTIP_ANCHOR_DESC"],
        get = function() return component.GetSettings().tooltip_anchor or "RIGHT" end,
        set = function(_, _, value)
            component.GetSettings().tooltip_anchor = value
            component.Refresh()
        end,
        values = function()
            local onclick = function(_, _, value)
                component.GetSettings().tooltip_anchor = value
                component.Refresh()
            end
            return {
                {label = L["TOOLTIP_ANCHOR_DEFAULT"], value = "DEFAULT", onclick = onclick},
                {label = L["TOOLTIP_ANCHOR_CURSOR"], value = "CURSOR", onclick = onclick},
                {label = L["TOOLTIP_ANCHOR_RIGHT"], value = "RIGHT", onclick = onclick},
                {label = L["TOOLTIP_ANCHOR_TOP"], value = "TOP", onclick = onclick},
            }
        end,
    }
    return widgets
end

---Build anchoring widgets (anchor frame, side, offsets, width mode, dimensions).
---@param componentName string
---@param component component
---@return table[]
local function buildAnchoringWidgets(componentName, component)
    local wc = trackerWidthConfig[componentName] or {widthMin = 20, widthMax = 1000}
    local hc = trackerHeightConfig[componentName] or {heightMin = 5, heightMax = 150}
    local wpc = trackerWidthPctConfig[componentName]
    local isViewerTracker = trackerViewerComponents[componentName]
    local isBarTracker = trackerBarComponents[componentName]
    local isTrinketTracker = componentName == "TrinketTracker"
    local isRacialTracker = componentName == "RacialTracker"
    local isConsumableTracker = componentName == "ConsumableTracker"
    local isConsumableBuffTracker = componentName == "ConsumableBuffTracker"
    local isRaidBuffTracker = componentName == "RaidBuffTracker"
    -- secureCLICK, not secure: only SecureActionButton chains cascade blocked
    -- ops, so only those two components are steered onto position_reference.
    -- The AuraContainer trackers ship real anchor_parent chains (Anchoring.lua).
    local isSecure = private.Anchor.secureClickComponents[componentName]

    local function isFreeMoving()
        if isSecure then
            local pr = component.GetSettings().anchor_profile.position_reference
            return not pr or pr == "none"
        end
        local ap = component.GetSettings().anchor_profile.anchor_parent
        return not ap or ap == "none"
    end

    ---Shared by the position_reference dropdown's `set` and its per-option
    ---`onclick`. A plain `type = "select"` runs only the onclick (patterns.md),
    ---so the two bodies must not be allowed to drift.
    local function applyPositionReference(value)
        if private.Anchor.WouldCreateCycle(componentName, value) then
            private.print(string.format(L["ANCHOR_CIRCULAR_ERROR"],
                resolveDisplayName(componentName), resolveDisplayName(value)))
            return
        end
        local settings = component.GetSettings()
        local ap = settings.anchor_profile
        local wasFollowing = ap.position_reference and ap.position_reference ~= "none"
        if value == "none" and wasFollowing then
            local f = component.GetFrame()
            if f and f:GetLeft() then
                local scale = f:GetScale()
                private.EditMode.CapturePositionForFreeMove(
                    componentName, settings, ap,
                    f:GetLeft() * scale, f:GetRight() * scale,
                    f:GetTop() * scale, f:GetBottom() * scale, scale)
            end
        end
        ap.position_reference = value
        private.Anchor.Refresh()
    end

    ---Shared by the Anchor Frame dropdown's `set` and `onclick`, for the same
    ---reason. Leaving an anchor for "none" captures the on-screen position, as
    ---Edit Mode's twin does, so the frame stays put instead of jumping to stale
    ---free-move offsets.
    local function applyAnchorParent(value)
        if private.Anchor.WouldCreateCycle(componentName, value) then
            local selfName = resolveDisplayName(componentName)
            local targetName = resolveDisplayName(value)
            private.print(string.format(L["ANCHOR_CIRCULAR_ERROR"], selfName, targetName))
            return
        end
        local settings = component.GetSettings()
        local ap = settings.anchor_profile
        if value == "none" and ap.anchor_parent ~= "none" then
            local f = component.GetFrame()
            if f and f:GetLeft() then
                local scale = f:GetScale()
                private.EditMode.CapturePositionForFreeMove(
                    componentName, settings, ap,
                    f:GetLeft() * scale, f:GetRight() * scale,
                    f:GetTop() * scale, f:GetBottom() * scale, scale)
            end
        end
        ap.anchor_parent = value
        private.Anchor.RebuildAnchorTree()
        private.Anchor.Refresh()
    end

    ---Shared by the Anchor Point / Frame Point `set` and `onclick`. Recomputes
    ---the offsets so the frame stays in place; a hand-picked Frame Point is
    ---marked so the Trinket/Consumable alignment sync does not overwrite it.
    local function applyFreeMovePoint(key, value)
        local ap = component.GetSettings().anchor_profile
        private.EditMode.SetFreeMovePoint(component.GetFrame(), ap, key, value)
        if key == "frame_point" then ap.frame_point_manual = true end
        private.Anchor.Refresh()
    end

    local widgets = {
        {type = "label", get = function() return L["SECTION_ANCHORING"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        isSecure and {
            type = "select",
            name = L["SETTING_POSITION_REFERENCE"],
            desc = L["SETTING_POSITION_REFERENCE_DESC"],
            get = function() return component.GetSettings().anchor_profile.position_reference or "none" end,
            set = function(_, _, value) applyPositionReference(value) end,
            values = function()
                local onclick = function(_, _, value) applyPositionReference(value) end
                local vals = {{label = L["ANCHOR_NONE"], value = "none", onclick = onclick}}
                for _, other in ipairs(private.ComponentManager.GetAllComponents()) do
                    local otherName = other.GetComponentName()
                    if otherName ~= componentName then
                        vals[#vals + 1] = {label = resolveDisplayName(otherName), value = otherName, onclick = onclick}
                    end
                end
                return vals
            end,
        } or {
            type = "select",
            name = L["SETTING_ANCHOR_FRAME"],
            desc = L["SETTING_ANCHOR_FRAME_DESC"],
            get = function() return component.GetSettings().anchor_profile.anchor_parent end,
            set = function(_, _, value) applyAnchorParent(value) end,
            values = function()
                local onclick = function(_, _, value) applyAnchorParent(value) end
                local vals = buildAnchorParentValues(componentName)
                for _, v in ipairs(vals) do
                    v.onclick = onclick
                end
                return vals
            end,
        },

        {
            type = "select",
            name = L["SETTING_ANCHOR_POINT"],
            desc = L["SETTING_ANCHOR_POINT_DESC"],
            get = function()
                return string.upper(component.GetSettings().anchor_profile.parent_point or "CENTER")
            end,
            set = function(_, _, value) applyFreeMovePoint("parent_point", value) end,
            values = function()
                local onclick = function(_, _, value) applyFreeMovePoint("parent_point", value) end
                local vals = {}
                for i, v in ipairs(anchorPointValues) do
                    vals[i] = {label = v.label, value = v.value, onclick = onclick}
                end
                return vals
            end,
            disableif = function() return not isFreeMoving() end,
        },

        {
            type = "select",
            name = L["SETTING_FRAME_POINT"],
            desc = L["SETTING_FRAME_POINT_DESC"],
            get = function()
                return string.upper(component.GetSettings().anchor_profile.frame_point or "TOP")
            end,
            set = function(_, _, value) applyFreeMovePoint("frame_point", value) end,
            values = function()
                local onclick = function(_, _, value) applyFreeMovePoint("frame_point", value) end
                local vals = {}
                for i, v in ipairs(anchorPointValues) do
                    vals[i] = {label = v.label, value = v.value, onclick = onclick}
                end
                return vals
            end,
            disableif = function() return not isFreeMoving() end,
        },

        {
            type = "range",
            name = L["SETTING_FREE_OFFSET_X"],
            desc = L["SETTING_FREE_OFFSET_X_DESC"],
            min = -3000,
            max = 3000,
            step = 1,
            get = function() return component.GetSettings().anchor_profile.xoff or 0 end,
            set = function(_, _, value)
                component.GetSettings().anchor_profile.xoff = value
                private.Anchor.Refresh()
            end,
            disableif = function() return not isFreeMoving() end,
        },

        {
            type = "range",
            name = L["SETTING_FREE_OFFSET_Y"],
            desc = L["SETTING_FREE_OFFSET_Y_DESC"],
            min = -3000,
            max = 3000,
            step = 1,
            get = function() return component.GetSettings().anchor_profile.yoff or 0 end,
            set = function(_, _, value)
                component.GetSettings().anchor_profile.yoff = value
                private.Anchor.Refresh()
            end,
            disableif = function() return not isFreeMoving() end,
        },

        isSecure and {
            type = "select",
            name = L["SETTING_POSITION_SIDE"],
            desc = L["SETTING_POSITION_SIDE_DESC"],
            get = function() return component.GetSettings().anchor_profile.position_side or "bottom" end,
            set = function(_, _, value)
                component.GetSettings().anchor_profile.position_side = value
                private.Anchor.Refresh()
            end,
            values = function()
                local onclick = function(_, _, value)
                    component.GetSettings().anchor_profile.position_side = value
                    private.Anchor.Refresh()
                end
                return {
                    {label = L["ANCHOR_BOTTOM"], value = "bottom", onclick = onclick},
                    {label = L["ANCHOR_TOP"], value = "top", onclick = onclick},
                    {label = L["ANCHOR_LEFT"], value = "left", onclick = onclick},
                    {label = L["ANCHOR_RIGHT"], value = "right", onclick = onclick},
                }
            end,
            disableif = isFreeMoving,
        } or {
            type = "select",
            name = L["SETTING_ANCHOR_SIDE"],
            desc = L["SETTING_ANCHOR_SIDE_DESC"],
            get = function() return component.GetSettings().anchor_profile.anchor_side end,
            set = function(_, _, value)
                component.GetSettings().anchor_profile.anchor_side = value
                private.Anchor.Refresh()
            end,
            values = function()
                local onclick = function(_, _, value)
                    component.GetSettings().anchor_profile.anchor_side = value
                    private.Anchor.Refresh()
                end
                local vals = {}
                for i, v in ipairs(anchorSideValues) do
                    vals[i] = {label = v.label, value = v.value, onclick = onclick}
                end
                return vals
            end,
            disableif = isFreeMoving,
        },

        isSecure and {
            type = "range",
            name = L["SETTING_POSITION_OFFSET"],
            desc = L["SETTING_POSITION_OFFSET_DESC"],
            min = 0,
            max = 200,
            step = 1,
            get = function() return component.GetSettings().anchor_profile.position_offset or 30 end,
            set = function(_, _, value)
                component.GetSettings().anchor_profile.position_offset = value
                private.Anchor.Refresh()
            end,
            disableif = isFreeMoving,
        } or {
            type = "range",
            name = L["SETTING_ANCHOR_OFFSET_X"],
            desc = L["SETTING_ANCHOR_OFFSET_X_DESC"],
            min = -1000,
            max = 1000,
            step = 1,
            get = function() return component.GetSettings().anchor_profile.anchor_offset_x or 0 end,
            set = function(_, _, value)
                component.GetSettings().anchor_profile.anchor_offset_x = value
                private.Anchor.Refresh()
            end,
            disableif = isFreeMoving,
        },

        not isSecure and {
            type = "range",
            name = L["SETTING_ANCHOR_OFFSET_Y"],
            desc = L["SETTING_ANCHOR_OFFSET_Y_DESC"],
            min = -1000,
            max = 1000,
            step = 1,
            get = function() return component.GetSettings().anchor_profile.anchor_offset_y or 0 end,
            set = function(_, _, value)
                component.GetSettings().anchor_profile.anchor_offset_y = value
                private.Anchor.Refresh()
            end,
            disableif = isFreeMoving,
        } or nil,
    }

    if wpc then
        widgets[#widgets + 1] = {
            type = "select",
            name = L["SETTING_WIDTH_MODE"],
            desc = L["SETTING_WIDTH_MODE_DESC"],
            get = function() return component.GetSettings().anchor_profile.anchor_width_mode or "percent" end,
            set = function(_, _, value)
                component.GetSettings().anchor_profile.anchor_width_mode = value
                private.Anchor.Refresh()
                if isViewerTracker then
                    component.Refresh()
                end
            end,
            values = function()
                local onclick = function(_, _, value)
                    component.GetSettings().anchor_profile.anchor_width_mode = value
                    private.Anchor.Refresh()
                    if isViewerTracker then
                        component.Refresh()
                    end
                end
                return {
                    {label = L["WIDTH_MODE_PERCENT"], value = "percent", onclick = onclick},
                    {label = L["WIDTH_MODE_ABSOLUTE"], value = "absolute", onclick = onclick},
                }
            end,
            disableif = isFreeMoving,
        }

        widgets[#widgets + 1] = {
            type = "range",
            name = L["SETTING_WIDTH_PCT"],
            desc = L["SETTING_WIDTH_PCT_DESC"],
            min = wpc.min,
            max = wpc.max,
            step = 1,
            get = function() return component.GetSettings().anchor_profile.anchor_width_pct or 100 end,
            set = function(_, _, value)
                component.GetSettings().anchor_profile.anchor_width_pct = value
                private.Anchor.Refresh()
                if isViewerTracker then
                    component.Refresh()
                end
            end,
            disableif = function()
                local ap = component.GetSettings().anchor_profile
                return (not ap.anchor_parent or ap.anchor_parent == "none")
                    or (ap.anchor_width_mode or "percent") == "absolute"
            end,
        }
    end

    -- Size settings (skip for Trinket/Consumable/Bar trackers — they have dedicated layout sections;
    -- the two secure trackers size to their content and never read width/height). Same list as
    -- EditMode's size block.
    if not isTrinketTracker and not isRacialTracker and not isConsumableTracker
        and not isConsumableBuffTracker and not isRaidBuffTracker and not isBarTracker then
        widgets[#widgets + 1] = {
            type = "range",
            name = L["SETTING_WIDTH"],
            desc = L["SETTING_WIDTH_DESC"],
            min = wc.widthMin,
            max = wc.widthMax,
            step = 1,
            get = function() return component.GetSettings().width end,
            set = function(_, _, value)
                component.GetSettings().width = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            disableif = (wpc or isViewerTracker) and function()
                local settings = component.GetSettings()
                -- Mirrors this function's own isFreeMoving above: an ABSENT
                -- anchor_parent is free-moving, so a bare `~= "none"` read it as
                -- anchored and disabled this slider on a profile that has none.
                local ap = settings.anchor_profile.anchor_parent
                local isAnchored = ap ~= nil and ap ~= "none"
                local isPercentMode = (settings.anchor_profile.anchor_width_mode or "percent") == "percent"
                return (wpc ~= nil and isAnchored and isPercentMode)
                    or (isViewerTracker and isAnchored and isPercentMode and settings.frame_size_mode == "max_per_row")
            end or nil,
        }

        if not isViewerTracker and component.GetSettings().height ~= nil then
            widgets[#widgets + 1] = {
                type = "range",
                name = L["SETTING_HEIGHT"],
                desc = L["SETTING_HEIGHT_DESC"],
                min = hc.heightMin,
                max = hc.heightMax,
                step = 1,
                get = function() return component.GetSettings().height end,
                set = function(_, _, value)
                    component.GetSettings().height = value
                    component.Refresh()
                    private.Anchor.Refresh()
                end,
            }
        end

        -- Extra-row height. Only SecondaryResources carries the key, so its
        -- presence is the gate — same idiom as the height slider above.
        if component.GetSettings().extra_row_height ~= nil then
            widgets[#widgets + 1] = {
                type = "range",
                name = L["SETTING_EXTRA_ROW_HEIGHT"],
                desc = L["SETTING_EXTRA_ROW_HEIGHT_DESC"],
                min = hc.heightMin,
                max = hc.heightMax,
                step = 1,
                get = function() return component.GetSettings().extra_row_height end,
                set = function(_, _, value)
                    component.GetSettings().extra_row_height = value
                    component.Refresh()
                    private.Anchor.Refresh()
                end,
            }
        end

        -- Height slider for viewer tracker components: shown only in vertical
        -- fixed-height modes where settings.height acts as the constraint axis.
        if isViewerTracker then
            widgets[#widgets + 1] = {
                type = "range",
                name = L["SETTING_HEIGHT"],
                desc = L["SETTING_HEIGHT_DESC"],
                min = hc.heightMin,
                max = hc.heightMax,
                step = 1,
                get = function() return component.GetSettings().height end,
                set = function(_, _, value)
                    component.GetSettings().height = value
                    component.Refresh()
                    private.Anchor.Refresh()
                end,
                disableif = function()
                    return (component.GetSettings().layout_direction or "horizontal") ~= "vertical"
                end,
            }
        end

        -- Orientation dropdown for bar components that support vertical fill
        if component.GetSettings().orientation ~= nil then
            widgets[#widgets + 1] = {
                type = "select",
                name = L["SETTING_ORIENTATION"],
                desc = L["SETTING_ORIENTATION_DESC"],
                get = function() return component.GetSettings().orientation or "horizontal" end,
                values = function()
                    local onclick = function(_, _, value)
                        component.GetSettings().orientation = value
                        -- fontsDirty gate: value/cast text rotation lives in the
                        -- font pass, which Refresh only runs when fontsDirty is set.
                        private.fontsDirty = true
                        component.Refresh()
                        private.fontsDirty = false
                        private.Anchor.Refresh()
                    end
                    return {
                        {label = L["SETTING_ORIENTATION_HORIZONTAL"], value = "horizontal", onclick = onclick},
                        {label = L["SETTING_ORIENTATION_VERTICAL"], value = "vertical", onclick = onclick},
                    }
                end,
            }
        end

        -- Bar spacing slider for components with segmented bars
        if component.GetSettings().bar_spacing ~= nil then
            widgets[#widgets + 1] = {
                type = "range",
                name = L["SETTING_BAR_SPACING"],
                desc = L["SETTING_BAR_SPACING_DESC"],
                min = -5,
                max = 20,
                step = 1,
                get = function() return component.GetSettings().bar_spacing end,
                set = function(_, _, value)
                    component.GetSettings().bar_spacing = value
                    component.Refresh()
                    private.Anchor.Refresh()
                end,
            }
        end
    end

    return widgets
end

---Build icon layout widgets for viewer tracker components.
---@param componentName string
---@param component component
---@return table[]
local function buildViewerTrackerLayoutWidgets(componentName, component)
    local widgets = {
        {type = "label", get = function() return L["SECTION_ICON_LAYOUT"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "select",
            name = L["SETTING_LAYOUT_DIRECTION"],
            desc = L["SETTING_LAYOUT_DIRECTION_DESC"],
            get = function() return component.GetSettings().layout_direction or "horizontal" end,
            set = function(_, _, value)
                local s = component.GetSettings()
                s.layout_direction = value
                s.layout_alignment = "center"
                if value == "vertical" then
                    if s.overflow_direction ~= "left" and s.overflow_direction ~= "right" then
                        s.overflow_direction = "right"
                    end
                else
                    if s.overflow_direction ~= "top" and s.overflow_direction ~= "bottom" then
                        s.overflow_direction = "top"
                    end
                end
                component.Refresh()
                private.Anchor.Refresh()
                if trackersLeftCol and trackersLeftCol.RefreshOptions then trackersLeftCol:RefreshOptions() end
            end,
            values = function()
                local onclick = function(_, _, value)
                    local s = component.GetSettings()
                    s.layout_direction = value
                    s.layout_alignment = "center"
                    if value == "vertical" then
                        if s.overflow_direction ~= "left" and s.overflow_direction ~= "right" then
                            s.overflow_direction = "right"
                        end
                    else
                        if s.overflow_direction ~= "top" and s.overflow_direction ~= "bottom" then
                            s.overflow_direction = "top"
                        end
                    end
                    component.Refresh()
                    private.Anchor.Refresh()
                    if trackersLeftCol and trackersLeftCol.RefreshOptions then trackersLeftCol:RefreshOptions() end
                end
                return {
                    {label = L["LAYOUT_DIRECTION_HORIZONTAL"], value = "horizontal", onclick = onclick},
                    {label = L["LAYOUT_DIRECTION_VERTICAL"], value = "vertical", onclick = onclick},
                }
            end,
        },

        {
            type = "select",
            name = L["SETTING_LAYOUT_ALIGNMENT"],
            desc = L["SETTING_LAYOUT_ALIGNMENT_DESC"],
            get = function() return component.GetSettings().layout_alignment or "center" end,
            set = function(_, _, value)
                component.GetSettings().layout_alignment = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = function()
                local onclick = function(_, _, value)
                    component.GetSettings().layout_alignment = value
                    component.Refresh()
                    private.Anchor.Refresh()
                end
                if (component.GetSettings().layout_direction or "horizontal") == "vertical" then
                    return {
                        {label = L["LAYOUT_ALIGNMENT_TOP"], value = "top", onclick = onclick},
                        {label = L["LAYOUT_ALIGNMENT_CENTER"], value = "center", onclick = onclick},
                        {label = L["LAYOUT_ALIGNMENT_BOTTOM"], value = "bottom", onclick = onclick},
                    }
                end
                return {
                    {label = L["LAYOUT_ALIGNMENT_LEFT"], value = "left", onclick = onclick},
                    {label = L["LAYOUT_ALIGNMENT_CENTER"], value = "center", onclick = onclick},
                    {label = L["LAYOUT_ALIGNMENT_RIGHT"], value = "right", onclick = onclick},
                }
            end,
        },

        {
            type = "select",
            name = L["SETTING_SIZE_MODE"],
            desc = L["SETTING_SIZE_MODE_DESC"],
            get = function() return component.GetSettings().frame_size_mode end,
            set = function(_, _, value)
                component.GetSettings().frame_size_mode = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = function()
                local onclick = function(_, _, value)
                    component.GetSettings().frame_size_mode = value
                    component.Refresh()
                    private.Anchor.Refresh()
                end
                local isVertical = (component.GetSettings().layout_direction or "horizontal") == "vertical"
                return {
                    {label = L["SETTING_MAX_WIDTH"], value = "max_width", onclick = onclick},
                    {label = L["SETTING_MAX_PER_ROW"], value = "max_per_row", onclick = onclick},
                    {label = isVertical and L["SETTING_FIXED_HEIGHT"] or L["SETTING_FIXED_WIDTH"], value = "fixed_width", onclick = onclick},
                    {label = isVertical and L["SETTING_FIXED_HEIGHT_SPREAD"] or L["SETTING_FIXED_WIDTH_SPREAD"], value = "fixed_width_spread", onclick = onclick},
                    {label = isVertical and L["SETTING_FIXED_HEIGHT_STRETCH"] or L["SETTING_FIXED_WIDTH_STRETCH"], value = "fixed_width_stretch", onclick = onclick},
                }
            end,
        },

        {
            type = "range",
            name = L["SETTING_MAX_PER_ROW"],
            desc = L["SETTING_MAX_PER_ROW_DESC"],
            min = 1,
            max = 20,
            step = 1,
            get = function() return component.GetSettings().max_icons_per_row end,
            set = function(_, _, value)
                component.GetSettings().max_icons_per_row = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            disableif = function()
                local s = component.GetSettings()
                local m = s.frame_size_mode or "max_width"
                return m ~= "max_per_row"
            end,
        },

        {
            type = "range",
            name = L["SETTING_MIN_WIDTH"],
            desc = L["SETTING_MIN_WIDTH_DESC"],
            min = 0,
            max = 1000,
            step = 1,
            get = function() return component.GetSettings().min_width or 0 end,
            set = function(_, _, value)
                component.GetSettings().min_width = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            disableif = function()
                local s = component.GetSettings()
                if (s.layout_direction or "horizontal") == "vertical" then return false end
                -- Mirrors computeGridGeometry's isContentWidth: min_width can
                -- only floor a width the frame derived from its icons, so it is
                -- dead in the fixed_width* modes (which take the container
                -- width outright) and in a content mode with no icon_size.
                -- Gating on max_per_row alone greyed the slider out in the
                -- DEFAULT mode, where it is in fact shaping the frame.
                local m = s.frame_size_mode or "max_width"
                if m == "fixed_width" or m == "fixed_width_spread"
                    or m == "fixed_width_stretch" then
                    return true
                end
                return not (m == "max_per_row" or (s.icon_size and s.icon_size > 0))
            end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_SIZE"],
            desc = L["SETTING_ICON_SIZE_DESC"],
            min = 8,
            max = 80,
            step = 1,
            get = function() return component.GetSettings().icon_size end,
            set = function(_, _, value)
                component.GetSettings().icon_size = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            disableif = function()
                return component.GetSettings().frame_size_mode == "fixed_width"
            end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_HEIGHT"],
            desc = L["SETTING_ICON_HEIGHT_DESC"],
            min = 0,
            max = 80,
            step = 1,
            get = function() return component.GetSettings().icon_height or 0 end,
            set = function(_, _, value)
                -- Snap values between 0 and the icon_size min (8) back to 8.
                if value > 0 and value < 8 then value = 8 end
                component.GetSettings().icon_height = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            disableif = function()
                return component.GetSettings().frame_size_mode == "fixed_width_stretch"
            end,
        },

        {
            type = "range",
            name = L["SETTING_OVERFLOW_ICON_SIZE"],
            desc = L["SETTING_OVERFLOW_ICON_SIZE_DESC"],
            min = 8,
            max = 80,
            step = 1,
            get = function() return component.GetSettings().overflow_icon_size end,
            set = function(_, _, value)
                component.GetSettings().overflow_icon_size = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            disableif = function()
                local m = component.GetSettings().frame_size_mode or "max_width"
                return m == "fixed_width" or m == "fixed_width_spread" or m == "fixed_width_stretch"
            end,
            -- Which icons landed on an overflow row is only knowable under slots.
            hidden = component.IsUsingSlots ~= nil and not component.IsUsingSlots(),
        },

        {
            type = "select",
            name = L["SETTING_OVERFLOW_DIRECTION"],
            desc = L["SETTING_OVERFLOW_DIRECTION_DESC"],
            get = function() return component.GetSettings().overflow_direction end,
            set = function(_, _, value)
                component.GetSettings().overflow_direction = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = function()
                local onclick = function(_, _, value)
                    component.GetSettings().overflow_direction = value
                    component.Refresh()
                    private.Anchor.Refresh()
                end
                if (component.GetSettings().layout_direction or "horizontal") == "vertical" then
                    return {
                        {label = L["OVERFLOW_LEFT"], value = "left", onclick = onclick},
                        {label = L["OVERFLOW_RIGHT"], value = "right", onclick = onclick},
                    }
                end
                return {
                    {label = L["ANCHOR_TOP"], value = "top", onclick = onclick},
                    {label = L["ANCHOR_BOTTOM"], value = "bottom", onclick = onclick},
                }
            end,
            disableif = function()
                local s = component.GetSettings()
                local m = s.frame_size_mode or "max_width"
                return m == "fixed_width" or m == "fixed_width_spread" or m == "fixed_width_stretch"
            end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_OFFSET"],
            desc = L["SETTING_ICON_OFFSET_DESC"],
            min = -5,
            max = 20,
            step = 1,
            get = function() return component.GetSettings().icon_offset end,
            set = function(_, _, value)
                component.GetSettings().icon_offset = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
        },
    }

    return widgets
end

---Build bar layout widgets for bar tracker components (BuffTrackerBars).
---@param componentName string
---@param component component
---@return table[]
local function buildBarTrackerLayoutWidgets(componentName, component)
    local widgets = {
        {type = "label", get = function() return L["SECTION_BAR_LAYOUT"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "select",
            name = L["SETTING_LAYOUT_DIRECTION"],
            desc = L["SETTING_LAYOUT_DIRECTION_DESC"],
            get = function() return component.GetSettings().layout_direction or "vertical" end,
            set = function(_, _, value)
                local s = component.GetSettings()
                s.layout_direction = value
                s.layout_alignment = "center"
                if value == "horizontal" then
                    if s.growth_direction ~= "left" and s.growth_direction ~= "right" then
                        s.growth_direction = "right"
                    end
                else
                    if s.growth_direction ~= "up" and s.growth_direction ~= "down" then
                        s.growth_direction = "up"
                    end
                end
                component.Refresh()
                private.Anchor.Refresh()
                if trackersLeftCol and trackersLeftCol.RefreshOptions then trackersLeftCol:RefreshOptions() end
            end,
            values = function()
                local onclick = function(_, _, value)
                    local s = component.GetSettings()
                    s.layout_direction = value
                    s.layout_alignment = "center"
                    if value == "horizontal" then
                        if s.growth_direction ~= "left" and s.growth_direction ~= "right" then
                            s.growth_direction = "right"
                        end
                    else
                        if s.growth_direction ~= "up" and s.growth_direction ~= "down" then
                            s.growth_direction = "up"
                        end
                    end
                    component.Refresh()
                    private.Anchor.Refresh()
                    if trackersLeftCol and trackersLeftCol.RefreshOptions then trackersLeftCol:RefreshOptions() end
                end
                return {
                    {label = L["LAYOUT_DIRECTION_HORIZONTAL"], value = "horizontal", onclick = onclick},
                    {label = L["LAYOUT_DIRECTION_VERTICAL"], value = "vertical", onclick = onclick},
                }
            end,
        },

        {
            type = "select",
            name = L["SETTING_LAYOUT_ALIGNMENT"],
            desc = L["SETTING_LAYOUT_ALIGNMENT_DESC"],
            get = function() return component.GetSettings().layout_alignment or "center" end,
            set = function(_, _, value)
                component.GetSettings().layout_alignment = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = function()
                local onclick = function(_, _, value)
                    component.GetSettings().layout_alignment = value
                    component.Refresh()
                    private.Anchor.Refresh()
                end
                if (component.GetSettings().layout_direction or "vertical") == "vertical" then
                    return {
                        {label = L["LAYOUT_ALIGNMENT_TOP"], value = "top", onclick = onclick},
                        {label = L["LAYOUT_ALIGNMENT_CENTER"], value = "center", onclick = onclick},
                        {label = L["LAYOUT_ALIGNMENT_BOTTOM"], value = "bottom", onclick = onclick},
                    }
                end
                return {
                    {label = L["LAYOUT_ALIGNMENT_LEFT"], value = "left", onclick = onclick},
                    {label = L["LAYOUT_ALIGNMENT_CENTER"], value = "center", onclick = onclick},
                    {label = L["LAYOUT_ALIGNMENT_RIGHT"], value = "right", onclick = onclick},
                }
            end,
        },

        {
            type = "range",
            name = L["SETTING_BAR_WIDTH"],
            desc = L["SETTING_BAR_WIDTH_DESC"],
            min = 20, max = 1000, step = 1,
            get = function() return component.GetSettings().bar_width end,
            -- fontsDirty gate: bar name truncation width lives in the font pass,
            -- which Refresh only runs when fontsDirty is set.
            set = function(_, _, value)
                component.GetSettings().bar_width = value
                private.fontsDirty = true
                component.Refresh()
                private.fontsDirty = false
                private.Anchor.Refresh()
            end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_SIZE"],
            desc = L["SETTING_ICON_SIZE_DESC"],
            min = 8, max = 60, step = 1,
            get = function() return component.GetSettings().icon_size end,
            -- fontsDirty gate: bar name truncation width depends on icon size and
            -- is applied in the font pass, which needs fontsDirty set.
            set = function(_, _, value)
                component.GetSettings().icon_size = value
                private.fontsDirty = true
                component.Refresh()
                private.fontsDirty = false
                private.Anchor.Refresh()
            end,
        },

        {
            type = "range",
            name = L["SETTING_BAR_HEIGHT"],
            desc = L["SETTING_BAR_HEIGHT_DESC"],
            min = 5, max = 60, step = 1,
            get = function() return component.GetSettings().bar_height end,
            set = function(_, _, value) component.GetSettings().bar_height = value; component.Refresh(); private.Anchor.Refresh() end,
        },

        {
            type = "range",
            name = L["SETTING_BAR_SPACING"],
            desc = L["SETTING_BAR_SPACING_DESC"],
            min = -5, max = 20, step = 1,
            get = function() return component.GetSettings().bar_spacing end,
            set = function(_, _, value) component.GetSettings().bar_spacing = value; component.Refresh(); private.Anchor.Refresh() end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_OFFSET"],
            desc = L["SETTING_BAR_ICON_OFFSET_DESC"],
            min = -5, max = 20, step = 1,
            get = function() return component.GetSettings().icon_offset end,
            -- fontsDirty gate: bar name truncation width depends on icon offset and
            -- is applied in the font pass, which needs fontsDirty set.
            set = function(_, _, value)
                component.GetSettings().icon_offset = value
                private.fontsDirty = true
                component.Refresh()
                private.fontsDirty = false
                private.Anchor.Refresh()
            end,
        },

        {
            type = "range",
            name = L["SETTING_BAR_ICON_OFFSET_X"],
            desc = L["SETTING_BAR_ICON_OFFSET_X_DESC"],
            min = -50, max = 50, step = 1,
            get = function() return component.GetSettings().icon_offset_x or 0 end,
            set = function(_, _, value) component.GetSettings().icon_offset_x = value; component.Refresh(); private.Anchor.Refresh() end,
        },

        {
            type = "range",
            name = L["SETTING_BAR_ICON_OFFSET_Y"],
            desc = L["SETTING_BAR_ICON_OFFSET_Y_DESC"],
            min = -50, max = 50, step = 1,
            get = function() return component.GetSettings().icon_offset_y or 0 end,
            set = function(_, _, value) component.GetSettings().icon_offset_y = value; component.Refresh(); private.Anchor.Refresh() end,
        },

        {
            type = "select",
            name = L["SETTING_GROWTH_DIRECTION"],
            desc = L["SETTING_GROWTH_DIRECTION_DESC"],
            get = function() return component.GetSettings().growth_direction end,
            set = function(_, _, value)
                component.GetSettings().growth_direction = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
            values = function()
                local onclick = function(_, _, value)
                    component.GetSettings().growth_direction = value
                    component.Refresh()
                    private.Anchor.Refresh()
                end
                if (component.GetSettings().layout_direction or "vertical") == "horizontal" then
                    return {
                        {label = L["SETTING_GROWTH_LEFT"], value = "left", onclick = onclick},
                        {label = L["SETTING_GROWTH_RIGHT"], value = "right", onclick = onclick},
                    }
                end
                return {
                    {label = L["SETTING_GROWTH_UP"], value = "up", onclick = onclick},
                    {label = L["SETTING_GROWTH_DOWN"], value = "down", onclick = onclick},
                }
            end,
        },

        {
            type = "select",
            name = L["SETTING_BAR_CONTENT"],
            desc = L["SETTING_BAR_CONTENT_DESC"],
            get = function() return component.GetSettings().bar_content end,
            -- fontsDirty gate: bar name truncation width (and whether the name
            -- shows at all) is applied in the font pass, which needs fontsDirty set.
            set = function(_, _, value)
                component.GetSettings().bar_content = value
                private.fontsDirty = true
                if component.RefreshAndRelayout then component.RefreshAndRelayout() else component.Refresh() end
                private.fontsDirty = false
            end,
            values = function()
                local onclick = function(_, _, value)
                    component.GetSettings().bar_content = value
                    private.fontsDirty = true
                    if component.RefreshAndRelayout then component.RefreshAndRelayout() else component.Refresh() end
                    private.fontsDirty = false
                end
                return {
                    {label = L["SETTING_BAR_CONTENT_ICON_AND_BAR"], value = "IconAndName", onclick = onclick},
                    {label = L["SETTING_BAR_CONTENT_ICON_ONLY"], value = "IconOnly", onclick = onclick},
                    {label = L["SETTING_BAR_CONTENT_BAR_ONLY"], value = "NameOnly", onclick = onclick},
                    {label = L["SETTING_BAR_CONTENT_BAR_ONLY_NO_NAME"], value = "BarOnlyNoName", onclick = onclick},
                    {label = L["SETTING_BAR_CONTENT_ICON_AND_BAR_NO_NAME"], value = "IconAndBarNoName", onclick = onclick},
                }
            end,
        },

        {
            type = "toggle",
            name = L["SETTING_BAR_COLLAPSE"],
            desc = L["SETTING_BAR_COLLAPSE_DESC"],
            get = function() return component.GetSettings().collapse end,
            set = function(_, _, value)
                component.GetSettings().collapse = value
                if component.RefreshAndRelayout then component.RefreshAndRelayout() else component.Refresh() end
            end,
        },

        {
            type = "color",
            name = L["SETTING_BAR_FILL_COLOR"],
            desc = L["SETTING_BAR_FILL_COLOR_DESC"],
            get = function()
                local c = component.GetSettings().bar_fill_color
                return {private.Util.Color(c)}
            end,
            set = function(_, r, g, b, a)
                component.GetSettings().bar_fill_color = {r, g, b, a}
                component.Refresh()
            end,
        },

    }

    return widgets
end

---Build trinket tracker layout widgets.
---@param component component
---@return table[]
local function buildTrinketLayoutWidgets(component)
    local widgets = {
        {type = "label", get = function() return L["SECTION_ICON_LAYOUT"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "select",
            name = L["SETTING_LAYOUT"],
            desc = L["SETTING_LAYOUT_DESC"],
            get = function() return component.GetSettings().layout end,
            set = function(_, _, value) component.GetSettings().layout = value; component.Refresh(); private.Anchor.Refresh() end,
            values = function()
                local onclick = function(_, _, value) component.GetSettings().layout = value; component.Refresh(); private.Anchor.Refresh() end
                return {
                    {label = L["SETTING_LAYOUT_HORIZONTAL"], value = "horizontal", onclick = onclick},
                    {label = L["SETTING_LAYOUT_VERTICAL"], value = "vertical", onclick = onclick},
                }
            end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_SIZE"],
            desc = L["SETTING_ICON_SIZE_DESC"],
            min = 8, max = 80, step = 1,
            get = function() return component.GetSettings().icon_size end,
            set = function(_, _, value) component.GetSettings().icon_size = value; component.Refresh(); private.Anchor.Refresh() end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_HEIGHT"],
            desc = L["SETTING_ICON_HEIGHT_DESC"],
            min = 0, max = 80, step = 1,
            get = function() return component.GetSettings().icon_height or 0 end,
            set = function(_, _, value)
                if value > 0 and value < 8 then value = 8 end
                component.GetSettings().icon_height = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_OFFSET"],
            desc = L["SETTING_ICON_OFFSET_DESC"],
            min = -5, max = 20, step = 1,
            get = function() return component.GetSettings().icon_offset end,
            set = function(_, _, value) component.GetSettings().icon_offset = value; component.Refresh(); private.Anchor.Refresh() end,
        },

        {
            type = "toggle",
            name = L["SETTING_RESERVE_SLOTS"],
            desc = L["SETTING_RESERVE_SLOTS_DESC"],
            get = function() return component.GetSettings().reserve_slots end,
            set = function(_, _, value) component.GetSettings().reserve_slots = value; component.Refresh(); private.Anchor.Refresh() end,
        },

        {
            type = "toggle",
            name = L["SETTING_SHOW_PASSIVE_TRINKETS"],
            desc = L["SETTING_SHOW_PASSIVE_TRINKETS_DESC"],
            get = function() return component.GetSettings().show_passive end,
            set = function(_, _, value) component.GetSettings().show_passive = value; component.Refresh(); private.Anchor.Refresh() end,
        },

    }

    return widgets
end

---Build racial tracker layout widgets.
---@param component component
---@return table[]
local function buildRacialLayoutWidgets(component)
    local widgets = {
        {type = "label", get = function() return L["SECTION_ICON_LAYOUT"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "select",
            name = L["SETTING_LAYOUT"],
            desc = L["SETTING_LAYOUT_DESC"],
            get = function() return component.GetSettings().layout end,
            set = function(_, _, value) component.GetSettings().layout = value; component.Refresh(); private.Anchor.Refresh() end,
            values = function()
                local onclick = function(_, _, value) component.GetSettings().layout = value; component.Refresh(); private.Anchor.Refresh() end
                return {
                    {label = L["SETTING_LAYOUT_HORIZONTAL"], value = "horizontal", onclick = onclick},
                    {label = L["SETTING_LAYOUT_VERTICAL"], value = "vertical", onclick = onclick},
                }
            end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_SIZE"],
            desc = L["SETTING_ICON_SIZE_DESC"],
            min = 8, max = 80, step = 1,
            get = function() return component.GetSettings().icon_size end,
            set = function(_, _, value) component.GetSettings().icon_size = value; component.Refresh(); private.Anchor.Refresh() end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_HEIGHT"],
            desc = L["SETTING_ICON_HEIGHT_DESC"],
            min = 0, max = 80, step = 1,
            get = function() return component.GetSettings().icon_height or 0 end,
            set = function(_, _, value)
                if value > 0 and value < 8 then value = 8 end
                component.GetSettings().icon_height = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_OFFSET"],
            desc = L["SETTING_ICON_OFFSET_DESC"],
            min = -5, max = 20, step = 1,
            get = function() return component.GetSettings().icon_offset end,
            set = function(_, _, value) component.GetSettings().icon_offset = value; component.Refresh(); private.Anchor.Refresh() end,
        },
    }

    return widgets
end

---Build consumable tracker layout + category widgets.
---@param component component
---@return table[]
local function buildConsumableLayoutWidgets(component)
    local widgets = {
        {type = "label", get = function() return L["SECTION_ICON_LAYOUT"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "select",
            name = L["SETTING_LAYOUT"],
            desc = L["SETTING_LAYOUT_DESC"],
            get = function() return component.GetSettings().layout end,
            set = function(_, _, value) component.GetSettings().layout = value; component.Refresh(); private.Anchor.Refresh() end,
            values = function()
                local onclick = function(_, _, value) component.GetSettings().layout = value; component.Refresh(); private.Anchor.Refresh() end
                return {
                    {label = L["SETTING_LAYOUT_HORIZONTAL"], value = "horizontal", onclick = onclick},
                    {label = L["SETTING_LAYOUT_VERTICAL"], value = "vertical", onclick = onclick},
                    {label = L["SETTING_LAYOUT_BLOCK"], value = "block", onclick = onclick},
                }
            end,
        },

        {
            type = "select",
            name = L["SETTING_LAYOUT_ALIGNMENT"],
            desc = L["SETTING_LAYOUT_ALIGNMENT_DESC"],
            get = function() return component.GetSettings().layout_alignment or "left" end,
            set = function(_, _, value) component.GetSettings().layout_alignment = value; component.Refresh(); private.Anchor.Refresh() end,
            values = function()
                local onclick = function(_, _, value) component.GetSettings().layout_alignment = value; component.Refresh(); private.Anchor.Refresh() end
                if component.GetSettings().layout == "vertical" then
                    return {
                        {label = L["LAYOUT_ALIGNMENT_TOP"], value = "top", onclick = onclick},
                        {label = L["LAYOUT_ALIGNMENT_CENTER"], value = "center", onclick = onclick},
                        {label = L["LAYOUT_ALIGNMENT_BOTTOM"], value = "bottom", onclick = onclick},
                    }
                end
                return {
                    {label = L["LAYOUT_ALIGNMENT_LEFT"], value = "left", onclick = onclick},
                    {label = L["LAYOUT_ALIGNMENT_CENTER"], value = "center", onclick = onclick},
                    {label = L["LAYOUT_ALIGNMENT_RIGHT"], value = "right", onclick = onclick},
                }
            end,
            disableif = function() return component.GetSettings().layout == "block" end,
        },

        {
            type = "select",
            name = L["SETTING_BLOCK_DIRECTION"],
            desc = L["SETTING_BLOCK_DIRECTION_DESC"],
            get = function() return component.GetSettings().block_direction or "horizontal" end,
            set = function(_, _, value) component.GetSettings().block_direction = value; component.Refresh(); private.Anchor.Refresh() end,
            values = function()
                local onclick = function(_, _, value) component.GetSettings().block_direction = value; component.Refresh(); private.Anchor.Refresh() end
                return {
                    {label = L["LAYOUT_DIRECTION_HORIZONTAL"], value = "horizontal", onclick = onclick},
                    {label = L["LAYOUT_DIRECTION_VERTICAL"], value = "vertical", onclick = onclick},
                }
            end,
            disableif = function() return component.GetSettings().layout ~= "block" end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_SIZE"],
            desc = L["SETTING_ICON_SIZE_DESC"],
            min = 8, max = 80, step = 1,
            get = function() return component.GetSettings().icon_size end,
            set = function(_, _, value) component.GetSettings().icon_size = value; component.Refresh(); private.Anchor.Refresh() end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_HEIGHT"],
            desc = L["SETTING_ICON_HEIGHT_DESC"],
            min = 0, max = 80, step = 1,
            get = function() return component.GetSettings().icon_height or 0 end,
            set = function(_, _, value)
                if value > 0 and value < 8 then value = 8 end
                component.GetSettings().icon_height = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_OFFSET"],
            desc = L["SETTING_ICON_OFFSET_DESC"],
            min = -5, max = 20, step = 1,
            get = function() return component.GetSettings().icon_offset end,
            set = function(_, _, value) component.GetSettings().icon_offset = value; component.Refresh(); private.Anchor.Refresh() end,
        },

        {
            type = "toggle",
            name = L["SETTING_SHOW_COUNT"],
            desc = L["SETTING_SHOW_COUNT_DESC"],
            get = function() return component.GetSettings().show_count end,
            set = function(_, _, value) component.GetSettings().show_count = value; component.Refresh() end,
        },
    }

    return widgets
end

---Build tracked items (category + per-family toggles) for the consumable tracker.
---@param component component
---@return table[]
local function buildConsumableTrackedItemsWidgets(component)
    local widgets = {
        {type = "label", get = function() return L["SECTION_TRACKED_ITEMS"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},
    }

    local categoryOrder = private.ConsumableTracker.GetCategoryOrder()
    for _, category in ipairs(categoryOrder) do
        local labelKey = private.ConsumableTracker.GetCategoryLabel(category)
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L[labelKey],
            desc = "",
            get = function()
                local val = component.GetSettings().tracked_categories[category]
                if val == nil then return true end
                return val
            end,
            set = function(_, _, value)
                component.GetSettings().tracked_categories[category] = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
        }
    end

    -- Per-family toggles with icons
    local families = private.ConsumableTracker.GetFamilies()
    local familiesByCategory = {}
    for _, family in ipairs(families) do
        if not familiesByCategory[family.category] then
            familiesByCategory[family.category] = {}
        end
        local catList = familiesByCategory[family.category]
        catList[#catList + 1] = family
    end

    for _, category in ipairs(categoryOrder) do
        local catFamilies = familiesByCategory[category]
        if catFamilies then
            local catLabelKey = private.ConsumableTracker.GetCategoryLabel(category)
            widgets[#widgets + 1] = {
                type = "label",
                get = function() return L[catLabelKey] end,
                text_template = orangeFontTemplate, color = orangeFontTemplate.color,
            }
            for _, family in ipairs(catFamilies) do
                local familyKey = family.key
                widgets[#widgets + 1] = {
                    type = "toggle",
                    name = private.ConsumableTracker.GetFamilyName(family),
                    icontexture = family.icon,
                    iconsize = {16, 16},
                    desc = "",
                    hooks = {
                        OnEnter = function(frame)
                            local itemId = family.itemIds[#family.itemIds]
                            GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
                            GameTooltip:SetItemByID(itemId)
                            GameTooltip:Show()
                        end,
                        OnLeave = function() GameTooltip:Hide() end,
                    },
                    get = function()
                        local val = private.profile.components.ConsumableTracker.tracked_families[familyKey]
                        if val == nil then return true end
                        return val
                    end,
                    set = function(_, _, value)
                        private.profile.components.ConsumableTracker.tracked_families[familyKey] = value
                        private.ConsumableTracker.Refresh()
                        private.Anchor.Refresh()
                    end,
                }
            end
        end
    end

    return widgets
end

---Build tracked racial toggles for the racial tracker (right column).
---@param component component
---@return table[]
local function buildRacialTrackedWidgets(component)
    local widgets = {
        {type = "label", get = function() return L["SECTION_TRACKED_RACIALS"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},
    }

    local rt = private.RacialTracker
    if not rt then return widgets end

    local racialIDs = rt.GetResolvedSpellIDs()
    if not racialIDs then return widgets end

    for _, spellID in ipairs(racialIDs) do
        local capturedID = spellID
        local spellName = C_Spell.GetSpellName(capturedID)
        local spellTexture = C_Spell.GetSpellTexture(capturedID)
        widgets[#widgets + 1] = {
            type = "toggle",
            name = spellName or ("Spell " .. capturedID),
            icontexture = spellTexture,
            iconsize = {16, 16},
            desc = "",
            hooks = {
                OnEnter = function(frame)
                    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
                    GameTooltip:SetSpellByID(capturedID)
                    GameTooltip:Show()
                end,
                OnLeave = function() GameTooltip:Hide() end,
            },
            get = function()
                local excluded = component.GetSettings().excluded_racials
                return not (excluded and excluded[capturedID])
            end,
            set = function(_, _, value)
                local settings = component.GetSettings()
                if not settings.excluded_racials then settings.excluded_racials = {} end
                if value then
                    settings.excluded_racials[capturedID] = nil
                else
                    settings.excluded_racials[capturedID] = true
                end
                component.Refresh()
                private.Anchor.Refresh()
            end,
        }
    end

    return widgets
end

---Resolve user input (item name, ID, or link) to an itemID using Blizzard APIs.
---@param input string
---@return number?
local function resolveItemInput(input)
    if not input or input == "" then return nil end
    -- Numeric itemID
    local asNumber = tonumber(input)
    if asNumber then
        local name = C_Item.GetItemInfoInstant(asNumber)
        if name then return asNumber end
        return nil
    end
    -- Item link (shift-click or pasted): extract ID directly from pattern
    local linkID = tonumber(input:match("item:(%d+)"))
    if linkID then return linkID end
    -- Item name (only works if cached) — first return is itemID
    local resolvedID = C_Item.GetItemInfoInstant(input)
    if resolvedID then return resolvedID end
    return nil
end

-- EditBox reference for shift-click item link insertion.
-- Set when the trinket exclude textentry gains focus, cleared on focus loss.
---@type editbox?
local trinketExcludeEditBox

-- Hook the link insertion function so shift-clicking items inserts links into
-- the trinket exclude textentry when it has focus.  Pattern follows AceGUI:
-- post-hook is fine because the original only inserts into focused chat EditBoxes.
do
    local function onInsertLink(text)
        if trinketExcludeEditBox and trinketExcludeEditBox:IsVisible() and trinketExcludeEditBox:HasFocus() then
            trinketExcludeEditBox:Insert(text)
        end
    end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", onInsertLink)
    elseif ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", onInsertLink)
    end
end

---Build trinket slot selection + blacklist widgets for the trinket tracker (right column).
---@param component component
---@param refreshCallback function  called after blacklist add/remove to rebuild the panel
---@return table[]
local function buildTrinketExcludeWidgets(component, refreshCallback)
    ---Add an itemID to the trinket blacklist and refresh (validates trinket equip slot).
    local function addExcludedTrinket(itemID)
        if not itemID then return end
        local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
        if equipLoc ~= "INVTYPE_TRINKET" then return end
        local settings = component.GetSettings()
        if not settings.excluded_trinkets then settings.excluded_trinkets = {} end
        if settings.excluded_trinkets[itemID] then return end
        settings.excluded_trinkets[itemID] = true
        component.Refresh()
        private.Anchor.Refresh()
        if refreshCallback then refreshCallback() end
    end

    local widgets = {
        {type = "label", get = function() return L["SECTION_SLOT_SELECTION"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "toggle",
            name = L["SETTING_SHOW_SLOT_1"],
            desc = L["SETTING_SHOW_SLOT_1_DESC"],
            get = function()
                local val = component.GetSettings().show_slot_1
                if val == nil then return true end
                return val
            end,
            set = function(_, _, value)
                component.GetSettings().show_slot_1 = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
        },

        {
            type = "toggle",
            name = L["SETTING_SHOW_SLOT_2"],
            desc = L["SETTING_SHOW_SLOT_2_DESC"],
            get = function()
                local val = component.GetSettings().show_slot_2
                if val == nil then return true end
                return val
            end,
            set = function(_, _, value)
                component.GetSettings().show_slot_2 = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
        },

        {type = "blank"},
        {type = "label", get = function() return L["SECTION_EXCLUDED_TRINKETS"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "textentry",
            name = L["SETTING_EXCLUDE_TRINKET_INPUT"],
            desc = L["SETTING_EXCLUDE_TRINKET_INPUT_DESC"],
            get = function() return "" end,
            -- DF calls func(param1, param2, text, editbox) from OnEnterPressed
            func = function(_, _, text, editbox)
                addExcludedTrinket(resolveItemInput(text))
                if editbox and editbox.SetText then editbox:SetText("") end
            end,
            hooks = {
                OnEditFocusGained = function(editbox)
                    trinketExcludeEditBox = editbox
                end,
                OnEditFocusLost = function(editbox)
                    if trinketExcludeEditBox == editbox then
                        trinketExcludeEditBox = nil
                    end
                end,
            },
        },

        {
            type = "execute",
            name = L["SETTING_EXCLUDE_TRINKET_DROP"],
            desc = L["SETTING_EXCLUDE_TRINKET_DROP_DESC"],
            func = function()
                local infoType, itemID = GetCursorInfo()
                if infoType == "item" and itemID then
                    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
                    if equipLoc == "INVTYPE_TRINKET" then
                        ClearCursor()
                        addExcludedTrinket(itemID)
                    end
                end
            end,
        },
    }

    -- Dynamic list of currently excluded items
    local excluded = component.GetSettings().excluded_trinkets
    if excluded and next(excluded) then
        widgets[#widgets + 1] = {type = "blank"}
        widgets[#widgets + 1] = {type = "label", get = function() return L["SETTING_EXCLUDED_LIST"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
        for itemID in pairs(excluded) do
            local capturedID = itemID
            local itemName = C_Item.GetItemNameByID(capturedID)
            local itemIcon = C_Item.GetItemIconByID(capturedID)
            local displayName = itemName or ("Item " .. tostring(capturedID))
            if itemIcon then
                displayName = "|T" .. itemIcon .. ":16:16|t " .. displayName
            end
            widgets[#widgets + 1] = {
                type = "execute",
                width = 240,
                name = "|cffff4444X|r  " .. displayName,
                desc = L["SETTING_REMOVE_EXCLUDED"],
                hooks = {
                    OnEnter = function(frame)
                        GameTooltip:SetOwner(frame.widget or frame, "ANCHOR_RIGHT")
                        GameTooltip:SetItemByID(capturedID)
                        GameTooltip:Show()
                    end,
                    OnLeave = function() GameTooltip:Hide() end,
                },
                func = function()
                    local settings = component.GetSettings()
                    if settings.excluded_trinkets then
                        settings.excluded_trinkets[capturedID] = nil
                    end
                    component.Refresh()
                    private.Anchor.Refresh()
                    if refreshCallback then refreshCallback() end
                end,
            }
        end
    end

    return widgets
end

-- =========================================================================
-- Per-spell settings: spell_colors, pandemic_glow_excludes and aura_unit
-- =========================================================================
-- One implementation of the writes the Tracking tab's rows make (through the
-- private.Options exports, since TrackingTab.lua is its own module).  The
-- trackers read both keys through Util.ResolveByBaseOrOverride
-- (AuraBarTracker applyBarFill, AuraContainer syncPandemic), so the writers
-- resolve the same way: an entry already saved under the other id of a
-- base/override pair is the one replaced or removed, never shadowed by a
-- second entry the reader cannot see.  Callers run their own refresh after a
-- write, as each surface did before.

---ResolveByBaseOrOverride callback: `id` itself when `map` has a key for it.
---@param id number
---@param map table
---@return number|nil
local function keyInMap(id, map)
    if map[id] ~= nil then return id end
    return nil
end

---ResolveByBaseOrOverride callback: true when `id` IS `target`.
---@param id number
---@param target number
---@return true|nil
local function idIsTarget(id, target)
    if id == target then return true end
    return nil
end

---The key in a per-spell colour map (`spell_colors`, `spell_borders`) its reader
---resolves `spellID`'s colour from, or nil.
---@param settings table|nil
---@param mapKey string
---@param spellID number
---@return number|nil
local function findColorKey(settings, mapKey, spellID)
    local colors = settings and settings[mapKey]
    if type(colors) ~= "table" then return nil end
    return private.Util.ResolveByBaseOrOverride(spellID, keyInMap, colors)
end

---The {r, g, b, a} `mapKey` holds for `spellID` (the bar fill, the icon border),
---or nil when no valid per-spell colour resolves (a corrupt entry reads as none).
---@param settings table|nil
---@param mapKey string
---@param spellID number
---@return number[]|nil
local function getMapColor(settings, mapKey, spellID)
    local key = findColorKey(settings, mapKey, spellID)
    local c = key and settings[mapKey][key]
    if type(c) ~= "table" or type(c[1]) ~= "number" then return nil end
    return c
end

---Set `spellID`'s colour in `mapKey`, under the key a reader already resolves
---when one exists, else under `spellID`.
---@param settings table
---@param mapKey string
---@param spellID number
local function setMapColor(settings, mapKey, spellID, r, g, b, a)
    if type(settings[mapKey]) ~= "table" then settings[mapKey] = {} end
    local key = findColorKey(settings, mapKey, spellID) or spellID
    settings[mapKey][key] = {r, g, b, a or 1}
end

---Drop every `mapKey` entry a reader could resolve for `spellID`, so the spell
---falls back to the display's own colour.
---@param settings table
---@param mapKey string
---@param spellID number
local function clearMapColor(settings, mapKey, spellID)
    local key = findColorKey(settings, mapKey, spellID)
    while key do
        settings[mapKey][key] = nil
        key = findColorKey(settings, mapKey, spellID)
    end
end

---Is `spellID` in the per-spell exclude list `listKey` (`pandemic_glow_excludes`,
---`active_swipe_excludes`)?  The readers' own test (AuraContainer
---syncPandemic, IconTracker syncAuraSlots).
---@param settings table|nil
---@param listKey string
---@param spellID number
---@return boolean
local function isExcluded(settings, listKey, spellID)
    return private.Util.BaseOrOverrideInList(spellID, settings and settings[listKey])
end

---Add `spellID` to, or take every equivalent id out of, the exclude list `listKey`.
---@param settings table
---@param listKey string
---@param spellID number
---@param excluded boolean
local function setExcluded(settings, listKey, spellID, excluded)
    if type(settings[listKey]) ~= "table" then settings[listKey] = {} end
    local list = settings[listKey]
    if excluded then
        if not isExcluded(settings, listKey, spellID) then list[#list + 1] = spellID end
        return
    end
    for i = #list, 1, -1 do
        if private.Util.ResolveByBaseOrOverride(spellID, idIsTarget, list[i]) then
            table.remove(list, i)
        end
    end
end

---The `aura_unit` key already holding `spellID`'s unit scope, or nil.  The
---reader (AuraContainer.ExpandUnitScope) looks keys up raw, so this finds an
---entry the retired Additional Frames list saved under the id the user picked,
---which can be the other half of a base/override pair from the row's key.
---@param settings table|nil
---@param spellID number
---@return number|nil
local function findAuraUnitKey(settings, spellID)
    local scopes = settings and settings.aura_unit
    if type(scopes) ~= "table" then return nil end
    return private.Util.ResolveByBaseOrOverride(spellID, keyInMap, scopes)
end

---Which aura groups `spellID` may appear in: "player", "target" or the
---default "both" (AuraContainer.SplitByUnitScope).
---@param settings table|nil
---@param spellID number
---@return "both"|"player"|"target"
local function getAuraUnit(settings, spellID)
    local key = findAuraUnitKey(settings, spellID)
    return key and settings.aura_unit[key] or "both"
end

---Set `spellID`'s unit scope.  "both" is the default, so it drops every entry
---that resolves for the spell and a profile carries only real overrides.
---@param settings table
---@param spellID number
---@param unit "both"|"player"|"target"
local function setAuraUnit(settings, spellID, unit)
    if type(settings.aura_unit) ~= "table" then settings.aura_unit = {} end
    if unit ~= "both" then
        settings.aura_unit[findAuraUnitKey(settings, spellID) or spellID] = unit
        return
    end
    local key = findAuraUnitKey(settings, spellID)
    while key do
        settings.aura_unit[key] = nil
        key = findAuraUnitKey(settings, spellID)
    end
end

-- The bar trackers' fill colour and the icon trackers' border colour: one shape.
options.GetSpellColor = function(settings, spellID) return getMapColor(settings, "spell_colors", spellID) end
options.SetSpellColor = function(settings, spellID, r, g, b, a) setMapColor(settings, "spell_colors", spellID, r, g, b, a) end
options.ClearSpellColor = function(settings, spellID) clearMapColor(settings, "spell_colors", spellID) end
options.GetSpellBorder = function(settings, spellID) return getMapColor(settings, "spell_borders", spellID) end
options.SetSpellBorder = function(settings, spellID, r, g, b, a) setMapColor(settings, "spell_borders", spellID, r, g, b, a) end
options.ClearSpellBorder = function(settings, spellID) clearMapColor(settings, "spell_borders", spellID) end
options.GetMissingGlow = function(settings, spellID) return getMapColor(settings, "missing_glow", spellID) end
options.SetMissingGlow = function(settings, spellID, r, g, b, a) setMapColor(settings, "missing_glow", spellID, r, g, b, a) end
options.ClearMissingGlow = function(settings, spellID) clearMapColor(settings, "missing_glow", spellID) end
options.IsExcluded = isExcluded
options.SetExcluded = setExcluded
options.GetAuraUnit = getAuraUnit
options.SetAuraUnit = setAuraUnit

---Build layout widgets for the consumable buff tracker.
---@param component component
---@return table[]
local function buildConsumableBuffLayoutWidgets(component)
    local widgets = {
        {type = "label", get = function() return L["SECTION_ICON_LAYOUT"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "select",
            name = L["SETTING_LAYOUT"],
            desc = L["SETTING_LAYOUT_DESC"],
            get = function() return component.GetSettings().layout end,
            set = function(_, _, value) component.GetSettings().layout = value; component.Refresh(); private.Anchor.Refresh() end,
            values = function()
                local onclick = function(_, _, value) component.GetSettings().layout = value; component.Refresh(); private.Anchor.Refresh() end
                return {
                    {label = L["SETTING_LAYOUT_HORIZONTAL"], value = "horizontal", onclick = onclick},
                    {label = L["SETTING_LAYOUT_VERTICAL"], value = "vertical", onclick = onclick},
                    {label = L["SETTING_LAYOUT_BLOCK"], value = "block", onclick = onclick},
                }
            end,
        },

        {
            type = "select",
            name = L["SETTING_LAYOUT_ALIGNMENT"],
            desc = L["SETTING_LAYOUT_ALIGNMENT_DESC"],
            get = function() return component.GetSettings().layout_alignment or "left" end,
            set = function(_, _, value) component.GetSettings().layout_alignment = value; component.Refresh(); private.Anchor.Refresh() end,
            values = function()
                local onclick = function(_, _, value) component.GetSettings().layout_alignment = value; component.Refresh(); private.Anchor.Refresh() end
                if component.GetSettings().layout == "vertical" then
                    return {
                        {label = L["LAYOUT_ALIGNMENT_TOP"], value = "top", onclick = onclick},
                        {label = L["LAYOUT_ALIGNMENT_CENTER"], value = "center", onclick = onclick},
                        {label = L["LAYOUT_ALIGNMENT_BOTTOM"], value = "bottom", onclick = onclick},
                    }
                end
                return {
                    {label = L["LAYOUT_ALIGNMENT_LEFT"], value = "left", onclick = onclick},
                    {label = L["LAYOUT_ALIGNMENT_CENTER"], value = "center", onclick = onclick},
                    {label = L["LAYOUT_ALIGNMENT_RIGHT"], value = "right", onclick = onclick},
                }
            end,
            disableif = function() return component.GetSettings().layout == "block" end,
        },

        {
            type = "select",
            name = L["SETTING_BLOCK_DIRECTION"],
            desc = L["SETTING_BLOCK_DIRECTION_DESC"],
            get = function() return component.GetSettings().block_direction or "horizontal" end,
            set = function(_, _, value) component.GetSettings().block_direction = value; component.Refresh(); private.Anchor.Refresh() end,
            values = function()
                local onclick = function(_, _, value) component.GetSettings().block_direction = value; component.Refresh(); private.Anchor.Refresh() end
                return {
                    {label = L["LAYOUT_DIRECTION_HORIZONTAL"], value = "horizontal", onclick = onclick},
                    {label = L["LAYOUT_DIRECTION_VERTICAL"], value = "vertical", onclick = onclick},
                }
            end,
            disableif = function() return component.GetSettings().layout ~= "block" end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_SIZE"],
            desc = L["SETTING_ICON_SIZE_DESC"],
            min = 8, max = 80, step = 1,
            get = function() return component.GetSettings().icon_size end,
            set = function(_, _, value) component.GetSettings().icon_size = value; component.Refresh(); private.Anchor.Refresh() end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_HEIGHT"],
            desc = L["SETTING_ICON_HEIGHT_DESC"],
            min = 0, max = 80, step = 1,
            get = function() return component.GetSettings().icon_height or 0 end,
            set = function(_, _, value)
                if value > 0 and value < 8 then value = 8 end
                component.GetSettings().icon_height = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
        },

        {
            type = "range",
            name = L["SETTING_ICON_OFFSET"],
            desc = L["SETTING_ICON_OFFSET_DESC"],
            min = -5, max = 20, step = 1,
            get = function() return component.GetSettings().icon_offset end,
            set = function(_, _, value) component.GetSettings().icon_offset = value; component.Refresh(); private.Anchor.Refresh() end,
        },

        {
            type = "toggle",
            name = L["SETTING_SHOW_COUNT"],
            desc = L["SETTING_SHOW_COUNT_DESC"],
            get = function() return component.GetSettings().show_count end,
            set = function(_, _, value) component.GetSettings().show_count = value; component.Refresh() end,
        },

    }

    return widgets
end

---Build tracked category toggles for the consumable buff tracker.
---@param component component
---@return table[]
local function buildConsumableBuffTrackedItemsWidgets(component)
    local widgets = {
        {
            type = "toggle",
            name = L["SETTING_CLICKABLE"],
            desc = L["SETTING_CLICKABLE_DESC"],
            get = function() return component.GetSettings().clickable end,
            set = function(_, _, value)
                component.GetSettings().clickable = value
                if private.Tooltip then private.Tooltip.RefreshAll() end
                component.Refresh()
            end,
        },
        {type = "blank"},
        {type = "label", get = function() return L["SECTION_TRACKED_ITEMS"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},
    }

    local catOrder = private.ConsumableBuffTracker.GetCategoryOrder()
    for _, catKey in ipairs(catOrder) do
        local labelKey = private.ConsumableBuffTracker.GetCategoryLabel(catKey)
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L[labelKey],
            desc = "",
            get = function()
                local val = component.GetSettings().tracked_categories[catKey]
                if val == nil then return true end
                return val
            end,
            set = function(_, _, value)
                component.GetSettings().tracked_categories[catKey] = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
        }
    end

    -- Per-item toggles with icons, grouped by category
    local entries = private.ConsumableBuffTracker.GetEntries()
    local entriesByCategory = {}
    for _, entry in ipairs(entries) do
        if not entriesByCategory[entry.category] then
            entriesByCategory[entry.category] = {}
        end
        local catList = entriesByCategory[entry.category]
        catList[#catList + 1] = entry
    end

    for _, catKey in ipairs(catOrder) do
        local catEntries = entriesByCategory[catKey]
        if catEntries then
            local catLabelKey = private.ConsumableBuffTracker.GetCategoryLabel(catKey)
            widgets[#widgets + 1] = {
                type = "label",
                get = function() return L[catLabelKey] end,
                text_template = orangeFontTemplate, color = orangeFontTemplate.color,
            }
            for _, entry in ipairs(catEntries) do
                local entryKey = entry.key
                widgets[#widgets + 1] = {
                    type = "toggle",
                    name = private.ConsumableBuffTracker.GetEntryName(entry),
                    icontexture = entry.icon,
                    iconsize = {16, 16},
                    desc = "",
                    hooks = {
                        OnEnter = function(frame)
                            GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
                            GameTooltip:SetItemByID(entry.itemId)
                            GameTooltip:Show()
                        end,
                        OnLeave = function() GameTooltip:Hide() end,
                    },
                    get = function()
                        local val = private.profile.components.ConsumableBuffTracker.tracked_buffs[entryKey]
                        if val == nil then return true end
                        return val
                    end,
                    set = function(_, _, value)
                        private.profile.components.ConsumableBuffTracker.tracked_buffs[entryKey] = value
                        private.ConsumableBuffTracker.Refresh()
                        private.Anchor.Refresh()
                    end,
                }
            end
        end
    end

    -- Glow settings
    widgets[#widgets + 1] = {type = "blank"}
    widgets[#widgets + 1] = {type = "label", get = function() return L["SECTION_GLOW_EFFECTS"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}

    widgets[#widgets + 1] = {
        type = "toggle",
        name = L["SETTING_GLOW_ENABLED"],
        desc = L["SETTING_GLOW_ENABLED_DESC"],
        get = function() return component.GetSettings().glow.enabled end,
        set = function(_, _, value)
            component.GetSettings().glow.enabled = value
            if not value and component.StopAllGlows then component.StopAllGlows() end
            component.Refresh()
        end,
    }

    widgets[#widgets + 1] = {type = "blank"}
    widgets[#widgets + 1] = {type = "label", get = function() return L["GLOW_HEADER_MISSING"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
    widgets[#widgets + 1] = {
        type = "toggle",
        name = L["SETTING_GLOW_MISSING"],
        desc = L["SETTING_GLOW_MISSING_DESC"],
        get = function() return component.GetSettings().glow.missing_enabled end,
        set = function(_, _, value) component.GetSettings().glow.missing_enabled = value; component.Refresh() end,
        disableif = function() return not component.GetSettings().glow.enabled end,
    }

    widgets[#widgets + 1] = {type = "blank"}
    widgets[#widgets + 1] = {type = "label", get = function() return L["GLOW_HEADER_EXPIRING"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
    widgets[#widgets + 1] = {
        type = "toggle",
        name = L["SETTING_GLOW_EXPIRING"],
        desc = L["SETTING_GLOW_EXPIRING_DESC"],
        get = function() return component.GetSettings().glow.expiring_enabled end,
        set = function(_, _, value) component.GetSettings().glow.expiring_enabled = value; component.Refresh() end,
        disableif = function() return not component.GetSettings().glow.enabled end,
    }

    widgets[#widgets + 1] = {
        type = "range",
        name = L["SETTING_EXPIRING_TIME"],
        desc = L["SETTING_EXPIRING_TIME_DESC"],
        min = 30, max = 900, step = 30,
        get = function() return component.GetSettings().glow.expiring_time end,
        set = function(_, _, value) component.GetSettings().glow.expiring_time = value end,
        disableif = function() return not component.GetSettings().glow.expiring_enabled end,
    }

    widgets[#widgets + 1] = {type = "blank"}
    widgets[#widgets + 1] = {type = "label", get = function() return L["SECTION_VISIBILITY"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
    widgets[#widgets + 1] = {
        type = "toggle",
        name = L["SETTING_HIDE_WHEN_APPLIED"],
        desc = L["SETTING_HIDE_WHEN_APPLIED_DESC"],
        get = function() return component.GetSettings().hide_when_applied end,
        set = function(_, _, value) component.GetSettings().hide_when_applied = value; component.Refresh(); private.Anchor.Refresh() end,
    }

    widgets[#widgets + 1] = {
        type = "toggle",
        name = L["SETTING_SHOW_IN_CHALLENGE_MODE"],
        desc = L["SETTING_SHOW_IN_CHALLENGE_MODE_DESC"],
        get = function() return component.GetSettings().show_in_challenge_mode end,
        set = function(_, _, value) component.GetSettings().show_in_challenge_mode = value; component.Refresh() end,
    }

    return widgets
end

---Build layout widgets for the raid buff tracker.
---@param component component
---@return table[]
local function buildRaidBuffLayoutWidgets(component)
    local widgets = {
        {type = "label", get = function() return L["SECTION_ICON_LAYOUT"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},
        {
            type = "select",
            name = L["SETTING_LAYOUT"],
            desc = L["SETTING_LAYOUT_DESC"],
            get = function() return component.GetSettings().layout end,
            set = function(_, _, value) component.GetSettings().layout = value; component.Refresh(); private.Anchor.Refresh() end,
            values = function()
                local onclick = function(_, _, value) component.GetSettings().layout = value; component.Refresh(); private.Anchor.Refresh() end
                return {
                    {label = L["SETTING_LAYOUT_HORIZONTAL"], value = "horizontal", onclick = onclick},
                    {label = L["SETTING_LAYOUT_VERTICAL"], value = "vertical", onclick = onclick},
                    {label = L["SETTING_LAYOUT_BLOCK"], value = "block", onclick = onclick},
                }
            end,
        },
        {
            type = "select",
            name = L["SETTING_LAYOUT_ALIGNMENT"],
            desc = L["SETTING_LAYOUT_ALIGNMENT_DESC"],
            get = function() return component.GetSettings().layout_alignment or "left" end,
            set = function(_, _, value) component.GetSettings().layout_alignment = value; component.Refresh(); private.Anchor.Refresh() end,
            values = function()
                local onclick = function(_, _, value) component.GetSettings().layout_alignment = value; component.Refresh(); private.Anchor.Refresh() end
                if component.GetSettings().layout == "vertical" then
                    return {
                        {label = L["LAYOUT_ALIGNMENT_TOP"], value = "top", onclick = onclick},
                        {label = L["LAYOUT_ALIGNMENT_CENTER"], value = "center", onclick = onclick},
                        {label = L["LAYOUT_ALIGNMENT_BOTTOM"], value = "bottom", onclick = onclick},
                    }
                end
                return {
                    {label = L["LAYOUT_ALIGNMENT_LEFT"], value = "left", onclick = onclick},
                    {label = L["LAYOUT_ALIGNMENT_CENTER"], value = "center", onclick = onclick},
                    {label = L["LAYOUT_ALIGNMENT_RIGHT"], value = "right", onclick = onclick},
                }
            end,
            disableif = function() return component.GetSettings().layout == "block" end,
        },
        {
            type = "select",
            name = L["SETTING_BLOCK_DIRECTION"],
            desc = L["SETTING_BLOCK_DIRECTION_DESC"],
            get = function() return component.GetSettings().block_direction or "horizontal" end,
            set = function(_, _, value) component.GetSettings().block_direction = value; component.Refresh(); private.Anchor.Refresh() end,
            values = function()
                local onclick = function(_, _, value) component.GetSettings().block_direction = value; component.Refresh(); private.Anchor.Refresh() end
                return {
                    {label = L["LAYOUT_DIRECTION_HORIZONTAL"], value = "horizontal", onclick = onclick},
                    {label = L["LAYOUT_DIRECTION_VERTICAL"], value = "vertical", onclick = onclick},
                }
            end,
            disableif = function() return component.GetSettings().layout ~= "block" end,
        },
        {
            type = "range",
            name = L["SETTING_ICON_SIZE"],
            desc = L["SETTING_ICON_SIZE_DESC"],
            min = 8, max = 80, step = 1,
            get = function() return component.GetSettings().icon_size end,
            set = function(_, _, value) component.GetSettings().icon_size = value; component.Refresh(); private.Anchor.Refresh() end,
        },
        {
            type = "range",
            name = L["SETTING_ICON_HEIGHT"],
            desc = L["SETTING_ICON_HEIGHT_DESC"],
            min = 0, max = 80, step = 1,
            get = function() return component.GetSettings().icon_height or 0 end,
            set = function(_, _, value)
                if value > 0 and value < 8 then value = 8 end
                component.GetSettings().icon_height = value
                component.Refresh()
                private.Anchor.Refresh()
            end,
        },
        {
            type = "range",
            name = L["SETTING_ICON_OFFSET"],
            desc = L["SETTING_ICON_OFFSET_DESC"],
            min = -5, max = 20, step = 1,
            get = function() return component.GetSettings().icon_offset end,
            set = function(_, _, value) component.GetSettings().icon_offset = value; component.Refresh(); private.Anchor.Refresh() end,
        },
    }
    return widgets
end

---Build tracked buff toggles and glow settings for the raid buff tracker.
---@param component component
---@return table[]
local function buildRaidBuffTrackedItemsWidgets(component)
    local widgets = {
        {
            type = "toggle",
            name = L["SETTING_CLICKABLE"],
            desc = L["SETTING_CLICKABLE_DESC"],
            get = function() return component.GetSettings().clickable end,
            set = function(_, _, value)
                component.GetSettings().clickable = value
                if private.Tooltip then private.Tooltip.RefreshAll() end
                component.Refresh()
            end,
        },
        {type = "blank"},
        {type = "label", get = function() return L["SECTION_TRACKED_ITEMS"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},
    }

    widgets[#widgets + 1] = {
        type = "toggle",
        name = L["SETTING_SHOW_ALL_BUFFS"],
        desc = L["SETTING_SHOW_ALL_BUFFS_DESC"],
        get = function() return component.GetSettings().show_all_buffs end,
        set = function(_, _, value) component.GetSettings().show_all_buffs = value; component.Refresh(); private.Anchor.Refresh() end,
    }

    local buffDefs = private.RaidBuffTracker.GetBuffDefinitions()
    for _, def in ipairs(buffDefs) do
        local buffKey = def.key
        widgets[#widgets + 1] = {
            type = "toggle",
            name = private.RaidBuffTracker.GetBuffLabel(buffKey),
            icontexture = C_Spell.GetSpellTexture(def.spellId) or def.fallbackIcon,
            iconsize = {16, 16},
            desc = "",
            hooks = {
                OnEnter = function(frame)
                    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
                    GameTooltip:SetSpellByID(def.spellId)
                    GameTooltip:Show()
                end,
                OnLeave = function() GameTooltip:Hide() end,
            },
            get = function()
                local val = component.GetSettings().tracked_buffs[buffKey]
                if val == nil then return true end
                return val
            end,
            set = function(_, _, value)
                component.GetSettings().tracked_buffs[buffKey] = value
                private.RaidBuffTracker.Refresh()
                private.Anchor.Refresh()
            end,
        }
    end

    widgets[#widgets + 1] = {type = "blank"}
    widgets[#widgets + 1] = {type = "label", get = function() return L["SECTION_GLOW_EFFECTS"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}

    widgets[#widgets + 1] = {
        type = "toggle",
        name = L["SETTING_GLOW_ENABLED"],
        desc = L["SETTING_GLOW_ENABLED_DESC"],
        get = function() return component.GetSettings().glow.enabled end,
        set = function(_, _, value)
            component.GetSettings().glow.enabled = value
            if not value and component.StopAllGlows then component.StopAllGlows() end
            component.Refresh()
        end,
    }

    widgets[#widgets + 1] = {
        type = "toggle",
        name = L["SETTING_GLOW_MISSING"],
        desc = L["SETTING_GLOW_MISSING_DESC"],
        get = function() return component.GetSettings().glow.missing_enabled end,
        set = function(_, _, value) component.GetSettings().glow.missing_enabled = value; component.Refresh() end,
        disableif = function() return not component.GetSettings().glow.enabled end,
    }

    widgets[#widgets + 1] = {type = "blank"}
    widgets[#widgets + 1] = {type = "label", get = function() return L["SECTION_VISIBILITY"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
    widgets[#widgets + 1] = {
        type = "toggle",
        name = L["SETTING_HIDE_WHEN_APPLIED"],
        desc = L["SETTING_HIDE_WHEN_APPLIED_DESC"],
        get = function() return component.GetSettings().hide_when_applied end,
        set = function(_, _, value) component.GetSettings().hide_when_applied = value; component.Refresh(); private.Anchor.Refresh() end,
    }

    return widgets
end

---Build tracked-spells list, sort order, color source, overflow, and self-cast
---filter widgets for the outbound buff tracker (right column of the detail panel).
---@param component component
---@param refresh fun()?  rebuild the detail panel so the tracked-spell rows redraw
---@return table[]
local function buildOutboundBuffTrackedItemsWidgets(component, refresh)
    local widgets = {}

    widgets[#widgets + 1] = {type = "label", get = function() return L["SECTION_TRACKED_ITEMS"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}

    -- Tracked spell entries: one toggle-free row per spell plus a remove button.
    local trackedSpells = component.GetSettings().tracked_spells or {}
    for _, spellID in ipairs(trackedSpells) do
        local capturedID = spellID
        local spellName = C_Spell.GetSpellName(capturedID) or ("Spell " .. tostring(capturedID))
        local icon = C_Spell.GetSpellTexture(capturedID)
        widgets[#widgets + 1] = {
            type = "execute",
            name = spellName .. " (" .. tostring(capturedID) .. ")",
            icontexture = icon,
            iconsize = {16, 16},
            desc = L["SETTING_OUTBOUND_REMOVE_SPELL_DESC"],
            func = function()
                component.RemoveTrackedSpell(capturedID)
                if refresh then refresh() end
            end,
        }
    end

    -- Input field to add a spellID by number.
    widgets[#widgets + 1] = {
        type = "textentry",
        name = L["SETTING_OUTBOUND_ADD_SPELL"],
        desc = L["SETTING_OUTBOUND_ADD_SPELL_DESC"],
        get = function() return "" end,
        -- DF calls func(param1, param2, text, editbox) from OnEnterPressed
        func = function(_, _, text, editbox)
            local id = tonumber(text)
            if id and id > 0 then
                component.AddTrackedSpell(id)
                if refresh then refresh() end
            end
            if editbox and editbox.SetText then editbox:SetText("") end
        end,
    }

    widgets[#widgets + 1] = {type = "blank"}
    widgets[#widgets + 1] = {type = "label", get = function() return L["SECTION_OUTBOUND_FILTERING"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}

    widgets[#widgets + 1] = {
        type = "toggle",
        name = L["SETTING_OUTBOUND_FILTER_SELF_CAST"],
        desc = L["SETTING_OUTBOUND_FILTER_SELF_CAST_DESC"],
        get = function() return component.GetSettings().filter_self_cast end,
        set = function(_, _, value) component.GetSettings().filter_self_cast = value; component.Refresh() end,
    }

    widgets[#widgets + 1] = {
        type = "select",
        name = L["SETTING_OUTBOUND_SORT_ORDER"],
        desc = L["SETTING_OUTBOUND_SORT_ORDER_DESC"],
        get = function() return component.GetSettings().sort_order or "remaining_asc" end,
        set = function(_, _, value) component.GetSettings().sort_order = value; component.Refresh() end,
        values = function()
            local onclick = function(_, _, value)
                component.GetSettings().sort_order = value
                component.Refresh()
            end
            return {
                {label = L["SETTING_OUTBOUND_SORT_REMAINING_ASC"], value = "remaining_asc", onclick = onclick},
                {label = L["SETTING_OUTBOUND_SORT_REMAINING_DESC"], value = "remaining_desc", onclick = onclick},
                {label = L["SETTING_OUTBOUND_SORT_NAME_ASC"], value = "name_asc", onclick = onclick},
            }
        end,
    }

    widgets[#widgets + 1] = {
        type = "select",
        name = L["SETTING_OUTBOUND_NAME_COLOR_SOURCE"],
        desc = L["SETTING_OUTBOUND_NAME_COLOR_SOURCE_DESC"],
        get = function() return component.GetSettings().name_color_source or "class" end,
        set = function(_, _, value) component.GetSettings().name_color_source = value; component.Refresh() end,
        values = function()
            local onclick = function(_, _, value)
                component.GetSettings().name_color_source = value
                component.Refresh()
            end
            return {
                {label = L["SETTING_OUTBOUND_NAME_COLOR_CLASS"], value = "class", onclick = onclick},
                {label = L["SETTING_OUTBOUND_NAME_COLOR_STATIC"], value = "static", onclick = onclick},
            }
        end,
    }

    widgets[#widgets + 1] = {
        type = "color",
        name = L["SETTING_OUTBOUND_NAME_COLOR_STATIC"],
        desc = L["SETTING_OUTBOUND_NAME_COLOR_STATIC_DESC"],
        get = function()
            local c = component.GetSettings().name_color_static or {1, 1, 1, 1}
            return c[1], c[2], c[3], c[4]
        end,
        set = function(_, r, g, b, a)
            component.GetSettings().name_color_static = {r, g, b, a}
            component.Refresh()
        end,
        disableif = function() return component.GetSettings().name_color_source ~= "static" end,
    }

    widgets[#widgets + 1] = {type = "blank"}
    widgets[#widgets + 1] = {type = "label", get = function() return L["SECTION_OUTBOUND_DISPLAY"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}

    widgets[#widgets + 1] = {
        type = "range",
        name = L["SETTING_OUTBOUND_MAX_BARS"],
        desc = L["SETTING_OUTBOUND_MAX_BARS_DESC"],
        min = 1, max = 40, step = 1,
        get = function() return component.GetSettings().max_bars or 8 end,
        set = function(_, _, value) component.GetSettings().max_bars = value; component.Refresh(); private.Anchor.Refresh() end,
    }

    widgets[#widgets + 1] = {
        type = "toggle",
        name = L["SETTING_OUTBOUND_OVERFLOW_HIDE"],
        desc = L["SETTING_OUTBOUND_OVERFLOW_HIDE_DESC"],
        get = function() return component.GetSettings().overflow_hide ~= false end,
        set = function(_, _, value) component.GetSettings().overflow_hide = value; component.Refresh(); private.Anchor.Refresh() end,
    }

    return widgets
end

---Build glow effect widgets for trinket/consumable trackers.
---@param component component
---@return table[]
local function buildGlowWidgets(component)
    local glowSettings = component.GetSettings().glow
    if not glowSettings then return {} end

    local widgets = {}

    widgets[#widgets + 1] = {type = "label", get = function() return L["SECTION_GLOW_EFFECTS"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
    widgets[#widgets + 1] = {
        type = "toggle",
        name = L["SETTING_GLOW_ENABLED"],
        desc = L["SETTING_GLOW_ENABLED_DESC"],
        get = function() return component.GetSettings().glow.enabled end,
        set = function(_, _, value)
            component.GetSettings().glow.enabled = value
            if not value and component.StopAllGlows then component.StopAllGlows() end
        end,
        children_follow_enabled = true,
        childrenids = {"glow_flash", "glow_pulse", "glow_approaching", "glow_active"},
    }

    widgets[#widgets + 1] = {type = "blank"}
    widgets[#widgets + 1] = {type = "label", get = function() return L["GLOW_HEADER_FLASH"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
    widgets[#widgets + 1] = {
        type = "toggle",
        id = "glow_flash",
        name = L["SETTING_GLOW_FLASH"],
        desc = L["SETTING_GLOW_FLASH_DESC"],
        get = function() return component.GetSettings().glow.flash_enabled end,
        set = function(_, _, value) component.GetSettings().glow.flash_enabled = value end,
        disableif = function() return not component.GetSettings().glow.enabled end,
    }

    widgets[#widgets + 1] = {type = "blank"}
    widgets[#widgets + 1] = {type = "label", get = function() return L["GLOW_HEADER_PULSE"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
    widgets[#widgets + 1] = {
        type = "toggle",
        id = "glow_pulse",
        name = L["SETTING_GLOW_PULSE"],
        desc = L["SETTING_GLOW_PULSE_DESC"],
        get = function() return component.GetSettings().glow.pulse_enabled end,
        set = function(_, _, value)
            component.GetSettings().glow.pulse_enabled = value
            if not value and component.StopAllGlows then component.StopAllGlows() end
        end,
        disableif = function() return not component.GetSettings().glow.enabled end,
    }
    widgets[#widgets + 1] = {
        type = "range",
        name = L["SETTING_GLOW_DURATION"],
        desc = L["SETTING_GLOW_DURATION_DESC"],
        min = 0, max = 30, step = 1,
        get = function() return component.GetSettings().glow.pulse_duration end,
        set = function(_, _, value) component.GetSettings().glow.pulse_duration = value end,
        disableif = function()
            local glow = component.GetSettings().glow
            return not glow.enabled or not glow.pulse_enabled
        end,
    }

    if component.name == "ConsumableTracker" or component.name == "TrinketTracker" then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_GLOW_READY_IN_MPLUS"],
            desc = L["SETTING_GLOW_READY_IN_MPLUS_DESC"],
            get = function() return component.GetSettings().glow.ready_in_mplus_enabled end,
            set = function(_, _, value)
                component.GetSettings().glow.ready_in_mplus_enabled = value
                if not value and component.StopAllGlows then component.StopAllGlows() end
            end,
            disableif = function()
                local glow = component.GetSettings().glow
                return not glow.enabled or not glow.pulse_enabled
            end,
        }
    end

    widgets[#widgets + 1] = {type = "blank"}
    widgets[#widgets + 1] = {type = "label", get = function() return L["GLOW_HEADER_APPROACHING"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
    widgets[#widgets + 1] = {
        type = "toggle",
        id = "glow_approaching",
        name = L["SETTING_GLOW_APPROACHING"],
        desc = L["SETTING_GLOW_APPROACHING_DESC"],
        get = function() return component.GetSettings().glow.approaching_enabled end,
        set = function(_, _, value)
            component.GetSettings().glow.approaching_enabled = value
            if not value and component.StopAllGlows then component.StopAllGlows() end
        end,
        disableif = function() return not component.GetSettings().glow.enabled end,
    }
    widgets[#widgets + 1] = {
        type = "range",
        name = L["SETTING_GLOW_APPROACHING_TIME"],
        desc = L["SETTING_GLOW_APPROACHING_TIME_DESC"],
        min = 0, max = 300, step = 1,
        get = function() return component.GetSettings().glow.approaching_time end,
        set = function(_, _, value) component.GetSettings().glow.approaching_time = value end,
        disableif = function()
            local glow = component.GetSettings().glow
            return not glow.enabled or not glow.approaching_enabled
        end,
    }

    widgets[#widgets + 1] = {type = "blank"}
    widgets[#widgets + 1] = {type = "label", get = function() return L["GLOW_HEADER_ACTIVE"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
    widgets[#widgets + 1] = {
        type = "toggle",
        id = "glow_active",
        name = L["SETTING_GLOW_ACTIVE"],
        desc = L["SETTING_GLOW_ACTIVE_DESC"],
        get = function() return component.GetSettings().glow.active_enabled end,
        set = function(_, _, value)
            component.GetSettings().glow.active_enabled = value
            if not value and component.StopAllGlows then component.StopAllGlows() end
        end,
        disableif = function() return not component.GetSettings().glow.enabled end,
    }

    return widgets
end

---Build background panel widgets for any component.
---@param getSettings fun(): table  function returning the component's settings table (must contain .background)
---@param refreshFn fun()  function to call after changing a setting (e.g. Anchor.Refresh)
---@return table[] widgets
local defaultBackground = {enabled = false, color = {0, 0, 0, 0.6}, padding_h = 4, padding_v = 4, rounded = false, roundness = 8, border_style = "none", border_color = {0, 0, 0, 0.8}, party_corners = "left"}

local BORDER_STYLE_OPTIONS = {
    {label = NONE, value = "none"},
    {label = "Plain", value = "plain"},
    {label = "Slider", value = "slider"},
    {label = "Tooltip", value = "tooltip"},
    {label = "Dialog", value = "dialog"},
    {label = "Dialog Gold", value = "dialog_gold"},
    {label = "Achievement", value = "achievement_wood"},
    {label = "Chat Bubble", value = "chat_bubble"},
    {label = "Toast", value = "toast"},
    {label = "Party", value = "party"},
}

local function ensureBackground(settings)
    if not settings.background then
        settings.background = {}
        for k, v in pairs(defaultBackground) do
            settings.background[k] = type(v) == "table" and {unpack(v)} or v
        end
    end
    return settings
end

local function buildBackgroundWidgets(getSettings, refreshFn)
    local widgets = {}

    widgets[#widgets + 1] = {type = "label", get = function() return L["COMPONENT_BG_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}

    widgets[#widgets + 1] = {
        type = "toggle",
        name = L["COMPONENT_BG_ENABLED"],
        desc = L["COMPONENT_BG_ENABLED_DESC"],
        get = function() return getSettings().background.enabled end,
        set = function(_, _, value)
            getSettings().background.enabled = value
            refreshFn()
        end,
        children_follow_enabled = true,
        childrenids = {"cue_bg_border_style", "cue_bg_party_corners", "cue_bg_color", "cue_bg_padding_h", "cue_bg_padding_v", "cue_bg_rounded", "cue_bg_roundness", "cue_bg_border_color"},
    }

    widgets[#widgets + 1] = {
        type = "select",
        id = "cue_bg_border_style",
        name = L["COMPONENT_BG_BORDER_STYLE"],
        desc = L["COMPONENT_BG_BORDER_STYLE_DESC"],
        values = function()
            local t = {}
            for _, opt in ipairs(BORDER_STYLE_OPTIONS) do
                t[#t + 1] = {label = opt.label, value = opt.value, onclick = function(_, _, value)
                    getSettings().background.border_style = value
                    refreshFn()
                end}
            end
            return t
        end,
        get = function() return getSettings().background.border_style or "none" end,
        set = function(_, _, value)
            getSettings().background.border_style = value
            refreshFn()
        end,
        disableif = function() return getSettings().background.rounded end,
    }

    local PARTY_CORNER_OPTIONS = {
        {label = L["PARTY_CORNERS_LEFT"], value = "left"},
        {label = L["PARTY_CORNERS_RIGHT"], value = "right"},
        {label = L["PARTY_CORNERS_TOP"], value = "top"},
        {label = L["PARTY_CORNERS_BOTTOM"], value = "bottom"},
        {label = L["PARTY_CORNERS_ALL"], value = "all"},
        {label = L["PARTY_CORNERS_TL"], value = "tl"},
        {label = L["PARTY_CORNERS_TR"], value = "tr"},
        {label = L["PARTY_CORNERS_BL"], value = "bl"},
        {label = L["PARTY_CORNERS_BR"], value = "br"},
    }
    widgets[#widgets + 1] = {
        type = "select",
        id = "cue_bg_party_corners",
        name = L["PARTY_CORNERS"],
        desc = L["PARTY_CORNERS_DESC"],
        values = function()
            local t = {}
            for _, opt in ipairs(PARTY_CORNER_OPTIONS) do
                t[#t + 1] = {label = opt.label, value = opt.value, onclick = function(_, _, value)
                    getSettings().background.party_corners = value
                    refreshFn()
                end}
            end
            return t
        end,
        get = function() return getSettings().background.party_corners or "left" end,
        set = function(_, _, value)
            getSettings().background.party_corners = value
            refreshFn()
        end,
        disableif = function() return getSettings().background.rounded or getSettings().background.border_style ~= "party" end,
    }

    widgets[#widgets + 1] = {
        type = "color",
        id = "cue_bg_color",
        name = L["COMPONENT_BG_COLOR"],
        desc = L["COMPONENT_BG_COLOR_DESC"],
        get = function()
            local c = getSettings().background.color
            return {c[1], c[2], c[3], c[4]}
        end,
        set = function(_, r, g, b, a)
            getSettings().background.color = {r, g, b, a}
            refreshFn()
        end,
    }

    widgets[#widgets + 1] = {
        type = "range",
        id = "cue_bg_padding_h",
        name = L["COMPONENT_BG_PADDING_H"],
        desc = L["COMPONENT_BG_PADDING_H_DESC"],
        min = 0,
        max = 25,
        step = 1,
        get = function() return getSettings().background.padding_h or getSettings().background.padding or 4 end,
        set = function(_, _, value)
            getSettings().background.padding_h = value
            refreshFn()
        end,
    }

    widgets[#widgets + 1] = {
        type = "range",
        id = "cue_bg_padding_v",
        name = L["COMPONENT_BG_PADDING_V"],
        desc = L["COMPONENT_BG_PADDING_V_DESC"],
        min = 0,
        max = 25,
        step = 1,
        get = function() return getSettings().background.padding_v or getSettings().background.padding or 4 end,
        set = function(_, _, value)
            getSettings().background.padding_v = value
            refreshFn()
        end,
    }

    widgets[#widgets + 1] = {
        type = "toggle",
        id = "cue_bg_rounded",
        name = L["COMPONENT_BG_ROUNDED"],
        desc = L["COMPONENT_BG_ROUNDED_DESC"],
        get = function() return getSettings().background.rounded end,
        set = function(_, _, value)
            getSettings().background.rounded = value
            refreshFn()
        end,
    }

    widgets[#widgets + 1] = {
        type = "range",
        id = "cue_bg_roundness",
        name = L["COMPONENT_BG_ROUNDNESS"],
        desc = L["COMPONENT_BG_ROUNDNESS_DESC"],
        min = 1,
        max = 16,
        step = 1,
        get = function() return getSettings().background.roundness end,
        set = function(_, _, value)
            getSettings().background.roundness = value
            refreshFn()
        end,
        disableif = function() return not getSettings().background.rounded end,
    }

    widgets[#widgets + 1] = {
        type = "color",
        id = "cue_bg_border_color",
        name = L["COMPONENT_BG_BORDER_COLOR"],
        desc = L["COMPONENT_BG_BORDER_COLOR_DESC"],
        get = function()
            local c = getSettings().background.border_color
            return {c[1], c[2], c[3], c[4]}
        end,
        set = function(_, r, g, b, a)
            getSettings().background.border_color = {r, g, b, a}
            refreshFn()
        end,
        disableif = function() return (getSettings().background.border_style or "none") == "none" end,
    }

    return widgets
end

---Build component-specific feature widgets (health bar, secondary resources, primary resources, etc.).
---@param componentName string
---@param component component
---@return table[]
local function buildComponentSpecificWidgets(componentName, component)
    local widgets = {}
    local rightWidgets = {}

    -- The two aura trackers run Blizzard's compacting groups engine unless slots
    -- are on; there the button-to-aura binding is secret and every per-spell
    -- feature is inert.  Hide those widgets rather than present controls that
    -- silently do nothing (.context/migration-parity-gaps.md D).  Every other
    -- component has no IsUsingSlots, so the gate is false and nothing is hidden.
    local groupsEngine = component.IsUsingSlots ~= nil and not component.IsUsingSlots()

    -- Texture dropdown (cast bars, health bar, resource bars)
    if component.GetSettings().texture ~= nil then
        local isCastBar = component.GetSettings().cast_name_font ~= nil
        local textureSetCallback = function(_, _, value)
            component.GetSettings().texture = value
            component.Refresh()
        end

        widgets[#widgets + 1] = {type = "label", get = function() return L["SECTION_TEXTURE"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
        widgets[#widgets + 1] = {
            type = "select",
            name = isCastBar and L["SETTING_CAST_TEXTURE"] or L["SETTING_TEXTURE"],
            desc = isCastBar and L["SETTING_CAST_TEXTURE_DESC"] or L["SETTING_TEXTURE_DESC"],
            get = function() return component.GetSettings().texture end,
            set = textureSetCallback,
            values = function()
                local textureValues = {{label = L["SETTING_TEXTURE_DEFAULT"], value = "", onclick = textureSetCallback}}
                for _, key in ipairs(LibSharedMedia:List("statusbar") or {}) do
                    textureValues[#textureValues + 1] = {label = key, value = key, onclick = textureSetCallback}
                end
                return textureValues
            end,
        }
        if isCastBar then
            -- castbar_colors is profile-wide, shared by player/target/focus, so
            -- this repaints all three like its Background sibling below and the
            -- Colors-tab duplicate — component.Refresh() left the other two bars
            -- rendering the old texture until something else refreshed them.
            local bgTextureSetCallback = function(_, _, value)
                private.profile.castbar_colors.background_texture = value
                applyCastBarColors()
            end
            widgets[#widgets + 1] = {
                type = "select",
                name = L["COLOR_BACKGROUND_TEXTURE"],
                desc = L["COLOR_BACKGROUND_TEXTURE_DESC"],
                get = function() return private.profile.castbar_colors.background_texture end,
                set = bgTextureSetCallback,
                values = function()
                    local t = {{label = L["SETTING_TEXTURE_DEFAULT"], value = "", onclick = bgTextureSetCallback}}
                    for _, key in ipairs(LibSharedMedia:List("statusbar") or {}) do
                        t[#t + 1] = {label = key, value = key, onclick = bgTextureSetCallback}
                    end
                    return t
                end,
            }
            widgets[#widgets + 1] = {
                type = "color",
                name = L["COLOR_BACKGROUND"],
                desc = L["COLOR_BACKGROUND_DESC"],
                get = function()
                    local c = private.profile.castbar_colors.background
                    return c[1], c[2], c[3], c[4]
                end,
                set = function(_, r, g, b, a)
                    private.profile.castbar_colors.background = {r, g, b, a}
                    applyCastBarColors()
                end,
            }
        end
        widgets[#widgets + 1] = {type = "blank"}
    end

    -- Background panel (below texture, above features)
    appendWidgets(widgets, buildBackgroundWidgets(
        function() return ensureBackground(component.GetSettings()) end,
        function()
            private.ComponentManager.RefreshAllComponents()
            private.Anchor.Refresh()
        end
    ))
    widgets[#widgets + 1] = {type = "blank"}

    -- Features heading (for components that have feature widgets below)
    local hasFeatures = component.GetSettings().keybind_font ~= nil
        or (componentName == "BuffTracker" or componentName == "BuffTrackerBars")
        or component.GetSettings().color_mode ~= nil
        or component.GetSettings().text_format ~= nil
        or component.GetSettings().show_timer ~= nil
        or componentName == "SecondaryResources"
        or component.GetSettings().text_format_mana ~= nil
        or component.GetSettings().mass_disintegrate_glow ~= nil
        or component.GetSettings().show_when_casting ~= nil
        or component.GetSettings().hide_inactive_background ~= nil
        or component.GetSettings().hide_cd_swipe ~= nil
        or component.GetSettings().hide_active_swipe ~= nil
        or component.GetSettings().suppress_buff_icon_swap ~= nil
        or component.GetSettings().hide_gcd_swipe ~= nil
        or component.GetSettings().no_cd_overlay ~= nil
        or component.GetSettings().no_desaturation ~= nil
        or component.GetSettings().hide_cd_text ~= nil
        or component.GetSettings().show_skyriding_abilities ~= nil
        or component.GetSettings().show_vehicle_abilities ~= nil
        or component.GetSettings().show_override_bar_abilities ~= nil
        or component.GetSettings().cast_text_format ~= nil
        or component.GetSettings().show_icon ~= nil
        or component.GetSettings().show_latency ~= nil
        or component.GetSettings().instant_only ~= nil
        or component.GetSettings().bar_color ~= nil
        or component.GetSettings().latency_color ~= nil
        or component.GetSettings().show_shield ~= nil
        or component.GetSettings().show_active_duration ~= nil
    if hasFeatures then
        widgets[#widgets + 1] = {type = "label", get = function() return L["SECTION_FEATURES"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
    end

    -- Show keybind toggle
    if component.GetSettings().keybind_font ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_KEYBIND"],
            desc = L["SETTING_SHOW_KEYBIND_DESC"],
            get = function() return component.GetSettings().keybind_font.enabled end,
            set = function(_, _, value) component.GetSettings().keybind_font.enabled = value; component.Refresh() end,
        }
    end

    -- Show active duration (TrinketTracker only, as in 2.13.4: on the cooldown
    -- trackers hide_active_swipe alone controls the buff takeover, and a key a
    -- 3.0 profile saved there would otherwise surface as a dead toggle)
    if componentName == "TrinketTracker" and component.GetSettings().show_active_duration ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_ACTIVE_DURATION"],
            desc = L["SETTING_SHOW_ACTIVE_DURATION_DESC"],
            get = function() return component.GetSettings().show_active_duration end,
            set = function(_, _, value) component.GetSettings().show_active_duration = value; component.Refresh() end,
        }
    end

    -- Show timer (bar trackers)
    if component.GetSettings().show_timer ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_TIMER"],
            desc = L["SETTING_SHOW_TIMER_DESC"],
            get = function() return component.GetSettings().show_timer end,
            set = function(_, _, value) component.GetSettings().show_timer = value; component.Refresh() end,
        }
    end

    -- Track Totems (bar tracker rows, icon tracker icons leading the run).  NOT
    -- slots-gated, unlike every other per-spell feature here: the totems are
    -- slot-indexed chrome of our own, and neither placement needs the aura
    -- block's (secret) extent.
    if component.GetSettings().show_totems ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_TOTEMS"],
            desc = L["SETTING_SHOW_TOTEMS_DESC"],
            get = function() return component.GetSettings().show_totems end,
            set = function(_, _, value)
                component.GetSettings().show_totems = value
                component.Refresh()
                -- Reserved rows change the reported size, so the anchor chain
                -- has to re-derive rather than wait for a spell-count change.
                private.Anchor.Refresh()
            end,
        }
    end

    -- Always-show engine switch (the two aura trackers only — the key is absent
    -- on every other component).  Off is groups, where the button-to-aura
    -- binding is secret and every per-spell feature is inert.  It used to follow
    -- Blizzard's "hide when inactive" (ON by default, on a viewer this addon keeps
    -- at alpha 0); that setting is now copied in once by pm.MigrateHideWhenInactive.
    if component.GetSettings().always_show_tracked ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_ALWAYS_SHOW_TRACKED"],
            desc = L["SETTING_ALWAYS_SHOW_TRACKED_DESC"],
            get = function() return component.GetSettings().always_show_tracked end,
            set = function(_, _, value)
                component.GetSettings().always_show_tracked = value
                component.Refresh()
                private.Anchor.Refresh()
                -- The engine just changed, so the slots-only widgets appear or
                -- vanish; deferred because this runs from a pooled switch that
                -- the rebuild recycles.
                C_Timer.After(0, function()
                    if selectTrackerComponentFn then selectTrackerComponentFn(componentName) end
                end)
            end,
        }
        -- Slots only: the grey cell under the engine-shown colour copy is what
        -- carries it.  The toggle above rebuilds the panel, so no disableif.
        if component.GetSettings().always_show_tracked == true then
            widgets[#widgets + 1] = {
                type = "toggle",
                name = L["SETTING_DESATURATE_INACTIVE"],
                desc = L["SETTING_DESATURATE_INACTIVE_DESC"],
                get = function() return component.GetSettings().desaturate_inactive == true end,
                set = function(_, _, value)
                    component.GetSettings().desaturate_inactive = value
                    component.Refresh()
                end,
            }
        end
        -- [EXPERIMENTAL] Collapsing slot chain (BuffTracker only): player and
        -- target auras in one Tracking-tab order.  Always Show outranks it, and
        -- the toggle above rebuilds the panel, so it is offered only without.
        -- No rebuild here: IsUsingSlots ignores the chain, so the widget set
        -- does not change.
        if component.GetSettings().collapse_layout ~= nil
            and component.GetSettings().always_show_tracked ~= true then
            widgets[#widgets + 1] = {
                type = "toggle",
                name = L["SETTING_COLLAPSE_LAYOUT"],
                desc = L["SETTING_COLLAPSE_LAYOUT_DESC"],
                get = function() return component.GetSettings().collapse_layout == true end,
                set = function(_, _, value)
                    component.GetSettings().collapse_layout = value
                    component.Refresh()
                    -- The chain reports the slots box, groups the configured one.
                    private.Anchor.Refresh()
                end,
            }
        end
    end

    -- Assisted Combat rotation highlight (CooldownTracker, UtilitiesTracker)
    if component.GetSettings().rotation_highlight ~= nil then
        widgets[#widgets + 1] = {type = "blank"}
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_ROTATION_HIGHLIGHT"],
            desc = L["SETTING_ROTATION_HIGHLIGHT_DESC"],
            get = function() return component.GetSettings().rotation_highlight end,
            set = function(_, _, value)
                component.GetSettings().rotation_highlight = value
                if value and C_CVar.GetCVar("assistedCombatHighlight") ~= "1" then
                    C_CVar.SetCVar("assistedCombatHighlight", "1")
                end
                if private.AssistedHighlight then
                    private.AssistedHighlight.OnSettingChanged()
                    if not value then private.AssistedHighlight.OfferBlizzardHighlightOff() end
                end
                component.Refresh()
            end,
        }
    end

    -- Hide icon texture (CooldownTracker, UtilitiesTracker)
    if component.GetSettings().hide_icon ~= nil then
        widgets[#widgets + 1] = {type = "blank"}
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_HIDE_ICON"],
            desc = L["SETTING_HIDE_ICON_DESC"],
            get = function() return component.GetSettings().hide_icon end,
            -- fontsDirty gate: on the aura trackers this lands in the
            -- AuraContainer restyle pass, which Refresh only runs when the flag
            -- is set (patterns.md "fontsDirty").
            set = function(_, _, value)
                component.GetSettings().hide_icon = value
                private.fontsDirty = true
                component.Refresh()
                private.fontsDirty = false
            end,
        }
    end

    -- Hide cooldown swipe (CooldownTracker, UtilitiesTracker)
    if component.GetSettings().hide_cd_swipe ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_HIDE_CD_SWIPE"],
            desc = L["SETTING_HIDE_CD_SWIPE_DESC"],
            get = function() return component.GetSettings().hide_cd_swipe end,
            -- fontsDirty gate: see hide_icon above.
            set = function(_, _, value)
                component.GetSettings().hide_cd_swipe = value
                private.fontsDirty = true
                component.Refresh()
                private.fontsDirty = false
            end,
        }
    end

    -- Hide active buff swipe (CooldownTracker, UtilitiesTracker)
    if component.GetSettings().hide_active_swipe ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_HIDE_ACTIVE_SWIPE"],
            desc = L["SETTING_HIDE_ACTIVE_SWIPE_DESC"],
            get = function() return component.GetSettings().hide_active_swipe end,
            set = function(_, _, value) component.GetSettings().hide_active_swipe = value; private.CDMDataSource.EnsureEnabled(); component.Refresh() end,
        }
    end

    -- Don't override icons on procs (CooldownTracker, UtilitiesTracker)
    if component.GetSettings().suppress_buff_icon_swap ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SUPPRESS_BUFF_ICON_SWAP"],
            desc = L["SETTING_SUPPRESS_BUFF_ICON_SWAP_DESC"],
            get = function() return component.GetSettings().suppress_buff_icon_swap end,
            set = function(_, _, value)
                component.GetSettings().suppress_buff_icon_swap = value
                private.CDMDataSource.EnsureEnabled()
                component.Refresh()
            end,
        }
    end

    -- No cooldown dimming overlay (CooldownTracker, UtilitiesTracker)
    if component.GetSettings().no_cd_overlay ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_NO_CD_OVERLAY"],
            desc = L["SETTING_NO_CD_OVERLAY_DESC"],
            get = function() return component.GetSettings().no_cd_overlay end,
            set = function(_, _, value) component.GetSettings().no_cd_overlay = value; component.Refresh() end,
            disableif = function() return not component.GetSettings().hide_active_swipe end,
        }
    end

    -- No cooldown dimming: edge-only indicator variant (CooldownTracker, UtilitiesTracker)
    if component.GetSettings().no_cd_overlay_edge_only ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_NO_CD_OVERLAY_EDGE_ONLY"],
            desc = L["SETTING_NO_CD_OVERLAY_EDGE_ONLY_DESC"],
            get = function() return component.GetSettings().no_cd_overlay_edge_only end,
            set = function(_, _, value) component.GetSettings().no_cd_overlay_edge_only = value; component.Refresh() end,
            disableif = function() return not component.GetSettings().hide_active_swipe or not component.GetSettings().no_cd_overlay end,
        }
    end

    -- No desaturation (CooldownTracker, UtilitiesTracker)
    if component.GetSettings().no_desaturation ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_NO_DESATURATION"],
            desc = L["SETTING_NO_DESATURATION_DESC"],
            get = function() return component.GetSettings().no_desaturation end,
            set = function(_, _, value) component.GetSettings().no_desaturation = value; component.Refresh() end,
        }
    end

    -- Force desaturation on cooldown (CooldownTracker, UtilitiesTracker)
    if component.GetSettings().force_desaturation ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_FORCE_DESATURATION"],
            desc = L["SETTING_FORCE_DESATURATION_DESC"],
            get = function() return component.GetSettings().force_desaturation end,
            set = function(_, _, value) component.GetSettings().force_desaturation = value; component.Refresh() end,
            disableif = function() return component.GetSettings().no_desaturation end,
        }
    end

    -- No out-of-range tint (CooldownTracker, UtilitiesTracker)
    if component.GetSettings().no_range_tint ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_NO_RANGE_TINT"],
            desc = L["SETTING_NO_RANGE_TINT_DESC"],
            get = function() return component.GetSettings().no_range_tint end,
            set = function(_, _, value) component.GetSettings().no_range_tint = value; component.Refresh() end,
        }
    end

    -- Icon visibility mode (CooldownTracker, UtilitiesTracker)
    if component.GetSettings().icon_visibility_mode ~= nil then
        widgets[#widgets + 1] = {
            type = "select",
            name = L["SETTING_ICON_VISIBILITY_MODE"],
            desc = L["SETTING_ICON_VISIBILITY_MODE_DESC"],
            get = function() return component.GetSettings().icon_visibility_mode end,
            set = function(_, _, value)
                component.GetSettings().icon_visibility_mode = value
                private.CDMDataSource.EnsureEnabled()
                component.Refresh()
            end,
            values = function()
                local onclick = function(_, _, value)
                    component.GetSettings().icon_visibility_mode = value
                private.CDMDataSource.EnsureEnabled()
                    component.Refresh()
                end
                return {
                    {label = L["SETTING_ICON_VISIBILITY_DISABLED"], value = 1, onclick = onclick},
                    {label = L["SETTING_ICON_VISIBILITY_HIDE_READY"], value = 2, onclick = onclick},
                    {label = L["SETTING_ICON_VISIBILITY_FADE_READY"], value = 3, onclick = onclick},
                    {label = L["SETTING_ICON_VISIBILITY_HIDE_ONCD"], value = 4, onclick = onclick},
                    {label = L["SETTING_ICON_VISIBILITY_FADE_ONCD"], value = 5, onclick = onclick},
                }
            end,
        }
        widgets[#widgets + 1] = {
            type = "range",
            name = L["SETTING_ICON_VISIBILITY_FADED_ALPHA"],
            desc = L["SETTING_ICON_VISIBILITY_FADED_ALPHA_DESC"],
            min = 0, max = 1, step = 0.05,
            usedecimals = true,
            get = function() return component.GetSettings().icon_visibility_faded_alpha or 0.3 end,
            set = function(_, _, value)
                component.GetSettings().icon_visibility_faded_alpha = value
                component.Refresh()
            end,
        }
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_ICON_VISIBILITY_TREAT_CHARGING_AS_ON_CD"],
            desc = L["SETTING_ICON_VISIBILITY_TREAT_CHARGING_AS_ON_CD_DESC"],
            get = function()
                local v = component.GetSettings().icon_visibility_treat_charging_as_on_cd
                if v == nil then return true end
                return v
            end,
            set = function(_, _, value)
                component.GetSettings().icon_visibility_treat_charging_as_on_cd = value
                component.Refresh()
            end,
            disableif = function() return (component.GetSettings().icon_visibility_mode or 1) <= 1 end,
        }
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_HIDE_READY_BLINK"],
            desc = L["SETTING_HIDE_READY_BLINK_DESC"],
            get = function() return component.GetSettings().hide_ready_blink end,
            set = function(_, _, value) component.GetSettings().hide_ready_blink = value; component.Refresh() end,
        }
    end

    -- Hide all cooldown countdown text
    if component.GetSettings().hide_cd_text ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_HIDE_CD_TEXT"],
            desc = L["SETTING_HIDE_CD_TEXT_DESC"],
            get = function() return component.GetSettings().hide_cd_text end,
            -- fontsDirty gate: see hide_icon above.
            set = function(_, _, value)
                component.GetSettings().hide_cd_text = value
                private.fontsDirty = true
                component.Refresh()
                private.fontsDirty = false
            end,
        }
    end

    -- Hide charge recharge text (CooldownTracker only)
    if component.GetSettings().hide_charge_cd_text ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_HIDE_CHARGE_CD_TEXT"],
            desc = L["SETTING_HIDE_CHARGE_CD_TEXT_DESC"],
            get = function() return component.GetSettings().hide_charge_cd_text end,
            set = function(_, _, value) component.GetSettings().hide_charge_cd_text = value; component.Refresh() end,
            disableif = function() return component.GetSettings().hide_cd_text end,
        }
    end

    -- Hide zero charges (CooldownTracker, UtilitiesTracker)
    if component.GetSettings().hide_zero_charges ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_HIDE_ZERO_CHARGES"],
            desc = L["SETTING_HIDE_ZERO_CHARGES_DESC"],
            get = function() return component.GetSettings().hide_zero_charges end,
            set = function(_, _, value) component.GetSettings().hide_zero_charges = value; component.Refresh() end,
        }
    end

    -- Hide GCD swipe (CooldownTracker, UtilitiesTracker)
    if component.GetSettings().hide_gcd_swipe ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_HIDE_GCD_SWIPE"],
            desc = L["SETTING_HIDE_GCD_SWIPE_DESC"],
            get = function() return component.GetSettings().hide_gcd_swipe end,
            set = function(_, _, value) component.GetSettings().hide_gcd_swipe = value; component.Refresh() end,
        }
    end

    -- GCD edge on available charges (CooldownTracker, UtilitiesTracker)
    if component.GetSettings().gcd_edge_charges ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_GCD_EDGE_CHARGES"],
            desc = L["SETTING_GCD_EDGE_CHARGES_DESC"],
            get = function() return component.GetSettings().gcd_edge_charges end,
            set = function(_, _, value) component.GetSettings().gcd_edge_charges = value; component.Refresh() end,
            disableif = function() return component.GetSettings().hide_gcd_swipe end,
        }
    end

    -- Reverse cooldown swipe (CooldownTracker, UtilitiesTracker, RacialTracker)
    if component.GetSettings().reverse_swipe ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_REVERSE_SWIPE"],
            desc = L["SETTING_REVERSE_SWIPE_DESC"],
            get = function() return component.GetSettings().reverse_swipe end,
            set = function(_, _, value) component.GetSettings().reverse_swipe = value; component.Refresh() end,
        }
    end

    -- Show skyriding abilities (CooldownTracker only)
    if component.GetSettings().show_skyriding_abilities ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_SKYRIDING_ABILITIES"],
            desc = L["SETTING_SHOW_SKYRIDING_ABILITIES_DESC"],
            get = function() return component.GetSettings().show_skyriding_abilities end,
            set = function(_, _, value) component.GetSettings().show_skyriding_abilities = value; component.Refresh() end,
        }
    end

    -- Show vehicle abilities (CooldownTracker only)
    if component.GetSettings().show_vehicle_abilities ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_VEHICLE_ABILITIES"],
            desc = L["SETTING_SHOW_VEHICLE_ABILITIES_DESC"],
            get = function() return component.GetSettings().show_vehicle_abilities end,
            set = function(_, _, value) component.GetSettings().show_vehicle_abilities = value; component.Refresh() end,
        }
    end

    -- Show override bar abilities (CooldownTracker only)
    if component.GetSettings().show_override_bar_abilities ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_OVERRIDE_BAR_ABILITIES"],
            desc = L["SETTING_SHOW_OVERRIDE_BAR_ABILITIES_DESC"],
            get = function() return component.GetSettings().show_override_bar_abilities end,
            set = function(_, _, value) component.GetSettings().show_override_bar_abilities = value; component.Refresh() end,
        }
    end

    -- Show keybind text on override/vehicle/skyriding frames (CooldownTracker only)
    if component.GetSettings().show_override_keybind_text ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_OVERRIDE_KEYBIND_TEXT"],
            desc = L["SETTING_SHOW_OVERRIDE_KEYBIND_TEXT_DESC"],
            get = function() return component.GetSettings().show_override_keybind_text end,
            set = function(_, _, value) component.GetSettings().show_override_keybind_text = value; component.Refresh() end,
        }
    end

    -- Route trinkets into CooldownTracker (CooldownTracker only)
    if component.GetSettings().route_trinkets ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_CT_SHOW_TRINKETS"],
            desc = L["SETTING_CT_SHOW_TRINKETS_DESC"],
            get = function() return component.GetSettings().route_trinkets end,
            set = function(_, _, value)
                component.GetSettings().route_trinkets = value
                if private.TrinketTracker then private.TrinketTracker.Refresh() end
                component.Refresh()
                private.Anchor.Refresh()
            end,
        }
    end

    -- Route combat potions into CooldownTracker (CooldownTracker only)
    if component.GetSettings().route_combat_potions ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_CT_SHOW_COMBAT_POTIONS"],
            desc = L["SETTING_CT_SHOW_COMBAT_POTIONS_DESC"],
            get = function() return component.GetSettings().route_combat_potions end,
            set = function(_, _, value)
                component.GetSettings().route_combat_potions = value
                if private.ConsumableTracker then private.ConsumableTracker.Refresh() end
                component.Refresh()
                private.Anchor.Refresh()
            end,
        }
    end

    -- Channel tick marks (PlayerCastBar only)
    if component.GetSettings().show_channel_ticks ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_CHANNEL_TICKS"],
            desc = L["SETTING_SHOW_CHANNEL_TICKS_DESC"],
            get = function() return component.GetSettings().show_channel_ticks end,
            set = function(_, _, value) component.GetSettings().show_channel_ticks = value end,
        }
    end

    -- Cast pushback cutaway (PlayerCastBar only). Read live per pushback, so
    -- no Refresh and no private.fontsDirty — this is not a restyle-applied key.
    if component.GetSettings().pushback_flash ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_PUSHBACK_FLASH"],
            desc = L["SETTING_PUSHBACK_FLASH_DESC"],
            get = function() return component.GetSettings().pushback_flash end,
            set = function(_, _, value) component.GetSettings().pushback_flash = value end,
        }
    end

    -- Mass Disintegrate glow (PlayerCastBar — Evoker only)
    if component.GetSettings().mass_disintegrate_glow ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_MASS_DISINTEGRATE_GLOW"],
            desc = L["SETTING_MASS_DISINTEGRATE_GLOW_DESC"],
            get = function() return component.GetSettings().mass_disintegrate_glow end,
            set = function(_, _, value) component.GetSettings().mass_disintegrate_glow = value end,
        }
    end

    -- Show when casting (PlayerCastBar only)
    if component.GetSettings().show_when_casting ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_WHEN_CASTING"],
            desc = L["SETTING_SHOW_WHEN_CASTING_DESC"],
            get = function() return component.GetSettings().show_when_casting end,
            set = function(_, _, value)
                component.GetSettings().show_when_casting = value
                component.Refresh()
                private.Anchor.OnComponentStateChange()
            end,
        }
    end

    -- Hide background when inactive (PlayerCastBar only)
    if component.GetSettings().hide_inactive_background ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_HIDE_INACTIVE_BG"],
            desc = L["SETTING_HIDE_INACTIVE_BG_DESC"],
            get = function() return component.GetSettings().hide_inactive_background end,
            set = function(_, _, value)
                component.GetSettings().hide_inactive_background = value
                component.Refresh()
            end,
        }
    end

    -- Track instant casts (PlayerCastBar only)
    if component.GetSettings().track_instant_casts ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_TRACK_INSTANT_CASTS"],
            desc = L["SETTING_TRACK_INSTANT_CASTS_DESC"],
            get = function() return component.GetSettings().track_instant_casts end,
            set = function(_, _, value)
                component.GetSettings().track_instant_casts = value
                component.Refresh()
            end,
        }
    end

    -- Show cast icon (all cast bars)
    if component.GetSettings().show_icon ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_CAST_ICON"],
            desc = L["SETTING_SHOW_CAST_ICON_DESC"],
            get = function() return component.GetSettings().show_icon end,
            set = function(_, _, value) component.GetSettings().show_icon = value; component.Refresh() end,
        }
    end

    -- Show spark (all cast bars)
    if component.GetSettings().show_spark ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_SPARK"],
            desc = L["SETTING_SHOW_SPARK_DESC"],
            get = function() return component.GetSettings().show_spark end,
            set = function(_, _, value) component.GetSettings().show_spark = value; component.Refresh() end,
        }
    end

    -- Show latency overlay (GlobalCooldown, PlayerCastBar)
    if component.GetSettings().show_latency ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_LATENCY"],
            desc = L["SETTING_SHOW_LATENCY_DESC"],
            get = function() return component.GetSettings().show_latency end,
            set = function(_, _, value) component.GetSettings().show_latency = value; component.Refresh() end,
        }
    end

    -- Instant casts only (GlobalCooldown)
    if component.GetSettings().instant_only ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_INSTANT_ONLY"],
            desc = L["SETTING_INSTANT_ONLY_DESC"],
            get = function() return component.GetSettings().instant_only end,
            set = function(_, _, value) component.GetSettings().instant_only = value end,
        }
    end

    -- Bar color (GlobalCooldown)
    if component.GetSettings().bar_color ~= nil then
        widgets[#widgets + 1] = {
            type = "color",
            name = L["SETTING_BAR_COLOR"],
            desc = L["SETTING_BAR_COLOR_DESC"],
            boxfirst = true,
            get = function()
                local c = component.GetSettings().bar_color
                return c[1], c[2], c[3], c[4]
            end,
            set = function(_, r, g, b, a)
                component.GetSettings().bar_color = {r, g, b, a}
                component.Refresh()
            end,
        }
    end

    -- Latency color (GlobalCooldown, PlayerCastBar)
    if component.GetSettings().latency_color ~= nil then
        widgets[#widgets + 1] = {
            type = "color",
            name = L["SETTING_LATENCY_COLOR"],
            desc = L["SETTING_LATENCY_COLOR_DESC"],
            boxfirst = true,
            get = function()
                local c = component.GetSettings().latency_color
                return c[1], c[2], c[3], c[4]
            end,
            set = function(_, r, g, b, a)
                component.GetSettings().latency_color = {r, g, b, a}
                component.Refresh()
            end,
        }
    end

    -- Show queue pip (GlobalCooldown)
    if component.GetSettings().show_queue_pip ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_QUEUE_PIP"],
            desc = L["SETTING_SHOW_QUEUE_PIP_DESC"],
            get = function() return component.GetSettings().show_queue_pip end,
            set = function(_, _, value) component.GetSettings().show_queue_pip = value; component.Refresh() end,
        }
    end

    -- Queue pip color (GlobalCooldown)
    if component.GetSettings().queue_pip_color ~= nil then
        widgets[#widgets + 1] = {
            type = "color",
            name = L["SETTING_QUEUE_PIP_COLOR"],
            desc = L["SETTING_QUEUE_PIP_COLOR_DESC"],
            boxfirst = true,
            get = function()
                local c = component.GetSettings().queue_pip_color
                return c[1], c[2], c[3], c[4]
            end,
            set = function(_, r, g, b, a)
                component.GetSettings().queue_pip_color = {r, g, b, a}
                component.Refresh()
            end,
            disableif = function() return not component.GetSettings().show_queue_pip end,
        }
    end

    -- Show duration (GlobalCooldown)
    if component.GetSettings().show_duration ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_DURATION"],
            desc = L["SETTING_SHOW_DURATION_DESC"],
            get = function() return component.GetSettings().show_duration end,
            set = function(_, _, value) component.GetSettings().show_duration = value; component.Refresh() end,
        }
    end

    -- Show spell name (GlobalCooldown)
    if component.GetSettings().show_spell_name ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_SPELL_NAME"],
            desc = L["SETTING_SHOW_SPELL_NAME_DESC"],
            get = function() return component.GetSettings().show_spell_name end,
            set = function(_, _, value) component.GetSettings().show_spell_name = value; component.Refresh() end,
        }
    end

    -- Fill direction (GlobalCooldown)
    if component.GetSettings().fill_direction ~= nil then
        widgets[#widgets + 1] = {
            type = "select",
            name = L["SETTING_FILL_DIRECTION"],
            desc = L["SETTING_FILL_DIRECTION_DESC"],
            get = function() return component.GetSettings().fill_direction end,
            set = function(_, _, value)
                component.GetSettings().fill_direction = value
                component.Refresh()
            end,
            values = function()
                local onclick = function(_, _, value)
                    component.GetSettings().fill_direction = value
                    component.Refresh()
                end
                return {
                    {label = L["FILL_DIRECTION_RIGHT"], value = "right", onclick = onclick},
                    {label = L["FILL_DIRECTION_LEFT"], value = "left", onclick = onclick},
                }
            end,
        }
    end

    -- Blank before shield group (when show_icon precedes it)
    if component.GetSettings().show_shield ~= nil and component.GetSettings().show_icon ~= nil then
        widgets[#widgets + 1] = {type = "blank"}
    end

    -- Show shield indicator (Target/Focus cast bars only)
    if component.GetSettings().show_shield ~= nil then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_SHIELD"],
            desc = L["SETTING_SHOW_SHIELD_DESC"],
            get = function() return component.GetSettings().show_shield end,
            set = function(_, _, value) component.GetSettings().show_shield = value; component.Refresh() end,
        }
    end

    -- Shield scale (Target/Focus cast bars only)
    if component.GetSettings().shield_scale ~= nil then
        widgets[#widgets + 1] = {
            type = "range",
            name = L["SETTING_SHIELD_SCALE"],
            desc = L["SETTING_SHIELD_SCALE_DESC"],
            min = 0.5,
            max = 3.0,
            step = 0.1,
            usedecimals = true,
            get = function() return component.GetSettings().shield_scale end,
            set = function(_, _, value) component.GetSettings().shield_scale = value; component.Refresh() end,
            disableif = function() return not component.GetSettings().show_shield end,
        }
    end

    -- Shield offset X (Target/Focus cast bars only)
    if component.GetSettings().shield_offset_x ~= nil then
        widgets[#widgets + 1] = {
            type = "range",
            name = L["SETTING_SHIELD_OFFSET_X"],
            desc = L["SETTING_SHIELD_OFFSET_X_DESC"],
            min = -50,
            max = 50,
            step = 1,
            get = function() return component.GetSettings().shield_offset_x end,
            set = function(_, _, value) component.GetSettings().shield_offset_x = value; component.Refresh() end,
            disableif = function() return not component.GetSettings().show_shield end,
        }
    end

    -- Shield offset Y (Target/Focus cast bars only)
    if component.GetSettings().shield_offset_y ~= nil then
        widgets[#widgets + 1] = {
            type = "range",
            name = L["SETTING_SHIELD_OFFSET_Y"],
            desc = L["SETTING_SHIELD_OFFSET_Y_DESC"],
            min = -50,
            max = 50,
            step = 1,
            get = function() return component.GetSettings().shield_offset_y end,
            set = function(_, _, value) component.GetSettings().shield_offset_y = value; component.Refresh() end,
            disableif = function() return not component.GetSettings().show_shield end,
        }
    end

    -- Cast bar text display (all cast bars)
    -- For target/focus cast bars (have show_shield), move to right column; otherwise left
    if component.GetSettings().cast_text_format ~= nil then
        -- fontsDirty gate: show/hide of name & time text lives in ApplyFonts,
        -- which Refresh only runs when fontsDirty is set.
        local castTextOnClick = function(_, _, value)
            component.GetSettings().cast_text_format = value
            private.fontsDirty = true
            component.Refresh()
            private.fontsDirty = false
        end
        local castTextValues = function()
            return {
                {label = L["CAST_TEXT_FORMAT_BOTH"], value = "both", onclick = castTextOnClick},
                {label = L["CAST_TEXT_FORMAT_NAME"], value = "name", onclick = castTextOnClick},
                {label = L["CAST_TEXT_FORMAT_TIME"], value = "time", onclick = castTextOnClick},
                {label = L["CAST_TEXT_FORMAT_NONE"], value = "none", onclick = castTextOnClick},
            }
        end
        local castTextTarget = component.GetSettings().show_shield ~= nil and rightWidgets or widgets
        if castTextTarget == rightWidgets and #rightWidgets == 0 then
            castTextTarget[#castTextTarget + 1] = {type = "label", get = function() return L["SECTION_TEXT_DISPLAY"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
        end
        castTextTarget[#castTextTarget + 1] = {
            type = "select",
            name = L["SETTING_CAST_TEXT_FORMAT"],
            desc = L["SETTING_CAST_TEXT_FORMAT_DESC"],
            get = function() return component.GetSettings().cast_text_format end,
            set = castTextOnClick,
            values = castTextValues,
        }

        -- fontsDirty gate: cueTimeStyle is written by ApplyFonts, which Refresh
        -- only runs when fontsDirty is set.
        local castTimeStyleOnClick = function(_, _, value)
            component.GetSettings().cast_time_style = value
            private.fontsDirty = true
            component.Refresh()
            private.fontsDirty = false
        end
        castTextTarget[#castTextTarget + 1] = {
            type = "select",
            name = L["SETTING_CAST_TIME_STYLE"],
            desc = L["SETTING_CAST_TIME_STYLE_DESC"],
            get = function() return component.GetSettings().cast_time_style end,
            set = castTimeStyleOnClick,
            values = function()
                return {
                    {label = L["CAST_TIME_STYLE_REMAINING"], value = "remaining", onclick = castTimeStyleOnClick},
                    {label = L["CAST_TIME_STYLE_ELAPSED_TOTAL"], value = "elapsed_total", onclick = castTimeStyleOnClick},
                    {label = L["CAST_TIME_STYLE_REMAINING_TOTAL"], value = "remaining_total", onclick = castTimeStyleOnClick},
                }
            end,
            disableif = function()
                local mode = component.GetSettings().cast_text_format
                return mode ~= "both" and mode ~= "time"
            end,
        }
    end

    -- Cast name max width (all cast bars)
    if component.GetSettings().cast_name_max_width ~= nil then
        local castWidthTarget = component.GetSettings().show_shield ~= nil and rightWidgets or widgets
        castWidthTarget[#castWidthTarget + 1] = {
            type = "range",
            name = L["SETTING_CAST_NAME_MAX_WIDTH"],
            desc = L["SETTING_CAST_NAME_MAX_WIDTH_DESC"],
            min = 0,
            max = 100,
            step = 5,
            get = function() return component.GetSettings().cast_name_max_width end,
            -- fontsDirty gate: Text:SetWidth lives in ApplyFonts, which Refresh
            -- only runs when fontsDirty is set.
            set = function(_, _, value)
                component.GetSettings().cast_name_max_width = value
                private.fontsDirty = true
                component.Refresh()
                private.fontsDirty = false
            end,
        }
    end

    -- Color mode (health bar)
    if component.GetSettings().color_mode ~= nil then
        widgets[#widgets + 1] = {
            type = "select",
            name = L["SETTING_COLOR_MODE"],
            desc = L["SETTING_COLOR_MODE_DESC"],
            get = function() return component.GetSettings().color_mode end,
            set = function(_, _, value) component.GetSettings().color_mode = value; component.Refresh() end,
            values = function()
                local onclick = function(_, _, value) component.GetSettings().color_mode = value; component.Refresh() end
                return {
                    {label = L["COLOR_MODE_CLASS"], value = "class", onclick = onclick},
                    {label = L["COLOR_MODE_GRADIENT"], value = "gradient", onclick = onclick},
                }
            end,
        }
    end

    -- Text format (health bar)
    if component.GetSettings().text_format ~= nil then
        local textFormatOnClick = function(_, _, value) component.GetSettings().text_format = value; component.Refresh() end
        local textFormatValues = function()
            return {
                {label = L["TEXT_FORMAT_PERCENT"], value = "percent", onclick = textFormatOnClick},
                {label = L["TEXT_FORMAT_CURRENT"], value = "current", onclick = textFormatOnClick},
                {label = L["TEXT_FORMAT_BOTH"], value = "both", onclick = textFormatOnClick},
                {label = L["TEXT_FORMAT_NONE"], value = "none", onclick = textFormatOnClick},
            }
        end
        widgets[#widgets + 1] = {
            type = "select",
            name = L["SETTING_TEXT_FORMAT"],
            desc = L["SETTING_TEXT_FORMAT_DESC"],
            get = function() return component.GetSettings().text_format end,
            set = function(_, _, value) component.GetSettings().text_format = value; component.Refresh() end,
            values = textFormatValues,
        }
    end

    -- Show shields, healing prediction (health bar)
    if componentName == "PlayerHealthBar" then
        widgets[#widgets + 1] = {type = "blank"}
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_INTERACTABLE"],
            desc = L["SETTING_INTERACTABLE_DESC"],
            get = function() return component.GetSettings().interactable end,
            set = function(_, _, value) component.GetSettings().interactable = value; component.Refresh() end,
        }
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_SHIELDS"],
            desc = L["SETTING_SHOW_SHIELDS_DESC"],
            get = function() return component.GetSettings().show_shields end,
            set = function(_, _, value) component.GetSettings().show_shields = value; component.Refresh() end,
        }
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_HEALING_PREDICTION"],
            desc = L["SETTING_SHOW_HEALING_PREDICTION_DESC"],
            get = function() return component.GetSettings().show_healing_prediction end,
            set = function(_, _, value) component.GetSettings().show_healing_prediction = value; component.Refresh() end,
        }
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_BAR_SMOOTHING"],
            desc = L["SETTING_BAR_SMOOTHING_DESC"],
            get = function() return component.GetSettings().bar_smoothing end,
            set = function(_, _, value) component.GetSettings().bar_smoothing = value; component.Refresh() end,
        }
    end

    if componentName == "PrimaryResources" then
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_BAR_SMOOTHING"],
            desc = L["SETTING_BAR_SMOOTHING_DESC"],
            get = function() return component.GetSettings().bar_smoothing end,
            set = function(_, _, value) component.GetSettings().bar_smoothing = value; component.Refresh() end,
        }
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SPEND_PREDICTION"],
            desc = L["SETTING_SPEND_PREDICTION_DESC"],
            get = function() return component.GetSettings().spend_prediction end,
            set = function(_, _, value)
                component.GetSettings().spend_prediction = value
                component.Refresh()
            end,
            children_follow_enabled = true,
            childrenids = {"spend_prediction_color"},
        }
        widgets[#widgets + 1] = {
            type = "color",
            name = L["SETTING_SPEND_PREDICTION_COLOR"],
            desc = L["SETTING_SPEND_PREDICTION_COLOR_DESC"],
            id = "spend_prediction_color",
            get = function()
                local c = component.GetSettings().spend_prediction_color
                return {private.Util.Color(c)}
            end,
            set = function(_, r, g, b, a)
                component.GetSettings().spend_prediction_color = {r, g, b, a}
                component.Refresh()
            end,
        }
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_FIVE_SECOND_RULE"],
            desc = L["SETTING_FIVE_SECOND_RULE_DESC"],
            hidden = not component.HasFiveSecondRule,
            get = function() return component.GetSettings().five_second_rule end,
            set = function(_, _, value)
                component.GetSettings().five_second_rule = value
                component.Refresh()
            end,
            children_follow_enabled = true,
            childrenids = {"five_second_rule_size"},
        }
        widgets[#widgets + 1] = {
            type = "select",
            name = L["SETTING_FIVE_SECOND_RULE_SIZE"],
            desc = L["SETTING_FIVE_SECOND_RULE_SIZE_DESC"],
            id = "five_second_rule_size",
            hidden = not component.HasFiveSecondRule,
            values = function()
                local t = {}
                for _, size in ipairs({"full", "top", "bottom"}) do
                    t[#t + 1] = {label = L["FIVE_SECOND_RULE_SIZE_" .. size:upper()], value = size, onclick = function(_, _, value)
                        component.GetSettings().five_second_rule_size = value
                        component.Refresh()
                    end}
                end
                return t
            end,
            get = function() return component.GetSettings().five_second_rule_size end,
        }
    end

    -- Show value (secondary resources)
    if componentName == "SecondaryResources" then
        -- General features (left column)
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SHOW_VALUE"],
            desc = L["SETTING_SHOW_VALUE_DESC"],
            get = function() return component.GetSettings().show_value end,
            set = function(_, _, value) component.GetSettings().show_value = value; component.Refresh() end,
            children_follow_enabled = true,
            childrenids = {"warlock_shard_fragments"},
        }
        widgets[#widgets + 1] = {
            type = "toggle",
            id = "warlock_shard_fragments",
            name = L["SETTING_WARLOCK_SHARD_FRAGMENTS"],
            desc = L["SETTING_WARLOCK_SHARD_FRAGMENTS_DESC"],
            get = function() return component.GetSettings().warlock_shard_fragments end,
            set = function(_, _, value) component.GetSettings().warlock_shard_fragments = value; component.Refresh() end,
        }
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_BAR_SMOOTHING"],
            desc = L["SETTING_BAR_SMOOTHING_DESC"],
            get = function() return component.GetSettings().bar_smoothing end,
            set = function(_, _, value) component.GetSettings().bar_smoothing = value; component.Refresh() end,
        }
        widgets[#widgets + 1] = {type = "blank"}
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_WARLOCK_SPEND_PREDICTION"],
            desc = L["SETTING_WARLOCK_SPEND_PREDICTION_DESC"],
            get = function() return component.GetSettings().warlock_spend_prediction end,
            set = function(_, _, value)
                component.GetSettings().warlock_spend_prediction = value
                component.Refresh()
            end,
        }
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_BUILDER_PREDICTION"],
            desc = L["SETTING_BUILDER_PREDICTION_DESC"],
            get = function() return component.GetSettings().builder_prediction end,
            set = function(_, _, value)
                component.GetSettings().builder_prediction = value
                component.Refresh()
            end,
            children_follow_enabled = true,
            childrenids = {"builder_prediction_color"},
        }
        widgets[#widgets + 1] = {
            type = "color",
            name = L["SETTING_BUILDER_PREDICTION_COLOR"],
            desc = L["SETTING_BUILDER_PREDICTION_COLOR_DESC"],
            id = "builder_prediction_color",
            get = function()
                local c = component.GetSettings().builder_prediction_color
                return {private.Util.Color(c)}
            end,
            set = function(_, r, g, b, a)
                component.GetSettings().builder_prediction_color = {r, g, b, a}
                component.Refresh()
            end,
        }
        widgets[#widgets + 1] = {type = "blank"}
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_SKYRIDING_VIGOR"],
            desc = L["SETTING_SKYRIDING_VIGOR_DESC"],
            get = function() return component.GetSettings().skyriding_vigor end,
            set = function(_, _, value) component.GetSettings().skyriding_vigor = value; component.Refresh(); private.Anchor.OnComponentStateChange() end,
            children_follow_enabled = true,
            childrenids = {"skyriding_show_speed"},
        }
        widgets[#widgets + 1] = {
            type = "toggle",
            id = "skyriding_show_speed",
            name = L["SETTING_SKYRIDING_SHOW_SPEED"],
            desc = L["SETTING_SKYRIDING_SHOW_SPEED_DESC"],
            get = function() return component.GetSettings().skyriding_show_speed end,
            set = function(_, _, value) component.GetSettings().skyriding_show_speed = value end,
            disableif = function() return not component.GetSettings().skyriding_vigor end,
        }

        -- Class-specific features (right column)
        rightWidgets[#rightWidgets + 1] = {type = "label", get = function() return L["SECTION_CLASS_FEATURES"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_SORT_RUNES"],
            desc = L["SETTING_SORT_RUNES_DESC"],
            get = function() return component.GetSettings().sort_runes end,
            set = function(_, _, value) component.GetSettings().sort_runes = value; component.Refresh() end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_DRUID_CAT_FORM"],
            desc = L["SETTING_DRUID_CAT_FORM_DESC"],
            get = function() return component.GetSettings().druid_cat_form end,
            set = function(_, _, value) component.GetSettings().druid_cat_form = value; component.Refresh(); private.Anchor.OnComponentStateChange() end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_BREWMASTER_STAGGER"],
            desc = L["SETTING_BREWMASTER_STAGGER_DESC"],
            get = function() return component.GetSettings().brewmaster_stagger end,
            set = function(_, _, value)
                component.GetSettings().brewmaster_stagger = value
                private.SecondaryResources.ReevaluatePowerType()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_STAGGER_PIPS"],
            desc = L["SETTING_STAGGER_PIPS_DESC"],
            get = function() return component.GetSettings().stagger_pips end,
            set = function(_, _, value)
                component.GetSettings().stagger_pips = value
                component.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_BREWMASTER_VITALITY"],
            desc = L["SETTING_BREWMASTER_VITALITY_DESC"],
            get = function() return component.GetSettings().brewmaster_vitality end,
            set = function(_, _, value)
                component.GetSettings().brewmaster_vitality = value
                private.SecondaryResources.ReevaluatePowerType()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_MISTWEAVER_VITALITY"],
            desc = L["SETTING_MISTWEAVER_VITALITY_DESC"],
            get = function() return component.GetSettings().mistweaver_vitality end,
            set = function(_, _, value)
                component.GetSettings().mistweaver_vitality = value
                private.SecondaryResources.ReevaluatePowerType()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_MISTWEAVER_TEACHINGS"],
            desc = L["SETTING_MISTWEAVER_TEACHINGS_DESC"],
            get = function() return component.GetSettings().mistweaver_teachings end,
            set = function(_, _, value)
                component.GetSettings().mistweaver_teachings = value
                private.SecondaryResources.ReevaluatePowerType()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_ARMS_SWEEPING_STRIKES"],
            desc = L["SETTING_ARMS_SWEEPING_STRIKES_DESC"],
            get = function() return component.GetSettings().arms_sweeping_strikes end,
            set = function(_, _, value)
                component.GetSettings().arms_sweeping_strikes = value
                private.SecondaryResources.ReevaluatePowerType()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_MAGE_SHATTER_STACKS"],
            desc = L["SETTING_MAGE_SHATTER_STACKS_DESC"],
            get = function() return component.GetSettings().mage_shatter_stacks end,
            set = function(_, _, value)
                component.GetSettings().mage_shatter_stacks = value
                -- Refresh, not ReevaluatePowerType: this is an extra row, and
                -- ReevaluatePowerType compares only row 1's resource, so beside
                -- Icicles it would early-return and the row would never appear or
                -- leave. With Icicles off, Refresh hands the row-1 change to it.
                component.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_WARLOCK_WILD_IMPS"],
            desc = L["SETTING_WARLOCK_WILD_IMPS_DESC"],
            get = function() return component.GetSettings().warlock_wild_imps end,
            set = function(_, _, value)
                component.GetSettings().warlock_wild_imps = value
                -- Extra row: Refresh, not ReevaluatePowerType (see above).
                component.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_MAGE_ARCANE_SALVO_STACKS"],
            desc = L["SETTING_MAGE_ARCANE_SALVO_STACKS_DESC"],
            get = function() return component.GetSettings().mage_arcane_salvo_stacks end,
            set = function(_, _, value)
                component.GetSettings().mage_arcane_salvo_stacks = value
                -- Extra row: Refresh, not ReevaluatePowerType (see above).
                component.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_EVOKER_UNBOUND_FLAME"],
            desc = L["SETTING_EVOKER_UNBOUND_FLAME_DESC"],
            get = function() return component.GetSettings().evoker_unbound_flame end,
            set = function(_, _, value)
                component.GetSettings().evoker_unbound_flame = value
                -- Extra row: Refresh, not ReevaluatePowerType (see above).
                component.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_EVOKER_UNBOUND_FLAME_EXPIRY"],
            desc = L["SETTING_EVOKER_UNBOUND_FLAME_EXPIRY_DESC"],
            get = function() return component.GetSettings().evoker_unbound_flame_expiry end,
            set = function(_, _, value)
                component.GetSettings().evoker_unbound_flame_expiry = value
                component.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_DH_NEARBY_SOULS"],
            desc = L["SETTING_DH_NEARBY_SOULS_DESC"],
            get = function() return component.GetSettings().dh_nearby_souls end,
            set = function(_, _, value)
                component.GetSettings().dh_nearby_souls = value
                -- Extra row: Refresh, not ReevaluatePowerType (see above).
                component.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_DH_ART_OF_GLAIVE_HAVOC"],
            desc = L["SETTING_DH_ART_OF_GLAIVE_HAVOC_DESC"],
            get = function() return component.GetSettings().dh_art_of_glaive_havoc end,
            set = function(_, _, value)
                component.GetSettings().dh_art_of_glaive_havoc = value
                -- Havoc's PRIMARY, not an extra row -- the spec has no other
                -- secondary resource -- so this changes what
                -- getPlayerSecondaryPowerType resolves to and needs the full
                -- re-evaluation, unlike its two sibling toggles below.
                private.SecondaryResources.ReevaluatePowerType()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_DH_ART_OF_GLAIVE_VENGEANCE"],
            desc = L["SETTING_DH_ART_OF_GLAIVE_VENGEANCE_DESC"],
            get = function() return component.GetSettings().dh_art_of_glaive_vengeance end,
            set = function(_, _, value)
                component.GetSettings().dh_art_of_glaive_vengeance = value
                -- Extra row: Refresh, not ReevaluatePowerType (see above).
                component.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_DH_ART_OF_GLAIVE_DEVOURER"],
            desc = L["SETTING_DH_ART_OF_GLAIVE_DEVOURER_DESC"],
            get = function() return component.GetSettings().dh_art_of_glaive_devourer end,
            set = function(_, _, value)
                component.GetSettings().dh_art_of_glaive_devourer = value
                -- Extra row: Refresh, not ReevaluatePowerType (see above).
                component.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_FURY_WHIRLWIND"],
            desc = L["SETTING_FURY_WHIRLWIND_DESC"],
            get = function() return component.GetSettings().fury_whirlwind end,
            set = function(_, _, value)
                component.GetSettings().fury_whirlwind = value
                private.SecondaryResources.ReevaluatePowerType()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_PROTECTION_IGNORE_PAIN"],
            desc = L["SETTING_PROTECTION_IGNORE_PAIN_DESC"],
            get = function() return component.GetSettings().protection_ignore_pain end,
            set = function(_, _, value)
                component.GetSettings().protection_ignore_pain = value
                private.CDMDataSource.EnsureEnabled()
                private.SecondaryResources.ReevaluatePowerType()
            end,
            children_follow_enabled = true,
            childrenids = {"ip_time_bar"},
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            id = "ip_time_bar",
            name = L["SETTING_PROTECTION_IGNORE_PAIN_TIME_BAR"],
            desc = L["SETTING_PROTECTION_IGNORE_PAIN_TIME_BAR_DESC"],
            get = function() return component.GetSettings().protection_ignore_pain_time_bar end,
            set = function(_, _, value)
                component.GetSettings().protection_ignore_pain_time_bar = value
                private.SecondaryResources.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            id = "ip_pandemic",
            name = L["SETTING_PROTECTION_IGNORE_PAIN_PANDEMIC"],
            desc = L["SETTING_PROTECTION_IGNORE_PAIN_PANDEMIC_DESC"],
            get = function() return component.GetSettings().protection_ignore_pain_pandemic end,
            set = function(_, _, value)
                component.GetSettings().protection_ignore_pain_pandemic = value
                -- Native pandemic region: the setting is CONVERGED by
                -- ipState.syncPandemic (register/unregister), not re-read per
                -- frame, so the toggle needs a pass to land on.
                private.SecondaryResources.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_SURVIVAL_TIP_OF_THE_SPEAR"],
            desc = L["SETTING_SURVIVAL_TIP_OF_THE_SPEAR_DESC"],
            get = function() return component.GetSettings().survival_tip_of_the_spear end,
            set = function(_, _, value)
                component.GetSettings().survival_tip_of_the_spear = value
                private.SecondaryResources.ReevaluatePowerType()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_FROST_ICICLES"],
            desc = L["SETTING_FROST_ICICLES_DESC"],
            get = function() return component.GetSettings().frost_icicles end,
            set = function(_, _, value)
                component.GetSettings().frost_icicles = value
                private.SecondaryResources.ReevaluatePowerType()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_GUARDIAN_IRONFUR"],
            desc = L["SETTING_GUARDIAN_IRONFUR_DESC"],
            get = function() return component.GetSettings().guardian_ironfur end,
            set = function(_, _, value)
                component.GetSettings().guardian_ironfur = value
                private.SecondaryResources.ReevaluatePowerType()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_ENHANCEMENT_MAELSTROM_WEAPON"],
            desc = L["SETTING_ENHANCEMENT_MAELSTROM_WEAPON_DESC"],
            get = function() return component.GetSettings().enhancement_maelstrom_weapon end,
            set = function(_, _, value)
                component.GetSettings().enhancement_maelstrom_weapon = value
                private.SecondaryResources.ReevaluatePowerType()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_ENHANCEMENT_MW_THRESHOLD"],
            desc = L["SETTING_ENHANCEMENT_MW_THRESHOLD_DESC"],
            get = function() return component.GetSettings().enhancement_mw_threshold end,
            set = function(_, _, value)
                component.GetSettings().enhancement_mw_threshold = value
                private.SecondaryResources.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_ROGUE_COUP_DE_GRACE"],
            desc = L["SETTING_ROGUE_COUP_DE_GRACE_DESC"],
            get = function() return component.GetSettings().rogue_coup_de_grace end,
            set = function(_, _, value)
                component.GetSettings().rogue_coup_de_grace = value
                private.SecondaryResources.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_FIRE_BLAST_CHARGES"],
            desc = L["SETTING_FIRE_BLAST_CHARGES_DESC"],
            get = function() return component.GetSettings().fire_blast_charges end,
            set = function(_, _, value)
                component.GetSettings().fire_blast_charges = value
                private.SecondaryResources.ReevaluatePowerType()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_DISCIPLINE_RADIANCE_CHARGES"],
            desc = L["SETTING_DISCIPLINE_RADIANCE_CHARGES_DESC"],
            get = function() return component.GetSettings().discipline_radiance_charges end,
            set = function(_, _, value)
                component.GetSettings().discipline_radiance_charges = value
                private.SecondaryResources.ReevaluatePowerType()
            end,
        }
        -- Last in the section on purpose: this is the one setting here that is
        -- NOT per-spec. It governs how every stack strip above renders --
        -- discrete pips or one continuous fill -- so it reads as a footer to
        -- the list rather than as another class toggle wedged among them.
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_STACK_STRIP_SEGMENTED"],
            desc = L["SETTING_STACK_STRIP_SEGMENTED_DESC"],
            get = function() return component.GetSettings().stack_strip_segmented ~= false end,
            set = function(_, _, value)
                component.GetSettings().stack_strip_segmented = value
                -- Refresh, not ReevaluatePowerType: the power type is unchanged,
                -- so ReevaluatePowerType would early-return. Refresh re-runs
                -- refreshResourceCount (new host-segment count) and
                -- updateStackPips, whose guard then releases and rebuilds the
                -- pip set at the new count.
                component.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        -- The aura-fed ammo overlay and the VM-gated CS pip are blocked (aura
        -- data locked down), so their color pickers are not offered. The
        -- preview slab (engine-side fill-seam + non-secret cap math) and the
        -- forecast text still work and keep their options.
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_DEVOURER_REAP_FORECAST"],
            desc = L["SETTING_DEVOURER_REAP_FORECAST_DESC"],
            get = function() return component.GetSettings().devourer_reap_forecast end,
            set = function(_, _, value)
                component.GetSettings().devourer_reap_forecast = value
                component.Refresh()
            end,
            children_follow_enabled = true,
            childrenids = {
                "devourer_reap_forecast_show_text",
                "devourer_reap_preview_color",
                "devourer_reap_ammo_color",
                "devourer_reap_pip_color",
            },
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            id = "devourer_reap_forecast_show_text",
            name = L["SETTING_DEVOURER_REAP_FORECAST_SHOW_TEXT"],
            desc = L["SETTING_DEVOURER_REAP_FORECAST_SHOW_TEXT_DESC"],
            get = function() return component.GetSettings().devourer_reap_forecast_show_text end,
            set = function(_, _, value)
                component.GetSettings().devourer_reap_forecast_show_text = value
                component.Refresh()
            end,
            disableif = function() return not component.GetSettings().devourer_reap_forecast end,
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "color",
            id = "devourer_reap_preview_color",
            name = L["SETTING_DEVOURER_REAP_PREVIEW_COLOR"],
            desc = L["SETTING_DEVOURER_REAP_PREVIEW_COLOR_DESC"],
            get = function()
                local c = component.GetSettings().devourer_reap_preview_color
                return {c[1], c[2], c[3], c[4] or 0.55}
            end,
            set = function(_, r, g, b, a)
                component.GetSettings().devourer_reap_preview_color = {r, g, b, a}
                component.Refresh()
            end,
            disableif = function() return not component.GetSettings().devourer_reap_forecast end,
        }
        -- These two used to sit behind a `>= 120100` gate that hid them on every
        -- shipping client, on the theory that 12.1 had blocked the visuals they
        -- colour. Both readers are live: the ammo colour goes onto the bound
        -- aura-tap bar (`auraTap.bars["reapammo"]`) and the pip colour onto
        -- `reapFc.pipCS`, in `reapFc.applyColors`.
        rightWidgets[#rightWidgets + 1] = {
            type = "color",
            id = "devourer_reap_ammo_color",
            name = L["SETTING_DEVOURER_REAP_AMMO_COLOR"],
            desc = L["SETTING_DEVOURER_REAP_AMMO_COLOR_DESC"],
            get = function()
                local c = component.GetSettings().devourer_reap_ammo_color
                return {private.Util.Color(c)}
            end,
            set = function(_, r, g, b, a)
                component.GetSettings().devourer_reap_ammo_color = {r, g, b, a}
                component.Refresh()
            end,
            disableif = function() return not component.GetSettings().devourer_reap_forecast end,
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "color",
            id = "devourer_reap_pip_color",
            name = L["SETTING_DEVOURER_REAP_PIP_COLOR"],
            desc = L["SETTING_DEVOURER_REAP_PIP_COLOR_DESC"],
            get = function()
                local c = component.GetSettings().devourer_reap_pip_color
                return {c[1], c[2], c[3], c[4] or 0.9}
            end,
            set = function(_, r, g, b, a)
                component.GetSettings().devourer_reap_pip_color = {r, g, b, a}
                component.Refresh()
            end,
            disableif = function() return not component.GetSettings().devourer_reap_forecast end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_MARKSMAN_AIMED_SHOT"],
            desc = L["SETTING_MARKSMAN_AIMED_SHOT_DESC"],
            get = function() return component.GetSettings().marksman_aimed_shot end,
            set = function(_, _, value)
                component.GetSettings().marksman_aimed_shot = value
                private.SecondaryResources.ReevaluatePowerType()
            end,
            children_follow_enabled = true,
            childrenids = {"marksman_lock_and_load"},
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            id = "marksman_lock_and_load",
            name = L["SETTING_MARKSMAN_LOCK_AND_LOAD"],
            desc = L["SETTING_MARKSMAN_LOCK_AND_LOAD_DESC"],
            get = function() return component.GetSettings().marksman_lock_and_load end,
            set = function(_, _, value)
                component.GetSettings().marksman_lock_and_load = value
                private.CDMDataSource.EnsureEnabled()
                component.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_EVOKER_ESSENCE_BURST"],
            desc = L["SETTING_EVOKER_ESSENCE_BURST_DESC"],
            get = function() return component.GetSettings().evoker_essence_burst end,
            set = function(_, _, value)
                component.GetSettings().evoker_essence_burst = value
                private.CDMDataSource.EnsureEnabled()
                component.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "color",
            id = "evoker_essence_burst_color",
            name = L["SETTING_EVOKER_ESSENCE_BURST_COLOR"],
            desc = L["SETTING_EVOKER_ESSENCE_BURST_COLOR_DESC"],
            get = function()
                local c = component.GetSettings().evoker_essence_burst_color
                return {private.Util.Color(c)}
            end,
            set = function(_, r, g, b, a)
                component.GetSettings().evoker_essence_burst_color = {r, g, b, a}
                component.Refresh()
            end,
            -- Shared by two independent features: the burst tap AND the spender
            -- prediction border (essencePred.applyBorder reads this colour and
            -- gates only on evoker_essence_prediction).  Greying it out on the
            -- burst toggle alone locked the picker in a state where the colour
            -- was still on screen — the prediction setting's own description
            -- says as much ("The highlight shares the Essence Burst color").
            disableif = function()
                local s = component.GetSettings()
                return not (s.evoker_essence_burst or s.evoker_essence_prediction)
            end,
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_EVOKER_ESSENCE_PREDICTION"],
            desc = L["SETTING_EVOKER_ESSENCE_PREDICTION_DESC"],
            get = function() return component.GetSettings().evoker_essence_prediction end,
            set = function(_, _, value)
                component.GetSettings().evoker_essence_prediction = value
                private.CDMDataSource.EnsureEnabled()
                component.Refresh()
            end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_PALADIN_SWING_TIMER"],
            desc = L["SETTING_PALADIN_SWING_TIMER_DESC"],
            get = function() return component.GetSettings().paladin_swing_timer end,
            set = function(_, _, value)
                component.GetSettings().paladin_swing_timer = value
                component.Refresh()
            end,
            children_follow_enabled = true,
            childrenids = {"paladin_swing_custom_color", "paladin_swing_color", "paladin_swing_overflow"},
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            id = "paladin_swing_custom_color",
            name = L["SETTING_PALADIN_SWING_CUSTOM_COLOR"],
            desc = L["SETTING_PALADIN_SWING_CUSTOM_COLOR_DESC"],
            get = function() return component.GetSettings().paladin_swing_custom_color end,
            set = function(_, _, value)
                component.GetSettings().paladin_swing_custom_color = value
                component.Refresh()
            end,
            disableif = function() return not component.GetSettings().paladin_swing_timer end,
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "color",
            id = "paladin_swing_color",
            name = L["SETTING_PALADIN_SWING_COLOR"],
            desc = L["SETTING_PALADIN_SWING_COLOR_DESC"],
            get = function()
                local c = component.GetSettings().paladin_swing_color
                return {private.Util.Color(c)}
            end,
            set = function(_, r, g, b, a)
                component.GetSettings().paladin_swing_color = {r, g, b, a}
                component.Refresh()
            end,
            disableif = function() return not component.GetSettings().paladin_swing_timer or not component.GetSettings().paladin_swing_custom_color end,
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            id = "paladin_swing_overflow",
            name = L["SETTING_PALADIN_SWING_OVERFLOW"],
            desc = L["SETTING_PALADIN_SWING_OVERFLOW_DESC"],
            get = function() return component.GetSettings().paladin_swing_overflow end,
            set = function(_, _, value)
                component.GetSettings().paladin_swing_overflow = value
                component.Refresh()
            end,
            disableif = function() return not component.GetSettings().paladin_swing_timer end,
            children_follow_enabled = true,
            childrenids = {"paladin_swing_overflow_glow"},
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            id = "paladin_swing_overflow_glow",
            name = L["SETTING_PALADIN_SWING_OVERFLOW_GLOW"],
            desc = L["SETTING_PALADIN_SWING_OVERFLOW_GLOW_DESC"],
            get = function() return component.GetSettings().paladin_swing_overflow_glow end,
            set = function(_, _, value)
                component.GetSettings().paladin_swing_overflow_glow = value
                component.Refresh()
            end,
            disableif = function() return not component.GetSettings().paladin_swing_timer or not component.GetSettings().paladin_swing_overflow end,
        }
        rightWidgets[#rightWidgets + 1] = {type = "blank"}
        rightWidgets[#rightWidgets + 1] = {
            type = "toggle",
            name = L["SETTING_PALADIN_DIVINE_PURPOSE"],
            desc = L["SETTING_PALADIN_DIVINE_PURPOSE_DESC"],
            get = function() return component.GetSettings().paladin_divine_purpose end,
            set = function(_, _, value)
                component.GetSettings().paladin_divine_purpose = value
                private.CDMDataSource.EnsureEnabled()
                component.Refresh()
            end,
            children_follow_enabled = true,
            childrenids = {"paladin_divine_purpose_color"},
        }
        rightWidgets[#rightWidgets + 1] = {
            type = "color",
            id = "paladin_divine_purpose_color",
            name = L["SETTING_PALADIN_DIVINE_PURPOSE_COLOR"],
            desc = L["SETTING_PALADIN_DIVINE_PURPOSE_COLOR_DESC"],
            get = function()
                local c = component.GetSettings().paladin_divine_purpose_color
                return {private.Util.Color(c)}
            end,
            set = function(_, r, g, b, a)
                component.GetSettings().paladin_divine_purpose_color = {r, g, b, a}
                component.Refresh()
            end,
            disableif = function() return not component.GetSettings().paladin_divine_purpose end,
        }
    end

    -- Text format mana / other (primary resources)
    if component.GetSettings().text_format_mana ~= nil then
        local manaOnClick = function(_, _, value) component.GetSettings().text_format_mana = value; component.Refresh() end
        local textFormatValues = function()
            return {
                {label = L["TEXT_FORMAT_PERCENT"], value = "percent", onclick = manaOnClick},
                {label = L["TEXT_FORMAT_CURRENT"], value = "current", onclick = manaOnClick},
                {label = L["TEXT_FORMAT_BOTH"], value = "both", onclick = manaOnClick},
                {label = L["TEXT_FORMAT_NONE"], value = "none", onclick = manaOnClick},
            }
        end
        widgets[#widgets + 1] = {
            type = "select",
            name = L["SETTING_TEXT_FORMAT_MANA"],
            desc = L["SETTING_TEXT_FORMAT_MANA_DESC"],
            get = function() return component.GetSettings().text_format_mana end,
            set = function(_, _, value) component.GetSettings().text_format_mana = value; component.Refresh() end,
            values = textFormatValues,
        }
    end
    if component.GetSettings().text_format_other ~= nil then
        local otherOnClick = function(_, _, value) component.GetSettings().text_format_other = value; component.Refresh() end
        local textFormatValues = function()
            return {
                {label = L["TEXT_FORMAT_PERCENT"], value = "percent", onclick = otherOnClick},
                {label = L["TEXT_FORMAT_CURRENT"], value = "current", onclick = otherOnClick},
                {label = L["TEXT_FORMAT_BOTH"], value = "both", onclick = otherOnClick},
                {label = L["TEXT_FORMAT_NONE"], value = "none", onclick = otherOnClick},
            }
        end
        widgets[#widgets + 1] = {
            type = "select",
            name = L["SETTING_TEXT_FORMAT_OTHER"],
            desc = L["SETTING_TEXT_FORMAT_OTHER_DESC"],
            get = function() return component.GetSettings().text_format_other end,
            set = function(_, _, value) component.GetSettings().text_format_other = value; component.Refresh() end,
            values = textFormatValues,
        }
    end

    -- Active aura glow + pandemic glow suite (all viewer trackers)
    if component.GetSettings().pandemic_glow ~= nil then
        -- Not hidden under groups: the glow is a region bound into the aura
        -- button's subtree, so the engine drives it without any button-to-spell
        -- binding — unlike proc_glow, which still needs one.
        widgets[#widgets + 1] = {type = "blank"}
        widgets[#widgets + 1] = {type = "label", get = function() return L["GLOW_HEADER_ACTIVE_AURA"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_ACTIVE_GLOW"],
            desc = L["SETTING_ACTIVE_GLOW_DESC"],
            get = function() return component.GetSettings().active_glow end,
            -- fontsDirty gate: the glow's on/off and colour are applied by the
            -- per-button restyle pass, which Refresh only runs when the flag is
            -- set (patterns.md "fontsDirty").
            set = function(_, _, value)
                component.GetSettings().active_glow = value
                -- Reconcile, not an enable: active_glow no longer counts toward
                -- needsViewerChildren, so switching it OFF is now a case that can
                -- turn the CDM CVar off outright.
                private.CDMDataSource.EnsureEnabled()
                private.fontsDirty = true
                component.Refresh()
                private.fontsDirty = false
            end,
        }
        widgets[#widgets + 1] = {
            type = "color",
            name = L["SETTING_ACTIVE_GLOW_COLOR"],
            desc = L["SETTING_ACTIVE_GLOW_COLOR_DESC"],
            get = function()
                local c = component.GetSettings().active_glow_color
                return {private.Util.Color(c)}
            end,
            set = function(_, r, g, b, a)
                component.GetSettings().active_glow_color = {r, g, b, a}
                private.fontsDirty = true
                component.Refresh()
                private.fontsDirty = false
            end,
            disableif = function() return not component.GetSettings().active_glow end,
        }
        widgets[#widgets + 1] = {type = "blank"}
        widgets[#widgets + 1] = {type = "label", get = function() return L["GLOW_HEADER_PANDEMIC"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
        widgets[#widgets + 1] = {
            type = "toggle",
            name = L["SETTING_PANDEMIC_GLOW"],
            desc = L["SETTING_PANDEMIC_GLOW_DESC"],
            get = function() return component.GetSettings().pandemic_glow end,
            set = function(_, _, value) component.GetSettings().pandemic_glow = value; component.Refresh() end,
        }
        -- The urgency colors and the two threshold sliders are deliberately not
        -- offered: the window and the fade belong to Blizzard's own pandemic
        -- region, which has no readable remaining-%.  Nothing offers them any
        -- more — the Additional Frame panel kept them for a DurationObject-curve
        -- renderer that no longer exists.
        widgets[#widgets + 1] = {
            type = "select",
            name = L["SETTING_PANDEMIC_GLOW_STYLE"],
            desc = L["SETTING_PANDEMIC_GLOW_STYLE_DESC"],
            -- Only the two border variants: the cue on these trackers is a
            -- static border drawn inside an aura button's subtree, where no
            -- animated style can run (see Core/AuraContainer.lua).
            values = function()
                return {
                    {label = L["PANDEMIC_STYLE_BORDER"], value = "border", onclick = function()
                        component.GetSettings().pandemic_glow_style = "border"
                        component.Refresh()
                    end},
                    {label = L["PANDEMIC_STYLE_BORDER_INSIDE"], value = "border_inside", onclick = function()
                        component.GetSettings().pandemic_glow_style = "border_inside"
                        component.Refresh()
                    end},
                }
            end,
            -- A profile carrying one of the retired animated styles reads back
            -- as the outside border, which is what it now renders as.
            get = function()
                local st = component.GetSettings().pandemic_glow_style
                return st == "border_inside" and "border_inside" or "border"
            end,
            set = function(_, _, value) component.GetSettings().pandemic_glow_style = value; component.Refresh() end,
            disableif = function() return not component.GetSettings().pandemic_glow end,
        }
        widgets[#widgets + 1] = {
            type = "color",
            name = L["SETTING_PANDEMIC_GLOW_COLOR"],
            desc = L["SETTING_PANDEMIC_GLOW_COLOR_DESC"],
            get = function()
                local c = component.GetSettings().pandemic_glow_color
                return {private.Util.Color(c)}
            end,
            set = function(_, r, g, b, a)
                component.GetSettings().pandemic_glow_color = {r, g, b, a}
                component.Refresh()
            end,
            disableif = function() return not component.GetSettings().pandemic_glow end,
        }
        widgets[#widgets + 1] = {
            type = "range",
            name = L["SETTING_PANDEMIC_GLOW_THICKNESS"],
            desc = L["SETTING_PANDEMIC_GLOW_THICKNESS_DESC"],
            min = 1, max = 6, step = 1,
            get = function() return component.GetSettings().pandemic_glow_thickness or 2 end,
            set = function(_, _, value) component.GetSettings().pandemic_glow_thickness = value; component.Refresh() end,
            disableif = function() return not component.GetSettings().pandemic_glow end,
        }
        if component.GetSettings().cdm_glow_color ~= nil then
            widgets[#widgets + 1] = {
                type = "color",
                name = L["SETTING_CDM_GLOW_COLOR"],
                desc = L["SETTING_CDM_GLOW_COLOR_DESC"],
                get = function()
                    local c = component.GetSettings().cdm_glow_color
                    return {private.Util.Color(c)}
                end,
                -- No push needed: PlayReadyFlash re-tints from the live
                -- setting on every flash, so the next one picks this up.
                set = function(_, r, g, b, a)
                    component.GetSettings().cdm_glow_color = {r, g, b, a}
                end,
            }
        end

    end

    -- Proc glow (CooldownTracker, UtilitiesTracker, BuffTracker, BuffTrackerBars)
    if component.GetSettings().proc_glow_style ~= nil and not groupsEngine then
        widgets[#widgets + 1] = {type = "blank"}
        widgets[#widgets + 1] = {type = "label", get = function() return L["PROC_GLOW_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
        widgets[#widgets + 1] = {
            type = "select",
            name = L["PROC_GLOW_STYLE"],
            desc = L["PROC_GLOW_STYLE_DESC"],
            values = function()
                return {
                    {label = L["PROC_STYLE_BLIZZARD"], value = "blizzard", onclick = function()
                        component.GetSettings().proc_glow_style = "blizzard"
                        component.Refresh()
                    end},
                    {label = L["PROC_STYLE_BORDER"], value = "border", onclick = function()
                        component.GetSettings().proc_glow_style = "border"
                        component.Refresh()
                    end},
                    {label = L["PROC_STYLE_BORDER_INSIDE"], value = "border_inside", onclick = function()
                        component.GetSettings().proc_glow_style = "border_inside"
                        component.Refresh()
                    end},
                    {label = L["PROC_STYLE_ANTS"], value = "ants", onclick = function()
                        component.GetSettings().proc_glow_style = "ants"
                        component.Refresh()
                    end},
                    {label = L["PROC_STYLE_AUTOCAST"], value = "autocast", onclick = function()
                        component.GetSettings().proc_glow_style = "autocast"
                        component.Refresh()
                    end},
                    {label = L["PROC_STYLE_PIXEL"], value = "pixel", onclick = function()
                        component.GetSettings().proc_glow_style = "pixel"
                        component.Refresh()
                    end},
                    {label = L["PROC_STYLE_NONE"], value = "none", onclick = function()
                        component.GetSettings().proc_glow_style = "none"
                        component.Refresh()
                    end},
                }
            end,
            get = function() return component.GetSettings().proc_glow_style or "blizzard" end,
            set = function(_, _, value) component.GetSettings().proc_glow_style = value; component.Refresh() end,
        }
        widgets[#widgets + 1] = {
            type = "color",
            name = L["PROC_GLOW_COLOR"],
            desc = L["PROC_GLOW_COLOR_DESC"],
            get = function()
                local c = component.GetSettings().proc_glow_color
                return {private.Util.Color(c)}
            end,
            set = function(_, r, g, b, a)
                component.GetSettings().proc_glow_color = {r, g, b, a}
                component.Refresh()
            end,
            disableif = function() return component.GetSettings().proc_glow_style == "none" end,
        }
        widgets[#widgets + 1] = {
            type = "range",
            name = L["PROC_GLOW_ALPHA"],
            desc = L["PROC_GLOW_ALPHA_DESC"],
            min = 0, max = 100, step = 5,
            get = function() return component.GetSettings().proc_glow_alpha or 100 end,
            set = function(_, _, value) component.GetSettings().proc_glow_alpha = value; component.Refresh() end,
            disableif = function() return component.GetSettings().proc_glow_style == "none" end,
        }
        widgets[#widgets + 1] = {
            type = "range",
            name = L["PROC_GLOW_THICKNESS"],
            desc = L["PROC_GLOW_THICKNESS_DESC"],
            min = 1, max = 6, step = 1,
            get = function() return component.GetSettings().proc_glow_thickness or 2 end,
            set = function(_, _, value) component.GetSettings().proc_glow_thickness = value; component.Refresh() end,
            disableif = function()
                local style = component.GetSettings().proc_glow_style
                return not (style == "border" or style == "border_inside"
                         or style == "pixel"  or style == "autocast")
            end,
        }
    end

    return {left = widgets, right = rightWidgets}
end

---Build font setting widgets for a specific component, gathering all its font groups.
---@param componentName string
---@param component component
---@return table[]
local function buildTrackerFontWidgets(componentName, component)
    local widgets = {}
    local refreshFn = function()
        private.fontsDirty = true
        component.Refresh()
        private.fontsDirty = false
    end

    -- Determine which font keys exist for this component
    local settings = component.GetSettings()

    -- GCD bar: duration_font + spell_name_font
    if settings.duration_font and settings.spell_name_font and not settings.cast_name_font and not settings.name_font then
        appendWidgets(widgets, fontGroupWidgets(componentName, "duration_font", L["SETTING_GCD_DURATION_TEXT"], 24, refreshFn, true))
        appendWidgets(widgets, fontGroupWidgets(componentName, "spell_name_font", L["SETTING_GCD_SPELL_NAME_TEXT"], 24, refreshFn, true))
    end

    -- Cast bars: cast_name_font + cast_time_font
    if settings.cast_name_font then
        appendWidgets(widgets, fontGroupWidgets(componentName, "cast_name_font", L["SETTING_CAST_NAME_TEXT"], 24, refreshFn, true))
        appendWidgets(widgets, fontGroupWidgets(componentName, "cast_time_font", L["SETTING_CAST_TIME_TEXT"], 24, refreshFn, true))
    end

    -- Resource/health bars: value_font
    if settings.value_font and not settings.cast_name_font then
        appendWidgets(widgets, fontGroupWidgets(componentName, "value_font", L["SETTING_VALUE_TEXT"], 24, refreshFn, true))
    end

    -- Icon trackers: timer_font + stacks_font
    if settings.timer_font then
        appendWidgets(widgets, fontGroupWidgets(componentName, "timer_font", L["SETTING_TIMER_TEXT"], 32, refreshFn, true))
        if settings.stacks_font then
            appendWidgets(widgets, fontGroupWidgets(componentName, "stacks_font", L["SETTING_STACKS_TEXT"], 32, refreshFn, true))
        end
    end

    -- Bar tracker: name_font + duration_font + stacks_font
    if settings.name_font then
        appendWidgets(widgets, fontGroupWidgets(componentName, "name_font", L["SETTING_NAME_TEXT"], 24, refreshFn, true))
        if settings.duration_font then
            appendWidgets(widgets, fontGroupWidgets(componentName, "duration_font", L["SETTING_DURATION_TEXT"], 24, refreshFn, true))
        end
        if settings.stacks_font and not settings.timer_font then
            appendWidgets(widgets, fontGroupWidgets(componentName, "stacks_font", L["SETTING_STACKS_TEXT"], 32, refreshFn, true))
        end
    end

    -- Consumable/Trinket: count_font + duration_font (without name_font)
    if settings.count_font and not settings.name_font then
        appendWidgets(widgets, fontGroupWidgets(componentName, "count_font", L["SETTING_COUNT_TEXT"], 24, refreshFn, true))
    end
    if settings.duration_font and not settings.name_font and not settings.timer_font and not settings.spell_name_font then
        appendWidgets(widgets, fontGroupWidgets(componentName, "duration_font", L["SETTING_DURATION_TEXT"], 24, refreshFn, true))
    end

    -- Keybind font
    if settings.keybind_font then
        appendWidgets(widgets, keybindFontGroupWidgets(componentName, L["SETTING_KEYBIND_TEXT"], 32, refreshFn))
    end

    if #widgets > 0 then
        table.insert(widgets, 1, {type = "label", get = function() return L["SECTION_FONTS"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color})
    end

    return widgets
end

---Build the breakpoint pips custom UI on a scroll child, anchored below BuildMenu content.
---@param parent frame  the scroll child to build on
---@param yOffset number  Y offset from TOPLEFT of parent where the section starts
---@param parentWidth number  available width for the section
---@param target "primary"|"secondary"|nil  which bar's pip list to edit (default "primary")
local function buildBreakpointPipsSection(parent, yOffset, parentWidth, target)
    target = target or "primary"
    local pipSettings = private.profile.breakpoint_pips
    local buttonTemplate = private.Templates.ButtonTemplate
    local orangeTemplate = orangeFontTemplate

    local populatePipList

    ---Storage key + explicit power type for the edited bar. nil powerType =
    ---use the player's current power (non-moved specs on the primary bar).
    local function getSpecKey()
        return private.BreakpointPips.GetKeyForCurrentSpec(target)
    end

    ---Both editor sections (primary tab / secondary tab) share the
    ---breakpoint_pips globals (enabled, width, mode, ...), so every setter
    ---refreshes both components — a change here must not leave stale pips on
    ---the other bar.
    local function refreshPips()
        private.PrimaryResources.Refresh()
        private.SecondaryResources.Refresh()
    end

    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    container:SetSize(parentWidth, 400)

    -- Header
    local pipHeader = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pipHeader:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    if orangeTemplate and orangeTemplate.color then
        pipHeader:SetTextColor(unpack(orangeTemplate.color))
    end
    pipHeader:SetText(target == "secondary" and L["BREAKPOINT_PIPS_HEADER_SECONDARY"] or L["BREAKPOINT_PIPS_HEADER"])

    -- Enable toggle
    local pipToggle = framework:CreateSwitch(container, function(_, _, value)
        private.profile.breakpoint_pips.enabled = value
        refreshPips()
        if populatePipList then populatePipList() end
    end, pipSettings.enabled, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        framework:GetTemplate("switch", private.UIDefaults.presets.checkbox))
    pipToggle:SetPoint("TOPLEFT", pipHeader, "BOTTOMLEFT", 0, -8)
    pipToggle:SetAsCheckBox()
    pipToggle:SetTooltip(L["BREAKPOINT_PIPS_ENABLED_DESC"])

    local pipToggleLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pipToggleLabel:SetPoint("LEFT", pipToggle.widget, "RIGHT", 5, 0)
    pipToggleLabel:SetText(L["BREAKPOINT_PIPS_ENABLED"])

    -- Per-spec enable toggle (missing key = enabled)
    local function getPipEnabledMap()
        local bp = private.profile.breakpoint_pips
        if type(bp.per_spec_enabled) ~= "table" then
            bp.per_spec_enabled = {}
        end
        return bp.per_spec_enabled
    end

    local function isPipSpecEnabled(key)
        if not key then return true end
        return getPipEnabledMap()[key] ~= false
    end

    local specToggle = framework:CreateSwitch(container, function(_, _, value)
        local key = getSpecKey()
        if not key then return end
        getPipEnabledMap()[key] = value and true or false
        refreshPips()
    end, isPipSpecEnabled(getSpecKey()), nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        framework:GetTemplate("switch", private.UIDefaults.presets.checkbox))
    specToggle:SetPoint("TOPLEFT", pipToggle.widget, "BOTTOMLEFT", 0, -8)
    specToggle:SetAsCheckBox()
    specToggle:SetTooltip(L["BREAKPOINT_PIPS_SPEC_ENABLED_DESC"])

    local specToggleLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    specToggleLabel:SetPoint("LEFT", specToggle.widget, "RIGHT", 5, 0)
    specToggleLabel:SetText(L["BREAKPOINT_PIPS_SPEC_ENABLED"])

    local function refreshSpecToggle()
        specToggle:SetValue(isPipSpecEnabled(getSpecKey()))
    end

    local disabledColor = {0.5, 0.5, 0.5}
    local enabledColor = {1, 1, 1}

    -- Pip width slider
    local pipWidthLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pipWidthLabel:SetPoint("TOPLEFT", specToggle.widget, "BOTTOMLEFT", 0, -12)
    pipWidthLabel:SetText(L["BREAKPOINT_PIP_WIDTH"])

    local pipWidthSlider = framework:CreateSlider(container, 140, 20, 1, 6, 1,
        pipSettings.pip_width or 2, false, nil, nil, nil,
        framework:GetTemplate("slider", private.UIDefaults.presets.slider))
    pipWidthSlider:SetPoint("LEFT", pipWidthLabel, "RIGHT", 10, 0)
    pipWidthSlider:SetHook("OnValueChanged", function(_, _, value)
        private.profile.breakpoint_pips.pip_width = value
        refreshPips()
    end)

    -- Show pip line toggle
    local pipLineToggle = framework:CreateSwitch(container, function(_, _, value)
        private.profile.breakpoint_pips.show_pip_line = value
        refreshPips()
    end, pipSettings.show_pip_line ~= false, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        framework:GetTemplate("switch", private.UIDefaults.presets.checkbox))
    pipLineToggle:SetPoint("TOPLEFT", pipWidthLabel, "BOTTOMLEFT", 0, -12)
    pipLineToggle:SetAsCheckBox()
    pipLineToggle:SetTooltip(L["BREAKPOINT_PIP_SHOW_LINE_DESC"])

    local pipLineLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pipLineLabel:SetPoint("LEFT", pipLineToggle.widget, "RIGHT", 5, 0)
    pipLineLabel:SetText(L["BREAKPOINT_PIP_SHOW_LINE"])

    -- Zone auto-hide toggle
    local zoneAutoHideToggle = framework:CreateSwitch(container, function(_, _, value)
        private.profile.breakpoint_pips.zone_auto_hide = value
        refreshPips()
    end, pipSettings.zone_auto_hide ~= false, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        framework:GetTemplate("switch", private.UIDefaults.presets.checkbox))
    zoneAutoHideToggle:SetPoint("TOPLEFT", pipLineToggle.widget, "BOTTOMLEFT", 0, -12)
    zoneAutoHideToggle:SetAsCheckBox()
    zoneAutoHideToggle:SetTooltip(L["BREAKPOINT_PIP_ZONE_AUTO_HIDE_DESC"])

    local zoneAutoHideLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    zoneAutoHideLabel:SetPoint("LEFT", zoneAutoHideToggle.widget, "RIGHT", 5, 0)
    zoneAutoHideLabel:SetText(L["BREAKPOINT_PIP_ZONE_AUTO_HIDE"])

    -- Fill interpolation dropdown
    local fillInterpDropdown = framework:CreateDropDown(container, function()
        return {
            {label = "Step", value = "step", onclick = function(_, _, value) private.profile.breakpoint_pips.fill_interpolation = value; refreshPips() end},
            {label = "Linear", value = "linear", onclick = function(_, _, value) private.profile.breakpoint_pips.fill_interpolation = value; refreshPips() end},
        }
    end, 1, nil, nil, nil, nil, framework:GetTemplate("dropdown", private.UIDefaults.presets.dropdown))
    fillInterpDropdown:SetPoint("TOPLEFT", zoneAutoHideToggle.widget, "BOTTOMLEFT", 0, -12)
    fillInterpDropdown:SetSize(120, 20)
    fillInterpDropdown:SetTooltip(L["BREAKPOINT_FILL_INTERPOLATION_DESC"])
    fillInterpDropdown:Select(pipSettings.fill_interpolation == "linear" and "linear" or "step")

    local fillInterpLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fillInterpLabel:SetPoint("LEFT", fillInterpDropdown.widget, "RIGHT", 5, 0)
    fillInterpLabel:SetText(L["BREAKPOINT_FILL_INTERPOLATION"])

    -- Pip mode dropdown (percent vs absolute)
    local pipModeDropdown = framework:CreateDropDown(container, function()
        return {
            {label = "Percent", value = "percent", onclick = function(_, _, value) private.profile.breakpoint_pips.pip_mode = value; refreshPips(); if populatePipList then populatePipList() end end},
            {label = "Absolute", value = "absolute", onclick = function(_, _, value) private.profile.breakpoint_pips.pip_mode = value; refreshPips(); if populatePipList then populatePipList() end end},
        }
    end, 1, nil, nil, nil, nil, framework:GetTemplate("dropdown", private.UIDefaults.presets.dropdown))
    pipModeDropdown:SetPoint("TOPLEFT", fillInterpDropdown.widget, "BOTTOMLEFT", 0, -12)
    pipModeDropdown:SetSize(120, 20)
    pipModeDropdown:SetTooltip(L["BREAKPOINT_PIP_MODE_DESC"])
    pipModeDropdown:Select(pipSettings.pip_mode == "absolute" and "absolute" or "percent")

    local pipModeLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pipModeLabel:SetPoint("LEFT", pipModeDropdown.widget, "RIGHT", 5, 0)
    pipModeLabel:SetText(L["BREAKPOINT_PIP_MODE"])

    -- Spec label
    local specLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    specLabel:SetPoint("TOPLEFT", pipModeDropdown.widget, "BOTTOMLEFT", 0, -16)

    local function updateSpecLabel()
        local specIndex = C_SpecializationInfo.GetSpecialization()
        local label = private.GetLocalizedClassSpecLabel(nil, specIndex)
        specLabel:SetText(format(L["BREAKPOINT_PIPS_SPEC_LABEL"], label ~= "" and label or "Unknown"))
    end
    updateSpecLabel()

    -- Unregister events when hidden (prevents stale handlers on orphaned scroll children)
    container:RegisterEvent("PLAYER_TALENT_UPDATE")
    container:SetScript("OnEvent", function()
        -- Secondary section: the new spec may have no continuous bar — hide
        -- rather than leave a dead editor. (Switching back onto a moved spec
        -- requires a page rebuild, same as every conditionally-built section.)
        if target == "secondary" and not getSpecKey() then
            container:Hide()
            return
        end
        updateSpecLabel()
        refreshSpecToggle()
        populatePipList()
    end)
    container:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
    end)

    -- Add pip controls. Absolute mode ranges on the edited bar's power —
    -- explicit for the moved specs (mana / continuous resource), the player's
    -- current power otherwise (nil powerType = default UnitPowerMax behavior).
    local isAbsolute = pipSettings.pip_mode == "absolute"
    local _, editedPower = getSpecKey()
    local sliderMax = isAbsolute and math.max(UnitPowerMax("player", editedPower), 1) or 100
    local addSlider = framework:CreateSlider(container, 180, 20, 0, sliderMax, 1,
        math.floor(sliderMax / 2), false, nil, nil, nil,
        framework:GetTemplate("slider", private.UIDefaults.presets.slider))
    addSlider:SetPoint("TOPLEFT", specLabel, "BOTTOMLEFT", 0, -12)

    local addBtn = framework:CreateButton(container, function()
        local pct = math.floor(addSlider:GetValue())
        local key = getSpecKey()
        if not key then return end

        if not private.profile.breakpoint_pips.pips[key] then
            private.profile.breakpoint_pips.pips[key] = {}
        end
        local pipList = private.profile.breakpoint_pips.pips[key]

        local inserted = false
        for i, existing in ipairs(pipList) do
            if pct < existing.pct then
                table.insert(pipList, i, {pct = pct, color = {1, 1, 1, 0.8}})
                inserted = true
                break
            end
        end
        if not inserted then
            pipList[#pipList + 1] = {pct = pct, color = {1, 1, 1, 0.8}}
        end

        refreshPips()
        populatePipList()
    end, 60, 22, L["BREAKPOINT_PIP_ADD"], false, false, false, nil, nil)
    addBtn:SetPoint("LEFT", addSlider.widget, "RIGHT", 40, 0)
    addBtn:SetTemplate(buttonTemplate)

    -- Pip list
    local ROW_HEIGHT = 24
    local MAX_VISIBLE_ROWS = 10
    local pipRows = {}

    local listContainer = CreateFrame("Frame", nil, container)
    listContainer:SetPoint("TOPLEFT", addSlider.widget, "BOTTOMLEFT", 0, -8)
    listContainer:SetSize(380, ROW_HEIGHT * MAX_VISIBLE_ROWS + 4)

    local emptyLabel = listContainer:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyLabel:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 5, 0)
    emptyLabel:SetText(L["BREAKPOINT_PIPS_EMPTY"])

    local function getPipRow(index)
        if pipRows[index] then return pipRows[index] end

        local row = CreateFrame("Frame", nil, listContainer)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("LEFT", listContainer, "LEFT", 0, 0)
        row:SetPoint("RIGHT", listContainer, "RIGHT", 0, 0)

        row.pctText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.pctText:SetPoint("LEFT", row, "LEFT", 5, 0)
        row.pctText:SetWidth(45)
        row.pctText:SetJustifyH("RIGHT")

        row.swatchBg = CreateFrame("Button", nil, row)
        row.swatchBg:SetSize(20, 20)
        row.swatchBg:SetPoint("LEFT", row.pctText, "RIGHT", 10, 0)

        row.swatchTex = row.swatchBg:CreateTexture(nil, "ARTWORK")
        row.swatchTex:SetSnapToPixelGrid(false)
        row.swatchTex:SetTexelSnappingBias(0)
        row.swatchTex:SetAllPoints()

        row.swatchBg:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self)
            GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", 0, 0)
            GameTooltip:SetText("Click to change color")
            GameTooltip:Show()
        end)
        row.swatchBg:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        row.removeBtn = framework:CreateButton(row, function() end, 60, 18,
            L["BREAKPOINT_PIP_REMOVE"], false, false, false, nil, nil)
        row.removeBtn:SetPoint("LEFT", row.swatchBg, "RIGHT", 10, 0)
        row.removeBtn:SetTemplate(buttonTemplate)

        -- Zone toggle checkbox
        row.zoneToggle = framework:CreateSwitch(row, function() end, false,
            nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
            framework:GetTemplate("switch", private.UIDefaults.presets.checkbox))
        row.zoneToggle:SetPoint("LEFT", row.removeBtn.widget, "RIGHT", 14, 0)
        row.zoneToggle:SetAsCheckBox()
        row.zoneToggle:SetFixedParameter(index)
        row.zoneToggle:SetTooltip(L["BREAKPOINT_PIP_ZONE_ENABLED_DESC"])

        row.zoneLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.zoneLabel:SetPoint("LEFT", row.zoneToggle.widget, "RIGHT", 3, 0)
        row.zoneLabel:SetText(L["BREAKPOINT_PIP_ZONE_ENABLED"])

        -- Zone color swatch
        row.zoneSwatchBg = CreateFrame("Button", nil, row)
        row.zoneSwatchBg:SetSize(18, 18)
        row.zoneSwatchBg:SetPoint("LEFT", row.zoneLabel, "RIGHT", 8, 0)

        row.zoneSwatchTex = row.zoneSwatchBg:CreateTexture(nil, "ARTWORK")
        row.zoneSwatchTex:SetSnapToPixelGrid(false)
        row.zoneSwatchTex:SetTexelSnappingBias(0)
        row.zoneSwatchTex:SetAllPoints()

        row.zoneSwatchBg:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self)
            GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", 0, 0)
            GameTooltip:SetText(L["BREAKPOINT_PIP_ZONE_COLOR"])
            GameTooltip:Show()
        end)
        row.zoneSwatchBg:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Zone direction toggle button
        row.zoneDirBtn = framework:CreateButton(row, function() end, 42, 18,
            L["BREAKPOINT_PIP_ZONE_PREVIOUS"], false, false, false, nil, nil)
        row.zoneDirBtn:SetPoint("LEFT", row.zoneSwatchBg, "RIGHT", 6, 0)
        row.zoneDirBtn:SetTemplate(buttonTemplate)
        row.zoneDirBtn:SetTooltip(L["BREAKPOINT_PIP_ZONE_DIRECTION_DESC"])

        -- Fill color toggle
        row.fillToggle = framework:CreateSwitch(row, function() end, false, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
            framework:GetTemplate("switch", private.UIDefaults.presets.checkbox))
        row.fillToggle:SetPoint("LEFT", row.zoneDirBtn.widget, "RIGHT", 12, 0)
        row.fillToggle:SetAsCheckBox()
        row.fillToggle:SetFixedParameter(index)
        row.fillToggle:SetTooltip(L["BREAKPOINT_PIP_FILL_ENABLED_DESC"])

        row.fillLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.fillLabel:SetPoint("LEFT", row.fillToggle.widget, "RIGHT", 3, 0)
        row.fillLabel:SetText(L["BREAKPOINT_PIP_FILL_ENABLED"])

        -- Fill color swatch
        row.fillSwatchBg = CreateFrame("Button", nil, row)
        row.fillSwatchBg:SetSize(18, 18)
        row.fillSwatchBg:SetPoint("LEFT", row.fillLabel, "RIGHT", 8, 0)

        row.fillSwatchTex = row.fillSwatchBg:CreateTexture(nil, "ARTWORK")
        row.fillSwatchTex:SetSnapToPixelGrid(false)
        row.fillSwatchTex:SetTexelSnappingBias(0)
        row.fillSwatchTex:SetAllPoints()

        row.fillSwatchBg:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self)
            GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", 0, 0)
            GameTooltip:SetText(L["BREAKPOINT_PIP_FILL_COLOR"])
            GameTooltip:Show()
        end)
        row.fillSwatchBg:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        pipRows[index] = row
        return row
    end

    populatePipList = function()
        local key, editedPowerType = getSpecKey()
        local pipList = key and private.profile.breakpoint_pips.pips[key] or {}
        local modeIsAbsolute = private.profile.breakpoint_pips.pip_mode == "absolute"

        -- Update add slider range when mode changes
        local newMax = modeIsAbsolute and math.max(UnitPowerMax("player", editedPowerType), 1) or 100
        addSlider:SetMinMaxValues(0, newMax)
        if addSlider:GetValue() > newMax then
            addSlider:SetValue(math.floor(newMax / 2))
        end

        emptyLabel:SetShown(#pipList == 0)

        for i, pip in ipairs(pipList) do
            local row = getPipRow(i)
            row:SetPoint("TOPLEFT", listContainer, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
            row.pctText:SetText(modeIsAbsolute and format("%.0f", pip.pct) or format("%.0f%%", pip.pct))

            local c = pip.color
            row.swatchTex:SetColorTexture(private.Util.Color(c))

            row.swatchBg:SetScript("OnClick", function()
                local prevR, prevG, prevB, prevA = private.Util.Color(c)
                ColorPickerFrame:SetupColorPickerAndShow({
                    r = c[1], g = c[2], b = c[3],
                    opacity = c[4] or 1,
                    hasOpacity = true,
                    swatchFunc = function()
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        local a = ColorPickerFrame:GetColorAlpha()
                        pip.color = {r, g, b, a}
                        row.swatchTex:SetColorTexture(r, g, b, a)
                        refreshPips()
                    end,
                    opacityFunc = function()
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        local a = ColorPickerFrame:GetColorAlpha()
                        pip.color = {r, g, b, a}
                        row.swatchTex:SetColorTexture(r, g, b, a)
                        refreshPips()
                    end,
                    cancelFunc = function()
                        pip.color = {prevR, prevG, prevB, prevA}
                        row.swatchTex:SetColorTexture(prevR, prevG, prevB, prevA)
                        refreshPips()
                    end,
                })
            end)

            local capturedIndex = i
            row.removeBtn:SetClickFunction(function()
                table.remove(pipList, capturedIndex)
                refreshPips()
                populatePipList()
            end)

            -- Zone toggle
            local zoneOn = pip.zone_enabled or false
            row.zoneToggle:SetValue(zoneOn)
            row.zoneToggle.OnSwitch = function(_, _, value)
                pip.zone_enabled = value
                if value and not pip.zone_color then
                    pip.zone_color = {1, 1, 1, 0.3}
                    local zc2 = pip.zone_color
                    row.zoneSwatchTex:SetColorTexture(zc2[1], zc2[2], zc2[3], zc2[4] or 1)
                end
                row.zoneSwatchBg:SetEnabled(value)
                row.zoneSwatchBg:SetAlpha(value and 1 or 0.4)
                row.zoneDirBtn:SetEnabled(value)
                row.zoneDirBtn.widget:SetAlpha(value and 1 or 0.4)
                refreshPips()
            end

            -- Zone color swatch
            local zc = pip.zone_color or {1, 1, 1, 0.3}
            row.zoneSwatchTex:SetColorTexture(zc[1], zc[2], zc[3], zc[4] or 1)
            row.zoneSwatchBg:SetEnabled(zoneOn)
            row.zoneSwatchBg:SetAlpha(zoneOn and 1 or 0.4)
            row.zoneSwatchBg:SetScript("OnClick", function()
                if not pip.zone_enabled then return end
                local zcc = pip.zone_color or {1, 1, 1, 0.3}
                local prevR, prevG, prevB, prevA = zcc[1], zcc[2], zcc[3], zcc[4] or 1
                ColorPickerFrame:SetupColorPickerAndShow({
                    r = zcc[1], g = zcc[2], b = zcc[3],
                    opacity = zcc[4] or 1,
                    hasOpacity = true,
                    swatchFunc = function()
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        local a = ColorPickerFrame:GetColorAlpha()
                        pip.zone_color = {r, g, b, a}
                        row.zoneSwatchTex:SetColorTexture(r, g, b, a)
                        refreshPips()
                    end,
                    opacityFunc = function()
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        local a = ColorPickerFrame:GetColorAlpha()
                        pip.zone_color = {r, g, b, a}
                        row.zoneSwatchTex:SetColorTexture(r, g, b, a)
                        refreshPips()
                    end,
                    cancelFunc = function()
                        pip.zone_color = {prevR, prevG, prevB, prevA}
                        row.zoneSwatchTex:SetColorTexture(prevR, prevG, prevB, prevA)
                        refreshPips()
                    end,
                })
            end)

            -- Zone direction toggle
            local dir = pip.zone_direction or "previous"
            row.zoneDirBtn:SetText(dir == "previous" and L["BREAKPOINT_PIP_ZONE_PREVIOUS"] or L["BREAKPOINT_PIP_ZONE_NEXT"])
            row.zoneDirBtn:SetEnabled(zoneOn)
            row.zoneDirBtn.widget:SetAlpha(zoneOn and 1 or 0.4)
            row.zoneDirBtn:SetClickFunction(function()
                if not pip.zone_enabled then return end
                local curDir = pip.zone_direction or "previous"
                pip.zone_direction = curDir == "previous" and "next" or "previous"
                row.zoneDirBtn:SetText(pip.zone_direction == "previous" and L["BREAKPOINT_PIP_ZONE_PREVIOUS"] or L["BREAKPOINT_PIP_ZONE_NEXT"])
                refreshPips()
            end)

            -- Fill color toggle
            local fillOn = pip.bar_color_enabled or false
            row.fillToggle:SetValue(fillOn)
            row.fillToggle.OnSwitch = function(_, _, value)
                pip.bar_color_enabled = value
                if value and not pip.bar_color then
                    pip.bar_color = {1, 0.5, 0, 1}
                    local fc = pip.bar_color
                    row.fillSwatchTex:SetColorTexture(fc[1], fc[2], fc[3], fc[4] or 1)
                end
                row.fillSwatchBg:SetEnabled(value)
                row.fillSwatchBg:SetAlpha(value and 1 or 0.4)
                refreshPips()
            end

            -- Fill color swatch
            local fc = pip.bar_color or {1, 0.5, 0, 1}
            row.fillSwatchTex:SetColorTexture(fc[1], fc[2], fc[3], fc[4] or 1)
            row.fillSwatchBg:SetEnabled(fillOn)
            row.fillSwatchBg:SetAlpha(fillOn and 1 or 0.4)
            row.fillSwatchBg:SetScript("OnClick", function()
                if not pip.bar_color_enabled then return end
                local fcc = pip.bar_color or {1, 0.5, 0, 1}
                local prevR, prevG, prevB, prevA = fcc[1], fcc[2], fcc[3], fcc[4] or 1
                ColorPickerFrame:SetupColorPickerAndShow({
                    r = fcc[1], g = fcc[2], b = fcc[3],
                    opacity = fcc[4] or 1,
                    hasOpacity = true,
                    swatchFunc = function()
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        local a = ColorPickerFrame:GetColorAlpha()
                        pip.bar_color = {r, g, b, a}
                        row.fillSwatchTex:SetColorTexture(r, g, b, a)
                        refreshPips()
                    end,
                    opacityFunc = function()
                        local r, g, b = ColorPickerFrame:GetColorRGB()
                        local a = ColorPickerFrame:GetColorAlpha()
                        pip.bar_color = {r, g, b, a}
                        row.fillSwatchTex:SetColorTexture(r, g, b, a)
                        refreshPips()
                    end,
                    cancelFunc = function()
                        pip.bar_color = {prevR, prevG, prevB, prevA}
                        row.fillSwatchTex:SetColorTexture(prevR, prevG, prevB, prevA)
                        refreshPips()
                    end,
                })
            end)

            row:Show()
        end

        for i = #pipList + 1, #pipRows do
            pipRows[i]:Hide()
        end

        local enabled = private.profile.breakpoint_pips.enabled
        pipWidthLabel:SetTextColor(unpack(enabled and enabledColor or disabledColor))
        pipWidthSlider:SetEnabled(enabled)
        pipLineLabel:SetTextColor(unpack(enabled and enabledColor or disabledColor))
        pipLineToggle:SetEnabled(enabled)
        zoneAutoHideLabel:SetTextColor(unpack(enabled and enabledColor or disabledColor))
        zoneAutoHideToggle:SetEnabled(enabled)
        fillInterpLabel:SetTextColor(unpack(enabled and enabledColor or disabledColor))
        fillInterpDropdown:SetEnabled(enabled)
    end

    populatePipList()
end

---Builds the per-spec Resource Threshold Colors section shown under the
---SecondaryResources tracker tab. Mirrors the structure of
---buildBreakpointPipsSection but targets the SecondaryResources profile's
---`resource_thresholds` table and supports three modes (single / all_previous / all).
---For secret-backed display modes (Fire Blast / Aimed Shot / Vengeance Soul
---Fragments) only the "all" mode is honored — the mode dropdown is locked
---to "all" and a hint label is shown.
---@param parent frame
---@param yOffset number
---@param parentWidth number
local function buildThresholdColorsSection(parent, yOffset, parentWidth)
    local buttonTemplate = private.Templates.ButtonTemplate
    local enabledColor = {1, 1, 1}
    local disabledColor = {0.5, 0.5, 0.5}

    local MODE_VALUES = {"single", "all_previous", "all"}
    local function modeLabel(mode)
        if mode == "single" then return L["THRESHOLD_COLORS_MODE_SINGLE"] end
        if mode == "all_previous" then return L["THRESHOLD_COLORS_MODE_ALL_PREVIOUS"] end
        return L["THRESHOLD_COLORS_MODE_ALL"]
    end

    ---Returns the per-spec threshold list key "CLASSFILENAME-specIndex", or nil if unknown.
    local function getSpecKey()
        local _, class = UnitClass("player")
        local specIndex = C_SpecializationInfo.GetSpecialization()
        if not class or not specIndex then return nil end
        return class .. "-" .. specIndex
    end

    ---Returns true when the currently active secondary resource is secret-backed
    ---(Fire Blast, Aimed Shot, Vengeance Soul Fragments) — only "all" mode allowed.
    local function isActiveSecret()
        if private._sr and private._sr.IsSecretBackedResource then
            return private._sr.IsSecretBackedResource()
        end
        return false
    end

    -- Header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    header:SetText(L["THRESHOLD_COLORS_HEADER"])
    header:SetTextColor(1, 0.85, 0)

    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    desc:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    desc:SetJustifyH("LEFT")
    desc:SetJustifyV("TOP")
    desc:SetWordWrap(true)
    desc:SetText(L["THRESHOLD_COLORS_ENABLED_DESC"])

    ---Returns the per-spec enabled map, migrating legacy boolean shape if needed.
    local function getEnabledMap()
        local sr = private.profile.components.SecondaryResources
        if type(sr.resource_thresholds_enabled) ~= "table" then
            -- A legacy `false` meant "off everywhere"; the global toggle is that switch now.
            if sr.resource_thresholds_enabled == false then sr.resource_thresholds_global_enabled = false end
            sr.resource_thresholds_enabled = {}
        end
        return sr.resource_thresholds_enabled
    end

    ---Reads the per-spec enabled flag. Missing key = enabled (new-spec default).
    local function isSpecEnabled(key)
        if not key then return true end
        local map = getEnabledMap()
        local v = map[key]
        if v == nil then return true end
        return v and true or false
    end

    ---Reads the global master flag (defaults to enabled).
    local function isGlobalEnabled()
        getEnabledMap() -- migrate first: a legacy `false` lands in the flag read below
        local v = private.profile.components.SecondaryResources.resource_thresholds_global_enabled
        if v == nil then return true end
        return v and true or false
    end

    -- Global master toggle (applies to every spec)
    local globalToggle = framework:CreateSwitch(parent, function(_, _, value)
        private.profile.components.SecondaryResources.resource_thresholds_global_enabled = value and true or false
        private.SecondaryResources.Refresh()
    end, isGlobalEnabled(),
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        framework:GetTemplate("switch", private.UIDefaults.presets.checkbox))
    globalToggle:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)
    globalToggle:SetAsCheckBox()
    globalToggle:SetTooltip(L["THRESHOLD_COLORS_GLOBAL_ENABLED_DESC"])

    local globalLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    globalLabel:SetPoint("LEFT", globalToggle.widget or globalToggle, "RIGHT", 4, 0)
    globalLabel:SetText(L["THRESHOLD_COLORS_GLOBAL_ENABLED"])

    -- Per-spec enable toggle (sits next to the global toggle; state refreshed on spec change)
    local specToggle = framework:CreateSwitch(parent, function(_, _, value)
        local key = getSpecKey()
        if not key then return end
        getEnabledMap()[key] = value and true or false
        private.SecondaryResources.Refresh()
    end, isSpecEnabled(getSpecKey()),
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        framework:GetTemplate("switch", private.UIDefaults.presets.checkbox))
    specToggle:SetPoint("LEFT", globalLabel, "RIGHT", 20, 0)
    specToggle:SetAsCheckBox()
    specToggle:SetTooltip(L["THRESHOLD_COLORS_SPEC_ENABLED_DESC"])

    local specToggleLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    specToggleLabel:SetPoint("LEFT", specToggle.widget or specToggle, "RIGHT", 4, 0)
    specToggleLabel:SetText(L["THRESHOLD_COLORS_SPEC_ENABLED"])

    -- Stack strips only, and no rebuild is needed: the blend mode is baked at build
    -- time but applyColors re-asserts it on every Refresh, which this setter fires.
    local glowToggle = framework:CreateSwitch(parent, function(_, _, value)
        private.profile.components.SecondaryResources.stack_strip_threshold_glow = value and true or false
        private.SecondaryResources.Refresh()
    end, private.profile.components.SecondaryResources.stack_strip_threshold_glow and true or false,
        nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        framework:GetTemplate("switch", private.UIDefaults.presets.checkbox))
    glowToggle:SetPoint("LEFT", specToggleLabel, "RIGHT", 20, 0)
    glowToggle:SetAsCheckBox()
    glowToggle:SetTooltip(L["THRESHOLD_COLORS_STACK_GLOW_DESC"])

    local glowToggleLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    glowToggleLabel:SetPoint("LEFT", glowToggle.widget or glowToggle, "RIGHT", 4, 0)
    glowToggleLabel:SetText(L["THRESHOLD_COLORS_STACK_GLOW"])

    -- Spec label
    local specLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    specLabel:SetPoint("TOPLEFT", globalToggle.widget or globalToggle, "BOTTOMLEFT", 0, -10)

    -- Secret-resource hint label (shown when active mode is secret-backed)
    local hintLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hintLabel:SetPoint("TOPLEFT", specLabel, "BOTTOMLEFT", 0, -4)
    hintLabel:SetTextColor(0.95, 0.75, 0.2)
    hintLabel:SetText(L["THRESHOLD_COLORS_SECRET_RESOURCE_HINT"])
    hintLabel:Hide()

    -- Stack strips ignore `mode` entirely — their count is protected, so the only
    -- thing they can key a color off is a pip's own index ("from this stack upward").
    -- This hint replaces the mode dropdown for them rather than sitting beside it.
    local stackHintLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stackHintLabel:SetPoint("TOPLEFT", hintLabel, "BOTTOMLEFT", 0, -4)
    stackHintLabel:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    stackHintLabel:SetJustifyH("LEFT")
    stackHintLabel:SetWordWrap(true)
    stackHintLabel:SetTextColor(0.95, 0.75, 0.2)
    stackHintLabel:SetText(L["THRESHOLD_COLORS_STACK_HINT"])
    stackHintLabel:Hide()

    -- Forward declaration — defined below, referenced by the resource dropdown, the
    -- Add button and the list rebuild. Declared HERE rather than next to the Add
    -- button: the resource dropdown's onclick names it ~90 lines earlier, and Lua 5.1
    -- would capture that read as a nil global, leaving the picker silently unable to
    -- redraw the list (see `.context/patterns.md`, the `disableif` case).
    local populateList

    -- Which bar a threshold applies to. nil = the primary row, matching the profile
    -- shape (`resource_threshold.resource`), where nil is also the legacy meaning.
    local addResource = nil

    ---The rows a threshold can be scoped to for the CURRENT spec, straight from the
    ---component so the picker offers exactly what is on screen. Empty before the
    ---component has built its rows, which the callers below all tolerate.
    local function thresholdResources()
        if private._sr and private._sr.GetThresholdResources then
            return private._sr.GetThresholdResources()
        end
        return {}
    end

    local function resourceLabel(id)
        for _, r in ipairs(thresholdResources()) do
            if r.id == id then
                return r.labelKey and L[r.labelKey] or L["THRESHOLD_COLORS_RESOURCE_PRIMARY"]
            end
        end
        -- A threshold saved against a strip that is not active right now (setting
        -- toggled off, or a different hero spec). Show the id rather than dropping the
        -- row, so the entry stays identifiable and removable.
        return id or L["THRESHOLD_COLORS_RESOURCE_PRIMARY"]
    end

    ---True when `id` names a stack strip, which is what makes `mode` meaningless.
    ---Row 1 counts: a spec whose primary IS a strip (Sweeping Strikes, Teachings,
    ---Art of the Glaive on Havoc) reports `isStrip` on the nil-id entry.
    local function resourceIsStrip(id)
        for _, r in ipairs(thresholdResources()) do
            if r.id == id then return r.isStrip end
        end
        return false
    end

    local addResourceLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    addResourceLabel:SetPoint("TOPLEFT", stackHintLabel, "BOTTOMLEFT", 0, -10)
    addResourceLabel:SetText(L["THRESHOLD_COLORS_RESOURCE"] .. ":")

    local addResourceDropdown
    local function addResourceOptions()
        local opts = {}
        for _, r in ipairs(thresholdResources()) do
            local id = r.id
            local label = r.labelKey and L[r.labelKey] or L["THRESHOLD_COLORS_RESOURCE_PRIMARY"]
            opts[#opts + 1] = {
                label = label,
                value = id or "",
                onclick = function()
                    addResource = id
                    if addResourceDropdown then addResourceDropdown:Select(label) end
                    if populateList then populateList() end
                end,
            }
        end
        return opts
    end
    addResourceDropdown = framework:CreateDropDown(parent, addResourceOptions,
        resourceLabel(addResource), 170, 20, nil, nil,
        framework:GetTemplate("dropdown", private.UIDefaults.presets.dropdown))
    addResourceDropdown:SetPoint("LEFT", addResourceLabel, "RIGHT", 8, 0)
    addResourceDropdown:SetTooltip(L["THRESHOLD_COLORS_RESOURCE_DESC"])

    -- Add row
    local addLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    addLabel:SetPoint("TOPLEFT", addResourceLabel, "BOTTOMLEFT", 0, -10)
    addLabel:SetText(L["THRESHOLD_COLORS_VALUE"] .. ":")

    local addValue = 1
    local addMode = "all"
    local addColor = {1, 0.5, 0, 1}

    local addSlider = framework:CreateSlider(parent, 110, 20, 1, 20, 1, addValue, false, nil, nil, nil,
        framework:GetTemplate("slider", private.UIDefaults.presets.slider))
    addSlider:SetPoint("LEFT", addLabel, "RIGHT", 8, 0)
    addSlider:SetTooltip(L["THRESHOLD_COLORS_VALUE_DESC"])
    addSlider:SetHook("OnValueChanged", function(_, _, value)
        addValue = value
    end)

    local addModeDropdown
    local function addModeOptions()
        local opts = {}
        for _, mode in ipairs(MODE_VALUES) do
            opts[#opts + 1] = {
                label = modeLabel(mode),
                value = mode,
                onclick = function()
                    addMode = mode
                    if addModeDropdown then addModeDropdown:Select(modeLabel(mode)) end
                end,
            }
        end
        return opts
    end
    addModeDropdown = framework:CreateDropDown(parent, addModeOptions, modeLabel(addMode), 110, 20, nil, nil,
        framework:GetTemplate("dropdown", private.UIDefaults.presets.dropdown))
    addModeDropdown:SetPoint("LEFT", addSlider.widget or addSlider, "RIGHT", 10, 0)
    addModeDropdown:SetTooltip(L["THRESHOLD_COLORS_MODE_DESC"])

    -- Add-row color swatch
    local addSwatchBg = CreateFrame("Button", nil, parent)
    addSwatchBg:SetSize(20, 20)
    addSwatchBg:SetPoint("LEFT", addModeDropdown.widget or addModeDropdown, "RIGHT", 10, 0)

    local addSwatchTex = addSwatchBg:CreateTexture(nil, "ARTWORK")
    addSwatchTex:SetSnapToPixelGrid(false)
    addSwatchTex:SetTexelSnappingBias(0)
    addSwatchTex:SetAllPoints()
    addSwatchTex:SetColorTexture(addColor[1], addColor[2], addColor[3], addColor[4] or 1)

    addSwatchBg:SetScript("OnClick", function()
        local prevR, prevG, prevB, prevA = addColor[1], addColor[2], addColor[3], addColor[4] or 1
        ColorPickerFrame:SetupColorPickerAndShow({
            r = addColor[1], g = addColor[2], b = addColor[3],
            opacity = addColor[4] or 1,
            hasOpacity = true,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = ColorPickerFrame:GetColorAlpha()
                addColor = {r, g, b, a}
                addSwatchTex:SetColorTexture(r, g, b, a)
            end,
            opacityFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = ColorPickerFrame:GetColorAlpha()
                addColor = {r, g, b, a}
                addSwatchTex:SetColorTexture(r, g, b, a)
            end,
            cancelFunc = function()
                addColor = {prevR, prevG, prevB, prevA}
                addSwatchTex:SetColorTexture(prevR, prevG, prevB, prevA)
            end,
        })
    end)

    local addButton = framework:CreateButton(parent, function()
        local key = getSpecKey()
        if not key then return end
        local rt = private.profile.components.SecondaryResources.resource_thresholds
        if not rt then
            rt = {}
            private.profile.components.SecondaryResources.resource_thresholds = rt
        end
        if not rt[key] then rt[key] = {} end
        local mode = addMode
        -- A strip's SEGMENT recolour still ignores mode, but its animated border honours
        -- all three, so the user's choice is stored rather than overwritten. Only the
        -- charge-secret resources are still forced.
        if not resourceIsStrip(addResource) and isActiveSecret() then
            mode = "all"
        end
        rt[key][#rt[key] + 1] = {
            value = addValue,
            mode = mode,
            resource = addResource,
            color = {addColor[1], addColor[2], addColor[3], addColor[4] or 1},
        }
        if private._sr and private._sr.invalidateThresholdColorCache then
            private._sr.invalidateThresholdColorCache()
        end
        private.SecondaryResources.Refresh()
        if populateList then populateList() end
    end, 60, 20, L["THRESHOLD_COLORS_ADD"], false, false, false, nil, nil)
    addButton:SetPoint("LEFT", addSwatchBg, "RIGHT", 10, 0)
    addButton:SetTemplate(buttonTemplate)

    -- List of existing rows (rebuilt on populateList).
    local listAnchor = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listAnchor:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 0, -14)
    listAnchor:SetText(" ")  -- invisible spacer used as anchor for first row
    listAnchor:Hide()

    local emptyLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyLabel:SetPoint("TOPLEFT", listAnchor, "BOTTOMLEFT", 0, -2)
    emptyLabel:SetText(L["THRESHOLD_COLORS_EMPTY"])
    emptyLabel:SetTextColor(0.6, 0.6, 0.6)

    local rowPool = {}

    ---Returns (creating if needed) a row frame at `index`.
    local function acquireRow(index)
        if rowPool[index] then return rowPool[index] end
        local row = CreateFrame("Frame", nil, parent)
        row:SetSize(parentWidth - 10, 24)

        row.valueLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.valueLabel:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.valueLabel:SetWidth(40)
        row.valueLabel:SetJustifyH("LEFT")

        row.resourceLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.resourceLabel:SetPoint("LEFT", row.valueLabel, "RIGHT", 4, 0)
        row.resourceLabel:SetWidth(150)
        row.resourceLabel:SetJustifyH("LEFT")

        row.modeLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.modeLabel:SetPoint("LEFT", row.resourceLabel, "RIGHT", 4, 0)
        row.modeLabel:SetWidth(90)
        row.modeLabel:SetJustifyH("LEFT")

        row.swatchBg = CreateFrame("Button", nil, row)
        row.swatchBg:SetSize(18, 18)
        row.swatchBg:SetPoint("LEFT", row.modeLabel, "RIGHT", 4, 0)
        row.swatchTex = row.swatchBg:CreateTexture(nil, "ARTWORK")
        row.swatchTex:SetSnapToPixelGrid(false)
        row.swatchTex:SetTexelSnappingBias(0)
        row.swatchTex:SetAllPoints()
        row.swatchBg:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self)
            GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", 0, 0)
            GameTooltip:SetText(L["THRESHOLD_COLORS_COLOR"])
            GameTooltip:Show()
        end)
        row.swatchBg:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.removeBtn = framework:CreateButton(row, function() end, 60, 18,
            L["THRESHOLD_COLORS_REMOVE"], false, false, false, nil, nil)
        row.removeBtn:SetPoint("LEFT", row.swatchBg, "RIGHT", 8, 0)
        row.removeBtn:SetTemplate(buttonTemplate)

        rowPool[index] = row
        return row
    end

    populateList = function()
        local key = getSpecKey()
        local label = private.GetLocalizedClassSpecLabel(nil, C_SpecializationInfo.GetSpecialization())
        specLabel:SetText(L["THRESHOLD_COLORS_SPEC_LABEL"]:format(label ~= "" and label or "?"))

        -- Refresh toggle states (global is invariant across spec change, per-spec is not)
        globalToggle:SetValue(isGlobalEnabled())
        specToggle:SetValue(isSpecEnabled(key))

        -- Keep the picker honest across a spec change: a resource that is no longer on
        -- screen cannot be added against, so fall back to the first row. That row is
        -- not always the primary (nil): with the primary switched off, row 1 is an
        -- extra strip and nil is not offered at all.
        local offered = thresholdResources()
        local stillOffered = false
        for _, r in ipairs(offered) do
            if r.id == addResource then stillOffered = true break end
        end
        if not stillOffered then
            addResource = offered[1] and offered[1].id
        end
        if addResourceDropdown then
            addResourceDropdown:Select(resourceLabel(addResource))
        end

        -- Three-way:
        --   stack strip      -> all three modes, but they shape the animated BORDER only.
        --                       The segment recolour still runs from the chosen stack
        --                       upward, because a segment can only report that the count
        --                       reached it. stackHintLabel says so.
        --   charge-secret    -> "all" only (Fire Blast / Aimed Shot / Radiance /
        --                       Vengeance fold through EvaluateColorFromBoolean)
        --   everything else  -> all three modes
        local isStrip = resourceIsStrip(addResource)
        local secret = not isStrip and isActiveSecret()
        stackHintLabel:SetShown(isStrip)
        hintLabel:SetShown(secret)
        local modeUsable = not secret
        if secret then
            addMode = "all"
            if addModeDropdown then addModeDropdown:Select(modeLabel("all")) end
        end
        -- Greyed, not hidden: the swatch and Add button anchor off this dropdown's
        -- right edge, so hiding it would leave a hole in the row rather than closing
        -- it up. stackHintLabel carries the explanation instead.
        if addModeDropdown and addModeDropdown.widget then
            addModeDropdown.widget:EnableMouse(modeUsable)
            addModeDropdown.widget:SetAlpha(modeUsable and 1 or 0.55)
        end

        local rt = private.profile.components.SecondaryResources.resource_thresholds
        local list = key and rt and rt[key] or nil
        local count = list and #list or 0

        if count == 0 then
            emptyLabel:Show()
        else
            emptyLabel:Hide()
        end

        -- Anchor rows under listAnchor, stacking vertically.
        local prev = listAnchor
        for i = 1, count do
            local t = list[i]
            local row = acquireRow(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -4)
            row:Show()

            row.valueLabel:SetText((t.value or 0))
            row.resourceLabel:SetText(resourceLabel(t.resource))
            -- A strip's stored mode is inert, so showing it would be a lie. The dash
            -- says "not applicable" without inventing a fourth mode name.
            row.modeLabel:SetText(modeLabel(t.mode or "all"))

            local c = t.color or {1, 1, 1, 1}
            local rr, gg, bb, aa = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
            row.swatchTex:SetColorTexture(rr, gg, bb, aa)

            row.swatchBg:SetScript("OnClick", function()
                local prevR, prevG, prevB, prevA = private.Util.Color(c)
                ColorPickerFrame:SetupColorPickerAndShow({
                    r = c[1], g = c[2], b = c[3],
                    opacity = c[4] or 1,
                    hasOpacity = true,
                    swatchFunc = function()
                        local rcR, rcG, rcB = ColorPickerFrame:GetColorRGB()
                        local rcA = ColorPickerFrame:GetColorAlpha()
                        t.color = {rcR, rcG, rcB, rcA}
                        t.__colorObj = nil
                        row.swatchTex:SetColorTexture(rcR, rcG, rcB, rcA)
                        private.SecondaryResources.Refresh()
                    end,
                    opacityFunc = function()
                        local rcR, rcG, rcB = ColorPickerFrame:GetColorRGB()
                        local rcA = ColorPickerFrame:GetColorAlpha()
                        t.color = {rcR, rcG, rcB, rcA}
                        t.__colorObj = nil
                        row.swatchTex:SetColorTexture(rcR, rcG, rcB, rcA)
                        private.SecondaryResources.Refresh()
                    end,
                    cancelFunc = function()
                        t.color = {prevR, prevG, prevB, prevA}
                        t.__colorObj = nil
                        row.swatchTex:SetColorTexture(prevR, prevG, prevB, prevA)
                        private.SecondaryResources.Refresh()
                    end,
                })
            end)

            local capturedIndex = i
            row.removeBtn:SetClickFunction(function()
                if not list then return end
                table.remove(list, capturedIndex)
                if private._sr and private._sr.invalidateThresholdColorCache then
                    private._sr.invalidateThresholdColorCache()
                end
                private.SecondaryResources.Refresh()
                populateList()
            end)

            prev = row
        end

        for i = count + 1, #rowPool do
            rowPool[i]:Hide()
        end
    end

    -- Refresh on spec change
    local specEventFrame = CreateFrame("Frame", nil, parent)
    specEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specEventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    specEventFrame:SetScript("OnEvent", function()
        if populateList then populateList() end
    end)

    populateList()
end

---Build the Trackers tab with sidebar navigation + scrollable detail panel.
---@param panel frame
local function buildTrackersTab(panel)
    local options_text_template = framework:GetTemplate("font", private.UIDefaults.presets.font)
    local options_dropdown_template = framework:GetTemplate("dropdown", private.UIDefaults.presets.dropdown)
    local options_switch_template = framework:GetTemplate("switch", private.UIDefaults.presets.checkbox)
    local options_slider_template = framework:GetTemplate("slider", private.UIDefaults.presets.slider)
    local options_button_template = framework:GetTemplate("button", private.UIDefaults.presets.button)
    local buttonTemplate = private.Templates.ButtonTemplate

    -- =====================================================================
    -- Sidebar (left)
    -- =====================================================================
    local sidebarWidth = 160
    local sidebar = CreateFrame("Frame", frameName .. "TrackersSidebar", panel)
    sidebar:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -5)
    sidebar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 5)
    sidebar:SetWidth(sidebarWidth)

    -- =====================================================================
    -- Detail panel (right, scrollable)
    -- =====================================================================
    local detailPanel = CreateFrame("Frame", frameName .. "TrackersDetail", panel)
    detailPanel:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 10, 4)
    detailPanel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 5)

    local hintLabel = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hintLabel:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 2, 0)
    hintLabel:SetText("|cff888888" .. L["TRACKERS_HINT"] .. "|r")
    hintLabel:Hide()

    -- DF canvas scrollbox provides smooth (animated) scrolling that
    -- UIPanelScrollFrameTemplate does not support.
    local scrollFrame = framework:CreateCanvasScrollBox(detailPanel, nil, frameName .. "TrackersScrollFrame", {
        smooth_scrolling = false,
        smooth_scrolling_speed = 20,
        smooth_scrolling_acceleration_factor = 2,
        smooth_scrolling_acceleration = true,
        use_momentum = true,
        momentum_friction = 6,
        use_drag_scroll = true,
    })
    scrollFrame:SetPoint("TOPLEFT", hintLabel, "BOTTOMLEFT", -2, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", detailPanel, "BOTTOMRIGHT", 0, 0)
    scrollFrame:Hide()

    local emptyLabel = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyLabel:SetPoint("CENTER", detailPanel, "CENTER", 0, 0)
    emptyLabel:SetText(L["TRACKERS_SELECT_PROMPT"])
    emptyLabel:SetTextColor(0.5, 0.5, 0.5)

    local selectedComponent = nil

    local currentPipsChild = nil
    local currentThresholdChild = nil
    local sidebarButtons = {}
    local scrollChildCounter = 0

    -- Persistent column frames for BuildMenuVolatile reuse
    local childWidth = private.Templates.OptionsPanel.width - 20 - sidebarWidth - 10 - 30
    local colGap = 20
    local colWidth = math.floor((childWidth - colGap) / 2)

    -- Reuse the scroll child that CreateCanvasScrollBox auto-creates so we
    -- don't orphan it by calling SetScrollChild with a second frame.
    local persistentScrollChild = scrollFrame.child
    persistentScrollChild:SetWidth(childWidth)

    local leftCol = CreateFrame("Frame", frameName .. "TrackersLeft", persistentScrollChild)
    leftCol:SetPoint("TOPLEFT", persistentScrollChild, "TOPLEFT", 0, 0)
    leftCol:SetSize(colWidth, 10)
    framework:SetAsOptionsPanel(leftCol)
    trackersLeftCol = leftCol

    local rightCol = CreateFrame("Frame", frameName .. "TrackersRight", persistentScrollChild)
    rightCol:SetPoint("TOPLEFT", persistentScrollChild, "TOPLEFT", colWidth + colGap, 0)
    rightCol:SetSize(colWidth, 10)
    framework:SetAsOptionsPanel(rightCol)
    trackersRightCol = rightCol

    optionsPanelColumns[#optionsPanelColumns + 1] = leftCol
    optionsPanelColumns[#optionsPanelColumns + 1] = rightCol

    ---Estimate the pixel height consumed by a BuildMenu widget array.
    ---@param widgets table[]
    ---@return number
    local function estimateWidgetHeight(widgets)
        local h = 0
        for _, w in ipairs(widgets) do
            -- BuildMenuVolatile skips a hidden widget entirely (it never even
            -- advances its Y offset), so counting one here inflates the column
            -- and leaves a gap where the widget would have been.
            if w.hidden then
            elseif w.type == "blank" then
                h = h + 20
            elseif w.type == "label" then
                h = h + 22
            else
                h = h + 28
            end
        end
        return h
    end

    ---Rebuild the detail panel for the given component.
    ---@param componentName string
    local function populateDetailPanel(componentName)
        -- Hide previous breakpoint pips child if any
        if currentPipsChild then
            currentPipsChild:Hide()
            currentPipsChild:SetParent(nil)
            currentPipsChild = nil
        end
        -- Hide previous threshold colors child if any
        if currentThresholdChild then
            currentThresholdChild:Hide()
            currentThresholdChild:SetParent(nil)
            currentThresholdChild = nil
        end

        emptyLabel:Hide()
        hintLabel:Show()
        scrollFrame:Show()

        local component = private[componentName]
        if not component then return end

        -- ── Left column: settings, anchoring, layout, features, glow ──
        local leftWidgets = {}

        -- Enabled + Visibility
        appendWidgets(leftWidgets, buildEnabledVisibilityWidgets(componentName, component))
        leftWidgets[#leftWidgets + 1] = {type = "blank"}

        -- Tooltip (mode + anchor; skipped for components without tooltip_mode)
        local tooltipWidgets = buildTooltipWidgets(component)
        if #tooltipWidgets > 0 then
            appendWidgets(leftWidgets, tooltipWidgets)
            leftWidgets[#leftWidgets + 1] = {type = "blank"}
        end

        -- Anchoring
        appendWidgets(leftWidgets, buildAnchoringWidgets(componentName, component))
        leftWidgets[#leftWidgets + 1] = {type = "blank"}

        -- Layout (type-specific)
        if trackerViewerComponents[componentName] then
            appendWidgets(leftWidgets, buildViewerTrackerLayoutWidgets(componentName, component))
            leftWidgets[#leftWidgets + 1] = {type = "blank"}
        elseif trackerBarComponents[componentName] then
            appendWidgets(leftWidgets, buildBarTrackerLayoutWidgets(componentName, component))
            leftWidgets[#leftWidgets + 1] = {type = "blank"}
        elseif componentName == "TrinketTracker" then
            appendWidgets(leftWidgets, buildTrinketLayoutWidgets(component))
            leftWidgets[#leftWidgets + 1] = {type = "blank"}
        elseif componentName == "RacialTracker" then
            appendWidgets(leftWidgets, buildRacialLayoutWidgets(component))
            leftWidgets[#leftWidgets + 1] = {type = "blank"}
        elseif componentName == "ConsumableTracker" then
            appendWidgets(leftWidgets, buildConsumableLayoutWidgets(component))
            leftWidgets[#leftWidgets + 1] = {type = "blank"}
        elseif componentName == "ConsumableBuffTracker" then
            appendWidgets(leftWidgets, buildConsumableBuffLayoutWidgets(component))
            leftWidgets[#leftWidgets + 1] = {type = "blank"}
        elseif componentName == "RaidBuffTracker" then
            appendWidgets(leftWidgets, buildRaidBuffLayoutWidgets(component))
            leftWidgets[#leftWidgets + 1] = {type = "blank"}
        end

        -- Component-specific features (texture, pandemic glow, health options, etc.)
        local specificResult = buildComponentSpecificWidgets(componentName, component)
        if #specificResult.left > 0 then
            appendWidgets(leftWidgets, specificResult.left)
            leftWidgets[#leftWidgets + 1] = {type = "blank"}
        end
        local specificRightWidgets = specificResult.right

        -- Glow effects (trinket/consumable) — skip components with custom glow in right column
        if componentName ~= "ConsumableBuffTracker" and componentName ~= "RaidBuffTracker" and componentName ~= "OutboundBuffTracker" then
            local glowWidgets = buildGlowWidgets(component)
            if #glowWidgets > 0 then
                appendWidgets(leftWidgets, glowWidgets)
            end
        end

        leftWidgets.always_boxfirst = true

        -- ── Right column: fonts + component-specific right features ──
        local rightWidgets = {}

        local fontWidgets = buildTrackerFontWidgets(componentName, component)
        if #fontWidgets > 0 then
            appendWidgets(rightWidgets, fontWidgets)
        end

        -- Tracked/excluded items list below fonts
        if componentName == "ConsumableTracker" then
            rightWidgets[#rightWidgets + 1] = {type = "blank"}
            appendWidgets(rightWidgets, buildConsumableTrackedItemsWidgets(component))
        elseif componentName == "ConsumableBuffTracker" then
            rightWidgets[#rightWidgets + 1] = {type = "blank"}
            appendWidgets(rightWidgets, buildConsumableBuffTrackedItemsWidgets(component))
        elseif componentName == "RaidBuffTracker" then
            rightWidgets[#rightWidgets + 1] = {type = "blank"}
            appendWidgets(rightWidgets, buildRaidBuffTrackedItemsWidgets(component))
        elseif componentName == "OutboundBuffTracker" then
            rightWidgets[#rightWidgets + 1] = {type = "blank"}
            appendWidgets(rightWidgets, buildOutboundBuffTrackedItemsWidgets(component, function() populateDetailPanel(componentName) end))
        elseif componentName == "RacialTracker" then
            rightWidgets[#rightWidgets + 1] = {type = "blank"}
            appendWidgets(rightWidgets, buildRacialTrackedWidgets(component))
        elseif componentName == "TrinketTracker" then
            rightWidgets[#rightWidgets + 1] = {type = "blank"}
            appendWidgets(rightWidgets, buildTrinketExcludeWidgets(component, function() populateDetailPanel(componentName) end))
        end

        -- CDM trackers: their per-spell lists (order, custom spells, pandemic
        -- exclusions, bar colours) live in the Tracking tab; one button opens
        -- this tracker's section there.
        if private.Util.CDM_COMPONENT_VIEWER_KEYS[componentName] then
            rightWidgets[#rightWidgets + 1] = {type = "blank"}
            rightWidgets[#rightWidgets + 1] = {
                type = "execute",
                width = 240,
                name = L["TRACKERS_EDIT_IN_TRACKING"],
                desc = L["TRACKERS_EDIT_IN_TRACKING_DESC"],
                func = function()
                    private.Options.OpenOptionsPanel(options.TRACKING_TAB_INDEX, componentName)
                end,
            }
        end

        -- Component-specific right-column features (below fonts)
        if #specificRightWidgets > 0 then
            if #rightWidgets > 0 then
                rightWidgets[#rightWidgets + 1] = {type = "blank"}
            end
            appendWidgets(rightWidgets, specificRightWidgets)
        end

        -- Drop corrupted spell_colors entries (pre-fix saved data), which
        -- AuraBarTracker's applyBarFill would index.  Kept from the retired
        -- per-spell colour list, which ran it whenever this panel opened; the
        -- Additional Frame panel keeps the same loop for bar frames.
        local barColors = componentName == "BuffTrackerBars" and component.GetSettings().spell_colors
        if type(barColors) == "table" then
            for sid, entry in pairs(barColors) do
                if type(entry) ~= "table" or type(entry[1]) ~= "number" then
                    barColors[sid] = nil
                end
            end
        end
        rightWidgets.always_boxfirst = true

        -- ── Render columns using BuildMenuVolatile (reuses pooled widgets) ──
        framework:BuildMenuVolatile(leftCol, leftWidgets, 0, 0, 3000, false,
            options_text_template, options_dropdown_template, options_switch_template,
            true, options_slider_template, options_button_template, refreshBuildMenuColumns)
        resetSwitchPool(leftCol)

        if #rightWidgets > 0 then
            framework:BuildMenuVolatile(rightCol, rightWidgets, 0, 0, 3000, false,
                options_text_template, options_dropdown_template, options_switch_template,
                true, options_slider_template, options_button_template, refreshBuildMenuColumns)
            resetSwitchPool(rightCol)
        else
            framework:ClearOptionsPanel(rightCol)
        end

        limitDropdownMenuHeight(leftCol)
        limitDropdownMenuHeight(rightCol)

        -- Calculate total content height (max of both columns)
        local leftHeight = estimateWidgetHeight(leftWidgets)
        local rightHeight = estimateWidgetHeight(rightWidgets)
        local totalHeight = math.max(leftHeight, rightHeight)

        -- PrimaryResources: append breakpoint pips section below right column (column 2)
        if componentName == "PrimaryResources" then
            scrollChildCounter = scrollChildCounter + 1
            local pipsChild = CreateFrame("Frame", frameName .. "TrackersPips" .. scrollChildCounter, persistentScrollChild)
            pipsChild:SetPoint("TOPLEFT", persistentScrollChild, "TOPLEFT", colWidth + colGap, -rightHeight - 20)
            pipsChild:SetSize(colWidth, 420)
            pipsChild:Show()
            currentPipsChild = pipsChild
            buildBreakpointPipsSection(pipsChild, 0, colWidth)
            totalHeight = math.max(totalHeight, rightHeight + 20 + 420)
        end

        -- SecondaryResources: append resource threshold colors section spanning both columns.
        -- Position is computed from the actual rendered child bounds of the two columns
        -- (synchronous measure + deferred re-measure on next frame, since child positions
        -- sometimes settle after BuildMenuVolatile returns).
        if componentName == "SecondaryResources" then
            scrollChildCounter = scrollChildCounter + 1
            local thresholdChild = CreateFrame("Frame", frameName .. "TrackersThresholds" .. scrollChildCounter, persistentScrollChild)
            local estimatedOffset = math.max(leftHeight, rightHeight) + 20
            thresholdChild:SetPoint("TOPLEFT", persistentScrollChild, "TOPLEFT", 0, -estimatedOffset)
            thresholdChild:SetSize(childWidth, 360)
            thresholdChild:Show()
            currentThresholdChild = thresholdChild
            buildThresholdColorsSection(thresholdChild, 0, childWidth)

            -- Breakpoint pips for the continuous secondary bar, appended below
            -- the threshold section. Built only for the moved specs (Elemental /
            -- Balance / Shadow) — every other spec has no continuous bar.
            local pipsChild
            if private.BreakpointPips.GetKeyForCurrentSpec("secondary") then
                scrollChildCounter = scrollChildCounter + 1
                pipsChild = CreateFrame("Frame", frameName .. "TrackersPips" .. scrollChildCounter, persistentScrollChild)
                pipsChild:SetPoint("TOPLEFT", persistentScrollChild, "TOPLEFT", 0, -(estimatedOffset + 360 + 20))
                pipsChild:SetSize(colWidth, 420)
                pipsChild:Show()
                currentPipsChild = pipsChild
                buildBreakpointPipsSection(pipsChild, 0, colWidth, "secondary")
            end

            local function reanchor()
                if not thresholdChild:IsShown() then return end
                local lh = measureColumnHeight(leftCol)
                local rh = measureColumnHeight(rightCol)
                local measured = math.max(lh, rh)
                if measured <= 0 then return end
                local base = measured + 20
                thresholdChild:ClearAllPoints()
                thresholdChild:SetPoint("TOPLEFT", persistentScrollChild, "TOPLEFT", 0, -base)
                local contentBottom = base + 360
                if pipsChild then
                    pipsChild:ClearAllPoints()
                    pipsChild:SetPoint("TOPLEFT", persistentScrollChild, "TOPLEFT", 0, -(contentBottom + 20))
                    contentBottom = contentBottom + 20 + 420
                end
                persistentScrollChild:SetHeight(contentBottom + 50)
            end
            reanchor()
            C_Timer.After(0, reanchor)

            totalHeight = math.max(totalHeight, estimatedOffset + 360 + (pipsChild and (20 + 420) or 0))
        end

        persistentScrollChild:SetHeight(totalHeight + 50)
        scrollFrame:SetVerticalScroll(0)
    end

    -- =====================================================================
    -- Sidebar component groups
    -- =====================================================================
    local trackerGroups = {
        {label = L["TRACKER_GROUP_ICON"], components = {"CooldownTracker", "BuffTracker", "UtilitiesTracker", "BuffTrackerBars"}},
        {label = L["TRACKER_GROUP_CAST_BARS"], components = {"PlayerCastBar", "TargetCastBar", "FocusCastBar", "GlobalCooldown"}},
        {label = L["TRACKER_GROUP_RESOURCES"], components = {"PrimaryResources", "SecondaryResources", "PlayerHealthBar"}},
        {label = L["TRACKER_GROUP_ITEMS"], components = {"TrinketTracker", "RacialTracker", "ConsumableTracker", "ConsumableBuffTracker", "RaidBuffTracker", "OutboundBuffTracker"}},
    }

    ---Select a component in the sidebar and populate its detail panel.
    ---@param componentName string
    local function selectComponent(componentName)
        selectedComponent = componentName
        for _, btn in ipairs(sidebarButtons) do
            if btn._cue_componentName == componentName then
                btn._cue_indicator:SetColorTexture(1, 0.85, 0)
                btn._cue_indicator:SetAlpha(1)
            else
                btn._cue_indicator:SetColorTexture(0.4, 0.4, 0.4)
                btn._cue_indicator:SetAlpha(0.6)
            end
        end
        populateDetailPanel(componentName)
    end

    -- Expose for OpenOptionsPanel(tabIndex, componentName)
    selectTrackerComponentFn = selectComponent

    -- Build sidebar buttons grouped with separators
    local yOffset = 0
    for groupIndex, group in ipairs(trackerGroups) do
        -- Group separator (skip for first group)
        if groupIndex > 1 then
            local separator = sidebar:CreateTexture(nil, "ARTWORK")
            separator:SetSnapToPixelGrid(false)
            separator:SetTexelSnappingBias(0)
            separator:SetHeight(1)
            separator:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 5, yOffset - 4)
            separator:SetPoint("RIGHT", sidebar, "RIGHT", -5, 0)
            separator:SetColorTexture(0.3, 0.3, 0.3, 0.8)
            yOffset = yOffset - 9
        end

        -- Group label
        local groupLabel = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        groupLabel:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 5, yOffset)
        groupLabel:SetText(group.label)
        groupLabel:SetTextColor(0.7, 0.7, 0.7)
        yOffset = yOffset - 16

        -- Component buttons
        for _, compName in ipairs(group.components) do
            local displayName = resolveDisplayName(compName)
            local btn = framework:CreateButton(sidebar, function()
                selectComponent(compName)
            end, sidebarWidth - 4, 22, displayName, false, false, false, nil, nil)
            btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, yOffset)
            btn:SetTemplate(buttonTemplate)

            -- Left indicator bar (Plater-style)
            local indicator = btn.widget:CreateTexture(nil, "OVERLAY")
            indicator:SetSnapToPixelGrid(false)
            indicator:SetTexelSnappingBias(0)
            indicator:SetSize(4, 18)
            indicator:SetPoint("LEFT", btn.widget, "LEFT", 2, 0)
            btn._cue_indicator = indicator
            btn._cue_componentName = compName

            sidebarButtons[#sidebarButtons + 1] = btn
            yOffset = yOffset - 24
        end
    end

    -- Refresh the currently selected component when profile changes
    private.Callback.Register("OnProfileChanged", function()
        if selectedComponent then
            populateDetailPanel(selectedComponent)
        end
    end)

    -- Select first component by default
    selectComponent("CooldownTracker")
end

---Build the Profile Management tab content inside panel.
---Embeds the standard AceDBOptions-3.0 profile UI via AceConfigDialog-3.0.
---Profile switch/copy/delete/reset are handled by AceDBOptions; the AceDB
---callbacks registered in Init.lua keep private.profile in sync.
---@param panel frame
local function buildProfileManagementTab(panel)
    local AceGUI = LibStub("AceGUI-3.0")
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")

    -- Split panel: AceDB profiles on top, auto-switching on bottom
    local aceHeight = math.floor(panel:GetHeight() * 0.50)

    local acePanel = CreateFrame("Frame", nil, panel)
    acePanel:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    acePanel:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    acePanel:SetHeight(aceHeight)

    local container = AceGUI:Create("SimpleGroup")
    container:SetLayout("Fill")
    container.frame:SetParent(acePanel)
    container.frame:ClearAllPoints()
    container.frame:SetAllPoints(acePanel)
    container.frame:Show()

    AceConfigDialog:Open("ClassUIEnhanced-Profiles", container)

    -- Auto-switching section below AceDB
    local switchPanel = CreateFrame("Frame", nil, panel)
    switchPanel:SetPoint("TOPLEFT", acePanel, "BOTTOMLEFT", 0, -4)
    switchPanel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    local options_text_template = framework:GetTemplate("font", private.UIDefaults.presets.font)
    local options_dropdown_template = framework:GetTemplate("dropdown", private.UIDefaults.presets.dropdown)
    local options_switch_template = framework:GetTemplate("switch", private.UIDefaults.presets.checkbox)

    ---Build a profile dropdown values list with a grey <Disabled> first entry.
    ---@return table
    local function buildProfileDropdownValues(onClickFn)
        local t = {}
        t[#t + 1] = {
            label = "|cff888888" .. L["DISABLED_OPTION"] .. "|r",
            value = "__disabled__",
            onclick = onClickFn,
        }
        for _, key in ipairs(private.public.db:GetProfiles()) do
            t[#t + 1] = {label = key, value = key, onclick = onClickFn}
        end
        return t
    end

    local settings = private.public.db.global.spec_profile_sync

    -- No spec system (WoW Forever reports one pseudo-spec per class): the two
    -- dual-spec talent groups take the specs' place, and the role section goes,
    -- since the pseudo-spec's role never follows the talents (SpecProfileSync).
    local numSpecs = GetNumSpecializations() or 0
    local playerClassFilename = select(2, UnitClass("player"))
    local hasSpecSystem = numSpecs > 1

    local col_options = {
        {type = "label", get = function() return L["SPEC_PROFILE_SYNC_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

        {
            type = "toggle",
            name = L["SPEC_PROFILE_SYNC_ENABLED"],
            desc = L["SPEC_PROFILE_SYNC_ENABLED_DESC"],
            get = function() return settings.enabled end,
            set = function(_, _, value)
                settings.enabled = value
            end,
        },

        {
            type = "select",
            name = L["SPEC_PROFILE_SYNC_DEFAULT"],
            desc = L["SPEC_PROFILE_SYNC_DEFAULT_DESC"],
            get = function()
                return settings.default_profile or "__disabled__"
            end,
            set = function(_, _, value)
                settings.default_profile = (value ~= "__disabled__") and value or nil
            end,
            values = function()
                return buildProfileDropdownValues(function(_, _, value)
                    settings.default_profile = (value ~= "__disabled__") and value or nil
                end)
            end,
            disableif = function() return not settings.enabled end,
        },

        {type = "blank"},
        {type = "label", get = function() return L[hasSpecSystem and "SPEC_PROFILE_SYNC_SPEC_HEADER" or "SPEC_PROFILE_SYNC_GROUP_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},
    }

    if hasSpecSystem then
        -- Per-spec dropdowns (dynamic for current class)
        for i = 1, numSpecs do
            local specId, _, _, specIcon = C_SpecializationInfo.GetSpecializationInfo(i)
            if specId then
                local specKey = playerClassFilename .. "-" .. i
                col_options[#col_options + 1] = {
                    type = "select",
                    name = private.GetLocalizedClassSpecLabel(playerClassFilename, i),
                    desc = L["SPEC_PROFILE_SYNC_SPEC_DESC"],
                    icontexture = specIcon,
                    get = function()
                        return settings.spec_mappings[specKey] or "__disabled__"
                    end,
                    set = function(_, _, value)
                        settings.spec_mappings[specKey] = (value ~= "__disabled__") and value or nil
                    end,
                    values = function()
                        return buildProfileDropdownValues(function(_, _, value)
                            settings.spec_mappings[specKey] = (value ~= "__disabled__") and value or nil
                        end)
                    end,
                    disableif = function() return not settings.enabled end,
                }
            end
        end
    else
        -- Both groups always: the panel is built once, and a group-2 mapping
        -- set before dual spec is unlocked simply waits for it.
        local groupEntries = {
            {group = 1, label = DUAL_SPEC_PRIMARY or L["SPEC_PROFILE_SYNC_GROUP_1"]},
            {group = 2, label = DUAL_SPEC_SECONDARY or L["SPEC_PROFILE_SYNC_GROUP_2"]},
        }

        for _, entry in ipairs(groupEntries) do
            -- Same key shape as SpecProfileSync's getTalentGroupKey.
            local groupKey = playerClassFilename .. "-G" .. entry.group
            col_options[#col_options + 1] = {
                type = "select",
                name = entry.label,
                desc = L["SPEC_PROFILE_SYNC_GROUP_DESC"],
                get = function()
                    return settings.spec_mappings[groupKey] or "__disabled__"
                end,
                set = function(_, _, value)
                    settings.spec_mappings[groupKey] = (value ~= "__disabled__") and value or nil
                end,
                values = function()
                    return buildProfileDropdownValues(function(_, _, value)
                        settings.spec_mappings[groupKey] = (value ~= "__disabled__") and value or nil
                    end)
                end,
                disableif = function() return not settings.enabled end,
            }
        end
    end

    if hasSpecSystem then
        -- Role fallback section
        col_options[#col_options + 1] = {type = "blank"}
        col_options[#col_options + 1] = {type = "label", get = function() return L["SPEC_PROFILE_SYNC_ROLE_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}

        local roleEntries = {
            {key = "TANK", label = TANK or "Tank"},
            {key = "HEALER", label = HEALER or "Healer"},
            {key = "DAMAGER", label = DAMAGER or "DPS"},
        }

        for _, entry in ipairs(roleEntries) do
            col_options[#col_options + 1] = {
                type = "select",
                name = entry.label,
                desc = L["SPEC_PROFILE_SYNC_ROLE_DESC"],
                get = function()
                    return settings.role_mappings[entry.key] or "__disabled__"
                end,
                set = function(_, _, value)
                    settings.role_mappings[entry.key] = (value ~= "__disabled__") and value or nil
                end,
                values = function()
                    return buildProfileDropdownValues(function(_, _, value)
                        settings.role_mappings[entry.key] = (value ~= "__disabled__") and value or nil
                    end)
                end,
                disableif = function() return not settings.enabled end,
            }
        end
    end

    local col = CreateFrame("Frame", "CUE_SpecProfileSyncCol", switchPanel)
    col:SetPoint("TOPLEFT", switchPanel, "TOPLEFT", 10, 0)
    col:SetPoint("BOTTOMRIGHT", switchPanel, "BOTTOMRIGHT", -10, 0)

    framework:BuildMenu(col, col_options, 0, 0, 500, false, options_text_template, options_dropdown_template, options_switch_template, true)

    -- Re-open AceDB when the tab becomes visible again so the dialog content refreshes
    panel:SetScript("OnShow", function()
        AceConfigDialog:Open("ClassUIEnhanced-Profiles", container)
    end)
end

-- ---------------------------------------------------------------------------
-- Grouped checkbox helper — creates segment checkboxes under section headers
-- ---------------------------------------------------------------------------

---Create segment checkboxes grouped by section headers inside a parent frame.
---Segments are grouped according to their `group` field and the ordered group
---definitions from ProfileManager.GetSegmentGroups(). Each group renders a
---header label followed by checkbox rows. Hovering a checkbox shows a tooltip
---with the segment description.
---@param parent frame
---@param availableIds table<string, boolean>|nil  if non-nil, only these ids are interactable
---@param startY number  y-offset from parent TOPLEFT for the first group header
---@param colWidth number  width per checkbox column
---@param cols number  number of columns
---@return table<string, table> checkboxMap  segId → { checkbox, label }
---@return number endY  y-offset after the last row
---@return table headers  array of created header FontStrings (for cleanup)
local function createGroupedSegmentCheckboxes(parent, availableIds, startY, colWidth, cols)
    local checkboxMap = {}
    local headers = {}
    local y = startY
    local xBase = 10
    local rowHeight = 22
    local groupGap = 6
    local headerHeight = 16

    local segments = private.ProfileManager.GetSegments()
    local groups = private.ProfileManager.GetSegmentGroups()

    for gi, group in ipairs(groups) do
        -- Collect segments belonging to this group
        local groupSegs = {}
        for _, seg in ipairs(segments) do
            if seg.group == group.id then
                groupSegs[#groupSegs + 1] = seg
            end
        end

        if #groupSegs > 0 then
            -- Gap before header (skip for first group)
            if gi > 1 then
                y = y - groupGap
            end

            -- Section header
            local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            header:SetPoint("TOPLEFT", parent, "TOPLEFT", xBase, y)
            header:SetText(L[group.label] or group.id)
            header:SetTextColor(1, 0.82, 0)
            headers[#headers + 1] = header
            y = y - headerHeight

            -- Checkboxes for this group
            local col = 0
            for _, seg in ipairs(groupSegs) do
                local x = xBase + col * colWidth
                local isAvailable = (availableIds == nil) or (availableIds[seg.id] == true)

                local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
                cb:SetSize(20, 20)
                cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
                cb:SetChecked(isAvailable)
                cb:SetEnabled(isAvailable)
                -- Extend hit rect to cover the label text for easier hovering
                cb:SetHitRectInsets(0, -(colWidth - 24), 0, 0)

                local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
                lbl:SetText(L[seg.label] or seg.id)

                -- Tooltip with segment description
                if seg.desc then
                    cb:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:AddLine(L[seg.label] or seg.id, 1, 1, 1)
                        GameTooltip:AddLine(L[seg.desc] or "", nil, nil, nil, true)
                        GameTooltip:Show()
                    end)
                    cb:SetScript("OnLeave", function()
                        GameTooltip:Hide()
                    end)
                end

                if not isAvailable then
                    lbl:SetTextColor(0.4, 0.4, 0.4)
                    cb:SetAlpha(0.4)
                end

                checkboxMap[seg.id] = { checkbox = cb, label = lbl }

                col = col + 1
                if col >= cols then
                    col = 0
                    y = y - rowHeight
                end
            end

            -- If last row was partial, advance y
            if col > 0 then
                y = y - rowHeight
            end
        end
    end

    return checkboxMap, y, headers
end


---Build the Import/Export tab content inside panel.
---The tab has two views:
--- 1. Default view: export checkboxes + buttons, import button, text editor.
--- 2. Import confirmation view: detected segment checkboxes, source info,
---    profile name, import mode radio, confirm/cancel buttons.
---@param panel frame
local function buildImportExportTab(panel)
    local buttonTemplate = private.Templates.ButtonTemplate

    -- =====================================================================
    -- Shared: text editor (always visible at the bottom)
    -- =====================================================================
    local editorLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editorLabel:SetText(L["IMPORT_EXPORT_STRING_LABEL"])

    local editorW = private.Templates.OptionsPanel.width - 40
    local editorH = 100 -- initial height, resized dynamically after layout
    local importExportEditor = framework:NewSpecialLuaEditorEntry(panel, editorW, editorH, "ImportExportEditor", frameName .. "ImportExportEditor", true)
    importExportEditor:SetPoint("TOPLEFT", editorLabel, "BOTTOMLEFT", 0, -5)
    importExportEditor:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 10)
    importExportEditor.editbox:SetMaxBytes(200000)
    importExportEditor.editbox:SetMaxLetters(200000)

    importExportEditor:SetBackdrop({
        edgeFile = [[Interface\Buttons\WHITE8X8]],
        edgeSize = 1,
        bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
        tileSize = 64,
        tile = true
    })
	importExportEditor:SetBackdropBorderColor(.2, .2, .2, 0.8)
	importExportEditor:SetBackdropColor(.1, .1, .1, .8)
	framework:ReskinSlider(importExportEditor.scroll)

    -- Hide the scrollbar — import/export strings are single-line
    importExportEditor.scroll.ScrollBar:Hide()
    importExportEditor.scroll.ScrollBar:HookScript("OnShow", function(self) self:Hide() end)

    -- Click anywhere on the editor area to focus the editbox
    importExportEditor:SetScript("OnMouseDown", function() importExportEditor:SetFocus() end)
    importExportEditor.scroll:SetScript("OnMouseDown", function() importExportEditor:SetFocus() end)

    -- =====================================================================
    -- View 1: Default (export + import trigger)
    -- =====================================================================
    local defaultView = CreateFrame("Frame", nil, panel)
    defaultView:SetAllPoints(panel)

    -- Export section
    local exportHeader = defaultView:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    exportHeader:SetPoint("TOPLEFT", defaultView, "TOPLEFT", 10, -10)
    exportHeader:SetText(L["EXPORT_SEGMENTS_LABEL"])

    local exportCheckboxes, exportEndY = createGroupedSegmentCheckboxes(
        defaultView, nil, -28, 190, 5
    )

    local selectAllExportBtn = framework:CreateButton(defaultView, function()
        for _, entry in pairs(exportCheckboxes) do
            if entry.checkbox:IsEnabled() then entry.checkbox:SetChecked(true) end
        end
    end, 80, 22, L["SELECT_ALL"], false, false, false, nil, nil)
    selectAllExportBtn:SetPoint("TOPLEFT", defaultView, "TOPLEFT", 10, exportEndY - 4)
    selectAllExportBtn:SetTemplate(buttonTemplate)

    local selectNoneExportBtn = framework:CreateButton(defaultView, function()
        for _, entry in pairs(exportCheckboxes) do
            if entry.checkbox:IsEnabled() then entry.checkbox:SetChecked(false) end
        end
    end, 80, 22, L["SELECT_NONE"], false, false, false, nil, nil)
    selectNoneExportBtn:SetPoint("LEFT", selectAllExportBtn.widget, "RIGHT", 5, 0)
    selectNoneExportBtn:SetTemplate(buttonTemplate)

    local exportBtn = framework:CreateButton(defaultView, function()
        local selected = {}
        for segId, entry in pairs(exportCheckboxes) do
            if entry.checkbox:GetChecked() then
                selected[segId] = true
            end
        end
        local str = private.ProfileManager.ExportSegmented(selected)
        importExportEditor:SetText(str)
        importExportEditor:SetFocus()
        importExportEditor:HighlightText()
    end, 100, 28, L["EXPORT_BUTTON"], false, false, false, nil, nil)
    exportBtn:SetPoint("LEFT", selectNoneExportBtn.widget, "RIGHT", 15, 0)
    exportBtn:SetTemplate(buttonTemplate)
    exportBtn:SetIcon([[Interface/AddOns/ClassUIEnhanced/Assets/Textures/OptionsButtons/export_icon.png]], 16, 28, "overlay", {0, 1, 0, 1}, {1, 1, 1, 1}, 2)

    -- Import section (just a trigger button — confirmation happens in view 2)
    local importHeader = defaultView:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    importHeader:SetPoint("TOPLEFT", selectAllExportBtn.widget, "BOTTOMLEFT", 0, -16)
    importHeader:SetText(L["IMPORT_BUTTON"])

    -- =====================================================================
    -- View 2: Import confirmation (shown after clicking Import)
    -- =====================================================================
    local confirmView = CreateFrame("Frame", nil, panel)
    confirmView:SetAllPoints(panel)
    confirmView:Hide()

    -- Populated dynamically when import is triggered
    local confirmCheckboxes = {}
    local confirmHeaders = {}
    local confirmSourceInfo
    local confirmSourceUrl
    local confirmUrlBox
    local confirmSegLabel
    local importAsNewRadio
    local importIntoCurrentRadio
    local confirmNameEntry
    local confirmNameLabel
    local pendingEnvelope

    ---Show the import confirmation view with detected segments.
    ---@param envelope table  parsed envelope from parseEnvelope()
    local function showImportConfirmation(envelope)
        pendingEnvelope = envelope
        defaultView:Hide()
        confirmView:Show()

        -- Clear previous dynamic content
        for _, entry in pairs(confirmCheckboxes) do
            entry.checkbox:Hide()
            entry.checkbox:SetParent(nil)
            entry.label:Hide()
        end
        confirmCheckboxes = {}
        for _, h in ipairs(confirmHeaders) do
            h:Hide()
        end
        confirmHeaders = {}

        -- Build available segment set
        local availableIds = {}
        for _, segId in ipairs(envelope.segments) do
            availableIds[segId] = true
        end

        -- Source info line
        if not confirmSourceInfo then
            confirmSourceInfo = confirmView:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            confirmSourceInfo:SetPoint("TOPLEFT", confirmView, "TOPLEFT", 10, -10)
            confirmSourceInfo:SetTextColor(0.7, 0.7, 0.7)
        end

        if envelope.name and envelope.semver then
            local tocStr = envelope.toc_version and tostring(envelope.toc_version) or "?"
            confirmSourceInfo:SetText(string.format(L["IMPORT_SOURCE_INFO"], envelope.name, envelope.semver, tocStr))
        elseif envelope.name then
            confirmSourceInfo:SetText(string.format(L["IMPORT_SOURCE_INFO_NO_VERSION"], envelope.name))
        else
            confirmSourceInfo:SetText("")
        end
        confirmSourceInfo:Show()

        -- URL (copyable EditBox) and/or revision info
        if not confirmUrlBox then
            confirmUrlBox = CreateFrame("EditBox", frameName .. "ConfirmUrlBox", confirmView, "InputBoxTemplate")
            confirmUrlBox:SetSize(350, 22)
            confirmUrlBox:SetAutoFocus(false)
            confirmUrlBox:SetFontObject(GameFontHighlightSmall)
            confirmUrlBox:SetScript("OnTextChanged", function(self, userInput)
                if userInput then
                    self:SetText(self._cue_url or "")
                    self:HighlightText()
                end
            end)
            confirmUrlBox:SetScript("OnEditFocusGained", function(self)
                self:HighlightText()
            end)
            confirmUrlBox:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
            end)
        end
        if not confirmSourceUrl then
            confirmSourceUrl = confirmView:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            confirmSourceUrl:SetTextColor(0.5, 0.7, 1.0)
        end

        confirmUrlBox:ClearAllPoints()
        confirmSourceUrl:ClearAllPoints()

        if envelope.url then
            confirmUrlBox._cue_url = envelope.url
            confirmUrlBox:SetText(envelope.url)
            confirmUrlBox:SetPoint("TOPLEFT", confirmSourceInfo, "BOTTOMLEFT", 0, -4)
            confirmUrlBox:Show()
            if envelope.version then
                confirmSourceUrl:SetPoint("LEFT", confirmUrlBox, "RIGHT", 8, 0)
                confirmSourceUrl:SetText("(revision " .. tostring(envelope.version) .. ")")
                confirmSourceUrl:Show()
            else
                confirmSourceUrl:Hide()
            end
        elseif envelope.version then
            confirmUrlBox:Hide()
            confirmSourceUrl:SetPoint("TOPLEFT", confirmSourceInfo, "BOTTOMLEFT", 0, -2)
            confirmSourceUrl:SetText(string.format(L["IMPORT_SOURCE_REVISION_ONLY"], tostring(envelope.version)))
            confirmSourceUrl:Show()
        else
            confirmUrlBox:Hide()
            confirmSourceUrl:Hide()
        end

        -- Segment checkboxes
        if not confirmSegLabel then
            confirmSegLabel = confirmView:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        local segLabelAnchor
        if confirmUrlBox:IsShown() then
            segLabelAnchor = confirmUrlBox
        elseif confirmSourceUrl:IsShown() then
            segLabelAnchor = confirmSourceUrl
        else
            segLabelAnchor = confirmSourceInfo
        end
        confirmSegLabel:ClearAllPoints()
        confirmSegLabel:SetPoint("TOPLEFT", segLabelAnchor, "BOTTOMLEFT", 0, -10)
        confirmSegLabel:SetText(L["IMPORT_SEGMENTS_LABEL"])
        confirmSegLabel:Show()

        local sourceHeight = confirmSourceInfo:GetStringHeight()
        if confirmUrlBox:IsShown() then
            sourceHeight = sourceHeight + 4 + confirmUrlBox:GetHeight()
        elseif confirmSourceUrl:IsShown() then
            sourceHeight = sourceHeight + 2 + confirmSourceUrl:GetStringHeight()
        end
        local labelBottom = -10 - sourceHeight - 10
        confirmCheckboxes, _, confirmHeaders = createGroupedSegmentCheckboxes(
            confirmView, availableIds, labelBottom - 18, 190, 5
        )

        -- Pre-fill profile name from envelope
        if envelope.name then
            confirmNameEntry:SetText(envelope.name)
        else
            confirmNameEntry:SetText(L["DEFAULT_PROFILE_NAME"])
        end

        -- Default import mode: if the envelope name differs from the current
        -- profile, default to "import as new" so the user doesn't accidentally
        -- overwrite their active profile with someone else's settings.
        local currentProfileName = private.ProfileManager.GetCurrentProfileKey()
        local namesDiffer = envelope.name and envelope.name ~= currentProfileName
        if namesDiffer then
            importAsNewRadio:SetChecked(true)
            importIntoCurrentRadio:SetChecked(false)
            confirmNameEntry:Enable()
            confirmNameLabel:SetTextColor(1, 1, 1)
        else
            importIntoCurrentRadio:SetChecked(true)
            importAsNewRadio:SetChecked(false)
            confirmNameEntry:Disable()
            confirmNameLabel:SetTextColor(0.4, 0.4, 0.4)
        end
    end

    ---Hide confirmation view, return to default.
    local function hideImportConfirmation()
        confirmView:Hide()
        defaultView:Show()
        pendingEnvelope = nil
        importExportEditor:SetText("")
    end

    ---Execute the confirmed import.
    local function executeImport()
        if not pendingEnvelope then return end

        -- Gather selected segments
        local selectedSegIds = {}
        for segId, entry in pairs(confirmCheckboxes) do
            if entry.checkbox:IsEnabled() and entry.checkbox:GetChecked() then
                selectedSegIds[#selectedSegIds + 1] = segId
            end
        end

        if #selectedSegIds == 0 then
            private.print(L["IMPORT_NO_SEGMENTS_SELECTED"])
            return
        end

        local profileName = confirmNameEntry:GetText()
        if not profileName or profileName == "" then profileName = L["DEFAULT_PROFILE_NAME"] end
        local asNew = importAsNewRadio and importAsNewRadio:GetChecked()

        local ok, err = private.ProfileManager.ImportSegmented(
            pendingEnvelope, selectedSegIds, profileName, asNew
        )

        if ok then
            private.print(string.format(L["PARTIAL_IMPORT_APPLIED"], #selectedSegIds, profileName))
            refreshBuildMenuColumns()
            if not asNew then
                private.Callback.Trigger("OnProfileChanged")
            end
        else
            private.print(string.format(L["IMPORT_FAILED"], err or "unknown"))
        end

        hideImportConfirmation()
    end

    -- Import trigger button (in default view)
    local importBtn = framework:CreateButton(defaultView, function()
        local str = importExportEditor:GetText()
        local decoded, err = private.ProfileManager.DecompressData(str)
        if not decoded then
            private.print(string.format(L["IMPORT_FAILED"], err or "unknown error"))
            return
        end
        local envelope, perr = private.ProfileManager.ParseEnvelope(decoded)
        if not envelope then
            private.print(string.format(L["IMPORT_FAILED"], perr or "unknown error"))
            return
        end
        showImportConfirmation(envelope)
    end, 100, 28, L["IMPORT_BUTTON"], false, false, false, nil, nil)
    importBtn:SetPoint("TOPLEFT", importHeader, "BOTTOMLEFT", 0, -8)
    importBtn:SetTemplate(buttonTemplate)
    importBtn:SetIcon([[Interface/AddOns/ClassUIEnhanced/Assets/Textures/OptionsButtons/import_icon.png]], 16, 28, "overlay", {0, 1, 0, 1}, {1, 1, 1, 1}, 2)

    -- Position editor label dynamically below the import button
    editorLabel:SetPoint("TOPLEFT", importBtn.widget, "BOTTOMLEFT", 0, -10)

    -- Profile source info (shows _sharing metadata for the current profile)
    local profileSourceInfo = defaultView:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    profileSourceInfo:SetPoint("TOPRIGHT", defaultView, "TOPRIGHT", -10, -12)
    profileSourceInfo:SetJustifyH("RIGHT")
    profileSourceInfo:SetWordWrap(false)
    profileSourceInfo:SetTextColor(0.5, 0.5, 0.5)

    -- Copyable URL for the current profile's sharing metadata
    local profileUrlBox = CreateFrame("EditBox", frameName .. "ProfileUrlBox", defaultView, "InputBoxTemplate")
    profileUrlBox:SetSize(300, 22)
    profileUrlBox:SetAutoFocus(false)
    profileUrlBox:SetFontObject(GameFontHighlightSmall)
    profileUrlBox:SetJustifyH("RIGHT")
    profileUrlBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(self._cue_url or "")
            self:HighlightText()
        end
    end)
    profileUrlBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    profileUrlBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    profileUrlBox:Hide()

    local function updateProfileSourceDisplay()
        local sharing = private.profile and private.profile._sharing
        if not sharing or (not sharing.semver and not sharing.url and not sharing.version) then
            profileSourceInfo:Hide()
            profileUrlBox:Hide()
            return
        end
        -- Build text metadata (non-URL parts)
        local parts = {}
        if sharing.semver then
            parts[#parts + 1] = "v" .. sharing.semver
        end
        if sharing.version then
            parts[#parts + 1] = "revision " .. tostring(sharing.version)
        end
        if #parts > 0 then
            profileSourceInfo:SetText(L["PROFILE_SOURCE_LABEL"] .. " " .. table.concat(parts, " | "))
        else
            profileSourceInfo:SetText(L["PROFILE_SOURCE_LABEL"])
        end
        profileSourceInfo:Show()

        -- URL in copyable EditBox
        if sharing.url then
            profileUrlBox._cue_url = sharing.url
            profileUrlBox:SetText(sharing.url)
            profileUrlBox:ClearAllPoints()
            profileUrlBox:SetPoint("TOPRIGHT", profileSourceInfo, "BOTTOMRIGHT", 0, -2)
            profileUrlBox:Show()
        else
            profileUrlBox:Hide()
        end
    end

    defaultView:HookScript("OnShow", updateProfileSourceDisplay)
    panel:HookScript("OnShow", function()
        if defaultView:IsShown() then
            updateProfileSourceDisplay()
        end
    end)
    updateProfileSourceDisplay()

    -- Confirm view: bottom section (two rows, anchored from bottom)
    -- Row 1 (bottom): confirm + cancel + profile name on one line
    local confirmBtn = framework:CreateButton(confirmView, executeImport, 120, 28, L["CONFIRM_IMPORT"], false, false, false, nil, nil)
    confirmBtn:SetPoint("BOTTOMLEFT", editorLabel, "TOPLEFT", 0, -4)
    confirmBtn:SetTemplate(buttonTemplate)

    local cancelBtn = framework:CreateButton(confirmView, hideImportConfirmation, 80, 28, L["CANCEL_IMPORT"], false, false, false, nil, nil)
    cancelBtn:SetPoint("LEFT", confirmBtn.widget, "RIGHT", 5, 0)
    cancelBtn:SetTemplate(buttonTemplate)

    confirmNameLabel = confirmView:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    confirmNameLabel:SetPoint("LEFT", cancelBtn.widget, "RIGHT", 20, 0)
    confirmNameLabel:SetText(L["PROFILE_NAME_LABEL"])

    confirmNameEntry = framework:CreateTextEntry(confirmView, function() end, 200, 24, "ConfirmProfileName", frameName .. "ConfirmProfileName", L["DEFAULT_PROFILE_NAME"])
    confirmNameEntry:SetPoint("LEFT", confirmNameLabel, "RIGHT", 8, 0)

    -- Row 2: import mode radios + select all/none on one line
    importIntoCurrentRadio = CreateFrame("CheckButton", nil, confirmView, "UICheckButtonTemplate")
    importIntoCurrentRadio:SetSize(20, 20)
    importIntoCurrentRadio:SetPoint("BOTTOMLEFT", confirmBtn.widget, "TOPLEFT", 0, 4)
    importIntoCurrentRadio:SetChecked(true)
    local intoCurLabel = importIntoCurrentRadio:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intoCurLabel:SetPoint("LEFT", importIntoCurrentRadio, "RIGHT", 4, 0)
    intoCurLabel:SetText(L["IMPORT_INTO_CURRENT"])

    importAsNewRadio = CreateFrame("CheckButton", nil, confirmView, "UICheckButtonTemplate")
    importAsNewRadio:SetSize(20, 20)
    importAsNewRadio:SetPoint("LEFT", intoCurLabel, "RIGHT", 15, 0)
    importAsNewRadio:SetChecked(false)
    local asNewLabel = importAsNewRadio:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    asNewLabel:SetPoint("LEFT", importAsNewRadio, "RIGHT", 4, 0)
    asNewLabel:SetText(L["IMPORT_AS_NEW"])

    local selectAllImportBtn = framework:CreateButton(confirmView, function()
        for _, entry in pairs(confirmCheckboxes) do
            if entry.checkbox:IsEnabled() then entry.checkbox:SetChecked(true) end
        end
    end, 80, 22, L["SELECT_ALL"], false, false, false, nil, nil)
    selectAllImportBtn:SetPoint("LEFT", asNewLabel, "RIGHT", 20, 0)
    selectAllImportBtn:SetTemplate(buttonTemplate)

    local selectNoneImportBtn = framework:CreateButton(confirmView, function()
        for _, entry in pairs(confirmCheckboxes) do
            if entry.checkbox:IsEnabled() then entry.checkbox:SetChecked(false) end
        end
    end, 80, 22, L["SELECT_NONE"], false, false, false, nil, nil)
    selectNoneImportBtn:SetPoint("LEFT", selectAllImportBtn.widget, "RIGHT", 5, 0)
    selectNoneImportBtn:SetTemplate(buttonTemplate)

    -- Radio button mutual exclusion + name entry enable/disable
    importIntoCurrentRadio:SetScript("OnClick", function(self)
        self:SetChecked(true)
        importAsNewRadio:SetChecked(false)
        confirmNameEntry:Disable()
        confirmNameLabel:SetTextColor(0.4, 0.4, 0.4)
    end)
    importAsNewRadio:SetScript("OnClick", function(self)
        self:SetChecked(true)
        importIntoCurrentRadio:SetChecked(false)
        confirmNameEntry:Enable()
        confirmNameLabel:SetTextColor(1, 1, 1)
    end)

    -- Initial state: importing into current, name entry disabled
    confirmNameEntry:Disable()
    confirmNameLabel:SetTextColor(0.4, 0.4, 0.4)
end


---Convert raw changelog markdown to WoW-formatted text with color codes.
---@param raw string
---@return string
local function formatChangelog(raw)
    local lines = {}
    local started = false
    local lastWasVersion = false
    for line in raw:gmatch("[^\n]*") do
        if not started then
            if line:match("^## ") then
                started = true
            end
        end
        if started then
            local version = line:match("^## (.+)")
            local section = line:match("^### (.+)")
            local bullet = line:match("^%- (.+)")
            if version then
                if #lines > 0 then
                    lines[#lines + 1] = ""
                    lines[#lines + 1] = ""
                end
                lines[#lines + 1] = "|cffffcc00" .. version .. "|r"
                lastWasVersion = true
            elseif section then
                if not lastWasVersion then
                    lines[#lines + 1] = ""
                end
                lastWasVersion = false
                lines[#lines + 1] = "|cffff9900  " .. section .. "|r"
            elseif bullet then
                lastWasVersion = false
                bullet = bullet:gsub("%*%*(.-)%*%*", "%1")
                lines[#lines + 1] = "    \226\128\162 " .. bullet
            elseif line ~= "" then
                lastWasVersion = false
                lines[#lines + 1] = "    " .. line:gsub("%*%*(.-)%*%*", "%1")
            end
        end
    end
    return table.concat(lines, "\n")
end

---Changelog popup frame (lazy-created on first button click).
---@type frame?
local changelogFrame

---Show the changelog popup, creating it on first use.
local function showChangelogPopup()
    if not changelogFrame then
        local popupName = frameName .. "ChangelogPopup"
        changelogFrame = framework:CreateRoundedPanel(uiParent, popupName, private.Templates.RoundedCornerPreset)
        changelogFrame:SetSize(800, 500)
        changelogFrame:SetPoint("CENTER", uiParent, "CENTER", 0, 0)
        changelogFrame:SetFrameStrata("DIALOG")
        changelogFrame:SetToplevel(true)
        framework:MakeDraggable(changelogFrame)
        tinsert(UISpecialFrames, popupName)

        -- Close button (same style as main options panel)
        local closeBtn = CreateFrame("Button", nil, changelogFrame)
        closeBtn:SetSize(16, 16)
        closeBtn:SetPoint("TOPRIGHT", changelogFrame, "TOPRIGHT", -8, -8)
        closeBtn:SetNormalTexture([[Interface\GLUES\LOGIN\Glues-CheckBox-Check]])
        closeBtn:SetHighlightTexture([[Interface\GLUES\LOGIN\Glues-CheckBox-Check]])
        closeBtn:SetPushedTexture([[Interface\GLUES\LOGIN\Glues-CheckBox-Check]])
        closeBtn:GetNormalTexture():SetDesaturated(true)
        closeBtn:GetHighlightTexture():SetDesaturated(true)
        closeBtn:GetPushedTexture():SetDesaturated(true)
        closeBtn:SetAlpha(0.7)
        closeBtn:SetScript("OnClick", function() changelogFrame:Hide() end)

        -- Title
        local title = changelogFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", changelogFrame, "TOP", 0, -10)
        title:SetText(L["ABOUT_CHANGELOG"])
        title:SetTextColor(1, 0.82, 0)

        -- Scrollable text area
        local scrollFrame = CreateFrame("ScrollFrame", popupName .. "Scroll", changelogFrame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", changelogFrame, "TOPLEFT", 15, -35)
        scrollFrame:SetPoint("BOTTOMRIGHT", changelogFrame, "BOTTOMRIGHT", -30, 15)

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(750)
        scrollFrame:SetScrollChild(scrollChild)

        local text = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        text:SetWidth(750)
        text:SetWordWrap(true)
        text:SetJustifyH("LEFT")

        if private.changelog then
            text:SetText(formatChangelog(private.changelog))
        else
            text:SetText(L["ABOUT_CHANGELOG_DEV"])
        end

        scrollChild:SetHeight(text:GetStringHeight() + 20)
    end

    changelogFrame:Show()
    -- Same strata as the options panel (frame level 400); a fresh frame starts far below it.
    changelogFrame:Raise()
end

-- ---------------------------------------------------------------------------
-- Additional Frames tab (sidebar + detail panel)
-- ---------------------------------------------------------------------------

---Forward-declared rebuild function (set inside buildAdditionalFramesTab).
local buildAdditionalFramesTab_Rebuild

---Build the Additional Frames tab with sidebar + detail panel layout.
---@param panel frame
local function buildAdditionalFramesTab(panel)
    local buttonTemplate = private.Templates.ButtonTemplate
    local options_text_template = framework:GetTemplate("font", private.UIDefaults.presets.font)
    local options_dropdown_template = framework:GetTemplate("dropdown", private.UIDefaults.presets.dropdown)
    local options_switch_template = framework:GetTemplate("switch", private.UIDefaults.presets.checkbox)
    local options_slider_template = framework:GetTemplate("slider", private.UIDefaults.presets.slider)
    local options_button_template = framework:GetTemplate("button", private.UIDefaults.presets.button)

    -- Description
    local description = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    description:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -5)
    description:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    description:SetWordWrap(true)
    description:SetNonSpaceWrap(true)
    description:SetJustifyH("LEFT")
    description:SetText(L["ADDITIONAL_FRAMES_DESC"])
    description:SetTextColor(0.7, 0.7, 0.7)

    -- =====================================================================
    -- Left sidebar: Create buttons + frame list
    -- =====================================================================
    local sidebarWidth = 180
    local sidebar = CreateFrame("Frame", frameName .. "AFSidebar", panel)
    sidebar:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -10)
    sidebar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 10)
    sidebar:SetWidth(sidebarWidth)

    -- Create buttons
    local createSpellsBtn = framework:CreateButton(sidebar, function()
        local id = private.AdditionalFrameManager.CreateFrame("spells", L["NEW_SPELLS_FRAME_NAME"])
        if id then
            C_Timer.After(0, function()
                -- Rebuild UI and select the new frame
                buildAdditionalFramesTab_Rebuild(id)
            end)
        end
    end, 56, 22, L["CREATE_SPELLS_FRAME"], false, false, false, nil, nil)
    createSpellsBtn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0)
    createSpellsBtn:SetTemplate(buttonTemplate)

    local createBuffsBtn = framework:CreateButton(sidebar, function()
        local id = private.AdditionalFrameManager.CreateFrame("buffs", L["NEW_BUFFS_FRAME_NAME"])
        if id then
            C_Timer.After(0, function()
                buildAdditionalFramesTab_Rebuild(id)
            end)
        end
    end, 56, 22, L["CREATE_BUFFS_FRAME"], false, false, false, nil, nil)
    createBuffsBtn:SetPoint("LEFT", createSpellsBtn.widget, "RIGHT", 3, 0)
    createBuffsBtn:SetTemplate(buttonTemplate)

    local createBarBtn = framework:CreateButton(sidebar, function()
        local id = private.AdditionalFrameManager.CreateFrame("bar", L["NEW_BAR_FRAME_NAME"])
        if id then
            C_Timer.After(0, function()
                buildAdditionalFramesTab_Rebuild(id)
            end)
        end
    end, 56, 22, L["CREATE_BAR_FRAME"], false, false, false, nil, nil)
    createBarBtn:SetPoint("LEFT", createBuffsBtn.widget, "RIGHT", 3, 0)
    createBarBtn:SetTemplate(buttonTemplate)

    -- Frame list (scrollable area)
    local listTop = -30
    local listButtons = {}
    local selectedFrameId = nil

    -- 22 = the template's scrollbar, which sits outside the frame's right edge
    local listScrollFrame = CreateFrame("ScrollFrame", frameName .. "AFListScrollFrame", sidebar, "UIPanelScrollFrameTemplate")
    listScrollFrame:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, listTop)
    listScrollFrame:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -22, 0)
    -- Scrollbar only while the list overflows (ScrollFrame_OnScrollRangeChanged)
    listScrollFrame.scrollBarHideable = true
    listScrollFrame.ScrollBar:Hide()

    local listScrollChild = CreateFrame("Frame", frameName .. "AFListScrollChild", listScrollFrame)
    listScrollChild:SetWidth(sidebarWidth - 22)
    listScrollFrame:SetScrollChild(listScrollChild)

    -- =====================================================================
    -- Right detail panel
    -- =====================================================================
    local detailPanel = CreateFrame("Frame", frameName .. "AFDetail", panel)
    detailPanel:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 10, 0)
    detailPanel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 10)

    -- Empty state message
    local emptyLabel = detailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyLabel:SetPoint("CENTER", detailPanel, "CENTER", 0, 0)
    emptyLabel:SetText(L["NO_FRAMES_CREATED"])
    emptyLabel:SetTextColor(0.5, 0.5, 0.5)
    emptyLabel:SetJustifyH("CENTER")

    -- Scrollable detail area (same pattern as Trackers tab)
    local detailTotalWidth = private.Templates.OptionsPanel.width - 20 - sidebarWidth - 10
    local scrollbarMargin = 30
    local availableWidth = detailTotalWidth - scrollbarMargin

    local afScrollFrame = CreateFrame("ScrollFrame", frameName .. "AFScrollFrame", detailPanel, "UIPanelScrollFrameTemplate")
    afScrollFrame:SetPoint("TOPLEFT", detailPanel, "TOPLEFT", 0, 0)
    afScrollFrame:SetPoint("BOTTOMRIGHT", detailPanel, "BOTTOMRIGHT", 0, 0)
    afScrollFrame:Hide()

    local afScrollChild = CreateFrame("Frame", frameName .. "AFScrollChild", afScrollFrame)
    afScrollChild:SetWidth(availableWidth)
    afScrollFrame:SetScrollChild(afScrollChild)

    -- Detail content container (hidden when no frame selected)
    local detailContent = CreateFrame("Frame", nil, afScrollChild)
    detailContent:SetPoint("TOPLEFT", afScrollChild, "TOPLEFT", 0, 0)
    detailContent:SetPoint("RIGHT", afScrollChild, "RIGHT", 0, 0)

    -- Frame name entry
    local nameLabel = detailContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", detailContent, "TOPLEFT", 0, 0)
    nameLabel:SetText(L["FRAME_NAME_LABEL"])
    nameLabel:SetTextColor(1, 0.82, 0)

    local nameEntry = framework:CreateTextEntry(detailContent, function(_, _, text)
        if selectedFrameId and private.profile.additional_frames[selectedFrameId] then
            private.profile.additional_frames[selectedFrameId].name = text
            -- Update EditMode display name (editModeName is read dynamically by
            -- LibEditMode's GetSystemName closure)
            local comp = private.ComponentManager.GetComponent("AdditionalFrame_" .. selectedFrameId)
            if comp and comp.GetFrame then
                local f = comp.GetFrame()
                if f then f.editModeName = text end
            end
            -- Update sidebar button text
            buildAdditionalFramesTab_Rebuild(selectedFrameId)
        end
    end, 250, 22, "AFNameEntry", frameName .. "AFNameEntry")
    nameEntry:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -3)

    -- Frame type indicator
    local typeLabel = detailContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeLabel:SetPoint("LEFT", nameEntry.widget, "RIGHT", 10, 0)
    typeLabel:SetTextColor(0.6, 0.6, 0.6)

    -- Delete button
    local deleteBtn = framework:CreateButton(detailContent, function()
        if selectedFrameId and private.profile.additional_frames[selectedFrameId] then
            local frameName2 = private.profile.additional_frames[selectedFrameId].name or selectedFrameId
            -- The id rides on the dialog: OnAccept must delete the frame the
            -- dialog named, not whatever is selected when Yes is clicked.
            StaticPopup_Show("CLASSUIENHANCED_DELETE_AF", frameName2, nil, selectedFrameId)
        end
    end, 80, 22, L["DELETE_FRAME"], false, false, false, nil, nil)
    deleteBtn:SetPoint("LEFT", typeLabel, "RIGHT", 15, 0)
    deleteBtn:SetTemplate(buttonTemplate)

    -- Enabled toggle
    local enabledToggle = framework:CreateSwitch(detailContent, function(_, _, value)
        if not selectedFrameId then return end
        local s = private.profile.additional_frames[selectedFrameId]
        if not s then return end
        local instance = private.AdditionalFrameManager.GetInstance(selectedFrameId)
        if instance then
            if value then
                private.ComponentManager.EnableComponent(instance.component.name)
            else
                private.ComponentManager.DisableComponent(instance.component.name)
            end
        end
    end, true, nil, nil, nil, nil, "AFEnabled", frameName .. "AFEnabled")
    enabledToggle:SetTemplate(options_switch_template)
    enabledToggle:SetAsCheckBox()
    enabledToggle:SetPoint("LEFT", deleteBtn.widget, "RIGHT", 15, 0)
    local enabledLabel = detailContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    enabledLabel:SetPoint("LEFT", enabledToggle.widget, "RIGHT", 5, 0)
    enabledLabel:SetText(L["SETTING_ENABLED"])
    enabledLabel:SetTextColor(0.9, 0.9, 0.9)

    -- The frame's spells, items, order, custom spells and per-spell settings
    -- are edited in the Tracking tab; this opens it on the frame's section.
    local editInTrackingBtn = framework:CreateButton(detailContent, function()
        if selectedFrameId then
            private.Options.OpenOptionsPanel(options.TRACKING_TAB_INDEX, "AdditionalFrame_" .. selectedFrameId)
        end
    end, 240, 22, L["TRACKERS_EDIT_IN_TRACKING"], false, false, false, nil, nil)
    editInTrackingBtn:SetTemplate(buttonTemplate)
    editInTrackingBtn.widget:SetWidth(editInTrackingBtn.widget.text:GetStringWidth() + 24)
    editInTrackingBtn:SetPoint("TOPLEFT", nameEntry.widget, "BOTTOMLEFT", 0, -15)
    editInTrackingBtn:SetTooltip(L["AF_EDIT_IN_TRACKING_DESC"])

    -- Three-column layout for settings below the button: Visibility + Anchoring | Layout + Size | Fonts
    local settingsGap = 10
    local settingsColWidth = math.floor((availableWidth - settingsGap * 2) / 3)

    -- =====================================================================
    -- Settings panels (three columns below the Tracking-tab button)
    -- =====================================================================
    local col1Offset = 0
    local col2Offset = settingsColWidth + settingsGap
    local col3Offset = (settingsColWidth + settingsGap) * 2

    -- Column frames (section headers are inline via orange labels in widget arrays)
    -- Reuse old frame names to ensure stale frames from prior sessions are overwritten
    local col1Frame = CreateFrame("Frame", frameName .. "AFVisCol", detailContent)
    col1Frame:SetPoint("TOPLEFT", editInTrackingBtn.widget, "BOTTOMLEFT", col1Offset, -25)
    col1Frame:SetWidth(settingsColWidth)
    col1Frame:SetHeight(400)

    local col2Frame = CreateFrame("Frame", frameName .. "AFLayoutCol", detailContent)
    col2Frame:SetPoint("TOPLEFT", editInTrackingBtn.widget, "BOTTOMLEFT", col2Offset, -25)
    col2Frame:SetWidth(settingsColWidth)
    col2Frame:SetHeight(400)

    local col3Frame = CreateFrame("Frame", frameName .. "AFSizeCol", detailContent)
    col3Frame:SetPoint("TOPLEFT", editInTrackingBtn.widget, "BOTTOMLEFT", col3Offset, -25)
    col3Frame:SetWidth(settingsColWidth)
    col3Frame:SetHeight(400)

    optionsPanelColumns[#optionsPanelColumns + 1] = col1Frame
    optionsPanelColumns[#optionsPanelColumns + 1] = col2Frame
    optionsPanelColumns[#optionsPanelColumns + 1] = col3Frame

    -- Hide stale frames from the old 4-column layout that may persist in the widget pool
    local staleNames = {"AFAnchorCol", "AFCol1", "AFCol2", "AFCol3", "AFFontCol1", "AFFontCol2", "AFFontCol3"}
    for _, name in ipairs(staleNames) do
        local stale = _G[frameName .. name]
        if stale then stale:Hide() end
    end

    ---Refresh all three additional-frame settings columns so widgets re-read values.
    local function refreshAFColumns()
        if col1Frame.RefreshOptions then col1Frame:RefreshOptions() end
        if col2Frame.RefreshOptions then col2Frame:RefreshOptions() end
        if col3Frame.RefreshOptions then col3Frame:RefreshOptions() end
    end

    ---Refresh the selected additional frame after a setting change.
    local function refreshSelectedFrame()
        if not selectedFrameId then return end
        local instance = private.AdditionalFrameManager.GetInstance(selectedFrameId)
        if instance then instance.component.Refresh() end
        private.ComponentManager.RefreshAllComponents()
        private.Anchor.Refresh()
    end

    ---Estimate the pixel height consumed by a BuildMenu widget array.
    ---@param widgets table[]
    ---@return number
    local function estimateWidgetHeight(widgets)
        local h = 0
        for _, w in ipairs(widgets) do
            -- BuildMenuVolatile skips a hidden widget entirely (it never even
            -- advances its Y offset), so counting one here inflates the column
            -- and leaves a gap where the widget would have been.
            if w.hidden then
            elseif w.type == "blank" then
                h = h + 20
            elseif w.type == "label" then
                h = h + 22
            else
                h = h + 28
            end
        end
        return h
    end

    ---Build font widgets for an additional frame font key.
    ---@param fontKey string  e.g. "timer_font", "name_font"
    ---@param headerLabel string  label shown above the controls
    ---@param maxSize number  max font size for the slider
    ---@param refreshFn function  called after each change
    ---@param hasPosition? boolean  when true, append anchor point + offset controls
    ---@return table[]
    local function buildAFFontWidgets(fontKey, headerLabel, maxSize, refreshFn, hasPosition)
        local emptyFont = {font_face = "Friz Quadrata TT", font_size = 12, font_flags = "OUTLINE"}
        ---@return table
        local function getFontSettings()
            local af = selectedFrameId and private.profile.additional_frames[selectedFrameId]
            return af and af[fontKey] or emptyFont
        end
        local function hasOutline()
            local flags = getFontSettings().font_flags
            return flags ~= "" and flags ~= "NONE"
        end
        local widgets = {
            {type = "label", get = function() return headerLabel end, text_template = orangeFontTemplate, color = orangeFontTemplate.color},

            {
                type = "selectfont",
                name = L["SETTING_FONT"],
                desc = L["SETTING_FONT_DESC"],
                get = function() return getFontSettings().font_face end,
                set = function(_, _, value) getFontSettings().font_face = value; refreshFn() end,
            },

            {
                type = "range",
                name = L["SETTING_FONT_SIZE"],
                desc = L["SETTING_FONT_SIZE_DESC"],
                min = 6, max = maxSize, step = 1,
                get = function() return getFontSettings().font_size end,
                set = function(_, _, value) getFontSettings().font_size = value; refreshFn() end,
            },

            {
                type = "selectoutline",
                name = L["SETTING_FONT_OUTLINE"],
                desc = L["SETTING_FONT_OUTLINE_DESC"],
                get = function() return getFontSettings().font_flags end,
                set = function(_, _, value)
                    getFontSettings().font_flags = value
                    if value ~= "" and value ~= "NONE" then
                        getFontSettings().shadow_color = {0, 0, 0, 1}
                        getFontSettings().shadow_offset_x = 1
                        getFontSettings().shadow_offset_y = -1
                    end
                    refreshFn()
                end,
            },

            {
                type = "color",
                name = L["SETTING_FONT_COLOR"],
                desc = L["SETTING_FONT_COLOR_DESC"],
                boxfirst = true,
                get = function()
                    local c = getFontSettings().font_color or {1, 1, 1, 1}
                    return private.Util.Color(c)
                end,
                set = function(_, r, g, b, a)
                    getFontSettings().font_color = {r, g, b, a}
                    refreshFn()
                end,
            },

            {
                type = "color",
                name = L["SETTING_FONT_SHADOW_COLOR"],
                desc = L["SETTING_FONT_SHADOW_COLOR_DESC"],
                boxfirst = true,
                get = function()
                    local c = getFontSettings().shadow_color or {0, 0, 0, 1}
                    return private.Util.Color(c)
                end,
                set = function(_, r, g, b, a)
                    getFontSettings().shadow_color = {r, g, b, a}
                    refreshFn()
                end,
                disableif = hasOutline,
            },

            {
                type = "range",
                name = L["SETTING_FONT_SHADOW_OFFSET_X"],
                desc = L["SETTING_FONT_SHADOW_OFFSET_X_DESC"],
                min = -5, max = 5, step = 1,
                get = function() return getFontSettings().shadow_offset_x or 1 end,
                set = function(_, _, value) getFontSettings().shadow_offset_x = value; refreshFn() end,
                disableif = hasOutline,
            },

            {
                type = "range",
                name = L["SETTING_FONT_SHADOW_OFFSET_Y"],
                desc = L["SETTING_FONT_SHADOW_OFFSET_Y_DESC"],
                min = -5, max = 5, step = 1,
                get = function() return getFontSettings().shadow_offset_y or -1 end,
                set = function(_, _, value) getFontSettings().shadow_offset_y = value; refreshFn() end,
                disableif = hasOutline,
            },
        }

        if hasPosition then
            widgets[#widgets + 1] = {
                type = "select",
                name = L["SETTING_FONT_ANCHOR"],
                desc = L["SETTING_FONT_ANCHOR_DESC"],
                values = function()
                    local t = {}
                    for _, opt in ipairs(FONT_ANCHOR_OPTIONS) do
                        t[#t + 1] = {label = opt.label, value = opt.value, onclick = function(_, _, value)
                            getFontSettings().anchor_point = value
                            refreshFn()
                        end}
                    end
                    return t
                end,
                get = function() return getFontSettings().anchor_point or "CENTER" end,
                set = function(_, _, value) getFontSettings().anchor_point = value; refreshFn() end,
            }

            widgets[#widgets + 1] = {
                type = "range",
                name = L["SETTING_FONT_OFFSET_X"],
                desc = L["SETTING_FONT_OFFSET_X_DESC"],
                min = -50, max = 50, step = 1,
                get = function() return getFontSettings().offset_x or 0 end,
                set = function(_, _, value) getFontSettings().offset_x = value; refreshFn() end,
            }

            widgets[#widgets + 1] = {
                type = "range",
                name = L["SETTING_FONT_OFFSET_Y"],
                desc = L["SETTING_FONT_OFFSET_Y_DESC"],
                min = -50, max = 50, step = 1,
                get = function() return getFontSettings().offset_y or 0 end,
                set = function(_, _, value) getFontSettings().offset_y = value; refreshFn() end,
            }
        end

        return widgets
    end

    local function clearAllColumns()
        for _, col in ipairs({col1Frame, col2Frame, col3Frame}) do
            if col.widget_list then framework:ClearOptionsPanel(col) end
        end
    end

    ---Build all settings widgets for the currently selected additional frame.
    local function buildLayoutSettings()
        if not selectedFrameId then
            clearAllColumns()
            return
        end
        local settings = private.profile.additional_frames[selectedFrameId]
        if not settings then
            clearAllColumns()
            return
        end

        -- Same engine gate as the built-in trackers: under Blizzard's compacting
        -- groups engine the button-to-aura binding is secret, so every per-spell
        -- widget below is inert and is hidden rather than shown doing nothing.
        -- IsUsingSlots lives on the frame's aura tracker (AdditionalFrameManager
        -- getAuraTracker), not on the plain instance.component wrapper, which
        -- has no such method -- read there, the gate was always false.
        local afInstance = private.AdditionalFrameManager.GetInstance(selectedFrameId)
        local afComponent = afInstance and (afInstance.auraTracker or afInstance.component)
        local groupsEngine = afComponent ~= nil and afComponent.IsUsingSlots ~= nil
            and not afComponent.IsUsingSlots()
        ---Append the active/pandemic glow suite (and proc glow, if available)
        ---to the given widgets list. Shared between icon and bar frame types.
        local function addGlowSuite(widgets)
            if settings.pandemic_glow == nil then return end
            if #widgets > 0 then widgets[#widgets + 1] = {type = "blank"} end
            widgets[#widgets + 1] = {
                type = "toggle",
                name = L["SETTING_ACTIVE_GLOW"],
                desc = L["SETTING_ACTIVE_GLOW_DESC"],
                get = function() return settings.active_glow end,
                -- fontsDirty gate: an aura frame applies the glow through its
                -- per-button restyle pass (patterns.md "fontsDirty").  Not
                -- hidden under groups — the region is bound into the aura
                -- button, so it needs no button-to-spell binding.
                set = function(_, _, value)
                    settings.active_glow = value
                    private.CDMDataSource.EnsureEnabled()
                    private.fontsDirty = true
                    refreshSelectedFrame()
                    private.fontsDirty = false
                end,
            }
            widgets[#widgets + 1] = {
                type = "color",
                name = L["SETTING_ACTIVE_GLOW_COLOR"],
                desc = L["SETTING_ACTIVE_GLOW_COLOR_DESC"],
                get = function()
                    local c = settings.active_glow_color
                    return {private.Util.Color(c)}
                end,
                set = function(_, r, g, b, a)
                    settings.active_glow_color = {r, g, b, a}
                    private.fontsDirty = true
                    refreshSelectedFrame()
                    private.fontsDirty = false
                end,
                disableif = function() return not settings.active_glow end,
            }
            widgets[#widgets + 1] = {
                type = "toggle",
                name = L["SETTING_PANDEMIC_GLOW"],
                desc = L["SETTING_PANDEMIC_GLOW_DESC"],
                get = function() return settings.pandemic_glow end,
                set = function(_, _, value) settings.pandemic_glow = value; refreshSelectedFrame() end,
            }
            widgets[#widgets + 1] = {
                type = "select",
                name = L["SETTING_PANDEMIC_GLOW_STYLE"],
                desc = L["SETTING_PANDEMIC_GLOW_STYLE_DESC"],
                -- Only the two border variants, exactly as on the built-in
                -- trackers: every frame type now draws the cue on a native
                -- pandemic region inside an aura button's subtree, where no
                -- animated style can run (see Core/AuraContainer.lua).
                values = function()
                    return {
                        {label = L["PANDEMIC_STYLE_BORDER"], value = "border", onclick = function()
                            settings.pandemic_glow_style = "border"
                            refreshSelectedFrame()
                        end},
                        {label = L["PANDEMIC_STYLE_BORDER_INSIDE"], value = "border_inside", onclick = function()
                            settings.pandemic_glow_style = "border_inside"
                            refreshSelectedFrame()
                        end},
                    }
                end,
                -- A profile carrying one of the retired animated styles reads
                -- back as the outside border, which is what it now renders as.
                get = function()
                    local st = settings.pandemic_glow_style
                    return st == "border_inside" and "border_inside" or "border"
                end,
                set = function(_, _, value) settings.pandemic_glow_style = value; refreshSelectedFrame() end,
                disableif = function() return not settings.pandemic_glow end,
            }
            widgets[#widgets + 1] = {
                type = "color",
                name = L["SETTING_PANDEMIC_GLOW_COLOR"],
                desc = L["SETTING_PANDEMIC_GLOW_COLOR_DESC"],
                get = function()
                    local c = settings.pandemic_glow_color
                    return {private.Util.Color(c)}
                end,
                set = function(_, r, g, b, a)
                    settings.pandemic_glow_color = {r, g, b, a}
                    refreshSelectedFrame()
                end,
                disableif = function() return not settings.pandemic_glow end,
            }
            -- The urgency colours and the two threshold sliders are gone for the
            -- same reason they are absent from the built-in trackers: the window
            -- is Blizzard's and the region is binary, so there is no continuous
            -- remaining-% for a fade or a three-band ramp to read.  So is the
            -- LibCustomGlow alpha — no animated style survives in this subtree.
            widgets[#widgets + 1] = {
                type = "range",
                name = L["SETTING_PANDEMIC_GLOW_THICKNESS"],
                desc = L["SETTING_PANDEMIC_GLOW_THICKNESS_DESC"],
                min = 1, max = 6, step = 1,
                get = function() return settings.pandemic_glow_thickness or 2 end,
                set = function(_, _, value) settings.pandemic_glow_thickness = value; refreshSelectedFrame() end,
                disableif = function() return not settings.pandemic_glow end,
            }
            -- Ready flash colour: only spells frames seed the key, as the
            -- cooldown trackers do.
            if settings.cdm_glow_color ~= nil then
                widgets[#widgets + 1] = {
                    type = "color",
                    name = L["SETTING_CDM_GLOW_COLOR"],
                    desc = L["SETTING_CDM_GLOW_COLOR_DESC"],
                    get = function()
                        local c = settings.cdm_glow_color
                        return {private.Util.Color(c)}
                    end,
                    -- No push needed: PlayReadyFlash re-tints from the live
                    -- setting on every flash, so the next one picks this up.
                    set = function(_, r, g, b, a)
                        settings.cdm_glow_color = {r, g, b, a}
                    end,
                }
            end
            -- Proc glow (every frame type that seeds proc_glow_style — icons and bars)
            if settings.proc_glow_style ~= nil and not groupsEngine then
                widgets[#widgets + 1] = {type = "blank"}
                widgets[#widgets + 1] = {type = "label", get = function() return L["PROC_GLOW_HEADER"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
                widgets[#widgets + 1] = {
                    type = "select",
                    name = L["PROC_GLOW_STYLE"],
                    desc = L["PROC_GLOW_STYLE_DESC"],
                    values = function()
                        return {
                            {label = L["PROC_STYLE_BLIZZARD"], value = "blizzard", onclick = function()
                                settings.proc_glow_style = "blizzard"
                                refreshSelectedFrame()
                            end},
                            {label = L["PROC_STYLE_BORDER"], value = "border", onclick = function()
                                settings.proc_glow_style = "border"
                                refreshSelectedFrame()
                            end},
                            {label = L["PROC_STYLE_BORDER_INSIDE"], value = "border_inside", onclick = function()
                                settings.proc_glow_style = "border_inside"
                                refreshSelectedFrame()
                            end},
                            {label = L["PROC_STYLE_ANTS"], value = "ants", onclick = function()
                                settings.proc_glow_style = "ants"
                                refreshSelectedFrame()
                            end},
                            {label = L["PROC_STYLE_AUTOCAST"], value = "autocast", onclick = function()
                                settings.proc_glow_style = "autocast"
                                refreshSelectedFrame()
                            end},
                            {label = L["PROC_STYLE_PIXEL"], value = "pixel", onclick = function()
                                settings.proc_glow_style = "pixel"
                                refreshSelectedFrame()
                            end},
                            {label = L["PROC_STYLE_NONE"], value = "none", onclick = function()
                                settings.proc_glow_style = "none"
                                refreshSelectedFrame()
                            end},
                        }
                    end,
                    get = function() return settings.proc_glow_style or "blizzard" end,
                    set = function(_, _, value) settings.proc_glow_style = value; refreshSelectedFrame() end,
                }
                widgets[#widgets + 1] = {
                    type = "color",
                    name = L["PROC_GLOW_COLOR"],
                    desc = L["PROC_GLOW_COLOR_DESC"],
                    get = function()
                        local c = settings.proc_glow_color
                        return {private.Util.Color(c)}
                    end,
                    set = function(_, r, g, b, a)
                        settings.proc_glow_color = {r, g, b, a}
                        refreshSelectedFrame()
                    end,
                    disableif = function() return settings.proc_glow_style == "none" end,
                }
                widgets[#widgets + 1] = {
                    type = "range",
                    name = L["PROC_GLOW_ALPHA"],
                    desc = L["PROC_GLOW_ALPHA_DESC"],
                    min = 0, max = 100, step = 5,
                    get = function() return settings.proc_glow_alpha or 100 end,
                    set = function(_, _, value) settings.proc_glow_alpha = value; refreshSelectedFrame() end,
                    disableif = function() return settings.proc_glow_style == "none" end,
                }
                widgets[#widgets + 1] = {
                    type = "range",
                    name = L["PROC_GLOW_THICKNESS"],
                    desc = L["PROC_GLOW_THICKNESS_DESC"],
                    min = 1, max = 6, step = 1,
                    get = function() return settings.proc_glow_thickness or 2 end,
                    set = function(_, _, value) settings.proc_glow_thickness = value; refreshSelectedFrame() end,
                    disableif = function()
                        local style = settings.proc_glow_style
                        return not (style == "border" or style == "border_inside"
                                 or style == "pixel"  or style == "autocast")
                    end,
                }
            end
        end

        -- =================================================================
        -- Column 3: Layout (direction, alignment, growth/overflow)
        -- =================================================================
        local layoutWidgets = {}

        layoutWidgets[#layoutWidgets + 1] = {
            type = "select",
            name = L["SETTING_LAYOUT_DIRECTION"],
            desc = L["SETTING_LAYOUT_DIRECTION_DESC"],
            get = function() return settings.layout_direction or (settings.frame_type == "bar" and "vertical" or "horizontal") end,
            set = function(_, _, value)
                settings.layout_direction = value
                settings.layout_alignment = "center"
                refreshSelectedFrame()
                buildLayoutSettings()
            end,
            values = function()
                local onclick = function(_, _, value)
                    settings.layout_direction = value
                    settings.layout_alignment = "center"
                    refreshSelectedFrame()
                    buildLayoutSettings()
                end
                return {
                    {label = L["LAYOUT_DIRECTION_HORIZONTAL"], value = "horizontal", onclick = onclick},
                    {label = L["LAYOUT_DIRECTION_VERTICAL"], value = "vertical", onclick = onclick},
                }
            end,
        }
        layoutWidgets[#layoutWidgets + 1] = {
            type = "select",
            name = L["SETTING_LAYOUT_ALIGNMENT"],
            desc = L["SETTING_LAYOUT_ALIGNMENT_DESC"],
            get = function() return settings.layout_alignment or "center" end,
            set = function(_, _, value) settings.layout_alignment = value; refreshSelectedFrame() end,
            values = function()
                local onclick = function(_, _, value) settings.layout_alignment = value; refreshSelectedFrame() end
                local dir = settings.layout_direction or (settings.frame_type == "bar" and "vertical" or "horizontal")
                if dir == "vertical" then
                    return {
                        {label = L["LAYOUT_ALIGNMENT_TOP"], value = "top", onclick = onclick},
                        {label = L["LAYOUT_ALIGNMENT_CENTER"], value = "center", onclick = onclick},
                        {label = L["LAYOUT_ALIGNMENT_BOTTOM"], value = "bottom", onclick = onclick},
                    }
                end
                return {
                    {label = L["LAYOUT_ALIGNMENT_LEFT"], value = "left", onclick = onclick},
                    {label = L["LAYOUT_ALIGNMENT_CENTER"], value = "center", onclick = onclick},
                    {label = L["LAYOUT_ALIGNMENT_RIGHT"], value = "right", onclick = onclick},
                }
            end,
        }

        if settings.frame_type == "bar" then
            layoutWidgets[#layoutWidgets + 1] = {
                type = "select",
                name = L["SETTING_GROWTH_DIRECTION"],
                desc = L["SETTING_GROWTH_DIRECTION_DESC"],
                get = function() return settings.growth_direction or "up" end,
                set = function(_, _, value) settings.growth_direction = value; refreshSelectedFrame() end,
                values = function()
                    local onclick = function(_, _, value) settings.growth_direction = value; refreshSelectedFrame() end
                    if (settings.layout_direction or "vertical") == "vertical" then
                        return {
                            {label = L["SETTING_GROWTH_UP"], value = "up", onclick = onclick},
                            {label = L["SETTING_GROWTH_DOWN"], value = "down", onclick = onclick},
                        }
                    end
                    return {
                        {label = L["SETTING_GROWTH_LEFT"], value = "left", onclick = onclick},
                        {label = L["SETTING_GROWTH_RIGHT"], value = "right", onclick = onclick},
                    }
                end,
            }
            layoutWidgets[#layoutWidgets + 1] = {
                type = "select",
                name = L["SETTING_BAR_SIZE_MODE"],
                desc = L["SETTING_BAR_SIZE_MODE_DESC"],
                get = function() return settings.bar_size_mode or "fixed" end,
                set = function(_, _, value)
                    settings.bar_size_mode = value
                    refreshSelectedFrame()
                    buildLayoutSettings()
                end,
                values = function()
                    local onclick = function(_, _, value)
                        settings.bar_size_mode = value
                        refreshSelectedFrame()
                        buildLayoutSettings()
                    end
                    return {
                        {label = L["SETTING_BAR_SIZE_FIXED"], value = "fixed", onclick = onclick},
                        {label = L["SETTING_BAR_SIZE_FILL"], value = "fill", onclick = onclick},
                    }
                end,
            }
        else
            layoutWidgets[#layoutWidgets + 1] = {
                type = "select",
                name = L["SETTING_SIZE_MODE"],
                desc = L["SETTING_SIZE_MODE_DESC"],
                get = function() return settings.frame_size_mode or "max_width" end,
                set = function(_, _, value)
                    settings.frame_size_mode = value
                    refreshSelectedFrame()
                    buildLayoutSettings()
                end,
                values = function()
                    local onclick = function(_, _, value)
                        settings.frame_size_mode = value
                        refreshSelectedFrame()
                        buildLayoutSettings()
                    end
                    local isVertical = (settings.layout_direction or "horizontal") == "vertical"
                    return {
                        {label = L["SETTING_MAX_WIDTH"], value = "max_width", onclick = onclick},
                        {label = L["SETTING_MAX_PER_ROW"], value = "max_per_row", onclick = onclick},
                        {label = isVertical and L["SETTING_FIXED_HEIGHT"] or L["SETTING_FIXED_WIDTH"], value = "fixed_width", onclick = onclick},
                        {label = isVertical and L["SETTING_FIXED_HEIGHT_SPREAD"] or L["SETTING_FIXED_WIDTH_SPREAD"], value = "fixed_width_spread", onclick = onclick},
                        {label = isVertical and L["SETTING_FIXED_HEIGHT_STRETCH"] or L["SETTING_FIXED_WIDTH_STRETCH"], value = "fixed_width_stretch", onclick = onclick},
                    }
                end,
            }

            layoutWidgets[#layoutWidgets + 1] = {
                type = "select",
                name = L["SETTING_OVERFLOW_DIRECTION"],
                desc = L["SETTING_OVERFLOW_DIRECTION_DESC"],
                get = function() return settings.overflow_direction or "top" end,
                set = function(_, _, value) settings.overflow_direction = value; refreshSelectedFrame() end,
                values = function()
                    local onclick = function(_, _, value) settings.overflow_direction = value; refreshSelectedFrame() end
                    if (settings.layout_direction or "horizontal") == "vertical" then
                        return {
                            {label = L["OVERFLOW_LEFT"], value = "left", onclick = onclick},
                            {label = L["OVERFLOW_RIGHT"], value = "right", onclick = onclick},
                        }
                    end
                    return {
                        {label = L["ANCHOR_TOP"], value = "top", onclick = onclick},
                        {label = L["ANCHOR_BOTTOM"], value = "bottom", onclick = onclick},
                    }
                end,
                disableif = function()
                    local m = settings.frame_size_mode or "max_width"
                    return m == "fixed_width" or m == "fixed_width_spread" or m == "fixed_width_stretch"
                end,
            }
        end

        -- Background panel
        layoutWidgets[#layoutWidgets + 1] = {type = "blank"}
        appendWidgets(layoutWidgets, buildBackgroundWidgets(
            function() return ensureBackground(settings) end,
            function() refreshSelectedFrame() end
        ))

        -- =================================================================
        -- Size widgets (merged into col1 below anchoring)
        -- Features + Glow/Colors widgets (merged into col2 below layout)
        -- =================================================================
        local sizeWidgets = {}
        local featuresWidgets = {}
        local glowColorsWidgets = {}

        if settings.frame_type == "bar" then
            local fillMode = (settings.bar_size_mode or "fixed") == "fill"
            -- Width slider: visible only in fill mode
            sizeWidgets[#sizeWidgets + 1] = {
                type = "range",
                name = L["SETTING_WIDTH"],
                desc = L["SETTING_WIDTH_DESC"],
                min = 20, max = 1000, step = 1,
                get = function() return settings.width or 220 end,
                set = function(_, _, value) settings.width = value; refreshSelectedFrame() end,
                hidden = not fillMode,
            }
            -- Bar Width slider: hidden in fill mode
            sizeWidgets[#sizeWidgets + 1] = {
                type = "range",
                name = L["SETTING_BAR_WIDTH"],
                desc = L["SETTING_BAR_WIDTH_DESC"],
                min = 20, max = 1000, step = 1,
                get = function() return settings.bar_width or 220 end,
                -- fontsDirty gate: bar name truncation width lives in the font pass,
                -- which the layout only runs when fontsDirty is set.
                set = function(_, _, value)
                    settings.bar_width = value
                    private.fontsDirty = true
                    refreshSelectedFrame()
                    private.fontsDirty = false
                end,
                hidden = fillMode,
            }
            sizeWidgets[#sizeWidgets + 1] = {
                type = "range",
                name = L["SETTING_BAR_HEIGHT"],
                desc = L["SETTING_BAR_HEIGHT_DESC"],
                min = 5, max = 60, step = 1,
                get = function() return settings.bar_height or 30 end,
                set = function(_, _, value) settings.bar_height = value; refreshSelectedFrame() end,
            }
            sizeWidgets[#sizeWidgets + 1] = {
                type = "range",
                name = L["SETTING_ICON_SIZE"],
                desc = L["SETTING_ICON_SIZE_DESC"],
                min = 8, max = 60, step = 1,
                get = function() return settings.icon_size or 30 end,
                -- fontsDirty gate: bar name truncation width depends on icon size
                -- and is applied in the font pass, which needs fontsDirty set.
                set = function(_, _, value)
                    settings.icon_size = value
                    private.fontsDirty = true
                    refreshSelectedFrame()
                    private.fontsDirty = false
                end,
            }
            sizeWidgets[#sizeWidgets + 1] = {
                type = "range",
                name = L["SETTING_BAR_SPACING"],
                desc = L["SETTING_BAR_SPACING_DESC"],
                min = -5, max = 20, step = 1,
                get = function() return settings.bar_spacing or 2 end,
                set = function(_, _, value) settings.bar_spacing = value; refreshSelectedFrame() end,
            }
            sizeWidgets[#sizeWidgets + 1] = {
                type = "range",
                name = L["SETTING_ICON_OFFSET"],
                desc = L["SETTING_BAR_ICON_OFFSET_DESC"],
                min = -5, max = 20, step = 1,
                get = function() return settings.icon_offset or 2 end,
                -- fontsDirty gate: bar name truncation width depends on icon offset
                -- and is applied in the font pass, which needs fontsDirty set.
                set = function(_, _, value)
                    settings.icon_offset = value
                    private.fontsDirty = true
                    refreshSelectedFrame()
                    private.fontsDirty = false
                end,
            }
            sizeWidgets[#sizeWidgets + 1] = {
                type = "range",
                name = L["SETTING_BAR_ICON_OFFSET_X"],
                desc = L["SETTING_BAR_ICON_OFFSET_X_DESC"],
                min = -50, max = 50, step = 1,
                get = function() return settings.icon_offset_x or 0 end,
                set = function(_, _, value) settings.icon_offset_x = value; refreshSelectedFrame() end,
            }
            sizeWidgets[#sizeWidgets + 1] = {
                type = "range",
                name = L["SETTING_BAR_ICON_OFFSET_Y"],
                desc = L["SETTING_BAR_ICON_OFFSET_Y_DESC"],
                min = -50, max = 50, step = 1,
                get = function() return settings.icon_offset_y or 0 end,
                set = function(_, _, value) settings.icon_offset_y = value; refreshSelectedFrame() end,
            }
            sizeWidgets[#sizeWidgets + 1] = {
                type = "select",
                name = L["SETTING_BAR_CONTENT"],
                desc = L["SETTING_BAR_CONTENT_DESC"],
                get = function() return settings.bar_content or "IconAndName" end,
                -- fontsDirty gate: bar name truncation width (and whether the name
                -- shows at all) is applied in the font pass, which needs fontsDirty set.
                set = function(_, _, value)
                    settings.bar_content = value
                    private.fontsDirty = true
                    refreshSelectedFrame()
                    private.fontsDirty = false
                end,
                values = function()
                    local onclick = function(_, _, value)
                        settings.bar_content = value
                        private.fontsDirty = true
                        refreshSelectedFrame()
                        private.fontsDirty = false
                    end
                    return {
                        {label = L["SETTING_BAR_CONTENT_ICON_AND_BAR"], value = "IconAndName", onclick = onclick},
                        {label = L["SETTING_BAR_CONTENT_ICON_ONLY"], value = "IconOnly", onclick = onclick},
                        {label = L["SETTING_BAR_CONTENT_BAR_ONLY"], value = "NameOnly", onclick = onclick},
                        {label = L["SETTING_BAR_CONTENT_BAR_ONLY_NO_NAME"], value = "BarOnlyNoName", onclick = onclick},
                        {label = L["SETTING_BAR_CONTENT_ICON_AND_BAR_NO_NAME"], value = "IconAndBarNoName", onclick = onclick},
                    }
                end,
            }
            sizeWidgets[#sizeWidgets + 1] = {
                type = "toggle",
                name = L["SETTING_BAR_COLLAPSE"],
                desc = L["SETTING_BAR_COLLAPSE_DESC"],
                get = function() return settings.collapse end,
                set = function(_, _, value) settings.collapse = value; refreshSelectedFrame() end,
            }
            sizeWidgets[#sizeWidgets + 1] = {
                type = "toggle",
                name = L["SETTING_SHOW_TIMER"],
                desc = L["SETTING_SHOW_TIMER_DESC"],
                get = function() return settings.show_timer end,
                set = function(_, _, value) settings.show_timer = value; refreshSelectedFrame() end,
            }
            if settings.bar_fill_color ~= nil then
                glowColorsWidgets[#glowColorsWidgets + 1] = {
                    type = "color",
                    name = L["SETTING_BAR_FILL_COLOR"],
                    desc = L["SETTING_BAR_FILL_COLOR_DESC"],
                    get = function()
                        local c = settings.bar_fill_color
                        return {private.Util.Color(c)}
                    end,
                    set = function(_, r, g, b, a)
                        settings.bar_fill_color = {r, g, b, a}
                        refreshSelectedFrame()
                    end,
                }
            end
            addGlowSuite(glowColorsWidgets)

            -- Drop corrupted spell_colors entries (pre-fix saved data), which
            -- AuraBarTracker's applyBarFill would index.  Kept from the retired
            -- per-spell colour list, which ran it whenever this panel opened.
            if type(settings.spell_colors) == "table" then
                for sid, entry in pairs(settings.spell_colors) do
                    if type(entry) ~= "table" or type(entry[1]) ~= "number" then
                        settings.spell_colors[sid] = nil
                    end
                end
            end

        else
            sizeWidgets[#sizeWidgets + 1] = {
                type = "range",
                name = L["SETTING_WIDTH"],
                desc = L["SETTING_WIDTH_DESC"],
                min = 20, max = 1000, step = 1,
                get = function() return settings.width or 300 end,
                set = function(_, _, value) settings.width = value; refreshSelectedFrame() end,
            }
            sizeWidgets[#sizeWidgets + 1] = {
                type = "range",
                name = L["SETTING_HEIGHT"],
                desc = L["SETTING_HEIGHT_DESC"],
                min = 10, max = 400, step = 1,
                get = function() return settings.height or 100 end,
                set = function(_, _, value) settings.height = value; refreshSelectedFrame() end,
            }
            sizeWidgets[#sizeWidgets + 1] = {
                type = "range",
                name = L["SETTING_MAX_PER_ROW"],
                desc = L["SETTING_MAX_PER_ROW_DESC"],
                min = 1, max = 20, step = 1,
                get = function() return settings.max_icons_per_row or 8 end,
                set = function(_, _, value) settings.max_icons_per_row = value; refreshSelectedFrame() end,
                disableif = function()
                    return (settings.frame_size_mode or "max_width") ~= "max_per_row"
                end,
            }
            sizeWidgets[#sizeWidgets + 1] = {
                type = "range",
                name = L["SETTING_MIN_WIDTH"],
                desc = L["SETTING_MIN_WIDTH_DESC"],
                min = 0, max = 1000, step = 1,
                get = function() return settings.min_width or 0 end,
                set = function(_, _, value) settings.min_width = value; refreshSelectedFrame() end,
                disableif = function()
                    if (settings.layout_direction or "horizontal") == "vertical" then return false end
                    return (settings.frame_size_mode or "max_width") ~= "max_per_row"
                end,
            }
            sizeWidgets[#sizeWidgets + 1] = {
                type = "range",
                name = L["SETTING_ICON_SIZE"],
                desc = L["SETTING_ICON_SIZE_DESC"],
                min = 8, max = 80, step = 1,
                get = function() return settings.icon_size or 40 end,
                set = function(_, _, value) settings.icon_size = value; refreshSelectedFrame() end,
                disableif = function()
                    return settings.frame_size_mode == "fixed_width"
                end,
            }
            sizeWidgets[#sizeWidgets + 1] = {
                type = "range",
                name = L["SETTING_ICON_HEIGHT"],
                desc = L["SETTING_ICON_HEIGHT_DESC"],
                min = 0, max = 80, step = 1,
                get = function() return settings.icon_height or 0 end,
                set = function(_, _, value)
                    if value > 0 and value < 8 then value = 8 end
                    settings.icon_height = value
                    refreshSelectedFrame()
                end,
                disableif = function()
                    return settings.frame_size_mode == "fixed_width_stretch"
                end,
            }
            sizeWidgets[#sizeWidgets + 1] = {
                type = "range",
                name = L["SETTING_OVERFLOW_ICON_SIZE"],
                desc = L["SETTING_OVERFLOW_ICON_SIZE_DESC"],
                min = 8, max = 80, step = 1,
                -- Which icons landed on an overflow row is only knowable under slots.
                hidden = groupsEngine,
                get = function() return settings.overflow_icon_size or 20 end,
                set = function(_, _, value) settings.overflow_icon_size = value; refreshSelectedFrame() end,
                disableif = function()
                    local m = settings.frame_size_mode or "max_width"
                    return m == "fixed_width" or m == "fixed_width_spread" or m == "fixed_width_stretch"
                end,
            }
            sizeWidgets[#sizeWidgets + 1] = {
                type = "range",
                name = L["SETTING_ICON_OFFSET"],
                desc = L["SETTING_ICON_OFFSET_DESC"],
                min = -5, max = 20, step = 1,
                get = function() return settings.icon_offset or 1 end,
                set = function(_, _, value) settings.icon_offset = value; refreshSelectedFrame() end,
            }

            -- Swipe suppression (icon-type frames only).
            --
            -- This branch also serves `buffs` frames, which render through
            -- AuraIconTracker — and that tracker reads exactly three of the keys
            -- below: hide_icon, hide_cd_swipe, hide_cd_text.  Everything else is
            -- cooldown state carried on an IconTracker button, which an aura
            -- button does not have, so the widgets are hidden rather than left
            -- writing keys nothing reads.
            local spellsFrame = settings.frame_type == "spells"
            featuresWidgets[#featuresWidgets + 1] = {type = "label", get = function() return L["SECTION_FEATURES"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
            if settings.hide_icon ~= nil then
                featuresWidgets[#featuresWidgets + 1] = {
                    type = "toggle",
                    name = L["SETTING_HIDE_ICON"],
                    desc = L["SETTING_HIDE_ICON_DESC"],
                    get = function() return settings.hide_icon end,
                    -- fontsDirty gate: on a buffs frame this lands in the
                    -- AuraContainer restyle pass, which the refresh only runs
                    -- when the flag is set (patterns.md "fontsDirty").
                    set = function(_, _, value)
                        settings.hide_icon = value
                        private.fontsDirty = true
                        refreshSelectedFrame()
                        private.fontsDirty = false
                    end,
                }
            end
            featuresWidgets[#featuresWidgets + 1] = {
                type = "toggle",
                name = L["SETTING_HIDE_CD_SWIPE"],
                desc = L["SETTING_HIDE_CD_SWIPE_DESC"],
                get = function() return settings.hide_cd_swipe end,
                -- fontsDirty gate: see hide_icon above.
                set = function(_, _, value)
                    settings.hide_cd_swipe = value
                    private.fontsDirty = true
                    refreshSelectedFrame()
                    private.fontsDirty = false
                end,
            }
            featuresWidgets[#featuresWidgets + 1] = {
                type = "toggle",
                name = L["SETTING_HIDE_ACTIVE_SWIPE"],
                desc = L["SETTING_HIDE_ACTIVE_SWIPE_DESC"],
                get = function() return settings.hide_active_swipe end,
                set = function(_, _, value) settings.hide_active_swipe = value; private.CDMDataSource.EnsureEnabled(); refreshSelectedFrame() end,
                hidden = not spellsFrame,
            }
            if settings.suppress_buff_icon_swap ~= nil then
                featuresWidgets[#featuresWidgets + 1] = {
                    type = "toggle",
                    name = L["SETTING_SUPPRESS_BUFF_ICON_SWAP"],
                    desc = L["SETTING_SUPPRESS_BUFF_ICON_SWAP_DESC"],
                    get = function() return settings.suppress_buff_icon_swap end,
                    set = function(_, _, value)
                        settings.suppress_buff_icon_swap = value
                        refreshSelectedFrame()
                    end,
                }
            end
            featuresWidgets[#featuresWidgets + 1] = {
                type = "toggle",
                name = L["SETTING_HIDE_GCD_SWIPE"],
                desc = L["SETTING_HIDE_GCD_SWIPE_DESC"],
                get = function() return settings.hide_gcd_swipe end,
                set = function(_, _, value) settings.hide_gcd_swipe = value; refreshSelectedFrame() end,
                hidden = not spellsFrame,
            }
            featuresWidgets[#featuresWidgets + 1] = {
                type = "toggle",
                name = L["SETTING_GCD_EDGE_CHARGES"],
                desc = L["SETTING_GCD_EDGE_CHARGES_DESC"],
                get = function() return settings.gcd_edge_charges end,
                set = function(_, _, value) settings.gcd_edge_charges = value; refreshSelectedFrame() end,
                disableif = function() return settings.hide_gcd_swipe end,
                hidden = not spellsFrame,
            }
            featuresWidgets[#featuresWidgets + 1] = {
                type = "toggle",
                name = L["SETTING_REVERSE_SWIPE"],
                desc = L["SETTING_REVERSE_SWIPE_DESC"],
                get = function() return settings.reverse_swipe end,
                -- Kept for `buffs` too: restyleButton flips the aura button's
                -- Cooldown away from Blizzard's reversed buff direction.
                -- fontsDirty gate: see hide_icon above.
                set = function(_, _, value)
                    settings.reverse_swipe = value
                    private.fontsDirty = true
                    refreshSelectedFrame()
                    private.fontsDirty = false
                end,
            }
            featuresWidgets[#featuresWidgets + 1] = {
                type = "toggle",
                name = L["SETTING_NO_CD_OVERLAY"],
                desc = L["SETTING_NO_CD_OVERLAY_DESC"],
                get = function() return settings.no_cd_overlay end,
                set = function(_, _, value) settings.no_cd_overlay = value; refreshSelectedFrame() end,
                disableif = function() return not settings.hide_active_swipe end,
                hidden = not spellsFrame,
            }
            featuresWidgets[#featuresWidgets + 1] = {
                type = "toggle",
                name = L["SETTING_NO_CD_OVERLAY_EDGE_ONLY"],
                desc = L["SETTING_NO_CD_OVERLAY_EDGE_ONLY_DESC"],
                get = function() return settings.no_cd_overlay_edge_only end,
                set = function(_, _, value) settings.no_cd_overlay_edge_only = value; refreshSelectedFrame() end,
                disableif = function() return not settings.hide_active_swipe or not settings.no_cd_overlay end,
                hidden = not spellsFrame,
            }
            featuresWidgets[#featuresWidgets + 1] = {
                type = "toggle",
                name = L["SETTING_NO_DESATURATION"],
                desc = L["SETTING_NO_DESATURATION_DESC"],
                get = function() return settings.no_desaturation end,
                set = function(_, _, value) settings.no_desaturation = value; refreshSelectedFrame() end,
                hidden = not spellsFrame,
            }
            featuresWidgets[#featuresWidgets + 1] = {
                type = "toggle",
                name = L["SETTING_FORCE_DESATURATION"],
                desc = L["SETTING_FORCE_DESATURATION_DESC"],
                get = function() return settings.force_desaturation end,
                set = function(_, _, value) settings.force_desaturation = value; refreshSelectedFrame() end,
                disableif = function() return settings.no_desaturation end,
                hidden = not spellsFrame,
            }
            featuresWidgets[#featuresWidgets + 1] = {
                type = "toggle",
                name = L["SETTING_NO_RANGE_TINT"],
                desc = L["SETTING_NO_RANGE_TINT_DESC"],
                get = function() return settings.no_range_tint end,
                set = function(_, _, value) settings.no_range_tint = value; refreshSelectedFrame() end,
                hidden = not spellsFrame,
            }
            if settings.frame_type == "spells" then
                featuresWidgets[#featuresWidgets + 1] = {
                    type = "select",
                    name = L["SETTING_ICON_VISIBILITY_MODE"],
                    desc = L["SETTING_ICON_VISIBILITY_MODE_DESC"],
                    get = function() return settings.icon_visibility_mode or 1 end,
                    set = function(_, _, value)
                        settings.icon_visibility_mode = value
                        private.CDMDataSource.EnsureEnabled()
                        refreshSelectedFrame()
                    end,
                    values = function()
                        local onclick = function(_, _, value)
                            settings.icon_visibility_mode = value
                            private.CDMDataSource.EnsureEnabled()
                            refreshSelectedFrame()
                        end
                        return {
                            {label = L["SETTING_ICON_VISIBILITY_DISABLED"], value = 1, onclick = onclick},
                            {label = L["SETTING_ICON_VISIBILITY_HIDE_READY"], value = 2, onclick = onclick},
                            {label = L["SETTING_ICON_VISIBILITY_FADE_READY"], value = 3, onclick = onclick},
                            {label = L["SETTING_ICON_VISIBILITY_HIDE_ONCD"], value = 4, onclick = onclick},
                            {label = L["SETTING_ICON_VISIBILITY_FADE_ONCD"], value = 5, onclick = onclick},
                        }
                    end,
                }
                featuresWidgets[#featuresWidgets + 1] = {
                    type = "range",
                    name = L["SETTING_ICON_VISIBILITY_FADED_ALPHA"],
                    desc = L["SETTING_ICON_VISIBILITY_FADED_ALPHA_DESC"],
                    min = 0, max = 1, step = 0.05,
                    usedecimals = true,
                    get = function() return settings.icon_visibility_faded_alpha or 0.3 end,
                    set = function(_, _, value)
                        settings.icon_visibility_faded_alpha = value
                        refreshSelectedFrame()
                    end,
                }
                featuresWidgets[#featuresWidgets + 1] = {
                    type = "toggle",
                    name = L["SETTING_ICON_VISIBILITY_TREAT_CHARGING_AS_ON_CD"],
                    desc = L["SETTING_ICON_VISIBILITY_TREAT_CHARGING_AS_ON_CD_DESC"],
                    get = function()
                        local v = settings.icon_visibility_treat_charging_as_on_cd
                        if v == nil then return true end
                        return v
                    end,
                    set = function(_, _, value)
                        settings.icon_visibility_treat_charging_as_on_cd = value
                        refreshSelectedFrame()
                    end,
                    disableif = function() return (settings.icon_visibility_mode or 1) <= 1 end,
                }
                featuresWidgets[#featuresWidgets + 1] = {
                    type = "toggle",
                    name = L["SETTING_HIDE_READY_BLINK"],
                    desc = L["SETTING_HIDE_READY_BLINK_DESC"],
                    get = function() return settings.hide_ready_blink end,
                    set = function(_, _, value) settings.hide_ready_blink = value; refreshSelectedFrame() end,
                }
            end
            featuresWidgets[#featuresWidgets + 1] = {
                type = "toggle",
                name = L["SETTING_HIDE_CD_TEXT"],
                desc = L["SETTING_HIDE_CD_TEXT_DESC"],
                get = function() return settings.hide_cd_text end,
                -- fontsDirty gate: see hide_icon above.
                set = function(_, _, value)
                    settings.hide_cd_text = value
                    private.fontsDirty = true
                    refreshSelectedFrame()
                    private.fontsDirty = false
                end,
            }
            if settings.hide_charge_cd_text ~= nil then
                featuresWidgets[#featuresWidgets + 1] = {
                    type = "toggle",
                    name = L["SETTING_HIDE_CHARGE_CD_TEXT"],
                    desc = L["SETTING_HIDE_CHARGE_CD_TEXT_DESC"],
                    get = function() return settings.hide_charge_cd_text end,
                    set = function(_, _, value) settings.hide_charge_cd_text = value; refreshSelectedFrame() end,
                    disableif = function() return settings.hide_cd_text end,
                }
            end
            if settings.hide_zero_charges ~= nil then
                featuresWidgets[#featuresWidgets + 1] = {
                    type = "toggle",
                    name = L["SETTING_HIDE_ZERO_CHARGES"],
                    desc = L["SETTING_HIDE_ZERO_CHARGES_DESC"],
                    get = function() return settings.hide_zero_charges end,
                    set = function(_, _, value) settings.hide_zero_charges = value; refreshSelectedFrame() end,
                }
            end
            addGlowSuite(glowColorsWidgets)
        end

        -- Always-show engine switch, mirroring the built-in tracker toggle.  Off
        -- is groups, where the button-to-aura binding is secret and every
        -- per-spell feature is inert.
        if settings.frame_type == "bar" or settings.frame_type == "buffs" then
            glowColorsWidgets[#glowColorsWidgets + 1] = {type = "blank"}
            glowColorsWidgets[#glowColorsWidgets + 1] = {
                type = "toggle",
                name = L["SETTING_ALWAYS_SHOW_TRACKED"],
                desc = L["SETTING_ALWAYS_SHOW_TRACKED_DESC"],
                get = function() return settings.always_show_tracked == true end,
                set = function(_, _, value)
                    settings.always_show_tracked = value
                    refreshSelectedFrame()
                    -- The engine just changed, so the slots-only widgets appear
                    -- or vanish; deferred because this runs from a pooled switch
                    -- that the rebuild recycles.
                    C_Timer.After(0, buildLayoutSettings)
                end,
            }
            -- Slots only, like the built-in tracker toggle.
            if settings.always_show_tracked == true then
                glowColorsWidgets[#glowColorsWidgets + 1] = {
                    type = "toggle",
                    name = L["SETTING_DESATURATE_INACTIVE"],
                    desc = L["SETTING_DESATURATE_INACTIVE_DESC"],
                    get = function() return settings.desaturate_inactive == true end,
                    set = function(_, _, value)
                        settings.desaturate_inactive = value
                        refreshSelectedFrame()
                    end,
                }
            end
        end

        -- =================================================================
        -- Anchor widgets (merged into col1 below visibility)
        -- =================================================================
        local componentName = "AdditionalFrame_" .. selectedFrameId

        ---Free-moving as on every component panel: no anchor parent. A
        ---cursor-following frame is anchored -- to the cursor, by Anchor Side and
        ---the anchor offsets -- so the free-move point and offset controls do
        ---nothing for it.
        local function isFreeMoving()
            local ap = settings.anchor_profile.anchor_parent
            return not ap or ap == "none"
        end

        local anchorWidgets = {}

        ---The AF container, but only while free-moving: a cursor-following
        ---frame reads anchor_side/offset, so there is no free-move rect to keep.
        local function freeMoveFrameAF()
            if not isFreeMoving() then return nil end
            local instance = private.AdditionalFrameManager.GetInstance(selectedFrameId)
            return instance and instance.component.GetFrame()
        end

        ---Shared by the Anchor Frame `set` and `onclick` (plain select). Leaving
        ---an anchor for "none" captures the on-screen position so the frame
        ---stays put, as the component panel and Edit Mode do.
        local function applyAnchorParentAF(value)
            if private.Anchor.WouldCreateCycle(componentName, value) then
                private.print(string.format(L["ANCHOR_CIRCULAR_ERROR"], settings.name or selectedFrameId, resolveDisplayName(value)))
                return
            end
            local ap = settings.anchor_profile
            if value == "none" and ap.anchor_parent ~= "none" then
                local instance = private.AdditionalFrameManager.GetInstance(selectedFrameId)
                local f = instance and instance.component.GetFrame()
                if f and f:GetLeft() then
                    local scale = f:GetScale()
                    private.EditMode.CapturePositionForFreeMove(
                        componentName, settings, ap,
                        f:GetLeft() * scale, f:GetRight() * scale,
                        f:GetTop() * scale, f:GetBottom() * scale, scale)
                end
            end
            ap.anchor_parent = value
            private.Anchor.RebuildAnchorTree()
            refreshSelectedFrame()
            buildLayoutSettings()
        end

        ---Shared by the Anchor Point / Frame Point `set` and `onclick`; keeps the
        ---frame in place (EditMode.SetFreeMovePoint).
        local function applyFreeMovePointAF(key, value)
            private.EditMode.SetFreeMovePoint(freeMoveFrameAF(), settings.anchor_profile, key, value)
            refreshSelectedFrame()
        end

        anchorWidgets[#anchorWidgets + 1] = {
            type = "select",
            name = L["SETTING_ANCHOR_FRAME"],
            desc = L["SETTING_ANCHOR_FRAME_DESC"],
            get = function() return settings.anchor_profile.anchor_parent end,
            set = function(_, _, value) applyAnchorParentAF(value) end,
            values = function()
                local onclick = function(_, _, value) applyAnchorParentAF(value) end
                local vals = buildAnchorParentValues(componentName)
                for _, v in ipairs(vals) do
                    v.onclick = onclick
                end
                return vals
            end,
        }

        -- Declared above every widget that uses it: Lua 5.1 captures locals at
        -- definition time, so a `disableif = isOffsetDisabled` written earlier in
        -- the file would capture nil and silently never disable the widget.
        local function isOffsetDisabled()
            return settings.anchor_profile.anchor_parent == "none"
        end

        anchorWidgets[#anchorWidgets + 1] = {
            type = "select",
            name = L["SETTING_ANCHOR_POINT"],
            desc = L["SETTING_ANCHOR_POINT_DESC"],
            get = function()
                return string.upper(settings.anchor_profile.parent_point or "CENTER")
            end,
            set = function(_, _, value) applyFreeMovePointAF("parent_point", value) end,
            values = function()
                local onclick = function(_, _, value) applyFreeMovePointAF("parent_point", value) end
                local vals = {}
                for i, v in ipairs(anchorPointValues) do
                    vals[i] = {label = v.label, value = v.value, onclick = onclick}
                end
                return vals
            end,
            disableif = function() return not isFreeMoving() end,
        }

        anchorWidgets[#anchorWidgets + 1] = {
            type = "select",
            name = L["SETTING_FRAME_POINT"],
            desc = L["SETTING_FRAME_POINT_DESC"],
            get = function()
                return string.upper(settings.anchor_profile.frame_point or "TOP")
            end,
            set = function(_, _, value) applyFreeMovePointAF("frame_point", value) end,
            values = function()
                local onclick = function(_, _, value) applyFreeMovePointAF("frame_point", value) end
                local vals = {}
                for i, v in ipairs(anchorPointValues) do
                    vals[i] = {label = v.label, value = v.value, onclick = onclick}
                end
                return vals
            end,
            disableif = function() return not isFreeMoving() end,
        }

        anchorWidgets[#anchorWidgets + 1] = {
            type = "range",
            name = L["SETTING_FREE_OFFSET_X"],
            desc = L["SETTING_FREE_OFFSET_X_DESC"],
            min = -3000,
            max = 3000,
            step = 1,
            get = function() return settings.anchor_profile.xoff or 0 end,
            set = function(_, _, value)
                settings.anchor_profile.xoff = value
                refreshSelectedFrame()
            end,
            disableif = function() return not isFreeMoving() end,
        }

        anchorWidgets[#anchorWidgets + 1] = {
            type = "range",
            name = L["SETTING_FREE_OFFSET_Y"],
            desc = L["SETTING_FREE_OFFSET_Y_DESC"],
            min = -3000,
            max = 3000,
            step = 1,
            get = function() return settings.anchor_profile.yoff or 0 end,
            set = function(_, _, value)
                settings.anchor_profile.yoff = value
                refreshSelectedFrame()
            end,
            disableif = function() return not isFreeMoving() end,
        }

        anchorWidgets[#anchorWidgets + 1] = {
            type = "select",
            name = L["SETTING_ANCHOR_SIDE"],
            desc = L["SETTING_ANCHOR_SIDE_DESC"],
            get = function() return settings.anchor_profile.anchor_side end,
            set = function(_, _, value)
                settings.anchor_profile.anchor_side = value
                refreshSelectedFrame()
            end,
            values = function()
                local onclick = function(_, _, value)
                    settings.anchor_profile.anchor_side = value
                    refreshSelectedFrame()
                end
                local vals = {}
                for i, v in ipairs(anchorSideValues) do
                    vals[i] = {label = v.label, value = v.value, onclick = onclick}
                end
                return vals
            end,
            disableif = isOffsetDisabled,
        }

        anchorWidgets[#anchorWidgets + 1] = {
            type = "select",
            name = L["SETTING_WIDTH_MODE"],
            desc = L["SETTING_WIDTH_MODE_DESC"],
            get = function() return settings.anchor_profile.anchor_width_mode or "percent" end,
            set = function(_, _, value)
                settings.anchor_profile.anchor_width_mode = value
                refreshSelectedFrame()
            end,
            values = function()
                local onclick = function(_, _, value)
                    settings.anchor_profile.anchor_width_mode = value
                    refreshSelectedFrame()
                end
                return {
                    {label = L["WIDTH_MODE_PERCENT"], value = "percent", onclick = onclick},
                    {label = L["WIDTH_MODE_ABSOLUTE"], value = "absolute", onclick = onclick},
                }
            end,
            -- The cursor has no width to inherit.
            disableif = function()
                return isFreeMoving() or settings.anchor_profile.anchor_parent == "cursor"
            end,
        }

        anchorWidgets[#anchorWidgets + 1] = {
            type = "range",
            name = L["SETTING_WIDTH_PCT"],
            desc = L["SETTING_WIDTH_PCT_DESC"],
            min = 10,
            max = 200,
            step = 1,
            get = function() return settings.anchor_profile.anchor_width_pct or 100 end,
            set = function(_, _, value)
                settings.anchor_profile.anchor_width_pct = value
                refreshSelectedFrame()
            end,
            disableif = function()
                local ap = settings.anchor_profile.anchor_parent
                return ap == "none" or ap == "cursor"
                    or (settings.anchor_profile.anchor_width_mode or "percent") == "absolute"
            end,
        }
        anchorWidgets[#anchorWidgets + 1] = {
            type = "range",
            name = L["SETTING_ANCHOR_OFFSET_X"],
            desc = L["SETTING_ANCHOR_OFFSET_X_DESC"],
            min = -1000,
            max = 1000,
            step = 1,
            get = function() return settings.anchor_profile.anchor_offset_x end,
            set = function(_, _, value)
                settings.anchor_profile.anchor_offset_x = value
                refreshSelectedFrame()
            end,
            disableif = isOffsetDisabled,
        }

        anchorWidgets[#anchorWidgets + 1] = {
            type = "range",
            name = L["SETTING_ANCHOR_OFFSET_Y"],
            desc = L["SETTING_ANCHOR_OFFSET_Y_DESC"],
            min = -1000,
            max = 1000,
            step = 1,
            get = function() return settings.anchor_profile.anchor_offset_y end,
            set = function(_, _, value)
                settings.anchor_profile.anchor_offset_y = value
                refreshSelectedFrame()
            end,
            disableif = isOffsetDisabled,
        }

        -- =================================================================
        -- Visibility widgets (start of col1)
        -- =================================================================
        local visWidgets = {}

        visWidgets[#visWidgets + 1] = {
            type = "select",
            name = L["SETTING_VISIBILITY"],
            desc = L["SETTING_VISIBILITY_DESC"],
            get = function()
                local vis = settings.visibility or "inherit"
                if vis == "hide_when_mounted" then return "auto"
                elseif vis == "only_in_combat" then return "always" end
                return vis
            end,
            set = function(_, _, value)
                settings.visibility = value
                private.Anchor.InvalidateTargetRuleCache()
                refreshSelectedFrame()
            end,
            values = function()
                local onclick = function(_, _, value)
                    settings.visibility = value
                    -- The rule scan skips a "hidden" frame's rules.
                    private.Anchor.InvalidateTargetRuleCache()
                    refreshSelectedFrame()
                end
                return {
                    {label = L["VISIBILITY_INHERIT"], value = "inherit", onclick = onclick},
                    {label = L["VISIBILITY_ALWAYS"], value = "always", onclick = onclick},
                    {label = L["VISIBILITY_AUTO"], value = "auto", onclick = onclick},
                    {label = L["VISIBILITY_HIDDEN"], value = "hidden", onclick = onclick},
                }
            end,
        }

        visWidgets[#visWidgets + 1] = {
            type = "range",
            name = L["SETTING_OPACITY"],
            desc = L["SETTING_OPACITY_DESC"],
            min = 10,
            max = 100,
            step = 5,
            get = function() return math.floor((settings.alpha or 1) * 100 + 0.5) end,
            set = function(_, _, value)
                settings.alpha = value / 100
                refreshSelectedFrame()
            end,
        }

        visWidgets[#visWidgets + 1] = {
            type = "select",
            name = L["SETTING_FRAME_STRATA"],
            desc = L["SETTING_FRAME_STRATA_DESC"],
            get = function() return settings.frame_strata or "inherit" end,
            set = function(_, _, value)
                settings.frame_strata = (value == "inherit") and nil or value
                refreshSelectedFrame()
            end,
            values = function()
                local onclick = function(_, _, value)
                    settings.frame_strata = (value == "inherit") and nil or value
                    refreshSelectedFrame()
                end
                return {
                    {label = L["FRAME_STRATA_INHERIT"], value = "inherit", onclick = onclick},
                    {label = "BACKGROUND", value = "BACKGROUND", onclick = onclick},
                    {label = "LOW", value = "LOW", onclick = onclick},
                    {label = "MEDIUM", value = "MEDIUM", onclick = onclick},
                    {label = "HIGH", value = "HIGH", onclick = onclick},
                    {label = "DIALOG", value = "DIALOG", onclick = onclick},
                    {label = "FULLSCREEN", value = "FULLSCREEN", onclick = onclick},
                    {label = "FULLSCREEN_DIALOG", value = "FULLSCREEN_DIALOG", onclick = onclick},
                    {label = "TOOLTIP", value = "TOOLTIP", onclick = onclick},
                }
            end,
        }

        local ruleConditions = {
            {key = "mounted", name = L["VISIBILITY_RULE_MOUNTED"], desc = L["VISIBILITY_RULE_MOUNTED_DESC"]},
            {key = "out_of_combat", name = L["VISIBILITY_RULE_OUT_OF_COMBAT"], desc = L["VISIBILITY_RULE_OUT_OF_COMBAT_DESC"]},
            {key = "no_target", name = L["VISIBILITY_RULE_NO_TARGET"], desc = L["VISIBILITY_RULE_NO_TARGET_DESC"]},
        }
        for _, cond in ipairs(ruleConditions) do
            local ruleOnclick = function(_, _, value)
                if not settings.visibility_rules then
                    settings.visibility_rules = {fade_alpha = 30}
                end
                settings.visibility_rules[cond.key] = value == "off" and false or value
                private.Anchor.InvalidateTargetRuleCache()
                refreshSelectedFrame()
            end
            visWidgets[#visWidgets + 1] = {
                type = "select",
                name = cond.name,
                desc = cond.desc,
                get = function()
                    local rules = settings.visibility_rules
                    return (rules and rules[cond.key]) or "off"
                end,
                set = function(_, _, value) ruleOnclick(nil, nil, value) end,
                values = function()
                    return {
                        {label = L["VISIBILITY_RULE_OFF"], value = "off", onclick = ruleOnclick},
                        {label = L["VISIBILITY_RULE_HIDE"], value = "hide", onclick = ruleOnclick},
                        {label = L["VISIBILITY_RULE_FADE"], value = "fade", onclick = ruleOnclick},
                    }
                end,
            }
        end

        visWidgets[#visWidgets + 1] = {
            type = "range",
            name = L["VISIBILITY_FADE_OPACITY"],
            desc = L["VISIBILITY_FADE_OPACITY_DESC"],
            min = 10,
            max = 90,
            step = 5,
            get = function()
                local rules = settings.visibility_rules
                return (rules and rules.fade_alpha) or 30
            end,
            set = function(_, _, value)
                if not settings.visibility_rules then
                    settings.visibility_rules = {fade_alpha = 30}
                end
                settings.visibility_rules.fade_alpha = value
                refreshSelectedFrame()
            end,
            disableif = function()
                local rules = settings.visibility_rules
                if not rules then return true end
                return rules.mounted ~= "fade" and rules.out_of_combat ~= "fade" and rules.no_target ~= "fade"
            end,
        }

        -- Tooltip mode + anchor: AF defaults seed tooltip_mode at frame creation
        -- so the dropdowns appear for every additional frame instance. Built into
        -- its own widget list so the Tooltip section gets its own header in col1.
        local tooltipWidgets = {}
        tooltipWidgets[#tooltipWidgets + 1] = {
            type = "select",
            name = L["TOOLTIP_MODE"],
            desc = L["TOOLTIP_MODE_DESC"],
            get = function() return settings.tooltip_mode or "off" end,
            set = function(_, _, value)
                settings.tooltip_mode = value
                refreshSelectedFrame()
                if private.Tooltip then private.Tooltip.RefreshAll() end
            end,
            values = function()
                local onclick = function(_, _, value)
                    settings.tooltip_mode = value
                    refreshSelectedFrame()
                    if private.Tooltip then private.Tooltip.RefreshAll() end
                end
                return {
                    {label = L["TOOLTIP_MODE_ALWAYS"], value = "always", onclick = onclick},
                    {label = L["TOOLTIP_MODE_OUT_OF_COMBAT"], value = "out_of_combat", onclick = onclick},
                    {label = L["TOOLTIP_MODE_OFF"], value = "off", onclick = onclick},
                }
            end,
        }
        tooltipWidgets[#tooltipWidgets + 1] = {
            type = "select",
            name = L["TOOLTIP_ANCHOR"],
            desc = L["TOOLTIP_ANCHOR_DESC"],
            get = function() return settings.tooltip_anchor or "RIGHT" end,
            set = function(_, _, value)
                settings.tooltip_anchor = value
                refreshSelectedFrame()
            end,
            values = function()
                local onclick = function(_, _, value)
                    settings.tooltip_anchor = value
                    refreshSelectedFrame()
                end
                return {
                    {label = L["TOOLTIP_ANCHOR_DEFAULT"], value = "DEFAULT", onclick = onclick},
                    {label = L["TOOLTIP_ANCHOR_CURSOR"], value = "CURSOR", onclick = onclick},
                    {label = L["TOOLTIP_ANCHOR_RIGHT"], value = "RIGHT", onclick = onclick},
                    {label = L["TOOLTIP_ANCHOR_TOP"], value = "TOP", onclick = onclick},
                }
            end,
        }

        -- =================================================================
        -- Merge into 3 columns and render
        -- =================================================================

        -- Column 1: Visibility + Tooltip + Anchoring + Size
        local col1Widgets = {}
        col1Widgets[#col1Widgets + 1] = {type = "label", get = function() return L["SETTING_VISIBILITY"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
        appendWidgets(col1Widgets, visWidgets)
        col1Widgets[#col1Widgets + 1] = {type = "blank"}
        col1Widgets[#col1Widgets + 1] = {type = "label", get = function() return L["SECTION_TOOLTIP"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
        appendWidgets(col1Widgets, tooltipWidgets)
        col1Widgets[#col1Widgets + 1] = {type = "blank"}
        col1Widgets[#col1Widgets + 1] = {type = "label", get = function() return L["SECTION_ANCHORING"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
        appendWidgets(col1Widgets, anchorWidgets)
        col1Widgets[#col1Widgets + 1] = {type = "blank"}
        col1Widgets[#col1Widgets + 1] = {type = "label", get = function() return L["SETTING_SIZE"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
        appendWidgets(col1Widgets, sizeWidgets)
        col1Widgets.always_boxfirst = true

        -- Column 2: Layout + Features + Glow/Colors + Custom Spells
        local col2Widgets = {}
        local refreshFn = function() refreshSelectedFrame() end
        col2Widgets[#col2Widgets + 1] = {type = "label", get = function() return L["SECTION_LAYOUT_SETTINGS"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
        appendWidgets(col2Widgets, layoutWidgets)
        if #featuresWidgets > 0 then
            col2Widgets[#col2Widgets + 1] = {type = "blank"}
            appendWidgets(col2Widgets, featuresWidgets)
        end
        if #glowColorsWidgets > 0 then
            col2Widgets[#col2Widgets + 1] = {type = "blank"}
            appendWidgets(col2Widgets, glowColorsWidgets)
        end
        col2Widgets.always_boxfirst = true

        -- Column 3: Fonts (all text/font options)
        local col3Widgets = {}
        if settings.frame_type == "bar" then
            appendWidgets(col3Widgets, buildAFFontWidgets("name_font", L["SETTING_NAME_TEXT"], 24, refreshFn))
            col3Widgets[#col3Widgets + 1] = {type = "blank"}
            appendWidgets(col3Widgets, buildAFFontWidgets("duration_font", L["SETTING_DURATION_TEXT"], 24, refreshFn))
            col3Widgets[#col3Widgets + 1] = {type = "blank"}
            appendWidgets(col3Widgets, buildAFFontWidgets("stacks_font", L["SETTING_STACKS_TEXT"], 32, refreshFn, true))
        else
            appendWidgets(col3Widgets, buildAFFontWidgets("timer_font", L["SETTING_TIMER_TEXT"], 32, refreshFn, true))
            col3Widgets[#col3Widgets + 1] = {type = "blank"}
            appendWidgets(col3Widgets, buildAFFontWidgets("stacks_font", L["SETTING_STACKS_TEXT"], 32, refreshFn, true))

            -- Keybind text: enabled toggle + font widgets
            col3Widgets[#col3Widgets + 1] = {type = "blank"}
            col3Widgets[#col3Widgets + 1] = {type = "label", get = function() return L["SETTING_KEYBIND_TEXT"] end, text_template = orangeFontTemplate, color = orangeFontTemplate.color}
            col3Widgets[#col3Widgets + 1] = {
                type = "toggle",
                name = L["SETTING_SHOW_KEYBIND"],
                desc = L["SETTING_SHOW_KEYBIND_DESC"],
                get = function() return settings.keybind_font and settings.keybind_font.enabled end,
                set = function(_, _, value)
                    if not settings.keybind_font then
                        settings.keybind_font = {
                            enabled = false,
                            font_face = "2002",
                            font_size = 12,
                            font_flags = "OUTLINE",
                            font_color = {1, 1, 1, 1},
                            anchor_point = "BOTTOMLEFT",
                            offset_x = 2,
                            offset_y = 2,
                        }
                    end
                    settings.keybind_font.enabled = value
                    refreshFn()
                end,
            }
            local keybindDisable = function()
                return not (settings.keybind_font and settings.keybind_font.enabled)
            end
            local kbWidgets = buildAFFontWidgets("keybind_font", L["SETTING_KEYBIND_TEXT"], 32, refreshFn, true)
            -- Remove the header label (first widget) since we already added one above
            table.remove(kbWidgets, 1)
            for _, w in ipairs(kbWidgets) do
                if not w.disableif then w.disableif = keybindDisable end
            end
            appendWidgets(col3Widgets, kbWidgets)
        end
        col3Widgets.always_boxfirst = true

        framework:BuildMenuVolatile(col1Frame, col1Widgets, 0, 0, 3000, false,
            options_text_template, options_dropdown_template, options_switch_template,
            true, options_slider_template, options_button_template, refreshAFColumns)
        resetSwitchPool(col1Frame)

        framework:BuildMenuVolatile(col2Frame, col2Widgets, 0, 0, 3000, false,
            options_text_template, options_dropdown_template, options_switch_template,
            true, options_slider_template, options_button_template, refreshAFColumns)
        resetSwitchPool(col2Frame)

        framework:BuildMenuVolatile(col3Frame, col3Widgets, 0, 0, 3000, false,
            options_text_template, options_dropdown_template, options_switch_template,
            true, options_slider_template, options_button_template, refreshAFColumns)
        resetSwitchPool(col3Frame)

        limitDropdownMenuHeight(col1Frame)
        limitDropdownMenuHeight(col2Frame)
        limitDropdownMenuHeight(col3Frame)

        -- Update scroll child height based on content
        -- Fixed content above columns: name (~40) + gap (~15) + Tracking-tab button (~22) + gap (~25)
        local fixedContentHeight = 102
        local tallestCol = math.max(estimateWidgetHeight(col1Widgets), estimateWidgetHeight(col2Widgets), estimateWidgetHeight(col3Widgets))
        afScrollChild:SetHeight(fixedContentHeight + tallestCol + 50)
        afScrollFrame:SetVerticalScroll(0)
    end

    -- =====================================================================
    -- Sidebar list rebuild + detail selection
    -- =====================================================================

    ---Select an additional frame in the sidebar and populate the detail panel.
    ---@param frameId string|nil
    local function selectFrame(frameId)
        selectedFrameId = frameId

        -- Update sidebar button highlights
        for _, btn in ipairs(listButtons) do
            if btn._cue_frameId == frameId then
                btn._cue_indicator:SetColorTexture(1, 0.85, 0)
                btn._cue_indicator:SetAlpha(1)
            else
                btn._cue_indicator:SetColorTexture(0.4, 0.4, 0.4)
                btn._cue_indicator:SetAlpha(0.6)
            end
        end

        if not frameId or not private.profile.additional_frames[frameId] then
            emptyLabel:Show()
            afScrollFrame:Hide()
            detailContent:Hide()
            return
        end

        emptyLabel:Hide()
        afScrollFrame:Show()
        detailContent:Show()

        local settings = private.profile.additional_frames[frameId]
        nameEntry:SetText(settings.name or frameId)
        local typeNames = { spells = "Spells", buffs = "Buffs", bar = "Bar" }
        typeLabel:SetText(string.format(L["FRAME_TYPE_LABEL"], typeNames[settings.frame_type] or settings.frame_type))
        enabledToggle:SetValue(settings.enabled)

        buildLayoutSettings()
    end

    ---Rebuild the sidebar frame list and optionally select a frame.
    ---@param selectId string|nil frame to select after rebuild
    local function rebuild(selectId)
        -- Hide existing sidebar buttons
        for _, btn in ipairs(listButtons) do
            btn:Hide()
        end
        wipe(listButtons)

        local frameIds = private.AdditionalFrameManager.GetAllFrameIds()
        local yOffset = 0

        for _, fid in ipairs(frameIds) do
            local settings = private.profile.additional_frames[fid]
            if settings then
                local label = settings.name or fid
                local btn = framework:CreateButton(listScrollChild, function()
                    selectFrame(fid)
                end, sidebarWidth - 26, 22, label, false, false, false, nil, nil)
                btn:SetPoint("TOPLEFT", listScrollChild, "TOPLEFT", 0, yOffset)
                btn:SetTemplate(buttonTemplate)

                -- Left indicator
                local indicator = btn.widget:CreateTexture(nil, "OVERLAY")
                indicator:SetSnapToPixelGrid(false)
                indicator:SetTexelSnappingBias(0)
                indicator:SetSize(4, 18)
                indicator:SetPoint("LEFT", btn.widget, "LEFT", 2, 0)
                btn._cue_indicator = indicator
                btn._cue_frameId = fid

                listButtons[#listButtons + 1] = btn
                yOffset = yOffset - 26
            end
        end
        listScrollChild:SetHeight(-yOffset)

        -- Show empty state if no frames
        if #frameIds == 0 then
            emptyLabel:Show()
            afScrollFrame:Hide()
            detailContent:Hide()
            selectedFrameId = nil
        else
            selectFrame(selectId or frameIds[1])
        end
    end

    -- Store rebuild as upvalue-accessible function for create/delete callbacks
    buildAdditionalFramesTab_Rebuild = rebuild

    -- Static popup for delete confirmation
    StaticPopupDialogs["CLASSUIENHANCED_DELETE_AF"] = {
        text = L["DELETE_FRAME_CONFIRM"],
        button1 = YES,
        button2 = NO,
        OnAccept = function(_, frameId)
            if frameId and private.profile.additional_frames[frameId] then
                private.AdditionalFrameManager.DeleteFrame(frameId)
                rebuild(nil)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    -- Rebuild when profile changes so the sidebar reflects the new profile's frames
    private.Callback.Register("OnProfileChanged", function()
        rebuild(nil)
    end)

    -- Initial build
    rebuild(nil)
end

local function buildAboutTab(panel)
    local logoTexturePath = "Interface\\AddOns\\" .. addonName .. "\\Assets\\Textures\\logo.png"
    local version = private.GetVersionInfo()

    -- Logo centered at top
    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSnapToPixelGrid(false)
    logo:SetTexelSnappingBias(0)
    logo:SetSize(128, 128)
    logo:SetPoint("TOP", panel, "TOP", 0, -20)
    logo:SetTexture(logoTexturePath)

    -- Addon name
    local titleFont = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    titleFont:SetPoint("TOP", logo, "BOTTOM", 0, -10)
    titleFont:SetText(addonName)
    titleFont:SetTextColor(1, 0.82, 0)

    -- Description
    local desc = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOP", titleFont, "BOTTOM", 0, -10)
    desc:SetPoint("LEFT", panel, "LEFT", 40, 0)
    desc:SetPoint("RIGHT", panel, "RIGHT", -40, 0)
    desc:SetWordWrap(true)
    desc:SetNonSpaceWrap(true)
    desc:SetJustifyH("CENTER")
    desc:SetText(L["ABOUT_DESCRIPTION"])
    desc:SetTextColor(0.8, 0.8, 0.8)

    -- Version line (copyable)
    local versionAnchor = desc
    local infoY = -40
    if version ~= "" then
        local versionLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        versionLabel:SetPoint("TOP", desc, "BOTTOM", 0, -20)
        versionLabel:SetText(L["ABOUT_VERSION_LABEL"] .. ":")
        versionLabel:SetTextColor(1, 0.82, 0)

        local versionBox = framework:CreateTextEntry(panel, function() end, 300, 24, "AboutVersionBox", frameName .. "AboutVersionBox")
        versionBox:SetPoint("TOP", versionLabel, "BOTTOM", 0, -5)
        versionBox:SetText(version)
        versionBox:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(version)
                self:HighlightText()
            end
        end)
        versionBox:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
        end)

        versionAnchor = versionBox.widget
        infoY = -15
    end

    local infoAnchor = versionAnchor

    -- Authors
    local authorsLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    authorsLabel:SetPoint("TOP", infoAnchor, "BOTTOM", 0, infoY)
    authorsLabel:SetText(L["ABOUT_AUTHORS_LABEL"] .. ": |cffffffff" .. L["ABOUT_AUTHORS"] .. "|r")
    authorsLabel:SetTextColor(1, 0.82, 0)

    -- Discord
    local discordLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    discordLabel:SetPoint("TOP", authorsLabel, "BOTTOM", 0, -15)
    discordLabel:SetText(L["ABOUT_DISCORD_LABEL"] .. ":")
    discordLabel:SetTextColor(1, 0.82, 0)

    -- Editable but read-only text entry for the Discord link (copyable)
    local discordUrl = "https://discord.gg/8dWuth44Dx"
    local discordBox = framework:CreateTextEntry(panel, function() end, 300, 24, "AboutDiscordLink", frameName .. "AboutDiscordLink")
    discordBox:SetPoint("TOP", discordLabel, "BOTTOM", 0, -5)
    discordBox:SetText(discordUrl)

    -- Make it read-only: revert any edits and re-select on focus
    discordBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(discordUrl)
            self:HighlightText()
        end
    end)
    discordBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)

    -- Changelog button
    local changelogBtn = framework:CreateButton(panel, function()
        showChangelogPopup()
    end, 120, 28, L["ABOUT_CHANGELOG"], false, false, false, nil, nil)
    changelogBtn:SetPoint("TOP", discordBox.widget, "BOTTOM", 0, -20)
    changelogBtn:SetTemplate(private.Templates.ButtonTemplate)
end

function private.Options.CreateOptionsFrame()
    optionsFrame = framework:CreateRoundedPanel(uiParent, frameName, private.Templates.RoundedCornerPreset)
    optionsFrame:SetSize(private.Templates.OptionsPanel.width, private.Templates.OptionsPanel.height)
    optionsFrame:SetPoint("center", uiParent, "center", 0, 0)
    optionsFrame:SetFrameStrata("DIALOG")
    optionsFrame:SetFrameLevel(400)
    optionsFrame:SetToplevel(true)

    framework:MakeDraggable(optionsFrame)

    -- ESC key closes the panel (WoW looks up UISpecialFrames by global name)
    tinsert(UISpecialFrames, frameName)

    -- Close button (top-right, desaturated check mark — matches DetailsFramework SimplePanel style)
    local closeBtn = CreateFrame("Button", nil, optionsFrame)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("topright", optionsFrame, "topright", -8, -8)
    closeBtn:SetNormalTexture([[Interface\GLUES\LOGIN\Glues-CheckBox-Check]])
    closeBtn:SetHighlightTexture([[Interface\GLUES\LOGIN\Glues-CheckBox-Check]])
    closeBtn:SetPushedTexture([[Interface\GLUES\LOGIN\Glues-CheckBox-Check]])
    closeBtn:GetNormalTexture():SetDesaturated(true)
    closeBtn:GetHighlightTexture():SetDesaturated(true)
    closeBtn:GetPushedTexture():SetDesaturated(true)
    closeBtn:SetAlpha(0.7)
    closeBtn:SetScript("OnClick", function() optionsFrame:Hide() end)

    -- Title fontstring
    local titleFontString = optionsFrame:CreateFontString(nil, "overlay", "GameFontNormal")
    titleFontString:SetPoint("top", optionsFrame, "top", 0, -5)
    titleFontString:SetText(L["OPTIONS_TITLE"])

    -- Version info (top-right, subtle)
    local versionText = framework:CreateLabel(optionsFrame, private.GetVersionInfo(), 11, "white")
    versionText:SetPoint("topright", optionsFrame, "topright", -28, -7)
    versionText:SetAlpha(0.75)

    -- Title logo with circular mask so it doesn't clip the rounded border or tabs
    local addonIcon = optionsFrame:CreateTexture(nil, "overlay")
    addonIcon:SetSnapToPixelGrid(false)
    addonIcon:SetTexelSnappingBias(0)
    addonIcon:SetSize(24, 24)
    addonIcon:SetPoint("topleft", optionsFrame, "topleft", 3, -3)
    addonIcon:SetTexture(private.Templates.TitleTexture)

    local iconMask = optionsFrame:CreateMaskTexture()
    iconMask:SetSnapToPixelGrid(false)
    iconMask:SetTexelSnappingBias(0)
    iconMask:SetAllPoints(addonIcon)
    iconMask:SetTexture("Interface/CHARACTERFRAME/TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    addonIcon:AddMaskTexture(iconMask)

    -- Options panel scale slider — delegated to DetailsFramework's CreateScaleBar
    -- (same code Plater uses). It builds the "Scale:" label + 120×14 slider at frame's
    -- upper-left, handles right-click manual-entry editbox, and applies frame:SetScale
    -- on mouse-up. We pass a metatable proxy so reads/writes of config.scale go straight
    -- to our global SavedVariables (db.global.options_panel_scale) — persists across
    -- profile switches. Sentinel 0 in SavedVariables means "auto" and is resolved once
    -- on first open to 1/UIParent:GetScale() (clamped to the 0.6–1.6 range CreateScaleBar
    -- enforces internally).
    local panelW = private.Templates.OptionsPanel.width
    local panelH = private.Templates.OptionsPanel.height

    local savedScale = private.public.db.global.options_panel_scale
    if not savedScale or savedScale <= 0 then
        local auto = 1 / UIParent:GetScale()
        if auto > 1.6 then auto = 1.6 end
        if auto < 0.6 then auto = 0.6 end
        private.public.db.global.options_panel_scale = auto
    end

    -- Round to 2 decimals so the right-click editbox and slider readouts don't show
    -- floating-point noise like 0.9500000001 when the step-0.05 slider lands there.
    local function roundScale(v)
        return math.floor((v or 0) * 100 + 0.5) / 100
    end
    local scaleBarConfig = setmetatable({}, {
        __index = function(_, k)
            if k == "scale" then return roundScale(private.public.db.global.options_panel_scale) end
        end,
        __newindex = function(_, k, v)
            if k == "scale" and type(v) == "number" then
                private.public.db.global.options_panel_scale = roundScale(v)
            end
        end,
    })

    optionsFrame:SetScale(private.public.db.global.options_panel_scale)
    local scaleBar = framework:CreateScaleBar(optionsFrame, scaleBarConfig)

    -- Pre-select the editbox text on right-click so the user can overtype immediately.
    -- The editbox is a child of scaleBar.widget (the Slider frame) and isn't exposed,
    -- so we locate it via GetChildren and hook its focus event non-destructively.
    for _, child in ipairs({scaleBar.widget:GetChildren()}) do
        if child:GetObjectType() == "EditBox" then
            child:HookScript("OnEditFocusGained", function(self)
                self:HighlightText()
            end)
            break
        end
    end

    -- Move "Scale:" label (and, via the label→slider anchor, the slider itself)
    -- out of the upper-left so the addon icon can sit at its original position.
    for _, region in ipairs({scaleBar.widget:GetRegions()}) do
        if region:GetObjectType() == "FontString" and region:GetText() == "Scale:" then
            region:ClearAllPoints()
            region:SetPoint("topleft", optionsFrame, "topleft", 32, -7)
            break
        end
    end

    -- Exposed for /cue resetoptionspanel — resets scale to 1 and re-centers the panel.
    private.Options.ResetOptionsPanelLayout = function()
        private.public.db.global.options_panel_scale = 1
        if scaleBar and scaleBar.SetValue then
            scaleBar:SetValue(1)
        end
        optionsFrame:SetScale(1)
        optionsFrame:ClearAllPoints()
        optionsFrame:SetPoint("topleft", uiParent, "topleft",
            (uiParent:GetWidth() - panelW) / 2,
            -(uiParent:GetHeight() - panelH) / 2)
    end

    -- Content panels (shared position, toggled by tab buttons)
    local contentX = 10
    local contentY = -58
    local contentW = private.Templates.OptionsPanel.width - 20
    local contentH = private.Templates.OptionsPanel.height - 68

    local generalPanel = CreateFrame("Frame", frameName .. "GeneralPanel", optionsFrame)
    generalPanel:SetSize(contentW, contentH)
    generalPanel:SetPoint("topleft", optionsFrame, "topleft", contentX, contentY)

    local colorsPanel = CreateFrame("Frame", frameName .. "ColorsPanel", optionsFrame)
    colorsPanel:SetSize(contentW, contentH)
    colorsPanel:SetPoint("topleft", optionsFrame, "topleft", contentX, contentY)
    colorsPanel:Hide()

    local trackersPanel = CreateFrame("Frame", frameName .. "TrackersPanel", optionsFrame)
    trackersPanel:SetSize(contentW, contentH)
    trackersPanel:SetPoint("topleft", optionsFrame, "topleft", contentX, contentY)
    trackersPanel:Hide()

    local additionalFramesPanel = CreateFrame("Frame", frameName .. "AdditionalFramesPanel", optionsFrame)
    additionalFramesPanel:SetSize(contentW, contentH)
    additionalFramesPanel:SetPoint("topleft", optionsFrame, "topleft", contentX, contentY)
    additionalFramesPanel:Hide()

    local trackingPanel = CreateFrame("Frame", frameName .. "TrackingPanel", optionsFrame)
    trackingPanel:SetSize(contentW, contentH)
    trackingPanel:SetPoint("topleft", optionsFrame, "topleft", contentX, contentY)
    trackingPanel:Hide()

    local profilePanel = CreateFrame("Frame", nil, optionsFrame)
    profilePanel:SetSize(contentW, contentH)
    profilePanel:SetPoint("topleft", optionsFrame, "topleft", contentX, contentY)
    profilePanel:Hide()

    local importExportPanel = CreateFrame("Frame", nil, optionsFrame)
    importExportPanel:SetSize(contentW, contentH)
    importExportPanel:SetPoint("topleft", optionsFrame, "topleft", contentX, contentY)
    importExportPanel:Hide()

    local aboutPanel = CreateFrame("Frame", nil, optionsFrame)
    aboutPanel:SetSize(contentW, contentH)
    aboutPanel:SetPoint("topleft", optionsFrame, "topleft", contentX, contentY)
    aboutPanel:Hide()

    -- Tab system with left selection indicators (Plater-style tab buttons)
    local tabButtons = {}
    local tabPanels = {generalPanel, trackersPanel, additionalFramesPanel, trackingPanel, colorsPanel, profilePanel, importExportPanel, aboutPanel}

    ---Switch to the given tab index: update indicators and show/hide panels.
    ---@param index number
    local function selectTab(index)
        for i, tab in ipairs(tabButtons) do
            if i == index then
                tab._cue_indicator:SetColorTexture(1, 0.85, 0)
                tab._cue_indicator:SetAlpha(1)
                tabPanels[i]:Show()
            else
                tab._cue_indicator:SetColorTexture(0.4, 0.4, 0.4)
                tab._cue_indicator:SetAlpha(0.6)
                tabPanels[i]:Hide()
            end
        end
    end

    -- Expose to module-level upvalue so OpenOptionsPanel can switch tabs.
    selectTabFn = selectTab

    ---Create a styled tab button with a left selection indicator bar.
    ---Width is computed dynamically from the label text.
    ---@param label string
    ---@param tabIndex number
    ---@return table dfButton
    local function createTabButton(label, tabIndex)
        local tabPad = 20
        local btn = framework:CreateButton(optionsFrame, function()
            selectTab(tabIndex)
        end, 80, 25, label, false, false, false, nil, nil)
        btn.widget:SetWidth(btn.widget.text:GetStringWidth() + tabPad)

        -- Left-side colored bar (4px wide, matches button height minus small inset)
        local indicator = btn.widget:CreateTexture(nil, "OVERLAY")
        indicator:SetSnapToPixelGrid(false)
        indicator:SetTexelSnappingBias(0)
        indicator:SetSize(4, 21)
        indicator:SetPoint("LEFT", btn.widget, "LEFT", 2, 0)
        btn._cue_indicator = indicator

        return btn
    end

    local buttonTemplate = private.Templates.ButtonTemplate

    tabButtons[1] = createTabButton(L["TAB_GENERAL"], 1)
    tabButtons[1]:SetPoint("topleft", optionsFrame, "topleft", 10, -30)
    tabButtons[1]:SetTemplate(buttonTemplate)

    tabButtons[2] = createTabButton(L["TAB_TRACKERS"], 2)
    tabButtons[2]:SetPoint("left", tabButtons[1].widget, "right", 5, 0)
    tabButtons[2]:SetTemplate(buttonTemplate)

    tabButtons[3] = createTabButton(L["TAB_ADDITIONAL_TRACKERS"], 3)
    tabButtons[3]:SetPoint("left", tabButtons[2].widget, "right", 5, 0)
    tabButtons[3]:SetTemplate(buttonTemplate)

    tabButtons[4] = createTabButton(L["TAB_TRACKING"], 4)
    tabButtons[4]:SetPoint("left", tabButtons[3].widget, "right", 5, 0)
    tabButtons[4]:SetTemplate(buttonTemplate)

    tabButtons[5] = createTabButton(L["TAB_COLORS"], 5)
    tabButtons[5]:SetPoint("left", tabButtons[4].widget, "right", 5, 0)
    tabButtons[5]:SetTemplate(buttonTemplate)

    tabButtons[6] = createTabButton(L["TAB_PROFILE_MANAGEMENT"], 6)
    tabButtons[6]:SetPoint("left", tabButtons[5].widget, "right", 5, 0)
    tabButtons[6]:SetTemplate(buttonTemplate)

    tabButtons[7] = createTabButton(L["TAB_IMPORT_EXPORT"], 7)
    tabButtons[7]:SetPoint("left", tabButtons[6].widget, "right", 5, 0)
    tabButtons[7]:SetTemplate(buttonTemplate)

    tabButtons[8] = createTabButton(L["TAB_ABOUT"], 8)
    tabButtons[8]:SetPoint("left", tabButtons[7].widget, "right", 5, 0)
    tabButtons[8]:SetTemplate(buttonTemplate)

    -- Auto-size a button to its text width + padding
    local function autoSizeButton(btn, hPadding)
        hPadding = hPadding or 24
        btn:SetWidth(btn.button.text:GetStringWidth() + hPadding)
    end

    -- Cooldown Settings button (rightmost)
    local cdSettingsBtn = framework:CreateButton(optionsFrame, function()
        _G["CooldownViewerSettings"]:Show()
    end, 100, 25, L["COOLDOWN_MANAGER_SETTINGS"], false, false, false, nil, nil)
    cdSettingsBtn:SetPoint("topright", optionsFrame, "topright", -10, -30)
    cdSettingsBtn:SetTemplate(buttonTemplate)
    autoSizeButton(cdSettingsBtn)
    -- No Cooldown Manager to open on MoP Classic.  Hidden, not removed: the
    -- Edit Mode button anchors to it.
    if not private.compat.HasCooldownManager() then cdSettingsBtn.widget:Hide() end

    -- Open Edit Mode button (to the left of Cooldown Settings)
    local editModeBtn = framework:CreateButton(optionsFrame, function()
        optionsFrame:Hide()
        ShowUIPanel(EditModeManagerFrame)
    end, 100, 25, L["OPEN_EDIT_MODE"], false, false, false, nil, nil)
    editModeBtn:SetPoint("right", cdSettingsBtn.widget, "left", -5, 0)
    editModeBtn:SetTemplate(buttonTemplate)
    autoSizeButton(editModeBtn)

    -- Select the first tab by default
    selectTab(1)

    -- Build tab content
    buildGeneralTab(generalPanel)
    buildColorsTab(colorsPanel)
    buildTrackersTab(trackersPanel)
    buildAdditionalFramesTab(additionalFramesPanel)
    private.TrackingTab.Build(trackingPanel)
    -- The Tracking tab's listeners follow the whole window, not only tab switches.
    optionsFrame:HookScript("OnShow", private.TrackingTab.Attach)
    optionsFrame:HookScript("OnHide", private.TrackingTab.Detach)
    buildProfileManagementTab(profilePanel)
    buildImportExportTab(importExportPanel)
    buildAboutTab(aboutPanel)

    return optionsFrame
end

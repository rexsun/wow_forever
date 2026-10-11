local ADDON_NAME = ...
local YUI = _G.YUI
if not (YUI and YUI.YHUD and YUI.YHUD.Client) then return end

local YHUD = YUI.YHUD or {}
YUI.YHUD = YHUD

YHUD.PRODUCT_ID = "yhud"
YHUD.IS_STANDALONE = YUI.GetAddonProductId
    and YUI:GetAddonProductId(ADDON_NAME, "suite") == YHUD.PRODUCT_ID or false
YHUD.STORAGE_KEY = "YHUD"
YHUD.SETTINGS_ENTRY = "yhud.settings"
YHUD.CONFIG_SET_PROVIDER_ID = "yhud"
YHUD.LAYOUT_TRINKETS_ID = "yui.product.yhud.trinkets"
YHUD.VERSION = "0.5.0"
YHUD.SCHEMA_VERSION = 44
YHUD.PROFILE_VERSION = 44

YHUD.EQUIPMENT_AURA_BUNDLE_ENTRY_KEY = "bundle:equipment-auras"
YHUD.EQUIPMENT_AURA_BUNDLE_MONITOR_ID = "monitor:bundle:equipment-auras"
YHUD.EQUIPMENT_AURA_BUNDLE_KIND = "equipmentAura"

YHUD.runtimeProfileRevision =
    (tonumber(YHUD.runtimeProfileRevision) or 0) + 1
YHUD.profileCacheStats = YHUD.profileCacheStats or {}
YHUD.profileCacheStats.hits = YHUD.profileCacheStats.hits or 0
YHUD.profileCacheStats.misses = YHUD.profileCacheStats.misses or 0
YHUD.profileCacheStats.invalidations =
    YHUD.profileCacheStats.invalidations or 0
YHUD._runtimeProfile = nil
YHUD._runtimeProfileCanonical = nil
YHUD._runtimeProfileSpecKey = nil
YHUD._runtimeProfileRevision = nil
YHUD._mergedDB = nil
YHUD._mergedDBProfile = nil

YHUD.GROUP_IDS = {
    IMPORTANT = "group:official:important",
    UTILITY = "group:official:utility",
    BUFF = "group:official:buff",
    BAR = "group:official:bar",
    RESOURCES = "group:system:resources",
    TRINKETS = "group:system:trinkets",
    SKYRIDING = "group:system:skyriding",
}

YHUD.DEFAULT_GROUP_BY_CATEGORY = {
    essential = YHUD.GROUP_IDS.IMPORTANT,
    utility = YHUD.GROUP_IDS.UTILITY,
    trackedBuff = YHUD.GROUP_IDS.BUFF,
    trackedBar = YHUD.GROUP_IDS.BAR,
}

YHUD.DEFAULT_CATEGORY_BY_GROUP = {
    [YHUD.GROUP_IDS.IMPORTANT] = "essential",
    [YHUD.GROUP_IDS.UTILITY] = "utility",
    [YHUD.GROUP_IDS.BUFF] = "trackedBuff",
    [YHUD.GROUP_IDS.BAR] = "trackedBar",
}

local DEFAULT_GROUP_ORDER = {
    YHUD.GROUP_IDS.IMPORTANT,
    YHUD.GROUP_IDS.UTILITY,
    YHUD.GROUP_IDS.BUFF,
    YHUD.GROUP_IDS.BAR,
    YHUD.GROUP_IDS.RESOURCES,
    YHUD.GROUP_IDS.TRINKETS,
}

local DEFAULT_ICON_GROUP_LAYOUT = {
    iconSize = 42,
    columnSpacing = 1,
    rowSpacing = 1,
    maxPerLine = 6,
    alignment = "center",
    wrapDirection = "down",
    rowDirection = "right",
}

local DEFAULT_ICON_GROUP_STYLE = {
    iconShape = "roundedSquare",
    iconBorder = "thin",
    iconZoom = 0.08,
    iconBorderColor = { r = 0, g = 0, b = 0, a = 1 },
    iconBackgroundColor = { r = 0, g = 0, b = 0, a = 0.72 },
    iconShadow = true,
    iconShadowColor = { r = 0, g = 0, b = 0, a = 0.5 },
    cooldownSwipeColor = { r = 0, g = 0, b = 0, a = 0.82 },
    cooldownSwipe = true,
    cooldownGCD = true,
    cooldownBling = false,
    cooldownText = true,
    cooldownTextFont = "default",
    cooldownTextSize = 14,
    cooldownTextOutline = "outlineShadow",
    cooldownTextPosition = "center",
    cooldownTextOffsetX = 0,
    cooldownTextOffsetY = 0,
    cooldownTextColor = {
        r = 1,
        g = 1,
        b = 1,
        a = 1,
    },
    keybindTextMode = "off",
    keybindTextFont = "default",
    keybindTextSize = 12,
    keybindTextOutline = "outlineShadow",
    keybindTextPosition = "top-right",
    keybindTextOffsetX = 2,
    keybindTextOffsetY = 1,
    keybindTextColor = { r = 1, g = 1, b = 1, a = 1 },
    keybindTextOverrides = {},
    countText = true,
    countTextFont = "default",
    countTextSize = 12,
    countTextOutline = "outlineShadow",
    countTextPosition = "bottom",
    countTextOffsetX = -2,
    countTextOffsetY = 2,
    countTextColor = { r = 1, g = 1, b = 1, a = 1 },
}

local DEFAULT_BAR_GROUP_LAYOUT = {
    width = 244,
    height = 24,
    columnSpacing = 6,
    rowSpacing = 6,
    maxPerLine = 1,
    alignment = "center",
    wrapDirection = "up",
    orientation = "horizontal",
    fillDirection = "forward",
    iconPosition = "left",
    iconGap = 0,
}

local DEFAULT_RING_GROUP_LAYOUT = {
    diameter = 52,
    ringStep = 8,
    columnSpacing = 8,
    rowSpacing = 8,
    maxPerLine = 6,
    alignment = "center",
    wrapDirection = "up",
}

local DEFAULT_RESOURCE_GROUP_LAYOUT = {
    widthMode = "auto",
    width = 290,
    minWidth = 150,
    height = 16,
    spacing = -1,
    alignment = "center",
    direction = "down",
    orientation = "horizontal",
    fillDirection = "forward",
}

local DEFAULT_DURATION_GROUP_STYLE = {
    smoothProgress = true,
    iconShape = "square",
    iconBorder = "thin",
    cooldownText = true,
    cooldownTextFont = "default",
    cooldownTextSize = 13,
    cooldownTextOutline = "outlineShadow",
    cooldownTextPosition = "center",
    cooldownTextColor = {
        r = 1,
        g = 1,
        b = 1,
        a = 1,
    },
    nameText = true,
    nameTextFormat = "%n",
    nameTextFont = "default",
    nameTextSize = 12,
    nameTextOutline = "outlineShadow",
    nameTextPosition = "center",
    nameTextAnchor = "bar-center",
    nameTextOffsetX = 0,
    nameTextOffsetY = 0,
    nameTextColor = {
        r = 1,
        g = 1,
        b = 1,
        a = 1,
    },
    fillColor = {
        r = 0.25,
        g = 0.55,
        b = 0.95,
        a = 1,
    },
    fillTexture = "yui-g1",
    trackColor = { r = 0.04, g = 0.06, b = 0.08, a = 0.92 },
    borderColor = { r = 0, g = 0, b = 0, a = 1 },
    showIcon = true,
    timeText = true,
    timeTextFont = "default",
    timeTextSize = 12,
    timeTextOutline = "outlineShadow",
    timeTextPosition = "right",
    timeTextAnchor = "bar-right",
    timeTextOffsetX = 0,
    timeTextOffsetY = 0,
    timeTextColor = { r = 1, g = 1, b = 1, a = 1 },
    countTextAnchor = "icon-bottom-right",
    ringThickness = 8,
    ringDirection = "clockwise",
    ringStart = "top",
    ringTrackColor = { r = 0.04, g = 0.06, b = 0.08, a = 0.92 },
    ringBorderColor = { r = 0, g = 0, b = 0, a = 1 },
}

local DEFAULT_RESOURCE_GROUP_STYLE = {
    smoothProgress = true,
    border = 1,
    borderColor = { r = 0, g = 0, b = 0, a = 1 },
    fillTexture = "yui-g1",
    fillColorMode = "resource",
    fillColor = { r = 0.25, g = 0.55, b = 0.95, a = 1 },
    textFont = "default",
    textSize = 12,
    textOutline = "outlineShadow",
    textColor = {
        r = 1,
        g = 1,
        b = 1,
        a = 1,
    },
    backgroundColor = {
        r = 0.04,
        g = 0.06,
        b = 0.08,
        a = 0.92,
    },
}

local DEFAULT_MONITOR_GLOW_APPEARANCE = {
        style = "pixel",
        size = 1,
        lines = 6,
        thickness = 2,
        speed = 0.25,
        alpha = 0.9,
        offsetX = 0,
        offsetY = 0,
        color = {
            1,
            0.70,
            0.10,
            1,
        },
}

local DEFAULT_NATIVE_PROC_GLOW = {
    mode = "default",
}

local DEFAULT_SHARED_CONTENT = {
    entries = {
        ["slot:13"] = {
            entryKey = "slot:13",
            sourceKey = "slot:13",
            sourceType = "yhud.inventory-slot-cooldown",
            semantic = "cooldown",
            origin = "preset",
            presetKey = "slot:13",
            crossSpecMaterialization = "immediate",
            slotId = 13,
            contract = {
                capability = "full",
                view = "self",
                group = "free",
                style = "full",
                fallback = "hide",
            },
        },
        ["slot:14"] = {
            entryKey = "slot:14",
            sourceKey = "slot:14",
            sourceType = "yhud.inventory-slot-cooldown",
            semantic = "cooldown",
            origin = "preset",
            presetKey = "slot:14",
            crossSpecMaterialization = "immediate",
            slotId = 14,
            contract = {
                capability = "full",
                view = "self",
                group = "free",
                style = "full",
                fallback = "hide",
            },
        },
    },
    monitors = {
        ["monitor:slot:13"] = {
            id = "monitor:slot:13",
            entryKey = "slot:13",
            sourceKey = "slot:13",
            groupId = YHUD.GROUP_IDS.TRINKETS,
            view = "icon",
            order = 1,
            enabled = true,
        },
        ["monitor:slot:14"] = {
            id = "monitor:slot:14",
            entryKey = "slot:14",
            sourceKey = "slot:14",
            groupId = YHUD.GROUP_IDS.TRINKETS,
            view = "icon",
            order = 2,
            enabled = true,
        },
    },
    groupMembers = {
        [YHUD.GROUP_IDS.TRINKETS] = {
            before = {},
            after = {
                "monitor:slot:13",
                "monitor:slot:14",
            },
        },
    },
}

local DEFAULT_SPEC_CONTENT = {
    initialization = {
        nativeSeedVersion = 0,
    },
    suppressedOfficial = {},
    entries = {},
    monitors = {},
    groupMembers = {},
}

local DEFAULT_SKYRIDING_STYLE_SETTINGS = {
    horizon = {
        width = 420,
        speedHeight = 18,
        resourceHeight = 8,
        iconSize = 48,
        ringThickness = 4,
        rowGap = 4,
        pipGap = 3,
        vigorColor = { r = 0.10, g = 0.88, b = 0.64, a = 1 },
        secondWindColor = { r = 1.00, g = 0.76, b = 0.18, a = 1 },
        speedFont = "default",
        speedFontSize = 12,
    },
    halo = {
        width = 287,
        speedHeight = 16,
        vigorHeight = 9,
        secondWindHeight = 9,
        rowGap = 1,
        pipGap = 2,
        vigorColor = { r = 0.10, g = 0.88, b = 0.64, a = 1 },
        secondWindColor = { r = 1.00, g = 0.76, b = 0.18, a = 1 },
        speedFont = "default",
        speedFontSize = 12,
    },
}

local DEFAULT_SKYRIDING_SETTINGS = {
    enabled = false,
    style = "halo",
    styles = DEFAULT_SKYRIDING_STYLE_SETTINGS,
}

local DEFAULT_PROFILE = assert(YHUD.Client.defaultProfile, "YHUD client default profile must load before Defaults")
DEFAULT_PROFILE.sharedContent = DEFAULT_PROFILE.sharedContent or DEFAULT_SHARED_CONTENT

DEFAULT_GROUP_ORDER = DEFAULT_PROFILE.groups.order
DEFAULT_SHARED_CONTENT = DEFAULT_PROFILE.sharedContent
local defaultSlotMonitor = DEFAULT_SHARED_CONTENT.monitors
    and DEFAULT_SHARED_CONTENT.monitors["monitor:slot:13"]
YHUD.DEFAULT_SLOT_PRESET_GROUP_ID =
    defaultSlotMonitor and defaultSlotMonitor.groupId
    or YHUD.GROUP_IDS.TRINKETS

local BUILTIN_SPECIAL_RESOURCE_SELECTIONS = YHUD.Client.specialResourceSelections or {}
local BUILTIN_SPECIAL_RESOURCE_IDS = YHUD.Client.specialResourceIds or {}
local BUILTIN_SPECIAL_RESOURCE_SETTING_DEFAULTS = YHUD.Client.specialResourceSettingDefaults or {}

YHUD.Defaults = {
    enabled = false,
    schemaVersion = YHUD.SCHEMA_VERSION,
    profileVersion = YHUD.PROFILE_VERSION,
    profile = DEFAULT_PROFILE,
}

local function CopyValue(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do
        copy[CopyValue(key)] = CopyValue(child)
    end
    return copy
end

local function CopyPersistedValue(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do
        if type(key) ~= "string" or key:sub(1, 5) ~= "_yhud" then
            copy[CopyValue(key)] = CopyPersistedValue(child)
        end
    end
    return copy
end

local RESOURCE_SETTINGS_DELTA_VERSION = 1
YHUD._RESOURCE_SETTINGS_DELTA_VERSION = RESOURCE_SETTINGS_DELTA_VERSION
-- 历史存储基线固定不随客户端默认方案变化，保留已保存的资源文字偏好。
local RESOURCE_SETTINGS_STORAGE_BASELINE_V31 = {
    ["arcaneCharges"] = {
        ["valueText"] = false,
        ["visibilityMode"] = "nonzeroOrCombat",
    },
    ["arcaneSalvo"] = {
        ["visibilityMode"] = "nonzeroOrCombat",
    },
    ["comboPoints"] = {
        ["visibilityMode"] = "nonzeroOrCombat",
    },
    ["demonicCore"] = {
        ["displayMode"] = "divided",
        ["valueText"] = true,
        ["visibilityMode"] = "nonzeroOrCombat",
    },
    ["ebonMight"] = {
        ["valueFormat"] = "value",
    },
    ["energy"] = {
        ["valueFormat"] = "value",
    },
    ["fireBlastCharges"] = {
        ["valueText"] = false,
    },
    ["focus"] = {
        ["valueFormat"] = "value",
    },
    ["frozen"] = {
        ["fillColor"] = {
            ["g"] = 0.56078433990479,
            ["r"] = 0.23921570181847,
        },
        ["visibilityMode"] = "nonzeroOrCombat",
    },
    ["fury"] = {
        ["valueFormat"] = "value",
    },
    ["icicles"] = {
        ["fillColor"] = {
            ["g"] = 0.97254908084869,
            ["r"] = 0.89411771297455,
        },
        ["valueText"] = false,
        ["visibilityMode"] = "nonzeroOrCombat",
    },
    ["ignorePain"] = {
        ["visibilityMode"] = "nonzeroOrCombat",
    },
    ["insanity"] = {
        ["visibilityMode"] = "nonzeroOrCombat",
    },
    ["lunarPower"] = {
        ["fillColor"] = {
            ["b"] = 0.94901967048645,
            ["g"] = 0.90196084976196,
            ["r"] = 0.28627452254295,
        },
        ["valueFormat"] = "value",
    },
    ["maelstrom"] = {
        ["valueFormat"] = "value",
    },
    ["maelstromWeapon"] = {
        ["thresholdColorEnabled"] = true,
        ["thresholds"] = {
            ["high"] = {
                ["color"] = {
                    ["b"] = 0.1294117718935,
                    ["g"] = 0.50196081399918,
                    ["r"] = 0.94901967048645,
                },
                ["value"] = 6,
            },
            ["low"] = {
                ["color"] = {
                    ["b"] = 1,
                    ["g"] = 0.70196080207825,
                    ["r"] = 0.20000001788139,
                },
                ["enabled"] = false,
                ["value"] = 5,
            },
        },
    },
    ["mana"] = {
        ["heightOverride"] = 7,
        ["valueText"] = false,
        ["visibilityMode"] = "nonzeroOrCombat",
    },
    ["runes"] = {
        ["displayMode"] = "cells",
        ["segmentSpacing"] = 0,
        ["valueText"] = false,
    },
    ["runicPower"] = {
        ["valueFormat"] = "value",
        ["visibilityMode"] = "nonzeroOrCombat",
    },
    ["sweepingStrikes"] = {
        ["fillColor"] = {
            ["b"] = 0.18823531270027,
            ["g"] = 0.62745100259781,
            ["r"] = 0.92941182851791,
        },
        ["visibilityMode"] = "nonzero",
    },
    ["tipOfTheSpear"] = {
        ["valueText"] = false,
        ["visibilityMode"] = "nonzeroOrCombat",
    },
    ["vengeanceSoulFragments"] = {
        ["valueText"] = false,
        ["visibilityMode"] = "nonzeroOrCombat",
    },
    ["whirlwindStacks"] = {
        ["fillColor"] = {
            ["b"] = 1,
            ["g"] = 0.80000007152557,
            ["r"] = 0.27450981736183,
        },
        ["visibilityMode"] = "nonzeroOrCombat",
    },
}

-- Mainline uses catalog text formats; Forever keeps its explicit factory snapshot.
-- The frozen delta baseline above still describes previously saved profiles.
if YHUD.Client.id ~= "forever" then
    for _, setting in pairs(DEFAULT_PROFILE.resources.settingsByResource) do
        setting.valueFormat = nil
    end
end

local RESOURCE_TEXT_STORAGE_DEFAULTS = {
    mana = { true, "percent" }, rage = { true, "percent" },
    focus = { true, "value" }, energy = { true, "value" },
    runicPower = { true, "value" }, lunarPower = { true, "value" },
    maelstrom = { true, "value" }, insanity = { true, "percent" },
    fury = { true, "value" }, stagger = { true, "percent" },
    ignorePain = { true, "percent" }, ironfur = { false, "percent" },
    enrage = { false, "percent" }, ebonMight = { true, "value" },
    remoteStrike = { false, "percent" },
}

local function FillDefaults(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then return target end
    for key, defaultValue in pairs(defaults) do
        local value = target[key]
        if value == nil then
            target[key] = CopyValue(defaultValue)
        elseif type(value) == "table" and type(defaultValue) == "table" then
            if #defaultValue == 0 then
                FillDefaults(value, defaultValue)
            end
        end
    end
    return target
end

local EXISTING_PROFILE_DEFAULTS = CopyValue(DEFAULT_PROFILE)
do
    local editableDefaultGroups = {
        ["group:user:1"] = true,
        ["group:user:2"] = true,
    }
    for groupId in pairs(editableDefaultGroups) do
        EXISTING_PROFILE_DEFAULTS.groups.items[groupId] = nil
        EXISTING_PROFILE_DEFAULTS.layout.groups[groupId] = nil
        EXISTING_PROFILE_DEFAULTS.layout.placements[groupId] = nil
        EXISTING_PROFILE_DEFAULTS.style.groups[groupId] = nil
    end
    for index = #EXISTING_PROFILE_DEFAULTS.groups.order, 1, -1 do
        if editableDefaultGroups[
            EXISTING_PROFILE_DEFAULTS.groups.order[index]
        ] then
            table.remove(EXISTING_PROFILE_DEFAULTS.groups.order, index)
        end
    end
    EXISTING_PROFILE_DEFAULTS.sharedContent = {
        entries = {},
        monitors = {},
        groupMembers = {},
    }
    if YHUD.Client.id == "forever" then
        EXISTING_PROFILE_DEFAULTS.contentBySpec = {}
        EXISTING_PROFILE_DEFAULTS.officialOverridesBySpec = {}
        EXISTING_PROFILE_DEFAULTS.defaultPresetOverridesBySpec = {}
        EXISTING_PROFILE_DEFAULTS.defaultPresetTombstonesBySpec = {}
    end
end

local function ClampInteger(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value then return fallback end
    value = math.floor(value + 0.5)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function NormalizeBoolean(value, fallback)
    if value == nil then return fallback == true end
    return value == true
end

local function EncodeUtf8BytesAsLatin1(value)
    return (value:gsub("[\128-\255]", function(character)
        local byte = string.byte(character)
        if byte < 192 then return string.char(194, byte) end
        return string.char(195, byte - 64)
    end))
end

local LEGACY_MOJIBAKE_NAME_REPAIRS = {}
for _, correctName in ipairs({
    "英勇",
    "防御技能组",
    "鲁莽药水",
    "光注法力药水",
    "银月城生命药水",
    "圣光潜力",
    "治疗石",
    "种族技能组",
    "饰品栏 13",
    "饰品栏 14",
}) do
    LEGACY_MOJIBAKE_NAME_REPAIRS[
        EncodeUtf8BytesAsLatin1(correctName)
    ] = correctName
end

local function RepairLegacyMojibakeEntryNames(entries)
    if type(entries) ~= "table" then return end
    for _, entry in pairs(entries) do
        if type(entry) == "table" and entry.origin == "preset"
            and type(entry.name) == "string" then
            local repaired = LEGACY_MOJIBAKE_NAME_REPAIRS[entry.name]
            if repaired then entry.name = repaired end
        end
    end
end

local function RepairLegacyMojibakeProfileNames(profile)
    RepairLegacyMojibakeEntryNames(profile.entries)
    local shared = type(profile.sharedContent) == "table"
        and profile.sharedContent or nil
    RepairLegacyMojibakeEntryNames(shared and shared.entries)
    for _, content in pairs(type(profile.contentBySpec) == "table"
        and profile.contentBySpec or {}) do
        RepairLegacyMojibakeEntryNames(
            type(content) == "table" and content.entries or nil
        )
    end
end

local function GetDefaultVisibilityRule(groupId)
    local groups = DEFAULT_PROFILE.groups
        and DEFAULT_PROFILE.groups.items or nil
    local group = groups and groups[groupId]
    return group and group.visibility or nil
end

local function NormalizeVisibilityRule(rule, groupId)
    if YUI.Visibility and YUI.Visibility.MigrateGroup then return YUI.Visibility:MigrateGroup(rule) end
    if type(rule) ~= "table" then return nil end
    local normalized = {}
    if rule.combat == "in" or rule.combat == "out" then
        normalized.combat = rule.combat
    end
    if rule.mounted == "mounted" or rule.mounted == "unmounted" then
        normalized.mounted = rule.mounted
    end

    local sourceHide = type(rule.hide) == "table" and rule.hide or nil
    if sourceHide then
        local hide = {}
        local defaultRule = GetDefaultVisibilityRule(groupId)
        local defaultHide = type(defaultRule) == "table"
            and type(defaultRule.hide) == "table" and defaultRule.hide or {}
        local function CopyHideValue(field)
            local value = sourceHide[field]
            if value == true
                or (value == false and defaultHide[field] == true) then
                hide[field] = value
            end
        end
        CopyHideValue("noTarget")
        CopyHideValue("housing")
        CopyHideValue("skyriding")
        if next(hide) then normalized.hide = hide end
    end
    return next(normalized) and normalized or nil
end

local function NormalizeIconGroupLayout(layout, fallback)
    layout = type(layout) == "table" and layout or {}
    fallback = type(fallback) == "table"
        and fallback or DEFAULT_ICON_GROUP_LAYOUT

    layout.iconSize = ClampInteger(
        layout.iconSize,
        24,
        96,
        ClampInteger(fallback.iconSize, 24, 96, 42)
    )
    layout.columnSpacing = ClampInteger(
        layout.columnSpacing,
        0,
        32,
        ClampInteger(fallback.columnSpacing, 0, 32, 1)
    )
    layout.rowSpacing = ClampInteger(
        layout.rowSpacing,
        0,
        32,
        ClampInteger(fallback.rowSpacing, 0, 32, 1)
    )
    layout.spacing = nil
    layout.maxPerLine = ClampInteger(
        layout.maxPerLine,
        1,
        20,
        ClampInteger(fallback.maxPerLine, 1, 20, 6)
    )

    local wrapDirection = layout.wrapDirection
    if wrapDirection ~= "up" and wrapDirection ~= "down" then
        local legacyDirection = layout.direction
        if legacyDirection == "up" or legacyDirection == "down" then
            wrapDirection = legacyDirection
        else
            wrapDirection = fallback.wrapDirection
        end
    end
    if wrapDirection ~= "up" then wrapDirection = "down" end
    layout.wrapDirection = wrapDirection
    layout.direction = nil

    local rowDirection = layout.rowDirection
    if rowDirection ~= "left" and rowDirection ~= "right" then
        rowDirection = fallback.rowDirection
    end
    if rowDirection ~= "left" then rowDirection = "right" end
    layout.rowDirection = rowDirection

    local alignment = layout.alignment
    if alignment ~= "start" and alignment ~= "end"
        and alignment ~= "center" then
        alignment = fallback.alignment
    end
    if alignment ~= "start" and alignment ~= "end" then
        alignment = "center"
    end
    layout.alignment = alignment
    return layout
end

local BAR_ORIENTATIONS = {
    horizontal = true,
    vertical = true,
}

local BAR_ICON_POSITIONS = {
    left = true,
    right = true,
    top = true,
    bottom = true,
    center = true,
}

local function MigrateV20BarLayoutToOuterBox(layout)
    if type(layout) ~= "table" then return end
    local oldLength = ClampInteger(layout.width, 48, 640, 220)
    local oldThickness = ClampInteger(layout.height, 12, 160, 24)
    local orientation = BAR_ORIENTATIONS[layout.orientation]
        and layout.orientation or "horizontal"
    local iconPosition = BAR_ICON_POSITIONS[layout.iconPosition]
        and layout.iconPosition
        or (orientation == "vertical" and "top" or "left")
    if orientation == "vertical" then
        if iconPosition == "left" then
            iconPosition = "bottom"
        elseif iconPosition == "right" then
            iconPosition = "top"
        end
    end
    local iconGap = ClampInteger(layout.iconGap, 0, 32, 0)
    local trackWidth = orientation == "vertical"
        and oldThickness or oldLength
    local trackHeight = orientation == "vertical"
        and oldLength or oldThickness
    local outerWidth = trackWidth
    local outerHeight = trackHeight
    if iconPosition == "left" or iconPosition == "right" then
        outerWidth = outerWidth + oldThickness + iconGap
    elseif iconPosition == "top" or iconPosition == "bottom" then
        outerHeight = outerHeight + oldThickness + iconGap
    end
    layout.width = orientation == "vertical"
        and outerHeight or outerWidth
    layout.height = orientation == "vertical"
        and outerWidth or outerHeight
end

local function MigrateV21AxisSpacing(layout, fallbackSpacing)
    if type(layout) ~= "table" then return end
    local spacing = ClampInteger(
        layout.spacing,
        0,
        32,
        fallbackSpacing
    )
    if layout.columnSpacing == nil then layout.columnSpacing = spacing end
    if layout.rowSpacing == nil then layout.rowSpacing = spacing end
    layout.spacing = nil
end

local function MigrateV23ExplicitBarTextAnchors(profile)
    local groups = profile and profile.groups and profile.groups.items
    local layouts = profile and profile.layout and profile.layout.groups
    local styles = profile and profile.style and profile.style.groups
    if type(groups) ~= "table" then return end
    profile.style = type(profile.style) == "table" and profile.style or {}
    profile.style.groups = type(styles) == "table" and styles or {}
    styles = profile.style.groups
    for groupId, group in pairs(groups) do
        if type(group) == "table" and group.layout == "bars" then
            local layout = type(layouts) == "table" and layouts[groupId]
            local vertical = type(layout) == "table"
                and layout.orientation == "vertical"
            local style = type(styles[groupId]) == "table"
                and styles[groupId] or {}
            styles[groupId] = style
            if style.timeTextAnchor == nil
                or style.timeTextAnchor == "auto" then
                style.timeTextAnchor = vertical and "bar-bottom" or "bar-right"
            end
            if style.countTextAnchor == nil
                or style.countTextAnchor == "auto" then
                style.countTextAnchor = vertical
                    and "bar-outside-top" or "icon-bottom-right"
            end
            if style.nameTextAnchor == nil
                or style.nameTextAnchor == "auto" then
                style.nameTextAnchor = "bar-center"
            end
        end
    end
end

local WRAP_DIRECTIONS = {
    down = true,
    up = true,
}

local RING_DIRECTIONS = {
    outward = true,
    inward = true,
}

local RESOURCE_DIRECTIONS = {
    right = true,
    left = true,
    down = true,
    up = true,
}

local GROUP_ALIGNMENTS = {
    start = true,
    center = true,
    ["end"] = true,
}

local RESOURCE_FILL_DIRECTIONS = {
    forward = true,
    reverse = true,
}

local function NormalizeDurationGroupLayout(layout, layoutType, fallback)
    layout = type(layout) == "table" and layout or {}
    local isRing = layoutType == "rings"
    fallback = type(fallback) == "table" and fallback
        or (isRing and DEFAULT_RING_GROUP_LAYOUT
            or DEFAULT_BAR_GROUP_LAYOUT)

    local fallbackSpacing = isRing and 8 or 6
    layout.columnSpacing = ClampInteger(
        layout.columnSpacing,
        0,
        32,
        ClampInteger(fallback.columnSpacing, 0, 32, fallbackSpacing)
    )
    layout.rowSpacing = ClampInteger(
        layout.rowSpacing,
        0,
        32,
        ClampInteger(fallback.rowSpacing, 0, 32, fallbackSpacing)
    )
    layout.spacing = nil
    layout.maxPerLine = ClampInteger(
        layout.maxPerLine,
        1,
        20,
        ClampInteger(fallback.maxPerLine, 1, 20, 6)
    )
    layout.alignment = GROUP_ALIGNMENTS[layout.alignment]
        and layout.alignment
        or (GROUP_ALIGNMENTS[fallback.alignment]
            and fallback.alignment or "center")

    if isRing then
        layout.diameter = ClampInteger(
            layout.diameter,
            24,
            160,
            ClampInteger(fallback.diameter, 24, 160, 52)
        )
        layout.ringStep = ClampInteger(
            layout.ringStep,
            2,
            48,
            ClampInteger(fallback.ringStep, 2, 48, 8)
        )
        local legacyDirection = layout.direction
        layout.wrapDirection = WRAP_DIRECTIONS[layout.wrapDirection]
            and layout.wrapDirection
            or (WRAP_DIRECTIONS[legacyDirection]
                and legacyDirection
                or (WRAP_DIRECTIONS[fallback.wrapDirection]
                    and fallback.wrapDirection or "up"))
        layout.direction = RING_DIRECTIONS[legacyDirection]
            and legacyDirection or nil
        return layout
    end

    layout.width = ClampInteger(
        layout.width,
        48,
        832,
        ClampInteger(fallback.width, 48, 832, 244)
    )
    layout.height = ClampInteger(
        layout.height,
        12,
        352,
        ClampInteger(fallback.height, 12, 352, 24)
    )
    layout.orientation = BAR_ORIENTATIONS[layout.orientation]
        and layout.orientation
        or (BAR_ORIENTATIONS[fallback.orientation]
            and fallback.orientation or "horizontal")
    layout.fillDirection = RESOURCE_FILL_DIRECTIONS[layout.fillDirection]
        and layout.fillDirection or "forward"
    layout.iconPosition = BAR_ICON_POSITIONS[layout.iconPosition]
        and layout.iconPosition
        or (BAR_ICON_POSITIONS[fallback.iconPosition]
            and fallback.iconPosition
            or (layout.orientation == "vertical" and "top" or "left"))
    layout.iconGap = ClampInteger(
        layout.iconGap,
        0,
        32,
        ClampInteger(fallback.iconGap, 0, 32, 0)
    )
    local legacyDirection = layout.direction
    layout.wrapDirection = WRAP_DIRECTIONS[layout.wrapDirection]
        and layout.wrapDirection
        or (WRAP_DIRECTIONS[legacyDirection]
            and legacyDirection
            or (WRAP_DIRECTIONS[fallback.wrapDirection]
                and fallback.wrapDirection or "up"))
    layout.direction = nil
    return layout
end

local function NormalizeResourceGroupLayout(layout, fallback)
    layout = type(layout) == "table" and layout or {}
    fallback = type(fallback) == "table"
        and fallback or DEFAULT_RESOURCE_GROUP_LAYOUT
    local widthMode = layout.widthMode
    if widthMode ~= "auto" and widthMode ~= "fixed" then
        widthMode = fallback.widthMode
    end
    layout.widthMode = widthMode == "fixed" and "fixed" or "auto"
    layout.width = ClampInteger(
        layout.width,
        48,
        640,
        ClampInteger(fallback.width, 48, 640, 290)
    )
    layout.minWidth = ClampInteger(
        layout.minWidth,
        48,
        640,
        ClampInteger(fallback.minWidth, 48, 640, 150)
    )
    layout.height = ClampInteger(
        layout.height,
        8,
        160,
        ClampInteger(fallback.height, 8, 160, 16)
    )
    layout.spacing = ClampInteger(
        layout.spacing,
        -12,
        32,
        ClampInteger(fallback.spacing, -12, 32, -1)
    )
    layout.alignment = GROUP_ALIGNMENTS[layout.alignment]
        and layout.alignment
        or (GROUP_ALIGNMENTS[fallback.alignment]
            and fallback.alignment or "center")
    layout.direction = RESOURCE_DIRECTIONS[layout.direction]
        and layout.direction
        or (RESOURCE_DIRECTIONS[fallback.direction]
            and fallback.direction or "down")
    layout.orientation = "horizontal"
    layout.fillDirection =
        RESOURCE_FILL_DIRECTIONS[layout.fillDirection]
            and layout.fillDirection
            or (RESOURCE_FILL_DIRECTIONS[fallback.fillDirection]
                and fallback.fillDirection or "forward")
    if YUI.IsForever == true then
        layout.handPairMode = layout.handPairMode == "split" and "split" or "stacked"
        layout.mainHandFillDirection = layout.mainHandFillDirection == "reverse"
            and "reverse" or "forward"
        layout.offHandFillDirection = layout.offHandFillDirection == "reverse"
            and "reverse" or "forward"
    else
        layout.handPairMode, layout.mainHandFillDirection, layout.offHandFillDirection = nil, nil, nil
    end
    return layout
end

local GROUP_PLACEMENT_POINTS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local function NormalizeBasicGroupPlacement(value)
    if type(value) ~= "table" then return nil end
    local sourceAnchor = type(value.anchor) == "table" and value.anchor or {}
    local point = GROUP_PLACEMENT_POINTS[sourceAnchor.point]
        and sourceAnchor.point or "CENTER"
    local relativePoint = GROUP_PLACEMENT_POINTS[sourceAnchor.relativePoint]
        and sourceAnchor.relativePoint or point
    local relative = type(sourceAnchor.relative) == "string"
        and sourceAnchor.relative ~= "" and sourceAnchor.relative or "UIParent"
    local sourceOffset = type(value.offset) == "table" and value.offset or {}
    return {
        version = 2,
        anchor = {
            point = point,
            relative = relative,
            relativePoint = relativePoint,
        },
        offset = {
            x = ClampInteger(sourceOffset.x, -2000, 2000, 0),
            y = ClampInteger(sourceOffset.y, -2000, 2000, 0),
        },
    }
end

local function NormalizeGroupPlacement(value)
    local placement = NormalizeBasicGroupPlacement(value)
    if not placement then return nil end
    local fallback = NormalizeBasicGroupPlacement(value.fallback)
    if fallback then placement.fallback = fallback end
    return placement
end

local GROUP_FRAME_PREFIX = "YUI_YHUD_Group_"

local function GetGroupFrameName(groupId)
    if groupId == YHUD.GROUP_IDS.TRINKETS then
        return "YUI_YHUD_TrinketGroup"
    end
    return GROUP_FRAME_PREFIX .. tostring(groupId):gsub("[^%w_]", "_")
end

local function IsYHUDGroupFrameName(name)
    return name == "YUI_YHUD_TrinketGroup"
        or (type(name) == "string"
            and name:sub(1, #GROUP_FRAME_PREFIX) == GROUP_FRAME_PREFIX)
end

local function NormalizeSafeGroupFallback(value, knownFrameNames)
    if type(value) ~= "table"
        or type(value.anchor) ~= "table"
        or type(value.offset) ~= "table" then
        return nil
    end
    local anchor = value.anchor
    if not GROUP_PLACEMENT_POINTS[anchor.point]
        or not GROUP_PLACEMENT_POINTS[anchor.relativePoint]
        or type(anchor.relative) ~= "string"
        or anchor.relative == ""
        or tonumber(value.offset.x) == nil
        or tonumber(value.offset.y) == nil then
        return nil
    end
    if IsYHUDGroupFrameName(anchor.relative)
        and knownFrameNames[anchor.relative] ~= true then
        return nil
    end
    return NormalizeBasicGroupPlacement(value)
end

local function RepairDanglingGroupAnchors(profile, options)
    options = type(options) == "table" and options or {}
    local groups = profile and profile.groups and profile.groups.items
    local placements = profile and profile.layout
        and profile.layout.placements
    if type(groups) ~= "table" or type(placements) ~= "table" then
        return true, { changed = false, repaired = 0 }
    end

    local removedGroupId = options.removedGroupId
    local targetOnly = options.targetOnly == true
    local removedFrameName = type(removedGroupId) == "string"
        and GetGroupFrameName(removedGroupId) or nil
    local knownFrameNames = {}
    for groupId in pairs(groups) do
        if groupId ~= removedGroupId then
            knownFrameNames[GetGroupFrameName(groupId)] = true
        end
    end

    local repairs = {}
    for groupId, placement in pairs(placements) do
        local anchor = type(placement) == "table" and placement.anchor
        local relative = type(anchor) == "table" and anchor.relative
        local dangling = IsYHUDGroupFrameName(relative)
            and knownFrameNames[relative] ~= true
            and (not targetOnly or relative == removedFrameName)
        if dangling then
            local fallback = NormalizeSafeGroupFallback(
                placement.fallback,
                knownFrameNames
            )
            if not fallback then
                return nil, "dangling-group-anchor-no-fallback", {
                    groupId = groupId,
                    relative = relative,
                }
            end
            repairs[#repairs + 1] = {
                groupId = groupId,
                placement = fallback,
            }
        end
    end

    for index = 1, #repairs do
        local repair = repairs[index]
        placements[repair.groupId] = repair.placement
    end
    return true, {
        changed = #repairs > 0,
        repaired = #repairs,
    }
end

function YHUD:RepairDanglingGroupAnchors(profile, options)
    return RepairDanglingGroupAnchors(
        self:GetCanonicalProfile(profile),
        options
    )
end

function YHUD:HasLegacyTrinketGroup(profile)
    return self.Client.id == "forever" and type(profile) == "table"
        and type(profile.groups) == "table"
        and type(profile.groups.items) == "table"
        and profile.groups.items[self.GROUP_IDS.TRINKETS] ~= nil
end

-- Cold migration only. Compact documents must be decoded by ConfigSets first.
function YHUD:RetireLegacyTrinketGroup(profile)
    if not self:HasLegacyTrinketGroup(profile) then return profile end
    if profile.specDocuments or profile.contentBySpecPack then
        return nil, "trinket-migration-requires-expanded-content"
    end
    profile = CopyValue(profile)
    local retired = self.GROUP_IDS.TRINKETS
    local repaired, code, detail = RepairDanglingGroupAnchors(profile, {
        removedGroupId = retired, targetOnly = true,
    })
    if not repaired then return nil, code, detail end
    local candidate = profile.groups.items["group:user:1"]
    local target = type(candidate) == "table"
        and (candidate.layout == "icons" or candidate.layout == "rings")
        and "group:user:1" or self.GROUP_IDS.IMPORTANT
    local function MergeMembers(root)
        if type(root) ~= "table" or type(root[retired]) ~= "table" then return end
        local destination = type(root[target]) == "table" and root[target] or {}
        local seen = {}
        for _, id in ipairs(destination) do seen[id] = true end
        for _, id in ipairs(root[retired]) do
            if not seen[id] then destination[#destination + 1] = id; seen[id] = true end
        end
        root[target], root[retired] = destination, nil
    end
    local function MoveContent(content)
        if type(content) ~= "table" then return end
        local members = content.groupMembers
        if type(members) == "table" and type(members[retired]) == "table"
            and members[retired].after then
            members[target] = members[target] or { before = {}, after = {} }
            for _, side in ipairs({ "before", "after" }) do
                local lists = { [target] = members[target][side], [retired] = members[retired][side] }
                MergeMembers(lists)
                members[target][side] = lists[target] or {}
            end
            members[retired] = nil
        else
            MergeMembers(members)
        end
        for _, monitor in pairs(content.monitors or {}) do
            if monitor.groupId == retired then monitor.groupId = target end
        end
        for index, id in ipairs(type(members) == "table" and members[target] or {}) do
            local monitor = content.monitors and content.monitors[id]
            if monitor then monitor.order = index end
        end
    end
    MoveContent(profile.sharedContent)
    MoveContent(profile)
    for _, content in pairs(profile.contentBySpec or {}) do MoveContent(content) end
    profile.defaultPresetOverridesBySpec = profile.defaultPresetOverridesBySpec or {}
    for specKey, content in pairs(profile.contentBySpec or {}) do
        local overrides = profile.defaultPresetOverridesBySpec[specKey] or {}
        local tombstones = profile.defaultPresetTombstonesBySpec
            and profile.defaultPresetTombstonesBySpec[specKey] or {}
        for _, key in ipairs({ "slot:13", "slot:14" }) do
            local present = false
            for _, monitor in pairs(content.monitors or {}) do
                if monitor.entryKey == key then present = true; break end
            end
            if not present and tombstones[key] ~= true
                and (not overrides[key] or not overrides[key].groupId) then
                overrides[key] = overrides[key] or {}
                overrides[key].groupId = target
            end
        end
        profile.defaultPresetOverridesBySpec[specKey] = overrides
    end
    for _, overrides in pairs(profile.defaultPresetOverridesBySpec or {}) do
        for _, override in pairs(overrides) do
            if override.groupId == retired then override.groupId = target end
        end
    end
    for _, overrides in pairs(profile.officialOverridesBySpec or {}) do
        MergeMembers(overrides.groups)
        for _, override in pairs(overrides.monitors or {}) do
            if override.groupId == retired then override.groupId = target end
        end
    end
    profile.groups.items[retired] = nil
    for index = #(profile.groups.order or {}), 1, -1 do
        if profile.groups.order[index] == retired then table.remove(profile.groups.order, index) end
    end
    for _, root in pairs({ profile.layout and profile.layout.groups,
        profile.layout and profile.layout.placements, profile.style and profile.style.groups }) do
        if type(root) == "table" then root[retired] = nil end
    end
    return profile
end

-- Existing profiles intentionally omit editable default groups. Promote any
-- default placement that depended on one of those groups to its saved fallback
-- before the defaults are merged into an older profile.
do
    local repaired, code = RepairDanglingGroupAnchors(
        EXISTING_PROFILE_DEFAULTS
    )
    if not repaired then
        error("invalid YHUD existing-profile defaults: " .. tostring(code))
    end
end

local function NormalizeGroupPlacements(placements, groups)
    local normalized = {}
    if type(placements) ~= "table" or type(groups) ~= "table" then
        return normalized
    end
    for groupId in pairs(groups) do
        local placement = NormalizeGroupPlacement(placements[groupId])
        if placement then normalized[groupId] = placement end
    end
    return normalized
end

local ICON_SHAPES = {
    square = true,
    roundedSquare = true,
    flatSquare = true,
    flatRounded = true,
    wideSquare = true,
    wideRounded = true,
    circle = true,
}

local ICON_BORDERS = {
    none = true,
    thin = true,
    medium = true,
    thick = true,
    extraThick = true,
}

local RESOURCE_BORDER_THICKNESS = {
    none = 0,
    thin = 1,
    medium = 2,
    thick = 3,
    extraThick = 4,
}

local function NormalizeResourceBorder(value, fallback)
    value = RESOURCE_BORDER_THICKNESS[value] or value
    fallback = RESOURCE_BORDER_THICKNESS[fallback] or fallback
    return ClampInteger(value, 0, 12, ClampInteger(fallback, 0, 12, 1))
end

local COOLDOWN_TEXT_OUTLINES = {
    none = true,
    outline = true,
    thick = true,
    shadow = true,
    outlineShadow = true,
}

local RESOURCE_VALUE_FORMATS = {
    percent = true,
    percentSign = true,
    value = true,
    valuePercent = true,
    percentValue = true,
    valuePercentParen = true,
    valueMax = true,
    whole = true,
    duration = true,
}

local RESOURCE_DISPLAY_MODES = {
    bar = true,
    divided = true,
    cells = true,
    dots = true,
}

local RESOURCE_VISIBILITY_MODES = {
    always = true,
    nonzero = true,
    nonzeroOrCombat = true,
}

local DEFAULT_RESOURCE_LOW_COLOR = {
    r = 0.90,
    g = 0.20,
    b = 0.20,
    a = 1,
}

local DEFAULT_RESOURCE_HIGH_COLOR = {
    r = 0.20,
    g = 0.85,
    b = 0.35,
    a = 1,
}

local DEFAULT_RUNE_COLORS = {
    blood = { r = 0.82, g = 0.12, b = 0.18, a = 1 },
    frost = { r = 0.20, g = 0.62, b = 0.95, a = 1 },
    unholy = { r = 0.18, g = 0.72, b = 0.28, a = 1 },
}

local RESOURCE_TEXT_POSITIONS = {
    start = true,
    center = true,
    ["end"] = true,
}

local TEXT_POSITIONS = {
    center = true,
    top = true,
    bottom = true,
    left = true,
    right = true,
    ["top-left"] = true,
    ["bottom-left"] = true,
    ["top-right"] = true,
    ["bottom-right"] = true,
}

local COOLDOWN_TEXT_POSITIONS = TEXT_POSITIONS
local NAME_TEXT_POSITIONS = TEXT_POSITIONS

local KEYBIND_TEXT_MODES = {
    off = true,
    auto = true,
    manual = true,
}

local function NormalizeKeybindOverrideText(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("[%z\1-\31\127]", "")
    local count = 0
    local last = 0
    for index = 1, #value do
        local byte = value:byte(index)
        if byte < 128 or byte >= 194 then
            count = count + 1
            if count > 16 then break end
        end
        last = index
    end
    return value:sub(1, last)
end

local function NormalizeKeybindOverrides(value)
    local result = {}
    if type(value) ~= "table" then return result end
    for spellID, text in pairs(value) do
        local numericID = tonumber(spellID)
        if numericID and numericID > 0 and numericID % 1 == 0 then
            text = NormalizeKeybindOverrideText(text)
            if text ~= nil then result[numericID] = text end
        end
    end
    return result
end

local BAR_TEXT_ANCHORS = {
    ["icon-top-left"] = true,
    ["icon-top"] = true,
    ["icon-top-right"] = true,
    ["icon-left"] = true,
    ["icon-center"] = true,
    ["icon-right"] = true,
    ["icon-bottom-left"] = true,
    ["icon-bottom"] = true,
    ["icon-bottom-right"] = true,
    ["bar-left"] = true,
    ["bar-center"] = true,
    ["bar-right"] = true,
    ["bar-top"] = true,
    ["bar-bottom"] = true,
    ["bar-top-left"] = true,
    ["bar-top-right"] = true,
    ["bar-bottom-left"] = true,
    ["bar-bottom-right"] = true,
    ["bar-outside-left"] = true,
    ["bar-outside-right"] = true,
    ["bar-outside-top"] = true,
    ["bar-outside-bottom"] = true,
}

local RING_PROGRESS_DIRECTIONS = {
    clockwise = true,
    counterclockwise = true,
}

local RING_START_POSITIONS = {
    top = true,
    right = true,
    bottom = true,
    left = true,
}

local RING_THICKNESS_VALUES = { 4, 8, 14, 22 }

local function NormalizeRingThickness(value, fallback)
    value = tonumber(value) or tonumber(fallback) or 8
    local best = RING_THICKNESS_VALUES[1]
    local distance = math.abs(value - best)
    for index = 2, #RING_THICKNESS_VALUES do
        local candidate = RING_THICKNESS_VALUES[index]
        local candidateDistance = math.abs(value - candidate)
        if candidateDistance < distance then
            best = candidate
            distance = candidateDistance
        end
    end
    return best
end

local function NormalizeChoice(value, choices, fallback)
    if choices[value] then return value end
    if choices[fallback] then return fallback end
    for choice in pairs(choices) do
        return choice
    end
end

local function NormalizeFontChoice(value, fallback)
    if type(value) == "string" and value ~= "" and #value <= 160 then
        return value
    end
    if type(fallback) == "string"
        and fallback ~= "" and #fallback <= 160 then
        return fallback
    end
    return "default"
end

local function NormalizeStatusBarTexture(value, fallback)
    if type(value) == "string" and value ~= "" and #value <= 160 then
        return value
    end
    if type(fallback) == "string"
        and fallback ~= "" and #fallback <= 160 then
        return fallback
    end
    return "yui-g1"
end

local function ClampUnit(value, fallback)
    value = tonumber(value)
    if not value then value = tonumber(fallback) or 1 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function NormalizeColor(value, fallback)
    value = type(value) == "table" and value or {}
    fallback = type(fallback) == "table" and fallback
        or { r = 1, g = 1, b = 1, a = 1 }
    return {
        r = ClampUnit(value.r or value[1], fallback.r or fallback[1]),
        g = ClampUnit(value.g or value[2], fallback.g or fallback[2]),
        b = ClampUnit(value.b or value[3], fallback.b or fallback[3]),
        a = ClampUnit(value.a or value[4], fallback.a or fallback[4]),
    }
end

function YHUD:NormalizeMonitorAppearanceOverride(value)
    if type(value) ~= "table" then return nil end
    local result = {}
    if type(value.fillColor) == "table" then
        result.fillColor = NormalizeColor(value.fillColor)
    end
    if type(value.trackColor) == "table" then
        result.trackColor = NormalizeColor(value.trackColor)
    end
    if type(value.stackThresholds) == "table" then
        result.stackThresholds = self:NormalizeBarStackThresholds(value.stackThresholds)
    end
    if value.cooldownSwipeMode == "disabled"
        or value.cooldownSwipeMode == "forward"
        or value.cooldownSwipeMode == "reverse" then
        result.cooldownSwipeMode = value.cooldownSwipeMode
    end
    return next(result) and result or nil
end

function YHUD:ResolveMonitorCooldownSwipe(
    cooldownSwipeMode,
    groupEnabled,
    defaultReverse
)
    if cooldownSwipeMode == "disabled" then
        return false, defaultReverse == true
    end
    if cooldownSwipeMode == "forward" then return true, false end
    if cooldownSwipeMode == "reverse" then return true, true end
    return groupEnabled ~= false, defaultReverse == true
end

local MONITOR_GLOW_STYLES = {
    none = true,
    pixel = true,
    soft = true,
    button = true,
    autocast = true,
    proc = true,
    pulse = true,
}

local MONITOR_GLOW_CONDITIONS = {
    ["self-ready"] = true,
    ["self-cooldown"] = true,
    ["aura-present"] = true,
    ["aura-missing"] = true,
    ["condition-met"] = true,
}

local MONITOR_SOUND_CONDITIONS = {
    ["self-ready"] = true,
    ["self-cooldown"] = true,
    ["aura-present"] = true,
    ["aura-missing"] = true,
    ["condition-met"] = true,
    ["timer-ended"] = true,
}

local function ClampNumber(value, minimum, maximum, fallback)
    value = tonumber(value)
    if value == nil then value = tonumber(fallback) or minimum end
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function NormalizeSkyridingStyleSettings(styleId, settings)
    settings = type(settings) == "table" and settings or {}
    local fallback = DEFAULT_SKYRIDING_STYLE_SETTINGS[styleId]
        or DEFAULT_SKYRIDING_STYLE_SETTINGS.horizon
    local normalized = {
        width = ClampInteger(settings.width, 180, 720, fallback.width),
        speedHeight = ClampInteger(
            settings.speedHeight,
            8,
            40,
            fallback.speedHeight
        ),
        rowGap = ClampInteger(settings.rowGap, 0, 16, fallback.rowGap),
        pipGap = ClampInteger(settings.pipGap, 0, 12, fallback.pipGap),
        vigorColor = NormalizeColor(settings.vigorColor, fallback.vigorColor),
        secondWindColor = NormalizeColor(
            settings.secondWindColor,
            fallback.secondWindColor
        ),
        speedFont = NormalizeFontChoice(
            settings.speedFont,
            fallback.speedFont
        ),
        speedFontSize = ClampInteger(
            settings.speedFontSize,
            8,
            32,
            fallback.speedFontSize
        ),
    }
    if styleId == "halo" then
        normalized.vigorHeight = ClampInteger(
            settings.vigorHeight,
            4,
            28,
            fallback.vigorHeight
        )
        normalized.secondWindHeight = ClampInteger(
            settings.secondWindHeight,
            4,
            28,
            fallback.secondWindHeight
        )
    else
        normalized.resourceHeight = ClampInteger(
            settings.resourceHeight,
            4,
            28,
            fallback.resourceHeight
        )
        normalized.iconSize = ClampInteger(
            settings.iconSize,
            28,
            96,
            fallback.iconSize
        )
        local ringThickness = tonumber(settings.ringThickness)
            or fallback.ringThickness
        if ringThickness >= 11 then
            normalized.ringThickness = 14
        elseif ringThickness >= 6 then
            normalized.ringThickness = 8
        else
            normalized.ringThickness = 4
        end
    end
    return normalized
end

local function NormalizeSkyridingSettings(settings)
    settings = type(settings) == "table" and settings or {}
    local sourceStyles = type(settings.styles) == "table"
        and settings.styles or {}
    return {
        enabled = settings.enabled == true,
        style = "halo",
        styles = {
            horizon = NormalizeSkyridingStyleSettings(
                "horizon",
                sourceStyles.horizon
            ),
            halo = NormalizeSkyridingStyleSettings(
                "halo",
                sourceStyles.halo
            ),
        },
    }
end

local function NormalizeMonitorGlowColor(value, fallback)
    value = type(value) == "table" and value or {}
    fallback = type(fallback) == "table"
        and fallback or DEFAULT_MONITOR_GLOW_APPEARANCE.color
    return {
        ClampUnit(value.r or value[1], fallback.r or fallback[1]),
        ClampUnit(value.g or value[2], fallback.g or fallback[2]),
        ClampUnit(value.b or value[3], fallback.b or fallback[3]),
        ClampUnit(value.a or value[4], fallback.a or fallback[4]),
    }
end

local function NormalizeMonitorGlowAppearance(appearance)
    appearance = type(appearance) == "table" and appearance or {}
    local fallback = DEFAULT_MONITOR_GLOW_APPEARANCE
    return {
        style = NormalizeChoice(
            appearance.style,
            MONITOR_GLOW_STYLES,
            fallback.style
        ),
        size = ClampNumber(appearance.size, 0.25, 5, fallback.size),
        lines = ClampInteger(
            appearance.lines,
            1,
            20,
            fallback.lines
        ),
        thickness = ClampInteger(
            appearance.thickness,
            1,
            20,
            fallback.thickness
        ),
        speed = ClampNumber(appearance.speed, 0, 3, fallback.speed),
        alpha = ClampNumber(appearance.alpha, 0.1, 1, fallback.alpha),
        offsetX = ClampNumber(
            appearance.offsetX or appearance.xOffset,
            -1,
            1,
            fallback.offsetX
        ),
        offsetY = ClampNumber(
            appearance.offsetY or appearance.yOffset,
            -1,
            1,
            fallback.offsetY
        ),
        color = NormalizeMonitorGlowColor(
            appearance.color,
            fallback.color
        ),
    }
end

local function NormalizeMonitorGlow(glow)
    if type(glow) ~= "table" then return nil end
    local sourceRules = type(glow.rules) == "table" and glow.rules or nil
    if not sourceRules then
        if glow.enabled ~= true then return nil end
        sourceRules = {}
        local legacyConditions = type(glow.conditions) == "table"
            and glow.conditions or {}
        for index = 1, #legacyConditions do
            sourceRules[#sourceRules + 1] = {
                condition = legacyConditions[index],
                appearance = glow.appearance,
                combatOnly = glow.combatOnly == true or nil,
            }
        end
    end

    local rules = {}
    local seen = {}
    for index = 1, #sourceRules do
        local sourceRule = sourceRules[index]
        local condition = type(sourceRule) == "table"
            and sourceRule.condition or nil
        local conditionType = type(condition) == "table"
            and condition.type or condition
        if MONITOR_GLOW_CONDITIONS[conditionType]
            and not seen[conditionType] then
            seen[conditionType] = true
            local appearance = type(sourceRule.appearance) == "table"
                and sourceRule.appearance or DEFAULT_MONITOR_GLOW_APPEARANCE
            rules[#rules + 1] = {
                condition = {
                    type = conditionType,
                },
                appearance = NormalizeMonitorGlowAppearance(appearance),
                combatOnly = sourceRule.combatOnly == true and true or nil,
            }
        end
    end
    return #rules > 0 and { rules = rules } or nil
end

local function NormalizeSoundReference(value)
    if type(value) ~= "string" or value == "" or value == "None" then
        return nil
    end
    if YUI.Sound and YUI.Sound.NormalizeReference then
        return YUI.Sound:NormalizeReference(value)
    end
    if value:match("^voice:.+") or value:match("^system:.+")
        or value:match("^lsm:.+") or value:match("^custom:.+") then
        return value
    end
    return "voice:" .. value
end

local function NormalizeMonitorSound(sound)
    if type(sound) ~= "table" or type(sound.rules) ~= "table" then
        return nil
    end
    local rules = {}
    local seen = {}
    for index = 1, #sound.rules do
        local sourceRule = sound.rules[index]
        local condition = type(sourceRule) == "table"
            and sourceRule.condition or nil
        local conditionType = type(condition) == "table"
            and condition.type or condition
        if MONITOR_SOUND_CONDITIONS[conditionType]
            and not seen[conditionType] then
            seen[conditionType] = true
            local soundKey = NormalizeSoundReference(sourceRule.sound)
            rules[#rules + 1] = {
                condition = { type = conditionType },
                sound = soundKey,
            }
        end
    end
    return #rules > 0 and { rules = rules } or nil
end

local function NormalizeNativeProcGlow(value)
    value = type(value) == "table" and value or DEFAULT_NATIVE_PROC_GLOW
    local result = {
        mode = value.mode == "custom" and "custom" or "default",
    }
    if result.mode == "custom" then
        result.appearance = NormalizeMonitorGlowAppearance(value.appearance)
        if result.appearance.style == "none" then
            result.mode = "default"
            result.appearance = nil
        end
    end
    if value.combatOnly == true then result.combatOnly = true end
    return result
end

local function FilterMonitorGlowForEntry(glow, entry)
    if not (glow and type(entry) == "table") then return nil end
    local capabilities = type(YHUD.GetEntryMonitorConditionCapabilities)
            == "function"
        and YHUD:GetEntryMonitorConditionCapabilities(entry, "glow") or nil
    if not capabilities then return nil end
    local supportedConditions = {}
    for index = 1, #(capabilities.conditions or {}) do
        supportedConditions[capabilities.conditions[index]] = true
    end
    local rules = {}
    for index = 1, #(glow.rules or {}) do
        local rule = glow.rules[index]
        local conditionType = rule.condition and rule.condition.type
        if supportedConditions[conditionType] then
            rules[#rules + 1] = rule
        end
    end
    glow.rules = rules
    return #rules > 0 and glow or nil
end

local function FilterMonitorSoundForEntry(sound, entry)
    if not sound then return nil end
    if type(entry) ~= "table"
        or type(YHUD.GetEntryMonitorConditionCapabilities) ~= "function" then
        return sound
    end
    local capabilities = YHUD:GetEntryMonitorConditionCapabilities(
        entry,
        "sound"
    )
    -- Official cooldown entries are rebuilt from Blizzard's catalog before
    -- their saved overrides are materialized.  If that snapshot is not yet
    -- classifiable, keep the sparse rule instead of treating "unknown" as
    -- "unsupported" and erasing user data.
    if not capabilities then
        if entry.origin == "official-cdm" then return sound end
        return nil
    end
    local supportedConditions = {}
    for index = 1, #(capabilities.conditions or {}) do
        supportedConditions[capabilities.conditions[index]] = true
    end
    local rules = {}
    for index = 1, #(sound.rules or {}) do
        local rule = sound.rules[index]
        local conditionType = rule.condition and rule.condition.type
        if supportedConditions[conditionType] then
            rules[#rules + 1] = rule
        end
    end
    sound.rules = rules
    return #rules > 0 and sound or nil
end

local function NormalizeIconGroupStyle(style, fallback)
    style = type(style) == "table" and style or {}
    fallback = type(fallback) == "table"
        and fallback or DEFAULT_ICON_GROUP_STYLE

    local shape = style.iconShape
    if shape == "rounded" then shape = "roundedSquare" end
    local fallbackShape = fallback.iconShape
    if fallbackShape == "rounded" then fallbackShape = "roundedSquare" end
    style.iconShape = NormalizeChoice(
        shape,
        ICON_SHAPES,
        fallbackShape or DEFAULT_ICON_GROUP_STYLE.iconShape
    )
    style.iconBorder = NormalizeChoice(
        style.iconBorder,
        ICON_BORDERS,
        fallback.iconBorder or DEFAULT_ICON_GROUP_STYLE.iconBorder
    )
    style.iconZoom = ClampNumber(
        style.iconZoom,
        0,
        0.24,
        fallback.iconZoom or DEFAULT_ICON_GROUP_STYLE.iconZoom
    )
    style.iconBorderColor = NormalizeColor(
        style.iconBorderColor,
        fallback.iconBorderColor
            or DEFAULT_ICON_GROUP_STYLE.iconBorderColor
    )
    style.iconBackgroundColor = NormalizeColor(
        style.iconBackgroundColor,
        fallback.iconBackgroundColor
            or DEFAULT_ICON_GROUP_STYLE.iconBackgroundColor
    )
    style.iconShadow = NormalizeBoolean(
        style.iconShadow, NormalizeBoolean(fallback.iconShadow, true)
    )
    style.iconShadowColor = NormalizeColor(
        style.iconShadowColor,
        fallback.iconShadowColor or DEFAULT_ICON_GROUP_STYLE.iconShadowColor
    )
    style.cooldownSwipeColor = NormalizeColor(
        style.cooldownSwipeColor,
        fallback.cooldownSwipeColor
            or DEFAULT_ICON_GROUP_STYLE.cooldownSwipeColor
    )
    style.cooldownSwipe = NormalizeBoolean(
        style.cooldownSwipe,
        NormalizeBoolean(fallback.cooldownSwipe, true)
    )
    style.cooldownGCD = NormalizeBoolean(
        style.cooldownGCD,
        NormalizeBoolean(fallback.cooldownGCD, true)
    )
    style.cooldownBling = NormalizeBoolean(
        style.cooldownBling,
        NormalizeBoolean(fallback.cooldownBling, false)
    )
    style.cooldownText = NormalizeBoolean(
        style.cooldownText,
        NormalizeBoolean(fallback.cooldownText, true)
    )
    style.cooldownTextFont = NormalizeFontChoice(
        style.cooldownTextFont,
        fallback.cooldownTextFont
            or DEFAULT_ICON_GROUP_STYLE.cooldownTextFont
    )
    style.cooldownTextSize = ClampInteger(
        style.cooldownTextSize,
        8,
        32,
        ClampInteger(
            fallback.cooldownTextSize,
            8,
            32,
            DEFAULT_ICON_GROUP_STYLE.cooldownTextSize
        )
    )
    style.cooldownTextOutline = NormalizeChoice(
        style.cooldownTextOutline,
        COOLDOWN_TEXT_OUTLINES,
        fallback.cooldownTextOutline
            or DEFAULT_ICON_GROUP_STYLE.cooldownTextOutline
    )
    style.cooldownTextPosition = NormalizeChoice(
        style.cooldownTextPosition,
        COOLDOWN_TEXT_POSITIONS,
        fallback.cooldownTextPosition
            or DEFAULT_ICON_GROUP_STYLE.cooldownTextPosition
    )
    style.cooldownTextOffsetX = ClampNumber(
        style.cooldownTextOffsetX,
        -64,
        64,
        fallback.cooldownTextOffsetX or 0
    )
    style.cooldownTextOffsetY = ClampNumber(
        style.cooldownTextOffsetY,
        -64,
        64,
        fallback.cooldownTextOffsetY or 0
    )

    local color = type(style.cooldownTextColor) == "table"
        and style.cooldownTextColor or {}
    local fallbackColor = type(fallback.cooldownTextColor) == "table"
        and fallback.cooldownTextColor
        or DEFAULT_ICON_GROUP_STYLE.cooldownTextColor
    style.cooldownTextColor = {
        r = ClampUnit(color.r or color[1], fallbackColor.r or fallbackColor[1]),
        g = ClampUnit(color.g or color[2], fallbackColor.g or fallbackColor[2]),
        b = ClampUnit(color.b or color[3], fallbackColor.b or fallbackColor[3]),
        a = ClampUnit(color.a or color[4], fallbackColor.a or fallbackColor[4]),
    }
    style.keybindTextMode = NormalizeChoice(
        style.keybindTextMode,
        KEYBIND_TEXT_MODES,
        fallback.keybindTextMode or DEFAULT_ICON_GROUP_STYLE.keybindTextMode
    )
    style.keybindTextFont = NormalizeFontChoice(
        style.keybindTextFont,
        fallback.keybindTextFont or DEFAULT_ICON_GROUP_STYLE.keybindTextFont
    )
    style.keybindTextSize = ClampInteger(
        style.keybindTextSize,
        8,
        32,
        ClampInteger(fallback.keybindTextSize, 8, 32, 12)
    )
    style.keybindTextOutline = NormalizeChoice(
        style.keybindTextOutline,
        COOLDOWN_TEXT_OUTLINES,
        fallback.keybindTextOutline or "outlineShadow"
    )
    style.keybindTextPosition = NormalizeChoice(
        style.keybindTextPosition,
        COOLDOWN_TEXT_POSITIONS,
        fallback.keybindTextPosition or "top-right"
    )
    style.keybindTextOffsetX = ClampNumber(
        style.keybindTextOffsetX,
        -64,
        64,
        fallback.keybindTextOffsetX or 2
    )
    style.keybindTextOffsetY = ClampNumber(
        style.keybindTextOffsetY,
        -64,
        64,
        fallback.keybindTextOffsetY or 1
    )
    style.keybindTextColor = NormalizeColor(
        style.keybindTextColor,
        fallback.keybindTextColor or DEFAULT_ICON_GROUP_STYLE.keybindTextColor
    )
    style.keybindTextOverrides = NormalizeKeybindOverrides(
        style.keybindTextOverrides
    )
    style.countText = NormalizeBoolean(
        style.countText,
        NormalizeBoolean(fallback.countText, true)
    )
    style.countTextFont = NormalizeFontChoice(
        style.countTextFont,
        fallback.countTextFont or "default"
    )
    style.countTextSize = ClampInteger(
        style.countTextSize,
        8,
        32,
        ClampInteger(fallback.countTextSize, 8, 32, 12)
    )
    style.countTextOutline = NormalizeChoice(
        style.countTextOutline,
        COOLDOWN_TEXT_OUTLINES,
        fallback.countTextOutline or "outlineShadow"
    )
    style.countTextPosition = NormalizeChoice(
        style.countTextPosition,
        NAME_TEXT_POSITIONS,
        fallback.countTextPosition or "bottom"
    )
    style.countTextOffsetX = ClampNumber(
        style.countTextOffsetX,
        -64,
        64,
        fallback.countTextOffsetX or -2
    )
    style.countTextOffsetY = ClampNumber(
        style.countTextOffsetY,
        -64,
        64,
        fallback.countTextOffsetY or 2
    )
    style.countTextColor = NormalizeColor(
        style.countTextColor,
        fallback.countTextColor or DEFAULT_ICON_GROUP_STYLE.countTextColor
    )
    return style
end

local function NormalizeDurationGroupStyle(style, fallback)
    style = type(style) == "table" and style or {}
    fallback = type(fallback) == "table"
        and fallback or DEFAULT_DURATION_GROUP_STYLE
    style = NormalizeIconGroupStyle(style, fallback)
    style.smoothProgress = NormalizeBoolean(
        style.smoothProgress,
        NormalizeBoolean(fallback.smoothProgress, true)
    )
    style.nameText = NormalizeBoolean(
        style.nameText,
        NormalizeBoolean(fallback.nameText, true)
    )
    local nameTextFormat = type(style.nameTextFormat) == "string"
        and style.nameTextFormat or fallback.nameTextFormat
    if type(nameTextFormat) ~= "string"
        or nameTextFormat == ""
        or #nameTextFormat > 64 then
        nameTextFormat = "%n"
    end
    style.nameTextFormat = nameTextFormat
    style.nameTextFont = NormalizeFontChoice(
        style.nameTextFont,
        fallback.nameTextFont or "default"
    )
    style.nameTextSize = ClampInteger(
        style.nameTextSize,
        8,
        32,
        ClampInteger(fallback.nameTextSize, 8, 32, 12)
    )
    style.nameTextOutline = NormalizeChoice(
        style.nameTextOutline,
        COOLDOWN_TEXT_OUTLINES,
        fallback.nameTextOutline or "outlineShadow"
    )
    style.nameTextPosition = NormalizeChoice(
        style.nameTextPosition,
        NAME_TEXT_POSITIONS,
        fallback.nameTextPosition or "center"
    )
    style.nameTextAnchor = NormalizeChoice(
        style.nameTextAnchor,
        BAR_TEXT_ANCHORS,
        fallback.nameTextAnchor or "bar-center"
    )
    style.nameTextOffsetX = ClampNumber(
        style.nameTextOffsetX,
        -64,
        64,
        fallback.nameTextOffsetX or 0
    )
    style.nameTextOffsetY = ClampNumber(
        style.nameTextOffsetY,
        -64,
        64,
        fallback.nameTextOffsetY or 0
    )
    local nameColor = type(style.nameTextColor) == "table"
        and style.nameTextColor or {}
    local fallbackNameColor = type(fallback.nameTextColor) == "table"
        and fallback.nameTextColor
        or DEFAULT_DURATION_GROUP_STYLE.nameTextColor
    style.nameTextColor = {
        r = ClampUnit(
            nameColor.r or nameColor[1],
            fallbackNameColor.r or fallbackNameColor[1]
        ),
        g = ClampUnit(
            nameColor.g or nameColor[2],
            fallbackNameColor.g or fallbackNameColor[2]
        ),
        b = ClampUnit(
            nameColor.b or nameColor[3],
            fallbackNameColor.b or fallbackNameColor[3]
        ),
        a = ClampUnit(
            nameColor.a or nameColor[4],
            fallbackNameColor.a or fallbackNameColor[4]
        ),
    }
    local fill = type(style.fillColor) == "table"
        and style.fillColor or {}
    local fallbackFill = type(fallback.fillColor) == "table"
        and fallback.fillColor or DEFAULT_DURATION_GROUP_STYLE.fillColor
    style.fillColor = {
        r = ClampUnit(fill.r or fill[1], fallbackFill.r or fallbackFill[1]),
        g = ClampUnit(fill.g or fill[2], fallbackFill.g or fallbackFill[2]),
        b = ClampUnit(fill.b or fill[3], fallbackFill.b or fallbackFill[3]),
        a = ClampUnit(fill.a or fill[4], fallbackFill.a or fallbackFill[4]),
    }
    style.fillTexture = NormalizeStatusBarTexture(
        style.fillTexture,
        fallback.fillTexture or "yui-g1"
    )
    style.trackColor = NormalizeColor(
        style.trackColor,
        fallback.trackColor or DEFAULT_DURATION_GROUP_STYLE.trackColor
    )
    style.borderColor = NormalizeColor(
        style.borderColor,
        fallback.borderColor or DEFAULT_DURATION_GROUP_STYLE.borderColor
    )
    style.showIcon = NormalizeBoolean(
        style.showIcon,
        NormalizeBoolean(fallback.showIcon, true)
    )
    style.timeText = NormalizeBoolean(
        style.timeText,
        NormalizeBoolean(fallback.timeText, true)
    )
    style.timeTextFont = NormalizeFontChoice(
        style.timeTextFont,
        fallback.timeTextFont or "default"
    )
    style.timeTextSize = ClampInteger(
        style.timeTextSize,
        8,
        32,
        ClampInteger(fallback.timeTextSize, 8, 32, 12)
    )
    style.timeTextOutline = NormalizeChoice(
        style.timeTextOutline,
        COOLDOWN_TEXT_OUTLINES,
        fallback.timeTextOutline or "outlineShadow"
    )
    style.timeTextPosition = NormalizeChoice(
        style.timeTextPosition,
        NAME_TEXT_POSITIONS,
        fallback.timeTextPosition or "right"
    )
    style.timeTextAnchor = NormalizeChoice(
        style.timeTextAnchor,
        BAR_TEXT_ANCHORS,
        fallback.timeTextAnchor or "bar-right"
    )
    style.countTextAnchor = NormalizeChoice(
        style.countTextAnchor,
        BAR_TEXT_ANCHORS,
        fallback.countTextAnchor or "icon-bottom-right"
    )
    if style.showIcon == false then
        local nameAnchor = style.nameTextAnchor
        if type(nameAnchor) == "string"
            and nameAnchor:find("icon-", 1, true) == 1 then
            style.nameTextAnchor = "bar-" .. nameAnchor:sub(6)
        end
        local timeAnchor = style.timeTextAnchor
        if type(timeAnchor) == "string"
            and timeAnchor:find("icon-", 1, true) == 1 then
            style.timeTextAnchor = "bar-" .. timeAnchor:sub(6)
        end
        local countAnchor = style.countTextAnchor
        if type(countAnchor) == "string"
            and countAnchor:find("icon-", 1, true) == 1 then
            style.countTextAnchor = "bar-" .. countAnchor:sub(6)
        end
    end
    style.timeTextOffsetX = ClampNumber(
        style.timeTextOffsetX,
        -64,
        64,
        fallback.timeTextOffsetX or 0
    )
    style.timeTextOffsetY = ClampNumber(
        style.timeTextOffsetY,
        -64,
        64,
        fallback.timeTextOffsetY or 0
    )
    style.timeTextColor = NormalizeColor(
        style.timeTextColor,
        fallback.timeTextColor or DEFAULT_DURATION_GROUP_STYLE.timeTextColor
    )
    style.ringThickness = NormalizeRingThickness(
        style.ringThickness,
        fallback.ringThickness
    )
    style.ringDirection = NormalizeChoice(
        style.ringDirection,
        RING_PROGRESS_DIRECTIONS,
        fallback.ringDirection or "clockwise"
    )
    style.ringStart = NormalizeChoice(
        style.ringStart,
        RING_START_POSITIONS,
        fallback.ringStart or "top"
    )
    style.ringTrackColor = NormalizeColor(
        style.ringTrackColor,
        fallback.ringTrackColor
            or DEFAULT_DURATION_GROUP_STYLE.ringTrackColor
    )
    style.ringBorderColor = NormalizeColor(
        style.ringBorderColor,
        fallback.ringBorderColor
            or DEFAULT_DURATION_GROUP_STYLE.ringBorderColor
    )
    return style
end

local function NormalizeResourceGroupStyle(style, fallback)
    style = type(style) == "table" and style or {}
    fallback = type(fallback) == "table"
        and fallback or DEFAULT_RESOURCE_GROUP_STYLE
    style.smoothProgress = NormalizeBoolean(
        style.smoothProgress,
        NormalizeBoolean(fallback.smoothProgress, true)
    )
    style.border = NormalizeResourceBorder(style.border, fallback.border)
    style.borderColor = NormalizeColor(
        style.borderColor,
        fallback.borderColor or DEFAULT_RESOURCE_GROUP_STYLE.borderColor
    )
    style.fillTexture = NormalizeStatusBarTexture(
        style.fillTexture,
        fallback.fillTexture or "yui-g1"
    )
    style.fillColorMode = style.fillColorMode == "custom"
        and "custom" or "resource"
    style.fillColor = NormalizeColor(
        style.fillColor,
        fallback.fillColor or DEFAULT_RESOURCE_GROUP_STYLE.fillColor
    )
    style.nameText = nil
    style.valueText = nil
    style.textFont = NormalizeFontChoice(
        style.textFont,
        fallback.textFont or "default"
    )
    style.textSize = ClampInteger(
        style.textSize,
        8,
        32,
        ClampInteger(fallback.textSize, 8, 32, 12)
    )
    style.textOutline = NormalizeChoice(
        style.textOutline,
        COOLDOWN_TEXT_OUTLINES,
        fallback.textOutline or "outlineShadow"
    )

    local textColor = type(style.textColor) == "table"
        and style.textColor or {}
    local fallbackTextColor = type(fallback.textColor) == "table"
        and fallback.textColor or DEFAULT_RESOURCE_GROUP_STYLE.textColor
    style.textColor = {
        r = ClampUnit(
            textColor.r or textColor[1],
            fallbackTextColor.r or fallbackTextColor[1]
        ),
        g = ClampUnit(
            textColor.g or textColor[2],
            fallbackTextColor.g or fallbackTextColor[2]
        ),
        b = ClampUnit(
            textColor.b or textColor[3],
            fallbackTextColor.b or fallbackTextColor[3]
        ),
        a = ClampUnit(
            textColor.a or textColor[4],
            fallbackTextColor.a or fallbackTextColor[4]
        ),
    }

    local background = type(style.backgroundColor) == "table"
        and style.backgroundColor or {}
    local fallbackBackground = type(fallback.backgroundColor) == "table"
        and fallback.backgroundColor
        or DEFAULT_RESOURCE_GROUP_STYLE.backgroundColor
    style.backgroundColor = {
        r = ClampUnit(
            background.r or background[1],
            fallbackBackground.r or fallbackBackground[1]
        ),
        g = ClampUnit(
            background.g or background[2],
            fallbackBackground.g or fallbackBackground[2]
        ),
        b = ClampUnit(
            background.b or background[3],
            fallbackBackground.b or fallbackBackground[3]
        ),
        a = ClampUnit(
            background.a or background[4],
            fallbackBackground.a or fallbackBackground[4]
        ),
    }
    return style
end

local function NormalizeResourceTextOverride(override, fallback)
    if type(override) ~= "table" then return nil end
    fallback = type(fallback) == "table"
        and fallback or DEFAULT_RESOURCE_GROUP_STYLE
    return {
        textFont = NormalizeFontChoice(
            override.textFont,
            fallback.textFont or "default"
        ),
        textSize = ClampInteger(
            override.textSize,
            8,
            32,
            ClampInteger(fallback.textSize, 8, 32, 12)
        ),
        textOutline = NormalizeChoice(
            override.textOutline,
            COOLDOWN_TEXT_OUTLINES,
            fallback.textOutline or "outlineShadow"
        ),
        textColor = NormalizeColor(
            override.textColor,
            fallback.textColor or DEFAULT_RESOURCE_GROUP_STYLE.textColor
        ),
    }
end

local function NormalizeResourceAppearanceOverride(override, fallback)
    if type(override) ~= "table" then return nil end
    fallback = type(fallback) == "table"
        and fallback or DEFAULT_RESOURCE_GROUP_STYLE
    return {
        border = NormalizeResourceBorder(override.border, fallback.border),
        borderColor = NormalizeColor(
            override.borderColor,
            fallback.borderColor or DEFAULT_RESOURCE_GROUP_STYLE.borderColor
        ),
        fillTexture = NormalizeStatusBarTexture(
            override.fillTexture,
            fallback.fillTexture or "yui-g1"
        ),
        backgroundColor = NormalizeColor(
            override.backgroundColor,
            fallback.backgroundColor
                or DEFAULT_RESOURCE_GROUP_STYLE.backgroundColor
        ),
    }
end

function YHUD:IsResourceThresholdModeSelectable(definition)
    return definition and definition.valueKind == "continuous"
        and (definition.provider and definition.provider.kind or "unit-power") == "unit-power"
end

function YHUD:GetDefaultResourceThresholdMode(definition)
    return (definition and definition.valueKind == "discrete"
        or self:IsResourceThresholdModeSelectable(definition) and definition.id ~= "mana")
        and "value" or "percent"
end

local DEFAULT_RESOURCE_MODERATE_COLOR = { 0.95, 0.78, 0.22, 1 }
local DEFAULT_RESOURCE_SEVERE_COLOR = { 0.90, 0.28, 0.22, 1 }

local function NormalizeResourceThresholds(thresholds, definition, mode)
    thresholds = type(thresholds) == "table" and thresholds or {}
    definition = type(definition) == "table" and definition or {}
    local discrete = definition.valueKind == "discrete"
    local fallbackMax = ClampInteger(
        definition.segmentCountFallback or definition.previewMax,
        1,
        100,
        5
    )
    local maximum = mode == "value" and not discrete and 1000000000 or 100
    local defaultLow = discrete
        and math.max(1, math.floor((fallbackMax * 0.30) + 0.5))
        or 30
    local defaultHigh = discrete
        and math.max(defaultLow, math.ceil(fallbackMax * 0.70))
        or (definition.appearanceExtension == "severity" and 60 or 70)
    local low = type(thresholds.low) == "table" and thresholds.low or {}
    local high = type(thresholds.high) == "table" and thresholds.high or {}
    local lowValue = ClampInteger(low.value, 0, maximum, defaultLow)
    local highValue = ClampInteger(high.value, 0, maximum, defaultHigh)
    if highValue <= lowValue then
        if lowValue >= maximum then
            lowValue = math.max(0, maximum - 1)
            highValue = maximum
        else
            highValue = lowValue + 1
        end
    end
    return {
        low = {
            enabled = NormalizeBoolean(low.enabled, true),
            value = lowValue,
            color = NormalizeColor(low.color, definition.appearanceExtension == "severity"
                and DEFAULT_RESOURCE_MODERATE_COLOR or DEFAULT_RESOURCE_LOW_COLOR),
        },
        high = {
            enabled = NormalizeBoolean(high.enabled, true),
            value = highValue,
            color = NormalizeColor(high.color, definition.appearanceExtension == "severity"
                and DEFAULT_RESOURCE_SEVERE_COLOR or DEFAULT_RESOURCE_HIGH_COLOR),
        },
    }
end

function YHUD:NormalizeBarStackThresholds(value)
    value = type(value) == "table" and value or {}
    local result = NormalizeResourceThresholds(value, {
        valueKind = "discrete", previewMax = 10,
    }, "value")
    result.enabled = value.enabled == true
    return result
end

function YHUD:IsResourceInverseFillSupported(definition, setting)
    definition = type(definition) == "table" and definition or {}
    setting = type(setting) == "table" and setting or {}
    local kind = definition.provider and definition.provider.kind or "unit-power"
    return setting.displayMode ~= "cells" and setting.displayMode ~= "dots"
        and definition.appearanceExtension ~= "severity"
        and setting.thresholdColorEnabled ~= true
        and (kind == "unit-power" or kind == "spell-count"
            or kind == "simulated-stacks" or kind == "aura-duration"
            or kind == "absorb" or kind == "stagger")
end

local function NormalizeResourceText(setting, definition, legacyValueText, second)
    setting = type(setting) == "table" and setting or {}
    definition = type(definition) == "table" and definition or {}
    local discrete = definition.valueKind == "discrete"
    local defaultValueText = definition.defaultValueText ~= false
    if legacyValueText ~= nil and setting.valueText == nil then
        defaultValueText = legacyValueText == true
    end
    local valueFormat = setting.valueFormat
    local providerKind = definition.provider and definition.provider.kind
    if not RESOURCE_VALUE_FORMATS[valueFormat]
        or (valueFormat == "whole" and not discrete)
        or (valueFormat == "duration" and providerKind ~= "aura-duration" and providerKind ~= "absorb"
            and providerKind ~= "swing-timer") then
        valueFormat = definition.defaultValueFormat or (discrete and "value" or "percent")
    end
    if discrete and valueFormat ~= "valueMax" and valueFormat ~= "whole" then
        valueFormat = "value"
    elseif providerKind == "aura-duration" or providerKind == "swing-timer" then
        valueFormat = "duration"
    elseif definition.id == "stagger" or definition.id == "ignorePain" then
        valueFormat = providerKind == "absorb" and valueFormat == "duration" and "duration"
            or (valueFormat == "percent" and "percent" or "percentSign")
    elseif definition.id == "ironfur" then
        valueFormat = "value"
    end
    return {
        valueText = NormalizeBoolean(setting.valueText, not second and defaultValueText),
        valueFormat = valueFormat,
        textPosition = NormalizeChoice(setting.textPosition, RESOURCE_TEXT_POSITIONS, second and "end" or "center"),
        textOffsetX = ClampInteger(setting.textOffsetX, -64, 64, 0),
        textOffsetY = ClampInteger(setting.textOffsetY, -64, 64, 0),
    }
end

local function NormalizeResourceSetting(
    setting,
    definition,
    legacyValueText,
    legacyDisplayMode,
    initialBorderColor
)
    definition = type(definition) == "table" and definition or {}
    setting = type(setting) == "table" and setting
        or definition.defaultSettings or {}
    local discrete = definition.valueKind == "discrete"
    local thresholdMode = discrete and "value"
        or (YHUD:IsResourceThresholdModeSelectable(definition)
            and (setting.thresholdMode or YHUD:GetDefaultResourceThresholdMode(definition)) == "value"
            and "value" or "percent")
    local thresholds = NormalizeResourceThresholds(setting.thresholds, definition, thresholdMode)
    local thresholdValues = {}
    for _, mode in ipairs({ "percent", "value" }) do
        local saved = type(setting.thresholdValues) == "table" and setting.thresholdValues[mode]
        local normalized = NormalizeResourceThresholds({
            low = { value = type(saved) == "table" and saved.low or nil },
            high = { value = type(saved) == "table" and saved.high or nil },
        }, definition, mode)
        thresholdValues[mode] = { low = normalized.low.value, high = normalized.high.value }
    end
    thresholdValues[thresholdMode] = { low = thresholds.low.value, high = thresholds.high.value }
    local text = NormalizeResourceText(setting, definition, legacyValueText)
    local fillColor = setting.fillColor
    local oldAppearance = type(setting.appearanceOverride) == "table"
        and setting.appearanceOverride or nil
    if fillColor == nil and oldAppearance
        and oldAppearance.fillColorMode == "custom" then
        fillColor = oldAppearance.fillColor
    end
    local displayMode = setting.displayMode
    if not discrete then
        displayMode = "bar"
    elseif legacyDisplayMode == true then
        displayMode = "bar"
    elseif not RESOURCE_DISPLAY_MODES[displayMode] then
        displayMode = RESOURCE_DISPLAY_MODES[definition.defaultDisplayMode]
            and definition.defaultDisplayMode or "divided"
    end
    local dividerColorFallback = oldAppearance
        and oldAppearance.borderColor
        or initialBorderColor
        or DEFAULT_RESOURCE_GROUP_STYLE.borderColor
    local runeColors = type(setting.runeColors) == "table"
        and setting.runeColors or {}
    local heightOverride = type(setting.heightOverride) == "number"
        and ClampInteger(setting.heightOverride, 1, 160, nil) or nil
    local result = {
        visibilityMode = NormalizeChoice(
            setting.visibilityMode,
            RESOURCE_VISIBILITY_MODES,
            "always"
        ),
        valueText = text.valueText,
        valueFormat = text.valueFormat,
        abbreviateValues = NormalizeBoolean(setting.abbreviateValues, false),
        textPosition = text.textPosition,
        textOffsetX = text.textOffsetX,
        textOffsetY = text.textOffsetY,
        text2 = NormalizeResourceText(setting.text2, definition, nil, true),
        heightOverride = heightOverride,
        fillColor = NormalizeColor(
            fillColor,
            definition.color or DEFAULT_RESOURCE_GROUP_STYLE.fillColor
        ),
        runeColors = {
            blood = NormalizeColor(
                runeColors.blood,
                DEFAULT_RUNE_COLORS.blood
            ),
            frost = NormalizeColor(
                runeColors.frost,
                DEFAULT_RUNE_COLORS.frost
            ),
            unholy = NormalizeColor(
                runeColors.unholy,
                DEFAULT_RUNE_COLORS.unholy
            ),
        },
        runeCooldownTextMode = NormalizeChoice(setting.runeCooldownTextMode,
            { all = true, none = true, shortest = true }, "all"),
        runeCooldownTextSize = ClampInteger(
            setting.runeCooldownTextSize,
            8,
            32,
            12
        ),
        displayMode = displayMode,
        inverseFill = NormalizeBoolean(setting.inverseFill, definition.id == "remoteStrike"),
        segmentSpacing = ClampInteger(setting.segmentSpacing, -5, 32, 2),
        dividerThickness = ClampInteger(
            setting.dividerThickness,
            1,
            4,
            1
        ),
        dividerColor = NormalizeColor(
            setting.dividerColor,
            dividerColorFallback
        ),
        thresholdColorEnabled = NormalizeBoolean(
            setting.thresholdColorEnabled,
            definition.appearanceExtension == "severity"
        ),
        fillCeilingPercent = definition.appearanceExtension == "severity"
            and ClampInteger(setting.fillCeilingPercent, 1, 500, 100) or nil,
        thresholdMarkerEnabled = NormalizeBoolean(
            setting.thresholdMarkerEnabled,
            false
        ),
        thresholdMode = thresholdMode,
        thresholdValues = thresholdValues,
        thresholds = thresholds,
        thresholdMarkerColor = NormalizeColor(
            setting.thresholdMarkerColor,
            dividerColorFallback
        ),
        thresholdMarkerThickness = ClampInteger(
            setting.thresholdMarkerThickness,
            1,
            4,
            1
        ),
        textOverride = NormalizeResourceTextOverride(
            setting.textOverride,
            DEFAULT_RESOURCE_GROUP_STYLE
        ),
        appearanceOverride = NormalizeResourceAppearanceOverride(
            setting.appearanceOverride,
            DEFAULT_RESOURCE_GROUP_STYLE
        ),
    }
    return result
end

-- Only replace complete, recognizable shipped palettes; custom combinations survive.
local function MigrateResourceSeverityDefaults(setting, definition)
    if definition.appearanceExtension ~= "severity" then return end
    local low, high = setting.thresholds.low, setting.thresholds.high
    local function Matches(color, r, g, b)
        return color.r == r and color.g == g and color.b == b and color.a == 1
    end
    if low.value ~= 30 or not low.enabled or not high.enabled then return end
    local legacy = high.value == 70
        and Matches(low.color, 0.90, 0.20, 0.20)
        and Matches(high.color, 0.20, 0.85, 0.35)
    local previous = high.value == 60
        and Matches(low.color, 1, 0.85, 0.2)
        and Matches(high.color, 1, 0.2, 0.2)
    if not legacy and not previous then return end
    low.color = NormalizeColor(nil, DEFAULT_RESOURCE_MODERATE_COLOR)
    high.color = NormalizeColor(nil, DEFAULT_RESOURCE_SEVERE_COLOR)
    high.value = 60
    setting.thresholdValues.percent.high = 60
    if legacy then setting.thresholdColorEnabled = true end
end

local function ApplyResourceSettingDelta(target, delta)
    if type(target) ~= "table" or type(delta) ~= "table" then return target end
    for key, value in pairs(delta) do
        if key == "heightOverride" and value == false then
            target[key] = nil
        elseif type(value) == "table" and type(target[key]) == "table" then
            ApplyResourceSettingDelta(target[key], value)
        else
            target[key] = CopyValue(value)
        end
    end
    return target
end

local function GetResourceSettingStorageBaseline(
    resourceId,
    definition,
    initialBorderColor
)
    local baseline = CopyValue(RESOURCE_SETTINGS_STORAGE_BASELINE_V31[resourceId]) or {}
    baseline.thresholdMode = definition.valueKind == "discrete" and "value" or "percent"
    if definition.appearanceExtension == "severity" then
        baseline.thresholdColorEnabled = baseline.thresholdColorEnabled == true
        baseline.thresholds = baseline.thresholds or { high = { value = 70 } }
        baseline.thresholds.low = baseline.thresholds.low or {}
        baseline.thresholds.high = baseline.thresholds.high or { value = 70 }
        baseline.thresholds.low.color = baseline.thresholds.low.color or CopyValue(DEFAULT_RESOURCE_LOW_COLOR)
        baseline.thresholds.high.color = baseline.thresholds.high.color or CopyValue(DEFAULT_RESOURCE_HIGH_COLOR)
    end
    local old = RESOURCE_TEXT_STORAGE_DEFAULTS[resourceId]
    if baseline.valueText == nil then baseline.valueText = old == nil or old[1] end
    if baseline.valueFormat == nil then baseline.valueFormat = old and old[2] or "value" end
    return NormalizeResourceSetting(baseline, definition, nil, nil, initialBorderColor)
end

local function MaterializeResourceSettingDeltas(
    settings,
    resourceCatalog,
    initialBorderColor
)
    settings = type(settings) == "table" and settings or {}
    local materialized = {}
    local definitionIds = resourceCatalog:GetDefinitionIds()
    for index = 1, #definitionIds do
        local resourceId = definitionIds[index]
        local definition = resourceCatalog:GetDefinition(resourceId)
        local baseline = GetResourceSettingStorageBaseline(
            resourceId,
            definition,
            initialBorderColor
        )
        materialized[resourceId] = ApplyResourceSettingDelta(
            baseline,
            settings[resourceId]
        )
    end
    return materialized
end

function YHUD:T(key, fallback)
    local locale = YUI.Locale and YUI.Locale.Get and YUI.Locale:Get("YHUD") or nil
    local value = locale and locale[key]
    if type(value) == "string" and value ~= "" and value ~= key then
        return value
    end
    return fallback or key
end

local function IsStableSpecKey(value)
    return type(value) == "string"
        and value:match("^[A-Z][A-Z0-9_]*:[1-9][0-9]*$") ~= nil
end

-- 配置目录暂不可用时使用客户端固定清单；能够枚举时完全来自统一 Talent API，
-- 绝不从当前角色或 SavedVariables 反推。
local FALLBACK_SUPPORTED_SPEC_KEYS = YHUD.Client.fallbackSpecKeys or {}
local SPECIALIZATION_DATA_ROOTS = {
    "contentBySpec",
    "officialOverridesBySpec",
    "defaultPresetTombstonesBySpec",
    "defaultPresetOverridesBySpec",
}
local RESOURCE_SPECIALIZATION_ROOTS = { "bySpec", "orderBySpec", "formOverrides" }

local supportedSpecKeys
local supportedSpecKeySet

local function BuildSupportedSpecKeys()
    local keys, seen = {}, {}
    local unitAPI = YUI.API and YUI.API.Unit
    local talentAPI = YUI.API and YUI.API.Talent
    local classes = unitAPI and unitAPI.GetClassInfos
        and unitAPI.GetClassInfos() or {}
    local getClassSpecs = talentAPI and (talentAPI.GetClassConfigurationSpecializations or talentAPI.GetClassSpecializations)
    if getClassSpecs then
        for classIndex = 1, #classes do
            local classInfo = classes[classIndex]
            local classFile = type(classInfo) == "table"
                and classInfo.classFile or nil
            local specs = classFile
                and getClassSpecs(classFile) or {}
            for specIndex = 1, #specs do
                local specID = tonumber(specs[specIndex]
                    and specs[specIndex].specID)
                local specKey = specID and classFile
                    and (string.upper(classFile) .. ":" .. tostring(specID))
                    or nil
                if IsStableSpecKey(specKey) and not seen[specKey] then
                    seen[specKey] = true
                    keys[#keys + 1] = specKey
                end
            end
        end
    end
    if #keys == 0 then
        for index = 1, #FALLBACK_SUPPORTED_SPEC_KEYS do
            keys[index] = FALLBACK_SUPPORTED_SPEC_KEYS[index]
            seen[keys[index]] = true
        end
    else
        table.sort(keys)
    end
    return keys, seen
end

function YHUD:GetSupportedSpecKeys()
    if not supportedSpecKeys then
        supportedSpecKeys, supportedSpecKeySet = BuildSupportedSpecKeys()
    end
    return CopyValue(supportedSpecKeys)
end

function YHUD:IsSupportedSpecKey(specKey)
    if not supportedSpecKeySet then self:GetSupportedSpecKeys() end
    return supportedSpecKeySet[specKey] == true
end

local function RemoveUnsupportedSpecializationData(profile)
    for _, rootKey in ipairs(SPECIALIZATION_DATA_ROOTS) do
        local root = profile[rootKey]
        if type(root) == "table" then
            for specKey in pairs(root) do
                if not YHUD:IsSupportedSpecKey(specKey) then
                    root[specKey] = nil
                end
            end
        end
    end
end

-- 旧 Forever 职业键一次性展开到三系；已有三系内容优先，各系独立持有数据。
function YHUD:MigrateClientSpecializationMap(map)
    if type(map) ~= "table" then return false end
    local changed = false
    for legacy, keys in pairs(self.Client.legacySpecKeyMap or {}) do
        local value = map[legacy]
        if value ~= nil then
            for _, key in ipairs(keys) do
                if map[key] == nil then map[key] = CopyValue(value) end
            end
            map[legacy] = nil
            changed = true
        end
    end
    return changed
end

function YHUD:MigrateClientSpecializationKeys(profile)
    if type(profile) ~= "table" then return false end
    local changed = false
    for _, root in ipairs(SPECIALIZATION_DATA_ROOTS) do
        changed = self:MigrateClientSpecializationMap(profile[root]) or changed
    end
    local resources = profile.resources
    if type(resources) == "table" then
        for legacy, keys in pairs(self.Client.legacySpecKeyMap or {}) do
            local classFile, oldID = legacy:match("^([A-Z]+):(%d+)$")
            for _, root in ipairs(RESOURCE_SPECIALIZATION_ROOTS) do
                local map = type(resources[root]) == "table" and resources[root][classFile]
                if type(map) == "table" then
                    local value = map[oldID] or map[tonumber(oldID)]
                    if value ~= nil then
                        for _, key in ipairs(keys) do
                            local id = key:match(":(%d+)$")
                            if map[id] == nil and map[tonumber(id)] == nil then map[id] = CopyValue(value) end
                        end
                        map[oldID], map[tonumber(oldID)] = nil, nil
                        changed = true
                    end
                end
            end
        end
    end
    local documents = profile.specDocuments
    if type(documents) == "table" then
        changed = self:MigrateClientSpecializationMap(documents.blocks) or changed
        changed = self:MigrateClientSpecializationMap(documents.summaries) or changed
    end
    return changed
end

function YHUD:CopyValue(value)
    return CopyValue(value)
end

YHUD.DEFAULT_CONTENT_BASELINE_VERSION = 1
local DEFAULT_SLOT_PRESET_KEYS = { "slot:13", "slot:14" }

function YHUD:IsDefaultSlotPresetEntry(entry)
    if type(entry) ~= "table" then return false end
    local key = entry.presetKey or entry.entryKey
    return key == "slot:13" or key == "slot:14"
end

local function HasMonitorForEntry(content, entryKey)
    for _, monitor in pairs(content.monitors or {}) do
        if monitor.entryKey == entryKey then return true end
    end
    return false
end

local function NormalizeDefaultPresetState(profile, sourceVersion)
    local tombstones = type(profile.defaultPresetTombstonesBySpec) == "table"
        and profile.defaultPresetTombstonesBySpec or {}
    local overrides = type(profile.defaultPresetOverridesBySpec) == "table"
        and profile.defaultPresetOverridesBySpec or {}
    local baselineVersion = tonumber(profile.defaultContentBaselineVersion)
    for specKey, content in pairs(profile.contentBySpec or {}) do
        if IsStableSpecKey(specKey) and type(content) == "table" then
            local specTombstones = type(tombstones[specKey]) == "table"
                and tombstones[specKey] or {}
            if baselineVersion ~= YHUD.DEFAULT_CONTENT_BASELINE_VERSION then
                for index = 1, #DEFAULT_SLOT_PRESET_KEYS do
                    local entryKey = DEFAULT_SLOT_PRESET_KEYS[index]
                    if not HasMonitorForEntry(content, entryKey) then
                        specTombstones[entryKey] = true
                    end
                end
            end
            local normalizedTombstones = {}
            for index = 1, #DEFAULT_SLOT_PRESET_KEYS do
                local entryKey = DEFAULT_SLOT_PRESET_KEYS[index]
                if specTombstones[entryKey] == true then
                    normalizedTombstones[entryKey] = true
                end
            end
            tombstones[specKey] = next(normalizedTombstones)
                and normalizedTombstones or nil
            if type(overrides[specKey]) ~= "table" then
                overrides[specKey] = nil
            end
        end
    end
    profile.defaultContentBaselineVersion =
        YHUD.DEFAULT_CONTENT_BASELINE_VERSION
    profile.defaultPresetTombstonesBySpec = tombstones
    profile.defaultPresetOverridesBySpec = overrides
    return profile
end

function YHUD:MaterializeDefaultSlotPresets(profile, content, specKey)
    if type(profile) ~= "table" or type(content) ~= "table"
        or not IsStableSpecKey(specKey) then
        return content
    end
    local tombstones = profile.defaultPresetTombstonesBySpec
        and profile.defaultPresetTombstonesBySpec[specKey] or {}
    local overrides = profile.defaultPresetOverridesBySpec
        and profile.defaultPresetOverridesBySpec[specKey] or {}
    content.entries = type(content.entries) == "table" and content.entries or {}
    content.monitors = type(content.monitors) == "table" and content.monitors or {}
    content.groupMembers = type(content.groupMembers) == "table"
        and content.groupMembers or {}

    for index = 1, #DEFAULT_SLOT_PRESET_KEYS do
        local entryKey = DEFAULT_SLOT_PRESET_KEYS[index]
        if tombstones[entryKey] ~= true
            and not HasMonitorForEntry(content, entryKey) then
            local entry = CopyValue(DEFAULT_SHARED_CONTENT.entries[entryKey])
            local baselineMonitor = DEFAULT_SHARED_CONTENT.monitors[
                "monitor:" .. entryKey
            ]
            local override = type(overrides[entryKey]) == "table"
                and overrides[entryKey] or {}
            local groupId = type(override.groupId) == "string"
                and profile.groups.items[override.groupId]
                and override.groupId
                or type(baselineMonitor) == "table"
                    and type(baselineMonitor.groupId) == "string"
                    and profile.groups.items[baselineMonitor.groupId]
                    and baselineMonitor.groupId
                or (self.Client.id == "forever"
                    and self.GROUP_IDS.IMPORTANT or self.GROUP_IDS.TRINKETS)
            if entry and baselineMonitor
                and profile.groups.items[groupId] then
                entry.entryKey = entryKey
                entry.presetKey = entryKey
                entry.contentScope = self.CONTENT_SCOPE_SPEC
                entry.applicability = nil
                content.entries[entryKey] = entry

                local monitorId = "monitor:" .. entryKey
                local suffix = 2
                while content.monitors[monitorId] do
                    monitorId = "monitor:" .. entryKey .. ":"
                        .. tostring(suffix)
                    suffix = suffix + 1
                end
                local monitor = CopyValue(baselineMonitor)
                for key, value in pairs(type(override.monitor) == "table"
                    and override.monitor or {}) do
                    monitor[key] = CopyValue(value)
                end
                monitor.id = monitorId
                monitor.entryKey = entryKey
                monitor.sourceKey = entry.sourceKey
                monitor.contentScope = self.CONTENT_SCOPE_SPEC
                monitor.groupId = groupId
                monitor.enabled = monitor.enabled ~= false
                monitor.view = monitor.view or "icon"
                content.monitors[monitorId] = monitor
                local members = content.groupMembers[monitor.groupId]
                if type(members) ~= "table" then
                    members = {}
                    content.groupMembers[monitor.groupId] = members
                end
                local insertAt = tonumber(override.index)
                if not insertAt then
                    insertAt = math.min(index, #members + 1)
                end
                table.insert(members, insertAt, monitorId)
                local legacyIndex = tonumber(override.index)
                overrides[entryKey] = legacyIndex and {
                    index = legacyIndex,
                } or nil
            end
        end
    end
    if type(profile.defaultPresetOverridesBySpec) == "table"
        and next(overrides) == nil then
        profile.defaultPresetOverridesBySpec[specKey] = nil
    end
    return content
end

local function MergeContent(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then return target end
    target.initialization = type(target.initialization) == "table"
        and target.initialization or {}
    target.entries = type(target.entries) == "table" and target.entries or {}
    target.monitors = type(target.monitors) == "table" and target.monitors or {}
    target.groupMembers = type(target.groupMembers) == "table"
        and target.groupMembers or {}
    target.projectionOrder = type(target.projectionOrder) == "table"
        and target.projectionOrder or {}
    target.suppressedOfficial = type(target.suppressedOfficial) == "table"
        and target.suppressedOfficial or {}

    for key, value in pairs(type(source.initialization) == "table"
        and source.initialization or {}) do
        if target.initialization[key] == nil then
            target.initialization[key] = CopyValue(value)
        end
    end
    for key, value in pairs(type(source.entries) == "table"
        and source.entries or {}) do
        if target.entries[key] == nil then target.entries[key] = CopyValue(value) end
    end
    for key, value in pairs(type(source.monitors) == "table"
        and source.monitors or {}) do
        if target.monitors[key] == nil then
            target.monitors[key] = CopyValue(value)
        end
    end
    for groupId, values in pairs(type(source.groupMembers) == "table"
        and source.groupMembers or {}) do
        local members = target.groupMembers[groupId]
        if type(members) ~= "table" then
            target.groupMembers[groupId] = CopyValue(values)
        else
            local seen = {}
            for index = 1, #members do seen[members[index]] = true end
            for index = 1, #values do
                if not seen[values[index]] then
                    members[#members + 1] = values[index]
                    seen[values[index]] = true
                end
            end
        end
    end
    for groupId, values in pairs(type(source.projectionOrder) == "table"
        and source.projectionOrder or {}) do
        if type(target.projectionOrder[groupId]) ~= "table" then
            target.projectionOrder[groupId] = CopyValue(values)
        end
    end
    for key, value in pairs(type(source.suppressedOfficial) == "table"
        and source.suppressedOfficial or {}) do
        if value == true then target.suppressedOfficial[key] = true end
    end
    return target
end

local function ExtractLegacyContent(profile)
    local content = {
        initialization = CopyValue(profile.initialization or {}),
        entries = CopyValue(profile.entries or {}),
        monitors = CopyValue(profile.monitors or {}),
        groupMembers = CopyValue(profile.groupMembers or {}),
        suppressedOfficial = CopyValue(profile.suppressedOfficial or {}),
    }
    local groups = profile.groups and profile.groups.items or {}
    for groupId, group in pairs(groups) do
        if type(group) == "table" and type(group.monitors) == "table" then
            content.groupMembers[groupId] = CopyValue(group.monitors)
        end
    end
    return content
end

local function MergeBloodlustTimerEntries(profile, content)
    local preset = YHUD.BLOODLUST_PRESET
    if type(preset) ~= "table"
        or type(preset.entryKey) ~= "string"
        or type(preset.spellIDs) ~= "table" then
        return false
    end

    local spellIDs = {}
    for index = 1, #preset.spellIDs do
        local spellID = tonumber(preset.spellIDs[index])
        if spellID then spellIDs[spellID] = true end
    end
    local matchedEntries = {}
    for entryKey, entry in pairs(content.entries) do
        if entryKey == preset.entryKey
            or (type(entry) == "table"
                and entry.sourceType == YHUD.CAST_BUFF_TIMER_SOURCE_TYPE
                and spellIDs[tonumber(entry.spellId)] == true) then
            matchedEntries[entryKey] = true
        end
    end
    if not next(matchedEntries) then return false end

    local keeperMonitorId
    local keeperEntryKey
    local groupOrder = profile.groups and profile.groups.order or {}
    for groupIndex = 1, #groupOrder do
        local members = content.groupMembers[groupOrder[groupIndex]]
        local memberLists = type(members) == "table"
            and (type(members.before) == "table"
                    or type(members.after) == "table")
            and { members.before or {}, members.after or {} }
            or { type(members) == "table" and members or {} }
        for listIndex = 1, #memberLists do
            local memberList = memberLists[listIndex]
            for monitorIndex = 1, #memberList do
                local monitorId = memberList[monitorIndex]
                local monitor = content.monitors[monitorId]
                if monitor and matchedEntries[monitor.entryKey] then
                    if monitor.entryKey == preset.entryKey then
                        keeperMonitorId = monitorId
                        keeperEntryKey = monitor.entryKey
                        break
                    end
                    if not keeperMonitorId then
                        keeperMonitorId = monitorId
                        keeperEntryKey = monitor.entryKey
                    end
                end
            end
            if keeperEntryKey == preset.entryKey then break end
        end
        if keeperEntryKey == preset.entryKey then break end
    end
    if not keeperMonitorId then
        for monitorId, monitor in pairs(content.monitors) do
            if type(monitor) == "table"
                and matchedEntries[monitor.entryKey] then
                keeperMonitorId = monitorId
                keeperEntryKey = monitor.entryKey
                if monitor.entryKey == preset.entryKey then break end
            end
        end
    end

    local entry = CopyValue(
        content.entries[preset.entryKey]
            or (keeperEntryKey and content.entries[keeperEntryKey])
            or {}
    )
    entry.entryKey = preset.entryKey
    entry.sourceKey = preset.sourceKey
    entry.sourceType = preset.sourceType
        or YHUD.PLAYER_AURA_SOURCE_TYPE
        or "yhud.player-aura"
    entry.sourceIdentity = preset.sourceIdentity
    entry.semantic = "buff"
    entry.origin = "preset"
    entry.presetKey = preset.entryKey
    entry.crossSpecMaterialization = "immediate"
    entry.spellId = preset.displaySpellID
    entry.spellIds = CopyValue(preset.spellIDs)
    entry.triggerSpellIds = nil
    entry.durationSeconds = nil
    entry.nameKey = "designer.preset.bloodlust"
    entry.name = YHUD:T(
        "designer.preset.bloodlust",
        "嗜血/英勇"
    )
    content.entries[preset.entryKey] = entry

    for groupId, members in pairs(content.groupMembers) do
        local function Retain(memberList)
            local retained = {}
            for index = 1, #memberList do
                local monitorId = memberList[index]
                local monitor = content.monitors[monitorId]
                if monitor and matchedEntries[monitor.entryKey] then
                    if monitorId == keeperMonitorId then
                        monitor.entryKey = preset.entryKey
                        monitor.sourceKey = preset.sourceKey
                        retained[#retained + 1] = monitorId
                    else
                        content.monitors[monitorId] = nil
                    end
                else
                    retained[#retained + 1] = monitorId
                end
            end
            return retained
        end
        if type(members.before) == "table"
            or type(members.after) == "table" then
            content.groupMembers[groupId] = {
                before = Retain(members.before or {}),
                after = Retain(members.after or {}),
            }
        else
            content.groupMembers[groupId] =
                Retain(type(members) == "table" and members or {})
        end
    end
    for monitorId, monitor in pairs(content.monitors) do
        if matchedEntries[monitor.entryKey] then
            if monitorId == keeperMonitorId then
                monitor.entryKey = preset.entryKey
                monitor.sourceKey = preset.sourceKey
            else
                content.monitors[monitorId] = nil
            end
        end
    end
    for entryKey in pairs(matchedEntries) do
        if entryKey ~= preset.entryKey then
            content.entries[entryKey] = nil
        end
    end
    return true
end

local OFFICIAL_CDM_CATEGORY_RANK = {
    essential = 1,
    utility = 2,
    trackedBuff = 3,
    trackedBar = 4,
}

local function ParseOfficialCDMKey(value)
    if type(value) ~= "string" then return nil end
    local cooldownId = value:match("^cdm:(%d+)$")
    if cooldownId then
        cooldownId = tonumber(cooldownId)
        return cooldownId, nil, true, false
    end
    local category
    category, cooldownId = value:match("^cdm:([^:]+):(%d+)$")
    if cooldownId then
        return tonumber(cooldownId), category, false, false
    end
    cooldownId = value:match("^official:cdm:(%d+)$")
    if cooldownId then
        return tonumber(cooldownId), nil, false, true
    end
    category, cooldownId =
        value:match("^official:cdm:([^:]+):(%d+)$")
    if cooldownId then
        return tonumber(cooldownId), category, false, true
    end
    return nil
end

local function StableOfficialCDMEntryKey(value)
    local cooldownId = ParseOfficialCDMKey(value)
    if not cooldownId or cooldownId < 1 then return nil end
    return "cdm:" .. tostring(cooldownId), cooldownId
end

local function StableOfficialCDMRef(value)
    local stableKey = StableOfficialCDMEntryKey(value)
    if not stableKey then return nil end
    if value:sub(1, 9) == "official:" then
        return "official:" .. stableKey
    end
    return stableKey
end

local function ParseOfficialCDMMonitorId(value)
    if type(value) ~= "string" then return nil end
    local cooldownId = value:match("^monitor:cdm:(%d+)$")
    if cooldownId then return tonumber(cooldownId), true end
    local category
    category, cooldownId = value:match("^monitor:cdm:([^:]+):(%d+)$")
    if cooldownId then return tonumber(cooldownId), false, category end
    category, cooldownId =
        value:match("^monitor:official:cdm:([^:]+):(%d+)$")
    if cooldownId then return tonumber(cooldownId), false, category end
    cooldownId = value:match("^monitor:official:cdm:(%d+)$")
    if cooldownId then return tonumber(cooldownId), false end
    return nil
end

local function StableOfficialCDMMonitorId(value)
    local cooldownId = ParseOfficialCDMMonitorId(value)
    if not cooldownId or cooldownId < 1 then return nil end
    return "monitor:cdm:" .. tostring(cooldownId), cooldownId
end

local function CategoryRank(category)
    return OFFICIAL_CDM_CATEGORY_RANK[category] or 100
end

local function OrderedGroupIds(profile, groupMembers)
    local result = {}
    local seen = {}
    local order = profile.groups and profile.groups.order or {}
    for index = 1, #order do
        local groupId = order[index]
        if type(groupId) == "string" and not seen[groupId] then
            seen[groupId] = true
            result[#result + 1] = groupId
        end
    end
    local extras = {}
    for groupId in pairs(type(groupMembers) == "table" and groupMembers or {}) do
        if type(groupId) == "string" and not seen[groupId] then
            extras[#extras + 1] = groupId
        end
    end
    table.sort(extras)
    for index = 1, #extras do result[#result + 1] = extras[index] end
    return result
end

local function BuildMonitorPlacementRanks(profile, content)
    local result = {}
    local rank = 0
    local groupIds = OrderedGroupIds(profile, content.groupMembers)
    local function Visit(values)
        for index = 1, #(type(values) == "table" and values or {}) do
            local monitorId = values[index]
            if type(monitorId) == "string" and result[monitorId] == nil then
                rank = rank + 1
                result[monitorId] = rank
            end
        end
    end
    for index = 1, #groupIds do
        local members = content.groupMembers[groupIds[index]]
        if type(members) == "table"
            and (type(members.before) == "table"
                or type(members.after) == "table") then
            Visit(members.before)
            Visit(members.after)
        else
            Visit(members)
        end
    end
    return result
end

local function RewriteMonitorList(values, resolutions)
    local result = {}
    local seen = {}
    for index = 1, #(type(values) == "table" and values or {}) do
        local monitorId = values[index]
        local resolution = resolutions[monitorId]
        local nextId = monitorId
        local retain = true
        if resolution then
            nextId = resolution.monitorId
            retain = resolution.keep == true
        end
        if retain and type(nextId) == "string" and not seen[nextId] then
            seen[nextId] = true
            result[#result + 1] = nextId
        end
    end
    return result
end

local function RewriteProjectionList(values, resolutions)
    local result = {}
    local seen = {}
    for index = 1, #(type(values) == "table" and values or {}) do
        local value = values[index]
        local prefix, monitorId = type(value) == "string"
            and value:match("^(shared:)(.+)$") or nil, nil
        if prefix then
            monitorId = value:sub(#prefix + 1)
        else
            prefix, monitorId = type(value) == "string"
                and value:match("^(spec:)(.+)$") or nil, nil
            if prefix then monitorId = value:sub(#prefix + 1) end
        end
        if not monitorId then monitorId = value end
        local resolution = resolutions[monitorId]
        local nextValue = value
        local retain = true
        if resolution then
            retain = resolution.keep == true
            nextValue = (prefix or "") .. resolution.monitorId
        end
        if retain and type(nextValue) == "string" and not seen[nextValue] then
            seen[nextValue] = true
            result[#result + 1] = nextValue
        end
    end
    return result
end

local function RewriteKeyIndex(index, keyMap, resolutions)
    if type(index) ~= "table" then return index end
    local result = {}
    for key, value in pairs(index) do
        local nextKey = keyMap and keyMap[key] or nil
        local resolution = resolutions and resolutions[key] or nil
        if resolution then
            if resolution.keep then result[resolution.monitorId] = value end
        elseif not nextKey or nextKey == key then
            result[nextKey or key] = value
        end
    end
    local keys = {}
    for key in pairs(index) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    for keyIndex = 1, #keys do
        local key = keys[keyIndex]
        local nextKey = keyMap and keyMap[key] or nil
        if nextKey and result[nextKey] == nil then
            result[nextKey] = index[key]
        end
    end
    return result
end

local function MigrateOfficialCDMContent(profile, content)
    if type(content) ~= "table" then return {}, {} end
    content.entries = type(content.entries) == "table" and content.entries or {}
    content.monitors = type(content.monitors) == "table" and content.monitors or {}
    content.groupMembers = type(content.groupMembers) == "table"
        and content.groupMembers or {}

    local placementRanks = BuildMonitorPlacementRanks(profile, content)
    local candidatesByCooldown = {}
    local entryKeys = {}
    for entryKey in pairs(content.entries) do
        entryKeys[#entryKeys + 1] = entryKey
    end
    table.sort(entryKeys)
    for index = 1, #entryKeys do
        local entryKey = entryKeys[index]
        local cooldownId, category, stable = ParseOfficialCDMKey(entryKey)
        local entry = content.entries[entryKey]
        if cooldownId and cooldownId > 0 and type(entry) == "table" then
            local candidates = candidatesByCooldown[cooldownId]
            if not candidates then
                candidates = {}
                candidatesByCooldown[cooldownId] = candidates
            end
            candidates[#candidates + 1] = {
                entryKey = entryKey,
                entry = entry,
                category = category,
                stable = stable == true,
                monitorIds = {},
            }
        end
    end

    local candidateByEntry = {}
    for _, candidates in pairs(candidatesByCooldown) do
        for index = 1, #candidates do
            candidateByEntry[candidates[index].entryKey] = candidates[index]
        end
    end
    local monitorIds = {}
    for monitorId in pairs(content.monitors) do
        monitorIds[#monitorIds + 1] = monitorId
    end
    table.sort(monitorIds)
    for index = 1, #monitorIds do
        local monitorId = monitorIds[index]
        local monitor = content.monitors[monitorId]
        local candidate = type(monitor) == "table"
            and candidateByEntry[monitor.entryKey] or nil
        if candidate then
            candidate.monitorIds[#candidate.monitorIds + 1] = monitorId
        end
    end
    for _, candidates in pairs(candidatesByCooldown) do
        for index = 1, #candidates do
            table.sort(candidates[index].monitorIds, function(left, right)
                local leftRank = placementRanks[left] or math.huge
                local rightRank = placementRanks[right] or math.huge
                if leftRank ~= rightRank then return leftRank < rightRank end
                return left < right
            end)
        end
    end

    local entryKeyMap = {}
    local monitorResolutions = {}
    local cooldownIds = {}
    for cooldownId in pairs(candidatesByCooldown) do
        cooldownIds[#cooldownIds + 1] = cooldownId
    end
    table.sort(cooldownIds)
    for cooldownIndex = 1, #cooldownIds do
        local cooldownId = cooldownIds[cooldownIndex]
        local candidates = candidatesByCooldown[cooldownId]
        table.sort(candidates, function(left, right)
            if left.stable ~= right.stable then return left.stable end
            local leftMonitored = #left.monitorIds > 0
            local rightMonitored = #right.monitorIds > 0
            if leftMonitored ~= rightMonitored then return leftMonitored end
            if leftMonitored then
                local leftRank = placementRanks[left.monitorIds[1]] or math.huge
                local rightRank = placementRanks[right.monitorIds[1]] or math.huge
                if leftRank ~= rightRank then return leftRank < rightRank end
            end
            local leftCategory = CategoryRank(left.category)
            local rightCategory = CategoryRank(right.category)
            if leftCategory ~= rightCategory then
                return leftCategory < rightCategory
            end
            return left.entryKey < right.entryKey
        end)

        local winner = candidates[1]
        local stableEntryKey = "cdm:" .. tostring(cooldownId)
        local entry = winner.entry
        entry.entryKey = stableEntryKey
        entry.origin = "official-cdm"
        entry.cooldownId = cooldownId
        if entry.officialCategory == nil
            and OFFICIAL_CDM_CATEGORY_RANK[winner.category] then
            entry.officialCategory = winner.category
        end
        if entry.sourceCategory == nil and winner.category then
            entry.sourceCategory = winner.category
        end
        entry.displayCategory = entry.officialCategory
        local auraSource = entry.semantic == "buff"
            or entry.officialCategory == "trackedBuff"
            or entry.officialCategory == "trackedBar"
            or entry.sourceCategory == "trackedBuff"
            or entry.sourceCategory == "trackedBar"
            or entry.sourceCategory == "equipSlotTracked"
            or entry.sourceCategory == "specAgnosticTracked"
        if auraSource then
            entry.semantic = "buff"
            entry.sourceKey = "aura:cdm:" .. tostring(cooldownId)
        else
            entry.semantic = entry.semantic or "cooldown"
            entry.sourceKey = nil
        end

        local duplicateMonitorIds = {}
        local monitorCandidates = {}
        for candidateIndex = 1, #candidates do
            local candidate = candidates[candidateIndex]
            entryKeyMap[candidate.entryKey] = stableEntryKey
            for monitorIndex = 1, #candidate.monitorIds do
                local monitorId = candidate.monitorIds[monitorIndex]
                duplicateMonitorIds[monitorId] = true
                monitorCandidates[#monitorCandidates + 1] = {
                    monitorId = monitorId,
                    candidate = candidate,
                }
            end
        end
        table.sort(monitorCandidates, function(left, right)
            if left.candidate.stable ~= right.candidate.stable then
                return left.candidate.stable
            end
            local leftRank = placementRanks[left.monitorId] or math.huge
            local rightRank = placementRanks[right.monitorId] or math.huge
            if leftRank ~= rightRank then return leftRank < rightRank end
            local leftCategory = CategoryRank(left.candidate.category)
            local rightCategory = CategoryRank(right.candidate.category)
            if leftCategory ~= rightCategory then
                return leftCategory < rightCategory
            end
            return left.monitorId < right.monitorId
        end)

        if #monitorCandidates > 0 then
            local keeperId = monitorCandidates[1].monitorId
            local keeper = content.monitors[keeperId]
            local derivedCooldownId = ParseOfficialCDMMonitorId(keeperId)
            local nextMonitorId = derivedCooldownId == cooldownId
                and ("monitor:" .. stableEntryKey) or keeperId
            if content.monitors[nextMonitorId]
                and not duplicateMonitorIds[nextMonitorId] then
                nextMonitorId = keeperId
            end
            for monitorId in pairs(duplicateMonitorIds) do
                monitorResolutions[monitorId] = {
                    monitorId = nextMonitorId,
                    keep = monitorId == keeperId,
                }
                content.monitors[monitorId] = nil
            end
            keeper.id = nextMonitorId
            keeper.entryKey = stableEntryKey
            keeper.sourceKey = entry.sourceKey
            keeper.officialCategory = entry.officialCategory
            content.monitors[nextMonitorId] = keeper
        end

        for candidateIndex = 1, #candidates do
            content.entries[candidates[candidateIndex].entryKey] = nil
        end
        content.entries[stableEntryKey] = entry
    end

    for groupId, members in pairs(content.groupMembers) do
        if type(members) == "table"
            and (type(members.before) == "table"
                or type(members.after) == "table") then
            content.groupMembers[groupId] = {
                before = RewriteMonitorList(
                    members.before,
                    monitorResolutions
                ),
                after = RewriteMonitorList(
                    members.after,
                    monitorResolutions
                ),
            }
        else
            content.groupMembers[groupId] = RewriteMonitorList(
                members,
                monitorResolutions
            )
        end
    end
    if type(content.projectionOrder) == "table" then
        for groupId, values in pairs(content.projectionOrder) do
            content.projectionOrder[groupId] = RewriteProjectionList(
                values,
                monitorResolutions
            )
        end
    end

    local suppressed = {}
    for entryKey, hidden in pairs(type(content.suppressedOfficial) == "table"
        and content.suppressedOfficial or {}) do
        local stableEntryKey = StableOfficialCDMEntryKey(entryKey)
        if hidden == true then
            suppressed[stableEntryKey or entryKey] = true
        end
    end
    if content.suppressedOfficial ~= nil then
        content.suppressedOfficial = suppressed
    end
    content._yhudScopeByEntry = RewriteKeyIndex(
        content._yhudScopeByEntry,
        entryKeyMap
    )
    content._yhudScopeByMonitor = RewriteKeyIndex(
        content._yhudScopeByMonitor,
        nil,
        monitorResolutions
    )
    content._yhudLaneByMonitor = RewriteKeyIndex(
        content._yhudLaneByMonitor,
        nil,
        monitorResolutions
    )
    return entryKeyMap, monitorResolutions
end

local function MigrateOfficialCDMOverrides(profile)
    local overridesBySpec = type(profile.officialOverridesBySpec) == "table"
        and profile.officialOverridesBySpec or {}
    local groupOrder = OrderedGroupIds(
        profile,
        profile.groups and profile.groups.items or {}
    )
    for _, overrides in pairs(overridesBySpec) do
        if type(overrides) == "table" then
            local groups = type(overrides.groups) == "table"
                and overrides.groups or {}
            local normalizedGroups = {}
            local seenOfficialRefs = {}
            local referencedEntryKeys = {}
            local referencedEntryCount = 0
            for groupIndex = 1, #groupOrder do
                local groupId = groupOrder[groupIndex]
                local refs = groups[groupId]
                if type(refs) == "table" then
                    local normalized = {}
                    local seen = {}
                    for index = 1, #refs do
                        local ref = refs[index]
                        local stableRef = StableOfficialCDMRef(ref)
                        local nextRef = stableRef or ref
                        local customMonitorId = type(nextRef) == "string"
                            and nextRef:match("^custom:(monitor:.+)$") or nil
                        if customMonitorId then
                            local stableMonitorId =
                                StableOfficialCDMMonitorId(customMonitorId)
                            if stableMonitorId then
                                nextRef = "custom:" .. stableMonitorId
                            end
                        end
                        local official = type(nextRef) == "string"
                            and nextRef:sub(1, 9) == "official:"
                        if type(nextRef) == "string" and not seen[nextRef]
                            and (not official
                                or not seenOfficialRefs[nextRef]) then
                            seen[nextRef] = true
                            if official then
                                seenOfficialRefs[nextRef] = true
                                local originalEntryKey = type(ref) == "string"
                                    and ref:sub(10) or nil
                                if originalEntryKey
                                    and referencedEntryKeys[originalEntryKey]
                                        == nil then
                                    referencedEntryCount = referencedEntryCount + 1
                                    referencedEntryKeys[originalEntryKey] =
                                        referencedEntryCount
                                end
                            end
                            normalized[#normalized + 1] = nextRef
                        end
                    end
                    normalizedGroups[groupId] = normalized
                end
            end
            local extraGroupIds = {}
            local knownGroups = {}
            for index = 1, #groupOrder do knownGroups[groupOrder[index]] = true end
            for groupId in pairs(groups) do
                if not knownGroups[groupId] then extraGroupIds[#extraGroupIds + 1] = groupId end
            end
            table.sort(extraGroupIds)
            for index = 1, #extraGroupIds do
                local groupId = extraGroupIds[index]
                local refs = groups[groupId]
                local normalized = {}
                local seen = {}
                for refIndex = 1, #(type(refs) == "table" and refs or {}) do
                    local ref = refs[refIndex]
                    local nextRef = StableOfficialCDMRef(ref) or ref
                    if type(nextRef) == "string" and not seen[nextRef]
                        and not seenOfficialRefs[nextRef] then
                        seen[nextRef] = true
                        if nextRef:sub(1, 9) == "official:" then
                            seenOfficialRefs[nextRef] = true
                        end
                        normalized[#normalized + 1] = nextRef
                    end
                end
                normalizedGroups[groupId] = normalized
            end
            overrides.groups = next(normalizedGroups)
                and normalizedGroups or nil

            local monitorOverrides = type(overrides.monitors) == "table"
                and overrides.monitors or {}
            local candidatesByStableKey = {}
            for entryKey, value in pairs(monitorOverrides) do
                local stableEntryKey = StableOfficialCDMEntryKey(entryKey)
                if stableEntryKey then
                    local candidates = candidatesByStableKey[stableEntryKey]
                    if not candidates then
                        candidates = {}
                        candidatesByStableKey[stableEntryKey] = candidates
                    end
                    local _, category, stable = ParseOfficialCDMKey(entryKey)
                    candidates[#candidates + 1] = {
                        entryKey = entryKey,
                        value = value,
                        category = category,
                        stable = stable == true,
                        referenced = referencedEntryKeys[entryKey],
                    }
                end
            end
            local normalizedMonitors = {}
            for stableEntryKey, candidates in pairs(candidatesByStableKey) do
                table.sort(candidates, function(left, right)
                    if left.stable ~= right.stable then return left.stable end
                    local leftReferenced = left.referenced ~= nil
                    local rightReferenced = right.referenced ~= nil
                    if leftReferenced ~= rightReferenced then
                        return leftReferenced
                    end
                    if leftReferenced and left.referenced ~= right.referenced then
                        return left.referenced < right.referenced
                    end
                    local leftRank = CategoryRank(left.category)
                    local rightRank = CategoryRank(right.category)
                    if leftRank ~= rightRank then return leftRank < rightRank end
                    return left.entryKey < right.entryKey
                end)
                normalizedMonitors[stableEntryKey] = candidates[1].value
            end
            for entryKey, value in pairs(monitorOverrides) do
                if not StableOfficialCDMEntryKey(entryKey) then
                    normalizedMonitors[entryKey] = value
                end
            end
            overrides.monitors = next(normalizedMonitors)
                and normalizedMonitors or nil

            local normalizedSuppressed = {}
            for entryKey, hidden in pairs(type(overrides.suppressed) == "table"
                and overrides.suppressed or {}) do
                if hidden == true then
                    local stableEntryKey =
                        StableOfficialCDMEntryKey(entryKey)
                    normalizedSuppressed[stableEntryKey or entryKey] = true
                end
            end
            overrides.suppressed = next(normalizedSuppressed)
                and normalizedSuppressed or nil
        end
    end
    profile.officialOverridesBySpec = overridesBySpec
end

local function MigrateOfficialCDMProfile(profile)
    local entryKeyMap = {}
    local monitorResolutions = {}
    local function Migrate(content)
        local contentEntryMap, contentMonitorResolutions =
            MigrateOfficialCDMContent(profile, content)
        for key, value in pairs(contentEntryMap) do entryKeyMap[key] = value end
        for key, value in pairs(contentMonitorResolutions) do
            monitorResolutions[key] = value
        end
    end
    Migrate(profile.sharedContent)
    for _, content in pairs(type(profile.contentBySpec) == "table"
        and profile.contentBySpec or {}) do
        Migrate(content)
    end
    Migrate(profile.pendingLegacyContent)
    MigrateOfficialCDMOverrides(profile)
    profile._yhudScopeByEntry = RewriteKeyIndex(
        profile._yhudScopeByEntry,
        entryKeyMap
    )
    profile._yhudScopeByMonitor = RewriteKeyIndex(
        profile._yhudScopeByMonitor,
        nil,
        monitorResolutions
    )
    profile._yhudLaneByMonitor = RewriteKeyIndex(
        profile._yhudLaneByMonitor,
        nil,
        monitorResolutions
    )
end

local EnsureMigratedCooldownGroup

local function NormalizeContent(profile, content, scope, specKey)
    content = type(content) == "table" and content or {}
    scope = scope == YHUD.CONTENT_SCOPE_SHARED
        and YHUD.CONTENT_SCOPE_SHARED or YHUD.CONTENT_SCOPE_SPEC
    local shared = scope == YHUD.CONTENT_SCOPE_SHARED
    if shared then
        content.initialization = nil
        content.suppressedOfficial = nil
        content.projectionOrder = nil
    else
        content.initialization = type(content.initialization) == "table"
            and content.initialization or {}
        content.initialization.nativeSeedVersion =
            tonumber(content.initialization.nativeSeedVersion) or 0
        content.suppressedOfficial =
            type(content.suppressedOfficial) == "table"
                and content.suppressedOfficial or {}
    end
    local policyRevision = tonumber(profile.contentPolicyRevision)
        or tonumber(content.initialization
            and content.initialization.contentPolicyRevision)
        or 1
    content.entries = type(content.entries) == "table" and content.entries or {}
    content.monitors = type(content.monitors) == "table" and content.monitors or {}
    content.groupMembers = type(content.groupMembers) == "table"
        and content.groupMembers or {}
    local retired = YHUD.Client and YHUD.Client.retiredPresetKeys
    if retired then
        for entryKey, entry in pairs(content.entries) do
            if type(entry) == "table" and entry.origin == "preset"
                and (retired[entry.presetKey or entry.presetId or entryKey]
                    or retired[entry.sourceIdentity]
                    or (entry.bundleKind == "defensive"
                        and retired["bundle:defensive"])) then
                content.entries[entryKey] = nil
            end
        end
    end
    if policyRevision < 3 then
        MergeBloodlustTimerEntries(profile, content)
    end

    local groups = profile.groups and profile.groups.items or {}
    local listed = {}
    local entryMonitors = {}
    local function AppendMember(members, monitorId, groupId)
        local monitor = content.monitors[monitorId]
        local entry = monitor and content.entries[monitor.entryKey]
        if type(monitorId) ~= "string"
            or not monitor or not entry
            or listed[monitorId]
            or entryMonitors[monitor.entryKey] then
            return false
        end
        members[#members + 1] = monitorId
        listed[monitorId] = true
        entryMonitors[monitor.entryKey] = monitorId
        monitor.id = monitorId
        monitor.groupId = groupId
        monitor.order = #members
        monitor.enabled = monitor.enabled ~= false
        monitor.sourceKey = entry.sourceKey
        monitor.contentScope = scope
        monitor.glow = FilterMonitorGlowForEntry(
            NormalizeMonitorGlow(monitor.glow),
            entry
        )
        monitor.sound = FilterMonitorSoundForEntry(
            NormalizeMonitorSound(monitor.sound),
            entry
        )
        monitor.nativeProcGlowOverride =
            type(monitor.nativeProcGlowOverride) == "table"
                and NormalizeNativeProcGlow(monitor.nativeProcGlowOverride)
                or nil
        monitor.visibilityMode = YHUD:SupportsPersistentDisplay(entry)
            and monitor.visibilityMode == "always"
            and "always" or "active"
        monitor.stateEffects = YHUD:NormalizeMonitorStateEffects(
            monitor.stateEffects,
            entry,
            monitor.skillAuraDisplayOverride
        )
        monitor.appearanceOverride =
            YHUD:NormalizeMonitorAppearanceOverride(
                monitor.appearanceOverride
            )
        monitor.skillAuraDisplayOverride = nil
        return true
    end
    for groupId in pairs(groups) do
        local source = content.groupMembers[groupId]
        if shared then
            local lanes = {
                before = {},
                after = {},
            }
            if type(source) == "table" then
                local beforeSource = type(source.before) == "table"
                    and source.before or {}
                local afterSource = type(source.after) == "table"
                    and source.after or source
                for index = 1, #beforeSource do
                    AppendMember(lanes.before, beforeSource[index], groupId)
                end
                for index = 1, #afterSource do
                    AppendMember(lanes.after, afterSource[index], groupId)
                end
            end
            content.groupMembers[groupId] = lanes
        else
            local members = {}
            if type(source) == "table" then
                for index = 1, #source do
                    AppendMember(members, source[index], groupId)
                end
            end
            content.groupMembers[groupId] = members
        end
    end

    for monitorId, monitor in pairs(content.monitors) do
        local entry = type(monitor) == "table"
            and content.entries[monitor.entryKey] or nil
        local groupId = type(monitor) == "table" and monitor.groupId or nil
        if not listed[monitorId]
            and entry and groups[groupId]
            and not entryMonitors[monitor.entryKey] then
            local rootMembers = content.groupMembers[groupId]
            local members = shared and rootMembers.after or rootMembers
            members[#members + 1] = monitorId
            listed[monitorId] = true
            entryMonitors[monitor.entryKey] = monitorId
            monitor.id = monitorId
            monitor.order = #members
            monitor.enabled = monitor.enabled ~= false
            monitor.sourceKey = entry.sourceKey
            monitor.contentScope = scope
            monitor.glow = FilterMonitorGlowForEntry(
                NormalizeMonitorGlow(monitor.glow),
                entry
            )
            monitor.sound = FilterMonitorSoundForEntry(
                NormalizeMonitorSound(monitor.sound),
                entry
            )
            monitor.nativeProcGlowOverride =
                type(monitor.nativeProcGlowOverride) == "table"
                    and NormalizeNativeProcGlow(
                        monitor.nativeProcGlowOverride
                    ) or nil
            monitor.visibilityMode = YHUD:SupportsPersistentDisplay(entry)
                and monitor.visibilityMode == "always"
                and "always" or "active"
            monitor.stateEffects = YHUD:NormalizeMonitorStateEffects(
                monitor.stateEffects,
                entry,
                monitor.skillAuraDisplayOverride
            )
            monitor.appearanceOverride =
                YHUD:NormalizeMonitorAppearanceOverride(
                    monitor.appearanceOverride
                )
            monitor.skillAuraDisplayOverride = nil
        end
    end
    for monitorId in pairs(content.monitors) do
        if not listed[monitorId] then content.monitors[monitorId] = nil end
    end

    for entryKey, entry in pairs(content.entries) do
        if type(entryKey) ~= "string" or type(entry) ~= "table" then
            content.entries[entryKey] = nil
        else
            entry.entryKey = entryKey
            YHUD:RepairConsumablePresetReplication(entry, entryKey)
            YHUD:RepairAmmoPresetReplication(entry)
            if entryKey == (YHUD.EQUIPMENT_AURA_BUNDLE_ENTRY_KEY
                or "bundle:equipment-auras") then
                entry.name = nil
                entry.nameKey = "designer.quick_equipment_auras"
            end
            entry.contentScope = scope
            entry.applicability = shared
                and (YHUD.NormalizeApplicability
                    and YHUD:NormalizeApplicability(
                        entry.applicability,
                        entry,
                        specKey
                    ) or entry.applicability)
                or nil
            entry.semantic = YHUD.GetEntrySemantic
                and YHUD:GetEntrySemantic(entry)
                or entry.semantic
                or "cooldown"
            if entry.sourceType == YHUD.CAST_BUFF_TIMER_SOURCE_TYPE
                or entry.sourceType == YHUD.SPELL_EVENT_WINDOW_SOURCE_TYPE then
                local duration = tonumber(entry.durationSeconds)
                local invalid = not duration
                    or duration ~= duration
                    or duration < 0.1 or duration > 3600
                if not invalid
                    and entry.sourceType == YHUD.SPELL_EVENT_WINDOW_SOURCE_TYPE then
                    local displaySpellID = tonumber(entry.spellId)
                    invalid = not displaySpellID or displaySpellID <= 0
                        or displaySpellID >= math.huge
                        or displaySpellID ~= math.floor(displaySpellID)
                    local triggerSpellIDs = entry.triggerSpellIds
                    if type(triggerSpellIDs) ~= "table"
                        or #triggerSpellIDs == 0 then
                        invalid = true
                    else
                        for index = 1, #triggerSpellIDs do
                            local triggerSpellID = tonumber(triggerSpellIDs[index])
                            if not triggerSpellID or triggerSpellID <= 0
                                or triggerSpellID >= math.huge
                                or triggerSpellID ~= math.floor(triggerSpellID) then
                                invalid = true
                                break
                            end
                        end
                    end
                end
                if invalid then
                    content.entries[entryKey] = nil
                    local monitorId = entryMonitors[entryKey]
                    if monitorId then content.monitors[monitorId] = nil end
                end
            end
        end
    end

    for groupId, members in pairs(content.groupMembers) do
        if shared then
            local retained = {
                before = {},
                after = {},
            }
            for _, lane in ipairs({ "before", "after" }) do
                for index = 1, #(members[lane] or {}) do
                    local monitorId = members[lane][index]
                    local monitor = content.monitors[monitorId]
                    if monitor and content.entries[monitor.entryKey] then
                        retained[lane][#retained[lane] + 1] = monitorId
                        monitor.order = #retained[lane]
                    else
                        content.monitors[monitorId] = nil
                    end
                end
            end
            content.groupMembers[groupId] = retained
        else
            local retained = {}
            for index = 1, #members do
                local monitorId = members[index]
                local monitor = content.monitors[monitorId]
                if monitor and content.entries[monitor.entryKey] then
                    retained[#retained + 1] = monitorId
                    monitor.order = #retained
                else
                    content.monitors[monitorId] = nil
                end
            end
            content.groupMembers[groupId] = retained
        end
    end

    if not shared then
        for entryKey, value in pairs(content.suppressedOfficial) do
            if value ~= true or type(entryKey) ~= "string" then
                content.suppressedOfficial[entryKey] = nil
            end
        end
    end
    return content
end

local function CollectSupportedSpecKeys(profile, currentSpecKey)
    return YHUD:GetSupportedSpecKeys()
end

local function LegacyEntryTargetsSpec(entry, specKey, currentSpecKey)
    local applicability = type(entry) == "table"
        and entry.applicability or nil
    if type(applicability) ~= "table"
        or applicability.kind == "all" then
        return true
    end
    -- A specialization key carries class context but not the target
    -- character's race. Preserve a legacy racial monitor only for the
    -- character/spec that is performing the migration instead of guessing
    -- that it applies to every specialization in the ConfigSet.
    if applicability.kind == "race" then
        return specKey == currentSpecKey
    end
    if applicability.kind == "class" then
        local classFile = specKey:match("^([^:]+):")
        return classFile == applicability.classFile
    end
    return false
end

local function NextMigratedId(values, preferred)
    if type(preferred) == "string" and values[preferred] == nil then
        return preferred
    end
    local base = type(preferred) == "string" and preferred
        or "yhud:migrated"
    local index = 2
    while values[base .. ":" .. tostring(index)] ~= nil do
        index = index + 1
    end
    return base .. ":" .. tostring(index)
end

local function BuildSemanticIdentityIndex(content)
    local identities = {}
    for monitorId, monitor in pairs(content.monitors or {}) do
        local entry = type(monitor) == "table"
            and content.entries[monitor.entryKey] or nil
        local identity = YHUD.GetEntrySemanticIdentity
            and YHUD:GetEntrySemanticIdentity(entry, monitor.entryKey)
        if identity then identities[identity] = monitorId end
    end
    return identities
end

local function MigrateV38SpecializationOwnership(profile, currentSpecKey)
    local shared = type(profile.sharedContent) == "table"
        and profile.sharedContent or nil
    if not shared then
        profile.sharedContent = nil
        profile._yhudLaneByMonitor = nil
        return
    end

    shared = NormalizeContent(
        profile,
        shared,
        YHUD.CONTENT_SCOPE_SHARED,
        currentSpecKey
    )
    EnsureMigratedCooldownGroup(profile, shared)
    shared = NormalizeContent(
        profile,
        shared,
        YHUD.CONTENT_SCOPE_SHARED,
        currentSpecKey
    )
    profile.contentBySpec = type(profile.contentBySpec) == "table"
        and profile.contentBySpec or {}
    local specKeys = CollectSupportedSpecKeys(profile, currentSpecKey)
    local groups = profile.groups and profile.groups.items or {}
    local report = {
        fromSchemaVersion = 38,
        toSchemaVersion = 39,
        currentSpecKey = currentSpecKey,
        targetSpecCount = #specKeys,
        sourceMonitorCount = 0,
        copied = 0,
        skippedConflict = 0,
        skippedInapplicable = 0,
        skippedInvalid = 0,
    }
    for _ in pairs(shared.monitors or {}) do
        report.sourceMonitorCount = report.sourceMonitorCount + 1
    end

    for specIndex = 1, #specKeys do
        local specKey = specKeys[specIndex]
        local content = NormalizeContent(
            profile,
            profile.contentBySpec[specKey] or YHUD:CreateDefaultContent(),
            YHUD.CONTENT_SCOPE_SPEC,
            specKey
        )
        local identities = BuildSemanticIdentityIndex(content)

        for groupId in pairs(groups) do
            local targetMembers = content.groupMembers[groupId]
            if type(targetMembers) ~= "table" then
                targetMembers = {}
                content.groupMembers[groupId] = targetMembers
            end
            local lanes = shared.groupMembers[groupId] or {}
            for _, laneName in ipairs({ "before", "after" }) do
                local members = type(lanes[laneName]) == "table"
                    and lanes[laneName] or {}
                for memberIndex = 1, #members do
                    local sourceMonitorId = members[memberIndex]
                    local sourceMonitor = shared.monitors[sourceMonitorId]
                    local sourceEntry = sourceMonitor
                        and shared.entries[sourceMonitor.entryKey] or nil
                    local identity = sourceEntry
                        and YHUD:GetEntrySemanticIdentity(
                            sourceEntry,
                            sourceMonitor.entryKey
                        ) or nil
                    local applies = sourceEntry and sourceMonitor and identity
                        and LegacyEntryTargetsSpec(
                            sourceEntry,
                            specKey,
                            currentSpecKey
                        )
                    if not sourceEntry or not sourceMonitor or not identity then
                        report.skippedInvalid = report.skippedInvalid + 1
                    elseif not applies then
                        report.skippedInapplicable =
                            report.skippedInapplicable + 1
                    elseif identities[identity] ~= nil then
                        report.skippedConflict = report.skippedConflict + 1
                    else
                        local entryKey = NextMigratedId(
                            content.entries,
                            sourceMonitor.entryKey
                        )
                        local monitorId = NextMigratedId(
                            content.monitors,
                            sourceMonitorId
                        )
                        local entry = CopyValue(sourceEntry)
                        entry.entryKey = entryKey
                        entry.contentScope = YHUD.CONTENT_SCOPE_SPEC
                        if entry.origin == "preset" then
                            entry.presetKey = entry.presetKey
                                or entry.presetId or sourceMonitor.entryKey
                            if entry.crossSpecMaterialization == nil then
                                entry.crossSpecMaterialization =
                                    (entry.bundleKind == "racial"
                                        or entry.bundleKind == (YHUD.EQUIPMENT_AURA_BUNDLE_KIND
                                            or "equipmentAura"))
                                    and "deferred" or "immediate"
                            end
                        end
                        if type(entry.applicability) == "table"
                            and entry.applicability.kind == "race" then
                            entry.crossSpecContext = CopyValue(entry.applicability)
                            entry.materializationState = "deferred"
                        end
                        entry.applicability = nil
                        local monitor = CopyValue(sourceMonitor)
                        monitor.id = monitorId
                        monitor.entryKey = entryKey
                        monitor.contentScope = YHUD.CONTENT_SCOPE_SPEC
                        monitor.groupId = groupId
                        content.entries[entryKey] = entry
                        content.monitors[monitorId] = monitor
                        targetMembers[#targetMembers + 1] = monitorId
                        identities[identity] = monitorId
                        report.copied = report.copied + 1
                    end
                end
            end
        end
        profile.contentBySpec[specKey] = NormalizeContent(
            profile,
            content,
            YHUD.CONTENT_SCOPE_SPEC,
            specKey
        )
    end

    profile.sharedContent = nil
    profile._yhudLaneByMonitor = nil
    profile._yhudScopeByEntry = nil
    profile._yhudScopeByMonitor = nil
    YHUD.lastSpecializationMigrationReport = report
end

function YHUD:ConsumeSpecializationMigrationReport()
    local report = self.lastSpecializationMigrationReport
    self.lastSpecializationMigrationReport = nil
    return report and CopyValue(report) or nil
end

local function MakeMonitorRef(scope, monitorId)
    return (scope == YHUD.CONTENT_SCOPE_SHARED and "shared:" or "spec:")
        .. tostring(monitorId)
end

local function ParseMonitorRef(value)
    if type(value) ~= "string" then return nil, nil end
    local prefix, monitorId = value:match("^([^:]+):(.+)$")
    if (prefix ~= "shared" and prefix ~= "spec")
        or not monitorId or monitorId == "" then
        return nil, nil
    end
    return prefix == "shared"
        and YHUD.CONTENT_SCOPE_SHARED or YHUD.CONTENT_SCOPE_SPEC,
        monitorId
end

local function BuildThreeLaneProjection(sharedContent, specContent, groupId)
    local lanes = sharedContent.groupMembers[groupId] or {}
    local before = type(lanes.before) == "table" and lanes.before or {}
    local after = type(lanes.after) == "table" and lanes.after or {}
    local spec = specContent.groupMembers[groupId] or {}
    local result = {}
    local laneByMonitor = {}
    local function Append(scope, lane, members)
        for index = 1, #members do
            local monitorId = members[index]
            result[#result + 1] = MakeMonitorRef(scope, monitorId)
            laneByMonitor[monitorId] = lane
        end
    end
    Append(
        YHUD.CONTENT_SCOPE_SHARED,
        YHUD.CONTENT_LANE_BEFORE or "before",
        before
    )
    Append(
        YHUD.CONTENT_SCOPE_SPEC,
        YHUD.CONTENT_LANE_SPEC or "spec",
        spec
    )
    Append(
        YHUD.CONTENT_SCOPE_SHARED,
        YHUD.CONTENT_LANE_AFTER or "after",
        after
    )
    return result, laneByMonitor
end

local function MigrateV9ProjectionLanes(profile, specKey, forceProjection)
    local shared = type(profile.sharedContent) == "table"
        and profile.sharedContent or {}
    shared.groupMembers = type(shared.groupMembers) == "table"
        and shared.groupMembers or {}
    local selected = IsStableSpecKey(specKey)
        and type(profile.contentBySpec) == "table"
        and profile.contentBySpec[specKey] or nil
    local selectedProjection = type(selected) == "table"
        and type(selected.projectionOrder) == "table"
        and selected.projectionOrder or {}
    local groups = profile.groups and profile.groups.items or {}

    for groupId in pairs(groups) do
        local source = shared.groupMembers[groupId]
        if not forceProjection
            and type(source) == "table"
            and #source == 0
            and (type(source.before) == "table"
                or type(source.after) == "table") then
            shared.groupMembers[groupId] = {
                before = CopyValue(source.before or {}),
                after = CopyValue(source.after or {}),
            }
        else
            local legacyMembers
            if type(source) == "table"
                and (type(source.before) == "table"
                    or type(source.after) == "table") then
                legacyMembers = {}
                for index = 1, #source do
                    legacyMembers[#legacyMembers + 1] = source[index]
                end
                for _, lane in ipairs({ source.before or {}, source.after or {} }) do
                    for index = 1, #lane do
                        local monitorId = lane[index]
                        local seen
                        for memberIndex = 1, #legacyMembers do
                            if legacyMembers[memberIndex] == monitorId then
                                seen = true
                                break
                            end
                        end
                        if not seen then
                            legacyMembers[#legacyMembers + 1] = monitorId
                        end
                    end
                end
            else
                legacyMembers = type(source) == "table" and source or {}
            end
            local projection = selectedProjection[groupId]
            local firstSpecIndex
            local sharedProjectionIndex = {}
            if type(projection) == "table" then
                for index = 1, #projection do
                    local ref = projection[index]
                    local scope, monitorId = ParseMonitorRef(ref)
                    if not scope then
                        if shared.monitors and shared.monitors[ref] then
                            scope = YHUD.CONTENT_SCOPE_SHARED
                            monitorId = ref
                        elseif selected and selected.monitors
                            and selected.monitors[ref] then
                            scope = YHUD.CONTENT_SCOPE_SPEC
                            monitorId = ref
                        end
                    end
                    if scope == YHUD.CONTENT_SCOPE_SPEC
                        and not firstSpecIndex then
                        firstSpecIndex = index
                    elseif scope == YHUD.CONTENT_SCOPE_SHARED
                        and monitorId
                        and sharedProjectionIndex[monitorId] == nil then
                        sharedProjectionIndex[monitorId] = index
                    end
                end
            end
            local lanes = {
                before = {},
                after = {},
            }
            for index = 1, #legacyMembers do
                local monitorId = legacyMembers[index]
                local projectionIndex = sharedProjectionIndex[monitorId]
                local lane = firstSpecIndex and projectionIndex
                        and projectionIndex < firstSpecIndex
                    and lanes.before or lanes.after
                lane[#lane + 1] = monitorId
            end
            shared.groupMembers[groupId] = lanes
        end
    end

    for _, content in pairs(type(profile.contentBySpec) == "table"
        and profile.contentBySpec or {}) do
        if type(content) == "table" then content.projectionOrder = nil end
    end
    profile.sharedContent = shared
end

local function IsSpecOwnedEntry(entry)
    return type(entry) == "table"
        and (entry.origin == "official-cdm"
            or entry.semantic == "resource"
            or entry.sourceType == "yhud.unit-power")
end

local function FindMonitorByEntry(content, entryKey)
    for monitorId, monitor in pairs(content.monitors or {}) do
        if type(monitor) == "table" and monitor.entryKey == entryKey then
            return monitorId, monitor
        end
    end
    return nil
end

local function NextContentMonitorId(content, preferred, entryKey)
    if type(preferred) == "string" and not content.monitors[preferred] then
        return preferred
    end
    local base = "monitor:shared:" .. tostring(entryKey)
    if not content.monitors[base] then return base end
    local index = 2
    while content.monitors[base .. ":" .. tostring(index)] do
        index = index + 1
    end
    return base .. ":" .. tostring(index)
end

local function PlacementRank(profile, groupId)
    local group = profile.groups and profile.groups.items
        and profile.groups.items[groupId]
    return group and group.kind == "user" and 0 or 1,
        group and tonumber(group.order) or 9999
end

local function PreferCandidatePlacement(profile, currentGroupId, nextGroupId)
    local currentKind, currentOrder = PlacementRank(profile, currentGroupId)
    local nextKind, nextOrder = PlacementRank(profile, nextGroupId)
    if nextKind ~= currentKind then return nextKind < currentKind end
    return nextOrder < currentOrder
end

local function RemoveMember(content, groupId, monitorId)
    local source = content.groupMembers and content.groupMembers[groupId]
    if type(source) ~= "table" then return end
    if type(source.before) == "table" or type(source.after) == "table" then
        for _, lane in ipairs({ source.before or {}, source.after or {} }) do
            for index = #lane, 1, -1 do
                if lane[index] == monitorId then table.remove(lane, index) end
            end
        end
        return
    end
    for index = #source, 1, -1 do
        if source[index] == monitorId then table.remove(source, index) end
    end
end

local function AddSharedCandidate(
    profile,
    shared,
    entry,
    monitor,
    groupId,
    specKey
)
    local applicability = YHUD.NormalizeApplicability
        and YHUD:NormalizeApplicability(entry.applicability, entry, specKey)
        or entry.applicability
    local baseEntryKey = entry.entryKey
    if entry.sourceIdentity == "bloodlust"
        or entry.sourceIdentity == "bloodlust-heroism" then
        baseEntryKey = YHUD.BLOODLUST_PRESET
            and YHUD.BLOODLUST_PRESET.entryKey
            or "buff-aura:bloodlust"
        applicability = { kind = "all" }
    end
    local entryKey = YHUD.QualifySharedEntryKey
        and YHUD:QualifySharedEntryKey(baseEntryKey, applicability)
        or baseEntryKey
    local existingMonitorId, existingMonitor =
        FindMonitorByEntry(shared, entryKey)
    local replacePlacement = existingMonitor
        and PreferCandidatePlacement(
            profile,
            existingMonitor.groupId,
            groupId
        )

    if not shared.entries[entryKey] or replacePlacement then
        local nextEntry = CopyValue(entry)
        nextEntry.entryKey = entryKey
        nextEntry.contentScope = YHUD.CONTENT_SCOPE_SHARED
        nextEntry.applicability = CopyValue(applicability)
        if nextEntry.sourceIdentity == "bloodlust" then
            nextEntry.sourceIdentity = "bloodlust-heroism"
        end
        shared.entries[entryKey] = nextEntry
    end

    if not monitor then return entryKey, nil end
    if existingMonitor and not replacePlacement then
        return entryKey, existingMonitorId
    end
    local monitorId = existingMonitorId
        or NextContentMonitorId(shared, monitor.id, entryKey)
    if existingMonitor then
        RemoveMember(shared, existingMonitor.groupId, monitorId)
    end
    local nextMonitor = CopyValue(monitor)
    nextMonitor.id = monitorId
    nextMonitor.entryKey = entryKey
    nextMonitor.sourceKey = shared.entries[entryKey].sourceKey
    nextMonitor.groupId = groupId
    nextMonitor.contentScope = YHUD.CONTENT_SCOPE_SHARED
    shared.monitors[monitorId] = nextMonitor
    local lanes = shared.groupMembers[groupId]
    if type(lanes) ~= "table"
        or (type(lanes.before) ~= "table"
            and type(lanes.after) ~= "table") then
        lanes = {
            before = {},
            after = type(lanes) == "table" and lanes or {},
        }
        shared.groupMembers[groupId] = lanes
    end
    lanes.before = type(lanes.before) == "table" and lanes.before or {}
    lanes.after = type(lanes.after) == "table" and lanes.after or {}
    lanes.after[#lanes.after + 1] = monitorId
    return entryKey, monitorId
end

local function MigrateV8ContentRoots(profile)
    local shared = CopyValue(DEFAULT_SHARED_CONTENT)
    local nextBySpec = {}
    local specKeys = {}
    for specKey in pairs(type(profile.contentBySpec) == "table"
        and profile.contentBySpec or {}) do
        if IsStableSpecKey(specKey) then specKeys[#specKeys + 1] = specKey end
    end
    table.sort(specKeys)

    for specIndex = 1, #specKeys do
        local specKey = specKeys[specIndex]
        local source = type(profile.contentBySpec[specKey]) == "table"
            and profile.contentBySpec[specKey] or {}
        MergeBloodlustTimerEntries(profile, source)
        local specContent = CopyValue(DEFAULT_SPEC_CONTENT)
        specContent.projectionOrder = {}
        specContent.initialization = CopyValue(source.initialization or {})
        specContent.suppressedOfficial =
            CopyValue(source.suppressedOfficial or {})
        local mappedEntries = {}
        local mappedMonitors = {}

        for entryKey, entry in pairs(type(source.entries) == "table"
            and source.entries or {}) do
            if type(entry) == "table" then
                entry = CopyValue(entry)
                entry.entryKey = entryKey
                if IsSpecOwnedEntry(entry) then
                    entry.contentScope = YHUD.CONTENT_SCOPE_SPEC
                    entry.applicability = nil
                    specContent.entries[entryKey] = entry
                    mappedEntries[entryKey] = {
                        scope = YHUD.CONTENT_SCOPE_SPEC,
                        entryKey = entryKey,
                    }
                else
                    local sharedKey = AddSharedCandidate(
                        profile,
                        shared,
                        entry,
                        nil,
                        nil,
                        specKey
                    )
                    mappedEntries[entryKey] = {
                        scope = YHUD.CONTENT_SCOPE_SHARED,
                        entryKey = sharedKey,
                    }
                end
            end
        end

        local groupIds = profile.groups and profile.groups.order or {}
        for groupIndex = 1, #groupIds do
            local groupId = groupIds[groupIndex]
            local members = source.groupMembers
                and source.groupMembers[groupId] or {}
            specContent.groupMembers[groupId] = {}
            specContent.projectionOrder[groupId] = {}
            for memberIndex = 1, #members do
                local oldMonitorId = members[memberIndex]
                local monitor = source.monitors
                    and source.monitors[oldMonitorId]
                local mapped = monitor and mappedEntries[monitor.entryKey]
                if monitor and mapped then
                    if mapped.scope == YHUD.CONTENT_SCOPE_SPEC then
                        local monitorId = oldMonitorId
                        local nextMonitor = CopyValue(monitor)
                        nextMonitor.id = monitorId
                        nextMonitor.entryKey = mapped.entryKey
                        nextMonitor.contentScope = YHUD.CONTENT_SCOPE_SPEC
                        specContent.monitors[monitorId] = nextMonitor
                        specContent.groupMembers[groupId][
                            #specContent.groupMembers[groupId] + 1
                        ] = monitorId
                        mappedMonitors[oldMonitorId] = {
                            scope = YHUD.CONTENT_SCOPE_SPEC,
                            monitorId = monitorId,
                        }
                    else
                        local sharedEntry = shared.entries[mapped.entryKey]
                        local _, monitorId = AddSharedCandidate(
                            profile,
                            shared,
                            sharedEntry,
                            monitor,
                            groupId,
                            specKey
                        )
                        mappedMonitors[oldMonitorId] = {
                            scope = YHUD.CONTENT_SCOPE_SHARED,
                            monitorId = monitorId,
                        }
                    end
                end
            end
            for memberIndex = 1, #members do
                local mapped = mappedMonitors[members[memberIndex]]
                if mapped and mapped.monitorId then
                    specContent.projectionOrder[groupId][
                        #specContent.projectionOrder[groupId] + 1
                    ] = MakeMonitorRef(mapped.scope, mapped.monitorId)
                end
            end
        end
        nextBySpec[specKey] = specContent
    end
    profile.sharedContent = shared
    profile.contentBySpec = nextBySpec
end

EnsureMigratedCooldownGroup = function(profile, content)
    local groups = profile.groups and profile.groups.items or {}
    local migrated = {}
    local relocated = {}
    local function QueueRelocated(targetGroupId, monitorId, lane)
        relocated[targetGroupId] = relocated[targetGroupId] or {}
        relocated[targetGroupId][#relocated[targetGroupId] + 1] = {
            monitorId = monitorId,
            lane = lane,
        }
    end
    local function FilterMembers(groupId, members, retained, lane)
        local group = groups[groupId]
        for index = 1, #members do
            local monitorId = members[index]
            local monitor = content.monitors[monitorId]
            local entry = monitor and content.entries[monitor.entryKey]
            local semantic = entry and (YHUD.GetEntrySemantic
                and YHUD:GetEntrySemantic(entry) or entry.semantic)
            local compatible = group and monitor and entry
            if compatible and YHUD.CanPlaceEntry then
                compatible = YHUD:CanPlaceEntry(entry, group, monitor.view)
                    == true
            elseif compatible and semantic == "cooldown" then
                compatible = group.layout ~= "bars" and group.layout ~= "rings"
            end
            if compatible then
                retained[#retained + 1] = monitorId
            elseif monitor and semantic == "cooldown" then
                migrated[#migrated + 1] = {
                    monitorId = monitorId,
                    lane = lane,
                }
            elseif monitor and semantic == "buff" then
                local targetGroupId = entry.officialCategory
                        and YHUD.DEFAULT_GROUP_BY_CATEGORY
                        and YHUD.DEFAULT_GROUP_BY_CATEGORY[
                            entry.officialCategory
                        ]
                    or YHUD.GROUP_IDS.BUFF
                QueueRelocated(targetGroupId, monitorId, lane)
            else
                content.monitors[monitorId] = nil
            end
        end
    end
    for groupId, members in pairs(content.groupMembers or {}) do
        if type(members.before) == "table"
            or type(members.after) == "table" then
            local retained = {
                before = {},
                after = {},
            }
            FilterMembers(
                groupId,
                members.before or {},
                retained.before,
                YHUD.CONTENT_LANE_BEFORE or "before"
            )
            FilterMembers(
                groupId,
                members.after or {},
                retained.after,
                YHUD.CONTENT_LANE_AFTER or "after"
            )
            content.groupMembers[groupId] = retained
        else
            local retained = {}
            FilterMembers(
                groupId,
                members,
                retained,
                YHUD.CONTENT_LANE_SPEC or "spec"
            )
            content.groupMembers[groupId] = retained
        end
    end

    if #migrated > 0 then
        local groupId = "group:user:migrated-cooldowns"
        local group = groups[groupId]
        if not group then
            group = {
                id = groupId,
                nameKey = "group.migrated_cooldowns",
                kind = "user",
                mode = "free",
                layout = "icons",
                contentPolicy = "cooldown-primary",
                enabled = true,
                showUnavailablePreview = false,
                fixedName = false,
                fixedDelete = false,
                officialCategories = {},
            }
            groups[groupId] = group
            profile.groups.order[#profile.groups.order + 1] = groupId
            profile.layout.groups[groupId] = NormalizeIconGroupLayout(nil)
            profile.style.groups[groupId] = NormalizeIconGroupStyle(nil)
        end
        relocated[groupId] = migrated
    end

    for targetGroupId, monitorItems in pairs(relocated) do
        local target = groups[targetGroupId]
        local members = content.groupMembers[targetGroupId]
        if target and type(members) ~= "table" then
            members = {}
            content.groupMembers[targetGroupId] = members
        end
        for index = 1, #monitorItems do
            local item = monitorItems[index]
            local monitorId = item.monitorId
            local monitor = content.monitors[monitorId]
            if target and monitor then
                local targetMembers = members
                if type(members.before) == "table"
                    or type(members.after) == "table" then
                    local lane = item.lane == (YHUD.CONTENT_LANE_BEFORE
                            or "before")
                        and "before" or "after"
                    targetMembers = members[lane]
                end
                targetMembers[#targetMembers + 1] = monitorId
                monitor.groupId = targetGroupId
                monitor.view = target.layout == "bars" and "bar"
                    or target.layout == "rings" and "ring"
                    or "icon"
                monitor.order = #targetMembers
            else
                content.monitors[monitorId] = nil
            end
        end
    end
end

function YHUD:IsStableSpecKey(value)
    return IsStableSpecKey(value) and self:IsSupportedSpecKey(value)
end

function YHUD:GetCurrentSpecKey()
    local service = YUI.Settings and YUI.Settings.ConfigSets
    if service and service.GetCurrentSpecializationKey then
        local key = service:GetCurrentSpecializationKey()
        if self:IsSupportedSpecKey(key) then return key end
    end
    local settings = YUI.Settings
    if settings and settings.GetCurrentSpecSelectionKey then
        local key = settings:GetCurrentSpecSelectionKey()
        if self:IsSupportedSpecKey(key) then return key end
    end
    return nil
end

function YHUD:CreateDefaultContent()
    return CopyValue(DEFAULT_SPEC_CONTENT)
end

function YHUD:CreateDefaultSharedContent()
    return CopyValue(DEFAULT_SHARED_CONTENT)
end

function YHUD:GetCanonicalProfile(profile)
    return type(profile) == "table"
        and (rawget(profile, "_yhudCanonical") or profile)
        or profile
end

function YHUD:GetContent(profile, specKey, create)
    profile = self:GetCanonicalProfile(profile)
    if type(profile) ~= "table" or not IsStableSpecKey(specKey) then
        return nil, "invalid-spec-key"
    end
    profile.contentBySpec = type(profile.contentBySpec) == "table"
        and profile.contentBySpec or {}
    local content = profile.contentBySpec[specKey]
    if not content and type(profile.specDocuments) == "table"
        and self.ConfigSets
        and type(self.ConfigSets.LoadSpecDocument) == "function" then
        local loaded, code = self.ConfigSets:LoadSpecDocument(
            profile,
            specKey,
            create == true
        )
        if not loaded and code ~= "content-not-found" then
            return nil, code
        end
        content = loaded
    end
    if not content and create == true then
        content = self:CreateDefaultContent()
        profile.contentBySpec[specKey] = content
    end
    if not content then return nil, "content-not-found" end
    content = NormalizeContent(
        profile,
        content,
        self.CONTENT_SCOPE_SPEC,
        specKey
    )
    profile.contentBySpec[specKey] = content
    return content
end

function YHUD:GetSpecContent(profile, specKey, create)
    return self:GetContent(profile, specKey, create)
end

function YHUD:GetSharedContent(profile, create)
    profile = self:GetCanonicalProfile(profile)
    if type(profile) ~= "table" then return nil, "invalid-profile" end
    if create == true then
        return nil, "legacy-shared-content-read-only"
    end
    local content = profile.sharedContent
    if not content then return nil, "content-not-found" end
    content = NormalizeContent(
        profile,
        content,
        self.CONTENT_SCOPE_SHARED
    )
    profile.sharedContent = content
    return content
end

function YHUD:BuildGroupProjection(profile, specKey, groupId)
    local canonical = self:GetCanonicalProfile(profile)
    local content, code = self:GetContent(canonical, specKey, false)
    if not content then return nil, code end
    local projection = {}
    for index = 1, #(content.groupMembers[groupId] or {}) do
        projection[index] = MakeMonitorRef(
            self.CONTENT_SCOPE_SPEC,
            content.groupMembers[groupId][index]
        )
    end
    return projection, {}
end

function YHUD:GetScopedProfile(profile, specKey, create)
    local canonical = self:GetCanonicalProfile(profile)
    specKey = specKey
        or (type(profile) == "table" and rawget(profile, "_yhudSpecKey"))
        or self:GetCurrentSpecKey()
    local content, code = self:GetContent(canonical, specKey, false)
    local virtualContent = false
    if not content and (create == true or create == "virtual") then
        content = NormalizeContent(
            canonical,
            self:CreateDefaultContent(),
            self.CONTENT_SCOPE_SPEC,
            specKey
        )
        if create == true then
            canonical.contentBySpec[specKey] = content
        else
            virtualContent = true
        end
    end
    if not content then return nil, code end

    self:MaterializeDefaultSlotPresets(canonical, content, specKey)

    local itemProxies = {}
    local mergedEntries = {}
    local mergedMonitors = {}
    local mergedMembers = {}
    local scopeByEntry = {}
    local scopeByMonitor = {}
    for entryKey, entry in pairs(content.entries) do
        mergedEntries[entryKey] = CopyValue(entry)
        scopeByEntry[entryKey] = self.CONTENT_SCOPE_SPEC
    end
    for monitorId, monitor in pairs(content.monitors) do
        mergedMonitors[monitorId] = CopyValue(monitor)
        scopeByMonitor[monitorId] = self.CONTENT_SCOPE_SPEC
    end
    for groupId, group in pairs(canonical.groups.items) do
        local members = {}
        local seenMembers = {}
        local sourceMembers = content.groupMembers[groupId] or {}
        for index = 1, #sourceMembers do
            local monitorId = sourceMembers[index]
            local monitor = content.monitors[monitorId]
            if monitor and not seenMembers[monitorId] then
                members[#members + 1] = monitorId
                seenMembers[monitorId] = true
                local mergedMonitor = mergedMonitors[monitorId]
                if mergedMonitor then
                    mergedMonitor.groupId = groupId
                    mergedMonitor.order = #members
                end
            end
        end
        mergedMembers[groupId] = members
        itemProxies[groupId] = setmetatable({}, {
            __index = function(_, key)
                if key == "monitors" then
                    return mergedMembers[groupId]
                end
                return group[key]
            end,
            __newindex = function(_, key, value)
                if key == "monitors" then
                    mergedMembers[groupId] = value
                else
                    group[key] = value
                end
            end,
        })
    end
    local groupsProxy = setmetatable({}, {
        __index = function(_, key)
            if key == "items" then return itemProxies end
            return canonical.groups[key]
        end,
        __newindex = function(_, key, value)
            if key ~= "items" then canonical.groups[key] = value end
        end,
    })
    local scoped = {
        _yhudCanonical = canonical,
        _yhudSpecKey = specKey,
        _yhudContent = content,
        _yhudSpecContent = content,
        _yhudVirtualContent = virtualContent,
        _yhudScopeByEntry = scopeByEntry,
        _yhudScopeByMonitor = scopeByMonitor,
        _yhudMergedMembers = mergedMembers,
        entries = mergedEntries,
        monitors = mergedMonitors,
        groups = groupsProxy,
    }
    return setmetatable(scoped, {
        __index = function(_, key)
            if key == "initialization" then return content.initialization end
            if key == "suppressedOfficial" then
                return content.suppressedOfficial
            end
            return canonical[key]
        end,
        __newindex = function(_, key, value)
            if key == "initialization" then
                content.initialization = value
            elseif key == "suppressedOfficial" then
                content.suppressedOfficial = value
            else
                canonical[key] = value
            end
        end,
    })
end

function YHUD:InvalidateRuntimeProfile()
    self.runtimeProfileRevision =
        (tonumber(self.runtimeProfileRevision) or 0) + 1
    self._runtimeProfile = nil
    self._runtimeProfileCanonical = nil
    self._runtimeProfileSpecKey = nil
    self._runtimeProfileRevision = nil
    self._initialResourceProfile = nil
    self._initialResourceProfileCanonical = nil
    self._initialResourceProfileRevision = nil
    local stats = self.profileCacheStats
    if stats then
        stats.invalidations = (stats.invalidations or 0) + 1
    end
    return self.runtimeProfileRevision
end

function YHUD:IsInitialSpecialization()
    local talent = YUI.API and YUI.API.Talent
    local info = talent and (talent.GetCurrentConfigurationSpecializationInfo or talent.GetCurrentSpecializationInfo)
        and (talent.GetCurrentConfigurationSpecializationInfo or talent.GetCurrentSpecializationInfo)() or nil
    return type(info) == "table" and info.isInitial == true
end

function YHUD:GetFirstCurrentClassSpecKey()
    local talent = YUI.API and YUI.API.Talent
    local unit = YUI.API and YUI.API.Unit
    local classFile = unit and unit.GetClassToken
        and unit.GetClassToken("player") or nil
    if not classFile and unit and unit.UnitClass then
        local _, token = unit.UnitClass("player")
        classFile = token
    end
    local specs = classFile and talent and (talent.GetClassConfigurationSpecializations or talent.GetClassSpecializations)
        and (talent.GetClassConfigurationSpecializations or talent.GetClassSpecializations)(classFile) or {}
    local specID = tonumber(specs[1] and specs[1].specID)
    local specKey = specID and string.upper(classFile)
        .. ":" .. tostring(specID) or nil
    return self:IsSupportedSpecKey(specKey) and specKey or nil
end

local INITIAL_RESOURCE_OMITTED_FIELDS = {
    contentBySpec = true,
    officialOverridesBySpec = true,
    defaultPresetTombstonesBySpec = true,
    defaultPresetOverridesBySpec = true,
    contentBySpecPack = true,
    specDocuments = true,
    sharedContent = true,
}

function YHUD:CreateInitialResourceProfile(profile)
    local canonical = self:GetCanonicalProfile(profile)
    if type(canonical) ~= "table" then return nil, "invalid-profile" end
    local revision = tonumber(self.runtimeProfileRevision) or 0
    if self._initialResourceProfile
        and self._initialResourceProfileCanonical == canonical
        and self._initialResourceProfileRevision == revision then
        return self._initialResourceProfile
    end

    local projected = {}
    for key, value in pairs(canonical) do
        if not INITIAL_RESOURCE_OMITTED_FIELDS[key]
            and not (type(key) == "string" and key:sub(1, 5) == "_yhud") then
            projected[key] = CopyValue(value)
        end
    end
    projected._yhudInitialResourceOnly = true
    projected.contentBySpec = {}
    projected.entries = {}
    projected.monitors = {}
    projected.groupMembers = {}
    projected.suppressedOfficial = {}

    local sourceGroups = canonical.groups
    projected.groups = { order = {}, items = {} }
    for _, groupId in ipairs(sourceGroups and sourceGroups.order or {}) do
        local group = sourceGroups.items[groupId]
        if group.layout == "resource" then
            projected.groups.order[#projected.groups.order + 1] = groupId
            projected.groups.items[groupId] = CopyValue(group)
        end
    end

    self._initialResourceProfile = projected
    self._initialResourceProfileCanonical = canonical
    self._initialResourceProfileRevision = revision
    return projected
end

function YHUD:GetRuntimeProfileForCurrentContext(profile, create)
    profile = profile or self:GetConfigProfile()
    local specKey = self:GetCurrentSpecKey()
    if self:IsStableSpecKey(specKey) then
        return self:GetRuntimeProfile(profile, specKey, create ~= false)
    end
    if self:IsInitialSpecialization() then
        return self:CreateInitialResourceProfile(profile)
    end
    return nil, "invalid-spec-key"
end

function YHUD:GetRuntimeProfile(profile, specKey, create)
    local canonical = self:GetCanonicalProfile(profile)
    if type(canonical) ~= "table" then
        return nil, "invalid-profile"
    end
    specKey = specKey
        or (type(profile) == "table" and rawget(profile, "_yhudSpecKey"))
        or self:GetCurrentSpecKey()
    if not self:IsStableSpecKey(specKey) then
        return nil, "invalid-spec-key"
    end

    local revision = tonumber(self.runtimeProfileRevision) or 0
    if self._runtimeProfile
        and self._runtimeProfileCanonical == canonical
        and self._runtimeProfileSpecKey == specKey
        and self._runtimeProfileRevision == revision then
        local stats = self.profileCacheStats
        if stats then stats.hits = (stats.hits or 0) + 1 end
        return self._runtimeProfile
    end

    if type(canonical.specDocuments) == "table"
        and rawget(canonical, "_yhudSpecDocumentProjection") ~= true
        and self.ConfigSets
        and type(self.ConfigSets.MaterializeProfile) == "function" then
        local projected, code = self.ConfigSets:MaterializeProfile(
            canonical,
            specKey,
            false
        )
        if not projected then return nil, code end
        local scoped
        scoped, code = self:GetScopedProfile(projected, specKey, create ~= false)
        if not scoped then return nil, code end
        self._runtimeProfile = scoped
        self._runtimeProfileCanonical = canonical
        self._runtimeProfileSpecKey = specKey
        self._runtimeProfileRevision = revision
        local stats = self.profileCacheStats
        if stats then stats.misses = (stats.misses or 0) + 1 end
        return scoped
    end

    local scoped, code = self:GetScopedProfile(
        canonical,
        specKey,
        create ~= false
    )
    if not scoped then return nil, code end
    self._runtimeProfile = scoped
    self._runtimeProfileCanonical = canonical
    self._runtimeProfileSpecKey = specKey
    self._runtimeProfileRevision = revision
    local stats = self.profileCacheStats
    if stats then stats.misses = (stats.misses or 0) + 1 end
    return scoped
end

function YHUD:GetProfileCacheStats(target)
    target = target or {}
    local stats = self.profileCacheStats or {}
    target.hits = stats.hits or 0
    target.misses = stats.misses or 0
    target.invalidations = stats.invalidations or 0
    target.revision = tonumber(self.runtimeProfileRevision) or 0
    return target
end

function YHUD:PersistScopedProfile(profile)
    if type(profile) ~= "table"
        or not rawget(profile, "_yhudCanonical")
        or not IsStableSpecKey(rawget(profile, "_yhudSpecKey")) then
        return nil, "invalid-scoped-profile"
    end
    local canonical = rawget(profile, "_yhudCanonical")
    local specKey = rawget(profile, "_yhudSpecKey")
    local content = {
        initialization = CopyPersistedValue(profile.initialization or {}),
        suppressedOfficial = CopyPersistedValue(
            profile.suppressedOfficial or {}
        ),
        entries = {},
        monitors = {},
        groupMembers = {},
    }
    for entryKey, entry in pairs(profile.entries or {}) do
        local nextEntry = CopyPersistedValue(entry)
        nextEntry.contentScope = self.CONTENT_SCOPE_SPEC
        nextEntry.applicability = nil
        content.entries[entryKey] = nextEntry
    end

    for monitorId, monitor in pairs(profile.monitors or {}) do
        if content.entries[monitor.entryKey] == nil then
            return nil, "entry-not-found"
        end
        local nextMonitor = CopyPersistedValue(monitor)
        nextMonitor.contentScope = self.CONTENT_SCOPE_SPEC
        content.monitors[monitorId] = nextMonitor
    end

    for groupId in pairs(canonical.groups.items) do
        content.groupMembers[groupId] = {}
        local group = profile.groups.items[groupId]
        local members = group and group.monitors or {}
        for index = 1, #members do
            local monitorId = members[index]
            local monitor = profile.monitors[monitorId]
            if monitor and content.monitors[monitorId] then
                monitor.groupId = groupId
                monitor.order = index
                local targetMembers = content.groupMembers[groupId]
                targetMembers[#targetMembers + 1] = monitorId
                local stored = content.monitors[monitorId]
                if stored then
                    stored.groupId = groupId
                    stored.order = #targetMembers
                end
            end
        end
    end

    canonical.sharedContent = nil
    canonical.contentBySpec[specKey] = NormalizeContent(
        canonical,
        content,
        self.CONTENT_SCOPE_SPEC,
        specKey
    )
    canonical.contentPolicyRevision =
        tonumber(self.CONTENT_POLICY_REVISION) or 4
    local scoped, code = self:GetScopedProfile(canonical, specKey, true)
    if not scoped then return nil, code end
    if self._runtimeProfileCanonical == canonical then
        self:InvalidateRuntimeProfile()
    end
    return scoped
end

function YHUD:GetDefaultMonitorGlow()
    return { rules = {} }
end

function YHUD:GetDefaultMonitorGlowAppearance()
    return CopyValue(DEFAULT_MONITOR_GLOW_APPEARANCE)
end

function YHUD:NormalizeMonitorGlow(glow)
    return NormalizeMonitorGlow(CopyValue(glow))
end

function YHUD:NormalizeMonitorSound(sound)
    return NormalizeMonitorSound(CopyValue(sound))
end

function YHUD:NormalizeMonitorGlowAppearance(appearance)
    return NormalizeMonitorGlowAppearance(CopyValue(appearance))
end

function YHUD:NormalizeNativeProcGlow(value)
    return NormalizeNativeProcGlow(CopyValue(value))
end

function YHUD:GetEffectiveNativeProcGlow(profile, monitor)
    if type(monitor) == "table"
        and type(monitor.nativeProcGlowOverride) == "table" then
        return monitor.nativeProcGlowOverride
    end
    local style = type(profile) == "table" and profile.style or nil
    return type(style) == "table"
        and type(style.nativeProcGlow) == "table"
        and style.nativeProcGlow or DEFAULT_NATIVE_PROC_GLOW
end

function YHUD:NormalizeVisibilityRule(rule, groupId)
    return NormalizeVisibilityRule(CopyValue(rule), groupId)
end

function YHUD:NormalizeSkyridingSettings(settings)
    return NormalizeSkyridingSettings(CopyValue(settings))
end

function YHUD:GetDefaultSkyridingStyleSettings(styleId)
    styleId = styleId == "halo" and "halo" or "horizon"
    return NormalizeSkyridingStyleSettings(styleId, nil)
end

function YHUD:GetSkyridingSettings(profile)
    profile = self:GetCanonicalProfile(profile)
    return NormalizeSkyridingSettings(
        type(profile) == "table" and profile.skyriding or nil
    )
end

function YHUD:CreateDefaultProfile(specKey)
    local profile = CopyValue(DEFAULT_PROFILE)
    local catalog = self.ResourceCatalog
    if catalog and catalog.GetDefinitionIds then
        for _, id in ipairs(catalog:GetDefinitionIds()) do
            local definition = catalog:GetDefinition(id)
            local setting = profile.resources.settingsByResource[id]
                or CopyValue(definition.defaultSettings) or {}
            if self.Client.id ~= "forever" or setting.valueText == nil then
                setting.valueText = definition.defaultValueText ~= false
            end
            if self.Client.id ~= "forever" or setting.valueFormat == nil then
                setting.valueFormat = definition.defaultValueFormat
            end
            if self.Client.id ~= "forever" or setting.thresholdMode == nil then
                setting.thresholdMode = self:GetDefaultResourceThresholdMode(definition)
            end
            profile.resources.settingsByResource[id] = setting
        end
    end
    return self:NormalizeProfile(profile, specKey)
end

function YHUD:NormalizeIconGroupLayout(layout, fallback)
    return NormalizeIconGroupLayout(layout, fallback)
end

function YHUD:GetIconGroupLayout(profile, groupId)
    profile = type(profile) == "table" and profile or {}
    local layoutRoot = type(profile.layout) == "table"
        and profile.layout or {}
    local fallback = CopyValue(DEFAULT_ICON_GROUP_LAYOUT)
    if groupId == self.GROUP_IDS.TRINKETS
        and type(layoutRoot.trinkets) == "table" then
        fallback = CopyValue(layoutRoot.trinkets)
    end
    local group = profile.groups and profile.groups.items
        and profile.groups.items[groupId]
    if group and group.contentPolicy == "buff-only" then
        fallback.wrapDirection = "up"
    end
    local groupLayouts = layoutRoot.groups
    local layout = type(groupLayouts) == "table"
        and groupLayouts[groupId] or nil
    return NormalizeIconGroupLayout(CopyValue(layout), fallback)
end

function YHUD:NormalizeIconGroupStyle(style, fallback)
    return NormalizeIconGroupStyle(style, fallback)
end

function YHUD:GetIconGroupStyle(profile, groupId)
    profile = type(profile) == "table" and profile or {}
    local styleRoot = type(profile.style) == "table"
        and profile.style or {}
    local fallback = {
        iconShape = styleRoot.iconShape,
        iconBorder = styleRoot.iconBorder,
        cooldownSwipe = styleRoot.cooldownSwipe,
        cooldownBling = styleRoot.cooldownBling,
        cooldownText = styleRoot.cooldownText,
        cooldownTextFont = styleRoot.cooldownTextFont,
        cooldownTextSize = styleRoot.cooldownTextSize,
        cooldownTextOutline = styleRoot.cooldownTextOutline,
        cooldownTextPosition = styleRoot.cooldownTextPosition,
        cooldownTextColor = styleRoot.cooldownTextColor,
        keybindTextMode = styleRoot.keybindTextMode,
        keybindTextFont = styleRoot.keybindTextFont,
        keybindTextSize = styleRoot.keybindTextSize,
        keybindTextOutline = styleRoot.keybindTextOutline,
        keybindTextPosition = styleRoot.keybindTextPosition,
        keybindTextOffsetX = styleRoot.keybindTextOffsetX,
        keybindTextOffsetY = styleRoot.keybindTextOffsetY,
        keybindTextColor = styleRoot.keybindTextColor,
        keybindTextOverrides = styleRoot.keybindTextOverrides,
    }
    fallback = NormalizeIconGroupStyle(fallback, DEFAULT_ICON_GROUP_STYLE)
    local groupStyles = styleRoot.groups
    local style = type(groupStyles) == "table"
        and groupStyles[groupId] or nil
    return NormalizeIconGroupStyle(CopyValue(style), fallback)
end

function YHUD:NormalizeDurationGroupLayout(layout, layoutType, fallback)
    return NormalizeDurationGroupLayout(layout, layoutType, fallback)
end

function YHUD:GetDurationGroupLayout(profile, groupId, layoutType)
    profile = type(profile) == "table" and profile or {}
    local group = profile.groups and profile.groups.items
        and profile.groups.items[groupId]
    layoutType = layoutType or (group and group.layout) or "bars"
    local root = type(profile.layout) == "table"
        and profile.layout or {}
    local groups = type(root.groups) == "table" and root.groups or {}
    local fallback = CopyValue(
        layoutType == "rings" and DEFAULT_RING_GROUP_LAYOUT
            or DEFAULT_BAR_GROUP_LAYOUT
    )
    if group and group.contentPolicy ~= "buff-only" then
        fallback.wrapDirection = "down"
    end
    return NormalizeDurationGroupLayout(
        CopyValue(groups[groupId]),
        layoutType,
        fallback
    )
end

function YHUD:NormalizeDurationGroupStyle(style, fallback)
    return NormalizeDurationGroupStyle(style, fallback)
end

function YHUD:GetDurationGroupStyle(profile, groupId)
    profile = type(profile) == "table" and profile or {}
    local group = profile.groups and profile.groups.items
        and profile.groups.items[groupId]
    local root = type(profile.style) == "table"
        and profile.style or {}
    local groups = type(root.groups) == "table" and root.groups or {}
    local fallback = CopyValue(DEFAULT_DURATION_GROUP_STYLE)
    if group and group.layout == "rings" then
        fallback.iconShape = "roundedSquare"
        fallback.countText = false
    end
    return NormalizeDurationGroupStyle(
        CopyValue(groups[groupId]),
        fallback
    )
end

function YHUD:NormalizeResourceGroupLayout(layout, fallback)
    return NormalizeResourceGroupLayout(layout, fallback)
end

function YHUD:NormalizeGroupPlacements(placements, groups)
    return NormalizeGroupPlacements(placements, groups)
end

function YHUD:GetResourceGroupLayout(profile, groupId)
    profile = type(profile) == "table" and profile or {}
    groupId = groupId or self.GROUP_IDS.RESOURCES
    local root = type(profile.layout) == "table"
        and profile.layout or {}
    local groups = type(root.groups) == "table" and root.groups or {}
    return NormalizeResourceGroupLayout(
        CopyValue(groups[groupId]),
        DEFAULT_RESOURCE_GROUP_LAYOUT
    )
end

function YHUD:NormalizeResourceGroupStyle(style, fallback)
    return NormalizeResourceGroupStyle(style, fallback)
end

function YHUD:GetResourceGroupStyle(profile, groupId)
    profile = type(profile) == "table" and profile or {}
    groupId = groupId or self.GROUP_IDS.RESOURCES
    local root = type(profile.style) == "table"
        and profile.style or {}
    local groups = type(root.groups) == "table" and root.groups or {}
    return NormalizeResourceGroupStyle(
        CopyValue(groups[groupId]),
        DEFAULT_RESOURCE_GROUP_STYLE
    )
end

function YHUD:NormalizeResourceTextSetting(setting, resourceId)
    local catalog = self.ResourceCatalog
    return NormalizeResourceText(setting, catalog and catalog:GetDefinition(resourceId))
end

function YHUD:NormalizeResourceSetting(
    setting,
    resourceId,
    legacyValueText,
    legacyDisplayMode,
    initialBorderColor
)
    local catalog = self.ResourceCatalog
    local definition = catalog and catalog.GetDefinition
        and catalog:GetDefinition(resourceId) or nil
    return NormalizeResourceSetting(
        setting,
        definition,
        legacyValueText,
        legacyDisplayMode,
        initialBorderColor
    )
end

function YHUD:_GetResourceSettingStorageBaseline(resourceId, initialBorderColor)
    local catalog = self.ResourceCatalog
    local definition = catalog and catalog.GetDefinition
        and catalog:GetDefinition(resourceId) or nil
    return GetResourceSettingStorageBaseline(
        resourceId,
        definition,
        initialBorderColor
    )
end

-- Resource configuration has one owner per group. Legacy roots are accepted
-- only while normalizing old profiles and by old callers' default-group scope.
function YHUD:GetResourceConfig(profile, groupId)
    local root = type(profile) == "table" and profile.resources or nil
    if type(root) ~= "table" then return {} end
    if type(root.byGroup) == "table" then
        return root.byGroup[groupId or self.GROUP_IDS.RESOURCES] or {}
    end
    return root
end

function YHUD:GetResourceProfile(profile, groupId)
    local layout = profile and profile.layout and profile.layout.groups
        and profile.layout.groups[groupId or self.GROUP_IDS.RESOURCES]
    return {
        resources = self:GetResourceConfig(profile, groupId),
        _yhudInitialResourceOnly = profile and profile._yhudInitialResourceOnly,
        _yhudHandPairMode = YUI.IsForever == true and layout and layout.handPairMode,
    }
end

function YHUD:HasEnabledResourceGroup(profile)
    local groups = profile and profile.groups and profile.groups.items
    if type(groups) == "table" then
        for _, group in pairs(groups) do
            if group.layout == "resource" and group.enabled == true then return true end
        end
        return false
    end
    return profile and profile.resources and profile.resources.enabled == true or false
end

function YHUD:GetResourceSetting(profile, resourceId, groupId)
    profile = type(profile) == "table" and profile or {}
    local resources = self:GetResourceConfig(profile, groupId)
    local settings = type(resources.settingsByResource) == "table"
        and resources.settingsByResource or {}
    return self:NormalizeResourceSetting(settings[resourceId], resourceId)
end

function YHUD:GetEffectiveResourceStyle(profile, groupId, resourceId, specID)
    local global = self:GetResourceGroupStyle(profile, groupId)
    local setting = self:GetResourceSetting(profile, resourceId, groupId)
    local definition = self.ResourceCatalog and self.ResourceCatalog:GetDefinition(resourceId)
    local text = setting.textOverride or global
    local appearance = setting.appearanceOverride or global
    local fillColor = setting.fillColor
    if resourceId == "runes" and type(setting.runeColors) == "table" then
        local runeColorKey = tonumber(specID) == 250 and "blood"
            or (tonumber(specID) == 252 and "unholy" or "frost")
        fillColor = setting.runeColors[runeColorKey] or fillColor
    end
    return {
        smoothProgress = global.smoothProgress == true,
        visibilityMode = setting.visibilityMode,
        valueText = setting.valueText,
        valueFormat = setting.valueFormat,
        abbreviateValues = setting.abbreviateValues,
        text2 = setting.text2,
        valueDurationPreview = definition and definition.provider and definition.provider.kind == "absorb" and 12 or nil,
        textPosition = setting.textPosition,
        textOffsetX = setting.textOffsetX,
        textOffsetY = setting.textOffsetY,
        heightOverride = setting.heightOverride,
        textFont = text.textFont,
        textSize = text.textSize,
        textOutline = text.textOutline,
        textColor = CopyValue(text.textColor),
        runeCooldownTextSize = setting.runeCooldownTextSize,
        runeCooldownTextMode = setting.runeCooldownTextMode,
        border = appearance.border,
        borderColor = CopyValue(appearance.borderColor),
        fillTexture = appearance.fillTexture,
        fillColorMode = "custom",
        fillColor = CopyValue(fillColor),
        backgroundColor = CopyValue(appearance.backgroundColor),
        displayMode = setting.displayMode,
        inverseFill = setting.inverseFill == true,
        segmentSpacing = setting.segmentSpacing,
        dividerThickness = setting.dividerThickness,
        dividerColor = CopyValue(setting.dividerColor),
        thresholdColorEnabled = setting.thresholdColorEnabled,
        thresholdMode = setting.thresholdMode,
        thresholdDirection = setting.fillCeilingPercent and "ascending" or nil,
        fillCeilingPercent = setting.fillCeilingPercent,
        thresholdMarkerEnabled = setting.thresholdMarkerEnabled,
        thresholds = CopyValue(setting.thresholds),
        thresholdMarkerColor = CopyValue(setting.thresholdMarkerColor),
        thresholdMarkerThickness = setting.thresholdMarkerThickness,
    }
end

function YHUD:NormalizeProfile(profile, specKey)
    profile = self:GetCanonicalProfile(profile)
    if type(profile) ~= "table" then profile = {} end
    if self:HasLegacyTrinketGroup(profile) then
        local code, detail
        if self.ConfigSets and self.ConfigSets.RetireLegacyTrinketGroup then
            profile, code, detail = self.ConfigSets:RetireLegacyTrinketGroup(profile)
        else
            profile, code, detail = self:RetireLegacyTrinketGroup(profile)
        end
        if not profile then return nil, code, detail end
    end
    local byGroup = type(profile.resources) == "table"
        and type(profile.resources.byGroup) == "table"
        and profile.resources.byGroup or nil
    if byGroup then
        profile.resources = byGroup[self.GROUP_IDS.RESOURCES] or {}
    end
    self:MigrateClientSpecializationKeys(profile)
    RemoveUnsupportedSpecializationData(profile)
    RepairLegacyMojibakeProfileNames(profile)
    local sourceVersion = tonumber(profile.schemaVersion) or 0
    local needsV32OfficialCDMIdentityMigration = sourceVersion < 32
    local sourceResources = type(profile.resources) == "table"
        and profile.resources or nil
    local sourceResourceSettings = sourceResources
        and type(sourceResources.settingsByResource) == "table"
        and sourceResources.settingsByResource or nil
    local materializeResourceSettings = sourceResourceSettings ~= nil and (sourceVersion < 31
        or (sourceResources
            and sourceResources.settingsDeltaVersion
                == RESOURCE_SETTINGS_DELTA_VERSION))
    if sourceResources then
        sourceResources.settingsDeltaVersion = nil
        if sourceResourceSettings then
            sourceResources.settingsByResource = false
        end
    end
    local needsV30ResourceWidthModeMigration = sourceVersion < 30
    local needsV24ExplicitBarTextAnchors = sourceVersion < 24
    local needsV22AxisSpacingMigration = sourceVersion < 22
    local needsV21OuterBoxMigration = sourceVersion < 21
    local needsV12ResourceAppearanceMigration = sourceVersion < 12
    local needsV11ResourceMigration = sourceVersion < 11
    local needsV10LaneMigration = sourceVersion < 10
    local needsV9ContentMigration = sourceVersion < 9
    local needsV39SpecializationOwnershipMigration = sourceVersion < 39
    local hadLegacyContent = sourceVersion < 8
        and (type(profile.entries) == "table"
            or type(profile.monitors) == "table"
            or type(profile.groupMembers) == "table")
    local legacyContent = hadLegacyContent and ExtractLegacyContent(profile) or nil
    specKey = IsStableSpecKey(specKey) and specKey or self:GetCurrentSpecKey()

    local legacyResourceValueText
    if needsV11ResourceMigration then
        local legacyStyle = type(profile.style) == "table"
            and type(profile.style.groups) == "table"
            and profile.style.groups[self.GROUP_IDS.RESOURCES] or nil
        if type(legacyStyle) == "table"
            and type(legacyStyle.valueText) == "boolean" then
            legacyResourceValueText = legacyStyle.valueText
        end
    end

    if needsV22AxisSpacingMigration and type(profile.layout) == "table" then
        MigrateV21AxisSpacing(profile.layout.trinkets, 6)
        local groupLayouts = profile.layout.groups
        local groupItems = type(profile.groups) == "table"
            and type(profile.groups.items) == "table"
            and profile.groups.items or nil
        if type(groupLayouts) == "table" then
            for groupId, layout in pairs(groupLayouts) do
                if groupId ~= self.GROUP_IDS.RESOURCES then
                    local group = groupItems and groupItems[groupId]
                    MigrateV21AxisSpacing(
                        layout,
                        group and group.layout == "rings" and 8 or 6
                    )
                end
            end
        end
    end

    if needsV24ExplicitBarTextAnchors then
        MigrateV23ExplicitBarTextAnchors(profile)
    end

    local profileDefaults = self.Client.id ~= "forever" and sourceVersion < 29
        and DEFAULT_PROFILE or EXISTING_PROFILE_DEFAULTS
    if type(profile.specDocuments) == "table" then
        profileDefaults = CopyValue(profileDefaults)
        profileDefaults.contentBySpec = nil
        profileDefaults.sharedContent = nil
    end
    FillDefaults(profile, profileDefaults)
    profile.skyriding = NormalizeSkyridingSettings(profile.skyriding)
    if sourceResourceSettings then
        profile.resources.settingsByResource = sourceResourceSettings
    end
    profile.resources.settingsDeltaVersion = nil
    if needsV30ResourceWidthModeMigration then
        local resourceLayout = type(profile.layout) == "table"
            and type(profile.layout.groups) == "table"
            and profile.layout.groups[self.GROUP_IDS.RESOURCES] or nil
        if type(resourceLayout) == "table" then
            resourceLayout.widthMode = "fixed"
        end
    end
    profile.schemaVersion = self.SCHEMA_VERSION
    profile.profileVersion = self.PROFILE_VERSION

    if needsV11ResourceMigration then
        local styleRoot = type(profile.style) == "table"
            and profile.style or {}
        styleRoot.cooldownTextOutline = "outlineShadow"
        local groupStyles = type(styleRoot.groups) == "table"
            and styleRoot.groups or {}
        for _, groupStyle in pairs(groupStyles) do
            if type(groupStyle) == "table" then
                groupStyle.cooldownTextOutline = "outlineShadow"
                groupStyle.countTextOutline = "outlineShadow"
                groupStyle.nameTextOutline = "outlineShadow"
                groupStyle.timeTextOutline = "outlineShadow"
                groupStyle.textOutline = "outlineShadow"
            end
        end
    end

    profile.racials = type(profile.racials) == "table"
        and profile.racials or {}
    profile.racials.enabled = profile.racials.enabled == true
    local legacyRacialChoices = type(profile.racials.choicesByRace) == "table"
        and profile.racials.choicesByRace or nil
    if legacyRacialChoices then
        for raceToken, choices in pairs(legacyRacialChoices) do
            if type(raceToken) ~= "string" or type(choices) ~= "table" then
                legacyRacialChoices[raceToken] = nil
            else
                for spellID, enabled in pairs(choices) do
                    local numericID = tonumber(spellID)
                    if not numericID or numericID <= 0 then
                        choices[spellID] = nil
                    else
                        local stableKey = tostring(math.floor(numericID))
                        if stableKey ~= spellID then choices[spellID] = nil end
                        choices[stableKey] = enabled ~= false
                    end
                end
            end
        end
    end

    local cdm = profile.cdm
    cdm.sourceMode = "readOnly"
    cdm.importEnabled = NormalizeBoolean(cdm.importEnabled, true)
    cdm.writeBackEnabled = false
    cdm.skillAuraDisplay = NormalizeBoolean(cdm.skillAuraDisplay, true)
    cdm.skillAuraHighlight =
        NormalizeBoolean(cdm.skillAuraHighlight, true)
    cdm.inactiveDesaturate =
        NormalizeBoolean(cdm.inactiveDesaturate, false)

    local resources = profile.resources
    resources.enabled = NormalizeBoolean(resources.enabled, true)
    resources.singleton = true
    if sourceVersion < 26
        and self.ResourceCatalog
        and self.ResourceCatalog.MigrateLegacyFormOverrides then
        self.ResourceCatalog:MigrateLegacyFormOverrides(resources)
    end
    if self.ResourceCatalog and self.ResourceCatalog.NormalizeFormOverrides then
        resources.formOverrides =
            self.ResourceCatalog:NormalizeFormOverrides(resources.formOverrides)
    elseif type(resources.formOverrides) ~= "table" then
        resources.formOverrides = {}
    end
    if self.ResourceCatalog and self.ResourceCatalog.NormalizeSelections then
        resources.bySpec =
            self.ResourceCatalog:NormalizeSelections(resources.bySpec)
    elseif type(resources.bySpec) ~= "table" then
        resources.bySpec = {}
    end
    if self.ResourceCatalog and self.ResourceCatalog.NormalizeOrders then
        resources.orderBySpec =
            self.ResourceCatalog:NormalizeOrders(resources.orderBySpec)
    elseif type(resources.orderBySpec) ~= "table" then
        resources.orderBySpec = {}
    end
    resources.bySpec.DRUID = nil
    resources.orderBySpec.DRUID = nil
    for classFile, classSelections in pairs(BUILTIN_SPECIAL_RESOURCE_SELECTIONS) do
        local targetClass = resources.bySpec[classFile]
        if type(targetClass) ~= "table" then
            targetClass = {}
            resources.bySpec[classFile] = targetClass
        end
        for targetSpec, defaults in pairs(classSelections) do
            local targetSelection = targetClass[targetSpec]
            if type(targetSelection) ~= "table" then
                targetSelection = {}
                targetClass[targetSpec] = targetSelection
            end
            for resourceId, defaultEnabled in pairs(defaults) do
                if type(targetSelection[resourceId]) ~= "boolean" then
                    targetSelection[resourceId] = defaultEnabled == true
                end
            end
        end
    end
    local resourceCatalog = self.ResourceCatalog
    local resourceStyle = type(profile.style) == "table"
        and type(profile.style.groups) == "table"
        and profile.style.groups[self.GROUP_IDS.RESOURCES] or nil
    local initialResourceBorderColor = type(resourceStyle) == "table"
        and resourceStyle.borderColor or nil
    local settingsByResource = type(resources.settingsByResource) == "table"
        and resources.settingsByResource or {}
    for resourceId, defaults in pairs(
        BUILTIN_SPECIAL_RESOURCE_SETTING_DEFAULTS
    ) do
        if type(settingsByResource[resourceId]) ~= "table" then
            settingsByResource[resourceId] = CopyValue(defaults)
        end
    end
    if materializeResourceSettings
        and resourceCatalog
        and resourceCatalog.GetDefinitionIds
        and resourceCatalog.GetDefinition then
        settingsByResource = MaterializeResourceSettingDeltas(
            settingsByResource,
            resourceCatalog,
            initialResourceBorderColor
        )
    end
    local normalizedSettings = {}
    if resourceCatalog and resourceCatalog.GetDefinitionIds then
        local definitionIds = resourceCatalog:GetDefinitionIds()
        for index = 1, #definitionIds do
            local resourceId = definitionIds[index]
            if sourceResourceSettings ~= nil then
                local definition = resourceCatalog:GetDefinition(resourceId)
                local setting = settingsByResource[resourceId]
                    or CopyValue(definition.defaultSettings) or {}
                if setting.thresholdMode == nil then
                    setting.thresholdMode = definition.valueKind == "discrete" and "value" or "percent"
                end
                settingsByResource[resourceId] = setting
            end
            normalizedSettings[resourceId] = NormalizeResourceSetting(
                settingsByResource[resourceId],
                resourceCatalog:GetDefinition(resourceId),
                legacyResourceValueText,
                needsV12ResourceAppearanceMigration
                    and not BUILTIN_SPECIAL_RESOURCE_IDS[resourceId],
                initialResourceBorderColor
            )
            MigrateResourceSeverityDefaults(
                normalizedSettings[resourceId], resourceCatalog:GetDefinition(resourceId)
            )
        end
    end
    resources.settingsByResource = normalizedSettings

    local trinkets = profile.items.trinkets
    trinkets.enabled = NormalizeBoolean(trinkets.enabled, true)
    if type(trinkets.slots) ~= "table" then trinkets.slots = {} end
    trinkets.slots[13] = NormalizeBoolean(trinkets.slots[13], true)
    trinkets.slots[14] = NormalizeBoolean(trinkets.slots[14], true)

    if type(profile.groups.order) ~= "table" then
        profile.groups.order = CopyValue(DEFAULT_GROUP_ORDER)
    end
    if type(profile.groups.items) ~= "table" then profile.groups.items = {} end
    FillDefaults(profile.groups.items, profileDefaults.groups.items)

    local groups = profile.groups.items
    local normalizedOrder = {}
    local seenGroups = {}
    for index = 1, #profile.groups.order do
        local groupId = profile.groups.order[index]
        if type(groupId) == "string"
            and groups[groupId]
            and not seenGroups[groupId] then
            seenGroups[groupId] = true
            normalizedOrder[#normalizedOrder + 1] = groupId
        end
    end
    for index = 1, #DEFAULT_GROUP_ORDER do
        local groupId = DEFAULT_GROUP_ORDER[index]
        if groups[groupId] and not seenGroups[groupId] then
            seenGroups[groupId] = true
            normalizedOrder[#normalizedOrder + 1] = groupId
        end
    end
    local customGroupIds = {}
    for groupId in pairs(groups) do
        if type(groupId) == "string" and not seenGroups[groupId] then
            customGroupIds[#customGroupIds + 1] = groupId
        end
    end
    table.sort(customGroupIds)
    for index = 1, #customGroupIds do
        normalizedOrder[#normalizedOrder + 1] = customGroupIds[index]
    end
    profile.groups.order = normalizedOrder

    for index = 1, #normalizedOrder do
        local groupId = normalizedOrder[index]
        local group = groups[groupId]
        group.id = groupId
        group.order = index
        group.displayLayer = ClampInteger(group.displayLayer, 1, 10, 5)
        if group.mode ~= "fixed" and group.mode ~= "official" then
            group.mode = "free"
        end
        if group.layout ~= "bars"
            and group.layout ~= "rings"
            and group.layout ~= "resource" then
            group.layout = "icons"
        end
        group.layoutMode = group.layoutMode == "fixed" and "fixed" or "auto"
        group.enabled = NormalizeBoolean(group.enabled, true)
        group.showUnavailablePreview = NormalizeBoolean(
            group.showUnavailablePreview,
            false
        )
        group.showTooltip = NormalizeBoolean(group.showTooltip, true)
        group.visibility = NormalizeVisibilityRule(group.visibility, groupId)
        if self.NormalizeGroupContentPolicy then
            self:NormalizeGroupContentPolicy(group)
        end
        local syncCategory = self.GetDefaultGroupSyncCategory
            and self:GetDefaultGroupSyncCategory(groupId)
        group.syncCategory = syncCategory
        group.officialCategories = syncCategory and { syncCategory } or {}
    end

    local important = groups[self.GROUP_IDS.IMPORTANT]
    important.fixedName = true
    important.fixedDelete = true
    important.fixedEnabled = nil

    local fixedIds = {
        self.GROUP_IDS.IMPORTANT,
        self.GROUP_IDS.UTILITY,
        self.GROUP_IDS.BUFF,
        self.GROUP_IDS.BAR,
    }
    for index = 1, #fixedIds do
        local group = groups[fixedIds[index]]
        group.fixedName = true
        group.fixedDelete = true
        group.enabled = NormalizeBoolean(group.enabled, true)
    end

    local resourceGroup = groups[self.GROUP_IDS.RESOURCES]
    resourceGroup.singleton = nil
    resourceGroup.layout = "resource"
    if not byGroup then resourceGroup.enabled = resources.enabled end
    resourceGroup.fixedName = true
    resourceGroup.fixedDelete = true

    local trinketGroup = groups[self.GROUP_IDS.TRINKETS]
    if trinketGroup then
        trinketGroup.layout = "icons"
        trinketGroup.enabled = NormalizeBoolean(trinketGroup.enabled, true)
    end

    if needsV21OuterBoxMigration
        and type(profile.layout) == "table"
        and type(profile.layout.groups) == "table" then
        for groupId, group in pairs(groups) do
            if group.layout == "bars" then
                MigrateV20BarLayoutToOuterBox(
                    profile.layout.groups[groupId]
                )
            end
        end
    end
    if type(profile.layout) ~= "table" then profile.layout = {} end
    FillDefaults(profile.layout, self.Client.id == "forever"
        and profileDefaults.layout or DEFAULT_PROFILE.layout)
    local legacyTrinketLayout = NormalizeIconGroupLayout(
        profile.layout.trinkets,
        DEFAULT_ICON_GROUP_LAYOUT
    )
    profile.layout.trinkets = legacyTrinketLayout
    if type(profile.layout.groups) ~= "table" then
        profile.layout.groups = {}
    end
    for index = 1, #normalizedOrder do
        local groupId = normalizedOrder[index]
        local group = groups[groupId]
        if group.layout == "icons" then
            local fallback = CopyValue(
                groupId == self.GROUP_IDS.TRINKETS
                    and legacyTrinketLayout or DEFAULT_ICON_GROUP_LAYOUT
            )
            if group.contentPolicy == "buff-only" then
                fallback.wrapDirection = "up"
            end
            profile.layout.groups[groupId] = NormalizeIconGroupLayout(
                profile.layout.groups[groupId],
                fallback
            )
        elseif group.layout == "bars" or group.layout == "rings" then
            local fallback = CopyValue(
                group.layout == "rings"
                    and DEFAULT_RING_GROUP_LAYOUT
                    or DEFAULT_BAR_GROUP_LAYOUT
            )
            if group.contentPolicy ~= "buff-only" then
                fallback.wrapDirection = "down"
            end
            profile.layout.groups[groupId] = NormalizeDurationGroupLayout(
                profile.layout.groups[groupId],
                group.layout,
                fallback
            )
        elseif group.layout == "resource" then
            profile.layout.groups[groupId] = NormalizeResourceGroupLayout(
                profile.layout.groups[groupId],
                DEFAULT_RESOURCE_GROUP_LAYOUT
            )
        end
    end
    profile.layout.placements = NormalizeGroupPlacements(
        profile.layout.placements,
        groups
    )
    -- v33 repairs saved placements whose YHUD-relative group no longer exists.
    -- The repair is deliberately idempotent and also protects current-schema
    -- imports before they enter ConfigSets storage.
    RepairDanglingGroupAnchors(profile)
    profile.layout.trinkets = CopyValue(
        profile.layout.groups[self.GROUP_IDS.TRINKETS]
            or legacyTrinketLayout
    )

    local style = profile.style
    style.nativeProcGlow = NormalizeNativeProcGlow(style.nativeProcGlow)
    if type(style.pandemicGlow) ~= "boolean" then
        style.pandemicGlow = true
    end
    local legacyStyle = NormalizeIconGroupStyle({
        iconShape = style.iconShape,
        iconBorder = style.iconBorder,
        cooldownBling = style.cooldownBling,
        cooldownText = style.cooldownText,
        cooldownTextFont = style.cooldownTextFont,
        cooldownTextSize = style.cooldownTextSize,
        cooldownTextOutline = style.cooldownTextOutline,
        cooldownTextPosition = style.cooldownTextPosition,
        cooldownTextColor = style.cooldownTextColor,
    }, DEFAULT_ICON_GROUP_STYLE)
    style.iconShape = legacyStyle.iconShape
    style.iconBorder = legacyStyle.iconBorder
    style.cooldownBling = legacyStyle.cooldownBling
    style.cooldownText = legacyStyle.cooldownText
    style.cooldownTextFont = legacyStyle.cooldownTextFont
    style.cooldownTextSize = legacyStyle.cooldownTextSize
    style.cooldownTextOutline = legacyStyle.cooldownTextOutline
    style.cooldownTextPosition = legacyStyle.cooldownTextPosition
    style.cooldownTextColor = legacyStyle.cooldownTextColor
    if type(style.groups) ~= "table" then style.groups = {} end
    for index = 1, #normalizedOrder do
        local groupId = normalizedOrder[index]
        local group = groups[groupId]
        if group.layout == "icons" then
            style.groups[groupId] = NormalizeIconGroupStyle(
                style.groups[groupId],
                legacyStyle
            )
        elseif group.layout == "bars" or group.layout == "rings" then
            local fallback = CopyValue(DEFAULT_DURATION_GROUP_STYLE)
            if group.layout == "rings" then
                fallback.iconShape = "roundedSquare"
                fallback.countText = false
            end
            style.groups[groupId] = NormalizeDurationGroupStyle(
                style.groups[groupId],
                fallback
            )
        elseif group.layout == "resource" then
            style.groups[groupId] = NormalizeResourceGroupStyle(
                style.groups[groupId],
                DEFAULT_RESOURCE_GROUP_STYLE
            )
        end
    end

    profile.contentBySpec = type(profile.contentBySpec) == "table"
        and profile.contentBySpec or {}
    if legacyContent then
        if IsStableSpecKey(specKey) then
            local target = profile.contentBySpec[specKey]
                or self:CreateDefaultContent()
            profile.contentBySpec[specKey] = MergeContent(target, legacyContent)
        else
            profile.pendingLegacyContent = MergeContent(
                type(profile.pendingLegacyContent) == "table"
                    and profile.pendingLegacyContent or {},
                legacyContent
            )
        end
    end
    if IsStableSpecKey(specKey)
        and type(profile.pendingLegacyContent) == "table" then
        local target = profile.contentBySpec[specKey]
            or self:CreateDefaultContent()
        profile.contentBySpec[specKey] =
            MergeContent(target, profile.pendingLegacyContent)
        profile.pendingLegacyContent = nil
        needsV9ContentMigration = true
    end

    if needsV9ContentMigration then
        MigrateV8ContentRoots(profile)
    end
    if needsV10LaneMigration then
        MigrateV9ProjectionLanes(profile, specKey, needsV9ContentMigration)
    end
    if needsV32OfficialCDMIdentityMigration then
        MigrateOfficialCDMProfile(profile)
    end

    local racialBundleEntry = type(profile.sharedContent) == "table"
        and type(profile.sharedContent.entries) == "table"
        and profile.sharedContent.entries["racial:bundle"] or nil
    if racialBundleEntry and legacyRacialChoices then
        local saved = type(racialBundleEntry.bundleChoicesByContext) == "table"
            and racialBundleEntry.bundleChoicesByContext or {}
        racialBundleEntry.bundleChoicesByContext = saved
        for raceToken, choices in pairs(legacyRacialChoices) do
            if type(raceToken) == "string" and type(choices) == "table" then
                local target = type(saved[raceToken]) == "table"
                    and saved[raceToken] or {}
                saved[raceToken] = target
                for spellID, enabled in pairs(choices) do
                    target[spellID] = enabled ~= false
                end
            end
        end
        profile.racials.choicesByRace = nil
    end

    if needsV39SpecializationOwnershipMigration
        or type(profile.sharedContent) == "table" then
        MigrateV38SpecializationOwnership(profile, specKey)
    end

    profile.entries = nil
    profile.monitors = nil
    profile.groupMembers = nil
    profile.customMonitors = nil
    profile.initialization = nil
    profile.suppressedOfficial = nil
    profile.groups.categoryClaims = nil
    for _, group in pairs(groups) do group.monitors = nil end

    profile.sharedContent = nil

    for contentSpecKey, content in pairs(profile.contentBySpec) do
        if IsStableSpecKey(contentSpecKey) then
            content = NormalizeContent(
                profile,
                content,
                self.CONTENT_SCOPE_SPEC,
                contentSpecKey
            )
            EnsureMigratedCooldownGroup(profile, content)
            profile.contentBySpec[contentSpecKey] =
                NormalizeContent(
                    profile,
                    content,
                    self.CONTENT_SCOPE_SPEC,
                    contentSpecKey
                )
            profile.contentBySpec[contentSpecKey].projectionOrder = nil
        else
            profile.contentBySpec[contentSpecKey] = nil
        end
    end
    NormalizeDefaultPresetState(profile, sourceVersion)
    for contentSpecKey, content in pairs(profile.contentBySpec) do
        self:MaterializeDefaultSlotPresets(
            profile,
            content,
            contentSpecKey
        )
    end
    profile.contentPolicyRevision =
        tonumber(self.CONTENT_POLICY_REVISION) or 4

    normalizedOrder = {}
    seenGroups = {}
    for index = 1, #profile.groups.order do
        local groupId = profile.groups.order[index]
        if groups[groupId] and not seenGroups[groupId] then
            normalizedOrder[#normalizedOrder + 1] = groupId
            seenGroups[groupId] = true
            groups[groupId].order = #normalizedOrder
        end
    end
    profile.groups.order = normalizedOrder

    local diagnostics = profile.diagnostics
    diagnostics.enabled = diagnostics.enabled == true
    diagnostics.detail = diagnostics.enabled and diagnostics.detail == true or false
    resources.selectionDefault = "catalog"
    resources.enabled = nil
    resources.singleton = nil
    local normalizedResourceGroups = { [self.GROUP_IDS.RESOURCES] = resources }
    for groupId, group in pairs(groups) do
        if group.layout == "resource" and groupId ~= self.GROUP_IDS.RESOURCES then
            group.singleton = nil
            local config = byGroup and byGroup[groupId] or {}
            config = type(config) == "table" and config or {}
            config.selectionDefault = "none"
            self:MigrateClientSpecializationKeys({ resources = config })
            config.bySpec = resourceCatalog and resourceCatalog:NormalizeSelections(config.bySpec) or {}
            config.orderBySpec = resourceCatalog and resourceCatalog:NormalizeOrders(config.orderBySpec) or {}
            config.formOverrides = resourceCatalog and resourceCatalog:NormalizeFormOverrides(config.formOverrides) or {}
            local settings = type(config.settingsByResource) == "table" and config.settingsByResource or {}
            if config.settingsDeltaVersion == RESOURCE_SETTINGS_DELTA_VERSION then
                local style = profile.style.groups[groupId]
                settings = MaterializeResourceSettingDeltas(settings, resourceCatalog, style and style.borderColor)
            end
            local normalized = {}
            for resourceId, setting in pairs(settings) do
                if resourceCatalog and resourceCatalog:GetDefinition(resourceId) then
                    normalized[resourceId] = self:NormalizeResourceSetting(setting, resourceId)
                end
            end
            config.settingsByResource = normalized
            config.settingsDeltaVersion = nil
            config.enabled = nil
            config.singleton = nil
            normalizedResourceGroups[groupId] = config
        end
    end
    profile.resources = { byGroup = normalizedResourceGroups }
    return profile
end

-- Character preferences are intentionally outside the ConfigSets profile.
function YHUD:LoadConsolePreferences()
    local db = YUI.DB and YUI.DB.GetAceDB
        and YUI.DB:GetAceDB(self.PRODUCT_ID)
    local charKey = db and db.keys and db.keys.char
    if type(charKey) ~= "string" or charKey == ""
        or type(db.global) ~= "table" then
        return nil, "character-storage-unavailable"
    end
    local root = db.global.consolePreferences
    if type(root) ~= "table" then
        root = { characters = {} }
        db.global.consolePreferences = root
    end
    if type(root.characters) ~= "table" then root.characters = {} end
    local preferences = root.characters[charKey]
    if type(preferences) ~= "table" then
        preferences = {}
        root.characters[charKey] = preferences
    end
    preferences.autoHidePersonalResource = preferences.autoHidePersonalResource ~= false
    preferences.soundEnabled = preferences.soundEnabled ~= false
    self.consolePreferences = preferences
    self.monitorSoundEnabled = self.Client.soundReminders ~= false and preferences.soundEnabled
    return preferences
end

function YHUD:GetConsolePreference(key)
    if key == "soundEnabled" and self.Client.soundReminders == false then return false end
    if key == "soundEnabled" and YUI.Sound and YUI.Sound.GetPreferences then
        local sound = YUI.Sound:GetPreferences()
        if sound then return sound.enabled end
    end
    local preferences = self.consolePreferences or self:LoadConsolePreferences()
    return not preferences or preferences[key] ~= false
end

function YHUD:SetConsolePreference(key, value)
    if key == "soundEnabled" and self.Client.soundReminders == false then return false, "sound-unavailable-client" end
    if key == "soundEnabled" and YUI.Sound and YUI.Sound.SetPreferences then
        local sound, code = YUI.Sound:GetPreferences()
        if not sound then return false, code end
        sound.enabled = value == true
        return YUI.Sound:SetPreferences(sound)
    end
    if key ~= "autoHidePersonalResource" and key ~= "soundEnabled" then
        return false, "unknown-console-preference"
    end
    local preferences, code = self:LoadConsolePreferences()
    if not preferences then return false, code end
    value = value == true
    if preferences[key] == value then return true end
    preferences[key] = value
    self.monitorSoundEnabled = self.Client.soundReminders ~= false and preferences.soundEnabled
    if key == "autoHidePersonalResource" and self.BlizzardSettings then
        self.BlizzardSettings:ApplyPersonalResource("console-preference")
    end
    return true
end

function YHUD:MergeDefaults(db)
    if self.IS_STANDALONE then db.enabled = true end
    if self._mergedDB == db and self._mergedDBProfile == db.profile then
        return db
    end
    if db.enabled == nil then db.enabled = self.Defaults.enabled end
    if db.schemaVersion == nil then
        db.schemaVersion = self.Defaults.schemaVersion
    end
    if db.profileVersion == nil then
        db.profileVersion = self.Defaults.profileVersion
    end
    if type(db.profile) ~= "table" then
        db.profile = CopyValue(DEFAULT_PROFILE)
    end
    db.enabled = db.enabled == true
    db.schemaVersion = self.SCHEMA_VERSION
    db.profileVersion = self.PROFILE_VERSION
    local configSets = self.ConfigSets
    local normalized, code
    if configSets and type(configSets.NormalizeRuntimeProfile) == "function" then
        normalized, code = configSets:NormalizeRuntimeProfile(
            db.profile,
            self:GetCurrentSpecKey(),
            true
        )
    else
        normalized, code = self:NormalizeProfile(
            db.profile,
            self:GetCurrentSpecKey()
        )
    end
    if not normalized then return db, code end
    db.profile = normalized
    self._mergedDB = db
    self._mergedDBProfile = db.profile
    self:InvalidateRuntimeProfile()
    return db
end

function YHUD:GetProfile()
    if YUI.DB and YUI.DB.GetProfile then
        local profile = YUI.DB:GetProfile(self.PRODUCT_ID)
        if type(profile) == "table" then return profile end
    end
    return nil
end

function YHUD:InvalidateDBCache()
    self.db = nil
    self._mergedDB = nil
    self._mergedDBProfile = nil
    return true
end

function YHUD:EnsureDB(force)
    if force ~= true
        and type(self.db) == "table"
        and self._mergedDB == self.db
        and self._mergedDBProfile == self.db.profile then
        return self.db
    end
    local profile = self:GetProfile()
    if type(profile) ~= "table" then
        self.db = self.db or self:CopyValue(self.Defaults)
        return self:MergeDefaults(self.db)
    end
    if type(profile[self.STORAGE_KEY]) ~= "table" then
        profile[self.STORAGE_KEY] = {}
    end
    self.db = profile[self.STORAGE_KEY]
    return self:MergeDefaults(self.db)
end

function YHUD:GetDB()
    return self:EnsureDB()
end

function YHUD:GetConfigProfile()
    local db = self:GetDB()
    return db and db.profile
end

function YHUD:GetActiveProfile(create)
    local profile = self:GetConfigProfile()
    if not profile then return nil, "profile-unavailable" end
    return self:GetRuntimeProfileForCurrentContext(profile, create)
end

function YHUD:ReplaceConfigProfile(profile)
    local db = self:GetDB()
    if not db then return nil, "db-unavailable" end
    local normalized = self:CopyValue(self:GetCanonicalProfile(profile))
    local configSets = self.ConfigSets
    if configSets and type(configSets.NormalizeRuntimeProfile) == "function"
        and type(normalized.specDocuments) == "table" then
        normalized._yhudSpecDocumentProjection = nil
        normalized.contentBySpec = {}
        local stored, code = configSets:NormalizeRuntimeProfile(
            normalized,
            self:GetCurrentSpecKey(),
            true
        )
        if not stored then return nil, code end
        db.profile = stored
    elseif configSets and type(configSets.NormalizeRuntimeProfile) == "function" then
        local stored, code = configSets:NormalizeRuntimeProfile(
            normalized,
            self:GetCurrentSpecKey(),
            true
        )
        if not stored then return nil, code end
        db.profile = stored
    else
        db.profile = self:NormalizeProfile(
            normalized,
            self:GetCurrentSpecKey()
        )
    end
    self._mergedDB = db
    self._mergedDBProfile = db.profile
    self:InvalidateRuntimeProfile()
    return db.profile
end

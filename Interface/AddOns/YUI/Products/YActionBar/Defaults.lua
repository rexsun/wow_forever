local YUI = _G.YUI
if not YUI then return end

local YAB = YUI.YActionBar or {}
YUI.YActionBar = YAB
local Client = assert(YAB.Client, "YActionBar client must load before shared runtime")
YAB.SPECIAL_BUTTON_MODE = Client.ownedStanceButtons == true and "owned-stance-template" or "native-reuse"

YAB.PRODUCT_ID = "yactionbar"
YAB.STORAGE_KEY = "YActionBar"
YAB.SETTINGS_ENTRY = "yactionbar.settings"
YAB.VERSION = "0.1.0"

YAB.BAR_ORDER = { "main", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8" }
YAB.SPECIAL_BAR_ORDER = { "pet", "stance", "possess", "extraAction", "zoneAbility", "vehicleExit" }
if Client.questItems == true then YAB.SPECIAL_BAR_ORDER[#YAB.SPECIAL_BAR_ORDER + 1] = "questItems" end
YAB.SPECIAL_GROUP_ID = "specialActionsGroup"
YAB.SPECIAL_GROUPING_MODE_INDEPENDENT = "independent"
YAB.SPECIAL_GROUPING_MODE_ALL = "all"
YAB.SPECIAL_GROUPING_MODE_ABILITIES = "abilities"

local SPECIAL_GROUPING_MODES = {
    [YAB.SPECIAL_GROUPING_MODE_INDEPENDENT] = true,
    [YAB.SPECIAL_GROUPING_MODE_ALL] = true,
    [YAB.SPECIAL_GROUPING_MODE_ABILITIES] = true,
}

local SPECIAL_GROUP_GROWTH_DIRECTIONS = {
    up = true,
    down = true,
    left = true,
    right = true,
}

local SPECIAL_GROUP_ALIGNMENTS = {
    start = true,
    center = true,
    ["end"] = true,
}

function YAB:NormalizeSpecialGroupingMode(value)
    if SPECIAL_GROUPING_MODES[value] then
        return value
    end
    return self.SPECIAL_GROUPING_MODE_INDEPENDENT
end

function YAB:GetSpecialGroupingMode(db)
    db = db or (self.GetDB and self:GetDB()) or nil
    local grouping = db and db.specialGrouping
    return self:NormalizeSpecialGroupingMode(grouping and grouping.mode)
end

function YAB:NormalizeSpecialGroupGrowthDirection(value)
    return SPECIAL_GROUP_GROWTH_DIRECTIONS[value] and value or "up"
end

function YAB:NormalizeSpecialGroupAlignment(value)
    return SPECIAL_GROUP_ALIGNMENTS[value] and value or "center"
end

function YAB:GetSpecialGroupConfig(db)
    db = db or (self.GetDB and self:GetDB()) or nil
    local grouping = db and db.specialGrouping
    return grouping and grouping.config or nil
end

function YAB:IsSpecialBarGrouped(barId, mode)
    mode = self:NormalizeSpecialGroupingMode(mode)
    if mode == self.SPECIAL_GROUPING_MODE_ALL then
        return barId == "zoneAbility" or barId == "extraAction" or barId == "vehicleExit"
    end
    if mode == self.SPECIAL_GROUPING_MODE_ABILITIES then
        return barId == "zoneAbility" or barId == "extraAction"
    end
    return false
end

local SPECIAL_BAR_RULES = {
    pet = {
        buttonMode = "configurable",
        defaultButtons = 10,
        minButtons = 1,
        maxButtons = 10,
        managedButtons = true,
        compactLayout = false,
        snapshotOverrides = {
            hideEmptySlots = false,
            showCounts = false,
            countSize = 12,
            countOffsetX = 0,
            countOffsetY = 0,
            showMacroNames = false,
            macroNameSize = 10,
            macroNameOffsetX = 0,
            macroNameOffsetY = 0,
        },
    },
    stance = {
        buttonMode = "runtime",
        defaultButtons = 10,
        minButtons = 1,
        maxButtons = 10,
        retailCapacity = 10,
        presentationCapacity = 10,
        managedButtons = true,
        compactLayout = true,
        retailSnapshotOverrides = {
            hideEmptySlots = false,
            rangeMode = "none",
            showCounts = false,
            countSize = 12,
            countOffsetX = 0,
            countOffsetY = 0,
            showMacroNames = false,
            macroNameSize = 10,
            macroNameOffsetX = 0,
            macroNameOffsetY = 0,
        },
    },
    possess = {
        buttonMode = "legacy-configurable",
        defaultButtons = 2,
        minButtons = 1,
        maxButtons = 12,
        managedButtons = true,
        keybindable = false,
        compactLayout = true,
    },
    extraAction = {
        buttonMode = "fixed",
        fixedButtons = 1,
        previewButtons = 1,
        keybindable = true,
        snapshotOverrides = {
            hideEmptySlots = false,
            rows = 1,
            spacing = 4,
            alignment = "left",
            showMacroNames = false,
            macroNameSize = 10,
            macroNameOffsetX = 0,
            macroNameOffsetY = 0,
        },
        nonRetailSnapshotOverrides = {
            cooldownTextSize = 0,
        },
    },
    zoneAbility = {
        buttonMode = "external",
        previewButtons = 2,
        keybindable = false,
        snapshotOverrides = {
            buttons = 1,
            hideEmptySlots = false,
            rows = 1,
            alignment = "left",
            rangeMode = "none",
            showHotkeys = false,
            hotkeySize = 12,
            hotkeyOffsetX = 0,
            hotkeyOffsetY = 0,
            showMacroNames = false,
            macroNameSize = 10,
            macroNameOffsetX = 0,
            macroNameOffsetY = 0,
        },
        nonRetailSnapshotOverrides = {
            cooldownTextSize = 0,
            cooldownTextOffsetX = 0,
            cooldownTextOffsetY = 0,
        },
    },
    vehicleExit = {
        buttonMode = "fixed",
        fixedButtons = 1,
        previewButtons = 1,
        keybindable = false,
        snapshotOverrides = {
            hideEmptySlots = false,
            hideSkyriding = false,
            rows = 1,
            spacing = 4,
            alignment = "left",
            iconZoom = 0.08,
            cooldownFade = true,
            cooldownTextSize = 0,
            cooldownTextOffsetX = 0,
            cooldownTextOffsetY = 0,
            rangeMode = "none",
            showHotkeys = false,
            hotkeySize = 12,
            hotkeyOffsetX = 0,
            hotkeyOffsetY = 0,
            showCounts = false,
            countSize = 12,
            countOffsetX = 0,
            countOffsetY = 0,
            showMacroNames = false,
            macroNameSize = 10,
            macroNameOffsetX = 0,
            macroNameOffsetY = 0,
        },
    },
}

local SpecialBars = YAB.SpecialBars or {}
if Client.questItems == true then
    SPECIAL_BAR_RULES.questItems = {
        buttonMode = "runtime", managedButtons = true, compactLayout = false,
        keybindable = false, previewButtons = 3,
        capabilities = { enabled = true, visibility = true, size = true, spacing = true, rows = true,
            alignment = true, skin = true, iconZoom = true, border = true, borderColor = true,
            background = true, backgroundColor = true, shadow = true, shadowColor = true,
            cooldownFade = true, cooldownTextSize = true, cooldownTextOffsetX = true,
            cooldownTextOffsetY = true, showCounts = true, countSize = true,
            countOffsetX = true, countOffsetY = true },
        snapshotOverrides = { hideEmptySlots = false, showHotkeys = false,
            showMacroNames = false, rangeMode = "none" },
    }
end
YAB.SpecialBars = SpecialBars
SpecialBars.rules = SPECIAL_BAR_RULES

local function ClampSpecialButtonCount(value, minimum, maximum, fallback)
    local count = math.floor(tonumber(value) or tonumber(fallback) or minimum or 1)
    if minimum and count < minimum then count = minimum end
    if maximum and count > maximum then count = maximum end
    return count
end

local function GetRuntimeStanceCount(rule, config, snapshot)
    local adapter = YAB.Adapter
    local getForms = adapter and adapter.GetNumShapeshiftForms
    local actual
    if type(getForms) == "function" then
        actual = tonumber(getForms(adapter))
    elseif type(_G.GetNumShapeshiftForms) == "function" then
        actual = tonumber(_G.GetNumShapeshiftForms())
    end
    if actual == nil then
        if Client.ownedStanceButtons == true then
            return rule.retailCapacity or rule.presentationCapacity or rule.defaultButtons
        end
        return ClampSpecialButtonCount(
            snapshot and snapshot.buttons or config and config.buttons,
            rule.minButtons,
            rule.maxButtons,
            rule.defaultButtons
        )
    end

    actual = math.floor(actual)
    if actual < 0 then actual = 0 end
    local capacity = Client.ownedStanceButtons == true
        and (rule.retailCapacity or rule.presentationCapacity or rule.maxButtons)
        or ClampSpecialButtonCount(
            snapshot and snapshot.buttons or config and config.buttons,
            rule.minButtons,
            rule.maxButtons,
            rule.defaultButtons
        )
    if capacity and actual > capacity then actual = capacity end
    return actual
end

function SpecialBars:GetRule(barId)
    return SPECIAL_BAR_RULES[barId]
end

function SpecialBars:IsRuntimeKeybindable(barId)
    local rule = SPECIAL_BAR_RULES[barId]
    if not rule then return true end
    return rule.keybindable ~= false
end

function SpecialBars:GetRuntimeButtonCount(barId, config, snapshot)
    local rule = SPECIAL_BAR_RULES[barId]
    if not rule then return nil end
    if barId == "stance" then
        return GetRuntimeStanceCount(rule, config, snapshot)
    end
    if barId == "questItems" then
        local record = YAB.QuestItems and YAB.QuestItems.record
        return math.max(record and #record.buttons or 0, 1)
    end
    if rule.fixedButtons then
        return rule.fixedButtons
    end
    if rule.buttonMode == "external" then
        return nil
    end
    return ClampSpecialButtonCount(
        snapshot and snapshot.buttons or config and config.buttons,
        rule.minButtons,
        rule.maxButtons,
        rule.defaultButtons
    )
end

function SpecialBars:GetPlayerClassToken()
    local unitAPI = YUI.API and YUI.API.Unit
    if unitAPI and type(unitAPI.UnitClass) == "function" then
        local _, token = unitAPI.UnitClass("player")
        if type(token) == "string" then return token end
    end
    if type(UnitClass) == "function" then
        local _, token = UnitClass("player")
        if type(token) == "string" then return token end
    end
    return nil
end

function SpecialBars:GetEditModeButtonCount(barId, config, snapshot)
    local rule = SPECIAL_BAR_RULES[barId]
    if not rule then return nil end
    if barId == "pet" then
        return rule.maxButtons or rule.defaultButtons or 10
    end
    if barId == "stance" then
        return rule.presentationCapacity or 10
    end
    return self:GetRuntimeButtonCount(barId, config, snapshot)
end

local function ApplySnapshotOverrides(snapshot, overrides)
    for key, value in pairs(overrides or {}) do
        snapshot[key] = value
    end
end

function SpecialBars:NormalizeConfigSnapshot(barId, snapshot, config)
    if type(snapshot) ~= "table" then return snapshot end
    local rule = SPECIAL_BAR_RULES[barId]
    if not rule then return snapshot end

    if barId == "pet" or rule.fixedButtons or Client.deterministicSpecialBars == true then
        local buttonCount = barId == "stance" and Client.ownedStanceButtons == true
            and (rule.retailCapacity or rule.presentationCapacity or rule.defaultButtons)
            or self:GetRuntimeButtonCount(barId, config, snapshot)
        if buttonCount then snapshot.buttons = buttonCount end
    end
    ApplySnapshotOverrides(snapshot, rule.snapshotOverrides)
    if Client.deterministicSpecialBars == true then
        ApplySnapshotOverrides(snapshot, rule.retailSnapshotOverrides)
    else
        ApplySnapshotOverrides(snapshot, rule.nonRetailSnapshotOverrides)
    end
    if barId ~= "questItems" and (barId == "pet" or Client.deterministicSpecialBars == true) and snapshot.buttons then
        local rowValue = snapshot.rows
        if barId == "pet" or (barId == "stance" and Client.ownedStanceButtons == true) then
            rowValue = config and config.rows or rowValue
        end
        snapshot.rows = ClampSpecialButtonCount(rowValue, 1, snapshot.buttons, 1)
    end
    return snapshot
end

function SpecialBars:GetPreviewButtonCount(barId, config, snapshot)
    local rule = SPECIAL_BAR_RULES[barId]
    if not rule then return nil end
    if barId == "pet" then
        return self:GetRuntimeButtonCount(barId, config, snapshot)
    end
    if barId == "questItems" then return self:GetRuntimeButtonCount(barId, config, snapshot) end
    return rule.previewButtons
end

local function CopyValue(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = CopyValue(item)
    end
    return result
end

local function FillDefaults(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then
        return target
    end
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = CopyValue(value)
        elseif type(target[key]) == "table" and type(value) == "table" then
            FillDefaults(target[key], value)
        end
    end
    return target
end

local function ApplyOverrides(target, overrides)
    if type(target) ~= "table" or type(overrides) ~= "table" then
        return target
    end
    for key, value in pairs(overrides) do
        if type(value) == "table" and type(target[key]) == "table" then
            ApplyOverrides(target[key], value)
        else
            target[key] = CopyValue(value)
        end
    end
    return target
end

local TEXT_DEFAULTS = {
    hotkeyOffsetX = 0,
    hotkeyOffsetY = 0,
    countOffsetX = 0,
    countOffsetY = 0,
    macroNameOffsetX = 0,
    macroNameOffsetY = 0,
    cooldownTextOffsetX = 0,
    cooldownTextOffsetY = 0,
    cooldownTextSize = 12,
}

local PROFESSION_QUALITY_BASELINE_DEFAULTS = {
    showProfessionQuality = true,
    professionQualitySize = 16,
    professionQualityOffsetX = 0,
    professionQualityOffsetY = 0,
}

local PROFESSION_QUALITY_DEFAULTS = {
    showProfessionQuality = true,
    professionQualitySize = 21,
    professionQualityOffsetX = 0,
    professionQualityOffsetY = 0,
}

local function FillTextDefaults(config)
    if type(config) ~= "table" then return end
    FillDefaults(config, TEXT_DEFAULTS)
end

YAB.Defaults = {
    enabled = false,
    nativeMode = false,
    activeRecipe = "default",
    runtime = {
        blocked = false,
        blockedReason = nil,
        degraded = {},
        reloadRequired = false,
        reloadRequiredReason = nil,
        deferredOperation = nil,
        deferredMode = nil,
        nativeSuppressionMode = "none",
        takeoverMode = "strong",
        specialButtonMode = YAB.SPECIAL_BUTTON_MODE,
    },
    bars = {
        main = {
            enabled = true,
            kind = "action",
            label = "动作条 1",
            page = 1,
            paging = true,
            buttons = 12,
            rows = 1,
            size = 36,
            spacing = 4,
            alignment = "left",
            alpha = 1,
            visibility = "always",
            hideEmptySlots = false,
            hideSkyriding = false,
            skin = "square",
            iconZoom = 0.08,
            border = "thin",
            borderColor = { 0, 0, 0, 1 },
            background = "black",
            cooldownFade = true,
            rangeMode = "red",
            showHotkeys = true,
            hotkeySize = 12,
            showCounts = true,
            countSize = 12,
            showMacroNames = true,
            macroNameSize = 10,
            layout = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 38 },
        },
        bar2 = {
            enabled = true,
            kind = "action",
            label = "动作条 2",
            page = 6,
            paging = false,
            buttons = 12,
            rows = 1,
            size = 34,
            spacing = 4,
            alignment = "left",
            alpha = 1,
            visibility = "always",
            hideEmptySlots = false,
            hideSkyriding = false,
            skin = "square",
            iconZoom = 0.08,
            border = "thin",
            borderColor = { 0, 0, 0, 1 },
            background = "black",
            cooldownFade = true,
            rangeMode = "red",
            showHotkeys = true,
            hotkeySize = 12,
            showCounts = true,
            countSize = 12,
            showMacroNames = true,
            macroNameSize = 10,
            layout = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 80 },
        },
        bar3 = {
            enabled = true,
            kind = "action",
            label = "动作条 3",
            page = 5,
            paging = false,
            buttons = 12,
            rows = 1,
            size = 34,
            spacing = 4,
            alignment = "left",
            alpha = 1,
            visibility = "always",
            hideEmptySlots = false,
            hideSkyriding = false,
            skin = "square",
            iconZoom = 0.08,
            border = "thin",
            borderColor = { 0, 0, 0, 1 },
            background = "black",
            cooldownFade = true,
            rangeMode = "red",
            showHotkeys = true,
            hotkeySize = 12,
            showCounts = true,
            countSize = 12,
            showMacroNames = true,
            macroNameSize = 10,
            layout = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 122 },
        },
        bar4 = {
            enabled = false,
            kind = "action",
            label = "动作条 4",
            page = 3,
            paging = false,
            buttons = 12,
            rows = 12,
            size = 34,
            spacing = 4,
            alignment = "left",
            alpha = 1,
            visibility = "always",
            hideEmptySlots = false,
            hideSkyriding = false,
            skin = "square",
            iconZoom = 0.08,
            border = "thin",
            borderColor = { 0, 0, 0, 1 },
            background = "black",
            cooldownFade = true,
            rangeMode = "red",
            showHotkeys = true,
            hotkeySize = 12,
            showCounts = true,
            countSize = 12,
            showMacroNames = true,
            macroNameSize = 10,
            layout = { point = "RIGHT", relativePoint = "RIGHT", x = -42, y = 0 },
        },
        bar5 = {
            enabled = false,
            kind = "action",
            label = "动作条 5",
            page = 4,
            paging = false,
            buttons = 12,
            rows = 12,
            size = 34,
            spacing = 4,
            alignment = "left",
            alpha = 1,
            visibility = "always",
            hideEmptySlots = false,
            hideSkyriding = false,
            skin = "square",
            iconZoom = 0.08,
            border = "thin",
            borderColor = { 0, 0, 0, 1 },
            background = "black",
            cooldownFade = true,
            rangeMode = "red",
            showHotkeys = true,
            hotkeySize = 12,
            showCounts = true,
            countSize = 12,
            showMacroNames = true,
            macroNameSize = 10,
            layout = { point = "RIGHT", relativePoint = "RIGHT", x = -82, y = 0 },
        },
        bar6 = {
            enabled = false,
            kind = "action",
            label = "动作条 6",
            page = 13,
            paging = false,
            buttons = 12,
            rows = 12,
            size = 34,
            spacing = 4,
            alignment = "left",
            alpha = 1,
            visibility = "always",
            hideEmptySlots = false,
            hideSkyriding = false,
            skin = "square",
            iconZoom = 0.08,
            border = "thin",
            borderColor = { 0, 0, 0, 1 },
            background = "black",
            cooldownFade = true,
            rangeMode = "red",
            showHotkeys = true,
            hotkeySize = 12,
            showCounts = true,
            countSize = 12,
            showMacroNames = true,
            macroNameSize = 10,
            layout = { point = "RIGHT", relativePoint = "RIGHT", x = -122, y = 0 },
        },
        bar7 = {
            enabled = false,
            kind = "action",
            label = "动作条 7",
            page = 14,
            paging = false,
            buttons = 12,
            rows = 12,
            size = 34,
            spacing = 4,
            alignment = "left",
            alpha = 1,
            visibility = "always",
            hideEmptySlots = false,
            hideSkyriding = false,
            skin = "square",
            iconZoom = 0.08,
            border = "thin",
            borderColor = { 0, 0, 0, 1 },
            background = "black",
            cooldownFade = true,
            rangeMode = "red",
            showHotkeys = true,
            hotkeySize = 12,
            showCounts = true,
            countSize = 12,
            showMacroNames = true,
            macroNameSize = 10,
            layout = { point = "RIGHT", relativePoint = "RIGHT", x = -162, y = 0 },
        },
        bar8 = {
            enabled = false,
            kind = "action",
            label = "动作条 8",
            page = 15,
            paging = false,
            buttons = 12,
            rows = 12,
            size = 34,
            spacing = 4,
            alignment = "left",
            alpha = 1,
            visibility = "always",
            hideEmptySlots = false,
            hideSkyriding = false,
            skin = "square",
            iconZoom = 0.08,
            border = "thin",
            borderColor = { 0, 0, 0, 1 },
            background = "black",
            cooldownFade = true,
            rangeMode = "red",
            showHotkeys = true,
            hotkeySize = 12,
            showCounts = true,
            countSize = 12,
            showMacroNames = true,
            macroNameSize = 10,
            layout = { point = "RIGHT", relativePoint = "RIGHT", x = -202, y = 0 },
        },
    },
    specialBars = {
        pet = {
            enabled = true,
            label = "宠物条",
            buttons = 10,
            rows = 1,
            size = 30,
            spacing = 4,
            alignment = "left",
            visibility = "always",
            hideEmptySlots = false,
            hideSkyriding = false,
            skin = "square",
            iconZoom = 0.08,
            border = "thin",
            borderColor = { 0, 0, 0, 1 },
            background = "black",
            cooldownFade = true,
            rangeMode = "red",
            showHotkeys = true,
            hotkeySize = 12,
            showCounts = true,
            countSize = 12,
            showMacroNames = true,
            macroNameSize = 10,
            layout = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 164 },
        },
        stance = {
            enabled = true,
            label = "姿态/形态条",
            buttons = 10,
            rows = 1,
            size = 30,
            spacing = 4,
            alignment = "center",
            visibility = "always",
            hideEmptySlots = false,
            hideSkyriding = false,
            skin = "square",
            iconZoom = 0.08,
            border = "thin",
            borderColor = { 0, 0, 0, 1 },
            background = "black",
            cooldownFade = true,
            rangeMode = "red",
            showHotkeys = true,
            hotkeySize = 12,
            showCounts = true,
            countSize = 12,
            showMacroNames = true,
            macroNameSize = 10,
            layout = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 198 },
        },
        possess = {
            enabled = true,
            label = "控制条",
            buttons = 2,
            rows = 1,
            size = 30,
            spacing = 4,
            alignment = "left",
            visibility = "always",
            hideEmptySlots = false,
            hideSkyriding = false,
            skin = "square",
            iconZoom = 0.08,
            border = "thin",
            borderColor = { 0, 0, 0, 1 },
            background = "black",
            cooldownFade = true,
            rangeMode = "red",
            showHotkeys = true,
            hotkeySize = 12,
            showCounts = true,
            countSize = 12,
            showMacroNames = true,
            macroNameSize = 10,
            layout = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 232 },
        },
        extraAction = {
            enabled = true,
            label = "额外动作",
            buttons = 1,
            rows = 1,
            size = 52,
            spacing = 4,
            alignment = "left",
            visibility = "always",
            hideEmptySlots = false,
            hideSkyriding = false,
            skin = "blizzard",
            iconZoom = 0.08,
            border = "thin",
            borderColor = { 0, 0, 0, 1 },
            background = "black",
            cooldownFade = true,
            rangeMode = "red",
            showHotkeys = true,
            hotkeySize = 12,
            showCounts = true,
            countSize = 12,
            showMacroNames = true,
            macroNameSize = 10,
            layout = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -180 },
        },
        zoneAbility = {
            enabled = true,
            label = "区域能力",
            buttons = 1,
            rows = 1,
            size = 52,
            spacing = 4,
            alignment = "left",
            visibility = "always",
            hideEmptySlots = false,
            hideSkyriding = false,
            skin = "square",
            iconZoom = 0.08,
            border = "thin",
            borderColor = { 0, 0, 0, 1 },
            background = "black",
            cooldownFade = true,
            rangeMode = "red",
            showHotkeys = true,
            hotkeySize = 12,
            showCounts = true,
            countSize = 12,
            showMacroNames = true,
            macroNameSize = 10,
            layout = { point = "CENTER", relativePoint = "CENTER", x = 64, y = -180 },
        },
        vehicleExit = {
            enabled = true,
            label = "离开载具",
            buttons = 1,
            rows = 1,
            size = 32,
            spacing = 4,
            alignment = "left",
            visibility = "always",
            hideEmptySlots = false,
            hideSkyriding = false,
            skin = "square",
            iconZoom = 0.08,
            border = "thin",
            borderColor = { 0, 0, 0, 1 },
            background = "black",
            cooldownFade = true,
            rangeMode = "red",
            showHotkeys = true,
            hotkeySize = 12,
            showCounts = true,
            countSize = 12,
            showMacroNames = true,
            macroNameSize = 10,
            layout = { point = "CENTER", relativePoint = "CENTER", x = -64, y = -180 },
        },
    },
    appearance = {
        skin = "default",
        buttonSize = 36,
        spacing = 4,
        iconZoom = 0.08,
        pressedEffect = "darken",
        showHotkeys = true,
        showCounts = true,
        showMacroNames = true,
        showAuraTimers = false,
        outOfCombatAlpha = 1,
        nativeMode = false,
    },
    interaction = {
        tooltipMode = "always",
        autoRankUpgrade = Client.rankUpgrade == true and true or nil,
    },
    specialGrouping = {
        mode = "independent",
        config = {
            enabled = true,
            label = "特殊动作条组",
            size = 52,
            spacing = 4,
            growthDirection = "up",
            groupAlignment = "center",
            visibility = "always",
            hideEmptySlots = false,
            hideSkyriding = false,
            skin = "square",
            iconZoom = 0.08,
            border = "thin",
            borderColor = { 0, 0, 0, 1 },
            background = "black",
            cooldownFade = true,
            rangeMode = "red",
            showHotkeys = true,
            hotkeySize = 12,
            showCounts = true,
            countSize = 12,
            showMacroNames = true,
            macroNameSize = 10,
        },
    },
    recipes = {
        lastApplied = nil,
        previewing = nil,
        snapshot = nil,
    },
    keybinds = {
        enabled = true,
        bindings = {},
        pending = {},
    },
    conflict = {
        last = nil,
    },
    debug = {
        enabled = false,
        verbose = false,
    },
}

for _, config in pairs(YAB.Defaults.bars or {}) do
    FillTextDefaults(config)
    FillDefaults(config, PROFESSION_QUALITY_BASELINE_DEFAULTS)
end
for _, config in pairs(YAB.Defaults.specialBars or {}) do
    FillTextDefaults(config)
end
FillTextDefaults(YAB.Defaults.specialGrouping and YAB.Defaults.specialGrouping.config)

-- ConfigSets schema 2 stores sparse deltas against the original baseline. Keep
-- that source immutable while the runtime defaults move to the YUI preset.
YAB.ConfigSetBaselineDefaultsV1 = CopyValue(YAB.Defaults)

-- Optional Forever bar is outside the immutable ConfigSets V1 baseline.
if Client.questItems == true then
    local config = CopyValue(YAB.Defaults.specialBars.zoneAbility)
    ApplyOverrides(config, { label = "任务物品", size = 40, spacing = 4,
        skin = "roundedSquare", showHotkeys = false, showMacroNames = false,
        rangeMode = "none", layout = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 200 } })
    YAB.Defaults.specialBars.questItems = config
end

local BUTTON_APPEARANCE_DEFAULTS = {
    shadow = true,
    backgroundColor = { 34 / 255, 34 / 255, 34 / 255, 0.72 },
}
for _, config in pairs(YAB.Defaults.bars or {}) do
    FillDefaults(config, BUTTON_APPEARANCE_DEFAULTS)
end
for _, config in pairs(YAB.Defaults.specialBars or {}) do
    FillDefaults(config, BUTTON_APPEARANCE_DEFAULTS)
end
FillDefaults(YAB.Defaults.specialGrouping and YAB.Defaults.specialGrouping.config, BUTTON_APPEARANCE_DEFAULTS)

for _, config in pairs(YAB.Defaults.bars or {}) do
    ApplyOverrides(config, PROFESSION_QUALITY_DEFAULTS)
end

ApplyOverrides(YAB.Defaults, {
    bars = {
        main = {
            spacing = 0,
            countSize = 16,
            countOffsetX = 3,
            countOffsetY = -3,
            macroNameSize = 12,
        },
        bar2 = {
            size = 36,
            spacing = 0,
            countSize = 16,
            countOffsetX = 3,
            countOffsetY = -3,
            macroNameSize = 12,
        },
        bar3 = {
            size = 36,
            spacing = 0,
            countSize = 16,
            countOffsetX = 3,
            countOffsetY = -3,
            macroNameSize = 12,
        },
        bar4 = {
            enabled = true,
            rows = 3,
            size = 32,
            spacing = 0,
            visibility = "mouseover",
            countSize = 14,
            countOffsetX = 4,
            countOffsetY = -4,
            macroNameSize = 12,
        },
        bar5 = {
            enabled = true,
            rows = 3,
            size = 32,
            spacing = 0,
            visibility = "mouseover",
            countSize = 14,
            countOffsetX = 4,
            countOffsetY = -4,
            macroNameSize = 12,
        },
    },
    specialBars = {
        pet = {
            size = 25,
            spacing = 0,
        },
        stance = {
            spacing = 0,
            skin = "flatSquare",
        },
        extraAction = {
            size = 48,
            skin = "roundedSquare",
        },
        zoneAbility = {
            size = 48,
            skin = "roundedSquare",
        },
        vehicleExit = {
            size = 48,
        },
    },
    specialGrouping = {
        mode = "all",
        config = {
            spacing = 0,
            groupAlignment = "start",
            skin = "roundedSquare",
        },
    },
})

local function YUIDefaultPlacement(point, relative, relativePoint, x, y, fallbackX, fallbackY)
    return {
        version = 2,
        anchor = {
            point = point,
            relative = relative,
            relativePoint = relativePoint,
        },
        offset = { x = x, y = y },
        fallback = {
            version = 2,
            anchor = {
                point = "BOTTOM",
                relative = "UIParent",
                relativePoint = "BOTTOM",
            },
            offset = { x = fallbackX, y = fallbackY },
        },
    }
end

YAB.DefaultPlacements = {
    ["yactionbar.main"] = YUIDefaultPlacement(
        "BOTTOM", "UIParent", "BOTTOM", 0, 3, -11, 38
    ),
    ["yactionbar.bar2"] = YUIDefaultPlacement(
        "BOTTOM", "YUI_YActionBar_Mover_main", "TOP", 0, 1, 0, 40
    ),
    ["yactionbar.bar3"] = YUIDefaultPlacement(
        "BOTTOM", "YUI_YActionBar_Mover_bar2", "TOP", 0, 1, 0, 77
    ),
    ["yactionbar.bar4"] = YUIDefaultPlacement(
        "BOTTOMRIGHT", "YUI_YActionBar_Mover_main", "BOTTOMLEFT", -5, 1, -285, 4
    ),
    ["yactionbar.bar5"] = YUIDefaultPlacement(
        "BOTTOMLEFT", "YUI_YActionBar_Mover_main", "BOTTOMRIGHT", 5, 1, 285, 4
    ),
    ["yactionbar.pet"] = YUIDefaultPlacement(
        "BOTTOMLEFT", "YUI_YActionBar_Mover_bar3", "TOPLEFT", 0, 33, -66, 146
    ),
    ["yactionbar.stance"] = YUIDefaultPlacement(
        "BOTTOMLEFT", "YUI_YActionBar_Mover_bar3", "TOPLEFT", 0, 2, -201, 115
    ),
    ["yactionbar.extraAction"] = YUIDefaultPlacement(
        "BOTTOM", "YUI_YActionBar_Mover_zoneAbility", "TOP", 0, 0, 190, 165
    ),
    ["yactionbar.zoneAbility"] = YUIDefaultPlacement(
        "BOTTOMLEFT", "YUI_YActionBar_Mover_main", "TOPRIGHT", 0, 150, 242, 189
    ),
    ["yactionbar.vehicleExit"] = YUIDefaultPlacement(
        "BOTTOM", "YUI_YActionBar_Mover_extraAction", "TOP", 0, 0, 190, 217
    ),
    ["yactionbar.specialActionsGroup"] = YUIDefaultPlacement(
        "BOTTOMRIGHT", "YUI_YActionBar_Mover_main", "TOPRIGHT", 0, 74, 190, 113
    ),
}
if Client.questItems == true then
    YAB.DefaultPlacements["yactionbar.questItems"] = YUIDefaultPlacement(
        "BOTTOM", "UIParent", "BOTTOM", 0, 200, 0, 200
    )
end

local function UpgradeVisibilityConfig(config)
    if config and type(config.visibility) ~= "table" and YUI.Visibility then
        config.visibility = YUI.Visibility:MigrateActionBar(config.visibility, config.hideSkyriding)
        config.hideSkyriding = false
    end
end

-- Preserve the frozen v1 baseline above; runtime defaults use the current schema.
for _, config in pairs(YAB.Defaults.bars or {}) do UpgradeVisibilityConfig(config) end
for _, config in pairs(YAB.Defaults.specialBars or {}) do UpgradeVisibilityConfig(config) end
UpgradeVisibilityConfig(YAB.Defaults.specialGrouping and YAB.Defaults.specialGrouping.config)

function YAB:CopyValue(value)
    return CopyValue(value)
end

function YAB:MergeDefaults(db)
    if type(db) ~= "table" then
        return db
    end
    FillDefaults(db, self.Defaults)
    if YUI.Visibility then
        for _, config in pairs(db.bars or {}) do UpgradeVisibilityConfig(config) end
        for _, config in pairs(db.specialBars or {}) do UpgradeVisibilityConfig(config) end
        UpgradeVisibilityConfig(db.specialGrouping and db.specialGrouping.config)
    end
    db.specialGrouping = db.specialGrouping or {}
    db.specialGrouping.mode = self:NormalizeSpecialGroupingMode(db.specialGrouping.mode)
    db.specialGrouping.config = db.specialGrouping.config or {}
    db.specialGrouping.config.enabled = true
    db.specialGrouping.config.growthDirection = self:NormalizeSpecialGroupGrowthDirection(db.specialGrouping.config.growthDirection)
    db.specialGrouping.config.groupAlignment = self:NormalizeSpecialGroupAlignment(db.specialGrouping.config.groupAlignment)
    return db
end

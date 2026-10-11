local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

local YAB = YUI.YActionBar
local Client = assert(YAB.Client, "YActionBar client must load before shared runtime")
local ConfigSets = {}
YAB.ConfigSets = ConfigSets
ConfigSets.dormantPlacements = {}
ConfigSets.dormantConfigOverrides = {}

ConfigSets.PROVIDER_ID = "yactionbar"
ConfigSets.SCHEMA_VERSION = 4
ConfigSets.BASELINE_VERSION = 1
ConfigSets.DEFAULT_BUILTIN_ID = "classic-three-row"

local BAR_IDS = YAB.BAR_ORDER or {
    "main", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8",
}
local SPECIAL_BAR_IDS = YAB.SPECIAL_BAR_ORDER or {
    "pet", "stance", "possess", "extraAction", "zoneAbility", "vehicleExit",
}
local SPECIAL_GROUP_ID = YAB.SPECIAL_GROUP_ID or "specialActionsGroup"

local SCOPE_ORDER = {
    "display",
    "layout",
    "appearance",
    "text",
    "global",
    "screenPosition",
}

local SCOPE_DEFINITIONS = {
    display = {
        labelKey = "config_sets.scope.display",
        label = "显示",
        defaultSelected = true,
    },
    layout = {
        labelKey = "config_sets.scope.layout",
        label = "布局",
        defaultSelected = true,
    },
    appearance = {
        labelKey = "config_sets.scope.appearance",
        label = "外观",
        defaultSelected = true,
    },
    text = {
        labelKey = "config_sets.scope.text",
        label = "文本",
        defaultSelected = true,
    },
    global = {
        labelKey = "config_sets.scope.global",
        label = "全局",
        defaultSelected = true,
    },
    screenPosition = {
        labelKey = "config_sets.scope.screen_positions",
        label = "屏幕位置",
        defaultSelected = true,
    },
}

local CONFIG_FIELDS = {
    display = {
        "enabled",
        "visibility",
        "hideEmptySlots",
        "hideSkyriding",
    },
    layout = {
        "buttons",
        "rows",
        "size",
        "spacing",
        "alignment",
    },
    appearance = {
        "skin",
        "iconZoom",
        "border",
        "borderColor",
        "background",
        "backgroundColor",
        "shadow",
        "shadowColor",
        "cooldownFade",
        "rangeMode",
    },
    text = {
        "showHotkeys",
        "hotkeyColor",
        "hotkeySize",
        "hotkeyOffsetX",
        "hotkeyOffsetY",
        "showCounts",
        "countColor",
        "countSize",
        "countOffsetX",
        "countOffsetY",
        "showMacroNames",
        "macroNameColor",
        "macroNameSize",
        "macroNameOffsetX",
        "macroNameOffsetY",
        "cooldownTextColor",
        "cooldownTextSize",
        "cooldownTextOffsetX",
        "cooldownTextOffsetY",
        "showProfessionQuality",
        "professionQualitySize",
        "professionQualityOffsetX",
        "professionQualityOffsetY",
    },
}

local SPECIAL_GROUP_FIELDS = {
    display = {
        "visibility",
        "hideSkyriding",
    },
    layout = {
        "size",
        "spacing",
        "growthDirection",
        "groupAlignment",
    },
    appearance = CONFIG_FIELDS.appearance,
    text = CONFIG_FIELDS.text,
}

local FIELD_SCOPE = {}
for scopeId, fields in pairs(CONFIG_FIELDS) do
    for _, field in ipairs(fields) do
        FIELD_SCOPE[field] = scopeId
    end
end
FIELD_SCOPE.growthDirection = "layout"
FIELD_SCOPE.groupAlignment = "layout"

local OPTIONAL_FIELDS = {
    backgroundColor = true,
    shadow = true,
    shadowColor = true,
    hotkeyColor = true,
    countColor = true,
    macroNameColor = true,
    cooldownTextColor = true,
}

local TEXT_COLOR_CAPABILITY = {
    hotkeyColor = "hotkeySize",
    countColor = "countSize",
    macroNameColor = "macroNameSize",
    cooldownTextColor = "cooldownTextSize",
}

local function MakeSet(values)
    local result = {}
    for _, value in ipairs(values or {}) do
        result[value] = true
    end
    return result
end

local ALL_CONFIG_CAPABILITIES = {}
for _, fields in pairs(CONFIG_FIELDS) do
    for _, field in ipairs(fields) do
        ALL_CONFIG_CAPABILITIES[field] = true
    end
end

local SPECIAL_CAPABILITIES = {
    pet = MakeSet({
        "enabled", "visibility", "hideSkyriding",
        "buttons", "size", "spacing", "alignment", "rows",
        "skin", "iconZoom", "border", "borderColor", "background", "backgroundColor", "shadow", "shadowColor", "cooldownFade", "rangeMode",
        "showHotkeys", "hotkeySize", "hotkeyOffsetX", "hotkeyOffsetY",
        "cooldownTextSize", "cooldownTextOffsetX", "cooldownTextOffsetY",
    }),
    extraAction = MakeSet({
        "enabled", "visibility", "hideSkyriding",
        "size",
        "skin", "iconZoom", "border", "borderColor", "background", "backgroundColor", "shadow", "shadowColor", "cooldownFade", "rangeMode",
        "showHotkeys", "hotkeySize", "hotkeyOffsetX", "hotkeyOffsetY",
        "showCounts", "countSize", "countOffsetX", "countOffsetY",
        "cooldownTextOffsetX", "cooldownTextOffsetY",
    }),
    zoneAbility = MakeSet({
        "enabled", "visibility", "hideSkyriding",
        "size", "spacing",
        "skin", "iconZoom", "border", "borderColor", "background", "backgroundColor", "shadow", "shadowColor", "cooldownFade",
        "showCounts", "countSize", "countOffsetX", "countOffsetY",
    }),
    vehicleExit = MakeSet({
        "enabled", "visibility",
        "size",
        "skin", "border", "borderColor", "background", "backgroundColor", "shadow", "shadowColor",
    }),
}

local RETAIL_SPECIAL_CAPABILITIES = {
    stance = MakeSet({
        "enabled", "visibility", "hideSkyriding",
        "size", "spacing", "alignment", "rows",
        "skin", "iconZoom", "border", "borderColor", "background", "backgroundColor", "shadow", "shadowColor", "cooldownFade",
        "showHotkeys", "hotkeySize", "hotkeyOffsetX", "hotkeyOffsetY",
        "cooldownTextSize", "cooldownTextOffsetX", "cooldownTextOffsetY",
    }),
    extraAction = MakeSet({
        "enabled", "visibility", "hideSkyriding",
        "size",
        "skin", "iconZoom", "border", "borderColor", "background", "backgroundColor", "shadow", "shadowColor", "cooldownFade", "rangeMode",
        "showHotkeys", "hotkeySize", "hotkeyOffsetX", "hotkeyOffsetY",
        "showCounts", "countSize", "countOffsetX", "countOffsetY",
        "cooldownTextSize", "cooldownTextOffsetX", "cooldownTextOffsetY",
    }),
    zoneAbility = MakeSet({
        "enabled", "visibility", "hideSkyriding",
        "size", "spacing",
        "skin", "iconZoom", "border", "borderColor", "background", "backgroundColor", "shadow", "shadowColor", "cooldownFade",
        "showCounts", "countSize", "countOffsetX", "countOffsetY",
        "cooldownTextSize", "cooldownTextOffsetX", "cooldownTextOffsetY",
    }),
    vehicleExit = SPECIAL_CAPABILITIES.vehicleExit,
}

local SPECIAL_GROUP_CAPABILITIES = MakeSet({
    "visibility", "hideSkyriding",
    "size", "spacing", "growthDirection", "groupAlignment",
    "skin", "iconZoom", "border", "borderColor", "background", "backgroundColor", "shadow", "shadowColor", "cooldownFade", "rangeMode",
    "showHotkeys", "hotkeySize", "hotkeyOffsetX", "hotkeyOffsetY",
    "showCounts", "countSize", "countOffsetX", "countOffsetY",
    "showMacroNames", "macroNameSize", "macroNameOffsetX", "macroNameOffsetY",
    "cooldownTextSize", "cooldownTextOffsetX", "cooldownTextOffsetY",
})

local VALID_VISIBILITY = MakeSet({
    "hidden", "always", "mouseover", "combat", "outOfCombat", "mounted", "unmounted",
})
local VALID_ALIGNMENT = MakeSet({ "left", "center", "right" })
local VALID_SKIN = MakeSet({ "square", "roundedSquare", "flatSquare", "flatRounded", "wideSquare", "wideRounded", "circle" })
local VALID_EXTRA_SKIN = MakeSet({ "blizzard", "square", "roundedSquare", "flatSquare", "flatRounded", "wideSquare", "wideRounded", "circle" })
local VALID_BORDER = MakeSet({ "none", "thin", "medium", "thick", "extraThick" })
local VALID_BACKGROUND = MakeSet({ "transparent", "black", "blizzard" })
local VALID_RANGE = MakeSet({ "none", "red" })
local VALID_PRESSED_EFFECT = MakeSet({ "darken", "innerGlow" })
local VALID_TOOLTIP_MODE = MakeSet({ "always", "outOfCombat" })
local VALID_GROUPING_MODE = MakeSet({ "independent", "all", "abilities" })
local VALID_BLIZZARD_ELEMENT_VISIBILITY = MakeSet({ "show", "hide" })
local VALID_GROWTH_DIRECTION = MakeSet({ "up", "down", "left", "right" })
local VALID_GROUP_ALIGNMENT = MakeSet({ "start", "center", "end" })
local VALID_ANCHOR_POINT = MakeSet({
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
})

local BOOLEAN_FIELDS = MakeSet({
    "enabled", "hideEmptySlots", "hideSkyriding", "cooldownFade", "shadow",
    "showHotkeys", "showCounts", "showMacroNames", "showProfessionQuality",
})

local NUMBER_LIMITS = {
    buttons = { 1, 12, true },
    rows = { 1, 12, true },
    size = { 24, 64, true },
    spacing = { -10, 12, true },
    iconZoom = { 0, 0.2, false },
    hotkeySize = { 8, 24, true },
    countSize = { 8, 24, true },
    macroNameSize = { 8, 24, true },
    cooldownTextSize = { 0, 32, true },
    hotkeyOffsetX = { -16, 16, true },
    hotkeyOffsetY = { -16, 16, true },
    countOffsetX = { -16, 16, true },
    countOffsetY = { -16, 16, true },
    macroNameOffsetX = { -16, 16, true },
    macroNameOffsetY = { -16, 16, true },
    cooldownTextOffsetX = { -16, 16, true },
    cooldownTextOffsetY = { -16, 16, true },
    professionQualitySize = { 8, 32, true },
    professionQualityOffsetX = { -16, 16, true },
    professionQualityOffsetY = { -16, 16, true },
}

local BAR_ID_SET = MakeSet(BAR_IDS)
local SPECIAL_BAR_ID_SET = MakeSet(SPECIAL_BAR_IDS)
local LAYOUT_ID_SET = {}
local LAYOUT_IDS = {}

local function AddLayoutId(id)
    local layoutId = "yactionbar." .. tostring(id)
    LAYOUT_ID_SET[layoutId] = true
    LAYOUT_IDS[#LAYOUT_IDS + 1] = layoutId
end

for _, id in ipairs(BAR_IDS) do AddLayoutId(id) end
for _, id in ipairs(SPECIAL_BAR_IDS) do AddLayoutId(id) end
AddLayoutId(SPECIAL_GROUP_ID)

local function CopyValue(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do
        result[key] = CopyValue(item)
    end
    return result
end

local function ValuesEqual(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not ValuesEqual(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function Clamp(value, minimum, maximum, integer)
    value = tonumber(value)
    if value == nil then return nil end
    if integer then value = math.floor(value + 0.5) end
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    return value
end

local function NormalizeColor(value)
    if type(value) ~= "table" then return nil end
    local result = {}
    for index = 1, 4 do
        local component = value[index]
        if component == nil then
            component = index == 1 and value.r
                or index == 2 and value.g
                or index == 3 and value.b
                or value.a
        end
        component = Clamp(component, 0, 1, false)
        if component == nil then
            component = index == 4 and 1 or 0
        end
        result[index] = component
    end
    return result
end

local function NormalizeScopeIds(scopeIds)
    local result = {}
    if type(scopeIds) == "string" then
        if SCOPE_DEFINITIONS[scopeIds] then result[scopeIds] = true end
    elseif type(scopeIds) == "table" then
        for key, value in pairs(scopeIds) do
            local scopeId = type(key) == "number" and value or key
            local selected = type(key) == "number" or value == true
            if selected and SCOPE_DEFINITIONS[scopeId] then
                result[scopeId] = true
            end
        end
    end
    if next(result) == nil then
        for _, scopeId in ipairs(SCOPE_ORDER) do
            result[scopeId] = true
        end
    end
    return result
end

local function ScopeIdsToArray(scopeSet)
    local result = {}
    for _, scopeId in ipairs(SCOPE_ORDER) do
        if scopeSet[scopeId] then result[#result + 1] = scopeId end
    end
    return result
end

local function IsInCombat()
    if YAB.Adapter and type(YAB.Adapter.InCombat) == "function" then
        return YAB.Adapter:InCombat() == true
    end
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() == true or false
end

local function GetSpecialCapabilities(barId)
    if barId == "questItems" then
        local rule = YAB.SpecialBars:GetRule(barId)
        return rule and rule.capabilities or {}
    end
    if Client.deterministicSpecialBars == true and RETAIL_SPECIAL_CAPABILITIES[barId] then
        return RETAIL_SPECIAL_CAPABILITIES[barId]
    end
    return SPECIAL_CAPABILITIES[barId] or ALL_CONFIG_CAPABILITIES
end

local function IsFieldSupported(kind, id, field)
    local capabilityField = TEXT_COLOR_CAPABILITY[field] or field
    if kind == "bars" then return ALL_CONFIG_CAPABILITIES[capabilityField] == true end
    if kind == "specialBars" then
        local capabilities = GetSpecialCapabilities(id)
        return capabilities and capabilities[capabilityField] == true or false
    end
    if kind == "specialGrouping" then
        return SPECIAL_GROUP_CAPABILITIES[capabilityField] == true
    end
    return false
end

local function IsPortableFieldSupported(kind, id, field)
    local capabilityField = TEXT_COLOR_CAPABILITY[field] or field
    if kind == "bars" then return ALL_CONFIG_CAPABILITIES[capabilityField] == true end
    if kind == "specialBars" then
        return SPECIAL_BAR_ID_SET[id] == true
            and ALL_CONFIG_CAPABILITIES[capabilityField] == true
    end
    if kind == "specialGrouping" then
        return SPECIAL_GROUP_CAPABILITIES[capabilityField] == true
    end
    return false
end

local function NormalizeFieldValue(field, value, id)
    if BOOLEAN_FIELDS[field] then
        if type(value) ~= "boolean" then return nil, "expected boolean" end
        return value
    end
    local limits = NUMBER_LIMITS[field]
    if limits then
        local maximum = limits[2]
        if field == "buttons" and id == "pet" then maximum = 10 end
        local normalized = Clamp(value, limits[1], maximum, limits[3])
        if normalized == nil then return nil, "expected number" end
        return normalized
    end
    if OPTIONAL_FIELDS[field] or field == "borderColor" then
        local color = NormalizeColor(value)
        if not color then return nil, "expected color" end
        return color
    end
    if field == "visibility" then
        if type(value) == "table" and YUI.Visibility then
            local valid, code = YUI.Visibility:ValidateBranches(value, { hover = true })
            if not valid then return nil, code end
            return YUI.Visibility:NormalizeBranches(value)
        end
        if VALID_VISIBILITY[value] then return value end
        return nil, "invalid visibility"
    end
    if field == "alignment" then
        if VALID_ALIGNMENT[value] then return value end
        return nil, "invalid alignment"
    end
    if field == "skin" then
        local values = id == "extraAction" and VALID_EXTRA_SKIN or VALID_SKIN
        if values[value] then return value end
        return nil, "invalid skin"
    end
    if field == "border" then
        if VALID_BORDER[value] then return value end
        return nil, "invalid border"
    end
    if field == "background" then
        if VALID_BACKGROUND[value] then return value end
        return nil, "invalid background"
    end
    if field == "rangeMode" then
        if VALID_RANGE[value] then return value end
        return nil, "invalid range mode"
    end
    if field == "growthDirection" then
        if VALID_GROWTH_DIRECTION[value] then return value end
        return nil, "invalid growth direction"
    end
    if field == "groupAlignment" then
        if VALID_GROUP_ALIGNMENT[value] then return value end
        return nil, "invalid group alignment"
    end
    return nil, "unsupported field"
end

local function AddUnset(bucket, path)
    bucket.unset = bucket.unset or {}
    bucket.unset[#bucket.unset + 1] = path
end

local function CaptureConfigBucket(bucket, containerName, sourceTable, ids, scopeId, kind, supports)
    local fields = kind == "specialGrouping" and SPECIAL_GROUP_FIELDS[scopeId] or CONFIG_FIELDS[scopeId]
    supports = supports or IsFieldSupported
    if not fields then return end
    if kind == "specialGrouping" then
        local target = {}
        for _, field in ipairs(fields) do
            if supports(kind, SPECIAL_GROUP_ID, field) then
                local value = sourceTable and sourceTable[field]
                if value == nil then
                    if OPTIONAL_FIELDS[field] then AddUnset(bucket, "specialGrouping." .. field) end
                else
                    target[field] = CopyValue(value)
                end
            end
        end
        if next(target) ~= nil then bucket.specialGrouping = target end
        return
    end

    local container = {}
    for _, id in ipairs(ids or {}) do
        local source = sourceTable and sourceTable[id]
        if type(source) == "table" then
            local target = {}
            for _, field in ipairs(fields) do
                if supports(kind, id, field) then
                    local value = source[field]
                    if value == nil then
                        if OPTIONAL_FIELDS[field] then
                            AddUnset(bucket, containerName .. "." .. id .. "." .. field)
                        end
                    else
                        target[field] = CopyValue(value)
                    end
                end
            end
            if next(target) ~= nil then container[id] = target end
        end
    end
    if next(container) ~= nil then bucket[containerName] = container end
end

local function CaptureRegisteredPlacement(layout, layoutId)
    if not (layout and type(layout.GetPlacement) == "function") then return nil end
    local placement = layout:GetPlacement(layoutId)
    return type(placement) == "table" and CopyValue(placement) or nil
end

local function CapturePlacement(layout, layoutId)
    local placement = CaptureRegisteredPlacement(layout, layoutId)
    if placement then return placement end
    placement = ConfigSets.dormantPlacements and ConfigSets.dormantPlacements[layoutId]
    return type(placement) == "table" and CopyValue(placement) or nil
end

function ConfigSets:Capture(scopeIds, context)
    local db = YAB.GetDB and YAB:GetDB() or nil
    if type(db) ~= "table" then return nil, "missing-db" end
    local scopeSet = NormalizeScopeIds(scopeIds)
    local data = {}

    for _, scopeId in ipairs({ "display", "layout", "appearance", "text" }) do
        if scopeSet[scopeId] then
            local bucket = {}
            CaptureConfigBucket(bucket, "bars", db.bars, BAR_IDS, scopeId, "bars")
            CaptureConfigBucket(bucket, "specialBars", db.specialBars, SPECIAL_BAR_IDS, scopeId, "specialBars")
            CaptureConfigBucket(
                bucket,
                nil,
                db.specialGrouping and db.specialGrouping.config,
                nil,
                scopeId,
                "specialGrouping"
            )
            data[scopeId] = bucket
        end
    end

    if scopeSet.global then
        data.global = {
            appearance = {
                pressedEffect = db.appearance and db.appearance.pressedEffect == "innerGlow" and "innerGlow" or "darken",
            },
            interaction = {
                tooltipMode = db.interaction and db.interaction.tooltipMode == "outOfCombat" and "outOfCombat" or "always",
            },
            specialGrouping = {
                mode = YAB.NormalizeSpecialGroupingMode
                    and YAB:NormalizeSpecialGroupingMode(db.specialGrouping and db.specialGrouping.mode)
                    or (db.specialGrouping and db.specialGrouping.mode)
                    or "independent",
            },
        }
        if Client.rankUpgrade == true then
            data.global.interaction.autoRankUpgrade = not db.interaction or db.interaction.autoRankUpgrade ~= false
        end
    end

    if scopeSet.screenPosition then
        local layout = YUI.Layout
        if not (layout and type(layout.GetPlacement) == "function") then
            return nil, "screen-position-unavailable"
        end
        local placements = {}
        for _, layoutId in ipairs(LAYOUT_IDS) do
            local placement = CapturePlacement(layout, layoutId)
            if placement then placements[layoutId] = placement end
        end
        if next(placements) == nil and #ScopeIdsToArray(scopeSet) == 1 then
            return nil, "screen-position-unavailable"
        end
        data.screenPosition = { placements = placements }
    end

    return data
end

local function ValidateKeys(source, allowed, path)
    if type(source) ~= "table" then return false, path .. ": expected table" end
    for key in pairs(source) do
        if not allowed[key] then
            return false, path .. ": unsupported key " .. tostring(key)
        end
    end
    return true
end

local function NormalizeConfigContainer(source, scopeId, kind, supports)
    if type(source) ~= "table" then return nil, "expected table" end
    supports = supports or IsFieldSupported
    local ids = kind == "bars" and BAR_ID_SET or SPECIAL_BAR_ID_SET
    local result = {}
    for id, fields in pairs(source) do
        if not ids[id] then return nil, "unsupported " .. kind .. " id " .. tostring(id) end
        if type(fields) ~= "table" then return nil, kind .. "." .. tostring(id) .. ": expected table" end
        local target = {}
        for field, value in pairs(fields) do
            if FIELD_SCOPE[field] ~= scopeId or not supports(kind, id, field) then
                return nil, kind .. "." .. tostring(id) .. ": unsupported field " .. tostring(field)
            end
            local normalized, err = NormalizeFieldValue(field, value, id)
            if err then return nil, kind .. "." .. tostring(id) .. "." .. tostring(field) .. ": " .. err end
            target[field] = normalized
        end
        result[id] = target
    end
    return result
end

local function NormalizeSpecialGroupConfig(source, scopeId, supports)
    if type(source) ~= "table" then return nil, "expected table" end
    supports = supports or IsFieldSupported
    local result = {}
    for field, value in pairs(source) do
        if FIELD_SCOPE[field] ~= scopeId or not supports("specialGrouping", SPECIAL_GROUP_ID, field) then
            return nil, "specialGrouping: unsupported field " .. tostring(field)
        end
        local normalized, err = NormalizeFieldValue(field, value, SPECIAL_GROUP_ID)
        if err then return nil, "specialGrouping." .. tostring(field) .. ": " .. err end
        result[field] = normalized
    end
    return result
end

local function ValidateUnsetPath(path, scopeId, supports)
    supports = supports or IsFieldSupported
    if type(path) ~= "string" then return false end
    local container, id, field = path:match("^(bars)%.([%w_]+)%.([%w_]+)$")
    if not container then
        container, id, field = path:match("^(specialBars)%.([%w_]+)%.([%w_]+)$")
    end
    if container then
        local ids = container == "bars" and BAR_ID_SET or SPECIAL_BAR_ID_SET
        return ids[id] == true
            and OPTIONAL_FIELDS[field] == true
            and FIELD_SCOPE[field] == scopeId
            and supports(container, id, field)
    end
    field = path:match("^specialGrouping%.([%w_]+)$")
    return OPTIONAL_FIELDS[field] == true
        and FIELD_SCOPE[field] == scopeId
        and supports("specialGrouping", SPECIAL_GROUP_ID, field)
end

local function NormalizeUnset(source, scopeId, supports)
    if source == nil then return nil end
    if type(source) ~= "table" then return nil, "unset: expected array" end
    local length = #source
    local count = 0
    for key in pairs(source) do
        if type(key) ~= "number"
            or key < 1
            or key > length
            or key ~= math.floor(key) then
            return nil, "unset: expected dense array"
        end
        count = count + 1
    end
    if count ~= length then return nil, "unset: expected dense array" end
    local result = {}
    local seen = {}
    for index, path in ipairs(source) do
        if not ValidateUnsetPath(path, scopeId, supports) then
            return nil, "unset: unsupported path " .. tostring(path)
        end
        if not seen[path] then
            result[#result + 1] = path
            seen[path] = true
        end
    end
    return result
end

local function NormalizeConfigScopeBucket(source, scopeId, supports)
    local ok, err = ValidateKeys(source, {
        bars = true,
        specialBars = true,
        specialGrouping = true,
        unset = true,
    }, scopeId)
    if not ok then return nil, err end
    local result = {}
    if source.bars ~= nil then
        result.bars, err = NormalizeConfigContainer(source.bars, scopeId, "bars", supports)
        if not result.bars then return nil, err end
    end
    if source.specialBars ~= nil then
        result.specialBars, err = NormalizeConfigContainer(source.specialBars, scopeId, "specialBars", supports)
        if not result.specialBars then return nil, err end
    end
    if source.specialGrouping ~= nil then
        result.specialGrouping, err = NormalizeSpecialGroupConfig(source.specialGrouping, scopeId, supports)
        if not result.specialGrouping then return nil, err end
    end
    if source.unset ~= nil then
        result.unset, err = NormalizeUnset(source.unset, scopeId, supports)
        if not result.unset then return nil, err end
    end
    return result
end

local function NormalizeGlobalBucket(source)
    local ok, err = ValidateKeys(source, {
        appearance = true,
        interaction = true,
        blizzardUI = true,
        specialGrouping = true,
    }, "global")
    if not ok then return nil, err end
    local result = {}
    if source.appearance ~= nil then
        ok, err = ValidateKeys(source.appearance, { pressedEffect = true }, "global.appearance")
        if not ok then return nil, err end
        local value = source.appearance.pressedEffect
        if not VALID_PRESSED_EFFECT[value] then return nil, "global.appearance.pressedEffect: invalid value" end
        result.appearance = { pressedEffect = value }
    end
    if source.interaction ~= nil then
        ok, err = ValidateKeys(source.interaction, { tooltipMode = true, autoRankUpgrade = true }, "global.interaction")
        if not ok then return nil, err end
        local value = source.interaction.tooltipMode
        if not VALID_TOOLTIP_MODE[value] then return nil, "global.interaction.tooltipMode: invalid value" end
        result.interaction = { tooltipMode = value }
        local upgrade = source.interaction.autoRankUpgrade
        if upgrade ~= nil and type(upgrade) ~= "boolean" then
            return nil, "global.interaction.autoRankUpgrade: invalid value"
        end
        if Client.rankUpgrade == true then result.interaction.autoRankUpgrade = upgrade end
    end
    if source.blizzardUI ~= nil then
        ok, err = ValidateKeys(source.blizzardUI, {
            statusTrackingBars = true,
            microMenu = true,
            bagsBar = true,
        }, "global.blizzardUI")
        if not ok then return nil, err end
        for key, value in pairs(source.blizzardUI) do
            if not VALID_BLIZZARD_ELEMENT_VISIBILITY[value] then
                return nil, "global.blizzardUI." .. key .. ": invalid value"
            end
        end
    end
    if source.specialGrouping ~= nil then
        ok, err = ValidateKeys(source.specialGrouping, { mode = true }, "global.specialGrouping")
        if not ok then return nil, err end
        local value = source.specialGrouping.mode
        if not VALID_GROUPING_MODE[value] then return nil, "global.specialGrouping.mode: invalid value" end
        result.specialGrouping = { mode = value }
    end
    return result
end

local function NormalizePlacement(source, path)
    if type(source) ~= "table" then return nil, path .. ": expected table" end
    local ok, err = ValidateKeys(source, {
        version = true,
        anchor = true,
        offset = true,
        fallback = true,
    }, path)
    if not ok then return nil, err end
    if type(source.anchor) ~= "table" or type(source.offset) ~= "table" then
        return nil, path .. ": missing anchor or offset"
    end
    ok, err = ValidateKeys(source.anchor, {
        point = true,
        relative = true,
        relativePoint = true,
    }, path .. ".anchor")
    if not ok then return nil, err end
    ok, err = ValidateKeys(source.offset, { x = true, y = true }, path .. ".offset")
    if not ok then return nil, err end
    local point = source.anchor.point
    local relativePoint = source.anchor.relativePoint
    local relative = source.anchor.relative
    if not VALID_ANCHOR_POINT[point] or not VALID_ANCHOR_POINT[relativePoint] then
        return nil, path .. ": invalid anchor point"
    end
    if type(relative) ~= "string" or relative == "" or #relative > 128 then
        return nil, path .. ": invalid relative frame"
    end
    local x = tonumber(source.offset.x)
    local y = tonumber(source.offset.y)
    if x == nil or y == nil then return nil, path .. ": invalid offset" end
    local roundedX = x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)
    local roundedY = y >= 0 and math.floor(y + 0.5) or math.ceil(y - 0.5)
    local result = {
        version = tonumber(source.version) or 2,
        anchor = {
            point = point,
            relative = relative,
            relativePoint = relativePoint,
        },
        offset = {
            x = roundedX,
            y = roundedY,
        },
    }
    if source.fallback ~= nil then
        result.fallback, err = NormalizePlacement(source.fallback, path .. ".fallback")
        if not result.fallback then return nil, err end
    end
    return result
end

local function NormalizeScreenPositionBucket(source)
    local ok, err = ValidateKeys(source, { placements = true }, "screenPosition")
    if not ok then return nil, err end
    if type(source.placements) ~= "table" then return nil, "screenPosition.placements: expected table" end
    local placements = {}
    for layoutId, placement in pairs(source.placements) do
        if not LAYOUT_ID_SET[layoutId] then
            return nil, "screenPosition.placements: unsupported id " .. tostring(layoutId)
        end
        placements[layoutId], err = NormalizePlacement(placement, "screenPosition.placements." .. layoutId)
        if not placements[layoutId] then return nil, err end
    end
    return { placements = placements }
end

function ConfigSets:Normalize(data, scopeIds, context)
    if type(data) ~= "table" then return nil, "invalid-data" end
    local scopeSet = NormalizeScopeIds(scopeIds)
    local normalized = {}
    for scopeId, bucket in pairs(data) do
        if not SCOPE_DEFINITIONS[scopeId] or not scopeSet[scopeId] then
            return nil, "unsupported-scope:" .. tostring(scopeId)
        end
        if type(bucket) ~= "table" then return nil, "invalid-scope:" .. tostring(scopeId) end
        local value, err
        if CONFIG_FIELDS[scopeId] then
            value, err = NormalizeConfigScopeBucket(bucket, scopeId)
        elseif scopeId == "global" then
            value, err = NormalizeGlobalBucket(bucket)
        elseif scopeId == "screenPosition" then
            value, err = NormalizeScreenPositionBucket(bucket)
        end
        if not value then return nil, err or ("invalid-scope:" .. tostring(scopeId)) end
        normalized[scopeId] = value
    end
    return normalized
end

local function NormalizeLegacyPortable(data, scopeIds)
    if type(data) ~= "table" then return nil, "invalid-data" end
    local scopeSet = NormalizeScopeIds(scopeIds)
    local normalized = {}
    for scopeId, bucket in pairs(data) do
        if not SCOPE_DEFINITIONS[scopeId] or not scopeSet[scopeId] then
            return nil, "unsupported-scope:" .. tostring(scopeId)
        end
        if type(bucket) ~= "table" then return nil, "invalid-scope:" .. tostring(scopeId) end
        local value, err
        if CONFIG_FIELDS[scopeId] then
            value, err = NormalizeConfigScopeBucket(
                bucket,
                scopeId,
                IsPortableFieldSupported
            )
        elseif scopeId == "global" then
            value, err = NormalizeGlobalBucket(bucket)
        elseif scopeId == "screenPosition" then
            value, err = NormalizeScreenPositionBucket(bucket)
        end
        if not value then return nil, err or ("invalid-scope:" .. tostring(scopeId)) end
        normalized[scopeId] = value
    end
    return normalized
end

local function FrozenPlacement(config)
    local layout = config and config.layout or nil
    return {
        version = 2,
        anchor = {
            point = layout and layout.point or "CENTER",
            relative = "UIParent",
            relativePoint = layout and layout.relativePoint
                or layout and layout.point
                or "CENTER",
        },
        offset = {
            x = layout and layout.x or 0,
            y = layout and layout.y or 0,
        },
    }
end

local function BuildBaseline(supports, defaults, defaultPlacements)
    defaults = defaults or YAB.Defaults or {}
    local data = {}
    for _, scopeId in ipairs({ "display", "layout", "appearance", "text" }) do
        local bucket = {}
        CaptureConfigBucket(
            bucket,
            "bars",
            defaults.bars,
            BAR_IDS,
            scopeId,
            "bars",
            supports
        )
        CaptureConfigBucket(
            bucket,
            "specialBars",
            defaults.specialBars,
            SPECIAL_BAR_IDS,
            scopeId,
            "specialBars",
            supports
        )
        CaptureConfigBucket(
            bucket,
            nil,
            defaults.specialGrouping and defaults.specialGrouping.config,
            nil,
            scopeId,
            "specialGrouping",
            supports
        )
        data[scopeId] = bucket
    end
    data.global = {
        appearance = {
            pressedEffect = defaults.appearance
                and defaults.appearance.pressedEffect
                or "darken",
        },
        interaction = {
            tooltipMode = defaults.interaction
                and defaults.interaction.tooltipMode
                or "always",
        },
        specialGrouping = {
            mode = defaults.specialGrouping and defaults.specialGrouping.mode or "independent",
        },
    }
    local placements = {}
    for _, id in ipairs(BAR_IDS) do
        local layoutId = "yactionbar." .. id
        placements[layoutId] = CopyValue(defaultPlacements and defaultPlacements[layoutId])
            or FrozenPlacement(defaults.bars and defaults.bars[id])
    end
    for _, id in ipairs(SPECIAL_BAR_IDS) do
        local layoutId = "yactionbar." .. id
        placements[layoutId] = CopyValue(defaultPlacements and defaultPlacements[layoutId])
            or FrozenPlacement(defaults.specialBars and defaults.specialBars[id])
    end
    local groupLayoutId = "yactionbar." .. SPECIAL_GROUP_ID
    placements[groupLayoutId] = CopyValue(defaultPlacements and defaultPlacements[groupLayoutId])
        or FrozenPlacement({
            layout = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = -180,
            },
        })
    data.screenPosition = { placements = placements }
    return data
end

local function HashFeed(hash, value)
    value = tostring(value)
    for index = 1, #value do
        hash = (hash * 33 + value:byte(index)) % 4294967291
    end
    return hash
end

local function HashValue(hash, value)
    local valueType = type(value)
    hash = HashFeed(hash, valueType)
    if valueType ~= "table" then return HashFeed(hash, value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        local leftType, rightType = type(left), type(right)
        if leftType ~= rightType then return leftType < rightType end
        return left < right
    end)
    for _, key in ipairs(keys) do
        hash = HashValue(hash, key)
        hash = HashValue(hash, value[key])
    end
    return HashFeed(hash, "end")
end

local schemaBaselineDefaults = YAB.ConfigSetBaselineDefaultsV1 or YAB.Defaults
local FROZEN_BASELINE = BuildBaseline(function(kind, id, field)
    -- Optional appearance fields added after baseline V1 do not change its hash.
    return field ~= "backgroundColor" and field ~= "shadow" and field ~= "shadowColor"
        and IsPortableFieldSupported(kind, id, field)
end, schemaBaselineDefaults)
-- Adding an optional client-specific bar must not change existing sparse hashes.
for _, scopeId in ipairs({ "display", "layout", "appearance", "text" }) do
    if FROZEN_BASELINE[scopeId].specialBars then FROZEN_BASELINE[scopeId].specialBars.questItems = nil end
end
FROZEN_BASELINE.screenPosition.placements["yactionbar.questItems"] = nil
local RUNTIME_BASELINE = BuildBaseline(IsFieldSupported, schemaBaselineDefaults)
local CURRENT_DEFAULT_SNAPSHOT = BuildBaseline(
    IsPortableFieldSupported,
    YAB.Defaults,
    YAB.DefaultPlacements
)
if Client.questItems == true then
    for _, scopeId in ipairs({ "display", "layout", "appearance", "text" }) do
        RUNTIME_BASELINE[scopeId].specialBars = RUNTIME_BASELINE[scopeId].specialBars or {}
        RUNTIME_BASELINE[scopeId].specialBars.questItems = CopyValue(CURRENT_DEFAULT_SNAPSHOT[scopeId].specialBars.questItems)
    end
end
YAB.ConfigSetBaselineDefaultsV1 = nil
ConfigSets.BASELINE_SIGNATURE = string.format("%08x", HashValue(5381, FROZEN_BASELINE))
ConfigSets.EXPECTED_BASELINE_SIGNATURE = "7e1c8478"

local UNSET_MARKER_KEY = "unset"

local function IsUnsetMarker(value)
    if type(value) ~= "table" or value[UNSET_MARKER_KEY] ~= true then return false end
    for key in pairs(value) do
        if key ~= UNSET_MARKER_KEY then return false end
    end
    return true
end

local function NewUnsetMarker()
    return { [UNSET_MARKER_KEY] = true }
end

local function ParseConfigPath(path)
    local container, id, field = path:match("^(bars)%.([%w_]+)%.([%w_]+)$")
    if not container then
        container, id, field = path:match("^(specialBars)%.([%w_]+)%.([%w_]+)$")
    end
    if container then return container, id, field end
    field = path:match("^specialGrouping%.([%w_]+)$")
    if field then return "specialGrouping", SPECIAL_GROUP_ID, field end
    return nil
end

local function GetConfigPathValue(bucket, path)
    local container, id, field = ParseConfigPath(path)
    if not container then return nil end
    if container == "specialGrouping" then
        return bucket.specialGrouping and bucket.specialGrouping[field]
    end
    return bucket[container]
        and bucket[container][id]
        and bucket[container][id][field]
end

local function NormalizeSparseConfigBucket(source, scopeId)
    if type(source) ~= "table" then return nil, "expected table" end
    local result = {}
    for path, value in pairs(source) do
        if type(path) ~= "string" then return nil, "invalid sparse path" end
        local container, id, field = ParseConfigPath(path)
        if not container
            or FIELD_SCOPE[field] ~= scopeId
            or not IsPortableFieldSupported(container, id, field) then
            return nil, "unsupported sparse path " .. tostring(path)
        end
        local baseline = GetConfigPathValue(FROZEN_BASELINE[scopeId], path)
        if type(value) == "table" and value[UNSET_MARKER_KEY] ~= nil and not IsUnsetMarker(value) then
            return nil, "invalid unset marker " .. tostring(path)
        end
        if IsUnsetMarker(value) then
            if not OPTIONAL_FIELDS[field] then
                return nil, "unsupported unset path " .. tostring(path)
            end
            if baseline ~= nil then result[path] = NewUnsetMarker() end
        else
            local normalized, err = NormalizeFieldValue(field, value, id)
            if err then return nil, tostring(path) .. ": " .. err end
            if not ValuesEqual(normalized, baseline) then result[path] = normalized end
        end
    end
    return result
end

local GLOBAL_PATHS = {
    ["appearance.pressedEffect"] = true,
    ["interaction.tooltipMode"] = true,
    ["specialGrouping.mode"] = true,
}
if Client.rankUpgrade == true then GLOBAL_PATHS["interaction.autoRankUpgrade"] = true end

local function GetGlobalPathValue(bucket, path)
    local section, field = path:match("^([%w_]+)%.([%w_]+)$")
    if section and bucket[section] then
        local value = bucket[section][field]
        if value == nil and Client.rankUpgrade == true and path == "interaction.autoRankUpgrade" then return true end
        return value
    end
end

local function NormalizeSparseGlobalBucket(source)
    if type(source) ~= "table" then return nil, "expected table" end
    local result = {}
    for path, value in pairs(source) do
        if not GLOBAL_PATHS[path] then return nil, "unsupported global path " .. tostring(path) end
        local valid = path == "appearance.pressedEffect" and VALID_PRESSED_EFFECT[value]
            or path == "interaction.tooltipMode" and VALID_TOOLTIP_MODE[value]
            or path == "specialGrouping.mode" and VALID_GROUPING_MODE[value]
            or path == "interaction.autoRankUpgrade" and type(value) == "boolean"
        if not valid then return nil, "invalid global value " .. tostring(path) end
        if value ~= GetGlobalPathValue(FROZEN_BASELINE.global, path) then result[path] = value end
    end
    return result
end

local function NormalizeSparseScreenPositionBucket(source)
    if type(source) ~= "table" then return nil, "expected table" end
    local result = {}
    for layoutId, placement in pairs(source) do
        if not LAYOUT_ID_SET[layoutId] then
            return nil, "unsupported screen position id " .. tostring(layoutId)
        end
        local normalized, err = NormalizePlacement(
            placement,
            "screenPosition." .. tostring(layoutId)
        )
        if not normalized then return nil, err end
        local baseline = FROZEN_BASELINE.screenPosition.placements[layoutId]
        if not ValuesEqual(normalized, baseline) then result[layoutId] = normalized end
    end
    return result
end

function ConfigSets:NormalizeSparse(data, scopeIds)
    if self.BASELINE_SIGNATURE ~= self.EXPECTED_BASELINE_SIGNATURE then
        return nil, "baseline-schema-mismatch"
    end
    if type(data) ~= "table" then return nil, "invalid-data" end
    local scopeSet = NormalizeScopeIds(scopeIds)
    for scopeId in pairs(data) do
        if not SCOPE_DEFINITIONS[scopeId] or not scopeSet[scopeId] then
            return nil, "unsupported-scope:" .. tostring(scopeId)
        end
    end
    local normalized = {}
    for _, scopeId in ipairs(SCOPE_ORDER) do
        if scopeSet[scopeId] then
            local source = data[scopeId] or {}
            local value, err
            if CONFIG_FIELDS[scopeId] then
                value, err = NormalizeSparseConfigBucket(source, scopeId)
            elseif scopeId == "global" then
                value, err = NormalizeSparseGlobalBucket(source)
            elseif scopeId == "screenPosition" then
                value, err = NormalizeSparseScreenPositionBucket(source)
            end
            if not value then return nil, err end
            normalized[scopeId] = value
        end
    end
    return normalized
end

local function AddSparseConfigFields(result, target, baseline, scopeId)
    for _, container in ipairs({ "bars", "specialBars" }) do
        for id, fields in pairs(target[container] or {}) do
            for field, value in pairs(fields) do
                local path = container .. "." .. id .. "." .. field
                local baselineValue = GetConfigPathValue(baseline, path)
                if IsPortableFieldSupported(container, id, field)
                    and FIELD_SCOPE[field] == scopeId
                    and not ValuesEqual(value, baselineValue) then
                    result[path] = CopyValue(value)
                end
            end
        end
    end
    for field, value in pairs(target.specialGrouping or {}) do
        local path = "specialGrouping." .. field
        local baselineValue = GetConfigPathValue(baseline, path)
        if IsPortableFieldSupported("specialGrouping", SPECIAL_GROUP_ID, field)
            and FIELD_SCOPE[field] == scopeId
            and not ValuesEqual(value, baselineValue) then
            result[path] = CopyValue(value)
        end
    end
    for _, path in ipairs(target.unset or {}) do
        if GetConfigPathValue(baseline, path) ~= nil then
            result[path] = NewUnsetMarker()
        end
    end
end

function ConfigSets:BuildSparseFromFull(data, scopeIds)
    local scopeSet = NormalizeScopeIds(scopeIds)
    local result = {}
    for _, scopeId in ipairs(SCOPE_ORDER) do
        if scopeSet[scopeId] then
            local bucket = {}
            local source = data[scopeId] or {}
            if CONFIG_FIELDS[scopeId] then
                AddSparseConfigFields(bucket, source, FROZEN_BASELINE[scopeId], scopeId)
            elseif scopeId == "global" then
                for path in pairs(GLOBAL_PATHS) do
                    local value = GetGlobalPathValue(source, path)
                    if value ~= nil
                        and value ~= GetGlobalPathValue(FROZEN_BASELINE.global, path) then
                        bucket[path] = CopyValue(value)
                    end
                end
            elseif scopeId == "screenPosition" then
                for layoutId, placement in pairs(source.placements or {}) do
                    local baseline = FROZEN_BASELINE.screenPosition.placements[layoutId]
                    if not ValuesEqual(placement, baseline) then
                        bucket[layoutId] = CopyValue(placement)
                    end
                end
            end
            result[scopeId] = bucket
        end
    end
    return self:NormalizeSparse(result, scopeIds)
end

local function RemoveUnsetPath(bucket, path)
    local unset = bucket.unset
    if type(unset) ~= "table" then return end
    for index = #unset, 1, -1 do
        if unset[index] == path then table.remove(unset, index) end
    end
    if #unset == 0 then bucket.unset = nil end
end

local function AddUnsetPath(bucket, path)
    bucket.unset = bucket.unset or {}
    for _, existing in ipairs(bucket.unset) do
        if existing == path then return end
    end
    bucket.unset[#bucket.unset + 1] = path
end

local function SetMaterializedConfigValue(bucket, path, value)
    local container, id, field = ParseConfigPath(path)
    if container == "specialGrouping" then
        bucket.specialGrouping = bucket.specialGrouping or {}
        bucket.specialGrouping[field] = IsUnsetMarker(value) and nil or CopyValue(value)
    else
        bucket[container] = bucket[container] or {}
        bucket[container][id] = bucket[container][id] or {}
        bucket[container][id][field] = IsUnsetMarker(value) and nil or CopyValue(value)
    end
    if IsUnsetMarker(value) then AddUnsetPath(bucket, path)
    else RemoveUnsetPath(bucket, path) end
end

function ConfigSets:MaterializeSparse(data, scopeIds)
    local normalized, err = self:NormalizeSparse(data, scopeIds)
    if not normalized then return nil, err end
    local scopeSet = NormalizeScopeIds(scopeIds)
    local result = {}
    for _, scopeId in ipairs(SCOPE_ORDER) do
        if scopeSet[scopeId] then
            local target = CopyValue(
                CONFIG_FIELDS[scopeId]
                    and RUNTIME_BASELINE[scopeId]
                    or FROZEN_BASELINE[scopeId]
            )
            if CONFIG_FIELDS[scopeId] then
                for path, value in pairs(normalized[scopeId]) do
                    local container, id, field = ParseConfigPath(path)
                    if IsFieldSupported(container, id, field) then
                        SetMaterializedConfigValue(target, path, value)
                    end
                end
            elseif scopeId == "global" then
                for path, value in pairs(normalized.global) do
                    local section, field = path:match("^([%w_]+)%.([%w_]+)$")
                    target[section][field] = CopyValue(value)
                end
                if Client.rankUpgrade == true and target.interaction.autoRankUpgrade == nil then
                    target.interaction.autoRankUpgrade = true
                end
            elseif scopeId == "screenPosition" then
                for layoutId, placement in pairs(normalized.screenPosition) do
                    target.placements[layoutId] = CopyValue(placement)
                end
            end
            if scopeId == "display" and YUI.Visibility then
                local function Upgrade(fields)
                    if fields and type(fields.visibility) ~= "table" then
                        fields.visibility = YUI.Visibility:MigrateActionBar(fields.visibility, fields.hideSkyriding)
                        fields.hideSkyriding = false
                    end
                end
                for _, fields in pairs(target.bars or {}) do Upgrade(fields) end
                for _, fields in pairs(target.specialBars or {}) do Upgrade(fields) end
                Upgrade(target.specialGrouping)
            end
            result[scopeId] = target
        end
    end
    return result, normalized
end

function ConfigSets:CaptureSparse(scopeIds, context)
    local full, err = self:Capture(scopeIds, context)
    if not full then return nil, err end
    local sparse
    sparse, err = self:BuildSparseFromFull(full, scopeIds)
    if not sparse then return nil, err end
    local scopeSet = NormalizeScopeIds(scopeIds)
    for scopeId, overrides in pairs(self.dormantConfigOverrides or {}) do
        if scopeSet[scopeId] and CONFIG_FIELDS[scopeId] then
            sparse[scopeId] = sparse[scopeId] or {}
            for path, value in pairs(overrides) do
                sparse[scopeId][path] = CopyValue(value)
            end
        end
    end
    if scopeSet.screenPosition then
        sparse.screenPosition = sparse.screenPosition or {}
        for layoutId, placement in pairs(self.dormantPlacements or {}) do
            local baseline = FROZEN_BASELINE.screenPosition.placements[layoutId]
            if not ValuesEqual(placement, baseline) then
                sparse.screenPosition[layoutId] = CopyValue(placement)
            end
        end
    end
    return sparse
end

function ConfigSets:ApplySparse(data, scopeIds, context)
    local materialized, normalized = self:MaterializeSparse(data, scopeIds)
    if not materialized then return false, normalized end
    local scopeSet = NormalizeScopeIds(scopeIds)
    if scopeSet.screenPosition then self.dormantPlacements = {} end
    self.dormantConfigOverrides = self.dormantConfigOverrides or {}
    for scopeId in pairs(CONFIG_FIELDS) do
        if scopeSet[scopeId] then self.dormantConfigOverrides[scopeId] = nil end
    end
    for scopeId, overrides in pairs(normalized) do
        if CONFIG_FIELDS[scopeId] then
            for path, value in pairs(overrides) do
                local container, id, field = ParseConfigPath(path)
                if not IsFieldSupported(container, id, field) then
                    self.dormantConfigOverrides[scopeId] =
                        self.dormantConfigOverrides[scopeId] or {}
                    self.dormantConfigOverrides[scopeId][path] = CopyValue(value)
                end
            end
        end
    end
    return self:ApplyData(materialized, scopeIds, {
        sparseData = normalized,
        serviceContext = context,
    })
end

local function RecordBarChange(result, kind, id, scopeId, field)
    result.changed = true
    result.touchedBars[kind] = result.touchedBars[kind] or {}
    local touched = result.touchedBars[kind][id]
    if not touched then
        touched = {}
        result.touchedBars[kind][id] = touched
    end
    touched[scopeId] = true
    touched.fields = touched.fields or {}
    touched.fields[field] = true
    if field == "enabled" then
        result.structuralBars[id] = true
        if kind == "specialBars" then
            result.reloadRequired = true
        end
    end
end

local function ApplyFields(target, fields, result, kind, id, scopeId)
    for field, value in pairs(fields or {}) do
        if not ValuesEqual(target[field], value) then
            target[field] = CopyValue(value)
            RecordBarChange(result, kind, id, scopeId, field)
        end
    end
    if scopeId == "layout" and id ~= "questItems" and target.buttons ~= nil and target.rows ~= nil then
        local maximum = math.max(1, math.floor(tonumber(target.buttons) or 1))
        local rows = math.max(1, math.min(math.floor(tonumber(target.rows) or 1), maximum))
        if target.rows ~= rows then
            target.rows = rows
            RecordBarChange(result, kind, id, scopeId, "rows")
        end
    end
end

local function ApplyUnsetPath(db, scopeId, path, result)
    local containerName, id, field = path:match("^(bars)%.([%w_]+)%.([%w_]+)$")
    if not containerName then
        containerName, id, field = path:match("^(specialBars)%.([%w_]+)%.([%w_]+)$")
    end
    if containerName then
        local target = db[containerName] and db[containerName][id]
        if target and target[field] ~= nil then
            target[field] = nil
            RecordBarChange(result, containerName, id, scopeId, field)
        end
        return
    end
    field = path:match("^specialGrouping%.([%w_]+)$")
    local target = db.specialGrouping and db.specialGrouping.config
    if field and target and target[field] ~= nil then
        target[field] = nil
        result.changed = true
        result.specialGroupConfigChanged = true
        result.specialGroupScopes[scopeId] = true
    end
end

local function ApplyConfigScope(db, scopeId, bucket, result)
    for id, fields in pairs(bucket.bars or {}) do
        db.bars[id] = db.bars[id] or {}
        ApplyFields(db.bars[id], fields, result, "bars", id, scopeId)
    end
    for id, fields in pairs(bucket.specialBars or {}) do
        db.specialBars[id] = db.specialBars[id] or {}
        ApplyFields(db.specialBars[id], fields, result, "specialBars", id, scopeId)
    end
    if bucket.specialGrouping then
        db.specialGrouping = db.specialGrouping or {}
        db.specialGrouping.config = db.specialGrouping.config or {}
        local before = CopyValue(db.specialGrouping.config)
        ApplyFields(
            db.specialGrouping.config,
            bucket.specialGrouping,
            result,
            "specialGrouping",
            SPECIAL_GROUP_ID,
            scopeId
        )
        if not ValuesEqual(before, db.specialGrouping.config) then
            result.specialGroupConfigChanged = true
            result.specialGroupScopes[scopeId] = true
        end
    end
    for _, path in ipairs(bucket.unset or {}) do
        ApplyUnsetPath(db, scopeId, path, result)
    end
end

local function ApplyGlobalScope(db, bucket, result)
    if bucket.appearance and db.appearance.pressedEffect ~= bucket.appearance.pressedEffect then
        db.appearance.pressedEffect = bucket.appearance.pressedEffect
        result.changed = true
        result.pressedEffectChanged = true
    end
    if bucket.interaction and db.interaction.tooltipMode ~= bucket.interaction.tooltipMode then
        db.interaction.tooltipMode = bucket.interaction.tooltipMode
        result.changed = true
        result.tooltipModeChanged = true
    end
    if Client.rankUpgrade == true and bucket.interaction and bucket.interaction.autoRankUpgrade ~= nil
        and db.interaction.autoRankUpgrade ~= bucket.interaction.autoRankUpgrade then
        db.interaction.autoRankUpgrade = bucket.interaction.autoRankUpgrade
        result.changed = true
        result.autoRankUpgradeChanged = true
    end
    if bucket.specialGrouping and db.specialGrouping.mode ~= bucket.specialGrouping.mode then
        db.specialGrouping.mode = bucket.specialGrouping.mode
        result.changed = true
        result.specialGroupingModeChanged = true
    end
end

function ConfigSets:ApplyData(data, scopeIds, context)
    local db = YAB.GetDB and YAB:GetDB() or nil
    if type(db) ~= "table" then return false, "missing-db" end
    db.bars = db.bars or {}
    db.specialBars = db.specialBars or {}
    db.specialGrouping = db.specialGrouping or { mode = "independent", config = {} }
    db.specialGrouping.config = db.specialGrouping.config or {}
    db.appearance = db.appearance or {}
    db.interaction = db.interaction or {}

    local result = {
        changed = false,
        touchedBars = {},
        structuralBars = {},
        specialGroupScopes = {},
        placements = {},
        placementWasReadable = {},
        placementOverrides = {},
        reloadRequired = false,
    }

    for _, scopeId in ipairs({ "display", "layout", "appearance", "text" }) do
        if data[scopeId] then ApplyConfigScope(db, scopeId, data[scopeId], result) end
    end
    if data.global then ApplyGlobalScope(db, data.global, result) end
    if data.screenPosition then
        local layout = YUI.Layout
        for layoutId, placement in pairs(
            data.screenPosition.placements or {}
        ) do
            result.placementOverrides[layoutId] = type(context) == "table"
                and type(context.sparseData) == "table"
                and type(context.sparseData.screenPosition) == "table"
                and context.sparseData.screenPosition[layoutId] ~= nil
                or false
            local current = CapturePlacement(layout, layoutId)
            result.placementWasReadable[layoutId] = current ~= nil
            if current == nil or not ValuesEqual(current, placement) then
                result.placements[layoutId] = CopyValue(placement)
                result.hasPlacements = true
                result.changed = true
            end
        end
    end

    return result
end

local function ApplyPlacement(layout, layoutId, placement)
    if not (layout and type(layout.SetPlacement) == "function") then
        return false, "screen-position-unavailable"
    end
    local ok, reason = layout:SetPlacement(layoutId, placement, true)
    if ok == false then return false, reason or ("placement-failed:" .. layoutId) end
    return true
end

local function CaptureSnapshotExtension(result, layout, layoutId)
    if result.placementWasReadable[layoutId] == true then return end
    local current = CapturePlacement(layout, layoutId)
    if not current then return end
    result.snapshotExtension = result.snapshotExtension or {}
    result.snapshotExtension.screenPosition = result.snapshotExtension.screenPosition or {}
    result.snapshotExtension.screenPosition[layoutId] = current
    result.placementWasReadable[layoutId] = true
end

local function ApplyAvailablePlacements(result, pending)
    local layout = YUI.Layout
    for layoutId, placement in pairs(result.placements or {}) do
        if CaptureRegisteredPlacement(layout, layoutId) then
            CaptureSnapshotExtension(result, layout, layoutId)
            local ok, err = ApplyPlacement(layout, layoutId, placement)
            if not ok then return false, err end
            ConfigSets.dormantPlacements[layoutId] = nil
        else
            pending[layoutId] = placement
        end
    end
    return true
end

local function ApplyPendingPlacements(result, pending)
    local layout = YUI.Layout
    for layoutId, placement in pairs(pending) do
        CaptureSnapshotExtension(result, layout, layoutId)
        if not CaptureRegisteredPlacement(layout, layoutId) then
            ConfigSets.dormantPlacements[layoutId] = CopyValue(placement)
        else
            local ok, err = ApplyPlacement(layout, layoutId, placement)
            if not ok then return false, err end
            ConfigSets.dormantPlacements[layoutId] = nil
        end
    end
    return true
end

function ConfigSets:PreserveDormantPlacement(layoutId, placement)
    if not LAYOUT_ID_SET[layoutId] or type(placement) ~= "table" then
        return false, "invalid-placement"
    end
    self.dormantPlacements = self.dormantPlacements or {}
    self.dormantPlacements[layoutId] = CopyValue(placement)
    return true
end

function ConfigSets:ApplyDormantPlacement(layoutId)
    local placement = self.dormantPlacements and self.dormantPlacements[layoutId]
    if not placement then return false, "no-dormant-placement" end
    if not CaptureRegisteredPlacement(YUI.Layout, layoutId) then
        return false, "screen-position-frame-unavailable"
    end
    local ok, err = ApplyPlacement(YUI.Layout, layoutId, placement)
    if not ok then return false, err end
    self.dormantPlacements[layoutId] = nil
    return true
end

local function CompleteSnapshotExtension(result, context)
    local extension = result and result.snapshotExtension
    if type(extension) ~= "table" then return end
    for _, scopeId in ipairs(context and context.scopeIds or {}) do
        if extension[scopeId] == nil then
            extension[scopeId] = {}
        end
    end
end

local function QueueTouchedBarRefreshes(manager, result)
    for kind, records in pairs(result.touchedBars or {}) do
        if kind == "bars" or kind == "specialBars" then
            for id, scopes in pairs(records) do
                if not result.structuralBars[id] then
                    if manager.RefreshConfigSnapshot then
                        manager:RefreshConfigSnapshot(id, YAB:GetDB())
                    end
                    if manager.QueueSettingsRefresh then
                        local fields = scopes.fields or {}
                        local needsLayout = scopes.layout == true
                        local needsVisual = scopes.appearance == true
                            or scopes.text == true
                        local needsAction = needsLayout
                            or fields.hideEmptySlots == true
                            or fields.rangeMode == true
                            or fields.cooldownFade == true
                        local needsVisibility = fields.visibility == true
                            or fields.hideSkyriding == true

                        if needsLayout then
                            manager:QueueSettingsRefresh(id, "layout")
                        elseif needsVisual then
                            manager:QueueSettingsRefresh(id, "visual")
                        end
                        if needsAction and not needsLayout then
                            manager:QueueSettingsRefresh(id, "action")
                        end
                        if needsVisibility then
                            manager:QueueSettingsRefresh(id, "visibility")
                        end
                    end
                end
            end
        end
    end
end

local function QueueGlobalVisualRefresh(manager)
    local db = YAB:GetDB()
    if manager.RefreshConfigSnapshots then manager:RefreshConfigSnapshots(db) end
    if not manager.QueueSettingsRefresh then return end
    for _, id in ipairs(BAR_IDS) do manager:QueueSettingsRefresh(id, "visual") end
    for _, id in ipairs(SPECIAL_BAR_IDS) do manager:QueueSettingsRefresh(id, "visual") end
end

local function ApplyStructuralBarChanges(manager, result, reason)
    if type(manager.ApplyBarStructureChanges) == "function" then
        return manager:ApplyBarStructureChanges(
            result.structuralBars,
            reason or "config-set"
        )
    end
    if type(manager.ApplyBarStructureChange) ~= "function" then
        return false, "runtime-structure-refresh-unavailable"
    end
    for id in pairs(result.structuralBars or {}) do
        local applied, applyReason = manager:ApplyBarStructureChange(
            id,
            reason or "config-set",
            true
        )
        if applied == false then
            return false, applyReason or "runtime-structure-refresh-failed"
        end
    end
    return true
end

function ConfigSets:Refresh(reason, result, context)
    result = result or {}
    if IsInCombat() then return false, "combat-lockdown" end

    local manager = YAB.BarManager
    local runtimeActive = manager and manager.runtimeActive == true
    if result.hasPlacements and not runtimeActive then
        return false, "screen-position-runtime-inactive"
    end

    local pendingPlacements = {}
    local ok, err = ApplyAvailablePlacements(result, pendingPlacements)
    if not ok then return false, err end

    local hasStructuralChanges = next(result.structuralBars or {}) ~= nil

    if runtimeActive and hasStructuralChanges then
        local applied, applyReason = ApplyStructuralBarChanges(
            manager,
            result,
            reason
        )
        if applied == false then
            return false, applyReason or "runtime-structure-refresh-failed"
        end
    end
    if runtimeActive then
        if result.specialGroupingModeChanged or result.specialGroupConfigChanged then
            if manager.RefreshSpecialGroupingRuntime then
                local refreshed, refreshReason = manager:RefreshSpecialGroupingRuntime(
                    YAB:GetDB(),
                    reason or "config-set"
                )
                if refreshed == false and refreshReason ~= "combat deferred" then
                    return false, refreshReason or "special-group-refresh-failed"
                end
            end
        end
        QueueTouchedBarRefreshes(manager, result)
        if result.pressedEffectChanged then QueueGlobalVisualRefresh(manager) end
    elseif result.changed and YAB.Refresh then
        YAB:Refresh(reason or "config-set")
    end

    if result.tooltipModeChanged then
        local factory = YAB.SecureFactory
        if factory and factory.HideRestrictedCombatTooltip then
            factory:HideRestrictedCombatTooltip()
        end
    end

    ok, err = ApplyPendingPlacements(result, pendingPlacements)
    if not ok then return false, err end
    if result.autoRankUpgradeChanged and YAB.RankUpgrade then YAB.RankUpgrade:SyncEnabled() end
    CompleteSnapshotExtension(result, context)
    return {
        snapshotExtension = result.snapshotExtension,
        reloadRequired = result.reloadRequired == true,
    }
end

function ConfigSets:CanApply(context)
    if IsInCombat() then return false, "combat-lockdown" end
    if not (YAB.IsEnabled and YAB:IsEnabled()) then
        return false, "product-disabled"
    end
    return true
end

local function UpgradeSparseVisibility(data, err)
    if not data then return nil, err end
    local service = YUI.Visibility
    local display = data.display
    if not (service and display) then return data end
    local function Upgrade(prefix, baseline)
        if baseline.visibility == nil then return end
        local mode = display[prefix .. "visibility"]
        if mode == nil then mode = baseline.visibility end
        if type(mode) ~= "table" then
            local sky = display[prefix .. "hideSkyriding"]
            if sky == nil then sky = baseline.hideSkyriding end
            display[prefix .. "visibility"] = service:MigrateActionBar(mode, sky)
            display[prefix .. "hideSkyriding"] = nil
        end
    end
    for _, container in ipairs({ "bars", "specialBars" }) do
        for id, baseline in pairs(FROZEN_BASELINE.display[container] or {}) do
            Upgrade(container .. "." .. id .. ".", baseline)
        end
    end
    Upgrade("specialGrouping.", FROZEN_BASELINE.display.specialGrouping or {})
    return data
end

function ConfigSets:Migrate(data, fromVersion, toVersion, context)
    fromVersion = tonumber(fromVersion) or self.SCHEMA_VERSION
    toVersion = tonumber(toVersion) or self.SCHEMA_VERSION
    local scopeIds = {}
    for _, scopeId in ipairs(SCOPE_ORDER) do
        if type(data) == "table" and data[scopeId] ~= nil then
            scopeIds[#scopeIds + 1] = scopeId
        end
    end
    if #scopeIds == 0 then return nil, "invalid-data" end
    if fromVersion == toVersion and toVersion == self.SCHEMA_VERSION then
        return UpgradeSparseVisibility(self:NormalizeSparse(data, scopeIds))
    end
    if toVersion ~= self.SCHEMA_VERSION or (fromVersion ~= 1 and fromVersion ~= 2 and fromVersion ~= 3) then
        return nil, "unsupported-schema-version"
    end
    if fromVersion == 1 then
        local legacy, err = NormalizeLegacyPortable(data, scopeIds)
        if not legacy then return nil, err end
        return UpgradeSparseVisibility(self:BuildSparseFromFull(legacy, scopeIds))
    end

    local migrated = CopyValue(data)
    local global = migrated.global
    if global ~= nil then
        if type(global) ~= "table" then return nil, "global: expected table" end
        local legacyPaths = {
            "blizzardUI.statusTrackingBars",
            "blizzardUI.microMenu",
            "blizzardUI.bagsBar",
        }
        for _, path in ipairs(legacyPaths) do
            local value = global[path]
            if value ~= nil and not VALID_BLIZZARD_ELEMENT_VISIBILITY[value] then
                return nil, "invalid global value " .. path
            end
            global[path] = nil
        end
        for path, value in pairs(global) do
            if type(path) == "string" and path:match("^blizzardUI%.") then
                return nil, "unsupported global path " .. tostring(path)
            end
        end
    end
    return UpgradeSparseVisibility(self:NormalizeSparse(migrated, scopeIds))
end

function ConfigSets:CanMigrate(fromVersion, toVersion)
    fromVersion = tonumber(fromVersion)
    return (fromVersion == 1 or fromVersion == 2 or fromVersion == 3)
        and tonumber(toVersion) == self.SCHEMA_VERSION
end

local BUILTINS = {
    {
        id = "classic-three-row",
        nameKey = "config_sets.builtin.yui.name",
        titleKey = "config_sets.builtin.yui.name",
        name = "YUI",
        title = "YUI",
        label = "YUI",
        descriptionKey = "config_sets.builtin.yui.description",
        description = "YUI 默认动作条配置。",
        schemaVersion = ConfigSets.SCHEMA_VERSION,
        scopeIds = {
            "display",
            "layout",
            "appearance",
            "text",
            "global",
            "screenPosition",
        },
        preview = {
            kind = "product",
            productId = "yactionbar",
            path = "presets\\classic-three-row.png",
            width = 256,
            height = 144,
        },
        data = CURRENT_DEFAULT_SNAPSHOT,
    },
}

for _, builtin in ipairs(BUILTINS) do
    local sparse, err = ConfigSets:BuildSparseFromFull(builtin.data, builtin.scopeIds)
    if not sparse then error("invalid YActionBar builtin: " .. tostring(err)) end
    builtin.data = sparse
end

local BUILTIN_BY_ID = {}
for _, builtin in ipairs(BUILTINS) do BUILTIN_BY_ID[builtin.id] = builtin end
BUILTIN_BY_ID.default = BUILTIN_BY_ID[ConfigSets.DEFAULT_BUILTIN_ID]

ConfigSets.Builtins = BUILTINS
ConfigSets.ScopeOrder = SCOPE_ORDER
ConfigSets.Scopes = SCOPE_DEFINITIONS

function ConfigSets:GetBuiltin(id)
    if id == nil or id == "" then id = self.DEFAULT_BUILTIN_ID end
    return BUILTIN_BY_ID[id]
end

function ConfigSets:GetBuiltins()
    return BUILTINS
end

local function MergeSnapshotExtension(snapshot, extension)
    if type(snapshot) ~= "table" or type(extension) ~= "table" then return snapshot end
    for scopeId, bucket in pairs(extension) do
        snapshot[scopeId] = snapshot[scopeId] or {}
        if scopeId == "screenPosition" then
            for layoutId, placement in pairs(bucket or {}) do
                if snapshot[scopeId][layoutId] == nil then
                    snapshot[scopeId][layoutId] = CopyValue(placement)
                end
            end
        end
    end
    return snapshot
end

function ConfigSets:ApplyBuiltinDirect(id, context)
    local builtin = self:GetBuiltin(id)
    if not builtin then return false, "builtin-not-found" end
    local allowed, err = self:CanApply(context)
    if not allowed then return false, err end
    local snapshot
    snapshot, err = self:CaptureSparse(builtin.scopeIds, context)
    if not snapshot then return false, err end
    local normalized
    normalized, err = self:NormalizeSparse(builtin.data, builtin.scopeIds, context)
    if not normalized then return false, err end
    local result
    result, err = self:ApplySparse(normalized, builtin.scopeIds, context)
    if result == false then return false, err end
    local refreshed
    refreshed, err = self:Refresh("config-set:" .. builtin.id, result, context)
    if refreshed == false then
        local rollback = self:ApplySparse(snapshot, builtin.scopeIds, context)
        if rollback then self:Refresh("config-set-rollback:" .. builtin.id, rollback, context) end
        return false, err
    end
    MergeSnapshotExtension(snapshot, result.snapshotExtension)
    self.directUndo = {
        data = snapshot,
        scopeIds = CopyValue(builtin.scopeIds),
        id = builtin.id,
    }
    return true, result
end

function ConfigSets:UndoDirect(context)
    local undo = self.directUndo
    if not undo then return false, "nothing-to-undo" end
    local normalized, err = self:NormalizeSparse(undo.data, undo.scopeIds, context)
    if not normalized then return false, err end
    local result
    result, err = self:ApplySparse(normalized, undo.scopeIds, context)
    if result == false then return false, err end
    local refreshed
    refreshed, err = self:Refresh("config-set-undo:" .. tostring(undo.id), result, context)
    if refreshed == false then return false, err end
    self.directUndo = nil
    return true, result
end

local Provider = {
    id = ConfigSets.PROVIDER_ID,
    productId = YAB.PRODUCT_ID or "yactionbar",
    schemaVersion = ConfigSets.SCHEMA_VERSION,
    localeNamespace = "YActionBar",
    editableUserSets = true,
    userSetScopePolicy = "all",
    configurationModes = {
        isolatedLibraries = true,
        defaultMode = "specialization",
    },
    previewZoom = false,
    specializationAssignments = true,
    defaultAssignment = {
        kind = "builtin",
        id = ConfigSets.DEFAULT_BUILTIN_ID,
    },
    autoApplyAssignments = true,
    scopeOrder = SCOPE_ORDER,
    scopes = SCOPE_DEFINITIONS,
    builtins = BUILTINS,
    maxUserSets = 30,
}

Provider.assignmentReady = function(context)
    if IsInCombat() then
        return false, "combat-lockdown"
    end
    if not (YAB.IsEnabled and YAB:IsEnabled()) then
        return false, "product-disabled"
    end
    if not (YAB.BarManager and YAB.BarManager.runtimeActive == true) then
        return false, "runtime-inactive"
    end
    return true
end
Provider.canApply = function(context)
    return ConfigSets:CanApply(context)
end
Provider.capture = function(scopeIds, context)
    return ConfigSets:CaptureSparse(scopeIds, context)
end
Provider.normalize = function(data, scopeIds, context)
    return ConfigSets:NormalizeSparse(data, scopeIds, context)
end
Provider.apply = function(data, scopeIds, context)
    return ConfigSets:ApplySparse(data, scopeIds, context)
end
Provider.restore = function(snapshot, scopeIds, context)
    return ConfigSets:ApplySparse(snapshot, scopeIds, context)
end
Provider.refresh = function(reason, result, context)
    return ConfigSets:Refresh(reason, result, context)
end
Provider.migrate = function(data, fromVersion, toVersion, context)
    return ConfigSets:Migrate(data, fromVersion, toVersion, context)
end
Provider.canMigrate = function(fromVersion, toVersion)
    return ConfigSets:CanMigrate(fromVersion, toVersion)
end

ConfigSets.Provider = Provider

function ConfigSets:RegisterWithService(service)
    if type(service) ~= "table" or type(service.RegisterProvider) ~= "function" then
        return false, "config-sets-service-unavailable"
    end
    if self.registeredService == service then return true end
    local ok, result, err = pcall(service.RegisterProvider, service, Provider)
    if not ok then return false, tostring(result) end
    if not result then return false, err or "provider-registration-failed" end
    self.registeredService = service
    return true
end

function ConfigSets:GetService()
    return YUI.Settings and YUI.Settings.ConfigSets or nil
end

local function AppendActiveSettingChanges(changes, barId, field, value)
    local scopeId = FIELD_SCOPE[field]
    if not scopeId then return nil, "unsupported-field" end

    local containerName
    local targetId = barId
    if barId == SPECIAL_GROUP_ID then
        containerName = "specialGrouping"
        targetId = nil
    elseif BAR_ID_SET[barId] then
        containerName = "bars"
    elseif SPECIAL_BAR_ID_SET[barId] then
        containerName = "specialBars"
    else
        return nil, "unsupported-bar"
    end
    if not IsFieldSupported(containerName, barId, field) then
        return nil, "unsupported-field"
    end

    local sparsePath = containerName .. "."
        .. (targetId and (tostring(targetId) .. ".") or "")
        .. tostring(field)
    local baseline = GetConfigPathValue(FROZEN_BASELINE[scopeId], sparsePath)
    local change = { path = { scopeId, sparsePath } }
    if value == nil then
        if not OPTIONAL_FIELDS[field] then return nil, "invalid-value" end
        if baseline == nil then change.remove = true
        else change.value = NewUnsetMarker() end
    else
        local normalized, err = NormalizeFieldValue(field, value, barId)
        if err then return nil, "invalid-value" end
        if ValuesEqual(normalized, baseline) then change.remove = true
        else change.value = normalized end
    end
    changes[#changes + 1] = change
    return true
end

function ConfigSets:PatchActive(changes, reason, owner)
    local service = self:GetService()
    if not (service and type(service.PatchActiveUserSet) == "function") then
        return nil, "config-sets-service-unavailable"
    end
    local result, code, detail = service:PatchActiveUserSet(
        self.PROVIDER_ID,
        changes,
        {
            reason = reason,
            owner = owner or self,
        }
    )
    return result, code, detail
end

function ConfigSets:SaveActiveSettings(barId, values, reason, owner)
    if type(values) ~= "table" or #values == 0 then
        return nil, "invalid-settings"
    end
    local changes = {}
    for index = 1, #values do
        local entry = values[index]
        if type(entry) ~= "table" or type(entry.field) ~= "string" then
            return nil, "invalid-settings"
        end
        local ok, code = AppendActiveSettingChanges(
            changes,
            barId,
            entry.field,
            entry.value
        )
        if not ok then return nil, code end
    end
    return self:PatchActive(changes, reason, owner)
end

function ConfigSets:SaveActiveSetting(barId, field, value, reason, owner)
    return self:SaveActiveSettings(
        barId,
        {
            { field = field, value = value },
        },
        reason,
        owner
    )
end

function ConfigSets:SaveActiveGlobalSetting(section, field, value, reason, owner)
    if type(section) ~= "string" or type(field) ~= "string" or value == nil then
        return nil, "invalid-settings"
    end
    local sparsePath = section .. "." .. field
    local normalized, err = NormalizeSparseGlobalBucket({
        [sparsePath] = value,
    })
    if not normalized then return nil, err or "invalid-settings" end
    local change = { path = { "global", sparsePath } }
    if normalized[sparsePath] == nil then change.remove = true
    else change.value = normalized[sparsePath] end
    return self:PatchActive({ change }, reason, owner)
end

local function BuildActivePlacementChange(layoutId, placement)
    if not LAYOUT_ID_SET[layoutId] then return nil, "unsupported-layout" end
    local normalized, err = NormalizePlacement(
        placement,
        "screenPosition." .. tostring(layoutId)
    )
    if not normalized then return nil, err or "invalid-placement" end

    local change = { path = { "screenPosition", layoutId } }
    local baseline = FROZEN_BASELINE.screenPosition.placements[layoutId]
    if ValuesEqual(normalized, baseline) then change.remove = true
    else change.value = normalized end
    return change, normalized
end

function ConfigSets:PatchActivePlacement(layoutId, placement, reason, owner)
    local change, normalized = BuildActivePlacementChange(layoutId, placement)
    if not change then return nil, normalized end
    local result, code, detail = self:PatchActive(
        { change },
        reason or "layout-placement-commit",
        owner
    )
    if not result then return nil, code, detail end
    return normalized, result.changed == true, result
end

function ConfigSets:SyncReadableActivePlacements(reason, owner)
    local changes = {}
    for _, layoutId in ipairs(LAYOUT_IDS) do
        local placement = CapturePlacement(YUI.Layout, layoutId)
        if placement then
            local change, normalized = BuildActivePlacementChange(layoutId, placement)
            if not change then return nil, normalized end
            changes[#changes + 1] = change
        end
    end
    if #changes == 0 then return true, false end

    local result, code, detail = self:PatchActive(
        changes,
        reason or "config-transfer-export",
        owner
    )
    if not result then return nil, code, detail end
    return true, result.changed == true, result
end

function ConfigSets:SaveActive(reason, owner)
    local service = self:GetService()
    if not (service and type(service.SaveActiveUserSet) == "function") then
        return nil, "config-sets-service-unavailable"
    end
    return service:SaveActiveUserSet(self.PROVIDER_ID, {
        reason = reason,
        owner = owner or self,
    })
end

ConfigSets:RegisterWithService(ConfigSets:GetService())

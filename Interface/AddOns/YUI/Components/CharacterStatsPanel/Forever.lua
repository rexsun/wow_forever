local _, addon = ...
local YUI = _G.YUI or addon
if not YUI or not YUI.IsForever then return end

local Data = YUI.CharacterStatsPanelForeverData
if not Data then return end
local Forever = {}
YUI.CharacterStatsPanelForever = Forever
local Talent = YUI.API.Talent
local PaperDoll = YUI.API.PaperDoll
local Security = YUI.API.Security
local Unit = YUI.API.Unit
local Frame = YUI.API.Frame
local LAYOUT_ID = "ybar.stats.panel"
local floor, format = math.floor, string.format
local unpack = unpack or table.unpack
local RESIDENT, DETAIL, HIDDEN = "RESIDENT", "DETAIL", "HIDDEN"
local OPTION_DEFAULTS = {
    enlargeCore = true, rowGap = 0, orientation = "VERTICAL",
    valueAlignment = "RIGHT", valueColumnGap = 12,
    showNames = true, showIcons = false, showMeters = false, iconSize = 22, meterYOffset = 0,
}
Forever.FONT_SIZE_MAX = 28
local MIN_PANEL_WIDTH = 80
local ICON_PRODUCT = "CharacterStatsPanel"
local DEFAULT_SKIN = { skinId = "minimal-rounded", skinOptions = {} }
local MAX_METER_TARGET = 1000000
local METER_HEIGHT, METER_GAP, ICON_GAP = 3, 3, 6
local HORIZONTAL_CELL_INSET = 2
local METER_Y_OFFSET_LIMIT = 8
local BuildOverview, PrepareOverview
local RESOURCE_KEYS = { hp = "healthDisplay", mana = "manaDisplay" }
local DEFAULT_RESOURCE_MODE = "CURRENT"
local RESOURCE_MODES = { DEFAULT_RESOURCE_MODE, "CURRENT_PERCENT", "PERCENT", "CURRENT_MAX", "MAX" }
local WHOLE_PERCENT_FORMAT, DECIMAL_PERCENT_FORMAT = "%.0f%%", "%.1f%%"
local RESOURCE_FORMATS = {
    CURRENT_PERCENT = "%d (%.0f%%)", PERCENT = WHOLE_PERCENT_FORMAT,
    CURRENT_MAX = "%d / %d", CURRENT = "%d", MAX = "%d",
}
local OVERVIEW_RESOURCE_FORMATS = { CURRENT_PERCENT = "%d (%.1f%%)", PERCENT = DECIMAL_PERCENT_FORMAT }

function Forever.InitializeNewConfig(settings)
    settings.panelWidth = 115
    settings.columnSpacing = 15
    -- 保存新外观的取值，让旧版导入时仍能读到它们。旧配置的缺省值沿用原来行为。
    settings.forever = {
        version = 3,
        showIcons = true,
        iconSize = 18,
        iconSkin = {
            skinId = DEFAULT_SKIN.skinId,
            skinOptions = { [DEFAULT_SKIN.skinId] = { border = "shade" } },
        },
    }
end

local function T(key)
    local locale = YUI.Locale and YUI.Locale:Get("CharacterStatsPanel")
    if key:sub(1, 7) == "common." then locale = YUI.Locale and YUI.Locale:Get("Core") end
    return locale and locale[key] or key
end

local function IsPublic(value)
    local predicate = type(issecretvalue) == "function" and issecretvalue
        or (Security and Security.IsSecretValue)
    if type(predicate) == "function" then
        local ok, restricted = pcall(predicate, value)
        if not ok or restricted ~= false then return false end
    end
    return true
end

local function PublicNumber(value)
    if not IsPublic(value) then return nil end
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        return value
    end
end

-- Shift the decimal representation instead of rounding a binary product at a boundary.
function Forever.Format(value, percent)
    value = PublicNumber(value)
    if not value then return "—" end
    local decimal = format("%.15g", value)
    local mantissa, exponent = decimal:match("^(.-)[eE]([+-]?%d+)$")
    mantissa, exponent = mantissa or decimal, tonumber(exponent) or 0
    local negative = mantissa:sub(1, 1) == "-"
    if negative then mantissa = mantissa:sub(2) end
    local whole, fraction = mantissa:match("^(%d+)%.?(%d*)$")
    if not whole then return "—" end
    local digits = whole .. fraction
    local shift = #whole + exponent + 1
    local scaled, remainder
    if shift <= 0 then
        scaled, remainder = 0, digits:find("[1-9]") ~= nil
    elseif shift >= #digits then
        scaled, remainder = tonumber(digits) * 10 ^ (shift - #digits), false
    else
        scaled = tonumber(digits:sub(1, shift))
        remainder = digits:sub(shift + 1):find("[1-9]") ~= nil
    end
    if negative then scaled = -scaled - (remainder and 1 or 0) end
    local text = scaled % 10 == 0 and format("%.0f", scaled / 10) or format("%.1f", scaled / 10)
    return text .. (percent and "%" or "")
end

local function ResourceMode(config, id)
    local mode = config[RESOURCE_KEYS[id]]
    return RESOURCE_FORMATS[mode] and mode or DEFAULT_RESOURCE_MODE
end

local function ReadResource(module, id)
    local states = module.foreverResourceStates
    if not states then states = {}; module.foreverResourceStates = states end
    local state, changed
    if id == "hp" then
        state, changed = Unit.ReadHealthDisplay("player", states[id])
    else
        state, changed = Unit.ReadPowerDisplay("player", 0, states[id])
    end
    states[id] = state
    return state, changed
end

local function PaintResourceText(hooks, text, state, mode, detailed)
    if not text then return end
    if state.publicMaxValue == 0 then hooks.text(text, "—"); return end
    local current, maximum = state.valueRaw, state.maxValueRaw
    local percentage = state.percentRaw
    if (mode == "PERCENT" or mode == "CURRENT_PERCENT") and not state.secret
        and state.value and state.maxValue and state.maxValue > 0 then
        percentage = math.max(0, math.min(100, state.value / state.maxValue * 100))
    end
    local first, second, count = current, nil, 1
    if mode == "MAX" then
        first = IsPublic(maximum) and state.publicMaxValue or maximum
    elseif mode == "PERCENT" then
        first = percentage
    elseif mode == "CURRENT_MAX" then
        second, count = maximum, 2
    elseif mode == "CURRENT_PERCENT" then
        if not IsPublic(percentage) or PublicNumber(percentage) then
            second, count = percentage, 2
        else
            mode = "CURRENT"
        end
    end
    local firstPublic = IsPublic(first)
    local secondPublic = count == 1 or IsPublic(second)
    local pattern = (detailed and OVERVIEW_RESOURCE_FORMATS[mode]) or RESOURCE_FORMATS[mode]
    if (firstPublic and not PublicNumber(first)) or (count == 2 and secondPublic and not PublicNumber(second)) then
        hooks.text(text, "—")
    elseif not firstPublic or not secondPublic then
        hooks.secretText(text, pattern, count, first, second)
    elseif count == 2 then
        hooks.text(text, format(pattern, first, second))
    else
        hooks.text(text, format(pattern, first))
    end
end

local function ResourceTextWidth(mode, size)
    local units = (mode == "CURRENT_PERCENT" or mode == "CURRENT_MAX") and 7 or (mode == "PERCENT" and 2.7 or 4)
    return math.ceil(size * units + 4)
end

local function ValueTextStyle(settings, hooks, labelFont)
    local defaults = hooks.valueTextDefaults
    local font = settings.valueFont or defaults.valueFont
    return font == settings.font and labelFont or hooks.fontPath(font),
        math.min(Forever.FONT_SIZE_MAX, math.max(8, PublicNumber(settings.valueFontSize) or defaults.valueFontSize)),
        settings.valueFontEffect or defaults.valueFontEffect, settings.valueTextMonochrome == true
end

local function ReadStat(id, unit, forDisplay)
    local value, mode = PaperDoll.ReadForeverStat(id, unit, forDisplay)
    if mode then return value, mode end
    return PublicNumber(value)
end

function Forever.Read(id, forDisplay)
    if not PaperDoll or not PaperDoll.ReadForeverStat then return nil end
    if id == "mp5" or id == "pet_hit" or id == "pet_crit" then return nil end
    if id:match("^pet_") then
        if not Unit.UnitExists then return nil end
        local ok, exists = pcall(Unit.UnitExists, "pet")
        if not ok or not IsPublic(exists) or exists ~= true then return nil end
        local petStat = id == "pet_hp" and "hp" or (id == "pet_armor" and "armor" or "ap")
        return ReadStat(petStat, "pet", forDisplay)
    end
    local weapon = id:match("^(.-)_skill$")
    if weapon then
        local rank, rankMode = ReadStat(weapon .. "_skill_rank", "player", forDisplay)
        local modifier, modifierMode = ReadStat(weapon .. "_skill_modifier", "player", forDisplay)
        if rankMode or modifierMode then return nil, "restricted" end
        if rank and modifier then return rank + modifier end
        return nil
    end
    if id == "sp_frostfire" then
        local fire, fireMode = ReadStat("sp_fire", "player", forDisplay)
        local frost, frostMode = ReadStat("sp_frost", "player", forDisplay)
        if fireMode or frostMode then return nil, "restricted" end
        if fire and frost then return math.min(fire, frost) end
        return nil
    end
    return ReadStat(id, "player", forDisplay)
end

local function NumberFormat(multiplier)
    -- Native truncation operates on the scaled significand. Allow for float error at exact tenths.
    return { breakpointData = { {
        breakpoint = 0, abbreviation = "", abbreviationIsGlobal = false,
        significandDivisor = 1 / (10 * multiplier * (1 + 1e-11)), fractionDivisor = 10,
    } } }
end

local SECRET_NUMBER = NumberFormat(1)
local SECRET_REGEN = NumberFormat(5)

local function StatPercentFormat(def, detailed)
    -- Camelot rounds the block row to a whole percent and shows tenths in its tooltip.
    return not detailed and (def.id == "block" or def.id == "movespeed") and WHOLE_PERCENT_FORMAT or DECIMAL_PERCENT_FORMAT
end

local function FormatStatValue(value, def, detailed)
    if not def.percent then return Forever.Format(value) end
    local pattern = StatPercentFormat(def, detailed)
    if pattern == WHOLE_PERCENT_FORMAT then value = floor(value + .5) end
    return format(pattern, value)
end

local function ReadStatDisplay(module, def, detailed)
    local id = def.id
    if id == "movespeed" then
        local value, mode = module.foreverRenderHooks.readMovementSpeed()
        if mode then return "—", nil, mode, value end
        return value and FormatStatValue(value, def, detailed) or "—", value
    end
    if id:match("_damage$") then
        local low, lowMode = Forever.Read(id .. "_min", true)
        local high, highMode = Forever.Read(id .. "_max", true)
        if (lowMode == "secret" or low) and (highMode == "secret" or high) then
            if lowMode or highMode then return "—", nil, "range", low, high end
            return Forever.Format(low) .. "–" .. Forever.Format(high)
        end
        return "—"
    end
    local value, mode = Forever.Read(id, true)
    if mode == "secret" or mode == "per_second" then return "—", nil, mode, value end
    local last = module.foreverLastPublicStats
    if value ~= nil then
        if not last then last = {}; module.foreverLastPublicStats = last end
        last[id] = value
        return FormatStatValue(value, def, detailed), value
    end
    if mode == "restricted" and last and last[id] ~= nil then
        return FormatStatValue(last[id], def, detailed) .. "*", nil, "cached"
    end
    return "—"
end

local function PaintStatText(hooks, text, def, mode, first, second, detailed)
    if mode == "secret_speed" then
        if type(AbbreviateNumbers) ~= "function" then return false end
        local ok = pcall(hooks.secretSpeedText, text, first)
        return ok
    elseif mode == "range" then
        hooks.secretText(text, "%.1f–%.1f", 2, first, second)
    elseif mode == "secret" and def.percent then
        hooks.secretText(text, StatPercentFormat(def, detailed), 1, first)
    elseif mode == "secret" or mode == "per_second" then
        if type(AbbreviateNumbers) == "function" then
            local options = mode == "per_second" and SECRET_REGEN or SECRET_NUMBER
            local ok, formatted = pcall(AbbreviateNumbers, first, options)
            if ok then
                hooks.secretText(text, "%s", 1, formatted)
                return true
            end
        end
        if mode == "per_second" then return false end
        hooks.secretText(text, "%.1f", 1, first)
    else
        return false
    end
    return true
end

local function SameParameter(value, default)
    if type(default) ~= "table" then return value == default end
    if type(value) ~= "table" then return false end
    for index = 1, 4 do
        if value[index] ~= default[index] then return false end
    end
    return true
end

local function SaveIconSkin(config, style)
    local skins = YUI.GUI2.IconSkins
    if not skins.definitions[style.skinId] then return end
    local overrides = skins:NormalizeOptions(style.skinOptions or {}) or {}
    for id, values in pairs(overrides) do
        local definition = skins.definitions[id]
        if definition then
            for key, value in pairs(values) do
                if SameParameter(value, definition[key]) then values[key] = nil end
            end
        end
        if not definition or next(values) == nil then overrides[id] = nil end
    end
    if style.skinId == DEFAULT_SKIN.skinId and next(overrides) == nil then
        config.iconSkin = nil
    else
        config.iconSkin = { skinId = style.skinId, skinOptions = overrides }
    end
end

local function GetIconSkin(config)
    local skin = config.iconSkin
    if type(skin) == "table" and YUI.GUI2.IconSkins.definitions[skin.skinId]
        and type(skin.skinOptions) == "table" then return skin end
    return DEFAULT_SKIN
end

local function HasMeter(def)
    return def.meterMax ~= nil and def.id ~= "mp5" and def.id ~= "pet_hit" and def.id ~= "pet_crit"
end

function Forever.GetMeterTarget(config, def)
    if not HasMeter(def) then return nil end
    local target = type(config.meterTargets) == "table" and config.meterTargets[def.id]
    if type(target) == "number" and target >= .1 and target <= MAX_METER_TARGET then return target end
    return def.meterMax
end

local function SetMeterTarget(config, def, input)
    local text = input:match("^%s*(.-)%s*$")
    local value
    if text ~= "" then
        if def.percent then text = text:gsub("%%$", "") end
        value = tonumber(text)
        if not value or not (value >= .1 and value <= MAX_METER_TARGET) then return false end
        value = tonumber(Forever.Format(value))
    end
    local old = Forever.GetMeterTarget(config, def)
    if not value or value == def.meterMax then
        if type(config.meterTargets) == "table" then
            config.meterTargets[def.id] = nil
            if next(config.meterTargets) == nil then config.meterTargets = nil end
        end
    else
        if type(config.meterTargets) ~= "table" then config.meterTargets = {} end
        config.meterTargets[def.id] = value
    end
    return old ~= Forever.GetMeterTarget(config, def)
end

local function LegacyTextHeight(settings, config)
    return math.ceil((tonumber(settings.fontSize) or 14) * (config.enlargeCore ~= false and 1.35 or 1)) + 3
end

function Forever.EnsureSettings(settings)
    if type(settings.forever) ~= "table" then settings.forever = {} end
    local config = settings.forever
    if type(config.selections) ~= "table" then config.selections = {} end
    if type(config.profiles) ~= "table" then config.profiles = {} end
    if type(config.colors) ~= "table" then config.colors = nil end
    if not config.version or config.version == 0 then
        -- Migrate legacy geometry once; a cleared default must not resurrect old spacing.
        if config.columns == nil and settings.panelOrientation == "HORIZONTAL" then config.columns = 2 end
        if type(config.rowGap) ~= "number" then
            config.rowGap = math.max(0, (tonumber(settings.spacing) or 21) - LegacyTextHeight(settings, config))
        end
        config.columns = config.columns == 2 and 2 or nil
        if config.enlargeCore ~= false then config.enlargeCore = nil end
        config.rowGap = math.max(0, config.rowGap)
        for key, value in pairs(OPTION_DEFAULTS) do
            if config[key] == value then config[key] = nil end
        end
        for key, profile in pairs(config.profiles) do
            if type(profile) == "table" and (type(profile.fields) ~= "table" or next(profile.fields) == nil) then
                config.profiles[key] = nil
            end
        end
        Forever.CompactSavedProfiles(config)
        config.version = 1
    end
    if config.version == 1 then
        if config.orientation == nil and config.columns == 2 then config.orientation = "HORIZONTAL" end
        config.columns = nil
        if config.orientation == OPTION_DEFAULTS.orientation then config.orientation = nil end
        config.version = 2
    end
    if config.version == 2 and YUI.GUI2 and YUI.GUI2.IconSkins then
        if not config.iconSkin and (config.iconShape or config.iconBorder or config.iconShadow ~= nil or config.iconShadowAlpha) then
            local skins = YUI.GUI2.IconSkins
            local oldStyle = skins:NormalizeSettings({ iconShape = config.iconShape or "roundedSquare" }, ICON_PRODUCT)
            local values = {}
            values.border = config.iconBorder
            values.shadow = config.iconShadow
            if type(config.iconShadowAlpha) == "number" then values.shadowColor = { 0, 0, 0, config.iconShadowAlpha } end
            oldStyle.skinOptions = { [oldStyle.skinId] = values }
            SaveIconSkin(config, oldStyle)
        end
        config.iconShape, config.iconBorder, config.iconShadow, config.iconShadowAlpha = nil, nil, nil, nil
        config.version = 3
    end
    return config
end

function Forever.GetOption(config, key)
    local value = config[key]
    if key == "enlargeCore" or key == "showNames" then return value ~= false end
    if key == "rowGap" then return type(value) == "number" and math.max(0, value) or 0 end
    if key == "orientation" then return value == "HORIZONTAL" and value or "VERTICAL" end
    if key == "valueAlignment" then return value == "LEFT" and value or OPTION_DEFAULTS[key] end
    if key == "valueColumnGap" then return math.min(60, math.max(0, PublicNumber(value) or OPTION_DEFAULTS[key])) end
    if key == "showIcons" or key == "showMeters" then return value == true end
    if key == "iconSize" then return math.min(40, math.max(12, PublicNumber(value) or OPTION_DEFAULTS[key])) end
    if key == "meterYOffset" then
        return math.min(METER_Y_OFFSET_LIMIT, math.max(-METER_Y_OFFSET_LIMIT, PublicNumber(value) or OPTION_DEFAULTS[key]))
    end
    if value == nil then return OPTION_DEFAULTS[key] end
    return value
end

function Forever.SetOption(config, key, value)
    if value == OPTION_DEFAULTS[key] then config[key] = nil else config[key] = value end
end

function Forever.SyncLegacyLayout(settings, config, resetGap)
    -- 老版本从组件根表读取排列方式和行高。
    settings.panelOrientation = Forever.GetOption(config, "orientation")
    if config.rowGap ~= nil or resetGap then
        settings.spacing = LegacyTextHeight(settings, config) + Forever.GetOption(config, "rowGap")
    end
end

local function ColorCode(r, g, b)
    r, g, b = PublicNumber(r), PublicNumber(g), PublicNumber(b)
    if not r or not g or not b then return nil end
    local function Byte(value) return floor(math.max(0, math.min(1, value)) * 255 + .5) end
    return Byte(r) * 65536 + Byte(g) * 256 + Byte(b)
end

function Forever.GetColor(config, id)
    local value = config.colors and config.colors[id]
    if type(value) == "number" and value >= 0 and value <= 16777215 then
        return floor(value / 65536) / 255, floor(value / 256) % 256 / 255, value % 256 / 255
    end
    local def = Data.byID[id]
    if def then return unpack(def.color) end
    return 1, 1, 1
end

function Forever.GetLabelColor(settings, config, id)
    if settings.appearanceStyle == "WHITE" or settings.appearanceStyle == "VALUE_COLORED" then return 1, 1, 1 end
    return Forever.GetColor(config, id)
end

function Forever.SetColor(module, id, color, config)
    local def = Data.byID[id]
    if not def or type(color) ~= "table" then return end
    local value = ColorCode(color[1], color[2], color[3])
    if not value then return end
    config = config or Forever.EnsureSettings(module.settings)
    local previous = config.colors and config.colors[id]
    if value == ColorCode(unpack(def.color)) then
        if config.colors then
            config.colors[id] = nil
            if not next(config.colors) then config.colors = nil end
        end
    else
        config.colors = config.colors or {}
        config.colors[id] = value
    end
    if previous == (config.colors and config.colors[id]) then return false end
    if module.settings and module.settings.forever == config then module:UpdateStatsPanel() end
    return true
end

local function InCombat()
    return Security and Security.InCombatLockdown and Security.InCombatLockdown() == true
end

local function FindPreset(class, id)
    local presets = Data.presets[class]
    if presets then
        for _, preset in ipairs(presets) do
            if preset.id == id then return preset end
        end
    end
end

function Forever.Resolve(module)
    if module.foreverContext and not module.foreverIdentityDirty then return module.foreverContext end
    if module.foreverContext and InCombat() then return module.foreverContext end
    local class = Unit.GetClassToken("player")
    if type(class) ~= "string" then return nil end
    local info = Talent.GetCurrentConfigurationSpecializationInfo and Talent.GetCurrentConfigurationSpecializationInfo()
    local group = PublicNumber(Talent.GetActiveTalentGroup and Talent.GetActiveTalentGroup())
    local configID = PublicNumber(Talent.GetCurrentConfigID and Talent.GetCurrentConfigID())
    local identity = class .. ":" .. (configID and ("config:" .. configID) or (group and ("group:" .. group) or "unassigned"))
    local config = Forever.EnsureSettings(module.settings)
    local manual = config.selections[identity]
    local preset = FindPreset(class, manual)
    local automatic = not preset
    local treePresets = Data.treePresets[class]
    local recommended = info and treePresets and treePresets[info.treeIndex or info.specIndex]
    preset = preset or FindPreset(class, recommended) or (Data.presets[class] and Data.presets[class][1])
    if not preset then return nil end
    local profileKey = class .. ":" .. preset.id
    local profile = config.profiles[profileKey]
    local previous = module.foreverContext
    if type(profile) ~= "table" then
        profile = previous and previous.config == config and previous.profileKey == profileKey and previous.profile or { fields = {} }
    end
    if type(profile.fields) ~= "table" then profile.fields = {} end
    module.foreverContext = { class = class, identity = identity, preset = preset, profile = profile, profileKey = profileKey,
        automatic = automatic, known = recommended ~= nil, config = config }
    Forever.SaveProfile(module.foreverContext)
    module.foreverIdentityDirty = false
    module.foreverPlan = nil
    return module.foreverContext
end

local function Contains(list, id)
    if list then for index, entry in ipairs(list) do if entry == id then return index end end end
end

local function RelatedAllowed(context, source, id)
    local class, preset = context.class, context.preset.id
    local agilityAP = class == "ROGUE" or class == "HUNTER" or (class == "DRUID" and preset == "cat")
    if (source == "ap" and id == "agi") or (source == "agi" and id == "ap") then return agilityAP end
    if source == "agi" and id == "rap" then return class == "HUNTER" end
    if source:match("^sp_") then
        if source == "sp_frostfire" then return id == "sp_fire" or id == "sp_frost" end
        local schools = Data.schools[class]
        return schools and schools[id] == true
    end
    return true
end

function Forever.DefaultMode(context, id)
    if Contains(context.preset.rows, id) then return RESIDENT end
    if id == "str" or id == "agi" or id == "sta" or id == "int" or id == "spirit" then return DETAIL end
    for _, rowID in ipairs(context.preset.rows) do
        local definition = Data.byID[rowID]
        if definition and Contains(definition.related, id) and RelatedAllowed(context, rowID, id) then return DETAIL end
    end
    return HIDDEN
end

local function FieldOverride(context, id)
    local field = context.profile.fields[id]
    if type(field) == "table" then return field end
end

function Forever.Mode(context, id)
    local field = FieldOverride(context, id)
    if field and (field.mode == RESIDENT or field.mode == DETAIL or field.mode == HIDDEN) then return field.mode end
    return Forever.DefaultMode(context, id)
end

local function Order(context, def, index)
    local field = FieldOverride(context, def.id)
    return field and PublicNumber(tonumber(field.order)) or Contains(context.preset.rows, def.id) or (100 + index)
end

local function ViewContext(module)
    local context = Forever.Resolve(module)
    local temporary = module.foreverTemporaryPreset
    if not context or not temporary then return context end
    if temporary.identity ~= context.identity or temporary.config ~= context.config then
        module.foreverTemporaryPreset = nil
        return context
    end
    if not temporary.context then
        local key = context.class .. ":" .. temporary.preset.id
        local profile = context.config.profiles[key]
        if type(profile) ~= "table" or type(profile.fields) ~= "table" then profile = { fields = {} } end
        temporary.context = { class = context.class, identity = context.identity, preset = temporary.preset,
            profileKey = key, profile = profile,
            config = context.config, temporary = true }
    end
    return temporary.context
end

function Forever.SaveProfile(context)
    local fields, current, defaults = context.profile.fields, {}, {}
    for id, field in pairs(fields) do
        if type(field) ~= "table" then fields[id] = nil end
    end
    for index, def in ipairs(Data.definitions) do
        local field = fields[def.id]
        if field then
            local mode = field.mode
            if (mode ~= RESIDENT and mode ~= DETAIL and mode ~= HIDDEN) or mode == Forever.DefaultMode(context, def.id) then
                field.mode = nil
            end
            field.order = PublicNumber(tonumber(field.order))
            if field.order == (Contains(context.preset.rows, def.id) or 100 + index) then field.order = nil end
            if not next(field) then fields[def.id] = nil end
        end
        if Forever.Mode(context, def.id) == RESIDENT then
            current[#current + 1] = { id = def.id, order = Order(context, def, index), index = index }
            defaults[#defaults + 1] = { id = def.id, order = Contains(context.preset.rows, def.id) or 100 + index, index = index }
        end
    end
    local function Less(a, b) return a.order == b.order and a.index < b.index or a.order < b.order end
    table.sort(current, Less)
    table.sort(defaults, Less)
    local same = true
    for index, row in ipairs(current) do if row.id ~= defaults[index].id then same = false; break end end
    if same then
        for id, field in pairs(fields) do
            if Data.byID[id] then
                field.order = nil
                if not next(field) then fields[id] = nil end
            end
        end
    end
    if next(fields) then context.config.profiles[context.profileKey] = context.profile
    else context.config.profiles[context.profileKey] = nil end
end

function Forever.CompactSavedProfiles(config)
    for key, profile in pairs(config.profiles) do
        local class, id
        if type(key) == "string" then class, id = key:match("^(%u+):(.+)$") end
        local preset = class and FindPreset(class, id)
        if preset and type(profile) == "table" and type(profile.fields) == "table" then
            Forever.SaveProfile({ class = class, preset = preset, profile = profile, profileKey = key, config = config })
        end
    end
end

function Forever.Plan(module)
    local context = ViewContext(module)
    if not context then return nil end
    if module.foreverPlan and (InCombat() or not module.foreverPlanDirty) then return module.foreverPlan end
    local plan = { context = context, rows = {} }
    for index, def in ipairs(Data.definitions) do
        if Forever.Mode(context, def.id) == RESIDENT then
            plan.rows[#plan.rows + 1] = { def = def, order = Order(context, def, index), index = index,
                core = Contains(context.preset.core, def.id) ~= nil }
        end
    end
    table.sort(plan.rows, function(a, b)
        if a.order == b.order then return a.index < b.index end
        return a.order < b.order
    end)
    local spellRows = 0
    for _, row in ipairs(plan.rows) do
        if row.def.id:match("^sp_") then spellRows = spellRows + 1 end
    end
    local attack = Contains(context.preset.rows, "hit_melee") and "melee"
        or (Contains(context.preset.rows, "hit_ranged") and "ranged" or "spell")
    for _, row in ipairs(plan.rows) do
        local id = row.def.id
        row.shortKey = row.def.shortKey
        if spellRows == 1 and id:match("^sp_") then row.shortKey = "forever.spell_power" end
        for _, kind in ipairs({ "hit", "crit", "haste" }) do
            if id == kind .. "_" .. attack then row.shortKey = Data.byID[kind .. "_melee"].shortKey end
        end
    end
    module.foreverPlan, module.foreverPlanDirty = plan, false
    return plan
end

function Forever.Invalidate(module, identity)
    module.foreverPlanDirty = true
    if identity then
        module.foreverIdentityDirty = true
        module.foreverTemporaryPreset = nil
        Forever.CloseOverview(module)
    end
end

function Forever.OverviewShown(module)
    return module.foreverOverview and module.foreverOverview:IsShown() or false
end

function Forever.GetMovementSpeedLines(module)
    local frame = module.statsFrame
    if not frame or not frame:IsShown() then return end
    return frame.speedLineValue, Forever.OverviewShown(module) and module.foreverOverview.speedLineValue
end

local function PaintMovementSpeed(hooks, text, value, mode, detailed)
    local def = Data.byID.movespeed
    if not PaintStatText(hooks, text, def, mode, value) then
        hooks.text(text, not mode and value and FormatStatValue(value, def, detailed) or "—")
    end
end

function Forever.RefreshMovementSpeed(module)
    local panelLine, overviewLine = Forever.GetMovementSpeedLines(module)
    if not panelLine and not overviewLine then return false end
    local hooks = module.foreverRenderHooks
    local value, mode = hooks.readMovementSpeed()
    if panelLine then PaintMovementSpeed(hooks, panelLine, value, mode, false) end
    if overviewLine then PaintMovementSpeed(hooks, overviewLine, value, mode, true) end
    return true
end

function Forever.CloseOverview(module)
    if module.foreverOverview then module.foreverOverview:Hide() end
    module.foreverOverviewRows = nil
end

function Forever.OverviewRows(module)
    if module.foreverOverviewRows then return module.foreverOverviewRows end
    local context = Forever.Resolve(module)
    if not context then return {} end
    local included, rows = {}, {}
    for _, preset in ipairs(Data.presets[context.class]) do
        local profile = context.config.profiles[context.class .. ":" .. preset.id]
        if type(profile) ~= "table" or type(profile.fields) ~= "table" then profile = { fields = {} } end
        local view = { class = context.class, preset = preset, profile = profile }
        for _, def in ipairs(Data.definitions) do
            if Forever.Mode(view, def.id) == RESIDENT then included[def.id] = true end
        end
    end
    for _, def in ipairs(Data.definitions) do
        if included[def.id] then rows[#rows + 1] = { def = def } end
    end
    module.foreverOverviewRows = rows
    return rows
end

function Forever.UpdateOverview(module, hooks)
    if not Forever.OverviewShown(module) then return end
    local popup, settings = module.foreverOverview, module.settings
    popup.speedLineValue = nil
    local rows = Forever.OverviewRows(module)
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local fontSize = math.max(11, math.min(settings.fontSize or 14, 16))
    local count = math.max(1, math.ceil(#rows / 2))
    local width = math.min(360, screenWidth > 100 and screenWidth - 32 or 360)
    local font = hooks.fontPath(settings.font)
    local valueFont, valueSize, valueEffect, valueMonochrome = ValueTextStyle(settings, hooks, font)
    valueSize = math.max(11, math.min(valueSize, 16))
    local pitch = math.max(fontSize, valueSize) + 8
    hooks.font(popup.subtitle, font, 16, settings.fontEffect)
    hooks.textWidth(popup.subtitle, width - popup.identityInset - 16)
    local bodyTop = 36 + math.max(20, popup.subtitle:GetStringHeight()) + 8
    local height = math.min(bodyTop + 16 + count * pitch, screenHeight > 100 and screenHeight - 32 or 600)
    local columnWidth = (width - 64) / 2
    hooks.size(popup, width, height)
    if popup.foreverBodyTop ~= bodyTop then
        popup.scroll:ClearAllPoints()
        popup.scroll:SetPoint("TOPLEFT", 16, -bodyTop)
        popup.foreverBodyTop = bodyTop
    end
    hooks.size(popup.scroll, width - 48, height - bodyTop - 16)
    hooks.size(popup.scroll.child, width - 48, count * pitch)
    local context = Forever.Resolve(module)
    local resourceLines = popup.resourceLines or {}
    popup.resourceLines = resourceLines
    resourceLines.hp, resourceLines.mana = nil, nil
    for index, row in ipairs(rows) do
        local line = popup.rows[index]
        local x, y = floor((index - 1) / count) * (columnWidth + 16), -((index - 1) % count) * pitch
        if line.foreverX ~= x or line.foreverY ~= y then
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", popup.scroll.child, "TOPLEFT", x, y)
            line.foreverX, line.foreverY = x, y
        end
        hooks.size(line, columnWidth, pitch)
        hooks.font(line.label, font, fontSize, settings.fontEffect)
        hooks.font(line.value, valueFont, valueSize, valueEffect, valueMonochrome)
        hooks.color(line, settings.appearanceStyle, Forever.GetColor(context.config, row.def.id))
        hooks.text(line.label, T(row.def.shortKey))
        local valueWidth = math.min(columnWidth * .7, math.max(columnWidth * .5, valueSize * 6))
        local id = row.def.id
        if RESOURCE_KEYS[id] then
            local mode = ResourceMode(context.config, id)
            PaintResourceText(hooks, line.value, ReadResource(module, id), mode, true)
            resourceLines[id] = line
            valueWidth = math.min(columnWidth - fontSize * 2 - 4, math.max(valueWidth, ResourceTextWidth(mode, valueSize)))
        elseif id == "movespeed" then
            popup.speedLineValue = line.value
        else
            local display, _, mode, first, second = ReadStatDisplay(module, row.def, true)
            if not PaintStatText(hooks, line.value, row.def, mode, first, second, true) then
                hooks.text(line.value, display)
            end
        end
        hooks.textWidth(line.label, columnWidth - valueWidth); hooks.textWidth(line.value, valueWidth)
        line.foreverRow = row
        hooks.shown(line, true)
    end
    for index = #rows + 1, #popup.rows do popup.rows[index].foreverRow = nil; hooks.shown(popup.rows[index], false) end
end

function Forever.SelectView(module, value)
    if not module.enabled or not module.statsFrame or not module.statsFrame:IsShown()
        or module.foreverDragging or module:IsStatsLayoutEditing() then return false end
    if value == "ALL" and Forever.OverviewShown(module) then
        Forever.CloseOverview(module)
        return true
    end
    if InCombat() then return false end
    local context = Forever.Resolve(module)
    if not context then return false end
    if value == "ALL" then
        local popup = module.foreverOverview or BuildOverview(module)
        PrepareOverview(module, popup)
        Forever.HideTooltip(module)
        popup:Show()
    else
        local preset = value ~= "DEFAULT" and FindPreset(context.class, value) or nil
        if value ~= "DEFAULT" and not preset then return false end
        module.foreverTemporaryPreset = preset and { preset = preset, identity = context.identity, config = context.config } or nil
    end
    Forever.HideTooltip(module)
    Forever.Invalidate(module)
    module:UpdateStatsPanel()
    return true
end

function Forever.CycleView(module)
    if not module.enabled or not module.statsFrame or not module.statsFrame:IsShown()
        or InCombat() or module.foreverDragging or module:IsStatsLayoutEditing() then return false end
    local context = ViewContext(module)
    local presets = context and Data.treePresets[context.class]
    if not presets then return false end
    local index = Contains(presets, context.preset.id) or 0
    local nextID = presets[index % #presets + 1]
    local saved = Forever.Resolve(module)
    return Forever.SelectView(module, nextID == saved.preset.id and "DEFAULT" or nextID)
end

function Forever.HideTooltip(module)
    Forever.RestoreTooltipValue(module)
    if module.foreverHoveredLine and GameTooltip and GameTooltip:IsOwned(module.foreverHoveredLine) then
        GameTooltip:Hide()
    end
    module.foreverHoveredLine = nil
    Forever.SetHoveredRow(module, nil)
end

function Forever.SetHoveredRow(module, line)
    local previous = module.foreverHoveredRow
    if previous == line then return end
    if previous and previous.hoverHighlight then previous.hoverHighlight:Hide() end
    module.foreverHoveredRow = line
    if line and line.hoverHighlight then line.hoverHighlight:Show() end
end

function Forever.RestoreTooltipValue(module, tooltip)
    module.foreverResourceTipCurrent, module.foreverResourceTipMax = nil, nil
    local style = module.foreverTooltipValueStyle
    if not style or (tooltip and style.tooltip ~= tooltip) then return end
    module.foreverTooltipValueStyle = nil
    local path, size, flags = style.region:GetFont()
    if path == style.path and size == style.enlargedSize and (flags or "") == style.flags then
        style.region:SetFont(style.path, style.size, style.flags)
    end
end

local function EnlargeTooltipValue(module, tooltip)
    local value = _G.GameTooltipTextRight1
    if not value or not value.GetFont or not value.SetFont or not tooltip.HookScript then return end
    if not module.foreverTooltipValueHooks then
        local cleared = function(tip) Forever.RestoreTooltipValue(module, tip) end
        local hidden = function(tip)
            Forever.RestoreTooltipValue(module, tip)
            if module.foreverHoveredLine and tip:IsOwned(module.foreverHoveredLine) then
                module.foreverHoveredLine = nil
                Forever.SetHoveredRow(module, nil)
            end
        end
        tooltip:HookScript("OnTooltipCleared", cleared)
        tooltip:HookScript("OnHide", hidden)
        module.foreverTooltipValueHooks = true
    end
    local path, size, flags = value:GetFont()
    if type(path) ~= "string" or type(size) ~= "number" then return end
    local style = module.foreverTooltipValueCache
    if not style then style = {}; module.foreverTooltipValueCache = style end
    module.foreverTooltipValueStyle = style
    style.tooltip, style.region, style.path, style.size, style.flags = tooltip, value, path, size, flags or ""
    style.enlargedSize = math.max(size + 2, math.floor(size * 1.2 + .5))
    value:SetFont(path, style.enlargedSize, style.flags)
end

function Forever.UpdateMoveHighlight(module, forceHide)
    local frame = module.statsFrame
    local highlight = frame and frame.foreverMoveHighlight
    if not highlight then return end
    local shown = false
    if not forceHide and module.enabled and frame:IsShown() and not module:IsStatsLayoutEditing() then
        local hovering = module.isHovering
        if frame.IsMouseOver then hovering = frame:IsMouseOver() end
        shown = module.foreverDragging == true or (hovering == true and not InCombat()
            and Frame and Frame.IsShiftKeyDown and Frame.IsShiftKeyDown() == true
            and not Frame.IsAltKeyDown() and not Frame.IsControlKeyDown())
    end
    shown = shown == true
    if highlight.foreverShown ~= shown then
        highlight.foreverShown = shown
        if shown then highlight:Show() else highlight:Hide() end
    end
end

function Forever.FinishDrag(module, commit)
    if not module.foreverDragging then return end
    local frame = module.statsFrame
    local originalAnchor = module.foreverDragAnchor
    module.foreverDragAnchor = nil
    module.foreverDragging = nil
    frame:StopMovingOrSizing()
    local function RestoreAnchor()
        if originalAnchor and originalAnchor[1] then
            frame:ClearAllPoints()
            frame:SetPoint(unpack(originalAnchor, 1, 5))
        end
    end
    local layout = YUI.Layout
    if layout and layout.CommitFramePosition then
        if commit and not InCombat() then
            if not layout:CommitFramePosition(LAYOUT_ID, frame, "stats-modifier-drag") then RestoreAnchor() end
        else
            RestoreAnchor()
            if layout.RefreshFrame then layout:RefreshFrame(LAYOUT_ID) end
        end
    elseif commit and not InCombat() then
        local point, _, relativePoint, x, y = frame:GetPoint(1)
        module.settings.framePosition = { point = point, relativePoint = relativePoint, x = x, y = y, userPlaced = true }
    else
        RestoreAnchor()
    end
    Forever.UpdateMoveHighlight(module)
end

function Forever.CancelInteraction(module)
    Forever.FinishDrag(module, false)
    Forever.CloseOverview(module)
    if module.foreverTemporaryPreset or (module.foreverPlan and module.foreverPlan.context.temporary) then
        module.foreverPlan, module.foreverPlanDirty = nil, true
    end
    module.foreverTemporaryPreset = nil
    Forever.HideTooltip(module)
    module.isHovering = false
    Forever.UpdateMoveHighlight(module, true)
    if module.statsFrame then
        module.statsFrame.foreverSettingsArmed = nil
        module.statsFrame.foreverClickArmed = nil
        for _, line in ipairs(module.statsFrame.lines) do
            line.foreverSettingsArmed, line.foreverClickArmed = nil, nil
        end
    end
end

function Forever.PrepareMouse(module, target)
    local function Modifier(name)
        return Frame and Frame[name] and Frame[name]() == true
    end
    target:RegisterForDrag("LeftButton")
    target:SetScript("OnMouseDown", function(self, button)
        self.foreverSettingsArmed = button == "LeftButton" and Modifier("IsAltKeyDown")
            and not Modifier("IsShiftKeyDown") and not Modifier("IsControlKeyDown")
        self.foreverClickArmed = (button == "LeftButton" or button == "RightButton")
            and not Modifier("IsAltKeyDown") and not Modifier("IsShiftKeyDown") and not Modifier("IsControlKeyDown") and button or nil
    end)
    target:SetScript("OnMouseUp", function(self, button)
        local armed = self.foreverSettingsArmed
        local clicked = self.foreverClickArmed == button
        self.foreverSettingsArmed, self.foreverClickArmed = nil, nil
        if not module.enabled or module.foreverDragging then return end
        if not armed then
            if not clicked or Modifier("IsAltKeyDown") or Modifier("IsShiftKeyDown") or Modifier("IsControlKeyDown") then return end
            if self.IsMouseOver and not self:IsMouseOver() then return end
            if button == "LeftButton" then Forever.CycleView(module)
            elseif button == "RightButton" then Forever.SelectView(module, "ALL") end
            return
        end
        if button ~= "LeftButton" or not Modifier("IsAltKeyDown")
            or Modifier("IsShiftKeyDown") or Modifier("IsControlKeyDown") then return end
        if not InCombat() then
            Forever.CancelInteraction(module)
            Forever.Invalidate(module)
            module:UpdateStatsPanel()
        end
        Forever.HideTooltip(module)
        if YUI.Settings and YUI.Settings.OpenComponentFeature then
            YUI.Settings:OpenComponentFeature("CharacterStatsPanel")
        end
    end)
    target:SetScript("OnDragStart", function(self, button)
        self.foreverSettingsArmed, self.foreverClickArmed = nil, nil
        if button ~= "LeftButton" or not module.enabled or InCombat() or module:IsStatsLayoutEditing()
            or not Modifier("IsShiftKeyDown") or Modifier("IsAltKeyDown") or Modifier("IsControlKeyDown") then return end
        Forever.HideTooltip(module)
        module.foreverDragAnchor = { module.statsFrame:GetPoint(1) }
        module.foreverDragging = true
        module.statsFrame:StartMoving()
        Forever.UpdateMoveHighlight(module)
    end)
    target:SetScript("OnDragStop", function() Forever.FinishDrag(module, true) end)
end

function Forever.Release(module)
    Forever.CancelInteraction(module)
    module.foreverTooltipValueCache = nil
    module.foreverLastPublicStats = nil
    module.foreverContext, module.foreverPlan = nil, nil
    module.foreverResourceLines, module.foreverResourceStates, module.foreverRenderHooks = nil, nil, nil
    if module.foreverResourceMeters then
        for _, meter in pairs(module.foreverResourceMeters) do
            meter:Hide()
            meter._yuiStatsShown = false
        end
    end
    module.foreverIdentityDirty, module.foreverPlanDirty = true, true
    if module.statsFrame then
        for _, line in ipairs(module.statsFrame.lines) do line.foreverRow = nil end
    end
end

local function GetTooltipValueText(tooltip)
    local name = tooltip.GetName and tooltip:GetName()
    if not name or not tooltip.NumLines then return end
    return _G[name .. "TextRight" .. tooltip:NumLines()]
end

local function AddResourceTooltipLine(tooltip, hooks, title, state, mode, r, g, b, vr, vg, vb)
    tooltip:AddDoubleLine(title, "—", r, g, b, vr, vg, vb)
    local text = GetTooltipValueText(tooltip)
    PaintResourceText(hooks, text, state, mode)
    return text
end

local function AddStatTooltipLine(tooltip, module, hooks, def, r, g, b, vr, vg, vb)
    local display, _, mode, first, second = ReadStatDisplay(module, def, true)
    tooltip:AddDoubleLine(T(def.nameKey), display, r, g, b, vr, vg, vb)
    if hooks and mode and mode ~= "cached" then
        local text = GetTooltipValueText(tooltip)
        if text then PaintStatText(hooks, text, def, mode, first, second, true) end
    end
    return mode == "cached"
end

function Forever.ShowTooltip(module, line)
    if not GameTooltip or not line.foreverRow or not module.foreverPlan or module.foreverDragging then return end
    Forever.RestoreTooltipValue(module)
    local row, context = line.foreverRow, module.foreverPlan.context
    local def = row.def
    local tooltip = GameTooltip
    tooltip:SetOwner(line, "ANCHOR_RIGHT")
    tooltip:ClearLines()
    local labelR, labelG, labelB = line.label:GetTextColor()
    local valueR, valueG, valueB = line.value:GetTextColor()
    local resource = RESOURCE_KEYS[def.id]
    local hooks = module.foreverRenderHooks
    local state = resource and hooks and module.foreverResourceStates and module.foreverResourceStates[def.id]
    local hasCachedValue
    if state then
        module.foreverResourceTipCurrent = AddResourceTooltipLine(tooltip, hooks, T(def.shortKey),
            state, "CURRENT", labelR, labelG, labelB, valueR, valueG, valueB)
    else
        hasCachedValue = AddStatTooltipLine(tooltip, module, hooks, def, labelR, labelG, labelB, valueR, valueG, valueB)
    end
    tooltip:AddLine(" ")
    local seen = module.foreverTooltipSeen or {}
    module.foreverTooltipSeen = seen
    for id in pairs(seen) do seen[id] = nil end
    seen[def.id] = true
    local hasDetails = false
    if state then
        module.foreverResourceTipMax = AddResourceTooltipLine(tooltip, hooks, T(def.nameKey),
            state, "MAX", labelR, labelG, labelB, valueR, valueG, valueB)
        hasDetails = true
    end
    local function Add(id)
        local other = Data.byID[id]
        if other and not seen[id] and Forever.Mode(context, id) ~= HIDDEN then
            seen[id] = true
            hasDetails = true
            local r, g, b = Forever.GetLabelColor(module.settings, context.config, id)
            local cached = AddStatTooltipLine(tooltip, module, hooks, other, r, g, b, Forever.GetColor(context.config, id))
            hasCachedValue = hasCachedValue or cached
        end
    end
    for _, id in ipairs(def.related or {}) do
        if RelatedAllowed(context, def.id, id) then Add(id) end
    end
    local weapon = def.id:match("^(.-)_skill$")
    if weapon then
        hasDetails = true
        tooltip:AddDoubleLine(T("forever.skill_cap"), Forever.Format(Forever.Read(weapon .. "_skill_max")), .8, .85, .9, 1, 1, 1)
    end
    -- Explicit extra detail choices remain accessible from the same, single tooltip.
    local extraHeader = false
    for _, other in ipairs(Data.definitions) do
        local field = FieldOverride(context, other.id)
        if field and field.mode == DETAIL and not seen[other.id] then
            if not extraHeader then
                tooltip:AddLine(" ")
                tooltip:AddLine(T("forever.details"), .8, .85, .9)
                extraHeader = true
            end
            Add(other.id)
        end
    end
    if def.descriptionKey then
        if hasDetails then tooltip:AddLine(" ") end
        tooltip:AddLine(T(def.descriptionKey), .75, .82, .9, true)
    end
    if hasCachedValue then tooltip:AddLine(T("forever.cached_combat_stat"), .75, .82, .9, true) end
    if not line.foreverOverview then
        local target, value = line.foreverMeterTarget, line.foreverMeterValue
        if target and value then
            local difference = value - target
            local key = "forever.meter_reference"
            if type(context.config.meterTargets) == "table" and context.config.meterTargets[def.id] then key = "forever.meter_custom" end
            tooltip:AddLine(format(T(key), FormatStatValue(target, def, true)), .75, .82, .9, true)
            local changeKey = difference < 0 and "forever.meter_remaining" or "forever.meter_above"
            if difference == 0 then
                tooltip:AddLine(T("forever.meter_reached"), .75, .82, .9, true)
            else
                local delta = tonumber(format("%.9f", math.abs(difference)))
                local amount = delta < .1 and ("< " .. Forever.Format(.1)) or Forever.Format(delta)
                if def.percent then amount = format(T("forever.meter_points"), amount) end
                tooltip:AddLine(format(T(changeKey), amount), .75, .82, .9, true)
            end
        end
        tooltip:AddLine(" ")
        if context.temporary then tooltip:AddLine(format(T("forever.quick_current"), T(context.preset.nameKey)), .75, .82, .9, true) end
        tooltip:AddLine(T("forever.mouse_select_hint"), 1, 1, 1, true)
        tooltip:AddLine(T("forever.mouse_all_hint"), 1, 1, 1, true)
        tooltip:AddLine(T("forever.mouse_drag_hint"), 1, 1, 1, true)
        tooltip:AddLine(" ")
        tooltip:AddLine(T("forever.mouse_settings_hint"), .6, .6, .6, true)
    end
    EnlargeTooltipValue(module, tooltip)
    tooltip:Show()
    module.foreverHoveredLine = line
    Forever.SetHoveredRow(module, line)
end

function Forever.PrepareLine(module, line)
    line:EnableMouse(true)
    line.label.gui2ColorKey, line.value.gui2ColorKey = nil, nil
    Forever.PrepareMouse(module, line)
    line:SetScript("OnEnter", function()
        module.isHovering, module.statsBaseAlpha = true, 1
        module:ApplyLinkedFadeAlpha()
        Forever.UpdateMoveHighlight(module)
        Forever.ShowTooltip(module, line)
        if not module.foreverDragging then Forever.SetHoveredRow(module, line) end
    end)
    line:SetScript("OnLeave", function()
        Forever.HideTooltip(module)
        module.isHovering = false
        module.statsBaseAlpha = (InCombat() or module.layoutPreviewing) and 1 or (module.settings.outOfCombatAlpha or 1)
        module:ApplyLinkedFadeAlpha()
        Forever.UpdateMoveHighlight(module)
    end)
end

local function PositionRegion(region, point, relative, relativePoint, x, y)
    if region.foreverPoint == point and region.foreverRelativePoint == relativePoint
        and region.foreverX == x and region.foreverY == y then return end
    region:ClearAllPoints()
    region:SetPoint(point, relative, relativePoint, x, y)
    region.foreverPoint, region.foreverRelativePoint = point, relativePoint
    region.foreverX, region.foreverY = x, y
end

local function RenderIcon(line, texture, appearance, hooks)
    local gui, icon = YUI.GUI2, line.foreverIcon
    if not appearance then
        if icon then hooks.shown(icon, false) end
        return
    end
    if not icon then
        icon = gui:CreateIconSlot(line, { variant = "bare", size = appearance.size, shape = appearance.shape,
            border = appearance.border, zoom = appearance.zoom, borderColor = appearance.borderColor,
            icon = texture, animate = false })
        icon:EnableMouse(false)
        icon.foreverTexture = texture
        line.foreverIcon = icon
    elseif icon.foreverTexture ~= texture then
        icon:SetIcon(texture)
        icon.foreverTexture = texture
    end
    if icon.foreverAppearance ~= appearance then
        if icon.foreverAppearance then
            icon:SetIconAppearance(appearance)
            icon:SetIconBorderColor(appearance.borderColor)
        end
        if appearance.shadow and appearance.shadowColor[4] > 0 then
            if not icon.foreverShadow then icon.foreverShadow = gui:CreateShapeShadow(icon) end
            gui:ApplyShapeShadow(icon.foreverShadow, { enabled = true, shape = appearance.shape, color = appearance.shadowColor },
                { anchor = icon, width = appearance.width, height = appearance.height })
        elseif icon.foreverShadow then
            gui:HideShapeShadow(icon.foreverShadow)
        end
        icon.foreverAppearance = appearance
    end
    hooks.shown(icon, true)
end

local function RenderMeter(line, fraction, left, bottom, width, r, g, b, hooks)
    local track, fill = line.foreverMeterTrack, line.foreverMeterFill
    if not fraction then
        if track then hooks.shown(track, false); hooks.shown(fill, false) end
        return
    end
    if not track then
        track = YUI.GUI2:CreateTexture(line, { layer = "ARTWORK", subLevel = -2 })
        track:SetColorTexture(0, 0, 0, .58)
        fill = YUI.GUI2:CreateTexture(line, { layer = "ARTWORK", subLevel = -1 })
        fill:SetPoint("LEFT", track, "LEFT")
        line.foreverMeterTrack, line.foreverMeterFill = track, fill
    end
    PositionRegion(track, "BOTTOMLEFT", line, "BOTTOMLEFT", left, bottom)
    hooks.size(track, width, METER_HEIGHT)
    hooks.shown(track, true)
    local pixels = floor(width * fraction + .5)
    if pixels > 0 then
        hooks.size(fill, pixels, METER_HEIGHT)
        if fill.foreverR ~= r or fill.foreverG ~= g or fill.foreverB ~= b then
            fill:SetColorTexture(r, g, b, .88)
            fill.foreverR, fill.foreverG, fill.foreverB = r, g, b
        end
    end
    hooks.shown(fill, pixels > 0)
end

local function PaintResourceMeter(bar, state, hooks)
    if not bar then return end
    local available = state.rawValuesAvailable and state.publicMaxValue ~= 0
    hooks.shown(bar, available)
    if not available then return end
    if state.secret or bar.foreverMax ~= state.maxValue then bar:SetMinMaxValues(0, state.maxValueRaw) end
    if state.secret or bar.foreverValue ~= state.value or bar.foreverMax ~= state.maxValue then
        bar:SetValue(state.valueRaw)
    end
    bar.foreverMax, bar.foreverValue = state.maxValue, state.value
end

local function LayoutResourceMeter(bar, line, left, bottom, width, r, g, b, hooks)
    PositionRegion(bar, "BOTTOMLEFT", line, "BOTTOMLEFT", left, bottom)
    hooks.size(bar, width, METER_HEIGHT)
    if bar.foreverR ~= r or bar.foreverG ~= g or bar.foreverB ~= b then
        bar:SetStatusBarColor(r, g, b, .9)
        bar.foreverR, bar.foreverG, bar.foreverB = r, g, b
    end
end

function Forever.RefreshResource(module, id)
    local hooks = module.foreverRenderHooks
    local plan = module.foreverPlan
    if not hooks or not plan or not module.enabled or not module.statsFrame:IsShown() then return end
    local line = module.foreverResourceLines and module.foreverResourceLines[id]
    local popup = module.foreverOverview
    local overview = Forever.OverviewShown(module) and popup.resourceLines and popup.resourceLines[id]
    if not line and not overview then return end
    local state, changed = ReadResource(module, id)
    if not changed then return end
    local mode = ResourceMode(plan.context.config, id)
    if line then
        PaintResourceText(hooks, line.value, state, mode)
        PaintResourceMeter(line.foreverActiveResourceMeter, state, hooks)
    end
    if overview then PaintResourceText(hooks, overview.value, state, mode, true) end
    local hovered = module.foreverHoveredLine
    if hovered and (hovered == line or hovered == overview) and GameTooltip and GameTooltip:IsOwned(hovered) then
        PaintResourceText(hooks, module.foreverResourceTipCurrent, state, "CURRENT")
        PaintResourceText(hooks, module.foreverResourceTipMax, state, "MAX")
    end
end

function Forever.Update(module, hooks)
    local frame, settings = module.statsFrame, module.settings
    local plan = Forever.Plan(module)
    if not frame or not plan then return end
    module.foreverRenderHooks = hooks
    local resourceLines = module.foreverResourceLines or {}
    module.foreverResourceLines = resourceLines
    resourceLines.hp, resourceLines.mana = nil, nil
    local previousWidth, previousHeight = frame:GetWidth(), frame:GetHeight()
    frame.speedLineValue = nil
    local config = Forever.EnsureSettings(settings)
    local fontSize = settings.fontSize or 14
    local fontPath = hooks.fontPath(settings.font)
    local valueFont, valueFontSize, valueEffect, valueMonochrome = ValueTextStyle(settings, hooks, fontPath)
    local enlargeCore = Forever.GetOption(config, "enlargeCore")
    local rowGap = Forever.GetOption(config, "rowGap")
    local width = math.max(settings.panelWidth or 128, MIN_PANEL_WIDTH)
    local horizontal = Forever.GetOption(config, "orientation") == "HORIZONTAL"
    local valueAlignment = horizontal and "CENTER" or Forever.GetOption(config, "valueAlignment")
    local valuesLeft = valueAlignment == "LEFT"
    local showNames = Forever.GetOption(config, "showNames")
    local showIcons = Forever.GetOption(config, "showIcons")
    local showMeters = Forever.GetOption(config, "showMeters")
    local appearance
    if showIcons and YUI.GUI2.IconSkins then
        local skin, size = GetIconSkin(config), Forever.GetOption(config, "iconSize")
        appearance = module.foreverIconAppearance
        if not appearance or appearance.skin ~= skin or appearance.size ~= size then
            appearance = YUI.GUI2.IconSkins:Resolve(skin, ICON_PRODUCT)
            appearance.size, appearance.skin = size, skin
            appearance.width, appearance.height = YUI.GUI2:GetIconAppearanceSize(size, appearance.shape)
            module.foreverIconAppearance = appearance
        end
    end
    local labelOffset = horizontal and 0 or (appearance and appearance.width + ICON_GAP or 0)
    local iconHeight = appearance and appearance.height or 0
    local horizontalIconSpace = appearance and iconHeight + ICON_GAP or 0
    local meterBottom = showMeters and (horizontal and 0 or METER_GAP) + Forever.GetOption(config, "meterYOffset") or 0
    -- Reserve any space below the row so a negative offset cannot reach the next row.
    local bottomPadding = math.max(0, -meterBottom)
    meterBottom = meterBottom + bottomPadding
    local meterSpace = (showMeters and METER_GAP + (horizontal and METER_HEIGHT or 0) or 0) + bottomPadding
    local columnGap = horizontal and math.max(0, tonumber(settings.columnSpacing) or 21) or 0
    local nameHeight = showNames and fontSize + 3 or 0
    local valueHeight = math.ceil(valueFontSize * (enlargeCore and 1.35 or 1)) + 3
    local rowHeight = math.max(nameHeight, valueHeight, iconHeight) + meterSpace
    local screenWidth
    if horizontal then
        screenWidth = UIParent and PublicNumber(UIParent:GetWidth())
        screenWidth = screenWidth and screenWidth > 0 and screenWidth or math.huge
        rowHeight = valueHeight + nameHeight + meterSpace + horizontalIconSpace
    end
    local widestLabel, widestValue = 0, 0
    for index, row in ipairs(plan.rows) do
        local line, id = frame.lines[index], row.def.id
        local valueSize = row.core and enlargeCore and valueHeight - 3 or valueFontSize
        hooks.shown(line.label, showNames)
        hooks.textWidth(line.value, 0)
        local labelWidth = 0
        if showNames then
            hooks.textWidth(line.label, 0)
            hooks.font(line.label, fontPath, fontSize, settings.fontEffect)
            labelWidth = hooks.text(line.label, T(row.shortKey)) or fontSize * 2
        end
        hooks.font(line.value, valueFont, valueSize, valueEffect, valueMonochrome)
        local valueWidth, value
        if RESOURCE_KEYS[id] then
            local mode = ResourceMode(config, id)
            resourceLines[id] = line
            PaintResourceText(hooks, line.value, ReadResource(module, id), mode)
            -- Reserve space independently of live or restricted resource values.
            valueWidth = ResourceTextWidth(mode, valueSize)
        elseif id == "movespeed" then
            frame.speedLineValue = line.value
            valueWidth = valueSize * 4
        else
            local display, mode, first, second
            display, value, mode, first, second = ReadStatDisplay(module, row.def)
            if PaintStatText(hooks, line.value, row.def, mode, first, second) then
                if horizontal or valuesLeft then
                    valueWidth = hooks.safeWidth(line.value, valueSize * (mode == "range" and 8 or 4))
                end
            else
                valueWidth = hooks.text(line.value, display)
            end
        end
        local target = showMeters and value and Forever.GetMeterTarget(config, row.def) or nil
        line.foreverMeterTarget, line.foreverMeterValue = target, target and value or nil
        if horizontal then
            local contentWidth = math.max(1, labelWidth, valueWidth or valueSize * 4, appearance and appearance.width or 0)
            line.foreverCellWidth = math.min(screenWidth, math.ceil(contentWidth) + HORIZONTAL_CELL_INSET * 2)
        elseif valuesLeft then
            widestLabel = math.max(widestLabel, labelWidth)
            widestValue = math.max(widestValue, valueWidth or valueSize * 4)
        end
    end
    local valueX
    if valuesLeft then
        local nameGap = showNames and Forever.GetOption(config, "valueColumnGap") or 0
        valueX = labelOffset + widestLabel + nameGap
        width = math.max(1, valueX + widestValue)
    end
    local rowPitch = rowHeight + rowGap
    local nextX, slot = 0, 0
    local frameWidth = horizontal and 1 or width
    for index, line in ipairs(frame.lines) do
        local row = plan.rows[index]
        if row then
            local cellWidth = horizontal and line.foreverCellWidth or width
            local x, y = 0, -(index - 1) * rowPitch
            if horizontal then
                if nextX > 0 and nextX + cellWidth > screenWidth then
                    nextX, slot = 0, slot + 1
                end
                x, y = nextX, -slot * rowPitch
                frameWidth = math.max(frameWidth, x + cellWidth)
                nextX = x + cellWidth + columnGap
            end
            if line.foreverX ~= x or line.foreverY ~= y then
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", frame.contentFrame, "TOPLEFT", x, y)
                line.foreverX, line.foreverY = x, y
            end
            hooks.size(line, cellWidth, rowHeight)
            local id = row.def.id
            local r, g, b = Forever.GetColor(config, id)
            hooks.color(line, settings.appearanceStyle, r, g, b)
            if line.foreverValueAlignment ~= valueAlignment then
                line.label:SetJustifyH(horizontal and "CENTER" or "LEFT")
                line.value:SetJustifyH(valueAlignment)
                line.foreverHorizontal, line.foreverValueAlignment = horizontal, valueAlignment
            end
            RenderIcon(line, row.def.icon, appearance, hooks)
            if horizontal then
                local decorated = appearance or showMeters
                local valueTop = decorated and horizontalIconSpace or nameHeight
                if showNames then
                    local labelY = decorated and -(horizontalIconSpace + valueHeight) or 0
                    PositionRegion(line.label, "TOP", line, "TOP", 0, labelY)
                end
                PositionRegion(line.value, "CENTER", line, "TOP", 0, -(valueTop + valueHeight / 2))
                if appearance then PositionRegion(line.foreverIcon, "TOP", line, "TOP", 0, 0) end
            else
                if showNames then PositionRegion(line.label, "LEFT", line, "LEFT", labelOffset, meterSpace / 2) end
                PositionRegion(line.value, valueAlignment, line, valueAlignment, valueX or 0, meterSpace / 2)
                if appearance and showMeters then
                    PositionRegion(line.foreverIcon, "BOTTOMLEFT", line, "BOTTOMLEFT", 0, meterSpace)
                elseif appearance then
                    PositionRegion(line.foreverIcon, "LEFT", line, "LEFT", 0, meterSpace / 2)
                end
            end
            local meterLeft = horizontal and HORIZONTAL_CELL_INSET or labelOffset
            local meterWidth = math.max(1, cellWidth - meterLeft - (horizontal and HORIZONTAL_CELL_INSET or 0))
            local target = line.foreverMeterTarget
            local fraction = target and math.min(1, math.max(0, line.foreverMeterValue / target))
            RenderMeter(line, fraction, meterLeft, meterBottom, meterWidth, r, g, b, hooks)
            local resourceMeter = RESOURCE_KEYS[id] and showMeters and module.foreverResourceMeters[id] or nil
            line.foreverActiveResourceMeter = resourceMeter
            if resourceMeter then
                LayoutResourceMeter(resourceMeter, line, meterLeft, meterBottom, meterWidth, r, g, b, hooks)
                PaintResourceMeter(resourceMeter, module.foreverResourceStates[id], hooks)
            end
            line.foreverRow = row
            hooks.shown(line, true)
        else
            if module.foreverHoveredLine == line then Forever.HideTooltip(module) end
            line.foreverRow = nil
            line.foreverActiveResourceMeter = nil
            hooks.shown(line, false)
        end
    end
    for id, bar in pairs(module.foreverResourceMeters) do
        if not showMeters or not resourceLines[id] then hooks.shown(bar, false) end
    end
    local rowCount = horizontal and slot + 1 or math.max(#plan.rows, 1)
    hooks.size(frame, frameWidth, rowCount * rowHeight + (rowCount - 1) * rowGap)
    hooks.size(frame.contentFrame, frameWidth, frame:GetHeight())
    hooks.scale(frame.contentFrame, 1)
    Forever.UpdateOverview(module, hooks)
    Forever.RefreshMovementSpeed(module)
    module:RefreshSpeedTickerState()
    if module.foreverHoveredLine then
        if GameTooltip and GameTooltip:IsOwned(module.foreverHoveredLine) then
            Forever.ShowTooltip(module, module.foreverHoveredLine)
        else
            Forever.RestoreTooltipValue(module)
            module.foreverHoveredLine = nil
            Forever.SetHoveredRow(module, nil)
        end
    end
    module:RefreshStatsLayoutBounds(previousWidth, previousHeight)
    Forever.UpdateMoveHighlight(module)
end

local function OrderedFields(context)
    local rows = {}
    for index, def in ipairs(Data.definitions) do
        rows[#rows + 1] = { def = def, index = index, mode = Forever.Mode(context, def.id), order = Order(context, def, index) }
    end
    table.sort(rows, function(a, b)
        local aResident, bResident = a.mode == RESIDENT, b.mode == RESIDENT
        if aResident ~= bResident then return aResident end
        if aResident and a.order ~= b.order then return a.order < b.order end
        return a.index < b.index
    end)
    return rows
end

function Forever.PrepareResourceMeters(module, parent)
    local meters = {}
    module.foreverResourceMeters = meters
    for id in pairs(RESOURCE_KEYS) do
        local bar = CreateFrame("StatusBar", nil, parent)
        bar:SetFrameLevel(parent:GetFrameLevel())
        bar:EnableMouse(false)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local background = YUI.GUI2:CreateTexture(bar, { layer = "BACKGROUND" })
        background:SetAllPoints(bar)
        background:SetColorTexture(0, 0, 0, .58)
        bar:Hide()
        bar._yuiStatsShown = false
        meters[id] = bar
    end
end

function Forever.MoveField(module, id, offset)
    local context = Forever.Resolve(module)
    if not context then return false end
    local rows, selected, count = OrderedFields(context), nil, 0
    for index, row in ipairs(rows) do
        if row.mode ~= RESIDENT then break end
        count = count + 1
        if row.def.id == id then selected = index end
    end
    local target = selected and selected + offset
    if not selected or target < 1 or target > count then return false end
    rows[selected], rows[target] = rows[target], rows[selected]
    for index = 1, count do
        local fieldID = rows[index].def.id
        local field = context.profile.fields[fieldID] or {}
        context.profile.fields[fieldID] = field
        field.order = index
    end
    Forever.SaveProfile(context)
    Forever.Invalidate(module)
    module:RefreshStatsSettings()
    return true
end

BuildOverview = function(module)
    local gui = YUI.GUI2
    local popup = gui:CreateFrame(UIParent, { name = "YUIStatsSpecializationOverview", hidden = true,
        width = 360, height = 240, movable = true, drag = "LeftButton", clamped = true, mouse = true })
    popup:SetFrameStrata("DIALOG")
    popup:SetPoint("CENTER", UIParent, "CENTER")
    popup.title = gui:CreateText(popup, T("forever.overview_title"), 14, "color.text.heading")
    popup.title:SetPoint("TOPLEFT", 16, -14)
    popup.identityIcon = gui:CreateTexture(popup, { width = 20, height = 20 })
    popup.identityIcon:SetPoint("TOPLEFT", 16, -34)
    popup.subtitle = gui:CreateText(popup, "", 16, "color.text.primary", "LEFT")
    popup.subtitle.gui2ColorKey = nil
    popup.subtitle:SetWordWrap(true)
    popup.close = gui.Form:CreateButton(popup, { text = T("forever.overview_close"), width = 52, height = 24,
        onClick = function() popup:Hide() end })
    popup.close:SetPoint("TOPRIGHT", -12, -9)
    popup.scroll = gui:CreateScrollFrame(popup, { width = 420, height = 160, childWidth = 420, autoHide = true })
    popup.scroll:SetPoint("TOPLEFT", 16, -60)
    popup.rows = {}
    popup:SetScript("OnHide", function()
        popup:StopMovingOrSizing()
        popup.speedLineValue = nil
        if not module.statsFrame.speedLineValue then module:StopSpeedTicker() end
        if module.foreverHoveredLine and module.foreverHoveredLine.foreverOverview then Forever.HideTooltip(module) end
        module.foreverOverviewRows = nil
        for _, line in ipairs(popup.rows) do line.foreverRow = nil end
    end)
    if gui.EnableEscapeClose then gui:EnableEscapeClose(popup, function() popup:Hide() end) end
    if gui.WindowAppearance then
        gui.WindowAppearance:Register(popup, { role = "dialog", themeProvider = function() return "native" end,
            headings = { popup.title } })
    end
    module.foreverOverview = popup
    return popup
end

PrepareOverview = function(module, popup)
    local context = Forever.Resolve(module)
    local name = Unit.GetCharacterName and Unit.GetCharacterName("player")
    popup.subtitle:SetText(IsPublic(name) and type(name) == "string" and name ~= "" and name or "—")
    local color = Unit.GetClassColor and Unit.GetClassColor(context.class)
    popup.subtitle:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
    local icons = YUI.API.Icons
    local icon = icons and icons.GetClassIcon and icons.GetClassIcon(context.class)
    popup.identityInset = icon and 42 or 16
    popup.subtitle:ClearAllPoints()
    popup.subtitle:SetPoint("TOPLEFT", popup.identityInset, -36)
    popup.identityIcon:SetShown(icon ~= nil)
    if icon then
        popup.identityIcon:SetTexture(icon.texture)
        popup.identityIcon:SetTexCoord(unpack(icon.texCoord))
    end
    for index = 1, #Forever.OverviewRows(module) do
        if not popup.rows[index] then
            local line = YUI.GUI2:CreateFrame(popup.scroll.child, { mouse = true })
            line.label = YUI.GUI2:CreateText(line, "", 14, "color.text.primary")
            line.value = YUI.GUI2:CreateText(line, "", 14, "color.text.primary", "RIGHT")
            line.label:SetPoint("LEFT")
            line.value:SetPoint("RIGHT")
            line.label:SetWordWrap(false); line.value:SetWordWrap(false)
            line.label.gui2ColorKey, line.value.gui2ColorKey = nil, nil
            line.foreverOverview = true
            line:SetScript("OnEnter", function() Forever.ShowTooltip(module, line) end)
            line:SetScript("OnLeave", function() Forever.HideTooltip(module) end)
            popup.rows[index] = line
        end
    end
end

local function RenderFieldTable(module, context, parent, x, y, width, descriptors)
    local gui = YUI.GUI2
    width = math.max(320, math.min(width or 500, (parent:GetWidth() or 500) - x - 10))
    local showMeters = Forever.GetOption(context.config, "showMeters")
    local stacked = showMeters and width < 490
    local meterWidth = 84
    local meterSpace = showMeters and not stacked and meterWidth + 8 or 0
    local rowHeight, headerHeight = 30, 26
    local pitch = rowHeight + (stacked and 24 or 0)
    local container = gui:CreateFrame(parent, { width = width, height = headerHeight + #Data.definitions * pitch })
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local modeWidth = math.min(160, math.max(110, math.floor((width - meterSpace) * .3)))
    local modeX, numberX = width - modeWidth - 94 - meterSpace, width - 86
    local meterX = numberX - meterSpace
    local colorX = modeX - 36
    local function Text(label, left, top, textWidth, color)
        local text = gui:CreateText(container, label, "font.size.md", color or "color.text.primary")
        text:SetPoint("TOPLEFT", container, "TOPLEFT", left, top)
        text:SetWidth(textWidth)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        return text
    end
    Text(T("forever.field"), 0, 0, colorX - 8, "color.text.secondary")
    Text(T("forever.color"), colorX, 0, 36, "color.text.secondary")
    Text(T("forever.field_mode"), modeX, 0, modeWidth, "color.text.secondary")
    if showMeters and not stacked then Text(T("forever.meter_field"), meterX, 0, meterWidth, "color.text.secondary") end
    Text(T("forever.order"), numberX, 0, 86, "color.text.secondary")
    local controls, RefreshRows = {}, nil
    for _, descriptor in ipairs(descriptors) do
        local field = descriptor
        local id = field.id
        local row = gui:CreateFrame(container, { width = width, height = rowHeight })
        local name = gui:CreateText(row, field.label, "font.size.md", "color.text.primary")
        name.gui2ColorKey = nil
        name:SetPoint("LEFT", row, "LEFT", 0, 0)
        name:SetWidth(colorX - 8)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        name:SetTextColor(Forever.GetLabelColor(module.settings, context.config, id))
        local color = gui.Form:CreateColorPicker(row, {
            type = "color", width = 24, height = 24, field = false, hasAlpha = false,
            tooltip = field.label, default = Data.byID[id].color, get = field.color.get,
            set = function(value)
                field.color.set(value)
                name:SetTextColor(Forever.GetLabelColor(module.settings, context.config, id))
            end,
        })
        color:SetPoint("LEFT", row, "LEFT", colorX, 0)
        local dropdown = gui.Form:CreateDropdown(row, {
            type = "dropdown", width = modeWidth, height = 24, options = field.options, get = field.get,
            tooltip = field.tooltip,
            set = function(value)
                field.set(value)
                RefreshRows()
            end,
        })
        dropdown:SetPoint("LEFT", row, "LEFT", modeX, 0)
        local number = gui:CreateText(row, "", "font.size.md", "color.text.secondary")
        number:SetPoint("LEFT", row, "LEFT", numberX, 0)
        number:SetWidth(28)
        number:SetJustifyH("CENTER")
        local up = gui.Form:CreateButton(row, { text = "↑", width = 24, height = 24,
            tooltip = T("forever.move_up"), onClick = function() Forever.MoveField(module, id, -1); RefreshRows() end })
        up:SetPoint("RIGHT", row, "RIGHT", -28, 0)
        local down = gui.Form:CreateButton(row, { text = "↓", width = 24, height = 24,
            tooltip = T("forever.move_down"), onClick = function() Forever.MoveField(module, id, 1); RefreshRows() end })
        down:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        local meter, meterLabel
        local def = Data.byID[id]
        if showMeters and HasMeter(def) then
            local function ReadTarget() return Forever.Format(Forever.GetMeterTarget(context.config, def), def.percent) end
            meter = gui.Form:CreateEditBox(row, {
                width = meterWidth, height = 22, get = ReadTarget, tooltip = T("forever.meter_edit_hint"),
                onFocusLost = function(edit)
                    if Forever.EnsureSettings(module.settings) == context.config
                        and SetMeterTarget(context.config, def, edit:GetText()) then module:UpdateStatsPanel() end
                    edit:SetValue(ReadTarget(), true)
                end,
            })
            meter:SetScript("OnEnterPressed", function(edit) edit:ClearFocus() end)
            meter:SetScript("OnEscapePressed", function(edit)
                edit:SetValue(ReadTarget(), true)
                edit:ClearFocus()
            end)
            if stacked then
                meterLabel = gui:CreateText(row, T("forever.meter_field"), "font.size.sm", "color.text.secondary")
                meterLabel:SetPoint("LEFT", row, "BOTTOMLEFT", 0, -10)
                meter:SetPoint("LEFT", meterLabel, "RIGHT", 8, 0)
            else
                meter:SetPoint("LEFT", row, "LEFT", meterX, 0)
            end
        end
        controls[id] = { frame = row, label = name, color = color, mode = dropdown, number = number, up = up, down = down,
            meter = meter, meterLabel = meterLabel }
        if YUI.Settings and YUI.Settings.Search then YUI.Settings.Search:Bind(field, dropdown, name) end
    end
    function container:RefreshColors()
        for id, control in pairs(controls) do
            control.label:SetTextColor(Forever.GetLabelColor(module.settings, context.config, id))
        end
    end
    RefreshRows = function()
        local rows, count = OrderedFields(context), 0
        for _, row in ipairs(rows) do if row.mode == RESIDENT then count = count + 1 end end
        for index, row in ipairs(rows) do
            local control = controls[row.def.id]
            control.frame:ClearAllPoints()
            control.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -headerHeight - (index - 1) * pitch)
            control.number:SetText(row.mode == RESIDENT and tostring(index) or "—")
            control.up:SetDisabled(row.mode ~= RESIDENT or index == 1)
            control.down:SetDisabled(row.mode ~= RESIDENT or index == count)
            if control.meter then control.meter:SetShown(row.mode == RESIDENT) end
            if control.meterLabel then control.meterLabel:SetShown(row.mode == RESIDENT) end
        end
    end
    RefreshRows()
    container.foreverFieldControls = controls
    return width, container:GetHeight(), container
end

function Forever.GetOptions(module, feature, shared)
    local context = Forever.Resolve(module)
    if not context then return {} end
    local colorTable
    local function Refresh(rebuild)
        module:RefreshStatsSettings()
        if colorTable and colorTable:IsShown() then colorTable:RefreshColors() end
        if rebuild and feature and feature.RefreshCurrentModule then feature:RefreshCurrentModule() end
    end
    local function Divider(key)
        return { type = "divider", label = T(key), alignLeft = true, collapsible = true,
            collapseKey = "component.character_stats_panel.compact." .. key, collapsed = false }
    end
    local autoText = T("forever.automatic")
    if context.automatic then autoText = autoText .. " · " .. T(context.preset.nameKey) end
    local presetOptions = { { text = autoText, value = "AUTO" } }
    for _, preset in ipairs(Data.presets[context.class]) do
        presetOptions[#presetOptions + 1] = { text = T(preset.nameKey), value = preset.id }
    end
    local config = context.config
    local gui = YUI.GUI2
    local options = {}
    local function AddGrid(fields, hidden)
        for _, field in ipairs(fields) do
            if field.type ~= "checkbox" then
                field.layoutPreset = "inlineSelector"
                field.labelWidth, field.minLabelWidth = 112, 112
            end
        end
        options[#options + 1] = { type = "custom", hidden = hidden, retainedFields = fields, render = function(parent, x, y, width)
            local _, gridWidth, gridHeight = YUI.Settings:RenderAlignedFields(parent, {
                x = x, y = y, width = width, columns = 2, columnGap = 20, minColumnWidth = 266,
                labelPosition = "top", rowHeight = 30, rowGap = 8, valueGap = 8, fields = fields,
            })
            return gridWidth, gridHeight
        end }
    end
    local formats = {}
    for _, mode in ipairs(RESOURCE_MODES) do
        formats[#formats + 1] = { value = mode, text = T("forever.resource_format." .. mode) }
    end
    local function ResourceField(id)
        local key = RESOURCE_KEYS[id]
        return { type = "dropdown", label = T("forever.resource_display." .. id), options = formats,
            get = function() return ResourceMode(config, id) end,
            set = function(mode)
                if not RESOURCE_FORMATS[mode] then return end
                config[key] = mode ~= DEFAULT_RESOURCE_MODE and mode or nil
                module:UpdateStatsPanel()
            end }
    end
    AddGrid({
        { type = "segmented", label = T("stats.settings.panel_orientation"),
            items = { { text = T("stats.option.vertical"), value = "VERTICAL" },
                { text = T("stats.option.horizontal"), value = "HORIZONTAL" } },
            get = function() return Forever.GetOption(config, "orientation") end,
            set = function(value) Forever.SetOption(config, "orientation", value); Refresh(true) end },
        { type = "dropdown", label = T("forever.playstyle"), options = presetOptions,
            get = function() return config.selections[context.identity] or "AUTO" end,
            set = function(value) config.selections[context.identity] = value ~= "AUTO" and value or nil; Refresh(true) end },
        ResourceField("hp"), ResourceField("mana"),
    })
    options[#options + 1] = { type = "row", gap = 12, rowGap = 8,
        children = {
            { type = "checkbox", label = T("stats.settings.panel_shown"), width = 150,
                get = function() return module.settings.panelShown ~= false end,
                set = function(value) module:SetPanelShown(value == true) end },
            { type = "checkbox", label = T("forever.show_names"), width = 140,
                get = function() return Forever.GetOption(config, "showNames") end,
                set = function(value) Forever.SetOption(config, "showNames", value == true); Refresh(true) end },
            { type = "checkbox", label = T("common.show_icon"), width = 112,
                get = function() return Forever.GetOption(config, "showIcons") end,
                set = function(value) Forever.SetOption(config, "showIcons", value == true); Refresh(true) end },
            { type = "checkbox", label = T("forever.show_meters"), width = 135,
                get = function() return Forever.GetOption(config, "showMeters") end,
                set = function(value) Forever.SetOption(config, "showMeters", value == true); Refresh(true) end },
        } }
    if context.automatic and not context.known then
        options[#options + 1] = { type = "text", label = T("forever.auto_unknown"), colorKey = "color.state.warning" }
    end
    local function Setting(fields, kind, key, label, extra, target)
        local field = extra or {}
        field.type, field.label = kind, T(label)
        field.get = function()
            if target then return Forever.GetOption(target, key) end
            return module.settings[key]
        end
        field.set = function(value)
            if not module.settings or module.settings.forever ~= config then return end
            if target then Forever.SetOption(target, key, value) else module.settings[key] = value end
            if key == "rowGap" then Forever.SyncLegacyLayout(module.settings, config, true) end
            Refresh(field.rebuild == true)
        end
        fields[#fields + 1] = field
    end
    local styleFields = {}
    if gui.Form and gui.Form.CreateFontStyle then
        local function FontStyleField(label, key)
            return { type = "custom", label = T(label), fontStyleKey = key,
                render = function(parent, _, width) return gui.Form:CreateFontStyle(parent, { key = key, width = width }) end }
        end
        styleFields[1] = FontStyleField("forever.label_text", "character_stats:text")
        styleFields[2] = FontStyleField("forever.value_text", "character_stats:value")
    else
        Setting(styleFields, "dropdown", "font", "common.font", { options = shared.fontOptions })
        Setting(styleFields, "slider", "fontSize", "common.font_size", { min = 8, max = Forever.FONT_SIZE_MAX, step = 1 })
        Setting(styleFields, "dropdown", "fontEffect", "stats.settings.font_effect", { options = shared.fontEffectOptions })
    end
    Setting(styleFields, "dropdown", "appearanceStyle", "stats.settings.appearance_style", { options = shared.styleOptions })
    Setting(styleFields, "checkbox", "enlargeCore", "forever.enlarge_core", nil, config)
    local function IsVertical() return Forever.GetOption(config, "orientation") == "VERTICAL" end
    local function UsesValueGap() return IsVertical() and Forever.GetOption(config, "valueAlignment") == "LEFT" end
    Setting(styleFields, "dropdown", "valueAlignment", "forever.value_alignment", {
        options = { { value = "LEFT", text = T("stats.option.align_left") }, { value = "RIGHT", text = T("stats.option.align_right") } },
        hidden = function() return not IsVertical() end, rebuild = true,
    }, config)
    Setting(styleFields, "slider", "panelWidth", "stats.settings.panel_width",
        { min = MIN_PANEL_WIDTH, max = 400, step = 1, hidden = function() return not IsVertical() or UsesValueGap() end })
    Setting(styleFields, "slider", "valueColumnGap", "stats.settings.column_spacing",
        { min = 0, max = 60, step = 1,
            hidden = function() return not UsesValueGap() or not Forever.GetOption(config, "showNames") end }, config)
    Setting(styleFields, "slider", "rowGap", "stats.settings.row_spacing", { min = 0, max = 30, step = 1 }, config)
    Setting(styleFields, "slider", "columnSpacing", "stats.settings.column_spacing", { min = 0, max = 60, step = 1,
        hidden = IsVertical })
    Setting(styleFields, "slider", "meterYOffset", "forever.meter_y_offset", {
        min = -METER_Y_OFFSET_LIMIT, max = METER_Y_OFFSET_LIMIT, step = 1,
        tooltip = T("forever.meter_y_offset_hint"),
        hidden = function() return not Forever.GetOption(config, "showMeters") end,
    }, config)
    Setting(styleFields, "slider", "outOfCombatAlpha", "stats.settings.out_of_combat_alpha", { min = 0, max = 1, step = .05 })
    local function IconsHidden() return not Forever.GetOption(config, "showIcons") end
    if gui.IconSkins and gui.Form and gui.Form.CreateIconSkinControl then
        local iconFields = {
            { type = "custom", label = gui.IconSkins:Label("title", T("forever.icon_style")),
                render = function(parent, _, width)
                    return gui.Form:CreateIconSkinControl(parent, {
                        width = width, product = ICON_PRODUCT, builtinOnly = true,
                        getStyle = function() return GetIconSkin(config) end,
                        set = function(style)
                            if Forever.EnsureSettings(module.settings) ~= config then return end
                            SaveIconSkin(config, style)
                            Refresh()
                        end,
                    })
                end },
        }
        Setting(iconFields, "slider", "iconSize", "forever.icon_size", { min = 12, max = 40, step = 1 }, config)
        local iconDivider = Divider("forever.icon_style")
        iconDivider.hidden = IconsHidden
        options[#options + 1] = iconDivider
        AddGrid(iconFields, IconsHidden)
    end
    options[#options + 1] = Divider("forever.text_spacing")
    AddGrid(styleFields)
    options[#options + 1] = Divider("forever.fields")
    options[#options + 1] = { type = "button", label = T("forever.restore"), width = 170,
        onClick = function() context.profile.fields = {}; Forever.SaveProfile(context); Refresh(true) end }
    options[#options + 1] = { type = "text", label = T("forever.fields_hint"), colorKey = "color.text.secondary" }
    options[#options + 1] = { type = "text", label = T("forever.meter_edit_hint"), colorKey = "color.text.secondary",
        hidden = function() return not Forever.GetOption(config, "showMeters") end }
    local modeOptions = {
        { text = T("forever.resident"), value = RESIDENT },
        { text = T("forever.detail"), value = DETAIL },
        { text = T("forever.hidden"), value = HIDDEN },
    }
    local descriptors, retainedFields = {}, {}
    for _, definition in ipairs(Data.definitions) do
        local def = definition
        local color = { type = "color", id = def.id, label = T(def.nameKey),
            get = function()
                local r, g, b = Forever.GetColor(context.config, def.id)
                return { r, g, b, 1 }
            end,
            set = function(value) Forever.SetColor(module, def.id, value, context.config) end,
        }
        local field = { type = "dropdown", id = def.id, label = T(def.nameKey), color = color,
            tooltip = T(def.descriptionKey), options = modeOptions,
            get = function() return Forever.Mode(context, def.id) end,
            set = function(value)
                local fields = context.profile.fields
                if not FieldOverride(context, def.id) then fields[def.id] = {} end
                fields[def.id].mode = value
                Forever.SaveProfile(context)
                Refresh()
            end,
        }
        descriptors[#descriptors + 1] = field
        retainedFields[#retainedFields + 1] = color
        retainedFields[#retainedFields + 1] = field
    end
    options[#options + 1] = { type = "custom", retainedFields = retainedFields, render = function(parent, x, y, width)
        local tableWidth, tableHeight, widget = RenderFieldTable(module, context, parent, x, y, width, descriptors)
        colorTable = widget
        return tableWidth, tableHeight, widget
    end }
    return options
end

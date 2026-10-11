local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.Components then return end

local Components = YUI.Components
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"
local S = YUI.Settings
local GUI2 = YUI.GUI2
local UnitAPI = YUI.API and YUI.API.Unit or YUI.WOW_API or {}
local TalentAPI = YUI.API and YUI.API.Talent or YUI.WOW_API or {}
local Icons = YUI.API and YUI.API.Icons
local L = YUI.Locale and YUI.Locale:Get("LagTolerance") or {}

local FEATURE_KEY = "LagTolerance"
local CONFIG_KEY = "LagTolerance_Config"
local EXPORT_PREFIX = "YUI-LT:v1:"
local LEGACY_EXPORT_PREFIX = "YUI-LAGTOLERANCE:v1:"
local CVAR_NAME = "SpellQueueWindow"
local ICON_SCOPE_ID = "settings"

local MODE_FIXED_ALL = "fixed_all"
local MODE_AUTO_ALL = "auto_all"
local MODE_FIXED_CLASS = "fixed_class"
local MODE_AUTO_CLASS = "auto_class"
local MODE_FIXED_SPEC = "fixed_spec"
local MODE_AUTO_SPEC = "auto_spec"

local FIXED_DEFAULT = 400
local AUTO_DEFAULT = 250
local MIN_VALUE = 0
local MAX_VALUE = 400
local AUTO_REFRESH_INTERVAL = 5
local VALUE_MAX_LETTERS = #tostring(MAX_VALUE)
local VALUE_GRID_COLUMNS = 3
local VALUE_GRID_GAP = 10
local VALUE_CELL_HEIGHT = 40
local VALUE_EDIT_WIDTH = 72
local VALUE_EDIT_WIDTH_COMPACT = 82
local VALUE_EDIT_HEIGHT = 26
local VALUE_ICON_SIZE = 26
local BATCH_BUTTON_WIDTH = 86
local TYPE_DROPDOWN_WIDTH = VALUE_EDIT_WIDTH + BATCH_BUTTON_WIDTH * 2 + 6 * 2
local CLASS_ICON_TEXCOORD_INSET = 0.07
local COLOR_RESET = "|r"
local COLOR_WHITE = "|cffffffff"
local COLOR_FIXED = "|cff35bf61"
local COLOR_AUTO = "|cffb56cff"
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local CLASS_ICON_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

local function T(key, fallback, ...)
    local value = L and L[key]
    if not value or value == "" or value == key then value = fallback or key end
    if select("#", ...) > 0 then
        return string.format(value, ...)
    end
    return value
end

local function UseCompactSpecNames()
    return YUI.Locale
        and YUI.Locale.UsesCompactSpecializationNames
        and YUI.Locale:UsesCompactSpecializationNames() == true
end

local function GetSpecDisplayName(specID, fallback)
    if YUI.Locale and YUI.Locale.GetSpecializationName then
        return YUI.Locale:GetSpecializationName(specID, fallback)
    end
    return fallback or tostring(specID or "")
end

local function GetValueCellEditWidth(entry)
    return entry and entry.specID and UseCompactSpecNames() and VALUE_EDIT_WIDTH_COMPACT or VALUE_EDIT_WIDTH
end

local function ColorizeKeyword(text, keyword, color)
    return tostring(text or ""):gsub(keyword, color .. keyword .. COLOR_RESET)
end

local function ColorizeModeText(text)
    return ColorizeKeyword(ColorizeKeyword(text, T("mode.fixed_keyword", "Fixed"), COLOR_FIXED), T("mode.auto_keyword", "Auto"), COLOR_AUTO)
end

local MODE_LABEL_KEYS = {
    [MODE_FIXED_ALL] = "mode.fixed_all",
    [MODE_AUTO_ALL] = "mode.auto_all",
    [MODE_FIXED_CLASS] = "mode.fixed_class",
    [MODE_AUTO_CLASS] = "mode.auto_class",
    [MODE_FIXED_SPEC] = "mode.fixed_spec",
    [MODE_AUTO_SPEC] = "mode.auto_spec",
}

local MODE_LABEL_FALLBACKS = {
    [MODE_FIXED_ALL] = "All Classes Fixed",
    [MODE_AUTO_ALL] = "All Classes Auto",
    [MODE_FIXED_CLASS] = "Class Fixed",
    [MODE_AUTO_CLASS] = "Class Auto",
    [MODE_FIXED_SPEC] = "Spec Fixed",
    [MODE_AUTO_SPEC] = "Spec Auto",
}

local function GetModeLabel(mode)
    return ColorizeModeText(T(MODE_LABEL_KEYS[mode], MODE_LABEL_FALLBACKS[mode] or tostring(mode)))
end

local function GetModeOptions()
    if YUI.IsForever then
        return {
            { text = GetModeLabel(MODE_FIXED_ALL), selectionText = GetModeLabel(MODE_FIXED_ALL), value = MODE_FIXED_ALL },
            { text = GetModeLabel(MODE_AUTO_ALL), selectionText = GetModeLabel(MODE_AUTO_ALL), value = MODE_AUTO_ALL },
        }
    end
    return {
        { text = GetModeLabel(MODE_FIXED_ALL), selectionText = GetModeLabel(MODE_FIXED_ALL), value = MODE_FIXED_ALL },
        { text = GetModeLabel(MODE_AUTO_ALL), selectionText = GetModeLabel(MODE_AUTO_ALL), value = MODE_AUTO_ALL },
        { text = GetModeLabel(MODE_FIXED_CLASS), selectionText = GetModeLabel(MODE_FIXED_CLASS), value = MODE_FIXED_CLASS },
        { text = GetModeLabel(MODE_AUTO_CLASS), selectionText = GetModeLabel(MODE_AUTO_CLASS), value = MODE_AUTO_CLASS },
        { text = GetModeLabel(MODE_FIXED_SPEC), selectionText = GetModeLabel(MODE_FIXED_SPEC), value = MODE_FIXED_SPEC },
        { text = GetModeLabel(MODE_AUTO_SPEC), selectionText = GetModeLabel(MODE_AUTO_SPEC), value = MODE_AUTO_SPEC },
    }
end

local AUTO_MODES = {
    [MODE_AUTO_ALL] = true,
    [MODE_AUTO_CLASS] = true,
    [MODE_AUTO_SPEC] = true,
}

local MODE_DEFAULTS = {
    [MODE_FIXED_ALL] = FIXED_DEFAULT,
    [MODE_FIXED_CLASS] = FIXED_DEFAULT,
    [MODE_FIXED_SPEC] = FIXED_DEFAULT,
    [MODE_AUTO_ALL] = AUTO_DEFAULT,
    [MODE_AUTO_CLASS] = AUTO_DEFAULT,
    [MODE_AUTO_SPEC] = AUTO_DEFAULT,
}

local SPEC_RANGE_MELEE = {
    [250] = true, [251] = true, [252] = true, -- 死亡骑士
    [577] = true, [581] = true, -- 恶魔猎手
    [103] = true, [104] = true, -- 德鲁伊
    [268] = true, [269] = true, [270] = true, -- 武僧
    [65] = true, [66] = true, [70] = true, -- 圣骑士
    [259] = true, [260] = true, [261] = true, -- 潜行者
    [263] = true, -- 萨满祭司
    [71] = true, [72] = true, [73] = true, -- 战士
}

local SPEC_RANGE_RANGED = {
    [1480] = true, -- 恶魔猎手：噬灭
    [62] = true, [63] = true, [64] = true, -- 法师
    [265] = true, [266] = true, [267] = true, -- 术士
    [256] = true, [257] = true, [258] = true, -- 牧师
    [1467] = true, [1468] = true, [1473] = true, -- 唤魔师
    [102] = true, [105] = true, -- 德鲁伊
    [253] = true, [254] = true, -- 猎人
    [262] = true, [264] = true, -- 萨满祭司
}

local ARMOR_GROUPS = {
    { labelKey = "armor.cloth", fallback = "Cloth", classes = { "MAGE", "PRIEST", "WARLOCK" } },
    { labelKey = "armor.leather", fallback = "Leather", classes = { "DEMONHUNTER", "MONK", "ROGUE", "DRUID" } },
    { labelKey = "armor.mail", fallback = "Mail", classes = { "EVOKER", "HUNTER", "SHAMAN" } },
    { labelKey = "armor.plate", fallback = "Plate", classes = { "DEATHKNIGHT", "PALADIN", "WARRIOR" } },
}

local CLASS_TOKENS = {
    "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER",
    "MAGE", "MONK", "PALADIN", "PRIEST", "ROGUE", "SHAMAN",
    "WARLOCK", "WARRIOR",
}

local function GetClassDisplayName(classToken, fallback)
    if YUI.Locale and YUI.Locale.GetClassName then
        return YUI.Locale:GetClassName(classToken, fallback)
    end
    return fallback or classToken or ""
end

local isFeatureEnabled = false
local autoTicker
local lastAppliedValue
local lastApplyErrorAt = 0

local function IsValidMode(mode)
    if YUI.IsForever then return mode == MODE_FIXED_ALL or mode == MODE_AUTO_ALL end
    return MODE_DEFAULTS[mode] ~= nil
end

local function IsAutoMode(mode)
    return AUTO_MODES[mode] == true
end

local function GetSpecRange(specID)
    specID = tonumber(specID)
    if not specID then return nil end
    if specID == 255 then
        return YUI.IsRetail and "melee" or "ranged"
    elseif SPEC_RANGE_MELEE[specID] then
        return "melee"
    elseif SPEC_RANGE_RANGED[specID] then
        return "ranged"
    end
    return nil
end

local function ClampValue(value)
    value = tonumber(value)
    if not value then return nil end
    value = math.floor(value + 0.5)
    if value < MIN_VALUE then
        return MIN_VALUE
    elseif value > MAX_VALUE then
        return MAX_VALUE
    end
    return value
end

local function NormalizeSavedValue(value)
    if value == nil or value == "" then
        return nil
    end
    return ClampValue(value)
end

local function GetStore()
    if Components.GetStore then
        local store = Components:GetStore(PRODUCT_ID)
        if type(store) == "table" then return store end
    end
    return nil
end

local function GetDB()
    local db
    if Components.EnsureConfig then
        db = Components:EnsureConfig(CONFIG_KEY, {}, PRODUCT_ID)
    else
        local store = GetStore()
        if not store then return nil end
        if type(store[CONFIG_KEY]) ~= "table" then
            store[CONFIG_KEY] = {}
        end
        db = store[CONFIG_KEY]
    end

    if not IsValidMode(db.mode) then db.mode = MODE_FIXED_ALL end
    if type(db.classFixed) ~= "table" then db.classFixed = {} end
    if type(db.classAuto) ~= "table" then db.classAuto = {} end
    if type(db.specFixed) ~= "table" then db.specFixed = {} end
    if type(db.specAuto) ~= "table" then db.specAuto = {} end
    db.fixedAll = NormalizeSavedValue(db.fixedAll)
    db.autoAll = NormalizeSavedValue(db.autoAll)
    return db
end

local function GetTooltipStore()
    return GetStore()
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

local function BuildSpecKey(classToken, specID)
    return tostring(classToken or "UNKNOWN") .. ":" .. tostring(specID or 0)
end

local function GetActiveSpecKey()
    local classToken = GetPlayerClassToken()
    if (TalentAPI.GetCurrentConfigurationSpecializationInfo or TalentAPI.GetCurrentSpecializationInfo) then
        local specInfo = (TalentAPI.GetCurrentConfigurationSpecializationInfo or TalentAPI.GetCurrentSpecializationInfo)()
        if specInfo then
            return BuildSpecKey(specInfo.classFile or classToken, specInfo.specID or 0)
        end
    end

    local specIndex = TalentAPI.GetSpecialization and TalentAPI.GetSpecialization() or GetSpecialization and GetSpecialization()
    if specIndex then
        local specID = TalentAPI.GetSpecializationInfo and TalentAPI.GetSpecializationInfo(specIndex)
            or GetSpecializationInfo and GetSpecializationInfo(specIndex)
        if specID then
            return BuildSpecKey(classToken, specID)
        end
        return BuildSpecKey(classToken, specIndex)
    end
    return BuildSpecKey(classToken, 0)
end

local function GetWorldLatency()
    if not GetNetStats then return 0 end
    local _, _, _, latencyWorld = GetNetStats()
    return ClampValue(latencyWorld) or 0
end

local function ResolveConfiguredValue(db)
    local mode = db and db.mode or MODE_FIXED_ALL
    local defaultValue = MODE_DEFAULTS[mode] or FIXED_DEFAULT

    if mode == MODE_FIXED_ALL then
        return db.fixedAll or defaultValue
    elseif mode == MODE_AUTO_ALL then
        return db.autoAll or defaultValue
    elseif mode == MODE_FIXED_CLASS then
        return NormalizeSavedValue(db.classFixed[GetPlayerClassToken()]) or defaultValue
    elseif mode == MODE_AUTO_CLASS then
        return NormalizeSavedValue(db.classAuto[GetPlayerClassToken()]) or defaultValue
    elseif mode == MODE_FIXED_SPEC then
        return NormalizeSavedValue(db.specFixed[GetActiveSpecKey()]) or defaultValue
    elseif mode == MODE_AUTO_SPEC then
        return NormalizeSavedValue(db.specAuto[GetActiveSpecKey()]) or defaultValue
    end

    return defaultValue
end

local function ResolveTooltipConfiguredValue(db)
    local mode = db and db.mode or MODE_FIXED_ALL
    local defaultValue = MODE_DEFAULTS[mode] or FIXED_DEFAULT

    if mode == MODE_FIXED_ALL then
        return NormalizeSavedValue(db.fixedAll) or defaultValue
    elseif mode == MODE_AUTO_ALL then
        return NormalizeSavedValue(db.autoAll) or defaultValue
    elseif mode == MODE_FIXED_CLASS then
        local values = type(db.classFixed) == "table" and db.classFixed or nil
        return values and NormalizeSavedValue(values[GetPlayerClassToken()]) or defaultValue
    elseif mode == MODE_AUTO_CLASS then
        local values = type(db.classAuto) == "table" and db.classAuto or nil
        return values and NormalizeSavedValue(values[GetPlayerClassToken()]) or defaultValue
    elseif mode == MODE_FIXED_SPEC then
        local values = type(db.specFixed) == "table" and db.specFixed or nil
        return values and NormalizeSavedValue(values[GetActiveSpecKey()]) or defaultValue
    elseif mode == MODE_AUTO_SPEC then
        local values = type(db.specAuto) == "table" and db.specAuto or nil
        return values and NormalizeSavedValue(values[GetActiveSpecKey()]) or defaultValue
    end

    return defaultValue
end

local function ComputeTargetValue()
    local db = GetDB()
    if not db then return FIXED_DEFAULT end

    local value = ResolveConfiguredValue(db)
    if IsAutoMode(db.mode) then
        value = value + GetWorldLatency()
    end

    return ClampValue(value) or (IsAutoMode(db.mode) and AUTO_DEFAULT or FIXED_DEFAULT)
end

local function GetCurrentCVarValue()
    if YUI.IsForever then
        local getter = C_CVar and C_CVar.GetCVar or GetCVar
        if not getter then return nil end
        local ok, value = pcall(getter, CVAR_NAME)
        return ok and tonumber(value) or nil
    end
    if not GetCVar then return nil end
    return ClampValue(GetCVar(CVAR_NAME))
end

local function PrintMessage(message)
    if YUI.Print then
        YUI:Print(message)
    else
        print("|cff00ccffYUI|r " .. tostring(message))
    end
end

local function IsRuntimeEnabled()
    if isFeatureEnabled then return true end

    local store = GetStore()
    if store and store[FEATURE_KEY] == true then
        isFeatureEnabled = true
        return true
    end

    return false
end

local function ApplyNow()
    if not IsRuntimeEnabled() then return false end

    local target = ComputeTargetValue()
    local current = GetCurrentCVarValue()
    if YUI.IsForever and current == nil then
        local now = GetTime and GetTime() or 0
        if lastApplyErrorAt == 0 or now - lastApplyErrorAt > 30 then
            lastApplyErrorAt = now
            PrintMessage(T("message.apply_failed", "Failed to apply Spell Queue Window: %s", "SpellQueueWindow unavailable"))
        end
        return false
    end
    if current == target then
        lastAppliedValue = target
        return true
    end
    if current == nil and lastAppliedValue == target then
        return true
    end

    local ok, result
    if SetCVar then
        ok, result = pcall(SetCVar, CVAR_NAME, tostring(target))
    elseif C_CVar and C_CVar.SetCVar then
        ok, result = pcall(C_CVar.SetCVar, CVAR_NAME, tostring(target))
    else
        ok, result = false, "SetCVar unavailable"
    end

    if ok and result ~= false then
        local applied = GetCurrentCVarValue()
        if (not YUI.IsForever and applied == nil) or applied == target then
            lastAppliedValue = target
            return true
        end
        result = "expected " .. tostring(target) .. ", got " .. tostring(applied)
    end

    local now = GetTime and GetTime() or 0
    if now - lastApplyErrorAt > 30 then
        lastApplyErrorAt = now
        PrintMessage(T("message.apply_failed", "Failed to apply Spell Queue Window: %s", tostring(result)))
    end
    return false
end

local function StopAutoTicker()
    if autoTicker then
        if autoTicker.Cancel then autoTicker:Cancel() end
        autoTicker = nil
    end
end

local function UpdateAutoTicker()
    local db = GetDB()
    if IsRuntimeEnabled() and db and IsAutoMode(db.mode) then
        if not autoTicker and C_Timer and C_Timer.NewTicker then
            autoTicker = C_Timer.NewTicker(AUTO_REFRESH_INTERVAL, ApplyNow)
        end
    else
        StopAutoTicker()
    end
end

local function ApplyAndRefreshTicker()
    UpdateAutoTicker()
    ApplyNow()
end

local function GetClassIconTexCoord(classToken)
    return CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken] or nil
end

local function InsetClassIconTexCoord(texCoord)
    if type(texCoord) ~= "table" then return nil end

    local left = texCoord[1] or 0
    local right = texCoord[2] or 1
    local top = texCoord[3] or 0
    local bottom = texCoord[4] or 1
    local width = right - left
    local height = bottom - top
    local insetX = width * CLASS_ICON_TEXCOORD_INSET
    local insetY = height * CLASS_ICON_TEXCOORD_INSET

    return {
        left + insetX,
        right - insetX,
        top + insetY,
        bottom - insetY,
    }
end

local function GetClassIcon(classToken)
    local texCoord = GetClassIconTexCoord(classToken)
    if texCoord then
        return CLASS_ICON_TEXTURE, InsetClassIconTexCoord(texCoord), true
    end
    return DEFAULT_ICON, nil, false
end

local function GetClassInfoMap()
    local map = {}
    local classInfos

    if UnitAPI.GetClassInfos then
        classInfos = UnitAPI.GetClassInfos()
    else
        classInfos = {}
        local count = UnitAPI.GetNumClasses and UnitAPI.GetNumClasses() or GetNumClasses and GetNumClasses() or 0
        for index = 1, count do
            local info
            if UnitAPI.GetClassInfo then
                info = UnitAPI.GetClassInfo(index)
            elseif GetClassInfo then
                local className, classFile, classID = GetClassInfo(index)
                info = { className = className, classFile = classFile, classID = classID }
            end
            classInfos[#classInfos + 1] = info
        end
    end

    for index, info in ipairs(classInfos) do
        if type(info) == "table" and info.classFile then
            local icon, iconTexCoord, isClassIcon = GetClassIcon(info.classFile)
            map[info.classFile] = {
                token = info.classFile,
                name = GetClassDisplayName(info.classFile, info.className),
                classID = info.classID or info.id or index,
                icon = icon,
                iconTexCoord = iconTexCoord,
                isClassIcon = isClassIcon,
            }
        end
    end

    if not next(map) then
        for _, token in ipairs(CLASS_TOKENS) do
            local icon, iconTexCoord, isClassIcon = GetClassIcon(token)
            map[token] = {
                token = token,
                name = GetClassDisplayName(token, token),
                icon = icon,
                iconTexCoord = iconTexCoord,
                isClassIcon = isClassIcon,
            }
        end
    end

    return map
end

local function GetOrderedClassGroups()
    local map = GetClassInfoMap()
    local groups = {}

    for _, group in ipairs(ARMOR_GROUPS) do
        local result = { label = T(group.labelKey, group.fallback), classes = {} }
        for _, token in ipairs(group.classes) do
            if map[token] then
                result.classes[#result.classes + 1] = map[token]
            end
        end
        if #result.classes > 0 then
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
        local fallback = RAID_CLASS_COLORS[classInfo.token]
        return fallback.r or 1, fallback.g or 1, fallback.b or 1, 1
    end
    return 1, 1, 1, 1
end

local function ColorComponent(value)
    value = tonumber(value) or 1
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    return math.floor(value * 255 + 0.5)
end

local function RGBToColorCode(r, g, b)
    return string.format("|cff%02x%02x%02x", ColorComponent(r), ColorComponent(g), ColorComponent(b))
end

local function WrapColor(text, color)
    return (color or COLOR_WHITE) .. tostring(text or "") .. COLOR_RESET
end

local function GetClassColorCode(classInfo)
    local r, g, b = GetClassColor(classInfo)
    return RGBToColorCode(r, g, b)
end

local function SetClassTextColor(text, classInfo)
    if not text then return end
    text:SetTextColor(GetClassColor(classInfo))
end

local function GetPlayerClassInfo()
    local classToken = GetPlayerClassToken()
    local map = GetClassInfoMap()
    return map[classToken] or {
        token = classToken,
        name = GetClassDisplayName(classToken, classToken),
        icon = select(1, GetClassIcon(classToken)),
        iconTexCoord = select(2, GetClassIcon(classToken)),
        isClassIcon = select(3, GetClassIcon(classToken)),
    }
end

local function GetActiveSpecDisplayName()
    if (TalentAPI.GetCurrentConfigurationSpecializationInfo or TalentAPI.GetCurrentSpecializationInfo) then
        local specInfo = (TalentAPI.GetCurrentConfigurationSpecializationInfo or TalentAPI.GetCurrentSpecializationInfo)()
        if specInfo and specInfo.name then
            return GetSpecDisplayName(specInfo.specID or specInfo.id, specInfo.name)
        end
    end

    local specIndex = TalentAPI.GetSpecialization and TalentAPI.GetSpecialization() or GetSpecialization and GetSpecialization()
    if not specIndex then return nil end

    local specID, specName
    if TalentAPI.GetSpecializationInfo then
        specID, specName = TalentAPI.GetSpecializationInfo(specIndex)
    elseif GetSpecializationInfo then
        specID, specName = GetSpecializationInfo(specIndex)
    end

    return GetSpecDisplayName(specID, specName)
end

local function GetAutoContext()
    local db = GetDB()
    local classInfo = GetPlayerClassInfo()
    if db and db.mode == MODE_AUTO_SPEC then
        return GetActiveSpecDisplayName() or classInfo.name or classInfo.token, classInfo, T("context.current_spec", "Current Spec")
    end
    return classInfo.name or classInfo.token, classInfo, T("context.current_class", "Current Class")
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

    if classInfo and (TalentAPI.GetClassConfigurationSpecializations or TalentAPI.GetClassSpecializations) then
        for _, specInfo in ipairs((TalentAPI.GetClassConfigurationSpecializations or TalentAPI.GetClassSpecializations)(classInfo)) do
            if specInfo.specID then
                local specName = specInfo.name or tostring(specInfo.specID)
                specs[#specs + 1] = {
                    key = BuildSpecKey(specInfo.classFile or classInfo.token, specInfo.specID),
                    specID = specInfo.specID,
                    name = specName,
                    displayName = GetSpecDisplayName(specInfo.specID, specName),
                    icon = specInfo.icon or DEFAULT_ICON,
                    nativeIcon = specInfo.icon,
                    classInfo = classInfo,
                }
            end
        end
    end

    if #specs == 0 and classInfo and classInfo.classID and GetSpecializationInfoForClassID then
        local sex = UnitSex and UnitSex("player") or nil
        local count = GetNumSpecsForClass(classInfo.classID)
        for index = 1, count do
            local specID, specName, _, specIcon = GetSpecializationInfoForClassID(classInfo.classID, index, sex)
            if specID then
                specName = specName or tostring(specID)
                specs[#specs + 1] = {
                    key = BuildSpecKey(classInfo.token, specID),
                    specID = specID,
                    name = specName,
                    displayName = GetSpecDisplayName(specID, specName),
                    icon = specIcon or DEFAULT_ICON,
                    nativeIcon = specIcon,
                    classInfo = classInfo,
                }
            end
        end
    end

    if #specs == 0 and classInfo and classInfo.token == GetPlayerClassToken() then
        local count = TalentAPI.GetNumSpecializations and TalentAPI.GetNumSpecializations() or 0
        for index = 1, count do
            local specID, specName, specIcon
            if TalentAPI.GetSpecializationInfo then
                specID, specName, _, specIcon = TalentAPI.GetSpecializationInfo(index)
            end
            specID = specID or index
            specName = specName or T("context.spec_fallback", "Spec %d", index)
            specs[#specs + 1] = {
                key = BuildSpecKey(classInfo.token, specID),
                specID = specID,
                name = specName,
                displayName = GetSpecDisplayName(specID, specName),
                icon = specIcon or DEFAULT_ICON,
                nativeIcon = specIcon,
                classInfo = classInfo,
            }
        end
    end

    return specs
end

local function SetEditTextColor(edit, key, fallback)
    if not edit then return end
    local r, g, b, a
    if key and GUI2 and GUI2.GetColor then
        r, g, b, a = GUI2:GetColor(key, fallback)
    elseif fallback then
        r, g, b, a = fallback[1], fallback[2], fallback[3], fallback[4] or 1
    else
        r, g, b, a = 1, 1, 1, 1
    end
    edit:SetTextColor(r or 1, g or 1, b or 1, a or 1)
end

local function ConfigureValueEdit(edit, defaultValue, getValue, setValue, refresh)
    if edit.SetNumeric then edit:SetNumeric(true) end
    if edit.SetMaxLetters then edit:SetMaxLetters(VALUE_MAX_LETTERS) end
    if edit.SetTextInsets then edit:SetTextInsets(8, 8, 0, 0) end
    edit:SetJustifyH("CENTER")

    local isSettingText = false
    local showingPlaceholder = false
    local suppressCommit = false

    local function Display()
        local saved = NormalizeSavedValue(getValue and getValue())
        isSettingText = true
        if saved == nil then
            showingPlaceholder = true
            edit:SetText(tostring(defaultValue))
            SetEditTextColor(edit, "color.text.disabled", { 0.45, 0.45, 0.45, 1 })
        else
            showingPlaceholder = false
            edit:SetText(tostring(saved))
            edit:SetTextColor(1, 1, 1, 1)
        end
        if edit.HighlightText then edit:HighlightText(0, 0) end
        if edit.SetCursorPosition then edit:SetCursorPosition(0) end
        isSettingText = false
    end

    local function Commit()
        local text = edit:GetText()
        if showingPlaceholder then text = "" end
        local value = NormalizeSavedValue(text)
        if setValue then setValue(value) end
        ApplyAndRefreshTicker()
        if refresh then refresh() else Display() end
    end

    edit:SetScript("OnEditFocusGained", function(self)
        if self.gui2Bg then GUI2:SetBorderColor(self.gui2Bg, "color.border.focus") end
        if showingPlaceholder then
            isSettingText = true
            self:SetText("")
            isSettingText = false
            showingPlaceholder = false
        elseif self.HighlightText then
            self:HighlightText()
        end
        self:SetTextColor(1, 1, 1, 1)
    end)

    edit:SetScript("OnEditFocusLost", function(self)
        if self.gui2Bg then GUI2:SetBorderColor(self.gui2Bg, "color.border.default") end
        if suppressCommit then
            suppressCommit = false
            return
        end
        Commit()
    end)

    edit:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    edit:SetScript("OnEscapePressed", function(self)
        suppressCommit = true
        Display()
        self:ClearFocus()
    end)

    edit:SetScript("OnTextChanged", function(self)
        if isSettingText then return end
        if self:HasFocus() then
            showingPlaceholder = false
            self:SetTextColor(1, 1, 1, 1)
        end
    end)

    Display()
end

local function RenderValueInput(parent, x, y, width, label, defaultValue, getValue, setValue, refresh)
    local frame = GUI2:CreateFrame(parent, { width = width or 620, height = 32 })
    frame:SetPoint("TOPLEFT", x, y)
    local labelWidth = GUI2.GetMetric and GUI2:GetMetric("layout.form.labelWidth", 120) or 120
    local gap = GUI2.GetMetric and GUI2:GetMetric("layout.form.gap", 10) or 10

    local labelText = GUI2:CreateText(frame, label, "font.size.md", "color.text.primary")
    labelText:SetPoint("LEFT", frame, "LEFT", 0, 0)
    labelText:SetWidth(labelWidth)
    labelText:SetJustifyH("LEFT")
    labelText:SetWordWrap(false)

    local edit = GUI2.Form:CreateEditBox(frame, { width = VALUE_EDIT_WIDTH, height = VALUE_EDIT_HEIGHT, autoFocus = false })
    edit:SetPoint("LEFT", frame, "LEFT", labelWidth + gap, 0)

    local hint = GUI2:CreateText(frame, "ms", "font.size.sm", "color.text.secondary")
    hint:SetPoint("LEFT", edit, "RIGHT", 6, 0)

    ConfigureValueEdit(edit, defaultValue, getValue, setValue, refresh)
    return width or 620, 32
end

local function AddValueInput(options, label, defaultValue, getValue, setValue, refresh)
    options[#options + 1] = {
        type = "custom",
        render = function(parent, x, y, width)
            return RenderValueInput(parent, x, y, width, label, defaultValue, getValue, setValue, refresh)
        end,
    }
end

local function RenderValueCell(parent, x, y, width, entry, defaultValue, refresh)
    local frame = GUI2:CreatePanel(parent, {
        width = width,
        height = VALUE_CELL_HEIGHT,
        surface = "color.surface.panel",
        border = "color.border.subtle",
    })
    frame:SetPoint("TOPLEFT", x, y)

    local hint = GUI2:CreateText(frame, "ms", "font.size.sm", "color.text.secondary")
    hint:SetPoint("RIGHT", frame, "RIGHT", -10, 0)

    local edit = GUI2.Form:CreateEditBox(frame, { width = GetValueCellEditWidth(entry), height = VALUE_EDIT_HEIGHT, autoFocus = false })
    edit:SetPoint("RIGHT", hint, "LEFT", -6, 0)
    ConfigureValueEdit(edit, defaultValue, entry.get, entry.set, refresh)

    local icon = GUI2:CreateIconSlot(frame, {
        size = VALUE_ICON_SIZE,
        icon = entry.icon or DEFAULT_ICON,
        texCoords = entry.iconTexCoord,
        shape = "square",
        variant = "surface",
        padding = entry.specID and 2 or 0,
    })
    icon:SetPoint("LEFT", frame, "LEFT", 10, 0)
    if icon.EnableMouse then icon:EnableMouse(false) end

    if entry.specID and Icons and Icons.GetScopedSpecIcon and Icons.ApplyIcon then
        local iconData = Icons.GetScopedSpecIcon(entry.specID, entry.nativeIcon or entry.icon, ICON_SCOPE_ID)
        if iconData then
            local texture = icon.icon or icon
            Icons.ApplyIcon(texture, iconData)
            if iconData.kind == "spec" and iconData.custom ~= true and not iconData.atlas and Icons.GetNativeSpecTexCoord then
                texture:SetTexCoord(unpack(Icons.GetNativeSpecTexCoord()))
            end
        end
    end

    local label = GUI2:CreateText(frame, entry.label or "", "font.size.md", "color.text.primary")
    label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", edit, "LEFT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    SetClassTextColor(label, entry.classInfo)

    return frame
end

local function RenderValueGrid(parent, x, y, width, entries, defaultValue, refresh)
    local gridWidth = width or 620
    local columns = VALUE_GRID_COLUMNS
    local cellWidth = math.floor((gridWidth - ((columns - 1) * VALUE_GRID_GAP)) / columns)
    local rows = math.ceil(#entries / columns)
    if rows < 1 then rows = 1 end

    local height = (rows * VALUE_CELL_HEIGHT) + ((rows - 1) * VALUE_GRID_GAP)
    local frame = GUI2:CreateFrame(parent, { width = gridWidth, height = height })
    frame:SetPoint("TOPLEFT", x, y)

    for index, entry in ipairs(entries) do
        local row = math.floor((index - 1) / columns)
        local col = (index - 1) % columns
        RenderValueCell(
            frame,
            col * (cellWidth + VALUE_GRID_GAP),
            -(row * (VALUE_CELL_HEIGHT + VALUE_GRID_GAP)),
            cellWidth,
            entry,
            defaultValue,
            refresh
        )
    end

    return gridWidth, height
end

local function AddValueGrid(options, entries, defaultValue, refresh)
    if not entries or #entries == 0 then return end
    options[#options + 1] = {
        type = "custom",
        render = function(parent, x, y, width)
            return RenderValueGrid(parent, x, y, width, entries, defaultValue, refresh)
        end,
    }
end

local function RenderBatchSetRow(parent, x, y, width, valueTable, entries, includeRangeButtons, refresh)
    local frame = GUI2:CreateFrame(parent, { width = width or 620, height = 32 })
    frame:SetPoint("TOPLEFT", x, y)

    local labelWidth = GUI2.GetMetric and GUI2:GetMetric("layout.form.labelWidth", 120) or 120
    local gap = GUI2.GetMetric and GUI2:GetMetric("layout.form.gap", 10) or 10
    local controlX = labelWidth + gap

    local labelText = GUI2:CreateText(frame, T("settings.batch", "Batch"), "font.size.md", "color.text.primary")
    labelText:SetPoint("LEFT", frame, "LEFT", 0, 0)
    labelText:SetWidth(labelWidth)
    labelText:SetJustifyH("LEFT")
    labelText:SetWordWrap(false)

    local edit = GUI2.Form:CreateEditBox(frame, { width = VALUE_EDIT_WIDTH, height = VALUE_EDIT_HEIGHT, autoFocus = false })
    edit:SetPoint("LEFT", frame, "LEFT", controlX, 0)
    if edit.SetNumeric then edit:SetNumeric(true) end
    if edit.SetMaxLetters then edit:SetMaxLetters(VALUE_MAX_LETTERS) end
    if edit.SetTextInsets then edit:SetTextInsets(8, 8, 0, 0) end
    edit:SetJustifyH("CENTER")

    local function GetBatchValue()
        local value = NormalizeSavedValue(edit:GetText())
        if value == nil then
            if edit.SetFocus then edit:SetFocus() end
            if edit.HighlightText then edit:HighlightText() end
        end
        return value
    end

    local function FinishBatch()
        ApplyAndRefreshTicker()
        if refresh then refresh() end
    end

    local function ApplyBatch(range)
        local value = GetBatchValue()
        if value == nil then return end

        local changed = false
        for _, entry in ipairs(entries or {}) do
            if not range or entry.range == range then
                valueTable[entry.key] = value
                changed = true
            end
        end

        if changed then FinishBatch() end
    end

    local function ClearBatch()
        for key in pairs(valueTable) do
            valueTable[key] = nil
        end
        FinishBatch()
    end

    local cursor = edit
    local function AddButton(text, onClick)
        local button = GUI2.Form:CreateButton(frame, {
            text = text,
            width = BATCH_BUTTON_WIDTH,
            height = VALUE_EDIT_HEIGHT,
            onClick = onClick,
        })
        button:SetPoint("LEFT", cursor, "RIGHT", 6, 0)
        cursor = button
        return button
    end

    AddButton(T("settings.apply_all", "Apply All"), function() ApplyBatch(nil) end)
    if includeRangeButtons then
        AddButton(T("settings.apply_melee", "Apply Melee"), function() ApplyBatch("melee") end)
        AddButton(T("settings.apply_ranged", "Apply Ranged"), function() ApplyBatch("ranged") end)
    end
    AddButton(T("settings.clear_all", "Clear All"), ClearBatch)

    return width or 620, 32
end

local function AddBatchSetRow(options, valueTable, entries, includeRangeButtons, refresh)
    if type(valueTable) ~= "table" or not entries or #entries == 0 then return end
    options[#options + 1] = {
        type = "custom",
        render = function(parent, x, y, width)
            return RenderBatchSetRow(parent, x, y, width, valueTable, entries, includeRangeButtons, refresh)
        end,
    }
end

local function BuildAutoInfoLine()
    local db = GetDB()
    local worldLatency = GetWorldLatency()
    local configuredValue = ResolveConfiguredValue(db)
    local target = ClampValue(configuredValue + worldLatency) or MAX_VALUE
    local contextName, classInfo, contextLabel = GetAutoContext()

    return T(
        "settings.auto_info",
        "%s: %s | SQW: %s + %s = %s",
        contextLabel,
        WrapColor(contextName, GetClassColorCode(classInfo)),
        WrapColor(configuredValue, COLOR_WHITE),
        WrapColor(worldLatency, COLOR_FIXED),
        WrapColor(tostring(target) .. " ms", COLOR_AUTO)
    )
end

local function RenderAutoInfo(parent, x, y, width)
    local frame = GUI2:CreateFrame(parent, { width = width or 620, height = 44 })
    frame:SetPoint("TOPLEFT", x, y)
    local labelWidth = GUI2.GetMetric and GUI2:GetMetric("layout.form.labelWidth", 120) or 120
    local gap = GUI2.GetMetric and GUI2:GetMetric("layout.form.gap", 10) or 10
    local controlX = labelWidth + gap

    local line1 = GUI2:CreateText(frame, T("settings.auto_formula", "Auto mode: SQW = base value + world latency (max 400)"), "font.size.md", "color.text.secondary")
    line1:SetPoint("TOPLEFT", frame, "TOPLEFT", controlX, 0)
    line1:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    line1:SetJustifyH("LEFT")
    line1:SetWordWrap(false)

    local line2 = GUI2:CreateText(frame, "", "font.size.md", "color.text.primary")
    line2:SetPoint("TOPLEFT", line1, "BOTTOMLEFT", 0, -6)
    line2:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    line2:SetJustifyH("LEFT")
    line2:SetWordWrap(false)

    local ticker

    local function StopTicker()
        if ticker then
            if ticker.Cancel then ticker:Cancel() end
            ticker = nil
        end
    end

    local function RefreshInfo()
        if not frame:IsShown() then
            StopTicker()
            return
        end

        line2:SetText(BuildAutoInfoLine())
    end

    frame:SetScript("OnHide", StopTicker)
    frame:SetScript("OnShow", function()
        RefreshInfo()
        if not ticker and C_Timer and C_Timer.NewTicker then
            ticker = C_Timer.NewTicker(AUTO_REFRESH_INTERVAL, RefreshInfo)
        end
    end)

    RefreshInfo()
    if C_Timer and C_Timer.NewTicker then
        ticker = C_Timer.NewTicker(AUTO_REFRESH_INTERVAL, RefreshInfo)
    end

    return width or 620, 44
end

local function AddAutoInfo(options)
    options[#options + 1] = {
        type = "custom",
        render = function(parent, x, y, width)
            return RenderAutoInfo(parent, x, y, width)
        end,
    }
end

local function CopyValueTable(source)
    local result = {}
    if type(source) == "table" then
        for key, value in pairs(source) do
            local normalized = NormalizeSavedValue(value)
            if normalized ~= nil then
                result[tostring(key)] = normalized
            end
        end
    end
    return result
end

local function BuildExportData(db)
    return {
        mode = IsValidMode(db.mode) and db.mode or MODE_FIXED_ALL,
        fixedAll = NormalizeSavedValue(db.fixedAll),
        autoAll = NormalizeSavedValue(db.autoAll),
        classFixed = CopyValueTable(db.classFixed),
        classAuto = CopyValueTable(db.classAuto),
        specFixed = CopyValueTable(db.specFixed),
        specAuto = CopyValueTable(db.specAuto),
    }
end

local function ReplaceConfig(data)
    if type(data) ~= "table" then return false end
    local db = GetDB()
    if not db then return false end

    db.mode = IsValidMode(data.mode) and data.mode or MODE_FIXED_ALL
    db.fixedAll = NormalizeSavedValue(data.fixedAll)
    db.autoAll = NormalizeSavedValue(data.autoAll)
    db.classFixed = CopyValueTable(data.classFixed)
    db.classAuto = CopyValueTable(data.classAuto)
    db.specFixed = CopyValueTable(data.specFixed)
    db.specAuto = CopyValueTable(data.specAuto)
    return true
end

local function GetSerializerLibraries()
    if not LibStub then return nil, nil end
    local serializer = LibStub:GetLibrary("AceSerializer-3.0")
    local deflate = LibStub:GetLibrary("LibDeflate")
    return serializer, deflate
end

local function ExportConfig()
    local serializer, deflate = GetSerializerLibraries()
    if not serializer or not deflate or not S or not S.ShowCopyPopup then
        PrintMessage(T("message.export_unavailable", "Export failed: serialization library unavailable."))
        return
    end

    local serialized = serializer:Serialize(BuildExportData(GetDB()))
    local compressed = deflate:CompressDeflate(serialized)
    local encoded = deflate:EncodeForPrint(compressed)
    S:ShowCopyPopup(T("popup.export_title", "Export Spell Queue Settings"), EXPORT_PREFIX .. encoded)
end

local function ImportConfig(text, refresh)
    local serializer, deflate = GetSerializerLibraries()
    if not serializer or not deflate then
        PrintMessage(T("message.import_unavailable", "Import failed: serialization library unavailable."))
        return
    end

    text = tostring(text or "")
    local encoded
    if text:sub(1, #EXPORT_PREFIX) == EXPORT_PREFIX then
        encoded = text:sub(#EXPORT_PREFIX + 1)
    elseif text:sub(1, #LEGACY_EXPORT_PREFIX) == LEGACY_EXPORT_PREFIX then
        encoded = text:sub(#LEGACY_EXPORT_PREFIX + 1)
    else
        PrintMessage(T("message.import_wrong_type", "Import failed: not a Spell Queue settings payload."))
        return
    end

    local compressed = deflate:DecodeForPrint(encoded)
    local serialized = compressed and deflate:DecompressDeflate(compressed)
    if not serialized then
        PrintMessage(T("message.import_decode_failed", "Import failed: payload could not be decoded."))
        return
    end

    local ok, data = serializer:Deserialize(serialized)
    if not ok or type(data) ~= "table" then
        PrintMessage(T("message.import_invalid", "Import failed: invalid payload."))
        return
    end

    if ReplaceConfig(data) then
        ApplyAndRefreshTicker()
        PrintMessage(T("message.import_success", "Spell Queue settings imported."))
        if refresh then refresh() end
    end
end

local Feature = {
    product = PRODUCT_ID,
    name = T("feature.name", "Spell Queue Window"),
    default = false,
    description = YUI.IsForever and (T("mode.fixed_all", "All Classes Fixed") .. " / " .. T("mode.auto_all", "All Classes Auto"))
        or T("feature.description", "Set Spell Queue Window globally, by class, or by spec, with import/export support."),
    tags = { T("feature.tag.combat", "Combat") },
    settingsMode = "inline",
    sourceRoot = "Components\\LagTolerance",
}

function Feature:GetTooltipSummary()
    local store = GetTooltipStore()
    if type(store) ~= "table" or store[FEATURE_KEY] ~= true then return nil end

    local db = store[CONFIG_KEY]
    if type(db) ~= "table" or not IsValidMode(db.mode) then return nil end

    local mode = db.mode
    local modeText = GetModeLabel(mode)
    if not modeText then return nil end

    local configuredValue = ResolveTooltipConfiguredValue(db)
    if IsAutoMode(mode) then
        local worldLatency = GetWorldLatency()
        local target = ClampValue(configuredValue + worldLatency) or MAX_VALUE
        return string.format(
            "%s %s + %s = %s",
            modeText,
            WrapColor(configuredValue, COLOR_WHITE),
            WrapColor(worldLatency, COLOR_FIXED),
            WrapColor(target, COLOR_AUTO)
        )
    end

    return string.format("%s %s", modeText, WrapColor(configuredValue, COLOR_WHITE))
end

function Feature:GetOptions()
    local db = GetDB()
    local importText = ""

    local function Refresh()
        if self.RefreshCurrentModule then
            self:RefreshCurrentModule()
        end
    end

    local options = {
        {
            type = "dropdown",
            label = T("settings.type", "Type"),
            inlineLabel = true,
            controlWidth = TYPE_DROPDOWN_WIDTH,
            options = GetModeOptions(),
            get = function() return db.mode end,
            set = function(value)
                if IsValidMode(value) then
                    db.mode = value
                    ApplyAndRefreshTicker()
                    Refresh()
                end
            end,
        },
    }

    local mode = db.mode
    local defaultValue = MODE_DEFAULTS[mode] or FIXED_DEFAULT
    local needsRefresh = IsAutoMode(mode) and Refresh or nil
    local batchValueTable
    local batchEntries
    local batchIncludesRangeButtons = false

    if mode == MODE_FIXED_CLASS or mode == MODE_AUTO_CLASS then
        batchValueTable = mode == MODE_FIXED_CLASS and db.classFixed or db.classAuto
        batchEntries = {}
        for _, group in ipairs(GetOrderedClassGroups()) do
            for _, classInfo in ipairs(group.classes) do
                batchEntries[#batchEntries + 1] = { key = classInfo.token }
            end
        end
    elseif mode == MODE_FIXED_SPEC or mode == MODE_AUTO_SPEC then
        batchValueTable = mode == MODE_FIXED_SPEC and db.specFixed or db.specAuto
        batchEntries = {}
        batchIncludesRangeButtons = true
        for _, group in ipairs(GetOrderedClassGroups()) do
            for _, classInfo in ipairs(group.classes) do
                local specs = GetSpecsForClass(classInfo)
                for _, spec in ipairs(specs) do
                    batchEntries[#batchEntries + 1] = {
                        key = spec.key,
                        range = GetSpecRange(spec.specID),
                    }
                end
            end
        end
    end

    if IsAutoMode(mode) then
        AddAutoInfo(options)
    end

    AddBatchSetRow(options, batchValueTable, batchEntries, batchIncludesRangeButtons, Refresh)

    if mode == MODE_FIXED_ALL then
        AddValueInput(options, T("settings.base_value", "Base Value"), defaultValue, function() return db.fixedAll end, function(value) db.fixedAll = value end, needsRefresh)
    elseif mode == MODE_AUTO_ALL then
        AddValueInput(options, T("settings.base_value", "Base Value"), defaultValue, function() return db.autoAll end, function(value) db.autoAll = value end, needsRefresh)
    elseif mode == MODE_FIXED_CLASS or mode == MODE_AUTO_CLASS then
        local valueTable = mode == MODE_FIXED_CLASS and db.classFixed or db.classAuto
        for _, group in ipairs(GetOrderedClassGroups()) do
            options[#options + 1] = { type = "divider", label = group.label, alignLeft = true, width = 620 }
            local entries = {}
            for _, classInfo in ipairs(group.classes) do
                local entryClass = classInfo
                entries[#entries + 1] = {
                    label = entryClass.name or entryClass.token,
                    icon = entryClass.icon,
                    iconTexCoord = entryClass.iconTexCoord,
                    classInfo = entryClass,
                    get = function()
                        return valueTable[entryClass.token]
                    end,
                    set = function(value)
                        valueTable[entryClass.token] = value
                    end,
                }
            end
            AddValueGrid(options, entries, defaultValue, needsRefresh)
        end
    elseif mode == MODE_FIXED_SPEC or mode == MODE_AUTO_SPEC then
        local valueTable = mode == MODE_FIXED_SPEC and db.specFixed or db.specAuto
        for _, group in ipairs(GetOrderedClassGroups()) do
            local insertedGroup = false
            for _, classInfo in ipairs(group.classes) do
                local specs = GetSpecsForClass(classInfo)
                if #specs > 0 then
                    if not insertedGroup then
                        options[#options + 1] = { type = "divider", label = group.label, alignLeft = true, width = 620 }
                        insertedGroup = true
                    end
                    local entries = {}
                    for _, spec in ipairs(specs) do
                        local entrySpec = spec
                        entries[#entries + 1] = {
                            label = entrySpec.displayName or entrySpec.name,
                            icon = entrySpec.icon,
                            iconTexCoord = entrySpec.iconTexCoord,
                            specID = entrySpec.specID,
                            nativeIcon = entrySpec.nativeIcon,
                            classInfo = entrySpec.classInfo,
                            get = function()
                                return valueTable[entrySpec.key]
                            end,
                            set = function(value)
                                valueTable[entrySpec.key] = value
                            end,
                        }
                    end
                    AddValueGrid(options, entries, defaultValue, needsRefresh)
                end
            end
        end
    end

    options[#options + 1] = { type = "divider", label = T("settings.import_export", "Import / Export"), alignLeft = true, width = 620 }
    options[#options + 1] = {
        type = "row",
        children = {
            {
                type = "button",
                label = T("settings.export_config", "Export Config"),
                width = 110,
                onClick = ExportConfig,
            },
            {
                type = "editbox",
                width = 390,
                get = function() return importText end,
                set = function(value) importText = value or "" end,
            },
            {
                type = "button",
                label = T("settings.import_config", "Import Config"),
                width = 110,
                onClick = function()
                    ImportConfig(importText, Refresh)
                end,
            },
        },
    }

    return options
end

Feature.callback = function(enable)
    isFeatureEnabled = enable == true
    if isFeatureEnabled then
        ApplyAndRefreshTicker()
    else
        StopAutoTicker()
        lastAppliedValue = nil
    end
end

if YUI.Event then
    local function OnRuntimeEvent()
        if IsRuntimeEnabled() then
            ApplyAndRefreshTicker()
        end
    end

    YUI.Event:On("YUI_WORLD_READY", OnRuntimeEvent, Feature)
    if not YUI.IsForever then
        YUI.Event:On("PLAYER_SPECIALIZATION_CHANGED", OnRuntimeEvent, Feature)
        YUI.Event:On("PLAYER_TALENT_UPDATE", OnRuntimeEvent, Feature)
        YUI.Event:On("CHARACTER_POINTS_CHANGED", OnRuntimeEvent, Feature)
        YUI.Event:On("ACTIVE_TALENT_GROUP_CHANGED", OnRuntimeEvent, Feature)
        YUI.Event:On("ACTIVE_COMBAT_CONFIG_CHANGED", OnRuntimeEvent, Feature)
    end
end

Components:RegisterFeature(FEATURE_KEY, Feature)

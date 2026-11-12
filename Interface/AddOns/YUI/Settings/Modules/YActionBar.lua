local YUI = _G.YUI

local function HasClientCapability(name)
    local product = YUI and YUI.YActionBar
    local client = product and product.Client
    return client and client[name] == true or false
end
if not YUI then return end

local S = YUI.Settings
local GUI2 = YUI.GUI2
if not S or not GUI2 then return end

local Locale = YUI.Locale
local L = Locale and Locale:Get("YActionBar") or {}
local LC = Locale and Locale:Get("Core") or {}
local CelestialSeries = S.CelestialSeries
local ACTION_BAR_NAV_ICON = CelestialSeries
    and CelestialSeries:GetIcon("yactionbar", 128)
    or 237290

local selectedBarId = "main"
local selectedGroup = "layout"
local DEFAULT_BORDER_COLOR = { 0, 0, 0, 1 }
local DEFAULT_BACKGROUND_COLOR = { 34 / 255, 34 / 255, 34 / 255, 0.72 }
local PREVIEW_MODE_PREVIEW = "preview"
local TEXT_OFFSET_MIN = -16
local TEXT_OFFSET_MAX = 16
local SETTINGS_BODY_FIXED_HEIGHT = 250
local SETTINGS_TAB_HEIGHT = 30
local SELECTOR_DOT_SIZE = 8
local HEADER_KEYBIND_WIDTH = 120
local HEADER_CONFIG_SET_WIDTH = 92
local HEADER_CONTROL_GAP = 8
local HEADER_CONTROL_HEIGHT = 26
local TEXT_ROW_CHECKBOX_WIDTH = 180
local TEXT_ROW_GEAR_GAP = 10
local TEXT_POPOVER_WIDTH = 300
local TEXT_POPOVER_CONTENT_WIDTH = 268
local TEXT_POPOVER_LABEL_WIDTH = 84
local TEXT_POPOVER_BODY_WIDTH = 166
local PREVIEW_DISABLED_ALPHA = 0.55
local MODULE_PAGE_LAYOUT = S.ModulePageLayout
    or { insetX = 20, titleTop = 20 }
local PAGE_TITLE_TOP = MODULE_PAGE_LAYOUT.titleTop
local PAGE_HEADER_TOP = 46
local previewProfessionQualityAtlas
local PREVIEW_PROFESSION_QUALITY_ATLAS = "Professions-Icon-Quality-12-Tier2-Inv"
local SpecialSettings = {}
local EffectPreview = {}
SpecialSettings.shadowColor = GUI2.ShapeShadowDefaults and GUI2.ShapeShadowDefaults.color or { 0, 0, 0, 0.5 }
SpecialSettings.specialGroupId = "specialActionsGroup"
SpecialSettings.specialGroupOrder = { "zoneAbility", "extraAction", "vehicleExit" }
SpecialSettings.growthDirectionOptionKeys = {
    "growth_direction.up",
    "growth_direction.down",
    "growth_direction.left",
    "growth_direction.right",
}
SpecialSettings.groupAlignmentOptionKeys = {
    "group_alignment.start",
    "group_alignment.center",
    "group_alignment.end",
}

local editorState = {
    mode = PREVIEW_MODE_PREVIEW,
    panX = 0,
    panY = 0,
    previewButtons = nil,
    previewFrame = nil,
    previewParent = nil,
    previewDb = nil,
    previewBarId = nil,
    previewX = nil,
    previewY = nil,
    previewWidth = nil,
    previewOnRerender = nil,
    modePromptLabel = nil,
    modePromptPulse = nil,
    textSettingsPopover = nil,
    textSettingsDismiss = nil,
    textSettingsType = nil,
}

local RefreshPreviewOnly
local CloseTextSettingsPopover
local T
local CT
local PreviewSafety = {
    security = YUI.API and YUI.API.Security,
}

function PreviewSafety:IsSecret(value)
    local security = self.security
    if security and type(security.IsSecretValue) == "function" then
        return security.IsSecretValue(value) == true
    end
    return false
end

function PreviewSafety:Number(value)
    local security = self.security
    if security and type(security.SafeNumber) == "function" then
        return security.SafeNumber(value)
    end
    if self:IsSecret(value) then return nil end
    if type(value) == "number" then return value end
    if type(value) ~= "string" then return nil end
    local ok, numberValue = pcall(tonumber, value)
    return ok and numberValue or nil
end

function PreviewSafety:String(value)
    local security = self.security
    if security and type(security.SafeString) == "function" then
        return security.SafeString(value)
    end
    if self:IsSecret(value) then return nil end
    return type(value) == "string" and value or nil
end

function PreviewSafety:Boolean(value)
    local security = self.security
    if security and type(security.SafeBoolean) == "function" then
        return security.SafeBoolean(value)
    end
    if self:IsSecret(value) then return nil end
    if type(value) == "boolean" then return value end
    return nil
end

function PreviewSafety:Value(value)
    if self:IsSecret(value) then return nil end
    return value
end

function PreviewSafety:Call(object, getter, ...)
    if not object or type(getter) ~= "function" then return false end
    return pcall(getter, object, ...)
end

function PreviewSafety:GetNumber(object, getter)
    local ok, value = self:Call(object, getter)
    if not ok then return nil, false end
    local numberValue = self:Number(value)
    return numberValue, numberValue ~= nil
end

local SETTING_FIELDS = {
    "enabled",
    "visibility",
    "hideEmptySlots",
    "hideSkyriding",
    "buttons",
    "size",
    "spacing",
    "alignment",
    "rows",
    "skinId",
    "skinOptions",
    "skin",
    "aspectActiveStyle",
    "showPetUtilities",
    "mageMissingBuffGlow",
    "mageScroll", "mageIntellect", "mageArmor", "mageArmorLeft", "mageArmorMiddle", "mageArmorRight",
    "flyoutDirection",
    "showQuestItems",
    "showCampTools",
    "iconZoom",
    "border",
    "borderColor",
    "background",
    "backgroundColor",
    "shadow",
    "shadowColor",
    "cooldownFade",
    "chargeRecoveryDisplay",
    "cooldownTextSize",
    "cooldownTextOffsetX",
    "cooldownTextOffsetY",
    "rangeMode",
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
    "showProfessionQuality",
    "professionQualitySize",
    "professionQualityOffsetX",
    "professionQualityOffsetY",
}

local TEXT_COLOR_CAPABILITIES = {
    hotkeyColor = "hotkeySize",
    countColor = "countSize",
    macroNameColor = "macroNameSize",
    cooldownTextColor = "cooldownTextSize",
}

local DEFAULT_SETTING_CAPABILITIES = {}
for _, key in ipairs(SETTING_FIELDS) do
    DEFAULT_SETTING_CAPABILITIES[key] = true
end
DEFAULT_SETTING_CAPABILITIES.aspectActiveStyle = false
DEFAULT_SETTING_CAPABILITIES.showPetUtilities = false
DEFAULT_SETTING_CAPABILITIES.mageMissingBuffGlow = false
for _, key in ipairs({ "mageScroll", "mageIntellect", "mageArmor", "mageArmorLeft", "mageArmorMiddle", "mageArmorRight" }) do
    DEFAULT_SETTING_CAPABILITIES[key] = false
end
DEFAULT_SETTING_CAPABILITIES.flyoutDirection = false
DEFAULT_SETTING_CAPABILITIES.showQuestItems = false
DEFAULT_SETTING_CAPABILITIES.showCampTools = false

local BAR_SETTING_CAPABILITIES = {
    specialActionsGroup = {
        chargeRecoveryDisplay = true,
        visibility = true,
        hideSkyriding = true,
        size = true,
        spacing = true,
        skin = true,
        iconZoom = true,
        border = true,
        borderColor = true,
        background = true,
        backgroundColor = true,
        shadow = true,
        shadowColor = true,
        cooldownFade = true,
        cooldownTextSize = true,
        cooldownTextOffsetX = true,
        cooldownTextOffsetY = true,
        rangeMode = true,
        showHotkeys = true,
        hotkeySize = true,
        hotkeyOffsetX = true,
        hotkeyOffsetY = true,
        showCounts = true,
        countSize = true,
        countOffsetX = true,
        countOffsetY = true,
        showMacroNames = true,
        macroNameSize = true,
        macroNameOffsetX = true,
        macroNameOffsetY = true,
    },
    pet = {
        enabled = true,
        hideEmptySlots = true,
        visibility = true,
        hideSkyriding = true,
        buttons = true,
        size = true,
        spacing = true,
        alignment = true,
        rows = true,
        skin = true,
        iconZoom = true,
        border = true,
        borderColor = true,
        background = true,
        backgroundColor = true,
        shadow = true,
        shadowColor = true,
        cooldownFade = true,
        cooldownTextSize = true,
        cooldownTextOffsetX = true,
        cooldownTextOffsetY = true,
        rangeMode = true,
        showHotkeys = true,
        hotkeySize = true,
        hotkeyOffsetX = true,
        hotkeyOffsetY = true,
    },
    extraAction = {
        enabled = true,
        visibility = true,
        hideSkyriding = true,
        size = true,
        skin = true,
        iconZoom = true,
        border = true,
        borderColor = true,
        background = true,
        backgroundColor = true,
        shadow = true,
        shadowColor = true,
        cooldownFade = true,
        cooldownTextOffsetX = true,
        cooldownTextOffsetY = true,
        rangeMode = true,
        showHotkeys = true,
        hotkeySize = true,
        hotkeyOffsetX = true,
        hotkeyOffsetY = true,
        showCounts = true,
        countSize = true,
        countOffsetX = true,
        countOffsetY = true,
    },
    zoneAbility = {
        enabled = true,
        visibility = true,
        hideSkyriding = true,
        size = true,
        spacing = true,
        skin = true,
        iconZoom = true,
        border = true,
        borderColor = true,
        background = true,
        backgroundColor = true,
        shadow = true,
        shadowColor = true,
        cooldownFade = true,
        showCounts = true,
        countSize = true,
        countOffsetX = true,
        countOffsetY = true,
    },
    vehicleExit = {
        enabled = true,
        visibility = true,
        size = true,
        skin = true,
        border = true,
        borderColor = true,
        background = true,
        backgroundColor = true,
        shadow = true,
        shadowColor = true,
    },
}

SpecialSettings.retailCapabilities = {
    stance = {
        enabled = true,
        visibility = true,
        hideSkyriding = true,
        size = true,
        spacing = true,
        alignment = true,
        rows = true,
        skin = true,
        iconZoom = true,
        border = true,
        borderColor = true,
        background = true,
        backgroundColor = true,
        shadow = true,
        shadowColor = true,
        cooldownFade = true,
        cooldownTextSize = true,
        cooldownTextOffsetX = true,
        cooldownTextOffsetY = true,
        showHotkeys = true,
        hotkeySize = true,
        hotkeyOffsetX = true,
        hotkeyOffsetY = true,
    },
    extraAction = {
        enabled = true,
        visibility = true,
        hideSkyriding = true,
        size = true,
        skin = true,
        iconZoom = true,
        border = true,
        borderColor = true,
        background = true,
        backgroundColor = true,
        shadow = true,
        shadowColor = true,
        cooldownFade = true,
        cooldownTextSize = true,
        cooldownTextOffsetX = true,
        cooldownTextOffsetY = true,
        rangeMode = true,
        showHotkeys = true,
        hotkeySize = true,
        hotkeyOffsetX = true,
        hotkeyOffsetY = true,
        showCounts = true,
        countSize = true,
        countOffsetX = true,
        countOffsetY = true,
    },
    zoneAbility = {
        enabled = true,
        visibility = true,
        hideSkyriding = true,
        size = true,
        spacing = true,
        skin = true,
        iconZoom = true,
        border = true,
        borderColor = true,
        background = true,
        backgroundColor = true,
        shadow = true,
        shadowColor = true,
        cooldownFade = true,
        cooldownTextSize = true,
        cooldownTextOffsetX = true,
        cooldownTextOffsetY = true,
        showCounts = true,
        countSize = true,
        countOffsetX = true,
        countOffsetY = true,
    },
    vehicleExit = {
        enabled = true,
        visibility = true,
        size = true,
        skin = true,
        border = true,
        borderColor = true,
        background = true,
        backgroundColor = true,
        shadow = true,
        shadowColor = true,
    },
}

for _, id in ipairs({ "extraAction", "zoneAbility" }) do
    BAR_SETTING_CAPABILITIES[id].chargeRecoveryDisplay = true
    SpecialSettings.retailCapabilities[id].chargeRecoveryDisplay = true
end

local function GetSettingCapabilities(barId)
    if barId == "pet" then
        BAR_SETTING_CAPABILITIES.pet.hideEmptySlots = HasClientCapability("petEmptySlots")
    end
    if barId == "questItems" or barId == "aspects" or barId == "totems" then
        local yab = YUI.YActionBar
        local rule = yab and yab.SpecialBars and yab.SpecialBars:GetRule(barId)
        return rule and rule.capabilities or {}
    end
    if HasClientCapability("deterministicSpecialBars") and SpecialSettings.retailCapabilities[barId] then
        return SpecialSettings.retailCapabilities[barId]
    end
    return BAR_SETTING_CAPABILITIES[barId] or DEFAULT_SETTING_CAPABILITIES
end

local function IsSettingSupported(barId, key)
    if key == "skinId" or key == "skinOptions" then key = "skin" end
    local capabilities = GetSettingCapabilities(barId)
    return capabilities and capabilities[key] == true
end

local function AddSettingField(fields, barId, key, field)
    if IsSettingSupported(barId, key) then
        fields[#fields + 1] = field
    end
end

SpecialSettings.textTypeSettingKeys = {
    hotkey = "hotkeySize",
    count = "countSize",
    macro = "macroNameSize",
    cooldown = "cooldownTextSize",
    professionQuality = "professionQualitySize",
}

function SpecialSettings:IsTextTypeSupported(barId, textType)
    if textType == "professionQuality" and not HasClientCapability("professionQuality") then return false end
    local key = self.textTypeSettingKeys[textType]
    return key ~= nil and IsSettingSupported(barId, key)
end

function SpecialSettings:IsTextSettingsSupported(barId)
    return self:IsTextTypeSupported(barId, "hotkey")
        or self:IsTextTypeSupported(barId, "count")
        or self:IsTextTypeSupported(barId, "macro")
        or self:IsTextTypeSupported(barId, "cooldown")
        or self:IsTextTypeSupported(barId, "professionQuality")
end

function SpecialSettings:ShouldCopyPreviewTextGeometry(options)
    return not options or options.copyRealTextGeometry ~= false
end

function SpecialSettings:IsSettingsGroupSupported(barId, groupId)
    if groupId == "class" then
        local yab = YUI.YActionBar
        return yab and yab.ClassTools and (barId == "classTools" or yab.ClassTools:IsClassBar(barId)) or false
    end
    if groupId == "text" then
        return self:IsTextSettingsSupported(barId)
    end
    return true
end

local BAR_BUTTON_LABELS = {
    main = "1",
    bar2 = "2",
    bar3 = "3",
    bar4 = "4",
    bar5 = "5",
    bar6 = "6",
    bar7 = "7",
    bar8 = "8",
}

local SPECIAL_BUTTON_WIDTHS = {
    stance = 74,
    pet = 68,
    possess = 86,
    extraAction = 74,
    zoneAbility = 74,
    vehicleExit = 96,
    specialActionsGroup = 110,
    questItems = 136,
    classTools = 136,
    mageTools = 152,
    aspects = 152,
    totems = 152,
}

local LAYOUT_SKIN_ASPECTS = {
    flatSquare = 1.35,
    flatRounded = 1.35,
    wideSquare = 10 / 9,
    wideRounded = 10 / 9,
}

local SPECIAL_PREVIEW_COUNTS = {
    pet = 10,
    stance = 10,
    possess = 10,
    extraAction = 1,
    zoneAbility = 2,
    vehicleExit = 1,
}

local PREVIEW_COLORS = {
    { 0.16, 0.22, 0.34 },
    { 0.24, 0.18, 0.27 },
    { 0.15, 0.27, 0.25 },
    { 0.17, 0.23, 0.33 },
    { 0.27, 0.18, 0.26 },
    { 0.15, 0.26, 0.24 },
    { 0.18, 0.23, 0.34 },
    { 0.25, 0.18, 0.27 },
    { 0.15, 0.26, 0.24 },
    { 0.17, 0.22, 0.32 },
    { 0.26, 0.18, 0.25 },
    { 0.15, 0.25, 0.25 },
}

T = function(key, fallback)
    local value = L and L[key]
    if value == nil or value == "" then return fallback or key end
    return value
end

CT = function(key, fallback)
    local value = LC and LC[key]
    if value == nil or value == "" then return fallback or key end
    return value
end

local function GetYAB()
    return YUI.YActionBar
end

local function GetDB()
    local yab = GetYAB()
    -- 设置可原地重置/复制字段，沿用完整规范化；游戏热路径使用 GetDB。
    if yab and yab.EnsureDB then return yab:EnsureDB() end
    return yab and yab.GetDB and yab:GetDB() or nil
end

function SpecialSettings:IsSpecialGroupBar(db, barId)
    if barId ~= self.specialGroupId then return false end
    local yab = GetYAB()
    local mode = yab and yab.GetSpecialGroupingMode and yab:GetSpecialGroupingMode(db)
        or db and db.specialGrouping and db.specialGrouping.mode
        or "independent"
    return mode ~= "independent"
        and db
        and db.specialGrouping
        and type(db.specialGrouping.config) == "table"
end

function SpecialSettings:GetSpecialGroupMembers(db)
    local yab = GetYAB()
    local mode = yab and yab.GetSpecialGroupingMode and yab:GetSpecialGroupingMode(db)
        or db and db.specialGrouping and db.specialGrouping.mode
        or "independent"
    if mode == "all" then
        return self.specialGroupOrder
    end
    if mode == "abilities" then
        return { "zoneAbility", "extraAction" }
    end
    return {}
end

function SpecialSettings:IsDeterministicSpecialPreview(barId)
    if barId == "pet" then return true end
    if not HasClientCapability("deterministicSpecialBars") then return false end
    return barId == "stance"
        or barId == "extraAction"
        or barId == "zoneAbility"
        or barId == "vehicleExit"
end

function SpecialSettings:GetBarLabelKey(barId, short)
    local prefix = short == true and "bar.short." or "bar."
    if barId == "stance" and HasClientCapability("ownedStanceButtons") then
        return prefix .. "stance.retail"
    end
    return prefix .. tostring(barId)
end

local function ClampNumber(value, minValue, maxValue, fallback)
    local numberValue = tonumber(value) or fallback or minValue
    if minValue and numberValue < minValue then numberValue = minValue end
    if maxValue and numberValue > maxValue then numberValue = maxValue end
    return numberValue
end

function SpecialSettings:GetLayoutButtonCount(barId, cfg, snapshot)
    local yab = GetYAB()
    if barId == "classTools" and yab.ClassTools then
        cfg = yab.ClassTools:GetPreviewConfig(barId)
        barId = yab.ClassTools:GetPreviewBarId(barId)
        if barId == "mageTools" then return math.max(#yab.MageTools:GetButtonKeys(cfg), 1) end
        if barId == "aspects" and yab.SpecialBars:GetPlayerClassToken() ~= "HUNTER" then
            return cfg.showPetUtilities ~= false and 7 or 6
        end
    end
    if barId == "questItems" then
        return math.max((cfg.showQuestItems ~= false and 3 or 0) + (cfg.showCampTools ~= false and 5 or 0), 1)
    end
    local specialBars = yab and yab.SpecialBars
    if barId == "aspects" and specialBars and specialBars.GetPreviewButtonCount then
        return ClampNumber(specialBars:GetPreviewButtonCount(barId, cfg, snapshot), 1, 12, 1)
    end
    if specialBars and specialBars.GetRuntimeButtonCount then
        local count = specialBars:GetRuntimeButtonCount(barId, cfg, snapshot)
        if count then return ClampNumber(count, 1, 12, 1) end
    end
    return ClampNumber(snapshot and snapshot.buttons or cfg and cfg.buttons, 1, 12, 12)
end

local function IsAlignmentEffective(barId, cfg, snapshot)
    if not IsSettingSupported(barId, "alignment") then return false end
    local count = SpecialSettings:GetLayoutButtonCount(barId, cfg, snapshot)
    local rows = ClampNumber(snapshot and snapshot.rows or cfg and cfg.rows, 1, count, 1)
    if rows <= 1 then return false end
    local columns = math.max(math.ceil(count / rows), 1)
    return columns > 1 and (count % columns) ~= 0
end

local function CopyValue(value)
    local yab = GetYAB()
    if yab and yab.CopyValue then
        return yab:CopyValue(value)
    end
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do
        result[key] = CopyValue(item)
    end
    return result
end

local function GetDefaultBar(barId)
    local yab = GetYAB()
    if not yab or not yab.Defaults then return nil end
    if yab.Defaults.bars and yab.Defaults.bars[barId] then
        return yab.Defaults.bars[barId]
    end
    if yab.Defaults.specialBars and yab.Defaults.specialBars[barId] then
        return yab.Defaults.specialBars[barId]
    end
    if barId == SpecialSettings.specialGroupId
        and yab.Defaults.specialGrouping
        and yab.Defaults.specialGrouping.config then
        return yab.Defaults.specialGrouping.config
    end
    return nil
end

local function IsOrdinaryBar(db, barId)
    return db and db.bars and db.bars[barId] ~= nil
end

local function IsSpecialBar(db, barId)
    return db and db.specialBars and db.specialBars[barId] ~= nil
end

local function IsSettingsSpecialBarVisible(yab, barId)
    if barId == "aspects" or barId == "totems" or barId == "mageTools" or barId == "classTools" then
        return yab and yab.Client and yab.Client.classBars == true
    end
    if barId == "questItems" then return yab and yab.Client and yab.Client.questItems == true end
    if barId == "possess" and yab and yab.Adapter and yab.Adapter.UseMainActionBarForPossess then
        return not yab.Adapter:UseMainActionBarForPossess()
    end
    return true
end

local function IsClassBarSamplePreview(barId)
    local yab = GetYAB()
    if not (yab and yab.Client and yab.Client.classBars == true) then return false end
    if barId == "classTools" or barId == "mageTools" then return true end
    if barId ~= "aspects" and barId ~= "totems" then return false end
    return yab.SpecialBars:GetPlayerClassToken() ~= (barId == "aspects" and "HUNTER" or "SHAMAN")
end

local function GetSettingsSpecialBarOrder(yab, db)
    local source = yab and yab.SPECIAL_BAR_ORDER or {}
    local order = {}
    db = db or GetDB()
    local mode = yab and yab.GetSpecialGroupingMode and yab:GetSpecialGroupingMode(db)
        or db and db.specialGrouping and db.specialGrouping.mode
        or "independent"
    for _, barId in ipairs(source) do
        if barId ~= "extraAction" and barId ~= "zoneAbility" and barId ~= "vehicleExit" and barId ~= "questItems"
            and IsSettingsSpecialBarVisible(yab, barId) then
            order[#order + 1] = barId
        end
    end
    if mode == "independent" then
        order[#order + 1] = "extraAction"
        order[#order + 1] = "zoneAbility"
        order[#order + 1] = "vehicleExit"
    else
        order[#order + 1] = SpecialSettings.specialGroupId
        if mode == "abilities" then
            order[#order + 1] = "vehicleExit"
        end
    end
    if HasClientCapability("questItems") then order[#order + 1] = "questItems" end
    return yab and yab.ClassTools and yab.ClassTools:GetSettingsOrder(order, db) or order
end

local function IsSelectableBar(db, barId)
    if IsOrdinaryBar(db, barId) then return true end
    if SpecialSettings:IsSpecialGroupBar(db, barId) then return true end
    if IsSpecialBar(db, barId) then
        local yab = GetYAB()
        local mode = yab and yab.GetSpecialGroupingMode and yab:GetSpecialGroupingMode(db)
            or db and db.specialGrouping and db.specialGrouping.mode
            or "independent"
        if yab and yab.IsSpecialBarGrouped and yab:IsSpecialBarGrouped(barId, mode) then
            return false
        end
        if yab and yab.ClassTools then
            if barId == "classTools" then return yab.ClassTools:HasSharedClasses(db) end
            if yab.ClassTools:IsClassBar(barId) then return yab.ClassTools:IsIndependent(barId, db) end
        end
        return IsSettingsSpecialBarVisible(GetYAB(), barId)
    end
    return false
end

local function GetBarConfig(db, barId)
    if IsOrdinaryBar(db, barId) then
        return db.bars[barId], "normal", db.bars
    end
    if IsSpecialBar(db, barId) then
        return db.specialBars[barId], "special", db.specialBars
    end
    if SpecialSettings:IsSpecialGroupBar(db, barId) then
        return db.specialGrouping.config, "specialGroup", nil
    end
    return nil, nil, nil
end

local function SelectSettingsBar(db, barId, preferPlayerClass)
    barId = barId ~= nil and tostring(barId) or nil
    local yab = GetYAB()
    if yab and yab.ClassTools then
        local tools = yab.ClassTools
        if preferPlayerClass and barId == "classTools"
            and not SpecialSettings:IsSettingsGroupSupported(selectedBarId, "class") then
            barId = tools:SelectClass(yab.SpecialBars:GetPlayerClassToken(), db)
                or tools:SelectClass(tools.previewClass, db) or barId
        elseif tools:IsClassBar(barId) then
            for _, class in ipairs(tools.classOrder) do
                if tools.classes[class] == barId then
                    barId = tools:SelectClass(class, db)
                    break
                end
            end
        end
        barId = tools:GetSettingsBarId(barId, db)
    end
    if barId and IsSelectableBar(db, barId) then
        selectedBarId = barId
        return true
    end
    return false
end

local function GetOrderForGroup(group)
    local yab = GetYAB()
    if group == "special" then
        return GetSettingsSpecialBarOrder(yab, GetDB())
    end
    return yab and yab.BAR_ORDER or {}
end

local function EnsureSelectedBar(db)
    local yab = GetYAB()
    if yab and yab.ClassTools then selectedBarId = yab.ClassTools:GetSettingsBarId(selectedBarId, db) end
    if IsSelectableBar(db, selectedBarId) then
        return selectedBarId
    end
    local order = yab and yab.BAR_ORDER or {}
    for _, barId in ipairs(order) do
        if IsOrdinaryBar(db, barId) then
            selectedBarId = barId
            return barId
        end
    end
    for _, barId in ipairs(GetSettingsSpecialBarOrder(yab, db)) do
        if IsSelectableBar(db, barId) then
            selectedBarId = barId
            return barId
        end
    end
    return selectedBarId
end

local function GetBarLabel(barId, cfg)
    return T(SpecialSettings:GetBarLabelKey(barId, false), cfg and cfg.label or tostring(barId))
end

local function BeginSliderDiagnosticPhase(name)
    local form = GUI2 and GUI2.Form
    if form and type(form.BeginSliderDiagnosticPhase) == "function" then
        return form:BeginSliderDiagnosticPhase(name)
    end
    return nil
end

local function EndSliderDiagnosticPhase(token)
    if not token then return end
    local form = GUI2 and GUI2.Form
    if form and type(form.EndSliderDiagnosticPhase) == "function" then
        form:EndSliderDiagnosticPhase(token)
    end
end

local function SyncConfigSnapshot(db, barId, scope)
    if barId == SpecialSettings.specialGroupId then return end
    local yab = GetYAB()
    local manager = yab and yab.BarManager
    if manager and manager.RefreshConfigSnapshot then
        manager:RefreshConfigSnapshot(barId, db)
    end
    if manager and manager.runtimeActive then
        if manager.QueueSettingsRefresh then
            manager:QueueSettingsRefresh(barId, scope or "full")
        else
            if manager.ApplyVisibility then
                manager:ApplyVisibility()
            end
            if manager.QueueFullRefresh then
                manager:QueueFullRefresh("settings")
            end
        end
    end
end

local function AutoSaveCurrentConfigSet(reason)
    local yab = GetYAB()
    local configSets = yab and yab.ConfigSets
    if configSets and type(configSets.SaveActive) == "function" then
        configSets:SaveActive(reason or "settings", S.YActionBarModule)
    end
end

local function PatchConfigSetSettings(barId, values, reason)
    local yab = GetYAB()
    local configSets = yab and yab.ConfigSets
    if not (configSets and type(configSets.SaveActiveSettings) == "function") then
        return nil, "config-sets-unavailable"
    end
    local autosavePhase = BeginSliderDiagnosticPhase("autosave")
    local result, code, detail = configSets:SaveActiveSettings(
        barId,
        values,
        reason or "settings",
        S.YActionBarModule
    )
    EndSliderDiagnosticPhase(autosavePhase)
    return result, code, detail
end

local function PatchConfigSetSetting(barId, field, value, reason)
    return PatchConfigSetSettings(
        barId,
        {
            { field = field, value = value },
        },
        reason or ("settings:" .. tostring(field))
    )
end

local function PatchGlobalConfigSetSetting(section, field, value, reason)
    local yab = GetYAB()
    local configSets = yab and yab.ConfigSets
    if not (configSets and type(configSets.SaveActiveGlobalSetting) == "function") then
        return nil, "config-sets-unavailable"
    end
    return configSets:SaveActiveGlobalSetting(
        section,
        field,
        value,
        reason or ("settings:" .. tostring(field)),
        S.YActionBarModule
    )
end

local function SyncAllConfigSnapshots(db)
    local yab = GetYAB()
    local manager = yab and yab.BarManager
    if manager and manager.RefreshConfigSnapshots then
        manager:RefreshConfigSnapshots(db)
    end
    if manager and manager.ApplyVisibility then
        manager:ApplyVisibility()
    end
    if manager and manager.runtimeActive and manager.QueueFullRefresh then
        manager:QueueFullRefresh("settings")
    end
end

local function ApplyStructuralRefresh(db, barId, reason)
    local result
    if barId == SpecialSettings.specialGroupId then
        local yab = GetYAB()
        local manager = yab and yab.BarManager
        if manager and manager.RefreshSpecialGroupingRuntime then
            result = manager:RefreshSpecialGroupingRuntime(
                db,
                reason or "settings:special-group"
            )
        else
            result = true
        end
    else
        local yab = GetYAB()
        if yab then
            local manager = yab.BarManager
            if manager and manager.RefreshConfigSnapshot then
                manager:RefreshConfigSnapshot(barId, db)
            end
            if manager and manager.ApplyBarStructureChange then
                result = manager:ApplyBarStructureChange(barId, reason or "settings")
            elseif yab.Refresh then
                result = yab:Refresh(reason or "settings")
            end
        end
    end
    return result
end

local function SyncSelectedConfigSnapshot(scope, previewReason)
    if selectedBarId == SpecialSettings.specialGroupId then
        local db = GetDB()
        local yab = GetYAB()
        local manager = yab and yab.BarManager
        local configPhase = BeginSliderDiagnosticPhase("config")
        if previewReason == "text-position" then
            for _, memberId in ipairs(manager and manager.specialGroupOrder or {}) do
                SyncConfigSnapshot(db, memberId, "visual")
            end
        elseif manager and manager.RefreshSpecialGroupingRuntime then
            manager:RefreshSpecialGroupingRuntime(db, "settings:special-group-" .. tostring(scope or "full"))
        end
        EndSliderDiagnosticPhase(configPhase)
        local previewPhase = BeginSliderDiagnosticPhase("preview")
        if RefreshPreviewOnly then
            RefreshPreviewOnly(previewReason or scope or "full")
        end
        EndSliderDiagnosticPhase(previewPhase)
        return
    end
    local configPhase = BeginSliderDiagnosticPhase("config")
    SyncConfigSnapshot(GetDB(), selectedBarId, scope)
    EndSliderDiagnosticPhase(configPhase)
    local previewPhase = BeginSliderDiagnosticPhase("preview")
    if RefreshPreviewOnly then
        RefreshPreviewOnly(previewReason or scope or "full")
    end
    EndSliderDiagnosticPhase(previewPhase)
end

local function SetSetting(cfg, key, value, refreshScope, deferSave)
    if cfg then
        cfg[key] = value
        if selectedBarId == SpecialSettings.specialGroupId then
            SyncSelectedConfigSnapshot(refreshScope or "full")
            if deferSave ~= true then
                PatchConfigSetSetting(
                    selectedBarId,
                    key,
                    cfg[key],
                    "settings:" .. tostring(key)
                )
            end
            return
        end
        if refreshScope == "structure" then
            ApplyStructuralRefresh(GetDB(), selectedBarId, "settings:" .. tostring(key))
            if RefreshPreviewOnly then
                RefreshPreviewOnly(refreshScope or "structure")
            end
        else
            SyncSelectedConfigSnapshot(refreshScope or "full")
        end
        if deferSave ~= true then
            PatchConfigSetSetting(
                selectedBarId,
                key,
                cfg[key],
                "settings:" .. tostring(key)
            )
        end
    end
end

local function CopySettings(source, target, targetBarId)
    if type(source) ~= "table" or type(target) ~= "table" then return end
    local capabilities = GetSettingCapabilities(targetBarId)
    for _, key in ipairs(SETTING_FIELDS) do
        local capabilityKey = TEXT_COLOR_CAPABILITIES[key] or key
        if capabilities[capabilityKey] == true then
            target[key] = CopyValue(source[key])
        end
    end
end

local function ResetSettingsToDefault(barId, cfg)
    local defaults = GetDefaultBar(barId)
    if not defaults or not cfg then return end
    CopySettings(defaults, cfg, barId)
    if barId == SpecialSettings.specialGroupId then
        cfg.growthDirection = defaults.growthDirection
        cfg.groupAlignment = defaults.groupAlignment
        local yab = GetYAB()
        local manager = yab and yab.BarManager
        if manager and manager.RefreshSpecialGroupingRuntime then
            manager:RefreshSpecialGroupingRuntime(GetDB(), "settings:special-group-reset")
        end
        if RefreshPreviewOnly then RefreshPreviewOnly("structure") end
        AutoSaveCurrentConfigSet("settings:special-group-reset")
        return
    end
    ApplyStructuralRefresh(GetDB(), barId, "settings:reset")
    AutoSaveCurrentConfigSet("settings:reset")
end

local function BuildOptions(keys)
    local commonShapeKeys = {
        ["skin.square"] = "common.shape.square",
        ["skin.rounded_square"] = "common.shape.rounded_square",
        ["skin.flat_square"] = "common.shape.flat_square",
        ["skin.flat_rounded"] = "common.shape.flat_rounded",
        ["skin.wide_square"] = "common.shape.wide_square",
        ["skin.wide_rounded"] = "common.shape.wide_rounded",
        ["skin.circle"] = "common.shape.circle",
    }
    local options = {}
    for _, key in ipairs(keys) do
        local commonKey = commonShapeKeys[key]
        options[#options + 1] = {
            text = commonKey
                and CT(commonKey, key)
                or T("settings.option." .. key, key),
            value = key,
        }
    end
    return options
end



local SKIN_OPTION_KEYS = {
    "skin.square",
    "skin.rounded_square",
    "skin.flat_square",
    "skin.flat_rounded",
    "skin.wide_square",
    "skin.wide_rounded",
    "skin.circle",
}
local EXTRA_ACTION_SKIN_OPTION_KEYS = {
    "skin.blizzard",
    "skin.square",
    "skin.rounded_square",
    "skin.flat_square",
    "skin.flat_rounded",
    "skin.wide_square",
    "skin.wide_rounded",
    "skin.circle",
}

local BORDER_OPTION_KEYS = {
    "border.none",
    "border.thin",
    "border.medium",
    "border.thick",
    "border.extra_thick",
}

local BACKGROUND_OPTION_KEYS = {
    "background.transparent",
    "background.solid",
    "background.blizzard",
}

local RANGE_OPTION_KEYS = {
    "range.none",
    "range.red",
}

local ALIGNMENT_OPTION_KEYS = {
    "alignment.left",
    "alignment.center",
    "alignment.right",
}

local PRESSED_EFFECT_OPTION_KEYS = {
    "pressed_effect.darken",
    "pressed_effect.inner_glow",
}

local TOOLTIP_MODE_OPTION_KEYS = {
    "tooltip_mode.always",
    "tooltip_mode.out_of_combat",
}

local SPECIAL_GROUPING_OPTION_KEYS = {
    "special_grouping.independent",
    "special_grouping.all",
    "special_grouping.abilities",
}

local VALUE_MAP = {
    ["visibility.hidden"] = "hidden",
    ["visibility.always"] = "always",
    ["visibility.mouseover"] = "mouseover",
    ["visibility.combat"] = "combat",
    ["visibility.out_of_combat"] = "outOfCombat",
    ["visibility.mounted"] = "mounted",
    ["visibility.unmounted"] = "unmounted",
    ["skin.blizzard"] = "blizzard",
    ["skin.square"] = "square",
    ["skin.rounded_square"] = "roundedSquare",
    ["skin.flat_square"] = "flatSquare",
    ["skin.flat_rounded"] = "flatRounded",
    ["skin.wide_square"] = "wideSquare",
    ["skin.wide_rounded"] = "wideRounded",
    ["skin.circle"] = "circle",
    ["border.none"] = "none",
    ["border.thin"] = "thin",
    ["border.medium"] = "medium",
    ["border.thick"] = "thick",
    ["border.extra_thick"] = "extraThick",
    ["background.transparent"] = "transparent",
    ["background.solid"] = "black",
    ["background.blizzard"] = "blizzard",
    ["range.none"] = "none",
    ["range.red"] = "red",
    ["alignment.left"] = "left",
    ["alignment.center"] = "center",
    ["alignment.right"] = "right",
    ["pressed_effect.darken"] = "darken",
    ["pressed_effect.inner_glow"] = "innerGlow",
    ["tooltip_mode.always"] = "always",
    ["tooltip_mode.out_of_combat"] = "outOfCombat",
    ["special_grouping.independent"] = "independent",
    ["special_grouping.all"] = "all",
    ["special_grouping.abilities"] = "abilities",
    ["growth_direction.up"] = "up",
    ["growth_direction.down"] = "down",
    ["growth_direction.left"] = "left",
    ["growth_direction.right"] = "right",
    ["group_alignment.start"] = "start",
    ["group_alignment.center"] = "center",
    ["group_alignment.end"] = "end",
}

local function BuildMappedOptions(keys)
    local options = BuildOptions(keys)
    for _, option in ipairs(options) do
        option.value = VALUE_MAP[option.value] or option.value
    end
    return options
end

local function GetSkinOptionKeys(barId)
    if barId == "extraAction" then
        return EXTRA_ACTION_SKIN_OPTION_KEYS
    end
    return SKIN_OPTION_KEYS
end

local function GetDefaultSkin(barId)
    if barId == "extraAction" then
        return "blizzard"
    end
    return "square"
end

local ShowCopySourcePopup
local ShowCopyTargetsPopup

local function SettingsIcon(name)
    if GUI2 and GUI2.GetSettingsIcon then
        return GUI2:GetSettingsIcon(name)
    end
    return nil
end

local function CreateButton(parent, text, width, onClick, tone, height, iconName)
    return GUI2.Form:CreateButton(parent, {
        text = text,
        width = width,
        height = height or 26,
        tone = tone or "accent",
        microIcon = iconName,
        iconSize = iconName and 16 or nil,
        contentAlign = iconName and "center" or nil,
        onClick = onClick,
    })
end

local function CreateTextLink(parent, text, width, onClick)
    if GUI2.Form and GUI2.Form.CreateTextLink then
        return GUI2.Form:CreateTextLink(parent, {
            text = text,
            width = width,
            onClick = onClick,
        })
    end
    return CreateButton(parent, text, width, onClick, "default", 22)
end

local function CreateSelectorItem(parent, text, width, enabled, selected, onClick)
    local button = CreateButton(parent, "", width, onClick, "default", 24)
    if button.text then button.text:SetText("") end
    if button.SetSelected then button:SetSelected(selected == true) end

    local dot = GUI2:CreateFrame(button, { width = SELECTOR_DOT_SIZE, height = SELECTOR_DOT_SIZE })
    dot:SetPoint("LEFT", button, "LEFT", 10, 0)
    local dotTexture = dot:CreateTexture(nil, "ARTWORK")
    dotTexture:SetAllPoints()
    local colorKey = enabled == false and "color.text.disabled" or "color.state.success"
    local r, g, b, a = GUI2:GetColor(colorKey)
    dotTexture:SetColorTexture(r or 1, g or 1, b or 1, a == nil and 1 or a)
    dot.texture = dotTexture

    local label = GUI2:CreateText(button, text or "", "font.size.md", enabled == false and "color.text.disabled" or "color.text.accent", "LEFT")
    label:SetPoint("LEFT", dot, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", button, "RIGHT", -6, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    button.yabSelectorDot = dot
    button.yabSelectorLabel = label
    return button
end

local function TrackPreviewButton(button)
    if not button then return end
    editorState.previewButtons = editorState.previewButtons or {}
    editorState.previewButtons[#editorState.previewButtons + 1] = button
end

local function ReleasePreviewButtons()
    local buttons = editorState.previewButtons
    if type(buttons) ~= "table" then return end
    editorState.previewButtons = nil
    local yab = GetYAB()
    local visuals = yab and yab.Visuals
    for index = 1, #buttons do
        local button = buttons[index]
        if button then
            if visuals and visuals.ReleaseButton then
                visuals:ReleaseButton(button)
            end
            if visuals and visuals.buttons then
                visuals.buttons[button] = nil
            end
            if button.Hide then button:Hide() end
        end
        buttons[index] = nil
    end
end

local function StopModePromptPulse()
    local group = editorState.modePromptPulse
    if group and group.Stop then
        group:Stop()
    end
    if editorState.modePromptLabel and editorState.modePromptLabel.SetAlpha then
        editorState.modePromptLabel:SetAlpha(1)
    end
    editorState.modePromptPulse = nil
    editorState.modePromptLabel = nil
end

local function ClearPreviewTransientState(preserveModePrompt)
    if EffectPreview.Hide then EffectPreview:Hide() end
    if not preserveModePrompt then
        StopModePromptPulse()
    end
    if editorState.selectorMenu then editorState.selectorMenu:Hide() end
    if editorState.copyMenu then editorState.copyMenu:Hide() end
    if editorState.visibilityMenu then editorState.visibilityMenu:Hide() end
    if GameTooltip then GameTooltip:Hide() end
    editorState.selectorMenu = nil
    editorState.copyMenu = nil
    editorState.visibilityMenu = nil
end

local function CleanupPreviewEditor(owner, preserveState)
    local mode = editorState.mode
    ReleasePreviewButtons()
    ClearPreviewTransientState()
    if CloseTextSettingsPopover then CloseTextSettingsPopover(true) end
    if editorState.dragFrame and editorState.dragFrame.StopMovingOrSizing then
        editorState.dragFrame:StopMovingOrSizing()
    end
    editorState.dragFrame = nil
    editorState.dragging = nil
    editorState.dragContext = nil
    if preserveState then
        editorState.mode = mode or PREVIEW_MODE_PREVIEW
    else
        editorState.mode = PREVIEW_MODE_PREVIEW
        editorState.panX = 0
        editorState.panY = 0
    end
    editorState.owner = nil
    editorState.previewFrame = nil
    editorState.previewParent = nil
    editorState.previewDb = nil
    editorState.previewBarId = nil
    editorState.previewX = nil
    editorState.previewY = nil
    editorState.previewWidth = nil
    editorState.previewOnRerender = nil
    return true
end

local function ResetEditorForBarChange()
    CleanupPreviewEditor()
    editorState.panX = 0
    editorState.panY = 0
end

local function GetPreviewBindingText(barId, index)
    local yab = GetYAB()
    local keybinds = yab and yab.Keybinds
    if not (keybinds and keybinds.GetBindingText) then
        return ""
    end
    local buttonKey = keybinds.GetButtonKey and keybinds:GetButtonKey(barId, index)
        or (tostring(barId) .. "." .. tostring(index))
    return keybinds:GetBindingText(buttonKey) or ""
end

local function BuildModePromptText()
    return T("settings.preview.title", "预览")
end

local function StartModePromptPulse(label)
    StopModePromptPulse()
    editorState.modePromptLabel = label
end

local function GetPreviewSnapshot(db, barId, cfg)
    if barId == SpecialSettings.specialGroupId then
        return GUI2.IconSkins:ApplyRecipe(CopyValue(cfg or {}), "Flare")
    end
    local yab = GetYAB()
    local manager = yab and yab.BarManager
    local snapshot = manager and manager.RefreshConfigSnapshot and manager:RefreshConfigSnapshot(barId, db) or nil
    if not snapshot and manager and manager.GetConfigSnapshot then
        snapshot = manager:GetConfigSnapshot(barId)
    end
    local previewSnapshot = snapshot or cfg or {}
    local specialBars = yab and yab.SpecialBars
    if specialBars and specialBars.NormalizeConfigSnapshot and not IsOrdinaryBar(db, barId) then
        previewSnapshot = CopyValue(previewSnapshot)
        specialBars:NormalizeConfigSnapshot(barId, previewSnapshot, cfg)
    end
    return previewSnapshot
end

local function BuildPreviewCountText(state, snapshot)
    if not state or state.hasAction ~= true then return "" end
    if snapshot and snapshot.showCounts == false then return "" end
    local display = state.displayCount
    if display ~= nil and display ~= "" then
        if type(display) == "number" or type(display) == "string" then
            return tostring(display)
        end
        return display
    end
    local count = type(state.count) == "number" and state.count or 0
    return count > 1 and tostring(count) or ""
end

local function BuildPreviewNameText(state, snapshot)
    if snapshot and snapshot.showMacroNames == false then return "" end
    return type(state and state.macroText) == "string" and state.macroText or ""
end

local function GetPreviewRecord(barId)
    local yab = GetYAB()
    if barId == "questItems" then return yab and yab.QuestItems and yab.QuestItems.record end
    local manager = yab and yab.BarManager
    return manager and manager.bars and manager.bars[barId] or nil
end

local function GetPreviewRecordButton(record, index)
    if not record then return nil end
    if record.externalButtons and record.externalButtons[index] then
        return record.externalButtons[index]
    end
    return record.buttons and record.buttons[index] or nil
end

local function CountPreviewRecordButtons(record)
    if not record then return 0 end
    local external = record.externalButtons and #record.externalButtons or 0
    local ordinary = record.buttons and #record.buttons or 0
    return math.max(external, ordinary)
end

local function GetPreviewButtonDimensions(snapshot, cfg, realButton)
    local width, height
    local liveGeometrySafe = true
    if realButton then
        width, liveGeometrySafe = PreviewSafety:GetNumber(realButton, realButton.GetWidth)
        local heightSafe
        height, heightSafe = PreviewSafety:GetNumber(realButton, realButton.GetHeight)
        liveGeometrySafe = liveGeometrySafe and heightSafe
    end
    local size = PreviewSafety:Number(snapshot and snapshot.size)
        or PreviewSafety:Number(cfg and cfg.size)
        or width
        or 36
    if not (width and width > 0) then
        width = size
    end
    if not (height and height > 0) then
        height = size
        local aspect = LAYOUT_SKIN_ASPECTS[snapshot and snapshot.skin]
        if aspect then
            height = math.floor((size / aspect) + 0.5)
            if height < 1 then height = 1 end
        end
    end
    return width, height, size, liveGeometrySafe
end

function SpecialSettings:BuildSpecialGroupPreviewLayout(db, cfg, snapshot)
    local members = self:GetSpecialGroupMembers(db)
    local spacing = ClampNumber(snapshot and snapshot.spacing or cfg and cfg.spacing, -10, 64, 4)
    local buttonWidth, buttonHeight, visualSize = GetPreviewButtonDimensions(snapshot, cfg, nil)
    local yab = GetYAB()
    local direction = yab and yab.NormalizeSpecialGroupGrowthDirection
        and yab:NormalizeSpecialGroupGrowthDirection(cfg and cfg.growthDirection)
        or cfg and cfg.growthDirection
        or "up"
    local alignment = yab and yab.NormalizeSpecialGroupAlignment
        and yab:NormalizeSpecialGroupAlignment(cfg and cfg.groupAlignment)
        or cfg and cfg.groupAlignment
        or "center"
    local vertical = direction == "up" or direction == "down"
    local units = {}
    local mainLength = 0
    local crossLength = 1
    for _, memberBarId in ipairs(members) do
        local memberConfig = db and db.specialBars and db.specialBars[memberBarId]
        if not memberConfig or memberConfig.enabled ~= false then
            local memberCount = memberBarId == "zoneAbility" and 2 or 1
            for memberIndex = 1, memberCount do
                units[#units + 1] = {
                    barId = memberBarId,
                    memberIndex = memberIndex,
                    width = buttonWidth,
                    height = buttonHeight,
                }
                mainLength = mainLength + (vertical and buttonHeight or buttonWidth)
                crossLength = math.max(crossLength, vertical and buttonWidth or buttonHeight)
            end
        end
    end
    if #units > 1 then
        mainLength = mainLength + spacing * (#units - 1)
    end
    mainLength = math.max(mainLength, 1)
    local width = vertical and crossLength or mainLength
    local height = vertical and mainLength or crossLength
    local positions = {}
    local cursor = (direction == "up" or direction == "left") and mainLength or 0
    for _, unit in ipairs(units) do
        local unitX = 0
        local unitY = 0
        if vertical then
            if alignment == "center" then
                unitX = (width - unit.width) * 0.5
            elseif alignment == "end" then
                unitX = width - unit.width
            end
            if direction == "up" then
                cursor = cursor - unit.height
                unitY = cursor
                cursor = cursor - spacing
            else
                unitY = cursor
                cursor = cursor + unit.height + spacing
            end
        else
            if alignment == "center" then
                unitY = (height - unit.height) * 0.5
            elseif alignment == "end" then
                unitY = height - unit.height
            end
            if direction == "left" then
                cursor = cursor - unit.width
                unitX = cursor
                cursor = cursor - spacing
            else
                unitX = cursor
                cursor = cursor + unit.width + spacing
            end
        end
        positions[#positions + 1] = {
            memberBarId = unit.barId,
            memberIndex = unit.memberIndex,
            x = unitX,
            y = -unitY,
            width = buttonWidth,
            height = buttonHeight,
            visualSize = visualSize,
        }
    end
    return {
        count = #positions,
        width = math.max(width, 1),
        height = math.max(height, 1),
        positions = positions,
        fromRecord = false,
    }
end

local function GetPreviewButtonCount(db, barId, cfg, snapshot, record)
    if not IsOrdinaryBar(db, barId) then
        if barId == "stance" then
            return SpecialSettings:GetLayoutButtonCount(barId, cfg, snapshot)
        end
        local yab = GetYAB()
        local specialBars = yab and yab.SpecialBars
        if specialBars and specialBars.GetPreviewButtonCount then
            local specialCount = specialBars:GetPreviewButtonCount(barId, cfg, snapshot)
            if specialCount then return specialCount end
        end
    end
    if IsSettingSupported(barId, "buttons") then
        return ClampNumber(snapshot and snapshot.buttons or cfg and cfg.buttons, 1, 12, 12)
    end
    if not IsOrdinaryBar(db, barId) then
        return SPECIAL_PREVIEW_COUNTS[barId] or ClampNumber(snapshot and snapshot.buttons or cfg and cfg.buttons, 1, 12, 1)
    end
    local realCount = CountPreviewRecordButtons(record)
    if realCount > 0 then
        return realCount
    end
    return SPECIAL_PREVIEW_COUNTS[barId] or ClampNumber(snapshot and snapshot.buttons or cfg and cfg.buttons, 1, 12, 1)
end

local function NormalizePreviewAlignment(value, fallback)
    value = tostring(value or "")
    if value == "left" or value == "center" or value == "right" then
        return value
    end
    return fallback or "left"
end

local function TryBuildRealPreviewLayout(db, barId, cfg, snapshot, record, count, expectedLayout)
    if not record or count < 1 then return nil end
    local holder = record.holder or record.mover
    local firstButton = GetPreviewRecordButton(record, 1)
    if not holder and firstButton and firstButton.GetParent then
        local ok, parent = PreviewSafety:Call(firstButton, firstButton.GetParent)
        holder = ok and PreviewSafety:Value(parent) or nil
    end
    if not holder then return nil end

    local holderLeft = PreviewSafety:GetNumber(holder, holder.GetLeft)
    local holderTop = PreviewSafety:GetNumber(holder, holder.GetTop)
    local layoutWidthSecret = PreviewSafety:IsSecret(record.layoutWidth)
    local layoutHeightSecret = PreviewSafety:IsSecret(record.layoutHeight)
    if layoutWidthSecret or layoutHeightSecret then return nil end
    local width = PreviewSafety:Number(record.layoutWidth)
    local height = PreviewSafety:Number(record.layoutHeight)
    if record.layoutWidth ~= nil and width == nil then return nil end
    if record.layoutHeight ~= nil and height == nil then return nil end
    if width == nil then width = PreviewSafety:GetNumber(holder, holder.GetWidth) end
    if height == nil then height = PreviewSafety:GetNumber(holder, holder.GetHeight) end
    if not (holderLeft and holderTop and width and height and width > 0 and height > 0) then
        return nil
    end

    -- Settings rebuild the preview before the queued runtime layout is applied.
    -- Reuse live geometry only after bounds, positions and sizes match the config.
    if math.abs(width - expectedLayout.width) > 0.5
        or math.abs(height - expectedLayout.height) > 0.5 then
        return nil
    end
    local expectedWidth, expectedHeight = GetPreviewButtonDimensions(snapshot, cfg, nil)
    local positions = {}
    for index = 1, count do
        local button = GetPreviewRecordButton(record, index)
        if not (button and button.GetLeft and button.GetTop) then
            return nil
        end
        local left = PreviewSafety:GetNumber(button, button.GetLeft)
        local top = PreviewSafety:GetNumber(button, button.GetTop)
        if not (left and top) then
            return nil
        end
        local expectedPosition = expectedLayout.positions[index]
        if math.abs((left - holderLeft) - expectedPosition.x) > 0.5
            or math.abs((top - holderTop) - expectedPosition.y) > 0.5 then
            return nil
        end
        local buttonWidth, buttonHeight, visualSize, liveGeometrySafe = GetPreviewButtonDimensions(snapshot, cfg, button)
        if not liveGeometrySafe
            or math.abs(buttonWidth - expectedWidth) > 0.5
            or math.abs(buttonHeight - expectedHeight) > 0.5 then
            return nil
        end
        positions[index] = {
            x = left - holderLeft,
            y = top - holderTop,
            width = buttonWidth,
            height = buttonHeight,
            visualSize = visualSize,
            realButton = button,
        }
    end

    return {
        count = count,
        width = width,
        height = height,
        positions = positions,
        fromRecord = true,
    }
end

local function BuildFallbackPreviewLayout(db, barId, cfg, snapshot, count, record)
    local rows = IsSettingSupported(barId, "rows")
        and ClampNumber(snapshot and snapshot.rows or cfg and cfg.rows, 1, count, 1)
        or 1
    local columns = math.max(math.ceil(count / rows), 1)
    local spacing = ClampNumber(snapshot and snapshot.spacing or cfg and cfg.spacing, -10, 64, 4)
    local buttonWidth, buttonHeight, visualSize = GetPreviewButtonDimensions(snapshot, cfg, nil)
    local width = columns * buttonWidth + math.max(columns - 1, 0) * spacing
    local height = rows * buttonHeight + math.max(rows - 1, 0) * spacing
    local alignment = IsSettingSupported(barId, "alignment")
        and NormalizePreviewAlignment(snapshot and snapshot.alignment, barId == "stance" and "center" or "left")
        or "left"
    local positions = {}

    for index = 1, count do
        local row = math.floor((index - 1) / columns)
        local col = (index - 1) % columns
        local rowStart = row * columns + 1
        local rowCount = math.min(columns, count - rowStart + 1)
        local rowWidth = rowCount * buttonWidth + math.max(rowCount - 1, 0) * spacing
        local offsetX = 0
        if alignment == "center" then
            offsetX = (width - rowWidth) * 0.5
        elseif alignment == "right" then
            offsetX = width - rowWidth
        end
        positions[index] = {
            x = offsetX + col * (buttonWidth + spacing),
            y = -(row * (buttonHeight + spacing)),
            width = buttonWidth,
            height = buttonHeight,
            visualSize = visualSize,
            realButton = GetPreviewRecordButton(record, index),
        }
    end

    return {
        count = count,
        width = math.max(width, 1),
        height = math.max(height, 1),
        positions = positions,
        fromRecord = false,
    }
end

local function BuildPreviewLayout(db, barId, cfg, snapshot)
    if barId == SpecialSettings.specialGroupId then
        return SpecialSettings:BuildSpecialGroupPreviewLayout(db, cfg, snapshot)
    end
    if barId == "questItems" and cfg.showQuestItems == false and cfg.showCampTools == false then
        return { count = 0, width = 1, height = 1, positions = {}, fromRecord = false }
    end
    local record = GetPreviewRecord(barId)
    local sample = IsClassBarSamplePreview(barId)
    local count = sample and (barId == "mageTools" and #GetYAB().MageTools:GetButtonKeys(cfg)
        or barId == "aspects" and cfg.showPetUtilities ~= false and 7 or 6)
        or GetPreviewButtonCount(db, barId, cfg, snapshot, record)
    local configuredLayout = BuildFallbackPreviewLayout(db, barId, cfg, snapshot, count, record)
    if sample or barId == "questItems" then return configuredLayout end
    if barId == "aspects" and record and record.petUtilityToggle and cfg.showPetUtilities ~= false then
        configuredLayout.positions[#configuredLayout.positions].realButton = record.petUtilityToggle
        return configuredLayout
    end
    local deterministic = SpecialSettings:IsDeterministicSpecialPreview(barId)
    if not deterministic then
        local realLayout = TryBuildRealPreviewLayout(db, barId, cfg, snapshot, record, count, configuredLayout)
        if realLayout then return realLayout end
    end
    return configuredLayout
end

local function GetPreviewActionSlot(adapter, snapshot, cfg, index, barId)
    local page = ClampNumber(snapshot and snapshot.page or cfg and cfg.page, 1, nil, 1)
    local yab = GetYAB()
    local manager = yab and yab.BarManager
    local record = GetPreviewRecord(barId)
    if manager and manager.GetActionPageForRecord and record then
        page = ClampNumber(manager:GetActionPageForRecord(barId, record, cfg), 1, nil, page)
    end
    if adapter and adapter.GetActionSlot then
        return adapter:GetActionSlot(page, index)
    end
    return ((page - 1) * 12) + index
end

local function ReadPreviewFontStringText(fontString)
    if not fontString then return nil end
    if fontString.IsShown then
        local ok, shown = PreviewSafety:Call(fontString, fontString.IsShown)
        shown = ok and PreviewSafety:Boolean(shown) or nil
        if shown ~= true then return nil end
    end
    if fontString.GetAlpha then
        local alpha, alphaSafe = PreviewSafety:GetNumber(fontString, fontString.GetAlpha)
        if not alphaSafe or alpha <= 0 then return nil end
    end
    if fontString.GetText then
        local ok, text = PreviewSafety:Call(fontString, fontString.GetText)
        if ok then return PreviewSafety:String(text) end
    end
    return nil
end

local function IsPreviewRegionVisible(region)
    if not region then return false end
    local ok, shown = PreviewSafety:Call(region, region.IsVisible or region.IsShown)
    return ok and PreviewSafety:Boolean(shown) == true or false
end

local function CopyRealButtonVisualState(state, realButton, includeText, readVisibleIcon)
    if not (state and realButton) then return false end
    local icon = realButton.icon or realButton.Icon
    local texture
    -- Slot APIs own action identity. Only visible external buttons supply icons.
    if readVisibleIcon == true and IsPreviewRegionVisible(realButton)
        and IsPreviewRegionVisible(icon) and icon.GetTexture then
        local ok, value = PreviewSafety:Call(icon, icon.GetTexture)
        texture = ok and PreviewSafety:Value(value) or nil
    end
    if texture then
        state.texture = texture
        state.hasAction = true
    end
    if includeText == true then
        local hotkey = ReadPreviewFontStringText(realButton.HotKey)
        local count = state.hasAction == true and ReadPreviewFontStringText(realButton.Count) or nil
        local name = state.hasAction == true and ReadPreviewFontStringText(realButton.Name) or nil
        if hotkey ~= nil then state.hotkeyText = hotkey end
        if count ~= nil then state.countText = count end
        if name ~= nil then state.nameText = name end
        return texture ~= nil or hotkey ~= nil or count ~= nil or name ~= nil
    end
    return texture ~= nil
end

local function BuildPreviewButtonState(db, barId, cfg, snapshot, index, realButton, copyRealText)
    local yab = GetYAB()
    local adapter = yab and yab.Adapter
    realButton = realButton or GetPreviewRecordButton(GetPreviewRecord(barId), index)
    local state = {
        texture = nil,
        hasAction = false,
        usable = true,
        rangeMode = snapshot and snapshot.rangeMode or "red",
        inRange = nil,
        checked = false,
        procGlow = false,
        count = 0,
        displayCount = "",
        macroText = "",
        hotkeyText = "",
        countText = "",
        nameText = "",
    }
    if IsOrdinaryBar(db, barId) and adapter then
        local slot = GetPreviewActionSlot(adapter, snapshot, cfg, index, barId)
        state.slot = slot
        if adapter.ReadActionIdentity then
            adapter:ReadActionIdentity(slot, state)
        else
            state.hasAction = adapter.HasAction and adapter:HasAction(slot) == true or false
            state.texture = adapter.GetActionTexture and adapter:GetActionTexture(slot) or nil
            state.count = tonumber(adapter.GetActionCount and adapter:GetActionCount(slot)) or 0
            state.displayCount = adapter.GetActionDisplayCount and adapter:GetActionDisplayCount(slot) or ""
            state.macroText = adapter.GetActionText and adapter:GetActionText(slot) or ""
        end
        if adapter.ReadActionCooldown then adapter:ReadActionCooldown(slot, state) end
        if adapter.ReadActionUsable then adapter:ReadActionUsable(slot, state) end
        if snapshot and snapshot.rangeMode ~= "none" and adapter.ReadActionRange then
            adapter:ReadActionRange(slot, state)
        else
            state.inRange = nil
        end
        if adapter.ReadActionState then adapter:ReadActionState(slot, state) end
        if adapter.ReadActionGlow then adapter:ReadActionGlow(slot, state) end
    elseif IsClassBarSamplePreview(barId) and yab.ClassBars then
        local spellID = yab.ClassBars:GetSampleSpellID(barId, index, cfg)
        local info = spellID and YUI.API.Spell.GetInfo(spellID)
        state.texture = info and (PreviewSafety:Value(info.originalIconID) or PreviewSafety:Value(info.iconID))
        if barId == "aspects" and index == 7 then state.texture = yab.ClassBars.petUtilityAbsentTexture end
        state.hasAction = state.texture ~= nil
        if barId == "aspects" and index <= 6 then
            state.aspectActiveStyle = cfg.aspectActiveStyle or "innerGlow"
            state.checked = index == 2
            state.aspectDimmed = state.aspectActiveStyle == "dimOthers" and not state.checked
            if state.checked and state.aspectActiveStyle == "nativeIcon" then
                state.texture = yab.ClassBars.aspectActiveTexture
            end
        end
    elseif barId == "aspects" and yab and yab.ClassBars and yab.ClassBars.petUtilities
        and realButton == yab.ClassBars.petUtilities.toggle and realButton ~= nil then
        local live = yab.ClassBars.petUtilities.toggleState
        state.texture = PreviewSafety:Value(live.texture)
        state.hasAction, state.usable = state.texture ~= nil, true
        state.checked = live.checked == true
        state.aspectActiveStyle = "innerGlow"
    elseif barId == "aspects" and yab and yab.ClassBars then
        local meta = realButton and yab.SecureFactory:GetButtonMeta(realButton)
        local spellID, known
        if meta then
            spellID, known = yab.ClassBars:ResolveAspect(yab.ClassBars.aspectFamilies[meta.index])
        else
            spellID, known = yab.ClassBars:GetAspectPreview(index, cfg)
        end
        if spellID then
            local info = YUI.API.Spell.GetInfo(spellID)
            state.texture = info and (PreviewSafety:Value(info.originalIconID) or PreviewSafety:Value(info.iconID))
            state.hasAction, state.usable = state.texture ~= nil, known
            state.unlearned = not known
            state.aspectActiveStyle = cfg.aspectActiveStyle or "innerGlow"
            local live = realButton and yab.ClassBars.states[realButton]
            if live then
                state.checked = live.visual.checked == true
                state.aspectDimmed = live.visual.aspectDimmed == true
                state.texture = live.visual.texture or state.texture
            end
        end
    elseif barId == "totems" then
        local button = realButton and (realButton.actionButton or realButton)
        local icon = button and (button.icon or button.Icon or _G[button:GetName() .. "Icon"])
        state.texture = icon and PreviewSafety:Value(icon:GetTexture())
        state.hasAction = state.texture ~= nil
    elseif barId == "questItems" then
        local items = yab and yab.QuestItems
        local entry = items and items.bound and items.bound[realButton]
        local questCount = cfg.showQuestItems ~= false and 3 or 0
        if index <= questCount and entry then
            state.texture = PreviewSafety:Value(entry.texture)
            state.hasAction = state.texture ~= nil
            state.count = PreviewSafety:Number(entry.charges) or 0
            local live = entry.visualState
            if live then
                state.cooldownStart = PreviewSafety:Number(live.cooldownStart)
                state.cooldownDuration = PreviewSafety:Number(live.cooldownDuration)
                state.cooldownEnable = PreviewSafety:Boolean(live.cooldownEnable) == true
                state.cooldownActive = PreviewSafety:Boolean(live.cooldownActive) == true
            end
        elseif index <= questCount then
            state.texture = ({ "Interface\\Icons\\INV_Misc_Book_09", "Interface\\Icons\\INV_Misc_Key_03", "Interface\\Icons\\INV_Misc_Orb_01" })[index]
            state.hasAction, state.count = true, index == 1 and 2 or 0
        elseif cfg.showCampTools ~= false then
            local sampleIndex = index - questCount
            local item = YUI.API and YUI.API.Item
            local tentIcon = item and item.GetIcon and PreviewSafety:Value(item.GetIcon(288185))
            local sleepingIcon = item and item.GetIcon and PreviewSafety:Value(item.GetIcon(211527))
            state.texture = ({ 135805, sleepingIcon or 133662, tentIcon or "Interface\\Icons\\INV_Misc_Bag_10",
                134250, "Interface\\Icons\\INV_Misc_Bag_08" })[sampleIndex]
            state.hasAction = state.texture ~= nil
        end
    elseif adapter and barId == "pet" and adapter.GetPetActionInfo then
        local ok, name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled =
            PreviewSafety:Call(adapter, adapter.GetPetActionInfo, index)
        name = ok and PreviewSafety:String(name) or nil
        texture = ok and PreviewSafety:Value(texture) or nil
        if PreviewSafety:Boolean(isToken) == true then
            state.texture = type(texture) == "string" and PreviewSafety:Value(_G[texture]) or nil
        else
            state.texture = texture
        end
        state.hasAction = name ~= nil or state.texture ~= nil
        state.checked = PreviewSafety:Boolean(isActive) == true
        state.usable = not state.hasAction or not adapter.IsPetActionUsable or adapter:IsPetActionUsable(index)
        state.petAutoCastAllowed = PreviewSafety:Boolean(autoCastAllowed) == true
        state.petAutoCastEnabled = PreviewSafety:Boolean(autoCastEnabled) == true
        if adapter.GetPetActionCooldown then
            local _, start, duration, enable = PreviewSafety:Call(adapter, adapter.GetPetActionCooldown, index)
            state.cooldownStart = PreviewSafety:Number(start)
            state.cooldownDuration = PreviewSafety:Number(duration)
            state.cooldownEnable = state.hasAction
                and (PreviewSafety:Boolean(enable) == true or PreviewSafety:Number(enable) == 1)
            state.cooldownActive = state.hasAction and state.cooldownEnable
                and state.cooldownDuration ~= nil and state.cooldownDuration > 0
        end
    elseif adapter and barId == "stance" and adapter.GetShapeshiftFormInfo then
        local ok, texture, active, castable = PreviewSafety:Call(adapter, adapter.GetShapeshiftFormInfo, index)
        state.texture = ok and PreviewSafety:Value(texture) or nil
        state.hasAction = state.texture ~= nil
        state.checked = PreviewSafety:Boolean(active) == true
        state.usable = PreviewSafety:Boolean(castable) ~= false
        if adapter.GetShapeshiftFormCooldown then
            local _, start, duration, enable = PreviewSafety:Call(adapter, adapter.GetShapeshiftFormCooldown, index)
            state.cooldownStart = PreviewSafety:Number(start)
            state.cooldownDuration = PreviewSafety:Number(duration)
            state.cooldownEnable = state.hasAction
                and (PreviewSafety:Boolean(enable) == true or PreviewSafety:Number(enable) == 1)
            state.cooldownActive = state.hasAction and state.cooldownEnable
                and state.cooldownDuration ~= nil and state.cooldownDuration > 0
        end
    elseif adapter and barId == "possess" and adapter.GetPossessInfo then
        local ok, texture, spellID, enabled = PreviewSafety:Call(adapter, adapter.GetPossessInfo, index)
        state.texture = ok and PreviewSafety:Value(texture) or nil
        state.hasAction = state.texture ~= nil
        state.usable = PreviewSafety:Boolean(enabled) ~= false
    elseif barId == "vehicleExit" and YUI.Assets and YUI.Assets.Product
        and IsPreviewRegionVisible(realButton or _G.MainMenuBarVehicleLeaveButton or _G.VehicleExitButton) then
        state.texture = YUI.Assets:Product("yactionbar", "icons\\vehicle-exit-modern.tga")
        state.hasAction = true
    end

    local externalIcon = barId == "extraAction" or barId == "zoneAbility"
    if barId == "extraAction" and not realButton and index == 1 then realButton = _G.ExtraActionButton1 end
    CopyRealButtonVisualState(state, realButton, false, externalIcon)

    state.rangeMode = snapshot and snapshot.rangeMode or state.rangeMode
    state.hotkeyText = snapshot and snapshot.showHotkeys == false and "" or GetPreviewBindingText(barId, index)
    state.countText = BuildPreviewCountText(state, snapshot)
    state.nameText = BuildPreviewNameText(state, snapshot)
    CopyRealButtonVisualState(state, realButton, copyRealText == true)
    if not SpecialSettings:IsTextTypeSupported(barId, "hotkey") then state.hotkeyText = "" end
    if not SpecialSettings:IsTextTypeSupported(barId, "count") then state.countText = "" end
    if not SpecialSettings:IsTextTypeSupported(barId, "macro") then state.nameText = "" end
    if snapshot then
        if snapshot.showHotkeys == false then state.hotkeyText = "" end
        if snapshot.showCounts == false then state.countText = "" end
        if snapshot.showMacroNames == false then state.nameText = "" end
    end

    return state
end

local function UpdatePreviewStripPosition(viewport, strip)
    if not (viewport and strip) then return end
    local panX = tonumber(editorState.panX) or 0
    local panY = tonumber(editorState.panY) or 0
    local viewportWidth = viewport.GetWidth and viewport:GetWidth() or 0
    local viewportHeight = viewport.GetHeight and viewport:GetHeight() or 0
    local stripWidth = strip.GetWidth and strip:GetWidth() or 0
    local stripHeight = strip.GetHeight and strip:GetHeight() or 0
    if viewportWidth > 0 and stripWidth > 0 and math.abs(panX) > (viewportWidth + stripWidth) * 0.5 then
        panX = 0
    end
    if viewportHeight > 0 and stripHeight > 0 and math.abs(panY) > (viewportHeight + stripHeight) * 0.5 then
        panY = 0
    end
    editorState.panX = panX
    editorState.panY = panY
    strip:ClearAllPoints()
    strip:SetPoint("CENTER", viewport, "CENTER", panX, panY)
end

local function ResetPreviewPan(onRerender)
    editorState.panX = 0
    editorState.panY = 0
    if RefreshPreviewOnly then
        RefreshPreviewOnly("center")
    elseif onRerender then
        onRerender()
    end
end

local StopPreviewDrag

StopPreviewDrag = function()
    local frame = editorState.dragFrame
    local context = editorState.dragContext
    if frame and frame.StopMovingOrSizing then
        frame:StopMovingOrSizing()
    end
    if context and editorState.dragging == "pan" then
        local viewport = context.viewport
        local strip = context.strip
        if viewport and strip and viewport.GetCenter and strip.GetCenter then
            local vx, vy = viewport:GetCenter()
            local sx, sy = strip:GetCenter()
            if vx and vy and sx and sy then
                editorState.panX = sx - vx
                editorState.panY = sy - vy
            end
            UpdatePreviewStripPosition(viewport, strip)
        end
    end
    editorState.dragFrame = nil
    editorState.dragging = nil
    editorState.dragContext = nil
end

local function StartPreviewPanDrag(frame, viewport, strip)
    if not strip then return end
    if strip.SetMovable then strip:SetMovable(true) end
    editorState.dragFrame = strip
    editorState.dragging = "pan"
    editorState.dragContext = { viewport = viewport, strip = strip }
    if strip.StartMoving then strip:StartMoving() end
end

local function CreatePreviewFontString(parent, template)
    if not (parent and parent.CreateFontString) then return nil end
    local text = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    if text.SetWordWrap then text:SetWordWrap(false) end
    if text.SetNonSpaceWrap then text:SetNonSpaceWrap(false) end
    if text.SetMaxLines then text:SetMaxLines(1) end
    return text
end

local function CreatePreviewCooldown(button)
    if not (button and type(CreateFrame) == "function") then return nil end
    local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, button, "CooldownFrameTemplate")
    if not (ok and cooldown) then return nil end
    if cooldown.EnableMouse then cooldown:EnableMouse(false) end
    if cooldown.Hide then cooldown:Hide() end
    return cooldown
end

local function GetPreviewFrameLevel(frame)
    if not (frame and type(frame.GetFrameLevel) == "function") then return nil end
    local ok, level = pcall(frame.GetFrameLevel, frame)
    if ok then return tonumber(level) end
    return nil
end

local function SyncPreviewTextOverlayLevel(button)
    local overlay = button and button.TextOverlayContainer
    if not (overlay and type(overlay.SetFrameLevel) == "function") then return false end
    local maxLevel = GetPreviewFrameLevel(button) or 0
    local frames = {
        button.cooldown,
        button.Cooldown,
        button.chargeCooldown,
        button.ChargeCooldown,
    }
    for _, frame in pairs(frames) do
        local level = GetPreviewFrameLevel(frame)
        if level and level > maxLevel then maxLevel = level end
    end
    overlay:SetFrameLevel(maxLevel + 1)
    return true
end

local function CreatePreviewVisualButton(parent, db, barId, snapshot, width, height, effectPreview)
    local button
    if effectPreview then
        button = GUI2:CreateFrame(parent, { type = "CheckButton", width = width, height = height, mouse = false })
        button.yabEffectPreview = true
        button:SetCheckedTexture(button:CreateTexture(nil, "OVERLAY"))
    else
        button = GUI2:CreateButtonFrame(parent, { width = width, height = height })
    end
    button.yabPreviewButton = true
    button.yabConfigSnapshot = snapshot
    local icon = button:CreateTexture(nil, "ARTWORK")
    button.icon = icon
    button.Icon = icon
    button.HotKey = CreatePreviewFontString(button, "GameFontHighlight")
    button.Count = CreatePreviewFontString(button, "GameFontHighlight")
    button.Name = CreatePreviewFontString(button, "GameFontHighlight")
    button.cooldown = CreatePreviewCooldown(button)
    button.Cooldown = button.cooldown
    button.chargeCooldown = CreatePreviewCooldown(button)
    if not effectPreview then TrackPreviewButton(button) end
    return button
end

local function GetPreviewProfessionQualityAtlas()
    if previewProfessionQualityAtlas ~= nil then
        return previewProfessionQualityAtlas or nil
    end
    local reader = _G.C_Texture and _G.C_Texture.GetAtlasInfo
    if type(reader) ~= "function" then
        previewProfessionQualityAtlas = false
        return nil
    end
    local ok, info = pcall(reader, PREVIEW_PROFESSION_QUALITY_ATLAS)
    if ok and info then
        previewProfessionQualityAtlas = PREVIEW_PROFESSION_QUALITY_ATLAS
        return previewProfessionQualityAtlas
    end
    previewProfessionQualityAtlas = false
    return nil
end

local function ApplyPreviewVisual(button, db, barId, snapshot, width, height, visualSize, state)
    local yab = GetYAB()
    local visuals = yab and yab.Visuals
    if not (button and visuals and visuals.ApplyButton) then return false end

    local options = {
        snapshot = snapshot,
        size = visualSize or width,
        width = width,
        height = height,
        zoom = snapshot and snapshot.iconZoom,
        previewAction = true,
    }
    if barId == "extraAction" or barId == "zoneAbility" or barId == "vehicleExit" then
        options.externalSpecialKind = barId
        if barId == "zoneAbility" then
            options.externalSpecialFrame = button:GetParent()
        end
    end

    visuals:ApplyButton(button, snapshot and snapshot.skin, options)
    if visuals.UpdateButton then
        visuals:UpdateButton(button, state, "full")
    end
    return true
end

function EffectPreview:Hide(owner)
    if GUI2.AssistedHighlightTooltip then GUI2.AssistedHighlightTooltip:Hide(owner) end
    if owner and self.owner ~= owner then return end
    self.owner = nil
    local yab = GetYAB()
    for _, button in ipairs(self.buttons or {}) do
        if yab and yab.Visuals then yab.Visuals:ReleaseButton(button) end
        button:Hide()
    end
    if self.panel then self.panel:Hide() end
end

function EffectPreview:Show(anchor, kind, db)
    self:Hide()
    if kind == "assisted" then
        GUI2.AssistedHighlightTooltip:Show(anchor, T("settings.assisted_highlight"))
        return
    end
    local yab = GetYAB()
    if not (yab and yab.Visuals) then return end
    if not self.panel then
        self.panel = GUI2:CreatePanel(UIParent, { width = 220, height = 132,
            surface = "color.surface.popup", border = "color.popup.border", shadow = true })
        self.panel:SetFrameStrata("TOOLTIP")
        if S.RegisterScaleWindow then S:RegisterScaleWindow(self.panel) end
        self.panel:SetClampedToScreen(true)
        self.panel:EnableMouse(false)
        self.title = GUI2:CreateText(self.panel, "", "font.size.md", "color.text.heading")
        self.title:SetPoint("TOP", 0, -10)
        self.footer = GUI2:CreateText(self.panel, "", "font.size.sm", "color.text.secondary")
        self.footer:SetWidth(196)
        self.footer:SetJustifyH("CENTER")
        self.footer:SetWordWrap(true)
        self.footer:SetPoint("BOTTOM", 0, 10)
        self.buttons = {}
        for index = 1, 2 do
            local button = CreatePreviewVisualButton(self.panel, db, "main", nil, 42, 42, true)
            button:SetPoint("TOPLEFT", index == 1 and 44 or 134, -38)
            self.buttons[index] = button
            local label = GUI2:CreateText(self.panel, T(index == 1 and "settings.effect_on" or "settings.effect_off"),
                "font.size.sm", "color.text.primary")
            label:SetPoint("TOP", button, "BOTTOM", 0, -8)
        end
        self.panel:HookScript("OnHide", function() if self.owner then self:Hide() end end)
    end
    self.owner = anchor
    self.panel:ClearAllPoints()
    self.panel:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 10)
    self.title:SetText(T("settings.show_action_state"))
    self.footer:SetText("")
    self.panel:SetHeight(128)
    local barId = IsOrdinaryBar(db, selectedBarId) and selectedBarId or "main"
    local base = GetPreviewSnapshot(db, barId, db.bars[barId])
    for index, button in ipairs(self.buttons) do
        local snapshot = CopyValue(base)
        snapshot.showActionState = index == 1
        snapshot.showHotkeys, snapshot.showMacroNames, snapshot.showCounts = false, false, false
        snapshot.showProfessionQuality = false
        button.yabConfigSnapshot = snapshot
        button:Show()
        ApplyPreviewVisual(button, db, "main", snapshot, 42, 42, 42, {
            hasAction = true, texture = 132261, usable = true, checked = true,
            hotkey = "", countText = "", name = "",
        })
        yab.Visuals:SetAssistedHighlight(button, false)
    end
    self.panel:Show()
end

function EffectPreview:Bind(field, kind, db, labelInset)
    if field.widget and field.widget.SetHitRectInsets and labelInset then
        field.widget:SetHitRectInsets(-labelInset, 0, 0, 0)
    end
    for _, region in pairs({ field.widget, field.labelRegion }) do
        if region and region.HookScript then
            region:HookScript("OnEnter", function(self) EffectPreview:Show(self, kind, db) end)
            region:HookScript("OnLeave", function(self) EffectPreview:Hide(self) end)
            region:HookScript("OnHide", function(self) EffectPreview:Hide(self) end)
        end
    end
end

local function MapPreviewTextRelativeFrame(relativeTo, realButton, previewButton)
    if not relativeTo then return previewButton end
    if relativeTo == realButton then return previewButton end
    if realButton and previewButton then
        if relativeTo == realButton.icon or relativeTo == realButton.Icon then
            return previewButton.icon or previewButton.Icon or previewButton
        end
        if relativeTo == realButton.HotKey then return previewButton.HotKey or previewButton end
        if relativeTo == realButton.Count then return previewButton.Count or previewButton end
        if relativeTo == realButton.Name then return previewButton.Name or previewButton end
    end
    return previewButton
end

local function CopyPreviewFontStringGeometry(target, source, realButton, previewButton, copyAnchors)
    if not (target and source and previewButton) then return false end
    local width = source.GetWidth and PreviewSafety:GetNumber(source, source.GetWidth) or nil
    local height = source.GetHeight and PreviewSafety:GetNumber(source, source.GetHeight) or nil
    if width and width > 0 and target.SetWidth then target:SetWidth(width) end
    if height and height > 0 and target.SetHeight then target:SetHeight(height) end
    if source.GetJustifyH and target.SetJustifyH then
        local ok, value = PreviewSafety:Call(source, source.GetJustifyH)
        value = ok and PreviewSafety:String(value) or nil
        if value then target:SetJustifyH(value) end
    end
    if source.GetJustifyV and target.SetJustifyV then
        local ok, value = PreviewSafety:Call(source, source.GetJustifyV)
        value = ok and PreviewSafety:String(value) or nil
        if value then target:SetJustifyV(value) end
    end
    if source.CanWordWrap and target.SetWordWrap then
        local ok, value = PreviewSafety:Call(source, source.CanWordWrap)
        if ok then value = PreviewSafety:Boolean(value) else value = nil end
        if value ~= nil then target:SetWordWrap(value) end
    end

    -- The live button refresh is queued after a settings write, so its points
    -- may still describe the previous text offsets. Preview positions already
    -- come from the current snapshot through Visuals.TextAnchors.
    if copyAnchors == false then return true end

    local pointCount = source.GetNumPoints and PreviewSafety:GetNumber(source, source.GetNumPoints) or nil
    if not pointCount or pointCount <= 0 then return false end
    pointCount = math.floor(pointCount)
    local anchors = {}
    for pointIndex = 1, pointCount do
        local ok, rawPoint, rawRelativeTo, rawRelativePoint, rawX, rawY = PreviewSafety:Call(source, source.GetPoint, pointIndex)
        if ok then
            local point = PreviewSafety:String(rawPoint)
            local relativeToSafe = not PreviewSafety:IsSecret(rawRelativeTo)
            local relativePointSafe = not PreviewSafety:IsSecret(rawRelativePoint)
            local xSafe = not PreviewSafety:IsSecret(rawX)
            local ySafe = not PreviewSafety:IsSecret(rawY)
            local relativePoint = relativePointSafe and (rawRelativePoint == nil and point or PreviewSafety:String(rawRelativePoint)) or nil
            local x = xSafe and (rawX == nil and 0 or PreviewSafety:Number(rawX)) or nil
            local y = ySafe and (rawY == nil and 0 or PreviewSafety:Number(rawY)) or nil
            if point and relativeToSafe and relativePoint and x ~= nil and y ~= nil then
                anchors[#anchors + 1] = {
                    point,
                    MapPreviewTextRelativeFrame(rawRelativeTo, realButton, previewButton),
                    relativePoint,
                    x,
                    y,
                }
            end
        end
    end
    if #anchors < 1 then return false end
    if target.ClearAllPoints then target:ClearAllPoints() end
    for _, anchor in ipairs(anchors) do
        target:SetPoint(anchor[1], anchor[2], anchor[3], anchor[4], anchor[5])
    end
    return true
end

local function ApplyPreviewTextGeometry(button, realButton)
    if not (button and realButton) then return end
    CopyPreviewFontStringGeometry(button.HotKey, realButton.HotKey, realButton, button, false)
    CopyPreviewFontStringGeometry(button.Count, realButton.Count, realButton, button, false)
end

local function RenderPreviewButton(parent, db, barId, cfg, snapshot, index, width, height, visualSize, x, y, onRerender, options)
    options = options or {}
    local state = BuildPreviewButtonState(db, barId, cfg, snapshot, index, options.realButton, options.copyRealText == true)
    local button = CreatePreviewVisualButton(parent, db, barId, snapshot, width, height)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if button.SetFrameLevel and parent.GetFrameLevel then
        button:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
    end
    ApplyPreviewVisual(button, db, barId, snapshot, width, height, visualSize, state)
    local professionQualityPreviewActive = editorState.textSettingsType == "professionQuality"
        and editorState.textSettingsPopover ~= nil
    if index == 1
        and professionQualityPreviewActive
        and HasClientCapability("professionQuality")
        and IsOrdinaryBar(db, barId) then
        local yab = GetYAB()
        local visuals = yab and yab.Visuals
        if visuals and visuals.ApplyProfessionQuality then
            visuals:ApplyProfessionQuality(button, GetPreviewProfessionQualityAtlas(), {
                showProfessionQuality = true,
                professionQualitySize = snapshot and snapshot.professionQualitySize,
                professionQualityOffsetX = snapshot and snapshot.professionQualityOffsetX,
                professionQualityOffsetY = snapshot and snapshot.professionQualityOffsetY,
            })
        end
    end
    if SpecialSettings:ShouldCopyPreviewTextGeometry(options) then
        ApplyPreviewTextGeometry(button, options.realButton)
    end
    SyncPreviewTextOverlayLevel(button)
    button:SetScript("OnMouseDown", function(self)
        local strip = self:GetParent()
        local viewport = strip and strip:GetParent()
        StartPreviewPanDrag(self, viewport, strip)
    end)
    button:SetScript("OnMouseUp", StopPreviewDrag)

    return button, state
end

local function ApplyDisabledPreviewPresentation(strip)
    if not strip then return end
    strip:SetAlpha(PREVIEW_DISABLED_ALPHA)
    for _, button in ipairs(editorState.previewButtons or {}) do
        if button and button.GetParent and button:GetParent() == strip
            and button.icon and button.icon.SetDesaturated then
            button.icon:SetDesaturated(true)
        end
    end
end

local function RenderActionBarPreview(parent, db, barId, cfg, viewport, onRerender)
    local yab = GetYAB()
    if yab and yab.ClassTools and (barId == "classTools" or yab.ClassTools:IsClassBar(barId)) then
        cfg = yab.ClassTools:GetPreviewConfig(barId, db)
        barId = yab.ClassTools:GetPreviewBarId(barId)
    end
    local snapshot = GetPreviewSnapshot(db, barId, cfg)
    local layout = BuildPreviewLayout(db, barId, cfg, snapshot)
    local count = layout.count or 1
    local width = layout.width or 1
    local height = layout.height or 1
    local shadowInset = snapshot.shadow ~= false and (tonumber(snapshot.size) or 36) / 6 or 0
    local strip = GUI2:CreateFrame(parent, { width = width + shadowInset * 2, height = height + shadowInset * 2 })
    strip:SetSize(width + shadowInset * 2, height + shadowInset * 2)
    if strip.SetFrameLevel and parent.GetFrameLevel then
        strip:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
    end
    UpdatePreviewStripPosition(viewport, strip)

    for index = 1, count do
        local position = layout.positions and layout.positions[index]
        if position then
            local previewBarId = position.memberBarId or barId
            local previewIndex = position.memberIndex or index
            local previewSnapshot = snapshot
            if position.memberBarId then
                previewSnapshot = CopyValue(snapshot)
                local yab = GetYAB()
                local specialBars = yab and yab.SpecialBars
                if specialBars and specialBars.NormalizeConfigSnapshot then
                    specialBars:NormalizeConfigSnapshot(previewBarId, previewSnapshot, cfg)
                end
            end
            RenderPreviewButton(
                strip,
                db,
                previewBarId,
                cfg,
                previewSnapshot,
                previewIndex,
                position.width or 36,
                position.height or position.width or 36,
                position.visualSize or position.width or 36,
                (position.x or 0) + shadowInset,
                (position.y or 0) - shadowInset,
                onRerender,
                {
                    realButton = position.realButton,
                    copyRealText = editorState.mode == PREVIEW_MODE_PREVIEW and cfg.enabled ~= false,
                }
            )
        end
    end
    if cfg.enabled == false then
        ApplyDisabledPreviewPresentation(strip)
    end
    return strip, width, height
end

local function RenderSelectorMenu(anchor, db, onSelect)
    if editorState.selectorMenu and editorState.selectorMenu:IsShown() then
        editorState.selectorMenu:Hide()
        return
    end
    if editorState.selectorMenu then editorState.selectorMenu:Hide() end

    local yab = GetYAB()
    local menuWidth = 370
    local padding = 12
    local normalButtonWidth = 56
    local normalGap = 10
    local rowHeight = 28
    local menu = GUI2:CreatePanel(anchor, {
        width = menuWidth,
        height = 172,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    menu:SetFrameLevel((anchor:GetFrameLevel() or 1) + 20)
    editorState.selectorMenu = menu

    local titleNormal = GUI2:CreateText(menu, T("settings.selector.normal_bars", "普通动作条"), "font.size.sm", "color.text.secondary")
    titleNormal:SetPoint("TOPLEFT", 12, -10)
    for index, barId in ipairs(yab and yab.BAR_ORDER or {}) do
        if db.bars and db.bars[barId] then
            local cfg = db.bars[barId]
            local current = barId
            local row = math.floor((index - 1) / 4)
            local col = (index - 1) % 4
            local button = CreateSelectorItem(menu, BAR_BUTTON_LABELS[barId] or tostring(barId), normalButtonWidth, cfg.enabled ~= false, current == selectedBarId, function()
                ResetEditorForBarChange()
                SelectSettingsBar(db, current)
                if onSelect then onSelect() end
            end)
            button:SetPoint("TOPLEFT", menu, "TOPLEFT", padding + col * (normalButtonWidth + normalGap), -30 - row * rowHeight)
        end
    end

    local order = GetSettingsSpecialBarOrder(yab, db)
    local cursorY, usedBottom = -88, -76
    local function RenderSection(titleKey, fallback, classTools)
        local cursorX, started = padding, false
        for _, barId in ipairs(order) do
            local cfg = GetBarConfig(db, barId)
            if cfg and SpecialSettings:IsSettingsGroupSupported(barId, "class") == classTools then
                if not started then
                    local title = GUI2:CreateText(menu, T(titleKey, fallback), "font.size.sm", "color.text.secondary")
                    title:SetPoint("TOPLEFT", padding, cursorY)
                    cursorY, started = cursorY - 20, true
                end
                local current = barId
                local width = SPECIAL_BUTTON_WIDTHS[barId] or 78
                if cursorX > padding and (barId == "questItems" or (cursorX + width) > (menuWidth - padding)) then
                    cursorX = padding
                    cursorY = cursorY - rowHeight
                end
                local button = CreateSelectorItem(menu, T(SpecialSettings:GetBarLabelKey(barId, true), GetBarLabel(barId, cfg)), width, cfg.enabled ~= false, current == selectedBarId, function()
                    ResetEditorForBarChange()
                    SelectSettingsBar(db, current, true)
                    if onSelect then onSelect() end
                end)
                button:SetPoint("TOPLEFT", menu, "TOPLEFT", cursorX, cursorY)
                cursorX = cursorX + width + 6
                usedBottom = cursorY - 24
            end
        end
        if started then cursorY = usedBottom - 10 end
    end
    RenderSection("settings.selector.special_bars", "特殊动作条", false)
    RenderSection("settings.selector.class_tools", "职业工具条", true)
    menu:SetHeight(math.max(142, math.abs(usedBottom) + 12))
    menu:Show()
end

local function RenderBarSelector(parent, db, x, y, width, onSelect)
    local frame = GUI2:CreateFrame(parent, { width = width, height = HEADER_CONTROL_HEIGHT })
    frame:SetPoint("TOPLEFT", x, y)
    local barId = EnsureSelectedBar(db)
    local cfg = GetBarConfig(db, barId)
    local selector = GUI2:CreateButtonFrame(frame, {
        template = "BackdropTemplate",
        width = width,
        height = HEADER_CONTROL_HEIGHT,
        onClick = function(button)
            RenderSelectorMenu(button, db, onSelect)
        end,
    })
    GUI2:SkinDropdownButton(selector)
    selector:SetPoint("TOPLEFT", 0, 0)
    local selectorDot = GUI2:CreateFrame(selector, { width = SELECTOR_DOT_SIZE, height = SELECTOR_DOT_SIZE })
    selectorDot:SetPoint("LEFT", selector, "LEFT", 10, 0)
    local selectorDotTexture = selectorDot:CreateTexture(nil, "ARTWORK")
    selectorDotTexture:SetAllPoints()
    local colorKey = cfg.enabled == false and "color.text.disabled" or "color.state.success"
    local r, g, b, a = GUI2:GetColor(colorKey)
    selectorDotTexture:SetColorTexture(r or 1, g or 1, b or 1, a == nil and 1 or a)
    selectorDot.texture = selectorDotTexture
    if selector.text then
        selector.text:SetText(GetBarLabel(barId, cfg))
        selector.text:ClearAllPoints()
        selector.text:SetPoint("LEFT", selectorDot, "RIGHT", 8, 0)
        selector.text:SetPoint("RIGHT", selector, "RIGHT", -24, 0)
    end
    selector.yabSelectorDot = selectorDot
    return frame, 26
end

local function ShowCopyMenu(parent, db, barId, onRerender)
    if editorState.copyMenu and editorState.copyMenu:IsShown() then
        editorState.copyMenu:Hide()
        return
    end
    if editorState.copyMenu then editorState.copyMenu:Hide() end
    local menu = GUI2:CreatePanel(parent, {
        width = 154,
        height = 64,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    menu:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -36)
    menu:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
    editorState.copyMenu = menu

    local copyTo = CreateButton(menu, T("settings.copy_to_other_bars", "复制到其他条"), 132, function()
        menu:Hide()
        ShowCopyTargetsPopup(db, barId, onRerender)
    end, "default", 24, "copy")
    copyTo:SetPoint("TOP", 0, -6)
    local copyFrom = CreateButton(menu, T("settings.copy_from_other_bar", "从其他条复制"), 132, function()
        menu:Hide()
        ShowCopySourcePopup(db, barId, onRerender)
    end, "default", 24, "copy")
    copyFrom:SetPoint("TOP", 0, -34)
    menu:Show()
end

local function CreateVisibilityEditor(parent, cfg, width, compact)
    return GUI2.Form:CreateVisibilityRuleEditor(parent, {
        width = width, height = compact and 24 or nil, popupWidth = 320,
        labelWidth = compact and 128 or math.min(128, math.floor(width * 0.35)),
        controlWidth = compact and 270 or math.max(width - math.min(128, math.floor(width * 0.35)) - 12, 60),
        compact = compact, allowHover = true, binding = cfg,
        value = cfg.visibility,
        get = function() return cfg.visibility end,
        set = function(rule) SetSetting(cfg, "visibility", rule, "visibility") end,
    })
end

local PREVIEW_CONTROL_GAP = 10
local PREVIEW_CONTROL_WIDTHS = {
    enabled = 80,
    visibility = 250,
}

local function BuildPreviewControlSpecs(barId)
    local specs = barId == SpecialSettings.specialGroupId
        and {
            { id = "visibility", width = PREVIEW_CONTROL_WIDTHS.visibility },
        }
        or {
            { id = "enabled", width = PREVIEW_CONTROL_WIDTHS.enabled },
            { id = "visibility", width = PREVIEW_CONTROL_WIDTHS.visibility },
        }
    local width = math.max(#specs - 1, 0) * PREVIEW_CONTROL_GAP
    for index = 1, #specs do
        width = width + specs[index].width
    end
    return specs, width
end

local function RenderPreviewControls(parent, db, barId, cfg, onRerender)
    if editorState.mode ~= PREVIEW_MODE_PREVIEW then return end
    local controlLevel = parent and parent.GetFrameLevel and ((parent:GetFrameLevel() or 1) + 8) or nil
    local function RaisePreviewControl(control)
        if control and controlLevel and control.SetFrameLevel then
            control:SetFrameLevel(controlLevel)
        end
    end

    local y = 12
    local specs, groupWidth = BuildPreviewControlSpecs(barId)
    local controlGroup = GUI2:CreateFrame(parent, { width = groupWidth, height = 24 })
    controlGroup:SetPoint("BOTTOM", parent, "BOTTOM", 0, y)
    local previous
    for index = 1, #specs do
        local spec = specs[index]
        local control
        if spec.id == "enabled" then
            local actionText = cfg.enabled == false
                and T("settings.enable_bar_action", "启用")
                or T("settings.disable_bar_action", "停用")
            control = CreateButton(controlGroup, actionText, spec.width, function()
                cfg.enabled = cfg.enabled == false
                ApplyStructuralRefresh(GetDB(), selectedBarId, "settings:enabled")
                PatchConfigSetSetting(
                    selectedBarId,
                    "enabled",
                    cfg.enabled,
                    "settings:enabled"
                )
                if IsSpecialBar(GetDB(), selectedBarId) and S.ShowReload then
                    S:ShowReload()
                end
                if onRerender then
                    onRerender()
                elseif RefreshPreviewOnly then
                    RefreshPreviewOnly("structure")
                end
            end, cfg.enabled == false and "success" or "default", 24,
                cfg.enabled == false and "play" or "square")
        elseif spec.id == "visibility" then
            control = CreateVisibilityEditor(controlGroup, cfg, spec.width, true)
        end
        if control then
            if previous then
                control:SetPoint("LEFT", previous, "RIGHT", PREVIEW_CONTROL_GAP, 0)
            else
                control:SetPoint("LEFT", controlGroup, "LEFT", 0, 0)
            end
            RaisePreviewControl(control)
            previous = control
        end
    end
end

function SpecialSettings:RenderClassToolsPreview(frame, db, barId, onRerender)
    local tools = GetYAB().ClassTools
    local previewId = tools:GetPreviewBarId(barId)
    for index, class in ipairs(tools.classOrder) do
        local id = tools.classes[class]
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then
            local insetX, insetY = (coords[2] - coords[1]) / 16, (coords[4] - coords[3]) / 16
            coords = { coords[1] + insetX, coords[2] - insetX, coords[3] + insetY, coords[4] - insetY }
        end
        local button = GUI2:CreateIconSlot(frame, {
            size = 26,
            icon = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES",
            texCoords = coords,
            crop = false,
            selected = previewId == id,
            onClick = function()
                selectedBarId = tools:SelectClass(class, db)
                if onRerender then onRerender() end
            end,
        })
        button:SetPoint("TOPLEFT", 12 + (index - 1) * 32, -12)
        button:SetFrameLevel(frame:GetFrameLevel() + 12)
    end
    local independent = tools:IsIndependent(previewId, db)
    local toggle = CreateButton(frame, T(independent and "class_tools.join" or "class_tools.detach"), 104, function()
        if tools:SetIndependent(previewId, not independent) then
            selectedBarId = tools:GetSettingsBarId(previewId)
            if onRerender then onRerender() end
        end
    end, "default", 24)
    toggle:SetPoint("BOTTOMRIGHT", -12, 10)
    toggle:SetFrameLevel(frame:GetFrameLevel() + 12)
end

local function RenderPreviewEditor(parent, db, barId, x, y, width, onRerender)
    local cfg = GetBarConfig(db, barId)
    local frame = GUI2:CreatePanel(parent, {
        width = width,
        height = 178,
        surface = "color.settings.panel",
        border = "color.border.default",
    })
    frame:SetPoint("TOPLEFT", x, y)
    frame:EnableMouse(true)
    frame:SetScript("OnMouseUp", StopPreviewDrag)
    editorState.owner = parent
    editorState.previewFrame = frame
    editorState.previewParent = parent
    editorState.previewDb = db
    editorState.previewBarId = barId
    editorState.previewX = x
    editorState.previewY = y
    editorState.previewWidth = width
    editorState.previewOnRerender = onRerender

    local label = GUI2:CreateText(frame, BuildModePromptText(), "font.size.md", "color.text.primary", "LEFT")
    label:SetPoint("TOPLEFT", 12, -18)
    StartModePromptPulse(label)

    local viewportHeight = 154
    local viewport = GUI2:CreateFrame(frame, { width = width - 24, height = viewportHeight })
    viewport:SetPoint("TOPLEFT", 12, -12)
    if viewport.SetFrameLevel and frame.GetFrameLevel then
        viewport:SetFrameLevel((frame:GetFrameLevel() or 1) + 1)
    end
    if viewport.SetClipsChildren then viewport:SetClipsChildren(true) end
    viewport:EnableMouse(true)

    local strip = RenderActionBarPreview(viewport, db, barId, cfg, viewport, onRerender)
    viewport:SetScript("OnMouseDown", function(self)
        StartPreviewPanDrag(self, viewport, strip)
    end)
    viewport:SetScript("OnMouseUp", StopPreviewDrag)

    local copy
    if barId ~= SpecialSettings.specialGroupId then
        copy = GUI2.Form:CreateIconButton(frame, {
            size = 24,
            icon = SettingsIcon("copy"),
            crop = false,
            tooltip = T("settings.copy_to_other_bars", "复制"),
            onClick = function()
                ShowCopyMenu(frame, db, barId, onRerender)
            end,
        })
        copy:SetPoint("TOPRIGHT", -12, -14)
        if copy.SetFrameLevel and frame.GetFrameLevel then
            copy:SetFrameLevel((frame:GetFrameLevel() or 1) + 8)
        end
    end

    local reset = GUI2.Form:CreateIconButton(frame, {
        size = 24,
        icon = SettingsIcon("rotate-ccw"),
        crop = false,
        tooltip = T("settings.restore_default", "恢复默认"),
        onClick = function()
            local function ApplyReset()
                ResetSettingsToDefault(barId, cfg)
                if onRerender then
                    onRerender()
                elseif RefreshPreviewOnly then
                    RefreshPreviewOnly("structure")
                end
            end
            if S.ShowConfirmPopup then
                S:ShowConfirmPopup(T("settings.confirm_restore_default", "恢复当前动作条的设置默认值？"), ApplyReset, {
                    acceptTone = "danger",
                })
            else
                ApplyReset()
            end
        end,
    })
    if copy then
        reset:SetPoint("RIGHT", copy, "LEFT", -6, 0)
    else
        reset:SetPoint("TOPRIGHT", -12, -14)
    end
    if reset.SetFrameLevel and frame.GetFrameLevel then
        reset:SetFrameLevel((frame:GetFrameLevel() or 1) + 8)
    end

    RenderPreviewControls(frame, db, barId, cfg, onRerender)
    if SpecialSettings:IsSettingsGroupSupported(barId, "class") then
        label:Hide()
        SpecialSettings:RenderClassToolsPreview(frame, db, barId, onRerender)
    end

    return frame, 178
end

RefreshPreviewOnly = function(reason)
    -- Visibility changes update summaries through the shared editor binding.
    -- Rebuilding here destroys the open popup owner and interrupts multi-selection.
    if reason == "visibility" then return true end
    local parent = editorState.previewParent
    local x = editorState.previewX
    local y = editorState.previewY
    local width = editorState.previewWidth
    if editorState.refreshingPreview or not (parent and x and y and width and S.ClearConfig) then
        return false
    end
    local db = GetDB() or editorState.previewDb
    local barId = selectedBarId or editorState.previewBarId
    local cfg = db and GetBarConfig(db, barId)
    if not (db and cfg) then return false end

    if reason == "text-position" then
        local yab = GetYAB()
        local visuals = yab and yab.Visuals
        if not (visuals and visuals.TextAnchors) then return false end
        -- Keep the existing preview frames, contents and pan position while dragging.
        for _, button in ipairs(editorState.previewButtons or {}) do
            local snapshot = button.yabConfigSnapshot
            local visual = visuals.buttons and visuals.buttons[button]
            if snapshot and visual then
                for _, prefix in ipairs(yab.TextStyle.prefixes) do
                    snapshot[prefix.."OffsetX"] = cfg[prefix.."OffsetX"] or 0
                    snapshot[prefix.."OffsetY"] = cfg[prefix.."OffsetY"] or 0
                end
                visuals.TextAnchors:Apply(button, visual, snapshot)
            end
        end
        return true
    end

    editorState.refreshingPreview = true
    ReleasePreviewButtons()
    ClearPreviewTransientState(editorState.mode ~= PREVIEW_MODE_PREVIEW)
    local oldFrame = editorState.previewFrame
    if oldFrame then
        S:ClearConfig(oldFrame)
        oldFrame:Hide()
        oldFrame:SetParent(nil)
    end
    editorState.previewFrame = nil
    RenderPreviewEditor(parent, db, barId, x, y, width, editorState.previewOnRerender)
    editorState.refreshingPreview = nil
    return true
end

ShowCopySourcePopup = function(db, targetBarId, onComplete)
    if not (GUI2 and GUI2.Form and UIParent and db) then return end
    local targetConfig, group, groupTable = GetBarConfig(db, targetBarId)
    if not targetConfig or not groupTable then return end

    local popup = GUI2:CreatePanel(UIParent, {
        width = 340,
        height = 260,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    S:RegisterScaleWindow(popup)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(9999)
    popup:EnableMouse(true)

    local title = GUI2:CreateText(popup, T("settings.copy_source_title", "从其他条复制"), "font.size.lg", "color.text.heading")
    title:SetPoint("TOP", 0, -18)

    local close = CreateButton(popup, T("settings.close", "关闭"), 82, function()
        popup:Hide()
        popup:SetParent(nil)
    end, "default", nil, "x")
    close:SetPoint("BOTTOM", 0, 18)

    local order = GetOrderForGroup(group)
    local columns = 2
    local itemWidth = 126
    local itemHeight = 26
    local gapX = 14
    local gapY = 10
    local startX = -((columns * itemWidth + (columns - 1) * gapX) / 2)
    local index = 0

    for _, sourceBarId in ipairs(order) do
        if sourceBarId ~= targetBarId and groupTable[sourceBarId] then
            index = index + 1
            local row = math.floor((index - 1) / columns)
            local col = (index - 1) % columns
            local currentSource = sourceBarId
            local button = CreateButton(popup, GetBarLabel(currentSource, groupTable[currentSource]), itemWidth, function()
                CopySettings(groupTable[currentSource], targetConfig, targetBarId)
                ApplyStructuralRefresh(db, targetBarId, "settings:copy")
                AutoSaveCurrentConfigSet("settings:copy")
                popup:Hide()
                popup:SetParent(nil)
                if onComplete then onComplete() end
            end, "accent")
            button:SetPoint("TOPLEFT", popup, "TOP", startX + col * (itemWidth + gapX), -56 - row * (itemHeight + gapY))
        end
    end

    popup:Show()
end

ShowCopyTargetsPopup = function(db, sourceBarId, onComplete)
    if not (GUI2 and GUI2.Form and UIParent and db) then return end
    local sourceConfig, group, groupTable = GetBarConfig(db, sourceBarId)
    if not sourceConfig or not groupTable then return end

    local targetIds = {}
    for _, targetBarId in ipairs(GetOrderForGroup(group)) do
        if targetBarId ~= sourceBarId and groupTable[targetBarId] then
            targetIds[#targetIds + 1] = targetBarId
        end
    end

    local columns = 2
    local itemWidth = 170
    local itemHeight = 28
    local gapX = 16
    local gapY = 8
    local rows = math.max(math.ceil(#targetIds / columns), 1)
    local popupWidth = 430
    local popupHeight = math.max(246, 154 + rows * (itemHeight + gapY))
    local selectedTargets = {}
    local checkboxes = {}

    local popup = GUI2:CreatePanel(UIParent, {
        width = popupWidth,
        height = popupHeight,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
    })
    S:RegisterScaleWindow(popup)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(9999)
    popup:EnableMouse(true)

    local title = GUI2:CreateText(popup, T("settings.copy_targets_title", "复制到指定动作条"), "font.size.lg", "color.text.heading")
    title:SetPoint("TOP", 0, -18)

    local feedback = GUI2:CreateText(popup, "", "font.size.sm", "color.text.warning", "CENTER")
    feedback:SetPoint("BOTTOM", popup, "BOTTOM", 0, 58)
    feedback:SetWidth(popupWidth - 44)

    local function SetFeedback(text)
        if feedback and feedback.SetText then
            feedback:SetText(text or "")
        end
    end

    local function SetAllTargets(value)
        value = value == true
        for _, targetBarId in ipairs(targetIds) do
            selectedTargets[targetBarId] = value or nil
            local checkbox = checkboxes[targetBarId]
            if checkbox and checkbox.SetChecked then
                checkbox:SetChecked(value, true)
            end
        end
        SetFeedback("")
    end

    local selectAll = CreateButton(popup, T("settings.copy_targets_select_all", "全选"), 82, function()
        SetAllTargets(true)
    end, "default", 24, "check")
    selectAll:SetPoint("TOP", popup, "TOP", -48, -48)

    local clear = CreateButton(popup, T("settings.copy_targets_clear", "清空"), 82, function()
        SetAllTargets(false)
    end, "default", 24, "x")
    clear:SetPoint("LEFT", selectAll, "RIGHT", 12, 0)

    local startX = -((columns * itemWidth + (columns - 1) * gapX) / 2)
    for index, targetBarId in ipairs(targetIds) do
        local row = math.floor((index - 1) / columns)
        local col = (index - 1) % columns
        local currentTarget = targetBarId
        local checkbox = GUI2.Form:CreateCheckbox(popup, {
            label = GetBarLabel(currentTarget, groupTable[currentTarget]),
            width = itemWidth,
            height = itemHeight,
            get = function() return selectedTargets[currentTarget] == true end,
            set = function(value)
                selectedTargets[currentTarget] = value == true or nil
                SetFeedback("")
            end,
        })
        checkbox:SetPoint("TOPLEFT", popup, "TOP", startX + col * (itemWidth + gapX), -84 - row * (itemHeight + gapY))
        checkboxes[currentTarget] = checkbox
    end

    local copy = CreateButton(popup, T("settings.copy_targets_apply", "复制"), 104, function()
        local changedBars = {}
        for _, targetBarId in ipairs(targetIds) do
            if selectedTargets[targetBarId] == true then
                CopySettings(sourceConfig, groupTable[targetBarId], targetBarId)
                changedBars[#changedBars + 1] = targetBarId
            end
        end
        if #changedBars == 0 then
            SetFeedback(T("settings.copy_targets_empty", "请选择至少一个目标动作条。"))
            return
        end
        SyncAllConfigSnapshots(db)
        for _, changedBarId in ipairs(changedBars) do
            ApplyStructuralRefresh(db, changedBarId, "settings:copy")
        end
        AutoSaveCurrentConfigSet("settings:copy-targets")
        popup:Hide()
        popup:SetParent(nil)
        if onComplete then onComplete() end
    end, "accent", nil, "copy")
    copy:SetPoint("BOTTOM", popup, "BOTTOM", -62, 18)

    local close = CreateButton(popup, T("settings.close", "关闭"), 104, function()
        popup:Hide()
        popup:SetParent(nil)
    end, "default", nil, "x")
    close:SetPoint("LEFT", copy, "RIGHT", 20, 0)

    popup:Show()
end

local ALIGNED_LAYOUT = {
    labelWidth = 118,
    labelGap = 10,
    valueWidth = 56,
    valueGap = 10,
    rowHeight = 32,
    rowGap = 10,
    columnGap = 32,
    minBodyWidth = 150,
}

local COMPACT_TWO_COLUMN_LAYOUT = {
    labelWidth = 112,
    labelGap = 8,
    columnGap = 20,
    minBodyWidth = 120,
}

local APPEARANCE_LAYOUT = {
    labelWidth = 112, labelGap = 8, columnGap = 20, minBodyWidth = 120,
    rowGap = 4,
}

local function GetAlignedBodyWidth(width, layout)
    layout = type(layout) == "table" and layout or ALIGNED_LAYOUT
    local availableWidth = math.max(tonumber(width) or 640, 320)
    local columnGap = tonumber(layout.columnGap) or ALIGNED_LAYOUT.columnGap
    local labelWidth = tonumber(layout.labelWidth) or ALIGNED_LAYOUT.labelWidth
    local labelGap = tonumber(layout.labelGap) or ALIGNED_LAYOUT.labelGap
    local minBodyWidth = tonumber(layout.minBodyWidth) or ALIGNED_LAYOUT.minBodyWidth
    local bodyWidth = math.floor((availableWidth - columnGap) / 2) - labelWidth - labelGap
    return math.max(bodyWidth, minBodyWidth)
end

local function RenderAligned(parent, fields, x, y, width, columns, layout)
    layout = type(layout) == "table" and layout or nil
    local _, _, height = S:RenderAlignedFields(parent, {
        fields = fields,
        x = x,
        y = y,
        width = width,
        columns = columns or 2,
        labelWidth = layout and layout.labelWidth or ALIGNED_LAYOUT.labelWidth,
        labelGap = layout and layout.labelGap or ALIGNED_LAYOUT.labelGap,
        bodyWidth = layout and layout.bodyWidth or GetAlignedBodyWidth(width, layout),
        valueWidth = ALIGNED_LAYOUT.valueWidth,
        valueGap = ALIGNED_LAYOUT.valueGap,
        rowHeight = layout and layout.rowHeight or ALIGNED_LAYOUT.rowHeight,
        rowGap = layout and layout.rowGap or ALIGNED_LAYOUT.rowGap,
        columnGap = layout and layout.columnGap or ALIGNED_LAYOUT.columnGap,
        minBodyWidth = layout and layout.minBodyWidth or ALIGNED_LAYOUT.minBodyWidth,
    })
    return height or 0
end

local function RenderDivider(parent, title, x, y, width)
    local divider = GUI2:CreateDivider(parent, width, nil, title, true)
    divider:SetPoint("TOPLEFT", x, y)
    return divider:GetHeight() or 22
end

local function RenderSection(parent, title, fields, x, y, width, columns)
    if not fields or #fields == 0 then return y end
    local dividerHeight = RenderDivider(parent, title, x, y, width)
    local fieldsY = y - dividerHeight - 10
    local fieldsHeight = RenderAligned(parent, fields, x, fieldsY, width, columns or 2)
    return fieldsY - fieldsHeight - 18
end

local function RenderFieldBlock(parent, fields, x, y, width, columns, bottomGap, layout)
    if not fields or #fields == 0 then return y end
    local fieldsHeight = RenderAligned(parent, fields, x, y, width, columns or 2, layout)
    return y - fieldsHeight - (bottomGap or 18)
end

local TEXT_SETTING_TYPES = {
    {
        id = "hotkey",
        labelKey = "settings.preview.text_hotkey",
        labelFallback = "键位文本",
        enabledKey = "showHotkeys",
        sizeKey = "hotkeySize",
        offsetXKey = "hotkeyOffsetX",
        offsetYKey = "hotkeyOffsetY",
        colorKey = "hotkeyColor",
        sizeMin = 8,
        sizeMax = 24,
        sizeFallback = 12,
    },
    {
        id = "count",
        labelKey = "settings.preview.text_count",
        labelFallback = "数量文本",
        enabledKey = "showCounts",
        sizeKey = "countSize",
        offsetXKey = "countOffsetX",
        offsetYKey = "countOffsetY",
        colorKey = "countColor",
        sizeMin = 8,
        sizeMax = 24,
        sizeFallback = 12,
    },
    {
        id = "macro",
        labelKey = "settings.preview.text_macro",
        labelFallback = "宏名称文本",
        enabledKey = "showMacroNames",
        sizeKey = "macroNameSize",
        offsetXKey = "macroNameOffsetX",
        offsetYKey = "macroNameOffsetY",
        colorKey = "macroNameColor",
        sizeMin = 8,
        sizeMax = 24,
        sizeFallback = 10,
    },
    {
        id = "cooldown",
        labelKey = "settings.preview.text_cooldown",
        labelFallback = "冷却文本",
        sizeKey = "cooldownTextSize",
        offsetXKey = "cooldownTextOffsetX",
        offsetYKey = "cooldownTextOffsetY",
        colorKey = "cooldownTextColor",
        sizeMin = 0,
        sizeMax = 32,
        sizeFallback = 12,
    },
    {
        id = "professionQuality",
        labelKey = "settings.preview.profession_quality",
        labelFallback = "专业品质图标",
        enabledKey = "showProfessionQuality",
        enabledRefreshScope = "visual",
        sizeKey = "professionQualitySize",
        offsetXKey = "professionQualityOffsetX",
        offsetYKey = "professionQualityOffsetY",
        sizeLabelKey = "common.size",
        sizeLabelFallback = "尺寸",
        sizeMin = 8,
        sizeMax = 32,
        sizeFallback = 21,
        offsetXFallback = 0,
        offsetYFallback = 0,
    },
}

local function ClampColorComponent(value, fallback)
    value = tonumber(value)
    if value == nil then value = fallback or 1 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function NormalizeTextColor(value, fallback)
    local source = type(value) == "table" and value or fallback
    if type(source) ~= "table" then source = { 1, 1, 1, 1 } end
    local alpha = source[4]
    if alpha == nil then alpha = source.a end
    return {
        ClampColorComponent(source[1] or source.r, 1),
        ClampColorComponent(source[2] or source.g, 1),
        ClampColorComponent(source[3] or source.b, 1),
        ClampColorComponent(alpha, 1),
    }
end

local function GetTextSettingEnabled(cfg, spec)
    if spec.enabledKey then return cfg[spec.enabledKey] ~= false end
    return (tonumber(cfg[spec.sizeKey]) or 0) > 0
end

local function SetTextSettingEnabled(cfg, spec, enabled)
    if spec.enabledKey then
        SetSetting(cfg, spec.enabledKey, enabled == true, spec.enabledRefreshScope or "action")
        return
    end
    SetSetting(cfg, spec.sizeKey, enabled == true and spec.sizeFallback or 0, "visual")
end

local function GetEffectiveTextColor(cfg, spec)
    if type(cfg[spec.colorKey]) == "table" then
        return NormalizeTextColor(cfg[spec.colorKey])
    end
    local r, g, b, a = GUI2:GetColor("color.text.primary")
    return NormalizeTextColor({ r, g, b, a })
end

CloseTextSettingsPopover = function(suppressPreviewRefresh)
    local professionQualityPreviewWasActive = editorState.textSettingsType == "professionQuality"
    if GUI2.FontStyle then GUI2.FontStyle:CloseForProvider("yactionbar") end
    -- A shared editor may already have been reused by another provider.
    local popup = editorState.textSettingsPopover
    if popup and popup ~= (GUI2.FontStyle and GUI2.FontStyle.editor) then popup:Hide() end
    if editorState.textSettingsDismiss then editorState.textSettingsDismiss:Hide() end
    editorState.textSettingsPopover = nil
    editorState.textSettingsDismiss = nil
    editorState.textSettingsType = nil
    if professionQualityPreviewWasActive
        and suppressPreviewRefresh ~= true
        and RefreshPreviewOnly then
        RefreshPreviewOnly("profession-quality-popover-closed")
    end
    return professionQualityPreviewWasActive
end

local function CreateTextSettingsPopover(anchor, parent, cfg, spec, barId)
    local currentPopup = editorState.textSettingsPopover
    local sharedEditor = GUI2.FontStyle and GUI2.FontStyle.editor
    if editorState.textSettingsType == spec.id and currentPopup and currentPopup:IsShown()
        and (currentPopup ~= sharedEditor or currentPopup.anchor == anchor) then
        CloseTextSettingsPopover()
        return nil
    end
    local professionQualityPreviewWasActive = CloseTextSettingsPopover(true)

    if spec.id ~= "professionQuality" and GUI2.FontStyle and GUI2.FontStyle.OpenEditor then
        local prefix = spec.sizeKey:sub(1, -5)
        editorState.textSettingsPopover = GUI2.FontStyle:OpenEditor("yactionbar:" .. barId .. "/" .. prefix, anchor, {placement="right"})
        editorState.textSettingsType = spec.id
        if professionQualityPreviewWasActive and RefreshPreviewOnly then RefreshPreviewOnly("profession-quality-popover-closed") end
        return editorState.textSettingsPopover
    end

    local host = editorState.owner or parent
    local hostLevel = host and host.GetFrameLevel and (host:GetFrameLevel() or 1) or 1
    local popup = GUI2:CreatePanel(UIParent, {
        width = TEXT_POPOVER_WIDTH,
        height = spec.colorKey and 222 or 178,
        surface = "color.surface.popup",
        border = "color.popup.border",
        shadow = true,
        shadowKey = "shadow.popup.size",
    })
    S:SyncOwnedWindowScale(popup, host)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(hostLevel + 42)
    popup:SetToplevel(true)
    popup:EnableMouse(true)
    if popup.SetClampedToScreen then popup:SetClampedToScreen(true) end
    popup:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 10, 0)
    popup:Raise()
    local popupLevel = popup:GetFrameLevel()

    local dismiss = GUI2:CreateButtonFrame(popup)
    dismiss:SetFrameStrata("DIALOG")
    dismiss:SetFrameLevel(popupLevel > 0 and (popupLevel - 1) or popupLevel)
    dismiss:SetAllPoints(UIParent)
    dismiss:RegisterForClicks("AnyUp")
    dismiss:SetScript("OnClick", CloseTextSettingsPopover)

    local titleText = spec.id == "professionQuality"
        and T("settings.preview.profession_quality_sample", "Profession quality icon (sample)")
        or T(spec.labelKey, spec.labelFallback)
    local title = GUI2:CreateText(popup, titleText, "font.size.lg", "color.text.heading", "LEFT")
    title:SetPoint("TOPLEFT", 16, -14)

    local fields = {
        {
            type = "slider",
            label = CT(spec.sizeLabelKey or "common.text_size", spec.sizeLabelFallback or "文本尺寸"),
            min = spec.sizeMin,
            max = spec.sizeMax,
            step = 1,
            default = spec.sizeFallback,
            get = function() return tonumber(cfg[spec.sizeKey]) or spec.sizeFallback end,
            set = function(value)
                SetSetting(
                    cfg,
                    spec.sizeKey,
                    ClampNumber(value, spec.sizeMin, spec.sizeMax, spec.sizeFallback),
                    "visual",
                    true
                )
            end,
            onCommit = function()
                PatchConfigSetSetting(
                    barId,
                    spec.sizeKey,
                    cfg[spec.sizeKey],
                    "settings:" .. tostring(spec.sizeKey)
                )
            end,
        },
        {
            type = "slider",
            label = CT("common.offset_x", "X 偏移"),
            min = TEXT_OFFSET_MIN,
            max = TEXT_OFFSET_MAX,
            step = 1,
            default = spec.offsetXFallback or 0,
            get = function() return tonumber(cfg[spec.offsetXKey]) or spec.offsetXFallback or 0 end,
            set = function(value)
                SetSetting(
                    cfg,
                    spec.offsetXKey,
                    ClampNumber(value, TEXT_OFFSET_MIN, TEXT_OFFSET_MAX, spec.offsetXFallback or 0),
                    "visual",
                    true
                )
            end,
            onCommit = function()
                PatchConfigSetSetting(
                    barId,
                    spec.offsetXKey,
                    cfg[spec.offsetXKey],
                    "settings:" .. tostring(spec.offsetXKey)
                )
            end,
        },
        {
            type = "slider",
            label = CT("common.offset_y", "Y 偏移"),
            min = TEXT_OFFSET_MIN,
            max = TEXT_OFFSET_MAX,
            step = 1,
            default = spec.offsetYFallback or 0,
            get = function() return tonumber(cfg[spec.offsetYKey]) or spec.offsetYFallback or 0 end,
            set = function(value)
                SetSetting(
                    cfg,
                    spec.offsetYKey,
                    ClampNumber(value, TEXT_OFFSET_MIN, TEXT_OFFSET_MAX, spec.offsetYFallback or 0),
                    "visual",
                    true
                )
            end,
            onCommit = function()
                PatchConfigSetSetting(
                    barId,
                    spec.offsetYKey,
                    cfg[spec.offsetYKey],
                    "settings:" .. tostring(spec.offsetYKey)
                )
            end,
        },
    }
    if spec.colorKey then
        fields[#fields + 1] = {
            type = "color",
            label = CT("common.text_color", "文本颜色"),
            hasAlpha = true,
            default = GetEffectiveTextColor(cfg, spec),
            get = function() return GetEffectiveTextColor(cfg, spec) end,
            set = function(value)
                SetSetting(cfg, spec.colorKey, NormalizeTextColor(value), "visual")
            end,
        }
    end
    RenderAligned(popup, fields, 16, -48, TEXT_POPOVER_CONTENT_WIDTH, 1, {
        labelWidth = TEXT_POPOVER_LABEL_WIDTH,
        bodyWidth = TEXT_POPOVER_BODY_WIDTH,
        valueWidth = 54,
        rowGap = 8,
    })

    editorState.textSettingsPopover = popup
    editorState.textSettingsDismiss = dismiss
    editorState.textSettingsType = spec.id
    if (professionQualityPreviewWasActive or spec.id == "professionQuality") and RefreshPreviewOnly then
        RefreshPreviewOnly("profession-quality-popover-opened")
    end
    return popup
end

local function RegisterTextStyle()
    local textStyle = YUI.YActionBar and YUI.YActionBar.TextStyle
    if not (textStyle and GUI2.FontStyle) then return false end
    if editorState.textStyleProvider == textStyle and editorState.fontStyleRegistry == GUI2.FontStyle then return true end
    -- Suite settings load before the product; standalone may load them after it.
    for _, field in ipairs(textStyle.fieldOrder) do
        if not TEXT_COLOR_CAPABILITIES[field] then SETTING_FIELDS[#SETTING_FIELDS+1] = field end
        TEXT_COLOR_CAPABILITIES[field] = textStyle.fields[field].capability
        DEFAULT_SETTING_CAPABILITIES[field] = true
    end
    textStyle:RegisterEditor({
        getDB=function()
            local yab=GetYAB()
            local profile=yab and yab.GetProfile and yab:GetProfile()
            return profile and profile[yab.STORAGE_KEY] or yab and yab.db
        end,
        getConfig=GetBarConfig, defaults=GetDefaultBar,
        label=GetBarLabel,
        supported=function(barId,role)
            return IsSettingsSpecialBarVisible(GetYAB(),barId) and SpecialSettings:IsTextTypeSupported(barId,role)
        end,
        save=function(barId,values)
            local result,code=PatchConfigSetSettings(barId,values,"settings:text-style")
            -- No active personal set is a normal direct-profile edit.
            if result==nil and code~="set_not_found" and code~="provider_not_found"
                and code~="config-sets-unavailable" and code~="config-sets-service-unavailable" then return false end
            return result~=false
        end,
        refresh=function(barId,positionOnly)
            if barId==selectedBarId then SyncSelectedConfigSnapshot("visual", positionOnly and "text-position")
            elseif barId==SpecialSettings.specialGroupId then
                local manager=GetYAB().BarManager
                if manager and manager.RefreshSpecialGroupingRuntime then manager:RefreshSpecialGroupingRuntime(GetDB(),"text-style") end
            else SyncConfigSnapshot(GetDB(),barId,"visual") end
        end,
    })
    editorState.textStyleProvider, editorState.fontStyleRegistry = textStyle, GUI2.FontStyle
    return true
end

local function RenderTextSettingsRows(parent, cfg, barId, x, y, width)
    local rowHeight = 34
    local rowGap = 8
    local rendered = 0
    for _, spec in ipairs(TEXT_SETTING_TYPES) do
        local rowSpec = spec
        if SpecialSettings:IsTextTypeSupported(barId, rowSpec.id) then
            local row = GUI2:CreateFrame(parent, { width = width, height = rowHeight })
            row:SetPoint("TOPLEFT", x, y - rendered * (rowHeight + rowGap))
            local checkboxWidth = math.min(TEXT_ROW_CHECKBOX_WIDTH, math.max(width - 42, 120))
            local checkbox = GUI2.Form:CreateCheckbox(row, {
                width = checkboxWidth,
                height = rowHeight,
                text = T(rowSpec.labelKey, rowSpec.labelFallback),
                tooltip = CT("common.enable", "启用"),
                get = function() return GetTextSettingEnabled(cfg, rowSpec) end,
                set = function(value) SetTextSettingEnabled(cfg, rowSpec, value == true) end,
            })
            checkbox:SetPoint("LEFT", 0, 0)
            local gear = GUI2.Form:CreateIconButton(row, {
                size = 26,
                icon = SettingsIcon("settings"),
                crop = false,
                tooltip = CT("common.settings", "设置"),
                onClick = function(button)
                    CreateTextSettingsPopover(button, parent, cfg, rowSpec, barId)
                end,
            })
            gear:SetPoint("LEFT", checkbox, "RIGHT", TEXT_ROW_GEAR_GAP, 0)
            gear:HookScript("OnHide", function(button)
                local editor = GUI2.FontStyle and GUI2.FontStyle.editor
                if editor and editor.anchor == button then GUI2.FontStyle:CloseEditor() end
            end)
            if gear.SetFrameLevel then gear:SetFrameLevel((parent:GetFrameLevel() or 1) + 41) end
            rendered = rendered + 1
        end
    end
    return rendered * rowHeight + math.max(rendered - 1, 0) * rowGap
end

local function RenderDisplaySection(parent, cfg, barId, x, y, width, specialParent)
    local cursorY, specialY = y, y
    specialParent = specialParent or parent
    local fieldLayout = { labelWidth = 112, labelGap = 8, bodyWidth = math.max(width - 120, 60), minBodyWidth = 60 }
    local enabledFields = {}
    AddSettingField(enabledFields, barId, "enabled", {
        type = "checkbox", label = T("settings.bar_enabled"), default = true,
        get = function() return cfg.enabled == true end,
        set = function(value)
            SetSetting(cfg, "enabled", value == true, "structure")
            if IsSpecialBar(GetDB(), barId) and S.ShowReload then S:ShowReload() end
        end,
    })
    AddSettingField(enabledFields, barId, "hideEmptySlots", {
        type = "checkbox", label = T("settings.hide_empty_slots"), default = false,
        get = function() return cfg.hideEmptySlots == true end,
        set = function(value) SetSetting(cfg, "hideEmptySlots", value == true, "action") end,
    })
    if #enabledFields > 0 then cursorY = cursorY - RenderAligned(parent, enabledFields, x, cursorY, width, 1, fieldLayout) - 18 end
    if GetSettingCapabilities(barId).visibility then
        local title = GUI2:CreateText(parent, CT("visibility.title", "显示规则"), "font.size.md", "color.text.heading", "LEFT")
        title:SetPoint("TOPLEFT", x, cursorY)
        local editor = CreateVisibilityEditor(parent, cfg, width, false)
        editor:SetPoint("TOPLEFT", x, cursorY - 28)
        cursorY = cursorY - 28 - editor:GetHeight() - 16
    end
    if barId == "main" then
        local db = GetDB()
        db.interaction = db.interaction or {}
        local field = {
            type = "specMultiSelect", label = T("settings.form_paging"), defaultSelected = true,
            panelTitle = T("settings.form_paging"), tooltip = T("settings.form_paging_tooltip"),
            get = function() return CopyValue(db.interaction.formPagingSpecs or {}) end,
            summaryFormatter = function(selected, total)
                return T(selected == total and "settings.paging_all" or selected == 0 and "settings.paging_none" or "settings.paging_selected")
            end,
            set = function(value)
                local yab = GetYAB()
                local mask = yab.ConfigSets:NormalizeFormPagingSpecs(value)
                if not mask then return end
                db.interaction.formPagingSpecs = mask
                if yab.BarManager and yab.BarManager.RefreshMainPaging then yab.BarManager:RefreshMainPaging() end
                PatchGlobalConfigSetSetting("interaction", "formPagingSpecs", mask, "settings:form-paging")
            end,
        }
        specialY = specialY - RenderAligned(specialParent, { field }, x, specialY, width, 1, fieldLayout) - 16
        if field.widget and GUI2.Tooltip then
            field.widget:HookScript("OnEnter", function(owner)
                GUI2.Tooltip:Show(owner, { title = field.label, content = function(tip)
                    tip:AddLine(field.tooltip)
                    if HasClientCapability("heldBindings") then tip:AddLine(T("settings.form_paging_warning"), "warning") end
                end })
            end)
            field.widget:HookScript("OnLeave", function(owner) GUI2.Tooltip:Hide(owner) end)
        end
    end
    local specialFields = {}
    if not SpecialSettings:IsSettingsGroupSupported(barId, "class") then
    AddSettingField(specialFields, barId, "showUnlearned", {
        type = "checkbox", label = T("settings.show_unlearned"), tooltip = T("settings.show_unlearned_tooltip"), default = false,
        get = function() return cfg.showUnlearned == true end,
        set = function(value) SetSetting(cfg, "showUnlearned", value == true, "action") end,
    })
    AddSettingField(specialFields, barId, "showPetUtilities", {
        type = "checkbox", label = T("settings.show_pet_utilities"), default = true,
        get = function() return cfg.showPetUtilities ~= false end,
        set = function(value) SetSetting(cfg, "showPetUtilities", value == true, "structure") end,
    })
    end
    if #specialFields > 0 then specialY = specialY - RenderAligned(specialParent, specialFields, x, specialY, width, 1, fieldLayout) - 16 end
    return cursorY, specialY
end

local function RenderGameCVarSetting(parent, x, y, width, cvar, label, tooltip, layout)
    local system = YUI.API and YUI.API.System
    local function IsAvailable()
        return system and system.GetCVarSafe and system.GetCVarBool and system.SetCVar
            and system.GetCVarSafe(cvar) ~= nil
    end
    local function IsInCombat()
        return InCombatLockdown and InCombatLockdown()
    end
    local checkbox
    local field = {
        type = "checkbox",
        label = label,
        get = function() return IsAvailable() and system.GetCVarBool(cvar) == true or false end,
        set = function(value)
            if IsAvailable() and not IsInCombat() then
                -- This explicit user setting uses the game setter; the conservative
                -- SetCVarSafe preflight rejects secure CVars even outside combat.
                system.SetCVar(cvar, value and 1 or 0)
            end
            -- Read back the game value even when a write was rejected.
            if checkbox then checkbox:RefreshGameCVar() end
        end,
    }
    local height = RenderAligned(parent, { field }, x, y, width, 1, layout)
    checkbox = field.widget
    -- Include the aligned label in the checkbox's hover/click area.
    if checkbox.SetHitRectInsets then
        checkbox:SetHitRectInsets(-(ALIGNED_LAYOUT.labelWidth + ALIGNED_LAYOUT.labelGap), 0, 0, 0)
    end
    -- Aligned fields remove the widget label. Supply the title separately so
    -- the full description is rendered as a wrapping body, not a title line.
    checkbox:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        local titleColor = NORMAL_FONT_COLOR
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, titleColor and titleColor.r or 1,
            titleColor and titleColor.g or 0.82, titleColor and titleColor.b or 0)
        GameTooltip:AddLine(tooltip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    checkbox:HookScript("OnLeave", function(self)
        if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self and YUI.HideGameTooltip then
            YUI.HideGameTooltip()
        end
    end)
    function checkbox:RefreshGameCVar()
        local available = IsAvailable()
        self:SetChecked(available and system.GetCVarBool(cvar) == true or false, true)
        self:SetDisabled(not available or IsInCombat())
    end
    function checkbox:OnGameCVarChanged(_, name)
        if name == cvar then self:RefreshGameCVar() end
    end
    local function OnShow(self)
        if YUI.Event then
            YUI.Event:OffOwner(self)
            YUI.Event:On("CVAR_UPDATE", "OnGameCVarChanged", self)
            YUI.Event:On("PLAYER_REGEN_DISABLED", "RefreshGameCVar", self)
            YUI.Event:On("PLAYER_REGEN_ENABLED", "RefreshGameCVar", self)
        end
        self:RefreshGameCVar()
    end
    checkbox:HookScript("OnShow", OnShow)
    checkbox:HookScript("OnHide", function(self)
        if YUI.Event then YUI.Event:OffOwner(self) end
        if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == self and YUI.HideGameTooltip then
            YUI.HideGameTooltip()
        end
    end)
    checkbox:RefreshGameCVar()
    if checkbox:IsShown() then OnShow(checkbox) end
    return height + ALIGNED_LAYOUT.rowGap
end

local function RenderKeyDownSetting(parent, x, y, width, layout)
    return RenderGameCVarSetting(parent, x, y, width, "ActionButtonUseKeyDown",
        T("settings.key_down", "按下施法"),
        T("settings.key_down_tooltip", "开启后，按下按键时施法；关闭后，松开按键时施法。直接修改游戏 CVar：ActionButtonUseKeyDown，与游戏设置同步，不随 YUI 配置方案保存或切换。战斗中无法修改。"), layout)
end

local function RenderKeyHeldSetting(parent, x, y, width)
    return RenderGameCVarSetting(parent, x, y, width, "ActionButtonUseKeyHeldSpell",
        T("settings.key_held", "按住施法"),
        T("settings.key_held_tooltip", "开启后，持续按住按键可连续施放支持此功能的法术，松开停止。直接修改游戏 CVar：ActionButtonUseKeyHeldSpell，与游戏设置同步，不随 YUI 配置方案保存或切换。战斗中无法修改。"))
end

local function RenderRankUpgradeSetting(parent, db, x, y, width)
    local field = {
        type = "checkbox",
        label = T("settings.auto_rank_upgrade"),
        tooltip = T("settings.auto_rank_upgrade_tooltip"),
        default = true,
        get = function() return db.interaction.autoRankUpgrade ~= false end,
        set = function(value)
            local yab = GetYAB()
            if not (yab and yab.RankUpgrade) then return end
            local enabled = value == true
            if (db.interaction.autoRankUpgrade ~= false) == enabled then return end
            yab.RankUpgrade:SetEnabled(enabled)
            PatchGlobalConfigSetSetting("interaction", "autoRankUpgrade", enabled, "settings:auto-rank-upgrade")
        end,
    }
    local height = RenderAligned(parent, { field }, x, y, width, 1, { bodyWidth = 24, minBodyWidth = 24 })
    if field.widget and field.widget.SetHitRectInsets then
        field.widget:SetHitRectInsets(-(ALIGNED_LAYOUT.labelWidth + ALIGNED_LAYOUT.labelGap), 0, 0, 0)
    end
    return height + ALIGNED_LAYOUT.rowGap
end

local function BuildChargeRecoveryPreviewStyle(cfg)
    cfg = GUI2.IconSkins:ApplyRecipe(CopyValue(cfg), "Flare")
    local fontStyle = GUI2.FontStyle
    local function TextStyle(prefix, size, enabled, position, offsetY)
        local effect = fontStyle.Decode(cfg[prefix .. "Outline"] or "OUTLINE",
            cfg[prefix .. "Shadow"] ~= false, cfg[prefix .. "Monochrome"])
        return {
            enabled = enabled, size = size, font = cfg[prefix .. "Font"],
            outline = fontStyle.EncodeEffect(effect, "camel"), monochrome = effect.monochrome,
            color = { fontStyle.ColorRGBA(cfg[prefix .. "Color"]) },
            position = position, offsetX = cfg[prefix .. "OffsetX"] or 0,
            offsetY = (cfg[prefix .. "OffsetY"] or 0) + (offsetY or 0),
        }
    end
    return {
        iconShape = cfg.skin == "blizzard" and "square" or cfg.skin,
        iconBorder = cfg.border, iconZoom = cfg.iconZoom, iconBorderColor = cfg.borderColor,
        iconBackgroundColor = cfg.background == "transparent" and { 0, 0, 0, 0 } or cfg.backgroundColor,
        iconShadow = cfg.shadow, iconShadowColor = cfg.shadowColor,
        cooldownSwipeColor = { 0, 0, 0, 0.42 },
        cooldownTextStyle = TextStyle("cooldownText", cfg.cooldownTextSize or 12,
            (cfg.cooldownTextSize or 12) > 0, "center"),
        countTextStyle = TextStyle("count", cfg.countSize or 12,
            cfg.showCounts ~= false, "bottom-right", -1),
    }
end

function SpecialSettings:RenderClassToolsOptions(parent, width, onRerender)
    local yab, db = GetYAB(), GetDB()
    local id = yab.ClassTools:GetPreviewBarId(selectedBarId)
    local cfg, fields = db.specialBars[id], {}
    local function Set(key, value)
        cfg[key] = value
        ApplyStructuralRefresh(db, id, "settings:" .. key)
        PatchConfigSetSetting(id, key, value, "settings:" .. key)
        if onRerender then onRerender() end
    end
    if id == "mageTools" then
        local availableWidth = math.max(width - 40, 1)
        local formWidth = math.min(availableWidth, 488)
        local iconCoords = { 1 / 16, 15 / 16, 1 / 16, 15 / 16 }
        local function Icon(info)
            return info and (PreviewSafety:Value(info.originalIconID) or PreviewSafety:Value(info.iconID)) or 134400
        end
        for _, entry in ipairs({ { "mageScroll", "scroll", yab.MageData.comprehendSpellID },
            { "mageIntellect", "intellect", yab.MageData.intellectSpellID },
            { "mageArmor", "armor", yab.MageTools:ResolveArmor(cfg.mageArmorLeft) } }) do
            local key = entry[1]
            local icon = Icon(YUI.API.Spell.GetInfo(entry[3]))
            fields[#fields + 1] = { type = "checkbox", height = 24,
                label = "|T" .. tostring(icon) .. ":16:16:0:0:64:64:4:60:4:60|t " .. T("class_tools." .. entry[2]),
                get = function() return cfg[key] ~= false end, set = function(value) Set(key, value == true) end }
        end
        local _, _, toggleHeight = S:RenderAlignedFields(parent, { fields = fields, x = 20, y = -12,
            width = math.min(availableWidth, 324), columns = 3, labelPosition = "top", columnGap = 12,
            minColumnWidth = 96, rowHeight = 24, rowGap = 8 })
        fields = {}
        local infoIce = YUI.API.Spell.GetInfo(yab.MageData.armorSpells.ice)
        local infoFrost = YUI.API.Spell.GetInfo(yab.MageData.armorSpells.frost)
        local options = { { value = "auto", icon = Icon(YUI.API.Spell.GetInfo(yab.MageTools:ResolveArmor("auto"))),
            iconSize = 16, texCoords = iconCoords, text = string.format(T("class_tools.armor_auto"),
            infoIce and infoIce.name or "", infoFrost and infoFrost.name or "") } }
        for _, key in ipairs({ "mage", "ice", "frost" }) do
            local info = YUI.API.Spell.GetInfo(yab.MageData.armorSpells[key])
            options[#options + 1] = { value = key, text = info and info.name or T("class_tools.unlearned"),
                icon = Icon(info), iconSize = 16, texCoords = iconCoords }
        end
        for _, entry in ipairs({ { "mageArmorLeft", "left" }, { "mageArmorRight", "right" } }) do
            local key = entry[1]
            fields[#fields + 1] = { type = "dropdown", label = T("class_tools." .. entry[2]), options = options,
                get = function() return cfg[key] end, set = function(value) Set(key, value) end }
        end
        local glowOptions = {}
        for _, style in ipairs({ "none", "pixel", "soft", "button", "autocast", "proc", "pulse", "masque" }) do
            glowOptions[#glowOptions + 1] = { value = style, text = T("class_tools.glow_" .. style) }
        end
        local labels = {}
        for _, key in ipairs({ "color", "lines", "thickness", "speed", "alpha", "size", "offsetX", "offsetY", "type", "params", "paramsDetail", "reset" }) do
            labels[key] = T("class_tools.glow_" .. key)
        end
        labels.none, labels.noneSummary = T("class_tools.glow_none"), T("class_tools.glow_none")
        labels.summaryLines, labels.summaryThickness, labels.summarySpeed = labels.lines, labels.thickness, labels.speed
        labels.summarySize, labels.summaryAlpha, labels.summaryColor = labels.size, labels.alpha, labels.color
        labels.summaryOffset = T("class_tools.glow_offset")
        fields[#fields + 1] = { type = "glow", span = "full", label = T("class_tools.missing_glow"),
            bodyWidth = math.min(formWidth, 280), panelWidth = formWidth,
            options = glowOptions, labels = labels, applyStyleDefaultsOnChange = true,
            default = yab.Defaults.specialBars.mageTools.mageMissingBuffGlow,
            getExpanded = function() return SpecialSettings.mageGlowExpanded == true end,
            setExpanded = function(value) SpecialSettings.mageGlowExpanded = value == true end,
            onRequestRefresh = function() if onRerender then onRerender() end end,
            get = function() return cfg.mageMissingBuffGlow end,
            set = function(value)
                cfg.mageMissingBuffGlow = CopyValue(value)
                yab.ClassTools:Invalidate()
                yab.MageTools:ApplyMissingGlowSettings(yab.ClassTools:GetConfig(id, db))
            end,
            onCommit = function()
                if GetDB() == db then
                    PatchConfigSetSetting(id, "mageMissingBuffGlow", cfg.mageMissingBuffGlow, "settings:mage-missing-glow")
                end
            end,
        }
        local _, _, height = S:RenderAlignedFields(parent, { fields = fields, x = 20, y = -toggleHeight - 26,
            width = formWidth, columns = 2, labelPosition = "top", columnGap = 12, minColumnWidth = 216,
            rowHeight = 26, rowGap = 14, topLabelGap = 4 })
        return toggleHeight + height + 38
    end
    if id == "aspects" then
        for _, entry in ipairs({ { "showUnlearned", "settings.show_unlearned" }, { "showPetUtilities", "settings.show_pet_utilities" } }) do
            local key = entry[1]
            fields[#fields + 1] = { type = "checkbox", label = T(entry[2]),
                get = function() return cfg[key] == true end, set = function(value) Set(key, value == true) end }
        end
    end
    if id == "aspects" then
        fields[#fields + 1] = { type = "dropdown", label = T("settings.aspect_active_style"),
            options = { { value = "innerGlow", text = T("aspect_active.inner_glow") },
                { value = "nativeIcon", text = T("aspect_active.native_icon") },
                { value = "dimOthers", text = T("aspect_active.dim_others") } },
            get = function() return cfg.aspectActiveStyle or "innerGlow" end,
            set = function(value) Set("aspectActiveStyle", value) end }
    end
    fields[#fields + 1] = { type = "dropdown", label = T("settings.flyout_direction"),
        options = BuildMappedOptions(SpecialSettings.growthDirectionOptionKeys),
        get = function() return cfg.flyoutDirection or "up" end, set = function(value) Set("flyoutDirection", value) end }
    return RenderAligned(parent, fields, 20, -16, width - 40, 2) + 32
end

local function RenderCurrentOptions(parent, cfg, formWidth, onRerender, db)
    local width = math.max(tonumber(formWidth) or 640, 320)
    local x = 20
    local y = -22
    local sectionWidth = math.max(width - x * 2, 280)

    local barId = selectedBarId
    if selectedGroup == "class" then return SpecialSettings:RenderClassToolsOptions(parent, formWidth, onRerender) end
    if selectedGroup == "global" then
        db = db or GetDB()
        db.appearance = db.appearance or {}
        db.interaction = db.interaction or {}
        db.specialGrouping = db.specialGrouping or {}
        local rankUpgrade = HasClientCapability("rankUpgrade")
        local twoColumns = rankUpgrade and sectionWidth >= 2 * (ALIGNED_LAYOUT.labelWidth + ALIGNED_LAYOUT.labelGap + 24) + ALIGNED_LAYOUT.columnGap
        local columnWidth = math.floor((sectionWidth - ALIGNED_LAYOUT.columnGap) / 2)
        if rankUpgrade then y = -10 end
        local stateFieldsY = y
        local firstRowHeight = RenderKeyDownSetting(parent, x, y, twoColumns and columnWidth or sectionWidth,
            twoColumns and { bodyWidth = 24, minBodyWidth = 24 } or nil)
        if twoColumns then
            firstRowHeight = math.max(firstRowHeight,
                RenderRankUpgradeSetting(parent, db, x + columnWidth + ALIGNED_LAYOUT.columnGap, y, columnWidth))
        end
        y = y - firstRowHeight
        if twoColumns then stateFieldsY = y end
        if rankUpgrade and not twoColumns then y = y - RenderRankUpgradeSetting(parent, db, x, y, sectionWidth) end
        if HasClientCapability("heldBindings") then
            y = y - RenderKeyHeldSetting(parent, x, y, sectionWidth)
        end
        local globalFields = {
            {
                type = "dropdown",
                label = T("settings.pressed_effect", "按压效果"),
                options = BuildMappedOptions(PRESSED_EFFECT_OPTION_KEYS),
                default = "darken",
                get = function() return db.appearance.pressedEffect == "innerGlow" and "innerGlow" or "darken" end,
                set = function(value)
                    db.appearance.pressedEffect = value == "innerGlow" and "innerGlow" or "darken"
                    SyncAllConfigSnapshots(db)
                    if RefreshPreviewOnly then RefreshPreviewOnly("visual") end
                    PatchGlobalConfigSetSetting(
                        "appearance",
                        "pressedEffect",
                        db.appearance.pressedEffect,
                        "settings:pressed-effect"
                    )
                end,
            },
            {
                type = "dropdown",
                label = T("settings.tooltip_mode", "鼠标提示"),
                options = BuildMappedOptions(TOOLTIP_MODE_OPTION_KEYS),
                default = "always",
                get = function() return db.interaction.tooltipMode == "outOfCombat" and "outOfCombat" or "always" end,
                set = function(value)
                    db.interaction.tooltipMode = value == "outOfCombat" and "outOfCombat" or "always"
                    local yab = GetYAB()
                    local factory = yab and yab.SecureFactory
                    if factory and factory.HideRestrictedCombatTooltip then
                        factory:HideRestrictedCombatTooltip()
                    end
                    PatchGlobalConfigSetSetting(
                        "interaction",
                        "tooltipMode",
                        db.interaction.tooltipMode,
                        "settings:tooltip-mode"
                    )
                end,
            },
            {
                type = "dropdown",
                label = T("settings.special_bar_grouping", "特殊动作条分组"),
                options = BuildMappedOptions(SPECIAL_GROUPING_OPTION_KEYS),
                default = "independent",
                get = function()
                    local yab = GetYAB()
                    if yab and yab.NormalizeSpecialGroupingMode then
                        return yab:NormalizeSpecialGroupingMode(db.specialGrouping.mode)
                    end
                    return (db.specialGrouping.mode == "all" or db.specialGrouping.mode == "abilities")
                        and db.specialGrouping.mode
                        or "independent"
                end,
                set = function(value)
                    local yab = GetYAB()
                    local normalized = yab and yab.NormalizeSpecialGroupingMode
                        and yab:NormalizeSpecialGroupingMode(value)
                        or (value == "all" or value == "abilities") and value
                        or "independent"
                    if db.specialGrouping.mode == normalized then return end
                    db.specialGrouping.mode = normalized
                    if normalized == "independent" then
                        if selectedBarId == SpecialSettings.specialGroupId then
                            selectedBarId = "extraAction"
                        end
                    else
                        selectedBarId = SpecialSettings.specialGroupId
                    end
                    local manager = yab and yab.BarManager
                    if manager and manager.RefreshSpecialGroupingRuntime then
                        manager:RefreshSpecialGroupingRuntime(db, "settings:special-group-mode")
                    end
                    PatchGlobalConfigSetSetting(
                        "specialGrouping",
                        "mode",
                        db.specialGrouping.mode,
                        "settings:special-group-mode"
                    )
                    if onRerender then
                        onRerender()
                    end
                end,
            },
        }
        y = RenderFieldBlock(parent, globalFields, x, y, sectionWidth, 1, rankUpgrade and 4 or nil)
        local stateFields = {
            {
                type = "checkbox",
                label = T("settings.show_action_state"),
                default = true,
                get = function() return db.appearance.showActionState ~= false end,
                set = function(value)
                    local enabled = value == true
                    if (db.appearance.showActionState ~= false) == enabled then return end
                    db.appearance.showActionState = enabled
                    SyncAllConfigSnapshots(db)
                    if RefreshPreviewOnly then RefreshPreviewOnly("visual") end
                    PatchGlobalConfigSetSetting("appearance", "showActionState", enabled, "settings:action-state")
                end,
            },
        }
        if HasClientCapability("assistedHighlight") then
            table.insert(stateFields, 1,
                {
                    type = "checkbox",
                    label = T("settings.assisted_highlight"),
                    default = false,
                    get = function() return db.appearance.assistedHighlight == true end,
                    set = function(value)
                        local enabled = value == true
                        if (db.appearance.assistedHighlight == true) == enabled then return end
                        db.appearance.assistedHighlight = enabled
                        local yab = GetYAB()
                        if yab and yab.BarManager and yab.BarManager.SyncAssistedHighlight then
                            yab.BarManager:SyncAssistedHighlight()
                        end
                        PatchGlobalConfigSetSetting("appearance", "assistedHighlight", enabled, "settings:assisted-highlight")
                    end,
                }
            )
        end
        local leftColumnWidth = ALIGNED_LAYOUT.labelWidth + ALIGNED_LAYOUT.labelGap + GetAlignedBodyWidth(sectionWidth)
        local rightColumnWidth = sectionWidth - leftColumnWidth - ALIGNED_LAYOUT.columnGap
        local secondColumn = rightColumnWidth >= ALIGNED_LAYOUT.labelWidth + ALIGNED_LAYOUT.labelGap + 24
        local stateY = RenderFieldBlock(parent, stateFields,
            secondColumn and x + leftColumnWidth + ALIGNED_LAYOUT.columnGap or x,
            secondColumn and stateFieldsY or y, secondColumn and rightColumnWidth or sectionWidth, 1, nil,
            { bodyWidth = 24, minBodyWidth = 24 })
        y = math.min(y, stateY)
        for _, field in ipairs(stateFields) do
            local labelInset = ALIGNED_LAYOUT.labelWidth + ALIGNED_LAYOUT.labelGap
            if field.label == T("settings.assisted_highlight") then
                if field.widget and field.widget.SetHitRectInsets then
                    field.widget:SetHitRectInsets(-labelInset, 0, 0, 0)
                end
                GUI2.AssistedHighlightTooltip:Bind(field.widget, field.label)
                GUI2.AssistedHighlightTooltip:Bind(field.labelRegion, field.label)
            else
                EffectPreview:Bind(field, "state", db, labelInset)
            end
        end
        return math.abs(y) + 4
    end
    if selectedGroup == "display" then
        local gap = COMPACT_TWO_COLUMN_LAYOUT.columnGap
        local twoColumns = sectionWidth >= 516
        local columnWidth = twoColumns and math.floor((sectionWidth - gap) / 2) or sectionWidth
        local left = GUI2:CreateFrame(parent, { width = columnWidth, height = 1, mouse = false })
        local right = GUI2:CreateFrame(parent, { width = columnWidth, height = 1, mouse = false })
        left:SetPoint("TOPLEFT", x, y)
        right:SetPoint("TOPLEFT", x + columnWidth + gap, y)
        local commonTitle = GUI2:CreateText(left, T("settings.common_options"), "font.size.md", "color.text.heading")
        local specialTitle = GUI2:CreateText(right, T("settings.bar_options"), "font.size.md", "color.text.heading")
        commonTitle:SetPoint("TOPLEFT", 0, 0)
        specialTitle:SetPoint("TOPLEFT", 0, 0)
        local leftY, rightY = RenderDisplaySection(left, cfg, barId, 0, -28, columnWidth, right)
        rightY = rightY or -28
        if barId == "questItems" and GetYAB().QuestItems then
            local items = GetYAB().QuestItems
            for _, spec in ipairs({ { "showQuestItems", "quest_items.toggle" }, { "showCampTools", "camp.toggle" } }) do
                local key = spec[1]
                local checkbox = GUI2.Form:CreateCheckbox(right, {
                    label = T(spec[2]), width = columnWidth,
                    get = function() return cfg[key] ~= false end,
                    set = function(value)
                        SetSetting(cfg, key, value == true, "structure")
                        if onRerender then onRerender() end
                    end,
                })
                checkbox:SetPoint("TOPLEFT", 0, rightY)
                rightY = rightY - 32
            end
            if cfg.showQuestItems ~= false then
                if items:HasSnoozedItems() then
                    local restore = CreateButton(right, T("quest_items.restore"), 160, function()
                        items:RestoreSnoozedItems()
                        S.YActionBarModule.SelectBar("questItems", true, "display")
                    end, "default", 28)
                    restore:SetPoint("TOPLEFT", 0, rightY)
                    rightY = rightY - 36
                end
            end
        end
        left:SetHeight(math.abs(leftY) + 4)
        right:SetHeight(math.abs(rightY) + 4)
        if not twoColumns then
            right:ClearAllPoints()
            right:SetPoint("TOPLEFT", x, y - left:GetHeight() - 16)
        end
        return math.abs(y) + (twoColumns and math.max(left:GetHeight(), right:GetHeight()) or left:GetHeight() + right:GetHeight() + 16) + 4
    end

    local layoutFields = {}
    local buttonMaximum = barId == "pet" and 10 or 12
    local buttonDefault = barId == "pet" and 10 or 12
    local layoutButtonCount = SpecialSettings:GetLayoutButtonCount(barId, cfg)
    AddSettingField(layoutFields, barId, "buttons", {
            type = "slider",
            label = T("settings.buttons", "按钮数量"),
            min = 1,
            max = buttonMaximum,
            step = 1,
            default = ClampNumber(cfg.buttons, 1, buttonMaximum, buttonDefault),
            get = function() return ClampNumber(cfg.buttons, 1, buttonMaximum, buttonDefault) end,
            set = function(value)
                local alignmentWasEffective = IsAlignmentEffective(barId, cfg)
                cfg.buttons = ClampNumber(value, 1, buttonMaximum, buttonDefault)
                cfg.rows = ClampNumber(cfg.rows, 1, cfg.buttons, math.min(cfg.buttons, 1))
                SyncSelectedConfigSnapshot("layout")
                if alignmentWasEffective ~= IsAlignmentEffective(barId, cfg) and onRerender then
                    onRerender()
                end
            end,
            onCommit = function()
                PatchConfigSetSettings(
                    barId,
                    {
                        { field = "buttons", value = cfg.buttons },
                        { field = "rows", value = cfg.rows },
                    },
                    "settings:buttons"
                )
            end,
    })
    AddSettingField(layoutFields, barId, "size", {
            type = "slider",
            label = T("settings.size", "尺寸"),
            min = 24,
            max = 64,
            step = 1,
            default = cfg.size or 36,
            get = function() return cfg.size or 36 end,
            set = function(value)
                cfg.size = ClampNumber(value, 24, 64, 36)
                SyncSelectedConfigSnapshot("layout")
            end,
            onCommit = function()
                PatchConfigSetSetting(
                    barId,
                    "size",
                    cfg.size,
                    "settings:size"
                )
            end,
    })
    AddSettingField(layoutFields, barId, "spacing", {
            type = "slider",
            label = T("settings.spacing", "间距"),
            min = -10,
            max = 12,
            step = 1,
            default = cfg.spacing or 4,
            get = function() return cfg.spacing or 4 end,
            set = function(value)
                cfg.spacing = ClampNumber(value, -10, 12, 4)
                SyncSelectedConfigSnapshot("layout")
            end,
            onCommit = function()
                PatchConfigSetSetting(
                    barId,
                    "spacing",
                    cfg.spacing,
                    "settings:spacing"
                )
            end,
    })
    if barId == SpecialSettings.specialGroupId then
        layoutFields[#layoutFields + 1] = {
            type = "dropdown",
            label = T("settings.growth_direction", "生长方向"),
            options = BuildMappedOptions(SpecialSettings.growthDirectionOptionKeys),
            default = "up",
            get = function()
                local yab = GetYAB()
                return yab and yab.NormalizeSpecialGroupGrowthDirection
                    and yab:NormalizeSpecialGroupGrowthDirection(cfg.growthDirection)
                    or cfg.growthDirection
                    or "up"
            end,
            set = function(value)
                local yab = GetYAB()
                local normalized = yab and yab.NormalizeSpecialGroupGrowthDirection
                    and yab:NormalizeSpecialGroupGrowthDirection(value)
                    or value
                    or "up"
                SetSetting(cfg, "growthDirection", normalized, "layout")
            end,
        }
        layoutFields[#layoutFields + 1] = {
            type = "dropdown",
            label = T("settings.group_alignment", "组内对齐"),
            options = BuildMappedOptions(SpecialSettings.groupAlignmentOptionKeys),
            default = "center",
            get = function()
                local yab = GetYAB()
                return yab and yab.NormalizeSpecialGroupAlignment
                    and yab:NormalizeSpecialGroupAlignment(cfg.groupAlignment)
                    or cfg.groupAlignment
                    or "center"
            end,
            set = function(value)
                local yab = GetYAB()
                local normalized = yab and yab.NormalizeSpecialGroupAlignment
                    and yab:NormalizeSpecialGroupAlignment(value)
                    or value
                    or "center"
                SetSetting(cfg, "groupAlignment", normalized, "layout")
            end,
        }
    end
    AddSettingField(layoutFields, barId, "alignment", {
            type = "dropdown",
            label = T("settings.alignment", "末行对齐"),
            options = BuildMappedOptions(ALIGNMENT_OPTION_KEYS),
            default = barId == "stance" and "center" or "left",
            get = function() return cfg.alignment or (barId == "stance" and "center" or "left") end,
            set = function(value) SetSetting(cfg, "alignment", value or "left", "layout") end,
            hidden = function() return not IsAlignmentEffective(barId, cfg) end,
    })
    AddSettingField(layoutFields, barId, "rows", {
            type = "slider",
            label = T("settings.rows", "行数"),
            min = 1,
            max = layoutButtonCount,
            step = 1,
            default = ClampNumber(cfg.rows, 1, layoutButtonCount, 1),
            get = function() return ClampNumber(cfg.rows, 1, layoutButtonCount, 1) end,
            set = function(value)
                local alignmentWasEffective = IsAlignmentEffective(barId, cfg)
                cfg.rows = ClampNumber(value, 1, SpecialSettings:GetLayoutButtonCount(barId, cfg), 1)
                SyncSelectedConfigSnapshot("layout")
                if alignmentWasEffective ~= IsAlignmentEffective(barId, cfg) and onRerender then
                    onRerender()
                end
            end,
            onCommit = function()
                PatchConfigSetSetting(
                    barId,
                    "rows",
                    cfg.rows,
                    "settings:rows"
                )
            end,
    })
    if not SpecialSettings:IsSettingsGroupSupported(barId, "class") then
    AddSettingField(layoutFields, barId, "flyoutDirection", {
        type = "dropdown",
        label = barId == "aspects" and T("settings.pet_utility_direction", "宠物技能展开方向")
            or T("settings.flyout_direction", "展开方向"),
        options = BuildMappedOptions(SpecialSettings.growthDirectionOptionKeys),
        default = "up",
        get = function() return cfg.flyoutDirection or "up" end,
        set = function(value) SetSetting(cfg, "flyoutDirection", value or "up", "layout") end,
    })
    end
    if selectedGroup == "layout" then
        y = RenderFieldBlock(parent, layoutFields, x, y, sectionWidth, 2)
        return math.abs(y) + 4
    end

    local appearanceFields = {}
    AddSettingField(appearanceFields, barId, "skin", {
        type = "custom",
        label = GUI2.IconSkins:Label("title", "皮肤"),
        tooltip = GUI2.IconSkins:Label("help"),
        render = function(host, _, bodyWidth)
            return GUI2.Form:CreateIconSkinControl(host, {
                width = bodyWidth, product = "Flare", native = barId == "extraAction",
                getPopupAnchor = function() return parent end,
                getStyle = function() return cfg end,
                getContext = function() return { groupId = barId } end,
                set = function(patch)
                    cfg.skinId, cfg.skinOptions = patch.skinId, patch.skinOptions
                    SyncSelectedConfigSnapshot("layout")
                    PatchConfigSetSettings(barId, {
                        { field = "skinId", value = cfg.skinId },
                        { field = "skinOptions", value = cfg.skinOptions },
                    }, "settings:skin")
                end,
            })
        end,
    })
    AddSettingField(appearanceFields, barId, "cooldownFade", {
            type = "checkbox",
            label = T("settings.cooldown_fade", "冷却褪色"),
            default = true,
            get = function() return cfg.cooldownFade ~= false end,
            set = function(value) SetSetting(cfg, "cooldownFade", value == true, "visual") end,
    })
    AddSettingField(appearanceFields, barId, "rangeMode", {
            type = "dropdown",
            label = T("settings.range_mode", "超出范围"),
            options = BuildMappedOptions(RANGE_OPTION_KEYS),
            default = "red",
            get = function() return cfg.rangeMode or "red" end,
            set = function(value) SetSetting(cfg, "rangeMode", value or "red", "action") end,
    })
    AddSettingField(appearanceFields, barId, "chargeRecoveryDisplay", {
        type = "custom",
        searchKey = "settings.charge_recovery_display",
        label = T("settings.charge_recovery_display", "充能未耗尽时"),
        render = function(host, _, bodyWidth)
            local control = GUI2.Form:CreateChargeRecoveryControl(host, {
                width = bodyWidth, showLabel = false,
                get = function() return cfg.chargeRecoveryDisplay or "hideSwipeOnly" end,
                set = function(value) SetSetting(cfg, "chargeRecoveryDisplay", value, "visual") end,
                getPreviewStyle = function() return BuildChargeRecoveryPreviewStyle(cfg) end,
            })
            control:SetPresentationLimits(true, (cfg.cooldownTextSize or 12) > 0)
            return control
        end,
    })
    if not SpecialSettings:IsSettingsGroupSupported(barId, "class") then
    AddSettingField(appearanceFields, barId, "aspectActiveStyle", {
            type = "dropdown",
            label = T("settings.aspect_active_style"),
            options = {
                { value = "innerGlow", text = T("aspect_active.inner_glow") },
                { value = "nativeIcon", text = T("aspect_active.native_icon") },
                { value = "dimOthers", text = T("aspect_active.dim_others") },
            },
            default = "innerGlow",
            get = function() return cfg.aspectActiveStyle or "innerGlow" end,
            set = function(value) SetSetting(cfg, "aspectActiveStyle", value or "innerGlow", "visual") end,
    })
    end
    if selectedGroup == "appearance" then
        -- 完整皮肤合并外观项，按实际字段数计算高度。
        return RenderAligned(parent, appearanceFields, x, -4, sectionWidth, 2, APPEARANCE_LAYOUT) + 8
    end

    if selectedGroup == "text" then
        if barId == SpecialSettings.specialGroupId then
            local note = GUI2:CreateText(
                parent,
                T("settings.special_group_text_note", "文字设置仅对支持该文字的组内按钮生效。"),
                "font.size.sm",
                "color.text.secondary",
                "LEFT"
            )
            note:SetPoint("TOPLEFT", x, y)
            note:SetWidth(sectionWidth)
            y = y - 28
        end
        local height = RenderTextSettingsRows(parent, cfg, barId, x, y, sectionWidth)
        return math.abs(y) + height + 4
    end

    return math.abs(y) + 4
end

local SETTINGS_GROUPS = {
    { id = "display", label = "settings.section.display", fallback = "显示", icon = "eye" },
    { id = "layout", label = "settings.section.layout", fallback = "布局", icon = "panels-top-left" },
    { id = "appearance", label = "settings.section.appearance", fallback = "外观", icon = "paintbrush" },
    { id = "text", label = "settings.section.text", fallback = "文本", icon = "text-initial" },
    { id = "global", label = "settings.section.global", fallback = "全局", icon = "settings" },
    { id = "class", label = "class_tools.tab", fallback = "职业条", icon = "user" },
}

local function RenderSettingsBody(parent, db, onRerender)
    local barId = EnsureSelectedBar(db)
    local cfg = GetBarConfig(db, barId)
    if not cfg then return 0 end
    SyncConfigSnapshot(db, barId)

    local bodyWidth = math.max(parent:GetWidth() or 700, 360)
    local body = GUI2:CreateFrame(parent)
    body:SetPoint("TOPLEFT", 0, 0)
    body:SetWidth(bodyWidth)

    local visibleGroups = {}
    for _, group in ipairs(SETTINGS_GROUPS) do
        if SpecialSettings:IsSettingsGroupSupported(barId, group.id) then
            visibleGroups[#visibleGroups + 1] = group
        end
    end
    if not SpecialSettings:IsSettingsGroupSupported(barId, selectedGroup) then
        selectedGroup = visibleGroups[1] and visibleGroups[1].id or "display"
    end

    local tabItems = {}
    for _, group in ipairs(visibleGroups) do
        tabItems[#tabItems + 1] = {
            text = T(group.label, group.fallback),
            value = group.id,
        }
    end

    local tabs = GUI2.Form:CreateUnderlineTabs(body, {
        width = bodyWidth,
        value = selectedGroup,
        fontSizeKey = "font.size.lg",
        showBaseline = true,
        baselineHeight = 1,
        baselineColorKey = "color.border.subtle",
        indicatorHeight = 2,
        indicatorColorKey = "color.text.accent",
        items = tabItems,
        onChange = function(_, value)
            selectedGroup = value or selectedGroup
            if onRerender then onRerender() end
        end,
    })
    tabs:SetPoint("TOPLEFT", 0, 0)

    local bodyHeight = SETTINGS_BODY_FIXED_HEIGHT
    local panelHeight = math.max(bodyHeight - SETTINGS_TAB_HEIGHT, 120)
    local panel = GUI2:CreateFrame(body, {
        width = bodyWidth,
        height = panelHeight,
    })
    panel:SetPoint("TOPLEFT", 0, -SETTINGS_TAB_HEIGHT)

    local scroll = GUI2:CreateScrollFrame(panel, {
        template = "UIPanelScrollFrameTemplate",
        childWidth = math.max(bodyWidth - 28, 320),
        childHeight = panelHeight,
    })
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 0)
    local scrollBar = scroll.ScrollBar or scroll.gui2ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -8)
        scrollBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 8)
    end
    local scrollChild = scroll.child or scroll.scrollChild
    local contentHeight = RenderCurrentOptions(scrollChild or panel, cfg, math.max(bodyWidth - 28, 320), onRerender, db)
    if scrollChild then
        scrollChild:SetWidth(math.max(bodyWidth - 28, 320))
        scrollChild:SetHeight(math.max(contentHeight, panelHeight))
    end
    local needsScroll = contentHeight > panelHeight
    if scrollBar then
        if needsScroll then
            scrollBar:Show()
            if scrollBar.UpdateVisualThumb then scrollBar:UpdateVisualThumb() end
        else
            if scrollBar.visualThumb then scrollBar.visualThumb:Hide() end
            scrollBar:Hide()
        end
    end
    scroll:EnableMouseWheel(needsScroll)
    if not needsScroll and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end

    body:SetHeight(bodyHeight)
    return bodyHeight
end

local function Render(parent)
    local yab = GetYAB()
    local db = GetDB()
    if not yab or not db then
        local text = GUI2:CreateText(parent, T("settings.not_loaded", "YActionBar 尚未加载。"), GUI2.Fonts.size_normal)
        text:SetPoint("TOPLEFT", 20, -20)
        parent:SetHeight(80)
        return
    end

    local controller, yielded = yab.GetYieldController and yab:GetYieldController()
    if not yielded and yab.ConflictGuard and type(yab.ConflictGuard.Check) == "function" then
        local conflict = yab.ConflictGuard:Check()
        if type(conflict) == "table" and conflict.blocked == true
            and conflict.status == "active" then
            controller, yielded = conflict.controller, true
        end
    end
    if yielded then
        if CleanupPreviewEditor then CleanupPreviewEditor(parent, true) end
        S:RenderConfig(parent, {
            { type = "text", label = S:FormatYieldNotice("actionbar", controller), colorKey = "color.text.primary" },
        })
        return
    end

    db.bars = db.bars or {}
    db.specialBars = db.specialBars or {}
    EnsureSelectedBar(db)

    if not parent.yabPreviewEditorHideHooked and parent.HookScript then
        parent.yabPreviewEditorHideHooked = true
        parent:HookScript("OnHide", function(frame)
            CleanupPreviewEditor(frame)
            frame.yabPreviewEditorNeedsRerender = true
        end)
        parent:HookScript("OnShow", function(frame)
            if not frame.yabPreviewEditorNeedsRerender or frame.yabPreviewEditorRendering then
                return
            end
            frame.yabPreviewEditorNeedsRerender = nil
            frame.yabPreviewEditorRendering = true
            if S.ClearConfig then
                S:ClearConfig(frame)
            end
            Render(frame)
            frame.yabPreviewEditorRendering = nil
        end)
    end
    parent.yabPreviewEditorNeedsRerender = nil

    local content = GUI2:CreateFrame(parent)
    content:SetPoint("TOPLEFT", 0, 0)
    local viewportWidth = parent:GetWidth() or 820
    if viewportWidth <= 0 then viewportWidth = 820 end
    local contentWidth = math.max(viewportWidth - 28, 360)
    local innerX = 20
    local innerRight = 22
    local innerWidth = math.max(contentWidth - innerX - innerRight, 320)
    content:SetWidth(contentWidth)

    local title = GUI2:CreateText(
        content,
        CelestialSeries
            and CelestialSeries:GetTitle(
                "yactionbar",
                T("product.brand_suffix", "Action Bar")
            )
            or T("settings.title", "Flare Action Bar"),
        "font.size.title",
        "color.text.heading"
    )
    title:SetPoint("TOPLEFT", innerX, -PAGE_TITLE_TOP)

    local function Rerender()
        if not S.ClearConfig then return end
        CleanupPreviewEditor(nil, true)
        S:ClearConfig(parent)
        Render(parent)
    end

    local selectorY = -PAGE_HEADER_TOP
    local selectorWidth = 190
    local _, selectorHeight = RenderBarSelector(content, db, innerX, selectorY, selectorWidth, function()
        Rerender()
    end)

    local keybind = GUI2.Form:CreateButton(content, {
        text = T("settings.keybind", "键位设置"),
        width = HEADER_KEYBIND_WIDTH,
        height = HEADER_CONTROL_HEIGHT,
        tone = "success",
        microIcon = "keyboard",
        iconSize = 16,
        contentAlign = "center",
        onClick = function()
            CloseTextSettingsPopover()
            local current = GetYAB()
            if current and current.EnterBindMode then
                local bindBarId = selectedBarId == SpecialSettings.specialGroupId and "extraAction" or selectedBarId
                current:EnterBindMode("settings", bindBarId)
            end
        end,
    })
    if selectedBarId == "questItems" then keybind:SetDisabled(true) end
    keybind:SetPoint("TOPRIGHT", content, "TOPRIGHT", -innerRight, selectorY)
    if S.Search then S.Search:Bind({ searchKey = "settings.keybind" }, keybind) end

    local configSets = GUI2.Form:CreateButton(content, {
        text = T("settings.config_sets", "方案"),
        width = HEADER_CONFIG_SET_WIDTH,
        height = HEADER_CONTROL_HEIGHT,
        microIcon = "save",
        iconSize = 16,
        contentAlign = "center",
        onClick = function()
            CloseTextSettingsPopover()
            local picker = S.ConfigSetPicker
            if picker and picker.Open then
                picker:Open(parent, {
                    providerId = "yactionbar",
                    ownerFrame = parent,
                    title = CT(
                        "settings.config_sets.title",
                        "配置方案"
                    ) .. " - " .. T("settings.title", "动作条"),
                    onApplied = function(result)
                        local providerResult = result and result.result
                        if providerResult and providerResult.reloadRequired and S.ShowReload then
                            S:ShowReload()
                        end
                    end,
                })
            end
        end,
    })
    configSets:SetPoint("RIGHT", keybind, "LEFT", -HEADER_CONTROL_GAP, 0)
    if S.Search then S.Search:Bind({ searchKey = "settings.config_sets" }, configSets) end

    local previewGap = 2
    local previewY = selectorY - selectorHeight - previewGap
    local previewWidth = math.min(630, math.max(innerWidth, 320))
    local previewX = innerX
    local _, previewHeight = RenderPreviewEditor(content, db, selectedBarId, previewX, previewY, previewWidth, Rerender)

    local body = GUI2:CreateFrame(content)
    body:SetPoint("TOPLEFT", innerX, previewY - previewHeight - 14)
    body:SetWidth(innerWidth)
    local bodyHeight = RenderSettingsBody(body, db, Rerender)
    body:SetHeight(bodyHeight)

    local contentHeight = math.abs(previewY - previewHeight - 14) + bodyHeight + 20
    content:SetHeight(contentHeight)
    parent:SetHeight(contentHeight)
    if S.RefreshCurrentModuleScroll then
        S:RefreshCurrentModuleScroll(false)
    end
end

local function RerenderSettingsModule()
    local yab = GetYAB()
    local moduleId = yab and yab.SETTINGS_ENTRY or "yactionbar.settings"
    local module = S.modulesById and S.modulesById[moduleId]
    if not (module and module.frame and module.frame.IsShown and module.frame:IsShown()) then
        return false
    end
    if S.ClearConfig then
        S:ClearConfig(module.frame)
    end
    Render(module.frame)
    return true
end

S.YActionBarModule = S.YActionBarModule or {}

function S.YActionBarModule:RegisterTextStyle()
    return RegisterTextStyle()
end
S.YActionBarModule:RegisterTextStyle()

function S.YActionBarModule:HideEffectPreview()
    EffectPreview:Hide()
end

function S.YActionBarModule:RefreshFromConfigSet(_, providerId)
    if providerId ~= "yactionbar" then return false end
    return RerenderSettingsModule()
end

function S.YActionBarModule.SelectBar(barId, rerender, group)
    local ok = SelectSettingsBar(GetDB(), barId)
    if ok and (group == "layout" or group == "appearance" or group == "display" or group == "text" or group == "class") then
        selectedGroup = group
    end
    if ok and rerender then
        RerenderSettingsModule()
    end
    return ok
end

if YUI.Event and YUI.Event.On then
    YUI.Event:On(
        "YUI_CONFIG_SET_ACTIVE_CHANGED",
        "RefreshFromConfigSet",
        S.YActionBarModule,
        {
            moduleId = "settings.yactionbar",
            traceName = "YActionBarSettings:RefreshFromConfigSet",
        }
    )
end

S:RegisterModule("Flare Action Bar", ACTION_BAR_NAV_ICON, Render, {
    id = "yactionbar.settings",
    product = "yactionbar",
    scope = "yactionbar",
    titleKey = "settings.title",
    titleNamespace = "YActionBar",
    navTitleKey = "settings.nav.action_bar",
    navIconCrop = false,
    navIconSize = CelestialSeries and CelestialSeries.NAV_ICON_SIZE or 26,
    navToggle = { moduleId = "yactionbar" },
})

if S.Search then
    S.Search:RegisterRoute("yactionbar.settings", function(group)
        if group == "global" or group == "layout" or group == "appearance" or group == "display" or group == "text" then
            selectedGroup = group
        end
    end)
end

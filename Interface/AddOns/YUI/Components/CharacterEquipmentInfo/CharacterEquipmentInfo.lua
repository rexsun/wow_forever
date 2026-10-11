local ADDON_NAME, addonTable = ...
local YUI = _G.YUI or addonTable

if not YUI or not (YUI.IsRetail or YUI.IsForever or YUI.IsWrath) then return end

local Components = YUI.Components
local PRODUCT_ID = YUI.GetAddonProductId and YUI:GetAddonProductId(ADDON_NAME, "suite")
    or YUI.ProductId or "suite"
local GUI2 = YUI.GUI2
local Event = YUI.Event
local PaperDoll = YUI.API and YUI.API.PaperDoll
local Item = YUI.API and YUI.API.Item
local UnitAPI = YUI.API and YUI.API.Unit
local TalentAPI = YUI.API and YUI.API.Talent
local Security = YUI.API and YUI.API.Security
local Appearance = GUI2 and GUI2.WindowAppearance
local LocaleManager = YUI.Locale
local Locale = LocaleManager and LocaleManager:Get("CharacterEquipmentInfo") or {}
local Unpack = unpack or table.unpack

if not Components or not GUI2 or not PaperDoll then return end

local FEATURE_KEY = "CharacterEquipmentInfo"
local CONFIG_KEY = "CharacterEquipmentInfo_Config"
local CARD_WIDTH = 330
local DEFAULT_FONT = GUI2.GetFont and GUI2:GetFont("font.family.body") or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local DEFAULT_FONT_SIZE = 13
local TEXT_CARD_WIDTH = 360
local CARD_GAP = 8
local CARD_INSET = 12
local CARD_HEADER_HEIGHT = 40
local CARD_BOTTOM_INSET = 8
local CARD_SECTION_GAP = 6
local ROW_HEIGHT = 21
local STAT_ROW_HEIGHT = 23
local STAT_COLUMN_GAP = 10
local STAT_VALUE_WIDTH = 48
local STAT_COMPARISON_MIN_FONT_SIZE = 8
local STAT_LABEL_PADDING = 2
local STAT_CONTENT_GAP = 4
local HEADER_TEXT_TOP = -4
local HEADER_TEXT_HEIGHT = 20
local COLUMN_GAP = 2
local HEADER_TEXT_SIZE = "font.size.lg"
local BODY_TEXT_SIZE = "font.size.md"
local SLOT_TEXT_MIN_WIDTH = 28
local SLOT_BADGE_PADDING_X = 2
local SLOT_BADGE_HEIGHT = 20
local SLOT_TEXT_OPTICAL_OFFSET_X = 1
local ITEM_LEVEL_FALLBACK_WIDTH = 24
local ITEM_LEVEL_TEXT_OPTICAL_OFFSET_X = 2
local STAT_BADGE_SIZE = 9
local STAT_BADGE_SOLID_SIZE = 7
local STAT_BADGE_GAP = 2
local STAT_BADGE_COUNT = 4
local STAT_BADGE_WIDTH = STAT_BADGE_SIZE * STAT_BADGE_COUNT
    + STAT_BADGE_GAP * (STAT_BADGE_COUNT - 1)
local PIXEL_SIZE = 1

-- 修改缺失附魔提示素材或颜色时，只需要调整此表。
local MISSING_ENHANCEMENT_ICON = {
    atlas = "QuestLegendary",
    size = 14,
    color = { 1.00, 0.25, 0.25, 1.00 },
}

local CRAFTED_TRACK_COLOR = { 1.00, 0.42, 0.78, 1.00 }
local NO_TRACK_COLOR = { 0.72, 0.72, 0.72, 1.00 }
local PENDING_TRACK_COLOR = { 0.53, 0.53, 0.53, 1.00 }
local EMPTY_TRACK_COLOR = { 0.44, 0.44, 0.44, 1.00 }

local SECONDARY_STAT_IDS = (YUI.IsForever or YUI.IsWrath) and { "crit", "haste", "hit", "expertise" }
    or { "crit", "haste", "mastery", "versatility" }
local SUMMARY_STAT_IDS = YUI.IsForever and { "primary_summary", "power_summary", "crit", "haste" } or SECONDARY_STAT_IDS
local ZHCN_SLOT_TEXT_OPTICAL_OFFSETS = {
    head = true,
    neck = true,
    shoulder = true,
    back = true,
    chest = true,
    wrist = true,
    hands = true,
    waist = true,
    legs = true,
    feet = true,
    finger1 = true,
    finger2 = true,
}
local SECONDARY_STAT_COLORS = {
    str = { 1.00, 0.20, 0.20 },
    agi = { 0.20, 1.00, 0.20 },
    int = { 0.20, 0.60, 1.00 },
    spell_power = { 0.80, 0.50, 1.00 },
    attack_power = { 1.00, 0.20, 0.20 },
    ranged_attack_power = { 1.00, 0.20, 0.20 },
    primary_summary = { 1, 1, 1 },
    power_summary = { 1, 1, 1 },
    crit = { 1.00, 0.50, 0.00 },
    haste = { 1.00, 1.00, 0.00 },
    hit = { 0.80, 0.40, 0.80 },
    expertise = { 0.53, 0.53, 0.93 },
    mastery = { 0.80, 0.40, 0.80 },
    versatility = { 0.53, 0.53, 0.93 },
}
local DEFAULTS = {
    showSummary = true,
    slotFlyout = true,
    slotItemLevel = true,
    slotEnchant = true,
    slotGems = true,
    slotDurability = true,
    slotColorMode = "quality",
    slotLevelOutline = "outlineShadow",
    slotEnchantOutline = "outlineShadow",
    slotDurabilityOutline = "outlineShadow",
    slotColor = { r = 1, g = 1, b = 1 },
    showSecondaryStats = true,
    equipmentSecondaryStatStyle = "blocks",
    themeStyle = "auto",
}

local SLOT_DEFINITIONS = PaperDoll.GetSlotDefinitions()
local STAT_DEFINITIONS = PaperDoll.GetStatDefinitions()

local runtime = {
    enabled = false,
    eventOwner = {},
    eventAttached = false,
    refreshPending = false,
    generation = 0,
    hookedFrames = setmetatable({}, { __mode = "k" }),
    playerCard = nil,
    inspectCard = nil,
}

local function T(key, fallback)
    local value = Locale[key]
    if value and value ~= "" then return value end
    return fallback or key
end

local function GetCurrentLocale()
    if LocaleManager and type(LocaleManager.Current) == "function" then
        local ok, locale = pcall(LocaleManager.Current, LocaleManager)
        if ok and type(locale) == "string" then return locale end
    end
    if type(GetLocale) == "function" then
        local ok, locale = pcall(GetLocale)
        if ok and type(locale) == "string" then return locale end
    end
    return "enUS"
end

local function GetSlotTextOpticalOffset(definition)
    if GetCurrentLocale() == "zhCN"
        and definition
        and ZHCN_SLOT_TEXT_OPTICAL_OFFSETS[definition.key]
    then
        return SLOT_TEXT_OPTICAL_OFFSET_X
    end
    return 0
end

local function IsSecret(value)
    if Security and type(Security.IsSecretValue) == "function" then
        local ok, secret = pcall(Security.IsSecretValue, value)
        if ok then return secret == true end
    end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if ok then return secret == true end
    end
    return false
end

local function NormalizeFontSize(value)
    value = tonumber(value)
    if not value or value ~= value or value == 0 then return DEFAULT_FONT_SIZE end
    return math.max(10, math.min(16, math.floor(value)))
end

local function NormalizeFont(value)
    return type(value) == "string" and value ~= "" and value ~= "auto" and value or DEFAULT_FONT
end

local function GetDB()
    local db = DEFAULTS
    if Components and type(Components.EnsureConfig) == "function" then
        db = Components:EnsureConfig(CONFIG_KEY, DEFAULTS, PRODUCT_ID) or DEFAULTS
    end
    db.textFont, db.numberFont = NormalizeFont(db.textFont), NormalizeFont(db.numberFont)
    db.textFontSize, db.numberFontSize = NormalizeFontSize(db.textFontSize), NormalizeFontSize(db.numberFontSize)
    return db
end

local function NormalizeThemeStyle(value)
    if value == "native" or value == "dark" then return value end
    return "auto"
end

local function GetThemeStyle()
    return NormalizeThemeStyle(GetDB().themeStyle)
end

local function NormalizeEquipmentSecondaryStatStyle(value)
    if value == "none" or value == "blocks" or value == "text" then return value end
    return "blocks"
end

local function GetEquipmentSecondaryStatStyle(db)
    if YUI.IsForever then return "none" end
    db = db or GetDB()
    return NormalizeEquipmentSecondaryStatStyle(db.equipmentSecondaryStatStyle)
end

local function IsShown(frame)
    return frame and type(frame.IsShown) == "function" and frame:IsShown() == true
end

local function SafeUnitName(unit)
    if UnitAPI and type(UnitAPI.GetDisplayNameInfo) == "function" then
        local ok, info = pcall(UnitAPI.GetDisplayNameInfo, unit)
        if ok and type(info) == "table" then
            local name = info.displayName or info.name
            if not IsSecret(name) then
                return name, info.classToken
            end
        end
    end

    if type(UnitName) == "function" then
        local ok, name = pcall(UnitName, unit)
        if ok and not IsSecret(name) then return name end
    end

    return nil
end

local function SafeClass(unit, classToken)
    if type(classToken) == "string" and not IsSecret(classToken) then return classToken end
    if UnitAPI and type(UnitAPI.UnitClass) == "function" then
        local ok, _, token = pcall(UnitAPI.UnitClass, unit)
        if ok and type(token) == "string" and not IsSecret(token) then return token end
    end
    if type(UnitClass) == "function" then
        local ok, _, token = pcall(UnitClass, unit)
        if ok and type(token) == "string" and not IsSecret(token) then return token end
    end
end

local function ReadSpecName(unit)
    local specID
    if unit == "player" then
        local index = TalentAPI and type(TalentAPI.GetSpecialization) == "function"
            and TalentAPI.GetSpecialization()
        if index and not IsSecret(index)
            and TalentAPI and type(TalentAPI.GetSpecializationInfo) == "function"
        then
            specID = select(1, TalentAPI.GetSpecializationInfo(index))
        end
    elseif type(GetInspectSpecialization) == "function" then
        local ok, value = pcall(GetInspectSpecialization, unit)
        if ok and not IsSecret(value) then specID = value end
    end

    if specID and not IsSecret(specID)
        and TalentAPI and type(TalentAPI.GetSpecializationInfoByID) == "function"
    then
        local ok, _, name = pcall(TalentAPI.GetSpecializationInfoByID, specID)
        if ok and not IsSecret(name) then return name end
    end

    return nil
end

local function ReadIdentity(unit)
    local name, classToken = SafeUnitName(unit)
    classToken = SafeClass(unit, classToken)

    local level
    if type(UnitLevel) == "function" then
        local ok, value = pcall(UnitLevel, unit)
        if ok then level = value end
    end
    local levelSecret = IsSecret(level)
    if levelSecret then level = nil end

    local classColor = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    return {
        name = name or T("value.unknown", "Unknown"),
        classToken = classToken,
        classColor = classColor,
        level = level,
        levelSecret = levelSecret,
        specName = ReadSpecName(unit),
    }
end

local function ResolveOutlineFlags(flags)
    local values = {}
    if type(flags) == "string" then
        for flag in flags:gmatch("[^,%s]+") do
            local upper = flag:upper()
            if upper ~= "OUTLINE" and upper ~= "THICKOUTLINE" then
                values[#values + 1] = flag
            end
        end
    end
    values[#values + 1] = "OUTLINE"
    return table.concat(values, ",")
end

local function ApplyTextEffects(fontString)
    if not fontString then return end
    if type(fontString.GetFont) == "function" and type(fontString.SetFont) == "function" then
        local ok, path, size, flags = pcall(fontString.GetFont, fontString)
        if ok and type(path) == "string" and type(size) == "number" then
            pcall(fontString.SetFont, fontString, path, size, ResolveOutlineFlags(flags))
        end
    end
    if type(fontString.SetShadowColor) == "function" then
        pcall(fontString.SetShadowColor, fontString, 0, 0, 0, 1)
    end
    if type(fontString.SetShadowOffset) == "function" then
        pcall(fontString.SetShadowOffset, fontString, 1, -1)
    end
end

local function CreateText(parent, text, size, color, justify, role)
    local fontString = GUI2:CreateText(
        parent,
        text or "",
        size or "font.size.sm",
        color or "color.text.primary",
        justify or "LEFT"
    )
    ApplyTextEffects(fontString)
    fontString._equipmentFontRole = role or "text"
    fontString._equipmentDefaultPath, fontString._equipmentDefaultSize, fontString._equipmentDefaultFlags = fontString:GetFont()
    return fontString
end

local function SetTextColorKey(fontString, key)
    if fontString and type(GUI2.SetTextColorKey) == "function" then
        GUI2:SetTextColorKey(fontString, key)
    end
end

local function HideTooltip()
    if type(YUI.HideGameTooltip) == "function" then
        YUI.HideGameTooltip()
    elseif GameTooltip and type(GameTooltip.Hide) == "function" then
        GameTooltip:Hide()
    end
end

local function ShowTooltip(row, link)
    if not row or not link or not GameTooltip then return end
    if type(GameTooltip.SetOwner) ~= "function" or type(GameTooltip.SetHyperlink) ~= "function" then
        return
    end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    if ok and type(GameTooltip.Show) == "function" then
        GameTooltip:Show()
    end
end

local function ShowEnhancementTooltip(alert)
    local enhancement = alert and alert.enhancement
    if not enhancement or not enhancement.missing or not GameTooltip then return end
    if type(GameTooltip.SetOwner) ~= "function" or type(GameTooltip.SetText) ~= "function" then
        return
    end

    GameTooltip:SetOwner(alert, "ANCHOR_RIGHT")
    GameTooltip:SetText(T("item.enhancement.missing_title", "缺失强化"))
    if enhancement.missingEnchant and type(GameTooltip.AddLine) == "function" then
        GameTooltip:AddLine(T("item.enhancement.missing_enchant", "缺少附魔"), 1, 0.25, 0.25)
    end
    if type(enhancement.emptySockets) == "number"
        and enhancement.emptySockets > 0
        and type(GameTooltip.AddLine) == "function"
    then
        GameTooltip:AddLine(string.format(
            T("item.enhancement.empty_sockets", "空宝石槽：%d"),
            enhancement.emptySockets
        ), 1, 0.25, 0.25)
    end
    if type(enhancement.addableSockets) == "number"
        and enhancement.addableSockets > 0
        and type(GameTooltip.AddLine) == "function"
    then
        GameTooltip:AddLine(string.format(
            T("item.enhancement.addable_sockets", "可添加宝石槽：%d"),
            enhancement.addableSockets
        ), 1, 0.75, 0.25)
    end
    if type(GameTooltip.Show) == "function" then GameTooltip:Show() end
end

local function ShowSecondaryStatsTooltip(row)
    if not row or not GameTooltip
        or type(GameTooltip.SetOwner) ~= "function"
        or type(GameTooltip.SetText) ~= "function"
    then
        return
    end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(T(YUI.IsForever and "stats.summary_title" or "stats.equipment_title", "装备属性"))
    if type(GameTooltip.AddLine) == "function" then
        GameTooltip:AddLine(T(
            YUI.IsForever and "stats.summary_tooltip" or "stats.equipment_tooltip",
            "根据当前可读取的装备、宝石和附魔汇总；不包含天赋、种族和临时效果。"
        ), 1, 1, 1, true)
        if row._comparisonVisible then
            GameTooltip:AddLine(T(
                "stats.comparison_tooltip",
                "括号表示与自己装备副属性数值的差异。"
            ), 0.72, 0.72, 0.72, true)
        end
    end
    if type(GameTooltip.Show) == "function" then GameTooltip:Show() end
end

local function GetRenderedTextWidth(fontString, fallback)
    if not fontString then return fallback or 0 end
    local getWidth = fontString.GetUnboundedStringWidth or fontString.GetStringWidth
    if type(getWidth) == "function" then
        local ok, width = pcall(getWidth, fontString)
        if ok and type(width) == "number" and width >= 0 then
            return math.ceil(width)
        end
    end
    return fallback or 0
end

local function CaptureComparisonFont(row)
    local comparison = row and row.comparison
    if not comparison or type(comparison.GetFont) ~= "function" then return end
    local ok, path, size, flags = pcall(comparison.GetFont, comparison)
    if ok and type(path) == "string" and type(size) == "number" then
        row._comparisonBaseFontPath = path
        row._comparisonBaseFontSize = size
        row._comparisonBaseFontFlags = flags
    end
end

local function RestoreComparisonFont(row)
    local comparison = row and row.comparison
    if not comparison or type(comparison.SetFont) ~= "function"
        or type(row._comparisonBaseFontPath) ~= "string"
        or type(row._comparisonBaseFontSize) ~= "number"
    then
        return
    end
    pcall(
        comparison.SetFont,
        comparison,
        row._comparisonBaseFontPath,
        row._comparisonBaseFontSize,
        row._comparisonBaseFontFlags
    )
end

local function FitComparisonFont(row, maxWidth)
    local comparison = row and row.comparison
    if not comparison then return end
    maxWidth = math.max(1, math.floor(maxWidth or 1))
    row._comparisonMaxWidth = maxWidth
    RestoreComparisonFont(row)

    local baseSize = row._comparisonBaseFontSize
    local renderedWidth = GetRenderedTextWidth(comparison, maxWidth)
    local fontSize = baseSize
    if type(baseSize) == "number" and renderedWidth > maxWidth then
        fontSize = math.max(
            STAT_COMPARISON_MIN_FONT_SIZE,
            math.floor(baseSize * maxWidth / renderedWidth)
        )
        if fontSize < baseSize and type(comparison.SetFont) == "function" then
            pcall(
                comparison.SetFont,
                comparison,
                row._comparisonBaseFontPath,
                fontSize,
                row._comparisonBaseFontFlags
            )
        end
    end
    row._comparisonFontSize = fontSize
    comparison:SetWidth(maxWidth)
end

local function GetPixelMetric(region, desiredPixels)
    if type(GUI2.GetPixelSize) == "function" then
        local size = GUI2:GetPixelSize(region, desiredPixels, desiredPixels)
        if type(size) == "number" and size > 0 then return size end
    end
    return desiredPixels
end

local function ApplyPixelPolicy(texture)
    if texture and type(GUI2.ApplyTexturePixelPolicy) == "function" then
        GUI2:ApplyTexturePixelPolicy(texture)
    end
end

local function UpdateSlotTextWidth(card)
    if not card then return end
    local width = SLOT_TEXT_MIN_WIDTH
    for _, row in ipairs(card.equipmentRows or {}) do
        width = math.max(width, GetRenderedTextWidth(row.slotText, SLOT_TEXT_MIN_WIDTH))
    end
    local firstRow = card.equipmentRows and card.equipmentRows[1]
    local padding = GetPixelMetric(firstRow, SLOT_BADGE_PADDING_X)
    local badgeWidth = width + (padding * 2)
    for _, row in ipairs(card.equipmentRows or {}) do
        row.slotBadge:SetWidth(badgeWidth)
    end
    card.slotTextWidth = width
    card.slotBadgeWidth = badgeWidth
end

local RefreshEquipmentTextLayout
local LayoutCard
local SyncCardWidths

local function ApplyCardFonts(card, rowHeight)
    local db = GetDB()
    local textFont, numberFont = NormalizeFont(db.textFont), NormalizeFont(db.numberFont)
    local textSize, numberSize = NormalizeFontSize(db.textFontSize), NormalizeFontSize(db.numberFontSize)
    if card._fontRowHeight == rowHeight and card._textFont == textFont
        and card._numberFont == numberFont and card._textSize == textSize and card._numberSize == numberSize
    then return end
    card._fontRowHeight, card._textFont, card._numberFont = rowHeight, textFont, numberFont
    card._textSize, card._numberSize = textSize, numberSize
    for _, fontString in ipairs(card.themeTexts) do
        local numeric = fontString._equipmentFontRole == "number"
        local path = numeric and numberFont or textFont
        local size = numeric and numberSize or textSize
        local skinPath = fontString._equipmentSkinPath or fontString._equipmentDefaultPath
        local flags = fontString._equipmentSkinFlags or fontString._equipmentDefaultFlags
        local limit = fontString._equipmentHeightLimit or (rowHeight - 4)
        size = math.max(1, math.min(size, limit))
        local ok, applied = pcall(fontString.SetFont, fontString, path, size, flags)
        if not ok or applied == false then fontString:SetFont(skinPath, size, flags) end
    end
    for _, row in pairs(card.statRows) do CaptureComparisonFont(row) end
    UpdateSlotTextWidth(card)
end

local function ApplyCardTheme(card, context)
    if not card or not Appearance or type(Appearance.ApplyFont) ~= "function" then return end
    card.contentInset = YUI.IsForever and context and context.source == "native" and 20 or CARD_INSET
    for _, fontString in ipairs(card.themeTexts or {}) do
        -- 先恢复创建时字体，避免外观 provider 将上次的用户覆盖当成默认值。
        fontString:SetFont(fontString._equipmentDefaultPath, fontString._equipmentDefaultSize, fontString._equipmentDefaultFlags)
        Appearance:ApplyFont(fontString, context)
        ApplyTextEffects(fontString)
        fontString._equipmentSkinPath, fontString._equipmentSkinSize, fontString._equipmentSkinFlags = fontString:GetFont()
    end
    card._fontRowHeight = nil
    if LayoutCard then LayoutCard(card, card.kind == "inspect") end
    if SyncCardWidths then SyncCardWidths() end
end

local function GetContentParent(card)
    return card.content or card
end

local function CreateSectionLine(card, paintKey)
    if not GUI2 or type(GUI2.CreateTexture) ~= "function" then return nil end

    local line = GUI2:CreateTexture(card, { layer = "ARTWORK", subLevel = 7 })
    if type(GUI2.ApplyTexturePixelPolicy) == "function" then
        pcall(GUI2.ApplyTexturePixelPolicy, GUI2, line)
    end
    if type(GUI2.SetTexturePaintKey) == "function" then
        GUI2:SetTexturePaintKey(line, paintKey or "color.border.subtle")
    end
    if type(line.SetHeight) == "function" then
        local pixel = type(GUI2.GetPixelSize) == "function"
            and GUI2:GetPixelSize(line, 1, 1) or PIXEL_SIZE
        line:SetHeight(pixel)
    end
    return line
end

local function CreateEquipmentRow(card, definition)
    local row = GUI2:CreateFrame(GetContentParent(card), {
        width = CARD_WIDTH - 24,
        height = ROW_HEIGHT,
    })
    row:EnableMouse(true)
    row.columnGap = GetPixelMetric(row, COLUMN_GAP)
    row.slotBadgePaddingX = GetPixelMetric(row, SLOT_BADGE_PADDING_X)
    row.slotTextOpticalOffsetX = GetPixelMetric(row, GetSlotTextOpticalOffset(definition))
    row.itemLevelTextOpticalOffsetX = GetPixelMetric(row, ITEM_LEVEL_TEXT_OPTICAL_OFFSET_X)

    row.slotBadge = GUI2:CreateFrame(row, {
        width = SLOT_TEXT_MIN_WIDTH + (row.slotBadgePaddingX * 2),
        height = GetPixelMetric(row, SLOT_BADGE_HEIGHT),
    })
    row.slotBadge:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.slotBadge.background = GUI2:CreateTexture(row.slotBadge, { layer = "BACKGROUND", subLevel = 1 })
    row.slotBadge.background:SetPoint("TOPLEFT", row.slotBadge, "TOPLEFT", 0, 0)
    row.slotBadge.background:SetPoint("BOTTOMRIGHT", row.slotBadge, "BOTTOMRIGHT", 0, 0)
    ApplyPixelPolicy(row.slotBadge.background)
    row.slotBadge.borders = {}
    local borderPixel = GetPixelMetric(row.slotBadge, 1)
    local borderPoints = {
        { "TOPLEFT", "TOPRIGHT", "height" },
        { "BOTTOMLEFT", "BOTTOMRIGHT", "height" },
        { "TOPLEFT", "BOTTOMLEFT", "width" },
        { "TOPRIGHT", "BOTTOMRIGHT", "width" },
    }
    for index, points in ipairs(borderPoints) do
        local border = GUI2:CreateTexture(row.slotBadge, { layer = "OVERLAY", subLevel = 2 })
        ApplyPixelPolicy(border)
        border:SetPoint(points[1], row.slotBadge, points[1], 0, 0)
        border:SetPoint(points[2], row.slotBadge, points[2], 0, 0)
        if points[3] == "height" then
            border:SetHeight(borderPixel)
        else
            border:SetWidth(borderPixel)
        end
        row.slotBadge.borders[index] = border
    end

    row.slotText = CreateText(row.slotBadge, "", BODY_TEXT_SIZE, "color.text.muted", "CENTER")
    row.slotText:SetPoint(
        "CENTER",
        row.slotBadge,
        "CENTER",
        row.slotTextOpticalOffsetX,
        0
    )
    row.slotText:SetWordWrap(false)

    row.levelColumn = GUI2:CreateFrame(row, {
        width = ITEM_LEVEL_FALLBACK_WIDTH,
        height = ROW_HEIGHT,
    })
    row.levelColumn:SetPoint("LEFT", row.slotBadge, "RIGHT", row.columnGap, 0)

    row.levelText = CreateText(row.levelColumn, "", BODY_TEXT_SIZE, "color.text.secondary", "CENTER", "number")
    row.levelText:SetPoint(
        "CENTER",
        row.levelColumn,
        "CENTER",
        row.itemLevelTextOpticalOffsetX,
        0
    )
    row.levelText:SetWordWrap(false)

    local statBadgeSize = GetPixelMetric(row, STAT_BADGE_SIZE)
    local statSolidSize = GetPixelMetric(row, STAT_BADGE_SOLID_SIZE)
    local statBadgeGap = GetPixelMetric(row, STAT_BADGE_GAP)
    local statBadgeWidth = statBadgeSize * STAT_BADGE_COUNT
        + statBadgeGap * (STAT_BADGE_COUNT - 1)
    row.statBadgeWidth = statBadgeWidth
    row.statBadgeGroup = GUI2:CreateFrame(row, {
        width = statBadgeWidth,
        height = statBadgeSize,
    })
    row.statBadgeGroup:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.statBadges = {}
    for index = 1, STAT_BADGE_COUNT do
        local badge = GUI2:CreateFrame(row.statBadgeGroup, {
            width = statBadgeSize,
            height = statBadgeSize,
        })
        if index == 1 then
            badge:SetPoint("LEFT", row.statBadgeGroup, "LEFT", 0, 0)
        else
            badge:SetPoint("LEFT", row.statBadges[index - 1], "RIGHT", statBadgeGap, 0)
        end
        badge.outline = GUI2:CreateTexture(badge, { layer = "BACKGROUND", subLevel = 1 })
        badge.outline:SetSize(statBadgeSize, statBadgeSize)
        badge.outline:SetPoint("CENTER", badge, "CENTER", 0, 0)
        badge.outline:SetColorTexture(0, 0, 0, 0.75)
        ApplyPixelPolicy(badge.outline)
        badge.outline:Hide()
        badge.solid = GUI2:CreateTexture(badge, { layer = "ARTWORK", subLevel = 2 })
        badge.solid:SetSize(statSolidSize, statSolidSize)
        badge.solid:SetPoint("CENTER", badge, "CENTER", 0, 0)
        ApplyPixelPolicy(badge.solid)
        badge.solid:Hide()
        badge.text = CreateText(badge, T("stat.short." .. SECONDARY_STAT_IDS[index]), BODY_TEXT_SIZE, "color.text.primary", "CENTER")
        badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)
        badge.text:SetWordWrap(false)
        badge.text:Hide()
        card.themeTexts[#card.themeTexts + 1] = badge.text
        badge:Hide()
        row.statBadges[index] = badge
    end

    row.nameText = CreateText(row, "", BODY_TEXT_SIZE, "color.text.primary")
    row.nameText:SetPoint("LEFT", row.levelColumn, "RIGHT", row.columnGap, 0)
    row.nameText:SetWordWrap(false)

    if YUI.IsForever then
        row.enchantText = CreateText(row, "", BODY_TEXT_SIZE, "color.state.success")
        row.enchantText:SetWordWrap(true)
        row.enchantText:Hide()
        card.themeTexts[#card.themeTexts + 1] = row.enchantText
        row.gems = {}
        for index = 1, 4 do
            local gem = GUI2:CreateTexture(row, { layer = "ARTWORK" })
            gem:Hide()
            row.gems[index] = gem
        end
    end

    row.upgradeText = CreateText(row, "", BODY_TEXT_SIZE, "color.text.primary", "LEFT", "number")
    row.upgradeText:SetWordWrap(false)

    row.enhancementAlert = GUI2:CreateFrame(row, {
        width = MISSING_ENHANCEMENT_ICON.size,
        height = MISSING_ENHANCEMENT_ICON.size,
    })
    row.enhancementAlert:EnableMouse(true)
    row.enhancementAlert.icon = GUI2:CreateTexture(
        row.enhancementAlert,
        { layer = "ARTWORK", subLevel = 3 }
    )
    row.enhancementAlert.icon:SetPoint("TOPLEFT", row.enhancementAlert, "TOPLEFT", 0, 0)
    row.enhancementAlert.icon:SetPoint("BOTTOMRIGHT", row.enhancementAlert, "BOTTOMRIGHT", 0, 0)
    ApplyPixelPolicy(row.enhancementAlert.icon)
    if type(row.enhancementAlert.icon.SetAtlas) == "function" then
        row.enhancementAlert.icon:SetAtlas(MISSING_ENHANCEMENT_ICON.atlas, false)
    end
    row.enhancementAlert.icon:SetVertexColor(Unpack(MISSING_ENHANCEMENT_ICON.color))
    row.enhancementAlert:SetScript("OnEnter", ShowEnhancementTooltip)
    row.enhancementAlert:SetScript("OnLeave", HideTooltip)
    row.enhancementAlert:Hide()

    row:SetScript("OnEnter", function(self)
        if self.link then ShowTooltip(self, self.link) end
    end)
    row:SetScript("OnLeave", HideTooltip)
    row.definition = definition
    return row
end

local function FindSecondaryStat(records, statID)
    for _, record in ipairs(records) do
        if record.id == statID then return record end
    end
end

local function UpdateItemStatBadges(row, records, style)
    records = type(records) == "table" and records or {}
    for index = 1, STAT_BADGE_COUNT do
        local badge = row.statBadges[index]
        badge.record = nil
        badge.outline:Hide()
        badge.solid:Hide()
        badge.text:Hide()
        badge:Hide()
    end

    local showGroup = style ~= "none"
    row.statBadgeGroup:SetShown(showGroup)
    if not showGroup then return false end

    for index, statID in ipairs(SECONDARY_STAT_IDS) do
        local record = FindSecondaryStat(records, statID)
        local badge = row.statBadges[index]
        local color = record and SECONDARY_STAT_COLORS[record.id]
        if record and color then
            badge.record = record
            badge.solid:SetColorTexture(color[1], color[2], color[3], 1)
            if style == "text" then
                badge.text:SetTextColor(color[1], color[2], color[3], 1)
                badge.text:Show()
            else
                badge.outline:Show()
                badge.solid:Show()
            end
            badge:Show()
        end
    end
    return true
end

local function CreateStatRow(card, definition)
    local row = GUI2:CreateFrame(GetContentParent(card), {
        width = CARD_WIDTH - 24,
        height = ROW_HEIGHT,
    })

    row.label = CreateText(row, "", BODY_TEXT_SIZE, "color.text.secondary")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetWordWrap(false)

    row.value = CreateText(row, "", BODY_TEXT_SIZE, "color.text.primary", "RIGHT", "number")
    row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.value:SetWidth(100)
    row.value:SetWordWrap(false)

    row.comparison = CreateText(row, "", BODY_TEXT_SIZE, "color.text.muted", "LEFT", "number")
    row.label._equipmentHeightLimit = STAT_ROW_HEIGHT - 4
    row.value._equipmentHeightLimit = STAT_ROW_HEIGHT - 4
    row.comparison._equipmentHeightLimit = STAT_ROW_HEIGHT - 4
    row.comparison:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.comparison:SetWidth(1)
    row.comparison:SetJustifyH("RIGHT")
    row.comparison:SetWordWrap(false)
    row.comparison:Hide()
    CaptureComparisonFont(row)

    row.definition = definition
    row._visible = false
    row._comparisonVisible = false
    row:EnableMouse(true)
    row:SetScript("OnEnter", ShowSecondaryStatsTooltip)
    row:SetScript("OnLeave", HideTooltip)
    row:Hide()
    return row
end

local function CreateSection(card, key, labelKey)
    local section = {
        key = key,
        heading = CreateText(GetContentParent(card), T(labelKey), "font.size.sm", "color.text.heading"),
        rows = {},
    }
    section.heading:Hide()
    card.themeTexts[#card.themeTexts + 1] = section.heading
    card.themeHeadings[#card.themeHeadings + 1] = section.heading
    return section
end

local function BuildCard(kind)
    local card = GUI2:CreateFrame(UIParent, {
        name = kind == "player" and "YUICharacterEquipmentInfoPlayer" or "YUICharacterEquipmentInfoInspect",
        width = CARD_WIDTH,
        height = 120,
        frameStrata = "HIGH",
        clampedToScreen = true,
    })
    card.kind = kind
    card.themeTexts = {}
    card.themeHeadings = {}
    card.equipmentRows = {}
    card.statRows = {}
    card.sections = {}

    card.content = card

    card.title = CreateText(card, "", HEADER_TEXT_SIZE, "color.text.heading")
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_INSET, HEADER_TEXT_TOP)
    card.title:SetPoint("RIGHT", card, "RIGHT", -106, 0)
    card.title:SetHeight(HEADER_TEXT_HEIGHT)
    card.title:SetWordWrap(false)
    card.title._equipmentHeightLimit = HEADER_TEXT_HEIGHT - 2
    card.themeTexts[#card.themeTexts + 1] = card.title
    card.themeHeadings[#card.themeHeadings + 1] = card.title

    card.meta = CreateText(card, "", HEADER_TEXT_SIZE, "color.text.secondary", "RIGHT", "number")
    card.meta._equipmentHeightLimit = HEADER_TEXT_HEIGHT - 2
    card.meta:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_INSET, HEADER_TEXT_TOP)
    card.meta:SetWidth(86)
    card.meta:SetHeight(HEADER_TEXT_HEIGHT)
    card.meta:SetJustifyH("RIGHT")
    card.meta:SetWordWrap(false)
    card.themeTexts[#card.themeTexts + 1] = card.meta

    card.headerLine = CreateSectionLine(card)
    card.secondaryLine = CreateSectionLine(card, "color.border.default")

    card.sections.equipment = CreateSection(card, "equipment", "section.equipment")
    for _, definition in ipairs(SLOT_DEFINITIONS) do
        local row = CreateEquipmentRow(card, definition)
        row.slotText:SetText(T(definition.labelKey))
        card.equipmentRows[#card.equipmentRows + 1] = row
        card.sections.equipment.rows[#card.sections.equipment.rows + 1] = row
        card.themeTexts[#card.themeTexts + 1] = row.slotText
        card.themeTexts[#card.themeTexts + 1] = row.nameText
        card.themeTexts[#card.themeTexts + 1] = row.upgradeText
        card.themeTexts[#card.themeTexts + 1] = row.levelText
    end

    card.sections.primary = CreateSection(card, "primary", "section.primary")
    card.sections.secondary = CreateSection(card, "secondary", "section.secondary")
    card.sections.defense = CreateSection(card, "defense", "section.defense")

    for _, definition in ipairs(STAT_DEFINITIONS) do
        if definition.category ~= "summary" then
            local section = card.sections[definition.category]
            if section then
                local row = CreateStatRow(card, definition)
                row.label:SetText(T("stat." .. definition.id))
                section.rows[#section.rows + 1] = row
                card.statRows[definition.id] = row
                card.themeTexts[#card.themeTexts + 1] = row.label
                card.themeTexts[#card.themeTexts + 1] = row.value
                card.themeTexts[#card.themeTexts + 1] = row.comparison
            end
        end
    end

    if YUI.IsForever then
        for _, id in ipairs({ "primary_summary", "power_summary" }) do
            local row = CreateStatRow(card, { id = id, category = "primary" })
            row.label:SetText(T("stat." .. id))
            card.statRows[id] = row
            card.themeTexts[#card.themeTexts + 1] = row.label
            card.themeTexts[#card.themeTexts + 1] = row.value
            card.themeTexts[#card.themeTexts + 1] = row.comparison
        end
    end

    card.statsNotice = CreateText(GetContentParent(card), T("stats.unavailable"), BODY_TEXT_SIZE, "color.text.muted")
    card.statsNotice:SetJustifyH("LEFT")
    card.statsNotice:SetWordWrap(true)
    card.statsNotice:Hide()
    card.themeTexts[#card.themeTexts + 1] = card.statsNotice

    card.emptyNotice = CreateText(GetContentParent(card), T("content.empty"), BODY_TEXT_SIZE, "color.text.muted")
    card.emptyNotice:SetJustifyH("LEFT")
    card.emptyNotice:SetWordWrap(true)
    card.emptyNotice:Hide()
    card.themeTexts[#card.themeTexts + 1] = card.emptyNotice

    if Appearance and type(Appearance.Register) == "function" then
        local context = Appearance:Register(card, {
            themeProvider = GetThemeStyle,
            blizzardWindow = kind == "inspect" and "inspect" or "charsheet",
            headings = card.themeHeadings,
            noTopBar = true,
            role = "character-summary",
            nativeBorderOverflow = YUI.IsForever == true,
            onRefresh = function(_, refreshedContext)
                ApplyCardTheme(card, refreshedContext)
            end,
        })
        ApplyCardTheme(card, context)
    else
        UpdateSlotTextWidth(card)
    end

    card:Hide()
    return card
end

local function FormatNumber(value)
    if type(value) ~= "number" or IsSecret(value) then return T("value.unavailable", "—") end
    return tostring(math.floor(value + 0.5))
end

local function FormatEquipmentLevel(level)
    if type(level) ~= "number" or IsSecret(level) then return "" end
    return FormatNumber(level)
end

local function FormatUpgradeProgress(upgrade)
    if type(upgrade) == "table" and not upgrade.secret
        and type(upgrade.currentLevel) == "number"
        and type(upgrade.maxLevel) == "number"
        and upgrade.maxLevel > 0
    then
        return "("
            .. FormatNumber(upgrade.currentLevel)
            .. "/"
            .. FormatNumber(upgrade.maxLevel)
            .. ")"
    end
    return ""
end

local function FormatAverageItemLevel(value)
    if type(value) ~= "number" then
        return T("value.unavailable", "—")
    end
    if IsSecret(value) then
        local ok, text = pcall(string.format, "%.1f", value)
        return ok and text or T("value.unavailable", "—")
    end
    if value == math.floor(value) then
        return tostring(value)
    end
    return string.format("%.1f", value)
end

local function SetItemQualityColor(fontString, quality)
    if not fontString then return end
    if Item and type(Item.GetQualityColor) == "function" and quality ~= nil then
        local r, g, b = Item.GetQualityColor(quality)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            fontString:SetTextColor(r, g, b, 1)
            return
        end
    end
    SetTextColorKey(fontString, "color.text.primary")
end

local function ResolveTrackColor(slot)
    if YUI.IsForever then
        if slot and not slot.secret and not slot.pending and slot.available
            and type(slot.quality) == "number" and Item and type(Item.GetQualityColor) == "function" then
            local r, g, b = Item.GetQualityColor(slot.quality)
            if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                return r, g, b, 1
            end
        end
        local color = NO_TRACK_COLOR
        if slot and (slot.secret or slot.pending) then
            color = PENDING_TRACK_COLOR
        elseif not slot or not slot.available then
            color = EMPTY_TRACK_COLOR
        end
        return Unpack(color)
    end
    local upgrade = slot and slot.upgrade
    if upgrade and FormatUpgradeProgress(upgrade) ~= "" and upgrade.quality ~= nil
        and Item and type(Item.GetQualityColor) == "function"
    then
        local r, g, b = Item.GetQualityColor(upgrade.quality)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b, 1
        end
    end
    if slot and type(slot.craftedQuality) == "number" then
        return Unpack(CRAFTED_TRACK_COLOR)
    end
    local color
    if slot and slot.pending then
        color = PENDING_TRACK_COLOR
    elseif not slot or not slot.available then
        color = EMPTY_TRACK_COLOR
    else
        color = NO_TRACK_COLOR
    end
    return color[1], color[2], color[3], color[4]
end

local function ApplyTrackColor(row, slot)
    local r, g, b, a = ResolveTrackColor(slot)
    row.slotText:SetTextColor(r, g, b, a)
    if YUI.IsForever then
        SetTextColorKey(row.levelText, "color.text.primary")
    else
        row.levelText:SetTextColor(r, g, b, a)
    end
    row.slotBadge.background:SetColorTexture(r, g, b, 0.16)
    for _, border in ipairs(row.slotBadge.borders) do
        border:SetColorTexture(r, g, b, 0.85)
    end
end

local function UpdateEquipmentLevelWidth(card)
    local width = 0
    for _, row in ipairs(card.equipmentRows or {}) do
        width = math.max(width, GetRenderedTextWidth(row.levelText, 0))
    end
    if width <= 0 then width = ITEM_LEVEL_FALLBACK_WIDTH end
    for _, row in ipairs(card.equipmentRows or {}) do
        row.levelColumn:SetWidth(width)
    end
    card.itemLevelWidth = width
end

local function UpdateEquipmentTextLayout(card, row, itemStatStyle)
    local rowWidth = card:GetWidth() - ((card.contentInset or CARD_INSET) * 2)
    local columnGap = row.columnGap or GetPixelMetric(row, COLUMN_GAP)
    local slotBadgePaddingX = row.slotBadgePaddingX or GetPixelMetric(row, SLOT_BADGE_PADDING_X)
    local leftWidth = (card.slotBadgeWidth or (SLOT_TEXT_MIN_WIDTH + slotBadgePaddingX * 2))
        + columnGap
        + (card.itemLevelWidth or ITEM_LEVEL_FALLBACK_WIDTH)
        + columnGap
    local rightWidth = itemStatStyle ~= "none"
        and ((row.statBadgeWidth or STAT_BADGE_WIDTH) + COLUMN_GAP) or 0

    local upgradeWidth = 0
    local upgradeShown = row.upgradeVisible == true
    if upgradeShown then
        upgradeWidth = GetRenderedTextWidth(row.upgradeText, 0)
        row.upgradeText:SetWidth(upgradeWidth)
        row.upgradeText:Show()
    else
        row.upgradeText:Hide()
    end

    local alertShown = row.enhancementAlert.enhancement
        and row.enhancementAlert.enhancement.missing == true
    local suffixWidth = upgradeShown and (COLUMN_GAP + upgradeWidth) or 0
    if alertShown then
        suffixWidth = suffixWidth + COLUMN_GAP + MISSING_ENHANCEMENT_ICON.size
    end

    local maximumNameWidth = math.max(1, rowWidth - leftWidth - rightWidth - suffixWidth)
    if YUI.IsForever then
        local size = math.max(8, math.min(16, card._textSize or DEFAULT_FONT_SIZE))
        local count = row.gemCount or 0
        local gemWidth = count > 0 and count * (size + 2) + COLUMN_GAP or 0
        maximumNameWidth = math.max(1, maximumNameWidth - gemWidth)
        local nameWidth = math.min(GetRenderedTextWidth(row.nameText, maximumNameWidth), maximumNameWidth)
        row.nameText:SetWidth(math.max(1, nameWidth))
        local anchor = row.nameText
        for index, gem in ipairs(row.gems) do
            gem:ClearAllPoints()
            gem:SetSize(size, size)
            gem:SetPoint("LEFT", anchor, "RIGHT", COLUMN_GAP, 0)
            gem:SetShown(index <= count)
            if index <= count then anchor = gem end
        end
        local enchantWidth = row.enchantVisible and GetRenderedTextWidth(row.enchantText, 0) or 0
        local remaining = rowWidth - leftWidth - nameWidth - gemWidth - COLUMN_GAP
        row.enchantText:ClearAllPoints()
        row.extraHeight = 0
        if enchantWidth > 0 then
            if enchantWidth <= remaining then
                row.enchantText:SetWidth(enchantWidth)
                row.enchantText:SetPoint("LEFT", anchor, "RIGHT", COLUMN_GAP, 0)
            else
                local width = math.max(1, rowWidth - leftWidth)
                row.enchantText:SetWidth(width)
                row.enchantText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -2)
                row.extraHeight = math.ceil(enchantWidth / width) * ((card._textSize or DEFAULT_FONT_SIZE) + 3) + 2
                if row.enchantText.GetStringHeight then
                    row.extraHeight = math.max(row.extraHeight, row.enchantText:GetStringHeight() + 2)
                end
            end
        end
        row.enchantText:SetShown(row.enchantVisible == true)
        row.upgradeText:Hide()
        row.enhancementAlert:Hide()
        return
    end
    local naturalNameWidth = GetRenderedTextWidth(row.nameText, maximumNameWidth)
    row.nameText:SetWidth(math.max(1, math.min(naturalNameWidth, maximumNameWidth)))

    row.upgradeText:ClearAllPoints()
    if upgradeShown then
        row.upgradeText:SetPoint("LEFT", row.nameText, "RIGHT", COLUMN_GAP, 0)
    end

    row.enhancementAlert:ClearAllPoints()
    if alertShown then
        local anchor = upgradeShown and row.upgradeText or row.nameText
        row.enhancementAlert:SetPoint("LEFT", anchor, "RIGHT", COLUMN_GAP, 0)
        row.enhancementAlert:Show()
    else
        row.enhancementAlert:Hide()
    end
end

RefreshEquipmentTextLayout = function(card, itemStatStyle)
    if not card then return end
    UpdateEquipmentLevelWidth(card)
    for _, row in ipairs(card.equipmentRows or {}) do
        UpdateEquipmentTextLayout(card, row, itemStatStyle)
    end
end

local function UpdateEquipmentRows(card, unit)
    local probe = _G.YUI_CharacterEquipmentProbe
    local started = probe and probe("begin", "equipment")
    local snapshot = PaperDoll.ReadEquipment(unit, card.equipmentSnapshot)
    if probe then
        probe("finish", "equipment", started)
        probe("snapshot", unit, snapshot)
    end
    card.equipmentSnapshot = snapshot
    local itemStatStyle = GetEquipmentSecondaryStatStyle(GetDB())

    for index, row in ipairs(card.equipmentRows) do
        local slot = snapshot.slots[index] or {}
        row.link = slot.link

        local name
        if slot.secret then
            name = T("value.unavailable", "—")
        elseif not slot.available then
            name = T("item.empty", "—")
        elseif slot.pending then
            name = T("item.loading", "Loading…")
        else
            name = slot.name or slot.link or T("value.unavailable", "—")
        end

        row.nameText:SetText(name)
        local levelText = FormatEquipmentLevel(slot.level)
        local upgradeText = FormatUpgradeProgress(slot.upgrade)
        row.levelText:SetText(levelText)
        row.upgradeText:SetText(upgradeText)
        row.upgradeVisible = upgradeText ~= ""
        SetItemQualityColor(row.nameText, slot.quality)
        SetItemQualityColor(row.upgradeText, slot.quality)
        ApplyTrackColor(row, slot)

        row.enhancementAlert.enhancement = slot.enhancement
        if YUI.IsForever then
            local display = not slot.secret and slot.slotDisplay
            row.enchantVisible = display and type(display.enchant) == "string" and display.enchant ~= "" or false
            row.enchantText:SetText(row.enchantVisible and display.enchant or "")
            row.gemCount = display and display.gems and math.min(4, #display.gems) or 0
            for index, gem in ipairs(row.gems) do
                gem:SetTexture(index <= row.gemCount and display.gems[index] or nil)
            end
        end
        UpdateItemStatBadges(row, slot.secondaryStats, itemStatStyle)

        if slot.pending and slot.itemID then
            if probe then probe("load", slot.itemID) end
            local requestStarted = probe and probe("begin", "load")
            PaperDoll.RequestItemData(slot.itemID)
            if probe then probe("finish", "load", requestStarted) end
        end
    end
    RefreshEquipmentTextLayout(card, itemStatStyle)
end

local function RoundSignedPercent(value)
    if value < 0 then return math.ceil(value - 0.5) end
    return math.floor(value + 0.5)
end

local function UpdateComparison(row, value, baseline, enabled)
    row._comparisonVisible = false
    row.comparison:SetText("")
    row.comparison:Hide()
    if not enabled or type(value) ~= "number"
        or type(baseline) ~= "number" or baseline <= 0
    then
        return
    end

    local difference = RoundSignedPercent((value - baseline) / baseline * 100)
    local sign = difference > 0 and "+" or ""
    row.comparison:SetText(string.format("(%s%d%%)", sign, difference))
    row._comparisonVisible = true
    if difference > 0 then
        SetTextColorKey(row.comparison, "color.state.success")
    elseif difference < 0 then
        SetTextColorKey(row.comparison, "color.state.danger")
    else
        SetTextColorKey(row.comparison, "color.text.muted")
    end
    row.comparison:Show()
end

local function UpdateStatRows(card, isInspect, comparisonTotals)
    if YUI.IsForever then
        local snapshot = PaperDoll.ReadEquipmentSummaryTotals and PaperDoll.ReadEquipmentSummaryTotals(card.equipmentSnapshot, card.secondaryTotals)
        card.secondaryTotals, card.statsAvailable = snapshot, snapshot ~= nil
        local profile = PaperDoll.GetEquipmentSummaryProfile and PaperDoll.GetEquipmentSummaryProfile(card.classToken)
        for _, id in ipairs(SUMMARY_STAT_IDS) do
            local row = card.statRows[id]
            if row then
                local keys = id == "primary_summary" and profile and profile.primary
                    or id == "power_summary" and profile and profile.power
                local label, value = "", ""
                row.summaryColorKey = keys and #keys == 1 and keys[1] or nil
                if keys then
                    for index, key in ipairs(keys) do
                        local separator = index > 1 and "/" or ""
                        local partLabel = T((id == "power_summary" and "summary." or "stat.") .. key)
                        local partValue = FormatNumber(snapshot and snapshot.values[key])
                        local color = #keys > 1 and SECONDARY_STAT_COLORS[key]
                        if color then
                            local prefix = string.format("|cff%02x%02x%02x", math.floor(color[1] * 255 + .5),
                                math.floor(color[2] * 255 + .5), math.floor(color[3] * 255 + .5))
                            partLabel, partValue = prefix .. partLabel .. "|r", prefix .. partValue .. "|r"
                        end
                        label = label .. separator .. partLabel
                        value = value .. separator .. partValue
                    end
                else
                    label = T("stat." .. id)
                    value = FormatNumber(snapshot and snapshot.values[id])
                end
                row.label:SetText(label)
                row.value:SetText(snapshot and snapshot.pending and T("item.loading") or value)
                row._visible = true
                -- Compound values do not have one meaningful comparison percentage.
                UpdateComparison(row, snapshot and snapshot.values[id], comparisonTotals and comparisonTotals.values[id],
                    isInspect and snapshot and snapshot.complete and comparisonTotals and comparisonTotals.complete and not keys)
            end
        end
        card.statsNotice:Hide()
        return
    end
    local snapshot
    if type(PaperDoll.ReadEquipmentSecondaryTotals) == "function" then
        snapshot = PaperDoll.ReadEquipmentSecondaryTotals(
            card.equipmentSnapshot,
            card.secondaryTotals
        )
    end
    card.secondaryTotals = snapshot
    card.statsAvailable = snapshot ~= nil

    local comparisonComplete = isInspect
        and snapshot and snapshot.complete == true
        and comparisonTotals and comparisonTotals.complete == true
    for _, id in ipairs(SECONDARY_STAT_IDS) do
        local row = card.statRows[id]
        if row then
            local value = snapshot and snapshot.complete and snapshot.values[id] or nil
            row._visible = snapshot ~= nil
            row._record = value
            if type(value) == "number" then
                row.value:SetText(FormatNumber(value))
            elseif snapshot and snapshot.pending then
                row.value:SetText(T("item.loading", "Loading…"))
            else
                row.value:SetText(T("value.unavailable", "—"))
            end
            UpdateComparison(
                row,
                value,
                comparisonComplete and comparisonTotals.values[id] or nil,
                comparisonComplete
            )
        end
    end

    card.statsNotice:SetText(T("stats.unavailable"))
    card.statsNotice:Hide()
end

local function GetCardHeight(card)
    if card and type(card.GetHeight) == "function" then
        local ok, height = pcall(card.GetHeight, card)
        if ok and type(height) == "number" and height > 0 then
            return height
        end
    end
    return 460
end

local function GetLineHeight(line)
    if line and type(line.GetHeight) == "function" then
        local height = line:GetHeight()
        if type(height) == "number" and height > 0 then return height end
    end
    return PIXEL_SIZE
end

local function PlaceSectionLine(line, card, y)
    if not line then return end
    local CARD_INSET = card.contentInset or CARD_INSET
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_INSET, y)
    line:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_INSET, y)
    line:Show()
end

local function HideSectionLine(line)
    if line then line:Hide() end
end

local function LayoutEquipment(card, top, rowHeight)
    local CARD_INSET = card.contentInset or CARD_INSET
    local section = card.sections.equipment
    section.heading:Hide()
    for _, row in ipairs(section.rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_INSET, top)
        row:SetPoint("RIGHT", card, "RIGHT", -CARD_INSET, 0)
        row:SetHeight(rowHeight + (row.extraHeight or 0))
        if YUI.IsForever then
            row.slotBadge:ClearAllPoints()
            row.slotBadge:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(rowHeight - row.slotBadge:GetHeight()) / 2)
        end
        row:Show()
        top = top - rowHeight - (row.extraHeight or 0)
    end
    return top
end

local function ApplySecondaryStatColor(row, statID)
    local color = SECONDARY_STAT_COLORS[row and row.summaryColorKey or statID]
    if not row or not color then return end
    row.label:SetTextColor(color[1], color[2], color[3], 1)
    row.value:SetTextColor(color[1], color[2], color[3], 1)
end

local function LayoutSecondaryStats(card, top, isInspect, db)
    local CARD_INSET = card.contentInset or CARD_INSET
    local SECONDARY_STAT_IDS = SUMMARY_STAT_IDS
    local secondaryEnabled = db.showSecondaryStats == true
    for _, id in ipairs(SECONDARY_STAT_IDS) do
        local row = card.statRows[id]
        if row then row:Hide() end
    end

    if not secondaryEnabled then
        card.statsNotice:Hide()
        return false
    end

    local visibleCount = 0
    for _, id in ipairs(SECONDARY_STAT_IDS) do
        local row = card.statRows[id]
        if row and row._visible then visibleCount = visibleCount + 1 end
    end

    if not card.statsAvailable or visibleCount == 0 then
        card.statsNotice:ClearAllPoints()
        card.statsNotice:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_INSET, top)
        card.statsNotice:SetPoint("RIGHT", card, "RIGHT", -CARD_INSET, 0)
        card.statsNotice:SetHeight(STAT_ROW_HEIGHT * 2)
        card.statsNotice:Show()
        return true
    end

    card.statsNotice:Hide()
    local width = card:GetWidth() - (CARD_INSET * 2)
    local columnWidth = (width - STAT_COLUMN_GAP) / 2
    for rowIndex = 0, 1 do
        local leftID = SECONDARY_STAT_IDS[(rowIndex * 2) + 1]
        local rightID = SECONDARY_STAT_IDS[(rowIndex * 2) + 2]
        local leftRow = card.statRows[leftID]
        local rightRow = card.statRows[rightID]
        for column = 0, 1 do
            local id = column == 0 and leftID or rightID
            local row = column == 0 and leftRow or rightRow
            local columnOffset = column * (columnWidth + STAT_COLUMN_GAP)
            if row then
                row:ClearAllPoints()
                row:SetPoint(
                    "TOPLEFT",
                    card,
                    "TOPLEFT",
                    CARD_INSET + columnOffset,
                    top - (rowIndex * STAT_ROW_HEIGHT)
                )
                row:SetWidth(columnWidth)
                row:SetHeight(STAT_ROW_HEIGHT)
                row.value:ClearAllPoints()
                row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                local valueWidth = math.max(STAT_VALUE_WIDTH, GetRenderedTextWidth(row.value, STAT_VALUE_WIDTH))
                row.value:SetWidth(valueWidth)
                local labelWidth = math.min(
                    GetRenderedTextWidth(row.label, 0) + STAT_LABEL_PADDING,
                    math.max(1, columnWidth - valueWidth - STAT_CONTENT_GAP)
                )
                row.label:SetWidth(labelWidth)
                if row._comparisonVisible then
                    local comparisonMaxWidth = columnWidth
                        - labelWidth
                        - valueWidth
                        - (STAT_CONTENT_GAP * 2)
                    row.comparison:ClearAllPoints()
                    row.comparison:SetPoint(
                        "RIGHT",
                        row.value,
                        "LEFT",
                        -STAT_CONTENT_GAP,
                        0
                    )
                    FitComparisonFont(row, comparisonMaxWidth)
                else
                    RestoreComparisonFont(row)
                    row._comparisonMaxWidth = nil
                    row._comparisonFontSize = row._comparisonBaseFontSize
                end
                row:Show()
                ApplySecondaryStatColor(row, id)
            end
        end
    end
    return true
end

LayoutCard = function(card, isInspect)
    local CARD_INSET = card.contentInset or CARD_INSET
    local db = GetDB()
    local height = card.hostHeight or GetCardHeight(card)
    local lineHeight = GetLineHeight(card.headerLine or card.secondaryLine)
    local statsHeight = STAT_ROW_HEIGHT * 2
    local statsTop = -height + CARD_BOTTOM_INSET + statsHeight
    local statsLineY = statsTop + CARD_SECTION_GAP + lineHeight
    local equipmentTop = -CARD_HEADER_HEIGHT - CARD_SECTION_GAP - lineHeight
    local availableEquipmentHeight = equipmentTop - statsLineY
    local rowHeight = math.floor(availableEquipmentHeight / #SLOT_DEFINITIONS)
    rowHeight = math.max(1, math.min(24, rowHeight))

    ApplyCardFonts(card, rowHeight)
    local style = GetEquipmentSecondaryStatStyle(db)
    local cellSize = GetPixelMetric(card, STAT_BADGE_SIZE)
    local gap = GetPixelMetric(card, STAT_BADGE_GAP)
    if style == "text" then
        for _, badge in ipairs(card.equipmentRows[1].statBadges) do
            cellSize = math.max(cellSize, GetRenderedTextWidth(badge.text, 13) + 2)
        end
    end
    local groupWidth = cellSize * STAT_BADGE_COUNT + gap * (STAT_BADGE_COUNT - 1)
    if card._badgeCellSize ~= cellSize or card._badgeRowHeight ~= rowHeight or card._badgeStyle ~= style then
        card._badgeCellSize, card._badgeRowHeight, card._badgeStyle = cellSize, rowHeight, style
        for _, row in ipairs(card.equipmentRows) do
            row.statBadgeWidth = groupWidth
            row.statBadgeGroup:SetSize(groupWidth, style == "text" and rowHeight or cellSize)
            for _, badge in ipairs(row.statBadges) do
                badge:SetSize(cellSize, style == "text" and rowHeight or cellSize)
            end
            row.slotBadge:SetHeight(math.min(SLOT_BADGE_HEIGHT, rowHeight))
        end
    end
    UpdateEquipmentLevelWidth(card)
    local baseWidth = YUI.IsForever and 300 or (style == "text" and TEXT_CARD_WIDTH or CARD_WIDTH)
    local reservedWidth = card.slotBadgeWidth + card.itemLevelWidth + COLUMN_GAP * 2
        + (style ~= "none" and groupWidth + COLUMN_GAP or 0)
    local suffixWidth = 0
    for _, row in ipairs(card.equipmentRows) do
        local suffix = row.upgradeVisible and GetRenderedTextWidth(row.upgradeText, 0) + COLUMN_GAP or 0
        if row.enhancementAlert.enhancement and row.enhancementAlert.enhancement.missing then
            suffix = suffix + MISSING_ENHANCEMENT_ICON.size + COLUMN_GAP
        end
        suffixWidth = math.max(suffixWidth, suffix)
    end
    card.desiredWidth = math.max(baseWidth, math.ceil(CARD_INSET * 2 + reservedWidth + suffixWidth + 130))
    if db.showSecondaryStats == true and (YUI.IsForever or db.textFont ~= DEFAULT_FONT
        or db.numberFont ~= DEFAULT_FONT or db.textFontSize ~= DEFAULT_FONT_SIZE
        or db.numberFontSize ~= DEFAULT_FONT_SIZE)
    then
        local statWidth = 0
        for _, id in ipairs(SUMMARY_STAT_IDS) do
            local row = card.statRows[id]
            if row then
                local valueWidth = math.max(STAT_VALUE_WIDTH, GetRenderedTextWidth(row.value, STAT_VALUE_WIDTH))
                local comparisonWidth = row._comparisonVisible and 60 or 0
                statWidth = math.max(statWidth, GetRenderedTextWidth(row.label, 0) + STAT_LABEL_PADDING
                    + valueWidth + comparisonWidth + STAT_CONTENT_GAP * 2)
            end
        end
        card.desiredWidth = math.max(card.desiredWidth, math.ceil(statWidth * 2 + STAT_COLUMN_GAP + CARD_INSET * 2))
    end
    card:SetWidth(math.max(card.desiredWidth, card.sharedWidth or 0))
    local metaWidth = math.max(86, GetRenderedTextWidth(card.meta, 86))
    card.meta:SetWidth(metaWidth)
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_INSET, HEADER_TEXT_TOP)
    card.meta:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_INSET, HEADER_TEXT_TOP)
    card.title:SetPoint("RIGHT", card, "RIGHT", -(CARD_INSET + metaWidth + CARD_GAP), 0)
    RefreshEquipmentTextLayout(card, style)

    if YUI.IsForever then
        local extraHeight = 0
        for _, row in ipairs(card.equipmentRows) do extraHeight = extraHeight + (row.extraHeight or 0) end
        local minimumRowHeight = math.max(card._textSize or DEFAULT_FONT_SIZE, card._numberSize or DEFAULT_FONT_SIZE) + 5
        local minimumHeight = CARD_HEADER_HEIGHT + CARD_SECTION_GAP * 2 + lineHeight * 2
            + #SLOT_DEFINITIONS * minimumRowHeight + extraHeight + CARD_BOTTOM_INSET + statsHeight
        height = math.max(height, minimumHeight)
        card.desiredHeight = height
        height = math.max(height, card.sharedHeight or 0)
        card:SetHeight(height)
        statsTop = -height + CARD_BOTTOM_INSET + statsHeight
        statsLineY = statsTop + CARD_SECTION_GAP + lineHeight
        rowHeight = math.max(minimumRowHeight, math.min(24, math.floor((equipmentTop - statsLineY - extraHeight) / #SLOT_DEFINITIONS)))
    end

    PlaceSectionLine(card.headerLine, card, -CARD_HEADER_HEIGHT)
    LayoutEquipment(card, equipmentTop, rowHeight)

    local hasStats = LayoutSecondaryStats(card, statsTop, isInspect, db)
    if hasStats then
        PlaceSectionLine(card.secondaryLine, card, statsLineY)
    else
        HideSectionLine(card.secondaryLine)
    end

    card.emptyNotice:Hide()
    card.contentHeight = height
end

SyncCardWidths = function()
    local playerCard, inspectCard = runtime.playerCard, runtime.inspectCard
    if not playerCard or not inspectCard then return end
    local sharedWidth = playerCard.desiredWidth or CARD_WIDTH
    if IsShown(_G.InspectFrame) then
        sharedWidth = math.max(sharedWidth, inspectCard.desiredWidth or CARD_WIDTH)
    end
    playerCard.sharedWidth = sharedWidth
    inspectCard.sharedWidth = IsShown(_G.InspectFrame) and sharedWidth or nil
    if YUI.IsForever and IsShown(_G.InspectFrame) then
        local sharedHeight = math.max(playerCard.desiredHeight or 0, inspectCard.desiredHeight or 0)
        playerCard.sharedHeight, inspectCard.sharedHeight = sharedHeight, sharedHeight
    end
    if playerCard:GetWidth() ~= sharedWidth or (playerCard.sharedHeight and playerCard:GetHeight() ~= playerCard.sharedHeight) then LayoutCard(playerCard, false) end
    if inspectCard.sharedWidth and (inspectCard:GetWidth() ~= sharedWidth
        or (inspectCard.sharedHeight and inspectCard:GetHeight() ~= inspectCard.sharedHeight)) then LayoutCard(inspectCard, true) end
end

local function UpdateCard(card, unit, isInspect, comparisonTotals)
    if not card then return end

    local identity = ReadIdentity(unit)
    card.classToken = identity.classToken
    card.title:SetText(identity.name)
    if identity.classColor then
        card.title:SetTextColor(
            identity.classColor.r,
            identity.classColor.g,
            identity.classColor.b,
            1
        )
    else
        local context = Appearance and Appearance.GetContext and Appearance:GetContext(card)
        if not (Appearance and Appearance.ApplyAccent and Appearance:ApplyAccent(card.title, context)) then
            SetTextColorKey(card.title, "color.text.heading")
        end
    end

    local itemLevel = PaperDoll.ReadAverageItemLevel(unit)
    local average
    if itemLevel then
        average = itemLevel.equipped or itemLevel.overall
    end
    local meta = T("value.unavailable", "—")
    if itemLevel and itemLevel.available and type(average) == "number" then
        meta = FormatAverageItemLevel(average)
    end
    card.meta:SetText(meta)
    SetTextColorKey(card.meta, "color.text.accent")

    UpdateEquipmentRows(card, unit)
    UpdateStatRows(card, isInspect, comparisonTotals)
    local probe = _G.YUI_CharacterEquipmentProbe
    local started = probe and probe("begin", "layout")
    LayoutCard(card, isInspect)
    if probe then probe("finish", "layout", started) end
end

local function ResolveHost()
    if IsShown(_G.InspectFrame) then return _G.InspectFrame, true end
    if IsShown(_G.CharacterFrame) then return _G.CharacterFrame, false end
    return nil, false
end

local function IsCharacterPaperDollActive()
    return _G.CharacterFrame
        and _G.CharacterFrame.activeSubframe == "PaperDollFrame"
end

local function ReadHostHeight(host)
    if not host or type(host.GetHeight) ~= "function" then return nil end
    local ok, height = pcall(host.GetHeight, host)
    if ok and type(height) == "number" and height > 0 then
        return height
    end
end

local function SetCardDimensions(card, width, height)
    if not card then return end
    if width and type(card.SetWidth) == "function" then
        card:SetWidth(width)
    end
    if height and type(card.SetHeight) == "function" then
        card.hostHeight = height
        card:SetHeight(height)
    end
end

local function GetHostCardGap(host, card)
    if not YUI.IsForever then return CARD_GAP end
    local modeTabs = host.ModeTabs
    if not modeTabs or not IsShown(modeTabs) or not modeTabs.Tabs
        or type(host.GetRight) ~= "function" then return CARD_GAP end
    local hostRight = host:GetRight()
    if not hostRight then return CARD_GAP end
    local hostScale = host:GetEffectiveScale()
    local cardScale = card:GetEffectiveScale()
    local right = hostRight * hostScale
    for _, tab in ipairs(modeTabs.Tabs) do
        if IsShown(tab) and type(tab.GetRight) == "function" then
            local tabRight = tab:GetRight()
            if tabRight then right = math.max(right, tabRight * tab:GetEffectiveScale()) end
        end
    end
    return CARD_GAP + (right - hostRight * hostScale) / cardScale
end

local function RefreshRuntime()
    if not runtime.enabled then return end

    if YUI.CharacterEquipmentOverlays then YUI.CharacterEquipmentOverlays:Refresh(GetDB()) end
    if GetDB().showSummary == false then
        if runtime.playerCard then runtime.playerCard:Hide() end
        if runtime.inspectCard then runtime.inspectCard:Hide() end
        return
    end
    local host, inspecting = ResolveHost()
    if not host then
        if runtime.playerCard then runtime.playerCard:Hide() end
        if runtime.inspectCard then runtime.inspectCard:Hide() end
        return
    end

    if not inspecting and (not IsCharacterPaperDollActive()
        or ((YUI.IsRetail or YUI.IsForever) and IsShown(_G.GearManagerPopupFrame))) then
        if runtime.playerCard then runtime.playerCard:Hide() end
        if runtime.inspectCard then runtime.inspectCard:Hide() end
        return
    end

    local level = type(host.GetFrameLevel) == "function" and host:GetFrameLevel() or 1
    local hostHeight = ReadHostHeight(host)
    local playerCard = runtime.playerCard
    local inspectCard = runtime.inspectCard
    playerCard.sharedWidth, inspectCard.sharedWidth = nil, nil
    playerCard.sharedHeight, inspectCard.sharedHeight = nil, nil
    SetCardDimensions(playerCard, nil, hostHeight)
    SetCardDimensions(inspectCard, nil, hostHeight)
    if hostHeight then
        playerCard.hostHeight = hostHeight
        inspectCard.hostHeight = hostHeight
    end
    if inspecting then
        playerCard:ClearAllPoints()
        playerCard:SetPoint("TOPLEFT", inspectCard, "TOPRIGHT", CARD_GAP, 0)
        playerCard:SetFrameLevel(level + 20)
        playerCard:Show()
        UpdateCard(playerCard, "player", false)

        inspectCard:ClearAllPoints()
        inspectCard:SetPoint("TOPLEFT", host, "TOPRIGHT", GetHostCardGap(host, inspectCard), 0)
        inspectCard:SetFrameLevel(level + 20)
        inspectCard:Show()
        UpdateCard(
            inspectCard,
            _G.InspectFrame and _G.InspectFrame.unit,
            true,
            playerCard.secondaryTotals
        )
        SyncCardWidths()
    else
        playerCard:ClearAllPoints()
        playerCard:SetPoint("TOPLEFT", host, "TOPRIGHT", GetHostCardGap(host, playerCard), 0)
        playerCard:SetFrameLevel(level + 20)
        playerCard:Show()
        UpdateCard(playerCard, "player", false)
        inspectCard:Hide()
    end
end

local function RequestRefresh(delay, reason)
    local probe = _G.YUI_CharacterEquipmentProbe
    if probe then probe("request", reason or "runtime/settings", runtime.refreshPending) end
    if not runtime.enabled or runtime.refreshPending then return end
    runtime.refreshPending = true
    local generation = runtime.generation

    local function Run()
        if generation ~= runtime.generation or not runtime.enabled then return end
        runtime.refreshTimer = nil
        runtime.refreshPending = false
        local activeProbe = _G.YUI_CharacterEquipmentProbe
        local started = activeProbe and activeProbe("begin", "refresh", reason or "runtime/settings")
        RefreshRuntime()
        if activeProbe then activeProbe("finish", "refresh", started) end
    end

    if C_Timer and type(C_Timer.NewTimer) == "function" then
        runtime.refreshTimer = C_Timer.NewTimer(delay or 0, Run)
    elseif delay and delay > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, Run)
    elseif C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, Run)
    else
        Run()
    end
end

local function HookFrame(frame)
    if not frame or runtime.hookedFrames[frame] or type(frame.HookScript) ~= "function" then
        return
    end

    runtime.hookedFrames[frame] = true
    frame:HookScript("OnShow", function() RequestRefresh(nil, "host.OnShow") end)
    frame:HookScript("OnHide", function() RequestRefresh(nil, "host.OnHide") end)
    frame:HookScript("OnSizeChanged", function() RequestRefresh(nil, "host.OnSizeChanged") end)
end

local function HookModeTabs(host)
    if YUI.IsForever and host and host.ModeTabs then
        local modeTabs = host.ModeTabs
        HookFrame(modeTabs)
        for _, tab in ipairs(modeTabs.Tabs or {}) do HookFrame(tab) end
    end
end

local function RequestOverlayRefresh()
    RequestRefresh(nil, "slot overlay")
end

local function TryHookFrames()
    if YUI.CharacterEquipmentOverlays then YUI.CharacterEquipmentOverlays:Hook(RequestOverlayRefresh) end
    HookFrame(_G.CharacterFrame)
    HookModeTabs(_G.CharacterFrame)
    HookModeTabs(_G.InspectFrame)
    HookFrame(_G.PaperDollFrame)
    if YUI.IsRetail or YUI.IsForever then
        HookFrame(_G.GearManagerPopupFrame)
    end
    HookFrame(_G.ReputationFrame)
    HookFrame(_G.TokenFrame)
    HookFrame(_G.InspectFrame)
    HookFrame(_G.InspectPaperDollFrame)
end

local function HasPendingItem(card, itemID)
    if not IsShown(card) then return false end
    local snapshot = card.equipmentSnapshot
    local slots = snapshot and snapshot.slots
    if not slots then return false end
    for index = 1, #SLOT_DEFINITIONS do
        local slot = slots[index]
        if slot and not IsSecret(slot.pending) and slot.pending == true
            and not IsSecret(slot.itemID) and slot.itemID == itemID
        then
            return true
        end
    end
    return false
end

local function OnRuntimeEvent(event, arg1, arg2)
    if not runtime.enabled then return end
    local probe = _G.YUI_CharacterEquipmentProbe
    if probe then probe("event", event, arg1) end

    if event == "ITEM_DATA_LOAD_RESULT" or event == "GET_ITEM_INFO_RECEIVED" then
        if IsSecret(arg1) or IsSecret(arg2) or type(arg1) ~= "number"
            or arg1 <= 0 or arg1 % 1 ~= 0 or arg2 ~= true
        then return end
        local host, inspecting = ResolveHost()
        if not host or (not inspecting and not IsCharacterPaperDollActive()) then return end
        if (YUI.CharacterEquipmentOverlays and YUI.CharacterEquipmentOverlays:HasPending(arg1))
            or HasPendingItem(runtime.playerCard, arg1)
            or (inspecting and HasPendingItem(runtime.inspectCard, arg1))
        then
            RequestRefresh(0.05, event)
        end
        return
    end

    TryHookFrames()
    if event == "UNIT_INVENTORY_CHANGED" then
        if IsSecret(arg1) then return end
        local inspectUnit = _G.InspectFrame and _G.InspectFrame.unit
        if arg1 ~= "player" and arg1 ~= inspectUnit then return end
    elseif event == "INSPECT_READY" then
        RequestRefresh(0.05, event)
        return
    elseif event == "ADDON_LOADED" then
        RequestRefresh(0.05, event)
        return
    end

    RequestRefresh(nil, event)
end

local function AttachEvents()
    if runtime.eventAttached or not Event or type(Event.On) ~= "function" then return end
    runtime.eventAttached = true

    local events = {
        "ADDON_LOADED",
        "PLAYER_EQUIPMENT_CHANGED",
        "UPDATE_INVENTORY_DURABILITY",
        "BAG_UPDATE_DELAYED",
        "PLAYER_REGEN_ENABLED",
        "UNIT_INVENTORY_CHANGED",
        "PLAYER_AVG_ITEM_LEVEL_UPDATE",
        "PLAYER_SPECIALIZATION_CHANGED",
        "UNIT_STATS",
        "COMBAT_RATING_UPDATE",
        "MASTERY_UPDATE",
        "PLAYER_TALENT_UPDATE",
        "INSPECT_READY",
        "ITEM_DATA_LOAD_RESULT",
        "GET_ITEM_INFO_RECEIVED",
        "PLAYER_TARGET_CHANGED",
        "YUI_WORLD_READY",
    }
    for _, event in ipairs(events) do
        Event:On(event, OnRuntimeEvent, runtime.eventOwner)
    end
end

local function DetachEvents()
    runtime.generation = runtime.generation + 1
    if runtime.refreshTimer then runtime.refreshTimer:Cancel(); runtime.refreshTimer = nil end
    if Event and type(Event.OffOwner) == "function" then
        Event:OffOwner(runtime.eventOwner)
    end
    runtime.eventAttached = false
    runtime.refreshPending = false
end

local function EnsureRuntime()
    if runtime.playerCard then
        AttachEvents()
        TryHookFrames()
        RequestRefresh()
        return
    end

    runtime.playerCard = BuildCard("player")
    runtime.inspectCard = BuildCard("inspect")
    AttachEvents()
    TryHookFrames()
    RequestRefresh()
end

local function SetEnabled(enabled)
    if YUI.CharacterEquipmentOverlays then YUI.CharacterEquipmentOverlays:StopPreview() end
    runtime.enabled = enabled == true
    if runtime.enabled then
        EnsureRuntime()
    else
        DetachEvents()
        if YUI.CharacterEquipmentOverlays then YUI.CharacterEquipmentOverlays:Hide() end
        if runtime.playerCard then runtime.playerCard:Hide() end
        if runtime.inspectCard then runtime.inspectCard:Hide() end
    end
end

local Feature = {
    product = PRODUCT_ID,
    name = T("feature.name", "角色装备观察"),
    description = T("feature.description", "在角色面板右侧显示装备和属性摘要。"),
    default = true,
    settingsMode = "inline",
    assetFolders = { "Components\\CharacterEquipmentInfo\\Media" },
    modSwitchImage = "modswitch\\characterequipmentinfo-bg.png",
    modSwitchImageCrop = false,
    versions = { "forever", "mainline", "wrath" },
    callback = SetEnabled,
}

function Feature:GetSettingsTitleAction()
    return {
        getText = function()
            return T(YUI.CharacterEquipmentOverlays and YUI.CharacterEquipmentOverlays:IsPreviewing() and "preview.stop" or "preview.random")
        end,
        bind = function(button)
            if YUI.CharacterEquipmentOverlays then YUI.CharacterEquipmentOverlays:BindPreviewButton(button) end
        end,
        onClick = function()
            if runtime.enabled and YUI.CharacterEquipmentOverlays then
                if YUI.CharacterEquipmentOverlays:IsPreviewing() then
                    YUI.CharacterEquipmentOverlays:StopPreview()
                    YUI.CharacterEquipmentOverlays:Refresh(GetDB())
                else
                    YUI.CharacterEquipmentOverlays:Preview(GetDB())
                end
            end
        end,
    }
end

function Feature:GetDetailOptions()
    local db = GetDB()
    local function Refresh()
        if Appearance and type(Appearance.Refresh) == "function" then
            if runtime.playerCard then Appearance:Refresh(runtime.playerCard) end
            if runtime.inspectCard then Appearance:Refresh(runtime.inspectCard) end
        end
        RequestRefresh()
    end

    local fontOptions = {}
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    for name, path in pairs(media and media:HashTable("font") or {}) do
        if type(path) == "string" and path ~= "" then
            fontOptions[#fontOptions + 1] = { text = name, value = path }
        end
    end
    for _, path in ipairs({ DEFAULT_FONT, db.textFont, db.numberFont }) do
        local found = false
        for _, option in ipairs(fontOptions) do
            if option.value == path then found = true; break end
        end
        if not found then
            fontOptions[#fontOptions + 1] = { text = path:match("([^\\/]+)$") or path, value = path }
        end
    end
    table.sort(fontOptions, function(a, b) return a.text < b.text end)
    local sizeOptions = {}
    for size = 10, 16 do sizeOptions[#sizeOptions + 1] = { text = tostring(size), value = size } end
    local function FontOptions(role)
        return {
            type = "row",
            children = {
                {
                    type = "dropdown", label = T("settings." .. role .. "_font"), width = 180,
                    options = fontOptions, default = DEFAULT_FONT,
                    get = function() return NormalizeFont(db[role .. "Font"]) end,
                    set = function(value) db[role .. "Font"] = NormalizeFont(value) end,
                    onChange = Refresh,
                },
                {
                    type = "dropdown", label = T("settings." .. role .. "_font_size"), width = 180,
                    tooltip = T("settings.font_size.help"),
                    options = sizeOptions, default = DEFAULT_FONT_SIZE,
                    get = function() return NormalizeFontSize(db[role .. "FontSize"]) end,
                    set = function(value) db[role .. "FontSize"] = NormalizeFontSize(value) end,
                    onChange = Refresh,
                },
            },
        }
    end

    local options = {}
    options[#options + 1] = { type = "divider", label = T("section.summary"), width = 560,
        alignLeft = true, collapsible = true, collapseKey = "equipment.summary", collapsed = true }
    options[#options + 1] = { type = "checkbox", label = T("settings.enabled"),
        get = function() return db.showSummary ~= false end,
        set = function(value) db.showSummary = value == true; Refresh() end }
    local cardOptions = {
        {
            type = "row",
            children = {
                {
                    type = "checkbox",
                    label = T(YUI.IsForever and "settings.show_summary_stats" or "settings.show_secondary", "显示底部属性"),
                    get = function() return db.showSecondaryStats == true end,
                    set = function(value) db.showSecondaryStats = value == true end,
                    onChange = Refresh,
                },
            },
        },
        {
            type = "row",
            children = {
                {
                    type = "dropdown",
                    label = T("settings.equipment_secondary", "装备副属性"),
                    width = 180,
                    options = {
                        { text = T("settings.equipment_secondary.none", "不显示"), value = "none" },
                        { text = T("settings.equipment_secondary.blocks", "色块"), value = "blocks" },
                        { text = T("settings.equipment_secondary.text", "文字"), value = "text" },
                    },
                    default = "blocks",
                    get = function() return GetEquipmentSecondaryStatStyle(db) end,
                    set = function(value)
                        db.equipmentSecondaryStatStyle = NormalizeEquipmentSecondaryStatStyle(value)
                        db.secondaryStatSolidBlocks = false
                    end,
                    onChange = Refresh,
                },
                {
                    type = "dropdown",
                    label = T("settings.theme_style", "皮肤风格"),
                    width = 180,
                    options = {
                        { text = T("settings.theme.auto", "自动"), value = "auto" },
                        { text = T("settings.theme.native", "原生"), value = "native" },
                        { text = T("settings.theme.modern", "现代"), value = "dark" },
                    },
                    default = "auto",
                    get = GetThemeStyle,
                    set = function(value) db.themeStyle = NormalizeThemeStyle(value) end,
                    onChange = Refresh,
                },
            },
        },
        FontOptions("text"),
        FontOptions("number"),
    }
    if YUI.IsForever then table.remove(cardOptions[2].children, 1) end
    for _, option in ipairs(cardOptions) do options[#options + 1] = option end
    if YUI.CharacterEquipmentOverlays then
        local overlayOptions = YUI.CharacterEquipmentOverlays:BuildOptions(db, fontOptions,
            function() if runtime.enabled then YUI.CharacterEquipmentOverlays:Refresh(db) end end)
        for _, option in ipairs(overlayOptions) do options[#options + 1] = option end
    end
    return options
end

function Feature:GetOptions()
    local details = self:GetDetailOptions()
    local sections, current = {}, nil
    for _, option in ipairs(details) do
        if option.type == "divider" then
            current = { id = option.collapseKey, label = option.label, options = {} }
            sections[#sections + 1] = current
        else
            current.options[#current.options + 1] = option
        end
    end
    sections[1].toggle = table.remove(sections[1].options, 1)
    local flyout
    for index = 2, #sections do
        local section = sections[index]
        local sourceFields
        for _, option in ipairs(section.options) do
            if option.fields then sourceFields = option.fields end
        end
        section.toggle = sourceFields[1]
        local fields = {}
        for fieldIndex = 2, math.min(#sourceFields, 8) do fields[#fields + 1] = sourceFields[fieldIndex] end
        if index == 2 then
            flyout = { id = "equipment.flyout", label = T("settings.flyout"), toggle = sourceFields[9],
                fields = { sourceFields[11], sourceFields[12] } }
        end
        section.fields = fields
        section.suppressed = YUI.CharacterEquipmentOverlays:IsSuppressed()
    end
    sections[#sections + 1] = flyout
    local function FieldsOption(fields)
        return { type = "custom", fields = fields, render = function(parent, x, y, width)
            local _, w, h = YUI.Settings:RenderAlignedFields(parent, {
                x = x, y = y, width = width, columns = 1,
                labelWidth = 100, labelGap = 12, bodyWidth = 190,
                valueWidth = 44, valueGap = 8, rowHeight = 30, rowGap = 12, fields = fields,
            })
            for _, field in ipairs(fields) do
                if field.updateVisibility then field.updateVisibility() end
            end
            return w, h
        end }
    end
    for _, section in ipairs(sections) do
        if section.fields then
            section.options = { FieldsOption(section.fields) }
            if section == flyout then
                table.insert(section.options, 1, { type = "text", label = T("settings.flyout_style_shared") })
            end
        end
    end
    local atlases = { "poi-workorders", "UpgradeItem-32x32", "Reagents", "keyflameon-32x32", "Repair", "bags-greenarrow" }
    for index, section in ipairs(sections) do section.atlas = atlases[index] end
    return { { type = "custom", sections = sections, render = function(parent, x, y, width)
        local root = GUI2:CreateFrame(parent, { width = width, height = 380 })
        root:SetPoint("TOPLEFT", x, y)
        local navWidth, gap = 190, 24
        local pageLayout = YUI.Settings.ModulePageLayout or {}
        local inset = pageLayout.insetX or 20
        local body = GUI2:CreateFrame(root, { width = math.max(360, width - navWidth - gap + inset), height = 380 })
        body:SetPoint("TOPLEFT", navWidth + gap - inset, pageLayout.titleTop or 20)
        local separator = GUI2:CreateTexture(root, { layer = "BACKGROUND" })
        separator:SetSize(GUI2.mult or 1, 348)
        separator:SetPoint("TOPLEFT", navWidth + gap / 2, 0)
        GUI2:SetTexturePaintKey(separator, "color.border.default")
        local buttons = {}
        local function Select(section)
            self.settingsSection = section.id
            for id, button in pairs(buttons) do button:SetSelected(id == section.id) end
            YUI.Settings:ClearConfig(body)
            local config = { { type = "divider", label = section.label, alignLeft = true } }
            for _, option in ipairs(section.options) do config[#config + 1] = option end
            YUI.Settings:RenderConfig(body, config)
        end
        for index, section in ipairs(sections) do
            local rowY = -(index - 1) * 40
            local toggle = GUI2:CreateCheckBox(root, { width = 24, height = 32,
                get = section.toggle.get, set = section.toggle.set })
            toggle:SetPoint("TOPLEFT", 8, rowY - 2)
            local button = GUI2:CreateButtonFrame(root, { width = navWidth - 34, height = 36 })
            button:SetPoint("TOPLEFT", 34, rowY)
            local background = GUI2:CreateTexture(button, { layer = "BACKGROUND" })
            background:SetPoint("TOPLEFT", -34, 0)
            background:SetPoint("BOTTOMRIGHT", 0, 0)
            GUI2:SetTexturePaintKey(background, "color.interaction.soft")
            local accent = GUI2:CreateTexture(button, { layer = "ARTWORK" })
            accent:SetSize(2 * (GUI2.mult or 1), 24)
            accent:SetPoint("LEFT", -34, 0)
            GUI2:SetTexturePaintKey(accent, "color.accent.primary")
            local icon = GUI2:CreateTexture(button, { layer = "ARTWORK" })
            icon:SetSize(20, 20)
            icon:SetPoint("LEFT", 2, 0)
            icon:SetAtlas(section.atlas)
            local label = GUI2:CreateText(button, section.label, "font.size.md", "color.text.primary")
            label:SetPoint("LEFT", 30, 0)
            label:SetWidth(navWidth - 68)
            label:SetJustifyH("LEFT")
            function button:SetSelected(selected)
                self.selected = selected
                background:SetShown(selected)
                accent:SetShown(selected)
                GUI2:SetTextColorKey(label, selected and "color.text.accent" or "color.text.primary")
            end
            button:SetScript("OnEnter", function() background:Show() end)
            button:SetScript("OnLeave", function() background:SetShown(button.selected) end)
            button:SetScript("OnClick", function() Select(section) end)
            buttons[section.id] = button
        end
        local selected = sections[1]
        for _, section in ipairs(sections) do
            if section.id == self.settingsSection then selected = section; break end
        end
        Select(selected)
        local contentHeight = math.max(350, body:GetHeight() - (pageLayout.titleTop or 20))
        separator:SetHeight(contentHeight)
        if YUI.CharacterEquipmentOverlays and YUI.CharacterEquipmentOverlays:IsSuppressed() then
            local status = GUI2:CreateText(root, T("settings.compatibility_footer"), "font.size.sm", "color.text.secondary")
            status:SetPoint("TOPLEFT", 0, -contentHeight - 20)
            status:SetWidth(width)
            status:SetJustifyH("LEFT")
            status:SetWordWrap(true)
            contentHeight = contentHeight + 64
        end
        root:SetHeight(contentHeight)
        return width, contentHeight
    end } }
end

function Feature:GetSubFeatureStates()
    local db = Components:CopyConfigSnapshot(CONFIG_KEY, DEFAULTS, PRODUCT_ID)
    if not db then return {} end
    return {
        { label = T("section.summary"), enabled = db.showSummary ~= false },
        { label = T("section.level"), enabled = db.slotItemLevel ~= false },
        { label = T("section.enchant"), enabled = db.slotEnchant ~= false },
        { label = T("section.gems"), enabled = db.slotGems ~= false },
        { label = T("section.durability"), enabled = db.slotDurability ~= false },
        { label = T("settings.flyout"), enabled = db.slotFlyout ~= false },
    }
end

function Feature:OnSettingsLeave()
    if YUI.CharacterEquipmentOverlays and YUI.CharacterEquipmentOverlays:IsPreviewing() then
        YUI.CharacterEquipmentOverlays:StopPreview()
        RequestRefresh()
    end
end

Components:RegisterFeature(FEATURE_KEY, Feature)

local _, addonTable = ...
local YUI = _G.YUI or addonTable
if not YUI or not YUI.IsForever then return end

local GUI = YUI.GUI2
local PaperDoll = YUI.API.PaperDoll
local Talent = YUI.API.Talent
local Unit = YUI.API.Unit
local Security = YUI.API.Security
local Icons = YUI.API.Icons
local GetStatIcon = Icons and Icons.GetCharacterStatIcon
local STAT_ICON_SIZE, STAT_ICON_GAP = 16, 4
local Summary = { StatIDs = { "forever_1", "forever_2", "forever_3", "forever_4", "forever_5", "forever_6" } }
YUI.CharacterEquipmentSummaryForever = Summary
local Locale = YUI.Locale:Get("CharacterEquipmentInfo")
local CoreLocale = YUI.Locale:Get("Core")
local Unpack = unpack or table.unpack
local function T(key) return Locale[key] or key end
local function Secret(value)
    local check = Security and Security.IsSecretValue or issecretvalue
    return type(check) == "function" and check(value) == true
end
local function UnitGUID(unit)
    if Secret(unit) or type(unit) ~= "string" or not (Unit and Unit.UnitGUID) then return end
    local ok, value = pcall(Unit.UnitGUID, unit)
    if ok and not Secret(value) and type(value) == "string" then return value end
end
local function Number(value)
    return not Secret(value) and type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
local function Format(value)
    if not Number(value) then return T("value.unavailable") end
    local result = string.format("%.1f", math.floor(value * 10) / 10)
    return (result:gsub("%.0$", ""))
end
Summary.Format = Format

local colors = {
    str = { 1, .333, .333 }, agi = { .333, 1, .333 }, sta = { 1, 1, 1 },
    int = { .2, .6, 1 }, spirit = { .4, 1, .8 }, armor = { .8, .667, .467 },
    ap = { 1, .333, .333 }, rap = { 1, .333, .333 }, healing = { .533, .933, .6 },
    hit = { .447, .878, .922 }, crit = { 1, .6, 0 }, spell = { .773, .596, 1 },
    mp5 = { .4, .729, 1 }, defense = { .918, .843, .675 },
    block_value = { .722, .588, .894 }, expertise = { 1, .8, .467 },
}
local definitions = {}
local function Define(id, color, nameKey, shortKey)
    definitions[id] = { id = id, color = colors[color], nameKey = nameKey or ("summary.name." .. id),
        shortKey = shortKey or ("summary.short." .. id) }
end
for _, id in ipairs({ "str", "agi", "sta", "int", "spirit", "armor" }) do Define(id, id, "stat." .. id, "stat." .. id) end
for _, id in ipairs({ "ap", "rap", "healing", "mp5", "defense", "block_value", "expertise" }) do Define(id, id) end
for _, attack in ipairs({ "melee", "ranged", "spell" }) do
    Define("hit_" .. attack, "hit", nil, "summary.short.hit")
    Define("crit_" .. attack, "crit", nil, "summary.short.crit")
end
for _, school in ipairs({ "holy", "fire", "frost", "shadow", "arcane", "nature" }) do
    Define("sp_" .. school, "spell", nil, "summary.short.spell")
end
Summary.Definitions = definitions

local profiles = {}
local function Profile(class, index, rows, core)
    profiles[class] = profiles[class] or {}
    profiles[class][index] = { rows = rows, core = core or {} }
end
local melee = { "ap", "str", "sta", "hit_melee", "crit_melee", "expertise" }
local tank = { "sta", "armor", "defense", "str", "block_value", "hit_melee" }
local healing = { "healing", "int", "spirit", "mp5", "sta", "crit_spell" }
local function Caster(school) return { "sp_" .. school, "int", "hit_spell", "crit_spell", "spirit", "sta" } end
Profile("WARRIOR", 0, { "str", "sta", "armor", "hit_melee", "crit_melee", "defense" }, { str = true })
Profile("WARRIOR", 1, melee, { ap = true }); Profile("WARRIOR", 2, melee, { ap = true }); Profile("WARRIOR", 3, tank, { sta = true, armor = true })
Profile("PALADIN", 0, { "str", "int", "sta", "crit_melee", "sp_holy", "healing" }, { str = true })
Profile("PALADIN", 1, healing, { healing = true }); Profile("PALADIN", 2, tank, { sta = true, armor = true })
Profile("PALADIN", 3, { "str", "int", "sta", "hit_melee", "crit_melee", "sp_holy" }, { str = true })
Profile("HUNTER", 0, { "agi", "sta", "rap", "hit_ranged", "crit_ranged", "int" }, { agi = true })
Profile("HUNTER", 1, { "rap", "agi", "hit_ranged", "crit_ranged", "sta", "int" }, { rap = true })
Profile("HUNTER", 2, profiles.HUNTER[1].rows, { rap = true })
Profile("HUNTER", 3, { "ap", "agi", "sta", "hit_melee", "crit_melee", "expertise" }, { ap = true })
Profile("ROGUE", 0, { "agi", "str", "sta", "hit_melee", "crit_melee", "ap" }, { agi = true })
for index = 1, 3 do Profile("ROGUE", index, { "ap", "agi", "hit_melee", "crit_melee", "str", "sta" }, { ap = true }) end
Profile("PRIEST", 0, { "int", "spirit", "sta", "healing", "sp_holy", "crit_spell" }, { int = true })
Profile("PRIEST", 1, healing, { healing = true }); Profile("PRIEST", 2, healing, { healing = true }); Profile("PRIEST", 3, Caster("shadow"), { sp_shadow = true })
Profile("SHAMAN", 0, { "str", "int", "sta", "sp_nature", "healing", "crit_spell" }, { int = true })
Profile("SHAMAN", 1, Caster("nature"), { sp_nature = true })
Profile("SHAMAN", 2, { "ap", "sp_nature", "str", "hit_melee", "crit_melee", "hit_spell" }, { ap = true, sp_nature = true })
Profile("SHAMAN", 3, healing, { healing = true })
Profile("MAGE", 0, { "int", "sta", "sp_arcane", "hit_spell", "crit_spell", "spirit" }, { int = true })
for index, school in ipairs({ "arcane", "fire", "frost" }) do Profile("MAGE", index, Caster(school), { ["sp_" .. school] = true }) end
Profile("WARLOCK", 0, { "int", "sta", "sp_shadow", "hit_spell", "crit_spell", "spirit" }, { int = true })
Profile("WARLOCK", 1, Caster("shadow"), { sp_shadow = true }); Profile("WARLOCK", 2, Caster("shadow"), { sp_shadow = true }); Profile("WARLOCK", 3, Caster("fire"), { sp_fire = true })
Profile("DRUID", 0, { "agi", "int", "sta", "sp_nature", "healing", "spirit" }, { int = true })
Profile("DRUID", 1, Caster("nature"), { sp_nature = true })
Profile("DRUID", 2, { "agi", "sta", "str", "armor", "hit_melee", "crit_melee" }, { agi = true, sta = true })
Profile("DRUID", 3, healing, { healing = true })
Summary.Profiles = profiles

-- TalentTab order and textures from wowf 1.60.1.70938, matching the approved preview.
local icons = {
    WARRIOR = { 132292, 132347, 134952 }, PALADIN = { 135920, 135893, 135873 }, HUNTER = { 132164, 132222, 132215 },
    ROGUE = { 132292, 132090, 132320 }, PRIEST = { 135987, 237542, 136207 }, SHAMAN = { 136048, 136051, 136052 },
    MAGE = { 135932, 135810, 135846 }, WARLOCK = { 136145, 136172, 136186 }, DRUID = { 136096, 132276, 136041 },
}
local schoolDetails = {
    PALADIN = { "sp_holy" }, PRIEST = { "sp_holy", "sp_shadow" }, SHAMAN = { "sp_nature", "sp_fire", "sp_frost" },
    MAGE = { "sp_arcane", "sp_fire", "sp_frost" }, WARLOCK = { "sp_shadow", "sp_fire" }, DRUID = { "sp_nature", "sp_arcane" },
}
local function TreeName(class, index)
    return CoreLocale["talent.configuration." .. class:lower() .. "." .. index] or T("value.unknown")
end
local tooltip, tooltipCard, hoveredRow, pinnedRow, escapeCloseFrame
local ESCAPE_FRAME_NAME = "YUIEquipmentSummaryEscape"
local function Highlight(row, shown) if row and row.summaryHighlight then row.summaryHighlight:SetShown(shown == true) end end
local function ClearTooltipState()
    Highlight(hoveredRow, false)
    hoveredRow, pinnedRow, tooltipCard = nil, nil, nil
    if escapeCloseFrame and escapeCloseFrame:IsShown() then escapeCloseFrame:Hide() end
end
function Summary:HideTooltip(card)
    if card and tooltipCard ~= card then return end
    ClearTooltipState()
    if tooltip then tooltip:Hide() end
end
local function ShowEscapeClose()
    if type(UISpecialFrames) ~= "table" then return end
    if not escapeCloseFrame then
        -- One reusable invisible close target, active only while pinned.
        -- Do not mutate UISpecialFrames from the native CloseSpecialWindows loop.
        escapeCloseFrame = GUI:CreateFrame(UIParent, { name = ESCAPE_FRAME_NAME, width = 1, height = 1 })
        escapeCloseFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        escapeCloseFrame:SetAlpha(0)
        escapeCloseFrame:EnableMouse(false)
        escapeCloseFrame:Hide()
        escapeCloseFrame:SetScript("OnHide", function()
            if pinnedRow then Summary:HideTooltip() end
        end)
        table.insert(UISpecialFrames, ESCAPE_FRAME_NAME)
    end
    if not escapeCloseFrame:IsShown() then escapeCloseFrame:Show() end
end
local function Tooltip(owner, card)
    if not tooltip then
        tooltip = CreateFrame("GameTooltip", "YUIEquipmentSummaryTooltip", UIParent, "GameTooltipTemplate")
        tooltip:HookScript("OnHide", ClearTooltipState)
    end
    tooltip:SetOwner(owner, "ANCHOR_RIGHT")
    tooltip:ClearLines()
    tooltipCard = card
    return tooltip
end
local function SimpleTooltip(owner, card, title, note)
    if pinnedRow then return end
    local tip = Tooltip(owner, card)
    tip:SetText(title)
    tip:AddLine(" ")
    tip:AddLine(note, .75, .82, .9, true)
    tip:Show()
end
local function ShowStat(row, force, pin)
    if pinnedRow and not force then return end
    local wasPinned = pinnedRow == row
    local card, id = row.summaryCard, row.summaryID
    local definition = definitions[id]
    if not definition then return end
    Highlight(hoveredRow, false)
    local tip = Tooltip(row, card)
    if pin or wasPinned then pinnedRow = row end
    hoveredRow = row
    Highlight(row, true)
    local color = definition.color
    tip:AddDoubleLine(T(definition.nameKey), row.summaryText, color[1], color[2], color[3], color[1], color[2], color[3])
    tip:AddLine(" ")
    tip:AddDoubleLine(T("summary.equipment_total"), row.summaryText, .85, .88, .92, 1, 1, 1)
    local baseline = card.foreverComparisonTotals
    local previous = baseline and baseline.complete and baseline.values[id]
    if Number(row.summaryValue) and Number(previous) and card.secondaryTotals.complete then
        local delta = row.summaryValue - previous
        tip:AddDoubleLine(T("summary.compare_self"), (delta > 0 and "+" or "") .. Format(delta),
            .85, .88, .92, delta < 0 and 1 or .4, delta > 0 and 1 or .5, .5)
    end
    if id == "ap" then
        tip:AddDoubleLine(T("summary.equipment_strength"), Format(card.secondaryTotals.values.str), .85, .88, .92, Unpack(colors.str))
    elseif id:sub(1, 3) == "sp_" then
        for _, other in ipairs(schoolDetails[card.classToken] or {}) do
            if other ~= id then
                tip:AddDoubleLine(T(definitions[other].nameKey), Format(card.secondaryTotals.values[other]), .85, .88, .92, Unpack(colors.spell))
            end
        end
    end
    tip:AddLine(" ")
    tip:AddLine(T("summary.equipment_only"), .75, .82, .9, true)
    tip:AddLine(" ")
    tip:AddLine(T(pinnedRow == row and "summary.unpin_hint" or "summary.pin_hint"), 1, 1, 1)
    local value = _G.YUIEquipmentSummaryTooltipTextRight1
    if value and value.GetFont then
        if not tooltip.summaryValueFont then tooltip.summaryValueFont = { value:GetFont() } end
        local font = tooltip.summaryValueFont
        value:SetFont(font[1], math.max(font[2] + 2, font[2] * 1.2), font[3])
    end
    tip:Show()
    if pinnedRow == row then ShowEscapeClose() end
end

function Summary:Build(card, helpers)
    card.foreverSummaryHelpers = helpers
    card.foreverSummaryHeader = GUI:CreateFrame(card, { width = 240, height = 24 })
    local header = card.foreverSummaryHeader
    header.label = helpers.CreateText(header, T("stats.summary_title"), "font.size.sm", "color.text.secondary")
    header.label:SetPoint("LEFT", header, "LEFT", 0, 0)
    card.themeTexts[#card.themeTexts + 1] = header.label
    header.buttons = {}
    for index = 1, 3 do
        local button = GUI:CreateIconSlot(header, { size = 20, icon = 134400, variant = "bare", shape = "circle", border = "thin", clicks = "LeftButtonUp",
            selectedBorderColor = { .945, .804, .439, 1 }, animate = false,
            onClick = function()
                Summary:HideTooltip(card)
                card.foreverManualTree = index
                helpers.Refresh(card)
            end })
        button:SetPoint("RIGHT", header, "RIGHT", -(3 - index) * 25, 0)
        button:HookScript("OnEnter", function() SimpleTooltip(button, card, TreeName(card.classToken, index), T("summary.spec_hint")) end)
        button:HookScript("OnLeave", function() if not pinnedRow then Summary:HideTooltip(card) end end)
        header.buttons[index] = button
    end
    for _, key in ipairs(self.StatIDs) do
        local row = helpers.CreateStatRow(card, { id = key, category = "primary" })
        row.summaryCard = card
        row.summaryHighlight = GUI:CreateTexture(row, { layer = "BACKGROUND" })
        GUI:SetTexturePaintKey(row.summaryHighlight, "color.control.hover")
        row.summaryHighlight:SetAllPoints(row)
        row.summaryHighlight:SetAlpha(.18)
        row.summaryHighlight:Hide()
        row:SetScript("OnEnter", function() ShowStat(row) end)
        row:SetScript("OnLeave", function() if not pinnedRow then Summary:HideTooltip(card) end end)
        row:SetScript("OnMouseUp", function(_, mouseButton)
            if mouseButton ~= "LeftButton" then return end
            if pinnedRow == row then Summary:HideTooltip(card); return end
            Summary:HideTooltip()
            ShowStat(row, true, true)
        end)
        card.statRows[key] = row
        card.themeTexts[#card.themeTexts + 1] = row.label
        card.themeTexts[#card.themeTexts + 1] = row.value
        card.themeTexts[#card.themeTexts + 1] = row.comparison
    end
    card:HookScript("OnHide", function() Summary:HideTooltip(card) end)
end

function Summary:ResetInspection(card)
    if not card then return end
    card.foreverInspectReadyGUID, card.foreverDetectedTree = nil, nil
    card.foreverTalentDirty = true
end
function Summary:InspectReady(card, guid)
    if not card or Secret(guid) or type(guid) ~= "string" then return end
    local host = _G.InspectFrame
    -- Native OnEvent shows the window after this response; OnHide clears unit.
    if not host or UnitGUID(host.unit) ~= guid then return end
    card.foreverInspectReadyGUID = guid
    card.foreverTalentDirty = true
end
function Summary:InspectShown(card)
    local host = _G.InspectFrame
    -- Recover a matching completion missed while disabled. In this client the
    -- native window is shown only after its INSPECT_READY handler succeeds.
    if host and host:IsShown() then self:InspectReady(card, UnitGUID(host.unit)) end
end
function Summary:InvalidateTalents(card) if card then card.foreverTalentDirty = true end end
function Summary:Update(card, isInspect, comparisonTotals)
    local unit = card.equipmentSnapshot.unit
    local guid = UnitGUID(unit)
    if not guid or card.foreverUnitGUID ~= guid or card.foreverClass ~= card.classToken then
        self:HideTooltip(card)
        card.foreverUnitGUID, card.foreverClass = guid, card.classToken
        card.foreverManualTree, card.foreverDetectedTree, card.foreverTalentDirty = nil, nil, true
        if card.foreverInspectReadyGUID ~= guid then card.foreverInspectReadyGUID = nil end
    end
    -- A missing link is only a known empty slot after this inspection is ready.
    -- Reuse the adapter's unavailable path to clear all previous/partial totals.
    local inspectReady = not isInspect or (guid ~= nil and card.foreverInspectReadyGUID == guid)
    local snapshot = PaperDoll.ReadEquipmentSummaryTotals(inspectReady and card.equipmentSnapshot or nil, card.secondaryTotals)
    if not inspectReady and guid then snapshot.pending = true end
    card.secondaryTotals, card.statsAvailable = snapshot, true
    card.foreverComparisonTotals = isInspect and comparisonTotals or nil
    if card.foreverTalentDirty then
        card.foreverTalentDirty = false
        local getter = not isInspect and Talent and Talent.GetCurrentConfigurationSpecializationInfo
            or (guid and card.foreverInspectReadyGUID == guid and Talent and Talent.GetInspectConfigurationSpecializationInfo)
        local ok, info = false, nil
        if getter then ok, info = pcall(getter, unit) end
        local index = ok and not Secret(info) and type(info) == "table" and info.treeIndex
        card.foreverDetectedTree = Number(index) and index % 1 == 0 and index >= 1 and index <= 3
            and Number(info.points) and info.points > 0 and index or nil
    end
    local classProfiles = profiles[card.classToken] or profiles.WARRIOR
    local index = card.foreverManualTree or card.foreverDetectedTree or 0
    card.foreverProfile = classProfiles[index] or classProfiles[0]
    local classIcons = icons[card.classToken]
    for tree, button in ipairs(card.foreverSummaryHeader.buttons) do
        if classIcons then
            if button.summaryIcon ~= classIcons[tree] then
                button.summaryIcon = classIcons[tree]
                button.icon:SetTexture(button.summaryIcon)
            end
            local selected = tree == index
            if button.summarySelected ~= selected then
                button:SetSelected(selected)
                button:SetAlpha(selected and 1 or .45)
                button.summarySelected = selected
            end
            button:Show()
        else button:Hide() end
    end
    for position, key in ipairs(self.StatIDs) do
        local row = card.statRows[key]
        local id = card.foreverProfile.rows[position]
        if row.summaryID ~= id then self:HideTooltip(card) end
        local definition = definitions[id]
        row.summaryID, row.summaryValue = id, snapshot.values[id]
        row.summaryText = snapshot.pending and T("item.loading") or Format(row.summaryValue)
        row.label:SetText(T(card.classToken == "SHAMAN" and index == 2 and id == "hit_spell" and "summary.short.spell_hit" or definition.shortKey))
        row.value:SetText(row.summaryText)
        row._visible, row._comparisonVisible = true, false
        row.comparison:Hide()
    end
    card.statsNotice:Hide()
    if hoveredRow and tooltipCard == card then ShowStat(hoveredRow, true) end
end

function Summary:GetHeight(db)
    local rowHeight = math.max(23, math.ceil(math.max(db.textFontSize or 13, (db.numberFontSize or 13) * 1.2)) + 5)
    return 29 + rowHeight * 3, rowHeight
end

function Summary:GetIconSpace(db)
    return GetStatIcon and db.showSummaryIcons ~= false and STAT_ICON_SIZE + STAT_ICON_GAP or 0
end

local function LayoutStatIcon(row, iconSpace)
    local texture = iconSpace > 0 and GetStatIcon(row.summaryID)
    local icon = row.summaryStatIcon
    if texture then
        if not icon then
            icon = GUI:CreateIconSlot(row, {
                size = STAT_ICON_SIZE, icon = texture, variant = "bare",
                shape = "roundedSquare", border = "shade", zoom = 0.08, animate = false,
            })
            icon:SetPoint("LEFT", row, "LEFT", 0, 0)
            icon:EnableMouse(false)
            row.summaryStatIcon, row.summaryIconTexture = icon, texture
        elseif row.summaryIconTexture ~= texture then
            icon:SetIcon(texture)
            row.summaryIconTexture = texture
        end
        icon:Show()
    elseif icon then
        icon:Hide()
    end

    local inset = texture and iconSpace or 0
    if row.summaryLabelInset ~= inset then
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", row, "LEFT", inset, 0)
        row.summaryLabelInset = inset
    end
    return inset
end

function Summary:Layout(card, top, db)
    local enabled = db.showSecondaryStats == true
    card.foreverSummaryHeader:SetShown(enabled)
    if not enabled then
        for _, key in ipairs(self.StatIDs) do card.statRows[key]:Hide() end
        self:HideTooltip(card)
        card.statsNotice:Hide()
        return false
    end
    local inset = card.contentInset or 12
    local width = card:GetWidth() - inset * 2
    local columnWidth = (width - 10) / 2
    local iconSpace = self:GetIconSpace(db)
    local _, rowHeight = self:GetHeight(db)
    local header = card.foreverSummaryHeader
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", card, "TOPLEFT", inset, top)
    header:SetSize(width, 24)
    header.label:SetWidth(math.max(1, width - 80))
    for position, key in ipairs(self.StatIDs) do
        local row = card.statRows[key]
        local definition = definitions[row.summaryID]
        local column, line = (position - 1) % 2, math.floor((position - 1) / 2)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", card, "TOPLEFT", inset + column * (columnWidth + 10), top - 29 - line * rowHeight)
        row:SetSize(columnWidth, rowHeight)
        local path, _, flags = row.value:GetFont()
        local core = card.foreverProfile and card.foreverProfile.core[row.summaryID]
        local size = (card._numberSize or db.numberFontSize or 13) * (core and 1.2 or 1)
        row.value:SetFont(path, math.min(rowHeight - 3, size), flags)
        row.value:ClearAllPoints()
        row.value:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        local valueWidth = math.max(48, row.value:GetUnboundedStringWidth())
        row.value:SetWidth(math.min(columnWidth - 4, valueWidth))
        local labelInset = LayoutStatIcon(row, iconSpace)
        row.label:SetWidth(math.max(1, columnWidth - labelInset - row.value:GetWidth() - 4))
        if definition then
            row.label:SetTextColor(Unpack(definition.color))
            row.value:SetTextColor(Unpack(definition.color))
        end
        row:Show()
    end
    card.statsNotice:Hide()
    return true
end

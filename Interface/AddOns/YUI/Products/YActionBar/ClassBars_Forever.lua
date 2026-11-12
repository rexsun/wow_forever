local YUI = _G.YUI
local YAB = YUI and YUI.YActionBar
if not (YAB and YAB.Client and YAB.Client.classBars == true) then return end

local Bars = { active = {}, pool = {}, states = {}, configDirty = {}, structureDirty = true,
    pending = false, passes = 0, nativeFrames = setmetatable({}, { __mode = "k" }),
    totems = { main = {}, panels = {}, choices = {}, bindings = {}, bindingByCommand = {},
        states = {}, spellLists = {}, selected = {} },
    petUtilities = { pool = {}, states = {}, buttons = {} } }
YAB.ClassBars = Bars
local Spell = YUI.API.Spell
local Item = YUI.API.Item
local Unit = YUI.API.Unit
local Security = YUI.API.Security
Bars.mageCastEvents = { UNIT_SPELLCAST_SENT = true, UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true }
Bars.events = { "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UPDATE_BINDINGS",
    "UNIT_AURA", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "UPDATE_MULTI_CAST_ACTIONBAR",
    "UNIT_PET", "UNIT_HAPPINESS", "UNIT_NAME_UPDATE",
    "PET_BAR_UPDATE", "PET_BAR_UPDATE_COOLDOWN", "PET_BAR_UPDATE_USABLE",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_UPDATE_STATE", "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_USABLE",
    "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "SKILL_LINES_CHANGED", "GET_ITEM_INFO_RECEIVED", "PLAYER_LEVEL_UP",
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }
local COMMON_EVENTS = { SPELLS_CHANGED = true, PLAYER_ENTERING_WORLD = true,
    PLAYER_REGEN_ENABLED = true, UPDATE_BINDINGS = true }
local MAGE_EVENTS = { UNIT_AURA = true, SPELL_UPDATE_COOLDOWN = true, SPELL_UPDATE_USABLE = true,
    BAG_UPDATE_DELAYED = true, BAG_UPDATE_COOLDOWN = true, SKILL_LINES_CHANGED = true,
    GET_ITEM_INFO_RECEIVED = true, PLAYER_LEVEL_UP = true }
local ASPECT_EVENTS = { UNIT_AURA = true, SPELL_UPDATE_COOLDOWN = true, SPELL_UPDATE_USABLE = true,
    UNIT_PET = true, UNIT_HAPPINESS = true, UNIT_NAME_UPDATE = true,
    PET_BAR_UPDATE = true, PET_BAR_UPDATE_COOLDOWN = true, PET_BAR_UPDATE_USABLE = true }
local TOTEM_EVENTS = { UPDATE_MULTI_CAST_ACTIONBAR = true, SPELL_UPDATE_COOLDOWN = true,
    SPELL_UPDATE_USABLE = true, ACTIONBAR_SLOT_CHANGED = true, ACTIONBAR_UPDATE_STATE = true,
    ACTIONBAR_UPDATE_COOLDOWN = true, ACTIONBAR_UPDATE_USABLE = true }

local PET_HAPPINESS = {
    [1] = { key = "pet_utilities.unhappy", hex = "ffff3333", color = { 1, 0.2, 0.2, 1 } },
    [2] = { key = "pet_utilities.content", hex = "ffffd100", color = { 1, 0.82, 0, 1 } },
    [3] = { key = "pet_utilities.happy", hex = "ff33ff33", color = { 0.2, 1, 0.2, 1 } },
}

-- Ordered rank families, validated against the Forever 1.60.1.70532 client.
-- Optional families are offered only when the player actually knows one.
Bars.aspectFamilies = {
    { 13163 },
    { 13165, 14318, 14319, 14320, 14321, 14322, 25296 },
    { 5118 },
    { 13161, 1299445, 1299446, 1299447 },
    { 13159 },
    { 20043, 20190 },
    { 34074, 415423, optional = true },
    { 469145, optional = true },
}
-- SpellMisc ActiveIconFileDataID is shared by every supported aspect rank.
Bars.aspectActiveTexture = 136116
Bars.petUtilityAbsentTexture = 132161

-- Player spells, not pet action slots. Only learned families are presented.
Bars.petUtilityFamilies = {
    { 883 }, { 2641 }, { 982 },
    { 136, 3111, 3661, 3662, 13542, 13543, 13544 },
    { 6991 }, { 1515 },
}

local function InCombat() return YAB.Adapter:InCombat() end
local function Config(id) return YAB.ClassTools:GetConfig(id) end
local function Text(key) return YUI.Locale:Get("YActionBar")[key] end
local function Number(value) return Security.SafeNumber(value) end
local function Boolean(value) return Security.SafeBoolean(value) end

function Bars:Owns(id) return id == "aspects" or id == "totems" or id == "mageTools" or id == "classTools" end

function Bars:ConsumesEvent(event)
    if self.mageCastEvents[event] then
        return self.active.mageTools == true and Config("mageTools").mageScroll ~= false
    end
    return (self.active.mageTools == true and (MAGE_EVENTS[event] == true or COMMON_EVENTS[event] == true))
        or ((self.active.aspects or self.active.totems) and COMMON_EVENTS[event] == true)
        or (self.active.aspects == true and ASPECT_EVENTS[event] == true)
        or (self.active.totems == true and TOTEM_EVENTS[event] == true)
end

local function ResolveKnownFamily(family)
    for rank = #family, 1, -1 do
        if Spell.GetKnownState(family[rank]) == true then return family[rank], true end
    end
    return family[1], false
end

function Bars:ResolveAspect(family) return ResolveKnownFamily(family) end

function Bars:GetAspectOrder(config)
    local order, seen = {}, {}
    local saved = config and config.aspectOrder
    for position = 1, #self.aspectFamilies do
        local index = type(saved) == "table" and saved[position]
        if type(index) == "number" and index % 1 == 0 and self.aspectFamilies[index] and not seen[index] then
            order[#order + 1], seen[index] = index, true
        end
    end
    for index = 1, #self.aspectFamilies do
        if not seen[index] then order[#order + 1] = index end
    end
    return order
end

function Bars:GetAspectPreview(position, config)
    local count = 0
    for _, index in ipairs(self:GetAspectOrder(config)) do
        local family = self.aspectFamilies[index]
        local spellID, known = self:ResolveAspect(family)
        if known or (not family.optional and config.showUnlearned) then
            count = count + 1
            if count == position then return spellID, known, index end
        end
    end
    return nil, nil, count
end

-- Inert settings samples, independent of the current character's spellbook.
local TOTEM_PREVIEW_SPELLS = { 66842, 3599, 8071, 5394, 8512, 36936 }
function Bars:GetSampleSpellID(id, position, config)
    if YAB.ClassTools then id = YAB.ClassTools:GetPreviewBarId(id) end
    if id == "mageTools" then return YAB.MageTools:GetSampleSpellID(position, config) end
    if id == "totems" then return TOTEM_PREVIEW_SPELLS[position] end
    if id ~= "aspects" then return nil end
    if position == 7 then return 883 end
    local count = 0
    for _, index in ipairs(self:GetAspectOrder(config)) do
        local family = self.aspectFamilies[index]
        if not family.optional then
            count = count + 1
            if count == position then return family[1] end
        end
    end
end

local function PetStatus()
    if not Unit.Exists("pet") then return nil, nil, false end
    return Security.SafeString(Unit.Name("pet")), Unit.GetPetHappiness(), true
end

local function PetUtilityTooltip(name, happiness)
    if YAB:GetDB().interaction.tooltipMode == "outOfCombat" and InCombat() then
        GameTooltip:Hide()
        return
    end
    GameTooltip:SetText(Text("pet_utilities.title"))
    GameTooltip:AddLine(" ")
    if name then
        local attitude = PET_HAPPINESS[happiness]
        local status = attitude and (" |c" .. attitude.hex .. Text(attitude.key) .. "|r") or ""
        GameTooltip:AddLine(name .. status, 1, 1, 1)
        local foods = Unit.GetPetFoodTypes()
        if foods then
            local foodText = "|cffffffff" .. table.concat(foods, ", ") .. "|r"
            GameTooltip:AddLine(string.format(Text("pet_utilities.food"), foodText), 1, 0.82, 0, true)
        end
        GameTooltip:AddLine(" ")
    end
    local key = Bars.petUtilities.panel:IsShown() and "pet_utilities.collapse" or "pet_utilities.expand"
    GameTooltip:AddLine(Text(key), 1, 1, 1)
    GameTooltip:Show()
end

local function Enter(button)
    if not Bars.active.aspects then return end
    local interaction = YAB:GetDB().interaction
    if interaction.tooltipMode == "outOfCombat" and InCombat() then return end
    local utilities = Bars.petUtilities
    local entry = Bars.states[button] or utilities.states[button]
    if not entry and button ~= utilities.toggle then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if button == utilities.toggle then
        PetUtilityTooltip(PetStatus())
        return
    end
    GameTooltip:SetSpellByID(entry.spellID)
    if not entry.known then
        local level = Spell.GetLevelLearned and Spell.GetLevelLearned(entry.spellID)
        if level then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format(Text("class_bars.learn_level"), level), 1, 0.2, 0.2)
        end
    end
    GameTooltip:Show()
end

local function Leave(button)
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

function Bars:CancelAspectDrag()
    local button = self.dragButton
    self.dragButton = nil
    if button then button:SetAlpha(self.dragAlpha or 1) end
    self.dragAlpha = nil
end

function Bars:SwapAspects(first, second)
    if InCombat() or not self.active.aspects or first == second
        or not self.aspectFamilies[first] or not self.aspectFamilies[second] then return false end
    local config = Config("aspects")
    local order, firstPosition, secondPosition = self:GetAspectOrder(config)
    for position, index in ipairs(order) do
        if index == first then firstPosition = position end
        if index == second then secondPosition = position end
    end
    order[firstPosition], order[secondPosition] = second, first
    YAB:GetDB().specialBars.aspects.aspectOrder = order
    YAB.ClassTools:Invalidate()
    if YAB.ConfigSets then YAB.ConfigSets:SaveActiveSetting("aspects", "aspectOrder", order, "aspect-reorder", self) end
    self.structureDirty = true
    self:Refresh("aspects")
    return true
end

local function AspectDragStart(button)
    local record = YAB.BarManager.bars.aspects
    if InCombat() or not Bars.active.aspects or not record or record.classBarEditing
        or (YAB.KeybindMode and YAB.KeybindMode.active) or not IsModifiedClick("PICKUPACTION")
        or (GetCursorInfo and GetCursorInfo() ~= nil) then return end
    Bars:CancelAspectDrag()
    Bars.dragButton, Bars.dragAlpha = button, Number(button:GetAlpha()) or 1
    button:SetAlpha(Bars.dragAlpha * 0.5)
    Leave(button)
end

local function AspectDragStop(button)
    if Bars.dragButton ~= button then return end
    local target
    local record = YAB.BarManager.bars.aspects
    if not InCombat() and record then
        for _, candidate in ipairs(record.buttons) do
            if candidate ~= button and candidate:IsMouseOver() then target = candidate; break end
        end
    end
    Bars:CancelAspectDrag()
    if target then
        local factory = YAB.SecureFactory
        Bars:SwapAspects(factory:GetButtonMeta(button).index, factory:GetButtonMeta(target).index)
    end
end

local function AspectHidden(button)
    if Bars.dragButton == button then Bars:CancelAspectDrag() end
end

local function Edit(record, editing)
    editing = editing == true
    if record.classBarEditing == editing then return end
    record.classBarEditing = editing
    if record.id == "totems" then Bars:CloseTotemFlyout() end
    Bars.structureDirty = true
    Bars.configDirty[record.id] = true
    if not record.classBarLayoutTransition then Bars:Refresh(record.id) end
end

function Bars:EnsureRecord(id)
    local manager = YAB.BarManager
    local record = manager.bars[id]
    if record then return record end
    record = { id = id, kind = id, buttons = {}, classBarEditing = false }
    local holder, reason = manager:PrepareFrames(record, id, Config(id), false)
    if not holder then return nil, reason end
    record.onEnterEditMode = function() Edit(record, true) end
    record.onExitEditMode = function() Edit(record, false) end
    record.onEditModeFilterChanged = function(_, visible) Edit(record, visible) end
    manager.bars[id] = record
    YAB.LayoutBridge:Register(id, record, Text("bar." .. id), Config(id))
    return record
end

function Bars:BuildAspects(record, config)
    self:CancelAspectDrag()
    local manager, factory = YAB.BarManager, YAB.SecureFactory
    record.buttons = {}
    for _, index in ipairs(self:GetAspectOrder(config)) do
        local family = self.aspectFamilies[index]
        local spellID, known = self:ResolveAspect(family)
        local visible = known or (not family.optional and (config.showUnlearned or record.classBarEditing))
        local button = self.pool[index]
        if visible then
            if not button then
                button = factory:CreateClassSpellButton(record.holder, index)
                button:SetScript("OnEnter", Enter)
                button:SetScript("OnLeave", Leave)
                button:RegisterForDrag("LeftButton")
                button:SetScript("OnDragStart", AspectDragStart)
                button:SetScript("OnDragStop", AspectDragStop)
                button:SetScript("OnHide", AspectHidden)
                self.pool[index] = button
                local key = YAB.Keybinds:GetButtonKey("aspects", index)
                YAB.Keybinds:HookButton(button, key)
            end
            if button:GetParent() ~= record.holder then button:SetParent(record.holder) end
            local castable = known and not record.classBarEditing
            factory:SetSecureAttribute(button, "type", castable and "spell" or nil)
            factory:SetSecureAttribute(button, "spell", castable and spellID or nil)
            factory:ApplyClickAttributes(button)
            self.states[button] = self.states[button] or { visual = {} }
            local state = self.states[button]
            state.spellID, state.known = spellID, known
            local info = Spell.GetInfo(spellID)
            state.texture = info and (Number(info.originalIconID) or Number(info.iconID)) or "Interface\\Icons\\INV_Misc_QuestionMark"
            manager.buttonConfigSnapshots[button] = record.configSnapshot
            manager.buttonsByKey[YAB.Keybinds:GetButtonKey("aspects", index)] = button
            record.buttons[#record.buttons + 1] = button
            button:Show()
        elseif button then
            factory:SetSecureAttribute(button, "type", nil)
            factory:SetSecureAttribute(button, "spell", nil)
            button:Hide()
            self.states[button] = nil
            manager.buttonConfigSnapshots[button] = nil
            manager.buttonsByKey[YAB.Keybinds:GetButtonKey("aspects", index)] = nil
        end
    end
    self:BuildPetUtilities(record)
    record.configSnapshot.buttons = math.max(#record.buttons, 1)
    manager:ApplyLayout(record, config, YAB:GetDB())
    YAB.Keybinds:ApplyRuntimeBindings()
end

function Bars:RefreshPetUtilityToggle(refreshPetIcon)
    local utilities = self.petUtilities
    if not utilities.toggle or not utilities.toggle:IsShown() or not YAB.Visuals.buttons[utilities.toggle] then return end
    local state = utilities.toggleState
    local checked = utilities.panel:IsShown()
    local name, happiness, hasPet = PetStatus()
    if hasPet and (refreshPetIcon or not utilities.hasPet) then
        local info = Spell.GetInfo(883)
        utilities.summonedTexture = info and (Number(info.iconID) or Number(info.originalIconID))
            or "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    local changed = state.checked ~= checked or utilities.petName ~= name or utilities.happiness ~= happiness
    state.checked, utilities.petName, utilities.happiness = checked, name, happiness
    utilities.hasPet = hasPet
    state.texture = hasPet and utilities.summonedTexture or self.petUtilityAbsentTexture
    YAB.Visuals:UpdateButton(utilities.toggle, state, "full")
    local attitude = PET_HAPPINESS[happiness]
    YAB.Visuals:SetPetHappiness(utilities.toggle, happiness ~= 3 and attitude and attitude.color or nil)
    if (changed or refreshPetIcon) and GameTooltip:IsOwned(utilities.toggle) then
        PetUtilityTooltip(name, happiness)
    end
end

local function UtilityPanelChanged()
    Bars:RefreshPetUtilityToggle()
end

local function PreparePetFeed(button)
    if InCombat() or not Bars.active.aspects or button ~= Bars.petUtilities.toggle
        or not button:IsShown() or not button:GetAttribute("yab-pet-utilities-enabled")
        or not (Item and Item.CanFeedPetFromCursor) then return end
    if Item.CanFeedPetFromCursor() == true then
        YAB.SecureFactory:SetSecureAttribute(button, "type", "target")
    end
end

local function PetUtilityPreClick(button)
    if InCombat() or button:GetAttribute("yab-pet-utility-drop")
        or not (Item and Item.GetCursorItemID) then return end
    local _, hasItem = Item.GetCursorItemID()
    if not hasItem then return end
    -- A carried-item click can precede OnReceiveDrag. Claim it before the native
    -- call clears the cursor, keeping both event paths in the same gesture.
    YAB.SecureFactory:SetSecureAttribute(button, "yab-pet-utility-drop", true)
    PreparePetFeed(button)
    YAB.SecureFactory:SetSecureAttribute(button, "yab-pet-feed-click", true)
end

function Bars:BuildPetUtilities(record)
    local utilities, factory, manager = self.petUtilities, YAB.SecureFactory, YAB.BarManager
    if utilities.panel then utilities.panel:Hide() end
    utilities.buttons = {}
    record.classButtons = {}
    local enabled = Config("aspects").showPetUtilities ~= false
    for index, family in ipairs(self.petUtilityFamilies) do
        local spellID, known = ResolveKnownFamily(family)
        local button = utilities.pool[index]
        if known and enabled then
            if not utilities.panel then
                utilities.panel, utilities.toggle = factory:CreatePetUtilityPanel(record.holder)
                utilities.panel:HookScript("OnShow", UtilityPanelChanged)
                utilities.panel:HookScript("OnHide", UtilityPanelChanged)
                utilities.toggle:HookScript("OnEnter", Enter)
                utilities.toggle:HookScript("OnLeave", Leave)
                utilities.toggle:SetScript("OnHide", Leave)
                utilities.toggle:SetScript("PreClick", PetUtilityPreClick)
                -- CheckButton may flip its native checked state even when a drop
                -- claimed the click. Always restore it from the popup's state.
                utilities.toggle:HookScript("PostClick", UtilityPanelChanged)
                utilities.toggle.PreparePetFeed = PreparePetFeed
                utilities.toggleState = { hasAction = true, usable = true, aspectActiveStyle = "innerGlow" }
            end
            if not button then
                button = factory:CreatePetUtilityButton(utilities.panel, index)
                button:SetScript("OnEnter", Enter)
                button:SetScript("OnLeave", Leave)
                utilities.pool[index] = button
                button:SetScript("OnHide", Leave)
            end
            factory:ApplyClickAttributes(button)
            local entry = utilities.states[button] or { visual = {} }
            utilities.states[button] = entry
            entry.spellID, entry.known = spellID, true
            local info = Spell.GetInfo(spellID)
            entry.texture = info and (Number(info.originalIconID) or Number(info.iconID))
            manager.buttonConfigSnapshots[button] = record.configSnapshot
            utilities.buttons[#utilities.buttons + 1] = button
            button:Show()
        elseif button then
            factory:SetSecureAttribute(button, "type", nil)
            factory:SetSecureAttribute(button, "spell", nil)
            button:Hide()
            utilities.states[button] = nil
            manager.buttonConfigSnapshots[button], manager.mouseoverRecords[button] = nil, nil
            if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        end
    end
    if utilities.toggle then
        utilities.hasPet = nil
        utilities.panel:SetParent(record.holder)
        utilities.toggle:SetParent(record.holder)
        local visible = #utilities.buttons > 0
        utilities.toggle:SetShown(visible)
        manager.buttonConfigSnapshots[utilities.toggle] = visible and record.configSnapshot or nil
        record.petUtilityToggle = visible and utilities.toggle or nil
        record.classButtons = visible and { utilities.toggle, utilities.panel } or {}
        if not visible then
            manager.mouseoverRecords[utilities.toggle], manager.mouseoverRecords[utilities.panel] = nil, nil
        end
        for _, button in ipairs(utilities.buttons) do record.classButtons[#record.classButtons + 1] = button end
    end
    self:SyncPetUtilityInteraction(record)
end

function Bars:SyncPetUtilityInteraction(record)
    if not record or not self.petUtilities.panel then return end
    if InCombat() then self.pending = true; return end
    local utilities = self.petUtilities
    local enabled = Config("aspects").showPetUtilities ~= false
        and not record.classBarEditing and not YAB.BarManager.bindPresentationActive
    if not enabled then utilities.panel:Hide() end
    YAB.SecureFactory:SetSecureAttribute(utilities.toggle, "yab-pet-utilities-enabled",
        enabled and #utilities.buttons > 0)
    for _, button in ipairs(utilities.buttons) do
        YAB.SecureFactory:SetSecureAttribute(button, "type", enabled and "spell" or nil)
        YAB.SecureFactory:SetSecureAttribute(button, "spell", enabled and utilities.states[button].spellID or nil)
    end
end

local FLYOUT_POINTS = { up = { "BOTTOM", "TOP" }, down = { "TOP", "BOTTOM" },
    left = { "RIGHT", "LEFT" }, right = { "LEFT", "RIGHT" } }

function Bars:LayoutFlyout(panel, opener, buttons, width, height, spacing, direction, shownOnly)
    direction = FLYOUT_POINTS[direction] and direction or "up"
    local horizontal = direction == "left" or direction == "right"
    local point = direction == "up" and "BOTTOM" or direction == "down" and "TOP"
        or direction == "left" and "RIGHT" or "LEFT"
    local count, opening = 0, math.max(4, spacing)
    for _, button in ipairs(buttons) do
        if not shownOnly or button:IsShown() then
            button:ClearAllPoints()
            local offset = opening + count * ((horizontal and width or height) + spacing)
            button:SetPoint(point, panel, point,
                horizontal and (direction == "left" and -offset or offset) or 0,
                not horizontal and (direction == "down" and -offset or offset) or 0)
            count = count + 1
        end
    end
    if count == 0 then return 0 end
    local length = opening + count * (horizontal and width or height) + (count - 1) * spacing
    panel:SetSize(horizontal and length or width, horizontal and height or length)
    panel:ClearAllPoints()
    panel:SetPoint(FLYOUT_POINTS[direction][1], opener, FLYOUT_POINTS[direction][2], 0, 0)
    return count
end

function Bars:LayoutPetUtilities(record, width, height, buttonWidth, buttonHeight, spacing, columns, alignment)
    if InCombat() then self.pending = true; return width, height end
    local utilities = self.petUtilities
    if #utilities.buttons == 0 then return width, height end
    local toggle, panel = utilities.toggle, utilities.panel
    local count = #record.buttons + 1
    columns = columns or math.max(math.ceil(count / math.min(record.configSnapshot.rows or 1, count)), 1)
    local row, col = math.floor((count - 1) / columns), (count - 1) % columns
    local rowCount = count - row * columns
    local rowWidth = rowCount * buttonWidth + (rowCount - 1) * spacing
    local offset = alignment == "right" and width - rowWidth
        or alignment == "center" and math.floor((width - rowWidth) * 0.5 + 0.5) or 0
    toggle:ClearAllPoints()
    toggle:SetPoint("TOPLEFT", record.holder, "TOPLEFT", math.max(0, offset) + col * (buttonWidth + spacing),
        -row * (buttonHeight + spacing))
    for position = 0, #utilities.buttons do
        local button = position == 0 and toggle or utilities.buttons[position]
        button:SetSize(buttonWidth, buttonHeight)
        YAB.Skins:ApplyButton(button, YAB.Skins:Normalize("default"), {
            size = record.configSnapshot.size, width = buttonWidth, height = buttonHeight,
            zoom = record.configSnapshot.iconZoom, snapshot = record.configSnapshot })
        if position == 0 then YAB.Visuals:PreparePetHappiness(button) end
    end
    self:LayoutFlyout(panel, toggle, utilities.buttons, buttonWidth, buttonHeight, spacing,
        record.configSnapshot.flyoutDirection)
    return width, height
end

function Bars:RefreshPetUtilityVisuals()
    local utilities = self.petUtilities
    for _, button in ipairs(utilities.buttons) do
        local entry = utilities.states[button]
        local state, id = entry.visual, entry.spellID
        state.hasAction, state.texture, state.actionID = true, entry.texture, id
        local usable, noMana = C_Spell.IsSpellUsable(id)
        state.usable, state.noMana = Boolean(usable) == true, Boolean(noMana) == true
        state.cooldownDurationObject = Spell.GetCooldownDurationObject(id)
        state.cooldownEnable = true
        state.cooldownStart, state.cooldownDuration = nil, nil
        if not state.cooldownDurationObject then
            local cooldown = Spell.GetCooldown(id)
            if cooldown then
                state.cooldownStart, state.cooldownDuration = cooldown.startTime, cooldown.duration
                state.cooldownEnable = cooldown.isEnabled
            end
        end
        YAB.Visuals:UpdateButton(button, state, "full")
        state.cooldownDurationObject = nil
    end
    self:RefreshPetUtilityToggle()
end

function Bars:StopPetUtilities()
    local utilities, manager, factory = self.petUtilities, YAB.BarManager, YAB.SecureFactory
    if not utilities.panel then return end
    factory:SetSecureAttribute(utilities.toggle, "yab-pet-utilities-enabled", false)
    factory:SetSecureAttribute(utilities.toggle, "yab-pet-utility-drop", nil)
    factory:SetSecureAttribute(utilities.toggle, "yab-pet-feed-click", nil)
    factory:SetSecureAttribute(utilities.toggle, "type", nil)
    utilities.panel:Hide()
    utilities.toggle:Hide()
    for _, button in pairs(utilities.pool) do
        factory:SetSecureAttribute(button, "type", nil)
        factory:SetSecureAttribute(button, "spell", nil)
        button:Hide()
        YAB.Visuals:ReleaseButton(button)
        manager.buttonConfigSnapshots[button], manager.mouseoverRecords[button] = nil, nil
        utilities.states[button] = nil
        if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    end
    YAB.Visuals:ReleaseButton(utilities.toggle)
    manager.buttonConfigSnapshots[utilities.toggle], manager.mouseoverRecords[utilities.toggle] = nil, nil
    manager.mouseoverRecords[utilities.panel] = nil
    local record = manager.bars.aspects
    if record then record.classButtons, record.petUtilityToggle = {}, nil end
    if GameTooltip:IsOwned(utilities.toggle) then GameTooltip:Hide() end
    utilities.buttons = {}
end

function Bars:RefreshAspectVisuals(record)
    local snapshot = record.configSnapshot
    local activeStyle = Config("aspects").aspectActiveStyle
    if activeStyle ~= "nativeIcon" and activeStyle ~= "dimOthers" then activeStyle = "innerGlow" end
    local anyActive = false
    for _, button in ipairs(record.buttons) do
        local entry = self.states[button]
        local state, id = entry.visual, entry.spellID
        state.hasAction, state.texture = true, entry.texture
        state.actionID, state.rangeMode = id, "none"
        state.unlearned = not entry.known
        state.usable, state.noMana, state.checked = entry.known, false, false
        if entry.known then
            local usable, noMana = C_Spell.IsSpellUsable(id)
            state.usable, state.noMana = Boolean(usable) == true, Boolean(noMana) == true
            if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                local family = self.aspectFamilies[YAB.SecureFactory:GetButtonMeta(button).index]
                for _, auraID in ipairs(family) do
                    local aura = C_UnitAuras.GetPlayerAuraBySpellID(auraID)
                    if not Security.IsSecretValue(aura) and aura ~= nil then state.checked = true; break end
                end
            end
        end
        if state.checked then anyActive = true end
        state.hotkeyText = snapshot.showHotkeys and YAB.Keybinds:GetBindingText(
            YAB.Keybinds:GetButtonKey("aspects", YAB.SecureFactory:GetButtonMeta(button).index)) or ""
        state.cooldownDurationObject = entry.known and Spell.GetCooldownDurationObject(id) or nil
        state.cooldownEnable = entry.known
        state.cooldownStart, state.cooldownDuration = nil, nil
        if not state.cooldownDurationObject and entry.known then
            local cooldown = Spell.GetCooldown(id)
            if cooldown then
                state.cooldownStart, state.cooldownDuration = cooldown.startTime, cooldown.duration
                state.cooldownEnable = cooldown.isEnabled
            end
        end
    end
    for _, button in ipairs(record.buttons) do
        local entry = self.states[button]
        local state = entry.visual
        state.aspectActiveStyle = activeStyle
        state.aspectDimmed = activeStyle == "dimOthers" and anyActive and not state.checked
        if activeStyle == "nativeIcon" and state.checked then
            state.texture = self.aspectActiveTexture
        end
        YAB.Visuals:UpdateButton(button, state, "full")
        state.cooldownDurationObject = nil
    end
end

-- Only the native root is parked. Native children and regions are never adopted.
function Bars:CaptureNativeFrame(frame)
    if not frame or self.nativeFrames[frame] then return end
    local state = { parent = frame:GetParent(), width = frame:GetWidth(), height = frame:GetHeight(), points = {} }
    for index = 1, frame:GetNumPoints() do state.points[index] = { frame:GetPoint(index) } end
    self.nativeFrames[frame] = state
end

local TOTEM_PRIORITY = { 2, 1, 3, 4 }
local TOTEM_SUMMONS = { 66842, 66843, 66844 }
local TOTEM_RECALL = 36936
local TOTEM_CLEAR = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

local function TotemTooltip(button)
    if not Bars.active.totems then return end
    local interaction = YAB:GetDB().interaction
    if interaction.tooltipMode == "outOfCombat" and InCombat() then return end
    local entry = Bars.totems.states[button]
    if not entry then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if entry.role == "slot" then
        local action = Number(button:GetAttribute("action"))
        local spellID = action and YAB.Adapter:GetActionSpellID(action)
        if spellID and spellID > 0 then
            GameTooltip:SetAction(action)
        else
            GameTooltip:SetText(_G.MULTI_CAST_TOOLTIP_NO_TOTEM or "")
        end
    elseif entry.spellID and entry.spellID > 0 then
        GameTooltip:SetSpellByID(entry.spellID)
    else
        GameTooltip:SetText(_G.MULTI_CAST_TOOLTIP_NO_TOTEM or "")
    end
    GameTooltip:Show()
end

function Bars:CloseTotemFlyout()
    local record = YAB.BarManager.bars.totems
    if not record or not record.totemController then return end
    if InCombat() then return end
    for _, panel in ipairs(self.totems.panels) do panel:Hide() end
end

function Bars:SyncTotemInteraction()
    local record = YAB.BarManager.bars.totems
    if not record or not record.totemController then return end
    if InCombat() then self.pending = true; return end
    local enabled = self.active.totems and not record.classBarEditing
        and not YAB.BarManager.bindPresentationActive
        and Number(record.totemController:GetAttribute("action-base")) ~= nil
    record.totemController:SetAttribute("interactive", enabled == true)
    for _, button in ipairs(record.buttons) do
        local entry = self.totems.states[button]
        YAB.SecureFactory:SetSecureAttribute(button, "type", enabled and entry.known
            and (entry.role == "slot" and "action" or "spell") or nil)
    end
    if not enabled then self:CloseTotemFlyout() end
    self:RefreshTotemBindings(not enabled)
end

local function TotemPageChanged()
    if Bars.active.totems then
        Bars:SyncTotemCommands(YAB.BarManager.bars.totems)
        YAB.BarManager:QueueSpecialRefresh("totems", "totem page")
    end
end

local function TotemPresentationShown()
    if Bars.active.totems then YAB.BarManager:QueueSpecialRefresh("totems", "totem hover") end
end

local function TotemSelectionChanged()
    if Bars.active.totems then YAB.BarManager:QueueSpecialRefresh("totems", "totem selection") end
end

function Bars:AttachTotems(record)
    if _G.MultiCastFlyoutFrame then MultiCastFlyoutFrame:Hide() end
    local frame = _G.MultiCastActionBarFrame
    if frame then
        self:CaptureNativeFrame(frame)
        if not YAB.BarManager:SuppressNativeClassFrame(record, frame) then return false end
        record.nativeTotemFrame = frame
        record.initialTotemPage = Number(frame.currentPage)
        if YUI.Layout and YUI.Layout.SetNativeEditModeClaim then
            YUI.Layout:SetNativeEditModeClaim(self, frame, true)
        end
    end
    return true
end

function Bars:GetTotemButton(record, role, index, parent)
    local totems, factory = self.totems, YAB.SecureFactory
    parent = parent or record.holder
    local key = role .. index
    local button = totems.main[key]
    if not button then
        button = factory:CreateTotemButton(parent, role, index)
        totems.main[key] = button
        totems.states[button] = { role = role, visual = {} }
        button:HookScript("OnEnter", TotemTooltip)
        button:HookScript("OnLeave", Leave)
    end
    if button:GetParent() ~= parent then button:SetParent(parent) end
    return button, totems.states[button]
end

function Bars:SyncTotemCommands(record)
    local totems, factory, manager = self.totems, YAB.SecureFactory, YAB.BarManager
    local page = Number(record.totemController:GetAttribute("totem-page")) or 1
    local position = 0
    for _, button in ipairs(record.buttons) do
        local entry, command = totems.states[button]
        if entry.role == "slot" then
            position = position + 1
            command = "MULTICASTACTIONBUTTON" .. ((page - 1) * 4 + position)
        elseif entry.role == "summon" then
            command = "MULTICASTSUMMONBUTTON" .. page
        else
            command = "MULTICASTRECALLBUTTON1"
        end
        local meta = factory:GetButtonMeta(button)
        meta.commandName = command
        meta.totemBindingManaged = true
        local key = "totems." .. (entry.role == "slot" and entry.slot or entry.role)
        if not meta.buttonKey then
            meta.buttonKey = key
            YAB.Keybinds:HookButton(button, key)
        end
        manager.buttonsByKey[key] = button
    end
end

local function ReadTotemBinding(command, result)
    for key in pairs(result) do result[key] = nil end
    if command and not YUI.API.ActionBar:ReadBinding(command, result) then
        for key in pairs(result) do result[key] = nil end
    end
end

function Bars:BuildTotemBindings(record)
    local totems, factory = self.totems, YAB.SecureFactory
    if not Number(record.totemController:GetAttribute("action-base"))
        or record.classBarEditing or YAB.BarManager.bindPresentationActive
        or (YAB.Keybinds.GetSystemBindingSuppressionReason and YAB.Keybinds:GetSystemBindingSuppressionReason()) then
        ClearOverrideBindings(record.totemController)
        return
    end
    local bindings, count, slotPosition = totems.bindings, 0, {}
    for command in pairs(totems.bindingByCommand) do totems.bindingByCommand[command] = nil end
    for _, slot in ipairs(TOTEM_PRIORITY) do
        if #totems.spellLists[slot] > 0 then slotPosition[#slotPosition + 1] = slot end
    end
    local function Bind(role, index, command, action, spell)
        local button = self:GetTotemButton(record, role, index, record.totemController)
        factory:SetSecureAttribute(button, "type", action and "action" or spell and "spell" or nil)
        factory:SetSecureAttribute(button, "action", action)
        factory:SetSecureAttribute(button, "spell", spell)
        factory:ApplyClickAttributes(button)
        button:Hide()
        count = count + 1
        local entry = bindings[count] or {}
        bindings[count] = entry
        ReadTotemBinding(command, entry)
        entry.buttonName = button:GetName()
        totems.bindingByCommand[command] = entry
    end
    for page = 1, 3 do
        for position, slot in ipairs(slotPosition) do
            Bind("bindingSlot", (page - 1) * 4 + position,
                "MULTICASTACTIONBUTTON" .. ((page - 1) * 4 + position),
                YUI.API.ActionBar:GetMultiCastActionSlot(page, slot))
        end
        if Spell.GetKnownState(TOTEM_SUMMONS[page]) then
            Bind("bindingSummon", page, "MULTICASTSUMMONBUTTON" .. page, nil, TOTEM_SUMMONS[page])
        end
    end
    local recall = totems.main.recall1
    if recall and Spell.GetKnownState(TOTEM_RECALL) then
        count = count + 1
        local entry = bindings[count] or {}
        bindings[count] = entry
        ReadTotemBinding("MULTICASTRECALLBUTTON1", entry)
        entry.buttonName = recall:GetName()
        totems.bindingByCommand.MULTICASTRECALLBUTTON1 = entry
    end
    for index = #bindings, count + 1, -1 do bindings[index] = nil end
    factory:ApplyTotemBindings(record.totemController, bindings)
end

function Bars:RefreshTotemBindings(suppressed)
    local record = YAB.BarManager.bars.totems
    if not self.active.totems or not record or not record.totemController then return end
    if InCombat() then self.pending = true; return end
    if suppressed then ClearOverrideBindings(record.totemController)
    else self:BuildTotemBindings(record) end
end

function Bars:BuildTotems(record, config)
    local totems, factory, api = self.totems, YAB.SecureFactory, YUI.API.ActionBar
    if not record.totemController then
        record.totemController = totems.controller or factory:CreateTotemController(record.holder)
        totems.controller = record.totemController
        record.totemController:SetParent(record.holder)
        record.totemController.TotemPageChanged = TotemPageChanged
        record.totemController.TotemPresentationShown = TotemPresentationShown
        record.totemController.TotemSelectionChanged = TotemSelectionChanged
        for index = 1, 5 do
            totems.panels[index] = totems.panels[index]
                or factory:CreateTotemPanel(record.holder, record.totemController, index)
            totems.panels[index]:SetParent(record.holder)
            totems.choices[index] = totems.choices[index] or {}
        end
    end
    local controller = record.totemController
    for _, panel in ipairs(totems.panels) do
        panel:Hide()
        panel.choiceCount = 0
    end
    for _, button in pairs(totems.main) do
        factory:SetSecureAttribute(button, "type", nil)
        factory:SetSecureAttribute(button, "_onenter", nil)
        button:Hide()
        local meta = factory:GetButtonMeta(button)
        if meta.buttonKey then YAB.BarManager.buttonsByKey[meta.buttonKey] = nil end
    end
    record.buttons, record.classButtons = {}, {}
    local firstAction = api:GetMultiCastActionSlot(1, 1)
    controller:SetAttribute("action-base", firstAction and firstAction - 1 or nil)
    if not firstAction then
        controller:SetAttribute("interactive", false)
        controller:SetAttribute("selector-count", 0)
        ClearOverrideBindings(controller)
        return
    end
    local page = record.initialTotemPage or Number(controller:GetAttribute("totem-page"))
        or (record.nativeTotemFrame and Number(record.nativeTotemFrame.currentPage))
    record.initialTotemPage = nil
    if not page or page < 1 or page > 3 or page % 1 ~= 0 then page = 1 end
    for index, spell in ipairs(TOTEM_SUMMONS) do
        local known = Spell.GetKnownState(spell) == true
        controller:SetAttribute("summon" .. index, known and spell or nil)
        if page == index and index > 1 and not known then page = 1 end
    end
    local function Main(role, slot, spell, visible)
        if not visible and not record.classBarEditing then return end
        local button, entry = self:GetTotemButton(record, role, slot)
        entry.slot, entry.spellID, entry.known = role == "slot" and slot or nil, spell, visible == true
        if role == "slot" then
            controller:SetFrameRef("slot" .. slot, button)
        elseif role == "summon" then
            controller:SetFrameRef("summon", button)
        end
        local enabled = visible and not record.classBarEditing
        factory:SetSecureAttribute(button, "type", enabled and (role == "slot" and "action" or "spell") or nil)
        factory:SetSecureAttribute(button, "spell", enabled and spell or nil)
        factory:ApplyClickAttributes(button)
        button:Show()
        record.buttons[#record.buttons + 1] = button
        return button
    end
    Main("summon", 1, TOTEM_SUMMONS[page], Spell.GetKnownState(TOTEM_SUMMONS[page]) == true)
    for _, slot in ipairs(TOTEM_PRIORITY) do
        totems.spellLists[slot] = api:GetMultiCastSpells(slot, totems.spellLists[slot])
        Main("slot", slot, nil, #totems.spellLists[slot] > 0)
    end
    Main("recall", 1, TOTEM_RECALL, Spell.GetKnownState(TOTEM_RECALL) == true)
    local selectors = 0
    for panelIndex, panel in ipairs(totems.panels) do
        local choices, count = totems.choices[panelIndex], 0
        local slot = panelIndex - 1
        local list = panelIndex == 1 and TOTEM_SUMMONS or totems.spellLists[slot]
        local function Choice(spell, pageChoice)
            count = count + 1
            local button = choices[count]
            if not button then
                button = factory:CreateTotemButton(panel, "choice" .. panelIndex, count)
                choices[count] = button
                totems.states[button] = { role = "choice", visual = {} }
                button:HookScript("OnEnter", TotemTooltip)
                button:HookScript("OnLeave", Leave)
                factory:PrepareTotemChoice(button, panel, controller, pageChoice)
            end
            local entry = totems.states[button]
            entry.spellID, entry.page, entry.slot = spell, pageChoice, slot
            factory:SetSecureAttribute(button, "type", panelIndex > 1 and "multispell" or nil)
            factory:SetSecureAttribute(button, "spell", spell)
            if pageChoice then
                factory:SetSecureAttribute(button, "totem-page", pageChoice)
            else
                button:SetAttribute("totem-slot", slot)
                selectors = selectors + 1
                controller:SetFrameRef("selector" .. selectors, button)
            end
            button:Show()
        end
        if panelIndex == 1 then
            for index, spell in ipairs(list) do
                if Spell.GetKnownState(spell) == true then Choice(spell, index) end
            end
        elseif #list > 0 then
            Choice(0)
            for _, spell in ipairs(list) do Choice(spell) end
        end
        panel.choiceCount = count
        for index = count + 1, #choices do
            choices[index]:Hide()
            factory:SetSecureAttribute(choices[index], "type", nil)
        end
        local opener = totems.main[panelIndex == 1 and "summon1" or "slot" .. slot]
        if opener and opener:IsShown() and count > 0 and not record.classBarEditing then
            factory:PrepareTotemOpener(opener, panel, controller)
        end
    end
    controller:SetAttribute("selector-count", selectors)
    factory:SetTotemPage(controller, page)
    self:SyncTotemCommands(record)
    self:SyncTotemInteraction()
end

local function TotemCooldownDone(cooldown)
    local button = cooldown:GetParent()
    local entry = Bars.totems.states[button]
    if not (Bars.active.totems and entry and entry.cooldownHook == cooldown
        and not entry.cooldownUpdating and entry.visual.cooldownActive == true and button:IsVisible()) then return end
    entry.visual.cooldownActive, entry.visual.cooldownEnable = false, false
    local id = entry.visual.actionID
    if id and id > 0 then
        local usable, noMana = C_Spell.IsSpellUsable(id)
        entry.visual.usable, entry.visual.noMana = Boolean(usable) ~= false, Boolean(noMana) == true
    end
    YAB.Visuals:UpdateButton(button, entry.visual, ":cooldownMeta:usable:")
end

function Bars:ApplyTotemLayout(record, config, db)
    if InCombat() then self.pending = true; return end
    if not record.totemController then return end
    local manager, snapshot = YAB.BarManager, record.configSnapshot
    local count = math.max(#record.buttons, 1)
    local size, height = manager:GetLayoutButtonSize(config, snapshot, db)
    local rows = math.max(1, math.min(math.floor(snapshot.rows or 1), count))
    local spacing, columns = snapshot.spacing or 8
    local width, totalHeight
    width, totalHeight, rows, columns = manager:MeasureLayoutGrid(count, rows, spacing, size, height)
    record.layoutWidth, record.layoutHeight = width, totalHeight
    record.mover:SetSize(width, totalHeight)
    record.holder:SetSize(width, totalHeight)
    local function Style(button)
        button:SetSize(size, height)
        YAB.Skins:ApplyButton(button, YAB.Skins:Normalize("default"), {
            size = snapshot.size, width = size, height = height, zoom = snapshot.iconZoom, snapshot = snapshot })
        local visual, entry = YAB.Visuals.buttons[button], self.totems.states[button]
        local cooldown = visual and visual.cooldown
        if entry and cooldown and entry.cooldownHook ~= cooldown then
            cooldown:HookScript("OnCooldownDone", TotemCooldownDone)
            entry.cooldownHook = cooldown
        end
        manager.buttonConfigSnapshots[button] = snapshot
        record.classButtons[#record.classButtons + 1] = button
    end
    record.classButtons = {}
    for position, button in ipairs(record.buttons) do
        local row, col = math.floor((position - 1) / columns), (position - 1) % columns
        local rowCount = math.min(columns, count - row * columns)
        local rowWidth = rowCount * size + (rowCount - 1) * spacing
        local offset = snapshot.alignment == "right" and width - rowWidth
            or snapshot.alignment == "center" and math.floor((width - rowWidth) * 0.5 + 0.5) or 0
        Style(button)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", record.holder, "TOPLEFT",
            math.max(0, offset) + col * (size + spacing), -row * (height + spacing))
    end
    for index, panel in ipairs(self.totems.panels) do
        local choices = self.totems.choices[index]
        for i = 1, panel.choiceCount do Style(choices[i]) end
        local opener = self.totems.main[index == 1 and "summon1" or "slot" .. (index - 1)]
        if opener and panel.choiceCount > 0 then
            self:LayoutFlyout(panel, opener, choices, size, height, spacing, snapshot.flyoutDirection, true)
        end
        record.classButtons[#record.classButtons + 1] = panel
    end
    snapshot.buttons = count
    manager:UpdateMouseoverAlpha(record)
    YAB.SecureFactory:ConfigureBarController(record.controller, record, config, width, totalHeight)
    YAB.LayoutBridge:Refresh("totems")
end

function Bars:RefreshTotemVisuals(record, prepareHidden)
    local totems, snapshot = self.totems, record.configSnapshot
    local page = Number(record.totemController:GetAttribute("totem-page")) or 1
    for _, button in ipairs(record.classButtons) do
        local entry = totems.states[button]
        if entry and (prepareHidden or button:IsVisible()) then
            local state, id = entry.visual, entry.spellID
            if entry.role == "slot" then
                local action = Number(button:GetAttribute("action"))
                id = action and YAB.Adapter:GetActionSpellID(action)
                id = id and id > 0 and id or nil
                totems.selected[entry.slot] = id or false
            elseif entry.role == "summon" then
                id = TOTEM_SUMMONS[page]
                entry.spellID = id
            end
            local info = id and id > 0 and Spell.GetInfo(id)
            state.texture = info and info.iconID
                or (id and id > 0 and "Interface\\Icons\\INV_Misc_QuestionMark") or TOTEM_CLEAR
            state.hasAction, state.actionID, state.rangeMode = true, id, "none"
            state.unlearned = entry.known == false
            state.usable, state.noMana = not state.unlearned, false
            state.checked = entry.page == page or (entry.role == "choice" and entry.slot > 0
                and (id > 0 and id or false) == totems.selected[entry.slot])
            if id and id > 0 then
                local usable, noMana = C_Spell.IsSpellUsable(id)
                state.usable, state.noMana = Boolean(usable) ~= false, Boolean(noMana) == true
            end
            local command = YAB.SecureFactory:GetButtonMeta(button).commandName
            local binding = command and totems.bindingByCommand[command]
            state.hotkeyText = snapshot.showHotkeys and binding and binding.primaryText or ""
            if entry.cooldownSpellID ~= id then
                entry.cooldownSpellID, state.cooldownActive = id, false
            end
            state.cooldownDurationObject = nil
            state.cooldownStart, state.cooldownDuration, state.cooldownModRate = nil, nil, nil
            state.cooldownEnable = false
            if id and id > 0 then
                -- Readable native values use the shared unchanged-cooldown cache.
                -- Restricted values remain transient inputs to the native duration sink.
                local cooldown = Spell.GetCooldown(id)
                if cooldown then
                    state.cooldownStart, state.cooldownDuration = cooldown.startTime, cooldown.duration
                    state.cooldownEnable, state.cooldownModRate = cooldown.isEnabled, cooldown.modRate
                else
                    state.cooldownDurationObject = Spell.GetCooldownDurationObject(id)
                    state.cooldownEnable = state.cooldownDurationObject and true or false
                end
                -- Public rule flags distinguish real cooldowns from the GCD,
                -- including when the native duration itself is restricted.
                local active, resolved = Spell.ReadCooldownRuleState(id)
                if resolved then
                    state.cooldownActive = active
                elseif cooldown then
                    state.cooldownActive = cooldown.isEnabled == true and cooldown.duration > 1.5
                elseif not state.cooldownEnable then
                    state.cooldownActive = false
                end
            end
            entry.cooldownUpdating = true
            YAB.Visuals:UpdateButton(button, state, "full")
            entry.cooldownUpdating = nil
            state.cooldownDurationObject = nil
        end
    end
end

function Bars:Refresh(id)
    if not self.active[id] then return end
    local record = YAB.BarManager.bars[id]
    if not record then return end
    local config = Config(id)
    local structural = self.configDirty[id] or (id == "aspects" and self.structureDirty)
    if structural and InCombat() then self.pending = true end
    if structural and not InCombat() then
        local layoutId = YAB.ClassTools:GetLayoutId(id)
        if not YAB.LayoutBridge.classLayoutIds or YAB.LayoutBridge.classLayoutIds[id] ~= layoutId then
            YAB.LayoutBridge:Register(id, record, Text("bar." .. id), config)
        end
        YAB.BarManager:AttachConfigSnapshot(record, id, config, "special")
        if id == "aspects" then
            self:BuildAspects(record, config)
            self.structureDirty = false
        elseif id == "mageTools" then
            YAB.MageTools:Build(record, config)
        else
            self:BuildTotems(record, config)
            self:ApplyTotemLayout(record, config, YAB:GetDB())
        end
        self.configDirty[id] = nil
        YAB.BarManager:ApplyRecordVisibility(record)
        YAB.BarManager:ApplyMouseoverVisibility(record)
    end
    if id == "aspects" then
        self:RefreshAspectVisuals(record)
        self:RefreshPetUtilityVisuals()
    elseif id == "mageTools" then
        YAB.MageTools:Refresh(record)
    elseif record.totemController then
        self:RefreshTotemVisuals(record, structural and not InCombat())
    end
    self.passes = self.passes + 1
end

function Bars:OnEvent(event, ...)
    if self.active.mageTools then YAB.MageTools:OnEvent(event, ...) end
    if self.mageCastEvents[event] then return end
    if event == "UNIT_HAPPINESS" or event == "UNIT_NAME_UPDATE" or event == "UNIT_PET" then
        self:RefreshPetUtilityToggle(event == "UNIT_PET")
        if event ~= "UNIT_PET" then return end
    end
    if event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        self.structureDirty, self.configDirty.totems = true, true
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if self.pending then
            self.pending = false
            self:SyncEnabled()
        elseif self.active.mageTools then
            YAB.BarManager:QueueSpecialRefresh("mageTools", event)
        end
        return
    end
    if event == "UPDATE_BINDINGS" then
        self.configDirty.totems = true
    end
    for id in pairs(self.active) do YAB.BarManager:QueueSpecialRefresh(id, event) end
end

function Bars:GetStats()
    local main, choices = 0, 0
    for _ in pairs(self.totems.main) do main = main + 1 end
    for _, pool in ipairs(self.totems.choices) do choices = choices + #pool end
    return { aspects = self.active.aspects == true, totems = self.active.totems == true,
        listening = self.listening == true, pending = self.pending == true, passes = self.passes,
        totemHosts = main, totemChoices = choices, totemPanels = #self.totems.panels }
end

function Bars:SyncEnabled()
    if InCombat() then self.pending = true; return end
    local db, manager = YAB:GetDB(), YAB.BarManager
    local class = YAB.SpecialBars:GetPlayerClassToken()
    for _, id in ipairs({ "aspects", "totems", "mageTools" }) do
        local wanted = db.enabled and manager.runtimeActive and Config(id).enabled
            and class == (id == "aspects" and "HUNTER" or id == "totems" and "SHAMAN" or "MAGE")
        if wanted then
            local record = self:EnsureRecord(id)
            self.active[id] = record and true or nil
            if record and id == "totems" and not record.nativeTotemFrame and not self:AttachTotems(record) then
                self:StopBar(id)
                record = nil
            end
            if record then
                self.configDirty[id] = true
                self:Refresh(id)
            end
        elseif self.active[id] then
            self:StopBar(id)
        end
    end
    YAB.LayoutBridge:SyncClassToolsMover()
    self.listening = (self.active.aspects or self.active.totems or self.active.mageTools) == true
    manager:SyncClassBarEvents()
    if manager.RefreshActionBroadcasterMode then manager:RefreshActionBroadcasterMode("class bars") end
end

function Bars:StopBar(id)
    if InCombat() then self.pending = true; return false end
    if id == "totems" then self:CloseTotemFlyout() end
    self.active[id] = nil
    if id == "totems" then
        local record, factory, manager = YAB.BarManager.bars[id], YAB.SecureFactory, YAB.BarManager
        if record and record.totemController then
            record.totemController:SetAttribute("interactive", false)
            ClearOverrideBindings(record.totemController)
        end
        local function Release(button)
            factory:SetSecureAttribute(button, "type", nil)
            button:Hide()
            YAB.Visuals:ReleaseButton(button)
            manager.buttonConfigSnapshots[button], manager.mouseoverRecords[button] = nil, nil
            local meta = factory:GetButtonMeta(button)
            if meta.buttonKey then manager.buttonsByKey[meta.buttonKey] = nil end
            if GameTooltip and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        end
        for _, button in pairs(self.totems.main) do Release(button) end
        for _, choices in ipairs(self.totems.choices) do
            for _, button in ipairs(choices) do Release(button) end
        end
        for _, panel in ipairs(self.totems.panels) do manager.mouseoverRecords[panel] = nil end
        for frame, state in pairs(self.nativeFrames) do
            manager:RestoreNativeClassFrame(frame, state)
            self.nativeFrames[frame] = nil
        end
        if YUI.Layout and YUI.Layout.ReleaseNativeEditModeOwner then YUI.Layout:ReleaseNativeEditModeOwner(self) end
        if record then
            record.buttons, record.classButtons = {}, {}
            if record.nativeTotemFrame and _G.ChangeMultiCastActionPage then
                local page = record.totemController and Number(record.totemController:GetAttribute("totem-page")) or 1
                ChangeMultiCastActionPage(page)
            end
            record.nativeTotemFrame = nil
        end
        YAB.Keybinds:ApplyRuntimeBindings()
    elseif id == "mageTools" then
        YAB.MageTools:Stop()
    else
        self:CancelAspectDrag()
        self:StopPetUtilities()
        for index, button in pairs(self.pool) do
            YAB.SecureFactory:SetSecureAttribute(button, "type", nil)
            YAB.SecureFactory:SetSecureAttribute(button, "spell", nil)
            button:Hide()
            self.states[button] = nil
            YAB.BarManager.buttonsByKey[YAB.Keybinds:GetButtonKey("aspects", index)] = nil
            YAB.Visuals:ReleaseButton(button)
            if GameTooltip and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        end
        YAB.Keybinds:ApplyRuntimeBindings()
    end
    YAB.BarManager:DeactivateBar(id)
    self.configDirty[id] = nil
    return true
end

function Bars:Stop()
    if InCombat() then self.pending = true; return false end
    self:StopBar("aspects")
    self:StopBar("totems")
    self:StopBar("mageTools")
    self.listening, self.pending, self.structureDirty = false, false, true
    YAB.BarManager:SyncClassBarEvents()
    return true
end

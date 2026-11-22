local YUI = _G.YUI
local YAB = YUI and YUI.YActionBar
if not (YAB and YAB.Client and YAB.Client.classBars == true) then return end

local Bars = { active = {}, pool = {}, states = {}, configDirty = {}, structureDirty = true,
    pending = false, passes = 0, nativeFrames = setmetatable({}, { __mode = "k" }),
    totems = { main = {}, panels = {}, choices = {}, bindings = {}, bindingByCommand = {},
        states = {}, spellLists = {}, selected = {}, learnedTimes = {} },
    petUtilities = { pool = {}, states = {}, buttons = {} } }
YAB.ClassBars = Bars
local Spell = YUI.API.Spell
local Item = YUI.API.Item
local Unit = YUI.API.Unit
local Security = YUI.API.Security
local Totem = YUI.API.Totem
-- Older Core 42 builds provide only the native selection timer adapter.
if not (Totem and Totem.GetSlotCount and Totem.ReadSlot and Totem.GetSlotDuration) then Totem = nil end
Bars.mageCastEvents = { UNIT_SPELLCAST_SENT = true, UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true }
Bars.events = { "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "UPDATE_BINDINGS",
    "UNIT_AURA", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "UPDATE_MULTI_CAST_ACTIONBAR",
    "UNIT_PET", "UNIT_HAPPINESS", "UNIT_NAME_UPDATE",
    "PET_BAR_UPDATE", "PET_BAR_UPDATE_COOLDOWN", "PET_BAR_UPDATE_USABLE",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_UPDATE_STATE", "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_USABLE",
    "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "SKILL_LINES_CHANGED", "GET_ITEM_INFO_RECEIVED", "PLAYER_LEVEL_UP",
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }
Bars.utilityEvents = { UNIT_AURA=true, SPELL_UPDATE_COOLDOWN=true, SPELL_UPDATE_USABLE=true,
    BAG_UPDATE_DELAYED=true, BAG_UPDATE_COOLDOWN=true, GET_ITEM_INFO_RECEIVED=true, PLAYER_LEVEL_UP=true,
    UNIT_PET=true, UNIT_INVENTORY_CHANGED=true, PLAYER_EQUIPMENT_CHANGED=true }
Bars.events[#Bars.events + 1], Bars.events[#Bars.events + 2] = "UNIT_INVENTORY_CHANGED", "PLAYER_EQUIPMENT_CHANGED"
Bars.events[#Bars.events + 1], Bars.events[#Bars.events + 2] = "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED"
Bars.events[#Bars.events + 1] = "WEAPON_ENCHANT_CHANGED"
Bars.events[#Bars.events + 1], Bars.events[#Bars.events + 2] = "PLAYER_TOTEM_UPDATE", "ADDON_RESTRICTION_STATE_CHANGED"
Bars.events[#Bars.events + 1], Bars.events[#Bars.events + 2] = "PLAYER_TARGET_CHANGED", "UNIT_LEVEL"
local COMMON_EVENTS = { SPELLS_CHANGED = true, PLAYER_ENTERING_WORLD = true,
    PLAYER_REGEN_ENABLED = true, UPDATE_BINDINGS = true }
local MAGE_EVENTS = { UNIT_AURA = true, SPELL_UPDATE_COOLDOWN = true, SPELL_UPDATE_USABLE = true,
    BAG_UPDATE_DELAYED = true, BAG_UPDATE_COOLDOWN = true, SKILL_LINES_CHANGED = true,
    GET_ITEM_INFO_RECEIVED = true, PLAYER_LEVEL_UP = true,
    PLAYER_TARGET_CHANGED = true, UNIT_LEVEL = true }
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
-- Optional families also require a learned rank in the settings list.
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

function Bars:Owns(id) return id == "classTools" or YAB.ClassTools:IsClassBar(id) end

function Bars:ConsumesEvent(event)
    if event == "WEAPON_ENCHANT_CHANGED" then return self.active.rogueTools == true or self.active.totems == true or self.active.warlockTools == true end
    if event == "GROUP_ROSTER_UPDATE" then return self.active.paladinBlessings == true or self.active.warlockTools == true end
    if event == "PLAYER_TOTEM_UPDATE" then return Totem ~= nil and self.active.totems == true end
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then return next(self.active) ~= nil end
    if event == "PLAYER_REGEN_DISABLED" then
        return self.active.paladinBlessings == true or self.active.totems == true or self.active.mageTools == true
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" and Totem and self.active.totems then return true end
    if self.mageCastEvents[event] then
        if self.active.paladinBlessings then return true end
        return self.active.mageTools == true and Config("mageTools").mageScroll ~= false
    end
    if COMMON_EVENTS[event] then return next(self.active) ~= nil end
    if self.utilityEvents[event] then
        if event == "UNIT_PET" then return self.active.warlockTools == true or self.active.aspects == true end
        if event == "UNIT_INVENTORY_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
            return self.active.totems == true or self.active.rogueTools == true or self.active.warlockTools == true
        end
        if self.active.paladinBlessings then return true end
        for id in pairs(self.active) do if YAB.UtilityTools and YAB.ClassToolData.catalog[id] then return true end end
    end
    return (self.active.mageTools == true and (MAGE_EVENTS[event] == true or COMMON_EVENTS[event] == true))
        or ((self.active.aspects or self.active.totems) and COMMON_EVENTS[event] == true)
        or (self.active.aspects == true and ASPECT_EVENTS[event] == true)
        or (self.active.totems == true and TOTEM_EVENTS[event] == true)
end

local function ResolveKnownFamily(family, knownSpells)
    for rank = #family, 1, -1 do
        local spellID = family[rank]
        local known
        if knownSpells then known = knownSpells[spellID] else known = Spell.GetKnownState(spellID) end
        if known == true then return spellID, true end
    end
    return family[1], false
end

function Bars:ResolveAspect(family)
    return ResolveKnownFamily(family, self.active.aspects and self.aspectKnown)
end

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
        if known then
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
    if YAB.UtilityTools then return YAB.UtilityTools:GetSampleSpellID(id, position, config) end
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

local function SpellTooltipTitle(tip, spellID, fallback, fallbackIcon)
    local info = spellID and Spell.GetInfo(spellID)
    local name = info and Security.SafeString(info.name)
    local icon = info and (Number(info.originalIconID) or Number(info.iconID))
    YAB.ClassTools:TooltipIconTitle(tip, name or fallback, icon or fallbackIcon)
    return name or fallback, icon or fallbackIcon
end

local function AddPetTooltipStatus(tip, name, happiness, hasPet, dead, showFood)
    if not hasPet then
        tip:AddLine(Text("class_tools.pet_absent"), 1, 0.82, 0, true)
    elseif dead then
        local status = Text("pet_utilities.dead")
        tip:AddLine(name and (name .. " · " .. status) or status, 1, 0.2, 0.2, true)
    else
        local attitude = PET_HAPPINESS[happiness]
        local status = attitude and (" |c" .. attitude.hex .. Text(attitude.key) .. "|r") or ""
        tip:AddLine((name or Text("bar.pet")) .. status, 1, 1, 1, true)
        local foods = showFood and Unit.GetPetFoodTypes()
        if foods then
            local foodText = "|cffffffff" .. table.concat(foods, ", ") .. "|r"
            tip:AddLine(string.format(Text("pet_utilities.food"), foodText), 1, 0.82, 0, true)
        end
    end
    tip:AddLine(" ")
end

local function PetUtilityTooltip(name, happiness, hasPet, dead)
    if YAB:GetDB().interaction.tooltipMode == "outOfCombat" and InCombat() then
        GameTooltip:Hide()
        return
    end
    local utilities, tip, tools = Bars.petUtilities, GameTooltip, YAB.ClassTools
    if dead == nil then dead = hasPet and Unit.IsDead("pet") end
    utilities.tooltipPetDead = dead
    tools:TooltipIconTitle(tip, Text("pet_utilities.title"), utilities.toggleState.texture)
    AddPetTooltipStatus(tip, name, happiness, hasPet, dead, true)
    local key = utilities.panel:IsShown() and "pet_utilities.collapse" or "pet_utilities.expand"
    tools:TooltipAction(tip, "LeftButton", Text(key))
    tools:TooltipSettings(tip, utilities.toggle)
    tip:Show()
end

local function Enter(button)
    if not Bars.active.aspects then return end
    local interaction = YAB:GetDB().interaction
    if interaction.tooltipMode == "outOfCombat" and InCombat() then return end
    local utilities = Bars.petUtilities
    local aspect = Bars.states[button]
    local entry = aspect or utilities.states[button]
    if not entry and button ~= utilities.toggle then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if button == utilities.toggle then
        PetUtilityTooltip(PetStatus())
        return
    end
    local tip, tools, id = GameTooltip, YAB.ClassTools, entry.spellID
    local name, icon = SpellTooltipTitle(tip, id, Text("class_tools.state_unknown"), entry.texture)
    tools:TooltipSpellEffect(tip, id)
    if aspect and Bars.currentAspect then
        local info = Spell.GetInfo(Bars.currentAspect)
        local activeIcon = info and (Number(info.originalIconID) or Number(info.iconID))
        if activeIcon then
            local iconText = YUI.GUI2.Tooltip:IconText("", activeIcon, nil, true)
            tip:AddLine(string.format(Text("class_bars.current_aspect"), iconText), 1, 1, 1, true)
            tip:AddLine(" ")
        end
    elseif not aspect then
        local name, happiness, hasPet = PetStatus()
        AddPetTooltipStatus(tip, name, happiness, hasPet, hasPet and Unit.IsDead("pet"), id == 6991)
    end
    if entry.known then
        local reason, tone = tools:SpellUseReason(id)
        tools:TooltipAction(tip, "LeftButton", name, icon, reason, nil, tone)
        if aspect then
            local unavailable
            if button:GetAttribute("*type2") ~= "macro" then unavailable = Text("class_tools.state_unknown") end
            tools:TooltipAction(tip, "RightButton", Text("class_bars.cancel_aspect"), nil, unavailable, nil, "secondary")
        end
    else
        local level = Spell.GetLevelLearned and Number(Spell.GetLevelLearned(id))
        local text = level and level > 0 and string.format(Text("class_bars.learn_level"), level)
            or Text("class_bars.unlearned")
        tip:AddLine(text, 1, 0.2, 0.2, true)
    end
    local meta = YAB.SecureFactory:GetButtonMeta(button)
    if meta and meta.classToolKey then tools:TooltipSettings(tip, button) end
    tip:Show()
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

local function SetAspectActions(factory, button, spellID, cancelMacro)
    factory:SetSecureAttribute(button, "type", spellID and "spell" or nil)
    factory:SetSecureAttribute(button, "spell", spellID)
    factory:SetSecureAttribute(button, "*type2", cancelMacro and "macro" or spellID and "none" or nil)
    factory:SetSecureAttribute(button, "*macrotext2", cancelMacro)
end

function Bars:BuildAspects(record, config)
    self:CancelAspectDrag()
    local manager, factory = YAB.BarManager, YAB.SecureFactory
    self.aspectKnown = self.aspectKnown or {}
    self.aspectBookIncomplete = nil
    local commands, seenNames = {}, {}
    for _, family in ipairs(self.aspectFamilies) do
        for _, spellID in ipairs(family) do
            local known = Security.SafeBoolean(Spell.GetKnownState(spellID))
            if known == nil then
                self.aspectBookIncomplete = true
            else
                self.aspectKnown[spellID] = known or nil
            end
            if self.aspectKnown[spellID] and not record.classBarEditing then
                local info = Spell.GetInfo(spellID)
                local name = info and Security.SafeString(info.name)
                if not name or name == "" then self.aspectBookIncomplete = true end
                if name and name ~= "" and not seenNames[name] and not name:find("[%c;%[%]]") then
                    seenNames[name] = true
                    commands[#commands + 1] = "/cancelaura " .. name
                end
            end
        end
    end
    -- The native click cancels by localized name even when the aura is secret.
    local cancelMacro = #commands > 0 and table.concat(commands, "\n") or nil
    record.buttons = {}
    for _, index in ipairs(self:GetAspectOrder(config)) do
        local family = self.aspectFamilies[index]
        local spellID, known = ResolveKnownFamily(family, self.aspectKnown)
        local visible = known
            and (not YAB.ClassTools.IsButtonEnabled or YAB.ClassTools:IsButtonEnabled("aspects", "aspect" .. index, config))
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
            SetAspectActions(factory, button, not record.classBarEditing and spellID or nil, cancelMacro)
            factory:ApplyClickAttributes(button)
            self.states[button] = self.states[button] or { visual = {} }
            local state = self.states[button]
            state.spellID, state.known = spellID, known
            local info = Spell.GetInfo(spellID)
            state.texture = info and (Number(info.originalIconID) or Number(info.iconID))
                or state.texture or "Interface\\Icons\\INV_Misc_QuestionMark"
            manager.buttonConfigSnapshots[button] = record.configSnapshot
            manager.buttonsByKey[YAB.Keybinds:GetButtonKey("aspects", index)] = button
            if YAB.ClassTools.PrepareButton then YAB.ClassTools:PrepareButton(button, "aspects", "aspect" .. index) end
            record.buttons[#record.buttons + 1] = button
            button:Show()
        elseif button then
            local entry = self.states[button]
            if entry and entry.auraDisplay then YAB.ClassTools:ReleaseAuraTimer(entry) end
            SetAspectActions(factory, button)
            button:Hide()
            self.states[button] = nil
            manager.buttonConfigSnapshots[button] = nil
            manager.buttonsByKey[YAB.Keybinds:GetButtonKey("aspects", index)] = nil
        end
    end
    self:BuildPetUtilities(record)
    record.classToolPrepared = YAB.ClassTools.GetLayoutButtons ~= nil
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
        or utilities.hasPet ~= hasPet
    state.checked, utilities.petName, utilities.happiness = checked, name, happiness
    utilities.hasPet = hasPet
    state.texture = hasPet and utilities.summonedTexture or self.petUtilityAbsentTexture
    YAB.Visuals:UpdateButton(utilities.toggle, state, "full")
    local attitude = PET_HAPPINESS[happiness]
    YAB.Visuals:SetPetHappiness(utilities.toggle, happiness ~= 3 and attitude and attitude.color or nil)
    if GameTooltip:IsOwned(utilities.toggle) then
        local dead = hasPet and Unit.IsDead("pet")
        if changed or refreshPetIcon or utilities.tooltipPetDead ~= dead then
            PetUtilityTooltip(name, happiness, hasPet, dead)
        end
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
        if visible and YAB.ClassTools.PrepareButton then YAB.ClassTools:PrepareButton(utilities.toggle, "aspects", "pet") end
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
local FLYOUT_TWO_LANE_MIN_CHOICES = 6

function Bars:LayoutFlyout(panel, opener, buttons, width, height, spacing, direction, shownOnly)
    direction = FLYOUT_POINTS[direction] and direction or "up"
    local horizontal = direction == "left" or direction == "right"
    local point, openerPoint = FLYOUT_POINTS[direction][1], FLYOUT_POINTS[direction][2]
    local count = #buttons
    if shownOnly then
        count = 0
        for _, button in ipairs(buttons) do
            if button:IsShown() then count = count + 1 end
        end
    end
    if count == 0 then return 0 end

    local lanes = count >= FLYOUT_TWO_LANE_MIN_CHOICES and 2 or 1
    local depth = math.ceil(count / lanes)
    local alongSize, acrossSize = horizontal and width or height, horizontal and height or width
    local sign = (direction == "left" or direction == "down") and -1 or 1
    local opening, index = math.max(4, spacing), 0
    -- Keep the full panel against the opener so secure auto-hide covers the gaps.
    local length = opening + depth * alongSize + (depth - 1) * spacing
    local crossLength = lanes * acrossSize + (lanes - 1) * spacing
    panel:SetSize(horizontal and length or crossLength, horizontal and crossLength or length)
    panel:ClearAllPoints()
    panel:SetPoint(point, opener, openerPoint, 0, 0)

    for _, button in ipairs(buttons) do
        if not shownOnly or button:IsShown() then
            local along = sign * (opening + math.floor(index / lanes) * (alongSize + spacing))
            local across = (index % lanes - (lanes - 1) / 2) * (acrossSize + spacing)
            button:ClearAllPoints()
            button:SetPoint(point, panel, point, horizontal and along or across, horizontal and -across or along)
            index = index + 1
        end
    end
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
    if not record.classToolPrepared then
        toggle:ClearAllPoints()
        toggle:SetPoint("TOPLEFT", record.holder, "TOPLEFT", math.max(0, offset) + col * (buttonWidth + spacing),
            -row * (buttonHeight + spacing))
    end
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
        local usable, noMana = Spell.GetUsableState(id)
        state.usable, state.noMana = Boolean(usable) ~= false, Boolean(noMana) == true
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
    if YAB.ClassTools.ReleaseButton then YAB.ClassTools:ReleaseButton(utilities.toggle) end
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

function Bars:RefreshAspectAuraStyle(button)
    local entry = self.states[button]
    if not entry or InCombat() then return end
    local record = YAB.BarManager.bars.aspects
    if not record or record.classBarEditing then
        if entry.auraDisplay then YAB.ClassTools:ReleaseAuraTimer(entry) end
        return
    end
    if not entry.auraDisplay and not (Unit.EnsureFilteredAuraDisplay and Unit.EnsureFilteredAuraDisplay()) then return end
    local index = YAB.SecureFactory:GetButtonMeta(button).index
    local style = YAB.Visuals:CaptureStatusAuraIconStyle(button)
    if not style then return end
    YAB.ClassTools:SyncAuraTimer(entry, button, "hunter-aspect-" .. index, self.aspectFamilies[index], style)
end

function Bars:RefreshAspectVisuals(record)
    local snapshot = record.configSnapshot
    local currentAspect, currentFamily
    if #record.buttons > 0 and Unit.GetPlayerAuraBySpellID then
        for index, family in ipairs(self.aspectFamilies) do
            for _, auraID in ipairs(family) do
                if Unit.GetPlayerAuraBySpellID(auraID) then
                    currentAspect, currentFamily = auraID, index
                    break
                end
            end
            if currentAspect then break end
        end
    end
    local aspectChanged = self.currentAspect ~= currentAspect
    self.currentAspect = currentAspect
    for _, button in ipairs(record.buttons) do
        local entry = self.states[button]
        local state, id = entry.visual, entry.spellID
        local index = YAB.SecureFactory:GetButtonMeta(button).index
        state.hasAction, state.texture = true, entry.texture
        state.actionID, state.rangeMode = id, "none"
        state.checked = index == currentFamily
        state.aspectActiveStyle = "dimOthers"
        -- The native icon covers this dimmed base for the exact active family.
        -- Public aura identity is only a fallback and tooltip detail.
        state.aspectDimmed = entry.auraDisplay ~= nil or not state.checked
        local usable, noMana = Spell.GetUsableState(id)
        state.usable, state.noMana = Boolean(usable) ~= false, Boolean(noMana) == true
        state.hotkeyText = snapshot.showHotkeys and YAB.Keybinds:GetBindingText(
            YAB.Keybinds:GetButtonKey("aspects", index)) or ""
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
        if aspectChanged and GameTooltip and GameTooltip:IsOwned(button) then Enter(button) end
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
local TOTEM_EVENT_WINDOW = 0.5

local function KnownTotemIcon(info)
    local icon = info and Number(info.iconID)
    return icon and icon > 0 and icon or nil
end

local function NewTotemTracking()
    return { slots = {}, active = {}, changed = {}, updatedAt = {}, opaque = {},
        elements = {}, names = {}, observation = {}, dirty = true }
end

local function RebuildTotemCatalog(totems)
    local tracking = totems.tracking
    wipe(tracking.elements)
    wipe(tracking.names)
    for element, spells in pairs(totems.spellLists) do
        for _, id in ipairs(spells) do
            tracking.elements[id] = element
            local info = Spell.GetInfo(id)
            local name = info and Security.SafeString(info.name)
            if name then
                local existing = tracking.names[name]
                if existing == nil then tracking.names[name] = element
                elseif existing ~= element then tracking.names[name] = false end
            end
        end
    end
    tracking.dirty = true
end

local function ObserveTotemCast(tracking, unit, id)
    if Security.SafeString(unit) ~= "player" then return false end
    id = Number(id)
    local element = id and tracking.elements[id]
    if not (element or id == TOTEM_RECALL or id == TOTEM_SUMMONS[1]
        or id == TOTEM_SUMMONS[2] or id == TOTEM_SUMMONS[3]) then return false end
    local now = GetTime()
    if element and (not tracking.castAt or now - tracking.castAt > TOTEM_EVENT_WINDOW) then
        tracking.castID, tracking.castElement = id, element
    else
        -- A multicast or multiple nearby casts cannot identify one new slot.
        tracking.castID, tracking.castElement = nil, nil
    end
    if id == TOTEM_RECALL then tracking.discardOpaque = true end
    tracking.castAt = now
    tracking.dirty = true
    return true
end

local function MatchTotemUpdate(tracking, now, count, learned)
    local castAt, id, element = tracking.castAt, tracking.castID, tracking.castElement
    if not (id and now - castAt <= TOTEM_EVENT_WINDOW) then return end
    local candidate
    for slot = 1, count do
        local at = tracking.updatedAt[slot]
        if at and now - at <= TOTEM_EVENT_WINDOW and math.abs(castAt - at) <= TOTEM_EVENT_WINDOW then
            if candidate then return end
            candidate = slot
        end
    end
    if not candidate then return end
    tracking.castID, tracking.updatedAt[candidate] = nil, nil
    if not tracking.opaque[candidate] then return end
    for slot, active in pairs(tracking.slots) do
        if slot ~= candidate and active.element == element and not tracking.opaque[slot] then return end
    end
    for slot, active in pairs(tracking.slots) do
        if active.element == element then tracking.slots[slot] = nil end
    end
    local info = Spell.GetInfo(id)
    tracking.slots[candidate] = { element = element, slot = candidate, spellID = id,
        name = info and Security.SafeString(info.name), icon = KnownTotemIcon(info), start = castAt, duration = learned[id],
        rate = 1, inferredAt = now, timerRevision = 1 }
end

local function RefreshTotemTracking(totems)
    local tracking = totems.tracking
    if not (Totem and tracking.dirty) then return end
    tracking.dirty = false
    local now, count = GetTime(), Totem.GetSlotCount()
    local observation = tracking.observation
    for slot = 1, count do
        local present = Totem.ReadSlot(slot, observation)
        local active = tracking.slots[slot]
        local wasOpaque = tracking.opaque[slot]
        tracking.opaque[slot] = present == nil
        if present == true then
            local id, name = observation.spellID, observation.name
            local element = tracking.elements[id] or tracking.names[name]
            if element then
                active = active or {}
                local sameSpell = active.element == element
                    and ((id and active.spellID == id) or (not id and active.name == name))
                local start, duration = observation.start, observation.duration
                local rate = observation.rate and observation.rate > 0 and observation.rate or 1
                if start and start > 0 and duration and duration > 0 then
                    if tracking.elements[id] then totems.learnedTimes[id] = duration / rate end
                    active.inferredAt = nil
                elseif not tracking.changed[slot] and not tracking.discardOpaque and sameSpell then
                    start, duration, rate = active.start, active.duration, active.rate
                else
                    start, duration = nil, nil
                    active.inferredAt = nil
                end
                if not sameSpell or tracking.changed[slot] or tracking.refreshTimers or wasOpaque
                    or start ~= active.start or duration ~= active.duration or rate ~= active.rate then
                    active.timerRevision = (active.timerRevision or 0) + 1
                end
                active.icon = observation.icon or (sameSpell and active.icon)
                    or KnownTotemIcon(id and Spell.GetInfo(id))
                active.element, active.slot, active.spellID, active.name = element, slot, id, name
                active.start, active.duration, active.rate = start, duration, rate
            else
                active = nil
            end
        elseif present == false or tracking.discardOpaque or tracking.changed[slot] then
            active = nil
        elseif active and active.inferredAt and now - active.inferredAt <= TOTEM_EVENT_WINDOW
            and next(tracking.changed) then
            -- A second slot update in the same burst makes our one-slot match ambiguous.
            active = nil
        elseif active and (tracking.refreshTimers or not wasOpaque) then
            active.timerRevision = active.timerRevision + 1
        end
        if active and active.duration and now >= active.start + active.duration / active.rate then active = nil end
        tracking.slots[slot] = active
    end
    if not tracking.discardOpaque then MatchTotemUpdate(tracking, now, count, totems.learnedTimes) end
    tracking.discardOpaque, tracking.refreshTimers = nil, nil
    wipe(tracking.changed)
    wipe(tracking.active)
    for slot, active in pairs(tracking.slots) do
        if slot > count then tracking.slots[slot] = nil
        else
            local previous = tracking.active[active.element]
            if not previous or (active.start or 0) > (previous.start or 0) then
                tracking.active[active.element] = active
            end
        end
    end
end

local function TotemSelectionDiffers(tracking, active, id, info)
    if tracking.elements[active.spellID] then return active.spellID ~= id end
    return not (active.name and info and active.name == Security.SafeString(info.name))
end

local function AddActiveTotemTooltip(tip, entry)
    local tracking = Bars.totems.tracking
    local active = tracking and tracking.active[entry.slot]
    if not active then return end
    local now = GetTime()
    local expiration = active.duration and active.start + active.duration / active.rate
    if expiration and expiration <= now then return end
    local info = not active.name and active.spellID and Spell.GetInfo(active.spellID)
    local name = active.name or (info and Security.SafeString(info.name)) or Text("class_tools.state_unknown")
    tip:AddLine(string.format(Text("class_tools.totem_active"), name), 1, 1, 1, true)
    tip:AddLine(" ")
end

local function TotemTooltip(button)
    if not Bars.active.totems then return end
    local interaction = YAB:GetDB().interaction
    if interaction.tooltipMode == "outOfCombat" and InCombat() then return end
    local entry = Bars.totems.states[button]
    if not entry then return end
    local tip, tools, spellID = GameTooltip, YAB.ClassTools, entry.spellID
    if entry.role == "slot" then
        local action = Number(button:GetAttribute("action"))
        spellID = Number(action and YAB.Adapter:GetActionSpellID(action))
    elseif entry.role == "summon" then
        spellID = Number(button:GetAttribute("spell")) or spellID
    end
    if spellID and spellID <= 0 then spellID = nil end

    tip:SetOwner(button, "ANCHOR_RIGHT")
    local name, icon
    if spellID then
        name, icon = SpellTooltipTitle(tip, spellID, Text("class_tools.state_unknown"), "Interface\\Icons\\INV_Misc_QuestionMark")
        if not entry.page then tools:TooltipSpellEffect(tip, spellID) end
    else
        tools:TooltipIconTitle(tip, _G.MULTI_CAST_TOOLTIP_NO_TOTEM or Text("class_tools.no_selection"), TOTEM_CLEAR)
    end
    if entry.role == "choice" then
        if not spellID then
            tools:TooltipAction(tip, "RightButton", Text("class_tools.clear_selection"))
        elseif entry.page then
            tools:TooltipAction(tip, "LeftButton", Text("class_tools.select_page"))
        else
            local reason, tone = tools:SpellUseReason(spellID)
            tools:TooltipAction(tip, "LeftButton", string.format(Text("class_tools.totem_cast_once"), name),
                icon, reason, nil, tone)
            tools:TooltipAction(tip, "RightButton", string.format(Text("class_tools.select_spell"), name), icon)
        end
    else
        if entry.role == "slot" then AddActiveTotemTooltip(tip, entry) end
        if spellID then
            local reason, tone = tools:SpellUseReason(spellID)
            tools:TooltipAction(tip, "LeftButton", name, icon, reason, nil, tone)
        end
        if entry.role == "summon" or entry.role == "slot" then
            if spellID then tip:AddLine(" ") end
            tip:AddLine(Text("class_tools.hover_choices"), 1, 1, 1, true)
        end
        tools:TooltipSettings(tip, button)
    end
    tip:Show()
end

local function SetTotemHovered(button, hovered)
    local entry = Bars.totems.states[button]
    if (entry.hovered == true) == hovered then return end
    entry.hovered = hovered or nil
    local manager = YAB.BarManager
    local record = manager.bars.totems
    if Bars.active.totems and entry.totemDiffers and record and button:IsVisible()
        and not record.classBarEditing and not manager.bindPresentationActive then
        Bars:RefreshTotemButton(record, button, entry)
    end
end

local function TotemEnter(button)
    SetTotemHovered(button, true)
    TotemTooltip(button)
end

local function TotemLeave(button)
    SetTotemHovered(button, false)
    Leave(button)
end

local function TotemHide(button)
    Bars.totems.states[button].hovered = nil
    Leave(button)
end

function Bars:CloseTotemFlyout()
    local record = YAB.BarManager.bars.totems
    if not record or not record.totemController then return end
    if InCombat() then return end
    YAB.SecureFactory:CloseTotemPanels(record.totemController)
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
        if entry then
        YAB.SecureFactory:SetSecureAttribute(button, "type", enabled and entry.known
            and (entry.role == "slot" and "action" or "spell") or nil)
        YAB.SecureFactory:SetSecureAttribute(button, "*type-Keybind", enabled and entry.known
            and (entry.role == "slot" and "action" or "spell") or "none")
        end
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
        if not YAB.BarManager:SuppressNativeClassFrame(record, frame) then
            self.nativeFrames[frame] = nil
            return false
        end
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
        button:HookScript("OnEnter", role == "slot" and TotemEnter or TotemTooltip)
        button:HookScript("OnLeave", role == "slot" and TotemLeave or Leave)
        if role == "slot" then button:HookScript("OnHide", TotemHide) end
    end
    if button:GetParent() ~= parent then button:SetParent(parent) end
    return button, totems.states[button]
end

function Bars:SyncTotemCommands(record)
    local totems, factory, manager = self.totems, YAB.SecureFactory, YAB.BarManager
    local page = Number(record.totemController:GetAttribute("totem-page")) or 1
    local positions, position = {}, 0
    for _, slot in ipairs(TOTEM_PRIORITY) do
        if #(totems.spellLists[slot] or {}) > 0 then position = position + 1; positions[slot] = position end
    end
    for _, button in ipairs(record.buttons) do
        local entry, command = totems.states[button]
        if entry then
        if entry.role == "slot" then
            command = "MULTICASTACTIONBUTTON" .. ((page - 1) * 4 + positions[entry.slot])
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
    local function Bind(role, index, command, action, spell, key)
        local button = self:GetTotemButton(record, role, index, record.totemController)
        factory:SetSecureAttribute(button, "type", YAB.ClassTools:IsButtonEnabled("totems", key) and (action and "action" or spell and "spell") or nil)
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
                YUI.API.ActionBar:GetMultiCastActionSlot(page, slot), nil, ({[1]="fire",[2]="earth",[3]="water",[4]="air"})[slot])
        end
        if Spell.GetKnownState(TOTEM_SUMMONS[page]) then
            Bind("bindingSummon", page, "MULTICASTSUMMONBUTTON" .. page, nil, TOTEM_SUMMONS[page], "summon")
        end
    end
    if Spell.GetKnownState(TOTEM_RECALL) then
        local recall = self:GetTotemButton(record, "recall", 1)
        factory:SetSecureAttribute(recall, "*type-Keybind", YAB.ClassTools:IsButtonEnabled("totems", "recall") and "spell" or "none")
        factory:SetSecureAttribute(recall, "*spell-Keybind", TOTEM_RECALL)
        count = count + 1
        local entry = bindings[count] or {}; bindings[count] = entry
        ReadTotemBinding("MULTICASTRECALLBUTTON1", entry)
        entry.buttonName, entry.clickButton = recall:GetName(), "Keybind"
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
    totems.tracking = totems.tracking or NewTotemTracking()
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
        if YAB.ClassTools.ReleaseButton then YAB.ClassTools:ReleaseButton(button) end
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
        local key = role == "slot" and ({[1]="fire",[2]="earth",[3]="water",[4]="air"})[slot] or role
        if not YAB.ClassTools:IsButtonEnabled("totems", key, config) then return end
        if not visible and not record.classBarEditing then return end
        local button, entry = self:GetTotemButton(record, role, slot)
        local meta = factory:GetButtonMeta(button)
        meta.buttonKey = "totems." .. (role == "slot" and slot or role)
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
        if YAB.ClassTools.PrepareButton then YAB.ClassTools:PrepareButton(button, "totems", key) end
        return button
    end
    Main("summon", 1, TOTEM_SUMMONS[page], Spell.GetKnownState(TOTEM_SUMMONS[page]) == true)
    for _, slot in ipairs(TOTEM_PRIORITY) do
        totems.spellLists[slot] = api:GetMultiCastSpells(slot, totems.spellLists[slot])
        Main("slot", slot, nil, #totems.spellLists[slot] > 0)
    end
    RebuildTotemCatalog(totems)
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
            factory:SetSecureAttribute(button, "type", nil)
            factory:SetSecureAttribute(button, "type1", panelIndex > 1 and spell > 0 and "spell" or nil)
            factory:SetSecureAttribute(button, "type2", panelIndex > 1 and "multispell" or nil)
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
            factory:SetSecureAttribute(choices[index], "type1", nil)
            factory:SetSecureAttribute(choices[index], "type2", nil)
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
    if YAB.UtilityTools then YAB.UtilityTools:Build(record, config, true) end
    record.classToolPrepared = YAB.ClassTools.GetLayoutButtons ~= nil
end

local function TotemCooldownDone(cooldown)
    local button = cooldown:GetParent()
    local entry = Bars.totems.states[button]
    if not (Bars.active.totems and entry and entry.cooldownHook == cooldown
        and not entry.cooldownUpdating and entry.visual.cooldownActive == true and button:IsVisible()) then return end
    entry.visual.cooldownActive, entry.visual.cooldownEnable = false, false
    local id = entry.visual.actionID
    if id and id > 0 then
        local usable, noMana = Spell.GetUsableState(id)
        entry.visual.usable, entry.visual.noMana = Boolean(usable) ~= false, Boolean(noMana) == true
    end
    YAB.Visuals:UpdateButton(button, entry.visual, ":cooldownMeta:usable:")
end

local function TotemLifetimeDone(cooldown)
    local totems = Bars.totems
    local entry = totems.states[cooldown:GetParent()]
    if not (Bars.active.totems and entry and entry.lifetimeTimer == cooldown
        and entry.timerShown and not entry.timerUpdating) then return end
    local tracking, active = totems.tracking, entry.liveTotem
    if not (tracking and active and entry.timerRevision == active.timerRevision
        and tracking.slots[active.slot] == active and tracking.active[active.element] == active) then return end
    tracking.slots[active.slot], tracking.active[active.element] = nil, nil
    YAB.BarManager:QueueSpecialRefresh("totems", "totem expired")
end

local function UpdateTotemLifetime(totems, entry)
    local tracking = totems.tracking
    local active = tracking.active[entry.slot]
    local revision = active and active.timerRevision
    if entry.liveTotem ~= active or entry.timerRevision ~= revision then
        entry.timerUpdating = true
        local clock = active and Totem.GetSlotDuration(active.slot)
        local start, duration, rate
        if active and active.duration and GetTime() < active.start + active.duration / active.rate then
            start, duration, rate = active.start, active.duration, active.rate
        end
        local shown, native = YAB.Visuals:ApplyTotemTimer(entry.lifetimeTimer, clock, start, duration, rate)
        entry.timerShown = shown
        entry.timerEstimated = shown and not native and active.inferredAt ~= nil
        entry.liveTotem, entry.timerRevision = active, revision
        entry.timerUpdating = nil
    end
    return active
end

function Bars:ApplyTotemLayout(record, config, db)
    if InCombat() then self.pending = true; return end
    if not record.totemController then return end
    local manager, snapshot = YAB.BarManager, record.configSnapshot
    local layoutButtons = record.classToolPrepared and YAB.ClassTools:GetLayoutButtons(record) or record.buttons
    local count = math.max(#layoutButtons, 1)
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
        if entry and entry.role == "slot" and Totem then
            entry.lifetimeTimer = entry.lifetimeTimer or YAB.Visuals:PrepareTotemTimer(button, nil, TotemLifetimeDone)
            entry.timerRevision = nil
        end
        manager.buttonConfigSnapshots[button] = snapshot
        record.classButtons[#record.classButtons + 1] = button
    end
    record.classButtons = {}
    for position, button in ipairs(layoutButtons) do
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

function Bars:RefreshTotemButton(record, button, entry, page)
    local totems, snapshot = self.totems, record.configSnapshot
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
    local selectedIcon = info and info.iconID
    local activeIcon, showActive
    if entry.role == "slot" and Totem then
        selectedIcon = KnownTotemIcon(info)
        local active = UpdateTotemLifetime(totems, entry)
        local differs = active and TotemSelectionDiffers(totems.tracking, active, id, info)
        entry.totemDiffers = differs
        local editing = record.classBarEditing or YAB.BarManager.bindPresentationActive
        activeIcon = active and (active.icon or (not differs and selectedIcon))
        showActive = activeIcon and not editing and (not differs or not entry.hovered)
        state.hideTotemLifetimeNumbers = not showActive
        state.hideCooldownNumbers = showActive and entry.timerShown
        state.countText = showActive and entry.timerEstimated and "~" or differs and "•" or ""
    end
    local actionPresentation = not (showActive and entry.totemDiffers)
    state.texture = showActive and activeIcon or selectedIcon
        or (id and id > 0 and "Interface\\Icons\\INV_Misc_QuestionMark") or TOTEM_CLEAR
    state.hasAction, state.actionID, state.rangeMode = true, id, "none"
    state.unlearned = entry.known == false
    state.usable, state.noMana = not state.unlearned, false
    state.checked = (entry.page ~= nil and entry.page == page) or (entry.role == "choice" and entry.slot > 0
        and (id > 0 and id or false) == totems.selected[entry.slot])
    if actionPresentation and id and id > 0 then
        local usable, noMana = Spell.GetUsableState(id)
        state.usable, state.noMana = Boolean(usable) ~= false, Boolean(noMana) == true
    end
    local command = YAB.SecureFactory:GetButtonMeta(button).commandName
    local binding = command and totems.bindingByCommand[command]
    state.hotkeyText = snapshot.showHotkeys and binding and binding.primaryText or ""
    local cooldownID = actionPresentation and id or nil
    if entry.cooldownSpellID ~= cooldownID then
        entry.cooldownSpellID, state.cooldownActive = cooldownID, false
    end
    state.cooldownDurationObject = nil
    state.cooldownStart, state.cooldownDuration, state.cooldownModRate = nil, nil, nil
    state.cooldownEnable = false
    if cooldownID and cooldownID > 0 then
        -- Readable native values use the shared unchanged-cooldown cache.
        -- Restricted values remain transient inputs to the native duration sink.
        local cooldown = Spell.GetCooldown(cooldownID)
        if cooldown then
            state.cooldownStart, state.cooldownDuration = cooldown.startTime, cooldown.duration
            state.cooldownEnable, state.cooldownModRate = cooldown.isEnabled, cooldown.modRate
        else
            state.cooldownDurationObject = Spell.GetCooldownDurationObject(cooldownID)
            state.cooldownEnable = state.cooldownDurationObject and true or false
        end
        -- Public rule flags distinguish real cooldowns from the GCD,
        -- including when the native duration itself is restricted.
        local active, resolved = Spell.ReadCooldownRuleState(cooldownID)
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

function Bars:RefreshTotemVisuals(record, prepareHidden)
    local totems = self.totems
    RefreshTotemTracking(totems)
    local page = Number(record.totemController:GetAttribute("totem-page")) or 1
    for _, button in ipairs(record.classButtons) do
        local entry = totems.states[button]
        if entry and (prepareHidden or button:IsVisible()) then self:RefreshTotemButton(record, button, entry, page) end
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
        elseif id == "totems" then
            self:BuildTotems(record, config)
            self:ApplyTotemLayout(record, config, YAB:GetDB())
            if YAB.UtilityTools then YAB.UtilityTools:Layout(record) end
        elseif id == "paladinBlessings" then
            YAB.PaladinBlessings:BuildStandalone(record, config)
            record.configSnapshot.buttons = math.max(#record.buttons, 1)
            YAB.BarManager:ApplyLayout(record, config, YAB:GetDB())
            YAB.PaladinBlessings:Layout(YAB.PaladinBlessings.entry, record)
        elseif YAB.UtilityTools then
            YAB.UtilityTools:Build(record, config)
            record.configSnapshot.buttons = math.max(#record.buttons, 1)
            YAB.BarManager:ApplyLayout(record, config, YAB:GetDB())
            YAB.UtilityTools:Layout(record)
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
    if id == "paladinBlessings" then
        YAB.UtilityTools:ReadInventory("paladinTools")
        YAB.PaladinBlessings:Refresh(YAB.PaladinBlessings.entry)
    elseif YAB.UtilityTools then YAB.UtilityTools:Refresh(record) end
    self.passes = self.passes + 1
end

function Bars:OnEvent(event, ...)
    if event == "PLAYER_TARGET_CHANGED" or event == "UNIT_LEVEL" then
        if self.active.mageTools and YAB.UtilityTools
            and (event ~= "UNIT_LEVEL" or Security.SafeString((...)) == "target") then
            YAB.UtilityTools:RefreshConjureTargetTooltip()
        end
        return
    end
    if self.totemRestorePending and not InCombat()
        and (event == "PLAYER_ENTERING_WORLD" or event == "ADDON_RESTRICTION_STATE_CHANGED") then
        self:SyncEnabled("totems")
    end
    local tracking = self.active.totems and self.totems.tracking
    if tracking and Totem then
        if event == "ADDON_RESTRICTION_STATE_CHANGED" then
            tracking.dirty, tracking.refreshTimers = true, true
        elseif event == "PLAYER_TOTEM_UPDATE" then
            local slot = Number((...))
            if slot and slot % 1 == 0 and slot >= 1 and slot <= Totem.GetSlotCount() then
                tracking.changed[slot], tracking.updatedAt[slot] = true, GetTime()
            else
                tracking.discardOpaque, tracking.castID = true, nil
                wipe(tracking.updatedAt)
            end
            tracking.dirty = true
            YAB.BarManager:QueueSpecialRefresh("totems", event)
            return
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" and ObserveTotemCast(tracking, select(1, ...), select(3, ...)) then
            YAB.BarManager:QueueSpecialRefresh("totems", event)
        elseif event == "PLAYER_ENTERING_WORLD" then
            self.totems.tracking = NewTotemTracking()
            RebuildTotemCatalog(self.totems)
            -- The old region may have the same numeric revision after a reset.
            for _, entry in pairs(self.totems.states) do entry.timerRevision = nil end
        elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
            tracking.dirty, tracking.refreshTimers = true, true
        end
    end
    if event=="UNIT_AURA" then
        local unit=Security.SafeString((...))
        if self.active.paladinBlessings and YAB.PaladinBlessings then YAB.PaladinBlessings:OnUnitAura(unit) end
        if self.active.warlockTools and YAB.SoulstoneBinding then YAB.SoulstoneBinding:OnUnitAura(unit) end
        if unit and unit~="player" then return end
    end
    if self.active.paladinBlessings and YAB.PaladinBlessings then YAB.PaladinBlessings:OnEvent(event, ...) end
    if self.active.warlockTools and YAB.SoulstoneBinding then YAB.SoulstoneBinding:OnEvent(event, ...) end
    if YAB.UtilityTools then YAB.UtilityTools:OnEvent(event, ...) end
    if self.active.mageTools and YAB.UtilityTools and (event == "PLAYER_REGEN_DISABLED"
        or event == "PLAYER_REGEN_ENABLED" or event == "ADDON_RESTRICTION_STATE_CHANGED") then
        YAB.UtilityTools:RefreshConjureTargetTooltip()
    end
    if self.active.mageTools then YAB.MageTools:OnEvent(event, ...) end
    if self.mageCastEvents[event] then return end
    if event == "UNIT_HAPPINESS" or event == "UNIT_NAME_UPDATE" or event == "UNIT_PET" then
        self:RefreshPetUtilityToggle(event == "UNIT_PET")
        if event ~= "UNIT_PET" then return end
    end
    if event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        self.structureDirty, self.configDirty.totems = true, true
    end
    if self.active.aspects and self.aspectBookIncomplete
        and (event == "ADDON_RESTRICTION_STATE_CHANGED" or event == "PLAYER_REGEN_ENABLED") then
        self.configDirty.aspects = true
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if self.pending then
            self.pending = false
            self:SyncEnabled()
        else
            if self.totemRestorePending then self:SyncEnabled("totems") end
            for id in pairs(self.active) do YAB.BarManager:QueueSpecialRefresh(id, event) end
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

local function SyncBarEnabled(self, id, runtimeEnabled, class)
    local config = Config(id)
    local wanted = runtimeEnabled and config and config.enabled
        and class == YAB.ClassTools:GetClassToken(id)
        and (id == "aspects" or id == "totems" or id == "mageTools" or YAB.UtilityTools ~= nil)
    if wanted then
        if id == "totems" then self.totemRestorePending = nil end
        local wasActive = self.active[id]
        local record = self:EnsureRecord(id)
        self.active[id] = record and true or nil
        if record and id == "totems" and not record.nativeTotemFrame and not self:AttachTotems(record) then
            self:StopBar(id)
            return
        end
        if record then
            self.configDirty[id] = true
            self:Refresh(id)
            return not wasActive and id ~= "aspects"
        end
    elseif self.active[id] then
        local stopped, reason = self:StopBar(id)
        if not stopped then return nil, reason end
    end
end

function Bars:SyncEnabled(id)
    if InCombat() then self.pending = true; return end
    local db, manager = YAB:GetDB(), YAB.BarManager
    local runtimeEnabled = db.enabled and manager.runtimeActive
    local class = YAB.SpecialBars:GetPlayerClassToken()
    local refreshBindings, failure
    if id then
        refreshBindings, failure = SyncBarEnabled(self, id, runtimeEnabled, class)
    else
        for _, barId in ipairs(YAB.ClassTools.ids) do
            local refresh, reason = SyncBarEnabled(self, barId, runtimeEnabled, class)
            if refresh then refreshBindings = true end
            failure = failure or reason
        end
    end
    if refreshBindings then YAB.Keybinds:ApplyRuntimeBindings() end
    if failure then return false, failure end
    local layout = YAB.LayoutBridge
    if id then layout:SyncClassToolsMover("classTools") end
    layout:SyncClassToolsMover(id, class)
    self.listening = next(self.active) ~= nil
    manager:SyncClassBarEvents()
    if manager.RefreshActionBroadcasterMode then manager:RefreshActionBroadcasterMode("class bars") end
    return true
end

function Bars:StopBar(id)
    if InCombat() then self.pending = true; return false end
    if not self.active[id] and not YAB.BarManager.bars[id] then return true end
    if id == "totems" then
        -- Keep our functional bar and the original parent if the handoff fails.
        for frame, state in pairs(self.nativeFrames) do
            if not YAB.BarManager:RestoreNativeClassFrame(frame, state) then
                self.totemRestorePending = true
                return false, "native totem restoration pending"
            end
            self.nativeFrames[frame] = nil
        end
        self.totemRestorePending = nil
        self:CloseTotemFlyout()
    end
    self.active[id] = nil
    if id == "aspects" then self.aspectKnown, self.aspectBookIncomplete = nil, nil end
    if id == "paladinBlessings" and YAB.PaladinBlessings.entry then YAB.PaladinBlessings:Stop(YAB.PaladinBlessings.entry) end
    if YAB.UtilityTools then YAB.UtilityTools:Stop(id) end
    if id == "totems" then
        local record, factory, manager = YAB.BarManager.bars[id], YAB.SecureFactory, YAB.BarManager
        if record and record.totemController then
            record.totemController:SetAttribute("interactive", false)
            ClearOverrideBindings(record.totemController)
        end
        local function Release(button)
            factory:SetSecureAttribute(button, "type", nil)
            button:Hide()
            local entry = self.totems.states[button]
            if entry then
                if entry.role == "choice" then
                    factory:SetSecureAttribute(button, "type1", nil)
                    factory:SetSecureAttribute(button, "type2", nil)
                end
                if entry.lifetimeTimer then
                    entry.timerShown, entry.timerEstimated, entry.liveTotem, entry.timerRevision = nil, nil, nil, nil
                    YAB.Visuals:ApplyTotemTimer(entry.lifetimeTimer)
                end
            end
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
        self.totems.tracking = nil
        if YUI.Layout and YUI.Layout.ReleaseNativeEditModeOwner then YUI.Layout:ReleaseNativeEditModeOwner(self) end
        if record then
            record.buttons, record.classButtons = {}, {}
            if record.nativeTotemFrame and _G.ChangeMultiCastActionPage then
                local page = record.totemController and Number(record.totemController:GetAttribute("totem-page")) or 1
                ChangeMultiCastActionPage(page)
            end
            record.nativeTotemFrame = nil
        end
    elseif id == "mageTools" then
        YAB.MageTools:Stop()
    elseif id == "aspects" then
        self:CancelAspectDrag()
        self:StopPetUtilities()
        self.currentAspect = nil
        for index, button in pairs(self.pool) do
            local entry = self.states[button]
            if entry and entry.auraDisplay then YAB.ClassTools:ReleaseAuraTimer(entry) end
            if YAB.ClassTools.ReleaseButton then YAB.ClassTools:ReleaseButton(button) end
            SetAspectActions(YAB.SecureFactory, button)
            button:Hide()
            self.states[button] = nil
            YAB.BarManager.buttonsByKey[YAB.Keybinds:GetButtonKey("aspects", index)] = nil
            YAB.Visuals:ReleaseButton(button)
            if GameTooltip and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        end
    end
    YAB.BarManager:DeactivateBar(id)
    YAB.Keybinds:ApplyRuntimeBindings()
    self.configDirty[id] = nil
    return true
end

function Bars:Stop()
    if InCombat() then self.pending = true; return false end
    for _, id in ipairs(YAB.ClassTools.ids) do
        local stopped, reason = self:StopBar(id)
        if not stopped then return false, reason end
    end
    self.listening, self.pending, self.structureDirty = false, false, true
    YAB.BarManager:SyncClassBarEvents()
    return true
end

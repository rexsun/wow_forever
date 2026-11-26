local YUI = _G.YUI
local YAB = YUI and YUI.YActionBar
if not (YAB and YAB.Client and YAB.Client.classBars) then return end

local Tools, Data = YAB.ClassTools, YAB.ClassToolData
local Spell, Item, Unit, Security = YUI.API.Spell, YUI.API.Item, YUI.API.Unit, YUI.API.Security
local Utility = { records = {}, states = {}, itemEffects = {},
    inventoryDirty = true, bookDirty = true, auraDirty = true }
YAB.UtilityTools = Utility
local function Number(value) return Security.SafeNumber(value) end
local function Text(key) return YUI.Locale:Get("YActionBar")["class_tools." .. key] end
local function Info(id) return id and Spell.GetInfo(id) end
local function Name(id) local info = Info(id); return info and Security.SafeString(info.name) end
local function Texture(id) local info = Info(id); return info and (Number(info.originalIconID) or Number(info.iconID)) end
local function TracksAuraIdentity(definition)
    return definition.shield or definition.auraPriority or definition.activeAura or definition.aura and definition.right ~= nil
end
local function IsWeaponItem(definition)
    return definition.weaponSlot ~= nil and definition.items ~= nil
end
local function PreviewsLeftOnHover(definition)
    return definition.hoverMenu or definition.auraPriority or definition.activeAura or IsWeaponItem(definition) or definition.binding
end
local function OtherShield(entry, selected)
    for _, variant in ipairs(entry.variants) do
        if variant ~= selected then return variant end
    end
end
local function IsEarthShield(id) return id == 408514 or id == 408519 end
local function Count(item) return item and Utility.counts and Utility.counts[item] end
local function CountText(count) return count ~= nil and tostring(count) or "—" end
local function Now() return YUI.API.System and YUI.API.System.GetTime and Number(YUI.API.System.GetTime()) end
local function Label(entry, text)
    if entry.label and entry.labelText ~= text then entry.label:SetText(text); entry.labelText = text end
end

local function AuraIsActive(aura, now)
    return aura and (not now or not aura.expirationTime or aura.expirationTime == 0 or aura.expirationTime > now)
end

function Utility:SoulstoneStatus(entry)
    local now = Now()
    local aura = self.auras and self.auras[entry.key]
    if AuraIsActive(aura, now) then return aura, nil, true end
    local known = self.auras ~= nil and not entry.auraNamesIncomplete
        and not (self.auraUnavailable and self.auraUnavailable[entry.key])
    local peer = known and YAB.SoulstoneBinding and YAB.SoulstoneBinding.binding
    return nil, AuraIsActive(peer, now) and peer or nil, known
end

function Utility:ReadBook()
    if not self.bookDirty then return end
    self.book = {}
    if Spell.ReadRankedPlayerSpellBook then
        local entries = Spell.ReadRankedPlayerSpellBook()
        self.bookReady = type(entries) == "table"
        for _, entry in ipairs(entries or {}) do self.book[entry.spellID] = true end
    end
    self.bookDirty = nil
end

function Utility:Known(id)
    if self.bookReady then return self.book[id] == true end
    return self.book and self.book[id] == true or Spell.GetKnownState(id) == true
end

function Utility:Highest(family)
    for index = #(family or {}), 1, -1 do if self:Known(family[index]) then return family[index] end end
end

function Utility:ReadPoisonSkill()
    local profession = YUI.API.Profession
    local rank = profession and profession.GetSkillLineRank and Number(profession.GetSkillLineRank(Data.poisonSkillLine))
    local known = Security.SafeBoolean(Spell.GetKnownState(Data.poisonSkillSpell))
    if rank and rank > 0 or known == true or self.book[Data.poisonSkillSpell] then
        self.poisonLearned = true
    elseif rank == 0 or known == false then
        self.poisonLearned = false
    end
end

local function ClearWeaponItem(effect)
    effect.itemID, effect.expiration, effect.duration = nil, nil, nil
end

local function ReadWeaponItem(effect, weapon, enchant, itemsByEnchant, now)
    local has = enchant and Security.SafeBoolean(enchant.hasEnchant)
    local enchantID = enchant and Number(enchant.enchantID)
    local remaining = enchant and Number(enchant.remainingMS)
    effect.known = has == false or has == true and enchantID ~= nil
    effect.unknown = weapon.canEnchant ~= false and (not effect.known or weapon.canEnchant == nil)
    if weapon.canEnchant == false or has == false then
        ClearWeaponItem(effect)
    elseif effect.known then
        local item = itemsByEnchant[enchantID]
        if item ~= effect.itemID then ClearWeaponItem(effect) end
        effect.itemID = item
        if item then
            if remaining and now and weapon.canEnchant then
                effect.duration = math.max(0, remaining / 1000)
                effect.expiration = now + effect.duration
            end
            effect.unknown = remaining == nil or now == nil or weapon.canEnchant == nil
        end
    end
end

local function FindWarlockStoneEnchant(read)
    local imbue, temporary = read.imbue, read.temporary
    local stones = Data.warlockStoneByEnchant
    if imbue.hasEnchant == true and stones[imbue.enchantID] then return imbue end
    if temporary.hasEnchant == true and stones[temporary.enchantID] then return temporary end

    -- Clear a previous stone only when neither slot could still contain it.
    local imbueKnown = imbue.hasEnchant == false or imbue.hasEnchant == true and imbue.enchantID ~= nil
    local temporaryKnown = temporary.hasEnchant == false or temporary.hasEnchant == true and temporary.enchantID ~= nil
    if imbueKnown and temporaryKnown then return imbue end
end

function Utility:ReadItemWeapon(weapon, slot, sharpening)
    local rawItemID = Item.GetInventoryItemID("player", slot)
    local itemID = Number(rawItemID)
    local empty = itemID == nil and not Security.IsSecretValue(rawItemID) and rawItemID == nil
    if weapon.itemReset or itemID and weapon.itemID and itemID ~= weapon.itemID then
        ClearWeaponItem(weapon.imbue)
        if weapon.temporary then ClearWeaponItem(weapon.temporary) end
    end
    weapon.itemReset = nil
    if empty or itemID then weapon.itemID = itemID end
    local equipLoc, classID, subclassID
    if itemID and Item.GetInfoInstant then
        local _, _, _, location, _, class, subclass = Item.GetInfoInstant(itemID)
        equipLoc, classID, subclassID = Security.SafeString(location), Number(class), Number(subclass)
    end
    equipLoc = equipLoc or itemID and Security.SafeString(Item.GetEquipLoc(itemID))
    weapon.canEnchant = not empty and equipLoc and (classID == nil or classID == 2)
        and equipLoc ~= "INVTYPE_SHIELD" and equipLoc ~= "INVTYPE_HOLDABLE"
    weapon.weaponMask = subclassID and 2 ^ subclassID

    local read, supported
    if Item.ReadWeaponEnchants then read, supported = Item.ReadWeaponEnchants(slot, weapon.read) end
    local enchant
    if read then
        if sharpening then enchant = read.imbue
        else enchant = FindWarlockStoneEnchant(read) end
    elseif not supported and Item.ReadWeaponEnchant then
        enchant = Item.ReadWeaponEnchant(slot, weapon.read.imbue)
        local legacyID = enchant and Number(enchant.enchantID)
        if sharpening and legacyID and Data.sharpeningByEnchant[legacyID] then enchant = nil end
    end
    local now = Now()
    local itemsByEnchant = sharpening and Data.poisonByEnchant or Data.warlockStoneByEnchant
    ReadWeaponItem(weapon.imbue, weapon, enchant, itemsByEnchant, now)
    if sharpening then ReadWeaponItem(weapon.temporary, weapon, read and read.temporary, Data.sharpeningByEnchant, now) end
end

local function ReadImbuedWeapon(weapon, slot)
    local itemID = Number(Item.GetInventoryItemID("player", slot))
    local equipLoc = itemID and Security.SafeString(Item.GetEquipLoc(itemID))
    weapon.canEnchant = equipLoc and equipLoc ~= "INVTYPE_SHIELD" and equipLoc ~= "INVTYPE_HOLDABLE"
    local read = Item.ReadWeaponEnchant and Item.ReadWeaponEnchant(slot, weapon.imbueRead)
    if read then weapon.imbueRead = read end
    local has = read and Security.SafeBoolean(read.hasEnchant)
    local id = read and Number(read.enchantID)
    local remaining = read and Number(read.remainingMS)
    -- A failed read can reuse a confirmed deadline until a change invalidates it.
    if weapon.imbueReset or itemID and weapon.itemID and itemID ~= weapon.itemID
        or (has == nil or has == true and not id) and not weapon.expiration
        or weapon.canEnchant == false or has == false or has == true and id and id ~= weapon.enchantID then
        weapon.enchantID, weapon.expiration, weapon.duration = nil, nil, nil
    end
    weapon.imbueReset = nil
    if itemID then weapon.itemID = itemID end
    weapon.imbueAbsent = has == false
    weapon.imbueUnknown = has == nil or has == true and (not id or not remaining)
    if has == true and id and weapon.canEnchant ~= false then
        weapon.enchantID = id
        local now = Now()
        if itemID and weapon.canEnchant and now and remaining then
            weapon.duration = math.max(0, remaining / 1000)
            weapon.expiration = now + weapon.duration
        end
    end
end

function Utility:PrepareWeaponItems(id)
    self.weaponVariants = self.weaponVariants or {}
    for _, definition in pairs(Data.catalog[id]) do
        if IsWeaponItem(definition) then
            for _, itemID in ipairs(definition.items) do
                local variant = self.weaponVariants[itemID]
                if not variant then
                    variant = {value=itemID, itemID=itemID, level=Data.items[itemID].level}
                    self.weaponVariants[itemID] = variant
                end
                if not variant.texture then variant.texture = Item.GetIcon(itemID) end
            end
        end
    end
end

function Utility:WeaponItemDisplay(entry, fallback)
    local definition = entry.definition
    local weapon = self.weapons and self.weapons[definition.weaponSlot]
    local effect = weapon and (definition.sharpening and weapon.temporary or weapon.imbue)
    local item = effect and effect.itemID
    if item and definition.stone and not Data:SupportsSelection(entry.id, entry.key, item) then return fallback, weapon end
    local alternate = definition.sharpening and item and Data.sharpeningAlternates[item]
    if alternate and self.level and self.level >= Data.items[alternate].level and (Count(alternate) or 0) > 0 then
        local selected = entry.selected and entry.selected.itemID
        if selected == alternate or Count(item) == 0 or self.level < Data.items[item].level then item = alternate end
    end
    return item and self.weaponVariants[item] or fallback, weapon, effect
end

function Utility:ReadInventory(id)
    if not self.inventoryDirty or id == "aspects" then return end
    self.counts = self.counts or {}
    local wanted = {}
    for _, definition in pairs(Data.catalog[id] or {}) do
        for _, item in ipairs(definition.items or {}) do wanted[item] = true end
        if definition.counter then wanted[definition.counter] = true end
        for _, family in ipairs(definition.families or {}) do
            for _, spell in ipairs(family) do
                local product, reagent = Data.products[spell], Data.reagents[spell]
                if product then wanted[product.itemID] = true end
                if reagent then wanted[reagent.itemID] = true end
            end
        end
        for _, spell in ipairs(definition.right or {}) do local reagent = Data.reagents[spell]; if reagent then wanted[reagent.itemID] = true end end
        for _, family in pairs(definition.greater or {}) do
            for _, spell in ipairs(family) do local reagent = Data.reagents[spell]; if reagent then wanted[reagent.itemID] = true end end
        end
    end
    for item in pairs(wanted) do
        local count = Number(Item.GetCount(item, false, false, false, false))
        self.counts[item] = count and math.max(0, count) or nil
    end
    self.itemKnowledge = self.itemKnowledge or {}
    for _, definition in pairs(Data.catalog[id] or {}) do
        local ready = true
        for _, item in ipairs(definition.items or {}) do if self.counts[item] == nil then ready = false; break end end
        self.itemKnowledge[definition] = ready
    end
    self.level = Number(Unit.GetPlayerLevel())
    self.weapons = self.weapons or {}
    if id == "rogueTools" or id == "warlockTools" then
        local sharpening = id == "rogueTools"
        for slot = 16, sharpening and 17 or 16 do
            local weapon = self.weapons[slot]
            if not weapon then
                weapon = {imbue={}, temporary=sharpening and {} or nil, read={imbue={}, temporary={}}}
                self.weapons[slot] = weapon
            end
            self:ReadItemWeapon(weapon, slot, sharpening)
        end
    elseif id == "totems" then
        local slot = Data.catalog.totems.imbue.weaponSlot
        local weapon = self.weapons[slot] or {}; self.weapons[slot] = weapon
        ReadImbuedWeapon(weapon, slot)
    end
    self.inventoryDirty = nil
end

function Utility:Variants(definition, selected)
    local variants = {}
    if definition.manaGemSlot then
        local spell = self.manaGemSpells[definition.manaGemSlot]
        if spell then variants[1] = {value=spell, spellID=spell} end
    elseif definition.poison or definition.sharpening then
        local weapon = definition.sharpening and self.weapons and self.weapons[definition.weaponSlot]
        for _, item in ipairs(definition.items) do
            local data, count = Data.items[item], Count(item)
            local fits = not definition.sharpening or weapon and weapon.canEnchant and weapon.weaponMask
                and math.floor(data.weaponMask / weapon.weaponMask) % 2 == 1
            if fits and count and count > 0 and self.level and self.level >= data.level then
                variants[#variants + 1] = { value = item, itemID = item, level = data.level }
            end
        end
        -- Keep the chosen poison's identity when its last dose is used.
        if definition.poison and selected and Data:SupportsSelection("rogueTools", "mainhand", selected) then
            local found
            for _, variant in ipairs(variants) do if variant.value == selected then found = true end end
            if not found then variants[#variants + 1] = { value = selected, itemID = selected, unavailable = true } end
        end
    else
        for _, family in ipairs(definition.families or {}) do
            if definition.ranks then
                for _, spell in ipairs(family) do if self:Known(spell) then variants[#variants + 1] = {value=spell, spellID=spell} end end
            else
                local spell = self:Highest(family)
                if spell then variants[#variants + 1] = {value=spell, spellID=spell, family=family[1]} end
                local greater = definition.greater and self:Highest(definition.greater[family[1]])
                if greater then variants[#variants + 1] = {value=greater, spellID=greater, family=family[1]} end
            end
        end
    end
    for _, variant in ipairs(variants) do
        if variant.itemID then variant.texture = Item.GetIcon(variant.itemID)
        else
            local info = Info(variant.spellID)
            variant.name = info and Security.SafeString(info.name)
            variant.texture = info and (Number(info.originalIconID) or Number(info.iconID))
            local product = definition.conjured and Data.products[variant.spellID]
            local itemInfo = product and Item.GetInfo(product.itemID)
            variant.productName = itemInfo and Security.SafeString(itemInfo.name)
        end
    end
    return variants
end

function Utility:Action(definition, variant)
    if not variant then return {} end
    local product = definition.conjured and Data.products[variant.spellID]
    if product then return {type="item", item="item:" .. product.itemID} end
    if variant.itemID then
        if IsWeaponItem(definition) then
            return { type = "macro", macrotext = "/use item:" .. variant.itemID .. "\n/use " .. definition.weaponSlot }
        end
        return { type = "item", item = "item:" .. variant.itemID }
    end
    if definition.friend or definition.shield and IsEarthShield(variant.spellID) then
        -- Leave the unit unset so native targeting and auto-self-cast settings apply.
        return { type = "spell", spell = variant.spellID }
    end
    return { type = "spell", spell = variant.spellID, unit = definition.shield and "player" or definition.target }
end

function Utility:OwnedStone(definition)
    local chosen
    for _, item in ipairs(definition.items) do
        if Count(item) and Count(item) > 0 and self.level and self.level >= Data.items[item].level then chosen = item end
    end
    return chosen
end

local function SaveSelection(entry, value)
    local config = YAB:GetDB().specialBars[entry.id]
    config.classToolSelected = config.classToolSelected or {}
    if config.classToolSelected[entry.key] == value then return end
    config.classToolSelected[entry.key] = value
    Tools:Invalidate()
    if YAB.ConfigSets then YAB.ConfigSets:SaveActiveSetting(entry.id, "classToolSelected", config.classToolSelected, "class-tool-selection", Utility) end
end

local function Selected(button, value)
    local entry = Utility.states[button]
    if not entry or not entry.byValue[value] then return end
    if entry.definition.shield then entry.right = Number(button:GetAttribute("spell2")) end
    SaveSelection(entry, value)
    YAB.BarManager:QueueSpecialRefresh(entry.id, "class-tool-selection")
end

local function ItemName(itemID)
    local info = itemID and Item.GetInfo(itemID)
    return info and Security.SafeString(info.name)
end

local function ItemReason(itemID)
    local count = Count(itemID)
    if count == nil then return Text("state_unknown"), "secondary" end
    if count == 0 then return Text("empty_item") end
    if Item.IsUsable and Security.SafeBoolean(Item.IsUsable(itemID)) == false then return Text("not_usable") end
end

local function SpellReason(spellID)
    local reagent = spellID and Data.reagents[spellID]
    if reagent then
        local count = Count(reagent.itemID)
        if count == nil then return Text("state_unknown"), "secondary" end
        if count < reagent.count then return Text("missing") end
    end
    local reason,tone=Tools:SpellUseReason(spellID)
    if reason then return reason,tone end
    local cooldown=spellID and Spell.GetCooldown and Spell.GetCooldown(spellID)
    local start=cooldown and Number(cooldown.startTime)
    local duration=cooldown and Number(cooldown.duration)
    local now=Now()
    if start and duration and now and start>0 and duration>1.5 and now<start+duration then return Text("cooldown") end
end

local function ConjureTargetLevel()
    return Unit.GetLevel and Unit.GetLevel("target")
end

local function IsConjurePlayerTarget()
    return Unit.IsPlayer("target") == true and Unit.IsFriend("target") == true
end

local function ConjureTargetVariant(entry, level)
    for index = #entry.variants, 1, -1 do
        local variant = entry.variants[index]
        if Data.products[variant.spellID].level <= level then return variant end
    end
end

local function PrepareTargetCraft(button, mouse, down)
    if down or mouse ~= "RightButton" or not IsControlKeyDown() or IsShiftKeyDown()
        or IsAltKeyDown() or YAB.Adapter:InCombat() then return end
    local entry = Utility.states[button]
    if not (entry and entry.enabled) then return end
    local level = IsConjurePlayerTarget() and ConjureTargetLevel()
    local variant = level and ConjureTargetVariant(entry, level)
    YAB.SecureFactory:SetSecureAttribute(button, "class-tool-target-spell", variant and variant.spellID or nil)
end

local function ConjureItemName(variant, fallback)
    local product = variant and Data.products[variant.spellID]
    return variant and variant.productName or ItemName(product and product.itemID) or Text(fallback)
end

function Utility:ConjureYield(spellID)
    local scaling = Data.conjureScaling[spellID]
    if not scaling or not self.level then return end
    local levels = math.max(0, math.min(self.level, scaling.maxLevel) - scaling.level)
    local amount = math.floor((scaling.baseCount or 2) + levels * (scaling.perLevel or 2))
    return math.min(amount, Data.conjureStackSize)
end

local function AddConjureTargetTooltip(tip, entry)
    local def, formatter = entry.definition, YUI.GUI2.Tooltip
    local level = ConjureTargetLevel()
    local name = Unit.GetCharacterName and Unit.GetCharacterName("target")
    local class = Unit.GetClassToken and Security.SafeString(Unit.GetClassToken("target"))
    local color = name and class and Unit.GetClassColor(class)
    if color then name = color:WrapTextInColorCode(name) end
    local targetText = name or formatter:ColorText("—", "secondary")
    if level then
        targetText = targetText .. " " .. formatter:ColorText(string.format(Text("conjure_level_value"), level), "subheading")
    else
        targetText = targetText .. " " .. formatter:ColorText(Text("conjure_level_unknown"), "secondary")
    end
    tip:AddLine(" ")
    tip:AddLine(string.format(Text("conjure_target"), targetText), 1, 1, 1, true)
    local suited = level and ConjureTargetVariant(entry, level)
    local action, tone
    if YAB.Adapter:InCombat() then
        action, tone = Text("conjure_target_combat"), "secondary"
    elseif not suited then
        action, tone = Text(level and "conjure_target_no_rank" or "conjure_target_level_unknown"), "secondary"
    else
        local suitedProduct = Data.products[suited.spellID]
        local itemText = ConjureItemName(suited, def.productText)
        local amount = Utility:ConjureYield(suited.spellID)
        if amount then itemText = itemText .. " ×" .. amount end
        action = string.format(Text("conjure_target_craft"), formatter:IconText(itemText, Item.GetIcon(suitedProduct.itemID)))
    end
    tip:AddLine(formatter:FormatAction({button="RightButton", modifiers={"CTRL"}, text=action,
        keyTone="body", textTone=tone or "heading"}), 1, 1, 1, true)
end

function Utility:ItemEffect(itemID, full)
    local saved = self.itemEffects[itemID]
    if saved then return saved end
    local itemSpell = Data.items[itemID] and Data.items[itemID].useSpellID
    local raw
    if itemSpell and Spell.GetPublicTooltipDescription then
        raw = Spell.GetPublicTooltipDescription(itemSpell)
    end
    local prefix = Security.SafeString(_G.ITEM_SPELL_TRIGGER_ONUSE)
    local format = (itemSpell or full) and Tools.TooltipEffectText or Tools.CompactItemEffectText
    local text = format(Tools, raw, prefix)
    if not text and Item.GetPublicUseText then
        text = format(Tools, Item.GetPublicUseText(itemID), prefix)
    end
    if not text and Spell.GetPublicDescription then
        local useSpell = itemSpell
        if not useSpell and Item.GetSpell then
            local ok, _, id = pcall(Item.GetSpell, itemID)
            useSpell = ok and Number(id)
        end
        if useSpell then text = format(Tools, Spell.GetPublicDescription(useSpell), prefix) end
    end
    self.itemEffects[itemID] = text
    return text
end

function Utility:ShowConjureTooltip(tip, button, entry, variant)
    local def, formatter = entry.definition, YUI.GUI2.Tooltip
    local product = variant and Data.products[variant.spellID]
    local icon = product and Item.GetIcon(product.itemID)
    Tools:TooltipIconTitle(tip, ConjureItemName(variant, def.productText), icon)
    if product then
        if def.targetCraft then
            tip:AddLine(string.format(Text("conjure_level"), formatter:ColorText(
                string.format(Text("conjure_level_value"), product.level), "subheading")), 1, 1, 1, true)
            local amount = self:ConjureYield(variant.spellID)
            tip:AddLine(string.format(Text("conjure_yield"), formatter:ColorText(
                amount and string.format(Text("conjure_yield_" .. def.targetCraft), amount) or "—", amount and "heading" or "secondary")), 1, 1, 1, true)
            tip:AddLine(" ")
        end
        Tools:TooltipEffect(tip, self:ItemEffect(product.itemID))
    end
    if entry.choice then
        Tools:TooltipAction(tip, "LeftButton", Text("conjure_choose_rank"))
        tip:Show()
        return
    end
    local itemReason, itemTone = ItemReason(product and product.itemID)
    local spellReason, spellTone = SpellReason(variant and variant.spellID)
    Tools:TooltipAction(tip, "LeftButton", Text(def.consumeText), nil, itemReason, nil, itemTone)
    Tools:TooltipAction(tip, "RightButton", Text("conjure_create"), nil, spellReason, nil, spellTone)
    if def.targetCraft then
        Tools:TooltipAction(tip, "RightButton", Text("rank_menu"), nil, nil, {"SHIFT"})
        if IsConjurePlayerTarget() then AddConjureTargetTooltip(tip, entry) end
    end
    Tools:TooltipSettings(tip, button)
    tip:Show()
end

local function TooltipReagent(tip, reagent)
    if not reagent then return end
    local formatter, count = YUI.GUI2.Tooltip, Count(reagent.itemID)
    local missing = count ~= nil and count < reagent.count
    local tone = missing and "requirement" or count == nil and "secondary" or "heading"
    tip:AddLine(formatter:IconText(string.format(Text("action_row"), ItemName(reagent.itemID) or Text("reagent"),
        formatter:ColorText(CountText(count), tone)), Item.GetIcon(reagent.itemID)), 1, 1, 1, true)
end

local function ShowTravelTooltip(tip, button, entry, variant)
    local spellID = variant and variant.spellID
    Tools:TooltipIconTitle(tip, variant and variant.name or Text(entry.key), variant and variant.texture)
    Tools:TooltipSpellEffect(tip, spellID, true)
    local reagent = spellID and Data.reagents[spellID]
    local reason, tone = SpellReason(spellID)
    Tools:TooltipAction(tip, "LeftButton", Text("cast"), nil, reason, nil, tone)
    if not entry.choice then
        Tools:TooltipAction(tip, "RightButton", Text("choose_execute"))
        Tools:TooltipBinding(tip, button)
    end
    if reagent then
        tip:AddLine(" ")
        TooltipReagent(tip, reagent)
    end
    if not entry.choice then Tools:TooltipSettings(tip) end
    tip:Show()
end

local function StatusLine(tip, started, text, tone, icon)
    if not started then tip:AddLine(" ") end
    local r, g, b = YUI.GUI2:GetColor("color.tooltip." .. (tone or "body"))
    tip:AddLine(YUI.GUI2.Tooltip:IconText(text, icon), r, g, b, true)
    return true
end

local function WithShardCost(text, reagent)
    if reagent and reagent.itemID == 6265 then return string.format(Text("shard_cost"), text, reagent.count) end
    return text
end

local function TooltipStock(tip, started, itemID)
    local count = Count(itemID)
    local tone = count == nil and "secondary" or count == 0 and "requirement" or "heading"
    return StatusLine(tip, started, string.format(Text("inventory_count"),
        YUI.GUI2.Tooltip:ColorText(CountText(count), tone)), nil, Item.GetIcon(itemID))
end

local function TooltipActiveEffect(tip, entry, variant, weapon)
    local now, definition = Now(), entry.definition
    local started
    if IsWeaponItem(definition) and weapon then
        local actual, _, effect = Utility:WeaponItemDisplay(entry)
        local id = actual and actual.itemID
        local name = id and ItemName(id)
        if name and (not now or not effect.expiration or effect.expiration > now) then
            started = StatusLine(tip, started, string.format(Text("active_effect"), name),
                effect.unknown and "secondary" or nil, Item.GetIcon(id))
        end
        if effect and effect.unknown then started = StatusLine(tip, started, Text("state_unknown"), "secondary") end
        return started
    end
    if definition.binding then
        local own, peer = Utility:SoulstoneStatus(entry)
        if own or peer then
            local label = Text("soul_bound_self")
            if not own then
                local color = peer.class and Unit.GetClassColor(peer.class)
                local name = color and color.WrapTextInColorCode and color:WrapTextInColorCode(peer.name) or peer.name
                label = string.format(Text("soul_bound_target"), name)
            end
            local unknown = peer and peer.unknown
            started = StatusLine(tip, started, label, unknown and "secondary" or nil)
            if unknown then started = StatusLine(tip, started, Text("state_unknown"), "secondary") end
        end
        return started
    end
    local active
    if TracksAuraIdentity(definition) then
        active = Utility:ActiveAura(entry, now)
    elseif definition.aura then
        local aura = Utility.auras and Utility.auras[entry.key]
        if AuraIsActive(aura, now) then active = variant end
    elseif weapon and weapon.enchantID and (not now or not weapon.expiration or weapon.expiration > now) then
        active = entry.activeVariant
    end
    if active and active.name then
        started = StatusLine(tip, started, string.format(Text("active_effect"), active.name),
            weapon and weapon.imbueUnknown and "secondary" or nil, active.texture)
    end
    if weapon and weapon.imbueUnknown then started = StatusLine(tip, started, Text("state_unknown"), "secondary") end
    return started
end

function Utility:ShowTooltip(button)
    local entry = self.states[button]
    if not entry then return end
    if entry.definition.team and YAB.PaladinBlessings then return YAB.PaladinBlessings:ShowTooltip(button) end
    if not YAB.SecureFactory:ShouldShowTooltip(button) then
        if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        return
    end
    local variant = entry.choice or entry.byValue[entry.button:GetAttribute("class-tool-selected")] or entry.selected
    local tip, definition = GameTooltip, entry.definition
    local weaponItem = IsWeaponItem(definition)
    tip:SetOwner(button, "ANCHOR_RIGHT")
    if definition.conjured then return self:ShowConjureTooltip(tip, button, entry, variant) end
    if definition.travel then return ShowTravelTooltip(tip, button, entry, variant) end
    local spellID, itemID = variant and variant.spellID, variant and variant.itemID
    Tools:TooltipIconTitle(tip, ItemName(itemID) or Name(spellID) or Text(entry.key),
        itemID and Item.GetIcon(itemID) or Texture(spellID))
    if itemID then
        Tools:TooltipEffect(tip, self:ItemEffect(itemID, definition.stone))
    elseif spellID then
        Tools:TooltipSpellEffect(tip, spellID)
    end
    if not entry.choice then
        local reagent = spellID and Data.reagents[spellID]
        local rightReagent = entry.right and Data.reagents[entry.right]
        local left = variant and (ItemName(variant.itemID) or Name(variant.spellID)) or Text("cast_current")
        local leftIcon = variant and (variant.itemID and Item.GetIcon(variant.itemID) or Texture(variant.spellID))
        local right, rightIcon, leftReason, rightReason, leftTone, rightTone
        if definition.stone or weaponItem then
            left = Text(weaponItem and "apply" or "use") .. " " .. (ItemName(variant and variant.itemID) or Text(entry.key))
            if weaponItem and itemID then left = string.format(Text("weapon_action"), left, Text(definition.weaponSlot == 16 and "weapon_main" or "weapon_off")) end
            leftReason, leftTone = ItemReason(variant and variant.itemID)
            if not (variant and variant.itemID) then
                local unknown = self.itemKnowledge and self.itemKnowledge[definition] == false
                leftReason, leftTone = Text(unknown and "state_unknown" or "empty_item"), unknown and "secondary" or nil
            end
        else
            left = WithShardCost(left, reagent)
            leftReason, leftTone = SpellReason(spellID)
        end
        if definition.cancelAura then
            right, rightIcon = Text("cancel_buff"), variant and Texture(variant.spellID)
        elseif entry.right then
            right, rightIcon = WithShardCost(Name(entry.right) or Text("cast"), rightReagent), Texture(entry.right)
            rightReason, rightTone = SpellReason(entry.right)
        elseif definition.mode == "select" then right = Text("choose_destination")
        elseif definition.mode == "cast" and not definition.hoverMenu then
            right = Text(definition.selectOnRight and "blessing_menu" or weaponItem and "choose_apply" or "choose_execute")
        end
        local weapon = definition.weaponSlot and self.weapons and self.weapons[definition.weaponSlot]
        if weapon and weapon.canEnchant == false then leftReason, leftTone = Text("no_weapon"), nil end
        Tools:TooltipAction(tip, "LeftButton", left, leftIcon, leftReason, nil, leftTone)
        if right then Tools:TooltipAction(tip, "RightButton", right, rightIcon, rightReason, nil, rightTone) end
        local hoverChoices = definition.hoverMenu and (not definition.shield or #entry.variants > 2)
        local started = TooltipActiveEffect(tip, entry, variant, weapon)
        if hoverChoices then started = StatusLine(tip, started, Text("hover_choices")) end
        if definition.weaponSlot and not weaponItem then
            started = StatusLine(tip, started, Text(definition.weaponSlot == 16 and "mainhand_target" or "offhand_target"))
        end
        if definition.pet and Unit.Exists then
            local exists = Security.SafeBoolean(Unit.Exists("pet"))
            if exists == false then
                started = StatusLine(tip, started, Text("pet_absent"), "heading")
            elseif exists and Unit.Name then
                local petName = Security.SafeString(Unit.Name("pet"))
                if petName then started = StatusLine(tip, started, string.format(Text("active_pet"), petName)) end
            end
        end
        local actual = weaponItem and self:WeaponItemDisplay(entry)
        if actual and not definition.stone and variant and actual.itemID ~= itemID then
            started = StatusLine(tip, started, Text("poison_sync_pending"), "heading")
        end
        if itemID and weaponItem then TooltipStock(tip, started, itemID) end
        Tools:TooltipBinding(tip, button)
        if reagent or rightReagent then
            tip:AddLine(" ")
            TooltipReagent(tip, reagent or rightReagent)
            if reagent and rightReagent and rightReagent.itemID ~= reagent.itemID then TooltipReagent(tip, rightReagent) end
        end
        Tools:TooltipSettings(tip)
    elseif variant then
        if definition.mode == "select" then
            Tools:TooltipAction(tip, "LeftButton", Text("choose_destination"))
        elseif variant.itemID then
            local reason, tone = ItemReason(variant.itemID)
            local weapon = definition.weaponSlot and self.weapons and self.weapons[definition.weaponSlot]
            if weapon and weapon.canEnchant == false then reason, tone = Text("no_weapon"), nil end
            local action = Text(weaponItem and "apply" or "use") .. " " .. (ItemName(variant.itemID) or Text(entry.key))
            if weaponItem then action = string.format(Text("weapon_action"), action, Text(definition.weaponSlot == 16 and "weapon_main" or "weapon_off")) end
            Tools:TooltipAction(tip, "LeftButton", action, Item.GetIcon(variant.itemID), reason, nil, tone)
            if weaponItem then TooltipStock(tip, false, variant.itemID) end
        else
            local reason, tone = SpellReason(variant.spellID)
            local reagent = Data.reagents[variant.spellID]
            if reagent and reagent.itemID == 6265 then
                local action = WithShardCost(Name(spellID) or Text("cast_current"), reagent)
                Tools:TooltipAction(tip, "LeftButton", action, Texture(spellID), reason, nil, tone)
            else
                Tools:TooltipSpell(tip, "LeftButton", variant.spellID, reason, nil, tone)
            end
            if definition.selectOnRight then Tools:TooltipAction(tip, "RightButton", Text("set_primary")) end
            if reagent then tip:AddLine(" "); TooltipReagent(tip, reagent) end
        end
        if definition.mode == "select" or definition.weaponSlot and not weaponItem then tip:AddLine(" ") end
        if definition.mode == "select" then tip:AddLine(Text("select_only"), 1, 1, 1, true) end
        if definition.weaponSlot and not weaponItem then tip:AddLine(Text(definition.weaponSlot == 16 and "mainhand_target" or "offhand_target"), 1, 1, 1, true) end
    end
    tip:Show()
end

local function SetToolHovered(button, hovered)
    local entry = Utility.states[button]
    if not entry or entry.choice or not PreviewsLeftOnHover(entry.definition) or (entry.hovered == true) == hovered then return end
    entry.hovered = hovered or nil
    if entry.enabled and YAB.ClassBars.active[entry.id] and button:IsVisible() then
        local selected = entry.byValue[button:GetAttribute("class-tool-selected")] or entry.selected
        Utility:UpdateVisual(button, entry, selected)
    end
end

local function Enter(button)
    SetToolHovered(button, true)
    Utility:ShowTooltip(button)
end

local function Leave(button)
    SetToolHovered(button, false)
    GameTooltip:Hide()
end

local function ClearToolHover(button)
    Utility.states[button].hovered = nil
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end
local function CooldownDone(cooldown)
    local button = cooldown:GetParent()
    local entry = Utility.states[button]
    if entry and not entry.cooldownUpdating and YAB.ClassBars.active[entry.id] then
        if entry.definition.weaponSlot then Utility.inventoryDirty = true end
        if entry.definition.sharpening then YAB.ClassBars.configDirty[entry.id] = true end
        Utility.auraDirty = true
        YAB.BarManager:QueueSpecialRefresh(entry.id, "class-tool-duration")
    end
end

function Utility:PrepareVisual(button, entry, snapshot)
    if YAB.Adapter:InCombat() then return end
    YAB.Skins:ApplyButton(button, YAB.Skins:Normalize("default"), { size=snapshot.size, width=snapshot.size,
        height=snapshot.buttonHeight or snapshot.size, zoom=snapshot.iconZoom, snapshot=snapshot })
    YAB.BarManager.buttonConfigSnapshots[button] = snapshot
    local visual = YAB.Visuals.buttons[button]
    if visual and visual.cooldown and entry.cooldownHook ~= visual.cooldown then
        visual.cooldown:HookScript("OnCooldownDone", CooldownDone); entry.cooldownHook = visual.cooldown
    end
    if YUI.GUI2 and YUI.GUI2.CreateText and not entry.label then
        entry.label = YUI.GUI2:CreateText(visual and visual.classTextHost or button, "", "font.size.sm", "color.text.primary", "CENTER")
        -- Product levels and city captions retain their own colors across theme refreshes.
        entry.label.gui2ColorKey = nil
    end
    if entry.label then
        if visual and visual.classTextHost and entry.label:GetParent() ~= visual.classTextHost then
            entry.label:SetParent(visual.classTextHost)
        end
        local level = entry.choice and Data.products[entry.choice.spellID]
        entry.label:ClearAllPoints()
        if level then
            entry.label:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
            entry.label:SetTextColor(101 / 255, 217 / 255, 1, 1)
        else
            Tools:AnchorCaption(entry.label, button, snapshot)
            entry.label:SetTextColor(1, 1, 1, 1)
        end
        Label(entry, level and ("Lv" .. level.level) or "")
        Tools:StyleText(entry.label)
    end
    if entry.definition.travel and visual and visual.count then
        visual.count:ClearAllPoints()
        visual.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT",
            -2 + (Number(snapshot.countOffsetX) or 0), 1 + (Number(snapshot.countOffsetY) or 0))
    end
end

function Utility:ReleaseBuffTimer(entry)
    Tools:ReleaseAuraTimer(entry)
end

-- Only the public owner is retained after the native Aura subtree is bound.
function Utility:RefreshBuffTimerStyle(button)
    local entry = self.states[button]
    if not entry or not entry.timerWanted then return end
    if YAB.Adapter:InCombat() then
        YAB.ClassBars.pending, YAB.ClassBars.configDirty[entry.id] = true, true
        return
    end
    if not self.nativeTimersReady then return end
    local identity = TracksAuraIdentity(entry.definition) or entry.definition.binding
    if identity and not Unit.SetFilteredAuraDisplayIdentitySuppressed then return end
    local style = YAB.Visuals:CaptureStatusTimerStyle(button, entry.id == "paladinTools" or identity or entry.definition.auraIcon)
    if not style then return end
    Tools:SyncAuraTimer(entry,button,"class-" .. entry.id .. "-" .. entry.key,entry.timerSpellIDs,style)
end

function Utility:Configure(entry, record, config)
    local button, factory, definition = entry.button, YAB.SecureFactory, entry.definition
    local weaponItem = IsWeaponItem(definition)
    local saved = config.classToolSelected and config.classToolSelected[entry.key]
    entry.variants = definition.poison and not self.poisonLearned and {} or self:Variants(definition, saved)
    entry.byValue = {}
    for _, variant in ipairs(entry.variants) do entry.byValue[variant.value] = variant end
    if entry.id == "totems" and definition.weaponSlot then
        entry.byEnchant = {}
        for _, family in ipairs(definition.families) do
            for _, id in ipairs(family) do
                local enchant = Data.enchants[id]
                if enchant then
                    entry.byEnchant[enchant] = entry.byValue[id] or {value=id, spellID=id, name=Name(id), texture=Texture(id)}
                end
            end
        end
    end
    local selected = entry.byValue[saved]
    if not selected then selected = definition.ranks and entry.variants[#entry.variants] or entry.variants[1] end
    local available = #entry.variants > 0
    if definition.poison or definition.sharpening then
        local actual, weapon, effect = self:WeaponItemDisplay(entry)
        if definition.poison then
            available = self.poisonLearned == true
        else
            local active = actual and (not effect.expiration or (Now() or math.huge) < effect.expiration)
            available = weapon and weapon.canEnchant and (available or active)
        end
        if available and actual and effect.known and weapon.canEnchant == true then
            selected = actual
            entry.byValue[actual.value] = actual
            SaveSelection(entry, actual.value)
        end
    end
    if entry.id == "mageTools" and (entry.key == "water" or entry.key == "bread") then
        local highest = entry.variants[#entry.variants]
        if highest then
            if self.resetConjured or entry.highestKnown ~= highest.value then
                selected = highest
                SaveSelection(entry, highest.value)
                config.classToolSelected = config.classToolSelected or {}
                config.classToolSelected[entry.key] = highest.value
            end
            entry.highestKnown = highest.value
        end
    end
    if definition.stone then
        local item = self:OwnedStone(definition)
        local family = weaponItem and definition.families[1]
        entry.craft = family and self:Highest(family) or selected and selected.spellID
        selected = {value=item or 0,itemID=item,spellID=not item and entry.craft or nil,texture=item and Item.GetIcon(item) or Texture(entry.craft)}
        available = entry.craft ~= nil or not weaponItem and item ~= nil
    end
    entry.selected = selected
    local enabled = Tools:IsButtonEnabled(entry.id, entry.key, config)
    entry.enabled = enabled and available == true and not record.classBarEditing and not YAB.BarManager.bindPresentationActive
    entry.timerWanted = (definition.aura == true or definition.binding == true or definition.activeAura == true
        or definition.shield == true) and entry.enabled == true
    if entry.timerWanted then
        entry.timerSpellIDs = {}
        if definition.binding then
            for _, spell in ipairs(definition.boundAuras) do entry.timerSpellIDs[#entry.timerSpellIDs + 1] = spell end
        else
            for _, family in ipairs(definition.families or {}) do
                for _, spell in ipairs(family) do entry.timerSpellIDs[#entry.timerSpellIDs + 1] = spell end
                for _, spell in ipairs(definition.greater and definition.greater[family[1]] or {}) do entry.timerSpellIDs[#entry.timerSpellIDs + 1] = spell end
            end
            for _, spell in ipairs(definition.right or {}) do entry.timerSpellIDs[#entry.timerSpellIDs + 1] = spell end
        end
    end
    if not entry.timerWanted or not self.nativeTimersReady then self:ReleaseBuffTimer(entry) end
    for _, field in ipairs({"type","spell","item","macrotext","unit"}) do
        factory:SetSecureAttribute(button, field, nil)
        factory:SetSecureAttribute(button, field .. "1", nil)
        factory:SetSecureAttribute(button, field .. "2", nil)
    end
    local friendly = definition.friend == true or definition.shield == true
    factory:SetSecureAttribute(button, "checkselfcast", friendly or nil)
    factory:SetSecureAttribute(button, "checkfocuscast", friendly or nil)
    local action = self:Action(definition, selected)
    if definition.stone and not selected.itemID then action = {} end
    if definition.stone and weaponItem then
        local weapon = self.weapons and self.weapons[definition.weaponSlot]
        if not weapon or weapon.canEnchant ~= true then action = {} end
    end
    if not entry.enabled then action = {} end
    for field, value in pairs(action) do factory:SetSecureAttribute(button, field .. "1", value) end
    factory:SetSecureAttribute(button, "class-tool-selected", selected and selected.value)
    factory:SetSecureAttribute(button, "class-tool-interactive", entry.enabled)
    local shiftMenu = definition.conjured and definition.ranks == true
    factory:SetSecureAttribute(button, "class-tool-shift-menu", shiftMenu == true)
    factory:SetSecureAttribute(button, "class-tool-paired", definition.shield == true)
    for _, prefix in ipairs({"shift-","alt-shift-","ctrl-shift-","alt-ctrl-shift-"}) do
        factory:SetSecureAttribute(button, prefix .. "type2", shiftMenu and "none" or nil)
    end
    entry.right = definition.right and self:Highest(definition.right)
    if definition.stone then entry.right = entry.craft end
    if definition.conjured then entry.right = selected and selected.spellID end
    if definition.shield then
        local other = OtherShield(entry, selected)
        entry.right = other and other.spellID
    end
    if entry.right and entry.enabled then
        local rightAction = self:Action(definition.stone and {} or definition, {spellID=entry.right})
        if definition.conjured then rightAction = {type="spell", spell=entry.right} end
        for field, value in pairs(rightAction) do factory:SetSecureAttribute(button, field .. "2", value) end
    end
    if definition.cancelAura and entry.enabled and selected then
        factory:SetSecureAttribute(button,"type2","cancelaura")
        factory:SetSecureAttribute(button,"spell2",selected.name)
    end
    entry.panel:Hide()
    local count = definition.mode and (not definition.shield or #entry.variants > 2) and #entry.variants or 0
    for index = 1, math.max(count, #entry.choices) do
        local choice, variant = entry.choices[index], entry.variants[index]
        if index <= count then
            if not choice then
                choice = factory:CreateClassToolChoice(entry.panel, button, index); entry.choices[index] = choice
                choice:SetScript("OnEnter", Enter); choice:SetScript("OnLeave", Leave)
                self.states[choice] = { id=entry.id,key=entry.key,button=button,definition=definition,visual={} }
            end
            local state = self.states[choice]
            state.choice, state.byValue = variant, entry.byValue
            local chosenAction = self:Action(definition, variant)
            local rightAction
            if entry.enabled then
                if definition.conjured then rightAction = {type="spell", spell=variant.spellID}
                elseif definition.shield then rightAction = self:Action(definition, OtherShield(entry, variant)) end
            end
            for _, field in ipairs({"type","spell","item","macrotext","unit"}) do
                local value = entry.enabled and chosenAction[field]
                factory:SetSecureAttribute(choice, "selected-" .. field, value)
                factory:SetSecureAttribute(choice, field, definition.mode == "cast" and value or nil)
                factory:SetSecureAttribute(choice, "selected-right-" .. field, rightAction and rightAction[field])
            end
            factory:SetSecureAttribute(choice, "checkselfcast", friendly or nil)
            factory:SetSecureAttribute(choice, "checkfocuscast", friendly or nil)
            factory:SetSecureAttribute(choice, "class-tool-select-on-right", definition.selectOnRight == true)
            factory:SetSecureAttribute(choice, "class-tool-cast-only", weaponItem)
            factory:SetSecureAttribute(choice, "type2", nil)
            factory:SetSecureAttribute(choice, "macrotext2", nil)
            factory:SetSecureAttribute(choice, "class-tool-value", variant.value)
            choice:SetSize(record.configSnapshot.size, record.configSnapshot.buttonHeight or record.configSnapshot.size)
            self:PrepareVisual(choice, state, record.configSnapshot)
            choice:SetChecked(selected and variant.value == selected.value or false)
            choice:Show()
            record.classButtons[#record.classButtons + 1] = choice
        elseif choice then
            factory:SetSecureAttribute(choice, "type", nil); choice:Hide()
            YAB.Visuals:ReleaseButton(choice)
            YAB.BarManager.buttonConfigSnapshots[choice], YAB.BarManager.mouseoverRecords[choice] = nil, nil
        end
    end
    factory:SetSecureAttribute(button, "class-tool-choices", count)
    if definition.hoverMenu then
        factory:PrepareTotemOpener(button, entry.panel, record.totemController, definition.hoverMenu)
    end
    Tools:PrepareButton(button, entry.id, entry.key)
    self:RefreshBuffTimerStyle(button)
    if not entry.enabled then factory:SetSecureAttribute(button, "*type-Keybind", "none") end
    if enabled and (available or record.classBarEditing and entry.id ~= "aspects" and not definition.manaGemSlot) then
        button:Show(); record.buttons[#record.buttons + 1] = button
        record.classButtons[#record.classButtons + 1] = entry.panel
        return true
    end
    Tools:ReleaseButton(button); button:Hide()
end

local function IndexAura(names, entry, id, seen)
    local name = Name(id)
    if not name then
        if seen or entry.definition.binding then entry.auraNamesIncomplete = true end
        return
    end
    names[name] = seen and name or entry.key
    if seen and not seen[name] then
        seen[name] = true
        entry.auraEffects[#entry.auraEffects + 1] = {value=id, spellID=id, name=name, texture=Texture(id)}
    end
end

function Utility:Build(record, config, append)
    if YAB.Adapter:InCombat() then return end
    local bookDirty = self.bookDirty
    self:ReadBook()
    if record.id == "rogueTools" and (bookDirty or self.poisonLearned == nil) then self:ReadPoisonSkill() end
    if record.id == "rogueTools" or record.id == "warlockTools" then self:PrepareWeaponItems(record.id) end
    self:ReadInventory(record.id)
    if record.id == "mageTools" then
        local learned = {}
        for index = #Data.manaGemSpells, 1, -1 do
            local spell = Data.manaGemSpells[index]
            if self:Known(spell) then learned[#learned + 1] = spell end
        end
        self.manaGemSpells = learned
    end
    local wantsTimers
    for _, definition in pairs(Data.catalog[record.id] or {}) do
        if definition.aura or definition.binding or definition.activeAura or definition.shield then wantsTimers = true; break end
    end
    self.nativeTimersReady = wantsTimers and Unit.EnsureFilteredAuraDisplay
        and Unit.EnsureFilteredAuraDisplay() == true
        and type(YAB.Visuals.CaptureStatusTimerStyle) == "function"
        and type(YAB.Visuals.CreateStatusTimerBindings) == "function"
    local entries = self.records[record.id] or {}; self.records[record.id] = entries
    local bindingsChanged
    if not append then record.buttons, record.classButtons = {}, {} end
    for _, key in ipairs(Tools:GetButtonOrder(record.id, config)) do
        local definition = Data.catalog[record.id] and Data.catalog[record.id][key]
        if definition and (not definition.team or YAB.PaladinBlessings)
            and (not definition.manaGemSlot or entries[key]
                or self.manaGemSpells[definition.manaGemSlot] and Tools:IsButtonEnabled(record.id, key, config)) then
            local entry = entries[key]
            local dynamicBinding = definition.manaGemSlot or IsWeaponItem(definition)
            local wasShown = entry and entry.button:IsShown() or false
            if not entry then
                local button, panel = YAB.SecureFactory:CreateClassTool(record.holder, record.id, key, definition.hoverMenu, definition.targetCraft)
                entry = {id=record.id,key=key,button=button,panel=panel,choices={},visual={},definition=definition}
                if definition.aura then
                    entry.timerSpellIDs = {}
                    for _, family in ipairs(definition.families) do
                        for _, spellID in ipairs(family) do entry.timerSpellIDs[#entry.timerSpellIDs + 1] = spellID end
                    end
                    for _, spellID in ipairs(definition.right or {}) do
                        entry.timerSpellIDs[#entry.timerSpellIDs + 1] = spellID
                    end
                end
                entries[key], self.states[button] = entry, entry
                button.ClassToolSelected = Selected
                if definition.targetCraft then button:HookScript("PreClick", PrepareTargetCraft) end
                if definition.hoverMenu then
                    -- The template's OnEnter dispatches the protected flyout opener.
                    button:HookScript("OnEnter", Enter)
                    button:HookScript("OnLeave", Leave)
                else
                    button:SetScript("OnEnter", Enter)
                    button:SetScript("OnLeave", Leave)
                end
                if PreviewsLeftOnHover(definition) then button:HookScript("OnHide", ClearToolHover) end
            end
            entry.button:SetParent(record.holder); entry.panel:SetParent(record.holder)
            if definition.team and YAB.PaladinBlessings then YAB.PaladinBlessings:Build(entry, record, config)
            elseif not definition.team then self:Configure(entry, record, config) end
            if dynamicBinding and wasShown ~= entry.button:IsShown() then bindingsChanged = true end
            if definition.binding and YAB.SoulstoneBinding then YAB.SoulstoneBinding:Prepare(entry) end
        end
    end
    if bindingsChanged and record.classToolPrepared and YAB.Keybinds then
        YAB.Keybinds:ApplyRuntimeBindings(true)
    end
    record.classToolPrepared = true
    if (record.id=="paladinTools" or record.id=="warlockTools") and YAB.BarManager.SyncClassBarEvents then YAB.BarManager:SyncClassBarEvents() end
    if record.id == "mageTools" then self.resetConjured = nil end
    self.auraNames = {}
    for _, entry in pairs(entries) do
        entry.auraNamesIncomplete = nil
        if entry.definition.binding then
            for _, id in ipairs(entry.definition.boundAuras) do IndexAura(self.auraNames, entry, id) end
            entry.bindingIcon = Texture(20765)
        elseif (entry.id ~= "aspects" or entry.timerWanted)
            and (entry.definition.aura or entry.definition.shield or entry.definition.activeAura) then
            local seen
            if TracksAuraIdentity(entry.definition) then
                entry.auraEffects, seen = {}, {}
                for _, variant in ipairs(entry.variants) do
                    if variant.name and not seen[variant.name] then
                        seen[variant.name] = true
                        entry.auraEffects[#entry.auraEffects + 1] = variant
                    end
                end
            end
            for _, family in ipairs(entry.definition.families) do
                for _, id in ipairs(family) do IndexAura(self.auraNames, entry, id, seen) end
                for _, id in ipairs(entry.definition.greater and entry.definition.greater[family[1]] or {}) do
                    IndexAura(self.auraNames, entry, id, seen)
                end
            end
            for _, id in ipairs(entry.definition.right or {}) do IndexAura(self.auraNames, entry, id, seen) end
        end
    end
    self.auraDirty = true
end

function Utility:Layout(record)
    local snapshot = record.configSnapshot
    for _, entry in pairs(self.records[record.id] or {}) do
        if entry.definition.team and YAB.PaladinBlessings then YAB.PaladinBlessings:Layout(entry, record)
        elseif entry.button:IsShown() then
            self:PrepareVisual(entry.button, entry, snapshot)
            if entry.definition.columns then self:LayoutBlessings(entry, snapshot)
            else YAB.ClassBars:LayoutFlyout(entry.panel, entry.button, entry.choices, snapshot.size,
                snapshot.buttonHeight or snapshot.size, snapshot.spacing or 4, snapshot.flyoutDirection, true) end
            local seen = {}
            for _, button in ipairs(record.classButtons) do seen[button] = true end
            if not seen[entry.panel] then record.classButtons[#record.classButtons + 1] = entry.panel end
            for _, button in ipairs(entry.choices) do
                if button:IsShown() and not seen[button] then record.classButtons[#record.classButtons + 1] = button end
            end
        end
    end
end

function Utility:LayoutBlessings(entry, snapshot)
    if YAB.Adapter:InCombat() then return end
    local size, height, gap = snapshot.size, snapshot.buttonHeight or snapshot.size, snapshot.spacing or 4
    local rows, positions = 0, {}
    for _, variant in ipairs(entry.variants) do
        if not positions[variant.family] then rows=rows+1;positions[variant.family]=rows end
    end
    entry.panel:SetSize(size*2+gap,rows*(height+gap)-gap)
    entry.panel:ClearAllPoints()
    local direction=snapshot.flyoutDirection
    if direction=="down" then entry.panel:SetPoint("TOPLEFT",entry.button,"BOTTOMLEFT",0,-gap)
    elseif direction=="left" then entry.panel:SetPoint("BOTTOMRIGHT",entry.button,"BOTTOMLEFT",-gap,0)
    elseif direction=="right" then entry.panel:SetPoint("BOTTOMLEFT",entry.button,"BOTTOMRIGHT",gap,0)
    else entry.panel:SetPoint("BOTTOMLEFT",entry.button,"TOPLEFT",0,gap) end
    for index,variant in ipairs(entry.variants) do
        local column=entry.definition.greater[variant.family]
        local greater=false;for _,spell in ipairs(column or {}) do if spell==variant.spellID then greater=true;break end end
        local button=entry.choices[index];button:ClearAllPoints();button:SetPoint("TOPLEFT",entry.panel,"TOPLEFT",greater and size+gap or 0,-(positions[variant.family]-1)*(height+gap))
    end
end

function Utility:ResourceReady(spellID)
    local reagent = Data.reagents[spellID]
    if not reagent then return true end
    local count = Count(reagent.itemID)
    return count and count >= reagent.count or false
end

local function ApplyAuraClock(state, aura)
    local clock = Unit.GetAuraDurationObject and Unit.GetAuraDurationObject("player", aura.auraInstanceID)
    if clock then
        state.cooldownDurationObject = clock
        state.cooldownEnable, state.cooldownIsStatus = true, true
    elseif aura.duration and aura.expirationTime then
        state.cooldownStart, state.cooldownDuration = aura.expirationTime - aura.duration, aura.duration
        state.cooldownEnable, state.cooldownIsStatus = aura.duration > 0, true
    end
end

function Utility:ActiveAura(entry, now)
    local confirmed = self.auras ~= nil and not entry.auraNamesIncomplete
    local active, observed
    for _, variant in ipairs(entry.auraEffects or entry.variants) do
        local name = variant.name
        if not name or self.auraUnavailable and self.auraUnavailable[name] then
            confirmed = false
        else
            local aura = self.auras and self.auras[name]
            if AuraIsActive(aura, now) then
                if active and entry.auraDisplay then return nil, nil, false end
                if not active then active, observed = variant, aura end
            end
        end
    end
    return active, observed, confirmed
end

function Utility:ApplyActiveEffect(entry, selected, state, weapon)
    local now = Now()
    local definition = entry.definition
    local active, aura, confirmed
    if TracksAuraIdentity(definition) then
        active, aura, confirmed = self:ActiveAura(entry, now)
    elseif weapon then
        if weapon.enchantID and (not now or not weapon.expiration or weapon.expiration > now) then
            active = entry.byEnchant[weapon.enchantID]
        end
        confirmed = weapon.imbueAbsent
    end
    entry.activeVariant = active
    local different = active and (not selected
        or active.value ~= selected.value and (not active.name or active.name ~= selected.name))
    local preview = PreviewsLeftOnHover(definition) and not (definition.shield and entry.right)
    local showActive = entry.enabled ~= false and (not entry.hovered or not preview or active and not different
        and (not entry.auraDisplay or confirmed))
    local showNative = showActive and entry.auraDisplay ~= nil
    if entry.auraDisplay then Unit.SetFilteredAuraDisplayIdentitySuppressed(entry.auraDisplay, not showNative) end
    -- The native filter can draw a private aura independently of this action.
    state.auraIconOverlay = showNative and active ~= nil
    local icon = active and (aura and Number(aura.icon) or active.texture)
    state.checked = active ~= nil and showActive and (state.auraIconOverlay or icon ~= nil) or false
    if preview then state.countText = different and "•" or "" end
    local wantsSelfShield = selected and not IsEarthShield(selected.spellID)
    state.missingBuff = confirmed and active == nil and (weapon and weapon.canEnchant == true
        or definition.shield and wantsSelfShield or definition.aura and definition.warnMissing ~= false) or false
    if not (state.auraIconOverlay or showActive and icon) then return end
    state.texture = icon or state.texture
    state.usable, state.noMana = true, false
    state.cooldownStart, state.cooldownDuration, state.cooldownEnable = 0, 0, false
    state.cooldownIsStatus = true
    if not state.auraIconOverlay then
        if aura then ApplyAuraClock(state, aura)
        elseif weapon and weapon.expiration and weapon.duration and weapon.duration > 0 then
            state.cooldownDuration = weapon.duration
            state.cooldownStart = weapon.expiration - state.cooldownDuration
            state.cooldownEnable = true
        end
    end
end

function Utility:ApplySoulstoneStatus(entry, state)
    local own, peer = self:SoulstoneStatus(entry)
    local showActive = entry.enabled ~= false and not entry.hovered
    local showNative = entry.auraDisplay ~= nil and showActive and not peer
    if entry.auraDisplay then Unit.SetFilteredAuraDisplayIdentitySuppressed(entry.auraDisplay, not showNative) end
    state.auraIconOverlay = showNative and own ~= nil
    if not (showActive and (own or peer)) then return end

    if own or peer then state.texture = own and Number(own.icon) or entry.bindingIcon or state.texture end
    state.checked, state.usable, state.noMana = own ~= nil or peer ~= nil, true, false
    state.countText = ""
    state.cooldownStart, state.cooldownDuration, state.cooldownEnable = 0, 0, false
    state.cooldownIsStatus = true
    if peer then
        state.cooldownStart, state.cooldownDuration = peer.expirationTime - peer.duration, peer.duration
        state.cooldownEnable = true
    elseif own and not showNative then
        ApplyAuraClock(state, own)
    end
end

function Utility:UpdateVisual(button, entry, variant, choice)
    local definition, state = entry.definition, entry.visual
    local weaponItem = IsWeaponItem(definition)
    local craftedWeaponStone = weaponItem and definition.stone and not choice
    local weapon = definition.weaponSlot and self.weapons and self.weapons[definition.weaponSlot]
    local preparedItem = craftedWeaponStone and variant and variant.itemID
    local preparedCount = Count(preparedItem)
    local stoneUsable = (preparedCount or 0) > 0 and weapon and weapon.canEnchant == true
    local weaponEffect
    if weaponItem and not choice then
        local actual, _, effect = self:WeaponItemDisplay(entry, variant)
        local preview = entry.hovered and variant and actual and variant.value ~= actual.value
        if not preview then variant = actual end
        -- An empty stone preview keeps the active enchant clock.
        if not preview or craftedWeaponStone and not stoneUsable then weaponEffect = effect end
    end
    state.hasAction, state.texture = true, variant and variant.texture
        or definition.previewItem and Item.GetIcon(definition.previewItem)
        or Texture(Data.preview[entry.id][entry.key])
    state.countText, state.checked, state.missingBuff = "", false, false
    state.auraIconOverlay = not choice and entry.auraDisplay ~= nil
        and entry.timerStyle ~= nil and entry.timerStyle.iconLevel ~= nil
    state.cooldownStart, state.cooldownDuration, state.cooldownEnable, state.cooldownDurationObject = 0, 0, false, nil
    state.cooldownIsStatus = false
    state.usable, state.noMana = variant ~= nil and not variant.unavailable, false
    if variant then
        local product, reagent = Data.products[variant.spellID], Data.reagents[variant.spellID]
        if not choice then
            if product then state.countText = CountText(Count(product.itemID))
            elseif variant.itemID then state.countText = CountText(Count(variant.itemID))
            elseif definition.counter then state.countText = CountText(Count(definition.counter))
            elseif definition.travel and reagent then state.countText = CountText(Count(reagent.itemID)) end
        elseif variant.itemID then state.countText = CountText(Count(variant.itemID)) end
        if definition.hideCount then state.countText = "" end
        local useItem = variant.itemID or not choice and definition.conjured and product and product.itemID
        if craftedWeaponStone then useItem = preparedItem end
        if useItem then
            if not craftedWeaponStone then state.usable = (Count(useItem) or 0) > 0 end
            if definition.conjured and Item.IsUsable then state.usable = state.usable and Security.SafeBoolean(Item.IsUsable(useItem)) ~= false end
            local cooldown = Item.GetCooldown and Item.GetCooldown(useItem)
            state.cooldownStart, state.cooldownDuration = cooldown and Number(cooldown.startTime) or 0, cooldown and Number(cooldown.duration) or 0
            state.cooldownEnable = cooldown and Security.SafeBoolean(cooldown.isEnabled) == true or false
        elseif not craftedWeaponStone then
            state.usable = state.usable and self:ResourceReady(variant.spellID)
            if variant.spellID and Spell.GetUsableState then
                local usable, noMana = Spell.GetUsableState(variant.spellID)
                state.usable = state.usable and Security.SafeBoolean(usable) ~= false
                state.noMana = Security.SafeBoolean(noMana) == true
            end
            local cooldown = variant.spellID and Spell.GetCooldown and Spell.GetCooldown(variant.spellID)
            state.cooldownStart, state.cooldownDuration = cooldown and cooldown.startTime or 0, cooldown and cooldown.duration or 0
            state.cooldownEnable = cooldown and Security.SafeBoolean(cooldown.isEnabled) == true or false
        end
        if entry.label and not (choice and product) then
            local city = definition.travel and Data.cityKeys[variant.spellID]
            Label(entry, city and Text("city_" .. city) or "")
        end
    end
    if craftedWeaponStone then
        state.usable = stoneUsable == true
        state.countText = preparedItem and CountText(preparedCount)
            or (self.itemKnowledge and self.itemKnowledge[definition] == false and "—" or "0")
    elseif (definition.stone or weaponItem) and not choice and not (variant and variant.itemID) then
        state.usable, state.noMana = false, false
        state.countText = self.itemKnowledge and self.itemKnowledge[definition] == false and "—" or "0"
        state.cooldownStart, state.cooldownDuration, state.cooldownEnable = 0, 0, false
    end
    if weapon then
        state.usable = state.usable and weapon.canEnchant == true
    end
    if weaponEffect and (not definition.stone or weaponEffect.itemID) then
        local now, expiration = Now(), weaponEffect.expiration
        local active = weaponEffect.itemID ~= nil and (not expiration or now and expiration > now)
        state.checked = active and not weaponEffect.unknown or false
        state.missingBuff = not definition.stone and weapon.canEnchant == true and weaponEffect.known and weaponEffect.itemID == nil
        if active and craftedWeaponStone and not entry.hovered then state.usable = true end
        if active or not definition.stone then state.cooldownStart, state.cooldownDuration, state.cooldownEnable = 0, 0, false end
        if active and expiration and now then
            state.cooldownStart = expiration - weaponEffect.duration
            state.cooldownDuration = weaponEffect.duration
            state.cooldownEnable, state.cooldownIsStatus = true, true
        end
    end
    local activeEffect = not choice and (definition.hoverMenu or TracksAuraIdentity(definition))
    if activeEffect then
        self:ApplyActiveEffect(entry, variant, state, weapon)
    elseif not choice and definition.aura then
        local aura = self.auras and self.auras[entry.key]
        if self.auras and not (self.auraUnavailable and self.auraUnavailable[entry.key]) then
            state.checked = aura ~= nil
            state.missingBuff = aura == nil and definition.warnMissing ~= false
            if aura and not entry.auraDisplay then ApplyAuraClock(state, aura) end
        end
    end
    if not choice and definition.binding then
        self:ApplySoulstoneStatus(entry, state)
    elseif entry.auraDisplay and not activeEffect then
        state.cooldownStart, state.cooldownDuration, state.cooldownDurationObject = 0, 0, nil
        state.cooldownEnable, state.cooldownIsStatus = false, true
    end
    if not choice and definition.pet and Unit.Exists then
        state.missingBuff = Security.SafeBoolean(Unit.Exists("pet")) == false
    end
    if choice then state.checked = entry.button:GetAttribute("class-tool-selected") == variant.value end
    -- The resource quantity and city label retain priority at the small icon size.
    state.hotkeyText = not choice and definition.travel and state.countText ~= "" and "" or nil
    entry.cooldownUpdating = true
    YAB.Visuals:UpdateButton(button, state, "full")
    state.cooldownDurationObject = nil
    entry.cooldownUpdating = nil
end

function Utility:Refresh(record)
    if not Data.catalog[record.id] then return end
    self:ReadInventory(record.id)
    if record.id=="warlockTools" and YAB.SoulstoneBinding then YAB.SoulstoneBinding:Refresh() end
    if self.auraDirty then
        self.auras, self.auraUnavailable = nil, nil
        if Unit.ReadHelpfulTimersByName and (record.id ~= "aspects" or self.auraNames and next(self.auraNames)) then
            self.auras, self.auraUnavailable = Unit.ReadHelpfulTimersByName("player", self.auraNames or {})
        end
        self.auraDirty = nil
    end
    for _, entry in pairs(self.records[record.id] or {}) do
        if entry.definition.team and YAB.PaladinBlessings then YAB.PaladinBlessings:Refresh(entry)
        elseif entry.button:IsShown() then
            local variant = entry.byValue[entry.button:GetAttribute("class-tool-selected")] or entry.selected
            if entry.definition.poison or entry.definition.sharpening then
                local actual, weapon, effect = self:WeaponItemDisplay(entry)
                if actual and effect.known and weapon.canEnchant == true and (not variant or actual.value ~= variant.value)
                    and not YAB.ClassBars.configDirty[entry.id] then
                    YAB.ClassBars.configDirty[entry.id] = true
                    if YAB.Adapter:InCombat() then YAB.ClassBars.pending = true
                    else YAB.BarManager:QueueSpecialRefresh(entry.id, "weapon-item-confirmed") end
                end
            end
            self:UpdateVisual(entry.button, entry, variant)
            for _, choice in ipairs(entry.choices) do
                local state = self.states[choice]
                if choice:IsShown() and state and state.choice then self:UpdateVisual(choice, state, state.choice, true) end
            end
            if GameTooltip:IsOwned(entry.button) then self:ShowTooltip(entry.button) end
        end
    end
end

local CONJURE_KEYS = { "water", "bread" }
function Utility:RefreshConjureTargetTooltip()
    local tip = GameTooltip
    for _, key in ipairs(CONJURE_KEYS) do
        local entry = self.records.mageTools and self.records.mageTools[key]
        if entry and tip:IsOwned(entry.button) then
            self:ShowTooltip(entry.button)
            return
        end
    end
end

function Utility:OnEvent(event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local initialLogin, reloadingUi = ...
        if Security.SafeBoolean(initialLogin) == true or Security.SafeBoolean(reloadingUi) == true then
            self.resetConjured = true
        end
    end
    local active=YAB.ClassBars.active
    local hasUtility=active.paladinBlessings
    for id in pairs(active) do if Data.catalog[id] then hasUtility=true;break end end
    if not hasUtility then return end
    if event == "PLAYER_LEVEL_UP" or event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD"
        or event == "ADDON_RESTRICTION_STATE_CHANGED" then
        self.itemEffects = {}
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID = Number((...))
        if itemID then self.itemEffects[itemID] = nil end
    end
    if event == "UNIT_INVENTORY_CHANGED" and Security.SafeString((...)) ~= "player" then return end
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        self.auraDirty, self.inventoryDirty = true, true
        return
    end
    if active.totems then
        local slot = Data.catalog.totems.imbue.weaponSlot
        local weapon = self.weapons and self.weapons[slot]
        local changedSlot = event == "PLAYER_EQUIPMENT_CHANGED" and Number((...))
        if weapon and (event == "WEAPON_ENCHANT_CHANGED" or event == "PLAYER_ENTERING_WORLD"
            or event == "PLAYER_EQUIPMENT_CHANGED" and (not changedSlot or changedSlot == slot)) then
            weapon.imbueReset = true
        end
        if event == "WEAPON_ENCHANT_CHANGED" or event == "PLAYER_REGEN_ENABLED" then
            self.inventoryDirty = true
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" and Security.SafeString((...)) == "player"
            and Data.enchants[Number(select(3, ...))] then
            self.inventoryDirty = true
            YAB.BarManager:QueueSpecialRefresh("totems", event)
        end
    end
    local itemWeapons = active.rogueTools or active.warlockTools
    local enchantChanged = event == "WEAPON_ENCHANT_CHANGED" or event == "PLAYER_REGEN_ENABLED"
    if itemWeapons and enchantChanged then self.inventoryDirty = true end
    if itemWeapons and event == "PLAYER_EQUIPMENT_CHANGED" and self.weapons then
        local slot = Number((...))
        for index = 16, 17 do
            if not slot or slot == index then local weapon = self.weapons[index]; if weapon then weapon.itemReset = true end end
        end
    end
    local bookChanged = event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD"
        or active.rogueTools and event == "SKILL_LINES_CHANGED"
    local weaponChanged = event == "UNIT_INVENTORY_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED"
    if bookChanged then self.bookDirty = true end
    if event == "UNIT_AURA" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then self.auraDirty = true end
    if event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED" or event == "PLAYER_LEVEL_UP"
        or weaponChanged or active.rogueTools and enchantChanged or bookChanged then
        self.inventoryDirty = true
        for id in pairs(active) do
            -- Team blessings consume reagent counts during visual refresh and own their roster invalidation.
            if id ~= "paladinBlessings" and id ~= "aspects" and (id ~= "totems" or not weaponChanged) then
                YAB.ClassBars.configDirty[id] = true
            end
        end
    end
end

function Utility:Stop(id)
    self.itemEffects = {}
    if id=="warlockTools" and YAB.SoulstoneBinding then YAB.SoulstoneBinding:Stop() end
    for _, entry in pairs(self.records[id] or {}) do
        if entry.definition.team and YAB.PaladinBlessings then YAB.PaladinBlessings:Stop(entry) end
        self:ReleaseBuffTimer(entry)
        entry.timerWanted = nil
        entry.panel:Hide()
        YAB.BarManager.mouseoverRecords[entry.panel] = nil
        for _, button in ipairs(entry.choices) do
            YAB.SecureFactory:SetSecureAttribute(button, "type", nil); button:Hide(); YAB.Visuals:ReleaseButton(button)
            YAB.BarManager.buttonConfigSnapshots[button], YAB.BarManager.mouseoverRecords[button] = nil, nil
        end
        YAB.SecureFactory:SetSecureAttribute(entry.button, "type1", nil)
        YAB.SecureFactory:SetSecureAttribute(entry.button, "type2", nil)
        if entry.definition.targetCraft then
            YAB.SecureFactory:SetSecureAttribute(entry.button, "class-tool-target-spell", nil)
            YAB.SecureFactory:SetSecureAttribute(entry.button, "ctrl-type2", "none")
            YAB.SecureFactory:SetSecureAttribute(entry.button, "ctrl-spell2", nil)
        end
        YAB.SecureFactory:SetSecureAttribute(entry.button, "class-tool-interactive", false)
        Tools:ReleaseButton(entry.button); entry.button:Hide(); YAB.Visuals:ReleaseButton(entry.button)
        YAB.BarManager.buttonConfigSnapshots[entry.button], YAB.BarManager.mouseoverRecords[entry.button] = nil, nil
        if GameTooltip:IsOwned(entry.button) then GameTooltip:Hide() end
    end
    self.inventoryDirty, self.bookDirty, self.auraDirty = true, true, true
    if id == "rogueTools" or id == "warlockTools" or id == "totems" then self.weapons = nil end
    if id == "rogueTools" or id == "warlockTools" then self.weaponVariants, self.poisonLearned = nil, nil end
end

function Utility:GetPreviewKeys(id, config)
    local result = {}
    for _, key in ipairs(Tools:GetButtonOrder(id, config)) do
        local gemSlot = id == "mageTools" and Tools.manaGemSlot[key]
        if Tools:IsButtonEnabled(id, key, config)
            and (not gemSlot or not self.manaGemSpells or self.manaGemSpells[gemSlot])
            and (id ~= "paladinBlessings" or key=="manage" or config.teamBlessings and config.teamBlessings[key])
            and (id ~= "aspects" or key ~= "aspect7" and key ~= "aspect8") then
            result[#result + 1] = key
        end
    end
    return result
end
function Utility:GetPreviewButtonCount(id, config)
    if id == "aspects" or id == "totems" then
        local record = YAB.BarManager and YAB.BarManager.bars[id]
        if record and record.classToolPrepared then return #Tools:GetLayoutButtons(record) end
    end
    return #self:GetPreviewKeys(id, config)
end
function Utility:GetSampleSpellID(id, position, config)
    local key = self:GetPreviewKeys(id, config)[position]
    if id == "paladinBlessings" then return key~="manage" and config.teamBlessings and config.teamBlessings[key] or nil,key end
    local gemSlot = id == "mageTools" and key and Tools.manaGemSlot[key]
    if gemSlot and self.manaGemSpells then return self.manaGemSpells[gemSlot], key end
    return Data.preview[id] and Data.preview[id][key], key
end

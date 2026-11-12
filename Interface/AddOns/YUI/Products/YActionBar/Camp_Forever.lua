local YUI = _G.YUI
local YAB = YUI and YUI.YActionBar
if not (YAB and YAB.Client and YAB.Client.questItems == true) then return end

-- Forever 1.60.1.70862. ItemSparse supplies profession requirements; the
-- runtime reads quantities, cooldowns and auras instead of simulating rewards.
local Camp = { pool = {}, entries = setmetatable({}, { __mode = "k" }), observed = {},
    facilities = {}, effects = {}, passes = 0, auraDirty = true, inventoryDirty = true }
YAB.Camp = Camp
local Item, Unit, Profession = YUI.API.Item, YUI.API.Unit, YUI.API.Profession
local Security = YUI.API.Security
local TOY, SLEEPING_BAG, SLEEPING_BENEFIT = 288185, 211527, 429959
local TOY_FACILITY = { id = TOY }
local NEAR, REST, REST_ALT, BENEFIT, FATIGUE = 1283391, 1229739, 1289723, 1229741, 1229451
local FIRE_ICON, UNKNOWN_ICON = 135805, "Interface\\Icons\\INV_Misc_QuestionMark"
local FACILITIES_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local ARROWS = { up = { "▲", "▼" }, down = { "▼", "▲" }, left = { "◀", "▶" }, right = { "▶", "◀" } }
local CATALOG = {
    { id = 279967, skill = 356, rank = 20, spell = 1229745, effect = 1230098 },
    { id = 279968, skill = 129, rank = 20, spell = 1230117, effect = 1230124 },
    { id = 279979, skill = 393, rank = 20, spell = 1229517, effect = 1229519 },
    { id = 279978, skill = 165, rank = 20, spell = 1229432, tent = true },
    { id = 279962, skill = 182, rank = 20, spell = 1229705, effect = 1229718 },
    { id = 279976, skill = 333, rank = 20, spell = 1230643 },
    { id = 279944, skill = 164, rank = 20, spell = 1230171, effect = 1230172 },
    { id = 279960, skill = 186, rank = 20, spell = 1230161, effect = 1230164 },
    { id = 279956, skill = 171, rank = 20, spell = 1230564, effect = 1230587 },
    { id = 279972, skill = 197, rank = 20, spell = 1229504, effect = 1229513, benefit = "effect.spirit", faction = "Horde" },
    { id = 279973, skill = 197, rank = 20, spell = 1229504, effect = 1229513, benefit = "effect.spirit", faction = "Alliance" },
    { id = 279950, skill = 202, rank = 20, spell = 1230656 },
}
Camp.catalog = CATALOG
local INVENTORY_IDS = { [TOY] = true, [SLEEPING_BAG] = true }
for _, row in ipairs(CATALOG) do INVENTORY_IDS[row.id] = true end
local EFFECTS = { 1229513, 1229519, 1229718, 1230098, 1230124, 1230164, 1230172, 1230587, 1230653 }
local EFFECT_KEYS = { [1229513] = "effect.intellect", [1229519] = "effect.critical",
    [1229718] = "effect.spirit", [1230098] = "effect.attributes", [1230124] = "effect.stamina",
    [1230164] = "effect.attack_power", [1230172] = "effect.strength", [1230587] = "effect.mana" }
local TRACKED = { [NEAR] = true, [REST] = true, [REST_ALT] = true, [BENEFIT] = true, [FATIGUE] = true }
TRACKED[SLEEPING_BENEFIT] = true
for _, id in ipairs(EFFECTS) do TRACKED[id] = true end
local EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "SKILL_LINES_CHANGED",
    "SPELLS_CHANGED", "NEW_TOY_ADDED", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED",
    "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_STARTED_MOVING" }
local function Text(key) return YUI.Locale:Get("YActionBar")["camp." .. key] end
local function Number(value) return Security.SafeNumber(value) end
local function String(value) return Security.SafeString(value) end
local function InCombat() return YAB.Adapter:InCombat() end
local function Config() return YAB:GetDB().specialBars.questItems end
local function Items() return YAB.QuestItems end
local function Future(value, now) return value and value > now and value or nil end
local function Earlier(left, right) return left and right and math.min(left, right) or left or right end
local function AddLine(text, color)
    local r, g, b = YUI.GUI2:GetColor(color or "color.tooltip.body")
    GameTooltip:AddLine(text, r, g, b, true)
end

local function SetTextColor(entry, field, color)
    local text = entry[field]
    if text and entry[field .. "Color"] ~= color then
        YUI.GUI2:SetTextColorKey(text, color)
        entry[field .. "Color"] = color
    end
end

function Camp:ClearWaiting()
    self.waitStartedAt, self.waitUntil, self.waitReady = nil, nil, nil
end

function Camp:SetExpanded(value)
    if InCombat() then self.pendingCollapse = true; return false end
    self.expanded = value == true and self.panel ~= nil
    if self.panel then self.panel:SetShown(self.expanded) end
    if self.dismissFrame then self.dismissFrame:SetShown(self.expanded) end
    if self.frame then
        if self.expanded then self.frame:RegisterEvent("GLOBAL_MOUSE_DOWN")
        else self.frame:UnregisterEvent("GLOBAL_MOUSE_DOWN") end
    end
    if not self.expanded then
        self.pendingPlacement = nil
        local owner, hovered = Items(), Items().hovered
        local entry = hovered and self.entries[hovered]
        if hovered and (hovered == self.panel or entry and type(entry.key) == "number") then
            if hovered and GameTooltip:IsOwned(hovered) then GameTooltip:Hide() end
            owner.hovered = nil
            if owner.pending then owner:Request(true) end
        end
    end
    self:RefreshArrow()
    return true
end

local function ReadAura(id, now)
    if not (Unit and Unit.GetUnitAuraBySpellID) then return nil end
    local aura = Unit.GetUnitAuraBySpellID("player", id)
    if type(aura) ~= "table" or Security.IsSecretValue(aura) or Security.CanAccessTable(aura) == false then return nil end
    local spellID, expires, duration = Number(aura.spellId), Number(aura.expirationTime), Number(aura.duration)
    if spellID ~= id or (expires and expires > 0 and expires <= now) then return nil end
    return { spellID = id, icon = Number(aura.icon), name = String(aura.name),
        instance = Number(aura.auraInstanceID), expires = expires or 0, duration = duration or 0,
        applications = Number(aura.applications) }
end

local function NativeCount(id)
    return Item and Item.GetCount and Number(Item.GetCount(id, false, false, false, false)) or 0
end
local function Count(id) return Camp.counts and Camp.counts[id] or 0 end

local function ItemName(id)
    local info = Item and Item.GetInfo and Item.GetInfo(id)
    return info and String(info.name) or string.format(Text("facility_id"), id)
end

local function SpellName(id)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
    local name = info and String(info.name)
    return name and name:find("%S") and name or nil
end

local function ExpectedBenefit(row)
    local name = row.id == TOY and Text("toy_short_name") or ItemName(row.id)
    local key = row.benefit or row.effect and EFFECT_KEYS[row.effect]
    local effect = key and Text(key) or row.effect and SpellName(row.effect)
    if row.tent or row.id == TOY then effect = Text("effect.rested") end
    return effect and string.format(Text("expected_effect"), effect, name)
        or string.format(Text("identified_facility"), name)
end

function Camp:ReadInventory()
    local ranks = {}
    self.worldNames = {}
    self.itemSpells = {}
    self.counts = self.counts or {}
    self.counts[SLEEPING_BAG] = NativeCount(SLEEPING_BAG)
    for _, row in ipairs(CATALOG) do
        self.counts[row.id] = NativeCount(row.id)
        if Item and Item.GetSpell then
            local _, spellID = Item.GetSpell(row.id)
            self.itemSpells[row.id] = Number(spellID)
        end
        local info = Item and Item.GetInfo and Item.GetInfo(row.id)
        local name = info and String(info.name)
        if name then self.worldNames[name] = row.id end
        name = SpellName(row.spell)
        if name then self.worldNames[name] = row.id end
    end
    if Item and Item.GetSpell then local _, spellID = Item.GetSpell(TOY); self.itemSpells[TOY] = Number(spellID) end
    local toyInfo = Item and Item.GetInfo and Item.GetInfo(TOY)
    if toyInfo and String(toyInfo.name) then self.worldNames[toyInfo.name] = TOY end
    if Profession and Profession.GetProfessions and Profession.GetProfessionInfo then
        local indexes = { Profession.GetProfessions() }
        for slot = 1, 7 do
            local index = Number(indexes[slot])
            if index then
                local skill, _, rank = Profession.GetProfessionInfo(index)
                skill, rank = Number(skill), Number(rank)
                if skill and rank then ranks[skill] = rank end
            end
        end
    end
    local faction = UnitFactionGroup and String(UnitFactionGroup("player"))
    self.facilities = {}
    self.allowed = {}
    self.allowed[SLEEPING_BAG] = Count(SLEEPING_BAG) > 0
    for _, row in ipairs(CATALOG) do
        -- Items acquired before learning the profession remain inspectable, but
        -- an unavailable profession never creates a misleading usable action.
        if (ranks[row.skill] or 0) >= row.rank and (not row.faction or row.faction == faction) then
            self.facilities[#self.facilities + 1] = row
            self.allowed[row.id] = true
        end
    end
    self.toyOwned = PlayerHasToy and Security.SafeBoolean(PlayerHasToy(TOY)) == true or false
    self.inventoryDirty = false
end

function Camp:ReadAuras(now)
    local wasContext = self.near ~= nil or self.rest ~= nil
    self.near = ReadAura(NEAR, now)
    self.rest = ReadAura(REST, now) or ReadAura(REST_ALT, now)
    self.benefit = ReadAura(BENEFIT, now)
    self.fatigue = ReadAura(FATIGUE, now)
    self.sleepingBenefit = ReadAura(SLEEPING_BENEFIT, now)
    self.effects = {}
    for _, id in ipairs(EFFECTS) do
        local aura = ReadAura(id, now)
        if aura then self.effects[#self.effects + 1] = aura end
    end
    if self.rest then self:ClearWaiting() end
    if wasContext and not (self.near or self.rest) then
        self:ClearWaiting()
        self.pendingPlacement = nil
        self.holdUntil = now + 5
        wipe(self.observed)
    elseif self.near or self.rest then self.holdUntil = nil end
    self.auraDirty = false
end

function Camp:HasContext()
    return self.active == true and (self.near ~= nil or self.rest ~= nil or Future(self.holdUntil, GetTime()) ~= nil)
end

function Camp:NextDeadline(now)
    if not self.active then return nil end
    local nextAt = Earlier(Future(self.holdUntil, now), Future(self.waitUntil, now))
    for _, aura in ipairs({ self.near or false, self.rest or false, self.benefit or false, self.fatigue or false,
        self.sleepingBenefit or false }) do
        if aura then nextAt = Earlier(nextAt, Future(aura.expires, now)) end
    end
    for _, aura in ipairs(self.effects) do nextAt = Earlier(nextAt, Future(aura.expires, now)) end
    for _, expires in pairs(self.observed) do nextAt = Earlier(nextAt, Future(expires, now)) end
    for button, entry in pairs(self.entries) do
        if self.visible and self.visible[button] then nextAt = Earlier(nextAt, Future(entry.cooldownEnd, now)) end
    end
    return nextAt
end

function Camp:Update(now)
    if not self.active then return end
    if self.pendingCollapse and not InCombat() then
        self.pendingCollapse, self.expanded = nil, false
        self:SetExpanded(false)
    end
    if self.auraDirty or (self.nextAt and self.nextAt <= now) then self:ReadAuras(now) end
    if self.inventoryDirty then self:ReadInventory() end
    if self.waitUntil and self.waitUntil <= now then self.waitUntil, self.waitReady = nil, true end
    for id, expires in pairs(self.observed) do if expires <= now then self.observed[id] = nil end end
    self:RefreshVisuals()
    self.nextAt = self:NextDeadline(now)
    self.passes = self.passes + 1
end

function Camp:GetSignature()
    if not self.active or not self:HasContext() then return "" end
    local keys = { "sit", Count(SLEEPING_BAG) > 0 and "sleep" or "", self.toyOwned and "toy" or "", self.fatigue and "fatigue" or "" }
    for _, row in ipairs(self.facilities) do keys[#keys + 1] = tostring(row.id) end
    return table.concat(keys, ":")
end

function Camp:IsButton(button) return self.entries[button] ~= nil end

function Camp:IsWanted(button)
    local entry = self.entries[button]
    if not entry or not self.active or not self:HasContext() then return false end
    if entry.key == "sleep" then return Count(SLEEPING_BAG) > 0 end
    if entry.key == "toy" then return self.toyOwned end
    if entry.key == "fatigue" then return self.fatigue ~= nil end
    if entry.key == "toggle" then return #self.facilities > 0 end
    return entry.key == "sit"
end

function Camp:ObservedCount()
    local count = 0
    for _ in pairs(self.observed) do count = count + 1 end
    return count
end

function Camp:HasEffect(spellID)
    if not spellID then return false end
    for _, aura in ipairs(self.effects) do if aura.spellID == spellID then return true end end
    return false
end

function Camp:TooltipPreview(hasBuff)
    local shown, restrictedShown = false, false
    for index = 1, #CATALOG + 1 do
        local row = CATALOG[index] or TOY_FACILITY
        if self.observed[row.id] and not self:HasEffect(row.effect) then
            if not shown then
                GameTooltip:AddLine(" ")
                AddLine(Text("expected"), "color.tooltip.heading")
                shown = true
            end
            if self.fatigue and (row.tent or row.id == TOY) then
                if not restrictedShown then
                    AddLine(Text("rested_restricted"), "color.state.danger")
                    restrictedShown = true
                end
            else
                -- Native observations identify a tent type, not its owner or party.
                AddLine(row.id == TOY and Text("toy_group_preview") or ExpectedBenefit(row))
            end
        end
    end
    if shown then AddLine(Text("partial"), "color.tooltip.secondary")
    elseif not hasBuff and self:ObservedCount() == 0 then
        GameTooltip:AddLine(" ")
        AddLine(Text("unknown"), "color.tooltip.secondary")
    end
end

local function ShowAura(aura)
    if aura and aura.instance and GameTooltip.SetUnitAuraByAuraInstanceID then
        GameTooltip:SetUnitAuraByAuraInstanceID("player", aura.instance)
        return true
    end
    return false
end

function Camp:PositionTooltip()
    local holder = Items().record and Items().record.holder
    if not holder then return end
    local left, right, top = holder:GetLeft(), holder:GetRight(), holder:GetTop()
    if self.expanded and self.panel then
        left = math.min(left or 0, self.panel:GetLeft() or left or 0)
        right = math.max(right or 0, self.panel:GetRight() or right or 0)
        top = math.max(top or 0, self.panel:GetTop() or top or 0)
    end
    if not (left and right and top) then return end
    local width, height = GameTooltip:GetWidth(), GameTooltip:GetHeight()
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local x = right + 8
    if x + width > screenWidth then x = math.max(4, left - width - 8) end
    local y = math.min(screenHeight - 4, math.max(height + 4, top))
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

function Camp:Tooltip(button)
    local entry = self.entries[button]
    if not entry or not self.active or Items().editing then return end
    if YAB:GetDB().interaction.tooltipMode == "outOfCombat" and InCombat() then
        if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_NONE")
    if entry.key == "sit" then
        local buff = self.benefit or self.effects[1]
        if self.rest then
            if not ShowAura(self.rest) then
                GameTooltip:SetText(Text("resting"))
                GameTooltip:AddLine(Text("keep_resting"), 1, 1, 1, true)
            end
        elseif self.waitStartedAt then
            GameTooltip:SetText(Text("sit"))
            AddLine(Text(self.waitReady and "waiting_retry" or "waiting"), "color.state.warning")
            if buff then
                local names
                for _, aura in ipairs(self.effects) do
                    local name = aura.name or SpellName(aura.spellID)
                    if name then names = names and names .. Text("effect_separator") .. name or name end
                end
                GameTooltip:AddLine(" ")
                AddLine(string.format(Text("current_effects"), names or buff.name or Text("benefits")), "color.state.success")
            end
        elseif buff then
            if not ShowAura(buff) then GameTooltip:SetText(buff.name or Text("benefits")) end
            if #self.effects > 0 then
                local separated = false
                for _, aura in ipairs(self.effects) do
                    local name = aura.name or SpellName(aura.spellID)
                    if aura.spellID ~= buff.spellID and name then
                        if not separated then GameTooltip:AddLine(" "); separated = true end
                        AddLine(name, "color.state.success")
                    end
                end
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(Text("refresh"), 1, 1, 1, true)
        else
            GameTooltip:SetText(Text("sit"))
            AddLine(Text(not self.near and "no_signal" or "sit_help"))
        end
        if not self.rest and self.near then self:TooltipPreview(buff ~= nil) end
    elseif entry.key == "toggle" then
        GameTooltip:SetText(Text("facilities"))
        local carried = 0
        for _, row in ipairs(self.facilities) do if Count(row.id) > 0 then carried = carried + 1 end end
        GameTooltip:AddLine(string.format(Text("facility_counts"), carried, #self.facilities), 1, 1, 1, true)
        GameTooltip:AddLine(Text(self.expanded and "collapse" or "expand"), 1, 1, 1, true)
    elseif entry.key == "fatigue" then
        if not ShowAura(self.fatigue) then GameTooltip:SetText(Text("restriction_ended")) end
        GameTooltip:AddLine(Text("restriction_help"), 1, 1, 1, true)
    else
        GameTooltip:SetItemByID(entry.id)
        if entry.key ~= "toy" and Count(entry.id) == 0 then AddLine(Text("missing"), "color.state.danger") end
        if entry.key == "sleep" and self.sleepingBenefit then
            local aura = self.sleepingBenefit
            local name = aura.name or SpellName(SLEEPING_BENEFIT)
            if name then
                if aura.applications and aura.applications > 0 then
                    name = string.format(Text("sleep_stacks"), name, aura.applications)
                end
                GameTooltip:AddLine(" ")
                AddLine(string.format(Text("current_effects"), name), "color.state.success")
                if aura.expires > GetTime() then
                    AddLine(string.format(Text("benefit_remaining"), SecondsToTime(aura.expires - GetTime(), false, true)), "color.state.success")
                end
            end
        end
        if self.fatigue and (entry.key == "toy" or entry.row and entry.row.tent) then
            GameTooltip:AddLine(Text(entry.key == "toy" and "toy_restriction" or "restriction_help"), 1, 0.82, 0, true)
        end
    end
    if InCombat() then AddLine(Text("combat"), "color.state.danger") end
    if entry.key == "sit" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(YUI.GUI2.Tooltip:FormatAction({ button = "LeftButton", modifiers = { "ALT" } }, true))
    end
    GameTooltip:Show()
    self:PositionTooltip()
end

local function Enter(button)
    if not Camp.active then return end
    Items().hovered = button
    Camp:Tooltip(button)
end

local function Leave(button)
    local owner = Items()
    if owner.hovered == button then owner.hovered = nil end
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    if owner.pending then owner:Request(true) end
end

local function AfterSit()
    if not Camp.active or InCombat() or Items().editing or Camp.rest or (Camp.waitStartedAt and not Camp.waitReady) then return end
    Camp.waitStartedAt, Camp.waitUntil, Camp.waitReady = GetTime(), GetTime() + 10, nil
    Camp:RefreshVisuals()
    Items():Request(true)
end

local function OpenSettings()
    if not Camp.active or InCombat() or Items().editing then return end
    YAB.SettingsBridge:Open("questItems", "display")
end

local function Toggle()
    if not Camp.active or InCombat() or Items().editing or not Camp.panel then return end
    Camp:SetExpanded(not Camp.expanded)
    Camp:RefreshVisuals()
    if Items().hovered and Camp.entries[Items().hovered] then Camp:Tooltip(Items().hovered) end
end

local function BeforePlace(button)
    local entry = Camp.entries[button]
    if not entry or not entry.id or InCombat() or not Camp.expanded then return end
    Camp.pendingPlacement = { id = entry.id, count = Count(entry.id), spell = Camp.itemSpells[entry.id],
        cooldownEnd = entry.cooldownEnd or 0 }
end

function Camp:ConfirmPlacement()
    local pending = self.pendingPlacement
    if not (pending and pending.cast) then return end
    local cooldownEnd = 0
    for button, entry in pairs(self.entries) do if entry.id == pending.id then cooldownEnd = entry.cooldownEnd or 0; break end end
    if Count(pending.id) < pending.count or (pending.id == TOY and cooldownEnd > math.max(GetTime(), pending.cooldownEnd)) then self:SetExpanded(false) end
end

function Camp:EnsureButton(record, key, id, row)
    local button = self.pool[key]
    if not button then
        button = YUI.GUI2.Secure:CreateActionHost(record.holder, { useOnKeyDown = false,
            onEnter = Enter, onLeave = Leave, frameLevelOffset = 1 })
        if not button then return nil end
        button:ClearAllPoints()
        YAB.SecureFactory:SetButtonMeta(button, { barId = "questItems", kind = "questItems" })
        self.pool[key] = button
        self.entries[button] = { key = key, id = id, row = row, visual = { hasAction = true, hotkeyText = "", nameText = "" } }
        local host = YUI.GUI2:CreateFrame(button, { width = 1, height = 1, mouse = false })
        host:SetAllPoints(button)
        self.entries[button].textHost = host
        if type(key) == "string" then
            local label = YUI.GUI2:CreateText(host, "", "font.size.sm", "color.tooltip.heading")
            YUI.GUI2:ApplyFontAppearance(label, { outline = "outlineShadow", size = YUI.GUI2:GetMetric("font.size.sm", 12) })
            label:SetPoint("BOTTOM", button, "BOTTOM", 0, 1)
            label:SetJustifyH("CENTER")
            self.entries[button].label = label
            if key == "sit" then
                local badge = YUI.GUI2:CreateText(host, "", "font.size.sm", "color.tooltip.heading")
                YUI.GUI2:ApplyFontAppearance(badge, { outline = "outlineShadow", size = YUI.GUI2:GetMetric("font.size.sm", 12) })
                badge:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -1)
                badge:SetJustifyH("RIGHT")
                badge:Hide()
                self.entries[button].badge = badge
            elseif key == "toggle" then
                local arrow = YUI.GUI2:CreateText(host, "", "font.size.sm", "color.tooltip.heading")
                YUI.GUI2:ApplyFontAppearance(arrow, { outline = "outlineShadow", size = YUI.GUI2:GetMetric("font.size.sm", 12) })
                arrow:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -1)
                arrow:SetJustifyH("RIGHT")
                self.entries[button].arrow = arrow
            end
        end
    end
    return button
end

function Camp:Actions(button, editing)
    local entry = self.entries[button]
    local enabled = not editing and self.active and (self.near or self.rest)
    local canUse = enabled and (not entry.id or (entry.key == "toy" and self.toyOwned)
        or (entry.key ~= "toy" and self.allowed and self.allowed[entry.id] and Count(entry.id) > 0))
    local mode = editing and "edit" or entry.key == "sit" and (canUse and not self.rest
        and (not self.waitStartedAt or self.waitReady) and "sit" or "noop")
        or entry.key == "toggle" and "toggle" or entry.id and canUse and "item" or "noop"
    if entry.actionMode == mode then return end
    local action
    if mode == "sit" then action = { kind = "macro", macrotext = "/stopmacro [combat]\n/sit", afterClick = AfterSit }
    elseif mode == "item" then action = { kind = "macro", macrotext = "/stopmacro [combat]\n/use item:" .. entry.id,
        beforeClick = entry.key ~= "sleep" and BeforePlace or nil }
    elseif mode == "toggle" then action = { kind = "custom", onClick = Toggle } end
    button:SetActions({ left = action, right = action,
        altLeft = entry.key == "sit" and not editing and { kind = "custom", onClick = OpenSettings } or nil })
    entry.actionMode = mode
end

local function Cooldown(visual, startAt, duration, enabled)
    visual.cooldownStart, visual.cooldownDuration = startAt or 0, duration or 0
    visual.cooldownEnable = enabled == true
    visual.cooldownActive = enabled == true
end

function Camp:RefreshArrow()
    local entry = self.pool.toggle and self.entries[self.pool.toggle]
    if not (entry and entry.arrow) then return end
    local arrows = ARROWS[self.panelDirection or Config().flyoutDirection] or ARROWS.up
    local text = arrows[self.expanded and 2 or 1]
    if entry.arrowText ~= text then entry.arrow:SetText(text); entry.arrowText = text end
end

function Camp:RefreshVisuals()
    local owner, now = Items(), GetTime()
    if not self.active or not owner then return end
    local editing = owner.editing == true
    for button, entry in pairs(self.entries) do
      if self.visible and self.visible[button] then
        local state = entry.visual
        local aura
        state.cooldownIsStatus = false
        state.campPresentation = nil
        state.texture, state.countText, state.checked = FIRE_ICON, "", false
        state.usable = not InCombat() and (self.near ~= nil or self.rest ~= nil)
        Cooldown(state, 0, 0, false)
        if entry.key == "sit" then
            local waiting = self.waitStartedAt ~= nil and not self.rest
            aura = self.rest
            if not aura and not waiting then aura = self.benefit or self.effects[1] end
            state.texture = aura and aura.icon or FIRE_ICON
            state.usable = aura ~= nil or (not InCombat() and self.near ~= nil)
            local count = self:ObservedCount()
            local badge = (editing or aura) and ""
                or waiting and (self.waitReady and "" or "…") or count > 0 and (entry.compact and tostring(count)
                    or string.format(Text("preview_badge"), count)) or ""
            if entry.badgeText ~= badge then
                entry.badge:SetText(badge)
                entry.badge:SetShown(badge ~= "")
                entry.badgeText = badge
            end
            SetTextColor(entry, "badge", aura and "color.state.success" or self.waitStartedAt and "color.state.warning"
                or count > 0 and "color.tooltip.heading" or "color.tooltip.secondary")
        elseif entry.key == "fatigue" then
            aura = self.fatigue
            state.texture, state.usable = aura and aura.icon or 134250, false
            state.campPresentation = aura and "restriction" or nil
        elseif entry.key == "toggle" then
            state.texture, state.checked = FACILITIES_ICON, self.expanded == true
            state.usable = not InCombat()
        elseif entry.id then
            local texture = Item and Item.GetIcon and Item.GetIcon(entry.id)
            state.texture = Number(texture) or String(texture) or UNKNOWN_ICON
            local count = Count(entry.id)
            state.countText = entry.key ~= "toy" and entry.key ~= "sleep" and Config().showCounts ~= false and tostring(count) or ""
            state.usable = state.usable and (entry.key == "toy" and self.toyOwned
                or entry.key ~= "toy" and self.allowed and self.allowed[entry.id] and count > 0)
            local cd = Item and Item.GetCooldown and Item.GetCooldown(entry.id)
            local startAt, duration = cd and Number(cd.startTime), cd and Number(cd.duration)
            local enabled = cd and (Security.SafeBoolean(cd.isEnabled) == true or Number(cd.isEnabled) == 1)
            local active = enabled and startAt and duration and duration > 0 and startAt + duration > now
            entry.cooldownEnd = active and startAt + duration or nil
            Cooldown(state, startAt, duration, active == true)
            if active then state.usable = false end
            if entry.key == "toy" and active then state.campPresentation = "toyCooldown" end
        end
        if aura and aura.duration > 0 and aura.expires > now then Cooldown(state, aura.expires - aura.duration, aura.duration, true) end
        state.cooldownIsStatus = (entry.key == "sit" or entry.key == "fatigue") and aura ~= nil
        if not InCombat() then self:Actions(button, editing) end
        if editing then Cooldown(state, 0, 0, false); state.usable, state.countText = true, "" end
        if entry.label then
            local key = entry.key == "sit" and (self.rest and "rest_short"
                or self.waitStartedAt and (self.waitReady and "retry_short" or "waiting_short")
                or aura and "benefits_short" or "sit_short")
                or entry.key .. "_short"
            local label = Text(key)
            if entry.labelText ~= label then entry.label:SetText(label); entry.labelText = label end
            SetTextColor(entry, "label", self.fatigue and (entry.key == "toy" or entry.key == "fatigue") and "color.state.danger"
                or entry.key == "sleep" and not editing and self.sleepingBenefit and "color.state.success"
                or entry.key == "sit" and self.waitStartedAt and "color.state.warning"
                or entry.key == "sit" and not self.rest and aura and "color.state.success" or "color.tooltip.heading")
        end
        YAB.Visuals:UpdateButton(button, state, "full")
      end
    end
    self:RefreshArrow()
    if owner.hovered and self.entries[owner.hovered] and GameTooltip:IsOwned(owner.hovered) then self:Tooltip(owner.hovered) end
end

function Camp:Apply(record, editing)
    if InCombat() then return end
    local shown = {}
    record.classButtons = {}
    self.panelButtons = {}
    if not self.hookedHolders then self.hookedHolders = setmetatable({}, { __mode = "k" }) end
    if not self.hookedHolders[record.holder] then
        record.holder:HookScript("OnHide", function(holder)
            if not Camp.active or not Camp.panel or Camp.panel:GetParent() ~= holder then return end
            if InCombat() then Camp.pendingCollapse = true
            else Camp:SetExpanded(false) end
            local hovered = Items().hovered
            if hovered and (Camp.entries[hovered] or hovered == Camp.panel) then
                if GameTooltip:IsOwned(hovered) then GameTooltip:Hide() end
                Items().hovered = nil
            end
        end)
        self.hookedHolders[record.holder] = true
    end
    if self.active and (editing or self:HasContext()) then
        local keys = { "sit" }
        if Count(SLEEPING_BAG) > 0 or editing then keys[#keys + 1] = "sleep" end
        if self.toyOwned or editing then keys[#keys + 1] = "toy" end
        if self.fatigue or editing then keys[#keys + 1] = "fatigue" end
        if #self.facilities > 0 or editing then keys[#keys + 1] = "toggle" end
        for _, key in ipairs(keys) do
            local button = self:EnsureButton(record, key, key == "toy" and TOY or key == "sleep" and SLEEPING_BAG or nil)
            if button then
                button:SetParent(record.holder)
                shown[button] = true
                record.buttons[#record.buttons + 1] = button
                button:SetAlpha(1)
                button:Show()
            end
        end
        if #self.facilities > 0 and not editing then
            if not self.panel then
                self.panel = YUI.GUI2:CreateFrame(record.holder, { width = 1, height = 1, mouse = true })
                self.panel:SetClampedToScreen(true)
                self.panel:SetScript("OnEnter", function(owner) if Camp.active then Items().hovered = owner end end)
                self.panel:SetScript("OnLeave", Leave)
                self.dismissFrame = YUI.GUI2:CreateFrame(UIParent, { width = 1, height = 1, mouse = false, hidden = true })
                self.dismissFrame:SetScript("OnHide", function() if Camp.expanded then Camp:SetExpanded(false) end end)
                YUI.GUI2:EnableEscapeClose(self.dismissFrame, function() Camp:SetExpanded(false); Camp:RefreshVisuals() end)
            end
            self.panel:SetParent(record.holder)
            self.panel:SetFrameLevel(record.holder:GetFrameLevel() + 5)
            record.classButtons[1] = self.panel
            self.panelButtons = {}
            for _, row in ipairs(self.facilities) do
                local button = self:EnsureButton(record, row.id, row.id, row)
                if button then
                    button:SetParent(self.panel)
                    button:SetFrameLevel(self.panel:GetFrameLevel() + 1)
                    shown[button] = true
                    self.panelButtons[#self.panelButtons + 1] = button
                    record.classButtons[#record.classButtons + 1] = button
                    button:Show()
                end
            end
        else self.expanded = false end
    else self.expanded = false end
    for button, entry in pairs(self.entries) do
        if not shown[button] then button:Hide(); button:SetActions({}); entry.actionMode = nil; YAB.Visuals:ReleaseButton(button) end
    end
    self.visible = shown
    self:SetExpanded(self.expanded == true)
end

function Camp:Layout(record)
    if InCombat() then return end
    for _, button in ipairs(record.buttons) do
        local entry = self.entries[button]
        if entry and entry.label then
            entry.compact = button:GetWidth() < 36
            entry.label:SetShown(not entry.compact)
        end
        if entry then YAB.Visuals:PrepareCampText(button, entry.textHost) end
    end
    if not self.panel or not self.pool.toggle then return end
    local buttons, toggle, snapshot = self.panelButtons or {}, self.pool.toggle, record.configSnapshot
    if #buttons == 0 then return end
    local width, height = toggle:GetWidth(), toggle:GetHeight()
    local gap = math.max(2, snapshot.spacing or 4)
    local offset = math.max(4, gap)
    local direction = Config().flyoutDirection or "up"
    local holder = record.holder
    local left, right, top, bottom = holder:GetLeft(), holder:GetRight(), holder:GetTop(), holder:GetBottom()
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local room = { up = screenHeight - (top or screenHeight) - offset, down = (bottom or 0) - offset,
        left = (left or 0) - offset, right = screenWidth - (right or screenWidth) - offset }
    local opposite = { up = "down", down = "up", left = "right", right = "left" }
    if not room[direction] then direction = "up" end
    local vertical = direction == "up" or direction == "down"
    local unit = vertical and height or width
    if room[direction] < unit and room[opposite[direction]] > room[direction] then direction = opposite[direction] end
    local primary = math.max(1, math.min(#buttons, 6, math.floor((room[direction] + gap) / (unit + gap))))
    local secondary = math.ceil(#buttons / primary)
    local columns, rows = vertical and secondary or primary, vertical and primary or secondary
    local panelWidth, panelHeight = columns * (width + gap) - gap, rows * (height + gap) - gap
    self.panel:SetSize(panelWidth, panelHeight)
    self.panel:ClearAllPoints()
    self.panelDirection = direction
    local x = math.max(4, math.min(toggle:GetLeft() or 4, screenWidth - panelWidth - 4))
    local y = math.min(screenHeight - 4, math.max(panelHeight + 4, toggle:GetTop() or screenHeight - 4))
    if vertical then
        if direction == "up" then self.panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, (top or 0) + offset)
        else self.panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, (bottom or 0) - offset) end
    elseif direction == "left" then self.panel:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", (left or 0) - offset, y)
    else self.panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (right or 0) + offset, y) end
    for index, button in ipairs(buttons) do
        button:SetSize(width, height)
        button:ClearAllPoints()
        local p, s = (index - 1) % primary, math.floor((index - 1) / primary)
        if direction == "up" then button:SetPoint("BOTTOMLEFT", self.panel, "BOTTOMLEFT", s * (width + gap), p * (height + gap))
        elseif direction == "down" then button:SetPoint("TOPLEFT", self.panel, "TOPLEFT", s * (width + gap), -p * (height + gap))
        elseif direction == "left" then button:SetPoint("TOPRIGHT", self.panel, "TOPRIGHT", -p * (width + gap), -s * (height + gap))
        else button:SetPoint("TOPLEFT", self.panel, "TOPLEFT", p * (width + gap), -s * (height + gap)) end
        YAB.Skins:ApplyButton(button, YAB.Skins:Normalize("default"), { size = snapshot.size,
            width = width, height = height, zoom = snapshot.iconZoom, snapshot = snapshot })
        YAB.Visuals:PrepareCampText(button, self.entries[button].textHost)
    end
    self:RefreshVisuals()
end

-- This is observation of a native world tooltip, never a scan of all camp
-- objects. Records expire and are discarded on losing the camp/zone signal.
function Camp:ObserveTooltip(tooltip, tooltipData)
    if tooltip ~= GameTooltip or not self.active or not (self.near or self.rest) then return end
    if type(tooltipData) ~= "table" or Security.IsSecretValue(tooltipData)
        or Security.CanAccessTable(tooltipData) == false then return end
    local guid = String(tooltipData.guid)
    local kind = Number(tooltipData.type)
    local types = Enum and Enum.TooltipDataType
    local world = guid and (guid:match("^GameObject%-") or guid:match("^Creature%-"))
        or types and types.Object and kind == types.Object
    if not world then return end
    local name = _G.GameTooltipTextLeft1 and String(_G.GameTooltipTextLeft1:GetText())
    if not name then return end
    local id = self.worldNames and self.worldNames[name]
    if not id then return end
    local now = GetTime()
    -- Native tooltips may be refreshed repeatedly without a new pointer entry.
    -- Repeated evidence must not cause per-frame visual work or timer churn.
    if self.observed[id] and self.observed[id] > now + 15 then return end
    self.observed[id] = now + 30
    self:RefreshVisuals()
    Items():Request(true)
end

local function TooltipPostCall(tooltip, data) Camp:ObserveTooltip(tooltip, data) end
local function RelevantUpdate(update)
    if type(update) ~= "table" or Security.IsSecretValue(update) or Security.CanAccessTable(update) == false then return true end
    if Security.SafeBoolean(update.isFullUpdate) == true then return true end
    for _, field in ipairs({ "addedAuras", "updatedAuraInstanceIDs", "removedAuraInstanceIDs" }) do
        local value = update[field]
        if value ~= nil and (Security.IsSecretValue(value) or Security.CanAccessTable(value) == false) then return true end
    end
    for _, aura in ipairs(update.addedAuras or {}) do
        if type(aura) == "table" and not Security.IsSecretValue(aura) and Security.CanAccessTable(aura) ~= false
            and TRACKED[Number(aura.spellId) or 0] then return true end
    end
    local function Known(instance)
        for _, aura in ipairs({ Camp.near or false, Camp.rest or false, Camp.benefit or false, Camp.fatigue or false,
            Camp.sleepingBenefit or false }) do
            if aura and aura.instance == instance then return true end
        end
        for _, aura in ipairs(Camp.effects) do if aura.instance == instance then return true end end
    end
    for _, instance in ipairs(update.updatedAuraInstanceIDs or {}) do if Known(Number(instance)) then return true end end
    for _, instance in ipairs(update.removedAuraInstanceIDs or {}) do if Known(Number(instance)) then return true end end
    return false
end

local function OnEvent(_, event, unit, update, spellID)
    if not Camp.active then return end
    if event == "PLAYER_STARTED_MOVING" then
        if not Camp.waitStartedAt then return end
        Camp:ClearWaiting()
    elseif (event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN")
        and not Camp:HasContext() and not Camp.pendingPlacement then return end
    if event == "GLOBAL_MOUSE_DOWN" then
        if Camp.expanded and not Camp.panel:IsMouseOver() and not Camp.pool.toggle:IsMouseOver()
            and not (Camp.pendingPlacement and SpellIsTargeting and Security.SafeBoolean(SpellIsTargeting()) == true) then
            Camp:SetExpanded(false); Camp:RefreshVisuals()
        end
        return
    end
    if event:find("UNIT_SPELLCAST_", 1, true) then
        local pending = Camp.pendingPlacement
        if unit ~= "player" or not pending or not pending.spell or pending.spell ~= Number(spellID) then return end
        if event ~= "UNIT_SPELLCAST_SUCCEEDED" then Camp.pendingPlacement = nil; return end
        pending.cast = true
    end
    if event == "GET_ITEM_INFO_RECEIVED" and not INVENTORY_IDS[Number(unit) or 0] then return end
    if event == "UNIT_AURA" and unit ~= "player" then return end
    if event == "UNIT_AURA" and not RelevantUpdate(update) then return end
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        wipe(Camp.observed); Camp.holdUntil = nil
        Camp:ClearWaiting(); Camp.pendingPlacement = nil
        Camp.near, Camp.rest = nil, nil
    end
    if event == "PLAYER_REGEN_DISABLED" then Camp:ClearWaiting(); Camp.pendingPlacement = nil end
    -- Combat may temporarily make an aura unreadable. Its persistent instance
    -- can then return only as an unknown delta, so resync before deferred layout.
    if event == "UNIT_AURA" or event == "PLAYER_REGEN_ENABLED"
        or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then Camp.auraDirty = true end
    if event == "SKILL_LINES_CHANGED" or event == "SPELLS_CHANGED" or event == "NEW_TOY_ADDED"
        or event == "BAG_UPDATE_DELAYED" or event == "PLAYER_ENTERING_WORLD" or event == "GET_ITEM_INFO_RECEIVED" then Camp.inventoryDirty = true end
    -- Visible state is independent of hover/combat structure deferral.
    Camp:Update(GetTime())
    Camp:ConfirmPlacement()
    Items():Request(true)
end

function Camp:Start()
    if self.active or Config().showCampTools == false then return end
    self.active, self.auraDirty, self.inventoryDirty = true, true, true
    self.frame = self.frame or CreateFrame("Frame")
    self.frame:SetScript("OnEvent", OnEvent)
    self.frame:RegisterUnitEvent("UNIT_AURA", "player")
    self.frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    self.frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    self.frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    for _, event in ipairs(EVENTS) do self.frame:RegisterEvent(event) end
    if not self.tooltipHooked and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        for _, kind in ipairs({ Enum.TooltipDataType.Unit, Enum.TooltipDataType.Object }) do
            if kind then TooltipDataProcessor.AddTooltipPostCall(kind, TooltipPostCall) end
        end
        self.tooltipHooked = true
    end
    self:Update(GetTime())
end

function Camp:Stop()
    local owner = Items()
    if owner and owner.hovered and self.entries[owner.hovered] then
        if GameTooltip:IsOwned(owner.hovered) then GameTooltip:Hide() end
        owner.hovered = nil
    end
    self.active, self.expanded = false, false
    self.visible = nil
    if self.frame then self.frame:UnregisterAllEvents(); self.frame:SetScript("OnEvent", nil) end
    wipe(self.observed)
    self.near, self.rest, self.benefit, self.fatigue = nil, nil, nil, nil
    self.sleepingBenefit = nil
    self:ClearWaiting()
    self.holdUntil, self.nextAt, self.pendingCollapse, self.panelDirection, self.pendingPlacement = nil, nil, nil, nil, nil
    if self.dismissFrame then self.dismissFrame:Hide() end
    wipe(self.effects)
    if not InCombat() then self:Release() end
end

function Camp:Release()
    if InCombat() then return end
    self:SetExpanded(false)
    if self.panel then self.panel:Hide() end
    if self.panel and YAB.BarManager.mouseoverRecords then YAB.BarManager.mouseoverRecords[self.panel] = nil end
    for button, entry in pairs(self.entries) do
        if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
        button:Hide(); button:SetActions({}); entry.actionMode = nil
        YAB.Visuals:ReleaseButton(button)
        if YAB.BarManager.mouseoverRecords then YAB.BarManager.mouseoverRecords[button] = nil end
    end
end

function Camp:GetStats()
    local pooled = 0
    for _ in pairs(self.pool) do pooled = pooled + 1 end
    return { active = self.active == true, pooledButtons = pooled, passes = self.passes,
        observations = self:ObservedCount(), listeners = self.active and #EVENTS + 4 + (self.expanded and 1 or 0) or 0,
        deadline = self.nextAt, expanded = self.expanded == true }
end

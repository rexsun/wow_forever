local YUI = _G.YUI
local YAB = YUI and YUI.YActionBar
if not (YAB and YAB.Client and YAB.Client.classBars == true) then return end
local Mage = { pool = {}, choices = {}, states = {}, inventoryDirty = true, auraDirty = true }
YAB.MageTools = Mage
local Data, Spell, Item, Unit, Security = YAB.MageData, YUI.API.Spell, YUI.API.Item, YUI.API.Unit, YUI.API.Security
local function Text(key) return YUI.Locale:Get("YActionBar")["class_tools." .. key] end
local function Number(value) return Security.SafeNumber(value) end
local function Info(id) return Spell.GetInfo(id) end
local function Name(id) local info = Info(id); return info and Security.SafeString(info.name) end
local function Icon(id) local info = Info(id); return info and (Number(info.originalIconID) or Number(info.iconID)) end
local function Texture(icon) return "|T" .. tostring(icon or 134400) .. ":16:16:0:0:64:64:4:60:4:60|t" end
local TIMER_KEYS = { "intellect", "armor" }
local function Action(tip, key, id, showLearningState)
    local name = Name(id) or Text("unlearned")
    if showLearningState and Spell.GetKnownState(id) == false then
        name = "|cff808080" .. name .. "|r |cffff2020" .. Text("unlearned_suffix") .. "|r"
    end
    tip:AddLine(Text(key) .. ": " .. Texture(Icon(id)) .. " " .. name, 1, 1, 1)
end

local function Now()
    local system = YUI.API.System
    return system and system.GetTime and Number(system.GetTime())
end

function Mage:HideReceipts()
    local root = self.receiptFrame
    if not root then return end
    if YUI.Animation then YUI.Animation:StopOwner(root) end
    for _, row in ipairs(root.rows) do row.active = false; row:Hide() end
    root:Hide()
end

local function ScrollHidden()
    Mage.comprehension = nil
    Mage:HideReceipts()
end

-- The three visual rows are prepared OOC, independent of secure spell hosts.
function Mage:PrepareReceipts()
    if self.receiptFrame or YAB.Adapter:InCombat() then return end
    local gui = YUI.GUI2
    if not (gui and gui.CreateFrame and gui.CreateText and gui.ApplyFontAppearance
        and YUI.Animation and YUI.Animation.FloatText) then return end
    local root = gui:CreateFrame(UIParent, { mouse = false, frameStrata = "HIGH" })
    root.rows, root.cursor = {}, 0
    for index = 1, 3 do
        local row = gui:CreateFrame(root, { width = 1, height = 24, mouse = false })
        row.text = gui:CreateText(row, "", "font.size.md", "color.text.primary", "CENTER")
        row.text:SetAllPoints(row)
        row.text:SetWordWrap(false)
        gui:ApplyFontAppearance(row.text, { size = 14, outline = "outlineShadow" })
        row.finished = function()
            row.active = false
            for _, other in ipairs(root.rows) do if other.active then return end end
            root:Hide()
        end
        row:Hide()
        root.rows[index] = row
    end
    root:SetScript("OnHide", function()
        YUI.Animation:StopOwner(root)
        for _, row in ipairs(root.rows) do row.active = false; row:Hide() end
    end)
    root:Hide()
    self.receiptFrame = root
end

function Mage:ShowReceipt(itemID, count)
    local record = YAB.BarManager and YAB.BarManager.bars.mageTools
    local root, scroll = self.receiptFrame, self.pool.scroll
    if not (root and record and not record.classBarEditing and scroll and scroll:IsVisible()) then return false end
    local info = Item.GetInfo(itemID)
    local name = info and Security.SafeString(info.name)
    if not name then return false, "item-data" end
    local quality = Number(info.quality)
    if quality and Item.GetQualityColor then
        local _, _, _, hex = Item.GetQualityColor(quality)
        hex = Security.SafeString(hex)
        if hex and hex:match("^%x%x%x%x%x%x%x%x$") then name = "|c" .. hex .. name .. "|r" end
    end
    local mover = record.mover
    local scale = mover and Number(mover:GetEffectiveScale())
    local parentScale, width, height = Number(UIParent:GetEffectiveScale()), Number(UIParent:GetWidth()), Number(UIParent:GetHeight())
    local x = mover and Number(mover:GetCenter())
    local top, bottom = mover and Number(mover:GetTop()), mover and Number(mover:GetBottom())
    if not (x and top and bottom and scale and parentScale and width and height and parentScale > 0 and width > 24 and height > 96) then return false end
    scale = scale / parentScale
    x, top, bottom = x * scale, top * scale, bottom * scale
    local above = height - top >= bottom
    local index = root.cursor % 3 + 1
    for candidate, row in ipairs(root.rows) do if not row.active then index = candidate; break end end
    root.cursor = index
    local row = root.rows[index]
    YUI.Animation:StopTarget(row, "comprehension-result")
    local message = Texture(info.texture or Item.GetIcon(itemID)) .. " " .. name
    if count > 1 then message = message .. " ×" .. count end
    row:SetSize(width - 16, 24)
    row.text:SetText(string.format(Text("received"), message))
    local textWidth = math.min(Number(row.text:GetStringWidth()) or 256, width - 20)
    row:SetSize(textWidth + 4, 24)
    local halfWidth = (textWidth + 4) / 2
    x = math.max(halfWidth + 8, math.min(width - halfWidth - 8, x))
    -- Keep the whole 32px travel outside adjacent rows, even for quick casts.
    local offset = (index - 1) * 60
    local y = above and math.min(top + 8 + offset, height - 64) or math.max(bottom - 8 - offset, 64)
    row:ClearAllPoints()
    row:SetPoint(above and "BOTTOM" or "TOP", UIParent, "BOTTOMLEFT", x, y)
    row:SetAlpha(1)
    row.active = true
    root:Show(); row:Show()
    local handle = YUI.Animation:FloatText(row, { owner = root, key = "comprehension-result",
        direction = above and "up" or "down", distance = 32, duration = 2, easing = "linear", onFinished = row.finished })
    if not handle or handle.noop then row:Hide(); row.finished() end
    return true
end

-- Correlate successful player casts with actual carried-bag conversion. No
-- localized loot parsing, optimistic result, polling, or per-cast timer.
function Mage:CheckComprehensionResult()
    local pending, inventory, now = self.comprehension, self.inventory, Now()
    if not pending then return end
    if not now or now > pending.expires then self.comprehension = nil; return end
    if not (inventory and inventory.available) then return end
    local budget = math.min(pending.succeeded, math.max(0, pending.beforeTotal - inventory.total)) - pending.reported
    if budget > 0 then
        for itemID, count in pairs(inventory.decodedCounts) do
            local gained = math.min(budget, count - (pending.beforeCounts[itemID] or 0) - (pending.reportedCounts[itemID] or 0))
            if gained > 0 then
                local shown, reason = self:ShowReceipt(itemID, gained)
                if shown then
                    pending.reportedCounts[itemID] = (pending.reportedCounts[itemID] or 0) + gained
                    pending.reported, budget = pending.reported + gained, budget - gained
                elseif reason == "item-data" and not pending.requested[itemID] and Item.RequestLoadDataByID then
                    pending.requested[itemID] = true; Item.RequestLoadDataByID(itemID)
                end
                if budget == 0 then break end
            end
        end
    end
    if pending.waiting == 0 and pending.reported >= pending.succeeded then self.comprehension = nil end
end

function Mage:OnComprehensionCast(event, unit, ...)
    if Security.SafeString(unit) ~= "player" then return end
    local sent = event == "UNIT_SPELLCAST_SENT"
    local rawGUID, rawID
    if sent then rawGUID, rawID = select(2, ...) else rawGUID, rawID = ... end
    local castGUID, spellID = Security.SafeString(rawGUID), Number(rawID)
    if spellID ~= Data.comprehendSpellID or not castGUID then return end
    local now = Now()
    if not now then return end
    local pending = self.comprehension
    if pending and now > pending.expires then pending = nil; self.comprehension = nil end
    if sent then
        local record = YAB.BarManager and YAB.BarManager.bars.mageTools
        if not (record and not record.classBarEditing and self.pool.scroll and self.pool.scroll:IsVisible()) then return end
        if not pending then
            self:ReadInventory(); self.inventoryDirty = nil
            local inventory = self.inventory
            if not inventory.available or inventory.total == 0 then return end
            pending = { beforeTotal = inventory.total, beforeCounts = inventory.decodedCounts,
                casts = {}, requested = {}, reportedCounts = {}, waiting = 0, succeeded = 0, reported = 0 }
            self.comprehension = pending
        end
        if pending.casts[castGUID] ~= nil or pending.waiting + pending.succeeded >= 16 then return end
        pending.casts[castGUID], pending.waiting = false, pending.waiting + 1
        pending.expires = now + 8
    elseif pending and pending.casts[castGUID] == false then
        pending.waiting = pending.waiting - 1
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            pending.casts[castGUID], pending.succeeded = true, pending.succeeded + 1
            pending.expires = now + 8
        else pending.casts[castGUID] = nil end
        self:CheckComprehensionResult()
    end
end

function Mage:InitializeDB(db)
    if db.mageToolsVersion == 1 then return end
    local config = db.specialBars and db.specialBars.mageTools
    if config then
        if config.mageArmorLeft == "mage" and config.mageArmorMiddle == "ice" and config.mageArmorRight == "frost" then
            config.mageArmorLeft, config.mageArmorRight = "auto", "mage"
        end
        config.mageArmorMiddle = nil
    end
    db.mageToolsVersion = 1
end

function Mage:ResolveArmor(binding)
    if binding == "auto" or binding == nil then
        return Spell.GetKnownState(Data.armorSpells.ice) == true and Data.armorSpells.ice or Data.armorSpells.frost
    end
    return Data.armorSpells[binding] or Data.armorSpells.frost
end

function Mage:SetMissingGlow(entry, shown)
    shown = shown == true and entry.glowEnabled == true
    if entry.glow and entry.glowShown ~= shown then
        entry.glow:SetGlowShown(shown)
        entry.glowShown = shown
    end
end

-- At most two owned effects. Layout, textures and the selected animation are
-- prepared OOC; aura events only change the requested visibility state.
function Mage:PrepareMissingGlows(record, config)
    local gui = YUI.GUI2
    if not (gui and gui.CreateGlow) then return end
    local params = config.mageMissingBuffGlow or YAB.Defaults.specialBars.mageTools.mageMissingBuffGlow
    if YAB.ConfigSets and YAB.ConfigSets.NormalizeMageGlow then
        params = YAB.ConfigSets:NormalizeMageGlow(params) or YAB.Defaults.specialBars.mageTools.mageMissingBuffGlow
    end
    for _, button in ipairs(record.buttons) do
        local entry = self.states[button]
        if entry.key ~= "scroll" then
            entry.glowEnabled = params.style ~= "none"
            if entry.glowEnabled then
                local options = YAB:CopyValue(params)
                options.hidden, options.restrictedParent, options.skinOwner = true, true, button
                options.trustedWidth, options.trustedHeight = button:GetWidth(), button:GetHeight()
                options.trustedFrameLevel = button:GetFrameLevel() + 6
                options.trustedFrameStrata = button:GetFrameStrata()
                options.shape, options.targetShape = record.configSnapshot.skin, record.configSnapshot.skin
                entry.glow = gui:CreateGlow(button, options)
                -- Prime the selected component's animation while creation is safe.
                if entry.glow then entry.glow:SetGlowShown(true); entry.glow:SetGlowShown(false) end
                entry.glowShown = false
            else self:SetMissingGlow(entry, false) end
        end
    end
end

function Mage:ApplyMissingGlowSettings(config)
    if YAB.Adapter:InCombat() then
        YAB.ClassBars.configDirty.mageTools, YAB.ClassBars.pending = true, true
        return
    end
    local record = YAB.BarManager and YAB.BarManager.bars.mageTools
    if not (record and YAB.ClassBars.active.mageTools) then return end
    self:PrepareMissingGlows(record, config)
    for _, button in ipairs(record.buttons) do
        local entry = self.states[button]
        self:SetMissingGlow(entry, entry.visual.missingBuff)
    end
end

-- Pure selection: the displayed quantity never changes until the next bag snapshot.
function Mage:SelectScrolls(slots, rank, level)
    local result = { eligible = 0, locked = 0, decoded = {}, decodedCounts = {}, rank = rank, total = 0, available = true }
    local seen = {}
    for _, slot in ipairs(slots or {}) do
        local required = Data.untranslated[slot.itemID]
        if required then
            result.total = result.total + slot.count
            if rank and required <= rank then
                result.eligible = result.eligible + slot.count
                if not result.target and not slot.locked then result.target = slot end
            elseif rank then
                result.locked = result.locked + slot.count
                result.minimum = math.min(result.minimum or required, required)
            end
        elseif Data.decoded[slot.itemID] then
            result.decodedCounts[slot.itemID] = (result.decodedCounts[slot.itemID] or 0) + slot.count
            if level and level >= Data.decoded[slot.itemID] and not seen[slot.itemID] then
                seen[slot.itemID] = true
                result.decoded[#result.decoded + 1] = slot.itemID
            end
        end
    end
    return result
end

function Mage:ReadInventory()
    self.powder = Number(Item.GetCount(Data.powderItemID, false, false, false, false)) or 0
    local slots = Item.ReadCarriedSlots and Item.ReadCarriedSlots()
    if not slots then self.inventory = { eligible = 0, locked = 0, decoded = {}, decodedCounts = {}, total = 0, available = false }; return end
    local profession = YUI.API.Profession
    local rank = profession and profession.GetSkillLineRank and profession.GetSkillLineRank(Data.skillLineID)
    local level = Number(Unit.GetPlayerLevel())
    self.inventory = self:SelectScrolls(slots, rank, level)
    self:CheckComprehensionResult()
end

function Mage:GetButtonKeys(config)
    local keys = {}
    if config.mageScroll ~= false then keys[#keys + 1] = "scroll" end
    if config.mageIntellect ~= false then keys[#keys + 1] = "intellect" end
    if config.mageArmor ~= false then keys[#keys + 1] = "armor" end
    return keys
end

function Mage:GetSampleSpellID(position, config)
    local key = self:GetButtonKeys(config)[position]
    return key == "scroll" and Data.comprehendSpellID or key == "intellect" and Data.intellectSpellID
        or key == "armor" and self:ResolveArmor(config.mageArmorLeft)
end

function Mage:ShowTooltip(button)
    local entry = self.states[button]
    if not entry then return end
    local tip, config = GameTooltip, YAB.ClassTools:GetConfig("mageTools")
    tip:SetOwner(button, "ANCHOR_RIGHT")
    if entry.itemID then tip:SetItemByID(entry.itemID); tip:Show(); return end
    tip:AddLine(Text(entry.key), 1, 0.82, 0)
    if entry.key == "scroll" then
        Action(tip, "left", Data.comprehendSpellID)
        tip:AddLine(Text("right") .. ": " .. Texture(Item.GetIcon(213548)) .. " " .. Text("usable_scrolls"), 1, 1, 1)
        local inventory = self.inventory
        if not inventory or not inventory.rank then tip:AddLine(Text("skill_unknown"), 1, 0.2, 0.2)
        else
            tip:AddLine(string.format(Text("eligible"), inventory.eligible), 1, 1, 1)
            if inventory.locked > 0 then
                tip:AddLine(string.format(Text("insufficient"), inventory.locked, inventory.rank, inventory.minimum), 1, 0.2, 0.2)
            end
        end
    elseif entry.key == "intellect" then
        Action(tip, "left", Data.intellectSpellID, true)
        Action(tip, "right", Data.brillianceSpellID, true)
        tip:AddLine(" ")
        local count = self.powder or 0
        tip:AddLine(Texture(Item.GetIcon(Data.powderItemID) or Data.powderIcon) .. " " .. Text("powder") .. ": " .. count
            .. (count == 0 and " " .. Text("missing") or ""), 1, count == 0 and 0.2 or 0.82, count == 0 and 0.2 or 0)
    else
        Action(tip, "left", self.armorLeft or self:ResolveArmor(config.mageArmorLeft), true)
        Action(tip, "right", self.armorRight or self:ResolveArmor(config.mageArmorRight or "mage"), true)
    end
    tip:AddLine(" ")
    tip:AddLine(Text("settings"), 0.2, 1, 0.2)
    tip:Show()
end

local function Enter(button) Mage:ShowTooltip(button) end
local function Leave() GameTooltip:Hide() end
local function Click(button, mouse, down)
    if down or mouse ~= "LeftButton" then return end
    if IsAltKeyDown() then
        YAB.ClassTools.previewClass = "MAGE"
        YAB:OpenSettings(YAB.ClassTools:GetSettingsBarId("mageTools"), "class")
    elseif Mage.states[button].key == "scroll" and not (Mage.inventory and Mage.inventory.target) then
        local inventory = Mage.inventory
        local message = inventory and inventory.locked > 0 and string.format(Text("rank_required"), inventory.rank, inventory.minimum)
            or inventory and inventory.total > 0 and Text("skill_unknown") or Text("no_scrolls")
        UIErrorsFrame:AddMessage(message, 1, 0.2, 0.2)
    end
end

function Mage:Build(record, config)
    local manager, factory = YAB.BarManager, YAB.SecureFactory
    if record.classBarEditing then ScrollHidden() end
    for _, entry in pairs(self.states) do self:SetMissingGlow(entry, false) end
    self.armorLeft, self.armorRight = self:ResolveArmor(config.mageArmorLeft), self:ResolveArmor(config.mageArmorRight or "mage")
    self.inventoryDirty, self.auraDirty = true, true
    self:ReadInventory(); self.inventoryDirty = nil
    record.buttons, record.classButtons = {}, {}
    if not self.panel then self.panel = factory:CreateMageScrollPanel(record.holder) end
    self.panel:Hide()
    for _, key in ipairs({ "scroll", "intellect", "armor" }) do
        local button = self.pool[key]
        if not button then
            button = factory:CreateMageToolButton(record.holder, key, self.panel)
            self.pool[key], self.states[button] = button, { key = key, visual = {} }
            button:SetScript("OnEnter", Enter); button:SetScript("OnLeave", Leave)
            button:HookScript("PostClick", Click)
            if key == "scroll" then button:HookScript("OnHide", ScrollHidden) end
        end
        local entry = self.states[button]
        local id = key == "scroll" and Data.comprehendSpellID or key == "intellect" and Data.intellectSpellID
            or self.armorLeft
        entry.texture = Icon(id) or (key == "scroll" and Data.comprehendIcon)
        local enabled = config["mage" .. key:sub(1, 1):upper() .. key:sub(2)] ~= false
        factory:ConfigureMageTool(button, key, config, self.inventory, record.classBarEditing)
        manager.buttonConfigSnapshots[button] = record.configSnapshot
        if enabled or record.classBarEditing then
            record.buttons[#record.buttons + 1] = button; button:Show()
        else button:Hide() end
    end
    self.auraNames = {}
    for _, id in ipairs({ Data.intellectSpellID, Data.brillianceSpellID }) do
        local name = Name(id); if name then self.auraNames[name] = "intellect" end
    end
    for _, id in pairs(Data.armorSpells) do local name = Name(id); if name then self.auraNames[name] = "armor" end end
    self:BuildChoices(record)
    record.configSnapshot.buttons = math.max(#record.buttons, 1)
    manager:ApplyLayout(record, config, YAB:GetDB())
    self:PrepareMissingGlows(record, config)
    self:PrepareReceipts()
    local snapshot = record.configSnapshot
    YAB.ClassBars:LayoutFlyout(self.panel, self.pool.scroll, self.choices,
        snapshot.size, snapshot.buttonHeight or snapshot.size, snapshot.spacing, snapshot.flyoutDirection, true)
end

function Mage:BuildChoices(record)
    local factory, manager = YAB.SecureFactory, YAB.BarManager
    local count = 0
    for _, itemID in ipairs(self.inventory.decoded) do
        local _, spellID = Item.GetSpell(itemID)
        if Number(spellID) then
            count = count + 1
            local button = self.choices[count]
            if not button then
                button = factory:CreateMageScrollChoice(self.panel, count)
                self.choices[count], self.states[button] = button, { visual = {}, cooldown = {} }
                button:SetScript("OnEnter", Enter); button:SetScript("OnLeave", Leave)
            end
            self.states[button].itemID = itemID
            factory:SetSecureAttribute(button, "type", not record.classBarEditing and "item" or nil)
            factory:SetSecureAttribute(button, "item", "item:" .. itemID)
            manager.buttonConfigSnapshots[button] = record.configSnapshot
            button:SetSize(record.configSnapshot.size, record.configSnapshot.size)
            YAB.Skins:ApplyButton(button, YAB.Skins:Normalize("default"), { size = record.configSnapshot.size, snapshot = record.configSnapshot })
            button:Show()
        elseif Item.RequestLoadDataByID then Item.RequestLoadDataByID(itemID) end
    end
    record.classButtons[1] = self.panel
    for index = 1, count do record.classButtons[#record.classButtons + 1] = self.choices[index] end
    self.panel.choiceCount = count
    YAB.SecureFactory:SetSecureAttribute(self.pool.scroll, "scroll-count", record.classBarEditing and 0 or count)
    for index = count + 1, #self.choices do self.choices[index]:Hide() end
end

function Mage:Refresh(record)
    local inventory = self.inventory or { eligible = 0, decoded = {} }
    if self.inventoryDirty then self:ReadInventory(); inventory = self.inventory; self.inventoryDirty = nil end
    local refreshAuras = self.auraDirty
    if refreshAuras then
        local auras, unavailable
        if Unit.ReadHelpfulTimersByName then
            auras, unavailable = Unit.ReadHelpfulTimersByName("player", self.auraNames or {})
        end
        self.aurasReady = type(auras) == "table"
        self.auras = self.auras or {}
        self.auraUnavailable = unavailable
        for _, key in ipairs(TIMER_KEYS) do
            if self.aurasReady and (auras[key] or not (unavailable and unavailable[key])) then
                self.auras[key] = auras[key]
            end
        end
        self.auraDirty = nil
    end
    for _, button in ipairs(record.buttons) do
        local entry = self.states[button]
        local state, key = entry.visual, entry.key
        local aura = self.auras and self.auras[key]
        local known = self.aurasReady == true and not (self.auraUnavailable and self.auraUnavailable[key])
        state.missingBuff = key ~= "scroll" and known and aura == nil
        state.hasAction, state.texture = true, aura and aura.icon or entry.texture
        state.usable = key ~= "scroll" or inventory.eligible > 0 or #inventory.decoded > 0
        state.count = key == "scroll" and inventory.eligible or nil
        state.countText = key == "scroll" and tostring(inventory.eligible) or ""
        state.cooldownIsStatus = key ~= "scroll"
        if refreshAuras and key ~= "scroll" then
            local durationObject = aura and Unit.GetAuraDurationObject
                and Unit.GetAuraDurationObject("player", aura.auraInstanceID)
            if durationObject then
                state.cooldownDurationObject, state.cooldownEnable = durationObject, true
                state.cooldownDuration = aura.duration
                state.cooldownStart = aura.duration and aura.expirationTime and aura.expirationTime - aura.duration or nil
            elseif aura and aura.duration and aura.expirationTime then
                state.cooldownEnable = aura.duration > 0
                state.cooldownDuration = aura.duration
                state.cooldownStart = aura.expirationTime - aura.duration
            elseif known and not aura then
                state.cooldownEnable, state.cooldownDuration, state.cooldownStart = false, 0, 0
            end
        end
        YAB.Visuals:UpdateButton(button, state, "full")
        if state.cooldownDurationObject then
            state.cooldownDurationObject, state.cooldownDuration, state.cooldownStart = nil, nil, nil
        end
        self:SetMissingGlow(entry, state.missingBuff)
        if GameTooltip:IsOwned(button) then self:ShowTooltip(button) end
    end
    for index = 1, self.panel.choiceCount or 0 do
        local button = self.choices[index]
        local entry = self.states[button]
        local state = entry.visual
        state.hasAction, state.texture = true, Item.GetIcon(entry.itemID)
        state.usable = Security.SafeBoolean(Item.IsUsable(entry.itemID)) == true
        state.count = Number(Item.GetCount(entry.itemID, false, false, false, false))
        state.countText = state.count and state.count > 1 and tostring(state.count) or ""
        local cooldown = Item.ReadItemCooldown(entry.itemID, entry.cooldown)
        state.cooldownStart, state.cooldownDuration = cooldown and cooldown.startTime or 0, cooldown and cooldown.duration or 0
        state.cooldownEnable = cooldown and cooldown.isEnabled == true or false
        YAB.Visuals:UpdateButton(button, state, "full")
    end
end

function Mage:OnEvent(event, ...)
    if YAB.ClassBars.mageCastEvents[event] then self:OnComprehensionCast(event, ...); return end
    local itemID = ...
    if event == "PLAYER_ENTERING_WORLD" then self.comprehension = nil; self:HideReceipts() end
    if event == "GET_ITEM_INFO_RECEIVED" and not (Data.decoded[Number(itemID)] or itemID == Data.powderItemID) then return end
    if event == "UNIT_AURA" or event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_REGEN_ENABLED" then self.auraDirty = true end
    if event == "BAG_UPDATE_DELAYED" or event == "SKILL_LINES_CHANGED" or event == "GET_ITEM_INFO_RECEIVED"
        or event == "SPELLS_CHANGED" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_ENTERING_WORLD" then
        self.inventoryDirty = true
        YAB.ClassBars.configDirty.mageTools = true
    end
end

function Mage:Stop()
    self.comprehension = nil
    self:HideReceipts()
    for _, entry in pairs(self.states) do self:SetMissingGlow(entry, false) end
    if self.panel then
        self.panel:Hide()
        YAB.BarManager.mouseoverRecords[self.panel] = nil
    end
    for button in pairs(self.states) do
        YAB.SecureFactory:ClearMageTool(button)
        button:Hide(); YAB.Visuals:ReleaseButton(button)
        YAB.BarManager.buttonConfigSnapshots[button], YAB.BarManager.mouseoverRecords[button] = nil, nil
        if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    end
    self.inventory, self.auras, self.powder, self.auraNames = nil, nil, nil, nil
    self.aurasReady, self.auraUnavailable, self.armorLeft, self.armorRight = nil, nil, nil, nil
    self.inventoryDirty, self.auraDirty = true, true
end

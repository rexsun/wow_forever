local YUI = _G.YUI
local YBar, Item = YUI.YBar, YUI.API.Item
local L = YUI.Locale:Get("YBar")
local Restore = {}
YBar.TeleportRestore = Restore
local slotsByLocation = {
    INVTYPE_FINGER = {11, 12}, INVTYPE_TRINKET = {13, 14}, INVTYPE_WEAPON = {16, 17},
    INVTYPE_2HWEAPON = {16, 17}, INVTYPE_WEAPONMAINHAND = {16, 17},
    INVTYPE_CLOAK = {15}, INVTYPE_BACK = {15}, INVTYPE_TABARD = {19}, INVTYPE_FEET = {8},
}

function Restore:Cancel()
    self.transaction = nil
    if self.captureTimer then self.captureTimer:Cancel(); self.captureTimer = nil end
    YUI.Event:OffOwner(self)
end

local function FinishCapture()
    Restore.captureTimer = nil
    if Restore.transaction and Restore.transaction.state == "capture" then Restore:Cancel() end
end

function Restore:Capture(itemID)
    if InCombatLockdown() or Item.IsEquipped(itemID) then return end
    self:Cancel()
    local location = Item.GetEquipLoc(itemID)
    local slots = slotsByLocation[location]
    local _, spellID = Item.GetSpell(itemID)
    if not slots or not spellID then return end
    local t = { itemID = itemID, spellID = spellID, location = location, slots = {}, state = "capture", attempts = 0 }
    for _, slot in ipairs(slots) do
        local guid = Item.GetSlotInstance(slot)
        -- Missing GUID on an occupied slot cannot safely be treated as an empty slot.
        if Item.GetInventoryItemID("player", slot) and not guid then return end
        t.slots[slot] = { original = guid or false }
    end
    self.transaction = t
    self.captureTimer = C_Timer.NewTimer(2, FinishCapture)
    for _, event in ipairs({"PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED",
        "CURSOR_CHANGED", "PLAYER_REGEN_ENABLED", "YUI_WORLD_READY"}) do
        YUI.Event:On(event, "OnEvent", self)
    end
    for _, event in ipairs({"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED"}) do
        YUI.Event:On(event, "OnEvent", self, {unit = "player"})
    end
end

function Restore:Observe()
    local t = self.transaction
    if not t or t.executing then return end
    local teleportFound = false
    for slot in pairs(t.slots) do
        if Item.GetInventoryItemID("player", slot) == t.itemID then teleportFound = true end
    end
    if not teleportFound and t.state == "capture" then return end
    for slot, record in pairs(t.slots) do
        local current = Item.GetSlotInstance(slot) or false
        if not record.changed and current ~= record.original then
            local replacedByTeleport = Item.GetInventoryItemID("player", slot) == t.itemID
                or (slot == 17 and current == false and t.location == "INVTYPE_2HWEAPON"
                    and Item.GetInventoryItemID("player", 16) == t.itemID)
            if replacedByTeleport then
                record.changed, record.replacement = true, current
            else
                t.slots[slot] = nil
                t.cancelled = true
            end
        elseif record.changed and current ~= record.replacement and current ~= record.original then
            -- An explicit later equipment choice takes precedence.
            t.slots[slot] = nil
            t.cancelled = true
        end
    end
    if t.state == "capture" then t.state = "equipped" end
end

function Restore:TryRestore()
    local t = self.transaction
    if not t or t.state ~= "ready" or t.executing then return end
    if InCombatLockdown() or GetCursorInfo() then return end
    t.executing = true
    local pending, missing = false, false
    -- Restore the main hand before the off hand when a two-handed item displaced both.
    for slot = 1, 19 do
        local record = t.slots[slot]
        if record and record.changed then
            local current = Item.GetSlotInstance(slot) or false
            if current == record.original then
                t.slots[slot] = nil
            elseif current ~= record.replacement then
                t.slots[slot] = nil
            else
                local ok, reason = Item.RestoreInstance(record.original, slot)
                if ok then
                    t.slots[slot] = nil
                elseif reason == "missing" then
                    missing = true
                    t.slots[slot] = nil
                else
                    pending = true
                end
            end
        end
    end
    t.executing = false
    if missing then YUI:Print(L["restore.missing"]); t.failed = true end
    if not pending then
        if not t.failed and not t.cancelled then YUI:Print(L["restore.complete"]) end
        self:Cancel()
    else
        t.attempts = t.attempts + 1
        if t.attempts >= 8 then YUI:Print(L["restore.failed"]); self:Cancel() end
    end
end

function Restore:OnEvent(event, unit, _, spellID)
    local t = self.transaction
    if not t or t.executing then return end
    if event:find("UNIT_SPELLCAST", 1, true) then
        if unit ~= "player" or spellID ~= t.spellID or t.state == "capture" then return end
        if event == "UNIT_SPELLCAST_START" then t.casting = true; return end
        t.state = "ready"
    elseif event == "YUI_WORLD_READY" then
        if t.casting then t.state = "ready" end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        self:Observe()
    end
    self:TryRestore()
end

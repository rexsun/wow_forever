local YUI = _G.YUI
local B = YUI and YUI.YBags
if not B then return end

local Model = { bags = {}, byUID = {}, totals = {}, waiting = {}, serial = 0, revision = 0 }
B.Model = Model
local metadata = { "name", "quality", "classID", "subClassID", "subType", "equipLoc", "level", "bindType", "system", "quest", "family", "isCraftingReagent", "gearTrade", "gearSet" }
local function Total(item, sign)
    if not item then return end
    local n = (Model.totals[item.itemID] or 0) + item.count * sign
    Model.totals[item.itemID] = n ~= 0 and n or nil
end
function Model:Tag(item)
    local config = B:GetConfig()
    item.section, item.group, item.groupOrder = B.Classification:Classify(item, config, self.compiled)
    B.Stats.classified = B.Stats.classified + 1
end
local function RecentChange(changes,item,delta)
    local change=changes[item.itemID]
    if not change then change={delta=0};changes[item.itemID]=change end
    change.delta=change.delta+delta
    if delta<0 then change.removed=(change.removed or 0)-delta end
    return change
end
function Model:UpdateRecent(changes,allowNew,trackCombatLoot)
    -- Use the native new marker and matched GUIDs first. Net gain is the
    -- fallback bound when a newly marked slot could come from an old pile.
    local changed=false
    local cursor=self.recentCursor
    for _,change in pairs(changes) do
        if change.arrivals then
            local remaining=change.delta
            local combatGain=trackCombatLoot and remaining-(change.grown or 0)
            for _,arrival in ipairs(change.arrivals) do
                local item=arrival.item
                local previous=item.guid and change.departed and change.departed[item.guid]
                if not previous and cursor and item.guid==cursor.guid and item.itemID==cursor.itemID then previous=cursor end
                if previous then
                    item.new=previous.new
                elseif allowNew and arrival.signal then
                    local removed=change.removed or 0
                    -- A new GUID with a larger stack than all observed losses
                    -- cannot have come entirely from those carried stacks.
                    local distinctGain=item.guid and remaining>(change.grown or 0) and item.count>removed
                        and item.count<=remaining+removed-(change.grown or 0)
                    if remaining>=item.count or distinctGain then
                        item.new=true
                        remaining=remaining-item.count
                    end
                end
                if item.new then
                    self:Tag(item)
                    item.revision=item.revision+1
                    changed=true
                end
                -- Scripted loot can lack a native new-item marker. Require
                -- a carried gain that cannot be explained by moving a stack.
                if trackCombatLoot and allowNew and not previous and (item.new or
                    combatGain>=item.count and (item.guid or item.count>(change.removed or 0))) then
                    combatGain=combatGain-item.count
                    self.combatArrivals=self.combatArrivals or setmetatable({}, {__mode="k"})
                    self.combatArrivals[item]=true
                end
            end
        end
    end
    if cursor and not YUI.API.Bags.CursorBusy() then self.recentCursor=nil end
    return changed
end
function Model:ApplyBag(id, incoming, capacity, family, isInitial, kind, recentChanges, space, selectedSlots, changedSlots, trackCombatLoot)
    local bag = self.bags[id]
    local structural, changed, occupiedDelta = false, false, 0
    local chargeSlotsChanged=false
    if not bag then bag = { id=id, slots={}, capacity=0, family=0 }; self.bags[id] = bag; structural=true end
    space=space or YUI.API.Bags.SpaceKey(id,family,kind)
    if bag.capacity ~= capacity or bag.family ~= family or bag.space ~= space then structural=true end
    bag.capacity, bag.family, bag.space = capacity, family, space
    bag.kind=kind or "bags"
    local trackSort=YUI.IsForever and bag.kind=="bags" and space~="keyring"
    local sortChanged=trackSort and structural
    local trackRecent=recentChanges and not isInitial and bag.kind=="bags"
    for index = 1, selectedSlots and #selectedSlots or math.max(capacity, bag.previousCapacity or 0) do
        local slot = selectedSlots and selectedSlots[index] or index
        local old, value = bag.slots[slot], incoming[slot]
        local same = old and value and old.itemID == value.itemID and old.link == value.link and (not old.guid or not value.guid or old.guid==value.guid)
        if same then
            if trackRecent and old.count~=value.count then
                local delta=value.count-old.count
                local change=RecentChange(recentChanges,value,delta)
                if delta>0 then change.grown=(change.grown or 0)+delta end
            end
            -- Keep identity stable for existing views, but distinguish a
            -- remembered GUID from one actually observed in this slot read.
            local guidRetained=old.guid and not value.guid or nil
            old.gearKnown,old.gearRevision=value.gearKnown,value.gearRevision
            if value.guid then old.guid=value.guid end
            old.space=bag.space
            local identityChanged = false
            local bindingChanged=old.bound~=value.bound
            local groupingChanged=bindingChanged or old.maxStack~=value.maxStack or old.charges~=value.charges
                or old.maxCharges~=value.maxCharges or old.chargeConsumable~=value.chargeConsumable or old.chargeSpellID~=value.chargeSpellID
            local loadedChanged=old.loaded~=value.loaded
            for _, key in ipairs(metadata) do if old[key] ~= value[key] then identityChanged = true; break end end
            if old.count ~= value.count or old.locked ~= value.locked or old.bound ~= value.bound or old.questVisual ~= value.questVisual
                or identityChanged or groupingChanged or loadedChanged then
                if trackSort and not sortChanged then
                    sortChanged=old.count~=value.count or old.locked~=value.locked or groupingChanged or loadedChanged
                        or old.quest~=value.quest or old.family~=value.family or old.isCraftingReagent~=value.isCraftingReagent
                        or old.classID~=value.classID or old.equipLoc~=value.equipLoc or old.quality~=value.quality
                end
                if old.chargeSpellID~=value.chargeSpellID then chargeSlotsChanged=true end
                local boeChanged=YUI.IsForever and bindingChanged
                    and B.Classification:IsUnboundEquipment(old)~=B.Classification:IsUnboundEquipment(value)
                Total(old, -1)
                local uid, wasNew, revision, guid = old.uid, old.new, old.revision, old.guid
                local section, group, groupOrder = old.section, old.group, old.groupOrder
                for key in pairs(old) do old[key] = nil end
                for key, field in pairs(value) do old[key] = field end
                old.uid, old.new, old.revision = uid, wasNew, revision + 1
                old.guid=old.guid or guid
                old.bag, old.slot, old.key = id, slot, tostring(id) .. ":" .. slot
                old.space=bag.space
                Total(old, 1)
                if identityChanged or boeChanged then self:Tag(old)
                else old.section, old.group, old.groupOrder = section, group, groupOrder end
                structural = structural or identityChanged or groupingChanged
                changed = true
                if changedSlots then changedSlots[#changedSlots+1]=slot end
            end
            old.guidRetained=guidRetained
        elseif old or value then
            if trackSort then sortChanged=true end
            if trackRecent then
                if old then
                    local change=RecentChange(recentChanges,old,-old.count)
                    if old.guid then
                        change.departed=change.departed or {}
                        change.departed[old.guid]=old
                    end
                end
                if value then
                    local change=RecentChange(recentChanges,value,value.count)
                    if value.new or value.guid or trackCombatLoot then
                        change.arrivals=change.arrivals or {}
                        change.arrivals[#change.arrivals+1]={item=value,signal=value.new==true}
                    end
                end
            end
            if (old and old.chargeSpellID)~=(value and value.chargeSpellID) then chargeSlotsChanged=true end
            if not old then occupiedDelta=occupiedDelta+1
            elseif not value then occupiedDelta=occupiedDelta-1 end
            if old then Total(old, -1); self.byUID[old.uid] = nil end
            bag.slots[slot] = value
            if value then
                self.serial = self.serial + 1
                value.bag, value.slot, value.key = id, slot, tostring(id) .. ":" .. slot
                value.space=bag.space
                value.uid, value.revision = value.key .. ":" .. self.serial, 1
                value.new = false
                self.byUID[value.uid] = value
                Total(value, 1)
                self:Tag(value)
            end
            structural, changed = true, true
            if changedSlots then changedSlots[#changedSlots+1]=slot end
        end
    end
    bag.previousCapacity = capacity
    if changed or structural then self.revision = self.revision + 1 end
    return structural, changed, occupiedDelta, chargeSlotsChanged, sortChanged
end
function Model:Reclassify()
    self.compiled = B.Classification:Compile(B:GetConfig().rules)
    for _, item in pairs(self.byUID) do self:Tag(item) end
end
function Model:List(ids)
    local result, empties = {}, {}
    for _, id in ipairs(ids) do
        local bag = self.bags[id]
        if bag then
            for slot=1,bag.capacity do
                local item=bag.slots[slot]
                if item then result[#result+1]=item
                else empties[#empties+1]={empty=true,bag=id,slot=slot,family=bag.family,space=bag.space or "normal"} end
            end
        end
    end
    return result, empties
end
function Model:Reset()
    self.bags, self.byUID, self.totals, self.waiting = {}, {}, {}, {}
    self.recentCursor=nil
    self.combatArrivals=nil
    self.serial, self.revision = 0, 0
    self.compiled = B.Classification:Compile(B:GetConfig().rules)
end
function Model:Audit()
    local totals, seen = {}, {}
    for _, bag in pairs(self.bags) do
        for slot, item in pairs(bag.slots) do
            if seen[item.uid] or item.slot ~= slot or self.byUID[item.uid] ~= item then return false end
            seen[item.uid] = true
            totals[item.itemID] = (totals[item.itemID] or 0) + item.count
        end
    end
    for id, count in pairs(totals) do if self.totals[id] ~= count then return false end end
    for id, count in pairs(self.totals) do if totals[id] ~= count then return false end end
    return true
end

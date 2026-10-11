local YUI = _G.YUI
if not YUI.IsRetail then return end
local Item = YUI.API.Item

-- Product-loaded adapters: available independently of the CoreEmbed provider.
function Item.GetInstanceGUID(location)
    if not location or not C_Item.DoesItemExist(location) then return nil end
    local guid = C_Item.GetItemGUID(location)
    if issecretvalue and issecretvalue(guid) then return nil end
    return guid
end

function Item.GetSlotInstance(slot)
    return Item.GetInstanceGUID(ItemLocation:CreateFromEquipmentSlot(slot))
end

function Item.FindCarriedInstance(guid)
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if Item.GetInstanceGUID(ItemLocation:CreateFromBagAndSlot(bag, slot)) == guid then
                return bag, slot
            end
        end
    end
end

-- Returns success, or a stable retry/missing reason. Never clears a user's cursor.
function Item.RestoreInstance(guid, target)
    if InCombatLockdown() or GetCursorInfo() or IsInventoryItemLocked(target) then return false, "busy" end
    if guid == false then
        if not Item.GetSlotInstance(target) then return true end
        for bag = 0, NUM_BAG_SLOTS do
            local free, family = C_Container.GetContainerNumFreeSlots(bag)
            if free and free > 0 and family == 0 then
                for slot = 1, C_Container.GetContainerNumSlots(bag) do
                    if not C_Container.GetContainerItemInfo(bag, slot) then
                        PickupInventoryItem(target)
                        C_Container.PickupContainerItem(bag, slot)
                        if GetCursorInfo() then ClearCursor() end
                        return not Item.GetSlotInstance(target), "busy"
                    end
                end
            end
        end
        return false, "busy"
    end
    if Item.GetSlotInstance(target) == guid then return true end
    local bag, slot = Item.FindCarriedInstance(guid)
    if not bag then return false, "missing" end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or info.isLocked then return false, "busy" end
    C_Container.PickupContainerItem(bag, slot)
    PickupInventoryItem(target)
    if GetCursorInfo() then C_Container.PickupContainerItem(bag, slot) end
    if GetCursorInfo() then ClearCursor() end
    return Item.GetSlotInstance(target) == guid, "busy"
end

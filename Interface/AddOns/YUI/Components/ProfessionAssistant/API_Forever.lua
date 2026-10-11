local _, YUI = ...
if not YUI.IsForever then return end
local API = { spellID = 13262 }
YUI.API.ProfessionAssistant = API
local Item = YUI.API.Item
local function ItemGUID(bag, slot)
    local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
    -- GetItemGUID rejects empty locations after disenchanting or moving equipment.
    if not C_Item.DoesItemExist(location) then return nil end
    return C_Item.GetItemGUID(location)
end

function API.Known()
    return C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(API.spellID) == true
end

function API.InCombat()
    return YUI.API.Security.InCombatLockdown()
end

-- Cold scan only while the assistant is visible. Uncached/unknown items fail closed.
function API.Read(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or info.isLocked or not info.hyperlink or (info.stackCount or 1) ~= 1 then return end
    local data = Item.GetInfo(info.hyperlink)
    if not data or not data.name or not data.quality or data.quality < 2 or data.quality > 4 then return end
    if (data.classID ~= 2 and data.classID ~= 4) or not data.equipLoc or data.equipLoc == "" then return end
    local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
    local guid = ItemGUID(bag, slot)
    if not guid then return end
    local tooltip = C_TooltipInfo and C_TooltipInfo.GetBagItem(bag, slot)
    if tooltip and tooltip.lines then
        for _, line in ipairs(tooltip.lines) do
            if ITEM_DISENCHANT_NOT_DISENCHANTABLE and line.leftText == ITEM_DISENCHANT_NOT_DISENCHANTABLE then return end
        end
    end
    local level = C_Item.GetDetailedItemLevelInfo(info.hyperlink) or data.level
    if not level then return end
    return { guid = guid, bag = bag, slot = slot, link = info.hyperlink, name = data.name,
        icon = info.iconFileID, quality = data.quality, level = level,
        boe = data.bindType == 2 and not C_Item.IsBound(location) }
end

function API.Scan()
    local items, byGUID = {}, {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local item = API.Read(bag, slot)
            if item then items[#items + 1], byGUID[item.guid] = item, item end
        end
    end
    return items, byGUID
end

function API.Exists(guid)
    if not guid then return false end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if ItemGUID(bag, slot) == guid then return true end
        end
    end
    return false
end

-- Snapshot quantities before auto-loot clears slots. No predicted loot or bag deltas.
function API.Loot()
    local loot, sources = {}, {}
    for slot = 1, GetNumLootItems() do
        local icon, name, count, _, quality = GetLootSlotInfo(slot)
        local link = GetLootSlotLink(slot)
        local source = { GetLootSourceInfo(slot) }
        for i = 1, #source, 2 do sources[#sources + 1] = source[i] end
        if link then loot[#loot + 1] = { link = link, icon = icon, name = name, count = count, quality = quality } end
    end
    return loot, sources
end

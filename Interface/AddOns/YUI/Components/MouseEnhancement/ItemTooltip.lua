local _, addonTable = ...
local YUI = _G.YUI or addonTable
local Security = YUI and YUI.API and YUI.API.Security
local Item = YUI and YUI.API and YUI.API.Item
if not (YUI and YUI.IsForever == true and YUI.Components and Security and Item) then return end

local L = YUI.Locale and YUI.Locale:Get("MouseEnhancement") or {}
local ItemTooltip = {}
YUI._MouseEnhancementItemTooltip = ItemTooltip

local targets = {
    "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
}
local equipmentSlots = {
    INVTYPE_HEAD = true, INVTYPE_NECK = true, INVTYPE_SHOULDER = true,
    INVTYPE_CHEST = true, INVTYPE_ROBE = true, INVTYPE_WAIST = true,
    INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true,
    INVTYPE_HAND = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true,
    INVTYPE_CLOAK = true, INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true,
}
local records = setmetatable({}, { __mode = "k" })
local enabled, hooksInstalled = false, false
local lineCount, cacheMissCount, failureCount = 0, 0, 0

local function ReadField(object, key)
    if Security.IsSecretValue(object) or type(object) ~= "table" then return nil end
    local ok, value = pcall(function() return object[key] end)
    if not ok or Security.IsSecretValue(value) then return nil end
    return value
end

local function PublicNumber(value)
    if Security.IsSecretValue(value) or type(value) ~= "number" then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function ReadBoolean(tooltip, method)
    local ok, value = Security.SafeMethod("MouseEnhancement:item-tooltip-state", tooltip, method)
    if not ok or Security.IsSecretValue(value) or type(value) ~= "boolean" then return nil end
    return value
end

local function CanUse(tooltip)
    local target = false
    for i = 1, #targets do
        if tooltip == _G[targets[i]] then target = true; break end
    end
    return target and tooltip ~= nil and ReadBoolean(tooltip, "IsForbidden") == false
        and ReadBoolean(tooltip, "IsProtected") == false
end

local function GetProcessingData(tooltip)
    local ok, info = Security.SafeMethod("MouseEnhancement:item-tooltip-data", tooltip, "GetProcessingTooltipInfo")
    return ok and ReadField(info, "tooltipData") or nil
end

local function GetReference(tooltip, data)
    local link = ReadField(data, "hyperlink")
    if type(link) == "string" and link ~= "" then return link end
    local ok, _, itemLink = Security.SafeMethod("MouseEnhancement:item-tooltip-link", tooltip, "GetItem")
    if ok and not Security.IsSecretValue(itemLink) and type(itemLink) == "string" and itemLink ~= "" then
        return itemLink
    end
    local id = PublicNumber(ReadField(data, "id"))
    return id and id > 0 and id or nil
end

local function QualityColor(quality)
    quality = PublicNumber(quality)
    if not quality or quality < 0 or quality > 8 then return "ffffffff" end
    local ok, _, _, _, hex = pcall(Item.GetQualityColor, quality)
    if ok and not Security.IsSecretValue(hex) and type(hex) == "string" and hex:match("^%x%x%x%x%x%x%x%x$") then
        return hex
    end
    return "ffffffff"
end

local function OnItemStart(tooltip, data)
    if not enabled or not CanUse(tooltip) then return end
    if Security.IsSecretValue(data) or type(data) ~= "table" then return end
    local record = records[tooltip]
    if not record then record = {}; records[tooltip] = record end
    record.data, record.inserted = data, false
end

local function OnItemName(tooltip, lineData)
    if not enabled or not CanUse(tooltip) then return end
    local record = records[tooltip]
    if not record or record.inserted or Security.IsSecretValue(lineData) then return end
    local data = GetProcessingData(tooltip)
    local itemType = _G.Enum and _G.Enum.TooltipDataType and _G.Enum.TooltipDataType.Item
    if not data or data ~= record.data or ReadField(data, "type") ~= itemType then return end
    local reference = GetReference(tooltip, data)
    if not reference then return end
    local ok, info = pcall(Item.GetInfo, reference)
    if not ok then failureCount = failureCount + 1; return end
    if not info then cacheMissCount = cacheMissCount + 1; return end
    local equipLoc = ReadField(info, "equipLoc")
    if type(equipLoc) ~= "string" or not equipmentSlots[equipLoc] then return end
    local level = PublicNumber(ReadField(info, "level"))
    if not level or level <= 0 then return end
    local label = L["tooltip.item_level"] or "Item Level"
    local text = string.format("|cffffd200%s|r |c%s%d|r", label, QualityColor(ReadField(info, "quality")), math.floor(level))
    -- The native line post-call runs before binding and stat lines are added.
    if Security.SafeMethod("MouseEnhancement:item-tooltip-line", tooltip, "AddLine", text, 1, 0.82, 0, false) then
        record.inserted = true
        lineCount = lineCount + 1
    else
        failureCount = failureCount + 1
    end
end

local function InstallHooks()
    if hooksInstalled then return true end
    local processor = _G.TooltipDataProcessor
    local types, lineTypes = _G.Enum and _G.Enum.TooltipDataType, _G.Enum and _G.Enum.TooltipDataLineType
    if not (processor and type(processor.AddTooltipPreCall) == "function"
        and type(processor.AddLinePostCall) == "function" and types and types.Item ~= nil
        and lineTypes and lineTypes.ItemName ~= nil) then return false end
    processor.AddTooltipPreCall(types.Item, OnItemStart)
    processor.AddLinePostCall(lineTypes.ItemName, OnItemName)
    hooksInstalled = true
    return true
end

local function RefreshShownItems()
    for i = 1, #targets do
        local tooltip = _G[targets[i]]
        if CanUse(tooltip) and ReadBoolean(tooltip, "IsShown") == true then
            local ok, data = Security.SafeMethod("MouseEnhancement:item-tooltip-current", tooltip, "GetPrimaryTooltipData")
            local itemType = _G.Enum and _G.Enum.TooltipDataType and _G.Enum.TooltipDataType.Item
            if ok and itemType ~= nil and ReadField(data, "type") == itemType then
                if not Security.SafeMethod("MouseEnhancement:item-tooltip-refresh", tooltip, "RebuildFromTooltipInfo") then
                    failureCount = failureCount + 1
                end
            end
        end
    end
end

function ItemTooltip.Configure(db, featureEnabled)
    local nextEnabled = YUI.IsForever == true and featureEnabled == true and db.tooltipItemLevelEnabled ~= false
    if nextEnabled and not InstallHooks() then
        failureCount = failureCount + 1
        return false
    end
    if nextEnabled == enabled then return true end
    enabled = nextEnabled
    RefreshShownItems()
    if not enabled then
        for tooltip in pairs(records) do records[tooltip] = nil end
    end
    return true
end

function ItemTooltip.GetDiagnostics()
    local tooltipCount = 0
    for _ in pairs(records) do tooltipCount = tooltipCount + 1 end
    return {
        enabled = enabled, hooksInstalled = hooksInstalled, tooltipCount = tooltipCount,
        lineCount = lineCount, cacheMissCount = cacheMissCount, failureCount = failureCount,
    }
end

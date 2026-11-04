local _, YUI = ...

YUI.API = YUI.API or {}

local ActionBar = YUI.API.ActionBar or {}
YUI.API.ActionBar = ActionBar

local function IsSecretValue(value)
    local security = YUI.API and YUI.API.Security
    if security and security.IsSecretValue then
        return security.IsSecretValue(value) == true
    end
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == true
end

local function SafeNumber(value)
    if IsSecretValue(value) or value == nil then return nil end
    local ok, numberValue = pcall(tonumber, value)
    if not ok or IsSecretValue(numberValue) then return nil end
    return numberValue
end

local function SafeString(value)
    if IsSecretValue(value) or type(value) ~= "string" then return nil end
    return value
end

-- Cold Forever configuration reads. Slot identities belong to the game, not UI frames.
function ActionBar:GetMultiCastActionSlot(page, slot)
    if not YUI.IsForever or IsSecretValue(page) or IsSecretValue(slot)
        or type(page) ~= "number" or type(slot) ~= "number"
        or page < 1 or page > 3 or page % 1 ~= 0 or slot < 1 or slot > 4 or slot % 1 ~= 0 then return nil end
    local api = _G.C_ActionBar
    if not (api and type(api.GetMultiCastBarIndex) == "function") then return nil end
    local ok, index = pcall(api.GetMultiCastBarIndex)
    if not ok or IsSecretValue(index) or type(index) ~= "number"
        or index < 1 or index % 1 ~= 0 then return nil end
    -- Keep all twelve slots exact within Lua's safe integer range.
    if index > 750599937895082 then return nil end
    return (index - 1) * 12 + (page - 1) * 4 + slot
end

function ActionBar:GetMultiCastSpells(slot, result)
    if IsSecretValue(result) or type(result) ~= "table" then result = {} end
    for key in pairs(result) do result[key] = nil end
    if not YUI.IsForever or IsSecretValue(slot) or type(slot) ~= "number"
        or slot < 1 or slot > 4 or slot % 1 ~= 0 then return result end
    local spell = YUI.API and YUI.API.Spell
    if type(_G.GetMultiCastTotemSpells) ~= "function"
        or not (spell and type(spell.GetKnownState) == "function") then return result end
    local function ReadSpells(ok, ...)
        if not ok then return end
        -- Cold, bounded enumeration; preserve holes without a temporary values table.
        for i = 1, math.min(select("#", ...), 64) do
            local id = select(i, ...)
            if not IsSecretValue(id) and type(id) == "number"
                and id > 0 and id < math.huge and id % 1 == 0 then
                local knownOK, known = pcall(spell.GetKnownState, id)
                if knownOK and not IsSecretValue(known) and known == true then
                    result[#result + 1] = id
                end
            end
        end
    end
    ReadSpells(pcall(_G.GetMultiCastTotemSpells, slot))
    return result
end

local BINDING_MODIFIERS = {
    CTRL = "C",
    ALT = "A",
    SHIFT = "S",
    META = "M",
}

local BINDING_KEYS = {
    MOUSEWHEELUP = "MU",
    MOUSEWHEELDOWN = "MD",
    NUMPADDECIMAL = "N.",
    NUMPADPLUS = "N+",
    NUMPADMINUS = "N-",
    NUMPADMULTIPLY = "N*",
    NUMPADDIVIDE = "N/",
    CAPSLOCK = "Caps",
    PAGEUP = "PU",
    PAGEDOWN = "PD",
    SPACE = "SpB",
    INSERT = "Ins",
    HOME = "Hm",
    DELETE = "Del",
}

local function SplitBindingKey(rawKey)
    local prefix = ""
    local baseKey = rawKey
    while true do
        local modifier = baseKey:match("^(%u+)%-")
        local abbreviation = modifier and BINDING_MODIFIERS[modifier]
        if not abbreviation then break end
        prefix = prefix .. abbreviation
        baseKey = baseKey:sub(#modifier + 2)
    end
    return prefix, baseKey
end

local function FormatKnownBindingKey(baseKey)
    local text = BINDING_KEYS[baseKey]
    if text then return text end

    local button = baseKey:match("^BUTTON(%d+)$")
    if button then return "M" .. button end
    local numpad = baseKey:match("^NUMPAD(%d+)$")
    if numpad then return "N" .. numpad end

    if #baseKey == 1 or baseKey:match("^F%d+$") then
        return baseKey
    end
    return nil
end

local function ClearResult(result)
    result = result or {}
    for key in pairs(result) do
        result[key] = nil
    end
    return result
end

local function ReadActionInfo(slot)
    local modern = _G.C_ActionBar and _G.C_ActionBar.GetActionInfo
    local reader = type(modern) == "function" and modern or _G.GetActionInfo
    if type(reader) ~= "function" then return nil, "api-unavailable" end

    local ok, actionType, actionID, actionSubType = pcall(reader, slot)
    if not ok then return nil, "api-error" end
    if IsSecretValue(actionType)
        or IsSecretValue(actionID)
        or IsSecretValue(actionSubType) then
        return nil, "restricted"
    end
    if actionType == nil then return nil, "empty" end
    actionType = SafeString(actionType)
    if not actionType then return nil, "invalid-action-type" end
    return actionType, actionID, actionSubType
end

local function ReadMacroSpellID(macroIndex)
    if type(_G.GetMacroSpell) ~= "function" then
        return nil, "api-unavailable"
    end
    local ok, first, second, third = pcall(_G.GetMacroSpell, macroIndex)
    if not ok then return nil, "api-error" end
    if IsSecretValue(first) or IsSecretValue(second) or IsSecretValue(third) then
        return nil, "restricted"
    end
    local spellID = SafeNumber(first)
        or SafeNumber(second)
        or SafeNumber(third)
    if not spellID or spellID <= 0 then return nil, "unavailable" end
    return math.floor(spellID), nil
end

local function ResolveMacroIndexByActionText(slot)
    if type(_G.GetActionText) ~= "function"
        or type(_G.GetMacroIndexByName) ~= "function" then
        return nil, "unavailable"
    end
    local okText, macroName = pcall(_G.GetActionText, slot)
    if not okText then return nil, "api-error" end
    if IsSecretValue(macroName) then return nil, "restricted" end
    macroName = SafeString(macroName)
    if not macroName or macroName == "" then return nil, "unavailable" end
    local okIndex, resolvedIndex = pcall(_G.GetMacroIndexByName, macroName)
    if not okIndex then return nil, "api-error" end
    if IsSecretValue(resolvedIndex) then return nil, "restricted" end
    resolvedIndex = SafeNumber(resolvedIndex)
    if not resolvedIndex or resolvedIndex <= 0 then return nil, "unavailable" end
    return math.floor(resolvedIndex), nil
end

local function ResolveMacroIndex(slot, actionID, actionSubType)
    local macroIndex, reason = ResolveMacroIndexByActionText(slot)
    if macroIndex then return macroIndex, nil end
    if reason == "api-error" or reason == "restricted" then
        return nil, reason
    end

    -- Retail may expose the currently effective spell/item ID in actionID
    -- for a typed macro. In that shape actionID must never be treated as a
    -- macro index. Older shapes expose the actual macro index instead.
    if actionSubType == "spell" or actionSubType == "item" then
        return nil, "unavailable"
    end
    macroIndex = SafeNumber(actionID)
    if macroIndex and macroIndex > 0 then
        return math.floor(macroIndex), nil
    end
    return nil, "unavailable"
end

function ActionBar:IsAvailable()
    return type(_G.C_ActionBar and _G.C_ActionBar.GetActionInfo) == "function"
        or type(_G.GetActionInfo) == "function"
end

function ActionBar:GetProfessionQualityAtlas(slot)
    if (YUI.IsForever or YUI.IsRetail) ~= true then return nil end
    slot = SafeNumber(slot)
    if not slot or slot <= 0 then return nil end

    local reader = _G.C_ActionBar and _G.C_ActionBar.GetProfessionQualityInfo
    if type(reader) ~= "function" then return nil end

    local ok, info = pcall(reader, math.floor(slot))
    if not ok or IsSecretValue(info) or type(info) ~= "table" then return nil end
    return SafeString(info.iconInventory)
end

function ActionBar:ReadSlotIdentity(slot, result)
    slot = SafeNumber(slot)
    if not slot or slot <= 0 then return nil, "invalid-slot" end
    slot = math.floor(slot)

    local actionType, actionID, actionSubType = ReadActionInfo(slot)
    if not actionType then return nil, actionID end

    result = ClearResult(result)
    result.slot = slot
    result.actionType = actionType
    result.actionSubType = SafeString(actionSubType)
    result.actionID = SafeNumber(actionID)

    if actionType == "spell" then
        local spellID = SafeNumber(actionID)
        if not spellID or spellID <= 0 then return nil, "invalid-spell" end
        result.spellID = math.floor(spellID)
    elseif actionType == "macro" then
        local macroIndex, macroReason = ResolveMacroIndex(
            slot, actionID, result.actionSubType
        )
        if macroReason == "api-error" or macroReason == "restricted" then
            return nil, macroReason
        end
        result.macroIndex = macroIndex
        if result.actionSubType == "spell" then
            local currentSpellID = SafeNumber(actionID)
            if currentSpellID and currentSpellID > 0 then
                result.currentSpellID = math.floor(currentSpellID)
            end
        elseif result.actionSubType == "item" then
            local currentItemID = SafeNumber(actionID)
            if currentItemID and currentItemID > 0 then
                result.currentItemID = math.floor(currentItemID)
            end
        elseif macroIndex then
            local spellID, spellReason = ReadMacroSpellID(macroIndex)
            if spellReason == "api-error" or spellReason == "restricted" then
                return nil, spellReason
            end
            result.currentSpellID = spellID
        end
    elseif actionType == "item" then
        local itemID = SafeNumber(actionID)
        if itemID and itemID > 0 then result.itemID = math.floor(itemID) end
    end

    return result, nil
end

function ActionBar:IsCursorEmpty()
    if type(_G.GetCursorInfo) ~= "function" then return false, "api-unavailable" end
    local ok, cursorType = pcall(_G.GetCursorInfo)
    if not ok or IsSecretValue(cursorType) then return false, "restricted" end
    return cursorType == nil, cursorType and "cursor-busy" or nil
end

-- Forever regular/bonus player pages end at page 15; special pages start at 16.
-- One cold scan supplies both highest-rank presence and candidate slots.
function ActionBar:ReadPlayerSpellSlots()
    if not YUI.IsForever then return nil, "unsupported-client" end
    local slots, counts = {}, {}
    for slot = 1, 180 do
        local actionType, id = ReadActionInfo(slot)
        if not actionType and id ~= "empty" then return nil, id end
        if actionType == "spell" then
            id = SafeNumber(id)
            if not id then return nil, "restricted" end
            slots[#slots + 1] = { slot = slot, spellID = id }
            counts[id] = (counts[id] or 0) + 1
        end
    end
    return slots, counts
end

-- Never clear a pre-existing cursor. Recheck the source after pickup, and report
-- success only after reading back the requested spell from the destination.
function ActionBar:ReplaceSpellSlot(slot, expectedID, targetID)
    if not YUI.IsForever then return false, "unsupported-client" end
    slot, expectedID, targetID = SafeNumber(slot), SafeNumber(expectedID), SafeNumber(targetID)
    if not slot or not expectedID or not targetID then return false, "invalid-argument" end
    local security = YUI.API and YUI.API.Security
    if not security or security.InCombatLockdown() then return false, "combat-lockdown" end
    if not self:IsCursorEmpty() then return false, "cursor-busy" end
    local spell = YUI.API and YUI.API.Spell
    if not spell or spell.GetKnownState(targetID) ~= true then return false, "unknown-spell" end
    if not (_G.C_Spell and _G.C_Spell.PickupSpell and _G.PlaceAction and _G.ClearCursor) then
        return false, "api-unavailable"
    end
    local actionType, id = ReadActionInfo(slot)
    if actionType ~= "spell" or SafeNumber(id) ~= expectedID then return false, "slot-changed" end
    local picked = security.SafeCall("ActionBar rank pickup", _G.C_Spell.PickupSpell, targetID)
    if not picked then return false, "pickup-failed" end
    local cursorOK, cursorType = pcall(_G.GetCursorInfo)
    if not cursorOK or IsSecretValue(cursorType) then return false, "restricted" end
    if cursorType ~= "spell" then return false, "pickup-failed" end
    actionType, id = ReadActionInfo(slot)
    if security.InCombatLockdown() or actionType ~= "spell" or SafeNumber(id) ~= expectedID then
        security.SafeCall("ActionBar rank cancel pickup", _G.ClearCursor)
        return false, "slot-changed"
    end
    local placed = security.SafeCall("ActionBar rank place", _G.PlaceAction, slot)
    security.SafeCall("ActionBar rank clear pickup", _G.ClearCursor)
    actionType, id = ReadActionInfo(slot)
    if placed and actionType == "spell" and SafeNumber(id) == targetID then return true end
    return false, "placement-unconfirmed"
end

function ActionBar:ReadMacroBody(macroIndex)
    macroIndex = SafeNumber(macroIndex)
    if not macroIndex or macroIndex <= 0 then return nil, "invalid-macro" end
    macroIndex = math.floor(macroIndex)

    if type(_G.GetMacroBody) == "function" then
        local ok, body = pcall(_G.GetMacroBody, macroIndex)
        if not ok then return nil, "api-error" end
        if IsSecretValue(body) then return nil, "restricted" end
        body = SafeString(body)
        if body then return body, nil end
    end

    if type(_G.GetMacroInfo) ~= "function" then
        return nil, "api-unavailable"
    end
    local ok, name, icon, body = pcall(_G.GetMacroInfo, macroIndex)
    if not ok then return nil, "api-error" end
    if IsSecretValue(name) or IsSecretValue(icon) or IsSecretValue(body) then
        return nil, "restricted"
    end
    body = SafeString(body)
    if body then return body, nil end
    return nil, "unavailable"
end

function ActionBar:FormatBindingKey(rawKey)
    rawKey = SafeString(rawKey)
    if not rawKey or rawKey == "" then return nil, "invalid-key" end

    local prefix, baseKey = SplitBindingKey(rawKey)
    if baseKey == "" then return nil, "invalid-key" end
    local known = FormatKnownBindingKey(baseKey)
    if known then return prefix .. known, nil end
    if type(_G.GetBindingText) ~= "function" then
        return prefix .. baseKey, nil
    end

    local ok, text = pcall(_G.GetBindingText, baseKey, 1)
    if not ok then return nil, "api-error" end
    if IsSecretValue(text) then return nil, "restricted" end
    text = SafeString(text)
    if not text or text == "" then text = baseKey end
    return prefix .. text, nil
end

function ActionBar:ReadBinding(command, result)
    command = SafeString(command)
    if not command or command == "" then return nil, "invalid-command" end
    if type(_G.GetBindingKey) ~= "function" then
        return nil, "api-unavailable"
    end

    local ok, primaryKey, secondaryKey = pcall(_G.GetBindingKey, command)
    if not ok then return nil, "api-error" end
    if IsSecretValue(primaryKey) or IsSecretValue(secondaryKey) then
        return nil, "restricted"
    end
    primaryKey = SafeString(primaryKey)
    secondaryKey = SafeString(secondaryKey)
    if not primaryKey and not secondaryKey then return nil, "unbound" end

    result = ClearResult(result)
    result.command = command
    result.primaryKey = primaryKey
    result.secondaryKey = secondaryKey
    if primaryKey then
        local text, reason = self:FormatBindingKey(primaryKey)
        if not text then return nil, reason end
        result.primaryText = text
    end
    if secondaryKey then
        local text, reason = self:FormatBindingKey(secondaryKey)
        if not text then return nil, reason end
        result.secondaryText = text
    end
    return result, nil
end

local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local Manager = YHUD and YHUD.ResourceManager
if not Manager then return end

local function Positive(value)
    if _G.issecretvalue and _G.issecretvalue(value) then return nil end
    local n = tonumber(value)
    return n and n > 0 and n < 2147483647 and n == math.floor(n) and n or nil
end

-- Uses the same entry schema and source adapters as the ordinary picker. No
-- monitor is moved or created when a resource takes a copy of its descriptor.
function Manager:CreateManualEntry(kind, value, secondsText)
    local spellID = Positive(value)
    local api = YUI.API and YUI.API.Spell
    local info = spellID and api and api.GetInfo and api.GetInfo(spellID)
    if not info or not info.name then return nil, "spell-not-found" end
    local entry = { spellId = spellID, name = info.name, icon = info.iconID or info.icon,
        origin = "custom", semantic = "cooldown", sourceType = "spell-cooldown",
        sourceKey = "spell:" .. spellID,
        contract = { capability = "full", view = "self", group = "free", style = "full", fallback = "hide", status = "verified" } }
    if kind == "self-aura" or kind == "target-debuff" then
        local target = kind == "target-debuff"
        entry.sourceType, entry.semantic = YHUD.PLAYER_AURA_SOURCE_TYPE, "buff"
        entry.filteredAuraScope = target and YHUD.FILTERED_AURA_SCOPE_TARGET_HARMFUL
            or YHUD.FILTERED_AURA_SCOPE_PLAYER_HELPFUL
        entry.sourceKey = (target and "aura:target:harmful-player:" or "aura:player:helpful:") .. spellID
        entry.sourceIdentity, entry.spellIds = entry.sourceKey, { spellID }
        entry.contract.capability, entry.contract.view = "aura-display", target and "target" or "self"
    elseif kind == "cast-timer" then
        local seconds = tonumber(secondsText)
        if not seconds or seconds ~= seconds or seconds < 0.1 or seconds > 3600 then
            return nil, "invalid-buff-duration"
        end
        entry.sourceType, entry.semantic = YHUD.CAST_BUFF_TIMER_SOURCE_TYPE, "buff"
        entry.durationSeconds = seconds
        entry.sourceKey = "resource-timer:" .. spellID .. ":" .. seconds
        entry.sourceIdentity = entry.sourceKey
    elseif kind ~= "spell" then return nil, "unsupported-resource-source" end
    entry.entryKey = entry.sourceKey
    return entry
end

function Manager:BuildSelectionEntry(profile, option)
    if option.kind == "official" then
        return YHUD.CDMImport:CreateEntry(option.row, profile.entries[option.entryKey])
    end
    local existing = option.entryKey and profile.entries[option.entryKey]
    if existing then return YHUD:CopyValue(existing) end
    if option.itemID or option.itemIDs then return nil end
    if option.kind ~= "aura-preset" and option.kind ~= "timed-buff"
        and option.kind ~= "spell-event-window" then return nil end
    local entry = {
        entryKey = option.entryKey, sourceKey = option.sourceKey or option.entryKey,
        sourceType = option.sourceType or YHUD.CAST_BUFF_TIMER_SOURCE_TYPE,
        sourceIdentity = option.sourceIdentity, origin = "preset", semantic = "buff",
        spellId = option.spellID, spellIds = YHUD:CopyValue(option.spellIDs),
        triggerSpellIds = YHUD:CopyValue(option.triggerSpellIDs),
        durationSeconds = option.durationSeconds, name = option.name, icon = option.icon,
        presetId = option.presetId, nameKey = option.nameKey,
    }
    return entry
end

function Manager:BuildSelectionOptions(profile, options, family)
    local result, seen = {}, {}
    local function Add(option, entry)
        if not self:Capabilities(entry) then return end
        local identity = entry.entryKey or entry.sourceKey
        if not identity or seen[identity] then return end
        seen[identity] = true
        option.resourceEntry = entry
        -- In another group is information, never an ownership constraint here.
        option.status, option.pickerState, option.unavailable = "add", "add", false
        option.claimedByBundle, option.pickerPresentationValid = nil, true
        result[#result + 1] = option
    end
    for _, option in ipairs(options) do Add(option, self:BuildSelectionEntry(profile, option)) end
    local keys = {}
    for key, entry in pairs(profile.entries or {}) do
        if entry.origin ~= "official-cdm" and (entry.semantic == "buff") == (family == "buff") then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local entry = profile.entries[key]
        Add({ key = "resource:" .. key, entryKey = key, kind = "resource-entry",
            section = "preset", displaySection = "available", name = entry.name,
            icon = entry.icon, spellID = entry.spellId }, YHUD:CopyValue(entry))
    end
    return result
end

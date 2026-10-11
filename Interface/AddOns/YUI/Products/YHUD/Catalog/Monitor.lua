local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local ProfileModel = YHUD.ProfileModel
local CDMImport = YHUD.CDMImport
local CDMCatalog = YHUD.CDMCatalog
local Item = YUI.API and YUI.API.Item
if not (ProfileModel and CDMImport and CDMCatalog) then return end

local MonitorCatalog = {}
YHUD.MonitorCatalog = MonitorCatalog

local ACTIVE_CATEGORIES = {
    essential = true,
    utility = true,
    trackedBuff = true,
    trackedBar = true,
}

local QUICK_RACIAL_FOLDER_KEY = "quick:racials"
local RACIAL_BUNDLE_ENTRY_KEY = "racial:bundle"
local RACIAL_BUNDLE_SOURCE_KEY = "racial:bundle"
local SPELL_BUNDLE_SOURCE_TYPE = "spell-bundle"
local SPELL_EVENT_WINDOW_SOURCE_TYPE = YHUD.SPELL_EVENT_WINDOW_SOURCE_TYPE
    or "yhud.spell-event-window"
local BLOOD_DEATH_KNIGHT_SPEC_KEY = "DEATHKNIGHT:250"
local EQUIPMENT_AURA_BUNDLE_ENTRY_KEY =
    YHUD.EQUIPMENT_AURA_BUNDLE_ENTRY_KEY or "bundle:equipment-auras"
local EQUIPMENT_AURA_BUNDLE_KIND =
    YHUD.EQUIPMENT_AURA_BUNDLE_KIND or "equipmentAura"
local Security = YUI.API and YUI.API.Security
local PRESETS = YHUD.MonitorPresets or {}
local QUICK_ITEM_PRESETS = PRESETS.quickItems or {}
local TIMED_BUFF_SPELL_PRESETS = PRESETS.timedBuffs or {}
local TIER_SET_AURA_PRESETS = PRESETS.tierSetAuras or {}
local QUICK_TIMED_BUFF_PRESETS = PRESETS.timedItems or {}
local DEFENSIVE_SPELLS = PRESETS.defensives or {}
local INTERRUPT_CONTROL_SPELLS = PRESETS.interrupts or {}
local BLOOD_BOIL_WINDOW_PRESET = YHUD.BLOOD_BOIL_WINDOW_PRESET
local RACIAL_PRESETS = YUI.API and YUI.API.Racial and YUI.API.Racial.Presets or {}

local OFFICIAL_ITEM_COOLDOWN_IDENTITIES = {}
for presetIndex = 1, #QUICK_ITEM_PRESETS do
    local preset = QUICK_ITEM_PRESETS[presetIndex]
    local itemIDs = type(preset.itemIDs) == "table"
        and preset.itemIDs or { preset.itemID }
    for itemIndex = 1, #itemIDs do
        local itemID = tonumber(itemIDs[itemIndex])
        if itemID and itemID > 0 then
            OFFICIAL_ITEM_COOLDOWN_IDENTITIES[math.floor(itemID)] = {
                cooldownIDs = preset.officialCooldownIDs,
                spellCategoryIDs = preset.officialSpellCategoryIDs,
                legacySpellIDs = preset.legacyOfficialSpellIDs,
            }
        end
    end
end

local SPELL_BUNDLE_DEFINITIONS = {
    defensive = {
        kind = "defensive",
        optionKey = "quick:defensives",
        entryKey = "bundle:defensive",
        sourceKey = "bundle:defensive",
        nameKey = "designer.quick_defensives",
        fallbackName = "防御技能组",
        spells = DEFENSIVE_SPELLS,
    },
    interruptControl = {
        kind = "interruptControl",
        optionKey = "quick:interrupt-control",
        entryKey = "bundle:interrupt-control",
        sourceKey = "bundle:interrupt-control",
        nameKey = "designer.quick_interrupt_control",
        fallbackName = "断控技能组",
        spells = INTERRUPT_CONTROL_SPELLS,
    },
}

local function IsPositiveInteger(value)
    value = tonumber(value)
    return value
        and value > 0
        and value == math.floor(value)
        and value
        or nil
end

local function IsPublicPositiveInteger(value)
    if Security and Security.IsSecretValue
        and Security.IsSecretValue(value) == true then
        return nil
    end
    return IsPositiveInteger(value)
end

local function T(key, fallback)
    return YHUD:T(key, fallback)
end

local function ResolveSpell(spellID)
    spellID = IsPositiveInteger(spellID)
    local api = YUI.API and YUI.API.Spell
    local info = spellID and api and api.GetInfo and api.GetInfo(spellID)
    return {
        id = spellID,
        name = info and info.name
            or string.format(T("designer.unknown_spell", "法术 %d"), spellID or 0),
        icon = info and (info.iconID or info.originalIconID),
    }
end

local function NormalizeRacialContextKey(value, uppercase)
    if type(value) ~= "string" or value == "" then return nil end
    local token = string.lower(value)
    if token == "haranir" then token = "harronir" end
    return uppercase and string.upper(token) or token
end

function MonitorCatalog:NormalizeRacialContextKey(value)
    return NormalizeRacialContextKey(value, false)
end

local function GetPlayerRaceContext()
    local api = YUI.API and YUI.API.Unit
    local racial = YUI.API and YUI.API.Racial
    local raceToken = racial and racial.GetPlayerRaceToken
        and racial.GetPlayerRaceToken()
        or (api and api.GetRaceToken and api.GetRaceToken("player"))
    if type(raceToken) ~= "string" or raceToken == "" then
        return nil
    end

    local lookupToken = NormalizeRacialContextKey(raceToken, true)
    local presets = RACIAL_PRESETS[lookupToken]
    if not presets then return nil end
    return lookupToken, string.lower(lookupToken), presets
end

local function RacialEntryAllowed(entry, classToken)
    if type(entry) ~= "table" then return true end
    if entry.class and entry.class ~= classToken then return false end
    if entry.notClass and entry.notClass == classToken then return false end
    return true
end

local function IsKnownSpell(spellID)
    local api = YUI.API and YUI.API.Spell
    return api
        and api.IsKnownOrInSpellBook
        and api.IsKnownOrInSpellBook(spellID) == true
end

local function GetRacialMemberSpellID(member)
    return IsPositiveInteger(
        type(member) == "table" and member.spellID or member
    )
end

local function CollectRacialFamilySpellIDs(member)
    local result = {}
    local seen = {}
    local function Add(value)
        value = IsPositiveInteger(value)
        if value and not seen[value] then
            seen[value] = true
            result[#result + 1] = value
        end
    end
    Add(GetRacialMemberSpellID(member))
    if type(member) == "table" then
        for index = 1, #(member.aliases or {}) do
            Add(member.aliases[index])
        end
        for index = 1, #(member.spellIDs or {}) do
            Add(member.spellIDs[index])
        end
    end
    return result
end

local function FindKnownRacialSpellID(member)
    local familySpellIDs = CollectRacialFamilySpellIDs(member)
    for index = 1, #familySpellIDs do
        if IsKnownSpell(familySpellIDs[index]) then
            return familySpellIDs[index]
        end
    end
    return nil
end

local function ResolveRacialRuntimeSpellID(member, knownOnly)
    local spellID = GetRacialMemberSpellID(member)
    if not spellID then return nil end
    if knownOnly then
        return FindKnownRacialSpellID(member) or spellID
    end
    return spellID
end

local function FindRacialMember(presets, spellID)
    spellID = IsPositiveInteger(spellID)
    if not spellID then return nil end
    for index = 1, #(presets or {}) do
        local member = presets[index]
        local familySpellIDs = CollectRacialFamilySpellIDs(member)
        for familyIndex = 1, #familySpellIDs do
            if familySpellIDs[familyIndex] == spellID then
                return member
            end
        end
    end
    return nil
end

local function CurrentPlayerClassToken()
    local unitApi = YUI.API and YUI.API.Unit
    local classToken = unitApi and unitApi.GetClassToken
        and unitApi.GetClassToken("player")
    return type(classToken) == "string" and string.upper(classToken) or nil
end

function MonitorCatalog:GetPlayerRacialPreviewIcon()
    local _, _, presets = GetPlayerRaceContext()
    local classToken = CurrentPlayerClassToken()
    for index = 1, #(presets or {}) do
        local member = presets[index]
        if RacialEntryAllowed(member, classToken) then
            local spellID = FindKnownRacialSpellID(member)
            if spellID then
                return ResolveSpell(spellID).icon or 134400
            end
        end
    end
    return 134400
end

local function CollectRacialSpells(raceContextKey)
    local _, currentRaceToken = GetPlayerRaceContext()
    raceContextKey = NormalizeRacialContextKey(raceContextKey, false)
        or currentRaceToken
    local presets = raceContextKey
        and RACIAL_PRESETS[string.upper(raceContextKey)] or nil
    if not presets then return nil, {} end

    local classToken = CurrentPlayerClassToken()
    local result = {}
    local seen = {}
    local function AddSpell(spellID)
        if spellID and not seen[spellID] then
            seen[spellID] = true
            result[#result + 1] = spellID
            return true
        end
        return false
    end
    for index = 1, #presets do
        local entry = presets[index]
        if RacialEntryAllowed(entry, classToken) then
            AddSpell(GetRacialMemberSpellID(entry))
        end
    end
    return raceContextKey, result
end

local function CollectPlayerRacialSpells()
    return CollectRacialSpells(nil)
end

local function GetSpecContext(profile, requestedSpecKey)
    local specKey = requestedSpecKey
    if not YHUD:IsStableSpecKey(specKey) then
        specKey = type(profile) == "table"
        and rawget(profile, "_yhudSpecKey") or nil
    end
    if not YHUD:IsStableSpecKey(specKey) then
        specKey = YHUD:GetCurrentSpecKey()
    end
    if not YHUD:IsStableSpecKey(specKey) then return nil end
    local classToken, specID = specKey:match("^([^:]+):(%d+)$")
    specID = IsPositiveInteger(specID)
    if not classToken or not specID then return nil end
    return string.upper(classToken), specID, specKey
end

local function GetBundleMemberSpellID(member)
    return IsPositiveInteger(
        type(member) == "table" and member.spellID or member
    )
end

local function CollectBundleFamilySpellIDs(member, specID, knownOnly)
    local result = {}
    local seen = {}
    local function Add(value)
        value = IsPositiveInteger(value)
        if value and not seen[value] then
            seen[value] = true
            result[#result + 1] = value
        end
    end
    local spellID = GetBundleMemberSpellID(member)
    Add(spellID)
    if type(member) == "table" then
        for index = 1, #(type(member.aliases) == "table"
            and member.aliases or {}) do
            Add(member.aliases[index])
        end
    end
    local api = YUI.API and YUI.API.Spell
    if spellID and api and api.GetOverrideSpellID then
        Add(api.GetOverrideSpellID(spellID, specID, knownOnly))
    end
    return result
end

local function ResolveBundleRuntimeSpellID(member, specID, knownOnly)
    local spellID = GetBundleMemberSpellID(member)
    local api = YUI.API and YUI.API.Spell
    local overrideSpellID = spellID and api and api.GetOverrideSpellID
        and api.GetOverrideSpellID(spellID, specID, knownOnly) or spellID
    if overrideSpellID and overrideSpellID ~= spellID then
        return overrideSpellID
    end
    if knownOnly and type(member) == "table" then
        for index = 1, #(type(member.aliases) == "table"
            and member.aliases or {}) do
            local alias = IsPositiveInteger(member.aliases[index])
            if alias and IsKnownSpell(alias) then return alias end
        end
    end
    return spellID
end

local function AppendSpellIDs(
    target,
    seen,
    spellIDs,
    knownOnly,
    specID
)
    for index = 1, #(type(spellIDs) == "table" and spellIDs or {}) do
        local member = spellIDs[index]
        local spellID = GetBundleMemberSpellID(member)
        local runtimeSpellID = ResolveBundleRuntimeSpellID(
            member,
            specID,
            knownOnly
        )
        local known = not knownOnly
            or IsKnownSpell(runtimeSpellID)
            or IsKnownSpell(spellID)
        if spellID and not seen[spellID]
            and known then
            seen[spellID] = true
            target[#target + 1] = spellID
        end
    end
end

local function ApplySavedSpellOrder(spellIDs, savedOrder)
    if type(savedOrder) ~= "table" or #spellIDs < 2 then
        return spellIDs
    end
    local allowed = {}
    for index = 1, #spellIDs do allowed[spellIDs[index]] = true end
    local ordered = {}
    local added = {}
    for index = 1, #savedOrder do
        local spellID = IsPositiveInteger(savedOrder[index])
        if spellID and allowed[spellID] and not added[spellID] then
            added[spellID] = true
            ordered[#ordered + 1] = spellID
        end
    end
    for index = 1, #spellIDs do
        local spellID = spellIDs[index]
        if not added[spellID] then
            added[spellID] = true
            ordered[#ordered + 1] = spellID
        end
    end
    return ordered
end

local function ReadContextData(entry, field, contextKey, legacyField)
    local saved = entry and entry[field]
    local value = type(saved) == "table" and saved[contextKey] or nil
    if value == nil and legacyField then value = entry and entry[legacyField] end
    return value
end

local function MigrateContextData(entry, field, contextKey, legacyField)
    local saved = entry and entry[field]
    if type(saved) ~= "table" then
        saved = {}
        entry[field] = saved
    end
    if saved[contextKey] == nil and legacyField
        and entry[legacyField] ~= nil then
        saved[contextKey] = entry[legacyField]
    end
    if legacyField then entry[legacyField] = nil end
    return saved
end

local function CollectPlayerBundleSpells(profile, bundleKind, requestedSpecKey)
    local definition = SPELL_BUNDLE_DEFINITIONS[bundleKind]
    local classToken, specID, specKey = GetSpecContext(profile, requestedSpecKey)
    local classData = definition and classToken
        and definition.spells[classToken]
    if not classData then return {} end
    local knownOnly = specKey == YHUD:GetCurrentSpecKey()
    local result = {}
    local seen = {}
    AppendSpellIDs(result, seen, classData.class, knownOnly, specID)
    AppendSpellIDs(result, seen, classData[specID], knownOnly, specID)
    local entry = type(profile) == "table"
        and type(profile.entries) == "table"
        and profile.entries[definition.entryKey] or nil
    local legacyOrderField = type(profile) == "table"
        and specKey == rawget(profile, "_yhudSpecKey")
        and "bundleOrder" or nil
    local savedOrder = specKey and ReadContextData(
        entry,
        "bundleOrderByContext",
        specKey,
        legacyOrderField
    ) or nil
    return ApplySavedSpellOrder(result, savedOrder)
end

local function FindBundleMember(definition, classToken, specID, spellID)
    local classData = definition and definition.spells[classToken]
    if not classData then return nil end
    for _, members in ipairs({ classData.class, classData[specID] }) do
        for index = 1, #(type(members) == "table" and members or {}) do
            local member = members[index]
            if GetBundleMemberSpellID(member) == spellID then
                return member
            end
        end
    end
    return spellID
end

local function GetRacialContextKeys(profile, requestedRaceToken)
    local _, currentRaceToken = GetPlayerRaceContext()
    local raceToken = NormalizeRacialContextKey(requestedRaceToken, false)
        or currentRaceToken
    if not raceToken then return nil end
    local specKey = type(profile) == "table"
        and rawget(profile, "_yhudSpecKey") or nil
    if not YHUD:IsStableSpecKey(specKey) then
        specKey = YHUD:GetCurrentSpecKey()
    end
    local contextKey = YHUD:IsStableSpecKey(specKey)
        and (raceToken .. "@" .. specKey) or raceToken
    local classToken = CurrentPlayerClassToken()
    local legacyClassKey
    if type(classToken) == "string" and classToken ~= "" then
        legacyClassKey = raceToken .. ":" .. string.lower(classToken)
    end
    return raceToken, contextKey, raceToken, legacyClassKey
end

local function GetLegacyRacialAliasKeys(
    raceToken,
    contextKey,
    legacyClassKey
)
    if raceToken ~= "harronir" then return nil, nil, nil end
    local specSuffix = contextKey and contextKey:match("^harronir(@.+)$")
    local classSuffix = legacyClassKey
        and legacyClassKey:match("^harronir(:.+)$") or nil
    return specSuffix and ("haranir" .. specSuffix) or nil,
        "haranir",
        classSuffix and ("haranir" .. classSuffix) or nil
end

local function ReadRacialContextData(
    entry,
    field,
    raceToken,
    contextKey,
    legacyRaceKey,
    legacyClassKey
)
    local saved = entry and entry[field]
    if type(saved) ~= "table" then return nil end
    local value = saved[contextKey]
    if value == nil and legacyRaceKey then
        value = saved[legacyRaceKey]
    end
    if value == nil and legacyClassKey then
        value = saved[legacyClassKey]
    end
    local aliasContextKey, aliasRaceKey, aliasClassKey =
        GetLegacyRacialAliasKeys(
            raceToken,
            contextKey,
            legacyClassKey
        )
    if value == nil and aliasContextKey then
        value = saved[aliasContextKey]
    end
    if value == nil and aliasRaceKey then value = saved[aliasRaceKey] end
    if value == nil and aliasClassKey then value = saved[aliasClassKey] end
    return value
end

local function MigrateRacialContextData(
    entry,
    field,
    raceToken,
    contextKey,
    legacyRaceKey,
    legacyClassKey
)
    local saved = entry and entry[field]
    if type(saved) ~= "table" then return saved end
    if saved[contextKey] == nil then
        local inherited = ReadRacialContextData(
            entry,
            field,
            raceToken,
            contextKey,
            legacyRaceKey,
            legacyClassKey
        )
        if inherited ~= nil then
            saved[contextKey] = YHUD:CopyValue(inherited)
        end
    end
    return saved
end

local function GetRacialPresetsForContext(contextKey)
    contextKey = NormalizeRacialContextKey(contextKey, false)
    return contextKey and RACIAL_PRESETS[string.upper(contextKey)] or nil
end

local function CanonicalizeRacialSpellID(contextKey, spellID)
    spellID = IsPositiveInteger(spellID)
    local member = spellID and FindRacialMember(
        GetRacialPresetsForContext(contextKey),
        spellID
    ) or nil
    return member and GetRacialMemberSpellID(member) or nil, member
end

local function CanonicalizeRacialSavedOrder(contextKey, savedOrder)
    if type(savedOrder) ~= "table" then return savedOrder end
    local result = {}
    local seen = {}
    for index = 1, #savedOrder do
        local canonical = CanonicalizeRacialSpellID(
            contextKey,
            savedOrder[index]
        )
        if canonical and not seen[canonical] then
            seen[canonical] = true
            result[#result + 1] = canonical
        end
    end
    return result
end

local function ReadStoredRacialChoice(choices, spellID)
    if type(choices) ~= "table" or not spellID then return nil end
    local value = choices[tostring(spellID)]
    if value == nil then value = choices[spellID] end
    return value
end

local function ReadRacialFamilyChoice(choices, member)
    if type(choices) ~= "table" then return true end
    local canonical = GetRacialMemberSpellID(member)
    local canonicalValue = ReadStoredRacialChoice(choices, canonical)
    if canonicalValue ~= nil then return canonicalValue ~= false end
    local familySpellIDs = CollectRacialFamilySpellIDs(member)
    for index = 1, #familySpellIDs do
        local value = ReadStoredRacialChoice(choices, familySpellIDs[index])
        if value == false then return false end
    end
    return true
end

local function MigrateRacialChoiceTable(contextKey, choices)
    if type(choices) ~= "table" then return choices end
    local presets = GetRacialPresetsForContext(contextKey)
    for index = 1, #(presets or {}) do
        local member = presets[index]
        local canonical = GetRacialMemberSpellID(member)
        local canonicalKey = canonical and tostring(canonical)
        local familySpellIDs = CollectRacialFamilySpellIDs(member)
        local canonicalValue = ReadStoredRacialChoice(choices, canonical)
        if canonicalKey and canonicalValue == nil then
            local migrated
            for familyIndex = 1, #familySpellIDs do
                local value = ReadStoredRacialChoice(
                    choices,
                    familySpellIDs[familyIndex]
                )
                if value == false then
                    migrated = false
                    break
                elseif value == true then
                    migrated = true
                end
            end
            if migrated ~= nil then choices[canonicalKey] = migrated end
        elseif canonicalKey and choices[canonicalKey] == nil then
            choices[canonicalKey] = canonicalValue
        end
        if canonical then choices[canonical] = nil end
        for familyIndex = 1, #familySpellIDs do
            local familySpellID = familySpellIDs[familyIndex]
            if familySpellID ~= canonical then
                choices[tostring(familySpellID)] = nil
                choices[familySpellID] = nil
            end
        end
    end
    return choices
end

local function BuildSpellBundleEntry(definition, representative)
    return {
        entryKey = definition.entryKey,
        sourceKey = definition.sourceKey,
        sourceType = SPELL_BUNDLE_SOURCE_TYPE,
        bundleKind = definition.kind,
        bundleEnabled = true,
        semantic = "cooldown",
        origin = "preset",
        contentScope = YHUD.CONTENT_SCOPE_SPEC,
        presetKey = definition.entryKey,
        crossSpecMaterialization = "immediate",
        name = T(definition.nameKey, definition.fallbackName),
        icon = representative and representative.icon,
        contract = {
            capability = "full",
            view = "self",
            group = "free",
            style = "full",
            fallback = "hide",
            status = "verified",
        },
    }
end

local function BuildEquipmentAuraBundleEntry()
    return {
        entryKey = EQUIPMENT_AURA_BUNDLE_ENTRY_KEY,
        sourceKey = EQUIPMENT_AURA_BUNDLE_ENTRY_KEY,
        sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE or "yhud.player-aura",
        bundleKind = EQUIPMENT_AURA_BUNDLE_KIND,
        bundleEnabled = true,
        semantic = "buff",
        origin = "preset",
        contentScope = YHUD.CONTENT_SCOPE_SPEC,
        presetKey = EQUIPMENT_AURA_BUNDLE_ENTRY_KEY,
        crossSpecMaterialization = "deferred",
        compatibleViews = {
            icon = true,
            bar = true,
            ring = true,
        },
        nameKey = "designer.quick_equipment_auras",
        icon = 2103819,
        contract = {
            capability = "native-enhanced",
            view = "self",
            group = "free",
            style = "full",
            fallback = "hide",
            status = "verified",
        },
    }
end

local function StoreRacialSignatureSpell(signature, count, changed, spellID)
    count = count + 1
    if signature[count] ~= spellID then
        signature[count] = spellID
        changed = true
    end
    return count, changed
end

function MonitorCatalog:UpdatePlayerRacialSignature(signature)
    if type(signature) ~= "table" then
        return nil, "invalid-signature"
    end
    local cachedRaceToken = signature.raceToken
    local cachedClassToken = signature.classToken
    local raceToken = NormalizeRacialContextKey(cachedRaceToken, true)
    local presets = raceToken and RACIAL_PRESETS[raceToken]
    if not presets then
        raceToken, _, presets = GetPlayerRaceContext()
    end
    if not presets then return nil end

    local classToken = type(cachedClassToken) == "string"
        and cachedClassToken or nil
    if not classToken then
        local unitApi = YUI.API and YUI.API.Unit
        classToken = unitApi and unitApi.GetClassToken
            and unitApi.GetClassToken("player")
    end
    if type(classToken) ~= "string" or classToken == "" then
        return nil
    end

    local previousCount = tonumber(signature.count) or 0
    local count = 0
    local changed = signature.raceToken ~= raceToken
        or signature.classToken ~= classToken
    for index = 1, #presets do
        local entry = presets[index]
        if RacialEntryAllowed(entry, classToken) then
            local selectedSpellID = FindKnownRacialSpellID(entry)
            if selectedSpellID then
                count, changed = StoreRacialSignatureSpell(
                    signature,
                    count,
                    changed,
                    selectedSpellID
                )
            end
        end
    end
    for index = count + 1, previousCount do
        signature[index] = nil
        changed = true
    end
    if previousCount ~= count then changed = true end
    signature.raceToken = raceToken
    signature.classToken = classToken
    signature.count = count
    return raceToken, classToken, count, changed
end

local function BuildRacialBundleEntry(representative)
    return {
        entryKey = RACIAL_BUNDLE_ENTRY_KEY,
        sourceKey = RACIAL_BUNDLE_SOURCE_KEY,
        sourceType = "racial-bundle",
        bundleKind = "racial",
        bundleEnabled = true,
        semantic = "cooldown",
        origin = "preset",
        contentScope = YHUD.CONTENT_SCOPE_SPEC,
        presetKey = RACIAL_BUNDLE_ENTRY_KEY,
        crossSpecMaterialization = "deferred",
        name = T("designer.quick_racials", "种族技能组"),
        icon = representative and representative.icon,
        contract = {
            capability = "full",
            view = "self",
            group = "free",
            style = "full",
            fallback = "hide",
            status = "verified",
        },
    }
end

local function IsPlayerRacialSpell(spellID)
    local raceToken, spellIDs = CollectPlayerRacialSpells()
    for index = 1, #spellIDs do
        if spellIDs[index] == spellID then
            return true, raceToken
        end
    end
    return false, raceToken
end

local function ResolveSlot(slotID)
    local api = YUI.API and YUI.API.Item
    local itemID = api and api.GetInventoryItemID
        and api.GetInventoryItemID("player", slotID)
    local name = itemID and api.GetName and api.GetName(itemID)
    local icon = api and api.GetInventoryItemTexture
        and api.GetInventoryItemTexture("player", slotID)
    if not icon and itemID and api and api.GetIcon then
        icon = api.GetIcon(itemID)
    end
    return {
        id = itemID,
        name = string.format(
            T("designer.slot_name", "饰品栏 %d"),
            slotID
        ),
        itemName = name,
        icon = icon,
    }
end

local function ResolveItem(itemID, knownPreset, fallbackName)
    itemID = IsPositiveInteger(itemID)
    local api = YUI.API and YUI.API.Item
    local name = itemID and api and api.GetNameByID
        and api.GetNameByID(itemID)
    if not name and itemID and api and api.GetName then
        name = api.GetName(itemID)
    end
    local icon = itemID and api and api.GetIcon
        and api.GetIcon(itemID)
    local resolvedID
    if itemID and api and api.GetInfoInstant then
        local instantID, _, _, _, instantIcon = api.GetInfoInstant(itemID)
        resolvedID = IsPositiveInteger(instantID)
        if not icon then icon = instantIcon end
    end
    if itemID and not name and api and api.RequestLoadDataByID then
        api.RequestLoadDataByID(itemID)
    end
    return {
        id = itemID,
        name = name
            or fallbackName
            or string.format(
                T("designer.unknown_item", "物品 %d"),
                itemID or 0
            ),
        icon = icon,
        found = knownPreset == true
            or resolvedID == itemID
            or name ~= nil
            or icon ~= nil,
    }
end

local function FindMonitor(profile, entryKey, targetGroupId)
    local groups = profile.groups
    local order = groups and groups.order or {}
    local items = groups and groups.items or {}
    local monitors = profile.monitors or {}
    local first

    for groupIndex = 1, #order do
        local groupId = order[groupIndex]
        local group = items[groupId]
        local monitorIds = group and group.monitors or {}
        for monitorIndex = 1, #monitorIds do
            local monitor = monitors[monitorIds[monitorIndex]]
            if monitor and monitor.entryKey == entryKey then
                if monitor.groupId == targetGroupId then
                    return monitor, true
                end
                if not first then first = monitor end
            end
        end
    end
    return first, false
end

local function FindActiveMonitor(profile, entryKey)
    local monitor = FindMonitor(profile, entryKey)
    local group = monitor
        and profile.groups
        and profile.groups.items
        and profile.groups.items[monitor.groupId]
    if not monitor
        or monitor.enabled == false
        or not group
        or group.enabled ~= true then
        return nil
    end
    return monitor
end

local function ResolveStatus(profile, groupId, entryKey, view, supported)
    local monitor, current = FindMonitor(profile, entryKey, groupId)
    if not supported then return "unsupported", monitor end
    local placed = ProfileModel:CanPlace(profile, entryKey, groupId, view)
    if not placed then return "incompatible", monitor end
    if current then return "current", monitor end
    if monitor then return "move", monitor end
    return "add", nil
end

local function GetTargetView(profile, groupId)
    local group = profile.groups and profile.groups.items
        and profile.groups.items[groupId]
    return group and ProfileModel:GetDefaultView(group.layout) or nil
end

local function ResolveOfficialPresentationName(kind)
    if kind == "healthstone" then
        return T("designer.cdm.healthstone", "治疗石")
    end
    if kind == "combatPotion" then
        return T("designer.cdm.combat_potion", "战斗药水")
    end
    if kind == "healthPotion" then
        return T("designer.cdm.health_potion", "生命药水")
    end
    return nil
end

local function BuildOfficialOption(profile, groupId, row)
    local category = row.category
    local entryKey = "cdm:" .. tostring(row.cooldownID)
    local entry = profile.entries[entryKey]
    local spellID = entry and (entry.overrideSpellId or entry.spellId)
        or row.overrideSpellID
        or row.spellID
    local spell = ResolveSpell(spellID)
    local presentationName = ResolveOfficialPresentationName(
        row.presentationKind
    )
    local pickerPresentationValid = spell.id ~= nil
        or (entry and type(entry.name) == "string" and entry.name ~= "")
        or (entry and entry.icon ~= nil)
        or presentationName ~= nil
        or row.presentationIcon ~= nil
    local contract = entry and entry.contract or {}
    local nativeVisible = row.nativeVisible ~= false
    local supported = nativeVisible
        and ACTIVE_CATEGORIES[category] == true
        and entry ~= nil
        and (entry.sourceKey ~= nil
            or contract.capability == "native-enhanced"
            or contract.view == "native")
    local view = GetTargetView(profile, groupId)
    local status, monitor =
        ResolveStatus(profile, groupId, entryKey, view, supported)

    local isKnown = row.isKnown ~= false
        and (not entry or entry.isKnown ~= false)
    local displaySection
    local pickerState
    if not isKnown then
        displaySection = "unlearned"
        pickerState = "unavailable"
    elseif not nativeVisible then
        displaySection = "native-hidden"
        pickerState = "native-disabled"
    else
        displaySection = "available"
        pickerState = (status == "unsupported" or status == "incompatible")
            and "unavailable" or status
    end

    return {
        key = "official:" .. entryKey,
        section = "official",
        kind = "official",
        category = category,
        row = YHUD:CopyValue(row),
        entryKey = entryKey,
        sourceKey = entry and entry.sourceKey,
        claimedSourceKey = entryKey,
        claimedFallbackSourceKey = row.spellCategoryID
            and ("spell-category:" .. tostring(row.spellCategoryID))
            or (row.equipSlot
                and ("slot:" .. tostring(row.equipSlot))
                or (spellID and ("spell:" .. tostring(spellID)) or nil)),
        name = entry and entry.name
            or presentationName
            or spell.name,
        icon = entry and entry.icon
            or row.presentationIcon
            or spell.icon,
        view = view,
        status = status,
        displaySection = displaySection,
        pickerState = pickerState,
        nativeVisibility = nativeVisible and "shown" or "hidden",
        pickerPresentationValid = pickerPresentationValid,
        unavailable = not isKnown or not nativeVisible,
        monitorId = monitor and monitor.id,
        fromGroupId = monitor and monitor.groupId,
    }
end

local function IsOfficialRowForFamily(row, semanticFamily)
    if type(row) ~= "table" or not IsPositiveInteger(row.cooldownID) then
        return false
    end
    local category = ACTIVE_CATEGORIES[row.category] and row.category
        or row.sourceCategory
    if semanticFamily == "buff" then
        return category == "trackedBuff" or category == "trackedBar"
            or category == "equipSlotTracked"
            or category == "specAgnosticTracked"
    end
    return category == "essential" or category == "utility"
        or category == "equipSlotEssential"
        or category == "specAgnosticEssential"
end

local function IsOfficialRowNativeVisible(row)
    if row.nativeVisible ~= nil then return row.nativeVisible == true end
    return type(row.category) == "string" and row.metadataOnly ~= true
end

local function DecoratePickerOption(option)
    if type(option) ~= "table" then return option end
    if option.kind == "official" then
        if option.status == "claimed" then
            option.pickerState = "preset-management"
        elseif option.displaySection == "available" then
            option.pickerState = (option.status == "unsupported"
                or option.status == "incompatible")
                and "unavailable" or option.status
        end
        return option
    end
    option.displaySection = "preset"
    option.nativeVisibility = "not-applicable"
    if option.status == "claimed" then
        option.pickerState = "preset-management"
    elseif option.status == "unsupported" or option.status == "incompatible"
        or option.unavailable == true then
        option.pickerState = "unavailable"
    else
        option.pickerState = option.status or "add"
    end
    return option
end

local function BuildSlotOption(profile, groupId, slotID)
    local entryKey = "slot:" .. tostring(slotID)
    local slot = ResolveSlot(slotID)
    local view = GetTargetView(profile, groupId)
    local status, monitor =
        ResolveStatus(profile, groupId, entryKey, view, true)
    return {
        key = "quick:" .. entryKey,
        section = "quick",
        kind = "slot",
        entryKey = entryKey,
        sourceKey = entryKey,
        slotID = slotID,
        itemID = slot.id,
        name = slot.name,
        icon = slot.icon,
        view = view,
        status = status,
        monitorId = monitor and monitor.id,
        fromGroupId = monitor and monitor.groupId,
    }
end

local function BuildAmmoOption(profile, groupId, specKey)
    local ammo = YHUD.Ammo
    if not (ammo and ammo:IsSupported(specKey)) then return nil end
    local statusProfile = profile
    if not profile.entries[ammo.ENTRY_KEY] then
        local draft = ProfileModel:BeginDraft(profile, { specKey = specKey })
        if not draft then return nil end
        local entry = ProfileModel:AddEntry(draft, ammo.ENTRY_KEY, ammo:BuildEntry())
        if not entry then return nil end
        statusProfile = draft.profile
    end
    local view = GetTargetView(statusProfile, groupId)
    local status, monitor = ResolveStatus(statusProfile, groupId, ammo.ENTRY_KEY, view, true)
    return {
        key = "quick:ammo", section = "quick", kind = "ammo",
        entryKey = ammo.ENTRY_KEY, sourceKey = ammo.ENTRY_KEY,
        name = T("designer.quick.ammo", "弹药数量"), icon = ammo:GetPreviewIcon(),
        origin = "preset", view = view, status = status,
        monitorId = monitor and monitor.id, fromGroupId = monitor and monitor.groupId,
    }
end

local function BuildQuickRacialOption(profile, groupId)
    local _, spellIDs = CollectPlayerRacialSpells()
    local representative = ResolveSpell(spellIDs[1])
    local statusProfile = profile
    if not profile.entries[RACIAL_BUNDLE_ENTRY_KEY] then
        local statusDraft = ProfileModel:BeginDraft(profile, {
            specKey = rawget(profile, "_yhudSpecKey"),
        })
        if statusDraft then
            ProfileModel:AddEntry(
                statusDraft,
                RACIAL_BUNDLE_ENTRY_KEY,
                BuildRacialBundleEntry(representative)
            )
            statusProfile = statusDraft.profile
        end
    end
    local view = GetTargetView(statusProfile, groupId)
    local status, monitor =
        ResolveStatus(
            statusProfile,
            groupId,
            RACIAL_BUNDLE_ENTRY_KEY,
            view,
            #spellIDs > 0
        )
    return {
        key = QUICK_RACIAL_FOLDER_KEY,
        section = "quick",
        kind = "racial-bundle",
        entryKey = RACIAL_BUNDLE_ENTRY_KEY,
        sourceKey = RACIAL_BUNDLE_SOURCE_KEY,
        name = T("designer.quick_racials", "种族技能组"),
        icon = MonitorCatalog:GetPlayerRacialPreviewIcon(),
        origin = "preset",
        view = view,
        status = status,
        monitorId = monitor and monitor.id,
        fromGroupId = monitor and monitor.groupId,
    }
end

local function BuildQuickSpellBundleOption(profile, groupId, bundleKind)
    local definition = SPELL_BUNDLE_DEFINITIONS[bundleKind]
    if not definition then return nil end
    local spellIDs = CollectPlayerBundleSpells(profile, bundleKind)
    if #spellIDs == 0 then return nil end
    local representative = ResolveSpell(spellIDs[1])
    local statusProfile = profile
    if not profile.entries[definition.entryKey] then
        local statusDraft = ProfileModel:BeginDraft(profile, {
            specKey = rawget(profile, "_yhudSpecKey"),
        })
        if statusDraft then
            ProfileModel:AddEntry(
                statusDraft,
                definition.entryKey,
                BuildSpellBundleEntry(definition, representative)
            )
            statusProfile = statusDraft.profile
        end
    end
    local view = GetTargetView(statusProfile, groupId)
    local status, monitor = ResolveStatus(
        statusProfile,
        groupId,
        definition.entryKey,
        view,
        true
    )
    return {
        key = definition.optionKey,
        section = "quick",
        kind = "spell-bundle",
        bundleKind = bundleKind,
        entryKey = definition.entryKey,
        sourceKey = definition.sourceKey,
        spellID = spellIDs[1],
        name = T(definition.nameKey, definition.fallbackName),
        icon = representative.icon,
        origin = "preset",
        view = view,
        status = status,
        monitorId = monitor and monitor.id,
        fromGroupId = monitor and monitor.groupId,
    }
end

local function BuildEquipmentAuraBundleOption(profile, groupId)
    local statusProfile = profile
    if not profile.entries[EQUIPMENT_AURA_BUNDLE_ENTRY_KEY] then
        local statusDraft = ProfileModel:BeginDraft(profile, {
            specKey = rawget(profile, "_yhudSpecKey"),
        })
        if statusDraft then
            ProfileModel:AddEntry(
                statusDraft,
                EQUIPMENT_AURA_BUNDLE_ENTRY_KEY,
                BuildEquipmentAuraBundleEntry()
            )
            statusProfile = statusDraft.profile
        end
    end
    local view = GetTargetView(statusProfile, groupId)
    local status, monitor = ResolveStatus(
        statusProfile,
        groupId,
        EQUIPMENT_AURA_BUNDLE_ENTRY_KEY,
        view,
        true
    )
    return {
        key = "quick:equipment-auras",
        section = "quick",
        kind = "equipment-aura-bundle",
        bundleKind = EQUIPMENT_AURA_BUNDLE_KIND,
        entryKey = EQUIPMENT_AURA_BUNDLE_ENTRY_KEY,
        sourceKey = EQUIPMENT_AURA_BUNDLE_ENTRY_KEY,
        name = T("designer.quick_equipment_auras", "饰品触发"),
        icon = 2103819,
        origin = "preset",
        view = view,
        status = status,
        monitorId = monitor and monitor.id,
        fromGroupId = monitor and monitor.groupId,
    }
end

local function FindLegacyItemMonitor(profile, preset)
    local legacyItemIDs = type(preset.legacyItemIDs) == "table"
        and preset.legacyItemIDs or nil
    if not legacyItemIDs then return nil end
    for legacyItemID in pairs(legacyItemIDs) do
        local monitor = FindMonitor(
            profile,
            "item:" .. tostring(legacyItemID)
        )
        if monitor then return monitor end
    end
    return nil
end

local function BuildQuickItemOption(profile, groupId, preset)
    local itemID = preset.itemID
    local entryKey = "item:" .. tostring(itemID)
    local fallbackName = T(preset.fallbackKey, preset.fallback)
    local displayItemID = itemID
    if preset.preferredItemID then
        local itemApi = YUI.API and YUI.API.Item
        local count = itemApi and itemApi.GetCount
            and tonumber(itemApi.GetCount(preset.preferredItemID, false, true))
        if count and count > 0 then displayItemID = preset.preferredItemID end
    end
    local item = ResolveItem(displayItemID, true, fallbackName)
    local itemIDs = type(preset.itemIDs) == "table"
        and preset.itemIDs or nil
    local legacyItemIDs = type(preset.legacyItemIDs) == "table"
        and preset.legacyItemIDs or nil
    if not profile.entries[entryKey] then
        profile.entries[entryKey] = {
            entryKey = entryKey,
            sourceKey = entryKey,
            sourceType = "item-cooldown",
            semantic = "cooldown",
            origin = "preset",
            contentScope = YHUD.CONTENT_SCOPE_SPEC,
            presetKey = entryKey,
            crossSpecMaterialization = "immediate",
            itemId = itemID,
            itemIds = itemIDs,
            legacyItemIds = legacyItemIDs,
            name = item.name,
            icon = item.icon,
            contract = {
                capability = "display",
                view = "self",
                group = "free",
                style = "static",
                fallback = "hide",
                status = "verified",
            },
        }
    end
    local displayName = preset.fixedName
        and T(preset.fallbackKey, preset.fixedName)
        or item.name
    local view = GetTargetView(profile, groupId)
    local status, monitor =
        ResolveStatus(profile, groupId, entryKey, view, item.found)
    if status == "add" and not monitor then
        monitor = FindLegacyItemMonitor(profile, preset)
        if monitor then
            status = monitor.groupId == groupId and "current" or "move"
        end
    end
    return {
        key = "quick:" .. entryKey,
        section = "quick",
        kind = "item",
        entryKey = entryKey,
        sourceKey = entryKey,
        itemID = itemID,
        itemIDs = itemIDs,
        legacyItemIDs = legacyItemIDs,
        name = displayName or item.name,
        icon = item.icon,
        origin = "preset",
        knownPreset = true,
        fallbackName = fallbackName,
        view = view,
        status = status,
        monitorId = monitor and monitor.id,
        fromGroupId = monitor and monitor.groupId,
    }
end

local function BuildTimedBuffPresetOption(profile, groupId, preset)
    local itemID = IsPositiveInteger(preset.itemID)
    local factionToken
    local displaySpellID = preset.displaySpellID or preset.spellID
    if preset.presetId == "bloodlust" then
        factionToken = YHUD:GetPlayerFactionToken()
        displaySpellID = factionToken == "Horde" and 2825 or 32182
    end
    local spellID = IsPositiveInteger(displaySpellID)
    local spell = spellID and ResolveSpell(spellID) or nil
    local name = spell and spell.name
    local icon = preset.icon or (spell and spell.icon)
    local displayName = name
    if preset.presetId == "bloodlust" then
        local horde = factionToken == "Horde"
        displayName = T(
            horde and "designer.preset.bloodlust_horde"
                or "designer.preset.bloodlust_alliance",
            horde and "嗜血" or "英勇"
        )
        icon = spell and spell.icon
    end
    local entryKey = preset.entryKey
        or (spellID and ("buff-timer:" .. tostring(spellID)))
    local itemIDs = type(preset.itemIDs) == "table"
        and preset.itemIDs or nil
    local legacyItemIDs = type(preset.legacyItemIDs) == "table"
        and preset.legacyItemIDs or nil
    local legacySpellIDs = type(preset.legacySpellIDs) == "table"
        and preset.legacySpellIDs or nil
    local view = GetTargetView(profile, groupId)
    local status = "unsupported"
    local monitor
    if entryKey then
        if profile.entries[entryKey] then
            status, monitor =
                ResolveStatus(profile, groupId, entryKey, view, true)
        else
            status = "add"
        end
    end

    local baseName = (preset.presetId == "bloodlust" or preset.nameKey == nil)
        and displayName
        or T(preset.nameKey, preset.fallbackName)
    local kind = "timed-buff"
    if preset.sourceType == YHUD.PLAYER_AURA_SOURCE_TYPE then
        kind = "aura-preset"
    elseif preset.sourceType == SPELL_EVENT_WINDOW_SOURCE_TYPE then
        kind = "spell-event-window"
    end
    return {
        key = preset.presetId
            and ("preset:buff:" .. tostring(preset.presetId))
            or (itemID
                and ("preset:buff:item:" .. tostring(itemID))
                or ("preset:buff:spell:" .. tostring(spellID))),
        section = preset.section or (itemID and "quick" or "preset"),
        kind = kind,
        presetId = preset.presetId,
        entryKey = entryKey,
        spellID = spellID,
        tooltipSpellID = spellID,
        itemID = itemID,
        itemIDs = itemIDs,
        legacyItemIDs = legacyItemIDs,
        legacySpellIDs = legacySpellIDs,
        sourceKey = preset.sourceKey,
        sourceType = preset.sourceType,
        sourceIdentity = preset.sourceIdentity,
        spellIDs = preset.spellIDs,
        triggerSpellIDs = preset.triggerSpellIDs,
        durationSeconds = preset.durationSeconds,
        name = baseName,
        nameKey = preset.nameKey,
        presetLabelKey = preset.presetLabelKey,
        tooltipNoteKey = preset.tooltipNoteKey,
        tooltipItemIDs = preset.tooltipItemIDs,
        verificationStatus = preset.verificationStatus,
        contentScope = preset.contentScope,
        icon = icon,
        faction = factionToken,
        view = view,
        status = status,
        unavailable = spellID == nil,
        monitorId = monitor and monitor.id,
        fromGroupId = monitor and monitor.groupId,
    }
end

local function ImportRows(profile, rows, specKey)
    local preview, code = CDMImport:BuildPreview(profile, rows, specKey)
    if not preview then return nil, code end
    local imported, report =
        CDMImport:ApplyPreview(profile, preview, specKey)
    if not imported then return nil, report end
    return imported, preview, report
end

function MonitorCatalog:Build(
    profile,
    specKey,
    groupId,
    semanticFamily,
    options
)
    if not YHUD:IsStableSpecKey(specKey) then
        options = semanticFamily
        semanticFamily = type(groupId) == "table"
            and groupId.semanticFamily or nil
        if type(groupId) == "table" then options = groupId end
        groupId = specKey
        specKey = type(profile) == "table"
            and rawget(profile, "_yhudSpecKey") or YHUD:GetCurrentSpecKey()
    end
    if not YHUD:IsStableSpecKey(specKey) then
        return nil, "invalid-spec-key"
    end
    if type(profile) == "table" and rawget(profile, "_yhudCanonical") then
        local persisted, code = YHUD:PersistScopedProfile(profile)
        if not persisted then return nil, code end
        profile = persisted
    end
    local canonical = YHUD:NormalizeProfile(
        YHUD:CopyValue(YHUD:GetCanonicalProfile(profile)),
        specKey
    )
    profile = YHUD:GetScopedProfile(canonical, specKey, true)
    local group = profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    semanticFamily = semanticFamily == "buff" and "buff" or "cooldown"
    local capabilities = YHUD:GetGroupAddCapabilities(group)
    if not capabilities[semanticFamily] then
        return nil, "content-policy-mismatch"
    end

    local result = {
        groupId = groupId,
        specKey = specKey,
        semanticFamily = semanticFamily,
        options = {},
        warning = nil,
        officialSnapshot = nil,
    }
    local readOptions = {}
    for key, value in pairs(type(options) == "table" and options or {}) do
        if key ~= "includeOfficial" then readOptions[key] = value end
    end
    readOptions.allowUnlearned = true
    readOptions.includeHidden = true
    local includeOfficial = type(options) ~= "table"
        or options.includeOfficial ~= false
    local rows, snapshot
    if includeOfficial then rows, snapshot = CDMCatalog:Read(readOptions) end
    if rows then
        local importRows = {}
        for index = 1, #rows do
            local row = rows[index]
            if IsOfficialRowForFamily(row, semanticFamily)
                and IsOfficialRowNativeVisible(row) then
                importRows[#importRows + 1] = row
            end
        end
        local imported, code = ImportRows(profile, importRows, specKey)
        if not imported then return nil, code end
        profile = imported
        local claimedSources = semanticFamily == "cooldown"
            and self:GetClaimedCooldownSources(profile) or nil
        result.officialSnapshot = YHUD:CopyValue(snapshot)
        for index = 1, #rows do
            local row = rows[index]
            if IsOfficialRowForFamily(row, semanticFamily) then
                local option = BuildOfficialOption(profile, groupId, row)
                local claimSourceKey = option.claimedSourceKey
                    or option.sourceKey
                local claim = claimedSources and claimSourceKey
                    and claimedSources[claimSourceKey]
                if not claim and claimedSources
                    and option.claimedFallbackSourceKey then
                    claim = claimedSources[option.claimedFallbackSourceKey]
                end
                if claim then
                    option.status = "claimed"
                    option.unavailable = true
                    option.monitorId = claim.monitor.id
                    option.fromGroupId = claim.monitor.groupId
                    option.claimedByBundle = claim.bundleKind
                end
                result.options[#result.options + 1] =
                    DecoratePickerOption(option)
            end
        end
    elseif includeOfficial then
        result.warning = snapshot
    end

    if semanticFamily == "cooldown" then
        local ammoOption = BuildAmmoOption(profile, groupId, specKey)
        if ammoOption then result.options[#result.options + 1] = ammoOption end
        result.options[#result.options + 1] =
            BuildSlotOption(profile, groupId, 13)
        result.options[#result.options + 1] =
            BuildSlotOption(profile, groupId, 14)
        local _, _, racialPresets = GetPlayerRaceContext()
        if racialPresets then
            result.options[#result.options + 1] =
                BuildQuickRacialOption(profile, groupId)
        end
        local defensive =
            BuildQuickSpellBundleOption(profile, groupId, "defensive")
        if defensive then result.options[#result.options + 1] = defensive end
        local interruptControl = BuildQuickSpellBundleOption(
            profile,
            groupId,
            "interruptControl"
        )
        if interruptControl then
            result.options[#result.options + 1] = interruptControl
        end
        for index = 1, #QUICK_ITEM_PRESETS do
            result.options[#result.options + 1] =
                BuildQuickItemOption(
                    profile,
                    groupId,
                    QUICK_ITEM_PRESETS[index]
                )
        end
    else
        result.options[#result.options + 1] =
            BuildEquipmentAuraBundleOption(profile, groupId)
        for index = 1, #TIMED_BUFF_SPELL_PRESETS do
            local preset = TIMED_BUFF_SPELL_PRESETS[index]
            if not preset.specKey or preset.specKey == specKey then
                result.options[#result.options + 1] =
                    BuildTimedBuffPresetOption(profile, groupId, preset)
            end
        end
        for index = 1, #QUICK_TIMED_BUFF_PRESETS do
            result.options[#result.options + 1] =
                BuildTimedBuffPresetOption(
                    profile,
                    groupId,
                    QUICK_TIMED_BUFF_PRESETS[index]
                )
        end
        for index = 1, #TIER_SET_AURA_PRESETS do
            local preset = TIER_SET_AURA_PRESETS[index]
            if preset.specKey == specKey then
                result.options[#result.options + 1] =
                    BuildTimedBuffPresetOption(profile, groupId, preset)
            end
        end
    end
    for index = 1, #result.options do
        DecoratePickerOption(result.options[index])
    end
    return result
end

function MonitorCatalog:GetClaimedCooldownSources(profile)
    local claimed = {}
    if type(profile) ~= "table" or type(profile.entries) ~= "table" then
        return claimed
    end

    local function StoreClaim(sourceKey, bundleKind, monitor, semantic)
        if type(sourceKey) ~= "string" or sourceKey == "" then return end
        if not claimed[sourceKey] then
            claimed[sourceKey] = {
                bundleKind = bundleKind,
                monitor = monitor,
                semantic = semantic or "cooldown",
            }
        end
    end

    local function Claim(entryKey, bundleKind, spellIDs)
        local monitor = FindActiveMonitor(profile, entryKey)
        if not monitor then return end
        for index = 1, #spellIDs do
            local sourceKey = "spell:" .. tostring(spellIDs[index])
            StoreClaim(sourceKey, bundleKind, monitor)
        end
    end

    local function ClaimSpellIdentity(entry, monitor)
        local function StoreSpell(value)
            value = tonumber(value)
            if value and value > 0 then
                StoreClaim(
                    "spell:" .. tostring(math.floor(value)),
                    "spell",
                    monitor
                )
            end
        end
        if type(entry.sourceKey) == "string"
            and entry.sourceKey:sub(1, 6) == "spell:" then
            StoreClaim(entry.sourceKey, "spell", monitor)
        end
        StoreSpell(entry.spellId)
        StoreSpell(entry.spellID)
        StoreSpell(entry.overrideSpellId)
        StoreSpell(entry.overrideSpellID)
        StoreSpell(entry.runtimeSpellId)
        StoreSpell(entry.runtimeSpellID)
        for _, field in ipairs({
            entry.spellIds,
            entry.spellIDs,
            entry.linkedSpellIds,
            entry.linkedSpellIDs,
        }) do
            for index = 1, #(type(field) == "table" and field or {}) do
                StoreSpell(field[index])
            end
        end
    end

    local equipmentEntry = profile.entries[EQUIPMENT_AURA_BUNDLE_ENTRY_KEY]
    local equipmentMonitor = equipmentEntry
        and equipmentEntry.bundleEnabled ~= false
        and FindActiveMonitor(profile, EQUIPMENT_AURA_BUNDLE_ENTRY_KEY)
        or nil
    if equipmentMonitor then
        for entryKey, entry in pairs(profile.entries) do
            if YHUD:IsOfficialEquipmentBuffEntry(entry) then
                StoreClaim(
                    entryKey,
                    EQUIPMENT_AURA_BUNDLE_KIND,
                    equipmentMonitor,
                    "buff"
                )
            end
        end
    end

    local racialEntry = profile.entries[RACIAL_BUNDLE_ENTRY_KEY]
    if racialEntry
        and racialEntry.bundleEnabled ~= false
        and type(profile.racials) == "table"
        and profile.racials.enabled == true then
        local _, racialOptions = self:GetPlayerRacialOptions(profile)
        local racialSpellIDs = {}
        for index = 1, #racialOptions do
            if racialOptions[index].enabled ~= false then
                local option = racialOptions[index]
                racialSpellIDs[#racialSpellIDs + 1] = option.spellID
                if option.runtimeSpellID ~= option.spellID then
                    racialSpellIDs[#racialSpellIDs + 1] =
                        option.runtimeSpellID
                end
                for aliasIndex = 1, #(option.aliases or {}) do
                    racialSpellIDs[#racialSpellIDs + 1] =
                        option.aliases[aliasIndex]
                end
            end
        end
        Claim(RACIAL_BUNDLE_ENTRY_KEY, "racial", racialSpellIDs)
    end

    for _, bundleKind in ipairs({ "defensive", "interruptControl" }) do
        local definition = SPELL_BUNDLE_DEFINITIONS[bundleKind]
        local entry = profile.entries[definition.entryKey]
        if entry and entry.bundleEnabled ~= false then
            local _, options = self:GetSpellBundleOptions(
                profile,
                bundleKind
            )
            local enabledSpellIDs = {}
            for index = 1, #(options or {}) do
                if options[index].enabled ~= false then
                    local option = options[index]
                    enabledSpellIDs[#enabledSpellIDs + 1] = option.spellID
                    if option.runtimeSpellID ~= option.spellID then
                        enabledSpellIDs[#enabledSpellIDs + 1] =
                            option.runtimeSpellID
                    end
                    for aliasIndex = 1, #(option.aliases or {}) do
                        enabledSpellIDs[#enabledSpellIDs + 1] =
                            option.aliases[aliasIndex]
                    end
                end
            end
            Claim(
                definition.entryKey,
                bundleKind,
                enabledSpellIDs
            )
        end
    end

    local itemAPI = YUI.API and YUI.API.Item
    local entryKeys = {}
    for entryKey in pairs(profile.entries) do
        entryKeys[#entryKeys + 1] = entryKey
    end
    table.sort(entryKeys)
    for entryIndex = 1, #entryKeys do
        local entryKey = entryKeys[entryIndex]
        local entry = profile.entries[entryKey]
        if type(entry) == "table"
            and YHUD:GetEntrySemantic(entry) == "cooldown" then
            local monitor = FindActiveMonitor(profile, entryKey)
            if monitor and entry.sourceType == "yhud.inventory-slot-cooldown" then
                local slotID = tonumber(entry.slotId)
                if slotID and slotID > 0 then
                    StoreClaim(
                        "slot:" .. tostring(math.floor(slotID)),
                        "slot",
                        monitor
                    )
                end
            elseif monitor and entry.sourceType == "item-cooldown" then
                local itemIDs = {}
                local seenItemIDs = {}
                local function AddItemID(value)
                    value = tonumber(value)
                    if value and value > 0 then
                        value = math.floor(value)
                        if not seenItemIDs[value] then
                            seenItemIDs[value] = true
                            itemIDs[#itemIDs + 1] = value
                        end
                    end
                end
                AddItemID(entry.itemId)
                for index = 1, #(type(entry.itemIds) == "table"
                    and entry.itemIds or {}) do
                    AddItemID(entry.itemIds[index])
                end
                for itemID in pairs(type(entry.legacyItemIds) == "table"
                    and entry.legacyItemIds or {}) do
                    AddItemID(itemID)
                end
                for index = 1, #itemIDs do
                    local officialIdentities =
                        OFFICIAL_ITEM_COOLDOWN_IDENTITIES[itemIDs[index]]
                    for cooldownIndex = 1, #(type(officialIdentities) == "table"
                        and type(officialIdentities.cooldownIDs) == "table"
                        and officialIdentities.cooldownIDs or {}) do
                        StoreClaim(
                            "cdm:" .. tostring(
                                officialIdentities.cooldownIDs[cooldownIndex]
                            ),
                            "item",
                            monitor
                        )
                    end
                    for categoryIndex = 1, #(type(officialIdentities) == "table"
                        and type(officialIdentities.spellCategoryIDs) == "table"
                        and officialIdentities.spellCategoryIDs or {}) do
                        StoreClaim(
                            "spell-category:" .. tostring(
                                officialIdentities.spellCategoryIDs[categoryIndex]
                            ),
                            "item",
                            monitor
                        )
                    end
                    for spellIndex = 1, #(type(officialIdentities) == "table"
                        and type(officialIdentities.legacySpellIDs) == "table"
                        and officialIdentities.legacySpellIDs or {}) do
                        StoreClaim(
                            "spell:" .. tostring(
                                officialIdentities.legacySpellIDs[spellIndex]
                            ),
                            "item",
                            monitor
                        )
                    end
                    local spellID
                    if itemAPI and itemAPI.GetSpell then
                        local _, resolvedSpellID =
                            itemAPI.GetSpell(itemIDs[index])
                        spellID = resolvedSpellID
                    end
                    spellID = tonumber(spellID)
                    if spellID and spellID > 0 then
                        StoreClaim(
                            "spell:" .. tostring(math.floor(spellID)),
                            "item",
                            monitor
                        )
                    end
                end
            elseif monitor
                and entry.origin ~= "official-cdm"
                and entry.bundleKind == nil
                and entry.sourceType ~= "racial-bundle" then
                ClaimSpellIdentity(entry, monitor)
            end
        end
    end
    return claimed
end

local function SetEntryPresentation(draft, entryKey, name, icon)
    local entry = draft.profile.entries[entryKey]
    if not entry then return nil, "entry-not-found" end
    if name and entry.name ~= name then
        entry.name = name
        ProfileModel:MarkDraftChanged(draft)
    end
    if icon and entry.icon ~= icon then
        entry.icon = icon
        ProfileModel:MarkDraftChanged(draft)
    end
    return entry
end

local function PlaceEntry(staged, groupId, entryKey, view, origin)
    local placed, code =
        ProfileModel:CanPlace(staged.profile, entryKey, groupId, view)
    if not placed then return nil, code end

    local existing, current =
        FindMonitor(staged.profile, entryKey, groupId)
    if current then
        return {
            action = "current",
            monitor = YHUD:CopyValue(existing),
        }
    end

    local monitor
    if existing then
        monitor, code =
            ProfileModel:MoveMonitor(
                staged,
                existing.id,
                groupId,
                nil,
                view
            )
        if not monitor then return nil, code end
        return {
            action = "move",
            monitor = monitor,
            fromGroupId = existing.groupId,
        }
    end

    monitor, code = ProfileModel:AddMonitor(staged, {
        entryKey = entryKey,
        groupId = groupId,
        view = view,
        origin = origin,
    })
    if not monitor then return nil, code end
    return {
        action = "add",
        monitor = monitor,
    }
end

local function AdoptResult(target, staged, result)
    local adopted, code = ProfileModel:AdoptDraft(target, staged)
    if not adopted then return nil, code end
    result.entryKey = result.monitor and result.monitor.entryKey
    result.groupId = result.monitor and result.monitor.groupId
    return result
end

local function ApplyOfficial(target, groupId, row)
    if type(row) ~= "table" then return nil, "invalid-option" end
    if not ACTIVE_CATEGORIES[row.category] then
        return nil, "official-source-unsupported"
    end

    local staged = ProfileModel:BeginDraft(target.profile, {
        combat = target.combat == true,
        specKey = target.specKey,
    })
    local imported, preview, report =
        ImportRows(staged.profile, { row }, target.specKey)
    if not imported then return nil, preview end
    staged = ProfileModel:BeginDraft(imported, {
        combat = target.combat == true,
        specKey = target.specKey,
    })
    if report.applied > 0 then staged.changed = true end

    local mapping = preview.mapping[1]
    if not mapping or not mapping.entryKey then
        return nil, "official-source-unsupported"
    end
    local entry = staged.profile.entries[mapping.entryKey]
    local spell = ResolveSpell(
        entry and (entry.overrideSpellId or entry.spellId)
    )
    SetEntryPresentation(staged, mapping.entryKey, spell.name, spell.icon)

    local view = GetTargetView(staged.profile, groupId)
    local result, code = PlaceEntry(
        staged,
        groupId,
        mapping.entryKey,
        view,
        "official-cdm"
    )
    if not result then return nil, code end
    return AdoptResult(target, staged, result)
end

local function ApplySlot(target, groupId, slotID)
    local entryKey = "slot:" .. tostring(slotID)
    local staged = ProfileModel:BeginDraft(target.profile, {
        combat = target.combat == true,
        specKey = target.specKey,
    })
    local slot = ResolveSlot(slotID)
    local entry, code =
        SetEntryPresentation(staged, entryKey, slot.name, slot.icon)
    if not entry then return nil, code end

    local result
    result, code = PlaceEntry(
        staged,
        groupId,
        entryKey,
        GetTargetView(staged.profile, groupId),
        "preset"
    )
    if not result then return nil, code end
    return AdoptResult(target, staged, result)
end

function MonitorCatalog:Apply(draft, groupId, option)
    if not ProfileModel:IsDraft(draft) or draft.closed == true then
        return nil, "invalid-draft"
    end
    if type(option) ~= "table" then return nil, "invalid-option" end
    if option.kind == "official" then
        return ApplyOfficial(draft, groupId, option.row)
    end
    if option.kind == "ammo" then
        local ammo = YHUD.Ammo
        if not (ammo and ammo:IsApplicable(draft.specKey)) then
            return nil, "unsupported-preset-client"
        end
        local staged = ProfileModel:BeginDraft(draft.profile, {
            combat = draft.combat == true, specKey = draft.specKey,
        })
        if not staged.profile.entries[ammo.ENTRY_KEY] then
            local entry, code = ProfileModel:AddEntry(staged, ammo.ENTRY_KEY, ammo:BuildEntry())
            if not entry then return nil, code end
        end
        local result, code = PlaceEntry(staged, groupId, ammo.ENTRY_KEY,
            GetTargetView(staged.profile, groupId), "preset")
        if not result then return nil, code end
        return AdoptResult(draft, staged, result)
    end
    if option.kind == "slot" then
        local slotID = IsPositiveInteger(option.slotID)
        if slotID ~= 13 and slotID ~= 14 then
            return nil, "invalid-slot"
        end
        return ApplySlot(draft, groupId, slotID)
    end
    if option.kind == "racial-bundle" or option.kind == "racial" then
        return self:AddRacial(draft, groupId)
    end
    if option.kind == "spell-bundle" then
        return self:AddSpellBundle(draft, groupId, option.bundleKind)
    end
    if option.kind == "equipment-aura-bundle" then
        return self:AddEquipmentAuraBundle(draft, groupId)
    end
    if option.kind == "item" then
        return self:AddItem(draft, groupId, option.itemID, {
            origin = option.origin or "preset",
            knownPreset = option.knownPreset == true,
            name = option.name,
            fallbackName = option.fallbackName,
            itemIDs = option.itemIDs,
            legacyItemIDs = option.legacyItemIDs,
        })
    end
    if option.kind == "aura-preset" then
        return self:AddPresetPlayerAura(
            draft,
            draft.specKey,
            groupId,
            option.spellID,
            option.spellIDs,
            {
                entryKey = option.entryKey,
                sourceKey = option.sourceKey,
                sourceIdentity = option.sourceIdentity,
                name = option.name,
                nameKey = option.nameKey,
                contentScope = option.contentScope,
            }
        )
    end
    if option.kind == "timed-buff" then
        return self:AddCustomBuffTimer(
            draft,
            draft.specKey,
            groupId,
            option.spellID,
            option.durationSeconds,
            {
                entryKey = option.entryKey,
                sourceKey = option.sourceKey,
                sourceIdentity = option.sourceIdentity,
                triggerSpellIDs = option.triggerSpellIDs,
                itemIDs = option.itemIDs,
                legacyItemIDs = option.legacyItemIDs,
                legacySpellIDs = option.legacySpellIDs,
                name = option.name,
                icon = option.icon,
                nameKey = option.nameKey,
                origin = "preset",
            }
        )
    end
    if option.kind == "spell-event-window" then
        return self:AddPresetSpellEventWindow(
            draft,
            draft.specKey,
            groupId,
            option
        )
    end
    return nil, "invalid-option"
end

local function RowMatchesSpell(row, spellID)
    if row.spellID == spellID or row.overrideSpellID == spellID then
        return true
    end
    local linked = row.linkedSpellIDs
    if type(linked) == "table" then
        for index = 1, #linked do
            if linked[index] == spellID then return true end
        end
    end
    return false
end

function MonitorCatalog:AddCustomSpell(draft, groupId, spellID, options)
    if not ProfileModel:IsDraft(draft) or draft.closed == true then
        return nil, "invalid-draft"
    end
    spellID = IsPositiveInteger(spellID)
    if not spellID then return nil, "invalid-spell-id" end

    local claim = self:GetClaimedCooldownSources(draft.profile)[
        "spell:" .. tostring(spellID)
    ]
    if claim and claim.bundleKind ~= "spell" then
        return {
            action = "current",
            groupId = claim.monitor.groupId,
            monitor = claim.monitor,
            claimedByBundle = claim.bundleKind,
        }
    end

    local rows = CDMCatalog:Read(options)
    if type(rows) == "table" then
        for index = 1, #rows do
            local row = rows[index]
            if type(row) == "table"
                and (row.category == "essential"
                    or row.category == "utility")
                and RowMatchesSpell(row, spellID) then
                if not ACTIVE_CATEGORIES[row.category] then
                    return nil, "official-source-unsupported"
                end
                return ApplyOfficial(draft, groupId, row)
            end
        end
    end

    local spell = ResolveSpell(spellID)
    local api = YUI.API and YUI.API.Spell
    local info = api and api.GetInfo and api.GetInfo(spellID)
    if not (info and info.name) then return nil, "spell-not-found" end

    local sourceKey = "spell:" .. tostring(spellID)
    local applicability = YHUD:NormalizeApplicability(nil, {
        sourceType = "spell-cooldown",
        origin = "custom",
    }, draft.specKey)
    local entryKey = YHUD:QualifySharedEntryKey(
        sourceKey,
        applicability
    )
    local staged = ProfileModel:BeginDraft(draft.profile, {
        combat = draft.combat == true,
        specKey = draft.specKey,
    })
    local existing = staged.profile.entries[entryKey]
    if existing then
        if existing.sourceKey ~= sourceKey
            or existing.sourceType ~= "spell-cooldown" then
            return nil, "entry-conflict"
        end
        SetEntryPresentation(staged, entryKey, spell.name, spell.icon)
    else
        local added, code = ProfileModel:AddEntry(staged, entryKey, {
            sourceKey = sourceKey,
            sourceType = "spell-cooldown",
            semantic = "cooldown",
            origin = "custom",
            applicability = applicability,
            spellId = spellID,
            name = spell.name,
            icon = spell.icon,
            contract = {
                capability = "full",
                view = "self",
                group = "free",
                style = "full",
                fallback = "hide",
                status = "verified",
            },
        })
        if not added then return nil, code end
    end

    local result, code = PlaceEntry(
        staged,
        groupId,
        entryKey,
        GetTargetView(staged.profile, groupId),
        "custom"
    )
    if not result then return nil, code end
    return AdoptResult(draft, staged, result)
end

function MonitorCatalog:AddSpellBundle(draft, groupId, bundleKind)
    if not ProfileModel:IsDraft(draft) or draft.closed == true then
        return nil, "invalid-draft"
    end
    local definition = SPELL_BUNDLE_DEFINITIONS[bundleKind]
    if not definition then return nil, "invalid-spell-bundle" end
    local spellIDs = CollectPlayerBundleSpells(draft.profile, bundleKind)
    if #spellIDs == 0 then return nil, "spell-bundle-not-available" end
    local _, bundleOptions = self:GetSpellBundleOptions(
        draft.profile,
        bundleKind
    )
    local representative = ResolveSpell(
        bundleOptions and bundleOptions[1]
            and bundleOptions[1].runtimeSpellID
            or spellIDs[1]
    )
    local staged = ProfileModel:BeginDraft(draft.profile, {
        combat = draft.combat == true,
        specKey = draft.specKey,
    })
    local existing = staged.profile.entries[definition.entryKey]
    if existing then
        if existing.sourceKey ~= definition.sourceKey
            or existing.sourceType ~= SPELL_BUNDLE_SOURCE_TYPE
            or existing.bundleKind ~= bundleKind then
            return nil, "entry-conflict"
        end
        existing.bundleEnabled = true
        existing.contentScope = YHUD.CONTENT_SCOPE_SPEC
        existing.applicability = nil
        for _, monitor in pairs(staged.profile.monitors or {}) do
            if monitor.entryKey == definition.entryKey then
                monitor.contentScope = YHUD.CONTENT_SCOPE_SPEC
            end
        end
        SetEntryPresentation(
            staged,
            definition.entryKey,
            T(definition.nameKey, definition.fallbackName),
            representative.icon
        )
        staged.changed = true
    else
        local added, code = ProfileModel:AddEntry(
            staged,
            definition.entryKey,
            BuildSpellBundleEntry(definition, representative)
        )
        if not added then return nil, code end
    end

    local result, code = PlaceEntry(
        staged,
        groupId,
        definition.entryKey,
        GetTargetView(staged.profile, groupId),
        "preset"
    )
    if not result then return nil, code end
    return AdoptResult(draft, staged, result)
end

function MonitorCatalog:AddEquipmentAuraBundle(draft, groupId)
    if not ProfileModel:IsDraft(draft) or draft.closed == true then
        return nil, "invalid-draft"
    end

    local staged = ProfileModel:BeginDraft(draft.profile, {
        combat = draft.combat == true,
        specKey = draft.specKey,
    })
    local existing = staged.profile.entries[EQUIPMENT_AURA_BUNDLE_ENTRY_KEY]
    if existing then
        if existing.sourceKey ~= EQUIPMENT_AURA_BUNDLE_ENTRY_KEY
            or existing.bundleKind ~= EQUIPMENT_AURA_BUNDLE_KIND
            or existing.semantic ~= "buff" then
            return nil, "entry-conflict"
        end
        existing.sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE
            or "yhud.player-aura"
        existing.bundleEnabled = true
        existing.contentScope = YHUD.CONTENT_SCOPE_SPEC
        existing.applicability = nil
        existing.compatibleViews = {
            icon = true,
            bar = true,
            ring = true,
        }
        existing.contract = BuildEquipmentAuraBundleEntry().contract
        existing.name = nil
        existing.nameKey = "designer.quick_equipment_auras"
        existing.icon = 2103819
        for _, monitor in pairs(staged.profile.monitors or {}) do
            if monitor.entryKey == EQUIPMENT_AURA_BUNDLE_ENTRY_KEY then
                monitor.contentScope = YHUD.CONTENT_SCOPE_SPEC
            end
        end
        ProfileModel:MarkDraftChanged(staged)
    else
        local added, code = ProfileModel:AddEntry(
            staged,
            EQUIPMENT_AURA_BUNDLE_ENTRY_KEY,
            BuildEquipmentAuraBundleEntry()
        )
        if not added then return nil, code end
    end

    local result, code = PlaceEntry(
        staged,
        groupId,
        EQUIPMENT_AURA_BUNDLE_ENTRY_KEY,
        GetTargetView(staged.profile, groupId),
        "preset"
    )
    if not result then return nil, code end
    return AdoptResult(draft, staged, result)
end

function MonitorCatalog:AddRacial(draft, groupId)
    if not ProfileModel:IsDraft(draft) or draft.closed == true then
        return nil, "invalid-draft"
    end
    local raceToken, spellIDs = CollectPlayerRacialSpells()
    if #spellIDs == 0 then
        return nil, "racial-not-available"
    end
    local representative = ResolveSpell(spellIDs[1])
    local staged = ProfileModel:BeginDraft(draft.profile, {
        combat = draft.combat == true,
        specKey = draft.specKey,
    })
    local legacyEntryKeys = {}
    for entryKey, entry in pairs(staged.profile.entries) do
        if entryKey ~= RACIAL_BUNDLE_ENTRY_KEY
            and type(entryKey) == "string"
            and entryKey:sub(1, 7) == "racial:"
            and type(entry) == "table" then
            legacyEntryKeys[entryKey] = true
        end
    end
    if next(legacyEntryKeys) then
        local legacyMonitorIds = {}
        for monitorId, monitor in pairs(staged.profile.monitors) do
            if legacyEntryKeys[monitor.entryKey] then
                legacyMonitorIds[#legacyMonitorIds + 1] = monitorId
            end
        end
        for index = 1, #legacyMonitorIds do
            ProfileModel:RemoveMonitor(staged, legacyMonitorIds[index])
        end
        for entryKey in pairs(legacyEntryKeys) do
            staged.profile.entries[entryKey] = nil
            if staged.profile._yhudScopeByEntry then
                staged.profile._yhudScopeByEntry[entryKey] = nil
            end
        end
        staged.changed = true
    end
    local existing = staged.profile.entries[RACIAL_BUNDLE_ENTRY_KEY]
    if existing then
        if existing.sourceKey ~= RACIAL_BUNDLE_SOURCE_KEY
            or existing.sourceType ~= "racial-bundle" then
            return nil, "entry-conflict"
        end
        existing.bundleKind = "racial"
        existing.bundleEnabled = true
        SetEntryPresentation(
            staged,
            RACIAL_BUNDLE_ENTRY_KEY,
            T("designer.quick_racials", "种族技能组"),
            representative.icon
        )
    else
        local added, code = ProfileModel:AddEntry(
            staged,
            RACIAL_BUNDLE_ENTRY_KEY,
            BuildRacialBundleEntry(representative)
        )
        if not added then return nil, code end
    end

    local migratedEntry = staged.profile.entries[RACIAL_BUNDLE_ENTRY_KEY]
    local legacyRacials = staged.profile.racials
    local legacyChoices = type(legacyRacials) == "table"
        and type(legacyRacials.choicesByRace) == "table"
        and legacyRacials.choicesByRace or nil
    if legacyChoices then
        local _, stableRaceToken = GetPlayerRaceContext()
        if stableRaceToken
            and type(legacyChoices[stableRaceToken]) == "table" then
            local saved = type(migratedEntry.bundleChoicesByContext) == "table"
                and migratedEntry.bundleChoicesByContext or {}
            migratedEntry.bundleChoicesByContext = saved
            if type(saved[stableRaceToken]) ~= "table" then
                saved[stableRaceToken] = {}
            end
            for spellID, enabled in pairs(legacyChoices[stableRaceToken]) do
                saved[stableRaceToken][spellID] = enabled ~= false
            end
            MigrateRacialChoiceTable(
                stableRaceToken,
                saved[stableRaceToken]
            )
            staged.changed = true
        end
        legacyRacials.choicesByRace = nil
    end

    staged.profile.racials = type(staged.profile.racials) == "table"
        and staged.profile.racials or {}
    staged.profile.racials.enabled = true
    staged.changed = true

    local result, code = PlaceEntry(
        staged,
        groupId,
        RACIAL_BUNDLE_ENTRY_KEY,
        GetTargetView(staged.profile, groupId),
        "preset"
    )
    if not result then return nil, code end
    return AdoptResult(draft, staged, result)
end

function MonitorCatalog:GetRacialContexts()
    local _, currentRaceToken = GetPlayerRaceContext()
    local unitApi = YUI.API and YUI.API.Unit
    local contexts = {}
    for raceToken in pairs(RACIAL_PRESETS) do
        local stableToken = NormalizeRacialContextKey(raceToken, false)
        local _, spellIDs = CollectRacialSpells(stableToken)
        if #spellIDs > 0 then
            local racial = YUI.API and YUI.API.Racial
            local info = racial and racial.GetRaceInfo and racial.GetRaceInfo(raceToken)
                or (unitApi and unitApi.GetRaceInfoByFile
                    and unitApi.GetRaceInfoByFile(raceToken))
            contexts[#contexts + 1] = {
                key = stableToken,
                name = info and info.raceName or raceToken,
                raceID = info and info.raceID or 9999,
                raceFile = string.upper(info and info.clientFileString or raceToken),
                current = stableToken == currentRaceToken,
            }
        end
    end
    table.sort(contexts, function(left, right)
        if left.current ~= right.current then return left.current end
        if left.raceID ~= right.raceID then
            return left.raceID < right.raceID
        end
        return left.name < right.name
    end)
    return contexts, currentRaceToken
end

local function ResolveProfileChargeCapability(
    profile,
    spellID,
    runtimeSpellID,
    aliases
)
    local family = {}
    local function Add(value)
        value = IsPositiveInteger(value)
        if value then family[value] = true end
    end
    Add(spellID)
    Add(runtimeSpellID)
    for index = 1, #(type(aliases) == "table" and aliases or {}) do
        Add(aliases[index])
    end

    for _, candidate in pairs(type(profile) == "table"
        and type(profile.entries) == "table" and profile.entries or {}) do
        if type(candidate) == "table" and candidate.charges == true then
            if family[IsPositiveInteger(candidate.spellId)]
                or family[IsPositiveInteger(candidate.overrideSpellId)]
                or family[IsPositiveInteger(candidate.overrideTooltipSpellId)]
                or family[IsPositiveInteger(candidate.chargeSpellId)] then
                return true
            end
            local linked = candidate.linkedSpellIds
            for index = 1, #(type(linked) == "table" and linked or {}) do
                if family[IsPositiveInteger(linked[index])] then return true end
            end
        end
    end
    return false
end

function MonitorCatalog:GetPlayerRacialOptions(profile, requestedRaceToken)
    local raceToken, spellIDs = CollectRacialSpells(requestedRaceToken)
    local presets = GetRacialPresetsForContext(raceToken)
    local _, currentRaceToken = GetPlayerRaceContext()
    local knownOnly = raceToken == currentRaceToken
    local entry = type(profile) == "table"
        and type(profile.entries) == "table"
        and profile.entries[RACIAL_BUNDLE_ENTRY_KEY] or nil
    local _, contextKey, legacyRaceKey, legacyClassKey =
        GetRacialContextKeys(profile, raceToken)
    local savedOrder = ReadRacialContextData(
        entry,
        "bundleOrderByContext",
        raceToken,
        contextKey,
        legacyRaceKey,
        legacyClassKey
    )
    spellIDs = ApplySavedSpellOrder(
        spellIDs,
        CanonicalizeRacialSavedOrder(raceToken, savedOrder)
    )
    local result = {}
    local choices = ReadRacialContextData(
        entry,
        "bundleChoicesByContext",
        raceToken,
        contextKey,
        legacyRaceKey,
        legacyClassKey
    )
    for index = 1, #spellIDs do
        local spellID = spellIDs[index]
        local member = FindRacialMember(presets, spellID) or spellID
        local runtimeSpellID = ResolveRacialRuntimeSpellID(
            member,
            knownOnly
        ) or spellID
        local familySpellIDs = CollectRacialFamilySpellIDs(member)
        local spell = ResolveSpell(runtimeSpellID)
        result[index] = {
            spellID = spellID,
            runtimeSpellID = runtimeSpellID,
            aliases = familySpellIDs,
            hasCharges = ResolveProfileChargeCapability(
                profile,
                spellID,
                runtimeSpellID,
                familySpellIDs
            ),
            name = spell.name,
            icon = spell.icon,
            enabled = ReadRacialFamilyChoice(choices, member),
        }
    end
    return raceToken, result
end

local function BuildEnabledSpellSourceRecords(options)
    local result = {}
    local seenSources = {}
    for index = 1, #(type(options) == "table" and options or {}) do
        local option = options[index]
        if option and option.enabled ~= false then
            local spellID = IsPositiveInteger(option.spellID)
            local runtimeSpellID = IsPositiveInteger(option.runtimeSpellID)
                or spellID
            if spellID then
                local sourceKey = "spell:" .. tostring(spellID)
                if not seenSources[sourceKey] then
                    local hasCharges = option.hasCharges == true
                    local aliases = {}
                    local seenAliases = {}
                    local function AddAlias(value)
                        value = IsPositiveInteger(value)
                        if value and not seenAliases[value] then
                            seenAliases[value] = true
                            aliases[#aliases + 1] = value
                        end
                    end
                    AddAlias(spellID)
                    AddAlias(runtimeSpellID)
                    for aliasIndex = 1, #(type(option.aliases) == "table"
                        and option.aliases or {}) do
                        AddAlias(option.aliases[aliasIndex])
                    end
                    table.sort(aliases)
                    seenSources[sourceKey] = true
                    result[#result + 1] = {
                        spellID = spellID,
                        runtimeSpellID = runtimeSpellID,
                        chargeSpellID = runtimeSpellID,
                        displayIcon = option.icon or 134400,
                        displayName = option.name,
                        hasCharges = hasCharges,
                        aliases = aliases,
                        sourceKey = sourceKey,
                        signature = table.concat({
                            tostring(runtimeSpellID),
                            tostring(runtimeSpellID),
                            table.concat(aliases, ","),
                            hasCharges and "1" or "0",
                        }, ":"),
                    }
                end
            end
        end
    end
    return result
end

function MonitorCatalog:GetEnabledPlayerRacialSources(profile)
    if type(profile) ~= "table"
        or type(profile.entries) ~= "table"
        or type(profile.entries[RACIAL_BUNDLE_ENTRY_KEY]) ~= "table"
        or profile.entries[RACIAL_BUNDLE_ENTRY_KEY].bundleEnabled == false
        or type(profile.racials) ~= "table"
        or profile.racials.enabled ~= true
        or not FindActiveMonitor(profile, RACIAL_BUNDLE_ENTRY_KEY) then
        return {}
    end
    local _, options = self:GetPlayerRacialOptions(profile)
    return BuildEnabledSpellSourceRecords(options)
end

function MonitorCatalog:GetEnabledPlayerRacialSpells(profile)
    local sources = self:GetEnabledPlayerRacialSources(profile)
    local result = {}
    for index = 1, #sources do
        result[index] = sources[index].runtimeSpellID
    end
    return result
end

function MonitorCatalog:SetRacialSpellEnabled(
    draft,
    spellID,
    enabled,
    requestedRaceToken
)
    if not ProfileModel:IsDraft(draft) or draft.closed == true then
        return nil, "invalid-draft"
    end
    spellID = IsPositiveInteger(spellID)
    if not spellID then return nil, "invalid-spell-id" end
    local raceToken, spellIDs = CollectRacialSpells(requestedRaceToken)
    spellID = CanonicalizeRacialSpellID(raceToken, spellID)
    local supported = false
    for index = 1, #spellIDs do
        if spellIDs[index] == spellID then supported = true break end
    end
    if not supported or not raceToken then
        return nil, "racial-not-available"
    end
    local entry = draft.profile.entries[RACIAL_BUNDLE_ENTRY_KEY]
    local _, contextKey, legacyRaceKey, legacyClassKey =
        GetRacialContextKeys(draft.profile, raceToken)
    if not entry or not contextKey then return nil, "racial-not-added" end
    local racials = type(draft.profile.racials) == "table"
        and draft.profile.racials or {}
    draft.profile.racials = racials
    racials.enabled = true
    entry.bundleEnabled = true
    local saved = MigrateRacialContextData(
        entry,
        "bundleChoicesByContext",
        raceToken,
        contextKey,
        legacyRaceKey,
        legacyClassKey
    )
    if type(saved) ~= "table" then
        saved = {}
        entry.bundleChoicesByContext = saved
    end
    local choices = saved[contextKey]
    if type(choices) ~= "table" then
        choices = {}
        saved[contextKey] = choices
    end
    MigrateRacialChoiceTable(raceToken, choices)
    choices[tostring(spellID)] = enabled ~= false
    ProfileModel:MarkDraftChanged(draft)
    return true
end

function MonitorCatalog:GetSpellBundleOptions(
    profile,
    bundleKind,
    requestedSpecKey
)
    local definition = SPELL_BUNDLE_DEFINITIONS[bundleKind]
    if not definition then return nil, "invalid-spell-bundle" end
    local classToken, specID, specKey = GetSpecContext(
        profile,
        requestedSpecKey
    )
    local spellIDs = CollectPlayerBundleSpells(profile, bundleKind, specKey)
    local entry = type(profile) == "table"
        and type(profile.entries) == "table"
        and profile.entries[definition.entryKey] or nil
    local choices = specKey and ReadContextData(
        entry,
        "bundleChoicesByContext",
        specKey,
        type(profile) == "table"
            and specKey == rawget(profile, "_yhudSpecKey")
            and "bundleChoices" or nil
    ) or nil
    local result = {}
    local knownOnly = specKey == YHUD:GetCurrentSpecKey()
    for index = 1, #spellIDs do
        local spellID = spellIDs[index]
        local member = FindBundleMember(
            definition,
            classToken,
            specID,
            spellID
        )
        local runtimeSpellID = ResolveBundleRuntimeSpellID(
            member,
            specID,
            knownOnly
        ) or spellID
        local aliases = CollectBundleFamilySpellIDs(
            member,
            specID,
            knownOnly
        )
        local spell = ResolveSpell(runtimeSpellID)
        result[index] = {
            spellID = spellID,
            runtimeSpellID = runtimeSpellID,
            aliases = aliases,
            hasCharges = ResolveProfileChargeCapability(
                profile,
                spellID,
                runtimeSpellID,
                aliases
            ),
            name = spell.name,
            icon = spell.icon,
            enabled = type(choices) ~= "table"
                or choices[tostring(spellID)] ~= false,
        }
    end
    return specKey, result
end

function MonitorCatalog:GetEnabledSpellBundleSpells(profile, bundleKind)
    local sources = self:GetEnabledSpellBundleSources(profile, bundleKind)
    local result = {}
    for index = 1, #sources do
        result[index] = sources[index].runtimeSpellID
    end
    return result
end

local EQUIPMENT_TRIGGER_KIND_ORDER = {
    ["active-timer"] = 1,
    ["official-passive"] = 2,
    ["missing-official-config"] = 3,
    ["missing-active-timer"] = 4,
}
local EQUIPMENT_ACTIVE_SOURCE_CATEGORIES = {
    equipSlotEssential = true,
    specAgnosticEssential = true,
}

local function SafePositiveNumber(value)
    if Security and Security.IsSecretValue
        and Security.IsSecretValue(value) == true then
        return nil
    end
    if Security and Security.SafeNumber then
        value = Security.SafeNumber(value)
    elseif type(value) ~= "number" then
        return nil
    end
    return value and value == value and value > 0 and value or nil
end

local function AddEquipmentIdentity(target, ordered, value)
    value = IsPositiveInteger(value)
    if value and not target[value] then
        target[value] = true
        ordered[#ordered + 1] = value
    end
    return value
end

local function AddEquipmentEntryIdentities(entry, strong, related, ordered)
    if type(entry) ~= "table" then return end
    for _, value in ipairs({
        entry.spellId,
        entry.overrideSpellId,
        entry.overrideTooltipSpellId,
        entry.runtimeSpellId,
    }) do
        value = AddEquipmentIdentity(related, ordered, value)
        if value then strong[value] = true end
    end
    for index = 1, #(entry.linkedSpellIds or {}) do
        AddEquipmentIdentity(related, ordered, entry.linkedSpellIds[index])
    end
end

local function OfficialEntryHasIdentity(entry)
    if type(entry) ~= "table" then return false end
    for _, value in ipairs({
        entry.spellId,
        entry.overrideSpellId,
        entry.overrideTooltipSpellId,
        entry.runtimeSpellId,
    }) do
        if IsPositiveInteger(value) then return true end
    end
    for index = 1, #(entry.linkedSpellIds or {}) do
        if IsPositiveInteger(entry.linkedSpellIds[index]) then return true end
    end
    return false
end

local function OfficialEntryMatchesActive(entry, strong, related)
    if type(entry) ~= "table" then return false end
    for _, value in ipairs({
        entry.spellId,
        entry.overrideSpellId,
        entry.overrideTooltipSpellId,
        entry.runtimeSpellId,
    }) do
        value = IsPositiveInteger(value)
        if value and related[value] then return true end
    end
    for index = 1, #(entry.linkedSpellIds or {}) do
        local value = IsPositiveInteger(entry.linkedSpellIds[index])
        if value and strong[value] then return true end
    end
    return false
end

local function ResolveEquipmentSlotPresentation(equipSlot)
    if not (Item and Item.GetInventoryItemID) then return nil, nil end
    local itemID = IsPublicPositiveInteger(
        Item.GetInventoryItemID("player", equipSlot)
    )
    if not itemID then return nil, nil end
    local icon = Item.GetInventoryItemTexture
        and Item.GetInventoryItemTexture("player", equipSlot) or nil
    local name = Item.GetName and Item.GetName(itemID) or nil
    if Security and Security.IsSecretValue then
        if Security.IsSecretValue(icon) == true then icon = nil end
        if Security.IsSecretValue(name) == true then name = nil end
    end
    return icon, name
end

local function ResolveEquipmentActiveTimer(
    equipSlot,
    strongIdentities,
    relatedIdentities,
    orderedIdentities
)
    if not (Item and Item.GetInventoryItemID and Item.GetSpell) then return nil end
    local itemID = IsPublicPositiveInteger(
        Item.GetInventoryItemID("player", equipSlot)
    )
    if not itemID then return nil end
    local _, triggerSpellID = Item.GetSpell(itemID)
    triggerSpellID = IsPublicPositiveInteger(triggerSpellID)
    if not triggerSpellID then return nil end
    AddEquipmentIdentity(relatedIdentities, orderedIdentities, triggerSpellID)
    strongIdentities[triggerSpellID] = true
    local durationSeconds = Item.GetUseEffectDurationSeconds
        and SafePositiveNumber(Item.GetUseEffectDurationSeconds(
            itemID,
            triggerSpellID,
            "player",
            equipSlot
        )) or nil

    local spell = ResolveSpell(triggerSpellID)
    local icon = Item.GetInventoryItemTexture
        and Item.GetInventoryItemTexture("player", equipSlot)
        or nil
    if Security and Security.IsSecretValue
        and Security.IsSecretValue(icon) == true then
        icon = nil
    end
    icon = icon or spell.icon
    local itemName = Item.GetName and Item.GetName(itemID) or nil
    if Security and Security.IsSecretValue
        and Security.IsSecretValue(itemName) == true then
        itemName = nil
    end
    if not durationSeconds then
        return nil, {
            kind = "missing-active-timer",
            childIdentity = "active:" .. tostring(equipSlot),
            equipSlot = equipSlot,
            buffSlot = 0,
            cooldownID = 0,
            itemID = itemID,
            spellID = triggerSpellID,
            displayIcon = icon,
            displayName = itemName or spell.name,
            sourceKey = "equipment-trigger-preview:active:"
                .. tostring(equipSlot),
            previewOnly = true,
            reason = "duration-unavailable",
        }
    end
    table.sort(orderedIdentities)
    local sourceKey = "equipment-trigger:" .. tostring(equipSlot)
    return {
        kind = "active-timer",
        childIdentity = "active:" .. tostring(equipSlot),
        equipSlot = equipSlot,
        buffSlot = 0,
        cooldownID = 0,
        itemID = itemID,
        spellID = triggerSpellID,
        runtimeSpellID = triggerSpellID,
        aliases = YHUD:CopyValue(orderedIdentities),
        triggerSpellIDs = { triggerSpellID },
        durationSeconds = durationSeconds,
        displayIcon = icon,
        icon = icon,
        displayName = itemName or spell.name,
        sourceKey = sourceKey,
        sourceIdentity = sourceKey,
        signature = table.concat({
            tostring(equipSlot),
            tostring(itemID),
            tostring(triggerSpellID),
            tostring(durationSeconds),
        }, ":"),
    }
end

function MonitorCatalog:GetEquipmentTriggerProjection(profile)
    local entries = type(profile) == "table"
        and type(profile.entries) == "table" and profile.entries or nil
    if not entries then return {} end

    local projection = {}
    local activeStrongBySlot = { [13] = {}, [14] = {} }
    local activeRelatedBySlot = { [13] = {}, [14] = {} }
    local activeOrderedBySlot = { [13] = {}, [14] = {} }
    for entryKey, entry in pairs(entries) do
        local equipSlot = type(entry) == "table"
            and tonumber(entry.equipSlot) or nil
        if type(entry) == "table"
            and entry.origin == "official-cdm"
            and (equipSlot == 13 or equipSlot == 14)
            and EQUIPMENT_ACTIVE_SOURCE_CATEGORIES[
                entry.sourceCategory
            ] == true then
            AddEquipmentEntryIdentities(
                entry,
                activeStrongBySlot[equipSlot],
                activeRelatedBySlot[equipSlot],
                activeOrderedBySlot[equipSlot]
            )
        end
    end

    for equipSlot = 13, 14 do
        local activeTimer, activeIssue = ResolveEquipmentActiveTimer(
            equipSlot,
            activeStrongBySlot[equipSlot],
            activeRelatedBySlot[equipSlot],
            activeOrderedBySlot[equipSlot]
        )
        if activeTimer then
            projection[#projection + 1] = activeTimer
        elseif activeIssue then
            projection[#projection + 1] = activeIssue
        end
    end

    for entryKey, entry in pairs(entries) do
        if YHUD:IsOfficialEquipmentBuffEntry(entry) then
            local equipSlot = tonumber(entry.equipSlot)
            local cooldownID = IsPositiveInteger(entry.cooldownId) or 0
            local buffSlot = IsPositiveInteger(entry.buffSlot) or 0
            local activeOwned = OfficialEntryMatchesActive(
                entry,
                activeStrongBySlot[equipSlot],
                activeRelatedBySlot[equipSlot]
            )
            if not activeOwned
                and YHUD:IsOfficialEquipmentBuffUsable(entry) then
                local displaySpellID = IsPositiveInteger(
                    entry.overrideTooltipSpellId
                        or entry.overrideSpellId
                        or entry.spellId
                )
                projection[#projection + 1] = {
                    kind = "official-passive",
                    childIdentity = "official:" .. tostring(cooldownID),
                    equipSlot = equipSlot,
                    buffSlot = buffSlot,
                    cooldownID = cooldownID,
                    entryKey = entryKey,
                    sourceKey = entry.sourceKey or entryKey,
                    spellID = displaySpellID,
                    runtimeSpellID = displaySpellID,
                    aliases = YHUD:CopyValue(entry.linkedSpellIds or {}),
                    displayIcon = entry.icon,
                    icon = entry.icon,
                    displayName = YHUD:GetEntryDisplayName(
                        entry,
                        "cdm:" .. tostring(cooldownID)
                    ),
                    signature = table.concat({
                        tostring(equipSlot),
                        "official",
                        tostring(buffSlot),
                        tostring(cooldownID),
                    }, ":"),
                }
            elseif not activeOwned and OfficialEntryHasIdentity(entry) then
                local displaySpellID = IsPositiveInteger(
                    entry.overrideTooltipSpellId
                        or entry.overrideSpellId
                        or entry.spellId
                )
                local fallbackIcon, fallbackName =
                    ResolveEquipmentSlotPresentation(equipSlot)
                projection[#projection + 1] = {
                    kind = "missing-official-config",
                    childIdentity = "missing-official:"
                        .. tostring(cooldownID),
                    equipSlot = equipSlot,
                    buffSlot = buffSlot,
                    cooldownID = cooldownID,
                    entryKey = entryKey,
                    spellID = displaySpellID,
                    runtimeSpellID = displaySpellID,
                    aliases = YHUD:CopyValue(entry.linkedSpellIds or {}),
                    displayIcon = entry.icon or fallbackIcon,
                    icon = entry.icon or fallbackIcon,
                    displayName = YHUD:GetEntryDisplayName(
                        entry,
                        fallbackName or "cdm:" .. tostring(cooldownID)
                    ),
                    sourceKey = table.concat({
                        "equipment-trigger-preview",
                        tostring(equipSlot),
                        tostring(cooldownID),
                    }, ":"),
                    previewOnly = true,
                    configured = entry.displayCategory == "trackedBuff",
                    reason = entry.displayCategory == "trackedBuff"
                        and "official-unavailable" or "not-configured",
                }
            end
        end
    end

    table.sort(projection, function(left, right)
        if left.equipSlot ~= right.equipSlot then
            return left.equipSlot < right.equipSlot
        end
        local leftKind = EQUIPMENT_TRIGGER_KIND_ORDER[left.kind] or 99
        local rightKind = EQUIPMENT_TRIGGER_KIND_ORDER[right.kind] or 99
        if leftKind ~= rightKind then return leftKind < rightKind end
        if left.buffSlot ~= right.buffSlot then
            return left.buffSlot < right.buffSlot
        end
        return left.cooldownID < right.cooldownID
    end)
    return projection
end

function YHUD:GetEquipmentTriggerProjection(profile)
    return MonitorCatalog:GetEquipmentTriggerProjection(profile)
end

function MonitorCatalog:GetMonitorLayoutProjection(
    profile,
    entry,
    monitor,
    preview,
    claimedSources,
    projectionContext
)
    if type(entry) ~= "table" or type(monitor) ~= "table" then
        return nil
    end
    local bundleKind = entry.bundleKind
    if not bundleKind and entry.sourceType == "racial-bundle" then
        bundleKind = "racial"
    end
    if not bundleKind then return nil end

    local sources
    if bundleKind == (YHUD.EQUIPMENT_AURA_BUNDLE_KIND
        or "equipmentAura") then
        local projection = projectionContext
            and projectionContext.equipmentTriggerProjection or nil
        if not projection then
            projection = self:GetEquipmentTriggerProjection(profile)
            if projectionContext then
                projectionContext.equipmentTriggerProjection = projection
            end
        end
        sources = {}
        for index = 1, #projection do
            local source = projection[index]
            if source.kind == "official-passive"
                or source.kind == "active-timer"
                or (preview == true and source.previewOnly == true) then
                sources[#sources + 1] = source
            end
        end
        if preview == true and #sources == 0 then
            sources[1] = {
                kind = "empty-equipment",
                childIdentity = "empty",
                sourceKey = "equipment-trigger-preview:" .. monitor.id,
                displayIcon = entry.icon,
                displayName = YHUD:GetEntryDisplayName(entry, "Trinkets"),
                previewOnly = true,
            }
        end
    elseif bundleKind == "racial" then
        sources = self:GetEnabledPlayerRacialSources(profile)
    else
        sources = self:GetEnabledSpellBundleSources(profile, bundleKind)
    end

    if type(sources) ~= "table" then return {} end
    if type(claimedSources) ~= "table" then return sources end
    local filtered = {}
    for index = 1, #sources do
        local source = sources[index]
        local canonicalSpellID = type(source) == "table"
            and source.spellID or source
        local sourceKey = type(source) == "table"
            and source.sourceKey
            or (canonicalSpellID and ("spell:" .. tostring(canonicalSpellID)))
        local claim = sourceKey and claimedSources[sourceKey]
        if not claim or not claim.monitor or claim.monitor.id == monitor.id then
            filtered[#filtered + 1] = source
        end
    end
    return filtered
end

function YHUD:GetMonitorLayoutProjection(
    profile,
    entry,
    monitor,
    preview,
    claimedSources,
    projectionContext
)
    return MonitorCatalog:GetMonitorLayoutProjection(
        profile,
        entry,
        monitor,
        preview,
        claimedSources,
        projectionContext
    )
end

function MonitorCatalog:GetEnabledActiveTrinketSources(profile)
    local bundle = type(profile) == "table" and profile.entries
        and profile.entries[EQUIPMENT_AURA_BUNDLE_ENTRY_KEY]
    if not bundle or bundle.bundleEnabled == false
        or not FindActiveMonitor(profile, EQUIPMENT_AURA_BUNDLE_ENTRY_KEY) then
        return {}
    end
    local projection = self:GetEquipmentTriggerProjection(profile)
    local result = {}
    for index = 1, #projection do
        if projection[index].kind == "active-timer" then
            result[#result + 1] = projection[index]
        end
    end
    return result
end

function MonitorCatalog:GetEnabledSpellBundleSources(profile, bundleKind)
    local definition = SPELL_BUNDLE_DEFINITIONS[bundleKind]
    local entry = definition
        and type(profile) == "table"
        and type(profile.entries) == "table"
        and profile.entries[definition.entryKey] or nil
    if not entry
        or entry.bundleEnabled == false
        or not FindActiveMonitor(profile, definition.entryKey) then
        return {}
    end
    local _, options = self:GetSpellBundleOptions(profile, bundleKind)
    return BuildEnabledSpellSourceRecords(options)
end

function MonitorCatalog:SetSpellBundleEnabled(
    draft,
    bundleKind,
    spellID,
    enabled,
    requestedSpecKey
)
    if not ProfileModel:IsDraft(draft) or draft.closed == true then
        return nil, "invalid-draft"
    end
    local definition = SPELL_BUNDLE_DEFINITIONS[bundleKind]
    spellID = IsPositiveInteger(spellID)
    if not definition or not spellID then
        return nil, "invalid-spell-bundle"
    end
    local entry = draft.profile.entries[definition.entryKey]
    if not entry then return nil, "spell-bundle-not-added" end
    local _, _, specKey = GetSpecContext(draft.profile, requestedSpecKey)
    local available = false
    local spellIDs = CollectPlayerBundleSpells(
        draft.profile,
        bundleKind,
        specKey
    )
    for index = 1, #spellIDs do
        if spellIDs[index] == spellID then
            available = true
            break
        end
    end
    if not available then return nil, "spell-bundle-spell-unavailable" end
    entry.bundleEnabled = true
    local saved = MigrateContextData(
        entry,
        "bundleChoicesByContext",
        specKey,
        specKey == rawget(draft.profile, "_yhudSpecKey")
            and "bundleChoices" or nil
    )
    local choices = type(saved[specKey]) == "table" and saved[specKey] or {}
    saved[specKey] = choices
    choices[tostring(spellID)] = enabled ~= false
    ProfileModel:MarkDraftChanged(draft)
    return true
end

function MonitorCatalog:MoveSpellBundleSpell(
    draft,
    bundleKind,
    spellID,
    targetIndex,
    requestedContextKey
)
    if not ProfileModel:IsDraft(draft) or draft.closed == true then
        return nil, "invalid-draft"
    end
    spellID = IsPositiveInteger(spellID)
    targetIndex = IsPositiveInteger(targetIndex)
    if not spellID or not targetIndex then return nil, "invalid-order" end

    local options
    local entry
    local orderTarget
    local contextKey
    local legacyRaceKey
    local legacyClassKey
    local racialContextKey
    if bundleKind == "racial" then
        entry = draft.profile.entries[RACIAL_BUNDLE_ENTRY_KEY]
        racialContextKey, contextKey, legacyRaceKey, legacyClassKey =
            GetRacialContextKeys(draft.profile, requestedContextKey)
        if not entry or not contextKey then return nil, "racial-not-added" end
        spellID = CanonicalizeRacialSpellID(racialContextKey, spellID)
        if not spellID then
            return nil, "spell-bundle-spell-unavailable"
        end
        _, options = self:GetPlayerRacialOptions(
            draft.profile,
            racialContextKey
        )
        orderTarget = {}
    else
        local definition = SPELL_BUNDLE_DEFINITIONS[bundleKind]
        entry = definition and draft.profile.entries[definition.entryKey]
        if not entry then return nil, "spell-bundle-not-added" end
        local _, _, specKey = GetSpecContext(
            draft.profile,
            requestedContextKey
        )
        contextKey = specKey
        _, options = self:GetSpellBundleOptions(
            draft.profile,
            bundleKind,
            contextKey
        )
        orderTarget = {}
    end

    local currentIndex
    for index = 1, #(options or {}) do
        orderTarget[index] = options[index].spellID
        if options[index].spellID == spellID then currentIndex = index end
    end
    if not currentIndex then return nil, "spell-bundle-spell-unavailable" end
    targetIndex = math.max(1, math.min(targetIndex, #orderTarget))
    if currentIndex ~= targetIndex then
        table.remove(orderTarget, currentIndex)
        table.insert(orderTarget, targetIndex, spellID)
    end
    if bundleKind == "racial" then
        local saved = MigrateRacialContextData(
            entry,
            "bundleOrderByContext",
            racialContextKey,
            contextKey,
            legacyRaceKey,
            legacyClassKey
        )
        if type(saved) ~= "table" then
            saved = {}
            entry.bundleOrderByContext = saved
        end
        saved[contextKey] = orderTarget
    else
        local saved = MigrateContextData(
            entry,
            "bundleOrderByContext",
            contextKey,
            contextKey == rawget(draft.profile, "_yhudSpecKey")
                and "bundleOrder" or nil
        )
        saved[contextKey] = orderTarget
    end
    ProfileModel:MarkDraftChanged(draft)
    return orderTarget
end

function MonitorCatalog:SetSpellBundleActive(draft, bundleKind, enabled)
    if not ProfileModel:IsDraft(draft) or draft.closed == true then
        return nil, "invalid-draft"
    end
    local entryKey = bundleKind == "racial"
        and RACIAL_BUNDLE_ENTRY_KEY
        or (bundleKind == EQUIPMENT_AURA_BUNDLE_KIND
            and EQUIPMENT_AURA_BUNDLE_ENTRY_KEY)
        or (SPELL_BUNDLE_DEFINITIONS[bundleKind]
            and SPELL_BUNDLE_DEFINITIONS[bundleKind].entryKey)
    local entry = entryKey and draft.profile.entries[entryKey]
    if not entry then return nil, "spell-bundle-not-added" end
    entry.bundleEnabled = enabled == true
    if bundleKind == "racial" then
        draft.profile.racials = type(draft.profile.racials) == "table"
            and draft.profile.racials or {}
        draft.profile.racials.enabled = enabled == true
    end
    ProfileModel:MarkDraftChanged(draft)
    return true
end

function MonitorCatalog:AddItem(draft, groupId, itemID, options)
    if not ProfileModel:IsDraft(draft) or draft.closed == true then
        return nil, "invalid-draft"
    end
    itemID = IsPositiveInteger(itemID)
    if not itemID then return nil, "invalid-item-id" end

    options = type(options) == "table" and options or {}
    local item = ResolveItem(
        itemID,
        options.knownPreset == true,
        options.fallbackName
    )
    if not item.found then return nil, "item-not-found" end

    local entryKey = "item:" .. tostring(itemID)
    local staged = ProfileModel:BeginDraft(draft.profile, {
        combat = draft.combat == true,
        specKey = draft.specKey,
    })
    if type(options.legacyItemIDs) == "table" then
        local legacyEntryKeys = {}
        for legacyItemID in pairs(options.legacyItemIDs) do
            local legacyKey = "item:" .. tostring(legacyItemID)
            if staged.profile.entries[legacyKey] then
                legacyEntryKeys[legacyKey] = true
            end
        end
        if next(legacyEntryKeys) then
            local familyMonitorId
            local duplicateMonitorIds = {}
            for monitorId, monitor in pairs(staged.profile.monitors) do
                if legacyEntryKeys[monitor.entryKey] then
                    if not familyMonitorId then
                        monitor.entryKey = entryKey
                        monitor.sourceKey = entryKey
                        familyMonitorId = monitorId
                        staged.changed = true
                    else
                        duplicateMonitorIds[#duplicateMonitorIds + 1] =
                            monitorId
                    end
                end
            end
            for index = 1, #duplicateMonitorIds do
                ProfileModel:RemoveMonitor(
                    staged,
                    duplicateMonitorIds[index]
                )
            end
            for legacyKey in pairs(legacyEntryKeys) do
                staged.profile.entries[legacyKey] = nil
                if staged.profile._yhudScopeByEntry then
                    staged.profile._yhudScopeByEntry[legacyKey] = nil
                end
            end
        end
    end
    local existing = staged.profile.entries[entryKey]
    if existing then
        if existing.sourceKey ~= entryKey
            or existing.sourceType ~= "item-cooldown" then
            return nil, "entry-conflict"
        end
        if options.itemIDs then
            existing.itemIds = YHUD:CopyValue(options.itemIDs)
        end
        if options.legacyItemIDs then
            existing.legacyItemIds = YHUD:CopyValue(options.legacyItemIDs)
        end
        SetEntryPresentation(
            staged,
            entryKey,
            options.name or item.name,
            item.icon
        )
    else
        local added, code = ProfileModel:AddEntry(staged, entryKey, {
            sourceKey = entryKey,
            sourceType = "item-cooldown",
            semantic = "cooldown",
            origin = options.origin == "preset" and "preset" or "custom",
            applicability = { kind = "all" },
            itemId = itemID,
            itemIds = options.itemIDs and YHUD:CopyValue(options.itemIDs) or nil,
            legacyItemIds = options.legacyItemIDs
                and YHUD:CopyValue(options.legacyItemIDs) or nil,
            name = options.name or item.name,
            icon = item.icon,
            contract = {
                capability = "display",
                view = "self",
                group = "free",
                style = "static",
                fallback = "hide",
                status = "verified",
            },
        })
        if not added then return nil, code end
    end

    local result, code = PlaceEntry(
        staged,
        groupId,
        entryKey,
        GetTargetView(staged.profile, groupId),
        "custom"
    )
    if not result then return nil, code end
    return AdoptResult(draft, staged, result)
end

function MonitorCatalog:AddCustomItem(draft, groupId, itemID)
    return self:AddItem(draft, groupId, itemID, {
        origin = "custom",
    })
end

function MonitorCatalog:AddCustomAura(
    draft,
    specKey,
    groupId,
    spellID,
    scopeKey
)
    if not ProfileModel:IsDraft(draft) or draft.closed == true then
        return nil, "invalid-draft"
    end
    if specKey ~= draft.specKey then return nil, "spec-context-changed" end
    if scopeKey ~= YHUD.FILTERED_AURA_SCOPE_PLAYER_HELPFUL
        and scopeKey ~= YHUD.FILTERED_AURA_SCOPE_TARGET_HARMFUL then
        return nil, "invalid-aura-scope"
    end

    spellID = IsPositiveInteger(spellID)
    if not spellID then return nil, "invalid-spell-id" end
    local spell = ResolveSpell(spellID)
    local api = YUI.API and YUI.API.Spell
    local info = api and api.GetInfo and api.GetInfo(spellID)
    if not (info and info.name) then return nil, "spell-not-found" end

    local targetDebuff = scopeKey
        == YHUD.FILTERED_AURA_SCOPE_TARGET_HARMFUL
    local entryKey = targetDebuff
        and ("aura:target:harmful-player:" .. tostring(spellID))
        or ("aura:player:helpful:" .. tostring(spellID))
    local sourceKey = entryKey
    local labelKey = targetDebuff
        and "designer.custom_aura_target"
        or "designer.custom_aura_self"
    local staged = ProfileModel:BeginDraft(draft.profile, {
        combat = draft.combat == true,
        specKey = specKey,
    })
    local existing = staged.profile.entries[entryKey]
    if existing then
        if existing.sourceKey ~= sourceKey
            or existing.sourceType ~= YHUD.PLAYER_AURA_SOURCE_TYPE
            or existing.filteredAuraScope ~= scopeKey then
            return nil, "entry-conflict"
        end
        existing.spellId = spellID
        existing.spellIds = { spellID }
        existing.semantic = "buff"
        existing.origin = "custom"
        existing.sourceIdentity = sourceKey
        existing.filteredAuraScope = scopeKey
        existing.labelKey = labelKey
        SetEntryPresentation(staged, entryKey, spell.name, spell.icon)
        ProfileModel:MarkDraftChanged(staged)
    else
        local added, code = ProfileModel:AddEntry(staged, entryKey, {
            sourceKey = sourceKey,
            sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
            sourceIdentity = sourceKey,
            semantic = "buff",
            compatibleViews = {
                icon = true,
                bar = true,
                ring = true,
            },
            origin = "custom",
            filteredAuraScope = scopeKey,
            spellId = spellID,
            spellIds = { spellID },
            name = spell.name,
            icon = spell.icon,
            labelKey = labelKey,
            contract = {
                capability = "aura-display",
                view = targetDebuff and "target" or "self",
                group = "free",
                style = "full",
                fallback = "hide",
                status = "verified",
            },
        })
        if not added then return nil, code end
    end

    local result, code = PlaceEntry(
        staged,
        groupId,
        entryKey,
        GetTargetView(staged.profile, groupId),
        "custom"
    )
    if not result then return nil, code end
    return AdoptResult(draft, staged, result)
end

function MonitorCatalog:AddPresetPlayerAura(
    draft,
    specKey,
    groupId,
    displaySpellID,
    spellIDs,
    options
)
    if not ProfileModel:IsDraft(draft) or draft.closed == true then
        return nil, "invalid-draft"
    end
    if specKey ~= draft.specKey then return nil, "spec-context-changed" end
    options = type(options) == "table" and options or {}
    displaySpellID = IsPositiveInteger(displaySpellID)
    if not displaySpellID then return nil, "invalid-spell-id" end

    local spell = ResolveSpell(displaySpellID)
    local api = YUI.API and YUI.API.Spell
    local info = api and api.GetInfo and api.GetInfo(displaySpellID)
    if not (info and info.name) then return nil, "spell-not-found" end

    local aliases = {}
    local seen = {}
    for index = 1, #(type(spellIDs) == "table" and spellIDs or {}) do
        local spellID = IsPositiveInteger(spellIDs[index])
        if spellID and not seen[spellID] then
            aliases[#aliases + 1] = spellID
            seen[spellID] = true
        end
    end
    if not seen[displaySpellID] then
        aliases[#aliases + 1] = displaySpellID
    end
    if #aliases == 0 then return nil, "invalid-spell-id" end

    local contentScope = YHUD.CONTENT_SCOPE_SPEC
    local applicability = nil
    local entryKey = type(options.entryKey) == "string"
            and options.entryKey ~= "" and options.entryKey
        or ("buff-aura:" .. tostring(displaySpellID))
    local sourceKey = type(options.sourceKey) == "string"
            and options.sourceKey ~= "" and options.sourceKey
        or ("aura:" .. entryKey)
    local staged = ProfileModel:BeginDraft(draft.profile, {
        combat = draft.combat == true,
        specKey = specKey,
    })
    local existing = staged.profile.entries[entryKey]
    if existing then
        if existing.sourceKey ~= sourceKey
            or existing.sourceType ~= YHUD.PLAYER_AURA_SOURCE_TYPE then
            return nil, "entry-conflict"
        end
        existing.spellId = displaySpellID
        existing.spellIds = YHUD:CopyValue(aliases)
        existing.sourceIdentity = options.sourceIdentity
        existing.semantic = "buff"
        existing.nameKey = options.nameKey
        existing.origin = "preset"
        existing.presetKey = options.presetKey
            or options.presetId or entryKey
        existing.crossSpecMaterialization =
            options.crossSpecMaterialization or "immediate"
        existing.crossSpecEligibility = options.crossSpecEligibility
            and YHUD:CopyValue(options.crossSpecEligibility) or nil
        existing.applicability = applicability
            and YHUD:CopyValue(applicability) or nil
        existing.contentScope = contentScope
        SetEntryPresentation(
            staged,
            entryKey,
            options.name or spell.name,
            spell.icon
        )
        staged.changed = true
    else
        local added, code = ProfileModel:AddEntry(staged, entryKey, {
            sourceKey = sourceKey,
            sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE,
            sourceIdentity = options.sourceIdentity,
            semantic = "buff",
            compatibleViews = {
                icon = true,
                bar = true,
                ring = true,
            },
            origin = "preset",
            presetKey = options.presetKey or options.presetId or entryKey,
            crossSpecMaterialization =
                options.crossSpecMaterialization or "immediate",
            crossSpecEligibility = options.crossSpecEligibility
                and YHUD:CopyValue(options.crossSpecEligibility) or nil,
            contentScope = contentScope,
            applicability = applicability,
            spellId = displaySpellID,
            spellIds = YHUD:CopyValue(aliases),
            name = options.name or spell.name,
            nameKey = options.nameKey,
            icon = spell.icon,
            contract = {
                capability = "aura-display",
                view = "self",
                group = "free",
                style = "full",
                fallback = "hide",
                status = "verified",
            },
        })
        if not added then return nil, code end
    end

    local result, code = PlaceEntry(
        staged,
        groupId,
        entryKey,
        GetTargetView(staged.profile, groupId),
        "preset"
    )
    if not result then return nil, code end
    return AdoptResult(draft, staged, result)
end

local function NormalizeTriggerSpellIDs(values)
    if type(values) ~= "table" then return nil end
    local result = {}
    local seen = {}
    for index = 1, #values do
        local spellID = IsPositiveInteger(values[index])
        if not spellID then return nil end
        if not seen[spellID] then
            seen[spellID] = true
            result[#result + 1] = spellID
        end
    end
    return #result > 0 and result or nil
end

function MonitorCatalog:AddPresetSpellEventWindow(
    draft,
    specKey,
    groupId,
    option
)
    if not ProfileModel:IsDraft(draft) or draft.closed == true then
        return nil, "invalid-draft"
    end
    if specKey ~= draft.specKey then return nil, "spec-context-changed" end
    if specKey ~= BLOOD_DEATH_KNIGHT_SPEC_KEY then
        return nil, "preset-context-mismatch"
    end
    option = type(option) == "table" and option or {}

    local spellID = IsPositiveInteger(option.spellID)
    local triggerSpellIDs = NormalizeTriggerSpellIDs(option.triggerSpellIDs)
    local durationSeconds = Security and Security.SafeNumber
        and Security.SafeNumber(option.durationSeconds)
        or tonumber(option.durationSeconds)
    if not BLOOD_BOIL_WINDOW_PRESET then return nil, "unsupported-preset-client" end
    if spellID ~= BLOOD_BOIL_WINDOW_PRESET.displaySpellID
        or not triggerSpellIDs
        or #triggerSpellIDs ~= 1
        or triggerSpellIDs[1]
            ~= BLOOD_BOIL_WINDOW_PRESET.triggerSpellIDs[1]
        or durationSeconds ~= BLOOD_BOIL_WINDOW_PRESET.durationSeconds
        or option.presetId ~= BLOOD_BOIL_WINDOW_PRESET.presetId
        or option.entryKey ~= BLOOD_BOIL_WINDOW_PRESET.entryKey
        or option.sourceKey ~= BLOOD_BOIL_WINDOW_PRESET.sourceKey then
        return nil, "preset-definition-mismatch"
    end

    local spell = ResolveSpell(spellID)
    local api = YUI.API and YUI.API.Spell
    local info = api and api.GetInfo and api.GetInfo(spellID)
    if not (spell and info and info.name) then return nil, "spell-not-found" end

    local entryKey = BLOOD_BOIL_WINDOW_PRESET.entryKey
    local sourceKey = BLOOD_BOIL_WINDOW_PRESET.sourceKey

    local compatibleViews = {
        icon = true,
        bar = true,
        ring = true,
    }
    local contract = {
        capability = "timed-display",
        view = "self",
        group = "free",
        style = "full",
        fallback = "hide",
        status = "verified",
    }
    local name = T(
        BLOOD_BOIL_WINDOW_PRESET.nameKey,
        BLOOD_BOIL_WINDOW_PRESET.fallbackName
    )
    local staged = ProfileModel:BeginDraft(draft.profile, {
        combat = draft.combat == true,
        specKey = specKey,
    })
    local existing = staged.profile.entries[entryKey]
    if existing then
        if existing.sourceKey ~= sourceKey
            or existing.sourceType ~= SPELL_EVENT_WINDOW_SOURCE_TYPE then
            return nil, "entry-conflict"
        end
        existing.semantic = "buff"
        existing.contentScope = YHUD.CONTENT_SCOPE_SPEC
        existing.applicability = nil
        existing.origin = "preset"
        existing.presetId = BLOOD_BOIL_WINDOW_PRESET.presetId
        existing.presetKey = BLOOD_BOIL_WINDOW_PRESET.presetId
        existing.crossSpecMaterialization = "immediate"
        existing.crossSpecEligibility = { classFile = "DEATHKNIGHT" }
        existing.spellId = spellID
        existing.triggerSpellIds = YHUD:CopyValue(triggerSpellIDs)
        existing.durationSeconds = durationSeconds
        existing.compatibleViews = compatibleViews
        existing.nameKey = BLOOD_BOIL_WINDOW_PRESET.nameKey
        existing.presetLabelKey = BLOOD_BOIL_WINDOW_PRESET.presetLabelKey
        existing.labelKey = "designer.monitor.type_event_window"
        existing.contract = contract
        SetEntryPresentation(staged, entryKey, name, spell.icon)
        ProfileModel:MarkDraftChanged(staged)
    else
        local added, code = ProfileModel:AddEntry(staged, entryKey, {
            sourceKey = sourceKey,
            sourceType = SPELL_EVENT_WINDOW_SOURCE_TYPE,
            semantic = "buff",
            contentScope = YHUD.CONTENT_SCOPE_SPEC,
            origin = "preset",
            presetId = BLOOD_BOIL_WINDOW_PRESET.presetId,
            presetKey = BLOOD_BOIL_WINDOW_PRESET.presetId,
            crossSpecMaterialization = "immediate",
            crossSpecEligibility = { classFile = "DEATHKNIGHT" },
            spellId = spellID,
            triggerSpellIds = YHUD:CopyValue(triggerSpellIDs),
            durationSeconds = durationSeconds,
            compatibleViews = compatibleViews,
            name = name,
            nameKey = BLOOD_BOIL_WINDOW_PRESET.nameKey,
            presetLabelKey = BLOOD_BOIL_WINDOW_PRESET.presetLabelKey,
            icon = spell.icon,
            labelKey = "designer.monitor.type_event_window",
            contract = contract,
        })
        if not added then return nil, code end
    end

    local result, code = PlaceEntry(
        staged,
        groupId,
        entryKey,
        GetTargetView(staged.profile, groupId),
        "preset"
    )
    if not result then return nil, code end
    return AdoptResult(draft, staged, result)
end

function MonitorCatalog:AddCustomBuffTimer(
    draft,
    specKey,
    groupId,
    spellID,
    durationSeconds,
    options
)
    if not YHUD:IsStableSpecKey(specKey) then
        durationSeconds = spellID
        spellID = groupId
        groupId = specKey
        specKey = draft and draft.specKey
    end
    if not ProfileModel:IsDraft(draft) or draft.closed == true then
        return nil, "invalid-draft"
    end
    if specKey ~= draft.specKey then return nil, "spec-context-changed" end
    options = type(options) == "table" and options or {}

    spellID = IsPositiveInteger(spellID)
    local security = YUI.API and YUI.API.Security
    if security and security.SafeNumber then
        durationSeconds = security.SafeNumber(durationSeconds)
    elseif type(durationSeconds) ~= "number" then
        durationSeconds = nil
    end
    if not spellID then return nil, "invalid-spell-id" end
    if not durationSeconds
        or durationSeconds ~= durationSeconds
        or durationSeconds < 0.1
        or durationSeconds > 3600 then
        return nil, "invalid-buff-duration"
    end

    local spell = ResolveSpell(spellID)
    local api = YUI.API and YUI.API.Spell
    local info = api and api.GetInfo and api.GetInfo(spellID)
    if not (info and info.name) then return nil, "spell-not-found" end

    local origin = options.origin == "preset" and "preset" or "custom"
    local applicability = origin == "preset"
        and { kind = "all" }
        or YHUD:NormalizeApplicability(nil, {
            sourceType = YHUD.CAST_BUFF_TIMER_SOURCE_TYPE,
            origin = origin,
        }, specKey)
    local entryKey = type(options.entryKey) == "string"
            and options.entryKey ~= ""
            and options.entryKey
        or ("buff-timer:" .. tostring(spellID))
    entryKey = YHUD:QualifySharedEntryKey(entryKey, applicability)
    local sourceKey = type(options.sourceKey) == "string"
            and options.sourceKey ~= ""
            and options.sourceKey
        or entryKey
    local itemIDs = type(options.itemIDs) == "table"
        and options.itemIDs or nil
    local legacyItemIDs = type(options.legacyItemIDs) == "table"
        and options.legacyItemIDs or nil
    local legacySpellIDs = type(options.legacySpellIDs) == "table"
        and options.legacySpellIDs or nil
    local staged = ProfileModel:BeginDraft(draft.profile, {
        combat = draft.combat == true,
        specKey = specKey,
    })
    local existing = staged.profile.entries[entryKey]
    if existing then
        if existing.sourceKey ~= sourceKey
            or existing.sourceType ~= YHUD.CAST_BUFF_TIMER_SOURCE_TYPE then
            return nil, "entry-conflict"
        end
        existing.durationSeconds = durationSeconds
        existing.semantic = "buff"
        existing.sourceIdentity = options.sourceIdentity
        existing.triggerSpellIds = options.triggerSpellIDs
            and YHUD:CopyValue(options.triggerSpellIDs) or nil
        existing.itemIds = itemIDs and YHUD:CopyValue(itemIDs) or nil
        existing.legacyItemIds = legacyItemIDs
            and YHUD:CopyValue(legacyItemIDs) or nil
        existing.legacySpellIds = legacySpellIDs
            and YHUD:CopyValue(legacySpellIDs) or nil
        existing.nameKey = options.nameKey
        existing.origin = origin
        existing.applicability = YHUD:CopyValue(applicability)
        existing.contentScope = YHUD.CONTENT_SCOPE_SPEC
        SetEntryPresentation(
            staged,
            entryKey,
            options.name or spell.name,
            options.icon or spell.icon
        )
        staged.changed = true
    else
        local legacyEntryKeys = {}
        if legacySpellIDs then
            for legacySpellID, _ in pairs(legacySpellIDs) do
                local legacyKey = "buff-timer:" .. tostring(legacySpellID)
                if staged.profile.entries[legacyKey] then
                    legacyEntryKeys[legacyKey] = true
                end
            end
        end
        if next(legacyEntryKeys) then
            local familyMonitorId
            local duplicateMonitorIds = {}
            for monitorId, monitor in pairs(staged.profile.monitors) do
                if legacyEntryKeys[monitor.entryKey] then
                    if not familyMonitorId then
                        monitor.entryKey = entryKey
                        monitor.sourceKey = sourceKey
                        familyMonitorId = monitorId
                        staged.changed = true
                    else
                        duplicateMonitorIds[#duplicateMonitorIds + 1] =
                            monitorId
                    end
                end
            end
            for index = 1, #duplicateMonitorIds do
                ProfileModel:RemoveMonitor(
                    staged,
                    duplicateMonitorIds[index]
                )
            end
            for legacyKey in pairs(legacyEntryKeys) do
                staged.profile.entries[legacyKey] = nil
                if staged.profile._yhudScopeByEntry then
                    staged.profile._yhudScopeByEntry[legacyKey] = nil
                end
            end
        end
        local added, code = ProfileModel:AddEntry(staged, entryKey, {
            sourceKey = sourceKey,
            sourceType = YHUD.CAST_BUFF_TIMER_SOURCE_TYPE,
            semantic = "buff",
            compatibleViews = {
                icon = true,
                bar = true,
                ring = true,
            },
            origin = origin,
            applicability = applicability,
            spellId = spellID,
            sourceIdentity = options.sourceIdentity,
            triggerSpellIds = options.triggerSpellIDs
                and YHUD:CopyValue(options.triggerSpellIDs) or nil,
            itemIds = itemIDs and YHUD:CopyValue(itemIDs) or nil,
            legacyItemIds = legacyItemIDs
                and YHUD:CopyValue(legacyItemIDs) or nil,
            legacySpellIds = legacySpellIDs
                and YHUD:CopyValue(legacySpellIDs) or nil,
            durationSeconds = durationSeconds,
            name = options.name or spell.name,
            nameKey = options.nameKey,
            icon = options.icon or spell.icon,
            labelKey = "designer.timed_buff",
            contract = {
                capability = "timed-display",
                view = "self",
                group = "free",
                style = "full",
                fallback = "hide",
                status = "verified",
            },
        })
        if not added then return nil, code end
    end

    local result, code = PlaceEntry(
        staged,
        groupId,
        entryKey,
        GetTargetView(staged.profile, groupId),
        "custom"
    )
    if not result then return nil, code end
    return AdoptResult(draft, staged, result)
end

local function MonitorIdentityDescriptor(profile, monitorId)
    local monitor = type(profile) == "table"
        and type(profile.monitors) == "table"
        and profile.monitors[monitorId]
    local entry = monitor
        and type(profile.entries) == "table"
        and profile.entries[monitor.entryKey]
    if not monitor or not entry then return nil end
    if entry.origin == "official-cdm" then return nil end

    if entry.sourceType == "item-cooldown" and entry.itemId then
        return {
            kind = "item",
            value = entry.itemId,
        }
    end

    if entry.sourceType == YHUD.PLAYER_AURA_SOURCE_TYPE
        and entry.origin == "custom"
        and (entry.filteredAuraScope
                == YHUD.FILTERED_AURA_SCOPE_PLAYER_HELPFUL
            or entry.filteredAuraScope
                == YHUD.FILTERED_AURA_SCOPE_TARGET_HARMFUL)
        and entry.spellId then
        return {
            kind = "aura",
            value = entry.spellId,
            auraScope = entry.filteredAuraScope,
        }
    end

    local spellID = entry.overrideSpellId or entry.spellId
    if not spellID then return nil end
    if entry.sourceType == "spell-cooldown"
        or entry.sourceType == YHUD.CAST_BUFF_TIMER_SOURCE_TYPE then
        return {
            kind = "spell",
            value = spellID,
            durationSeconds = entry.sourceType
                    == YHUD.CAST_BUFF_TIMER_SOURCE_TYPE
                and entry.durationSeconds or nil,
        }
    end
    return nil
end

function MonitorCatalog:GetEditableMonitorIdentity(profile, monitorId)
    local descriptor = MonitorIdentityDescriptor(profile, monitorId)
    return descriptor and YHUD:CopyValue(descriptor) or nil
end

local function GroupMonitorIndex(group, monitorId)
    for index = 1, #(group and group.monitors or {}) do
        if group.monitors[index] == monitorId then return index end
    end
    return nil
end

local function RemoveUnusedCustomEntry(profile, entryKey)
    local entry = profile.entries and profile.entries[entryKey]
    if not entry or entry.origin == "official-cdm" then return end
    for _, monitor in pairs(profile.monitors or {}) do
        if monitor.entryKey == entryKey then return end
    end
    profile.entries[entryKey] = nil
    local scopeByEntry = rawget(profile, "_yhudScopeByEntry")
    if scopeByEntry then scopeByEntry[entryKey] = nil end
end

function MonitorCatalog:ReplaceMonitorIdentity(
    draft,
    monitorId,
    value,
    durationSeconds
)
    if not ProfileModel:IsDraft(draft) or draft.closed == true then
        return nil, "invalid-draft"
    end
    local descriptor = MonitorIdentityDescriptor(draft.profile, monitorId)
    if not descriptor then return nil, "monitor-identity-readonly" end
    value = IsPositiveInteger(value)
    if not value then return nil, "invalid-monitor-id" end
    if descriptor.durationSeconds ~= nil then
        local security = YUI.API and YUI.API.Security
        if security and security.SafeNumber then
            durationSeconds = security.SafeNumber(durationSeconds)
        elseif type(durationSeconds) ~= "number" then
            durationSeconds = nil
        end
        if not durationSeconds
            or durationSeconds ~= durationSeconds
            or durationSeconds < 0.1
            or durationSeconds > 3600 then
            return nil, "invalid-buff-duration"
        end
    end
    if value == descriptor.value
        and (descriptor.durationSeconds == nil
            or durationSeconds == descriptor.durationSeconds) then
        return {
            action = "current",
            monitor = YHUD:CopyValue(draft.profile.monitors[monitorId]),
            groupId = draft.profile.monitors[monitorId].groupId,
        }
    end

    if value == descriptor.value and descriptor.durationSeconds ~= nil then
        return self:AddCustomBuffTimer(
            draft,
            draft.specKey,
            draft.profile.monitors[monitorId].groupId,
            value,
            durationSeconds
        )
    end

    local staged = ProfileModel:BeginDraft(draft.profile, {
        combat = draft.combat == true,
        specKey = draft.specKey,
    })
    local oldMonitor = staged.profile.monitors[monitorId]
    local oldEntry = oldMonitor
        and staged.profile.entries[oldMonitor.entryKey]
    local oldGroup = oldMonitor
        and staged.profile.groups.items[oldMonitor.groupId]
    local oldIndex = GroupMonitorIndex(oldGroup, monitorId)
    if not oldMonitor or not oldEntry or not oldIndex then
        return nil, "monitor-not-found"
    end
    local oldEntryKey = oldMonitor.entryKey
    local oldLane = rawget(staged.profile, "_yhudLaneByMonitor")
    oldLane = oldLane and oldLane[monitorId]

    local result, code
    if descriptor.kind == "item" then
        result, code = self:AddCustomItem(
            staged,
            oldMonitor.groupId,
            value
        )
    elseif descriptor.kind == "aura" then
        result, code = self:AddCustomAura(
            staged,
            staged.specKey,
            oldMonitor.groupId,
            value,
            descriptor.auraScope
        )
    elseif oldEntry.sourceType == YHUD.CAST_BUFF_TIMER_SOURCE_TYPE then
        result, code = self:AddCustomBuffTimer(
            staged,
            staged.specKey,
            oldMonitor.groupId,
            value,
            durationSeconds or oldEntry.durationSeconds
        )
    else
        result, code = self:AddCustomSpell(
            staged,
            oldMonitor.groupId,
            value
        )
    end
    if not result then return nil, code end
    if result.action ~= "add" then
        return nil, "monitor-identity-conflict"
    end

    local replacementId = result.monitor and result.monitor.id
    local replacement = replacementId
        and staged.profile.monitors[replacementId]
    local replacementEntry = replacement
        and staged.profile.entries[replacement.entryKey]
    if not replacement or not replacementEntry then
        return nil, "monitor-not-found"
    end
    replacement.enabled = oldMonitor.enabled
    replacement.visibilityMode = oldMonitor.visibilityMode
    replacement.stateEffects = YHUD:NormalizeMonitorStateEffects(
        YHUD:CopyValue(oldMonitor.stateEffects),
        replacementEntry
    )
    replacement.appearanceOverride =
        YHUD:NormalizeMonitorAppearanceOverride(
            YHUD:CopyValue(oldMonitor.appearanceOverride)
        )
    replacement.glow = YHUD:CopyValue(oldMonitor.glow)
    replacement.sound = YHUD:NormalizeMonitorSound(
        YHUD:CopyValue(oldMonitor.sound)
    )

    local removed
    removed, code = ProfileModel:RemoveMonitor(staged, monitorId)
    if not removed then return nil, code end
    local targetLane = YHUD.CONTENT_LANE_SPEC
    local moved
    moved, code = ProfileModel:MoveMonitor(
        staged,
        replacementId,
        oldMonitor.groupId,
        oldIndex,
        oldMonitor.view,
        targetLane
    )
    if not moved then return nil, code end
    RemoveUnusedCustomEntry(staged.profile, oldEntryKey)
    staged.changed = true

    return AdoptResult(draft, staged, {
        action = "replace",
        monitor = moved,
    })
end

local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local CDMImport = {}
YHUD.CDMImport = CDMImport

local PREVIEW_MARKER = "yhud-cdm-import-preview-v1"

local DISPLAY_CATEGORIES = {
    essential = true,
    utility = true,
    trackedBuff = true,
    trackedBar = true,
}

local SOURCE_CATEGORIES = {
    essential = true,
    utility = true,
    trackedBuff = true,
    trackedBar = true,
    equipSlotEssential = true,
    equipSlotTracked = true,
    specAgnosticEssential = true,
    specAgnosticTracked = true,
}

local BUFF_SOURCE_CATEGORIES = {
    trackedBuff = true,
    trackedBar = true,
    equipSlotTracked = true,
    specAgnosticTracked = true,
}

local PRESENTATION_NAMES = {
    healthstone = {
        key = "designer.cdm.healthstone",
        fallback = "治疗石",
    },
    combatPotion = {
        key = "designer.cdm.combat_potion",
        fallback = "战斗药水",
    },
    healthPotion = {
        key = "designer.cdm.health_potion",
        fallback = "生命药水",
    },
}

local function IsPositiveInteger(value)
    return type(value) == "number"
        and value == math.floor(value)
        and value > 0
end

local function IsNonNegativeInteger(value)
    return type(value) == "number"
        and value == math.floor(value)
        and value >= 0
end

local function ClonePlain(value, seen, depth)
    local valueType = type(value)
    if valueType == "nil"
        or valueType == "boolean"
        or valueType == "number"
        or valueType == "string" then
        return value
    end
    if valueType ~= "table" then return nil, "invalid-metadata" end
    depth = (depth or 0) + 1
    if depth > 24 then return nil, "invalid-metadata" end
    seen = seen or {}
    if seen[value] then return nil, "invalid-metadata" end
    seen[value] = true
    local copy = {}
    for key, child in pairs(value) do
        local keyType = type(key)
        if keyType ~= "string" and keyType ~= "number" then
            seen[value] = nil
            return nil, "invalid-metadata"
        end
        local cloned, code = ClonePlain(child, seen, depth)
        if code then
            seen[value] = nil
            return nil, code
        end
        copy[key] = cloned
    end
    seen[value] = nil
    return copy
end

local function EqualValue(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not EqualValue(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function ContractForCategory(displayCategory)
    return {
        capability = displayCategory and "native-enhanced" or "meta",
        view = displayCategory and "native" or nil,
        group = "free",
        style = "static",
        fallback = "hide",
        status = "verified",
    }
end

local function OptionalBoolean(value)
    if type(value) == "boolean" then return value end
    return nil
end

local function BuildEntry(
    existing,
    row,
    sourceCategory,
    displayCategory,
    cooldownId
)
    local entry = type(existing) == "table" and ClonePlain(existing) or {}
    if not entry then return nil, "invalid-existing-entry" end

    local entryKey = "cdm:" .. tostring(cooldownId)
    entry.entryKey = entryKey
    entry.origin = "official-cdm"
    entry.officialCategory = displayCategory
    entry.sourceCategory = sourceCategory
    entry.displayCategory = displayCategory
    entry.semantic = BUFF_SOURCE_CATEGORIES[sourceCategory]
        and "buff" or "cooldown"
    entry.cooldownId = cooldownId
    entry.order = IsPositiveInteger(row.order) and row.order or nil
    entry.spellId = IsPositiveInteger(row.spellID) and row.spellID or nil
    entry.spellCategoryId = IsPositiveInteger(row.spellCategoryID)
        and row.spellCategoryID or nil
    entry.presentationKind = type(row.presentationKind) == "string"
        and row.presentationKind or nil
    entry.overrideSpellId = IsPositiveInteger(row.overrideSpellID)
        and row.overrideSpellID or nil
    entry.overrideTooltipSpellId =
        IsPositiveInteger(row.overrideTooltipSpellID)
        and row.overrideTooltipSpellID or nil
    entry.equipSlot = IsPositiveInteger(row.equipSlot)
        and row.equipSlot or nil
    entry.buffSlot = IsPositiveInteger(row.buffSlot)
        and row.buffSlot or nil
    entry.sourceCategoryId = IsNonNegativeInteger(row.sourceCategoryID)
        and row.sourceCategoryID or nil
    entry.displayCategoryId = IsNonNegativeInteger(row.displayCategoryID)
        and row.displayCategoryID or nil
    entry.linkedSpellIds = nil
    if row.linkedSpellIDs ~= nil then
        local linkedSpellIds, code = ClonePlain(row.linkedSpellIDs)
        if not linkedSpellIds then return nil, code end
        entry.linkedSpellIds = linkedSpellIds
    end
    entry.selfAura = OptionalBoolean(row.selfAura)
    entry.hasAura = OptionalBoolean(row.hasAura)
    entry.canUseAuraForCooldown = OptionalBoolean(
        row.canUseAuraForCooldown
    )
    entry.charges = OptionalBoolean(row.charges)
    entry.isKnown = OptionalBoolean(row.isKnown)
    entry.isInvisible = OptionalBoolean(row.isInvisible)
    local spellAPI = YUI.API and YUI.API.Spell
    local itemAPI = YUI.API and YUI.API.Item
    local presentation = PRESENTATION_NAMES[entry.presentationKind]
    local displaySpellId = entry.overrideTooltipSpellId
        or entry.overrideSpellId
        or entry.spellId
    local linkedSpellIds = {}
    for index = 1, #(entry.linkedSpellIds or {}) do
        local linkedSpellId = entry.linkedSpellIds[index]
        if IsPositiveInteger(linkedSpellId) then
            linkedSpellIds[#linkedSpellIds + 1] = linkedSpellId
        end
    end
    local fallbackSpellId = #linkedSpellIds > 0 and linkedSpellIds[1] or nil
    local equipmentName
    local equipmentIcon
    if #linkedSpellIds > 1
        and (entry.equipSlot == 13 or entry.equipSlot == 14)
        and itemAPI then
        local itemID = itemAPI.GetInventoryItemID
            and itemAPI.GetInventoryItemID("player", entry.equipSlot)
        if IsPositiveInteger(itemID) then
            local name = itemAPI.GetName and itemAPI.GetName(itemID)
            local icon = itemAPI.GetInventoryItemTexture
                and itemAPI.GetInventoryItemTexture("player", entry.equipSlot)
            equipmentName = type(name) == "string" and name ~= ""
                and name or nil
            equipmentIcon = (type(icon) == "number" or type(icon) == "string")
                and icon or nil
        end
    end
    local displayName = presentation
        and YHUD:T(presentation.key, presentation.fallback)
        or (displaySpellId and spellAPI
        and spellAPI.GetName
        and spellAPI.GetName(displaySpellId))
        or equipmentName
        or (fallbackSpellId and spellAPI
        and spellAPI.GetName
        and spellAPI.GetName(fallbackSpellId))
    if type(displayName) == "string" and displayName ~= "" then
        entry.name = displayName
    end
    local displayIcon = row.presentationIcon
        or (displaySpellId and spellAPI
        and spellAPI.GetTexture
        and spellAPI.GetTexture(displaySpellId))
        or equipmentIcon
        or (fallbackSpellId and spellAPI
        and spellAPI.GetTexture
        and spellAPI.GetTexture(fallbackSpellId))
    if displayIcon ~= nil then
        entry.icon = displayIcon
    end
    entry.flags = nil
    if row.flags ~= nil then
        local flags, code = ClonePlain(row.flags)
        if not flags then return nil, code end
        entry.flags = flags
    end
    entry.contract = ContractForCategory(displayCategory)

    entry.runtimeSpellId = nil
    entry.chargeSpellId = nil
    if entry.semantic == "buff" then
        entry.sourceKey = "aura:cdm:" .. tostring(cooldownId)
        entry.sourceType = YHUD.PLAYER_AURA_SOURCE_TYPE
            or "yhud.player-aura"
    else
        entry.sourceKey = nil
        entry.sourceType = nil
    end
    entry.evidenceStatus = "verified"
    return entry
end

local function ResolveScopedProfile(profile, specKey, copy)
    specKey = specKey
        or (type(profile) == "table" and rawget(profile, "_yhudSpecKey"))
        or YHUD:GetCurrentSpecKey()
    if not YHUD:IsStableSpecKey(specKey) then
        return nil, "invalid-spec-key"
    end
    if type(profile) == "table"
        and rawget(profile, "_yhudCanonical")
        and copy ~= true then
        return profile, specKey
    end
    if type(profile) == "table"
        and rawget(profile, "_yhudCanonical")
        and copy == true then
        local canonical = YHUD:NormalizeProfile(
            YHUD:CopyValue(YHUD:GetCanonicalProfile(profile)),
            specKey
        )
        local working, code = YHUD:GetScopedProfile(
            canonical,
            specKey,
            true
        )
        if not working then return nil, code end
        working.entries = YHUD:CopyValue(profile.entries or {})
        working.monitors = YHUD:CopyValue(profile.monitors or {})
        working._yhudScopeByEntry = YHUD:CopyValue(
            rawget(profile, "_yhudScopeByEntry") or {}
        )
        working._yhudScopeByMonitor = YHUD:CopyValue(
            rawget(profile, "_yhudScopeByMonitor") or {}
        )
        working._yhudLaneByMonitor = YHUD:CopyValue(
            rawget(profile, "_yhudLaneByMonitor") or {}
        )
        for groupId, group in pairs(working.groups.items) do
            local sourceGroup = profile.groups
                and profile.groups.items
                and profile.groups.items[groupId]
            group.monitors = YHUD:CopyValue(
                sourceGroup and sourceGroup.monitors or {}
            )
        end
        local persisted
        persisted, code = YHUD:PersistScopedProfile(working)
        if not persisted then return nil, code end
        profile = persisted
    end
    local canonical = YHUD:GetCanonicalProfile(profile)
    if copy == true then canonical = YHUD:CopyValue(canonical) end
    canonical = YHUD:NormalizeProfile(canonical, specKey)
    local scoped, code = YHUD:GetScopedProfile(canonical, specKey, true)
    if not scoped then return nil, code end
    return scoped, specKey
end

local function AddRejected(preview, index, row, reason)
    preview.rejected[#preview.rejected + 1] = {
        inputIndex = index,
        category = type(row) == "table" and row.category or nil,
        sourceCategory = type(row) == "table" and row.sourceCategory or nil,
        displayCategory = type(row) == "table" and row.displayCategory or nil,
        cooldownId = type(row) == "table" and row.cooldownID or nil,
        reason = reason,
    }
    preview.counts.rejected = preview.counts.rejected + 1
end

function CDMImport:BuildPreview(profile, officialEntries, specKey)
    local scoped, code = ResolveScopedProfile(profile, specKey, false)
    if not scoped then return nil, code end
    profile = scoped
    officialEntries = type(officialEntries) == "table" and officialEntries or {}

    local preview = {
        marker = PREVIEW_MARKER,
        inputCount = #officialEntries,
        added = {},
        updated = {},
        unchanged = {},
        pending = {},
        rejected = {},
        mapping = {},
        changes = {},
        sourceConsumers = {},
        counts = {
            input = #officialEntries,
            imported = 0,
            added = 0,
            updated = 0,
            unchanged = 0,
            rejected = 0,
            pendingEvidence = 0,
            determinedSources = 0,
            deduplicatedRuntime = 0,
            duplicateInputs = 0,
            sourceKeyChanges = 0,
            writeBackCalls = 0,
        },
    }

    local seenEntries = {}
    for index = 1, #officialEntries do
        local row = officialEntries[index]
        if type(row) ~= "table" then
            AddRejected(preview, index, row, "invalid-entry")
        else
            local sourceCategory = row.sourceCategory or row.category
            local displayCategory = row.displayCategory
            if row.sourceCategory == nil and displayCategory == nil then
                displayCategory = row.category
            end
            if not SOURCE_CATEGORIES[sourceCategory] then
                AddRejected(preview, index, row, "unknown-source-category")
            elseif displayCategory ~= nil
                and not DISPLAY_CATEGORIES[displayCategory] then
                AddRejected(preview, index, row, "unknown-display-category")
            elseif not IsPositiveInteger(row.cooldownID) then
                AddRejected(preview, index, row, "missing-cooldown-id")
            else
                local entryKey = "cdm:" .. tostring(row.cooldownID)
                if seenEntries[entryKey] then
                    preview.counts.duplicateInputs = preview.counts.duplicateInputs + 1
                else
                    seenEntries[entryKey] = true
                    local existing = profile.entries[entryKey]
                    local candidate, code = BuildEntry(
                        existing,
                        row,
                        sourceCategory,
                        displayCategory,
                        row.cooldownID
                    )
                    if not candidate then
                        AddRejected(preview, index, row, code)
                    else
                        local mapping = {
                            inputIndex = index,
                            entryKey = entryKey,
                            sourceKey = candidate.sourceKey,
                            category = displayCategory,
                            sourceCategory = sourceCategory,
                            displayCategory = displayCategory,
                            metadataOnly = displayCategory == nil,
                            pendingEvidence = candidate.evidenceStatus == "pending",
                        }
                        preview.mapping[#preview.mapping + 1] = mapping
                        preview.counts.imported = preview.counts.imported + 1

                        if mapping.pendingEvidence then
                            preview.pending[#preview.pending + 1] = mapping
                            preview.counts.pendingEvidence =
                                preview.counts.pendingEvidence + 1
                        elseif candidate.sourceKey then
                            local consumers = preview.sourceConsumers[candidate.sourceKey]
                            if not consumers then
                                consumers = {}
                                preview.sourceConsumers[candidate.sourceKey] = consumers
                                preview.counts.determinedSources =
                                    preview.counts.determinedSources + 1
                            end
                            consumers[#consumers + 1] = entryKey
                        end

                        local action
                        if not existing then
                            action = "add"
                            preview.added[#preview.added + 1] = mapping
                            preview.counts.added = preview.counts.added + 1
                        elseif EqualValue(existing, candidate) then
                            action = "unchanged"
                            preview.unchanged[#preview.unchanged + 1] = mapping
                            preview.counts.unchanged = preview.counts.unchanged + 1
                        else
                            action = "update"
                            preview.updated[#preview.updated + 1] = mapping
                            preview.counts.updated = preview.counts.updated + 1
                            if existing.sourceKey ~= candidate.sourceKey then
                                preview.counts.sourceKeyChanges =
                                    preview.counts.sourceKeyChanges + 1
                            end
                        end
                        if action ~= "unchanged" then
                            preview.changes[#preview.changes + 1] = {
                                action = action,
                                entryKey = entryKey,
                                before = existing and ClonePlain(existing) or nil,
                                after = candidate,
                            }
                        end
                    end
                end
            end
        end
    end

    for _, consumers in pairs(preview.sourceConsumers) do
        if #consumers > 1 then
            preview.counts.deduplicatedRuntime =
                preview.counts.deduplicatedRuntime + #consumers - 1
        end
    end
    return preview
end

local function ApplyPreviewChanges(result, preview)
    local changedEntries = {}

    for index = 1, #preview.changes do
        local change = preview.changes[index]
        if change.action == "add" or change.action == "update" then
            local entry, code = ClonePlain(change.after)
            if not entry then return nil, code end
            entry.contentScope = YHUD.CONTENT_SCOPE_SPEC
            entry.applicability = nil
            result.entries[change.entryKey] = entry
            result._yhudScopeByEntry[change.entryKey] =
                YHUD.CONTENT_SCOPE_SPEC
            changedEntries[change.entryKey] = true
        end
    end

    local sourceKeyChanges = 0
    for _, monitor in pairs(result.monitors) do
        if changedEntries[monitor.entryKey] then
            local entry = result.entries[monitor.entryKey]
            local nextSourceKey = entry and entry.sourceKey or nil
            if monitor.sourceKey ~= nextSourceKey then
                monitor.sourceKey = nextSourceKey
                sourceKeyChanges = sourceKeyChanges + 1
            end
        end
    end

    return result, {
        applied = #preview.changes,
        sourceKeyChanges = sourceKeyChanges,
        writeBackCalls = 0,
    }
end

function CDMImport:ApplyPreviewToDraft(draft, preview)
    if type(preview) ~= "table" or preview.marker ~= PREVIEW_MARKER then
        return nil, "invalid-preview"
    end
    local profileModel = YHUD.ProfileModel
    if not profileModel
        or not profileModel:IsDraft(draft)
        or draft.closed == true then
        return nil, "invalid-draft"
    end
    local profile, report = ApplyPreviewChanges(draft.profile, preview)
    draft.profile = profile
    if report.applied > 0 then profileModel:MarkDraftChanged(draft) end
    return report
end

function CDMImport:ApplyPreview(profile, preview, specKey)
    if type(preview) ~= "table" or preview.marker ~= PREVIEW_MARKER then
        return nil, "invalid-preview"
    end
    local result, code = ResolveScopedProfile(profile, specKey, true)
    if not result then return nil, code end
    local report
    result, report = ApplyPreviewChanges(result, preview)
    result, code = YHUD:PersistScopedProfile(result)
    if not result then return nil, code end
    return result, report
end

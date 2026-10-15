local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local CDMCatalog = {}
YHUD.CDMCatalog = CDMCatalog

CDMCatalog.stats = {
    reconciles = 0,
    noChangeSkips = 0,
    changedReconciles = 0,
    nativeSettingsSignals = 0,
    layoutUnchangedSkips = 0,
}

local RESTORE_PREVIEW_MARKER = "yhud-cdm-restore-preview-v1"
local DEFAULT_SEED_MARKER = "yhud-cdm-default-seed-v1"
local CLAIM_PROJECTION_UNAVAILABLE = "claim-projection-unavailable"
CDMCatalog.CLAIM_PROJECTION_UNAVAILABLE = CLAIM_PROJECTION_UNAVAILABLE
local OFFICIAL_CATEGORIES = {
    "essential",
    "utility",
    "trackedBuff",
    "trackedBar",
}

local function GetReader()
    return YUI.API and YUI.API.CooldownViewer
end

local function GetDefaultGroupId(category)
    local mapping = YHUD.DEFAULT_GROUP_BY_CATEGORY
    return mapping and mapping[category] or nil
end

local function RestoreSavedOfficialOverrides(profile, specKey, options)
    local allOverrides = type(profile) == "table"
        and profile.officialOverridesBySpec or nil
    local overrides = type(allOverrides) == "table" and allOverrides[specKey]
        or nil
    if type(overrides) ~= "table" or next(overrides) == nil then
        return profile, { changed = false }
    end

    local configSets = YHUD.ConfigSets
    if not (configSets and configSets.RestoreOfficialOverrides) then
        return nil, "config-overrides-unavailable"
    end
    return configSets:RestoreOfficialOverrides(profile, specKey, options)
end

local function FilterCategoryRows(rows, category)
    local filtered = {}
    for index = 1, #rows do
        local row = rows[index]
        if type(row) == "table" and row.category == category then
            filtered[#filtered + 1] = row
        end
    end
    return filtered
end

local function BuildOrderedEntryKeys(
    importPreview,
    category,
    profile,
    knownOnly
)
    local entryKeys = {}
    for index = 1, #importPreview.mapping do
        local mapping = importPreview.mapping[index]
        local entry = profile
            and profile.entries
            and profile.entries[mapping.entryKey]
        if mapping.category == category
            and (not knownOnly or not entry or entry.isKnown ~= false) then
            entryKeys[#entryKeys + 1] = mapping.entryKey
        end
    end
    return entryKeys
end

local function IsOfficialEntryClaimed(entry, claimed)
    return YHUD:IsOfficialEntryClaimed(entry, claimed)
end

local function FilterClaimedOfficialEntries(
    profile,
    orderedEntryKeys,
    claimed
)
    if not next(claimed) then
        return orderedEntryKeys, nil
    end
    local filtered = {}
    local removed = {}
    for index = 1, #orderedEntryKeys do
        local entryKey = orderedEntryKeys[index]
        local entry = profile.entries and profile.entries[entryKey]
        if IsOfficialEntryClaimed(entry, claimed) then
            removed[entryKey] = true
        else
            filtered[#filtered + 1] = entryKey
        end
    end
    return filtered, next(removed) and removed or nil
end

local function RecordClaimProjectionFailure(detail)
    if YHUD.Diagnostics and type(YHUD.Diagnostics.Record) == "function" then
        YHUD.Diagnostics:Record("claim-projection", detail)
    end
    return nil, CLAIM_PROJECTION_UNAVAILABLE
end

local function ResolveClaimedCooldownSources(profile)
    local catalog = YHUD.MonitorCatalog
    if not catalog
        or type(catalog.GetClaimedCooldownSources) ~= "function" then
        return RecordClaimProjectionFailure("claim-source-unavailable")
    end
    local claimed = catalog:GetClaimedCooldownSources(profile)
    if type(claimed) ~= "table" then
        return RecordClaimProjectionFailure("claim-source-invalid")
    end
    return claimed
end

local function ReadAllOptions(options)
    local result = {}
    if type(options) == "table" then
        for key, value in pairs(options) do
            result[key] = value
        end
    end
    result.allowUnlearned = true
    return result
end

local function HasCategoryMonitor(profile, category)
    local groups = profile
        and profile.groups
        and profile.groups.items
    if type(groups) ~= "table" then return false end
    for _, group in pairs(groups) do
        local monitors = type(group) == "table" and group.monitors or nil
        if type(monitors) == "table" then
            for index = 1, #monitors do
                local monitor = monitors[index]
                local entry = type(monitor) == "table"
                    and profile.entries
                    and profile.entries[monitor.entryKey]
                local monitorCategory = type(monitor) == "table"
                    and monitor.officialCategory or nil
                if not monitorCategory and type(entry) == "table" then
                    monitorCategory = entry.officialCategory
                end
                if monitorCategory == category then return true end
            end
        end
    end
    return false
end

function CDMCatalog:Read(options)
    local reader = GetReader()
    if not reader or type(reader.ReadEntries) ~= "function" then
        return nil, "cooldown-viewer-api-unavailable"
    end
    options = type(options) == "table" and options or {}
    if options.allowUnlearned == nil then
        options.allowUnlearned = false
    end
    return reader:ReadEntries(options)
end

function CDMCatalog:CaptureLayoutSignature(specKey)
    local reader = GetReader()
    if not reader or type(reader.GetLayoutSignature) ~= "function" then
        return false
    end
    local signature = reader:GetLayoutSignature()
    if signature == nil then return false end
    self.layoutSignature = signature
    self.layoutSignatureSpecKey = specKey
    return true
end

function CDMCatalog:IsLayoutSignatureCurrent(specKey)
    if self.layoutSignatureSpecKey ~= specKey
        or self.layoutSignature == nil then
        return false
    end
    local reader = GetReader()
    if not reader or type(reader.GetLayoutSignature) ~= "function" then
        return false
    end
    local signature = reader:GetLayoutSignature()
    return signature ~= nil and signature == self.layoutSignature
end

local function FindMonitorForEntry(profile, entryKey)
    for monitorId, monitor in pairs(profile.monitors) do
        if monitor.entryKey == entryKey then return monitorId, monitor end
    end
    return nil
end

local function RemoveOfficialIdentity(draft, entryKey)
    local profile = draft.profile
    local monitorId, monitor = FindMonitorForEntry(profile, entryKey)
    if monitorId then
        local group = profile.groups.items[monitor.groupId]
        if group then
            for index = #group.monitors, 1, -1 do
                if group.monitors[index] == monitorId then
                    table.remove(group.monitors, index)
                end
            end
            for index = 1, #group.monitors do
                local retained = profile.monitors[group.monitors[index]]
                if retained then retained.order = index end
            end
        end
        profile.monitors[monitorId] = nil
    end
    profile.entries[entryKey] = nil
    profile.suppressedOfficial[entryKey] = nil
    YHUD.ProfileModel:MarkDraftChanged(draft)
end

local function FindNativeInsertionIndex(profile, group, orderedEntryKeys, position)
    for index = position - 1, 1, -1 do
        local monitorId = FindMonitorForEntry(profile, orderedEntryKeys[index])
        local monitor = monitorId and profile.monitors[monitorId]
        if monitor and monitor.groupId == group.id then
            for memberIndex = 1, #group.monitors do
                if group.monitors[memberIndex] == monitorId then
                    return memberIndex + 1
                end
            end
        end
    end
    for index = position + 1, #orderedEntryKeys do
        local monitorId = FindMonitorForEntry(profile, orderedEntryKeys[index])
        local monitor = monitorId and profile.monitors[monitorId]
        if monitor and monitor.groupId == group.id then
            for memberIndex = 1, #group.monitors do
                if group.monitors[memberIndex] == monitorId then
                    return memberIndex
                end
            end
        end
    end
    return #group.monitors + 1
end

local function BuildDraftOfficialOrder(profile)
    local orderedByCategory = {}
    for index = 1, #OFFICIAL_CATEGORIES do
        orderedByCategory[OFFICIAL_CATEGORIES[index]] = {}
    end
    for entryKey, entry in pairs(type(profile) == "table"
        and type(profile.entries) == "table" and profile.entries or {}) do
        local category = type(entry) == "table" and entry.officialCategory
        local ordered = category and orderedByCategory[category]
        if ordered and entry.origin == "official-cdm" then
            ordered[#ordered + 1] = {
                entryKey = entryKey,
                order = tonumber(entry.order),
                cooldownId = tonumber(entry.cooldownId),
            }
        end
    end
    for index = 1, #OFFICIAL_CATEGORIES do
        local category = OFFICIAL_CATEGORIES[index]
        local rows = orderedByCategory[category]
        table.sort(rows, function(left, right)
            local leftOrder = left.order or math.huge
            local rightOrder = right.order or math.huge
            if leftOrder ~= rightOrder then return leftOrder < rightOrder end
            local leftCooldownId = left.cooldownId or math.huge
            local rightCooldownId = right.cooldownId or math.huge
            if leftCooldownId ~= rightCooldownId then
                return leftCooldownId < rightCooldownId
            end
            return left.entryKey < right.entryKey
        end)
        local entryKeys = {}
        for rowIndex = 1, #rows do
            entryKeys[rowIndex] = rows[rowIndex].entryKey
        end
        orderedByCategory[category] = entryKeys
    end
    return orderedByCategory
end

local function ProjectDraftClaims(staged, claimed)
    local profileModel = YHUD.ProfileModel
    local profile = staged.profile
    local orderedByCategory = BuildDraftOfficialOrder(profile)
    local removed = 0
    local restored = 0
    local code

    for categoryIndex = 1, #OFFICIAL_CATEGORIES do
        local category = OFFICIAL_CATEGORIES[categoryIndex]
        local ordered = orderedByCategory[category]
        local groupId = GetDefaultGroupId(category)
        local group = groupId and profile.groups.items[groupId]
        if #ordered > 0 and not group then
            return RecordClaimProjectionFailure("group-not-found")
        end

        for position = 1, #ordered do
            local entryKey = ordered[position]
            local entry = profile.entries[entryKey]
            local monitorId = FindMonitorForEntry(profile, entryKey)
            if IsOfficialEntryClaimed(entry, claimed) then
                if monitorId then
                    local removedMonitor
                    removedMonitor, code = profileModel:RemoveMonitor(
                        staged,
                        monitorId
                    )
                    if not removedMonitor then
                        return RecordClaimProjectionFailure(code)
                    end
                    profile.suppressedOfficial[entryKey] = nil
                    removed = removed + 1
                end
            elseif not monitorId
                and profile.suppressedOfficial[entryKey] ~= true then
                local monitor
                monitor, code = profileModel:AddMonitor(staged, {
                    id = "monitor:" .. entryKey,
                    entryKey = entryKey,
                    groupId = groupId,
                    view = profileModel:GetDefaultView(group.layout),
                    index = FindNativeInsertionIndex(
                        profile,
                        group,
                        ordered,
                        position
                    ),
                    origin = "official-cdm",
                    officialCategory = category,
                })
                if not monitor then
                    return RecordClaimProjectionFailure(code)
                end
                restored = restored + 1
            end
        end
    end

    return {
        changed = removed > 0 or restored > 0,
        removed = removed,
        restored = restored,
        writeBackCalls = 0,
    }
end

local function HasDraftClaimCapabilities(profileModel)
    return type(profileModel) == "table"
        and type(profileModel.IsDraft) == "function"
        and type(profileModel.BeginDraft) == "function"
        and type(profileModel.AdoptDraft) == "function"
        and type(profileModel.RemoveMonitor) == "function"
        and type(profileModel.AddMonitor) == "function"
        and type(profileModel.GetDefaultView) == "function"
end

function CDMCatalog:ApplyDraftClaimMutation(draft, mutator)
    local profileModel = YHUD.ProfileModel
    if not profileModel
        or type(profileModel.IsDraft) ~= "function"
        or not profileModel:IsDraft(draft)
        or draft.closed == true then
        return nil, "invalid-draft"
    end
    if type(mutator) ~= "function" then return nil, "invalid-mutator" end
    if not HasDraftClaimCapabilities(profileModel) then
        return RecordClaimProjectionFailure("profile-model-unavailable")
    end
    local catalog = YHUD.MonitorCatalog
    if not catalog
        or type(catalog.GetClaimedCooldownSources) ~= "function" then
        return RecordClaimProjectionFailure("claim-source-unavailable")
    end

    local staged, code = profileModel:BeginDraft(draft.profile, {
        combat = draft.combat == true,
        specKey = draft.specKey,
    })
    if not staged then return nil, code end

    local result
    result, code = mutator(staged)
    if not result then return nil, code end

    local claimed
    claimed, code = ResolveClaimedCooldownSources(staged.profile)
    if not claimed then return nil, code end
    local report
    report, code = ProjectDraftClaims(staged, claimed)
    if not report then return nil, code end

    if staged.changed == true then
        local adopted
        adopted, code = profileModel:AdoptDraft(draft, staged)
        if not adopted then
            return RecordClaimProjectionFailure(code)
        end
    end
    return result, report
end

function CDMCatalog:ReconcileDraftClaims(draft)
    local result, report = self:ApplyDraftClaimMutation(draft, function()
        return true
    end)
    if not result then return nil, report end
    return report
end

function CDMCatalog:ReconcileContext(profile, specKey, options)
    options = type(options) == "table" and options or {}
    specKey = specKey
        or (type(profile) == "table" and rawget(profile, "_yhudSpecKey"))
        or YHUD:GetCurrentSpecKey()
    if not YHUD:IsStableSpecKey(specKey) then
        return nil, "invalid-spec-key"
    end

    local importer = YHUD.CDMImport
    local profileModel = YHUD.ProfileModel
    if not importer then return nil, "cdm-import-unavailable" end
    if not profileModel then return nil, "profile-model-unavailable" end

    self.stats.reconciles = self.stats.reconciles + 1

    local rows, snapshot = self:Read(ReadAllOptions(options))
    if not rows then return nil, snapshot end
    if #rows == 0 and options.allowEmpty ~= true then
        return nil, "cooldown-viewer-empty"
    end
    local reader = GetReader()
    if reader and reader.PrimeAuraStackSources then
        reader:PrimeAuraStackSources(rows)
    end

    local canonical = YHUD:GetCanonicalProfile(profile)
    local scoped
    if type(profile) == "table"
        and rawget(profile, "_yhudCanonical") == canonical
        and rawget(profile, "_yhudSpecKey") == specKey then
        scoped = profile
    elseif options.runtimeOwned == true then
        scoped = YHUD:GetScopedProfile(canonical, specKey, true)
    else
        scoped = YHUD:GetRuntimeProfile(canonical, specKey, true)
    end
    if not scoped then return nil, "content-not-found" end
    local preview, code = importer:BuildPreview(scoped, rows, specKey)
    if not preview then return nil, code end

    local snapshotKeys = {}
    local snapshotEntryKeys = {}
    for index = 1, #preview.mapping do
        local entryKey = preview.mapping[index].entryKey
        snapshotKeys[entryKey] = true
        snapshotEntryKeys[#snapshotEntryKeys + 1] = entryKey
    end
    local claimed, claimCode = ResolveClaimedCooldownSources(scoped)
    if not claimed then return nil, claimCode end
    local _, scopedClaimedEntryKeys = FilterClaimedOfficialEntries(
        scoped,
        snapshotEntryKeys,
        claimed
    )
    local monitorByEntry = {}
    local duplicateMonitor = false
    for monitorId, monitor in pairs(scoped.monitors) do
        local entryKey = monitor.entryKey
        if entryKey then
            if monitorByEntry[entryKey] then duplicateMonitor = true end
            monitorByEntry[entryKey] = monitorId
        end
    end
    local needsReconcile = #preview.changes > 0
        or duplicateMonitor
        or options.restoreCategory ~= nil
        or scoped.initialization.nativeSeedVersion
            ~= YHUD.NATIVE_SEED_VERSION
    local retained = 0
    local suppressed = 0
    for index = 1, #preview.mapping do
        local mapping = preview.mapping[index]
        local entryKey = mapping.entryKey
        local monitorId = monitorByEntry[entryKey]
        if scopedClaimedEntryKeys and scopedClaimedEntryKeys[entryKey] then
            if monitorId then needsReconcile = true end
        elseif scoped.suppressedOfficial[entryKey] == true then
            suppressed = suppressed + 1
            if monitorId then needsReconcile = true end
        elseif monitorId then
            local monitor = scoped.monitors[monitorId]
            if not mapping.category
                or monitor.officialCategory ~= mapping.category then
                needsReconcile = true
            else
                retained = retained + 1
            end
        elseif mapping.category ~= nil then
            needsReconcile = true
        end
    end
    for entryKey, entry in pairs(scoped.entries) do
        if entry.origin == "official-cdm" and not snapshotKeys[entryKey] then
            needsReconcile = true
            break
        end
    end
    if not needsReconcile then
        local restored, restoreReport = RestoreSavedOfficialOverrides(
            canonical,
            specKey
        )
        if not restored then return nil, restoreReport end
        if restoreReport.changed == true then
            self.stats.changedReconciles = self.stats.changedReconciles + 1
            self:CaptureLayoutSignature(specKey)
            return restored, {
                marker = DEFAULT_SEED_MARKER,
                changed = true,
                specKey = specKey,
                created = 0,
                retained = retained,
                moved = 0,
                removed = 0,
                suppressed = suppressed,
                restoredOverrides = true,
                import = {
                    applied = 0,
                    sourceKeyChanges = 0,
                    writeBackCalls = 0,
                },
                officialSnapshot = YHUD:CopyValue(snapshot),
                writeBackCalls = 0,
            }, nil
        end
        self.stats.noChangeSkips = self.stats.noChangeSkips + 1
        self:CaptureLayoutSignature(specKey)
        return canonical, {
            marker = DEFAULT_SEED_MARKER,
            changed = false,
            specKey = specKey,
            created = 0,
            retained = retained,
            moved = 0,
            removed = 0,
            suppressed = suppressed,
            import = {
                applied = 0,
                sourceKeyChanges = 0,
                writeBackCalls = 0,
            },
            officialSnapshot = YHUD:CopyValue(snapshot),
            writeBackCalls = 0,
        }, scoped
    end

    local draft
    -- The preview was compared against the expanded runtime content. Stored
    -- profiles may omit unchanged native entries, so use that same root for
    -- the draft. BeginDraft copies it unless this is an owned materialization.
    draft, code = profileModel:BeginDraft(YHUD:GetCanonicalProfile(scoped), {
        specKey = specKey,
        combat = options.combat == true,
        ownedRoot = options.runtimeOwned == true,
    })
    if not draft then return nil, code end
    local importReport
    importReport, code = importer:ApplyPreviewToDraft(draft, preview)
    if not importReport then return nil, code end

    local orderedByCategory = {}
    for index = 1, #OFFICIAL_CATEGORIES do
        orderedByCategory[OFFICIAL_CATEGORIES[index]] = {}
    end
    for index = 1, #preview.mapping do
        local mapping = preview.mapping[index]
        local ordered = orderedByCategory[mapping.category]
        if ordered then ordered[#ordered + 1] = mapping.entryKey end
    end

    local claimedEntryKeys
    for index = 1, #OFFICIAL_CATEGORIES do
        local category = OFFICIAL_CATEGORIES[index]
        local filtered, removedClaims = FilterClaimedOfficialEntries(
            draft.profile,
            orderedByCategory[category],
            claimed
        )
        orderedByCategory[category] = filtered
        if removedClaims then
            claimedEntryKeys = claimedEntryKeys or {}
            for entryKey in pairs(removedClaims) do
                claimedEntryKeys[entryKey] = true
            end
        end
    end

    local removed = 0
    local stale = {}
    for entryKey, entry in pairs(draft.profile.entries) do
        if entry.origin == "official-cdm" and not snapshotKeys[entryKey] then
            stale[#stale + 1] = entryKey
        end
    end
    for index = 1, #stale do
        RemoveOfficialIdentity(draft, stale[index])
        removed = removed + 1
    end
    for index = 1, #preview.mapping do
        local mapping = preview.mapping[index]
        if mapping.category == nil then
            local monitorId = FindMonitorForEntry(
                draft.profile,
                mapping.entryKey
            )
            if monitorId then
                profileModel:RemoveMonitor(draft, monitorId)
                draft.profile.suppressedOfficial[mapping.entryKey] = nil
                removed = removed + 1
            end
        end
    end
    for entryKey in pairs(claimedEntryKeys or {}) do
        local monitorId = FindMonitorForEntry(draft.profile, entryKey)
        if monitorId then
            profileModel:RemoveMonitor(draft, monitorId)
            draft.profile.suppressedOfficial[entryKey] = nil
            removed = removed + 1
        end
    end

    local restoredCategory = options.restoreCategory
    local created = 0
    retained = 0
    suppressed = 0
    local moved = 0
    if restoredCategory and not orderedByCategory[restoredCategory] then
        return nil, "invalid-category"
    end

    if restoredCategory then
        local restored
        restored, code = profileModel:RestoreCategory(
            draft,
            restoredCategory,
            GetDefaultGroupId(restoredCategory),
            orderedByCategory[restoredCategory]
        )
        if not restored then return nil, code end
        created = created + #(restored.created or {})
        retained = retained + #(restored.retained or {})
        moved = moved + #(restored.moved or {})
    end

    for categoryIndex = 1, #OFFICIAL_CATEGORIES do
        local category = OFFICIAL_CATEGORIES[categoryIndex]
        if category ~= restoredCategory then
            local groupId = GetDefaultGroupId(category)
            local group = draft.profile.groups.items[groupId]
            local ordered = orderedByCategory[category]
            for position = 1, #ordered do
                local entryKey = ordered[position]
                local monitorId = FindMonitorForEntry(draft.profile, entryKey)
                if draft.profile.suppressedOfficial[entryKey] == true then
                    if monitorId then
                        profileModel:RemoveMonitor(draft, monitorId)
                    end
                    suppressed = suppressed + 1
                elseif monitorId then
                    local monitor = draft.profile.monitors[monitorId]
                    local insertionIndex = FindNativeInsertionIndex(
                        draft.profile,
                        group,
                        ordered,
                        position
                    )
                    if monitor.groupId ~= groupId
                        or monitor.officialCategory ~= category then
                        local movedMonitor
                        movedMonitor, code = profileModel:MoveMonitor(
                            draft,
                            monitorId,
                            groupId,
                            insertionIndex,
                            profileModel:GetDefaultView(group.layout),
                            YHUD.CONTENT_LANE_SPEC
                        )
                        if not movedMonitor then return nil, code end
                        monitor = draft.profile.monitors[monitorId]
                        monitor.origin = "official-cdm"
                        monitor.officialCategory = category
                        moved = moved + 1
                    end
                    retained = retained + 1
                else
                    local insertionIndex = FindNativeInsertionIndex(
                        draft.profile,
                        group,
                        ordered,
                        position
                    )
                    local monitor
                    monitor, code = profileModel:AddMonitor(draft, {
                        id = "monitor:" .. entryKey,
                        entryKey = entryKey,
                        groupId = groupId,
                        view = profileModel:GetDefaultView(group.layout),
                        index = insertionIndex,
                        origin = "official-cdm",
                        officialCategory = category,
                    })
                    if not monitor then return nil, code end
                    created = created + 1
                end
            end
        end
    end

    draft.profile.initialization.nativeSeedVersion =
        YHUD.NATIVE_SEED_VERSION
    if draft.profile.initialization.nativeSeedVersion
            ~= scoped.initialization.nativeSeedVersion then
        profileModel:MarkDraftChanged(draft)
    end

    local result, summary = profileModel:CommitDraft(draft)
    if not result then return nil, summary end
    local restoreReport
    result, restoreReport = RestoreSavedOfficialOverrides(
        result,
        specKey
    )
    if not result then return nil, restoreReport end
    local changed = summary.changed == true or restoreReport.changed == true
    if changed then
        self.stats.changedReconciles = self.stats.changedReconciles + 1
    end
    self:CaptureLayoutSignature(specKey)
    return result, {
        marker = DEFAULT_SEED_MARKER,
        changed = changed,
        specKey = specKey,
        created = created,
        retained = retained,
        moved = moved,
        removed = removed,
        suppressed = suppressed,
        restoredOverrides = restoreReport.changed == true,
        import = YHUD:CopyValue(importReport),
        officialSnapshot = YHUD:CopyValue(snapshot),
        writeBackCalls = 0,
    }, restoreReport.changed == true and nil or draft.profile
end

function CDMCatalog:GetStats(target)
    target = target or {}
    target.reconciles = self.stats.reconciles or 0
    target.noChangeSkips = self.stats.noChangeSkips or 0
    target.changedReconciles = self.stats.changedReconciles or 0
    target.nativeSettingsSignals = self.stats.nativeSettingsSignals or 0
    target.layoutUnchangedSkips = self.stats.layoutUnchangedSkips or 0
    return target
end

function CDMCatalog:SeedDefaultCategories(profile, options)
    return self:ReconcileContext(
        profile,
        type(options) == "table" and options.specKey or nil,
        options
    )
end

function CDMCatalog:BuildPreview(profile, options)
    local rows, snapshot = self:Read(options)
    if not rows then return nil, snapshot end

    local importer = YHUD.CDMImport
    if not importer then return nil, "cdm-import-unavailable" end

    local specKey = type(options) == "table" and options.specKey or nil
    local preview, code = importer:BuildPreview(profile, rows, specKey)
    if not preview then return nil, code end
    preview.officialSnapshot = YHUD:CopyValue(snapshot)
    return preview
end

function CDMCatalog:ApplyToProfile(profile, options)
    local preview, code = self:BuildPreview(profile, options)
    if not preview then return nil, code end

    local result, report =
        YHUD.CDMImport:ApplyPreview(
            profile,
            preview,
            type(options) == "table" and options.specKey or nil
        )
    if not result then return nil, report end
    report.officialSnapshot =
        YHUD:CopyValue(preview.officialSnapshot)
    return YHUD:GetCanonicalProfile(result), report, preview
end

function CDMCatalog:ApplyToDraft(draft, options)
    local profileModel = YHUD.ProfileModel
    if not profileModel
        or not profileModel:IsDraft(draft)
        or draft.closed == true then
        return nil, "invalid-draft"
    end

    options = type(options) == "table" and options or {}
    options.specKey = draft.specKey
    local preview, code = self:BuildPreview(draft.profile, options)
    if not preview then return nil, code end
    local result, report = YHUD.CDMImport:ApplyPreview(
        draft.profile,
        preview,
        draft.specKey
    )
    if not result then return nil, report end

    local staged
    staged, code = profileModel:BeginDraft(result, {
        specKey = draft.specKey,
        combat = draft.combat == true,
    })
    if not staged then return nil, code end
    if report.applied > 0 then staged.changed = true end
    local adopted
    adopted, code = profileModel:AdoptDraft(draft, staged)
    if not adopted then return nil, code end
    return report, preview
end

function CDMCatalog:BuildRestorePreview(profile, category, options)
    local defaultGroupId = GetDefaultGroupId(category)
    if not defaultGroupId then return nil, "invalid-category" end

    local rows, snapshot = self:Read(ReadAllOptions(options))
    if not rows then return nil, snapshot end

    local importer = YHUD.CDMImport
    local profileModel = YHUD.ProfileModel
    if not importer then return nil, "cdm-import-unavailable" end
    if not profileModel then return nil, "profile-model-unavailable" end

    local categoryRows = FilterCategoryRows(rows, category)
    local specKey = type(options) == "table" and options.specKey
        or (type(profile) == "table" and rawget(profile, "_yhudSpecKey"))
    local importPreview, code =
        importer:BuildPreview(profile, categoryRows, specKey)
    if not importPreview then return nil, code end
    local importedProfile, importReport =
        importer:ApplyPreview(profile, importPreview, specKey)
    if not importedProfile then return nil, importReport end

    local orderedEntryKeys = BuildOrderedEntryKeys(
        importPreview,
        category,
        importedProfile,
        false
    )
    local claimed
    claimed, code = ResolveClaimedCooldownSources(importedProfile)
    if not claimed then return nil, code end
    orderedEntryKeys = FilterClaimedOfficialEntries(
        importedProfile,
        orderedEntryKeys,
        claimed
    )
    local staged
    staged, code = profileModel:BeginDraft(importedProfile, {
        specKey = specKey,
    })
    if not staged then return nil, code end
    if importReport.applied > 0 then staged.changed = true end
    local restoreReport, code = profileModel:RestoreCategory(
        staged,
        category,
        defaultGroupId,
        orderedEntryKeys
    )
    if not restoreReport then return nil, code end

    return {
        marker = RESTORE_PREVIEW_MARKER,
        category = category,
        defaultGroupId = defaultGroupId,
        orderedEntryKeys = YHUD:CopyValue(orderedEntryKeys),
        importPreview = YHUD:CopyValue(importPreview),
        importReport = YHUD:CopyValue(importReport),
        restoreReport = YHUD:CopyValue(restoreReport),
        officialSnapshot = YHUD:CopyValue(snapshot),
        writeBackCalls = 0,
    }
end

function CDMCatalog:ApplyRestorePreview(draft, preview)
    local profileModel = YHUD.ProfileModel
    local importer = YHUD.CDMImport
    if not profileModel
        or not profileModel:IsDraft(draft)
        or draft.closed == true then
        return nil, "invalid-draft"
    end
    if not importer then return nil, "cdm-import-unavailable" end
    if type(preview) ~= "table"
        or preview.marker ~= RESTORE_PREVIEW_MARKER
        or type(preview.orderedEntryKeys) ~= "table"
        or type(preview.importPreview) ~= "table" then
        return nil, "invalid-preview"
    end

    local defaultGroupId = GetDefaultGroupId(preview.category)
    if not defaultGroupId
        or preview.defaultGroupId ~= defaultGroupId then
        return nil, "invalid-preview"
    end

    local staged = profileModel:BeginDraft(draft.profile, {
        combat = draft.combat == true,
        specKey = draft.specKey,
    })
    local importedProfile, importReport =
        importer:ApplyPreview(
            staged.profile,
            preview.importPreview,
            draft.specKey
        )
    if not importedProfile then return nil, importReport end
    staged = profileModel:BeginDraft(importedProfile, {
        combat = draft.combat == true,
        specKey = draft.specKey,
    })
    if importReport.applied > 0 then staged.changed = true end

    local claimed
    claimed, code = ResolveClaimedCooldownSources(staged.profile)
    if not claimed then return nil, code end
    local orderedEntryKeys = FilterClaimedOfficialEntries(
        staged.profile,
        preview.orderedEntryKeys,
        claimed
    )
    local restoreReport, code = profileModel:RestoreCategory(
        staged,
        preview.category,
        defaultGroupId,
        orderedEntryKeys
    )
    if not restoreReport then return nil, code end

    local adopted
    adopted, code = profileModel:AdoptDraft(draft, staged)
    if not adopted then return nil, code end

    return {
        category = preview.category,
        defaultGroupId = defaultGroupId,
        import = YHUD:CopyValue(importReport),
        restore = YHUD:CopyValue(restoreReport),
        officialSnapshot = YHUD:CopyValue(preview.officialSnapshot),
        writeBackCalls = 0,
    }
end

function CDMCatalog:RestoreDefaultCategory(draft, category, options)
    local preview, code =
        self:BuildRestorePreview(draft and draft.profile, category, options)
    if not preview then return nil, code end
    local report
    report, code = self:ApplyRestorePreview(draft, preview)
    if not report then return nil, code end
    return report, preview
end

local function RejectNativeCommit(catalog, code)
    -- ReconcileContext already sampled the layout. A failed commit must remain
    -- retryable on the next native/context event, without a polling loop.
    catalog.layoutSignature = nil
    catalog.layoutSignatureSpecKey = nil
    if YHUD.Diagnostics then
        YHUD.Diagnostics:Record("cdm-reconcile-save", code)
    end
    return nil, code
end

function CDMCatalog:RunPendingReconcile()
    if not self.active then return false end
    self.pendingTimer = nil
    local transfer = YUI.Settings and YUI.Settings.ConfigTransfer
    if transfer and transfer.IsImporting and transfer:IsImporting(YHUD.PRODUCT_ID) then
        self.pendingImport = true
        self.pendingReason = self.pendingReason or "native-settings"
        return false
    end
    self.pendingImport = nil
    if InCombatLockdown and InCombatLockdown() then
        self.pendingCombat = true
        return false
    end
    self.pendingCombat = false
    local reason = self.pendingReason or "native-settings"
    self.pendingReason = nil
    local specKey = YHUD:GetCurrentSpecKey()
    if not YHUD:IsStableSpecKey(specKey) then
        return nil, "invalid-spec-key"
    end
    local profile = YHUD:GetConfigProfile()
    local result, report = self:ReconcileContext(profile, specKey, {
        reason = reason,
    })
    if not result then
        if YHUD.Diagnostics then
            YHUD.Diagnostics:Record("cdm-reconcile", report)
        end
        return nil, report
    end
    if report.changed then
        local adapter = YHUD.ConfigSets
        if not (adapter and adapter.PrepareNativeSyncProfile and adapter.SaveActive) then
            return RejectNativeCommit(self, "config-save-unavailable")
        end
        local stored, code = adapter:PrepareNativeSyncProfile(profile, result, specKey)
        if not stored then return RejectNativeCommit(self, code) end
        if profile ~= YHUD:GetConfigProfile() or specKey ~= YHUD:GetCurrentSpecKey() then
            return RejectNativeCommit(self, "stale-native-sync")
        end
        local replaced
        replaced, code = YHUD:ReplaceConfigProfile(stored)
        if not replaced then return RejectNativeCommit(self, code) end
        local called, saved, saveCode = pcall(
            adapter.SaveActive, adapter, "native-cooldown-sync", YHUD
        )
        if not called or not saved then
            local restored, restoreCode = YHUD:ReplaceConfigProfile(profile)
            return RejectNativeCommit(self, not restored and restoreCode
                or called and (saveCode or "config-save-failed") or saved)
        end
        -- Keep the already reconciled runtime projection; storage now owns all
        -- spec documents, so refresh does not need another catalog read/decode.
        local scoped = YHUD:GetScopedProfile(result, specKey, true)
        if scoped then
            YHUD._runtimeProfile = scoped
            YHUD._runtimeProfileCanonical = replaced
            YHUD._runtimeProfileSpecKey = specKey
            YHUD._runtimeProfileRevision = tonumber(YHUD.runtimeProfileRevision) or 0
        end
        YHUD:Refresh("native-cooldown-sync")
    end
    local designer = YHUD.Designer
    if designer and designer.IsOpen and designer:IsOpen()
        and designer.ReconcileNativeSettings then
        local changed, designerReport = designer:ReconcileNativeSettings()
        if changed == nil then
            if YHUD.Diagnostics then
                YHUD.Diagnostics:Record(
                    "designer-cdm-reconcile",
                    designerReport
                )
            end
        elseif changed and YHUD.DesignerUI and YHUD.DesignerUI.active
            and YHUD.DesignerUI.RefreshAfterStructuralMutation then
            YHUD.DesignerUI:RefreshAfterStructuralMutation(false)
        end
    end
    return true, report
end

function CDMCatalog:RequestReconcile(reason)
    if not self.active then return false end
    self.pendingReason = reason or self.pendingReason or "native-settings"
    if self.pendingTimer and self.pendingTimer.Cancel then
        self.pendingTimer:Cancel()
        self.pendingTimer = nil
    end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingCombat = true
        return true
    end
    if C_Timer and C_Timer.NewTimer then
        local watchdog = YUI.CPUWatchdog
        if watchdog and watchdog.sceneCapture then watchdog:SceneTaskScheduled("yhud.catalog-reconcile") end
        self.pendingTimer = C_Timer.NewTimer(0.05, function()
            local watchdog = YUI.CPUWatchdog
            if watchdog and watchdog.sceneCapture then
                return watchdog:MeasureSceneTask("yhud.catalog-reconcile", CDMCatalog.RunPendingReconcile, CDMCatalog)
            end
            CDMCatalog:RunPendingReconcile()
        end)
        return true
    end
    return self:RunPendingReconcile()
end

function CDMCatalog:CancelPendingReconcile()
    local reason = self.pendingReason
    if self.pendingTimer and self.pendingTimer.Cancel then
        self.pendingTimer:Cancel()
    end
    self.pendingTimer = nil
    self.pendingReason = nil
    self.pendingCombat = false
    self.pendingImport = nil
    return reason
end

function CDMCatalog:OnImportReleased()
    if not self.active or not self.pendingImport then return end
    self.pendingImport = nil
    return self:RequestReconcile(self.pendingReason)
end

function CDMCatalog:OnNativeSettingsChanged()
    self.stats.nativeSettingsSignals = self.stats.nativeSettingsSignals + 1
    local specKey = YHUD:GetCurrentSpecKey()
    local layoutUnchanged = YHUD:IsStableSpecKey(specKey)
        and self:IsLayoutSignatureCurrent(specKey)
    local reader = GetReader()
    if reader and reader.InvalidateAuraStackSources then
        reader:InvalidateAuraStackSources()
    end
    if layoutUnchanged then
        self.stats.layoutUnchangedSkips =
            self.stats.layoutUnchangedSkips + 1
        return true
    end
    return self:RequestReconcile("native-settings")
end

function CDMCatalog:OnContextChanged(_, unit)
    if unit and unit ~= "player" then return end
    if YHUD.RequestContextRefresh then
        return YHUD:RequestContextRefresh("specialization-changed")
    end
    return self:RequestReconcile("specialization-changed")
end

function CDMCatalog:OnCombatEnded()
    if YHUD.pendingContextCombat and YHUD.RequestContextRefresh then
        return YHUD:RequestContextRefresh("combat-ended")
    end
    if self.pendingCombat or self.pendingReason then
        return self:RequestReconcile("combat-ended")
    end
end

function CDMCatalog:RegisterCallbacks()
    if self.active then return true end
    self.active = true
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback(
            "CooldownViewerSettings.OnDataChanged",
            self.OnNativeSettingsChanged,
            self
        )
    end
    if YUI.Event and YUI.Event.On then
        YUI.Event:On("YUI_CONFIG_TRANSFER_RELEASED", "OnImportReleased", self, {
            moduleId = YHUD.PRODUCT_ID,
            traceName = "YHUD.CDMCatalog.ImportReleased",
        })
        YUI.Event:On(
            "PLAYER_SPECIALIZATION_CHANGED",
            "OnContextChanged",
            self,
            {
                unit = "player",
                moduleId = YHUD.PRODUCT_ID,
                traceName = "YHUD.CDMCatalog.Context",
            }
        )
        YUI.Event:On(
            "PLAYER_REGEN_ENABLED",
            "OnCombatEnded",
            self,
            {
                moduleId = YHUD.PRODUCT_ID,
                traceName = "YHUD.CDMCatalog.Combat",
            }
        )
    end
    return true
end

function CDMCatalog:UnregisterCallbacks()
    self.active = false
    self:CancelPendingReconcile()
    if EventRegistry and EventRegistry.UnregisterCallback then
        EventRegistry:UnregisterCallback(
            "CooldownViewerSettings.OnDataChanged",
            self
        )
    end
    if YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(self)
    end
    return true
end

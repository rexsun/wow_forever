local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local Service = YUI.Settings and YUI.Settings.ConfigSets
local Adapter = YHUD.ConfigSets
local ProfileModel = YHUD.ProfileModel
if not (Service and Adapter and ProfileModel) then return end

local ConfigCatalog = {}
YHUD.ConfigCatalog = ConfigCatalog

ConfigCatalog.PROVIDER_ID = YHUD.CONFIG_SET_PROVIDER_ID
ConfigCatalog.selectedId = nil
local CommitPreparedDraft

local function GetPackBaseline(profile)
    if type(profile) ~= "table" then return nil end
    if type(profile.specDocuments) == "table" then
        return YHUD:CopyValue(profile.specDocuments)
    end
    return nil
end

local function SetCoordinationContext(item, specKey, generation, report)
    local catalog = YHUD.CDMCatalog
    item.coordinationContext = {
        specKey = specKey,
        generation = tonumber(generation),
        layoutSignature = catalog
            and catalog.layoutSignatureSpecKey == specKey
            and catalog.layoutSignature or nil,
        report = report,
    }
end

local function UserReference(setId)
    return {
        kind = "user",
        id = setId,
    }
end

local function CountMap(values)
    local count = 0
    for _ in pairs(type(values) == "table" and values or {}) do
        count = count + 1
    end
    return count
end

local function SummarizeProfile(profile)
    profile = type(profile) == "table" and profile or {}
    local specKey = YHUD:GetCurrentSpecKey()
    if YHUD:IsStableSpecKey(specKey) then
        local canonical = YHUD:GetCanonicalProfile(profile)
        if rawget(canonical, "_yhudSpecDocumentProjection") ~= true then
            canonical = YHUD:NormalizeProfile(canonical, specKey)
        end
        profile = YHUD:GetScopedProfile(
            canonical,
            specKey,
            true
        ) or profile
    end
    local groups = profile.groups and profile.groups.items or {}
    local monitors = profile.monitors or {}
    return {
        groupCount = CountMap(groups),
        monitorCount = CountMap(monitors),
        resourceEnabled = YHUD:HasEnabledResourceGroup(profile),
    }
end

-- The provider's public metadata determines which service contract is active.
-- Profile-owned libraries do not expose configuration modes. Never call the
-- retired mode API in that case; retain reads for the legacy service fixture.
local function ReadLegacyMode()
    local provider = Service:GetProvider(ConfigCatalog.PROVIDER_ID)
    if not provider then return nil, "provider_not_found" end
    if not provider.configurationModes then return nil end
    return Service:GetConfigurationMode(ConfigCatalog.PROVIDER_ID)
end

local function ReadSet(setId, options)
    options = type(options) == "table" and options or {}
    local configurationMode, modeCode, modeDetail =
        ReadLegacyMode()
    if modeCode then return nil, modeCode, modeDetail end
    local public, code, detail = Service:GetSet(
        ConfigCatalog.PROVIDER_ID,
        "user",
        setId
    )
    if not public then return nil, code, detail end
    if configurationMode and public.configurationMode ~= configurationMode then
        return nil, "configuration_mode_mismatch"
    end
    local snapshot
    snapshot, code, detail = Service:GetSetData(
        ConfigCatalog.PROVIDER_ID,
        "user",
        setId
    )
    if not snapshot then return nil, code, detail end
    local assignment
    if configurationMode ~= "unified" then
        assignment, code, detail = Service:GetAssignment(
            ConfigCatalog.PROVIDER_ID,
            UserReference(setId)
        )
        if not assignment then return nil, code, detail end
    else
        assignment = {
            mode = "all",
            specKeys = {},
            enabled = true,
        }
    end
    local data = snapshot.data
    local storageData = YHUD:CopyValue(data)
    local packBaseline
    local materializationReport
    local materializeSpecKey = options.specKey or YHUD:GetCurrentSpecKey()
    local reusedRuntime = type(options.runtimeProfile) == "table"
        and type(data) == "table" and type(data.profile) == "table"
        and type(data.profile.specDocuments) == "table"
    if reusedRuntime then
        packBaseline = GetPackBaseline(data.profile)
        data.profile, code = Adapter:CaptureRuntimeProfile(
            options.runtimeProfile,
            materializeSpecKey
        )
        if not data.profile then return nil, code end
        data.profile.specDocuments = packBaseline
        data.profile._yhudSpecDocumentProjection = true
        materializationReport = {
            changed = false,
            specKey = materializeSpecKey,
            reusedRuntime = true,
            writeBackCalls = 0,
        }
    elseif options.materialize ~= false
        and type(data) == "table" and data.profile then
        data.profile, materializationReport, packBaseline =
            Adapter:MaterializeProfile(
            data.profile,
            materializeSpecKey,
            true
        )
        if not data.profile then
            return nil, materializationReport, packBaseline
        end
    end
    local item = {
        set = public,
        data = data,
        storageData = storageData,
        packBaseline = packBaseline,
        materializationReport = materializationReport,
        materializedSpecKey = (reusedRuntime
            or options.materialize ~= false) and materializeSpecKey or nil,
        reusedRuntime = reusedRuntime,
        scopeIds = snapshot.scopeIds,
        assignment = assignment,
        summary = options.materialize ~= false
            and SummarizeProfile(data and data.profile) or nil,
    }
    if materializationReport then
        SetCoordinationContext(
            item,
            materializeSpecKey,
            options.generation,
            materializationReport
        )
    end
    return item
end

function ConfigCatalog:EnsureReady()
    local provider, code, detail = Adapter:RegisterProvider()
    if not provider then return nil, code, detail end
    local ensured
    ensured, code, detail = Adapter:EnsureDefaultUserSet()
    if not ensured then return nil, code, detail end
    return true
end

function ConfigCatalog:Get(setId, options)
    local ready, code, detail = self:EnsureReady()
    if not ready then return nil, code, detail end
    return ReadSet(setId, options)
end

function ConfigCatalog:StartGet(setId, options)
    options = type(options) == "table" and options or {}
    local ready, code, detail = self:EnsureReady()
    if not ready then
        if type(options.onComplete) == "function" then
            options.onComplete(nil, code, detail)
        end
        return { finished = true, Cancel = function() return false end }
    end
    local item
    item, code, detail = ReadSet(setId, {
        materialize = false,
        specKey = options.specKey,
        runtimeProfile = options.runtimeProfile,
    })
    if not item then
        if type(options.onComplete) == "function" then
            options.onComplete(nil, code, detail)
        end
        return { finished = true, Cancel = function() return false end }
    end
    local runtimeSpecKey = YHUD:GetCurrentSpecKey()
    local specKey = options.specKey or runtimeSpecKey
    local chain = {
        finished = false,
        cancelled = false,
        committing = false,
    }
    function chain:Cancel()
        if self.finished or self.cancelled or self.committing then
            return false
        end
        self.cancelled = true
        if self.active and type(self.active.Cancel) == "function" then
            self.active:Cancel()
        end
        return true
    end
    local function IsCurrent()
        if chain.cancelled then return false end
        return YHUD:GetCurrentSpecKey() == runtimeSpecKey
            and (type(options.isCurrent) ~= "function"
                or options.isCurrent() == true)
    end
    local function Complete(result, resultCode, resultDetail)
        if chain.cancelled or chain.finished then return end
        chain.finished = true
        if type(options.onComplete) == "function" then
            options.onComplete(result, resultCode, resultDetail)
        end
    end
    local function FinishItem(profile, packBaseline, storageData, report)
        item.data.profile = profile
        item.packBaseline = packBaseline
        item.materializationReport = report
        item.materializedSpecKey = specKey
        item.reusedRuntime = type(report) == "table"
            and report.reusedRuntime == true or false
        SetCoordinationContext(item, specKey, options.generation, report)
        if type(storageData) == "table" then
            item.storageData = YHUD:CopyValue(storageData)
        end
        item.summary = SummarizeProfile(profile)
        Complete(item)
    end
    if item.reusedRuntime == true then
        SetCoordinationContext(
            item,
            specKey,
            options.generation,
            item.materializationReport
        )
        item.summary = SummarizeProfile(item.data.profile)
        Complete(item)
        return chain
    end
    chain.active = Adapter:StartMaterializeProfile(
        item.data.profile,
        specKey,
        {
            owned = true,
            isCurrent = IsCurrent,
            onProgress = options.onProgress,
            onComplete = function(result, resultCode, resultDetail)
                if not result then
                    Complete(nil, resultCode, resultDetail)
                    return
                end
                local baseline = result.packBaseline
                -- Opening is read-only. Legacy packs are converted only when
                -- the player explicitly saves the draft.
                FinishItem(result.profile, baseline, nil, result.report)
            end,
        }
    )
    return chain
end

function ConfigCatalog:List()
    local ready, code, detail = self:EnsureReady()
    if not ready then return nil, code, detail end
    local configurationMode
    configurationMode, code, detail =
        ReadLegacyMode()
    if code then return nil, code, detail end
    local sets
    sets, code, detail = Service:ListUserSets(self.PROVIDER_ID, {
        configurationMode = configurationMode,
    })
    if not sets then return nil, code, detail end

    local active = Service:GetActiveReference(self.PROVIDER_ID)
    local assignments = configurationMode ~= "unified"
        and (Service:GetAssignments(self.PROVIDER_ID) or {})
        or {}
    local byReference = assignments.byReference or {}
    local rows = {}
    for index = 1, #sets do
        local set = sets[index]
        rows[#rows + 1] = {
            set = set,
            assignment = configurationMode == "unified"
                and { mode = "all", specKeys = {}, enabled = true }
                or byReference["user:" .. set.id]
                or { mode = "none", specKeys = {} },
            index = index,
            active = active
                and active.kind == "user"
                and active.id == set.id
                or false,
        }
    end
    return rows
end

function ConfigCatalog:Create(name, sourceSetId)
    local ready, code, detail = self:EnsureReady()
    if not ready then return nil, code, detail end
    local configurationMode
    configurationMode, code, detail =
        ReadLegacyMode()
    if code then return nil, code, detail end
    if sourceSetId then
        local duplicated
        duplicated, code, detail = Service:DuplicateUserSet(
            self.PROVIDER_ID,
            sourceSetId,
            name,
            { configurationMode = configurationMode }
        )
        if not duplicated then return nil, code, detail end
        self.selectedId = duplicated.id
        return self:Get(duplicated.id)
    end
    local created
    created, code, detail = Service:CreateUserSet(self.PROVIDER_ID, {
        name = name,
        description = "",
        source = {
            kind = "builtin",
            id = Adapter.BUILTIN_ID,
        },
        scopeIds = { "profile" },
        owner = YHUD,
        configurationMode = configurationMode,
    })
    if not created then return nil, code, detail end
    self.selectedId = created.id
    return self:Get(created.id)
end

function ConfigCatalog:Import(value, name)
    local ready, code, detail = self:EnsureReady()
    if not ready then return nil, code, detail end
    local configurationMode
    configurationMode, code, detail =
        ReadLegacyMode()
    if code then return nil, code, detail end
    local metadata = {
        configurationMode = configurationMode,
    }
    if name ~= nil then metadata.name = name end
    local imported
    imported, code, detail = Service:ImportUserSet(
        self.PROVIDER_ID,
        value,
        metadata
    )
    if not imported then return nil, code, detail end
    self.selectedId = imported.id
    return self:Get(imported.id)
end

function ConfigCatalog:Export(setId)
    local ready, code, detail = self:EnsureReady()
    if not ready then return nil, code, detail end
    return Service:ExportUserSet(self.PROVIDER_ID, setId)
end

function ConfigCatalog:Delete(setId)
    local ready, code, detail = self:EnsureReady()
    if not ready then return nil, code, detail end
    local deleted
    deleted, code, detail = Service:DeleteUserSet(self.PROVIDER_ID, setId)
    if not deleted then return nil, code, detail end
    if self.selectedId == setId then self.selectedId = nil end
    Adapter:EnsureDefaultUserSet(true)
    return true
end

function ConfigCatalog:SetAssignment(setId, mode, specKeys)
    local ready, code, detail = self:EnsureReady()
    if not ready then return nil, code, detail end
    return Service:SetAssignment(
        self.PROVIDER_ID,
        UserReference(setId),
        mode,
        specKeys
    )
end

function ConfigCatalog:GetSpecializationGroups(options)
    local ready, code, detail = self:EnsureReady()
    if not ready then return nil, code, detail end
    return Service:GetSpecializationGroups(self.PROVIDER_ID, options)
end

function ConfigCatalog:SetSelected(setId, loadedItem)
    local item, code, detail = loadedItem
    if not item then item, code, detail = self:Get(setId) end
    if not item or not item.set or item.set.id ~= setId then
        return nil, code or "set-not-found", detail
    end
    self.selectedId = setId
    return item
end

function ConfigCatalog:GetSelected()
    local rows, code, detail = self:List()
    if not rows then return nil, code, detail end
    if self.selectedId then
        for index = 1, #rows do
            if rows[index].set.id == self.selectedId then
                return ReadSet(self.selectedId)
            end
        end
    end
    for index = 1, #rows do
        if rows[index].active then
            self.selectedId = rows[index].set.id
            return ReadSet(self.selectedId)
        end
    end
    local first = rows[1]
    if first then self.selectedId = first.set.id end
    return first and ReadSet(first.set.id) or nil
end

function ConfigCatalog:ResolveSelectedId(preferredId)
    if type(preferredId) == "string" and preferredId ~= "" then
        return preferredId
    end
    local rows, code, detail = self:List()
    if not rows then return nil, code, detail end
    if self.selectedId then
        for index = 1, #rows do
            if rows[index].set.id == self.selectedId then
                return self.selectedId
            end
        end
    end
    for index = 1, #rows do
        if rows[index].active then return rows[index].set.id end
    end
    return rows[1] and rows[1].set.id or nil, "set-not-found"
end

function ConfigCatalog:IsActive(setId)
    local rows, code, detail = self:List()
    if not rows then return nil, code, detail end
    for index = 1, #rows do
        local row = rows[index]
        if row.set.id == setId then return row.active == true end
    end
    return nil, "set-not-found"
end

function ConfigCatalog:BeginDraft(setId, options, existingItem)
    local item, code, detail = existingItem
    if not item then item, code, detail = self:Get(setId) end
    if not item then return nil, code, detail end
    if not item.set or item.set.id ~= setId then
        return nil, "set-not-found"
    end
    options = type(options) == "table" and options or {}
    options.specKey = options.specKey or YHUD:GetCurrentSpecKey()
    local draft
    draft, code = ProfileModel:BeginDraft(item.data.profile, options)
    if not draft then return nil, code end
    draft.setId = setId
    draft.packBaseline = item.packBaseline
    draft.storageSnapshot = item.storageData
    draft.runtimeSnapshot = item.data
    return draft
end

CommitPreparedDraft = function(draft, prepared, options)
    local previousStored = draft.storageSnapshot
    local previousRuntime = draft.runtimeSnapshot
    if type(previousStored) ~= "table" or type(previousRuntime) ~= "table" then
        return nil, "invalid-draft-snapshot"
    end
    local revision = tonumber(draft.revision) or 0
    local generation = tonumber(options.generation) or 0
    local token, code, detail = Adapter:CreatePreparedUserSetToken({
        setId = draft.setId,
        targetStored = { profile = prepared.profile },
        targetRuntime = { profile = prepared.runtimeProfile },
        previousStored = previousStored,
        previousRuntime = previousRuntime,
        session = draft,
        revision = revision,
        generation = generation,
    })
    if not token then return nil, code, detail end
    local preparedOptions = {
        preparedToken = token,
        preparedSession = draft,
        preparedRevision = revision,
        preparedGeneration = generation,
        preparedPurpose = "target",
        previewSynchronized = options.previewSynchronized == true,
        deferPreparedEvent = options.apply == true,
        nativeCategoryReloadApproved =
            options.nativeCategoryReloadApproved == true,
        nativeCategorySyncEligible =
            options.nativeCategorySyncEligible ~= false,
        nativeCategoryPlan = options.nativeCategoryPlan,
        nativeCategoryReport = options.nativeCategoryReport,
    }
    local updated
    updated, code, detail = Service:UpdateUserSetData(
        ConfigCatalog.PROVIDER_ID,
        draft.setId,
        { profile = {} },
        { "profile" },
        preparedOptions
    )
    if not updated then
        Adapter:ReleasePreparedUserSetToken(token)
        return nil, code, detail
    end
    local applied
    if options.apply == true then
        if type(options.onCommit) == "function" then
            local committed, commitDetail = pcall(options.onCommit)
            if not committed then
                preparedOptions.preparedPurpose = "rollback"
                local restored, rollbackCode, rollbackDetail =
                    Service:UpdateUserSetData(
                        ConfigCatalog.PROVIDER_ID,
                        draft.setId,
                        { profile = {} },
                        { "profile" },
                        preparedOptions
                    )
                Adapter:ReleasePreparedUserSetToken(token)
                if not restored then
                    return nil,
                        "rollback-failed",
                        rollbackDetail or rollbackCode
                end
                return nil, "commit-callback-failed", commitDetail
            end
        end
        applied, code, detail = Service:Apply(
            ConfigCatalog.PROVIDER_ID,
            UserReference(draft.setId),
            YHUD,
            preparedOptions
        )
        if not applied then
            preparedOptions.preparedPurpose = "rollback"
            local restored, rollbackCode, rollbackDetail =
                Service:UpdateUserSetData(
                    ConfigCatalog.PROVIDER_ID,
                    draft.setId,
                    { profile = {} },
                    { "profile" },
                    preparedOptions
                )
            Adapter:ReleasePreparedUserSetToken(token)
            if not restored then
                return nil,
                    "rollback-failed",
                    rollbackDetail or rollbackCode
            end
            return nil, code, detail
        end
    end
    Adapter:ReleasePreparedUserSetToken(token)
    if options.closeDraft ~= false then ProfileModel:CloseDraft(draft) end
    return {
        set = updated.set,
        data = updated.data,
        summary = options.summary,
        applied = applied ~= nil,
        applyResult = applied,
        compressedCount = prepared.compressedCount,
        serializedCount = prepared.serializedCount,
        reusedCount = prepared.reusedCount,
    }
end

function ConfigCatalog:StartSaveDraft(draft, options)
    if not ProfileModel:IsDraft(draft) or not draft.setId then
        if type(options) == "table" and type(options.onComplete) == "function" then
            options.onComplete(nil, "invalid-draft")
        end
        return { finished = true, Cancel = function() return false end }
    end
    options = type(options) == "table" and options or {}
    local profile, summary = ProfileModel:PrepareDraft(draft)
    if not profile then
        if type(options.onComplete) == "function" then
            options.onComplete(nil, summary)
        end
        return { finished = true, Cancel = function() return false end }
    end
    local revision = tonumber(draft.revision) or 0
    return Adapter:StartPrepareProfileForStorage(
        profile,
        draft.packBaseline,
        draft.runtimeSpecKey or draft.viewSpecKey or YHUD:GetCurrentSpecKey(),
        {
            owned = true,
            dirtySpecs = draft.dirtySpecs,
            isCurrent = function()
                return ProfileModel:IsDraft(draft)
                    and draft.closed ~= true
                    and (tonumber(draft.revision) or 0) == revision
                    and (type(options.isCurrent) ~= "function"
                        or options.isCurrent() == true)
            end,
            onProgress = options.onProgress,
            onComplete = function(prepared, code, detail)
                if not prepared then
                    if type(options.onComplete) == "function" then
                        options.onComplete(nil, code, detail)
                    end
                    return
                end
                if (tonumber(draft.revision) or 0) ~= revision then
                    if type(options.onComplete) == "function" then
                        options.onComplete(nil, "stale-pack-job")
                    end
                    return
                end
                options.summary = summary
                local result
                result, code, detail = CommitPreparedDraft(
                    draft,
                    prepared,
                    options
                )
                if type(options.onComplete) == "function" then
                    options.onComplete(result, code, detail)
                end
            end,
        }
    )
end

function ConfigCatalog:SaveDraft(draft, options)
    if not ProfileModel:IsDraft(draft) or not draft.setId then
        return nil, "invalid-draft"
    end
    options = type(options) == "table" and options or {}
    local profile, summary = ProfileModel:PrepareDraft(draft)
    if not profile then return nil, summary end

    local prepared, code, detail = Adapter:PrepareProfileForSave(
        profile,
        draft.packBaseline,
        draft.runtimeSpecKey or draft.viewSpecKey or YHUD:GetCurrentSpecKey(),
        true,
        { dirtySpecs = draft.dirtySpecs }
    )
    if not prepared then return nil, code, detail end
    options.summary = summary
    return CommitPreparedDraft(draft, prepared, options)
end

function ConfigCatalog:Apply(setId)
    local ready, code, detail = self:EnsureReady()
    if not ready then return nil, code, detail end
    return Service:Apply(
        self.PROVIDER_ID,
        UserReference(setId),
        YHUD
    )
end

function ConfigCatalog:RestoreDraftStorageSnapshot(setId, snapshot)
    if type(setId) ~= "string" or setId == ""
        or type(snapshot) ~= "table" then
        return nil, "invalid-draft-snapshot"
    end
    return Service:UpdateUserSetData(
        self.PROVIDER_ID,
        setId,
        snapshot,
        { "profile" },
        {
            reason = "native-category-reload-recovery",
            owner = YHUD,
        }
    )
end

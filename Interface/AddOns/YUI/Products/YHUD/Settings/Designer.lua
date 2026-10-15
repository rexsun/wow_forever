local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local Catalog = YHUD.ConfigCatalog
local ProfileModel = YHUD.ProfileModel
local CDMCatalog = YHUD.CDMCatalog
local MonitorCatalog = YHUD.MonitorCatalog
local ResourceCatalog = YHUD.ResourceCatalog
if not (Catalog and ProfileModel and CDMCatalog and MonitorCatalog) then return end

local Designer = {
    session = nil,
    openGeneration = 0,
    saveGeneration = 0,
}
YHUD.Designer = Designer

local CLASS_ARMOR_ORDER = {
    PRIEST = 1, MAGE = 1, WARLOCK = 1,
    DEMONHUNTER = 2, DRUID = 2, MONK = 2, ROGUE = 2,
    EVOKER = 3, HUNTER = 3, SHAMAN = 3,
    DEATHKNIGHT = 4, PALADIN = 4, WARRIOR = 4,
}

local function GetClassName(classFile, fallback)
    if YUI.Locale and YUI.Locale.GetClassName then
        return YUI.Locale:GetClassName(classFile, fallback)
    end
    return fallback or classFile or ""
end

local function GetSpecializationName(specID, fallback)
    if YUI.Locale and YUI.Locale.GetSpecializationName then
        return YUI.Locale:GetSpecializationName(specID, fallback)
    end
    return fallback or tostring(specID or "")
end

local function FindInitialGroupId(profile)
    local groups = profile and profile.groups
    local order = groups and groups.order
    local items = groups and groups.items
    if type(order) ~= "table" or type(items) ~= "table" then return nil end
    for index = 1, #order do
        local groupId = order[index]
        if items[groupId] then return groupId end
    end
    return nil
end

local function UpdatePreviewState(session)
    local staticPreview = session.viewSpecKey ~= session.runtimeSpecKey
    session.staticPreview = staticPreview
    session.previewMode = staticPreview and "static" or "runtime"
    session.frozenRuntimePreview = staticPreview
    return staticPreview
end

local function NotifyContextChanged(session, reason)
    local Event = YUI.Event
    if not (Event and type(Event.Emit) == "function") then return end
    Event:Emit("YHUD_DESIGNER_CONTEXT_CHANGED", {
        setId = session.setId,
        reason = reason or "designer-context-changed",
        runtimeSpecKey = session.runtimeSpecKey,
        viewSpecKey = session.viewSpecKey,
        staticPreview = session.staticPreview == true,
    })
end

local function ApplyRuntimeSpecChange(self, session, specKey, reason)
    if not YHUD:IsStableSpecKey(specKey)
        and not (specKey == nil and YHUD:IsInitialSpecialization()) then
        return nil, "invalid-spec-key"
    end
    if session.runtimeSpecKey == specKey then return false end

    session.runtimeSpecKey = specKey
    session.draft.runtimeSpecKey = specKey
    session.runtimeContextChanged = true
    session.runtimeContextReason = reason or "runtime-spec-changed"
    session.runtimeEquivalent = false
    session.previewRuntimeDirty = false
    session.previewRuntimeRevision = nil
    session.presentationProfile = nil
    session.presentationRevision = nil
    session.presentationSpecKey = nil
    session.selectedPreviewMonitorId = nil
    UpdatePreviewState(session)
    NotifyContextChanged(session, session.runtimeContextReason)
    return true
end

local function EnsureSession(self)
    local session = self.session
    if not session or session.closed == true then
        return nil, "designer-not-open"
    end
    if not ProfileModel:IsDraft(session.draft)
        or session.draft.closed == true then
        return nil, "invalid-draft"
    end
    if session.saving == true then return nil, "designer-busy" end
    local currentSpecKey = YHUD:GetCurrentSpecKey()
    if YHUD:IsStableSpecKey(currentSpecKey)
        and currentSpecKey ~= session.runtimeSpecKey then
        ApplyRuntimeSpecChange(
            self,
            session,
            currentSpecKey,
            "runtime-spec-observed"
        )
    end
    return session
end

local function ApplyClaimMutation(session, mutate)
    if type(CDMCatalog.ApplyDraftClaimMutation) ~= "function" then
        if YHUD.Diagnostics and type(YHUD.Diagnostics.Record) == "function" then
            YHUD.Diagnostics:Record(
                "claim-projection",
                "draft-mutation-unavailable"
            )
        end
        return nil, "claim-projection-unavailable"
    end
    return CDMCatalog:ApplyDraftClaimMutation(session.draft, mutate)
end

function Designer:IsOpen()
    return self.session ~= nil and self.session.closed ~= true
end

function Designer:GetSession()
    return EnsureSession(self)
end

function Designer:GetProfile()
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return session.draft.profile
end

function Designer:PlanNativeCategorySync()
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local active
    active, code = Catalog:IsActive(session.setId)
    if active == nil then return nil, code end
    if active ~= true or session.viewSpecKey ~= session.runtimeSpecKey then
        return {
            kind = "cooldown-category-reload",
            requests = {},
        }, nil, {
            changedCount = 0,
            requiresReload = false,
            activationMode = "none",
        }
    end
    local configSets = YHUD.ConfigSets
    if not (configSets
        and type(configSets.PlanNativeCategorySync) == "function") then
        return nil, "native-category-planner-unavailable"
    end
    return configSets:PlanNativeCategorySync(
        session.draft.profile,
        session.runtimeSpecKey
    )
end

local OFFICIAL_REF_PREFIX = "official:"
local PRESET_REF_PREFIX = "preset:"
local CUSTOM_REF_PREFIX = "custom:"

local function GetMonitorOrderRef(profile, monitorId)
    local monitor = profile and profile.monitors
        and profile.monitors[monitorId]
    local entry = monitor and profile.entries
        and profile.entries[monitor.entryKey]
    if not (monitor and entry) then return nil end
    local identity = YHUD:GetEntrySemanticIdentity(entry, monitor.entryKey)
    if type(identity) == "string"
        and (identity:sub(1, #OFFICIAL_REF_PREFIX) == OFFICIAL_REF_PREFIX
            or identity:sub(1, #PRESET_REF_PREFIX) == PRESET_REF_PREFIX) then
        return identity
    end
    return CUSTOM_REF_PREFIX .. monitorId
end

local function AppendUniqueMonitor(target, seen, monitorId)
    if not monitorId or seen[monitorId] then return end
    seen[monitorId] = true
    target[#target + 1] = monitorId
end

local function ApplyPresentationOrder(profile, canonical, specKey)
    local specOverrides = type(canonical.officialOverridesBySpec) == "table"
        and canonical.officialOverridesBySpec[specKey] or nil
    local groupsById = specOverrides and specOverrides.groups or {}
    local monitorByRef = {}
    for monitorId in pairs(profile.monitors or {}) do
        local ref = GetMonitorOrderRef(profile, monitorId)
        if ref and monitorByRef[ref] == nil then
            monitorByRef[ref] = monitorId
        end
    end

    for groupId, group in pairs(profile.groups and profile.groups.items or {}) do
        local storedRefs = type(groupsById[groupId]) == "table"
            and groupsById[groupId] or nil
        local hasResolvedOfficial = false
        for index = 1, #(storedRefs or {}) do
            local ref = storedRefs[index]
            local monitorId = monitorByRef[ref]
            local monitor = monitorId and profile.monitors[monitorId]
            local entry = monitor and profile.entries[monitor.entryKey]
            if monitor and monitor.groupId == groupId
                and entry and entry.origin == "official-cdm" then
                hasResolvedOfficial = true
                break
            end
        end

        local nextOrder = {}
        local seen = {}
        if hasResolvedOfficial then
            for index = 1, #storedRefs do
                local monitorId = monitorByRef[storedRefs[index]]
                local monitor = monitorId and profile.monitors[monitorId]
                if monitor and monitor.groupId == groupId then
                    AppendUniqueMonitor(nextOrder, seen, monitorId)
                end
            end
        else
            local nativeRows = {}
            for index = 1, #(group.monitors or {}) do
                local monitorId = group.monitors[index]
                local monitor = profile.monitors[monitorId]
                local entry = monitor and profile.entries[monitor.entryKey]
                if entry and entry.origin == "official-cdm" then
                    nativeRows[#nativeRows + 1] = {
                        monitorId = monitorId,
                        order = tonumber(entry.order) or math.huge,
                        entryKey = tostring(monitor.entryKey or ""),
                    }
                end
            end
            table.sort(nativeRows, function(left, right)
                if left.order ~= right.order then
                    return left.order < right.order
                end
                return left.entryKey < right.entryKey
            end)
            for index = 1, #nativeRows do
                AppendUniqueMonitor(
                    nextOrder,
                    seen,
                    nativeRows[index].monitorId
                )
            end
        end

        for index = 1, #(group.monitors or {}) do
            AppendUniqueMonitor(nextOrder, seen, group.monitors[index])
        end
        group.monitors = nextOrder
        for index = 1, #nextOrder do
            local monitor = profile.monitors[nextOrder[index]]
            if monitor then
                monitor.groupId = groupId
                monitor.order = index
            end
        end
    end
end

local function BuildPresentationProfile(session, requestedSpecKey)
    local canonical = YHUD:CopyValue(session.draft.root)
    local specKey = requestedSpecKey or session.viewSpecKey
    local source = specKey == session.viewSpecKey
        and session.draft.profile
        or YHUD:GetScopedProfile(canonical, specKey, "virtual")
    if not source then return nil, "presentation-source-failed" end
    local content = YHUD:CreateDefaultContent()
    content.initialization = YHUD:CopyValue(source.initialization or {})
    content.suppressedOfficial = YHUD:CopyValue(
        source.suppressedOfficial or {}
    )
    content.entries = YHUD:CopyValue(source.entries or {})
    content.monitors = YHUD:CopyValue(source.monitors or {})
    content.groupMembers = {}
    for groupId, group in pairs(source.groups.items or {}) do
        content.groupMembers[groupId] = YHUD:CopyValue(group.monitors or {})
    end
    canonical.contentBySpec = type(canonical.contentBySpec) == "table"
        and canonical.contentBySpec or {}
    canonical.contentBySpec[specKey] = content

    local profile = YHUD:GetScopedProfile(canonical, specKey, true)
    if not profile then return nil, "presentation-profile-failed" end
    local semanticIdentities = {}
    for entryKey, entry in pairs(profile.entries or {}) do
        local identity = YHUD:GetEntrySemanticIdentity(entry, entryKey)
        if identity then semanticIdentities[identity] = true end
        if entry.origin == "official-cdm" then
            entry._yhudReadOnlyPreview = true
        end
    end
    for _, monitor in pairs(profile.monitors or {}) do
        local entry = profile.entries[monitor.entryKey]
        if entry and entry.origin == "official-cdm" then
            monitor._yhudReadOnlyPreview = true
        end
    end

    local cache = YHUD.NativePreviewCache
    local snapshot, metadataOrCode
    if cache and cache.Get then
        snapshot, metadataOrCode = cache:Get(specKey)
    else
        metadataOrCode = "native-preview-unavailable"
    end
    local metadata = type(metadataOrCode) == "table"
        and YHUD:CopyValue(metadataOrCode) or {
            code = metadataOrCode,
        }
    metadata.cacheAvailable = snapshot ~= nil
    local specOverrides = type(canonical.officialOverridesBySpec) == "table"
        and canonical.officialOverridesBySpec[specKey] or nil
    local officialPlacement = {}
    for groupId, refs in pairs(specOverrides and specOverrides.groups or {}) do
        if profile.groups.items[groupId] and type(refs) == "table" then
            for index = 1, #refs do
                local ref = refs[index]
                if type(ref) == "string"
                    and ref:sub(1, #OFFICIAL_REF_PREFIX)
                        == OFFICIAL_REF_PREFIX then
                    officialPlacement[ref] = groupId
                end
            end
        end
    end
    for index = 1, #(snapshot and snapshot.entries or {}) do
        local descriptor = snapshot.entries[index]
        local entryKey = descriptor.entryKey
        local identity = "official:" .. tostring(entryKey)
        if content.suppressedOfficial[entryKey] ~= true
            and profile.entries[entryKey] == nil
            and semanticIdentities[identity] ~= true then
            local groupId = officialPlacement[identity]
                or (YHUD.DEFAULT_GROUP_BY_CATEGORY
                    and YHUD.DEFAULT_GROUP_BY_CATEGORY[descriptor.category])
            local group = groupId and profile.groups.items[groupId]
            if group then
                local entry = {
                    entryKey = entryKey,
                    sourceKey = entryKey,
                    origin = "official-cdm",
                    officialCategory = descriptor.category,
                    sourceCategory = descriptor.category,
                    semantic = (descriptor.category == "trackedBuff"
                            or descriptor.category == "trackedBar")
                        and "buff" or "cooldown",
                    cooldownId = descriptor.cooldownId,
                    cooldownID = descriptor.cooldownId,
                    name = descriptor.name,
                    icon = descriptor.icon,
                    order = descriptor.order,
                    isKnown = descriptor.isKnown == true,
                    contentScope = YHUD.CONTENT_SCOPE_SPEC,
                    _yhudReadOnlyPreview = true,
                    _yhudCacheOnlyPreview = true,
                }
                local monitorId = "preview:native:" .. entryKey
                local suffix = 2
                while profile.monitors[monitorId] do
                    monitorId = "preview:native:" .. entryKey .. ":"
                        .. tostring(suffix)
                    suffix = suffix + 1
                end
                local monitor = {
                    id = monitorId,
                    entryKey = entryKey,
                    groupId = groupId,
                    enabled = true,
                    view = group.layout == "bars" and "bar"
                        or group.layout == "rings" and "ring" or "icon",
                    order = #group.monitors + 1,
                    _yhudReadOnlyPreview = true,
                    _yhudCacheOnlyPreview = true,
                }
                profile.entries[entryKey] = entry
                profile.monitors[monitorId] = monitor
                group.monitors[#group.monitors + 1] = monitorId
                semanticIdentities[identity] = true
            end
        end
    end
    ApplyPresentationOrder(profile, canonical, specKey)
    return profile, metadata
end

function Designer:GetPresentationProfile()
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    if session.staticPreview ~= true then return session.draft.profile end
    local revision = tonumber(session.draft.revision) or 0
    if session.presentationProfile
        and session.presentationRevision == revision
        and session.presentationSpecKey == session.viewSpecKey then
        return session.presentationProfile
    end
    local profile, metadata = BuildPresentationProfile(session)
    if not profile then return nil, metadata end
    session.presentationProfile = profile
    session.presentationRevision = revision
    session.presentationSpecKey = session.viewSpecKey
    session.presentationCapturedAt = metadata and metadata.capturedAt or nil
    session.presentationNativeCacheAvailable = metadata
        and metadata.cacheAvailable == true or false
    session.presentationNativeCacheCode = metadata and metadata.code or nil
    return profile
end

function Designer:GetNativePreviewState()
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    if session.staticPreview ~= true then
        return {
            staticPreview = false,
            cacheAvailable = false,
        }
    end
    local profile
    profile, code = self:GetPresentationProfile()
    if not profile then return nil, code end
    return {
        staticPreview = true,
        cacheAvailable = session.presentationNativeCacheAvailable == true,
        capturedAt = session.presentationCapturedAt,
        code = session.presentationNativeCacheCode,
    }
end

local function BuildGroupOrderRefs(profile, groupId)
    local refs = {}
    local seen = {}
    local group = profile and profile.groups and profile.groups.items
        and profile.groups.items[groupId]
    for index = 1, #(group and group.monitors or {}) do
        local ref = GetMonitorOrderRef(profile, group.monitors[index])
        if ref and not seen[ref] then
            seen[ref] = true
            refs[#refs + 1] = ref
        end
    end
    return refs
end

local function FindSemanticMonitorGroup(profile, identity)
    if type(identity) ~= "string" then return nil end
    for _, monitor in pairs(profile and profile.monitors or {}) do
        local entry = profile.entries and profile.entries[monitor.entryKey]
        if entry and YHUD:GetEntrySemanticIdentity(
            entry,
            monitor.entryKey
        ) == identity then
            return monitor.groupId
        end
    end
    return nil
end

function Designer:GetPresentationOrderRefs(specKey, groupId)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    if not YHUD:IsStableSpecKey(specKey) then
        return nil, "invalid-spec-key"
    end
    local profile
    profile, code = BuildPresentationProfile(session, specKey)
    if not profile then return nil, code end
    local group = profile.groups and profile.groups.items
        and profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    return BuildGroupOrderRefs(profile, groupId)
end

function Designer:GetMonitorAccess(monitorId)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    if monitorId and monitorId == session.selectedPreviewMonitorId
        and session.staticPreview == true then
        local profile = self:GetPresentationProfile()
        local monitor = profile and profile.monitors
            and profile.monitors[monitorId]
        local entry = monitor and profile.entries
            and profile.entries[monitor.entryKey]
        if monitor and entry and monitor._yhudCacheOnlyPreview == true then
            return false, "native-read-only", monitor, entry
        end
    end
    return ProfileModel:GetMonitorAccess(session.draft, monitorId)
end

function Designer:GetPreviewState()
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return {
        mode = session.previewMode,
        staticPreview = session.staticPreview == true,
        frozen = session.frozenRuntimePreview == true,
        runtimeSpecKey = session.runtimeSpecKey,
        viewSpecKey = session.viewSpecKey,
    }
end

function Designer:CanUseRuntimePreview()
    local state, code = self:GetPreviewState()
    if not state then return nil, code end
    if state.staticPreview then return false, "static-preview", state end
    return true, nil, state
end

function Designer:OnRuntimeSpecChanged(specKey, reason)
    local session = self.session
    if not session or session.closed == true then return false end
    if not ProfileModel:IsDraft(session.draft)
        or session.draft.closed == true then
        return nil, "invalid-draft"
    end
    return ApplyRuntimeSpecChange(self, session, specKey, reason)
end

function Designer:SwitchViewSpec(specKey)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    if not YHUD:IsStableSpecKey(specKey) then
        return nil, "invalid-spec-key"
    end
    if session.viewSpecKey == specKey then
        return session.draft.profile, self:GetPreviewState()
    end

    local previousGroupId = session.selectedGroupId
    local profile
    profile, code = ProfileModel:SwitchDraftSpec(session.draft, specKey)
    if not profile then return nil, code end

    session.viewSpecKey = specKey
    -- Retain the legacy alias until every Designer consumer has moved to the
    -- explicit view/runtime keys.
    session.specKey = specKey
    session.selectedMonitorId = nil
    session.selectedPreviewMonitorId = nil
    session.pendingRestore = nil
    local groups = profile.groups and profile.groups.items
    if not (groups and groups[previousGroupId]) then
        session.selectedGroupId = FindInitialGroupId(profile)
    end
    session.resourceClassFile = nil
    session.resourceSpecID = nil
    session.resourceFormKey = nil
    session.runtimeEquivalent = false
    session.previewRuntimeRevision = nil
    session.presentationProfile = nil
    session.presentationRevision = nil
    session.presentationSpecKey = nil
    UpdatePreviewState(session)
    NotifyContextChanged(session, "view-spec-changed")
    return profile, self:GetPreviewState()
end

local function AssignmentEnablesSpec(assignment, specKey)
    assignment = type(assignment) == "table" and assignment or {}
    if assignment.mode == "all" or assignment.mode == "default" then
        return true
    end
    if assignment.mode ~= "specs" then return false end
    local specKeys = assignment.specKeys or {}
    if specKeys[specKey] == true then return true end
    for index = 1, #specKeys do
        if specKeys[index] == specKey then return true end
    end
    return false
end

function Designer:GetSpecializationSections()
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local runtimeClass = (session.runtimeSpecKey or session.viewSpecKey)
        and (session.runtimeSpecKey or session.viewSpecKey):match("^([^:]+):")
        or nil
    local sections = {
        { id = "current-class", rows = {} },
        { id = "enabled", rows = {} },
        { id = "disabled", rows = {} },
    }
    local classes = ResourceCatalog and ResourceCatalog.GetClasses
        and ResourceCatalog:GetClasses() or {}
    for classIndex = 1, #classes do
        local classInfo = classes[classIndex]
        local classFile = classInfo.classFile
        local specs = ResourceCatalog:GetSpecializations(classFile)
        for specIndex = 1, #specs do
            local spec = specs[specIndex]
            local specKey = classFile .. ":" .. tostring(spec.specID)
            local enabled = AssignmentEnablesSpec(session.assignment, specKey)
            local row = {
                value = specKey,
                specKey = specKey,
                text = GetSpecializationName(spec.specID, spec.name or tostring(spec.specID)),
                icon = spec.icon,
                classFile = classFile,
                className = GetClassName(classFile, classInfo.className or classFile),
                classID = classInfo.classID or 999,
                specID = spec.specID,
                specIndex = spec.specIndex or specIndex,
                armor = CLASS_ARMOR_ORDER[classFile] or 99,
                current = specKey == session.runtimeSpecKey,
                viewed = specKey == session.viewSpecKey,
                enabled = enabled,
            }
            local section = classFile == runtimeClass and sections[1]
                or (enabled and sections[2] or sections[3])
            section.rows[#section.rows + 1] = row
        end
    end
    local function SortRows(left, right)
        if left.armor ~= right.armor then return left.armor < right.armor end
        if left.classID ~= right.classID then
            return left.classID < right.classID
        end
        return left.specIndex < right.specIndex
    end
    for index = 1, #sections do table.sort(sections[index].rows, SortRows) end
    return sections
end

function Designer:CopySelectedMonitorToSpecializations(targetSpecKeys)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    if not session.selectedMonitorId then return nil, "monitor-not-selected" end
    local monitor = session.draft.profile.monitors[session.selectedMonitorId]
    if not monitor then return nil, "monitor-not-found" end
    local entry = session.draft.profile.entries[monitor.entryKey]
    local identity = entry and YHUD:GetEntrySemanticIdentity(
        entry,
        monitor.entryKey
    ) or nil
    local targetOrderRefsBySpec = {}
    for index = 1, #(targetSpecKeys or {}) do
        local specKey = targetSpecKeys[index]
        if YHUD:IsStableSpecKey(specKey)
            and specKey ~= session.viewSpecKey then
            local presentation
            presentation, code = BuildPresentationProfile(session, specKey)
            if not presentation then return nil, code end
            local refsByGroup = {
                [monitor.groupId] = BuildGroupOrderRefs(
                    presentation,
                    monitor.groupId
                ),
            }
            local previousGroupId = FindSemanticMonitorGroup(
                presentation,
                identity
            )
            if previousGroupId and previousGroupId ~= monitor.groupId then
                refsByGroup[previousGroupId] = BuildGroupOrderRefs(
                    presentation,
                    previousGroupId
                )
            end
            targetOrderRefsBySpec[specKey] = refsByGroup
        end
    end
    return ProfileModel:CopyMonitorToSpecializations(
        session.draft,
        session.selectedMonitorId,
        targetSpecKeys,
        {
            targetOrderRefsBySpec = targetOrderRefsBySpec,
        }
    )
end

function Designer:SyncSelectedMonitorToSpecializations(targetSpecKeys, scopes)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    if not session.selectedMonitorId then return nil, "monitor-not-selected" end
    return ProfileModel:SyncMonitorToSpecializations(
        session.draft,
        session.selectedMonitorId,
        targetSpecKeys,
        scopes
    )
end

function Designer:GetEquipmentTriggerProjection()
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    if not YHUD.GetEquipmentTriggerProjection then
        return nil, "equipment-trigger-provider-unavailable"
    end
    return YHUD:GetEquipmentTriggerProjection(session.draft.profile)
end

local function FindResourceClass(classFile)
    if not (ResourceCatalog and ResourceCatalog.GetClasses) then return nil end
    classFile = type(classFile) == "string" and string.upper(classFile) or nil
    local classes = ResourceCatalog:GetClasses()
    for index = 1, #classes do
        local info = classes[index]
        if info.classFile == classFile then return info end
    end
    return nil
end

local function FindResourceSpec(classFile, specID)
    if not (ResourceCatalog and ResourceCatalog.GetSpecializations) then
        return nil
    end
    specID = tonumber(specID)
    local specs = ResourceCatalog:GetSpecializations(classFile)
    for index = 1, #specs do
        local info = specs[index]
        if tonumber(info.specID) == specID then return info end
    end
    return nil
end

function Designer:GetResourcePreviewContext()
    local session, code = EnsureSession(self)
    if not session then return nil, nil, code end
    if not ResourceCatalog then return nil, nil, "resource-catalog-unavailable" end

    local classFile = session.resourceClassFile
    local specID = session.resourceSpecID
    if not FindResourceClass(classFile) or not FindResourceSpec(classFile, specID) then
        classFile = session.viewSpecKey
            and session.viewSpecKey:match("^([^:]+):") or nil
        specID = session.viewSpecKey
            and tonumber(session.viewSpecKey:match(":(%d+)$")) or nil
    end
    if (not FindResourceClass(classFile)
        or not FindResourceSpec(classFile, specID))
        and session.staticPreview ~= true then
        classFile, specID = ResourceCatalog:GetCurrentContext()
    end
    if not FindResourceClass(classFile) then
        local classes = ResourceCatalog:GetClasses()
        classFile = classes[1] and classes[1].classFile or nil
    end
    if not FindResourceSpec(classFile, specID) then
        local specs = ResourceCatalog:GetSpecializations(classFile)
        specID = specs[1] and specs[1].specID or nil
    end

    local formKey = session.resourceFormKey
    local formOptions = ResourceCatalog:GetFormOptions(classFile, specID)
    local formFound = false
    for index = 1, #formOptions do
        if formOptions[index].key == formKey then formFound = true break end
    end
    if not formFound then
        formKey = ResourceCatalog:GetDefaultFormKey(classFile, specID)
    end

    session.resourceClassFile = classFile
    session.resourceSpecID = specID
    session.resourceFormKey = formKey
    return classFile, specID, formKey
end

function Designer:SetResourcePreviewClass(classFile)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local classInfo = FindResourceClass(classFile)
    if not classInfo then return nil, "resource-class-not-found" end
    local specs = ResourceCatalog:GetSpecializations(classInfo.classFile)
    local spec = specs[1]
    if not spec then return nil, "resource-spec-not-found" end

    session.resourceClassFile = classInfo.classFile
    session.resourceSpecID = spec.specID
    session.resourceFormKey = ResourceCatalog:GetDefaultFormKey(
        classInfo.classFile,
        spec.specID
    )
    return classInfo.classFile, spec.specID, session.resourceFormKey
end

function Designer:SetResourcePreviewSpec(specID)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local classFile = session.resourceClassFile
    if not FindResourceClass(classFile) then
        classFile = self:GetResourcePreviewContext()
    end
    local spec = FindResourceSpec(classFile, specID)
    if not spec then return nil, "resource-spec-not-found" end
    session.resourceClassFile = classFile
    session.resourceSpecID = spec.specID
    local options = ResourceCatalog:GetFormOptions(classFile, spec.specID)
    local found = false
    for index = 1, #options do
        if options[index].key == session.resourceFormKey then found = true break end
    end
    if not found then
        session.resourceFormKey = ResourceCatalog:GetDefaultFormKey(
            classFile,
            spec.specID
        )
    end
    return spec
end

function Designer:SetResourcePreviewForm(formKey)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local classFile, specID = self:GetResourcePreviewContext()
    local options = ResourceCatalog:GetFormOptions(classFile, specID)
    for index = 1, #options do
        if options[index].key == formKey then
            session.resourceFormKey = formKey
            return formKey
        end
    end
    return nil, "resource-form-not-found"
end

function Designer:IsDirty()
    local session = self.session
    return session ~= nil
        and session.closed ~= true
        and session.draft
        and session.draft.changed == true
        or false
end

function Designer:ReconcileNativeSettings()
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    if session.staticPreview == true then
        return nil, "static-preview", self:GetPreviewState()
    end

    local draft = session.draft
    local canonical, summary = ProfileModel:PrepareDraft(draft)
    if not canonical then return nil, summary end

    local result, report = CDMCatalog:ReconcileContext(
        canonical,
        session.viewSpecKey,
        { reason = "native-settings-designer" }
    )
    if not result then return nil, report end
    if report.changed ~= true then return false, report end

    local staged
    staged, code = ProfileModel:BeginDraft(result, {
        specKey = session.viewSpecKey,
        runtimeSpecKey = session.runtimeSpecKey,
        combat = draft.combat == true,
    })
    if not staged then return nil, code end

    local changed = draft.changed == true
    local revision = tonumber(draft.revision) or 0
    local adopted
    adopted, code = ProfileModel:AdoptDraft(draft, staged)
    if not adopted then return nil, code end
    draft.changed = changed
    draft.revision = revision + 1

    local profile = draft.profile
    if ProfileModel.NormalizeSpecialOverflowOrders then
        local normalized
        normalized, code = ProfileModel:NormalizeSpecialOverflowOrders(draft)
        if normalized == nil then return nil, code end
    end
    if not (profile.groups and profile.groups.items
        and profile.groups.items[session.selectedGroupId]) then
        session.selectedGroupId = FindInitialGroupId(profile)
        session.selectedMonitorId = nil
    elseif session.selectedMonitorId
        and not profile.monitors[session.selectedMonitorId] then
        session.selectedMonitorId = nil
    end
    session.runtimeEquivalent = false
    return true, report
end

function Designer:SetGroupPlacements(placements)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ProfileModel:SetGroupPlacements(session.draft, placements)
end

local function FinishOpenFromItem(
    self,
    item,
    options,
    activeReference,
    specKey,
    generation
)
    local code, detail
    local runtimeEquivalent = activeReference
        and activeReference.kind == "user"
        and activeReference.id == item.set.id
        and options.runtimeSpecAvailable ~= false
        or false

    local draft
    draft, code, detail = Catalog:BeginDraft(item.set.id, options, item)
    if not draft then return nil, code, detail end
    local draftSetId = draft.setId
    local coordination = item.coordinationContext
    local coordinated = item.materializedSpecKey == specKey
        and (type(coordination) ~= "table"
            or coordination.specKey == specKey
                and (coordination.generation == nil
                    or coordination.generation == generation))
    local report = coordinated and item.materializationReport or nil
    local reconcileChanged = type(report) == "table"
        and report.changed == true or false
    if not report and options.runtimeSpecAvailable ~= false
        and YHUD.CDMCatalog and YHUD.CDMCatalog.ReconcileContext then
        local seeded
        seeded, report = YHUD.CDMCatalog:ReconcileContext(
            draft.root,
            specKey
        )
        reconcileChanged = seeded ~= nil
            and type(report) == "table"
            and report.changed == true
            or false
        if seeded and reconcileChanged then
            local reconciledDraft
            reconciledDraft, code = ProfileModel:BeginDraft(seeded, {
                specKey = specKey,
                runtimeSpecKey = options.runtimeSpecKey,
                runtimeSpecAvailable = options.runtimeSpecAvailable,
                combat = options.combat == true,
            })
            if not reconciledDraft then return nil, code end
            reconciledDraft.setId = draftSetId
            reconciledDraft.packBaseline = draft.packBaseline
            reconciledDraft.storageSnapshot = draft.storageSnapshot
            reconciledDraft.runtimeSnapshot = draft.runtimeSnapshot
            reconciledDraft.dirtySpecs[specKey] = true
            draft = reconciledDraft
            -- Reconciliation establishes the editable baseline. It is not a
            -- user edit and must not trigger the unsaved-changes dialog.
        end
    end
    if reconcileChanged then runtimeEquivalent = false end
    if ProfileModel.NormalizeSpecialOverflowOrders then
        local normalized
        normalized, code = ProfileModel:NormalizeSpecialOverflowOrders(draft)
        if normalized == nil then return nil, code end
        if normalized > 0 then runtimeEquivalent = false end
    end
    Catalog:SetSelected(item.set.id, item)

    local runtimeSpecKey
    if options.runtimeSpecAvailable ~= false then
        runtimeSpecKey = options.runtimeSpecKey or specKey
    end
    local session = {
        setId = item.set.id,
        name = item.set.name,
        assignment = YHUD:CopyValue(item.assignment),
        runtimeSpecKey = runtimeSpecKey or nil,
        viewSpecKey = specKey,
        specKey = specKey,
        draft = draft,
        selectedGroupId = FindInitialGroupId(draft.profile),
        selectedMonitorId = nil,
        selectedPreviewMonitorId = nil,
        pendingRestore = nil,
        runtimeEquivalent = runtimeEquivalent == true,
        reconcileChanged = reconcileChanged,
        previewRuntimeDirty = false,
        previewRuntimeRevision = runtimeEquivalent and not reconcileChanged
            and (draft.revision or 0) or nil,
        previewRuntimeRebuildRequired = false,
        closed = false,
        generation = generation,
    }
    UpdatePreviewState(session)
    self.session = session
    return session
end

local function GetActiveReference()
    return YUI.Settings
        and YUI.Settings.ConfigSets
        and YUI.Settings.ConfigSets.GetActiveReference
        and YUI.Settings.ConfigSets:GetActiveReference(Catalog.PROVIDER_ID)
end

local function GetReusableRuntimeProfile(
    activeReference,
    setId,
    specKey,
    runtimeSpecKey
)
    if runtimeSpecKey ~= specKey
        or type(activeReference) ~= "table"
        or activeReference.kind ~= "user"
        or activeReference.id ~= setId then
        return nil
    end
    local profile = YHUD._runtimeProfile
    if type(profile) ~= "table"
        or YHUD._runtimeProfileSpecKey ~= specKey
        or YHUD._runtimeProfileCanonical ~= YHUD:GetConfigProfile()
        or YHUD._runtimeProfileRevision
            ~= (tonumber(YHUD.runtimeProfileRevision) or 0) then
        return nil
    end
    local catalog = YHUD.CDMCatalog
    if catalog then
        if catalog.pendingReason or catalog.pendingTimer
            or catalog.pendingCombat == true then
            return nil
        end
        if type(catalog.IsLayoutSignatureCurrent) == "function"
            and catalog:IsLayoutSignatureCurrent(specKey) ~= true then
            return nil
        end
    end
    return profile
end

function Designer:Open(setId, options)
    if self:IsOpen() then return nil, "designer-already-open" end
    local runtimeSpecKey = YHUD:GetCurrentSpecKey()
    local specKey = runtimeSpecKey or YHUD:GetFirstCurrentClassSpecKey()
    if not YHUD:IsStableSpecKey(specKey) then
        return nil, "invalid-spec-key"
    end
    options = type(options) == "table" and options or {}
    options.specKey = specKey
    options.runtimeSpecKey = runtimeSpecKey
    options.runtimeSpecAvailable = runtimeSpecKey ~= nil
    local activeReference = GetActiveReference()
    local resolvedId, code, detail = Catalog:ResolveSelectedId(
        setId or (activeReference and activeReference.kind == "user"
            and activeReference.id or nil)
    )
    if not resolvedId then return nil, code, detail end
    local item
    item, code, detail = Catalog:Get(resolvedId, {
        specKey = specKey,
        runtimeProfile = GetReusableRuntimeProfile(
            activeReference,
            resolvedId,
            specKey,
            runtimeSpecKey
        ),
    })
    if not item then return nil, code or "set-not-found", detail end
    self.openGeneration = self.openGeneration + 1
    return FinishOpenFromItem(
        self,
        item,
        options,
        activeReference,
        specKey,
        self.openGeneration
    )
end

function Designer:StartOpen(setId, options)
    if self:IsOpen() then
        if type(options) == "table" and type(options.onComplete) == "function" then
            options.onComplete(nil, "designer-already-open")
        end
        return { finished = true, Cancel = function() return false end }
    end
    local runtimeSpecKey = YHUD:GetCurrentSpecKey()
    local specKey = runtimeSpecKey or YHUD:GetFirstCurrentClassSpecKey()
    if not YHUD:IsStableSpecKey(specKey) then
        if type(options) == "table" and type(options.onComplete) == "function" then
            options.onComplete(nil, "invalid-spec-key")
        end
        return { finished = true, Cancel = function() return false end }
    end
    options = type(options) == "table" and options or {}
    local activeReference = GetActiveReference()
    local resolvedId, code, detail = Catalog:ResolveSelectedId(
        setId or (activeReference and activeReference.kind == "user"
            and activeReference.id or nil)
    )
    if not resolvedId then
        if type(options.onComplete) == "function" then
            options.onComplete(nil, code, detail)
        end
        return { finished = true, Cancel = function() return false end }
    end
    self.openGeneration = self.openGeneration + 1
    local generation = self.openGeneration
    local runtimeProfile = GetReusableRuntimeProfile(
        activeReference,
        resolvedId,
        specKey,
        runtimeSpecKey
    )
    return Catalog:StartGet(resolvedId, {
        specKey = specKey,
        runtimeProfile = runtimeProfile,
        generation = generation,
        isCurrent = function()
            return self.session == nil
                and self.openGeneration == generation
                and (type(options.isCurrent) ~= "function"
                    or options.isCurrent() == true)
        end,
        onProgress = options.onProgress,
        onComplete = function(item, resultCode, resultDetail)
            if not item then
                if type(options.onComplete) == "function" then
                    options.onComplete(nil, resultCode, resultDetail)
                end
                return
            end
            if self.openGeneration ~= generation or self.session ~= nil then
                if type(options.onComplete) == "function" then
                    options.onComplete(nil, "stale-pack-job")
                end
                return
            end
            local openOptions = {
                specKey = specKey,
                runtimeSpecKey = runtimeSpecKey,
                runtimeSpecAvailable = runtimeSpecKey ~= nil,
                combat = options.combat == true,
            }
            local session
            session, resultCode, resultDetail = FinishOpenFromItem(
                self,
                item,
                openOptions,
                activeReference,
                specKey,
                generation
            )
            if type(options.onComplete) == "function" then
                options.onComplete(session, resultCode, resultDetail)
            end
        end,
    })
end

function Designer:SelectGroup(groupId)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local groups = session.draft.profile.groups
    if not groups or not groups.items[groupId] then
        return nil, "group-not-found"
    end
    session.selectedGroupId = groupId
    session.selectedMonitorId = nil
    session.selectedPreviewMonitorId = nil
    session.pendingRestore = nil
    return groups.items[groupId]
end

function Designer:GetGroupMonitorSummary(groupId)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    groupId = groupId or session.selectedGroupId
    local profile = session.staticPreview == true
        and self:GetPresentationProfile() or session.draft.profile
    local group = profile.groups and profile.groups.items
        and profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end

    local currentAvailable = 0
    local currentTotal = 0
    for index = 1, #(group.monitors or {}) do
        local monitor = profile.monitors[group.monitors[index]]
        local entry = monitor and profile.entries[monitor.entryKey]
        if monitor then
            currentTotal = currentTotal + 1
            local availability = entry and YHUD:EvaluateEntryAvailability(
                entry,
                session.viewSpecKey
            ) or "available"
            if monitor.enabled ~= false and availability == "available" then
                currentAvailable = currentAvailable + 1
            end
        end
    end

    local otherTotal = 0
    local countedSpecs = {}
    for specKey, content in pairs(session.draft.root.contentBySpec or {}) do
        if specKey ~= session.viewSpecKey and type(content) == "table" then
            countedSpecs[specKey] = true
            local members = content.groupMembers
                and content.groupMembers[groupId]
            if type(members) == "table" then
                if type(members.before) == "table"
                    or type(members.after) == "table" then
                    otherTotal = otherTotal + #(members.before or {})
                        + #(members.after or {})
                else
                    otherTotal = otherTotal + #members
                end
            end
        end
    end
    local summaries = session.draft.root.specDocuments
        and session.draft.root.specDocuments.summaries or nil
    for specKey, summary in pairs(type(summaries) == "table"
        and summaries or {}) do
        if specKey ~= session.viewSpecKey and not countedSpecs[specKey]
            and type(summary) == "table"
            and type(summary.groupCounts) == "table" then
            otherTotal = otherTotal
                + (tonumber(summary.groupCounts[groupId]) or 0)
        end
    end
    return {
        currentAvailable = currentAvailable,
        currentTotal = currentTotal,
        otherTotal = otherTotal,
    }
end

function Designer:ClearSelection()
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    session.selectedGroupId = nil
    session.selectedMonitorId = nil
    session.selectedPreviewMonitorId = nil
    session.pendingRestore = nil
    return true
end

function Designer:ListMonitorOptions(groupId, semanticFamily, options)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    if type(semanticFamily) == "table" and options == nil then
        options = semanticFamily
        semanticFamily = options.semanticFamily
    end
    local catalogOptions = {}
    for key, value in pairs(type(options) == "table" and options or {}) do
        catalogOptions[key] = value
    end
    catalogOptions.includeOfficial =
        session.viewSpecKey == session.runtimeSpecKey
    return MonitorCatalog:Build(
        session.draft.profile,
        session.specKey,
        groupId or session.selectedGroupId,
        semanticFamily,
        catalogOptions
    )
end

function Designer:AddMonitorOption(option, groupId)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local result
    result, code = ApplyClaimMutation(session, function(staged)
        return MonitorCatalog:Apply(
            staged,
            groupId or session.selectedGroupId,
            option
        )
    end)
    if not result then return nil, code end
    session.selectedGroupId = result.groupId or session.selectedGroupId
    session.selectedMonitorId =
        result.monitor and result.monitor.id or session.selectedMonitorId
    return result
end

function Designer:AddMonitorOptions(options, groupId)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    if type(options) ~= "table" or #options == 0 then
        return nil, "invalid-options"
    end
    local targetGroupId = groupId or session.selectedGroupId
    local results
    results, code = ApplyClaimMutation(session, function(staged)
        local stagedResults = {}
        for index = 1, #options do
            local option = options[index]
            local state = type(option) == "table"
                and (option.pickerState or option.status) or nil
            if state ~= "add" and state ~= "move" then
                return nil, "invalid-batch-option"
            end
            local result, applyCode = MonitorCatalog:Apply(
                staged,
                targetGroupId,
                option
            )
            if not result then return nil, applyCode end
            stagedResults[#stagedResults + 1] = result
        end
        return stagedResults
    end)
    if not results then return nil, code end
    session.selectedGroupId = targetGroupId
    local last = results[#results]
    session.selectedMonitorId = last and last.monitor
        and last.monitor.id or session.selectedMonitorId
    return results
end

local function GetBundleContextSelection(session, bundleKind)
    session.bundleContextByKind = type(session.bundleContextByKind) == "table"
        and session.bundleContextByKind or {}
    local selected = session.bundleContextByKind[bundleKind]
    if bundleKind == "racial" then
        if MonitorCatalog.NormalizeRacialContextKey then
            selected = MonitorCatalog:NormalizeRacialContextKey(selected)
        end
        if type(selected) ~= "string" or selected == "" then
            local _, currentRace = MonitorCatalog:GetRacialContexts()
            selected = currentRace
        end
    elseif not YHUD:IsStableSpecKey(selected) then
        selected = session.specKey
    end
    session.bundleContextByKind[bundleKind] = selected
    return selected
end

function Designer:GetSpellBundleContexts(bundleKind)
    local session, code = EnsureSession(self)
    if not session then return nil, nil, code end
    if bundleKind ~= "racial"
        and bundleKind ~= "defensive"
        and bundleKind ~= "interruptControl" then
        return nil, nil, "invalid-spell-bundle"
    end
    local contexts = {}
    if bundleKind == "racial" then
        local rows, currentRace = MonitorCatalog:GetRacialContexts()
        for index = 1, #rows do
            local row = rows[index]
            contexts[index] = {
                value = row.key,
                text = row.name,
                raceID = row.raceID,
                raceFile = row.raceFile,
                current = row.current,
            }
        end
        local selected = GetBundleContextSelection(session, bundleKind)
        if not selected then selected = currentRace end
        return contexts, selected
    end

    local currentClass = session.specKey and session.specKey:match("^([^:]+):")
    local classes = ResourceCatalog and ResourceCatalog.GetClasses
        and ResourceCatalog:GetClasses() or {}
    for classIndex = 1, #classes do
        local classInfo = classes[classIndex]
        local classFile = classInfo.classFile
        local specs = ResourceCatalog:GetSpecializations(classFile)
        for specIndex = 1, #specs do
            local spec = specs[specIndex]
            local specKey = classFile .. ":" .. tostring(spec.specID)
            local _, options = MonitorCatalog:GetSpellBundleOptions(
                session.draft.profile,
                bundleKind,
                specKey
            )
            if #(options or {}) > 0 then
                contexts[#contexts + 1] = {
                    value = specKey,
                    text = GetClassName(classFile, classInfo.className or classFile)
                        .. " - " .. GetSpecializationName(spec.specID, spec.name or tostring(spec.specID)),
                    icon = spec.icon,
                    classFile = classFile,
                    className = GetClassName(classFile, classInfo.className or classFile),
                    specID = spec.specID,
                    specName = GetSpecializationName(spec.specID, spec.name or tostring(spec.specID)),
                    current = specKey == session.specKey,
                    currentClass = classFile == currentClass,
                    armor = CLASS_ARMOR_ORDER[classFile] or 99,
                    classID = classInfo.classID or 999,
                    specIndex = spec.specIndex or specIndex,
                }
            end
        end
    end
    table.sort(contexts, function(left, right)
        if left.current ~= right.current then return left.current end
        if left.currentClass ~= right.currentClass then
            return left.currentClass
        end
        if left.armor ~= right.armor then return left.armor < right.armor end
        if left.classID ~= right.classID then
            return left.classID < right.classID
        end
        return left.specIndex < right.specIndex
    end)
    return contexts, GetBundleContextSelection(session, bundleKind)
end

function Designer:SetSpellBundleContext(bundleKind, contextKey)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    if bundleKind == "racial"
        and MonitorCatalog.NormalizeRacialContextKey then
        contextKey = MonitorCatalog:NormalizeRacialContextKey(contextKey)
    end
    local contexts = self:GetSpellBundleContexts(bundleKind)
    for index = 1, #(contexts or {}) do
        if contexts[index].value == contextKey then
            session.bundleContextByKind[bundleKind] = contextKey
            return true
        end
    end
    return nil, "spell-bundle-context-unavailable"
end

function Designer:GetPlayerRacialOptions(contextKey)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return MonitorCatalog:GetPlayerRacialOptions(
        session.draft.profile,
        contextKey or GetBundleContextSelection(session, "racial")
    )
end

function Designer:SetRacialSpellEnabled(spellID, enabled)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ApplyClaimMutation(session, function(staged)
        return MonitorCatalog:SetRacialSpellEnabled(
            staged,
            spellID,
            enabled,
            GetBundleContextSelection(session, "racial")
        )
    end)
end

function Designer:GetSpellBundleOptions(bundleKind)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    if bundleKind == "racial" then
        return MonitorCatalog:GetPlayerRacialOptions(
            session.draft.profile,
            GetBundleContextSelection(session, bundleKind)
        )
    end
    return MonitorCatalog:GetSpellBundleOptions(
        session.draft.profile,
        bundleKind,
        GetBundleContextSelection(session, bundleKind)
    )
end

function Designer:SetSpellBundleEnabled(bundleKind, spellID, enabled)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    if bundleKind == "racial" then
        return ApplyClaimMutation(session, function(staged)
            return MonitorCatalog:SetRacialSpellEnabled(
                staged,
                spellID,
                enabled,
                GetBundleContextSelection(session, bundleKind)
            )
        end)
    end
    return ApplyClaimMutation(session, function(staged)
        return MonitorCatalog:SetSpellBundleEnabled(
            staged,
            bundleKind,
            spellID,
            enabled,
            GetBundleContextSelection(session, bundleKind)
        )
    end)
end

function Designer:MoveSpellBundleSpell(bundleKind, spellID, targetIndex)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return MonitorCatalog:MoveSpellBundleSpell(
        session.draft,
        bundleKind,
        spellID,
        targetIndex,
        GetBundleContextSelection(session, bundleKind)
    )
end

function Designer:AddCustomSpell(spellID, groupId)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local result
    result, code = MonitorCatalog:AddCustomSpell(
        session.draft,
        groupId or session.selectedGroupId,
        spellID
    )
    if not result then return nil, code end
    session.selectedGroupId = result.groupId or session.selectedGroupId
    session.selectedMonitorId =
        result.monitor and result.monitor.id or session.selectedMonitorId
    return result
end

function Designer:AddCustomItem(itemID, groupId)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local result
    result, code = ApplyClaimMutation(session, function(staged)
        return MonitorCatalog:AddCustomItem(
            staged,
            groupId or session.selectedGroupId,
            itemID
        )
    end)
    if not result then return nil, code end
    session.selectedGroupId = result.groupId or session.selectedGroupId
    session.selectedMonitorId =
        result.monitor and result.monitor.id or session.selectedMonitorId
    return result
end

function Designer:AddCustomAura(spellID, scopeKey, groupId)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local result
    result, code = MonitorCatalog:AddCustomAura(
        session.draft,
        session.specKey,
        groupId or session.selectedGroupId,
        spellID,
        scopeKey
    )
    if not result then return nil, code end
    session.selectedGroupId = result.groupId or session.selectedGroupId
    session.selectedMonitorId =
        result.monitor and result.monitor.id or session.selectedMonitorId
    return result
end

function Designer:AddCustomBuffTimer(
    spellID,
    durationSeconds,
    groupId
)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local result
    result, code = MonitorCatalog:AddCustomBuffTimer(
        session.draft,
        session.specKey,
        groupId or session.selectedGroupId,
        spellID,
        durationSeconds
    )
    if not result then return nil, code end
    session.selectedGroupId = result.groupId or session.selectedGroupId
    session.selectedMonitorId =
        result.monitor and result.monitor.id or session.selectedMonitorId
    return result
end

function Designer:SelectMonitor(monitorId)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local monitor = session.draft.profile.monitors[monitorId]
    if not monitor and session.staticPreview == true then
        local profile = self:GetPresentationProfile()
        local previewMonitor = profile and profile.monitors
            and profile.monitors[monitorId]
        local previewEntry = previewMonitor and profile.entries
            and profile.entries[previewMonitor.entryKey]
        if previewMonitor and previewEntry
            and previewMonitor._yhudCacheOnlyPreview == true then
            session.selectedGroupId = previewMonitor.groupId
            session.selectedMonitorId = nil
            session.selectedPreviewMonitorId = monitorId
            session.pendingRestore = nil
            return previewMonitor
        end
    end
    if not monitor then return nil, "monitor-not-found" end
    session.selectedGroupId = monitor.groupId
    session.selectedMonitorId = monitorId
    session.selectedPreviewMonitorId = nil
    local entry = session.draft.profile.entries[monitor.entryKey]
    local bundleKind = entry and entry.bundleKind
    if bundleKind == "defensive" or bundleKind == "interruptControl" then
        session.bundleContextByKind = type(session.bundleContextByKind) == "table"
            and session.bundleContextByKind or {}
        session.bundleContextByKind[bundleKind] = session.viewSpecKey
    end
    session.pendingRestore = nil
    return monitor
end

function Designer:GetSelectedMonitorId()
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return session.selectedMonitorId or session.selectedPreviewMonitorId
end

function Designer:GetSelectedMonitor()
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local monitorId = session.selectedMonitorId or session.selectedPreviewMonitorId
    if not monitorId then return nil, "monitor-not-selected" end
    local profile = session.selectedPreviewMonitorId == monitorId
        and self:GetPresentationProfile() or session.draft.profile
    local monitor = profile and profile.monitors[monitorId]
    if not monitor then
        if session.selectedPreviewMonitorId == monitorId then
            session.selectedPreviewMonitorId = nil
        else
            session.selectedMonitorId = nil
        end
        return nil, "monitor-not-found"
    end
    return monitor
end

function Designer:GetEditableMonitorIdentity(monitorId)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    monitorId = monitorId or session.selectedMonitorId
    if not monitorId then return nil, "monitor-not-selected" end
    local descriptor = MonitorCatalog:GetEditableMonitorIdentity(
        session.draft.profile,
        monitorId
    )
    if not descriptor then return nil, "monitor-identity-readonly" end
    return descriptor
end

function Designer:ReplaceMonitorIdentity(monitorId, value, durationSeconds)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local allowed
    allowed, code = ProfileModel:GetMonitorAccess(session.draft, monitorId)
    if allowed ~= true then return nil, code end
    monitorId = monitorId or session.selectedMonitorId
    if not monitorId then return nil, "monitor-not-selected" end
    local result
    result, code = ApplyClaimMutation(session, function(staged)
        return MonitorCatalog:ReplaceMonitorIdentity(
            staged,
            monitorId,
            value,
            durationSeconds
        )
    end)
    if not result then return nil, code end
    session.selectedGroupId = result.groupId or session.selectedGroupId
    session.selectedMonitorId = result.monitor
        and result.monitor.id or session.selectedMonitorId
    return result
end

function Designer:SetMonitorGlow(monitorId, definition)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    monitorId = monitorId or session.selectedMonitorId
    if not monitorId then return nil, "monitor-not-selected" end
    return ProfileModel:SetMonitorGlow(
        session.draft,
        monitorId,
        definition
    )
end

function Designer:SetMonitorSound(monitorId, definition)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    monitorId = monitorId or session.selectedMonitorId
    if not monitorId then return nil, "monitor-not-selected" end
    return ProfileModel:SetMonitorSound(
        session.draft,
        monitorId,
        definition
    )
end

function Designer:SetNativeProcGlow(definition)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ProfileModel:SetNativeProcGlow(session.draft, definition)
end

function Designer:SetMonitorNativeProcGlowOverride(monitorId, definition)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    monitorId = monitorId or session.selectedMonitorId
    if not monitorId then return nil, "monitor-not-selected" end
    return ProfileModel:SetMonitorNativeProcGlowOverride(
        session.draft,
        monitorId,
        definition
    )
end

function Designer:SetMonitorVisibilityMode(monitorId, value)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    monitorId = monitorId or session.selectedMonitorId
    if not monitorId then return nil, "monitor-not-selected" end
    return ProfileModel:SetMonitorVisibilityMode(
        session.draft,
        monitorId,
        value
    )
end

function Designer:SetSkillAuraDisplay(enabled)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ProfileModel:SetSkillAuraDisplay(session.draft, enabled)
end

function Designer:SetGlobalMonitorStateEffect(key, enabled)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ProfileModel:SetGlobalMonitorStateEffect(
        session.draft,
        key,
        enabled
    )
end

function Designer:SetPandemicGlow(enabled)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ProfileModel:SetPandemicGlow(session.draft, enabled)
end

function Designer:SetMonitorSkillAuraDisplayOverride(monitorId, value)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    monitorId = monitorId or session.selectedMonitorId
    if not monitorId then return nil, "monitor-not-selected" end
    return ProfileModel:SetMonitorSkillAuraDisplayOverride(
        session.draft,
        monitorId,
        value
    )
end

function Designer:SetMonitorStateEffect(monitorId, key, value)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    monitorId = monitorId or session.selectedMonitorId
    if not monitorId then return nil, "monitor-not-selected" end
    return ProfileModel:SetMonitorStateEffect(
        session.draft,
        monitorId,
        key,
        value
    )
end

function Designer:ResetMonitorStateEffects(monitorId)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    monitorId = monitorId or session.selectedMonitorId
    if not monitorId then return nil, "monitor-not-selected" end
    return ProfileModel:ResetMonitorStateEffects(session.draft, monitorId)
end

function Designer:SetMonitorAppearanceOverride(monitorId, patch)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    monitorId = monitorId or session.selectedMonitorId
    if not monitorId then return nil, "monitor-not-selected" end
    return ProfileModel:SetMonitorAppearanceOverride(
        session.draft,
        monitorId,
        patch
    )
end

function Designer:ResetMonitorAppearanceOverride(monitorId)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    monitorId = monitorId or session.selectedMonitorId
    if not monitorId then return nil, "monitor-not-selected" end
    return ProfileModel:ResetMonitorAppearanceOverride(
        session.draft,
        monitorId
    )
end

function Designer:CountSkillAuraDisplayOverrides()
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ProfileModel:CountSkillAuraDisplayOverrides(session.draft)
end

function Designer:ClearSkillAuraDisplayOverrides()
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ProfileModel:ClearSkillAuraDisplayOverrides(session.draft)
end

function Designer:CountMonitorStateEffectOverrides(key)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ProfileModel:CountMonitorStateEffectOverrides(
        session.draft,
        key
    )
end

function Designer:ClearMonitorStateEffectOverrides(key)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ProfileModel:ClearMonitorStateEffectOverrides(
        session.draft,
        key
    )
end

function Designer:ListMonitorTargets(monitorId)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    monitorId = monitorId or session.selectedMonitorId
    local profile = session.draft.profile
    local monitor = monitorId and profile.monitors[monitorId]
    if not monitor then return nil, "monitor-not-found" end

    local result = {}
    local groups = profile.groups
    local order = groups and groups.order or {}
    local items = groups and groups.items or {}
    for index = 1, #order do
        local groupId = order[index]
        local group = items[groupId]
        local placed = group and ProfileModel:CanPlace(
            profile,
            monitor.entryKey,
            groupId,
            ProfileModel:GetDefaultView(group.layout)
        )
        if placed then
            result[#result + 1] = group
        end
    end
    return result
end

function Designer:MoveMonitor(monitorId, groupId, targetIndex)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local current = session.draft.profile.monitors[monitorId]
    if current and current.groupId == (groupId or session.selectedGroupId)
        and targetIndex == nil then
        session.selectedGroupId = current.groupId
        session.selectedMonitorId = current.id
        return current
    end
    local targetGroupId = groupId or session.selectedGroupId
    local targetGroup =
        session.draft.profile.groups.items[targetGroupId]
    if not targetGroup then return nil, "group-not-found" end
    local monitor
    monitor, code = ApplyClaimMutation(session, function(staged)
        local stagedGroup = staged.profile.groups.items[targetGroupId]
        if not stagedGroup then return nil, "group-not-found" end
        return ProfileModel:MoveMonitor(
            staged,
            monitorId,
            targetGroupId,
            targetIndex,
            ProfileModel:GetDefaultView(stagedGroup.layout)
        )
    end)
    if not monitor then return nil, code end
    session.selectedGroupId = monitor.groupId
    session.selectedMonitorId = monitor.id
    return monitor
end

function Designer:ReorderMonitor(monitorId, targetLane, targetIndex)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local monitor
    monitor, code =
        ProfileModel:ReorderMonitor(
            session.draft,
            monitorId,
            targetLane,
            targetIndex
        )
    if not monitor then return nil, code end
    session.selectedGroupId = monitor.groupId
    session.selectedMonitorId = monitor.id
    return monitor
end

function Designer:ReorderMonitorRelative(monitorId, placement)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    if type(placement) ~= "table" then
        return nil, "invalid-drop-placement"
    end
    local viewSpecKey = session.viewSpecKey or session.draft.viewSpecKey
        or session.draft.specKey
    if placement.sourceSpecKey ~= nil
        and placement.sourceSpecKey ~= viewSpecKey then
        return nil, "drop-context-changed"
    end

    local source = session.draft.profile.monitors
        and session.draft.profile.monitors[monitorId]
    if not source then return nil, "monitor-not-found" end
    local groupId = source.groupId
    if placement.sourceGroupId ~= nil
        and placement.sourceGroupId ~= groupId then
        return nil, "drop-context-changed"
    end
    local presentation
    presentation, code = self:GetPresentationProfile()
    if not presentation then return nil, code end
    local presentationSource = presentation.monitors
        and presentation.monitors[monitorId]
    if not presentationSource or presentationSource.groupId ~= groupId then
        return nil, "drop-context-changed"
    end

    local presentationRefs = BuildGroupOrderRefs(presentation, groupId)
    local presentationRefSet = {}
    for index = 1, #presentationRefs do
        presentationRefSet[presentationRefs[index]] = true
    end

    local refs = {}
    local seen = {}
    local specKey = viewSpecKey
    local specOverrides = type(session.draft.root.officialOverridesBySpec)
        == "table" and session.draft.root.officialOverridesBySpec[specKey] or nil
    local storedRefs = specOverrides and type(specOverrides.groups) == "table"
        and specOverrides.groups[groupId] or nil
    for index = 1, #(storedRefs or {}) do
        local ref = storedRefs[index]
        local isUnresolvedOfficial = type(ref) == "string"
            and ref:sub(1, #OFFICIAL_REF_PREFIX) == OFFICIAL_REF_PREFIX
        if not seen[ref] and (presentationRefSet[ref] or isUnresolvedOfficial) then
            seen[ref] = true
            refs[#refs + 1] = ref
        end
    end
    for index = 1, #presentationRefs do
        local ref = presentationRefs[index]
        if not seen[ref] then
            seen[ref] = true
            refs[#refs + 1] = ref
        end
    end

    local sourceRef = GetMonitorOrderRef(presentation, monitorId)
    local sourceIndex
    for index = 1, #refs do
        if refs[index] == sourceRef then
            sourceIndex = index
            break
        end
    end
    if not sourceIndex then return nil, "drop-source-changed" end
    table.remove(refs, sourceIndex)

    local insertIndex
    if placement.kind == "head" then
        insertIndex = 1
    elseif placement.kind == "tail" then
        insertIndex = #refs + 1
    elseif type(placement.beforeMonitorId) == "string" then
        local anchor = presentation.monitors
            and presentation.monitors[placement.beforeMonitorId]
        if not anchor or anchor.groupId ~= groupId
            or anchor.id == monitorId then
            return nil, "drop-anchor-changed"
        end
        local anchorRef = GetMonitorOrderRef(
            presentation,
            placement.beforeMonitorId
        )
        for index = 1, #refs do
            if refs[index] == anchorRef then
                insertIndex = index
                break
            end
        end
        if not insertIndex then return nil, "drop-anchor-changed" end
    else
        return nil, "invalid-drop-placement"
    end
    table.insert(refs, insertIndex, sourceRef)

    local monitor
    monitor, code = ProfileModel:ReorderMonitorByOrderRefs(
        session.draft,
        monitorId,
        groupId,
        refs
    )
    if not monitor then return nil, code end
    session.selectedGroupId = monitor.groupId
    session.selectedMonitorId = monitor.id
    return monitor
end

function Designer:RemoveMonitor(monitorId, allSpecializations)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local monitor = session.draft.profile.monitors[monitorId]
    if not monitor then return nil, "monitor-not-found" end
    local entry = session.draft.profile.entries[monitor.entryKey]
    local bundleKind = entry and entry.bundleKind
    if not bundleKind and entry and entry.sourceType == "racial-bundle" then
        bundleKind = "racial"
    end
    local groupId = monitor.groupId
    local removed
    removed, code = ApplyClaimMutation(session, function(staged)
        if allSpecializations == true then
            return ProfileModel:RemoveMonitorFromAllSpecializations(
                staged, monitorId, bundleKind and function(scopeDraft)
                    return MonitorCatalog:SetSpellBundleActive(scopeDraft, bundleKind, false)
                end or nil
            )
        end
        local stagedRemoved, stagedCode =
            ProfileModel:RemoveMonitor(staged, monitorId)
        if not stagedRemoved then return nil, stagedCode end
        if bundleKind then
            return MonitorCatalog:SetSpellBundleActive(
                staged,
                bundleKind,
                false
            )
        end
        return true
    end)
    if not removed then return nil, code end
    session.selectedGroupId = groupId
    if session.selectedMonitorId == monitorId then
        session.selectedMonitorId = nil
    end
    return true
end

function Designer:CreateGroup(name, contentPolicy, layout)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    if contentPolicy == "icons"
        or contentPolicy == "bars"
        or contentPolicy == "rings" then
        layout = contentPolicy
        contentPolicy = nil
    end
    layout = layout or "icons"
    contentPolicy = contentPolicy
        or (layout == "resource" and "resource-only")
        or ((layout == "bars" or layout == "rings")
            and "buff-only" or "cooldown-primary")
    local group
    group, code = ProfileModel:CreateGroup(session.draft, {
        name = name,
        layout = layout,
        contentPolicy = contentPolicy,
    })
    if not group then return nil, code end
    session.selectedGroupId = group.id
    session.selectedMonitorId = nil
    session.pendingRestore = nil
    return group
end

function Designer:CreateCooldownGroup(name)
    return self:CreateGroup(name, "cooldown-primary", "icons")
end

function Designer:CreateBuffGroup(name, layout)
    return self:CreateGroup(name, "buff-only", layout or "icons")
end

function Designer:RenameGroup(groupId, name)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    groupId = groupId or session.selectedGroupId
    local group = session.draft.profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.name == name then return true end
    return ProfileModel:RenameGroup(session.draft, groupId, name)
end

function Designer:SetGroupEnabled(groupId, enabled)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ApplyClaimMutation(session, function(staged)
        return ProfileModel:SetGroupEnabled(staged, groupId, enabled)
    end)
end

function Designer:SetGroupLayoutMode(groupId, layoutMode)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    groupId = groupId or session.selectedGroupId
    return ProfileModel:SetGroupLayoutMode(
        session.draft,
        groupId,
        layoutMode
    )
end

function Designer:SetGroupDisplayLayer(groupId, displayLayer)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    groupId = groupId or session.selectedGroupId
    return ProfileModel:SetGroupDisplayLayer(
        session.draft,
        groupId,
        displayLayer
    )
end

function Designer:SetGroupUnavailablePreview(groupId, enabled)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    groupId = groupId or session.selectedGroupId
    return ProfileModel:SetGroupUnavailablePreview(
        session.draft,
        groupId,
        enabled
    )
end

function Designer:SetGroupTooltip(groupId, enabled)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    groupId = groupId or session.selectedGroupId
    return ProfileModel:SetGroupTooltip(
        session.draft,
        groupId,
        enabled
    )
end

function Designer:SetGroupVisibility(groupId, rule)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    groupId = groupId or session.selectedGroupId
    return ProfileModel:SetGroupVisibility(session.draft, groupId, rule)
end

function Designer:SetSkyridingSettings(patch)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ProfileModel:SetSkyridingSettings(session.draft, patch)
end

function Designer:SetSkyridingStyleSettings(styleId, patch)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ProfileModel:SetSkyridingStyleSettings(
        session.draft,
        styleId,
        patch
    )
end

function Designer:SetGroupIconLayout(groupId, patch)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    groupId = groupId or session.selectedGroupId
    return ProfileModel:SetGroupIconLayout(
        session.draft,
        groupId,
        patch
    )
end

function Designer:SetGroupIconStyle(groupId, patch)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    groupId = groupId or session.selectedGroupId
    return ProfileModel:SetGroupIconStyle(
        session.draft,
        groupId,
        patch
    )
end

function Designer:SetGroupDurationLayout(groupId, patch)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    groupId = groupId or session.selectedGroupId
    return ProfileModel:SetGroupDurationLayout(
        session.draft,
        groupId,
        patch
    )
end

function Designer:SetGroupDurationOrientation(groupId, orientation)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    groupId = groupId or session.selectedGroupId
    return ProfileModel:SetGroupDurationOrientation(
        session.draft,
        groupId,
        orientation
    )
end

function Designer:SetGroupDurationStyle(groupId, patch)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    groupId = groupId or session.selectedGroupId
    return ProfileModel:SetGroupDurationStyle(
        session.draft,
        groupId,
        patch
    )
end

function Designer:SetGroupResourceLayout(groupId, patch)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    groupId = groupId or session.selectedGroupId
    return ProfileModel:SetGroupResourceLayout(
        session.draft,
        groupId,
        patch
    )
end

function Designer:SetGroupResourceStyle(groupId, patch)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    groupId = groupId or session.selectedGroupId
    return ProfileModel:SetGroupResourceStyle(
        session.draft,
        groupId,
        patch
    )
end

function Designer:SetPlayerCastSettings(patch)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ProfileModel:SetPlayerCastSettings(session.draft, patch)
end

function Designer:SetResourceSetting(resourceId, patch)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ProfileModel:SetResourceSetting(session.draft, resourceId, patch, session.selectedGroupId)
end

function Designer:SetResourceTextOverride(resourceId, enabled, patch)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ProfileModel:SetResourceTextOverride(
        session.draft,
        resourceId,
        enabled,
        patch,
        session.selectedGroupId
    )
end

function Designer:SetResourceAppearanceOverride(resourceId, enabled, patch)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    return ProfileModel:SetResourceAppearanceOverride(
        session.draft,
        resourceId,
        enabled,
        patch,
        session.selectedGroupId
    )
end

function Designer:SetResourcePresetEnabled(resourceId, enabled)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local classFile, specID, formKey
    classFile, specID, formKey = self:GetResourcePreviewContext()
    if not classFile or not specID then return nil, code end
    if formKey then
        return ProfileModel:SetResourceFormPresetEnabled(
            session.draft,
            classFile,
            specID,
            formKey,
            resourceId,
            enabled,
            session.selectedGroupId
        )
    end
    return ProfileModel:SetResourcePresetEnabled(
        session.draft,
        classFile,
        specID,
        resourceId,
        enabled,
        session.selectedGroupId
    )
end

function Designer:MoveResourcePreset(resourceId, targetIndex, enabledOnly)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local classFile, specID, formKey
    classFile, specID, formKey = self:GetResourcePreviewContext()
    if not classFile or not specID then return nil, code end
    if formKey then
        return ProfileModel:MoveResourceFormPreset(
            session.draft,
            classFile,
            specID,
            formKey,
            resourceId,
            targetIndex,
            session.selectedGroupId,
            enabledOnly
        )
    end
    return ProfileModel:MoveResourcePreset(
        session.draft,
        classFile,
        specID,
        resourceId,
        targetIndex,
        enabledOnly,
        session.selectedGroupId
    )
end

function Designer:ResetResourceFormOverride()
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local classFile, specID, formKey = self:GetResourcePreviewContext()
    if not formKey then return nil, "resource-form-not-found" end
    return ProfileModel:ResetResourceFormOverride(
        session.draft,
        classFile,
        specID,
        formKey,
        session.selectedGroupId
    )
end

function Designer:DeleteGroup(groupId)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    groupId = groupId or session.selectedGroupId

    local deleted
    deleted, code = ProfileModel:DeleteGroup(session.draft, groupId)
    if not deleted then return nil, code end

    session.selectedGroupId = nil
    session.selectedMonitorId = nil
    session.pendingRestore = nil
    return true
end

function Designer:PreviewDefaultRestore(groupId, options)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    groupId = groupId or session.selectedGroupId
    local category = YHUD.DEFAULT_CATEGORY_BY_GROUP[groupId]
    if not category then return nil, "default-group-required" end

    local restoreOptions = {}
    for key, value in pairs(type(options) == "table" and options or {}) do
        restoreOptions[key] = value
    end
    restoreOptions.specKey = session.specKey
    local preview
    preview, code =
        CDMCatalog:BuildRestorePreview(
            session.draft.profile,
            category,
            restoreOptions
        )
    if not preview then return nil, code end
    session.pendingRestore = preview
    return preview
end

function Designer:ConfirmDefaultRestore(preview)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    preview = preview or session.pendingRestore
    if not preview or preview ~= session.pendingRestore then
        return nil, "restore-confirmation-required"
    end

    local report
    report, code =
        CDMCatalog:ApplyRestorePreview(session.draft, preview)
    if not report then return nil, code end
    session.selectedGroupId = report.defaultGroupId
    session.pendingRestore = nil
    return report
end

function Designer:CancelDefaultRestore()
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    session.pendingRestore = nil
    return true
end

function Designer:Save(options)
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    options = type(options) == "table" and options or {}

    local apply = options.apply
    if apply == nil then
        apply, code = Catalog:IsActive(session.setId)
        if apply == nil then return nil, code end
    end

    local result, detail
    result, code, detail = Catalog:SaveDraft(session.draft, {
        apply = apply == true,
        nativeCategoryReloadApproved =
            options.nativeCategoryReloadApproved == true,
        nativeCategorySyncEligible = apply == true
            and session.viewSpecKey == session.runtimeSpecKey,
        nativeCategoryPlan = options.nativeCategoryPlan,
        nativeCategoryReport = options.nativeCategoryReport,
        closeDraft = options.keepSessionForReload ~= true,
    })
    if not result then return nil, code, detail end

    if options.keepSessionForReload ~= true then
        session.closed = true
        self.session = nil
    end
    return result
end

function Designer:StartSave(options)
    local session, code = EnsureSession(self)
    if not session then
        if type(options) == "table" and type(options.onComplete) == "function" then
            options.onComplete(nil, code)
        end
        return { finished = true, Cancel = function() return false end }
    end
    if session.saving == true then
        if type(options) == "table" and type(options.onComplete) == "function" then
            options.onComplete(nil, "busy")
        end
        return { finished = true, Cancel = function() return false end }
    end
    options = type(options) == "table" and options or {}
    local apply = options.apply
    if apply == nil then
        apply, code = Catalog:IsActive(session.setId)
        if apply == nil then
            if type(options.onComplete) == "function" then
                options.onComplete(nil, code)
            end
            return { finished = true, Cancel = function() return false end }
        end
    end
    self.saveGeneration = self.saveGeneration + 1
    local generation = self.saveGeneration
    local revision = tonumber(session.draft.revision) or 0
    local previewSynchronized = apply == true
        and session.staticPreview ~= true
        and session.viewSpecKey == session.runtimeSpecKey
        and session.previewRuntimeDirty == true
        and session.previewRuntimeRevision == revision
        and session.previewRuntimeRebuildRequired ~= true
    session.saving = true
    local underlying
    local proxy = { finished = false }
    function proxy:Cancel()
        if self.finished then return false end
        self.finished = true
        local cancelled = underlying and underlying.Cancel
            and underlying:Cancel() or false
        if Designer.session == session
            and Designer.saveGeneration == generation then
            session.saving = false
            Designer.saveGeneration = Designer.saveGeneration + 1
        end
        return cancelled
    end
    underlying = Catalog:StartSaveDraft(session.draft, {
        apply = apply == true,
        nativeCategoryReloadApproved =
            options.nativeCategoryReloadApproved == true,
        nativeCategorySyncEligible = apply == true
            and session.viewSpecKey == session.runtimeSpecKey,
        nativeCategoryPlan = options.nativeCategoryPlan,
        nativeCategoryReport = options.nativeCategoryReport,
        closeDraft = options.keepSessionForReload ~= true,
        generation = generation,
        previewSynchronized = previewSynchronized,
        isCurrent = function()
            return Designer.session == session
                and session.closed ~= true
                and session.saving == true
                and Designer.saveGeneration == generation
                and (tonumber(session.draft.revision) or 0) == revision
        end,
        onProgress = options.onProgress,
        onCommit = options.onCommit,
        onComplete = function(result, resultCode, resultDetail)
            proxy.finished = true
            if Designer.session == session
                and Designer.saveGeneration == generation then
                session.saving = false
            end
            if result and options.keepSessionForReload ~= true then
                session.closed = true
                Designer.session = nil
            end
            if type(options.onComplete) == "function" then
                options.onComplete(result, resultCode, resultDetail)
            end
        end,
    })
    if underlying and underlying.finished then proxy.finished = true end
    return proxy
end

function Designer:Cancel()
    local session, code = EnsureSession(self)
    if not session then return nil, code end
    local closed
    closed, code = ProfileModel:CancelDraft(session.draft)
    if not closed then return nil, code end
    session.closed = true
    self.session = nil
    self.saveGeneration = self.saveGeneration + 1
    return true
end

function Designer:ForceClose()
    if not self:IsOpen() then return true end
    return self:Cancel()
end

function Designer:Switch(setId, resolution, options)
    local session, code = EnsureSession(self)
    if not session then return self:Open(setId, options) end
    if setId == session.setId then return session end

    if session.draft.changed == true then
        if resolution == nil then return nil, "unsaved-changes" end
        if resolution == "cancel" then return nil, "cancelled" end
        if resolution == "save" then
            local saved, detail
            saved, code, detail = self:Save()
            if not saved then return nil, code, detail end
        elseif resolution == "discard" then
            local discarded
            discarded, code = self:Cancel()
            if not discarded then return nil, code end
        else
            return nil, "invalid-resolution"
        end
    else
        local discarded
        discarded, code = self:Cancel()
        if not discarded then return nil, code end
    end

    return self:Open(setId, options)
end

function Designer:StartSwitch(setId, resolution, options)
    options = type(options) == "table" and options or {}
    local session, code = EnsureSession(self)
    if not session then
        return self:StartOpen(setId, options)
    end
    if setId == session.setId then
        if type(options.onComplete) == "function" then
            options.onComplete(session)
        end
        return { finished = true, Cancel = function() return false end }
    end
    if session.draft.changed == true then
        if resolution == nil then
            if type(options.onComplete) == "function" then
                options.onComplete(nil, "unsaved-changes")
            end
            return { finished = true, Cancel = function() return false end }
        end
        if resolution == "cancel" then
            if type(options.onComplete) == "function" then
                options.onComplete(nil, "cancelled")
            end
            return { finished = true, Cancel = function() return false end }
        end
        if resolution ~= "save" and resolution ~= "discard" then
            if type(options.onComplete) == "function" then
                options.onComplete(nil, "invalid-resolution")
            end
            return { finished = true, Cancel = function() return false end }
        end
    end

    local chain = { finished = false, cancelled = false }
    local underlying
    function chain:Cancel()
        if self.finished or self.cancelled then return false end
        self.cancelled = true
        if underlying and type(underlying.Cancel) == "function" then
            underlying:Cancel()
        end
        return true
    end
    local function Complete(result, resultCode, resultDetail)
        if chain.finished or chain.cancelled then return end
        chain.finished = true
        if type(options.onComplete) == "function" then
            options.onComplete(result, resultCode, resultDetail)
        end
    end
    local function OpenTarget()
        if chain.cancelled then return end
        underlying = self:StartOpen(setId, {
            isCurrent = options.isCurrent,
            onProgress = options.onProgress,
            onComplete = Complete,
        })
    end
    local function DiscardAndOpen()
        local discarded, discardCode = self:Cancel()
        if not discarded then
            Complete(nil, discardCode)
            return
        end
        OpenTarget()
    end

    if session.draft.changed == true and resolution == "save" then
        local saveJob = self:StartSave({
            onProgress = options.onProgress,
            onComplete = function(result, resultCode, resultDetail)
                if chain.cancelled then return end
                if not result then
                    Complete(nil, resultCode, resultDetail)
                    return
                end
                OpenTarget()
            end,
        })
        if underlying == nil then underlying = saveJob end
    else
        DiscardAndOpen()
    end
    return chain
end

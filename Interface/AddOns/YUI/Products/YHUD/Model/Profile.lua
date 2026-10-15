local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local ProfileModel = {}
YHUD.ProfileModel = ProfileModel

local DRAFT_MARKER = "yhud-profile-draft-v1"

local LAYOUT_VIEWS = {
    icons = {
        icon = true,
    },
    bars = {
        bar = true,
    },
    rings = {
        ring = true,
    },
    resource = {},
}

local DEFAULT_VIEW = {
    icons = "icon",
    bars = "bar",
    rings = "ring",
}

local CATEGORY_LAYOUTS = {
    essential = {
        icons = true,
    },
    utility = {
        icons = true,
    },
    trackedBuff = {
        icons = true,
        bars = true,
        rings = true,
    },
    trackedBar = {
        bars = true,
        rings = true,
    },
}

local RING_THICKNESS_VALUES = {
    [4] = true,
    [8] = true,
    [14] = true,
    [22] = true,
}

local function IsStableId(value)
    return type(value) == "string"
        and value ~= ""
        and #value <= 160
        and value:match("^[%w%._:%-]+$") ~= nil
end

local function IsDraft(value)
    return type(value) == "table"
        and value.marker == DRAFT_MARKER
        and type(value.profile) == "table"
end

local function EnsureOpenDraft(draft)
    if not IsDraft(draft) then return nil, "invalid-draft" end
    if draft.closed then return nil, "draft-closed" end
    return true
end

local function ArrayIndex(values, target)
    if type(values) ~= "table" then return nil end
    for index = 1, #values do
        if values[index] == target then return index end
    end
    return nil
end

local function RemoveArrayValue(values, target)
    local index = ArrayIndex(values, target)
    if not index then return nil end
    table.remove(values, index)
    return index
end

local function InsertArrayValue(values, value, index)
    index = tonumber(index)
    if index then
        index = math.floor(index)
        if index < 1 then index = 1 end
        if index > #values + 1 then index = #values + 1 end
        table.insert(values, index, value)
        return index
    end
    values[#values + 1] = value
    return #values
end

local function NormalizeGroupOrders(profile)
    local order = profile.groups.order
    for index = 1, #order do
        local group = profile.groups.items[order[index]]
        if group then group.order = index end
    end
end

local function NormalizeMonitorOrders(profile, groupId)
    local group = profile.groups.items[groupId]
    if not group then return end
    for index = 1, #group.monitors do
        local monitor = profile.monitors[group.monitors[index]]
        if monitor then monitor.order = index end
    end
end

local function GetMonitorLane(profile, monitorId)
    return YHUD.CONTENT_LANE_SPEC
end

local function SetMonitorLane(profile, monitorId, lane)
    return YHUD.CONTENT_LANE_SPEC
end

local function GetGroupLanes(profile, groupId, omittedMonitorId)
    local result = {
        [YHUD.CONTENT_LANE_SPEC] = {},
    }
    local group = profile.groups.items[groupId]
    for index = 1, #(group and group.monitors or {}) do
        local monitorId = group.monitors[index]
        if monitorId ~= omittedMonitorId then
            result[YHUD.CONTENT_LANE_SPEC][
                #result[YHUD.CONTENT_LANE_SPEC] + 1
            ] = monitorId
        end
    end
    return result
end

local function ApplyGroupLanes(profile, groupId, lanes)
    local group = profile.groups.items[groupId]
    if not group then return false end
    local members = {}
    local laneMembers = lanes[YHUD.CONTENT_LANE_SPEC] or {}
    for index = 1, #laneMembers do
        local monitorId = laneMembers[index]
        members[#members + 1] = monitorId
    end
    group.monitors = members
    NormalizeMonitorOrders(profile, groupId)
    return true
end

local function DefaultMonitorLane(monitor)
    return YHUD.CONTENT_LANE_SPEC
end

local function MarkChanged(draft)
    draft.changed = true
    draft.revision = (draft.revision or 0) + 1
end

local function MarkSpecChanged(draft, specKey)
    specKey = specKey or draft.viewSpecKey or draft.specKey
    if YHUD:IsStableSpecKey(specKey) then
        draft.dirtySpecs[specKey] = true
    end
    MarkChanged(draft)
end

local function VirtualScopeHasContent(profile)
    if rawget(profile, "_yhudVirtualContent") ~= true then return true end
    if next(profile.entries or {}) or next(profile.monitors or {})
        or next(profile.suppressedOfficial or {}) then
        return true
    end
    local initialization = profile.initialization or {}
    for key, value in pairs(initialization) do
        if not (key == "nativeSeedVersion" and tonumber(value) == 0) then
            return true
        end
    end
    return false
end

local function PersistDraftScope(draft)
    if rawget(draft.profile, "_yhudVirtualContent") == true
        and not VirtualScopeHasContent(draft.profile) then
        return draft.profile
    end
    local scoped, code = YHUD:PersistScopedProfile(draft.profile)
    if not scoped then return nil, code end
    draft.profile = scoped
    draft.root = rawget(scoped, "_yhudCanonical") or draft.root
    return scoped
end

local function ValuesEqual(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not ValuesEqual(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function MarkDirty(draft, groupId, specOwned)
    if not draft.dirtyGroups[groupId] then
        draft.dirtyGroups[groupId] = true
        draft.dirtyGroupCount = draft.dirtyGroupCount + 1
    end
    if specOwned == true then
        MarkSpecChanged(draft)
    else
        MarkChanged(draft)
    end
end

local function IsSpecialMonitor(profile, monitorId)
    local monitor = profile and profile.monitors
        and profile.monitors[monitorId]
    local entry = monitor and profile.entries
        and profile.entries[monitor.entryKey]
    return monitor ~= nil
        and YHUD:IsFilteredAuraLayoutMonitor(entry, monitor, true) == true
end

local function IsSpecialOverflowOrderValid(
    profile,
    group,
    monitorIds,
    projectionContext
)
    local state = YHUD.GetSpecialMonitorGroupState
        and YHUD:GetSpecialMonitorGroupState(
            profile,
            group,
            true,
            projectionContext
        )
    if not (state and state.segmented == true) then return true end
    local specialStarted = false
    for index = 1, #(monitorIds or {}) do
        if IsSpecialMonitor(profile, monitorIds[index]) then
            specialStarted = true
        elseif specialStarted then
            return false
        end
    end
    return true
end

local function NormalizeSpecialOverflowOrder(profile, group, projectionContext)
    local state = YHUD.GetSpecialMonitorGroupState
        and YHUD:GetSpecialMonitorGroupState(
            profile,
            group,
            true,
            projectionContext
        )
    if not (state and state.segmented == true) then return false end
    local nextMonitors = {}
    for index = 1, #(group.monitors or {}) do
        local monitorId = group.monitors[index]
        if not IsSpecialMonitor(profile, monitorId) then
            nextMonitors[#nextMonitors + 1] = monitorId
        end
    end
    for index = 1, #(group.monitors or {}) do
        local monitorId = group.monitors[index]
        if IsSpecialMonitor(profile, monitorId) then
            nextMonitors[#nextMonitors + 1] = monitorId
        end
    end
    if ValuesEqual(group.monitors, nextMonitors) then return false end
    group.monitors = nextMonitors
    NormalizeMonitorOrders(profile, group.id)
    return true
end

function ProfileModel:IsSpecialOverflowOrderValid(profile, group, monitorIds)
    return IsSpecialOverflowOrderValid(profile, group, monitorIds)
end

function ProfileModel:NormalizeSpecialOverflowOrder(draft, groupId)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local group = draft.profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if not NormalizeSpecialOverflowOrder(draft.profile, group) then
        return false
    end
    MarkDirty(draft, groupId, true)
    return true
end

function ProfileModel:NormalizeSpecialOverflowOrders(draft)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local changed = 0
    local projectionContext = YHUD.BuildMonitorLayoutProjectionContext
        and YHUD:BuildMonitorLayoutProjectionContext(draft.profile, true)
        or nil
    for index = 1, #(draft.profile.groups.order or {}) do
        local groupId = draft.profile.groups.order[index]
        local group = draft.profile.groups.items[groupId]
        if group and NormalizeSpecialOverflowOrder(
            draft.profile,
            group,
            projectionContext
        ) then
            MarkDirty(draft, groupId, true)
            changed = changed + 1
        end
    end
    return changed
end

function ProfileModel:MarkDraftChanged(draft)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    MarkSpecChanged(draft)
    return true
end

function ProfileModel:SetPlayerCastSettings(draft, patch)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    if type(patch) ~= "table" or type(patch.hideNative) ~= "boolean" then return nil, "invalid-settings" end
    draft.root.playerCast = { hideNative = patch.hideNative }
    MarkChanged(draft)
    return YHUD:CopyValue(draft.root.playerCast)
end

function ProfileModel:SetSkyridingSettings(draft, patch)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    if type(patch) ~= "table" then return nil, "invalid-settings" end

    local current = YHUD:NormalizeSkyridingSettings(draft.root.skyriding)
    local candidate = YHUD:CopyValue(current)
    if patch.enabled ~= nil then candidate.enabled = patch.enabled end
    if patch.style ~= nil then candidate.style = patch.style end
    if type(patch.styles) == "table" then
        candidate.styles = YHUD:CopyValue(patch.styles)
    end
    candidate = YHUD:NormalizeSkyridingSettings(candidate)
    if ValuesEqual(current, candidate) then return YHUD:CopyValue(current) end

    draft.root.skyriding = candidate
    MarkChanged(draft)
    return YHUD:CopyValue(candidate)
end

function ProfileModel:SetSkyridingStyleSettings(draft, styleId, patch)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    if styleId ~= "horizon" and styleId ~= "halo" then
        return nil, "invalid-style"
    end
    if type(patch) ~= "table" then return nil, "invalid-settings" end
    local current = YHUD:NormalizeSkyridingSettings(draft.root.skyriding)
    local candidate = YHUD:CopyValue(current)
    local target = candidate.styles[styleId]
    for field, value in pairs(patch) do target[field] = value end
    candidate = YHUD:NormalizeSkyridingSettings(candidate)
    if ValuesEqual(current, candidate) then
        return YHUD:CopyValue(current.styles[styleId])
    end
    draft.root.skyriding = candidate
    MarkChanged(draft)
    return YHUD:CopyValue(candidate.styles[styleId])
end

function ProfileModel:SetGroupPlacements(draft, placements)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local groups = draft.root.groups and draft.root.groups.items or {}
    local normalized = YHUD:NormalizeGroupPlacements(placements, groups)
    draft.root.layout = type(draft.root.layout) == "table"
        and draft.root.layout or {}
    local current = type(draft.root.layout.placements) == "table"
        and draft.root.layout.placements or {}
    if ValuesEqual(current, normalized) then
        return YHUD:CopyValue(normalized), false
    end
    draft.root.layout.placements = normalized
    MarkChanged(draft)
    return YHUD:CopyValue(normalized), true
end

local function GetMonitorCategory(profile, monitor)
    if type(monitor) ~= "table" then return nil end
    if CATEGORY_LAYOUTS[monitor.officialCategory] then
        return monitor.officialCategory
    end
    local entry = profile.entries[monitor.entryKey]
    if entry and CATEGORY_LAYOUTS[entry.officialCategory] then
        return entry.officialCategory
    end
    return nil
end

local function NextId(items, prefix)
    local index = 1
    while items[prefix .. tostring(index)] do
        index = index + 1
    end
    return prefix .. tostring(index)
end

local function CheckPlacement(entry, group, view)
    local allowed = group and LAYOUT_VIEWS[group.layout]
    if not (allowed and allowed[view]) then
        return nil, "view-layout-mismatch"
    end

    local contract = entry.contract or {}
    if contract.group == "official" and group.mode ~= "official" then
        return nil, "official-group-required"
    end
    if contract.group == "fixed" then
        local fixedGroupId = entry.fixedGroupId
        if not fixedGroupId or group.id ~= fixedGroupId then
            return nil, "fixed-group-required"
        end
    end
    if view == "official" and group.mode ~= "official" then
        return nil, "official-group-required"
    end
    if contract.view == "official" and view ~= "official" then
        return nil, "official-view-required"
    end
    if YHUD.CanPlaceEntry then
        local permitted, code = YHUD:CanPlaceEntry(entry, group, view)
        if not permitted then return nil, code end
    end
    return true
end

local function ResolveDraftParts(draft, entryKey, groupId)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, nil, code end
    local profile = draft.profile
    local entry = profile.entries[entryKey]
    if not entry then return nil, nil, "entry-not-found" end
    local group = profile.groups.items[groupId]
    if not group then return nil, nil, "group-not-found" end
    return entry, group
end

function ProfileModel:IsDraft(value)
    return IsDraft(value)
end

function ProfileModel:GetDefaultView(layout)
    return DEFAULT_VIEW[layout]
end

function ProfileModel:NormalizeMonitorAppearanceForLayout(value, layout)
    local appearance = YHUD:NormalizeMonitorAppearanceOverride(value)
    if not appearance then return nil end
    if layout == "icons" then
        return YHUD:NormalizeMonitorAppearanceOverride({
            cooldownSwipeMode = appearance.cooldownSwipeMode,
        })
    end
    if layout == "bars" or layout == "rings" then
        return YHUD:NormalizeMonitorAppearanceOverride({
            fillColor = appearance.fillColor,
            trackColor = appearance.trackColor,
            stackThresholds = layout == "bars" and appearance.stackThresholds or nil,
        })
    end
    return nil
end

function ProfileModel:GetContent(profile, specKey, create)
    return YHUD:GetContent(profile, specKey, create)
end

function ProfileModel:CanPlace(profile, specKey, entryKey, groupId, view)
    if not YHUD:IsStableSpecKey(specKey) then
        view = groupId
        groupId = entryKey
        entryKey = specKey
        specKey = type(profile) == "table"
            and rawget(profile, "_yhudSpecKey") or nil
    end
    if type(profile) ~= "table" then return nil, "invalid-profile" end
    local scoped = rawget(profile, "_yhudCanonical")
        and profile
        or YHUD:GetScopedProfile(profile, specKey, false)
    if not scoped then return nil, "content-not-found" end
    local entries = scoped.entries
    local groups = scoped.groups and scoped.groups.items
    local entry = entries and entries[entryKey]
    if not entry then return nil, "entry-not-found" end
    local group = groups and groups[groupId]
    if not group then return nil, "group-not-found" end
    if group.layout == "resource" then
        return nil, "resource-preset-only"
    end
    view = view or DEFAULT_VIEW[group.layout]
    return CheckPlacement(entry, group, view)
end

function ProfileModel:BeginDraft(profile, options)
    options = type(options) == "table" and options or {}
    local specKey = options.specKey
        or (type(profile) == "table" and rawget(profile, "_yhudSpecKey"))
        or YHUD:GetCurrentSpecKey()
    if not YHUD:IsStableSpecKey(specKey) then
        return nil, "invalid-spec-key"
    end
    if type(profile) == "table" and rawget(profile, "_yhudCanonical") then
        local persisted, code = YHUD:PersistScopedProfile(profile)
        if not persisted then return nil, code end
        profile = rawget(persisted, "_yhudCanonical")
    end
    local canonical = YHUD:GetCanonicalProfile(profile)
    local ownedRoot = options.ownedRoot == true
    if not ownedRoot then canonical = YHUD:CopyValue(canonical) end
    if rawget(canonical, "_yhudSpecDocumentProjection") ~= true then
        canonical = YHUD:NormalizeProfile(canonical, specKey)
    end
    local runtimeSpecKey
    if options.runtimeSpecAvailable == false then
        runtimeSpecKey = nil
    else
        runtimeSpecKey = options.runtimeSpecKey
            or YHUD:GetCurrentSpecKey() or specKey
    end
    local scoped, code = YHUD:GetScopedProfile(
        canonical,
        specKey,
        specKey == runtimeSpecKey and true or "virtual"
    )
    if not scoped then return nil, code end
    return {
        marker = DRAFT_MARKER,
        root = canonical,
        profile = scoped,
        specKey = specKey,
        viewSpecKey = specKey,
        runtimeSpecKey = runtimeSpecKey,
        changed = false,
        revision = 0,
        closed = false,
        combat = options.combat == true,
        dirtyGroups = {},
        dirtySpecs = {},
        dirtyGroupCount = 0,
        sourceRebuilds = 0,
        writeBackCalls = 0,
        ownedRoot = ownedRoot,
    }
end

function ProfileModel:SwitchDraftSpec(draft, specKey)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    if not YHUD:IsStableSpecKey(specKey) then
        return nil, "invalid-spec-key"
    end
    if draft.viewSpecKey == specKey then return draft.profile end

    local scoped
    scoped, code = PersistDraftScope(draft)
    if not scoped then return nil, code end
    local nextProfile
    nextProfile, code = YHUD:GetScopedProfile(
        draft.root,
        specKey,
        specKey == draft.runtimeSpecKey and true or "virtual"
    )
    if not nextProfile then return nil, code end
    draft.profile = nextProfile
    draft.viewSpecKey = specKey
    draft.specKey = specKey
    return nextProfile
end

local function GetMutableMonitor(draft, monitorId)
    local monitor = draft.profile and draft.profile.monitors
        and draft.profile.monitors[monitorId] or nil
    if not monitor then return nil, nil, "monitor-not-found" end
    local entry = draft.profile.entries
        and draft.profile.entries[monitor.entryKey] or nil
    if draft.viewSpecKey ~= draft.runtimeSpecKey
        and entry and entry.origin == "official-cdm" then
        return nil, entry, "native-read-only"
    end
    return monitor, entry
end

local function SetDefaultPresetTombstone(draft, entry, deleted)
    if not (YHUD.IsDefaultSlotPresetEntry
        and YHUD:IsDefaultSlotPresetEntry(entry)) then
        return false
    end
    local specKey = draft.viewSpecKey or draft.specKey
    local root = draft.root
    root.defaultPresetTombstonesBySpec =
        type(root.defaultPresetTombstonesBySpec) == "table"
            and root.defaultPresetTombstonesBySpec or {}
    local specTombstones = type(
        root.defaultPresetTombstonesBySpec[specKey]
    ) == "table" and root.defaultPresetTombstonesBySpec[specKey] or {}
    root.defaultPresetTombstonesBySpec[specKey] = specTombstones
    local presetKey = entry.presetKey or entry.entryKey
    specTombstones[presetKey] = deleted == true and true or nil
    if next(specTombstones) == nil then
        root.defaultPresetTombstonesBySpec[specKey] = nil
    end
    if deleted == true and type(root.defaultPresetOverridesBySpec) == "table"
        and type(root.defaultPresetOverridesBySpec[specKey]) == "table" then
        root.defaultPresetOverridesBySpec[specKey][presetKey] = nil
        if next(root.defaultPresetOverridesBySpec[specKey]) == nil then
            root.defaultPresetOverridesBySpec[specKey] = nil
        end
    end
    return true
end

function ProfileModel:GetMonitorAccess(draft, monitorId)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local monitor, entry
    monitor, entry, code = GetMutableMonitor(draft, monitorId)
    if not monitor then return false, code, entry end
    return true, nil, monitor, entry
end

local function BuildDraftSummary(draft)
    return {
        changed = draft.changed == true,
        revision = draft.revision or 0,
        combatDraft = draft.combat == true,
        dirtyGroupCount = draft.dirtyGroupCount,
        dirtySpecs = YHUD:CopyValue(draft.dirtySpecs),
        sourceRebuilds = draft.sourceRebuilds,
        writeBackCalls = draft.writeBackCalls,
        viewSpecKey = draft.viewSpecKey,
        runtimeSpecKey = draft.runtimeSpecKey,
    }
end

local function ValidateDraftStorageBudget(draft)
    local budget = YHUD.StorageBudget
    if not (budget and budget.Evaluate) then return true end
    local report, code = budget:Evaluate(draft.root)
    if not report then return nil, code end
    draft.storageBudgetReport = report
    if report.hardLimitExceeded then
        return nil, "capacity-exceeded", report
    end
    return true, nil, report
end

function ProfileModel:PrepareDraft(draft)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local scoped
    scoped, code = PersistDraftScope(draft)
    if not scoped then return nil, code end
    draft.profile = scoped
    draft.root = rawget(scoped, "_yhudCanonical") or draft.root
    local valid
    valid, code = self:ValidateCanonical(draft.root)
    if not valid then return nil, code end
    local result = draft.ownedRoot == true
        and draft.root or YHUD:CopyValue(draft.root)
    return result, BuildDraftSummary(draft)
end

function ProfileModel:CloseDraft(draft)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    draft.closed = true
    return true
end

function ProfileModel:CancelDraft(draft)
    return self:CloseDraft(draft)
end

function ProfileModel:AdoptDraft(target, staged)
    local open, code = EnsureOpenDraft(target)
    if not open then return nil, code end
    open, code = EnsureOpenDraft(staged)
    if not open then return nil, code end
    local scoped
    scoped, code = PersistDraftScope(staged)
    if not scoped then return nil, code end
    staged.profile = scoped
    staged.root = rawget(scoped, "_yhudCanonical") or staged.root
    local valid
    valid, code = self:ValidateCanonical(staged.root)
    if not valid then return nil, code end

    target.root = YHUD:CopyValue(staged.root)
    target.profile = YHUD:GetScopedProfile(
        target.root,
        target.viewSpecKey or target.specKey,
        (target.viewSpecKey or target.specKey) == target.runtimeSpecKey
            and true or "virtual"
    )
    if staged.changed then MarkChanged(target) end
    for specKey in pairs(staged.dirtySpecs or {}) do
        target.dirtySpecs[specKey] = true
    end
    for groupId in pairs(staged.dirtyGroups) do
        if not target.dirtyGroups[groupId] then
            target.dirtyGroups[groupId] = true
            target.dirtyGroupCount = target.dirtyGroupCount + 1
        end
    end
    target.sourceRebuilds =
        target.sourceRebuilds + (staged.sourceRebuilds or 0)
    target.writeBackCalls =
        target.writeBackCalls + (staged.writeBackCalls or 0)
    return true
end

function ProfileModel:AddEntry(draft, entryKey, definition, replace)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    if not IsStableId(entryKey) or type(definition) ~= "table" then
        return nil, "invalid-entry"
    end
    if draft.profile.entries[entryKey] and replace ~= true then
        return nil, "entry-exists"
    end

    local entry = YHUD:CopyValue(definition)
    entry.entryKey = entryKey
    YHUD:RepairConsumablePresetReplication(entry, entryKey)
    YHUD:RepairAmmoPresetReplication(entry)
    entry.semantic = YHUD:GetEntrySemantic(entry)
    local semanticIdentity = YHUD:GetEntrySemanticIdentity(entry, entryKey)
    if not semanticIdentity then return nil, "invalid-semantic-identity" end
    for existingKey, existingEntry in pairs(draft.profile.entries) do
        if existingKey ~= entryKey
            and YHUD:GetEntrySemanticIdentity(existingEntry, existingKey)
                == semanticIdentity then
            return nil, "semantic-identity-exists"
        end
    end
    entry.contentScope = YHUD.CONTENT_SCOPE_SPEC
    entry.applicability = nil
    entry.contract = type(entry.contract) == "table" and entry.contract or {}
    local nativeOfficial = entry.origin == "official-cdm"
        and (entry.contract.capability == "native-enhanced"
            or entry.contract.view == "native")
    if not IsStableId(entry.sourceKey) and not nativeOfficial then
        return nil, "invalid-source-key"
    end
    draft.profile.entries[entryKey] = entry
    draft.profile._yhudScopeByEntry[entryKey] = YHUD.CONTENT_SCOPE_SPEC
    MarkSpecChanged(draft)
    return YHUD:CopyValue(entry)
end

function ProfileModel:CreateGroup(draft, definition)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local persisted
    persisted, code = YHUD:PersistScopedProfile(draft.profile)
    if not persisted then return nil, code end
    draft.profile = persisted
    draft.root = rawget(persisted, "_yhudCanonical") or draft.root
    definition = type(definition) == "table" and definition or {}
    local profile = draft.profile
    local layout = definition.layout
    if not LAYOUT_VIEWS[layout] then return nil, "invalid-layout" end
    local contentPolicy = definition.contentPolicy
    if contentPolicy ~= "cooldown-primary"
        and contentPolicy ~= "buff-only"
        and contentPolicy ~= "resource-only"
        and contentPolicy ~= "cast-only" then
        return nil, "invalid-content-policy"
    end
    if contentPolicy == "cooldown-primary" and layout ~= "icons" then
        return nil, "content-layout-mismatch"
    end
    if contentPolicy == "buff-only"
        and layout ~= "icons"
        and layout ~= "bars"
        and layout ~= "rings" then
        return nil, "content-layout-mismatch"
    end

    if (layout == "resource") ~= (contentPolicy == "resource-only" or contentPolicy == "cast-only") then
        return nil, "content-layout-mismatch"
    end

    local groupId = definition.id
    if groupId == nil then
        groupId = NextId(profile.groups.items, "group:user:")
    end
    if not IsStableId(groupId) then return nil, "invalid-group-id" end
    if profile.groups.items[groupId] then return nil, "group-exists" end

    local group = {
        id = groupId,
        name = type(definition.name) == "string" and definition.name
            or YHUD:T("designer.new_group_title", "新分组"),
        kind = "user",
        mode = "free",
        layout = layout,
        layoutMode = "auto",
        displayLayer = 5,
        contentPolicy = contentPolicy,
        enabled = definition.enabled ~= false,
        showUnavailablePreview =
            definition.showUnavailablePreview == true,
        showTooltip = definition.showTooltip ~= false,
        fixedName = false,
        fixedDelete = false,
        singleton = false,
        officialCategories = {},
    }
    YHUD:NormalizeGroupContentPolicy(group)
    draft.root.groups.items[groupId] = group
    if layout == "resource" then
        draft.root.resources.byGroup[groupId] = {
            selectionDefault = "none", bySpec = {}, orderBySpec = {},
            formOverrides = {}, settingsByResource = {},
        }
    end
    for _, content in pairs(draft.root.contentBySpec or {}) do
        content.groupMembers = type(content.groupMembers) == "table"
            and content.groupMembers or {}
        content.groupMembers[groupId] = {}
    end
    draft.profile = YHUD:GetScopedProfile(
        draft.root,
        draft.specKey,
        draft.specKey == draft.runtimeSpecKey and true or "virtual"
    )
    profile = draft.profile
    group = profile.groups.items[groupId]
    profile.groups.order[#profile.groups.order + 1] = groupId
    if layout == "icons" then
        profile.layout = type(profile.layout) == "table"
            and profile.layout or {}
        profile.layout.groups = type(profile.layout.groups) == "table"
            and profile.layout.groups or {}
        profile.layout.groups[groupId] =
            YHUD:GetIconGroupLayout(profile, groupId)
        profile.style = type(profile.style) == "table"
            and profile.style or {}
        profile.style.groups = type(profile.style.groups) == "table"
            and profile.style.groups or {}
        profile.style.groups[groupId] =
            YHUD:GetIconGroupStyle(profile, groupId)
    elseif layout == "resource" then
        profile.layout.groups[groupId] = YHUD:GetResourceGroupLayout(profile, groupId)
        profile.style.groups[groupId] = YHUD:GetResourceGroupStyle(profile, groupId)
        if contentPolicy == "cast-only" then
            profile.layout.groups[groupId].width = 300
            profile.layout.groups[groupId].widthMode = "fixed"
            profile.layout.groups[groupId].height = 24
        end
    elseif layout == "bars" or layout == "rings" then
        profile.layout = type(profile.layout) == "table"
            and profile.layout or {}
        profile.layout.groups = type(profile.layout.groups) == "table"
            and profile.layout.groups or {}
        profile.layout.groups[groupId] =
            YHUD:GetDurationGroupLayout(profile, groupId, layout)
        if layout == "rings" then
            profile.layout.groups[groupId].direction = "outward"
        end
        profile.style = type(profile.style) == "table"
            and profile.style or {}
        profile.style.groups = type(profile.style.groups) == "table"
            and profile.style.groups or {}
        profile.style.groups[groupId] =
            YHUD:GetDurationGroupStyle(profile, groupId)
    end
    NormalizeGroupOrders(profile)
    MarkDirty(draft, groupId)
    return YHUD:CopyValue(draft.root.groups.items[groupId])
end

function ProfileModel:RenameGroup(draft, groupId, name)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local group = draft.profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.fixedName then return nil, "fixed-name" end
    if type(name) ~= "string" or name:match("^%s*$") or #name > 144 then
        return nil, "invalid-name"
    end
    group.nameKey = nil
    group.name = name
    MarkDirty(draft, groupId)
    return true
end

function ProfileModel:SetGroupEnabled(draft, groupId, enabled)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local group = draft.profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    enabled = enabled == true
    if group.fixedEnabled and not enabled then return nil, "fixed-enabled" end
    if group.enabled == enabled then return true end
    group.enabled = enabled
    MarkDirty(draft, groupId)
    return true
end

function ProfileModel:SetGroupLayoutMode(draft, groupId, layoutMode)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local group = draft.profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if layoutMode ~= "auto" and layoutMode ~= "fixed" then
        return nil, "invalid-layout-mode"
    end
    if group.layoutMode == layoutMode then return true end
    group.layoutMode = layoutMode
    NormalizeSpecialOverflowOrder(draft.profile, group)
    MarkDirty(draft, groupId)
    return true
end

function ProfileModel:SetGroupDisplayLayer(draft, groupId, displayLayer)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local group = draft.profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    displayLayer = tonumber(displayLayer)
    if not displayLayer or displayLayer % 1 ~= 0
        or displayLayer < 1 or displayLayer > 10 then
        return nil, "invalid-display-layer"
    end
    if group.displayLayer == displayLayer then return true end
    group.displayLayer = displayLayer
    MarkDirty(draft, groupId)
    return true
end

function ProfileModel:SetGroupUnavailablePreview(draft, groupId, enabled)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local group = draft.profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.layout == "resource" then
        return nil, "unsupported-group-layout"
    end
    enabled = enabled == true
    if group.showUnavailablePreview == enabled then return true end
    group.showUnavailablePreview = enabled
    MarkDirty(draft, groupId)
    return true
end

function ProfileModel:SetGroupTooltip(draft, groupId, enabled)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local group = draft.profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.layout == "resource" then
        return nil, "unsupported-group-layout"
    end
    enabled = enabled == true
    if group.showTooltip == enabled then return true end
    group.showTooltip = enabled
    MarkDirty(draft, groupId)
    return true
end

local function SameVisibilityRule(left, right, groupId)
    left = YHUD:NormalizeVisibilityRule(left, groupId)
    right = YHUD:NormalizeVisibilityRule(right, groupId)
    if left == nil or right == nil then return left == right end
    if left.version == 2 and right.version == 2 then
        return YUI.Visibility:SameBranches(left, right)
    end
    local leftHide = left.hide or {}
    local rightHide = right.hide or {}
    return left.combat == right.combat
        and left.mounted == right.mounted
        and leftHide.noTarget == rightHide.noTarget
        and leftHide.housing == rightHide.housing
        and leftHide.skyriding == rightHide.skyriding
end

function ProfileModel:SetGroupVisibility(draft, groupId, rule)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local group = draft.profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if type(rule) == "table" and rule.version ~= nil and YUI.Visibility then
        local valid, code = YUI.Visibility:ValidateBranches(rule, { hover = false })
        if not valid then return nil, code end
    end
    local normalized = YHUD:NormalizeVisibilityRule(rule, groupId)
    if SameVisibilityRule(group.visibility, normalized, groupId) then
        return true
    end
    group.visibility = normalized
    MarkDirty(draft, groupId)
    return true
end

function ProfileModel:SetGroupIconLayout(draft, groupId, patch)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local profile = draft.profile
    local group = profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.layout ~= "icons" then return nil, "icon-group-required" end
    if type(patch) ~= "table" then return nil, "invalid-layout" end

    local nextLayout = YHUD:GetIconGroupLayout(profile, groupId)
    for key, value in pairs(patch) do
        if key ~= "iconSize" and key ~= "columnSpacing"
            and key ~= "rowSpacing"
            and key ~= "maxPerLine" and key ~= "alignment"
            and key ~= "wrapDirection" and key ~= "rowDirection" then
            return nil, "invalid-layout-field"
        end
        nextLayout[key] = value
    end
    nextLayout = YHUD:NormalizeIconGroupLayout(nextLayout)

    profile.layout = type(profile.layout) == "table"
        and profile.layout or {}
    profile.layout.groups = type(profile.layout.groups) == "table"
        and profile.layout.groups or {}
    profile.layout.groups[groupId] = nextLayout
    if groupId == YHUD.GROUP_IDS.TRINKETS then
        profile.layout.trinkets = YHUD:CopyValue(nextLayout)
    end
    NormalizeSpecialOverflowOrder(profile, group)
    MarkDirty(draft, groupId)
    return YHUD:CopyValue(nextLayout)
end

function ProfileModel:SetGroupIconStyle(draft, groupId, patch)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local profile = draft.profile
    local group = profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.layout ~= "icons" then return nil, "icon-group-required" end
    if type(patch) ~= "table" then return nil, "invalid-style" end

    local nextStyle = YHUD:GetIconGroupStyle(profile, groupId)
    for key, value in pairs(patch) do
        if key ~= "iconShape" and key ~= "iconBorder"
            and key ~= "iconZoom"
            and key ~= "iconBorderColor"
            and key ~= "iconBackgroundColor"
            and key ~= "iconShadow"
            and key ~= "iconShadowColor"
            and key ~= "cooldownSwipeColor"
            and key ~= "cooldownSwipe"
            and key ~= "cooldownGCD"
            and key ~= "cooldownBling"
            and key ~= "cooldownText"
            and key ~= "cooldownTextFont"
            and key ~= "cooldownTextSize"
            and key ~= "cooldownTextOutline"
            and key ~= "cooldownTextPosition"
            and key ~= "cooldownTextOffsetX"
            and key ~= "cooldownTextOffsetY"
            and key ~= "cooldownTextColor"
            and key ~= "keybindTextMode"
            and key ~= "keybindTextFont"
            and key ~= "keybindTextSize"
            and key ~= "keybindTextOutline"
            and key ~= "keybindTextPosition"
            and key ~= "keybindTextOffsetX"
            and key ~= "keybindTextOffsetY"
            and key ~= "keybindTextColor"
            and key ~= "keybindTextOverrides"
            and key ~= "countText"
            and key ~= "countTextFont"
            and key ~= "countTextSize"
            and key ~= "countTextOutline"
            and key ~= "countTextPosition"
            and key ~= "countTextOffsetX"
            and key ~= "countTextOffsetY"
            and key ~= "countTextColor" then
            return nil, "invalid-style-field"
        end
        nextStyle[key] = YHUD:CopyValue(value)
    end
    nextStyle = YHUD:NormalizeIconGroupStyle(nextStyle)

    profile.style = type(profile.style) == "table"
        and profile.style or {}
    profile.style.groups = type(profile.style.groups) == "table"
        and profile.style.groups or {}
    profile.style.groups[groupId] = nextStyle
    MarkDirty(draft, groupId)
    return YHUD:CopyValue(nextStyle)
end

function ProfileModel:SetGroupDurationLayout(draft, groupId, patch)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local profile = draft.profile
    local group = profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.layout ~= "bars" and group.layout ~= "rings" then
        return nil, "duration-group-required"
    end
    if type(patch) ~= "table" then return nil, "invalid-layout" end

    local allowed = group.layout == "rings" and {
        diameter = true,
        ringStep = true,
        columnSpacing = true,
        rowSpacing = true,
        maxPerLine = true,
        alignment = true,
        wrapDirection = true,
        direction = true,
    } or {
        width = true,
        height = true,
        columnSpacing = true,
        rowSpacing = true,
        maxPerLine = true,
        alignment = true,
        wrapDirection = true,
        orientation = true,
        fillDirection = true,
        iconPosition = true,
        iconGap = true,
    }
    local nextLayout =
        YHUD:GetDurationGroupLayout(profile, groupId, group.layout)
    for key, value in pairs(patch) do
        if not allowed[key] then return nil, "invalid-layout-field" end
        nextLayout[key] = value
    end
    nextLayout = YHUD:NormalizeDurationGroupLayout(
        nextLayout,
        group.layout
    )

    profile.layout.groups[groupId] = nextLayout
    MarkDirty(draft, groupId)
    return YHUD:CopyValue(nextLayout)
end

function ProfileModel:SetGroupDurationOrientation(draft, groupId, orientation)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local profile = draft.profile
    local group = profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.layout ~= "bars" then return nil, "bar-group-required" end
    local fillDirection
    if orientation == "horizontal-forward" or orientation == "horizontal-reverse"
        or orientation == "vertical-forward" or orientation == "vertical-reverse" then
        orientation, fillDirection = orientation:match("^(%a+)%-(%a+)$")
    end
    if orientation ~= "horizontal" and orientation ~= "vertical" then
        return nil, "invalid-orientation"
    end

    local nextLayout = YHUD:GetDurationGroupLayout(profile, groupId, "bars")
    if fillDirection and nextLayout.orientation == orientation then
        local layout = self:SetGroupDurationLayout(draft, groupId, {
            fillDirection = fillDirection,
        })
        return { layout = layout, style = YHUD:GetDurationGroupStyle(profile, groupId) }
    end
    nextLayout.fillDirection = fillDirection or nextLayout.fillDirection
    nextLayout.orientation = orientation
    nextLayout.iconPosition = orientation == "vertical" and "bottom" or "left"
    nextLayout = YHUD:NormalizeDurationGroupLayout(nextLayout, "bars")

    local nextStyle = YHUD:GetDurationGroupStyle(profile, groupId)
    if orientation == "vertical" then
        nextStyle.timeTextAnchor = "bar-bottom"
        nextStyle.nameTextAnchor = "bar-center"
        nextStyle.countTextAnchor = "bar-outside-top"
    else
        nextStyle.timeTextAnchor = "bar-right"
        nextStyle.nameTextAnchor = "bar-center"
        nextStyle.countTextAnchor = "icon-bottom-right"
    end
    nextStyle = YHUD:NormalizeDurationGroupStyle(nextStyle)

    profile.layout.groups[groupId] = nextLayout
    profile.style.groups[groupId] = nextStyle
    MarkDirty(draft, groupId)
    return {
        layout = YHUD:CopyValue(nextLayout),
        style = YHUD:CopyValue(nextStyle),
    }
end

function ProfileModel:SetGroupDurationStyle(draft, groupId, patch)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local profile = draft.profile
    local group = profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.layout ~= "bars" and group.layout ~= "rings" then
        return nil, "duration-group-required"
    end
    if type(patch) ~= "table" then return nil, "invalid-style" end

    local allowed = {
        smoothProgress = true,
        iconShape = true,
        iconBorder = true,
        iconZoom = true,
        iconBorderColor = true,
        iconBackgroundColor = true,
        cooldownSwipeColor = true,
        cooldownText = true,
        cooldownTextFont = true,
        cooldownTextSize = true,
        cooldownTextOutline = true,
        cooldownTextPosition = true,
        cooldownTextOffsetX = true,
        cooldownTextOffsetY = true,
        cooldownTextColor = true,
        countText = true,
        countTextFont = true,
        countTextSize = true,
        countTextOutline = true,
        countTextPosition = true,
        countTextAnchor = true,
        countTextOffsetX = true,
        countTextOffsetY = true,
        countTextColor = true,
        nameText = true,
        nameTextFormat = true,
        nameTextFont = true,
        nameTextSize = true,
        nameTextOutline = true,
        nameTextPosition = true,
        nameTextAnchor = true,
        nameTextOffsetX = true,
        nameTextOffsetY = true,
        nameTextColor = true,
        fillColor = true,
        runeColors = true,
        fillTexture = true,
        trackColor = true,
        borderColor = true,
        showIcon = true,
        timeText = true,
        timeTextFont = true,
        timeTextSize = true,
        timeTextOutline = true,
        timeTextPosition = true,
        timeTextAnchor = true,
        timeTextOffsetX = true,
        timeTextOffsetY = true,
        timeTextColor = true,
        ringThickness = true,
        ringDirection = true,
        ringStart = true,
        ringTrackColor = true,
        ringBorderColor = true,
    }
    local nextStyle = YHUD:GetDurationGroupStyle(profile, groupId)
    for key, value in pairs(patch) do
        if not allowed[key] then return nil, "invalid-style-field" end
        nextStyle[key] = YHUD:CopyValue(value)
    end
    nextStyle = YHUD:NormalizeDurationGroupStyle(nextStyle)

    profile.style.groups[groupId] = nextStyle
    MarkDirty(draft, groupId)
    return YHUD:CopyValue(nextStyle)
end

function ProfileModel:SetGroupResourceLayout(draft, groupId, patch)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local profile = draft.profile
    local group = profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.layout ~= "resource" then
        return nil, "resource-group-required"
    end
    if type(patch) ~= "table" then return nil, "invalid-layout" end

    local allowed = {
        widthMode = true,
        width = true,
        minWidth = true,
        height = true,
        spacing = true,
        alignment = true,
        direction = true,
        orientation = true,
        fillDirection = true,
        handPairMode = YUI.IsForever == true,
        mainHandFillDirection = YUI.IsForever == true,
        offHandFillDirection = YUI.IsForever == true,
    }
    local nextLayout = YHUD:GetResourceGroupLayout(profile, groupId)
    for key, value in pairs(patch) do
        if not allowed[key] then return nil, "invalid-layout-field" end
        nextLayout[key] = value
    end
    nextLayout = YHUD:NormalizeResourceGroupLayout(nextLayout)
    profile.layout.groups[groupId] = nextLayout
    MarkDirty(draft, groupId)
    return YHUD:CopyValue(nextLayout)
end

function ProfileModel:SetGroupResourceStyle(draft, groupId, patch)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local profile = draft.profile
    local group = profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.layout ~= "resource" then
        return nil, "resource-group-required"
    end
    if type(patch) ~= "table" then return nil, "invalid-style" end

    local allowed = {
        smoothProgress = true,
        border = true,
        borderColor = true,
        fillTexture = true,
        fillColorMode = true,
        fillColor = true,
        textFont = true,
        textSize = true,
        textOutline = true,
        textColor = true,
        backgroundColor = true,
    }
    local nextStyle = YHUD:GetResourceGroupStyle(profile, groupId)
    for key, value in pairs(patch) do
        if not allowed[key] then return nil, "invalid-style-field" end
        nextStyle[key] = YHUD:CopyValue(value)
    end
    nextStyle = YHUD:NormalizeResourceGroupStyle(nextStyle)
    profile.style.groups[groupId] = nextStyle
    MarkDirty(draft, groupId)
    return YHUD:CopyValue(nextStyle)
end

local function GetKnownResourceSetting(profile, resourceId, groupId)
    local Catalog = YHUD.ResourceCatalog
    if not (Catalog and Catalog.GetDefinition
        and Catalog:GetDefinition(resourceId)) then
        return nil, "unknown-resource"
    end
    groupId = groupId or YHUD.GROUP_IDS.RESOURCES
    local group = profile.groups.items[groupId]
    if not group or group.layout ~= "resource" then return nil, "resource-group-required" end
    return YHUD:GetResourceSetting(profile, resourceId, groupId)
end

function ProfileModel:SetResourceSetting(draft, resourceId, patch, groupId)
    groupId = groupId or YHUD.GROUP_IDS.RESOURCES
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    if type(patch) ~= "table" then return nil, "invalid-resource-setting" end
    local setting
    setting, code = GetKnownResourceSetting(draft.profile, resourceId, groupId)
    if not setting then return nil, code end
    local allowed = {
        visibilityMode = true,
        valueText = true,
        valueFormat = true,
        abbreviateValues = true,
        text2 = true,
        textPosition = true,
        textOffsetX = true,
        textOffsetY = true,
        heightOverride = true,
        fillColor = true,
        runeColors = true,
        runeCooldownTextSize = true,
        runeCooldownTextMode = true,
        displayMode = true,
        inverseFill = true,
        segmentSpacing = true,
        dividerThickness = true,
        dividerColor = true,
        thresholdColorEnabled = true,
        thresholdMarkerEnabled = true,
        thresholds = true,
        thresholdMode = true,
        fillCeilingPercent = true,
        thresholdValues = true,
        cast = true,
        thresholdMarkerColor = true,
        thresholdMarkerThickness = true,
    }
    if patch.thresholdMode and patch.thresholdMode ~= setting.thresholdMode and not patch.thresholds then
        local saved = setting.thresholdValues and setting.thresholdValues[patch.thresholdMode]
        if saved then
            setting.thresholds.low.value = saved.low
            setting.thresholds.high.value = saved.high
        end
    end
    for key, value in pairs(patch) do
        if not allowed[key] then return nil, "invalid-resource-setting-field" end
        setting[key] = YHUD:CopyValue(value)
    end
    setting = YHUD:NormalizeResourceSetting(setting, resourceId)
    YHUD:GetResourceConfig(draft.profile, groupId).settingsByResource[resourceId] = setting
    MarkDirty(draft, groupId)
    return YHUD:CopyValue(setting)
end

function ProfileModel:SetResourceTextOverride(draft, resourceId, enabled, patch, groupId)
    groupId = groupId or YHUD.GROUP_IDS.RESOURCES
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local setting
    setting, code = GetKnownResourceSetting(draft.profile, resourceId, groupId)
    if not setting then return nil, code end
    if enabled ~= true then
        setting.textOverride = nil
    else
        local global = YHUD:GetResourceGroupStyle(
            draft.profile,
            groupId
        )
        local override = setting.textOverride or {
            textFont = global.textFont,
            textSize = global.textSize,
            textOutline = global.textOutline,
            textColor = YHUD:CopyValue(global.textColor),
        }
        if type(patch) == "table" then
            local allowed = {
                textFont = true,
                textSize = true,
                textOutline = true,
                textColor = true,
            }
            for key, value in pairs(patch) do
                if not allowed[key] then return nil, "invalid-text-override-field" end
                override[key] = YHUD:CopyValue(value)
            end
        end
        setting.textOverride = override
    end
    setting = YHUD:NormalizeResourceSetting(setting, resourceId)
    YHUD:GetResourceConfig(draft.profile, groupId).settingsByResource[resourceId] = setting
    MarkDirty(draft, groupId)
    return YHUD:CopyValue(setting)
end

function ProfileModel:SetResourceAppearanceOverride(
    draft,
    resourceId,
    enabled,
    patch,
    groupId
)
    groupId = groupId or YHUD.GROUP_IDS.RESOURCES
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local setting
    setting, code = GetKnownResourceSetting(draft.profile, resourceId, groupId)
    if not setting then return nil, code end
    if enabled ~= true then
        setting.appearanceOverride = nil
    else
        local global = YHUD:GetResourceGroupStyle(
            draft.profile,
            groupId
        )
        local override = setting.appearanceOverride or {
            border = global.border,
            borderColor = YHUD:CopyValue(global.borderColor),
            fillTexture = global.fillTexture,
            backgroundColor = YHUD:CopyValue(global.backgroundColor),
        }
        if type(patch) == "table" then
            local allowed = {
                border = true,
                borderColor = true,
                fillTexture = true,
                backgroundColor = true,
            }
            for key, value in pairs(patch) do
                if not allowed[key] then
                    return nil, "invalid-appearance-override-field"
                end
                override[key] = YHUD:CopyValue(value)
            end
        end
        setting.appearanceOverride = override
    end
    setting = YHUD:NormalizeResourceSetting(setting, resourceId)
    YHUD:GetResourceConfig(draft.profile, groupId).settingsByResource[resourceId] = setting
    MarkDirty(draft, groupId)
    return YHUD:CopyValue(setting)
end

function ProfileModel:SetResourcePresetEnabled(
    draft,
    classFile,
    specID,
    resourceId,
    enabled,
    groupId
)
    groupId = groupId or YHUD.GROUP_IDS.RESOURCES
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local group = draft.profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.layout ~= "resource" then return nil, "resource-group-required" end
    local Catalog = YHUD.ResourceCatalog
    if not (Catalog and Catalog.SetPresetEnabled) then
        return nil, "resource-catalog-unavailable"
    end
    local changed
    changed, code = Catalog:SetPresetEnabled(
        YHUD:GetResourceProfile(draft.profile, groupId),
        classFile,
        specID,
        resourceId,
        enabled
    )
    if not changed then return nil, code end
    MarkDirty(draft, groupId)
    return true
end

function ProfileModel:MoveResourcePreset(
    draft,
    classFile,
    specID,
    resourceId,
    targetIndex,
    enabledOnly,
    groupId
)
    groupId = groupId or YHUD.GROUP_IDS.RESOURCES
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local group = draft.profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.layout ~= "resource" then return nil, "resource-group-required" end
    local Catalog = YHUD.ResourceCatalog
    if not (Catalog and Catalog.MovePreset) then
        return nil, "resource-catalog-unavailable"
    end
    local order
    order, code = Catalog:MovePreset(
        YHUD:GetResourceProfile(draft.profile, groupId),
        classFile,
        specID,
        resourceId,
        targetIndex,
        enabledOnly
    )
    if not order then return nil, code end
    MarkDirty(draft, groupId)
    return YHUD:CopyValue(order)
end

function ProfileModel:SetResourceFormPresetEnabled(
    draft,
    classFile,
    specID,
    formKey,
    resourceId,
    enabled,
    groupId
)
    groupId = groupId or YHUD.GROUP_IDS.RESOURCES
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local group = draft.profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.layout ~= "resource" then return nil, "resource-group-required" end
    local Catalog = YHUD.ResourceCatalog
    if not (Catalog and Catalog.SetFormPresetEnabled) then
        return nil, "resource-catalog-unavailable"
    end
    local changed
    changed, code = Catalog:SetFormPresetEnabled(
        YHUD:GetResourceProfile(draft.profile, groupId),
        classFile,
        specID,
        formKey,
        resourceId,
        enabled
    )
    if not changed then return nil, code end
    MarkDirty(draft, groupId)
    return true
end

function ProfileModel:MoveResourceFormPreset(
    draft,
    classFile,
    specID,
    formKey,
    resourceId,
    targetIndex,
    groupId,
    enabledOnly
)
    groupId = groupId or YHUD.GROUP_IDS.RESOURCES
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local group = draft.profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.layout ~= "resource" then return nil, "resource-group-required" end
    local Catalog = YHUD.ResourceCatalog
    if not (Catalog and Catalog.MoveFormPreset) then
        return nil, "resource-catalog-unavailable"
    end
    local order
    order, code = Catalog:MoveFormPreset(
        YHUD:GetResourceProfile(draft.profile, groupId),
        classFile,
        specID,
        formKey,
        resourceId,
        targetIndex,
        enabledOnly
    )
    if not order then return nil, code end
    MarkDirty(draft, groupId)
    return YHUD:CopyValue(order)
end

function ProfileModel:ResetResourceFormOverride(
    draft,
    classFile,
    specID,
    formKey,
    groupId
)
    groupId = groupId or YHUD.GROUP_IDS.RESOURCES
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local group = draft.profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.layout ~= "resource" then return nil, "resource-group-required" end
    local Catalog = YHUD.ResourceCatalog
    if not (Catalog and Catalog.ResetFormOverride) then
        return nil, "resource-catalog-unavailable"
    end
    local reset
    reset, code = Catalog:ResetFormOverride(
        YHUD:GetResourceProfile(draft.profile, groupId),
        classFile,
        specID,
        formKey
    )
    if not reset then return nil, code end
    MarkDirty(draft, groupId)
    return true
end

function ProfileModel:DeleteGroup(draft, groupId)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local persisted
    persisted, code = YHUD:PersistScopedProfile(draft.profile)
    if not persisted then return nil, code end
    draft.profile = persisted
    draft.root = rawget(persisted, "_yhudCanonical") or draft.root
    local profile = draft.profile
    local group = profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if group.fixedDelete then return nil, "fixed-delete" end
    if group.layout == "resource" then
        local config = YHUD:GetResourceConfig(profile, groupId)
        for _, specs in pairs(config.bySpec or {}) do
            for _, selection in pairs(specs) do
                for _, enabled in pairs(selection) do
                    if enabled == true then return nil, "group-not-empty" end
                end
            end
        end
        for _, specs in pairs(config.formOverrides or {}) do
            for _, forms in pairs(specs) do
                for _, form in pairs(forms) do
                    for _, enabled in pairs(form.enabled or {}) do
                        if enabled == true then return nil, "group-not-empty" end
                    end
                end
            end
        end
    end
    local sharedMembers = draft.root.sharedContent
        and draft.root.sharedContent.groupMembers
        and draft.root.sharedContent.groupMembers[groupId]
    if type(sharedMembers) == "table"
        and (#(sharedMembers.before or {}) > 0
            or #(sharedMembers.after or {}) > 0) then
        return nil, "group-not-empty"
    end
    for _, content in pairs(draft.root.contentBySpec or {}) do
        local members = content.groupMembers
            and content.groupMembers[groupId]
        if type(members) == "table" and #members > 0 then
            return nil, "group-not-empty"
        end
    end
    local summaries = draft.root.specDocuments
        and draft.root.specDocuments.summaries or nil
    for specKey, summary in pairs(type(summaries) == "table"
        and summaries or {}) do
        if draft.root.contentBySpec[specKey] == nil
            and type(summary) == "table"
            and type(summary.groupCounts) == "table"
            and (tonumber(summary.groupCounts[groupId]) or 0) > 0 then
            return nil, "group-not-empty"
        end
    end
    local repaired, repairCode, repairDetail =
        YHUD:RepairDanglingGroupAnchors(draft.root, {
            removedGroupId = groupId,
            targetOnly = true,
        })
    if not repaired then return nil, repairCode, repairDetail end
    draft.root.resources.byGroup[groupId] = nil
    draft.root.groups.items[groupId] = nil
    if draft.root.sharedContent
        and type(draft.root.sharedContent.groupMembers) == "table" then
        draft.root.sharedContent.groupMembers[groupId] = nil
    end
    for _, content in pairs(draft.root.contentBySpec or {}) do
        if type(content.groupMembers) == "table" then
            content.groupMembers[groupId] = nil
        end
    end
    if draft.root.layout and type(draft.root.layout.groups) == "table" then
        draft.root.layout.groups[groupId] = nil
    end
    if draft.root.layout and type(draft.root.layout.placements) == "table" then
        draft.root.layout.placements[groupId] = nil
    end
    if draft.root.style and type(draft.root.style.groups) == "table" then
        draft.root.style.groups[groupId] = nil
    end
    RemoveArrayValue(draft.root.groups.order, groupId)
    draft.profile = YHUD:GetScopedProfile(
        draft.root,
        draft.specKey,
        draft.specKey == draft.runtimeSpecKey and true or "virtual"
    )
    NormalizeGroupOrders(draft.profile)
    MarkDirty(draft, groupId)
    return true
end

function ProfileModel:AddMonitor(draft, definition)
    definition = type(definition) == "table" and definition or {}
    local entry, group, code = ResolveDraftParts(
        draft,
        definition.entryKey,
        definition.groupId
    )
    if not entry then return nil, code end

    if group.layout == "resource" then
        return nil, "resource-preset-only"
    end
    local view = definition.view or DEFAULT_VIEW[group.layout]
    local placed
    placed, code = CheckPlacement(entry, group, view)
    if not placed then return nil, code end
    if definition.sourceKey and definition.sourceKey ~= entry.sourceKey then
        return nil, "source-key-mismatch"
    end

    local profile = draft.profile
    for _, existing in pairs(profile.monitors) do
        if existing.entryKey == definition.entryKey then
            return nil, "entry-already-placed"
        end
    end
    local monitorId = definition.id
        or NextId(profile.monitors, "monitor:user:")
    if not IsStableId(monitorId) then return nil, "invalid-monitor-id" end
    if profile.monitors[monitorId] then return nil, "monitor-exists" end

    local monitor = {
        id = monitorId,
        entryKey = definition.entryKey,
        sourceKey = entry.sourceKey,
        groupId = group.id,
        view = view,
        order = 0,
        enabled = definition.enabled ~= false,
        contentScope = entry.contentScope,
        origin = definition.origin
            or (entry.origin == "official-cdm" and "official-cdm" or nil),
        officialCategory = definition.officialCategory
            or entry.officialCategory,
        glow = definition.glow
            and YHUD:NormalizeMonitorGlow(definition.glow)
            or nil,
        sound = definition.sound
            and YHUD:NormalizeMonitorSound(definition.sound)
            or nil,
        nativeProcGlowOverride = type(definition.nativeProcGlowOverride)
            == "table" and YHUD:NormalizeNativeProcGlow(
                definition.nativeProcGlowOverride
            ) or nil,
        visibilityMode = YHUD:SupportsPersistentDisplay(entry)
            and definition.visibilityMode == "always"
            and "always" or "active",
        stateEffects = YHUD:NormalizeMonitorStateEffects(
            definition.stateEffects,
            entry,
            definition.skillAuraDisplayOverride
        ),
        appearanceOverride = self:NormalizeMonitorAppearanceForLayout(
            definition.appearanceOverride,
            group.layout
        ),
    }
    profile.monitors[monitorId] = monitor
    profile._yhudScopeByMonitor[monitorId] = entry.contentScope
    InsertArrayValue(group.monitors, monitorId, definition.index)
    NormalizeMonitorOrders(profile, group.id)
    NormalizeSpecialOverflowOrder(profile, group)
    if entry.origin == "official-cdm" then
        profile.suppressedOfficial[entry.entryKey] = nil
    end
    SetDefaultPresetTombstone(draft, entry, false)
    if YHUD.InitializeMixedAuraDesaturation then
        YHUD:InitializeMixedAuraDesaturation(profile, group.id)
    end
    MarkDirty(draft, group.id, true)
    return YHUD:CopyValue(monitor)
end

local function FindMonitorBySemanticIdentity(profile, identity)
    if type(identity) ~= "string" then return nil end
    for monitorId, monitor in pairs(profile.monitors or {}) do
        if YHUD:GetMonitorSemanticIdentity(profile, monitor) == identity then
            return monitorId, monitor,
                profile.entries and profile.entries[monitor.entryKey] or nil
        end
    end
    return nil
end

local function FindEntryBySemanticIdentity(profile, identity)
    if type(identity) ~= "string" then return nil end
    for entryKey, entry in pairs(profile.entries or {}) do
        if YHUD:GetEntrySemanticIdentity(entry, entryKey) == identity then
            return entryKey, entry
        end
    end
    return nil
end

local function NormalizeTargetSpecKeys(values)
    local result = {}
    local seen = {}
    for index = 1, #(values or {}) do
        local specKey = values[index]
        if YHUD:IsStableSpecKey(specKey) and not seen[specKey] then
            seen[specKey] = true
            result[#result + 1] = specKey
        end
    end
    table.sort(result)
    return result
end

local ORDER_REF_PREFIXES = {
    "official:",
    "preset:",
    "custom:",
}

local function IsOrderRef(value)
    if type(value) ~= "string" then return false end
    for index = 1, #ORDER_REF_PREFIXES do
        local prefix = ORDER_REF_PREFIXES[index]
        if value:sub(1, #prefix) == prefix and #value > #prefix then
            return true
        end
    end
    return false
end

local function GetMonitorOrderRef(profile, monitorId)
    local monitor = profile and profile.monitors
        and profile.monitors[monitorId]
    local entry = monitor and profile.entries
        and profile.entries[monitor.entryKey]
    if not (monitor and entry) then return nil end
    local identity = YHUD:GetEntrySemanticIdentity(entry, monitor.entryKey)
    if type(identity) == "string"
        and (identity:sub(1, 9) == "official:"
            or identity:sub(1, 7) == "preset:") then
        return identity
    end
    return "custom:" .. monitorId
end

local function AppendUniqueOrderRef(target, seen, ref)
    if not IsOrderRef(ref) or seen[ref] then return end
    seen[ref] = true
    target[#target + 1] = ref
end

local function RemoveOrderRef(target, seen, ref)
    if not IsOrderRef(ref) then return false end
    local removed = false
    for index = #target, 1, -1 do
        if target[index] == ref then
            table.remove(target, index)
            removed = true
        end
    end
    if removed and type(seen) == "table" then seen[ref] = nil end
    return removed
end

local function BuildTargetOrderBaseline(
    staged,
    targetProfile,
    targetSpecKey,
    groupId,
    options
)
    local supplied = type(options) == "table"
        and type(options.targetOrderRefsBySpec) == "table"
        and type(options.targetOrderRefsBySpec[targetSpecKey]) == "table"
        and options.targetOrderRefsBySpec[targetSpecKey][groupId] or nil
    local specOverrides = type(staged.root.officialOverridesBySpec) == "table"
        and staged.root.officialOverridesBySpec[targetSpecKey] or nil
    local stored = specOverrides and type(specOverrides.groups) == "table"
        and specOverrides.groups[groupId] or nil
    local source = type(supplied) == "table" and supplied or stored
    local refs = {}
    local seen = {}
    for index = 1, #(source or {}) do
        AppendUniqueOrderRef(refs, seen, source[index])
    end
    local group = targetProfile.groups.items[groupId]
    for index = 1, #(group and group.monitors or {}) do
        AppendUniqueOrderRef(
            refs,
            seen,
            GetMonitorOrderRef(targetProfile, group.monitors[index])
        )
    end
    return refs, seen
end

local function StoreTargetOrderRefs(
    staged,
    targetSpecKey,
    groupId,
    refs
)
    local root = staged.root
    root.officialOverridesBySpec =
        type(root.officialOverridesBySpec) == "table"
            and root.officialOverridesBySpec or {}
    local specOverrides = type(root.officialOverridesBySpec[targetSpecKey])
        == "table" and root.officialOverridesBySpec[targetSpecKey] or {}
    root.officialOverridesBySpec[targetSpecKey] = specOverrides
    specOverrides.groups = type(specOverrides.groups) == "table"
        and specOverrides.groups or {}
    specOverrides.groups[groupId] = YHUD:CopyValue(refs)
end

function ProfileModel:CopyMonitorToSpecializations(
    draft,
    monitorId,
    targetSpecKeys,
    options
)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local sourceSpecKey = draft.viewSpecKey or draft.specKey
    local sourceMonitor = draft.profile.monitors[monitorId]
    local sourceEntry = sourceMonitor
        and draft.profile.entries[sourceMonitor.entryKey] or nil
    if not sourceEntry then return nil, "monitor-not-found" end
    local allowed
    allowed, code = YHUD:CanCrossSpecOperate(
        "copy",
        sourceEntry,
        draft.runtimeSpecKey,
        sourceSpecKey
    )
    if not allowed then return nil, code end

    local identity = YHUD:GetEntrySemanticIdentity(
        sourceEntry,
        sourceMonitor.entryKey
    )
    if not identity then return nil, "invalid-semantic-identity" end
    local sourceEntryCopy = YHUD:CopyValue(sourceEntry)
    local sourceMonitorCopy = YHUD:CopyValue(sourceMonitor)
    -- Sound rules have their own library; graphical copies do not create reminders.
    sourceMonitorCopy.sound = nil
    local staged
    staged, code = self:BeginDraft(draft.profile, {
        specKey = sourceSpecKey,
        runtimeSpecKey = draft.runtimeSpecKey,
        combat = draft.combat == true,
    })
    if not staged then return nil, code end

    local report = {
        operation = "copy",
        sourceSpecKey = sourceSpecKey,
        targets = {},
        copied = 0,
        overwritten = 0,
        skipped = 0,
    }
    local targets = NormalizeTargetSpecKeys(targetSpecKeys)
    for index = 1, #targets do
        local targetSpecKey = targets[index]
        local row = { specKey = targetSpecKey }
        report.targets[#report.targets + 1] = row
        if targetSpecKey == sourceSpecKey then
            row.status = "source"
            report.skipped = report.skipped + 1
        else
            local materializable, materialization =
                YHUD:CanMaterializePresetForSpec(
                    sourceEntryCopy,
                    targetSpecKey
                )
            if not materializable then
                row.status = materialization == "preset-not-applicable"
                    and "not-applicable" or "policy-denied"
                row.code = materialization
                report.skipped = report.skipped + 1
            else
                local targetProfile
                targetProfile, code = self:SwitchDraftSpec(staged, targetSpecKey)
                if not targetProfile then return nil, code, report end
                if targetProfile.groups.items[sourceMonitorCopy.groupId] == nil then
                    return nil, "group-not-found", report
                else
                    local targetOrderRefs, seenTargetOrderRefs =
                        BuildTargetOrderBaseline(
                            staged,
                            targetProfile,
                            targetSpecKey,
                            sourceMonitorCopy.groupId,
                            options
                        )
                    local targetMonitorId, targetMonitor =
                        FindMonitorBySemanticIdentity(targetProfile, identity)
                    if targetMonitor then
                        local targetEntryKey = targetMonitor.entryKey
                        local previousGroupId = targetMonitor.groupId
                        local previousGroup =
                            targetProfile.groups.items[previousGroupId]
                        if not previousGroup then
                            return nil, "group-not-found", report
                        end
                        local targetOrderRef = GetMonitorOrderRef(
                            targetProfile,
                            targetMonitorId
                        )
                        local previousOrderRefs, seenPreviousOrderRefs
                        if previousGroupId ~= sourceMonitorCopy.groupId then
                            previousOrderRefs, seenPreviousOrderRefs =
                                BuildTargetOrderBaseline(
                                    staged,
                                    targetProfile,
                                    targetSpecKey,
                                    previousGroupId,
                                    options
                                )
                        end
                        RemoveArrayValue(previousGroup.monitors, targetMonitorId)
                        NormalizeMonitorOrders(targetProfile, previousGroupId)
                        NormalizeSpecialOverflowOrder(targetProfile, previousGroup)
                        MarkDirty(staged, previousGroupId, true)
                        if previousOrderRefs then
                            RemoveOrderRef(
                                previousOrderRefs,
                                seenPreviousOrderRefs,
                                targetOrderRef
                            )
                            StoreTargetOrderRefs(
                                staged,
                                targetSpecKey,
                                previousGroupId,
                                previousOrderRefs
                            )
                        end
                        RemoveOrderRef(
                            targetOrderRefs,
                            seenTargetOrderRefs,
                            targetOrderRef
                        )

                        targetProfile.monitors[targetMonitorId] = nil
                        if targetProfile._yhudScopeByMonitor then
                            targetProfile._yhudScopeByMonitor[targetMonitorId] = nil
                        end
                        local entryDefinition = YHUD:CopyValue(sourceEntryCopy)
                        entryDefinition.entryKey = targetEntryKey
                        entryDefinition.contentScope = YHUD.CONTENT_SCOPE_SPEC
                        entryDefinition.applicability = nil
                        local replacedEntry
                        replacedEntry, code = self:AddEntry(
                            staged,
                            targetEntryKey,
                            entryDefinition,
                            true
                        )
                        if not replacedEntry then return nil, code, report end

                        local copiedMonitor = YHUD:CopyValue(sourceMonitorCopy)
                        -- Keep the target's historical data available for recovery.
                        copiedMonitor.sound = YHUD:CopyValue(targetMonitor.sound)
                        copiedMonitor.id = targetMonitorId
                        copiedMonitor.entryKey = targetEntryKey
                        copiedMonitor.index = nil
                        local addedMonitor
                        addedMonitor, code = self:AddMonitor(staged, copiedMonitor)
                        if not addedMonitor then return nil, code, report end
                        AppendUniqueOrderRef(
                            targetOrderRefs,
                            seenTargetOrderRefs,
                            GetMonitorOrderRef(targetProfile, addedMonitor.id)
                        )
                        StoreTargetOrderRefs(
                            staged,
                            targetSpecKey,
                            sourceMonitorCopy.groupId,
                            targetOrderRefs
                        )
                        row.status = "overwritten"
                        row.materialization = materialization
                        row.monitorId = addedMonitor.id
                        report.overwritten = report.overwritten + 1
                    else
                        local entryKey = FindEntryBySemanticIdentity(
                            targetProfile,
                            identity
                        )
                        if not entryKey then
                            entryKey = sourceMonitorCopy.entryKey
                            if targetProfile.entries[entryKey] ~= nil then
                                entryKey = NextId(targetProfile.entries, "entry:copy:")
                            end
                            local entryDefinition = YHUD:CopyValue(sourceEntryCopy)
                            entryDefinition.entryKey = entryKey
                            entryDefinition.contentScope = YHUD.CONTENT_SCOPE_SPEC
                            entryDefinition.applicability = nil
                            local addedEntry
                            addedEntry, code = self:AddEntry(
                                staged,
                                entryKey,
                                entryDefinition
                            )
                            if not addedEntry then return nil, code, report end
                        end

                        local copiedMonitor = YHUD:CopyValue(sourceMonitorCopy)
                        copiedMonitor.id = targetProfile.monitors[copiedMonitor.id]
                            and NextId(targetProfile.monitors, "monitor:copy:")
                            or copiedMonitor.id
                        copiedMonitor.entryKey = entryKey
                        copiedMonitor.index = nil
                        local addedMonitor
                        addedMonitor, code = self:AddMonitor(staged, copiedMonitor)
                        if not addedMonitor then return nil, code, report end
                        AppendUniqueOrderRef(
                            targetOrderRefs,
                            seenTargetOrderRefs,
                            GetMonitorOrderRef(targetProfile, addedMonitor.id)
                        )
                        StoreTargetOrderRefs(
                            staged,
                            targetSpecKey,
                            sourceMonitorCopy.groupId,
                            targetOrderRefs
                        )
                        row.status = "copied"
                        row.materialization = materialization
                        row.monitorId = addedMonitor.id
                        report.copied = report.copied + 1
                    end
                end
            end
        end
    end

    local restored
    restored, code = self:SwitchDraftSpec(staged, sourceSpecKey)
    if not restored then return nil, code, report end
    local withinBudget, budgetCode, budgetReport =
        ValidateDraftStorageBudget(staged)
    if not withinBudget then
        return nil, budgetCode, budgetReport or report
    end
    local adopted
    adopted, code = self:AdoptDraft(draft, staged)
    if not adopted then return nil, code, report end
    return report
end

function ProfileModel:SyncMonitorToSpecializations(
    draft,
    monitorId,
    targetSpecKeys,
    scopes
)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    scopes = type(scopes) == "table" and scopes or {}
    local syncDisplay = scopes.display == true
    if not syncDisplay then
        return nil, "sync-scope-empty"
    end

    local sourceSpecKey = draft.viewSpecKey or draft.specKey
    local sourceMonitor = draft.profile.monitors[monitorId]
    local sourceEntry = sourceMonitor
        and draft.profile.entries[sourceMonitor.entryKey] or nil
    if not sourceEntry then return nil, "monitor-not-found" end
    if syncDisplay then
        local allowed
        allowed, code = YHUD:CanCrossSpecOperate(
            "sync-display",
            sourceEntry,
            draft.runtimeSpecKey,
            sourceSpecKey
        )
        if not allowed then return nil, code end
    end

    local identity = YHUD:GetEntrySemanticIdentity(
        sourceEntry,
        sourceMonitor.entryKey
    )
    if not identity then return nil, "invalid-semantic-identity" end
    local source = YHUD:CopyValue(sourceMonitor)
    local staged
    staged, code = self:BeginDraft(draft.profile, {
        specKey = sourceSpecKey,
        runtimeSpecKey = draft.runtimeSpecKey,
        combat = draft.combat == true,
    })
    if not staged then return nil, code end

    local report = {
        operation = "sync",
        sourceSpecKey = sourceSpecKey,
        targets = {},
        synced = 0,
        skipped = 0,
    }
    local targets = NormalizeTargetSpecKeys(targetSpecKeys)
    for index = 1, #targets do
        local targetSpecKey = targets[index]
        local row = { specKey = targetSpecKey }
        report.targets[#report.targets + 1] = row
        if targetSpecKey == sourceSpecKey then
            row.status = "source"
            report.skipped = report.skipped + 1
        elseif sourceEntry.sourceType == "yhud.ammo-count"
            and not YHUD:CanMaterializePresetForSpec(sourceEntry, targetSpecKey) then
            row.status, row.code = "not-applicable", "preset-not-applicable"
            report.skipped = report.skipped + 1
        else
            local targetProfile
            targetProfile, code = self:SwitchDraftSpec(staged, targetSpecKey)
            if not targetProfile then return nil, code, report end
            local targetMonitorId, targetMonitor, targetEntry =
                FindMonitorBySemanticIdentity(targetProfile, identity)
            if not targetMonitor then
                row.status = "missing"
                report.skipped = report.skipped + 1
            elseif targetEntry.origin == "official-cdm" then
                row.status = "native-read-only"
                report.skipped = report.skipped + 1
            else
                if syncDisplay then
                    targetMonitor.visibilityMode = source.visibilityMode
                    targetMonitor.stateEffects =
                        YHUD:NormalizeMonitorStateEffects(
                            YHUD:CopyValue(source.stateEffects),
                            targetEntry
                        )
                    local targetGroup = targetProfile.groups.items[
                        targetMonitor.groupId
                    ]
                    targetMonitor.appearanceOverride =
                        self:NormalizeMonitorAppearanceForLayout(
                            YHUD:CopyValue(source.appearanceOverride),
                            targetGroup and targetGroup.layout
                        )
                    targetMonitor.glow = source.glow
                        and YHUD:NormalizeMonitorGlow(
                            YHUD:CopyValue(source.glow)
                        ) or nil
                    targetMonitor.nativeProcGlowOverride =
                        source.nativeProcGlowOverride
                        and YHUD:NormalizeNativeProcGlow(
                            YHUD:CopyValue(source.nativeProcGlowOverride)
                        ) or nil
                    if targetGroup then
                        NormalizeSpecialOverflowOrder(
                            targetProfile,
                            targetGroup
                        )
                    end
                end
                MarkDirty(staged, targetMonitor.groupId, true)
                row.status = "synced"
                row.monitorId = targetMonitorId
                report.synced = report.synced + 1
            end
        end
    end

    local restored
    restored, code = self:SwitchDraftSpec(staged, sourceSpecKey)
    if not restored then return nil, code, report end
    local withinBudget, budgetCode, budgetReport =
        ValidateDraftStorageBudget(staged)
    if not withinBudget then
        return nil, budgetCode, budgetReport or report
    end
    local adopted
    adopted, code = self:AdoptDraft(draft, staged)
    if not adopted then return nil, code, report end
    return report
end

function ProfileModel:SetMonitorVisibilityMode(draft, monitorId, value)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    if value ~= "active" and value ~= "always" then
        return nil, "invalid-visibility-mode"
    end
    local monitor, entry
    monitor, entry, code = GetMutableMonitor(draft, monitorId)
    if not monitor then return nil, code end
    if not YHUD:SupportsPersistentDisplay(entry) then
        return nil, "persistent-display-unsupported"
    end
    monitor.visibilityMode = value
    local group = draft.profile.groups.items[monitor.groupId]
    if group then NormalizeSpecialOverflowOrder(draft.profile, group) end
    MarkDirty(draft, monitor.groupId, true)
    return value
end

function ProfileModel:SetMonitorStateEffect(draft, monitorId, key, value)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    if value ~= nil and type(value) ~= "boolean" then
        return nil, "invalid-monitor-state-effect"
    end
    local monitor, entry
    monitor, entry, code = GetMutableMonitor(draft, monitorId)
    if not monitor then return nil, code end
    local supported = key == "inactiveDesaturate"
        and YHUD:CanConfigureMonitorStateEffects(entry)
        or (key == "auraTimer" or key == "auraHighlight")
            and YHUD:CanConfigureSkillAuraDisplay(entry)
    if not supported then return nil, "monitor-state-effect-unsupported" end

    local effects = type(monitor.stateEffects) == "table"
        and monitor.stateEffects or {}
    effects[key] = value
    monitor.stateEffects = next(effects) and effects or nil
    MarkDirty(draft, monitor.groupId, true)
    return value == nil and "inherit" or value
end

function ProfileModel:ResetMonitorStateEffects(draft, monitorId)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local monitor
    monitor, _, code = GetMutableMonitor(draft, monitorId)
    if not monitor then return nil, code end
    local changed = monitor.stateEffects ~= nil
    monitor.stateEffects = nil
    if changed then MarkDirty(draft, monitor.groupId, true) end
    return changed
end

function ProfileModel:SetMonitorAppearanceOverride(
    draft,
    monitorId,
    patch
)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    if type(patch) ~= "table" then
        return nil, "invalid-monitor-appearance"
    end
    local monitor
    monitor, _, code = GetMutableMonitor(draft, monitorId)
    if not monitor then return nil, code end
    local group = draft.profile.groups.items[monitor.groupId]
    if not group or (group.layout ~= "icons"
        and group.layout ~= "bars" and group.layout ~= "rings") then
        return nil, "monitor-appearance-unsupported"
    end
    local current = type(monitor.appearanceOverride) == "table"
        and YHUD:CopyValue(monitor.appearanceOverride) or {}
    if group.layout == "icons" then
        local mode = patch.cooldownSwipeMode
        if mode == "inherit" then
            current.cooldownSwipeMode = nil
        elseif mode == "disabled" or mode == "forward" or mode == "reverse" then
            current.cooldownSwipeMode = mode
        elseif mode ~= nil then
            return nil, "invalid-monitor-appearance"
        end
    else
        if patch.fillColor ~= nil then current.fillColor = patch.fillColor end
        if patch.trackColor ~= nil then current.trackColor = patch.trackColor end
        if group.layout == "bars" and patch.stackThresholds ~= nil then
            current.stackThresholds = patch.stackThresholds
        end
    end
    monitor.appearanceOverride =
        YHUD:NormalizeMonitorAppearanceOverride(current)
    MarkDirty(draft, monitor.groupId, true)
    return YHUD:CopyValue(monitor.appearanceOverride)
end

function ProfileModel:ResetMonitorAppearanceOverride(draft, monitorId)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local monitor
    monitor, _, code = GetMutableMonitor(draft, monitorId)
    if not monitor then return nil, code end
    local changed = monitor.appearanceOverride ~= nil
    monitor.appearanceOverride = nil
    if changed then MarkDirty(draft, monitor.groupId, true) end
    return changed
end

function ProfileModel:SetMonitorGlow(draft, monitorId, definition)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local monitor
    monitor, _, code = GetMutableMonitor(draft, monitorId)
    if not monitor then return nil, code end
    if definition ~= nil and type(definition) ~= "table" then
        return nil, "invalid-glow"
    end

    local normalized = definition == nil
        and nil or YHUD:NormalizeMonitorGlow(definition)
    for index = 1, #(normalized and normalized.rules or {}) do
        local condition = normalized.rules[index].condition
        if not YHUD:IsMonitorGlowConditionSupported(
            draft.profile,
            monitor,
            condition and condition.type
        ) then
            return nil, "invalid-glow-condition"
        end
    end
    monitor.glow = normalized
    monitor._yhudGlowRuntime = nil
    MarkDirty(draft, monitor.groupId, true)
    return YHUD:CopyValue(monitor.glow)
end

function ProfileModel:SetMonitorSound(draft, monitorId, definition)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local monitor
    monitor, _, code = GetMutableMonitor(draft, monitorId)
    if not monitor then return nil, code end
    if definition ~= nil and type(definition) ~= "table" then
        return nil, "invalid-sound"
    end

    local normalized = definition == nil
        and nil or YHUD:NormalizeMonitorSound(definition)
    for index = 1, #(normalized and normalized.rules or {}) do
        local condition = normalized.rules[index].condition
        if not YHUD:IsMonitorSoundConditionSupported(
            draft.profile,
            monitor,
            condition and condition.type
        ) then
            return nil, "invalid-sound-condition"
        end
    end
    monitor.sound = normalized
    monitor._yhudSoundRuntime = nil
    MarkDirty(draft, monitor.groupId, true)
    return YHUD:CopyValue(monitor.sound)
end

function ProfileModel:SetNativeProcGlow(draft, definition)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    if type(definition) ~= "table" then
        return nil, "invalid-native-proc-glow"
    end
    draft.root.style = type(draft.root.style) == "table"
        and draft.root.style or {}
    draft.root.style.nativeProcGlow =
        YHUD:NormalizeNativeProcGlow(definition)
    for groupId in pairs(draft.profile.groups.items) do
        MarkDirty(draft, groupId)
    end
    return YHUD:CopyValue(draft.root.style.nativeProcGlow)
end

function ProfileModel:SetMonitorNativeProcGlowOverride(
    draft,
    monitorId,
    definition
)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    if definition ~= nil and type(definition) ~= "table" then
        return nil, "invalid-native-proc-glow"
    end
    local monitor
    monitor, _, code = GetMutableMonitor(draft, monitorId)
    if not monitor then return nil, code end
    local capabilities = YHUD:GetMonitorGlowCapabilities(
        draft.profile,
        monitor
    )
    if not (capabilities and capabilities.nativeProc == true) then
        return nil, "native-proc-glow-unsupported"
    end
    if definition == nil then
        monitor.nativeProcGlowOverride = nil
    else
        monitor.nativeProcGlowOverride =
            YHUD:NormalizeNativeProcGlow(definition)
    end
    MarkDirty(draft, monitor.groupId, true)
    return YHUD:CopyValue(monitor.nativeProcGlowOverride)
end

function ProfileModel:SetSkillAuraDisplay(draft, enabled)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    if type(enabled) ~= "boolean" then
        return nil, "invalid-skill-aura-display"
    end
    draft.root.cdm = type(draft.root.cdm) == "table" and draft.root.cdm or {}
    draft.root.cdm.skillAuraDisplay = enabled
    for groupId in pairs(draft.profile.groups.items) do
        MarkDirty(draft, groupId)
    end
    return enabled
end

local GLOBAL_MONITOR_STATE_EFFECT_FIELDS = {
    auraHighlight = "skillAuraHighlight",
    inactiveDesaturate = "inactiveDesaturate",
}

function ProfileModel:SetGlobalMonitorStateEffect(draft, key, enabled)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local field = GLOBAL_MONITOR_STATE_EFFECT_FIELDS[key]
    if not field then return nil, "invalid-monitor-state-effect" end
    if type(enabled) ~= "boolean" then
        return nil, "invalid-monitor-state-effect-value"
    end
    draft.root.cdm = type(draft.root.cdm) == "table"
        and draft.root.cdm or {}
    draft.root.cdm[field] = enabled
    for groupId in pairs(draft.profile.groups.items) do
        MarkDirty(draft, groupId)
    end
    return enabled
end

function ProfileModel:SetPandemicGlow(draft, enabled)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    if type(enabled) ~= "boolean" then
        return nil, "invalid-pandemic-glow"
    end
    draft.root.style = type(draft.root.style) == "table"
        and draft.root.style or {}
    draft.root.style.pandemicGlow = enabled
    for groupId in pairs(draft.profile.groups.items) do
        MarkDirty(draft, groupId)
    end
    return enabled
end

function ProfileModel:SetMonitorSkillAuraDisplayOverride(
    draft,
    monitorId,
    value
)
    local result, code = self:SetMonitorStateEffect(
        draft,
        monitorId,
        "auraTimer",
        value
    )
    if code == "monitor-state-effect-unsupported" then
        return nil, "skill-aura-display-unsupported"
    end
    return result, code
end

local MONITOR_STATE_EFFECT_OVERRIDE_KEYS = {
    auraTimer = true,
    auraHighlight = true,
    inactiveDesaturate = true,
}

local function VisitMonitorStateEffectOverrides(draft, visitor)
    local function Visit(monitors)
        for monitorId, monitor in pairs(type(monitors) == "table" and monitors or {}) do
            visitor(monitorId, monitor)
        end
    end
    Visit(draft.profile and draft.profile.monitors)
end

function ProfileModel:CountMonitorStateEffectOverrides(draft, key)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    if not MONITOR_STATE_EFFECT_OVERRIDE_KEYS[key] then
        return nil, "invalid-monitor-state-effect"
    end
    local count = 0
    VisitMonitorStateEffectOverrides(draft, function(_, monitor)
        local effects = type(monitor) == "table"
            and type(monitor.stateEffects) == "table"
            and monitor.stateEffects or nil
        if effects and type(effects[key]) == "boolean" then
            count = count + 1
        end
    end)
    return count
end

function ProfileModel:ClearMonitorStateEffectOverrides(draft, key)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    if not MONITOR_STATE_EFFECT_OVERRIDE_KEYS[key] then
        return nil, "invalid-monitor-state-effect"
    end
    local count = 0
    VisitMonitorStateEffectOverrides(draft, function(_, monitor)
        local effects = type(monitor) == "table"
            and type(monitor.stateEffects) == "table"
            and monitor.stateEffects or nil
        if effects and type(effects[key]) == "boolean" then
            effects[key] = nil
            monitor.stateEffects = next(effects) and effects or nil
            count = count + 1
        end
    end)
    if count > 0 then
        for groupId in pairs(draft.profile.groups.items) do
            MarkDirty(draft, groupId, true)
        end
    end
    return count
end

function ProfileModel:CountSkillAuraDisplayOverrides(draft)
    return self:CountMonitorStateEffectOverrides(draft, "auraTimer")
end

function ProfileModel:ClearSkillAuraDisplayOverrides(draft)
    return self:ClearMonitorStateEffectOverrides(draft, "auraTimer")
end

function ProfileModel:MoveMonitor(
    draft,
    monitorId,
    targetGroupId,
    targetIndex,
    targetView,
    targetLane
)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local mutable
    mutable, _, code = GetMutableMonitor(draft, monitorId)
    if not mutable then return nil, code end
    local profile = draft.profile
    local monitor = profile.monitors[monitorId]
    if not monitor then return nil, "monitor-not-found" end
    local entry = profile.entries[monitor.entryKey]
    if not entry then return nil, "entry-not-found" end
    local target = profile.groups.items[targetGroupId]
    if not target then return nil, "group-not-found" end
    targetView = targetView or monitor.view
    local placed
    placed, code = CheckPlacement(entry, target, targetView)
    if not placed then return nil, code end

    local sourceGroupId = monitor.groupId
    local source = profile.groups.items[sourceGroupId]
    if not source then return nil, "group-not-found" end
    RemoveArrayValue(source.monitors, monitorId)
    NormalizeMonitorOrders(profile, sourceGroupId)
    InsertArrayValue(target.monitors, monitorId, targetIndex)
    NormalizeMonitorOrders(profile, targetGroupId)
    monitor.groupId = targetGroupId
    monitor.view = targetView
    monitor.appearanceOverride =
        self:NormalizeMonitorAppearanceForLayout(
            monitor.appearanceOverride,
            target.layout
        )
    NormalizeSpecialOverflowOrder(profile, source)
    NormalizeSpecialOverflowOrder(profile, target)
    if YHUD.InitializeMixedAuraDesaturation then
        YHUD:InitializeMixedAuraDesaturation(profile, targetGroupId)
    end
    MarkDirty(draft, sourceGroupId, true)
    MarkDirty(draft, targetGroupId, true)
    return YHUD:CopyValue(monitor), {
        sourceChanged = false,
        sourceRebuilds = 0,
        writeBackCalls = 0,
    }
end

function ProfileModel:ReorderMonitor(draft, monitorId, targetLane, targetIndex)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local profile = draft.profile
    local monitor
    monitor, _, code = GetMutableMonitor(draft, monitorId)
    if not monitor then return nil, code end
    local group = profile.groups.items[monitor.groupId]
    if not group then return nil, "group-not-found" end
    if not ArrayIndex(group.monitors, monitorId) then
        return nil, "orphan-monitor"
    end
    if type(targetLane) == "number" and targetIndex == nil then
        targetIndex = targetLane
    end
    local nextMonitors = YHUD:CopyValue(group.monitors)
    RemoveArrayValue(nextMonitors, monitorId)
    InsertArrayValue(nextMonitors, monitorId, targetIndex)
    if not IsSpecialOverflowOrderValid(profile, group, nextMonitors) then
        return nil, "special-overflow-region"
    end
    group.monitors = nextMonitors
    NormalizeMonitorOrders(profile, group.id)
    MarkDirty(draft, group.id, true)
    return YHUD:CopyValue(monitor)
end

function ProfileModel:ReorderMonitorByOrderRefs(
    draft,
    monitorId,
    groupId,
    orderedRefs
)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local profile = draft.profile
    local monitor
    monitor, _, code = GetMutableMonitor(draft, monitorId)
    if not monitor then return nil, code end
    if monitor.groupId ~= groupId then return nil, "drop-context-changed" end
    local group = profile.groups.items[groupId]
    if not group then return nil, "group-not-found" end
    if not ArrayIndex(group.monitors, monitorId) then
        return nil, "orphan-monitor"
    end
    if type(orderedRefs) ~= "table" then
        return nil, "invalid-order-refs"
    end

    local monitorByRef = {}
    local sourceRef = GetMonitorOrderRef(profile, monitorId)
    for index = 1, #group.monitors do
        local candidateId = group.monitors[index]
        local ref = GetMonitorOrderRef(profile, candidateId)
        if not IsOrderRef(ref) then return nil, "invalid-order-ref" end
        if monitorByRef[ref] ~= nil then
            return nil, "duplicate-order-ref"
        end
        monitorByRef[ref] = candidateId
    end

    local nextMonitors = {}
    local seen = {}
    local hasOfficialRef = false
    for index = 1, #orderedRefs do
        local ref = orderedRefs[index]
        if not IsOrderRef(ref) then return nil, "invalid-order-ref" end
        if seen[ref] then return nil, "duplicate-order-ref" end
        seen[ref] = true
        local official = ref:sub(1, 9) == "official:"
        hasOfficialRef = hasOfficialRef or official
        local candidateId = monitorByRef[ref]
        if candidateId then
            nextMonitors[#nextMonitors + 1] = candidateId
        elseif not official then
            return nil, "drop-context-changed"
        end
    end
    if not seen[sourceRef] then return nil, "drop-source-changed" end
    for ref in pairs(monitorByRef) do
        if not seen[ref] then return nil, "drop-context-changed" end
    end
    if #nextMonitors ~= #group.monitors then
        return nil, "drop-context-changed"
    end
    if not IsSpecialOverflowOrderValid(profile, group, nextMonitors) then
        return nil, "special-overflow-region"
    end

    local specKey = draft.viewSpecKey or draft.specKey
    local specOverrides = type(draft.root.officialOverridesBySpec) == "table"
        and draft.root.officialOverridesBySpec[specKey] or nil
    local storedRefs = specOverrides and type(specOverrides.groups) == "table"
        and specOverrides.groups[groupId] or nil
    local storeRefs = hasOfficialRef or type(storedRefs) == "table"
    local orderChanged = not ValuesEqual(group.monitors, nextMonitors)
    local refsChanged = storeRefs
        and not ValuesEqual(storedRefs, orderedRefs) or false
    if not orderChanged and not refsChanged then
        return YHUD:CopyValue(monitor)
    end

    if orderChanged then
        group.monitors = nextMonitors
        NormalizeMonitorOrders(profile, group.id)
    end
    if storeRefs then
        StoreTargetOrderRefs(draft, specKey, groupId, orderedRefs)
    end
    MarkDirty(draft, group.id, true)
    return YHUD:CopyValue(monitor)
end

function ProfileModel:RemoveMonitor(draft, monitorId)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local profile = draft.profile
    local monitor
    monitor, _, code = GetMutableMonitor(draft, monitorId)
    if not monitor then return nil, code end
    local group = profile.groups.items[monitor.groupId]
    if group then
        RemoveArrayValue(group.monitors, monitorId)
        NormalizeMonitorOrders(profile, group.id)
        MarkDirty(draft, group.id, true)
    end
    local entry = profile.entries[monitor.entryKey]
    if entry and entry.origin == "official-cdm" then
        profile.suppressedOfficial[entry.entryKey] = true
    end
    if entry then SetDefaultPresetTombstone(draft, entry, true) end
    profile.monitors[monitorId] = nil
    local laneByMonitor = rawget(profile, "_yhudLaneByMonitor")
    if laneByMonitor then laneByMonitor[monitorId] = nil end
    MarkChanged(draft)
    return true
end

-- Match monitor identity across stored scopes, independent of its group placement.
function ProfileModel:RemoveMonitorFromAllSpecializations(draft, monitorId, onScopeRemoved)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    local source = draft.profile.monitors[monitorId]
    local entry = source and draft.profile.entries[source.entryKey]
    if not entry then return nil, "monitor-not-found" end
    local allowed
    allowed, code = YHUD:CanCrossSpecOperate("delete", entry,
        draft.runtimeSpecKey, draft.viewSpecKey)
    if not allowed then return nil, code end
    local identity = YHUD:GetEntrySemanticIdentity(entry, source.entryKey)
    if not identity then return nil, "invalid-semantic-identity" end
    local sourceSpecKey = draft.viewSpecKey or draft.specKey
    local staged
    staged, code = self:BeginDraft(draft.profile, {
        specKey = sourceSpecKey,
        runtimeSpecKey = draft.runtimeSpecKey,
        combat = draft.combat == true,
    })
    if not staged then return nil, code end
    local keys = { [sourceSpecKey] = true }
    for specKey in pairs(staged.root.contentBySpec or {}) do keys[specKey] = true end
    local documents = staged.root.specDocuments
    for specKey in pairs(documents and documents.blocks or {}) do keys[specKey] = true end
    if YHUD:IsDefaultSlotPresetEntry(entry) then
        for _, specKey in ipairs(YHUD.Client and YHUD.Client.fallbackSpecKeys or {}) do
            keys[specKey] = true
        end
    end
    local targets = {}
    for specKey in pairs(keys) do
        if YHUD:IsStableSpecKey(specKey) then targets[#targets + 1] = specKey end
    end
    table.sort(targets)
    local report = { removed = 0, specializations = 0 }
    for _, specKey in ipairs(targets) do
        local profile
        profile, code = self:SwitchDraftSpec(staged, specKey)
        if not profile then return nil, code end
        local matches = {}
        for id, monitor in pairs(profile.monitors) do
            if YHUD:GetMonitorSemanticIdentity(profile, monitor) == identity then
                matches[#matches + 1] = id
            end
        end
        for _, id in ipairs(matches) do
            local removed
            removed, code = self:RemoveMonitor(staged, id)
            if not removed then return nil, code end
            report.removed = report.removed + 1
        end
        if #matches > 0 then
            report.specializations = report.specializations + 1
            if onScopeRemoved then
                local updated
                updated, code = onScopeRemoved(staged)
                if not updated then return nil, code end
            end
        end
    end
    local restored
    restored, code = self:SwitchDraftSpec(staged, sourceSpecKey)
    if not restored then return nil, code end
    local adopted
    adopted, code = self:AdoptDraft(draft, staged)
    if not adopted then return nil, code end
    return report
end

function ProfileModel:ClaimCategory(draft, category, targetGroupId)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end
    if not CATEGORY_LAYOUTS[category] then return nil, "invalid-category" end
    local defaultGroupId = YHUD.DEFAULT_GROUP_BY_CATEGORY
        and YHUD.DEFAULT_GROUP_BY_CATEGORY[category]
    if targetGroupId ~= defaultGroupId then
        return nil, "native-sync-fixed"
    end
    return {
        previousGroupId = defaultGroupId,
        targetGroupId = targetGroupId,
        movedMonitorIds = {},
    }
end

local function NextOfficialMonitorId(profile, entryKey)
    local base = "monitor:" .. entryKey
    if not profile.monitors[base] then return base end
    local index = 2
    while profile.monitors[base .. ":" .. tostring(index)] do
        index = index + 1
    end
    return base .. ":" .. tostring(index)
end

local function SelectExistingCategoryMonitors(profile, category, targetGroupId)
    local selectedByEntry = {}
    local categoryMonitorIds = {}

    local function VisitGroup(groupId)
        local group = profile.groups.items[groupId]
        if not group then return end
        for index = 1, #group.monitors do
            local monitorId = group.monitors[index]
            local monitor = profile.monitors[monitorId]
            if GetMonitorCategory(profile, monitor) == category then
                categoryMonitorIds[#categoryMonitorIds + 1] = monitorId
                if monitor and not selectedByEntry[monitor.entryKey] then
                    selectedByEntry[monitor.entryKey] = monitorId
                end
            end
        end
    end

    VisitGroup(targetGroupId)
    for index = 1, #profile.groups.order do
        local groupId = profile.groups.order[index]
        if groupId ~= targetGroupId then VisitGroup(groupId) end
    end
    return selectedByEntry, categoryMonitorIds
end

local function FindOfficialInsertionIndex(profile, group, category)
    local customBefore = 0
    for index = 1, #group.monitors do
        local monitor = profile.monitors[group.monitors[index]]
        if GetMonitorCategory(profile, monitor) == category then
            return customBefore + 1
        end
        customBefore = customBefore + 1
    end
    return #group.monitors + 1
end

local function NormalizeFixedCategory(profile, category, targetGroupId)
    for _, group in pairs(profile.groups.items) do
        while RemoveArrayValue(group.officialCategories, category) do end
    end
    local target = profile.groups.items[targetGroupId]
    target.officialCategories[#target.officialCategories + 1] = category
end

local function RestoreCategoryInDraft(
    draft,
    category,
    targetGroupId,
    orderedEntryKeys
)
    local profile = draft.profile
    local allowedLayouts = CATEGORY_LAYOUTS[category]
    if not allowedLayouts then return nil, "invalid-category" end
    local defaultGroupId = YHUD.DEFAULT_GROUP_BY_CATEGORY
        and YHUD.DEFAULT_GROUP_BY_CATEGORY[category]
    if targetGroupId ~= defaultGroupId then
        return nil, "native-sync-fixed"
    end
    local target = profile.groups.items[targetGroupId]
    if not target then return nil, "group-not-found" end
    if not allowedLayouts[target.layout] then
        return nil, "category-layout-mismatch"
    end
    if type(orderedEntryKeys) ~= "table" then
        return nil, "invalid-entry-order"
    end

    local insertionIndex =
        FindOfficialInsertionIndex(profile, target, category)
    local selectedByEntry, categoryMonitorIds =
        SelectExistingCategoryMonitors(profile, category, targetGroupId)
    local previousGroupId
    for groupId, group in pairs(profile.groups.items) do
        for index = 1, #group.monitors do
            if GetMonitorCategory(profile, profile.monitors[group.monitors[index]])
                    == category then
                previousGroupId = groupId
                break
            end
        end
        if previousGroupId then break end
    end
    local touchedGroups = {}
    local customByGroup = {}

    for index = 1, #profile.groups.order do
        local groupId = profile.groups.order[index]
        local group = profile.groups.items[groupId]
        local custom = {}
        for monitorIndex = 1, #group.monitors do
            local monitorId = group.monitors[monitorIndex]
            local monitor = profile.monitors[monitorId]
            if GetMonitorCategory(profile, monitor) ~= category then
                custom[#custom + 1] = monitorId
            else
                touchedGroups[groupId] = true
            end
        end
        customByGroup[groupId] = custom
    end

    NormalizeFixedCategory(profile, category, targetGroupId)
    if previousGroupId then touchedGroups[previousGroupId] = true end
    touchedGroups[targetGroupId] = true

    local report = {
        category = category,
        previousGroupId = previousGroupId,
        targetGroupId = targetGroupId,
        retained = {},
        created = {},
        moved = {},
        removed = {},
        pending = {},
        duplicateEntryKeys = {},
        writeBackCalls = 0,
    }
    local desiredIds = {}
    local desiredIdSet = {}
    local seenEntryKeys = {}

    for index = 1, #orderedEntryKeys do
        local entryKey = orderedEntryKeys[index]
        if type(entryKey) ~= "string" then
            return nil, "invalid-entry-key"
        end
        if seenEntryKeys[entryKey] then
            report.duplicateEntryKeys[#report.duplicateEntryKeys + 1] =
                entryKey
        else
            seenEntryKeys[entryKey] = true
            local entry = profile.entries[entryKey]
            if not entry then return nil, "entry-not-found" end
            if entry.officialCategory ~= category then
                return nil, "entry-category-mismatch"
            end
            profile.suppressedOfficial[entryKey] = nil

            local contract = type(entry.contract) == "table"
                and entry.contract or {}
            local nativeOfficial = entry.origin == "official-cdm"
                and (contract.capability == "native-enhanced"
                    or contract.view == "native")
            if not IsStableId(entry.sourceKey) and not nativeOfficial then
                report.pending[#report.pending + 1] = entryKey
            else
                local monitorId = selectedByEntry[entryKey]
                local monitor = monitorId and profile.monitors[monitorId]
                local view = monitor and monitor.view
                    or DEFAULT_VIEW[target.layout]
                local placed
                if nativeOfficial then
                    view = DEFAULT_VIEW[target.layout]
                    placed = view ~= nil
                else
                    placed = CheckPlacement(entry, target, view)
                    if not placed then
                        view = DEFAULT_VIEW[target.layout]
                        placed = CheckPlacement(entry, target, view)
                    end
                end
                if not placed then return nil, "view-layout-mismatch" end

                if monitor then
                    report.retained[#report.retained + 1] = monitorId
                    if monitor.groupId ~= targetGroupId then
                        report.moved[#report.moved + 1] = monitorId
                    end
                else
                    monitorId = NextOfficialMonitorId(profile, entryKey)
                    monitor = {
                        id = monitorId,
                        enabled = true,
                    }
                    profile.monitors[monitorId] = monitor
                    report.created[#report.created + 1] = monitorId
                end

                monitor.entryKey = entryKey
                monitor.sourceKey = entry.sourceKey
                monitor.groupId = targetGroupId
                monitor.view = view
                monitor.appearanceOverride =
                    ProfileModel:NormalizeMonitorAppearanceForLayout(
                        monitor.appearanceOverride,
                        target.layout
                    )
                monitor.origin = "official-cdm"
                monitor.officialCategory = category
                monitor.contentScope = YHUD.CONTENT_SCOPE_SPEC
                SetMonitorLane(profile, monitorId, YHUD.CONTENT_LANE_SPEC)
                desiredIds[#desiredIds + 1] = monitorId
                desiredIdSet[monitorId] = true
            end
        end
    end

    for index = 1, #categoryMonitorIds do
        local monitorId = categoryMonitorIds[index]
        if not desiredIdSet[monitorId] then
            profile.monitors[monitorId] = nil
            local laneByMonitor = rawget(profile, "_yhudLaneByMonitor")
            if laneByMonitor then laneByMonitor[monitorId] = nil end
            report.removed[#report.removed + 1] = monitorId
        end
    end

    for groupId, monitors in pairs(customByGroup) do
        profile.groups.items[groupId].monitors = monitors
    end
    local targetMonitors = target.monitors
    if insertionIndex < 1 then insertionIndex = 1 end
    if insertionIndex > #targetMonitors + 1 then
        insertionIndex = #targetMonitors + 1
    end
    for index = 1, #desiredIds do
        table.insert(targetMonitors, insertionIndex + index - 1, desiredIds[index])
    end

    for groupId in pairs(touchedGroups) do
        ApplyGroupLanes(profile, groupId, GetGroupLanes(profile, groupId))
        MarkDirty(draft, groupId, true)
    end
    report.counts = {
        retained = #report.retained,
        created = #report.created,
        moved = #report.moved,
        removed = #report.removed,
        pending = #report.pending,
        duplicateEntryKeys = #report.duplicateEntryKeys,
        writeBackCalls = 0,
    }
    return report
end

function ProfileModel:RestoreCategory(
    draft,
    category,
    targetGroupId,
    orderedEntryKeys
)
    local open, code = EnsureOpenDraft(draft)
    if not open then return nil, code end

    local staged = self:BeginDraft(draft.profile, {
        combat = draft.combat == true,
        specKey = draft.specKey,
    })
    local report
    report, code = RestoreCategoryInDraft(
        staged,
        category,
        targetGroupId,
        orderedEntryKeys
    )
    if not report then return nil, code end

    local adopted
    adopted, code = self:AdoptDraft(draft, staged)
    if not adopted then return nil, code end
    return report
end

function ProfileModel:BuildSourceIndex(profile, enabledOnly)
    profile = type(profile) == "table" and profile or {}
    local groups = profile.groups and profile.groups.items or {}
    local monitors = profile.monitors or {}
    local sources = {}
    local sourceCount = 0
    local monitorCount = 0
    if enabledOnly == nil then enabledOnly = true end

    local groupOrder = profile.groups and profile.groups.order or {}
    for groupIndex = 1, #groupOrder do
        local group = groups[groupOrder[groupIndex]]
        if group and (not enabledOnly or group.enabled) then
            for monitorIndex = 1, #group.monitors do
                local monitorId = group.monitors[monitorIndex]
                local monitor = monitors[monitorId]
                local entry = monitor
                    and profile.entries
                    and profile.entries[monitor.entryKey]
                local eligible = not entry
                    or YHUD:EvaluateEntryApplicability(
                        entry,
                        rawget(profile, "_yhudSpecKey")
                    ) == "eligible"
                if monitor
                    and monitor.sourceKey
                    and eligible
                    and (not enabledOnly or monitor.enabled) then
                    local consumers = sources[monitor.sourceKey]
                    if not consumers then
                        consumers = {}
                        sources[monitor.sourceKey] = consumers
                        sourceCount = sourceCount + 1
                    end
                    consumers[#consumers + 1] = monitorId
                    monitorCount = monitorCount + 1
                end
            end
        end
    end
    return {
        sources = sources,
        sourceCount = sourceCount,
        monitorCount = monitorCount,
    }
end

local function ValidateIconGroupLayout(layout)
    if type(layout) ~= "table" then return false end
    local iconSize = layout.iconSize
    local maxPerLine = layout.maxPerLine
    if type(iconSize) ~= "number" or iconSize % 1 ~= 0
        or iconSize < 24 or iconSize > 96 then
        return false
    end
    if type(layout.columnSpacing) ~= "number"
        or layout.columnSpacing % 1 ~= 0
        or layout.columnSpacing < 0 or layout.columnSpacing > 32
        or type(layout.rowSpacing) ~= "number"
        or layout.rowSpacing % 1 ~= 0
        or layout.rowSpacing < 0 or layout.rowSpacing > 32 then
        return false
    end
    if type(maxPerLine) ~= "number" or maxPerLine % 1 ~= 0
        or maxPerLine < 1 or maxPerLine > 20 then
        return false
    end
    if layout.wrapDirection ~= "down"
        and layout.wrapDirection ~= "up" then
        return false
    end
    if layout.rowDirection ~= "right"
        and layout.rowDirection ~= "left" then
        return false
    end
    if layout.alignment ~= "start" and layout.alignment ~= "center"
        and layout.alignment ~= "end" then
        return false
    end
    return true
end

local function ValidateUnitColor(color)
    if type(color) ~= "table" then return false end
    local keys = { "r", "g", "b", "a" }
    for index = 1, #keys do
        local value = color[keys[index]]
        if type(value) ~= "number" or value < 0 or value > 1 then
            return false
        end
    end
    return true
end

local function ValidateGlowAppearance(appearance)
    if type(appearance) ~= "table" then return false end
    if appearance.style ~= "none"
        and appearance.style ~= "pixel"
        and appearance.style ~= "soft"
        and appearance.style ~= "button"
        and appearance.style ~= "autocast"
        and appearance.style ~= "proc"
        and appearance.style ~= "pulse" then
        return false
    end
    if type(appearance.size) ~= "number"
        or appearance.size < 0.25 or appearance.size > 5
        or type(appearance.lines) ~= "number"
        or appearance.lines % 1 ~= 0
        or appearance.lines < 1 or appearance.lines > 20
        or type(appearance.thickness) ~= "number"
        or appearance.thickness % 1 ~= 0
        or appearance.thickness < 1 or appearance.thickness > 20
        or type(appearance.speed) ~= "number"
        or appearance.speed < 0 or appearance.speed > 3
        or type(appearance.alpha) ~= "number"
        or appearance.alpha < 0.1 or appearance.alpha > 1
        or type(appearance.offsetX) ~= "number"
        or appearance.offsetX < -1 or appearance.offsetX > 1
        or type(appearance.offsetY) ~= "number"
        or appearance.offsetY < -1 or appearance.offsetY > 1 then
        return false
    end

    local color = appearance.color
    if type(color) ~= "table" then return false end
    for index = 1, 4 do
        local value = color[index]
        if type(value) ~= "number" or value < 0 or value > 1 then
            return false
        end
    end
    return true
end

local function ValidateNativeProcGlow(value)
    if type(value) ~= "table"
        or (value.mode ~= "default" and value.mode ~= "custom")
        or (value.combatOnly ~= nil and value.combatOnly ~= true) then
        return false
    end
    if value.mode == "default" then return value.appearance == nil end
    return ValidateGlowAppearance(value.appearance)
        and value.appearance.style ~= "none"
end

local function ValidateMonitorGlow(profile, monitor, glow)
    if glow == nil then return true end
    if type(glow) ~= "table"
        or type(glow.rules) ~= "table"
        or #glow.rules < 1
        or #glow.rules > 2 then
        return false
    end
    local seen = {}
    for index = 1, #glow.rules do
        local rule = glow.rules[index]
        local condition = type(rule) == "table" and rule.condition or nil
        local conditionType = type(condition) == "table"
            and condition.type or nil
        if rule.combatOnly ~= nil and rule.combatOnly ~= true then
            return false
        end
        if seen[conditionType]
            or not YHUD:IsMonitorGlowConditionSupported(
                profile,
                monitor,
                conditionType
            )
            or not ValidateGlowAppearance(rule.appearance) then
            return false
        end
        seen[conditionType] = true
    end
    return true
end

local function ValidateMonitorSound(profile, monitor, sound)
    if sound == nil then return true end
    if type(sound) ~= "table"
        or type(sound.rules) ~= "table"
        or #sound.rules < 1 then
        return false
    end
    local capabilities = YHUD:GetMonitorSoundCapabilities(profile, monitor)
    if not capabilities then
        local entry = profile.entries and profile.entries[monitor.entryKey]
        -- Official cooldown rows can temporarily lack the metadata needed to
        -- classify them while the Blizzard catalog is being rebuilt.  Their
        -- sparse override must remain valid and dormant until that identity
        -- resolves again.
        return type(entry) == "table" and entry.origin == "official-cdm"
    end
    if #sound.rules > #capabilities.conditions then
        return false
    end
    local seen = {}
    for index = 1, #sound.rules do
        local rule = sound.rules[index]
        local condition = type(rule) == "table" and rule.condition or nil
        local conditionType = type(condition) == "table"
            and condition.type or nil
        local soundKey = type(rule) == "table" and rule.sound or nil
        if seen[conditionType]
            or not YHUD:IsMonitorSoundConditionSupported(
                profile,
                monitor,
                conditionType
            )
            or (soundKey ~= nil and (
                type(soundKey) ~= "string"
                or soundKey == ""
                or #soundKey > 160
            )) then
            return false
        end
        seen[conditionType] = true
    end
    return true
end

local function ValidateFontChoice(value)
    return type(value) == "string" and value ~= "" and #value <= 160
end

local VALID_TEXT_POSITIONS = {
    center = true,
    top = true,
    bottom = true,
    left = true,
    right = true,
    ["top-left"] = true,
    ["bottom-left"] = true,
    ["top-right"] = true,
    ["bottom-right"] = true,
}

local function ValidateIconGroupStyle(style)
    if type(style) ~= "table" then return false end
    if style.iconShape ~= "square"
        and style.iconShape ~= "roundedSquare"
        and style.iconShape ~= "flatSquare"
        and style.iconShape ~= "flatRounded"
        and style.iconShape ~= "wideSquare"
        and style.iconShape ~= "wideRounded"
        and style.iconShape ~= "circle" then
        return false
    end
    if style.iconBorder ~= "none" and style.iconBorder ~= "thin"
        and style.iconBorder ~= "medium"
        and style.iconBorder ~= "thick"
        and style.iconBorder ~= "extraThick" then
        return false
    end
    if type(style.iconZoom) ~= "number"
        or style.iconZoom < 0 or style.iconZoom > 0.24 then
        return false
    end
    if not ValidateUnitColor(style.iconBorderColor)
        or not ValidateUnitColor(style.iconBackgroundColor)
        or not ValidateUnitColor(style.iconShadowColor)
        or not ValidateUnitColor(style.cooldownSwipeColor) then
        return false
    end
    if type(style.iconShadow) ~= "boolean"
        or type(style.cooldownBling) ~= "boolean"
        or type(style.cooldownSwipe) ~= "boolean"
        or type(style.cooldownGCD) ~= "boolean"
        or type(style.cooldownText) ~= "boolean" then
        return false
    end
    if not ValidateFontChoice(style.cooldownTextFont) then
        return false
    end
    if type(style.cooldownTextSize) ~= "number"
        or style.cooldownTextSize % 1 ~= 0
        or style.cooldownTextSize < 8
        or style.cooldownTextSize > 32 then
        return false
    end
    if style.cooldownTextOutline ~= "none"
        and style.cooldownTextOutline ~= "outline"
        and style.cooldownTextOutline ~= "thick"
        and style.cooldownTextOutline ~= "shadow"
        and style.cooldownTextOutline ~= "outlineShadow" then
        return false
    end
    if not VALID_TEXT_POSITIONS[style.cooldownTextPosition] then
        return false
    end
    if type(style.cooldownTextOffsetX) ~= "number"
        or style.cooldownTextOffsetX < -64
        or style.cooldownTextOffsetX > 64
        or type(style.cooldownTextOffsetY) ~= "number"
        or style.cooldownTextOffsetY < -64
        or style.cooldownTextOffsetY > 64 then
        return false
    end
    if type(style.countText) ~= "boolean"
        or not ValidateFontChoice(style.countTextFont)
        or type(style.countTextSize) ~= "number"
        or style.countTextSize < 8 or style.countTextSize > 32
        or style.countTextSize % 1 ~= 0
        or (style.countTextOutline ~= "none"
            and style.countTextOutline ~= "outline"
            and style.countTextOutline ~= "thick"
            and style.countTextOutline ~= "shadow"
            and style.countTextOutline ~= "outlineShadow")
        or not VALID_TEXT_POSITIONS[style.countTextPosition]
        or type(style.countTextOffsetX) ~= "number"
        or style.countTextOffsetX < -64
        or style.countTextOffsetX > 64
        or type(style.countTextOffsetY) ~= "number"
        or style.countTextOffsetY < -64
        or style.countTextOffsetY > 64 then
        return false
    end
    if style.keybindTextMode ~= "off"
        and style.keybindTextMode ~= "auto"
        and style.keybindTextMode ~= "manual" then
        return false
    end
    if not ValidateFontChoice(style.keybindTextFont)
        or type(style.keybindTextSize) ~= "number"
        or style.keybindTextSize % 1 ~= 0
        or style.keybindTextSize < 8
        or style.keybindTextSize > 32
        or (style.keybindTextOutline ~= "none"
            and style.keybindTextOutline ~= "outline"
            and style.keybindTextOutline ~= "thick"
            and style.keybindTextOutline ~= "shadow"
            and style.keybindTextOutline ~= "outlineShadow")
        or not VALID_TEXT_POSITIONS[style.keybindTextPosition]
        or type(style.keybindTextOffsetX) ~= "number"
        or style.keybindTextOffsetX < -64
        or style.keybindTextOffsetX > 64
        or type(style.keybindTextOffsetY) ~= "number"
        or style.keybindTextOffsetY < -64
        or style.keybindTextOffsetY > 64
        or not ValidateUnitColor(style.keybindTextColor)
        or type(style.keybindTextOverrides) ~= "table" then
        return false
    end
    for spellID, text in pairs(style.keybindTextOverrides) do
        if type(spellID) ~= "number" or spellID <= 0
            or spellID % 1 ~= 0 or type(text) ~= "string" then
            return false
        end
        local characterCount = 0
        for index = 1, #text do
            local byte = text:byte(index)
            if byte < 128 or byte >= 194 then
                characterCount = characterCount + 1
            end
            if byte < 32 or byte == 127 or characterCount > 16 then
                return false
            end
        end
    end
    return ValidateUnitColor(style.cooldownTextColor)
        and ValidateUnitColor(style.countTextColor)
end

local function ValidateDurationGroupLayout(layout, layoutType)
    if type(layout) ~= "table" then return false end
    if type(layout.columnSpacing) ~= "number"
        or layout.columnSpacing % 1 ~= 0
        or layout.columnSpacing < 0 or layout.columnSpacing > 32
        or type(layout.rowSpacing) ~= "number"
        or layout.rowSpacing % 1 ~= 0
        or layout.rowSpacing < 0 or layout.rowSpacing > 32 then
        return false
    end
    if type(layout.maxPerLine) ~= "number"
        or layout.maxPerLine % 1 ~= 0
        or layout.maxPerLine < 1 or layout.maxPerLine > 20 then
        return false
    end
    if layout.alignment ~= "start" and layout.alignment ~= "center"
        and layout.alignment ~= "end" then
        return false
    end

    if layoutType == "rings" then
        if type(layout.diameter) ~= "number" or layout.diameter % 1 ~= 0
            or layout.diameter < 24 or layout.diameter > 160 then
            return false
        end
        return layout.wrapDirection == "down"
            or layout.wrapDirection == "up"
    end

    if type(layout.width) ~= "number" or layout.width % 1 ~= 0
        or layout.width < 48 or layout.width > 832 then
        return false
    end
    if type(layout.height) ~= "number" or layout.height % 1 ~= 0
        or layout.height < 12 or layout.height > 352 then
        return false
    end
    if layout.orientation ~= "horizontal"
        and layout.orientation ~= "vertical" then
        return false
    end
    if layout.fillDirection ~= nil and layout.fillDirection ~= "forward"
        and layout.fillDirection ~= "reverse" then
        return false
    end
    if layout.iconPosition ~= "left" and layout.iconPosition ~= "right"
        and layout.iconPosition ~= "top"
        and layout.iconPosition ~= "bottom"
        and layout.iconPosition ~= "center" then
        return false
    end
    if type(layout.iconGap) ~= "number" or layout.iconGap % 1 ~= 0
        or layout.iconGap < 0 or layout.iconGap > 32 then
        return false
    end
    return layout.wrapDirection == "down"
        or layout.wrapDirection == "up"
end

local function ValidateStatusBarTexture(value)
    return type(value) == "string"
        and value ~= ""
        and #value <= 160
end

local function ValidateDurationGroupStyle(style)
    if not ValidateIconGroupStyle(style) then return false end
    if type(style.nameText) ~= "boolean" then return false end
    if type(style.nameTextFormat) ~= "string"
        or style.nameTextFormat == ""
        or #style.nameTextFormat > 64 then
        return false
    end
    if not ValidateFontChoice(style.nameTextFont) then
        return false
    end
    if type(style.nameTextSize) ~= "number"
        or style.nameTextSize % 1 ~= 0
        or style.nameTextSize < 8
        or style.nameTextSize > 32 then
        return false
    end
    if style.nameTextOutline ~= "none"
        and style.nameTextOutline ~= "outline"
        and style.nameTextOutline ~= "thick"
        and style.nameTextOutline ~= "shadow"
        and style.nameTextOutline ~= "outlineShadow" then
        return false
    end
    if not VALID_TEXT_POSITIONS[style.nameTextPosition] then
        return false
    end
    if type(style.nameTextOffsetX) ~= "number"
        or style.nameTextOffsetX < -64
        or style.nameTextOffsetX > 64
        or type(style.nameTextOffsetY) ~= "number"
        or style.nameTextOffsetY < -64
        or style.nameTextOffsetY > 64 then
        return false
    end
    if not ValidateStatusBarTexture(style.fillTexture) then
        return false
    end
    if type(style.showIcon) ~= "boolean"
        or type(style.timeText) ~= "boolean"
        or not ValidateFontChoice(style.timeTextFont)
        or type(style.timeTextSize) ~= "number"
        or style.timeTextSize % 1 ~= 0
        or style.timeTextSize < 8
        or style.timeTextSize > 32
        or (style.timeTextOutline ~= "none"
            and style.timeTextOutline ~= "outline"
            and style.timeTextOutline ~= "thick"
            and style.timeTextOutline ~= "shadow"
            and style.timeTextOutline ~= "outlineShadow")
        or not VALID_TEXT_POSITIONS[style.timeTextPosition]
        or type(style.timeTextOffsetX) ~= "number"
        or style.timeTextOffsetX < -64
        or style.timeTextOffsetX > 64
        or type(style.timeTextOffsetY) ~= "number"
        or style.timeTextOffsetY < -64
        or style.timeTextOffsetY > 64
        or type(style.ringThickness) ~= "number"
        or not RING_THICKNESS_VALUES[style.ringThickness]
        or (style.ringDirection ~= "clockwise"
            and style.ringDirection ~= "counterclockwise")
        or (style.ringStart ~= "top"
            and style.ringStart ~= "right"
            and style.ringStart ~= "bottom"
            and style.ringStart ~= "left") then
        return false
    end
    return ValidateUnitColor(style.nameTextColor)
        and ValidateUnitColor(style.fillColor)
        and ValidateUnitColor(style.trackColor)
        and ValidateUnitColor(style.borderColor)
        and ValidateUnitColor(style.timeTextColor)
        and ValidateUnitColor(style.ringTrackColor)
        and ValidateUnitColor(style.ringBorderColor)
end

local function ValidateResourceGroupLayout(layout)
    if type(layout) ~= "table" then return false end
    if YUI.IsForever == true then
        if layout.handPairMode ~= "stacked" and layout.handPairMode ~= "split" then return false end
        for _, key in ipairs({ "mainHandFillDirection", "offHandFillDirection" }) do
            if layout[key] ~= "forward" and layout[key] ~= "reverse" then return false end
        end
    elseif layout.handPairMode ~= nil or layout.mainHandFillDirection ~= nil
        or layout.offHandFillDirection ~= nil then
        return false
    end
    if layout.widthMode ~= "auto" and layout.widthMode ~= "fixed" then
        return false
    end
    if type(layout.width) ~= "number" or layout.width % 1 ~= 0
        or layout.width < 48 or layout.width > 640 then
        return false
    end
    if type(layout.minWidth) ~= "number" or layout.minWidth % 1 ~= 0
        or layout.minWidth < 48 or layout.minWidth > 640 then
        return false
    end
    if type(layout.height) ~= "number" or layout.height % 1 ~= 0
        or layout.height < 8 or layout.height > 160 then
        return false
    end
    if type(layout.spacing) ~= "number" or layout.spacing % 1 ~= 0
        or layout.spacing < -12 or layout.spacing > 32 then
        return false
    end
    if layout.alignment ~= "start" and layout.alignment ~= "center"
        and layout.alignment ~= "end" then
        return false
    end
    if layout.direction ~= "right" and layout.direction ~= "left"
        and layout.direction ~= "down" and layout.direction ~= "up" then
        return false
    end
    if layout.orientation ~= "horizontal"
        and layout.orientation ~= "vertical" then
        return false
    end
    return layout.fillDirection == "forward"
        or layout.fillDirection == "reverse"
end

local function ValidateResourceGroupStyle(style)
    if type(style) ~= "table" then return false end
    if type(style.border) ~= "number" or style.border % 1 ~= 0
        or style.border < 0 or style.border > 12 then
        return false
    end
    if not ValidateStatusBarTexture(style.fillTexture) then
        return false
    end
    if style.fillColorMode ~= "resource"
        and style.fillColorMode ~= "custom" then
        return false
    end
    if not ValidateFontChoice(style.textFont) then
        return false
    end
    if type(style.textSize) ~= "number" or style.textSize % 1 ~= 0
        or style.textSize < 8 or style.textSize > 32 then
        return false
    end
    if style.textOutline ~= "none"
        and style.textOutline ~= "outline"
        and style.textOutline ~= "thick"
        and style.textOutline ~= "shadow"
        and style.textOutline ~= "outlineShadow" then
        return false
    end
    return ValidateUnitColor(style.textColor)
        and ValidateUnitColor(style.backgroundColor)
        and ValidateUnitColor(style.borderColor)
        and ValidateUnitColor(style.fillColor)
end

local function ValidateResourceTextOverride(override)
    if type(override) ~= "table" then return override == nil end
    return ValidateFontChoice(override.textFont)
        and type(override.textSize) == "number"
        and override.textSize % 1 == 0
        and override.textSize >= 8
        and override.textSize <= 32
        and (override.textOutline == "none"
            or override.textOutline == "outline"
            or override.textOutline == "thick"
            or override.textOutline == "shadow"
            or override.textOutline == "outlineShadow")
        and ValidateUnitColor(override.textColor)
end

local function ValidateResourceAppearanceOverride(override)
    if type(override) ~= "table" then return override == nil end
    return type(override.border) == "number"
        and override.border % 1 == 0
        and override.border >= 0
        and override.border <= 12
        and ValidateStatusBarTexture(override.fillTexture)
        and ValidateUnitColor(override.borderColor)
        and ValidateUnitColor(override.backgroundColor)
end

local function ValidateResourceThresholds(thresholds, valueMode)
    if type(thresholds) ~= "table" then return false end
    local maximum = valueMode and 1000000000 or 100
    local low = thresholds.low
    local high = thresholds.high
    if type(low) ~= "table" or type(high) ~= "table" then return false end
    local function ValidThreshold(value)
        return type(value) == "table"
            and type(value.enabled) == "boolean"
            and type(value.value) == "number"
            and value.value % 1 == 0
            and value.value >= 0
            and value.value <= maximum
            and ValidateUnitColor(value.color)
    end
    return ValidThreshold(low)
        and ValidThreshold(high)
        and low.value < high.value
end

local function ValidateResourceSettings(profile, groupId)
    if groupId == nil and type(profile.resources.byGroup) == "table" then
        for id, group in pairs(profile.groups.items) do
            if group.layout == "resource" and type(profile.resources.byGroup[id]) ~= "table" then return false end
        end
        for id, config in pairs(profile.resources.byGroup) do
            local group = profile.groups.items[id]
            if not group or group.layout ~= "resource" or type(config) ~= "table"
                or not ValidateResourceSettings(profile, id) then return false end
            local selectionDefault = id == YHUD.GROUP_IDS.RESOURCES and "catalog" or "none"
            if config.selectionDefault ~= selectionDefault then return false end
        end
        return true
    end
    local resources = YHUD:GetResourceConfig(profile, groupId)
    local settings = type(resources) == "table"
        and resources.settingsByResource or nil
    if type(settings) ~= "table" then return false end
    local Catalog = YHUD.ResourceCatalog
    if not (Catalog and Catalog.GetDefinition) then
        return next(settings) == nil
    end
    for resourceId, setting in pairs(settings) do
        if resourceId == "cast" then
            local cast = type(setting) == "table" and setting.cast
            if type(cast) ~= "table" or type(cast.icon) ~= "boolean" or type(cast.name) ~= "boolean"
                or type(cast.progress) ~= "boolean" or (cast.idle ~= "reserve" and cast.idle ~= "collapse")
                or (cast.iconSide ~= "left" and cast.iconSide ~= "right")
                or type(cast.iconGap) ~= "number" or cast.iconGap < 0 or cast.iconGap > 12 or cast.iconGap % 1 ~= 0 then return false end
            if cast.namePosition ~= "start" and cast.namePosition ~= "center" and cast.namePosition ~= "end" then return false end
            for _, key in ipairs({ "nameSize", "progressSize" }) do
                local value = cast[key]
                if value ~= nil and (type(value) ~= "number" or value < 8
                    or value > 32 or value % 1 ~= 0) then return false end
            end
            for _, key in ipairs({ "nameOffsetX", "nameOffsetY" }) do
                local value = cast[key]
                if type(value) ~= "number" or value < -64 or value > 64 or value % 1 ~= 0 then return false end
            end
        end
        local definition = Catalog:GetDefinition(resourceId)
        if not definition or type(setting) ~= "table"
            or (setting.visibilityMode ~= "always"
                and setting.visibilityMode ~= "nonzero"
                and setting.visibilityMode ~= "nonzeroOrCombat")
            or type(setting.valueText) ~= "boolean"
            or (setting.textPosition ~= "start"
                and setting.textPosition ~= "center"
                and setting.textPosition ~= "end")
            or type(setting.textOffsetX) ~= "number"
            or setting.textOffsetX % 1 ~= 0
            or setting.textOffsetX < -64
            or setting.textOffsetX > 64
            or type(setting.textOffsetY) ~= "number"
            or setting.textOffsetY % 1 ~= 0
            or setting.textOffsetY < -64
            or setting.textOffsetY > 64
            or (setting.heightOverride ~= nil
                and (type(setting.heightOverride) ~= "number"
                    or setting.heightOverride % 1 ~= 0
                    or setting.heightOverride < 1
                    or setting.heightOverride > 160))
            or not ValidateUnitColor(setting.fillColor)
            or type(setting.segmentSpacing) ~= "number"
            or setting.segmentSpacing % 1 ~= 0
            or setting.segmentSpacing < -5
            or setting.segmentSpacing > 32
            or type(setting.dividerThickness) ~= "number"
            or setting.dividerThickness % 1 ~= 0
            or setting.dividerThickness < 1
            or setting.dividerThickness > 4
            or not ValidateUnitColor(setting.dividerColor)
            or type(setting.thresholdColorEnabled) ~= "boolean"
            or (setting.inverseFill ~= nil and type(setting.inverseFill) ~= "boolean")
            or type(setting.thresholdMarkerEnabled) ~= "boolean"
            or not ValidateResourceThresholds(
                setting.thresholds,
                setting.thresholdMode == "value" and definition.valueKind ~= "discrete"
            )
            or not ValidateUnitColor(setting.thresholdMarkerColor)
            or type(setting.thresholdMarkerThickness) ~= "number"
            or setting.thresholdMarkerThickness % 1 ~= 0
            or setting.thresholdMarkerThickness < 1
            or setting.thresholdMarkerThickness > 4
            or not ValidateResourceTextOverride(setting.textOverride)
            or not ValidateResourceAppearanceOverride(
                setting.appearanceOverride
            ) then
            return false
        end
        local second = setting.text2
        if type(second) ~= "table" or type(second.valueText) ~= "boolean"
            or (second.textPosition ~= "start" and second.textPosition ~= "center" and second.textPosition ~= "end") then return false end
        for _, key in ipairs({ "textOffsetX", "textOffsetY" }) do
            local value = second[key]
            if type(value) ~= "number" or value % 1 ~= 0 or value < -64 or value > 64 then return false end
        end
        local normalizedSecond = YHUD:NormalizeResourceTextSetting(second, resourceId)
        if second.valueFormat ~= normalizedSecond.valueFormat then return false end
        if setting.abbreviateValues ~= nil and type(setting.abbreviateValues) ~= "boolean" then return false end
        if setting.thresholdMode ~= "value" and setting.thresholdMode ~= "percent" then return false end
        if setting.fillCeilingPercent ~= nil and (definition.appearanceExtension ~= "severity"
            or type(setting.fillCeilingPercent) ~= "number" or setting.fillCeilingPercent % 1 ~= 0
            or setting.fillCeilingPercent < 1 or setting.fillCeilingPercent > 500) then return false end
        if not YHUD:IsResourceThresholdModeSelectable(definition)
            and setting.thresholdMode ~= (definition.valueKind == "discrete" and "value" or "percent") then
            return false
        end
        if type(setting.thresholdValues) ~= "table" then return false end
        for _, mode in ipairs({ "percent", "value" }) do
            local saved = setting.thresholdValues[mode]
            local maximum = mode == "value" and 1000000000 or 100
            if type(saved) ~= "table" or type(saved.low) ~= "number" or type(saved.high) ~= "number"
                or saved.low % 1 ~= 0 or saved.high % 1 ~= 0 or saved.low < 0
                or saved.high > maximum or saved.low >= saved.high then return false end
        end
        if setting.runeCooldownTextMode ~= nil
            and setting.runeCooldownTextMode ~= "all"
            and setting.runeCooldownTextMode ~= "none"
            and setting.runeCooldownTextMode ~= "shortest" then return false end
        if definition.valueKind == "discrete" then
            if (setting.valueFormat ~= "value" and setting.valueFormat ~= "valueMax"
                and setting.valueFormat ~= "whole")
                or (setting.displayMode ~= "bar"
                    and setting.displayMode ~= "divided"
                    and setting.displayMode ~= "cells"
                    and setting.displayMode ~= "dots") then
                return false
            end
        elseif setting.valueFormat ~= "percent"
            and setting.valueFormat ~= "percentSign"
            and setting.valueFormat ~= "value"
            and setting.valueFormat ~= "valuePercent"
            and setting.valueFormat ~= "percentValue"
            and setting.valueFormat ~= "valuePercentParen"
            and setting.valueFormat ~= "valueMax"
            and setting.valueFormat ~= "duration" then
            return false
        elseif setting.displayMode ~= "bar" then
            return false
        end
    end
    return true
end

local GROUP_PLACEMENT_POINTS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local function ValidateBasicGroupPlacement(placement)
    local anchor = type(placement) == "table" and placement.anchor or nil
    local offset = type(placement) == "table" and placement.offset or nil
    return placement and placement.version == 2
        and type(anchor) == "table"
        and GROUP_PLACEMENT_POINTS[anchor.point] == true
        and GROUP_PLACEMENT_POINTS[anchor.relativePoint] == true
        and type(anchor.relative) == "string"
        and anchor.relative ~= ""
        and type(offset) == "table"
        and type(offset.x) == "number" and offset.x % 1 == 0
        and offset.x >= -2000 and offset.x <= 2000
        and type(offset.y) == "number" and offset.y % 1 == 0
        and offset.y >= -2000 and offset.y <= 2000
end

local function ValidateGroupPlacement(placement)
    return ValidateBasicGroupPlacement(placement)
        and (placement.fallback == nil
            or ValidateBasicGroupPlacement(placement.fallback))
end

function ProfileModel:Validate(profile)
    if type(profile) ~= "table"
        or type(profile.entries) ~= "table"
        or type(profile.monitors) ~= "table"
        or type(profile.groups) ~= "table"
        or type(profile.groups.order) ~= "table"
        or type(profile.groups.items) ~= "table"
        or type(profile.layout) ~= "table"
        or type(profile.layout.groups) ~= "table"
        or type(profile.layout.placements) ~= "table"
        or type(profile.style) ~= "table"
        or type(profile.style.groups) ~= "table" then
        return nil, "invalid-profile"
    end
    if type(profile.cdm) ~= "table"
        or type(profile.cdm.skillAuraDisplay) ~= "boolean"
        or type(profile.cdm.skillAuraHighlight) ~= "boolean"
        or type(profile.cdm.inactiveDesaturate) ~= "boolean" then
        return nil, "invalid-skill-aura-display"
    end
    if not ValidateNativeProcGlow(profile.style.nativeProcGlow) then
        return nil, "invalid-native-proc-glow"
    end

    local seenGroups = {}
    for groupId, placement in pairs(profile.layout.placements) do
        if profile.groups.items[groupId] == nil
            or not ValidateGroupPlacement(placement) then
            return nil, "invalid-group-placement"
        end
    end
    for index = 1, #profile.groups.order do
        local groupId = profile.groups.order[index]
        local group = profile.groups.items[groupId]
        if not group or seenGroups[groupId] then
            return nil, "invalid-group-order"
        end
        seenGroups[groupId] = true
        if group.id ~= groupId or group.order ~= index then
            return nil, "invalid-group-order"
        end
        if not LAYOUT_VIEWS[group.layout]
            or (group.layoutMode ~= "auto" and group.layoutMode ~= "fixed")
            or type(group.displayLayer) ~= "number"
            or group.displayLayer % 1 ~= 0
            or group.displayLayer < 1 or group.displayLayer > 10
            or type(group.monitors) ~= "table"
            or type(group.officialCategories) ~= "table"
            or type(group.showUnavailablePreview) ~= "boolean"
            or type(group.showTooltip) ~= "boolean" then
            return nil, "invalid-group"
        end
        local policyId, policy = YHUD:GetGroupContentPolicy(group)
        if group.contentPolicy ~= policyId
            or not policy
            or not policy.layouts[group.layout] then
            return nil, "invalid-content-policy"
        end
        if group.layout == "icons"
            and not ValidateIconGroupLayout(
                profile.layout.groups[groupId]
            ) then
            return nil, "invalid-group-layout"
        end
        if group.layout == "icons"
            and not ValidateIconGroupStyle(
                profile.style.groups[groupId]
            ) then
            return nil, "invalid-group-style"
        end
        if (group.layout == "bars" or group.layout == "rings")
            and not ValidateDurationGroupLayout(
                profile.layout.groups[groupId],
                group.layout
            ) then
            return nil, "invalid-group-layout"
        end
        if (group.layout == "bars" or group.layout == "rings")
            and not ValidateDurationGroupStyle(
                profile.style.groups[groupId]
            ) then
            return nil, "invalid-group-style"
        end
        if group.layout == "resource"
            and not ValidateResourceGroupLayout(
                profile.layout.groups[groupId]
            ) then
            return nil, "invalid-group-layout"
        end
        if group.layout == "resource"
            and not ValidateResourceGroupStyle(
                profile.style.groups[groupId]
            ) then
            return nil, "invalid-group-style"
        end
        if group.fixedEnabled and group.enabled ~= true then
            return nil, "fixed-enabled"
        end
    end
    for groupId in pairs(profile.groups.items) do
        if not seenGroups[groupId] then return nil, "invalid-group-order" end
    end
    if not ValidateResourceSettings(profile) then
        return nil, "invalid-resource-settings"
    end

    for groupId, group in pairs(profile.groups.items) do
        local seenCategories = {}
        local expectedCategory = YHUD:GetDefaultGroupSyncCategory(groupId)
        for index = 1, #group.officialCategories do
            local category = group.officialCategories[index]
            if seenCategories[category] or category ~= expectedCategory then
                return nil, "category-sync-mismatch"
            end
            seenCategories[category] = true
        end
        if expectedCategory
            and (group.syncCategory ~= expectedCategory
                or not seenCategories[expectedCategory]) then
            return nil, "category-sync-mismatch"
        end
        if not expectedCategory
            and (group.syncCategory ~= nil
                or #group.officialCategories > 0) then
            return nil, "category-sync-mismatch"
        end
    end

    local listedMonitors = {}
    local listedEntries = {}
    local listedSemanticIdentities = {}
    for groupId, group in pairs(profile.groups.items) do
        for index = 1, #group.monitors do
            local monitorId = group.monitors[index]
            local monitor = profile.monitors[monitorId]
            if not monitor or listedMonitors[monitorId] then
                return nil, "orphan-monitor"
            end
            listedMonitors[monitorId] = true
            if monitor.id ~= monitorId
                or monitor.groupId ~= groupId
                or monitor.order ~= index then
                return nil, "invalid-monitor-order"
            end
            local entry = profile.entries[monitor.entryKey]
            if not entry then return nil, "entry-not-found" end
            if listedEntries[monitor.entryKey] then
                return nil, "entry-already-placed"
            end
            listedEntries[monitor.entryKey] = monitorId
            local semanticIdentity = YHUD:GetEntrySemanticIdentity(
                entry,
                monitor.entryKey
            )
            if not semanticIdentity then
                return nil, "invalid-semantic-identity"
            end
            if listedSemanticIdentities[semanticIdentity] then
                return nil, "semantic-identity-exists"
            end
            listedSemanticIdentities[semanticIdentity] = monitorId
            if monitor.sourceKey ~= entry.sourceKey then
                return nil, "source-key-mismatch"
            end
            if monitor.officialCategory ~= nil then
                if not CATEGORY_LAYOUTS[monitor.officialCategory]
                    or (entry.officialCategory
                        and entry.officialCategory
                            ~= monitor.officialCategory) then
                    return nil, "monitor-category-mismatch"
                end
            end
            local placed, code = CheckPlacement(entry, group, monitor.view)
            if not placed then return nil, code end
            if not ValidateMonitorGlow(profile, monitor, monitor.glow) then
                return nil, "invalid-monitor-glow"
            end
            if not ValidateMonitorSound(profile, monitor, monitor.sound) then
                return nil, "invalid-monitor-sound"
            end
            if monitor.nativeProcGlowOverride ~= nil
                and not ValidateNativeProcGlow(
                    monitor.nativeProcGlowOverride
                ) then
                return nil, "invalid-native-proc-glow"
            end
            if monitor.stateEffects ~= nil then
                if type(monitor.stateEffects) ~= "table"
                    or monitor.skillAuraDisplayOverride ~= nil then
                    return nil, "invalid-monitor-state-effects"
                end
                local normalized = YHUD:NormalizeMonitorStateEffects(
                    monitor.stateEffects,
                    entry
                )
                if normalized == nil then
                    return nil, "invalid-monitor-state-effects"
                end
                for key, value in pairs(monitor.stateEffects) do
                    if normalized[key] ~= value then
                        return nil, "invalid-monitor-state-effects"
                    end
                end
                for key, value in pairs(normalized) do
                    if monitor.stateEffects[key] ~= value then
                        return nil, "invalid-monitor-state-effects"
                    end
                end
            elseif monitor.skillAuraDisplayOverride ~= nil then
                return nil, "invalid-monitor-state-effects"
            end
            if monitor.appearanceOverride ~= nil then
                if group.layout ~= "icons" and group.layout ~= "bars"
                    and group.layout ~= "rings" then
                    return nil, "invalid-monitor-appearance"
                end
                local appearance = monitor.appearanceOverride
                local normalized =
                    YHUD:NormalizeMonitorAppearanceOverride(appearance)
                if not normalized then
                    return nil, "invalid-monitor-appearance"
                end
                for key, value in pairs(appearance) do
                    local valid = group.layout == "icons"
                        and key == "cooldownSwipeMode"
                        and (value == "disabled" or value == "forward"
                            or value == "reverse")
                        or (group.layout == "bars" or group.layout == "rings")
                            and (key == "fillColor" or key == "trackColor")
                            and ValidateUnitColor(value)
                        or group.layout == "bars" and key == "stackThresholds"
                            and type(value) == "table"
                            and ValuesEqual(value, normalized.stackThresholds)
                    if not valid or normalized[key] == nil then
                        return nil, "invalid-monitor-appearance"
                    end
                end
                for key in pairs(normalized) do
                    if appearance[key] == nil then
                        return nil, "invalid-monitor-appearance"
                    end
                end
            end
        end
    end
    for monitorId in pairs(profile.monitors) do
        if not listedMonitors[monitorId] then return nil, "orphan-monitor" end
    end
    return true
end

function ProfileModel:ValidateCanonical(profile)
    profile = YHUD:GetCanonicalProfile(profile)
    if type(profile) ~= "table"
        or type(profile.contentBySpec) ~= "table" then
        return nil, "invalid-profile"
    end
    for specKey, content in pairs(profile.contentBySpec) do
        if not YHUD:IsStableSpecKey(specKey) or type(content) ~= "table" then
            return nil, "invalid-spec-key"
        end
        local scoped, code = YHUD:GetScopedProfile(profile, specKey, false)
        if not scoped then return nil, code end
        local valid
        valid, code = self:Validate(scoped)
        if not valid then return nil, code end
    end
    return true
end

function ProfileModel:CommitDraft(draft)
    local profile, summary = self:PrepareDraft(draft)
    if not profile then return nil, summary end
    draft.closed = true
    return profile, summary
end

local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local LayoutBridge = YHUD.LayoutBridge or {}
YHUD.LayoutBridge = LayoutBridge

local GROUP_LAYOUT_PREFIX = "yui.product.yhud.group."
local PROJECTION_LAYOUT_PREFIX = "yui.product.yhud.projection."

LayoutBridge.registeredGroups = LayoutBridge.registeredGroups or {}
LayoutBridge.designProjectionGroups = LayoutBridge.designProjectionGroups or {}
LayoutBridge.editGroups = LayoutBridge.editGroups or {}
LayoutBridge.anchorProviders = LayoutBridge.anchorProviders or {}
LayoutBridge.appliedPlacements = nil

local DEFAULT_TITLES = {
    [YHUD.GROUP_IDS and YHUD.GROUP_IDS.IMPORTANT] = "YHUD 重要技能",
    [YHUD.GROUP_IDS and YHUD.GROUP_IDS.UTILITY] = "YHUD 效能技能",
    [YHUD.GROUP_IDS and YHUD.GROUP_IDS.BUFF] = "YHUD 增益效果",
    [YHUD.GROUP_IDS and YHUD.GROUP_IDS.BAR] = "YHUD 状态栏",
    [YHUD.GROUP_IDS and YHUD.GROUP_IDS.RESOURCES] = "YHUD 资源条",
    [YHUD.GROUP_IDS and YHUD.GROUP_IDS.TRINKETS] = "YHUD 饰品",
}

local SUPPORTED_LAYOUTS = {
    icons = true,
    bars = true,
    rings = true,
    resource = true,
}

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

local function GetLayoutId(groupId)
    if YHUD.GROUP_IDS
        and groupId == YHUD.GROUP_IDS.TRINKETS
        and YHUD.LAYOUT_TRINKETS_ID then
        return YHUD.LAYOUT_TRINKETS_ID
    end
    return GROUP_LAYOUT_PREFIX .. tostring(groupId)
end

local function IsYHUDLayoutId(id)
    return id == YHUD.LAYOUT_TRINKETS_ID
        or (type(id) == "string" and id:sub(1, #GROUP_LAYOUT_PREFIX) == GROUP_LAYOUT_PREFIX)
        or (type(id) == "string" and id:sub(1, #PROJECTION_LAYOUT_PREFIX) == PROJECTION_LAYOUT_PREFIX)
end

local function BuildDefaultPlacement(group)
    local order = type(group) == "table" and tonumber(group.order) or 6
    if type(group) == "table" and group.kind == "user" then
        return {
            version = 2,
            anchor = {
                point = "CENTER",
                relative = "UIParent",
                relativePoint = "CENTER",
            },
            offset = {
                x = 0,
                y = 0,
            },
        }
    end
    return {
        version = 2,
        anchor = {
            point = "BOTTOM",
            relative = "UIParent",
            relativePoint = "BOTTOM",
        },
        offset = {
            x = 0,
            y = 220 + (6 - (order or 6)) * 54,
        },
    }
end

local function GetGroupTitle(groupId, group)
    local fallback = DEFAULT_TITLES[groupId]
        or (type(group) == "table" and group.name)
        or ("YHUD " .. tostring(groupId))
    if type(group) == "table" and type(group.name) == "string" and group.name ~= "" then
        return group.name
    end
    if type(group) == "table" and type(group.nameKey) == "string" then
        return YHUD:T(group.nameKey, fallback)
    end
    return fallback
end

local function GetGroupFrameName(groupId)
    if YHUD.GROUP_IDS and groupId == YHUD.GROUP_IDS.TRINKETS then
        return "YUI_YHUD_TrinketGroup"
    end
    return "YUI_YHUD_Group_" .. tostring(groupId):gsub("[^%w_]", "_")
end

local function GetLayoutProfileOwner(profile)
    if profile and profile == YHUD._initialResourceProfile then
        return YHUD._initialResourceProfileCanonical or profile
    end
    if profile and profile == YHUD._runtimeProfile then
        return YHUD._runtimeProfileCanonical or profile
    end
    return (YHUD.GetCanonicalProfile and YHUD:GetCanonicalProfile(profile))
        or profile
end

-- Declare absent runtime groups before placing their dependents. Core Layout
-- owns guarded history and fallback; a design preview is never real geometry.
function LayoutBridge:SyncAnchorProviders(profile)
    local Layout = YUI.Layout
    if not (Layout and Layout.RegisterAnchorProvider) then return end
    local canonical = GetLayoutProfileOwner(profile)
    local groups = canonical and canonical.groups and canonical.groups.items or {}
    local runtimeGroups = profile and profile.groups and profile.groups.items or {}
    local profileChanged = self.anchorProfile ~= profile
    self.anchorProfile = profile
    for groupId, group in pairs(groups) do
        local state = self.anchorProviders[groupId]
        local runtimeGroup = runtimeGroups[groupId]
        local enabled = runtimeGroup ~= nil and runtimeGroup.enabled == true
            and SUPPORTED_LAYOUTS[runtimeGroup.layout] == true
        if not state then
            state = { name = GetGroupFrameName(groupId), enabled = enabled }
            self.anchorProviders[groupId] = state
            Layout:RegisterAnchorProvider(GetLayoutId(groupId), {
                name = state.name,
                getState = function() return state.enabled and "enabled" or "disabled" end,
            })
        elseif state.enabled ~= enabled or profileChanged then
            state.enabled = enabled
            Layout:InvalidateAnchorProvider(GetLayoutId(groupId))
        end
        state.title = GetGroupTitle(groupId, group)
    end
    for groupId, state in pairs(self.anchorProviders) do
        if not groups[groupId] then
            if state.enabled ~= false then
                state.enabled = false
                Layout:InvalidateAnchorProvider(GetLayoutId(groupId))
            end
            if profile and Layout.UnregisterAnchorProvider
                and Layout:UnregisterAnchorProvider(GetLayoutId(groupId)) then
                self.anchorProviders[groupId] = nil
            end
        end
    end
end

local function CreateProjectionStorage(placement)
    local storage = { value = placement }
    function storage:get() return self.value end
    function storage:set(_, value) self.value = value; return true end
    function storage:clear() self.value = nil; return true end
    function storage:identity() return self end
    return storage
end

local function BuildAnchorTargets(includeGroups)
    local Layout = YUI.Layout
    local targets = {}
    if includeGroups ~= false then
        for _, state in pairs(LayoutBridge.anchorProviders) do
            targets[#targets + 1] = { name = state.name, label = state.title }
        end
    end
    for id, entry in pairs(Layout and Layout.frames or {}) do
        if not IsYHUDLayoutId(id) and type(entry) == "table" then
            local spec = entry.spec
            local frame = entry.frame or (type(spec) == "table" and spec.frame)
            if frame then
                local title = type(spec) == "table" and spec.title
                targets[#targets + 1] = {
                    frame = frame,
                    label = type(title) == "string" and title or id,
                }
            end
        end
    end
    table.sort(targets, function(left, right)
        return tostring(left.label) < tostring(right.label)
    end)
    return targets
end

local function SetNativeBridgeLayoutPreview(enabled)
    local NativeBridge = YHUD.NativeBridge
    if not (NativeBridge and NativeBridge.active) then
        return false
    end
    local method = enabled and NativeBridge.EnterLayoutPreview
        or NativeBridge.ExitLayoutPreview
    if method then return method(NativeBridge) end
    if NativeBridge.Sync then
        local View = YHUD.View
        return NativeBridge:Sync(
            View and View.profile or nil,
            enabled and "layout-edit-enter" or "layout-edit-exit"
        )
    end
    return false
end

local function GetDisplayedProfile()
    local View = YHUD.View
    if View and type(View.profile) == "table" then
        return View.profile
    end
    if YHUD.GetActiveProfile then
        local profile = YHUD:GetActiveProfile(false)
        if type(profile) == "table" then return profile end
    end
    return YHUD.GetConfigProfile and YHUD:GetConfigProfile() or nil
end

local function BuildEffectiveProfilePlacements(profile)
    local groups = profile and profile.groups and profile.groups.items or {}
    local stored = profile and profile.layout and profile.layout.placements or {}
    stored = YHUD:NormalizeGroupPlacements(stored, groups)
    local effective = {}
    for groupId, group in pairs(groups) do
        effective[groupId] = stored[groupId] or BuildDefaultPlacement(group)
    end
    return effective, groups
end

local function TranslateProjectionPlacement(placement, names)
    local copy = YHUD:CopyValue(placement)
    local current = copy
    while type(current) == "table" do
        local anchor = current.anchor
        if anchor and names and names[anchor.relative] then
            anchor.relative = names[anchor.relative]
        end
        current = current.fallback
    end
    return copy
end

local function RefreshProjectionPlacement(self, groupId, placement)
    local projection = self.designProjectionGroups[groupId]
    local Layout = YUI.Layout
    if not (projection and Layout and Layout.SetPlacement) then return false end
    placement = TranslateProjectionPlacement(placement, projection.anchorNames)
    if Layout.GetPlacement
        and ValuesEqual(Layout:GetPlacement(projection.layoutId), placement) then
        return false
    end
    return Layout:SetPlacement(projection.layoutId, placement, true)
end

function LayoutBridge:CaptureProfilePlacements(profile)
    local Layout = YUI.Layout
    if not Layout then return nil, "layout-unavailable" end
    profile = profile or GetDisplayedProfile()
    if type(profile) ~= "table" then return nil, "profile-unavailable" end
    local groups = profile.groups and profile.groups.items or {}
    local storedPlacements = profile.layout and profile.layout.placements
    local placements = {}
    local readable = {}
    local private = Layout._private
    for groupId, group in pairs(groups) do
        local current = self.registeredGroups[groupId]
        local layoutId = current and current.layoutId or GetLayoutId(groupId)
        local placement
        if current and Layout.GetPlacement then
            placement = Layout:GetPlacement(layoutId)
            if type(placement) == "table" then readable[groupId] = true end
        end
        if type(placement) ~= "table"
            and private and private.GetSavedPlacement then
            placement = private.GetSavedPlacement(layoutId)
            if type(placement) == "table" then readable[groupId] = true end
        end
        if type(placement) ~= "table"
            and type(storedPlacements) == "table" then
            placement = storedPlacements[groupId]
        end
        if type(placement) ~= "table" then
            placement = BuildDefaultPlacement(group)
        end
        placements[groupId] = placement
    end
    return YHUD:NormalizeGroupPlacements(placements, groups), readable
end

function LayoutBridge:ApplyProfilePlacements(profile, force)
    local Layout = YUI.Layout
    if not Layout then return false end
    local effective, groups = BuildEffectiveProfilePlacements(profile)
    local owner = GetLayoutProfileOwner(GetDisplayedProfile() or profile)
    local sameOwner = self.appliedPlacementOwner == owner
    if sameOwner and Layout.GetPlacementState and Layout.GetPlacement then
        for groupId, current in pairs(self.registeredGroups) do
            local requested = effective[groupId]
            if requested and Layout:GetPlacementState(current.layoutId) == "fallback" then
                local live = Layout:GetPlacement(current.layoutId)
                -- Keep updated screen history only for the same request and
                -- runtime owner. A new scheme or draft placement must win.
                if type(live) == "table" and ValuesEqual(live.anchor, requested.anchor)
                    and ValuesEqual(live.offset, requested.offset) then
                    effective[groupId] = live
                end
            end
        end
    end
    if force ~= true and sameOwner and self.appliedPlacements
        and ValuesEqual(self.appliedPlacements, effective) then
        return false
    end

    local private = Layout._private
    if private and private.SavePlacement then
        for groupId, current in pairs(self.registeredGroups) do
            if groups[groupId] == nil and not current.designProjection then
                private.SavePlacement(current.layoutId, nil)
            end
        end
    end
    for groupId, placement in pairs(effective) do
        local current = self.registeredGroups[groupId]
        local layoutId = current and current.layoutId or GetLayoutId(groupId)
        if current and current.designProjection and Layout.SetPlacement then
            Layout:SetPlacement(layoutId, placement, true)
        elseif private and private.SavePlacement then
            private.SavePlacement(layoutId, placement)
        end
        if current and not current.designProjection then
            local entry = Layout.frames and Layout.frames[layoutId]
            if private and private.ApplyPlacement and entry then
                private.ApplyPlacement(entry, placement, true, { replaceRequest = not sameOwner })
            elseif Layout.SetPlacement then
                Layout:SetPlacement(layoutId, placement, true)
            end
        end
        if not (YHUD.View and YHUD.View.designMode) then
            RefreshProjectionPlacement(self, groupId, placement)
        end
    end
    self.appliedPlacements = YHUD:CopyValue(effective)
    self.appliedPlacementOwner = owner
    return true
end

local function RecordPlacementCommitFailure(groupId, code, detail)
    local Diagnostics = YHUD.Diagnostics
    if Diagnostics and Diagnostics.Record then
        Diagnostics:Record(
            "layout-placement-commit",
            tostring(groupId) .. ":" .. tostring(detail or code)
        )
    end
end

function LayoutBridge:OnGroupPlacementCommitted(groupId, placement, reason)
    if type(groupId) ~= "string" or type(placement) ~= "table" then
        return false, "invalid-placement"
    end

    local Designer = YHUD.Designer
    local stored, changed, detail
    local editingDraft = Designer
        and Designer.IsOpen
        and Designer:IsOpen() == true
    if editingDraft then
        local profile = Designer:GetProfile()
        local current = profile and profile.layout
            and profile.layout.placements or {}
        local placements = YHUD:CopyValue(current)
        placements[groupId] = placement
        stored, changed = Designer:SetGroupPlacements(placements)
    else
        local ConfigSets = YHUD.ConfigSets
        if not (ConfigSets and ConfigSets.PatchActiveGroupPlacement) then
            RecordPlacementCommitFailure(
                groupId,
                "config-sets-service-unavailable"
            )
            return false, "config-sets-service-unavailable"
        end
        stored, changed, detail = ConfigSets:PatchActiveGroupPlacement(
            groupId,
            placement,
            "layout-placement-" .. tostring(reason or "commit"),
            YHUD
        )
    end

    if type(stored) ~= "table" then
        RecordPlacementCommitFailure(groupId, changed, detail)
        return false, changed, detail
    end
    local committed = editingDraft and stored[groupId] or stored
    if type(committed) ~= "table" then
        RecordPlacementCommitFailure(groupId, "invalid-placement-result")
        return false, "invalid-placement-result"
    end
    RefreshProjectionPlacement(self, groupId, committed)
    if not editingDraft and self.appliedPlacements and type(committed) == "table" then
        self.appliedPlacements[groupId] = YHUD:CopyValue(committed)
    end
    return true, changed
end

-- Dynamic groups retain a scene, not a guessed cold size. Validate its owner
-- without activating the product, migrating DB data, or creating monitors.
local function CaptureGroupAnchorGuard(groupId, designProjection)
    if designProjection then return function() return false end end
    local profile = YUI.DB and YUI.DB.GetProfile and YUI.DB:GetProfile()
    local db = profile and profile[YHUD.STORAGE_KEY or "YHUD"]
    local canonical = db and db.profile
    local groups = canonical and canonical.groups and canonical.groups.items
    local group = groups and groups[groupId]
    if not group or not YHUD.CopyValue then return function() return false end end
    local snapshot = YHUD:CopyValue(group)
    snapshot.enabled = nil
    local layout = YHUD:CopyValue(canonical.layout)
    local spec = YHUD.GetCurrentSpecKey and YHUD:GetCurrentSpecKey()
    return function()
        local currentProfile = YUI.DB and YUI.DB.GetProfile and YUI.DB:GetProfile()
        local currentDB = currentProfile and currentProfile[YHUD.STORAGE_KEY or "YHUD"]
        if not currentDB or currentDB.profile ~= canonical then return false end
        if YHUD.GetCurrentSpecKey and YHUD:GetCurrentSpecKey() ~= spec then return false end
        local current = canonical.groups and canonical.groups.items and canonical.groups.items[groupId]
        if not current or not ValuesEqual(canonical.layout, layout) then return false end
        for key, value in pairs(current) do
            if key ~= "enabled" and not ValuesEqual(value, snapshot[key]) then return false end
        end
        for key, value in pairs(snapshot) do
            if not ValuesEqual(value, current[key]) then return false end
        end
        return true
    end
end

function LayoutBridge:RegisterGroup(groupId, group, frame, designProjection)
    local Layout = YUI.Layout
    if not (Layout and Layout.RegisterFrame and frame) then return false end
    designProjection = designProjection == true
    local layoutId = designProjection and (PROJECTION_LAYOUT_PREFIX .. tostring(groupId))
        or GetLayoutId(groupId)
    local current = self.registeredGroups[groupId]
    local title = GetGroupTitle(groupId, group)
    if current and current.frame == frame and current.layoutId == layoutId
        and (current.designProjection == true) == designProjection then
        if current.title == title and current.exactMoverBounds == true then
            local enabled = group.enabled == true
            if current.enabled ~= enabled
                and Layout.SetAnchorTargetAvailable then
                local transitioned = Layout:SetAnchorTargetAvailable(
                    layoutId,
                    enabled
                )
                if not transitioned then return false end
            end
            current.enabled = enabled
            return true
        end
    elseif current then
        self:UnregisterGroup(groupId)
    end

    local storage = designProjection and CreateProjectionStorage(BuildDefaultPlacement(group)) or nil
    local entry = Layout:RegisterFrame(layoutId, {
        frame = frame,
        captureAnchorSnapshotGuard = function()
            return CaptureGroupAnchorGuard(groupId, designProjection)
        end,
        title = title,
        category = "product",
        editModeFilterGroup = "monitor.cooldown",
        defaultPlacement = BuildDefaultPlacement(group),
        placementStorage = storage,
        movable = true,
        snap = true,
        pixelAlignOrigin = true,
        anchorTargets = BuildAnchorTargets,
        combatProtected = false,
        minWidth = 42,
        minHeight = 42,
        exactMoverBounds = true,
        getMoverBounds = function()
            if YHUD.View and YHUD.View.GetGroupMoverBounds then
                return YHUD.View:GetGroupMoverBounds(groupId)
            end
            return nil
        end,
        isEditModeEnabled = function() return LayoutBridge.designLayoutProjection == nil end,
        isEnabled = function()
            if not YHUD:IsEnabled() then return false end
            local Designer = YHUD.Designer
            local profile = designProjection
                and Designer and Designer.GetProfile
                and Designer:GetProfile() or GetDisplayedProfile()
            local currentGroup = profile
                and profile.groups
                and profile.groups.items
                and profile.groups.items[groupId]
            return currentGroup ~= nil
                and currentGroup.enabled == true
                and SUPPORTED_LAYOUTS[currentGroup.layout] == true
        end,
        openPluginSettings = function()
            return YHUD:OpenSettings()
        end,
        onPlacementCommitted = function(_, placement, _, _, reason)
            return LayoutBridge:OnGroupPlacementCommitted(
                groupId,
                placement,
                reason
            )
        end,
        onEnterEditMode = function()
            if LayoutBridge.editGroups[groupId] then return end
            LayoutBridge.editGroups[groupId] = true
            local View = YHUD.View
            if View then
                local wasLayoutEditing = View.layoutEditMode == true
                if not wasLayoutEditing then
                    local changed = false
                    if View.SetLayoutEditMode then
                        changed = View:SetLayoutEditMode(true, true) == true
                            or changed
                    end
                    changed = View:SetPreview(true, true) == true or changed
                    SetNativeBridgeLayoutPreview(true)
                    if View.RefreshLayoutPreview then
                        View:RefreshLayoutPreview(true)
                    elseif changed and View.RefreshAll then
                        View:RefreshAll()
                    end
                end
            end
        end,
        onExitEditMode = function()
            LayoutBridge.editGroups[groupId] = nil
            if next(LayoutBridge.editGroups) then return end
            local View = YHUD.View
            if View then
                local wasLayoutEditing = View.layoutEditMode == true
                local changed = View:SetPreview(false, true) == true
                if not wasLayoutEditing then return end
                if View.SetLayoutEditMode then
                    changed = View:SetLayoutEditMode(false, true) == true or changed
                end
                SetNativeBridgeLayoutPreview(false)
                if View.RefreshLayoutPreview then
                    View:RefreshLayoutPreview(false)
                elseif changed and View.RefreshAll then
                    View:RefreshAll()
                end
                local Sources = YHUD.Sources
                if Sources and Sources.active and Sources.Refresh then
                    Sources:Refresh("layout-edit-exit", true)
                end
            end
        end,
    })
    if not entry then return false end
    self.registeredGroups[groupId] = {
        layoutId = layoutId,
        frame = frame,
        title = title,
        exactMoverBounds = true,
        enabled = group.enabled == true,
        designProjection = designProjection,
        storage = storage,
    }
    self.registered = true
    return true
end

function LayoutBridge:RegisterDesignProjectionGroup(
    groupId,
    group,
    frame,
    placement,
    projection
)
    local Layout = YUI.Layout
    if not (Layout and Layout.RegisterFrame and frame) then return false end
    local previous = self.designProjectionGroups[groupId]
    if previous and previous.frame ~= frame then
        self:UnregisterDesignProjectionGroup(groupId, previous.frame)
        previous = nil
    end
    local current = self.registeredGroups[groupId]
    placement = placement
        or (current and Layout.GetPlacement and Layout:GetPlacement(current.layoutId))
        or BuildDefaultPlacement(group)
    local title = GetGroupTitle(groupId, group)
    local state = previous or {
        -- A pooled frame keeps its identity when it represents another group.
        -- Layout's retained anchor definitions must follow that same identity.
        layoutId = PROJECTION_LAYOUT_PREFIX .. tostring(frame.GetName and frame:GetName() or groupId),
        frame = frame,
        storage = CreateProjectionStorage(),
    }
    state.projection = projection
    state.anchorNames = projection and projection.anchorNames
    local value = TranslateProjectionPlacement(placement, state.anchorNames)
    if previous and state.title == title and state.enabled == group.enabled then
        return Layout:SetPlacement(state.layoutId, value, true)
    end
    state.storage.value = value
    state.title, state.enabled = title, group.enabled
    local entry = Layout:RegisterFrame(state.layoutId, {
        frame = frame,
        title = title,
        category = "product",
        editModeFilterGroup = "monitor.cooldown",
        captureAnchorSnapshotGuard = function() return function() return false end end,
        defaultPlacement = TranslateProjectionPlacement(BuildDefaultPlacement(group), state.anchorNames),
        placementStorage = state.storage,
        anchorTargets = function()
            local targets = BuildAnchorTargets(false)
            local names = state.anchorNames or {}
            local groups = state.projection and state.projection.profile.groups.items or {}
            for id, item in pairs(groups) do
                targets[#targets + 1] = {
                    name = names[GetGroupFrameName(id)],
                    label = GetGroupTitle(id, item),
                }
            end
            return targets
        end,
        pixelAlignOrigin = true,
        combatProtected = false,
        movable = function() return state.projection ~= nil
            and YHUD.View and YHUD.View.designMode == true
            and YHUD.View.designProjection == state.projection end,
        isEditModeEnabled = function() return state.projection ~= nil
            and LayoutBridge.designLayoutProjection == state.projection end,
        exactMoverBounds = true,
        getMoverBounds = function()
            return YHUD.View:GetGroupMoverBounds(groupId, true)
        end,
        isEnabled = group.enabled == true,
        onPlacementCommitted = function(_, value, _, _, reason)
            return LayoutBridge:OnGroupPlacementCommitted(groupId,
                TranslateProjectionPlacement(value, state.projection and state.projection.logicalAnchorNames), reason)
        end,
    })
    if not entry then return false end
    self.designProjectionGroups[groupId] = state
    return true
end

function LayoutBridge:BeginGroupDrag(groupId, frame)
    local state = self.designProjectionGroups[groupId]
    local Layout = YUI.Layout
    if not (state and state.frame == frame and state.projection
        and YHUD.View and YHUD.View.designProjection == state.projection
        and Layout and Layout.BeginDirectDrag and Layout.EndDirectDrag)
        or self.dragGroupId then return false end
    if not Layout:BeginDirectDrag(state.layoutId, { snap = false }) then return false end
    self.dragGroupId, self.dragGroupFrame = groupId, frame
    return true
end

function LayoutBridge:EndGroupDrag(groupId, frame, cancel)
    if self.dragGroupId ~= groupId or self.dragGroupFrame ~= frame then return false end
    self.dragGroupId, self.dragGroupFrame = nil, nil
    local Layout = YUI.Layout
    return Layout and Layout.EndDirectDrag and Layout:EndDirectDrag(cancel == true) or false
end

function LayoutBridge:SyncDesignProjection(projection)
    local Layout = YUI.Layout
    if not (projection and Layout and Layout.SetPlacement) then return false end
    local groups = projection.profile.groups.items
    local names, logicalNames = {}, {}
    for groupId in pairs(groups) do
        local runtime = projection.groups[groupId]
        local name = runtime and runtime.frame:GetName()
            or ("YUI_YHUD_DesignPending_" .. tostring(groupId):gsub("[^%w_]", "_"))
        local logicalName = GetGroupFrameName(groupId)
        names[logicalName], logicalNames[name] = name, logicalName
    end
    projection.anchorNames, projection.logicalAnchorNames = names, logicalNames
    local placements = projection.profile.layout and projection.profile.layout.placements or {}
    local byName, resolved, visiting = {}, {}, {}
    for groupId in pairs(groups) do byName[GetGroupFrameName(groupId)] = groupId end
    local function Apply(groupId)
        if resolved[groupId] then return true end
        if visiting[groupId] then return false end
        local runtime = projection.groups[groupId]
        if not runtime then return true end
        visiting[groupId] = true
        local placement = placements[groupId]
        local target = placement and placement.anchor and byName[placement.anchor.relative]
        if target and not Apply(target) then return false end
        -- Resolve targets first: screen clamping must use their final geometry.
        if not self:RegisterDesignProjectionGroup(groupId, runtime.group, runtime.frame, placement, projection) then
            return false
        end
        visiting[groupId], resolved[groupId] = nil, true
        return true
    end
    for groupId in pairs(projection.groups) do
        if not Apply(groupId) then return false end
    end
    return true
end

function LayoutBridge:BeginDesignLayout(projection)
    local Layout = YUI.Layout
    if not (projection and Layout and not Layout:IsEditing()) then return false end
    self.designLayoutProjection = projection
    if not self:SyncDesignProjection(projection) then
        self.designLayoutProjection = nil
        return false
    end
    YHUD.View:SetDesignLayoutMode(true)
    return true
end

function LayoutBridge:EndDesignLayout(closeEditor)
    if not self.designLayoutProjection then return false end
    if closeEditor and YUI.Layout and YUI.Layout:IsEditing() then
        YUI.Layout:CloseEditMode()
    end
    self.designLayoutProjection = nil
    if YHUD.View then YHUD.View:SetDesignLayoutMode(false) end
    return true
end

function LayoutBridge:UnregisterDesignProjectionGroup(groupId, frame)
    local projection = self.designProjectionGroups[groupId]
    if projection and (not frame or projection.frame == frame) then
        self:EndGroupDrag(groupId, projection.frame, true)
        local Layout = YUI.Layout
        if Layout and Layout.UnregisterFrame then
            Layout:UnregisterFrame(projection.layoutId)
        end
        projection.projection = nil
        projection.anchorNames = nil
        self.designProjectionGroups[groupId] = nil
        return true
    end
    local current = self.registeredGroups[groupId]
    if not (current and current.designProjection == true) then return false end
    if frame and current.frame ~= frame then return false end
    return self:UnregisterGroup(groupId)
end

function LayoutBridge:PrepareProfileTransition(profile)
    self:SyncAnchorProviders(profile)
    local Layout = YUI.Layout
    if not (Layout and Layout.SetAnchorTargetAvailable) then return true end
    local groups = profile and profile.groups and profile.groups.items or {}
    for groupId, current in pairs(self.registeredGroups) do
        local nextGroup = groups[groupId]
        local nextEnabled = nextGroup
            and nextGroup.enabled == true
            and SUPPORTED_LAYOUTS[nextGroup.layout] == true
        if current.enabled == true and not nextEnabled then
            local transitioned, code = Layout:SetAnchorTargetAvailable(
                current.layoutId,
                false
            )
            if not transitioned then return false, code end
            current.enabled = false
        end
    end
    return true
end

function LayoutBridge:FinalizeProfileTransition(profile)
    return self:Sync(profile)
end

function LayoutBridge:RefreshPixelAlignedPlacements(groupId)
    local Layout = YUI.Layout
    local current = groupId and self.registeredGroups[groupId]
    if current and Layout and Layout.RefreshPixelAlignedFrame then
        return Layout:RefreshPixelAlignedFrame(current.layoutId) > 0
    end
    if not (Layout and Layout.RefreshPixelAlignedFrames) then return false end
    return Layout:RefreshPixelAlignedFrames() > 0
end

function LayoutBridge:RefreshPixelAlignedPlacementsIfNeeded(groupId)
    local Layout = YUI.Layout
    local current = groupId and self.registeredGroups[groupId]
    if current and Layout and Layout.RefreshPixelAlignedFrameIfNeeded then
        local visited, applied, unavailable =
            Layout:RefreshPixelAlignedFrameIfNeeded(current.layoutId)
        return tonumber(visited) or 0,
            tonumber(applied) or 0,
            tonumber(unavailable) or 0,
            false
    end

    if current and Layout and Layout.RefreshPixelAlignedFrame then
        local refreshed = tonumber(
            Layout:RefreshPixelAlignedFrame(current.layoutId)
        ) or 0
        return refreshed, refreshed, refreshed, false
    end
    if not (Layout and Layout.RefreshPixelAlignedFrames) then
        return 0, 0, 1, true
    end
    local refreshed = tonumber(Layout:RefreshPixelAlignedFrames()) or 0
    return refreshed, refreshed, refreshed, true
end

function LayoutBridge:UnregisterGroup(groupId)
    local projection = self.designProjectionGroups[groupId]
    if projection then
        self:UnregisterDesignProjectionGroup(groupId, projection.frame)
    end
    local current = self.registeredGroups[groupId]
    if not current then return false end
    if YUI.Layout and YUI.Layout.UnregisterFrame then
        YUI.Layout:UnregisterFrame(current.layoutId)
    end
    self.registeredGroups[groupId] = nil
    self.registered = next(self.registeredGroups) ~= nil
    return true
end

function LayoutBridge:Sync(profile)
    local Layout = YUI.Layout
    local View = YHUD.View
    if not (Layout and Layout.RegisterFrame and View and View.GetGroupFrames) then
        return false
    end
    profile = profile or (YHUD.GetConfigProfile and YHUD:GetConfigProfile())
    if type(profile) ~= "table" then return false end

    -- Sync can receive the Designer's viewed specialization when opening the
    -- position editor. Only the actual View owns runtime target availability.
    self:SyncAnchorProviders(type(View.profile) == "table" and View.profile or profile)
    self:ApplyProfilePlacements(profile)

    local frames = View:GetGroupFrames({}, true)
    local groups = profile.groups and profile.groups.items or {}
    local desired = {}
    for groupId, frame in pairs(frames) do
        local group = groups[groupId]
        if group
            and group.enabled ~= true
            and SUPPORTED_LAYOUTS[group.layout] == true then
            desired[groupId] = true
            self:RegisterGroup(groupId, group, frame)
        end
    end
    for groupId, frame in pairs(frames) do
        local group = groups[groupId]
        if group
            and group.enabled == true
            and SUPPORTED_LAYOUTS[group.layout] == true then
            desired[groupId] = true
            self:RegisterGroup(groupId, group, frame)
        end
    end

    local stale = {}
    for groupId in pairs(self.registeredGroups) do
        if not desired[groupId] then
            stale[#stale + 1] = groupId
        end
    end
    for index = 1, #stale do
        self:UnregisterGroup(stale[index])
    end
    self.registered = next(self.registeredGroups) ~= nil
    return self.registered
end

function LayoutBridge:Register()
    return self:Sync()
end

function LayoutBridge:Open(source)
    local Layout = YUI.Layout
    if not (Layout and Layout.OpenEditMode) then return false end
    return Layout:OpenEditMode(source or "yhud-settings")
end

function LayoutBridge:CommitGroupPosition(groupId, sourceFrame)
    local Layout = YUI.Layout
    local projection = self.designProjectionGroups[groupId]
    local current = projection and projection.frame == sourceFrame and projection
        or self.registeredGroups[groupId]
    if not (current and Layout and Layout.CommitFramePosition) then
        return false
    end
    local committed = Layout:CommitFramePosition(
        current.layoutId,
        sourceFrame or current.frame,
        "frame-drag"
    )
    if committed and projection and projection.frame == sourceFrame
        and Layout.GetPlacement then
        local placement = Layout:GetPlacement(current.layoutId)
        if placement then
            RefreshProjectionPlacement(self, groupId, placement)
        end
    end
    return committed
end

function LayoutBridge:ResetGroupPosition(groupId, group)
    local Layout = YUI.Layout
    local current = self.registeredGroups[groupId]
    if not current then
        local View = YHUD.View
        local frame = View and View.GetGroupFrame
            and View:GetGroupFrame(groupId)
        if not group then
            local profile = View and View.profile
            group = profile and profile.groups
                and profile.groups.items[groupId]
        end
        if frame and group then
            self:RegisterGroup(groupId, group, frame)
            current = self.registeredGroups[groupId]
        end
    end
    if not (current and Layout and Layout.ResetFrame) then
        return false
    end
    return Layout:ResetFrame(current.layoutId, "reset")
end

function LayoutBridge:CapturePlacements(profile)
    local Layout = YUI.Layout
    if not (Layout and Layout.GetPlacement) then return {} end
    local snapshot = {}
    profile = profile or (YHUD.GetConfigProfile and YHUD:GetConfigProfile())
    local groups = profile and profile.groups and profile.groups.items or {}
    for groupId, group in pairs(groups) do
        local current = self.registeredGroups[groupId]
        local layoutId = current and current.layoutId or GetLayoutId(groupId)
        local savedPlacement = current and current.storage and current.storage.value
            or (Layout._private
            and Layout._private.GetSavedPlacement
            and Layout._private.GetSavedPlacement(layoutId))
        local placement = current
            and Layout:GetPlacement(layoutId)
            or savedPlacement
            or (profile.layout and profile.layout.placements and profile.layout.placements[groupId])
            or BuildDefaultPlacement(group)
        snapshot[groupId] = {
            layoutId = layoutId,
            hasSavedPlacement = savedPlacement ~= nil,
            placement = placement,
        }
    end
    return snapshot
end

function LayoutBridge:HasPlacementChanges(snapshot)
    local Layout = YUI.Layout
    if type(snapshot) ~= "table"
        or not (Layout and Layout.GetPlacement) then
        return false
    end
    for groupId, saved in pairs(snapshot) do
        local current = self.registeredGroups[groupId]
        if current and current.layoutId == saved.layoutId then
            local placement = Layout:GetPlacement(current.layoutId)
            if not ValuesEqual(placement, saved.placement) then return true end
        end
    end
    return false
end

function LayoutBridge:RestorePlacements(snapshot, profile)
    local Layout = YUI.Layout
    if type(snapshot) ~= "table"
        or not (Layout and Layout.SetPlacement) then
        return false
    end
    local restored = false
    local restoredPlacements = {}
    for groupId, saved in pairs(snapshot) do
        local current = self.registeredGroups[groupId]
        local private = Layout._private
        local temporary = type(saved.layoutId) == "string"
            and saved.layoutId:sub(1, #PROJECTION_LAYOUT_PREFIX) == PROJECTION_LAYOUT_PREFIX
        if type(saved.placement) == "table" then
            restoredPlacements[groupId] = saved.placement
            if current and current.storage and current.layoutId == saved.layoutId then
                restored = Layout:SetPlacement(current.layoutId, saved.placement, true) == true or restored
            elseif not temporary and private and private.SavePlacement then
                private.SavePlacement(
                    saved.layoutId,
                    saved.hasSavedPlacement and saved.placement or nil
                )
                restored = true
            end
            if current and not current.storage and current.layoutId == saved.layoutId then
                local entry = Layout.frames and Layout.frames[current.layoutId]
                if private and private.ApplyPlacement and entry then
                    private.ApplyPlacement(entry, saved.placement, true, { replaceRequest = true })
                    restored = true
                else
                    local applied = Layout:SetPlacement(
                        current.layoutId,
                        saved.placement,
                        true
                    )
                    if applied and not saved.hasSavedPlacement
                        and private and private.SavePlacement then
                        private.SavePlacement(current.layoutId, nil)
                    end
                    restored = applied == true or restored
                end
            end
        end
    end
    local private = Layout._private
    if private and private.SavePlacement then
        for groupId, current in pairs(self.registeredGroups) do
            if not snapshot[groupId] and not current.storage then
                private.SavePlacement(current.layoutId, nil)
                restored = true
            end
        end
    end
    self.appliedPlacements = YHUD:CopyValue(restoredPlacements)
    self.appliedPlacementOwner = GetLayoutProfileOwner(profile or GetDisplayedProfile())
    return restored
end

function LayoutBridge:Unregister()
    self:EndDesignLayout(true)
    local projectionIds = {}
    for groupId in pairs(self.designProjectionGroups) do projectionIds[#projectionIds + 1] = groupId end
    for _, groupId in ipairs(projectionIds) do self:UnregisterDesignProjectionGroup(groupId) end
    self:SyncAnchorProviders(nil)
    local groupIds = {}
    for groupId in pairs(self.registeredGroups) do
        groupIds[#groupIds + 1] = groupId
    end
    for index = 1, #groupIds do
        self:UnregisterGroup(groupIds[index])
    end
    self.registered = false
    self.appliedPlacements = nil
    self.appliedPlacementOwner = nil
end

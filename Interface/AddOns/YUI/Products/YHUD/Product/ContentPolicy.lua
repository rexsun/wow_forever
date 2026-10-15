local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

YHUD.CONTENT_POLICY_REVISION = 18

function YHUD:CanConfigureSkillAuraDisplay(entry)
    return type(entry) == "table"
        and entry.origin == "official-cdm"
        and (entry.officialCategory == "essential"
            or entry.officialCategory == "utility")
        and entry.canUseAuraForCooldown == true
end

function YHUD:GetEffectiveSkillAuraDisplay(profile, monitor, entry)
    if not self:CanConfigureSkillAuraDisplay(entry) then return true end
    local override
    if type(monitor) == "table" then
        local effects = type(monitor.stateEffects) == "table"
            and monitor.stateEffects or nil
        override = effects and effects.auraTimer
        if override == nil then
            override = monitor.skillAuraDisplayOverride
        end
    end
    if type(override) == "boolean" then return override end
    local cdm = type(profile) == "table" and profile.cdm or nil
    return not (type(cdm) == "table" and cdm.skillAuraDisplay == false)
end
YHUD.NATIVE_SEED_VERSION = 2
YHUD.CONTENT_SCOPE_SHARED = "shared"
YHUD.CONTENT_SCOPE_SPEC = "spec"
YHUD.CONTENT_LANE_BEFORE = "before"
YHUD.CONTENT_LANE_SPEC = "spec"
YHUD.CONTENT_LANE_AFTER = "after"
YHUD.CAST_BUFF_TIMER_SOURCE_TYPE = "yhud.cast-buff-timer"
YHUD.SPELL_EVENT_WINDOW_SOURCE_TYPE = "yhud.spell-event-window"
YHUD.PLAYER_AURA_SOURCE_TYPE = "yhud.player-aura"
YHUD.RUNTIME_CHANNEL_TIMED_SOURCE = "timed-source"
YHUD.RUNTIME_CHANNEL_NATIVE_OFFICIAL = "native-official"
YHUD.RUNTIME_CHANNEL_PREVIEW_ONLY = "preview-only"

local CROSS_SPEC_DISPLAY_FIELDS = {
    visibilityMode = true,
    stateEffects = true,
    appearanceOverride = true,
    glow = true,
    nativeProcGlowOverride = true,
}

local CROSS_SPEC_SOUND_FIELDS = {
    sound = true,
}

local function PositiveInteger(value)
    value = tonumber(value)
    if not value or value <= 0 or value >= math.huge then return nil end
    value = math.floor(value)
    return value > 0 and value or nil
end

function YHUD:GetEntrySemanticIdentity(entry, entryKey)
    if type(entry) ~= "table" then return nil end
    entryKey = type(entryKey) == "string" and entryKey
        or (type(entry.entryKey) == "string" and entry.entryKey or nil)

    if entry.origin == "official-cdm" then
        return entryKey and ("official:" .. entryKey) or nil
    end

    local presetKey = entry.presetKey or entry.presetId
    if entry.origin == "preset" or presetKey ~= nil then
        presetKey = type(presetKey) == "string" and presetKey or entryKey
        return presetKey and ("preset:" .. presetKey) or nil
    end

    local sourceType = type(entry.sourceType) == "string"
        and entry.sourceType or "unknown"
    local spellID = PositiveInteger(entry.spellId)
        or PositiveInteger(entry.spellID)
        or PositiveInteger(entry.runtimeSpellId)
    if spellID
        and sourceType == self.PLAYER_AURA_SOURCE_TYPE
        and entry.origin == "custom"
        and (entry.filteredAuraScope == self.FILTERED_AURA_SCOPE_PLAYER_HELPFUL
            or entry.filteredAuraScope
                == self.FILTERED_AURA_SCOPE_TARGET_HARMFUL) then
        return sourceType .. ":" .. entry.filteredAuraScope
            .. ":spell:" .. tostring(spellID)
    end
    if spellID then
        return sourceType .. ":spell:" .. tostring(spellID)
    end
    local itemID = PositiveInteger(entry.itemId)
        or PositiveInteger(entry.itemID)
    if itemID then
        return sourceType .. ":item:" .. tostring(itemID)
    end
    local slotID = PositiveInteger(entry.slotId)
        or PositiveInteger(entry.equipSlot)
    if slotID then
        return sourceType .. ":slot:" .. tostring(slotID)
    end
    local sourceIdentity = type(entry.sourceIdentity) == "string"
        and entry.sourceIdentity or nil
    if sourceIdentity then
        return sourceType .. ":identity:" .. sourceIdentity
    end
    return entryKey and (sourceType .. ":entry:" .. entryKey) or nil
end

function YHUD:GetMonitorSemanticIdentity(profile, monitor)
    if type(profile) ~= "table" or type(monitor) ~= "table" then return nil end
    local entries = profile.entries
    local entry = type(entries) == "table" and entries[monitor.entryKey] or nil
    return self:GetEntrySemanticIdentity(entry, monitor.entryKey)
end

function YHUD:GetCrossSpecFieldWhitelist(kind)
    if kind == "display" then return CROSS_SPEC_DISPLAY_FIELDS end
    if kind == "sound" then return CROSS_SPEC_SOUND_FIELDS end
    return nil
end

local CONSUMABLE_PRESET_ITEMS = {
    [5512] = true, [224464] = true,
    [241304] = true, [241305] = true, [241300] = true, [241301] = true,
    [271884] = true, [271883] = true,
    [241308] = true, [241309] = true, [245898] = true, [245897] = true,
    [241288] = true, [241289] = true, [245902] = true, [245903] = true,
    [271887] = true, [271886] = true, [274764] = true, [274763] = true,
    [241302] = true, [241303] = true,
}

-- Fill missing metadata at creation and load time; preserve explicit policies.
function YHUD:RepairConsumablePresetReplication(entry, entryKey)
    if type(entry) ~= "table" or entry.origin ~= "preset"
        or entry.crossSpecMaterialization ~= nil
        or entry.materializationMode ~= nil then return end
    local supported = entry.sourceType == "item-cooldown"
        and CONSUMABLE_PRESET_ITEMS[entry.itemId] == true
    if entry.sourceType == self.CAST_BUFF_TIMER_SOURCE_TYPE then
        local identity = entry.sourceIdentity or entryKey
        supported = identity == "buff-timer:burst-potion"
            or identity == "buff-timer:invis-potion"
    end
    if not supported then return end
    entry.presetKey = entry.presetKey or entry.presetId or entryKey
    entry.crossSpecMaterialization = "immediate"
end

function YHUD:RepairAmmoPresetReplication(entry)
    if YUI.IsForever ~= true or type(entry) ~= "table"
        or entry.sourceType ~= "yhud.ammo-count" or entry.origin ~= "preset" then return end
    if entry.crossSpecMaterialization == nil and entry.materializationMode == nil then
        entry.crossSpecMaterialization = "immediate"
    end
    if entry.crossSpecEligibility == nil then
        entry.crossSpecEligibility = { classFile = "HUNTER" }
    end
end

function YHUD:CanCrossSpecOperate(operation, entry, runtimeSpecKey, viewSpecKey)
    if type(operation) ~= "string" or type(entry) ~= "table" then
        return nil, "cross-spec-policy-denied"
    end
    if entry.origin == "official-cdm" then
        return nil, "native-read-only"
    end
    if operation == "copy" or operation == "sync-display"
        or operation == "sync-sound" then
        if entry.origin == "preset" then
            local materialization = entry.crossSpecMaterialization
                or entry.materializationMode
            if materialization ~= "immediate"
                and materialization ~= "deferred" then
                return nil, "preset-cross-spec-unregistered"
            end
        end
        return true
    end
    if operation == "edit" or operation == "move"
        or operation == "reorder" or operation == "delete" then
        return true
    end
    return nil, "cross-spec-policy-denied"
end

function YHUD:CanMaterializePresetForSpec(entry, specKey)
    if type(entry) == "table" and entry.sourceType == "yhud.ammo-count"
        and (YUI.IsForever ~= true or type(specKey) ~= "string"
            or specKey:match("^HUNTER:") == nil) then
        return nil, "preset-not-applicable"
    end
    if type(entry) ~= "table" or entry.origin ~= "preset" then return true end
    if type(specKey) ~= "string" then return nil, "invalid-spec-key" end
    local mode = entry.crossSpecMaterialization or entry.materializationMode
    if mode ~= "immediate" and mode ~= "deferred" then
        return nil, "preset-cross-spec-unregistered"
    end
    local eligibility = entry.crossSpecEligibility
    if type(eligibility) ~= "table" then return true, mode end
    local classFile, specID = specKey:match("^([^:]+):([1-9][0-9]*)$")
    if eligibility.classFile and eligibility.classFile ~= classFile then
        return nil, "preset-not-applicable"
    end
    if type(eligibility.specKeys) == "table"
        and eligibility.specKeys[specKey] ~= true then
        return nil, "preset-not-applicable"
    end
    if type(eligibility.specIDs) == "table"
        and eligibility.specIDs[tonumber(specID)] ~= true then
        return nil, "preset-not-applicable"
    end
    return true, mode
end

local FILTERED_AURA_EXCLUDED_RUNTIME_CHANNELS = {
    [YHUD.RUNTIME_CHANNEL_TIMED_SOURCE] = true,
    [YHUD.RUNTIME_CHANNEL_NATIVE_OFFICIAL] = true,
    [YHUD.RUNTIME_CHANNEL_PREVIEW_ONLY] = true,
}

function YHUD:CanUseFilteredAuraDisplay()
    local Unit = YUI.API and YUI.API.Unit
    return Unit and Unit.SupportsFilteredAuraDisplay
        and Unit.SupportsFilteredAuraDisplay() == true
end

function YHUD:IsFilteredAuraEntry(entry)
    return type(entry) == "table"
        and entry.sourceType == self.PLAYER_AURA_SOURCE_TYPE
        and entry.origin ~= "official-cdm"
        and entry.sourceIdentity ~= "bloodlust-heroism"
end

function YHUD:IsLogicalEquipmentAuraParent(entry, monitor)
    return type(entry) == "table"
        and type(monitor) == "table"
        and entry.bundleKind == self.EQUIPMENT_AURA_BUNDLE_KIND
        and entry.bundleEnabled == true
        and monitor._yhudRuntimeChannel == nil
end

function YHUD:IsFilteredAuraMonitor(entry, monitor)
    if type(entry) ~= "table"
        or type(monitor) ~= "table"
        or entry.sourceType ~= self.PLAYER_AURA_SOURCE_TYPE
        or entry.sourceIdentity == "bloodlust-heroism" then
        return false
    end
    if self:IsLogicalEquipmentAuraParent(entry, monitor) then
        return false
    end
    if FILTERED_AURA_EXCLUDED_RUNTIME_CHANNELS[
        monitor._yhudRuntimeChannel
    ] == true then
        return false
    end
    if entry.origin ~= "official-cdm" then return true end
    local displayCategory = entry.displayCategory or entry.officialCategory
    if displayCategory ~= "trackedBuff"
        and displayCategory ~= "trackedBar" then
        return false
    end
    return not self:IsOfficialNativeView(
        displayCategory,
        monitor.view
    )
end

function YHUD:CanUseBarStackThresholds(entry, monitor)
    return type(entry) == "table" and type(monitor) == "table"
        and monitor.view == "bar"
        and entry.sourceType == self.PLAYER_AURA_SOURCE_TYPE
        and entry.sourceIdentity ~= "bloodlust-heroism"
        and not self:IsLogicalEquipmentAuraParent(entry, monitor)
        and FILTERED_AURA_EXCLUDED_RUNTIME_CHANNELS[monitor._yhudRuntimeChannel] ~= true
end

function YHUD:GetOfficialNativeCategoryTarget(entry, monitor)
    if type(entry) ~= "table" or type(monitor) ~= "table"
        or entry.origin ~= "official-cdm"
        or not tonumber(entry.cooldownId) then
        return nil
    end
    local currentCategory = entry.displayCategory
        or entry.officialCategory
    if currentCategory ~= "trackedBuff"
        and currentCategory ~= "trackedBar" then
        return nil
    end
    local target = monitor.view == "icon" and "trackedBuff"
        or (monitor.view == "bar" and "trackedBar" or nil)
    if not target or target == currentCategory then return nil end
    return target
end

function YHUD:IsFilteredAuraLayoutMonitor(entry, monitor, assumeNativeTarget)
    if assumeNativeTarget == true
        and self:GetOfficialNativeCategoryTarget(entry, monitor) then
        return false
    end
    return self:IsFilteredAuraMonitor(entry, monitor)
end

function YHUD:GetOfficialNativeCategoryAssignments(profile)
    if type(profile) ~= "table" then return nil, "invalid-profile" end
    local assignments = {}
    local byCooldownID = {}
    local groups = profile.groups and profile.groups.items or {}
    for _, group in pairs(groups) do
        if type(group) == "table" and group.enabled ~= false then
            for index = 1, #(group.monitors or {}) do
                local monitor = profile.monitors
                    and profile.monitors[group.monitors[index]]
                local entry = monitor and profile.entries
                    and profile.entries[monitor.entryKey]
                local target = monitor and monitor.enabled ~= false
                    and self:GetOfficialNativeCategoryTarget(entry, monitor)
                    or nil
                local cooldownID = target and tonumber(entry.cooldownId) or nil
                if cooldownID then
                    local previous = byCooldownID[cooldownID]
                    if previous and previous ~= target then
                        return nil, "conflicting-native-category-target"
                    end
                    if not previous then
                        byCooldownID[cooldownID] = target
                        assignments[#assignments + 1] = {
                            cooldownID = cooldownID,
                            targetCategory = target,
                            currentCategory = entry.displayCategory
                                or entry.officialCategory,
                        }
                    end
                end
            end
        end
    end
    table.sort(assignments, function(left, right)
        return left.cooldownID < right.cooldownID
    end)
    return assignments
end

YHUD.FILTERED_AURA_LAYOUT_ENGINE_FLOW = "engine-flow"
YHUD.FILTERED_AURA_LAYOUT_MIXED_DYNAMIC_SINGLE_LINE =
    "mixed-dynamic-single-line"
YHUD.FILTERED_AURA_LAYOUT_MIXED_SEGMENTED_OVERFLOW =
    "mixed-segmented-overflow"
YHUD.FILTERED_AURA_LAYOUT_MIXED_FIXED = "mixed-fixed"
YHUD.FILTERED_AURA_FIXED_REASON_UNSUPPORTED_LAYOUT =
    "unsupported-layout"
YHUD.FILTERED_AURA_FIXED_REASON_NON_FLOW_MEMBER =
    "non-flow-member"
YHUD.FILTERED_AURA_FIXED_REASON_PERSISTENT_MEMBER =
    "persistent-member"
YHUD.FILTERED_AURA_FIXED_REASON_SCOPE_MISMATCH =
    "scope-mismatch"
YHUD.FILTERED_AURA_FIXED_REASON_CONFIGURED_LAYOUT =
    "configured-layout"
YHUD.FILTERED_AURA_SCOPE_PLAYER_HELPFUL = "player-helpful"
YHUD.FILTERED_AURA_SCOPE_PLAYER_HELPFUL_CDM_EXTENDED =
    "player-helpful-cdm-extended"
YHUD.FILTERED_AURA_SCOPE_TARGET_HARMFUL = "target-harmful-player"

function YHUD:BuildMonitorLayoutProjectionContext(profile, preview)
    local monitorCatalog = self.MonitorCatalog
    return {
        profile = profile,
        preview = preview == true,
        claimedCooldownSources = monitorCatalog
            and monitorCatalog.GetClaimedCooldownSources
            and monitorCatalog:GetClaimedCooldownSources(profile) or {},
    }
end

local CDM_EXTENDED_PLAYER_AURA_IDENTITIES = {
    [404542] = true,
    [1226662] = true,
}

local function HasCDMExtendedPlayerAuraIdentity(entry)
    if type(entry) ~= "table" or entry.origin ~= "official-cdm" then
        return false
    end
    if CDM_EXTENDED_PLAYER_AURA_IDENTITIES[
        tonumber(entry.spellId)
    ] == true or CDM_EXTENDED_PLAYER_AURA_IDENTITIES[
        tonumber(entry.overrideSpellId)
    ] == true or CDM_EXTENDED_PLAYER_AURA_IDENTITIES[
        tonumber(entry.overrideTooltipSpellId)
    ] == true then
        return true
    end
    for _, values in ipairs({ entry.spellIds, entry.linkedSpellIds }) do
        if type(values) == "table" then
            for index = 1, #values do
                if CDM_EXTENDED_PLAYER_AURA_IDENTITIES[
                    tonumber(values[index])
                ] == true then
                    return true
                end
            end
        end
    end
    return false
end

function YHUD:GetFilteredAuraScopeKey(entry)
    if type(entry) == "table" then
        local explicitScope = entry.filteredAuraScope
        if explicitScope == self.FILTERED_AURA_SCOPE_TARGET_HARMFUL then
            return self.FILTERED_AURA_SCOPE_TARGET_HARMFUL
        end
        if explicitScope == self.FILTERED_AURA_SCOPE_PLAYER_HELPFUL then
            return self.FILTERED_AURA_SCOPE_PLAYER_HELPFUL
        end
    end
    if type(entry) == "table"
        and entry.origin == "official-cdm"
        and entry.hasAura == true
        and entry.selfAura == false
        and entry.canUseAuraForCooldown == true then
        return self.FILTERED_AURA_SCOPE_TARGET_HARMFUL
    end
    if HasCDMExtendedPlayerAuraIdentity(entry) then
        return self.FILTERED_AURA_SCOPE_PLAYER_HELPFUL_CDM_EXTENDED
    end
    return self.FILTERED_AURA_SCOPE_PLAYER_HELPFUL
end

function YHUD:GetFilteredAuraGroupProjectionStrategy(
    profile,
    group,
    assumeNativeTargets,
    projectionContext,
    projectedMembers
)
    if not self:CanUseFilteredAuraDisplay()
        or type(profile) ~= "table"
        or type(group) ~= "table" then
        return nil
    end
    local state = {
        specialCount = 0,
        otherCount = 0,
        potentialCount = 0,
        maxPerLine = 1,
        hasPersistentMember = false,
        hasScopeMismatch = false,
        hasNonFlowMember = false,
    }
    local hasPersistentMember = false
    local scopeKey
    local claimedSources = projectionContext
        and projectionContext.claimedCooldownSources or nil
    if not claimedSources then
        claimedSources = self.MonitorCatalog
            and self.MonitorCatalog.GetClaimedCooldownSources
            and self.MonitorCatalog:GetClaimedCooldownSources(profile) or nil
    end
    if group.layout == "icons" and self.GetIconGroupLayout then
        local layout = self:GetIconGroupLayout(profile, group.id)
        state.maxPerLine = math.max(
            1,
            math.floor(tonumber(layout and layout.maxPerLine) or 1)
        )
    end
    local function Accumulate(candidate, candidateEntry, projectedCount, filtered)
        if candidate and candidateEntry then
            projectedCount = math.max(
                1,
                math.floor(tonumber(projectedCount) or 1)
            )
            state.potentialCount = state.potentialCount + projectedCount
            if filtered == nil then
                filtered = self:IsFilteredAuraLayoutMonitor(
                    candidateEntry,
                    candidate,
                    assumeNativeTargets
                )
            end
            if not filtered then
                state.otherCount = state.otherCount + projectedCount
                local displayCategory = candidateEntry.displayCategory
                    or candidateEntry.officialCategory
                if candidateEntry.origin == "official-cdm"
                    and displayCategory ~= "trackedBuff"
                    and not self:GetOfficialNativeCategoryTarget(
                        candidateEntry,
                        candidate
                    ) then
                    state.hasNonFlowMember = true
                end
            else
                state.specialCount = state.specialCount + projectedCount
                hasPersistentMember = hasPersistentMember
                    or candidate.visibilityMode == "always"
                local candidateScope =
                    self:GetFilteredAuraScopeKey(candidateEntry)
                if scopeKey == nil then
                    scopeKey = candidateScope
                elseif candidateScope ~= scopeKey then
                    state.hasScopeMismatch = true
                end
            end
        end
    end
    if type(projectedMembers) == "table" then
        for index = 1, #projectedMembers do
            local member = projectedMembers[index]
            Accumulate(
                member and member.monitor,
                member and member.entry,
                1,
                member and member.special
            )
        end
    else
        for index = 1, #(group.monitors or {}) do
            local candidate = profile.monitors
                and profile.monitors[group.monitors[index]]
            if candidate and candidate.enabled ~= false then
                local candidateEntry = profile.entries
                    and profile.entries[candidate.entryKey]
                if candidateEntry then
                local projection = self.GetMonitorLayoutProjection
                    and self:GetMonitorLayoutProjection(
                        profile,
                        candidateEntry,
                        candidate,
                        true,
                        claimedSources,
                        projectionContext
                    ) or nil
                local projectedCount = projection and #projection or 1
                    Accumulate(
                        candidate,
                        candidateEntry,
                        projectedCount,
                        nil
                    )
                end
            end
        end
    end
    state.hasPersistentMember = hasPersistentMember
    if state.specialCount == 0 then return nil, nil, state end
    if group.layout ~= "icons" and group.layout ~= "bars" then
        return self.FILTERED_AURA_LAYOUT_MIXED_FIXED,
            self.FILTERED_AURA_FIXED_REASON_UNSUPPORTED_LAYOUT,
            state
    end
    if state.hasNonFlowMember then
        return self.FILTERED_AURA_LAYOUT_MIXED_FIXED,
            self.FILTERED_AURA_FIXED_REASON_NON_FLOW_MEMBER,
            state
    end
    if hasPersistentMember then
        return self.FILTERED_AURA_LAYOUT_MIXED_FIXED,
            self.FILTERED_AURA_FIXED_REASON_PERSISTENT_MEMBER,
            state
    end
    if group.layoutMode == "fixed" then
        return self.FILTERED_AURA_LAYOUT_MIXED_FIXED,
            self.FILTERED_AURA_FIXED_REASON_CONFIGURED_LAYOUT,
            state
    end
    if state.otherCount == 0
        and (group.layout == "icons"
            or state.hasScopeMismatch ~= true) then
        return self.FILTERED_AURA_LAYOUT_ENGINE_FLOW, nil, state
    end
    if group.layout ~= "icons" then
        return self.FILTERED_AURA_LAYOUT_MIXED_FIXED,
            self.FILTERED_AURA_FIXED_REASON_UNSUPPORTED_LAYOUT,
            state
    end
    if state.potentialCount > state.maxPerLine then
        return self.FILTERED_AURA_LAYOUT_MIXED_SEGMENTED_OVERFLOW,
            nil,
            state
    end
    return self.FILTERED_AURA_LAYOUT_MIXED_DYNAMIC_SINGLE_LINE, nil, state
end

function YHUD:GetSpecialMonitorGroupState(
    profile,
    group,
    assumeNativeTargets,
    projectionContext
)
    local strategy, reason, state =
        self:GetFilteredAuraGroupProjectionStrategy(
            profile,
            group,
            assumeNativeTargets,
            projectionContext
        )
    state = state or {
        specialCount = 0,
        otherCount = 0,
        potentialCount = 0,
        maxPerLine = 1,
        hasPersistentMember = false,
        hasScopeMismatch = false,
        hasNonFlowMember = false,
    }
    state.strategy = strategy
    state.reason = reason
    state.segmented = strategy ==
        self.FILTERED_AURA_LAYOUT_MIXED_SEGMENTED_OVERFLOW
    return state
end

function YHUD:GetEffectiveGroupLayoutMode(profile, group, assumeNativeTargets)
    local configuredMode = type(group) == "table"
        and group.layoutMode == "fixed" and "fixed" or "auto"
    local strategy, reason =
        self:GetFilteredAuraGroupProjectionStrategy(
            profile,
            group,
            assumeNativeTargets
        )
    local overrideReason = strategy == self.FILTERED_AURA_LAYOUT_MIXED_FIXED
        and reason ~= self.FILTERED_AURA_FIXED_REASON_CONFIGURED_LAYOUT
        and reason or nil
    return overrideReason and "fixed" or configuredMode,
        configuredMode,
        overrideReason
end

function YHUD:GetFilteredAuraProjectionStrategy(
    profile,
    monitor,
    assumeNativeTargets
)
    if type(profile) ~= "table" or type(monitor) ~= "table" then
        return nil
    end
    local entry = profile.entries and profile.entries[monitor.entryKey]
    if not self:IsFilteredAuraLayoutMonitor(
        entry,
        monitor,
        assumeNativeTargets
    ) then return nil end
    local group = profile.groups and profile.groups.items
        and profile.groups.items[monitor.groupId]
    if type(group) ~= "table" then return nil end
    return self:GetFilteredAuraGroupProjectionStrategy(
        profile,
        group,
        assumeNativeTargets
    )
end

function YHUD:IsFilteredAuraMixedMonitor(profile, monitor)
    local strategy = self:GetFilteredAuraProjectionStrategy(profile, monitor)
    return strategy ~= nil
        and strategy ~= self.FILTERED_AURA_LAYOUT_ENGINE_FLOW
end

local COOLDOWN_MONITOR_CONDITIONS = {
    "self-ready",
    "self-cooldown",
}

local AURA_MONITOR_CONDITIONS = {
    "aura-present",
    "aura-missing",
}

local EVENT_WINDOW_MONITOR_CONDITIONS = {
    "condition-met",
}

local EVENT_WINDOW_SOUND_CONDITIONS = {
    "condition-met",
    "timer-ended",
}

function YHUD:GetEntryMonitorConditionCapabilities(entry, channel)
    if type(entry) ~= "table" then return nil end
    channel = channel == "sound" and "sound" or "glow"
    if channel == "sound" and self.Client and self.Client.soundReminders == false then return nil end
    local officialCooldown = entry.origin == "official-cdm"
        and (entry.officialCategory == "essential"
            or entry.officialCategory == "utility")
        and self:GetEntrySemantic(entry) == "cooldown"
        and type(entry.spellId) == "number"
        and entry.spellId > 0
        and entry.equipSlot == nil
        and entry.itemId == nil
        and entry.itemID == nil
        and entry.slotId == nil
    if entry.sourceType == "spell-cooldown" or officialCooldown then
        return {
            kind = "cooldown",
            conditions = COOLDOWN_MONITOR_CONDITIONS,
            nativeProc = true,
            labelKind = "spell",
        }
    end
    if entry.sourceType == "item-cooldown" then
        return {
            kind = "cooldown",
            conditions = COOLDOWN_MONITOR_CONDITIONS,
            nativeProc = false,
            labelKind = "item",
        }
    end
    if entry.sourceType == self.PLAYER_AURA_SOURCE_TYPE
        and self:GetEntrySemantic(entry) == "buff" then
        if channel == "sound" and entry.origin ~= "official-cdm" then
            return nil
        end
        return {
            kind = "aura",
            conditions = AURA_MONITOR_CONDITIONS,
            nativeProc = false,
            persistent = self:SupportsPersistentDisplay(entry),
            labelKind = "aura",
        }
    end
    if (entry.sourceType == self.SPELL_EVENT_WINDOW_SOURCE_TYPE
            or entry.sourceType == self.CAST_BUFF_TIMER_SOURCE_TYPE)
        and self:GetEntrySemantic(entry) == "buff" then
        return {
            kind = "event-window",
            conditions = channel == "sound"
                and EVENT_WINDOW_SOUND_CONDITIONS
                or EVENT_WINDOW_MONITOR_CONDITIONS,
            nativeProc = false,
            persistent = self:SupportsPersistentDisplay(entry),
            labelKind = "timer",
        }
    end
    return nil
end

function YHUD:GetMonitorConditionCapabilities(profile, monitor, channel)
    if type(profile) ~= "table" or type(monitor) ~= "table" then
        return nil
    end
    local entry = profile.entries and profile.entries[monitor.entryKey]
    return self:GetEntryMonitorConditionCapabilities(entry, channel)
end

function YHUD:IsMonitorConditionSupported(
    profile,
    monitor,
    conditionType,
    channel
)
    local capabilities = self:GetMonitorConditionCapabilities(
        profile,
        monitor,
        channel
    )
    for index = 1, #(capabilities and capabilities.conditions or {}) do
        if capabilities.conditions[index] == conditionType then return true end
    end
    return false
end

function YHUD:GetMonitorGlowCapabilities(profile, monitor)
    return self:GetMonitorConditionCapabilities(profile, monitor, "glow")
end

function YHUD:IsMonitorGlowConditionSupported(profile, monitor, conditionType)
    return self:IsMonitorConditionSupported(
        profile,
        monitor,
        conditionType,
        "glow"
    )
end

function YHUD:GetMonitorSoundCapabilities(profile, monitor)
    return self:GetMonitorConditionCapabilities(profile, monitor, "sound")
end

function YHUD:IsMonitorSoundConditionSupported(profile, monitor, conditionType)
    return self:IsMonitorConditionSupported(
        profile,
        monitor,
        conditionType,
        "sound"
    )
end

function YHUD:InitializeMixedAuraDesaturation(profile, groupId)
    if not self:CanUseFilteredAuraDisplay() then return false end
    local group = profile and profile.groups and profile.groups.items
        and profile.groups.items[groupId]
    if not group then return false end

    local mixed = group.layout ~= "icons" and group.layout ~= "bars"
    local filtered = {}
    for index = 1, #(group.monitors or {}) do
        local monitor = profile.monitors
            and profile.monitors[group.monitors[index]]
        local entry = monitor and profile.entries
            and profile.entries[monitor.entryKey]
        if monitor and monitor.enabled ~= false then
            if self:IsFilteredAuraMonitor(entry, monitor) then
                filtered[#filtered + 1] = monitor
            else
                mixed = true
            end
        end
    end
    if #filtered == 0 or not mixed then return false end

    local changed = false
    for index = 1, #filtered do
        local monitor = filtered[index]
        monitor.stateEffects = type(monitor.stateEffects) == "table"
            and monitor.stateEffects or {}
        if monitor.stateEffects.inactiveDesaturate == nil then
            monitor.stateEffects.inactiveDesaturate = true
            changed = true
        end
    end
    return changed
end

local PERSISTENT_DISPLAY_SOURCE_TYPES = {
    [YHUD.CAST_BUFF_TIMER_SOURCE_TYPE] = true,
    [YHUD.SPELL_EVENT_WINDOW_SOURCE_TYPE] = true,
    [YHUD.PLAYER_AURA_SOURCE_TYPE] = true,
}

function YHUD:SupportsPersistentDisplay(entry)
    if type(entry) ~= "table" or self:GetEntrySemantic(entry) ~= "buff" then
        return false
    end
    if PERSISTENT_DISPLAY_SOURCE_TYPES[entry.sourceType] then return true end
    return entry.origin == "official-cdm"
        and (entry.officialCategory == "trackedBuff"
            or entry.officialCategory == "trackedBar")
end

function YHUD:CanConfigureMonitorStateEffects(entry)
    return self:CanConfigureSkillAuraDisplay(entry)
        or self:SupportsPersistentDisplay(entry)
end

function YHUD:NormalizeMonitorStateEffects(value, entry, legacyAuraTimer)
    if not self:CanConfigureMonitorStateEffects(entry) then return nil end
    value = type(value) == "table" and value or {}
    local effects = {}
    if self:CanConfigureSkillAuraDisplay(entry) then
        local auraTimer = value.auraTimer
        if auraTimer == nil then auraTimer = legacyAuraTimer end
        if type(auraTimer) == "boolean" then effects.auraTimer = auraTimer end
        if type(value.auraHighlight) == "boolean" then
            effects.auraHighlight = value.auraHighlight
        end
    end
    if type(value.inactiveDesaturate) == "boolean" then
        effects.inactiveDesaturate = value.inactiveDesaturate
    end
    return next(effects) and effects or nil
end

function YHUD:GetEffectiveSkillAuraHighlight(profile, monitor, entry)
    if not self:CanConfigureSkillAuraDisplay(entry)
        or not self:GetEffectiveSkillAuraDisplay(profile, monitor, entry) then
        return false
    end
    local effects = type(monitor) == "table"
        and type(monitor.stateEffects) == "table"
        and monitor.stateEffects or nil
    if effects and type(effects.auraHighlight) == "boolean" then
        return effects.auraHighlight
    end
    local cdm = type(profile) == "table" and profile.cdm or nil
    return not (type(cdm) == "table" and cdm.skillAuraHighlight == false)
end

function YHUD:GetEffectiveInactiveDesaturate(profile, monitor, entry)
    if not self:CanConfigureMonitorStateEffects(entry) then return false end
    local effects = type(monitor) == "table"
        and type(monitor.stateEffects) == "table"
        and monitor.stateEffects or nil
    if effects and type(effects.inactiveDesaturate) == "boolean" then
        return effects.inactiveDesaturate
    end
    local cdm = type(profile) == "table" and profile.cdm or nil
    return type(cdm) == "table" and cdm.inactiveDesaturate == true
end

function YHUD:GetEntryPresetLabel(entry)
    if type(entry) ~= "table" then return nil end
    if entry.sourceType == self.SPELL_EVENT_WINDOW_SOURCE_TYPE
        and entry.sourceKey == "spell-event-window:1265982" then return nil end
    local key = type(entry.presetLabelKey) == "string"
        and entry.presetLabelKey ~= "" and entry.presetLabelKey or nil
    local fallback
    local preset = self.BLOOD_BOIL_WINDOW_PRESET
    if type(preset) == "table"
        and entry.sourceType == preset.sourceType
        and entry.sourceKey == preset.sourceKey
        and (entry.presetId == preset.presetId
            or entry.presetKey == preset.presetId) then
        key = key or preset.presetLabelKey
        fallback = preset.fallbackPresetLabel
    end
    if type(key) == "string" and key ~= "" then
        local localized = self:T(key, fallback)
        if type(localized) == "string" and localized ~= "" then
            return localized
        end
    end
    return type(fallback) == "string" and fallback ~= ""
        and fallback or nil
end

local APPLICABILITY_KINDS = {
    all = true,
    class = true,
    race = true,
}

local function ParseSpecKey(specKey)
    if type(specKey) ~= "string" then return nil, nil end
    local classFile, specID = specKey:match(
        "^([A-Z][A-Z0-9_]*):([1-9][0-9]*)$"
    )
    return classFile, tonumber(specID)
end

local function CurrentRaceToken()
    local unitAPI = YUI.API and YUI.API.Unit
    local value = unitAPI and unitAPI.GetRaceToken
        and unitAPI.GetRaceToken("player")
    if type(value) ~= "string" or value == "" then return nil end
    return string.lower(value)
end

local function IsAllContextSource(entry)
    if type(entry) ~= "table" then return false end
    if entry.sourceIdentity == "bloodlust"
        or entry.sourceIdentity == "bloodlust-heroism" then
        return true
    end
    if entry.origin == "preset" and not entry.raceToken then
        return true
    end
    return entry.sourceType == "item-cooldown"
        or entry.sourceType == "yhud.inventory-slot-cooldown"
        or entry.sourceType == YHUD.PLAYER_AURA_SOURCE_TYPE
end

function YHUD:NormalizeApplicability(value, entry, specKey)
    value = type(value) == "table" and value or {}
    local kind = APPLICABILITY_KINDS[value.kind] and value.kind or nil
    if kind == "all" then return { kind = "all" } end
    if kind == "class" then
        local classFile = type(value.classFile) == "string"
            and string.upper(value.classFile) or nil
        if classFile and classFile:match("^[A-Z][A-Z0-9_]*$") then
            return {
                kind = "class",
                classFile = classFile,
            }
        end
    elseif kind == "race" then
        local raceToken = type(value.raceToken) == "string"
            and string.lower(value.raceToken) or nil
        if raceToken and raceToken:match("^[a-z][a-z0-9_]*$") then
            return {
                kind = "race",
                raceToken = raceToken,
            }
        end
    end

    if IsAllContextSource(entry) then return { kind = "all" } end
    if type(entry) == "table" and type(entry.raceToken) == "string"
        and entry.raceToken ~= "" then
        return {
            kind = "race",
            raceToken = string.lower(entry.raceToken),
        }
    end
    local classFile = ParseSpecKey(specKey)
    if classFile then
        return {
            kind = "class",
            classFile = classFile,
        }
    end
    return nil
end

function YHUD:GetContentContext(specKey)
    local classFile, specID = ParseSpecKey(specKey)
    if not classFile then return nil, "invalid-spec-key" end
    return {
        specKey = specKey,
        classFile = classFile,
        specID = specID,
        raceToken = CurrentRaceToken(),
    }
end

function YHUD:QualifySharedEntryKey(baseKey, applicability)
    if type(baseKey) ~= "string" or baseKey == "" then return nil end
    if type(applicability) ~= "table" or applicability.kind == "all" then
        return baseKey
    end
    if applicability.kind == "class"
        and type(applicability.classFile) == "string" then
        local suffix = ":class:" .. applicability.classFile
        return baseKey:sub(-#suffix) == suffix
            and baseKey or (baseKey .. suffix)
    end
    if applicability.kind == "race"
        and type(applicability.raceToken) == "string" then
        local embeddedPrefix = "racial:"
            .. applicability.raceToken
            .. ":"
        if baseKey:sub(1, #embeddedPrefix) == embeddedPrefix then
            return baseKey
        end
        local suffix = ":race:" .. applicability.raceToken
        return baseKey:sub(-#suffix) == suffix
            and baseKey or (baseKey .. suffix)
    end
    return baseKey
end

function YHUD:EvaluateEntryApplicability(entry, specKey, context)
    if type(entry) ~= "table" then return "ineligible" end
    if entry.contentScope ~= self.CONTENT_SCOPE_SHARED then
        return "eligible"
    end
    context = type(context) == "table" and context
        or self:GetContentContext(specKey)
    if type(context) ~= "table" then return "ineligible" end
    local applicability = entry.applicability
    if type(applicability) ~= "table" then return "ineligible" end
    if applicability.kind == "all" then return "eligible" end
    if applicability.kind == "class" then
        return applicability.classFile == context.classFile
            and "eligible" or "ineligible"
    end
    if applicability.kind == "race" then
        return context.raceToken
                and applicability.raceToken == context.raceToken
            and "eligible" or "ineligible"
    end
    return "ineligible"
end

function YHUD:EvaluateEntryAvailability(entry, specKey, context)
    if type(entry) == "table" and entry.sourceType == "yhud.ammo-count"
        and not (self.Ammo and self.Ammo:IsApplicable(specKey)) then
        return "ineligible"
    end
    if self:EvaluateEntryApplicability(entry, specKey, context)
        ~= "eligible" then
        return "ineligible"
    end
    if entry.isKnown == false or entry.unavailable == true then
        return "unavailable"
    end
    local applicability = entry.applicability
    local classOwned = type(applicability) == "table"
        and applicability.kind == "class"
    local spellBound = entry.sourceType == "spell-cooldown"
        or entry.sourceType == self.CAST_BUFF_TIMER_SOURCE_TYPE
    if entry.contentScope == self.CONTENT_SCOPE_SHARED
        and classOwned and spellBound then
        local spellAPI = YUI.API and YUI.API.Spell
        local known = spellAPI and spellAPI.IsKnownOrInSpellBook
            and spellAPI.IsKnownOrInSpellBook(
                tonumber(entry.runtimeSpellId)
                    or tonumber(entry.spellId)
            )
        if known == false then return "unavailable" end
    end
    return "available"
end

local POLICY = {
    ["cooldown-primary"] = {
        semantics = {
            cooldown = true,
            buff = true,
        },
        layouts = {
            icons = true,
        },
        addCooldown = true,
        addBuff = true,
    },
    ["cooldown-only"] = {
        semantics = {
            cooldown = true,
        },
        layouts = {
            icons = true,
        },
        addCooldown = true,
        addBuff = false,
    },
    ["buff-only"] = {
        semantics = {
            buff = true,
        },
        layouts = {
            icons = true,
            bars = true,
            rings = true,
        },
        addCooldown = false,
        addBuff = true,
    },
    ["resource-only"] = {
        semantics = {
            resource = true,
        },
        layouts = {
            resource = true,
        },
        addCooldown = false,
        addBuff = false,
    },
    ["cast-only"] = {
        semantics = { resource = true },
        layouts = { resource = true },
        addCooldown = false,
        addBuff = false,
    },
}

local DEFAULT_GROUP_POLICY = {
    [YHUD.GROUP_IDS.IMPORTANT] = "cooldown-primary",
    [YHUD.GROUP_IDS.UTILITY] = "cooldown-primary",
    [YHUD.GROUP_IDS.BUFF] = "buff-only",
    [YHUD.GROUP_IDS.BAR] = "buff-only",
    [YHUD.GROUP_IDS.RESOURCES] = "resource-only",
    [YHUD.GROUP_IDS.TRINKETS] = "cooldown-only",
}

local DEFAULT_GROUP_SYNC = {
    [YHUD.GROUP_IDS.IMPORTANT] = "essential",
    [YHUD.GROUP_IDS.UTILITY] = "utility",
    [YHUD.GROUP_IDS.BUFF] = "trackedBuff",
    [YHUD.GROUP_IDS.BAR] = "trackedBar",
}

local OFFICIAL_VIEWS = {
    essential = {
        icon = true,
    },
    utility = {
        icon = true,
    },
    trackedBuff = {
        icon = true,
        bar = true,
        ring = true,
    },
    trackedBar = {
        icon = true,
        bar = true,
        ring = true,
    },
}

local OFFICIAL_NATIVE_VIEWS = {
    essential = "icon",
    utility = "icon",
    trackedBuff = "icon",
    trackedBar = "bar",
}

local LAYOUT_VIEW = {
    icons = "icon",
    bars = "bar",
    rings = "ring",
}

YHUD.CONTENT_POLICY = {
    revision = YHUD.CONTENT_POLICY_REVISION,
    contentScopes = {
        shared = YHUD.CONTENT_SCOPE_SHARED,
        spec = YHUD.CONTENT_SCOPE_SPEC,
    },
    applicabilityKinds = APPLICABILITY_KINDS,
    policies = POLICY,
    defaultGroupPolicy = DEFAULT_GROUP_POLICY,
    defaultGroupSync = DEFAULT_GROUP_SYNC,
    officialViews = OFFICIAL_VIEWS,
    officialNativeViews = OFFICIAL_NATIVE_VIEWS,
}

function YHUD:GetDefaultGroupContentPolicy(groupId)
    return DEFAULT_GROUP_POLICY[groupId]
end

function YHUD:GetDefaultGroupSyncCategory(groupId)
    return DEFAULT_GROUP_SYNC[groupId]
end

function YHUD:GetGroupContentPolicy(group)
    if type(group) ~= "table" then return nil end
    local policyId = group.contentPolicy
        or DEFAULT_GROUP_POLICY[group.id]
    -- User-created icon groups share one visible product type. Keep their
    -- accepted monitor kinds consistent even when an older creation path
    -- persisted the former buff-only policy.
    if group.kind == "user" and group.layout == "icons" then
        policyId = "cooldown-primary"
    end
    if not POLICY[policyId] then
        if group.layout == "resource" then
            policyId = "resource-only"
        elseif group.layout == "bars" or group.layout == "rings" then
            policyId = "buff-only"
        else
            policyId = "cooldown-primary"
        end
    end
    return policyId, POLICY[policyId]
end

function YHUD:GetEntrySemantic(entry)
    if type(entry) ~= "table" then return nil end
    if entry.semantic == "cooldown"
        or entry.semantic == "buff"
        or entry.semantic == "resource" then
        return entry.semantic
    end
    if entry.sourceType == self.CAST_BUFF_TIMER_SOURCE_TYPE
        or entry.sourceType == self.SPELL_EVENT_WINDOW_SOURCE_TYPE
        or entry.officialCategory == "trackedBuff"
        or entry.officialCategory == "trackedBar" then
        return "buff"
    end
    if entry.sourceType == "yhud.unit-power" then return "resource" end
    return "cooldown"
end

local EQUIPMENT_TRACKED_CATEGORIES = {
    equipSlotTracked = true,
    specAgnosticTracked = true,
}

function YHUD:IsOfficialEquipmentBuffEntry(entry)
    local equipSlot = type(entry) == "table"
        and tonumber(entry.equipSlot) or nil
    return type(entry) == "table"
        and entry.origin == "official-cdm"
        and (equipSlot == 13 or equipSlot == 14)
        and EQUIPMENT_TRACKED_CATEGORIES[entry.sourceCategory] == true
        and self:GetEntrySemantic(entry) == "buff"
end

local function HasPublicOfficialPresentation(entry)
    if type(entry.name) == "string" and entry.name ~= "" then return true end
    if entry.icon ~= nil then return true end
    for _, field in ipairs({
        entry.spellId,
        entry.spellID,
        entry.overrideSpellId,
        entry.overrideSpellID,
        entry.runtimeSpellId,
        entry.runtimeSpellID,
    }) do
        local value = tonumber(field)
        if value and value > 0 then return true end
    end
    for _, field in ipairs({
        entry.spellIds,
        entry.spellIDs,
        entry.linkedSpellIds,
        entry.linkedSpellIDs,
    }) do
        for index = 1, #(type(field) == "table" and field or {}) do
            local value = tonumber(field[index])
            if value and value > 0 then return true end
        end
    end
    return false
end

function YHUD:IsOfficialEntryRenderable(entry)
    if type(entry) ~= "table" or entry.origin ~= "official-cdm" then
        return true
    end
    local equipmentBuff = self:IsOfficialEquipmentBuffEntry(entry)
    if not equipmentBuff then return true end
    return HasPublicOfficialPresentation(entry)
end

function YHUD:IsOfficialEquipmentBuffUsable(entry)
    return self:IsOfficialEquipmentBuffEntry(entry)
        and entry.displayCategory == "trackedBuff"
        and entry.isKnown ~= false
        and entry.isInvisible ~= true
        and HasPublicOfficialPresentation(entry)
end

function YHUD:IsOfficialEntryClaimed(entry, claimedSources, monitorID)
    if type(entry) ~= "table" or type(claimedSources) ~= "table" then
        return false
    end
    local semantic = self:GetEntrySemantic(entry)
    local function MatchesClaim(identity)
        if type(identity) ~= "string" or identity == "" then return false end
        local claim = claimedSources[identity]
        if claim == nil then return false end
        if type(claim) ~= "table" then
            return semantic == "cooldown"
        end
        if monitorID and claim.monitor
            and claim.monitor.id == monitorID then
            return false
        end
        return claim.semantic == nil or claim.semantic == semantic
    end
    if MatchesClaim(entry.entryKey) or MatchesClaim(entry.sourceKey) then
        return true
    end
    local spellCategoryID = tonumber(entry.spellCategoryId)
    if spellCategoryID
        and MatchesClaim(
            "spell-category:" .. tostring(math.floor(spellCategoryID))
        ) then
        return true
    end
    local equipSlot = tonumber(entry.equipSlot)
    if equipSlot
        and MatchesClaim("slot:" .. tostring(math.floor(equipSlot))) then
        return true
    end
    local function ClaimedSpell(spellID)
        spellID = tonumber(spellID)
        return spellID
            and MatchesClaim("spell:" .. tostring(math.floor(spellID)))
    end
    if ClaimedSpell(entry.spellId)
        or ClaimedSpell(entry.spellID)
        or ClaimedSpell(entry.overrideSpellId)
        or ClaimedSpell(entry.overrideSpellID)
        or ClaimedSpell(entry.runtimeSpellId)
        or ClaimedSpell(entry.runtimeSpellID) then
        return true
    end
    for _, field in ipairs({
        entry.spellIds,
        entry.spellIDs,
        entry.linkedSpellIds,
        entry.linkedSpellIDs,
    }) do
        for index = 1, #(type(field) == "table" and field or {}) do
            if ClaimedSpell(field[index]) then return true end
        end
    end
    return false
end

local SYSTEM_ENTRY_NAME_KEYS = {
    defensive = "designer.quick_defensives",
    interruptControl = "designer.quick_interrupt_control",
    racial = "designer.quick_racials",
    equipmentAura = "designer.quick_equipment_auras",
}

function YHUD:GetPlayerFactionToken()
    local cached = rawget(self, "_playerFactionToken")
    if cached == "Horde" or cached == "Alliance" then return cached end

    local unitAPI = YUI.API and YUI.API.Unit
    local faction = unitAPI and unitAPI.UnitFactionGroup
        and unitAPI.UnitFactionGroup("player")
    cached = faction == "Horde" and "Horde" or "Alliance"
    self._playerFactionToken = cached
    return cached
end

function YHUD:GetEntryDisplayName(entry, fallback)
    if type(entry) ~= "table" then return fallback or "-" end
    if entry.sourceIdentity == "bloodlust"
        or entry.sourceIdentity == "bloodlust-heroism" then
        local horde = self:GetPlayerFactionToken() == "Horde"
        return self:T(
            horde and "designer.preset.bloodlust_horde"
                or "designer.preset.bloodlust_alliance",
            horde and "嗜血" or "英勇"
        )
    end
    if entry.sourceType == self.SPELL_EVENT_WINDOW_SOURCE_TYPE
        and entry.sourceKey == "spell-event-window:1265982" then
        return self:T("designer.preset.blood_boil_window", "沸点")
    end
    local bundleKind = entry.bundleKind
    if not bundleKind and entry.sourceType == "racial-bundle" then
        bundleKind = "racial"
    end
    local nameKey = entry.nameKey or SYSTEM_ENTRY_NAME_KEYS[bundleKind]
    if type(nameKey) == "string" and nameKey ~= "" then
        local localized = self:T(
            nameKey,
            type(entry.name) == "string" and entry.name ~= ""
                and entry.name or fallback
        )
        if type(localized) == "string" and localized ~= "" then
            return localized
        end
    end
    if type(entry.name) == "string" and entry.name ~= "" then
        return entry.name
    end
    local spellID = tonumber(
        entry.overrideTooltipSpellId
        or entry.overrideTooltipSpellID
        or entry.overrideSpellId
        or entry.overrideSpellID
        or entry.spellId
        or entry.spellID
    )
    local spellAPI = YUI.API and YUI.API.Spell
    if spellID and spellAPI and spellAPI.GetName then
        local name = spellAPI.GetName(spellID)
        if type(name) == "string" and name ~= "" then return name end
    end
    local itemID = tonumber(entry.itemId or entry.itemID)
    local itemAPI = YUI.API and YUI.API.Item
    if itemID and itemAPI and itemAPI.GetNameByID then
        local name = itemAPI.GetNameByID(itemID)
        if type(name) == "string" and name ~= "" then return name end
    end
    local slotID = tonumber(entry.slotId or entry.slotID)
    if slotID then
        return string.format(
            "%s %d",
            self:T("monitor.slot", "饰品"),
            slotID
        )
    end
    return fallback or tostring(spellID or itemID or entry.entryKey or "-")
end

function YHUD:GetEntryCompatibleViews(entry)
    if type(entry) ~= "table" then return {} end
    if type(entry.compatibleViews) == "table" then
        return entry.compatibleViews
    end
    if entry.origin == "official-cdm" then
        return OFFICIAL_VIEWS[entry.officialCategory] or {}
    end
    if entry.sourceType == self.CAST_BUFF_TIMER_SOURCE_TYPE then
        return {
            icon = true,
            bar = true,
            ring = true,
        }
    end
    if entry.sourceType == self.SPELL_EVENT_WINDOW_SOURCE_TYPE then
        return {
            icon = true,
            bar = true,
            ring = true,
        }
    end
    if self:GetEntrySemantic(entry) == "resource" then
        return {
            resource = true,
        }
    end
    return {
        icon = true,
    }
end

function YHUD:IsOfficialNativeView(category, view)
    return OFFICIAL_NATIVE_VIEWS[category] == view
end

function YHUD:NormalizeGroupContentPolicy(group)
    if type(group) ~= "table" then return nil end
    local policyId = DEFAULT_GROUP_POLICY[group.id]
        or group.contentPolicy
    if group.kind == "user" and group.layout == "icons" then
        policyId = "cooldown-primary"
    end
    if not POLICY[policyId] then
        policyId = (group.layout == "bars" or group.layout == "rings")
            and "buff-only"
            or (group.layout == "resource"
                and "resource-only"
                or "cooldown-primary")
    end
    local policy = POLICY[policyId]
    if not policy.layouts[group.layout] then
        if policyId == "buff-only" then
            group.layout = "icons"
        elseif policyId == "resource-only" or policyId == "cast-only" then
            group.layout = "resource"
        else
            group.layout = "icons"
        end
    end
    group.contentPolicy = policyId
    group.syncCategory = DEFAULT_GROUP_SYNC[group.id]
    return policyId
end

function YHUD:CanPlaceEntry(entry, group, view)
    if type(entry) ~= "table" then return nil, "entry-not-found" end
    if type(group) ~= "table" then return nil, "group-not-found" end

    local _, policy = self:GetGroupContentPolicy(group)
    local semantic = self:GetEntrySemantic(entry)
    if not (policy and policy.semantics[semantic]) then
        return nil, "content-policy-mismatch"
    end
    if not policy.layouts[group.layout] then
        return nil, "content-layout-mismatch"
    end

    view = view or LAYOUT_VIEW[group.layout]
    local compatibleViews = self:GetEntryCompatibleViews(entry)
    if not compatibleViews[view] then
        return nil, "source-view-mismatch"
    end
    return true
end

function YHUD:GetGroupAddCapabilities(group)
    local _, policy = self:GetGroupContentPolicy(group)
    if not policy then
        return {
            cooldown = false,
            buff = false,
        }
    end
    return {
        cooldown = policy.addCooldown == true,
        buff = policy.addBuff == true,
    }
end

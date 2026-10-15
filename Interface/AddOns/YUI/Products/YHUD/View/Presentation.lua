local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
local View = YHUD and YHUD.View
local I = View and View._internal
if not I then return end

local ResourceCatalog = I.ResourceCatalog
local DEFAULT_ICON_SIZE = I.DEFAULT_ICON_SIZE
local DEFAULT_SPACING = I.DEFAULT_SPACING
local DEFAULT_MAX_PER_LINE = I.DEFAULT_MAX_PER_LINE
local EMPTY_DESIGN_GROUP_WIDTH = I.EMPTY_DESIGN_GROUP_WIDTH
local LAYOUT_VIEWS = I.LAYOUT_VIEWS
local GetIconLayout = I.GetIconLayout
local GetDurationLayout = I.GetDurationLayout
local GetResourceLayout = I.GetResourceLayout
local FormatMonitorName = I.FormatMonitorName
local GetEntryName = I.GetEntryName
local QUESTION_ICON = I.QUESTION_ICON
local SLOT_SOURCE_TYPE = "yhud.inventory-slot-cooldown"

local function CopyMonitor(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local function IsPublicTexture(texture)
    local textureType = type(texture)
    if textureType ~= "number" and textureType ~= "string" then
        return false
    end
    local security = YUI.API and YUI.API.Security
    local checker = security and security.IsSecretValue
        or _G.issecretvalue
    if type(checker) == "function" then
        local ok, secret = pcall(checker, texture)
        if not ok or secret == true then return false end
    end
    return true
end

local function ResolveInventorySlotPreviewIcon(entry, state, queryCurrent)
    if type(entry) == "table" and YHUD.Ammo
        and entry.sourceType == YHUD.Ammo.SOURCE_TYPE then
        return YHUD.Ammo:ResolveIcon(state, queryCurrent ~= false), true
    end
    if type(entry) ~= "table"
        or entry.sourceType ~= SLOT_SOURCE_TYPE then
        return nil, false
    end
    local slotID = tonumber(entry.slotId or entry.slotID)
    if slotID ~= 13 and slotID ~= 14 then return nil, false end

    local itemAPI = YUI.API and YUI.API.Item
    local icon
    if itemAPI and type(itemAPI.GetInventoryItemTexture) == "function" then
        local ok, currentIcon = pcall(
            itemAPI.GetInventoryItemTexture,
            "player",
            slotID
        )
        if ok and IsPublicTexture(currentIcon) then icon = currentIcon end
    end
    if not icon and type(state) == "table"
        and IsPublicTexture(state.icon) then
        icon = state.icon
    end
    if not icon and IsPublicTexture(entry.icon) then icon = entry.icon end
    return icon or QUESTION_ICON, true
end

I.ResolveInventorySlotPreviewIcon = ResolveInventorySlotPreviewIcon

local function GetGroupLayout(profile, group)
    if group.layout == "icons" then
        local layout = GetIconLayout(profile, group.id)
        layout.layoutType = "icons"
        layout.view = "icon"
        layout.itemWidth = layout.iconWidth
        layout.itemHeight = layout.iconHeight
        return layout
    end
    if group.layout == "bars" or group.layout == "rings" then
        return GetDurationLayout(profile, group.id, group.layout)
    end
    if group.layout == "resource" then
        return GetResourceLayout(profile, group.id)
    end
    return {
        layoutType = group.layout,
        view = nil,
    }
end

local function BuildShadowedAuraSpellIds(profile)
    local result = {}
    local groups = profile.groups and profile.groups.items or {}
    for _, monitor in pairs(profile.monitors or {}) do
        local entry = monitor and profile.entries
            and profile.entries[monitor.entryKey]
        local group = monitor and groups[monitor.groupId]
        if entry
            and entry.origin ~= "official-cdm"
            and entry.sourceType == YHUD.PLAYER_AURA_SOURCE_TYPE
            and monitor.enabled ~= false
            and group
            and group.enabled == true then
            for index = 1, #(entry.spellIds or {}) do
                result[entry.spellIds[index]] = true
            end
            if entry.spellId then result[entry.spellId] = true end
        end
    end
    return result
end

local function IsShadowedOfficial(plan, entry)
    if not (entry
        and entry.origin == "official-cdm"
        and (entry.officialCategory == "trackedBuff"
            or entry.officialCategory == "trackedBar")) then
        return false
    end
    local shadowed = plan.shadowedAuraSpellIds
    if shadowed[entry.spellId] or shadowed[entry.overrideSpellId] then
        return true
    end
    for index = 1, #(entry.linkedSpellIds or {}) do
        if shadowed[entry.linkedSpellIds[index]] then return true end
    end
    return false
end

local function ResolveGroupStrategy(plan, group, members)
    if not YHUD.GetFilteredAuraGroupProjectionStrategy then return nil end
    return YHUD:GetFilteredAuraGroupProjectionStrategy(
        plan.profile,
        group,
        plan.preview,
        plan.projectionContext,
        members
    )
end

local function NewGroupPlan(plan, groupId)
    local group = plan.groups[groupId]
    if not group then return nil end
    local expectedView = LAYOUT_VIEWS[group.layout]
    local configuredLayoutMode = group.layoutMode == "fixed"
        and "fixed" or "auto"
    local result = {
        id = groupId,
        group = group,
        layout = GetGroupLayout(plan.profile, group),
        expectedView = expectedView,
        view = expectedView,
        configuredLayoutMode = configuredLayoutMode,
        effectiveLayoutMode = configuredLayoutMode,
        layoutModeOverrideReason = nil,
        filteredAuraProjectionStrategy = nil,
        filteredAuraProjectionReason = nil,
        filteredAuraProjectionState = nil,
        members = {},
        memberById = {},
        cursor = 1,
        done = expectedView == nil or group.enabled ~= true,
        resourcePresets = nil,
        hasCombatResourceVisibility = false,
    }
    plan.groupPlans[groupId] = result
    return result
end

local function FinalizeGroupPlan(plan, groupPlan)
    if not groupPlan or groupPlan.finalized == true then return groupPlan end
    local strategy, reason, state = ResolveGroupStrategy(
        plan,
        groupPlan.group,
        groupPlan.members
    )
    local overrideReason = strategy == YHUD.FILTERED_AURA_LAYOUT_MIXED_FIXED
        and reason or nil
    if overrideReason == YHUD.FILTERED_AURA_FIXED_REASON_CONFIGURED_LAYOUT then
        overrideReason = nil
    end
    groupPlan.filteredAuraProjectionStrategy = strategy
    groupPlan.filteredAuraProjectionReason = reason
    groupPlan.filteredAuraProjectionState = state
    groupPlan.layoutModeOverrideReason = overrideReason
    groupPlan.effectiveLayoutMode = overrideReason and "fixed"
        or groupPlan.configuredLayoutMode
    groupPlan.finalized = true
    return groupPlan
end

local function AddSourceConsumer(plan, sourceKey, monitorId)
    if not sourceKey then return end
    local consumers = plan.monitorsBySource[sourceKey]
    if not consumers then
        consumers = {}
        plan.monitorsBySource[sourceKey] = consumers
    end
    consumers[#consumers + 1] = monitorId
end

local function AddMember(
    plan,
    groupPlan,
    monitor,
    entry,
    logicalId,
    physicalId,
    availability,
    previewOnly,
    sourceKey
)
    local runtimeMonitor = monitor
    if plan.copyMonitors then
        runtimeMonitor = CopyMonitor(monitor)
        runtimeMonitor._yhudProjectionProfile = plan.profile
        runtimeMonitor._yhudProjectionEntry = entry
    end
    if plan.preview and plan.copyMonitors then
        local state = YHUD.Model and YHUD.Model.GetState
            and YHUD.Model:GetState(sourceKey) or nil
        local previewIcon, inventorySlotPreview =
            ResolveInventorySlotPreviewIcon(entry, state)
        if inventorySlotPreview then
            runtimeMonitor._yhudInventorySlotPreview = true
            runtimeMonitor._yhudDisplayIcon = previewIcon
        end
    end
    runtimeMonitor.id = physicalId
    if logicalId ~= physicalId then
        runtimeMonitor._yhudParentMonitorId = logicalId
    end
    local special = YHUD.IsFilteredAuraLayoutMonitor
        and YHUD:IsFilteredAuraLayoutMonitor(
            entry,
            runtimeMonitor,
            plan.preview
        ) == true
        or false
    local displayName = runtimeMonitor._yhudDisplayName
        or GetEntryName(entry)
    if groupPlan.layout.view == "bar"
        or groupPlan.layout.view == "ring" then
        displayName = FormatMonitorName(
            groupPlan.layout.nameTextFormat,
            displayName
        )
    end
    local member = {
        id = physicalId,
        physicalId = physicalId,
        logicalId = logicalId,
        monitor = runtimeMonitor,
        entry = entry,
        sourceKey = sourceKey,
        availability = availability,
        previewOnly = previewOnly == true,
        special = special,
        displayName = displayName,
        lane = YHUD.CONTENT_LANE_SPEC,
    }
    groupPlan.members[#groupPlan.members + 1] = member
    groupPlan.memberById[physicalId] = member
    plan.desiredMonitors[physicalId] = runtimeMonitor
    plan.membersById[physicalId] = member
    plan.logicalMonitors[logicalId] =
        plan.logicalMonitors[logicalId] or runtimeMonitor
    if plan.logicalSpecial[logicalId] == nil then
        plan.logicalSpecial[logicalId] = special
    elseif special then
        plan.logicalSpecial[logicalId] = true
    end
    if availability == "unavailable" or previewOnly == true then
        plan.unavailableMonitors[physicalId] = true
    else
        AddSourceConsumer(plan, sourceKey, physicalId)
    end
    if runtimeMonitor.resourceVisibilityMode == "nonzeroOrCombat" then
        groupPlan.hasCombatResourceVisibility = true
    end
    return member
end

local function GetResourcePresets(plan, groupPlan)
    if groupPlan.resourcePresets then return groupPlan.resourcePresets end
    local presets
    if type(plan.resourcePresets) == "table" then
        presets = plan.resourcePresets
    elseif plan.profile.groups.items[groupPlan.id]
        and plan.profile.groups.items[groupPlan.id].contentPolicy == "cast-only" then
        presets = ResourceCatalog:GetGroupPresets(plan.profile, groupPlan.id)
    elseif plan.resourceClassFile and plan.resourceSpecID then
        presets = ResourceCatalog:GetPreviewPresets(
            YHUD:GetResourceProfile(plan.profile, groupPlan.id),
            plan.resourceClassFile,
            plan.resourceSpecID,
            plan.resourceFormKey
        )
    else
        presets = ResourceCatalog:GetGroupPresets(plan.profile, groupPlan.id)
    end
    presets = presets or {}
    local focusedResourceId = (plan.focusedResourceGroupId == nil
        or plan.focusedResourceGroupId == groupPlan.id) and plan.focusedResourceId or nil
    if focusedResourceId then
        local found = false
        for index = 1, #presets do
            if presets[index].id == focusedResourceId then
                found = true
                break
            end
        end
        if not found then
            local definition = ResourceCatalog:GetDefinition(focusedResourceId)
            local classFile = plan.resourceClassFile
            local specID = plan.resourceSpecID
            if not classFile or not specID then
                classFile, specID = ResourceCatalog:GetCurrentContext()
            end
            local sourceKey = definition
                and ResourceCatalog:BuildSourceKey(
                    classFile,
                    specID,
                    focusedResourceId
                )
            if definition and sourceKey then
                presets[#presets + 1] = {
                    id = definition.id,
                    sourceKey = sourceKey,
                    classFile = classFile,
                    specID = specID,
                    powerType = definition.powerType,
                    powerToken = definition.powerToken,
                    provider = YHUD:CopyValue(definition.provider),
                    nameKey = definition.nameKey,
                    valueKind = definition.valueKind,
                    previewMax = definition.previewMax,
                    segmentCountFallback = definition.segmentCountFallback,
                    defaultValueText = definition.defaultValueText ~= false,
                    color = definition.color,
                    enabled = true,
                }
            end
        end
    end
    groupPlan.resourcePresets = presets
    return presets
end

local function BuildResourcePresentationSpec(plan, groupPlan, preset)
    local layout = groupPlan.layout or {}
    local style = YHUD.GetEffectiveResourceStyle
        and YHUD:GetEffectiveResourceStyle(
            plan.profile,
            groupPlan.id,
            preset.id,
            preset.specID
        ) or layout
    local provider = preset.provider or {}
    local providerKind = provider.kind
    local segmentCount = preset.segmentCountFallback or preset.previewMax
    local displayMode = style.displayMode
    if providerKind == "rune-cooldowns" then
        displayMode = "cells"
    elseif segmentCount and segmentCount > 25 and displayMode ~= "bar" then
        displayMode = "bar"
    end
    if (displayMode == "divided" or displayMode == "cells"
        or displayMode == "dots") and not segmentCount then
        displayMode = "bar"
    end

    local auraApplication = providerKind == "unit-aura-stacks"
        or providerKind == "adaptive-aura-stacks"
    local auraApplicationVariants
    if auraApplication then
        auraApplicationVariants = {
            {
                spellIDs = { provider.spellID },
                maxApplications = segmentCount,
            },
        }
        if providerKind == "adaptive-aura-stacks"
            and provider.alternateSpellID and provider.alternateMax then
            auraApplicationVariants[2] = {
                spellIDs = { provider.alternateSpellID },
                maxApplications = provider.alternateMax,
            }
        end
    end

    local textAppearance = {
        valueFormat = style.valueFormat,
        abbreviateValues = style.abbreviateValues,
        text2 = style.text2,
        previewDuration = style.valueDurationPreview,
        fractionalValues = providerKind == "unit-power-partial",
        valueText = style.valueText,
        position = style.textPosition,
        offsetX = style.textOffsetX,
        offsetY = style.textOffsetY,
        font = style.textFont,
        size = style.textSize,
        outline = style.textOutline,
        color = style.textColor,
    }
    return {
        style = style,
        width = layout.effectiveResourceWidth
            or layout.resourceWidth or 290,
        height = style.heightOverride or layout.resourceHeight or 16,
        display = {
            mode = displayMode,
            inverseFill = style.inverseFill == true
                and YHUD:IsResourceInverseFillSupported(preset, style),
            smoothProgress = layout.smoothProgress == true,
            valueKind = preset.valueKind,
            segmentCount = segmentCount,
            segmentSpacing = style.segmentSpacing,
            dividerThickness = style.dividerThickness,
            dividerColor = style.dividerColor,
            thresholdColorEnabled = style.thresholdColorEnabled,
            thresholdMode = style.thresholdMode,
            thresholdDirection = style.thresholdDirection,
            fillCeilingPercent = style.fillCeilingPercent,
            thresholdMarkerEnabled = style.thresholdMarkerEnabled,
            thresholds = style.thresholds,
            thresholdMarkerColor = style.thresholdMarkerColor,
            thresholdMarkerThickness = style.thresholdMarkerThickness,
            independentCells = providerKind == "rune-cooldowns",
            chargedPointColor = provider.chargedColor,
        },
        bindings = {
            rechargeProgress = providerKind == "spell-charges",
            durationProgress = providerKind == "aura-duration"
                or providerKind == "ironfur-timers" or providerKind == "swing-timer" or providerKind == "player-cast",
            durationProgressDirection = providerKind == "swing-timer" and "elapsed" or "remaining",
            auraDurationSpellID = providerKind == "aura-duration"
                and provider.spellID,
            auraTextSpellID = providerKind == "absorb" and provider.spellID or nil,
            auraDurationUnit = providerKind == "aura-duration"
                and provider.unit,
            auraDurationFilter = providerKind == "aura-duration"
                and provider.filter,
            auraDurationDirection = providerKind == "aura-duration"
                and provider.durationDirection,
            auraDurationFillColor = style.fillColor,
            auraDurationTextAppearance = textAppearance,
            auraApplicationSpellIDs = auraApplication and {
                provider.spellID,
                provider.alternateSpellID,
            } or nil,
            auraApplicationVariants = auraApplicationVariants,
            auraApplicationUnit = auraApplication and provider.unit or nil,
            auraApplicationFilter = auraApplication and provider.filter or nil,
            auraApplicationRequirePlayerSource = auraApplication
                and provider.requirePlayerSource == true or false,
            auraApplicationMax = auraApplication and segmentCount or nil,
            auraApplicationFillColor = style.fillColor,
            auraApplicationTextAppearance = textAppearance,
            timerMarkers = providerKind == "ironfur-timers",
            partialRecharge = providerKind == "unit-power-partial",
            partialUnit = "player",
            partialPowerType = preset.powerType,
            partialScale = provider.partialScale or 1000,
            partialSource = provider.partialSource,
            partialPollInterval = provider.safetyPollInterval,
        },
        text = {
            nameText = providerKind == "player-cast" and style.cast and style.cast.name == true,
            namePosition = providerKind == "player-cast" and style.cast and style.cast.namePosition or nil,
            nameSize = providerKind == "player-cast" and style.cast and (style.cast.nameSize or style.textSize) or nil,
            nameOffsetX = providerKind == "player-cast" and style.cast and style.cast.nameOffsetX or nil,
            nameOffsetY = providerKind == "player-cast" and style.cast and style.cast.nameOffsetY or nil,
            valueText = providerKind == "player-cast" and style.cast and style.cast.progress == true or providerKind ~= "player-cast" and style.valueText,
            valueFormat = style.valueFormat,
            abbreviateValues = style.abbreviateValues,
            text2 = style.text2,
            previewDuration = style.valueDurationPreview,
            fractionalValues = providerKind == "unit-power-partial",
            position = style.textPosition,
            offsetX = style.textOffsetX,
            offsetY = style.textOffsetY,
            font = style.textFont,
            size = providerKind == "player-cast" and style.cast and style.cast.progressSize or style.textSize,
            runeCooldownTextSize = style.runeCooldownTextSize,
            runeCooldownTextMode = style.runeCooldownTextMode,
            outline = style.textOutline,
            color = style.textColor,
        },
        preview = {
            value = tonumber(preset.previewMax) or 100,
            maxValue = tonumber(preset.previewMax) or 100,
            independentCells = providerKind == "rune-cooldowns",
        },
    }
end

function I.RefreshPresentationResources(plan, groupId, resourceId)
    local groupPlan = type(plan) == "table"
        and type(plan.groupPlans) == "table"
        and plan.groupPlans[groupId] or nil
    if not (groupPlan and groupPlan.done == true
        and groupPlan.expectedView == "resource") then
        return false, 0
    end

    local refreshed = 0
    for index = 1, #groupPlan.members do
        local member = groupPlan.members[index]
        local monitor = member and member.monitor
        local preset = monitor and monitor._yhudResource
        if preset and (resourceId == nil or preset.id == resourceId) then
            local setting = YHUD:GetResourceSetting(plan.profile, preset.id, groupId)
            local resourceSpec = BuildResourcePresentationSpec(
                plan,
                groupPlan,
                preset
            )
            if plan.copyMonitors then
                monitor._yhudProjectionProfile = plan.profile
            end
            monitor.resourceVisibilityMode = setting.visibilityMode
            monitor._yhudResourcePresentation = resourceSpec
            member.resourceSpec = resourceSpec
            refreshed = refreshed + 1
        end
    end
    return refreshed > 0, refreshed
end

local function AppendResourceMember(plan, groupPlan, preset, index)
    local monitorId = "monitor:" .. groupPlan.id .. ":" .. preset.sourceKey
    local setting = YHUD:GetResourceSetting(plan.profile, preset.id, groupPlan.id)
    local monitor = {
        id = monitorId,
        sourceKey = preset.sourceKey,
        groupId = groupPlan.id,
        view = "resource",
        order = index,
        enabled = true,
        resourceVisibilityMode = setting.visibilityMode,
        _yhudResource = preset,
        _yhudSynthetic = true,
    }
    local resourceSpec = BuildResourcePresentationSpec(
        plan,
        groupPlan,
        preset
    )
    monitor._yhudResourcePresentation = resourceSpec
    local member = AddMember(
        plan,
        groupPlan,
        monitor,
        nil,
        monitorId,
        monitorId,
        "available",
        false,
        preset.sourceKey
    )
    member.resourceSpec = resourceSpec
end

local function ResolveBundleSources(plan, monitorId, monitor, entry, bundleKind)
    if YHUD.GetMonitorLayoutProjection then
        return YHUD:GetMonitorLayoutProjection(
            plan.profile,
            entry,
            monitor,
            plan.preview,
            plan.claimedCooldownSources,
            plan.projectionContext
        ) or {}
    end
    local catalog = YHUD.MonitorCatalog
    if bundleKind == (YHUD.EQUIPMENT_AURA_BUNDLE_KIND
        or "equipmentAura") then
        local projection = YHUD.GetEquipmentTriggerProjection
            and YHUD:GetEquipmentTriggerProjection(plan.profile) or {}
        local result = {}
        for index = 1, #projection do
            local source = projection[index]
            if source.kind == "official-passive"
                or source.kind == "active-timer"
                or (plan.preview and source.previewOnly == true) then
                result[#result + 1] = source
            end
        end
        return result
    end
    if bundleKind == "racial" then
        return catalog and catalog.GetEnabledPlayerRacialSources
            and catalog:GetEnabledPlayerRacialSources(plan.profile) or {}
    end
    return catalog and catalog.GetEnabledSpellBundleSources
        and catalog:GetEnabledSpellBundleSources(plan.profile, bundleKind) or {}
end

local function AppendBundleMembers(
    plan,
    groupPlan,
    monitorId,
    monitor,
    entry,
    bundleKind,
    availability
)
    local sources = ResolveBundleSources(
        plan,
        monitorId,
        monitor,
        entry,
        bundleKind
    )
    for index = 1, #sources do
        local source = sources[index]
        local spellID = type(source) == "table" and source.spellID or source
        local runtimeSpellID = type(source) == "table"
            and (source.runtimeSpellID or spellID) or spellID
        local sourceKey = type(source) == "table" and source.sourceKey
            or ("spell:" .. tostring(spellID))
        local claim = plan.claimedCooldownSources[sourceKey]
        if not claim or not claim.monitor or claim.monitor.id == monitorId then
            local identity = type(source) == "table"
                and (source.childIdentity or source.cooldownID) or spellID
            local childId = monitorId .. ":" .. tostring(bundleKind)
                .. ":" .. tostring(identity)
            local child = YHUD:CopyValue(monitor)
            child.id = childId
            if type(source) == "table"
                and source.kind == "official-passive"
                and source.entryKey then
                child.entryKey = source.entryKey
            end
            child.sourceKey = sourceKey
            child._yhudParentMonitorId = monitorId
            child._yhudBundleKind = bundleKind
            child._yhudBundleSpellID = spellID
            child._yhudRuntimeSpellID = runtimeSpellID
            child._yhudSpellIdentities = type(source) == "table"
                and source.aliases or nil
            child._yhudSpellSignature = type(source) == "table"
                and source.signature or nil
            child._yhudDisplayIcon = type(source) == "table"
                and (source.displayIcon or source.icon) or nil
            child._yhudDisplayName = type(source) == "table"
                and source.displayName or nil
            child._yhudEquipmentTriggerKind = type(source) == "table"
                and source.kind or nil
            child._yhudPreviewOnly = type(source) == "table"
                and source.previewOnly == true or nil
            if child._yhudPreviewOnly == true then
                child._yhudRuntimeChannel = YHUD.RUNTIME_CHANNEL_PREVIEW_ONLY
                    or "preview-only"
            elseif child._yhudEquipmentTriggerKind == "active-timer" then
                child._yhudRuntimeChannel = YHUD.RUNTIME_CHANNEL_TIMED_SOURCE
                    or "timed-source"
            elseif child._yhudEquipmentTriggerKind == "official-passive" then
                child._yhudRuntimeChannel = YHUD.RUNTIME_CHANNEL_NATIVE_OFFICIAL
                    or "native-official"
            end
            if bundleKind == "racial" then
                child._yhudRacialSpellID = spellID
            end
            local childEntry = child.entryKey and plan.profile.entries
                and plan.profile.entries[child.entryKey] or entry
            AddMember(
                plan,
                groupPlan,
                child,
                childEntry,
                monitorId,
                childId,
                availability,
                child._yhudPreviewOnly,
                sourceKey
            )
        end
    end
end

local function AppendConfiguredMonitor(plan, groupPlan, monitorId)
    local monitor = plan.profile.monitors
        and plan.profile.monitors[monitorId]
    local entry = monitor and plan.profile.entries
        and plan.profile.entries[monitor.entryKey]
    if not (monitor and entry) then return end
    local availability = YHUD:EvaluateEntryAvailability(
        entry,
        rawget(plan.profile, "_yhudSpecKey")
    )
    if IsShadowedOfficial(plan, entry)
        or not YHUD:IsOfficialEntryRenderable(entry) then
        availability = "ineligible"
    end
    local bundleKind = entry.bundleKind
    if not bundleKind and entry.sourceType == "racial-bundle" then
        bundleKind = "racial"
    end
    if not bundleKind and YHUD:IsOfficialEntryClaimed(
        entry,
        plan.claimedCooldownSources,
        monitorId
    ) then
        availability = "ineligible"
    end
    local includeUnavailable = availability == "unavailable"
        and (plan.preview or groupPlan.configuredLayoutMode == "fixed")
        and groupPlan.group.showUnavailablePreview ~= false
    local eligible = monitor.enabled ~= false
        and monitor.view == groupPlan.expectedView
        and availability ~= "ineligible"
        and (availability == "available" or includeUnavailable)
    if not eligible then return end
    if bundleKind then
        AppendBundleMembers(
            plan,
            groupPlan,
            monitorId,
            monitor,
            entry,
            bundleKind,
            availability
        )
    else
        AddMember(
            plan,
            groupPlan,
            monitor,
            entry,
            monitorId,
            monitorId,
            availability,
            false,
            monitor.sourceKey
        )
    end
end

function I.BeginPresentationPlan(profile, options)
    if type(profile) ~= "table" then return nil end
    options = type(options) == "table" and options or {}
    local projectionContext = options.projectionContext
    if not projectionContext and YHUD.BuildMonitorLayoutProjectionContext then
        projectionContext = YHUD:BuildMonitorLayoutProjectionContext(
            profile,
            options.preview == true
        )
    end
    local catalog = YHUD.MonitorCatalog
    local claimed = projectionContext
        and projectionContext.claimedCooldownSources
        or (catalog and catalog.GetClaimedCooldownSources
            and catalog:GetClaimedCooldownSources(profile) or {})
    return {
        profile = profile,
        preview = options.preview == true,
        copyMonitors = options.copyMonitors == true,
        projectionContext = projectionContext,
        claimedCooldownSources = claimed,
        shadowedAuraSpellIds = BuildShadowedAuraSpellIds(profile),
        groups = profile.groups and profile.groups.items or {},
        groupOrder = profile.groups and profile.groups.order or {},
        groupPlans = {},
        desiredMonitors = {},
        logicalMonitors = {},
        membersById = {},
        logicalSpecial = {},
        monitorsBySource = {},
        unavailableMonitors = {},
        resourceClassFile = options.resourceClassFile,
        resourceSpecID = options.resourceSpecID,
        resourceFormKey = options.resourceFormKey,
        focusedResourceId = options.focusedResourceId,
        focusedResourceGroupId = options.focusedResourceGroupId,
        resourcePresets = options.resourcePresets,
    }
end

function I.StepPresentationGroup(plan, groupId, budget)
    if type(plan) ~= "table" then return true, nil, 0 end
    local groupPlan = plan.groupPlans[groupId]
        or NewGroupPlan(plan, groupId)
    if not groupPlan or groupPlan.done then return true, groupPlan, 0 end
    budget = math.max(1, math.floor(tonumber(budget) or 1))
    local processed = 0
    if groupPlan.expectedView == "resource" and ResourceCatalog then
        local presets = GetResourcePresets(plan, groupPlan)
        while processed < budget and groupPlan.cursor <= #presets do
            AppendResourceMember(
                plan,
                groupPlan,
                presets[groupPlan.cursor],
                groupPlan.cursor
            )
            groupPlan.cursor = groupPlan.cursor + 1
            processed = processed + 1
        end
        groupPlan.done = groupPlan.cursor > #presets
    else
        local monitorIds = groupPlan.group.monitors or {}
        while processed < budget and groupPlan.cursor <= #monitorIds do
            AppendConfiguredMonitor(
                plan,
                groupPlan,
                monitorIds[groupPlan.cursor]
            )
            groupPlan.cursor = groupPlan.cursor + 1
            processed = processed + 1
        end
        groupPlan.done = groupPlan.cursor > #monitorIds
    end
    if groupPlan.done then FinalizeGroupPlan(plan, groupPlan) end
    return groupPlan.done, groupPlan, processed
end

function I.FinishPresentationGroup(plan, groupId)
    local done, groupPlan
    repeat
        done, groupPlan = I.StepPresentationGroup(plan, groupId, 64)
    until done
    return groupPlan
end

local function ResolveConcentricRingMetrics(
    slot,
    diameter,
    requestedThickness,
    referenceDiameter
)
    local resolver = slot and slot.ResolveDurationRingMetrics
    if type(resolver) == "function" then
        local ok, material, thickness, _, outerRadius = pcall(
            resolver,
            slot,
            diameter,
            requestedThickness,
            referenceDiameter
        )
        if ok and type(thickness) == "number" and thickness > 0
            and type(outerRadius) == "number" and outerRadius > 0 then
            return material, thickness, outerRadius
        end
    end
    local thickness = math.max(1, tonumber(requestedThickness) or 8)
    return nil, thickness, diameter * 0.5
end

local function ResolveNextConcentricRingMetrics(
    slot,
    previousOuterRadius,
    ringGap,
    requestedThickness,
    referenceDiameter
)
    local resolver = slot and slot.ResolveConcentricDurationRingMetrics
    if type(resolver) == "function" then
        local ok, material, diameter, thickness, outerRadius = pcall(
            resolver,
            slot,
            previousOuterRadius,
            ringGap,
            requestedThickness,
            referenceDiameter
        )
        if ok and type(diameter) == "number" and diameter > 0
            and type(thickness) == "number" and thickness > 0
            and type(outerRadius) == "number"
            and outerRadius > previousOuterRadius then
            return material, diameter, thickness, outerRadius
        end
    end
    local thickness = math.max(1, tonumber(requestedThickness) or 8)
    local outerRadius = previousOuterRadius
        + math.max(0, tonumber(ringGap) or 0) + thickness
    return nil, outerRadius * 2, thickness, outerRadius
end

local function BuildConcentricRingGeometry(layout, items, count)
    local baseDiameter = layout.diameter or DEFAULT_ICON_SIZE
    local gap = layout.ringStep or 8
    local requestedThickness = layout.ringThickness or 8
    local diameters = { baseDiameter }
    local materials, thicknesses, outerRadii = {}, {}, {}
    local fallback
    for index = 1, count do
        if items[index] then fallback = items[index] break end
    end
    local function SlotForLayer(layer)
        local index = layout.direction == "inward"
            and (count - layer + 1) or layer
        return items[index] or fallback
    end
    materials[1], thicknesses[1], outerRadii[1] =
        ResolveConcentricRingMetrics(
            SlotForLayer(1),
            baseDiameter,
            requestedThickness,
            baseDiameter
        )
    for layer = 2, count do
        materials[layer], diameters[layer], thicknesses[layer],
            outerRadii[layer] = ResolveNextConcentricRingMetrics(
                SlotForLayer(layer),
                outerRadii[layer - 1],
                gap,
                requestedThickness,
                baseDiameter
            )
    end
    local geometry = {
        mode = "concentric",
        width = diameters[count] or baseDiameter,
        height = diameters[count] or baseDiameter,
        placements = {},
        baseDiameter = baseDiameter,
        count = count,
    }
    for index = 1, count do
        if items[index] then
            local layoutPosition = index - 1
            local layer = layout.direction == "inward"
                and (count - layoutPosition) or (layoutPosition + 1)
            geometry.placements[index] = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 0,
                diameter = diameters[layer] or baseDiameter,
                material = materials[layer],
                thickness = requestedThickness,
                referenceDiameter = baseDiameter,
                frameLevelOffset = layoutPosition + 1,
            }
        end
    end
    return geometry
end

local function ItemSize(layout)
    if layout.view == "bar" then
        return layout.itemWidth or 244, layout.itemHeight or 24
    end
    if layout.view == "ring" then
        local diameter = layout.diameter or DEFAULT_ICON_SIZE
        return diameter, diameter
    end
    return layout.itemWidth or layout.iconWidth
            or layout.iconSize or DEFAULT_ICON_SIZE,
        layout.itemHeight or layout.iconHeight
            or layout.iconSize or DEFAULT_ICON_SIZE
end

local function ResourceItemSize(layout, item, index, options)
    local metric = options and options.resourceMetrics
        and options.resourceMetrics[index]
    local width = metric and metric.width
        or item and item.gui2ResourceWidth
        or item and item._yhudResourcePresentation
            and item._yhudResourcePresentation.width
        or layout.effectiveResourceWidth
        or layout.resourceWidth
        or 290
    local height = metric and metric.height
        or item and item.gui2ResourceHeight
        or item and item._yhudResourcePresentation
            and item._yhudResourcePresentation.height
        or layout.resourceHeight
        or 16
    width = tonumber(width)
    height = tonumber(height)
    return width and width > 0 and width or 290,
        height and height > 0 and height or 16
end

local function BuildResourceStackGeometry(layout, items, count, options)
    local horizontal = layout.direction == "right"
        or layout.direction == "left"
    local perLine = math.min(
        math.max(1, math.floor(tonumber(layout.maxPerLine)
            or DEFAULT_MAX_PER_LINE)),
        math.max(1, count)
    )
    local spacing = tonumber(layout.spacing) or 0
    if spacing ~= 0 and options and options.pixelSize then
        local resolved = options.pixelSize(math.abs(spacing))
        if type(resolved) == "number" then
            spacing = spacing < 0 and -resolved or resolved
        end
    end
    local minimumStep = options and options.minimumPixelStep or 1
    local lineCount = count > 0 and math.ceil(count / perLine) or 1
    local metrics, lines = {}, {}
    for lineIndex = 1, lineCount do
        lines[lineIndex] = {
            primarySize = 0,
            secondarySize = 0,
            secondaryOffset = 0,
        }
    end
    for index = 1, count do
        if items[index] then
            local width, height = ResourceItemSize(
                layout,
                items[index],
                index,
                options
            )
            local layoutPosition = index - 1
            local lineIndex = math.floor(layoutPosition / perLine) + 1
            local metric = {
                width = width,
                height = height,
                primarySize = horizontal and width or height,
                secondarySize = horizontal and height or width,
                lineIndex = lineIndex,
                position = layoutPosition % perLine,
            }
            metrics[index] = metric
            lines[lineIndex].secondarySize = math.max(
                lines[lineIndex].secondarySize,
                metric.secondarySize
            )
        end
    end

    local primarySize = 0
    for lineIndex = 1, lineCount do
        local line = lines[lineIndex]
        local firstPosition = (lineIndex - 1) * perLine + 1
        local lastPosition = math.min(firstPosition + perLine - 1, count)
        local cursor, extent = 0, 0
        for position = firstPosition, lastPosition do
            local metric = metrics[position]
            if metric then
                metric.primaryOffset = cursor
                extent = math.max(extent, cursor + metric.primarySize)
                cursor = cursor + metric.primarySize
                if position < lastPosition then
                    local gap = spacing
                    if gap < 0 then
                        gap = math.max(
                            gap,
                            -metric.primarySize + minimumStep
                        )
                    end
                    cursor = cursor + gap
                end
            end
        end
        line.primarySize = math.max(extent, minimumStep)
        primarySize = math.max(primarySize, line.primarySize)
    end

    local secondaryCursor, secondarySize = 0, 0
    for lineIndex = 1, lineCount do
        local line = lines[lineIndex]
        line.secondaryOffset = secondaryCursor
        secondarySize = math.max(
            secondarySize,
            secondaryCursor + line.secondarySize
        )
        secondaryCursor = secondaryCursor + line.secondarySize
        if lineIndex < lineCount then
            local gap = spacing
            if gap < 0 then
                gap = math.max(gap, -line.secondarySize + minimumStep)
            end
            secondaryCursor = secondaryCursor + gap
        end
    end

    local fullWidth = horizontal and primarySize or secondarySize
    local fullHeight = horizontal and secondarySize or primarySize
    local geometry = {
        mode = "resource",
        width = fullWidth,
        height = fullHeight,
        fullWidth = fullWidth,
        fullHeight = fullHeight,
        placements = {},
        count = count,
        metrics = metrics,
        lines = lines,
        prefixWidths = { [0] = 0 },
        prefixHeights = { [0] = 0 },
    }
    local completedPrimarySize = 0
    local currentLineIndex, currentLineExtent = 0, 0
    for index = 1, count do
        local metric = metrics[index]
        if metric then
            local line = lines[metric.lineIndex]
            local unused = primarySize - line.primarySize
            local alignmentOffset = layout.alignment == "end" and unused
                or (layout.alignment == "center" and unused * 0.5 or 0)
            local crossOffset = (line.secondarySize - metric.secondarySize) * 0.5
            local primaryOffset = alignmentOffset + metric.primaryOffset
            local secondaryOffset = line.secondaryOffset + crossOffset
            local placement = {
                width = metric.width,
                height = metric.height,
            }
            if layout.direction == "left" then
                placement.point, placement.relativePoint = "TOPRIGHT", "TOPRIGHT"
                placement.x, placement.y = -primaryOffset, -secondaryOffset
            elseif layout.direction == "down" then
                placement.point, placement.relativePoint = "TOPLEFT", "TOPLEFT"
                placement.x, placement.y = secondaryOffset, -primaryOffset
            elseif layout.direction == "up" then
                placement.point, placement.relativePoint =
                    "BOTTOMLEFT", "BOTTOMLEFT"
                placement.x, placement.y = secondaryOffset, primaryOffset
            else
                placement.point, placement.relativePoint = "TOPLEFT", "TOPLEFT"
                placement.x, placement.y = primaryOffset, -secondaryOffset
            end
            geometry.placements[index] = placement

            if currentLineIndex ~= metric.lineIndex then
                currentLineIndex = metric.lineIndex
                currentLineExtent = 0
            end
            currentLineExtent = math.max(
                currentLineExtent,
                metric.primaryOffset + metric.primarySize
            )
            local prefixPrimarySize = math.max(
                completedPrimarySize,
                currentLineExtent
            )
            local prefixSecondarySize = line.secondaryOffset
                + line.secondarySize
            geometry.prefixWidths[index] = horizontal
                and prefixPrimarySize or prefixSecondarySize
            geometry.prefixHeights[index] = horizontal
                and prefixSecondarySize or prefixPrimarySize
            if metric.position == perLine - 1 then
                completedPrimarySize = math.max(
                    completedPrimarySize,
                    currentLineExtent
                )
            end
        end
    end
    local visibleCount = options and tonumber(options.visibleCount)
    if visibleCount then
        visibleCount = math.max(0, math.min(count, math.floor(visibleCount)))
        geometry.width = geometry.prefixWidths[visibleCount] or 0
        geometry.height = geometry.prefixHeights[visibleCount] or 0
    end
    if count == 0 and options and options.design then
        local itemWidth, itemHeight = ItemSize(layout)
        geometry.width = math.max(itemWidth, EMPTY_DESIGN_GROUP_WIDTH)
        geometry.height = math.max(itemHeight, 38)
    end
    return geometry
end

local function BuildResourceGeometry(layout, items, count, options)
    if layout.handPairMode ~= "split" or YUI.IsForever ~= true then
        return BuildResourceStackGeometry(layout, items, count, options)
    end
    local mainIndex, offIndex
    for index = 1, count do
        local metric = options and options.resourceMetrics and options.resourceMetrics[index]
        local id = metric and metric.resourceId or items[index] and items[index]._yhudResourceId
        if id == "swingMainHand" then mainIndex = index end
        if id == "swingOffHand" then offIndex = index end
    end
    if not (mainIndex and offIndex) then
        return BuildResourceStackGeometry(layout, items, count, options)
    end
    local rowItems, rowMetrics, rowIndices = {}, {}, {}
    local mainWidth, mainHeight = ResourceItemSize(layout, items[mainIndex], mainIndex, options)
    local offWidth, offHeight = ResourceItemSize(layout, items[offIndex], offIndex, options)
    local pairRow
    for index = 1, count do
        if index == math.min(mainIndex, offIndex) then
            pairRow = #rowItems + 1
            rowItems[pairRow] = items[mainIndex]
            rowMetrics[pairRow] = { width = math.max(mainWidth, offWidth), height = math.max(mainHeight, offHeight) }
            rowIndices[pairRow] = { mainIndex, offIndex }
        elseif index ~= mainIndex and index ~= offIndex then
            local width, height = ResourceItemSize(layout, items[index], index, options)
            rowItems[#rowItems + 1] = items[index]
            rowMetrics[#rowMetrics + 1] = { width = width, height = height }
            rowIndices[#rowIndices + 1] = { index }
        end
    end
    local rowOptions = {}
    for key, value in pairs(options or {}) do rowOptions[key] = value end
    rowOptions.resourceMetrics, rowOptions.visibleCount = rowMetrics, nil
    local geometry = BuildResourceStackGeometry(layout, rowItems, #rowItems, rowOptions)
    local placements, metrics = {}, {}
    local gap = options and options.minimumPixelStep or 1
    for rowIndex, indices in ipairs(rowIndices) do
        local placement = geometry.placements[rowIndex]
        if rowIndex == pairRow then
            local width = placement.width
            local leftWidth = math.floor((width - gap) * 0.5 / gap) * gap
            local rightWidth = width - gap - leftWidth
            for half, index in ipairs(indices) do
                local item = {}
                for key, value in pairs(placement) do item[key] = value end
                item.width = half == 1 and leftWidth or rightWidth
                if item.point == "TOPRIGHT" then
                    item.x = item.x - (half == 1 and rightWidth + gap or 0)
                else
                    item.x = item.x + (half == 2 and leftWidth + gap or 0)
                end
                placements[index], metrics[index] = item, { width = item.width, height = item.height }
            end
        else
            placements[indices[1]], metrics[indices[1]] = placement, geometry.metrics[rowIndex]
        end
    end
    geometry.placements, geometry.metrics, geometry.count = placements, metrics, count
    geometry.prefixWidths, geometry.prefixHeights = nil, nil
    return geometry
end

local function AppendRows(target, indices, maxPerLine, kind, startIndex)
    for start = startIndex or 1, #indices, maxPerLine do
        local row = { kind = kind, indices = {}, specialFlags = {} }
        for index = start, math.min(#indices, start + maxPerLine - 1) do
            row.indices[#row.indices + 1] = indices[index]
            row.specialFlags[#row.specialFlags + 1] = kind == "special"
        end
        target[#target + 1] = row
    end
end

local function BuildSegmentedGeometry(layout, items, count, specialFlags)
    local itemWidth, itemHeight = ItemSize(layout)
    local columnSpacing = tonumber(layout.columnSpacing) or DEFAULT_SPACING
    local rowSpacing = tonumber(layout.rowSpacing) or DEFAULT_SPACING
    local maxPerLine = math.max(
        1,
        math.floor(tonumber(layout.maxPerLine) or DEFAULT_MAX_PER_LINE)
    )
    local ordinary, special = {}, {}
    for index = 1, count do
        if items[index] then
            local target = specialFlags and specialFlags[index]
                and special or ordinary
            target[#target + 1] = index
        end
    end
    local ordinaryRows, specialRows = {}, {}
    AppendRows(ordinaryRows, ordinary, maxPerLine, "ordinary")
    local specialStart = 1
    local lastOrdinaryRow = ordinaryRows[#ordinaryRows]
    if lastOrdinaryRow and #lastOrdinaryRow.indices < maxPerLine then
        local available = maxPerLine - #lastOrdinaryRow.indices
        local fillCount = math.min(available, #special)
        for index = 1, fillCount do
            lastOrdinaryRow.indices[#lastOrdinaryRow.indices + 1] =
                special[index]
            lastOrdinaryRow.specialFlags[
                #lastOrdinaryRow.specialFlags + 1
            ] = true
        end
        if fillCount > 0 then
            lastOrdinaryRow.kind = "mixed"
            specialStart = fillCount + 1
        end
    end
    AppendRows(
        specialRows,
        special,
        maxPerLine,
        "special",
        specialStart
    )
    local rows = {}
    for index = 1, #ordinaryRows do
        rows[#rows + 1] = ordinaryRows[index]
    end
    for index = 1, #specialRows do
        rows[#rows + 1] = specialRows[index]
    end
    local maxColumns = 1
    for rowIndex = 1, #rows do
        maxColumns = math.max(maxColumns, #rows[rowIndex].indices)
    end
    local width = maxColumns * itemWidth
        + math.max(0, maxColumns - 1) * columnSpacing
    local rowCount = #rows
    local height = math.max(1, rowCount) * itemHeight
        + math.max(0, rowCount - 1) * rowSpacing
    local geometry = {
        mode = "segmented",
        width = width,
        height = height,
        placements = {},
        count = count,
        rows = rows,
        ordinaryRows = ordinaryRows,
        specialRows = specialRows,
        itemWidth = itemWidth,
        itemHeight = itemHeight,
        rowSpacing = rowSpacing,
        columnSpacing = columnSpacing,
    }
    local function PlaceRows(rows)
        for rowIndex = 1, #rows do
            local row = rows[rowIndex]
            local rowWidth = #row.indices * itemWidth
                + math.max(0, #row.indices - 1) * columnSpacing
            local unused = width - rowWidth
            local startX = layout.alignment == "end" and unused
                or (layout.alignment == "center" and unused * 0.5 or 0)
            local visualRow = rowIndex - 1
            for column = 1, #row.indices do
                local itemIndex = row.indices[column]
                local visualColumn = layout.rowDirection == "left"
                    and (#row.indices - column) or (column - 1)
                geometry.placements[itemIndex] = {
                    point = layout.wrapDirection == "up"
                        and "BOTTOMLEFT" or "TOPLEFT",
                    relativePoint = layout.wrapDirection == "up"
                        and "BOTTOMLEFT" or "TOPLEFT",
                    x = startX
                        + visualColumn * (itemWidth + columnSpacing),
                    y = layout.wrapDirection == "up"
                        and visualRow * (itemHeight + rowSpacing)
                        or -visualRow * (itemHeight + rowSpacing),
                    width = itemWidth,
                    height = itemHeight,
                    region = row.kind,
                    regionRow = rowIndex,
                    special = row.specialFlags[column] == true,
                }
            end
        end
    end
    -- The first ordinary row always remains nearest the saved group anchor.
    -- Its remaining configured capacity is filled by special monitors before
    -- later special-only rows are appended.
    PlaceRows(rows)
    return geometry
end

local function BuildStaticGeometry(layout, items, count, options)
    local itemWidth, itemHeight = ItemSize(layout)
    local verticalBar = layout.view == "bar"
        and layout.orientation == "vertical"
    local horizontal = not verticalBar
    local perLine = math.min(
        math.max(1, tonumber(layout.maxPerLine) or DEFAULT_MAX_PER_LINE),
        math.max(1, count)
    )
    local lineCount = count > 0 and math.ceil(count / perLine) or 1
    local columnSpacing = tonumber(layout.columnSpacing) or 0
    local rowSpacing = tonumber(layout.rowSpacing) or 0
    local primaryItemSize = horizontal and itemWidth or itemHeight
    local secondaryItemSize = horizontal and itemHeight or itemWidth
    local primarySpacing
    local secondarySpacing
    if horizontal then
        primarySpacing = columnSpacing
        secondarySpacing = rowSpacing
    else
        primarySpacing = rowSpacing
        secondarySpacing = columnSpacing
    end
    local primaryStep = primaryItemSize + primarySpacing
    local secondaryStep = secondaryItemSize + secondarySpacing
    local primarySize = perLine * primaryItemSize
        + math.max(0, perLine - 1) * primarySpacing
    local secondarySize = lineCount * secondaryItemSize
        + math.max(0, lineCount - 1) * secondarySpacing
    local geometry = {
        mode = "static",
        width = horizontal and primarySize or secondarySize,
        height = horizontal and secondarySize or primarySize,
        placements = {},
        count = count,
    }
    if count == 0 and options and options.design then
        geometry.width = math.max(itemWidth, EMPTY_DESIGN_GROUP_WIDTH)
        geometry.height = math.max(itemHeight, 38)
    end
    local placed = 0
    for index = 1, count do
        if items[index] then
            local layoutPosition = options and options.fixedLayout
                and (index - 1) or placed
            local line = math.floor(layoutPosition / perLine)
            local position = layoutPosition % perLine
            local itemsInLine = math.min(perLine, count - line * perLine)
            local linePrimarySize = itemsInLine * primaryItemSize
                + math.max(0, itemsInLine - 1) * primarySpacing
            local unused = primarySize - linePrimarySize
            local alignmentOffset = layout.alignment == "end" and unused
                or (layout.alignment == "center" and unused * 0.5 or 0)
            local rowPosition = position
            if layout.view == "icon" and layout.rowDirection == "left" then
                rowPosition = itemsInLine - position - 1
            end
            local primaryOffset = alignmentOffset + rowPosition * primaryStep
            local secondaryOffset = line * secondaryStep
            local placement = { width = itemWidth, height = itemHeight }
            if layout.view == "ring" then
                placement.diameter = layout.diameter or itemWidth
                placement.thickness = layout.ringThickness
                placement.referenceDiameter = nil
            end
            if verticalBar and layout.wrapDirection == "up" then
                placement.point, placement.relativePoint = "TOPRIGHT", "TOPRIGHT"
                placement.x, placement.y = -secondaryOffset, -primaryOffset
            elseif verticalBar then
                placement.point, placement.relativePoint = "TOPLEFT", "TOPLEFT"
                placement.x, placement.y = secondaryOffset, -primaryOffset
            elseif layout.wrapDirection == "up" then
                placement.point, placement.relativePoint =
                    "BOTTOMLEFT", "BOTTOMLEFT"
                placement.x, placement.y = primaryOffset, secondaryOffset
            else
                placement.point, placement.relativePoint = "TOPLEFT", "TOPLEFT"
                placement.x, placement.y = primaryOffset, -secondaryOffset
            end
            geometry.placements[index] = placement
            placed = placed + 1
        end
    end
    return geometry
end

-- The saved group anchor belongs to the full row, independent of active
-- members. Content width remains a separate public metric for consumers such
-- as resource bars; restricted Aura geometry is never measured here.
function I.GetAutoIconRowWidth(layout)
    if layout.view ~= "icon" or layout.layoutMode == "fixed" then return nil end
    local itemWidth = ItemSize(layout)
    local columns = math.max(
        1, math.floor(tonumber(layout.maxPerLine) or DEFAULT_MAX_PER_LINE)
    )
    return columns * itemWidth
        + (columns - 1) * (tonumber(layout.columnSpacing) or 0)
end

function I.BuildGroupGeometry(layout, items, count, options)
    layout = type(layout) == "table" and layout or {}
    items = type(items) == "table" and items or {}
    count = math.max(0, math.floor(tonumber(count) or #items))
    options = type(options) == "table" and options or {}
    if layout.view == "ring"
        and (layout.direction == "outward" or layout.direction == "inward") then
        return BuildConcentricRingGeometry(layout, items, count)
    end
    if layout.view == "resource" then
        return BuildResourceGeometry(layout, items, count, options)
    end
    local geometry
    if options.segmented == true then
        geometry = BuildSegmentedGeometry(
            layout,
            items,
            count,
            options.specialFlags
        )
    else
        geometry = BuildStaticGeometry(layout, items, count, options)
    end
    local rowWidth = not options.fixedLayout and I.GetAutoIconRowWidth(layout)
    if rowWidth then
        geometry.contentWidth = geometry.width
        local unused = rowWidth - geometry.width
        local offset = layout.alignment == "end" and unused
            or (layout.alignment == "center" and unused * 0.5 or 0)
        geometry.width = rowWidth
        for _, placement in pairs(geometry.placements) do
            placement.x = placement.x + offset
        end
    end
    return geometry
end

function I.ApplyGroupGeometry(geometry, adapter)
    if not (geometry and adapter) then return false end
    local changed = adapter.SetHolderSize
        and adapter:SetHolderSize(geometry.width, geometry.height) == true
        or false
    for index = 1, tonumber(geometry.count)
        or #(geometry.placements or {}) do
        local placement = geometry.placements[index]
        if placement then
            if placement.diameter and adapter.SetRingGeometry then
                changed = adapter:SetRingGeometry(index, placement) == true
                    or changed
            elseif adapter.SetItemSize then
                changed = adapter:SetItemSize(
                    index,
                    placement.width,
                    placement.height
                ) == true or changed
            end
            if adapter.SetItemPoint then
                changed = adapter:SetItemPoint(index, placement) == true
                    or changed
            end
            if placement.frameLevelOffset and adapter.SetItemFrameLevel then
                changed = adapter:SetItemFrameLevel(
                    index,
                    placement.frameLevelOffset
                ) == true or changed
            end
        end
    end
    return changed
end

I.GetPresentationGroupLayout = GetGroupLayout

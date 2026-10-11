local YUI = _G.YUI
local YHUD = YUI and YUI.YHUD
if not YHUD then return end

local NativeBridge = YHUD.NativeBridge or {}
YHUD.NativeBridge = NativeBridge

local OFFICIAL_ADDON = "Blizzard_CooldownViewer"
NativeBridge.officialRuntimeRetryDelays =
    NativeBridge.officialRuntimeRetryDelays
    or { 0, 0.05, 0.1, 0.25, 0.5, 1, 2 }
local OFFICIAL_SWIPE_TEXTURE =
    "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
local OFFICIAL_ICON_OVERLAY_ATLAS =
    "UI-HUD-CoolDownManager-IconOverlay"
local OFFICIAL_ICON_OVERLAY_TEXTURE = 6707800
local Unpack = unpack or table.unpack
local HAS_SCOPED_GROUP_IDS = YHUD.GROUP_IDS ~= nil
local GROUP_IDS = YHUD.GROUP_IDS or {
    IMPORTANT = "group:essential",
    UTILITY = "group:utility",
    BUFF = "group:buff",
    BAR = "group:bar",
}
local DESCRIPTORS = {
    {
        category = "essential",
        defaultGroupId = GROUP_IDS.IMPORTANT,
        globalName = "EssentialCooldownViewer",
        layout = "icons",
        kind = "icon",
        includeUnmapped = false,
        dynamicVisibility = false,
    },
    {
        category = "utility",
        defaultGroupId = GROUP_IDS.UTILITY,
        globalName = "UtilityCooldownViewer",
        layout = "icons",
        kind = "icon",
        includeUnmapped = false,
        dynamicVisibility = false,
    },
    {
        category = "trackedBuff",
        defaultGroupId = GROUP_IDS.BUFF,
        globalName = "BuffIconCooldownViewer",
        layout = "icons",
        kind = "icon",
        includeUnmapped = not HAS_SCOPED_GROUP_IDS,
        dynamicVisibility = true,
    },
    {
        category = "trackedBar",
        defaultGroupId = GROUP_IDS.BAR,
        globalName = "BuffBarCooldownViewer",
        layout = "bars",
        kind = "bar",
        includeUnmapped = not HAS_SCOPED_GROUP_IDS,
        dynamicVisibility = true,
    },
}
local DESCRIPTOR_BY_CATEGORY = {}
for descriptorIndex = 1, #DESCRIPTORS do
    local descriptor = DESCRIPTORS[descriptorIndex]
    DESCRIPTOR_BY_CATEGORY[descriptor.category] = descriptor
end
local PANDEMIC_GLOW_COLOR = { 1, 0.08, 0.02, 0.9 }
local PANDEMIC_ICON_GLOW_TEXTURES =
    YUI.GUI2 and YUI.GUI2.IconStateInnerTextures or {}
local PANDEMIC_MATERIAL_GLOW = {
    style = "material",
    color = PANDEMIC_GLOW_COLOR,
    hidden = true,
}
local PANDEMIC_PIXEL_GLOW = {
    style = "pixel",
    size = 1,
    lines = 8,
    thickness = 2,
    speed = 0.35,
    alpha = 0.9,
    color = PANDEMIC_GLOW_COLOR,
    hidden = true,
}
local ICON_COOLDOWN_FRAME_LEVEL_OFFSET = 8
local ICON_TEXT_FRAME_LEVEL_OFFSET = 10
local ICON_TEXT_DRAW_LAYER = "OVERLAY"
local ICON_TEXT_DRAW_SUBLEVEL = 7
local DIRTY_MEMBERSHIP = 1
local DIRTY_LAYOUT = 2
local DIRTY_STRUCTURE = 3
local STAT_FIELDS = {
    "exactAuraSignals",
    "exactAuraVisibilityChanges",
    "exactAuraStableSignals",
    "geometryHookRepairs",
    "geometryAuditRepairs",
    "geometryRepairFailures",
    "activeStateSignals",
    "activeStateSignalsCoalesced",
    "activeStateImmediateRepairs",
    "activeStateSettleFlushes",
    "activeStateSettleRepairs",
    "activeStateStaleSignals",
    "viewerScaleMismatches",
    "activeStateImmediateGroupRelayouts",
    "activeStateRecollects",
    "activeStateRecollectScannedFrames",
    "activeStateRecollectMaxFrames",
    "activeStateRecollectMembershipChanges",
    "activeStateRecollectRetries",
    "activeStateRecollectFailures",
    "itemFrameAcquireSignals",
    "itemFrameAcquireElapsedMS",
    "itemFrameAcquireMaxMS",
    "categorySyncs",
    "categorySyncRequests",
    "categorySyncCoalesced",
    "categorySyncFlushes",
    "categorySyncElapsedMS",
    "categorySyncScannedFrames",
    "categorySyncMaxFrames",
    "pandemicShowSignals",
    "pandemicHideSignals",
    "procGlowSignals",
    "procGlowWrites",
    "staticLayoutSignals",
    "staticLayoutScannedFrames",
    "staticLayoutMaxFrames",
    "staticLayoutReleaseAuditsSkipped",
    "staticCooldownSignals",
    "staticCooldownElapsedMS",
    "staticCooldownMaxMS",
    "staticPositionRepairs",
    "staticPositionElapsedMS",
    "staticPositionMaxMS",
    "frameStateCreates",
    "iconChromeCreates",
    "statusChromeCreates",
    "procGlowCreates",
    "pandemicGlowCreates",
    "exactNativeBarRewrites",
    "layoutWrites",
    "dynamicMembershipSignals",
    "dynamicMembershipChanges",
    "dynamicMembershipFlushes",
    "dynamicMembershipScannedMembers",
    "dynamicMembershipMaxMembers",
    "dynamicGroupFlushes",
    "dynamicLayoutSignals",
    "dynamicLayoutFlushes",
    "barContentSignals",
    "barContentRewrites",
    "nativeDurationTextWrites",
    "contextSafeFlushes",
    "categoryStructureFlushes",
    "categoryFlushProfileReads",
    "visibilityProjections",
    "visibilityAlphaWrites",
    "visibilityAlphaSkips",
    "visibilityAlphaFailures",
}
NativeBridge.states = NativeBridge.states or {}
NativeBridge.frameStates = NativeBridge.frameStates
    or setmetatable({}, { __mode = "k" })
NativeBridge.keybindStates = NativeBridge.keybindStates
    or setmetatable({}, { __mode = "k" })
NativeBridge.procFrames = NativeBridge.procFrames
    or setmetatable({}, { __mode = "k" })
NativeBridge.procHookedFrames = NativeBridge.procHookedFrames
    or setmetatable({}, { __mode = "k" })
NativeBridge.debuffBorderHooks = NativeBridge.debuffBorderHooks
    or setmetatable({}, { __mode = "k" })
NativeBridge.pandemicHookedRegions = NativeBridge.pandemicHookedRegions
    or setmetatable({}, { __mode = "k" })
NativeBridge.pandemicRegionOwners = NativeBridge.pandemicRegionOwners
    or setmetatable({}, { __mode = "k" })
NativeBridge.skillAuraHookedFrames = NativeBridge.skillAuraHookedFrames
    or setmetatable({}, { __mode = "k" })
NativeBridge.spellUsesHookedFrames = NativeBridge.spellUsesHookedFrames
    or setmetatable({}, { __mode = "k" })
NativeBridge.chargeGainedHookedFrames = NativeBridge.chargeGainedHookedFrames
    or setmetatable({}, { __mode = "k" })
NativeBridge.timerShownHookedFrames = NativeBridge.timerShownHookedFrames
    or setmetatable({}, { __mode = "k" })
NativeBridge.barContentHookedFrames = NativeBridge.barContentHookedFrames
    or setmetatable({}, { __mode = "k" })
NativeBridge.barDurationHookedFrames = NativeBridge.barDurationHookedFrames
    or setmetatable({}, { __mode = "k" })
NativeBridge.staticCooldownHookedFrames =
    NativeBridge.staticCooldownHookedFrames
    or setmetatable({}, { __mode = "k" })
NativeBridge.staticPositionHookedFrames =
    NativeBridge.staticPositionHookedFrames
    or setmetatable({}, { __mode = "k" })
NativeBridge.dynamicPointHookedFrames =
    NativeBridge.dynamicPointHookedFrames
    or setmetatable({}, { __mode = "k" })
NativeBridge.dynamicSizeHookedFrames =
    NativeBridge.dynamicSizeHookedFrames
    or setmetatable({}, { __mode = "k" })
NativeBridge.dynamicScaleHookedFrames =
    NativeBridge.dynamicScaleHookedFrames
    or setmetatable({}, { __mode = "k" })
NativeBridge.tooltipHookedFrames = NativeBridge.tooltipHookedFrames
    or setmetatable({}, { __mode = "k" })
NativeBridge.active = NativeBridge.active == true
NativeBridge.editModeActive = NativeBridge.editModeActive == true
NativeBridge.editModeExitObserved = NativeBridge.editModeExitObserved == true
NativeBridge.editCallbacksRegistered =
    NativeBridge.editCallbacksRegistered == true
NativeBridge.dirtyCategories = NativeBridge.dirtyCategories or {}
NativeBridge.dirtyCategoryReasons = NativeBridge.dirtyCategoryReasons or {}
NativeBridge.dirtyCategoryKinds = NativeBridge.dirtyCategoryKinds or {}
NativeBridge.dirtyCategoryCombatSafe =
    NativeBridge.dirtyCategoryCombatSafe or {}
NativeBridge.activeStateSettleGroups =
    NativeBridge.activeStateSettleGroups or {}
NativeBridge.activeStateSettlePending =
    NativeBridge.activeStateSettlePending == true
NativeBridge.activeStateSettleTicks =
    tonumber(NativeBridge.activeStateSettleTicks) or 0
NativeBridge.activeStateRecollectRetry =
    tonumber(NativeBridge.activeStateRecollectRetry) or 0
NativeBridge.officialRuntimeGeneration =
    tonumber(NativeBridge.officialRuntimeGeneration) or 0
NativeBridge.officialRuntimeReady =
    NativeBridge.officialRuntimeReady == true
NativeBridge.stats = NativeBridge.stats or {}
for statIndex = 1, #STAT_FIELDS do
    local field = STAT_FIELDS[statIndex]
    NativeBridge.stats[field] = tonumber(NativeBridge.stats[field]) or 0
end

local function AddStat(field, amount)
    NativeBridge.stats[field] = (NativeBridge.stats[field] or 0)
        + (amount or 1)
end

local function MaxStat(field, value)
    if type(value) ~= "number" then return end
    NativeBridge.stats[field] = math.max(
        NativeBridge.stats[field] or 0,
        value
    )
end

local function ProfileNowMS()
    if YHUD.performanceDiagnosticsEnabled ~= true then return nil end
    if type(debugprofilestop) ~= "function" then return nil end
    local ok, value = pcall(debugprofilestop)
    return ok and type(value) == "number" and value or nil
end

local function RecordProfileElapsed(totalField, maxField, startedAt)
    local finishedAt = ProfileNowMS()
    if not (startedAt and finishedAt) then return end
    local elapsed = math.max(0, finishedAt - startedAt)
    AddStat(totalField, elapsed)
    MaxStat(maxField, elapsed)
end

local function GetSecurity()
    return YUI.API and YUI.API.Security
end

local function IsSecret(value)
    local security = GetSecurity()
    return security
        and security.IsSecretValue
        and security.IsSecretValue(value) == true
end

local function SafeNumber(value)
    local security = GetSecurity()
    if security and security.SafeNumber then
        return security.SafeNumber(value)
    end
    if IsSecret(value) or type(value) ~= "number" then return nil end
    return value
end

local function SafeString(value)
    local security = GetSecurity()
    if security and security.SafeString then
        return security.SafeString(value)
    end
    if IsSecret(value) or type(value) ~= "string" then return nil end
    return value
end

local function SafeBoolean(value)
    local security = GetSecurity()
    if security and security.SafeBoolean then
        return security.SafeBoolean(value)
    end
    if IsSecret(value) or type(value) ~= "boolean" then return nil end
    return value
end

local function GetRuntimeTime()
    local combat = YUI.API and YUI.API.Combat
    if not (combat and combat.GetTime) then return nil end
    local ok, value = pcall(combat.GetTime)
    return ok and SafeNumber(value) or nil
end

local function IsInCombat()
    local combat = YUI.API and YUI.API.Combat
    if combat and combat.InCombatLockdown then
        local ok, value = pcall(combat.InCombatLockdown)
        return ok and value == true
    end
    local security = GetSecurity()
    if security and security.InCombatLockdown then
        local ok, value = pcall(security.InCombatLockdown)
        return ok and value == true
    end
    return false
end

local function ReadObjectField(object, fieldName)
    return object[fieldName]
end

local function SafeMethod(object, methodName, ...)
    if not object then return false, "missing-object" end
    local ok, method = pcall(ReadObjectField, object, methodName)
    if not ok or type(method) ~= "function" then
        return false, "missing-method"
    end
    return pcall(method, object, ...)
end

local function SafeField(object, fieldName)
    if not object then return false, "missing-object" end
    return pcall(ReadObjectField, object, fieldName)
end

local function IsEditModeActive()
    local manager = _G.EditModeManagerFrame
    if not manager then return false end
    local ok, shown = SafeMethod(manager, "IsShown")
    return ok and SafeBoolean(shown) == true
end

local function IsNativeEditModeActive()
    if NativeBridge.editModeActive == true then return true end
    if NativeBridge.editModeExitObserved == true then return false end
    return IsEditModeActive()
end

local function GetState(category)
    local state = NativeBridge.states[category]
    if not state then
        state = {
            category = category,
            status = "idle",
        }
        NativeBridge.states[category] = state
    end
    state.dynamicGroupBuffers = state.dynamicGroupBuffers or {}
    state.dirtyDynamicGroups = state.dirtyDynamicGroups or {}
    state.dirtyStaticGroups = state.dirtyStaticGroups or {}
    state.staleDynamicFrames = state.staleDynamicFrames or {}
    return state
end

local function SetStatus(state, status)
    state.status = status
end

local function EnsureOfficialAddon()
    local allPresent = true
    for index = 1, #DESCRIPTORS do
        if not _G[DESCRIPTORS[index].globalName] then
            allPresent = false
            break
        end
    end
    if allPresent then return true end
    if IsInCombat() then return false end

    local system = YUI.API and YUI.API.System
    if not (system and system.LoadAddOn) then return false end
    if system.IsAddOnLoadedSafe
        and system.IsAddOnLoadedSafe(OFFICIAL_ADDON) == true then
        return true
    end
    local ok, loadedOrLoading, reason = pcall(
        system.LoadAddOn,
        OFFICIAL_ADDON
    )
    NativeBridge.officialRuntimeLoadReason = ok and reason or loadedOrLoading
    return ok and loadedOrLoading == true
end

function NativeBridge:GetOfficialDataProvider()
    local settings = _G.CooldownViewerSettings
    if not (settings and type(settings.GetDataProvider) == "function") then
        return nil
    end
    local ok, provider = pcall(settings.GetDataProvider, settings)
    return ok and provider or nil
end

function NativeBridge:GetOfficialViewerPresence(target)
    target = target or {}
    local complete = true
    for index = 1, #DESCRIPTORS do
        local globalName = DESCRIPTORS[index].globalName
        local present = _G[globalName] ~= nil
        target[globalName] = present
        if not present then complete = false end
    end
    return target, complete
end

function NativeBridge:IsOfficialRuntimeReady()
    local loaded = EnsureOfficialAddon()
    local _, viewersReady = self:GetOfficialViewerPresence({})
    local providerReady = self:GetOfficialDataProvider() ~= nil
    if not loaded then return false, "addon-unavailable" end
    if not viewersReady then return false, "viewer-unavailable" end
    if not providerReady then return false, "data-provider-unavailable" end
    return true
end

function NativeBridge:GetOfficialRuntimeReadiness(target)
    target = target or {}
    local system = YUI.API and YUI.API.System
    target.addonLoaded = system and system.IsAddOnLoadedSafe
        and system.IsAddOnLoadedSafe(OFFICIAL_ADDON) == true or false
    target.viewers, target.viewersReady = self:GetOfficialViewerPresence(
        target.viewers or {}
    )
    target.dataProviderReady = self:GetOfficialDataProvider() ~= nil
    target.active = self.active == true
    target.ready = self.officialRuntimeReady == true
    target.pending = self.officialRuntimeTimer ~= nil
    target.reason = self.officialRuntimeReason
        or self.officialRuntimeLoadReason
    return target
end
local function SetAlphaIfChanged(state, frame, alpha, verify)
    if not frame or type(alpha) ~= "number" then return false end
    state.lastAlpha = state.lastAlpha or setmetatable({}, { __mode = "k" })
    if verify == true then
        local readOK, current = SafeMethod(frame, "GetAlpha")
        current = readOK and SafeNumber(current) or nil
        if current == alpha then
            state.lastAlpha[frame] = alpha
            return true, false
        end
    elseif state.lastAlpha[frame] == alpha then
        return true, false
    end
    local ok = SafeMethod(frame, "SetAlpha", alpha)
    if ok then state.lastAlpha[frame] = alpha end
    return ok, ok
end

local function GetAlphaBaseline(state, frame)
    state.alphaBaseline = state.alphaBaseline
        or setmetatable({}, { __mode = "k" })
    local alpha = state.alphaBaseline[frame]
    if alpha == nil then
        local ok, value = SafeMethod(frame, "GetAlpha")
        alpha = ok and SafeNumber(value) or 1
        state.alphaBaseline[frame] = alpha
    end
    return alpha
end

local function RestoreAlpha(state, frame, verify)
    if not frame then return true end
    return SetAlphaIfChanged(
        state,
        frame,
        GetAlphaBaseline(state, frame),
        verify
    )
end

local ApplyManagedFrameVisibility
local SetNativeTooltipMouseEnabled
local ApplyStaticFrameParking
local ApplyDynamicMemberLayout
local ApplyStaticMemberLayout

local function GetOfficialFrames(viewer)
    local frames = {}
    local pool = viewer and viewer.itemFramePool
    if pool then
        local ok = pcall(function()
            for frame in pool:EnumerateActive() do
                frames[#frames + 1] = frame
            end
        end)
        if ok then return frames, true end
    end

    local ok, container = SafeMethod(viewer, "GetItemContainerFrame")
    if ok and container then
        local layoutOk, layoutFrames = SafeMethod(
            container,
            "GetLayoutChildren"
        )
        if layoutOk and type(layoutFrames) == "table" then
            return layoutFrames, false
        end
    end
    ok, container = SafeMethod(viewer, "GetLayoutChildren")
    if ok and type(container) == "table" then return container, false end
    return frames, false
end

local function GetCooldownID(frame)
    local ok, cooldownID = SafeMethod(frame, "GetCooldownID")
    cooldownID = ok and SafeNumber(cooldownID) or nil
    if not cooldownID then
        local fieldOk, fieldValue = SafeField(frame, "cooldownID")
        cooldownID = fieldOk and SafeNumber(fieldValue) or nil
    end
    if not cooldownID or cooldownID <= 0 then return nil end
    return math.floor(cooldownID)
end

local function IsShown(frame)
    local ok, shown = SafeMethod(frame, "IsShown")
    return ok and SafeBoolean(shown) == true
end

local function BuildMonitorMap(profile, category, layout)
    local result = {}
    local hasSoundRules = false
    local groups = profile and profile.groups and profile.groups.items
    local view = YHUD.View
    local monitors = view and view.profile == profile
        and type(view.desiredMonitors) == "table"
        and view.desiredMonitors
        or (profile and profile.monitors or {})
    local entries = profile and profile.entries or {}
    local monitorCatalog = YHUD.MonitorCatalog
    local claimedSources = monitorCatalog
        and monitorCatalog.GetClaimedCooldownSources
        and monitorCatalog:GetClaimedCooldownSources(profile) or {}
    for monitorId, monitor in pairs(monitors) do
        local group = groups and groups[monitor.groupId]
        local entry = monitor and entries[monitor.entryKey]
        local availability = entry and YHUD.EvaluateEntryAvailability
            and YHUD:EvaluateEntryAvailability(
                entry,
                rawget(profile, "_yhudSpecKey")
            ) or "available"
        local persistentAuraOverlay = monitor
            and monitor.visibilityMode == "always"
            and category == "trackedBuff"
            and layout == "icons"
        if monitor and monitor.enabled ~= false
            and (monitor.visibilityMode ~= "always" or persistentAuraOverlay)
            and group and group.enabled == true
            and group.layout == layout
            and entry
            and (availability == "available"
                or category == "trackedBuff"
                or category == "trackedBar")
            and entry.origin == "official-cdm"
            and entry.officialCategory == category
            and not YHUD:IsOfficialEntryClaimed(
                entry,
                claimedSources,
                monitor._yhudParentMonitorId or monitorId
            )
            and type(entry.cooldownId) == "number" then
            local canUseAuraForCooldown =
                YHUD.CanConfigureSkillAuraDisplay
                and YHUD:CanConfigureSkillAuraDisplay(entry) == true
            local skillAuraDisplay = true
            if canUseAuraForCooldown
                and YHUD.GetEffectiveSkillAuraDisplay then
                skillAuraDisplay = YHUD:GetEffectiveSkillAuraDisplay(
                    profile,
                    monitor,
                    entry
                ) ~= false
            end
            local auraHighlight = YHUD.GetEffectiveSkillAuraHighlight
                and YHUD:GetEffectiveSkillAuraHighlight(
                    profile,
                    monitor,
                    entry
                ) == true
            local inactiveDesaturate = YHUD.GetEffectiveInactiveDesaturate
                and YHUD:GetEffectiveInactiveDesaturate(
                    profile,
                    monitor,
                    entry
                ) == true
            local appearance = type(monitor.appearanceOverride) == "table"
                and monitor.appearanceOverride or nil
            local soundRuntime = YHUD.Sound and YHUD.Sound.Compile
                and YHUD.Sound:Compile(profile, monitor) or nil
            if soundRuntime then hasSoundRules = true end
            local glowRuntime = YHUD.Glow and YHUD.Glow.Compile
                and YHUD.Glow:Compile(profile, monitor) or nil
            local hasCooldownRules = category == "essential"
                or category == "utility"
            hasCooldownRules = hasCooldownRules and (
                glowRuntime and glowRuntime.kind == "cooldown"
                    and type(glowRuntime.rules) == "table"
                    and #glowRuntime.rules > 0
                or soundRuntime and soundRuntime.kind == "cooldown"
                    and type(soundRuntime.rules) == "table"
                    and #soundRuntime.rules > 0
            ) or false
            local spellId = entry.overrideSpellId or entry.spellId
            local chargeSpellId = entry.chargeSpellId or spellId
            local spellEligible = (YHUD.GetEntrySemantic
                    and YHUD:GetEntrySemantic(entry)
                    or entry.semantic or "cooldown") == "cooldown"
                and entry.sourceType ~= "item-cooldown"
                and entry.sourceType ~= "yhud.inventory-slot-cooldown"
                and entry.itemId == nil and entry.itemID == nil
                and entry.slotId == nil
            local gcdEligible = spellEligible and layout == "icons"
                and (category == "essential" or category == "utility")
                and entry.equipSlot == nil
            local groupRuntime = view and view.profile == profile
                and view.groups and view.groups[monitor.groupId]
            local groupStyle = groupRuntime or (gcdEligible
                and YHUD.GetIconGroupStyle
                and YHUD:GetIconGroupStyle(profile, monitor.groupId))
            local cooldownGCD = not groupStyle or groupStyle.cooldownGCD ~= false
            result[entry.cooldownId] = {
                monitorId = monitorId,
                groupId = monitor.groupId,
                sourceKey = monitor.sourceKey,
                hasChargesHint = entry.charges == true,
                glowRuntime = glowRuntime,
                soundRuntime = soundRuntime,
                fillColor = appearance and appearance.fillColor or nil,
                trackColor = appearance and appearance.trackColor or nil,
                cooldownSwipeMode = appearance
                    and appearance.cooldownSwipeMode or nil,
                persistentAuraOverlay = persistentAuraOverlay == true,
                canUseAuraForCooldown = canUseAuraForCooldown,
                skillAuraDisplay = skillAuraDisplay,
                auraHighlight = auraHighlight,
                inactiveDesaturate = inactiveDesaturate,
                gcdEligible = gcdEligible,
                cooldownGCD = cooldownGCD,
                needsSkillAuraRefresh = (canUseAuraForCooldown == true
                    and (skillAuraDisplay == false
                        or auraHighlight == false
                        or inactiveDesaturate == true))
                    or gcdEligible,
                spellId = spellId,
                baseSpellId = entry.spellId,
                overrideSpellId = entry.overrideSpellId,
                chargeSpellId = chargeSpellId,
                cooldownCompletionEnabled = hasCooldownRules,
                cooldownCompletionCooldownSpellId = spellId,
                cooldownCompletionChargeSpellId = chargeSpellId,
                keybindSpellEligible = spellEligible,
            }
        end
    end
    return result, hasSoundRules
end

local function GetActiveConfigProfile()
    if YHUD.GetActiveProfile then
        return YHUD:GetActiveProfile(false)
    end
    return YHUD.GetConfigProfile and YHUD:GetConfigProfile() or nil
end

local function ColorComponents(color, defaultR, defaultG, defaultB, defaultA)
    color = type(color) == "table" and color or {}
    return tonumber(color.r or color[1]) or defaultR,
        tonumber(color.g or color[2]) or defaultG,
        tonumber(color.b or color[3]) or defaultB,
        tonumber(color.a or color[4]) or defaultA
end

local function CopyCompiledColor(target, source, r, g, b, a)
    target = target or {}
    local cr, cg, cb, ca = ColorComponents(source, r, g, b, a)
    target[1], target[2], target[3], target[4] = cr, cg, cb, ca
    return target
end

local function CopyCompiledTextStyle(target, source)
    target = target or {}
    source = type(source) == "table" and source or {}
    target.enabled = source.enabled ~= false
    target.font = source.font
    target.size = source.size
    target.outline = source.outline
    target.position = source.position
    target.anchor = source.anchor
    target.offsetX = source.offsetX
    target.offsetY = source.offsetY
    target.color = CopyCompiledColor(
        target.color,
        source.color,
        1,
        1,
        1,
        1
    )
    return target
end

local function BuildEffectiveStatusSnapshot(runtime, binding, styleState)
    local gui = YUI.GUI2
    local source = runtime.statusBarStyle
    if not source and gui and gui.CompileStatusBarStyle then
        source = gui:CompileStatusBarStyle(runtime)
    end
    if not source then return nil end
    local target = styleState.compiledStatus or {}
    target.texture = source.texture
    target.textureId = source.textureId
    target.textureU0 = source.textureU0
    target.textureU1 = source.textureU1
    target.textureV0 = source.textureV0
    target.textureV1 = source.textureV1
    target.fillColorMode = source.fillColorMode
    target.fillColor = CopyCompiledColor(
        target.fillColor,
        binding and binding.fillColor or source.fillColor,
        0.25,
        0.55,
        0.95,
        1
    )
    target.trackColor = CopyCompiledColor(
        target.trackColor,
        binding and binding.trackColor or source.trackColor,
        0.04,
        0.06,
        0.08,
        0.92
    )
    target.border = source.border
    target.borderThickness = source.borderThickness
    target.borderColor = CopyCompiledColor(
        target.borderColor,
        source.borderColor,
        1,
        1,
        1,
        1
    )
    target.showIcon = runtime.showIcon ~= false
    target.nameText = CopyCompiledTextStyle(target.nameText, source.nameText)
    if runtime.orientation == "vertical" then
        target.nameText.enabled = false
    end
    target.timeText = CopyCompiledTextStyle(target.timeText, source.timeText)
    target.countText = CopyCompiledTextStyle(target.countText, source.countText)
    styleState.compiledStatus = target
    return target
end

local function CaptureRegionGeometry(region)
    if not region then return nil end
    local geometry = {}
    local ok, width, height = SafeMethod(region, "GetSize")
    if ok then
        geometry.width = SafeNumber(width)
        geometry.height = SafeNumber(height)
    end
    local orientation
    ok, orientation = SafeMethod(region, "GetOrientation")
    geometry.orientation = ok and SafeString(orientation) or nil
    local reverseFill
    ok, reverseFill = SafeMethod(region, "GetReverseFill")
    geometry.reverseFill = ok and SafeBoolean(reverseFill) or nil
    local rotatesTexture
    ok, rotatesTexture = SafeMethod(region, "GetRotatesTexture")
    geometry.rotatesTexture = ok and SafeBoolean(rotatesTexture) or nil
    local fillStyle
    ok, fillStyle = SafeMethod(region, "GetFillStyle")
    geometry.fillStyle = ok and fillStyle or nil
    local points
    local pointCount = 0
    ok, pointCount = SafeMethod(region, "GetNumPoints")
    pointCount = ok and SafeNumber(pointCount) or nil
    if pointCount then
        points = {}
        for pointIndex = 1, pointCount do
            local pointOk, point, relative, relativePoint, x, y =
                SafeMethod(region, "GetPoint", pointIndex)
            point = pointOk and SafeString(point) or nil
            relativePoint = pointOk and SafeString(relativePoint) or nil
            x = pointOk and SafeNumber(x) or nil
            y = pointOk and SafeNumber(y) or nil
            if point and relativePoint and x and y then
                points[#points + 1] = {
                    point,
                    relative,
                    relativePoint,
                    x,
                    y,
                }
            end
        end
    end
    geometry.points = points
    local shown
    ok, shown = SafeMethod(region, "IsShown")
    geometry.shown = ok and SafeBoolean(shown) or nil
    local alpha
    ok, alpha = SafeMethod(region, "GetAlpha")
    geometry.alpha = ok and SafeNumber(alpha) or nil
    return geometry
end

local function RestoreRegionGeometry(region, geometry)
    if not (region and geometry) then return end
    if geometry.width and geometry.height then
        SafeMethod(region, "SetSize", geometry.width, geometry.height)
    end
    if geometry.orientation then
        SafeMethod(region, "SetOrientation", geometry.orientation)
    end
    if geometry.rotatesTexture ~= nil then
        SafeMethod(
            region,
            "SetRotatesTexture",
            geometry.rotatesTexture
        )
    end
    if geometry.fillStyle ~= nil then
        SafeMethod(region, "SetFillStyle", geometry.fillStyle)
    elseif geometry.reverseFill ~= nil then
        SafeMethod(region, "SetReverseFill", geometry.reverseFill)
    end
    if geometry.points then
        SafeMethod(region, "ClearAllPoints")
        for index = 1, #geometry.points do
            SafeMethod(region, "SetPoint", Unpack(geometry.points[index]))
        end
    end
    if geometry.shown ~= nil then
        SafeMethod(region, "SetShown", geometry.shown)
    end
    if geometry.alpha ~= nil then
        SafeMethod(region, "SetAlpha", geometry.alpha)
    end
end

local function SetRegionParentIfChanged(region, parent)
    if not (region and parent) then return false end
    local ok, current = SafeMethod(region, "GetParent")
    if ok and current == parent then return false end
    local setOK = SafeMethod(region, "SetParent", parent)
    return setOK == true
end

local function CaptureFontString(fontString, naturalSize)
    if not fontString then return nil end
    local state = {
        geometry = CaptureRegionGeometry(fontString),
        naturalSize = naturalSize == true,
    }
    if state.naturalSize and state.geometry then
        -- Countdown text is sized by the native Cooldown driver. Its measured
        -- width is content-dependent and must never become a fixed restore size.
        state.geometry.width = nil
        state.geometry.height = nil
    end
    local ok, parent = SafeMethod(fontString, "GetParent")
    state.parent = ok and parent or nil
    local font, size, flags
    ok, font, size, flags = SafeMethod(fontString, "GetFont")
    if ok then
        state.font = font
        state.size = size
        state.flags = flags
    end
    ok, state.r, state.g, state.b, state.a =
        SafeMethod(fontString, "GetTextColor")
    if not ok then
        state.r = nil
        state.g = nil
        state.b = nil
        state.a = nil
    end
    ok, state.drawLayer, state.drawSubLevel =
        SafeMethod(fontString, "GetDrawLayer")
    if not ok then
        state.drawLayer = nil
        state.drawSubLevel = nil
    end
    for _, property in ipairs({ "WordWrap", "NonSpaceWrap", "MaxLines", "JustifyV", "JustifyH" }) do
        local captured, value = SafeMethod(fontString, "Get" .. property)
        if captured then state[property] = value end
    end
    return state
end

local function RestoreFontString(fontString, state)
    if not (fontString and state) then return end
    for _, property in ipairs({ "WordWrap", "NonSpaceWrap", "MaxLines", "JustifyV", "JustifyH" }) do
        if state[property] ~= nil then
            SafeMethod(fontString, "Set" .. property, state[property])
        end
    end
    if state.parent then
        SafeMethod(fontString, "SetParent", state.parent)
    end
    if state.naturalSize == true then
        SafeMethod(fontString, "SetSize", 0, 0)
    end
    RestoreRegionGeometry(fontString, state.geometry)
    if state.font and state.size then
        SafeMethod(
            fontString,
            "SetFont",
            state.font,
            state.size,
            state.flags or ""
        )
    end
    if state.r then
        SafeMethod(
            fontString,
            "SetTextColor",
            state.r,
            state.g,
            state.b,
            state.a or 1
        )
    end
    if state.drawLayer then
        SafeMethod(
            fontString,
            "SetDrawLayer",
            state.drawLayer,
            state.drawSubLevel
        )
    end
end

local function SetFrameLevelIfChanged(frame, level)
    if not (frame and type(level) == "number") then return false end
    local ok, current = SafeMethod(frame, "GetFrameLevel")
    current = ok and SafeNumber(current) or nil
    if current == level then return false end
    return SafeMethod(frame, "SetFrameLevel", level) == true
end

local function GetSafeFrameLevel(frame)
    local ok, level = SafeMethod(frame, "GetFrameLevel")
    return ok and SafeNumber(level) or 0
end

local function SetFrameStrataIfChanged(frame, strata)
    if not (frame and type(strata) == "string") then return false end
    local ok, current = SafeMethod(frame, "GetFrameStrata")
    current = ok and SafeString(current) or nil
    if current == strata then return false end
    return SafeMethod(frame, "SetFrameStrata", strata) == true
end

local function CaptureFrameLayer(frame)
    if not frame then return nil end
    local levelOK, level = SafeMethod(frame, "GetFrameLevel")
    local strataOK, strata = SafeMethod(frame, "GetFrameStrata")
    if not levelOK and not strataOK then return nil end
    return {
        frame = frame,
        levelCaptured = levelOK == true,
        level = levelOK and SafeNumber(level) or nil,
        strataCaptured = strataOK == true,
        strata = strataOK and SafeString(strata) or nil,
    }
end

local function RestoreFrameLayer(record)
    if not (record and record.frame) then return false end
    local changed = false
    if record.strataCaptured == true and record.strata then
        changed = SetFrameStrataIfChanged(
            record.frame,
            record.strata
        ) or changed
    end
    if record.levelCaptured == true and record.level ~= nil then
        changed = SetFrameLevelIfChanged(
            record.frame,
            record.level
        ) or changed
    end
    return changed
end

local function EnsureFrameLayerRecord(styleState, key, frame)
    styleState.nativeFrameLayers = styleState.nativeFrameLayers or {}
    local record = styleState.nativeFrameLayers[key]
    if record and record.frame ~= frame then
        RestoreFrameLayer(record)
        record = nil
    end
    if not record and frame then
        record = CaptureFrameLayer(frame)
        styleState.nativeFrameLayers[key] = record
    end
    return record
end

local function ApplyFrameLayer(styleState, key, frame, strata, level)
    local record = EnsureFrameLayerRecord(styleState, key, frame)
    if not record then return false end
    local changed = SetFrameStrataIfChanged(frame, strata)
    changed = SetFrameLevelIfChanged(frame, level) or changed
    return changed
end

local function RestoreNativeFrameLayers(styleState)
    local records = styleState and styleState.nativeFrameLayers
    if not records then return false end
    local changed = false
    for key, record in pairs(records) do
        changed = RestoreFrameLayer(record) or changed
        records[key] = nil
    end
    styleState.nativeFrameLayers = nil
    styleState.nativeLayerRuntime = nil
    styleState.nativeLayerBinding = nil
    styleState.nativeDisplayLevel = nil
    styleState.nativeDisplayStrata = nil
    return changed
end

local function ApplyNativeFrameLayers(frame, styleState, runtime, binding)
    local view = YHUD.View
    if not (frame and styleState and runtime and view
        and view.GetMonitorDisplayLayer) then
        return false
    end
    local monitorId = binding and binding.monitorId
    local level, strata = view:GetMonitorDisplayLayer(runtime, monitorId)
    if not (level and strata) then return false end
    local changed = ApplyFrameLayer(
        styleState, "root", frame, strata, level
    )
    changed = ApplyFrameLayer(
        styleState, "icon", frame.Icon, strata, level + 1
    ) or changed
    changed = ApplyFrameLayer(
        styleState, "bar", frame.Bar, strata, level + 1
    ) or changed
    changed = ApplyFrameLayer(
        styleState, "debuffBorder", frame.DebuffBorder, strata, level + 12
    ) or changed
    local glowLevel = level + ICON_TEXT_FRAME_LEVEL_OFFSET - 1
    local gui = YUI.GUI2
    local customGlow = styleState.nativeCustomGlow
    if customGlow and customGlow._SetGlowLayerContext then
        changed = customGlow:_SetGlowLayerContext(
            glowLevel,
            strata
        ) or changed
    end
    local procGlow = styleState.nativeProcGlow
    if procGlow and gui and gui.LayoutManagedProcGlow
        and (styleState.nativeProcGlowFrameLevel ~= glowLevel
            or styleState.nativeProcGlowFrameStrata ~= strata) then
        local width = runtime.itemWidth or runtime.iconWidth
            or runtime.diameter or runtime.iconSize
        local height = runtime.itemHeight or runtime.iconHeight
            or runtime.diameter or runtime.iconSize
        local targetShape = runtime.view == "ring"
            and "circle" or runtime.shape or "square"
        gui:LayoutManagedProcGlow(
            procGlow,
            frame,
            width,
            height,
            glowLevel,
            strata,
            targetShape
        )
        styleState.nativeProcGlowFrameLevel = glowLevel
        styleState.nativeProcGlowFrameStrata = strata
        changed = true
    end
    styleState.nativeLayerRuntime = runtime
    styleState.nativeLayerBinding = binding
    styleState.nativeDisplayLevel = level
    styleState.nativeDisplayStrata = strata
    return changed
end

local function SetIconTextDrawLayer(text)
    if not text then return false end
    local ok, layer, subLevel = SafeMethod(text, "GetDrawLayer")
    layer = ok and SafeString(layer) or nil
    subLevel = ok and SafeNumber(subLevel) or nil
    if layer == ICON_TEXT_DRAW_LAYER
        and subLevel == ICON_TEXT_DRAW_SUBLEVEL then
        return false
    end
    return SafeMethod(
        text,
        "SetDrawLayer",
        ICON_TEXT_DRAW_LAYER,
        ICON_TEXT_DRAW_SUBLEVEL
    ) == true
end

local function GetNativeCountCarrier(frame, count)
    if not (frame and count) then return nil end
    if frame.ChargeCount and frame.ChargeCount.Current == count then
        return frame.ChargeCount
    end
    if frame.Applications and frame.Applications.Applications == count then
        return frame.Applications
    end
    local ok, parent = SafeMethod(count, "GetParent")
    return ok and parent or nil
end

local function RestoreNativeCountCarrierLevel(styleState)
    if not (styleState and styleState.countCarrier
        and styleState.countCarrierFrameLevelCaptured == true) then
        return false
    end
    local restored = SetFrameLevelIfChanged(
        styleState.countCarrier,
        styleState.countCarrierFrameLevel
    )
    styleState.countCarrier = nil
    styleState.countCarrierFrameLevel = nil
    styleState.countCarrierFrameLevelCaptured = nil
    return restored
end

function NativeBridge:_ResolveTextLayer(runtime, fallbackLevel)
    local view = YHUD.View
    if view and view.GetMonitorTextLayer then
        local level, strata = view:GetMonitorTextLayer(runtime)
        if level then return level, strata end
    end
    return fallbackLevel + ICON_TEXT_FRAME_LEVEL_OFFSET,
        runtime and runtime.displayLayerStrata
end

local function ApplyNativeIconTextLayers(
    frame,
    styleState,
    runtime,
    cooldownText,
    count
)
    if not (frame and styleState) then return false end
    if cooldownText
        and styleState.cooldownTextRegion ~= cooldownText then
        styleState.cooldownTextRegion = cooldownText
        styleState.cooldownFont = CaptureFontString(cooldownText, true)
    end
    local view = YHUD.View
    local binding = styleState.nativeBinding
        or styleState.nativeStyleBinding or styleState.binding
    runtime = runtime or styleState.nativeStyleRuntime
        or styleState.nativeLayerRuntime
        or binding and view and view.groups
            and view.groups[binding.groupId]
    local nativeAura = styleState.nativeCategory == "trackedBuff"
        or styleState.nativeCategory == "trackedBar"
    local level
    if nativeAura then
        level = styleState.nativeDisplayLevel
        if type(level) ~= "number"
            and runtime and view and view.GetMonitorDisplayLayer then
            level = view:GetMonitorDisplayLayer(
                runtime,
                binding and binding.monitorId
            )
        end
        if type(level) ~= "number" then
            local forbiddenOK, forbidden = SafeMethod(
                frame,
                "IsForbidden"
            )
            local protectedOK, protected = SafeMethod(
                frame,
                "IsProtected"
            )
            if forbiddenOK and protectedOK
                and SafeBoolean(forbidden) == false
                and SafeBoolean(protected) == false then
                local levelOK, currentLevel = SafeMethod(
                    frame,
                    "GetFrameLevel"
                )
                level = levelOK and SafeNumber(currentLevel) or nil
            end
        end
    else
        local levelOK, currentLevel = SafeMethod(frame, "GetFrameLevel")
        level = levelOK and SafeNumber(currentLevel) or 0
    end
    level = type(level) == "number" and level or 0
    local textLevel = NativeBridge:_ResolveTextLayer(
        runtime,
        level
    )
    local changed = false
    local cooldown = frame.Cooldown
    if cooldown
        and styleState.cooldownFrameLevelCaptured ~= true then
        local ok, original = SafeMethod(cooldown, "GetFrameLevel")
        styleState.cooldownFrameLevel = ok and SafeNumber(original) or nil
        styleState.cooldownFrameLevelCaptured = ok == true
    end
    changed = SetFrameLevelIfChanged(
        cooldown,
        level + ICON_COOLDOWN_FRAME_LEVEL_OFFSET
    ) or changed
    changed = SetIconTextDrawLayer(cooldownText) or changed

    local carrier = GetNativeCountCarrier(frame, count)
    if carrier ~= styleState.countCarrier then
        RestoreNativeCountCarrierLevel(styleState)
        if carrier then
            local ok, original = SafeMethod(carrier, "GetFrameLevel")
            styleState.countCarrier = carrier
            styleState.countCarrierFrameLevel =
                ok and SafeNumber(original) or nil
            styleState.countCarrierFrameLevelCaptured = ok == true
        end
    end
    changed = SetFrameLevelIfChanged(
        carrier,
        textLevel
    ) or changed
    changed = SetIconTextDrawLayer(count) or changed
    return changed
end

local function GetFrameStyleState(frame)
    local state = NativeBridge.frameStates[frame]
    if state then return state end
    state = {
        iconState = {},
        cooldownState = {},
        statusState = {},
    }
    NativeBridge.frameStates[frame] = state
    AddStat("frameStateCreates")
    if frame.GetScale then
        local ok, value = pcall(frame.GetScale, frame)
        if ok then state.scale = value end
    end
    if frame.GetSize then
        local ok, width, height = pcall(frame.GetSize, frame)
        if ok then
            state.width = SafeNumber(width)
            state.height = SafeNumber(height)
        end
    end
    return state
end

local function SameGeometryNumber(left, right)
    return type(left) == "number"
        and type(right) == "number"
        and math.abs(left - right) < 0.001
end

local function ClearDynamicIconGeometry(styleState)
    if not styleState then return end
    styleState.dynamicGeometryCooldownID = nil
    styleState.dynamicGeometryPoint = nil
    styleState.dynamicGeometryRelative = nil
    styleState.dynamicGeometryRelativePoint = nil
    styleState.dynamicGeometryOffsetX = nil
    styleState.dynamicGeometryOffsetY = nil
    styleState.dynamicGeometryWidth = nil
    styleState.dynamicGeometryHeight = nil
    styleState.dynamicGeometryScale = nil
    styleState.dynamicGeometryWrite = nil
    styleState.repairingDynamicGeometry = nil
end

local function SetDynamicIconGeometryIdentity(styleState, cooldownID)
    if not styleState then return false end
    cooldownID = SafeNumber(cooldownID)
    if styleState.dynamicGeometryCooldownID == cooldownID then return true end
    ClearDynamicIconGeometry(styleState)
    styleState.dynamicGeometryCooldownID = cooldownID
    return cooldownID ~= nil
end

local function CaptureDynamicIconSizeScale(frame, styleState)
    if not (frame and styleState) then return false end
    local cooldownID = GetCooldownID(frame)
    if not cooldownID or cooldownID ~= styleState.cooldownID then
        ClearDynamicIconGeometry(styleState)
        return false
    end
    styleState.dynamicGeometryCooldownID = cooldownID
    local sizeOK, width, height = SafeMethod(frame, "GetSize")
    width = sizeOK and SafeNumber(width) or nil
    height = sizeOK and SafeNumber(height) or nil
    styleState.dynamicGeometryWidth = width
    styleState.dynamicGeometryHeight = height
    local scaleOK, scale = SafeMethod(frame, "GetScale")
    styleState.dynamicGeometryScale = scaleOK and SafeNumber(scale) or nil
    return width ~= nil and height ~= nil
end

local function CaptureDynamicIconGeometry(frame, styleState)
    if not CaptureDynamicIconSizeScale(frame, styleState) then return false end
    local countOK, pointCount = SafeMethod(frame, "GetNumPoints")
    pointCount = countOK and SafeNumber(pointCount) or nil
    if pointCount ~= 1 then
        styleState.dynamicGeometryPoint = nil
        styleState.dynamicGeometryRelative = nil
        styleState.dynamicGeometryRelativePoint = nil
        styleState.dynamicGeometryOffsetX = nil
        styleState.dynamicGeometryOffsetY = nil
        return false
    end
    local pointOK, point, relativeTo, relativePoint, offsetX, offsetY =
        SafeMethod(frame, "GetPoint", 1)
    point = pointOK and SafeString(point) or nil
    relativePoint = pointOK and SafeString(relativePoint) or nil
    offsetX = pointOK and SafeNumber(offsetX) or nil
    offsetY = pointOK and SafeNumber(offsetY) or nil
    if not (point and relativePoint and offsetX and offsetY) then
        styleState.dynamicGeometryPoint = nil
        styleState.dynamicGeometryRelative = nil
        styleState.dynamicGeometryRelativePoint = nil
        styleState.dynamicGeometryOffsetX = nil
        styleState.dynamicGeometryOffsetY = nil
        return false
    end
    styleState.dynamicGeometryPoint = point
    styleState.dynamicGeometryRelative = relativeTo
    styleState.dynamicGeometryRelativePoint = relativePoint
    styleState.dynamicGeometryOffsetX = offsetX
    styleState.dynamicGeometryOffsetY = offsetY
    return true
end

local function DynamicIconGeometryIsManaged(frame, styleState)
    if not NativeBridge.active or IsNativeEditModeActive()
        or not (frame and styleState)
        or NativeBridge.dynamicGeometryLayoutWrite == true
        or styleState.dynamicGeometryWrite == true
        or styleState.repairingDynamicGeometry == true
        or styleState.nativeCategory ~= "trackedBuff"
        or styleState.nativeManaged ~= true
        or styleState.nativeIncluded ~= true
        or not IsShown(frame) then
        return false
    end
    local state = NativeBridge.states.trackedBuff
    if not (state and state.dynamicMembers
        and state.dynamicMembers[frame] == styleState) then
        return false
    end
    local cooldownID = GetCooldownID(frame)
    if not cooldownID
        or cooldownID ~= styleState.cooldownID
        or cooldownID ~= styleState.dynamicGeometryCooldownID then
        ClearDynamicIconGeometry(styleState)
        return false
    end
    return true
end

local function DynamicIconPointMatches(frame, styleState)
    local expectedPoint = styleState.dynamicGeometryPoint
    if not expectedPoint then return true end
    local countOK, pointCount = SafeMethod(frame, "GetNumPoints")
    pointCount = countOK and SafeNumber(pointCount) or nil
    if pointCount ~= 1 then return false end
    local pointOK, point, relativeTo, relativePoint, offsetX, offsetY =
        SafeMethod(frame, "GetPoint", 1)
    if not pointOK then return false end
    return point == expectedPoint
        and relativeTo == styleState.dynamicGeometryRelative
        and relativePoint == styleState.dynamicGeometryRelativePoint
        and SameGeometryNumber(
            SafeNumber(offsetX),
            styleState.dynamicGeometryOffsetX
        )
        and SameGeometryNumber(
            SafeNumber(offsetY),
            styleState.dynamicGeometryOffsetY
        )
end

local function RepairDynamicIconPoint(frame, styleState)
    if not styleState.dynamicGeometryPoint
        or DynamicIconPointMatches(frame, styleState) then
        return false, false
    end
    styleState.repairingDynamicGeometry = true
    local clearOK = SafeMethod(frame, "ClearAllPoints")
    local pointOK = SafeMethod(
        frame,
        "SetPoint",
        styleState.dynamicGeometryPoint,
        styleState.dynamicGeometryRelative,
        styleState.dynamicGeometryRelativePoint,
        styleState.dynamicGeometryOffsetX,
        styleState.dynamicGeometryOffsetY
    )
    styleState.repairingDynamicGeometry = nil
    return clearOK and pointOK, not (clearOK and pointOK)
end

local function RepairDynamicIconSize(frame, styleState)
    local expectedWidth = styleState.dynamicGeometryWidth
    local expectedHeight = styleState.dynamicGeometryHeight
    if not (expectedWidth and expectedHeight) then return false, false end
    local sizeOK, width, height = SafeMethod(frame, "GetSize")
    width = sizeOK and SafeNumber(width) or nil
    height = sizeOK and SafeNumber(height) or nil
    if sizeOK
        and SameGeometryNumber(width, expectedWidth)
        and SameGeometryNumber(height, expectedHeight) then
        return false, false
    end
    styleState.repairingDynamicGeometry = true
    local writeOK = SafeMethod(frame, "SetSize", expectedWidth, expectedHeight)
    styleState.repairingDynamicGeometry = nil
    return writeOK == true, writeOK ~= true
end

local function RepairDynamicIconScale(frame, styleState)
    local expectedScale = styleState.dynamicGeometryScale
    if not expectedScale then return false, false end
    local scaleOK, scale = SafeMethod(frame, "GetScale")
    scale = scaleOK and SafeNumber(scale) or nil
    if scaleOK and SameGeometryNumber(scale, expectedScale) then
        return false, false
    end
    styleState.repairingDynamicGeometry = true
    local writeOK = SafeMethod(frame, "SetScale", expectedScale)
    styleState.repairingDynamicGeometry = nil
    return writeOK == true, writeOK ~= true
end

local function AuditDynamicIconGeometry(
    frame,
    checkPoint,
    checkSize,
    checkScale
)
    local styleState = frame and NativeBridge.frameStates[frame]
    if not DynamicIconGeometryIsManaged(frame, styleState) then
        return false, false
    end
    local repaired = false
    local failed = false
    local wrote, writeFailed
    if checkPoint == true then
        wrote, writeFailed = RepairDynamicIconPoint(frame, styleState)
        repaired = wrote or repaired
        failed = writeFailed or failed
    end
    if checkSize == true then
        wrote, writeFailed = RepairDynamicIconSize(frame, styleState)
        repaired = wrote or repaired
        failed = writeFailed or failed
    end
    if checkScale == true then
        wrote, writeFailed = RepairDynamicIconScale(frame, styleState)
        repaired = wrote or repaired
        failed = writeFailed or failed
    end
    return repaired, failed
end

local function RecordDynamicGeometryRepair(statField, repaired, failed)
    if repaired then AddStat(statField) end
    if failed then AddStat("geometryRepairFailures") end
end

local function OnDynamicTrackedBuffSetPoint(frame)
    RecordDynamicGeometryRepair(
        "geometryHookRepairs",
        AuditDynamicIconGeometry(frame, true, false, false)
    )
end

local function OnDynamicTrackedBuffSetSize(frame)
    RecordDynamicGeometryRepair(
        "geometryHookRepairs",
        AuditDynamicIconGeometry(frame, false, true, false)
    )
end

local function OnDynamicTrackedBuffSetScale(frame)
    RecordDynamicGeometryRepair(
        "geometryHookRepairs",
        AuditDynamicIconGeometry(frame, false, false, true)
    )
end

local function InstallDynamicTrackedBuffGeometryHooks(frame)
    if not frame then return false end
    local hook = _G.hooksecurefunc
    if type(hook) ~= "function" then return false end
    local installed = false
    if not NativeBridge.dynamicPointHookedFrames[frame]
        and type(frame.SetPoint) == "function" then
        local ok = pcall(
            hook,
            frame,
            "SetPoint",
            OnDynamicTrackedBuffSetPoint
        )
        if ok then NativeBridge.dynamicPointHookedFrames[frame] = true end
        installed = installed or ok
    end
    if not NativeBridge.dynamicSizeHookedFrames[frame]
        and type(frame.SetSize) == "function" then
        local ok = pcall(
            hook,
            frame,
            "SetSize",
            OnDynamicTrackedBuffSetSize
        )
        if ok then NativeBridge.dynamicSizeHookedFrames[frame] = true end
        installed = installed or ok
    end
    if not NativeBridge.dynamicScaleHookedFrames[frame]
        and type(frame.SetScale) == "function" then
        local ok = pcall(
            hook,
            frame,
            "SetScale",
            OnDynamicTrackedBuffSetScale
        )
        if ok then NativeBridge.dynamicScaleHookedFrames[frame] = true end
        installed = installed or ok
    end
    return installed
end

function NativeBridge:BeginDynamicGeometryLayout()
    self.dynamicGeometryLayoutDepth =
        (tonumber(self.dynamicGeometryLayoutDepth) or 0) + 1
    self.dynamicGeometryLayoutWrite = true
    return self.dynamicGeometryLayoutDepth
end

function NativeBridge:AbortDynamicGeometryLayout()
    self.dynamicGeometryLayoutDepth = nil
    self.dynamicGeometryLayoutWrite = nil
end

function NativeBridge:FinishDynamicGeometryLayout(byMonitor, frames)
    local depth = tonumber(self.dynamicGeometryLayoutDepth) or 0
    if depth > 1 then
        self.dynamicGeometryLayoutDepth = depth - 1
        return false
    end
    self.dynamicGeometryLayoutDepth = nil
    if byMonitor then
        for _, frame in pairs(byMonitor) do
            local styleState = self.frameStates[frame]
            if styleState and styleState.nativeCategory == "trackedBuff" then
                CaptureDynamicIconGeometry(frame, styleState)
            end
        end
    end
    if frames then
        for index = 1, #frames do
            local frame = frames[index]
            local styleState = self.frameStates[frame]
            if styleState and styleState.nativeCategory == "trackedBuff" then
                CaptureDynamicIconGeometry(frame, styleState)
            end
        end
    end
    self.dynamicGeometryLayoutWrite = nil
    return true
end

local function ApplyFont(fontString, appearance)
    local gui = YUI.GUI2
    if gui and gui.ApplyFontAppearance then
        pcall(gui.ApplyFontAppearance, gui, fontString, appearance)
    end
end

local function CaptureTargetMasks(target)
    local masks = {}
    if not target then return masks end
    local ok, count = SafeMethod(target, "GetNumMaskTextures")
    count = ok and SafeNumber(count) or nil
    if not count then return masks end
    for index = 1, count do
        local maskOK, mask =
            SafeMethod(target, "GetMaskTexture", index)
        if maskOK and mask then masks[#masks + 1] = mask end
    end
    for index = 1, #masks do
        SafeMethod(target, "RemoveMaskTexture", masks[index])
    end
    return masks
end

local function RestoreTargetMasks(target, masks)
    if not (target and masks) then return end
    for index = 1, #masks do
        SafeMethod(target, "AddMaskTexture", masks[index])
    end
end

local function CaptureOwnerMaskTextures(owner, target)
    local masks = {}
    if not (owner and owner.GetRegions and target) then return masks end
    local packed = { pcall(owner.GetRegions, owner) }
    if not packed[1] then return masks end
    for index = 2, #packed do
        local region = packed[index]
        local typeOK, objectType = SafeMethod(region, "GetObjectType")
        objectType = typeOK and SafeString(objectType) or nil
        local isMask = objectType == "MaskTexture"
        if not isMask then
            local maskOK, result =
                SafeMethod(region, "IsObjectType", "MaskTexture")
            isMask = maskOK and result == true
        end
        if isMask then
            masks[#masks + 1] = region
            SafeMethod(target, "RemoveMaskTexture", region)
        end
    end
    return masks
end

local function CaptureOfficialIconOverlays(owner)
    local overlays = {}
    if not (owner and owner.GetRegions) then return overlays end
    local packed = { pcall(owner.GetRegions, owner) }
    if not packed[1] then return overlays end
    for index = 2, #packed do
        local region = packed[index]
        local atlasOK, atlas = SafeMethod(region, "GetAtlas")
        local textureOK, texture = SafeMethod(region, "GetTexture")
        atlas = atlasOK and SafeString(atlas) or nil
        texture = textureOK and SafeNumber(texture) or nil
        if atlas == OFFICIAL_ICON_OVERLAY_ATLAS
            or texture == OFFICIAL_ICON_OVERLAY_TEXTURE then
            local alphaOK, alpha = SafeMethod(region, "GetAlpha")
            overlays[#overlays + 1] = {
                region = region,
                alpha = alphaOK and SafeNumber(alpha) or 1,
            }
            SafeMethod(region, "SetAlpha", 0)
        end
    end
    return overlays
end

local function CreateBorderEdges(gui, owner)
    local edges = {}
    local function Edge()
        return gui:CreateTexture(owner, {
            layer = "OVERLAY",
            subLevel = 7,
        })
    end
    edges.top = Edge()
    edges.bottom = Edge()
    edges.left = Edge()
    edges.right = Edge()
    edges.top:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0)
    edges.top:SetPoint("TOPRIGHT", owner, "TOPRIGHT", 0, 0)
    edges.bottom:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", 0, 0)
    edges.bottom:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0)
    edges.left:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0)
    edges.left:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", 0, 0)
    edges.right:SetPoint("TOPRIGHT", owner, "TOPRIGHT", 0, 0)
    edges.right:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0)
    return edges
end

local function SetEdgeThickness(edges, thickness, owner, pixelSize)
    if not edges then return end
    local logical = math.max(1, tonumber(thickness) or 1)
    local gui = YUI.GUI2
    local size = tonumber(pixelSize)
        or (gui and gui.GetPixelSize
            and gui:GetPixelSize(owner, logical, logical))
        or math.max(1, logical * ((gui and gui.mult) or 1))
    if gui and gui.LayoutPixelBorder and owner then
        gui:LayoutPixelBorder(
            edges,
            owner,
            logical,
            0,
            0,
            size
        )
        return
    end
    edges.top:SetHeight(size)
    edges.bottom:SetHeight(size)
    edges.left:SetWidth(size)
    edges.right:SetWidth(size)
end

local function EnsureNativeIconChrome(
    owner,
    icon,
    cooldown,
    styleState,
    snapshot
)
    local gui = YUI.GUI2
    if not (gui and gui.CreateTexture and owner and icon) then
        return nil
    end
    local chrome = styleState.nativeIconChrome
    if not chrome then
        AddStat("iconChromeCreates")
        local iconMasks = CaptureTargetMasks(icon)
        local rangeOK, outOfRange =
            SafeMethod(owner, "GetOutOfRangeTexture")
        if not (rangeOK and outOfRange) then
            outOfRange = owner.OutOfRange
        end
        chrome = {
            owner = owner,
            icon = icon,
            cooldown = cooldown,
            outOfRange = outOfRange,
            iconMasks = iconMasks,
            cooldownMasks = CaptureTargetMasks(cooldown),
            outOfRangeMasks = CaptureTargetMasks(outOfRange),
            ownerIconMasks = #iconMasks == 0
                and CaptureOwnerMaskTextures(owner, icon) or {},
            overlays = CaptureOfficialIconOverlays(owner),
        }
        chrome.background = gui:CreateTexture(owner, {
            layer = "BACKGROUND",
            subLevel = -7,
        })
        chrome.background:SetAllPoints(owner)
        chrome.edges = CreateBorderEdges(gui, owner)
        chrome.shapeBorder = gui:CreateTexture(owner, {
            layer = "OVERLAY",
            subLevel = 7,
        })
        chrome.shapeBorder:SetAllPoints(owner)
        if owner.CreateMaskTexture then
            local ok, mask = pcall(
                owner.CreateMaskTexture,
                owner,
                nil,
                "BACKGROUND"
            )
            if ok then
                chrome.mask = mask
                mask:SetAllPoints(owner)
            end
        end
        chrome.target = {
            icon = icon,
            background = chrome.background,
            mask = chrome.mask,
        }
        chrome.target.SetBorderThickness = function(
            target,
            thickness,
            pixelSize
        )
            SetEdgeThickness(
                chrome.edges,
                thickness,
                owner,
                pixelSize
            )
            local family = chrome.family
            local paths = family
                and gui.IconAppearanceBorderTextures
                and gui.IconAppearanceBorderTextures[family]
            local path = paths and paths[thickness]
            if path then chrome.shapeBorder:SetTexture(path) end
        end
        styleState.nativeIconChrome = chrome
    end

    local family = snapshot and snapshot.borderFamily
    if chrome.family ~= family or chrome.target.border == nil then
        chrome.family = family
        chrome.target.border = family
            and chrome.shapeBorder or chrome.edges
        styleState.iconState.borderColor = nil
        styleState.iconState.borderShown = nil
        styleState.iconState.borderThickness = nil
        chrome.shapeBorder:Hide()
        for _, edge in pairs(chrome.edges) do edge:Hide() end
    end
    local paths = family
        and gui.IconAppearanceBorderTextures
        and gui.IconAppearanceBorderTextures[family]
    local thickness = snapshot and snapshot.borderThickness or 0
    local path = paths and paths[thickness]
    if path then chrome.shapeBorder:SetTexture(path) end
    SetEdgeThickness(chrome.edges, thickness, owner)

    local maskPath = snapshot and snapshot.mask
    if chrome.mask and maskPath then
        chrome.mask:SetTexture(
            maskPath,
            "CLAMPTOBLACKADDITIVE",
            "CLAMPTOBLACKADDITIVE"
        )
        SafeMethod(icon, "AddMaskTexture", chrome.mask)
        SafeMethod(cooldown, "AddMaskTexture", chrome.mask)
        SafeMethod(chrome.background, "AddMaskTexture", chrome.mask)
        SafeMethod(chrome.outOfRange, "AddMaskTexture", chrome.mask)
    elseif chrome.mask then
        SafeMethod(icon, "RemoveMaskTexture", chrome.mask)
        SafeMethod(cooldown, "RemoveMaskTexture", chrome.mask)
        SafeMethod(chrome.background, "RemoveMaskTexture", chrome.mask)
        SafeMethod(chrome.outOfRange, "RemoveMaskTexture", chrome.mask)
    end
    return chrome.target
end

local function EnsureNativeStatusChrome(bar, styleState)
    local gui = YUI.GUI2
    if not (gui and gui.CreateTexture and bar) then return nil end
    local chrome = styleState.nativeStatusChrome
    if chrome then return chrome.target end
    chrome = {}
    AddStat("statusChromeCreates")
    chrome.track = gui:CreateTexture(bar, {
        layer = "BACKGROUND",
        subLevel = -7,
    })
    chrome.track:SetAllPoints(bar)
    chrome.overlay = CreateFrame("Frame", nil, bar)
    chrome.overlay:SetAllPoints(bar)
    if chrome.overlay.SetFrameLevel then
        SafeMethod(
            chrome.overlay,
            "SetFrameLevel",
            GetSafeFrameLevel(bar) + 2
        )
    end
    chrome.edges = gui.EnsureStatusBarBorder
        and gui:EnsureStatusBarBorder(chrome.overlay)
        or CreateBorderEdges(gui, chrome.overlay)
    chrome.target = {
        track = chrome.track,
        border = chrome.edges,
    }
    chrome.target.SetBorderThickness = function(
        _,
        thickness,
        pixelSize
    )
        SetEdgeThickness(
            chrome.edges,
            thickness,
            chrome.overlay,
            pixelSize
        )
    end
    styleState.nativeStatusChrome = chrome
    return chrome.target
end

local function SuppressNativeRegionWhileStyled(
    frame,
    styleState,
    region,
    key
)
    if not (region and key) then return end
    SafeMethod(region, "SetAlpha", 0)
    SafeMethod(region, "Hide")
end

local function SuppressDebuffBorderWhileStyled(frame, styleState)
    local border = frame and frame.DebuffBorder
    if not border then return false end
    if styleState.debuffBorder and styleState.debuffBorder ~= border then
        SafeMethod(
            styleState.debuffBorder,
            "SetAlpha",
            styleState.debuffBorderAlpha or 1
        )
        SafeMethod(
            styleState.debuffBorderTexture,
            "SetAlpha",
            styleState.debuffBorderTextureAlpha or 1
        )
    end
    if styleState.debuffBorder ~= border then
        styleState.debuffBorder = border
        local ok, alpha = SafeMethod(border, "GetAlpha")
        styleState.debuffBorderAlpha = ok and SafeNumber(alpha) or 1
        styleState.debuffBorderTexture = border.Texture
        local textureOK, textureAlpha = SafeMethod(
            styleState.debuffBorderTexture,
            "GetAlpha"
        )
        styleState.debuffBorderTextureAlpha =
            textureOK and SafeNumber(textureAlpha) or 1
    end
    SafeMethod(border, "SetAlpha", 0)
    SafeMethod(styleState.debuffBorderTexture, "SetAlpha", 0)
    return true
end

local function SetNativeProcGlowShown(styleState, shown)
    local gui = YUI.GUI2
    local glow = styleState and styleState.nativeProcGlow
    if not (gui and gui.SetManagedProcGlowShown and glow) then
        return false
    end
    if styleState.nativeProcAlert then
        local alphaOK, alpha = SafeMethod(
            styleState.nativeProcAlert,
            "GetAlpha"
        )
        if not alphaOK or SafeNumber(alpha) ~= 0 then
            SafeMethod(styleState.nativeProcAlert, "SetAlpha", 0)
        end
    end
    if styleState.nativeProcGlowShown == (shown == true) then
        return false
    end
    styleState.nativeProcGlowShown = shown == true
    gui:SetManagedProcGlowShown(glow, shown == true)
    return true
end

function NativeBridge:_NormalizeProcGlowShape(snapshot)
    local shape = snapshot and snapshot.shape
    return shape == "circle" and "circle" or "square"
end

function NativeBridge:_ResolveCustomGlowShape(snapshot, appearance)
    if appearance and appearance.style == "proc" then
        return self:_NormalizeProcGlowShape(snapshot)
    end
    return snapshot and snapshot.shape or "square"
end

local ArmNativeCooldownCompletion

local function RefreshNativeCooldownGlowState(frame, styleState)
    local binding = styleState and (styleState.nativeBinding
        or styleState.nativeStyleBinding or styleState.binding)
    local glowCompiled = binding and binding.glowRuntime
    local soundCompiled = binding and binding.soundRuntime
    local hasGlowRules = glowCompiled and glowCompiled.kind == "cooldown"
        and type(glowCompiled.rules) == "table"
        and #glowCompiled.rules > 0
    local hasSoundRules = soundCompiled and soundCompiled.kind == "cooldown"
        and type(soundCompiled.rules) == "table"
        and #soundCompiled.rules > 0
    if not hasGlowRules and not hasSoundRules then
        if styleState then styleState.nativeGlowCooldownState = nil end
        return nil
    end

    local state = styleState.nativeGlowCooldownState
    if not state then
        state = {
            sourceKind = "spell",
            cooldownActive = false,
            chargeActive = false,
            available = false,
            secret = true,
        }
        styleState.nativeGlowCooldownState = state
    end

    local spell = YUI.API and YUI.API.Spell
    local cooldownActive, cooldownResolved = false, false
    local gcdOK, gcdValue = SafeField(frame, "isOnGCD")
    local nativeGCD
    if gcdOK then nativeGCD = SafeBoolean(gcdValue) end
    if nativeGCD == true then
        return state
    end

    local actualOK, actualValue = SafeField(
        frame,
        "isOnActualCooldown"
    )
    local nativeActual
    if actualOK then nativeActual = SafeBoolean(actualValue) end
    if nativeActual ~= nil then
        cooldownActive = nativeActual == true
        cooldownResolved = true
    elseif spell and spell.ReadCooldownRuleState and binding.spellId then
        cooldownActive, cooldownResolved =
            spell.ReadCooldownRuleState(binding.spellId)
        cooldownActive = cooldownActive == true
        cooldownResolved = cooldownResolved == true
    end
    local chargeActive = false
    local chargeResolved = true
    local completionMode = "cooldown"
    if binding.hasChargesHint == true then
        local chargeInfoOK, chargeInfo = SafeField(
            frame,
            "cachedSpellChargeInfo"
        )
        if not chargeInfoOK or chargeInfo == nil
            or type(chargeInfo) ~= "table" then
            chargeResolved = false
        else
            local activeOK, activeValue = SafeField(
                chargeInfo,
                "isActive"
            )
            local maximumOK, maximumValue = SafeField(
                chargeInfo,
                "maxCharges"
            )
            local active
            if activeOK then
                active = SafeBoolean(activeValue)
            end
            local maximum
            if maximumOK then
                maximum = SafeNumber(maximumValue)
            end
            if maximum ~= nil then
                maximum = math.floor(maximum + 0.5)
                if maximum < 1 or maximum > 20 then maximum = nil end
            end
            if active == nil or maximum == nil then
                chargeResolved = false
            elseif maximum > 1 then
                chargeActive = active == true
                completionMode = "charge"
            end
        end
    end

    local resolved = cooldownResolved == true and chargeResolved == true
    state.cooldownActive = resolved and cooldownActive == true or false
    state.chargeActive = resolved and chargeActive == true or false
    state.available = resolved
    state.secret = not resolved
    if resolved and ArmNativeCooldownCompletion then
        ArmNativeCooldownCompletion(
            binding,
            frame,
            cooldownActive == true or chargeActive == true,
            completionMode
        )
    end
    return state
end

local function SyncNativeProcGlow(
    frame,
    styleState,
    snapshot,
    inCombatOverride,
    chargeCompleted
)
    local gui = YUI.GUI2
    if not (gui and frame and styleState) then
        return false
    end
    local alert = frame.SpellActivationAlert
    if alert and styleState.nativeProcAlert ~= alert then
        if styleState.nativeProcAlert then
            SafeMethod(
                styleState.nativeProcAlert,
                "SetAlpha",
                styleState.nativeProcAlertAlpha or 1
            )
        end
        styleState.nativeProcAlert = alert
        local ok, alpha = SafeMethod(alert, "GetAlpha")
        styleState.nativeProcAlertAlpha =
            ok and SafeNumber(alpha) or 1
    end
    local nativeSignal = alert and IsShown(alert) or false
    if alert then
        local alphaOK, alpha = SafeMethod(alert, "GetAlpha")
        if not alphaOK or SafeNumber(alpha) ~= 0 then
            SafeMethod(alert, "SetAlpha", 0)
        end
    end
    local binding = styleState.nativeBinding
        or styleState.nativeStyleBinding
        or styleState.binding
    local compiled = binding and binding.glowRuntime
    local state = binding and binding.sourceKey and YHUD.Model
        and YHUD.Model:GetState(binding.sourceKey)
        or styleState.nativeGlowCooldownState
    local category = styleState.nativeCategory
    local auraPresent = (category == "trackedBuff" or category == "trackedBar")
        and styleState.nativeIncluded == true
    local inCombat = SafeBoolean(inCombatOverride)
    if inCombat == nil then inCombat = IsInCombat() end
    local kind, appearance
    if YHUD.Glow and YHUD.Glow.Resolve then
        kind, appearance = YHUD.Glow:Resolve(
            compiled,
            state,
            inCombat,
            false,
            nativeSignal,
            auraPresent and true or nil,
            auraPresent,
            false
        )
    end
    if not compiled and nativeSignal == true then
        kind = "native-default"
    end
    if styleState.visibilitySuppressed == true then
        kind = nil
        appearance = nil
    end

    local view = YHUD.View
    local monitor = binding and binding.monitorId and view
        and view.desiredMonitors
        and view.desiredMonitors[binding.monitorId]
    local nativeAura = category == "trackedBuff"
        or category == "trackedBar"
    local runtime = binding and view and view.groups
        and view.groups[binding.groupId]
    local trustedDisplayWidth = runtime and (
        runtime.itemWidth or runtime.iconWidth
            or runtime.diameter or runtime.iconSize
    ) or nil
    local trustedDisplayHeight = runtime and (
        runtime.itemHeight or runtime.iconHeight
            or runtime.diameter or runtime.iconSize
    ) or nil
    local trustedWidth = nativeAura and (
        trustedDisplayWidth or 42
    ) or nil
    local trustedHeight = nativeAura and (
        trustedDisplayHeight or 42
    ) or nil
    local glowFrameLevel, glowFrameStrata
    if runtime and view and view.GetMonitorDisplayLayer then
        glowFrameLevel, glowFrameStrata = view:GetMonitorDisplayLayer(
            runtime,
            binding and binding.monitorId
        )
        if type(glowFrameLevel) == "number" then
            glowFrameLevel = glowFrameLevel
                + ICON_TEXT_FRAME_LEVEL_OFFSET - 1
        else
            glowFrameLevel = nil
        end
    end
    if monitor and not nativeAura
        and YHUD.Sound and YHUD.Sound.Observe then
        YHUD.Sound:Observe(
            monitor,
            binding.soundRuntime,
            state,
            auraPresent and true or nil,
            auraPresent,
            monitor.visibilityMode == "always",
            styleState.visibilitySuppressed == true
                or not view or view.active ~= true
                or view.preview == true
                or view.designMode == true
                or view.layoutEditMode == true,
            chargeCompleted == true
        )
    end

    local changed = false
    if kind ~= "native-default" then
        changed = SetNativeProcGlowShown(styleState, false) or changed
    end
    local customShown = kind == "native-custom" or kind == "custom-rule"
    if customShown and gui.CreateGlow then
        local glow = styleState.nativeCustomGlow
        if not glow then
            glow = gui:CreateGlow(frame, {
                hidden = true,
                restrictedParent = nativeAura,
                trustedWidth = trustedWidth,
                trustedHeight = trustedHeight,
                trustedFrameLevel = glowFrameLevel,
                trustedFrameStrata = glowFrameStrata,
            })
            styleState.nativeCustomGlow = glow
            AddStat("procGlowCreates")
        end
        if glow then
            if glow._SetGlowLayoutContext then
                glow:_SetGlowLayoutContext(
                    nativeAura,
                    trustedWidth,
                    trustedHeight
                )
            end
            if glow._SetGlowLayerContext then
                changed = glow:_SetGlowLayerContext(
                    glowFrameLevel,
                    glowFrameStrata
                ) or changed
            end
            local shape = NativeBridge:_ResolveCustomGlowShape(
                snapshot,
                appearance
            )
            local targetShape = snapshot and snapshot.shape or "square"
            if glow.SetGlowShape
                and (styleState.nativeCustomGlowShape ~= shape
                    or styleState.nativeCustomGlowTargetShape
                        ~= targetShape) then
                glow:SetGlowShape(shape, targetShape)
                styleState.nativeCustomGlowShape = shape
                styleState.nativeCustomGlowTargetShape = targetShape
                changed = true
            end
            if glow.SetGlowParams
                and styleState.nativeCustomGlowAppearance ~= appearance then
                glow:SetGlowParams(appearance)
                styleState.nativeCustomGlowAppearance = appearance
                changed = true
            end
            if glow.SetGlowShown
                and styleState.nativeCustomGlowShown ~= true then
                glow:SetGlowShown(true)
                styleState.nativeCustomGlowShown = true
                changed = true
            end
        end
    elseif styleState.nativeCustomGlowShown == true
        and styleState.nativeCustomGlow
        and styleState.nativeCustomGlow.SetGlowShown then
        styleState.nativeCustomGlow:SetGlowShown(false)
        styleState.nativeCustomGlowShown = false
        changed = true
    end
    local keepDefaultGlow = kind == "native-default"
        or not compiled
        or compiled.nativeConfig
            and compiled.nativeConfig.mode == "default"
    if not keepDefaultGlow or not gui.CreateManagedProcGlow then
        return changed
    end

    local shape = NativeBridge:_NormalizeProcGlowShape(snapshot)
    local targetShape = snapshot and snapshot.shape or "square"
    local procFrames = NativeBridge.procFrames[frame]
    if not procFrames then
        procFrames = {}
        NativeBridge.procFrames[frame] = procFrames
    end
    if styleState.nativeProcGlow
        and styleState.nativeProcGlowShape ~= shape
        and gui.SetManagedProcGlowShown then
        gui:SetManagedProcGlowShown(
            styleState.nativeProcGlow,
            false
        )
        styleState.nativeProcGlow = nil
        styleState.nativeProcGlowShown = nil
    end
    local glow = styleState.nativeProcGlow
    if not glow then
        local cacheKey = shape == "circle"
            and "nativeProcGlowCircle"
            or "nativeProcGlowSquare"
        glow = styleState[cacheKey]
            or procFrames[cacheKey]
            or gui:CreateManagedProcGlow(
                frame,
                shape,
                trustedDisplayWidth,
                trustedDisplayHeight,
                glowFrameLevel,
                glowFrameStrata,
                targetShape
            )
        if glow and not styleState[cacheKey]
            and not procFrames[cacheKey] then
            AddStat("procGlowCreates")
        end
        styleState[cacheKey] = glow
        procFrames[cacheKey] = glow
        styleState.nativeProcGlow = glow
        styleState.nativeProcGlowShape = shape
        styleState.nativeProcGlowTargetShape = targetShape
        styleState.nativeProcGlowShown = nil
        styleState.nativeProcGlowLayoutDirty = true
    end
    if styleState.nativeProcGlowTargetShape ~= targetShape then
        styleState.nativeProcGlowTargetShape = targetShape
        styleState.nativeProcGlowLayoutDirty = true
    end
    if not glow then return false end
    local procLayerDirty = styleState.nativeProcGlowFrameLevel
            ~= glowFrameLevel
        or styleState.nativeProcGlowFrameStrata ~= glowFrameStrata
    if (styleState.nativeProcGlowLayoutDirty == true
            or procLayerDirty)
        and gui.LayoutManagedProcGlow then
        gui:LayoutManagedProcGlow(
            glow,
            frame,
            trustedDisplayWidth,
            trustedDisplayHeight,
            glowFrameLevel,
            glowFrameStrata,
            targetShape
        )
        styleState.nativeProcGlowLayoutDirty = false
        styleState.nativeProcGlowFrameLevel = glowFrameLevel
        styleState.nativeProcGlowFrameStrata = glowFrameStrata
        changed = true
    end
    changed = SetNativeProcGlowShown(
        styleState,
        kind == "native-default"
    ) or changed
    return changed
end

local function GetNativeCompletionDurationObject(binding, mode)
    local spell = YUI.API and YUI.API.Spell
    if not (spell and binding) then return nil end
    if mode == "charge" then
        if not spell.GetChargeDurationObject then return nil end
        return spell.GetChargeDurationObject(
            binding.cooldownCompletionChargeSpellId
        )
    end
    if mode == "cooldown" then
        if not spell.GetCooldownDurationObject then return nil end
        return spell.GetCooldownDurationObject(
            binding.cooldownCompletionCooldownSpellId,
            true
        )
    end
    return nil
end

local function ApplyNativeCooldownCompletion(binding, mode, active)
    local frames = binding and binding.cooldownCompletionFrames
    if type(frames) ~= "table"
        or binding.cooldownCompletionMode ~= mode then
        return false
    end
    local changed = false
    binding.cooldownCompletionActive = active == true
    for frame in pairs(frames) do
        local styleState = NativeBridge.frameStates[frame]
        local currentBinding = styleState and (styleState.nativeBinding
            or styleState.nativeStyleBinding or styleState.binding)
        if NativeBridge.active and currentBinding == binding
            and styleState.nativeIncluded == true then
            local state = styleState.nativeGlowCooldownState
            if type(state) == "table" then
                local wasActive = state.available == true
                    and state.secret ~= true
                    and (state.cooldownActive == true
                        or state.chargeActive == true)
                    or nil
                if active == true then
                    if binding.cooldownCompletionMode == "charge" then
                        state.chargeActive = true
                    else
                        state.cooldownActive = true
                    end
                else
                    state.cooldownActive = false
                    state.chargeActive = false
                end
                state.available = true
                state.secret = false
                if wasActive ~= (active == true) then changed = true end
                SyncNativeProcGlow(frame, styleState, styleState.compiledIcon)
            end
        end
    end
    return changed
end

local OnNativeCooldownCompletion

local function EnsureNativeCooldownCompletionHandle(binding, mode)
    if not (binding and binding.cooldownCompletionEnabled == true
        and (mode == "cooldown" or mode == "charge")) then
        return nil
    end
    if binding.cooldownCompletionHandle
        and binding.cooldownCompletionMode == mode then
        return binding.cooldownCompletionHandle
    end

    local spell = YUI.API and YUI.API.Spell
    if not (spell and spell.AcquireCooldownCompletion) then return nil end
    if binding.cooldownCompletionHandle
        and spell.ReleaseCooldownCompletion then
        spell.ReleaseCooldownCompletion(binding.cooldownCompletionHandle)
    end
    binding.cooldownCompletionHandle = nil
    binding.cooldownCompletionMode = nil
    binding.cooldownCompletionActive = nil

    local spellID = mode == "charge"
        and binding.cooldownCompletionChargeSpellId
        or binding.cooldownCompletionCooldownSpellId
    if not spellID then return nil end
    local handle = spell.AcquireCooldownCompletion(
        binding,
        spellID,
        mode,
        OnNativeCooldownCompletion
    )
    if handle then
        binding.cooldownCompletionHandle = handle
        binding.cooldownCompletionMode = mode
    end
    return handle
end

OnNativeCooldownCompletion = function(
    binding,
    _,
    mode,
    handle
)
    if not (NativeBridge.active and binding
        and binding.cooldownCompletionHandle == handle
        and binding.cooldownCompletionMode == mode) then
        return
    end
    local durationObject = GetNativeCompletionDurationObject(binding, mode)
    if durationObject == nil then return end
    local spell = YUI.API and YUI.API.Spell
    local active, resolved = spell.ArmCooldownCompletion(
        handle,
        durationObject
    )
    if resolved ~= true then return end
    ApplyNativeCooldownCompletion(
        binding,
        mode,
        active == true
    )
end

ArmNativeCooldownCompletion = function(binding, frame, active, mode)
    local handle = EnsureNativeCooldownCompletionHandle(binding, mode)
    if not handle then return false end
    local frames = binding.cooldownCompletionFrames
    if type(frames) == "table" and frame then frames[frame] = true end
    if active ~= true then
        binding.cooldownCompletionActive = false
        return false
    end

    local durationObject = GetNativeCompletionDurationObject(binding, mode)
    if durationObject == nil then return false end
    local spell = YUI.API and YUI.API.Spell
    local armed, resolved = spell.ArmCooldownCompletion(
        handle,
        durationObject
    )
    if resolved ~= true then return false end
    if armed == false then
        return ApplyNativeCooldownCompletion(
            binding,
            mode,
            false
        )
    end
    binding.cooldownCompletionActive = true
    return true
end

local function ReleaseCooldownCompletionBindings(state)
    local spell = YUI.API and YUI.API.Spell
    for _, binding in pairs(state and state.monitorByCooldown or {}) do
        local handle = binding and binding.cooldownCompletionHandle
        if handle and spell and spell.ReleaseCooldownCompletion then
            spell.ReleaseCooldownCompletion(handle)
        end
        if binding then
            binding.cooldownCompletionHandle = nil
            binding.cooldownCompletionMode = nil
            binding.cooldownCompletionFrames = nil
            binding.cooldownCompletionActive = nil
        end
    end
end

local function InitializeCooldownCompletionBindings(state, descriptor)
    local category = descriptor and descriptor.category
    if category ~= "essential" and category ~= "utility" then return end
    for _, binding in pairs(state and state.monitorByCooldown or {}) do
        if binding and binding.cooldownCompletionEnabled == true then
            binding.cooldownCompletionFrames = setmetatable(
                {},
                { __mode = "k" }
            )
        end
    end
end

function NativeBridge:OnNativeProcFrameRefresh(frame)
    if not self.active or IsNativeEditModeActive() or not frame then return false end
    local styleState = self.frameStates[frame]
    if not (styleState and styleState.nativeIncluded == true) then return false end
    AddStat("procGlowSignals")
    local changed = SyncNativeProcGlow(
        frame,
        styleState,
        styleState.compiledIcon
    ) == true
    if changed then AddStat("procGlowWrites") end
    return changed
end

function NativeBridge:RefreshGlowCombatState(inCombat)
    if not self.active or IsNativeEditModeActive() then return false end
    local changed = false
    for frame, styleState in pairs(self.frameStates) do
        local binding = styleState.nativeBinding
            or styleState.nativeStyleBinding
            or styleState.binding
        local compiled = binding and binding.glowRuntime
        local category = styleState.nativeCategory
        local hasCooldownRules = compiled
            and compiled.kind == "cooldown"
            and type(compiled.rules) == "table"
            and #compiled.rules > 0
            and (category == "essential" or category == "utility")
        if styleState.nativeIncluded == true and compiled
            and (compiled.hasCombatOnly == true or hasCooldownRules) then
            if hasCooldownRules then
                RefreshNativeCooldownGlowState(frame, styleState)
            end
            changed = SyncNativeProcGlow(
                frame,
                styleState,
                styleState.compiledIcon,
                inCombat
            ) or changed
        end
    end
    return changed
end

function NativeBridge:RefreshMonitorGlow(monitorId)
    if not self.active or IsNativeEditModeActive() then return false end
    local view = YHUD.View
    local monitor = view and view.desiredMonitors
        and view.desiredMonitors[monitorId]
    local runtime = monitor and view.groups and view.groups[monitor.groupId]
    local frame = runtime and runtime.nativeByMonitor
        and runtime.nativeByMonitor[monitorId]
    local styleState = frame and self.frameStates[frame]
    if not (styleState and styleState.nativeIncluded == true) then
        return false
    end
    return SyncNativeProcGlow(
        frame,
        styleState,
        styleState.compiledIcon
    ) == true
end

local function ObserveNativeAuraSound(binding, present)
    if not (binding and binding.soundRuntime) then return false end
    local view = YHUD.View
    local monitor = binding.monitorId and view
        and view.desiredMonitors
        and view.desiredMonitors[binding.monitorId]
    if not (monitor and YHUD.Sound and YHUD.Sound.Observe) then
        return false
    end
    local runtime = binding.groupId and view.groups
        and view.groups[binding.groupId]
    local persistent = monitor.visibilityMode == "always"
    local suppressed = not view or view.active ~= true
        or NativeBridge.active ~= true
        or NativeBridge.layoutPreviewActive == true
        or IsNativeEditModeActive()
        or view.preview == true
        or view.designMode == true
        or view.layoutEditMode == true
        or view.designerSurfaceVisible == false
        or not runtime
        or runtime.enabled ~= true
        or runtime.designerStateAllowed == false
        or runtime.visibilityAllowed == false
    return YHUD.Sound:Observe(
        monitor,
        binding.soundRuntime,
        nil,
        true,
        present == true,
        persistent,
        suppressed
    ) == true
end

local function SyncNativeAuraSoundStates(state, descriptor)
    if not (state and state.hasAuraSoundRules == true
        and descriptor and descriptor.dynamicVisibility == true) then
        return false
    end
    local view = YHUD.View
    if not (view and view.groups) then return false end
    local played = false
    for _, binding in pairs(state.monitorByCooldown or {}) do
        if binding and binding.soundRuntime then
            local runtime = binding.groupId and view.groups[binding.groupId]
            local categoryState = runtime and runtime.nativeCategories
                and runtime.nativeCategories[descriptor.category]
            local frame = categoryState and categoryState.byMonitor
                and categoryState.byMonitor[binding.monitorId]
            played = ObserveNativeAuraSound(
                binding,
                frame ~= nil
            ) or played
        end
    end
    return played
end

local function SyncNativeAuraPlaceholderGlow(binding, present)
    local view = YHUD.View
    local slot = binding and binding.monitorId and view
        and view.byMonitor and view.byMonitor[binding.monitorId]
    local monitor = binding and binding.monitorId and view
        and view.desiredMonitors and view.desiredMonitors[binding.monitorId]
    if not (slot and monitor
        and slot._yhudNativePersistentPlaceholder == true) then
        return false
    end
    if not view.ApplyMonitorGlow then return false end
    return view:ApplyMonitorGlow(
        slot,
        monitor,
        nil,
        false,
        true,
        present == true,
        true
    )
end

local function InstallNativeProcHooks(frame)
    if not frame or NativeBridge.procHookedFrames[frame] then return false end
    local hook = _G.hooksecurefunc
    if type(hook) ~= "function" then return false end
    local installed = false
    for _, methodName in ipairs({
        "OnSpellActivationOverlayGlowShowEvent",
        "OnSpellActivationOverlayGlowHideEvent",
    }) do
        if type(frame[methodName]) == "function" then
            local ok = pcall(hook, frame, methodName, function(itemFrame)
                NativeBridge:OnNativeProcFrameRefresh(itemFrame)
            end)
            installed = installed or ok
        end
    end
    if installed then NativeBridge.procHookedFrames[frame] = true end
    return installed
end

local function SetPandemicGlowShown(styleState, shown)
    local glow = styleState and styleState.pandemicGlow
    if not glow or not glow.SetGlowShown then return false end
    shown = shown == true
    if styleState.pandemicGlowShown == shown then return false end
    glow:SetGlowShown(shown)
    styleState.pandemicGlowShown = shown
    return true
end

local function RecordVisibilityAlphaResult(ok, wrote)
    if wrote == true then
        AddStat("visibilityAlphaWrites")
    elseif ok == true then
        AddStat("visibilityAlphaSkips")
    else
        AddStat("visibilityAlphaFailures")
    end
end

local function IsNativeGroupVisible(groupId)
    local view = YHUD.View
    local runtime = groupId and view and view.groups
        and view.groups[groupId]
    return NativeBridge.active == true
        and not IsNativeEditModeActive()
        and NativeBridge.layoutPreviewActive ~= true
        and view and view.active == true
        and view.designMode ~= true
        and view.designerSurfaceVisible ~= false
        and view.preview ~= true
        and runtime and runtime.enabled == true
        and runtime.designerStateAllowed ~= false
        and runtime.visibilityAllowed ~= false
        and (not view.IsGroupLevelDisplayAllowed
            or view:IsGroupLevelDisplayAllowed(runtime))
end

ApplyManagedFrameVisibility = function(state, frame, styleState, verify)
    if not (state and frame and styleState) then return false, false end
    local visible = styleState.nativeIncluded == true
        and IsNativeGroupVisible(styleState.nativeGroupId)
    local view = YHUD.View
    local monitorId = styleState.monitorId
        or styleState.nativeBinding and styleState.nativeBinding.monitorId
        or styleState.binding and styleState.binding.monitorId
    local projected = monitorId and view and (
        view.filteredAuraDynamicNodes
            and view.filteredAuraDynamicNodes[monitorId]
        or view.byMonitor and view.byMonitor[monitorId]
            and view.byMonitor[monitorId]
                ._yhudFilteredAuraChainCompatible == true
    )
    if projected then visible = false end
    styleState.visibilitySuppressed = not visible
    if not visible then
        SetNativeProcGlowShown(styleState, false)
        SetPandemicGlowShown(styleState, false)
    end
    local alpha = visible and GetAlphaBaseline(state, frame) or 0
    local ok, wrote = SetAlphaIfChanged(state, frame, alpha, verify)
    if SetNativeTooltipMouseEnabled then
        SetNativeTooltipMouseEnabled(
            frame,
            styleState,
            visible and styleState.nativeTooltipMouseRequested == true
        )
    end
    if ApplyStaticFrameParking then
        ApplyStaticFrameParking(frame, styleState)
    end
    RecordVisibilityAlphaResult(ok, wrote)
    return ok, wrote
end

local function RestoreCooldownFlash(styleState)
    if not styleState then return end
    local flash = styleState.cooldownFlashFrame
    if flash then
        SafeMethod(
            flash,
            "SetAlpha",
            styleState.cooldownFlashAlpha or 1
        )
    end
    styleState.cooldownFlashFrame = nil
    styleState.cooldownFlashAlpha = nil
    styleState.cooldownFlashSuppressed = nil
end

local function ApplyCooldownFlash(frame, styleState, snapshot)
    local flash = frame and frame.CooldownFlash
    if styleState.cooldownFlashFrame
        and styleState.cooldownFlashFrame ~= flash then
        RestoreCooldownFlash(styleState)
    end
    if not flash then return false end
    if styleState.cooldownFlashFrame ~= flash then
        local ok, alpha = SafeMethod(flash, "GetAlpha")
        styleState.cooldownFlashFrame = flash
        styleState.cooldownFlashAlpha =
            ok and SafeNumber(alpha) or 1
    end
    local enabled = snapshot and snapshot.drawBling == true
        and styleState.nativeGCDTimer ~= true
    local cooldown = frame and frame.Cooldown
    if cooldown then
        local ok, current = SafeMethod(cooldown, "GetDrawBling")
        if not ok or SafeBoolean(current) ~= enabled then
            SafeMethod(cooldown, "SetDrawBling", enabled)
        end
        if styleState.cooldownState then
            styleState.cooldownState.drawBling = enabled
        end
    end
    if enabled then
        SafeMethod(
            flash,
            "SetAlpha",
            styleState.cooldownFlashAlpha or 1
        )
    else
        SafeMethod(flash.FlashAnim, "Stop")
        SafeMethod(flash, "SetAlpha", 0)
    end
    styleState.cooldownFlashSuppressed = not enabled
    return true
end

local PandemicMaterialGlow = {}
PandemicMaterialGlow.__index = PandemicMaterialGlow

function PandemicMaterialGlow:SetGlowParams(params)
    self.params = params or PANDEMIC_MATERIAL_GLOW
    local color = self.params.color or PANDEMIC_GLOW_COLOR
    SafeMethod(
        self.Texture,
        "SetVertexColor",
        color[1] or 1,
        color[2] or 0,
        color[3] or 0,
        color[4] == nil and 1 or color[4]
    )
end

function PandemicMaterialGlow:SetGlowShape(shape)
    local texturePath = PANDEMIC_ICON_GLOW_TEXTURES[shape]
        or PANDEMIC_ICON_GLOW_TEXTURES.square
    if self.shape == shape and self.texturePath == texturePath then
        return false
    end
    self.shape = shape
    self.texturePath = texturePath
    SafeMethod(self.Texture, "SetTexture", texturePath)
    return true
end

function PandemicMaterialGlow:SetGlowShown(shown)
    shown = shown == true
    if self.shown == shown then return false end
    self.shown = shown
    SafeMethod(self.Texture, shown and "Show" or "Hide")
    return true
end

local function CreatePandemicMaterialGlow(gui, target, shape)
    if not (gui and gui.CreateTexture and target) then return nil end
    local texture = gui:CreateTexture(target, {
        layer = "OVERLAY",
        subLevel = 7,
    })
    if not texture then return nil end
    SafeMethod(texture, "SetAllPoints", target)
    SafeMethod(texture, "SetTexCoord", 0, 1, 0, 1)
    SafeMethod(texture, "SetBlendMode", "ADD")
    local glow = setmetatable({
        target = target,
        Texture = texture,
    }, PandemicMaterialGlow)
    glow:SetGlowParams(PANDEMIC_MATERIAL_GLOW)
    glow:SetGlowShape(shape)
    glow:SetGlowShown(false)
    return glow
end

local function EnsurePandemicGlow(frame, styleState, runtime, descriptor)
    local gui = YUI.GUI2
    if not (frame and styleState and runtime and descriptor
        and gui and gui.CreateFrame) then
        return nil
    end
    local target = styleState.pandemicGlowTarget
    if not target then
        target = gui:CreateFrame(frame, {})
        if not target then return nil end
        AddStat("pandemicGlowCreates")
        SafeMethod(target, "EnableMouse", false)
        SafeMethod(target, "SetAllPoints", frame)
        if target.SetFrameLevel and frame.GetFrameLevel then
            local ok, level = SafeMethod(frame, "GetFrameLevel")
            SafeMethod(
                target,
                "SetFrameLevel",
                ((ok and SafeNumber(level)) or 0) + 12
            )
        end
        SafeMethod(target, "Show")
        styleState.pandemicGlowTarget = target
    end
    local shape = runtime.shape or runtime.iconShape or "square"
    local pixel = descriptor.kind == "bar"
    local params = pixel and PANDEMIC_PIXEL_GLOW
        or PANDEMIC_MATERIAL_GLOW
    local glow = styleState.pandemicGlow
    if not glow then
        if pixel and gui.CreateGlow then
            glow = gui:CreateGlow(target, {
                style = PANDEMIC_PIXEL_GLOW.style,
                size = PANDEMIC_PIXEL_GLOW.size,
                lines = PANDEMIC_PIXEL_GLOW.lines,
                thickness = PANDEMIC_PIXEL_GLOW.thickness,
                speed = PANDEMIC_PIXEL_GLOW.speed,
                alpha = PANDEMIC_PIXEL_GLOW.alpha,
                color = PANDEMIC_PIXEL_GLOW.color,
                hidden = true,
                restrictedParent = descriptor.dynamicVisibility == true,
                trustedWidth = runtime.itemWidth or runtime.iconWidth or 244,
                trustedHeight = runtime.itemHeight or runtime.iconHeight or 24,
            })
        elseif not pixel then
            glow = CreatePandemicMaterialGlow(gui, target, shape)
        end
    end
    if not glow then return nil end
    styleState.pandemicGlow = glow
    if pixel and glow._SetGlowLayoutContext then
        glow:_SetGlowLayoutContext(
            descriptor.dynamicVisibility == true,
            runtime.itemWidth or runtime.iconWidth or 244,
            runtime.itemHeight or runtime.iconHeight or 24
        )
    end
    if glow.SetGlowParams then
        glow:SetGlowParams(params)
    end
    if glow.SetGlowShape then glow:SetGlowShape(shape) end
    if styleState.pandemicGlowShown ~= true then
        glow:SetGlowShown(false)
    end
    return glow
end

local function SuppressNativePandemic(frame, styleState, region)
    region = region or (frame and frame.PandemicIcon)
    if not region then return false end
    local previous = styleState.pandemicNativeFrame
    if previous and previous ~= region then
        SafeMethod(
            previous,
            "SetAlpha",
            styleState.pandemicNativeAlpha == nil
                and 1 or styleState.pandemicNativeAlpha
        )
        if NativeBridge.pandemicRegionOwners[previous] == frame then
            NativeBridge.pandemicRegionOwners[previous] = nil
        end
    end
    if previous ~= region then
        local ok, alpha = SafeMethod(region, "GetAlpha")
        styleState.pandemicNativeAlpha = ok and SafeNumber(alpha) or 1
    end
    styleState.pandemicNativeFrame = region
    styleState.pandemicNativeSuppressed = true
    SafeMethod(region, "SetAlpha", 0)
    return true
end

local function SyncPandemicAppearance(state, frame, region)
    local styleState = frame and NativeBridge.frameStates[frame]
    if not styleState then return false end
    SuppressNativePandemic(frame, styleState, region)
    local enabled = region ~= nil
        and styleState.nativeIncluded == true
        and styleState.visibilitySuppressed ~= true
        and state and state.pandemicGlowEnabled == true
    return SetPandemicGlowShown(styleState, enabled)
end

local function ClearPandemicAppearance(frame, styleState)
    if not styleState then return end
    SetPandemicGlowShown(styleState, false)
    local region = styleState.pandemicNativeFrame
    if region then
        SafeMethod(
            region,
            "SetAlpha",
            styleState.pandemicNativeAlpha == nil
                and 1 or styleState.pandemicNativeAlpha
        )
    end
    if region and NativeBridge.pandemicRegionOwners[region] == frame then
        NativeBridge.pandemicRegionOwners[region] = nil
    end
    styleState.pandemicNativeFrame = nil
    styleState.pandemicNativeAlpha = nil
    styleState.pandemicNativeSuppressed = nil
    styleState.pandemicRegionVisible = nil
end

local function RestorePandemicAppearance(frame, styleState)
    ClearPandemicAppearance(frame, styleState)
    styleState.nativeIncluded = nil
    styleState.nativeManaged = nil
    styleState.nativeGroupId = nil
    styleState.visibilitySuppressed = nil
end

local function OnPandemicRegionShown(region)
    local frame = region and NativeBridge.pandemicRegionOwners[region]
    local styleState = frame and NativeBridge.frameStates[frame]
    if not NativeBridge.active or IsNativeEditModeActive()
        or not styleState or styleState.restoring == true
        or styleState.nativeManaged ~= true then
        return
    end
    if styleState.pandemicRegionVisible == true then return end
    styleState.pandemicRegionVisible = true
    local state = styleState.pandemicCategory
        and GetState(styleState.pandemicCategory) or nil
    AddStat("pandemicShowSignals")
    if styleState.visibilitySuppressed == true then
        SuppressNativePandemic(frame, styleState, region)
        SetPandemicGlowShown(styleState, false)
    else
        SyncPandemicAppearance(state, frame, region)
    end
end

local function OnPandemicRegionHidden(region)
    local frame = region and NativeBridge.pandemicRegionOwners[region]
    local styleState = frame and NativeBridge.frameStates[frame]
    if not styleState then return end
    if styleState.pandemicRegionVisible == true then
        AddStat("pandemicHideSignals")
    end
    ClearPandemicAppearance(frame, styleState)
end

local function InstallPandemicRegionHooks(region)
    if not region then return false end
    if NativeBridge.pandemicHookedRegions[region] == true then return true end
    if type(region.HookScript) ~= "function" then return false end
    local shown = pcall(
        region.HookScript,
        region,
        "OnShow",
        OnPandemicRegionShown
    )
    local hidden = pcall(
        region.HookScript,
        region,
        "OnHide",
        OnPandemicRegionHidden
    )
    if shown and hidden then
        NativeBridge.pandemicHookedRegions[region] = true
        return true
    end
    return false
end

local function ObservePandemicRegion(frame, descriptor, region)
    if not (frame and descriptor and region) then return false end
    local styleState = GetFrameStyleState(frame)
    styleState.pandemicCategory = descriptor.category
    local previous = styleState.pandemicNativeFrame
    if previous and previous ~= region then
        ClearPandemicAppearance(frame, styleState)
    end
    NativeBridge.pandemicRegionOwners[region] = frame
    if not InstallPandemicRegionHooks(region) then
        NativeBridge.pandemicRegionOwners[region] = nil
        return false
    end
    if IsShown(region) then
        styleState.pandemicRegionVisible = true
        return SyncPandemicAppearance(
            GetState(descriptor.category),
            frame,
            region
        )
    end
    SetPandemicGlowShown(styleState, false)
    return true
end

local function SyncCurrentPandemicAppearance(frame, descriptor)
    if not (frame and descriptor) then
        return false
    end
    local styleState = NativeBridge.frameStates[frame]
    if not styleState then return false end
    local region = frame.PandemicIcon
    if region then
        return ObservePandemicRegion(frame, descriptor, region)
    end
    ClearPandemicAppearance(frame, styleState)
    return true
end

local function RestoreNativeChrome(styleState)
    local chrome = styleState and styleState.nativeIconChrome
    if chrome then
        SafeMethod(chrome.icon, "RemoveMaskTexture", chrome.mask)
        SafeMethod(chrome.cooldown, "RemoveMaskTexture", chrome.mask)
        SafeMethod(chrome.background, "RemoveMaskTexture", chrome.mask)
        SafeMethod(chrome.outOfRange, "RemoveMaskTexture", chrome.mask)
        RestoreTargetMasks(chrome.icon, chrome.iconMasks)
        RestoreTargetMasks(chrome.cooldown, chrome.cooldownMasks)
        RestoreTargetMasks(
            chrome.outOfRange,
            chrome.outOfRangeMasks
        )
        RestoreTargetMasks(chrome.icon, chrome.ownerIconMasks)
        if chrome.background then chrome.background:Hide() end
        if chrome.shapeBorder then chrome.shapeBorder:Hide() end
        if chrome.mask then chrome.mask:Hide() end
        for _, edge in pairs(chrome.edges or {}) do edge:Hide() end
        for index = 1, #(chrome.overlays or {}) do
            local overlay = chrome.overlays[index]
            SafeMethod(
                overlay.region,
                "SetAlpha",
                overlay.alpha or 1
            )
        end
    end
    local statusChrome = styleState
        and styleState.nativeStatusChrome
    if statusChrome then
        if statusChrome.textOverlay then statusChrome.textOverlay:Hide() end
        local gui = YUI.GUI2
        if gui and gui.ReleaseProjectedStatusBarFill
            and statusChrome.projection then
            statusChrome.projection._yhudBarStackInputs = nil
            statusChrome.projection._yhudBarStackPolicy = nil
            statusChrome.projection._yhudBarStackBaseColor = nil
            gui:ReleaseProjectedStatusBarFill(
                statusChrome.projection
            )
        end
        if statusChrome.overlay then statusChrome.overlay:Hide() end
        if statusChrome.track then statusChrome.track:Hide() end
        for _, edge in pairs(statusChrome.edges or {}) do edge:Hide() end
    end
    local gui = YUI.GUI2
    if styleState and gui and gui.SetManagedProcGlowShown then
        if styleState.nativeProcGlowCircle then
            gui:SetManagedProcGlowShown(
                styleState.nativeProcGlowCircle,
                false
            )
        end
        if styleState.nativeProcGlowSquare then
            gui:SetManagedProcGlowShown(
                styleState.nativeProcGlowSquare,
                false
            )
        end
    end
    if styleState and styleState.nativeCustomGlow
        and styleState.nativeCustomGlow.SetGlowShown then
        styleState.nativeCustomGlow:SetGlowShown(false)
        styleState.nativeCustomGlowShown = false
        styleState.nativeCustomGlowAppearance = nil
    end
    if styleState and styleState.nativeProcAlert then
        SafeMethod(
            styleState.nativeProcAlert,
            "SetAlpha",
            styleState.nativeProcAlertAlpha or 1
        )
    end
    if styleState and styleState.debuffBorder then
        SafeMethod(
            styleState.debuffBorder,
            "SetAlpha",
            styleState.debuffBorderAlpha or 1
        )
        SafeMethod(
            styleState.debuffBorderTexture,
            "SetAlpha",
            styleState.debuffBorderTextureAlpha or 1
        )
    end
end

local function ApplySkillAuraDisplay(frame, reason)
    local styleState = frame and GetFrameStyleState(frame)
    if not styleState or styleState.applyingSkillAuraDisplay then return false end
    local previousGCDTimer = styleState.nativeGCDTimer == true
    local binding = styleState.nativeBinding
    local supported = binding and binding.canUseAuraForCooldown == true
    local enabled = not supported or binding.skillAuraDisplay ~= false
    local _, cachedAuraValue = SafeField(frame, "cooldownUseAuraDisplayTime")
    local auraDisplayState = SafeBoolean(cachedAuraValue)
    local auraActive = supported and auraDisplayState == true
    local _, cachedGCD = SafeField(frame, "isOnGCD")
    local _, cachedCharges = SafeField(frame, "wasSetFromCharges")
    styleState.nativeGCDTimer = auraDisplayState == false
        and SafeBoolean(cachedGCD) == true
        and SafeBoolean(cachedCharges) ~= true
    local filterGCD = binding and binding.gcdEligible == true
        and binding.cooldownGCD == false
        and styleState.nativeGCDTimer == true
    if enabled and not filterGCD then
        if styleState.skillAuraForcedOff then
            local refreshedByBlizzard = reason == "UNIT_AURA"
                or reason == "SPELL_UPDATE_COOLDOWN"
                or reason == "SPELL_UPDATE_USES"
                or reason == "native-refresh"
            if refreshedByBlizzard then
                styleState.skillAuraForcedOff = nil
                styleState.skillAuraRestorePending = nil
                styleState.skillCooldownDisplay = nil
            else
                styleState.skillAuraRestorePending = true
            end
        end
    else
        local spell = YUI.API and YUI.API.Spell
        local cooldown = frame.Cooldown
        local spellId = binding.spellId
        if not (spellId and cooldown and spell and spell.ReadCooldownDisplay) then
            return false
        end
        styleState.applyingSkillAuraDisplay = true
        local display = styleState.skillCooldownDisplay or {}
        styleState.skillCooldownDisplay = display
        spell.ReadCooldownDisplay(
            spellId,
            display,
            reason or "native-bridge",
            binding.chargeSpellId,
            binding.hasChargesHint
        )
        local durationObject = display.durationObject
        -- 光环计时关闭后仍可使用原生法术 GCD；充能/实际冷却保持优先。
        if durationObject == nil and binding.gcdEligible == true
            and binding.cooldownGCD ~= false and display.isEnabled ~= false
            and display.chargeActive ~= true and display.chargeStateSecret ~= true
            and SafeBoolean(cachedGCD) == true
            and spell.GetCooldownDurationObject then
            durationObject = spell.GetCooldownDurationObject(spellId, false)
        end
        styleState.nativeGCDTimer = display.durationObject == nil
            and (display.isOnGCD == true or SafeBoolean(cachedGCD) == true)
        SafeMethod(cooldown, "SetUseAuraDisplayTime", false)
        if durationObject ~= nil then
            SafeMethod(
                cooldown,
                "SetCooldownFromDurationObject",
                durationObject,
                true
            )
        else
            SafeMethod(cooldown, "Clear")
        end
        SafeMethod(cooldown, "SetSwipeColor", 0, 0, 0, 0.7)
        local icon = frame.Icon
        if icon and icon.SetDesaturated
            and display.cooldownStateSecret ~= true
            and display.chargeStateSecret ~= true then
            SafeMethod(
                icon,
                "SetDesaturated",
                display.cooldownActive == true
                    or (display.chargeActive == true
                        and (display.currentCharges or 0) < 1)
            )
        end
        styleState.skillAuraForcedOff = true
        styleState.skillAuraRestorePending = nil
        styleState.applyingSkillAuraDisplay = false
    end

    local cooldown = frame.Cooldown
    local icon = frame.Icon
    if supported and cooldown then
        if auraActive and binding.auraHighlight == false then
            SafeMethod(cooldown, "SetSwipeColor", 0, 0, 0, 0.7)
            styleState.auraHighlightSuppressed = true
        elseif auraActive and styleState.auraHighlightSuppressed then
            local colorOK, color = SafeField(frame, "cooldownSwipeColor")
            local rgbaOK, r, g, b, a
            if colorOK then
                rgbaOK, r, g, b, a = SafeMethod(color, "GetRGBA")
            end
            if rgbaOK then
                SafeMethod(cooldown, "SetSwipeColor", r, g, b, a)
            end
            styleState.auraHighlightSuppressed = nil
        elseif not auraActive then
            styleState.auraHighlightSuppressed = nil
        end

        if binding.inactiveDesaturate == true then
            SafeMethod(icon, "SetDesaturated", not auraActive)
            styleState.inactiveDesaturateApplied = true
        elseif styleState.inactiveDesaturateApplied then
            local _, nativeDesaturated = SafeField(
                frame,
                "cooldownDesaturated"
            )
            SafeMethod(
                icon,
                "SetDesaturated",
                SafeBoolean(nativeDesaturated) == true
            )
            styleState.inactiveDesaturateApplied = nil
        end
    end
    if styleState.compiledIcon
        and previousGCDTimer ~= (styleState.nativeGCDTimer == true) then
        ApplyCooldownFlash(frame, styleState, styleState.compiledIcon)
    end
    return true
end

local RehydrateNativeCooldownPresentation

local function OnNativeTimerShown(frame)
    if not NativeBridge.active or IsNativeEditModeActive() then return end
    local styleState = frame and NativeBridge.frameStates[frame]
    if styleState and styleState.nativeIncluded == true
        and RehydrateNativeCooldownPresentation then
        RehydrateNativeCooldownPresentation(frame, styleState, true)
    end
end

local function InstallNativeTimerShownHook(frame)
    if not frame or NativeBridge.timerShownHookedFrames[frame] then
        return false
    end
    local hook = _G.hooksecurefunc
    if type(hook) ~= "function"
        or type(frame.SetTimerShown) ~= "function" then
        return false
    end
    local ok = pcall(hook, frame, "SetTimerShown", OnNativeTimerShown)
    if ok then NativeBridge.timerShownHookedFrames[frame] = true end
    return ok
end

local function OnSkillAuraDisplayRefresh(owner)
    local styleState = owner and NativeBridge.frameStates[owner]
    local binding = styleState and styleState.nativeBinding
    if NativeBridge.active and not IsNativeEditModeActive()
        and styleState and styleState.nativeIncluded == true then
        RefreshNativeCooldownGlowState(owner, styleState)
        if binding and binding.needsSkillAuraRefresh == true then
            ApplySkillAuraDisplay(owner, "native-refresh")
        end
        if RehydrateNativeCooldownPresentation then
            RehydrateNativeCooldownPresentation(owner, styleState)
        end
    end
end

local function OnNativeSpellUsesRefresh(owner)
    local styleState = owner and NativeBridge.frameStates[owner]
    if not (NativeBridge.active and not IsNativeEditModeActive()
        and styleState and styleState.nativeIncluded == true) then
        return
    end
    RefreshNativeCooldownGlowState(owner, styleState)
    SyncNativeProcGlow(owner, styleState, styleState.compiledIcon)
end

local function OnNativeChargeGainedAlertTime(
    owner,
    _,
    chargeGainTime
)
    local styleState = owner and NativeBridge.frameStates[owner]
    if not (NativeBridge.active and not IsNativeEditModeActive()
        and styleState and styleState.nativeIncluded == true) then
        return
    end

    local publicGainTime = SafeNumber(chargeGainTime)
    local now = GetRuntimeTime()
    if not (publicGainTime and now and publicGainTime <= now) then
        return
    end

    local binding = styleState.nativeBinding
        or styleState.nativeStyleBinding or styleState.binding
    if not (binding and binding.soundRuntime) then return end
    local state = RefreshNativeCooldownGlowState(owner, styleState)
    if not (state and state.available == true and state.secret ~= true
        and binding.cooldownCompletionMode == "charge") then
        return
    end
    SyncNativeProcGlow(
        owner,
        styleState,
        styleState.compiledIcon,
        nil,
        true
    )
end

local function InstallSkillAuraDisplayHook(frame, descriptor)
    if descriptor and descriptor.kind == "bar" then return true end
    if not frame or NativeBridge.skillAuraHookedFrames[frame] then
        return true
    end
    local hook = _G.hooksecurefunc
    if type(hook) ~= "function"
        or type(frame.RefreshIconDesaturation) ~= "function" then
        return false
    end
    local installed = pcall(
        hook,
        frame,
        "RefreshIconDesaturation",
        OnSkillAuraDisplayRefresh
    )
    if installed then NativeBridge.skillAuraHookedFrames[frame] = true end
    if not NativeBridge.spellUsesHookedFrames[frame]
        and type(frame.OnSpellUpdateUsesEvent) == "function" then
        local usesInstalled = pcall(
            hook,
            frame,
            "OnSpellUpdateUsesEvent",
            OnNativeSpellUsesRefresh
        )
        if usesInstalled then
            NativeBridge.spellUsesHookedFrames[frame] = true
        end
    end
    if not NativeBridge.chargeGainedHookedFrames[frame]
        and type(frame.AddChargeGainedAlertTime) == "function" then
        local chargeInstalled = pcall(
            hook,
            frame,
            "AddChargeGainedAlertTime",
            OnNativeChargeGainedAlertTime
        )
        if chargeInstalled then
            NativeBridge.chargeGainedHookedFrames[frame] = true
        end
    end
    return installed
end

local function ApplyIconFrameGeometry(frame, runtime, styleState)
    local width = runtime.itemWidth
        or runtime.iconWidth
        or runtime.iconSize
        or 42
    local height = runtime.itemHeight
        or runtime.iconHeight
        or runtime.iconSize
        or 42
    local captureDynamicGeometry = styleState
        and styleState.nativeCategory == "trackedBuff"
        and styleState.cooldownID ~= nil
    if captureDynamicGeometry then
        styleState.dynamicGeometryWrite = true
    end
    SafeMethod(frame, "SetScale", 1)
    local gui = YUI.GUI2
    if not (gui and gui.SetPixelSnappedSize
        and gui:SetPixelSnappedSize(
            frame,
            width,
            height,
            1,
            1
    )) then
        SafeMethod(frame, "SetSize", width, height)
    end
    if captureDynamicGeometry then
        CaptureDynamicIconSizeScale(frame, styleState)
        styleState.dynamicGeometryWrite = nil
    end
end

local function CaptureMouseInputState(target, state)
    if not (target and state) or state.captured == true then return end
    local ok, current = SafeMethod(target, "IsMouseClickEnabled")
    if ok then
        state.clickSupported = true
        state.click = current == true
    else
        ok, current = SafeMethod(target, "IsMouseEnabled")
        if ok then
            state.legacySupported = true
            state.legacy = current == true
        end
    end
    ok, current = SafeMethod(target, "IsMouseMotionEnabled")
    if ok then
        state.motionSupported = true
        state.motion = current == true
    end
    state.captured = true
end

local function WriteMouseInputState(target, state, motionEnabled, force)
    if not (target and state) then return false, false end
    CaptureMouseInputState(target, state)
    motionEnabled = motionEnabled == true
    local ok = true
    local wrote = false
    if state.clickSupported == true
        and (force == true or state.appliedClick ~= false) then
        local clickOK = SafeMethod(target, "SetMouseClickEnabled", false)
        ok = clickOK and ok
        if clickOK then
            state.appliedClick = false
            wrote = true
        end
    end
    if state.motionSupported == true then
        if force == true or state.appliedMotion ~= motionEnabled then
            local motionOK = SafeMethod(
                target,
                "SetMouseMotionEnabled",
                motionEnabled
            )
            ok = motionOK and ok
            if motionOK then
                state.appliedMotion = motionEnabled
                wrote = true
            end
        end
    elseif state.legacySupported == true
        and (force == true or state.appliedLegacy ~= motionEnabled) then
        local legacyOK = SafeMethod(target, "EnableMouse", motionEnabled)
        ok = legacyOK and ok
        if legacyOK then
            state.appliedLegacy = motionEnabled
            wrote = true
        end
    end
    return ok, wrote
end

local function RestoreMouseInputState(target, state)
    if not (target and state and state.captured == true) then return end
    if state.clickSupported == true then
        SafeMethod(target, "SetMouseClickEnabled", state.click == true)
    end
    if state.motionSupported == true then
        SafeMethod(target, "SetMouseMotionEnabled", state.motion == true)
    elseif state.legacySupported == true then
        SafeMethod(target, "EnableMouse", state.legacy == true)
    end
end

local function ResolveNativeTooltipMotion(styleState)
    return styleState
        and styleState.nativeIncluded == true
        and IsNativeGroupVisible(styleState.nativeGroupId)
        and styleState.nativeTooltipMouseRequested == true
end

local function OnNativeTooltipsShown(frame)
    if not NativeBridge.active then return end
    local styleState = NativeBridge.frameStates[frame]
    if styleState then
        SetNativeTooltipMouseEnabled(
            frame,
            styleState,
            ResolveNativeTooltipMotion(styleState),
            true
        )
    end
end

local function InstallNativeTooltipHook(frame)
    if not frame or NativeBridge.tooltipHookedFrames[frame] then return false end
    local hook = _G.hooksecurefunc
    if type(hook) ~= "function"
        or type(frame.SetTooltipsShown) ~= "function" then
        return false
    end
    local ok = pcall(hook, frame, "SetTooltipsShown", OnNativeTooltipsShown)
    if ok then NativeBridge.tooltipHookedFrames[frame] = true end
    return ok
end

SetNativeTooltipMouseEnabled = function(frame, styleState, enabled, force)
    if not (frame and styleState) then return false, false end
    InstallNativeTooltipHook(frame)
    local input = styleState.nativeTooltipInput
    if not input then
        input = {}
        styleState.nativeTooltipInput = input
    end
    local ok, wrote = WriteMouseInputState(frame, input, enabled, force)
    local cooldown = frame.Cooldown
    if cooldown then
        local cooldownInput = styleState.nativeCooldownInput
        if not cooldownInput then
            cooldownInput = {}
            styleState.nativeCooldownInput = cooldownInput
        end
        local childOK, childWrote = WriteMouseInputState(
            cooldown,
            cooldownInput,
            false,
            force
        )
        ok = childOK and ok
        wrote = childWrote or wrote
    end
    styleState.nativeTooltipMouseEnabled = enabled == true
    if not ok and IsInCombat() then
        NativeBridge:ScheduleDeferred("categories")
    end
    return ok, wrote
end

local function CaptureFramePoints(frame)
    local points = {}
    local ok, count = SafeMethod(frame, "GetNumPoints")
    count = ok and SafeNumber(count) or nil
    for index = 1, count or 0 do
        local pointOK, point, relative, relativePoint, x, y =
            SafeMethod(frame, "GetPoint", index)
        point = pointOK and SafeString(point) or nil
        relativePoint = pointOK and SafeString(relativePoint) or nil
        x = pointOK and SafeNumber(x) or nil
        y = pointOK and SafeNumber(y) or nil
        if point and relativePoint and x and y then
            points[#points + 1] = {
                point,
                relative,
                relativePoint,
                x,
                y,
            }
        end
    end
    return points
end

local function RestoreFramePoints(frame, styleState)
    local points = styleState and styleState.nativeOriginalPoints
    if not (frame and type(points) == "table" and #points > 0) then
        return false
    end
    styleState.nativeParkingWrite = true
    styleState.nativeParked = false
    local ok = SafeMethod(frame, "ClearAllPoints")
    for index = 1, #points do
        ok = SafeMethod(frame, "SetPoint", Unpack(points[index])) and ok
    end
    styleState.nativeParkingWrite = nil
    return ok
end

ApplyStaticFrameParking = function(frame, styleState, force)
    local descriptor = styleState and styleState.nativeCategory
        and DESCRIPTOR_BY_CATEGORY[styleState.nativeCategory]
    if not (frame and descriptor and descriptor.dynamicVisibility ~= true) then
        return false
    end
    if styleState.nativeManaged == true then return false end
    if IsInCombat() then
        NativeBridge:ScheduleDeferred("categories")
        return false
    end
    if styleState.nativeParked == true and force ~= true then return false end
    if not styleState.nativeOriginalPoints then
        styleState.nativeOriginalPoints = CaptureFramePoints(frame)
    end
    styleState.nativeParkingWrite = true
    local clearOK = SafeMethod(frame, "ClearAllPoints")
    local pointOK = SafeMethod(
        frame,
        "SetPoint",
        "TOPLEFT",
        _G.UIParent,
        "TOPLEFT",
        -10000,
        10000
    )
    styleState.nativeParkingWrite = nil
    if clearOK and pointOK then
        styleState.nativeParked = true
        return true
    end
    return false
end

local function ApplyNativeTooltipMouse(frame, runtime, styleState)
    if not (frame and runtime and styleState) then return false end
    styleState.nativeTooltipMouseRequested = runtime.showTooltip ~= false
    local visible = styleState.nativeIncluded == true
        and IsNativeGroupVisible(styleState.nativeGroupId)
    local _, wrote = SetNativeTooltipMouseEnabled(
        frame,
        styleState,
        visible and styleState.nativeTooltipMouseRequested
    )
    return wrote == true
end

local function ApplyIconStyle(frame, runtime, descriptor, binding)
    local view = YHUD.View
    if view and view.ApplyIconShadow then
        view:ApplyIconShadow(frame, runtime, not IsInCombat())
    end
    local styleState = GetFrameStyleState(frame)
    RefreshNativeCooldownGlowState(frame, styleState)
    InstallNativeTimerShownHook(frame)
    local gui = YUI.GUI2
    local icon = frame.Icon
    local cooldown = frame.Cooldown
    local count = frame.ChargeCount and frame.ChargeCount.Current
    if not count and frame.Applications then
        count = frame.Applications.Applications
    end
    local _, cooldownText = SafeMethod(cooldown, "GetCountdownFontString")
    local cooldownRegionChanged = styleState.cooldownTextRegion ~= cooldownText
    styleState.cooldownTextRegion = cooldownText
    local countRegionChanged = styleState.countTextRegion ~= count
    styleState.countTextRegion = count
    if not styleState.iconTextCaptured then
        if not styleState.cooldownFont then
            local ok, fontString = SafeMethod(
                cooldown,
                "GetCountdownFontString"
            )
            styleState.cooldownFont =
                ok and CaptureFontString(fontString, true) or nil
        end
        styleState.countFont = CaptureFontString(count, true)
        styleState.iconTextCaptured = true
    else
        if cooldownRegionChanged then
            styleState.cooldownFont = CaptureFontString(cooldownText, true)
        end
        if countRegionChanged then
            styleState.countFont = CaptureFontString(count, true)
        end
    end
    SafeMethod(cooldownText, "SetSize", 0, 0)
    if count and (countRegionChanged
        or styleState.countNaturalSizeRegion ~= count) then
        SafeMethod(count, "SetSize", 0, 0)
        styleState.countNaturalSizeRegion = count
    end
    local snapshot = runtime.iconStyle
        or (gui and gui.CompileIconStyle
            and gui:CompileIconStyle(runtime, styleState.compiledIcon))
    styleState.compiledIcon = snapshot
    styleState.nativeCooldownDrawSwipe, styleState.nativeCooldownReverse =
        YHUD:ResolveMonitorCooldownSwipe(
            binding and binding.cooldownSwipeMode,
            runtime.cooldownSwipe,
            descriptor and descriptor.category == "trackedBuff"
        )
    if gui and gui.CaptureVisual and not styleState.capturedIcon then
        styleState.iconTarget = EnsureNativeIconChrome(
            frame,
            icon,
            cooldown,
            styleState,
            snapshot
        ) or { icon = icon }
        styleState.cooldownTarget = {
            cooldown = cooldown,
        }
        gui:CaptureVisual(styleState.iconTarget, styleState.iconState)
        gui:CaptureVisual(
            styleState.cooldownTarget,
            styleState.cooldownState
        )
        local original = styleState.cooldownState.original
        if original then
            original.swipeTexture = OFFICIAL_SWIPE_TEXTURE
            if descriptor and descriptor.category == "trackedBuff" then
                original.swipeColor = { 0, 0, 0, 0.7 }
            else
                original.swipeColor = { 1, 1, 1, 1 }
            end
            original.useCircularEdge = false
        end
        styleState.capturedIcon = true
    end
    styleState.iconTarget = EnsureNativeIconChrome(
        frame,
        icon,
        cooldown,
        styleState,
        snapshot
    ) or styleState.iconTarget
    if gui and gui.ApplyIconChrome and snapshot then
        gui:ApplyIconChrome(
            styleState.iconTarget,
            snapshot,
            styleState.iconState
        )
        gui:ApplyCooldownChrome(
            cooldown,
            snapshot,
            styleState.cooldownState
        )
        if gui.ApplyCooldownSwipe then
            gui:ApplyCooldownSwipe(
                cooldown,
                styleState.nativeCooldownDrawSwipe ~= false,
                styleState.nativeCooldownReverse == true,
                styleState.cooldownState
            )
        end
    end
    ApplyCooldownFlash(frame, styleState, snapshot)
    if cooldown then
        SafeMethod(
            cooldown,
            "SetHideCountdownNumbers",
            runtime.cooldownText == false
        )
    end
    if gui and gui.ApplyTextStyle and snapshot and snapshot.countText then
        styleState.countState = styleState.countState or {}
        styleState.countState.preserveVisibility = true
        gui:ApplyTextStyle(
            count,
            snapshot.countText,
            styleState.countState
        )
    end
    ApplyNativeIconTextLayers(
        frame,
        styleState,
        runtime,
        cooldownText,
        count
    )
    SuppressDebuffBorderWhileStyled(frame, styleState)
    SyncNativeProcGlow(frame, styleState, snapshot)
end

RehydrateNativeCooldownPresentation = function(frame, styleState, force)
    local cooldown = frame and frame.Cooldown
    local runtime = styleState and styleState.nativeStyleRuntime
    local snapshot = styleState and styleState.compiledIcon
    local gui = YUI.GUI2
    if not (cooldown and runtime and snapshot and gui) then
        return false
    end

    local _, cooldownText = SafeMethod(cooldown, "GetCountdownFontString")
    local regionChanged = styleState.cooldownTextRegion ~= cooldownText
    if regionChanged then
        styleState.cooldownTextRegion = cooldownText
        styleState.cooldownFont = CaptureFontString(cooldownText, true)
    end
    if regionChanged or force == true then
        SafeMethod(cooldownText, "SetSize", 0, 0)
        styleState.cooldownState = styleState.cooldownState or {}
        styleState.cooldownState.text = nil
        if cooldownText and snapshot.cooldownText
            and gui.ApplyTextStyle then
            styleState.cooldownState.text = {}
            gui:ApplyTextStyle(
                cooldownText,
                snapshot.cooldownText,
                styleState.cooldownState.text
            )
        end
    end
    local count = frame.ChargeCount and frame.ChargeCount.Current
    if not count and frame.Applications then
        count = frame.Applications.Applications
    end
    ApplyNativeIconTextLayers(
        frame,
        styleState,
        runtime,
        cooldownText,
        count
    )
    local hideNumbers = runtime.cooldownText == false
    local hideOK, currentHide = SafeMethod(
        cooldown,
        "GetHideCountdownNumbers"
    )
    if force == true or not hideOK
        or SafeBoolean(currentHide) ~= hideNumbers then
        SafeMethod(cooldown, "SetHideCountdownNumbers", hideNumbers)
    end
    if gui.ApplyCooldownSwipe then
        local drawSwipe = styleState.nativeCooldownDrawSwipe ~= false
        local reverse = styleState.nativeCooldownReverse == true
        local drawOK, currentDraw = SafeMethod(cooldown, "GetDrawSwipe")
        local reverseOK, currentReverse = SafeMethod(cooldown, "GetReverse")
        if force == true or not drawOK
            or SafeBoolean(currentDraw) ~= drawSwipe then
            styleState.cooldownState.drawSwipe = nil
        end
        if force == true or not reverseOK
            or SafeBoolean(currentReverse) ~= reverse then
            styleState.cooldownState.reverse = nil
        end
        gui:ApplyCooldownSwipe(
            cooldown,
            drawSwipe,
            reverse,
            styleState.cooldownState
        )
    end
    ApplyCooldownFlash(frame, styleState, snapshot)
    SyncNativeProcGlow(frame, styleState, snapshot)
    return true
end

local function SameLayoutNumber(left, right)
    return type(left) == "number"
        and type(right) == "number"
        and math.abs(left - right) < 0.001
end

local function SetRegionSizeIfChanged(region, width, height)
    if not region then return false end
    local widthOK, currentWidth = SafeMethod(region, "GetWidth")
    local heightOK, currentHeight = SafeMethod(region, "GetHeight")
    if widthOK and heightOK
        and SameLayoutNumber(SafeNumber(currentWidth), width)
        and SameLayoutNumber(SafeNumber(currentHeight), height) then
        return false
    end
    local ok = SafeMethod(region, "SetSize", width, height)
    return ok == true
end

local function RegionPointMatches(
    region,
    point,
    relativeTo,
    relativePoint,
    offsetX,
    offsetY
)
    local countOK, pointCount = SafeMethod(region, "GetNumPoints")
    pointCount = countOK and SafeNumber(pointCount) or nil
    if pointCount == 1 then
        local pointOK, currentPoint, currentRelative, currentRelativePoint,
            currentX, currentY = SafeMethod(region, "GetPoint", 1)
        if pointOK then
            return currentPoint == point
                and currentRelative == relativeTo
                and currentRelativePoint == relativePoint
                and SameLayoutNumber(SafeNumber(currentX) or 0, offsetX)
                and SameLayoutNumber(SafeNumber(currentY) or 0, offsetY)
        end
    elseif pointCount ~= nil then
        return false
    end
    return region._yhudNativePoint == point
        and region._yhudNativeRelative == relativeTo
        and region._yhudNativeRelativePoint == relativePoint
        and SameLayoutNumber(region._yhudNativeOffsetX or 0, offsetX)
        and SameLayoutNumber(region._yhudNativeOffsetY or 0, offsetY)
end

local function SetRegionPointIfChanged(
    region,
    point,
    relativeTo,
    relativePoint,
    offsetX,
    offsetY
)
    if not region or RegionPointMatches(
        region,
        point,
        relativeTo,
        relativePoint,
        offsetX,
        offsetY
    ) then
        return false
    end
    SafeMethod(region, "ClearAllPoints")
    local ok = SafeMethod(
        region,
        "SetPoint",
        point,
        relativeTo,
        relativePoint,
        offsetX,
        offsetY
    )
    if ok then
        region._yhudNativePoint = point
        region._yhudNativeRelative = relativeTo
        region._yhudNativeRelativePoint = relativePoint
        region._yhudNativeOffsetX = offsetX
        region._yhudNativeOffsetY = offsetY
    end
    return ok == true
end

local function SetRegionScaleIfChanged(region, scale)
    local ok, current = SafeMethod(region, "GetScale")
    current = ok and SafeNumber(current) or nil
    if SameLayoutNumber(current, scale) then return false end
    return SafeMethod(region, "SetScale", scale) == true
end

function NativeBridge:_SetVisualRegionState(region, shown, alpha)
    if not region then return false end
    local changed = false
    if type(shown) == "boolean" then
        local shownOK, currentShown = SafeMethod(region, "IsShown")
        currentShown = shownOK and SafeBoolean(currentShown) or nil
        if currentShown ~= shown then
            local wrote = SafeMethod(region, "SetShown", shown)
            if not wrote then
                wrote = SafeMethod(region, shown and "Show" or "Hide")
            end
            changed = wrote == true or changed
        end
    end
    if type(alpha) == "number" then
        local alphaOK, currentAlpha = SafeMethod(region, "GetAlpha")
        currentAlpha = alphaOK and SafeNumber(currentAlpha) or nil
        if currentAlpha ~= alpha then
            changed = SafeMethod(region, "SetAlpha", alpha) == true
                or changed
        end
    end
    return changed
end

function NativeBridge:_ApplyNativeBarIconVisibility(
    frame,
    styleState,
    snapshot,
    showIcon
)
    local chrome = styleState and styleState.nativeIconChrome
    local icon = frame and frame.Icon and frame.Icon.Icon
    if not icon then return false end
    showIcon = showIcon ~= false
    local original = styleState.barIconTextureGeometry
    local iconAlpha = showIcon
        and (original and original.alpha or 1) or 0
    local changed = self:_SetVisualRegionState(icon, showIcon, iconAlpha)
    if chrome then
        changed = self:_SetVisualRegionState(
            chrome.background,
            showIcon,
            nil
        ) or changed
        local thickness = tonumber(snapshot and snapshot.borderThickness) or 0
        local shaped = snapshot and snapshot.borderFamily ~= nil
        changed = self:_SetVisualRegionState(
            chrome.shapeBorder,
            showIcon and shaped and thickness > 0,
            nil
        ) or changed
        for _, edge in pairs(chrome.edges or {}) do
            changed = self:_SetVisualRegionState(
                edge,
                showIcon and not shaped and thickness > 0,
                nil
            ) or changed
        end
        changed = self:_SetVisualRegionState(
            chrome.mask,
            showIcon and snapshot and snapshot.mask ~= nil,
            nil
        ) or changed
        for index = 1, #(chrome.overlays or {}) do
            local overlay = chrome.overlays[index]
            local alphaOK, alpha = SafeMethod(overlay.region, "GetAlpha")
            alpha = alphaOK and SafeNumber(alpha) or nil
            if alpha ~= 0 then
                changed = SafeMethod(overlay.region, "SetAlpha", 0) == true
                    or changed
            end
        end
    end
    if showIcon then
        if styleState.debuffBorder then
            changed = self:_SetVisualRegionState(
                styleState.debuffBorder,
                nil,
                styleState.debuffBorderAlpha or 1
            ) or changed
            changed = self:_SetVisualRegionState(
                styleState.debuffBorderTexture,
                nil,
                styleState.debuffBorderTextureAlpha or 1
            ) or changed
        end
    else
        local border = frame and frame.DebuffBorder
        if border and styleState.debuffBorder ~= border then
            changed = SuppressDebuffBorderWhileStyled(frame, styleState)
                or changed
        else
            changed = self:_SetVisualRegionState(
                styleState.debuffBorder,
                nil,
                0
            ) or changed
            changed = self:_SetVisualRegionState(
                styleState.debuffBorderTexture,
                nil,
                0
            ) or changed
        end
    end
    styleState.nativeBarIconShown = showIcon
    return changed
end

local function PositionNativeBar(frame, runtime)
    local icon = frame.Icon
    local bar = frame.Bar
    if not (icon and bar) then return false end
    local position = runtime.iconPosition or "left"
    local gap = tonumber(runtime.iconGap) or 0
    local iconSize = tonumber(runtime.iconSize) or 24
    local showIcon = runtime.showIcon ~= false
    local barWidth = showIcon
        and (tonumber(runtime.barWidth) or 220)
        or (tonumber(runtime.itemWidth) or 244)
    local barHeight = showIcon
        and (tonumber(runtime.barHeight) or 24)
        or (tonumber(runtime.itemHeight) or 24)

    local changed = SetRegionSizeIfChanged(icon, iconSize, iconSize)
    changed = SetRegionSizeIfChanged(bar, barWidth, barHeight) or changed
    if not showIcon then
        changed = SetRegionPointIfChanged(
            bar,
            "CENTER",
            frame,
            "CENTER",
            0,
            0
        ) or changed
        return changed
    end
    -- Blizzard's SetBarContent always anchors Bar to Icon. Keep both YHUD
    -- anchors independent so a later native layout pass can never create a
    -- Bar <-> Icon dependency cycle before our post-hook restores the layout.
    if position == "right" then
        changed = SetRegionPointIfChanged(
            bar,
            "LEFT",
            frame,
            "LEFT",
            0,
            0
        ) or changed
        changed = SetRegionPointIfChanged(
            icon,
            "LEFT",
            frame,
            "LEFT",
            barWidth + gap,
            0
        ) or changed
    elseif position == "top" then
        changed = SetRegionPointIfChanged(
            bar,
            "BOTTOM",
            frame,
            "BOTTOM",
            0,
            0
        ) or changed
        changed = SetRegionPointIfChanged(
            icon,
            "BOTTOM",
            frame,
            "BOTTOM",
            0,
            barHeight + gap
        ) or changed
    elseif position == "bottom" then
        changed = SetRegionPointIfChanged(
            bar,
            "TOP",
            frame,
            "TOP",
            0,
            0
        ) or changed
        changed = SetRegionPointIfChanged(
            icon,
            "TOP",
            frame,
            "TOP",
            0,
            -(barHeight + gap)
        ) or changed
    else
        changed = SetRegionPointIfChanged(
            icon,
            "LEFT",
            frame,
            "LEFT",
            0,
            0
        ) or changed
        changed = SetRegionPointIfChanged(
            bar,
            "LEFT",
            frame,
            "LEFT",
            iconSize + gap,
            0
        ) or changed
    end
    return changed
end

function NativeBridge:RefreshNativeBarDurationText(frame)
    local styleState = self.frameStates[frame]
    if not self.active or not styleState or styleState.nativeManaged ~= true
        or styleState.compactDurationTextEnabled ~= true
        or not styleState.compactDurationFormatter or IsNativeEditModeActive() then
        return false
    end
    local visibleOK, visible = SafeMethod(frame, "IsVisible")
    if visibleOK and SafeBoolean(visible) ~= true then return false end
    local text = frame.Bar and frame.Bar.Duration
    local shownOK, shown = SafeMethod(text, "IsShown")
    if not shownOK or SafeBoolean(shown) ~= true then return false end
    local cooldownOK, expirationTime = SafeMethod(frame, "GetCooldownValues")
    expirationTime = cooldownOK and SafeNumber(expirationTime) or nil
    local currentTime = _G.GetTime and SafeNumber(_G.GetTime()) or nil
    if not expirationTime or not currentTime then return false end
    local remaining = expirationTime - currentTime
    -- 原生短秒数不变；受限值已在 SafeNumber 处拒绝，不读取文字反推计时。
    if remaining < 60 then return false end
    local formattedOK, formatted = SafeMethod(styleState.compactDurationFormatter, "FormatNumber", remaining)
    if not formattedOK then return false end
    local written = SafeMethod(text, "SetText", formatted)
    if written then AddStat("nativeDurationTextWrites") end
    return written
end

function NativeBridge._OnNativeBarDurationRefresh(frame)
    NativeBridge:RefreshNativeBarDurationText(frame)
end

function NativeBridge:_InstallNativeBarDurationFormatter(frame, styleState, appearance)
    if not (YHUD.Client and YHUD.Client.nativeBuffBarSeconds == true) then return end
    styleState.compactDurationTextEnabled = appearance and appearance.enabled ~= false
    local gui = YUI.GUI2
    styleState.compactDurationFormatter = gui and gui.GetDurationTextFormatter
        and gui:GetDurationTextFormatter() or nil
    if not styleState.compactDurationFormatter then return end
    if not NativeBridge.barDurationHookedFrames[frame]
        and type(frame.RefreshCooldownInfo) == "function" and _G.hooksecurefunc then
        local ok = pcall(_G.hooksecurefunc, frame, "RefreshCooldownInfo", self._OnNativeBarDurationRefresh)
        if ok then NativeBridge.barDurationHookedFrames[frame] = true end
    end
    NativeBridge:RefreshNativeBarDurationText(frame)
end

local function ApplyBarVisualStyle(frame, runtime, binding, styleState)
    local bar = frame and frame.Bar
    if not bar then return false end
    styleState = styleState or GetFrameStyleState(frame)
    local count = frame.Icon and frame.Icon.Applications
    -- 原生控件复用时可能替换文字对象；缓存与恢复快照必须跟随对象身份。
    if styleState.nameTextRegion and styleState.nameTextRegion ~= bar.Name then
        RestoreFontString(styleState.nameTextRegion, styleState.nameFont)
        styleState.nameFont = CaptureFontString(bar.Name)
        styleState.nameState, styleState.nameAnchorState = nil, nil
    end
    if styleState.cooldownTextRegion and styleState.cooldownTextRegion ~= bar.Duration then
        RestoreFontString(styleState.cooldownTextRegion, styleState.durationFont)
        styleState.durationFont = CaptureFontString(bar.Duration)
        styleState.durationState, styleState.durationAnchorState = nil, nil
    end
    if styleState.countTextRegion and styleState.countTextRegion ~= count then
        RestoreFontString(styleState.countTextRegion, styleState.applicationFont)
        styleState.applicationFont = CaptureFontString(count)
        styleState.countState, styleState.countAnchorState = nil, nil
    end
    styleState.nameTextRegion = bar.Name
    styleState.cooldownTextRegion = bar.Duration
    styleState.countTextRegion = count
    local gui = YUI.GUI2
    local statusSnapshot = BuildEffectiveStatusSnapshot(
        runtime,
        binding,
        styleState
    )
    NativeBridge:_InstallNativeBarDurationFormatter(frame, styleState, statusSnapshot and statusSnapshot.timeText)
    local iconChanged = NativeBridge:_ApplyNativeBarIconVisibility(
        frame,
        styleState,
        styleState.compiledIcon,
        statusSnapshot and statusSnapshot.showIcon
    )
    if gui and gui.ApplyStatusBarChrome and statusSnapshot then
        styleState.statusTarget = EnsureNativeStatusChrome(
            bar,
            styleState
        ) or styleState.statusTarget
        if not styleState.barStatusCaptured then
            styleState.driverStatusTarget = { statusBar = bar }
            styleState.driverStatusState = {}
            gui:CaptureVisual(
                styleState.driverStatusTarget,
                styleState.driverStatusState
            )
            styleState.barStatusCaptured = true
        end
        local chrome = styleState.nativeStatusChrome
        if chrome and gui.EnsureProjectedStatusBarFill then
            local projection = chrome.projection
            if not projection then
                projection = {}
                chrome.projection = projection
            end
            if not projection.nativeVisibleStatusBar then
                gui:EnsureProjectedStatusBarFill(
                    projection,
                    bar,
                    bar,
                    {
                        parent = bar,
                        clipFrameLevelOffset = 1,
                        visibleFrameLevelOffset = 1,
                        fillLayer = "ARTWORK",
                        fillSubLevel = 0,
                        orientation = runtime.orientation,
                        fillDirection = runtime.fillDirection or "forward",
                    }
                )
            else
                gui:SetProjectedStatusBarDirection(
                    projection,
                    runtime.orientation,
                    runtime.fillDirection or "forward",
                    true
                )
            end
            gui:SetProjectedStatusBarShown(projection, true)
            if chrome.overlay then
                chrome.overlay:Show()
            end
            if not chrome.textOverlay then
                chrome.textOverlay = CreateFrame("Frame", nil, frame)
                chrome.textOverlay:SetAllPoints(frame)
                SafeMethod(chrome.textOverlay, "EnableMouse", false)
            end
            local textLevel, textStrata = NativeBridge:_ResolveTextLayer(
                runtime, GetSafeFrameLevel(frame)
            )
            SetFrameLevelIfChanged(chrome.textOverlay, textLevel)
            SetFrameStrataIfChanged(chrome.textOverlay, textStrata)
            chrome.textOverlay:Show()
            if SetRegionParentIfChanged(bar.Name, chrome.textOverlay)
                and styleState.nameAnchorState then styleState.nameAnchorState.target = nil end
            if SetRegionParentIfChanged(bar.Duration, chrome.textOverlay)
                and styleState.durationAnchorState then styleState.durationAnchorState.target = nil end
            if SetRegionParentIfChanged(count, chrome.textOverlay)
                and styleState.countAnchorState then styleState.countAnchorState.target = nil end
            SetIconTextDrawLayer(bar.Name)
            SetIconTextDrawLayer(bar.Duration)
            SetIconTextDrawLayer(count)
            styleState.statusTarget.statusBar =
                projection.nativeVisibleStatusBar
            styleState.statusTarget.orientation = runtime.orientation
            styleState.statusTarget.fillDirection =
                runtime.fillDirection or "forward"
        end
        gui:ApplyStatusBarChrome(
            styleState.statusTarget,
            statusSnapshot,
            styleState.statusState
        )
        if chrome and gui.RefreshProjectedStatusBarLayer then
            gui:RefreshProjectedStatusBarLayer(chrome.projection)
        end
    end
    if gui and gui.ApplyTextStyle and statusSnapshot then
        styleState.nameState = styleState.nameState or {}
        styleState.durationState = styleState.durationState or {}
        styleState.countState = styleState.countState or {}
        styleState.nameState.preserveAnchors = true
        styleState.durationState.preserveAnchors = true
        styleState.countState.preserveAnchors = true
        gui:ApplyTextStyle(
            bar.Name,
            statusSnapshot.nameText,
            styleState.nameState
        )
        gui:ApplyTextStyle(
            bar.Duration,
            statusSnapshot.timeText,
            styleState.durationState
        )
        gui:ApplyTextStyle(
            styleState.countTextRegion,
            statusSnapshot.countText,
            styleState.countState
        )
        if gui.PositionStatusBarText then
            styleState.nameAnchorState = styleState.nameAnchorState or {}
            gui:PositionStatusBarText(
                bar.Name, statusSnapshot.nameText, runtime.orientation,
                bar, frame.Icon, statusSnapshot.showIcon, "name",
                styleState.nameAnchorState, nil,
                statusSnapshot.showIcon == false and runtime.itemWidth or runtime.barWidth
            )
            styleState.durationAnchorState =
                styleState.durationAnchorState or {}
            gui:PositionStatusBarText(
                bar.Duration,
                statusSnapshot.timeText,
                runtime.orientation,
                bar,
                frame.Icon,
                statusSnapshot.showIcon,
                "time",
                styleState.durationAnchorState
            )
            styleState.countAnchorState = styleState.countAnchorState or {}
            gui:PositionStatusBarText(
                styleState.countTextRegion,
                statusSnapshot.countText,
                runtime.orientation,
                bar,
                frame.Icon,
                statusSnapshot.showIcon,
                "count",
                styleState.countAnchorState
            )
            if count and gui.SizeStatusBarCountText then
                gui:SizeStatusBarCountText(count, statusSnapshot.countText, styleState.countState)
            end
        end
    end
    local projection = styleState.nativeStatusChrome
        and styleState.nativeStatusChrome.projection
    local view = YHUD.View
    if projection and view and view.ConfigureBarStackThresholds then
        local monitor = binding and view.desiredMonitors[binding.monitorId]
        local entry = monitor and view.profile and view.profile.entries[monitor.entryKey]
        local showIcon = runtime.showIcon ~= false
        view:ConfigureBarStackThresholds(projection, runtime, monitor, entry,
            showIcon and (runtime.barWidth or 220) or (runtime.itemWidth or 244))
        local chrome = styleState.nativeStatusChrome
        if gui.RaiseAuraBarThresholdOverlay then
            gui:RaiseAuraBarThresholdOverlay(projection, chrome.overlay, 1)
            gui:RaiseAuraBarThresholdOverlay(projection, chrome.textOverlay, 2)
        end
    end
    return statusSnapshot ~= nil or iconChanged
end

local function PreviewTextRegionColor(region, color)
    if not (region and type(color) == "table") then return false end
    local r = type(color.r) == "number" and color.r or color[1]
    local g = type(color.g) == "number" and color.g or color[2]
    local b = type(color.b) == "number" and color.b or color[3]
    local a = type(color.a) == "number" and color.a or color[4]
    if type(r) ~= "number" or type(g) ~= "number"
        or type(b) ~= "number" then
        return false
    end
    return SafeMethod(region, "SetTextColor", r, g, b, a or 1)
end

function NativeBridge:PreviewGroupTextColor(groupId, target, color)
    if type(groupId) ~= "string" or groupId == "" then return false end
    local field = target == "name" and "nameTextRegion"
        or (target == "count" and "countTextRegion"
            or "cooldownTextRegion")
    local changed = false
    for _, styleState in pairs(self.frameStates) do
        if styleState.nativeIncluded == true
            and styleState.nativeGroupId == groupId then
            changed = PreviewTextRegionColor(styleState[field], color) or changed
        end
    end
    return changed
end

local function FinalizeNativeBar(frame, runtime, binding, styleState)
    if not (frame and runtime and frame.Bar and frame.Icon) then return false end
    local changed = SetRegionScaleIfChanged(frame, 1)
    changed = SetRegionSizeIfChanged(
        frame,
        runtime.itemWidth or 244,
        runtime.itemHeight or 24
    ) or changed
    changed = PositionNativeBar(frame, runtime) or changed

    local bar = frame.Bar
    styleState = styleState or GetFrameStyleState(frame)
    styleState.statusState = styleState.statusState or {}
    styleState.nameState = styleState.nameState or {}
    -- Blizzard owns the text regions and may re-show the name while updating
    -- an active bar. Reassert only the visibility bit; material caches stay
    -- intact so the projected business texture remains a zero-write path.
    styleState.nameState.shown = nil
    if styleState.nameAnchorState then
        styleState.nameAnchorState.target = nil
    end
    if styleState.durationAnchorState then
        styleState.durationAnchorState.target = nil
    end
    if styleState.countAnchorState then
        styleState.countAnchorState.target = nil
    end
    changed = ApplyBarVisualStyle(frame, runtime, binding, styleState) or changed
    SuppressNativeRegionWhileStyled(
        frame,
        styleState,
        bar.BarBG,
        "bar-background"
    )
    SuppressNativeRegionWhileStyled(
        frame,
        styleState,
        bar.Pip,
        "bar-pip"
    )
    return changed
end

local function OnNativeBarContentChanged(frame)
    if not NativeBridge.active or IsNativeEditModeActive() then return false end
    local styleState = frame and NativeBridge.frameStates[frame]
    if not (styleState and styleState.nativeIncluded == true) then return false end
    local descriptor = DESCRIPTOR_BY_CATEGORY[styleState.nativeCategory]
    local runtime = styleState.nativeStyleRuntime
    if not (descriptor and descriptor.kind == "bar" and runtime) then
        return false
    end
    AddStat("barContentSignals")
    local changed = FinalizeNativeBar(
        frame,
        runtime,
        styleState.nativeStyleBinding,
        styleState
    )
    if changed then AddStat("barContentRewrites") end
    return changed
end

local function OnNativeBarShownStateChanged(frame)
    if not NativeBridge.active or IsNativeEditModeActive() then return false end
    local styleState = frame and NativeBridge.frameStates[frame]
    local category = styleState and styleState.nativeCategory
    local descriptor = category and DESCRIPTOR_BY_CATEGORY[category]
    if not (descriptor and descriptor.kind == "bar"
        and descriptor.dynamicVisibility == true) then
        return false
    end
    return NativeBridge:OnOfficialAuraFrameRefresh(
        nil,
        nil,
        nil,
        frame,
        category,
        GetCooldownID(frame)
    )
end

local function InstallNativeBarContentHooks(frame)
    local hook = _G.hooksecurefunc
    if not (frame and type(hook) == "function") then return false end
    local installed = NativeBridge.barContentHookedFrames[frame]
    if not installed then
        installed = {}
        NativeBridge.barContentHookedFrames[frame] = installed
    end
    local changed = false
    local function Install(methodName, field)
        if installed[field] == true or type(frame[methodName]) ~= "function" then
            return
        end
        local ok = pcall(hook, frame, methodName, function()
            OnNativeBarContentChanged(frame)
        end)
        if ok then
            installed[field] = true
            changed = true
        end
    end
    Install("SetBarContent", "content")
    Install("SetBarWidth", "width")
    if type(frame.HookScript) == "function" then
        if installed.show ~= true then
            local ok = pcall(frame.HookScript, frame, "OnShow", function()
                OnNativeBarShownStateChanged(frame)
            end)
            if ok then
                installed.show = true
                changed = true
            end
        end
        if installed.hide ~= true then
            local ok = pcall(frame.HookScript, frame, "OnHide", function()
                OnNativeBarShownStateChanged(frame)
            end)
            if ok then
                installed.hide = true
                changed = true
            end
        end
    end
    return changed
end

local function ApplyBarStyle(frame, runtime, binding)
    local styleState = GetFrameStyleState(frame)
    if not styleState.barGeometryCaptured then
        local iconFrame = frame.Icon
        local bar = frame.Bar
        styleState.iconGeometry = CaptureRegionGeometry(iconFrame)
        styleState.barGeometry = CaptureRegionGeometry(bar)
        styleState.barBackgroundGeometry =
            CaptureRegionGeometry(bar and bar.BarBG)
        styleState.pipGeometry = CaptureRegionGeometry(bar and bar.Pip)
        styleState.nameFont = CaptureFontString(bar and bar.Name)
        styleState.durationFont =
            CaptureFontString(bar and bar.Duration)
        styleState.applicationFont =
            CaptureFontString(iconFrame and iconFrame.Applications)
        styleState.barIconTextureGeometry =
            CaptureRegionGeometry(iconFrame and iconFrame.Icon)
        styleState.barGeometryCaptured = true
    end
    SetRegionScaleIfChanged(frame, 1)
    SetRegionSizeIfChanged(
        frame,
        runtime.itemWidth or 244,
        runtime.itemHeight or 24
    )
    PositionNativeBar(frame, runtime)
    local iconFrame = frame.Icon
    local icon = iconFrame and iconFrame.Icon
    local gui = YUI.GUI2
    local iconSnapshot = runtime.iconStyle
        or (gui and gui.CompileIconStyle
            and gui:CompileIconStyle(runtime, styleState.compiledIcon))
    styleState.compiledIcon = iconSnapshot
    if gui and gui.ApplyIconChrome and iconSnapshot then
        styleState.iconTarget = EnsureNativeIconChrome(
            iconFrame,
            icon,
            nil,
            styleState,
            iconSnapshot
        ) or styleState.iconTarget or { icon = icon }
        if not styleState.barIconCaptured then
            gui:CaptureVisual(styleState.iconTarget, styleState.iconState)
            styleState.barIconCaptured = true
        end
        gui:ApplyIconChrome(
            styleState.iconTarget,
            iconSnapshot,
            styleState.iconState
        )
    end

    local bar = frame.Bar
    if bar then
        ApplyBarVisualStyle(frame, runtime, binding, styleState)
        SuppressNativeRegionWhileStyled(
            frame,
            styleState,
            bar.BarBG,
            "bar-background"
        )
        SuppressNativeRegionWhileStyled(
            frame,
            styleState,
            bar.Pip,
            "bar-pip"
        )
    end
end

local function ApplyNativeKeybindText(
    frame,
    runtime,
    descriptor,
    binding,
    styleState
)
    local service = YHUD.KeybindText
    local eligible = descriptor and descriptor.kind == "icon"
        and descriptor.category ~= "trackedBuff"
        and runtime and runtime.layoutType == "icons"
        and binding and service and service.Resolve
    local text = eligible and service:Resolve(runtime, nil, nil, binding) or nil
    local retained = NativeBridge.keybindStates[frame]
    if retained and not styleState.keybindText then
        styleState.keybindOverlay = retained.overlay
        styleState.keybindText = retained.text
        styleState.keybindTextState = retained.state
        styleState.keybindTextValue = retained.value or ""
        styleState.keybindOverlayShown = retained.shown == true
    end
    if not text and not styleState.keybindText then return 0 end
    local gui = YUI.GUI2
    if not (gui and gui.CreateFrame and gui.CreateText
        and gui.ApplyTextStyle) then
        return 0
    end
    if not styleState.keybindText then
        if IsInCombat() then
            if NativeBridge.ScheduleDeferred then
                NativeBridge:ScheduleDeferred("sync")
            end
            return 0
        end
        local level = GetSafeFrameLevel(frame)
        local overlay = gui:CreateFrame(frame, {
            allPoints = true,
            mouse = false,
            frameLevel = level + 10,
        })
        styleState.keybindOverlay = overlay
        styleState.keybindText = gui:CreateText(
            overlay, "", 12, nil, "RIGHT"
        )
        styleState.keybindTextState = {}
        styleState.keybindTextValue = ""
        overlay:Hide()
        retained = {
            overlay = overlay,
            text = styleState.keybindText,
            state = styleState.keybindTextState,
            value = "",
            shown = false,
        }
        NativeBridge.keybindStates[frame] = retained
    end
    local writes = 0
    local value = text or ""
    if styleState.keybindTextValue ~= value then
        styleState.keybindText:SetText(value)
        styleState.keybindTextValue = value
        writes = writes + 1
    end
    local snapshot = styleState.keybindTextSnapshot
    if not snapshot then
        snapshot = {}
        styleState.keybindTextSnapshot = snapshot
    end
    snapshot.enabled = text ~= nil
    snapshot.font = runtime and runtime.keybindTextFont
    snapshot.size = runtime and runtime.keybindTextSize
    snapshot.outline = runtime and runtime.keybindTextOutline
    snapshot.position = runtime and runtime.keybindTextPosition
    snapshot.offsetX = runtime and runtime.keybindTextOffsetX
    snapshot.offsetY = runtime and runtime.keybindTextOffsetY
    snapshot.color = runtime and runtime.keybindTextColor
    writes = writes + gui:ApplyTextStyle(
        styleState.keybindText,
        snapshot,
        styleState.keybindTextState
    )
    local level = GetSafeFrameLevel(frame)
    local textLevel = NativeBridge:_ResolveTextLayer(runtime, level)
    if SetFrameLevelIfChanged(
        styleState.keybindOverlay,
        textLevel
    ) then
        writes = writes + 1
    end
    if SetIconTextDrawLayer(styleState.keybindText) then
        writes = writes + 1
    end
    local shown = text ~= nil
    if styleState.keybindOverlayShown ~= shown then
        if shown then
            styleState.keybindOverlay:Show()
        else
            styleState.keybindOverlay:Hide()
        end
        styleState.keybindOverlayShown = shown
        writes = writes + 1
    end
    retained = retained or NativeBridge.keybindStates[frame]
    if retained then
        retained.value = styleState.keybindTextValue
        retained.shown = styleState.keybindOverlayShown
    end
    return writes
end

local function ApplyNativeStyle(
    frame,
    runtime,
    descriptor,
    binding,
    styleRevision,
    forceGeometry
)
    local styleState = GetFrameStyleState(frame)
    ApplyNativeFrameLayers(frame, styleState, runtime, binding)
    if descriptor.kind == "bar" then
        InstallNativeBarContentHooks(frame)
    end
    ApplyNativeTooltipMouse(frame, runtime, styleState)
    ApplyNativeKeybindText(frame, runtime, descriptor, binding, styleState)
    styleState.pandemicCategory = descriptor.category
    local styleUnchanged = styleState.nativeStyleCategory
            == descriptor.category
        and styleState.nativeStyleRevision == styleRevision
        and styleState.nativeStyleRuntime == runtime
        and styleState.nativeStyleBinding == binding
    if styleUnchanged then
        if descriptor.kind == "bar" then
            FinalizeNativeBar(frame, runtime, binding, styleState)
        else
            if forceGeometry == true then
                ApplyIconFrameGeometry(frame, runtime, styleState)
            end
            local view = YHUD.View
            local shadow = view and view.iconShadowStates and view.iconShadowStates[frame]
            if shadow and (shadow.pending or (shadow.handle and shadow.handle.pending))
                and view.ApplyIconShadow then
                view:ApplyIconShadow(frame, runtime, not IsInCombat())
            end
            ApplyCooldownFlash(
                frame,
                styleState,
                styleState.compiledIcon
            )
        end
        EnsurePandemicGlow(frame, styleState, runtime, descriptor)
        SyncCurrentPandemicAppearance(frame, descriptor)
        if forceGeometry == true then
            styleState.nativeProcGlowLayoutDirty = true
        end
        SyncNativeProcGlow(frame, styleState, styleState.compiledIcon)
        return false
    end
    if descriptor.kind ~= "bar" then
        ApplyIconFrameGeometry(frame, runtime, styleState)
    end
    if descriptor.kind == "bar" then
        ApplyBarStyle(frame, runtime, binding)
    else
        ApplyIconStyle(frame, runtime, descriptor, binding)
    end
    EnsurePandemicGlow(frame, styleState, runtime, descriptor)
    SyncCurrentPandemicAppearance(frame, descriptor)
    styleState.nativeStyleCategory = descriptor.category
    styleState.nativeStyleRevision = styleRevision
    styleState.nativeStyleRuntime = runtime
    styleState.nativeStyleBinding = binding
    styleState.nativeProcGlowLayoutDirty = true
    SyncNativeProcGlow(frame, styleState, styleState.compiledIcon)
    return true
end

function NativeBridge:ApplyManagedFrameLayers()
    local changed = false
    for frame, styleState in pairs(self.frameStates) do
        if styleState.nativeIncluded == true then
            local runtime = styleState.nativeStyleRuntime
                or styleState.nativeLayerRuntime
            local binding = styleState.nativeStyleBinding
                or styleState.nativeLayerBinding
                or styleState.nativeBinding
                or styleState.binding
            if runtime then
                changed = ApplyNativeFrameLayers(
                    frame,
                    styleState,
                    runtime,
                    binding
                ) or changed
                local descriptor = styleState.nativeCategory
                    and DESCRIPTOR_BY_CATEGORY[styleState.nativeCategory]
                if descriptor and descriptor.kind == "bar" then
                    FinalizeNativeBar(frame, runtime, binding, styleState)
                else
                    local count = frame.ChargeCount
                        and frame.ChargeCount.Current
                    if not count and frame.Applications then
                        count = frame.Applications.Applications
                    end
                    local ok, cooldownText = SafeMethod(
                        frame.Cooldown,
                        "GetCountdownFontString"
                    )
                    ApplyNativeIconTextLayers(
                        frame,
                        styleState,
                        runtime,
                        ok and cooldownText or nil,
                        count
                    )
                    if styleState.keybindOverlay then
                        local rootOK, rootLevel = SafeMethod(
                            frame,
                            "GetFrameLevel"
                        )
                        rootLevel = rootOK and SafeNumber(rootLevel) or 0
                        local textLevel = self:_ResolveTextLayer(
                            runtime,
                            rootLevel
                        )
                        changed = SetFrameLevelIfChanged(
                            styleState.keybindOverlay,
                            textLevel
                        ) or changed
                    end
                end
            end
        end
    end
    return changed
end

local function ResetVisualStateCache(cache)
    if type(cache) ~= "table" then return {} end
    local original = cache.original
    for key in pairs(cache) do
        cache[key] = nil
    end
    cache.original = original
    return cache
end

local function InvalidateFrameStyle(frame)
    local state = frame and NativeBridge.frameStates[frame]
    if not state then return end
    state.nativeStyleCategory = nil
    state.nativeStyleRevision = nil
    state.nativeStyleRuntime = nil
    state.nativeStyleBinding = nil
    state.iconState = ResetVisualStateCache(state.iconState)
    state.cooldownState = ResetVisualStateCache(state.cooldownState)
    state.statusState = ResetVisualStateCache(state.statusState)
    state.countState = ResetVisualStateCache(state.countState)
    state.countNaturalSizeRegion = nil
    state.nativeProcGlowLayoutDirty = true
end

function NativeBridge:OnPandemicFrameSetup(viewer, frame, category)
    if not self.active or IsNativeEditModeActive() or not (viewer and frame) then
        return false
    end
    local descriptor = DESCRIPTOR_BY_CATEGORY[category]
    local state = descriptor and GetState(category) or nil
    local styleState = self.frameStates[frame]
    if not (descriptor and state and state.viewer == viewer
        and styleState and styleState.nativeManaged == true) then
        return false
    end
    local pool = viewer.pandemicIconPool
    if not (pool and type(pool.EnumerateActive) == "function") then
        return false
    end
    for region in pool:EnumerateActive() do
        local ok, parent = SafeMethod(region, "GetParent")
        if ok and parent == frame then
            return ObservePandemicRegion(frame, descriptor, region)
        end
    end
    return false
end

local function DetachStaticFrameBinding(styleState, frame, view, category)
    local binding = styleState and styleState.nativeBinding
    if not (binding and binding.groupId and binding.monitorId
        and view and view.DetachNativeStableFrame) then
        return false
    end
    return view:DetachNativeStableFrame(
        binding.groupId,
        binding.monitorId,
        frame,
        category
    )
end

local function MarkStaticGroupDirty(state, groupId)
    if state and groupId then state.dirtyStaticGroups[groupId] = true end
end

local function RequestStaticMemberLayout(state, category, previousGroupId, groupId)
    local wasEmpty = next(state.dirtyStaticGroups) == nil
    MarkStaticGroupDirty(state, previousGroupId)
    MarkStaticGroupDirty(state, groupId)
    if not next(state.dirtyStaticGroups) then return false end
    if not wasEmpty then return true end
    return NativeBridge:RequestCategorySync(
        category,
        "static-membership",
        DIRTY_MEMBERSHIP
    )
end

function NativeBridge:OnStaticFrameCooldownIDSet(frame)
    if not self.active or IsNativeEditModeActive() or not frame then return false end
    local styleState = self.frameStates[frame]
    local category = styleState and styleState.nativeCategory
    local descriptor = category and DESCRIPTOR_BY_CATEGORY[category]
    local state = descriptor and GetState(category) or nil
    if not (descriptor and descriptor.dynamicVisibility ~= true
        and state and state.monitorByCooldown
        and state.viewer == styleState.nativeViewer) then
        return false
    end

    AddStat("staticCooldownSignals")
    local startedAt = ProfileNowMS()
    local view = YHUD.View
    local previousBinding = styleState.nativeBinding
        or styleState.staticPreviousBinding
    local previousGroupId = styleState.staticPreviousGroupId
        or (previousBinding and previousBinding.groupId)
    local previousMonitorId = styleState.staticPreviousMonitorId
        or (previousBinding and previousBinding.monitorId)
    styleState.staticPreviousGroupId = nil
    styleState.staticPreviousMonitorId = nil
    styleState.staticPreviousBinding = nil
    local cooldownID = GetCooldownID(frame)
    local binding = cooldownID and state.monitorByCooldown[cooldownID]
    -- A pooled static frame can briefly lose its public cooldown identity while
    -- Blizzard rebuilds the viewer. Keep the last confirmed binding until the
    -- active-pool consistency pass either sees a new identity or confirms that
    -- the frame was released.
    if not cooldownID and previousBinding then
        binding = previousBinding
    end
    if previousBinding ~= binding then
        DetachStaticFrameBinding(styleState, frame, view, category)
    end
    styleState.nativeBinding = binding
    styleState.pandemicCategory = category
    GetAlphaBaseline(state, frame)
    state.itemAlphaFrames[frame] = true

    local runtime = binding and view and view.groups
        and view.groups[binding.groupId]
    if not (runtime and binding.monitorId
        and view.ReattachNativeStableFrame) then
        styleState.nativeManaged = false
        styleState.nativeIncluded = false
        styleState.nativeGroupId = nil
        ApplyManagedFrameVisibility(state, frame, styleState, true)
        if previousGroupId then
            RequestStaticMemberLayout(
                state,
                category,
                previousGroupId,
                nil
            )
        end
        RecordProfileElapsed(
            "staticCooldownElapsedMS",
            "staticCooldownMaxMS",
            startedAt
        )
        return false
    end

    styleState.nativeManaged = true
    styleState.nativeIncluded = true
    styleState.nativeGroupId = binding.groupId
    ApplyNativeStyle(
        frame,
        runtime,
        descriptor,
        binding,
        state.styleRevision,
        true
    )
    InstallNativeProcHooks(frame)
    InstallSkillAuraDisplayHook(frame, descriptor)
    ApplySkillAuraDisplay(frame, "native-refresh")
    ApplyManagedFrameVisibility(state, frame, styleState, true)
    local reattached = view:ReattachNativeStableFrame(
        binding.groupId,
        binding.monitorId,
        frame,
        category
    )
    local stableSlot = runtime.nativeStableSlots
        and runtime.nativeStableSlots[binding.monitorId]
    local projectedSlot = runtime.nativeByMonitor
        and runtime.nativeByMonitor[binding.monitorId]
    if previousGroupId ~= binding.groupId
        or previousMonitorId ~= binding.monitorId
        or not projectedSlot
        or projectedSlot ~= stableSlot then
        RequestStaticMemberLayout(
            state,
            category,
            previousGroupId,
            binding.groupId
        )
    end
    RecordProfileElapsed(
        "staticCooldownElapsedMS",
        "staticCooldownMaxMS",
        startedAt
    )
    return reattached
end

function NativeBridge:OnStaticFrameSetPoint(
    frame,
    point,
    relativeTo,
    relativePoint,
    x,
    y
)
    if not self.active or IsNativeEditModeActive() or not frame then return false end
    local styleState = self.frameStates[frame]
    local binding = styleState and styleState.nativeBinding
    local state = styleState and styleState.nativeCategory
        and self.states[styleState.nativeCategory]
    if styleState and styleState.nativeParkingWrite ~= true
        and styleState.nativeParked == true then
        if styleState.nativeManaged == true then
            styleState.nativeParked = false
        else
            point = SafeString(point)
            relativePoint = SafeString(relativePoint)
            x = SafeNumber(x)
            y = SafeNumber(y)
            if point and relativePoint and x and y then
                styleState.nativeOriginalPoints = {
                    { point, relativeTo, relativePoint, x, y },
                }
            end
            return ApplyStaticFrameParking(frame, styleState, true)
        end
    end
    if not (styleState and styleState.nativeIncluded == true
        and styleState.repairingStaticPosition ~= true
        and state and state.viewer == styleState.nativeViewer
        and binding and binding.groupId and binding.monitorId) then
        return false
    end
    local view = YHUD.View
    local runtime = view and view.groups and view.groups[binding.groupId]
    local slots = runtime and runtime.nativeStableSlots
    local slot = slots and slots[binding.monitorId]
    if not slot or relativeTo == slot or not view.ReattachNativeStableFrame then
        return false
    end

    local startedAt = ProfileNowMS()
    styleState.repairingStaticPosition = true
    local repaired = view:ReattachNativeStableFrame(
        binding.groupId,
        binding.monitorId,
        frame,
        styleState.nativeCategory
    )
    styleState.repairingStaticPosition = nil
    if repaired then AddStat("staticPositionRepairs") end
    RecordProfileElapsed(
        "staticPositionElapsedMS",
        "staticPositionMaxMS",
        startedAt
    )
    return repaired
end

local function OnStaticCooldownIDSet(frame)
    NativeBridge:OnStaticFrameCooldownIDSet(frame)
end

local function OnStaticSetPoint(
    frame,
    point,
    relativeTo,
    relativePoint,
    x,
    y
)
    NativeBridge:OnStaticFrameSetPoint(
        frame,
        point,
        relativeTo,
        relativePoint,
        x,
        y
    )
end

local function InstallStaticFrameHooks(frame)
    if not frame then return false end
    local hook = _G.hooksecurefunc
    if type(hook) ~= "function" then return false end
    local installed = false
    if not NativeBridge.staticCooldownHookedFrames[frame]
        and type(frame.OnCooldownIDSet) == "function" then
        local ok = pcall(hook, frame, "OnCooldownIDSet", OnStaticCooldownIDSet)
        if ok then NativeBridge.staticCooldownHookedFrames[frame] = true end
        installed = installed or ok
    end
    if not NativeBridge.staticPositionHookedFrames[frame]
        and type(frame.SetPoint) == "function" then
        local ok = pcall(hook, frame, "SetPoint", OnStaticSetPoint)
        if ok then NativeBridge.staticPositionHookedFrames[frame] = true end
        installed = installed or ok
    end
    return installed
end

function NativeBridge:OnStaticFrameAcquired(viewer, frame, category)
    if not self.active or IsNativeEditModeActive() or not (viewer and frame) then
        return false
    end
    local descriptor = DESCRIPTOR_BY_CATEGORY[category]
    local state = descriptor and GetState(category) or nil
    if not (descriptor and descriptor.dynamicVisibility ~= true
        and state and state.viewer == viewer) then
        return false
    end

    AddStat("itemFrameAcquireSignals")
    local startedAt = ProfileNowMS()
    InstallStaticFrameHooks(frame)
    local styleState = GetFrameStyleState(frame)
    if not styleState.nativeOriginalPoints then
        styleState.nativeOriginalPoints = CaptureFramePoints(frame)
    end
    local previousBinding = styleState.nativeBinding
    styleState.staticPreviousBinding = previousBinding
    styleState.staticPreviousGroupId = previousBinding
        and previousBinding.groupId or nil
    styleState.staticPreviousMonitorId = previousBinding
        and previousBinding.monitorId or nil
    styleState.nativeCategory = category
    styleState.nativeViewer = viewer
    styleState.pandemicCategory = category
    GetAlphaBaseline(state, frame)
    state.itemAlphaFrames[frame] = true
    if state.lastAlpha then state.lastAlpha[frame] = nil end
    if not previousBinding then
        styleState.nativeBinding = nil
        styleState.nativeManaged = false
        styleState.nativeIncluded = false
        styleState.nativeGroupId = nil
        ApplyManagedFrameVisibility(state, frame, styleState, true)
    end
    RecordProfileElapsed(
        "itemFrameAcquireElapsedMS",
        "itemFrameAcquireMaxMS",
        startedAt
    )
    return true
end

function NativeBridge:OnStaticViewerLayoutComplete(viewer, category)
    if not self.active or IsNativeEditModeActive() or not viewer then return false end
    local descriptor = DESCRIPTOR_BY_CATEGORY[category]
    local state = descriptor and GetState(category) or nil
    if not (descriptor and descriptor.dynamicVisibility ~= true
        and state and state.viewer == viewer) then
        return false
    end

    AddStat("staticLayoutSignals")
    local frames, activePoolComplete = GetOfficialFrames(viewer)
    AddStat("staticLayoutScannedFrames", #frames)
    MaxStat("staticLayoutMaxFrames", #frames)
    local repaired = false
    local generation = (state.staticLayoutGeneration or 0) + 1
    state.staticLayoutGeneration = generation
    for index = 1, #frames do
        local frame = frames[index]
        local styleState = self.frameStates[frame]
        if styleState then styleState.staticLayoutGeneration = generation end
        local cooldownID = GetCooldownID(frame)
        local binding = cooldownID and state.monitorByCooldown
            and state.monitorByCooldown[cooldownID]
        if not cooldownID and styleState and styleState.nativeBinding then
            binding = styleState.nativeBinding
        end
        local needsRepair = not styleState
            or styleState.nativeBinding ~= binding
        if not needsRepair and binding then
            local runtime = YHUD.View and YHUD.View.groups
                and YHUD.View.groups[binding.groupId]
            local slot = runtime and runtime.nativeStableSlots
                and runtime.nativeStableSlots[binding.monitorId]
            local ok, _, relativeTo = SafeMethod(frame, "GetPoint", 1)
            needsRepair = not (slot and ok and relativeTo == slot)
        elseif not needsRepair then
            needsRepair = styleState.nativeManaged == true
                or styleState.nativeIncluded == true
                or styleState.nativeParked ~= true
        end
        if needsRepair then
            repaired = self:OnStaticFrameCooldownIDSet(frame) or repaired
        end
    end
    if activePoolComplete then
        for frame in pairs(state.itemAlphaFrames or {}) do
            local styleState = self.frameStates[frame]
            local confirmedBinding = styleState
                and (styleState.nativeBinding
                    or styleState.staticPreviousBinding)
            if styleState and styleState.nativeCategory == category
                and styleState.nativeViewer == viewer
                and confirmedBinding
                and styleState.staticLayoutGeneration ~= generation then
                styleState.nativeBinding = confirmedBinding
                local previousGroupId = confirmedBinding.groupId
                DetachStaticFrameBinding(styleState, frame, YHUD.View, category)
                styleState.nativeBinding = nil
                styleState.staticPreviousBinding = nil
                styleState.staticPreviousGroupId = nil
                styleState.staticPreviousMonitorId = nil
                styleState.nativeManaged = false
                styleState.nativeIncluded = false
                styleState.nativeGroupId = nil
                ApplyManagedFrameVisibility(state, frame, styleState, true)
                RequestStaticMemberLayout(
                    state,
                    category,
                    previousGroupId,
                    nil
                )
                repaired = true
            end
        end
    else
        AddStat("staticLayoutReleaseAuditsSkipped")
    end
    return repaired
end

function NativeBridge:OnOfficialViewerEditModeEnter(viewer, category)
    if not self.active or not IsEditModeActive() then return false end
    local state = self.states[category]
    if not (state and state.viewer == viewer) then return false end
    self.editModeActive = true
    self.editModeExitObserved = false
    self.refreshBaseline = true
    self:CancelPendingCategorySync(true)
    if IsInCombat() then
        self:ScheduleDeferred("restore")
        return true
    end
    return self:RestoreAll("viewer-edit-mode-enter")
end

local function InstallViewerHook(state, descriptor, viewer)
    local hook = _G.hooksecurefunc
    if type(hook) ~= "function" then return false end
    local dynamic = descriptor.dynamicVisibility == true
    local layoutInstalled = state.layoutHookedViewer == viewer
    if not layoutInstalled
        and type(viewer.RefreshLayout) == "function" then
        layoutInstalled = pcall(hook, viewer, "RefreshLayout", function()
            if NativeBridge.active and not IsNativeEditModeActive()
                and state.viewer == viewer then
                if dynamic then
                    ApplyDynamicMemberLayout(state, descriptor, true)
                    NativeBridge:RequestCategorySync(
                        descriptor.category,
                        "viewer-layout",
                        DIRTY_LAYOUT
                    )
                    AddStat("dynamicLayoutSignals")
                else
                    NativeBridge:OnStaticViewerLayoutComplete(
                        viewer,
                        descriptor.category
                    )
                end
            end
        end)
        if layoutInstalled then state.layoutHookedViewer = viewer end
    end
    local editModeInstalled = state.editModeHookedViewer == viewer
    if not editModeInstalled
        and type(viewer.OnEditModeEnter) == "function" then
        editModeInstalled = pcall(
            hook,
            viewer,
            "OnEditModeEnter",
            function()
                NativeBridge:OnOfficialViewerEditModeEnter(
                    viewer,
                    descriptor.category
                )
            end
        )
        if editModeInstalled then state.editModeHookedViewer = viewer end
    end
    local acquireInstalled = dynamic or state.acquireHookedViewer == viewer
    if not dynamic and not acquireInstalled
        and type(viewer.OnAcquireItemFrame) == "function" then
        acquireInstalled = pcall(
            hook,
            viewer,
            "OnAcquireItemFrame",
            function(_, frame)
                NativeBridge:OnStaticFrameAcquired(
                    viewer,
                    frame,
                    descriptor.category
                )
            end
        )
        if acquireInstalled then state.acquireHookedViewer = viewer end
    end
    local pandemicInstalled = state.pandemicSetupHookedViewer == viewer
    if not pandemicInstalled
        and type(viewer.SetupPandemicStateFrameForItem) == "function" then
        pandemicInstalled = pcall(
            hook,
            viewer,
            "SetupPandemicStateFrameForItem",
            function(_, frame)
                NativeBridge:OnPandemicFrameSetup(
                    viewer,
                    frame,
                    descriptor.category
                )
            end
        )
        if pandemicInstalled then
            state.pandemicSetupHookedViewer = viewer
        end
    end
    return layoutInstalled or editModeInstalled
        or acquireInstalled or pandemicInstalled
end

local function ClearNativeFrames(state)
    local view = YHUD.View
    if view and view.ClearNativeGroupFrames and state.groupIds then
        for groupId in pairs(state.groupIds) do
            AddStat("layoutWrites")
            view:ClearNativeGroupFrames(groupId, state.category)
        end
    end
    state.groupIds = nil
    state.nativeFrames = nil
    state.nativeByMonitor = nil
end

local function RestoreFrameStyle(frame)
    local view = YHUD.View
    if view and view.HideIconShadow then view:HideIconShadow(frame) end
    local styleState = frame and NativeBridge.frameStates[frame]
    if not styleState then return end
    styleState.restoring = true
    if styleState.keybindOverlay then
        styleState.keybindOverlay:Hide()
        styleState.keybindOverlayShown = false
        local retained = NativeBridge.keybindStates[frame]
        if retained then retained.shown = false end
    end
    RestorePandemicAppearance(frame, styleState)
    RestoreCooldownFlash(styleState)
    local gui = YUI.GUI2
    if gui and gui.RestoreVisual then
        if styleState.iconTarget then
            gui:RestoreVisual(
                styleState.iconTarget,
                styleState.iconState
            )
        end
        if styleState.cooldownTarget then
            gui:RestoreVisual(
                styleState.cooldownTarget,
                styleState.cooldownState
            )
        end
        if styleState.driverStatusTarget then
            gui:RestoreVisual(
                styleState.driverStatusTarget,
                styleState.driverStatusState
            )
        end
    end
    if styleState.scale ~= nil then
        SafeMethod(frame, "SetScale", styleState.scale)
    end
    if styleState.width and styleState.height then
        SafeMethod(
            frame,
            "SetSize",
            styleState.width,
            styleState.height
        )
    end
    RestoreRegionGeometry(frame.Icon, styleState.iconGeometry)
    RestoreRegionGeometry(
        frame.Icon and frame.Icon.Icon,
        styleState.barIconTextureGeometry
    )
    RestoreRegionGeometry(frame.Bar, styleState.barGeometry)
    RestoreRegionGeometry(
        frame.Bar and frame.Bar.BarBG,
        styleState.barBackgroundGeometry
    )
    RestoreRegionGeometry(
        frame.Bar and frame.Bar.Pip,
        styleState.pipGeometry
    )
    RestoreFontString(
        frame.Bar and frame.Bar.Name,
        styleState.nameFont
    )
    RestoreFontString(
        frame.Bar and frame.Bar.Duration,
        styleState.durationFont
    )
    RestoreFontString(
        frame.Icon and frame.Icon.Applications,
        styleState.applicationFont
    )
    local ok, cooldownFontString = SafeMethod(
        frame.Cooldown,
        "GetCountdownFontString"
    )
    RestoreFontString(
        ok and cooldownFontString or nil,
        styleState.cooldownFont
    )
    local count = frame.ChargeCount and frame.ChargeCount.Current
    if not count and frame.Applications then
        count = frame.Applications.Applications
    end
    RestoreFontString(count, styleState.countFont)
    if styleState.cooldownFrameLevelCaptured == true
        and styleState.cooldownFrameLevel ~= nil then
        SetFrameLevelIfChanged(
            frame.Cooldown,
            styleState.cooldownFrameLevel
        )
    end
    RestoreNativeCountCarrierLevel(styleState)
    RestoreNativeChrome(styleState)
    RestoreNativeFrameLayers(styleState)
    RestoreMouseInputState(frame.Cooldown, styleState.nativeCooldownInput)
    RestoreMouseInputState(frame, styleState.nativeTooltipInput)
    if styleState.nativeCategory == "essential"
        or styleState.nativeCategory == "utility" then
        RestoreFramePoints(frame, styleState)
    end
    NativeBridge.frameStates[frame] = nil
end

function NativeBridge:RefreshKeybindTexts()
    local visited, writes = 0, 0
    for frame, styleState in pairs(self.frameStates) do
        local runtime = styleState.nativeStyleRuntime
        local binding = styleState.nativeStyleBinding
            or styleState.nativeBinding
            or styleState.binding
        local descriptor = styleState.nativeStyleCategory
            and DESCRIPTOR_BY_CATEGORY[styleState.nativeStyleCategory]
        if styleState.nativeManaged == true and runtime and descriptor then
            visited = visited + 1
            writes = writes + ApplyNativeKeybindText(
                frame, runtime, descriptor, binding, styleState
            )
        end
    end
    return visited, writes
end

local function RestoreNativeState(state, status)
    ReleaseCooldownCompletionBindings(state)
    ClearNativeFrames(state)
    RestoreMouseInputState(state.itemContainer, state.itemContainerInput)
    RestoreMouseInputState(state.viewer, state.viewerInput)
    state.itemContainer = nil
    state.itemContainerInput = nil
    state.viewerInput = nil
    RestoreAlpha(state, state.viewer)
    if state.itemAlphaFrames then
        for frame in pairs(state.itemAlphaFrames) do
            RestoreFrameStyle(frame)
            RestoreAlpha(state, frame)
        end
    end
    state.groupId = nil
    state.monitorByCooldown = nil
    state.hasAuraSoundRules = nil
    state.fallbackGroupId = nil
    state.pandemicGlowEnabled = nil
    state.dynamicMembers = nil
    for groupId in pairs(state.dirtyStaticGroups or {}) do
        state.dirtyStaticGroups[groupId] = nil
    end
    state.dynamicGroupBuffers = nil
    state.dirtyDynamicGroups = nil
    state.staleDynamicFrames = nil
    state.attached = false
    SetStatus(state, status or "restored")
    return true
end

local function ClearDynamicMap(target)
    for key in pairs(target) do
        target[key] = nil
    end
end

local function ClearDynamicArray(target)
    for index = #target, 1, -1 do
        target[index] = nil
    end
end

local function GetDynamicGroupBuffer(state, groupId)
    if not (state and groupId) then return nil end
    local buffers = state.dynamicGroupBuffers
    local buffer = buffers[groupId]
    if buffer then return buffer end
    buffer = {
        active = 1,
        present = false,
        byMonitorA = {},
        framesA = {},
        byMonitorB = {},
        framesB = {},
    }
    buffers[groupId] = buffer
    return buffer
end

local function GetDynamicGroupWorkBuffer(buffer)
    local nextIndex = buffer.active == 1 and 2 or 1
    local byMonitor = nextIndex == 1
        and buffer.byMonitorA or buffer.byMonitorB
    local frames = nextIndex == 1 and buffer.framesA or buffer.framesB
    ClearDynamicMap(byMonitor)
    ClearDynamicArray(frames)
    return nextIndex, byMonitor, frames
end

local function PrimeDynamicGroupBuffer(state, groupId, runtime, category)
    local buffer = GetDynamicGroupBuffer(state, groupId)
    if not buffer then return end
    local categoryState = runtime and runtime.nativeCategories
        and runtime.nativeCategories[category]
    if not categoryState then
        buffer.present = false
        return
    end
    if buffer.active == 1 then
        buffer.byMonitorA = categoryState.byMonitor
        buffer.framesA = categoryState.frames
    else
        buffer.byMonitorB = categoryState.byMonitor
        buffer.framesB = categoryState.frames
    end
    buffer.present = true
end

local function MarkDynamicGroupDirty(state, groupId)
    if state and groupId then
        state.dirtyDynamicGroups[groupId] = true
    end
end

local function ApplyNativeFrameSet(
    state,
    descriptor,
    monitorByCooldown,
    fallbackGroupId,
    forceLayout,
    forceRestyle
)
    local viewer = state and state.viewer
    local view = YHUD.View
    if not (viewer and monitorByCooldown and view and view.groups
        and view.SetNativeGroupFrames) then
        return false
    end
    local buckets = {}
    local dynamicMembers
    if descriptor.dynamicVisibility == true then
        dynamicMembers = state.dynamicMembers
            or setmetatable({}, { __mode = "k" })
        if descriptor.category == "trackedBuff" then
            for _, member in pairs(dynamicMembers) do
                ClearDynamicIconGeometry(member)
            end
        end
        ClearDynamicMap(dynamicMembers)
        ClearDynamicMap(state.dirtyDynamicGroups)
        for _, binding in pairs(monitorByCooldown) do
            if binding and binding.groupId then
                GetDynamicGroupBuffer(state, binding.groupId)
            end
        end
        if fallbackGroupId then
            GetDynamicGroupBuffer(state, fallbackGroupId)
        end
    else
        ClearDynamicMap(state.dirtyStaticGroups)
    end
    local function GetBucket(targetGroupId)
        local bucket = buckets[targetGroupId]
        if bucket then return bucket end
        local runtime = view.groups and view.groups[targetGroupId]
        if not runtime then return nil end
        bucket = {
            runtime = runtime,
            byMonitor = {},
            frames = {},
            stableMembers = descriptor.dynamicVisibility ~= true and {} or nil,
        }
        buckets[targetGroupId] = bucket
        return bucket
    end
    if descriptor.dynamicVisibility ~= true then
        for _, binding in pairs(monitorByCooldown) do
            local bucket = binding and GetBucket(binding.groupId)
            if bucket and binding.monitorId then
                bucket.stableMembers[binding.monitorId] = true
            end
        end
    end
    local frames = GetOfficialFrames(viewer)
    AddStat("categorySyncScannedFrames", #frames)
    MaxStat("categorySyncMaxFrames", #frames)
    for index = 1, #frames do
        local frame = frames[index]
        if forceRestyle == true then InvalidateFrameStyle(frame) end
        local cooldownID = GetCooldownID(frame)
        local binding = cooldownID and monitorByCooldown[cooldownID]
        local styleState = GetFrameStyleState(frame)
        if descriptor.dynamicVisibility ~= true
            and not styleState.nativeOriginalPoints then
            styleState.nativeOriginalPoints = CaptureFramePoints(frame)
        end
        styleState.nativeBinding = binding
        if descriptor.dynamicVisibility ~= true then
            styleState.staticPreviousBinding = nil
            styleState.staticPreviousGroupId = nil
            styleState.staticPreviousMonitorId = nil
        end
        styleState.nativeCategory = descriptor.category
        styleState.nativeViewer = viewer
        if descriptor.kind == "bar" then
            -- CooldownViewerSettings temporarily shows inactive bar items via
            -- UpdateShownState without SetBarContent or an Aura refresh.
            InstallNativeBarContentHooks(frame)
        end
        if descriptor.dynamicVisibility ~= true then
            InstallStaticFrameHooks(frame)
        end
        local targetGroupId = binding and binding.groupId
            or (descriptor.includeUnmapped == true and fallbackGroupId or nil)
        local bucket = targetGroupId and GetBucket(targetGroupId)
        local managed = bucket ~= nil
            and (binding ~= nil or descriptor.includeUnmapped == true)
        styleState.nativeManaged = managed
        styleState.nativeGroupId = targetGroupId
        styleState.pandemicCategory = descriptor.category
        if descriptor.category == "trackedBuff" then
            if managed then
                InstallDynamicTrackedBuffGeometryHooks(frame)
                styleState.cooldownID = cooldownID
                SetDynamicIconGeometryIdentity(styleState, cooldownID)
            else
                ClearDynamicIconGeometry(styleState)
            end
        end
        if managed then SyncCurrentPandemicAppearance(frame, descriptor) end
        -- Static cooldown viewers keep a stable identity even while Blizzard has
        -- not shown the pooled item yet.  Reserve and style those frames now so
        -- the first cooldown update cannot change YHUD geometry.  Aura viewers
        -- remain visibility-driven because hidden Aura frames are inactive.
        local include = bucket ~= nil
            and (binding ~= nil or descriptor.includeUnmapped == true)
            and (descriptor.dynamicVisibility ~= true or IsShown(frame))
        styleState.nativeIncluded = include
        GetAlphaBaseline(state, frame)
        state.itemAlphaFrames[frame] = true
        if include then
            ApplyNativeStyle(
                frame,
                bucket.runtime,
                descriptor,
                binding,
                state.styleRevision,
                forceLayout == true
            )
            if descriptor.dynamicVisibility ~= true then
                InstallNativeProcHooks(frame)
            end
            InstallSkillAuraDisplayHook(frame, descriptor)
            ApplySkillAuraDisplay(frame, "native-sync")
            if binding then
                bucket.byMonitor[binding.monitorId] = frame
            else
                bucket.frames[#bucket.frames + 1] = frame
            end
            if dynamicMembers then
                styleState.binding = binding
                styleState.groupId = targetGroupId
                styleState.monitorId = binding and binding.monitorId or nil
                styleState.cooldownID = cooldownID
                dynamicMembers[frame] = styleState
            end
            ApplyManagedFrameVisibility(state, frame, styleState, false)
        else
            if descriptor.category == "trackedBuff" then
                ClearDynamicIconGeometry(styleState)
            end
            RestoreNativeFrameLayers(styleState)
            ApplyManagedFrameVisibility(state, frame, styleState, false)
        end
    end
    local previousGroupIds = state.groupIds or {}
    local nextGroupIds = {}
    for targetGroupId, bucket in pairs(buckets) do
        nextGroupIds[targetGroupId] = true
        if descriptor.category == "trackedBuff" then
            NativeBridge:BeginDynamicGeometryLayout()
        end
        local layoutChanged = view:SetNativeGroupFrames(
            targetGroupId,
            bucket.byMonitor,
            bucket.frames,
            descriptor.category,
            forceLayout,
            bucket.stableMembers
        )
        if descriptor.category == "trackedBuff" then
            NativeBridge:FinishDynamicGeometryLayout(
                bucket.byMonitor,
                bucket.frames
            )
        end
        if layoutChanged then
            AddStat("layoutWrites")
        end
    end
    for previousGroupId in pairs(previousGroupIds) do
        if not nextGroupIds[previousGroupId] then
            if view:ClearNativeGroupFrames(
                previousGroupId,
                descriptor.category
            ) then
                AddStat("layoutWrites")
            end
        end
    end
    state.groupIds = nextGroupIds
    state.dynamicMembers = dynamicMembers
    if dynamicMembers then
        for groupId, buffer in pairs(state.dynamicGroupBuffers) do
            local runtime = view.groups[groupId]
            PrimeDynamicGroupBuffer(
                state,
                groupId,
                runtime,
                descriptor.category
            )
            if not nextGroupIds[groupId] then
                buffer.present = false
            end
        end
    end
    SyncNativeAuraSoundStates(state, descriptor)
    state.attached = true
    SetStatus(state, "attached")
    return true
end

ApplyStaticMemberLayout = function(state, descriptor)
    local view = YHUD.View
    if not (state and descriptor and descriptor.dynamicVisibility ~= true
        and view and view.RefreshNativeGroupFrames) then
        return false
    end
    local dirtyGroups = state.dirtyStaticGroups
    local changed = false
    for groupId in pairs(dirtyGroups) do
        dirtyGroups[groupId] = nil
        if view:RefreshNativeGroupFrames(groupId) then
            AddStat("layoutWrites")
            changed = true
        end
    end
    return changed
end

ApplyDynamicMemberLayout = function(state, descriptor, forceLayout)
    local view = YHUD.View
    if not (state and descriptor and descriptor.dynamicVisibility == true
        and state.dynamicMembers and view and view.groups
        and view.SetNativeGroupFrames) then
        return false
    end
    local dirtyGroups = state.dirtyDynamicGroups
    local groupIds = state.groupIds or {}
    state.groupIds = groupIds

    if forceLayout == true then
        for groupId in pairs(groupIds) do
            MarkDynamicGroupDirty(state, groupId)
        end
        local staleFrames = state.staleDynamicFrames
        ClearDynamicArray(staleFrames)
        for frame, member in pairs(state.dynamicMembers) do
            local previousGroupId = member.groupId
            local cooldownID = GetCooldownID(frame)
            local binding = cooldownID and state.monitorByCooldown
                and state.monitorByCooldown[cooldownID]
            local groupId = binding and binding.groupId
                or (descriptor.includeUnmapped == true
                    and state.fallbackGroupId or nil)
            local runtime = groupId and view.groups[groupId]
            if not (runtime and IsShown(frame)) then
                staleFrames[#staleFrames + 1] = frame
                MarkDynamicGroupDirty(state, previousGroupId)
            else
                if previousGroupId ~= groupId then
                    MarkDynamicGroupDirty(state, previousGroupId)
                end
                MarkDynamicGroupDirty(state, groupId)
                member.binding = binding
                member.groupId = groupId
                member.monitorId = binding and binding.monitorId or nil
                member.cooldownID = cooldownID
                member.nativeBinding = binding
                member.nativeCategory = descriptor.category
                member.nativeIncluded = true
                member.nativeGroupId = groupId
                if descriptor.category == "trackedBuff" then
                    InstallDynamicTrackedBuffGeometryHooks(frame)
                    SetDynamicIconGeometryIdentity(member, cooldownID)
                end
                ApplyNativeStyle(
                    frame,
                    runtime,
                    descriptor,
                    binding,
                    state.styleRevision,
                    true
                )
                ApplySkillAuraDisplay(frame, "dynamic-layout")
                ApplyManagedFrameVisibility(
                    state,
                    frame,
                    member,
                    false
                )
            end
        end
        for index = 1, #staleFrames do
            local frame = staleFrames[index]
            local styleState = state.dynamicMembers[frame]
            state.dynamicMembers[frame] = nil
            if styleState then
                styleState.nativeIncluded = false
                styleState.nativeGroupId = nil
                if descriptor.category == "trackedBuff" then
                    ClearDynamicIconGeometry(styleState)
                end
                ApplyManagedFrameVisibility(state, frame, styleState, false)
            else
                SetAlphaIfChanged(state, frame, 0)
            end
            staleFrames[index] = nil
        end
    end

    local changed = false
    for groupId in pairs(dirtyGroups) do
        dirtyGroups[groupId] = nil
        local buffer = GetDynamicGroupBuffer(state, groupId)
        local nextIndex, byMonitor, frames =
            GetDynamicGroupWorkBuffer(buffer)
        local memberCount = 0
        for frame, member in pairs(state.dynamicMembers) do
            AddStat("dynamicMembershipScannedMembers")
            if member.groupId == groupId then
                memberCount = memberCount + 1
                if member.monitorId then
                    byMonitor[member.monitorId] = frame
                else
                    frames[#frames + 1] = frame
                end
            end
        end
        MaxStat("dynamicMembershipMaxMembers", memberCount)
        AddStat("dynamicGroupFlushes")
        local runtime = view.groups[groupId]
        if runtime and memberCount > 0 then
            if descriptor.category == "trackedBuff" then
                NativeBridge:BeginDynamicGeometryLayout()
            end
            local layoutChanged = view:SetNativeGroupFrames(
                groupId,
                byMonitor,
                frames,
                descriptor.category,
                true
            )
            if descriptor.category == "trackedBuff" then
                NativeBridge:FinishDynamicGeometryLayout(byMonitor, frames)
            end
            if layoutChanged then
                AddStat("layoutWrites")
                changed = true
            end
            buffer.active = nextIndex
            buffer.present = true
            groupIds[groupId] = true
        else
            if (buffer.present or groupIds[groupId])
                and view:ClearNativeGroupFrames(
                    groupId,
                    descriptor.category
                ) then
                AddStat("layoutWrites")
                changed = true
            end
            buffer.present = false
            groupIds[groupId] = nil
        end
    end
    SyncNativeAuraSoundStates(state, descriptor)
    return changed
end

local function ApplyNativeDescriptor(
    profile,
    descriptor,
    forceLayout,
    forceRestyle
)
    local state = GetState(descriptor.category)
    local groups = profile and profile.groups
    local items = groups and groups.items
    local groupId = descriptor.defaultGroupId
    local group = groupId and items and items[groupId]
    if not groupId or not group then
        return RestoreNativeState(state, "unclaimed")
    end
    local fallbackGroupId = group.enabled == true
        and group.layout == descriptor.layout
        and groupId
        or nil

    local viewer = _G[descriptor.globalName]
    if not viewer then
        return RestoreNativeState(state, "frame-unavailable")
    end
    if state.viewer and state.viewer ~= viewer then
        RestoreNativeState(state, "frame-replaced")
    end
    state.viewer = viewer
    state.groupId = groupId
    state.fallbackGroupId = fallbackGroupId
    state.itemAlphaFrames = state.itemAlphaFrames
        or setmetatable({}, { __mode = "k" })
    ReleaseCooldownCompletionBindings(state)
    state.monitorByCooldown, state.hasAuraSoundRules = BuildMonitorMap(
        profile,
        descriptor.category,
        descriptor.layout
    )
    InitializeCooldownCompletionBindings(state, descriptor)
    state.pandemicGlowEnabled = not (
        type(profile.style) == "table"
        and profile.style.pandemicGlow == false
    )
    GetAlphaBaseline(state, viewer)
    InstallViewerHook(state, descriptor, viewer)
    state.viewerInput = state.viewerInput or {}
    local viewerInputOK = WriteMouseInputState(
        viewer,
        state.viewerInput,
        false,
        true
    )
    local containerOK, container = SafeMethod(viewer, "GetItemContainerFrame")
    if containerOK and container then
        state.itemContainer = container
        state.itemContainerInput = state.itemContainerInput or {}
        local containerInputOK = WriteMouseInputState(
            container,
            state.itemContainerInput,
            false,
            true
        )
        viewerInputOK = containerInputOK and viewerInputOK
    end
    if not viewerInputOK and IsInCombat() then
        NativeBridge:ScheduleDeferred("categories")
    end

    local view = YHUD.View
    if not (view and view.groups and view.SetNativeGroupFrames) then
        return RestoreNativeState(state, "holder-unavailable")
    end
    local preview = view.preview == true
    if preview then
        SetAlphaIfChanged(state, viewer, 0)
        for frame in pairs(state.itemAlphaFrames) do
            local styleState = NativeBridge.frameStates[frame]
            if styleState then
                styleState.visibilitySuppressed = true
                SetNativeProcGlowShown(styleState, false)
                SetPandemicGlowShown(styleState, false)
                SetNativeTooltipMouseEnabled(frame, styleState, false)
            end
            RestoreAlpha(state, frame)
        end
        ClearNativeFrames(state)
        state.attached = true
        SetStatus(state, "preview")
        return true
    end

    RestoreAlpha(state, viewer, true)
    return ApplyNativeFrameSet(
        state,
        descriptor,
        state.monitorByCooldown,
        fallbackGroupId,
        forceLayout,
        forceRestyle
    )
end

function NativeBridge:OnOfficialAuraFrameRefresh(
    _,
    _,
    _,
    frame,
    category,
    cooldownID,
    skipStableGeometryAudit,
    suppressCategorySync,
    suppressSignalStats
)
    if not self.active or IsNativeEditModeActive() or not frame then return false end
    local descriptor = DESCRIPTOR_BY_CATEGORY[category]
    if not descriptor or descriptor.dynamicVisibility ~= true then return false end
    if suppressSignalStats ~= true then
        AddStat("exactAuraSignals")
        AddStat("dynamicMembershipSignals")
    end
    local state = GetState(category)
    if state.viewer ~= _G[descriptor.globalName] or not state.monitorByCooldown then
        return false
    end
    cooldownID = SafeNumber(cooldownID) or GetCooldownID(frame)
    local binding = cooldownID and state.monitorByCooldown[cooldownID]
    local styleState = GetFrameStyleState(frame)
    local previousCategory = styleState.nativeCategory
    if previousCategory and previousCategory ~= category then
        local previousState = self.states[previousCategory]
        if previousState and previousState.dynamicMembers
            and previousState.dynamicMembers[frame] then
            local previousBinding = previousState.dynamicMembers[frame]
            MarkDynamicGroupDirty(previousState, previousBinding.groupId)
            previousState.dynamicMembers[frame] = nil
            if suppressCategorySync ~= true then
                self:RequestCategorySync(
                    previousCategory,
                    "aura-frame-rebound",
                    DIRTY_MEMBERSHIP
                )
            end
        end
    end
    local targetGroupId = binding and binding.groupId
        or (descriptor.includeUnmapped == true and state.fallbackGroupId or nil)
    local runtime = targetGroupId and YHUD.View and YHUD.View.groups
        and YHUD.View.groups[targetGroupId]
    local managed = runtime ~= nil
        and (binding ~= nil or descriptor.includeUnmapped == true)
    local shouldInclude = managed and IsShown(frame)
    state.dynamicMembers = state.dynamicMembers
        or setmetatable({}, { __mode = "k" })
    local previousMember = state.dynamicMembers[frame]
    local previousGroupId = previousMember and previousMember.groupId
    local memberChanged = (previousMember ~= nil) ~= shouldInclude
        or (previousMember and previousMember.groupId ~= targetGroupId)
        or (previousMember and previousMember.monitorId
            ~= (binding and binding.monitorId or nil))
        or (previousMember and previousMember.cooldownID ~= cooldownID)

    styleState.nativeManaged = managed
    styleState.nativeIncluded = shouldInclude
    styleState.nativeBinding = binding
    styleState.nativeCategory = category
    styleState.nativeGroupId = targetGroupId
    styleState.pandemicCategory = category
    styleState.cooldownID = cooldownID
    if category == "trackedBuff" then
        if shouldInclude then
            InstallDynamicTrackedBuffGeometryHooks(frame)
            SetDynamicIconGeometryIdentity(styleState, cooldownID)
        else
            ClearDynamicIconGeometry(styleState)
        end
    end
    GetAlphaBaseline(state, frame)
    state.itemAlphaFrames[frame] = true
    if shouldInclude then
        ApplyNativeStyle(
            frame,
            runtime,
            descriptor,
            binding,
            state.styleRevision,
            false
        )
        InstallSkillAuraDisplayHook(frame, descriptor)
        ApplySkillAuraDisplay(frame, "aura-frame-refresh")
        styleState.binding = binding
        styleState.groupId = targetGroupId
        styleState.monitorId = binding and binding.monitorId or nil
        state.dynamicMembers[frame] = styleState
        if descriptor.kind == "bar" then
            AddStat("exactNativeBarRewrites")
        end
        ApplyManagedFrameVisibility(state, frame, styleState, true)
    else
        state.dynamicMembers[frame] = nil
        if category == "trackedBuff" then
            ClearDynamicIconGeometry(styleState)
        end
        ApplyManagedFrameVisibility(state, frame, styleState, true)
        SyncNativeProcGlow(frame, styleState, styleState.compiledIcon)
    end
    SyncNativeAuraPlaceholderGlow(binding, shouldInclude)

    if memberChanged then
        MarkDynamicGroupDirty(state, previousGroupId)
        MarkDynamicGroupDirty(state, targetGroupId)
        if suppressSignalStats ~= true then
            AddStat("exactAuraVisibilityChanges")
            AddStat("dynamicMembershipChanges")
        end
        if suppressCategorySync ~= true then
            self:RequestCategorySync(
                category,
                "aura-frame-refresh",
                DIRTY_MEMBERSHIP
            )
        end
    else
        if suppressSignalStats ~= true then
            AddStat("exactAuraStableSignals")
        end
        if category == "trackedBuff" and shouldInclude
            and skipStableGeometryAudit ~= true then
            RecordDynamicGeometryRepair(
                "geometryAuditRepairs",
                AuditDynamicIconGeometry(frame, true, true, true)
            )
        end
    end
    return true, memberChanged
end

local function RecordTrackedBuffViewerScaleMismatch(viewer)
    if not viewer then return false end
    local mismatch = false
    local scaleOK, scale = SafeMethod(viewer, "GetScale")
    scale = scaleOK and SafeNumber(scale) or nil
    if scale and not SameGeometryNumber(scale, 1) then mismatch = true end

    local parentOK, parent = SafeMethod(viewer, "GetParent")
    local effectiveOK, effectiveScale = SafeMethod(viewer, "GetEffectiveScale")
    local parentEffectiveOK, parentEffectiveScale = false, nil
    if parentOK and parent then
        parentEffectiveOK, parentEffectiveScale =
            SafeMethod(parent, "GetEffectiveScale")
    end
    effectiveScale = effectiveOK and SafeNumber(effectiveScale) or nil
    parentEffectiveScale = parentEffectiveOK
        and SafeNumber(parentEffectiveScale) or nil
    if effectiveScale and parentEffectiveScale
        and parentEffectiveScale > 0
        and not SameGeometryNumber(
            effectiveScale / parentEffectiveScale,
            1
        ) then
        mismatch = true
    end
    if mismatch then AddStat("viewerScaleMismatches") end
    return mismatch
end

local function ReanchorCachedTrackedBuffGroup(state, groupId)
    if not (state and groupId) then return false end
    local view = YHUD.View
    local runtime = YHUD.View and YHUD.View.groups
        and YHUD.View.groups[groupId]
    local content = runtime and runtime.nativeCategories
        and runtime.nativeCategories.trackedBuff
    if not (content and view and type(view.SetNativeGroupFrames) == "function") then
        return false
    end
    AddStat("activeStateImmediateGroupRelayouts")
    NativeBridge:BeginDynamicGeometryLayout()
    local ok, changed = pcall(
        view.SetNativeGroupFrames,
        view,
        groupId,
        content.byMonitor,
        content.frames,
        "trackedBuff",
        true
    )
    NativeBridge:FinishDynamicGeometryLayout(
        content.byMonitor,
        content.frames
    )
    if not ok then
        AddStat("geometryRepairFailures")
        return false
    end
    return changed == true
end

local function ClearActiveStateRecollectGeneration(state)
    if state and state.dynamicMembers then
        for _, member in pairs(state.dynamicMembers) do
            member.activeStateRecollectGeneration = nil
        end
    end
    if state then state.activeStateRecollectGeneration = nil end
end

local function RecollectTrackedBuffPool(
    bridge,
    state,
    descriptor,
    generation
)
    local viewer = state.viewer
    local itemFramePool = viewer and viewer.itemFramePool
    if not (itemFramePool
        and type(itemFramePool.EnumerateActive) == "function") then
        return nil, nil
    end
    local adapter = YUI.API and YUI.API.CooldownViewer
    local scanned = 0
    local membershipChanges = 0
    for frame in itemFramePool:EnumerateActive() do
        scanned = scanned + 1
        if adapter and adapter.ObserveAuraFrame then
            adapter:ObserveAuraFrame("trackedBuff", frame, viewer)
        end
        local handled, memberChanged = bridge:OnOfficialAuraFrameRefresh(
            nil,
            nil,
            nil,
            frame,
            descriptor.category,
            GetCooldownID(frame),
            true,
            true,
            true
        )
        if handled then
            local member = state.dynamicMembers
                and state.dynamicMembers[frame]
            if member then
                member.activeStateRecollectGeneration = generation
            end
            if memberChanged then membershipChanges = membershipChanges + 1 end
        end
    end
    return scanned, membershipChanges
end


function NativeBridge:RecollectTrackedBuffMembers()
    AddStat("activeStateRecollects")
    local descriptor = DESCRIPTOR_BY_CATEGORY.trackedBuff
    local state = GetState("trackedBuff")
    local viewer = descriptor and _G[descriptor.globalName]
    if not descriptor or state.viewer ~= viewer
        or not state.monitorByCooldown or not state.dynamicMembers then
        AddStat("activeStateRecollectFailures")
        return false
    end

    local generation = (tonumber(state.activeStateRecollectGeneration) or 0)
        + 1
    state.activeStateRecollectGeneration = generation
    local ok, scanned, membershipChanges = pcall(
        RecollectTrackedBuffPool,
        self,
        state,
        descriptor,
        generation
    )
    if not ok or type(scanned) ~= "number" then
        AddStat("activeStateRecollectFailures")
        return false
    end
    AddStat("activeStateRecollectScannedFrames", scanned)
    MaxStat("activeStateRecollectMaxFrames", scanned)

    local staleFrames = state.staleDynamicFrames
    ClearDynamicArray(staleFrames)
    for frame, member in pairs(state.dynamicMembers) do
        if member.activeStateRecollectGeneration ~= generation then
            staleFrames[#staleFrames + 1] = frame
        end
    end
    for index = 1, #staleFrames do
        local frame = staleFrames[index]
        local member = state.dynamicMembers[frame]
        if member then
            MarkDynamicGroupDirty(state, member.groupId)
            state.dynamicMembers[frame] = nil
            member.nativeIncluded = false
            member.nativeGroupId = nil
            member.activeStateRecollectGeneration = nil
            ClearDynamicIconGeometry(member)
            ApplyManagedFrameVisibility(state, frame, member, false)
            membershipChanges = membershipChanges + 1
        end
        staleFrames[index] = nil
    end
    AddStat("activeStateRecollectMembershipChanges", membershipChanges)

    local changed = ApplyDynamicMemberLayout(state, descriptor, true)
    if changed then AddStat("activeStateSettleRepairs") end
    return true, changed
end

function NativeBridge:CancelActiveStateSettle()
    self.activeStateSettlePending = false
    self.activeStateSettleTicks = 0
    self.activeStateRecollectRetry = 0
    for groupId in pairs(self.activeStateSettleGroups) do
        self.activeStateSettleGroups[groupId] = nil
    end
    ClearActiveStateRecollectGeneration(self.states.trackedBuff)
    if self.activeStateSettleDriver then
        self.activeStateSettleDriver:Hide()
    end
end

function NativeBridge:FlushActiveStateSettle()
    if not self.active or IsNativeEditModeActive()
        or self.layoutPreviewActive then
        self:CancelActiveStateSettle()
        return false
    end
    AddStat("activeStateSettleFlushes")
    self.activeStateSettlePending = false
    self.activeStateSettleTicks = 0
    if self.activeStateSettleDriver then self.activeStateSettleDriver:Hide() end
    local collected, changed = self:RecollectTrackedBuffMembers()
    if not collected then
        if self.activeStateRecollectRetry < 1 then
            self.activeStateRecollectRetry = self.activeStateRecollectRetry + 1
            AddStat("activeStateRecollectRetries")
            self.activeStateSettlePending = true
            self.activeStateSettleTicks = 0
            if self.activeStateSettleDriver then
                self.activeStateSettleDriver:Show()
            end
            return false
        end
        self:CancelActiveStateSettle()
        return false
    end
    self.activeStateRecollectRetry = 0
    for groupId in pairs(self.activeStateSettleGroups) do
        self.activeStateSettleGroups[groupId] = nil
    end
    return changed == true
end

function NativeBridge:AdvanceActiveStateSettle()
    if not self.activeStateSettlePending then
        if self.activeStateSettleDriver then
            self.activeStateSettleDriver:Hide()
        end
        return false
    end
    if not self.active or IsNativeEditModeActive()
        or self.layoutPreviewActive then
        self:CancelActiveStateSettle()
        return false
    end
    self.activeStateSettleTicks = self.activeStateSettleTicks + 1
    if self.activeStateSettleTicks < 2 then return false end
    return self:FlushActiveStateSettle()
end

local function ActiveStateSettleOnUpdate()
    NativeBridge:AdvanceActiveStateSettle()
end

function NativeBridge:EnsureActiveStateSettleDriver()
    if self.activeStateSettleDriver then return true end
    if type(_G.CreateFrame) ~= "function" then return false end
    local activeStateSettleDriver = _G.CreateFrame("Frame")
    if not (activeStateSettleDriver
        and type(activeStateSettleDriver.SetScript) == "function"
        and type(activeStateSettleDriver.Show) == "function"
        and type(activeStateSettleDriver.Hide) == "function") then
        return false
    end
    activeStateSettleDriver:SetScript("OnUpdate", ActiveStateSettleOnUpdate)
    activeStateSettleDriver:Hide()
    self.activeStateSettleDriver = activeStateSettleDriver
    return true
end

local function MarkActiveStateSettleGroup(groups, groupId)
    if not groupId then return end
    groups[groupId] = true
end

function NativeBridge:RequestActiveStateSettle(
    previousGroupId,
    groupId
)
    if not self.active or IsNativeEditModeActive()
        or self.layoutPreviewActive then
        return false
    end
    MarkActiveStateSettleGroup(
        self.activeStateSettleGroups,
        previousGroupId
    )
    MarkActiveStateSettleGroup(
        self.activeStateSettleGroups,
        groupId
    )
    if self.activeStateSettlePending then
        AddStat("activeStateSignalsCoalesced")
        self.activeStateSettleTicks = 0
        return true
    end
    if not self:EnsureActiveStateSettleDriver() then return false end
    self.activeStateSettlePending = true
    self.activeStateSettleTicks = 0
    self.activeStateSettleDriver:Show()
    return true
end

function NativeBridge:OnOfficialAuraActiveStateChanged(
    _,
    _,
    frame,
    category,
    cooldownID,
    viewer
)
    if not self.active or IsNativeEditModeActive() or not frame then
        return false
    end
    if category ~= "trackedBuff" then return false end
    AddStat("activeStateSignals")
    local descriptor = DESCRIPTOR_BY_CATEGORY.trackedBuff
    local state = GetState("trackedBuff")
    cooldownID = SafeNumber(cooldownID)
    local currentCooldownID = GetCooldownID(frame)
    if not descriptor or viewer ~= _G[descriptor.globalName]
        or state.viewer ~= viewer or not cooldownID
        or currentCooldownID ~= cooldownID then
        AddStat("activeStateStaleSignals")
        return false
    end

    RecordTrackedBuffViewerScaleMismatch(viewer)
    local previousMember = state.dynamicMembers
        and state.dynamicMembers[frame]
    local previousGroupId = previousMember and previousMember.groupId
    if not self:OnOfficialAuraFrameRefresh(
        nil,
        nil,
        nil,
        frame,
        category,
        cooldownID,
        true
    ) then
        AddStat("activeStateStaleSignals")
        return false
    end
    local member = state.dynamicMembers and state.dynamicMembers[frame]
    local groupId = member and member.groupId
    if member then
        RecordDynamicGeometryRepair(
            "activeStateImmediateRepairs",
            AuditDynamicIconGeometry(frame, true, true, true)
        )
    end
    if previousGroupId
        and self.activeStateSettleGroups[previousGroupId] == nil then
        ReanchorCachedTrackedBuffGroup(state, previousGroupId)
    end
    if groupId ~= previousGroupId and groupId
        and self.activeStateSettleGroups[groupId] == nil then
        ReanchorCachedTrackedBuffGroup(state, groupId)
    end
    return self:RequestActiveStateSettle(previousGroupId, groupId)
end

function NativeBridge:RegisterAuraRefreshListener()
    if self.auraRefreshListener and self.auraActiveStateListener then
        return true
    end
    local adapter = YUI.API and YUI.API.CooldownViewer
    local event = adapter and adapter.AURA_REFRESH_EVENT
    local activeStateEvent = adapter and adapter.AURA_ACTIVE_STATE_EVENT
    if not (event and activeStateEvent and YUI.Event and YUI.Event.On) then
        return false
    end
    if not self.auraRefreshListener then
        self.auraRefreshListener = YUI.Event:On(
            event,
            "OnOfficialAuraFrameRefresh",
            self,
            { moduleId = "YHUD.NativeBridge" }
        )
    end
    if not self.auraActiveStateListener then
        self.auraActiveStateListener = YUI.Event:On(
            activeStateEvent,
            "OnOfficialAuraActiveStateChanged",
            self,
            { moduleId = "YHUD.NativeBridge" }
        )
    end
    return self.auraRefreshListener ~= nil
        and self.auraActiveStateListener ~= nil
end

function NativeBridge:UnregisterAuraRefreshListener()
    if self.auraRefreshListener and YUI.Event and YUI.Event.Off then
        YUI.Event:Off(self.auraRefreshListener)
    end
    if self.auraActiveStateListener and YUI.Event and YUI.Event.Off then
        YUI.Event:Off(self.auraActiveStateListener)
    end
    self.auraRefreshListener = nil
    self.auraActiveStateListener = nil
end

local function ApplyGroupCategoryVisibility(
    groupId,
    category,
    content,
    verify
)
    local descriptor = DESCRIPTOR_BY_CATEGORY[category]
    if not descriptor or type(content) ~= "table" then
        return false, false
    end
    local state = GetState(category)
    local changed = false
    local failed = false
    local byMonitor = content.byMonitor
    if type(byMonitor) == "table" then
        for _, frame in pairs(byMonitor) do
            local styleState = NativeBridge.frameStates[frame]
            if styleState then
                styleState.nativeGroupId = groupId
                local ok, wrote = ApplyManagedFrameVisibility(
                    state,
                    frame,
                    styleState,
                    verify
                )
                changed = wrote == true or changed
                failed = ok ~= true or failed
            end
        end
    end
    local frames = content.frames
    for index = 1, type(frames) == "table" and #frames or 0 do
        local frame = frames[index]
        local styleState = NativeBridge.frameStates[frame]
        if styleState then
            styleState.nativeGroupId = groupId
            local ok, wrote = ApplyManagedFrameVisibility(
                state,
                frame,
                styleState,
                verify
            )
            changed = wrote == true or changed
            failed = ok ~= true or failed
        end
    end
    return changed, failed
end

function NativeBridge:ApplyGroupVisibility(groupId)
    if not self.active or type(groupId) ~= "string" then return false end
    local view = YHUD.View
    local runtime = view and view.groups and view.groups[groupId]
    if not runtime then return false end
    AddStat("visibilityProjections")
    local changed = false
    local failed = false
    local categories = runtime.nativeCategories
    if type(categories) == "table" then
        for category, content in pairs(categories) do
            local wrote, categoryFailed = ApplyGroupCategoryVisibility(
                groupId,
                category,
                content,
                true
            )
            changed = wrote or changed
            failed = categoryFailed or failed
        end
    end
    if failed and IsInCombat() then self:ScheduleDeferred("sync") end
    return changed
end

function NativeBridge:RestorePresentationAlpha()
    if not self.active then return false end
    local changed = false
    local failed = false
    for index = 1, #DESCRIPTORS do
        local state = GetState(DESCRIPTORS[index].category)
        if state.viewer then
            local ok, wrote = RestoreAlpha(state, state.viewer, true)
            RecordVisibilityAlphaResult(ok, wrote)
            changed = wrote == true or changed
            failed = ok ~= true or failed
        end
        for frame in pairs(state.itemAlphaFrames or {}) do
            local styleState = self.frameStates[frame]
            local ok, wrote
            if styleState then
                ok, wrote = ApplyManagedFrameVisibility(
                    state,
                    frame,
                    styleState,
                    true
                )
            else
                ok, wrote = SetAlphaIfChanged(state, frame, 0, true)
                RecordVisibilityAlphaResult(ok, wrote)
            end
            changed = wrote == true or changed
            failed = ok ~= true or failed
        end
    end
    if failed and IsInCombat() then self:ScheduleDeferred("sync") end
    return changed
end

function NativeBridge:SyncCategory(category, reason, profile)
    local descriptor = DESCRIPTOR_BY_CATEGORY[category]
    if not descriptor or not self.active or IsNativeEditModeActive()
        or self.layoutPreviewActive then
        return false
    end
    if category == "trackedBuff" then self:CancelActiveStateSettle() end
    local state = GetState(category)
    if state.syncing then
        state.resyncRequested = true
        return true
    end

    AddStat("categorySyncs")
    local startedAt = ProfileNowMS()
    state.syncing = true
    state.resyncRequested = false
    profile = profile or GetActiveConfigProfile()
    if profile then
        state.styleRevision = (state.styleRevision or 0) + 1
    end
    local forceLayout = reason == "viewer-refresh"
        or reason == "bar-content"
        or reason == "edit-mode-exit-finalize"
    local forceRestyle = reason == "viewer-refresh"
        or reason == "bar-content"
        or reason == "edit-mode-exit-finalize"
    local ok = profile
        and ApplyNativeDescriptor(
            profile,
            descriptor,
            forceLayout,
            forceRestyle
        )
        or false
    if state.resyncRequested then
        state.resyncRequested = false
        profile = GetActiveConfigProfile() or profile
        if profile then
            state.styleRevision = (state.styleRevision or 0) + 1
        end
        ok = profile and ApplyNativeDescriptor(profile, descriptor, false) or ok
    end
    state.syncing = false
    state.lastReason = reason
    local finishedAt = ProfileNowMS()
    if startedAt and finishedAt then
        AddStat("categorySyncElapsedMS", math.max(0, finishedAt - startedAt))
    end
    return ok == true
end

function NativeBridge:RestoreAll(status)
    self:CancelPendingCategorySync(true)
    local restored = true
    for index = 1, #DESCRIPTORS do
        local state = GetState(DESCRIPTORS[index].category)
        if not RestoreNativeState(state, status) then
            restored = false
        end
    end
    local frame = next(self.frameStates)
    while frame do
        RestoreFrameStyle(frame)
        frame = next(self.frameStates)
    end
    return restored
end

function NativeBridge:EnterLayoutPreview()
    if not self.active or self.layoutPreviewActive then return false end
    self.layoutPreviewActive = true
    self:CancelActiveStateSettle()
    self:CancelPendingCategorySync(false)

    local view = YHUD.View
    if view and view.SuspendNativePresentation then
        view:SuspendNativePresentation()
    end

    for index = 1, #DESCRIPTORS do
        local state = GetState(DESCRIPTORS[index].category)
        local alphaSnapshot = {}
        local function CaptureAlpha(frame)
            if not frame or alphaSnapshot[frame] ~= nil then return end
            local ok, alpha = SafeMethod(frame, "GetAlpha")
            alphaSnapshot[frame] = ok and SafeNumber(alpha) or 1
        end
        CaptureAlpha(state.viewer)
        for frame in pairs(state.itemAlphaFrames or {}) do
            CaptureAlpha(frame)
            local styleState = NativeBridge.frameStates[frame]
            if styleState then
                styleState.visibilitySuppressed = true
                SetNativeProcGlowShown(styleState, false)
                SetPandemicGlowShown(styleState, false)
                SetNativeTooltipMouseEnabled(frame, styleState, false)
            end
            RestoreAlpha(state, frame)
        end
        state.layoutPreviewAlpha = alphaSnapshot
        SetAlphaIfChanged(state, state.viewer, 0)
        SetStatus(state, "layout-preview")
    end
    return true
end

function NativeBridge:CompleteLayoutPreviewExit()
    local view = YHUD.View
    if view and view.ResumeNativePresentation then
        view:ResumeNativePresentation()
    end

    for index = 1, #DESCRIPTORS do
        local state = GetState(DESCRIPTORS[index].category)
        local snapshot = state.layoutPreviewAlpha
        state.layoutPreviewAlpha = nil
        if snapshot then
            local alpha = state.viewer and snapshot[state.viewer]
            if alpha ~= nil then SetAlphaIfChanged(state, state.viewer, alpha) end
            -- Current membership/visibility owns item alpha, not the old snapshot.
            for frame in pairs(state.itemAlphaFrames or {}) do
                local styleState = NativeBridge.frameStates[frame]
                if styleState then
                    ApplyManagedFrameVisibility(state, frame, styleState, true)
                    if self.active and styleState.nativeIncluded == true then
                        RefreshNativeCooldownGlowState(frame, styleState)
                        SyncNativeProcGlow(frame, styleState, styleState.compiledIcon)
                        SyncCurrentPandemicAppearance(frame, DESCRIPTORS[index])
                    end
                end
            end
            if state.attached then SetStatus(state, "attached") end
        end
    end

    if not self.active then return true end
    if IsInCombat() then
        self.layoutPreviewExitPending = true
        self:ScheduleDeferred("categories")
        return true
    end
    self.layoutPreviewExitPending = nil
    local profile = GetActiveConfigProfile()
    for index = 1, #DESCRIPTORS do
        local category = DESCRIPTORS[index].category
        if self.dirtyCategories[category] then
            local reason = self.dirtyCategoryReasons[category]
                or "layout-preview-exit"
            self.dirtyCategories[category] = nil
            self.dirtyCategoryReasons[category] = nil
            self.dirtyCategoryKinds[category] = nil
            self.dirtyCategoryCombatSafe[category] = nil
            self:SyncCategory(category, reason, profile)
        end
    end
    return true
end

function NativeBridge:ExitLayoutPreview()
    if not self.layoutPreviewActive then return false end
    self.layoutPreviewActive = false
    return self:CompleteLayoutPreviewExit()
end

function NativeBridge:ScheduleDeferred(action)
    local priorities = {
        categories = 1,
        sync = 2,
        restore = 3,
    }
    local current = self.pendingAction
    if not current
        or (priorities[action] or 0) > (priorities[current] or 0) then
        self.pendingAction = action
    end
    if self.combatListener or not (YUI.Event and YUI.Event.Once) then
        return self.combatListener ~= nil
    end
    self.combatListener = YUI.Event:Once(
        "PLAYER_REGEN_ENABLED",
        "OnCombatEnded",
        self,
        {
            priority = 2500,
            traceName = "YHUD.NativeBridge",
        }
    )
    return self.combatListener ~= nil
end

function NativeBridge:CancelPendingCategorySync(clearDirty)
    if self.categorySyncTimer and self.categorySyncTimer.Cancel then
        self.categorySyncTimer:Cancel()
    end
    self.categorySyncTimer = nil
    if clearDirty ~= false then
        for category in pairs(self.dirtyCategories) do
            self.dirtyCategories[category] = nil
            self.dirtyCategoryReasons[category] = nil
            self.dirtyCategoryKinds[category] = nil
            self.dirtyCategoryCombatSafe[category] = nil
        end
    end
end

function NativeBridge:FlushPendingCategorySync()
    self.categorySyncTimer = nil
    if self.layoutPreviewActive then return false end
    if not self.active or IsNativeEditModeActive() then
        self:CancelPendingCategorySync(true)
        return false
    end
    local contextPending = YHUD.pendingContextTimer
        or YHUD.pendingContextReason
        or YHUD.pendingContextCombat
    AddStat("categorySyncFlushes")
    local profile
    local profileResolved = false
    local applied = false
    local inCombat = IsInCombat()
    local combatDeferred = false
    local contextDeferred = false
    for index = 1, #DESCRIPTORS do
        local category = DESCRIPTORS[index].category
        if self.dirtyCategories[category] then
            local dirtyKind = self.dirtyCategoryKinds[category]
                or DIRTY_STRUCTURE
            if contextPending and dirtyKind >= DIRTY_STRUCTURE then
                contextDeferred = true
            elseif inCombat and not self.dirtyCategoryCombatSafe[category] then
                combatDeferred = true
            else
                local reason = self.dirtyCategoryReasons[category]
                    or "category-coalesced"
                self.dirtyCategories[category] = nil
                self.dirtyCategoryReasons[category] = nil
                self.dirtyCategoryKinds[category] = nil
                self.dirtyCategoryCombatSafe[category] = nil
                local descriptor = DESCRIPTOR_BY_CATEGORY[category]
                if descriptor and dirtyKind <= DIRTY_LAYOUT then
                    if contextPending then AddStat("contextSafeFlushes") end
                    if descriptor.dynamicVisibility == true then
                        if dirtyKind == DIRTY_LAYOUT then
                            AddStat("dynamicLayoutFlushes")
                        else
                            AddStat("dynamicMembershipFlushes")
                        end
                        applied = ApplyDynamicMemberLayout(
                            GetState(category),
                            descriptor,
                            dirtyKind == DIRTY_LAYOUT
                        ) or applied
                    else
                        applied = ApplyStaticMemberLayout(
                            GetState(category),
                            descriptor
                        ) or applied
                    end
                else
                    AddStat("categoryStructureFlushes")
                    if not profileResolved then
                        profile = GetActiveConfigProfile()
                        profileResolved = true
                        AddStat("categoryFlushProfileReads")
                    end
                    if profile then
                        applied = self:SyncCategory(
                            category,
                            reason,
                            profile
                        ) or applied
                    end
                end
            end
        end
    end
    if combatDeferred then self:ScheduleDeferred("categories") end
    return applied or contextDeferred
end

local function PendingCategorySyncCallback()
    local watchdog = YUI.CPUWatchdog
    if watchdog and watchdog.sceneCapture then
        return watchdog:MeasureSceneTask("yhud.category-sync-timer", NativeBridge.FlushPendingCategorySync, NativeBridge)
    end
    return NativeBridge:FlushPendingCategorySync()
end

function NativeBridge:RequestCategorySync(category, reason, dirtyKind)
    if not self.active or IsNativeEditModeActive()
        or not DESCRIPTOR_BY_CATEGORY[category] then
        return false
    end
    AddStat("categorySyncRequests")
    local coalesced = false
    if self.dirtyCategories[category] then
        AddStat("categorySyncCoalesced")
        coalesced = true
    end
    dirtyKind = tonumber(dirtyKind)
        or (reason == "aura-frame-refresh" and DIRTY_MEMBERSHIP)
        or (reason == "viewer-layout" and DIRTY_LAYOUT)
        or DIRTY_STRUCTURE
    dirtyKind = math.max(
        DIRTY_MEMBERSHIP,
        math.min(DIRTY_STRUCTURE, dirtyKind)
    )
    if self.layoutPreviewActive then
        self.dirtyCategories[category] = true
        local previousKind = self.dirtyCategoryKinds[category]
        if not previousKind or dirtyKind > previousKind then
            self.dirtyCategoryKinds[category] = dirtyKind
            self.dirtyCategoryReasons[category] = reason
                or "layout-preview"
        elseif not self.dirtyCategoryReasons[category] then
            self.dirtyCategoryReasons[category] = reason
                or "layout-preview"
        end
        return true
    end
    local previousKind = self.dirtyCategoryKinds[category]
    if not previousKind or dirtyKind > previousKind then
        self.dirtyCategoryKinds[category] = dirtyKind
        self.dirtyCategoryReasons[category] = reason or "category-request"
    elseif not self.dirtyCategoryReasons[category] then
        self.dirtyCategoryReasons[category] = reason or "category-request"
    end
    self.dirtyCategories[category] = true
    local pendingKind = self.dirtyCategoryKinds[category] or dirtyKind
    local combatSafe = pendingKind <= DIRTY_LAYOUT
    self.dirtyCategoryCombatSafe[category] = combatSafe == true
    if IsInCombat() and not combatSafe
        and self.dirtyCategoryCombatSafe[category] ~= true then
        self:ScheduleDeferred("categories")
        return true
    end
    local contextPending = YHUD.pendingContextTimer
        or YHUD.pendingContextReason
        or YHUD.pendingContextCombat
    if contextPending and not combatSafe then
        if not coalesced then AddStat("categorySyncCoalesced") end
        return true
    end
    if self.categorySyncTimer then
        if not coalesced then AddStat("categorySyncCoalesced") end
        return true
    end
    if C_Timer and C_Timer.NewTimer then
        local watchdog = YUI.CPUWatchdog
        if watchdog and watchdog.sceneCapture then watchdog:SceneTaskScheduled("yhud.category-sync-timer") end
        self.categorySyncTimer = C_Timer.NewTimer(
            0,
            PendingCategorySyncCallback
        )
        return true
    end
    return self:FlushPendingCategorySync()
end

function NativeBridge:OnCombatEnded()
    self.combatListener = nil
    local view = YHUD.View
    if self.active and view and view.FlushPendingIconShadows then
        view:FlushPendingIconShadows()
    end
    local action = self.pendingAction
    self.pendingAction = nil
    if self.layoutPreviewExitPending then
        self.layoutPreviewExitPending = nil
        self:CompleteLayoutPreviewExit()
        if action == "categories" then return true end
    end
    if action == "restore" or not self.active then
        return self:RestoreAll("combat-restored")
    end
    if action == "categories" then
        return self:FlushPendingCategorySync()
    end
    if action == "sync" then
        return self:Sync(nil, "combat-ended")
    end
    return false
end

function NativeBridge:Sync(profile, reason)
    if not self.active then return false end
    self:CancelActiveStateSettle()
    if self.layoutPreviewActive then
        for index = 1, #DESCRIPTORS do
            local category = DESCRIPTORS[index].category
            self.dirtyCategories[category] = true
            self.dirtyCategoryKinds[category] = DIRTY_STRUCTURE
            self.dirtyCategoryReasons[category] = reason
                or "layout-preview-sync"
        end
        return true
    end
    if IsNativeEditModeActive() then
        return self:RestoreAll("edit-mode")
    end
    if IsInCombat() then
        self:ScheduleDeferred("sync")
        return true
    end

    self:CancelPendingCategorySync(true)

    if self.combatListener and YUI.Event and YUI.Event.Off then
        YUI.Event:Off(self.combatListener)
        self.combatListener = nil
    end
    self.pendingAction = nil
    profile = profile
        or GetActiveConfigProfile()
    if not profile then
        return self:RestoreAll("profile-unavailable")
    end

    EnsureOfficialAddon()
    for index = 1, #DESCRIPTORS do
        self:SyncCategory(
            DESCRIPTORS[index].category,
            reason or "sync",
            profile
        )
    end
    self.refreshBaseline = false
    self.lastReason = reason
    return true
end

function NativeBridge.OnEditModeEnter(owner)
    owner.editModeActive = true
    owner.editModeExitObserved = false
    owner.refreshBaseline = true
    owner:CancelActiveStateSettle()
    owner:CancelPendingCategorySync(true)
    if IsInCombat() then
        owner:ScheduleDeferred("restore")
        return
    end
    owner:RestoreAll("edit-mode-enter")
end

function NativeBridge.OnEditModeExit(owner)
    owner.editModeActive = false
    owner.editModeExitObserved = true
    owner.refreshBaseline = true
    local result = false
    if owner.active then
        result = owner:Sync(nil, "edit-mode-exit")
    end
    if owner.active then
        for index = 1, #DESCRIPTORS do
            owner:RequestCategorySync(
                DESCRIPTORS[index].category,
                "edit-mode-exit-finalize",
                DIRTY_STRUCTURE
            )
        end
    end
    return result
end

function NativeBridge:RegisterEditModeCallbacks()
    local registry = _G.EventRegistry
    if self.editCallbacksRegistered
        or not (registry and registry.RegisterCallback) then
        return false
    end
    registry:RegisterCallback(
        "EditMode.Enter",
        self.OnEditModeEnter,
        self
    )
    registry:RegisterCallback(
        "EditMode.Exit",
        self.OnEditModeExit,
        self
    )
    self.editCallbacksRegistered = true
    return true
end

function NativeBridge:UnregisterEditModeCallbacks()
    local registry = _G.EventRegistry
    if self.editCallbacksRegistered
        and registry
        and registry.UnregisterCallback then
        registry:UnregisterCallback("EditMode.Enter", self)
        registry:UnregisterCallback("EditMode.Exit", self)
    end
    self.editCallbacksRegistered = false
end

NativeBridge.officialRuntimeOwner = NativeBridge.officialRuntimeOwner or {}

function NativeBridge.officialRuntimeOwner:OnSignal(eventName)
    if not NativeBridge.active or NativeBridge.officialRuntimeReady then
        return false
    end
    return NativeBridge:RequestOfficialRuntimeSync(
        eventName or "official-runtime-signal",
        NativeBridge.officialRuntimeTimer == nil
    )
end

function NativeBridge.officialRuntimeOwner:OnDataChanged()
    return self:OnSignal("CooldownViewerSettings.OnDataChanged")
end

function NativeBridge.OfficialRuntimeTimerCallback()
    local generation = NativeBridge.officialRuntimeTimerGeneration
    NativeBridge.officialRuntimeTimer = nil
    NativeBridge.officialRuntimeTimerGeneration = nil
    if generation ~= NativeBridge.officialRuntimeGeneration then return false end
    local watchdog = YUI.CPUWatchdog
    if watchdog and watchdog.sceneCapture then
        return watchdog:MeasureSceneTask("yhud.official-runtime-timer", NativeBridge.RunOfficialRuntimeSync, NativeBridge)
    end
    return NativeBridge:RunOfficialRuntimeSync()
end

function NativeBridge:CancelOfficialRuntimeSync()
    if self.officialRuntimeTimer and self.officialRuntimeTimer.Cancel then
        self.officialRuntimeTimer:Cancel()
    end
    self.officialRuntimeTimer = nil
    self.officialRuntimeTimerGeneration = nil
    self.officialRuntimeRetryIndex = nil
end

function NativeBridge:RegisterOfficialRuntimeSignals()
    local owner = self.officialRuntimeOwner
    if owner.registered ~= true and YUI.Event and YUI.Event.On then
        YUI.Event:On(
            "YUI_WORLD_READY",
            "OnSignal",
            owner,
            {
                moduleId = "YHUD.NativeBridge",
                traceName = "YHUD.NativeBridge.Readiness",
            }
        )
        YUI.Event:On(
            "COOLDOWN_VIEWER_DATA_LOADED",
            "OnSignal",
            owner,
            {
                moduleId = "YHUD.NativeBridge",
                traceName = "YHUD.NativeBridge.Readiness",
            }
        )
        owner.registered = true
    end
    if owner.dataCallbackRegistered ~= true
        and EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback(
            "CooldownViewerSettings.OnDataChanged",
            owner.OnDataChanged,
            owner
        )
        owner.dataCallbackRegistered = true
    end
    return owner.registered == true
        or owner.dataCallbackRegistered == true
end

function NativeBridge:UnregisterOfficialRuntimeSignals()
    local owner = self.officialRuntimeOwner
    if owner.registered == true and YUI.Event and YUI.Event.OffOwner then
        YUI.Event:OffOwner(owner)
    end
    owner.registered = false
    if owner.dataCallbackRegistered == true
        and EventRegistry and EventRegistry.UnregisterCallback then
        EventRegistry:UnregisterCallback(
            "CooldownViewerSettings.OnDataChanged",
            owner
        )
    end
    owner.dataCallbackRegistered = false
end

function NativeBridge:RequestOfficialRuntimeSync(reason, reset)
    if not self.active or self.officialRuntimeReady then return false end
    if self.officialRuntimeTimer then return true end
    if reset == true or type(self.officialRuntimeRetryIndex) ~= "number" then
        self.officialRuntimeRetryIndex = 1
    end
    local retryIndex = self.officialRuntimeRetryIndex
    local delay = self.officialRuntimeRetryDelays[retryIndex]
    if delay == nil then return false end
    self.officialRuntimeRetryIndex = retryIndex + 1
    self.officialRuntimeReason = reason or self.officialRuntimeReason
        or "official-runtime"
    if C_Timer and C_Timer.NewTimer then
        self.officialRuntimeTimerGeneration = self.officialRuntimeGeneration
        local watchdog = YUI.CPUWatchdog
        if watchdog and watchdog.sceneCapture then watchdog:SceneTaskScheduled("yhud.official-runtime-timer") end
        self.officialRuntimeTimer = C_Timer.NewTimer(
            delay,
            self.OfficialRuntimeTimerCallback
        )
        return true
    end
    if delay == 0 then return self:RunOfficialRuntimeSync() end
    return false
end

function NativeBridge:RunOfficialRuntimeSync()
    if not self.active then return false end
    local ready, code = self:IsOfficialRuntimeReady()
    if not ready then
        self.officialRuntimeReason = code
        if self:RequestOfficialRuntimeSync(code, false) then return true end
        return false, code
    end
    self.officialRuntimeReady = true
    self.officialRuntimeReason = nil
    self.officialRuntimeRetryIndex = nil
    return self:Sync(self.officialRuntimeProfile, "official-runtime-ready")
end

function NativeBridge:Enable(profile)
    self.officialRuntimeGeneration = self.officialRuntimeGeneration + 1
    self:CancelOfficialRuntimeSync()
    self.officialRuntimeReady = false
    self.officialRuntimeReason = nil
    self.officialRuntimeProfile = profile
    self.active = true
    self:RegisterOfficialRuntimeSignals()
    self.editModeActive = IsEditModeActive()
    self.editModeExitObserved = false
    self.refreshBaseline = self.editModeActive
    self:EnsureActiveStateSettleDriver()
    self:RegisterAuraRefreshListener()
    local officialReady = self:PrepareOfficialRuntime()
    self:RegisterEditModeCallbacks()
    local synced = self:Sync(profile, "enable")
    local lifecycle = YUI.Lifecycle
    local worldAlreadyReady = lifecycle
        and type(lifecycle.IsReady) == "function"
        and lifecycle:IsReady("YUI_WORLD_READY") == true
    local runtimeReady = officialReady and self:IsOfficialRuntimeReady()
    if runtimeReady then
        self.officialRuntimeReady = true
    else
        self:RequestOfficialRuntimeSync(
            worldAlreadyReady and "world-already-ready" or "enable",
            true
        )
    end
    return synced
end

function NativeBridge:PrepareOfficialRuntime()
    local loaded = EnsureOfficialAddon()
    local adapter = YUI.API and YUI.API.CooldownViewer
    if adapter and adapter.SetAuraRefreshNotificationsEnabled then
        adapter:SetAuraRefreshNotificationsEnabled(true)
    end
    return loaded == true
end

function NativeBridge:Disable()
    self.officialRuntimeGeneration = self.officialRuntimeGeneration + 1
    self:CancelOfficialRuntimeSync()
    self:UnregisterOfficialRuntimeSignals()
    self.officialRuntimeReady = false
    self.officialRuntimeReason = nil
    self.officialRuntimeProfile = nil
    self.active = false
    self.editModeActive = false
    self.editModeExitObserved = false
    self:CancelActiveStateSettle()
    if self.layoutPreviewActive or self.layoutPreviewExitPending then
        self.layoutPreviewActive = false
        self.layoutPreviewExitPending = nil
        self:CompleteLayoutPreviewExit()
    end
    local adapter = YUI.API and YUI.API.CooldownViewer
    if adapter and adapter.SetAuraRefreshNotificationsEnabled then
        adapter:SetAuraRefreshNotificationsEnabled(false)
    end
    self:UnregisterAuraRefreshListener()
    self:CancelPendingCategorySync(true)
    self:UnregisterEditModeCallbacks()
    for index = 1, #DESCRIPTORS do
        ReleaseCooldownCompletionBindings(
            GetState(DESCRIPTORS[index].category)
        )
    end
    if IsInCombat() then
        self:ScheduleDeferred("restore")
        return true
    end
    if self.combatListener and YUI.Event and YUI.Event.Off then
        YUI.Event:Off(self.combatListener)
        self.combatListener = nil
    end
    self.pendingAction = nil
    return self:RestoreAll("disabled")
end

function NativeBridge:GetState(category)
    local state = GetState(category)
    return {
        category = category,
        attached = state.attached == true,
        groupId = state.groupId,
        status = state.status,
        pending = self.pendingAction,
    }
end

function NativeBridge:GetStats(target)
    target = target or {}
    for index = 1, #STAT_FIELDS do
        local field = STAT_FIELDS[index]
        target[field] = self.stats[field] or 0
    end
    return target
end

function NativeBridge:ResetStats()
    for index = 1, #STAT_FIELDS do
        self.stats[STAT_FIELDS[index]] = 0
    end
end

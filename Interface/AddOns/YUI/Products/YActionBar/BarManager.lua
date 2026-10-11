local YUI = _G.YUI
if not YUI or not YUI.YActionBar then return end

local YAB = YUI.YActionBar
local BarManager = {}
YAB.BarManager = BarManager
local Security = YUI.API and YUI.API.Security
local HotDiagnostics = YAB.HotDiagnostics

BarManager.bars = BarManager.bars or {}
BarManager.buttonsByKey = BarManager.buttonsByKey or {}
BarManager.nativeState = BarManager.nativeState or setmetatable({}, { __mode = "k" })
BarManager.nativeHooked = BarManager.nativeHooked or setmetatable({}, { __mode = "k" })
BarManager.externalState = BarManager.externalState or setmetatable({}, { __mode = "k" })
BarManager.externalFrameOwners = BarManager.externalFrameOwners or setmetatable({}, { __mode = "k" })
BarManager.externalButtonOwners = BarManager.externalButtonOwners or setmetatable({}, { __mode = "k" })
BarManager.externalSpecialHooks = BarManager.externalSpecialHooks or {}
BarManager.eventCount = BarManager.eventCount or 0
BarManager.hotEventBackend = "native-frame"
BarManager.nativeSuppressionMode = BarManager.nativeSuppressionMode or "none"
BarManager.nativeSuppressionDegraded = BarManager.nativeSuppressionDegraded or false
BarManager.nativeDisposedButtons = BarManager.nativeDisposedButtons or setmetatable({}, { __mode = "k" })
BarManager.nativeDisposalFailures = BarManager.nativeDisposalFailures or 0
BarManager.specialNativeSuppressionMode = BarManager.specialNativeSuppressionMode or "unknown"
BarManager.specialNativeSuppressionChanged = BarManager.specialNativeSuppressionChanged or false
BarManager.specialNativeSuppressionFailures = BarManager.specialNativeSuppressionFailures or 0
BarManager.specialNativeSuppressionReason = BarManager.specialNativeSuppressionReason or nil
BarManager.reloadRequired = BarManager.reloadRequired or false
BarManager.visualState = BarManager.visualState or {}
BarManager.rangeSlots = BarManager.rangeSlots or {}
BarManager.nextRangeSlots = BarManager.nextRangeSlots or {}
BarManager.rangeCheckEnabled = BarManager.rangeCheckEnabled or {}
BarManager.rangeOut = BarManager.rangeOut or {}
BarManager.auraLookup = BarManager.auraLookup or {}
BarManager.dirtySlots = BarManager.dirtySlots or {}
BarManager.dirtySpecialBars = BarManager.dirtySpecialBars or {}
BarManager.dirtySettingBars = BarManager.dirtySettingBars or {}
BarManager.processingDirtySlots = BarManager.processingDirtySlots or {}
BarManager.processingDirtySpecialBars = BarManager.processingDirtySpecialBars or {}
BarManager.processingDirtySettingBars = BarManager.processingDirtySettingBars or {}
BarManager.pendingStructuralBars = BarManager.pendingStructuralBars or {}
BarManager.pendingExternalSpecialBars = BarManager.pendingExternalSpecialBars or {}
BarManager.specialMoverProxies = BarManager.specialMoverProxies or {}
BarManager.specialGroupAnchorVisited = BarManager.specialGroupAnchorVisited or {}
BarManager.specialGroupLayoutScratch = BarManager.specialGroupLayoutScratch or {
    kinds = {},
    movers = {},
    widths = {},
    heights = {},
}
BarManager.specialGroupingMode = BarManager.specialGroupingMode or "independent"
BarManager.specialGroupConfig = BarManager.specialGroupConfig or nil
BarManager.specialGroupActiveMembers = BarManager.specialGroupActiveMembers or 0
BarManager.specialGroupLayouts = BarManager.specialGroupLayouts or 0
BarManager.specialGroupAnchorFallbacks = BarManager.specialGroupAnchorFallbacks or 0
BarManager.specialGroupingRefreshPending = BarManager.specialGroupingRefreshPending or false
BarManager.specialGroupingPlacementPending = BarManager.specialGroupingPlacementPending or false
BarManager.dirtyReasons = BarManager.dirtyReasons or {}
BarManager.slotButtons = BarManager.slotButtons or {}
BarManager.buttonSlots = BarManager.buttonSlots or setmetatable({}, { __mode = "k" })
BarManager.buttonStates = BarManager.buttonStates or setmetatable({}, { __mode = "k" })
BarManager.assistedCombatSlotCount = BarManager.assistedCombatSlotCount or 0
BarManager.assistedCombatTickerStarts = BarManager.assistedCombatTickerStarts or 0
BarManager.assistedCombatTickerStops = BarManager.assistedCombatTickerStops or 0
BarManager.assistedCombatTickerTicks = BarManager.assistedCombatTickerTicks or 0
BarManager.assistedCombatNextSpellPolls = BarManager.assistedCombatNextSpellPolls or 0
BarManager.assistedCombatNextSpellChanges = BarManager.assistedCombatNextSpellChanges or 0
BarManager.assistedCombatNextSpellFailures = BarManager.assistedCombatNextSpellFailures or 0
BarManager.assistedCombatForceUpdates = BarManager.assistedCombatForceUpdates or 0
BarManager.assistedCombatRefreshQueues = BarManager.assistedCombatRefreshQueues or 0
BarManager.assistedCombatVisibleSlotChecks = BarManager.assistedCombatVisibleSlotChecks or 0
BarManager.slotIdentityScratch = BarManager.slotIdentityScratch or {}
BarManager.slotIdentityShadowScratch = BarManager.slotIdentityShadowScratch or {}
BarManager.buttonConfigSnapshots = BarManager.buttonConfigSnapshots or setmetatable({}, { __mode = "k" })
BarManager.emptyButtonShown = BarManager.emptyButtonShown or setmetatable({}, { __mode = "k" })
BarManager.pendingEmptyButtonShown = BarManager.pendingEmptyButtonShown or setmetatable({}, { __mode = "k" })
BarManager.externalTextRegionShown = BarManager.externalTextRegionShown or setmetatable({}, { __mode = "k" })
BarManager.externalTextRegionAlpha = BarManager.externalTextRegionAlpha or setmetatable({}, { __mode = "k" })
BarManager.externalHotkeyText = BarManager.externalHotkeyText or setmetatable({}, { __mode = "k" })
BarManager.externalHotkeyDisplay = BarManager.externalHotkeyDisplay or setmetatable({}, { __mode = "k" })
BarManager.externalTextHooked = BarManager.externalTextHooked or setmetatable({}, { __mode = "k" })
BarManager.externalButtonIndices = BarManager.externalButtonIndices or setmetatable({}, { __mode = "k" })
BarManager.mouseoverRecords = BarManager.mouseoverRecords or setmetatable({}, { __mode = "k" })
BarManager.mouseoverHooked = BarManager.mouseoverHooked or setmetatable({}, { __mode = "k" })
BarManager.mouseoverFadeStates = BarManager.mouseoverFadeStates or setmetatable({}, { __mode = "k" })
BarManager.mouseoverFadeGroups = BarManager.mouseoverFadeGroups or setmetatable({}, { __mode = "k" })
BarManager.mouseoverFadeActiveCount = BarManager.mouseoverFadeActiveCount or 0
BarManager.mouseoverFadeInDuration = 0.15
BarManager.mouseoverFadeOutDuration = 0.20
BarManager.directActionButtons = BarManager.directActionButtons or {}
BarManager.directActionHolders = BarManager.directActionHolders or {}
BarManager.directActionListDirty = BarManager.directActionListDirty ~= false
BarManager.directActionButtonCount = BarManager.directActionButtonCount or 0
BarManager.directActionListRebuilds = BarManager.directActionListRebuilds or 0
BarManager.directActionListFallbacks = BarManager.directActionListFallbacks or 0
BarManager.actionHotRecords = BarManager.actionHotRecords or {}
BarManager.actionHotRecordsByButton = BarManager.actionHotRecordsByButton or setmetatable({}, { __mode = "k" })
BarManager.chargeHotRecords = BarManager.chargeHotRecords or {}
BarManager.countHotRecords = BarManager.countHotRecords or {}
BarManager.actionHotRecordCount = BarManager.actionHotRecordCount or 0
BarManager.chargeHotRecordCount = BarManager.chargeHotRecordCount or 0
BarManager.countHotRecordCount = BarManager.countHotRecordCount or 0
BarManager.actionHotRecordsDirty = BarManager.actionHotRecordsDirty ~= false
BarManager.nativeCoreState = BarManager.nativeCoreState or setmetatable({}, { __mode = "k" })
BarManager.nativeCoreCooldownButtons = BarManager.nativeCoreCooldownButtons or setmetatable({}, { __mode = "k" })
BarManager.nativeCoreCooldownDoneHooked = BarManager.nativeCoreCooldownDoneHooked or setmetatable({}, { __mode = "k" })
BarManager.broadcasterMode = BarManager.broadcasterMode or "unknown"
BarManager.broadcasterOff = BarManager.broadcasterOff or 0
BarManager.broadcasterOn = BarManager.broadcasterOn or 0
BarManager.broadcasterRestores = BarManager.broadcasterRestores or 0
BarManager.broadcasterFallbacks = BarManager.broadcasterFallbacks or 0
BarManager.broadcasterActual = BarManager.broadcasterActual or "unknown"
BarManager.broadcasterRegisteredEvents = BarManager.broadcasterRegisteredEvents or 0
BarManager.broadcasterButtonRegistered = BarManager.broadcasterButtonRegistered or 0
BarManager.broadcasterActionRegistered = BarManager.broadcasterActionRegistered or 0
BarManager.broadcasterReregisters = BarManager.broadcasterReregisters or 0
BarManager.broadcasterMismatch = BarManager.broadcasterMismatch or 0
BarManager.procButtonsBySpellID = BarManager.procButtonsBySpellID or {}
BarManager.procButtonsByFlyoutID = BarManager.procButtonsByFlyoutID or {}
BarManager.activeProcButtons = BarManager.activeProcButtons or setmetatable({}, { __mode = "k" })
BarManager.activeProcSpellIDs = BarManager.activeProcSpellIDs or {}
BarManager.actionIdentityGeneration = tonumber(BarManager.actionIdentityGeneration) or 1
BarManager.procIndexCompleteGeneration = tonumber(BarManager.procIndexCompleteGeneration) or 0
BarManager.procIndexMode = BarManager.procIndexMode == "production" and "production" or "shadow"
BarManager.procGlowVisited = BarManager.procGlowVisited or {}
BarManager.procGlowIndexedCandidates = BarManager.procGlowIndexedCandidates or {}
BarManager.procGlowLegacyCandidates = BarManager.procGlowLegacyCandidates or {}
BarManager.procGlowActiveScratch = BarManager.procGlowActiveScratch or {}
BarManager.procCaptureOverlayBaseline = BarManager.procCaptureOverlayBaseline or setmetatable({}, { __mode = "k" })
BarManager.procIndexShadowComparisons = BarManager.procIndexShadowComparisons or 0
BarManager.procIndexMismatches = BarManager.procIndexMismatches or 0
BarManager.procIndexRebuilds = BarManager.procIndexRebuilds or 0
BarManager.procIndexFallbacks = BarManager.procIndexFallbacks or 0
BarManager.procIndexIndexedShows = BarManager.procIndexIndexedShows or 0
BarManager.procIndexLegalEmptyShows = BarManager.procIndexLegalEmptyShows or 0
BarManager.cooldownState = BarManager.cooldownState or {}
BarManager.configSnapshots = BarManager.configSnapshots or {}
BarManager.configSnapshotVersion = BarManager.configSnapshotVersion or 0
BarManager.configSnapshotCount = BarManager.configSnapshotCount or 0
BarManager.emptySlotGridVisible = BarManager.emptySlotGridVisible == true
BarManager.bindPresentationActive = BarManager.bindPresentationActive == true
BarManager.bindPresentationPending = BarManager.bindPresentationPending == true
BarManager.bindPresentationHolderLayers = BarManager.bindPresentationHolderLayers or setmetatable({}, { __mode = "k" })
BarManager.shutdownDeactivateList = BarManager.shutdownDeactivateList or {}
BarManager.usablePayloadFallbacks = BarManager.usablePayloadFallbacks or 0
BarManager.usableInvalidPayloads = BarManager.usableInvalidPayloads or 0
BarManager.usableReconcileGeneration = BarManager.usableReconcileGeneration or 0
BarManager.usableReconcileSeen = BarManager.usableReconcileSeen or {}
BarManager.usableReconcileUsable = BarManager.usableReconcileUsable or {}
BarManager.usableReconcileNoMana = BarManager.usableReconcileNoMana or {}
BarManager.fullRefreshCount = BarManager.fullRefreshCount or 0
BarManager.lastFullRefreshReason = BarManager.lastFullRefreshReason or nil
BarManager.structuralBatchCount = BarManager.structuralBatchCount or 0
BarManager.structuralBarChangeCount = BarManager.structuralBarChangeCount or 0
BarManager.slotGlobalFallbacks = BarManager.slotGlobalFallbacks or 0
BarManager.slotIdentityNarrowHits = BarManager.slotIdentityNarrowHits or 0
BarManager.slotIdentityFallbacks = BarManager.slotIdentityFallbacks or 0
BarManager.slotIdentityShadowComparisons = BarManager.slotIdentityShadowComparisons or 0
BarManager.slotIdentityShadowMismatches = BarManager.slotIdentityShadowMismatches or 0
BarManager.slotIdentityNarrowDisabled = BarManager.slotIdentityNarrowDisabled == true
BarManager.rangeMapDirty = BarManager.rangeMapDirty ~= false
BarManager.rangeMapReconciles = BarManager.rangeMapReconciles or 0
BarManager.externalSpecialApplying = BarManager.externalSpecialApplying or {}

local DEFAULT_BORDER_COLOR = { 0, 0, 0, 1 }
local SPECIAL_PLACEHOLDER_TEXTURES = {
    pet = {
        "Interface\\Icons\\Ability_Hunter_BeastCall",
        "Interface\\Icons\\Ability_Druid_Dash",
        "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
        "Interface\\Icons\\Ability_Hunter_Pet_Bear",
        "Interface\\Icons\\Spell_Nature_SpiritWolf",
        "Interface\\Icons\\Ability_Hunter_MendPet",
        "Interface\\Icons\\Ability_Hunter_CatlikeReflexes",
        "Interface\\Icons\\Ability_Mount_JungleTiger",
        "Interface\\Icons\\Ability_Hunter_BeastSoothe",
        "Interface\\Icons\\INV_Misc_MonsterClaw_03",
    },
    stance = {
        "Interface\\Icons\\Ability_Druid_CatForm",
        "Interface\\Icons\\Ability_Racial_BearForm",
        "Interface\\Icons\\Ability_Druid_TravelForm",
        "Interface\\Icons\\Ability_Druid_AquaticForm",
        "Interface\\Icons\\Spell_Nature_ForceOfNature",
        "Interface\\Icons\\Spell_Nature_StarFall",
        "Interface\\Icons\\Ability_Druid_FlightForm",
        "Interface\\Icons\\Ability_Druid_Eclipse",
        "Interface\\Icons\\Ability_Druid_TreeofLife",
        "Interface\\Icons\\Spell_Nature_WispSplode",
    },
    possess = {
        "Interface\\Icons\\Spell_Shadow_Charm",
        "Interface\\Icons\\Spell_Shadow_MindSteal",
        "Interface\\Icons\\Spell_Shadow_Possession",
        "Interface\\Icons\\Spell_Shadow_Teleport",
        "Interface\\Icons\\Spell_Shadow_SoulLeech_3",
        "Interface\\Icons\\Spell_Shadow_ShadowWordDominate",
        "Interface\\Icons\\Spell_Shadow_PsychicScream",
        "Interface\\Icons\\Spell_Shadow_DeathCoil",
        "Interface\\Icons\\Spell_Shadow_SummonVoidWalker",
        "Interface\\Icons\\Spell_Shadow_Shadesofdarkness",
    },
}

local DEFAULT_CONFIG_SNAPSHOT = {
    alpha = 1,
    skin = "square",
    iconZoom = 0.08,
    border = "thin",
    borderColor = DEFAULT_BORDER_COLOR,
    background = "black",
    backgroundColor = { 34 / 255, 34 / 255, 34 / 255, 0.72 },
    shadow = true,
    shadowColor = { 0, 0, 0, 0.5 },
    cooldownFade = true,
    cooldownTextSize = 12,
    rangeMode = "red",
    showHotkeys = true,
    hotkeySize = 12,
    hotkeyOffsetX = 0,
    hotkeyOffsetY = 0,
    showCounts = true,
    countSize = 12,
    countOffsetX = 0,
    countOffsetY = 0,
    showMacroNames = true,
    macroNameSize = 10,
    macroNameOffsetX = 0,
    macroNameOffsetY = 0,
    cooldownTextOffsetX = 0,
    cooldownTextOffsetY = 0,
    showProfessionQuality = true,
    professionQualitySize = 21,
    professionQualityOffsetX = 0,
    professionQualityOffsetY = 0,
    alignment = "left",
}

local REMAINING_DURATION_EPSILON_SECONDS = 0.001
local MAX_EXPECTED_GCD_SECONDS = 1.5
local GCD_MARGIN_SECONDS = 0.1
local LAYOUT_SKIN_ASPECTS = {
    flatSquare = 1.35,
    flatRounded = 1.35,
    wideSquare = 10 / 9,
    wideRounded = 10 / 9,
}
local REAL_COOLDOWN_THRESHOLD_SECONDS = MAX_EXPECTED_GCD_SECONDS + GCD_MARGIN_SECONDS

local HOT_EVENTS = {
    "ACTIONBAR_SHOWGRID",
    "ACTIONBAR_HIDEGRID",
    "ACTIONBAR_SLOT_CHANGED",
    "ACTIONBAR_PAGE_CHANGED",
    "ACTIONBAR_UPDATE_COOLDOWN",
    "ACTIONBAR_UPDATE_STATE",
    "PLAYER_ENTER_COMBAT",
    "PLAYER_LEAVE_COMBAT",
    "START_AUTOREPEAT_SPELL",
    "STOP_AUTOREPEAT_SPELL",
    "ACTIONBAR_UPDATE_USABLE",
    "ACTION_RANGE_CHECK_UPDATE",
    "ACTION_USABLE_CHANGED",
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",
    "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
    "SPELL_UPDATE_CHARGES",
    "SPELL_UPDATE_USES",
    "SPELL_UPDATE_ICON",
    "SPELLS_CHANGED",
    "UPDATE_BINDINGS",
    "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_EXTRA_ACTIONBAR",
    "UPDATE_OVERRIDE_ACTIONBAR",
    "UPDATE_VEHICLE_ACTIONBAR",
    "UPDATE_POSSESS_BAR",
    "UPDATE_SHAPESHIFT_FORMS",
    "UPDATE_SHAPESHIFT_FORM",
    "UPDATE_SHAPESHIFT_USABLE",
    "UPDATE_SHAPESHIFT_COOLDOWN",
    "PET_BAR_UPDATE",
    "PET_BAR_UPDATE_COOLDOWN",
    "PET_BAR_UPDATE_USABLE",
    "PET_BATTLE_OPENING_DONE",
    "PET_BATTLE_CLOSE",
    "UNIT_PET",
    "UNIT_ENTERED_VEHICLE",
    "UNIT_EXITED_VEHICLE",
    "VEHICLE_UPDATE",
    "UNIT_AURA",
    "HOUSE_EDITOR_MODE_CHANGED",
    "PLAYER_TARGET_CHANGED",
    "CVAR_UPDATE",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_REGEN_DISABLED",
}

local ORDINARY_ACTION_EVENTS = {
    ACTIONBAR_SHOWGRID = true,
    ACTIONBAR_HIDEGRID = true,
    ACTIONBAR_SLOT_CHANGED = true,
    ACTIONBAR_PAGE_CHANGED = true,
    SPELL_ACTIVATION_OVERLAY_GLOW_SHOW = true,
    SPELL_ACTIVATION_OVERLAY_GLOW_HIDE = true,
    SPELLS_CHANGED = true,
    SPELL_UPDATE_USES = true,
    UNIT_AURA = true,
}

local ACTION_CONSUMER_EVENTS = {
    ACTIONBAR_UPDATE_COOLDOWN = true,
    ACTIONBAR_UPDATE_STATE = true,
    PLAYER_ENTER_COMBAT = true,
    PLAYER_LEAVE_COMBAT = true,
    START_AUTOREPEAT_SPELL = true,
    STOP_AUTOREPEAT_SPELL = true,
    ACTIONBAR_UPDATE_USABLE = true,
    ACTION_RANGE_CHECK_UPDATE = true,
    ACTION_USABLE_CHANGED = true,
    SPELL_UPDATE_CHARGES = true,
    SPELL_UPDATE_ICON = true,
    PLAYER_TARGET_CHANGED = true,
}

local BROADCASTER_BUTTON_MANIFEST = {
    { event = "PLAYER_ENTERING_WORLD" },
    { event = "ACTIONBAR_SLOT_CHANGED" },
    { event = "UPDATE_BINDINGS" },
    { event = "GAME_PAD_ACTIVE_CHANGED" },
    { event = "UPDATE_SHAPESHIFT_FORM" },
    { event = "ACTIONBAR_UPDATE_COOLDOWN" },
    { event = "PET_BAR_UPDATE" },
    { event = "PLAYER_MOUNT_DISPLAY_CHANGED" },
    { event = "UNIT_FLAGS", unit = "pet" },
    { event = "UNIT_AURA", unit = "pet" },
}

local BROADCASTER_ACTION_MANIFEST = {
    { event = "SPELL_UPDATE_CHARGES" },
    { event = "UPDATE_INVENTORY_ALERTS" },
    { event = "TRADE_SKILL_SHOW" },
    { event = "TRADE_SKILL_CLOSE" },
    { event = "ARCHAEOLOGY_CLOSED" },
    { event = "PLAYER_ENTER_COMBAT" },
    { event = "PLAYER_LEAVE_COMBAT" },
    { event = "START_AUTOREPEAT_SPELL" },
    { event = "STOP_AUTOREPEAT_SPELL" },
    { event = "UNIT_ENTERED_VEHICLE" },
    { event = "UNIT_EXITED_VEHICLE" },
    { event = "COMPANION_UPDATE" },
    { event = "UNIT_INVENTORY_CHANGED" },
    { event = "UNIT_SPELLCAST_SENT" },
    { event = "LEARNED_SPELL_IN_SKILL_LINE" },
    { event = "PET_STABLE_UPDATE" },
    { event = "PET_STABLE_SHOW" },
    { event = "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" },
    { event = "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" },
    { event = "UPDATE_SUMMONPETS_ACTION" },
    { event = "SPELL_UPDATE_ICON" },
    { event = "UNIT_SPELLCAST_INTERRUPTED", unit = "player" },
    { event = "UNIT_SPELLCAST_SUCCEEDED", unit = "player" },
    { event = "UNIT_SPELLCAST_FAILED", unit = "player" },
    { event = "UNIT_SPELLCAST_START", unit = "player" },
    { event = "UNIT_SPELLCAST_STOP", unit = "player" },
    { event = "UNIT_SPELLCAST_CHANNEL_START", unit = "player" },
    { event = "UNIT_SPELLCAST_CHANNEL_STOP", unit = "player" },
    { event = "UNIT_SPELLCAST_RETICLE_TARGET", unit = "player" },
    { event = "UNIT_SPELLCAST_RETICLE_CLEAR", unit = "player" },
    { event = "UNIT_SPELLCAST_EMPOWER_START", unit = "player" },
    { event = "UNIT_SPELLCAST_EMPOWER_STOP", unit = "player" },
    { event = "LOSS_OF_CONTROL_ADDED", unit = "player" },
    { event = "LOSS_OF_CONTROL_UPDATE", unit = "player" },
}

local FULL_REFRESH_REASONS = {
    create = true,
    refresh = true,
    rebuild = true,
    profile = true,
    config = true,
    layout = true,
    PLAYER_ENTERING_WORLD = true,
}

local BROADCASTER_REFRESH_EVENTS = {
    PLAYER_ENTERING_WORLD = true,
    PLAYER_REGEN_ENABLED = true,
    UPDATE_OVERRIDE_ACTIONBAR = true,
    UPDATE_VEHICLE_ACTIONBAR = true,
}

local MAIN_PAGE_IDENTITY_EVENTS = {
    ACTIONBAR_PAGE_CHANGED = true,
    UPDATE_BONUS_ACTIONBAR = true,
}

local VEHICLE_PAGE_IDENTITY_EVENTS = {
    UPDATE_OVERRIDE_ACTIONBAR = true,
    UPDATE_VEHICLE_ACTIONBAR = true,
}

local SPECIAL_NATIVE_SUPPRESSION_KINDS = { "pet", "stance", "possess" }
local MANAGED_SPECIAL_BUTTON_KINDS = { pet = true, stance = true, possess = true }
local COMPACT_SPECIAL_LAYOUT_KINDS = { stance = true, possess = true }
local ALIGNMENT_VALUES = { left = true, center = true, right = true }
local EXTERNAL_SPECIAL_BARS

local function ShouldRegisterHotEvent(event, auraEnabled, hasOrdinaryActions, hasExtraAction)
    if ORDINARY_ACTION_EVENTS[event] and hasOrdinaryActions ~= true then
        return false
    end
    if ACTION_CONSUMER_EVENTS[event] and hasOrdinaryActions ~= true and hasExtraAction ~= true then
        return false
    end
    if event == "UNIT_AURA" then
        return auraEnabled == true
    end
    if event == "PET_BATTLE_OPENING_DONE" or event == "PET_BATTLE_CLOSE" then
        return YAB.Adapter and YAB.Adapter.SupportsPetBattleState and YAB.Adapter:SupportsPetBattleState() == true
    end
    if event == "HOUSE_EDITOR_MODE_CHANGED" then
        return YAB.Adapter and YAB.Adapter.IsHouseEditorAvailable and YAB.Adapter:IsHouseEditorAvailable() == true
    end
    return true
end

local function RegisterHotEvent(frame, event, auraEnabled, hasOrdinaryActions, hasExtraAction)
    if not ShouldRegisterHotEvent(event, auraEnabled, hasOrdinaryActions, hasExtraAction) then
        return false
    end
    if event == "UNIT_AURA" and frame.RegisterUnitEvent then
        return pcall(frame.RegisterUnitEvent, frame, event, "player") == true
    end
    return pcall(frame.RegisterEvent, frame, event) == true
end

local function InCombat()
    return YAB.Adapter and YAB.Adapter:InCombat()
end

local function IsLayoutEditing()
    return YUI and YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing() == true
end

local function IsBindPresentationEditing(kind)
    if BarManager.bindPresentationActive ~= true then return false end
    if kind and YAB.SpecialBars and YAB.SpecialBars.IsRuntimeKeybindable then
        return YAB.SpecialBars:IsRuntimeKeybindable(kind) ~= false
    end
    return true
end

local function IsPresentationEditing(kind)
    return IsLayoutEditing() or IsBindPresentationEditing(kind)
end

local function ButtonHasNativeCommand(button)
    local factory = YAB.SecureFactory
    local command = factory and factory.GetButtonCommand and factory:GetButtonCommand(button)
        or (button and button.commandName)
    return type(command) == "string" and command ~= ""
end

local function ButtonListHasNativeCommand(buttons)
    for _, button in pairs(buttons or {}) do
        if ButtonHasNativeCommand(button) then return true end
    end
    return false
end

function BarManager:IsBindPresentationEligible(record)
    if not record then return false end
    local barId = record.id or record.kind
    if YAB.SpecialBars and YAB.SpecialBars.IsRuntimeKeybindable
        and YAB.SpecialBars:IsRuntimeKeybindable(barId) == false
    then
        return false
    end
    return ButtonListHasNativeCommand(record.buttons)
        or ButtonListHasNativeCommand(record.externalButtons)
end

function BarManager:IsRecordInBindPresentation(record)
    return self.bindPresentationActive == true and self:IsBindPresentationEligible(record)
end

function BarManager:RestoreBindPresentationLayers()
    local snapshots = self.bindPresentationHolderLayers
    if type(snapshots) ~= "table" then return true end
    local restored = true
    for holder, state in pairs(snapshots) do
        local strataOk = holder and holder.SetFrameStrata and pcall(holder.SetFrameStrata, holder, state.strata)
        local levelOk = holder and holder.SetFrameLevel and pcall(holder.SetFrameLevel, holder, state.level)
        if strataOk and levelOk then
            snapshots[holder] = nil
        else
            restored = false
        end
    end
    return restored
end

function BarManager:ApplyBindPresentationLayers()
    if next(self.bindPresentationHolderLayers or {}) and not self:RestoreBindPresentationLayers() then
        return false, "holder layer restore failed"
    end
    local snapshots = self.bindPresentationHolderLayers
    for _, record in pairs(self.bars or {}) do
        local holder = record and record.holder
        if holder and self:IsBindPresentationEligible(record) then
            local strataOk, strata = false, nil
            local levelOk, level = false, nil
            if holder.GetFrameStrata then
                strataOk, strata = pcall(holder.GetFrameStrata, holder)
            end
            if holder.GetFrameLevel then
                levelOk, level = pcall(holder.GetFrameLevel, holder)
            end
            if not (strataOk and type(strata) == "string" and levelOk and type(level) == "number") then
                self:RestoreBindPresentationLayers()
                return false, "holder layer capture failed"
            end
            snapshots[holder] = { strata = strata, level = level }
            local setStrataOk = holder.SetFrameStrata and pcall(holder.SetFrameStrata, holder, "DIALOG")
            local setLevelOk = setStrataOk and holder.SetFrameLevel and pcall(holder.SetFrameLevel, holder, 20)
            if not (setStrataOk and setLevelOk) then
                self:RestoreBindPresentationLayers()
                return false, "holder layer raise failed"
            end
        end
    end
    return true
end

local function GetSpecialPlaceholderTexture(kind, index)
    local list = SPECIAL_PLACEHOLDER_TEXTURES[kind]
    if not list or #list == 0 then return nil end
    return list[((index or 1) - 1) % #list + 1]
end

local function GetDB()
    return YAB.GetDB and YAB:GetDB() or nil
end

local function GetStanceBarDisplayLabel(config)
    if YAB.Client.ownedStanceButtons == true then
        local locale = YUI.Locale and YUI.Locale.Get and YUI.Locale:Get("YActionBar") or nil
        local label = locale and locale["bar.stance.retail"]
        if type(label) == "string" and label ~= "" then return label end
    end
    return config and config.label or "姿态/形态条"
end

local function GetBarConfig(db, barId)
    return db and db.bars and db.bars[barId] or nil
end

local function GetSpecialConfig(db, barId)
    return db and db.specialBars and db.specialBars[barId] or nil
end

local function GetEnabledSpecialNativeKinds(db)
    local kinds = {}
    for _, kind in ipairs(SPECIAL_NATIVE_SUPPRESSION_KINDS) do
        local config = GetSpecialConfig(db, kind)
        if config and config.enabled == true then
            kinds[#kinds + 1] = kind
        end
    end
    return kinds
end

local function AuraTimersEnabled(db)
    return db and db.appearance and db.appearance.showAuraTimers == true
end

local function GetRows(config)
    local rows = tonumber(config and config.rows) or 1
    if rows < 1 then rows = 1 end
    return rows
end

local function GetSize(config, db)
    return tonumber(config and config.size) or tonumber(db and db.appearance and db.appearance.buttonSize) or 36
end

local function GetSpacing(config, db)
    local spacing = tonumber(config and config.spacing) or tonumber(db and db.appearance and db.appearance.spacing) or 4
    if spacing < -10 then
        spacing = -10
    elseif spacing > 64 then
        spacing = 64
    end
    return spacing
end

local function SetDegraded(kind, reason)
    local db = GetDB()
    if not (db and db.runtime) then return end
    db.runtime.degraded = db.runtime.degraded or {}
    db.runtime.degraded[kind] = reason
end

local function ClearTable(tbl)
    if not tbl then return tbl end
    for key in pairs(tbl) do
        tbl[key] = nil
    end
    return tbl
end

local function SnapshotNumber(value, fallback, minValue, maxValue)
    local numberValue = tonumber(value) or fallback
    if minValue and numberValue < minValue then numberValue = minValue end
    if maxValue and numberValue > maxValue then numberValue = maxValue end
    return numberValue
end

local function SnapshotBoolean(value, fallback)
    if value == nil then return fallback == true end
    return value == true
end

local function SnapshotString(value, fallback)
    if value == nil or value == "" then return fallback end
    return value
end

local function NormalizeAlignment(value, fallback)
    value = tostring(value or "")
    if ALIGNMENT_VALUES[value] then return value end
    return fallback or "left"
end

local function SnapshotColor(value, fallback, target)
    fallback = fallback or DEFAULT_BORDER_COLOR
    local source = type(value) == "table" and value or fallback
    target = target or {}
    target[1] = SnapshotNumber(source[1], fallback[1] or 0, 0, 1)
    target[2] = SnapshotNumber(source[2], fallback[2] or 0, 0, 1)
    target[3] = SnapshotNumber(source[3], fallback[3] or 0, 0, 1)
    target[4] = SnapshotNumber(source[4], fallback[4] == nil and 1 or fallback[4], 0, 1)
    return target
end

local function SnapshotOptionalColor(value, target)
    if type(value) ~= "table" then return nil end
    target = target or {}
    target[1] = SnapshotNumber(value[1] or value.r, 1, 0, 1)
    target[2] = SnapshotNumber(value[2] or value.g, 1, 0, 1)
    target[3] = SnapshotNumber(value[3] or value.b, 1, 0, 1)
    local alpha = value[4]
    if alpha == nil then alpha = value.a end
    target[4] = SnapshotNumber(alpha, 1, 0, 1)
    return target
end

local function GetButtonConfigSnapshot(manager, button, fallbackBarId)
    if manager and button and manager.buttonConfigSnapshots and manager.buttonConfigSnapshots[button] then
        return manager.buttonConfigSnapshots[button]
    end
    if button and button.yabConfigSnapshot then
        return button.yabConfigSnapshot
    end
    if manager and fallbackBarId and manager.GetConfigSnapshot then
        return manager:GetConfigSnapshot(fallbackBarId) or DEFAULT_CONFIG_SNAPSHOT
    end
    return DEFAULT_CONFIG_SNAPSHOT
end

local function GetButtonMeta(button)
    return YAB.SecureFactory and YAB.SecureFactory.GetButtonMeta and YAB.SecureFactory:GetButtonMeta(button) or nil
end

local function IsNativeSpecialButton(button)
    local meta = GetButtonMeta(button)
    return meta and meta.nativeSpecial == true
end

local function IsManagedActionButton(button)
    local meta = GetButtonMeta(button)
    return meta and meta.nativeSpecial ~= true and meta.barId ~= nil
end

local function SetManagedActionButtonShown(manager, button, shown)
    if not button then return false end
    shown = shown == true
    if shown then
        if button.Show then button:Show() end
    else
        if button.Hide then button:Hide() end
    end
    if manager then
        manager.emptyButtonShown[button] = shown
        manager.pendingEmptyButtonShown[button] = nil
    end
    return true
end

local function SetButtonConfigSnapshot(manager, button, snapshot)
    if not button then return end
    if IsNativeSpecialButton(button) or IsManagedActionButton(button) or (manager.externalButtonOwners and manager.externalButtonOwners[button]) then
        manager.buttonConfigSnapshots[button] = snapshot
    else
        button.yabConfigSnapshot = snapshot
    end
    if IsManagedActionButton(button)
        and YAB.SecureFactory
        and YAB.SecureFactory.UpdateActionDragButton then
        YAB.SecureFactory:UpdateActionDragButton(button, snapshot ~= nil, snapshot and snapshot.hideEmptySlots == true)
    end
end

local function IsRangeSnapshotEnabled(snapshot)
    return snapshot and snapshot.rangeMode == "red"
end

local function GetConfiguredButtonCount(config, snapshot)
    local count = math.floor(tonumber(snapshot and snapshot.buttons) or tonumber(config and config.buttons) or 12)
    if count < 1 then
        count = 1
    elseif count > 12 then
        count = 12
    end
    return count
end

local function GetSpecialButtonCount(kind, config, snapshot)
    if YAB.SpecialBars and YAB.SpecialBars.GetRuntimeButtonCount then
        local count = YAB.SpecialBars:GetRuntimeButtonCount(kind, config, snapshot)
        if count then return count end
    end
    return GetConfiguredButtonCount(config, snapshot)
end

local function GetManagedSpecialButtonCount(kind, config, snapshot)
    local usePresentationCount = IsBindPresentationEditing(kind)
        or (kind ~= "stance" and IsLayoutEditing())
    if usePresentationCount and YAB.SpecialBars and YAB.SpecialBars.GetEditModeButtonCount then
        local count = YAB.SpecialBars:GetEditModeButtonCount(kind, config, snapshot)
        if count then return count end
    end
    return GetSpecialButtonCount(kind, config, snapshot)
end

local function GetLayoutButtonSize(config, snapshot, db)
    local size = tonumber(snapshot and snapshot.size) or GetSize(config, db)
    local width = size
    local height = size
    local skin = snapshot and snapshot.skin
    local aspect = LAYOUT_SKIN_ASPECTS[skin]
    if aspect then
        height = math.floor((size / aspect) + 0.5)
        if height < 1 then height = 1 end
    end
    return width, height, size
end

local function IsManagedSpecialButtonRecord(record)
    return record and MANAGED_SPECIAL_BUTTON_KINDS[record.kind] == true
end

local function IsCompactSpecialLayoutRecord(record)
    return record and COMPACT_SPECIAL_LAYOUT_KINDS[record.kind] == true
end

local function GetStanceFormCount()
    if not (YAB.Adapter and YAB.Adapter.GetNumShapeshiftForms) then return 0 end
    return math.floor(tonumber(YAB.Adapter:GetNumShapeshiftForms()) or 0)
end

local function IsSpecialButtonVisibleForLayout(kind, index, forcePlaceholder)
    if forcePlaceholder then return true end
    if not YAB.Adapter then return true end
    if kind == "pet" then
        local name, texture = YAB.Adapter:GetPetActionInfo(index)
        return name ~= nil or texture ~= nil
    elseif kind == "stance" then
        local formCount = GetStanceFormCount()
        if formCount > 0 then
            return index <= formCount
        end
        local iconTexture = YAB.Adapter:GetShapeshiftFormInfo(index)
        return iconTexture ~= nil
    elseif kind == "possess" then
        local texture = YAB.Adapter:GetPossessInfo(index)
        return texture ~= nil
    end
    return true
end

local function BuildLayoutButtons(record, maxCount)
    local buttons = record and record.buttons
    if not buttons then return nil, 0, nil end
    if not IsCompactSpecialLayoutRecord(record) then
        return buttons, #buttons, nil
    end
    local forcePlaceholder = IsPresentationEditing(record.kind)
    local layoutButtons = record.layoutButtons
    if not layoutButtons then
        layoutButtons = {}
        record.layoutButtons = layoutButtons
    else
        ClearTable(layoutButtons)
    end
    local signature = forcePlaceholder and "placeholder:" or ""
    for index, button in ipairs(buttons) do
        if maxCount and index > maxCount then break end
        if button and IsSpecialButtonVisibleForLayout(record.kind, index, forcePlaceholder) then
            layoutButtons[#layoutButtons + 1] = button
            signature = signature .. tostring(index) .. ":"
        end
    end
    return layoutButtons, #layoutButtons, signature
end

local function GetSnapshotAlpha(snapshot)
    local alpha = tonumber(snapshot and snapshot.alpha) or 1
    if alpha < 0 then
        return 0
    elseif alpha > 1 then
        return 1
    end
    return alpha
end

function BarManager:UpdateConfigSnapshot(barId, config, group)
    if not (barId and type(config) == "table") then return nil end
    local snapshots = self.configSnapshots
    if not snapshots then
        snapshots = {}
        self.configSnapshots = snapshots
    end
    local snapshot = snapshots[barId]
    local previousRangeMode = snapshot and snapshot.rangeMode or nil
    local snapshotCreated = snapshot == nil
    if not snapshot then
        snapshot = {}
        snapshots[barId] = snapshot
        self.configSnapshotCount = (self.configSnapshotCount or 0) + 1
    end

    snapshot.barId = barId
    snapshot.group = group or snapshot.group or "normal"
    snapshot.alpha = SnapshotNumber(config.alpha, 1, 0, 1)
    if YUI.Visibility and type(config.visibility) == "table" then
        snapshot.visibilityRule = YUI.Visibility:NormalizeBranches(config.visibility, snapshot.visibilityRule)
        snapshot.visibility = "always"
    else
        snapshot.visibilityRule = nil
        snapshot.visibility = SnapshotString(config.visibility, "always")
    end
    snapshot.hideEmptySlots = SnapshotBoolean(config.hideEmptySlots, false)
    snapshot.hideSkyriding = SnapshotBoolean(config.hideSkyriding, false)
    snapshot.buttons = SnapshotNumber(config.buttons, 12, 1, 12)
    snapshot.rows = SnapshotNumber(config.rows, 1, 1, barId == "questItems" and 12 or snapshot.buttons)
    snapshot.size = SnapshotNumber(config.size, 36, 1, 128)
    snapshot.spacing = SnapshotNumber(config.spacing, 4, -10, 64)
    snapshot.alignment = NormalizeAlignment(config.alignment, barId == "stance" and "center" or "left")
    snapshot.skin = SnapshotString(config.skin, "square")
    snapshot.iconZoom = SnapshotNumber(config.iconZoom, 0.08, 0, 1)
    snapshot.border = SnapshotString(config.border, "thin")
    snapshot.borderColor = SnapshotColor(config.borderColor, DEFAULT_BORDER_COLOR, snapshot.borderColor)
    snapshot.background = SnapshotString(config.background, "black")
    snapshot.backgroundColor = SnapshotColor(config.backgroundColor, DEFAULT_CONFIG_SNAPSHOT.backgroundColor, snapshot.backgroundColor)
    snapshot.shadow = SnapshotBoolean(config.shadow, DEFAULT_CONFIG_SNAPSHOT.shadow)
    snapshot.shadowColor = SnapshotColor(config.shadowColor, DEFAULT_CONFIG_SNAPSHOT.shadowColor, snapshot.shadowColor)
    local db = GetDB()
    local pressedEffect = SnapshotString(db and db.appearance and db.appearance.pressedEffect, "darken")
    snapshot.pressedEffect = pressedEffect == "innerGlow" and "innerGlow" or "darken"
    snapshot.cooldownFade = SnapshotBoolean(config.cooldownFade, true)
    snapshot.cooldownTextSize = SnapshotNumber(config.cooldownTextSize, 12, 0, 32)
    snapshot.rangeMode = SnapshotString(config.rangeMode, "red")
    if snapshot.group == "normal" and (snapshotCreated or previousRangeMode ~= snapshot.rangeMode) then
        self.rangeMapDirty = true
    end
    snapshot.showHotkeys = SnapshotBoolean(config.showHotkeys, true)
    snapshot.hotkeyColor = SnapshotOptionalColor(config.hotkeyColor, snapshot.hotkeyColor)
    snapshot.hotkeySize = SnapshotNumber(config.hotkeySize, 12, 1, 64)
    snapshot.hotkeyOffsetX = SnapshotNumber(config.hotkeyOffsetX, 0, -16, 16)
    snapshot.hotkeyOffsetY = SnapshotNumber(config.hotkeyOffsetY, 0, -16, 16)
    snapshot.showCounts = SnapshotBoolean(config.showCounts, true)
    snapshot.countColor = SnapshotOptionalColor(config.countColor, snapshot.countColor)
    snapshot.countSize = SnapshotNumber(config.countSize, 12, 1, 64)
    snapshot.countOffsetX = SnapshotNumber(config.countOffsetX, 0, -16, 16)
    snapshot.countOffsetY = SnapshotNumber(config.countOffsetY, 0, -16, 16)
    snapshot.showMacroNames = SnapshotBoolean(config.showMacroNames, true)
    snapshot.macroNameColor = SnapshotOptionalColor(config.macroNameColor, snapshot.macroNameColor)
    snapshot.macroNameSize = SnapshotNumber(config.macroNameSize, 10, 1, 64)
    snapshot.macroNameOffsetX = SnapshotNumber(config.macroNameOffsetX, 0, -16, 16)
    snapshot.macroNameOffsetY = SnapshotNumber(config.macroNameOffsetY, 0, -16, 16)
    snapshot.cooldownTextOffsetX = SnapshotNumber(config.cooldownTextOffsetX, 0, -16, 16)
    snapshot.cooldownTextOffsetY = SnapshotNumber(config.cooldownTextOffsetY, 0, -16, 16)
    snapshot.cooldownTextColor = SnapshotOptionalColor(config.cooldownTextColor, snapshot.cooldownTextColor)
    snapshot.showProfessionQuality = SnapshotBoolean(config.showProfessionQuality, true)
    snapshot.professionQualitySize = SnapshotNumber(config.professionQualitySize, 21, 8, 32)
    snapshot.professionQualityOffsetX = SnapshotNumber(config.professionQualityOffsetX, 0, -16, 16)
    snapshot.professionQualityOffsetY = SnapshotNumber(config.professionQualityOffsetY, 0, -16, 16)
    if snapshot.group == "special" and YAB.SpecialBars and YAB.SpecialBars.NormalizeConfigSnapshot then
        YAB.SpecialBars:NormalizeConfigSnapshot(barId, snapshot, config)
    end
    snapshot.revision = (snapshot.revision or 0) + 1

    self.configSnapshotVersion = (self.configSnapshotVersion or 0) + 1
    return snapshot
end

function BarManager:GetConfigSnapshot(barId)
    return self.configSnapshots and self.configSnapshots[barId] or nil
end

function BarManager:GetRuntimeSpecialPresentationConfig(barId, config)
    if self.specialGroupConfig
        and YAB.IsSpecialBarGrouped
        and YAB:IsSpecialBarGrouped(barId, self:GetSpecialGroupingMode()) == true then
        return self.specialGroupConfig
    end
    return config
end

function BarManager:RefreshConfigSnapshot(barId, db)
    db = db or GetDB()
    if not (db and barId) then return nil end
    local config = GetBarConfig(db, barId)
    if config then
        return self:UpdateConfigSnapshot(barId, config, "normal")
    end
    config = GetSpecialConfig(db, barId)
    if config then
        config = self:GetRuntimeSpecialPresentationConfig(barId, config)
        return self:UpdateConfigSnapshot(barId, config, "special")
    end
    return nil
end

function BarManager:RefreshConfigSnapshots(db)
    db = db or GetDB()
    if not db then return 0 end
    local count = 0
    for _, barId in ipairs(YAB.BAR_ORDER or {}) do
        local config = GetBarConfig(db, barId)
        if config then
            self:UpdateConfigSnapshot(barId, config, "normal")
            count = count + 1
        end
    end
    for _, barId in ipairs(YAB.SPECIAL_BAR_ORDER or {}) do
        local config = GetSpecialConfig(db, barId)
        if config then
            config = self:GetRuntimeSpecialPresentationConfig(barId, config)
            self:UpdateConfigSnapshot(barId, config, "special")
            count = count + 1
        end
    end
    self.configSnapshotCount = count
    return count
end

function BarManager:AttachConfigSnapshot(record, barId, config, group)
    if not record then return nil end
    if not config then
        record.configSnapshot = nil
        if record.buttons then
            for _, button in ipairs(record.buttons) do
                if button then
                    SetButtonConfigSnapshot(self, button, nil)
                end
            end
        end
        return nil
    end
    local snapshot = self:GetConfigSnapshot(barId)
    if not snapshot and config then
        snapshot = self:UpdateConfigSnapshot(barId, config, group)
    end
    record.configSnapshot = snapshot
    if record.kind == "action" then
        self.actionHotRecordsDirty = true
    end
    if record.buttons then
        for _, button in ipairs(record.buttons) do
            if button then
                SetButtonConfigSnapshot(self, button, snapshot)
            end
        end
    end
    return snapshot
end

local function AddButtonToListMap(map, key, button)
    if not (map and key and button) then return end
    local list = map[key]
    if not list then
        list = {}
        map[key] = list
    end
    for index = 1, #list do
        if list[index] == button then
            return
        end
    end
    list[#list + 1] = button
end

local function RemoveButtonFromListMap(map, key, button)
    if not (map and key and button) then return end
    local list = map[key]
    if not list then return end
    for index = #list, 1, -1 do
        if list[index] == button then
            table.remove(list, index)
            break
        end
    end
    if #list == 0 then
        map[key] = nil
    end
end

local function CountTableKeys(tbl)
    local count = 0
    for _ in pairs(tbl or {}) do
        count = count + 1
    end
    return count
end

local function NormalizeEventBoolean(value)
    if type(value) == "boolean" then return value end
    if type(value) == "number" then return value ~= 0 end
    if type(value) == "string" then
        return value == "1" or value == "true" or value == "TRUE"
    end
    return nil
end

local function IsSecretValue(value)
    return Security and Security.IsSecretValue and Security.IsSecretValue(value) == true or false
end

local function SafeCooldownNumber(value)
    if IsSecretValue(value) then return nil end
    if value == nil then return nil end
    if Security and Security.SafeNumber then
        return Security.SafeNumber(value)
    end
    local ok, numberValue = pcall(tonumber, value)
    if ok and numberValue ~= nil and not IsSecretValue(numberValue) then
        return numberValue
    end
    return nil
end

local function FastBoolean(value, nilValue)
    if IsSecretValue(value) then return nil end
    if value == nil then return nilValue end
    local valueType = type(value)
    if valueType == "boolean" then return value end
    if valueType == "number" then return value ~= 0 end
    return nil
end

local function ResetVisualState(state)
    state.hasAction = false
    state.texture = nil
    state.count = nil
    state.displayCount = nil
    state.countText = ""
    state.hotkeyText = ""
    state.nameText = ""
    state.hotkeyReady = false
    state.cooldownStart = nil
    state.cooldownDuration = nil
    state.cooldownEnable = nil
    state.cooldownModRate = nil
    state.cooldownDurationObject = nil
    state.realCooldownDurationObject = nil
    state.cooldownActive = false
    state.cooldownOnGCD = false
    state.chargeStart = nil
    state.chargeDuration = nil
    state.chargeEnable = nil
    state.chargeModRate = nil
    state.chargeDurationObject = nil
    state.usable = true
    state.noMana = false
    state.inRange = nil
    state.rangeMode = nil
    state.checked = false
    state.procGlow = false
    state.assistedCombat = false
    state.petAutoCastAllowed = false
    state.petAutoCastEnabled = false
    state.actionSpellID = nil
    state.actionType = nil
    state.actionID = nil
    state.actionSubType = nil
    state.procSpellID = nil
    state.flyoutID = nil
    state.macroText = ""
    state.identityReady = false
    state.slot = nil
    state.auraActive = false
    state.auraStart = nil
    state.auraDuration = nil
    state.auraExpirationTime = nil
    return state
end

local function UpdateButtonVisual(button, state, mode)
    if YAB.Visuals and YAB.Visuals.UpdateButton then
        return YAB.Visuals:UpdateButton(button, state, mode) or 0
    end
    return 0
end

local function BuildCountText(state, snapshot)
    if not state or state.hasAction ~= true then return "" end
    if not (snapshot and snapshot.showCounts == true) then return "" end
    local display = state.displayCount
    if IsSecretValue(display) then
        return display
    end
    if type(display) == "string" then
        return display
    end
    if type(display) == "number" then
        return tostring(display)
    end
    local count = type(state.count) == "number" and state.count or 0
    return count > 1 and tostring(count) or ""
end

local function BuildNameText(state, snapshot)
    if not (snapshot and snapshot.showMacroNames == true) then return "" end
    return type(state.macroText) == "string" and state.macroText or ""
end

local nativeCoreCurvesReady = false
local nativeCoreDesatCurveAny
local nativeCoreDesatCurveReal

local function GetNativeCoreState(manager, button)
    local states = manager.nativeCoreState
    if type(states) ~= "table" then
        states = setmetatable({}, { __mode = "k" })
        manager.nativeCoreState = states
    end
    local state = states[button]
    if not state then
        state = {}
        states[button] = state
    end
    return state
end

local function GetButtonAction(button)
    local action = button and button.GetAttribute and button:GetAttribute("action") or nil
    if type(action) ~= "number" then
        action = tonumber(action)
    end
    if type(action) ~= "number" and button then
        local directAction = button.action
        if type(directAction) == "number" then
            action = directAction
        else
            action = tonumber(directAction)
        end
    end
    return action
end

function BarManager:GetRecordButtonActionSlot(barId, button, page, index)
    if barId == "main" then
        local action = GetButtonAction(button)
        if action then return action end
    end
    return YAB.Adapter:GetActionSlot(page, index)
end

local function IsButtonVisible(button, holder)
    if holder and holder.IsShown and not holder:IsShown() then return false end
    return button and button.IsShown and button:IsShown()
end

local function ForEachVisibleSystemActionButton(callback)
    local button = _G.ExtraActionButton1
    if not IsButtonVisible(button) then return end
    local action = GetButtonAction(button)
    if action then callback(button, action) end
end

local function GetButtonIcon(button)
    if not button then return nil end
    if button.icon then return button.icon end
    if button.Icon then return button.Icon end
    local name = button.GetName and button:GetName()
    return name and _G[name .. "Icon"] or nil
end

local function GetButtonIconDiagnostic(button)
    if not button then return nil, "none" end
    if button.icon then return button.icon, "icon" end
    if button.Icon then return button.Icon, "Icon" end
    local name = button.GetName and button:GetName()
    local icon = name and _G[name .. "Icon"] or nil
    return icon, icon and "global" or "none"
end

local function GetButtonCooldown(button)
    return button and (button.cooldown or button.Cooldown) or nil
end

local function GetButtonChargeCooldown(button)
    return button and button.chargeCooldown or nil
end

local function GetButtonCount(button)
    return button and button.Count or nil
end

local function GetCooldownDesaturation(button)
    local visual = YAB.Visuals and YAB.Visuals.GetButtonVisual and YAB.Visuals:GetButtonVisual(button) or nil
    if visual and visual.cooldownDesaturation ~= nil then
        return visual.cooldownDesaturation
    end
    local skin = visual and visual.skin
    return (skin and skin.cooldownDesaturation) or 1
end

local function SetShownCached(state, key, region, shown)
    if not region or not region.SetShown then return 0 end
    shown = shown == true
    if state[key] == shown then return 0 end
    state[key] = shown
    region:SetShown(shown)
    return 1
end

local function SetCheckedCached(state, button, checked)
    if not (button and button.SetChecked) then return 0 end
    checked = checked == true
    if state.checked == checked then return 0 end
    state.checked = checked
    button:SetChecked(checked)
    return 1
end

function BarManager:SetButtonCheckedState(button, checked, nativeState)
    checked = checked == true
    local state = self.buttonStates[button]
    if state then state.checked = checked end
    return SetCheckedCached(nativeState or GetNativeCoreState(self, button), button, checked)
end

function BarManager:ClearButtonCheckedState(button)
    local nativeState = self.nativeCoreState[button]
    if not nativeState then
        local state = self.buttonStates[button]
        if state then state.checked = false end
        if button.SetChecked and (not button.GetChecked or button:GetChecked() == true) then
            button:SetChecked(false)
            return 1
        end
        return 0
    end
    -- Click and drag scripts can change the widget before our cached event path.
    if button.GetChecked then nativeState.checked = button:GetChecked() == true end
    return self:SetButtonCheckedState(button, false, nativeState)
end

local function ShouldHideNativeCoreCooldownNumbers(snapshot)
    return not (type(snapshot) == "table"
        and type(snapshot.cooldownTextSize) == "number"
        and snapshot.cooldownTextSize > 0)
end

local function SetCooldownNumbersHiddenCached(state, key, cooldown, hidden)
    if not (cooldown and cooldown.SetHideCountdownNumbers) then return 0 end
    hidden = hidden == true
    if state[key] == hidden then return 0 end
    state[key] = hidden
    cooldown:SetHideCountdownNumbers(hidden)
    return 1
end

local function ClearCooldownCached(state, key, cooldown)
    if not cooldown then return 0 end
    if state[key] == false then return 0 end
    if cooldown.Clear then
        cooldown:Clear()
    elseif cooldown.Hide then
        cooldown:Hide()
    end
    state[key] = false
    if key == "mainActive" then
        state.mainStart = nil
        state.mainDuration = nil
        state.mainModRate = nil
    else
        state.chargeStart = nil
        state.chargeDuration = nil
        state.chargeModRate = nil
    end
    return 1
end

local function SetCooldownDurationObjectCached(state, key, cooldown, durationObject)
    if not (cooldown and durationObject and cooldown.SetCooldownFromDurationObject) then return 0, false end
    cooldown:SetCooldownFromDurationObject(durationObject)
    state[key] = true
    if key == "mainActive" then
        state.mainStart = nil
        state.mainDuration = nil
        state.mainModRate = nil
    else
        state.chargeStart = nil
        state.chargeDuration = nil
        state.chargeModRate = nil
    end
    return 1, true
end

local function SetCooldownScalarCached(state, key, cooldown, safeBegin, safeSpan, safeRate)
    if not (cooldown and cooldown.SetCooldown) then return 0 end
    if key == "mainActive" then
        if state.mainActive == true
            and state.mainStart == safeBegin
            and state.mainDuration == safeSpan
            and state.mainModRate == safeRate then
            return 0
        end
        state.mainStart = safeBegin
        state.mainDuration = safeSpan
        state.mainModRate = safeRate
    else
        if state.chargeActive == true
            and state.chargeStart == safeBegin
            and state.chargeDuration == safeSpan
            and state.chargeModRate == safeRate then
            return 0
        end
        state.chargeStart = safeBegin
        state.chargeDuration = safeSpan
        state.chargeModRate = safeRate
    end
    if safeRate ~= nil then
        cooldown:SetCooldown(safeBegin, safeSpan, safeRate)
    else
        cooldown:SetCooldown(safeBegin, safeSpan)
    end
    if cooldown.Show then cooldown:Show() end
    state[key] = true
    return 1
end

local function EnsureNativeCoreCurves()
    if nativeCoreCurvesReady then return nativeCoreDesatCurveAny, nativeCoreDesatCurveReal end
    nativeCoreCurvesReady = true
    if not (C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType) then
        return nil, nil
    end
    nativeCoreDesatCurveAny = C_CurveUtil.CreateCurve()
    nativeCoreDesatCurveAny:SetType(Enum.LuaCurveType.Step)
    nativeCoreDesatCurveAny:AddPoint(0, 0)
    nativeCoreDesatCurveAny:AddPoint(REMAINING_DURATION_EPSILON_SECONDS, 1)
    nativeCoreDesatCurveReal = C_CurveUtil.CreateCurve()
    nativeCoreDesatCurveReal:SetType(Enum.LuaCurveType.Step)
    nativeCoreDesatCurveReal:AddPoint(0, 0)
    nativeCoreDesatCurveReal:AddPoint(REAL_COOLDOWN_THRESHOLD_SECONDS, 1)
    return nativeCoreDesatCurveAny, nativeCoreDesatCurveReal
end

local function SetIconDesaturationNative(icon, value, clearDesaturated, resetDesaturated)
    if not icon then return 0 end
    local writes = 0
    if clearDesaturated == true then
        if icon.SetDesaturation then
            icon:SetDesaturation(0)
            writes = writes + 1
        end
        if icon.SetDesaturated then
            icon:SetDesaturated(false)
            writes = writes + 1
        end
        if writes > 0 and YAB.Visuals and YAB.Visuals.SetIconDesaturationCache then
            YAB.Visuals:SetIconDesaturationCache(icon, 0)
        end
        return writes
    end
    if resetDesaturated == true and icon.SetDesaturated and icon.SetDesaturation then
        icon:SetDesaturated(false)
        writes = writes + 1
    end
    if icon.SetDesaturation then
        icon:SetDesaturation(value)
        writes = writes + 1
    elseif icon.SetDesaturated then
        icon:SetDesaturated(true)
        writes = writes + 1
    end
    if writes > 0 and YAB.Visuals and YAB.Visuals.SetIconDesaturationCache then
        YAB.Visuals:SetIconDesaturationCache(icon, nil)
    end
    return writes
end

local ApplyNativeCoreUsable

local function OnNativeCoreCooldownDone(cooldown)
    local button = cooldown and BarManager.nativeCoreCooldownButtons[cooldown]
    if not button then return end
    local state = BarManager.nativeCoreState and BarManager.nativeCoreState[button]
    if not state then return end
    local meta = GetButtonMeta(button)
    if meta and meta.barId == "stance" then
        if state.stanceCooldownUpdating ~= true then
            BarManager:RefreshStanceButton(button, meta.index, GetDB())
        end
        return
    end
    local hadActiveState = state.mainActive == true or state.mainOnGCD == true
    local hadRealCooldown = state.mainActive == true and state.mainOnGCD ~= true
    if state.nativeDesaturationActive == true then
        SetIconDesaturationNative(GetButtonIcon(button), 0, true)
        state.nativeDesaturationActive = false
    end
    state.mainActive = false
    state.mainOnGCD = false
    state.mainDoneGeneration = (state.mainDoneGeneration or 0) + 1
    local actionState = hadRealCooldown and BarManager.buttonStates and BarManager.buttonStates[button]
    if actionState and actionState.usable == false then
        local action = GetButtonAction(button)
        if action then ApplyNativeCoreUsable(button, action) end
    end
    if hadActiveState and HotDiagnostics and HotDiagnostics.detailEnabled then
        local domain = HotDiagnostics.domains and HotDiagnostics.domains.cooldown
        if domain then domain.doneResets = domain.doneResets + 1 end
    end
end

local function InstallNativeCoreCooldownDone(button)
    local cooldown = GetButtonCooldown(button)
    if not (cooldown and type(cooldown.HookScript) == "function") then return false end
    BarManager.nativeCoreCooldownButtons[cooldown] = button
    if BarManager.nativeCoreCooldownDoneHooked[cooldown] == true then return true end
    local ok = pcall(cooldown.HookScript, cooldown, "OnCooldownDone", OnNativeCoreCooldownDone)
    if ok then
        BarManager.nativeCoreCooldownDoneHooked[cooldown] = true
    else
        BarManager.nativeCoreCooldownButtons[cooldown] = nil
    end
    return ok == true
end

local function UnmapNativeCoreCooldownDone(button)
    local cooldown = GetButtonCooldown(button)
    if cooldown and BarManager.nativeCoreCooldownButtons[cooldown] == button then
        BarManager.nativeCoreCooldownButtons[cooldown] = nil
    end
end

local SetNativeCoreCountText

local function ClearNativeCoreCooldownState(state, button)
    if not state then return 0 end
    local writes = 0
    if state.nativeDesaturationActive == true then
        writes = writes + SetIconDesaturationNative(GetButtonIcon(button), 0, true)
        state.nativeDesaturationActive = false
    end
    writes = writes + ClearCooldownCached(state, "mainActive", GetButtonCooldown(button))
    writes = writes + ClearCooldownCached(state, "chargeActive", GetButtonChargeCooldown(button))
    return writes
end

local function ClearNativeCoreChargeState(state, button, clearCount)
    if not state then return 0 end
    local writes = ClearCooldownCached(state, "chargeActive", GetButtonChargeCooldown(button))
    if clearCount == true and SetNativeCoreCountText then
        writes = writes + SetNativeCoreCountText(BarManager, state, button, "", false)
    end
    return writes
end

local function ClearNativeCoreDesaturationState(manager, button)
    local state = manager and manager.nativeCoreState and manager.nativeCoreState[button]
    if not (state and state.nativeDesaturationActive == true) then return 0 end
    local writes = SetIconDesaturationNative(GetButtonIcon(button), 0, true)
    state.nativeDesaturationActive = false
    return writes
end

local function GetNativeCoreFallbackDisplayCount(action, button, getActionCountFunc, allowEmpty, diagnostic)
    if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
    local count = getActionCountFunc(action)
    if IsSecretValue(count) then return nil, false end
    if type(count) ~= "number" then
        count = tonumber(count)
    end
    if type(count) ~= "number" then
        return nil, false
    end
    local maxDisplayCount = button and button.maxDisplayCount
    if maxDisplayCount ~= nil then
        local maxCount = tonumber(maxDisplayCount)
        if maxCount and count > maxCount then
            return "*", true
        end
    end
    if count > 1 then
        return tostring(count), true
    end
    if allowEmpty == true then
        return "", true
    end
    return nil, false
end

local function GetNativeCoreDisplayCount(action, button, snapshot, getDisplayCountFunc, getActionCountFunc, diagnostic)
    if not (snapshot and snapshot.showCounts == true) then
        return "", true, false
    end
    local maxDisplayCount = button and button.maxDisplayCount
    local display
    if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
    if maxDisplayCount ~= nil then
        display = getDisplayCountFunc(action, maxDisplayCount)
    else
        display = getDisplayCountFunc(action)
    end
    if IsSecretValue(display) then return display, true, true end
    if display == nil then
        local fallbackText, fallbackAuthoritative = GetNativeCoreFallbackDisplayCount(action, button, getActionCountFunc, false, diagnostic)
        return fallbackText, fallbackAuthoritative, false
    end
    local displayType = type(display)
    local text
    if displayType == "string" then
        text = display
    elseif displayType == "number" then
        text = tostring(display)
    else
        local fallbackText, fallbackAuthoritative = GetNativeCoreFallbackDisplayCount(action, button, getActionCountFunc, false, diagnostic)
        return fallbackText, fallbackAuthoritative, false
    end
    return text, true, false
end

SetNativeCoreCountText = function(manager, state, button, text, textIsSecret)
    local writes = 0
    if textIsSecret == true then
        state.countText = nil
        state.countTextSecret = true
        if YAB.Visuals and YAB.Visuals.SetCountTextFast then
            writes = writes + (YAB.Visuals:SetCountTextFast(button, text, true) or 0)
        else
            local count = GetButtonCount(button)
            if count then
                count:SetText(text)
                writes = writes + 1
            end
        end
        return writes
    end

    if text == nil then return 0 end
    text = text or ""
    local previousText = state.countText
    local previousSecret = state.countTextSecret == true
    local changed = true
    if not previousSecret then
        changed = previousText ~= text
    end
    state.countText = text
    state.countTextSecret = false
    if not changed then return 0 end
    if YAB.Visuals and YAB.Visuals.SetCountTextFast then
        writes = writes + (YAB.Visuals:SetCountTextFast(button, text) or 0)
    else
        local count = GetButtonCount(button)
        if count then
            count:SetText(text)
            writes = writes + 1
        end
    end
    return writes
end

local function ApplyNativeCoreCountButton(manager, state, button, action, snapshot, backend, diagnostic)
    local displayText, displayAuthoritative, displaySecret = GetNativeCoreDisplayCount(action, button, snapshot, backend.getDisplayCount, backend.getActionCount, diagnostic)
    if displayAuthoritative then
        return SetNativeCoreCountText(manager, state, button, displayText, displaySecret)
    end
    manager.nativeCoreCountSkips = (manager.nativeCoreCountSkips or 0) + 1
    return 0
end

local function IsItemAction(action)
    if type(_G.GetActionInfo) ~= "function" then return false end
    local actionType = _G.GetActionInfo(action)
    return actionType == "item"
end

local function ComputeNativeCoreDesaturation(button, action, active, onGCD, durationObject, maxCharges, snapshot, forceAnyCurve)
    if active ~= true then return 0, true end
    if snapshot and snapshot.cooldownFade == false then return 0, true end
    if onGCD == true then return 0, true end
    local amount = GetCooldownDesaturation(button)
    if amount == 0 then return 0, true end
    local useRealCurve = forceAnyCurve ~= true and ((maxCharges ~= nil and maxCharges > 1) or IsItemAction(action))
    local curveAny, curveReal = EnsureNativeCoreCurves()
    if useRealCurve then
        if not (durationObject and durationObject.EvaluateRemainingDuration and curveReal) then return 0, true end
        return durationObject:EvaluateRemainingDuration(curveReal, 0), false
    end
    if not (durationObject and durationObject.EvaluateRemainingDuration and curveAny) then return 0, true end
    return durationObject:EvaluateRemainingDuration(curveAny, 0), false
end

local function NormalizeDiagnosticBarId(barId)
    barId = tostring(barId or ""):lower():match("^%s*(.-)%s*$") or ""
    if barId == "" then return nil end
    if barId == "main" or barId == "bar1" or barId == "1" then
        return "main"
    end
    local numberId = tonumber(barId) or tonumber(barId:match("^bar(%d+)$"))
    if numberId and numberId >= 2 and numberId <= 8 then
        return "bar" .. tostring(numberId)
    end
    return barId
end

local function DescribeDiagnosticBool(value)
    if IsSecretValue(value) then return "secret" end
    local result = FastBoolean(value, nil)
    if result == nil then
        return value == nil and "nil" or tostring(value)
    end
    return tostring(result)
end

local function SafeDiagnosticCall(func, ...)
    if type(func) ~= "function" then return nil, false end
    local ok, result = pcall(func, ...)
    if ok then return result, true end
    return nil, false
end

local function FindDirectActionButton(manager, target)
    if not (manager and target) then return false, nil, nil end
    local buttons, holders, count = manager:GetDirectActionButtonList()
    count = tonumber(count) or 0
    for index = 1, count do
        if buttons and buttons[index] == target then
            return true, index, holders and holders[index] or nil
        end
    end
    return false, nil, nil
end

local function BuildCooldownDiagnostic(manager, button, record)
    if not (manager and button) then return nil end
    local meta = GetButtonMeta(button)
    local actionBar = _G.C_ActionBar
    local action = GetButtonAction(button)
    local state = GetNativeCoreState(manager, button)
    local directKnown, directIndex, directHolder = FindDirectActionButton(manager, button)
    local holder = record and record.holder or directHolder or button:GetParent()
    local icon, iconSource = GetButtonIconDiagnostic(button)
    local hasActionRaw, hasActionOk = SafeDiagnosticCall(_G.HasAction, action)
    local hasAction = hasActionOk and FastBoolean(hasActionRaw, nil) or nil
    local cdInfo, cdOk = SafeDiagnosticCall(actionBar and actionBar.GetActionCooldown, action)
    local activeRaw = type(cdInfo) == "table" and cdInfo.isActive or nil
    local gcdRaw = type(cdInfo) == "table" and cdInfo.isOnGCD or nil
    local active = cdOk and FastBoolean(activeRaw, nil) or nil
    local onGCD = cdOk and FastBoolean(gcdRaw, nil) or nil
    local durationObject = active == true and SafeDiagnosticCall(actionBar and actionBar.GetActionCooldownDuration, action) or nil
    local chargeInfo = SafeDiagnosticCall(actionBar and actionBar.GetActionCharges, action)
    local maxCharges = type(chargeInfo) == "table" and SafeCooldownNumber(chargeInfo.maxCharges) or nil
    local stale = state.nativeDesaturationActive == true and active ~= true
    local holderShown = holder and holder.IsShown and holder:IsShown() == true or false
    local buttonShown = button.IsShown and button:IsShown() == true or false
    local iconShown = icon and icon.IsShown and icon:IsShown() == true or false
    return {
        barId = (meta and meta.barId) or button.yabBarId or (record and record.id) or "unknown",
        index = (meta and meta.index) or button.yabIndex or button.index or 0,
        name = button.GetName and button:GetName() or "unknown",
        action = action,
        directKnown = directKnown == true,
        directIndex = directIndex or 0,
        holderShown = holderShown,
        buttonShown = buttonShown,
        visibleByFilter = IsButtonVisible(button, holder),
        iconSource = iconSource,
        iconShown = iconShown,
        iconHasDesaturation = icon and type(icon.SetDesaturation) == "function" or false,
        iconHasDesaturated = icon and type(icon.SetDesaturated) == "function" or false,
        hasAction = hasActionOk and DescribeDiagnosticBool(hasActionRaw) or "api-error",
        cooldownActive = cdOk and DescribeDiagnosticBool(activeRaw) or "api-error",
        cooldownGCD = cdOk and DescribeDiagnosticBool(gcdRaw) or "api-error",
        durationObject = durationObject ~= nil,
        durationEvaluator = durationObject and type(durationObject.EvaluateRemainingDuration) == "function" or false,
        maxCharges = maxCharges or 0,
        stateMainActive = state.mainActive == true,
        stateChargeActive = state.chargeActive == true,
        stateDesaturationActive = state.nativeDesaturationActive == true,
        staleCandidate = stale == true,
    }
end

local function FormatCooldownDiagnostic(diag, prefix)
    if not diag then return nil end
    prefix = prefix or "YActionBar: cd"
    return string.format(
        "%s %s#%s action=%s active=%s gcd=%s stale=%s state(main=%s charge=%s desat=%s) shown(holder=%s button=%s icon=%s filter=%s) direct=%s:%s icon=%s desatAPI=%s/%s duration=%s eval=%s charges=%s",
        prefix,
        tostring(diag.barId),
        tostring(diag.index),
        tostring(diag.action or "nil"),
        tostring(diag.cooldownActive),
        tostring(diag.cooldownGCD),
        tostring(diag.staleCandidate),
        tostring(diag.stateMainActive),
        tostring(diag.stateChargeActive),
        tostring(diag.stateDesaturationActive),
        tostring(diag.holderShown),
        tostring(diag.buttonShown),
        tostring(diag.iconShown),
        tostring(diag.visibleByFilter),
        tostring(diag.directKnown),
        tostring(diag.directIndex or 0),
        tostring(diag.iconSource),
        tostring(diag.iconHasDesaturation),
        tostring(diag.iconHasDesaturated),
        tostring(diag.durationObject),
        tostring(diag.durationEvaluator),
        tostring(diag.maxCharges or 0)
    )
end

local function GetCachedActionInRange(manager, slot, snapshot)
    if not IsRangeSnapshotEnabled(snapshot) then return nil end
    local outOfRange = manager.rangeOut and manager.rangeOut[slot]
    if outOfRange == true then return false end
    if outOfRange == false then return true end
    return nil
end

local function ApplyActionTintState(manager, button, usable, noMana, inRange, snapshot, applyVisual)
    local state = manager.buttonStates and manager.buttonStates[button]
    if state then
        state.usable = usable
        state.noMana = noMana
        state.inRange = inRange
        state.rangeMode = snapshot and snapshot.rangeMode or state.rangeMode
    end
    if applyVisual ~= true or not (YAB.Visuals and YAB.Visuals.ApplyActionTintFast) then
        return 0
    end
    local outOfRange = IsRangeSnapshotEnabled(snapshot) and inRange == false
    return YAB.Visuals:ApplyActionTintFast(button, usable, noMana, outOfRange)
end

ApplyNativeCoreUsable = function(button, action)
    local fallbackBarId = button == _G.ExtraActionButton1 and "extraAction" or nil
    local snapshot = GetButtonConfigSnapshot(BarManager, button, fallbackBarId)
    local usable, noMana = YAB.Adapter:IsUsableAction(action)
    if usable == nil or noMana == nil then return 0 end
    local inRange = GetCachedActionInRange(BarManager, action, snapshot)
    return ApplyActionTintState(BarManager, button, usable, noMana, inRange, snapshot, true)
end

local function ApplyNativeCoreState(button, action, state)
    local current = type(_G.IsCurrentAction) == "function" and _G.IsCurrentAction(action) == true
    local repeating = type(_G.IsAutoRepeatAction) == "function" and _G.IsAutoRepeatAction(action) == true
    return BarManager:SetButtonCheckedState(button, current or repeating, state)
end

function BarManager:RefreshButtonCheckedState(button)
    if self.runtimeActive ~= true then return 0 end
    local visual = YAB.Visuals and YAB.Visuals.buttons[button]
    if not (visual and visual.nativeChecked and self.buttonConfigSnapshots[button]) then return 0 end
    local nativeState = GetNativeCoreState(self, button)
    nativeState.checked = button:GetChecked() == true
    if visual.isAction then
        local action = GetButtonAction(button)
        if action and type(_G.HasAction) == "function" and _G.HasAction(action) then
            return ApplyNativeCoreState(button, action, nativeState)
        end
    elseif visual.nativeSpecialKind == "stance" then
        local meta = GetButtonMeta(button)
        local _, active = YAB.Adapter:GetShapeshiftFormInfo(meta.index)
        return self:SetButtonCheckedState(button, active, nativeState)
    end
    return self:SetButtonCheckedState(button, false, nativeState)
end

local function ApplyNativeCoreIcon(button, action, state)
    local icon = GetButtonIcon(button)
    if not icon then return 0 end
    local texture = type(_G.GetActionTexture) == "function" and _G.GetActionTexture(action) or nil
    if IsSecretValue(texture) then return 0 end
    if texture == nil then
        return SetShownCached(state, "iconShown", icon, false)
    end
    local writes = 0
    if state.iconTexture ~= texture then
        state.iconTexture = texture
        icon:SetTexture(texture)
        writes = writes + 1
    end
    writes = writes + SetShownCached(state, "iconShown", icon, true)
    return writes
end

function BarManager:ClearRangeChecks()
    if YAB.Adapter and YAB.Adapter.SetActionRangeCheck then
        for slot in pairs(self.rangeCheckEnabled or {}) do
            YAB.Adapter:SetActionRangeCheck(slot, false)
        end
    end
    ClearTable(self.rangeSlots)
    ClearTable(self.nextRangeSlots)
    ClearTable(self.rangeCheckEnabled)
    ClearTable(self.rangeOut)
    self.rangeMapDirty = false
end

function BarManager:TrackRangeSlot(slot, snapshot)
    if not slot or not IsRangeSnapshotEnabled(snapshot) then return end
    self.rangeSlots[slot] = true
    if self.rangeCheckEnabled[slot] then return end
    if YAB.Adapter and YAB.Adapter.SetActionRangeCheck and YAB.Adapter:SetActionRangeCheck(slot, true) then
        self.rangeCheckEnabled[slot] = true
    end
end

function BarManager:RefreshAuraCache(db, force)
    if not AuraTimersEnabled(db) then
        ClearTable(self.auraLookup)
        self.auraDirty = false
        self.auraCacheReady = false
        return false
    end
    if not force and not self.auraDirty and self.auraCacheReady then
        return true
    end
    if YAB.Adapter and YAB.Adapter.BuildPlayerAuraLookup then
        YAB.Adapter:BuildPlayerAuraLookup(self.auraLookup)
    else
        ClearTable(self.auraLookup)
    end
    self.auraDirty = false
    self.auraCacheReady = true
    return true
end

function BarManager:ReconcileRangeSlots()
    if self.rangeMapDirty ~= true then return false end
    ClearTable(self.nextRangeSlots)
    for slot in pairs(self.slotButtons or {}) do
        local list = self.slotButtons and self.slotButtons[slot]
        local tracked = false
        if list then
            for index = 1, #list do
                local button = list[index]
                if button and IsRangeSnapshotEnabled(GetButtonConfigSnapshot(self, button)) then
                    tracked = true
                    break
                end
            end
        end
        if tracked then
            self.nextRangeSlots[slot] = true
            if not self.rangeCheckEnabled[slot] and YAB.Adapter and YAB.Adapter.SetActionRangeCheck and YAB.Adapter:SetActionRangeCheck(slot, true) then
                self.rangeCheckEnabled[slot] = true
            end
        end
    end
    for slot in pairs(self.rangeCheckEnabled or {}) do
        if not self.nextRangeSlots[slot] then
            if self.rangeCheckEnabled[slot] and YAB.Adapter and YAB.Adapter.SetActionRangeCheck then
                YAB.Adapter:SetActionRangeCheck(slot, false)
            end
            self.rangeCheckEnabled[slot] = nil
            self.rangeOut[slot] = nil
        end
    end
    ClearTable(self.rangeSlots)
    for slot in pairs(self.nextRangeSlots or {}) do
        self.rangeSlots[slot] = true
    end
    ClearTable(self.nextRangeSlots)
    self.rangeMapDirty = false
    self.rangeMapReconciles = (self.rangeMapReconciles or 0) + 1
    return true
end

function BarManager:ApplyAuraState(state, db)
    if not AuraTimersEnabled(db) then return end
    local aura = state.actionSpellID and self.auraLookup and self.auraLookup[state.actionSpellID]
    if not aura then return end
    state.auraActive = true
    state.auraStart = aura.start
    state.auraDuration = aura.duration
    state.auraExpirationTime = aura.expirationTime
end

function BarManager:GetButtonState(button)
    local state = self.buttonStates[button]
    if not state then
        state = ResetVisualState({})
        self.buttonStates[button] = state
    end
    return state
end

local function SafeSlotIdentityMatches(state, probe)
    return state.hasAction == probe.hasAction
        and state.actionType == probe.actionType
        and state.actionID == probe.actionID
        and state.actionSubType == probe.actionSubType
        and state.actionSpellID == probe.actionSpellID
        and state.procSpellID == probe.procSpellID
        and state.flyoutID == probe.flyoutID
end

local function IsTrustedUnchangedSlotIdentity(state, probe)
    if not (state and state.identityReady == true and probe and SafeSlotIdentityMatches(state, probe)) then
        return false
    end
    if state.hasAction ~= true then
        return state.actionType == nil
            and state.actionID == nil
            and state.actionSubType == nil
            and state.actionSpellID == nil
            and state.procSpellID == nil
            and state.flyoutID == nil
    end
    return state.actionType == "spell"
        and state.actionID ~= nil
        and state.actionSpellID == state.actionID
        and state.procSpellID == state.actionID
        and state.flyoutID == nil
        and not IsSecretValue(state.texture)
        and probe.texture ~= nil
        and not IsSecretValue(probe.texture)
end

function BarManager:TryRefreshUnchangedSlotIdentity(button, slot, probe, diagnostic)
    local state = self:GetButtonState(button)
    if state.slot ~= slot or not IsTrustedUnchangedSlotIdentity(state, probe) then
        if diagnostic then
            diagnostic.ineligibleButtons = (diagnostic.ineligibleButtons or 0) + 1
        end
        self.slotIdentityFallbacks = (self.slotIdentityFallbacks or 0) + 1
        return false
    end

    if diagnostic then
        diagnostic.eligibleButtons = (diagnostic.eligibleButtons or 0) + 1
        diagnostic.activeButtons = (diagnostic.activeButtons or 0) + 1
    end
    self.slotIdentityNarrowHits = (self.slotIdentityNarrowHits or 0) + 1

    if state.hasAction ~= true or state.texture == probe.texture then
        return true
    end
    state.texture = probe.texture
    local writes = UpdateButtonVisual(button, state, "identity") or 0
    if diagnostic then
        diagnostic.writes = (diagnostic.writes or 0) + writes
    end
    return true
end

function BarManager:ValidateSlotIdentityProbe(slot, probe, backend)
    local shadow = self.slotIdentityShadowScratch
    YAB.Adapter:ReadActionIdentity(slot, shadow, nil, backend)
    self.slotIdentityShadowComparisons = (self.slotIdentityShadowComparisons or 0) + 1
    local matches = not IsSecretValue(probe.texture)
        and not IsSecretValue(shadow.texture)
        and SafeSlotIdentityMatches(shadow, probe)
        and shadow.texture == probe.texture
    if not matches then
        self.slotIdentityShadowMismatches = (self.slotIdentityShadowMismatches or 0) + 1
        self.slotIdentityNarrowDisabled = true
    end
    return matches
end

local function AssistedCombatTickerCallback()
    if BarManager and BarManager.PollAssistedCombatSlots then
        BarManager:PollAssistedCombatSlots()
    end
end

function BarManager:CancelAssistedCombatTicker()
    local ticker = self.assistedCombatTicker
    if not ticker then return false end
    if type(ticker.Cancel) == "function" then
        pcall(ticker.Cancel, ticker)
    end
    self.assistedCombatTicker = nil
    self.assistedCombatTickerInterval = nil
    self.assistedCombatTickerStops = (self.assistedCombatTickerStops or 0) + 1
    return true
end

function BarManager:RefreshAssistedCombatTicker(forceRestart)
    local shouldRegister = YAB.Client.assistedCombat == true
        and (tonumber(self.assistedCombatSlotCount) or 0) > 0
        and self.runtimeActive == true
    local adapter = YAB.Adapter
    local cTimer = _G.C_Timer
    local interval = shouldRegister
        and adapter
        and adapter.GetAssistedCombatUpdateInterval
        and adapter:GetAssistedCombatUpdateInterval()
        or nil
    if not (shouldRegister and interval and cTimer and type(cTimer.NewTicker) == "function") then
        self:CancelAssistedCombatTicker()
        return false
    end
    if forceRestart ~= true
        and self.assistedCombatTicker
        and self.assistedCombatTickerInterval == interval then
        return true
    end
    self:CancelAssistedCombatTicker()
    local ok, ticker = pcall(cTimer.NewTicker, interval, AssistedCombatTickerCallback)
    if not (ok and ticker) then return false end
    self.assistedCombatTicker = ticker
    self.assistedCombatTickerInterval = interval
    self.assistedCombatTickerStarts = (self.assistedCombatTickerStarts or 0) + 1
    return true
end

function BarManager:IsAssistedCombatSlotVisible(slot)
    local list = self.slotButtons and self.slotButtons[slot]
    if not list then return false end
    for index = 1, #list do
        local button = list[index]
        local meta = GetButtonMeta(button)
        if IsButtonVisible(button, meta and meta.holder) then return true end
    end
    return false
end

function BarManager:PollAssistedCombatSlots()
    local slotCounts = self.assistedCombatSlotCounts
    local adapter = YAB.Adapter
    if self.runtimeActive ~= true or not slotCounts
        or not (adapter and adapter.GetAssistedCombatNextSpell
            and adapter.ForceUpdateAssistedCombatAction) then
        self:CancelAssistedCombatTicker()
        return 0, 0
    end
    self.assistedCombatTickerTicks = (self.assistedCombatTickerTicks or 0) + 1
    self.assistedCombatNextSpellPolls = (self.assistedCombatNextSpellPolls or 0) + 1
    local nextSpellID, available = adapter:GetAssistedCombatNextSpell()
    if available ~= true then
        self.assistedCombatNextSpellFailures = (self.assistedCombatNextSpellFailures or 0) + 1
        return 0, 0
    end
    if self.assistedCombatNextSpellReady ~= true
        or self.assistedCombatNextSpellID ~= nextSpellID then
        self.assistedCombatNextSpellReady = true
        self.assistedCombatNextSpellID = nextSpellID
        self.assistedCombatNextSpellGeneration = (self.assistedCombatNextSpellGeneration or 0) + 1
        self.assistedCombatNextSpellChanges = (self.assistedCombatNextSpellChanges or 0) + 1
    end
    local generation = self.assistedCombatNextSpellGeneration or 0
    local slotGenerations = self.assistedCombatSlotGenerations
    if not slotGenerations then
        slotGenerations = {}
        self.assistedCombatSlotGenerations = slotGenerations
    end
    local forced, queued = 0, 0
    for slot in pairs(slotCounts) do
        if slotGenerations[slot] ~= generation then
            self.assistedCombatVisibleSlotChecks = (self.assistedCombatVisibleSlotChecks or 0) + 1
            if self:IsAssistedCombatSlotVisible(slot)
                and adapter:ForceUpdateAssistedCombatAction(slot) == true then
                slotGenerations[slot] = generation
                forced = forced + 1
                self.assistedCombatForceUpdates = (self.assistedCombatForceUpdates or 0) + 1
                if self.dirtySlots[slot] ~= "identity" and self.dirtySlots[slot] ~= "full" then
                    self:QueueSlotRefresh(slot, "assisted combat forced update", "identity")
                    queued = queued + 1
                    self.assistedCombatRefreshQueues = (self.assistedCombatRefreshQueues or 0) + 1
                end
            end
        end
    end
    return forced, queued
end

function BarManager:SetButtonAssistedCombatSlot(button, slot, active)
    if not button then return false end
    local buttonSlots = self.assistedCombatButtonSlots
    local oldSlot = buttonSlots and buttonSlots[button]
    local targetSlot = active == true and tonumber(slot) or nil
    if oldSlot == targetSlot then return false end

    local slotCounts = self.assistedCombatSlotCounts
    if oldSlot and slotCounts then
        local count = (tonumber(slotCounts[oldSlot]) or 1) - 1
        if count > 0 then
            slotCounts[oldSlot] = count
        else
            slotCounts[oldSlot] = nil
            if self.assistedCombatSlotGenerations then
                self.assistedCombatSlotGenerations[oldSlot] = nil
            end
            self.assistedCombatSlotCount = math.max((tonumber(self.assistedCombatSlotCount) or 1) - 1, 0)
        end
        buttonSlots[button] = nil
    end

    if targetSlot then
        if not buttonSlots then
            buttonSlots = setmetatable({}, { __mode = "k" })
            self.assistedCombatButtonSlots = buttonSlots
        end
        if not slotCounts then
            slotCounts = {}
            self.assistedCombatSlotCounts = slotCounts
        end
        if not slotCounts[targetSlot] then
            self.assistedCombatSlotCount = (tonumber(self.assistedCombatSlotCount) or 0) + 1
            slotCounts[targetSlot] = 1
            if self.assistedCombatSlotGenerations then
                self.assistedCombatSlotGenerations[targetSlot] = nil
            end
        else
            slotCounts[targetSlot] = slotCounts[targetSlot] + 1
        end
        buttonSlots[button] = targetSlot
    elseif (tonumber(self.assistedCombatSlotCount) or 0) == 0 then
        self.assistedCombatButtonSlots = nil
        self.assistedCombatSlotCounts = nil
    end

    self:RefreshAssistedCombatTicker()
    return true
end

function BarManager:ClearAssistedCombatTracking()
    self:CancelAssistedCombatTicker()
    self.assistedCombatButtonSlots = nil
    self.assistedCombatSlotCounts = nil
    self.assistedCombatSlotGenerations = nil
    self.assistedCombatSlotCount = 0
    self.assistedCombatNextSpellReady = false
    self.assistedCombatNextSpellID = nil
    self.assistedCombatNextSpellGeneration = 0
end

function BarManager:UnmapButtonSlot(button)
    if YAB.Visuals and YAB.Visuals.StopRankUpgrade then YAB.Visuals:StopRankUpgrade(button) end
    self:SetButtonAssistedCombatSlot(button, nil, false)
    local oldSlot = self.buttonSlots[button]
    if not oldSlot then return end
    local list = self.slotButtons[oldSlot]
    if list then
        for index = #list, 1, -1 do
            if list[index] == button then
                table.remove(list, index)
                break
            end
        end
        if #list == 0 then
            self.slotButtons[oldSlot] = nil
        end
    end
    self.buttonSlots[button] = nil
    self.rangeMapDirty = true
end

function BarManager:MapButtonSlot(button, slot)
    if not button or not slot then return end
    local oldSlot = self.buttonSlots[button]
    if oldSlot == slot then return end
    self:UnmapButtonSlot(button)
    local list = self.slotButtons[slot]
    if not list then
        list = {}
        self.slotButtons[slot] = list
    end
    list[#list + 1] = button
    self.buttonSlots[button] = slot
    self.rangeMapDirty = true
end

function BarManager:ClearSlotMap()
    self:InvalidateProcIndex("slot map clear", "full")
    ClearTable(self.slotButtons)
    ClearTable(self.buttonSlots)
    self.rangeMapDirty = true
end

function BarManager:UpdateProcGlowCacheSize()
end

function BarManager:InvalidateProcIndex(reason, kind)
    kind = kind or "full"
    local currentGeneration = tonumber(self.actionIdentityGeneration) or 0
    local baseWasComplete = self.procIndexCompleteGeneration == currentGeneration
    local deltaWasEligible = self.procIndexDeltaCompleteEligible == true
        and self.procIndexDeltaGeneration == currentGeneration
    local nextGeneration = currentGeneration + 1
    self.actionIdentityGeneration = nextGeneration
    self.procIndexMode = "shadow"
    if kind == "delta" then
        self.procIndexDeltaCompleteEligible = baseWasComplete or deltaWasEligible
    else
        self.procIndexDeltaCompleteEligible = false
    end
    self.procIndexDeltaGeneration = nextGeneration
    self.procIndexLastInvalidationReason = reason
    return nextGeneration
end

function BarManager:MarkProcIndexComplete(generation)
    generation = tonumber(generation)
    if not generation or generation ~= self.actionIdentityGeneration then return false end
    self.procIndexCompleteGeneration = generation
    self.procIndexDeltaCompleteEligible = false
    self.procIndexDeltaGeneration = generation
    return true
end

function BarManager:ClearProcIndex()
    ClearTable(self.procButtonsBySpellID)
    ClearTable(self.procButtonsByFlyoutID)
end

function BarManager:TrackActiveProcButton(button, shown)
    if not button then return end
    if shown then
        self.activeProcButtons[button] = true
    else
        self.activeProcButtons[button] = nil
    end
end

function BarManager:UnmapButtonProc(button, state, preserveActive)
    state = state or (button and self.buttonStates and self.buttonStates[button])
    if not (button and state) then return end
    RemoveButtonFromListMap(self.procButtonsBySpellID, state.procSpellID, button)
    RemoveButtonFromListMap(self.procButtonsByFlyoutID, state.flyoutID, button)
    if preserveActive ~= true then
        self.activeProcButtons[button] = nil
    end
    self:UpdateProcGlowCacheSize()
end

function BarManager:MapButtonProc(button, state)
    if not (button and state and state.hasAction) then
        self:UpdateProcGlowCacheSize()
        return
    end
    AddButtonToListMap(self.procButtonsBySpellID, state.procSpellID, button)
    AddButtonToListMap(self.procButtonsByFlyoutID, state.flyoutID, button)
    self:UpdateProcGlowCacheSize()
end

function BarManager:ClearProcGlowTracking()
    self:InvalidateProcIndex("proc tracking clear", "full")
    self:ClearProcIndex()
    ClearTable(self.activeProcButtons)
    ClearTable(self.activeProcSpellIDs)
end

function BarManager:ForEachActionButton(callback)
    if type(callback) ~= "function" then return end
    for _, record in pairs(self.bars or {}) do
        if record and record.kind == "action" and record.buttons then
            local holder = record.holder
            local visible = not (holder and holder.IsShown) or holder:IsShown()
            if visible then
                for index = 1, #record.buttons do
                    local button = record.buttons[index]
                    if button then
                        callback(button, record, index)
                    end
                end
            end
        end
    end
end

function BarManager:MarkDirectActionListDirty()
    self.directActionListDirty = true
    self.actionHotRecordsDirty = true
end

function BarManager:HasOrdinaryActionButtons()
    for _, record in pairs(self.bars or {}) do
        if record and record.kind == "action" and record.buttons and #record.buttons > 0 then
            return true
        end
    end
    return false
end

function BarManager:RebuildDirectActionButtonList()
    local buttons = self.directActionButtons or {}
    local holders = self.directActionHolders or {}
    self.directActionButtons = buttons
    self.directActionHolders = holders
    ClearTable(buttons)
    ClearTable(holders)

    local count = 0
    for _, record in pairs(self.bars or {}) do
        if record and record.kind == "action" and record.buttons then
            local holder = record.holder
            local visible = not (holder and holder.IsShown) or holder:IsShown()
            if visible then
                for index = 1, #record.buttons do
                    local button = record.buttons[index]
                    if button then
                        count = count + 1
                        buttons[count] = button
                        holders[count] = holder
                    end
                end
            end
        end
    end
    self.directActionButtonCount = count
    self.directActionListDirty = false
    self.directActionListRebuilds = (self.directActionListRebuilds or 0) + 1
    return buttons, holders, count
end

function BarManager:GetDirectActionButtonList()
    if self.directActionListDirty ~= false or not self.directActionButtons or not self.directActionHolders then
        return self:RebuildDirectActionButtonList()
    end
    return self.directActionButtons, self.directActionHolders, self.directActionButtonCount or 0
end

local function ReadHotRecordMaxCharges(backend, action)
    if not (backend and backend.getChargeInfo and action) then return nil end
    if backend.mode == "retail-duration" then
        local chargeInfo = backend.getChargeInfo(action)
        local maxCharges = type(chargeInfo) == "table" and chargeInfo.maxCharges or nil
        return type(maxCharges) == "number" and maxCharges or nil
    end
    local _, maxCharges = backend.getChargeInfo(action)
    return SafeCooldownNumber(maxCharges)
end

local function PopulateActionHotRecord(manager, record, button, holder, backend, actionOverride, snapshotOverride)
    record.button = button
    record.holder = holder
    record.action = actionOverride or manager.buttonSlots[button] or GetButtonAction(button)
    record.state = manager.buttonStates[button]
    record.nativeState = GetNativeCoreState(manager, button)
    InstallNativeCoreCooldownDone(button)
    record.cooldown = GetButtonCooldown(button)
    record.chargeCooldown = GetButtonChargeCooldown(button)
    record.icon = GetButtonIcon(button)
    record.snapshot = snapshotOverride or GetButtonConfigSnapshot(manager, button)
    local state = record.state
    if state and state.identityReady == true then
        record.hasAction = state.hasAction == true
        record.actionType = state.actionType
    else
        record.hasAction = backend and backend.hasAction and backend.hasAction(record.action) == true or false
        record.actionType = state and state.actionType or nil
    end
    local maxCharges = record.hasAction and ReadHotRecordMaxCharges(backend, record.action) or nil
    record.maxCharges = maxCharges
    record.hasMultipleCharges = maxCharges ~= nil and maxCharges > 1
    record.isItem = record.actionType == "item"
    record.isMacro = record.actionType == "macro"
    record.cooldownFade = not record.snapshot or record.snapshot.cooldownFade ~= false
    record.showCounts = record.snapshot and record.snapshot.showCounts == true
    record.identityGeneration = manager.actionIdentityGeneration or 0
    record.configGeneration = record.snapshot and record.snapshot.revision or 0
    return record
end

local function RemoveIndexedHotRecord(records, count, target)
    for index = 1, count do
        if records[index] == target then
            for move = index, count - 1 do
                records[move] = records[move + 1]
            end
            records[count] = nil
            return count - 1
        end
    end
    return count
end

local function HotRecordNeedsCount(record)
    local needsCount = record.hasAction and record.showCounts
        and (record.hasMultipleCharges or record.isItem or record.isMacro or record.actionType == nil)
    local nativeState = record.nativeState
    if not needsCount and nativeState
        and (nativeState.countTextSecret == true
            or (type(nativeState.countText) == "string" and nativeState.countText ~= "")) then
        needsCount = true
    end
    return needsCount == true
end

local function SyncActionHotClassification(manager, record)
    local nativeState = record.nativeState
    local needsCharge = (record.hasAction and record.hasMultipleCharges)
        or (nativeState and nativeState.chargeActive == true)
    if record.inChargeIndex == true and not needsCharge then
        manager.chargeHotRecordCount = RemoveIndexedHotRecord(
            manager.chargeHotRecords,
            manager.chargeHotRecordCount or 0,
            record
        )
        record.inChargeIndex = false
    elseif record.inChargeIndex ~= true and needsCharge then
        local count = (manager.chargeHotRecordCount or 0) + 1
        manager.chargeHotRecords[count] = record
        manager.chargeHotRecordCount = count
        record.inChargeIndex = true
    end

    local needsCount = HotRecordNeedsCount(record)
    if record.inCountIndex == true and not needsCount then
        manager.countHotRecordCount = RemoveIndexedHotRecord(
            manager.countHotRecords,
            manager.countHotRecordCount or 0,
            record
        )
        record.inCountIndex = false
    elseif record.inCountIndex ~= true and needsCount then
        local count = (manager.countHotRecordCount or 0) + 1
        manager.countHotRecords[count] = record
        manager.countHotRecordCount = count
        record.inCountIndex = true
    end
end

function BarManager:RefreshActionHotRecord(button, action, snapshot, backend)
    if not button then return nil end
    backend = backend or self.actionHotBackend or self:PrepareActionHotBackend()
    local record = self.actionHotRecordsByButton[button]
    if not record then
        record = {}
        self.actionHotRecordsByButton[button] = record
    end
    local holder
    for index = 1, self.directActionButtonCount or 0 do
        if self.directActionButtons[index] == button then
            holder = self.directActionHolders[index]
            break
        end
    end
    PopulateActionHotRecord(self, record, button, holder, backend, action, snapshot)
    if self.actionHotRecordsDirty ~= true then
        SyncActionHotClassification(self, record)
    end
    return record
end

function BarManager:RebuildActionHotRecords()
    local buttons, holders, directCount = self:GetDirectActionButtonList()
    local records = self.actionHotRecords
    local chargeRecords = self.chargeHotRecords
    local countRecords = self.countHotRecords
    for index = 1, self.actionHotRecordCount or 0 do
        local record = records[index]
        if record then
            record.inActionIndex = false
            record.inChargeIndex = false
            record.inCountIndex = false
        end
    end
    ClearTable(records)
    ClearTable(chargeRecords)
    ClearTable(countRecords)
    local backend = self.actionHotBackend
    if self.actionHotBackendReady ~= true then
        backend = self:PrepareActionHotBackend()
    end
    local recordCount, chargeCount, countCount = 0, 0, 0
    directCount = tonumber(directCount) or 0
    for index = 1, directCount do
        local button = buttons[index]
        local holder = holders and holders[index]
        if button and IsButtonVisible(button, holder) then
            local record = self.actionHotRecordsByButton[button]
            if not record then
                record = {}
                self.actionHotRecordsByButton[button] = record
            end
            PopulateActionHotRecord(self, record, button, holder, backend)
            recordCount = recordCount + 1
            records[recordCount] = record
            record.inActionIndex = true
            local nativeState = record.nativeState
            if (record.hasAction and record.hasMultipleCharges)
                or (nativeState and nativeState.chargeActive == true) then
                chargeCount = chargeCount + 1
                chargeRecords[chargeCount] = record
                record.inChargeIndex = true
            end
            if HotRecordNeedsCount(record) then
                countCount = countCount + 1
                countRecords[countCount] = record
                record.inCountIndex = true
            end
        end
    end
    self.actionHotRecordCount = recordCount
    self.chargeHotRecordCount = chargeCount
    self.countHotRecordCount = countCount
    self.actionHotRecordsDirty = false
    return records, recordCount
end

function BarManager:GetActionHotRecords()
    if self.actionHotRecordsDirty ~= false then
        return self:RebuildActionHotRecords()
    end
    return self.actionHotRecords, self.actionHotRecordCount or 0
end

function BarManager:RebuildProcIndex(spellID, legacyCandidates)
    local generation = self.actionIdentityGeneration
    self.procIndexRebuilds = (self.procIndexRebuilds or 0) + 1
    self:ClearProcIndex()
    if legacyCandidates then ClearTable(legacyCandidates) end
    if not (YAB.Adapter and YAB.Adapter.ReadActionProcIdentity and YAB.Adapter.GetActionSlot) then
        return false
    end

    local db = GetDB()
    local pageState = self:GetPageState(false)
    for barId, record in pairs(self.bars or {}) do
        if record and record.kind == "action" and record.buttons then
            local config = db and GetBarConfig(db, barId)
            local page = self:GetActionPageForRecord(barId, record, config, pageState)
            local holder = record.holder
            local visible = not (holder and holder.IsShown) or holder:IsShown()
            for index = 1, #record.buttons do
                local button = record.buttons[index]
                if button then
                    local meta = GetButtonMeta(button)
                    local actionIndex = (meta and meta.index) or index
                    local slot = self:GetRecordButtonActionSlot(barId, button, page, actionIndex)
                    self:MapButtonSlot(button, slot)
                    local state = self.buttonStates[button]
                    if not state then
                        state = {}
                        self.buttonStates[button] = state
                    end
                    YAB.Adapter:ReadActionProcIdentity(slot, state)
                    self:MapButtonProc(button, state)
                    if legacyCandidates and visible and self:ButtonMatchesProcSpell(state, spellID) then
                        legacyCandidates[button] = true
                    end
                end
            end
        end
    end
    if self.actionIdentityGeneration ~= generation then return false end
    return self:MarkProcIndexComplete(generation)
end

function BarManager:RefreshButtonProcIdentity(button, currentSlot)
    if not (button and YAB.Adapter and YAB.Adapter.ReadActionProcIdentity) then
        return button and self.buttonStates and self.buttonStates[button] or nil
    end
    local slot = currentSlot or (self.buttonSlots and self.buttonSlots[button])
    if not slot then
        return self.buttonStates and self.buttonStates[button] or nil
    end
    if self.buttonSlots[button] ~= slot then
        self:MapButtonSlot(button, slot)
    end
    local state = self.buttonStates[button]
    if not state then
        state = {}
        self.buttonStates[button] = state
    end
    self:UnmapButtonProc(button, state, true)
    YAB.Adapter:ReadActionProcIdentity(slot, state)
    self:MapButtonProc(button, state)
    return state
end

function BarManager:ButtonMatchesProcSpell(state, spellID)
    if not (state and spellID) then return false end
    if state.procSpellID == spellID then return true end
    if state.flyoutID and YAB.Adapter and YAB.Adapter.IsFlyoutProcGlowFor then
        return YAB.Adapter:IsFlyoutProcGlowFor(state.flyoutID, spellID)
    end
    return false
end

function BarManager:IsButtonProcOverlayed(state)
    if not state or not state.hasAction then return false end
    if state.procSpellID and YAB.Adapter and YAB.Adapter.IsProcSpellOverlayed then
        local shown = YAB.Adapter:IsProcSpellOverlayed(state.procSpellID)
        if shown then
            self.activeProcSpellIDs[state.procSpellID] = true
        end
        return shown == true
    end
    if state.flyoutID and YAB.Adapter and YAB.Adapter.IsFlyoutProcGlowFor then
        for spellID in pairs(self.activeProcSpellIDs or {}) do
            if YAB.Adapter:IsFlyoutProcGlowFor(state.flyoutID, spellID) then
                return true
            end
        end
    end
    return false
end

function BarManager:ResyncButtonProcGlow(button, state)
    if not (button and state) then return end
    local shown = self:IsButtonProcOverlayed(state)
    state.procGlow = shown == true
    self:TrackActiveProcButton(button, state.procGlow)
end

function BarManager:SetButtonProcGlow(button, shown)
    if not button then return 0 end
    local state = self.buttonStates and self.buttonStates[button]
    if state then
        state.procGlow = shown == true
    end
    self:TrackActiveProcButton(button, shown == true)
    if YAB.Visuals and YAB.Visuals.SetProcGlow then
        return YAB.Visuals:SetProcGlow(button, shown == true) or 0
    end
    return 0
end

function BarManager:IsIndexedProcButtonVisible(button)
    if not button then return false end
    local meta = GetButtonMeta(button)
    local barId = meta and meta.barId
    local index = meta and meta.index
    local record = barId and self.bars and self.bars[barId]
    if not (record and record.kind == "action" and record.buttons and record.buttons[index] == button) then
        return false
    end
    local holder = record.holder
    return not (holder and holder.IsShown) or holder:IsShown()
end

function BarManager:CollectIndexedProcCandidates(spellID, candidates)
    candidates = candidates or self.procGlowIndexedCandidates
    ClearTable(candidates)
    local count = 0
    local direct = self.procButtonsBySpellID and self.procButtonsBySpellID[spellID]
    for index = 1, #(direct or {}) do
        local button = direct[index]
        if not candidates[button] and self:IsIndexedProcButtonVisible(button) then
            candidates[button] = true
            count = count + 1
        end
    end
    if YAB.Adapter and YAB.Adapter.IsFlyoutProcGlowFor then
        for flyoutID, buttons in pairs(self.procButtonsByFlyoutID or {}) do
            if YAB.Adapter:IsFlyoutProcGlowFor(flyoutID, spellID) then
                for index = 1, #buttons do
                    local button = buttons[index]
                    if not candidates[button] and self:IsIndexedProcButtonVisible(button) then
                        candidates[button] = true
                        count = count + 1
                    end
                end
            end
        end
    end
    return candidates, count
end

function BarManager:ReconcileProcCandidateUsable(button, generation, diagnostic)
    if YAB.Client.directUsableRefresh ~= true or not button
        or not (YAB.Adapter and YAB.Adapter.IsUsableAction) then
        return 0
    end
    local action = self.buttonSlots and self.buttonSlots[button]
    if not action then return 0 end
    local usable, noMana = self:ReadActionUsableForReconcile(action, generation, diagnostic)
    if usable == nil or noMana == nil then return 0 end
    local snapshot = GetButtonConfigSnapshot(self, button)
    local inRange = GetCachedActionInRange(self, action, snapshot)
    return ApplyActionTintState(self, button, usable, noMana, inRange, snapshot, true)
end

function BarManager:ApplyProcCandidateSet(candidates, shown, diagnostic)
    local touched, writes = 0, 0
    local usableGeneration
    if shown == true and YAB.Client.directUsableRefresh == true
        and YAB.Adapter and YAB.Adapter.IsUsableAction then
        usableGeneration = (self.usableReconcileGeneration or 0) + 1
        self.usableReconcileGeneration = usableGeneration
    end
    for button in pairs(candidates or {}) do
        touched = touched + 1
        writes = writes + self:SetButtonProcGlow(button, shown == true)
        if usableGeneration then
            writes = writes + self:ReconcileProcCandidateUsable(button, usableGeneration, diagnostic)
        end
    end
    return touched, writes
end

function BarManager:CollectLegacyProcCandidates(spellID, candidates)
    candidates = candidates or self.procGlowLegacyCandidates
    ClearTable(candidates)
    local count = 0
    local db = GetDB()
    local pageState = self:GetPageState(false)
    for barId, record in pairs(self.bars or {}) do
        if record and record.kind == "action" and record.buttons then
            local holder = record.holder
            local visible = not (holder and holder.IsShown) or holder:IsShown()
            if visible then
                local config = db and GetBarConfig(db, barId)
                local page = self:GetActionPageForRecord(barId, record, config, pageState)
                for index = 1, #record.buttons do
                    local button = record.buttons[index]
                    if button then
                        local meta = GetButtonMeta(button)
                        local actionIndex = (meta and meta.index) or index
                        local slot = self:GetRecordButtonActionSlot(barId, button, page, actionIndex)
                        local state = self:RefreshButtonProcIdentity(button, slot)
                        if self:ButtonMatchesProcSpell(state, spellID) then
                            candidates[button] = true
                            count = count + 1
                        end
                    end
                end
            end
        end
    end
    return candidates, count
end

function BarManager:CountProcCandidateMismatches(indexed, legacy)
    local mismatch = 0
    for button in pairs(indexed or {}) do
        if not legacy[button] then mismatch = mismatch + 1 end
    end
    for button in pairs(legacy or {}) do
        if not indexed[button] then mismatch = mismatch + 1 end
    end
    return mismatch
end

function BarManager:IsButtonCoveredByActiveProc(state)
    if not (state and state.hasAction) then return false end
    if state.procSpellID and self.activeProcSpellIDs[state.procSpellID] then
        return true
    end
    if state.flyoutID and YAB.Adapter and YAB.Adapter.IsFlyoutProcGlowFor then
        for activeSpellID in pairs(self.activeProcSpellIDs or {}) do
            if YAB.Adapter:IsFlyoutProcGlowFor(state.flyoutID, activeSpellID) then
                return true
            end
        end
    end
    return false
end

function BarManager:ApplyProcGlowForSpell(spellID, shown, diagnostic)
    if not spellID then return 0, 0 end
    if shown == true then
        local rebuilt = false
        if self.procIndexCompleteGeneration ~= self.actionIdentityGeneration then
            rebuilt = self:RebuildProcIndex(spellID, self.procGlowLegacyCandidates) == true
        end
        if self.procIndexCompleteGeneration == self.actionIdentityGeneration
            and self.procIndexMode == "shadow" then
            local shadowGeneration = self.actionIdentityGeneration
            local indexed = self:CollectIndexedProcCandidates(spellID, self.procGlowIndexedCandidates)
            local legacy = self.procGlowLegacyCandidates
            if not rebuilt then
                legacy = self:CollectLegacyProcCandidates(spellID, legacy)
            end
            local mismatch = self:CountProcCandidateMismatches(indexed, legacy)
            self.procIndexShadowComparisons = (self.procIndexShadowComparisons or 0) + 1
            local touched, writes = self:ApplyProcCandidateSet(legacy, true, diagnostic)
            local generationStable = self.actionIdentityGeneration == shadowGeneration
                and self.procIndexCompleteGeneration == shadowGeneration
            if not generationStable then
                self.procIndexMode = "shadow"
                self.procIndexFallbacks = (self.procIndexFallbacks or 0) + 1
            elseif mismatch == 0 then
                self.procIndexMode = "production"
            else
                self.procIndexMismatches = (self.procIndexMismatches or 0) + mismatch
                self.procIndexFallbacks = (self.procIndexFallbacks or 0) + 1
                self:InvalidateProcIndex("proc shadow mismatch", "full")
            end
            ClearTable(indexed)
            ClearTable(legacy)
            return touched, writes
        end
        if self.procIndexMode == "production"
            and self.procIndexCompleteGeneration == self.actionIdentityGeneration then
            local candidates, count = self:CollectIndexedProcCandidates(spellID, self.procGlowIndexedCandidates)
            self.procIndexIndexedShows = (self.procIndexIndexedShows or 0) + 1
            if count == 0 then
                self.procIndexLegalEmptyShows = (self.procIndexLegalEmptyShows or 0) + 1
                return 0, 0
            end
            return self:ApplyProcCandidateSet(candidates, true, diagnostic)
        end
        self.procIndexFallbacks = (self.procIndexFallbacks or 0) + 1
        local legacy = self.procGlowLegacyCandidates
        if not rebuilt then
            legacy = self:CollectLegacyProcCandidates(spellID, legacy)
        end
        local touched, writes = self:ApplyProcCandidateSet(legacy, true, diagnostic)
        ClearTable(legacy)
        return touched, writes
    end

    local touched, writes = 0, 0
    local usableGeneration
    local scratch = self.procGlowActiveScratch
    ClearTable(scratch)
    for button in pairs(self.activeProcButtons or {}) do
        scratch[#scratch + 1] = button
    end
    for index = 1, #scratch do
        local button = scratch[index]
        local state = self.buttonStates and self.buttonStates[button]
        if not self:IsButtonCoveredByActiveProc(state) then
            touched = touched + 1
            writes = writes + self:SetButtonProcGlow(button, false)
            if YAB.Client.directUsableRefresh == true and YAB.Adapter and YAB.Adapter.IsUsableAction then
                if not usableGeneration then
                    usableGeneration = (self.usableReconcileGeneration or 0) + 1
                    self.usableReconcileGeneration = usableGeneration
                end
                writes = writes + self:ReconcileProcCandidateUsable(button, usableGeneration, diagnostic)
            end
        end
        scratch[index] = nil
    end
    return touched, writes
end

function BarManager:HandleProcGlowEvent(event, spellID, diagnostic)
    local id = YAB.Adapter and YAB.Adapter.NormalizeSpellID and YAB.Adapter:NormalizeSpellID(spellID)
    if not id then
        return
    end
    self:MarkReason(event, "glow", false)

    local shown = event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
    if shown then
        self.activeProcSpellIDs[id] = true
    else
        self.activeProcSpellIDs[id] = nil
    end

    local touched, writes = self:ApplyProcGlowForSpell(id, shown, diagnostic)
    if diagnostic then
        diagnostic.buttons = diagnostic.buttons + (touched or 0)
        diagnostic.writes = diagnostic.writes + (writes or 0)
    end
    return touched, writes
end

function BarManager:ProcCaptureBool(value)
    if value == nil then return "unknown" end
    return value == true and "true" or "false"
end

function BarManager:IsProcCaptureSecretValue(value)
    if not (Security and type(Security.IsSecretValue) == "function") then return false end
    local ok, result = pcall(Security.IsSecretValue, value)
    return ok and result == true
end

function BarManager:ReadProcCaptureShown(frame)
    if not frame then return false end
    if type(frame.IsShown) ~= "function" then return nil end
    local ok, shown = pcall(frame.IsShown, frame)
    if not ok or self:IsProcCaptureSecretValue(shown) or type(shown) ~= "boolean" then return nil end
    return shown
end

function BarManager:ReadProcCaptureColorStatus(icon, visual)
    if not (icon and type(icon.GetVertexColor) == "function" and visual and type(visual.lastColor) == "table") then
        return "unknown"
    end
    local ok, r, g, b, a = pcall(icon.GetVertexColor, icon)
    if not ok or self:IsProcCaptureSecretValue(r) or self:IsProcCaptureSecretValue(g)
        or self:IsProcCaptureSecretValue(b) or self:IsProcCaptureSecretValue(a) then
        return "unknown"
    end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return "unknown"
    end
    if a == nil then a = 1 end
    if type(a) ~= "number" then return "unknown" end
    local expected = visual.lastColor
    local er = expected[1] or expected.r
    local eg = expected[2] or expected.g
    local eb = expected[3] or expected.b
    local ea = expected[4]
    if ea == nil then ea = expected.a end
    if ea == nil then ea = 1 end
    if type(er) ~= "number" or type(eg) ~= "number" or type(eb) ~= "number" or type(ea) ~= "number" then
        return "unknown"
    end
    local epsilon = 0.01
    return math.abs(r - er) <= epsilon
        and math.abs(g - eg) <= epsilon
        and math.abs(b - eb) <= epsilon
        and math.abs(a - ea) <= epsilon
        and "match" or "mismatch"
end

function BarManager:GetProcCaptureButtonKey(button)
    local meta = GetButtonMeta(button)
    if not meta then return "unknown" end
    return tostring(meta.barId or "unknown") .. "." .. tostring(meta.index or "?")
end

function BarManager:PrimeProcCaptureOverlayBaseline()
    local baseline = self.procCaptureOverlayBaseline
    ClearTable(baseline)
    if self.actionHotRecordsDirty ~= false then return false end
    local adapter = YAB.Adapter
    for index = 1, self.actionHotRecordCount or 0 do
        local record = self.actionHotRecords[index]
        local button = record and record.button
        local state = record and (record.state or (self.buttonStates and self.buttonStates[button]))
        if record and button and record.hasAction == true and state
            and IsButtonVisible(button, record.holder)
            and state.procSpellID ~= nil and adapter and adapter.IsProcSpellOverlayed
            and adapter:IsProcSpellOverlayed(state.procSpellID) == true then
            baseline[button] = true
        end
    end
    return true
end

function BarManager:ClearProcCaptureOverlayBaseline()
    ClearTable(self.procCaptureOverlayBaseline)
end

function BarManager:CancelProcCaptureFreezeTimer()
    local timer = self.procCaptureFreezeTimer
    self.procCaptureFreezeTimer = nil
    if timer and type(timer.Cancel) == "function" then
        pcall(timer.Cancel, timer)
    end
end

function BarManager.OnProcCaptureFreezeTimer()
    BarManager.procCaptureFreezeTimer = nil
    if HotDiagnostics and HotDiagnostics.FreezeProcCapture then
        HotDiagnostics:FreezeProcCapture("post-window")
    end
end

function BarManager:ScheduleProcCaptureFreeze()
    self:CancelProcCaptureFreezeTimer()
    local timerAPI = _G.C_Timer
    if not (timerAPI and type(timerAPI.NewTimer) == "function") then
        if HotDiagnostics and HotDiagnostics.FreezeProcCapture then
            HotDiagnostics:FreezeProcCapture("timer-unavailable")
        end
        return false
    end
    self.procCaptureFreezeTimer = timerAPI.NewTimer(1, BarManager.OnProcCaptureFreezeTimer)
    if not self.procCaptureFreezeTimer then
        if HotDiagnostics and HotDiagnostics.FreezeProcCapture then
            HotDiagnostics:FreezeProcCapture("timer-unavailable")
        end
        return false
    end
    return true
end

function BarManager:TraceProcCapture(event, phase, eventSpellID)
    local capture = HotDiagnostics
    if not (capture and capture.IsProcCaptureActive and capture:IsProcCaptureActive()) then return false end
    local recordsReady = self.actionHotRecordsDirty == false
    local records = recordsReady and self.actionHotRecords or nil
    local recordCount = recordsReady and (self.actionHotRecordCount or 0) or 0
    if not recordsReady then
        capture:RecordProcCapture(event, phase, "records=dirty")
        return false
    end

    local adapter = YAB.Adapter
    local normalizedEventSpellID = eventSpellID
    if adapter and adapter.NormalizeSpellID then
        normalizedEventSpellID = adapter:NormalizeSpellID(eventSpellID)
    end
    local isGlowShow = event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
    local isGlowHide = event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE"
    local showFocusSelected = false
    if isGlowShow and normalizedEventSpellID ~= nil
        and capture.CanReplaceProcCaptureFocus and capture:CanReplaceProcCaptureFocus() then
        for index = 1, recordCount do
            local record = records[index]
            local button = record and record.button
            local state = record and (record.state or (self.buttonStates and self.buttonStates[button]))
            if record and button and record.hasAction == true and state
                and IsButtonVisible(button, record.holder) then
                local exactMatch = state.procSpellID == normalizedEventSpellID
                if not exactMatch and state.flyoutID and adapter and adapter.IsFlyoutProcGlowFor then
                    exactMatch = adapter:IsFlyoutProcGlowFor(state.flyoutID, normalizedEventSpellID) == true
                end
                if exactMatch then
                    capture:SetProcCaptureFocus(
                        self:GetProcCaptureButtonKey(button),
                        record.action,
                        normalizedEventSpellID,
                        phase
                    )
                    showFocusSelected = true
                    break
                end
            end
        end
    end
    local exactCount, overlayCount, newOverlayCount, relevantCount = 0, 0, 0, 0
    local usableStale, visualStale, glowFrameMissing = 0, 0, 0
    local focusUsableStale, focusVisualStale, focusGlowFrameMissing = 0, 0, 0
    local focusEventMatchCount = 0
    local unhandledNewOverlay = 0
    local enhancedMode = not (YAB.Visuals and YAB.Visuals.GetDiagnosticVisualMode)
        or YAB.Visuals:GetDiagnosticVisualMode() ~= "native"

    for index = 1, recordCount do
        local record = records[index]
        local button = record and record.button
        local state = record and (record.state or (self.buttonStates and self.buttonStates[button]))
        if record and button and record.hasAction == true and state
            and IsButtonVisible(button, record.holder) then
            local procSpellID = state.procSpellID
            local eventMatch = normalizedEventSpellID ~= nil and procSpellID == normalizedEventSpellID
            if not eventMatch and normalizedEventSpellID ~= nil and state.flyoutID
                and adapter and adapter.IsFlyoutProcGlowFor then
                eventMatch = adapter:IsFlyoutProcGlowFor(state.flyoutID, normalizedEventSpellID) == true
            end
            if eventMatch then exactCount = exactCount + 1 end

            local overlayed = procSpellID ~= nil and adapter and adapter.IsProcSpellOverlayed
                and adapter:IsProcSpellOverlayed(procSpellID) == true or false
            if overlayed then overlayCount = overlayCount + 1 end
            local newlyOverlayed = overlayed and self.procCaptureOverlayBaseline[button] ~= true
            if newlyOverlayed then newOverlayCount = newOverlayCount + 1 end
            local buttonKey = self:GetProcCaptureButtonKey(button)
            if isGlowShow and newlyOverlayed and not showFocusSelected
                and capture.CanReplaceProcCaptureFocus and capture:CanReplaceProcCaptureFocus() then
                capture:SetProcCaptureFocus(buttonKey, record.action, normalizedEventSpellID, phase)
                showFocusSelected = true
            end
            local focusMatch = capture.IsProcCaptureFocus
                and capture:IsProcCaptureFocus(buttonKey) or false
            if focusMatch and eventMatch then focusEventMatchCount = focusEventMatchCount + 1 end

            local apiUsable, apiNoMana
            if adapter and adapter.IsUsableAction then
                apiUsable, apiNoMana = adapter:IsUsableAction(record.action)
            end
            local usableMismatch = apiUsable ~= nil and apiNoMana ~= nil
                and (state.usable ~= apiUsable or state.noMana ~= apiNoMana)
            if usableMismatch then usableStale = usableStale + 1 end
            if focusMatch and usableMismatch then focusUsableStale = focusUsableStale + 1 end

            local visual = YAB.Visuals and YAB.Visuals.GetButtonVisual
                and YAB.Visuals:GetButtonVisual(button) or nil
            local managerVisualMismatch = visual ~= nil and (
                visual.usable ~= (state.usable == true)
                or visual.noMana ~= (state.noMana == true)
                or visual.procGlow ~= (state.procGlow == true)
            )
            local colorStatus = "unknown"
            local baseRelevant = focusMatch or eventMatch or newlyOverlayed or usableMismatch or managerVisualMismatch
            if baseRelevant then
                colorStatus = self:ReadProcCaptureColorStatus(record.icon or button.icon or button.Icon, visual)
            end
            local actualVisualMismatch = managerVisualMismatch or colorStatus == "mismatch"
            if actualVisualMismatch then visualStale = visualStale + 1 end
            if focusMatch and actualVisualMismatch then focusVisualStale = focusVisualStale + 1 end

            local frameShown
            if baseRelevant and enhancedMode and state.procGlow == true and visual and visual.procGlow == true then
                frameShown = self:ReadProcCaptureShown(visual.procGlowFrame)
                if frameShown == false then glowFrameMissing = glowFrameMissing + 1 end
            end
            if focusMatch and frameShown == false then
                focusGlowFrameMissing = focusGlowFrameMissing + 1
            end
            if phase == "after" and isGlowShow and newlyOverlayed and state.procGlow ~= true then
                unhandledNewOverlay = unhandledNewOverlay + 1
            end

            local relevant = baseRelevant or actualVisualMismatch or frameShown == false
            if relevant then
                relevantCount = relevantCount + 1
                local detail = string.format(
                    "button=%s slot=%s eventSpell=%s procSpell=%s flyout=%s match=%s overlay=%s newOverlay=%s api=%s/%s manager=%s/%s/%s visual=%s/%s/%s frame=%s color=%s",
                    buttonKey,
                    tostring(record.action or "none"),
                    tostring(normalizedEventSpellID or "none"),
                    tostring(procSpellID or "none"),
                    tostring(state.flyoutID or "none"),
                    self:ProcCaptureBool(eventMatch),
                    self:ProcCaptureBool(overlayed),
                    self:ProcCaptureBool(newlyOverlayed),
                    self:ProcCaptureBool(apiUsable),
                    self:ProcCaptureBool(apiNoMana),
                    self:ProcCaptureBool(state.usable),
                    self:ProcCaptureBool(state.noMana),
                    self:ProcCaptureBool(state.procGlow),
                    self:ProcCaptureBool(visual and visual.usable),
                    self:ProcCaptureBool(visual and visual.noMana),
                    self:ProcCaptureBool(visual and visual.procGlow),
                    self:ProcCaptureBool(frameShown),
                    colorStatus
                )
                capture:RecordProcCapture(event, phase, detail)
                if focusMatch and capture.RecordProcCaptureKey then
                    if isGlowShow then
                        capture:RecordProcCaptureKey(
                            phase == "before" and "showBefore" or "showAfter",
                            event,
                            phase,
                            detail
                        )
                    elseif event == "ACTION_USABLE_CHANGED"
                        or event == "ACTIONBAR_UPDATE_USABLE"
                        or event == "PLAYER_TARGET_CHANGED"
                        or (event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" and eventMatch)
                        or event == "PLAYER_REGEN_ENABLED" then
                        local signature = string.format(
                            "overlay=%s api=%s/%s manager=%s/%s/%s visual=%s/%s/%s frame=%s color=%s",
                            self:ProcCaptureBool(overlayed),
                            self:ProcCaptureBool(apiUsable),
                            self:ProcCaptureBool(apiNoMana),
                            self:ProcCaptureBool(state.usable),
                            self:ProcCaptureBool(state.noMana),
                            self:ProcCaptureBool(state.procGlow),
                            self:ProcCaptureBool(visual and visual.usable),
                            self:ProcCaptureBool(visual and visual.noMana),
                            self:ProcCaptureBool(visual and visual.procGlow),
                            self:ProcCaptureBool(frameShown),
                            colorStatus
                        )
                        local force = event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE"
                            or event == "PLAYER_REGEN_ENABLED"
                        capture:RecordProcCaptureKey("timeline", event, phase, detail, signature, force)
                    end
                end
            end
            if phase == "after" then
                self.procCaptureOverlayBaseline[button] = overlayed and true or nil
            end
        end
    end

    local result
    if phase == "after" then
        local hasFocus = capture.HasProcCaptureFocus and capture:HasProcCaptureFocus()
        local relevantUsableStale = hasFocus and focusUsableStale or usableStale
        local relevantVisualStale = hasFocus and focusVisualStale or visualStale
        local relevantGlowFrameMissing = hasFocus and focusGlowFrameMissing or glowFrameMissing
        local procEventRelevant = not (isGlowShow or isGlowHide) or focusEventMatchCount > 0
        if isGlowShow and exactCount > 0 and relevantUsableStale > 0 then
            result = "USABLE_STALE"
        elseif isGlowShow and normalizedEventSpellID ~= nil
            and exactCount == 0 and unhandledNewOverlay > 0 then
            result = "IDENTITY_MISS"
        elseif isGlowHide and focusEventMatchCount > 0 and relevantUsableStale > 0 then
            result = "USABLE_STALE"
        elseif (event == "ACTION_USABLE_CHANGED" or event == "ACTIONBAR_UPDATE_USABLE"
            or event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_REGEN_ENABLED")
            and relevantUsableStale > 0 then
            result = "USABLE_STALE"
        elseif procEventRelevant and relevantVisualStale > 0 then
            result = "VISUAL_STALE"
        elseif procEventRelevant and relevantGlowFrameMissing > 0 then
            result = "GLOW_FRAME_MISSING"
        end
    end
    if relevantCount > 0 or result then
        capture:RecordProcCapture(event, phase, string.format(
            "summary records=%d relevant=%d exact=%d overlay=%d newOverlay=%d unhandledOverlay=%d usableStale=%d visualStale=%d glowMissing=%d",
            recordCount,
            relevantCount,
            exactCount,
            overlayCount,
            newOverlayCount,
            unhandledNewOverlay,
            usableStale,
            visualStale,
            glowFrameMissing
        ), result)
    end
    return result ~= nil
end

local SIMPLE_REFRESH_MODES = {
    aura = true,
    cooldown = true,
    cooldownMeta = true,
    glow = true,
    hotkey = true,
    range = true,
    state = true,
    text = true,
    usable = true,
}

local function MergeRefreshMode(current, mode)
    mode = mode or "full"
    if not current or current == mode then return mode end
    if current == "full" or mode == "full" or current == "identity" or mode == "identity" then
        return "full"
    end
    if not SIMPLE_REFRESH_MODES[current] and current:sub(1, 1) ~= ":" then
        return "full"
    end
    if not SIMPLE_REFRESH_MODES[mode] then
        return "full"
    end
    local merged = current:sub(1, 1) == ":" and current or (":" .. current .. ":")
    local token = ":" .. mode .. ":"
    if merged:find(token, 1, true) then return merged end
    return merged .. mode .. ":"
end

local function RefreshModeHas(mode, key)
    if mode == "full" or mode == key then return true end
    return type(mode) == "string" and mode:sub(1, 1) == ":" and mode:find(":" .. key .. ":", 1, true) ~= nil
end

local function RefreshModeUpdatesActionIdentity(mode)
    return mode == "identity" or mode == "full"
end

local function DirtySlotsUpdateActionIdentity(dirtySlots)
    for _, mode in pairs(dirtySlots or {}) do
        if RefreshModeUpdatesActionIdentity(mode) then return true end
    end
    return false
end

local SETTING_REFRESH_SCOPES = {
    action = true,
    layout = true,
    visual = true,
    visibility = true,
}

local function MergeSettingScope(current, scope)
    scope = scope or "full"
    if not current or current == scope then return scope end
    if current == "full" or scope == "full" then
        return "full"
    end
    if not SETTING_REFRESH_SCOPES[current] and current:sub(1, 1) ~= ":" then
        return "full"
    end
    if not SETTING_REFRESH_SCOPES[scope] then
        return "full"
    end
    local merged = current:sub(1, 1) == ":" and current or (":" .. current .. ":")
    local token = ":" .. scope .. ":"
    if merged:find(token, 1, true) then return merged end
    return merged .. scope .. ":"
end

local function SettingScopeHas(scope, key)
    if scope == "full" or scope == key then return true end
    return type(scope) == "string" and scope:sub(1, 1) == ":" and scope:find(":" .. key .. ":", 1, true) ~= nil
end

function BarManager:GetPageState(force)
    if force or not self.pageStateCache then
        self.pageStateCache = YAB.Adapter:GetActionPageState()
    end
    return self.pageStateCache
end

function BarManager:MarkReason(reason, mode, markDirty, prefix)
    reason = reason or "refresh"
    self.lastRefreshReason = reason
end

function BarManager:QueueSlotRefresh(slot, reason, mode)
    local numberSlot = tonumber(slot)
    if not numberSlot then
        self:QueueActionRefresh(reason, "full")
        return
    end
    self:MarkReason(reason, mode or "full")
    self.dirtySlots[numberSlot] = MergeRefreshMode(self.dirtySlots[numberSlot], mode or "full")
    if HotDiagnostics and HotDiagnostics.enabled then
        HotDiagnostics:RecordRefreshQueue(reason, mode or "full", "slot")
    end
    self:ScheduleRefresh()
end

function BarManager:QueueActionRefresh(reason, mode)
    mode = mode or "full"
    if RefreshModeUpdatesActionIdentity(mode) then
        self:InvalidateProcIndex(reason or "action refresh", "all")
    end
    self:MarkReason(reason, mode or "full")
    self.dirtyActionMode = MergeRefreshMode(self.dirtyActionMode, mode)
    if HotDiagnostics and HotDiagnostics.enabled then
        HotDiagnostics:RecordRefreshQueue(reason, mode, "action")
    end
    self:ScheduleRefresh()
end

function BarManager:QueueMainPageIdentity(reason)
    if reason == "secure-state-page" then
        local record = self.bars.main
        if record and record.buttons then
            for _, button in ipairs(record.buttons) do
                self:ClearButtonCheckedState(button)
            end
        end
    end
    self:InvalidateProcIndex(reason or "main page identity", "delta")
    self:MarkReason(reason, "page", false)
    self.pageStateCache = nil
    self.dirtyMainPageIdentity = true
    if InCombat() then
        self.mainPageSyncPending = true
    end
    if HotDiagnostics and HotDiagnostics.enabled then
        HotDiagnostics:RecordRefreshQueue(reason, "identity", "page")
    end
    self:ScheduleRefresh()
end

function BarManager:QueueGlobalIconRefresh(reason)
    self:MarkReason(reason, "icon", false)
    self.dirtyGlobalIcon = true
    if HotDiagnostics and HotDiagnostics.enabled then
        HotDiagnostics:RecordRefreshQueue(reason, "icon", "icon")
    end
    self:ScheduleRefresh()
end

function BarManager:MarkDirtyRefresh(reason, mode)
    reason = reason or "refresh"
    self.lastRefreshReason = reason
end

function BarManager:QueueCooldownMetaIfPending(reason)
    if self.refreshPending ~= true or self.fullRefreshPending == true or not self.dirtyActionMode then
        return
    end
    self:MarkDirtyRefresh(reason, "cooldownMeta")
    self.dirtyActionMode = MergeRefreshMode(self.dirtyActionMode, "cooldownMeta")
    if HotDiagnostics and HotDiagnostics.enabled then
        HotDiagnostics:RecordRefreshQueue(reason, "cooldownMeta", "merge")
    end
end

local function ApplyNativeCoreCooldownButton(manager, button, action, snapshot, backend, trustOnGCD, diagnostic, hotRecord, skipChargeRead, allowGCDDedup)
    local state = hotRecord and hotRecord.nativeState or GetNativeCoreState(manager, button)
    local wasMainActive = state.mainActive == true
    local wasChargeActive = state.chargeActive == true
    if not backend then return ClearNativeCoreCooldownState(state, button) end

    if hotRecord then
        if hotRecord.hasAction ~= true then
            return ClearNativeCoreCooldownState(state, button)
        end
    else
        if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
        if backend.hasAction(action) ~= true then
            return ClearNativeCoreCooldownState(state, button)
        end
    end

    if not action then
        return ClearNativeCoreCooldownState(state, button)
    end

    local writes = 0
    local cooldown = hotRecord and hotRecord.cooldown or GetButtonCooldown(button)
    local chargeCooldown = hotRecord and hotRecord.chargeCooldown or GetButtonChargeCooldown(button)
    local hideNumbers = ShouldHideNativeCoreCooldownNumbers(snapshot)
    writes = writes + SetCooldownNumbersHiddenCached(state, "mainNumbersHidden", cooldown, hideNumbers)
    writes = writes + SetCooldownNumbersHiddenCached(state, "chargeNumbersHidden", chargeCooldown, hideNumbers)

    local mainActiveNow = false
    local chargeActiveNow = false
    local desaturation = 0
    local clearDesaturated = true

    if backend.mode == "retail-duration" then
        if diagnostic then
            diagnostic.backendReads = diagnostic.backendReads + 1
            diagnostic.activeMainReads = diagnostic.activeMainReads + 1
        end
        local cooldownInfo = backend.getCooldownInfo(action)
        if type(cooldownInfo) ~= "table" then
            writes = writes + ClearNativeCoreCooldownState(state, button)
            if wasMainActive or wasChargeActive then
                writes = writes + ApplyNativeCoreUsable(button, action)
            end
            return writes
        end

        local active = cooldownInfo.isActive == true and cooldownInfo.isEnabled ~= false
        local onGCD = trustOnGCD == true and cooldownInfo.isOnGCD == true
        local durationObject
        if active then
            local repeatedGCD = allowGCDDedup == true
                and onGCD
                and wasMainActive
                and state.mainOnGCD == true
            if diagnostic then
                if repeatedGCD then
                    diagnostic.repeatGCDCandidates = diagnostic.repeatGCDCandidates + 1
                    diagnostic.skippedGCDWrites = diagnostic.skippedGCDWrites + 1
                end
            end
            if repeatedGCD then
                mainActiveNow = true
            else
                if diagnostic then
                    diagnostic.backendReads = diagnostic.backendReads + 1
                    diagnostic.activeMainReads = diagnostic.activeMainReads + 1
                end
                durationObject = backend.getCooldownDuration(action)
                local durationWrites, durationApplied = SetCooldownDurationObjectCached(state, "mainActive", cooldown, durationObject)
                writes = writes + durationWrites
                if diagnostic then
                    diagnostic.activeMainWrites = diagnostic.activeMainWrites + durationWrites
                end
                if durationApplied then
                    mainActiveNow = true
                    state.mainOnGCD = onGCD
                    state.mainApplyGeneration = (state.mainApplyGeneration or 0) + 1
                else
                    active = false
                    state.mainOnGCD = false
                    writes = writes + ClearCooldownCached(state, "mainActive", cooldown)
                end
            end
        else
            state.mainOnGCD = false
            writes = writes + ClearCooldownCached(state, "mainActive", cooldown)
        end

        local maxCharges = hotRecord and hotRecord.maxCharges or nil
        local chargeActive = false
        if skipChargeRead ~= true then
            if diagnostic then
                diagnostic.backendReads = diagnostic.backendReads + 1
                diagnostic.chargeInfoReads = diagnostic.chargeInfoReads + 1
            end
            local chargeInfo = backend.getChargeInfo(action)
            if type(chargeInfo) == "table" then
                maxCharges = chargeInfo.maxCharges
                if type(maxCharges) ~= "number" then maxCharges = nil end
                chargeActive = chargeInfo.isActive == true
            end
        end
        if maxCharges ~= nil and maxCharges > 1 and chargeActive then
            if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
            local chargeDurationObject = backend.getChargeDuration(action)
            local durationWrites, durationApplied = SetCooldownDurationObjectCached(state, "chargeActive", chargeCooldown, chargeDurationObject)
            writes = writes + durationWrites
            if durationApplied then
                chargeActiveNow = true
            else
                writes = writes + ClearCooldownCached(state, "chargeActive", chargeCooldown)
            end
        else
            writes = writes + ClearCooldownCached(state, "chargeActive", chargeCooldown)
        end

        local desaturationDurationObject = durationObject
        local forceAnyCurve = false
        if active and trustOnGCD ~= true then
            if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
            desaturationDurationObject = backend.getCooldownDuration(action, true)
            forceAnyCurve = true
        end
        desaturation, clearDesaturated = ComputeNativeCoreDesaturation(
            button,
            action,
            active,
            onGCD,
            desaturationDurationObject,
            maxCharges,
            snapshot,
            forceAnyCurve
        )
    else
        if diagnostic then
            diagnostic.backendReads = diagnostic.backendReads + 1
            diagnostic.activeMainReads = diagnostic.activeMainReads + 1
        end
        local startRaw, durationRaw, enableRaw, modRateRaw = backend.getCooldownInfo(action)
        local startValue = SafeCooldownNumber(startRaw)
        local durationValue = SafeCooldownNumber(durationRaw)
        local enableValue = FastBoolean(enableRaw, nil)
        local modRateValue = SafeCooldownNumber(modRateRaw)
        local active = enableValue == true
            and startValue ~= nil
            and durationValue ~= nil
            and durationValue > 0
        local onGCD = active and durationValue <= MAX_EXPECTED_GCD_SECONDS
        if active then
            writes = writes + SetCooldownScalarCached(state, "mainActive", cooldown, startValue, durationValue, modRateValue)
            mainActiveNow = state.mainActive == true
            state.mainOnGCD = onGCD
            if mainActiveNow then
                state.mainApplyGeneration = (state.mainApplyGeneration or 0) + 1
            end
        else
            state.mainOnGCD = false
            writes = writes + ClearCooldownCached(state, "mainActive", cooldown)
        end

        local currentCharges, maxCharges, chargeStart, chargeDuration, chargeModRate
        if skipChargeRead == true then
            maxCharges = hotRecord and hotRecord.maxCharges or nil
        else
            if diagnostic then
                diagnostic.backendReads = diagnostic.backendReads + 1
                diagnostic.chargeInfoReads = diagnostic.chargeInfoReads + 1
            end
            local currentRaw, maxRaw, chargeStartRaw, chargeDurationRaw, chargeModRateRaw = backend.getChargeInfo(action)
            currentCharges = SafeCooldownNumber(currentRaw)
            maxCharges = SafeCooldownNumber(maxRaw)
            chargeStart = SafeCooldownNumber(chargeStartRaw)
            chargeDuration = SafeCooldownNumber(chargeDurationRaw)
            chargeModRate = SafeCooldownNumber(chargeModRateRaw)
        end
        local chargeActive = maxCharges ~= nil
            and maxCharges > 1
            and currentCharges ~= nil
            and currentCharges < maxCharges
            and chargeStart ~= nil
            and chargeDuration ~= nil
            and chargeDuration > 0
        if chargeActive then
            writes = writes + SetCooldownScalarCached(state, "chargeActive", chargeCooldown, chargeStart, chargeDuration, chargeModRate)
            chargeActiveNow = state.chargeActive == true
        else
            writes = writes + ClearCooldownCached(state, "chargeActive", chargeCooldown)
        end

        if active and not onGCD and not (snapshot and snapshot.cooldownFade == false) then
            desaturation = GetCooldownDesaturation(button)
            clearDesaturated = desaturation == 0
        end
    end

    if clearDesaturated then
        if state.nativeDesaturationActive == true then
            writes = writes + SetIconDesaturationNative(GetButtonIcon(button), 0, true)
            state.nativeDesaturationActive = false
        end
    else
        local resetDesaturated = state.nativeDesaturationActive ~= true
        writes = writes + SetIconDesaturationNative(GetButtonIcon(button), desaturation, false, resetDesaturated)
        state.nativeDesaturationActive = true
    end
    if (wasMainActive and not mainActiveNow) or (wasChargeActive and not chargeActiveNow) then
        writes = writes + ApplyNativeCoreUsable(button, action)
    end
    return writes
end

local function ApplyPlainCooldownHot(record, backend, diagnostic)
    return ApplyNativeCoreCooldownButton(
        BarManager,
        record.button,
        record.action,
        record.snapshot,
        backend,
        true,
        diagnostic,
        record,
        true,
        true
    )
end

local function ApplyChargeCooldownHot(record, backend, diagnostic)
    return ApplyNativeCoreCooldownButton(
        BarManager,
        record.button,
        record.action,
        record.snapshot,
        backend,
        true,
        diagnostic,
        record,
        false,
        false
    )
end

local function ApplyItemOrUnknownCooldownHot(record, backend, diagnostic)
    return ApplyNativeCoreCooldownButton(
        BarManager,
        record.button,
        record.action,
        record.snapshot,
        backend,
        true,
        diagnostic,
        record,
        false,
        false
    )
end

local function ApplyNativeCoreChargeButton(manager, button, action, snapshot, backend, diagnostic, knownHasAction)
    local state = GetNativeCoreState(manager, button)
    if not backend then return ClearNativeCoreChargeState(state, button, true) end
    if knownHasAction ~= true then
        if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
        if backend.hasAction(action) ~= true then
            return ClearNativeCoreChargeState(state, button, true)
        end
    end

    local writes = 0
    local chargeCooldown = GetButtonChargeCooldown(button)
    writes = writes + SetCooldownNumbersHiddenCached(
        state,
        "chargeNumbersHidden",
        chargeCooldown,
        ShouldHideNativeCoreCooldownNumbers(snapshot)
    )
    if backend.mode == "retail-duration" then
        if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
        local chargeInfo = backend.getChargeInfo(action)
        local maxCharges
        local chargeActive = false
        if type(chargeInfo) == "table" then
            maxCharges = chargeInfo.maxCharges
            if type(maxCharges) ~= "number" then maxCharges = nil end
            chargeActive = chargeInfo.isActive == true
        end
        if diagnostic then
            if maxCharges ~= nil and maxCharges > 1 then
                diagnostic.eligibleButtons = diagnostic.eligibleButtons + 1
                if chargeActive then diagnostic.activeButtons = diagnostic.activeButtons + 1 end
            else
                diagnostic.ineligibleButtons = diagnostic.ineligibleButtons + 1
            end
        end
        if maxCharges ~= nil and maxCharges > 1 and chargeActive then
            if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
            local chargeDurationObject = backend.getChargeDuration(action)
            local durationWrites, durationApplied = SetCooldownDurationObjectCached(state, "chargeActive", chargeCooldown, chargeDurationObject)
            writes = writes + durationWrites
            if not durationApplied then
                writes = writes + ClearCooldownCached(state, "chargeActive", chargeCooldown)
            end
        else
            writes = writes + ClearCooldownCached(state, "chargeActive", chargeCooldown)
        end
        writes = writes + ApplyNativeCoreCountButton(manager, state, button, action, snapshot, backend, diagnostic)
        return writes
    end

    if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
    local currentRaw, maxRaw, chargeStartRaw, chargeDurationRaw, chargeModRateRaw = backend.getChargeInfo(action)
    local currentCharges = SafeCooldownNumber(currentRaw)
    local maxCharges = SafeCooldownNumber(maxRaw)
    local chargeStart = SafeCooldownNumber(chargeStartRaw)
    local chargeDuration = SafeCooldownNumber(chargeDurationRaw)
    local chargeModRate = SafeCooldownNumber(chargeModRateRaw)
    local multipleCharges = maxCharges ~= nil and maxCharges > 1
    local chargeActive = multipleCharges
        and currentCharges ~= nil
        and currentCharges < maxCharges
        and chargeStart ~= nil
        and chargeDuration ~= nil
        and chargeDuration > 0
    if diagnostic then
        if multipleCharges then
            diagnostic.eligibleButtons = diagnostic.eligibleButtons + 1
            if chargeActive then diagnostic.activeButtons = diagnostic.activeButtons + 1 end
        else
            diagnostic.ineligibleButtons = diagnostic.ineligibleButtons + 1
        end
    end
    if chargeActive then
        writes = writes + SetCooldownScalarCached(state, "chargeActive", chargeCooldown, chargeStart, chargeDuration, chargeModRate)
    else
        writes = writes + ClearCooldownCached(state, "chargeActive", chargeCooldown)
    end

    if multipleCharges then
        if not (snapshot and snapshot.showCounts == true) then
            writes = writes + SetNativeCoreCountText(manager, state, button, "", false)
        elseif currentCharges ~= nil then
            writes = writes + SetNativeCoreCountText(manager, state, button, tostring(currentCharges), false)
        else
            manager.nativeCoreCountSkips = (manager.nativeCoreCountSkips or 0) + 1
        end
    else
        writes = writes + ApplyNativeCoreCountButton(manager, state, button, action, snapshot, backend, diagnostic)
    end
    return writes
end

function BarManager:ForEachVisibleNativeCoreButton(callback)
    local buttons, holders, directCount = self:GetDirectActionButtonList()
    if not buttons then
        self.directActionListFallbacks = (self.directActionListFallbacks or 0) + 1
        for _, record in pairs(self.bars or {}) do
            if record.kind == "action" and record.buttons then
                local holder = record.holder
                for _, button in ipairs(record.buttons) do
                    if IsButtonVisible(button, holder) then
                        local action = GetButtonAction(button)
                        if action then callback(button, action, holder) end
                    end
                end
            end
        end
        return
    end
    directCount = tonumber(directCount) or 0
    for index = 1, directCount do
        local button = buttons[index]
        local holder = holders and holders[index]
        if IsButtonVisible(button, holder) then
            local action = GetButtonAction(button)
            if action then callback(button, action, holder) end
        end
    end
end

function BarManager:PrepareActionHotBackend()
    if self.actionHotBackendReady == true then
        return self.actionHotBackend
    end
    self.actionHotBackendReady = true
    local adapter = YAB.Adapter
    if adapter and adapter.GetActionHotBackend then
        self.actionHotBackend = adapter:GetActionHotBackend()
    else
        self.actionHotBackend = nil
    end
    return self.actionHotBackend
end

function BarManager:HandleNativeCoreCooldownEvent(event, diagnostic)
    self:MarkReason(event, "native-core", false)
    local backend = self.actionHotBackend
    if self.actionHotBackendReady ~= true then
        backend = self:PrepareActionHotBackend()
    end
    local extraButton = _G.ExtraActionButton1
    local extraHolder = _G.ExtraActionBarFrame
    local records, recordCount = self:GetActionHotRecords()
    recordCount = tonumber(recordCount) or 0
    for index = 1, recordCount do
        if diagnostic then diagnostic.candidates = diagnostic.candidates + 1 end
        local record = records[index]
        local button = record and record.button
        if button ~= extraButton and record and IsButtonVisible(button, record.holder) then
            if record.action then
                if diagnostic then diagnostic.buttons = diagnostic.buttons + 1 end
                local writes
                if record.hasMultipleCharges == true then
                    writes = ApplyChargeCooldownHot(record, backend, diagnostic)
                elseif record.isItem == true or record.isMacro == true or record.actionType == nil then
                    writes = ApplyItemOrUnknownCooldownHot(record, backend, diagnostic)
                else
                    writes = ApplyPlainCooldownHot(record, backend, diagnostic)
                end
                if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
            end
        end
    end
    if IsButtonVisible(extraButton, extraHolder) then
        if diagnostic then diagnostic.candidates = diagnostic.candidates + 1 end
        local action = GetButtonAction(extraButton)
        if action then
            if diagnostic then diagnostic.buttons = diagnostic.buttons + 1 end
            local writes = ApplyNativeCoreCooldownButton(self, extraButton, action, GetButtonConfigSnapshot(self, extraButton, "extraAction"), backend, true, diagnostic)
            if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
        end
    end
    return backend ~= nil
end

function BarManager:HandleNativeCoreChargeEvent(event, diagnostic)
    self:MarkReason(event, "native-core-count", false)
    local backend = self.actionHotBackend
    if self.actionHotBackendReady ~= true then
        backend = self:PrepareActionHotBackend()
    end
    local extraButton = _G.ExtraActionButton1
    local extraHolder = _G.ExtraActionBarFrame
    self:GetActionHotRecords()
    local chargeRecords = self.chargeHotRecords
    local chargeCount = self.chargeHotRecordCount or 0
    for index = 1, chargeCount do
        if diagnostic then diagnostic.candidates = diagnostic.candidates + 1 end
        local record = chargeRecords[index]
        local button = record and record.button
        if button ~= extraButton and record and IsButtonVisible(button, record.holder) then
            local action = record.action
            if action and record.hasAction then
                if diagnostic then diagnostic.buttons = diagnostic.buttons + 1 end
                local writes = ApplyNativeCoreChargeButton(self, button, action, record.snapshot, backend, diagnostic, true)
                if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
            elseif record.nativeState then
                if diagnostic then diagnostic.buttons = diagnostic.buttons + 1 end
                local writes = ClearNativeCoreChargeState(record.nativeState, button, true)
                if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
            end
        end
    end
    local countRecords = self.countHotRecords
    local countCount = self.countHotRecordCount or 0
    for index = 1, countCount do
        local record = countRecords[index]
        if record and record.hasMultipleCharges ~= true then
            if diagnostic then diagnostic.candidates = diagnostic.candidates + 1 end
            local button = record.button
            if button ~= extraButton and IsButtonVisible(button, record.holder) then
                if diagnostic then diagnostic.buttons = diagnostic.buttons + 1 end
                local writes
                if record.hasAction then
                    writes = ApplyNativeCoreCountButton(
                        self,
                        record.nativeState,
                        button,
                        record.action,
                        record.snapshot,
                        backend,
                        diagnostic
                    )
                else
                    writes = SetNativeCoreCountText(self, record.nativeState, button, "", false)
                end
                if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
            end
        end
    end
    if IsButtonVisible(extraButton, extraHolder) then
        if diagnostic then diagnostic.candidates = diagnostic.candidates + 1 end
        local action = GetButtonAction(extraButton)
        if action then
            if diagnostic then diagnostic.buttons = diagnostic.buttons + 1 end
            local writes = ApplyNativeCoreChargeButton(self, extraButton, action, GetButtonConfigSnapshot(self, extraButton, "extraAction"), backend, diagnostic)
            if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
        end
    end
    return backend ~= nil
end

function BarManager:HandleNativeCoreUsesEvent(event, spellID, relatedSpellID, diagnostic)
    local id = YAB.Adapter and YAB.Adapter.NormalizeSpellID
        and YAB.Adapter:NormalizeSpellID(spellID)
    if not id then return false end
    local relatedID = YAB.Adapter:NormalizeSpellID(relatedSpellID)
    local backend = self.actionHotBackend
    if self.actionHotBackendReady ~= true then
        backend = self:PrepareActionHotBackend()
    end
    if not backend then return false end

    self:MarkReason(event, "native-core-count", false)
    local records, recordCount = self:GetActionHotRecords()
    recordCount = tonumber(recordCount) or 0
    for index = 1, recordCount do
        if diagnostic then diagnostic.candidates = diagnostic.candidates + 1 end
        local record = records[index]
        local state = record and record.state
        local actionSpellID = state and state.actionSpellID
        if record and record.hasAction and record.action
            and actionSpellID
            and (actionSpellID == id or actionSpellID == relatedID) then
            local button = record.button
            if IsButtonVisible(button, record.holder) then
                if diagnostic then diagnostic.buttons = diagnostic.buttons + 1 end
                local writes = ApplyNativeCoreCountButton(
                    self,
                    record.nativeState,
                    button,
                    record.action,
                    record.snapshot,
                    backend,
                    diagnostic
                )
                if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
            end
        end
    end
    return true
end

local function ApplyActionUsableFullScanButton(manager, button, action, diagnostic)
    if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
    local hasAction = YAB.Adapter:HasAction(action) == true
    if hasAction then
        if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
        return ApplyNativeCoreUsable(button, action)
    end
    return 0
end

function BarManager:HandleActionUsableFullScan(event, diagnostic)
    self:MarkReason(event, "usable", false)
    local buttons, holders, directCount = self:GetDirectActionButtonList()
    if buttons then
        directCount = tonumber(directCount) or 0
        for index = 1, directCount do
            if diagnostic then diagnostic.candidates = diagnostic.candidates + 1 end
            local button = buttons[index]
            local holder = holders and holders[index]
            if IsButtonVisible(button, holder) then
                local action = GetButtonAction(button)
                if action then
                    if diagnostic then diagnostic.buttons = diagnostic.buttons + 1 end
                    local writes = ApplyActionUsableFullScanButton(self, button, action, diagnostic)
                    if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
                end
            end
        end
    end
    local extraButton = _G.ExtraActionButton1
    local extraHolder = _G.ExtraActionBarFrame
    if IsButtonVisible(extraButton, extraHolder) then
        if diagnostic then diagnostic.candidates = diagnostic.candidates + 1 end
        local action = GetButtonAction(extraButton)
        if action then
            if diagnostic then diagnostic.buttons = diagnostic.buttons + 1 end
            local writes = ApplyActionUsableFullScanButton(self, extraButton, action, diagnostic)
            if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
        end
    end
    return true
end

function BarManager:ReadActionUsableForReconcile(action, generation, diagnostic)
    if self.usableReconcileSeen[action] ~= generation then
        if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
        local usable, noMana = YAB.Adapter:IsUsableAction(action)
        self.usableReconcileSeen[action] = generation
        self.usableReconcileUsable[action] = usable
        self.usableReconcileNoMana[action] = noMana
    end
    return self.usableReconcileUsable[action], self.usableReconcileNoMana[action]
end

function BarManager:HandleActionUsableReconcile(event, diagnostic)
    self:MarkReason(event, "usable", false)
    local generation = (self.usableReconcileGeneration or 0) + 1
    self.usableReconcileGeneration = generation
    local records, recordCount = self:GetActionHotRecords()
    for index = 1, recordCount or 0 do
        if diagnostic then diagnostic.candidates = diagnostic.candidates + 1 end
        local record = records[index]
        local button = record and record.button
        if record and record.hasAction == true and record.action and IsButtonVisible(button, record.holder) then
            if diagnostic then diagnostic.buttons = diagnostic.buttons + 1 end
            local usable, noMana = self:ReadActionUsableForReconcile(record.action, generation, diagnostic)
            if usable ~= nil and noMana ~= nil then
                local inRange = GetCachedActionInRange(self, record.action, record.snapshot)
                local writes = ApplyActionTintState(self, button, usable, noMana, inRange, record.snapshot, true)
                if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
            end
        end
    end

    local extraButton = _G.ExtraActionButton1
    local extraHolder = _G.ExtraActionBarFrame
    if IsButtonVisible(extraButton, extraHolder) then
        if diagnostic then diagnostic.candidates = diagnostic.candidates + 1 end
        local action = GetButtonAction(extraButton)
        if action then
            if diagnostic then diagnostic.buttons = diagnostic.buttons + 1 end
            local usable, noMana = self:ReadActionUsableForReconcile(action, generation, diagnostic)
            if usable ~= nil and noMana ~= nil then
                local snapshot = GetButtonConfigSnapshot(self, extraButton, "extraAction")
                local inRange = GetCachedActionInRange(self, action, snapshot)
                local writes = ApplyActionTintState(self, extraButton, usable, noMana, inRange, snapshot, true)
                if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
            end
        end
    end
    return true
end

function BarManager:HandleNativeCoreUsableEvent(event)
    return self:HandleActionUsableFullScan(event)
end

function BarManager:HandleActionUsableChanges(changes, diagnostic)
    if type(changes) ~= "table" then
        self.usableInvalidPayloads = (self.usableInvalidPayloads or 0) + 1
        return false
    end

    self:MarkReason("ACTION_USABLE_CHANGED", "usable", false)
    local extraButton = changes[1] ~= nil and _G.ExtraActionButton1 or nil
    local extraHolder = extraButton and _G.ExtraActionBarFrame or nil
    local extraAction = extraButton and GetButtonAction(extraButton) or nil
    for _, change in ipairs(changes) do
        local slot = type(change) == "table" and change.slot or nil
        if type(slot) == "number" then
            if diagnostic then diagnostic.changes = diagnostic.changes + 1 end
            local list = self.slotButtons and self.slotButtons[slot]
            if list then
                for buttonIndex = 1, #list do
                    if diagnostic then diagnostic.candidates = diagnostic.candidates + 1 end
                    local button = list[buttonIndex]
                    if button then
                        local meta = GetButtonMeta(button)
                        local snapshot = GetButtonConfigSnapshot(self, button)
                        local inRange = GetCachedActionInRange(self, slot, snapshot)
                        if diagnostic then diagnostic.buttons = diagnostic.buttons + 1 end
                        local writes = ApplyActionTintState(self, button, change.usable, change.noMana, inRange, snapshot, IsButtonVisible(button, meta and meta.holder))
                        if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
                    end
                end
            end
            if extraAction == slot then
                if diagnostic then
                    diagnostic.candidates = diagnostic.candidates + 1
                    diagnostic.buttons = diagnostic.buttons + 1
                end
                local snapshot = GetButtonConfigSnapshot(self, extraButton, "extraAction")
                local inRange = GetCachedActionInRange(self, slot, snapshot)
                local writes = ApplyActionTintState(self, extraButton, change.usable, change.noMana, inRange, snapshot, IsButtonVisible(extraButton, extraHolder))
                if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
            end
        else
            self.usableInvalidPayloads = (self.usableInvalidPayloads or 0) + 1
        end
    end
    return true
end

function BarManager:HandleNativeCoreStateEvent(event, diagnostic)
    self:MarkReason(event, "state", false)
    local records, recordCount = self:GetActionHotRecords()
    for index = 1, recordCount or 0 do
        if diagnostic then diagnostic.candidates = diagnostic.candidates + 1 end
        local record = records[index]
        local button = record and record.button
        if record and IsButtonVisible(button, record.holder) then
            if diagnostic then diagnostic.buttons = diagnostic.buttons + 1 end
            local writes
            if record.hasAction then
                if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 2 end
                -- A secure page switch can precede the coalesced identity refresh.
                local action = record.action
                if self.dirtyMainPageIdentity then action = GetButtonAction(button) end
                if action then
                    writes = ApplyNativeCoreState(button, action, record.nativeState)
                else
                    writes = self:SetButtonCheckedState(button, false, record.nativeState)
                end
            else
                writes = self:SetButtonCheckedState(button, false, record.nativeState)
            end
            if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
        end
    end
    local button = _G.ExtraActionButton1
    local holder = _G.ExtraActionBarFrame
    if IsButtonVisible(button, holder) then
        if diagnostic then
            diagnostic.candidates = diagnostic.candidates + 1
            diagnostic.buttons = diagnostic.buttons + 1
            diagnostic.backendReads = diagnostic.backendReads + 2
        end
        local action = GetButtonAction(button)
        local hasAction = action and type(_G.HasAction) == "function" and FastBoolean(_G.HasAction(action), false) == true
        if hasAction then
            if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 2 end
            local writes = ApplyNativeCoreState(button, action, GetNativeCoreState(self, button))
            if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
        end
    end
    return true
end

function BarManager:RefreshGlobalVisibleIcons(event)
    self:MarkReason(event, "identity", false)
    local writes = 0
    local hasActionFunc = _G.HasAction
    if type(hasActionFunc) ~= "function" then return writes end
    local extraButton = _G.ExtraActionButton1
    local extraHolder = _G.ExtraActionBarFrame
    local buttons, holders, directCount = self:GetDirectActionButtonList()
    directCount = tonumber(directCount) or 0
    for index = 1, directCount do
        local button = buttons[index]
        local holder = holders and holders[index]
        if button ~= extraButton and IsButtonVisible(button, holder) then
            local action = GetButtonAction(button)
            local hasAction = action and hasActionFunc(action) == true
            if hasAction then
                writes = writes + ApplyNativeCoreIcon(button, action, GetNativeCoreState(self, button))
            end
        end
    end
    if IsButtonVisible(extraButton, extraHolder) then
        local action = GetButtonAction(extraButton)
        local hasAction = action and hasActionFunc(action) == true
        if hasAction then
            writes = writes + ApplyNativeCoreIcon(extraButton, action, GetNativeCoreState(self, extraButton))
        end
    end
    return writes
end

function BarManager:HandleNativeCoreIconEvent(event)
    self:QueueGlobalIconRefresh(event)
    return true
end

function BarManager:HandleNativeCoreSlotChanged(event, slot)
    local numberSlot = tonumber(slot)
    if slot == nil or numberSlot == 0 then
        self:QueueActionRefresh(event, "identity")
        return true
    end
    if not numberSlot or numberSlot < 1 then
        self.slotGlobalFallbacks = (self.slotGlobalFallbacks or 0) + 1
        return false
    end
    if self.slotButtons and self.slotButtons[numberSlot] then
        self:InvalidateProcIndex(event or "mapped slot identity", "delta")
        self:QueueSlotRefresh(numberSlot, event, "identity")
    end
    return true
end

function BarManager:GetCooldownDiagnosticLines(barId, index, limit)
    local lines = {}
    limit = tonumber(limit) or 6
    if limit < 1 then limit = 1 end

    local normalizedBarId = NormalizeDiagnosticBarId(barId)
    if normalizedBarId then
        local record = self.bars and self.bars[normalizedBarId] or nil
        local buttonIndex = tonumber(index) or 1
        local button = record and record.buttons and record.buttons[buttonIndex] or nil
        if not button then
            lines[#lines + 1] = string.format(
                "YActionBar: cd diag target not found (%s #%s). Usage: /yab diag cooldown bar3 11",
                tostring(normalizedBarId),
                tostring(buttonIndex)
            )
            return lines
        end
        lines[#lines + 1] = FormatCooldownDiagnostic(BuildCooldownDiagnostic(self, button, record), "YActionBar: cd target")
        return lines
    end

    local scanned, suspects, desatState, activeCooldown = 0, 0, 0, 0
    local printed = 0
    local order = YAB.BAR_ORDER or {}
    for orderIndex = 1, #order do
        local record = self.bars and self.bars[order[orderIndex]] or nil
        if record and record.kind == "action" and record.buttons then
            for buttonIndex = 1, #record.buttons do
                local button = record.buttons[buttonIndex]
                if button then
                    scanned = scanned + 1
                    local diag = BuildCooldownDiagnostic(self, button, record)
                    if diag then
                        if diag.stateDesaturationActive then desatState = desatState + 1 end
                        if diag.cooldownActive == "true" then activeCooldown = activeCooldown + 1 end
                        if diag.staleCandidate then
                            suspects = suspects + 1
                            if printed < limit then
                                printed = printed + 1
                                lines[#lines + 1] = FormatCooldownDiagnostic(diag, "YActionBar: cd suspect")
                            end
                        end
                    end
                end
            end
        end
    end

    table.insert(lines, 1, string.format(
        "YActionBar: cd scan scanned=%d suspects=%d desatState=%d active=%d directList=%d dirty=%s",
        scanned,
        suspects,
        desatState,
        activeCooldown,
        self.directActionButtonCount or 0,
        tostring(self.directActionListDirty == true)
    ))
    if suspects == 0 then
        lines[#lines + 1] = "YActionBar: cd scan found no stale desaturation candidates. Use /yab diag cooldown bar3 11 to inspect a specific icon while it is gray."
    end
    return lines
end

function BarManager:IsSpecialRefreshRelevant(kind, db)
    if not kind then return false, nil, nil, "missing-kind" end
    db = db or GetDB()
    local config = GetSpecialConfig(db, kind)
    if not config or config.enabled ~= true then
        return false, nil, config, "disabled"
    end
    local record = self.bars and self.bars[kind]
    if not record then
        return false, nil, config, "missing-record"
    end
    return true, record, config, "relevant"
end

function BarManager:QueueSpecialRefresh(kind, reason)
    if self.runtimeActive ~= true or not kind then
        return false, "inactive"
    end
    if EXTERNAL_SPECIAL_BARS[kind]
        and (self.externalSpecialApplyingAny == true
            or (self.externalSpecialApplying and self.externalSpecialApplying[kind] == true)) then
        return false, "applying"
    end
    local relevant, _, _, disposition = self:IsSpecialRefreshRelevant(kind)
    if relevant ~= true then
        return false, disposition
    end
    if EXTERNAL_SPECIAL_BARS[kind] and InCombat() then
        if self.pendingExternalSpecialBars[kind] ~= nil then
            return false, "duplicate-pending"
        end
        self.pendingExternalSpecialBars[kind] = reason or "external special refresh"
        return true, "combat-pending"
    end
    self:MarkReason(reason, kind or "special", true, "special")
    self.dirtySpecialBars[kind] = true
    if HotDiagnostics and HotDiagnostics.enabled then
        HotDiagnostics:RecordRefreshQueue(reason, kind or "special", "special")
    end
    self:ScheduleRefresh()
    return true, "queued"
end

function BarManager:RefreshDynamicSpecialLayoutsForEditMode(reason)
    local db = GetDB()
    if not db then return false end
    local refreshed = false
    for _, kind in ipairs(SPECIAL_NATIVE_SUPPRESSION_KINDS) do
        if MANAGED_SPECIAL_BUTTON_KINDS[kind] then
            local config = GetSpecialConfig(db, kind)
            if config and config.enabled == true then
                local record = self.bars and self.bars[kind]
                if not record and self.runtimeActive and not InCombat() then
                    if kind == "pet" then
                        record = self:CreatePetBar(config, db)
                    elseif kind == "stance" then
                        record = self:CreateStanceBar(config, db)
                    elseif kind == "possess" and not (YAB.Adapter and YAB.Adapter.UseMainActionBarForPossess and YAB.Adapter:UseMainActionBarForPossess()) then
                        record = self:CreatePossessBar(config, db)
                    end
                end
                if record then
                    if InCombat() then
                        self:QueueSpecialRefresh(kind, reason or "layout-edit")
                    else
                        self:AttachConfigSnapshot(record, kind, config, "special")
                        self:RefreshSpecialRecord(kind, db)
                        if YAB.LayoutBridge and YAB.LayoutBridge.Refresh then
                            YAB.LayoutBridge:Refresh(kind)
                        end
                    end
                    refreshed = true
                end
            end
        end
    end
    return refreshed
end

function BarManager:OnLayoutEditModeChanged(event)
    if self.runtimeActive ~= true or not self:IsSpecialGroupingActive() then return false end
    local reason = event == "YUI_LAYOUT_EDIT_MODE_OPENED"
        and "layout edit mode opened"
        or "layout edit mode closed"
    return self:ApplySpecialActionGrouping(reason)
end

function BarManager:RegisterLayoutEditHooks()
    local registered = false
    if not self.layoutEditEventListenersRegistered
        and type(YAB.RegisterLayoutEditEventListeners) == "function" then
        if YAB:RegisterLayoutEditEventListeners(self) then
            self.layoutEditEventListenersRegistered = true
            registered = true
        end
    end
    return registered
end

function BarManager:QueueFullRefresh(reason)
    reason = reason or "refresh"
    self:InvalidateProcIndex(reason, "full")
    self:MarkReason(reason, "full")
    if self.fullRefreshPending ~= true then
        self.pendingFullRefreshReason = reason
    end
    self.fullRefreshPending = true
    if HotDiagnostics and HotDiagnostics.enabled then
        HotDiagnostics:RecordRefreshQueue(reason, "full", "full")
    end
    self:ScheduleRefresh()
end

function BarManager:QueueSettingsRefresh(barId, scope)
    scope = scope or "full"
    if not barId or scope == "full" or not SETTING_REFRESH_SCOPES[scope] then
        self:QueueFullRefresh("settings")
        return
    end
    if SettingScopeHas(scope, "layout") then
        self:InvalidateProcIndex("settings layout", "full")
    end
    self:MarkReason("settings", "settings-" .. scope)
    self.dirtySettingBars[barId] = MergeSettingScope(self.dirtySettingBars[barId], scope)
    if HotDiagnostics and HotDiagnostics.enabled then
        HotDiagnostics:RecordRefreshQueue("settings", scope, "settings")
    end
    self:ScheduleRefresh()
end

function BarManager:ClearDirtyRefresh()
    ClearTable(self.dirtySlots)
    ClearTable(self.dirtySpecialBars)
    ClearTable(self.dirtySettingBars)
    ClearTable(self.dirtyReasons)
    ClearTable(self.processingDirtySlots)
    ClearTable(self.processingDirtySpecialBars)
    ClearTable(self.processingDirtySettingBars)
    ClearTable(self.pendingExternalSpecialBars)
    self.dirtyActionMode = nil
    self.dirtyMainPageIdentity = false
    self.dirtyGlobalIcon = false
    self.fullRefreshPending = false
    self.pendingFullRefreshReason = nil
    self.auraDirty = false
end

function BarManager:HandleRangeUpdate(slot, inRange, checksRange, diagnostic)
    local numberSlot = tonumber(slot)
    if not numberSlot then
        if diagnostic then diagnostic.fallbacks = diagnostic.fallbacks + 1 end
        self:QueueActionRefresh("range", "range")
        return
    end

    local checks = NormalizeEventBoolean(checksRange)
    local range = NormalizeEventBoolean(inRange)
    local outOfRange
    if checks == false or range == nil then
        outOfRange = nil
    else
        outOfRange = range == false
    end
    local slotTracked = self.rangeCheckEnabled[numberSlot] == true
    if slotTracked and self.rangeOut[numberSlot] == outOfRange then
        return
    end

    local extraButton = _G.ExtraActionButton1
    local extraHolder = _G.ExtraActionBarFrame
    local extraAction = extraButton and GetButtonAction(extraButton) or nil
    local extraMatches = extraAction == numberSlot
    local extraSnapshot = extraMatches and GetButtonConfigSnapshot(self, extraButton, "extraAction") or nil
    local extraTracked = extraMatches and IsRangeSnapshotEnabled(extraSnapshot)
    if not slotTracked and not extraTracked then
        self.rangeOut[numberSlot] = nil
        return
    end
    if self.rangeOut[numberSlot] == outOfRange then return end
    self.rangeOut[numberSlot] = outOfRange
    if diagnostic then diagnostic.changes = diagnostic.changes + 1 end

    local currentInRange = outOfRange == nil and nil or not outOfRange
    local list = self.slotButtons and self.slotButtons[numberSlot]
    if list then
        for index = 1, #list do
            if diagnostic then diagnostic.candidates = diagnostic.candidates + 1 end
            local button = list[index]
            if button then
                local meta = GetButtonMeta(button)
                local snapshot = GetButtonConfigSnapshot(self, button)
                if IsRangeSnapshotEnabled(snapshot) then
                    if diagnostic then diagnostic.buttons = diagnostic.buttons + 1 end
                    local state = self.buttonStates and self.buttonStates[button]
                    local usable = not state or state.usable ~= false
                    local noMana = state and state.noMana == true or false
                    local writes = ApplyActionTintState(self, button, usable, noMana, currentInRange, snapshot, IsButtonVisible(button, meta and meta.holder))
                    if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
                end
            end
        end
    end
    if extraTracked then
        if diagnostic then
            diagnostic.candidates = diagnostic.candidates + 1
            diagnostic.buttons = diagnostic.buttons + 1
        end
        local state = self.buttonStates and self.buttonStates[extraButton]
        local usable = not state or state.usable ~= false
        local noMana = state and state.noMana == true or false
        local writes = ApplyActionTintState(self, extraButton, usable, noMana, currentInRange, extraSnapshot, IsButtonVisible(extraButton, extraHolder))
        if diagnostic then diagnostic.writes = diagnostic.writes + (writes or 0) end
    end
    return true
end

local function OwnedActionHolderOnShow()
    if BarManager.runtimeActive ~= true then return end
    BarManager:MarkDirectActionListDirty()
    BarManager:QueueActionRefresh("action holder shown", "full")
end

function BarManager:PrepareFrames(record, id, config, secure)
    local mover, moverReason = YAB.SecureFactory:CreateMover(id, config)
    if not mover then return nil, moverReason end
    local holder, holderReason = YAB.SecureFactory:CreateHolder(id, config, secure)
    if not holder then return nil, holderReason end
    local controller, controllerReason = YAB.SecureFactory:CreateBarController(id, holder, mover)
    if not controller then return nil, controllerReason end
    holder:SetParent(mover)
    holder:ClearAllPoints()
    holder:SetPoint("CENTER", mover, "CENTER", 0, 0)
    holder:Show()
    mover:Show()
    record.mover = mover
    record.holder = holder
    record.controller = controller
    if record.kind == "action" and holder.SetScript then
        holder:SetScript("OnShow", OwnedActionHolderOnShow)
    end
    return holder
end

function BarManager:ReleaseActionButton(barId, index, button)
    if not button then return end
    self:ClearButtonCheckedState(button)
    if YAB.SecureFactory and YAB.SecureFactory.UnregisterNativeActionCooldown then
        YAB.SecureFactory:UnregisterNativeActionCooldown(button)
    end
    self:UnmapButtonProc(button)
    self:UnmapButtonSlot(button)
    self.buttonStates[button] = nil
    if self.nativeCoreState then
        self.nativeCoreState[button] = nil
    end
    SetButtonConfigSnapshot(self, button, nil)
    if YAB.Keybinds and YAB.Keybinds.GetButtonKey then
        self.buttonsByKey[YAB.Keybinds:GetButtonKey(barId, index)] = nil
    end
    SetManagedActionButtonShown(self, button, false)
end

function BarManager:ReconcileActionBarButtons(barId, record, config, pageState)
    if not (barId and record and record.kind == "action" and config) then return true, false end
    local snapshot = record.configSnapshot or self:GetConfigSnapshot(barId)
    local count = GetConfiguredButtonCount(config, snapshot)
    local buttons = record.buttons or {}
    record.buttons = buttons
    local page = self:GetActionPageForRecord(barId, record, config, pageState)
    local identityWillChange = #buttons ~= count
    if not identityWillChange then
        for index = 1, count do
            local button = buttons[index]
            local meta = GetButtonMeta(button)
            local expectedSlot = YAB.Adapter and YAB.Adapter:GetActionSlot(page, index) or (meta and meta.slot)
            if not button or not meta or meta.barId ~= barId or meta.index ~= index or meta.slot ~= expectedSlot then
                identityWillChange = true
                break
            end
        end
    end
    if identityWillChange then
        self:InvalidateProcIndex("action button reconciliation", "full")
    end
    record.activeButtonCount = count
    if InCombat() then
        record.pendingButtonCount = count
        self.buttonCountPending = true
        return false
    end

    record.page = page
    local changed = false
    for index = 1, count do
        local button = buttons[index]
        if not button then
            local buttonReason
            button, buttonReason = YAB.SecureFactory:CreateActionButton(record.holder, record.controller, barId, index, page)
            if not button then
                return false, buttonReason
            end
            InstallNativeCoreCooldownDone(button)
            buttons[index] = button
            changed = true
        else
            local meta = GetButtonMeta(button)
            local expectedSlot = YAB.Adapter and YAB.Adapter:GetActionSlot(page, index) or (meta and meta.slot)
            if not meta or meta.barId ~= barId or meta.index ~= index or meta.slot ~= expectedSlot then
                YAB.SecureFactory:SyncActionButtonState(button, record.holder, record.controller, barId, index, page)
            end
        end
        SetButtonConfigSnapshot(self, button, snapshot)
        SetManagedActionButtonShown(self, button, true)
        if YAB.Keybinds and YAB.Keybinds.GetButtonKey then
            local buttonKey = YAB.Keybinds:GetButtonKey(barId, index)
            self.buttonsByKey[buttonKey] = button
            if YAB.Keybinds.HookButton then
                YAB.Keybinds:HookButton(button, buttonKey)
            end
        end
    end

    for index = #buttons, count + 1, -1 do
        local button = buttons[index]
        if button then
            self:ReleaseActionButton(barId, index, button)
            buttons[index] = nil
            changed = true
        end
    end

    record.pendingButtonCount = nil
    self.buttonCountPending = nil
    if changed then
        self:MarkDirectActionListDirty()
        if barId == "main" and YAB.Drivers then
            YAB.Drivers:RegisterMainPaging(record.holder, buttons)
        end
    end
    return true, changed
end

function BarManager:CreateSpecialButton(kind, holder, index)
    if not (YAB.SecureFactory and holder and index) then return nil, "special button factory unavailable" end
    if kind == "pet" then
        return YAB.SecureFactory:CreatePetButton(holder, index)
    elseif kind == "stance" then
        return YAB.SecureFactory:CreateStanceButton(holder, index)
    elseif kind == "possess" then
        return YAB.SecureFactory:CreatePossessButton(holder, index)
    end
    return nil, "unsupported special bar"
end

function BarManager:MapSpecialButtonKey(kind, index, button)
    if not (YAB.Keybinds and YAB.Keybinds.GetButtonKey and kind and index) then return end
    local buttonKey = YAB.Keybinds:GetButtonKey(kind, index)
    self.buttonsByKey[buttonKey] = button
    if button and YAB.Keybinds.HookButton then
        YAB.Keybinds:HookButton(button, buttonKey)
    end
end

function BarManager:UnmapSpecialButtonKey(kind, index)
    if not (YAB.Keybinds and YAB.Keybinds.GetButtonKey and kind and index) then return end
    self.buttonsByKey[YAB.Keybinds:GetButtonKey(kind, index)] = nil
end

function BarManager:ReconcileSpecialButtons(kind, record, config)
    if not (kind and record and IsManagedSpecialButtonRecord(record) and config) then return true, false end
    local snapshot = record.configSnapshot or self:GetConfigSnapshot(kind)
    local count = GetManagedSpecialButtonCount(kind, config, snapshot)
    local buttons = record.buttons or {}
    record.buttons = buttons

    local needsChange = #buttons < count
    if not needsChange then
        for index = 1, count do
            local button = buttons[index]
            if button and button.IsShown and not button:IsShown() then
                needsChange = true
                break
            end
        end
    end
    if not needsChange then
        for index = count + 1, #buttons do
            local button = buttons[index]
            if button and (not button.IsShown or button:IsShown()) then
                needsChange = true
                break
            end
        end
    end

    if InCombat() then
        if needsChange or record.activeButtonCount ~= count then
            if record.pendingButtonCount == nil then
                record.pendingButtonCount = count
            end
            record.layoutPending = true
            self.buttonCountPending = true
        end
        return false, false, count
    end

    local changed = false
    for index = 1, count do
        local button = buttons[index]
        if not button then
            local reason
            button, reason = self:CreateSpecialButton(kind, record.holder, index)
            if not button then
                return false, reason or "special button unavailable", count
            end
            buttons[index] = button
            changed = true
        end
        SetButtonConfigSnapshot(self, button, snapshot)
        self:MapSpecialButtonKey(kind, index, button)
        if button.IsShown and not button:IsShown() then
            changed = true
        end
    end

    for index = count + 1, #buttons do
        local button = buttons[index]
        if button then
            if kind == "stance" then
                UnmapNativeCoreCooldownDone(button)
                self.nativeCoreState[button] = nil
            end
            SetButtonConfigSnapshot(self, button, nil)
            self:UnmapSpecialButtonKey(kind, index)
            if button.Hide and (not button.IsShown or button:IsShown()) then
                SetManagedActionButtonShown(self, button, false)
                changed = true
            else
                self.emptyButtonShown[button] = false
                self.pendingEmptyButtonShown[button] = nil
            end
        end
    end

    record.activeButtonCount = count
    record.pendingButtonCount = nil
    self.buttonCountPending = nil
    if changed and YAB.Keybinds and YAB.Keybinds.ApplyRuntimeBindings then
        YAB.Keybinds:ApplyRuntimeBindings(true)
    end
    return true, changed, count
end

function BarManager:MeasureLayoutGrid(count, rows, spacing, buttonWidth, buttonHeight)
    rows = math.max(1, math.min(math.floor(rows), count))
    local columns = math.max(math.ceil(count / rows), 1)
    return math.max(1, columns * buttonWidth + (columns - 1) * spacing),
        math.max(1, rows * buttonHeight + (rows - 1) * spacing), rows, columns
end

-- Pure geometry: no config snapshots, buttons, DB normalization or runtime startup.
function BarManager:MeasureDormantActionBar(config)
    config = config or {}
    local count = math.floor(SnapshotNumber(config.buttons, 12, 1, 12))
    local rows = SnapshotNumber(config.rows, 1, 1, count)
    local size = SnapshotNumber(config.size, 36, 1, 128)
    local height = size
    local aspect = LAYOUT_SKIN_ASPECTS[config.skin]
    if aspect then
        height = math.max(1, math.floor(size / aspect + 0.5))
    end
    return self:MeasureLayoutGrid(count, rows, SnapshotNumber(config.spacing, 4, -10, 64), size, height)
end

function BarManager:ApplyLayout(record, config, db)
    if not record or not record.holder then return end
    if InCombat() then
        record.layoutPending = true
        return
    end
    local snapshot = record.configSnapshot or (record.id and self:GetConfigSnapshot(record.id)) or DEFAULT_CONFIG_SNAPSHOT
    local managedCount = record.kind == "action" and GetConfiguredButtonCount(config, snapshot) or GetManagedSpecialButtonCount(record.kind, config, snapshot)
    local layoutButtons, layoutButtonCount, layoutSignature = BuildLayoutButtons(record, managedCount)
    local count = managedCount
    if IsCompactSpecialLayoutRecord(record) then
        count = math.max(layoutButtonCount or 0, 1)
    end
    local rows = math.floor(tonumber(snapshot and snapshot.rows) or GetRows(config))
    if rows < 1 then rows = 1 end
    if rows > count then rows = count end
    local spacing = tonumber(snapshot and snapshot.spacing)
    if spacing == nil then spacing = GetSpacing(config, db) end
    local buttonWidth, buttonHeight, size = GetLayoutButtonSize(config, snapshot, db)
    local width, height, columns
    width, height, rows, columns = self:MeasureLayoutGrid(count, rows, spacing, buttonWidth, buttonHeight)

    record.layoutWidth = width
    record.layoutHeight = height
    if record.mover then
        record.mover:SetSize(width, height)
        record.mover:Show()
    end
    record.holder:SetSize(width, height)
    self:UpdateMouseoverAlpha(record)
    if record.mover then
        record.holder:ClearAllPoints()
        record.holder:SetPoint("CENTER", record.mover, "CENTER", 0, 0)
    end

    local alignment = NormalizeAlignment(snapshot and snapshot.alignment, record.id == "stance" and "center" or "left")
    if layoutSignature ~= nil then
        record.layoutVisibleSignature = layoutSignature
        record.layoutVisibleCount = layoutButtonCount
    end

    for _, button in ipairs(record.buttons or {}) do
        button:SetSize(buttonWidth, buttonHeight)
        if YAB.Skins and button ~= record.recoveryButton then
            snapshot = record.configSnapshot or GetButtonConfigSnapshot(self, button)
            local skin = YAB.Skins:Normalize("default")
            YAB.Skins:ApplyButton(button, skin, { size = size, width = buttonWidth, height = buttonHeight, zoom = snapshot.iconZoom, snapshot = snapshot })
        end
    end

    local positionCount = math.min(layoutButtonCount or 0, count)
    for position = 1, positionCount do
        local button = layoutButtons and layoutButtons[position]
        if button then
            local row = math.floor((position - 1) / columns)
            local col = (position - 1) % columns
            local rowCount = math.min(columns, positionCount - (row * columns))
            local rowWidth = (rowCount * buttonWidth) + (math.max(rowCount - 1, 0) * spacing)
            local offsetX = 0
            if alignment == "center" then
                offsetX = math.floor(((width - rowWidth) * 0.5) + 0.5)
            elseif alignment == "right" then
                offsetX = width - rowWidth
            end
            if offsetX < 0 then offsetX = 0 end
            local x = offsetX + (col * (buttonWidth + spacing))
            local y = -(row * (buttonHeight + spacing))
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", record.holder, "TOPLEFT", x, y)
        end
    end
    if YAB.SecureFactory and YAB.SecureFactory.ConfigureBarController then
        YAB.SecureFactory:ConfigureBarController(record.controller, record, config, width, height)
    end
    if record.kind == "action" then
        self:MarkDirectActionListDirty()
    end
    record.layoutPending = nil
    if record.id and YAB.LayoutBridge and YAB.LayoutBridge.Refresh then
        YAB.LayoutBridge:Refresh(record.id)
    end
end

function BarManager:DeactivateBar(barId, options)
    local record = self.bars and self.bars[barId]
    if not record then return false end
    local externalSpecial = EXTERNAL_SPECIAL_BARS and EXTERNAL_SPECIAL_BARS[barId] == true
    if record.kind == "action" then
        self:InvalidateProcIndex("action bar deactivate", "full")
    end
    options = options or {}
    local restoreNativeSpecial = options.restoreNativeSpecial == true
    local buttons = record.buttons or {}
    local factory = YAB.SecureFactory
    if self.ReleaseMouseoverFade then
        self:ReleaseMouseoverFade(record)
    end
    if record.externalFrames or record.externalButtons then
        self:RestoreExternalRecord(record)
    end
    if self.ResetMouseoverProxy then
        self:ResetMouseoverProxy(record)
    end
    if record.holder and self.mouseoverRecords then
        self.mouseoverRecords[record.holder] = nil
    end
    for index, button in ipairs(buttons) do
        if button then
            if record.kind == "stance" then
                UnmapNativeCoreCooldownDone(button)
                self.nativeCoreState[button] = nil
            end
            if self.mouseoverRecords then
                self.mouseoverRecords[button] = nil
            end
            if record.kind == "action" and factory and factory.UnregisterNativeActionCooldown then
                factory:UnregisterNativeActionCooldown(button)
            end
            self:UnmapButtonProc(button)
            self:UnmapButtonSlot(button)
            self.buttonStates[button] = nil
            SetButtonConfigSnapshot(self, button, nil)
            if YAB.Keybinds and YAB.Keybinds.GetButtonKey then
                self.buttonsByKey[YAB.Keybinds:GetButtonKey(barId, index)] = nil
            end
            if restoreNativeSpecial and IsNativeSpecialButton(button) and factory and factory.RestoreNativeSpecialButton then
                factory:RestoreNativeSpecialButton(button)
            elseif record.kind == "action" then
                SetManagedActionButtonShown(self, button, false)
            elseif button.Hide then
                button:Hide()
            end
            buttons[index] = nil
        end
    end
    if record.kind == "action"
        and record.holder
        and record.holder.GetScript
        and record.holder.SetScript
        and record.holder:GetScript("OnShow") == OwnedActionHolderOnShow then
        record.holder:SetScript("OnShow", nil)
    end
    if record.controller then record.controller:Hide() end
    if record.visibilityHandle and YUI.Visibility then
        YUI.Visibility:Release(record.visibilityHandle)
        record.visibilityHandle = nil
    end
    if record.holder then record.holder:Hide() end
    if record.mover then record.mover:Hide() end
    if YAB.LayoutBridge and YAB.LayoutBridge.Unregister then
        YAB.LayoutBridge:Unregister(barId, externalSpecial)
    end
    record.configSnapshot = nil
    self.bars[barId] = nil
    if externalSpecial and self.runtimeActive == true then
        self:EnsureExternalSpecialMoverProxy(barId, GetDB())
        self:SyncSpecialLayoutOwnership(GetDB(), barId)
        self:ApplySpecialActionGrouping("special bar deactivated")
    end
    if record.kind == "action" then
        self:MarkDirectActionListDirty()
    end
    return true
end

local function IsActionBarId(barId)
    for _, id in ipairs(YAB.BAR_ORDER or {}) do
        if id == barId then return true end
    end
    return false
end

EXTERNAL_SPECIAL_BARS = {
    extraAction = true,
    zoneAbility = true,
    vehicleExit = true,
}

local EXTERNAL_SPECIAL_DEFINITIONS = {
    extraAction = {
        frames = { "ExtraActionBarFrame" },
        buttons = { "ExtraActionButton1" },
        baseSize = 52,
    },
    zoneAbility = {
        frames = { "ZoneAbilityFrame" },
        baseSize = 52,
        dynamicButtons = "zone",
    },
    vehicleExit = {
        buttons = { "MainMenuBarVehicleLeaveButton", "VehicleExitButton" },
        baseSize = 32,
    },
}
BarManager.retailNativeEditModeSystems = BarManager.retailNativeEditModeSystems or {
    "MainActionBar",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarLeft",
    "MultiBarRight",
    "MultiBar5",
    "MultiBar6",
    "MultiBar7",
}
BarManager.specialGroupId = YAB.SPECIAL_GROUP_ID or "specialActionsGroup"
BarManager.specialGroupOrder = BarManager.specialGroupOrder or { "zoneAbility", "extraAction", "vehicleExit" }
local EXTERNAL_FRAME_SCRATCH = {}
local EXTERNAL_BUTTON_SCRATCH = {}

local EXTERNAL_TEXT_NIL = {}
local EXTERNAL_TEXT_FIELDS = { "HotKey", "Count", "Name" }

function BarManager:CaptureSpecialGroupingMode(db)
    self.specialGroupingMode = YAB.GetSpecialGroupingMode
        and YAB:GetSpecialGroupingMode(db)
        or (YAB.SPECIAL_GROUPING_MODE_INDEPENDENT or "independent")
    local config = YAB.GetSpecialGroupConfig and YAB:GetSpecialGroupConfig(db) or nil
    self.specialGroupConfig = config and YAB.CopyValue and YAB:CopyValue(config) or config
    if self.specialGroupConfig then
        self.specialGroupConfig.growthDirection = YAB.NormalizeSpecialGroupGrowthDirection
            and YAB:NormalizeSpecialGroupGrowthDirection(self.specialGroupConfig.growthDirection)
            or "up"
        self.specialGroupConfig.groupAlignment = YAB.NormalizeSpecialGroupAlignment
            and YAB:NormalizeSpecialGroupAlignment(self.specialGroupConfig.groupAlignment)
            or "center"
    end
    return self.specialGroupingMode
end

function BarManager:RefreshSpecialGroupingRuntime(db, reason, forcePlacementRefresh)
    db = db or GetDB()
    if not db then return false, "missing db" end
    local previousMode = self:GetSpecialGroupingMode()
    self:CaptureSpecialGroupingMode(db)
    local modeChanged = previousMode ~= self:GetSpecialGroupingMode() or forcePlacementRefresh == true
    if self.runtimeActive ~= true then
        return true, modeChanged
    end
    self:RefreshNativeEditModeClaims()
    if InCombat() then
        self.specialGroupingRefreshPending = true
        self.specialGroupingPlacementPending = self.specialGroupingPlacementPending == true or modeChanged
        for _, kind in ipairs(self.specialGroupOrder) do
            self.pendingStructuralBars[kind] = reason or "special grouping settings"
        end
        return false, "combat deferred"
    end

    self.specialGroupingRefreshPending = false
    self.specialGroupingPlacementPending = false
    self:PrepareSpecialGroupingMoverFrames(db)
    for _, kind in ipairs(self.specialGroupOrder) do
        local snapshot = self:RefreshConfigSnapshot(kind, db)
        local record = self.bars and self.bars[kind]
        local config = GetSpecialConfig(db, kind)
        if record then
            record.configSnapshot = snapshot
            if config and config.enabled == true then
                self:ApplyExternalSpecialLayout(record, config, db)
            end
        end
    end
    if modeChanged and YAB.LayoutBridge and YAB.LayoutBridge.ReapplySpecialGroupingPlacements then
        YAB.LayoutBridge:ReapplySpecialGroupingPlacements()
    end
    if YAB.LayoutBridge and YAB.LayoutBridge.RefreshSpecialGrouping then
        YAB.LayoutBridge:RefreshSpecialGrouping()
    end
    self:ApplyVisibility()
    return true, modeChanged
end

function BarManager:GetSpecialGroupingMode()
    local preview = self.specialGroupDevPreview
    if preview and preview.active == true then
        return YAB.SPECIAL_GROUPING_MODE_ALL or "all"
    end
    return YAB.NormalizeSpecialGroupingMode
        and YAB:NormalizeSpecialGroupingMode(self.specialGroupingMode)
        or (self.specialGroupingMode == "all" or self.specialGroupingMode == "abilities") and self.specialGroupingMode
        or "independent"
end

function BarManager:IsSpecialGroupingActive()
    return self:GetSpecialGroupingMode() ~= (YAB.SPECIAL_GROUPING_MODE_INDEPENDENT or "independent")
end

function BarManager:IsSpecialGroupedKind(kind)
    return YAB.IsSpecialBarGrouped
        and YAB:IsSpecialBarGrouped(kind, self:GetSpecialGroupingMode()) == true
        or false
end

local function HasExternalSpecialAttachment(record)
    if not record then return false end
    if record.externalPrimary then return true end
    local frames = record.externalFrames
    if frames and frames[1] then return true end
    local buttons = record.externalButtons
    return buttons and buttons[1] ~= nil or false
end

function BarManager:RefreshNativeEditModeClaims()
    local layout = YUI.Layout
    if not (layout and type(layout.SetNativeEditModeClaim) == "function") then return false end

    local preview = self.specialGroupDevPreview
    local active = self.runtimeActive == true and not (preview and preview.active == true)
    local db = GetDB()
    local extraConfig = GetSpecialConfig(db, "extraAction")
    local zoneConfig = GetSpecialConfig(db, "zoneAbility")
    local vehicleConfig = GetSpecialConfig(db, "vehicleExit")
    local abilitiesWanted = active
        and ((extraConfig and extraConfig.enabled == true
                and self.bars and HasExternalSpecialAttachment(self.bars.extraAction))
            or (zoneConfig and zoneConfig.enabled == true
                and self.bars and HasExternalSpecialAttachment(self.bars.zoneAbility)))
    local vehicleWanted = active
        and vehicleConfig
        and vehicleConfig.enabled == true
        and self.bars
        and HasExternalSpecialAttachment(self.bars.vehicleExit)
    local abilitiesFrame = abilitiesWanted and _G.ExtraAbilityContainer or nil
    local vehicleFrame = vehicleWanted and (_G.MainMenuBarVehicleLeaveButton or _G.VehicleExitButton) or nil

    local ordinaryFrames = self.nativeEditModeOrdinaryFrames
    if not ordinaryFrames then
        ordinaryFrames = {}
        self.nativeEditModeOrdinaryFrames = ordinaryFrames
    end
    local nativeSystems = self.retailNativeEditModeSystems
    for index = 1, #nativeSystems do
        local name = nativeSystems[index]
        local wanted = active and YAB.Client.nonStructuralNativeSuppression == true and _G[name] or nil
        local current = ordinaryFrames[name]
        if current ~= wanted then
            if current then layout:SetNativeEditModeClaim(self, current, false) end
            if wanted then layout:SetNativeEditModeClaim(self, wanted, true) end
            ordinaryFrames[name] = wanted
        end
    end

    local currentAbilities = self.nativeEditModeAbilitiesFrame
    if currentAbilities ~= abilitiesFrame then
        if currentAbilities then layout:SetNativeEditModeClaim(self, currentAbilities, false) end
        if abilitiesFrame then layout:SetNativeEditModeClaim(self, abilitiesFrame, true) end
        self.nativeEditModeAbilitiesFrame = abilitiesFrame
    end

    local currentVehicle = self.nativeEditModeVehicleFrame
    if currentVehicle ~= vehicleFrame then
        if currentVehicle then layout:SetNativeEditModeClaim(self, currentVehicle, false) end
        if vehicleFrame then layout:SetNativeEditModeClaim(self, vehicleFrame, true) end
        self.nativeEditModeVehicleFrame = vehicleFrame
    end
    return true
end

function BarManager:GetSpecialGroupGrowthDirection()
    local value = self.specialGroupConfig and self.specialGroupConfig.growthDirection
    return YAB.NormalizeSpecialGroupGrowthDirection
        and YAB:NormalizeSpecialGroupGrowthDirection(value)
        or (value == "down" or value == "left" or value == "right") and value
        or "up"
end

function BarManager:GetSpecialGroupAlignment()
    local value = self.specialGroupConfig and self.specialGroupConfig.groupAlignment
    return YAB.NormalizeSpecialGroupAlignment
        and YAB:NormalizeSpecialGroupAlignment(value)
        or (value == "start" or value == "end") and value
        or "center"
end

function BarManager:GetExternalSpecialGrowthDirection(kind)
    if kind == "zoneAbility" and self:IsSpecialGroupedKind(kind) then
        return self:GetSpecialGroupGrowthDirection()
    end
    return "right"
end

function BarManager:GetSpecialMemberMover(kind)
    local record = self.bars and self.bars[kind]
    if record and record.mover then return record.mover end
    local proxy = self.specialMoverProxies and self.specialMoverProxies[kind]
    return proxy and proxy.mover or nil
end

function BarManager:EnsureExternalSpecialMoverProxy(kind, db)
    if not EXTERNAL_SPECIAL_BARS[kind] then return nil end
    local factory = YAB.SecureFactory
    if not (factory and factory.CreateMover) then return nil end
    db = db or GetDB()
    local memberConfig = GetSpecialConfig(db, kind)
    local config = self:GetRuntimeSpecialPresentationConfig(kind, memberConfig)
    if not config then return nil end
    local mover = factory:CreateMover(kind, config)
    if not mover then return nil end
    local proxy = self.specialMoverProxies[kind] or { id = kind, kind = kind, proxy = true }
    local size = tonumber(config.size) or (EXTERNAL_SPECIAL_DEFINITIONS[kind] and EXTERNAL_SPECIAL_DEFINITIONS[kind].baseSize) or 24
    proxy.mover = mover
    proxy.layoutWidth = size
    proxy.layoutHeight = size
    self.specialMoverProxies[kind] = proxy
    mover:SetSize(size, size)
    return proxy
end

function BarManager:PrepareSpecialGroupingMoverFrames(db)
    db = db or GetDB()
    for _, kind in ipairs(self.specialGroupOrder) do
        self:EnsureExternalSpecialMoverProxy(kind, db)
    end
    local factory = YAB.SecureFactory
    if not (factory and factory.CreateMover) then return nil end
    local mover = factory:CreateMover(self.specialGroupId, self.specialGroupConfig)
    if not mover then return nil end
    local record = self.specialGroupRecord or { id = self.specialGroupId, kind = "specialGroup" }
    record.mover = mover
    record.config = self.specialGroupConfig
    record.layoutWidth = tonumber(record.layoutWidth) or 24
    record.layoutHeight = tonumber(record.layoutHeight) or 24
    mover:SetSize(record.layoutWidth, record.layoutHeight)
    self.specialGroupRecord = record
    self:SyncSpecialLayoutOwnership(db)
    return record
end

function BarManager:SyncSpecialLayoutOwnership(db, forceMemberKind)
    local bridge = YAB.LayoutBridge
    if not (bridge and bridge.IsRegistered and bridge.Unregister) then
        return false, "layout bridge unavailable"
    end
    db = db or GetDB()
    local changed = 0
    for _, kind in ipairs(self.specialGroupOrder) do
        if self:IsSpecialGroupedKind(kind) then
            if bridge:IsRegistered(kind) and bridge:Unregister(kind, true) then
                changed = changed + 1
            end
        else
            local config = GetSpecialConfig(db, kind)
            local record = self.bars and self.bars[kind]
                or self.specialMoverProxies and self.specialMoverProxies[kind]
            if record and config
                and (forceMemberKind == kind or not bridge:IsRegistered(kind))
                and bridge.Register
                and bridge:Register(kind, record, config.label or kind, config) then
                changed = changed + 1
            end
        end
    end

    if self:IsSpecialGroupingActive() then
        if self.specialGroupRecord
            and not bridge:IsRegistered(self.specialGroupId)
            and bridge.RegisterSpecialGroup
            and bridge:RegisterSpecialGroup(self.specialGroupRecord, function()
                return BarManager:GetSpecialGroupDefaultPlacement()
            end) then
            changed = changed + 1
        end
    elseif bridge:IsRegistered(self.specialGroupId)
        and bridge:Unregister(self.specialGroupId, true) then
        changed = changed + 1
    end
    return true, changed
end

function BarManager:GetSpecialGroupDefaultPlacement()
    local db = GetDB()
    local direction = self:GetSpecialGroupGrowthDirection()
    for _, kind in ipairs(self.specialGroupOrder) do
        if self:IsSpecialGroupedKind(kind) then
            local config = GetSpecialConfig(db, kind)
            if config and config.enabled ~= false then
                local mover = self:GetSpecialMemberMover(kind)
                local centerX, centerY
                if mover and mover.GetCenter then
                    centerX, centerY = mover:GetCenter()
                end
                local width = mover and mover.GetWidth and mover:GetWidth() or tonumber(config.size) or 24
                local height = mover and mover.GetHeight and mover:GetHeight() or tonumber(config.size) or 24
                local x = centerX
                local y = centerY
                if direction == "up" then
                    y = mover and mover.GetBottom and mover:GetBottom() or (centerY and centerY - height * 0.5)
                elseif direction == "down" then
                    y = mover and mover.GetTop and mover:GetTop() or (centerY and centerY + height * 0.5)
                elseif direction == "left" then
                    x = mover and mover.GetRight and mover:GetRight() or (centerX and centerX + width * 0.5)
                elseif direction == "right" then
                    x = mover and mover.GetLeft and mover:GetLeft() or (centerX and centerX - width * 0.5)
                end
                if x and y then
                    local parentLeft = UIParent and UIParent.GetLeft and UIParent:GetLeft() or 0
                    local parentBottom = UIParent and UIParent.GetBottom and UIParent:GetBottom() or 0
                    local point = direction == "up" and "BOTTOM"
                        or direction == "down" and "TOP"
                        or direction == "right" and "LEFT"
                        or direction == "left" and "RIGHT"
                        or "CENTER"
                    return {
                        point = point,
                        relativeTo = "UIParent",
                        relativePoint = "BOTTOMLEFT",
                        x = x - (parentLeft or 0),
                        y = y - (parentBottom or 0),
                    }
                end
                local layout = config.layout
                if layout then
                    return {
                        point = layout.point or "CENTER",
                        relativeTo = "UIParent",
                        relativePoint = layout.relativePoint or layout.point or "CENTER",
                        x = layout.x or 0,
                        y = layout.y or 0,
                    }
                end
            end
        end
    end
    return {
        point = "CENTER",
        relativeTo = "UIParent",
        relativePoint = "CENTER",
        x = 0,
        y = -180,
    }
end

function BarManager:RegisterSpecialActionGroup()
    local record = self.specialGroupRecord or self:PrepareSpecialGroupingMoverFrames()
    if not record then
        return false
    end
    self:SyncSpecialLayoutOwnership(GetDB())
    local registered = YAB.LayoutBridge
        and YAB.LayoutBridge.IsRegistered
        and YAB.LayoutBridge:IsRegistered(self.specialGroupId)
        or false
    return registered
end

function BarManager:FrameDependsOnSpecialMember(frame, depth)
    if not frame or depth > 32 then return false end
    local visited = self.specialGroupAnchorVisited
    if visited[frame] then return false end
    visited[frame] = true
    local pointCount = frame.GetNumPoints and frame:GetNumPoints() or 0
    for pointIndex = 1, pointCount do
        local _, relativeFrame = frame:GetPoint(pointIndex)
        if relativeFrame then
            for _, kind in ipairs(self.specialGroupOrder) do
                if self:IsSpecialGroupedKind(kind) and relativeFrame == self:GetSpecialMemberMover(kind) then
                    return true
                end
            end
            if relativeFrame ~= UIParent and self:FrameDependsOnSpecialMember(relativeFrame, depth + 1) then
                return true
            end
        end
    end
    return false
end

function BarManager:PreventSpecialGroupAnchorCycle()
    local groupMover = self.specialGroupRecord and self.specialGroupRecord.mover
    if not groupMover then return true end
    ClearTable(self.specialGroupAnchorVisited)
    if not self:FrameDependsOnSpecialMember(groupMover, 0) then
        return true
    end
    local centerX, centerY
    if groupMover.GetCenter then
        centerX, centerY = groupMover:GetCenter()
    end
    if not (centerX and centerY) then return false end
    local parentLeft = UIParent and UIParent.GetLeft and UIParent:GetLeft() or 0
    local parentBottom = UIParent and UIParent.GetBottom and UIParent:GetBottom() or 0
    groupMover:ClearAllPoints()
    groupMover:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX - (parentLeft or 0), centerY - (parentBottom or 0))
    self.specialGroupAnchorFallbacks = (self.specialGroupAnchorFallbacks or 0) + 1
    return true
end

function BarManager:IsExternalSpecialRecordActive(record)
    if not record then return false end
    if YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing() then
        local config = GetSpecialConfig(GetDB(), record.kind)
        return config and config.enabled ~= false or false
    end
    if record.holder and record.holder.IsShown and not record.holder:IsShown() then
        return false
    end
    local primary = record.externalPrimary
    if primary and primary.IsShown and primary:IsShown() then
        return true
    end
    for _, button in ipairs(record.externalButtons or {}) do
        if button and button.IsShown and button:IsShown() then
            return true
        end
    end
    return false
end

function BarManager:ApplySpecialActionGrouping(reason)
    if self.runtimeActive ~= true then
        return false, "inactive"
    end
    if not self.specialGroupRecord then
        self:PrepareSpecialGroupingMoverFrames()
        self:RegisterSpecialActionGroup()
    end
    local groupRecord = self.specialGroupRecord
    local groupMover = groupRecord and groupRecord.mover
    if not groupMover then
        return false, "missing group mover"
    end
    self:RefreshNativeEditModeClaims()
    if InCombat() then
        for _, kind in ipairs(self.specialGroupOrder) do
            if self:IsSpecialGroupedKind(kind) then
                self.pendingStructuralBars[kind] = reason or "special grouping"
            end
        end
        return false, "combat deferred"
    end
    if not self:IsSpecialGroupingActive() then
        groupRecord.layoutWidth = 24
        groupRecord.layoutHeight = 24
        groupMover:SetSize(24, 24)
        groupMover:Hide()
        self.specialGroupActiveMembers = 0
        return true
    end

    groupMover:Show()
    self:PreventSpecialGroupAnchorCycle()
    local db = GetDB()
    local editing = YUI.Layout and YUI.Layout.IsEditing and YUI.Layout:IsEditing() or false
    local groupConfig = self.specialGroupConfig or {}
    local spacing = tonumber(groupConfig.spacing) or 4
    if spacing < -10 then spacing = -10 elseif spacing > 64 then spacing = 64 end
    local direction = self:GetSpecialGroupGrowthDirection()
    local alignment = self:GetSpecialGroupAlignment()
    local devPreview = self.specialGroupDevPreview
    local devPreviewActive = devPreview and devPreview.active == true
    if devPreviewActive and type(devPreview.refresh) == "function" then
        local ok, message = pcall(devPreview.refresh, self, devPreview, direction, spacing)
        devPreview.lastError = ok and nil or tostring(message)
    end
    local vertical = direction == "up" or direction == "down"
    local scratch = self.specialGroupLayoutScratch
    for index = 1, scratch.count or 0 do
        scratch.kinds[index] = nil
        scratch.movers[index] = nil
        scratch.widths[index] = nil
        scratch.heights[index] = nil
    end
    scratch.count = 0
    local activeCount = 0
    local mainLength = 0
    local crossLength = 24
    for _, kind in ipairs(self.specialGroupOrder) do
        if self:IsSpecialGroupedKind(kind) then
            local record = self.bars and self.bars[kind]
            local proxy = self.specialMoverProxies and self.specialMoverProxies[kind]
            local mover = record and record.mover or proxy and proxy.mover
            local config = GetSpecialConfig(db, kind)
            local width = tonumber(record and record.layoutWidth) or tonumber(proxy and proxy.layoutWidth) or tonumber(groupConfig.size) or 24
            local height = tonumber(record and record.layoutHeight) or tonumber(proxy and proxy.layoutHeight) or tonumber(groupConfig.size) or 24
            local active = (devPreviewActive or (config and config.enabled ~= false))
                and (devPreviewActive or editing or self:IsExternalSpecialRecordActive(record))
            if mover then
                mover:ClearAllPoints()
                if active then
                    activeCount = activeCount + 1
                    scratch.count = activeCount
                    scratch.kinds[activeCount] = kind
                    scratch.movers[activeCount] = mover
                    scratch.widths[activeCount] = width
                    scratch.heights[activeCount] = height
                    mainLength = mainLength + (vertical and height or width)
                    local cross = vertical and width or height
                    if cross > crossLength then crossLength = cross end
                else
                    mover:SetPoint("CENTER", groupMover, "CENTER", 0, 0)
                end
            end
        end
    end
    if activeCount > 1 then
        mainLength = mainLength + spacing * (activeCount - 1)
    end
    mainLength = math.max(mainLength, 24)
    groupRecord.layoutWidth = vertical and crossLength or mainLength
    groupRecord.layoutHeight = vertical and mainLength or crossLength
    groupMover:SetSize(groupRecord.layoutWidth, groupRecord.layoutHeight)
    local cursor = 0
    for index = 1, activeCount do
        local mover = scratch.movers[index]
        local width = scratch.widths[index]
        local height = scratch.heights[index]
        local point
        local offsetX = 0
        local offsetY = 0
        if direction == "up" then
            point = alignment == "start" and "BOTTOMLEFT" or alignment == "end" and "BOTTOMRIGHT" or "BOTTOM"
            offsetY = cursor
            cursor = cursor + height + spacing
        elseif direction == "down" then
            point = alignment == "start" and "TOPLEFT" or alignment == "end" and "TOPRIGHT" or "TOP"
            offsetY = -cursor
            cursor = cursor + height + spacing
        elseif direction == "right" then
            point = alignment == "start" and "TOPLEFT" or alignment == "end" and "BOTTOMLEFT" or "LEFT"
            offsetX = cursor
            cursor = cursor + width + spacing
        else
            point = alignment == "start" and "TOPRIGHT" or alignment == "end" and "BOTTOMRIGHT" or "RIGHT"
            offsetX = -cursor
            cursor = cursor + width + spacing
        end
        mover:SetPoint(point, groupMover, point, offsetX, offsetY)
    end
    self.specialGroupActiveMembers = activeCount
    self.specialGroupLayouts = (self.specialGroupLayouts or 0) + 1
    if YAB.LayoutBridge and YAB.LayoutBridge.RefreshSpecialGroup then
        YAB.LayoutBridge:RefreshSpecialGroup()
    end
    return true
end

local function CaptureExternalTextRegion(manager, region, captureText)
    if not (manager and region) then return end
    if manager.externalTextRegionShown[region] == nil and region.IsShown then
        local ok, shown = pcall(region.IsShown, region)
        if ok then manager.externalTextRegionShown[region] = shown == true end
    end
    if manager.externalTextRegionAlpha[region] == nil and region.GetAlpha then
        local ok, alpha = pcall(region.GetAlpha, region)
        if ok and type(alpha) == "number" then manager.externalTextRegionAlpha[region] = alpha end
    end
    if captureText == true and manager.externalHotkeyText[region] == nil and region.GetText then
        local ok, value = pcall(region.GetText, region)
        if ok then manager.externalHotkeyText[region] = value == nil and EXTERNAL_TEXT_NIL or value end
    end
end

local function SetExternalTextRegionVisible(region, shown)
    if not region then return end
    if shown == true then
        if region.SetAlpha then pcall(region.SetAlpha, region, 1) end
        if region.Show then pcall(region.Show, region) end
    elseif region.SetAlpha then
        pcall(region.SetAlpha, region, 0)
    elseif region.Hide then
        pcall(region.Hide, region)
    end
end

local function ApplyExternalButtonTextState(manager, kind, button, index, snapshot, useCachedHotkey)
    if not (manager and button and snapshot) then return end
    local hotkey = button.HotKey
    CaptureExternalTextRegion(manager, hotkey, true)
    CaptureExternalTextRegion(manager, button.Count, false)
    CaptureExternalTextRegion(manager, button.Name, false)

    local showHotkey = snapshot.showHotkeys == true
    if showHotkey and hotkey and hotkey.SetText and YAB.Keybinds and YAB.Keybinds.GetBindingText and YAB.Keybinds.GetButtonKey then
        local text = useCachedHotkey == true and manager.externalHotkeyDisplay[hotkey] or nil
        if text == nil then
            local buttonKey = YAB.Keybinds:GetButtonKey(kind, index)
            text = YAB.Keybinds:GetBindingText(buttonKey) or ""
            manager.externalHotkeyDisplay[hotkey] = text
        end
        pcall(hotkey.SetText, hotkey, text)
    end
    SetExternalTextRegionVisible(hotkey, showHotkey)
    SetExternalTextRegionVisible(button.Count, snapshot.showCounts == true)
    SetExternalTextRegionVisible(button.Name, snapshot.showMacroNames == true)
end

local function EnsureExternalButtonTextHooks(manager, kind, button)
    if kind ~= "extraAction" or not (manager and button) then return false end
    if manager.externalTextHooked[button] then return true end
    if type(hooksecurefunc) ~= "function" or type(button.UpdateHotkeys) ~= "function" then return false end
    local hooked = pcall(hooksecurefunc, button, "UpdateHotkeys", function(frame)
        if BarManager.externalButtonOwners[frame] ~= "extraAction" then return end
        local snapshot = GetButtonConfigSnapshot(BarManager, frame, "extraAction")
        local index = BarManager.externalButtonIndices[frame] or 1
        ApplyExternalButtonTextState(BarManager, "extraAction", frame, index, snapshot, false)
        if YAB.Visuals and YAB.Visuals.ApplyExternalTextSnapshot then
            YAB.Visuals:ApplyExternalTextSnapshot(frame, snapshot)
        end
    end) == true
    if hooked then manager.externalTextHooked[button] = true end
    return hooked
end

local function RestoreExternalTextRegionState(manager, region, restoreText)
    if not (manager and region) then return end
    local shown = manager.externalTextRegionShown[region]
    if shown ~= nil then
        if shown == true then
            if region.Show then pcall(region.Show, region) end
        elseif region.Hide then
            pcall(region.Hide, region)
        end
        manager.externalTextRegionShown[region] = nil
    end
    local alpha = manager.externalTextRegionAlpha[region]
    if alpha ~= nil then
        if region.SetAlpha then pcall(region.SetAlpha, region, alpha) end
        manager.externalTextRegionAlpha[region] = nil
    end
    if restoreText == true then
        local text = manager.externalHotkeyText[region]
        if text ~= nil then
            if region.SetText then
                pcall(region.SetText, region, text == EXTERNAL_TEXT_NIL and nil or text)
            end
            manager.externalHotkeyText[region] = nil
        end
    end
    manager.externalHotkeyDisplay[region] = nil
end

local function RestoreExternalButtonTextState(manager, button)
    if not (manager and button) then return end
    for _, field in ipairs(EXTERNAL_TEXT_FIELDS) do
        RestoreExternalTextRegionState(manager, button[field], field == "HotKey")
    end
end

local function ResolveFirstGlobal(names)
    if not names then return nil end
    for _, name in ipairs(names) do
        local frame = _G[name]
        if frame then return frame, name end
    end
    return nil
end

local function AddUniqueFrame(list, frame)
    if not (list and frame) then return false end
    for index = 1, #list do
        if list[index] == frame then return false end
    end
    list[#list + 1] = frame
    return true
end

local function CompareZoneAbilityButtons(left, right)
    return (tonumber(left and left.layoutIndex) or 0) < (tonumber(right and right.layoutIndex) or 0)
end

local function CollectZoneAbilityButtons(target)
    local frame = _G.ZoneAbilityFrame
    local container = frame and frame.SpellButtonContainer
    if not container then return 0 end
    local count = 0
    if type(container.EnumerateActive) == "function" then
        for button in container:EnumerateActive() do
            if AddUniqueFrame(target, button) then count = count + 1 end
        end
        table.sort(target, CompareZoneAbilityButtons)
        return count
    end
    local childCount = container.GetNumChildren and container:GetNumChildren() or 0
    for index = 1, childCount do
        local child = select(index, container:GetChildren())
        if child and (not child.IsShown or child:IsShown()) and AddUniqueFrame(target, child) then
            count = count + 1
        end
    end
    table.sort(target, CompareZoneAbilityButtons)
    return count
end

function BarManager:CreateBarById(barId, db)
    db = db or GetDB()
    if not (barId and db) then return nil, "missing bar config" end
    if IsActionBarId(barId) then
        local config = GetBarConfig(db, barId)
        if not config then return nil, "missing action bar config" end
        return self:CreateActionBar(barId, config, db)
    end
    local config = GetSpecialConfig(db, barId)
    if not config then return nil, "missing special bar config" end
    if barId == "pet" then
        return self:CreatePetBar(config, db)
    elseif barId == "stance" then
        return self:CreateStanceBar(config, db)
    elseif barId == "possess" then
        if YAB.Adapter and YAB.Adapter.UseMainActionBarForPossess and YAB.Adapter:UseMainActionBarForPossess() then
            self:DeactivateBar("possess")
            return nil, "possess handled by main action bar"
        end
        return self:CreatePossessBar(config, db)
    elseif EXTERNAL_SPECIAL_BARS[barId] then
        return self:AttachExternal(barId, config)
    end
    return nil, "unsupported bar"
end

function BarManager:ApplyBarStructureChange(
    barId,
    reason,
    deferFullRefresh,
    deferSharedRefresh
)
    if not barId then return false, "missing bar id" end
    if barId == "questItems" and YAB.QuestItems then
        YAB.QuestItems:SyncEnabled()
        return true
    end
    if InCombat() then
        self.pendingStructuralBars[barId] = reason or true
        return false, "combat deferred"
    end
    local db = GetDB()
    if not db then return false, "missing db" end
    if self.runtimeActive ~= true then
        if YAB.Refresh then
            return YAB:Refresh(reason or "structure")
        end
        return false, "runtime inactive"
    end
    local existingRecord = self.bars and self.bars[barId]
    if (existingRecord and existingRecord.kind == "action") or GetBarConfig(db, barId) then
        self:InvalidateProcIndex(reason or "action structure", "full")
    end
    if barId == "possess" and YAB.Adapter and YAB.Adapter.UseMainActionBarForPossess and YAB.Adapter:UseMainActionBarForPossess() then
        self.pendingStructuralBars[barId] = nil
        self:DeactivateBar("possess")
        if deferSharedRefresh ~= true then
            self:RegisterEvents()
            self:ApplyVisibility()
        end
        if deferFullRefresh ~= true then
            self:QueueFullRefresh(reason or "structure")
        end
        if deferSharedRefresh ~= true
            and YAB.Keybinds
            and type(YAB.Keybinds.ApplyRuntimeBindings) == "function" then
            YAB.Keybinds:ApplyRuntimeBindings()
        end
        self.structuralBarChangeCount =
            (self.structuralBarChangeCount or 0) + 1
        return true
    end
    self.pendingStructuralBars[barId] = nil
    self:RefreshConfigSnapshot(barId, db)
    local config = GetBarConfig(db, barId) or GetSpecialConfig(db, barId)
    local enabled = config and config.enabled == true
    if not enabled then
        self:DeactivateBar(barId, { restoreNativeSpecial = false })
    else
        local record, createReason = self:CreateBarById(barId, db)
        if not record then
            return false, createReason or "bar unavailable"
        end
        if record.kind == "action" then
            self:RefreshActionRecord(barId, record, config, db, nil, "full")
        elseif record.kind == "pet" or record.kind == "stance" or record.kind == "possess" then
            self:RefreshSpecialRecord(record.kind, db)
        end
    end
    if deferSharedRefresh ~= true then
        self:RegisterEvents()
        self:ApplyVisibility()
    end
    if deferFullRefresh ~= true then
        self:QueueFullRefresh(reason or "structure")
    end
    if deferSharedRefresh ~= true
        and YAB.Keybinds
        and type(YAB.Keybinds.ApplyRuntimeBindings) == "function" then
        YAB.Keybinds:ApplyRuntimeBindings()
    end
    self.structuralBarChangeCount =
        (self.structuralBarChangeCount or 0) + 1
    return true
end

function BarManager:ApplyBarStructureChanges(barIds, reason)
    if type(barIds) ~= "table" or next(barIds) == nil then
        return true, 0
    end
    if InCombat() then return false, "combat deferred" end

    local appliedCount = 0
    local visited = {}
    local function ApplyOrder(order)
        for _, barId in ipairs(order or {}) do
            if barIds[barId] and not visited[barId] then
                visited[barId] = true
                local applied, applyReason = self:ApplyBarStructureChange(
                    barId,
                    reason or "structure batch",
                    true,
                    true
                )
                if applied == false then
                    return false, applyReason
                end
                appliedCount = appliedCount + 1
            end
        end
        return true
    end

    local applied, applyReason = ApplyOrder(YAB.BAR_ORDER)
    if applied == false then return false, applyReason end
    applied, applyReason = ApplyOrder(YAB.SPECIAL_BAR_ORDER)
    if applied == false then return false, applyReason end
    for barId in pairs(barIds) do
        if not visited[barId] then
            applied, applyReason = self:ApplyBarStructureChange(
                barId,
                reason or "structure batch",
                true,
                true
            )
            if applied == false then return false, applyReason end
            appliedCount = appliedCount + 1
        end
    end

    self:RegisterEvents()
    self:ApplyVisibility()
    if YAB.Keybinds
        and type(YAB.Keybinds.ApplyRuntimeBindings) == "function" then
        YAB.Keybinds:ApplyRuntimeBindings()
    end
    self.structuralBatchCount = (self.structuralBatchCount or 0) + 1
    return true, appliedCount
end

function BarManager:ApplyPendingBarStructureChanges(reason)
    local pending = self.pendingStructuralBars
    if not pending or next(pending) == nil then return 0 end
    if InCombat() then return 0 end
    local refreshSpecialGrouping = self.specialGroupingRefreshPending == true
    local reapplySpecialPlacements = self.specialGroupingPlacementPending == true
    local ok, applied = self:ApplyBarStructureChanges(
        pending,
        reason or "combat-deferred-structure"
    )
    applied = ok and (applied or 0) or 0
    if refreshSpecialGrouping then
        self.specialGroupingRefreshPending = false
        self.specialGroupingPlacementPending = false
        local ok = self:RefreshSpecialGroupingRuntime(GetDB(), reason or "combat-deferred-special-grouping", reapplySpecialPlacements)
        if ok then applied = applied + 1 end
    end
    return applied
end

function BarManager:FlushPendingExternalSpecialRefreshes()
    local pending = self.pendingExternalSpecialBars
    if not pending or next(pending) == nil or InCombat() then return 0 end
    local queuedCount = 0
    for kind, reason in pairs(pending) do
        pending[kind] = nil
        local queued = self:QueueSpecialRefresh(kind, reason)
        if queued == true then queuedCount = queuedCount + 1 end
    end
    return queuedCount
end

function BarManager:CreateActionBar(barId, config, db)
    self:InvalidateProcIndex("action bar create", "full")
    local record = self.bars[barId] or { id = barId, kind = "action", buttons = {} }
    record.buttons = record.buttons or {}
    self.bars[barId] = record
    local holder, reason = self:PrepareFrames(record, barId, config, barId == "main")
    if not holder then return nil, reason end
    local page = YAB.Adapter and YAB.Adapter:GetActionBarPageForBar(barId, config.page) or config.page
    record.page = tonumber(page) or 1

    self:AttachConfigSnapshot(record, barId, config, "normal")
    local reconciled, reconcileReason = self:ReconcileActionBarButtons(barId, record, config)
    if not reconciled then return nil, reconcileReason end
    self:ApplyLayout(record, config, db)
    self:MarkDirectActionListDirty()
    if barId == "main" and YAB.Drivers then
        YAB.Drivers:RegisterMainPaging(holder, record.buttons)
    end
    if YAB.LayoutBridge then
        YAB.LayoutBridge:Register(barId, record, config.label or barId, config)
    end
    return record
end

function BarManager:CreatePetBar(config, db)
    local record = self.bars.pet or { id = "pet", kind = "pet", buttons = {} }
    record.buttons = record.buttons or {}
    self.bars.pet = record
    local holder, reason = self:PrepareFrames(record, "pet", config, false)
    if not holder then return nil, reason end
    self:AttachConfigSnapshot(record, "pet", config, "special")
    local reconciled, reconcileReason = self:ReconcileSpecialButtons("pet", record, config)
    if not reconciled and not InCombat() then return nil, reconcileReason end
    self:ApplyLayout(record, config, db)
    if YAB.LayoutBridge then
        YAB.LayoutBridge:Register("pet", record, config.label or "宠物条", config)
    end
    return record
end

function BarManager:CreateStanceBar(config, db)
    local record = self.bars.stance or { id = "stance", kind = "stance", buttons = {} }
    record.buttons = record.buttons or {}
    self.bars.stance = record
    local holder, reason = self:PrepareFrames(record, "stance", config, false)
    if not holder then return nil, reason end
    if YAB.Client.ownedStanceButtons == true
        and YAB.SecureFactory
        and YAB.SecureFactory.PrecreateRetailStanceButtons then
        local precreated, precreateReason = YAB.SecureFactory:PrecreateRetailStanceButtons(holder)
        if not precreated then return nil, precreateReason or "stance template unavailable" end
    end
    self:AttachConfigSnapshot(record, "stance", config, "special")
    local reconciled, reconcileReason = self:ReconcileSpecialButtons("stance", record, config)
    if not reconciled and not InCombat() then return nil, reconcileReason end
    self:ApplyLayout(record, config, db)
    if YAB.LayoutBridge then
        YAB.LayoutBridge:Register("stance", record, GetStanceBarDisplayLabel(config), config)
    end
    return record
end

function BarManager:CreatePossessBar(config, db)
    local record = self.bars.possess or { id = "possess", kind = "possess", buttons = {} }
    record.buttons = record.buttons or {}
    self.bars.possess = record
    local holder, reason = self:PrepareFrames(record, "possess", config, false)
    if not holder then return nil, reason end
    self:AttachConfigSnapshot(record, "possess", config, "special")
    local reconciled, reconcileReason = self:ReconcileSpecialButtons("possess", record, config)
    if not reconciled and not InCombat() then return nil, reconcileReason end
    self:ApplyLayout(record, config, db)
    if YAB.LayoutBridge then
        YAB.LayoutBridge:Register("possess", record, config.label or "控制条", config)
    end
    return record
end

local function CapturePoints(frame)
    local points = {}
    for index = 1, frame:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(index)
        points[index] = { point, relativeTo, relativePoint, x, y }
    end
    return points
end

local function CaptureFrameState(frame, mode)
    return {
        mode = mode,
        parent = frame:GetParent(),
        points = CapturePoints(frame),
        alpha = frame.GetAlpha and frame:GetAlpha() or 1,
        shown = frame.IsShown and frame:IsShown() or false,
        mouse = frame.IsMouseEnabled and frame:IsMouseEnabled() or false,
        frameLevel = frame.GetFrameLevel and frame:GetFrameLevel() or nil,
        frameStrata = frame.GetFrameStrata and frame:GetFrameStrata() or nil,
    }
end

local function RestoreFrameState(frame, state)
    if not frame or not state then return true end
    local ok = true
    if frame.SetParent and state.parent then
        ok = pcall(frame.SetParent, frame, state.parent) and ok
    end
    if frame.SetFrameStrata and state.frameStrata then
        ok = pcall(frame.SetFrameStrata, frame, state.frameStrata) and ok
    end
    if frame.SetFrameLevel and state.frameLevel then
        ok = pcall(frame.SetFrameLevel, frame, state.frameLevel) and ok
    end
    if frame.ClearAllPoints then
        ok = pcall(frame.ClearAllPoints, frame) and ok
    end
    if frame.SetPoint and type(state.points) == "table" then
        for _, point in ipairs(state.points) do
            ok = pcall(frame.SetPoint, frame, point[1], point[2], point[3], point[4], point[5]) and ok
        end
    end
    if frame.SetAlpha then ok = pcall(frame.SetAlpha, frame, state.alpha or 1) and ok end
    if frame.EnableMouse then ok = pcall(frame.EnableMouse, frame, state.mouse == true) and ok end
    if frame.EnableMouseClicks and state.mouseClicks ~= nil then
        ok = pcall(frame.EnableMouseClicks, frame, state.mouseClicks == true) and ok
    end
    if frame.EnableMouseMotion and state.mouseMotion ~= nil then
        ok = pcall(frame.EnableMouseMotion, frame, state.mouseMotion == true) and ok
    end
    if state.shown == true then
        if frame.Show then ok = pcall(frame.Show, frame) and ok end
    elseif frame.Hide then
        ok = pcall(frame.Hide, frame) and ok
    end
    return ok
end

local function CallFrameMethod(frame, method, ...)
    local func = frame and frame[method]
    if type(func) ~= "function" then return true end
    return pcall(func, frame, ...)
end

local function CaptureExternalFrame(manager, frame)
    if not (manager and frame) or manager.externalState[frame] then return end
    local state = CaptureFrameState(frame, "external")
    state.parentCaptured = true
    state.width = frame.GetWidth and frame:GetWidth() or nil
    state.height = frame.GetHeight and frame:GetHeight() or nil
    manager.externalState[frame] = state
end

local function RestoreExternalFrameState(frame, state)
    if not (frame and state) then return true end
    local ok = true
    if frame.SetParent and state.parentCaptured == true then
        ok = pcall(frame.SetParent, frame, state.parent) and ok
    end
    if frame.SetFrameStrata and state.frameStrata then
        ok = pcall(frame.SetFrameStrata, frame, state.frameStrata) and ok
    end
    if frame.SetFrameLevel and state.frameLevel then
        ok = pcall(frame.SetFrameLevel, frame, state.frameLevel) and ok
    end
    if frame.SetScale and state.scale then
        ok = pcall(frame.SetScale, frame, state.scale) and ok
    end
    if frame.SetSize and state.width and state.height then
        ok = pcall(frame.SetSize, frame, state.width, state.height) and ok
    end
    if frame.ClearAllPoints then
        ok = pcall(frame.ClearAllPoints, frame) and ok
    end
    if frame.SetPoint and type(state.points) == "table" then
        for _, point in ipairs(state.points) do
            ok = pcall(frame.SetPoint, frame, point[1], point[2], point[3], point[4], point[5]) and ok
        end
    end
    if frame.EnableMouse then ok = pcall(frame.EnableMouse, frame, state.mouse == true) and ok end
    if frame.EnableMouseClicks and state.mouseClicks ~= nil then
        ok = pcall(frame.EnableMouseClicks, frame, state.mouseClicks == true) and ok
    end
    if frame.EnableMouseMotion and state.mouseMotion ~= nil then
        ok = pcall(frame.EnableMouseMotion, frame, state.mouseMotion == true) and ok
    end
    return ok
end

function BarManager:RestoreExternalFrame(frame)
    local state = frame and self.externalState and self.externalState[frame]
    if not state then return true end
    local ok, restored = pcall(RestoreExternalFrameState, frame, state)
    self.externalState[frame] = nil
    self.externalFrameOwners[frame] = nil
    return ok and restored ~= false
end

local function RestoreExternalOwnedButton(manager, kind, button)
    if not (manager and kind and button) then return true end
    UnmapNativeCoreCooldownDone(button)
    SetButtonConfigSnapshot(manager, button, nil)
    manager.externalButtonOwners[button] = nil
    manager.externalButtonIndices[button] = nil
    if manager.mouseoverRecords then manager.mouseoverRecords[button] = nil end
    RestoreExternalButtonTextState(manager, button)

    if kind == "extraAction" and YAB.Visuals and YAB.Visuals.RestoreExternalSpecialButton then
        YAB.Visuals:RestoreExternalSpecialButton(button)
    elseif kind == "zoneAbility" and YAB.Visuals and YAB.Visuals.RestoreZoneAbilityButton then
        YAB.Visuals:RestoreZoneAbilityButton(button)
    elseif kind == "vehicleExit" and YAB.Visuals and YAB.Visuals.RestoreVehicleExitVisualMode then
        YAB.Visuals:RestoreVehicleExitVisualMode(button)
    elseif kind == "vehicleExit" and YAB.Visuals and YAB.Visuals.ReleaseButton then
        YAB.Visuals:ReleaseButton(button)
    end
    local ok = manager:RestoreExternalFrame(button)
    if kind == "extraAction" and type(button.UpdateHotkeys) == "function" then
        ok = CallFrameMethod(button, "UpdateHotkeys", button.buttonType) and ok
    elseif kind == "vehicleExit" and type(button.Update) == "function" then
        ok = CallFrameMethod(button, "Update") and ok
    end
    return ok
end

local function RestoreZoneAbilityContainerLayout(manager, record)
    local container = record and record.zoneAbilityContainer
    if not container then return true end
    local state = record.zoneAbilityContainerState
    if state then
        container.spacing = state.spacing
        container.fixedWidth = state.fixedWidth
        container.fixedHeight = state.fixedHeight
    end
    local ok = manager:RestoreExternalFrame(container)
    if type(container.Layout) == "function" then
        ok = pcall(container.Layout, container) and ok
    end
    record.zoneAbilityContainer = nil
    record.zoneAbilityContainerState = nil
    return ok
end

function BarManager:RestoreExternalRecord(record)
    if not record then return true end
    local ok = true
    if record.kind == "zoneAbility" and YAB.Visuals then
        local frame = record.externalFrames and record.externalFrames[1] or _G.ZoneAbilityFrame
        if YAB.Visuals.RestoreZoneAbilityFrameArt then
            YAB.Visuals:RestoreZoneAbilityFrameArt(frame)
        elseif YAB.Visuals.RestoreZoneAbilityVisualMode then
            YAB.Visuals:RestoreZoneAbilityVisualMode(frame, {})
        end
    end
    for index, button in ipairs(record.externalButtons or {}) do
        if button then
            if YAB.Keybinds and YAB.Keybinds.GetButtonKey then
                self.buttonsByKey[YAB.Keybinds:GetButtonKey(record.kind, index)] = nil
            end
            ok = RestoreExternalOwnedButton(self, record.kind, button) and ok
        end
    end
    for button, owner in pairs(self.externalButtonOwners or {}) do
        if owner == record.kind then
            ok = RestoreExternalOwnedButton(self, owner, button) and ok
        end
    end
    for _, frame in ipairs(record.externalFrames or {}) do
        if frame then
            if self.mouseoverRecords then
                self.mouseoverRecords[frame] = nil
            end
            ok = self:RestoreExternalFrame(frame) and ok
        end
    end
    if record.kind == "zoneAbility" then
        ok = RestoreZoneAbilityContainerLayout(self, record) and ok
    end
    ClearTable(record.externalButtons)
    ClearTable(record.externalFrames)
    return ok
end

-- These helpers are only used by ResolveExternalSpecialFrames.
do
local function SameFrameList(left, right)
    local leftCount = #(left or {})
    if leftCount ~= #(right or {}) then return false end
    for index = 1, leftCount do
        if left[index] ~= right[index] then return false end
    end
    return true
end

local function FrameListContains(frames, frame)
    for index = 1, #(frames or {}) do
        if frames[index] == frame then return true end
    end
    return false
end

local function CopyFrameList(target, source)
    ClearTable(target)
    for index = 1, #(source or {}) do
        target[index] = source[index]
    end
    return target
end

function BarManager:ResolveExternalSpecialFrames(kind, record)
    local definition = EXTERNAL_SPECIAL_DEFINITIONS[kind]
    if not definition then return nil, nil, nil, false end
    local primary = ResolveFirstGlobal(definition.frames)
    local frames = record.externalFrames or {}
    local buttons = record.externalButtons or {}
    local nextFrames = ClearTable(EXTERNAL_FRAME_SCRATCH)
    local nextButtons = ClearTable(EXTERNAL_BUTTON_SCRATCH)
    if primary then AddUniqueFrame(nextFrames, primary) end
    if kind == "vehicleExit" then
        local button = ResolveFirstGlobal(definition.buttons)
        if AddUniqueFrame(nextButtons, button) and not primary then
            primary = button
        end
    else
        for _, name in ipairs(definition.buttons or {}) do
            AddUniqueFrame(nextButtons, _G[name])
        end
    end
    if definition.dynamicButtons == "zone" then
        CollectZoneAbilityButtons(nextButtons)
    end
    local structureChanged = record.externalPrimary ~= primary
        or not SameFrameList(frames, nextFrames)
        or not SameFrameList(buttons, nextButtons)
    if structureChanged ~= true then
        ClearTable(nextFrames)
        ClearTable(nextButtons)
        return primary, frames, buttons, false
    end
    for index = 1, #frames do
        local frame = frames[index]
        if frame and not FrameListContains(nextFrames, frame) then
            self:RestoreExternalFrame(frame)
        end
    end
    for index = 1, #buttons do
        local button = buttons[index]
        if button and not FrameListContains(nextButtons, button) then
            RestoreExternalOwnedButton(self, kind, button)
        end
    end
    CopyFrameList(frames, nextFrames)
    CopyFrameList(buttons, nextButtons)
    ClearTable(nextFrames)
    ClearTable(nextButtons)
    record.externalFrames = frames
    record.externalButtons = buttons
    record.externalPrimary = primary
    for _, frame in ipairs(frames) do
        self.externalFrameOwners[frame] = kind
    end
    for _, button in ipairs(buttons) do
        self.externalButtonOwners[button] = kind
    end
    return primary, frames, buttons, true
end
end

local function GetExternalSpecialDimensions(kind, config, db, snapshot, buttonCount, growthDirection)
    local size = tonumber(snapshot and snapshot.size) or GetSize(config, db)
    local spacing = GetSpacing(config, db)
    local count = 1
    if kind == "zoneAbility" then
        count = math.max(buttonCount or 0, 1)
    end
    local width = size
    local height = size
    if count > 1 then
        local length = (size * count) + (spacing * (count - 1))
        if growthDirection == "up" or growthDirection == "down" then
            height = length
        else
            width = length
        end
    end
    if width < size then width = size end
    if height < size then height = size end
    return width, height, size
end

function BarManager:HasSingleCenterAnchor(frame, relativeTo)
    if not (frame and relativeTo and frame.GetNumPoints and frame.GetPoint) then return false end
    if frame:GetNumPoints() ~= 1 then return false end
    local point, relativeFrame, relativePoint, offsetX, offsetY = frame:GetPoint(1)
    return point == "CENTER"
        and relativeFrame == relativeTo
        and relativePoint == "CENTER"
        and (offsetX or 0) == 0
        and (offsetY or 0) == 0
end

function BarManager:IsExternalSpecialLayoutOwned(record, primary, frames, buttons)
    local holder = record and record.holder
    if not holder then return false end
    for index = 1, #(frames or {}) do
        local frame = frames[index]
        if frame and (frame:GetParent() ~= holder or not self:HasSingleCenterAnchor(frame, holder)) then
            return false
        end
    end
    if record.kind == "extraAction" then
        for index = 1, #(buttons or {}) do
            local button = buttons[index]
            if button and not self:HasSingleCenterAnchor(button, primary) then
                return false
            end
        end
    elseif record.kind == "vehicleExit" then
        for index = 1, #(buttons or {}) do
            local button = buttons[index]
            if button and (button:GetParent() ~= holder or not self:HasSingleCenterAnchor(button, holder)) then
                return false
            end
        end
    end
    return true
end

function BarManager:RefreshZoneAbilityContainerLayout(record, config, db, size, width, height)
    local frame = _G.ZoneAbilityFrame
    local container = frame and frame.SpellButtonContainer
    if not container then return true end
    if not record.zoneAbilityContainerState then
        record.zoneAbilityContainerState = {
            spacing = container.spacing,
            fixedWidth = container.fixedWidth,
            fixedHeight = container.fixedHeight,
        }
    end
    record.zoneAbilityContainer = container
    CaptureExternalFrame(self, container)
    local spacing = GetSpacing(config, db)
    container.spacing = spacing
    container.fixedWidth = width
    container.fixedHeight = height
    local ok = true
    local layout = container.Layout
    if type(layout) == "function" then
        ok = pcall(layout, container) == true
    end
    if not self:IsSpecialGroupedKind("zoneAbility") then
        return ok
    end
    if container.SetSize then
        ok = pcall(container.SetSize, container, width, height) and ok
    end
    local direction = self:GetExternalSpecialGrowthDirection("zoneAbility")
    local point = direction == "up" and "BOTTOM"
        or direction == "down" and "TOP"
        or direction == "left" and "RIGHT"
        or "LEFT"
    local stepX = direction == "right" and (size + spacing)
        or direction == "left" and -(size + spacing)
        or 0
    local stepY = direction == "up" and (size + spacing)
        or direction == "down" and -(size + spacing)
        or 0
    for index, button in ipairs(record.externalButtons or {}) do
        if button then
            CaptureExternalFrame(self, button)
            ok = CallFrameMethod(button, "ClearAllPoints") and ok
            ok = CallFrameMethod(button, "SetPoint", point, container, point, stepX * (index - 1), stepY * (index - 1)) and ok
        end
    end
    return ok
end

function BarManager:ApplyExternalSpecialVisuals(record, config, db, size, width, height)
    if InCombat() or not record then return false end
    local snapshot = record.configSnapshot or (record.id and self:GetConfigSnapshot(record.id)) or DEFAULT_CONFIG_SNAPSHOT
    local skin = YAB.Skins and YAB.Skins:Normalize("default")
    local ok = true
    for index, button in ipairs(record.externalButtons or {}) do
        if button then
            self.externalButtonOwners[button] = record.kind
            self.externalButtonIndices[button] = index
            CaptureExternalFrame(self, button)
            SetButtonConfigSnapshot(self, button, snapshot)
            if YAB.Keybinds and YAB.Keybinds.GetButtonKey then
                local buttonKey = YAB.Keybinds:GetButtonKey(record.kind, index)
                local keybindable = not (YAB.SpecialBars and YAB.SpecialBars.IsRuntimeKeybindable)
                    or YAB.SpecialBars:IsRuntimeKeybindable(record.kind)
                self.buttonsByKey[buttonKey] = keybindable and button or nil
                if keybindable and YAB.Keybinds.HookButton then
                    YAB.Keybinds:HookButton(button, buttonKey)
                end
            end
            if record.kind == "extraAction" then
                local actionState = self:GetButtonState(button)
                actionState.slot = GetButtonAction(button)
                actionState.rangeMode = snapshot.rangeMode
                InstallNativeCoreCooldownDone(button)
                EnsureExternalButtonTextHooks(self, record.kind, button)
            end
            if button.SetSize then
                ok = pcall(button.SetSize, button, size, size) and ok
            end
            if record.kind == "extraAction" and YAB.Visuals and YAB.Visuals.ApplyExtraActionVisualMode then
                local visualOptions = { size = size, width = size, height = size, zoom = snapshot.iconZoom, snapshot = snapshot }
                ok = YAB.Visuals:ApplyExtraActionVisualMode(button, snapshot, visualOptions) ~= false and ok
            elseif record.kind == "zoneAbility" and YAB.Visuals and YAB.Visuals.ApplyZoneAbilityVisualMode then
                local visualOptions = { size = size, width = size, height = size, zoom = snapshot.iconZoom, snapshot = snapshot }
                ok = YAB.Visuals:ApplyZoneAbilityVisualMode(record.externalFrames and record.externalFrames[1] or _G.ZoneAbilityFrame, { button }, snapshot, visualOptions) ~= false and ok
            elseif record.kind == "vehicleExit" and YAB.Visuals and YAB.Visuals.ApplyVehicleExitVisualMode then
                local visualOptions = { size = size, width = size, height = size, zoom = snapshot.iconZoom, snapshot = snapshot, externalSpecialKind = "vehicleExit" }
                ok = YAB.Visuals:ApplyVehicleExitVisualMode(button, snapshot, visualOptions) ~= false and ok
            elseif (button.icon or button.Icon) and YAB.Skins and skin then
                local visualOptions = { size = size, width = size, height = size, zoom = snapshot.iconZoom, snapshot = snapshot, externalSpecialKind = record.kind }
                ok = YAB.Skins:ApplyButton(button, skin, visualOptions) ~= false and ok
            end
            ApplyExternalButtonTextState(self, record.kind, button, index, snapshot)
        end
    end
    if record.kind == "zoneAbility" then
        ok = self:RefreshZoneAbilityContainerLayout(record, config, db, size, width, height) and ok
    end
    return ok
end

local function ApplyExternalSpecialLayoutBody(self, record, config, db)
    if not (record and record.kind and config) then return false end
    if InCombat() then
        self.pendingStructuralBars[record.kind] = "external special layout"
        return false
    end
    local primary, frames, buttons, structureChanged = self:ResolveExternalSpecialFrames(record.kind, record)
    if not primary then
        SetDegraded(record.kind, "native frame unavailable")
        return false
    end
    local snapshot = record.configSnapshot or self:GetConfigSnapshot(record.kind) or self:UpdateConfigSnapshot(record.kind, config, "special")
    local snapshotRevision = snapshot and snapshot.revision or 0
    local groupedZoneAbility = record.kind == "zoneAbility" and self:IsSpecialGroupedKind("zoneAbility")
    local externalLayoutOwned = self:IsExternalSpecialLayoutOwned(record, primary, frames, buttons)
    if structureChanged ~= true and record.externalAppliedSnapshotRevision == snapshotRevision and externalLayoutOwned and not groupedZoneAbility then
        return true
    end
    local growthDirection = self:GetExternalSpecialGrowthDirection(record.kind)
    local width, height, size = GetExternalSpecialDimensions(record.kind, config, db, snapshot, #(buttons or {}), growthDirection)
    record.layoutWidth = width
    record.layoutHeight = height
    if record.mover then record.mover:SetSize(width, height) end
    if record.holder then
        record.holder:SetSize(width, height)
        if record.mover then
            record.holder:ClearAllPoints()
            record.holder:SetPoint("CENTER", record.mover, "CENTER", 0, 0)
        end
    end
    local ok = true
    for _, frame in ipairs(frames or {}) do
        if frame then
            CaptureExternalFrame(self, frame)
            ok = CallFrameMethod(frame, "SetParent", record.holder) and ok
            ok = CallFrameMethod(frame, "ClearAllPoints") and ok
            ok = CallFrameMethod(frame, "SetPoint", "CENTER", record.holder, "CENTER", 0, 0) and ok
            ok = CallFrameMethod(frame, "SetSize", width, height) and ok
        end
    end
    if primary == _G.ExtraActionBarFrame and _G.ExtraActionButton1 then
        CaptureExternalFrame(self, _G.ExtraActionButton1)
        ok = CallFrameMethod(_G.ExtraActionButton1, "ClearAllPoints") and ok
        ok = CallFrameMethod(_G.ExtraActionButton1, "SetPoint", "CENTER", primary, "CENTER", 0, 0) and ok
    end
    if record.kind == "vehicleExit" then
        for _, button in ipairs(buttons or {}) do
            if button then
                CaptureExternalFrame(self, button)
                ok = CallFrameMethod(button, "SetParent", record.holder) and ok
                ok = CallFrameMethod(button, "ClearAllPoints") and ok
                ok = CallFrameMethod(button, "SetPoint", "CENTER", record.holder, "CENTER", 0, 0) and ok
                ok = CallFrameMethod(button, "SetSize", size, size) and ok
            end
        end
    end
    self:ApplyExternalSpecialVisuals(record, config, db, size, width, height)
    self:ApplyMouseoverVisibility(record)
    SetDegraded(record.kind, nil)
    if YAB.LayoutBridge and YAB.LayoutBridge.Refresh then
        YAB.LayoutBridge:Refresh(record.kind)
    end
    if ok then
        record.externalAppliedSnapshotRevision = snapshotRevision
    end
    return ok
end

function BarManager:ApplyExternalSpecialLayout(record, config, db)
    if not (record and record.kind and config) then return false end
    local kind = record.kind
    config = self:GetRuntimeSpecialPresentationConfig(kind, config)
    if self.externalSpecialApplyingAny == true or self.externalSpecialApplying[kind] == true then
        return false, "external special layout already applying"
    end
    self.externalSpecialApplyingAny = true
    self.externalSpecialApplying[kind] = true
    local callOk, applied, reason = pcall(ApplyExternalSpecialLayoutBody, self, record, config, db)
    self.externalSpecialApplying[kind] = nil
    self.externalSpecialApplyingAny = nil
    if not callOk then
        return false, applied
    end
    return applied, reason
end

function BarManager:RefreshExternalSpecialBar(kind, reason)
    if not (self.runtimeActive and kind and EXTERNAL_SPECIAL_BARS[kind]) then
        return false
    end
    self:InstallExternalSpecialHooks()
    if InCombat() then
        if self.pendingExternalSpecialBars[kind] == nil then
            self.pendingExternalSpecialBars[kind] = reason or "external special refresh"
        end
        return false
    end
    local record = self.bars and self.bars[kind]
    local db = GetDB()
    local config = GetSpecialConfig(db, kind)
    if not (record and config and config.enabled == true) then
        return false
    end
    self:AttachConfigSnapshot(record, kind, config, "special")
    local applied, applyReason = self:ApplyExternalSpecialLayout(record, config, db)
    self:ApplySpecialActionGrouping(reason or "external special refreshed")
    return applied, applyReason
end

function BarManager:OnExternalSpecialNativeFrameChanged(frame, reason)
    local kind = frame and self.externalFrameOwners and self.externalFrameOwners[frame]
    if not kind then
        if frame == _G.ExtraActionBarFrame then
            kind = "extraAction"
        elseif frame == _G.ZoneAbilityFrame then
            kind = "zoneAbility"
        elseif frame == _G.MainMenuBarVehicleLeaveButton or frame == _G.VehicleExitButton then
            kind = "vehicleExit"
        end
    end
    if kind then
        return self:QueueSpecialRefresh(kind, reason or "native layout")
    end
    return false
end

function BarManager:InstallExternalSpecialHooks()
    if type(hooksecurefunc) ~= "function" then return false end
    local hooks = self.externalSpecialHooks or {}
    self.externalSpecialHooks = hooks
    local hooked = false
    local container = _G.ExtraAbilityContainer
    if not hooks.extraAbilityAddFrame and container and type(container.AddFrame) == "function" then
        hooks.extraAbilityAddFrame = pcall(hooksecurefunc, container, "AddFrame", function(first, second)
            local frame = first == container and second or first
            BarManager:OnExternalSpecialNativeFrameChanged(frame, "extra ability add")
        end) == true
        hooked = hooks.extraAbilityAddFrame or hooked
    end
    if not hooks.extraAbilityRemoveFrame and container and type(container.RemoveFrame) == "function" then
        hooks.extraAbilityRemoveFrame = pcall(hooksecurefunc, container, "RemoveFrame", function(first, second)
            local frame = first == container and second or first
            BarManager:OnExternalSpecialNativeFrameChanged(frame, "extra ability remove")
            BarManager:QueueSpecialRefresh("extraAction", "extra ability remove")
            BarManager:QueueSpecialRefresh("zoneAbility", "extra ability remove")
        end) == true
        hooked = hooks.extraAbilityRemoveFrame or hooked
    end
    if not hooks.extraAbilityLayout and container and type(container.Layout) == "function" then
        hooks.extraAbilityLayout = pcall(hooksecurefunc, container, "Layout", function()
            BarManager:QueueSpecialRefresh("extraAction", "extra ability layout")
            BarManager:QueueSpecialRefresh("zoneAbility", "extra ability layout")
        end) == true
        hooked = hooks.extraAbilityLayout or hooked
    end
    if not hooks.extraActionUpdate and type(_G.ExtraActionBar_Update) == "function" then
        hooks.extraActionUpdate = pcall(hooksecurefunc, "ExtraActionBar_Update", function()
            BarManager:QueueSpecialRefresh("extraAction", "extra action update")
        end) == true
        hooked = hooks.extraActionUpdate or hooked
    end
    local zone = _G.ZoneAbilityFrame
    if not hooks.zoneAbilityUpdate and zone and type(zone.UpdateDisplayedZoneAbilities) == "function" then
        hooks.zoneAbilityUpdate = pcall(hooksecurefunc, zone, "UpdateDisplayedZoneAbilities", function(frame)
            BarManager:OnExternalSpecialNativeFrameChanged(frame == zone and frame or _G.ZoneAbilityFrame, "zone ability update")
        end) == true
        hooked = hooks.zoneAbilityUpdate or hooked
    end
    local leave = _G.MainMenuBarVehicleLeaveButton or _G.VehicleExitButton
    if leave and hooks.vehicleExitSetPointFrame ~= leave and type(leave.SetPoint) == "function" then
        local setPointHooked = pcall(hooksecurefunc, leave, "SetPoint", function(frame)
            BarManager:OnExternalSpecialNativeFrameChanged(frame == leave and frame or leave, "vehicle exit set point")
        end) == true
        if setPointHooked then
            hooks.vehicleExitSetPointFrame = leave
            hooked = true
        end
    end
    if not hooks.vehicleExitUpdate and leave and type(leave.Update) == "function" then
        hooks.vehicleExitUpdate = pcall(hooksecurefunc, leave, "Update", function(frame)
            BarManager:OnExternalSpecialNativeFrameChanged(frame == leave and frame or leave, "vehicle exit update")
        end) == true
        hooked = hooks.vehicleExitUpdate or hooked
    end
    return hooked
end

local function CaptureNativeFrame(manager, frame, mode)
    if not (manager and frame) or manager.nativeState[frame] then return end
    manager.nativeState[frame] = CaptureFrameState(frame, mode)
    if frame.IsMouseClickEnabled then
        local ok, enabled = pcall(frame.IsMouseClickEnabled, frame)
        manager.nativeState[frame].mouseClicks = ok and enabled or nil
    end
    if frame.IsMouseMotionEnabled then
        local ok, enabled = pcall(frame.IsMouseMotionEnabled, frame)
        manager.nativeState[frame].mouseMotion = ok and enabled or nil
    end
end

function BarManager:CaptureNativeSuppressionState(frame, mode, restoreAlpha, restoreMouse)
    if not frame or self.nativeState[frame] then return end
    local state = {
        mode = mode,
        nonStructural = true,
        restoreAlpha = restoreAlpha == true,
        restoreMouse = restoreMouse == true,
    }
    if state.restoreAlpha and frame.GetAlpha then
        local ok, alpha = pcall(frame.GetAlpha, frame)
        state.alpha = ok and alpha or 1
    end
    if state.restoreMouse then
        if frame.IsMouseEnabled then
            local ok, enabled = pcall(frame.IsMouseEnabled, frame)
            state.mouse = ok and enabled or false
        end
        if frame.IsMouseClickEnabled then
            local ok, enabled = pcall(frame.IsMouseClickEnabled, frame)
            state.mouseClicks = ok and enabled or nil
        end
        if frame.IsMouseMotionEnabled then
            local ok, enabled = pcall(frame.IsMouseMotionEnabled, frame)
            state.mouseMotion = ok and enabled or nil
        end
    end
    self.nativeState[frame] = state
end

function BarManager:RestoreNativeSuppressionState(frame, state)
    if not (frame and state) then return true end
    local ok = true
    if state.restoreAlpha and frame.SetAlpha then
        ok = pcall(frame.SetAlpha, frame, state.alpha or 1) and ok
    end
    if state.restoreMouse then
        if frame.EnableMouse then
            ok = pcall(frame.EnableMouse, frame, state.mouse == true) and ok
        end
        if frame.EnableMouseClicks and state.mouseClicks ~= nil then
            ok = pcall(frame.EnableMouseClicks, frame, state.mouseClicks == true) and ok
        end
        if frame.EnableMouseMotion and state.mouseMotion ~= nil then
            ok = pcall(frame.EnableMouseMotion, frame, state.mouseMotion == true) and ok
        end
    end
    return ok
end

function BarManager:IsRetailNativeSuppressionStable(frame)
    if not frame then return true end
    if type(frame.GetAlpha) == "function" then
        local ok, alpha = pcall(frame.GetAlpha, frame)
        if not ok or alpha ~= 0 then return false end
    end
    if type(frame.IsMouseEnabled) == "function" then
        local ok, enabled = pcall(frame.IsMouseEnabled, frame)
        if not ok or enabled == true then return false end
    end
    if type(frame.IsMouseClickEnabled) == "function" then
        local ok, enabled = pcall(frame.IsMouseClickEnabled, frame)
        if not ok or enabled == true then return false end
    end
    if type(frame.IsMouseMotionEnabled) == "function" then
        local ok, enabled = pcall(frame.IsMouseMotionEnabled, frame)
        if not ok or enabled == true then return false end
    end
    return true
end

local function DisableNativeMouse(frame)
    local ok = true
    ok = CallFrameMethod(frame, "EnableMouse", false) and ok
    ok = CallFrameMethod(frame, "EnableMouseClicks", false) and ok
    ok = CallFrameMethod(frame, "EnableMouseMotion", false) and ok
    return ok
end

function BarManager:SuppressRetailNativeFrame(frame, mode)
    if not frame then return true end
    if self.nativeState[frame] and self:IsRetailNativeSuppressionStable(frame) then return true end
    self:CaptureNativeSuppressionState(frame, mode, true, true)
    local ok = DisableNativeMouse(frame)
    if type(frame.SetAlpha) == "function" then
        ok = pcall(frame.SetAlpha, frame, 0) and ok
    end
    return ok
end

function BarManager:SuppressMainActionBarPagerMouse(frame)
    local pager = frame and frame.ActionBarPageNumber
    if not pager then return true end
    local ok = true
    self:CaptureNativeSuppressionState(pager, "retailPager", false, true)
    ok = DisableNativeMouse(pager) and ok
    if type(pager.GetChildren) == "function" and type(pager.GetNumChildren) == "function" then
        local countOk, count = pcall(pager.GetNumChildren, pager)
        if countOk then
            for index = 1, count do
                local child = select(index, pager:GetChildren())
                if child then
                    self:CaptureNativeSuppressionState(child, "retailPagerChild", false, true)
                    ok = DisableNativeMouse(child) and ok
                end
            end
        end
    end
    return ok
end

local function HasManagedEditModeVisibility(frame)
    return type(frame) == "table"
        and type(frame.SetShownBase) == "function"
        and type(frame.SetShownOverride) == "function"
end

local function HideMainActionBarVisuals(frame)
    if not frame then return true end
    local ok = true
    if type(frame.SetAlpha) == "function" then
        ok = pcall(frame.SetAlpha, frame, 0) and ok
    end
    local selection = frame.Selection
    if selection then
        ok = CallFrameMethod(selection, "Hide") and ok
        if type(selection.SetAlpha) == "function" then
            ok = pcall(selection.SetAlpha, selection, 0) and ok
        end
    end
    ok = CallFrameMethod(frame.EndCaps, "Hide") and ok
    ok = CallFrameMethod(frame.BorderArt, "Hide") and ok
    return ok
end

local function DisposeMainActionBarContainer(manager, frame)
    if not frame then return true end
    CaptureNativeFrame(manager, frame, "main")
    local ok = true
    DisableNativeMouse(frame)
    if type(frame.SetAlpha) == "function" then
        ok = pcall(frame.SetAlpha, frame, 0) and ok
    end
    return ok
end

local function DisposeNativeActionButton(manager, frame, hiddenParent, mode)
    if not frame then return true end
    if mode == "retailSuppressed" then
        local ok = manager:SuppressRetailNativeFrame(frame, mode)
        manager.nativeDisposedButtons[frame] = true
        return ok
    end
    CaptureNativeFrame(manager, frame, mode)
    local ok = true
    ok = CallFrameMethod(frame, "StopAnimating") and ok
    DisableNativeMouse(frame)
    if type(frame.SetAlpha) == "function" then
        ok = pcall(frame.SetAlpha, frame, 0) and ok
    end
    if hiddenParent and type(frame.SetParent) == "function" then
        ok = pcall(frame.SetParent, frame, hiddenParent) and ok
    end
    ok = CallFrameMethod(frame, "Hide") and ok
    manager.nativeDisposedButtons[frame] = true
    return ok
end

local function DisposeNativeContainer(manager, frame, hiddenParent, mode)
    if not frame then return true end
    if mode == "retailSuppressed" then
        local ok = manager:SuppressRetailNativeFrame(frame, mode)
        if frame == _G.MainActionBar then
            ok = manager:SuppressMainActionBarPagerMouse(frame) and ok
        end
        return ok
    end
    if mode == "main" or frame == _G.MainActionBar then
        return DisposeMainActionBarContainer(manager, frame)
    end
    CaptureNativeFrame(manager, frame, mode)
    local ok = true
    DisableNativeMouse(frame)
    if type(frame.SetAlpha) == "function" then
        ok = pcall(frame.SetAlpha, frame, 0) and ok
    end
    if mode == "hiddenParent" and hiddenParent and type(frame.SetParent) == "function" then
        ok = pcall(frame.SetParent, frame, hiddenParent) and ok
        return ok
    end
    if HasManagedEditModeVisibility(frame) then
        return ok
    end
    ok = CallFrameMethod(frame, "Hide") and ok
    return ok
end

function BarManager:AttachExternal(kind, config)
    local record = self.bars[kind] or { id = kind, kind = kind, buttons = {} }
    self.bars[kind] = record
    self:InstallExternalSpecialHooks()
    local holder = self:PrepareFrames(record, kind, config, false)
    if not holder then
        return nil
    end
    self:AttachConfigSnapshot(record, kind, config, "special")
    local applied = self:ApplyExternalSpecialLayout(record, config, GetDB())
    if not applied then SetDegraded(kind, "native frame unavailable or protected") end
    self:SyncSpecialLayoutOwnership(GetDB(), kind)
    self:ApplySpecialActionGrouping("external special attached")
    return record, applied
end

function BarManager:MarkReloadRequired(reason, blocked)
    reason = reason or "需要 /reload 后才能回到安全动作条状态。"
    self.nativeSuppressionMode = "reload-required"
    self.reloadRequired = true
    self.reloadRequiredReason = reason
    local db = GetDB()
    if db and db.runtime then
        db.runtime.reloadRequired = true
        db.runtime.reloadRequiredReason = reason
        db.runtime.blocked = blocked == true
        db.runtime.blockedReason = blocked == true and reason or nil
        db.runtime.nativeSuppressionMode = "reload-required"
        db.runtime.takeoverMode = "strong"
        db.runtime.specialButtonMode = YAB.SPECIAL_BUTTON_MODE or "native-reuse"
    end
    SetDegraded("nativeBars", reason)
    return false, reason
end

local function StoreSpecialNativeSuppressionState(manager, db, result)
    result = result or {}
    manager.specialNativeSuppressionMode = result.mode or "unknown"
    manager.specialNativeSuppressionChanged = result.changed == true
    manager.specialNativeSuppressionFailures = tonumber(result.failures) or 0
    manager.specialNativeSuppressionReason = result.reason
    if db and db.runtime then
        db.runtime.specialNativeSuppressionMode = manager.specialNativeSuppressionMode
        db.runtime.specialNativeSuppressionChanged = manager.specialNativeSuppressionChanged
        db.runtime.specialNativeSuppressionFailures = manager.specialNativeSuppressionFailures
        db.runtime.specialNativeSuppressionReason = manager.specialNativeSuppressionReason
    end
end

function BarManager:EnsureSpecialNativeSuppression(db)
    local kinds = GetEnabledSpecialNativeKinds(db)
    if #kinds == 0 then
        StoreSpecialNativeSuppressionState(self, db, { mode = "not-required", changed = false, failures = 0 })
        return true
    end
    if not (YAB.Adapter and YAB.Adapter.EnsureSpecialNativeSuppressed) then
        local reason = "缺少特殊动作条原生压制适配，YActionBar 已阻断运行时。"
        StoreSpecialNativeSuppressionState(self, db, { mode = "unavailable", changed = false, failures = #kinds, reason = reason })
        if db and db.runtime then
            db.runtime.blocked = true
            db.runtime.blockedReason = reason
        end
        SetDegraded("specialNativeBars", reason)
        return false, reason
    end

    local result = YAB.Adapter:EnsureSpecialNativeSuppressed(kinds)
    StoreSpecialNativeSuppressionState(self, db, result)
    if not result.ok then
        local reason = result.reason or "无法安全关闭原生特殊动作条，YActionBar 已阻断运行时。"
        if db and db.runtime then
            db.runtime.blocked = true
            db.runtime.blockedReason = reason
        end
        SetDegraded("specialNativeBars", reason)
        return false, reason
    end
    if result.changed == true then
        return true
    end
    return true
end

function BarManager:CanDisposeNativeBars()
    if CountTableKeys(self.nativeDisposedButtons) > 0 then
        self.nativeSuppressionMode = YAB.Client.nonStructuralNativeSuppression == true and "non-structural" or "disposed-early"
        return true
    end
    return true
end

function BarManager:HideNativeBars()
    if InCombat() then
        return false, "combat lockdown"
    end
    local canDispose, reason = self:CanDisposeNativeBars()
    if not canDispose then
        return false, reason
    end
    local hiddenParent
    if YAB.Client.nonStructuralNativeSuppression ~= true then
        hiddenParent = YAB.SecureFactory and YAB.SecureFactory:CreateHiddenParent()
        if not hiddenParent then
            return self:MarkReloadRequired("无法创建动作条隐藏容器，YActionBar 已阻断运行时。", true)
        end
    end
    self.nativeSuppressionMode = YAB.Client.nonStructuralNativeSuppression == true and "non-structural" or "disposed-early"
    self.nativeSuppressionDegraded = false
    self.reloadRequired = false
    self.nativeDisposalFailures = 0
    for _, entry in ipairs(YAB.Adapter:GetNativeButtonDisposal()) do
        local name = entry.name
        local frame = _G[name]
        if frame then
            if not DisposeNativeActionButton(self, frame, hiddenParent, entry.mode) then
                self.nativeSuppressionDegraded = true
                self.nativeDisposalFailures = (self.nativeDisposalFailures or 0) + 1
                SetDegraded("nativeBars", "native action button disposal failed: " .. tostring(name))
            end
        end
    end
    for _, entry in ipairs(YAB.Adapter:GetNativeFrameDisposal()) do
        local name = entry.name
        local frame = _G[name]
        if frame and entry.mode == "hiddenParent" and not hiddenParent then
            hiddenParent = YAB.SecureFactory and YAB.SecureFactory:CreateHiddenParent()
        end
        local disposed = true
        if frame and entry.mode == "hiddenParent" and not hiddenParent then
            disposed = false
        elseif frame then
            disposed = DisposeNativeContainer(self, frame, hiddenParent, entry.mode)
        end
        if frame and not disposed then
            self.nativeSuppressionDegraded = true
            self.nativeDisposalFailures = (self.nativeDisposalFailures or 0) + 1
            SetDegraded("nativeBars", "native bar container disposal failed: " .. tostring(name))
        end
    end
    local db = GetDB()
    if db and db.runtime then
        db.runtime.reloadRequired = false
        db.runtime.reloadRequiredReason = nil
        db.runtime.blocked = false
        db.runtime.blockedReason = nil
        db.runtime.nativeSuppressionMode = self.nativeSuppressionMode
        db.runtime.takeoverMode = "strong"
        db.runtime.specialButtonMode = YAB.SPECIAL_BUTTON_MODE or "native-reuse"
    end
    if self.nativeDisposalFailures > 0 then
        self.nativeSuppressionMode = "blocked"
        local failureReason = "原生动作条处置失败，YActionBar 已阻断运行时以避免半接管。"
        local restored, restoreReason = self:RestoreNativeBars()
        return false, restored and failureReason or restoreReason
    end
    return true
end

function BarManager:RestoreNativeBars()
    if InCombat() then
        return false, "combat lockdown"
    end
    local failures = 0
    for frame, state in pairs(self.nativeState) do
        local ok, restored
        if state.nonStructural == true then
            ok, restored = pcall(self.RestoreNativeSuppressionState, self, frame, state)
        else
            ok, restored = pcall(RestoreFrameState, frame, state)
        end
        if not (ok and restored ~= false) then
            failures = failures + 1
        end
    end
    if failures > 0 then
        self.nativeDisposalFailures = failures
        return self:MarkReloadRequired("原生动作条恢复失败，需要 /reload 才能回到安全状态。", true)
    end
    self.nativeState = setmetatable({}, { __mode = "k" })
    self.nativeDisposedButtons = setmetatable({}, { __mode = "k" })
    self.nativeDisposalFailures = 0
    self.nativeSuppressionMode = "none"
    self.nativeSuppressionDegraded = false
    self.reloadRequired = false
    self.reloadRequiredReason = nil
    local db = GetDB()
    if db and db.runtime then
        db.runtime.blocked = false
        db.runtime.blockedReason = nil
        db.runtime.reloadRequired = false
        db.runtime.reloadRequiredReason = nil
        db.runtime.nativeSuppressionMode = "none"
    end
    return true
end

function BarManager:RestoreExternal()
    if InCombat() then return false end
    local ok = true
    for button, kind in pairs(self.externalButtonOwners or {}) do
        ok = RestoreExternalOwnedButton(self, kind, button) and ok
    end
    for frame, state in pairs(self.externalState or {}) do
        local restoredOk, restored = pcall(RestoreExternalFrameState, frame, state)
        ok = ok and restoredOk and restored ~= false
    end
    self.externalState = setmetatable({}, { __mode = "k" })
    self.externalFrameOwners = setmetatable({}, { __mode = "k" })
    self.externalButtonOwners = setmetatable({}, { __mode = "k" })
    self.externalButtonIndices = setmetatable({}, { __mode = "k" })
    for region in pairs(self.externalTextRegionShown or {}) do
        RestoreExternalTextRegionState(self, region, self.externalHotkeyText[region] ~= nil)
    end
    self.externalTextRegionShown = setmetatable({}, { __mode = "k" })
    self.externalTextRegionAlpha = setmetatable({}, { __mode = "k" })
    self.externalHotkeyText = setmetatable({}, { __mode = "k" })
    self.externalHotkeyDisplay = setmetatable({}, { __mode = "k" })
    return ok
end

-- Keep broadcaster helpers scoped below Lua's 200-local chunk limit.
do
local function ReadManifestRegistration(frame, entry)
    if not (frame and entry and type(frame.IsEventRegistered) == "function") then
        return false, false
    end
    local ok, registered, unit1, unit2, unit3, unit4 = pcall(frame.IsEventRegistered, frame, entry.event)
    if not ok or registered ~= true then return false, false end
    if entry.unit then
        local exact = unit1 == entry.unit and unit2 == nil and unit3 == nil and unit4 == nil
        return true, exact
    end
    return true, unit1 == nil and unit2 == nil and unit3 == nil and unit4 == nil
end

local function RegisterManifestEntry(frame, entry)
    if not (frame and entry) then return false end
    local func
    local ok, result
    if entry.unit then
        func = frame.RegisterUnitEvent
        if type(func) ~= "function" then return false end
        ok, result = pcall(func, frame, entry.event, entry.unit)
    else
        func = frame.RegisterEvent
        if type(func) ~= "function" then return false end
        ok, result = pcall(func, frame, entry.event)
    end
    return ok == true and result ~= false
end

local function UnregisterManifestEntry(frame, entry)
    local func = frame and frame.UnregisterEvent
    if type(func) ~= "function" then return false end
    local ok, result = pcall(func, frame, entry.event)
    return ok == true and result ~= false
end

local function SuppressManifest(frame, manifest)
    if not (frame and manifest) then return frame == nil end
    local ok = true
    for index = 1, #manifest do
        local entry = manifest[index]
        local registered = ReadManifestRegistration(frame, entry)
        if registered and not UnregisterManifestEntry(frame, entry) then
            ok = false
        end
    end
    return ok
end

local function RestoreManifest(frame, manifest)
    if not (frame and manifest) then return frame == nil end
    local ok = true
    for index = 1, #manifest do
        local entry = manifest[index]
        local registered, exact = ReadManifestRegistration(frame, entry)
        if not exact then
            local ready = true
            if registered then
                ready = UnregisterManifestEntry(frame, entry)
            end
            if ready and not RegisterManifestEntry(frame, entry) then
                ready = false
            end
            if not ready then ok = false end
        end
    end
    return ok
end

local function AuditManifest(frame, manifest)
    if not (frame and manifest) then return 0, 0 end
    local registeredCount = 0
    local exactCount = 0
    for index = 1, #manifest do
        local registered, exact = ReadManifestRegistration(frame, manifest[index])
        if registered then registeredCount = registeredCount + 1 end
        if exact then exactCount = exactCount + 1 end
    end
    return registeredCount, exactCount
end

function BarManager:AuditActionBroadcasterEvents(reason)
    local buttonFrame = _G.ActionBarButtonEventsFrame
    local actionFrame = _G.ActionBarActionEventsFrame
    local buttonRegistered, buttonExact = AuditManifest(buttonFrame, BROADCASTER_BUTTON_MANIFEST)
    local actionRegistered, actionExact = AuditManifest(actionFrame, BROADCASTER_ACTION_MANIFEST)
    local totalRegistered = buttonRegistered + actionRegistered
    local totalExact = buttonExact + actionExact
    local expectedRegistered = #BROADCASTER_BUTTON_MANIFEST + #BROADCASTER_ACTION_MANIFEST
    local actual = "partial"

    if not buttonFrame and not actionFrame then
        actual = "unavailable"
    elseif totalRegistered == 0 then
        actual = "off"
    elseif buttonFrame and actionFrame and totalExact == expectedRegistered then
        actual = "on"
    end

    local previousTotal = tonumber(self.broadcasterRegisteredEvents) or 0
    local previousActual = self.broadcasterActual
    if self.broadcasterMode == "off" and totalRegistered > 0 and (previousTotal == 0 or previousActual == "off") then
        self.broadcasterReregisters = (self.broadcasterReregisters or 0) + 1
    end

    self.broadcasterActual = actual
    self.broadcasterRegisteredEvents = totalRegistered
    self.broadcasterButtonRegistered = buttonRegistered
    self.broadcasterActionRegistered = actionRegistered
    if self.broadcasterMode == "off" then
        self.broadcasterMismatch = totalRegistered
    else
        self.broadcasterMismatch = expectedRegistered - totalExact
    end
    if self.broadcasterVerifiedMode and self.broadcasterVerifiedMode ~= actual then
        self.broadcasterVerifiedMode = nil
    end
    self.broadcasterCallbacksSuppressed = false
    self.broadcasterAuditReason = reason
    self.broadcasterAuditCount = (self.broadcasterAuditCount or 0) + 1
    return totalRegistered, actual
end

function BarManager:NativeActionBroadcasterRequired(reason)
    if reason == "UNIT_ENTERED_VEHICLE" then return true end
    local adapter = YAB.Adapter
    if not adapter then return false end
    if adapter.HasVehicleActionBar and adapter:HasVehicleActionBar() then return true end
    if adapter.HasOverrideActionBar and adapter:HasOverrideActionBar() then return true end
    return false
end

function BarManager:SuppressActionBroadcasters(reason, force)
    if self.broadcasterMode == "off" and self.broadcasterVerifiedMode == "off" and force ~= true then
        return true
    end
    local buttonFrame = _G.ActionBarButtonEventsFrame
    local actionFrame = _G.ActionBarActionEventsFrame
    if not buttonFrame and not actionFrame then
        self.broadcasterFallbacks = (self.broadcasterFallbacks or 0) + 1
        self.broadcasterMode = "unavailable"
        self.broadcasterVerifiedMode = nil
        self:AuditActionBroadcasterEvents(reason)
        return false
    end
    local previousMode = self.broadcasterMode
    local buttonOk = not buttonFrame or SuppressManifest(buttonFrame, BROADCASTER_BUTTON_MANIFEST)
    local actionOk = not actionFrame or SuppressManifest(actionFrame, BROADCASTER_ACTION_MANIFEST)
    self.broadcasterMode = buttonOk and actionOk and "off" or "fallback"
    local _, actual = self:AuditActionBroadcasterEvents(reason)
    if buttonOk and actionOk and actual == "off" then
        self.broadcasterVerifiedMode = "off"
        if previousMode ~= "off" then
            self.broadcasterOff = (self.broadcasterOff or 0) + 1
        end
        self.broadcasterLastReason = reason
        return true
    end
    self.broadcasterFallbacks = (self.broadcasterFallbacks or 0) + 1
    self.broadcasterMode = "fallback"
    self.broadcasterVerifiedMode = nil
    self.broadcasterLastReason = reason
    return false
end

function BarManager:RestoreActionBroadcasters(reason, force)
    if self.broadcasterMode == "on" and self.broadcasterVerifiedMode == "on" and force ~= true then return true end
    local buttonFrame = _G.ActionBarButtonEventsFrame
    local actionFrame = _G.ActionBarActionEventsFrame
    if not buttonFrame and not actionFrame then
        self.broadcasterFallbacks = (self.broadcasterFallbacks or 0) + 1
        self.broadcasterMode = "unavailable"
        self.broadcasterVerifiedMode = nil
        self:AuditActionBroadcasterEvents(reason)
        return false
    end
    local previousMode = self.broadcasterMode
    local buttonOk = not buttonFrame or RestoreManifest(buttonFrame, BROADCASTER_BUTTON_MANIFEST)
    local actionOk = not actionFrame or RestoreManifest(actionFrame, BROADCASTER_ACTION_MANIFEST)
    self.broadcasterMode = buttonOk and actionOk and "on" or "fallback"
    local _, actual = self:AuditActionBroadcasterEvents(reason)
    if buttonOk and actionOk and actual == "on" then
        self.broadcasterVerifiedMode = "on"
        if previousMode ~= "on" then
            self.broadcasterOn = (self.broadcasterOn or 0) + 1
        end
        if force == true then
            self.broadcasterRestores = (self.broadcasterRestores or 0) + 1
        end
        self.broadcasterLastReason = reason
        return true
    end
    self.broadcasterFallbacks = (self.broadcasterFallbacks or 0) + 1
    self.broadcasterMode = "fallback"
    self.broadcasterVerifiedMode = nil
    self.broadcasterLastReason = reason
    return false
end
end

function BarManager:RefreshActionBroadcasterMode(reason)
    local targetMode = self:NativeActionBroadcasterRequired(reason) and "on" or "off"
    if self.broadcasterMode == targetMode and self.broadcasterVerifiedMode == targetMode then
        return true
    end
    if targetMode == "on" then
        return self:RestoreActionBroadcasters(reason, false)
    end
    return self:SuppressActionBroadcasters(reason, false)
end

function BarManager:UnregisterNativeActionCooldowns()
    if InCombat() then return false end
    local factory = YAB.SecureFactory
    if not (factory and factory.UnregisterNativeActionCooldown) then return false end
    for _, record in pairs(self.bars or {}) do
        if record.kind == "action" then
            for _, button in ipairs(record.buttons or {}) do
                factory:UnregisterNativeActionCooldown(button)
            end
        end
    end
    return true
end

function BarManager:AbortRuntimeCreation(reason)
    local restored, restoreReason = self:ShutdownRuntime()
    YAB.runtimeBlocked = true
    YAB.runtimeBlockedReason = restored and reason or restoreReason or reason
    return false, YAB.runtimeBlockedReason
end

function BarManager:CreateRuntime()
    local db = GetDB()
    if not db or db.enabled ~= true then
        return false
    end
    if YAB.ShouldDeferRuntimeStartup then
        local shouldDefer, deferMode = YAB:ShouldDeferRuntimeStartup()
        if shouldDefer and YAB.ScheduleRuntimeDeferred then
            return YAB:ScheduleRuntimeDeferred(deferMode == "world" and "world create runtime" or "combat create runtime", deferMode, "enable")
        end
    end
    if InCombat() then
        if YAB.ScheduleRuntimeDeferred then
            return YAB:ScheduleRuntimeDeferred("combat create runtime", "combat", "enable")
        elseif YAB.ScheduleCombatDeferredRuntime then
            return YAB:ScheduleCombatDeferredRuntime("combat create runtime", "enable")
        end
        if YAB.Drivers then
            YAB.Drivers:Queue("create runtime", function() BarManager:CreateRuntime() end)
        end
        return false
    end

    if YAB.Adapter and YAB.Adapter.CanUseSecureRuntime then
        local supported, reason = YAB.Adapter:CanUseSecureRuntime()
        if not supported then return false, reason end
    end
    self:CaptureSpecialGroupingMode(db)

    self:RestoreBindPresentationLayers()
    self.runtimeActive = false
    self.emptySlotGridVisible = false
    ClearTable(self.pendingEmptyButtonShown)
    self.emptySlotPending = false
    self.bindPresentationActive = false
    self.bindPresentationPending = false
    self:ResetStats()
    self:PrepareActionHotBackend()
    if YAB.Drivers and YAB.Drivers.ResetStats then
        YAB.Drivers:ResetStats()
    end
    self.buttonsByKey = {}
    self:ClearDirtyRefresh()
    self:ClearAssistedCombatTracking()
    self:ClearSlotMap()
    self:ClearProcGlowTracking()
    self.pageStateCache = nil
    ClearTable(self.directActionButtons)
    ClearTable(self.directActionHolders)
    self.directActionButtonCount = 0
    self.directActionListDirty = true
    ClearTable(self.actionHotRecords)
    ClearTable(self.chargeHotRecords)
    ClearTable(self.countHotRecords)
    self.actionHotRecordsByButton = setmetatable({}, { __mode = "k" })
    self.actionHotRecordCount = 0
    self.chargeHotRecordCount = 0
    self.countHotRecordCount = 0
    self.actionHotRecordsDirty = true
    ClearTable(self.buttonStates)
    self:RefreshConfigSnapshots(db)
    self.auraCacheReady = false
    local specialSuppressed, specialReason = self:EnsureSpecialNativeSuppression(db)
    if not specialSuppressed then
        return self:AbortRuntimeCreation(specialReason or "special native action bar suppression failed")
    end
    local hidden, hiddenReason = self:HideNativeBars()
    if not hidden then
        return self:AbortRuntimeCreation(hiddenReason or "native action bar disposal failed")
    end
    self.runtimeActive = true
    self:PrepareSpecialGroupingMoverFrames(db)

    for _, barId in ipairs(YAB.BAR_ORDER) do
        local config = GetBarConfig(db, barId)
        if config and config.enabled then
            local record, reason = self:CreateActionBar(barId, config, db)
            if not record then
                return self:AbortRuntimeCreation(reason or "action bar unavailable")
            end
        else
            self:DeactivateBar(barId)
        end
    end

    local petConfig = GetSpecialConfig(db, "pet")
    if petConfig and petConfig.enabled then
        local record, reason = self:CreatePetBar(petConfig, db)
        if not record then return self:AbortRuntimeCreation(reason or "pet action bar unavailable") end
    else
        self:DeactivateBar("pet")
    end
    local stanceConfig = GetSpecialConfig(db, "stance")
    if stanceConfig and stanceConfig.enabled then
        local record, reason = self:CreateStanceBar(stanceConfig, db)
        if not record then return self:AbortRuntimeCreation(reason or "stance action bar unavailable") end
    else
        self:DeactivateBar("stance")
    end
    local possessConfig = GetSpecialConfig(db, "possess")
    if YAB.Adapter and YAB.Adapter.UseMainActionBarForPossess and YAB.Adapter:UseMainActionBarForPossess() then
        self:DeactivateBar("possess")
    elseif possessConfig and possessConfig.enabled then
        local record, reason = self:CreatePossessBar(possessConfig, db)
        if not record then return self:AbortRuntimeCreation(reason or "possess action bar unavailable") end
    else
        self:DeactivateBar("possess")
    end
    self:InstallExternalSpecialHooks()
    self:RegisterSpecialActionGroup()
    for _, kind in ipairs({ "extraAction", "zoneAbility", "vehicleExit" }) do
        local config = GetSpecialConfig(db, kind)
        if config and config.enabled then self:AttachExternal(kind, config) else self:DeactivateBar(kind) end
    end
    self:RefreshNativeEditModeClaims()

    self:RegisterEvents()
    self:RegisterLayoutEditHooks()
    self:ApplyVisibility()
    self:QueueRefresh("create")
    if YAB.Keybinds then
        YAB.Keybinds:ApplyRuntimeBindings()
    end
    if YAB.RankUpgrade then YAB.RankUpgrade:SyncEnabled() end
    if YAB.QuestItems then YAB.QuestItems:SyncEnabled() end
    return true
end

function BarManager:ShutdownRuntime()
    if YAB.RankUpgrade then YAB.RankUpgrade:Stop() end
    if YAB.QuestItems then YAB.QuestItems:Stop() end
    if InCombat() then
        return false, "combat lockdown"
    end
    if YUI.Layout and type(YUI.Layout.ReleaseNativeEditModeOwner) == "function" then
        YUI.Layout:ReleaseNativeEditModeOwner(self)
    end
    self.nativeEditModeAbilitiesFrame = nil
    self.nativeEditModeVehicleFrame = nil
    self.nativeEditModeOrdinaryFrames = nil
    local devPreview = self.specialGroupDevPreview
    if devPreview then
        devPreview.active = false
        if type(devPreview.hide) == "function" then
            pcall(devPreview.hide, devPreview)
        end
    end
    if YUI.Event and YUI.Event.OffOwner then
        self.eventCount = YUI.Event:OffOwner(self) or 0
    end
    self.layoutEditEventListenersRegistered = false
    if self.hotEventFrame then
        self.hotEventFrame:UnregisterAllEvents()
        self.hotEventFrame:SetScript("OnEvent", nil)
    end
    if HotDiagnostics and HotDiagnostics.Stop then
        HotDiagnostics:Stop()
    end
    if HotDiagnostics and HotDiagnostics.CancelProcCapture then
        HotDiagnostics:CancelProcCapture("shutdown")
    end
    self:ClearAssistedCombatTracking()
    local broadcastersRestored = self:RestoreActionBroadcasters("shutdown", true)
    self.eventCount = 0
    if YAB.CancelBindMode then
        YAB:CancelBindMode("shutdown")
    end
    self:RestoreBindPresentationLayers()
    self.emptySlotGridVisible = false
    ClearTable(self.pendingEmptyButtonShown)
    self.emptySlotPending = false
    if YAB.SecureFactory and YAB.SecureFactory.ResetActionDragGrid then
        YAB.SecureFactory:ResetActionDragGrid()
    end
    self.bindPresentationActive = false
    self.bindPresentationPending = false
    if YAB.Keybinds then
        YAB.Keybinds:ClearRuntimeBindings()
    end
    if YAB.Drivers then
        YAB.Drivers:ClearAll()
    end
    if YUI.Visibility then YUI.Visibility:ReleaseOwner(self) end
    if YAB.Visuals and YAB.Visuals.ReleaseAll then
        YAB.Visuals:ReleaseAll()
    end
    self:ClearRangeChecks()
    self:ClearDirtyRefresh()
    self:ClearSlotMap()
    self:ClearProcGlowTracking()
    ClearTable(self.directActionButtons)
    ClearTable(self.directActionHolders)
    self.directActionButtonCount = 0
    self.directActionListDirty = true
    ClearTable(self.actionHotRecords)
    ClearTable(self.chargeHotRecords)
    ClearTable(self.countHotRecords)
    self.actionHotRecordsByButton = setmetatable({}, { __mode = "k" })
    self.actionHotRecordCount = 0
    self.chargeHotRecordCount = 0
    self.countHotRecordCount = 0
    self.actionHotRecordsDirty = true
    ClearTable(self.buttonStates)
    ClearTable(self.auraLookup)
    self.auraCacheReady = false
    self.mouseoverRecords = setmetatable({}, { __mode = "k" })
    if self.StopAllMouseoverFades then
        self:StopAllMouseoverFades()
    end
    if self.refreshFrame then
        self.refreshFrame:SetScript("OnUpdate", nil)
        self.refreshFrame:Hide()
    end
    self.refreshHandlerInstalled = false
    self.refreshPending = false
    self.runtimeActive = false
    self.nativeCoreCooldownButtons = setmetatable({}, { __mode = "k" })
    self:UnregisterNativeActionCooldowns()
    self:RestoreExternal()
    local restored, restoreReason = self:RestoreNativeBars()
    if not restored then
        return false, restoreReason
    end
    local deactivateList = self.shutdownDeactivateList
    ClearTable(deactivateList)
    for barId in pairs(self.bars) do
        deactivateList[#deactivateList + 1] = barId
    end
    for index = 1, #deactivateList do
        self:DeactivateBar(deactivateList[index], { restoreNativeSpecial = true })
    end
    ClearTable(deactivateList)
    if YAB.SecureFactory and YAB.SecureFactory.RestoreNativeSpecialButtons then
        local specialRestored, specialReason = YAB.SecureFactory:RestoreNativeSpecialButtons()
        if not specialRestored then
            return false, specialReason
        end
    end
    if YAB.LayoutBridge then
        YAB.LayoutBridge:UnregisterAll()
    end
    if self.specialGroupRecord and self.specialGroupRecord.mover then
        self.specialGroupRecord.mover:Hide()
    end
    for _, proxy in pairs(self.specialMoverProxies or {}) do
        if proxy and proxy.mover then proxy.mover:Hide() end
    end
    self.specialGroupingMode = YAB.SPECIAL_GROUPING_MODE_INDEPENDENT or "independent"
    self.specialGroupConfig = nil
    self.specialGroupActiveMembers = 0
    self.specialGroupingRefreshPending = false
    self.specialGroupingPlacementPending = false
    self.buttonsByKey = {}
    self.pageStateCache = nil
    if not broadcastersRestored then
        return false, "native action broadcaster restore failed"
    end
    return true
end

function BarManager:RegisterEvents()
    local db = GetDB()
    local auraEnabled = AuraTimersEnabled(db)
    local hasOrdinaryActions = self:HasOrdinaryActionButtons()
    local hasExtraAction = self.bars and self.bars.extraAction ~= nil
    if self.hotEventFrame then
        self.hotEventFrame:UnregisterAllEvents()
    else
        self.hotEventFrame = CreateFrame("Frame", "YUI_YActionBar_HotEventFrame")
    end
    self.eventCount = 0
    self.hotEventFrame:SetScript("OnEvent", function(_, event, ...)
        BarManager:OnEvent(event, ...)
    end)
    for _, event in ipairs(HOT_EVENTS) do
        if RegisterHotEvent(self.hotEventFrame, event, auraEnabled, hasOrdinaryActions, hasExtraAction) then
            self.eventCount = self.eventCount + 1
        end
    end
    self:RefreshActionBroadcasterMode("register")
end

function BarManager:OnEvent(event, ...)
    if event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        local unit = ...
        if unit and unit ~= "player" then return end
    end
    if event == "PET_BATTLE_OPENING_DONE" or event == "PET_BATTLE_CLOSE" or event == "HOUSE_EDITOR_MODE_CHANGED" then
        if YAB.Keybinds then
            YAB.Keybinds:ApplyRuntimeBindings()
        end
        if event == "PET_BATTLE_CLOSE" then
            self:QueueActionRefresh(event, "full")
            self:QueueSpecialRefresh("pet", event)
            self:QueueSpecialRefresh("stance", event)
        end
        self:MarkDirectActionListDirty()
        return
    end
    if BROADCASTER_REFRESH_EVENTS[event] then
        self:RefreshActionBroadcasterMode(event)
    end
    if event == "ACTIONBAR_SHOWGRID" or event == "ACTIONBAR_HIDEGRID" then
        self:HandleEmptySlotGridEvent(event)
        return
    end
    if event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        self:RefreshActionBroadcasterMode(event)
        self:QueueMainPageIdentity(event)
        self:QueueSpecialRefresh("vehicleExit", event)
        return
    elseif event == "VEHICLE_UPDATE" then
        self:QueueSpecialRefresh("vehicleExit", event)
        return
    elseif VEHICLE_PAGE_IDENTITY_EVENTS[event] then
        self:QueueMainPageIdentity(event)
        self:QueueSpecialRefresh("vehicleExit", event)
        return
    elseif MAIN_PAGE_IDENTITY_EVENTS[event] then
        self:QueueMainPageIdentity(event)
        return
    elseif event == "UPDATE_EXTRA_ACTIONBAR" then
        self:QueueSpecialRefresh("extraAction", event)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if YAB.Keybinds and YAB.Keybinds.RefreshHeldBindings then
            YAB.Keybinds:RefreshHeldBindings()
        end
        local driverReasons
        local structuralBars
        local externalSpecialBars
        local combatDiagnostic = HotDiagnostics
            and HotDiagnostics.enabled == true
            and HotDiagnostics.detailEnabled == true
            and type(HotDiagnostics.RecordCombatFlush) == "function"
        if combatDiagnostic then
            driverReasons = {}
            local queue = YAB.Drivers and YAB.Drivers.secureQueue
            for index = 1, #(queue or {}) do
                local reason = tostring(queue[index].reason or "secure")
                driverReasons[reason] = (driverReasons[reason] or 0) + 1
            end
            structuralBars = {}
            for barId, reason in pairs(self.pendingStructuralBars or {}) do
                structuralBars[barId] = reason
            end
            externalSpecialBars = {}
            for barId, reason in pairs(self.pendingExternalSpecialBars or {}) do
                externalSpecialBars[barId] = reason
            end
        end
        local secureApplied = 0
        if YAB.Drivers then
            local _, executed, failed = YAB.Drivers:Flush()
            executed = tonumber(executed) or 0
            failed = tonumber(failed) or 0
            secureApplied = math.max(executed - failed, 0)
        end
        local structuralApplied = self:ApplyPendingBarStructureChanges("combat-deferred-structure")
        structuralApplied = structuralApplied + self:FlushPendingStanceRefresh()
        local externalSpecialQueued = self:FlushPendingExternalSpecialRefreshes()
        if YAB.SecureFactory and YAB.SecureFactory.ResetActionDragGrid then
            YAB.SecureFactory:ResetActionDragGrid()
        end
        self.emptySlotGridVisible = false
        self:ApplyPendingEmptySlots()
        if YAB.Visuals and YAB.Visuals.FlushPendingProfessionQuality then
            YAB.Visuals:FlushPendingProfessionQuality()
        end
        if YAB.Visuals and YAB.Visuals.FlushPendingSpellFlyoutShadow then
            YAB.Visuals:FlushPendingSpellFlyoutShadow()
        end
        if YUI.GUI2 and YUI.GUI2.FlushShapeShadowBindings then
            YUI.GUI2:FlushShapeShadowBindings()
        end
        if self.mainPageSyncPending == true then
            self:QueueMainPageIdentity("combat-page-sync")
        end
        local fullRefreshQueued = secureApplied > 0 or structuralApplied > 0
        if fullRefreshQueued then
            self:QueueFullRefresh("combat-deferred-structure")
        end
        if combatDiagnostic then
            HotDiagnostics:RecordCombatFlush(
                secureApplied,
                structuralApplied,
                fullRefreshQueued,
                driverReasons,
                structuralBars,
                externalSpecialQueued,
                externalSpecialBars
            )
        end
        if HotDiagnostics and HotDiagnostics.IsProcCaptureActive
            and HotDiagnostics:IsProcCaptureActive() then
            self:TraceProcCapture(event, "after")
        end
        if HotDiagnostics and HotDiagnostics.OnProcCaptureCombatEnded then
            HotDiagnostics:OnProcCaptureCombatEnded()
        end
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        if HotDiagnostics and HotDiagnostics.NoteProcCaptureCombatStarted then
            HotDiagnostics:NoteProcCaptureCombatStarted()
        end
        if YAB.CancelBindMode then YAB:CancelBindMode("combat") end
        if YAB.SecureFactory and YAB.SecureFactory.HideRestrictedCombatTooltip then
            YAB.SecureFactory:HideRestrictedCombatTooltip()
        end
        self:MarkDirectActionListDirty()
        return
    elseif event == "ACTION_RANGE_CHECK_UPDATE" then
        local diagnostic, started, timingDomain
        if HotDiagnostics and HotDiagnostics.enabled then diagnostic, started, timingDomain = HotDiagnostics:Begin("range") end
        local slot, inRange, checksRange = ...
        self:HandleRangeUpdate(slot, inRange, checksRange, diagnostic)
        if timingDomain then HotDiagnostics:Finish(timingDomain, started) end
        return
    elseif event == "UPDATE_BINDINGS" then
        if YAB.Keybinds then
            YAB.Keybinds:ApplyRuntimeBindings()
        end
        self:QueueActionRefresh(event, "hotkey")
        self:QueueSpecialRefresh("pet", event)
        self:QueueSpecialRefresh("stance", event)
        self:QueueSpecialRefresh("possess", event)
        return
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit and unit ~= "player" then return end
        local db = GetDB()
        if not AuraTimersEnabled(db) then return end
        self.auraDirty = true
        self:QueueActionRefresh(event, "aura")
        return
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        local slot = ...
        if YAB.Keybinds and YAB.Keybinds.RefreshHeldBindings then
            YAB.Keybinds:RefreshHeldBindings()
        end
        local diagnostic, started, timingDomain
        if HotDiagnostics and HotDiagnostics.enabled then diagnostic, started, timingDomain = HotDiagnostics:Begin("identity") end
        self:HandleNativeCoreSlotChanged(event, slot)
        if diagnostic then
            diagnostic.changes = diagnostic.changes + 1
        end
        if timingDomain then HotDiagnostics:Finish(timingDomain, started) end
        return
    elseif event == "ACTIONBAR_UPDATE_COOLDOWN" then
        local diagnostic, started, timingDomain
        if HotDiagnostics and HotDiagnostics.enabled then diagnostic, started, timingDomain = HotDiagnostics:Begin("cooldown", true) end
        self:HandleNativeCoreCooldownEvent(event, diagnostic)
        if timingDomain then HotDiagnostics:Finish(timingDomain, started) end
        return
    elseif event == "SPELL_UPDATE_CHARGES" then
        local diagnostic, started, timingDomain
        if HotDiagnostics and HotDiagnostics.enabled then diagnostic, started, timingDomain = HotDiagnostics:Begin("charge", true) end
        self:HandleNativeCoreChargeEvent(event, diagnostic)
        if timingDomain then HotDiagnostics:Finish(timingDomain, started) end
        return
    elseif event == "SPELL_UPDATE_USES" then
        local diagnostic, started, timingDomain
        if HotDiagnostics and HotDiagnostics.enabled then diagnostic, started, timingDomain = HotDiagnostics:Begin("uses", true) end
        local spellID, relatedSpellID = ...
        self:HandleNativeCoreUsesEvent(event, spellID, relatedSpellID, diagnostic)
        if timingDomain then HotDiagnostics:Finish(timingDomain, started) end
        return
    elseif event == "ACTION_USABLE_CHANGED" then
        local diagnostic, started, timingDomain
        if HotDiagnostics and HotDiagnostics.enabled then diagnostic, started, timingDomain = HotDiagnostics:Begin("usable") end
        local changes = ...
        if HotDiagnostics and HotDiagnostics.IsProcCaptureActive
            and HotDiagnostics:IsProcCaptureActive() then
            self:TraceProcCapture(event, "before")
        end
        self:HandleActionUsableChanges(changes, diagnostic)
        if HotDiagnostics and HotDiagnostics.IsProcCaptureActive
            and HotDiagnostics:IsProcCaptureActive() then
            self:TraceProcCapture(event, "after")
        end
        if timingDomain then HotDiagnostics:Finish(timingDomain, started) end
        return
    elseif event == "ACTIONBAR_UPDATE_USABLE" or event == "PLAYER_TARGET_CHANGED" then
        local diagnostic, started, timingDomain
        if HotDiagnostics and HotDiagnostics.enabled then diagnostic, started, timingDomain = HotDiagnostics:Begin("usable") end
        if HotDiagnostics and HotDiagnostics.IsProcCaptureActive
            and HotDiagnostics:IsProcCaptureActive() then
            self:TraceProcCapture(event, "before")
        end
        if YAB.Client.directUsableRefresh == true then
            self:HandleActionUsableReconcile(event, diagnostic)
        else
            self:HandleActionUsableFullScan(event, diagnostic)
        end
        if HotDiagnostics and HotDiagnostics.IsProcCaptureActive
            and HotDiagnostics:IsProcCaptureActive() then
            self:TraceProcCapture(event, "after")
        end
        if timingDomain then HotDiagnostics:Finish(timingDomain, started) end
        return
    elseif event == "ACTIONBAR_UPDATE_STATE" or event == "PLAYER_ENTER_COMBAT" or event == "PLAYER_LEAVE_COMBAT"
        or event == "START_AUTOREPEAT_SPELL" or event == "STOP_AUTOREPEAT_SPELL" then
        local diagnostic, started, timingDomain
        if HotDiagnostics and HotDiagnostics.enabled then diagnostic, started, timingDomain = HotDiagnostics:Begin("state", true) end
        self:HandleNativeCoreStateEvent(event, diagnostic)
        if timingDomain then HotDiagnostics:Finish(timingDomain, started) end
        return
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        local diagnostic, started, timingDomain
        if HotDiagnostics and HotDiagnostics.enabled then diagnostic, started, timingDomain = HotDiagnostics:Begin("proc") end
        local spellID = ...
        if HotDiagnostics and HotDiagnostics.IsProcCaptureActive
            and HotDiagnostics:IsProcCaptureActive() then
            self:TraceProcCapture(event, "before", spellID)
        end
        self:HandleProcGlowEvent(event, spellID, diagnostic)
        if HotDiagnostics and HotDiagnostics.IsProcCaptureActive
            and HotDiagnostics:IsProcCaptureActive() then
            self:TraceProcCapture(event, "after", spellID)
        end
        if timingDomain then HotDiagnostics:Finish(timingDomain, started) end
        return
    elseif event == "SPELL_UPDATE_ICON" then
        local diagnostic, started, timingDomain
        if HotDiagnostics and HotDiagnostics.enabled then diagnostic, started, timingDomain = HotDiagnostics:Begin("identity") end
        self:HandleNativeCoreIconEvent(event)
        if timingDomain then HotDiagnostics:Finish(timingDomain, started) end
        return
    elseif event == "SPELLS_CHANGED" then
        self:QueueActionRefresh(event, "identity")
        return
    elseif event == "PET_BAR_UPDATE" or event == "PET_BAR_UPDATE_COOLDOWN" or event == "PET_BAR_UPDATE_USABLE" or event == "UNIT_PET" then
        self:QueueSpecialRefresh("pet", event)
        return
    elseif event == "UPDATE_SHAPESHIFT_FORMS" or event == "UPDATE_SHAPESHIFT_FORM" or event == "UPDATE_SHAPESHIFT_USABLE" or event == "UPDATE_SHAPESHIFT_COOLDOWN" then
        self:QueueSpecialRefresh("stance", event)
        return
    elseif event == "UPDATE_POSSESS_BAR" then
        self:QueueSpecialRefresh("possess", event)
        return
    elseif event == "CVAR_UPDATE" then
        local name = ...
        if name == "assistedCombatIconUpdateRate" then
            self:RefreshAssistedCombatTicker(true)
        elseif name == "ActionButtonUseKeyHeldSpell" then
            if YAB.Keybinds then YAB.Keybinds:ApplyRuntimeBindings() end
        elseif name == "ActionButtonUseKeyDown" or name == "lockActionBars" then
            if YAB.SecureFactory and YAB.SecureFactory.RefreshActionButtonClickAttributes then
                YAB.SecureFactory:RefreshActionButtonClickAttributes(event)
            end
            if name == "ActionButtonUseKeyDown" then
                self:QueueActionRefresh(event, "hotkey")
            end
        end
        return
    end
    if FULL_REFRESH_REASONS[event] then
        self:QueueFullRefresh(event)
    else
        self:QueueActionRefresh(event or "event", "full")
    end
end

local function RefreshFrameOnUpdate(frame)
    frame:Hide()
    BarManager.refreshPending = false
    local diagnostic, started, timingDomain
    if HotDiagnostics and HotDiagnostics.enabled then diagnostic, started, timingDomain = HotDiagnostics:Begin("refresh") end
    BarManager:RefreshVisuals(BarManager.lastRefreshReason, diagnostic)
    if timingDomain then HotDiagnostics:Finish(timingDomain, started) end
end

function BarManager:EnsureRefreshFrame()
    local frame = self.refreshFrame
    if not frame then
        frame = CreateFrame("Frame", "YUI_YActionBar_RefreshFrame")
        frame:Hide()
        self.refreshFrame = frame
    end
    if self.refreshHandlerInstalled ~= true then
        frame:SetScript("OnUpdate", RefreshFrameOnUpdate)
        self.refreshHandlerInstalled = true
    end
    return frame
end

function BarManager:ScheduleRefresh()
    if self.refreshPending then return end
    local frame = self:EnsureRefreshFrame()
    self.refreshPending = true
    frame:Show()
end

function BarManager:QueueRefresh(reason)
    if reason == "keybind" then
        self:QueueActionRefresh(reason, "hotkey")
        self:QueueSpecialRefresh("pet", reason)
        self:QueueSpecialRefresh("stance", reason)
        self:QueueSpecialRefresh("possess", reason)
    elseif FULL_REFRESH_REASONS[reason] or reason == nil then
        self:QueueFullRefresh(reason or "refresh")
    else
        self:QueueActionRefresh(reason, "full")
    end
end

function BarManager:SetMouseoverFadeActive(state, active)
    if not state then return end
    active = active == true
    if state.active == active then return end
    state.active = active
    if active then
        BarManager.mouseoverFadeActiveCount = (BarManager.mouseoverFadeActiveCount or 0) + 1
    else
        BarManager.mouseoverFadeActiveCount = math.max(0, (BarManager.mouseoverFadeActiveCount or 1) - 1)
    end
end

function BarManager.MouseoverFadeFinished(group)
    local state = BarManager.mouseoverFadeGroups and BarManager.mouseoverFadeGroups[group]
    if not state then return end
    BarManager:SetMouseoverFadeActive(state, false)
    local record = state.record
    local holder = record and record.holder
    local alpha = state.toAlpha
    if holder and alpha ~= nil then
        holder:SetAlpha(alpha)
        record.yabHolderAlpha = alpha
    end
end

function BarManager:GetMouseoverFadeCurrentAlpha(record, state)
    local holder = record and record.holder
    if not holder then return 1 end
    if state and state.active and state.group and state.group.GetProgress then
        local ok, progress = pcall(state.group.GetProgress, state.group)
        if ok and type(progress) == "number" then
            progress = math.max(0, math.min(1, progress))
            return (state.fromAlpha or 0) + (((state.toAlpha or 0) - (state.fromAlpha or 0)) * progress)
        end
    end
    if holder.GetAlpha then
        local alpha = holder:GetAlpha()
        if type(alpha) == "number" then return alpha end
    end
    return record.yabHolderAlpha or (state and state.toAlpha) or 1
end

function BarManager:EnsureMouseoverFade(record)
    local holder = record and record.holder
    if not (holder and holder.CreateAnimationGroup) then return nil end
    local state = self.mouseoverFadeStates[holder]
    if not state then
        local group = holder:CreateAnimationGroup()
        local animation = group and group.CreateAnimation and group:CreateAnimation("Alpha") or nil
        if not (group and animation) then return nil end
        if group.SetToFinalAlpha then group:SetToFinalAlpha(true) end
        if animation.SetOrder then animation:SetOrder(1) end
        group:SetScript("OnFinished", BarManager.MouseoverFadeFinished)
        state = { group = group, animation = animation }
        self.mouseoverFadeStates[holder] = state
        self.mouseoverFadeGroups[group] = state
    end
    state.record = record
    record.mouseoverFadeState = state
    return state
end

function BarManager:StopMouseoverFade(record, targetAlpha)
    local holder = record and record.holder
    if not holder then return false end
    local state = record.mouseoverFadeState or self.mouseoverFadeStates[holder]
    local alpha = targetAlpha
    if alpha == nil then
        alpha = self:GetMouseoverFadeCurrentAlpha(record, state)
    end
    if state and state.active then
        if state.group and state.group.Stop then state.group:Stop() end
        self:SetMouseoverFadeActive(state, false)
    end
    holder:SetAlpha(alpha)
    record.yabHolderAlpha = alpha
    return true
end

function BarManager:StartMouseoverFade(record, targetAlpha, duration)
    local holder = record and record.holder
    if not holder then return false end
    local state = self:EnsureMouseoverFade(record)
    if not state then
        return self:StopMouseoverFade(record, targetAlpha)
    end

    local currentAlpha = self:GetMouseoverFadeCurrentAlpha(record, state)
    if state.active then
        state.group:Stop()
        self:SetMouseoverFadeActive(state, false)
    end
    holder:SetAlpha(currentAlpha)
    record.yabHolderAlpha = currentAlpha

    duration = type(duration) == "number" and duration or 0
    if duration <= 0 or currentAlpha == targetAlpha then
        holder:SetAlpha(targetAlpha)
        record.yabHolderAlpha = targetAlpha
        state.fromAlpha = targetAlpha
        state.toAlpha = targetAlpha
        return true
    end

    state.fromAlpha = currentAlpha
    state.toAlpha = targetAlpha
    state.animation:SetDuration(duration)
    state.animation:SetFromAlpha(currentAlpha)
    state.animation:SetToAlpha(targetAlpha)
    self:SetMouseoverFadeActive(state, true)
    state.group:Play()
    return true
end

function BarManager:ReleaseMouseoverFade(record)
    if not record then return end
    local state = record.mouseoverFadeState
    self:StopMouseoverFade(record)
    if state then state.record = nil end
    record.mouseoverFadeState = nil
end

function BarManager:StopAllMouseoverFades()
    for _, state in pairs(self.mouseoverFadeStates or {}) do
        if state.active and state.group and state.group.Stop then
            state.group:Stop()
        end
        self:SetMouseoverFadeActive(state, false)
        if state.record then
            state.record.mouseoverFadeState = nil
        end
        state.record = nil
    end
    self.mouseoverFadeActiveCount = 0
end

local function VisibilityMouseChanged(frame)
    local manager = YAB.BarManager
    local record = manager and manager.mouseoverRecords and manager.mouseoverRecords[frame]
    if record and manager.UpdateMouseoverAlpha then
        manager:UpdateMouseoverAlpha(record, true)
    end
end

local function HookMouseoverFrame(manager, record, frame)
    if not (manager and record and frame) then return end
    manager.mouseoverRecords[frame] = record
    if not manager.mouseoverHooked[frame] and frame.HookScript then
        frame:HookScript("OnEnter", VisibilityMouseChanged)
        frame:HookScript("OnLeave", VisibilityMouseChanged)
        manager.mouseoverHooked[frame] = true
    end
end

local function IsMouseOverFrame(frame)
    return frame and frame.IsMouseOver and frame:IsMouseOver()
end

function BarManager:SetMouseMotionOnly(frame, enabled)
    if not frame then return false end
    local setClickEnabled = frame.SetMouseClickEnabled
    local setMotionEnabled = frame.SetMouseMotionEnabled or frame.EnableMouseMotion
    if not (setClickEnabled and setMotionEnabled) then
        if enabled ~= true and frame.EnableMouse then
            frame:EnableMouse(false)
        end
        return false
    end
    setClickEnabled(frame, false)
    setMotionEnabled(frame, enabled == true)
    return true
end

function BarManager:GetMouseoverProxy(record)
    local proxy = record and record.id == "main" and record.controller or nil
    if not (proxy
        and proxy.SetMouseClickEnabled
        and (proxy.SetMouseMotionEnabled or proxy.EnableMouseMotion)) then
        return nil
    end
    return proxy
end

function BarManager:SetMouseoverProxyMotion(record, enabled)
    local proxy = self:GetMouseoverProxy(record)
    if not proxy then return false end
    enabled = enabled == true
    if record.yabMouseoverProxyMotion == enabled then return true end
    if not self:SetMouseMotionOnly(proxy, enabled) then
        return false
    end
    record.yabMouseoverProxyMotion = enabled
    return true
end

function BarManager:SetMouseoverProxyRaised(record, raised)
    local proxy = self:GetMouseoverProxy(record)
    local holder = record and record.holder
    if not (proxy and holder and proxy.GetFrameLevel and proxy.SetFrameLevel and holder.GetFrameLevel) then
        return false
    end
    raised = raised == true
    if record.yabMouseoverProxyBaseLevel == nil then
        record.yabMouseoverProxyBaseLevel = proxy:GetFrameLevel() or 0
        record.yabMouseoverProxyBaseStrata = proxy.GetFrameStrata and proxy:GetFrameStrata() or nil
    end
    -- Reparenting the holder can change its strata. Frame levels only order
    -- frames within the same strata, so align both before moving the proxy.
    if proxy.GetFrameStrata and proxy.SetFrameStrata and holder.GetFrameStrata then
        local targetStrata = holder:GetFrameStrata()
        if proxy:GetFrameStrata() ~= targetStrata then
            proxy:SetFrameStrata(targetStrata)
        end
    end
    local holderLevel = holder:GetFrameLevel() or 0
    local targetLevel = raised and (holderLevel + 8) or math.max(holderLevel - 1, 0)
    if proxy:GetFrameLevel() ~= targetLevel then
        proxy:SetFrameLevel(targetLevel)
    end
    record.yabMouseoverProxyRaised = raised
    return true
end

function BarManager:ResetMouseoverProxy(record)
    if not record then return end
    self:SetMouseoverProxyMotion(record, false)
    local proxy = record.controller
    if proxy then
        local baseStrata = record.yabMouseoverProxyBaseStrata
        if baseStrata and proxy.GetFrameStrata and proxy.SetFrameStrata and proxy:GetFrameStrata() ~= baseStrata then
            proxy:SetFrameStrata(baseStrata)
        end
        local baseLevel = record.yabMouseoverProxyBaseLevel
        if baseLevel ~= nil and proxy.GetFrameLevel and proxy.SetFrameLevel and proxy:GetFrameLevel() ~= baseLevel then
            proxy:SetFrameLevel(baseLevel)
        end
    end
    record.yabMouseoverProxyBaseStrata = nil
    record.yabMouseoverProxyBaseLevel = nil
    record.yabMouseoverProxyRaised = nil
    if proxy and self.mouseoverRecords then
        self.mouseoverRecords[proxy] = nil
    end
end

local function SetHolderMouseMotion(holder, enabled)
    return BarManager:SetMouseMotionOnly(holder, enabled)
end

function BarManager:IsRecordMouseOver(record)
    if not record then return false end
    if IsMouseOverFrame(self:GetMouseoverProxy(record)) then return true end
    if IsMouseOverFrame(record.holder) then return true end
    local buttons = record.buttons
    if buttons then
        for index = 1, #buttons do
            if IsMouseOverFrame(buttons[index]) then
                return true
            end
        end
    end
    local externalFrames = record.externalFrames
    if externalFrames then
        for index = 1, #externalFrames do
            if IsMouseOverFrame(externalFrames[index]) then
                return true
            end
        end
    end
    local externalButtons = record.externalButtons
    if externalButtons then
        for index = 1, #externalButtons do
            if IsMouseOverFrame(externalButtons[index]) then
                return true
            end
        end
    end
    return false
end

function BarManager:EnsureMouseoverHooks(record)
    if not (record and record.holder) then return false end
    if InCombat() then
        record.mouseoverPending = true
        return false
    end
    local holder = record.holder
    HookMouseoverFrame(self, record, holder)
    local proxy = self:GetMouseoverProxy(record)
    if proxy then
        HookMouseoverFrame(self, record, proxy)
        self:SetMouseoverProxyMotion(record, true)
    end
    local buttons = record.buttons
    if buttons then
        for index = 1, #buttons do
            HookMouseoverFrame(self, record, buttons[index])
        end
    end
    local externalFrames = record.externalFrames
    if externalFrames then
        for index = 1, #externalFrames do
            HookMouseoverFrame(self, record, externalFrames[index])
        end
    end
    local externalButtons = record.externalButtons
    if externalButtons then
        for index = 1, #externalButtons do
            HookMouseoverFrame(self, record, externalButtons[index])
        end
    end
    SetHolderMouseMotion(holder, true)
    self:EnsureMouseoverFade(record)
    record.yabMouseoverEnabled = true
    record.mouseoverPending = nil
    return true
end

function BarManager:UpdateMouseoverAlpha(record, animate)
    local holder = record and record.holder
    if not (holder and holder.SetAlpha) then return false end
    local snapshot = record.configSnapshot
    local bindPresentation = self:IsRecordInBindPresentation(record)
    local baseAlpha = bindPresentation and 1 or GetSnapshotAlpha(snapshot)
    local branch = snapshot and snapshot.visibilityRule and YUI.Visibility:GetBranch(snapshot.visibilityRule, InCombat())
    local mouseoverMode = not bindPresentation and snapshot
        and (branch and branch.mode == "hover" or not branch and snapshot.visibility == "mouseover")
    local visibilityAlpha = 1
    if mouseoverMode then
        visibilityAlpha = ((self.emptySlotGridVisible == true and not InCombat()) or self:IsRecordMouseOver(record)) and 1 or 0
    end
    local alpha = baseAlpha * visibilityAlpha
    local state = record.mouseoverFadeState
    local targetChanged = record.yabMouseoverAlpha ~= visibilityAlpha or record.yabHolderTargetAlpha ~= alpha
    if targetChanged or (animate ~= true and state and state.active) then
        if animate == true and mouseoverMode then
            local duration = visibilityAlpha == 1 and self.mouseoverFadeInDuration or self.mouseoverFadeOutDuration
            self:StartMouseoverFade(record, alpha, duration)
        else
            self:StopMouseoverFade(record, alpha)
        end
        record.yabMouseoverAlpha = visibilityAlpha
        record.yabHolderTargetAlpha = alpha
    end
    if mouseoverMode then
        self:SetMouseoverProxyRaised(record, visibilityAlpha == 0)
    elseif snapshot and snapshot.visibilityRule
        and (snapshot.visibilityRule.inCombat.mode == "hover" or snapshot.visibilityRule.outOfCombat.mode == "hover") then
        -- Keep the preinstalled motion proxy ready for the other combat branch.
        -- It stays below buttons and never captures clicks.
        self:SetMouseoverProxyRaised(record, false)
    else
        self:ResetMouseoverProxy(record)
    end
    return true
end

function BarManager:ApplyMouseoverVisibility(record)
    if not (record and record.holder) then return false end
    local snapshot = record.configSnapshot
    local rule = snapshot and snapshot.visibilityRule
    local needsHover = rule and (rule.inCombat.mode == "hover" or rule.outOfCombat.mode == "hover")
        or snapshot and snapshot.visibility == "mouseover"
    if needsHover then
        self:EnsureMouseoverHooks(record)
    elseif record.yabMouseoverEnabled == true then
        if InCombat() then
            record.mouseoverPending = true
        else
            SetHolderMouseMotion(record.holder, false)
            record.yabMouseoverEnabled = false
            record.mouseoverPending = nil
        end
    end
    if not needsHover then
        self:ResetMouseoverProxy(record)
    end
    return self:UpdateMouseoverAlpha(record)
end

function BarManager:ApplyEmptySlotVisibilityForButton(button, state, snapshot, forceShow)
    if not button then return false end
    snapshot = snapshot or GetButtonConfigSnapshot(self, button)
    local shouldShow = true
    local bindPresentation = false
    if self.bindPresentationActive == true then
        local meta = GetButtonMeta(button)
        local record = meta and meta.barId and self.bars and self.bars[meta.barId] or nil
        bindPresentation = self:IsBindPresentationEligible(record)
    end
    if forceShow ~= true and not bindPresentation and snapshot and snapshot.hideEmptySlots == true and (not state or state.hasAction ~= true) and self.emptySlotGridVisible ~= true then
        shouldShow = false
    end
    if InCombat() then
        if self.emptyButtonShown[button] ~= shouldShow then
            self.pendingEmptyButtonShown[button] = shouldShow
            self.emptySlotPending = true
        else
            self.pendingEmptyButtonShown[button] = nil
        end
        return false
    end
    if self.emptyButtonShown[button] ~= shouldShow then
        SetManagedActionButtonShown(self, button, shouldShow)
    end
    self.pendingEmptyButtonShown[button] = nil
    return true
end

function BarManager:ApplyRecordEmptySlotVisibility(record)
    if not (record and record.kind == "action" and record.emptySlotReady == true) then return true end
    local buttons = record.buttons
    if not buttons then return true end
    local ok = true
    for index = 1, #buttons do
        local button = buttons[index]
        if button and not self:ApplyEmptySlotVisibilityForButton(button, self.buttonStates and self.buttonStates[button], record.configSnapshot) then
            ok = false
        end
    end
    return ok
end

function BarManager:BuildRecordVisibilityDriver(record)
    if self:IsRecordInBindPresentation(record) then
        return "show"
    end
    local snapshot = record and record.configSnapshot
    local gridPresentation = self.emptySlotGridVisible == true
        and record
        and record.kind == "action"
        and not InCombat()
    local mode = gridPresentation and "always" or (snapshot and snapshot.visibility or "always")
    local hideSkyriding = not gridPresentation and snapshot and snapshot.hideSkyriding == true
    return YAB.Adapter and YAB.Adapter:BuildVisibilityDriver(mode, hideSkyriding, record) or "show"
end

function BarManager:OnVisibilityDisposition(_, _, record)
    if record then self:UpdateMouseoverAlpha(record, false) end
end

function BarManager:ApplyRecordVisibility(record)
    local service = YUI.Visibility
    local rule = record.configSnapshot and record.configSnapshot.visibilityRule
    if not (service and rule) then
        return YAB.Drivers:RegisterVisibility(record.holder, self:BuildRecordVisibilityDriver(record))
    end
    local bypass = self:IsRecordInBindPresentation(record)
        or (self.emptySlotGridVisible == true and record.kind == "action" and not InCombat())
    bypass = bypass and "outOfCombat" or false
    local guard = YAB.Adapter:BuildVisibilityDriver("always", false, record)
    local handle = record.visibilityHandle
    if handle and handle.active then
        service:SetGuard(handle, guard)
        service:SetBypass(handle, bypass)
        return service:Update(handle, rule)
    end
    self:ApplyMouseoverVisibility(record)
    local err
    handle, err = service:Register({
        backend = "secure", owner = self, moduleId = YAB.PRODUCT_ID,
        target = record.holder, context = record, rule = rule, guard = guard,
        bypass = bypass, capabilities = { hover = true }, callback = "OnVisibilityDisposition",
    })
    record.visibilityHandle = handle
    record.visibilityError = err
    return handle ~= nil
end

function BarManager:ApplyEmptySlotGridVisibility()
    local ok = true
    for _, record in pairs(self.bars or {}) do
        if record and record.kind == "action" then
            if record.holder
                and YAB.Drivers
                and not self:ApplyRecordVisibility(record) then
                ok = false
            end
            ok = self:ApplyRecordEmptySlotVisibility(record) ~= false and ok
            self:ApplyMouseoverVisibility(record)
        end
    end
    return ok
end

function BarManager:HandleEmptySlotGridEvent(event)
    local visible = event == "ACTIONBAR_SHOWGRID"
    if self.emptySlotGridVisible == visible then
        return true
    end
    self.emptySlotGridVisible = visible
    self:MarkReason(event, "empty-grid", false)
    return self:ApplyEmptySlotGridVisibility()
end

function BarManager:ApplyPendingEmptySlots()
    if InCombat() then return false end
    if next(self.pendingEmptyButtonShown) == nil and self.emptySlotPending ~= true then return false end
    for button, pending in pairs(self.pendingEmptyButtonShown) do
        local meta = GetButtonMeta(button)
        local record = meta and meta.barId and self.bars and self.bars[meta.barId] or nil
        if not (record and record.kind == "action") then
            SetManagedActionButtonShown(self, button, pending)
        end
    end
    ClearTable(self.pendingEmptyButtonShown)
    self.emptySlotPending = false
    for _, record in pairs(self.bars or {}) do
        if record and record.kind == "action" then
            self:ApplyRecordEmptySlotVisibility(record)
        end
    end
    return true
end

function BarManager:RefreshActionButton(button, page, index, db, mode, diagnostic)
    if diagnostic then
        diagnostic.candidates = diagnostic.candidates + 1
        diagnostic.buttons = diagnostic.buttons + 1
        diagnostic.backendReads = diagnostic.backendReads + 1
    end
    local snapshot = GetButtonConfigSnapshot(self, button)
    local rangeEnabled = IsRangeSnapshotEnabled(snapshot)
    local meta = GetButtonMeta(button)
    local barId = meta and meta.barId
    local slot = self:GetRecordButtonActionSlot(barId, button, page, index)
    if not InCombat() and meta and meta.barId and meta.slot ~= slot and YAB.SecureFactory and YAB.SecureFactory.SyncActionButtonState then
        local record = barId and self.bars and self.bars[barId]
        local syncPage = page
        if barId == "main" then
            syncPage = math.floor((slot - 1) / 12) + 1
        end
        YAB.SecureFactory:SyncActionButtonState(button, button:GetParent(), record and record.controller, barId, (meta and meta.index) or index, syncPage)
        meta = GetButtonMeta(button)
    end
    self:MapButtonSlot(button, slot)
    self:TrackRangeSlot(slot, snapshot)

    local state = self:GetButtonState(button)
    local hotBackend = self.actionHotBackend
    if self.actionHotBackendReady ~= true then
        hotBackend = self:PrepareActionHotBackend()
    end
    local refreshCount = false
    local refreshNativeCooldown = false
    local displayText
    local displayAuthoritative = false
    local displaySecret = false
    mode = mode or "full"
    if state.slot ~= slot or mode == "identity" then
        mode = "full"
    end
    local identityRefreshed = false
    if mode == "full" or not state.identityReady then
        local previousIdentityReady = state.identityReady == true
        local previousSlot = state.slot
        local previouslyHadFlyout = state.flyoutID ~= nil
        identityRefreshed = true
        self:UnmapButtonProc(button, state)
        ResetVisualState(state)
        state.slot = slot
        local maxDisplayCount = button and button.maxDisplayCount
        if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
        YAB.Adapter:ReadActionIdentity(slot, state, maxDisplayCount, hotBackend)
        local hasFlyout = state.flyoutID ~= nil
        if previousIdentityReady
            and previousSlot == slot
            and previouslyHadFlyout ~= hasFlyout
            and YAB.SecureFactory
            and YAB.SecureFactory.SyncActionFlyoutIdentity then
            YAB.SecureFactory:SyncActionFlyoutIdentity(button, hasFlyout)
        end
        self:SetButtonAssistedCombatSlot(button, slot, state.hasAction == true and state.assistedCombat == true)
        refreshCount = true
        refreshNativeCooldown = true
        if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
        YAB.Adapter:ReadActionUsable(slot, state)
        if rangeEnabled then
            if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
            YAB.Adapter:ReadActionRange(slot, state)
        else
            state.inRange = nil
        end
        if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 2 end
        YAB.Adapter:ReadActionState(slot, state)
        YAB.Adapter:ReadActionGlow(slot, state)
        state.identityReady = true
        self:MapButtonProc(button, state)
        self:ResyncButtonProcGlow(button, state)
    else
        local refreshCooldownState = RefreshModeHas(mode, "cooldown") or RefreshModeHas(mode, "cooldownMeta")
        if refreshCooldownState or RefreshModeHas(mode, "text") then
            local maxDisplayCount = button and button.maxDisplayCount
            if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
            YAB.Adapter:ReadActionCounts(slot, state, maxDisplayCount, hotBackend)
            refreshCount = true
            refreshNativeCooldown = refreshCooldownState
        end
        if RefreshModeHas(mode, "usable") then
            if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
            YAB.Adapter:ReadActionUsable(slot, state)
            if rangeEnabled then
                if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
                YAB.Adapter:ReadActionRange(slot, state)
            else
                state.inRange = nil
            end
        elseif rangeEnabled and RefreshModeHas(mode, "range") then
            if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
            YAB.Adapter:ReadActionRange(slot, state)
        end
        if RefreshModeHas(mode, "state") then
            if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
            YAB.Adapter:ReadActionState(slot, state)
        end
        if RefreshModeHas(mode, "glow") then
            if diagnostic then diagnostic.backendReads = diagnostic.backendReads + 1 end
            YAB.Adapter:ReadActionGlow(slot, state)
            self:ResyncButtonProcGlow(button, state)
        end
    end

    if refreshCount and hotBackend and hotBackend.mode == "retail-duration" then
        if snapshot.showCounts ~= true then
            displayText = ""
            displayAuthoritative = true
        else
            displayText, displayAuthoritative, displaySecret = GetNativeCoreDisplayCount(
                slot,
                button,
                snapshot,
                hotBackend.getDisplayCount,
                hotBackend.getActionCount,
                diagnostic
            )
        end
        if displayAuthoritative and displaySecret ~= true then
            state.displayCount = displayText
        else
            state.displayCount = nil
        end
    end

    state.rangeMode = snapshot.rangeMode
    if rangeEnabled and self.rangeOut[slot] ~= nil then
        state.inRange = self.rangeOut[slot] == false
    elseif not rangeEnabled then
        state.inRange = nil
    end
    if mode == "full" or RefreshModeHas(mode, "aura") then
        state.auraActive = false
        state.auraStart = nil
        state.auraDuration = nil
        state.auraExpirationTime = nil
        self:ApplyAuraState(state, db)
    end
    state.countText = BuildCountText(state, snapshot)
    state.nameText = BuildNameText(state, snapshot)
    if snapshot.showHotkeys == true then
        if mode == "full" or RefreshModeHas(mode, "hotkey") or not state.hotkeyReady then
            local key = nil
            if meta and meta.barId and meta.index then
                key = YAB.Keybinds:GetBindingText(YAB.Keybinds:GetButtonKey(meta.barId, meta.index))
            end
            state.hotkeyText = key or ""
            state.hotkeyReady = true
        end
    elseif state.hotkeyText ~= "" or not state.hotkeyReady then
        state.hotkeyText = ""
        state.hotkeyReady = true
    end
    if snapshot.cooldownFade == false then
        if diagnostic then
            diagnostic.writes = diagnostic.writes + (ClearNativeCoreDesaturationState(self, button) or 0)
        else
            ClearNativeCoreDesaturationState(self, button)
        end
    end
    if diagnostic then
        diagnostic.writes = diagnostic.writes + (UpdateButtonVisual(button, state, mode) or 0)
    else
        UpdateButtonVisual(button, state, mode)
    end
    if identityRefreshed then
        local qualityAtlas
        if state.hasAction == true and state.actionType == "item" then
            local actionBarAPI = YUI.API and YUI.API.ActionBar
            if actionBarAPI and actionBarAPI.GetProfessionQualityAtlas then
                qualityAtlas = actionBarAPI:GetProfessionQualityAtlas(slot)
            end
        end
        local qualityWrites = YAB.Visuals and YAB.Visuals.ApplyProfessionQuality
            and YAB.Visuals:ApplyProfessionQuality(button, qualityAtlas, snapshot) or 0
        if diagnostic then diagnostic.writes = diagnostic.writes + qualityWrites end
    end
    if refreshNativeCooldown then
        if diagnostic then
            diagnostic.writes = diagnostic.writes + (ApplyNativeCoreCooldownButton(self, button, slot, snapshot, hotBackend, false, diagnostic) or 0)
        else
            ApplyNativeCoreCooldownButton(self, button, slot, snapshot, hotBackend, false)
        end
    end
    if refreshCount then
        local nativeState = GetNativeCoreState(self, button)
        if diagnostic then
            if displayAuthoritative and displaySecret == true then
                diagnostic.writes = diagnostic.writes + (SetNativeCoreCountText(self, nativeState, button, displayText, true) or 0)
            else
                diagnostic.writes = diagnostic.writes + (SetNativeCoreCountText(self, nativeState, button, state.countText, false) or 0)
            end
        else
            if displayAuthoritative and displaySecret == true then
                SetNativeCoreCountText(self, nativeState, button, displayText, true)
            else
                SetNativeCoreCountText(self, nativeState, button, state.countText, false)
            end
        end
    end
    self:ApplyEmptySlotVisibilityForButton(button, state, GetButtonConfigSnapshot(self, button))
    if identityRefreshed then
        self:RefreshActionHotRecord(button, slot, snapshot, hotBackend)
    end
    return true
end

function BarManager:RefreshPetButton(button, index, db)
    local snapshot = GetButtonConfigSnapshot(self, button, "pet")
    local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled = YAB.Adapter:GetPetActionInfo(index)
    local layoutEditing = IsLayoutEditing()
    button.tooltipName = name
    button.tooltipSubtext = nil
    local state = ResetVisualState(self.visualState)
    state.rangeMode = snapshot.rangeMode
    state.hasAction = texture ~= nil or name ~= nil
    state.texture = isToken and texture and _G[texture] or texture
    state.usable = not state.hasAction or YAB.Adapter:IsPetActionUsable(index)
    state.checked = isActive == true
    state.procGlow = false
    state.petAutoCastAllowed = autoCastAllowed == true
    state.petAutoCastEnabled = autoCastEnabled == true
    local start, duration, enable = YAB.Adapter:GetPetActionCooldown(index)
    state.cooldownStart = start
    state.cooldownDuration = duration
    state.cooldownEnable = enable
    state.cooldownActive = enable == true and type(duration) == "number" and duration > 0
    local key = YAB.Keybinds:GetBindingText(YAB.Keybinds:GetButtonKey("pet", index))
    state.hotkeyText = snapshot.showHotkeys == true and key or ""
    if layoutEditing then
        state.hasAction = false
        state.texture = nil
        state.checked = false
        state.petAutoCastAllowed = false
        state.petAutoCastEnabled = false
    end
    UpdateButtonVisual(button, state, "full")
    if layoutEditing then
        SetManagedActionButtonShown(self, button, false)
    else
        self:ApplyEmptySlotVisibilityForButton(button, state, snapshot, true)
    end
end

function BarManager:RefreshStanceButton(button, index, db)
    local snapshot = GetButtonConfigSnapshot(self, button, "stance")
    local iconTexture, active, castable, spellID = YAB.Adapter:GetShapeshiftFormInfo(index)
    local formAvailable = iconTexture ~= nil or spellID ~= nil
        or (index > 0 and index <= GetStanceFormCount())
    local meta = GetButtonMeta(button)
    local ownedStanceTemplate = YAB.Client.ownedStanceButtons == true and meta and meta.ownedStanceTemplate == true
    if ownedStanceTemplate and InCombat() and not formAvailable then
        return false
    end
    if YAB.Client.ownedStanceButtons ~= true
        and not InCombat()
        and YAB.SecureFactory
        and YAB.SecureFactory.SetSpellAction then
        YAB.SecureFactory:SetSpellAction(button, spellID)
    end
    local state = ResetVisualState(self.visualState)
    state.rangeMode = snapshot.rangeMode
    state.hasAction = formAvailable == true
    state.texture = iconTexture
    state.usable = castable ~= false
    state.checked = active == true
    local start, duration, enable = YAB.Adapter:GetShapeshiftFormCooldown(index)
    state.cooldownStart = start
    state.cooldownDuration = duration
    state.cooldownEnable = enable
    state.cooldownActive = enable == true and type(start) == "number" and type(duration) == "number"
        and duration > 0 and (not GetTime or start + duration > GetTime())
    if enable == true and state.cooldownActive ~= true then
        state.cooldownEnable = false
    end
    local key = YAB.Keybinds:GetBindingText(YAB.Keybinds:GetButtonKey("stance", index))
    state.hotkeyText = snapshot.showHotkeys == true and key or ""
    local cooldownState = GetNativeCoreState(self, button)
    InstallNativeCoreCooldownDone(button)
    -- Clear/SetCooldown may finish the previous swipe synchronously.
    cooldownState.stanceCooldownUpdating = true
    UpdateButtonVisual(button, state, "full")
    cooldownState.stanceCooldownUpdating = false
    self:ApplyEmptySlotVisibilityForButton(button, state, snapshot, IsBindPresentationEditing("stance"))
    return true
end

function BarManager:RefreshPossessButton(button, index, db)
    local snapshot = GetButtonConfigSnapshot(self, button, "possess")
    local texture, spellID, enabled = YAB.Adapter:GetPossessInfo(index)
    local state = ResetVisualState(self.visualState)
    state.rangeMode = snapshot.rangeMode
    state.hasAction = texture ~= nil
    state.texture = texture
    state.usable = enabled ~= false
    local key = YAB.Keybinds:GetBindingText(YAB.Keybinds:GetButtonKey("possess", index))
    state.hotkeyText = snapshot.showHotkeys == true and key or ""
    UpdateButtonVisual(button, state, "full")
    if spellID and not InCombat() then
        if YAB.SecureFactory and YAB.SecureFactory.SetSpellAction then
            YAB.SecureFactory:SetSpellAction(button, spellID)
        end
    end
    if not state.hasAction and IsPresentationEditing("possess") then
        local placeholderTexture = GetSpecialPlaceholderTexture("possess", index)
        if placeholderTexture then
            state.hasAction = true
            state.texture = placeholderTexture
            state.usable = true
            UpdateButtonVisual(button, state, "full")
        end
    end
    if not InCombat() then
        if state.hasAction then button:Show() else button:Hide() end
    end
end

function BarManager:RefreshSpecialLayoutIfNeeded(kind, record, db)
    if not IsCompactSpecialLayoutRecord(record) then return false end
    local config = GetSpecialConfig(db, kind)
    if not config then return false end
    local snapshot = record.configSnapshot or self:GetConfigSnapshot(kind) or DEFAULT_CONFIG_SNAPSHOT
    local count = GetManagedSpecialButtonCount(kind, config, snapshot)
    local _, visibleCount, signature = BuildLayoutButtons(record, count)
    if signature == record.layoutVisibleSignature and visibleCount == record.layoutVisibleCount then
        return false
    end
    if InCombat() then
        record.layoutPending = true
        return false
    end
    self:ApplyLayout(record, config, db)
    record.layoutPending = nil
    return true
end

function BarManager:GetActionPageForRecord(barId, record, config, pageState)
    if barId == "main" then
        pageState = pageState or self:GetPageState(false)
        return pageState.effectiveMainPage or pageState.actionPage or 1
    end
    return record.page or (YAB.Adapter and YAB.Adapter:GetActionBarPageForBar(barId, config and config.page)) or (config and config.page) or 1
end

function BarManager:RefreshActionRecord(barId, record, config, db, pageState, mode, diagnostic)
    local page = self:GetActionPageForRecord(barId, record, config, pageState)
    for index, button in ipairs(record.buttons or {}) do
        self:RefreshActionButton(button, page, index, db, mode, diagnostic)
    end
    record.emptySlotReady = true
end

function BarManager:RefreshAllActionButtons(db, pageState, mode, diagnostic)
    for barId, record in pairs(self.bars) do
        if record.kind == "action" then
            local config = GetBarConfig(db, barId)
            self:RefreshActionRecord(barId, record, config, db, pageState, mode or "full", diagnostic)
        end
    end
end

function BarManager:RefreshDirtySlots(db, pageState, dirtySlots, diagnostic)
    for slot, mode in pairs(dirtySlots or self.dirtySlots) do
        local list = self.slotButtons and self.slotButtons[slot]
        if list then
            local probe
            local probeValid = false
            if mode == "identity"
                and self.slotIdentityNarrowDisabled ~= true
                and YAB.Adapter
                and YAB.Adapter.ReadActionSafeIdentity then
                local hotBackend = self.actionHotBackend
                if self.actionHotBackendReady ~= true then
                    hotBackend = self:PrepareActionHotBackend()
                end
                probe = self.slotIdentityScratch
                YAB.Adapter:ReadActionSafeIdentity(slot, probe, hotBackend)
                probeValid = true
                if diagnostic then
                    diagnostic.backendReads = diagnostic.backendReads + 3
                    if probe.hasAction ~= true or probe.actionType == "spell" then
                        diagnostic.backendReads = diagnostic.backendReads + 5
                        if not self:ValidateSlotIdentityProbe(slot, probe, hotBackend) then
                            diagnostic.fallbacks = diagnostic.fallbacks + 1
                            probeValid = false
                        end
                    end
                end
            end
            for index = 1, #list do
                local button = list[index]
                local meta = GetButtonMeta(button)
                local barId = meta and meta.barId
                local record = barId and self.bars and self.bars[barId]
                local config = barId and GetBarConfig(db, barId)
                if button and record and config then
                    local narrow = probeValid and self:TryRefreshUnchangedSlotIdentity(button, slot, probe, diagnostic)
                    if narrow then
                        if diagnostic then
                            diagnostic.candidates = diagnostic.candidates + 1
                            diagnostic.buttons = diagnostic.buttons + 1
                        end
                    else
                        local page = self:GetActionPageForRecord(barId, record, config, pageState)
                        self:RefreshActionButton(button, page, (meta and meta.index) or index, db, mode, diagnostic)
                    end
                end
            end
        end
    end
end

function BarManager:RefreshSpecialRecord(kind, db, reconcileAttempted, reconciled, configuredCount)
    local record = self.bars and self.bars[kind]
    if not record then return end
    local config = GetSpecialConfig(db, kind)
    if not config then return end
    if reconcileAttempted ~= true then
        reconciled, _, configuredCount = self:ReconcileSpecialButtons(kind, record, config)
    end
    if not reconciled and not InCombat() then return end
    local refreshCount = configuredCount or GetSpecialButtonCount(kind, config, record.configSnapshot or self:GetConfigSnapshot(kind))
    if not reconciled and InCombat() then
        refreshCount = #record.buttons
    end
    if kind == "pet" then
        for index = 1, refreshCount do
            local button = record.buttons and record.buttons[index]
            if button then self:RefreshPetButton(button, index, db) end
        end
    elseif kind == "stance" then
        for index = 1, refreshCount do
            local button = record.buttons and record.buttons[index]
            if button then self:RefreshStanceButton(button, index, db) end
        end
    elseif kind == "possess" then
        for index = 1, refreshCount do
            local button = record.buttons and record.buttons[index]
            if button then self:RefreshPossessButton(button, index, db) end
        end
    end
    self:RefreshSpecialLayoutIfNeeded(kind, record, db)
end

function BarManager:FlushPendingStanceRefresh()
    if InCombat() then return 0 end
    local record = self.bars and self.bars.stance
    if not record or (record.pendingButtonCount == nil and record.layoutPending ~= true) then
        return 0
    end
    self:RefreshSpecialRecord("stance", GetDB())
    if record.pendingButtonCount ~= nil or record.layoutPending == true then
        return 0
    end
    return 1
end

function BarManager:RefreshDirtySpecialBars(db, dirtySpecialBars)
    for kind in pairs(dirtySpecialBars or self.dirtySpecialBars) do
        if EXTERNAL_SPECIAL_BARS[kind] then
            self:RefreshExternalSpecialBar(kind, "queued external special")
        else
            self:RefreshSpecialRecord(kind, db)
        end
    end
end

local SETTINGS_ACTION_REFRESH_MODE = ":hotkey:text:range:state:"

function BarManager:ApplySettingsVisualRecord(record, config, db)
    if InCombat() or not (record and config) then return end
    if EXTERNAL_SPECIAL_BARS[record.kind] then
        return self:ApplyExternalSpecialLayout(record, config, db)
    end
    local snapshot = record.configSnapshot or (record.id and self:GetConfigSnapshot(record.id)) or DEFAULT_CONFIG_SNAPSHOT
    local size = tonumber(snapshot and snapshot.size) or GetSize(config, db)
    local skin = YAB.Skins and YAB.Skins:Normalize("default")
    for _, button in ipairs(record.buttons or {}) do
        if button then
            SetButtonConfigSnapshot(self, button, snapshot)
            if YAB.Visuals and YAB.Visuals.ApplyRuntimeSnapshot then
                YAB.Visuals:ApplyRuntimeSnapshot(button, snapshot)
            elseif YAB.Skins and skin then
                local width = button.GetWidth and button:GetWidth() or size
                local height = button.GetHeight and button:GetHeight() or size
                if not width or width <= 0 then width = size end
                if not height or height <= 0 then height = size end
                YAB.Skins:ApplyButton(button, skin, { size = size, width = width, height = height, zoom = snapshot.iconZoom, snapshot = snapshot })
            end
        end
    end
end

function BarManager:RefreshSettingsActionRecord(barId, record, config, db, pageState, mode, diagnostic)
    if not (record and config) then return end
    if record.kind == "action" then
        self:RefreshActionRecord(barId, record, config, db, pageState, mode or SETTINGS_ACTION_REFRESH_MODE, diagnostic)
    elseif record.kind == "pet" or record.kind == "stance" or record.kind == "possess" then
        self:RefreshSpecialRecord(record.kind, db)
    elseif EXTERNAL_SPECIAL_BARS[record.kind] then
        self:ApplyExternalSpecialLayout(record, config, db)
    end
end

function BarManager:RefreshDirtySettings(db, pageState, dirtySettingBars, diagnostic)
    local visibilityDirty = false
    for barId, scope in pairs(dirtySettingBars or self.dirtySettingBars) do
        if barId == "questItems" and YAB.QuestItems then YAB.QuestItems:SyncEnabled() end
        local record = self.bars and self.bars[barId]
        if record then
            local config = GetBarConfig(db, barId) or GetSpecialConfig(db, barId)
            self:AttachConfigSnapshot(record, barId, config, record.kind == "action" and "normal" or "special")

            local layoutChanged = false
            local refreshRecord = SettingScopeHas(scope, "action")
            if SettingScopeHas(scope, "layout") then
                refreshRecord = true
                if record.kind == "action" and config and not InCombat() then
                    local ok, changed = self:ReconcileActionBarButtons(barId, record, config, pageState)
                    layoutChanged = ok == true and changed == true
                elseif (record.kind == "pet" or record.kind == "stance" or record.kind == "possess") and config and not InCombat() then
                    local ok, changed = self:ReconcileSpecialButtons(
                        record.kind,
                        record,
                        config
                    )
                    layoutChanged = ok == true and changed == true
                end
                if record.holder and config and not InCombat() then
                    if EXTERNAL_SPECIAL_BARS[record.kind] then
                        self:ApplyExternalSpecialLayout(record, config, db)
                    else
                        self:ApplyLayout(record, config, db)
                    end
                end
            elseif SettingScopeHas(scope, "visual") then
                self:ApplySettingsVisualRecord(record, config, db)
            end

            if refreshRecord then
                self:RefreshSettingsActionRecord(barId, record, config, db, pageState, layoutChanged and "identity" or SETTINGS_ACTION_REFRESH_MODE, diagnostic)
            end
            if SettingScopeHas(scope, "visibility") then
                visibilityDirty = true
            end
        end
    end
    if visibilityDirty then
        self:ApplyVisibility()
    end
end

function BarManager:RefreshVisuals(reason, diagnostic)
    local db = GetDB()
    if not db then return end

    local dirtySlots = self.dirtySlots
    self.dirtySlots = self.processingDirtySlots
    self.processingDirtySlots = dirtySlots
    ClearTable(self.dirtySlots)

    local dirtySpecialBars = self.dirtySpecialBars
    self.dirtySpecialBars = self.processingDirtySpecialBars
    self.processingDirtySpecialBars = dirtySpecialBars
    ClearTable(self.dirtySpecialBars)

    local dirtySettingBars = self.dirtySettingBars
    self.dirtySettingBars = self.processingDirtySettingBars
    self.processingDirtySettingBars = dirtySettingBars
    ClearTable(self.dirtySettingBars)

    local dirtyActionMode = self.dirtyActionMode
    self.dirtyActionMode = nil
    local dirtyMainPageIdentity = self.dirtyMainPageIdentity == true
    self.dirtyMainPageIdentity = false
    local dirtyGlobalIcon = self.dirtyGlobalIcon == true
    self.dirtyGlobalIcon = false
    local fullRefresh = self.fullRefreshPending == true
    local fullRefreshReason = self.pendingFullRefreshReason
    self.fullRefreshPending = false
    self.pendingFullRefreshReason = nil
    local auraDirty = self.auraDirty == true
    self.auraDirty = false
    local passReason = fullRefresh and (fullRefreshReason or reason or "refresh") or (reason or self.lastRefreshReason)
    if diagnostic then
        local passMode = "none"
        local passSourceCount = 0
        if fullRefresh then
            passMode = "full"
            passSourceCount = 1
        else
            if dirtyActionMode then passMode = dirtyActionMode; passSourceCount = passSourceCount + 1 end
            if dirtyMainPageIdentity then passMode = "page"; passSourceCount = passSourceCount + 1 end
            if dirtyGlobalIcon then passMode = "icon"; passSourceCount = passSourceCount + 1 end
            if next(dirtySlots) ~= nil then passMode = "slot"; passSourceCount = passSourceCount + 1 end
            if next(dirtySpecialBars) ~= nil then passMode = "special"; passSourceCount = passSourceCount + 1 end
            if next(dirtySettingBars) ~= nil then passMode = "settings"; passSourceCount = passSourceCount + 1 end
            if auraDirty then passMode = "aura"; passSourceCount = passSourceCount + 1 end
            if passSourceCount > 1 then passMode = "mixed" end
        end
        HotDiagnostics:RecordRefreshPass(diagnostic, passReason, passMode, fullRefresh and "full" or "partial")
        diagnostic.changes = diagnostic.changes
            + CountTableKeys(dirtySlots)
            + CountTableKeys(dirtySpecialBars)
            + CountTableKeys(dirtySettingBars)
        if fullRefresh then diagnostic.fallbacks = diagnostic.fallbacks + 1 end
    end
    self.lastRefreshReason = passReason
    local identityPassGeneration = self.actionIdentityGeneration
    local identityPassKind
    if fullRefresh then
        identityPassKind = "full"
    elseif RefreshModeUpdatesActionIdentity(dirtyActionMode) then
        identityPassKind = "all"
    elseif dirtyMainPageIdentity or DirtySlotsUpdateActionIdentity(dirtySlots) then
        identityPassKind = "delta"
    end
    local identityDeltaEligible = identityPassKind == "delta"
        and self.procIndexDeltaCompleteEligible == true
        and self.procIndexDeltaGeneration == identityPassGeneration

    if fullRefresh or auraDirty then
        self:RefreshAuraCache(db, true)
    elseif not AuraTimersEnabled(db) then
        self:RefreshAuraCache(db, false)
    end
    local settingsDirty = next(dirtySettingBars) ~= nil
    local needsPageState = fullRefresh or dirtyMainPageIdentity or settingsDirty or dirtyActionMode ~= nil or next(dirtySlots) ~= nil
    local pageState = needsPageState and self:GetPageState(fullRefresh or dirtyMainPageIdentity) or self.pageStateCache

    if fullRefresh then
        self:RefreshConfigSnapshots(db)
        for barId, record in pairs(self.bars) do
            local config = GetBarConfig(db, barId) or GetSpecialConfig(db, barId)
            self:AttachConfigSnapshot(record, barId, config, record.kind == "action" and "normal" or "special")
            local specialReconcileAttempted = false
            local specialReconciled = false
            local specialConfiguredCount
            if record.kind == "action" and config and not InCombat() then
                self:ReconcileActionBarButtons(barId, record, config, pageState)
            elseif (record.kind == "pet" or record.kind == "stance" or record.kind == "possess") and config and not InCombat() then
                specialReconcileAttempted = true
                specialReconciled, _, specialConfiguredCount = self:ReconcileSpecialButtons(
                    record.kind,
                    record,
                    config
                )
            end
            if record.holder and config and not InCombat() then
                if EXTERNAL_SPECIAL_BARS[record.kind] then
                    self:ApplyExternalSpecialLayout(record, config, db)
                else
                    self:ApplyLayout(record, config, db)
                end
            end
            if record.kind == "action" then
                self:RefreshActionRecord(barId, record, config, db, pageState, "full", diagnostic)
            elseif record.kind == "pet" or record.kind == "stance" or record.kind == "possess" then
                self:RefreshSpecialRecord(
                    record.kind,
                    db,
                    specialReconcileAttempted,
                    specialReconciled,
                    specialConfiguredCount
                )
            end
        end
        self:ApplyVisibility()
        if not InCombat() then
            self.mainPageSyncPending = false
        end
    else
        if settingsDirty then
            self:RefreshDirtySettings(db, pageState, dirtySettingBars, diagnostic)
        end
        if dirtyMainPageIdentity then
            local record = self.bars and self.bars.main
            local config = GetBarConfig(db, "main")
            if record and config then
                self:RefreshActionRecord("main", record, config, db, pageState, "identity", diagnostic)
                if not InCombat() then
                    self.mainPageSyncPending = false
                end
            end
        end
        if dirtyActionMode then
            self:RefreshAllActionButtons(db, pageState, dirtyActionMode, diagnostic)
        end
        if dirtyGlobalIcon then
            local iconWrites = self:RefreshGlobalVisibleIcons("SPELL_UPDATE_ICON")
            if diagnostic then diagnostic.writes = diagnostic.writes + (iconWrites or 0) end
        end
        self:RefreshDirtySlots(db, pageState, dirtySlots, diagnostic)
        self:RefreshDirtySpecialBars(db, dirtySpecialBars)
    end

    if self.rangeMapDirty == true then
        self:ReconcileRangeSlots()
    end
    if self.actionHotRecordsDirty == true then
        self:RebuildActionHotRecords()
    end
    ClearTable(dirtySlots)
    ClearTable(dirtySpecialBars)
    ClearTable(dirtySettingBars)
    if fullRefresh then
        if YAB.QuestItems then YAB.QuestItems:SyncEnabled() end
        self.fullRefreshCount = (self.fullRefreshCount or 0) + 1
        self.lastFullRefreshReason = passReason
    end
    if identityPassKind and self.actionIdentityGeneration == identityPassGeneration then
        if identityPassKind == "full" or identityPassKind == "all" then
            self:MarkProcIndexComplete(identityPassGeneration)
        elseif identityDeltaEligible
            and self.fullRefreshPending ~= true
            and self.dirtyMainPageIdentity ~= true
            and not RefreshModeUpdatesActionIdentity(self.dirtyActionMode)
            and not DirtySlotsUpdateActionIdentity(self.dirtySlots) then
            self:MarkProcIndexComplete(identityPassGeneration)
        end
    end
end

function BarManager:SetBindPresentation(active, reason)
    active = active == true
    local hasLayerSnapshots = next(self.bindPresentationHolderLayers or {}) ~= nil
    if self.bindPresentationActive == active and self.bindPresentationPending ~= true and (active or not hasLayerSnapshots) then
        return true
    end
    local previousActive = self.bindPresentationActive == true
    self.bindPresentationActive = active
    self.bindPresentationReason = reason or (active and "keybind enter" or "keybind exit")

    if InCombat() then
        self.bindPresentationPending = true
        if YAB.Drivers then
            YAB.Drivers:Queue("keybind presentation", function()
                if not BarManager.runtimeActive then return end
                local layersApplied
                if BarManager.bindPresentationActive == true then
                    BarManager:RefreshDynamicSpecialLayoutsForEditMode("keybind presentation prepare")
                    layersApplied = BarManager:ApplyBindPresentationLayers()
                else
                    layersApplied = BarManager:RestoreBindPresentationLayers()
                end
                local visibilityApplied = BarManager:ApplyVisibility()
                BarManager.bindPresentationPending = not (layersApplied and visibilityApplied)
                BarManager:RefreshDynamicSpecialLayoutsForEditMode("keybind presentation")
                BarManager:QueueSpecialRefresh("pet", "keybind presentation")
                BarManager:QueueSpecialRefresh("stance", "keybind presentation")
                BarManager:QueueSpecialRefresh("possess", "keybind presentation")
                BarManager:QueueFullRefresh("keybind presentation")
            end)
        end
        return false, "combat deferred"
    end

    self.bindPresentationPending = false
    local layersApplied
    if active then
        self:RefreshDynamicSpecialLayoutsForEditMode("keybind presentation prepare")
        layersApplied = self:ApplyBindPresentationLayers()
    else
        layersApplied = self:RestoreBindPresentationLayers()
    end
    if not layersApplied then
        if active and not previousActive then
            self.bindPresentationActive = false
            self.bindPresentationReason = "keybind presentation layer rollback"
            self:RestoreBindPresentationLayers()
            self:ApplyVisibility()
            self:RefreshDynamicSpecialLayoutsForEditMode(self.bindPresentationReason)
            self:QueueSpecialRefresh("pet", self.bindPresentationReason)
            self:QueueSpecialRefresh("stance", self.bindPresentationReason)
            self:QueueSpecialRefresh("possess", self.bindPresentationReason)
            self:QueueFullRefresh(self.bindPresentationReason)
        else
            self.bindPresentationPending = true
        end
        return false, "presentation layer failed"
    end
    local applied = self:ApplyVisibility()
    if not applied and active and not previousActive then
        self.bindPresentationActive = false
        self.bindPresentationReason = "keybind presentation rollback"
        self:RestoreBindPresentationLayers()
        self:ApplyVisibility()
        self:RefreshDynamicSpecialLayoutsForEditMode(self.bindPresentationReason)
        self:QueueSpecialRefresh("pet", self.bindPresentationReason)
        self:QueueSpecialRefresh("stance", self.bindPresentationReason)
        self:QueueSpecialRefresh("possess", self.bindPresentationReason)
        self:QueueFullRefresh(self.bindPresentationReason)
        return false, "presentation failed"
    end
    self:RefreshDynamicSpecialLayoutsForEditMode(self.bindPresentationReason)
    self:QueueSpecialRefresh("pet", self.bindPresentationReason)
    self:QueueSpecialRefresh("stance", self.bindPresentationReason)
    self:QueueSpecialRefresh("possess", self.bindPresentationReason)
    self:QueueFullRefresh(self.bindPresentationReason)
    return applied
end

function BarManager:ApplyVisibility()
    local ok = true
    for _, record in pairs(self.bars) do
        if record.mover and not InCombat() then
            record.mover:Show()
        end
        if record.holder then
            if YAB.Drivers and not self:ApplyRecordVisibility(record) then
                ok = false
            end
            self:ApplyMouseoverVisibility(record)
            if not self:ApplyRecordEmptySlotVisibility(record) then
                ok = false
            end
        end
    end
    self:MarkDirectActionListDirty()
    self:ApplySpecialActionGrouping("visibility applied")
    return ok
end

function BarManager:ResetStats()
    self.fullRefreshCount = 0
    self.lastFullRefreshReason = nil
    self.structuralBatchCount = 0
    self.structuralBarChangeCount = 0
    self.specialGroupActiveMembers = 0
    self.specialGroupLayouts = 0
    self.specialGroupAnchorFallbacks = 0
    self.usablePayloadFallbacks = 0
    self.slotGlobalFallbacks = 0
    self.slotIdentityNarrowHits = 0
    self.slotIdentityFallbacks = 0
    self.slotIdentityShadowComparisons = 0
    self.slotIdentityShadowMismatches = 0
    self.assistedCombatTickerStarts = 0
    self.assistedCombatTickerStops = 0
    self.assistedCombatTickerTicks = 0
    self.assistedCombatNextSpellPolls = 0
    self.assistedCombatNextSpellChanges = 0
    self.assistedCombatNextSpellFailures = 0
    self.assistedCombatForceUpdates = 0
    self.assistedCombatRefreshQueues = 0
    self.assistedCombatVisibleSlotChecks = 0
    self.broadcasterMismatch = 0
    self.rangeMapReconciles = 0
    self.procIndexShadowComparisons = 0
    self.procIndexMismatches = 0
    self.procIndexRebuilds = 0
    self.procIndexFallbacks = 0
    self.procIndexIndexedShows = 0
    self.procIndexLegalEmptyShows = 0
end

function BarManager:ResetSlotIdentityDiagnostics()
    self.slotIdentityNarrowHits = 0
    self.slotIdentityFallbacks = 0
    self.slotIdentityShadowComparisons = 0
    self.slotIdentityShadowMismatches = 0
end

function BarManager:GetSlotIdentityDiagnosticLine()
    return string.format(
        "YActionBar perf slot identity: narrow=%d fallbacks=%d shadow=%d mismatches=%d disabled=%s",
        self.slotIdentityNarrowHits or 0,
        self.slotIdentityFallbacks or 0,
        self.slotIdentityShadowComparisons or 0,
        self.slotIdentityShadowMismatches or 0,
        tostring(self.slotIdentityNarrowDisabled == true)
    )
end

function BarManager:GetStats()
    local activeBars, visibleBars, buttonCount = 0, 0, 0
    local nativeFrames, externalFrames = 0, 0
    for _, record in pairs(self.bars) do
        if record.holder then
            activeBars = activeBars + 1
            if record.holder:IsShown() then visibleBars = visibleBars + 1 end
        end
        buttonCount = buttonCount + #(record.buttons or {})
        buttonCount = buttonCount + #(record.externalButtons or {})
    end
    for _ in pairs(self.nativeState or {}) do nativeFrames = nativeFrames + 1 end
    for _ in pairs(self.externalState or {}) do externalFrames = externalFrames + 1 end
    self:AuditActionBroadcasterEvents("stats")
    return {
        questItems = YAB.QuestItems and YAB.QuestItems:GetStats() or nil,
        activeBars = activeBars,
        visibleBars = visibleBars,
        buttonCount = buttonCount,
        directActionButtonCount = self.directActionButtonCount or 0,
        directActionListRebuilds = self.directActionListRebuilds or 0,
        directActionListFallbacks = self.directActionListFallbacks or 0,
        cooldownPath = "native-core",
        broadcaster = self.broadcasterMode or "unknown",
        broadcasterMode = self.broadcasterMode or "unknown",
        broadcasterOff = self.broadcasterOff or 0,
        broadcasterOn = self.broadcasterOn or 0,
        broadcasterRestores = self.broadcasterRestores or 0,
        broadcasterFallbacks = self.broadcasterFallbacks or 0,
        broadcasterActual = self.broadcasterActual or "unknown",
        broadcasterRegistered = self.broadcasterRegisteredEvents or 0,
        broadcasterButtonRegistered = self.broadcasterButtonRegistered or 0,
        broadcasterActionRegistered = self.broadcasterActionRegistered or 0,
        broadcasterReregisters = self.broadcasterReregisters or 0,
        broadcasterMismatch = self.broadcasterMismatch or 0,
        broadcasterCallbacksSuppressed = false,
        nativeFrames = nativeFrames,
        nativeDisposedButtons = CountTableKeys(self.nativeDisposedButtons),
        nativeDisposalFailures = self.nativeDisposalFailures or 0,
        specialNativeSuppressionMode = self.specialNativeSuppressionMode or "unknown",
        specialNativeSuppressionChanged = self.specialNativeSuppressionChanged == true,
        specialNativeSuppressionFailures = self.specialNativeSuppressionFailures or 0,
        externalFrames = externalFrames,
        refreshQueue = self.refreshPending and 1 or 0,
        mouseoverFades = self.mouseoverFadeActiveCount or 0,
        pendingStructuralBars = CountTableKeys(self.pendingStructuralBars),
        pendingExternalSpecialBars = CountTableKeys(self.pendingExternalSpecialBars),
        specialGroupingMode = self:GetSpecialGroupingMode(),
        specialGroupActiveMembers = self.specialGroupActiveMembers or 0,
        specialGroupLayouts = self.specialGroupLayouts or 0,
        specialGroupAnchorFallbacks = self.specialGroupAnchorFallbacks or 0,
        configSnapshots = self.configSnapshotCount or 0,
        configSnapshotVersion = self.configSnapshotVersion or 0,
        fullRefreshCount = self.fullRefreshCount or 0,
        lastFullRefreshReason = self.lastFullRefreshReason,
        structuralBatchCount = self.structuralBatchCount or 0,
        structuralBarChangeCount = self.structuralBarChangeCount or 0,
        usablePayloadFallbacks = self.usablePayloadFallbacks or 0,
        usableInvalidPayloads = self.usableInvalidPayloads or 0,
        slotGlobalFallbacks = self.slotGlobalFallbacks or 0,
        slotIdentityNarrowHits = self.slotIdentityNarrowHits or 0,
        slotIdentityFallbacks = self.slotIdentityFallbacks or 0,
        slotIdentityShadowComparisons = self.slotIdentityShadowComparisons or 0,
        slotIdentityShadowMismatches = self.slotIdentityShadowMismatches or 0,
        slotIdentityNarrowDisabled = self.slotIdentityNarrowDisabled == true,
        assistedCombatTickerActive = self.assistedCombatTicker ~= nil,
        assistedCombatTickerInterval = self.assistedCombatTickerInterval,
        assistedCombatTickerStarts = self.assistedCombatTickerStarts or 0,
        assistedCombatTickerStops = self.assistedCombatTickerStops or 0,
        assistedCombatTickerTicks = self.assistedCombatTickerTicks or 0,
        assistedCombatNextSpellPolls = self.assistedCombatNextSpellPolls or 0,
        assistedCombatNextSpellChanges = self.assistedCombatNextSpellChanges or 0,
        assistedCombatNextSpellFailures = self.assistedCombatNextSpellFailures or 0,
        assistedCombatForceUpdates = self.assistedCombatForceUpdates or 0,
        assistedCombatRefreshQueues = self.assistedCombatRefreshQueues or 0,
        assistedCombatVisibleSlotChecks = self.assistedCombatVisibleSlotChecks or 0,
        rangeMapReconciles = self.rangeMapReconciles or 0,
        procIndexMode = self.procIndexMode or "shadow",
        actionIdentityGeneration = self.actionIdentityGeneration or 0,
        procIndexCompleteGeneration = self.procIndexCompleteGeneration or 0,
        procIndexShadowComparisons = self.procIndexShadowComparisons or 0,
        procIndexMismatches = self.procIndexMismatches or 0,
        procIndexRebuilds = self.procIndexRebuilds or 0,
        procIndexFallbacks = self.procIndexFallbacks or 0,
        procIndexIndexedShows = self.procIndexIndexedShows or 0,
        procIndexLegalEmptyShows = self.procIndexLegalEmptyShows or 0,
        events = self.eventCount or 0,
        hotEventBackend = self.hotEventBackend or "native-frame",
        nativeSuppressionMode = self.nativeSuppressionMode or "none",
        nativeSuppressionDegraded = self.nativeSuppressionDegraded == true,
        reloadRequired = self.reloadRequired == true,
        reloadRequiredReason = self.reloadRequiredReason,
        runtime = self.runtimeActive == true,
        lastRefreshReason = self.lastRefreshReason,
        bindPresentationActive = self.bindPresentationActive == true,
        bindPresentationPending = self.bindPresentationPending == true,
    }
end

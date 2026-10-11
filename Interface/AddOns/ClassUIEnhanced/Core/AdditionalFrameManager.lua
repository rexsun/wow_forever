
--[[
    AdditionalFrameManager: creates and manages user-defined additional frames
    that route specific spells from Blizzard CooldownViewer trackers into
    independent, positionable frames with their own layout settings.

    Three frame types:
    - "spells": grid layout, sources from CooldownEssential/CooldownUtility viewers + addon icons
    - "buffs": grid layout, sources from BuffIcon viewer
    - "bar": vertical stack, sources from BuffBar viewer

    Dual routing model: a spell can be routed to BOTH a spells AF (ability domain)
    AND one of buffs/bar AF (buff domain) simultaneously. Within each domain,
    exclusivity holds (one AF per spell).

    Each additional frame registers as a full component (anchoring, EditMode, profiles).
    Primary components pass an excludeFilter to their layout code that skips children
    whose spellID is routed here. Layout updates are triggered via the
    OnCDMSpellsChanged callback, dispatched to all active frames whenever CDM data changes.
--]]

local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field AdditionalFrameManager additionalframemanager

---@class additionalframemanager : table

---@type additionalframemanager
local manager = {}

-- Source keys for addon-owned icon sources (not CooldownViewer children).
-- These use cross-parent SetPoint + SetIgnoreParentAlpha to render icons
-- from TrinketTracker / ConsumableTracker inside additional frame containers.
local ADDON_ICON_SOURCES = {
    Trinket = true,
    Consumable = true,
    Racial = true,
}

---@class additional_frame_instance : table
---@field id string
---@field component component
---@field container frame
---@field addonIcons table<frame, boolean>  addon-owned icons (trinket/consumable) positioned in this container
---@field afForeignSeen table<frame, number>|nil  every foreign icon this frame's icon_visibility_mode filter has written state onto, stamped with the collect pass that last saw it (see releaseAFForeignIconState)
---@field afForeignPass number|nil  monotonic collect-pass token for afForeignSeen
---@field fontsOwed boolean|nil  a font edit arrived while hidden; applyFilteredLayout applies it on the next shown layout

---Active additional frame instances, keyed by frame id.
---@type table<string, additional_frame_instance>
local activeFrames = {}

---Ability routing domain: nested by source category.
---abilityRouting[category][spellID] = frameId.
---CDM sources (Essential/Utility/nil) share "CDM"; addon sources get their own key.
---@type table<string, table<number, string>>
local abilityRouting = {}

---Empty table returned for uninitialized routing categories (never mutated).
---@type table
local EMPTY_ROUTING = {}

---Buff routing domain: spellID → frame id for "buffs"/"bar"-type AFs.
---@type table<number, string>
local buffRouting = {}

---Counter for generating unique frame IDs.
---@type number
local nextFrameId = 1

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

---Normalize an assigned_spells entry to (spellID, source).
---Supports both legacy plain numbers and new {spellID, source} tables.
---@param entry number|table
---@return number spellID
---@return string|nil source  viewer source key ("Essential", "Utility", "BuffIcon", "BuffBar")
local function normalizeEntry(entry)
    if type(entry) == "number" then
        return entry, nil
    end
    return entry[1], entry[2]
end

---Map a source key to its routing category within the ability domain.
---CDM viewer sources share "CDM"; addon icon sources get their own key.
---@param source string|nil
---@return string
local function getRoutingCategory(source)
    if ADDON_ICON_SOURCES[source] then return source end
    return "CDM"
end

---Map a source key to the correct routing sub-table.
---@param source string|nil
---@return table  spellID → frameId
local function getRoutingSubTable(source)
    if source == "BuffIcon" or source == "BuffBar" then
        return buffRouting
    end
    local category = getRoutingCategory(source)
    return abilityRouting[category] or EMPTY_ROUTING
end


---Get the current override spell for a base spellID.
---Returns the override ID if one exists and differs from the base, else nil.
---Used to also route override spells (e.g. Divine Toll → Hammer of Light)
---alongside the user-assigned base spell.
---@param spellID number
---@return number|nil
local function getOverrideSpell(spellID)
    local override = private.compat.GetOverrideSpell(spellID)
    if override and override ~= spellID then
        return override
    end
    return nil
end

---The CDM entry key a LINKED id belongs to, or nil.  A linked id (a cooldown
---entry's aura, a talent variant's member) saved in `assigned_spells` is drawn
---by the frame AS its entry — buildAFAuraSpellMap and buildAFIconSpellMap
---collapse it to the owner — so the owner is what must leave its tracker.  The
---routing check walks base ↔ override only (Util.ResolveByBaseOrOverride), never
---from a tracker's key out to its linked ids, so without this the tracker drew
---the entry as well.  A base or override id is its own entry: nil.  So is an id
---that is one entry's own spell and another's linked id (Mass Entanglement
---`102359`, linked by Entangling Roots `339`): GetIdentityOwner keeps only the
---last writer, which would draw Entangling Roots in its place.  A peek: nil
---while the model is unresolved, never a forced build (patterns.md "Lazy caches
---vs init order").
---A rank of a WHOLE spell-rank family (WoW Forever: one CDM entry per rank)
---answers with the family's representative too: the frame holds the spell, and
---its tracker draws the family under that key (CDMDataSource.applyRankFamilies).
---@param spellID number
---@param bucket "cooldown"|"aura"  the frame's side
---@return number|nil
local function linkedOwner(spellID, bucket)
    local cdm = private.CDMDataSource
    if not cdm.IsResolved() then return nil end
    local rep = cdm.GetFamilyRep(spellID, bucket)
    if rep then return rep ~= spellID and rep or nil end
    if cdm.IsEntryKey(spellID) then return nil end
    local owner = cdm.GetIdentityOwner(spellID)
    if not owner or cdm.GetOverrideSpellID(owner) == spellID then return nil end
    return owner
end

---The CDM model build (GetModelStamp) rebuildSpellRouting last ran against —
---the one whose linked ids' owners are routed — or nil when it ran before any
---model existed.  The first rebuilds run at component enable, before the
---model; and on OnCDMSpellsChanged the trackers rebuild the model and query
---routing before this file's own handler runs.  ensureRoutingResolved catches
---up in both cases.
local routingStamp = nil

---Rebuild the dual routing tables from all active frames.
---"spells"-type AFs populate abilityRouting (per-category); "buffs"/"bar"-type populate buffRouting.
local function rebuildSpellRouting()
    for _, sub in pairs(abilityRouting) do wipe(sub) end
    wipe(buffRouting)
    routingStamp = private.CDMDataSource.GetModelStamp()
    for id in pairs(activeFrames) do
        local settings = private.profile.additional_frames[id]
        if settings and (settings.enabled or private.isEditMode) then
            if settings.frame_type == "spells" then
                for _, entry in ipairs(settings.assigned_spells) do
                    local spellID, source = normalizeEntry(entry)
                    local category = getRoutingCategory(source)
                    if not abilityRouting[category] then
                        abilityRouting[category] = {}
                    end
                    abilityRouting[category][spellID] = id
                    local override = getOverrideSpell(spellID)
                    if override then
                        abilityRouting[category][override] = id
                    end
                    local owner = not ADDON_ICON_SOURCES[source] and linkedOwner(spellID, "cooldown")
                    if owner then
                        abilityRouting[category][owner] = id
                    end
                end
            elseif settings.frame_type == "buffs" or settings.frame_type == "bar" then
                for _, entry in ipairs(settings.assigned_spells) do
                    local spellID, source = normalizeEntry(entry)
                    buffRouting[spellID] = id
                    local override = getOverrideSpell(spellID)
                    if override then
                        buffRouting[override] = id
                    end
                    local owner = not ADDON_ICON_SOURCES[source] and linkedOwner(spellID, "aura")
                    if owner then
                        buffRouting[owner] = id
                    end
                end
            end
        end
    end
end

---Rebuild the routing if the CDM model it was built against is not the current
---one (so the routed owners may be missing or stale).  Called by the routing
---queries: the trackers ask them after building the model themselves.
local function ensureRoutingResolved()
    local stamp = private.CDMDataSource.GetModelStamp()
    if stamp and stamp ~= routingStamp then
        rebuildSpellRouting()
    end
end

-- ---------------------------------------------------------------------------
-- Filtered layout: icon type
-- ---------------------------------------------------------------------------

---Returns true when an addon-owned icon (Trinket/Consumable/Racial) is
---currently usable, read from the icon's own cooldown state (set by the
---source component's update cycle):
---icon.wasOnCooldown is true while a real CD is active.  Charge-based addon
---icons additionally expose chargeInfo via the source spell; we re-query the
---spell directly so a spell with remaining charges counts as ready even while
---wasOnCooldown is true.
---
---treatChargingAsOnCD (default true) controls charge-spell semantics:
---  - true  (default): an in-flight recharge forces "not ready" even with a
---                     castable charge available — a 1/2 spell mid-recharge
---                     is treated as on cooldown.
---  - false: only zero charges count as on cooldown; 1/2 stays "ready"
---           (this is the historical AF behavior).
---@param icon frame
---@param treatChargingAsOnCD? boolean  defaults to true when nil
---@return boolean
local function isAddonIconReady(icon, treatChargingAsOnCD)
    if treatChargingAsOnCD == nil then treatChargingAsOnCD = true end
    local spellID = icon.spellID
    if spellID then
        local chargeInfo = C_Spell.GetSpellCharges(spellID)
        if chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1 then
            if treatChargingAsOnCD then
                -- Lax: any recharge in flight forces "not ready", even with a
                -- castable charge remaining.  Keys off chargeInfo.isActive;
                -- charge-count fields are render/pass-through only, not used
                -- in control-flow comparisons.
                return not chargeInfo.isActive
            end
            -- Strict: ready as long as cdInfo.isActive isn't asserting a
            -- full depletion.  cdInfo.isActive in Midnight is true only
            -- at 0/N for charge spells, so this matches "ready while any
            -- charge remains".
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            return not (cdInfo and cdInfo.isActive and not cdInfo.isOnGCD)
        end
    end
    return not icon.wasOnCooldown
end

local applyFilteredLayout

---Per-instance icon_visibility_mode filter.  Returns true when the candidate
---icon should be excluded from this frame's layout pass.  Every candidate is
---an addon-owned icon (Trinket/Consumable/Racial), so readiness comes from
---isAddonIconReady.
---Fade-mode icons stay in the layout until the fade-out animation completes;
---rapid toggle is handled by cancelling the in-flight fade.  Cached on the
---instance so the per-child branch debug throttle survives across passes.
---@param instance additional_frame_instance
---@return function excludeFilter
local function ensureExcludeFilter(instance)
    if not instance._excludeFilter then
        instance._excludeFilter = private.Util.MakeIconVisibilityFilter({
            getSettingsFn = function() return private.profile.additional_frames[instance.id] end,
            componentName = instance.component and instance.component.name,
            isReadyAddonFn = isAddonIconReady,
        })
    end
    return instance._excludeFilter
end

---Register/unregister the extra events that drive icon_visibility_mode
---re-evaluation, on the shared AFM swipe watcher.  Refcounted through
---manager._cueIvmCount so the last spells-AF leaving an active hide/fade mode
---unregisters them again.
---
---That watcher already carries SPELL_UPDATE_COOLDOWN, which covers spell
---cooldowns.  Trinkets, consumables and racials are item/action cooldowns whose
---readiness (isAddonIconReady, reading icon.wasOnCooldown as the source
---component maintains it) can transition without one, and a usability-only
---transition fires neither -- hence these two.
---
---This has to live on the AFM watcher rather than the factory's
---icontracker_config.extraWatcherEvents: the factory's per-event pass walks
---only its own pooled buttons, whereas foreign (routed) icons are re-collected
---and re-filtered by hooks.getAppendFrames, which runs only inside a full
---tracker.Refresh().  The AFM watcher's handler calls applyFilteredLayout,
---which is that full path.
---@param instance additional_frame_instance
---@param visibilityActive boolean
local function updateIvmWatcherEvents(instance, visibilityActive)
    local swipeW = manager._swipeWatcher
    if not swipeW then return end
    local wasActive = instance._cueIvmActive
    if visibilityActive and not wasActive then
        instance._cueIvmActive = true
        manager._cueIvmCount = (manager._cueIvmCount or 0) + 1
        if manager._cueIvmCount == 1 then
            swipeW:RegisterEvent("SPELL_UPDATE_USABLE")
            swipeW:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
        end
    elseif not visibilityActive and wasActive then
        instance._cueIvmActive = nil
        manager._cueIvmCount = (manager._cueIvmCount or 1) - 1
        if manager._cueIvmCount <= 0 then
            manager._cueIvmCount = 0
            swipeW:UnregisterEvent("SPELL_UPDATE_USABLE")
            swipeW:UnregisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
        end
    end
end

-- ---------------------------------------------------------------------------
-- Filtered layout: bar type
-- ---------------------------------------------------------------------------

---Build the {[spellID]=true} aura map for a bar-type Additional Frame: its own
---assigned spells, each widened to its full CDM aura identity set (the displayed
---aura is often a linked id, not the base spellID), plus the frame's custom
---spells.  ONE map — the tracker feeds it to both unit containers and the filter
---strings decide where each aura can land.
---@param instance additional_frame_instance
---@return table<number, true>
local function buildAFAuraSpellMap(instance)
    local settings = private.profile.additional_frames[instance.id]
    local map = {}
    if settings and settings.assigned_spells then
        for _, entry in ipairs(settings.assigned_spells) do
            local spellID = normalizeEntry(entry)
            if spellID then
                -- One key per CDM ENTRY, its base spell -- the same contract the
                -- CDM-backed maps follow, and the widening happens at the
                -- candidate filter (SyncSpellGroups/SyncSlots' idSetFor, and now
                -- SyncGroup's own).  This used to add every identity member as a
                -- sibling key, which was harmless only while the plain single
                -- group was the engine: under the per-spell groups that are now
                -- unconditional it built one group PER member, each matching the
                -- same live aura, so the entry drew twice and shifted every
                -- layoutIndex after it.
                --
                -- GetIdentityOwner, not the raw id: the AF picker saves
                -- `overrideSpellID or spellID` (Options.lua's assigned_spells
                -- writers), and an override has no identity set of its own --
                -- resolvedIdentity is keyed by base -- so an override-keyed entry
                -- would otherwise get a bare single-id filter and widen to
                -- nothing.
                local base = private.CDMDataSource.GetIdentityOwner(spellID) or spellID
                map[base] = true
            end
        end
    end
    local componentName = instance.component and instance.component.name
    if componentName and private.CustomSpells then
        local customMap = private.CustomSpells.GetSpellMapFor(componentName)
        if customMap then
            for spellID in pairs(customMap) do
                -- Skip a custom id that is another member of an assigned
                -- entry's identity set: that entry's group already matches
                -- the aura, and a second key draws it twice (the same rule
                -- CDMDataSource.BuildComponentSpellMaps applies).
                local owner = private.CDMDataSource.GetIdentityOwner(spellID)
                if not (owner and map[owner]) then map[spellID] = true end
            end
        end
    end
    return map
end

---Which factory an aura-rendering frame type uses.
---"spells" is deliberately absent: those frames route COOLDOWN icons, which are
---not aura-driven, and render through the IconTracker factory instead.
local AURA_TRACKER_BY_TYPE = {
    bar   = { factory = "AuraBarTracker" },
    buffs = { factory = "AuraIconTracker" },
}

---Whether a frame type routes through an aura-rendering tracker (bar or
---buff icons) rather than the spells/viewer-child path.
---@param frameType string
---@return boolean
manager.IsAuraType = function(frameType)
    return AURA_TRACKER_BY_TYPE[frameType] ~= nil
end

---Lazily build this frame's own aura tracker (bar or icon).
---
---Aura Additional Frames render through the SAME engines as the primary
---BuffTrackerBars / BuffTracker, each with its own player + target
---AuraContainers.  They used to cross-parent live CDM viewer children, which
---cannot work on 12.1: nothing re-runs the layout when a child's shown state
---flips, and the compaction driving it is secret.
---
---The tracker is HOSTED — it fills `instance.container`, which the AF already
---owns and the anchor system already positions, so the factory never creates a
---competing top-level frame.  It shares the AF's component name, so its
---Anchor visibility/alpha queries resolve to this frame's own settings.
---@param instance additional_frame_instance
---@param settings additional_frame_profile
---@return table|nil
local function getAuraTracker(instance, settings)
    if instance.auraTracker then return instance.auraTracker end
    if not instance.container or not instance.component then return nil end
    local spec = AURA_TRACKER_BY_TYPE[settings.frame_type]
    if not spec then return nil end
    local id = instance.id
    instance.auraTracker = private[spec.factory].CreateTracker({
        name = instance.component.name,
        prefix = "CUE_AF_" .. id,
        parent = instance.container,
        getSettings = function()
            return private.profile.additional_frames[id]
        end,
        buildSpellMap = function()
            local inst = activeFrames[id]
            return inst and buildAFAuraSpellMap(inst) or {}
        end,
    })
    instance.auraTracker.Initialize()
    return instance.auraTracker
end

-- ---------------------------------------------------------------------------
-- Icon (spells) tracker
-- ---------------------------------------------------------------------------

---Build the {[spellID]=true} cooldown map for a spells-type Additional Frame:
---its own assigned CDM spells plus its custom spells.
---
---Addon-source entries (Trinket / Consumable / Racial) are deliberately
---skipped.  Their `assigned_spells` id is an equip slot / consumable category /
---racial spell owned by ANOTHER component, and they reach the grid as foreign
---frames through hooks.getAppendFrames instead.  That skip is also what keeps
---the two halves disjoint: every entry is dispatched by ADDON_ICON_SOURCES to
---exactly one collector, so no entry can be drawn as both a pooled button and
---a foreign frame.
---
---No aura identity-set widening (buildAFAuraSpellMap's GetAuraIdentitySet hop):
---these are cooldowns, keyed by the base spellID the CDM and the pickers use.
---Custom spells go through CustomSpells.GetSpellMapFor and never a raw
---settings.custom_spells walk — the API applies shouldFilterEntry, which drops
---entries the player's own talents have replaced.
---
---`assigned_spells` is intersected with the CDM entries the current character
---actually has (IsCooldownSpellTracked).  It is PROFILE data, so it outlives a
---character and a spec change and accumulates other classes' spells; the
---pre-migration path collected live viewer children, and Blizzard only creates
---a child for an entry that passes its own display gate, so the filter came for
---free and was lost when collection became a build-from-profile.
---
---It FAILS OPEN — an unresolved model draws everything.  Components enable on
---PLAYER_LOGIN while CDMDataSource.Initialize() waits for
---LOADING_SCREEN_DISABLED, and intersecting against an unbuilt model would
---empty the frame.  Self-correcting: this map is rebuilt on every tracker
---Refresh, and OnCDMSpellsChanged fires after every invalidation.
---
---Custom spells are NOT filtered — they are explicit user entries, not CDM
---data, and buildComponentSpellMaps merges its customMap with no isKnown test
---either, so filtering here would diverge from the primary trackers.
---@param instance additional_frame_instance
---@return table<number, true>
local function buildAFIconSpellMap(instance)
    local settings = private.profile.additional_frames[instance.id]
    local map = {}
    if settings and settings.assigned_spells then
        for _, entry in ipairs(settings.assigned_spells) do
            local spellID, source = normalizeEntry(entry)
            if spellID and not ADDON_ICON_SOURCES[source] then
                -- A linked id is drawn as its entry: raw it would be an icon
                -- with no cooldown of its own (an aura, a variant member), and
                -- its entry's tracker no longer draws the entry, since
                -- rebuildSpellRouting routes the owner here.  A rank of a whole
                -- family likewise, as the family (tracked while any rank is).
                local key = linkedOwner(spellID, "cooldown") or spellID
                local tracked = private.CDMDataSource.IsCooldownSpellTracked(key)
                if tracked == nil or tracked == true then
                    map[key] = true
                end
            end
        end
    end
    local componentName = instance.component and instance.component.name
    if componentName and private.CustomSpells then
        -- Known, deliberately unfixed: a custom spell whose id is ALSO an
        -- addon-source entry (a racial added by hand, say) draws twice -- once
        -- as the foreign icon collectAFAppendIcons adopts, once as a pooled
        -- button from this map.  The ADDON_ICON_SOURCES skip above only
        -- partitions `assigned_spells`; custom spells are a separate list and
        -- carry no source tag.  The pre-migration path had the same overlap.
        local customMap = private.CustomSpells.GetSpellMapFor(componentName)
        if customMap then
            for spellID in pairs(customMap) do map[spellID] = true end
        end
    end
    return map
end

---Reused rank map for the spells-AF order-rank hook.  This runs on every layout
---pass of every migrated spells frame, so it must not allocate
---(.context/performance.md).  One shared table is safe across instances:
---table.sort is synchronous, the factory copies these ranks into its own
---scratch before adding synthetic append keys, and no caller holds the table.
---@type table<number, number>
local afRankScratch = {}

---Sort ranks for one spells-AF, in `assigned_spells` index space.
---
---Flattened port of the pre-migration icon-render path's spellOrderByViewer:
---one map, no viewer dimension, because the tracker holds a single merged spell map.  The override
---registration is kept — a spec-overridden spell reaches the tracker's map
---under whichever id the CDM handed over and must inherit its base entry's
---position either way.  Addon-source entries contribute no key here; they are
---ranked through their append index in this same space (see
---collectAFAppendIcons).
---@param id string  additional frame id
---@return table<number, number>|nil
local function buildAFOrderRank(id)
    wipe(afRankScratch)
    local s = private.profile.additional_frames[id]
    if not s then return nil end
    local n = 0
    local assigned = s.assigned_spells
    if assigned then
        for i = 1, #assigned do
            n = i
            local spellID, source = normalizeEntry(assigned[i])
            if spellID and not ADDON_ICON_SOURCES[source] then
                afRankScratch[spellID] = i
                local override = getOverrideSpell(spellID)
                if override then afRankScratch[override] = i end
                -- buildAFIconSpellMap keys a linked id by its owner.
                local owner = linkedOwner(spellID, "cooldown")
                if owner and afRankScratch[owner] == nil then afRankScratch[owner] = i end
            end
        end
    end
    -- Custom spells sort after every routed one, keeping their custom_spells
    -- order via the (#assigned_spells + i) offset.  A spell that is BOTH
    -- assigned and custom keeps its assigned_spells position: the nil guard is
    -- what stops this later write from dragging it to the tail.
    local custom = s.custom_spells
    if custom then
        for i = 1, #custom do
            local cs = custom[i]
            if cs and cs.spellID and afRankScratch[cs.spellID] == nil then
                afRankScratch[cs.spellID] = n + i
            end
        end
    end
    return afRankScratch
end

---Undo everything THIS frame's icon_visibility_mode filter wrote onto a
---borrowed icon.
---
---**Ownership rule: whoever sets an alpha override, starts a fade, or zeroes the
---inner textures of a frame it does not own is responsible for clearing that
---state when the frame goes back.**  The source component repairs a returned
---icon with a flat `SetAlpha(1)` (CooldownTracker's clearRoutedAddonIcons), but
---every writer of a routed icon's alpha multiplies the override back in
---(patterns.md, "every writer of viewer-child alpha multiplies
---iconAlphaOverrides") — so a stale override SURVIVES that repair and leaves the
---icon permanently dim (fade modes 3/5) or fully invisible (hide modes 2/4) in
---its source tracker until /reload.
---
---The filter writes the frame's OWN alpha as well as the side-table override —
---`child:SetAlpha(0)` in the hide branch, `StartIconFade` to fadedRatio in the
---fade branch (Util.MakeIconVisibilityFilter) — and `CancelIconFade` only stops
---the animation, it writes no alpha.  So the restore has to include it, in the
---same shape CooldownTracker.clearRoutedAddonIcons uses.  Only a trinket or a
---combat potion is re-alphaed by its new owner (CooldownTracker re-adopts it and
---placeIconButton re-alphas); RacialTracker, TrinketTracker with route_trinkets
---off and ConsumableTracker categories 2-5 only ever SetAlpha their CONTAINER,
---never the icon, so without this the frame stays at 0 or 0.3 until /reload.
---@param icon frame
local function clearAFForeignIconState(icon)
    private.Util.CancelIconFade(icon)
    icon:SetAlpha(1)
    private.Util.SetIconAlphaOverride(icon, nil)
    private.Util.RestoreInnerTextures(icon)
end

---Release the filter state of every foreign icon this frame has touched that
---the current collect pass did NOT see again.
---
---Why a pass token rather than a flat sweep: collectAFAppendIcons
---release-then-re-adopts on every layout pass, and an icon that is merely being
---re-adopted must keep its in-flight fade — cancelling it each pass would
---restart the animation from wherever it had reached.  Only an icon that has
---genuinely left (its assigned_spells entry was removed, or the frame stopped
---rendering) is stale, and that is exactly "not stamped with this pass".
---
---A hide-mode icon is filtered OUT of the append list and so never reaches
---instance.addonIcons — which is why this cannot key off that table.
---@param instance additional_frame_instance
---@param keepToken number|nil  pass token to keep; nil releases everything
local function releaseAFForeignIconState(instance, keepToken)
    local seen = instance.afForeignSeen
    if not seen then return end
    for icon, token in pairs(seen) do
        if token ~= keepToken then
            clearAFForeignIconState(icon)
            seen[icon] = nil
        end
    end
end

---Hand every foreign icon this frame currently holds back to its source
---component.  Source components never set strata explicitly (they inherit it
---from their parent), so without the restore a de-routed icon stays stuck at
---this frame's strata.  Ported from the pre-migration icon-render path's
---addon-icon reset.
---@param instance additional_frame_instance
local function releaseAFAppendIcons(instance)
    for icon in pairs(instance.addonIcons) do
        icon:SetIgnoreParentAlpha(false)
        local p = icon:GetParent()
        if p then icon:SetFrameStrata(p:GetFrameStrata()) end
    end
    wipe(instance.addonIcons)
    local list = instance.afAppendList
    if list then
        for i = #list, 1, -1 do list[i] = nil end
    end
end

---Restyle one adopted foreign icon from THIS frame's font settings.  The icon
---belongs to another component, which styles it from its own settings, so an
---adopted icon has to be restyled the way CooldownTracker restyles its routed
---trinkets/potions (applyAddonIconProperties).
---@param icon frame
---@param settings additional_frame_profile
local function applyAFAppendIconProperties(icon, settings)
    if settings.timer_font then
        if icon.DurationText then
            private.Util.ApplyFontProfile(icon.DurationText, settings.timer_font, icon)
        end
        if icon.BuffDurationText then
            private.Util.ApplyFontProfile(icon.BuffDurationText, settings.timer_font, icon)
        end
    end
    if icon.KeybindText then
        local keybindFont = settings.keybind_font
        if keybindFont and keybindFont.enabled then
            local keybindText
            if icon.slotID then
                local itemID = GetInventoryItemID("player", icon.slotID)
                if itemID then keybindText = private.Util.GetKeybindTextForItem(itemID) end
            elseif icon.itemId then
                keybindText = private.Util.GetKeybindTextForItem(icon.itemId)
            end
            if keybindText then
                icon.KeybindText:SetText(keybindText)
                private.Util.ApplyFontProfile(icon.KeybindText, keybindFont, icon)
                icon.KeybindText:Show()
            else
                icon.KeybindText:Hide()
            end
        else
            icon.KeybindText:Hide()
        end
    end
    if settings.stacks_font and icon.Count and icon.Count:IsShown() then
        private.Util.ApplyFontProfile(icon.Count, settings.stacks_font, icon)
    end
end

---Collect the Trinket / Consumable / Racial icons this frame has adopted, in
---`assigned_spells` order, recording each one's sort rank alongside.  Handed to
---the factory as hooks.getAppendFrames; `active == false` means "give them
---back".
---
---Release-then-re-adopt on every pass, like CooldownTracker's collector: with a
---handful of icons that is cheaper than diffing, and it is what returns a
---de-routed icon (an entry the user just removed) to its source component,
---which only lays out icons that IsSpellRouted no longer claims.
---@param instance additional_frame_instance
---@param active boolean
---@return table[]|nil
local function collectAFAppendIcons(instance, active)
    releaseAFAppendIcons(instance)
    -- Pass token for the filter-state sweep below: every candidate icon this
    -- pass evaluates gets stamped, and anything still carrying an older stamp
    -- has genuinely left this frame and gets its borrowed-icon state cleared.
    local token = (instance.afForeignPass or 0) + 1
    instance.afForeignPass = token
    if not active then
        releaseAFForeignIconState(instance, nil)
        return nil
    end
    local settings = private.profile.additional_frames[instance.id]
    if not settings or not settings.assigned_spells then
        releaseAFForeignIconState(instance, nil)
        return nil
    end
    local seen = instance.afForeignSeen
    if not seen then seen = {}; instance.afForeignSeen = seen end
    local componentName = instance.component and instance.component.name
    local shouldExclude = ensureExcludeFilter(instance)
    -- Adopted icons stay parented to their source component, so this frame's
    -- strata has to be written onto them directly (releaseAFAppendIcons undoes
    -- it).  Same reasoning as applyIconLayout's effectiveStrata pass.
    local strata = componentName and private.Anchor.GetEffectiveStrata(componentName) or "MEDIUM"

    local list = instance.afAppendList
    if not list then list = {}; instance.afAppendList = list end
    local ranks = instance.afAppendRanks
    if not ranks then ranks = {}; instance.afAppendRanks = ranks end
    local cand = instance.afAppendScratch
    if not cand then cand = {}; instance.afAppendScratch = cand end

    local n = 0
    for i, entry in ipairs(settings.assigned_spells) do
        local entryID, source = normalizeEntry(entry)
        if ADDON_ICON_SOURCES[source] then
            for k = #cand, 1, -1 do cand[k] = nil end
            if source == "Trinket" then
                local tt = private.TrinketTracker
                local icon = tt and tt.GetIconFrame(entryID)
                if icon then cand[1] = icon end
            elseif source == "Consumable" then
                local ct = private.ConsumableTracker
                if ct then
                    local icons = ct.GetIconsByCategory(entryID)
                    for k = 1, #icons do cand[k] = icons[k] end
                end
            elseif source == "Racial" then
                local rt = private.RacialTracker
                local icon = rt and rt.GetIconFrame(entryID)
                if icon then cand[1] = icon end
            end
            for k = 1, #cand do
                local icon = cand[k]
                -- Stamp BEFORE the filter runs: shouldExclude is what writes the
                -- alpha override / zeroes the inner textures, and it writes them
                -- on the excluded (hide-mode) icons too.
                seen[icon] = token
                if (icon:IsShown() or private.isEditMode) and not shouldExclude(icon) then
                    icon:SetIgnoreParentAlpha(true)
                    icon:SetFrameStrata(strata)
                    applyAFAppendIconProperties(icon, settings)
                    instance.addonIcons[icon] = true
                    n = n + 1
                    list[n] = icon
                    -- Sub-order within one entry (a consumable category can
                    -- yield several icons): a fractional offset keeps them in
                    -- collection order without reaching the next entry's
                    -- integer rank.  Equal ranks would fall through to the
                    -- factory comparator's id tie-break, which reverses append
                    -- order for the synthetic (negative) ids it keys them by.
                    ranks[n] = i + (k - 1) * 0.001
                end
            end
        end
    end
    for k = #ranks, n + 1, -1 do ranks[k] = nil end
    releaseAFForeignIconState(instance, token)
    return n > 0 and list or nil
end

---Lazily build this frame's own cooldown-icon tracker.
---
---"spells" Additional Frames render through the SAME engine as CooldownTracker
---and UtilitiesTracker — the IconTracker factory's own pooled icon frames.  They
---used to cross-parent live CDM viewer children, which cannot work on 12.1:
---nothing re-runs the layout when a child's shown state flips.
---
---There is deliberately no AURA_TRACKER_BY_TYPE entry for "spells": that table
---lists the aura factories, so the IconTracker factory is called directly here
---instead.
---
---The tracker is HOSTED — the factory builds its own wrapper inside
---`instance.container` and SetAllPoints it, never touching the outer frame, so
---the AF keeps sole ownership of positioning.  It shares the AF's component
---name, so its Anchor visibility/alpha/strata queries resolve to this frame's
---own settings.
---@param instance additional_frame_instance
---@param settings additional_frame_profile
---@return table|nil
local function getIconTracker(instance, settings)
    if instance.iconTracker then return instance.iconTracker end
    if not instance.container or not instance.component then return nil end
    if settings.frame_type ~= "spells" then return nil end
    local id = instance.id
    -- CreateTracker returns (component, ctx); only the component is needed here.
    instance.iconTracker = private.IconTracker.CreateTracker({
        name = instance.component.name,
        containerName = "CUE_AF_" .. id,
        parent = instance.container,
        getSettings = function()
            return private.profile.additional_frames[id]
        end,
        buildSpellMap = function()
            local inst = activeFrames[id]
            return inst and buildAFIconSpellMap(inst) or {}
        end,
        -- Without this the factory falls back to Util.BuildSpellOrderRank,
        -- which returns nil for any non-CDM component — an AF would sort by
        -- ascending spellID instead of assigned_spells order.
        getOrderRank = function()
            return buildAFOrderRank(id)
        end,
        -- Foreign icons hold their assigned_spells position instead of being
        -- appended last; the factory keys them by a synthetic negative id and
        -- ranks them through the same comparator.
        getAppendRank = function(_, index)
            local inst = activeFrames[id]
            local ranks = inst and inst.afAppendRanks
            return ranks and ranks[index]
        end,
        hooks = {
            getAppendFrames = function(active)
                local inst = activeFrames[id]
                if not inst then return nil end
                return collectAFAppendIcons(inst, active)
            end,
        },
    })
    instance.iconTracker.Initialize()
    return instance.iconTracker
end

---Apply filtered layout for a spells-type additional frame.
---@param instance additional_frame_instance
---@param settings additional_frame_profile
local function applySpellsLayout(instance, settings)
    -- Foreign (routed trinket/consumable/racial) icons are re-filtered only by a
    -- full tracker.Refresh(), which the shared AFM swipe watcher drives.  Keep
    -- its item-cooldown / usability events registered while a hide or fade mode
    -- is active -- the same refcount applyIconLayout maintained pre-migration.
    local mode = settings.icon_visibility_mode
    local visibilityActive = mode ~= nil and mode > 1 and not private.isEditMode
    updateIvmWatcherEvents(instance, visibilityActive)
    local iconTracker = getIconTracker(instance, settings)
    if not iconTracker then return end
    iconTracker.Refresh()
    -- Background suppression, restored from applyIconLayout: a frame that draws
    -- nothing hides its configured background, UNLESS a hide/fade mode is what
    -- emptied it (the frame is still live, just momentarily empty -- the old
    -- path's `visibilityHidAll` branch passed `false` there for the same
    -- reason).  IsCollapsed() is the post-Refresh "nothing was laid out" answer:
    -- lastSpellCount + lastAppendCount, i.e. the old path's visibleCount == 0
    -- once the hide modes are excluded by visibilityActive.
    private.Util.SetComponentEmpty(instance.container,
        not visibilityActive and iconTracker.IsCollapsed())
end

---Apply filtered layout for an aura-rendering additional frame (bar or buffs).
---@param instance additional_frame_instance
---@param settings additional_frame_profile
local function applyAuraLayout(instance, settings)
    local auraTracker = getAuraTracker(instance, settings)
    if auraTracker then auraTracker.Refresh() end
end

-- ---------------------------------------------------------------------------
-- Layout dispatch
-- ---------------------------------------------------------------------------

---Apply the filtered layout for an additional frame (dispatches by type).
---@param instance additional_frame_instance
applyFilteredLayout = function(instance)
    local settings = private.profile.additional_frames[instance.id]
    if not settings then return end
    if not settings.enabled and not private.isEditMode then return end
    -- Respect the AF's own visibility mode (e.g. "hidden").
    -- When not visible, hide addon-owned icons (Racial/Trinket/Consumable)
    -- that have SetIgnoreParentAlpha(true) — they won't hide with the
    -- container since they're parented to their source component.
    local compName = instance.component and instance.component.name
    if compName and not private.isEditMode
        and not private.Anchor.IsVisibleForComponent(compName) then
        if private.fontsDirty then instance.fontsOwed = true end
        for icon in pairs(instance.addonIcons) do
            icon:SetAlpha(0)
        end
        return
    end
    -- A font edit made while hidden: the hosted tracker styles only under
    -- private.fontsDirty, and the pass that reveals this frame carries none.
    local owed = instance.fontsOwed and not private.fontsDirty
    instance.fontsOwed = nil
    if owed then private.fontsDirty = true end
    -- Every frame type renders through its own factory tracker: the aura
    -- types own AuraContainers, "spells" owns an IconTracker whose pooled icon
    -- frames replace what used to be cross-parented CDM viewer children.
    if AURA_TRACKER_BY_TYPE[settings.frame_type] then
        applyAuraLayout(instance, settings)
    elseif settings.frame_type == "spells" then
        applySpellsLayout(instance, settings)
    end
    if owed then private.fontsDirty = false end
    -- Update background visibility after layout (empty state set by layout functions)
    if settings.background and instance.container then
        private.Util.ApplyComponentBackground(instance.container, settings.background)
    end
end

-- ---------------------------------------------------------------------------
-- Cursor following
-- ---------------------------------------------------------------------------

-- anchor_side → SetPoint anchor mapping for cursor mode.
-- "bottom" means the frame sits below the cursor → anchor its TOP edge.
local CURSOR_SIDE_TO_POINT = {
    bottom = "TOP",
    top = "BOTTOM",
    left = "RIGHT",
    right = "LEFT",
    topleft = "BOTTOMRIGHT",
    topright = "BOTTOMLEFT",
    bottomleft = "TOPRIGHT",
    bottomright = "TOPLEFT",
}

---OnUpdate handler that repositions a container at the mouse cursor.
---Reads cached offsets from the frame to avoid per-frame profile lookups.
---@param self frame
local function cursorFollowOnUpdate(self)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x = x / scale
    y = y / scale
    self:ClearAllPoints()
    self:SetPoint(self.cursorAnchorPoint, UIParent, "BOTTOMLEFT",
        x + self.cursorOffsetX, y + self.cursorOffsetY)
end

---Install or remove the cursor-follow OnUpdate on an instance's container.
---Active when anchor_parent == "cursor". Reuses anchor_profile fields:
---anchor_side as cursor anchor point, anchor_offset_x/y as cursor offset.
---Caches values on the frame for fast per-frame access.
---@param instance additional_frame_instance
---@param settings additional_frame_profile
local function updateCursorFollow(instance, settings)
    local container = instance.container
    if not container then return end
    local ap = settings.anchor_profile
    if ap.anchor_parent == "cursor" and not private.isEditMode then
        container.cursorAnchorPoint = CURSOR_SIDE_TO_POINT[ap.anchor_side] or "BOTTOMLEFT"
        container.cursorOffsetX = ap.anchor_offset_x or 0
        container.cursorOffsetY = ap.anchor_offset_y or 0
        container:SetScript("OnUpdate", cursorFollowOnUpdate)
        -- Position immediately so Anchor.Refresh() doesn't leave a stale frame.
        cursorFollowOnUpdate(container)
    else
        container:SetScript("OnUpdate", nil)
    end
end

-- ---------------------------------------------------------------------------
-- Component factory
-- ---------------------------------------------------------------------------

---Create a component table for an additional frame instance.
---@param id string
---@param instance additional_frame_instance
---@return component
local function createComponent(id, instance)
    ---@diagnostic disable-next-line: missing-fields
    local comp = {}
    comp.name = "AdditionalFrame_" .. id

    comp.GetSettings = function()
        return private.profile.additional_frames[id]
    end

    comp.GetEnabled = function()
        local s = private.profile.additional_frames[id]
        return s and s.enabled or false
    end

    comp.GetFrame = function()
        return instance.container
    end

    comp.GetComponentName = function()
        return comp.name
    end

    comp.GetComponentSize = function()
        -- Aura frames render through a tracker factory, whose containers are
        -- engine-sized and SECRET — the container rect is no longer set by a
        -- layout pass here, so reading it would report 0 (and a two-point
        -- anchor to it would inherit the secret rect).  The tracker computes
        -- the box from settings the same way the primary tracker does.
        -- A migrated "spells" frame is in the same position: the factory sizes
        -- its own wrapper, not this container.
        local tracker = instance.iconTracker or instance.auraTracker
        if tracker then
            local w, h = tracker.GetComponentSize()
            -- icon_visibility_mode 2/4 can hide every icon.  The factory then
            -- reports its 1x1 collapse sentinel (IconTracker.GetComponentSize:
            -- "if count == 0 then return 1, 1 end") -- right for the primary
            -- trackers, wrong for an Additional Frame: applyIconLayout held the
            -- container at its configured size precisely so anchored children
            -- keep their slot and the frame stays grabbable.  Restored here, on
            -- the AF side only -- the factory is untouched, so
            -- CooldownTracker/UtilitiesTracker still collapse to 1x1.
            --
            -- 0x0 has to be caught under the SAME condition.  The factory
            -- short-circuits on "spellCount == 0" (lastSpellCount +
            -- lastAppendCount) BEFORE it reaches the hide-mode branch, so a
            -- frame whose assigned_spells are only Trinket/Consumable/Racial
            -- entries -- buildAFIconSpellMap contributes no spell keys, and the
            -- hide filter can empty the append list -- reports 0x0 rather than
            -- the 1x1 sentinel.  Same failure, same repair.  With no hide mode
            -- configured 0x0 still falls through: that is the genuinely-empty
            -- case.
            --
            -- NOT the same condition applyIconLayout used: that branch keyed on
            -- visibilityActive (mode > 1), which INCLUDES fade modes 3/5.  This
            -- one is mode 2/4 only, and that is correct -- a fade mode never
            -- empties the visible set (MakeIconVisibilityFilter's fade branch
            -- always returns false, and a pooled button keeps cue_visAlpha =
            -- fadedAlpha, which layoutButtons counts), so a mode-3/5 frame can
            -- only read empty when it genuinely has nothing.  See
            -- AdditionalFrameManager.md for the icon_visibility_faded_alpha = 0
            -- seam this leaves.
            if instance.iconTracker and not private.isEditMode
                and ((w == 1 and h == 1) or (w == 0 and h == 0)) then
                local s = private.profile.additional_frames[id]
                local visMode = (s and s.icon_visibility_mode) or 1
                if s and s.enabled and (visMode == 2 or visMode == 4) then
                    local iconW = s.icon_size or 1
                    local iconH = (s.icon_height and s.icon_height > 0) and s.icon_height or iconW
                    return math.max(s.width or iconW, 1), math.max(s.height or iconH, 1)
                end
            end
            return w, h
        end
        local c = instance.container
        if c then
            return c:GetWidth(), c:GetHeight()
        end
        return 0, 0
    end

    comp.GetWantsContentWidth = function()
        -- Same delegation as GetComponentSize: the tracker's answer is
        -- engine-gated (slots vs groups) and the two must agree.
        local tracker = instance.iconTracker or instance.auraTracker
        if tracker then
            return tracker.GetWantsContentWidth()
        end
        local s = private.profile.additional_frames[id]
        if not s then return true end
        if s.bar_content == "IconOnly" and s.collapse then return true end
        if s.bar_size_mode == "fill" then return false end
        if s.anchor_profile and s.anchor_profile.anchor_width_mode == "percent" then
            return false
        end
        return true
    end

    -- Refresh this additional frame + re-run anchoring so a container-width
    -- change (bar_content, collapse) propagates to anchored children.
    comp.RefreshAndRelayout = function()
        comp.Refresh()
        if private.Anchor and private.Anchor.Refresh then
            private.Anchor.Refresh()
        end
    end

    comp.Initialize = function()
        -- no-op; lifecycle managed by AdditionalFrameManager
    end

    comp.Refresh = function()
        local s = private.profile.additional_frames[id]
        if not s or (not s.enabled and not private.isEditMode) then
            if instance.container then
                instance.container:Hide()
                instance.container:ClearAllPoints()
                instance.container:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
            end
            return
        end
        if not private.Anchor.IsVisibleForComponent(comp.name) then
            if private.fontsDirty then instance.fontsOwed = true end
            if instance.container then instance.container:Hide() end
            return
        end
        if instance.container then instance.container:Show() end
        applyFilteredLayout(instance)
        updateCursorFollow(instance, s)
        -- In EditMode, ensure container has a minimum size so it remains
        -- clickable and visible even when no viewer children are matched.
        if private.isEditMode and instance.container then
            local w, h = instance.container:GetSize()
            local iconSize = s.icon_size or s.bar_width or 40
            if w < iconSize then instance.container:SetWidth(s.width or iconSize) end
            if h < iconSize then instance.container:SetHeight(iconSize) end
        end
    end

    comp.ContentLayout = function()
        applyFilteredLayout(instance)
    end

    ---Re-alpha the frame's icons for Anchoring's visibility-only pass: a
    ---spells frame's icons ignore container alpha, and an aura frame's
    ---container is frozen in combat.  Both trackers are named after this
    ---component, so they read its effective alpha.
    comp.SyncAlpha = function()
        local tracker = instance.iconTracker or instance.auraTracker
        if tracker then tracker.SyncAlpha() end
    end

    comp.OnEnable = function()
        rebuildSpellRouting()
        if private.CustomSpells then
            private.CustomSpells.OnEnable(comp.name)
        end
        if instance.container then
            comp.Refresh()
        end
        private.ComponentManager.RefreshAllComponents()
        private.Anchor.Refresh()
    end

    comp.OnDisable = function()
        if private.CustomSpells then
            private.CustomSpells.OnDisable(comp.name)
        end
        -- Tear down icon_visibility_mode satellite watcher refcount for this
        -- instance (updateIvmWatcherEvents, still live via applySpellsLayout).
        if instance._cueIvmActive then
            instance._cueIvmActive = nil
            manager._cueIvmCount = (manager._cueIvmCount or 1) - 1
            if manager._cueIvmCount <= 0 and manager._swipeWatcher then
                manager._cueIvmCount = 0
                manager._swipeWatcher:UnregisterEvent("SPELL_UPDATE_USABLE")
                manager._swipeWatcher:UnregisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
            end
        end
        -- Reset addon icon alpha independence so they return to parent chain.
        if instance.addonIcons then
            for icon in pairs(instance.addonIcons) do
                icon:SetIgnoreParentAlpha(false)
            end
            wipe(instance.addonIcons)
        end
        -- ...and the borrowed-icon state our visibility filter wrote, which
        -- addonIcons does not cover (a hide-mode icon is filtered OUT of the
        -- append list yet still carries an alpha override of 0).
        releaseAFForeignIconState(instance, nil)
        -- Hide and park off-screen so the frame doesn't affect anchor chains.
        if instance.container then
            instance.container:Hide()
            instance.container:ClearAllPoints()
            instance.container:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10000, 10000)
        end
        -- Rebuild routing (excludes this now-disabled frame) and refresh
        -- parent components so they reclaim excluded icons.
        rebuildSpellRouting()
        private.ComponentManager.RefreshAllComponents()
        private.Anchor.Refresh()
    end

    return comp
end

-- ---------------------------------------------------------------------------
-- Default settings factories
-- ---------------------------------------------------------------------------

local function createDefaultSpellsSettings(id, name)
    return {
        id = id,
        name = name,
        frame_type = "spells",
        enabled = true,
        alpha = 1,
        assigned_spells = {},
        custom_spells = {},
        width = 300,
        height = 100,
        layout_direction = "horizontal",
        layout_alignment = "center",
        frame_size_mode = "max_width",
        max_icons_per_row = 8,
        icon_size = 40,
        icon_height = 0,
        overflow_icon_size = 20,
        overflow_direction = "top",
        icon_offset = 1,
        hide_icon = false,
        hide_cd_swipe = false,
        -- OFF by default, matching CooldownTracker/UtilitiesTracker and 2.13.4:
        -- an active buff takes the icon over, as in Blizzard's CDM.
        hide_active_swipe = false,
        hide_gcd_swipe = false,
        gcd_edge_charges = false,
        reverse_swipe = false,
        no_desaturation = false,
        force_desaturation = false,
        no_range_tint = false,
        hide_cd_text = false,
        hide_zero_charges = false,
        hide_charge_cd_text = false,
        active_glow = false,
        active_glow_color = {0.2, 0.8, 0.4, 1},
        pandemic_glow = false,
        pandemic_glow_style = "blizzard",
        pandemic_glow_color = {1, 0.843, 0, 1},
        pandemic_glow_thickness = 2,
        pandemic_glow_excludes = {},
        proc_glow_style = "blizzard",
        proc_glow_color = {1, 1, 1, 1},
        proc_glow_alpha = 100,
        proc_glow_thickness = 2,
        -- Ready-flash tint, read by IconTracker's GlowEffect.PlayReadyFlash.
        -- Same default as the two primary icon trackers (Profile.lua); without
        -- it the migrated ready flash renders untinted.
        cdm_glow_color = {1, 0.843, 0, 1},
        suppress_buff_icon_swap = false,
        tooltip_mode = "off",
        tooltip_anchor = "RIGHT",
        icon_visibility_mode = 1,
        icon_visibility_faded_alpha = 0.3,
        icon_visibility_treat_charging_as_on_cd = true,
        timer_font = {
            font_face = "Friz Quadrata TT",
            font_size = 12,
            font_flags = "OUTLINE",
            font_color = {1, 1, 1, 1},
            anchor_point = "CENTER",
            offset_x = 0,
            offset_y = 0,
        },
        stacks_font = {
            font_face = "Arial Narrow",
            font_size = 12,
            font_flags = "OUTLINE",
            font_color = {1, 1, 1, 1},
            anchor_point = "BOTTOMRIGHT",
            offset_x = -2,
            offset_y = 2,
        },
        keybind_font = {
            enabled = false,
            font_face = "2002",
            font_size = 12,
            font_flags = "OUTLINE",
            font_color = {1, 1, 1, 1},
            anchor_point = "BOTTOMLEFT",
            offset_x = 2,
            offset_y = 2,
        },
        background = {
            enabled = false,
            color = {0, 0, 0, 0.6},
            padding = 4,
            rounded = false,
            roundness = 8,
            border_color = {0, 0, 0, 0.8},
        },
        anchor_profile = {
            frame_point = "CENTER",
            parent_point = "CENTER",
            relative_frame = "UIParent",
            xoff = 0,
            yoff = 0,
            anchor_parent = "none",
            anchor_side = "bottom",
            anchor_offset_x = 0,
            anchor_offset_y = 0,
            anchor_width_pct = 100,
            anchor_width_mode = "absolute",
        },
    }
end

local function createDefaultBuffsSettings(id, name)
    return {
        id = id,
        name = name,
        frame_type = "buffs",
        enabled = true,
        alpha = 1,
        assigned_spells = {},
        custom_spells = {},
        -- Per-spell unit scope ("player"/"target"); absent = "both".
        aura_unit = {},
        -- Force the slots engine.  Without this key AuraIconTracker's
        -- `usingSlots` is permanently false and every per-spell feature below
        -- (glow, icon overrides, the whole PlaceGrid layout) is inert.
        always_show_tracked = false,
        -- Grey icon while the aura is not up; slots engine only.
        desaturate_inactive = false,
        width = 300,
        height = 100,
        layout_direction = "horizontal",
        layout_alignment = "center",
        frame_size_mode = "max_width",
        max_icons_per_row = 8,
        icon_size = 40,
        icon_height = 0,
        overflow_icon_size = 20,
        overflow_direction = "top",
        icon_offset = 1,
        -- The only four cooldown-icon keys AuraIconTracker reads.  The rest of
        -- that family (active/GCD swipe, desaturation, cooldown overlay, charge
        -- text) describes an IconTracker button's cooldown state, which an aura
        -- button does not have — the Options panel hides them for that reason.
        hide_cd_swipe = false,
        hide_icon = false,
        hide_cd_text = false,
        reverse_swipe = false,
        active_glow = false,
        active_glow_color = {0.2, 0.8, 0.4, 1},
        pandemic_glow = false,
        pandemic_glow_style = "blizzard",
        pandemic_glow_color = {1, 0.843, 0, 1},
        pandemic_glow_thickness = 2,
        pandemic_glow_excludes = {},
        proc_glow_style = "blizzard",
        proc_glow_color = {1, 1, 1, 1},
        proc_glow_alpha = 100,
        proc_glow_thickness = 2,
        tooltip_mode = "off",
        tooltip_anchor = "RIGHT",
        timer_font = {
            font_face = "Friz Quadrata TT",
            font_size = 12,
            font_flags = "OUTLINE",
            font_color = {1, 1, 1, 1},
            anchor_point = "CENTER",
            offset_x = 0,
            offset_y = 0,
        },
        stacks_font = {
            font_face = "Arial Narrow",
            font_size = 12,
            font_flags = "OUTLINE",
            font_color = {1, 1, 1, 1},
            anchor_point = "BOTTOMRIGHT",
            offset_x = -2,
            offset_y = 2,
        },
        background = {
            enabled = false,
            color = {0, 0, 0, 0.6},
            padding = 4,
            rounded = false,
            roundness = 8,
            border_color = {0, 0, 0, 0.8},
        },
        anchor_profile = {
            frame_point = "CENTER",
            parent_point = "CENTER",
            relative_frame = "UIParent",
            xoff = 0,
            yoff = 0,
            anchor_parent = "none",
            anchor_side = "bottom",
            anchor_offset_x = 0,
            anchor_offset_y = 0,
            anchor_width_pct = 100,
            anchor_width_mode = "absolute",
        },
    }
end

local function createDefaultBarSettings(id, name)
    return {
        id = id,
        name = name,
        frame_type = "bar",
        enabled = true,
        alpha = 1,
        assigned_spells = {},
        custom_spells = {},
        layout_direction = "vertical",
        layout_alignment = "center",
        bar_size_mode = "fixed",
        bar_width = 220,
        width = 220,
        bar_height = 30,
        bar_spacing = 2,
        icon_size = 30,
        icon_offset = 2,
        growth_direction = "up",
        bar_content = "IconAndName",
        collapse = false,
        show_timer = true,
        bar_fill_color = {1, 0.5, 0.25, 1},
        spell_colors = {},
        -- Per-spell unit scope ("player"/"target"); absent = "both".
        aura_unit = {},
        -- Force the slots engine.  Without this key AuraBarTracker's
        -- `usingSlots` is permanently false and the always-show grid is
        -- unreachable.
        always_show_tracked = false,
        -- Grey icon while the aura is not up; slots engine only.
        desaturate_inactive = false,
        active_glow = false,
        active_glow_color = {0.2, 0.8, 0.4, 1},
        pandemic_glow = false,
        pandemic_glow_style = "blizzard",
        pandemic_glow_color = {1, 0.843, 0, 1},
        pandemic_glow_thickness = 2,
        pandemic_glow_excludes = {},
        -- "border" rather than the icon builders' "blizzard" — square proc art
        -- stretched across a wide bar reads wrong.  See the BuffTrackerBars note.
        proc_glow_style = "border",
        proc_glow_color = {1, 1, 1, 1},
        proc_glow_alpha = 100,
        proc_glow_thickness = 2,
        tooltip_mode = "off",
        tooltip_anchor = "RIGHT",
        name_font = {
            font_face = "Friz Quadrata TT",
            font_size = 12,
            font_flags = "OUTLINE",
            font_color = {1, 1, 1, 1},
            anchor_point = "LEFT",
            offset_x = 5,
            offset_y = 0,
        },
        duration_font = {
            font_face = "Friz Quadrata TT",
            font_size = 12,
            font_flags = "OUTLINE",
            font_color = {1, 1, 1, 1},
            anchor_point = "RIGHT",
            offset_x = -8,
            offset_y = 0,
        },
        stacks_font = {
            font_face = "Arial Narrow",
            font_size = 12,
            font_flags = "OUTLINE",
            font_color = {1, 1, 1, 1},
            anchor_point = "BOTTOMRIGHT",
            offset_x = -5,
            offset_y = 5,
        },
        background = {
            enabled = false,
            color = {0, 0, 0, 0.6},
            padding = 4,
            rounded = false,
            roundness = 8,
            border_color = {0, 0, 0, 0.8},
        },
        anchor_profile = {
            frame_point = "CENTER",
            parent_point = "CENTER",
            relative_frame = "UIParent",
            xoff = 0,
            yoff = 0,
            anchor_parent = "none",
            anchor_side = "bottom",
            anchor_offset_x = 0,
            anchor_offset_y = 0,
            anchor_width_pct = 100,
            anchor_width_mode = "absolute",
        },
    }
end

-- ---------------------------------------------------------------------------
-- Frame activation / deactivation
-- ---------------------------------------------------------------------------

---Activate a single additional frame from its profile settings.
---Creates the container, component, registers with ComponentManager.
---@param id string
---@param settings additional_frame_profile
local function activateFrame(id, settings)
    if activeFrames[id] then return end

    local rawName = (settings.name and settings.name ~= "") and settings.name or id
    local safeName = rawName:gsub("[^%w_]", "_")
    local container = CreateFrame("Frame", "CUE_AF_" .. safeName, UIParent)
    container:SetSize(1, 1)
    if settings.enabled then
        container:Show()
    else
        container:Hide()
    end

    local instance = {
        id = id,
        container = container,
        addonIcons = {},
    }

    local comp = createComponent(id, instance)
    instance.component = comp

    activeFrames[id] = instance
    private.ComponentManager.RegisterComponent(comp.name, comp)

    -- Install cursor-follow OnUpdate if enabled
    updateCursorFollow(instance, settings)
end

---Deactivate and clean up a single additional frame.
---@param id string
local function deactivateFrame(id)
    local instance = activeFrames[id]
    if not instance then return end

    -- Unregister from EditMode before removing the component so the frame
    -- reference is still valid for cleanup.
    if private.EditMode and private.EditMode.UnregisterAdditionalFrame then
        private.EditMode.UnregisterAdditionalFrame(instance.component)
    end

    -- Release custom spell state (event watchers, frame pool) for this AF
    -- before unregistering so its component name still resolves.
    if private.CustomSpells then
        private.CustomSpells.OnDisable(instance.component.name)
    end

    -- Tear down this frame's factory tracker.  manager.OnProfileChanged
    -- deactivates + reactivates EVERY additional frame on EVERY profile switch
    -- and activateFrame builds a fresh instance table, so without this the old
    -- tracker's container, pooled buttons, aura slots and event registrations
    -- are abandoned while still registered.  OnDisable self-guards the
    -- Show/Hide half on InCombatLockdown().
    if instance.auraTracker then instance.auraTracker.OnDisable() end
    if instance.iconTracker then instance.iconTracker.OnDisable() end

    -- Unregister component
    private.ComponentManager.UnregisterComponent(instance.component.name)

    -- Reset SetIgnoreParentAlpha on addon-owned icons so they return
    -- to their original component's alpha chain.
    if instance.addonIcons then
        for icon in pairs(instance.addonIcons) do
            icon:SetIgnoreParentAlpha(false)
        end
        wipe(instance.addonIcons)
    end
    -- Same for the borrowed-icon state the visibility filter wrote.  The
    -- iconTracker.OnDisable above already releases it for a rendered spells
    -- frame (releaseAppendFrames routes through collectAFAppendIcons); this
    -- covers a frame that never got a tracker, and the dead viewer-child path.
    releaseAFForeignIconState(instance, nil)

    -- Hide container; FontStrings parented to child icons follow automatically.
    -- Frames are never garbage collected in WoW; deleted frames stay as hidden
    -- ghosts until /reload.
    instance.container:Hide()

    activeFrames[id] = nil
end

---Find the next available frame ID.
---@return string
local function allocateId()
    local id
    repeat
        id = "af_" .. nextFrameId
        nextFrameId = nextFrameId + 1
    until not private.profile.additional_frames[id]
    return id
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---Migrate legacy additional frame profiles to the new type system.
---"icon" → "spells". Strips source from assigned_spells entries.
---Detects orphaned buff-source spells in spells-type frames and notifies.
---Idempotent: only acts on frame_type == "icon".
local function migrateAdditionalFrames()
    if not private.profile or not private.profile.additional_frames then return end

    local orphanedByFrame = {}
    for id, settings in pairs(private.profile.additional_frames) do
        -- Every frame this addon creates has the key, but an imported frame
        -- need not — and this loop, rebuildSpellRouting and
        -- OnAddonIconRefresh all iterate it unguarded.
        if settings.assigned_spells == nil then settings.assigned_spells = {} end
        if settings.frame_type == "icon" then
            settings.frame_type = "spells"
            local newSpells = {}
            for _, entry in ipairs(settings.assigned_spells) do
                local spellID, source = normalizeEntry(entry)
                if ADDON_ICON_SOURCES[source] then
                    -- Keep addon sources in {id, source} format
                    newSpells[#newSpells + 1] = { spellID, source }
                elseif source == "BuffIcon" or source == "BuffBar" then
                    -- Orphaned buff-source spell — keep as plain ID (inert in spells frame)
                    newSpells[#newSpells + 1] = spellID
                    if not orphanedByFrame[id] then orphanedByFrame[id] = {} end
                    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
                    orphanedByFrame[id][#orphanedByFrame[id] + 1] = name or tostring(spellID)
                else
                    -- CooldownViewer spell — store as plain number
                    newSpells[#newSpells + 1] = spellID
                end
            end
            settings.assigned_spells = newSpells
        elseif settings.frame_type == "bar" then
            -- Normalize bar entries: strip source
            local newSpells = {}
            for _, entry in ipairs(settings.assigned_spells) do
                local spellID = normalizeEntry(entry)
                newSpells[#newSpells + 1] = spellID
            end
            settings.assigned_spells = newSpells
        end
    end

    -- Backfill missing default keys for existing frames
    for _, settings in pairs(private.profile.additional_frames) do
        if settings.custom_spells == nil then settings.custom_spells = {} end
        if settings.frame_type == "spells" then
            if settings.hide_icon == nil then settings.hide_icon = false end
            if settings.hide_zero_charges == nil then settings.hide_zero_charges = false end
            if settings.hide_charge_cd_text == nil then settings.hide_charge_cd_text = false end
            if settings.no_cd_overlay == nil then settings.no_cd_overlay = false end
            if settings.hide_cd_swipe == nil then settings.hide_cd_swipe = false end
            if settings.suppress_buff_icon_swap == nil then settings.suppress_buff_icon_swap = false end
            if settings.icon_visibility_treat_charging_as_on_cd == nil then settings.icon_visibility_treat_charging_as_on_cd = true end
            -- createDefaultSpellsSettings gained this key after frames already
            -- existed, and PlayReadyFlash tolerates nil by flashing white — so
            -- without the backfill an older frame flashes white forever while a
            -- newly created one flashes gold, with no AF-panel picker to fix it.
            if settings.cdm_glow_color == nil then settings.cdm_glow_color = {1, 0.843, 0, 1} end
        end
        if settings.frame_type == "buffs" then
            if settings.hide_cd_swipe == nil then settings.hide_cd_swipe = false end
            if settings.hide_icon == nil then settings.hide_icon = false end
        end
        if settings.frame_type == "spells" or settings.frame_type == "buffs" then
            if settings.active_glow == nil then settings.active_glow = false end
            if settings.active_glow_color == nil then settings.active_glow_color = {0.2, 0.8, 0.4, 1} end
            if settings.pandemic_glow == nil then settings.pandemic_glow = false end
            if settings.pandemic_glow_style == nil then settings.pandemic_glow_style = "blizzard" end
            if settings.pandemic_glow_color == nil then settings.pandemic_glow_color = {1, 0.843, 0, 1} end
            if settings.pandemic_glow_thickness == nil then settings.pandemic_glow_thickness = 2 end
            if settings.pandemic_glow_excludes == nil then settings.pandemic_glow_excludes = {} end
            if settings.proc_glow_style == nil then
                if settings.proc_glow_hide == true then
                    settings.proc_glow_style = "none"
                else
                    settings.proc_glow_style = "blizzard"
                end
            end
            settings.proc_glow_hide = nil
            if settings.proc_glow_color == nil then settings.proc_glow_color = {1, 1, 1, 1} end
            if settings.proc_glow_alpha == nil then settings.proc_glow_alpha = 100 end
            if settings.proc_glow_thickness == nil then settings.proc_glow_thickness = 2 end
        end
        -- Aura frames only: the slots-engine override. Frames created before it
        -- existed have no key, which reads as false at the tracker but also
        -- leaves the Options toggle with nothing to bind to.
        if settings.frame_type == "bar" or settings.frame_type == "buffs" then
            if settings.always_show_tracked == nil then settings.always_show_tracked = false end
        end
        if settings.frame_type == "bar" then
            if settings.bar_fill_color == nil then settings.bar_fill_color = {1, 0.5, 0.25, 1} end
            if settings.spell_colors == nil then settings.spell_colors = {} end
            if settings.active_glow == nil then settings.active_glow = false end
            if settings.active_glow_color == nil then settings.active_glow_color = {0.2, 0.8, 0.4, 1} end
            if settings.pandemic_glow == nil then settings.pandemic_glow = false end
            if settings.pandemic_glow_style == nil then settings.pandemic_glow_style = "blizzard" end
            if settings.pandemic_glow_color == nil then settings.pandemic_glow_color = {1, 0.843, 0, 1} end
            if settings.pandemic_glow_thickness == nil then settings.pandemic_glow_thickness = 2 end
            if settings.pandemic_glow_excludes == nil then settings.pandemic_glow_excludes = {} end
            if settings.proc_glow_style == nil then settings.proc_glow_style = "border" end
            if settings.proc_glow_color == nil then settings.proc_glow_color = {1, 1, 1, 1} end
            if settings.proc_glow_alpha == nil then settings.proc_glow_alpha = 100 end
            if settings.proc_glow_thickness == nil then settings.proc_glow_thickness = 2 end
        end
    end

    -- Notify about orphaned buff spells after loading screen
    if next(orphanedByFrame) then
        local function notifyOrphans()
            for id, spells in pairs(orphanedByFrame) do
                local s = private.profile.additional_frames[id]
                local frameName = s and s.name or id
                private.print(string.format(
                    "ClassUIEnhanced: '%s' was migrated to Spells type. These buff spells need reassigning to a Buffs frame: %s",
                    frameName, table.concat(spells, ", ")
                ))
            end
        end
        C_Timer.After(3, notifyOrphans)
    end
end


---Initialize from the current profile. Called once from Init.lua after
---component initialization but before Anchor.Initialize.
manager.Initialize = function()
    migrateAdditionalFrames()

    -- Activate all existing additional frames from profile
    for id, settings in pairs(private.profile.additional_frames) do
        activateFrame(id, settings)
    end

    rebuildSpellRouting()

    -- Listen for CDM spell changes to update affected additional frames.
    -- CDM viewers are suppressed (hidden) so their Layout() never fires;
    -- OnCDMSpellsChanged fires whenever the viewer's CDM data changes.
    private.Callback.Register("OnCDMSpellsChanged", function()
        -- The model was rebuilt: identity owners (linkedOwner) may have moved.
        rebuildSpellRouting()
        for _, instance in pairs(activeFrames) do
            applyFilteredLayout(instance)
        end
    end)

    -- When a primary component is disabled, refresh affected additional frames.
    private.Callback.Register("OnComponentDisable", function()
        for _, instance in pairs(activeFrames) do
            applyFilteredLayout(instance)
        end
    end)

    -- Rebuild routing when spell overrides change so IsSpellRouted()
    -- returns correct results for the new override on the first layout pass.
    local overrideWatcher = CreateFrame("Frame")
    overrideWatcher:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
    overrideWatcher:SetScript("OnEvent", function()
        rebuildSpellRouting()
    end)

    -- Re-apply swipe suppression after cooldown state changes.
    -- Blizzard's RefreshSpellCooldownInfo re-applies SetDrawSwipe(true) on
    -- SPELL_UPDATE_COOLDOWN, overriding our suppression.
    --
    -- Aura frames are excluded: their Cooldown is `cue_Cooldown`, created by
    -- AuraContainer.makeInit, so Blizzard never resets it and there is nothing
    -- to re-assert.  Without the skip a `buffs` frame with `reverse_swipe` on
    -- would match the predicate below and pay a full aura relayout on every
    -- SPELL_UPDATE_COOLDOWN (see .context/performance.md).
    local afSwipeDirty = false
    manager._swipeWatcher = manager._swipeWatcher or CreateFrame("Frame")
    local swipeWatcher = manager._swipeWatcher
    swipeWatcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    swipeWatcher:SetScript("OnEvent", function()
        if not afSwipeDirty then
            afSwipeDirty = true
            swipeWatcher:SetScript("OnUpdate", function(self)
                afSwipeDirty = false
                self:SetScript("OnUpdate", nil)
                for _, instance in pairs(activeFrames) do
                    local s = private.profile.additional_frames[instance.id]
                    if s and s.enabled and not manager.IsAuraType(s.frame_type)
                        and ((s.icon_visibility_mode and s.icon_visibility_mode > 1) or s.hide_cd_swipe or s.hide_active_swipe or s.hide_gcd_swipe or s.gcd_edge_charges or s.reverse_swipe or s.no_desaturation or s.hide_zero_charges or s.hide_charge_cd_text) then
                        applyFilteredLayout(instance)
                    end
                end
            end)
        end
    end)

end

---A fresh default settings table for a frame of `frameType`, with no id or
---name. Edit Mode's Reset To Default restores from it.
---@param frameType "spells"|"buffs"|"bar"
---@return table
manager.GetDefaultSettings = function(frameType)
    if frameType == "bar" then
        return createDefaultBarSettings()
    elseif frameType == "buffs" then
        return createDefaultBuffsSettings()
    end
    return createDefaultSpellsSettings()
end

---Create a new additional frame with default settings.
---@param frameType string "spells", "buffs", or "bar"
---@param name string user-facing label
---@return string id the allocated frame id
manager.CreateFrame = function(frameType, name)
    local id = allocateId()

    local settings
    if frameType == "bar" then
        settings = createDefaultBarSettings(id, name)
    elseif frameType == "buffs" then
        settings = createDefaultBuffsSettings(id, name)
    else
        settings = createDefaultSpellsSettings(id, name)
    end

    private.profile.additional_frames[id] = settings
    activateFrame(id, settings)
    rebuildSpellRouting()

    -- Register with EditMode if available
    if private.EditMode and private.EditMode.RegisterAdditionalFrame then
        private.EditMode.RegisterAdditionalFrame(activeFrames[id].component)
    end

    -- Rebuild the anchor tree so the new component is included in anchorRoots,
    -- then refresh all components and re-anchor (matches DeleteFrame pattern).
    private.Anchor.RebuildAnchorTree()
    private.ComponentManager.RefreshAllComponents()
    private.Anchor.Refresh()
    -- RegisterComponent does not fire OnComponentEnable, so nothing else
    -- re-evaluates the CDM CVar predicate for the newly created AF.
    private.CDMDataSource.EnsureEnabled()
    return id
end

---Delete an additional frame and clean up all references.
---@param id string
manager.DeleteFrame = function(id)
    deactivateFrame(id)
    private.profile.additional_frames[id] = nil
    rebuildSpellRouting()

    -- Refresh parent components so excluded spells return to their viewers
    private.ComponentManager.RefreshAllComponents()
    private.Anchor.Refresh()
    -- Re-evaluate the CDM CVar predicate now that this AF's settings are gone.
    private.CDMDataSource.EnsureEnabled()
end

---Check profile data directly to determine if a spell is assigned to an
---enabled bar-type additional frame.  Used as a fallback when runtime routing
---tables have not been populated yet during initial load.
---@param spellID number
---@return boolean
local function isSpellRoutedToBarProfile(spellID)
    local afs = private.profile.additional_frames
    if not afs then return false end
    for _, settings in pairs(afs) do
        -- Runs before Initialize's migration backfills assigned_spells.
        if settings.enabled and settings.frame_type == "bar" and settings.assigned_spells then
            for _, entry in ipairs(settings.assigned_spells) do
                local assignedID = normalizeEntry(entry)
                if assignedID == spellID then return true end
                local override = getOverrideSpell(assignedID)
                if override == spellID then return true end
            end
        end
    end
    return false
end

---Check if a spellID is routed to an additional frame in the domain matching
---the given source. Source maps to routing domain: Essential/Utility/Trinket/
---Consumable/Racial → abilityRouting; BuffIcon/BuffBar → buffRouting.
---@param spellID number
---@param source string|nil  source key ("Essential", "Utility", "BuffIcon", "BuffBar", etc.)
---@return boolean
---@param id number
---@param rt table  routing sub-table
---@return string|nil frameId
local function routingTableGet(id, rt)
    return rt[id]
end

---@param id number
---@return true|nil
local function barProfileHas(id)
    if isSpellRoutedToBarProfile(id) then return true end
    return nil
end

manager.IsSpellRouted = function(spellID, source)
    ensureRoutingResolved()
    local rt = getRoutingSubTable(source)
    -- Identity walk, not a raw lookup: the routing table is keyed by the id the
    -- Options picker offered (`overrideSpellID or spellID`), while a cooldown
    -- tracker asks with the plain `spellID` its map is keyed by.  Without this
    -- an overridden spell routed to an AF stayed in the tracker too and drew
    -- twice.
    if private.Util.ResolveByBaseOrOverride(spellID, routingTableGet, rt) then return true end
    -- Fallback: runtime routing tables may not be populated yet during initial
    -- load.  Check profile data directly for bar-type AFs.
    if source == "BuffBar" then
        return private.Util.ResolveByBaseOrOverride(spellID, barProfileHas) == true
    end
    return false
end

---Returns the profile settings table for the additional frame that a spell is
---routed to in the domain matching the given source, or nil if not routed.
---@param spellID number
---@param source string|nil
---@return table|nil
manager.GetRoutedFrameSettings = function(spellID, source)
    ensureRoutingResolved()
    local rt = getRoutingSubTable(source)
    -- The same identity walk as IsSpellRouted, so a spell it reports as
    -- routed always has settings here.
    local frameId = private.Util.ResolveByBaseOrOverride(spellID, routingTableGet, rt)
    if not frameId then return nil end
    return private.profile.additional_frames[frameId]
end

---Returns true if the given source key is an addon-owned icon source
---(Trinket, Consumable, Racial) rather than a CooldownViewer source.
---@param source string|nil
---@return boolean
manager.IsAddonIconSource = function(source)
    return ADDON_ICON_SOURCES[source] or false
end

---Called when the assigned spells for an additional frame change.
---Rebuilds routing table and source viewer cache, refreshes affected viewers.
---@param id string
manager.OnSpellAssignmentChanged = function(id)
    rebuildSpellRouting()

    local instance = activeFrames[id]
    if instance then
        local settings = private.profile.additional_frames[id]
        if settings then
            -- Apply layout immediately so the frame shows without disable/enable
            if instance.component then
                instance.component.Refresh()
            end
        end
    end

    -- Refresh all parent components (they re-layout with updated excludeFilter)
    private.ComponentManager.RefreshAllComponents()
    private.Anchor.Refresh()
end

---Called by TrinketTracker / ConsumableTracker after their icons refresh.
---Re-layouts any additional frames that have addon icon sources assigned.
manager.OnAddonIconRefresh = function()
    for _, instance in pairs(activeFrames) do
        local settings = private.profile.additional_frames[instance.id]
        if settings and settings.frame_type == "spells" then
            -- Check if this instance has any addon icon sources
            for _, entry in ipairs(settings.assigned_spells) do
                local _, source = normalizeEntry(entry)
                if ADDON_ICON_SOURCES[source] then
                    applyFilteredLayout(instance)
                    break
                end
            end
        end
    end
end

---Unregister all additional frame components from ComponentManager and EditMode.
---Called before switching profiles so that layout passes triggered by Hide()
---during deactivation don't encounter stale components with nil settings.
manager.UnregisterAllComponents = function()
    for _, instance in pairs(activeFrames) do
        if private.EditMode and private.EditMode.UnregisterAdditionalFrame then
            private.EditMode.UnregisterAdditionalFrame(instance.component)
        end
        private.ComponentManager.UnregisterComponent(instance.component.name)
    end
end

---Destroy all active frames and re-initialize from the current profile.
---Called when the active profile changes (switch, copy, reset).
manager.OnProfileChanged = function()
    for id in pairs(activeFrames) do
        deactivateFrame(id)
    end
    wipe(activeFrames)
    for _, sub in pairs(abilityRouting) do wipe(sub) end
    wipe(abilityRouting)
    wipe(buffRouting)
    nextFrameId = 1

    if private.profile and private.profile.additional_frames then
        migrateAdditionalFrames()
        for id, settings in pairs(private.profile.additional_frames) do
            activateFrame(id, settings)
        end
        rebuildSpellRouting()
    end
end

---Return all active frame IDs for the options UI.
---@return string[]
manager.GetAllFrameIds = function()
    local ids = {}
    for id in pairs(activeFrames) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

---Return the instance for a given frame ID.
---@param id string
---@return additional_frame_instance|nil
manager.GetInstance = function(id)
    return activeFrames[id]
end

---Rebuild the spell routing tables.  Must be called when isEditMode changes
---so that disabled AFs are correctly included/excluded from the routing table
---before any component refresh.
manager.RebuildRouting = rebuildSpellRouting

private.AdditionalFrameManager = manager

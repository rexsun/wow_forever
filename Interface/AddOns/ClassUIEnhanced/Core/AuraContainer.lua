---AuraContainer facade for ClassUIEnhanced.
---
---Wraps Blizzard's CustomAuraContainerTemplate (WoW 12.1+) to display buff auras
---via the secure AuraContainer system.  Provides:
---  * Container creation and aura group management
---  * initializeFrame closure factory (makeInit)
---  * Per-tracker button registry with dirty-flag restyle path
---  * Native pandemic regions (AddPandemicRegion) behind the pandemic_glow suite
---
---Hard-fails at load time if CustomAuraContainerTemplate is absent (requires 12.1+).

local _
---@type string, private
local addonName, private = ...
local LAC = LibStub("LibAuraContainer-1.0")

---@class auracontainerfacade
---@field Create fun(name: string, parent: frame, unit: string|nil): frame, frame
---@field CreateContainer fun(name: string, parent: frame): frame
---@field Suspend fun(container: frame)  disable a container for teardown; the next sync that wants auras re-enables it
---@field IdentityFilterHolds fun(filter: string, unit: string): boolean  will Blizzard's identity gate apply includeSpellIDs for this filter on this unit
---@field GateOnIdentity fun(container: frame, filter: string)  keep a container disabled while its filter's identity gate fails on its unit; re-call on reaction edges
---@field ExpandUnitScope fun(scopeMap: table<number,string>|nil): table<number,string>|nil
---@field SplitByUnitScope fun(spellMap: table<number,true>, scopeMap: table<number,string>|nil): table<number,true>, table<number,true>, table<number,true>
---@field UnitScopeAllowsSlot fun(scopeMap: table<number,string>|nil, spellID: number, isTargetContainer: boolean): boolean
---@field SyncGroup fun(container: frame, groupKey: string, filter: string, spellIDMap: table<number,true>, initFn: function|nil, layoutOpts: table, idSetFor: (fun(spellID: number): table<number,true>|nil)|nil)
---@field SyncSpellGroups fun(container: frame, keyPrefix: string, filter: string, spellIDMap: table<number,true>, idSetFor: (fun(spellID: number): table<number,true>|nil)|nil, initFor: fun(spellID: number): function, layoutOpts: table, rank: table<number,number>|nil)
---@field SyncSlots fun(container: frame, filters: string[], spellIDs: number[], cellFor: fun(index: number): frame, initButton: fun(button: frame, cell: frame, spellID: number), idSetFor: (fun(spellID: number, filterIndex: number): table<number,true>|nil)|nil, sigSalt: string|nil)
---@field ApplyTooltip fun(button: frame, settings: table)
---@field ApplyActiveGlow fun(button: frame, settings: table)
---@field ApplyCdmAlertGlow fun(button: frame, visualAlertType: number|nil, iconWidth: number|nil)  show/hide the CDM OnAuraApplied Visual alert on an aura button; the engine gates it with the aura
---@field SyncProcGlow fun(cells: frame[], list: number[], enabled: boolean, settings: table)
---@field AttachPandemic fun(button: frame, settings: table, componentName: string|nil, cell: frame|nil, barFrame: frame|nil)
---@field SyncPandemic fun(componentName: string, cells: frame[]|nil, list: number[]|nil, enabled: boolean, settings: table)
---@field CreateTextLayer fun(button: frame): frame  raised child frame to host a button's own text, above the border/cooldown child frames
---@field makeInit fun(componentName: string, getSettingsFn: fun():table, spellID: number|nil, singleFrame: boolean|nil): function
---@field RegisterTracker fun(componentName: string, restyleFn: fun(button:frame, settings:table))
---@field TrackButton fun(componentName: string, button: frame)
---@field ForEachTrackedButton fun(componentName: string, fn: fun(button: frame))  walk every acquired button of either engine; does NOT gate on aura secrecy
---@field MarkDirty fun(componentName: string)
---@field RestyleIfDirty fun(componentName: string, settings: table)

---Per-tracker state for the dirty-flag restyle system.
---Key = componentName; value = {restyleFn, buttons, isDirty}.
---@type table<string, {restyleFn: fun(button:frame, settings:table), buttons: table<frame, true>, isDirty: boolean}>
local trackerState = {}

-- ---------------------------------------------------------------------------
-- The identity-filter gate
-- ---------------------------------------------------------------------------
--
-- Blizzard applies `includeSpellIDs` only when
-- `AuraContainerUtil.CanApplyIdentityCandidateFilters` allows it
-- (`Blizzard_AuraContainerUtil.lua:11`).  When it does not, the spell-ID filter
-- is SKIPPED ENTIRELY -- not applied and failed, skipped -- so every aura
-- passing the container's filter STRING is admitted and a tracked-spell
-- container fills with untracked auras.  The stored filter is never damaged;
-- only the evaluation is wrong.
--
-- 12.1.0.69465 hotfixed the player-side half of this: a HELPFUL aura on the
-- player, a group member or their pet now short-circuits to "apply the filter"
-- (`:29`), and both `UnitCanAssist` calls now pass `canAssistImmunePC` /
-- `canAssistUninteractable` (`:35`), so vehicles, charms, cutscenes, mind
-- control and teleports no longer open the gate.  The addon-side recovery pass
-- that watched `UNIT_FLAGS` / `PLAYER_CONTROL_*` / vehicle edges and re-ran
-- `UpdateAllAuras` on every container went with it.
--
-- What remains is per-UNIT and deliberate: the gate still refuses a HARMFUL
-- filter on a unit the player can assist, and a HELPFUL one on a unit that is
-- neither player-controlled nor assistable.  Both are the CROSS filter of a
-- two-filter target block -- the one that unit's reaction makes meaningless
-- anyway -- so the owner hides that block, on the edges that move reaction:
-- `PLAYER_TARGET_CHANGED`, and `UNIT_FACTION` for the unit AND for the player
-- (being mind controlled flips the player's side, and fires it for "player"
-- only).  `SetShown` on an addon-owned frame is unrestricted, which is what
-- lets the guard work in combat.

---Would Blizzard's identity gate actually APPLY `includeSpellIDs` to the auras a
---container carrying `filter` on `unit` can receive?
---
---This is `CanApplyIdentityCandidateFilters` reduced by what the filter STRING
---already guarantees: a HARMFUL filter admits only harmful auras, so its gate
---collapses to `not UnitCanAssist`, and a HELPFUL one to the player-controlled
---short-circuit OR `UnitCanAssist`.  Same predicates, same unit, same arguments,
---so the two answers cannot drift apart -- whatever the game does to a unit's
---flags, we read exactly what the gate reads.
---
---Conservative in one direction: never-secret spells are exempt from the gate
---(`Blizzard_AuraContainerUtil.lua:23`) and would still be filtered correctly, so
---hiding the container hides those too.  Showing nothing beats showing every
---aura on the unit.
---@param filter string  the container's AuraUtil filter string
---@param unit string  the container's unit token
---@return boolean
local function identityFilterHolds(filter, unit)
    if filter:find("HARMFUL", 1, true) then
        return not UnitCanAssist("player", unit, true, true)
    end
    if private.compat.UnitIsPlayerControlledOrGroupMember(unit) then return true end
    return UnitCanAssist("player", unit, true, true)
end

-- ---------------------------------------------------------------------------
-- Gate-proof off switch
-- ---------------------------------------------------------------------------
--
-- An empty `includeSpellIDs` is the only "match nothing" the slot and group APIs
-- offer -- there is no public RemoveAuraSlot / RemoveAuraGroup -- and it is an
-- off switch only while the identity gate above holds.  Skip the gate and the
-- empty map is skipped with it, so a container tracking NOTHING shows
-- EVERYTHING its filter string admits.  That is the worst corner of the
-- asymmetry: with no tracked spell there is no icon chrome to draw either, so
-- the leak surfaces as adornments alone -- a pandemic glow or a duration ring
-- floating where no icon is.
--
-- `SetEnabled(false)` is immune to it.  `ParseAuras` early-returns on a disabled
-- container (`Blizzard_ManagedAuraContainer.lua:507`), so no aura is ever
-- offered to a candidate filter and the gate has nothing left to widen.  The
-- toggle runs a full rebuild, hence the demand table: the flip is paid on the
-- transition, not on every pass.

---Per-container demand: section key -> does that section track anything.
---Sections are disjoint per container (the slots engine keys `"slots"`, the
---groups engine its group key, the per-spell engine its key prefix -- which is
---never equal to one of its own `<prefix>_s<spellID>` keys), so a container
---stays enabled while ANY of them wants auras.
---@type table<frame, table<string, boolean>>
local containerDemand = setmetatable({}, {__mode = "k"})

---Per-container identity-gate filter (`GateOnIdentity`): the container is
---enabled only while `identityFilterHolds(filter, unit)` holds, on top of its
---demand.
---@type table<frame, string>
local containerGate = setmetatable({}, {__mode = "k"})

---Enable `container` exactly when some demand section wants auras AND its
---identity gate, if it has one, holds.
---@param container frame
local function applyEnabled(container)
    local any = false
    local demand = containerDemand[container]
    if demand then
        for _, v in pairs(demand) do
            if v then
                any = true
                break
            end
        end
    end
    local gate = containerGate[container]
    if any and gate then
        any = identityFilterHolds(gate, container:GetUnit())
    end
    container:SetEnabled(any)
end

---Record whether one section of `container` tracks anything, and enable or
---disable the container to match.  Call BEFORE any signature early-return.
---@param container frame
---@param key string  section key: a group key, a group-key prefix, or "slots"
---@param wants boolean
local function setContainerDemand(container, key, wants)
    local demand = containerDemand[container]
    if not demand then
        demand = {}
        containerDemand[container] = demand
    end
    if demand[key] == wants then return end
    demand[key] = wants
    applyEnabled(container)
end

---Gate `container` on Blizzard's identity gate for `filter` on its unit: while
---the gate fails, the container is DISABLED.  For a container whose every slot
---carries that one filter.  Call once to arm it, then again on every edge that
---can flip the unit's reaction (`PLAYER_TARGET_CHANGED`, `UNIT_FACTION` for the
---unit and for the player).
---
---Disabling rather than hiding is for owners with engine-shown decorations that
---outlive their button's visibility (IconTracker's covered-icon masks, which
---ignore their parent's): a hidden container stops processing, so its slots
---keep the last unit's matches, while a disabled one clears them
---(`ParseAllAuras` drops every candidate before its enabled check).
---@param container frame
---@param filter string  the filter string every slot of `container` carries
local function gateOnIdentity(container, filter)
    containerGate[container] = filter
    applyEnabled(container)
end

---Switch a container off for teardown: forget every recorded demand section,
---then disable it.
---
---Forgetting the record is the whole point.  A bare `SetEnabled(false)` that
---left the record UNTOUCHED would swallow the re-enable: the sections still read
---`true`, so the first `setContainerDemand(container, key, true)` of a re-enabled
---tracker's next sync matches on `demand[key] == wants` and early-returns without
---ever calling `SetEnabled(true)` — and that sync is the only path back, since
---there is no explicit resume.  With the record empty the same call sees a change
---and re-enables.
---
---(Writing `false` into each section would clear that hazard too — `false ~= true`
---proceeds.  `wipe` is still the better implementation because it additionally
---drops sections that will never be re-synced.)
---
---`SetEnabled` self-guards on an unchanged value
---(`AuraContainerSharedMixin:SetEnabled`), so a redundant call costs nothing.
---@param container frame
local function suspendContainer(container)
    local demand = containerDemand[container]
    if demand then wipe(demand) end
    container:SetEnabled(false)
end

---Create a plain wrapper Frame plus the AuraContainer inside it.
---
---Two-frame construction, secret-rect isolation: the engine sizes the
---AuraContainer with SECRET values (`OnLayoutComplete` does
---`container:SetSize(secretwrap(w, h))`), so any frame two-point-anchored to
---it — and any `GetWidth()`/`GetHeight()` read downstream — inherits a secret
---rect. Live incident: OutboundBuffTracker's percent-width anchor to
---BuffTrackerBars errored "attempt to compare a secret number value". The
---WRAPPER is the component/anchor-facing frame: its rect stays addon-owned
---(the anchor pass sizes it from GetComponentSize estimates), and the aura
---container hangs inside it single-point anchored, so the secret size never
---propagates. The pin corner and the flow origin
---(`SetFlowLayoutAnchorPoint`) must always MATCH — elements are anchored to
---the container at the flow origin (`ApplyElementLayout`), so a mismatched
---pin places the block at a secret offset. Neither is set here — both are
---derived from the component's growth/alignment settings and applied together
---in its layout sync (`applyContainerFlow`). Components use
---the wrapper for GetFrame/Show/Hide/SetAlpha and the aura container for all
---AuraContainer API calls.
---@param name string  global frame name for the wrapper, e.g. "CUE_BT_Container"
---@param parent frame  parent frame (typically UIParent)
---@param unit string|nil  container unit; defaults to "player" (SetUnit is per container, so a second unit means a second container)
---@return frame wrapper, frame auraContainer
local function create(name, parent, unit)
    local wrapper = CreateFrame("Frame", name, parent)
    local container = LAC:CreateContainer(name .. "_Aura", wrapper)
    container:SetPoint("TOPLEFT")
    container:SetUnit(unit or "player")
    container:SetEnabled(true)
    container:Show()
    return wrapper, container
end

---Create a bare AuraContainer in `parent`, with NO wrapper and NO anchor — the
---caller owns placement.
---
---For the two-container (player + target) trackers, whose containers share one
---auto-sized bounds frame so the pair can be centred as a unit: the per-container
---wrapper `create` adds would sit between the bounds frame and the containers
---and contribute a 0x0 rect to `GetBoundsRect`. The secret-rect isolation that
---wrapper provides is preserved one level up instead — the bounds frame inherits
---a secret rect, and the component frame above it stays addon-owned because
---nothing anchors it to the bounds frame.
---@param name string  global frame name
---@param parent frame
---@return frame auraContainer
local function createContainer(name, parent)
    local container = LAC:CreateContainer(name, parent)
    container:SetUnit("player")
    container:SetEnabled(true)
    container:Show()
    return container
end

---Per-container sync signatures: container -> {groupKey -> "ids|layout" string}.
---Used to skip the engine-side SetAuraGroupCandidateFilters / SetAuraGroupLayout
---calls (both force a full candidate re-evaluation) when nothing changed —
---SyncGroup runs on every Refresh/ContentLayout pass, i.e. every anchor layout.
---@type table<frame, table<string, string>>
local groupSyncSigs = setmetatable({}, {__mode = "k"})

---Reused output of `widenToIdentitySets`.  Safe to reuse: Blizzard deep-copies
---every inbound options/filter table (`CopyAndValidateInboundTable` →
---`securecopy`, Blizzard_CustomAuraContainer.lua:225), so the engine never holds
---a reference to this one, and `syncGroup` consumes it before returning.
---@type table<number, true>
local widenScratch = {}

---Expand a tracker's spell map — one key per CDM ENTRY, its base spell — into
---the full set of ids that can actually MANIFEST as an aura.
---
---The map deliberately holds one key per entry, because a key is a display row
---(`CDMDataSource.getTrackedSpellMap`); a candidate filter is a set match, and
---the two are not the same thing.  Every other engine already widened at the
---filter: `syncSpellGroups` takes `idSetFor`, `syncSlots` takes it too, and both
---aura trackers' slot paths pass `GetAuraIdentitySet`.  The PLAIN group was the
---one that did not, and it had no hook to pass one through.
---
---**It is the default engine for `AuraBarTracker`, which has no per-spell groups
---at all** (slots are opt-in through `always_show_tracked`), so
---without this a tracked bar whose displayed aura is a linked id — DK Outbreak
---77575 shown as Virulent Plague 191587, Evoker Fire Breath 357208 → 357209 —
---matches nothing and the row never appears. That is most of what a bar tracker
---tracks. Shipped broken in c9c8717 and caught in review.
---
---Widening cannot duplicate a row the way widening the MAP did: a plain group
---renders one button per live aura, and only one member of an entry's identity
---set is normally live.  Two genuinely concurrent members draw two buttons —
---exactly what the sibling-key map did — so this is no worse than before.
---@param spellIDMap table<number, true>  base-keyed tracked spells
---@param idSetFor (fun(spellID: number): table<number, true>|nil)|nil  the caller's widening; nil = CDMDataSource.GetAuraIdentitySet
---@return table<number, true>  the same table when nothing widens, else the reused scratch
local function widenToIdentitySets(spellIDMap, idSetFor)
    idSetFor = idSetFor or private.CDMDataSource.GetAuraIdentitySet
    local widened = nil
    for spellID in pairs(spellIDMap) do
        local idSet = idSetFor(spellID)
        if idSet then
            if not widened then
                widened = widenScratch
                wipe(widened)
                for id in pairs(spellIDMap) do widened[id] = true end
            end
            for id in pairs(idSet) do widened[id] = true end
        end
    end
    return widened or spellIDMap
end

---Serialize the sync inputs into a comparable signature string.
---@param spellIDMap table<number, true>
---@param layoutOpts table  flat table of number/boolean/string values
---@return string
local function computeGroupSig(spellIDMap, layoutOpts)
    local ids = {}
    for id in pairs(spellIDMap) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    local parts = { table.concat(ids, ",") }
    local keys = {}
    for k in pairs(layoutOpts) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    for i = 1, #keys do
        local k = keys[i]
        parts[#parts + 1] = k .. "=" .. tostring(layoutOpts[k])
    end
    return table.concat(parts, "|")
end

---Add a new aura group or update an existing one's spell list and layout.
---AddAuraGroup asserts that no group with groupKey exists; HasAuraGroup guards so
---callers can call SyncGroup idempotently on each Refresh.  Unchanged inputs
---(same spell set and layout) skip the engine calls entirely.
---
---maxFrameCount is math.huge (unbounded).  It IS updatable
---(`SetAuraGroupMaxFrameCount`, Blizzard_CustomAuraContainer.lua:366), but
---there is nothing to update it to: the count we could derive is the tracked
---spell count, not the live visible count, which is secret.  Blizzard
---allocates frames on demand in batches (AURA_FRAME_BATCH_SIZE), so an
---unbounded cap costs nothing up front.
---
---initFn is captured only at AddAuraGroup time; changing it requires a container
---rebuild (create a new container with a new name).
---
---@param container frame
---@param groupKey string
---@param filter string  AuraUtil filter string, e.g. "HELPFUL"
---@param spellIDMap table<number, true>  candidateFilters.includeSpellIDs
---@param initFn function|nil  initializeFrame closure; only used on the first call
---@param layoutOpts table  group layout options (elementWidth/Height, elementSpacing, lineSpacing etc.)
---@param idSetFor (fun(spellID: number): table<number, true>|nil)|nil  per-tracker widening (a by-name custom aura's ids); nil = CDMDataSource.GetAuraIdentitySet
local function syncGroup(container, groupKey, filter, spellIDMap, initFn, layoutOpts, idSetFor)
    setContainerDemand(container, groupKey, next(spellIDMap) ~= nil)
    spellIDMap = widenToIdentitySets(spellIDMap, idSetFor)
    local sigs = groupSyncSigs[container]
    if not sigs then
        sigs = {}
        groupSyncSigs[container] = sigs
    end
    local sig = computeGroupSig(spellIDMap, layoutOpts)

    if container:HasAuraGroup(groupKey) then
        if sigs[groupKey] == sig then return end
        sigs[groupKey] = sig
        container:SetAuraGroupCandidateFilters(groupKey, { includeSpellIDs = spellIDMap })
        container:SetAuraGroupLayout(groupKey, layoutOpts)
    else
        sigs[groupKey] = sig
        container:AddAuraGroup(groupKey, filter, {
            maxFrameCount    = math.huge,
            sortMethod       = LAC.SortMethod.Default,
            sortDirection    = LAC.SortDirection.Normal,
            candidateFilters = { includeSpellIDs = spellIDMap },
            initializeFrame  = initFn,
            layout           = layoutOpts,
        })
    end
end

-- ---------------------------------------------------------------------------
-- Per-spell groups engine (compacting AND identity-bearing)
-- ---------------------------------------------------------------------------
--
-- The third engine, and the only one that has both properties at once.
--
-- A normal group holds every tracked spell, so Blizzard decides which button
-- shows which aura and that binding is SECRET — no spellID to key per-spell
-- state by (icon_overrides, active_glow, proc_glow, spell_colors).  Slots give
-- identity but cannot compact: a slot button's shown state is secret, so we can
-- never know which cells to close up.
--
-- One group PER SPELL escapes both horns.  The group's candidateFilters hold
-- exactly one spell's identity set, so any button it acquires can only be
-- showing that spell — identity, from the filter rather than from a read.  And
-- compaction still comes from Blizzard: an inactive spell's group is simply
-- empty, and empty groups are skipped by the flow layout.  Blizzard's own
-- comment on the option (`AnchorUtil.lua:615`): "Empty groups do not contribute
-- spacing or force a new line", enforced by the `#elements > 0` guard in the
-- group loop (`:692`).
--
-- Ordering is ours too, which a single group never allowed:
-- `RebuildLayoutGroups` sorts descriptions by `layoutIndex` then registration
-- order (`Blizzard_CustomAuraContainer.lua:596-632`), and `layoutIndex` is a
-- validated group layout option (`:174`).
--
-- What it does NOT recover: anything needing the container's own geometry.
-- Blizzard still runs the flow and the resulting rect is still secret, so the
-- layout-shaped gaps (per-line centering of a partial row, overflow_icon_size,
-- the fixed_width* modes, content-hugging width) stay slots-only.
--
-- Source-derived, and shipping disabled means ordinary play never reaches it.
-- Two things to watch: that
-- N single-frame groups cost no more than one N-frame group (each group owns a
-- frame provider), and that icon spacing really does come from `groupSpacing` —
-- `elementSpacing` sits BETWEEN elements of one group and so never applies when
-- every group holds one element.

---Spacing key rewrite for the per-spell engine: with one element per group there
---is never an intra-group gap, so the caller's `elementSpacing` has to become
---`groupSpacing` or every icon renders flush.  Reused buffer — syncSpellGroups
---consumes it synchronously before returning.
local spellGroupLayout = {}

---Point a container at ONE AURA GROUP PER SPELL.
---
---Groups are allocated once per spellID and repointed thereafter, exactly like
---the slot pool: keys are stable (`<prefix>_s<spellID>`) and a spell that leaves
---the map takes the never-matching filter rather than being removed, since
---neither engine has a public removal API.
---
---Combat contract: callers bail under lockdown for the LAYOUT half of this —
---not for the filters. `SetAuraGroupCandidateFilters` carries no combat gate
---(`.context/api.md` "Aura rules"), so a re-filter alone would be legal in
---combat; the signature guard below exists because every such call ends in a
---full `UpdateAllAuras()`, not because it would be blocked.
---@param container frame
---@param keyPrefix string  group key prefix, unique per component
---@param filter string  AuraUtil filter string
---@param spellIDMap table<number, true>  the spells this container may show
---@param idSetFor (fun(spellID: number): table<number,true>|nil)|nil  widen one spell's filter to its full aura identity set
---@param initFor fun(spellID: number): function  build the initializeFrame closure for one spell
---@param layoutOpts table  group layout options; elementSpacing is rewritten to groupSpacing
---@param rank table<number, number>|nil  icon order from Util.BuildSpellOrderRank; nil = plain spellID order
local function syncSpellGroups(container, keyPrefix, filter, spellIDMap, idSetFor, initFor, layoutOpts, rank)
    setContainerDemand(container, keyPrefix, next(spellIDMap) ~= nil)
    local sigs = groupSyncSigs[container]
    if not sigs then
        sigs = {}
        groupSyncSigs[container] = sigs
    end

    wipe(spellGroupLayout)
    for k, v in pairs(layoutOpts) do spellGroupLayout[k] = v end
    spellGroupLayout.groupSpacing = layoutOpts.elementSpacing
    spellGroupLayout.elementSpacing = nil

    -- Deterministic layoutIndex: the flow order must not depend on pairs().
    -- This is the ONE compacting engine whose order is ours to set — the plain
    -- group hands its flow to AuraContainerSortMethod.Default.
    local ordered = {}
    for spellID in pairs(spellIDMap) do ordered[#ordered + 1] = spellID end
    private.Util.SortByOrderRank(ordered, rank)

    local wanted = {}
    for i = 1, #ordered do
        local spellID = ordered[i]
        local key = keyPrefix .. "_s" .. spellID
        wanted[key] = true
        local ids = (idSetFor and idSetFor(spellID)) or { [spellID] = true }
        spellGroupLayout.layoutIndex = i
        local sig = computeGroupSig(ids, spellGroupLayout)
        if container:HasAuraGroup(key) then
            if sigs[key] ~= sig then
                sigs[key] = sig
                container:SetAuraGroupCandidateFilters(key, { includeSpellIDs = ids })
                container:SetAuraGroupLayout(key, spellGroupLayout)
            end
        else
            sigs[key] = sig
            container:AddAuraGroup(key, filter, {
                -- ONE frame per group, not the math.huge default.  A group's
                -- candidate filter is the spell's whole identity set (base +
                -- override + linkedSpellIDs), so nothing stops two of those
                -- being active on the same unit at once -- and with no cap that
                -- renders one tracked entry as two icons and shifts everything
                -- after it.  AcquireFrames honours it directly
                -- (`math.min(auras:Size(), maxFrameCount)`,
                -- Blizzard_AuraContainerGroups.lua:212), which is what makes a
                -- per-spell group exactly as wide as a slot and `layoutIndex`
                -- therefore an exact position rather than a hint.
                maxFrameCount    = 1,
                sortMethod       = LAC.SortMethod.Default,
                sortDirection    = LAC.SortDirection.Normal,
                candidateFilters = { includeSpellIDs = ids },
                initializeFrame  = initFor(spellID),
                layout           = spellGroupLayout,
            })
        end
    end

    -- Neutralize groups for spells that left the map.  Keyed scan over our own
    -- signature table — `HasAuraGroup` is public but there is no enumerator.
    for key in pairs(sigs) do
        if not wanted[key] and key:find(keyPrefix .. "_s", 1, true) == 1
            and sigs[key] ~= "OFF" then
            sigs[key] = "OFF"
            container:SetAuraGroupCandidateFilters(key, { includeSpellIDs = {} })
        end
    end
end

-- ---------------------------------------------------------------------------
-- Slots engine (always-show)
-- ---------------------------------------------------------------------------
--
-- The second of the two AuraContainer engines.  Groups compact the SECRET
-- active set through Blizzard's flow layout; slots hold a STATIC grid, one
-- slot per tracked spell, laid out entirely by us — slot frames are excluded
-- from the container flow layout (GetFlowLayoutGroupDescriptions enumerates
-- aura GROUPS only), so Blizzard never positions them.  Neither engine can do
-- the other's job, which is why the trackers carry both and pick by
-- always_show_tracked.  Full design: patterns-auracontainer.md
-- "Always-show via slots".
--
-- Role split, forced by the button's aura-driven Show/Hide (ApplyVisibility
-- does SetShown(secretwrap(auraData ~= nil))): the caller's CHROME CELL — a
-- plain addon frame — carries the persistent icon/background/border/name, and
-- the slot button carries only the dynamic adornments (SetDurationCooldown,
-- SetDurationText, SetApplicationCount, SetDurationBar).  Anything created on
-- the button inherits the button's hide, which is right for adornments and
-- fatal for chrome.
--
-- The button is anchored to its cell inside initializeFrame, which the frame
-- provider runs BEFORE applying access restrictions (CreateFrame:
-- securecallfunction(initializeFrame, ...) then ApplyAccessRestrictions).  So
-- the anchor is always legal, and afterwards only the CELL is ever moved or
-- sized — the button follows for free and never needs a restricted geometry
-- call again.

---Per-container slot pool: how many slot indices have been allocated.
---Blizzard exposes HasAuraSlot only on the PRIVATE mixin
---(ManagedAuraContainerPrivateMixin:HasAuraSlot) — unlike HasAuraGroup, which
---CustomAuraContainerSharedMixin re-exports — so allocation has to be tracked
---addon-side.
---@type table<frame, number>
local slotCounts = setmetatable({}, {__mode = "k"})

---Last synced spell order per container.  Every SetAuraSlotCandidateFilters
---call ends in UpdateAllAuras(), so an unguarded sync would run N full aura
---re-evaluations on every Refresh (combat transitions, CDM changes) for an
---unchanged list.  Same reason groupSyncSigs exists for the groups engine.
---@type table<frame, string>
local slotSyncSigs = setmetatable({}, {__mode = "k"})

---Never-matching candidate filter: DoesAuraPassCandidateFilters fails any aura
---against a non-nil includeSpellIDs that lacks its spellId, so an EMPTY map
---matches nothing.  That is how a surplus slot — and the idle engine during a
---mode switch — is switched off without a removal API (there is no public
---RemoveAuraSlot / RemoveAuraGroup).
local NO_MATCH = {}

-- ---------------------------------------------------------------------------
-- Per-spell unit scope
-- ---------------------------------------------------------------------------

---Which of the three aura groups a tracked spell is allowed into.
---
---A container has exactly ONE unit, so a tracker runs three groups: player
---HELPFUL, target HARMFUL, target HELPFUL.  This is the per-spell restriction
---("this one is only ever a self-buff / only ever lands on the target"); the
---SELF-TARGET duplicate is a separate, automatic mechanism — see
---`targetHelpfulContainer` in Core/AuraBarTracker.lua.
---  * `"player"` → player HELPFUL only
---  * `"target"` → target HARMFUL + target HELPFUL
---  * `"both"` (default, nil) → all three
---Expand a per-spell scope map across each entry's full aura identity set.
---
---The profile stores the scope against the spell the USER picked (a CDM base
---id), but the map the engines actually walk is widened to every entry's
---`overrideSpellID` + `linkedSpellIDs` — the displayed aura is usually a linked
---id, not the base.  Without this, scoping a spell to "player" would leave its
---linked ids at the default and they would still populate all three groups.
---Returns the input untouched when there is nothing to expand.
---@param scopeMap table<number, string>|nil  profile `aura_unit`, keyed by base spellID
---@return table<number, string>|nil
local function expandUnitScope(scopeMap)
    if not scopeMap or not next(scopeMap) then return scopeMap end
    local expanded = {}
    for baseID, scope in pairs(scopeMap) do
        expanded[baseID] = scope
        local idSet = private.CDMDataSource.GetAuraIdentitySet(baseID)
        if idSet then
            for linkedID in pairs(idSet) do expanded[linkedID] = scope end
        end
    end
    return expanded
end

---@param spellMap table<number, true>  the tracker's full tracked set
---@param scopeMap table<number, string>|nil  EXPANDED `aura_unit` (see expandUnitScope); absent keys default to "both"
---@return table<number, true> playerHelpful, table<number, true> targetHarmful, table<number, true> targetHelpful
local function splitByUnitScope(spellMap, scopeMap)
    local playerHelpful, targetHarmful, targetHelpful = {}, {}, {}
    for spellID in pairs(spellMap) do
        local scope = scopeMap and scopeMap[spellID] or "both"
        if scope ~= "target" then playerHelpful[spellID] = true end
        if scope ~= "player" then
            targetHarmful[spellID] = true
            targetHelpful[spellID] = true
        end
    end
    return playerHelpful, targetHarmful, targetHelpful
end

---Does `spellID` belong in the slot fed by `filter`?  The slots-engine twin of
---`splitByUnitScope` — slots are allocated per (spell, filter) pair, so the
---scope has to be resolved per filter rather than per map.
---@param scopeMap table<number, string>|nil
---@param spellID number
---@param isTargetContainer boolean  true for either of the two target-unit containers
---@return boolean
local function unitScopeAllowsSlot(scopeMap, spellID, isTargetContainer)
    local scope = scopeMap and scopeMap[spellID] or "both"
    if isTargetContainer then return scope ~= "player" end
    return scope ~= "target"
end

---Point a container's aura slots at an ordered spell list.
---
---Slots are a retargetable pool, not a per-map-change rebuild: keys are
---allocated once and repointed via SetAuraSlotCandidateFilters.  Surplus slots
---take the never-matching filter; their cells are simply left out of the
---caller's layout.  One slot is allocated per (spell, filter) pair, which is
---what lets a single cell serve BuffTracker's target section — a tracked
---target spell may land as either a debuff or an ally buff, and only one of
---the two filters can ever match at a time, so both slot buttons sit on the
---same cell and at most one is ever shown.
---
---Combat contract: the container calls are restricted like every other
---AuraContainer API, so callers must already bail under lockdown.
---@param container frame
---@param filters string[]  AuraUtil filter strings, one slot per spell per entry
---@param spellIDs number[]  ordered tracked spells (empty = neutralize the engine)
---@param cellFor fun(index: number): frame  addon-owned chrome cell for grid position `index`
---@param initButton fun(button: frame, cell: frame, spellID: number)  create + bind adornments, anchor to cell
---@param idSetFor (fun(spellID: number, filterIndex: number): table<number,true>|nil)|nil  widen a slot's filter to a full aura identity set (override/linked ids); nil return keeps the single-ID filter, an EMPTY table neutralizes that one slot
---@param sigSalt string|nil  extra signature input, for caller state that changes what idSetFor returns without changing the spell list (the per-spell unit scope)
local function syncSlots(container, filters, spellIDs, cellFor, initButton, idSetFor, sigSalt)
    -- The signature is over the BASE ids only: idSetFor is a pure function of
    -- the base id and the CDM data behind it, and a CDM change invalidates the
    -- whole tracked list (hence the base list) anyway.  `sigSalt` is the escape
    -- hatch for inputs that break that purity — the unit scope is per-spell
    -- profile config, so it can change with the list untouched and would
    -- otherwise be skipped here.
    setContainerDemand(container, "slots", #spellIDs > 0)
    local sig = table.concat(spellIDs, ",") .. "|" .. (sigSalt or "")
    if slotSyncSigs[container] == sig then return end
    slotSyncSigs[container] = sig

    local allocated = slotCounts[container] or 0
    local want = #spellIDs
    for i = 1, math.max(want, allocated) do
        for f = 1, #filters do
            -- Resolved per FILTER, not per spell: one cell carries a slot for
            -- each filter, and the unit scope can admit a spell to one of them
            -- while neutralizing another (unitScopeAllowsSlot).
            local ids = NO_MATCH
            if i <= want then
                ids = (idSetFor and idSetFor(spellIDs[i], f)) or { [spellIDs[i]] = true }
            end
            local key = "cue_slot_" .. f .. "_" .. i
            if i <= allocated then
                container:SetAuraSlotCandidateFilters(key, { includeSpellIDs = ids })
            else
                local cell = cellFor(i)
                local spellID = spellIDs[i]
                container:AddAuraSlot(key, filters[f], {
                    candidateFilters = { includeSpellIDs = ids },
                    initializeFrame  = function(button)
                        initButton(button, cell, spellID)
                    end,
                })
            end
        end
    end
    if want > allocated then
        slotCounts[container] = want
    end
end

-- ---------------------------------------------------------------------------
-- Per-button tooltip configuration
-- ---------------------------------------------------------------------------

---Our tooltip_anchor values mapped onto the button's anchor point names
---(validAnchorPointNames, Blizzard_AuraButton.lua:36).  "DEFAULT" keeps the
---template's own ANCHOR_BOTTOMLEFT (Blizzard_AuraButton.xml KeyValues).
local TOOLTIP_ANCHORS = {
    DEFAULT = "ANCHOR_BOTTOMLEFT",
    CURSOR = "ANCHOR_CURSOR",
    RIGHT = "ANCHOR_RIGHT",
    TOP = "ANCHOR_TOP",
}

---Map tooltip_mode / tooltip_anchor onto the aura button's OWN tooltip.
---
---Deliberately NOT routed through Core/UI/Tooltip.lua: the button already owns a
---tooltip (intrinsic <OnEnter>/<OnLeave> → ShowTooltip, Blizzard_AuraButton.xml:27)
---and it is on by default, so the job is configuring it rather than adding one.
---It is also the only workable route under groups, where the button's aura
---identity is secret and a SetSpellByID tooltip would have nothing to key on.
---
---`out_of_combat` needs no combat callbacks — unlike the Tooltip module's
---EnableMouse formula, SetHideTooltipInCombat is re-evaluated per show inside
---ShouldShowTooltip (:181).  So the Tooltip module's "single source of truth for
---EnableMouse" rule does not extend to aura buttons.
---
---Call only where the button is not access-restricted: inside initializeFrame
---(the provider restricts afterwards) or while auras are not secret.  That is
---exactly the restyleFn contract, which is why every caller is a restyleFn —
---and why a pooled button cannot inherit a previous occupant's mouse state, as
---all buttons of one component share these settings.
---@param button frame
---@param settings table
local function applyTooltip(button, settings)
    local mode = settings.tooltip_mode or "off"
    button:SetMouseMotionEnabled(mode ~= "off")
    button:SetHideTooltipInCombat(mode == "out_of_combat")
    button:SetTooltipAnchorPoint(
        TOOLTIP_ANCHORS[settings.tooltip_anchor or "RIGHT"] or "ANCHOR_RIGHT", 0, 0)
end

-- ---------------------------------------------------------------------------
-- Active-aura glow
-- ---------------------------------------------------------------------------

---Apply `active_glow` to one button's bound border.
---
---The border is a region in the BUTTON's subtree, so the engine's aura-driven
---show/hide is the glow's on/off — there is no aura state to read here, and no
---per-refresh pass to run.  This only switches the FEATURE, which is why it
---lives on the restyle path (acquire, re-bind, settings change) rather than in
---a sync.
---
---That binding is what makes this work under BOTH engines and while auras are
---secret, and what lets a CUSTOM spell glow at all: the predecessor asked
---`CDMDataSource.GetAuraState`, which read a CDM viewer child and therefore
---reported `false` for every spell without one.  That function no longer exists —
---this was the first of its consumers to be re-sourced, and the pattern it set
---(bind a region into the aura button's subtree, let the engine drive it) is what
---eventually closed the last one.
---@param button frame
---@param settings table  component settings, read for active_glow/_color
local function applyActiveGlow(button, settings)
    local on = settings.active_glow == true
    local border = button.cue_ActiveGlow
    if not border then
        -- Built here rather than in an initializeFrame: five different init
        -- paths bind aura buttons (icon/bar x slots/groups, plus the icon
        -- tracker's own), and duplicating the construction in each is what left
        -- three of them without a border at all.  Every caller of this is a
        -- restyle, which runs in the same writable window an init does.
        if not on then return end
        border = private.GlowEffect.CreateActiveBorder(button)
        button.cue_ActiveGlow = border
    end
    border:SetShown(on)
    if on then
        private.GlowEffect.ApplyActiveBorderColor(border, settings.active_glow_color)
    end
end

---Show or hide the CDM `OnAuraApplied` **Visual** alert on one aura button.
---
---The overlay lives in the BUTTON's subtree, so the engine's aura-driven
---show/hide IS the alert's fire and release — the same trick `applyActiveGlow`
---uses, and the only route to an aura-event visual under the 12.1 lockdown,
---where nothing reports an aura application to Lua.
---
---Engine-agnostic, unlike `syncProcGlow` below: that one needs an unrestricted
---CELL for LibCustomGlow, while this lives in the button's own subtree.  All the
---caller has to supply is which spell the button holds — slots know it from the
---cell map, per-spell groups from the `cue_spellID` their candidate filter lets
---`makeInit` stamp.  Only the plain groups engine cannot answer it, and there the
---caller passes nil.
---
---One frame per SHAPE, created lazily and kept: the two shapes need different
---animations (a flipbook vs an alpha bounce), so switching type by rebuilding one
---frame's AnimationGroup would be strictly more code than holding both. Only a
---spell that actually has a visual alert configured ever builds either.
---@param button frame
---@param visualAlertType number|nil  an Enum.VisualAlertType value; nil hides
---@param iconWidth number|nil  button width, so the overlay's overhang scales with the icon the way Blizzard's does
local function applyCdmAlertGlow(button, visualAlertType, iconWidth)
    local art = visualAlertType and private.GlowEffect.GetCdmAlertArt(visualAlertType) or nil
    local wantAnts = art ~= nil and art.shape == "ants"
    local wantFlash = art ~= nil and art.shape == "flash"
    if wantAnts and not button.cue_CdmAlertAnts then
        button.cue_CdmAlertAnts = private.GlowEffect.CreateCdmAlertGlow(button, "ants")
    elseif wantFlash and not button.cue_CdmAlertFlash then
        button.cue_CdmAlertFlash = private.GlowEffect.CreateCdmAlertGlow(button, "flash")
    end
    if button.cue_CdmAlertAnts then button.cue_CdmAlertAnts:SetShown(wantAnts) end
    if button.cue_CdmAlertFlash then button.cue_CdmAlertFlash:SetShown(wantFlash) end
    if art then
        local overlay = wantAnts and button.cue_CdmAlertAnts or button.cue_CdmAlertFlash
        -- Re-anchored on every show: the overlay is created once and outlives any
        -- number of icon_size edits, which resize the button from the restyle
        -- pass without telling this one.
        private.GlowEffect.AnchorCdmAlertGlow(overlay, button, iconWidth)
        private.GlowEffect.ApplyCdmAlertGlowColor(overlay, art.color)
    end
end

---Drive `proc_glow_*` over one section of a slots grid.  Same shape and same
---constraints as the cell-based glows before it: it rides the unrestricted
---chrome CELL, and every pooled cell is walked so surplus cells and the idle
---groups engine (short or empty `list`) get their glow stopped.
---
---Needs no CDM bridge — `IsSpellOverlayed` answers from the spell ID alone —
---but it IS slots-only, unlike `applyActiveGlow` above: a proc is a property of
---the spell rather than of a live aura, so there is nothing on the button for
---the engine to bind it to, and under groups the button↔spell identity is
---secret.
---Queried by OUR spell ID rather than the event payload, which carries the
---*overlayed* ID and diverges under an override — the same derivation
---`IconTracker.applyProcGlow` uses.
---@param cells frame[]
---@param list number[]
---@param enabled boolean
---@param settings table
local function syncProcGlow(cells, list, enabled, settings)
    local style = settings.proc_glow_style or "blizzard"
    for i = 1, #cells do
        local spellID = enabled and list[i]
        -- Ask about the ACTIVE id as well as the CDM key.  A spec that replaces
        -- a tracked spell carries the overlay under the replacement's id, so a
        -- base-only query never lights it -- `Core/IconTracker.lua`'s
        -- `applyProcGlow` has always asked about both and this twin did not, so
        -- an overridden tracked buff simply never glowed.  Blizzard asks about
        -- the resolved id alone (`RefreshOverlayGlow` -> `GetSpellID`,
        -- CooldownViewerItemData.lua:216); we ask about both, because our button
        -- draws the override's art while the action slot still holds the base and
        -- either can carry the overlay.
        --
        -- No item-backed guard here, unlike the icon twin: a synthetic key never
        -- reaches an aura tracker's map (`getTrackedSpellMap` hands those out to
        -- cooldown-driven callers only), so every id in `list` is a real spell.
        local activeSpellID = spellID and private.compat.GetOverrideSpell(spellID)
        if spellID and (C_SpellActivationOverlay.IsSpellOverlayed(spellID)
            or (activeSpellID and activeSpellID ~= spellID
                and C_SpellActivationOverlay.IsSpellOverlayed(activeSpellID))) then
            private.GlowEffect.StartProc(cells[i], style,
                settings.proc_glow_color or {1, 1, 1, 1},
                (settings.proc_glow_alpha or 100) / 100,
                settings.proc_glow_thickness or 2)
        else
            private.GlowEffect.StopProc(cells[i])
        end
    end
end

-- ---------------------------------------------------------------------------
-- Pandemic glow (native region, 12.1.0.69111+)
-- ---------------------------------------------------------------------------
--
-- `CustomAuraButtonSharedMixin:AddPandemicRegion(region)` hands Blizzard an
-- addon-owned Region whose SHOWN state the engine drives: `UpdatePandemicWindow`
-- derives the window from `C_UnitAuras.GetRefreshExtendedDuration` minus
-- `GetAuraBaseDuration` (the duration a refresh would carry over — the pandemic
-- window by definition) and an OnUpdate does `region:SetShown(inWindow)`.
--
-- That is the whole reason pandemic glow is implementable at all now.  Every
-- previous route needed a value 12.1 makes unreadable: the CDM child's
-- `auraInstanceID` → `GetAuraDuration` → a curve, which errors (or returns nil)
-- while auras are secret, so the AdditionalFrameManager implementation goes dark
-- in exactly the content where a pandemic cue matters.  Here nothing crosses
-- into Lua: we supply the region, the engine decides when it shows, and it keeps
-- deciding in combat, encounters, M+ and PvP.  It also needs no CDM viewer
-- child, so `pandemic_glow` is no longer a `needsViewerChildren()` consumer.
--
-- What the native region cannot do, and why some settings are inert here:
--   * the window is Blizzard's, so there is no threshold to gate on;
--   * there is no continuous remaining-%, so neither an alpha fade nor a
--     three-band urgency colour ramp can be evaluated.  The six profile keys
--     that fed them are gone; copies in older saved profiles are ignored.
-- The region is binary — shown inside the window, hidden outside it — so the
-- cue is a STATIC border: one colour, one alpha, no pulse.  There is nothing to
-- animate against (the window is the only signal, and it is on or off), and
-- nothing animated can run in this subtree anyway: LibCustomGlow parents pooled
-- frames to the target and scripts them, both blocked by the secret aspects
-- below.  Colour and thickness apply; `pandemic_glow_style` selects only which
-- side of the edge the border draws on.
--
-- The region is a plain HOST frame, never the styled overlay itself:
-- `AddPandemicRegion` puts `Enum.SecretAspect.Shown` on whatever it is given,
-- so the overlays keep a plain shown state of their own while the host's
-- engine-driven visibility cascades to them.
--
-- The secret aspect reaches the whole host subtree, which constrains what the
-- overlays may be built from: `SetScript` is blocked there ("Cannot assign
-- script handler for 'onshow' (blocked by secret aspects)"), so no overlay may
-- drive itself from OnShow — the sync pass is the only start trigger; and the
-- host inherits the aura container's secret rect, so no overlay may read its
-- own width (see `patterns-auracontainer.md`).
--
-- A Frame is a legal region by design, not by luck: every other bind on the
-- button names a concrete widget type (`RequireObjectType("StatusBar")`,
-- `"FontString"`, `"Texture"`, `"Cooldown"`) and only this one names the base
-- type `"Region"`, which `IsObjectType` answers true for on any Frame.
--
-- Host placement is the same role split as everything else on a slot button:
-- the host is a child of the BUTTON (a hard requirement —
-- `ValidateInboundScriptObject` errors unless the region is a descendant of its
-- owner), so it inherits the button's aura-driven hide.  That is correct here:
-- no aura, no pandemic window.
--
-- Registration is LAZY, and that is a performance decision rather than a
-- structural one.  A registered region makes the engine call
-- `GetRefreshExtendedDuration`/`GetAuraBaseDuration` on every aura update and
-- run a per-frame OnUpdate for the whole life of any refreshable aura
-- (`ShouldEnableOnUpdate` is keyed on the window EXISTING, not on being inside
-- it) — real work on every tracked aura, for a feature that defaults off on all
-- four trackers.  So the region is added on the first pass that wants it and
-- removed again when the setting goes off.  The only restriction on the button
-- is `DenyTaintedAccessWhenAurasAreSecret` (the frame provider's
-- `AccessRestrictionFlags`), the same one `RestyleIfDirty` waits out, so both
-- calls are legal from a refresh pass whenever auras are readable — and always
-- legal from `initializeFrame`, which runs before restrictions are applied.
-- Acquire-time registration is what covers the groups engine, where Blizzard
-- allocates buttons on demand and the next component Refresh may be far away.

---@class pandemic_entry
---@field button frame
---@field bar frame|nil  duration strip for the bar variant's overlay geometry
---@field host frame|nil  created on first enable
---@field regionKey number|frame|nil  RemovePandemicRegion argument while registered; nil when not

---Pandemic entries keyed by the chrome CELL their button rides, for the slots
---engine.  A target cell carries one button per filter, so this is a list.
---@type table<frame, pandemic_entry[]>
local pandemicByCell = setmetatable({}, {__mode = "k"})

local OFF_COLOR = {0, 0, 0, 0}
local DEFAULT_PANDEMIC_COLOR = {0.2, 0.8, 0.4, 1}

---Pandemic entries keyed by component, for the groups engine — where there is
---no cell and no button↔spell binding to key anything by.
---@type table<string, pandemic_entry[]>
local pandemicByComponent = {}

---Sync passes that had to be skipped because auras were secret, keyed by the
---section they were for.  Value is the argument list, re-run once auras are
---readable again.  See `schedulePandemicRetry` for why this is not left to the
---next natural Refresh.
---@type table<any, table>
local pandemicDeferred = {}
local pandemicRetryArmed = false

---Forward declarations (Lua 5.1 upvalue capture): the retry calls syncPandemic,
---which is defined below it and re-arms the retry.
local syncPandemic
local schedulePandemicRetry

---Re-run every deferred pass, or re-arm if auras are still secret.
local function drainDeferredPandemic()
    pandemicRetryArmed = false
    if not next(pandemicDeferred) then return end
    if C_Secrets.ShouldAurasBeSecret() then
        schedulePandemicRetry()
        return
    end
    local work = pandemicDeferred
    pandemicDeferred = {}
    for _, a in pairs(work) do
        syncPandemic(a[1], a[2], a[3], a[4], a[5])
    end
end

---Poll for the end of the secrecy window.
---
---There is no event for it: `C_Secrets` is query-only (no `SECRET*` event exists
---in the API docs), and secrecy is NOT bracketed by combat — it covers whole M+
---runs, encounters and PvP matches, so `OnLeaveCombat` fires repeatedly *inside*
---the window and cannot be the convergence point.  Leaving it to "the next
---natural Refresh" would mean a settings change made in a dungeon lands at some
---unpredictable later moment, or not until `/reload`.
---
---Cost is bounded to the deferral: the timer is armed only while a pass is
---actually outstanding and stops as soon as the queue drains.
schedulePandemicRetry = function()
    if pandemicRetryArmed then return end
    pandemicRetryArmed = true
    C_Timer.After(1, drainDeferredPandemic)
end

---Hand the entry's host region to the engine, creating it on first use.
---Caller owns the secrecy gate (see the section note).
---@param entry pandemic_entry
---@param settings table  read for the initial thickness/style
local function registerPandemic(entry, settings)
    if not entry.host then
        local host = CreateFrame("Frame", nil, entry.button)
        -- Anchored, and its art built, ENTIRELY before the hand-over — the
        -- order every other addon using this API follows.  Afterwards the
        -- engine owns the object: its shown state is not ours to read or set,
        -- and its anchors are not ours to rewrite, so `pandemic_glow_style`
        -- offsets the edge TEXTURES rather than the region (GlowEffect).
        host:SetAllPoints(entry.bar or entry.button)
        private.GlowEffect.ApplyEdgeBorder(host,
            settings.pandemic_glow_style ~= "border_inside",
            settings.pandemic_glow_thickness or 2, OFF_COLOR)
        entry.host = host
    end
    -- 12.1.0 returns an index and RemovePandemicRegion takes it; 12.1.5 and
    -- Forever 1.60.1 return nothing, take the region itself, and assert on a
    -- second add of the same region — so the key must mark "registered" on both.
    entry.regionKey = entry.button:AddPandemicRegion(entry.host) or entry.host
end

---Record an aura button as a pandemic-glow carrier, and register it right away
---when the feature is already on.  Call from `initializeFrame`.
---
---Pass `componentName` for a groups-engine button and `cell` for a slots-engine
---one; the two registries are disjoint because a button is created by exactly
---one of the two init paths.
---@param button frame
---@param settings table  component settings, read for the initial pandemic_glow state
---@param componentName string|nil
---@param cell frame|nil
---@param barFrame frame|nil
local function attachPandemic(button, settings, componentName, cell, barFrame)
    -- Build guard, not a defensive existence check: the mixin method landed in
    -- 12.1.0.69111, while the 12.1 floor this whole module already enforces
    -- (CustomAuraContainerTemplate) goes back further.  With no entry recorded,
    -- syncPandemic finds nothing and the feature is silently absent on an older
    -- 12.1 build rather than erroring out of every refresh pass.
    if not button.AddPandemicRegion then return end
    local entry = { button = button, bar = barFrame }
    if cell then
        local list = pandemicByCell[cell]
        if not list then
            list = {}
            pandemicByCell[cell] = list
        end
        list[#list + 1] = entry
    elseif componentName then
        local list = pandemicByComponent[componentName]
        if not list then
            list = {}
            pandemicByComponent[componentName] = list
        end
        list[#list + 1] = entry
    end
    -- No secrecy gate: initializeFrame runs before the provider applies access
    -- restrictions, so this is legal even mid-combat.  The per-spell excludes
    -- are not applied here — the following sync pass owns them.
    --
    -- Only the REGISTRATION happens here, not the overlay build: a button
    -- acquired while auras are secret therefore carries a live region with
    -- nothing drawn in it until the first readable sync pass styles it.  That
    -- window is narrow in practice (the provider allocates a batch of buttons
    -- up front, out of secrecy, and those are already styled) and it self-heals
    -- through the deferred-sync drain, so it does not justify running the
    -- overlay constructors inside initializeFrame.
    if settings.pandemic_glow == true then
        registerPandemic(entry, settings)
    end
end

---Style one entry's overlay, register or unregister its region to match, or
---hide every overlay it has when the feature is off for it.
---Caller MUST have checked `C_Secrets.ShouldAurasBeSecret()` — every frame this
---touches lives inside the aura button's subtree, which is off limits while auras
---are secret (see the section note).  syncPandemic owns that gate so it is paid
---once per pass rather than once per entry.
---@param entry pandemic_entry
---@param on boolean
---@param settings table
local function applyPandemicEntry(entry, on, settings)
    if on ~= (entry.regionKey ~= nil) then
        if on then
            registerPandemic(entry, settings)
        else
            entry.button:RemovePandemicRegion(entry.regionKey)
            entry.regionKey = nil
        end
    end
    local host = entry.host
    if not host then return end

    -- The border is drawn on the HOST — the object handed to AddPandemicRegion —
    -- so the engine's SetShown drives the pixels directly.  It used to hang two
    -- frames deeper (host -> overlay -> border), which put two addon-owned shown
    -- states in the way that nothing in this subtree can read back.
    --
    -- Not registered means not shown, and an unregistered host keeps whatever
    -- shown state the engine last wrote (RemovePandemicRegion drops it from the
    -- iteration without hiding it) while still carrying SecretAspect.Shown.  So
    -- "off" is a transparent edge rather than a Hide.
    local c = OFF_COLOR
    if on and entry.regionKey then
        c = settings.pandemic_glow_color or DEFAULT_PANDEMIC_COLOR
    end
    private.GlowEffect.ApplyEdgeBorder(host,
        settings.pandemic_glow_style ~= "border_inside",
        settings.pandemic_glow_thickness or 2, c)
end

---Drive `pandemic_glow` across one tracker.
---
---SLOTS: pass the chrome cells and the index-aligned spell list; every pooled
---cell is walked, so a surplus cell and the idle engine (short or empty `list`)
---get their overlays hidden, and `pandemic_glow_excludes` is honoured per spell.
---
---GROUPS: pass nil for both.  The feature still works — the engine drives the
---region either way.  A per-spell group's button carries its spell
---(`cue_spellID`, stamped by makeInit from the group's candidate filter — no
---read of the secret binding), so `pandemic_glow_excludes` is honoured there
---too, as it was on every tracker before the aura-container rework.  A
---plain-group button (AuraBarTracker, which has no per-spell engine yet) has
---none and follows the tracker-wide setting.
---
---**Skipped wholesale while auras are secret.** `DenyTaintedAccessWhenAurasAreSecret`
---on the button cascades to its child regions — including ones we created before
---the restriction was applied, since it is on the object rather than the
---reference path (live-verified, `patterns-secrets.md`) — so every register,
---every overlay creation and every `SetAlpha`/`Show`/`IsShown` below would be a
---tainted access into a forbidden subtree.  That window is NOT combat: it covers
---whole dungeon runs, raid encounters and PvP matches, and the buff trackers'
---own `InCombatLockdown()` early-return does not cover the out-of-combat half of
---it.  The pass is queued and retried instead of dropped.
---@param componentName string
---@param cells frame[]|nil
---@param list number[]|nil
---@param enabled boolean
---@param settings table
syncPandemic = function(componentName, cells, list, enabled, settings)
    -- Keyed by section, so a later real Refresh supersedes a queued pass rather
    -- than stacking behind it.  `cells`, `list` and `settings` are live tables,
    -- so a retry re-reads current content; only `enabled` is a snapshot, and any
    -- real Refresh overwrites it.
    if C_Secrets.ShouldAurasBeSecret() then
        pandemicDeferred[cells or componentName] =
            { componentName, cells, list, enabled, settings }
        schedulePandemicRetry()
        return
    end
    pandemicDeferred[cells or componentName] = nil

    if cells then
        local excludes = enabled and settings.pandemic_glow_excludes
        for i = 1, #cells do
            local entries = pandemicByCell[cells[i]]
            if entries then
                local spellID = enabled and list and list[i]
                local on = (spellID ~= nil and spellID ~= false and spellID ~= 0)
                -- Identity match: the exclude list is keyed by the id the picker
                -- offered, this slot by whichever identity member it tracks.
                if on and private.Util.BaseOrOverrideInList(spellID, excludes) then
                    on = false
                end
                for e = 1, #entries do
                    applyPandemicEntry(entries[e], on, settings)
                end
            end
        end
        return
    end

    local entries = pandemicByComponent[componentName]
    if not entries then return end
    local excludes = enabled and settings.pandemic_glow_excludes
    for e = 1, #entries do
        local on = enabled
        local spellID = on and entries[e].button.cue_spellID
        if spellID and private.Util.BaseOrOverrideInList(spellID, excludes) then
            on = false
        end
        applyPandemicEntry(entries[e], on, settings)
    end
end

---Raised child frame to host an aura button's own text.
---
---The icon border (`Util.ApplyIconBorder`), the active-aura border and the
---duration Cooldown are all child FRAMES of the button, so a FontString created
---on the button itself draws UNDERNEATH them whatever its draw layer -- a
---cross-frame ordering `SetDrawLayer("OVERLAY", n)` cannot reach.  Same shape as
---`IconTracker`'s `textOverlay`.
---
---Safe on a forbidden button: nothing in `Blizzard_AuraContainer/` ever adds
---`Enum.SecretAspect.FrameLevel`, so `GetFrameLevel` returns a plain number, and
---`initializeFrame` runs before access restrictions are applied anyway.  A
---FontString created here is still an indirect DESCENDANT of the button, which is
---all `AuraContainerUtil.ValidateInboundScriptObject` requires -- the bound
---`cue_Timer` already lives one level down, on `cue_Cooldown`.
---@param button frame  an aura slot/group button, from inside initializeFrame
---@return frame
local function createTextLayer(button)
    local layer = CreateFrame("Frame", nil, button)
    layer:SetAllPoints(button)
    layer:SetFrameLevel(button:GetFrameLevel() + 10)
    return layer
end

-- Blizzard's `CustomAuraContainerConstants.FrameCreationBatchSize`
-- (Blizzard_AuraContainerShared.lua:105, 10 on 12.1.0 / 12.1.5 / Forever).
-- Hardcoded because that table lives in the AuraContainer's secure environment
-- and is not among the tables it copies out to addons (`:254-273`): reading it
-- from addon code yields nil (confirmed in a client, 2026-10-07).
local AURA_FRAME_BATCH_SIZE = 10

---Create an initializeFrame closure for a tracker component.
---
---The returned function is passed to AddAuraGroup as initializeFrame.
---It fires ONCE per button at acquire time (not on every aura update or refresh).
---Buttons are pooled by Blizzard and reused — use the dirty-flag restyle path
---(RegisterTracker + MarkDirty + RestyleIfDirty) to update already-acquired buttons.
---
---All regions created here MUST be children of `button` AND anchored to `button`
---to pass GetValidatedForbiddenObjectTable's forbidden-aspect inheritance checks.
---
---All three creation calls are live-verified by the shipped aura taps —
---`button:CreateFontString` and `CreateFrame("StatusBar", nil, button)` in
---`ensureEbonMightTap` (Components/PrimaryResources.lua), `CreateFontString` in
---SecondaryResources' `auraTap`.  Those are slot buttons, but slot and group
---buttons come from the same `CreateCustomFrameProvider` with the same
---`CustomAuraButtonTemplate`, so the aspect checks are the same code path.
---
---@param componentName string  used to track buttons in the dirty-flag registry
---@param getSettingsFn fun():table  returns current component settings; called at acquire time for initial styling
---@param spellID number|nil  the one spell this group can show; stamps `cue_spellID` and suppresses the SetIcon bind
---@param singleFrame boolean|nil  the group holds at most one frame (`maxFrameCount = 1`), so only the batch's last frame is built -- see the note at the top of the closure
---@return function  initializeFrame closure
local function makeInit(componentName, getSettingsFn, spellID, singleFrame)
    local created = 0
    return function(button)
        -- Pooled SPARE: created to pad the batch, and on a single-frame group it
        -- can never be acquired, so building it is pure waste.  Skipped work is
        -- everything below -- icon, text layer, count, cooldown, timer, glow,
        -- pandemic carrier -- plus the registry entry, which is the bigger win:
        -- `ForEachTrackedButton` and `RestyleIfDirty` walk the registry on every
        -- pass, so a spare would also be re-styled on every settings change.
        --
        -- Which frame survives is not a guess.  `AddAuraGroup` hard-codes
        -- `batchSize = CustomAuraContainerConstants.FrameCreationBatchSize`
        -- (Blizzard_CustomAuraContainer.lua:292, mirrored as
        -- AURA_FRAME_BATCH_SIZE) and creates the whole batch up-front;
        -- `AcquireFrame` then pops with `table.remove(availableFrames)`
        -- -- the LAST created (Blizzard_AuraContainerFrameProviders.lua:107).
        -- `ReleaseFrame` appends (`:127`) and `ReleaseAllFrames` rebuilds in
        -- ownedFrames order, so the same last frame cycles forever.  Hence "the
        -- last of each batch".
        --
        -- Only ever passed by `syncSpellGroups`, the one caller that sets
        -- `maxFrameCount = 1`.  A plain group takes math.huge and grows into the
        -- batch from the end, so it must build them all.
        --
        -- This does NOT weaken the batch's purpose. Blizzard pads to 10 to
        -- "obfuscate the number of auras as this invokes initialization
        -- callbacks" (Blizzard_AuraContainerShared.lua:103) -- the callback still
        -- fires ten times and still tells us nothing, because the count is fixed
        -- whatever the auras are doing.
        --
        -- If Blizzard ever pops from the front instead, or changes the batch
        -- size, the symptom is every icon on the compacting engine rendering
        -- blank. That is the thing to check first if that is ever reported.
        if singleFrame then
            created = created + 1
            if created % AURA_FRAME_BATCH_SIZE ~= 0 then
                -- Sized anyway: one cheap call, and an unsized frame has no rect
                -- at all, which is a stranger object to leave in a Blizzard pool
                -- than a blank one.
                local spareSettings = getSettingsFn()
                local spareSize = spareSettings.icon_size or 40
                button:SetSize(spareSize,
                    (spareSettings.icon_height and spareSettings.icon_height > 0)
                        and math.floor(spareSettings.icon_height) or spareSize)
                return
            end
        end
        -- REQUIRED: size the button here. The engine flow layout positions
        -- buttons at ONE anchor point and uses their NATURAL size
        -- (ApplyElementLayout: "Width and height are ignored... the element's
        -- natural size is used"); layout elementWidth/Height only advance the
        -- cursor. An unsized button has no rect and renders NOTHING.
        -- initializeFrame runs BEFORE access restrictions are applied
        -- (provider order), so SetSize here is always legal — Plater does the
        -- same (initAuraFrame → PixelUtil.SetSize).
        local initSettings = getSettingsFn()
        local iconSize = initSettings.icon_size or 40
        local iconHeight = (initSettings.icon_height and initSettings.icon_height > 0)
            and math.floor(initSettings.icon_height) or iconSize
        button:SetSize(iconSize, iconHeight)

        -- Icon texture: must be a child of button and anchored to button.
        -- Crop the baked-in icon border per the profile zoom settings (Plater
        -- sets its texcoord at init the same way; the engine's per-aura
        -- SetIconTextureForAura preserves it).
        button.cue_Icon = button:CreateTexture(nil, "ARTWORK")
        button.cue_Icon:SetAllPoints(button)
        button.cue_Icon:SetTexCoord(private.Util.GetIconZoomCoords(iconSize, iconHeight))
        if spellID then
            -- Per-spell groups: the button's spell is known from its group's
            -- candidate filter, so the ICON DECISION is ours.  The bind is not
            -- made here because it is conditional — an `icon_overrides` entry
            -- takes the texture back, and the bind is what would clobber it on
            -- every aura update.  restyleFn owns both directions (SetIcon /
            -- ClearIcon off `cue_spellID`) and runs at the tail of this closure,
            -- so a button is bound before it ever renders.
            button.cue_spellID = spellID
        else
            button:SetIcon(button.cue_Icon)
        end

        -- Stack count FontString: child of button, anchored to button corner.
        -- Font template is REQUIRED pre-bind: SetApplicationCount pushes text
        -- immediately and a font-less SetText errors "Font not set"
        -- (live-verified; restyleFn only re-fonts when stacks_font is set).
        button.cue_TextLayer = createTextLayer(button)
        button.cue_Count = button.cue_TextLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        button.cue_Count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        button:SetApplicationCount(button.cue_Count)

        -- Duration cooldown spiral: named for /fstack legibility.
        local bName = button:GetName()
        local cdName = bName and (bName .. "_CUE_CD") or nil
        button.cue_Cooldown = CreateFrame("Cooldown", cdName, button, "CooldownFrameTemplate")
        button.cue_Cooldown:SetAllPoints(button)
        -- Swipe before the bind, as Plater does: set only by restyleFn after it,
        -- hide_cd_swipe left the swipe drawing (reported 2026-09-28).  The edge
        -- goes with it; the slots engine's init already turns it off always.
        button.cue_Cooldown:SetDrawSwipe(initSettings.hide_cd_swipe ~= true)
        if initSettings.hide_cd_swipe == true then button.cue_Cooldown:SetDrawEdge(false) end
        button:SetDurationCooldown(button.cue_Cooldown)

        -- Timer text: first region of CooldownFrameTemplate is the countdown FontString.
        button.cue_Timer = button.cue_Cooldown:GetRegions()
        button:SetDurationText(button.cue_Timer, {})

        -- Active-aura border.  The button exists only while its aura does, so a
        -- border in its subtree IS the aura state — no viewer child, no Lua read,
        -- and it survives aura secrecy.  Created here for the same reason as the
        -- pandemic carrier: initializeFrame runs before access restrictions.
        applyActiveGlow(button, initSettings)

        -- Pandemic carrier.  Registering here (rather than waiting for the next
        -- sync pass) is what covers the groups engine, where Blizzard allocates
        -- buttons on demand and the next component Refresh may be far away.
        attachPandemic(button, initSettings, componentName)

        -- Register button in dirty-flag registry so OnProfileChanged can restyle.
        private.AuraContainer.TrackButton(componentName, button)

        -- Apply initial styling so buttons are correctly styled at acquire time
        -- (OnProfileChanged / restyleIfDirty only fires on subsequent settings changes).
        -- restyleFn must only touch addon-owned regions (cue_Icon, cue_Count,
        -- cue_Cooldown, etc.) — not secure-frame APIs — to avoid forbidden-object violations.
        local ts = trackerState[componentName]
        if ts and ts.restyleFn then
            ts.restyleFn(button, initSettings)
        end
    end
end

---Register a tracker component with the dirty-flag restyle system.
---Call during Initialize() for each component that creates an AuraContainer.
---@param componentName string
---@param restyleFn fun(button: frame, settings: table)  called on each tracked button when dirty
local function registerTracker(componentName, restyleFn)
    trackerState[componentName] = {
        restyleFn = restyleFn,
        buttons   = {},
        isDirty   = false,
    }
end

---Record an acquired button for a tracker component.
---Called from within the initializeFrame closure (componentName is a captured upvalue).
---@param componentName string
---@param button frame
local function trackButton(componentName, button)
    local state = trackerState[componentName]
    if not state then return end
    state.buttons[button] = true
end

---Walk every button a component has acquired, in either engine.
---
---The restyle registry is the only place slot buttons and group buttons are held
---together, and a consumer that must reach both (the CDM visual alert) would
---otherwise need a second registry per engine. Unlike `RestyleIfDirty` this does
---NOT gate on aura secrecy -- the caller decides, because not every per-button
---pass writes into the button's subtree.
---@param componentName string
---@param fn fun(button: frame)
local function forEachTrackedButton(componentName, fn)
    local state = trackerState[componentName]
    if not state then return end
    for button in pairs(state.buttons) do
        fn(button)
    end
end

---Mark a tracker's buttons as needing restyle on the next Refresh.
---Call when profile settings that affect button appearance (fonts, colors) change.
---@param componentName string
local function markDirty(componentName)
    local state = trackerState[componentName]
    if state then state.isDirty = true end
end

---Apply the restyle function to all tracked buttons if the tracker is dirty.
---Call from the component's Refresh() after any settings-change guard check.
---Clears the dirty flag; a no-op when the tracker is not dirty.
---@param componentName string
---@param settings table  current component settings passed to restyleFn
local function restyleIfDirty(componentName, settings)
    local state = trackerState[componentName]
    if not state or not state.isDirty then return end
    -- Buttons are tainted-locked while auras are secret
    -- (DenyTaintedAccessWhenAurasAreSecret): SetSize/SetFont on them throws the
    -- forbidden-object error (live: Plater's reSkinAuraButtons → DF SetFontSize
    -- → "calling 'GetFont' on bad self"), which would abort the calling Refresh
    -- mid-layout. Keep the dirty flag; the next Refresh out of secrecy applies.
    -- (makeInit's initial restyle is exempt: initializeFrame runs BEFORE the
    -- provider applies access restrictions.)
    if C_Secrets.ShouldAurasBeSecret() then return end
    state.isDirty = false
    for button in pairs(state.buttons) do
        state.restyleFn(button, settings)
    end
end

-- Mark all registered trackers dirty on profile change so the next component
-- Refresh() picks up updated fonts, colors, and other per-button settings.
private.Callback.Register("OnProfileChanged", function()
    for name in pairs(trackerState) do
        markDirty(name)
    end
end)

---@type auracontainerfacade
private.AuraContainer = {
    Create = create,
    CreateContainer = createContainer,
    Suspend = suspendContainer,
    IdentityFilterHolds = identityFilterHolds,
    GateOnIdentity = gateOnIdentity,
    ExpandUnitScope = expandUnitScope,
    SplitByUnitScope = splitByUnitScope,
    UnitScopeAllowsSlot = unitScopeAllowsSlot,
    SyncGroup = syncGroup,
    SyncSpellGroups = syncSpellGroups,
    SyncSlots = syncSlots,
    ApplyTooltip = applyTooltip,
    ApplyActiveGlow = applyActiveGlow,
    ApplyCdmAlertGlow = applyCdmAlertGlow,
    SyncProcGlow = syncProcGlow,
    AttachPandemic = attachPandemic,
    SyncPandemic = syncPandemic,
    CreateTextLayer = createTextLayer,
    makeInit = makeInit,
    RegisterTracker = registerTracker,
    TrackButton = trackButton,
    ForEachTrackedButton = forEachTrackedButton,
    MarkDirty = markDirty,
    RestyleIfDirty = restyleIfDirty,
}

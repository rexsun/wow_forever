
--[[
    Aura ICON tracker FACTORY — renders tracked aura icons via AuraContainer
    (WoW 12.1+).  `CreateTracker(config)` builds one independent instance; every
    consumer gets its own containers, cells and event driver.

    Consumers:
      - Components/BuffTracker.lua      — the primary tracker, spells from CDM
        category BuffIcon minus Additional-Frame-routed ones, plus custom spells
      - Core/AdditionalFrameManager.lua — one instance per `buffs`-type Additional
        Frame, spells from that frame's own assigned_spells

    Extracted so Additional Frames get REAL aura containers.  They previously
    cross-parented live CDM viewer children, which cannot work on 12.1: nothing
    re-runs an AF layout when a child's shown state flips, and the compaction
    that drives it is secret.  This is the icon twin of Core/AuraBarTracker.lua;
    the two are deliberately separate files rather than one parameterized engine,
    because only the RENDERING is shared in shape — the icon path places a grid
    through IconTracker.PlaceGrid, the bar path a single-line flow.

    Three aura groups across THREE containers (a container has exactly ONE unit;
    per-group SetUnit is deferred to 12.1.5, so this split is the architecture
    for the whole 12.1 cycle — see .context/patterns-auracontainer.md):
      - player container:          <name>_main           HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY
      - target container:          <name>_target_harmful HARMFUL|PLAYER
      - target-helpful container:  <name>_target_helpful HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY
    ONE spell map feeds all three; the filter strings decide where an aura can
    land, exactly as Blizzard's own CDM does.  The third container exists solely
    so the helpful block can be hidden while the player targets themself, which
    would otherwise draw a self-buff twice.
--]]

local _
---@type string, private
local addonName, private = ...
local LAC = LibStub("LibAuraContainer-1.0")

---@class private : table
---@field AuraIconTracker auraicontrackerfacade

---@class auraicontrackerfacade
---@field CreateTracker fun(config: table): table

---Master switch for the collapsing slot chain ([EXPERIMENTAL], `collapse_layout`).
---
---Back on 2026-10-02 for one thing per-spell groups cannot do: put player and
---target auras in ONE Tracking-tab order.  A container holds one unit and its
---groups form one flow block, so the groups engine draws every target aura after
---the whole player block; the chain anchors buttons across all three containers
---and so can interleave them (Core/AuraTrackers.md "Collapsing slot chain").
---The price is the groups flow: one chain is one line, with no wrap.  Set this to
---false to take the option out again; findings are in
---`.context/patterns-auracontainer.md` "Collapsing a slot chain".
local CHAIN_ENABLED = true

---Settings the dirty-flag restyle pass is the only writer of.  A change to
---any of them must reach the buttons through MarkDirty, so Refresh compares
---them itself instead of relying on every setter to raise private.fontsDirty.
---@type string[]
local RESTYLE_KEYS = {
    "icon_size", "icon_height",
    "hide_icon", "hide_cd_swipe", "hide_cd_text", "reverse_swipe",
    "desaturate_inactive",
}

---The spell whose ICON a tracked entry displays, which is not the entry's key.
---
---Blizzard's `CooldownViewerItemDataMixin:GetSpellTexture` takes the aura's own
---icon whenever `PreferAuraDataOverSpellData` holds — true for a passive entry,
---and for an actively-cast one whose aura lands on the target
---(`CooldownViewerItemData.lua:558/1091`) — and failing that the dynamic-
---appearance branch takes `GetLinkedSpell()` (`:571`).  Both resolve to the
---LINKED aura for an entry like DK Outbreak `77575`, whose displayed aura is
---Virulent Plague `191587`; the entry key is the cast spell and drawing it gives
---the cast icon instead of the debuff icon.
---
---The live aura is secret, so this is `linkedSpellIDs[1]` — the same static
---stand-in `IconTracker`'s swap slots use, exact for the single-link entries that
---are nearly all of them.  Entries with no link (and the item-backed keys, which
---already ARE aura ids) fall through to the key unchanged.
---
---**The always-show GRID cell is the only caller left.** A cell is drawn whether
---or not the aura is up, so it needs an answer while there is no aura to ask; the
---aura-driven buttons bind `SetIcon` instead and get Blizzard's own choice (see
---`restyleButton`).  Which is why a multi-link entry still shows link #1 on the
---grid — one cell per entry cannot say more, and one cell per LINK would draw
---four static Roll the Bones icons.
---@param spellID number
---@return number
local function displaySpellFor(spellID)
    return private.CDMDataSource.GetSwapIconSpell(spellID) or spellID
end

---Build one icon-tracker instance.
---
---**Every piece of state below is a local inside this function**, so each call
---produces fully independent closures — that is what lets one Additional Frame
---instance per `buffs` frame own its containers without colliding with the
---primary tracker or with another AF.  A variable accidentally left at MODULE
---scope would silently become shared across instances and would NOT be caught
---by single-instance testing.
---
---@param config table
---  * `name`           component name; also the aura-group key prefix and the
---                     AuraContainer tracker-registry key
---  * `prefix`         global frame-name prefix (e.g. "CUE_BT")
---  * `parent`         host frame for the wrapper (defaults to UIParent)
---  * `getSettings`    fun(): table — the profile table for this instance
---  * `buildSpellMap`  fun(): table<number, true> — tracked spells
---@return table tracker
local function createTracker(config)
    local name = config.name
    local prefix = config.prefix
    local getSettings = config.getSettings
    local buildSpellMap = config.buildSpellMap

---@diagnostic disable-next-line: missing-fields
local tracker = {}

tracker.name = name

---Last values of RESTYLE_KEYS seen by Refresh, per instance.
---@type table<string, any>
local lastRestyleGeom = {}

---Player-unit AuraContainer frame — created once in Initialize. Its rect is
---engine-owned and SECRET — never read or anchor to it.
---@type frame?
local container

---Plain wrapper around the player aura container — the component/anchor-facing
---frame (GetFrame/Show/Hide/SetAlpha). Addon-owned rect, safe to anchor to.
---@type frame?
local wrapper

---Target-unit AuraContainer (SetUnit "target") — carries the HARMFUL target
---group. Same secret-rect rules as the player container.
---@type frame?
local targetContainer

---Second target-unit AuraContainer, carrying the HELPFUL target group alone.
---Split out solely so it can be hidden while the player targets themself, which
---is when a self-buff would otherwise be drawn by both this and the player
---container.  See the matching note in Core/AuraBarTracker.lua for why a whole
---container is the granularity (every candidate-filter call is
---combat-restricted; `SetShown` on our own frame is not).
---@type frame?
local targetHelpfulContainer

---Bounds frame enclosing both aura containers — a CHILD of `wrapper` so it
---inherits Show/Hide/alpha automatically. Sized by `ResizeToBoundsRect` to the
---two blocks it holds, then centred on `wrapper` as a unit. Its rect is
---secret-derived; never read it.
---@type frame?
local pairFrame

---Tracked spell count for IsCollapsed / GetComponentSize estimates and the
---groups-mode section stacking offset. Updated on every Refresh.
---One count, not two: both containers hold the same map (see buildSpellMap).
---@type integer
local spellCount = 0

---Totem icons (`show_totems`), keyed by SLOT and never re-keyed; the block is
---"Totem icons" below.  Declared up here because both engines lead their run
---with them (syncContainerLayout, layoutSlotCells).
---@type frame[]
local totemCells = {}

---Totem slots the last Refresh laid out; 0 while the key is off.
local totemCount = 0

---initializeFrame closures for the per-spell groups engine, one per spellID.
---AddAuraGroup captures the closure at creation and a group is never removed, so
---these are built once per spell and reused for the life of the session.
---@type table<number, function>
local spellInitFns = {}

---The initializeFrame closure for one spell's group, memoized.
---@param spellID number
---@return function
local function spellInitFor(spellID)
    local fn = spellInitFns[spellID]
    if not fn then
        -- singleFrame: every per-spell group is created with maxFrameCount = 1,
        -- so nine of each batch of ten pooled buttons can never be acquired.
        fn = private.AuraContainer.makeInit(name, getSettings, spellID, true)
        spellInitFns[spellID] = fn
    end
    return fn
end

---Event driver for the target container refresh and the proc_glow poll.
---@type frame?
local auraEvents

---Last collapsed state for transition detection.
---@type boolean
local wasCollapsed = true

tracker.GetSettings = getSettings

---Read the row, do not index it blind: for a hosted (Additional Frame) tracker
---getSettings() returns private.profile.additional_frames[id], which is nil once
---the frame is deleted or a profile switch drops the id.  Every consumer treats
---this as a truthy test, so a nil return is safe where an error was not.
local getEnabled = function()
    local settings = getSettings()
    return settings and settings.enabled
end

tracker.GetEnabled = getEnabled

---Whether this tracker's shared-bus callbacks are currently registered.
local callbacksRegistered = false

---Named so OnDisable can actually unregister them.  Registering an anonymous
---closure per instance leaks one permanently-firing handler per tracker: a
---deleted Additional Frame's callbacks keep calling Refresh forever, and
---Callback.Trigger has no pcall, so one erroring handler aborts every handler
---after it.
---A spells/alerts change that lands mid-fight is lost to Refresh's combat bail,
---and the combat-exit layout pass runs ContentLayout (this Refresh) only for a
---tracker shown then: one hidden by a rule or its parent kept the stale map --
---under an out_of_combat hide, through the whole next fight.  One-shot, and
---registered only by such a change, never by an in-combat layout pass, so an
---ordinary fight costs nothing.
local catchUpAfterCombat
catchUpAfterCombat = function()
    private.Callback.Unregister("OnLeaveCombat", catchUpAfterCombat)
    tracker.Refresh()
end

local function onCallbackRefresh()
    if InCombatLockdown() then
        private.Callback.Register("OnLeaveCombat", catchUpAfterCombat)
    end
    tracker.Refresh()
end

local function registerTrackerCallbacks()
    if callbacksRegistered then return end
    callbacksRegistered = true
    private.Callback.Register("OnCDMSpellsChanged", onCallbackRefresh)
    -- The CDM visual-alert model lands REBUILD_DEBOUNCE after the spells signal
    -- above; this is the pass that picks it up (applyCdmAlertGlow).
    private.Callback.Register("OnCDMAlertsChanged", onCallbackRefresh)
    -- No combat-transition refreshes: Refresh bails in combat and, at
    -- PLAYER_REGEN_DISABLED (before the lockdown starts), only redrew the state
    -- already on screen, in the pull frame.  The catch-up on exit is Anchoring's
    -- OnLeaveCombat pass, which runs ContentLayout -- this Refresh -- plus
    -- catchUpAfterCombat when a change arrived mid-fight.
end

local function unregisterTrackerCallbacks()
    if not callbacksRegistered then return end
    callbacksRegistered = false
    private.Callback.Unregister("OnCDMSpellsChanged", onCallbackRefresh)
    private.Callback.Unregister("OnCDMAlertsChanged", onCallbackRefresh)
    -- A deleted Additional Frame must not refresh at combat end.
    private.Callback.Unregister("OnLeaveCombat", catchUpAfterCombat)
end

---Whether this tracker runs the always-show GRID (static, per-spell identity
---known) rather than a compacting engine.  Read here and nowhere else so the
---layout and the Options panel — which hides the grid-only widgets — cannot
---disagree.  The collapsing chain runs on slots too (Refresh's `usingSlots`),
---but it compacts and is one line, so overflow sizing and proc glow are as inert
---on it as on groups and the panel treats it as compacting.
---@return boolean
tracker.IsUsingSlots = function()
    return getSettings().always_show_tracked == true
end

-- Spell map: injected via config.buildSpellMap.  The primary tracker derives it
-- from a CDM category minus AF-routed spells; an Additional Frame derives it
-- from its own assigned_spells.  Either way it is ONE map fed to ALL THREE
-- groups — the filter strings decide where an aura can land, exactly as
-- Blizzard's own CDM does (`scanUnits = { "player", "target" }`,
-- CooldownViewerItemData.lua:1; `selfAura` is a DB2 field their UI never reads).

-- ---------------------------------------------------------------------------
-- Layout helpers
-- ---------------------------------------------------------------------------

---Effective icon height: icon_height override or square (old-engine contract).
---
---`chain_fit` ([TEST], collapsing chain only) replaces `icon_size` with a
---fit-to-box size — every tracked icon shrunk to fill the configured
---width/height in one run, capped at a quarter of it, straight out of the same
---`Util.ComputeViewerIconLayout` the `fixed_width` mode uses.  It was the only
---size mode the collapsing chain reacted to, and it is here rather than in
---`applySlotAnchors` because `restyleButton` writes `iconDims` onto every button
---AFTER the anchor pass and would otherwise overwrite it.
---
---Deliberately NOT gated on the chain.  The mode is no longer offered, but a
---profile saved while the prototype was enabled still carries it, and every
---other reader (`ComputeViewerIconLayout[Vertical]`, both `isFixed` tests)
---treats it as `fixed_width` — so applying it here keeps that profile
---self-consistent under the grid and groups engines instead of leaving the
---icon size disagreeing with the box.
---
---Sized from the TRACKED count, not the visible one: the chain compacts inside a
---box laid out for everything it could show, because the visible count is
---secret.  So icons do not grow as auras drop off — the run just gets shorter.
---@param settings table
---@return number w, number h
local function iconDims(settings)
    local size = settings.icon_size or 40
    if settings.frame_size_mode == "chain_fit" then
        if (settings.layout_direction or "horizontal") == "vertical" then
            size = private.Util.ComputeViewerIconLayoutVertical(settings, spellCount,
                private.Anchor.GetInheritedHeight(tracker.name))
        else
            size = private.Util.ComputeViewerIconLayout(settings, spellCount,
                private.Anchor.GetInheritedWidth(tracker.name))
        end
    end
    local h = (settings.icon_height and settings.icon_height > 0)
        and math.floor(settings.icon_height) or size
    return size, h
end

---Build the AddAuraGroup/SetAuraGroupLayout opts from component settings.
---@param settings table
---@return table
local function buildLayoutOpts(settings)
    local w, h = iconDims(settings)
    local spacing = settings.icon_offset or 1
    return {
        elementWidth   = w,
        elementHeight  = h,
        elementSpacing = spacing,
        lineSpacing    = spacing,
    }
end

---Line cap along the flow axis, mirroring the old ComputeViewerIconLayout
---constraint logic: max_per_row = explicit count formula reduced by the
---anchor-inherited size; max_width (and the degraded fixed_* modes) = profile
---width/height capped (horizontal) or replaced (vertical — old-engine
---behavior) by the inherited size. The inherited size is the anchor system's
---"follow parent %" width (anchor_width_mode/anchor_width_pct).
---@param settings table
---@return number
local function computeLineCap(settings)
    local vertical = (settings.layout_direction or "horizontal") == "vertical"
    local size = (iconDims(settings))
    local pad = settings.icon_offset or 1
    local mode = settings.frame_size_mode or "max_width"
    if mode == "max_per_row" then
        local n = math.max(1, settings.max_icons_per_row or 8)
        local _, h = iconDims(settings)
        local per = vertical and h or size
        local cap = n * per + (n - 1) * pad
        local avail = vertical
            and private.Anchor.GetInheritedHeight(tracker.name)
            or private.Anchor.GetInheritedWidth(tracker.name)
        if avail and avail > 0 and avail < cap then cap = avail end
        return cap
    end
    if vertical then
        local avail = private.Anchor.GetInheritedHeight(tracker.name)
        return (avail and avail > 0) and avail or (settings.height or 150)
    end
    local w = settings.width or 400
    local avail = private.Anchor.GetInheritedWidth(tracker.name)
    if avail and avail > 0 and avail < w then w = avail end
    return w
end

---Apply the old-engine layout contract to ONE aura container:
---layout_direction → flow axis, layout_alignment → flow origin,
---overflow_direction → cross-axis line growth (old defaults: rows overflow
---UPWARD, columns overflow RIGHTWARD). Returns the wrapper pin point.
---
---"center" alignment is approximated by pinning the container's cross-axis
---CENTER edge point to the wrapper's same point: the engine-sized rect then
---centers the whole icon block on the wrapper. Full lines match the old
---per-row centering exactly; a partial last line stays origin-aligned within
---the block (old engine centered it individually — not achievable with the
---flow layout, which needs per-line counts that are secret).
---Centred runs flow left to right, like the slots grid (`IconTracker.PlaceGrid`),
---so the Tracking-tab order reads the same in both engines.  A mirrored player
---block (3.0.0) put its partial row by the target seam but reversed that order.
---Exercised by any reload: a non-origin pin on the secret-sized container.
---@param c frame
---@param settings table
---@param lineCap number
---@return string pinPt, string originPt
local function applyContainerFlow(c, settings, lineCap)
    local vertical = (settings.layout_direction or "horizontal") == "vertical"
    local alignment = settings.layout_alignment or "center"
    local hDir, vDir, originPt, pinPt
    if vertical then
        local overflowDir = settings.overflow_direction or "right"
        hDir = (overflowDir == "left") and LAC.FlowDirection.Left
            or LAC.FlowDirection.Right
        local hEdge = (overflowDir == "left") and "RIGHT" or "LEFT"
        if alignment == "bottom" then
            vDir = LAC.FlowDirection.Up
            originPt = "BOTTOM" .. hEdge
        else
            vDir = LAC.FlowDirection.Down
            originPt = "TOP" .. hEdge
        end
        pinPt = (alignment ~= "top" and alignment ~= "bottom") and hEdge or originPt
        c:SetFlowLayoutAxis(LAC.FlowLayoutAxis.Vertical)
    else
        local overflowDir = settings.overflow_direction or "top"
        vDir = (overflowDir == "top") and LAC.FlowDirection.Up
            or LAC.FlowDirection.Down
        local vEdge = (overflowDir == "top") and "BOTTOM" or "TOP"
        if alignment == "right" then
            hDir = LAC.FlowDirection.Left
            originPt = vEdge .. "RIGHT"
        else
            hDir = LAC.FlowDirection.Right
            originPt = vEdge .. "LEFT"
        end
        pinPt = (alignment ~= "left" and alignment ~= "right") and vEdge or originPt
        c:SetFlowLayoutAxis(LAC.FlowLayoutAxis.Horizontal)
    end
    c:SetFlowLayoutGrowthDirection(hDir, vDir)
    c:SetFlowLayoutAnchorPoint(originPt)
    c:SetFlowLayoutMaximumLineSize(lineCap)
    c:SetFlowLayoutPadding(0, 0, 0, 0)
    c:ClearAllPoints()
    c:SetPoint(pinPt)
    return pinPt, originPt
end

---Size the bounds frame to the two aura blocks it encloses.
---
---**The `SetSize(0.001, 0.001)` first is load-bearing, not defensive.** The
---bounds rect is the union of the frame's OWN rect and its children's, so
---resizing without collapsing it first can only ever grow the frame — the
---centring would then be permanently stuck at the widest burst the tracker ever
---rendered.  Same shape Coolinator uses (`Display/Stack.lua` TriggerLayout).
---
---`ResizeToBoundsRect` takes no arguments and returns nothing, so the secret
---block extents are consumed entirely engine-side and never reach Lua — which is
---what makes centring the pair possible at all.
---
---Deliberately NOT combat-guarded: it is flagged `IsProtectedFunction`, but
---`pairFrame` is addon-created, and the house rule is to match a guard to an
---OBSERVED blocked action rather than a static sweep (patterns.md).  If it does
---blow up, the fix is an `InCombatLockdown()` skip here plus the combat-exit
---layout pass (Anchoring's OnLeaveCombat, which runs this tracker's Refresh) —
---at the cost of frozen centring during a pull.
local function resizePair()
    pairFrame:SetSize(0.001, 0.001)
    private.compat.ResizeToBoundsRect(pairFrame)
end

---Lead the groups engine's run with the totem icons and return the frame the
---player block chains onto: the last one, or nil with the key off.
---
---A collapsing chain (.context/patterns-auracontainer.md "Collapsing a slot
---chain") from `pairFrame`'s flow origin, which is its non-collapsing head: an
---empty slot is Hide()n (updateTotemCells) and closes its own gap, so the buffs
---slide up to the last totem shown without a SetPoint in combat.  The icons are
---children of `pairFrame`, so resizePair's bounds and the centring include them.
---Inferred, not yet seen: with no totem up the player block sits one
---`icon_offset` past the origin, since a collapsed link takes its own size
---out of the line but not the offset the block joins it with.
---@param originPt string  the run's flow origin (applyContainerFlow)
---@param trailingPt string  the corner the next link joins on
---@param dx number
---@param dy number
---@param head frame?  the non-collapsing head; `pairFrame` unless the slot
---  chain leads with the icons from its `chainOrigin` (applySlotAnchors)
---@return frame?
local function chainTotems(originPt, trailingPt, dx, dy, head)
    local prev
    for i = 1, totemCount do
        local cell = totemCells[i]
        cell:ClearAllPoints()
        if prev then
            cell:SetPoint(originPt, prev, trailingPt, dx, dy)
        else
            cell:SetPoint(originPt, head or pairFrame, originPt)
        end
        cell:SetCollapsesLayout(true)
        prev = cell
    end
    return prev
end

---Apply flow settings to both containers and CHAIN the target block directly
---onto the end of the player block along the run axis: a horizontal layout puts
---them side by side on one row, a vertical layout continues the column.
---
---The chain is an anchor, not an estimate. `OnLayoutComplete` sizes each
---container to its own VISIBLE block, so anchoring the target container's
---leading corner (its flow origin) to the player container's trailing corner
---abuts the two blocks exactly — with hide-when-inactive, the seam tracks the
---live icon count. The rect is secret to Lua, but the anchor resolves
---engine-side, so nothing here reads it. This replaces a settings-derived
---offset that reserved room for every TRACKED aura and so left a large gap
---whenever most of them were inactive.
---
---Nothing downstream measures the target wrapper or container — component size
---comes from `GetComponentSize`'s own estimate — so the secret rect stays
---contained to this pair (see the two-frame note in Core/AuraContainer.lua).
---Hide the target-HELPFUL block while the player is their own target, so a
---self-buff is not drawn by both it and the player container.
---
---`SetShown` on an addon-owned frame is unrestricted, which is the entire reason
---that group lives in a container of its own — see `targetHelpfulContainer`.
---Hidden children are excluded from `GetBoundsRect`, so `resizePair` closes the
---gap without extra bookkeeping.
---Defined above `Initialize` on purpose: the OnEvent closure there captures this
---as an upvalue at definition time (patterns.md "Lua 5.1 Upvalue Safety").
---Filter strings, matching Blizzard's own `GetTargetAurasFilterString`
---(CooldownViewerItemData.lua:661): friendly units (the player, and a friendly
---target) take HELPFUL with the nameplate-only flag INCLUDED, hostile units take
---HARMFUL.  Without INCLUDE_NAME_PLATE_ONLY a nameplate-flagged aura is silently
---dropped.  Blizzard picks one per unit via UnitIsFriend; we run both target
---groups concurrently instead, because SetAuraGroupCandidateFilters is
---combat-restricted and a target-change re-filter would break mid-pull.
---
---Declared up here rather than beside the slot-filter lists below because
---`syncSelfTargetSuppression` reads them, and a Lua 5.1 local captured after its
---reader resolves to a nil global (patterns.md "Lua 5.1 Upvalue Safety").
local PLAYER_HELPFUL = "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"
local PLAYER_HARMFUL = "HARMFUL|PLAYER"

---Also hides any block whose identity gate does not hold, which is the only
---repair for it: the gate is a function of the unit's reaction, so re-parsing
---just re-admits the same untracked auras.  Two independent reasons per target
---block, so both are ANDed rather than layered.
---
---This restores Blizzard's own model rather than departing from it:
---`GetTargetAurasFilterString` picks ONE filter per unit by reaction. We run both
---target filters concurrently only because `SetAuraGroupCandidateFilters` cannot
---be called in combat — hiding is the combat-safe way to make the same choice,
---and the block being hidden is always the one whose filter that unit's reaction
---makes meaningless anyway.
local function syncSelfTargetSuppression()
    if not targetHelpfulContainer then return end
    local holds = private.AuraContainer.IdentityFilterHolds
    container:SetShown(holds(PLAYER_HELPFUL, "player"))
    targetContainer:SetShown(holds(PLAYER_HARMFUL, "target"))
    targetHelpfulContainer:SetShown(holds(PLAYER_HELPFUL, "target")
        and not UnitIsUnit("target", "player"))
end

---@param settings table
local function syncContainerLayout(settings)
    local lineCap = computeLineCap(settings)
    local pinPt, originPt = applyContainerFlow(container, settings, lineCap)
    -- Configures the target containers' flow axis/origin/growth; their pins are
    -- replaced by the chain below.
    applyContainerFlow(targetContainer, settings, lineCap)
    applyContainerFlow(targetHelpfulContainer, settings, lineCap)

    local pad = settings.icon_offset or 1
    local vertical = (settings.layout_direction or "horizontal") == "vertical"
    local alignment = settings.layout_alignment or "center"
    -- Trailing corner of the player block = the opposite edge of its flow
    -- origin along the run axis, mirroring applyContainerFlow's growth
    -- direction so the target block continues the run instead of doubling back.
    local trailingPt, dx, dy = nil, 0, 0
    if vertical then
        local hEdge = (settings.overflow_direction == "left") and "RIGHT" or "LEFT"
        if alignment == "bottom" then
            trailingPt, dy = "TOP" .. hEdge, pad
        else
            trailingPt, dy = "BOTTOM" .. hEdge, -pad
        end
    else
        local vEdge = ((settings.overflow_direction or "top") == "top") and "BOTTOM" or "TOP"
        if alignment == "right" then
            trailingPt, dx = vEdge .. "LEFT", -pad
        else
            trailingPt, dx = vEdge .. "RIGHT", pad
        end
    end

    -- Player block at the bounds frame's own origin corner, target block chained
    -- onto its trailing edge.  applyContainerFlow already pinned the player
    -- container to its parent at `pinPt`; re-pin at the flow origin so the block
    -- starts in a known corner of the bounds frame and the chain is exact.
    -- Totem icons, when on, lead the run and the player block follows them.
    container:ClearAllPoints()
    local lastTotem = chainTotems(originPt, trailingPt, dx, dy)
    if lastTotem then
        container:SetPoint(originPt, lastTotem, trailingPt, dx, dy)
    else
        container:SetPoint(originPt, pairFrame, originPt)
    end
    targetContainer:ClearAllPoints()
    targetContainer:SetPoint(originPt, container, trailingPt, dx, dy)
    -- Helpful LAST in the chain, so hiding it (self-target suppression) leaves
    -- no hole between the other two blocks.
    targetHelpfulContainer:ClearAllPoints()
    targetHelpfulContainer:SetPoint(originPt, targetContainer, trailingPt, dx, dy)

    -- Size the bounds frame to the two blocks, then place it on the wrapper by
    -- the alignment pin.  ResizeToBoundsRect takes no arguments and returns
    -- nothing, so the secret extents stay engine-side; `pinPt` is the same point
    -- applyContainerFlow derives from layout_alignment, so "center" centres the
    -- PAIR rather than either block.
    pairFrame:ClearAllPoints()
    pairFrame:SetPoint(pinPt, wrapper, pinPt)
    resizePair()

    -- Re-run every frame while the groups engine is driving.  The engine sizes
    -- each container from its own OnUpdate (`OnLayoutComplete`), so a same-pass
    -- resize reads stale extents; and under hide-when-inactive the blocks change
    -- size whenever an aura comes or goes — including mid-combat, where Refresh
    -- bails.  The compaction that drives it is secret, so there is nothing to
    -- gate on and no event to hook: a per-frame recompute is the only signal
    -- available.  Coolinator drives its own ResizeToBoundsRect the same way
    -- (`Display/Group.lua` RegisterForLayout).
    pairFrame:SetScript("OnUpdate", resizePair)
end

-- ---------------------------------------------------------------------------
-- Dirty-flag restyle
-- ---------------------------------------------------------------------------

---The spell a tracked button draws (defined after the slot state it reads).
---@type fun(button: frame): number|nil
local spellOfButton

---Apply font settings to a tracked AuraContainer button.
---Called by RestyleIfDirty on OnProfileChanged.
---@param button frame
---@param settings table
local function restyleButton(button, settings)
    -- A totem icon (show_totems) has no aura to describe or glow from; the rest
    -- is plain widget work on whatever carries the cue_* keys.
    if not button.cue_totem then
        private.AuraContainer.ApplyTooltip(button, settings)
        private.AuraContainer.ApplyActiveGlow(button, settings)
    end
    -- Button size must track icon_size/icon_height: the flow layout uses the
    -- button's NATURAL size (set in makeInit); layout opts only drive spacing.
    local iconW, iconH = iconDims(settings)
    button:SetSize(iconW, iconH)
    -- Global icon_border.  Under groups the button IS the icon, so the border
    -- goes here; under slots the chrome is the cell and placeCell owns it, so a
    -- second one on the button would double-draw over it.
    --
    -- Except under desaturate_inactive: a slot button then carries the
    -- full-colour copy of the cell's icon (applyActiveIcons), and that copy sits
    -- a frame level above the cell -- over an inside border, and past hide_icon,
    -- unless the button carries both itself.
    if not button.cue_slot or settings.desaturate_inactive == true then
        -- A per-spell `spell_borders` colour needs the button's spell: nil for
        -- a plain group, whose binding is secret, which keeps the global one.
        private.Util.ApplyIconBorder(button, nil,
            private.Util.GetSpellBorderColor(settings, spellOfButton(button)))
        -- ApplyIconBorder re-shows the border; re-assert hide_icon after it.
        private.Util.ApplyIconVisibility(button, settings.hide_icon == true)
    else
        -- Under slots the icon lives on the CELL and placeCell owns this.  Hides
        -- a border an earlier desaturate_inactive pass drew (no-op otherwise).
        private.Util.ApplyIconVisibility(button, true)
    end
    -- Re-apply the icon crop so icon_zoom / aspect changes reach live buttons.
    if button.cue_Icon then
        button.cue_Icon:SetTexCoord(private.Util.GetIconZoomCoords(iconW, iconH))
        -- WHICH aura's icon a per-spell button draws is Blizzard's question, not
        -- ours.  A multi-link entry has no static answer — Roll the Bones `1214909`
        -- carries all four buffs in `linkedSpellIDs`, so `displaySpellFor`'s
        -- `linkedSpellIDs[1]` stand-in draws the same icon whichever one is rolled
        -- — and the engine already knows, because the button exists only while its
        -- matched aura does.  So bind `SetIcon` and let it write that aura's own
        -- texture, exactly as a plain group does.  No inactive state to cover:
        -- these buttons are aura-driven Show/Hide either way (per-spell group, or
        -- the collapsing chain, where `cue_spellID` moves the chrome onto the
        -- button; the grid's chrome is the cell and takes the nil branch).
        --
        -- An `icon_overrides` entry outranks Blizzard — the user pinned a texture —
        -- and the bind is precisely what would clobber it on every aura update, so
        -- an override takes the icon back with `ClearIcon`.  Both are plain mixin
        -- methods with no combat gate (`Blizzard_CustomAuraButton.lua:223/232`;
        -- `ValidateInboundScriptObject` checks parentage and forbidden/protected
        -- aspects only), but each ends in a full `UpdateAuraDisplay()`, so
        -- `cue_iconBound` keeps the calls to real transitions.
        --
        -- Only ever clears a bind WE made: a plain group is bound by `makeInit`
        -- with `cue_spellID` nil and must keep it.
        local override = button.cue_spellID
            and private.Util.ResolveIconOverride(button.cue_spellID)
        local wantBind = button.cue_spellID ~= nil and not override
        if wantBind ~= (button.cue_iconBound == true) then
            button.cue_iconBound = wantBind or nil
            if wantBind then
                button:SetIcon(button.cue_Icon)
            else
                button:ClearIcon()
                -- ClearIcon only drops the bind; the last aura texture the engine
                -- wrote would stay drawn — over the cell's chrome, on a grid slot.
                button.cue_Icon:SetTexture(nil)
            end
        end
        if override then button.cue_Icon:SetTexture(override) end
    end
    -- hide_cd_swipe / hide_cd_text.  Master applied these by walking the CDM
    -- viewer's children (`SetDrawSwipe` / `SetHideCountdownNumbers` per child);
    -- the AuraContainer button carries our own cue_Cooldown instead, so they
    -- belong on the restyle path — which covers acquire, re-bind and both
    -- engines.  Not an aura read: pure widget config on an addon-created frame.
    if button.cue_Cooldown then
        button.cue_Cooldown:SetDrawSwipe(settings.hide_cd_swipe ~= true)
        button.cue_Cooldown:SetHideCountdownNumbers(settings.hide_cd_text == true)
        -- Blizzard's BuffIcon swipe runs reversed (reverse="true",
        -- CooldownViewer.xml:183): the icon starts lit and darkens as the aura
        -- runs out.  reverse_swipe flips that.  2.13.4 never restyled BuffIcon
        -- children -- ApplySwipeToChild ran only on children carrying
        -- cooldownSwipeColor, which only Essential/Utility items set -- so the
        -- key did nothing there; it exists only on `buffs` Additional Frames and
        -- reads nil (= Blizzard's direction) elsewhere.
        button.cue_Cooldown:SetReverse(settings.reverse_swipe ~= true)
    end
    -- ApplyFontProfile carries face/size/outline/shadow/colour AND the profile's
    -- anchor_point/offset_x/offset_y.  Hand-rolling the first half here silently
    -- dropped the second, so the Font position controls did nothing on buff icons.
    if settings.timer_font and button.cue_Timer then
        private.Util.ApplyFontProfile(button.cue_Timer, settings.timer_font, button)
    end
    if settings.stacks_font and button.cue_Count then
        private.Util.ApplyFontProfile(button.cue_Count, settings.stacks_font, button)
    end
end

-- ---------------------------------------------------------------------------
-- Always-show engine (AddAuraSlot)
-- ---------------------------------------------------------------------------
--
-- The second display engine, selected by always_show_tracked.  Groups compact the secret active set; slots hold a
-- static grid of one cell per TRACKED spell, which is the mapped spell count —
-- a plain number we already have.  That is what makes the whole grid ours and
-- unblocks the layout gaps groups cannot serve (per-line centering of a partial
-- row, overflow_icon_size, the fixed_width* modes, content-hugging size).
--
-- Role split (patterns-auracontainer.md): our CELL carries the persistent
-- chrome, the slot button carries only the aura-driven adornments.  The button
-- is SetAllPoints'd to the cell inside initializeFrame — before the provider
-- applies access restrictions — so afterwards only the cell is ever moved and
-- the button never needs another (restricted) geometry call.

---One slot per (spell, container), all three sharing ONE chrome cell: a tracked
---spell may land on the player, as a target debuff, or as an ally-target buff.
---Separate cell pools per unit would draw every always-show spell twice.
---
---One filter per list because the target HELPFUL group now has a container of
---its own (`targetHelpfulContainer`) — the two target filters can no longer
---share a slot list.
local SELF_FILTERS = { PLAYER_HELPFUL }
local TARGET_HARMFUL_FILTERS = { PLAYER_HARMFUL }
local TARGET_HELPFUL_FILTERS = { PLAYER_HELPFUL }

---Idle-engine include map: matches no aura, so the groups engine allocates
---nothing while slots are driving (and vice versa).  Never mutated.
local EMPTY_MAP = {}

---Empty spell list handed to SyncSlots to switch the slots engine off.
---Never mutated.
local EMPTY_LIST = {}

---Chrome cells, ONE per tracked spell and shared by both containers' slots.
---Cell `i` carries the player-HELPFUL button plus the two target buttons, so a
---spell occupies one grid position no matter which unit its aura lands on.
---@type frame[]
local cells = {}

---Ordered (sorted) spell list backing the cells — map iteration order is not
---stable, and the grid order must be.
---@type number[]
local spellList = {}

---Grid index each allocated slot BUTTON sits on.  Three containers (self,
---target-harmful, target-helpful) share one cell per index and one
---`initSlotButton`, so a per-container registry would be three tables for one
---question; a flat button->index map answers it in one walk.  A slot's cell is
---fixed at allocation, so an entry here never moves — but the SPELL on that
---index does, which is exactly why the index rather than the spell is stored.
---@type table<frame, number>
local slotButtonIndex = {}

---Slot buttons in chain order, one array per container (1 = player, 2 = target
---HARMFUL, 3 = target HELPFUL), indexed by grid position.  `slotButtonIndex`
---answers "which spell is this button on"; this answers the reverse, which is
---what the collapsing chain needs to anchor them in a fixed order.
---@type table<number, frame[]>
local chainSlots = {{}, {}, {}}

---Non-collapsing head of the chain.  `SetCollapsesLayout` closes the gap left by
---a hidden frame by resolving through to what IT anchors to, so the first link
---needs something that is never hidden and never collapses to land on.
---@type frame?
local chainOrigin

---Button width the alert overlays are currently anchored against, set around
---the ForEachTrackedButton walk (same reason as `placeSettings`).
---@type number?
local alertIconWidth

---Whether the last Refresh ran the collapsing chain (implies `usingSlots`).
local usingChain = false

---Signature of the last applySlotAnchors pass — mode plus the spell list.  Every
---re-anchor writes into the aura buttons' subtree and ends in a full restyle, so
---it must not run on an unchanged list the way Refresh does.
local lastAnchorSig

---Reused ordered cell buffer for PlaceGrid.
---@type frame[]
local cellScratch = {}

---Settings for placeCell, set around the PlaceGrid call (same reason).
---@type table?
local placeSettings

---Expanded `aura_unit` for placeCell's missing glow, set by syncSlotEngine.
---@type table<number, string>|nil
local placeScope

---Whether the last Refresh ran the slots engine.
local usingSlots = false

---Total slot count at the last layout, for the anchor state-change trigger.
local lastSlotCount = -1

---The spell a tracked button draws: a per-spell group's or a chain link's
---stamped `cue_spellID`, else the spell on its grid slot.  Nil for a plain
---group, whose button-to-spell binding is secret.
---@param button frame
---@return number|nil
spellOfButton = function(button)
    local spellID = button.cue_spellID
    if spellID then return spellID end
    local index = slotButtonIndex[button]
    return index and usingSlots and spellList[index] or nil
end

---Fill `list` with the keys of `map` in icon order, truncating any stale tail.
---@param list number[]
---@param map table<number, true>
---@param rank table<number, number>|nil  from Util.BuildSpellOrderRank; nil (an
---  Additional Frame instance) keeps the plain spellID order this always had
local function fillSortedList(list, map, rank)
    local n = 0
    for id in pairs(map) do
        n = n + 1
        list[n] = id
    end
    for i = #list, n + 1, -1 do list[i] = nil end
    private.Util.SortByOrderRank(list, rank)
end

---Create or return the shared chrome cell at `index`.  Called once per
---(container, filter) pair for the same index, so it must be idempotent.
---@param index number
---@return frame
local function cellForSlot(index)
    local cell = cells[index]
    if cell then return cell end
    cell = CreateFrame("Frame", nil, wrapper)
    -- Chrome must render BELOW the adornments: the aura containers are children
    -- of `wrapper` and their slot buttons children of those, so a cell held at
    -- the wrapper's own frame level always sits underneath.
    cell:SetFrameLevel(wrapper:GetFrameLevel())
    cell.cue_Icon = cell:CreateTexture(nil, "ARTWORK")
    cell.cue_Icon:SetAllPoints(cell)
    -- Carried so initSlotButton can file its button under the same index; the
    -- cell is our own frame, unlike the button it will be anchored to.
    cell.cue_slotIndex = index
    -- missing_glow: built with the cell, hidden, because each slot button's
    -- mask is attached to it once in initSlotButton (syncMissingGlow).
    cell.cue_MissingGlow = private.GlowEffect.CreateActiveBorder(cell)
    cell.cue_MissingGlow:Hide()
    cells[index] = cell
    return cell
end

---initializeFrame for a slot button: adornments only.
---Deliberately NO SetIcon bind — the icon is chrome and lives on the cell, so
---it survives the button's aura-driven Show/Hide.
---@param button frame
---@param cell frame
local function initSlotButton(button, cell)
    button:SetAllPoints(cell)
    -- Marks the slots engine for restyleButton, which must not draw a second
    -- icon border over the cell's.  Cleared by the collapsing chain, where the
    -- cell is hidden and the button carries its own chrome instead — which is
    -- why the flag is set per pass in applySlotAnchors rather than only here.
    button.cue_slot = true
    slotButtonIndex[button] = cell.cue_slotIndex

    -- missing_glow: a mask the engine shows exactly while this button's aura is
    -- matched, erasing the cell's glow while the aura is up.  Bound and attached
    -- here, before the provider restricts the button.  A cell gets exactly three
    -- slot buttons (one per container), which is the three-mask cap per texture.
    local missingMask = private.IconTracker.BindCoveredMask(button)
    local edges = cell.cue_MissingGlow._edges
    for i = 1, #edges do
        edges[i]:AddMaskTexture(missingMask)
    end

    -- Icon texture on the BUTTON, unused while the grid engine draws chrome on
    -- the cell.  Created unconditionally because initializeFrame runs once per
    -- button and the chain mode can be switched on afterwards; an untextured
    -- ARTWORK region costs nothing until restyleButton binds it (which it does
    -- off `cue_spellID`, and only the chain sets that).  No bind HERE: in grid
    -- mode this texture must stay blank or it draws over the cell's chrome.
    button.cue_Icon = button:CreateTexture(nil, "ARTWORK")
    button.cue_Icon:SetAllPoints(button)

    -- Font template REQUIRED pre-bind: every Set* bind pushes text immediately
    -- and a font-less SetText errors "Font not set".
    button.cue_TextLayer = private.AuraContainer.CreateTextLayer(button)
    button.cue_Count = button.cue_TextLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.cue_Count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button:SetApplicationCount(button.cue_Count)

    button.cue_Cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cue_Cooldown:SetAllPoints(button)
    -- Blizzard's BuffIcon cooldown, which 2.13.4 displayed untouched
    -- (CooldownViewer.xml:183, CooldownViewer.lua OnLoad / RefreshCooldownInfo):
    -- 0.7 black swipe, no edge, aura countdown rounding.  Direction is
    -- restyleButton's.  Before the bind: the object is protected from then on.
    button.cue_Cooldown:SetSwipeColor(0, 0, 0, 0.7)
    button.cue_Cooldown:SetDrawEdge(false)
    button.cue_Cooldown:SetUseAuraDisplayTime(true)
    -- hide_cd_swipe too: set only by restyleButton after the bind, it left the
    -- swipe drawing (reported 2026-09-28).
    button.cue_Cooldown:SetDrawSwipe(getSettings().hide_cd_swipe ~= true)
    button:SetDurationCooldown(button.cue_Cooldown)

    -- Timer text: first region of CooldownFrameTemplate is the countdown FontString.
    button.cue_Timer = button.cue_Cooldown:GetRegions()
    button:SetDurationText(button.cue_Timer, {})

    -- Pandemic host, keyed by the cell so applyPandemicGlow can reach it by
    -- grid index (and therefore by spell, for pandemic_glow_excludes).
    private.AuraContainer.AttachPandemic(button, getSettings(), nil, cell)

    private.AuraContainer.TrackButton(name, button)
    restyleButton(button, getSettings())
end

---Per-container `initButton` wrappers: file the button under its grid index in
---`chainSlots[rank]`, then run the shared init.  Rank is 1 = player, 2 = target
---HARMFUL, 3 = target HELPFUL, matching the order the chain runs them in.
---
---Built once rather than per Refresh: `syncSlots` hands the closure straight to
---AddAuraSlot, so a fresh one per pass would allocate on every layout.
---@type fun(button: frame, cell: frame)[]
local slotInitFns = {}
for rank = 1, 3 do
    slotInitFns[rank] = function(button, cell)
        chainSlots[rank][cell.cue_slotIndex] = button
        initSlotButton(button, cell)
    end
end

---Show a cell's missing glow when its spell wants one and, for a spell tracked
---on the target only, there is a target.  Whether the aura is up is not asked:
---the slot buttons' masks erase the glow while it is.  Combat-safe (SetShown on
---our own frame), so the target handler re-runs it on every target change.
---@param cell frame  a slot cell
local function applyMissingGlowShown(cell)
    cell.cue_MissingGlow:SetShown(cell.cue_MissingWant == true
        and (not cell.cue_MissingTargetOnly or UnitExists("target")))
end

---Point a slot cell's missing glow at the spell now on its index: colour and
---scope from `missing_glow` / `aura_unit`, off when the spell has no entry.
---@param cell frame  a slot cell
local function syncMissingGlow(cell)
    local spellID = spellList[cell.cue_slotIndex]
    local color = private.Util.GetMissingGlowColor(placeSettings, spellID)
    cell.cue_MissingWant = color ~= nil
    if color then
        private.GlowEffect.ApplyActiveBorderColor(cell.cue_MissingGlow, color)
        -- The predicate syncSlotEngine's player slots use, so the glow and the
        -- slots cannot disagree on scope.
        cell.cue_MissingTargetOnly =
            not private.AuraContainer.UnitScopeAllowsSlot(placeScope, spellID, false)
    end
    applyMissingGlowShown(cell)
end

---Per-cell placement for the always-show grid.  The slot buttons ride along
---via their SetAllPoints anchor, so nothing here touches a restricted frame.
local function placeCell(cell, anchorPt, x, y, sizeW, sizeH)
    cell:ClearAllPoints()
    cell:SetPoint(anchorPt, wrapper, anchorPt, x, y)
    cell:SetSize(sizeW, sizeH)
    cell.cue_Icon:SetTexCoord(private.Util.GetIconZoomCoords(sizeW, sizeH))
    -- desaturate_inactive: the cell is what shows while the aura is NOT up.  A
    -- totem icon shows only while its totem is, so it is never greyed.
    cell.cue_Icon:SetDesaturated(not cell.cue_totem and placeSettings.desaturate_inactive == true)
    -- A totem icon has no cue_slotIndex, so it keeps the global border.
    private.Util.ApplyIconBorder(cell, nil,
        private.Util.GetSpellBorderColor(placeSettings, spellList[cell.cue_slotIndex]))
    -- ApplyIconBorder re-shows the border; re-assert hide_icon after it.
    private.Util.ApplyIconVisibility(cell, placeSettings.hide_icon == true)
    if cell.cue_slotIndex then syncMissingGlow(cell) end
    cell:Show()
end

---Hide pooled cells past the live count (their slot buttons already match
---nothing, but the chrome is ours and would otherwise stay drawn).
---@param cellArray frame[]
---@param live number
local function hideSurplusCells(cellArray, live)
    for i = live + 1, #cellArray do
        cellArray[i]:Hide()
    end
end

---This tracker's candidate-set widening: a `by_name` custom aura's ids
---(CustomSpells.GetAuraIdSet, per component), else the CDM entry's identity
---set.  Per tracker, not CDMDataSource.GetAuraIdentitySet itself: that one is
---global by spell id, and a by-name entry must not widen the same id in a
---tracker that holds it as an exact rank.
---@param spellID number
---@return table<number, true>|nil
local function identitySetFor(spellID)
    return private.CustomSpells.GetAuraIdSet(name, spellID)
        or private.CDMDataSource.GetAuraIdentitySet(spellID)
end

---Stable signature of the per-spell unit scope, so `SyncSlots` re-points its
---slots when the scope changes with the spell LIST untouched (its own signature
---is over the list alone).  Walks `spellList`, which is already sorted.
---@param scopeMap table<number, string>|nil
---@return string
local function scopeSignature(scopeMap)
    if not scopeMap then return "" end
    local parts = {}
    for i = 1, #spellList do
        parts[i] = scopeMap[spellList[i]] or ""
    end
    return table.concat(parts, ",")
end

---Point all three containers' slots at the spell list and paint the cell chrome.
---Every call walks the SAME list through the SAME cellForSlot, so slot `i` on
---any container lands on cell `i` — three buttons per cell, at most one shown.
---
---`aura_unit` is applied via the candidate set rather than by trimming the list:
---the cell index IS the list index, so a per-container list would misalign the
---three sets of buttons.
---@param spellMap table<number, true>
---@param scopeMap table<number, string>|nil  EXPANDED aura_unit, from Refresh
local function syncSlotEngine(spellMap, scopeMap)
    fillSortedList(spellList, spellMap, private.Util.BuildSpellOrderRank(name, spellMap))

    -- The name stamp: a by-name entry's ids change what identitySetFor
    -- returns without changing the list SyncSlots signs.
    local salt = scopeSignature(scopeMap) .. "|" .. private.CustomSpells.GetNameStamp()
    placeScope = scopeMap
    -- identitySetFor, not nil: the spell map is one key per CDM ENTRY (its
    -- base spell), so a single-ID filter would miss every entry whose displayed
    -- aura is an override or a linked id -- DK Outbreak 77575, shown as Virulent
    -- Plague 191587.  The map used to carry those ids as sibling keys, which
    -- matched at the cost of drawing the entry N times; the widening moved to the
    -- filter, where a set match belongs.  Returns nil for a spell with no wider
    -- identity (and for a custom spell not tracked by name), which SyncSlots
    -- reads as the single-ID filter -- the same fallback the per-spell groups
    -- engine already relies on.
    local function playerIds(spellID)
        if not private.AuraContainer.UnitScopeAllowsSlot(scopeMap, spellID, false) then
            return EMPTY_MAP
        end
        return identitySetFor(spellID)
    end
    local function targetIds(spellID)
        if not private.AuraContainer.UnitScopeAllowsSlot(scopeMap, spellID, true) then
            return EMPTY_MAP
        end
        return identitySetFor(spellID)
    end

    private.AuraContainer.SyncSlots(container, SELF_FILTERS, spellList,
        cellForSlot, slotInitFns[1], playerIds, salt)
    private.AuraContainer.SyncSlots(targetContainer, TARGET_HARMFUL_FILTERS, spellList,
        cellForSlot, slotInitFns[2], targetIds, salt)
    private.AuraContainer.SyncSlots(targetHelpfulContainer, TARGET_HELPFUL_FILTERS,
        spellList, cellForSlot, slotInitFns[3], targetIds, salt)

    -- Slot frames are never flow elements and ride their cells (children of
    -- `wrapper`), so the containers' own geometry is irrelevant here — the
    -- bounds frame just needs a resolvable rect and must stay shown, or the
    -- slot buttons inside it never render.  No ResizeToBoundsRect for the GRID:
    -- we own that layout, and PlaceGrid already centres it exactly.  The
    -- collapsing chain does not own its length, so Refresh hands the frame
    -- straight back to applyChainBounds after this.
    pairFrame:SetScript("OnUpdate", nil)
    pairFrame:ClearAllPoints()
    pairFrame:SetAllPoints(wrapper)

    -- Cell chrome: icon texture per the CDM dynamic-appearance path
    -- (conditional icon outranks the plain one), persistent across aura state.
    -- A manual icon_overrides entry outranks both — the migration to addon-owned
    -- cells took the icon off the viewer child, so the since-deleted
    -- Util.ApplyIconOverride could not have reached it and the override has to be
    -- resolved from the map key.
    for i = 1, #spellList do
        local texture = private.Util.ResolveIconOverride(spellList[i])
        if not texture then
            local iconID, _, conditionalIconID =
                C_Spell.GetSpellTexture(displaySpellFor(spellList[i]))
            texture = conditionalIconID or iconID
        end
        cells[i].cue_Icon:SetTexture(texture)
    end
end

---Lay the cells out on the shared tracker grid (IconTracker.PlaceGrid — the
---full old-viewer feature set, unchanged from the icon trackers).  Totem icons,
---when on, take the first cells: fixed places, like every always-show slot, so
---an empty totem slot is a gap rather than a shift.
---@param settings table
local function layoutSlotCells(settings)
    local n = #spellList
    hideSurplusCells(cells, n)
    for i = 1, totemCount do
        cellScratch[i] = totemCells[i]
    end
    for i = 1, n do
        cellScratch[totemCount + i] = cells[i]
    end
    n = totemCount + n
    for i = #cellScratch, n + 1, -1 do cellScratch[i] = nil end
    if n == 0 then return end

    placeSettings = settings
    private.IconTracker.PlaceGrid(settings, tracker.name, cellScratch, placeCell)
end

---desaturate_inactive: copy each cell's icon, in full colour, onto the slot
---buttons laid over it.  Whether an aura is up is secret, but the engine shows a
---slot button exactly while its aura is, so the copy IS the active state: colour
---while the aura is up, the cell's greyed icon while it is not -- or while the
---target slots have no target to match.  Nothing here reads an aura.
---
---Per Refresh rather than in restyleButton because the texture follows the
---spell on each index, which moves with the list, and the crop follows the
---cell's own size, which overflow_icon_size makes differ from icon_size.  Runs
---after RestyleIfDirty for the same reason.
---Grid only: the chain binds the button icon itself (restyleButton).
---@param settings table
local function applyActiveIcons(settings)
    -- Writes into the buttons' subtree (DenyTaintedAccessWhenAurasAreSecret);
    -- the next Refresh outside secrecy catches up.
    if private.Util.IsAuraAccessBlocked() then return end
    local desat = settings.desaturate_inactive == true
    for i = 1, #spellList do
        local cellIcon = cells[i].cue_Icon
        local texture = desat and cellIcon:GetTexture() or nil
        for rank = 1, 3 do
            local button = chainSlots[rank][i]
            if button then
                button.cue_Icon:SetTexture(texture)
                if texture then button.cue_Icon:SetTexCoord(cellIcon:GetTexCoord()) end
            end
        end
    end
end

---Does the collapsing chain have to be CENTRED on the wrapper?  Only then does
---anything need to know how long the run is.
---@param settings table
---@return boolean
local function isCentred(settings)
    local alignment = settings.layout_alignment or "center"
    return alignment ~= "left" and alignment ~= "right"
        and alignment ~= "top" and alignment ~= "bottom"
end

---Chain geometry from the layout settings: the point each link joins on, the
---point on the link BEFORE it, the gap between them, and the CROSS-axis point
---the whole run hangs off.
---
---Both points are CORNERS, and that is the fix for a run that sits too low.
---`placeGrid` pins a horizontal row to the wrapper's `vEdge` — the edge opposite
---`overflow_direction` — and only centres along the RUN axis; the cross axis is
---always an edge, never a midpoint.  A mid-height `LEFT` here instead centred the
---run on BOTH axes, so the chain hung half a box below where the grid drew it.
---Same rule rotated for a vertical run (`hEdge`).
---
---`myPt` doubles as the corner the run starts from, so the chain grows away from
---the alignment edge; a centred run starts at that corner of the bounds frame
---instead, which `applyChainBounds` has already pinned by `crossPt`.
---@param settings table
---@return string myPt, string prevPt, number dx, number dy, string crossPt
local function chainLeadPoint(settings)
    local pad = settings.icon_offset or 1
    local alignment = settings.layout_alignment or "center"
    if (settings.layout_direction or "horizontal") == "vertical" then
        -- placeGrid's vertical default is overflow_direction "right".
        local hEdge = (settings.overflow_direction == "left") and "RIGHT" or "LEFT"
        if alignment == "bottom" then
            return "BOTTOM" .. hEdge, "TOP" .. hEdge, 0, pad, hEdge
        end
        return "TOP" .. hEdge, "BOTTOM" .. hEdge, 0, -pad, hEdge
    end
    -- placeGrid's horizontal default is overflow_direction "bottom".
    local vEdge = (settings.overflow_direction == "top") and "BOTTOM" or "TOP"
    if alignment == "right" then
        return vEdge .. "RIGHT", vEdge .. "LEFT", -pad, 0, vEdge
    end
    return vEdge .. "LEFT", vEdge .. "RIGHT", pad, 0, vEdge
end

---Centre the collapsing chain by letting the ENGINE measure it.
---
---The run length is a function of how many buttons are shown, which is secret.
---`ResizeToBoundsRect` is the one way to consume that without reading it: no
---arguments, no return, so the extents stay engine-side while the bounds frame
---ends up sized to the VISIBLE run — and a single CENTER anchor to the wrapper
---then centres it as a unit.  Hidden children are excluded from the bounds, and
---a collapsed button is a hidden one.  Exactly how `syncContainerLayout` centres
---the groups engine's secret-width blocks; `resizePair` is the same helper, on
---the same per-frame OnUpdate and for the same reason (the engine settles the
---rects from its own OnUpdate, so a same-pass resize reads stale extents).
---
---⚠️ **UNVERIFIED — this needs `GetBoundsRect` to walk DESCENDANTS, not just
---direct children.**  The chain buttons are children of the aura containers,
---which are what the bounds frame actually holds.  Neither the wiki ("resizing a
---frame to match the bounds of its children") nor the generated docs say which,
---and every Blizzard call site is one level deep, so it is settled only in a
---client.  That is why ONLY the centred case takes this path: on a
---direct-children-only engine the symptom is a mis-centred `center` alignment,
---with left/right/top/bottom still on their known-good direct wrapper anchor —
---a readable answer rather than a broken tracker.
---
---The three containers are re-pinned to the bounds frame's leading corner
---because they are its real children: left where a groups-mode pass last put
---them, a stale offset would inflate the bounds even at zero size.
---
---Pinned by `crossPt`, NOT by CENTER: `crossPt` is a cross-axis EDGE point
---("TOP" is centre-x + top-y), so one anchor centres the run and pins the cross
---axis to the wrapper edge in the same call — the run-axis centring we want
---without the cross-axis centring we do not.  Identical to the `pinPt` the
---groups engine derives in `applyContainerFlow`.
---@param settings table
local function applyChainBounds(settings)
    pairFrame:ClearAllPoints()
    if not isCentred(settings) then
        -- syncSlotEngine's own setup, restated here because that runs first and
        -- this pass has to be able to take the frame back off the OnUpdate.
        pairFrame:SetAllPoints(wrapper)
        pairFrame:SetScript("OnUpdate", nil)
        return
    end
    local myPt, _, _, _, crossPt = chainLeadPoint(settings)
    container:ClearAllPoints()
    container:SetPoint(myPt, pairFrame, myPt)
    targetContainer:ClearAllPoints()
    targetContainer:SetPoint(myPt, pairFrame, myPt)
    targetHelpfulContainer:ClearAllPoints()
    targetHelpfulContainer:SetPoint(myPt, pairFrame, myPt)
    pairFrame:SetPoint(crossPt, wrapper, crossPt)
    pairFrame:SetScript("OnUpdate", resizePair)
end

---Anchor the allocated slot buttons for the engine that is running.
---
---**Grid** (the shipped always-show engine): every button sits on its chrome
---cell, which `layoutSlotCells` has already placed, so this only has to restore
---that binding after a chain pass.
---
---**Chain** (`collapse_layout`, [EXPERIMENTAL]): the buttons anchor to EACH
---OTHER and carry `SetCollapsesLayout(true)`, so a button the engine hides
---closes its own gap and the ones behind it slide up — compaction with per-spell
---identity, on anchors we own rather than Blizzard's flow layout.  The chrome
---moves onto the button for the same reason (`cue_slot` cleared, `cue_spellID`
---set, both read by `restyleButton`): a cell would stay drawn in the gap its
---button just closed.
---
---SPELL-major: each index's player, target-HARMFUL and target-HELPFUL buttons
---in turn, so player and target auras interleave in Tracking-tab order — the
---one thing the groups engine cannot do, since each container is one flow
---block.  Totem icons (`show_totems`) lead, as they lead the groups run.
---
---Chain gotchas, all live-verified — see patterns-auracontainer.md
---"Collapsing a slot chain":
---  * the head needs a frame that never collapses (`chainOrigin`), and the chain
---    must NOT close back onto it — that is two-point anchoring, and the last
---    link lands on top of the previous one;
---  * `GetPoint`/`GetLeft` deliberately report UNCOLLAPSED geometry, which is
---    very likely why this is legal on a button whose shown state is secret:
---    the display compacts while no readable coordinate moves;
---  * one chain is one LINE.  `max_per_row` / `max_width` wrap and cannot be
---    served here.
---
---A centred run is centred by the engine (`applyChainBounds`); whether its
---bounds walk reaches the buttons, which are grandchildren of `pairFrame`, is
---unverified.
---@param settings table
---@param chain boolean  run the collapsing chain instead of the static grid
local function applySlotAnchors(settings, chain)
    local w, h = iconDims(settings)
    -- Everything the pass APPLIES, not just the list it walks: the chain writes
    -- direction, alignment, size and spacing into the buttons, so a signature
    -- over the spells alone would skip a live edit to any of them.
    local sig = table.concat({
        chain and "c" or "g",
        settings.layout_direction or "horizontal",
        settings.layout_alignment or "center",
        settings.overflow_direction or "",
        w, h, settings.icon_offset or 1, totemCount,
        table.concat(spellList, ","),
    }, "|")
    if lastAnchorSig == sig then return end
    -- Both branches write geometry into the aura buttons' subtree, and end in a
    -- restyle that writes their regions; that subtree carries
    -- DenyTaintedAccessWhenAurasAreSecret.  Retried on the next pass outside
    -- secrecy — the signature is deliberately NOT stamped here.
    if private.Util.IsAuraAccessBlocked() then return end
    lastAnchorSig = sig

    local myPt, prevPt, dx, dy = chainLeadPoint(settings)
    -- Centred runs start from the BOUNDS frame, which the engine sizes to the
    -- visible chain (applyChainBounds); every other alignment pins straight to
    -- the wrapper edge, which needs no measurement at all.
    chainOrigin:ClearAllPoints()
    chainOrigin:SetPoint(myPt, chain and isCentred(settings) and pairFrame or wrapper, myPt)

    local prev = chain and chainTotems(myPt, prevPt, dx, dy, chainOrigin) or chainOrigin
    -- Every ALLOCATED slot, not just the live ones: a surplus slot carries the
    -- never-matching filter and is therefore hidden, so it collapses out of the
    -- chain on its own — but only if it is IN the chain.
    local n = math.max(#chainSlots[1], #chainSlots[2], #chainSlots[3])
    for i = 1, n do
        for rank = 1, 3 do
            local button = chainSlots[rank][i]
            if button then
                button:ClearAllPoints()
                if chain then
                    button.cue_slot = nil
                    button.cue_spellID = spellList[i]
                    button:SetSize(w, h)
                    if prev == chainOrigin then
                        button:SetPoint(myPt, prev, myPt)
                    else
                        button:SetPoint(myPt, prev, prevPt, dx, dy)
                    end
                    button:SetCollapsesLayout(true)
                    prev = button
                else
                    button.cue_slot = true
                    button.cue_spellID = nil
                    button:SetCollapsesLayout(false)
                    button:SetAllPoints(cells[i])
                end
            end
        end
    end

    -- The two flags above only decide which chrome `restyleButton` draws; the
    -- draw itself is the restyle pass, so a mode flip has to request one.
    private.AuraContainer.MarkDirty(name)
end

---Re-evaluate proc_glow across both sections.  Slots-only (see SyncProcGlow);
---under groups the lists are empty, which stops every glow.  Needs no CDM
---bridge — IsSpellOverlayed answers from the spell ID alone.
---@param settings table
local function applyProcGlow(settings)
    -- Chain mode excluded: the glow is a LibCustomGlow effect on the chrome
    -- CELL, and the chain hides every cell.  Moving it onto the button would put
    -- LibCustomGlow's own frames inside a subtree carrying
    -- DenyTaintedAccessWhenAurasAreSecret, which is a separate problem.
    local on = usingSlots and not usingChain
        and (settings.proc_glow_style or "blizzard") ~= "none"
    private.AuraContainer.SyncProcGlow(cells, spellList, on, settings)
end

---Re-evaluate the CDM `OnAuraApplied` **Visual** alert across every acquired
---button, in whichever engine is running.
---
---It needs one thing the plain groups engine cannot give — which spell a button
---holds — and BOTH other engines can: slots from `slotButtonIndex`, per-spell
---groups from the `cue_spellID` the candidate filter lets `makeInit` stamp
---(patterns-auracontainer.md "One group PER SPELL").  The glow itself is
---engine-agnostic: it is a frame in the button's subtree, like `active_glow`,
---not a LibCustomGlow effect on an unrestricted cell like `proc_glow` — which is
---why this is NOT slots-only the way `syncProcGlow` is.  A plain-groups button
---has neither key and resolves nil, which hides it.
---
---No feature toggle of its own: this is a replay of what the player configured
---in Blizzard's own Cooldown Manager, gated only by the `cdm_alerts` master
---switch — never by Blizzard's viewer state, since the glow is on our icon — the
---same reason the cooldown-side alerts have no per-component setting.
---
---Gated on aura secrecy: the overlay is a frame in the button's subtree, and that
---subtree carries `DenyTaintedAccessWhenAurasAreSecret`, so a `SetShown` on it
---would throw the forbidden-object error inside an encounter (the live incident
---behind `syncSwapSlots`' identical gate).  An alert therefore starts or stops
---applying on the next pass outside secrecy; a glow already running is
---unaffected, since the ENGINE, not this pass, is what shows and hides it.
---Hoisted rather than written inline at the ForEachTrackedButton call, so the
---pass allocates nothing per Refresh — the same reason the swap slots' two
---initButton closures are hoisted in `Core/IconTracker.lua`.
---@param button frame
local function applyCdmAlertToButton(button)
    local spellID = button.cue_spellID
    if not spellID then
        local index = slotButtonIndex[button]
        spellID = index and usingSlots and spellList[index] or nil
    end
    local visualType = spellID and private.CDMAlerts.GetAuraVisualAlert(spellID) or nil
    private.AuraContainer.ApplyCdmAlertGlow(button, visualType, alertIconWidth)
end

local function applyCdmAlertGlow(settings)
    if private.Util.IsAuraAccessBlocked() then return end
    -- Resolved once per pass into the upvalue the per-button function reads, for
    -- the same reason that function is hoisted at all: ForEachTrackedButton runs
    -- it per button and neither should allocate or re-derive.
    alertIconWidth = (iconDims(settings))
    private.AuraContainer.ForEachTrackedButton(name, applyCdmAlertToButton)
end

---Re-evaluate pandemic_glow.  Unlike the two glows above this works in BOTH
---engines — Blizzard drives the region's visibility, so nothing here has to know
---which button is showing which aura.  pandemic_glow_excludes needs the spell:
---under slots the cell lists supply it per index, under per-spell groups each
---button's `cue_spellID` does (AuraContainer.SyncPandemic).
---@param settings table
local function applyPandemicGlow(settings)
    local on = settings.pandemic_glow == true
    -- Both engines' registries are walked every pass, with the idle one taken
    -- through the off branch — the same "walk everything, let the short list
    -- switch it off" contract the other two glow syncs use.
    private.AuraContainer.SyncPandemic(tracker.name, cells, spellList,
        on and usingSlots, settings)
    private.AuraContainer.SyncPandemic(tracker.name, nil, nil,
        on and not usingSlots, settings)
end

---Switch the slots engine off: every slot takes the never-matching filter and
---the chrome cells are hidden.  Cheap no-op when slots were never allocated.
local function clearSlotEngine()
    private.AuraContainer.SyncSlots(container, SELF_FILTERS, EMPTY_LIST,
        cellForSlot, slotInitFns[1])
    private.AuraContainer.SyncSlots(targetContainer, TARGET_HARMFUL_FILTERS, EMPTY_LIST,
        cellForSlot, slotInitFns[2])
    private.AuraContainer.SyncSlots(targetHelpfulContainer, TARGET_HELPFUL_FILTERS,
        EMPTY_LIST, cellForSlot, slotInitFns[3])
    hideSurplusCells(cells, 0)
    wipe(spellList)
    -- The groups run re-anchors the totem icons (chainTotems), so a chain pass
    -- after it must re-chain them even with nothing else changed.
    lastAnchorSig = nil
end

-- ---------------------------------------------------------------------------
-- Totem icons (`show_totems`)
-- ---------------------------------------------------------------------------
--
-- The icon twin of AuraBarTracker's totem rows; read the block there and
-- Core/AuraTrackers.md "Summons" before changing this one.  A summon occupies a
-- TOTEM SLOT and applies no aura, so no aura engine fills its CDM entry.  One
-- icon per slot reaches it because it never asks which spell is in which slot.
--
-- Every totem value is secret and goes straight into an engine sink.  The one
-- branch is `if duration then` on GetTotemDuration(slot): nil for an empty
-- slot, and never itself secret.  `haveTotem` is piped into
-- SetAlphaFromBoolean and never tested; adding one such test breaks the block.
--
-- Built to be deleted with the bar rows once AuraContainers get a totem API:
-- one default-off key and no settings of its own.
--
-- The icons lead the tracker's own run, before the player buffs (the user's
-- call, 2026-09-30): the head of the groups engine's collapsing chain
-- (chainTotems), or the first cells of the always-show grid (layoutSlotCells).
-- `totemCells` / `totemCount` are declared with the other layout state up top.

---totemCount at the last anchor notification (Refresh).
local lastTotemCount = 0

---Icons laid out for the totem slots: every slot, occupied or not.  Placing
---waits for combat to end while a summon lands mid-fight, and Show/Hide does
---not, so each slot's icon is placed in advance and shown when it fills (the
---groups engine's chain then closes the gaps; the grid keeps them).
---@param settings table
---@return number
local function totemRowCount(settings)
    if not settings.show_totems then return 0 end
    return GetNumTotemSlots()
end

---Create or return the icon for `slot`.
---@param slot number
---@return frame
local function totemCellFor(slot)
    local cell = totemCells[slot]
    if cell then return cell end
    -- A child of the bounds frame, like the aura blocks it leads: resizePair's
    -- bounds then include it, so the centring covers the whole run.
    cell = CreateFrame("Frame", prefix .. "_Totem" .. slot, pairFrame)
    -- Read by restyleButton, which skips the two aura-only calls for it.
    cell.cue_totem = true
    cell.cue_Icon = cell:CreateTexture(nil, "ARTWORK")
    cell.cue_Icon:SetAllPoints(cell)
    -- The buff icon's cooldown (initSlotButton): 0.7 black swipe, no edge, aura
    -- countdown rounding.  Direction, swipe and text toggles are restyleButton's.
    cell.cue_Cooldown = CreateFrame("Cooldown", prefix .. "_Totem" .. slot .. "_Cooldown", cell, "CooldownFrameTemplate")
    cell.cue_Cooldown:SetAllPoints(cell)
    cell.cue_Cooldown:SetSwipeColor(0, 0, 0, 0.7)
    cell.cue_Cooldown:SetDrawEdge(false)
    cell.cue_Cooldown:SetUseAuraDisplayTime(true)
    -- The countdown is the cooldown's own, run from the DurationObject; its
    -- first region is the FontString timer_font styles.
    cell.cue_Timer = cell.cue_Cooldown:GetRegions()
    -- Natural expiry fires no PLAYER_TOTEM_UPDATE; Blizzard's buff icon catches
    -- it the same way (CooldownViewerBuffIconItemMixin:OnCooldownDone).  Never
    -- re-feeds the cooldown: that could restart the one being reported on.
    -- A slot still holding a duration as the swipe ends gets its alpha from
    -- haveTotem again, which is only as good as the slot's state at that
    -- moment: whether it has cleared by then is open (Blizzard's own comment,
    -- CooldownViewerCooldownItemMixin:OnCooldownDone, "No external event is
    -- dispatched when a totem finishes"; #57).  No poll or deferral papers
    -- over it (.context/memory/feedback_no_deferred_calls.md).
    cell.cue_Cooldown:SetScript("OnCooldownDone", function()
        if not GetTotemDuration(slot) then
            cell:Hide()
        else
            cell:SetAlphaFromBoolean((GetTotemInfo(slot)))
        end
    end)
    totemCells[slot] = cell
    return cell
end

---Pipe every reserved slot into its icon.  Runs on PLAYER_TOTEM_UPDATE and
---from each layout.
local function updateTotemCells()
    for slot = 1, totemCount do
        local cell = totemCells[slot]
        -- The generated docs say this return is never nil; for an empty slot it
        -- is, and the sink rejects nil.
        local duration = GetTotemDuration(slot)
        if duration then
            local haveTotem, _, _, _, icon = GetTotemInfo(slot)
            -- The alpha write stands in for the `if haveTotem` addon code cannot
            -- make.  Everything that IS known (an empty slot) is a real Hide().
            cell:SetAlphaFromBoolean(haveTotem)
            cell.cue_Icon:SetTexture(icon)
            -- SetTexture resets the crop (patterns.md).
            cell.cue_Icon:SetTexCoord(private.Util.GetIconZoomCoords(cell:GetSize()))
            cell.cue_Cooldown:SetCooldownFromDurationObject(duration)
            cell:Show()
        else
            cell:Hide()
        end
    end
end

---Ready the totem icons for this Refresh's layout: count, create, restyle, and
---the event.  Runs BEFORE the engine layout, which places them at the head of
---its run (chainTotems / layoutSlotCells); updateTotemCells pipes them after.
---
---Restyled only when the aura buttons are (patterns.md "fontsDirty"): the font
---flag or a RESTYLE_KEYS value that moved, read here without advancing
---`lastRestyleGeom`, which Refresh's restyle gate still owns — plus a new icon.
---Not through AuraContainer.TrackButton: its registry also feeds the CDM alert
---walk (ForEachTrackedButton), which expects aura buttons.  Restyling before
---placement matters on the grid, where placeCell then sizes an overflow cell.
---@param settings table
local function prepareTotemCells(settings)
    local n = totemRowCount(settings)
    for i = n + 1, #totemCells do totemCells[i]:Hide() end
    totemCount = n
    if n == 0 then
        auraEvents:UnregisterEvent("PLAYER_TOTEM_UPDATE")
        return
    end
    local due = private.fontsDirty
    for i = 1, #RESTYLE_KEYS do
        local k = RESTYLE_KEYS[i]
        if lastRestyleGeom[k] ~= settings[k] then due = true end
    end
    for i = 1, n do
        local fresh = totemCells[i] == nil
        -- Size, border, crop, swipe and timer font, as on a buff icon.  Before
        -- the pipe: SetReverse must precede the swipe it applies to.
        local cell = totemCellFor(i)
        if due or fresh then restyleButton(cell, settings) end
    end
    auraEvents:RegisterEvent("PLAYER_TOTEM_UPDATE")
end

-- ---------------------------------------------------------------------------
-- Component lifecycle
-- ---------------------------------------------------------------------------

tracker.Initialize = function()
    -- Register dirty-flag restyle BEFORE makeInit so the initial acquire
    -- styling path in makeInit finds the restyleFn in trackerState.
    private.AuraContainer.RegisterTracker(name, restyleButton)

    -- Component/anchor-facing frame: addon-owned rect, nothing anchors it to the
    -- (secret-sized) bounds frame below, so its rect never goes secret.
    -- `config.parent` is how an Additional Frame hands over its ALREADY
    -- anchor-managed container: the AF owns positioning (anchor_profile, cursor
    -- follow, EditMode), so the tracker fills it rather than becoming a second
    -- top-level frame competing for the same component name.  The primary
    -- tracker passes no parent and owns its own wrapper.
    local host = config.parent
    wrapper = CreateFrame("Frame", prefix .. "_Container", host or UIParent)
    if host then
        wrapper:SetAllPoints(host)
    end

    -- Bounds frame enclosing BOTH containers.  Frame:ResizeToBoundsRect() sizes
    -- it to its children engine-side — no arguments, no return, so the secret
    -- block extents never cross into Lua — and the frame is then centred on the
    -- wrapper as a unit.  Size comes from the children, position from the single
    -- anchor to `wrapper`, so there is no circular dependency.
    -- DisableUntrustedLayoutScriptsTemplate is REQUIRED, not decoration:
    -- AddAuraGroup stamps Enum.ForbiddenAspect.UntrustedLayoutScriptExecution on
    -- the container (Blizzard_CustomAuraContainer.lua:321), and Blizzard's own
    -- comment there says addon frames that participate with such a container
    -- must inherit this template to opt in (:318).  ResizeToBoundsRect over
    -- those children is exactly such a layout script.  Coolinator applies it the
    -- same way to its `sizeAssistant` frame (Display/AuraIconNext.lua:50).
    -- Native containers only: the template and the aspect it opts out of are
    -- 12.1, and an emulated (classic) container stamps nothing.
    pairFrame = CreateFrame("Frame", prefix .. "_Pair", wrapper,
        LAC.IsNative and "DisableUntrustedLayoutScriptsTemplate" or nil)

    -- Head of the collapsing chain (applySlotAnchors).  Sizeless and never
    -- hidden: a collapsing frame closes its gap by resolving through to what it
    -- anchors to, so the first link needs a landing point that does neither.
    --
    -- DisableUntrustedLayoutScriptsTemplate for the same reason `pairFrame` has
    -- it, and it is REQUIRED, not defensive: a centred chain anchors this to
    -- `pairFrame`, which carries UntrustedLayoutScriptExecution, and anchoring is
    -- refused outright when the dependent would INHERIT a forbidden aspect it has
    -- not opted into ("Anchoring disallowed as dependent object would inherit
    -- forbidden aspects", live 2026-09-09).  The template is that opt-in.
    -- Nothing to do with combat or aura state -- it is a static property of the
    -- frame, so the failure is on the first centred pass and every one after.
    chainOrigin = CreateFrame("Frame", nil, wrapper,
        LAC.IsNative and "DisableUntrustedLayoutScriptsTemplate" or nil)
    chainOrigin:SetSize(0.001, 0.001)

    -- Both containers are direct children of the bounds frame: a container has
    -- exactly one unit, so the target section needs its own.
    container = private.AuraContainer.CreateContainer(prefix .. "_Container_Aura", pairFrame)
    targetContainer = private.AuraContainer.CreateContainer(prefix .. "_TargetContainer_Aura", pairFrame)
    targetContainer:SetUnit("target")
    -- Same unit as targetContainer; separate ONLY so the helpful block can be
    -- hidden on its own when the player targets themself.
    targetHelpfulContainer = private.AuraContainer.CreateContainer(
        prefix .. "_TargetHelpfulContainer_Aura", pairFrame)
    targetHelpfulContainer:SetUnit("target")
    -- Disabled, not only hidden, while a target filter's identity gate fails:
    -- a hidden container keeps the last target's matches, and missing_glow's
    -- masks ignore their parent's visibility, so a frozen match would keep
    -- erasing a glow (AuraContainer.GateOnIdentity).  Re-armed on every
    -- reaction edge in the handler below.
    private.AuraContainer.GateOnIdentity(targetContainer, PLAYER_HARMFUL)
    private.AuraContainer.GateOnIdentity(targetHelpfulContainer, PLAYER_HELPFUL)

    -- SetUnit early-outs on an unchanged token, so a target SWAP fires no
    -- container-side refresh. UpdateAllAuras is Blizzard's sanctioned external
    -- refresh hook ("e.g. target changes" — Blizzard_AuraContainer.lua).
    --
    -- The proc-glow events are the only per-aura driver left here; Refresh
    -- registers them only while that feature can render.
    auraEvents = CreateFrame("Frame")
    auraEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
    -- A target's reaction can flip with no target change at all (mind control, a
    -- neutral NPC turning), and reaction is what decides which of the two target
    -- filters has a working identity gate.  The player's own flips it just as
    -- well (being mind controlled) and fires UNIT_FACTION for "player" only,
    -- which is why Blizzard's TargetFrame reacts to both units
    -- (TargetFrame.lua:200).
    auraEvents:RegisterUnitEvent("UNIT_FACTION", "target", "player")
    auraEvents:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_TARGET_CHANGED" or event == "UNIT_FACTION" then
            private.AuraContainer.GateOnIdentity(targetContainer, PLAYER_HARMFUL)
            private.AuraContainer.GateOnIdentity(targetHelpfulContainer, PLAYER_HELPFUL)
            targetContainer:UpdateAllAuras()
            targetHelpfulContainer:UpdateAllAuras()
            -- Combat-safe (SetShown on our own frame), which is why this can
            -- run on every target change while Refresh cannot.
            syncSelfTargetSuppression()
            for i = 1, #spellList do
                applyMissingGlowShown(cells[i])
            end
        elseif event == "PLAYER_TOTEM_UPDATE" then
            -- Registered by prepareTotemCells only while show_totems is on.
            updateTotemCells()
        else
            applyProcGlow(getSettings())
        end
    end)

    registerTrackerCallbacks()

    private.CustomSpells.OnEnable(name)

    tracker.Refresh()
end

tracker.GetFrame = function()
    return wrapper
end

---The bounds frame the engine sizes to the VISIBLE blocks — what a bar tracker
---anchored to this one pins its own bounds frame to (AuraBarTracker
---`followTarget`).  Its rect is secret-derived: anchor to it, never read it.
tracker.GetBoundsFrame = function()
    return pairFrame
end

tracker.Refresh = function()
    if not container then return end

    if not getEnabled() and not private.isEditMode then
        if not InCombatLockdown() then
            wrapper:Hide()
        end
        return
    end

    -- AuraContainer API calls (SyncGroup, layout setters) are restricted in combat.
    -- The container continues to display existing auras internally; the
    -- combat-exit layout pass catches up by running this Refresh as ContentLayout.
    -- That pass has no font pass, so a font edited mid-fight goes on the
    -- persistent restyle flag now (MarkDirty only sets it).
    if InCombatLockdown() then
        if private.fontsDirty then private.AuraContainer.MarkDirty(name) end
        return
    end

    local settings = getSettings()
    local spellMap = buildSpellMap()
    spellCount = 0
    for _ in pairs(spellMap) do spellCount = spellCount + 1 end

    -- Display mode: always_show_tracked.  It used to be Blizzard's viewer
    -- "Hide when inactive" setting with this as a CUE-side opt-in on top; that
    -- setting is now copied once into always_show_tracked
    -- (pm.MigrateHideWhenInactive) and never read again.  The default engine is
    -- groups, where the button↔aura binding is secret and every per-spell feature
    -- (icon_overrides, active_glow, proc_glow, spell_colors, the layout modes) is
    -- inert.
    -- [EXPERIMENTAL] Collapsing slot chain: slots for the identity, our own
    -- anchors for the compaction.  Always Show's grid outranks it.
    usingChain = CHAIN_ENABLED and settings.collapse_layout == true
        and not tracker.IsUsingSlots()
    usingSlots = tracker.IsUsingSlots() or usingChain

    -- Per-spell unit scope: which of the three groups each tracked spell may
    -- appear in.  Independent of the self-target suppression below — this is the
    -- user's "only ever a self-buff / only ever on the target" restriction.
    -- Expanded ONCE per Refresh and shared with the slots engine, so both
    -- engines resolve a spell's scope identically.
    local scopeMap = private.AuraContainer.ExpandUnitScope(settings.aura_unit)
    local playerMap, targetHarmfulMap, targetHelpfulMap =
        private.AuraContainer.SplitByUnitScope(spellMap, scopeMap)

    -- Per-spell groups: the compacting engine WITH identity — one group per
    -- spell, so a button's spell is known from its group's candidate filter
    -- instead of from a forbidden read (Core/AuraContainer.lua "Per-spell groups
    -- engine").  Recovers icon_overrides / active_glow / spell_colors and the CDM
    -- visual alert under compaction; the layout-shaped gaps stay slots-only,
    -- since Blizzard still owns the flow and the container rect is still secret.
    --
    -- UNCONDITIONAL since 2026-09-09.  It shipped behind a `per_spell_groups`
    -- toggle while it was experimental, and there was never a reason to prefer
    -- the plain group: identity is strictly extra, the compaction is Blizzard's
    -- either way, and `maxFrameCount = 1` makes each group exactly one icon.  The
    -- toggle and its profile key are gone; the plain-group path stays as the
    -- always-EMPTY_MAP branch below, which is what keeps one engine holding
    -- frames at a time.
    local usingSpellGroups = not usingSlots

    -- The idle engines take the never-matching include map, so exactly one is
    -- ever holding frames.  None has a public removal API; an empty
    -- includeSpellIDs is the sanctioned off switch.
    local layoutOpts = buildLayoutOpts(settings)
    -- No plain single group here at all.  With per-spell groups unconditional,
    -- `usingSlots or usingSpellGroups` was a tautology, so the three SyncGroup
    -- calls this file used to make could only ever pass EMPTY_MAP -- and
    -- `AddAuraGroup` allocates a batch of frames UNCONDITIONALLY, before it even
    -- reads maxFrameCount (`frameProvider:CreateFrameBatch()`,
    -- Blizzard_CustomAuraContainer.lua:301, batch size 10 at
    -- Blizzard_AuraContainerShared.lua:105).  Three never-matching groups
    -- therefore cost 30 pooled AuraButtons per tracker, each one running
    -- makeInit and entering the restyle registry.  Not calling them at all is
    -- the off switch when a group was never created in the first place.
    --
    -- `AuraBarTracker` still uses SyncGroup: it has no per-spell engine.

    local sgPlayer, sgHarmful, sgHelpful = EMPTY_MAP, EMPTY_MAP, EMPTY_MAP
    if usingSpellGroups then
        sgPlayer, sgHarmful, sgHelpful = playerMap, targetHarmfulMap, targetHelpfulMap
    end
    -- One rank for all three: the maps are subsets of spellMap and the ranks are
    -- per-key, so a superset table sorts each of them correctly.  Built here
    -- rather than inside each call because the table is reused -- see
    -- Util.BuildSpellOrderRank.
    local orderRank = private.Util.BuildSpellOrderRank(name, spellMap)
    private.AuraContainer.SyncSpellGroups(container, name .. "_sg",
        PLAYER_HELPFUL, sgPlayer, identitySetFor,
        spellInitFor, layoutOpts, orderRank)
    private.AuraContainer.SyncSpellGroups(targetContainer, name .. "_sg",
        PLAYER_HARMFUL, sgHarmful, identitySetFor,
        spellInitFor, layoutOpts, orderRank)
    private.AuraContainer.SyncSpellGroups(targetHelpfulContainer, name .. "_sg",
        PLAYER_HELPFUL, sgHelpful, identitySetFor,
        spellInitFor, layoutOpts, orderRank)

    -- Before either engine: both place the totem icons at the head of their run.
    prepareTotemCells(settings)
    if usingSlots then
        syncSlotEngine(spellMap, scopeMap)
        if usingChain then
            -- The chain draws its chrome on the buttons; a cell would stay
            -- visible in the gap its button just closed.
            hideSurplusCells(cells, 0)
            -- Unconditional, unlike applySlotAnchors below: syncSlotEngine puts
            -- the bounds frame back on the wrapper every pass, and the guarded
            -- anchor pass would leave centring off from the first unchanged
            -- Refresh onward.
            applyChainBounds(settings)
        else
            layoutSlotCells(settings)
        end
        applySlotAnchors(settings, usingChain)
    else
        clearSlotEngine()
        syncContainerLayout(settings)
    end
    -- After the placement: the grid Show()s every cell it places, and an empty
    -- slot's icon has to end up hidden.
    updateTotemCells()

    -- Settle the self-target state here too: PLAYER_TARGET_CHANGED covers every
    -- transition, but a login or profile switch with the player already
    -- self-targeted fires no such event.
    syncSelfTargetSuppression()

    -- active_glow needs no event driver and no pass here: its border is bound
    -- into the aura button's subtree, so Blizzard's own show/hide of the button
    -- is the glow.  restyleButton carries the on/off and the colour.

    -- proc_glow: its own Blizzard trigger.  Registered only while
    -- the feature can render (slots, style ~= "none"), so a groups-mode or
    -- disabled profile pays nothing.
    if usingSlots and (settings.proc_glow_style or "blizzard") ~= "none" then
        auraEvents:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        auraEvents:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    else
        auraEvents:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        auraEvents:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    end
    applyProcGlow(settings)

    -- The CDM's own Visual alert, replayed as a persistent glow.  No event
    -- driver either, and for a stronger reason than pandemic_glow's: there IS no
    -- aura-application event an addon can see, so the engine's show/hide of the
    -- slot button is used as the trigger instead.
    applyCdmAlertGlow(settings)

    -- pandemic_glow: no event driver at all — Blizzard's own OnUpdate on the
    -- aura button decides when the region shows.  This pass only carries the
    -- style/colour/exclude configuration onto the overlays.
    applyPandemicGlow(settings)

    -- Bridge the Options/EditMode font-setter contract (patterns.md
    -- "fontsDirty") into the AuraContainer dirty-restyle path: without this,
    -- MarkDirty only fires on profile change and live font edits never apply.
    --
    -- The geometry/feature keys the restyle pass owns reach the buttons the
    -- same way, so a setter that forgets to raise the flag writes the profile
    -- and changes nothing until a /reload.  Detect a move here rather than
    -- trusting ~20 call sites across Options, EditMode and the Additional
    -- Frame panel — the guard IconTracker already uses for its slot style.
    local geomChanged = false
    for i = 1, #RESTYLE_KEYS do
        local k = RESTYLE_KEYS[i]
        if lastRestyleGeom[k] ~= settings[k] then
            lastRestyleGeom[k] = settings[k]
            geomChanged = true
        end
    end
    if private.fontsDirty or geomChanged then
        private.AuraContainer.MarkDirty(name)
    end
    private.AuraContainer.RestyleIfDirty(name, settings)
    -- AFTER the restyle, which crops every button icon to icon_size: an
    -- overflow cell is a different size, and the copy has to match its cell.
    if usingSlots and not usingChain then
        applyActiveIcons(settings)
    end

    local shouldShow = (getEnabled() or private.isEditMode)
        and private.Anchor.IsVisibleForComponent(tracker.name)
    if shouldShow then
        local alpha = private.Anchor.GetEffectiveAlpha(tracker.name)
        wrapper:SetAlpha(alpha)
        wrapper:Show()
    else
        -- A real Hide(), not alpha 0: the wrapper is not protected, and Anchoring
        -- lays it out in combat, so the pass that makes it visible again can
        -- Show() it (Core/Anchoring.lua `secureComponents`).
        wrapper:Hide()
    end

    -- Notify anchoring system only when collapsed state changes so anchor children
    -- re-resolve their parent (collapse past or anchor to this frame).  Under
    -- slots the reported size is content-derived, so a spell-count change moves
    -- the box too — rare (talents / spec / CDM config), never a combat path.
    -- Both trackers are updated BEFORE the call so the re-entrant Refresh it
    -- triggers sees no further transition.
    local nowCollapsed = tracker.IsCollapsed()
    -- The totem line moves the box in either engine (GetComponentSize), with the
    -- key and with GetNumTotemSlots.
    if nowCollapsed ~= wasCollapsed or (usingSlots and spellCount ~= lastSlotCount)
        or totemCount ~= lastTotemCount then
        wasCollapsed = nowCollapsed
        lastSlotCount = spellCount
        lastTotemCount = totemCount
        private.Anchor.OnComponentStateChange()
    end
end

tracker.ContentLayout = tracker.Refresh

---Lightweight alpha sync for anchor inheritance.  Alpha only: showing and
---hiding the wrapper is the layout pass's job.
tracker.SyncAlpha = function()
    if not wrapper then return end
    local alpha = private.Anchor.IsVisibleForComponent(tracker.name)
        and private.Anchor.GetEffectiveAlpha(tracker.name) or 0
    wrapper:SetAlpha(alpha)
end

---Reads getSettings() rather than getEnabled(): a HOSTED tracker's settings row
---is `private.profile.additional_frames[id]`, and both AF teardown paths remove
---that row while this handler is still pending, so getEnabled()'s
---`getSettings().enabled` would index nil.  manager.DeleteFrame calls
---deactivateFrame(id) (which registers this) and only THEN nils the row;
---manager.OnProfileChanged runs its deactivate loop over the OLD ids after AceDB
---has already swapped private.profile, so an id absent from the new profile
---reads nil too.  The error would land inside Callback.Trigger("OnLeaveCombat"),
---which has no pcall, aborting the dispatch for every handler after this one.
---An absent row means the frame is gone, i.e. not enabled — hide.
local deferredDisableHide
deferredDisableHide = function()
    private.Callback.Unregister("OnLeaveCombat", deferredDisableHide)
    local settings = getSettings()
    if wrapper and not (settings and settings.enabled) and not private.isEditMode then
        wrapper:Hide()
    end
end

tracker.OnEnable = function()
    -- Paired with OnDisable's unregister.  Both are idempotent, so the primaries
    -- -- which get OnEnable on every profile switch via FullLayoutRefresh -- pay
    -- nothing at steady state, and a hosted tracker that is re-enabled after a
    -- disable gets its bus handlers back instead of going silently deaf.
    registerTrackerCallbacks()
    -- OnDisable takes auraEvents down wholesale, so the two PERMANENT
    -- registrations have to be restored here.  The proc-glow pair deliberately is
    -- not: Refresh owns it and re-arms it from the live settings.
    if auraEvents then
        auraEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
        auraEvents:RegisterUnitEvent("UNIT_FACTION", "target", "player")
    end
    if private.CustomSpells then
        private.CustomSpells.OnEnable(name)
    end
    if wrapper and not InCombatLockdown() then
        wrapper:Show()
        tracker.Refresh()
    end
end

---Undo everything that would otherwise outlive this tracker.  A HOSTED
---(Additional Frame) instance is discarded on every delete and every profile
---switch — activateFrame builds a fresh instance table — and WoW never garbage
---collects a frame, so anything left armed here keeps running for the rest of
---the session:
---  * the three internal-callback registrations;
---  * the CDM aura-event alert registration (Core/CDMAlerts.lua) — every
---    AddAuraSound id this tracker holds, or a deleted AF's spells keep
---    playing a sound forever, same class of leak as the callbacks above;
---  * every auraEvents registration.  The OnEvent closure's else arm calls
---    applyProcGlow(getSettings()), and applyProcGlow indexes that argument on
---    its first line, so a deleted AF's proc-glow event errors once per event
---    forever.  Refresh re-arms the glow pair on its own, so only the two
---    permanent registrations come back in OnEnable.
---  * the bounds frame's resize OnUpdate, which UnregisterAllEvents does NOT
---    clear — the trap Core/IconTracker.lua records at its spellWatcher
---    teardown.  Self-limiting while the wrapper is hidden; the combat branch
---    below is exactly the window where it is not.
---  * all three AuraContainers.  AuraContainer.Create ends in SetEnabled(true)
---    and the only other disable path (setContainerDemand) is reachable solely
---    from a Refresh a torn-down tracker never receives, so each abandoned set
---    keeps parsing on every UNIT_AURA for its unit — ParseAuras early-returns
---    only on a DISABLED container.  Engine-side, so Lua memory sampling and
---    /cueperf show nothing.  Not combat-guarded, for the reasons spelled out at
---    Core/IconTracker.lua's matching block.
---
---`Suspend` wipes the demand record rather than writing `false`, so the next
---sync re-enables the container by itself — deliberately no OnEnable counterpart.
tracker.OnDisable = function()
    unregisterTrackerCallbacks()
    if private.CustomSpells then
        private.CustomSpells.OnDisable(name)
    end
    if auraEvents then
        auraEvents:UnregisterAllEvents()
    end
    if pairFrame then
        pairFrame:SetScript("OnUpdate", nil)
    end
    if wrapper then
        if InCombatLockdown() then
            -- Refresh's disabled branch used to catch this up on the next combat
            -- transition; no such transition reaches a tracker whose callbacks
            -- were just unregistered.
            private.Callback.Register("OnLeaveCombat", deferredDisableHide)
        else
            wrapper:Hide()
        end
    end
    if container then
        private.AuraContainer.Suspend(container)
        private.AuraContainer.Suspend(targetContainer)
        private.AuraContainer.Suspend(targetHelpfulContainer)
    end
end

-- ---------------------------------------------------------------------------
-- Accessors
-- ---------------------------------------------------------------------------

tracker.GetComponentName = function()
    return tracker.name
end

---The exact map the engine feeds its containers — the source of truth for any
---UI that has to enumerate "spells this tracker handles" (the per-spell
---`aura_unit` list).  Deliberately the live map rather than a re-derivation:
---the two would drift the moment a routing or custom-spell rule changed.
---@return table<number, true>
tracker.GetTrackedSpells = buildSpellMap

---Engine-gated.
---
---GROUPS (hide-when-inactive): FIXED SIZE.  Blizzard's flow layout owns the
---rect and it is secret, so a content-hugging size could only be estimated from
---the MAPPED spell count — which over-reserves permanently (a buff tracker
---usually has most tracked auras inactive) while presenting itself to the
---anchor system as dynamic.  Permanently correct here; nothing else is possible.
---
---SLOTS (always-show): content-hugging, matching the icon trackers.  Every cell
---is ours and always shown, so the mapped count IS the rendered count and the
---extent is plain arithmetic — the secret container rect stops mattering.
tracker.GetWantsContentWidth = function()
    if not usingSlots then return false end
    local settings = getSettings()
    if (settings.layout_direction or "horizontal") == "vertical" then return true end
    local mode = settings.frame_size_mode or "max_width"
    if mode == "max_per_row" then return true end
    if mode == "max_width" and settings.icon_size and settings.icon_size > 0 then return true end
    return false
end

---Returns true when nothing is tracked.  Reserved totem icons are content: a
---tracker showing only totems is not collapsed.
tracker.IsCollapsed = function()
    return spellCount + totemRowCount(getSettings()) == 0
end

---Collapsed (nothing tracked) reports 0, 0 in either engine so the anchor
---system can close the gap entirely.
---
---Under SLOTS the box is the real grid extent, straight from the same
---computeGridGeometry the placement used — so the estimate and the layout can
---never disagree.
---
---Under GROUPS it is the CONFIGURED size, not a content estimate (see
---GetWantsContentWidth).  The internal container rects are engine-sized and the
---target block chains onto the player block, so nothing here estimates them.
---
---Totem icons (`show_totems`) lead the run in either engine: under SLOTS they
---are grid cells and count as such, under GROUPS they sit inside the
---configured box like the aura blocks.
tracker.GetComponentSize = function()
    local settings = getSettings()
    local n = spellCount + totemRowCount(settings)
    if n == 0 then return 0, 0 end
    if usingSlots then
        local _, _, _, _, _, gw, gh = private.IconTracker.ComputeGridGeometry(
            settings, n, tracker.name)
        return gw, gh
    end
    local w = settings.width or 400
    local minWidth = settings.min_width or 0
    if minWidth > 0 then w = math.max(w, minWidth) end
    local avail = private.Anchor.GetInheritedWidth(tracker.name)
    if avail and avail > 0 and w > avail then w = avail end
    return w, settings.height or 100
end

    return tracker
end

---@type auraicontrackerfacade
private.AuraIconTracker = {
    CreateTracker = createTracker,
}

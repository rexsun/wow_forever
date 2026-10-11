
--[[
    Aura bar tracker FACTORY — renders buff/proc aura progress bars via
    AuraContainer (WoW 12.1+).  `CreateTracker(config)` builds one independent
    instance; every consumer gets its own containers, cells and event driver.

    Consumers:
      - Components/BuffTrackerBars.lua  — the primary tracker, spells from CDM
        category BuffBar minus Additional-Frame-routed ones, plus custom spells
      - Core/AdditionalFrameManager.lua — one instance per `bar`-type Additional
        Frame, spells from that frame's own assigned_spells

    Extracted so Additional Frames get REAL aura containers.  They previously
    cross-parented live CDM viewer children, which cannot work on 12.1: nothing
    re-runs an AF layout when a child's shown state flips, and the compaction
    that drives it is secret.  See .context/patterns-auracontainer.md.

    Three aura groups across two containers (a container has exactly ONE unit;
    per-group SetUnit is deferred to 12.1.5, so this split is the architecture
    for the whole 12.1 cycle):
      - player container:  <name>_main           HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY
      - target container:  <name>_target_harmful HARMFUL|PLAYER
                           <name>_target_helpful HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY
    ONE spell map feeds all three; the filter strings decide where an aura can
    land, exactly as Blizzard's own CDM does.

    Each AuraButton renders as: [icon | status-bar-fill + name text | timer].
    Blizzard drives the status-bar fill level via SetDurationBar and the spell
    name via SetSpellName; both update automatically on UNIT_AURA.

    SetDurationBar and SetDurationText on plain StatusBar/FontString children are
    live-verified (ensureEbonMightTap, Components/PrimaryResources.lua).
    Unverified: SetSpellName only — it IS bound on the shipped path (buildBarButton,
    two lines from the verified SetDurationBar), so any slots-mode reload exercises
    it; what is unverified is whether the engine-written secret name renders.
--]]

local _
---@type string, private
local addonName, private = ...
local LAC = LibStub("LibAuraContainer-1.0")

---@class private : table
---@field AuraBarTracker aurabartrackerfacade

---@class aurabartrackerfacade
---@field CreateTracker fun(config: table): table

---Build one bar-tracker instance.
---
---**Every piece of state below is a local inside this function**, so each call
---produces fully independent closures — that is what lets one Additional Frame
---instance per `bar` frame own its containers without colliding with the
---primary tracker or with another AF.  A variable accidentally left at MODULE
---scope would silently become shared across instances and would NOT be caught
---by single-instance testing.
---
---@param config table
---  * `name`           component name; also the aura-group key prefix and the
---                     AuraContainer tracker-registry key
---  * `prefix`         global frame-name prefix (e.g. "CUE_BTB")
---  * `parent`         parent frame for the wrapper (defaults to UIParent)
---  * `getSettings`    fun(): table — the profile table for this instance
---  * `buildSpellMap`  fun(): table<number, true> — tracked spells
---@return table tracker
---Settings the dirty-flag restyle pass is the only writer of.  A change to
---any of them must reach the buttons through MarkDirty, so Refresh compares
---them itself instead of relying on every setter to raise private.fontsDirty.
---@type string[]
local RESTYLE_KEYS = {
    "bar_width", "bar_height", "icon_size", "icon_offset",
    "icon_offset_x", "icon_offset_y", "collapse", "show_timer",
    "bar_content", "bar_fill_color", "desaturate_inactive",
}

---Seconds between totem-row polls.  Module scope, not per instance: the
---trackers' own locals are near Lua 5.1's per-function cap.
local TOTEM_POLL = 0.25

---The spell whose icon and NAME a tracked entry displays, which is not the
---entry's key — see the twin in `Core/AuraIconTracker.lua` for the Blizzard
---precedence this reproduces.  Only the slots path needs it: under groups the
---engine writes both through the `SetIcon` / `SetSpellName` binds and already
---uses the live aura.
---@param spellID number
---@return number
local function displaySpellFor(spellID)
    return private.CDMDataSource.GetSwapIconSpell(spellID) or spellID
end

---anchor_side → the bars' own flow anchor that faces BuffTracker from there.
local FOLLOW_EDGE = { top = "BOTTOM", bottom = "TOP" }

---Where the groups engine pins its bounds frame when the bars sit on
---BuffTracker: that tracker's own bounds frame, which the engine sizes to the
---buffs actually showing, instead of its configured box.  Only a column growing
---AWAY from BuffTracker (Top + up, Bottom + down) — any other pin would need the
---bars' own extent, which is secret.  A collapsed or disabled BuffTracker is
---not followed: the anchor system already closes that gap.
---
---Legal because our bounds frame already carries
---DisableUntrustedLayoutScriptsTemplate, so it inherits nothing new; a plain
---frame is refused the same anchor (see the totem block).  Anchoring a pair to
---a pair was verified out of combat 2026-09-30.
---
---ponytail: BuffTracker's bounds frame stops resizing while its wrapper is
---hidden (visibility rules), so bars that stay shown then follow its last
---extent.  Gate on BuffTracker's live visibility if that shows up.
---@param settings table
---@param anchorPt string
---@return frame? bounds, string? relPt, number? x, number? y
local function followTarget(settings, anchorPt)
    local ap = settings.anchor_profile
    if not ap or ap.anchor_parent ~= "BuffTracker" then return nil end
    if FOLLOW_EDGE[ap.anchor_side or "bottom"] ~= anchorPt then return nil end
    local bt = private.ComponentManager.GetComponent("BuffTracker")
    if not bt or not bt.GetEnabled() or bt.IsCollapsed() then return nil end
    local bounds = bt.GetBoundsFrame()
    if not bounds then return nil end
    return bounds, anchorPt == "BOTTOM" and "TOP" or "BOTTOM",
        ap.anchor_offset_x or 0, ap.anchor_offset_y or 0
end

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

---Player-unit AuraContainer frame — created once in Initialize, managed by
---anchor system.
---@type frame?
local container

---Plain wrapper around the player aura container — the component/anchor-facing
---frame (GetFrame/Show/Hide/SetAlpha). Addon-owned rect, safe to anchor to;
---the aura container's own rect is engine-owned and SECRET.
---@type frame?
local wrapper

---Target-unit AuraContainer (SetUnit "target") — carries the HARMFUL target
---group. Same secret-rect rules as the player container.
---@type frame?
local targetContainer

---Second target-unit AuraContainer, carrying the HELPFUL target group alone.
---
---Split out from `targetContainer` purely so it can be hidden independently:
---when the player targets THEMSELF, a self-buff matches both the player
---container's HELPFUL group and this one, and the same aura renders twice.
---Blizzard dodges that by walking `scanUnits` and taking the first match
---(`CooldownViewerItemData.lua:1`) — unavailable to us, because re-pointing a
---group's candidate filters is combat-restricted like every other container
---call (patterns-auracontainer.md) and target changes are constant in combat.
---`SetShown` on our own frame is NOT restricted, so a whole container is the
---granularity at which the duplicate can be suppressed at all.
---@type frame?
local targetHelpfulContainer

---Bounds frame enclosing both aura containers — a CHILD of `wrapper` so it
---inherits Show/Hide/alpha automatically. Sized by `ResizeToBoundsRect` to the
---two blocks it holds, then pinned on `wrapper` as a unit. Its rect is
---secret-derived; never read it.
---@type frame?
local pairFrame

---Chrome rows for the totem/summon display (`show_totems`).  A SEPARATE array
---from `cells`: those are keyed by tracked spell and re-keyed whenever the
---spell list moves, these by totem SLOT and never move.  See the totem block
---below for why the slot keying is load-bearing rather than convenient.
---@type frame[]
local totemCells = {}

---Each totem row's parent, by slot: the link the chain is built from.  Sized
---to the row plus one `bar_spacing` on its leading side and Hide()n while its
---slot is empty, so a collapsed slot takes its spacing out of the run with it.
---@type frame[]
local totemSlots = {}

---Totem rows the last out-of-combat layout placed.  Kept while the key is off,
---so a re-enable in combat can show rows that are already placed.
local totemCount = 0

---Rows placed for the totem display: EVERY slot, occupied or not.
---
---Each slot's row is placed in advance because a summon lands mid-fight and
---`Refresh` places nothing in combat.  `Show`/`Hide` and alpha are available
---then, so a placed row is revealed when its slot fills.
---@param settings table
---@return number
local function totemRowCount(settings)
    if not settings.show_totems then return 0 end
    return GetNumTotemSlots()
end

---Tracked spell count for IsCollapsed / GetComponentSize estimates and the
---groups-mode section stacking offset. Updated on every Refresh.
---One count, not two: both containers hold the same map (see buildSpellMap).
---@type integer
local spellCount = 0

---initializeFrame closure captured for SyncGroup — only used by AddAuraGroup.
---@type function?
local initFn

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
---A spells change that lands mid-fight is lost to Refresh's combat bail, and the
---combat-exit layout pass runs ContentLayout (this Refresh) only for a tracker
---shown then: one hidden by a rule or its parent kept the stale map -- under an
---out_of_combat hide, through the whole next fight.  One-shot, and registered
---only by such a change, never by an in-combat layout pass, so an ordinary
---fight costs nothing.
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
    -- A deleted Additional Frame must not refresh at combat end.
    private.Callback.Unregister("OnLeaveCombat", catchUpAfterCombat)
end

---Which engine this tracker runs: slots (static grid, per-spell identity known)
---or Blizzard's compacting groups (button-to-aura binding is secret, so every
---per-spell feature is inert).  Read here and nowhere else so the layout and the
---Options panel — which hides the inert widgets — cannot disagree.
---@return boolean
tracker.IsUsingSlots = function()
    return getSettings().always_show_tracked == true
end

-- Spell map: injected via config.buildSpellMap.  The primary tracker derives it
-- from a CDM category minus AF-routed spells; an Additional Frame derives it
-- from its own assigned_spells.  Either way it is ONE map fed to BOTH unit
-- containers — the filter strings decide where an aura can land, exactly as
-- Blizzard's own CDM does (`scanUnits = { "player", "target" }`,
-- CooldownViewerItemData.lua:1; `selfAura` is a DB2 field their UI never reads).

-- ---------------------------------------------------------------------------
-- Layout helpers
-- ---------------------------------------------------------------------------

---Item geometry, mirroring the old `Util.LayoutViewerBars` contract:
---`bar_width` is the FULL item width (the icon sits INSIDE it, not beside it),
---percent-mode anchor inheritance replaces it ("follow parent width"), and
---`bar_content == "IconOnly"` collapses the item to `icon_size` **when the
---`collapse` setting is on** — the explicit user choice wins over inherited
---width, but the shrink itself is opt-in: with `collapse = false` an IconOnly
---row renders inside the configured `bar_width` / inherited width, which is the
---master behaviour. Item height is
---`max(bar_height, icon_size)` unless the icon is hidden (`ComputeBarItemHeight`).
---@param settings table
---@return number itemWidth, number itemHeight, number barLeftOffset
local function itemDims(settings)
    local iconSize = settings.icon_size or 30
    local barContent = settings.bar_content
    local width = settings.bar_width or 220
    local avail = private.Anchor.GetInheritedWidth(tracker.name)
    if avail and avail > 0 then width = avail end
    if barContent == "IconOnly" and settings.collapse then width = iconSize end
    local iconHidden = (barContent == "NameOnly" or barContent == "BarOnlyNoName")
    local barLeft = iconHidden and 0 or (iconSize + (settings.icon_offset or 2))
    local height = private.Util.ComputeBarItemHeight(barContent,
        settings.bar_height or 30, iconSize)
    return width, height, barLeft
end

---Build the AddAuraGroup/SetAuraGroupLayout opts from component settings.
---elementWidth/Height drive the layout cursor only; the button's NATURAL size
---(applyBarGeometry) is what actually renders — keep the two in sync.
---@param settings table
---@return table
local function buildLayoutOpts(settings)
    local w, h = itemDims(settings)
    local spacing = settings.bar_spacing or 2
    return {
        elementWidth   = w,
        elementHeight  = h,
        elementSpacing = spacing,
        lineSpacing    = spacing,
    }
end

---Resolve the single-line stack contract shared by both engines, mirroring the
---old `Util.LayoutViewerBars`: `layout_direction` → axis, `layout_alignment` →
---the anchored edge (falling back to `growth_direction` when "center", exactly
---as the old engine did). `growBack` means the run advances UP (vertical) or
---LEFT (horizontal).
---@param settings table
---@return boolean vertical, boolean growBack, string anchorPt
local function barFlow(settings)
    local vertical = (settings.layout_direction or "vertical") ~= "horizontal"
    local alignment = settings.layout_alignment or "center"
    local growDir = settings.growth_direction or "up"
    if vertical then
        local growUp = (alignment == "bottom")
            or (alignment ~= "top" and growDir == "up")
        return true, growUp, growUp and "BOTTOM" or "TOP"
    end
    local growLeft = (alignment == "right")
        or (alignment ~= "left" and growDir == "left")
    return false, growLeft, growLeft and "RIGHT" or "LEFT"
end

---Apply the single-line flow contract to ONE aura container; no wrapping —
---bars always occupy a single line.
---@param c frame
---@param settings table
---@return string anchorPt
local function applyContainerFlow(c, settings)
    local vertical, growBack, anchorPt = barFlow(settings)
    local hDir, vDir
    if vertical then
        vDir = growBack and LAC.FlowDirection.Up or LAC.FlowDirection.Down
        hDir = LAC.FlowDirection.Right
        c:SetFlowLayoutAxis(LAC.FlowLayoutAxis.Vertical)
    else
        hDir = growBack and LAC.FlowDirection.Left or LAC.FlowDirection.Right
        vDir = LAC.FlowDirection.Down
        c:SetFlowLayoutAxis(LAC.FlowLayoutAxis.Horizontal)
    end
    c:SetFlowLayoutGrowthDirection(hDir, vDir)
    c:SetFlowLayoutAnchorPoint(anchorPt)
    -- nil → math.huge: bars never wrap (the old engine placed them on one line).
    c:SetFlowLayoutMaximumLineSize(nil)
    c:SetFlowLayoutPadding(0, 0, 0, 0)
    -- Pin the aura container to its wrapper at the SAME point as the flow
    -- origin: the container's own rect is engine-owned and SECRET, so only
    -- the pinned point sits at a known wrapper position — any other flow
    -- origin would render at a secret offset.
    c:ClearAllPoints()
    c:SetPoint(anchorPt)
    return anchorPt
end

---Apply flow settings to both containers and CHAIN the target block directly
---onto the end of the player block along the run axis.
---
---The chain is an anchor, not an estimate: `OnLayoutComplete` sizes each
---container to its own VISIBLE block, so anchoring the target container's
---leading edge (its flow origin) to the player container's trailing edge abuts
---the two exactly, and the seam tracks the live bar count under
---hide-when-inactive. The rect is secret to Lua but the anchor resolves
---engine-side, so nothing here reads it. Replaces a settings-derived offset
---that reserved room for every TRACKED aura.
---
---`barFlow`'s anchor points are cross-axis MID-edge points ("TOP"/"BOTTOM" for
---a column, "LEFT"/"RIGHT" for a row), so chaining on them keeps the two blocks
---centred on the same line as well as gapless.
---Size the bounds frame to the two aura blocks it encloses.
---
---**The `SetSize(0.001, 0.001)` first is load-bearing, not defensive.** The
---bounds rect is the union of the frame's OWN rect and its children's, so
---resizing without collapsing it first can only ever grow the frame — the
---placement would then stay stuck at the tallest burst ever rendered. Same shape
---Coolinator uses (`Display/Stack.lua` TriggerLayout).
---
---`ResizeToBoundsRect` takes no arguments and returns nothing, so the secret
---block extents are consumed engine-side and never reach Lua. Deliberately NOT
---combat-guarded — see the matching note in Components/BuffTracker.lua.
local function resizePair()
    pairFrame:SetSize(0.001, 0.001)
    private.compat.ResizeToBoundsRect(pairFrame)
end

---Filter strings, matching Blizzard's own `GetTargetAurasFilterString`
---(CooldownViewerItemData.lua:661): friendly units (the player, and a friendly
---target) take HELPFUL with the nameplate-only flag INCLUDED, hostile units take
---HARMFUL.  Without INCLUDE_NAME_PLATE_ONLY a nameplate-flagged aura is silently
---dropped.
---
---Declared up here rather than beside the slot-filter lists below because
---`syncSelfTargetSuppression` reads them, and a Lua 5.1 local captured after its
---reader resolves to a nil global (patterns.md "Lua 5.1 Upvalue Safety").
local PLAYER_HELPFUL = "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"
local PLAYER_HARMFUL = "HARMFUL|PLAYER"

---Hide the target-HELPFUL block while the player is their own target, so a
---self-buff is not drawn by both it and the player container.
---
---`SetShown` on an addon-owned frame is unrestricted, which is the entire reason
---this group lives in a container of its own — see `targetHelpfulContainer`.
---Hidden children are excluded from `GetBoundsRect`, so `resizePair` closes the
---gap on its next tick without any extra bookkeeping.
---
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
    local anchorPt = applyContainerFlow(container, settings)
    -- Configures the target containers' flow axis/origin/growth; their pins are
    -- replaced by the chain below.
    applyContainerFlow(targetContainer, settings)
    applyContainerFlow(targetHelpfulContainer, settings)

    local vertical, growBack = barFlow(settings)
    local spacing = settings.bar_spacing or 2
    local trailingPt, dx, dy = nil, 0, 0
    if vertical then
        trailingPt = growBack and "TOP" or "BOTTOM"
        dy = growBack and spacing or -spacing
    else
        trailingPt = growBack and "LEFT" or "RIGHT"
        dx = growBack and -spacing or spacing
    end

    -- Player block at the bounds frame's own anchor point, then each target
    -- block chained onto the previous one's trailing edge.  Helpful goes LAST
    -- among the blocks; the containers collapse while hidden (Initialize), so
    -- self-target suppression leaves no hole before the totem rows either.
    container:ClearAllPoints()
    container:SetPoint(anchorPt, pairFrame, anchorPt)
    targetContainer:ClearAllPoints()
    targetContainer:SetPoint(anchorPt, container, trailingPt, dx, dy)
    targetHelpfulContainer:ClearAllPoints()
    targetHelpfulContainer:SetPoint(anchorPt, targetContainer, trailingPt, dx, dy)

    -- Size the bounds frame to the blocks, then pin it on the wrapper at the
    -- same alignment point, so the STACK is placed as a unit rather than any
    -- block individually.  Totem rows, when on, are children of the bounds
    -- frame chained after the blocks (layoutTotemCells), so they move with it.
    -- Sitting on BuffTracker, pin to its visible buffs instead (followTarget).
    pairFrame:ClearAllPoints()
    local follow, relPt, fx, fy = followTarget(settings, anchorPt)
    if follow then
        pairFrame:SetPoint(anchorPt, follow, relPt, fx, fy)
    else
        pairFrame:SetPoint(anchorPt, wrapper, anchorPt)
    end
    resizePair()
    pairFrame:SetScript("OnUpdate", resizePair)
end

---Apply item geometry to one bar button, mirroring the deleted
---`Util.SquarifyBarIcon` + the old `ApplyBarContentAndTimer`: a SQUARE icon
---pinned BOTTOMLEFT (it extends above the bar when `icon_size > bar_height` —
---that overhang is why the layout step is `ComputeBarItemHeight`), the bar
---occupying the bottom `bar_height` strip to the right of the icon, and
---`bar_content` / `show_timer` driving which regions are visible.
---`bar_content` show predicates.  Derived from settings and never read back off
---the regions: a region parented into an aura button answers `IsShown()` with a
---SECRET, and feeding that to `SetShown` on an addon frame throws
---"Secret values are only allowed during untainted execution".  The border
---overlays are siblings of the regions they outline, so they need the same
---answer from the same place.
---@param settings table
---@return boolean
local function iconShownFor(settings)
    local bc = settings.bar_content
    return bc ~= "NameOnly" and bc ~= "BarOnlyNoName"
end

---@param settings table
---@return boolean
local function barShownFor(settings)
    return settings.bar_content ~= "IconOnly"
end

---@param button frame
---@param settings table
local function applyBarGeometry(button, settings)
    local iconSize = settings.icon_size or 30
    local barContent = settings.bar_content
    local w, h, barLeft = itemDims(settings)
    button:SetSize(w, h)

    if button.cue_Icon then
        button.cue_Icon:ClearAllPoints()
        button.cue_Icon:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT",
            settings.icon_offset_x or 0, settings.icon_offset_y or 0)
        button.cue_Icon:SetSize(iconSize, iconSize)
        button.cue_Icon:SetTexCoord(private.Util.GetIconZoomCoords(iconSize, iconSize))
        button.cue_Icon:SetShown(iconShownFor(settings))
    end
    if button.cue_Bar then
        button.cue_Bar:ClearAllPoints()
        button.cue_Bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", barLeft, 0)
        button.cue_Bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        button.cue_Bar:SetHeight(settings.bar_height or 30)
        button.cue_Bar:SetShown(barShownFor(settings))
    end
    if button.cue_Bg then
        -- SetAllPoints tracks the bar's rect, but not its shown state.
        button.cue_Bg:SetShown(barContent ~= "IconOnly")
    end
    if button.cue_Name then
        button.cue_Name:SetShown(barContent ~= "IconOnly"
            and barContent ~= "BarOnlyNoName" and barContent ~= "IconAndBarNoName")
    end
    if button.cue_Timer then
        button.cue_Timer:SetShown(settings.show_timer ~= false)
    end
end

-- ---------------------------------------------------------------------------
-- Dirty-flag restyle
-- ---------------------------------------------------------------------------

---Forward declaration — defined before makeBarInit is called.
local restyleBarButton

---Apply font and color settings to a tracked AuraContainer bar button.
---@param button frame
---@param settings table
restyleBarButton = function(button, settings)
    -- A totem row is not an aura button: it has no aura to describe and no
    -- container binding to glow from.  Everything BELOW is plain widget work on
    -- whatever object carries the cue_* keys, which is why the totem block
    -- reuses this whole function rather than copying its geometry, borders,
    -- fill colour and fonts.
    if not button.cue_totem then
        private.AuraContainer.ApplyTooltip(button, settings)
        private.AuraContainer.ApplyActiveGlow(button, settings)
    end
    applyBarGeometry(button, settings)

    -- Global icon_border / bar_border, the pair the CDM-child path used to apply
    -- per viewer child (old Util.lua:4256).  Under groups the button carries
    -- both the icon and the bar; under slots the chrome is the cell and
    -- restyleBarCell owns them, so a second pair here would double-draw.
    if not button.cue_slot then
        if button.cue_Icon then
            -- The overlay is a sibling of the region it outlines, not a child,
            -- so bar_content hiding the icon/bar does not hide its border.
            private.Util.ApplyIconBorder(button, button.cue_Icon)
                :SetShown(iconShownFor(settings))
        end
        if button.cue_Bar then
            -- Parented to the BUTTON, anchored to the bar: the same shape the
            -- icon border above already survives in this subtree, rather than
            -- hanging a new frame off the engine-bound StatusBar.
            private.Util.ApplyBarBorder(button, button.cue_Bar)
                :SetShown(barShownFor(settings))
        end
    elseif button.cue_ActiveIcon then
        -- desaturate_inactive: the full-colour copy of the cell's icon
        -- (layoutBarCells) sits a frame level above the cell, over an inside
        -- icon border, so it carries its own.  Hidden with the setting off.
        local show = settings.desaturate_inactive == true and iconShownFor(settings)
        local iconSize = settings.icon_size or 30
        button.cue_ActiveIcon:SetTexCoord(private.Util.GetIconZoomCoords(iconSize, iconSize))
        button.cue_ActiveIcon:SetShown(show)
        private.Util.ApplyIconBorder(button, button.cue_ActiveIcon):SetShown(show)
    end

    if button.cue_Bar then
        local fc = settings.bar_fill_color or {1, 0.5, 0.25, 1}
        button.cue_Bar:SetStatusBarColor(fc[1], fc[2], fc[3], fc[4] or 1)
    end

    -- ApplyFontProfile carries face/size/outline/shadow/color AND the profile's
    -- anchor_point/offset_x/offset_y — the old bar path positioned every font
    -- that way (the old Util.ApplyViewerBarFonts), so anything less drops layout options.
    -- Parents mirror the old targets: Bar.Name/Bar.Duration → the bar frame,
    -- Icon.Applications → the icon.
    local itemW, _, barLeft = itemDims(settings)
    if settings.name_font and button.cue_Name then
        private.Util.ApplyFontProfile(button.cue_Name, settings.name_font, button.cue_Bar)
        button.cue_Name:SetDrawLayer("OVERLAY", 7)
        button.cue_Name:SetWidth((itemW - barLeft) * 0.8)
        button.cue_Name:SetWordWrap(false)
    end
    if settings.duration_font and button.cue_Timer then
        private.Util.ApplyFontProfile(button.cue_Timer, settings.duration_font, button.cue_Bar)
        button.cue_Timer:SetDrawLayer("OVERLAY", 7)
    end
    if settings.stacks_font and button.cue_Count then
        -- Slot buttons carry adornments only: the icon is chrome on the cell,
        -- so anchor the count to the button itself there.
        private.Util.ApplyFontProfile(button.cue_Count, settings.stacks_font,
            button.cue_Icon or button)
    end
end

---Create the initializeFrame closure for bar-mode AuraContainer buttons.
---Creates icon, StatusBar, name text, stack count, and timer text regions and
---binds them; all sizing/positioning is owned by applyBarGeometry (via the
---closing restyle) so creation and refresh can never disagree.
---Unverified: SetSpellName only — bound below alongside the aura-tap-verified
---SetDurationBar/SetDurationText (see the file header); unverified is whether the
---engine-written secret name renders, not whether the bind is reached.
---@return function
local function makeBarInit()
    return function(button)
        local s = getSettings()

        -- Icon texture. Size/position come from applyBarGeometry below; the
        -- flow layout uses the button's NATURAL size, and an unsized button
        -- has no rect and renders NOTHING (see patterns-auracontainer.md).
        button.cue_Icon = button:CreateTexture(nil, "ARTWORK")
        button:SetIcon(button.cue_Icon)

        -- Stack count on icon. Font template REQUIRED pre-bind: the bind
        -- pushes text immediately; font-less SetText errors "Font not set".
        button.cue_TextLayer = private.AuraContainer.CreateTextLayer(button)
        button.cue_Count = button.cue_TextLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        button.cue_Count:SetPoint("BOTTOMRIGHT", button.cue_Icon, "BOTTOMRIGHT", -2, 2)
        button:SetApplicationCount(button.cue_Count)

        -- Status bar for duration fill (right of the icon).
        -- SetDurationBar on a plain StatusBar child is live-verified — the same
        -- shape ships in ensureEbonMightTap (Components/PrimaryResources.lua).
        -- That is a SLOT button, but slot and group buttons come from the same
        -- provider (CreateCustomFrameProvider) with the same
        -- CustomAuraButtonTemplate and mixins, so the binding API is identical;
        -- only our own wiring is unproven here.
        button.cue_Bar = CreateFrame("StatusBar", nil, button)
        -- SOLID fill, not a gradient: `bar_fill_color` is applied with
        -- SetStatusBarColor, which TINTS the texture — over UI-StatusBar it
        -- comes out shaded rather than the configured color.  This is the same
        -- substitution the CDM-child path made on Blizzard's rounded atlas
        -- (Core/Util/Util.lua:2458).
        button.cue_Bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        button.cue_Bar:SetMinMaxValues(0, 1)
        button.cue_Bar:SetValue(1)
        -- direction defaults to ElapsedTime (bar FILLS as the aura ages);
        -- RemainingTime drains toward empty like a classic buff bar.
        button:SetDurationBar(button.cue_Bar, { direction = Enum.StatusBarTimerDirection.RemainingTime })

        -- Backdrop behind the fill, matching the old `Bar.BarBG` treatment
        -- (Util.lua:2464 — flat WHITE8x8 at 0.1/0.1/0.1/0.8, pinned to the bar
        -- rect).  Groups mode had no background at all, which is what made these
        -- bars read as unskinned; slots mode gets its equivalent from
        -- `cell.cue_Bg`.  Created on the BUTTON, so the bar (a child frame)
        -- always draws over it regardless of draw layer.
        button.cue_Bg = button:CreateTexture(nil, "BACKGROUND")
        button.cue_Bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
        button.cue_Bg:SetAllPoints(button.cue_Bar)

        -- Name / timer live inside the bar, positioned by the profile's font
        -- anchor_point in restyleBarButton (old ApplyViewerBarFonts contract).
        -- Font template REQUIRED pre-bind (same "Font not set" trap as cue_Count).
        --
        -- Created ON cue_Bar, not on the button.  cue_Bar is a child FRAME of the
        -- button, and a child frame draws above ALL of its parent's regions
        -- regardless of draw layer — so a FontString created on the button sits
        -- BEHIND the status-bar fill and no amount of SetDrawLayer("OVERLAY")
        -- rescues it (frame level beats region layer). As regions of the bar they
        -- share its frame level, and OVERLAY then puts them above its ARTWORK
        -- fill texture, which is what restyleBarButton's SetDrawLayer does.
        button.cue_Name = button.cue_Bar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        button.cue_Name:SetPoint("LEFT", button.cue_Bar, "LEFT", 5, 0)
        button:SetSpellName(button.cue_Name)

        -- SetDurationText on a plain FontString is live-verified by the same
        -- ensureEbonMightTap path (both its slots bind one).
        button.cue_Timer = button.cue_Bar:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
        button.cue_Timer:SetPoint("RIGHT", button.cue_Bar, "RIGHT", -5, 0)
        button:SetDurationText(button.cue_Timer, {})

        -- Pandemic host.  The bar strip is the overlay's anchor target (the
        -- item rect also covers the icon overhang), which is what `.Bar` binds.
        private.AuraContainer.AttachPandemic(button, s, name, nil, button.cue_Bar)

        -- Register for dirty-flag restyle on OnProfileChanged.
        private.AuraContainer.TrackButton(name, button)

        -- Initial styling at acquire time; also runs applyBarGeometry, which is
        -- what gives cue_Icon/cue_Bar their first resolvable rects.
        restyleBarButton(button, s)
    end
end

-- ---------------------------------------------------------------------------
-- Always-show engine (AddAuraSlot)
-- ---------------------------------------------------------------------------
--
-- Selected by always_show_tracked.  Groups
-- compact the secret active set; slots hold one cell per TRACKED spell, laid
-- out by us.  Bars are the best case for the role split: background + icon +
-- name are ours and persistent, Blizzard drives only the fill and the timer
-- into the bound StatusBar — background-plus-fill is normal bar construction.
-- See patterns-auracontainer.md "Always-show via slots".


---One slot per (spell, container), all three sharing ONE chrome cell: a tracked
---spell may land on the player, as a target debuff, or as an ally-target buff.
---Separate cell pools per unit would draw every always-show spell twice.
---
---One filter per list because the target HELPFUL group now has a container of
---its own (see `targetHelpfulContainer`) — the two target filters can no longer
---share a slot list.
local BAR_FILTERS = { PLAYER_HELPFUL }
local TARGET_HARMFUL_FILTERS = { PLAYER_HARMFUL }
local TARGET_HELPFUL_FILTERS = { PLAYER_HELPFUL }

---Idle-engine include map / spell list — match nothing, so exactly one engine
---holds frames at a time.  Never mutated.
local EMPTY_MAP = {}
local EMPTY_LIST = {}

---Chrome cells, ONE per tracked spell and shared by both containers' slots.
---Cell `i` carries the player-HELPFUL button plus the two target buttons, so a
---spell occupies one row no matter which unit its aura lands on.
---@type frame[]
local cells = {}

---Ordered (sorted) spell list backing the cells — map iteration order is not
---stable and the bar order must be.
---@type number[]
local spellList = {}

---Whether the last Refresh ran the slots engine.
local usingSlots = false

---Slot count at the last layout, for the anchor state-change trigger.
local lastSlotCount = -1

---Poll driving `updateTotemCells`.  PLAYER_TOTEM_UPDATE covers spawn and
---destruction but NOT natural expiry — Blizzard hits the same hole and works
---around it in CooldownViewerCooldownItemMixin:OnCooldownDone — and we cannot
---read a time left to notice, so a poll is the whole driver rather than a
---backstop to an event.
---@type table?
local totemTicker

---Fill `list` with the keys of `map` in bar order, truncating any stale tail.
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

---File-scope so the identity walk below allocates no closure per button.
---@param id number
---@param colors table<number, number[]>
---@return number[]|nil
local function lookupSpellColor(id, colors)
    return colors[id]
end

---Per-spell bar fill color — parity gap D5.
---This is what only the slots engine can do: under groups the container assigns
---auras to pooled buttons and that binding is secret, so there is no key to look
---a color up by.  Here each button belongs to one known spell.
---@param button frame
---@param spellID number
---@param settings table
local function applyBarFill(button, spellID, settings)
    if not button.cue_Bar then return end
    -- Identity walk, not a raw key: an entry is keyed by `overrideSpellID or
    -- spellID` (what the retired Spell Colors list saved) or by a Tracking-tab
    -- row's key, this button by whichever identity member its live aura carries.
    local fc = (settings.spell_colors
            and private.Util.ResolveByBaseOrOverride(spellID, lookupSpellColor,
                settings.spell_colors))
        or settings.bar_fill_color or {1, 0.5, 0.25, 1}
    button.cue_Bar:SetStatusBarColor(fc[1], fc[2], fc[3], fc[4] or 1)
end

---Create or return the shared chrome cell at `index`.  Called once per
---(container, filter) pair for the same index, so it must be idempotent.
---@param index number
---@return frame
local function cellForSlot(index)
    local cell = cells[index]
    if cell then return cell end
    cell = CreateFrame("Frame", nil, wrapper)
    -- Chrome renders BELOW the adornments: the aura container is a child of
    -- `wrapper` and the slot buttons children of it, so a cell held at the
    -- wrapper's own frame level always sits underneath.
    cell:SetFrameLevel(wrapper:GetFrameLevel())
    cell.cue_Bg = cell:CreateTexture(nil, "BACKGROUND")
    -- Same flat backdrop the CDM-child path gave Bar.BarBG (Util.lua:2464), so
    -- both engines render the pre-migration bar look.
    cell.cue_Bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    cell.cue_Icon = cell:CreateTexture(nil, "ARTWORK")
    -- Except the name, which the slot button's fill would cover: a region of the
    -- cell draws under every frame in the button subtree, draw layer or not.  A
    -- raised child frame (cell level + 10) clears the bar at wrapper + 4.
    cell.cue_TextLayer = private.AuraContainer.CreateTextLayer(cell)
    cell.cue_Name = cell.cue_TextLayer:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    cells[index] = cell
    return cell
end

---Chrome geometry + content for one bar cell, mirroring applyBarGeometry's
---contract for the persistent half: a square icon pinned BOTTOMLEFT and the
---bar strip occupying the bottom `bar_height` to its right.  The name is set
---from C_Spell directly rather than bound via SetSpellName — under slots we
---know the spell, and a bound name would vanish with the button.
---@param cell frame
---@param spellID number
---@param settings table
local function restyleBarCell(cell, spellID, settings)
    local iconSize = settings.icon_size or 30
    local barContent = settings.bar_content
    local w, _, barLeft = itemDims(settings)

    cell.cue_Icon:ClearAllPoints()
    cell.cue_Icon:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT",
        settings.icon_offset_x or 0, settings.icon_offset_y or 0)
    cell.cue_Icon:SetSize(iconSize, iconSize)
    cell.cue_Icon:SetTexCoord(private.Util.GetIconZoomCoords(iconSize, iconSize))
    cell.cue_Icon:SetShown(iconShownFor(settings))
    -- desaturate_inactive: the cell is what shows while the aura is NOT up.
    cell.cue_Icon:SetDesaturated(settings.desaturate_inactive == true)
    -- Manual icon_overrides outranks the CDM conditional-icon path.  The cell icon
    -- is addon-owned, so the deleted Util.ApplyIconOverride (the viewer-child
    -- path) could not have reached it and the override is resolved from the map
    -- key instead.
    local texture = private.Util.ResolveIconOverride(spellID)
    if not texture then
        local iconID, _, conditionalIconID =
            C_Spell.GetSpellTexture(displaySpellFor(spellID))
        texture = conditionalIconID or iconID
    end
    cell.cue_Icon:SetTexture(texture)

    cell.cue_Bg:ClearAllPoints()
    cell.cue_Bg:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", barLeft, 0)
    cell.cue_Bg:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 0, 0)
    cell.cue_Bg:SetHeight(settings.bar_height or 30)
    cell.cue_Bg:SetShown(barShownFor(settings))

    -- Global borders belong on the persistent chrome under slots: the cell is
    -- drawn whether or not the aura is up, the button only while it is.  Each
    -- overlay is a sibling of the region it outlines, so it needs the same
    -- bar_content show state applied by hand.
    private.Util.ApplyIconBorder(cell, cell.cue_Icon):SetShown(iconShownFor(settings))
    private.Util.ApplyBarBorder(cell, cell.cue_Bg):SetShown(barShownFor(settings))

    cell.cue_Name:SetShown(barContent ~= "IconOnly"
        and barContent ~= "BarOnlyNoName" and barContent ~= "IconAndBarNoName")
    local info = C_Spell.GetSpellInfo(displaySpellFor(spellID))
    cell.cue_Name:SetText(info and info.name or "")
    if settings.name_font then
        private.Util.ApplyFontProfile(cell.cue_Name, settings.name_font, cell.cue_Bg)
        cell.cue_Name:SetDrawLayer("OVERLAY", 7)
        cell.cue_Name:SetWidth((w - barLeft) * 0.8)
        cell.cue_Name:SetWordWrap(false)
    end
end

---initializeFrame for a slot button: adornments only.
---Deliberately NO SetIcon / SetSpellName bind — both are chrome on the cell.
---@param button frame
---@param cell frame
---@param spellID number
local function initSlotButton(button, cell, spellID)
    button:SetAllPoints(cell)
    -- Marks the slots engine for restyleBarButton, which must not draw a second
    -- pair of borders over the cell's.
    button.cue_slot = true

    -- Font template REQUIRED pre-bind: every Set* bind pushes text immediately
    -- and a font-less SetText errors "Font not set".
    button.cue_TextLayer = private.AuraContainer.CreateTextLayer(button)
    button.cue_Count = button.cue_TextLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.cue_Count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    button:SetApplicationCount(button.cue_Count)

    button.cue_Bar = CreateFrame("StatusBar", nil, button)
    -- Solid fill so bar_fill_color tints true — see makeBarInit.  The backdrop
    -- here is the cell's own cue_Bg, which already occupies the bar strip.
    button.cue_Bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    button.cue_Bar:SetMinMaxValues(0, 1)
    button.cue_Bar:SetValue(1)
    button:SetDurationBar(button.cue_Bar,
        { direction = Enum.StatusBarTimerDirection.RemainingTime })

    -- On cue_Bar, not the button — a child frame draws above its parent's
    -- regions regardless of draw layer, so a button-owned FontString would sit
    -- behind the fill.  See the matching note in makeBarInit.
    button.cue_Timer = button.cue_Bar:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
    button.cue_Timer:SetPoint("RIGHT", button.cue_Bar, "RIGHT", -5, 0)
    button:SetDurationText(button.cue_Timer, {})

    -- desaturate_inactive: a full-colour copy of the cell's icon, textured by
    -- layoutBarCells.  The engine shows this button exactly while its aura is
    -- up, so the copy is the active state and the cell's greyed icon the
    -- inactive one -- nothing reads an aura.  Anchored to the cell's icon, so
    -- icon_size / icon_offset_* move it with no geometry of its own.  Not
    -- `cue_Icon`: applyBarGeometry and the stack count key off that name.
    button.cue_ActiveIcon = button:CreateTexture(nil, "ARTWORK")
    button.cue_ActiveIcon:SetAllPoints(cell.cue_Icon)

    private.AuraContainer.AttachPandemic(button, getSettings(), nil, cell, button.cue_Bar)

    -- A target cell carries one button per filter (harmful + helpful), so this
    -- is a list: the per-spell fill has to reach whichever one ends up shown.
    cell.cue_buttons = cell.cue_buttons or {}
    cell.cue_buttons[#cell.cue_buttons + 1] = button
    private.AuraContainer.TrackButton(name, button)
    local s = getSettings()
    restyleBarButton(button, s)
    applyBarFill(button, spellID, s)
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

---Point all three containers' slots at the spell list.  Every call walks the
---SAME list through the SAME cellForSlot, so slot `i` on any container lands on
---cell `i` — three buttons per cell, at most one shown.
---
---`aura_unit` is applied here rather than by trimming the list: the cell index
---IS the list index, so a per-container list would misalign the three sets of
---buttons.  An out-of-scope spell instead gets an empty candidate set, which
---neutralizes that one slot and leaves every index in place.
---@param spellMap table<number, true>
---@param scopeMap table<number, string>|nil  EXPANDED aura_unit, from Refresh
local function syncSlotEngine(spellMap, scopeMap)
    fillSortedList(spellList, spellMap, private.Util.BuildSpellOrderRank(name, spellMap))

    -- The name stamp: a by-name entry's ids change what identitySetFor
    -- returns without changing the list SyncSlots signs.
    local salt = scopeSignature(scopeMap) .. "|" .. private.CustomSpells.GetNameStamp()
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

    private.AuraContainer.SyncSlots(container, BAR_FILTERS, spellList,
        cellForSlot, initSlotButton, playerIds, salt)
    private.AuraContainer.SyncSlots(targetContainer, TARGET_HARMFUL_FILTERS, spellList,
        cellForSlot, initSlotButton, targetIds, salt)
    private.AuraContainer.SyncSlots(targetHelpfulContainer, TARGET_HELPFUL_FILTERS,
        spellList, cellForSlot, initSlotButton, targetIds, salt)

    -- Slot frames are never flow elements and ride their cells (children of
    -- `wrapper`), so container geometry is irrelevant here — the bounds frame
    -- just needs a resolvable rect and must stay shown, or the slot buttons
    -- inside it never render.  No ResizeToBoundsRect in this mode: we own the
    -- stack, and layoutBarCells already places it exactly.
    pairFrame:SetScript("OnUpdate", nil)
    pairFrame:ClearAllPoints()
    pairFrame:SetAllPoints(wrapper)
end

---Stack the cells on one line, applying the same growth/alignment contract the
---groups engine hands to the flow layout (`syncContainerLayout`): bars never
---wrap, so this is a single run down or across the wrapper.
---@param settings table
local function layoutBarCells(settings)
    local n = #spellList
    for i = n + 1, #cells do cells[i]:Hide() end
    if n == 0 then return end

    local w, h = itemDims(settings)
    local spacing = settings.bar_spacing or 2
    local vertical, growBack, anchorPt = barFlow(settings)
    local step = vertical and (h + spacing) or (w + spacing)
    local dx = (not vertical) and (growBack and -step or step) or 0
    local dy = vertical and (growBack and step or -step) or 0

    -- desaturate_inactive's copy writes into the buttons' subtree
    -- (DenyTaintedAccessWhenAurasAreSecret); the next Refresh outside secrecy
    -- catches up.  Per Refresh because the texture follows the spell on each
    -- row, which moves with the list.
    local copyIcons = not private.Util.IsAuraAccessBlocked()
    local desat = settings.desaturate_inactive == true

    for i = 1, n do
        local cell = cells[i]
        local spellID = spellList[i]
        cell:ClearAllPoints()
        cell:SetPoint(anchorPt, wrapper, anchorPt, dx * (i - 1), dy * (i - 1))
        cell:SetSize(w, h)
        restyleBarCell(cell, spellID, settings)
        if cell.cue_buttons then
            local texture = desat and cell.cue_Icon:GetTexture() or nil
            for b = 1, #cell.cue_buttons do
                local button = cell.cue_buttons[b]
                applyBarFill(button, spellID, settings)
                if copyIcons then button.cue_ActiveIcon:SetTexture(texture) end
            end
        end
        cell:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Totem / summon rows
-- ---------------------------------------------------------------------------
--
-- A summon occupies a TOTEM SLOT and applies no player aura, so no aura engine
-- can ever fill its row (`.context/patterns-cooldownviewer.md` "A tracked buff
-- has TWO duration sources").  These rows are the only display that reaches
-- one, and they are indexed by SLOT for the reason that makes them possible at
-- all: nothing tells an addon which slot holds which spell, so a row never asks.
--
-- Every value read below is secret while its slot is occupied, and every one is
-- piped straight into an engine sink that accepts a secret.  Nothing here
-- reads, compares or branches on a totem value -- `SetAlphaFromBoolean` is what
-- stands in for the `if haveTotem` Blizzard's own TotemFrame can afford to
-- write.  Adding one such test is what breaks the whole block.
--
-- The one branch is `updateTotemCells`' `if duration then`, on the
-- DurationObject from `GetTotemDuration` -- an object that is never itself a
-- secret value, so the test is legal in every state.  Necessary, because an
-- empty slot returns a nil duration the sink rejects.
--
-- The rows' alpha, name text and icon take secret aspects from those sinks, so
-- nothing may READ them back (`GetAlpha`, `GetText`, `GetStringWidth`, ...)
-- either -- nothing does today.
--
-- Built to be DELETED: when Blizzard gives AuraContainers a totem API, identity
-- comes back and these entries should simply start working through the existing
-- slot path, with no extra rows at all.  So it is one default-off key and no
-- settings of its own -- every knob added here is migration debt for a feature
-- whose purpose is to stop existing.

---Create or return the totem row for `slot`.
---@param slot number
---@return frame
local function totemCellFor(slot)
    local cell = totemCells[slot]
    if cell then return cell end
    -- The slot's link in the chain, inside the bounds frame so resizePair and
    -- followTarget take the rows along.  Templated because it anchors onto an
    -- aura container (layoutTotemCells), which a plain frame is refused
    -- (patterns-auracontainer.md "An anchor TARGET propagates its forbidden
    -- aspects").  The row inside anchors only to it, as the icon twin's totem
    -- icons anchor bare onto pairFrame.
    local slotFrame = CreateFrame("Frame", nil, pairFrame,
        LAC.IsNative and "DisableUntrustedLayoutScriptsTemplate" or nil)
    slotFrame:SetCollapsesLayout(true)
    totemSlots[slot] = slotFrame
    cell = CreateFrame("Frame", nil, slotFrame)
    cell:SetFrameLevel(wrapper:GetFrameLevel())
    -- Read by restyleBarButton, which must skip the two AuraContainer calls.
    cell.cue_totem = true

    cell.cue_Icon = cell:CreateTexture(nil, "ARTWORK")
    -- An aura row splits chrome (the cell) from fill (the aura button).  There
    -- is no button here, so the cell owns both and the DurationObject goes into
    -- the StatusBar's own sink.  Solid texture for the same reason as
    -- makeBarInit: bar_fill_color TINTS it.
    cell.cue_Bar = CreateFrame("StatusBar", nil, cell)
    cell.cue_Bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    cell.cue_Bar:SetMinMaxValues(0, 1)
    cell.cue_Bar:SetValue(1)
    cell.cue_Bg = cell:CreateTexture(nil, "BACKGROUND")
    cell.cue_Bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    cell.cue_Bg:SetAllPoints(cell.cue_Bar)

    -- Regions of the BAR, not the cell: a child frame draws above all of its
    -- parent's regions whatever the draw layer (makeBarInit says why).
    cell.cue_Name = cell.cue_Bar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    cell.cue_Name:SetPoint("LEFT", cell.cue_Bar, "LEFT", 5, 0)
    cell.cue_Timer = cell.cue_Bar:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
    cell.cue_Timer:SetPoint("RIGHT", cell.cue_Bar, "RIGHT", -5, 0)
    -- The countdown an aura button gets from SetDurationText.  Same engine
    -- formatter, reached without a button (Blizzard_CustomAuraButton.lua:167).
    -- SetToDefaults CLEARS the formatter, and a binding without one writes no
    -- text at all; SetDurationText follows it with exactly this SetFormatter.
    cell.cue_Binding = C_DurationUtil.CreateDurationTextBinding()
    cell.cue_Binding:SetToDefaults()
    cell.cue_Binding:SetFormatter(LAC.Inbound.GetDefaultAuraDurationFormatter())
    cell.cue_Binding:SetFontString(cell.cue_Timer)

    totemCells[slot] = cell
    return cell
end

---Pipe every placed totem row.  Poll-driven, not event-driven: see `totemTicker`.
local function updateTotemCells()
    -- The disabled path Hides the wrapper and returns before Refresh can stop
    -- the ticker, and a tracker hidden by visibility is Hide()n too.
    if not wrapper:IsShown() then return end
    local showTimer = getSettings().show_timer ~= false
    for slot = 1, totemCount do
        local cell = totemCells[slot]
        -- The one branch is on the DurationObject's existence, never on
        -- `haveTotem`: an empty slot's `GetTotemDuration` is nil and
        -- `SetTimerDuration` rejects it ("bad argument #2"), unwinding out of
        -- Initialize.  The generated docs mark that return `Nilable = false`
        -- and are wrong.  The object itself is not secret (no
        -- `SecretWhenTotemSlotSecret` on it), so testing it is always legal.
        --
        -- Not `C_Secrets.ShouldTotemSlotBeSecret` as a plain/secret switch: it
        -- has answered false for a slot whose `GetTotemInfo` came back secret
        -- in the same call (1111x "boolean test on 'haveTotem'").
        local duration = GetTotemDuration(slot)
        if duration then
            local haveTotem, totemName, _, _, icon = GetTotemInfo(slot)
            -- The four writes that would each be a branch in untainted code.
            cell:SetAlphaFromBoolean(haveTotem)
            cell.cue_Icon:SetTexture(icon)
            cell.cue_Name:SetText(totemName)
            -- Eased, so the poll's re-bind glides instead of snapping.
            cell.cue_Bar:SetTimerDuration(duration,
                Enum.StatusBarInterpolation.ExponentialEaseOut,
                Enum.StatusBarTimerDirection.RemainingTime)
            cell.cue_Binding:SetDuration(duration)
            cell.cue_Binding:SetEnabled(showTimer)
            totemSlots[slot]:Show()
        else
            -- Empty is a plain fact, so a real Hide(): the slot collapses out
            -- of the chain, spacing and all (layoutTotemCells).
            totemSlots[slot]:Hide()
        end
    end
end

---Place the totem rows at the END of the run, after the aura bars.
---
---A collapsing chain (.context/patterns-auracontainer.md "Collapsing a slot
---chain") of slot frames, each the row plus one `bar_spacing` on its leading
---side, joined with no offset.  An empty slot is Hide()n by updateTotemCells
---and takes its spacing out with it, in combat, with no SetPoint: an offset on
---a link would survive the collapse, spacing inside the link does not.
---
---What the chain starts from: under GROUPS the target-helpful block, the last
---link of the aura chain (syncContainerLayout), whose secret extent the engine
---resolves; under SLOTS the last chrome cell, or the box's near edge with no
---spells.  So it runs AFTER the engine layout.  In combat nothing is placed:
---the key turned off hides the rows (collapsing them out of the run) and keeps
---`totemCount`, so turning it back on can show the same rows.
---@param settings table
local function layoutTotemCells(settings)
    local n = totemRowCount(settings)
    for i = n + 1, #totemSlots do totemSlots[i]:Hide() end
    if not InCombatLockdown() then totemCount = n end
    if n == 0 then
        if totemTicker then
            totemTicker:Cancel()
            totemTicker = nil
        end
        return
    end

    local spacing = settings.bar_spacing or 2
    local w, h = itemDims(settings)
    local vertical, growBack, anchorPt = barFlow(settings)

    -- Cross-axis mid-edge points, so the chain keeps the rows centred on the
    -- same line as the bars as well as gapless.
    local trailingPt = vertical and (growBack and "TOP" or "BOTTOM")
        or (growBack and "LEFT" or "RIGHT")
    local prev, prevPt, hx, hy
    if not usingSlots then
        prev, prevPt = targetHelpfulContainer, trailingPt
    elseif #spellList > 0 then
        prev, prevPt = cells[#spellList], trailingPt
    else
        -- Nothing before the rows: start one spacing back, so the first row,
        -- not its spacing, sits on the edge.
        prev, prevPt = pairFrame, anchorPt
        hx = vertical and 0 or (growBack and spacing or -spacing)
        hy = vertical and (growBack and -spacing or spacing) or 0
    end
    for i = 1, n do
        local cell = totemCellFor(i)
        local slotFrame = totemSlots[i]
        slotFrame:ClearAllPoints()
        slotFrame:SetPoint(anchorPt, prev, prevPt, hx or 0, hy or 0)
        if vertical then
            slotFrame:SetSize(w, h + spacing)
        else
            slotFrame:SetSize(w + spacing, h)
        end
        cell:ClearAllPoints()
        cell:SetPoint(trailingPt, slotFrame, trailingPt)
        -- Geometry, borders, fill colour and both fonts, identical to a bar
        -- button's -- the cue_totem guard is the only difference.
        restyleBarButton(cell, settings)
        prev, prevPt, hx, hy = slotFrame, trailingPt, nil, nil
    end

    updateTotemCells()
    if not totemTicker then
        totemTicker = C_Timer.NewTicker(TOTEM_POLL, updateTotemCells)
    end
end

---Re-evaluate proc_glow across both sections.  Slots-only (see SyncProcGlow);
---under groups the lists are empty, which stops every glow.  Needs no CDM bridge — IsSpellOverlayed answers from the
---spell ID alone.  The glow rides the chrome CELL, which is the bar's wrapper
---here rather than an icon, so syncProcGlow is shared with the icon tracker
---unchanged.
---@param settings table
local function applyProcGlow(settings)
    local on = usingSlots and (settings.proc_glow_style or "blizzard") ~= "none"
    private.AuraContainer.SyncProcGlow(cells, spellList, on, settings)
end

---Re-evaluate pandemic_glow across both sections.  Like active_glow, and unlike
---proc_glow, this works in BOTH engines — Blizzard drives the region's
---visibility from the aura's own refresh window, so nothing here needs the
---(secret) button↔aura binding.  The
---slots lists only add per-spell `pandemic_glow_excludes`; under groups every
---button follows the tracker-wide setting.  Both registries are walked every
---pass with the idle engine taken through the off branch.
---@param settings table
local function applyPandemicGlow(settings)
    local on = settings.pandemic_glow == true
    private.AuraContainer.SyncPandemic(tracker.name, cells, spellList,
        on and usingSlots, settings)
    private.AuraContainer.SyncPandemic(tracker.name, nil, nil,
        on and not usingSlots, settings)
end

---Switch the slots engine off: every slot takes the never-matching filter and
---the chrome cells are hidden.  Cheap no-op when slots were never allocated.
local function clearSlotEngine()
    private.AuraContainer.SyncSlots(container, BAR_FILTERS, EMPTY_LIST,
        cellForSlot, initSlotButton)
    private.AuraContainer.SyncSlots(targetContainer, TARGET_HARMFUL_FILTERS, EMPTY_LIST,
        cellForSlot, initSlotButton)
    private.AuraContainer.SyncSlots(targetHelpfulContainer, TARGET_HELPFUL_FILTERS,
        EMPTY_LIST, cellForSlot, initSlotButton)
    for i = 1, #cells do cells[i]:Hide() end
    wipe(spellList)
end

-- ---------------------------------------------------------------------------
-- Component lifecycle
-- ---------------------------------------------------------------------------

tracker.Initialize = function()
    -- Register dirty-flag restyle BEFORE makeBarInit so the initial acquire
    -- styling in makeBarInit finds the restyleFn in trackerState.
    private.AuraContainer.RegisterTracker(name, restyleBarButton)

    -- Component/anchor-facing frame: addon-owned rect, nothing anchors it to the
    -- (secret-sized) bounds frame below, so its rect never goes secret.
    --
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

    -- Bounds frame enclosing BOTH containers — sized to them by
    -- ResizeToBoundsRect (engine-side, no secret value crosses into Lua) and
    -- then placed on the wrapper as a unit.  Size from the children, position
    -- from the single anchor to `wrapper`: no circular dependency.
    -- DisableUntrustedLayoutScriptsTemplate is REQUIRED — see the matching note
    -- in Components/BuffTracker.lua (Blizzard_CustomAuraContainer.lua:318-321).
    -- Native containers only; classic has neither the template nor the aspect.
    pairFrame = CreateFrame("Frame", prefix .. "_Pair", wrapper,
        LAC.IsNative and "DisableUntrustedLayoutScriptsTemplate" or nil)

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
    -- A block hidden by syncSelfTargetSuppression closes its place in the
    -- chain, so the totem rows after it slide up rather than wait behind it.
    container:SetCollapsesLayout(true)
    targetContainer:SetCollapsesLayout(true)
    targetHelpfulContainer:SetCollapsesLayout(true)

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
            targetContainer:UpdateAllAuras()
            targetHelpfulContainer:UpdateAllAuras()
            -- Combat-safe (SetShown on our own frame), which is why this can
            -- run on every target change while Refresh cannot.
            syncSelfTargetSuppression()
        else
            applyProcGlow(getSettings())
        end
    end)

    initFn = makeBarInit()

    registerTrackerCallbacks()

    private.CustomSpells.OnEnable(name)

    tracker.Refresh()
end

tracker.GetFrame = function()
    return wrapper
end

tracker.Refresh = function()
    if not container then return end

    if not getEnabled() and not private.isEditMode then
        if not InCombatLockdown() then
            wrapper:Hide()
        end
        return
    end

    -- AuraContainer layout API calls are restricted in combat.  The totem rows
    -- are not one of them: Show, Hide and the ticker need no geometry, so the
    -- key is honoured here in BOTH directions over rows that are already
    -- placed — off is `layoutTotemCells`' own teardown, on restarts the poll,
    -- which shows the filled slots.  Only PLACING them has to wait, so an
    -- enable mid-fight with no rows placed does nothing until combat ends.
    if InCombatLockdown() then
        -- The combat-exit pass re-runs this Refresh without the font pass, so a
        -- font edited mid-fight goes on the persistent restyle flag now.
        if private.fontsDirty then private.AuraContainer.MarkDirty(name) end
        local s = getSettings()
        if not s.show_totems then
            layoutTotemCells(s)
        elseif totemCount > 0 and not totemTicker then
            updateTotemCells()
            totemTicker = C_Timer.NewTicker(TOTEM_POLL, updateTotemCells)
        end
        return
    end

    local settings = getSettings()
    local spellMap = buildSpellMap()
    spellCount = 0
    for _ in pairs(spellMap) do spellCount = spellCount + 1 end

    -- Display mode: always_show_tracked, Blizzard's "Hide when inactive" copied
    -- in once (pm.MigrateHideWhenInactive).  Same rationale as the icon twin
    -- (Core/AuraIconTracker.lua).
    usingSlots = tracker.IsUsingSlots()

    -- Per-spell unit scope: which of the three groups each tracked spell may
    -- appear in.  Independent of the self-target suppression below — this is the
    -- user's "only ever a self-buff / only ever on the target" restriction.
    -- Expanded ONCE per Refresh and shared with the slots engine, so both
    -- engines resolve a spell's scope identically.
    local scopeMap = private.AuraContainer.ExpandUnitScope(settings.aura_unit)
    local playerMap, targetHarmfulMap, targetHelpfulMap =
        private.AuraContainer.SplitByUnitScope(spellMap, scopeMap)

    -- The idle engine takes the never-matching include map, so exactly one of
    -- the two is ever holding frames.  Neither has a public removal API; an
    -- empty includeSpellIDs is the sanctioned off switch.
    if usingSlots then
        playerMap, targetHarmfulMap, targetHelpfulMap = EMPTY_MAP, EMPTY_MAP, EMPTY_MAP
    end
    local layoutOpts = buildLayoutOpts(settings)
    private.AuraContainer.SyncGroup(container, name .. "_main", PLAYER_HELPFUL,
        playerMap, initFn, layoutOpts, identitySetFor)
    private.AuraContainer.SyncGroup(targetContainer, name .. "_target_harmful",
        PLAYER_HARMFUL, targetHarmfulMap, initFn, layoutOpts, identitySetFor)
    private.AuraContainer.SyncGroup(targetHelpfulContainer, name .. "_target_helpful",
        PLAYER_HELPFUL, targetHelpfulMap, initFn, layoutOpts, identitySetFor)

    if usingSlots then
        syncSlotEngine(spellMap, scopeMap)
    else
        clearSlotEngine()
        syncContainerLayout(settings)
    end

    -- Settle the self-target state here too: PLAYER_TARGET_CHANGED covers every
    -- transition, but a login or profile switch with the player already
    -- self-targeted fires no such event.  syncContainerLayout re-Shows nothing,
    -- so ordering after it is not load-bearing — only clarity.
    syncSelfTargetSuppression()

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

    -- AFTER the restyle, never before: restyleBarButton resets every bar to the
    -- global bar_fill_color, and layoutBarCells is what re-applies the per-spell
    -- spell_colors override on top.
    if usingSlots then
        layoutBarCells(settings)
    end

    -- After both engines: the totem rows trail the run and chain onto its last
    -- link.  With the key off it is what hides the rows and stops the poll, so
    -- it needs no counterpart in clearSlotEngine.
    layoutTotemCells(settings)

    -- active_glow needs no event driver and no pass here: its border is bound
    -- into the aura button's subtree, so Blizzard's own show/hide of the button
    -- is the glow.  restyleBarButton carries the on/off and the colour.

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

    -- pandemic_glow needs no event driver — Blizzard's own OnUpdate on the aura
    -- button decides when the region shows; this only carries the configuration.
    applyPandemicGlow(settings)

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

    -- Under slots the reported size is content-derived, so a spell-count change
    -- moves the box too — rare (talents / spec / CDM config), never a combat
    -- path.  Both trackers are updated BEFORE the call so the re-entrant Refresh
    -- it triggers sees no further transition.
    local nowCollapsed = tracker.IsCollapsed()
    -- Totem rows count here too: they are reserved space, and their number moves
    -- with the setting and with GetNumTotemSlots on a spec change.  They also
    -- reach GetComponentSize under GROUPS (the branch with no settings.height —
    -- an Additional Frame), which the spell count never does, so the trigger
    -- cannot stay slots-only once the rows can render there.
    local rowCount = spellCount + totemRowCount(settings)
    if nowCollapsed ~= wasCollapsed
        or ((usingSlots or settings.show_totems) and rowCount ~= lastSlotCount) then
        wasCollapsed = nowCollapsed
        lastSlotCount = rowCount
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
    -- Same leak class as the bounds-frame OnUpdate above: a ticker survives the
    -- tracker, and a deleted Additional Frame's poll would run forever.
    if totemTicker then
        totemTicker:Cancel()
        totemTicker = nil
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
---GROUPS (hide-when-inactive): FIXED SIZE, same rationale as BuffTracker — the
---aura container's real rect is engine-owned and secret, so a content-hugging
---size could only be estimated from the MAPPED spell count, which over-reserves
---permanently while presenting itself to the anchor system as dynamic.
---Permanently correct there; nothing else is possible.
---
---SLOTS (always-show): the extent is ours.  Only a HORIZONTAL run derives its
---WIDTH from the bar count — a vertical stack's width is still the configured
---(or inherited) bar width, so it stays fixed.
tracker.GetWantsContentWidth = function()
    if not usingSlots then return false end
    local s = getSettings()
    -- IconOnly + collapse shrinks each item to icon_size (itemDims), so the box
    -- has to hug that width instead of the configured bar_width.  Kept inside
    -- the slots gate: under groups the size estimate is deliberately fixed
    -- (§D4), since the visible count is secret there.
    if s.bar_content == "IconOnly" and s.collapse then return true end
    return (s.layout_direction or "vertical") == "horizontal"
end

---Returns true when nothing is tracked.  Reserved totem rows are content: a
---tracker showing only summon rows is not collapsed.
tracker.IsCollapsed = function()
    return spellCount + totemRowCount(getSettings()) == 0
end

---Empty and not in EditMode reports 0, 0 in either engine so the anchor system
---can close the gap entirely.
---
---Under SLOTS the box is the real stack extent — `itemDims` per bar times the
---live count plus the gaps, i.e. exactly what layoutBarCells placed.
---
---Under GROUPS it is the CONFIGURED size, not a content estimate (see
---GetWantsContentWidth). Width follows the anchor-inherited size when there is
---one, exactly as `itemDims` does for the bars themselves, so the box can never
---be narrower than the bars it contains.
---
---`settings.height` is a COMPONENT-level box height that only the primary
---tracker has — an Additional Frame's profile carries `bar_height` (per item)
---and no box height at all (`createDefaultBarSettings`), so the old
---`settings.height or 100` literal reserved a 100px box for a 30px bar and
---pushed every anchored dependent down. Absent that key, fall back to the same
---stack extent the slots branch computes: the MAXIMUM the tracker can occupy,
---which over-reserves only while fewer auras are up — the documented groups
---tradeoff, since the live count is secret.
tracker.GetComponentSize = function()
    local settings = getSettings()
    -- Reserved totem rows occupy the run exactly as a tracked bar does.
    local count = spellCount + totemRowCount(settings)
    if count == 0 and not private.isEditMode then return 0, 0 end
    if usingSlots or not settings.height then
        local iw, ih = itemDims(settings)
        local n = math.max(1, count)
        local spacing = settings.bar_spacing or 2
        if (settings.layout_direction or "vertical") == "horizontal" then
            return n * iw + (n - 1) * spacing, ih
        end
        return iw, n * ih + (n - 1) * spacing
    end
    local w = private.Anchor.GetInheritedWidth(tracker.name)
    if not (w and w > 0) then w = settings.width or 250 end
    -- Totem rows come on top of the configured box: they follow the aura
    -- stack, so the reservation is the box plus the rows we placed.
    -- Over-reserves while fewer auras are up — the same groups tradeoff as
    -- the box itself.
    local n = totemRowCount(settings)
    if n == 0 then return w, settings.height end
    local iw, ih = itemDims(settings)
    local spacing = settings.bar_spacing or 2
    if (settings.layout_direction or "vertical") == "horizontal" then
        return w + n * (iw + spacing), settings.height
    end
    return w, settings.height + n * (ih + spacing)
end

    return tracker
end

---@type aurabartrackerfacade
private.AuraBarTracker = {
    CreateTracker = createTracker,
}

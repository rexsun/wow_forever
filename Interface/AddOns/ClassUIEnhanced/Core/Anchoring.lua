
local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field Anchor anchor

---@class anchor : table
---@field Initialize fun() Initializes the anchoring system
---@field OnComponentStateChange fun() Re-runs layout when a component is enabled or disabled
---@field Refresh fun() Applies the component-settings-driven layout to all component frames
---@field IsAnchorChainVisible fun(componentName: string): boolean Check if a component's anchor parent chain resolves to a valid enabled parent
---@field IsVisibleForComponent fun(componentName: string): boolean Returns true when a component should be visible (Edit Mode active OR anchor chain visible)
---@field WouldCreateCycle fun(componentName: string, newParent: string): boolean Check if an anchor_parent or position_reference change would create a circular chain
---@field MigrateAnchorProfiles fun() Migrate legacy visibility modes and anchor_offset to anchor_offset_x/y and add anchor_width_mode defaults
---@field InvalidateTargetRuleCache fun() Recalculate whether any component uses the no_target visibility rule or a combat-dependent visibility
---@field RefreshVisibilityOnly fun() Refresh for visibility rule changes (target/mount/combat)
---@field RebuildAnchorTree fun() Rebuild the static anchor tree (call after anchor parent changes)
---@field GetInheritedWidth fun(componentName: string): number? Returns the parent-constrained width for a component, or nil if free-moving/absolute
---@field GetInheritedHeight fun(componentName: string): number? Returns the parent-constrained height for a component on left/right side anchors in percent mode
---@field GetEffectiveAlpha fun(componentName: string): number Returns the effective alpha for a component (inherited parent alpha in inherit mode, own alpha otherwise, or fade from visibility rules)
---@field GetEffectiveStrata fun(componentName: string): string Returns the effective frame strata for a component (own setting if set, else walked from anchor chain, fallback "MEDIUM")
---@field ClearAllComponentPoints fun() Clear WoW-level anchor points on all component frames before a profile switch
---@field BeginBulkRefresh fun() Suppress OnComponentStateChange during bulk operations
---@field EndBulkRefresh fun() Resume OnComponentStateChange after bulk operations
---@field HasAnchoredDependents fun(name: string): boolean True if any component anchors to `name` (i.e. needs repositioning when `name`'s frame resizes)
---@field ForceVisibleMatters fun(name: string): boolean True if `name`'s GetForceVisible() override can actually change its visibility outcome (i.e. some mode/rule/chain would otherwise hide it). False = flipping forceVisible is inert, so callers must skip the refresh. Conservative: true when undecidable
---@field RelayoutSubtree fun(name: string, widthChanged?: boolean, heightChanged?: boolean) Reposition only name's anchored subtree (synchronous, same-frame) instead of a full Refresh when name resizes. widthChanged/heightChanged (explicit booleans from setTargetSize) gate which dependents relayout; nil = relayout all

---@type anchor
---@diagnostic disable-next-line: missing-fields
local anchor = {}

---Druid shapeshift form IDs that count as "mounted" for visibility purposes.
---27 = Travel Form, 29 = Flight Form, 3 = Travel Form (ground), 4 = Aquatic Form.
local druidTravelFormIDs = {[3] = true, [4] = true, [27] = true, [29] = true}

---Whether any component currently uses the no_target visibility rule.
---Cached to avoid iterating all components on every PLAYER_TARGET_CHANGED.
local anyComponentUsesTargetRule = false

---Whether any component's visibility depends on combat, split by what the pull
---has to do about it.  A hide (an out_of_combat "hide" rule, or the legacy
---"only_in_combat" mode) reveals frames, which takes a full pass; a fade only
---changes alpha, which RefreshVisibilityOnly covers.  With neither, entering
---combat changes nothing a layout pass computes, so the pull runs no pass.
local anyComponentHidesOutOfCombat = false
local anyComponentFadesOutOfCombat = false

---Check whether the "mounted" condition is currently active (mounted, vehicle,
---pet battle, taxi, druid travel form, client scene).
---@return boolean
local isMountedConditionActive = function()
    return IsMounted() or druidTravelFormIDs[GetShapeshiftFormID()]
        or UnitHasVehicleUI("player") or UnitOnTaxi("player")
        or (C_PetBattles and C_PetBattles.IsInBattle())
        or C_ActionBar.HasOverrideActionBar() or private.inClientScene
end

-- Per-pass cached game state. Seeded at the start of applyLayout,
-- RelayoutSubtree and RefreshVisibilityOnly, cleared at the end, and read
-- through the three accessors below by evaluateVisibilityRules,
-- evaluateVisibilityMode, layoutRecursive and anchor.IsMounted. Eliminates
-- redundant game API calls within a single layout pass; outside a pass the
-- cache is nil and each accessor falls through to the live query.
--
-- These MUST stay above their first reader: Lua 5.1 binds an upvalue at
-- closure-definition time, so a reader compiled above the declaration captures
-- the global of the same name (always nil) instead of the local, and the cache
-- silently never applies. That was the state until 2026-08-23 —
-- evaluateVisibilityRules sat above the old declaration site and paid three
-- live API calls per component per pass.
local cachedIsMounted
local cachedInCombat
local cachedHasTarget
-- The target state the last whole-tree pass (applyLayout, RefreshVisibilityOnly)
-- evaluated.  RelayoutSubtree walks one subtree, so it does not write it.
local appliedHasTarget

---Per-pass "mounted" state: the cached value during a layout pass, a live query
---outside one. Written as an explicit nil test rather than
---`cached ~= nil and cached or live()` — that idiom falls through to the live
---call whenever the cached value is FALSE, which is the common case, so it
---cached only the rarer answer.
---@return boolean
local function passIsMounted()
    if cachedIsMounted == nil then return isMountedConditionActive() end
    return cachedIsMounted
end

---Per-pass combat state. Same contract as passIsMounted.
---@return boolean
local function passInCombat()
    if cachedInCombat == nil then return InCombatLockdown() end
    return cachedInCombat
end

---Per-pass target state. Same contract as passIsMounted.
---@return boolean
local function passHasTarget()
    if cachedHasTarget == nil then return UnitExists("target") end
    return cachedHasTarget
end

---True when any `visibility_rules` entry is set to "hide". Used to force rule
---evaluation under otherwise pass-through visibility modes — a hide dropdown
---is an additive user intent that must not be suppressed by "inherit".
---@param settings table
---@return boolean
local hasAnyHideRule = function(settings)
    local rules = settings and settings.visibility_rules
    if not rules then return false end
    return rules.mounted == "hide"
        or rules.out_of_combat == "hide"
        or rules.no_target == "hide"
end

---Evaluate visibility rules for a component's settings.
---Returns whether the component should be shown, and a fade multiplier (1.0 = full).
---Hide uses OR logic: any active hide condition hides the frame.
---Fade uses AND logic: ALL configured fade conditions must be met simultaneously.
---When editMode is true, "hide" actions are skipped (frames stay visible for
---repositioning) but "fade" actions still apply as a live preview.
---@param settings table  component settings (must have .visibility_rules or nil)
---@param editMode boolean?  true when in Edit Mode
---@return boolean visible
---@return number fadeMultiplier
local evaluateVisibilityRules = function(settings, editMode)
    local rules = settings.visibility_rules
    if not rules then return true, 1 end

    local fadeAlpha = (rules.fade_alpha or 30) / 100
    local dominated = false  -- any "hide" condition currently met (OR logic)
    local fadeConfigured = 0 -- how many conditions are set to "fade"
    local fadeMet = 0        -- how many of those are currently triggered

    -- Mounted condition
    local mounted = passIsMounted()
    if rules.mounted == "hide" then
        if mounted then dominated = true end
    elseif rules.mounted == "fade" then
        fadeConfigured = fadeConfigured + 1
        if mounted then fadeMet = fadeMet + 1 end
    end

    -- Out of combat condition
    local inCombat = passInCombat()
    if rules.out_of_combat == "hide" then
        if not inCombat then dominated = true end
    elseif rules.out_of_combat == "fade" then
        fadeConfigured = fadeConfigured + 1
        if not inCombat then fadeMet = fadeMet + 1 end
    end

    -- No target condition
    local hasTarget = passHasTarget()
    if rules.no_target == "hide" then
        if not hasTarget then dominated = true end
    elseif rules.no_target == "fade" then
        fadeConfigured = fadeConfigured + 1
        if not hasTarget then fadeMet = fadeMet + 1 end
    end

    local fadeVal = (fadeConfigured > 0 and fadeMet == fadeConfigured) and fadeAlpha or 1
    if dominated and not editMode then return false, fadeVal end
    return true, fadeVal
end

---Resolve settings table and enabled state for a component name or additional
---frame ID.  Used by the alpha/fade chain walkers so they handle both component
---and AF anchors uniformly.
---@param name string
---@return table? settings
---@return boolean isEnabled
local resolveSettings = function(name)
    local comp = private.ComponentManager.GetComponent(name)
    if comp then
        return comp.GetSettings(), comp.GetEnabled()
    end
    if private.profile and private.profile.additional_frames then
        local afData = private.profile.additional_frames[name]
        if afData then
            return afData, afData.enabled ~= false
        end
    end
    return nil, false
end

---Tracks which root component frames have had visibility hooks installed.
---Keyed by frame reference to avoid storing addon state on Blizzard frames.
---@type table<frame, boolean>
local rootVisibilityWatched = {}

---External anchor frame names whose _G[name] hasn't resolved yet.
---Watched via ADDON_LOADED until the frame appears, then re-layout fires.
---@type table<string, boolean>
local pendingExternalFrames = {}

-- Forward-declared: assigned after applyLayout. Used by checkPendingExternalFrames
-- to guard against premature OnComponentStateChange before Initialize().
local isReady = false

---Components excluded from anchor chain resolution.
---When encountered as an anchor parent, resolveParentFrame walks past them to
---their own parent.  Dynamic-content components should use IsCollapsed instead
---(see TrinketTracker, BuffTracker) — it achieves the same skip-past behavior
---but only when the component actually has no visible content.
---This table is used by additional frames (registered via RegisterAdditionalFrame)
---which have dynamic content but no IsCollapsed implementation.
---@type table<componentname, boolean>
local nonAnchorableComponents = {
}

---Components using SecureActionButton children.  Membership means one thing
---only: their own position/size cannot be written during combat, so
---`layoutRecursive` and `ClearAllComponentPoints` skip them until it ends.
---
---The three AuraContainer trackers (BuffTracker, BuffTrackerBars,
---OutboundBuffTracker) were members on the premise that an AuraContainer makes
---its component frame protected.  It does not: that frame is a plain wrapper
---around the containers, and in combat, with an aura shown,
---`CUE_BT_Container:IsProtected()` read `false false` and a `Hide()`/`Show()`
---pair went through (2026-09-28).  The freeze cost them their visibility for
---whole fights: a wrapper hidden out of combat -- under a mount-hidden anchor
---parent, attacking straight off the mount -- could not be shown again until
---combat ended, and a hidden AuraContainer registers no UNIT_AURA.  They lay
---out in combat like any other component now.
---@type table<string, boolean>
local secureComponents = {
    ConsumableBuffTracker = true,
    RaidBuffTracker = true,
}

---The trackers whose protection comes from `SecureActionButtonTemplate`
---children -- the same members as `secureComponents`, kept apart because the
---two answer different questions (combat freeze vs. anchor-chain legality and
---which anchoring widgets to show).  ONLY these cascade blocked
---SetWidth/SetHeight/ClearAllPoints along an anchor chain, so only these are
---steered onto `position_reference` by the anchoring panels, and only these are
---barred from chaining across the secure boundary.
---
---The AuraContainer-only trackers chain normally: all three have shipped
---`anchor_parent` defaults since they were written — BuffTracker and
---BuffTrackerBars to the **non-secure** CooldownTracker, which relayouts
---hundreds of times per second in combat without ever blocking.  Treating them
---as secure-click cost them the anchor widgets they were actually configured
---with, and offered them a `position_reference` that could never take effect.
---@type table<string, boolean>
local secureClickComponents = {
    ConsumableBuffTracker = true,
    RaidBuffTracker = true,
}

---Static anchor tree. Children lists keyed by component name.
---Rebuilt only when components are enabled/disabled or anchor parents change.
---@type table<string, string[]>
local anchorChildren = {}

---Root components (anchor_parent = "none" or external anchor).
---@type string[]
local anchorRoots = {}

---Last-computed layout results. Overwritten in-place during each layout pass
---(no table allocation). Read by GetEffectiveAlpha, IsAnchorChainVisible, etc.
---@type table<string, {alpha: number, fade: number, rootVisible: boolean, anchorFrame: Frame?}>
local lastResult = {}

---Rebuild the static anchor tree from current component settings.
---Called on enable/disable, anchor parent changes, and profile switches.
local rebuildAnchorTree = function()
    wipe(anchorRoots)
    -- Clear children lists without deallocating tables
    for k, v in pairs(anchorChildren) do
        wipe(v)
    end
    for _, comp in ipairs(private.ComponentManager.GetAllComponents()) do
        local name = comp.GetComponentName()
        if not anchorChildren[name] then anchorChildren[name] = {} end
        -- Pre-create lastResult entry (no allocation during layout)
        if not lastResult[name] then
            lastResult[name] = { alpha = 1, fade = 1, rootVisible = true, anchorFrame = nil, effectiveStrata = "MEDIUM" }
        end
        local ap = comp.GetSettings().anchor_profile
        local parentName = ap and ap.anchor_parent
        if not parentName or parentName == "none" or parentName == "cursor" or private.externalAnchors[parentName] then
            -- True root, or anchored to an external frame (position-only parent).
            anchorRoots[#anchorRoots + 1] = name
        elseif private.ComponentManager.GetComponent(parentName) then
            -- Known CUE component parent — add as child in the tree.
            if not anchorChildren[parentName] then anchorChildren[parentName] = {} end
            local t = anchorChildren[parentName]
            t[#t + 1] = name
        else
            -- Unknown parent (e.g. external anchor not yet registered via AddAnchors,
            -- or a stale saved variable). Treat as root so the component still gets
            -- laid out with free-moving fallback instead of being orphaned.
            anchorRoots[#anchorRoots + 1] = name
        end
    end

    -- Detect unreachable components (cycles in anchor_parent chains) and
    -- promote them to roots so they fall back to free-moving positioning
    -- instead of silently disappearing.
    local reachable = {}
    local function markReachable(n)
        if reachable[n] then return end
        reachable[n] = true
        local ch = anchorChildren[n]
        if ch then
            for _, childName in ipairs(ch) do
                markReachable(childName)
            end
        end
    end
    for _, rootName in ipairs(anchorRoots) do
        markReachable(rootName)
    end
    for _, comp in ipairs(private.ComponentManager.GetAllComponents()) do
        local n = comp.GetComponentName()
        if not reachable[n] then
            anchorRoots[#anchorRoots + 1] = n
            local ap = comp.GetSettings().anchor_profile
            if ap then ap.anchor_parent = "none" end
            markReachable(n)
        end
    end
end

---Resolve the raw SetPoint arguments from an anchor_profile.
---Used for free-moving components (anchor_parent = "none") and as a fallback
---when no valid parent can be resolved.
---@param anchorProfile anchor_profile
---@return string, frame?, string, number, number
local getAnchorPoint = function(anchorProfile)
    local framePoint = anchorProfile.frame_point
    local relativeTo = anchorProfile.relative_frame
    local relativePoint = anchorProfile.parent_point
    local xOffset = anchorProfile.xoff
    local yOffset = anchorProfile.yoff

    ---@type frame
    local anchorFrame

    if relativeTo == "UIParent" then
        anchorFrame = _G["UIParent"]
    else
        local component = private.ComponentManager.GetComponent(relativeTo)
        if component then
            local componentMainFrame = component.GetFrame()
            if componentMainFrame then
                anchorFrame = componentMainFrame
            end
        else
            --fallback to a frame in the global namespace
            anchorFrame = _G[relativeTo]
        end
    end

    return framePoint, anchorFrame, relativePoint, xOffset, yOffset
end

---Resolve the effective anchor frame for a component by walking its anchor_parent
---chain upward, skipping any parent that is disabled or has no frame.
---Returns nil when the chain reaches anchor_parent = "none" or no valid frame is found.
---@param componentName string
---@param visited table<string, boolean>?  cycle guard
---@return frame?
local resolveParentFrame
resolveParentFrame = function(componentName, visited)
    visited = visited or {}
    if visited[componentName] then return nil end  -- circular chain guard
    visited[componentName] = true

    local component = private.ComponentManager.GetComponent(componentName)
    if not component then return nil end

    local compSettings = component.GetSettings()
    local anchorProfile = compSettings and compSettings.anchor_profile
    if not anchorProfile then return nil end

    local parentName = anchorProfile.anchor_parent
    if not parentName or parentName == "none" or parentName == "cursor" then return nil end

    local parentComponent = private.ComponentManager.GetComponent(parentName)

    -- Parent is an external anchor frame registered by another addon.
    -- External anchors are position-only leaf nodes; return the frame if it
    -- exists in _G (nil when the frame hasn't been created yet → free-moving fallback).
    if not parentComponent then
        if private.externalAnchors[parentName] then
            return _G[parentName]
        end
        return nil
    end

    -- Non-anchorable components (e.g. BuffTracker) are always skipped in the
    -- chain regardless of their enabled state or frame existence.  Children
    -- that reference them resolve to the non-anchorable component's own parent.
    if nonAnchorableComponents[parentName] then
        return resolveParentFrame(parentName, visited)
    end

    if parentComponent.GetEnabled() or private.isEditMode then
        -- Collapsed-but-enabled parents stay in the chain: their frame is still
        -- positioned (with zero content size), so children anchored to it sit at
        -- a stable location instead of jumping to the grandparent with their own
        -- anchor_side. Only fully disabled parents get walked past.
        local parentFrame = parentComponent.GetFrame()
        if parentFrame then return parentFrame end
    end

    -- Parent is disabled or has no frame; walk up to the parent's own parent.
    return resolveParentFrame(parentName, visited)
end

---anchor_profile fields inherited from an absent parent. Everything NOT in
---this list stays the child's own (width_pct, width_mode, and any fields
---added to anchor_profile in the future). See the absent-parent block in
---layoutRecursive for the shallow-copy-then-overwrite flow.
local inheritedPositionFields = {
    "frame_point",
    "parent_point",
    "relative_frame",
    "xoff",
    "yoff",
    "anchor_parent",
    "anchor_side",
    "anchor_offset_x",
    "anchor_offset_y",
    "position_reference",
    "position_side",
    "position_offset",
}

---True when the immediate parent is truly absent: not registered, disabled
---(outside EditMode), or enabled but has not produced a frame this session
---(e.g. CooldownTracker while CDM is off). An empty-but-framed parent
---(IsCollapsed == true) is NOT considered absent — use parentIsCollapsed
---for that. Callers:
---  * Positioning (layoutRecursive) combines both into the inheritance path.
---  * Width/height/visibility helpers short-circuit ONLY on truly-absent
---    parents — for collapsed parents the width/visibility chain still
---    resolves against the parent's configured size.
---@param componentName string
---@return boolean
local function parentIsAbsent(componentName)
    local component = private.ComponentManager.GetComponent(componentName)
    if not component then return false end
    local s = component.GetSettings()
    local ap = s and s.anchor_profile
    if not ap then return false end
    local parentName = ap.anchor_parent
    if not parentName or parentName == "none" or parentName == "cursor" then
        return false
    end
    if private.externalAnchors and private.externalAnchors[parentName] then
        return false
    end
    local parent = private.ComponentManager.GetComponent(parentName)
    if not parent then return true end
    if nonAnchorableComponents[parentName] then return false end
    -- Parent never produced a frame this session (e.g. a component whose
    -- Initialize has not run yet). Treat as absent in ALL modes, including
    -- Edit Mode, because there is no frame for the child to anchor against;
    -- without this, Edit Mode positions children at a non-existent frame's
    -- nil coordinates and they render at the wrong spot.
    if parent.GetFrame and parent.GetFrame() == nil then return true end
    -- Edit Mode bypass for user-toggled-off parents: the parent's frame still
    -- exists as a placeholder so children can chain-anchor normally for
    -- repositioning. Only parents that are disabled AND framed hit this
    -- bypass; frameless parents above already returned true.
    if private.isEditMode then return false end
    if not parent.GetEnabled() then return true end
    return false
end

---True when the immediate parent is present (enabled, framed) but has no
---content to show this pass (IsCollapsed returns true). Semantically: empty
---!= hidden — a collapsed parent is a valid reason to walk past it, but
---its children's own visibility is independent of its content count.
---  * Positioning — collapsed parents route children through the
---    anchor_profile-inheritance path so they land at the parent's
---    would-be slot instead of anchoring to a zero-sized frame.
---  * Visibility (IsAnchorChainVisible / isRootFrameVisible) — treated
---    the same as absent parents: children fall back to a free-moving
---    root for the visibility cascade so an empty parent does not
---    cascade-hide content-bearing children.
---  * Width/height inheritance — collapsed parents still have a valid
---    configured size via GetComponentSize, so inheritance flows normally;
---    this is the ONE dimension where collapsed differs from absent.
---@param componentName string
---@return boolean
local function parentIsCollapsed(componentName)
    local component = private.ComponentManager.GetComponent(componentName)
    if not component then return false end
    local s = component.GetSettings()
    local ap = s and s.anchor_profile
    if not ap then return false end
    local parentName = ap.anchor_parent
    if not parentName or parentName == "none" or parentName == "cursor" then
        return false
    end
    if private.externalAnchors and private.externalAnchors[parentName] then
        return false
    end
    local parent = private.ComponentManager.GetComponent(parentName)
    if not parent then return false end
    if private.isEditMode then return false end
    if nonAnchorableComponents[parentName] then return false end
    if not parent.GetEnabled() then return false end
    if parent.GetFrame and parent.GetFrame() == nil then return false end
    return (parent.IsCollapsed and parent.IsCollapsed()) or false
end

---True when componentName's immediate parent is present (component exists,
---has a frame, has its own anchor_profile) but disabled (GetEnabled() returns
---false). Strict subset of parentIsAbsent(): only the "disabled with frame
---and chain" case — not no-frame, external, non-anchorable, or missing.
---Walking past such a parent during visibility inheritance matches what the
---parent would have done if enabled (inherit from its own parent).
---@param componentName string
---@return boolean
local function parentIsDisabledButChained(componentName)
    local component = private.ComponentManager.GetComponent(componentName)
    if not component then return false end
    local s = component.GetSettings()
    local ap = s and s.anchor_profile
    if not ap then return false end
    local parentName = ap.anchor_parent
    if not parentName or parentName == "none" or parentName == "cursor" then return false end
    if private.externalAnchors and private.externalAnchors[parentName] then return false end
    if nonAnchorableComponents[parentName] then return false end
    local parent = private.ComponentManager.GetComponent(parentName)
    if not parent then return false end
    if private.isEditMode then return false end
    if parent.GetFrame and parent.GetFrame() == nil then return false end
    if parent.GetEnabled() then return false end
    local pSettings = parent.GetSettings()
    if not (pSettings and pSettings.anchor_profile) then return false end
    return true
end

---Walk anchor chain to root; return false if root frame is hidden/alpha 0.
---Stable within a single applyLayout() pass (only Blizzard toggles the root).
---@param componentName string
---@return boolean
local isRootFrameVisible = function(componentName)
    local visited = {}
    local current = componentName
    while current do
        if visited[current] then return true end
        visited[current] = true
        local comp = private.ComponentManager.GetComponent(current)
        if not comp then
            -- External anchors are position-only — never dictate CUE visibility.
            if private.externalAnchors[current] then
                return true
            end
            return true
        end
        local ap = comp.GetSettings().anchor_profile
        if not ap then return true end
        local parentName = ap.anchor_parent
        local naturalRoot = (not parentName or parentName == "none" or parentName == "cursor")

        if naturalRoot then
            -- Prefer the computed rootVisible from the last layout pass over
            -- raw frame state for our own components. Frame IsShown() reflects
            -- our own Show/Hide side effects AND any external toggle; the
            -- cache is the authoritative "what did our rules decide" signal
            -- and sidesteps the mount-transition deadlock (OnHide clears
            -- viewer alpha, component Refresh guards on alpha>0, viewer never
            -- restores). Fall back to frame state when no cache entry exists
            -- (bootstrap before the first applyLayout pass).
            local r = lastResult[current]
            if r ~= nil then return r.rootVisible end
            local frame = comp.GetFrame()
            return frame ~= nil and frame:IsShown()
        end

        -- Parent is disabled-but-chained (has frame, has own anchor_profile):
        -- walk past it so visibility inheritance reaches the grandparent —
        -- matches "inherit" intent through a spec-auto-hidden parent.
        if parentIsDisabledButChained(current) then
            current = parentName
        -- Other "absent" reasons (no frame yet, external anchor, non-
        -- anchorable, missing component) or "collapsed" (empty content this
        -- pass): free-moving fallback — "empty != hidden". Do NOT bind
        -- visibility to an absent/collapsed ancestor that may flicker
        -- mid-refresh.
        elseif parentIsAbsent(current) or parentIsCollapsed(current) then
            return true
        else
            current = parentName
        end
    end
    return true
end

---Use ClearAllPointsBase to bypass EditMode override chain and avoid taint.
---@param frame frame
local safeClearAllPoints = function(frame)
    if frame.ClearAllPointsBase then
        frame:ClearAllPointsBase()
    else
        frame:ClearAllPoints()
    end
end

---Use SetPointBase to bypass EditMode override chain and avoid taint.
---Non-system frames use private.Pixel.SetPoint for pixel-perfect positioning.
---NOTE: it snaps to pixel boundaries (PixelUtil the offsets, the engine flag
---the whole rect) — user-configured offsets
---(anchor_offset_x/y) may shift by up to 0.5px at non-100% UI scales.
---If positioning looks off, check this first.
---@param frame frame
---@param point string
---@param relativeTo frame
---@param relativePoint string
---@param offsetX number
---@param offsetY number
local safeSetPoint = function(frame, point, relativeTo, relativePoint, offsetX, offsetY)
    if frame == relativeTo then return end
    if frame.SetPointBase then
        frame:SetPointBase(point, relativeTo, relativePoint, offsetX, offsetY)
    else
        private.Pixel.SetPoint(frame, point, relativeTo, relativePoint, offsetX, offsetY)
    end
end

---Migrate legacy anchor_offset (single value) to anchor_offset_x/anchor_offset_y (raw
---WoW coordinates) and ensure anchor_width_mode is set for all component anchor_profiles.
---Called from ProfileManager.FullLayoutRefresh() to handle existing saved
---variables and imported profiles from older versions.  (OnProfileChanged reaches
---it only transitively — FullLayoutRefresh is that function's layout tail.)
---Kept indefinitely (decided 2026-07-28): it is the only thing upgrading profiles
---saved before those key renames, including imported ones, so removing it breaks
---any profile that has not taken a FullLayoutRefresh since.  The old
---TODO(2026-06-02) removal is cancelled, not deferred.
anchor.MigrateAnchorProfiles = function()
    if not private.profile then return end

    -- Migrate legacy visibility modes into visibility_rules for a single settings table.
    local migrateVisibility = function(data)
        if data.visibility == "hide_when_mounted" then
            data.visibility = "auto"
            data.visibility_rules = data.visibility_rules or {}
            data.visibility_rules.fade_alpha = data.visibility_rules.fade_alpha or 30
            data.visibility_rules.mounted = "hide"
        elseif data.visibility == "only_in_combat" then
            data.visibility = "always"
            data.visibility_rules = data.visibility_rules or {}
            data.visibility_rules.fade_alpha = data.visibility_rules.fade_alpha or 30
            data.visibility_rules.out_of_combat = "hide"
        end
    end

    -- Normalize visibility_rules values: older profiles may store boolean true
    -- instead of the expected string actions ("hide"/"fade"/false).
    local VALID_RULE_ACTIONS = {["hide"] = true, ["fade"] = true}
    local RULE_KEYS = {"mounted", "out_of_combat", "no_target"}
    local normalizeVisibilityRules = function(data)
        local rules = data.visibility_rules
        if not rules then return end
        for _, key in ipairs(RULE_KEYS) do
            local val = rules[key]
            if val == "off" then
                -- Legacy string form of Off; both live surfaces store boolean false.
                rules[key] = false
            elseif val ~= nil and val ~= false and not VALID_RULE_ACTIONS[val] then
                rules[key] = "hide"
            end
        end
    end

    if private.profile.components then
        for _, compData in pairs(private.profile.components) do
            migrateVisibility(compData)
            normalizeVisibilityRules(compData)
            local ap = compData.anchor_profile
            if ap then
                if ap.anchor_offset ~= nil and ap.anchor_offset_x == nil then
                    local side = ap.anchor_side or "bottom"
                    if side == "left" then
                        ap.anchor_offset_x = -(ap.anchor_offset)
                        ap.anchor_offset_y = 0
                    elseif side == "right" then
                        ap.anchor_offset_x = ap.anchor_offset
                        ap.anchor_offset_y = 0
                    elseif side == "top" then
                        ap.anchor_offset_x = 0
                        ap.anchor_offset_y = ap.anchor_offset
                    else -- bottom (default)
                        ap.anchor_offset_x = 0
                        ap.anchor_offset_y = -(ap.anchor_offset)
                    end
                    ap.anchor_offset = nil
                end
                if ap.anchor_width_mode == nil then
                    ap.anchor_width_mode = "percent"
                end
            end
        end
    end

    -- Also migrate additional frames (they have their own visibility field).
    if private.profile.additional_frames then
        for _, afData in pairs(private.profile.additional_frames) do
            migrateVisibility(afData)
            normalizeVisibilityRules(afData)
        end
    end

    anchor.InvalidateTargetRuleCache()
end

---Visited set for the current layout pass — prevents infinite recursion
---if a cycle somehow survives rebuildAnchorTree (e.g. from nonAnchorable migration).
local layoutVisited = {}
---position_reference followers placed in the current pass. Every pass
---re-anchors a follower, and its rect reads back stale for the rest of that
---frame, so a follower OF a follower (RaidBuffTracker follows
---ConsumableBuffTracker by default) rebuilds the rect from the anchor the pass
---published instead. The patterns.md rule: a pass that re-anchors a frame must
---not measure it. Wiped per pass.
local placedThisPass = {}
---Where a frame's centre sits from its single anchor point, in units of its size.
local POINT_TO_CENTER = { TOP = { 0, -0.5 }, BOTTOM = { 0, 0.5 }, RIGHT = { -0.5, 0 }, LEFT = { 0.5, 0 } }
local inheritedWidthCache = {}
local inheritedHeightCache = {}
local visibilityCache = {}
---Pass-scoped memo of component.GetComponentSize() results, keyed by the
---component's registered name.  Only used by getEffectiveParentWidth's
---ancestor query (a content-width parent's size is otherwise recomputed --
---CountVisibleViewerIcons walks all viewer children -- once per content-width
---descendant that queries it in the same pass).  Deliberately NOT used at a
---component's own self-positioning call sites in layoutRecursive: several
---components (GlobalCooldown, SecondaryResources) compute their width from
---live container:GetWidth() when cueAnchorOwnsWidth is set, which their own
---ContentLayout call (later in the same layoutRecursive invocation) mutates --
---caching the pre-ContentLayout value there would leak a stale width forward.
---The ancestor query is safe because top-down recursion guarantees a
---descendant is only visited after its ancestor's ContentLayout has already
---run, so every value ever stored here is already post-ContentLayout.
local componentSizeCache = {}

---Returns (width, height) for `component`, memoized in componentSizeCache for
---the current layout pass.  Width/height are always positive numbers here
---(never nil), so a plain two-value store needs no false-sentinel handling.
---@param name string  component's registered name (cache key)
---@param component table
---@return number width, number height
local function getCachedComponentSize(name, component)
    local cached = componentSizeCache[name]
    if cached then return cached[1], cached[2] end
    local w, h = component.GetComponentSize()
    componentSizeCache[name] = { w, h }
    return w, h
end

---Reusable scratch set for GetEffectiveAlpha's position_reference cycle guard.
---Wiped on every top-level entry; passed through unchanged on recursion.
local effectiveAlphaVisited = {}
---Scratch list of roots deferred to the second layout pass (position_reference
---secure components).  Reused across passes to avoid per-pass table alloc.
local deferredRoots = {}

---Valid WoW frame strata values; used to distinguish explicit settings from
---"inherit" (and to reject garbage values in saved variables).
local validStrata = {
    BACKGROUND = true,
    LOW = true,
    MEDIUM = true,
    HIGH = true,
    DIALOG = true,
    FULLSCREEN = true,
    FULLSCREEN_DIALOG = true,
    TOOLTIP = true,
}

---Resolve a component's effective frame strata by walking the anchor_parent
---chain until an explicit setting is found. Returns "MEDIUM" as the terminal
---fallback. Walks settings directly (not the lastResult cache) so correctness
---is independent of layout pass order.
local function resolveEffectiveStrata(settings, anchorProfile)
    if settings and settings.frame_strata and validStrata[settings.frame_strata] then
        return settings.frame_strata
    end
    local parentName = anchorProfile and anchorProfile.anchor_parent
    local visited
    while parentName and parentName ~= "none" and parentName ~= "cursor" do
        if visited and visited[parentName] then break end
        local parentComp = private.ComponentManager.GetComponent(parentName)
        local parentSettings = parentComp and parentComp.GetSettings()
        if parentSettings and parentSettings.frame_strata and validStrata[parentSettings.frame_strata] then
            return parentSettings.frame_strata
        end
        if not visited then visited = {} end
        visited[parentName] = true
        local parentAp = parentSettings and parentSettings.anchor_profile
        if not parentAp then break end
        parentName = parentAp.anchor_parent
    end
    return "MEDIUM"
end

---Classify a component's anchor SIZING — the derived values that layoutRecursive's
---positioning and dependentNeedsRelayout's skip decision must agree on. Pure function
---of the component's settings (no frame reads), so both read size-inheritance from one
---place: kept in sync by construction, not by the documented invariant. Returns
---multiple values (alloc-free). `liveWidth` is the useTwoPoint condition minus the
---runtime `parentWidth > 0` guard (bottom/top + percent-100 → width live-tracks parent).
---@param component table
---@param settings table
---@param anchorProfile table
---@return boolean wantsContentWidth
---@return string side       resolved anchor side (default "bottom")
---@return string widthMode  resolved width mode (default "percent")
---@return number widthPct   resolved width percent (default 100)
---@return boolean liveWidth bottom/top + percent-100 + not content: width live-tracks parent
local function classifyAnchorSize(component, settings, anchorProfile)
    local wantsContentWidth
    if component.GetWantsContentWidth then
        wantsContentWidth = component.GetWantsContentWidth()
    else
        wantsContentWidth = (settings.layout_direction == "vertical")
    end
    local side = anchorProfile.anchor_side or "bottom"
    local widthMode = anchorProfile.anchor_width_mode or "percent"
    local widthPct = anchorProfile.anchor_width_pct or 100
    local liveWidth = (side == "bottom" or side == "top")
        and widthMode == "percent"
        and widthPct == 100
        and not wantsContentWidth
    return wantsContentWidth, side, widthMode, widthPct, liveWidth
end

---Recursive layout function. Positions a component and recurses to its children.
---Parent values are passed as parameters — no cache lookup needed.
---When visibilityOnly is true, skips all positioning (ClearAllPoints, SetPoint,
---SetSize, GetComponentSize, backgrounds) and only updates visibility/alpha/fade.
---Used by RefreshVisibilityOnly for fast-path updates (e.g. target gained/lost).
---@param name string  component name
---@param parentFrame Frame?  resolved parent frame (nil for free-moving roots)
---@param parentAlpha number  inherited multiplicative alpha from parent chain
---@param parentFade number  inherited fade value from parent chain (math.min)
---@param rootVisible boolean  whether the root ancestor frame is visible
---@param visibilityOnly boolean?  skip positioning, only update visibility/alpha
-- Forward-declared: layoutRecursive (below) writes this on the visibilityOnly
-- Show/Hide path, but the flag's local otherwise lived below the function, so
-- those writes hit a stray global and RefreshVisibilityOnly never escalated.
-- Initialized at its use site (~L1667).
local needsStateChange
-- True only while RelayoutSubtree walks a resized component's dependents: those
-- passes exist to re-derive sizes and re-flow icons against the new parent
-- geometry, never to restyle, so ContentLayout is invoked with skinDirty=false
-- (the icon trackers' reposition-only fast path; components whose ContentLayout
-- takes no parameters ignore it).  Full passes (anchor.Refresh) keep skinDirty
-- true.  Without this, every in-combat content-size change (hide-when-ready
-- membership churn) ran a FULL skin pass on every anchored dependent — the
-- dominant cost of the ~5ms combat frames (UtilitiesTracker.ContentLayout at
-- 1.8ms avg inside each RelayoutSubtree).
local subtreeRepositionOnly = false
local layoutRecursive
layoutRecursive = function(name, parentFrame, parentAlpha, parentFade, rootVisible, visibilityOnly)
    if layoutVisited[name] then return end
    layoutVisited[name] = true

    local component = private.ComponentManager.GetComponent(name)
    if not component then return end

    local componentFrame = component.GetFrame()
    if not componentFrame then
        -- Component has no frame this session (e.g. CooldownTracker when CDM
        -- is off — its container needs the Blizzard viewer to be created).
        -- Don't drop the subtree on the floor: recurse into children so they
        -- can apply their absent-parent fallback (parentIsAbsent → inherit
        -- parent's anchor_profile).
        local children = anchorChildren[name]
        if children then
            for _, childName in ipairs(children) do
                layoutRecursive(childName, nil, parentAlpha, parentFade, rootVisible, visibilityOnly)
            end
        end
        return
    end

    local settings = component.GetSettings()
    if not settings then return end
    local anchorProfile = settings.anchor_profile
    local editHidden = private.editModeHidden and private.editModeHidden[name]
    local isActive = component.GetEnabled() or (private.isEditMode and not editHidden)
    local isNonAnchorable = nonAnchorableComponents[name]
    -- skipPositioning: don't position this component (disabled only). Collapsed-but-active
    -- components still get positioned so their frame has valid anchor points — children
    -- anchor to them normally and the component's own GetComponentSize / ContentLayout
    -- handles the zero-content sizing (e.g. BuffTrackerBars reports height=0 when empty).
    -- skipAsAnchorTarget: children skip past this component in the anchor chain only
    -- when it's fully disabled or non-anchorable. Collapsed components remain in the
    -- chain so children stay anchored to their stable position instead of jumping to
    -- the grandparent with their own anchor_side.
    local skipPositioning = not isActive
    local skipAsAnchorTarget = skipPositioning or isNonAnchorable

    -- Compute effective alpha/fade for this component
    local ownAlpha = skipPositioning and 1 or (settings.alpha or 1)
    local effectiveAlpha = skipPositioning and parentAlpha or ownAlpha

    local ownFade = 1
    if not skipPositioning then
        local _, fade = evaluateVisibilityRules(settings)
        ownFade = fade
    end
    local effectiveFade = math.min(ownFade, parentFade)

    -- Values children will inherit (non-anchorable: children see grandparent frame)
    local childFrame = skipAsAnchorTarget and parentFrame or componentFrame
    local childRootVisible = rootVisible

    -- Store results for external queries (GetEffectiveAlpha, IsAnchorChainVisible)
    local r = lastResult[name]
    local effectiveStrata = resolveEffectiveStrata(settings, anchorProfile)
    if r then
        r.alpha = effectiveAlpha
        r.fade = effectiveFade
        r.rootVisible = rootVisible
        r.anchorFrame = childFrame
        r.effectiveStrata = effectiveStrata
    end
    -- Skip positioning for disabled/collapsed components
    if skipPositioning then
        if not visibilityOnly then
            -- In Edit Mode, force-show disabled components for repositioning
            if private.isEditMode and isActive then
                componentFrame:Show()
            elseif editHidden then
                componentFrame:Hide()
            else
                private.Util.HideComponentBackground(componentFrame)
            end
        end
        -- Recurse to children with parent's frame (skip this component in chain)
        local children = anchorChildren[name]
        if children then
            for _, childName in ipairs(children) do
                layoutRecursive(childName, childFrame, effectiveAlpha, effectiveFade, childRootVisible, visibilityOnly)
            end
        end
        return
    end

    -- Secure frames (SecureActionButton children) and implicitly-protected
    -- frames (CDM containers — protected viewer icons are SetPoint'd to
    -- them, which propagates protection back to the container per
    -- Region:IsProtected): all positioning/sizing APIs are blocked during
    -- combat. Freeze in last known state; OnLeaveCombat refresh catches up.
    -- IsProtected is a cheap query and the check is gated by cachedInCombat
    -- so it's a no-op outside combat.
    if cachedInCombat and (secureComponents[name] or componentFrame:IsProtected()) then
        local children = anchorChildren[name]
        if children then
            for _, childName in ipairs(children) do
                layoutRecursive(childName, componentFrame, effectiveAlpha, effectiveFade, childRootVisible, visibilityOnly)
            end
        end
        return
    end

    -- === Position this component ===

    if not visibilityOnly and not InCombatLockdown() then
        componentFrame:SetFrameStrata(effectiveStrata)
        componentFrame:SetFrameLevel(100)
    end

    if private.isEditMode and not editHidden then
        if not visibilityOnly then componentFrame:Show() end
    elseif editHidden then
        if not visibilityOnly then componentFrame:Hide() end
        local children = anchorChildren[name]
        if children then
            for _, childName in ipairs(children) do
                layoutRecursive(childName, childFrame, effectiveAlpha, effectiveFade, childRootVisible, visibilityOnly)
            end
        end
        return
    end

    if not anchorProfile then
        local children = anchorChildren[name]
        if children then
            for _, childName in ipairs(children) do
                layoutRecursive(childName, childFrame, effectiveAlpha, effectiveFade, childRootVisible, visibilityOnly)
            end
        end
        return
    end

    -- Evaluate visibility mode override
    -- Position free-moving roots before visibility checks so hidden roots
    -- still have valid coordinates for children (e.g. reload while mounted).
    local apParentName = anchorProfile.anchor_parent
    -- Stopgap: when the profile points at an absent parent (CDM-gated or
    -- user-disabled, no frame to anchor to), treat the child as free-moving
    -- for this pass. Do NOT mutate anchor_profile — the original
    -- anchor_parent/anchor_width_pct settings survive so the child
    -- re-attaches correctly once the parent returns. See parentIsAbsent.
    --
    -- ALSO promote rootVisible/childRootVisible to true: a frame-less
    -- ancestor higher in the tree may have been called via the skipPositioning
    -- branch (UtilitiesTracker disabled by CDM gate) which passes its own
    -- false rootVisible down. Once we've decided to treat THIS component as
    -- its own free-moving root, the false signal from above is no longer
    -- meaningful and would only cascade-hide our own subtree. Same write to
    -- lastResult so IsAnchorChainVisible queries see the corrected value.
    -- Absence covers two cases, both routed through the same inheritance
    -- path for positioning: truly-absent (disabled/missing/frameless) and
    -- collapsed (enabled + framed but empty content). The two are kept
    -- distinct by parentIsAbsent vs parentIsCollapsed so width/visibility
    -- paths elsewhere can treat collapsed parents differently.
    --
    -- Content-bearing components that have their own bars/icons can opt
    -- out of the collapsed-parent walk-past via
    -- `comp.StaysAnchoredWhenParentCollapsed = true`. Without opt-out,
    -- OBT and similar trackers teleport to the grandparent's slot when
    -- their anchor_parent (e.g. BuffTrackerBars) temporarily empties.
    --
    -- Escape hatch: if parent's screen position is unresolved (GetLeft
    -- returns nil — happens when parent's SetHeight(0) hasn't re-resolved
    -- or when routed-away content zeroed height without flipping IsCollapsed),
    -- force the fallback regardless of opt-in or collapsed state. Staying
    -- anchored to a positionless parent makes the child positionless too
    -- and WoW won't render it at all — the fallback reroutes the child
    -- through the parent's own anchor (usually UIParent) which stays resolved.
    local staysAnchoredOnCollapse = component.StaysAnchoredWhenParentCollapsed
    local parentCollapsed = parentIsCollapsed(name)
    local parentPositionless = parentFrame and parentFrame.GetLeft
        and parentFrame:GetLeft() == nil or false
    local absentParentFallback = parentIsAbsent(name)
        or (parentCollapsed and not staysAnchoredOnCollapse)
        or parentPositionless
    if absentParentFallback then
        -- Parent is absent (no frame / disabled) or collapsed (no content
        -- this pass). Inherit the parent's position fields so the child
        -- lands at the parent's would-be slot.
        -- Start from a shallow copy of the child's own anchor_profile so any
        -- fields not in the inherit list (e.g. width_pct/width_mode, future
        -- additions) are preserved from the child's config. Walks up through
        -- further-absent ancestors until we reach a present parent or a
        -- free-move root.
        local inheritedProfile = {}
        for k, v in pairs(anchorProfile) do inheritedProfile[k] = v end
        anchorProfile = inheritedProfile

        local walkName = apParentName
        local walkVisited = {}
        while walkName and walkName ~= "none" and walkName ~= "cursor" do
            if walkVisited[walkName] then break end
            walkVisited[walkName] = true
            local walkComp = private.ComponentManager.GetComponent(walkName)
            if not walkComp then break end
            local walkSettings = walkComp.GetSettings()
            local walkAP = walkSettings and walkSettings.anchor_profile
            if not walkAP then break end
            -- Overwrite only the position fields; width/layout fields and any
            -- other child-owned settings already in `anchorProfile` are kept.
            for _, field in ipairs(inheritedPositionFields) do
                anchorProfile[field] = walkAP[field]
            end
            apParentName = anchorProfile.anchor_parent
            -- Stop inheriting once we reach a parent that is present (neither
            -- absent nor collapsed) or is itself a free-move root / external
            -- anchor.
            if not (parentIsAbsent(walkName) or parentIsCollapsed(walkName)) then break end
            walkName = apParentName
        end
        -- Re-resolve parentFrame against the inherited anchor_parent so the
        -- rest of layoutRecursive positions us relative to the correct frame.
        if apParentName and apParentName ~= "none" and apParentName ~= "cursor" then
            if private.externalAnchors and private.externalAnchors[apParentName] then
                parentFrame = _G[apParentName]
            else
                local p = private.ComponentManager.GetComponent(apParentName)
                parentFrame = p and (p.GetEnabled() or private.isEditMode) and p.GetFrame() or nil
            end
        else
            parentFrame = nil
        end
        -- Inherit rootVisible from the effective parent the walk landed on.
        -- When the walk ends at a real present component, its computed
        -- rootVisible is the authoritative signal — propagating its hidden
        -- state through disabled-but-chained intermediates matches the
        -- user's "inherit" intent (if the skipped parent were enabled it
        -- would inherit from its own parent; children should see the same
        -- effective root). Free-move / cursor / external-anchor endings
        -- and unresolved component lookups fall back to true so we don't
        -- cascade-hide on a bootstrap/stale-cache edge.
        local inheritedRootVisible = true
        if apParentName and apParentName ~= "none" and apParentName ~= "cursor"
                and not (private.externalAnchors and private.externalAnchors[apParentName]) then
            local landingParent = private.ComponentManager.GetComponent(apParentName)
            if landingParent then
                local lr = lastResult[apParentName]
                if lr then inheritedRootVisible = lr.rootVisible end
            end
        end
        rootVisible = inheritedRootVisible
        childRootVisible = inheritedRootVisible
        if r then r.rootVisible = inheritedRootVisible end
    end
    if not visibilityOnly and not parentFrame and (not apParentName or apParentName == "none" or apParentName == "cursor") then
        -- Screen-position-based following: compute position from a reference
        -- component's screen coords instead of using a direct anchor chain.
        -- Used by components with SecureActionButton children whose anchor
        -- chain would cascade protection to connected containers.
        -- Only repositioned out of combat (secure frames block SetPoint).
        local posRef = anchorProfile.position_reference
        if posRef and posRef ~= "none" and not cachedInCombat then
            local refComp = private.ComponentManager.GetComponent(posRef)
            local refFrame = refComp and refComp.GetFrame()
            if refFrame then
                local refLeft, refRight, refTop, refBottom
                local placed = placedThisPass[posRef] and lastResult[posRef]
                if placed then
                    -- The size reads back stale too (live report: GetSize put
                    -- RaidBuffTracker on the reference's top edge), so it comes from
                    -- the size its own layout set, taken now so a resize by its
                    -- ContentLayout counts.
                    local w, h = refComp.GetComponentSize()
                    local c = POINT_TO_CENTER[placed.placedPoint]
                    local cx, cy = placed.placedX + c[1] * w, placed.placedY + c[2] * h
                    refLeft, refRight, refTop, refBottom = cx - w / 2, cx + w / 2, cy + h / 2, cy - h / 2
                else
                    refLeft, refRight = refFrame:GetLeft(), refFrame:GetRight()
                    refTop, refBottom = refFrame:GetTop(), refFrame:GetBottom()
                end
                if refLeft and refBottom and refTop and refRight then
                    local posOffset = anchorProfile.position_offset or 0
                    local posSide = anchorProfile.position_side or "bottom"
                    local refCenterX = (refLeft + refRight) / 2
                    local refCenterY = (refTop + refBottom) / 2
                    local point, x, y
                    if posSide == "bottom" then
                        point, x, y = "TOP", refCenterX, refBottom - posOffset
                    elseif posSide == "top" then
                        point, x, y = "BOTTOM", refCenterX, refTop + posOffset
                    elseif posSide == "left" then
                        point, x, y = "RIGHT", refLeft - posOffset, refCenterY
                    elseif posSide == "right" then
                        point, x, y = "LEFT", refRight + posOffset, refCenterY
                    end
                    safeClearAllPoints(componentFrame)
                    if point then
                        safeSetPoint(componentFrame, point, UIParent, "BOTTOMLEFT", x, y)
                        local r = lastResult[name]
                        if r then
                            r.placedPoint, r.placedX, r.placedY = point, x, y
                            placedThisPass[name] = true
                        end
                    end
                    local cw, ch = component.GetComponentSize()
                    local fw = componentFrame:GetWidth()
                    componentFrame:SetSize(fw > 0 and fw or cw, ch)
                    componentFrame.cueAnchorOwnsWidth = false
                end
            end
        elseif not posRef or posRef == "none" then
            -- Cursor-anchored frames are positioned by OnUpdate; skip SetPoint
            -- but still apply size so layout works correctly.
            if apParentName == "cursor" then
                local cw, ch = component.GetComponentSize()
                local fw = componentFrame:GetWidth()
                componentFrame:SetSize(fw > 0 and fw or cw, ch)
                componentFrame.cueAnchorOwnsWidth = false
            elseif anchor.draggingFrame ~= componentFrame then
                safeClearAllPoints(componentFrame)
                local fp, af, rp, xo, yo = getAnchorPoint(anchorProfile)
                safeSetPoint(componentFrame, fp, af, rp, xo, yo)
                local cw, ch = component.GetComponentSize()
                -- Preserve existing content-based width (set by LayoutViewerIcons) to
                -- avoid inflating the container back to GetComponentSize() = settings.width.
                -- Only use GetComponentSize width on first initialization (fw <= 0).
                local fw = componentFrame:GetWidth()
                componentFrame:SetSize(fw > 0 and fw or cw, ch)
                componentFrame.cueAnchorOwnsWidth = false
            end
        end
        -- posRef + cachedInCombat: skip repositioning, keep last known position.
    end

    local hasOverride = component.GetVisibilityOverride and component.GetVisibilityOverride()
    local forceVisible = component.GetForceVisible and component.GetForceVisible()
    -- Override only engages when the user chose "inherit". Explicit visibility
    -- modes (hidden / always / only_in_combat / etc.) represent direct user
    -- intent and must win over any programmatic override.
    local settingsVis = settings.visibility or "inherit"
    local effectiveOverride = settingsVis == "inherit" and hasOverride or nil
    local visMode = effectiveOverride or settingsVis

    -- Alpha/fade inheritance override based on visibility mode
    local isSettingsAlways = visMode == "always" and not effectiveOverride
    local isRoot = not apParentName or apParentName == "none" or apParentName == "cursor"
    if not private.isEditMode and isSettingsAlways then
        -- "always" from settings breaks the entire visibility inheritance chain.
        -- Component uses own alpha (default from above), own fade, fresh rootVisible.
        effectiveFade = ownFade
        childRootVisible = true
        if r then
            r.fade = effectiveFade
            r.rootVisible = true
        end
    elseif effectiveOverride or (visMode == "inherit" and not isRoot) then
        -- Programmatic override (e.g. Vigor): displays at own alpha/fade,
        -- but children see the parent chain (transparent to children).
        -- "inherit" non-root: children see parent's alpha.
        effectiveAlpha = parentAlpha
        if r then r.alpha = effectiveAlpha end
    end

    if not private.isEditMode and visMode ~= "inherit" then
        local modeVisible
        -- IsCooldownViewerAvailable() reports false whenever the CDM CVar is
        -- off, which is NOT a reason to hide a cast bar or a resource bar: this
        -- gate is about the CDM *system* being present, not about our own CVar
        -- momentarily being off (ensureEnabled cannot write it in combat, so a
        -- mid-pull external flip leaves it off until OnLeaveCombat). Treat the
        -- system as available whenever the only thing missing is our own CVar.
        local cdmAvailable = (C_CooldownViewer and C_CooldownViewer.IsCooldownViewerAvailable()) or false
        if not cdmAvailable and not private.CDMDataSource.IsDataAvailable() then
            cdmAvailable = true
        end
        if visMode == "always" then
            modeVisible = true
        elseif visMode == "auto" then
            -- "auto" mirrors the CDM: hidden while mounted, so it tracks a CDM
            -- tracker's mounted-hide uniformly (primaries and AFs alike). The
            -- forceVisible gate below still wins, so a skyriding ability bar
            -- (CooldownTracker overrideMode) keeps showing while its normal
            -- content — and any auto AF sourcing it — hides.
            local mounted = passIsMounted()
            modeVisible = cdmAvailable and not mounted
        elseif visMode == "hide_when_mounted" then
            local mounted = passIsMounted()
            modeVisible = cdmAvailable and not mounted
        elseif visMode == "only_in_combat" then
            local inCombat = passInCombat()
            modeVisible = inCombat
        elseif visMode == "hidden" then
            modeVisible = false
        else
            modeVisible = true
        end
        if not modeVisible and not forceVisible then
                componentFrame:Hide()
            -- Anchoring is not parenting: hiding this frame hides nothing that
            -- is merely anchored to it, so the chain is broken by hand.  It is
            -- broken for EVERY hidden component, root or not -- a non-root that
            -- hides on its own mode still has to take its subtree with it.
            childRootVisible = false
            if r then r.rootVisible = childRootVisible end
            local children = anchorChildren[name]
            if children then
                for _, childName in ipairs(children) do
                    layoutRecursive(childName, childFrame, effectiveAlpha, effectiveFade, childRootVisible, visibilityOnly)
                end
            end
            return
        end
        -- Component is independently visible — break the rootVisible chain
        -- so children anchored to this component inherit "visible", not the
        -- hidden state of a root ancestor (e.g. viewer hidden by InCombat).
        -- Programmatic overrides (Vigor) are transparent: they display at own
        -- alpha/fade but children inherit the parent chain unchanged.
        if not modeVisible then
            -- Shown ONLY because forceVisible saved it from the gate above. The
            -- frame draws its override content (CooldownTracker's skyriding /
            -- vehicle bar), but that override is about THIS component, not its
            -- subtree: forceVisible's contract is that it can only PREVENT a
            -- hide, never GRANT visibility. Inheriting children therefore see
            -- the mode's verdict rather than the rescue -- the same false the
            -- hide branch above writes.
            -- Without this an "inherit" AF anchored to a CooldownTracker in
            -- overrideMode keeps drawing its normal spells beside the skyriding
            -- bar, while an "auto" AF correctly hides.
            childRootVisible = false
            if r then r.rootVisible = childRootVisible end
        elseif not effectiveOverride then
            childRootVisible = true
            -- Sync lastResult with what children inherit. This path breaks the
            -- rootVisible chain (component mode-visible under a hidden root), so
            -- external readers (RelayoutSubtree, IsAnchorChainVisible) must see the
            -- promoted value, not the stale incoming rootVisible written at entry.
            if r then r.rootVisible = true end
        end
    end

    -- Additive visibility rules apply under explicit visibility modes, when the
    -- component has no inheritance source (free-move without position_reference),
    -- OR when the user has configured any "hide" rule. A hide dropdown is an
    -- explicit additive intent that must OR with the parent chain — suppressing
    -- it under "inherit" silently discards a user-visible setting. Fade rules
    -- remain gated on the first two conditions (they only make sense alongside
    -- own alpha, not as additive overrides to an inherited chain).
    local wasRulesHidden = componentFrame.cueRulesHidden
    local posRefName = anchorProfile and anchorProfile.position_reference
    local hasInheritSource =
        (apParentName and apParentName ~= "none" and apParentName ~= "cursor")
        or (posRefName and posRefName ~= "none")
    if settingsVis ~= "inherit" or not hasInheritSource or hasAnyHideRule(settings) then
        local rulesVisible = evaluateVisibilityRules(settings, private.isEditMode)
        if not rulesVisible and not forceVisible then
            componentFrame.cueRulesHidden = true
            if visibilityOnly then
                if not wasRulesHidden then
                    componentFrame:Hide()
                    needsStateChange = true
                end
            else
                componentFrame:Hide()
            end
            childRootVisible = false
            if r then r.rootVisible = childRootVisible end
            local children = anchorChildren[name]
            if children then
                for _, childName in ipairs(children) do
                    layoutRecursive(childName, childFrame, effectiveAlpha, effectiveFade, childRootVisible, visibilityOnly)
                end
            end
            return
        elseif not rulesVisible then
            -- Rule-hidden, but forceVisible saved the frame.  Same contract as
            -- the mode gate above: the rescue is about THIS component, so
            -- inheriting children resolve as if the rule had hidden it.  This
            -- is also what downgrades the mode block's promotion, which runs
            -- before this gate and cannot know a rule will fire.
            childRootVisible = false
            if r then r.rootVisible = false end
        end
    end
    if visibilityOnly and wasRulesHidden then
        componentFrame:Show()
        needsStateChange = true
    end
    componentFrame.cueRulesHidden = nil

    -- Programmatic visibility overrides use their own fade/alpha for display,
    -- but do not break the inheritance chain for children.
    local displayFade = (effectiveOverride and ownFade) or effectiveFade
    local displayAlphaBase = (effectiveOverride and ownAlpha) or effectiveAlpha

    -- Auto-migrate non-anchorable parent references (positioning only)
    if not visibilityOnly and apParentName and nonAnchorableComponents[apParentName] then
        local target = apParentName
        local seen = {}
        while target and nonAnchorableComponents[target] do
            if seen[target] then target = "none"; break end
            seen[target] = true
            local parentComp = private.ComponentManager.GetComponent(target)
            if not parentComp then target = "none"; break end
            local pap = parentComp.GetSettings().anchor_profile
            if not pap or not pap.anchor_parent then target = "none"; break end
            target = pap.anchor_parent
        end
        if target == name then target = "none" end
        anchorProfile.anchor_parent = target
        apParentName = target
    end

    -- Compute display alpha
    local displayAlpha = private.isEditMode and 1
        or (displayFade < 1 and displayFade)
        or displayAlphaBase

    -- Free-moving root: position + visibility
    if not apParentName or apParentName == "none" or apParentName == "cursor" then
        -- A protected container (SecureActionButton children) has
        -- Show/Hide/SetPoint blocked during combat.  Skip entirely;
        -- OnLeaveCombat refresh catches up.  This is the freeze gate, so it
        -- reads secureComponents, not secureClickComponents.
        local isSecureFrame = secureComponents[name]
        local posRef = anchorProfile.position_reference
        -- Inherit visibility/fade from position_reference component.
        -- The reference is in the main anchor chain, already laid out by now.
        if posRef and posRef ~= "none" then
            local refResult = lastResult[posRef]
            if refResult then
                -- Inherit visibility from reference — overrides frame's own
                -- IsShown state (which reflects our previous Show/Hide calls).
                childRootVisible = refResult.rootVisible
                effectiveAlpha = effectiveAlpha * refResult.alpha
                effectiveFade = math.min(effectiveFade, refResult.fade)
                displayAlphaBase = effectiveAlpha
                -- Recompute displayAlpha using the same formula as the main path:
                -- fade overrides alpha when active, otherwise use alpha base.
                displayAlpha = private.isEditMode and 1
                    or (effectiveFade < 1 and effectiveFade)
                    or displayAlphaBase
                -- Update lastResult so downstream position_reference components
                -- (e.g. RaidBuffTracker → ConsumableBuffTracker) see inherited values.
                if r then
                    r.alpha = effectiveAlpha
                    r.fade = effectiveFade
                    r.rootVisible = childRootVisible
                end
            end
        end
        if not visibilityOnly then
            -- Cursor-anchored frames are positioned by OnUpdate; re-anchoring
            -- here would snap them to anchor_profile defaults (CENTER/UIParent)
            -- between ticks, producing a center-of-screen flicker on Refresh.
            if (not posRef or posRef == "none")
                and apParentName ~= "cursor"
                and anchor.draggingFrame ~= componentFrame then
                safeClearAllPoints(componentFrame)
                local fp, af, rp, xo, yo = getAnchorPoint(anchorProfile)
                safeSetPoint(componentFrame, fp, af, rp, xo, yo)
            end
            componentFrame.cueAnchorOwnsWidth = false
            if childRootVisible or forceVisible then
                componentFrame:Show()
            elseif isSecureFrame then
                -- Secure containers are implicitly protected (icon anchors).
                -- Hide() out of combat would leave the frame hidden when
                -- combat starts and the freeze prevents Show().  Keep the
                -- frame shown; alpha=0 (set below) makes it invisible.
                -- SyncAlpha can then restore visibility during combat.
                componentFrame:Show()
            else
                componentFrame:Hide()
            end
        end
        if isSecureFrame and not childRootVisible and not forceVisible then
            -- Secure container kept shown (above) — zero alpha to hide.
            componentFrame:SetAlpha(0)
        else
            componentFrame:SetAlpha(displayAlpha)
        end
        if not visibilityOnly then
            -- Apply per-component background
            if settings.background then
                private.Util.ApplyComponentBackground(componentFrame, settings.background)
            end
        end
        -- Update stored result to reflect actual root visibility so
        -- external queries (IsAnchorChainVisible, IsVisibleForComponent)
        -- return the correct value.
        local r = lastResult[name]
        if r then r.rootVisible = childRootVisible end
        if not visibilityOnly and component.ContentLayout then
            component.ContentLayout(not subtreeRepositionOnly)
        end
        local children = anchorChildren[name]
        if children then
            for _, childName in ipairs(children) do
                layoutRecursive(childName, childFrame, effectiveAlpha, effectiveFade, childRootVisible, visibilityOnly)
            end
        end
        return
    end

    -- Hide if root ancestor frame is hidden (inherit mode only).
    -- Gated on settingsVis so an active override (which promotes visMode to
    -- e.g. "always") still respects the user's intent to inherit.
    if not private.isEditMode and settingsVis == "inherit" and not rootVisible and not forceVisible then
        componentFrame:Hide()
        local children = anchorChildren[name]
        if children then
            for _, childName in ipairs(children) do
                layoutRecursive(childName, childFrame, effectiveAlpha, effectiveFade, childRootVisible, visibilityOnly)
            end
        end
        return
    end

    -- visibilityOnly: skip all parent-frame positioning branches, just update alpha
    if visibilityOnly then
        componentFrame:SetAlpha(displayAlpha)
        local children = anchorChildren[name]
        if children then
            for _, childName in ipairs(children) do
                layoutRecursive(childName, childFrame, effectiveAlpha, effectiveFade, childRootVisible, true)
            end
        end
        return
    end

    -- parentFrame was passed by the recursive caller (already resolved,
    -- skipping disabled/collapsed parents). For external-anchor roots,
    -- parentFrame was set at the applyLayout entry point.
    -- No valid parent: hide or fall back to free-moving
    if not parentFrame then
        if not private.isEditMode
            and settingsVis == "inherit"
            and not nonAnchorableComponents[apParentName]
            and private.ComponentManager.GetComponent(apParentName)
            and not forceVisible
        then
            componentFrame:Hide()
            local children = anchorChildren[name]
            if children then
                for _, childName in ipairs(children) do
                    layoutRecursive(childName, childFrame, effectiveAlpha, effectiveFade, childRootVisible)
                end
            end
            return
        end
        safeClearAllPoints(componentFrame)
        local fp, af, rp, xo, yo = getAnchorPoint(anchorProfile)
        safeSetPoint(componentFrame, fp, af, rp, xo, yo)
        componentFrame:Show()
        componentFrame:SetAlpha(displayAlpha)
        if settings.background then
            private.Util.ApplyComponentBackground(componentFrame, settings.background)
        end
        if component.ContentLayout then
            component.ContentLayout(not subtreeRepositionOnly)
        end
        local children = anchorChildren[name]
        if children then
            for _, childName in ipairs(children) do
                layoutRecursive(childName, childFrame, effectiveAlpha, effectiveFade, childRootVisible)
            end
        end
        return
    end

    -- (Removed: legacy "parentFrame:GetLeft() == nil → free-move fallback".
    -- Reading live frame coords here taints clickable trackers and triggers
    -- false fallbacks for zero-sized parents. The existing parentIsAbsent
    -- check above already routes absent/frameless parents through the
    -- anchor_profile-inheritance path, so we can trust parentFrame here.)

    -- === Normal anchored positioning ===
    local wantsContentWidth, side, widthMode, widthPct, liveWidth =
        classifyAnchorSize(component, settings, anchorProfile)
    local oX = anchorProfile.anchor_offset_x or 0
    local oY = anchorProfile.anchor_offset_y or 0
    local compW, compH = component.GetComponentSize()

    local effectiveWidth
    if wantsContentWidth then
        effectiveWidth = compW
    elseif widthMode == "absolute" then
        effectiveWidth = compW
    else
        local pw = parentFrame:GetWidth()
        effectiveWidth = pw > 0 and (pw * (widthPct / 100.0)) or compW
    end

    local parentWidth = parentFrame:GetWidth()
    local useTwoPoint = liveWidth and parentWidth > 0

    safeClearAllPoints(componentFrame)

    if side == "bottom" then
        componentFrame:SetHeight(compH)
        if useTwoPoint then
            safeSetPoint(componentFrame, "TOPLEFT", parentFrame, "BOTTOMLEFT", oX, oY)
            safeSetPoint(componentFrame, "TOPRIGHT", parentFrame, "BOTTOMRIGHT", oX, oY)
            componentFrame:SetWidth(parentFrame:GetWidth())
        else
            componentFrame:SetWidth(effectiveWidth)
            safeSetPoint(componentFrame, "TOP", parentFrame, "BOTTOM", oX, oY)
        end
    elseif side == "top" then
        componentFrame:SetHeight(compH)
        if useTwoPoint then
            safeSetPoint(componentFrame, "BOTTOMLEFT", parentFrame, "TOPLEFT", oX, oY)
            safeSetPoint(componentFrame, "BOTTOMRIGHT", parentFrame, "TOPRIGHT", oX, oY)
            componentFrame:SetWidth(parentFrame:GetWidth())
        else
            componentFrame:SetWidth(effectiveWidth)
            safeSetPoint(componentFrame, "BOTTOM", parentFrame, "TOP", oX, oY)
        end
    elseif side == "left" then
        componentFrame:SetWidth(compW)
        local parentHeight = parentFrame:GetHeight()
        if widthMode == "percent" and parentHeight > 0 then
            componentFrame:SetHeight(parentHeight * (widthPct / 100.0))
        else
            componentFrame:SetHeight(compH)
        end
        local vAlign = settings.layout_direction == "vertical"
            and (settings.layout_alignment or "center") or "center"
        if vAlign == "top" then
            safeSetPoint(componentFrame, "TOPRIGHT", parentFrame, "TOPLEFT", oX, oY)
        elseif vAlign == "bottom" then
            safeSetPoint(componentFrame, "BOTTOMRIGHT", parentFrame, "BOTTOMLEFT", oX, oY)
        else
            safeSetPoint(componentFrame, "RIGHT", parentFrame, "LEFT", oX, oY)
        end
    elseif side == "right" then
        componentFrame:SetWidth(compW)
        local parentHeight = parentFrame:GetHeight()
        if widthMode == "percent" and parentHeight > 0 then
            componentFrame:SetHeight(parentHeight * (widthPct / 100.0))
        else
            componentFrame:SetHeight(compH)
        end
        local vAlign = settings.layout_direction == "vertical"
            and (settings.layout_alignment or "center") or "center"
        if vAlign == "top" then
            safeSetPoint(componentFrame, "TOPLEFT", parentFrame, "TOPRIGHT", oX, oY)
        elseif vAlign == "bottom" then
            safeSetPoint(componentFrame, "BOTTOMLEFT", parentFrame, "BOTTOMRIGHT", oX, oY)
        else
            safeSetPoint(componentFrame, "LEFT", parentFrame, "RIGHT", oX, oY)
        end
    elseif side == "topleft" or side == "topright" or side == "bottomleft" or side == "bottomright" then
        componentFrame:SetWidth(compW)
        componentFrame:SetHeight(compH)
        local isVertical = settings.layout_direction == "vertical"
            or (settings.layout == "block" and settings.block_direction == "vertical")
            or settings.layout == "vertical"
        local childPoint, parentPoint
        if isVertical then
            if side == "topleft" then
                childPoint, parentPoint = "TOPRIGHT", "TOPLEFT"
            elseif side == "topright" then
                childPoint, parentPoint = "TOPLEFT", "TOPRIGHT"
            elseif side == "bottomleft" then
                childPoint, parentPoint = "BOTTOMRIGHT", "BOTTOMLEFT"
            else
                childPoint, parentPoint = "BOTTOMLEFT", "BOTTOMRIGHT"
            end
        else
            if side == "topleft" then
                childPoint, parentPoint = "BOTTOMLEFT", "TOPLEFT"
            elseif side == "topright" then
                childPoint, parentPoint = "BOTTOMRIGHT", "TOPRIGHT"
            elseif side == "bottomleft" then
                childPoint, parentPoint = "TOPLEFT", "BOTTOMLEFT"
            else
                childPoint, parentPoint = "TOPRIGHT", "BOTTOMRIGHT"
            end
        end
        safeSetPoint(componentFrame, childPoint, parentFrame, parentPoint, oX, oY)
    end

    componentFrame.cueAnchorOwnsWidth = true
    componentFrame:Show()
    componentFrame:SetAlpha(displayAlpha)

    -- Apply per-component background
    if settings.background then
        private.Util.ApplyComponentBackground(componentFrame, settings.background)
    end

    -- Content layout: position icons/bars within the container so the frame
    -- has its final content-based dimensions before children inherit from it.
    if component.ContentLayout then
        component.ContentLayout(not subtreeRepositionOnly)
    end

    -- Recurse to children
    local children = anchorChildren[name]
    if children then
        for _, childName in ipairs(children) do
            layoutRecursive(childName, childFrame, effectiveAlpha, effectiveFade, childRootVisible)
        end
    end
end

---Install visibility hooks on an external anchor frame so that show/hide changes
---trigger a layout refresh, the same way root component frames are watched.
---@param frame frame
local installExternalAnchorHooks = function(frame)
    if rootVisibilityWatched[frame] then return end
    rootVisibilityWatched[frame] = true

    local lastVisible = frame:IsShown() and frame:GetAlpha() > 0

    local function checkVisibilityChange(self)
        local visible = self:IsShown() and self:GetAlpha() > 0
        if visible ~= lastVisible then
            lastVisible = visible
            anchor.OnComponentStateChange()
        end
    end

    if frame.UpdateShownState then
        hooksecurefunc(frame, "UpdateShownState", function(self)
            checkVisibilityChange(self)
        end)
    end

    hooksecurefunc(frame, "SetAlpha", function(self)
        checkVisibilityChange(self)
    end)

    frame:HookScript("OnHide", function(self)
        checkVisibilityChange(self)
    end)
    frame:HookScript("OnShow", function(self)
        checkVisibilityChange(self)
    end)
end

-- Pending external frame watcher ------------------------------------------
-- When an external anchor's _G[name] doesn't exist yet, we track it here.
-- Uses ADDON_LOADED during load, then falls back to OnUpdate polling for
-- frames created after all addons have loaded (e.g. lazy frame creation
-- during PLAYER_ENTERING_WORLD or later).

local pendingWatcherFrame = CreateFrame("Frame")
local pendingWatcherActive = false

---Check all pending external frame names against _G. Install hooks and
---trigger re-layout for any that have appeared. Disable watcher when empty.
---@return boolean anyResolved
local checkPendingExternalFrames = function()
    local anyResolved = false
    for frameName in pairs(pendingExternalFrames) do
        local frame = _G[frameName]
        if frame and type(frame) == "table" and type(frame.IsShown) == "function" then
            pendingExternalFrames[frameName] = nil
            installExternalAnchorHooks(frame)
            anyResolved = true
        end
    end
    if anyResolved and isReady then
        anchor.OnComponentStateChange()
    end
    if not next(pendingExternalFrames) then
        pendingWatcherActive = false
        pendingWatcherFrame:UnregisterEvent("ADDON_LOADED")
        pendingWatcherFrame:SetScript("OnUpdate", nil)
    end
    return anyResolved
end

---Activate the watcher (ADDON_LOADED + OnUpdate polling).
local activatePendingWatcher = function()
    if pendingWatcherActive then return end
    pendingWatcherActive = true
    pendingWatcherFrame:RegisterEvent("ADDON_LOADED")
    -- Throttled OnUpdate: check once per second to catch late frame creation.
    local elapsed = 0
    pendingWatcherFrame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        checkPendingExternalFrames()
    end)
end

---Add a frame name to the pending set and start watching.
---@param frameName string
local addPendingExternalFrame = function(frameName)
    pendingExternalFrames[frameName] = true
    activatePendingWatcher()
end

pendingWatcherFrame:SetScript("OnEvent", function()
    checkPendingExternalFrames()
end)

---Expose for Public.lua so AddAnchors can track missing frames immediately.
---@param frameName string
anchor.TrackPendingExternalFrame = function(frameName)
    addPendingExternalFrame(frameName)
end

---Scan all components for external anchor parents and ensure visibility hooks
---are installed on any external frames that are in use. Tracks missing frames
---in the pending set for deferred resolution.
local ensureExternalAnchorHooks = function()
    checkPendingExternalFrames()
    for _, component in ipairs(private.ComponentManager.GetAllComponents()) do
        local s = component.GetSettings()
        local ap = s and s.anchor_profile
        if ap and ap.anchor_parent and private.externalAnchors[ap.anchor_parent] then
            local frame = _G[ap.anchor_parent]
            if frame then
                installExternalAnchorHooks(frame)
            else
                addPendingExternalFrame(ap.anchor_parent)
            end
        end
    end
end

---Layout all components via recursive top-down traversal. Parent values
---(alpha, fade, rootVisible, anchorFrame) flow as parameters — no cache
---rebuild or table allocation per pass.
---Dirty-loop re-entrancy: layoutRecursive calls Show()/Hide() on component
---frames, which fires OnShow/OnHide visibility hooks → OnComponentStateChange,
---which sets needsStateChange=true while a pass is in progress.  The outer
---repeat..until loop re-runs the pass in the same frame/call stack until the
---dirty flag is clear or the pass cap is reached.  Same-frame synchronous —
---no timer defer, no stutter.
local isRefreshing = false
needsStateChange = false -- forward-declared above layoutRecursive
local MAX_APPLY_PASSES = 3

---Components whose icons ignore container alpha (SetIgnoreParentAlpha), or
---whose frame the combat freeze in layoutRecursive skipped, never fade through
---a visibility-only walk or through a full pass in combat: the freeze returns
---before ContentLayout, which is where the full pass re-alphas them.  The icon
---and aura trackers, OutboundBuffTracker and every Additional Frame.  Re-sync
---each enabled one directly (SetAlpha is combat-safe).
local function syncAllComponentAlpha()
    for _, comp in ipairs(private.ComponentManager.GetAllComponents()) do
        if comp.SyncAlpha and comp.GetEnabled() then
            comp.SyncAlpha()
        end
    end
end

local applyLayout = function()
    if isRefreshing then
        needsStateChange = true
        return
    end
    isRefreshing = true
    local passes = 0
    repeat
        needsStateChange = false
        passes = passes + 1
        wipe(layoutVisited)
        wipe(placedThisPass)
        wipe(inheritedWidthCache)
        wipe(inheritedHeightCache)
        wipe(visibilityCache)
        wipe(componentSizeCache)
        cachedIsMounted = isMountedConditionActive()
        cachedInCombat = InCombatLockdown()
        cachedHasTarget = UnitExists("target")
        appliedHasTarget = cachedHasTarget
        if #anchorRoots == 0 then rebuildAnchorTree() end
        -- Two-pass layout: process normal roots first so that lastResult is
        -- populated for all components before position_reference roots read it
        -- for visibility/alpha inheritance.
        wipe(deferredRoots)
        for _, rootName in ipairs(anchorRoots) do
            local comp = private.ComponentManager.GetComponent(rootName)
            if comp then
                local ap = comp.GetSettings().anchor_profile
                if ap and ap.position_reference and ap.position_reference ~= "none" then
                    deferredRoots[#deferredRoots + 1] = rootName
                else
                    local apParent = ap and ap.anchor_parent
                    local pFrame, rv
                    if apParent and apParent ~= "none" and private.externalAnchors[apParent] then
                        pFrame = _G[apParent]
                        rv = true
                    elseif not apParent or apParent == "none" or apParent == "cursor" then
                        -- Free-moving root: no parent chain to inherit from.
                        -- rootVisible must be true so "inherit" visibility mode
                        -- doesn't create a circular dependency (frame hidden →
                        -- rootVisible false → stays hidden forever).
                        rv = true
                        pFrame = nil
                    else
                        -- Component is in anchorRoots only because rebuildAnchorTree
                        -- promoted it (configured parent isn't a registered
                        -- component — unknown external/AF anchor). Treat as
                        -- free-moving root regardless of own frame state. Reading
                        -- frame:IsShown() here would cascade-hide all children
                        -- whenever the promoted root's container happens to be
                        -- hidden.
                        rv = true
                        pFrame = nil
                    end
                    layoutRecursive(rootName, pFrame, 1, 1, rv)
                end
            end
        end
        -- Second pass: position_reference roots (secure components).
        -- rootVisible is derived from the reference component's result, not from
        -- the frame's own IsShown (which reflects our previous Hide call).
        local deferredCount = #deferredRoots
        if deferredCount > 0 then
            for i = 1, deferredCount do
                local rootName = deferredRoots[i]
                local comp = private.ComponentManager.GetComponent(rootName)
                if comp then
                    local ap = comp.GetSettings().anchor_profile
                    local pr = ap and ap.position_reference
                    local refResult = pr and pr ~= "none" and lastResult[pr]
                    -- Explicit nil-check: "refResult and refResult.rootVisible or true"
                    -- fails when rootVisible is false (false or true → true).
                    local rv = refResult == nil or refResult.rootVisible
                    layoutRecursive(rootName, nil, 1, 1, rv)
                end
            end
            -- Re-sync secure components: their Refresh/SyncAlpha reads
            -- GetEffectiveAlpha from lastResult, which was just updated with
            -- inherited values. SyncAlpha is combat-safe (SetAlpha is not protected).
            for i = 1, deferredCount do
                local rootName = deferredRoots[i]
                local comp = private.ComponentManager.GetComponent(rootName)
                if comp then
                    if comp.SyncAlpha then
                        comp.SyncAlpha()
                    elseif comp.Refresh and not InCombatLockdown() then
                        comp.Refresh()
                    end
                end
            end
        end
        -- Fallback pass: forceVisible components unreachable through the tree
        -- (e.g. parent's GetFrame() returns nil when CDM is hidden from login).
        -- Position at their saved EditMode coordinates so they appear on screen.
        for _, comp in ipairs(private.ComponentManager.GetAllComponents()) do
            local name = comp.name
            if name and not layoutVisited[name] and comp.GetForceVisible and comp.GetForceVisible() then
                local frame = comp.GetFrame()
                if frame then
                    local s = comp.GetSettings()
                    local ap = s and s.anchor_profile
                    if ap then
                        safeClearAllPoints(frame)
                        frame:SetSize(comp.GetComponentSize())
                        local fp, af, rp, xo, yo = getAnchorPoint(ap)
                        safeSetPoint(frame, fp, af, rp, xo, yo)
                        frame:Show()
                        frame:SetAlpha(s.alpha or 1)
                        if s.background then
                            private.Util.ApplyComponentBackground(frame, s.background)
                        end
                    end
                end
            end
        end
    until not needsStateChange or passes >= MAX_APPLY_PASSES
    -- The pull with a hide rule runs this pass inside the lockdown.
    if cachedInCombat then
        syncAllComponentAlpha()
    end
    -- Mirror each CDM-backed tracker's rect onto its external anchor proxy
    -- (CUE_<viewerKey>Anchor).  Driven from the pass tail rather than from a
    -- resize chokepoint because the proxy has to track MOVES as well as
    -- resizes, and by here every component is placed.  SyncAnchorProxy
    -- self-skips in combat and whenever the rect did not move.
    for compName in pairs(private.Util.CDM_COMPONENT_VIEWER_KEYS) do
        local comp = private.ComponentManager.GetComponent(compName)
        local frame = comp and comp.GetFrame and comp.GetFrame()
        if frame then
            private.Util.SyncAnchorProxy(frame, compName)
        end
    end
    isRefreshing = false
    cachedIsMounted = nil
    cachedInCombat = nil
    cachedHasTarget = nil
end

---Rebuild the anchor tree and expose it for external callers.
anchor.RebuildAnchorTree = function()
    rebuildAnchorTree()
    ensureExternalAnchorHooks()
end

---Clear WoW-level anchor points on all component frames.
---Called before profile-switch layout passes to break stale anchor
---relationships that would otherwise create circular dependencies
---when the anchor tree has been restructured.
---Secure/protected frames are skipped during combat — ClearAllPoints is
---blocked on them (same gate as layoutRecursive).  Their stale points are
---broken by the deferred FullLayoutRefresh that ProfileManager schedules on
---OnLeaveCombat.
anchor.ClearAllComponentPoints = function()
    local inCombat = InCombatLockdown()
    for _, comp in ipairs(private.ComponentManager.GetAllComponents()) do
        local frame = comp.GetFrame()
        if frame and not (inCombat and (secureComponents[comp.name] or frame:IsProtected())) then
            safeClearAllPoints(frame)
        end
    end
end

-- Guard: defers OnComponentStateChange-triggered refreshes until the end of
-- a bulk operation (e.g. profile apply) so the whole operation produces one
-- final Refresh instead of N.  Mid-operation state changes during an
-- anchor.Refresh pass are handled separately by the dirty loop (see
-- applyLayout and OnComponentStateChange).
local isInBulkRefresh = false
local pendingBulkStateChange = false

anchor.BeginBulkRefresh = function()
    isInBulkRefresh = true
end

anchor.EndBulkRefresh = function()
    isInBulkRefresh = false
    if pendingBulkStateChange then
        pendingBulkStateChange = false
        anchor.Refresh()
    end
end

-- Coalesces deferred bulk-refresh callbacks: only one pending timer per frame.
-- Used by OnComponentStateChange, RefreshVisibilityOnly and the combat and
-- mount callbacks.
local pendingDeferredRefresh = false
-- Whether any caller coalesced into the pending refresh asked for the font pass.
local pendingDeferredFonts = false

---Schedule a single deferred anchor.Refresh for the next frame.
---ContentLayout runs inline during the recursive layout pass, so a
---separate RefreshAllComponents call is no longer needed for sizing.
---Multiple calls within the same frame are coalesced into one refresh.
---
---`withFonts` raises private.fontsDirty around the pass.  Only a component
---state change asks for it: that is where new text appears (SecondaryResources
---rebuilds its rows and styles `valueText` only under the flag).
---
---No pass that merely REVEALS a component asks -- the pull with a hide rule,
---mount/dismount, RefreshVisibilityOnly's escalation.  The flag is global, so
---raising it to reach one hidden component restyled every aura button of every
---tracker: 365 ms per target swap under a no_target hide rule.  Instead each
---component that returns before its font block keeps the edit itself:
---Trinket, Racial, Consumable, every Additional Frame and IconTracker's
---takeover/disabled returns on a fontsOwed latch, the aura trackers on their
---persistent restyle flag, the secure-click trackers on fontsOwed.  Combat exit
---never asked (it restyled every aura button on each combat end).
---OR-ed before the coalescing return, so a caller that asks for fonts after one
---that did not still gets them.
---@param withFonts boolean?
local function scheduleDeferredBulkRefresh(withFonts)
    if withFonts then pendingDeferredFonts = true end
    if pendingDeferredRefresh then return end
    pendingDeferredRefresh = true
    C_Timer.After(0, function()
        pendingDeferredRefresh = false
        local fonts = pendingDeferredFonts
        pendingDeferredFonts = false
        if not isReady then return end
        if fonts then private.fontsDirty = true end
        anchor.Refresh()
        if fonts then private.fontsDirty = false end
    end)
end

---Returns true if any registered component anchors to `name` (via anchor_parent),
---so a size change on `name`'s frame requires re-resolving child positions. Reads
---the static anchor tree -- O(1), no allocation.
anchor.HasAnchoredDependents = function(name)
    local children = anchorChildren[name]
    return children ~= nil and #children > 0
end

---True when `name`'s visibility outcome can actually be changed by its
---GetForceVisible() override.
---
---forceVisible is consulted ONLY at hide gates -- mode (~L1148), rules (~L1190),
---inherit-chain (~L1359), absent-parent (~L1391) -- always in the shape
---`if not <wouldShow> and not forceVisible then Hide()`.  It can therefore only
---ever PREVENT a hide, never cause one.  So when nothing would hide the component,
---flipping forceVisible cannot change the layout outcome at all and the caller
---must not fire a refresh.
---
---Motivating case: PlayerCastBar's `show_when_casting` flips forceVisible on every
---cast start/end.  On a profile where nothing hides the bar (the default shape:
---root + visibility "inherit" + no hide rules) that fired a full-addon
---anchor.Refresh -- measured at ~17ms, up to 38 per session -- which provably
---changed nothing: an in-game watcher showed the container's IsShown and alpha
---identical across the flip (alpha tracks the combat fade rule, not casting).
---
---Deliberately conservative: returns true whenever the outcome cannot be ruled out
---from settings alone, so a mis-classification costs a redundant refresh (today's
---behaviour) rather than a stuck-hidden frame.
---@param name string  component name
---@return boolean
anchor.ForceVisibleMatters = function(name)
    local component = private.ComponentManager.GetComponent(name)
    if not component then return true end
    local settings = component.GetSettings()
    if not settings then return true end
    -- A programmatic override rewrites visMode at layout time (and only engages
    -- under "inherit"), so its hide modes aren't predictable from settings alone.
    if component.GetVisibilityOverride and component.GetVisibilityOverride() then
        return true
    end
    -- Rules gate: only an active hide rule can make rulesVisible false.
    if hasAnyHideRule(settings) then return true end
    local settingsVis = settings.visibility or "inherit"
    -- Mode gate: "always" is never mode-hidden, and "inherit" skips the mode gate
    -- entirely (L1113).  Every other mode (hidden / auto / only_in_combat /
    -- only_out_of_combat) can hide.
    if settingsVis ~= "inherit" and settingsVis ~= "always" then
        return true
    end
    -- Inherit-chain gate: an "inherit" component hides when its inheritance source
    -- is hidden.  Mirrors hasInheritSource (~L1185).  A component with neither an
    -- anchor_parent nor a position_reference always receives rootVisible = true, so
    -- it can never be chain-hidden.
    if settingsVis == "inherit" then
        local ap = settings.anchor_profile
        local apParentName = ap and ap.anchor_parent
        local posRefName = ap and ap.position_reference
        if apParentName and apParentName ~= "none" and apParentName ~= "cursor" then
            -- Having a parent is NOT the same as being hidden by it -- both chain
            -- gates read live state, so resolve it rather than assuming:
            --   L1359 fires only when the rootVisible the PARENT PASSES is false;
            --         that value is exactly lastResult[parent].rootVisible.
            --   L1391 fires only when the parent resolves no frame; that is
            --         lastResult[parent].anchorFrame == nil.
            -- If the parent currently resolves a frame AND passes rootVisible=true,
            -- neither gate can fire and forceVisible is inert *right now*.
            -- Re-evaluated per call, and it cannot go stale in a way that drops a
            -- needed refresh: any change to the chain's visibility is itself applied
            -- by a layout pass, which rewrites lastResult before the next call.
            local pr = lastResult[apParentName]
            if not (pr and pr.anchorFrame and pr.rootVisible) then
                return true
            end
            return false
        end
        -- position_reference roots inherit rootVisible from their reference via
        -- RefreshVisibilityOnly's deferred-root pass, whose nil-result semantics
        -- differ (nil => visible).  Rare; left conservative rather than mirrored.
        if posRefName and posRefName ~= "none" then
            return true
        end
    end
    return false
end

---Does a dependent's SIZE inherit the parent dimension that just changed?  A
---dependent's POSITION is always live (safeSetPoint to the parent frame), so a
---parent resize never needs repositioning -- only a parent-derived size recompute
---+ icon reflow, and only for the dimension the dependent actually inherits.
---Mirrors layoutRecursive's own width/height computation (~line 1465-1560) --
---KEEP IN SYNC:
---  * bottom/top side  -> width comes from the parent (height is own compH)
---  * left/right side  -> height comes from the parent when percent (width is own compW)
---  * absolute width   -> own size, fully parent-independent
---  * content-width    -> kept conservative (perf.md "reintroduce the overlap")
---Returns true (relayout) whenever unsure.  Skipping a dependent skips its whole
---subtree too, which is safe: an unchanged dependent's grandchildren live-anchor to
---an unchanged frame.
---@param childName string
---@param widthChanged boolean
---@param heightChanged boolean
---@return boolean
local function dependentNeedsRelayout(childName, widthChanged, heightChanged)
    local comp = private.ComponentManager.GetComponent(childName)
    if not comp or not comp.GetSettings then return true end
    local s = comp.GetSettings()
    local ap = s and s.anchor_profile
    if not ap then return true end
    local wantsContentWidth, side, widthMode, _, liveWidth = classifyAnchorSize(comp, s, ap)
    if wantsContentWidth then return true end                     -- own content width; keep conservative
    if widthMode == "absolute" then return false end              -- own size; parent-independent
    if side == "bottom" or side == "top" then
        -- liveWidth (percent-100) => useTwoPoint: width is the parent's, held LIVE by a
        -- two-corner anchor (TOPLEFT->BOTTOMLEFT + TOPRIGHT->BOTTOMRIGHT), so a parent
        -- width change updates it automatically with no recompute -- treat as static.
        -- percent<100 is a one-shot SetWidth(parent*pct) snapshot that goes stale, so it
        -- still relayouts on a width change.
        if liveWidth then return false end
        return widthChanged
    end
    if side == "left" or side == "right" then return heightChanged end
    return true                                                   -- corners / unknown side: conservative
end

---Reposition only `name`'s anchored subtree against `name`'s just-resized frame,
---synchronously and same-frame -- a scoped equivalent of applyLayout's normal-root
---branch restricted to `anchorChildren[name]`. Replaces a full `anchor.Refresh` for
---the frequent tracker-resize case, where only `name`'s dependents move, not all
---components. `lastResult[name]` holds exactly the context `name` passes its children
---(anchorFrame/alpha/fade/rootVisible), so they re-anchor with correct inheritance;
---`name` itself is marked visited and not re-laid-out (its geometry was just set by
---the caller). `isRefreshing` is raised so nested Show/Hide hooks fold into the dirty
---flag; a set flag escalates to one full refresh (rare -- grandchildren are laid out
---within this same recursion). Does NOT touch position_reference followers (not in
---anchorChildren; combat-frozen, caught by the next out-of-combat Refresh) or the
---forceVisible fallback pass (saved coords, resize-independent).
anchor.RelayoutSubtree = function(name, widthChanged, heightChanged)
    if not isReady then return end
    if isInBulkRefresh then
        -- Bulk operation in progress; defer to the single final EndBulkRefresh.
        pendingBulkStateChange = true
        return
    end
    if isRefreshing then
        -- A layout pass is already walking this subtree top-down. layoutRecursive
        -- runs each node's ContentLayout (which just set this size) BEFORE recursing
        -- into that node's children, so the descendant subtree is already re-laid-out
        -- against the new size within this same pass -- this re-entrant call is
        -- redundant. Do NOT set needsStateChange: that flag escalates a full-addon
        -- Refresh, and a child's resize never invalidates an already-positioned
        -- ancestor (a child's anchor_parent IS its ancestor, walked first). Setting it
        -- here fired 141 redundant full Refreshes in a 5.3s combat trace, ~50% CPU
        -- (see .context/performance.md). Genuine Show/Hide side effects still escalate
        -- via OnComponentStateChange's own re-entry guard.
        return
    end
    local children = anchorChildren[name]
    if not children or #children == 0 then return end
    local pr = lastResult[name]
    -- lastResult entries are pre-created with anchorFrame=nil (rebuildAnchorTree),
    -- so `not pr` never guards; a nil anchorFrame means name was never positioned --
    -- skip and let the next full pass place the subtree.
    if not pr or not pr.anchorFrame then return end

    isRefreshing = true
    needsStateChange = false
    wipe(layoutVisited)
    wipe(inheritedWidthCache)
    wipe(inheritedHeightCache)
    wipe(visibilityCache)
    wipe(componentSizeCache)
    cachedIsMounted = isMountedConditionActive()
    cachedInCombat = InCombatLockdown()
    cachedHasTarget = UnitExists("target")
    -- name's geometry was just committed by the caller; only its subtree moves.
    layoutVisited[name] = true
    -- Dimension gate: when the caller reports which dimension of `name` changed
    -- (setTargetSize passes explicit booleans), skip a dependent -- and its whole
    -- subtree -- whose size does not inherit that dimension.  Its position is
    -- live-anchored and its size is unchanged, so re-laying it out is pure waste
    -- (the common case: a height-only container resize relaying out width-inheriting
    -- children).  `gated` distinguishes "did not change" (false) from "no info"
    -- (nil -- other callers relayout everything, unchanged).
    local gated = widthChanged ~= nil or heightChanged ~= nil
    -- Subtree passes re-derive sizes/positions against the new parent geometry
    -- only — ContentLayout runs reposition-only (skinDirty=false); cleared
    -- before the escalation below so an escalated full Refresh skins normally.
    subtreeRepositionOnly = true
    for _, childName in ipairs(children) do
        if not gated or dependentNeedsRelayout(childName, widthChanged, heightChanged) then
            layoutRecursive(childName, pr.anchorFrame, pr.alpha, pr.fade, pr.rootVisible)
        end
    end
    subtreeRepositionOnly = false
    cachedIsMounted = nil
    cachedInCombat = nil
    cachedHasTarget = nil
    local dirty = needsStateChange
    isRefreshing = false
    -- Escalate once if a nested Show/Hide raised the dirty flag (mirrors
    -- RefreshVisibilityOnly). Rare: siblings are independent and grandchildren
    -- are laid out inside this recursion, so a full refresh seldom fires.
    if dirty then anchor.OnComponentStateChange() end
end

-- isReady: forward-declared near module-level tables; set to true in Initialize().

anchor.Initialize = function()
    isReady = true
    anchor.isReady = true
    rebuildAnchorTree()
    ensureExternalAnchorHooks()
    anchor.InvalidateTargetRuleCache()

    -- Install visibility watchers on root component CONTAINERS (not viewers).
    -- Viewer alpha fluctuates with Blizzard's UpdateShownState (e.g. alpha=0
    -- when no items are active) — watching it causes a per-frame oscillation
    -- between Blizzard hiding the viewer and our deferred refresh restoring it.
    -- Container Show/Hide reflects our addon's intent and is stable.
    for _, component in ipairs(private.ComponentManager.GetAllComponents()) do
        local s = component.GetSettings()
        local ap = s and s.anchor_profile
        if ap and (not ap.anchor_parent or ap.anchor_parent == "none" or ap.anchor_parent == "cursor") then
            local frame = component.GetFrame()
            if frame and not rootVisibilityWatched[frame] then
                rootVisibilityWatched[frame] = true
                local lastVisible = frame:IsShown() and frame:GetAlpha() > 0

                local function checkVisibilityChange()
                    if isRefreshing then return end
                    local visible = frame:IsShown() and frame:GetAlpha() > 0
                    if visible ~= lastVisible then
                        lastVisible = visible
                        anchor.OnComponentStateChange()
                    end
                end

                hooksecurefunc(frame, "SetAlpha", function()
                    checkVisibilityChange()
                end)

                frame:HookScript("OnHide", function()
                    checkVisibilityChange()
                end)
                frame:HookScript("OnShow", function()
                    checkVisibilityChange()
                end)
            end

        end
    end

    -- Two-pass refresh after Blizzard overwrites viewer positions via ApplySystemAnchor.
    EventRegistry:RegisterFrameEventAndCallback("EDIT_MODE_LAYOUTS_UPDATED", function()
        if not isReady then return end
        if InCombatLockdown() then return end
        if not private.profile then return end
        private.fontsDirty = true
        anchor.Refresh()
        private.fontsDirty = false
    end, anchor)

    -- Separate listener: EDIT_MODE_LAYOUTS_UPDATED may not fire if layout didn't change.
    EventRegistry:RegisterCallback("EditMode.Exit", function()
        if not isReady then return end
        if InCombatLockdown() then return end
        if not private.profile then return end
        private.fontsDirty = true
        anchor.Refresh()
        private.fontsDirty = false
    end, anchor)
end

anchor.OnComponentStateChange = function()
    if not isReady then return end
    if isRefreshing then
        -- Mid-refresh: flag the dirty loop inside applyLayout so it runs
        -- another pass before returning.  Same frame, same call stack —
        -- no timer defer, no one-frame stutter.
        needsStateChange = true
        return
    end
    if isInBulkRefresh then
        -- Bulk operation in progress (e.g. profile apply).  Defer to the
        -- single final Refresh fired from EndBulkRefresh.
        pendingBulkStateChange = true
        return
    end

    -- Coalesce: multiple components changing state in one frame (e.g. combat
    -- start collapsing/showing several trackers at once) each landed here and
    -- fired a full synchronous anchor.Refresh -- an in-game combat trace showed
    -- 4 back-to-back full refreshes in a single frame (~23ms, the PeakTime
    -- spike).  Route through the same one-refresh-per-frame coalescer that
    -- the combat and mount callbacks already use; the state applies one
    -- frame later, same tradeoff those paths accept.
    scheduleDeferredBulkRefresh(true)
end

anchor.Refresh = function()
    applyLayout()
end

---Frame currently being dragged in Edit Mode.  Set by EditMode.lua's
---OnDragStart hook, cleared by the position callback on drag stop.
---layoutRecursive skips ClearAllPoints+SetPoint on this frame so that
---deferred refreshes don't cancel the native WoW drag (StartMoving).
---@type Frame?
anchor.draggingFrame = nil

---True if anchor chain resolves to a visible parent (or free-moving).
---@param componentName string
---@param visited? table<string, boolean>  internal: position_reference cycle guard
---@return boolean
anchor.IsAnchorChainVisible = function(componentName, visited)
    local r = lastResult[componentName]
    if r and r.anchorFrame then
        return r.rootVisible
    end
    -- Fallback for components not yet laid out
    local component = private.ComponentManager.GetComponent(componentName)
    if not component then return false end
    local s = component.GetSettings()
    local ap = s and s.anchor_profile
    if not ap then return true end
    local parentName = ap.anchor_parent
    if not parentName or parentName == "none" or parentName == "cursor" then
        -- Free-moving root: check position_reference chain visibility.
        -- Without this, position_reference components always evaluate as
        -- visible even when their reference is hidden.
        local posRef = ap.position_reference
        if posRef and posRef ~= "none" then
            local refResult = lastResult[posRef]
            if refResult and refResult.anchorFrame then
                return refResult.rootVisible
            end
            -- Reference not yet laid out — defer to its own chain.
            -- The setters call WouldCreateCycle, which walks position_reference
            -- too, but an imported or hand-edited profile can still carry A→B→A
            -- and would recurse forever here. Cycle resolves to visible, the way
            -- isRootFrameVisible treats one.
            visited = visited or {}
            if visited[componentName] then return true end
            visited[componentName] = true
            return anchor.IsAnchorChainVisible(posRef, visited)
        end
        return true
    end
    -- Stopgap: when the immediate parent is absent (CDM-gated, disabled, no
    -- frame) or collapsed (enabled + framed but empty content), treat the
    -- component as a free-moving fallback root rather than requiring
    -- resolveParentFrame to find a non-nil ancestor frame. Without this, the
    -- fallback path returns false on initial load (before lastResult is
    -- populated) → SR.Refresh and similar hide the frame, and only the next
    -- Anchor.Refresh after a state change brings them back. Collapsed parents
    -- must not cascade-hide children either (empty != hidden).
    if parentIsAbsent(componentName) or parentIsCollapsed(componentName) then return true end
    if not isRootFrameVisible(componentName) then return false end
    return resolveParentFrame(componentName) ~= nil
end

local getEffectiveParentWidth
---Resolve the effective width that componentName's anchor parent provides.
---Walks the chain recursively, stacking percent-mode percentages, and reads
---frame width only at the root (anchor_parent = "none" or non-percent mode).
---Disabled parents are walked past (their percentage is not applied),
---mirroring resolveParentFrame behavior.
---@param componentName string
---@param visited? table<string, boolean>
---@return number?
getEffectiveParentWidth = function(componentName, visited)
    visited = visited or {}
    local component = private.ComponentManager.GetComponent(componentName)
    if not component then return nil end
    local s = component.GetSettings()
    local ap = s and s.anchor_profile
    if not ap then return nil end
    local parentName = ap.anchor_parent
    if not parentName or parentName == "none" or parentName == "cursor" then return nil end
    if visited[parentName] then return nil end -- circular guard
    visited[parentName] = true

    local parentComp = private.ComponentManager.GetComponent(parentName)

    -- External anchor or unknown component: read frame directly.
    if not parentComp then
        local parentFrame = resolveParentFrame(componentName)
        return parentFrame and parentFrame:GetWidth() or nil
    end

    -- Disabled parent (non-edit): passthrough — skip its percentage,
    -- return its own parent's effective width instead.
    if not parentComp.GetEnabled() and not private.isEditMode then
        return getEffectiveParentWidth(parentName, visited)
    end

    -- Enabled parent: compute its effective width from the chain.
    local parentAp = parentComp.GetSettings().anchor_profile
    if parentAp then
        local ppName = parentAp.anchor_parent
        if ppName and ppName ~= "none"
            and (parentAp.anchor_width_mode or "percent") == "percent"
        then
            local ppPct = parentAp.anchor_width_pct or 100
            local gpWidth = getEffectiveParentWidth(parentName, visited)
            if gpWidth and gpWidth > 0 then
                return gpWidth * (ppPct / 100.0)
            end
        end
    end

    -- Parent is root, absolute-mode, or external: use its configured size
    -- (GetComponentSize) instead of frame width.  Frame width may be smaller
    -- than configured width when LayoutViewerIcons shrinks the container to
    -- content; children must see the configured width for their constraints.
    if parentComp.GetComponentSize then
        local compW = getCachedComponentSize(parentName, parentComp)
        if compW and compW > 0 then return compW end
    end
    local parentFrame = parentComp.GetFrame()
    return parentFrame and parentFrame:GetWidth() or nil
end

---Return the parent-constrained width for an anchored component in percent mode.
---Returns nil when the component is free-moving, uses absolute width mode,
---or the parent frame cannot be resolved.  Used by layout code to cap
---icons-per-row and min_width to what the parent actually provides.
---Computes width by walking the anchor chain recursively instead of reading
---intermediate frame widths, which may be stale during RefreshAllComponents.
---@param componentName string
---@return number?
anchor.GetInheritedWidth = function(componentName)
    local cached = inheritedWidthCache[componentName]
    if cached ~= nil then return cached or nil end

    local component = private.ComponentManager.GetComponent(componentName)
    if not component then inheritedWidthCache[componentName] = false return nil end
    local settings = component.GetSettings()
    if not settings then inheritedWidthCache[componentName] = false return nil end
    local ap = settings.anchor_profile
    if not ap then inheritedWidthCache[componentName] = false return nil end
    local parentName = ap.anchor_parent
    if not parentName or parentName == "none" or parentName == "cursor" then inheritedWidthCache[componentName] = false return nil end
    -- Stopgap: treat absent immediate parents as free-moving, skipping width
    -- inheritance entirely rather than walking past the gate to UIParent (which
    -- produces huge children). See parentIsAbsent docstring.
    if parentIsAbsent(componentName) then inheritedWidthCache[componentName] = false return nil end
    local widthMode = ap.anchor_width_mode or "percent"
    if widthMode ~= "percent" then inheritedWidthCache[componentName] = false return nil end
    local pct = ap.anchor_width_pct or 100

    local parentWidth = getEffectiveParentWidth(componentName)
    if not parentWidth or parentWidth <= 0 then
        local parentFrame = resolveParentFrame(componentName)
        if not parentFrame then inheritedWidthCache[componentName] = false return nil end
        parentWidth = parentFrame:GetWidth()
    end
    local result = parentWidth * (pct / 100.0)
    inheritedWidthCache[componentName] = result
    return result
end

---Return the parent-constrained height for an anchored component in percent
---mode on a left/right side anchor.  Returns nil when the component is
---free-moving, uses absolute size mode, or is on a top/bottom anchor.
---Used by vertical fixed-height layout code so the container height
---matches the anchor parent's height instead of settings.height.
---@param componentName string
---@return number?
anchor.GetInheritedHeight = function(componentName)
    local cached = inheritedHeightCache[componentName]
    if cached ~= nil then return cached or nil end

    local component = private.ComponentManager.GetComponent(componentName)
    if not component then inheritedHeightCache[componentName] = false return nil end
    local settings = component.GetSettings()
    if not settings then inheritedHeightCache[componentName] = false return nil end
    local ap = settings.anchor_profile
    if not ap then inheritedHeightCache[componentName] = false return nil end
    local parentName = ap.anchor_parent
    if not parentName or parentName == "none" or parentName == "cursor" then inheritedHeightCache[componentName] = false return nil end
    -- Stopgap: treat absent immediate parents as free-moving (see parentIsAbsent).
    if parentIsAbsent(componentName) then inheritedHeightCache[componentName] = false return nil end
    local widthMode = ap.anchor_width_mode or "percent"
    if widthMode ~= "percent" then inheritedHeightCache[componentName] = false return nil end
    local side = ap.anchor_side or "bottom"
    if side ~= "left" and side ~= "right" then inheritedHeightCache[componentName] = false return nil end
    local pct = ap.anchor_width_pct or 100

    local parentFrame = resolveParentFrame(componentName)
    if not parentFrame then inheritedHeightCache[componentName] = false return nil end
    local parentHeight = parentFrame:GetHeight()
    if parentHeight <= 0 then inheritedHeightCache[componentName] = false return nil end
    local result = parentHeight * (pct / 100.0)
    inheritedHeightCache[componentName] = result
    return result
end

---Returns the effective alpha for a component (inherited or own based on mode).
---When a fade rule is active, returns the fade value.  Otherwise returns the
---component alpha (parent's alpha in inherit mode, own alpha otherwise).
---In Edit Mode, always returns 1.0 so components are fully visible for editing.
---Reads from lastResult (populated by layoutRecursive during applyLayout).
---@param componentName string
---@return number
anchor.GetEffectiveAlpha = function(componentName, _visited)
    if private.isEditMode then return 1 end
    local r = lastResult[componentName]
    if r then
        if not r.rootVisible then return 0 end
        local ownAlpha = r.fade < 1 and r.fade or r.alpha
        -- Position_reference components: lastResult may be stale when
        -- multiple layout passes race.  Walk the chain to the anchor-
        -- chain root (where lastResult IS reliable) and inherit its alpha.
        local comp = private.ComponentManager.GetComponent(componentName)
        if comp then
            local ap = comp.GetSettings().anchor_profile
            local posRef = ap and ap.position_reference
            if posRef and posRef ~= "none" then
                local visited
                if _visited then
                    visited = _visited
                else
                    wipe(effectiveAlphaVisited)
                    visited = effectiveAlphaVisited
                end
                if visited[posRef] then return ownAlpha end
                visited[componentName] = true
                local refAlpha = anchor.GetEffectiveAlpha(posRef, visited)
                if refAlpha < ownAlpha then return refAlpha end
            end
        end
        return ownAlpha
    end
    -- Fallback for additional frames not in the anchor tree
    local settings = resolveSettings(componentName)
    if not settings then return 1 end
    local visible, fade = evaluateVisibilityRules(settings)
    if visible and fade < 1 then return fade end
    return settings.alpha or 1
end

---Returns the effective frame strata resolved for a component.
---Reads from lastResult (populated by layoutRecursive). Mirrors the value
---already applied to the component frame at line ~798.
---@param componentName string
---@return string
anchor.GetEffectiveStrata = function(componentName)
    local r = lastResult[componentName]
    return (r and r.effectiveStrata) or "MEDIUM"
end

---Evaluate the visibility mode for a component.
---Non-inherit modes fully replace the anchor chain check.
---Does NOT check enabled state or Edit Mode (callers handle those).
---@param componentName string
---@return boolean
local evaluateVisibilityMode = function(componentName)
    local component = private.ComponentManager.GetComponent(componentName)
    if not component then return false end
    if component.GetForceVisible and component.GetForceVisible() then return true end
    local settings = component.GetSettings()
    if not settings then return false end
    local hasOverride = component.GetVisibilityOverride and component.GetVisibilityOverride()
    -- Override only engages when user chose "inherit"; explicit modes win.
    local settingsVis = settings.visibility or "inherit"
    local effectiveOverride = settingsVis == "inherit" and hasOverride or nil
    local mode = effectiveOverride or settingsVis
    -- Same system-vs-our-CVar distinction as the matching block in layoutRecursive.
    local cdmAvailable = (C_CooldownViewer and C_CooldownViewer.IsCooldownViewerAvailable()) or false
    if not cdmAvailable and not private.CDMDataSource.IsDataAvailable() then
        cdmAvailable = true
    end
    if mode == "always" then
        -- fall through to rules check
    elseif mode == "auto" then
        if not cdmAvailable then return false end
        -- "auto" mirrors the CDM: hidden while mounted (forceVisible is checked
        -- above and still wins, so skyriding ability bars keep showing).
        local mounted = passIsMounted()
        if mounted then return false end
    elseif mode == "hide_when_mounted" then
        local mounted = passIsMounted()
        if not (cdmAvailable and not mounted) then return false end
    elseif mode == "only_in_combat" then
        local inCombat = passInCombat()
        if not inCombat then return false end
    elseif mode == "hidden" then
        return false
    elseif mode == "inherit" then
        if not anchor.IsAnchorChainVisible(componentName) then return false end
    end

    -- Hide rules are additive across ALL visibility modes, so a configured one
    -- must evaluate even under "inherit" (patterns.md "Visibility & inheritance");
    -- only FADE rules stay inherit-gated, and those compose elsewhere. Otherwise
    -- "inherit" is pure pass-through — parent chain alone decides visibility.
    -- Gated on settingsVis (user intent), not mode — an active override can
    -- promote mode to "always" while the user still has "inherit" selected.
    -- Same gate as layoutRecursive's; keep the two in step.
    if settingsVis ~= "inherit" or hasAnyHideRule(settings) then
        local rulesVisible = evaluateVisibilityRules(settings)
        if not rulesVisible then return false end
    end

    return true
end

---True when component should be visible (Edit Mode active OR visibility mode satisfied).
---@param componentName string
---@return boolean
anchor.IsVisibleForComponent = function(componentName)
    local cached = visibilityCache[componentName]
    if cached ~= nil then return cached end
    local result
    if private.editModeHidden and private.editModeHidden[componentName] then
        result = false
    else
        result = private.isEditMode or evaluateVisibilityMode(componentName)
    end
    visibilityCache[componentName] = result
    return result
end

---Check whether pointing componentName at newParent would create a circular chain.
---Walks newParent's ancestor chain; returns true if componentName is encountered
---(meaning a cycle would form).
---
---The walk follows the EFFECTIVE chain — `anchor_parent`, or `position_reference`
---when there is no anchor_parent — because that is the chain the runtime walkers
---follow (`IsAnchorChainVisible`, `GetEffectiveAlpha`, `layoutRecursive`'s second
---pass). A `position_reference`-only cycle is one dropdown pick away from the
---shipped defaults: ConsumableBuffTracker and RaidBuffTracker are the only two
---components offered the widget, and RaidBuffTracker already follows
---ConsumableBuffTracker, so pointing ConsumableBuffTracker back closes the loop.
---@param componentName string  the component whose anchor_parent / position_reference is being set
---@param newParent string  the proposed new value
---@return boolean wouldCycle
anchor.WouldCreateCycle = function(componentName, newParent)
    if newParent == "none" or newParent == "cursor" then return false end
    local visited = {[componentName] = true}
    local current = newParent
    while current and current ~= "none" do
        if visited[current] then return true end
        visited[current] = true
        local comp = private.ComponentManager.GetComponent(current)
        if not comp then return false end
        local ap = comp.GetSettings().anchor_profile
        if not ap then return false end
        current = ap.anchor_parent
        if not current or current == "none" or current == "cursor" then
            current = ap.position_reference
        end
    end
    return false
end

private.Callback.Register("OnComponentEnable", function()
    rebuildAnchorTree()
    anchor.OnComponentStateChange()
end)
private.Callback.Register("OnComponentDisable", function()
    rebuildAnchorTree()
    anchor.OnComponentStateChange()
end)

-- Combat transitions, on the REGEN events because every combat read in a pass
-- is InCombatLockdown() (passInCombat, the secure freeze): the deferred pass
-- runs a frame later, inside the lockdown on entry and outside it on exit.
-- PLAYER_IN_COMBAT_CHANGED, which drove this before, tracks
-- UnitAffectingCombat instead and fires as a separate event, so the two
-- transitions could land a frame apart.
--
-- Entry runs only what the profile's combat dependence needs: nothing else a
-- pass computes changes at the pull, and this used to be a full relayout in the
-- middle of the opening rotation.  A hide reveals frames, which takes the full
-- pass, without fonts (see scheduleDeferredBulkRefresh).  A fade changes alpha
-- only: RefreshVisibilityOnly, a frame later so it runs inside the lockdown
-- like the full pass.  The full pass stays for "only_in_combat": the
-- visibility-only walk never Show()s a frame its mode revealed.
-- Exit always runs a full pass: the secure components were frozen for the
-- fight, and it is the catch-up pass for every tracker whose ContentLayout is
-- its Refresh (their own OnLeaveCombat refreshes are gone).
private.Callback.Register("OnEnterCombat", function()
    if anyComponentHidesOutOfCombat then
        scheduleDeferredBulkRefresh()
    elseif anyComponentFadesOutOfCombat then
        C_Timer.After(0, anchor.RefreshVisibilityOnly)
    end
end)
private.Callback.Register("OnLeaveCombat", function()
    scheduleDeferredBulkRefresh()
end)

-- Deferred: wait for Blizzard's mount animation/visibility changes to settle.
-- No fonts: a component revealed by dismounting keeps a hidden edit itself.
private.Callback.Register("OnMountStateChange", function()
    scheduleDeferredBulkRefresh()
end)

---Recalculate whether any component uses event-driven visibility rules
---(no_target, and combat: out_of_combat or the legacy "only_in_combat" mode).
---Called after profile changes and rule modifications.
anchor.InvalidateTargetRuleCache = function()
    anyComponentUsesTargetRule = false
    anyComponentHidesOutOfCombat = false
    anyComponentFadesOutOfCombat = false
    local function scanRules(settings)
        -- A "hidden" component looks the same in and out of combat and with or
        -- without a target: the mode gate hides it before the rules are read,
        -- and forceVisible shows it past both gates whatever the rules say.
        -- Counting its rules only bought a full pass on every pull (an Additional
        -- Frame parked at "hidden" with out_of_combat = hide).  Its children are
        -- scanned on their own settings.  The visibility-mode setters rescan.
        if settings.visibility == "hidden" then return end
        if settings.visibility == "only_in_combat" then anyComponentHidesOutOfCombat = true end
        local rules = settings.visibility_rules
        if not rules then return end
        if rules.no_target and rules.no_target ~= "off" then anyComponentUsesTargetRule = true end
        if rules.out_of_combat == "hide" then
            anyComponentHidesOutOfCombat = true
        elseif rules.out_of_combat == "fade" then
            anyComponentFadesOutOfCombat = true
        end
    end
    local components = private.ComponentManager.GetAllComponents()
    for _, comp in ipairs(components) do
        scanRules(comp.GetSettings())
    end
    if private.profile and private.profile.additional_frames then
        for _, afData in pairs(private.profile.additional_frames) do
            scanRules(afData)
        end
    end
end

---Lightweight refresh for visibility rule changes (target/mount/combat).
---Re-evaluates rules and updates container alpha/show/hide without full
---component relayout.  Falls back to a deferred full pass only if a component
---actually transitions between shown/hidden -- WITHOUT the font pass: under a
---no_target hide rule that is every target gained or lost, and the font pass
---restyles every aura button of every tracker (365 ms a swap in one capture).
---The components that style only while shown keep a hidden edit themselves
---(fontsOwed), so a reveal needs no font pass.
anchor.RefreshVisibilityOnly = function()
    if not isReady or isRefreshing then return end
    isRefreshing = true
    needsStateChange = false
    wipe(layoutVisited)
    wipe(visibilityCache)
    cachedIsMounted = isMountedConditionActive()
    cachedInCombat = InCombatLockdown()
    cachedHasTarget = UnitExists("target")
    appliedHasTarget = cachedHasTarget
    -- Two-pass: normal roots first, then position_reference roots.
    wipe(deferredRoots)
    for _, rootName in ipairs(anchorRoots) do
        local comp = private.ComponentManager.GetComponent(rootName)
        if comp then
            local ap = comp.GetSettings().anchor_profile
            if ap and ap.position_reference and ap.position_reference ~= "none" then
                deferredRoots[#deferredRoots + 1] = rootName
            else
                local apParent = ap and ap.anchor_parent
                local rv, pFrame
                if apParent and apParent ~= "none" and private.externalAnchors[apParent] then
                    pFrame = _G[apParent]
                    rv = true
                elseif not apParent or apParent == "none" or apParent == "cursor" then
                    rv = true
                else
                    -- Component is in anchorRoots only because rebuildAnchorTree
                    -- promoted it (configured parent isn't a registered component
                    -- — unknown external/AF anchor). Treat as free-moving root
                    -- regardless of own frame state. Reading frame:IsShown() here
                    -- would cascade-hide all children whenever the promoted root's
                    -- container happens to be hidden. Mirrors applyLayout.
                    rv = true
                end
                layoutRecursive(rootName, pFrame, 1, 1, rv, true)
            end
        end
    end
    local deferredCount = #deferredRoots
    if deferredCount > 0 then
        for i = 1, deferredCount do
            local rootName = deferredRoots[i]
            local comp = private.ComponentManager.GetComponent(rootName)
            if comp then
                local ap = comp.GetSettings().anchor_profile
                local pr = ap and ap.position_reference
                local refResult = pr and pr ~= "none" and lastResult[pr]
                -- Explicit nil-check: "refResult and refResult.rootVisible or true"
                -- fails when rootVisible is false (false or true → true).
                local rv = refResult == nil or refResult.rootVisible
                layoutRecursive(rootName, nil, 1, 1, rv, true)
            end
        end
        -- Re-sync alpha on secure component icons (SetAlpha is combat-safe).
        for i = 1, deferredCount do
            local rootName = deferredRoots[i]
            local comp = private.ComponentManager.GetComponent(rootName)
            if comp and comp.SyncAlpha then
                comp.SyncAlpha()
            end
        end
    end
    -- This walk is the whole combat-entry pass for a fade-only profile.
    -- ponytail: an enabled position_reference root syncs twice (above and in
    -- syncAllComponentAlpha); SyncAlpha only writes alpha, so the second call
    -- is a no-op.
    syncAllComponentAlpha()
    isRefreshing = false
    cachedIsMounted = nil
    cachedInCombat = nil
    cachedHasTarget = nil
    if needsStateChange then
        scheduleDeferredBulkRefresh()
    end
end

-- Target-change refresh — gated by anyComponentUsesTargetRule to skip when
-- no component has a no_target rule configured.  A no_target rule reads only
-- whether a target exists, and PLAYER_TARGET_CHANGED also fires on every switch
-- from one target to another, so a pass runs only when that differs from what
-- the last whole-tree pass applied.
private.Callback.Register("OnTargetChange", function()
    if not isReady then return end
    if not anyComponentUsesTargetRule then return end
    if UnitExists("target") == appliedHasTarget then return end
    anchor.RefreshVisibilityOnly()
end)

---Returns the cached mounted state during a layout pass, or a fresh check outside one.
---@return boolean
anchor.IsMounted = passIsMounted

---@type table<componentname, boolean>
anchor.nonAnchorable = nonAnchorableComponents

---@type table<componentname, boolean>
anchor.secureComponents = secureComponents
anchor.secureClickComponents = secureClickComponents

private.Anchor = anchor

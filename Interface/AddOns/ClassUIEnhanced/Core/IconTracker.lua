---Shared factory for the plain-frame cooldown icon trackers (CooldownTracker,
---UtilitiesTracker).
---
---Owns everything the two trackers have in common: the icon frame pool
---(display-only plain Frames — SecureActionButton children would protect the
---container and freeze combat relayout), the merged CDM+custom spell map, the
---per-button content refresh (secret-safe charge handling), the
---SPELL_UPDATE_COOLDOWN / keybind watchers, Refresh with membership-gated
---relayout, grid layout with the RelayoutSubtree resize chokepoint, alpha
---sync, and the size estimate.  Component-specific behavior (CooldownTracker's
---override bars) plugs in via config.hooks at well-defined seams.
---
---computeGridGeometry is the single source of the grid geometry formula, shared
---by the layout pass, this file's size estimate, and AuraIconTracker's (which is
---what BuffTracker's GetComponentSize resolves to).

local _
---@type string, private
local addonName, private = ...
local LAC = LibStub("LibAuraContainer-1.0")

---@class icontracker_hooks
---@field preRefresh nil|fun(): boolean  runs first in Refresh; return true when the hook owned the pass (e.g. override bar active)
---@field postSwipeUpdate nil|fun(settings: table): boolean  runs at the head of the per-event content pass; return true to own the pass and suppress the membership-change Refresh
---@field ownsContainer nil|fun(): boolean  true while the hook owns the container (override bar active); suppresses SyncAlpha's re-alpha of the parked base icons
---@field isCollapsed nil|fun(): boolean|nil  non-nil return overrides the default lastSpellCount==0 check
---@field getComponentSizeOverride nil|fun(): number|nil, number|nil  non-nil width return overrides the default grid estimate
---@field getAppendFrames nil|fun(active: boolean): table[]|nil  foreign icons to place after the spell grid (e.g. CooldownTracker's routed trinkets/potions); called with false when the grid is not showing, which must release them
---@field getForceVisible nil|fun(): boolean  installed as component.GetForceVisible when present
---@field afterInitialize nil|fun()  runs at the end of Initialize, before the first Refresh
---@field onEnable nil|fun()  runs first in OnEnable
---@field onDisable nil|fun()  runs first in OnDisable

---@class icontracker_config
---@field name string  component name (profile key, ComponentManager key)
---@field containerName string  global frame name for the container
---@field categoryId number  private.Enum.CooldownViewerCategoryIDs value, required only when buildSpellMap is absent
---@field routeKey string  AdditionalFrameManager routing domain, required only when buildSpellMap is absent
---@field extraWatcherEvents string[]|nil  additional events for the swipe watcher (e.g. ACTION_USABLE_CHANGED)
---@field hooks icontracker_hooks|nil
---@field parent Frame|nil  host frame an Additional Frame hands over its already anchor-managed container in; the tracker fills it instead of creating its own top-level frame
---@field getSettings nil|fun(): table  overrides the default private.profile.components[name] settings lookup (e.g. an Additional Frame's own profile entry)
---@field buildSpellMap nil|fun(): table<number, true>  overrides the default CDMDataSource-derived spell map (e.g. an Additional Frame's assigned_spells)
---@field getOrderRank nil|fun(name: string, spellMap: table<number, true>): table<number, number>|nil  overrides the default private.Util.BuildSpellOrderRank sort-rank lookup (e.g. an Additional Frame's assigned_spells order)
---@field getAppendRank nil|fun(frame: table, index: number): number|nil  interleaves hooks.getAppendFrames into the sort (same scale as getOrderRank) instead of appending last; nil = unranked.  See compareByOrderRank for the synthetic-id rules.

---@class icontracker_ctx  factory internals exposed to component hooks
---@field GetContainer fun(): Frame?
---@field SetContainerSize fun(w: number, h: number)
---@field activeButtons table<number, Frame>

---@class per_icon_slot_handle  one icon's own aura + swap containers
---@field wrapper Frame  cue wrapper, carries the icon's alpha
---@field container Frame  player-unit aura slots
---@field wrapperTarget Frame
---@field containerTarget Frame  target-unit aura slots, HARMFUL
---@field wrapperTargetHelpful Frame
---@field containerTargetHelpful Frame  target-unit aura slots, HELPFUL
---@field swapWrapper Frame  icon-swap wrapper, same alpha
---@field swapContainer Frame  player-unit swap slot
---@field swapWrapperTarget Frame
---@field swapContainerTarget Frame  target-unit swap slot, HARMFUL
---@field swapWrapperTargetHelpful Frame
---@field swapContainerTargetHelpful Frame  target-unit swap slot, HELPFUL

---@class icontrackerfacade
---@field CreateTracker fun(config: icontracker_config): table, icontracker_ctx
---@field ComputeGridGeometry fun(settings: viewer_tracker_profile_main, count: number, componentName: string): number, number, number, number, number, number, number
---@field PlaceGrid fun(settings: viewer_tracker_profile_main, componentName: string, frames: table, placeFn: fun(frame: table, anchorPt: string, x: number, y: number, w: number, h: number)): number, number
---@field BindCoveredMask fun(button: Frame): MaskTexture  bind a transparent mask to an aura slot button inside its initializeFrame; the engine shows it exactly while the button's aura is matched

-- ---------------------------------------------------------------------------
-- Shared pure helpers (no per-tracker state)
-- ---------------------------------------------------------------------------

---Mode-aware grid geometry shared by layoutButtons and GetComponentSize so
---the size estimate always agrees with the layout.  Honors layout_direction,
---frame_size_mode (incl. the single-line fixed_width* modes),
---overflow_icon_size, icon_height, min_width, and the anchor-inherited
---width/height caps.  Mirrors AdditionalFrameManager's layoutIcons sizing.
---@param settings viewer_tracker_profile_main
---@param count number  visible icon count (>= 1)
---@param componentName string
---@return number primarySize, number primaryHeight, number overflowSize, number overflowHeight, number iconsPerLine, number totalW, number totalH
local function computeGridGeometry(settings, count, componentName)
    local pad = settings.icon_offset or 2
    local mode = settings.frame_size_mode or "max_width"
    local layoutDir = settings.layout_direction or "horizontal"
    -- chain_fit ([TEST], collapsing chain only) is single-line like the three
    -- fixed modes, and sizes exactly like fixed_width -- so both the box estimate
    -- here and placeGrid's placement must treat it as one of them.  Without that
    -- it would fall through to the wrapping branch and the two would disagree.
    local isFixed = mode == "fixed_width" or mode == "fixed_width_spread"
        or mode == "fixed_width_stretch" or mode == "chain_fit"

    local availableWidth = private.Anchor.GetInheritedWidth(componentName)
    local availableHeight = (layoutDir == "vertical")
        and private.Anchor.GetInheritedHeight(componentName) or nil

    local primarySize, iconsPerLine
    if layoutDir == "vertical" then
        primarySize, iconsPerLine = private.Util.ComputeViewerIconLayoutVertical(settings, count, availableHeight)
    else
        primarySize, iconsPerLine = private.Util.ComputeViewerIconLayout(settings, count, availableWidth)
    end
    if primarySize <= 0 then primarySize = 1 end

    -- Icon height override (0/nil = square).  Ignored in fixed_width_stretch
    -- where icon_size already controls the cross-axis dimension.
    local hasIconHeight = settings.icon_height and settings.icon_height > 0
    local primaryHeight
    if mode == "fixed_width_stretch" or not hasIconHeight then
        primaryHeight = primarySize
    else
        primaryHeight = math.floor(settings.icon_height)
    end
    local overflowSize = (settings.overflow_icon_size and settings.overflow_icon_size > 0)
        and math.floor(settings.overflow_icon_size)
        or primarySize
    local overflowHeight = (hasIconHeight and mode ~= "fixed_width_stretch")
        and math.floor(overflowSize * settings.icon_height / primarySize)
        or overflowSize

    local minWidth = settings.min_width or 0
    local totalW, totalH
    if layoutDir == "vertical" then
        local containerHeight = settings.height or 150
        if availableHeight and availableHeight > 0 and availableHeight < containerHeight then
            containerHeight = availableHeight
        end
        if isFixed then
            totalW = math.max(primarySize, minWidth)
            totalH = containerHeight
        else
            local overflowLineCount = math.max(0, math.ceil(count / iconsPerLine) - 1)
            totalW = primarySize + overflowLineCount * (overflowSize + pad)
            if minWidth > 0 then totalW = math.max(totalW, minWidth) end
            local iconsInPrimary = math.min(count, iconsPerLine)
            totalH = iconsInPrimary * primaryHeight + math.max(0, iconsInPrimary - 1) * pad
        end
    else
        local containerWidth = settings.width or 400
        if availableWidth and availableWidth > 0 and availableWidth < containerWidth then
            containerWidth = availableWidth
        end
        if isFixed then
            totalW = containerWidth
            totalH = (mode == "fixed_width_stretch") and primarySize or primaryHeight
        else
            local overflowLineCount = math.max(0, math.ceil(count / iconsPerLine) - 1)
            totalH = primaryHeight + overflowLineCount * (overflowHeight + pad)
            local actualCols = math.min(count, iconsPerLine)
            local contentWidth = actualCols * primarySize + math.max(0, actualCols - 1) * pad
            local isContentWidth = (mode == "max_per_row")
                or (settings.icon_size and settings.icon_size > 0)
            if isContentWidth then
                totalW = math.max(contentWidth, minWidth)
                if availableWidth and availableWidth > 0 and totalW > availableWidth then
                    totalW = availableWidth
                end
            else
                totalW = containerWidth
            end
        end
    end
    return primarySize, primaryHeight, overflowSize, overflowHeight, iconsPerLine, totalW, totalH
end

---Place an ordered list of frames on the tracker grid and report the extent.
---
---Owns the complete old-viewer placement contract — layout_direction,
---layout_alignment (per-line, so a partial last line centers on its OWN count),
---the fixed_width* single-line modes, overflow lines at overflow_icon_size, and
---overflow_direction.  Geometry comes from computeGridGeometry, so every
---caller's GetComponentSize estimate agrees with what was actually placed.
---
---The caller supplies only the per-frame placement via
---`placeFn(frame, anchorPt, x, y, w, h)` — the anchor target and any styling
---are its business.  That is what lets the AuraContainer always-show trackers
---(BuffTracker / BuffTrackerBars slot cells) reuse this untouched: their cells
---are plain addon frames, positioned exactly like pooled icon buttons.
---@param settings viewer_tracker_profile_main
---@param componentName string
---@param frames Frame[]  ordered, all visible
---@param placeFn fun(frame: Frame, anchorPt: string, x: number, y: number, w: number, h: number)
---@return number totalW, number totalH
local function placeGrid(settings, componentName, frames, placeFn)
    local count = #frames
    if count == 0 then return 0, 0 end

    local pad = settings.icon_offset or 2
    local mode = settings.frame_size_mode or "max_width"
    local layoutDir = settings.layout_direction or "horizontal"
    local alignment = settings.layout_alignment or "center"
    -- chain_fit ([TEST], collapsing chain only) is single-line like the three
    -- fixed modes, and sizes exactly like fixed_width -- so both the box estimate
    -- here and placeGrid's placement must treat it as one of them.  Without that
    -- it would fall through to the wrapping branch and the two would disagree.
    local isFixed = mode == "fixed_width" or mode == "fixed_width_spread"
        or mode == "fixed_width_stretch" or mode == "chain_fit"

    local primarySize, primaryHeight, overflowSize, overflowHeight, iconsPerLine, totalW, totalH =
        computeGridGeometry(settings, count, componentName)

    -- Split into primary line and overflow lines.
    local primaryLine = {}
    local overflowLines = {}
    for i = 1, count do
        if i <= iconsPerLine then
            primaryLine[#primaryLine + 1] = frames[i]
        else
            local oi = math.ceil((i - iconsPerLine) / iconsPerLine)
            if not overflowLines[oi] then overflowLines[oi] = {} end
            local line = overflowLines[oi]
            line[#line + 1] = frames[i]
        end
    end

    if layoutDir == "vertical" then
        -- ===== VERTICAL PATH =====
        local overflowDir = settings.overflow_direction or "right"
        local hEdge = (overflowDir == "left") and "RIGHT" or "LEFT"
        local xSign = (overflowDir == "left") and -1 or 1
        local anchorPt
        if alignment == "top" then anchorPt = "TOP" .. hEdge
        elseif alignment == "bottom" then anchorPt = "BOTTOM" .. hEdge
        else anchorPt = hEdge end

        if isFixed then
            -- Fixed-height modes: all icons in a single column, no overflow.
            local containerHeight = totalH
            if mode == "fixed_width_stretch" then
                -- Icons stretch vertically to fill height; width = icon_size.
                local stretchH = math.max(1, math.floor((containerHeight - pad * (count - 1)) / count))
                local halfCol = math.floor((count * stretchH + (count - 1) * pad) / 2)
                for i = 1, count do
                    local y
                    if alignment == "top" then
                        y = -((i - 1) * (stretchH + pad))
                    elseif alignment == "bottom" then
                        y = (i - 1) * (stretchH + pad)
                    else
                        y = halfCol - stretchH / 2 - (i - 1) * (stretchH + pad)
                    end
                    placeFn(frames[i], anchorPt, 0, y, primarySize, stretchH)
                end
            elseif mode == "fixed_width_spread" then
                -- Icons at icon_size, spread evenly with equal gaps.
                local halfContainer = math.floor(containerHeight / 2)
                for i = 1, count do
                    local y
                    if count == 1 then
                        y = 0
                    else
                        local t = (i - 1) / (count - 1)
                        if alignment == "top" then
                            y = -(t * (containerHeight - primarySize))
                        elseif alignment == "bottom" then
                            y = t * (containerHeight - primarySize)
                        else
                            y = halfContainer - primarySize / 2 - t * (containerHeight - primarySize)
                        end
                    end
                    placeFn(frames[i], anchorPt, 0, y, primarySize, primaryHeight)
                end
            else -- fixed_width: dynamic square icons capped at height/4.
                local halfCol = math.floor((count * primarySize + (count - 1) * pad) / 2)
                for i = 1, count do
                    local y
                    if alignment == "top" then
                        y = -((i - 1) * (primarySize + pad))
                    elseif alignment == "bottom" then
                        y = (i - 1) * (primarySize + pad)
                    else
                        y = halfCol - primarySize / 2 - (i - 1) * (primarySize + pad)
                    end
                    placeFn(frames[i], anchorPt, 0, y, primarySize, primaryHeight)
                end
            end
        else
            -- Overflow / max-per-column modes.
            local function placeColumn(colFrames, sizeW, sizeH, xOff)
                local n = #colFrames
                local halfCol
                if alignment ~= "top" and alignment ~= "bottom" then
                    halfCol = math.floor((n * sizeH + (n - 1) * pad) / 2)
                end
                for i = 1, n do
                    local y
                    if alignment == "top" then
                        y = -((i - 1) * (sizeH + pad))
                    elseif alignment == "bottom" then
                        y = (i - 1) * (sizeH + pad)
                    else
                        y = halfCol - sizeH / 2 - (i - 1) * (sizeH + pad)
                    end
                    placeFn(colFrames[i], anchorPt, xOff, y, sizeW, sizeH)
                end
            end

            placeColumn(primaryLine, primarySize, primaryHeight, 0)
            for i, colFrames in ipairs(overflowLines) do
                local xOff = xSign * (primarySize + pad + (i - 1) * (overflowSize + pad))
                placeColumn(colFrames, overflowSize, overflowHeight, xOff)
            end
        end
    else
        -- ===== HORIZONTAL PATH =====
        local overflowDir = settings.overflow_direction or "bottom"
        local vEdge = (overflowDir == "top") and "BOTTOM" or "TOP"
        local ySign = (overflowDir == "top") and 1 or -1
        local anchorPt
        if alignment == "left" then anchorPt = vEdge .. "LEFT"
        elseif alignment == "right" then anchorPt = vEdge .. "RIGHT"
        else anchorPt = vEdge end

        if isFixed then
            -- Fixed-width modes: all icons in a single row, no overflow.
            local containerWidth = totalW
            if mode == "fixed_width_stretch" then
                -- Icons stretch horizontally to fill width; height = icon_size.
                local stretchW = math.max(1, math.floor((containerWidth - pad * (count - 1)) / count))
                local halfRow = math.floor((count * stretchW + (count - 1) * pad) / 2)
                for i = 1, count do
                    local x = -halfRow + stretchW / 2 + (i - 1) * (stretchW + pad)
                    placeFn(frames[i], anchorPt, x, 0, stretchW, primarySize)
                end
            elseif mode == "fixed_width_spread" then
                -- Icons at icon_size, spread evenly with equal gaps.
                local halfContainer = math.floor(containerWidth / 2)
                for i = 1, count do
                    local x
                    if count == 1 then
                        x = 0
                    else
                        local t = (i - 1) / (count - 1)
                        x = -halfContainer + primarySize / 2 + t * (containerWidth - primarySize)
                    end
                    placeFn(frames[i], anchorPt, x, 0, primarySize, primaryHeight)
                end
            else -- fixed_width: dynamic square icons capped at width/4.
                local halfRow = math.floor((count * primarySize + (count - 1) * pad) / 2)
                for i = 1, count do
                    local x = -halfRow + primarySize / 2 + (i - 1) * (primarySize + pad)
                    placeFn(frames[i], anchorPt, x, 0, primarySize, primaryHeight)
                end
            end
        else
            -- Overflow / max-per-row modes.
            local function placeRow(rowFrames, sizeW, sizeH, yOff)
                local n = #rowFrames
                local halfRow
                if alignment ~= "left" and alignment ~= "right" then
                    halfRow = math.floor((n * sizeW + (n - 1) * pad) / 2)
                end
                for i = 1, n do
                    local x
                    if alignment == "left" then
                        x = (i - 1) * (sizeW + pad)
                    elseif alignment == "right" then
                        x = -((i - 1) * (sizeW + pad))
                    else
                        x = -halfRow + sizeW / 2 + (i - 1) * (sizeW + pad)
                    end
                    placeFn(rowFrames[i], anchorPt, x, yOff, sizeW, sizeH)
                end
            end

            placeRow(primaryLine, primarySize, primaryHeight, 0)
            for i, rowFrames in ipairs(overflowLines) do
                local yOff = ySign * (primaryHeight + pad + (i - 1) * (overflowHeight + pad))
                placeRow(rowFrames, overflowSize, overflowHeight, yOff)
            end
        end
    end

    return totalW, totalH
end

---Candidate filter for the aura-duration slots.  One entry, so one slot per
---grid index: the container's unit is "player".
---
---INCLUDE_NAME_PLATE_ONLY matches Blizzard's own friendly-unit filter string
---(`GetTargetAurasFilterString`, CooldownViewerItemData.lua:661).  It is an
---*include* flag: without it, auras flagged nameplate-only are dropped from the
---match entirely (.context/api.md), which is silent — the slot simply never
---shows and every cue riding its button goes with it.
local AURA_SLOT_FILTERS = { "PLAYER|HELPFUL|INCLUDE_NAME_PLATE_ONLY" }

---Blizzard's own two TARGET filter strings, from `GetTargetAurasFilterString`
---(CooldownViewerItemData.lua:661), which picks by friendliness:
---`HARMFUL|PLAYER` on a hostile unit, the helpful string on a friendly one.
---`|PLAYER` on each is what scopes them to auras *we* applied.  Both the aura
---and the swap slots carry them.
---
---ONE CONTAINER PER STRING, each gated on its own identity gate
---(`AuraContainer.GateOnIdentity`), because on 12.1.0 a failed gate SKIPS
---`includeSpellIDs` rather than failing it (patterns-auracontainer.md "The
---identity-filter gate").  They used to share one container per family, which
---can only be switched as a whole, so the cross filter ran ungated: on a
---friendly target — self-targeted included — `HARMFUL|PLAYER` matched every
---debuff the player had cast on it, in every cell.  Live report: a self-cast
---22-minute quest debuff drawn as the aura takeover on every cooldown icon.
---Disabling the failed one is the choice Blizzard makes by reaction.
local TARGET_HARMFUL = "HARMFUL|PLAYER"
local TARGET_HELPFUL = "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"
local TARGET_HARMFUL_FILTERS = { TARGET_HARMFUL }
local TARGET_HELPFUL_FILTERS = { TARGET_HELPFUL }

---Empty spell list: `syncSlots` walks `1..max(want, allocated)` and gives every
---allocated slot the never-matching filter when the list is short, which is how
---a topology is switched off (there is no RemoveAuraSlot).
---@type number[]
local EMPTY_SLOT_LIST = {}

---Candidate filter for the player-unit icon-swap slots; the target ones use
---TARGET_HARMFUL_FILTERS / TARGET_HELPFUL_FILTERS, since a tracked spell's
---linked aura can be a debuff on an enemy or a buff on an ally.
local SWAP_SLOT_FILTERS_PLAYER = { "PLAYER|HELPFUL" }

---Dispel-type bind options for `bindCoveredIconMask`: `showAlways` has the
---engine `Show()` the mask for ANY matched aura and `Hide()` it otherwise, and
---`PreserveAsset` only vertex-colours it, which leaves it transparent.
local COVERED_ICON_MASK_OPTIONS = {
    showAlways = true,
    style = LAC.DispelTypeTextureStyle.PreserveAsset,
}

---Give a slot button a mask that erases the pooled icon's own art exactly while
---the button's aura is up, i.e. while the button covers that icon.
---
---A cover alone hides what is under it only at full opacity: alpha applies per
---region, so under any fade the covered art shows through.  The mask removes
---it instead.  It is fully transparent (a 1x1 CLAMPTOBLACKADDITIVE mask away
---from the icon, so every icon pixel samples alpha 0), and the ENGINE switches
---it: the dispel-type bind is the one setter that `Show()`s / `Hide()`s the
---object it is handed.  A mask merely created on the button would not do — a
---mask ignores its parent's visibility, so it would erase the icon for good.
---patterns-auracontainer.md "Where a decoration goes" has the client probes.
---
---Call from `initializeFrame`: binding is only legal before the button's
---access restrictions apply.  Adding the mask to the icon is `syncIconMasks`'
---job, because a texture takes at most three and a cell has up to twelve slot
---buttons.
---@param button Frame  slot button
---@return MaskTexture
local function bindCoveredIconMask(button)
    local mask = button:CreateMaskTexture()
    mask:SetTexture("Interface\\Buttons\\WHITE8x8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(1, 1)
    mask:SetPoint("TOPLEFT", UIParent)
    button:AddDispelTypeTexture(mask, COVERED_ICON_MASK_OPTIONS)
    return mask
end

---Ranks handed to compareByOrderRank for the current sort.  Module-level, like
---the comparator, so a layout pass allocates no closure; the sort is
---synchronous so there is no interleaving to worry about.
---@type table<number, number>|nil
local sortOrderRanks = nil

---Scratch table for the interleaved-append path only (config.getAppendRank
---present): layoutButtons wipes and refills this with a copy of the rank
---provider's ranks plus the synthetic append entries, then points
---sortOrderRanks at it, instead of writing synthetic ids into the provider's
---own table (BuildSpellOrderRank documents its return as a reused module
---table) or allocating a fresh table every pass.  Module-level and wiped, not
---reallocated, matching sortOrderRanks/frameScratch's idiom.  Untouched on
---the default (no getAppendRank) path.
---@type table<number, number>
local interleaveRankScratch = {}

---Sort comparator for the visible-buttons array: icon order, with id as the
---tie-break.
---
---Ranks come from whichever rank provider the tracker was built with —
---default is Util.BuildSpellOrderRank (the component's own `priority_order`
---first, Blizzard's CDM order — the layout blob's `orderedCooldownIDs`, or
---the DB2 category-set index — behind it); an injected config.getOrderRank
---(e.g. an Additional Frame's assigned_spells order) replaces it entirely.
---Sorting by id alone (what this used to do) matched Blizzard only by
---accident, since neither source is in id order.
---
---When config.getAppendRank is present, foreign icons (hooks.getAppendFrames)
---are merged into this same array before the sort, keyed by a synthetic
---negative id (-1, -2, … = negated 1-based index into the append list — see
---layoutButtons), so they are ranked through this same table rather than
---always landing after it.
---
---Unranked entries sort LAST, in id order — that is custom spells, which the
---rank source has never heard of, kept together at the end rather than
---interleaved at arbitrary positions among the ranked ones.  Within the
---unranked bucket, real (positive) ids sort before synthetic (negative) ones:
---without this, an unranked foreign icon — synthetic id, always negative —
---would sort ahead of every unranked real spell by plain numeric comparison,
---landing in front of the "last" bucket instead of at the true end.  This
---tie-break is what keeps that case safe: an appended frame with no rank
---(config.getAppendRank returned nil for it) still lands last.  Two unranked
---synthetic ids (two unranked foreign frames) are further tie-broken by
---ascending append index rather than plain id order, which would reverse
---append order (-2 < -1) — so they still draw in the order
---hooks.getAppendFrames(true) returned them.  All of this is inert on the
---default (no getAppendRank) path, where sortOrderRanks never holds a
---negative key.
local function compareByOrderRank(a, b)
    local ra = sortOrderRanks and sortOrderRanks[a.id]
    local rb = sortOrderRanks and sortOrderRanks[b.id]
    if ra ~= rb then
        if not ra then return false end
        if not rb then return true end
        return ra < rb
    end
    if ra == nil then
        if (a.id < 0) ~= (b.id < 0) then
            -- Both unranked: a synthetic (negative) id sorts after a real
            -- (positive) one, regardless of magnitude.
            return b.id < 0
        end
        if a.id < 0 then
            -- Both unranked AND both synthetic: ascending append index
            -- (id = -index, so a larger/less-negative id is the earlier
            -- append) instead of falling through to plain id order.
            return b.id < a.id
        end
    end
    return a.id < b.id
end

---Whether a spell counts as "on cooldown" for desaturation / visibility modes.
---Takes the already-fetched info tables so callers never double-fetch.
---A bare GCD is NOT a cooldown, and charge-spell semantics depend on
---treatChargingAsOnCD (default true / nil):
---true = any in-flight recharge counts (chargeInfo.isActive; currentCharges is
---secret and must never be compared, see patterns-secrets.md); false = only a
---real full cooldown counts (falls through to the non-charge formula).
---@param cdInfo table|nil  result of C_Spell.GetSpellCooldown(spellID)
---@param chargeInfo table|nil  result of C_Spell.GetSpellCharges(spellID)
---@param treatChargingAsOnCD boolean|nil  defaults to true when nil
---@return boolean
local function isSpellOnCooldown(cdInfo, chargeInfo, treatChargingAsOnCD)
    if treatChargingAsOnCD == nil then treatChargingAsOnCD = true end
    if treatChargingAsOnCD and chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1 then
        return chargeInfo.isActive == true
    end
    return cdInfo ~= nil and cdInfo.isActive == true and not cdInfo.isOnGCD
end

---Seed/refresh a tracker's named timer Font object and bind it to a button's
---Cooldown countdown text.  SetCountdownFont takes a global font object NAME,
---so a real named Font object is kept updated per tracker (created via
---GetOrCreateNamedFont — never bare CreateFont, see api.md).  Mirrors
---ApplyViewerFonts' timer handling: outline suppresses the shadow.
---@param button Frame
---@param timerFont table  settings.timer_font
---@param fontName string  per-tracker global font object name
local function applyButtonTimerFont(button, timerFont, fontName)
    local fontObj = private.Util.GetOrCreateNamedFont(fontName)
    local framework = _G["DetailsFramework"]
    framework:SetFont(fontObj, timerFont.font_face, timerFont.font_size, timerFont.font_flags)
    local hasOutline = timerFont.font_flags and timerFont.font_flags ~= "" and timerFont.font_flags ~= "NONE"
    local sox = timerFont.shadow_offset_x or 1
    local soy = timerFont.shadow_offset_y or -1
    if hasOutline or (sox == 0 and soy == 0) then
        fontObj:SetShadowColor(0, 0, 0, 0)
        fontObj:SetShadowOffset(0, 0)
    else
        local sc = timerFont.shadow_color or {0, 0, 0, 1}
        fontObj:SetShadowColor(sc[1], sc[2], sc[3], sc[4] or 1)
        fontObj:SetShadowOffset(sox, soy)
    end

    local cd = button.cue_Cooldown
    cd:SetCountdownFont(fontName)
    if cd.GetCountdownFontString then
        local fs = cd:GetCountdownFontString()
        if fs then
            local fc = timerFont.font_color or {1, 1, 1, 1}
            fs:SetTextColor(fc[1], fc[2], fc[3], fc[4] or 1)
            if timerFont.anchor_point then
                fs:ClearAllPoints()
                private.Pixel.SetPoint(fs, timerFont.anchor_point, button, timerFont.anchor_point,
                    timerFont.offset_x or 0, timerFont.offset_y or 0)
            end
        end
    end
end

---Apply font profiles to a button's FontStrings.  Runs at button creation and
---again only when a font setting changes (the private.fontsDirty pass in
---Refresh) — never on the per-event content path, which fires per
---SPELL_UPDATE_COOLDOWN in combat (see patterns.md "fontsDirty").
---@param button Frame
---@param settings viewer_tracker_profile_main
---@param timerFontName string  per-tracker global font object name for SetCountdownFont
local function applyButtonFonts(button, settings, timerFontName)
    if settings.stacks_font then
        private.Util.ApplyFontProfile(button.cue_Count, settings.stacks_font, button)
    end
    if settings.timer_font then
        applyButtonTimerFont(button, settings.timer_font, timerFontName)
    end
    local kb = settings.keybind_font
    if kb and kb.enabled then
        private.Util.ApplyFontProfile(button.cue_Keybind, kb, button)
    end
end

---Create the standard icon-button region kit on a freshly created pool frame.
---@param button Frame
---@param settings viewer_tracker_profile_main
---@param timerFontName string
local function initButton(button, settings, timerFontName)
    -- Ignore parent (container) alpha; buttons manage their own alpha directly.
    button:SetIgnoreParentAlpha(true)

    -- Icon texture fills the button.
    button.cue_Icon = button:CreateTexture(nil, "ARTWORK")
    button.cue_Icon:SetAllPoints(button)
    -- No mask of its own: a texture takes at most three, and all three belong
    -- to the slot buttons that cover this icon (bindCoveredIconMask).

    -- Out-of-range shadow, Blizzard's own atlas and alpha (CooldownViewer.xml:42).
    -- OVERLAY on the button, so the cooldown swipe (a child Frame at +3) still
    -- draws over it -- the same stacking their item frame has.  Unmasked, as
    -- theirs is.  refreshButtonContent writes its shown state unconditionally, so
    -- releaseButton needs no reset for it.
    button.cue_OutOfRange = button:CreateTexture(nil, "OVERLAY")
    button.cue_OutOfRange:SetAllPoints(button)
    button.cue_OutOfRange:SetAtlas("UI-CooldownManager-OORshadow")
    button.cue_OutOfRange:SetVertexColor(1, 1, 1, 0.5)
    button.cue_OutOfRange:Hide()

    -- Cooldown swipe overlay.  +3 rather than +1 leaves room for the icon-swap
    -- slot buttons underneath it (their container sits at tracker container+1, so
    -- they land at +2): a swapped icon replaces the base icon but must still be
    -- darkened by the real-cooldown swipe, or it reads as ready while on cooldown.
    button.cue_Cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cue_Cooldown:SetAllPoints(button)
    button.cue_Cooldown:SetFrameLevel(button:GetFrameLevel() + 3)
    button.cue_Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
    button.cue_Cooldown:SetDrawSwipe(true)
    button.cue_Cooldown:SetDrawEdge(false)
    button.cue_Cooldown:SetSwipeColor(0, 0, 0, 0.7)
    button.cue_Cooldown.noCooldownCount = true

    -- GCD overlay, 2.13.4's universal one (Util.GetOrCreateGCDCooldown, since
    -- deleted): its own dark swipe, no numbers, no edge, no bling.  +8 puts it
    -- above the aura takeover (slot button container+7, its Cooldown +8) so a
    -- GCD still sweeps over a buffed icon, and below the text overlay.
    button.cue_GCD = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cue_GCD:SetAllPoints(button)
    button.cue_GCD:SetFrameLevel(button:GetFrameLevel() + 8)
    button.cue_GCD:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
    button.cue_GCD:SetSwipeColor(0, 0, 0, 0.7)
    button.cue_GCD:SetDrawEdge(false)
    button.cue_GCD:SetDrawBling(false)
    button.cue_GCD:SetHideCountdownNumbers(true)
    button.cue_GCD.noCooldownCount = true

    -- Text overlay parented above the cooldown swipe.
    local textOverlay = CreateFrame("Frame", nil, button)
    textOverlay:SetAllPoints(button)
    textOverlay:SetFrameLevel(button.cue_Cooldown:GetFrameLevel() + 10)

    -- Charge count (bottom-right of icon).
    button.cue_Count = textOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.cue_Count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)

    -- Keybind text (top-left of icon).
    button.cue_Keybind = textOverlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.cue_Keybind:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)

    button.cue_spellID = nil
    button.cue_displaySpell = nil
    button.cue_visAlpha = 1

    applyButtonFonts(button, settings, timerFontName)
end

---Tooltip content resolver for pooled icon frames.
---@param self Frame
local function resolveTooltipSpell(self)
    local spellID = self.cue_spellID
    -- An item-backed entry has no spell to describe.  A trinket names a real
    -- equipped item, which is the tooltip Blizzard shows for it; a potion
    -- category does not — its item varies, and the last-used id comes back
    -- SECRET while cooldowns are restricted, so it can never reach SetItemByID.
    -- A nil payload is Tooltip.showTooltip's own "no tooltip" answer.
    local source = spellID and private.CDMDataSource.GetIconSource(spellID)
    if source then
        return "inventory", source.equipSlot
    end
    -- The rank a spell-rank family is drawn as (refreshButtonContent's display).
    local display = self.cue_displaySpell or spellID
    return "spell", display and (private.compat.GetOverrideSpell(display) or display)
end

---Reused stand-in for C_Spell.GetSpellCooldown's info table on the equip-slot
---path, so a per-frame refresh allocates nothing (performance.md "per-frame
---OnUpdate handlers that allocate").  Read and discarded within one
---refreshButtonContent call, so one table serves every button.
---`isOnGCD` is permanently false: an item cooldown never is one.
local itemCooldownInfo = {isActive = false, isOnGCD = false}

---Range-check registration state, shared by every tracker instance because the
---registration itself is global client state, not per tracker.
---
---`[spellID] = true` once we have asked the client to range-check that spell,
---`false` once we have established it has no range.  Blizzard keys the check on
---the BASE spellID (`GetBaseSpellID` is `cooldownInfo.spellID`, no override
---resolution, CooldownViewerItemData.lua:200) and matches the event against that
---same id, so this does too -- unlike every display query, which uses the active
---spell.
local rangeCheckEnabled = {}
---`[spellID] = true` while the current target is out of that spell's range;
---absent otherwise.  Written from the SPELL_RANGE_CHECK_UPDATE payload, which is
---the only source: C_Spell.IsSpellInRange is a one-shot read, and the event does
---not fire for a spell nobody enabled.
local spellOutOfRange = {}

---Ask the client to start range-checking one spell, once per session.
---
---**Deliberately never released.** Blizzard's `EnableSpellRangeCheck` is a flat
---per-spell bool, not a refcount ("False if the spell no longer needs the
---event"), and Blizzard's own CooldownViewer item frames enable the same spells
---for their own out-of-range tint (CooldownViewer.lua:743) -- they stay bound
---while CUE holds the viewers invisible, so they never release either.  Calling
---`false` when a button is released would therefore switch off a check the
---default UI, or another addon, is still relying on.  The registration is
---session state and is gone on the next reload; the cost of holding it is that
---SPELL_RANGE_CHECK_UPDATE keeps firing for a spell no longer tracked, which is
---one table store per event in the handler below.
---@param spellID number  the BASE spellID, matching Blizzard's own key
local function ensureRangeCheck(spellID)
    if rangeCheckEnabled[spellID] ~= nil then return end
    -- Same gate as Blizzard's (:740): a spell with no range never fires the
    -- event, so registering it is pure noise.
    local hasRange = C_Spell.SpellHasRange(spellID) and true or false
    rangeCheckEnabled[spellID] = hasRange
    if hasRange then
        -- EnableSpellRangeCheck is SecretArguments = AllowedWhenUntainted, unlike
        -- the three read APIs around it -- so this must never be handed a secret
        -- id.  It never is: the item-backed path (whose spellID can come from
        -- GetLastCategoryCooldownSource, SecretWhenCooldownsRestricted) does not
        -- reach here, and a potion has no range anyway.
        C_Spell.EnableSpellRangeCheck(spellID, true)
    end
end

---Write a button's keybind text.  Shared by refreshButtonContent and the
---OnKeybindsChanged handler, which redraws only this.  An item-backed entry
---(`source`) carries none: action slots hold spells.
---@param button Frame
---@param spellID number
---@param settings viewer_tracker_profile_main
---@param source table?  private.CDMDataSource.GetIconSource(spellID)
local function applyKeybindText(button, spellID, settings, source)
    local kb = settings.keybind_font
    if kb and kb.enabled and not source then
        local keybindText = private.Util.GetKeybindTextForSpell(spellID)
        if keybindText then
            button.cue_Keybind:SetText(keybindText)
            button.cue_Keybind:Show()
        else
            button.cue_Keybind:Hide()
        end
    else
        button.cue_Keybind:Hide()
    end
end

---The spell a key is DRAWN as.  A spell-rank family on "Highest" (WoW Forever)
---is drawn as its highest learned rank, whether a custom entry of this tracker
---(CustomSpells) or a whole CDM family (CDMDataSource) holds it; anything else
---is the key itself.  The key stays the button's identity -- the pool, config,
---order, alerts -- and everything the engine keys by the cast spell asks this
---instead: texture, cooldown, charges, usability, range, proc glow, keybind.
---@param componentName string
---@param spellID number
---@return number
local function displaySpell(componentName, spellID)
    return private.CustomSpells.GetRankedSpell(componentName, spellID)
        or private.CDMDataSource.GetRankedSpell(spellID) or spellID
end

---Update a button's visual content for the given spell (texture, cooldown
---swipe, charge count, desaturation, keybind text).  Also updates
---button.cue_visAlpha from icon_visibility_mode.  Combat-safe: no
---SetPoint/SetSize/SetFont.
---@param button Frame
---@param spellID number
---@param settings viewer_tracker_profile_main
---@param display number  displaySpell(name, spellID)
local function refreshButtonContent(button, spellID, settings, display)
    local iconSize = settings.icon_size or 40
    local iconHeight = (settings.icon_height and settings.icon_height > 0) and settings.icon_height or iconSize
    local visMode = settings.icon_visibility_mode or 1

    local suppressSwap = settings.suppress_buff_icon_swap == true

    -- Blizzard queries texture, cooldown and charges off the ACTIVE spell, not
    -- the base one — GetSpellCooldownInfo goes through GetSpellID (override
    -- first) and GetSpellChargeInfo through `overrideSpellID or spellID`
    -- (CooldownViewerItemData.lua:380/386).  C_Spell resolves no override for
    -- us, so a spec replacement — Augmentation's Deep Breath 357210 → Breath of
    -- Eons 403631 — drew the base spell's art and never showed a cooldown.
    -- The base id stays the key for everything that identifies CDM data or
    -- config: ResolveIconOverride, the button pool,
    -- and GetKeybindTextForSpell (action slots hold the base id).  Except for a
    -- spell-rank family on "Highest": every rank is its own spell, so an action
    -- slot holds whichever rank the player put there, most often the highest;
    -- keybind, range and proc glow ask `display` (displaySpell) like the rest.
    --
    -- Item-backed entries (potions keyed by spell category, trinkets by equip
    -- slot) have no spellID, so every C_Spell query here needs a different
    -- source.  Blizzard resolves the two the same way this does: the last item
    -- to start the category's cooldown (CooldownViewerItemData.lua:46) and the
    -- item equipped in the slot (CooldownViewer.lua:1024).
    local source = private.CDMDataSource.GetIconSource(spellID)
    local activeSpellID
    if source then
        -- GetOverrideSpell is SecretArguments = AllowedWhenUntainted, so addon
        -- code may not hand it the category's spellID, which is secret while
        -- cooldowns are restricted.  A category is not spec-overridable anyway.
        activeSpellID = source.spellCategoryID
            and private.compat.GetLastCategoryCooldownSource(source.spellCategoryID) or nil
    else
        activeSpellID = private.compat.GetOverrideSpell(display) or display
    end
    -- For the tooltip (resolveTooltipSpell), which only has the button.
    button.cue_displaySpell = display

    -- Icon texture and zoom.  Texcoords use the button's actual laid-out size
    -- (falling back to profile sizes before the first layout pass) — in the
    -- stretch and overflow-line cases it differs from icon_size/icon_height,
    -- and SetTexture resets SetTexCoord (patterns.md), so this per-refresh
    -- path must be self-contained.
    --
    -- suppress_buff_icon_swap OFF is the 12.0 baseline and reproduces the
    -- conditional-icon half of Blizzard's
    -- CooldownViewerItemDataMixin:GetSpellTexture dynamic-appearance path
    -- (CooldownViewerItemData.lua:548) — the conditional icon outranks the plain
    -- one.  ON takes Blizzard's own non-dynamic branch, originalIconID off the
    -- active spell.  The LINKED-spell half of that path is not here: the live
    -- linkedSpellID is secret while auras are, so the link is drawn as a static
    -- texture on an engine-shown swap slot instead (see syncSwapSlots).  The
    -- aura-icon branch above those never applied here: PreferAuraDataOverSpellData
    -- is false for an actively-cast spell whose aura lands on the player (:1084),
    -- which is every spell these trackers hold.
    -- A manual icon_overrides entry is the user pinning a texture, so it outranks
    -- the conditional icon here and suppresses the linked-spell swap slot in
    -- syncSwapSlots — the same precedence the deleted Util.ApplyIconOverride gave
    -- it on the CDM-child path, where the manual override won before the swap
    -- logic ran.
    local texture = private.Util.ResolveIconOverride(spellID)
    if not texture then
        if source then
            -- Blizzard's own precedence, in order: the static category art wins
            -- outright over anything dynamic, then the equipped item's icon
            -- (CooldownViewerItemData.lua:548/566).
            texture = source.icon
                or (source.equipSlot and ItemUtil.GetEquipSlotTexture(source.equipSlot))
        else
            local iconID, originalIconID, conditionalIconID = C_Spell.GetSpellTexture(activeSpellID)
            if suppressSwap then
                texture = originalIconID or iconID
            else
                texture = conditionalIconID or iconID
            end
        end
    end
    if texture then button.cue_Icon:SetTexture(texture) end
    local actualW, actualH = button:GetSize()
    if not actualW or actualW <= 0 then actualW, actualH = iconSize, iconHeight end
    button.cue_Icon:SetTexCoord(private.Util.GetIconZoomCoords(actualW, actualH))

    -- Cooldown overlay.  A trinket has no spell at all, so its cooldown comes
    -- off the equipped item.  C_Item.GetItemCooldown is NOT
    -- SecretWhenCooldownsRestricted (unlike C_Spell.GetSpellCooldown), so its
    -- numbers are plain and may be handed to SetCooldown, which rejects secrets
    -- from addon code (patterns-secrets.md "AllowedWhenUntainted Cooldown
    -- methods").  A potion category resolves to a real spellID and takes the
    -- ordinary spell path below; it has neither charges nor a GCD.
    local cdInfo, chargeInfo, itemStart, itemDuration
    if source and source.equipSlot then
        local itemID = GetInventoryItemID("player", source.equipSlot)
        if itemID then
            local startTime, duration, enable = private.compat.GetItemCooldown(itemID)
            if enable and duration and duration > 0 and (startTime + duration) > GetTime() then
                itemStart, itemDuration = startTime, duration
            end
        end
        itemCooldownInfo.isActive = itemDuration ~= nil
        cdInfo = itemCooldownInfo
    else
        cdInfo = activeSpellID and C_Spell.GetSpellCooldown(activeSpellID) or nil
        chargeInfo = activeSpellID and C_Spell.GetSpellCharges(activeSpellID) or nil
    end
    local hasCharges = chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1
    local isRealCD = cdInfo and cdInfo.isActive == true and not cdInfo.isOnGCD
    -- Published for CDMAlerts.OnCooldownStateChanged's edge detection. No
    -- duration/startTime gate (Blizzard's own CooldownViewer.lua:1002 has
    -- one) -- both are secret in 12.1 (.context/patterns-secrets.md) and
    -- isRealCD is already the whole "on a real cooldown" answer.
    -- Coerce to boolean: nil cdInfo (unused item category) must not collide
    -- with CDMAlerts' nil sentinel for "no prior observation".
    button.cue_onCooldown = isRealCD == true
    -- currentCharges is secret (patterns-secrets.md) — "at least one charge
    -- available" is the negation of "all depleted", which holds iff both
    -- the recharge and a real (non-GCD) cooldown are active.
    local allDepleted = hasCharges and chargeInfo.isActive == true and isRealCD
    local hasRemainingCharges = hasCharges and chargeInfo.isActive == true and not isRealCD
    -- The icon's own cooldown is now unconditional.  It used to yield the whole
    -- spiral to the aura duration while a tracked buff was up (`yieldToAura`),
    -- which is what forced a per-button GetAuraState read — and with it a viewer
    -- child walk — on every profile using the feature.  The aura now renders on
    -- the slot button, which the engine shows over this one while the aura is
    -- up, so the cooldown never has to be told to get out of the way.
    local cdDuration, fromCharges
    if chargeInfo and chargeInfo.isActive then
        cdDuration = C_Spell.GetSpellChargeDuration(activeSpellID)
        fromCharges = true
    elseif isRealCD then
        -- A GCD never lands here: it is drawn on cue_GCD (below).
        cdDuration = activeSpellID and C_Spell.GetSpellCooldownDuration(activeSpellID) or nil
    end
    -- reverse_swipe is applied BEFORE the cooldown is set, and on every pass
    -- whether or not one is set: the swipe reads its direction when it starts,
    -- so a SetReverse that follows SetCooldown can only ever affect the *next*
    -- cooldown.  The pre-12.1 renderer set it at the top of its per-child pass
    -- (Util.ApplySwipeToChild), which is why the option worked there and reads
    -- as dead here.  Blizzard orders it the same way
    -- (Blizzard_UIWidgetTemplateBase.lua:1314).
    button.cue_Cooldown:SetReverse(settings.reverse_swipe == true)
    if cdDuration or itemDuration then
        if itemDuration then
            button.cue_Cooldown:SetCooldown(itemStart, itemDuration)
        else
            button.cue_Cooldown:SetCooldownFromDurationObject(cdDuration)
        end
        -- no_cd_overlay / no_cd_overlay_edge_only are children of
        -- hide_active_swipe in Options and mean "do not DIM the icon while
        -- it is on cooldown".  On these plain buttons the dim IS the swipe,
        -- so they are a swipe recolor — gold tint, or fully transparent so
        -- only the leading edge reads (the addon-CD branch of the pre-12.1
        -- CDM renderer, since removed).  They never reach the GCD, which has its
        -- own dark overlay (cue_GCD), as it did in that renderer.
        local noDim = settings.hide_active_swipe and settings.no_cd_overlay
        if noDim then
            if settings.no_cd_overlay_edge_only then
                button.cue_Cooldown:SetSwipeColor(0, 0, 0, 0)
            else
                button.cue_Cooldown:SetSwipeColor(1, 0.95, 0.57, 0.4)
            end
        else
            button.cue_Cooldown:SetSwipeColor(0, 0, 0, 0.7)
        end
        -- gcd_edge_charges: a recharge with castable charges left renders
        -- as a leading-edge ring instead of the full darkening swipe.
        local edgeOnly = settings.gcd_edge_charges and fromCharges and hasRemainingCharges
        button.cue_Cooldown:SetDrawSwipe(not settings.hide_cd_swipe and not edgeOnly)
        -- The edge only where 2.13.4 drew one (Util.ApplySwipeToChild, since
        -- deleted): the two edge-only modes, gcd_edge_charges and the
        -- transparent no-dim swipe.  Blizzard's CDM also edges a recharge with
        -- charges left (CooldownViewer.lua:915), but 2.13.4 overrode that to a
        -- full swipe and left the edge to gcd_edge_charges.
        button.cue_Cooldown:SetDrawEdge((edgeOnly
            or (noDim and settings.no_cd_overlay_edge_only)) and true or false)
        button.cue_Cooldown:Show()
    else
        button.cue_Cooldown:Clear()
    end
    -- GCD: 2.13.4's universal overlay, independent of the charge / cooldown
    -- routing above and drawn over an active aura takeover too.  Gated by
    -- hide_gcd_swipe alone — hide_cd_swipe never reached it.
    local gcdDuration = not settings.hide_gcd_swipe and cdInfo and cdInfo.isActive
        and cdInfo.isOnGCD and activeSpellID
        and C_Spell.GetSpellCooldownDuration(activeSpellID) or nil
    button.cue_GCD:SetReverse(settings.reverse_swipe == true)
    if gcdDuration then
        button.cue_GCD:SetCooldownFromDurationObject(gcdDuration)
        button.cue_GCD:Show()
    else
        button.cue_GCD:Clear()
    end
    local hideText = settings.hide_cd_text
        or (settings.hide_charge_cd_text and hasCharges and not allDepleted)
    button.cue_Cooldown:SetHideCountdownNumbers(hideText and true or false)

    -- Ready blink = Blizzard's CooldownFlash flipbook (what hide_ready_blink is
    -- documented to suppress), NOT the Cooldown bling: the CDM's <Cooldown>
    -- element declares no BlingTexture at all (CooldownViewer.xml:48), so a CDM
    -- icon never blinged.  CooldownFrameTemplate does declare one, hence the
    -- unconditional disable — otherwise these buttons draw a blue star4 that
    -- 12.0 never showed.
    button.cue_Cooldown:SetDrawBling(false)

    -- Fire the flash on the ready EDGE.  Blizzard schedules it to *finish* at
    -- ready, which needs arithmetic on secret cooldown times (patterns-secrets.md
    -- "You cannot SCHEDULE off a secret time"), so it plays 0.75 s later here.
    -- The gate mirrors cooldownPlayFlash = isOnActualCooldown (CooldownViewer.lua
    -- :1009/:1043) unioned with the charge-recharge branch (:925).
    -- Mode 2 hides the icon the moment it is ready, so there is nothing to
    -- flash on; mode 3 only fades it, and hide_ready_blink is documented as
    -- "Independent of Icon Visibility", so the blink must still play there.
    local playsFlash = isRealCD or (chargeInfo and chargeInfo.isActive == true)
    if button.cue_wasOnCD and not playsFlash
        and not (settings.hide_ready_blink or visMode == 2) then
        private.GlowEffect.PlayReadyFlash(button, settings.cdm_glow_color)
    end
    button.cue_wasOnCD = playsFlash or nil

    -- hide_icon: cosmetic suppression of the spell texture + border (also
    -- re-applied after ApplyIconBorder in the layout pass).
    private.Util.ApplyIconVisibility(button, settings.hide_icon == true)

    -- Charge count.
    if hasCharges then
        -- Pass currentCharges straight through to SetText (render pass-through
        -- of a secret value is sanctioned; tostring() is not).
        if settings.hide_zero_charges then
            button.cue_Count:SetText(C_StringUtil.TruncateWhenZero(chargeInfo.currentCharges))
        else
            button.cue_Count:SetText(chargeInfo.currentCharges)
        end
        button.cue_Count:Show()
    elseif activeSpellID then
        -- Blizzard's fallback for a spell without charges: its cast ("use")
        -- count, shown while non-zero (CacheChargeValues, CooldownViewer.lua
        -- :1119) — Scourge Strike's Lesser Ghoul stacks.  Secret while cooldowns
        -- are restricted, so TruncateWhenZero stands in for the `> 0` test.
        button.cue_Count:SetText(C_StringUtil.TruncateWhenZero(C_Spell.GetSpellCastCount(activeSpellID)))
        button.cue_Count:Show()
    else
        button.cue_Count:Hide()
    end

    -- Cooldown state, read by the visibility modes below.
    local treatCharging = settings.icon_visibility_treat_charging_as_on_cd
    if treatCharging == nil then treatCharging = true end
    local onCD = isSpellOnCooldown(cdInfo, chargeInfo, treatCharging)

    -- Desaturation.
    if settings.no_desaturation then
        button.cue_Icon:SetDesaturated(false)
    else
        -- Desat keys off isRealCD, NOT onCD: a charge spell stays castable while
        -- recharging, so it must only grey out once every charge is spent (the
        -- full cooldown starts, isRealCD flips true).  onCD folds in
        -- icon_visibility_treat_charging_as_on_cd, which is a visibility setting
        -- and greys the icon the moment a recharge begins.  Matches the pre-12.1
        -- CDM renderer's `isRealCD and not hasRemainingCharges`.
        -- The pre-12.1 renderer's skipAuraDesat exception is not needed here:
        -- while the aura is up the takeover's icon copy covers this texture, so
        -- the icon reads coloured (grey under force_desaturation, syncAuraIcons).
        button.cue_Icon:SetDesaturated(isRealCD == true)
    end

    -- Usability tint, Blizzard's CooldownViewerCooldownItemMixin:RefreshIconColor
    -- (CooldownViewer.lua:1209) and its CooldownViewerConstants colours (:15-17).
    -- Desaturation above covers only the cooldown, so a spell with NO cooldown --
    -- a warrior's Execute -- had nothing that could ever dim it and read as
    -- permanently castable (reported 2026-09-14).
    --
    -- Read off the ACTIVE spell for the same reason the texture and swipe are
    -- (see activeSpellID above); IsSpellUsable is SecretArguments =
    -- AllowedWhenTainted, so it is callable in combat and on a secret id.
    --
    -- Out of range OUTRANKS both, as it does for Blizzard (:1227), and comes from
    -- the SPELL_RANGE_CHECK_UPDATE payload rather than a read -- see
    -- ensureRangeCheck.  It is keyed by the BASE spellID, which is what Blizzard
    -- registers and what the event carries; every other query here uses the
    -- active spell.  A rank family's base is the rank it is drawn as (display).
    -- An item-backed entry takes the usable colour unconditionally, exactly as
    -- Blizzard does for a spell-less entry that has a category (:1213), and never
    -- range-checks -- a potion has no range.
    if source then
        button.cue_Icon:SetVertexColor(1, 1, 1)
        button.cue_OutOfRange:Hide()
    else
        ensureRangeCheck(display)
        -- no_range_tint drops the red tint and its shadow; the usability tint
        -- below still applies.
        local outOfRange = not settings.no_range_tint and spellOutOfRange[display] == true
        if outOfRange then
            button.cue_Icon:SetVertexColor(0.64, 0.15, 0.15)
        else
            local isUsable, notEnoughPower = C_Spell.IsSpellUsable(activeSpellID)
            if isUsable then
                button.cue_Icon:SetVertexColor(1, 1, 1)
            elseif notEnoughPower then
                button.cue_Icon:SetVertexColor(0.5, 0.5, 1)
            else
                button.cue_Icon:SetVertexColor(0.4, 0.4, 0.4)
            end
        end
        -- Blizzard pairs the red tint with a shadow overlay (CooldownViewer.xml:42,
        -- SetShown at :1237).  Suppressed with the icon: hide_icon leaves nothing
        -- for a shadow to sit on.
        button.cue_OutOfRange:SetShown(outOfRange and not settings.hide_icon)
    end

    applyKeybindText(button, display, settings, source)

    -- icon_visibility_mode → per-button visibility alpha.  Every mode keys off
    -- the real cooldown alone; 2/3 hide/fade when READY, 4/5 the inverse.
    --
    -- 2/3 used to OR in "the tracked buff is up" ("buffing ~= ready"), which was
    -- the addon's last reader of a CooldownViewer child (GetAuraState ->
    -- rebuildAuraState) and the last thing holding the cooldownViewerEnabled
    -- CVar open.  It only ever differed from `onCD` for an entry buffed while
    -- NOT on cooldown: a GCD-only tracked spell, a charge spender sitting at
    -- full charges, or a buff outlasting its own cooldown.  Dropped
    -- deliberately, for the CDM independence — do not reintroduce it without
    -- re-reading CDMDataSource.md, since it brings the whole keep-alive back.
    local fadedAlpha = settings.icon_visibility_faded_alpha or 0.3
    if visMode == 2 then
        button.cue_visAlpha = onCD and 1 or 0
    elseif visMode == 3 then
        button.cue_visAlpha = onCD and 1 or fadedAlpha
    elseif visMode == 4 then
        button.cue_visAlpha = onCD and 0 or 1
    elseif visMode == 5 then
        button.cue_visAlpha = onCD and fadedAlpha or 1
    else
        button.cue_visAlpha = 1
    end
end

-- ---------------------------------------------------------------------------
-- Factory
-- ---------------------------------------------------------------------------

---Create an icon tracker component.  The returned component table is NOT yet
---registered with ComponentManager — the calling file does that (and assigns
---private.<Name>) so grep-ability and load order stay conventional.
---@param config icontracker_config
---@return table component, icontracker_ctx ctx
local function createTracker(config)
    local name = config.name
    local hooks = config.hooks or {}
    local extraWatcherEvents = config.extraWatcherEvents or {}

    local tracker = {}
    tracker.name = name

    ---Global font object name for SetCountdownFont (timer_font); distinct from
    ---the viewer-path names ("CUE_TimerFont_CooldownEssential" etc.).
    local timerFontName = "CUE_TimerFont_" .. name

    ---Addon-owned container frame, created once in Initialize.
    ---@type Frame?
    local container

    ---Free-list of released icon frames available for reuse.
    ---@type Frame[]
    local freeButtons = {}

    ---Active buttons keyed by spellID — all spells currently in the map.
    ---@type table<number, Frame>
    local activeButtons = {}

    -- Aura slots (hide_active_swipe OFF, and/or pandemic_glow) ---------------
    --
    -- 12.0 drew the ACTIVE AURA's remaining time in the icon's spiral, tinted
    -- gold, in place of the spell's real cooldown.  Aura durations are secret in
    -- 12.1, so the only way to render one is to let the engine do it: an
    -- AuraContainer slot per icon, with a Cooldown bound via SetDurationCooldown
    -- and a button the container shows only while the aura is up.
    --
    -- The same slot button is also what carries the native pandemic region
    -- (AuraContainer.AttachPandemic), so pandemic_glow runs the engine on its
    -- own — with the spiral suppressed and nothing yielded (see syncAuraSlots).
    --
    -- Slots are keyed by POOL INDEX, not by spell: a slot's cell is captured
    -- once (at AddAuraSlot time, the one moment geometry calls on the button are
    -- legal) and pooled buttons are never destroyed, so "the i-th button ever
    -- created" is the only stable cell identity the pool has — activeButtons is
    -- keyed by spell, and a spell's button changes as the pool recycles.  The
    -- slot button is SetAllPoints'd to its pooled button, so it rides every
    -- layout move for free and never needs another (restricted) geometry call.

    ---Every pooled button ever created, in creation order.
    ---@type Frame[]
    local allButtons = {}

    ---@type Frame?
    local auraWrapper
    ---@type Frame?
    local auraSlots
    ---Target-unit twins of the two above.  A separate container because SetUnit
    ---is per container, not per slot, and one per filter string because each is
    ---disabled on its own identity gate (TARGET_HARMFUL_FILTERS).
    ---@type Frame?
    local auraWrapperTarget
    ---@type Frame?
    local auraSlotsTarget
    ---@type Frame?
    local auraWrapperTargetHelpful
    ---@type Frame?
    local auraSlotsTargetHelpful

    -- Per-icon aura containers (the conditional topology) ---------------------
    --
    -- A cue bound into a slot button's subtree — the aura spiral, the pandemic
    -- border, the active-aura border — is shown by the ENGINE, and the button is
    -- not in our alpha chain (it is anchored to its cell, not parented to it).
    -- So an icon that `icon_visibility_mode` hides or fades keeps drawing its
    -- cues at full alpha.  The only frame we own between the component and the
    -- button is the container's WRAPPER, so per-icon alpha means one container
    -- per icon.
    --
    -- That costs a UNIT_AURA registration and per-delta bookkeeping each, and
    -- there is no RemoveAuraSlot to give it back.  `ShouldRegisterForUnitAuraEvents`
    -- (Blizzard_ManagedAuraContainer.lua:120-124) does key purely on
    -- HasAnyAuraGroups/HasAnyAuraSlots, but it is only the private-aura half of the
    -- decision: `UpdateEventRegistrations` (Blizzard_AuraContainer.lua:161) gates
    -- ALL dynamic registration on `ShouldRegisterForDynamicEvents` =
    -- `IsVisible() and IsEnabled()` (:157-159).  So a suspended container really
    -- does stop costing UNIT_AURA — which is what makes Suspend worth calling —
    -- and the residual cost is the slots that can never be removed from a
    -- container still in use.  Hence the topology is CONDITIONAL:
    -- mode 1 — the default, where every icon carries the same alpha
    -- — keeps the single shared container, and only modes 2-5 split.  An EMPTY
    -- container is free, which is why the shared one can stay eagerly created.
    --
    -- Neither topology is ever destroyed; switching neutralizes the abandoned
    -- one (every slot to the never-matching filter).  A profile that visits both
    -- keeps paying both until /reload.
    ---@type table<number, per_icon_slot_handle>
    local perIconSlots = {}
    ---@type boolean
    local usingPerIconSlots = false
    ---One-element spell list handed to SyncSlots per icon.  Reused: syncSlots
    ---captures the id and the cell as locals, never the table.
    ---@type number[]
    local perIconList = {}
    ---Pool index the shared perIconCellFor should answer with.
    ---@type number
    local perIconCellIndex = 0

    -- Icon-swap slots (suppress_buff_icon_swap OFF) ---------------------------
    --
    -- 12.0's swap read Blizzard's live `cooldownInfo.linkedSpellID` off the viewer
    -- child and textured the icon with it.  That value is secret-wrapped while
    -- auras are secret (it is returned from inside a branch conditioned on a
    -- secret aura field), so the swap is inverted instead: the LINKED ids come
    -- from the plain `linkedSpellIDs` table, and the engine supplies the "is it
    -- up" half by showing a slot button filtered to those ids.  A Texture on that
    -- button, bound with SetIcon so the engine draws the linked aura that
    -- actually matched, IS the swap — no secret is read in Lua, and it works in
    -- combat, which the old route did not.
    --
    -- Two containers because SetUnit is per container and a tracked spell's linked
    -- aura may land on the player (a proc buff) or on the target (a DoT).  Both
    -- are fed the merged spell map, never the selfAura split: `selfAura` is dead
    -- data Blizzard's own CDM never reads (.context/api.md), and the very spell
    -- that exposed the secret read — Fire Breath, whose linked aura is a target
    -- DoT — reports `selfAura = true`.
    --
    -- Slots are keyed by pool index for the same reason the aura slots are, and
    -- the swap texture's crop is re-applied on every sync (a slot's cell is fixed
    -- at allocation, but its size is not).
    ---@type Frame?
    local swapWrapperPlayer
    ---@type Frame?
    local swapSlotsPlayer
    ---@type Frame?
    local swapWrapperTarget
    ---@type Frame?
    local swapSlotsTarget
    ---@type Frame?
    local swapWrapperTargetHelpful
    ---@type Frame?
    local swapSlotsTargetHelpful

    ---Pool index each allocated swap slot button shadows, filled from the swap
    ---initializeFrame — the button is only writable there or outside aura
    ---secrecy, so this is what lets a later sync re-crop it.  Flat, like
    ---`auraSlotIndex`: a cell has one swap button per filter per topology, and a
    ---per-index registry kept only the last of them.
    ---@type table<Frame, number>
    local swapSlotIndex = {}

    ---Forward-declared: `clearSlotTopology` is defined above it and
    ---neutralizes the swap slots of whichever topology it is switching off.
    local initSwapButton

    ---Slot i's swap target: the spell on allButtons[i] when it has linked ids and
    ---the feature is on, else 0 (matches no aura).  Reused buffer.
    ---@type number[]
    local swapList = {}

    ---Slot i's filter target: the spell on allButtons[i], or 0 (matches no
    ---aura) when that button is free or the feature is off.  Reused buffer.
    ---@type number[]
    local slotList = {}

    ---Pool indices whose slot renders the aura takeover, as opposed to running
    ---purely to carry the pandemic / active-glow regions (the takeover is off,
    ---or `active_swipe_excludes` names the spell).  Set by syncAuraSlots and
    ---read by restyleSlotButton, syncAuraIcons and syncIconMasks, which draw
    ---nothing for an index missing here.
    ---@type table<number, true>
    local slotTakeover = {}
    ---An index entered or left `slotTakeover` since the last restyle.
    local slotTakeoverMoved = false

    ---Pool index each allocated aura slot button shadows.  One flat table, like
    ---`swapSlotIndex`: both containers of a pair share one `initSlotButton`, and
    ---the takeover pass wants every button for an index anyway.  A slot's cell
    ---is fixed at allocation, so an entry here never moves; buttons belonging to
    ---a switched-off topology stay registered but their filters match nothing,
    ---so re-texturing them is inert.
    ---@type table<Frame, number>
    local auraSlotIndex = {}

    ---Slot buttons (aura and swap) whose `cue_IconMask` is currently added to
    ---their pooled icon; `syncIconMasks` owns it.
    ---@type table<Frame, true>
    local iconMaskOn = {}

    ---Slot buttons (aura and swap) that belong to the per-icon topology.  Set at
    ---allocation, which always happens for the topology `usingPerIconSlots`
    ---names: the switch neutralizes the old one with the EMPTY list, which
    ---allocates nothing.
    ---@type table<Frame, true>
    local slotPerIcon = {}

    ---Aura slot buttons whose takeover icon is bound with `SetIcon`, which is
    ---done for an armed icon swap only (see syncAuraIcons).
    ---@type table<Frame, true>
    local auraIconBound = {}

    ---Last spiral-style settings, so the restyle pass runs only when one moved.
    local slotStyleReverse
    local slotStyleHideText, slotStyleHideSwipe

    ---A font edit a Refresh returned before (the preRefresh takeover, the
    ---disabled branch) waits for the next full one: the dismount pass that ends
    ---CooldownTracker's skyriding takeover carries no font pass.
    local fontsOwed = false

    ---Spell count from the last buildSpellMap, for IsCollapsed / size estimate.
    local lastSpellCount = 0

    ---Visible-icon count from the last layout pass — the size estimate must
    ---agree with what layout actually produced under the hide visibility modes.
    local lastVisibleCount = 0

    ---Foreign icons placed by the last layout pass (hooks.getAppendFrames), and
    ---their count.  Kept so SyncAlpha can re-alpha them without re-running the
    ---collector, which has side effects (SetIgnoreParentAlpha, font re-apply).
    ---@type table[]?
    local lastAppended
    local lastAppendCount = 0

    ---Last collapsed state for transition detection.
    local wasCollapsed = true

    ---@type Frame?
    local spellWatcher
    ---Whether a coalesced content pass is already scheduled on spellWatcher's
    ---OnUpdate.  At tracker scope so OnDisable can clear it in the same breath
    ---as the OnUpdate script — clearing the script alone would leave the flag
    ---latched at true and the coalescer permanently un-installable after a
    ---disable/enable cycle.
    local swipeDirty = false
    ---PLAYER_TARGET_CHANGED watcher for the target-unit aura containers.  Held
    ---at tracker scope (not as an Initialize local) so OnDisable can unregister
    ---it — a hosted tracker is thrown away and rebuilt on every profile switch,
    ---and an unreferenced frame with a live event registration keeps running.
    ---@type Frame?
    local targetWatcher

    ---@return viewer_tracker_profile_main
    local getSettings = config.getSettings or function()
        return private.profile.components[name]
    end
    tracker.GetSettings = getSettings

    ---Row-safe, for the same reason `deferredDisableHide` is: a HOSTED tracker's
    ---settings row is `private.profile.additional_frames[id]`, and both AF
    ---teardown paths remove that row while work scheduled by this tracker can
    ---still be pending (the swipe coalescer's OnUpdate), so
    ---a bare `getSettings().enabled` would index nil.  Guarding here rather
    ---than at each caller kills the whole error class at the source — an absent
    ---row means the frame is gone, i.e. not enabled.
    local function getEnabled()
        local settings = getSettings()
        return settings and settings.enabled
    end
    tracker.GetEnabled = getEnabled

    ---The pooled icon currently showing a spell, or nil when nothing is.  Named
    ---to match RacialTracker/TrinketTracker so `Core/Util/ButtonPress.lua` can
    ---find these buttons the same way it finds theirs — before the migration it
    ---reached them through the CDM viewer's children, which are now suppressed.
    ---@param spellID number
    ---@return Frame|nil
    tracker.GetIconFrame = function(spellID)
        return activeButtons[spellID]
    end

    ---Resize the container and notify anchored dependents through the
    ---dimension-gated RelayoutSubtree chokepoint (see performance.md) — a raw
    ---SetWidth/SetHeight leaves content-width children at stale positions.
    local function setContainerSize(w, h)
        local oldW, oldH = container:GetWidth(), container:GetHeight()
        container:SetWidth(w)
        container:SetHeight(h)
        local widthChanged = math.abs(w - oldW) > 0.5
        local heightChanged = math.abs(h - oldH) > 0.5
        if (widthChanged or heightChanged)
            and private.Anchor.HasAnchoredDependents(name) then
            private.Anchor.RelayoutSubtree(name, widthChanged, heightChanged)
        end
    end

    ---Build the merged {[spellID]=true} map via the shared CDMDataSource helper.
    ---
    ---The `selfAura` half is deliberately NOT kept as a separate eligibility set.
    ---It used to gate the aura slots — only "self-aura" spells got one — which is
    ---the exact mistake `.context/api.md` records: `selfAura` is a real DB2 field
    ---that Blizzard's own CDM never reads, and splitting on it drops tracking for
    ---every spell it mislabels.  Blizzard's model is to watch every tracked spell
    ---and let the candidate filter decide; a spell whose aura lands elsewhere just
    ---never matches the player-unit slot, which costs nothing and is what the
    ---icon-swap containers already do.
    ---@return table<number, true> merged
    local buildSpellMap = config.buildSpellMap or function()
        local selfMap, targetMap = private.CDMDataSource.BuildComponentSpellMaps(
            config.categoryId, config.routeKey, name)
        local merged = {}
        for spellID in pairs(selfMap) do merged[spellID] = true end
        for spellID in pairs(targetMap) do merged[spellID] = true end
        return merged
    end

    ---Style one slot button's bound spiral.  Registered as the tracker's
    ---AuraContainer restyle fn, so profile changes and setting edits re-run it
    ---out of aura secrecy (RestyleIfDirty's own gate).
    ---@param button Frame  slot button
    ---@param settings viewer_tracker_profile_main
    local function restyleSlotButton(button, settings)
        private.AuraContainer.ApplyActiveGlow(button, settings)
        local cd = button.cue_Cooldown
        -- Blizzard's own active-aura tint — the 12.0 look, which
        -- the pre-12.1 CDM renderer produced by recoloring the native CD with it.
        local auraColor = CooldownViewerConstants and CooldownViewerConstants.ITEM_AURA_COLOR
        local r, g, b, a = 1, 0.95, 0.57, 0.7
        if auraColor then
            r, g, b, a = auraColor.r, auraColor.g, auraColor.b, auraColor.a
        end
        -- The takeover (slotTakeover, see syncAuraSlots) draws Blizzard's own
        -- aura display (CheckCacheCooldownValuesFromAura, CooldownViewer.lua
        -- :885-887): a gold swipe over the aura's duration and no edge.  It
        -- contends with nothing -- the takeover icon (`cue_AuraIcon`) covers the
        -- icon's own cooldown underneath.
        cd:SetSwipeColor(r, g, b, a)
        -- The slot engine also runs when only pandemic_glow / active_glow want it
        -- (see syncAuraSlots).  In that case the Cooldown must draw NOTHING,
        -- leaving the button as a carrier for those regions alone.
        -- hide_cd_swipe hides this sweep too: in 2.13.4 it was a SetDrawSwipe on
        -- the CDM's own Cooldown, which during a buff WAS the gold sweep.
        local takeover = slotTakeover[auraSlotIndex[button]] == true
        cd:SetDrawSwipe(takeover and settings.hide_cd_swipe ~= true)
        cd:SetDrawEdge(false)
        cd:SetReverse(settings.reverse_swipe == true)
        -- No takeover: the icon's own countdown is the only timer, so a second
        -- one on top of it would double up.  Takeover: this IS the timer while
        -- the aura lasts, and `cue_AuraIcon` hides the icon's own countdown
        -- underneath it, so they never collide.  hide_cd_text is honoured here
        -- as well -- the aura timer stands in for the icon's timer, so the
        -- setting that suppresses one must suppress the other.
        local showsTimer = takeover and settings.hide_cd_text ~= true
        cd:SetHideCountdownNumbers(not showsTimer)
        if showsTimer and settings.timer_font then
            -- Same named Font object and same anchoring the pooled button's own
            -- countdown gets, so the two timers are indistinguishable as the
            -- display hands over.
            applyButtonTimerFont(button, settings.timer_font, timerFontName)
        end
    end

    ---initializeFrame for an aura slot: the bound spiral, and the one legal
    ---anchor to the pooled icon button it shadows.
    ---
    ---Deliberately no SetDurationText / SetApplicationCount bind — the spiral's
    ---own countdown numbers are the timer (same mechanism, same font object and
    ---hide_cd_text gate as the real-cooldown text), and charges are chrome that
    ---lives on the pooled button and must survive the slot's aura-driven hide.
    ---@param button Frame  slot button
    ---@param cell Frame  the pooled icon button this slot shadows
    local function initSlotButton(button, cell)
        button:SetAllPoints(cell)
        -- The takeover icon: an opaque copy (coloured unless force_desaturation)
        -- of the pooled button's art -- or, on an armed icon swap, the matched
        -- aura's own art via SetIcon -- set up by syncAuraIcons and left blank
        -- here (a slot's cell is fixed at allocation, the spell on it is not).
        -- The ENGINE's own show/hide of this button is what makes it a takeover:
        -- it covers the icon exactly while the tracked aura is up, which is the
        -- only way to reach "stay coloured while active" at all -- whether an
        -- aura is up is not readable in Lua under the 12.1 lockdown, so the
        -- icon's own SetDesaturated can never be told to hold off.
        -- It sits at container+7, above the pooled button's own cooldown
        -- (container+4, so the swipe and countdown underneath are covered) and
        -- below its text overlay (container+14, so charges and keybind survive).
        button.cue_AuraIcon = button:CreateTexture(nil, "ARTWORK")
        button.cue_AuraIcon:SetAllPoints(button)
        button.cue_AuraIcon:Hide()
        -- Erases the pooled icon's art while the takeover covers it, so a faded
        -- icon does not show it through the copy (syncIconMasks adds it).
        button.cue_IconMask = bindCoveredIconMask(button)
        slotPerIcon[button] = usingPerIconSlots or nil
        auraSlotIndex[button] = cell.cue_poolIndex
        button.cue_Cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        button.cue_Cooldown:SetAllPoints(button)
        button.cue_Cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8x8")
        button.cue_Cooldown:SetDrawBling(false)
        -- Aura countdown rounding, as the CDM's aura display set it
        -- (cooldownUseAuraDisplayTime, CooldownViewer.lua:870).  Before the
        -- bind: the object is protected from then on.
        button.cue_Cooldown:SetUseAuraDisplayTime(true)
        button.cue_Cooldown.noCooldownCount = true
        button:SetDurationCooldown(button.cue_Cooldown)
        -- Pandemic host, keyed by the pooled icon button this slot shadows, so
        -- syncPandemic can reach it by pool index — and therefore by spell, for
        -- pandemic_glow_excludes.
        private.AuraContainer.AttachPandemic(button, getSettings(), nil, cell)
        private.AuraContainer.TrackButton(name, button)
        restyleSlotButton(button, getSettings())
    end

    ---Cell for aura slot `index`: the pooled button it shadows.
    local function slotCellFor(index)
        return allButtons[index]
    end

    ---Cell for a per-icon container's single slot.  Module-scope rather than a
    ---closure per icon: syncSlots calls it once per sync and we would otherwise
    ---allocate one closure per icon per pass.
    ---@return Frame
    local function perIconCellFor()
        return allButtons[perIconCellIndex]
    end

    ---Re-evaluate one target-unit slot container against the current target:
    ---its identity gate (TARGET_HARMFUL_FILTERS), then a rebuild.  Also what
    ---arms the gate at creation.  The rebuild is needed because a target swap
    ---fires no container refresh of its own: SetUnit early-outs on an unchanged
    ---token and UNIT_AURA reports changes rather than the new unit's initial
    ---state.  UpdateAllAuras is Blizzard's sanctioned hook for exactly this and
    ---is combat-safe (patterns-auracontainer.md "Unit is container-level"), as
    ---is the SetEnabled behind the gate (see OnDisable).
    ---@param slots Frame  target-unit AuraContainer
    ---@param filter string  the one filter string its slots carry
    local function retargetSlots(slots, filter)
        private.AuraContainer.GateOnIdentity(slots, filter)
        slots:UpdateAllAuras()
    end

    ---The aura container carrying slot `index`, created on first use.
    ---
    ---Frame levels mirror the shared container so a cue lands in the same place
    ---either way: above the icon's own cooldown swipe (container+4), below the
    ---count / keybind overlay (container+14).
    ---@param index number  pool index
    ---@return per_icon_slot_handle
    local function ensurePerIconSlots(index)
        local handle = perIconSlots[index]
        if handle then return handle end
        local w, c = private.AuraContainer.Create(
            config.containerName .. "_AuraSlots" .. index, container)
        w:SetAllPoints(container)
        w:SetFrameLevel(container:GetFrameLevel() + 5)
        c:SetFrameLevel(w:GetFrameLevel() + 1)
        -- Target twins at the same levels: the three are mutually exclusive in
        -- practice (one aura, one unit, one reaction), so they never need to be
        -- ordered against each other.
        local wt, ct = private.AuraContainer.Create(
            config.containerName .. "_AuraSlotsT" .. index, container, "target")
        wt:SetAllPoints(container)
        wt:SetFrameLevel(container:GetFrameLevel() + 5)
        ct:SetFrameLevel(wt:GetFrameLevel() + 1)
        retargetSlots(ct, TARGET_HARMFUL)
        local wth, cth = private.AuraContainer.Create(
            config.containerName .. "_AuraSlotsTH" .. index, container, "target")
        wth:SetAllPoints(container)
        wth:SetFrameLevel(container:GetFrameLevel() + 5)
        cth:SetFrameLevel(wth:GetFrameLevel() + 1)
        retargetSlots(cth, TARGET_HELPFUL)
        -- Icon-swap pair for the same icon, at the shared swap levels
        -- (container+1, so the buttons land at +2): a swapped icon replaces the
        -- base icon but stays under that icon's own cooldown swipe and the
        -- spiral.  Built with the cue containers rather than on demand — an
        -- EMPTY container holds no slot, so it never registers for UNIT_AURA and
        -- costs nothing to keep — which buys one handle, one clear and one
        -- alpha mirror for both features.
        local sw, sc = private.AuraContainer.Create(
            config.containerName .. "_SwapPlayer" .. index, container)
        sw:SetAllPoints(container)
        sw:SetFrameLevel(container:GetFrameLevel() + 1)
        sc:SetFrameLevel(sw:GetFrameLevel())
        local swt, sct = private.AuraContainer.Create(
            config.containerName .. "_SwapTarget" .. index, container, "target")
        swt:SetAllPoints(container)
        swt:SetFrameLevel(container:GetFrameLevel() + 1)
        sct:SetFrameLevel(swt:GetFrameLevel())
        retargetSlots(sct, TARGET_HARMFUL)
        local swth, scth = private.AuraContainer.Create(
            config.containerName .. "_SwapTargetH" .. index, container, "target")
        swth:SetAllPoints(container)
        swth:SetFrameLevel(container:GetFrameLevel() + 1)
        scth:SetFrameLevel(swth:GetFrameLevel())
        retargetSlots(scth, TARGET_HELPFUL)
        handle = { wrapper = w, container = c, wrapperTarget = wt, containerTarget = ct,
            wrapperTargetHelpful = wth, containerTargetHelpful = cth,
            swapWrapper = sw, swapContainer = sc,
            swapWrapperTarget = swt, swapContainerTarget = sct,
            swapWrapperTargetHelpful = swth, swapContainerTargetHelpful = scth }
        perIconSlots[index] = handle
        return handle
    end

    ---Mirror a pooled icon's alpha onto the per-icon wrapper that carries its
    ---slot button, so an engine-shown cue fades and hides exactly with the icon
    ---it belongs to.  No-op on the shared topology, where every icon carries the
    ---same alpha by construction and `SyncAlpha` already alphas the one wrapper.
    ---@param button Frame
    ---@param alpha number
    ---@param mode number|nil  settings.icon_visibility_mode, so a cue fades on
    ---the same curve as the icon it belongs to rather than snapping under it
    local function syncCueAlpha(button, alpha, mode)
        if not usingPerIconSlots then return end
        local handle = perIconSlots[button.cue_poolIndex or 0]
        if handle then
            private.Util.ApplyIconVisibilityAlpha(handle.wrapper, alpha, mode)
            private.Util.ApplyIconVisibilityAlpha(handle.wrapperTarget, alpha, mode)
            private.Util.ApplyIconVisibilityAlpha(handle.wrapperTargetHelpful, alpha, mode)
            private.Util.ApplyIconVisibilityAlpha(handle.swapWrapper, alpha, mode)
            private.Util.ApplyIconVisibilityAlpha(handle.swapWrapperTarget, alpha, mode)
            private.Util.ApplyIconVisibilityAlpha(handle.swapWrapperTargetHelpful, alpha, mode)
        end
    end

    ---Write a pooled button's alpha and its cues', fading both when the
    ---visibility mode is a fade variant.
    ---@param button Frame
    ---@param alpha number
    ---@param mode number|nil  settings.icon_visibility_mode
    local function applyButtonAlpha(button, alpha, mode)
        private.Util.ApplyIconVisibilityAlpha(button, alpha, mode)
        syncCueAlpha(button, alpha, mode)
    end

    ---Neutralize a topology's slots: every allocated slot takes the
    ---never-matching filter, so the engine hides its button and every cue with
    ---it.  The sanctioned off switch — there is no RemoveAuraSlot, and nothing
    ---here is destroyed.
    ---@param perIcon boolean  which topology to switch off
    local function clearSlotTopology(perIcon)
        if perIcon then
            for index, handle in pairs(perIconSlots) do
                perIconCellIndex = index
                private.AuraContainer.SyncSlots(handle.container, AURA_SLOT_FILTERS,
                    EMPTY_SLOT_LIST, perIconCellFor, initSlotButton, nil)
                private.AuraContainer.SyncSlots(handle.containerTarget,
                    TARGET_HARMFUL_FILTERS, EMPTY_SLOT_LIST, perIconCellFor,
                    initSlotButton, nil)
                private.AuraContainer.SyncSlots(handle.containerTargetHelpful,
                    TARGET_HELPFUL_FILTERS, EMPTY_SLOT_LIST, perIconCellFor,
                    initSlotButton, nil)
                private.AuraContainer.SyncSlots(handle.swapContainer,
                    SWAP_SLOT_FILTERS_PLAYER, EMPTY_SLOT_LIST, perIconCellFor,
                    initSwapButton, nil)
                private.AuraContainer.SyncSlots(handle.swapContainerTarget,
                    TARGET_HARMFUL_FILTERS, EMPTY_SLOT_LIST, perIconCellFor,
                    initSwapButton, nil)
                private.AuraContainer.SyncSlots(handle.swapContainerTargetHelpful,
                    TARGET_HELPFUL_FILTERS, EMPTY_SLOT_LIST, perIconCellFor,
                    initSwapButton, nil)
            end
        elseif auraSlots then
            private.AuraContainer.SyncSlots(auraSlots, AURA_SLOT_FILTERS,
                EMPTY_SLOT_LIST, slotCellFor, initSlotButton, nil)
            private.AuraContainer.SyncSlots(auraSlotsTarget, TARGET_HARMFUL_FILTERS,
                EMPTY_SLOT_LIST, slotCellFor, initSlotButton, nil)
            private.AuraContainer.SyncSlots(auraSlotsTargetHelpful, TARGET_HELPFUL_FILTERS,
                EMPTY_SLOT_LIST, slotCellFor, initSlotButton, nil)
            private.AuraContainer.SyncSlots(swapSlotsPlayer, SWAP_SLOT_FILTERS_PLAYER,
                EMPTY_SLOT_LIST, slotCellFor, initSwapButton, nil)
            private.AuraContainer.SyncSlots(swapSlotsTarget, TARGET_HARMFUL_FILTERS,
                EMPTY_SLOT_LIST, slotCellFor, initSwapButton, nil)
            private.AuraContainer.SyncSlots(swapSlotsTargetHelpful, TARGET_HELPFUL_FILTERS,
                EMPTY_SLOT_LIST, slotCellFor, initSwapButton, nil)
        end
    end

    ---Point the aura slots at the currently displayed spells.
    ---
    ---A free or ineligible button's slot takes spell 0, which matches no aura —
    ---the sanctioned off switch, since there is no RemoveAuraSlot.
    ---
    ---TWO features want the slot engine, and they want different things from it:
    ---
    --- * `hide_active_swipe` OFF wants the TAKEOVER,
    ---   the 2.13.4 look and Blizzard's own aura display: while the aura is up
    ---   the engine shows the slot button, whose full-colour icon copy covers the
    ---   icon and whose bound Cooldown draws the gold swipe and the aura's timer.
    ---   No CDM gate — the pre-3.0 version needed `GetAuraState` (a viewer-child
    ---   read) to tell the icon to yield; the engine's show/hide of the slot
    ---   button makes the yield without Lua ever asking whether the aura is up.
    ---   `active_swipe_excludes` takes single spells out of it.
    ---
    --- * `pandemic_glow` / `active_glow` want only the button, as a carrier for
    ---   their regions.  Nothing drawn (restyleSlotButton switches every drawn
    ---   part of the bound Cooldown off for an index not in `slotTakeover`), and
    ---   no CDM gate — nothing on that path reads a viewer child either.
    ---
    ---This bails under lockdown and catches up on the combat-exit layout pass
    ---(Anchoring's OnLeaveCombat runs ContentLayout, i.e. Refresh).
    ---Not because container calls are
    ---combat-restricted — they aren't (see OnDisable below and
    ---`.context/api.md` "Aura rules (12.1+)"); this predates that finding and
    ---is kept deliberately, pending evidence that re-pointing aura slots
    ---mid-combat is safe.
    ---@param settings viewer_tracker_profile_main
    local function syncAuraSlots(settings)
        if not auraSlots or InCombatLockdown() then return end
        local n = #allButtons
        for i = 1, n do slotList[i] = 0 end
        for i = #slotList, n + 1, -1 do slotList[i] = nil end
        local takeover = settings.hide_active_swipe ~= true
        local excludes = settings.active_swipe_excludes
        local armed = false
        -- pandemic_glow and active_glow are the other reasons to run slots — the
        -- button is a pure carrier for a region whose visibility the engine owns.
        local cueWantsSlots = settings.pandemic_glow == true
            or settings.active_glow == true
        if takeover or cueWantsSlots then
            for spellID, button in pairs(activeButtons) do
                -- An item-backed entry has no aura identity, so its slot could
                -- never match — it would cost a pooled button and a filter entry
                -- per potion and trinket for nothing.
                if not private.CDMDataSource.GetIconSource(spellID) then
                    local index = button.cue_poolIndex
                    -- Same base/override test as the pandemic excludes.
                    local own = takeover
                        and not private.Util.BaseOrOverrideInList(spellID, excludes) or nil
                    -- An excluded spell still carries the glows' regions.
                    if own or cueWantsSlots then
                        slotList[index] = spellID
                        armed = true
                    end
                    if own ~= slotTakeover[index] then
                        slotTakeover[index] = own
                        slotTakeoverMoved = true
                    end
                end
            end
        end
        for i = 1, n do
            if slotList[i] == 0 and slotTakeover[i] then
                slotTakeover[i] = nil
                slotTakeoverMoved = true
            end
        end
        -- Only widen filters while the engine is actually on: resolving an
        -- identity set builds the CDM category model, which a profile with CDM
        -- integration off has no other reason to touch.  Keyed on "some slot
        -- points at a spell", which covers the takeover and pandemic-only modes
        -- alike — the displayed aura is often a linked id in both.
        local idSetFor = armed and private.CDMDataSource.GetAuraIdentitySet or nil
        -- State-transition trace only (Refresh runs hundreds of times a second in
        -- combat); the string is rebuilt per pass but printed only when it moves.
        -- Topology: per-icon only when icon_visibility_mode can give two icons
        -- different alphas.  Switching neutralizes the old one first, so its
        -- buttons cannot keep drawing cues the new one no longer owns.
        local wantPerIcon = (settings.icon_visibility_mode or 1) ~= 1
        if wantPerIcon ~= usingPerIconSlots then
            clearSlotTopology(usingPerIconSlots)
            usingPerIconSlots = wantPerIcon
        end

        if wantPerIcon then
            for i = 1, n do
                local spellID = slotList[i]
                local handle = perIconSlots[i]
                -- Create only for an icon that actually wants a slot; an icon
                -- that already has a container still gets a pass, to switch it
                -- off.  An unarmed icon feeds the EMPTY list rather than a 0
                -- entry: both neutralize the filter, but the empty one also
                -- drops the container's slot demand, so it can idle disabled.
                if handle or spellID ~= 0 then
                    local list = EMPTY_SLOT_LIST
                    if spellID ~= 0 then
                        perIconList[1] = spellID
                        list = perIconList
                    end
                    handle = handle or ensurePerIconSlots(i)
                    perIconCellIndex = i
                    private.AuraContainer.SyncSlots(handle.container, AURA_SLOT_FILTERS,
                        list, perIconCellFor, initSlotButton, idSetFor)
                    private.AuraContainer.SyncSlots(handle.containerTarget,
                        TARGET_HARMFUL_FILTERS, list, perIconCellFor,
                        initSlotButton, idSetFor)
                    private.AuraContainer.SyncSlots(handle.containerTargetHelpful,
                        TARGET_HELPFUL_FILTERS, list, perIconCellFor,
                        initSlotButton, idSetFor)
                end
            end
            return
        end
        -- Nothing armed feeds the EMPTY list rather than the all-zero one: both
        -- neutralize every allocated slot, but only the empty one drops the
        -- container's slot demand, so `setContainerDemand` can SetEnabled(false)
        -- and the container stops re-parsing auras entirely.
        local sharedList = armed and slotList or EMPTY_SLOT_LIST
        private.AuraContainer.SyncSlots(auraSlots, AURA_SLOT_FILTERS,
            sharedList, slotCellFor, initSlotButton, idSetFor)
        private.AuraContainer.SyncSlots(auraSlotsTarget, TARGET_HARMFUL_FILTERS,
            sharedList, slotCellFor, initSlotButton, idSetFor)
        private.AuraContainer.SyncSlots(auraSlotsTargetHelpful, TARGET_HELPFUL_FILTERS,
            sharedList, slotCellFor, initSlotButton, idSetFor)
    end

    ---initializeFrame for an icon-swap slot: one Texture, and the one legal anchor
    ---to the pooled icon button it shadows.
    ---
    ---The texture is bound with `SetIcon`, so the engine draws the art of the
    ---linked aura the slot matched.  A multi-link entry therefore shows the one
    ---that is up — Roll the Bones `1214909` carries four outcome buffs, and the
    ---static `linkedSpellIDs[1]` this replaced drew the same icon for all four.
    ---
    ---The swap replaces the base icon, so the base art is masked out while it
    ---shows (`bindCoveredIconMask`) rather than left under it to show through a
    ---fade.
    ---@param button Frame  slot button
    ---@param cell Frame  the pooled icon button this slot shadows
    initSwapButton = function(button, cell)
        button:SetAllPoints(cell)
        button.cue_SwapIcon = button:CreateTexture(nil, "ARTWORK")
        button.cue_SwapIcon:SetAllPoints(button)
        button:SetIcon(button.cue_SwapIcon)
        button.cue_IconMask = bindCoveredIconMask(button)
        slotPerIcon[button] = usingPerIconSlots or nil
        swapSlotIndex[button] = cell.cue_poolIndex
    end

    ---Point the icon-swap slots at the currently displayed spells and crop them.
    ---
    ---Only spells with linked ids get a slot: without one there is nothing to swap
    ---to, and `GetLinkedIdSet` returning nil would leave `SyncSlots` filtering on
    ---the base id — which would reveal the swapped icon while the BASE aura is up.
    ---
    ---Every value written here is plain.  The filter comes from the CDM's own
    ---`linkedSpellIDs` table and the texture from the engine's `SetIcon` bind, so
    ---Lua reads no secret on either side — which is the whole reason this
    ---replaces the live `linkedSpellID` read.
    ---
    ---Container calls are combat-restricted, so this bails under lockdown and
    ---catches up on the combat-exit layout pass, exactly like `syncAuraSlots`.  The
    ---swap ITSELF is engine-driven and therefore live in combat regardless.
    ---
    ---It also bails while auras are secret, which is NOT the same window: the
    ---slot buttons carry `DenyTaintedAccessWhenAurasAreSecret`, and that
    ---restriction cascades to `cue_SwapIcon` even though we created it inside
    ---`initializeFrame` (patterns-secrets.md).  Secrecy outlives combat in
    ---encounters/M+/PvP, so an `InCombatLockdown()`-only gate let the re-texture
    ---loop run against forbidden objects — live incident, `tex:Hide()` erroring
    ---"Attempt to access forbidden object from code tainted by an AddOn".
    ---@param settings viewer_tracker_profile_main
    ---@param merged table<number, true>
    local function syncSwapSlots(settings, merged)
        if not swapSlotsPlayer or InCombatLockdown()
            or private.Util.IsAuraAccessBlocked() then return end
        local n = #allButtons
        for i = 1, n do swapList[i] = 0 end
        for i = #swapList, n + 1, -1 do swapList[i] = nil end
        local on = settings.suppress_buff_icon_swap ~= true
        if on then
            for spellID, button in pairs(activeButtons) do
                -- A manual icon override outranks the swap: the user pinned that
                -- texture, and a swap slot would draw over it.
                if merged[spellID] and private.CDMDataSource.GetLinkedIdSet(spellID)
                    and not private.Util.ResolveIconOverride(spellID) then
                    swapList[button.cue_poolIndex] = spellID
                end
            end
        end
        local idSetFor = on and private.CDMDataSource.GetLinkedIdSet or nil
        -- EMPTY rather than the all-zero list when the feature is off, for the
        -- reason syncAuraSlots gives: both neutralize every allocated slot, but
        -- only the empty one drops the container's slot demand, so
        -- setContainerDemand can SetEnabled(false) and the container stops
        -- parsing auras.  With the zero list these two stayed enabled and
        -- registered for UNIT_AURA holding a slot per pool index that could
        -- never match -- 27 of them on a 9-icon tracker, for a feature switched
        -- off.
        local list = on and swapList or EMPTY_SLOT_LIST
        -- Per-icon topology: the swap slot rides its icon's OWN container pair,
        -- so the wrapper syncCueAlpha writes is the one carrying it and a mode
        -- 4/5 hide or fade takes the swapped icon with the icon.  On the shared
        -- pair it could not: a slot button is restricted, so the only alpha that
        -- reaches it is its container's, and one shared container cannot hold two
        -- icons' alphas.  syncAuraSlots owns the flag and runs first in Refresh,
        -- so it is already this pass's answer.
        if usingPerIconSlots then
            for i = 1, n do
                local handle = perIconSlots[i]
                -- Same create-or-switch-off rule as the cue slots: an icon with
                -- no swap and no container needs neither.
                if handle or swapList[i] ~= 0 then
                    local one = EMPTY_SLOT_LIST
                    if swapList[i] ~= 0 then
                        perIconList[1] = swapList[i]
                        one = perIconList
                    end
                    handle = handle or ensurePerIconSlots(i)
                    perIconCellIndex = i
                    private.AuraContainer.SyncSlots(handle.swapContainer,
                        SWAP_SLOT_FILTERS_PLAYER, one, perIconCellFor,
                        initSwapButton, idSetFor)
                    private.AuraContainer.SyncSlots(handle.swapContainerTarget,
                        TARGET_HARMFUL_FILTERS, one, perIconCellFor,
                        initSwapButton, idSetFor)
                    private.AuraContainer.SyncSlots(handle.swapContainerTargetHelpful,
                        TARGET_HELPFUL_FILTERS, one, perIconCellFor,
                        initSwapButton, idSetFor)
                end
            end
        else
            private.AuraContainer.SyncSlots(swapSlotsPlayer, SWAP_SLOT_FILTERS_PLAYER,
                list, slotCellFor, initSwapButton, idSetFor)
            private.AuraContainer.SyncSlots(swapSlotsTarget, TARGET_HARMFUL_FILTERS,
                list, slotCellFor, initSwapButton, idSetFor)
            private.AuraContainer.SyncSlots(swapSlotsTargetHelpful, TARGET_HELPFUL_FILTERS,
                list, slotCellFor, initSwapButton, idSetFor)
        end

        -- Re-crop.  The texture is the engine's (SetIcon), and its per-aura
        -- write keeps the texcoords (AuraContainer.lua's makeInit relies on the
        -- same), so only the crop follows a size or icon_zoom change here.
        -- Desaturation is not mirrored: the icon's own branch (`isRealCD`,
        -- refreshButtonContent) is a per-refresh cooldown state and this is a
        -- layout-pass sync, so a swapped icon stays saturated.
        --
        -- The engine picks among several matching links by its own candidate
        -- order, where Blizzard's CDM takes the first match in
        -- `linkedSpellIDs`.  They can only differ while two links are up at once.
        local iconSize = settings.icon_size or 40
        local iconHeight = (settings.icon_height and settings.icon_height > 0)
            and settings.icon_height or iconSize
        for button, index in pairs(swapSlotIndex) do
            -- Same texcoord source as refreshButtonContent: the button's actual
            -- laid-out size, falling back to the profile sizes before the first
            -- layout pass.
            local w, h = allButtons[index]:GetSize()
            if not w or w <= 0 then w, h = iconSize, iconHeight end
            button.cue_SwapIcon:SetTexCoord(private.Util.GetIconZoomCoords(w, h))
        end
    end

    ---Point every allocated aura slot's takeover icon at the art its pooled
    ---button is showing (`slotTakeover`, set by syncAuraSlots this pass).
    ---
    ---The texture comes from the pooled button's OWN `cue_Icon`, not from a
    ---second resolution of the same question: `refreshButtonContent` has already
    ---settled icon_overrides, the override spell and the conditional-icon
    ---precedence for this button, and reading back what it wrote cannot drift
    ---from it.  The one case where the pooled art is the wrong answer is an armed
    ---icon SWAP, which draws at container+2 and would vanish under the takeover
    ---at container+7 -- so there the copy is bound with `SetIcon` and the engine
    ---draws the aura the slot matched: for Roll the Bones, the outcome buff that
    ---was rolled.  This runs after `syncSwapSlots` so `swapList` is this pass's
    ---rather than the last one's.
    ---
    ---Same two gates as `syncSwapSlots`, for the same reason: the slot buttons
    ---carry `DenyTaintedAccessWhenAurasAreSecret` and the restriction cascades to
    ---a texture we created on them inside `initializeFrame`, and aura secrecy
    ---outlives combat in encounters/M+/PvP -- an `InCombatLockdown()`-only gate
    ---would run this loop against forbidden objects.
    ---@param settings viewer_tracker_profile_main
    local function syncAuraIcons(settings)
        if InCombatLockdown() or private.Util.IsAuraAccessBlocked() then return end
        local on = settings.hide_icon ~= true
        local iconSize = settings.icon_size or 40
        local iconHeight = (settings.icon_height and settings.icon_height > 0)
            and settings.icon_height or iconSize
        for button, index in pairs(auraSlotIndex) do
            local tex = button.cue_AuraIcon
            -- A slot whose filter matches nothing this pass never shows, so its
            -- copy is left blank rather than carrying stale art into the next
            -- spell that lands on this index; so is a glow carrier.
            local cell = on and slotTakeover[index] and allButtons[index] or nil
            -- Each SetIcon / ClearIcon ends in a full UpdateAuraDisplay, hence
            -- transitions only.  ClearIcon leaves the engine's last texture
            -- behind; the static branch below overwrites or hides it.
            local bind = cell ~= nil and (swapList[index] or 0) ~= 0
            if bind ~= (auraIconBound[button] == true) then
                auraIconBound[button] = bind or nil
                if bind then button:SetIcon(tex) else button:ClearIcon() end
            end
            local texture = cell and not bind and cell.cue_Icon:GetTexture()
            if tex and (bind or texture) then
                if texture then tex:SetTexture(texture) end
                -- Same texcoord source as refreshButtonContent: the button's
                -- actual laid-out size, falling back to the profile sizes before
                -- the first layout pass (SetTexture resets SetTexCoord).
                local w, h = cell:GetSize()
                if not w or w <= 0 then w, h = iconSize, iconHeight end
                tex:SetTexCoord(private.Util.GetIconZoomCoords(w, h))
                -- force_desaturation greys the takeover for the buff's whole
                -- duration.  2.13.4 greyed it only while the spell was on
                -- cooldown; this texture cannot follow that in combat (see the
                -- gate above), so it is set once per sync.
                tex:SetDesaturated(settings.force_desaturation == true
                    and settings.no_desaturation ~= true)
                tex:Show()
            elseif tex then
                tex:Hide()
            end
        end
    end

    ---Add or remove one slot button's `cue_IconMask` on its pooled icon, in the
    ---one direction this pass of `syncIconMasks` handles.
    ---@param button Frame  slot button
    ---@param index number  pool index it shadows
    ---@param want boolean  whether its mask should be on the icon
    ---@param adding boolean  pass 2 (adds) rather than pass 1 (removals)
    local function applyIconMask(button, index, want, adding)
        if want ~= adding or want == (iconMaskOn[button] == true) then return end
        iconMaskOn[button] = want or nil
        local icon = allButtons[index].cue_Icon
        if want then
            icon:AddMaskTexture(button.cue_IconMask)
        else
            icon:RemoveMaskTexture(button.cue_IconMask)
        end
    end

    ---Keep on each pooled icon only the masks of the slot buttons that can cover
    ---it now.  A texture takes at most THREE masks (the client errors past
    ---that), and a cell has up to twelve slot buttons: aura and swap, each with
    ---the player's filter plus the target's two, in each of two topologies.
    ---
    ---Only the active topology's buttons can show.  Of those, only one family
    ---covers the icon: the takeover where `slotTakeover` has the index, whose filters are a
    ---superset of the swap's (same units and strings, identity set over linked
    ---ids), so it covers every swap too; otherwise the swap, and a pandemic /
    ---active-glow carrier covers nothing.  That is three per cell, and every
    ---removal runs before any add, so a switch never passes through four.
    ---
    ---Transitions only (`iconMaskOn`): the set moves with hide_active_swipe,
    ---active_swipe_excludes or the topology, not per pass.  Same gates as
    ---syncAuraIcons, since the masks sit in the slot buttons' restricted subtrees.
    local function syncIconMasks()
        if InCombatLockdown() or private.Util.IsAuraAccessBlocked() then return end
        for pass = 1, 2 do
            local adding = pass == 2
            for button, index in pairs(auraSlotIndex) do
                applyIconMask(button, index, slotTakeover[index] == true
                    and (slotPerIcon[button] == true) == usingPerIconSlots, adding)
            end
            for button, index in pairs(swapSlotIndex) do
                applyIconMask(button, index, slotTakeover[index] ~= true
                    and (slotPerIcon[button] == true) == usingPerIconSlots, adding)
            end
        end
    end

    ---Bind (or re-bind) one pooled button's tooltip.  Hoisted out of
    ---acquireButton so OnEnable can restore the bindings OnDisable released:
    ---Tooltip.Release drops the button from the module's `tracked` array, and a
    ---pooled button is never re-created, so nothing else would ever bind it
    ---again.
    ---@param button Frame
    local function applyButtonTooltip(button)
        private.Tooltip.Apply(button, getSettings, resolveTooltipSpell, { kind = "own" })
    end

    ---Acquire a pooled icon frame; tooltip binding installed once at creation.
    local function acquireButton()
        local count = #freeButtons
        local button = freeButtons[count]
        if button then
            freeButtons[count] = nil
        else
            button = CreateFrame("Frame", nil, container)
            initButton(button, getSettings(), timerFontName)
            applyButtonTooltip(button)
            allButtons[#allButtons + 1] = button
            button.cue_poolIndex = #allButtons
        end
        button:Show()
        return button
    end

    ---Return an icon frame to the pool.
    local function releaseButton(button)
        -- A pooled button re-acquired for a different spell must not inherit the
        -- previous spell's proc glow; nothing else would ever clear it.
        private.GlowEffect.StopProc(button)
        -- Likewise the ready flash: a stale cue_wasOnCD would fire it on the new
        -- spell's first refresh, and an in-flight flipbook would resume on show.
        private.GlowEffect.StopReadyFlash(button)
        button.cue_wasOnCD = nil
        -- Likewise the alert edge-detection state and any running visual
        -- alert: a stale prevOnCooldown or a lingering animation would
        -- misfire/inherit onto whatever spell re-acquires this button.
        private.CDMAlerts.ReleaseButton(button)
        button:Hide()
        -- Drop the anchors too: a released button keeps its rect, and its aura
        -- slot's spiral is SetAllPoints'd to it from a container that is still
        -- shown — so a stale slot (the sync bails in combat) would keep drawing
        -- over empty space.  With no resolvable rect it draws nothing.
        -- placeIconButton re-anchors on re-acquire.
        button:ClearAllPoints()
        freeButtons[#freeButtons + 1] = button
    end

    ---Acquire buttons for new spells, release buttons for removed spells.
    ---@param spellMap table<number, true>
    local function syncButtons(spellMap)
        for spellID, button in pairs(activeButtons) do
            if not spellMap[spellID] then
                releaseButton(button)
                activeButtons[spellID] = nil
            end
        end
        for spellID in pairs(spellMap) do
            if not activeButtons[spellID] then
                local button = acquireButton()
                button.cue_spellID = spellID
                activeButtons[spellID] = button
            end
        end
    end

    ---Apply or clear the proc glow on one button per `proc_glow_style`.
    ---Blizzard's trigger is the SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE pair,
    ---but the event carries the *overlayed* spellID while our buttons are keyed
    ---by the CDM map's ID (they differ whenever the spell is overridden), so we
    ---query the state instead — the same derivation Blizzard's
    ---CooldownViewerCooldownItemMixin:RefreshOverlayGlow falls back to when it
    ---has no event state (`C_SpellActivationOverlay.IsSpellOverlayed`).
    ---The icon-hidden case (icon_visibility_mode hide) needs no handling
    ---here: the glow frames are ordinary descendants of the button, so a
    ---hidden button's alpha 0 cascades to them.
    ---@param button Frame
    ---@param spellID number
    ---@param settings viewer_tracker_profile_main
    ---@param display number  displaySpell(name, spellID): a rank family's drawn rank
    local function applyProcGlow(button, spellID, settings, display)
        local style = settings.proc_glow_style or "blizzard"
        -- A replacement spell is overlayed under whichever id the engine
        -- considers active, which is not our CDM key: Glacial Spike replaces
        -- Frostbolt/Frostfire Bolt, Prismatic Bolt replaces the next Arcane
        -- Blast, and neither ever glowed while only the base id was asked.
        -- Blizzard asks about the resolved id (RefreshOverlayGlow ->
        -- GetSpellID, CooldownViewerItemData.lua:216); we ask about both,
        -- because the button draws the override's art while the action slot
        -- still holds the base, and either can carry the overlay.
        local activeSpellID = display and private.compat.GetOverrideSpell(display)
        -- An item-backed key is not a spellID, so there is nothing to ask about.
        if style == "none"
            or private.CDMDataSource.GetIconSource(spellID)
            or not (C_SpellActivationOverlay.IsSpellOverlayed(display)
                or (activeSpellID and activeSpellID ~= display
                    and C_SpellActivationOverlay.IsSpellOverlayed(activeSpellID))) then
            private.GlowEffect.StopProc(button)
            return
        end
        private.GlowEffect.StartProc(button, style,
            settings.proc_glow_color or {1, 1, 1, 1},
            (settings.proc_glow_alpha or 100) / 100,
            settings.proc_glow_thickness or 2)
    end

    ---Placement settings for placeIconButton — set by layoutButtons around the
    ---placeGrid call.  Upvalues rather than a closure argument so the layout
    ---path (Refresh, hundreds/sec in combat) allocates no closure per pass.
    ---@type viewer_tracker_profile_main?
    local placeSettings
    local placeAlpha = 1

    ---Per-frame placement for the pooled icon buttons: anchor into the
    ---container, size, aspect-correct texcoords, alpha, border.
    local function placeIconButton(button, anchorPt, x, y, sizeW, sizeH)
        button:ClearAllPoints()
        button:SetPoint(anchorPt, container, anchorPt, x, y)
        button:SetSize(sizeW, sizeH)
        -- Foreign icon (a routed trinket/potion): its source component owns the
        -- texture, border, desaturation and text — we own only its rect and its
        -- alpha.  It stays parented to its source container, so the collector's
        -- SetIgnoreParentAlpha(true) is what makes this alpha stick.
        if not button.cue_Icon then
            -- An Additional Frame runs its foreign icons through the
            -- icon_visibility_mode filter, which parks a faded one on an alpha
            -- override and drives its own fade animation.  Multiply the
            -- override in and skip an in-flight fade rather than flat-writing
            -- (patterns.md: every writer of a routed icon's alpha multiplies
            -- the override).  Inert for CooldownTracker, whose foreign icons
            -- never carry one.
            if not private.Util.IsIconFading(button) then
                button:SetAlpha(placeAlpha * (private.Util.GetIconAlphaOverride(button) or 1))
            end
            return
        end
        button.cue_Icon:SetTexCoord(private.Util.GetIconZoomCoords(sizeW, sizeH))
        applyButtonAlpha(button, placeAlpha * (button.cue_visAlpha or 1),
            placeSettings.icon_visibility_mode)
        private.Util.ApplyIconBorder(button, nil,
            private.Util.GetSpellBorderColor(placeSettings, button.cue_spellID))
        -- ApplyIconBorder re-shows the border; re-assert hide_icon after it.
        private.Util.ApplyIconVisibility(button, placeSettings.hide_icon == true)
    end

    ---Reused ordered frame buffer handed to placeGrid — reverse-truncated so
    ---`#frameScratch` is the visible count (placeGrid iterates 1..#frames).
    ---@type Frame[]
    local frameScratch = {}

    ---Hand any foreign icons back to their source component.  They are not our
    ---children, so hiding the container does not hide them — without this they
    ---float at our last position and alpha.
    local function releaseAppendFrames()
        if hooks.getAppendFrames then hooks.getAppendFrames(false) end
        lastAppended = nil
        lastAppendCount = 0
    end

    ---Collect the visible buttons, hand them to the shared grid placement, and
    ---size the container.  Under a HIDE mode (2/4) a button at cue_visAlpha == 0
    ---is parked at alpha 0 and excluded; a fade mode keeps its slot even at
    ---faded_alpha 0, which is what its setting promises.  All geometry lives in placeGrid/computeGridGeometry, so the
    ---GetComponentSize estimate always agrees with the placement.
    ---@param spellMap table<number, true>
    ---@param settings viewer_tracker_profile_main
    ---@param effectiveAlpha number
    local function layoutButtons(spellMap, settings, effectiveAlpha)
        local visible = {}
        -- Only the HIDE modes drop a button out of the grid.  A fade mode at
        -- icon_visibility_faded_alpha == 0 reads as alpha 0 too, but its
        -- setting is documented as "still occupies its layout slot" — gating
        -- the grid on the alpha alone made it reflow like a hide mode.
        local hideMode = settings.icon_visibility_mode == 2
            or settings.icon_visibility_mode == 4
        for spellID in pairs(spellMap) do
            local button = activeButtons[spellID]
            if button then
                if not hideMode or (button.cue_visAlpha or 1) > 0 then
                    visible[#visible + 1] = {id = spellID, button = button}
                else
                    applyButtonAlpha(button, 0, settings.icon_visibility_mode)
                end
            end
        end
        sortOrderRanks = (config.getOrderRank or private.Util.BuildSpellOrderRank)(name, spellMap)

        -- Foreign icons ride the same grid.  Default (config.getAppendRank
        -- absent): appended after the sort, always landing last — the 12.0
        -- append order CooldownTracker's routed trinkets/potions rely on.
        -- When getAppendRank is present (an Additional Frame that wants a
        -- trinket/consumable/racial to hold its assigned_spells position
        -- instead), merge the appended frames into `visible` BEFORE the sort,
        -- keyed by a synthetic negative id (-1, -2, … = negated 1-based index
        -- into the append list), so they are ranked through the same
        -- sortOrderRanks/compareByOrderRank pass as real spells.
        local appended = hooks.getAppendFrames and hooks.getAppendFrames(true) or nil
        lastAppended = appended
        lastAppendCount = appended and #appended or 0

        local interleaveAppended = config.getAppendRank ~= nil
        if interleaveAppended and lastAppendCount > 0 then
            -- Copy the provider's ranks into the reused scratch table rather
            -- than writing synthetic ids into the provider's own table (it's
            -- a reused module table per BuildSpellOrderRank's contract), then
            -- point sortOrderRanks at the scratch copy for this sort.
            wipe(interleaveRankScratch)
            if sortOrderRanks then
                for id, rank in pairs(sortOrderRanks) do
                    interleaveRankScratch[id] = rank
                end
            end
            for i = 1, lastAppendCount do
                local synthID = -i
                visible[#visible + 1] = {id = synthID, button = appended[i]}
                interleaveRankScratch[synthID] = config.getAppendRank(appended[i], i)
            end
            sortOrderRanks = interleaveRankScratch
        end
        table.sort(visible, compareByOrderRank)

        local tailCount = interleaveAppended and 0 or lastAppendCount
        local count = #visible + tailCount
        lastVisibleCount = count
        if count == 0 then
            -- Nothing to draw is an ordinary steady state, not a transient: a
            -- CDM that reports no known spells leaves every tracker empty for as
            -- long as that is true.  Outside Edit Mode a 1x1 frame is right (the
            -- anchor system treats the component as collapsed and walks past
            -- it); in Edit Mode it leaves the user nothing to grab, so reserve
            -- the same one-icon box GetComponentSize already estimates there and
            -- keep frame and anchor system agreeing on the size.
            if private.isEditMode then
                local _, _, _, _, _, emptyW, emptyH = computeGridGeometry(settings, 1, name)
                setContainerSize(emptyW, emptyH)
            else
                setContainerSize(1, 1)
            end
            return
        end

        for i = 1, #visible do frameScratch[i] = visible[i].button end
        for i = 1, tailCount do frameScratch[#visible + i] = appended[i] end
        for i = #frameScratch, count + 1, -1 do frameScratch[i] = nil end

        placeSettings = settings
        placeAlpha = effectiveAlpha
        -- The slot spirals hang off their own wrapper, so component opacity has
        -- to be pushed there (the pooled buttons SetIgnoreParentAlpha).
        -- ponytail: component level only — a per-button alpha (the
        -- icon_visibility_mode fade/hide modes) cannot reach a restricted slot
        -- button; give each slot its own wrapper frame if that pairing matters.
        if auraWrapper then auraWrapper:SetAlpha(effectiveAlpha) end
        if auraWrapperTarget then auraWrapperTarget:SetAlpha(effectiveAlpha) end
        if auraWrapperTargetHelpful then auraWrapperTargetHelpful:SetAlpha(effectiveAlpha) end
        if swapWrapperPlayer then swapWrapperPlayer:SetAlpha(effectiveAlpha) end
        if swapWrapperTarget then swapWrapperTarget:SetAlpha(effectiveAlpha) end
        if swapWrapperTargetHelpful then swapWrapperTargetHelpful:SetAlpha(effectiveAlpha) end
        local totalW, totalH = placeGrid(settings, name, frameScratch, placeIconButton)

        setContainerSize(math.max(totalW, 1), math.max(totalH, 1))
    end

    -- -----------------------------------------------------------------------
    -- Component lifecycle
    -- -----------------------------------------------------------------------

    tracker.GetFrame = function()
        return container
    end

    tracker.Refresh = function()
        if not container then return end
        if private.fontsDirty then fontsOwed = true end

        -- Component seam: e.g. CooldownTracker's override-bar takeover.  A hook
        -- that owns the pass owns the whole container, so foreign icons go back.
        if hooks.preRefresh and hooks.preRefresh() then
            releaseAppendFrames()
            return
        end

        if not getEnabled() and not private.isEditMode then
            releaseAppendFrames()
            container:Hide()
            return
        end

        local settings = getSettings()
        local spellMap = buildSpellMap()
        lastSpellCount = 0
        for _ in pairs(spellMap) do lastSpellCount = lastSpellCount + 1 end

        syncButtons(spellMap)

        -- Aura takeover: repoint the slots at the current buttons, then
        -- restyle them when a setting they read has actually moved (the profile
        -- path marks dirty on its own; RestyleIfDirty is a no-op otherwise).
        syncAuraSlots(settings)
        -- Icon swap: same repoint, but fed the merged map — a linked aura can land
        -- on either unit and selfAura does not say which (see syncSwapSlots).
        syncSwapSlots(settings, spellMap)
        -- After syncSwapSlots, which is what makes swapList this pass's answer.
        syncAuraIcons(settings)
        -- After both slot syncs, so every button either family allocated this
        -- pass is known.
        syncIconMasks()
        -- hide_cd_swipe and hide_cd_text are in this gate because the takeover's
        -- gold swipe and countdown stand in for the icon's own while the aura
        -- lasts, and both settings govern them as they did in 2.13.4.
        -- The font request (private.fontsDirty, latched as fontsOwed) stays
        -- because it is the generic "a setter asked for the gated pass" flag
        -- (patterns.md), and restyleSlotButton is the only route to
        -- ApplyActiveGlow.
        local fonts = fontsOwed
        fontsOwed = false
        if fonts
            or settings.reverse_swipe ~= slotStyleReverse
            or slotTakeoverMoved
            or settings.hide_cd_text ~= slotStyleHideText
            or settings.hide_cd_swipe ~= slotStyleHideSwipe then
            slotStyleReverse = settings.reverse_swipe
            slotTakeoverMoved = false
            slotStyleHideText = settings.hide_cd_text
            slotStyleHideSwipe = settings.hide_cd_swipe
            private.AuraContainer.MarkDirty(name)
        end
        private.AuraContainer.RestyleIfDirty(name, settings)

        -- pandemic_glow: the slot buttons carry native pandemic regions whose
        -- visibility Blizzard drives, so this only carries the style/colour and
        -- the per-spell excludes onto their overlays.  Index-aligned with
        -- slotList by pool index, like the slots themselves.
        private.AuraContainer.SyncPandemic(name, allButtons, slotList,
            settings.pandemic_glow == true, settings)

        -- Settings-driven font pass, gated exactly like the old per-child
        -- styling (patterns.md "fontsDirty"): only when an Options/EditMode
        -- setter raised the flag around this Refresh (or one that returned early).
        if fonts then
            for _, button in pairs(activeButtons) do
                applyButtonFonts(button, settings, timerFontName)
            end
        end

        for spellID, button in pairs(activeButtons) do
            local display = displaySpell(name, spellID)
            refreshButtonContent(button, spellID, settings, display)
            -- Covers newly-acquired buttons and proc_glow_* setting changes;
            -- the live proc transitions come from the glow events below.
            applyProcGlow(button, spellID, settings, display)
        end

        local shouldShow = (getEnabled() or private.isEditMode)
            and private.Anchor.IsVisibleForComponent(name)
        if shouldShow then
            layoutButtons(spellMap, settings, private.Anchor.GetEffectiveAlpha(name))
            container:Show()
        else
            releaseAppendFrames()
            container:Hide()
        end

        local nowCollapsed = tracker.IsCollapsed()
        if nowCollapsed ~= wasCollapsed then
            wasCollapsed = nowCollapsed
            private.Anchor.OnComponentStateChange()
        end
    end

    tracker.ContentLayout = tracker.Refresh

    ---Lightweight alpha sync for anchor inheritance — buttons manage their own
    ---alpha (SetIgnoreParentAlpha), so container alpha does not cascade.
    tracker.SyncAlpha = function()
        if not container then return end
        local effectiveAlpha = private.Anchor.GetEffectiveAlpha(name)
        if auraWrapper then auraWrapper:SetAlpha(effectiveAlpha) end
        if auraWrapperTarget then auraWrapperTarget:SetAlpha(effectiveAlpha) end
        if auraWrapperTargetHelpful then auraWrapperTargetHelpful:SetAlpha(effectiveAlpha) end
        if swapWrapperPlayer then swapWrapperPlayer:SetAlpha(effectiveAlpha) end
        if swapWrapperTarget then swapWrapperTarget:SetAlpha(effectiveAlpha) end
        if swapWrapperTargetHelpful then swapWrapperTargetHelpful:SetAlpha(effectiveAlpha) end
        -- Skipped while a component hook owns the container (override-bar
        -- takeover): the base icons are parked at alpha 0 and must stay there.
        if not (hooks.ownsContainer and hooks.ownsContainer()) then
            local visMode = getSettings().icon_visibility_mode
            for _, button in pairs(activeButtons) do
                applyButtonAlpha(button, effectiveAlpha * (button.cue_visAlpha or 1), visMode)
            end
        end
        for i = 1, lastAppendCount do
            -- Same override/fade rule as placeIconButton's foreign-icon branch.
            local icon = lastAppended[i]
            if not private.Util.IsIconFading(icon) then
                icon:SetAlpha(effectiveAlpha * (private.Util.GetIconAlphaOverride(icon) or 1))
            end
        end
    end

    -- Internal-callback registrations ---------------------------------------
    --
    -- Callback.Register keys on FUNCTION IDENTITY (framework.table.addunique),
    -- so an anonymous closure built inside Initialize can never be taken back
    -- out again.  That is harmless for a component initialized once per session,
    -- but a HOSTED tracker (an Additional Frame) is created, initialized and
    -- thrown away on every profile switch, so each switch would leave one more
    -- permanent registration pointing at a dead tracker — and a dead spells
    -- tracker's Refresh still resolves LIVE state through activeFrames, so the
    -- ghost pass would steal the live frame's foreign icons.
    --
    -- One stable closure per tracker, plus a registered flag, makes
    -- register/unregister exact and idempotent in both directions: a second
    -- Initialize cannot double-register, and Initialize after OnDisable
    -- re-registers rather than leaving the tracker deaf.
    local function onCallbackRefresh()
        tracker.Refresh()
    end
    -- A keybind change redraws keybind text only.  Two cases keep the full
    -- Refresh: routed icons, whose text the collect re-asserts from THIS
    -- tracker's settings after their own tracker wrote it from its own; and the
    -- override bar, whose keybinds and slots are built in its layout.
    local function onKeybindsChanged()
        if lastAppendCount > 0 or (hooks.ownsContainer and hooks.ownsContainer()) then
            tracker.Refresh()
            return
        end
        local settings = getSettings()
        for spellID, button in pairs(activeButtons) do
            applyKeybindText(button, displaySpell(name, spellID), settings,
                private.CDMDataSource.GetIconSource(spellID))
        end
    end
    local callbacksRegistered = false

    -- No combat-transition refreshes.  At PLAYER_REGEN_DISABLED the lockdown has
    -- not started, so a Refresh there redrew the pre-combat state already on
    -- screen, in the pull frame.  On exit, Anchoring's OnLeaveCombat pass runs
    -- ContentLayout -- this Refresh -- for every visible tracker.
    --
    -- OnKeybindsChanged: Util's shared keybind watcher fires it once per burst,
    -- after it has invalidated the keybind cache.  It replaced a watcher per
    -- tracker, each invalidating the cache again and rebuilding it.
    local function registerTrackerCallbacks()
        if callbacksRegistered then return end
        callbacksRegistered = true
        private.Callback.Register("OnCDMSpellsChanged", onCallbackRefresh)
        private.Callback.Register("OnKeybindsChanged", onKeybindsChanged)
    end

    local function unregisterTrackerCallbacks()
        if not callbacksRegistered then return end
        callbacksRegistered = false
        private.Callback.Unregister("OnCDMSpellsChanged", onCallbackRefresh)
        private.Callback.Unregister("OnKeybindsChanged", onKeybindsChanged)
    end

    ---One-shot OnLeaveCombat container hide.  OnDisable cannot hide the
    ---container inside a lockdown, and it used to be the permanent OnLeaveCombat
    ---registration that caught that up (Refresh's disabled branch hides the
    ---container).  That registration is torn down now, so the catch-up is
    ---explicit — same observable behaviour, no permanent listener.
    ---
    ---Reads getSettings() rather than getEnabled(): a HOSTED tracker's settings
    ---row is `private.profile.additional_frames[id]`, and both AF teardown paths
    ---remove that row while this handler is still pending, so getEnabled()'s
    ---`getSettings().enabled` would index nil.  manager.DeleteFrame calls
    ---deactivateFrame(id) (which registers this) and only THEN nils the row;
    ---manager.OnProfileChanged runs its deactivate loop over the OLD ids after
    ---AceDB has already swapped private.profile, so an id absent from the new
    ---profile reads nil too.  The error would land inside
    ---Callback.Trigger("OnLeaveCombat"), which has no pcall, aborting the
    ---dispatch for every handler after this one.  An absent row means the frame
    ---is gone, i.e. not enabled — hide.
    local deferredDisableHide
    deferredDisableHide = function()
        private.Callback.Unregister("OnLeaveCombat", deferredDisableHide)
        local settings = getSettings()
        if container and not (settings and settings.enabled) and not private.isEditMode then
            container:Hide()
        end
    end

    tracker.Initialize = function()
        local host = config.parent
        container = CreateFrame("Frame", config.containerName, host or UIParent)
        if host then
            container:SetAllPoints(host)
        end

        -- Aura-duration spirals: register the restyle fn before any slot can be
        -- created (initSlotButton styles at acquire time), then the container
        -- the slot buttons live in.  The wrapper is a bare positioning anchor —
        -- slot frames are excluded from the container's flow layout and ride
        -- their cells instead — but it still needs a resolvable rect and must
        -- stay shown or its buttons never render.  Levels put the spirals above
        -- each icon's own cooldown swipe (container+4) and below the count /
        -- keybind text overlay (container+14).
        private.AuraContainer.RegisterTracker(name, restyleSlotButton)
        auraWrapper, auraSlots = private.AuraContainer.Create(
            config.containerName .. "_AuraSlots", container)
        auraWrapper:SetAllPoints(container)
        auraWrapper:SetFrameLevel(container:GetFrameLevel() + 5)
        auraSlots:SetFrameLevel(auraWrapper:GetFrameLevel() + 1)

        -- Target twin: SetUnit is per container, so a tracked spell's aura on the
        -- target needs its own.  This is the one that matters for pandemic — a
        -- refreshable aura is usually a DoT, while the player container mostly
        -- sees long-cooldown burst buffs with no refresh window at all.
        -- One per target filter string, each gated (TARGET_HARMFUL_FILTERS).
        auraWrapperTarget, auraSlotsTarget = private.AuraContainer.Create(
            config.containerName .. "_AuraSlotsT", container, "target")
        auraWrapperTarget:SetAllPoints(container)
        auraWrapperTarget:SetFrameLevel(container:GetFrameLevel() + 5)
        auraSlotsTarget:SetFrameLevel(auraWrapperTarget:GetFrameLevel() + 1)
        retargetSlots(auraSlotsTarget, TARGET_HARMFUL)
        auraWrapperTargetHelpful, auraSlotsTargetHelpful = private.AuraContainer.Create(
            config.containerName .. "_AuraSlotsTH", container, "target")
        auraWrapperTargetHelpful:SetAllPoints(container)
        auraWrapperTargetHelpful:SetFrameLevel(container:GetFrameLevel() + 5)
        auraSlotsTargetHelpful:SetFrameLevel(auraWrapperTargetHelpful:GetFrameLevel() + 1)
        retargetSlots(auraSlotsTargetHelpful, TARGET_HELPFUL)

        -- Icon-swap slots: one container per unit, since SetUnit is per container
        -- and a tracked spell's linked aura may land on the player or the target.
        -- Both sit at container+1 so their buttons land at +2 — above the pooled
        -- button (+1) whose base icon they replace, and BELOW that button's own
        -- cooldown swipe (+4) so the swapped icon is still darkened while the spell
        -- is on cooldown, and below the gold aura spirals (+5/+6).  No restyle fn:
        -- these carry a static texture and nothing style-driven.
        swapWrapperPlayer, swapSlotsPlayer = private.AuraContainer.Create(
            config.containerName .. "_SwapPlayer", container)
        swapWrapperPlayer:SetAllPoints(container)
        swapWrapperPlayer:SetFrameLevel(container:GetFrameLevel() + 1)
        swapSlotsPlayer:SetFrameLevel(swapWrapperPlayer:GetFrameLevel())

        swapWrapperTarget, swapSlotsTarget = private.AuraContainer.Create(
            config.containerName .. "_SwapTarget", container, "target")
        swapWrapperTarget:SetAllPoints(container)
        swapWrapperTarget:SetFrameLevel(container:GetFrameLevel() + 1)
        swapSlotsTarget:SetFrameLevel(swapWrapperTarget:GetFrameLevel())
        retargetSlots(swapSlotsTarget, TARGET_HARMFUL)
        swapWrapperTargetHelpful, swapSlotsTargetHelpful = private.AuraContainer.Create(
            config.containerName .. "_SwapTargetH", container, "target")
        swapWrapperTargetHelpful:SetAllPoints(container)
        swapWrapperTargetHelpful:SetFrameLevel(container:GetFrameLevel() + 1)
        swapSlotsTargetHelpful:SetFrameLevel(swapWrapperTargetHelpful:GetFrameLevel())
        retargetSlots(swapSlotsTargetHelpful, TARGET_HELPFUL)

        -- Every target-unit container is re-gated and rebuilt on a target swap
        -- (retargetSlots).  A target's reaction can also flip with no target
        -- change at all (mind control, a neutral NPC turning), and reaction
        -- decides which of the two target filters has a working identity gate;
        -- the player's own flips it just as well (being mind controlled) and
        -- fires UNIT_FACTION for "player" only, which is why Blizzard's
        -- TargetFrame reacts to both units (TargetFrame.lua:200).
        targetWatcher = CreateFrame("Frame")
        targetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
        targetWatcher:RegisterUnitEvent("UNIT_FACTION", "target", "player")
        targetWatcher:SetScript("OnEvent", function()
            retargetSlots(swapSlotsTarget, TARGET_HARMFUL)
            retargetSlots(swapSlotsTargetHelpful, TARGET_HELPFUL)
            retargetSlots(auraSlotsTarget, TARGET_HARMFUL)
            retargetSlots(auraSlotsTargetHelpful, TARGET_HELPFUL)
            for _, handle in pairs(perIconSlots) do
                retargetSlots(handle.containerTarget, TARGET_HARMFUL)
                retargetSlots(handle.containerTargetHelpful, TARGET_HELPFUL)
                retargetSlots(handle.swapContainerTarget, TARGET_HARMFUL)
                retargetSlots(handle.swapContainerTargetHelpful, TARGET_HELPFUL)
            end
        end)

        registerTrackerCallbacks()

        private.CustomSpells.OnEnable(name)

        -- rotation_highlight: register the pooled-button map so the Assisted
        -- Combat marching-ants overlay follows our buttons.
        private.AssistedHighlight.RegisterButtons(name, getSettings, function()
            return activeButtons
        end)

        -- SPELL_UPDATE_COOLDOWN (+ extraWatcherEvents): per-event content pass,
        -- coalesced to one pass per rendered frame via the swipeDirty OnUpdate.
        spellWatcher = CreateFrame("Frame")
        -- Proc glows are re-derived only when a glow event actually fired:
        -- SPELL_UPDATE_COOLDOWN drives this pass every rendered frame in combat,
        -- and an IsSpellOverlayed query per button per frame is pure waste.
        local procDirty = false
        local function onSwipeUpdate(self)
            swipeDirty = false
            self:SetScript("OnUpdate", nil)
            if not getEnabled() and not private.isEditMode then return end
            local doProc = procDirty
            procDirty = false
            local settings = getSettings()
            -- Component seam: e.g. the override-bar content-only pass.  Runs
            -- before the re-alpha loop below, which would otherwise undo the
            -- alpha-0 park the override takeover applies to the base icons.
            if hooks.postSwipeUpdate and hooks.postSwipeUpdate(settings) then
                return
            end
            local effectiveAlpha = private.Anchor.GetEffectiveAlpha(name)
            local visSetChanged = false
            -- Same rule as layoutButtons: only the HIDE modes change grid
            -- membership.  A fade mode at faded_alpha 0 also crosses the > 0
            -- line on every cooldown transition, and re-laying out for it would
            -- be a relayout storm for a set that never changed.
            local hideMode = settings.icon_visibility_mode == 2
                or settings.icon_visibility_mode == 4
            for spellID, button in pairs(activeButtons) do
                local wasVisible = (button.cue_visAlpha or 1) > 0
                local display = displaySpell(name, spellID)
                refreshButtonContent(button, spellID, settings, display)
                private.CDMAlerts.OnCooldownStateChanged(spellID, button.cue_onCooldown, button)
                if hideMode and ((button.cue_visAlpha or 1) > 0) ~= wasVisible then
                    visSetChanged = true
                end
                applyButtonAlpha(button, effectiveAlpha * (button.cue_visAlpha or 1),
                    settings.icon_visibility_mode)
                if doProc then
                    applyProcGlow(button, spellID, settings, display)
                end
            end
            if visSetChanged then
                -- The visible set changed (icon_visibility_mode hide modes):
                -- re-run the layout so grid slots and container size track it —
                -- in combat too, the frames are unprotected.  Gated on an
                -- actual membership change, never per-event.
                tracker.Refresh()
            end
        end
        spellWatcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        spellWatcher:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        spellWatcher:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
        -- Drives the usability tint in refreshButtonContent.  Registered by the
        -- factory rather than per component: every instance draws spell icons,
        -- and SPELL_UPDATE_COOLDOWN alone never fires for a spell whose only
        -- change is that it became castable.  Blizzard registers the pair
        -- together for the same reason (CooldownViewer.lua:2154).
        spellWatcher:RegisterEvent("SPELL_UPDATE_USABLE")
        -- Drives the out-of-range half of that tint.  Fires only for spells
        -- ensureRangeCheck has registered, so it is silent on a character whose
        -- tracked spells are all self-cast.
        spellWatcher:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")
        -- Drives the cast-count text; Blizzard refreshes it on this event
        -- (CooldownViewer.lua:2162), and a stack change need not move a cooldown.
        spellWatcher:RegisterEvent("SPELL_UPDATE_USES")
        -- No UNIT_AURA tick: it existed solely so a buff dropping out of combat
        -- refreshed the two GetAuraState consumers (the hide-when-ready set and
        -- the hide_active_swipe yield) before the next cast.  Both are gone, and
        -- every state these buttons draw now moves on SPELL_UPDATE_COOLDOWN.
        for i = 1, #extraWatcherEvents do
            spellWatcher:RegisterEvent(extraWatcherEvents[i])
        end
        spellWatcher:SetScript("OnEvent", function(_, event, spellID, inRange, checksRange)
            if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
                or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
                procDirty = true
            elseif event == "SPELL_RANGE_CHECK_UPDATE" then
                -- Blizzard's own reading of this payload (CooldownViewer.lua:829):
                -- checksRange false means no check was made (no target), which is
                -- NOT out of range.  Written to shared state, so every tracker's
                -- watcher stores the same value -- idempotent, and cheaper than
                -- routing one watcher's events to the others.
                if checksRange == true and inRange == false then
                    spellOutOfRange[spellID] = true
                else
                    spellOutOfRange[spellID] = nil
                end
            end
            if not swipeDirty then
                swipeDirty = true
                spellWatcher:SetScript("OnUpdate", onSwipeUpdate)
            end
        end)

        if hooks.afterInitialize then hooks.afterInitialize() end

        tracker.Refresh()
    end

    tracker.OnEnable = function()
        if hooks.onEnable then hooks.onEnable() end
        registerTrackerCallbacks()
        if targetWatcher then
            targetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
            targetWatcher:RegisterUnitEvent("UNIT_FACTION", "target", "player")
        end
        if spellWatcher then
            spellWatcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            spellWatcher:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
            spellWatcher:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
            spellWatcher:RegisterEvent("SPELL_UPDATE_USABLE")
            spellWatcher:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")
            spellWatcher:RegisterEvent("SPELL_UPDATE_USES")
            for i = 1, #extraWatcherEvents do
                spellWatcher:RegisterEvent(extraWatcherEvents[i])
            end
        end
        -- Symmetric with OnDisable's Tooltip.Release: the module tracks frames
        -- in an array Apply appends to, and a released button is gone from it
        -- for good otherwise (the pool is never rebuilt, so acquireButton's
        -- creation-time bind never runs again for it).
        for i = 1, #allButtons do
            applyButtonTooltip(allButtons[i])
        end
        if private.CustomSpells then
            private.CustomSpells.OnEnable(name)
        end
        if container and not InCombatLockdown() then
            container:Show()
            tracker.Refresh()
        end
    end

    ---Undo everything Initialize set up that would otherwise outlive this
    ---tracker:
    ---  * the two internal-callback registrations (keybind changes arrive
    ---    through one of them, so a torn-down tracker stops hearing them at
    ---    once -- a ghost tracker's Refresh resolves LIVE state through
    ---    activeFrames and would steal the live frame's foreign icons);
    ---  * both watcher frames — events AND the swipe coalescer's OnUpdate
    ---    script, which `UnregisterAllEvents` does not touch, plus its
    ---    pending-work flag so an in-flight OnUpdate cannot run against a
    ---    torn-down tracker;
    ---  * every AuraContainer it created, shared and per-icon, which otherwise
    ---    keeps parsing auras for the rest of the session;
    ---  * every pooled button's Tooltip binding, which otherwise stays in the
    ---    module's `tracked` array and is walked on every combat transition.
    ---
    ---The name-keyed registries (AuraContainer.RegisterTracker,
    ---AssistedHighlight.RegisterButtons) are deliberately left alone — they
    ---store one entry per component NAME, so a rebuilt tracker overwrites its
    ---predecessor instead of accumulating, and clearing them here would break
    ---the deactivate-all-then-activate-all order AdditionalFrameManager uses.
    tracker.OnDisable = function()
        if hooks.onDisable then hooks.onDisable() end
        if private.CustomSpells then
            private.CustomSpells.OnDisable(name)
        end
        unregisterTrackerCallbacks()
        -- What Refresh's disabled branch used to do on the next combat
        -- transition, now that no such transition reaches this tracker.
        releaseAppendFrames()
        if container then
            if InCombatLockdown() then
                private.Callback.Register("OnLeaveCombat", deferredDisableHide)
            else
                container:Hide()
            end
        end
        for i = 1, #allButtons do
            private.Tooltip.Release(allButtons[i])
        end
        if spellWatcher then
            spellWatcher:UnregisterAllEvents()
            -- UnregisterAllEvents leaves an OnUpdate script installed, and the
            -- coalescer only ever removes its own from inside itself — so a
            -- pass armed in the frame this tracker was torn down would still
            -- tick.  Flag and script go together: the script alone would leave
            -- swipeDirty latched true and the coalescer could never re-arm
            -- after a disable/enable cycle.
            spellWatcher:SetScript("OnUpdate", nil)
            swipeDirty = false
        end
        if targetWatcher then targetWatcher:UnregisterAllEvents() end
        -- The aura engine.  `AuraContainer.Create` enables every container it
        -- builds and nothing here ever switched them back off: clearSlotTopology
        -- is reachable only from syncAuraSlots, i.e. from a Refresh a torn-down
        -- tracker never receives.  An enabled container keeps parsing on every
        -- UNIT_AURA for its unit (ParseAllAuras early-returns only when
        -- disabled), so a hosted tracker — rebuilt on every profile switch —
        -- would leave one more live set behind each time, six shared plus six
        -- per icon under the per-icon topology.  Engine-side, so Lua memory
        -- sampling never shows it.
        --
        -- Not combat-guarded: SetEnabled is a plain Lua mixin (there is no
        -- InCombatLockdown anywhere in Blizzard_AuraContainer/), it self-guards
        -- on an unchanged value, and the UpdateAllAuras it ends in is the same
        -- call Blizzard's own OnHide_Intrinsic makes every time these
        -- containers' parent hides — which the anchor visibility pass does in
        -- combat routinely.
        if auraSlots then
            private.AuraContainer.Suspend(auraSlots)
            private.AuraContainer.Suspend(auraSlotsTarget)
            private.AuraContainer.Suspend(auraSlotsTargetHelpful)
            private.AuraContainer.Suspend(swapSlotsPlayer)
            private.AuraContainer.Suspend(swapSlotsTarget)
            private.AuraContainer.Suspend(swapSlotsTargetHelpful)
            for _, handle in pairs(perIconSlots) do
                private.AuraContainer.Suspend(handle.container)
                private.AuraContainer.Suspend(handle.containerTarget)
                private.AuraContainer.Suspend(handle.containerTargetHelpful)
                private.AuraContainer.Suspend(handle.swapContainer)
                private.AuraContainer.Suspend(handle.swapContainerTarget)
                private.AuraContainer.Suspend(handle.swapContainerTargetHelpful)
            end
        end
    end

    tracker.GetComponentName = function()
        return name
    end

    tracker.GetWantsContentWidth = function()
        local settings = getSettings()
        -- Vertical layouts size their width from content (columns), matching
        -- the shared viewer-layout path.
        if (settings.layout_direction or "horizontal") == "vertical" then return true end
        local mode = settings.frame_size_mode or "max_width"
        if mode == "max_per_row" then return true end
        if mode == "max_width" and settings.icon_size and settings.icon_size > 0 then return true end
        return false
    end

    ---Returns true when there is nothing to display.
    tracker.IsCollapsed = function()
        if hooks.isCollapsed then
            local v = hooks.isCollapsed()
            if v ~= nil then return v end
        end
        return lastSpellCount == 0 and lastAppendCount == 0
    end

    ---Estimate component size from profile settings and the last known counts.
    ---Under the hide visibility modes (2/4) the estimate uses the last laid-out
    ---visible count so it agrees with the actual container size.
    tracker.GetComponentSize = function()
        if hooks.getComponentSizeOverride then
            local w, h = hooks.getComponentSizeOverride()
            if w then return w, h end
        end
        local settings = getSettings()
        local spellCount = lastSpellCount + lastAppendCount
        if spellCount == 0 and not private.isEditMode then return 0, 0 end
        local count = (spellCount == 0 and private.isEditMode) and 1 or spellCount
        local visMode = settings.icon_visibility_mode or 1
        if (visMode == 2 or visMode == 4) and not private.isEditMode then
            count = lastVisibleCount
            if count == 0 then return 1, 1 end
        end
        local _, _, _, _, _, w, h = computeGridGeometry(settings, count, name)
        return w, h
    end

    if hooks.getForceVisible then
        tracker.GetForceVisible = hooks.getForceVisible
    end

    ---@type icontracker_ctx
    local ctx = {
        GetContainer = function() return container end,
        SetContainerSize = setContainerSize,
        activeButtons = activeButtons,
        ---Alpha a pooled button AND the per-icon aura wrapper riding it, so a cue
        ---the engine shows (spiral, pandemic border, active border) cannot outlive
        ---the icon it belongs to.  The override-bar takeover parks base icons
        ---through this rather than calling SetAlpha itself.
        ---
        ---Always instant (mode nil): a park is a takeover, not an
        ---`icon_visibility_mode` transition, and it also has to cancel a fade
        ---left in flight — otherwise the fade finishes and un-parks the icon.
        SetButtonAlpha = function(button, alpha)
            applyButtonAlpha(button, alpha, nil)
        end,
    }

    return tracker, ctx
end

---@type icontrackerfacade
private.IconTracker = {
    CreateTracker = createTracker,
    ComputeGridGeometry = computeGridGeometry,
    PlaceGrid = placeGrid,
    BindCoveredMask = bindCoveredIconMask,
}

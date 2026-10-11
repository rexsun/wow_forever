--[[
    OutboundBuffTracker component.
    Tracks buffs the player has applied on party/raid members and renders one
    horizontal bar per (ally, aura): recipient name, spell icon, remaining
    duration.  Default tracked spell is Prescience (410089).

    12.1 MIGRATION (Phase 6 of issue #40).  The old engine read
    `C_UnitAuras.GetUnitAuraBySpellID(unit, spellID)` per group unit on
    UNIT_AURA and drove its own StatusBars from `duration`/`expirationTime`.
    That call returns real data only for auras carrying the "aura never secret"
    flag — raid buffs and class self-buffs.  A buff the player puts on an ALLY
    is not one of those, so the read returned nil for every spell this tracker
    exists for and the bars blanked for the length of a pull.

    The replacement is N AuraContainers, ONE PER ALLY (`SetUnit(unit)` — unit is
    per container, and per-group SetUnit is not shipping before 12.1.5).  Each
    container holds a single aura group filtered
    `HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY`, whose `PLAYER` token is what makes
    this an OUTBOUND tracker: it restricts the group to auras cast by the
    player, so the old `aura.sourceUnit == "player"` read is not replaced, it is
    deleted.  Duration and icon are bound (`SetDurationBar` / `SetDurationText` /
    `SetIcon`) and driven by the engine — no aura value crosses into Lua, so the
    tracker works while auras are secret.

    Containers are pooled BY INDEX and repointed with `SetUnit` each Refresh, not
    allocated per raid slot: a 40-slot pool would mean 40 frame providers for the
    5 units a party actually has.  The per-index `initializeFrame` closure
    therefore cannot capture the unit — recipient identity is looked up through
    `blockOfButton` at restyle time instead.

    What the engine cannot give back:
      - `sort_order` "remaining_*" sorts WITHIN each ally's container
        (AuraContainerSortMethod.ExpirationOnly); across allies the order is the
        container chain.  A global remaining-time sort would need the remaining
        times, which are secret.  "name_asc" is exact — the chain is ours.
      - `max_bars` caps frames PER ALLY (`SetAuraGroupMaxFrameCount`); the live
        total is secret, so a global cap has nothing to count.
      - `spell_colors` is inert: which button shows which spell is decided by the
        engine and that binding is secret.  Same limitation the groups engine has
        on BuffTrackerBars.

    Events: GROUP_ROSTER_UPDATE / PLAYER_ENTERING_WORLD / UNIT_NAME_UPDATE — the
    roster, not the auras.  UNIT_AURA is gone; the engine owns aura deltas.

    Evidence:
      AuraContainer:SetUnit / AddAuraGroup / SetAuraGroupMaxFrameCount / SetAuraGroupSortMethod — Blizzard_CustomAuraContainer.lua
      CustomAuraButtonSharedMixin:SetIcon / SetDurationBar / SetDurationText / SetApplicationCount — Blizzard_CustomAuraButton.lua
      AuraUtil filter tokens (PLAYER = cast by player, INCLUDE_NAME_PLATE_ONLY) — AuraUtil.lua:279
      See .context/patterns-auracontainer.md and .context/api.md.
--]]

local _
---@type string, private
local addonName, private = ...
local LAC = LibStub("LibAuraContainer-1.0")

---@class private : table
---@field OutboundBuffTracker outboundbufftracker

---@class outboundbufftracker : component

---@type outboundbufftracker
---@diagnostic disable-next-line: missing-fields
local comp = {}

comp.name = "OutboundBuffTracker"

-- Keep OBT anchored to its configured parent (BuffTrackerBars) even when
-- the parent has no visible bars. Otherwise layoutRecursive's collapsed-
-- parent fallback walks past BTB, inherits BTB's UIParent anchor, and
-- teleports OBT to BTB's slot — visually reading as "tracker disappeared"
-- when a player buff is routed to an Additional Frame and BTB empties.
-- OBT has its own independent content (Prescience bars etc.) so staying
-- anchored to a 0-height parent frame at a known position is correct.
comp.StaysAnchoredWhenParentCollapsed = true

---------------------------------------------------------------------------
-- Forward declarations (Lua 5.1 upvalue safety)
---------------------------------------------------------------------------
local restyleButton
local itemDims

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local MAX_RAID_SIZE = 40 -- raid1..raid40 scan bound for roster enumeration

---`PLAYER` restricts the group to auras the player cast — the whole outbound
---semantic, applied engine-side.  `INCLUDE_NAME_PLATE_ONLY` is an INCLUDE flag
---(AuraUtil.lua:279): omitting it silently drops nameplate-flagged auras, and
---Blizzard adds it for every friendly unit.
local OUTBOUND_FILTER = "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY"

---Neutralizes a container's group without removing it — neither engine has a
---public group-removal API, so an empty include map is the sanctioned off
---switch (same contract AuraBarTracker uses for its idle engine).
local EMPTY_MAP = {}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

---Component/anchor-facing frame.  Addon-owned rect: the aura containers hang
---inside it single-point anchored so their SECRET engine-written size never
---propagates (Core/AuraContainer.lua "two-frame construction" — the live
---incident that note records was this component's percent-width anchor).
---@type frame?
local wrapper

---Container pool, indexed 1..N and repointed by `SetUnit` each Refresh.
---@type {container: frame, unit: string?, displayName: string?, classToken: string?, buttons: table<frame, true>, maxFrames: number?, sortMethod: number?, sortDirection: number?}[]
local blocks = {}

---Number of pool entries currently bound to a live unit; entries past this are
---hidden and hold the never-matching filter.
local activeBlocks = 0

---Reverse map for the restyle sweep: an `initializeFrame` closure captures the
---pool INDEX, but the recipient behind that index changes with the roster, so
---the name/class are resolved from the block at restyle time, not at init.
---@type table<frame, table>
local blockOfButton = setmetatable({}, {__mode = "k"})

---Roster event driver.
---@type frame?
local eventFrame

---Ordered unit tokens for the current roster (chain order).
---@type string[]
local orderedUnits = {}

---Tracked spell count and reserved row count, for IsCollapsed / GetComponentSize.
local spellCount = 0
local rowCount = 0

---Last collapsed state, for anchor state-change detection.
local wasCollapsed = true

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function getSettings()
    return private.profile.components[comp.name]
end

local function getEnabled()
    return getSettings().enabled
end

---Enumerate the units this tracker renders a block for.  Raid tokens already
---include the player; party tokens do not, so "player" is prepended there.
---Solo keeps the player so the tracker is configurable outside a group.
---`filter_self_cast` drops whichever token IS the player.
---@return string[]
local function getGroupUnits()
    local units = {}
    local settings = getSettings()
    local filterSelf = settings.filter_self_cast
    local inRaid = IsInRaid(LE_PARTY_CATEGORY_HOME) or IsInRaid(LE_PARTY_CATEGORY_INSTANCE)
    local inGroup = IsInGroup(LE_PARTY_CATEGORY_HOME) or IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    if inRaid then
        for i = 1, MAX_RAID_SIZE do
            local unit = "raid" .. i
            if UnitExists(unit) and not (filterSelf and UnitIsUnit(unit, "player")) then
                units[#units + 1] = unit
            end
        end
    elseif inGroup then
        if not filterSelf then units[#units + 1] = "player" end
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then units[#units + 1] = unit end
        end
    elseif not filterSelf then
        units[#units + 1] = "player"
    end

    -- "name_asc" is the one sort mode the engine cannot do for us and we can do
    -- exactly: the chain order is ours, and the recipient name is a plain value.
    if settings.sort_order == "name_asc" then
        table.sort(units, function(a, b)
            return (UnitName(a) or a) < (UnitName(b) or b)
        end)
    end
    return units
end

---@return table<number, true> spellMap, number count
local function buildSpellMap()
    local map = {}
    local count = 0
    local tracked = getSettings().tracked_spells or {}
    for i = 1, #tracked do
        local id = tracked[i]
        if type(id) == "number" and id > 0 and not map[id] then
            map[id] = true
            count = count + 1
        end
    end
    return map, count
end

---Group sort for the "remaining" modes.  Applies WITHIN one ally's container
---only — see the file header.
---@param settings table
---@return number sortMethod, number sortDirection
local function resolveSort(settings)
    local order = settings.sort_order or "remaining_asc"
    if order == "remaining_desc" then
        return LAC.SortMethod.ExpirationOnly, LAC.SortDirection.Reverse
    elseif order == "remaining_asc" then
        return LAC.SortMethod.ExpirationOnly, LAC.SortDirection.Normal
    end
    return LAC.SortMethod.Default, LAC.SortDirection.Normal
end

---------------------------------------------------------------------------
-- Layout geometry
---------------------------------------------------------------------------

---Item geometry.  `bar_width` is the FULL item width (icon INSIDE it), percent
---anchor inheritance replaces it, and `bar_content == "IconOnly"` collapses to
---`icon_size` only when `collapse` is on.
---@param settings table
---@return number itemWidth, number itemHeight, number barLeftOffset
itemDims = function(settings)
    local iconSize = settings.icon_size or 20
    local barContent = settings.bar_content or "IconAndName"
    local width = settings.bar_width or 220
    local avail = private.Anchor.GetInheritedWidth(comp.name)
    if avail and avail > 0 then width = avail end
    if barContent == "IconOnly" and settings.collapse then width = iconSize end
    local iconHidden = (barContent == "NameOnly" or barContent == "BarOnlyNoName")
    local barLeft = iconHidden and 0 or (iconSize + (settings.icon_offset or 2))
    local height = private.Util.ComputeBarItemHeight(barContent,
        settings.bar_height or 20, iconSize)
    return width, height, barLeft
end

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

---Single-line stack contract, mirroring AuraBarTracker: `layout_direction` →
---axis, `layout_alignment` → anchored edge (falling back to `growth_direction`
---when "center").  `growBack` means the run advances UP / LEFT.
---@param settings table
---@return boolean vertical, boolean growBack, string anchorPt
local function barFlow(settings)
    local vertical = (settings.layout_direction or "vertical") ~= "horizontal"
    local alignment = settings.layout_alignment or "center"
    local growDir = settings.growth_direction or "down"
    if vertical then
        local growUp = (alignment == "bottom")
            or (alignment ~= "top" and growDir == "up")
        return true, growUp, growUp and "BOTTOM" or "TOP"
    end
    local growLeft = (alignment == "right")
        or (alignment ~= "left" and growDir == "left")
    return false, growLeft, growLeft and "RIGHT" or "LEFT"
end

---Apply the single-line flow contract to ONE aura container; bars never wrap.
---The pin corner and the flow origin must MATCH — elements are anchored at the
---flow origin, so a mismatched pin places the block at a secret offset.
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
    c:SetFlowLayoutMaximumLineSize(nil)
    c:SetFlowLayoutPadding(0, 0, 0, 0)
    return anchorPt
end

---Chain the per-ally blocks into one run.
---
---The chain is an anchor, not an estimate: `OnLayoutComplete` sizes each
---container to its own VISIBLE block, so anchoring block N's flow origin to
---block N-1's trailing edge abuts them exactly and the seam tracks the live
---aura count.  The rect is secret to Lua but the anchor resolves engine-side,
---so nothing here reads it.  A block with no active aura collapses to zero
---extent and the next one closes up on its own.
---@param settings table
local function chainBlocks(settings)
    local anchorPt
    for i = 1, #blocks do
        anchorPt = applyContainerFlow(blocks[i].container, settings)
    end
    if not anchorPt then return end

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

    local previous
    for i = 1, activeBlocks do
        local c = blocks[i].container
        c:ClearAllPoints()
        if previous then
            c:SetPoint(anchorPt, previous, trailingPt, dx, dy)
        else
            c:SetPoint(anchorPt, wrapper, anchorPt)
        end
        previous = c
    end
end

---------------------------------------------------------------------------
-- Button construction / restyle
---------------------------------------------------------------------------

---@param button frame
---@param settings table
local function applyBarGeometry(button, settings)
    local iconSize = settings.icon_size or 20
    local barContent = settings.bar_content or "IconAndName"
    local w, h, barLeft = itemDims(settings)
    button:SetSize(w, h)

    if button.cue_Icon then
        button.cue_Icon:ClearAllPoints()
        button.cue_Icon:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT",
            settings.icon_offset_x or 0, settings.icon_offset_y or 0)
        button.cue_Icon:SetSize(iconSize, iconSize)
        button.cue_Icon:SetTexCoord(private.Util.GetIconZoomCoords(iconSize, iconSize))
        button.cue_Icon:SetShown(barContent ~= "NameOnly" and barContent ~= "BarOnlyNoName")
    end
    if button.cue_Bar then
        button.cue_Bar:ClearAllPoints()
        button.cue_Bar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", barLeft, 0)
        button.cue_Bar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        button.cue_Bar:SetHeight(settings.bar_height or 20)
        button.cue_Bar:SetShown(barContent ~= "IconOnly")
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

---Recipient name text + color.  `cue_Name` is NOT bound to `SetSpellName` — the
---name a user wants here is the ALLY's, which is a plain value we own per
---container, not an aura field.
---@param button frame
---@param settings table
local function applyRecipient(button, settings)
    if not button.cue_Name then return end
    local block = blockOfButton[button]
    button.cue_Name:SetText(block and block.displayName or "")

    local source = settings.name_color_source or "class"
    if source == "class" and block and block.classToken then
        local c = C_ClassColor.GetClassColor(block.classToken)
        if c then
            button.cue_Name:SetTextColor(c.r, c.g, c.b)
            return
        end
    end
    local static = settings.name_color_static or {1, 1, 1, 1}
    button.cue_Name:SetTextColor(static[1] or 1, static[2] or 1, static[3] or 1)
end

---@param button frame
---@param settings table
---Settings the dirty-flag restyle pass is the only writer of.  A change to
---any of them must reach the buttons through MarkDirty, so Refresh compares
---them itself instead of relying on every setter to raise private.fontsDirty.
---@type string[]
local RESTYLE_KEYS = {
    "bar_width", "bar_height", "icon_size", "icon_offset",
    "icon_offset_x", "icon_offset_y", "collapse", "show_timer",
    "bar_content", "bar_fill_color",
}

---Last values of RESTYLE_KEYS seen by Refresh.
---@type table<string, any>
local lastRestyleGeom = {}

restyleButton = function(button, settings)
    private.AuraContainer.ApplyTooltip(button, settings)
    applyBarGeometry(button, settings)

    if button.cue_Bar then
        -- `spell_colors` is deliberately not consulted: which button shows which
        -- spell is engine-decided and secret under groups.
        local fc = settings.bar_fill_color or {0.25, 0.78, 0.92, 1}
        button.cue_Bar:SetStatusBarColor(fc[1], fc[2], fc[3], fc[4] or 1)
    end

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
        private.Util.ApplyFontProfile(button.cue_Count, settings.stacks_font,
            button.cue_Icon or button)
    end

    applyRecipient(button, settings)
end

---Build the `initializeFrame` closure for pool entry `index`.  Captured once at
---AddAuraGroup time and never replaced, which is exactly why it captures the
---INDEX and not the unit — the unit behind an index changes with the roster.
---@param index number
---@return function
local function makeInit(index)
    return function(button)
        local s = getSettings()
        local block = blocks[index]

        -- Icon texture.  Size/position come from applyBarGeometry; the flow
        -- layout uses the button's NATURAL size and an unsized button renders
        -- nothing (patterns-auracontainer.md).
        button.cue_Icon = button:CreateTexture(nil, "ARTWORK")
        button:SetIcon(button.cue_Icon)

        -- Font template REQUIRED pre-bind: the bind pushes text immediately and
        -- a font-less SetText errors "Font not set".
        button.cue_TextLayer = private.AuraContainer.CreateTextLayer(button)
        button.cue_Count = button.cue_TextLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        button.cue_Count:SetPoint("BOTTOMRIGHT", button.cue_Icon, "BOTTOMRIGHT", -2, 2)
        button:SetApplicationCount(button.cue_Count)

        button.cue_Bar = CreateFrame("StatusBar", nil, button)
        -- SOLID fill, not a gradient: bar_fill_color is applied with
        -- SetStatusBarColor, which TINTS the texture.
        button.cue_Bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        button.cue_Bar:SetMinMaxValues(0, 1)
        button.cue_Bar:SetValue(1)
        button:SetDurationBar(button.cue_Bar,
            { direction = Enum.StatusBarTimerDirection.RemainingTime })

        button.cue_Bg = button:CreateTexture(nil, "BACKGROUND")
        button.cue_Bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
        button.cue_Bg:SetAllPoints(button.cue_Bar)

        -- Name / timer live INSIDE the bar frame: a child frame draws above all
        -- of its parent's regions regardless of draw layer, so a FontString on
        -- the button would sit behind the fill.
        button.cue_Name = button.cue_Bar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        button.cue_Name:SetPoint("LEFT", button.cue_Bar, "LEFT", 5, 0)

        button.cue_Timer = button.cue_Bar:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
        button.cue_Timer:SetPoint("RIGHT", button.cue_Bar, "RIGHT", -5, 0)
        button:SetDurationText(button.cue_Timer, {})

        blockOfButton[button] = block
        block.buttons[button] = true

        private.AuraContainer.TrackButton(comp.name, button)
        restyleButton(button, s)
    end
end

---Push the current recipient identity onto every button of every live block.
---
---Buttons are tainted-locked while auras are secret, exactly as
---`AuraContainer.RestyleIfDirty` documents; the caller gates on that.  Roster
---changes in combat are rare; the combat-exit layout pass (Anchoring's
---OnLeaveCombat, which runs ContentLayout = Refresh) catches up a shown tracker,
---and catchUpAfterCombat a hidden one.
---@param settings table
local function applyRecipients(settings)
    for i = 1, #blocks do
        for button in pairs(blocks[i].buttons) do
            applyRecipient(button, settings)
        end
    end
end

---------------------------------------------------------------------------
-- Pool
---------------------------------------------------------------------------

---@param index number
---@return table
local function acquireBlock(index)
    local block = blocks[index]
    if block then return block end
    block = {
        container = private.AuraContainer.CreateContainer(
            "CUE_OutboundBuffTracker_Block" .. index .. "_Aura", wrapper),
        buttons = {},
    }
    blocks[index] = block
    return block
end

---------------------------------------------------------------------------
-- Sync
---------------------------------------------------------------------------

---Show each block only when it has an ally.  `SetShown` on our own container is
---unrestricted, so unlike `Refresh` this keeps working in combat.
---
---No identity-gate guard here, unlike the target blocks in AuraIconTracker: this
---tracker's units are only ever `player` / `partyN` / `raidN` and its filter is
---HELPFUL, which is exactly the case 12.1.0.69465 made unconditional
---(`Blizzard_AuraContainerUtil.lua:29`).  The empty map an unused block gets from
---`SyncGroup` is therefore a real off switch again.
local function syncBlockVisibility()
    for i = 1, #blocks do
        blocks[i].container:SetShown(orderedUnits[i] ~= nil)
    end
end

local function syncBlocks(settings)
    local spellMap
    spellMap, spellCount = buildSpellMap()
    wipe(orderedUnits)
    if spellCount > 0 then
        for _, unit in ipairs(getGroupUnits()) do
            orderedUnits[#orderedUnits + 1] = unit
        end
    end
    activeBlocks = #orderedUnits

    local layoutOpts = buildLayoutOpts(settings)
    local sortMethod, sortDirection = resolveSort(settings)
    local maxFrames = (settings.overflow_hide ~= false)
        and (settings.max_bars or 8) or math.huge

    local needed = math.max(activeBlocks, #blocks)
    for i = 1, needed do
        local block = acquireBlock(i)
        local unit = orderedUnits[i]
        local groupKey = comp.name .. "_u" .. i

        if unit then
            if block.unit ~= unit then
                block.container:SetUnit(unit)
                block.unit = unit
            end
            block.displayName = UnitName(unit) or unit
            _, block.classToken = UnitClass(unit)
        else
            block.displayName = nil
            block.classToken = nil
        end

        -- Cached, not rebuilt per pass: SyncGroup only consumes it on the first
        -- AddAuraGroup, and ContentLayout runs this on every anchor layout.
        if not block.initFn then block.initFn = makeInit(i) end
        private.AuraContainer.SyncGroup(block.container, groupKey, OUTBOUND_FILTER,
            unit and spellMap or EMPTY_MAP, block.initFn, layoutOpts)
        -- Both setters re-mark AuraFrameAssignments dirty every call
        -- (SetAuraGroupSortMethod unconditionally), so they are guarded here the
        -- same way SyncGroup guards its own engine calls.
        if block.container:HasAuraGroup(groupKey) then
            if block.maxFrames ~= maxFrames then
                block.maxFrames = maxFrames
                block.container:SetAuraGroupMaxFrameCount(groupKey, maxFrames)
            end
            if block.sortMethod ~= sortMethod or block.sortDirection ~= sortDirection then
                block.sortMethod, block.sortDirection = sortMethod, sortDirection
                block.container:SetAuraGroupSortMethod(groupKey, sortMethod, sortDirection)
            end
        end
    end
    syncBlockVisibility()

    -- Reserved rows for the anchor box.  The live count is secret, so this is
    -- the tracker's CEILING: one row per ally per tracked spell, clamped by the
    -- user's own cap when overflow_hide is on.
    rowCount = activeBlocks * spellCount
    if settings.overflow_hide ~= false then
        rowCount = math.min(rowCount, settings.max_bars or 8)
    end
end

---------------------------------------------------------------------------
-- Event handler
---------------------------------------------------------------------------

---A roster or name change that lands mid-fight is lost to Refresh's combat bail,
---and the combat-exit layout pass runs ContentLayout (Refresh) only for a
---tracker shown then: one hidden by a rule or its parent kept the old
---recipients.  One-shot, registered only by such an event, never by an
---in-combat layout pass, so an ordinary fight costs nothing.
local catchUpAfterCombat
catchUpAfterCombat = function()
    private.Callback.Unregister("OnLeaveCombat", catchUpAfterCombat)
    comp.Refresh()
end

local function onEvent()
    if InCombatLockdown() then
        private.Callback.Register("OnLeaveCombat", catchUpAfterCombat)
    end
    comp.Refresh()
end

---------------------------------------------------------------------------
-- Component interface
---------------------------------------------------------------------------

function comp.Initialize()
    wrapper = CreateFrame("Frame", "CUE_OutboundBuffTracker", UIParent)
    wrapper:SetSize(220, 20)

    private.AuraContainer.RegisterTracker(comp.name, restyleButton)

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", onEvent)
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("UNIT_NAME_UPDATE")

    -- No combat-transition refreshes: see AuraIconTracker's
    -- registerTrackerCallbacks.  Anchoring's OnLeaveCombat pass runs
    -- ContentLayout, which is this Refresh; onEvent adds a one-shot catch-up
    -- when a roster change arrived mid-fight.

    comp.Refresh()
end

function comp.GetFrame()
    return wrapper
end

function comp.Refresh()
    if not wrapper then return end

    local settings = getSettings()

    if not getEnabled() and not private.isEditMode then
        wrapper:SetAlpha(0)
        if not InCombatLockdown() then wrapper:Hide() end
        return
    end

    -- AuraContainer layout API calls are combat-restricted; the combat-exit pass
    -- (and catchUpAfterCombat, for a roster change) re-runs this.  Alpha is not
    -- protected, so visibility still tracks.
    if InCombatLockdown() then
        -- The combat-exit pass re-runs this without the font pass, so a font
        -- edited mid-fight goes on the persistent restyle flag now.
        if private.fontsDirty then private.AuraContainer.MarkDirty(comp.name) end
        comp.SyncAlpha()
        return
    end

    syncBlocks(settings)
    chainBlocks(settings)

    -- Bridge the Options/EditMode font-setter contract (patterns.md
    -- "fontsDirty") into the AuraContainer dirty-restyle path.  The geometry
    -- keys restyleButton owns arrive the same way, so a setter that forgets to
    -- raise the flag writes the profile and changes nothing until a /reload —
    -- detect a move here rather than trusting every call site.
    local geomChanged = false
    for i = 1, #RESTYLE_KEYS do
        local k = RESTYLE_KEYS[i]
        if lastRestyleGeom[k] ~= settings[k] then
            lastRestyleGeom[k] = settings[k]
            geomChanged = true
        end
    end
    if private.fontsDirty or geomChanged then
        private.AuraContainer.MarkDirty(comp.name)
    end
    private.AuraContainer.RestyleIfDirty(comp.name, settings)

    -- Recipient identity is roster state, not settings, so it is pushed on every
    -- pass rather than through the dirty flag.  Same taint-lock gate.
    if not C_Secrets.ShouldAurasBeSecret() then
        applyRecipients(settings)
    end

    private.Util.ApplyComponentBackground(wrapper, settings.background)

    local shouldShow = (getEnabled() or private.isEditMode)
        and private.Anchor.IsVisibleForComponent(comp.name)
    if shouldShow then
        wrapper:SetAlpha(private.Anchor.GetEffectiveAlpha(comp.name))
        wrapper:Show()
    else
        -- A real Hide(), not alpha 0: the wrapper is not protected, and Anchoring
        -- lays it out in combat, so the pass that makes it visible again can
        -- Show() it (Core/Anchoring.lua `secureComponents`).
        wrapper:Hide()
    end

    local nowCollapsed = comp.IsCollapsed()
    if nowCollapsed ~= wasCollapsed then
        wasCollapsed = nowCollapsed
        private.Anchor.OnComponentStateChange()
    end
end

---Lightweight alpha sync for anchor inheritance — SetAlpha is not protected.
function comp.SyncAlpha()
    if not wrapper then return end
    local alpha = private.Anchor.IsVisibleForComponent(comp.name)
        and private.Anchor.GetEffectiveAlpha(comp.name) or 0
    wrapper:SetAlpha(alpha)
end

function comp.OnEnable()
    if wrapper and not InCombatLockdown() then
        wrapper:Show()
        comp.Refresh()
    end
end

function comp.OnDisable()
    if wrapper and not InCombatLockdown() then
        wrapper:Hide()
    end
end

function comp.GetComponentName()
    return comp.name
end

function comp.GetSettings()
    return getSettings()
end

function comp.GetEnabled()
    return getEnabled()
end

---Fixed size, same rationale as the other AuraContainer trackers: the aura
---container's real rect is engine-owned and secret, so the box can only be the
---reserved ceiling, never a live content hug.  IconOnly + collapse is the one
---case where the width is a settings constant rather than an estimate.
function comp.GetWantsContentWidth()
    local s = getSettings()
    if s.bar_content == "IconOnly" and s.collapse then return true end
    return false
end

---Nothing tracked, or nobody to track it on.
function comp.IsCollapsed()
    return rowCount == 0
end

function comp.GetComponentSize()
    local settings = getSettings()
    local iw, ih = itemDims(settings)
    local n = rowCount
    if n == 0 then
        if private.isEditMode then return iw, ih end
        return iw, 0
    end
    local spacing = settings.bar_spacing or 2
    if (settings.layout_direction or "vertical") == "horizontal" then
        return n * iw + (n - 1) * spacing, ih
    end
    return iw, n * ih + (n - 1) * spacing
end

comp.ContentLayout = function()
    comp.Refresh()
end

-- Refresh + re-run anchoring so a container-width change (e.g. bar_content,
-- collapse) propagates to anchored children immediately.
function comp.RefreshAndRelayout()
    comp.Refresh()
    if private.Anchor and private.Anchor.Refresh then
        private.Anchor.Refresh()
    end
end

---------------------------------------------------------------------------
-- Options-facing accessors
---------------------------------------------------------------------------

---Return the current tracked spell list (read-only view).
---@return number[]
function comp.GetTrackedSpells()
    return getSettings().tracked_spells or {}
end

---Add a spellID to the tracked list.  No-op if already present.
---@param spellID number
function comp.AddTrackedSpell(spellID)
    if type(spellID) ~= "number" or spellID <= 0 then return end
    local list = getSettings().tracked_spells
    for i = 1, #list do
        if list[i] == spellID then return end
    end
    list[#list + 1] = spellID
    comp.Refresh()
end

---Remove a spellID from the tracked list.
---@param spellID number
function comp.RemoveTrackedSpell(spellID)
    local list = getSettings().tracked_spells
    for i = 1, #list do
        if list[i] == spellID then
            table.remove(list, i)
            comp.Refresh()
            return
        end
    end
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

private.OutboundBuffTracker = comp
private.ComponentManager.RegisterComponent("OutboundBuffTracker", comp)

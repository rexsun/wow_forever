--[[
    TrackingTab.lua

    The Options "Tracking" tab (tab 4): every CDM tracker, every Additional
    Frame and the untracked pool as collapsible sections of rows, rendered
    from Core/TrackingModel.lua's BuildSections().  Row actions call the
    model's actions and re-read it.  Full contract in Core/UI/TrackingTab.md.

    Options.lua creates the panel and calls TrackingTab.Build(panel) from
    CreateOptionsFrame; nothing here runs at file load beyond defining the
    module table.
--]]

local _
---@type string, private
local addonName, private = ...

---@type detailsframework
local framework = _G["DetailsFramework"]

local L = private.L

---@class private : table
---@field TrackingTab trackingtab

---@class trackingtab : table
---@field Build fun(panel: frame)
---@field Attach fun()
---@field Detach fun()
---@field FocusSection fun(componentName: string)

---@type trackingtab
---@diagnostic disable-next-line: missing-fields
local trackingTab = {}
private.TrackingTab = trackingTab

---Same prefix as the Options panel's own frames.
local frameName = "CUE_OptionsPanel"

---Row pitch and row height: those of the retired Trackers-tab Icon Order
---list (ROW_HEIGHT 26 with 24-high rows).
local ROW_HEIGHT = 26
local ROW_INNER_HEIGHT = 24
local HEADER_HEIGHT = 28
local LABEL_HEIGHT = 20
local ADD_LINE_HEIGHT = 30
local SECTION_GAP = 8
local ROW_INDENT = 12
---The search filter applies from this many typed characters.
local SEARCH_MIN_CHARS = 2
---A drag auto-scrolls while the cursor is this close to the scroll box's
---top or bottom edge, at this many pixels per second.
local AUTOSCROLL_EDGE = 24
local AUTOSCROLL_SPEED = 400

-- ---------------------------------------------------------------------------
-- Session-local view state — never written to the profile.
-- ---------------------------------------------------------------------------

---Collapsed sections by section id.  The pool starts collapsed, everything
---else expanded.
---@type table<string, boolean>
local collapsed = { pool = true }
local showUnlearned = false
---The rank a collapsed spell row shows, by rank group key (collapseRanks):
---the picked rank's row key.
---@type table<string, number>
local rankPick = {}
---The "All specs" box, mirrored into TrackingModel.SetAllSpecs.
local allSpecs = false
local searchText = ""

-- ---------------------------------------------------------------------------
-- Built frames and the last model read (assigned by Build / refreshData)
-- ---------------------------------------------------------------------------

local panelFrame ---@type frame|nil
local scrollFrame ---@type scrollframe|nil
local scrollChild ---@type frame|nil
local notReadyLabel ---@type fontstring|nil
local eventFrame ---@type frame|nil

---@type tracking_section[]
local sections = {}
local modelReady = false
---Display title per section id, for the Move-to menu and the row tooltip.
---@type table<string, string>
local titleById = {}
---Scroll offset of each section's header in the last render.
---@type table<string, number>
local sectionTop = {}
---Section FocusSection asked for, scrolled to by the next ready render.
---@type string|nil
local pendingFocus
---The scroll offset that section's header needs, until the scroll range
---reaches it (applyFocus).
---@type number|nil
local focusWant

-- Pools, reused across renders.  Every entry is an addon-owned Options frame.
local headerPool, rowPool, labelPool, addPool = {}, {}, {}, {}
local headerUsed, rowUsed, labelUsed, addUsed = 0, 0, 0, 0

-- Forward declarations: the pooled frames' scripts call these.
local render
local requestRebuild

-- ---------------------------------------------------------------------------
-- Labels and filters
-- ---------------------------------------------------------------------------

---The title a section is shown under.
---@param section tracking_section
---@return string
local function sectionTitle(section)
    if section.kind == "cdm" then
        local keys = {
            CooldownTracker = "COMP_COOLDOWN_TRACKER",
            UtilitiesTracker = "COMP_UTILITIES_TRACKER",
            BuffTracker = "COMP_BUFF_TRACKER",
            BuffTrackerBars = "COMP_BUFF_TRACKER_BARS",
        }
        return L[keys[section.id]] or section.id
    elseif section.kind == "af" then
        -- The Additional Frames tab's own fallback: the id when unnamed.
        local title = (section.name and section.name ~= "") and section.name or section.afId
        if section.disabled then title = title .. " " .. L["TRACKING_FRAME_DISABLED"] end
        return title
    end
    return L["TRACKING_POOL"]
end

---A row's display name.  `row.name` is nil where TrackingModel leaves the
---wording to the UI; the item fallbacks are the ones the retired Icon Order
---list used.
---@param row tracking_row
---@return string
local function rowLabel(row)
    if row.name and row.name ~= "" then return row.name end
    -- Additional Frame addon-source entries: the retired Additional Frames
    -- list's labels (the slot, the consumable category).
    if row.source == "Trinket" then
        return row.key == 13 and L["TRINKET_SLOT_1"] or L["TRINKET_SLOT_2"]
    end
    if row.source == "Consumable" then
        local ct = private.ConsumableTracker
        if ct then
            for catKey, catID in pairs(ct.GetCategoryIDs()) do
                if catID == row.key then
                    return L["CONSUMABLE_CAT_" .. catKey:upper()] or L["ICON_ORDER_CONSUMABLE"]
                end
            end
        end
        return L["ICON_ORDER_CONSUMABLE"]
    end
    if row.kind == "item" then
        local iconSource = private.CDMDataSource.GetIconSource(row.key)
        if iconSource then
            if iconSource.equipSlot then return L["ICON_ORDER_TRINKET"] end
            return L["ICON_ORDER_CATEGORY_" .. tostring(iconSource.spellCategoryID)]
                or L["ICON_ORDER_CONSUMABLE"]
        end
    end
    return string.format(L["TRACKING_UNKNOWN_SPELL"], row.key)
end

---The lowercased search needle, or nil below SEARCH_MIN_CHARS.
---@return string|nil
local function currentNeedle()
    local text = (searchText or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #text < SEARCH_MIN_CHARS then return nil end
    return text:lower()
end

---Is `row` shown under the current search and "Show unlearned" state?
---"Unlearned" is `learned`, not `known`: a rank the character has but no
---tracker draws is listed, marked inactive (placeRow).
---A stale row is always eligible: it is a leftover to clean up, not an
---unlearned spell.  So is a custom row: the player added it, and its "Only
---When Usable" toggle is the way to make an unusable one draw (the retired
---custom-spell list listed every entry too).  And so is any row the player
---saved something on: a frame's entry (every row holding a `listIndex` into
---`assigned_spells`, which the retired Additional Frames list showed, and
---whose Remove here is the only way left to take it out) and a row with an
---icon override (the retired Icon Overrides list showed every one).
---@param row tracking_row
---@param needle string|nil
---@return boolean
local function rowVisible(row, needle)
    if not showUnlearned and not row.learned and row.kind ~= "stale" and row.kind ~= "custom"
        and not row.listIndex and not row.hasIconOverride then return false end
    if needle then
        if not rowLabel(row):lower():find(needle, 1, true)
            and not tostring(row.key):find(needle, 1, true) then
            return false
        end
    end
    return true
end

---The number in a rank label ("Rank 3" -> 3), for ordering a spell's ranks.
---@param row tracking_row
---@return number
local function rankNumber(row)
    return tonumber(row.rank:match("%d+")) or 0
end

---One row per spell where the client has spell ranks.  WoW Forever lists
---every rank as its own CDM entry (Moonfire: ten ranks, a cooldown and a buff
---each), so a list's ranked rows of one name, kind and bucket collapse into
---one, showing the rank `picks` names for the group, else the highest one the
---tracker draws (a whole family's representative), else the highest learned,
---else the lowest.  The collapse is visual only: every rank stays its own row
---in the model, and the row's rank button (openRankMenu) switches which one it
---shows or, in a tracker, what the spell is tracked as.  A group is listed when any of
---its ranks passes `visible`, so a learned spell's menu reaches its unlearned
---ranks without "Show unlearned".  Stale rows never collapse: each is its own
---leftover to clean up.
---@param listId string  the section id: a group never spans sections
---@param rows tracking_row[]
---@param visible fun(row: tracking_row): boolean
---@param picks table<string, number>  group key -> the picked rank's row key
---@return number[] shown  indices into `rows`, in row order
---@return table<number, table> groupAt  shown index -> { key, rows } of a collapsed row
local function collapseRanks(listId, rows, visible, picks)
    local groups, groupOf = {}, {}
    for i = 1, #rows do
        local row = rows[i]
        if row.rank and row.kind ~= "stale" then
            local key = table.concat({ listId, row.kind, row.bucket or "", row.name or "" }, "\0")
            local group = groups[key]
            if not group then
                group = { key = key, members = {} }
                groups[key] = group
            end
            group.members[#group.members + 1] = i
            groupOf[i] = group
        end
    end
    for _, group in pairs(groups) do
        local members = group.members
        table.sort(members, function(a, b)
            local ra, rb = rankNumber(rows[a]), rankNumber(rows[b])
            if ra ~= rb then return ra < rb end
            return a < b
        end)
        local picked, drawn, learned
        group.rows = {}
        for j = 1, #members do
            local row = rows[members[j]]
            group.rows[j] = row
            if row.key == picks[group.key] then picked = members[j] end
            if row.known then drawn = members[j] end
            if row.learned then learned = members[j] end
            if visible(row) then group.visible = true end
        end
        -- A whole spell-rank family draws only its representative, the one
        -- `known` row, so that is what the row shows unless a rank is picked.
        group.shown = picked or drawn or learned or members[1]
    end
    local shown, groupAt = {}, {}
    for i = 1, #rows do
        local group = groupOf[i]
        if group then
            if group.visible and group.shown == i then
                shown[#shown + 1] = i
                groupAt[i] = group
            end
        elseif visible(rows[i]) then
            shown[#shown + 1] = i
        end
    end
    return shown, groupAt
end

---True when a reorder in this section would change nothing on screen.
---Mirrors the Options panels' engine gate (`IsUsingSlots`): a bar display
---under Blizzard's compacting group is laid out by
---AuraContainerSortMethod.Default, so no addon order reaches it
---(Components/README.md "Icon Order").  BuffTracker is not gated — its
---compacting default is the per-spell groups engine, which does honour order.
---@param section tracking_section
---@return boolean
local function isOrderLocked(section)
    local bars = section.id == "BuffTrackerBars" or section.frameType == "bar"
    if not bars then return false end
    local component
    if section.kind == "cdm" then
        component = private[section.componentName]
    else
        -- IsUsingSlots lives on the frame's aura tracker (AdditionalFrameManager
        -- getAuraTracker), not on the plain instance.component wrapper.
        local instance = private.AdditionalFrameManager.GetInstance(section.afId)
        component = instance and (instance.auraTracker or instance.component)
    end
    return component ~= nil and component.IsUsingSlots ~= nil and not component.IsUsingSlots()
end

---The settings table holding a section's per-spell keys (`spell_colors`,
---`pandemic_glow_excludes`): the tracker's own for a CDM section, the frame's
---profile for an Additional Frame.
---@param section tracking_section|nil
---@return table|nil
local function sectionSettings(section)
    if not section then return nil end
    if section.kind == "cdm" then
        local component = private[section.componentName]
        return component and component.GetSettings() or nil
    elseif section.kind == "af" then
        local afs = private.profile and private.profile.additional_frames
        return afs and afs[section.afId] or nil
    end
    return nil
end

---After a per-spell write, the refresh the panel that used to edit the key
---runs: the Trackers tab's `component.Refresh()` for a CDM tracker, the
---Additional Frames tab's `refreshSelectedFrame` for a frame.
---@param section tracking_section
local function refreshSection(section)
    if section.kind == "cdm" then
        local component = private[section.componentName]
        if component then component.Refresh() end
    elseif section.kind == "af" then
        local instance = private.AdditionalFrameManager.GetInstance(section.afId)
        if instance then instance.component.Refresh() end
        private.ComponentManager.RefreshAllComponents()
        private.Anchor.Refresh()
    end
end

---refreshSection with the restyle pass: the buff trackers draw a per-spell
---border in their restyle, which a table-valued key never triggers on its own
---(their RESTYLE_KEYS diff scalars; patterns.md "fontsDirty gates ALL per-child
---styling").
---@param section tracking_section
local function restyleSection(section)
    private.fontsDirty = true
    refreshSection(section)
    private.fontsDirty = false
end

---Does `data` name a spell a per-spell setting can be keyed by?  An item row
---(a slot, a consumable category, a synthetic negative key) has no spellID.
---A duplicate Additional Frame entry is left out too: the row it duplicates
---already carries that spell's controls.
---@param data tracking_row
---@return boolean
local function isSpellRow(data)
    return data.kind ~= "item" and not data.source and data.key > 0
        and not (data.kind == "assigned" and data.duplicateOf)
end

---Which right-hand controls a section's rows carry.  Every row of a section
---shows the same set, each disabled where it does not apply to that row, so a
---control stays in one column down the section and a click always lands on
---the same kind of button.  Remove, Move to and Change icon are on every row;
---Up/Down on every section row; the rest per the retired Trackers-tab gates:
---  color     a bar display with a `bar_fill_color`, on the slots engine —
---            under Blizzard's compacting group the button↔spell binding is
---            secret, so a per-spell colour has nothing to key on (the same
---            condition isOrderLocked reads)
---  pandemic  the tracker carries a `pandemic_glow` setting at all, and is not
---            a bar display on Blizzard's compacting group: the exclude needs
---            the button's spell, which only BuffTracker's per-spell groups
---            carry there (AuraContainer.SyncPandemic; bars: #47)
---  unit      an aura section (`aura_unit`): both engines honour it
---            (AuraContainer.SplitByUnitScope / the slots' per-filter test)
---  restrict  the section has a custom row: Only When Usable on a cooldown
---            section, This spec on an aura section (none without a spec system)
---  force     the section has a row TrackingModel.CanForceActive allows
---  activeSwipe  a cooldown section (the cooldown trackers and `spells` frames,
---            all IconTracker, the reader): `active_swipe_excludes`.  Not gated on
---            `hide_active_swipe` being saved: a frame older than the key lacks
---            it, and the reader treats nil as on
---  rank      the section has a ranked row (collapseRanks); rows without one
---            leave the column empty, so the names still end in one line
---  border    an icon display (not Buff Bars, not a bar frame): `spell_borders`,
---            drawn by IconTracker and AuraIconTracker; bars wait on #47
---  missing   an aura icon display (BuffTracker, a `buffs` frame) on Always
---            Show: `missing_glow`, drawn on the slot cells, which only the
---            slots engine has
---pandemic, unit, restrict, force, activeSwipe, border and missing are not
---columns: they are the entries of the row's Options menu, a column whenever
---any is set.
---@param section tracking_section
---@return table cols  { order, color, pandemic, unit, restrict, force, activeSwipe, border, missing, options, rank, settings }
local function sectionColumns(section)
    local cols = { order = section.kind ~= "pool" }
    for i = 1, #section.rows do
        local row = section.rows[i]
        if row.rank and row.kind ~= "stale" then
            cols.rank = true
            break
        end
    end
    if not cols.order then return cols end
    local settings = sectionSettings(section)
    cols.settings = settings
    local bars = section.id == "BuffTrackerBars" or section.frameType == "bar"
    local locked = isOrderLocked(section)
    cols.color = bars and settings ~= nil and settings.bar_fill_color ~= nil and not locked
    cols.pandemic = settings ~= nil and settings.pandemic_glow ~= nil and not locked
    cols.unit = settings ~= nil and section.bucket == "aura"
    -- An aura host scopes by spec, not restrict_to_player
    -- (CustomSpells.shouldFilterEntry); with no spec system it has no box.
    if section.bucket ~= "aura" or private.CDMDataSource.GetSpecLayerKey() then
        for i = 1, #section.rows do
            if section.rows[i].kind == "custom" then
                cols.restrict = true
                break
            end
        end
    end
    for i = 1, #section.rows do
        if private.TrackingModel.CanForceActive(section.rows[i]) then
            cols.force = true
            break
        end
    end
    cols.activeSwipe = settings ~= nil and section.bucket == "cooldown"
    cols.border = settings ~= nil and not bars
    cols.missing = settings ~= nil and not bars and section.bucket == "aura"
        and settings.always_show_tracked == true
    cols.options = cols.pandemic or cols.unit or cols.restrict or cols.force or cols.activeSwipe
        or cols.border or cols.missing
    return cols
end

---May `a` and `b` (neighbouring rows of `section`) trade places through
---TrackingModel.Reorder?  An Additional Frame orders only its assigned block;
---custom rows rank after it (Core/TrackingModel.md, Reorder).
---@param section tracking_section
---@param a tracking_row
---@param b tracking_row
---@return boolean
local function canSwap(section, a, b)
    if a.key == b.key then return false end
    -- A stale row draws nothing and closes its section: never a position.
    if a.kind == "stale" or b.kind == "stale" then return false end
    if section.kind == "af" and (a.kind == "custom" or b.kind == "custom") then return false end
    -- A row the tracker does not draw is not in the order Reorder
    -- materializes, so the trade would be refused: an entry the character
    -- does not have, a custom entry restrict_to_player filters, or one that
    -- duplicates another row's aura/identity.
    if section.kind == "cdm" and (not a.known or not b.known
        or (a.kind == "custom" and a.duplicateOf) or (b.kind == "custom" and b.duplicateOf)) then
        return false
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Tooltip and menu
-- ---------------------------------------------------------------------------

---Spell / item tooltip for a row, plus the section it lives in.
---@param owner frame
---@param row tracking_row
local function showRowTooltip(owner, row)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local shown = false
    local slot = row.source == "Trinket" and row.key or nil
    if row.kind == "item" and not row.source then
        local iconSource = private.CDMDataSource.GetIconSource(row.key)
        slot = iconSource and iconSource.equipSlot or nil
    end
    if slot then
        shown = GameTooltip:SetInventoryItem("player", slot) and true or false
    elseif (not row.source or row.source == "Racial") and row.key > 0
        and C_Spell.GetSpellName(row.key) then
        GameTooltip:SetSpellByID(private.compat.GetOverrideSpell(row.key) or row.key)
        shown = true
    end
    if not shown then
        GameTooltip:SetText(rowLabel(row), 1, 1, 1)
    end
    if row.learned and not row.known and row.kind ~= "stale" and row.kind ~= "custom" then
        GameTooltip:AddLine(L["TRACKING_INACTIVE_DESC"], 0.8, 0.8, 0.8, true)
    end
    if row.thisSpec == false then
        GameTooltip:AddLine(L["TRACKING_OTHER_SPEC_DESC"], 0.8, 0.8, 0.8, true)
    end
    if row.byName then
        GameTooltip:AddLine(L["TRACKING_BY_NAME_DESC"], 0.8, 0.8, 0.8, true)
    end
    GameTooltip:AddLine(string.format(L["TRACKING_IN_SECTION"],
        titleById[row.sectionId] or row.sectionId), 0.6, 0.8, 1)
    -- A stale row: what is still saved for it, and where.
    local refs = row.refs
    if refs then
        for i = 1, #refs do
            local what = L["TRACKING_REF_" .. refs[i].list] or refs[i].list
            if refs[i].sectionId then
                what = what .. " (" .. (titleById[refs[i].sectionId] or refs[i].sectionId) .. ")"
            end
            GameTooltip:AddLine(string.format(L["TRACKING_SAVED_AS"], what), 0.8, 0.8, 0.8)
        end
    end
    GameTooltip:Show()
end

---The Move-to context menu: one entry per section TrackingModel.GetValidTargets
---returns, each moving the row to the end of that section -- or, in a tracker
---that follows Blizzard's order, to Blizzard's position for it.
---@param owner frame
---@param row tracking_row
---Below it, a Copy-to block: TrackingModel.GetCopyTargets, the other bucket's
---sections, each adding the spell there while the row stays.  One copy per
---type: once the spell is on the other bucket the block is one disabled line
---saying so.
---@param ranks "highest"|nil  a Spellbook row moved as "Highest" (rankModeOf)
local function openMoveMenu(owner, row, ranks)
    local targets = private.TrackingModel.GetValidTargets(row)
    local copyTargets, copyExists = private.TrackingModel.GetCopyTargets(row, sections)
    if #targets == 0 and #copyTargets == 0 then return end
    MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
        if #targets > 0 then
            rootDescription:CreateTitle(L["TRACKING_MOVE_TO"])
        end
        for i = 1, #targets do
            local targetId = targets[i]
            rootDescription:CreateButton(titleById[targetId] or targetId, function()
                private.TrackingModel.Move(row, targetId, nil, ranks)
                requestRebuild()
            end)
        end
        if #copyTargets > 0 or copyExists then
            if #targets > 0 then rootDescription:CreateDivider() end
            rootDescription:CreateTitle(L["TRACKING_COPY_TO"])
        end
        if copyExists then
            rootDescription:CreateButton(L[row.bucket == "cooldown" and "TRACKING_COPY_EXISTS_AURA"
                or "TRACKING_COPY_EXISTS_COOLDOWN"]):SetEnabled(false)
        end
        for i = 1, #copyTargets do
            local targetId = copyTargets[i]
            rootDescription:CreateButton(titleById[targetId] or targetId, function()
                private.TrackingModel.Copy(row, targetId)
                requestRebuild()
            end)
        end
    end)
end

local UNITS = { "both", "player", "target" }
local UNIT_LABEL = { both = "AURA_UNIT_BOTH", player = "AURA_UNIT_PLAYER", target = "AURA_UNIT_TARGET" }

---Which of the section's Options entries (sectionColumns) apply to `data`:
---the per-spell keys, a custom entry's box, Force Active.
---@param data tracking_row
---@param cols table  sectionColumns(section)
---@return boolean spell, boolean restrict, boolean force
local function rowOptions(data, cols)
    local spell = data.kind ~= "stale" and isSpellRow(data)
    return spell and (cols.pandemic or cols.unit or cols.activeSwipe or cols.border
            or cols.missing) or false,
        cols.restrict and data.kind == "custom" or false,
        cols.force and private.TrackingModel.CanForceActive(data) or false
end

---The Options menu: the per-spell settings of `row` that its section carries
---(sectionColumns) as checkboxes, the border colour as a swatch that opens the
---colour picker, then Track On (`aura_unit`) as radios.  A checkbox or radio
---keeps the menu open (Blizzard's default Refresh response), so several can be
---set in one go.
---@param owner frame
---@param row tracking_row
---@param section tracking_section
local function openOptionsMenu(owner, row, section)
    local cols = sectionColumns(section)
    local settings = cols.settings
    local spell, restrict, force = rowOptions(row, cols)
    if not settings or not (spell or restrict or force) then return end
    local options, model = private.Options, private.TrackingModel
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(rowLabel(row))
        -- Checked = the setting shows for this spell; unchecked = excluded.
        local function excludeBox(listKey, label, desc)
            local box = root:CreateCheckbox(label, function()
                return not options.IsExcluded(settings, listKey, row.key)
            end, function()
                options.SetExcluded(settings, listKey, row.key,
                    not options.IsExcluded(settings, listKey, row.key))
                refreshSection(section)
            end)
            box:SetTitleAndTextTooltip(label, desc)
        end
        if spell and cols.activeSwipe then
            excludeBox("active_swipe_excludes", L["TRACKING_ACTIVE_SWIPE"], L["TRACKING_ACTIVE_SWIPE_DESC"])
        end
        if spell and cols.pandemic then
            excludeBox("pandemic_glow_excludes", L["SETTING_PANDEMIC_GLOW"], L["TRACKING_PANDEMIC_DESC"])
        end
        if spell and cols.border then
            -- The swatch shows the icon border colour this spell draws with;
            -- the picker writes on every change, and Cancel puts back what it
            -- found (no entry, or the old colour).
            local own = options.GetSpellBorder(settings, row.key)
            local c = own or private.profile.icon_border.color
            local function pick()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                options.SetSpellBorder(settings, row.key, r, g, b, ColorPickerFrame:GetColorAlpha())
                restyleSection(section)
            end
            local colorInfo = {
                r = c[1], g = c[2], b = c[3], opacity = c[4] or 1, hasOpacity = true,
                swatchFunc = pick, opacityFunc = pick,
                cancelFunc = function()
                    if own then
                        options.SetSpellBorder(settings, row.key, own[1], own[2], own[3], own[4])
                    else
                        options.ClearSpellBorder(settings, row.key)
                    end
                    restyleSection(section)
                end,
            }
            local swatch = root:CreateColorSwatch(L["TRACKING_BORDER_COLOR"], function()
                ColorPickerFrame:SetupColorPickerAndShow(colorInfo)
            end, colorInfo)
            swatch:SetTitleAndTextTooltip(L["TRACKING_BORDER_COLOR"], L["TRACKING_BORDER_COLOR_DESC"])
            if own then
                local clear = root:CreateButton(L["TRACKING_BORDER_CLEAR"], function()
                    options.ClearSpellBorder(settings, row.key)
                    restyleSection(section)
                end)
                clear:SetTitleAndTextTooltip(L["TRACKING_BORDER_CLEAR"], L["TRACKING_BORDER_CLEAR_DESC"])
            end
        end
        if spell and cols.missing then
            -- An entry turns the glow on; its value is the colour (red at first).
            -- Applied on the layout pass (placeCell), so no restyle needed.
            local box = root:CreateCheckbox(L["TRACKING_MISSING_GLOW"], function()
                return options.GetMissingGlow(settings, row.key) ~= nil
            end, function()
                if options.GetMissingGlow(settings, row.key) then
                    options.ClearMissingGlow(settings, row.key)
                else
                    options.SetMissingGlow(settings, row.key, 1, 0, 0, 1)
                end
                refreshSection(section)
            end)
            box:SetTitleAndTextTooltip(L["TRACKING_MISSING_GLOW"], L["TRACKING_MISSING_GLOW_DESC"])
            -- Always built and greyed while off: a checkbox click re-inits the
            -- open menu's elements, it does not re-run this generator.  The
            -- colour is read on click, so Cancel restores what the picker found.
            local c = options.GetMissingGlow(settings, row.key) or { 1, 0, 0, 1 }
            local swatch = root:CreateColorSwatch(L["TRACKING_MISSING_GLOW_COLOR"], function()
                local own = options.GetMissingGlow(settings, row.key)
                if not own then return end
                local function pick()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    options.SetMissingGlow(settings, row.key, r, g, b, ColorPickerFrame:GetColorAlpha())
                    refreshSection(section)
                end
                ColorPickerFrame:SetupColorPickerAndShow({
                    r = own[1], g = own[2], b = own[3], opacity = own[4] or 1, hasOpacity = true,
                    swatchFunc = pick, opacityFunc = pick,
                    cancelFunc = function()
                        options.SetMissingGlow(settings, row.key, own[1], own[2], own[3], own[4])
                        refreshSection(section)
                    end,
                })
            end, { r = c[1], g = c[2], b = c[3], opacity = c[4] or 1, hasOpacity = true })
            swatch:SetTitleAndTextTooltip(L["TRACKING_MISSING_GLOW_COLOR"], L["TRACKING_MISSING_GLOW_COLOR_DESC"])
            swatch:SetEnabled(function() return options.GetMissingGlow(settings, row.key) ~= nil end)
        end
        -- The model's row is a snapshot, so these two boxes keep their own
        -- state; `known` follows either, so the badge and the order controls
        -- change and the tab rebuilds.
        if restrict then
            local aura = section.bucket == "aura"
            local on
            if aura then on = row.thisSpec ~= false else on = row.restrictToPlayer ~= false end
            local label = aura and L["TRACKING_THIS_SPEC"] or L["CUSTOM_SPELLS_USABLE_ONLY"]
            local box = root:CreateCheckbox(label, function() return on end, function()
                on = not on
                if aura then model.SetCustomSpec(row, on) else model.SetRestrictToPlayer(row, on) end
                requestRebuild()
            end)
            box:SetTitleAndTextTooltip(label,
                aura and L["TRACKING_THIS_SPEC_DESC"] or L["CUSTOM_SPELLS_USABLE_ONLY_DESC"])
            if aura then
                local byName = row.byName == true
                local nameBox = root:CreateCheckbox(L["TRACKING_BY_NAME"], function() return byName end, function()
                    if model.SetCustomByName(row, not byName) then
                        byName = not byName
                        requestRebuild()
                    end
                end)
                nameBox:SetTitleAndTextTooltip(L["TRACKING_BY_NAME"], L["TRACKING_BY_NAME_DESC"])
                -- Off stays clickable; on is refused for a name another
                -- by-name entry of this tracker already matches.
                nameBox:SetEnabled(function() return byName or model.CanSetCustomByName(row, true) end)
            end
        end
        if force then
            local on = row.forced == true
            local box = root:CreateCheckbox(L["TRACKING_FORCE_ACTIVE"], function() return on end, function()
                on = not on
                model.SetForceActive(row, on)
                requestRebuild()
            end)
            box:SetTitleAndTextTooltip(L["TRACKING_FORCE_ACTIVE"], L["TRACKING_FORCE_ACTIVE_DESC"])
        end
        if spell and cols.unit then
            root:CreateTitle(L["AURA_UNIT_HEADER"])
            for i = 1, #UNITS do
                local unit = UNITS[i]
                local radio = root:CreateRadio(L[UNIT_LABEL[unit]], function()
                    return options.GetAuraUnit(settings, row.key) == unit
                end, function()
                    options.SetAuraUnit(settings, row.key, unit)
                    refreshSection(section)
                end)
                radio:SetTitleAndTextTooltip(L["AURA_UNIT_HEADER"], L["AURA_UNIT_DESC"])
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Alerts menu: CUE's own per-spell alerts (CDMAlerts), pre-filled from the
-- Cooldown Manager.  A record is Blizzard's `{ type, event, payload }` shape.
-- ---------------------------------------------------------------------------

---Blizzard's per-spell cap (CooldownViewerLayoutManagerMixin:GetMaxNumAlertsPerItem).
local MAX_ALERTS = 3

---The Alerts button's markers: one icon per kind of alert the spell has, the
---atlases Blizzard's settings window shows on an item with alerts
---(CooldownViewerVisualAlertTarget.lua, CooldownViewerAlert_GetTypeAtlas).
local ALERT_MARK_SOUND = "|A:common-icon-sound:14:14|a"
local ALERT_MARK_VISUAL = "|A:common-icon-visual:14:14|a"

---The Alerts button's text for a spell: its markers, then the label.
---@param hasSound boolean
---@param hasVisual boolean
---@return string
local function alertsButtonText(hasSound, hasVisual)
    local marks = (hasSound and ALERT_MARK_SOUND or "") .. (hasVisual and ALERT_MARK_VISUAL or "")
    return marks == "" and L["TRACKING_ALERTS"] or marks .. " " .. L["TRACKING_ALERTS"]
end

---Blizzard's event names (CooldownViewerAlert.lua `alertWhenText`), built on
---first use: the global strings are the client's.
---@type table<number, string>|nil
local alertEventLabels

---@param alertEvent number  Enum.CooldownViewerAlertEventType
---@return string
local function alertEventText(alertEvent)
    if not alertEventLabels then
        local events = Enum.CooldownViewerAlertEventType
        alertEventLabels = {
            [events.Available] = COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_AVAILABLE,
            [events.PandemicTime] = COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_PANDEMIC,
            [events.OnCooldown] = COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_ON_COOLDOWN,
            [events.ChargeGained] = COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_CHARGE_GAINED,
            [events.OnAuraApplied] = COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_AURA_APPLIED,
            [events.OnAuraRemoved] = COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_AURA_REMOVED,
        }
    end
    return alertEventLabels[alertEvent] or tostring(alertEvent)
end

---One alert as a menu line: type icon, sound or visual, then the event.
---@param alert table
---@return string
local function alertLine(alert)
    local visual = CooldownViewerAlert_GetType(alert) == Enum.CooldownViewerAlertType.Visual
    return CreateAtlasMarkup(visual and "common-icon-visual" or "common-icon-sound", 16, 16)
        .. " " .. private.CDMAlerts.GetPayloadText(alert)
        .. "  |cff999999" .. alertEventText(CooldownViewerAlert_GetEvent(alert)) .. "|r"
end

---The events a row's alerts may fire on: its CDM entry's own set
---(C_CooldownViewer.GetValidAlertTypes), else its bucket's pair.  A spellbook
---row has no bucket and draws as a cooldown.
---@param row tracking_row
---@return number[]
local function alertEventsFor(row)
    local events = Enum.CooldownViewerAlertEventType
    if row.cooldownID then
        local valid = C_CooldownViewer.GetValidAlertTypes(row.cooldownID)
        table.sort(valid)
        return valid
    end
    if row.bucket == "aura" then return { events.OnAuraApplied, events.OnAuraRemoved } end
    return { events.Available, events.OnCooldown }
end

---Add one choice per sound or visual CUE can play on `alertEvent` under
---`parent`, from Blizzard's data tables (never their menu builders, which run
---their label caches): text-to-speech first, then Blizzard's sound categories.
---@param parent table  a menu element description
---@param alertType number
---@param alertEvent number
---@param isSelected fun(payload: number): boolean
---@param setSelected fun(payload: number): number|nil  a MenuResponse
local function addPayloadChoices(parent, alertType, alertEvent, isSelected, setSelected)
    if alertType == Enum.CooldownViewerAlertType.Visual then
        VisualAlertData_ForEach(function(data)
            parent:CreateRadio(data.text, isSelected, setSelected, data.enum)
        end)
        return
    end
    local tts = Enum.CooldownViewerSound.TextToSpeech
    if private.CDMAlerts.CanPlay(alertType, alertEvent, tts) then
        parent:CreateRadio(COOLDOWN_VIEWER_SETTINGS_ALERT_LABEL_SOUND_TYPE_TEXT_TO_SPEECH, isSelected, setSelected, tts)
    end
    local categoryName = tInvert(Enum.CooldownViewerSoundCategory)
    for category, sounds in ipairs(CooldownViewerSoundData) do
        local name = categoryName[category] or tostring(category)
        local sub = parent:CreateButton(_G["COOLDOWN_VIEWER_SETTINGS_SOUND_ALERT_CATEGORY_" .. name:upper()] or name)
        for i = 1, #sounds do
            sub:CreateRadio(sounds[i].text, isSelected, setSelected, sounds[i].soundEnum)
        end
    end
end

---The Alerts menu.  Lists CUE's own entry for the spell, else the Cooldown
---Manager's alerts CUE can play; the ones only Blizzard can play are listed
---apart, greyed.  The first change copies the list into CUE's entry
---(CDMAlerts.SetSpellAlerts); Blizzard's data is never written.  A sound or
---visual pick plays it and keeps the menu open so the next can be heard;
---every other change closes it.
---@param owner frame
---@param row tracking_row
---@param sampleFrame frame  the row's icon: a Visual sample plays on it
local function openAlertsMenu(owner, row, sampleFrame)
    local alerts = private.CDMAlerts
    local key = row.key
    local own, cdm = alerts.GetSpellAlerts(key)
    local shown, blizzardOnly = {}, {}
    for i = 1, own and #own or 0 do shown[i] = own[i] end
    for i = 1, cdm and #cdm or 0 do
        local a = cdm[i]
        local alertType, alertEvent = CooldownViewerAlert_GetType(a), CooldownViewerAlert_GetEvent(a)
        local payload = CooldownViewerAlert_GetPayload(a)
        if not alerts.CanPlay(alertType, alertEvent, payload) then
            blizzardOnly[#blizzardOnly + 1] = a
        elseif not own then
            shown[#shown + 1] = { alertType, alertEvent, payload }
        end
    end

    ---Copy `shown`, apply `edit`, and save it as CUE's entry.  `shown` then
    ---IS that entry, so the open menu's radios read the new values.
    local function commit(edit)
        local list = {}
        for i = 1, #shown do list[i] = { shown[i][1], shown[i][2], shown[i][3] } end
        edit(list)
        shown = list
        alerts.SetSpellAlerts(key, list)
    end
    local function exists(alertType, alertEvent, payload, skip)
        for i = 1, #shown do
            local a = shown[i]
            if i ~= skip and a[1] == alertType and a[2] == alertEvent and a[3] == payload then
                private.print(L["TRACKING_ALERT_EXISTS"])
                return true
            end
        end
        return false
    end

    local events = alertEventsFor(row)
    local TYPES = { Enum.CooldownViewerAlertType.Sound, Enum.CooldownViewerAlertType.Visual }
    local typeLabel = { [TYPES[1]] = L["TRACKING_ALERT_SOUND"], [TYPES[2]] = L["TRACKING_ALERT_VISUAL"] }

    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(rowLabel(row))
        root:CreateTitle(own and L["TRACKING_ALERTS_OWN"] or L["TRACKING_ALERTS_FROM_CDM"])
        if own and alerts.BlizzardPlaysToo(key) then
            local warn = root:CreateButton("|cffff8040" .. L["TRACKING_ALERTS_DOUBLE"] .. "|r")
            warn:SetEnabled(false)
            warn:SetTitleAndTextTooltip(L["TRACKING_ALERTS_DOUBLE"], L["TRACKING_ALERTS_DOUBLE_DESC"])
        end
        if #shown == 0 then
            root:CreateButton(L["TRACKING_ALERTS_NONE"]):SetEnabled(false)
        end
        for i = 1, #shown do
            local alertType = shown[i][1]
            local line = root:CreateButton(alertLine(shown[i]))
            line:CreateButton(L["TRACKING_ALERT_SAMPLE"], function()
                alerts.PlaySample(shown[i], key, sampleFrame)
                return MenuResponse.Open
            end)
            line:CreateTitle(L["TRACKING_ALERT_WHEN"])
            for _, alertEvent in ipairs(events) do
                if alerts.CanPlay(alertType, alertEvent, shown[i][3]) then
                    line:CreateRadio(alertEventText(alertEvent), function() return shown[i][2] == alertEvent end, function()
                        -- A payload pick above may have made this event unplayable.
                        if alerts.CanPlay(alertType, alertEvent, shown[i][3])
                            and not exists(alertType, alertEvent, shown[i][3], i) then
                            commit(function(list) list[i][2] = alertEvent end)
                        end
                        return MenuResponse.CloseAll
                    end)
                end
            end
            local payloads = line:CreateButton(typeLabel[alertType] or tostring(alertType))
            addPayloadChoices(payloads, alertType, shown[i][2], function(payload)
                return shown[i][3] == payload
            end, function(payload)
                if not exists(alertType, shown[i][2], payload, i) then
                    commit(function(list) list[i][3] = payload end)
                    alerts.PlaySample(shown[i], key, sampleFrame)
                end
                return MenuResponse.Refresh
            end)
            line:CreateButton(DELETE, function()
                commit(function(list) table.remove(list, i) end)
                return MenuResponse.CloseAll
            end)
        end
        if #blizzardOnly > 0 then
            root:CreateTitle(L["TRACKING_ALERTS_BLIZZARD_ONLY"])
            for i = 1, #blizzardOnly do
                local line = root:CreateButton(alertLine(blizzardOnly[i]))
                line:SetEnabled(false)
                line:SetTitleAndTextTooltip(L["TRACKING_ALERTS_BLIZZARD_ONLY"], L["TRACKING_ALERTS_BLIZZARD_ONLY_DESC"])
            end
        end

        root:CreateDivider()
        local add = root:CreateButton(L["TRACKING_ALERT_ADD"])
        if #shown >= MAX_ALERTS then
            add:SetEnabled(false)
            add:SetTitleAndTextTooltip(L["TRACKING_ALERT_ADD"], L["TRACKING_ALERT_ADD_FULL_DESC"])
        else
            -- Type, then event, then the sound or visual: picking one adds it.
            for _, alertType in ipairs(TYPES) do
                local typeMenu
                for _, alertEvent in ipairs(events) do
                    -- -1: any sound but text-to-speech, the widest a sound gets.
                    if alerts.CanPlay(alertType, alertEvent, -1) then
                        typeMenu = typeMenu or add:CreateButton(typeLabel[alertType])
                        local eventMenu = typeMenu:CreateButton(alertEventText(alertEvent))
                        addPayloadChoices(eventMenu, alertType, alertEvent, function() return false end, function(payload)
                            if not exists(alertType, alertEvent, payload) then
                                commit(function(list) list[#list + 1] = { alertType, alertEvent, payload } end)
                                alerts.PlaySample(shown[#shown], key, sampleFrame)
                            end
                            return MenuResponse.CloseAll
                        end)
                    end
                end
            end
        end
        if own then
            local reset = root:CreateButton(L["TRACKING_ALERTS_RESET"], function()
                alerts.SetSpellAlerts(key, nil)
                return MenuResponse.CloseAll
            end)
            reset:SetTitleAndTextTooltip(L["TRACKING_ALERTS_RESET"], L["TRACKING_ALERTS_RESET_DESC"])
        end
        root:CreateButton(L["COOLDOWN_MANAGER_SETTINGS"], function()
            _G["CooldownViewerSettings"]:Show()
            return MenuResponse.CloseAll
        end)
    end)
end

---The pool's sub-groups, in render order, and which one a pool row is in.
local POOL_GROUP_LABELS = { "TRACKING_POOL_COOLDOWNS", "TRACKING_POOL_AURAS",
    "TRACKING_POOL_SPELLBOOK", "TRACKING_POOL_STALE" }
---@param row tracking_row
---@return number
local function poolGroupOf(row)
    if row.kind == "spellbook" then return 3 end
    if row.kind == "stale" then return 4 end
    if row.bucket == "aura" then return 2 end
    return 1
end

---Cooldown or aura: which kind of section a rank row belongs to.  A spellbook
---spell is a cast (TrackingModel rule 2).
---@param row tracking_row
---@return string|nil
local function rankSide(row)
    if row.kind == "spellbook" then return "cooldown" end
    return row.bucket
end

---`rankPick` value for a Spellbook group moved as its highest learned rank.
local RANK_HIGHEST = "highest"

---What a collapsed row stands for as a whole spell, or nil for one rank:
---  "all"      a buff spell-rank family whole in this tracker: one cell for
---             whichever rank is up (CDMDataSource.applyRankFamilies)
---  "highest"  a cooldown family whole in this tracker, a custom cooldown
---             entry with `ranks = "highest"`, or a Spellbook group not pinned
---             to a rank (moved as "Highest", the default)
---@param data tracking_row  the row shown
---@param group table|nil  collapseRanks' group
---@return "all"|"highest"|nil
local function rankModeOf(data, group)
    if data.kind == "spellbook" then
        if not group then return nil end
        local pick = rankPick[group.key]
        return (pick == nil or pick == RANK_HIGHEST) and "highest" or nil
    end
    if data.kind == "custom" then
        return data.ranks == "highest" and "highest" or nil
    end
    local family = data.family
    if data.kind == "cdm" and data.sectionId ~= "pool" and family and family.whole
        and family.rep == data.key then
        return family.bucket == "aura" and "all" or "highest"
    end
    return nil
end

---A rank's menu label: its rank, the badge its own row would carry, and where
---it sits when that is not the row's own section.
---@param member tracking_row
---@param elsewhere boolean
---@return string
local function rankEntryLabel(member, elsewhere)
    local label = member.rank
    -- A whole family's ranks are drawn through its representative, so none of
    -- them is inactive on its own.
    local family = member.family
    if not member.learned then
        label = label .. "  |cff888888" .. L["TRACKING_BADGE_UNLEARNED"] .. "|r"
    elseif not member.known and member.kind ~= "spellbook" and not (family and family.whole) then
        label = label .. "  |cff888888" .. L["TRACKING_BADGE_INACTIVE"] .. "|r"
    end
    if elsewhere then
        local where = titleById[member.sectionId] or member.sectionId
        if member.sectionId == "pool" then
            where = where .. ": " .. L[POOL_GROUP_LABELS[poolGroupOf(member)]]
        end
        label = label .. "  |cff88bbff" .. where .. "|r"
    end
    return label
end

---Run `fn` after the player confirms `message` (CLASSUIENHANCED_RANK_CONFIRM,
---defined in Build).
---@param message string
---@param fn function
local function confirmRankChange(message, fn)
    StaticPopup_Show("CLASSUIENHANCED_RANK_CONFIRM", message, nil, fn)
end

---Every row of `current`'s spell in the last model read that `keep` admits,
---lowest rank first, then in section order.
---@param current tracking_row
---@param keep fun(row: tracking_row): boolean
---@return tracking_row[]
local function rankRowsOf(current, keep)
    local list, order = {}, {}
    for s = 1, #sections do
        local rows = sections[s].rows
        for i = 1, #rows do
            local row = rows[i]
            if row.rank and row.kind ~= "stale" and row.name == current.name and keep(row) then
                list[#list + 1] = row
                order[row] = s
            end
        end
    end
    table.sort(list, function(a, b)
        local ra, rb = rankNumber(a), rankNumber(b)
        if ra ~= rb then return ra < rb end
        return order[a] < order[b]
    end)
    return list
end

---A collapsed spell row's rank menu (collapseRanks, rankModeOf).
---  pool           the group's own ranks only switch which one the row shows; a
---                 Spellbook group adds "Highest", what a move then creates
---  tracker, CDM   "All ranks" / "Highest" brings every rank of the spell here
---                 (TrackingModel.SetFamilyMode); a rank makes it the only one
---                 here, the others going to Not tracked (SetSingleRank)
---  custom         "Highest" or a rank, in place (SetCustomRank)
---  frame, other   a rank from elsewhere swaps in (SwapRank)
---Taking a rank out of another tracker or frame asks first.  An entry the
---model would refuse is listed disabled.
---@param owner frame
---@param group table  { key, rows }
---@param current tracking_row  the rank the row shows now
---@param index number|nil  current's position in its section's rows
---@param section tracking_section
local function openRankMenu(owner, group, current, index, section)
    local model = private.TrackingModel
    local mode = rankModeOf(current, group)
    MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
        rootDescription:CreateTitle(L["TRACKING_RANK"])
        local function addRadio(label, selected, onPick, enabled)
            local radio = rootDescription:CreateRadio(label, function() return selected end, onPick)
            radio:SetResponse(MenuResponse.Close)
            radio:SetEnabled(enabled ~= false)
        end

        if current.sectionId == "pool" then
            if current.kind == "spellbook" then
                addRadio(L["TRACKING_RANK_HIGHEST"], mode == "highest", function()
                    rankPick[group.key] = RANK_HIGHEST
                    render()
                end)
            end
            for i = 1, #group.rows do
                local member = group.rows[i]
                addRadio(rankEntryLabel(member, false), mode == nil and member == current, function()
                    rankPick[group.key] = member.key
                    render()
                end)
            end
            return
        end

        if current.kind == "custom" and current.bucket == "cooldown" then
            addRadio(L["TRACKING_RANK_HIGHEST"], mode == "highest", function()
                if model.SetCustomRank(current, nil) then requestRebuild() end
            end)
            local seen = {}
            local ranks = rankRowsOf(current, function(row) return rankSide(row) == "cooldown" end)
            for i = 1, #ranks do
                local member = ranks[i]
                if not seen[member.key] then
                    seen[member.key] = true
                    addRadio(rankEntryLabel(member, false), mode == nil and member.key == current.key, function()
                        if model.SetCustomRank(current, member.key) then requestRebuild() end
                    end)
                end
            end
            return
        end

        local family = current.family
        if section.kind == "cdm" and current.kind == "cdm" and family then
            local members = rankRowsOf(current, function(row)
                return row.kind == "cdm" and row.family == family
            end)
            local foreign
            for i = 1, #members do
                local sid = members[i].sectionId
                if sid ~= current.sectionId and sid ~= "pool" then foreign = foreign or members[i] end
            end
            addRadio(family.bucket == "aura" and L["TRACKING_RANK_ALL"] or L["TRACKING_RANK_HIGHEST"],
                mode ~= nil, function()
                    local function go()
                        if model.SetFamilyMode(current, current.sectionId) then
                            rankPick[group.key] = nil
                            requestRebuild()
                        end
                    end
                    if foreign then
                        confirmRankChange(string.format(L["TRACKING_RANK_FAMILY_CONFIRM"], rowLabel(current),
                            titleById[foreign.sectionId] or foreign.sectionId), go)
                    else
                        go()
                    end
                end, mode ~= nil or model.CanSetFamilyMode(current, current.sectionId))
            for i = 1, #members do
                local member = members[i]
                local elsewhere = member.sectionId ~= current.sectionId
                addRadio(rankEntryLabel(member, elsewhere), mode == nil and member == current, function()
                    -- No view pick: what the tracker draws decides the row
                    -- (collapseRanks), so a pick could only go stale.
                    local function go()
                        if model.SetSingleRank(member, current.sectionId, index) then
                            rankPick[group.key] = nil
                            requestRebuild()
                        end
                    end
                    if elsewhere and member.sectionId ~= "pool" then
                        confirmRankChange(string.format(L["TRACKING_RANK_SINGLE_CONFIRM"],
                            rowLabel(member) .. " (" .. member.rank .. ")",
                            titleById[member.sectionId] or member.sectionId), go)
                    else
                        go()
                    end
                end, model.CanSetSingleRank(member, current.sectionId))
            end
            return
        end

        local inGroup = {}
        for i = 1, #group.rows do inGroup[group.rows[i]] = true end
        local side = rankSide(current)
        local ranks = rankRowsOf(current, function(row) return rankSide(row) == side end)
        for i = 1, #ranks do
            local member = ranks[i]
            local here = inGroup[member]
            addRadio(rankEntryLabel(member, not here), member == current, function()
                if here then
                    rankPick[group.key] = member.key
                    render()
                    return
                end
                local function swap()
                    if model.SwapRank(current, member, index) then
                        rankPick[group.key] = member.key
                        requestRebuild()
                    end
                end
                if member.sectionId == "pool" then
                    swap()
                else
                    confirmRankChange(string.format(L["TRACKING_RANK_SWAP_CONFIRM"],
                        rowLabel(member) .. " (" .. member.rank .. ")",
                        titleById[member.sectionId] or member.sectionId), swap)
                end
            end, here or (index ~= nil and model.CanSwapRank(current, member)))
        end
    end)
end

---Menu title per addon-source group, in TrackingModel's choice order.
local ADDON_SOURCE_TITLES = {
    Trinket = "SOURCE_TRINKETS",
    Consumable = "SOURCE_CONSUMABLES",
    Racial = "SOURCE_RACIALS",
}

---One addon-source choice's menu label, worded as the retired Additional
---Frames picker worded it.
---@param choice tracking_addon_choice
---@return string
local function addonChoiceLabel(choice)
    local label
    if choice.source == "Trinket" then
        local slot = choice.id == 13 and L["TRINKET_SLOT_1"] or L["TRINKET_SLOT_2"]
        label = choice.name and (slot .. ": " .. choice.name) or (slot .. " " .. L["ITEM_NOT_EQUIPPED"])
    elseif choice.source == "Consumable" then
        label = L["CONSUMABLE_CAT_" .. (choice.category or ""):upper()] or tostring(choice.id)
    else
        label = choice.name or string.format(L["TRACKING_UNKNOWN_SPELL"], choice.id)
    end
    if choice.texture then label = "|T" .. choice.texture .. ":16:16|t " .. label end
    return label
end

---The "Add item" menu of a `spells` Additional Frame section: every trinket
---slot, consumable category and racial TrackingModel.GetAddonSourceChoices
---offers, one already held by a frame greyed out and naming it.
---@param owner frame
---@param sectionId string
local function openAddItemMenu(owner, sectionId)
    local choices = private.TrackingModel.GetAddonSourceChoices(sectionId)
    if #choices == 0 then return end
    MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
        local lastSource
        for i = 1, #choices do
            local choice = choices[i]
            if choice.source ~= lastSource then
                lastSource = choice.source
                rootDescription:CreateTitle(L[ADDON_SOURCE_TITLES[choice.source]])
            end
            local label = addonChoiceLabel(choice)
            if choice.ownerAfId then
                local ownerId = "af:" .. choice.ownerAfId
                label = label .. " " .. string.format(L["SPELL_ALREADY_ASSIGNED"], titleById[ownerId] or choice.ownerAfId)
            end
            local button = rootDescription:CreateButton(label, function()
                if private.TrackingModel.AddAddonSource(choice.id, choice.source, sectionId) then
                    requestRebuild()
                end
            end)
            if choice.ownerAfId then button:SetEnabled(false) end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Drag and drop
--
-- Blizzard's CDM-settings flow (CooldownViewerSettingsMixin Begin/End/
-- CancelOrderChange) on addon-owned frames.  The OnUpdate and the
-- GLOBAL_MOUSE_UP registration exist only between beginDrag and endDrag;
-- endDrag is the one teardown every exit path calls.
-- ---------------------------------------------------------------------------

local dragIcon ---@type frame|nil  lazily created: the icon following the cursor
local reorderMarker ---@type frame|nil  lazily created: the insertion line

-- Drag state, all nil while no drag is in progress.
local dragRow ---@type frame|nil  the pooled source row, dimmed
local dragData ---@type tracking_row|nil
---The dragged row's rank mode, for a Spellbook row moved as "Highest".
local dragRanks ---@type "highest"|nil
---GetValidTargets(dragData) as a set, read once at drag start.
---@type table<string, boolean>|nil
local dragTargets
---GetTime() of the last teardown: a right-button cancel must not also click
---whatever is under the cursor in the same frame.
---@type number|nil
local dragEndedAt
---A rebuild requested mid-drag waits for the drag to end.
local rebuildAfterDrag = false

-- Where the cursor would drop, recomputed every tick.
local dropSection ---@type tracking_section|nil
local dropBefore ---@type frame|nil  rendered row the drop lands before; nil = end
local dropLast ---@type frame|nil  last rendered row of dropSection
local dropHeader ---@type frame|nil  dropSection's header

-- Last marker anchor and tint, so a tick re-anchors / re-tints only on change.
local markerRef, markerBelow, paintedLegal

---True while a drag runs, and for the rest of the frame it ended in.
---@return boolean
local function dragBusy()
    return dragRow ~= nil or dragEndedAt == GetTime()
end

---The rendered row the same-section drop trades places with (Reorder's
---`toIndex` row), or nil when the drop lands where the row already is.
---Positions count only dropSection's rendered rows, in render order, minus
---the stale rows closing it: a drop among those lands at the end.
---@return frame|nil
local function reorderAnchor()
    local n, from, gap = 0, nil, nil
    for i = 1, rowUsed do
        local row = rowPool[i]
        if row._cue_section == dropSection and row._cue_row.kind ~= "stale" then
            n = n + 1
            if row == dragRow then from = n end
            if row == dropBefore then gap = n end
        end
    end
    if not from then return nil end
    gap = gap or (n + 1)
    if gap == from or gap == from + 1 then return nil end
    -- Moving up lands before the row at the gap, moving down after the one
    -- above it: Reorder's remove-then-insert-at-anchor semantics.
    local want = gap < from and gap or (gap - 1)
    local k = 0
    for i = 1, rowUsed do
        local row = rowPool[i]
        if row._cue_section == dropSection and row._cue_row.kind ~= "stale" then
            k = k + 1
            if k == want then return row end
        end
    end
    return nil
end

---Would dropping on dropSection do something the model accepts?  Beside
---itself does nothing, which is never an error, locked section or not.
---@return boolean
local function dropIsLegal()
    local section = dropSection
    if section.id == dragData.sectionId then
        local anchor = reorderAnchor()
        if not anchor then return true end
        return not isOrderLocked(section) and canSwap(section, dragData, anchor._cue_row)
    end
    return dragTargets[section.id] == true
end

---Find the section and insertion point under the cursor from the rendered
---frames and `sectionTop` — never a model read.
---@param cy number  cursor y in scrollChild coordinates
local function updateDropTarget(cy)
    dropSection, dropBefore, dropLast, dropHeader = nil, nil, nil, nil
    if not scrollFrame:IsMouseOver() then return end
    local offset = scrollChild:GetTop() - cy
    if offset < 0 or offset > scrollChild:GetHeight() then return end
    local section
    for s = 1, #sections do
        local top = sectionTop[sections[s].id]
        if top and top <= offset then section = sections[s] end
    end
    if not section then return end
    -- Pool to pool changes nothing: no target at all.
    if section.kind == "pool" and dragData.sectionId == section.id then return end
    dropSection = section
    for i = 1, headerUsed do
        if headerPool[i]._cue_section == section then dropHeader = headerPool[i] end
    end
    -- On the header of an expanded section: before its first row.  A
    -- collapsed or empty section has no rendered rows: the end.
    local overHeader = offset < sectionTop[section.id] + HEADER_HEIGHT
    for i = 1, rowUsed do
        local row = rowPool[i]
        if row._cue_section == section then
            dropLast = row
            if not dropBefore then
                local _, centerY = row:GetCenter()
                if overHeader or cy > centerY then dropBefore = row end
            end
        end
    end
end

---Scroll while the cursor is within AUTOSCROLL_EDGE of the box's top or
---bottom edge — FocusSection's own SetVerticalScroll, clamped the same way.
local function autoScroll(cx, cy, elapsed)
    local left, right = scrollFrame:GetLeft(), scrollFrame:GetRight()
    local top, bottom = scrollFrame:GetTop(), scrollFrame:GetBottom()
    if not left or cx < left or cx > right or cy > top or cy < bottom then return end
    local step
    if cy > top - AUTOSCROLL_EDGE then
        step = -AUTOSCROLL_SPEED * elapsed
    elseif cy < bottom + AUTOSCROLL_EDGE then
        step = AUTOSCROLL_SPEED * elapsed
    else
        return
    end
    local current = scrollFrame:GetVerticalScroll()
    local target = math.max(0, math.min(current + step, scrollFrame:GetVerticalScrollRange()))
    if target ~= current then scrollFrame:SetVerticalScroll(target) end
end

---Show the marker at the drop point, tinted by legality, and tint the icon.
local function paintDrop()
    local legal = true
    if dropSection then
        legal = dropIsLegal()
        local ref, below = dropBefore, false
        if not ref then ref, below = dropLast or dropHeader, true end
        if ref then
            if ref ~= markerRef or below ~= markerBelow then
                markerRef, markerBelow = ref, below
                local edge = below and "BOTTOM" or "TOP"
                local dy = below and -1 or 1
                reorderMarker:ClearAllPoints()
                reorderMarker:SetPoint("LEFT", ref, edge .. "LEFT", 0, dy)
                reorderMarker:SetPoint("RIGHT", ref, edge .. "RIGHT", 0, dy)
            end
            reorderMarker:Show()
        else
            reorderMarker:Hide()
        end
    else
        reorderMarker:Hide()
    end
    if legal ~= paintedLegal then
        paintedLegal = legal
        -- Blizzard's marker tint: white / ERROR_COLOR.  Gold here, the grip's
        -- hover colour, since the line sits on the zebra stripes.
        if legal then
            reorderMarker.line:SetColorTexture(1, 0.82, 0, 1)
            dragIcon.icon:SetVertexColor(1, 1, 1)
        else
            reorderMarker.line:SetColorTexture(1, 0.1, 0.1, 1)
            dragIcon.icon:SetVertexColor(1, 0.3, 0.3)
        end
    end
end

---The one teardown: every drop, cancel, panel / window hide, profile change,
---render and error path ends here.  Idempotent, and safe before Build.
local function endDrag()
    if dragIcon then
        dragIcon:SetScript("OnUpdate", nil)
        dragIcon:UnregisterEvent("GLOBAL_MOUSE_UP")
        dragIcon:Hide()
    end
    if reorderMarker then reorderMarker:Hide() end
    local wasDragging = dragRow ~= nil
    if dragRow then dragRow:SetAlpha(1) end
    dragRow, dragData, dragTargets, dragRanks = nil, nil, nil, nil
    dropSection, dropBefore, dropLast, dropHeader = nil, nil, nil, nil
    markerRef, markerBelow, paintedLegal = nil, nil, nil
    if wasDragging then dragEndedAt = GetTime() end
    if rebuildAfterDrag then
        rebuildAfterDrag = false
        requestRebuild()
    end
end

---Does a fresh model still show `keyA` at `a` and `keyB` at `b` of the
---section?  Reorder takes indices; a model change during the drag (its
---rebuild waits for the drop) must not move a different row.
---@return boolean
local function modelShows(sectionId, a, keyA, b, keyB)
    local fresh, ready = private.TrackingModel.BuildSections()
    if not ready then return false end
    for s = 1, #fresh do
        if fresh[s].id == sectionId then
            local rows = fresh[s].rows
            return rows[a] ~= nil and rows[a].key == keyA and rows[b] ~= nil and rows[b].key == keyB
        end
    end
    return false
end

---The drop the last tick located, read off the rendered frames while they are
---still the drag's: a function committing it, false when refused, nil when
---there is nothing to do.  The commit runs after endDrag, so a throw in it
---leaves no drag behind.
---@return function|false|nil
local function planDrop()
    local section, data = dropSection, dragData
    if not section or not data or not dragRow then return nil end
    local model = private.TrackingModel
    if section.id == data.sectionId then
        -- Beside itself changes nothing, locked section or not.
        local anchor = reorderAnchor()
        if not anchor then return nil end
        if isOrderLocked(section) then return false end
        local anchorData = anchor._cue_row
        if not canSwap(section, data, anchorData) then return false end
        local sectionId, fromIndex, toIndex = section.id, dragRow._cue_index, anchor._cue_index
        return function()
            if not modelShows(sectionId, fromIndex, data.key, toIndex, anchorData.key) then return false end
            return model.Reorder(sectionId, fromIndex, toIndex)
        end
    end
    if not dragTargets[section.id] then return false end
    -- Before the row under the marker; past the last row (collapsed / empty /
    -- below the last row, or among the section's closing stale rows) appends.
    -- Always a position: a drop places the row, so an unarranged tracker's
    -- order is written, where the Move-to menu's nil leaves it on Blizzard's.
    -- Move re-checks legality itself.
    local targetId = section.id
    local index = dropBefore and dropBefore._cue_row.kind ~= "stale" and dropBefore._cue_index
        or #section.rows + 1
    local ranks = dragRanks
    return function() return model.Move(data, targetId, index, ranks) end
end

---GLOBAL_MOUSE_UP, registered only while dragging: left drops, right cancels.
local function onDragMouseUp(_, _, button)
    if button == "RightButton" then
        PlaySound(SOUNDKIT.UI_CURSOR_DROP_OBJECT)
        endDrag()
        return
    end
    if button ~= "LeftButton" then return end
    PlaySound(SOUNDKIT.UI_CURSOR_DROP_OBJECT)
    local commit = planDrop()
    endDrag()
    local result = commit
    if commit then result = commit() end
    if result == false then
        if SOUNDKIT.COOLDOWN_LAYOUT_MANAGER_PLACEMENT_ERROR then
            PlaySound(SOUNDKIT.COOLDOWN_LAYOUT_MANAGER_PLACEMENT_ERROR)
        end
    elseif result then
        requestRebuild()
    end
end

---The drag icon's OnUpdate: pin the icon to the cursor, auto-scroll,
---re-locate the drop.  A throw here repeats each frame until the mouse-up,
---which ends the drag whatever the tick did.
local function dragTick(self, elapsed)
    local x, y = GetCursorPosition()
    local iconScale = self:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / iconScale, y / iconScale)
    local scale = scrollChild:GetEffectiveScale()
    local cx, cy = x / scale, y / scale
    autoScroll(cx, cy, elapsed)
    updateDropTarget(cy)
    paintDrop()
end

---Create the drag icon and the marker on first use.  Neither carries an
---OnUpdate or an event registration until beginDrag installs them.
local function ensureDragFrames()
    if dragIcon then return end
    dragIcon = CreateFrame("Frame", nil, panelFrame)
    dragIcon:SetFrameStrata("TOOLTIP")
    dragIcon:SetSize(24, 24)
    dragIcon:Hide()
    dragIcon.icon = dragIcon:CreateTexture(nil, "ARTWORK")
    dragIcon.icon:SetAllPoints(dragIcon)
    dragIcon:SetScript("OnEvent", onDragMouseUp)

    reorderMarker = CreateFrame("Frame", nil, scrollChild)
    reorderMarker:SetFrameLevel(scrollChild:GetFrameLevel() + 50)
    reorderMarker:SetHeight(2)
    reorderMarker:Hide()
    reorderMarker.line = reorderMarker:CreateTexture(nil, "OVERLAY")
    reorderMarker.line:SetAllPoints(reorderMarker)
end

---A row's OnDragStart.
---@param row frame
local function beginDrag(row)
    if dragRow or not row._cue_draggable or not row._cue_row or not panelFrame or not scrollChild then return end
    ensureDragFrames()
    local data = row._cue_row
    dragRow, dragData, dragRanks = row, data, row._cue_rankMode
    dragTargets = {}
    local targets = private.TrackingModel.GetValidTargets(data)
    for i = 1, #targets do dragTargets[targets[i]] = true end
    GameTooltip:Hide()
    row:SetAlpha(0.4)
    dragIcon.icon:SetTexture(data.texture or 134400)
    PlaySound(SOUNDKIT.UI_CURSOR_PICKUP_OBJECT)
    dragIcon:RegisterEvent("GLOBAL_MOUSE_UP")
    dragIcon:SetScript("OnUpdate", dragTick)
    dragIcon:Show()
    dragTick(dragIcon, 0)
end

-- ---------------------------------------------------------------------------
-- Pooled widgets
-- ---------------------------------------------------------------------------

---Size a DF button to its label.
---@param btn table  a DF button
local function fitButton(btn)
    btn.widget:SetWidth(btn.widget.text:GetStringWidth() + 12)
end

---@return frame header
local function acquireHeader()
    headerUsed = headerUsed + 1
    local header = headerPool[headerUsed]
    if header then return header end
    local buttonTemplate = private.Templates.ButtonTemplate

    header = CreateFrame("Frame", nil, scrollChild)
    header:SetHeight(HEADER_HEIGHT - 4)
    header:EnableMouse(true)

    header.background = header:CreateTexture(nil, "BACKGROUND")
    header.background:SetAllPoints(header)
    header.background:SetColorTexture(0.2, 0.2, 0.2, 0.6)

    header.chevron = framework:CreateButton(header, function() end, 20, 20, "-", false, false, false, nil, nil)
    header.chevron:SetTemplate(buttonTemplate)
    header.chevron:SetPoint("LEFT", header, "LEFT", 2, 0)

    header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.title:SetPoint("LEFT", header.chevron.widget, "RIGHT", 6, 0)
    header.title:SetJustifyH("LEFT")

    header.resetMoves = framework:CreateButton(header, function() end, 20, 20, L["TRACKING_RESET_MOVES"], false, false, false, nil, nil)
    header.resetMoves:SetTemplate(buttonTemplate)
    fitButton(header.resetMoves)
    header.resetMoves:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    header.resetMoves:SetTooltip(L["TRACKING_RESET_MOVES_DESC"])

    header.resetOrder = framework:CreateButton(header, function() end, 20, 20, L["ICON_ORDER_RESET"], false, false, false, nil, nil)
    header.resetOrder:SetTemplate(buttonTemplate)
    fitButton(header.resetOrder)
    header.resetOrder:SetPoint("RIGHT", header.resetMoves.widget, "LEFT", -4, 0)
    header.resetOrder:SetTooltip(L["ICON_ORDER_RESET_DESC"])

    -- Shared by the chevron and the header's own left-click.
    local function toggle()
        if dragBusy() then return end
        local section = header._cue_section
        if not section then return end
        collapsed[section.id] = not collapsed[section.id]
        render()
    end
    header.chevron.widget:SetScript("OnClick", toggle)
    header:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then toggle() end
    end)

    -- Clears the tracker's icon order in one layer, like Reset moves: the
    -- current spec's own order, or the all-specs one with "All specs" ticked.
    header.resetOrder.widget:SetScript("OnClick", function()
        if dragBusy() then return end
        local section = header._cue_section
        if section then private.TrackingModel.ResetOrder(section.id) end
        requestRebuild()
    end)

    -- Clears the bucket's moves in one layer (both trackers of the bucket
    -- share it): the current spec's, or every spec's with "All specs" ticked.
    header.resetMoves.widget:SetScript("OnClick", function()
        if dragBusy() then return end
        local section = header._cue_section
        if section then private.TrackingModel.ResetMoves(section.bucket) end
        requestRebuild()
    end)

    headerPool[headerUsed] = header
    return header
end

---Pick an icon override for `data` — captured now, since the picker calls back
---after a render may have given the pooled row another row.  An addon-source
---row has no spell to key an override by.
---@param data tracking_row|nil
local function pickIcon(data)
    if not data or data.source or dragBusy() then return end
    private.IconPicker.Open(panelFrame, function(texture)
        private.TrackingModel.SetIconOverride(data, texture)
        requestRebuild()
    end)
end

---Clear `data`'s icon override (only that: a stale row's other refs stay).
---@param data tracking_row|nil
local function clearIcon(data)
    if not data or data.source or dragBusy() then return end
    private.TrackingModel.ClearIconOverride(data)
    requestRebuild()
end

---@return frame row
local function acquireRow()
    rowUsed = rowUsed + 1
    local row = rowPool[rowUsed]
    if row then return row end
    local buttonTemplate = private.Templates.ButtonTemplate

    row = CreateFrame("Frame", nil, scrollChild)
    row:SetHeight(ROW_INNER_HEIGHT)
    row:EnableMouse(true)

    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints(row)

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAllPoints(row)
    row.highlight:SetColorTexture(unpack(private.UIDefaults.lines.hoverColor))

    -- Drag grip, in the row indent left of the icon (the retired AF spell
    -- list's grip); the hit rect widens over it so it can be grabbed.
    -- Scripts are set here, once per pooled frame; placeRow only toggles
    -- `_cue_draggable` and the grip.
    row:RegisterForDrag("LeftButton")
    row:SetHitRectInsets(-10, 0, 0, 0)
    row:SetScript("OnDragStart", beginDrag)

    -- Icon: left-click picks an override, right-click clears it.
    row.iconBtn = CreateFrame("Button", nil, row)
    row.iconBtn:SetSize(20, 20)
    row.iconBtn:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.iconBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.icon = row.iconBtn:CreateTexture(nil, "ARTWORK")
    row.icon:SetSnapToPixelGrid(false)
    row.icon:SetTexelSnappingBias(0)
    row.icon:SetAllPoints(row.iconBtn)
    row.grip = row:CreateTexture(nil, "ARTWORK")
    row.grip:SetSnapToPixelGrid(false)
    row.grip:SetTexelSnappingBias(0)
    row.grip:SetSize(8, 16)
    row.grip:SetPoint("RIGHT", row.iconBtn, "LEFT", -2, 0)
    row.grip:SetColorTexture(0.4, 0.4, 0.4, 0.5)
    -- Corner mark: this row has an icon override.
    row.overrideMark = row.iconBtn:CreateTexture(nil, "OVERLAY")
    row.overrideMark:SetSnapToPixelGrid(false)
    row.overrideMark:SetTexelSnappingBias(0)
    row.overrideMark:SetSize(6, 6)
    row.overrideMark:SetPoint("TOPRIGHT", row.iconBtn, "TOPRIGHT", 1, 1)
    row.overrideMark:SetColorTexture(1, 0.82, 0, 1)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.iconBtn, "RIGHT", 6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    -- The right-hand columns, right to left: Remove, Move to, Down, Up, Change
    -- icon, Alerts, then the per-spell settings placeRow anchors.  Every row
    -- shows Remove and Move to, enabled or not, so each stays in one column.
    row.removeBtn = framework:CreateButton(row, function() end, 20, 20, L["TRACKING_REMOVE"], false, false, false, nil, nil)
    row.removeBtn:SetTemplate(buttonTemplate)
    fitButton(row.removeBtn)
    row.removeBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    row.moveBtn = framework:CreateButton(row, function() end, 20, 20, L["TRACKING_MOVE_TO"], false, false, false, nil, nil)
    row.moveBtn:SetTemplate(buttonTemplate)
    fitButton(row.moveBtn)
    row.moveBtn:SetPoint("RIGHT", row.removeBtn.widget, "LEFT", -4, 0)

    row.downBtn = framework:CreateButton(row, function() end, 20, 20, L["MOVE_DOWN"], false, false, false, nil, nil)
    row.downBtn:SetTemplate(buttonTemplate)
    fitButton(row.downBtn)
    row.downBtn:SetPoint("RIGHT", row.moveBtn.widget, "LEFT", -4, 0)

    row.upBtn = framework:CreateButton(row, function() end, 20, 20, L["MOVE_UP"], false, false, false, nil, nil)
    row.upBtn:SetTemplate(buttonTemplate)
    fitButton(row.upBtn)
    row.upBtn:SetPoint("RIGHT", row.downBtn.widget, "LEFT", -2, 0)

    -- The same action as clicking the icon, as a button: an override is
    -- otherwise easy to miss.
    row.iconPickBtn = framework:CreateButton(row, function() end, 20, 20, L["TRACKING_CHANGE_ICON"], false, false, false, nil, nil)
    row.iconPickBtn:SetTemplate(buttonTemplate)
    fitButton(row.iconPickBtn)
    row.iconPickBtn:SetTooltip(L["TRACKING_CHANGE_ICON_DESC"])
    row.iconPickBtn:SetClickFunction(function() pickIcon(row._cue_row) end)
    row.iconPickBtn:SetClickFunction(function() clearIcon(row._cue_row) end, nil, nil, "right")

    -- The spell's alerts (openAlertsMenu); a visual sample plays on the icon.
    row.alertsBtn = framework:CreateButton(row, function() end, 20, 20, L["TRACKING_ALERTS"], false, false, false, nil, nil)
    row.alertsBtn:SetTemplate(buttonTemplate)
    -- Sized for both markers, so the column keeps one width whatever a row shows.
    row.alertsBtn:SetText(alertsButtonText(true, true))
    fitButton(row.alertsBtn)
    row.alertsBtn.widget:SetScript("OnClick", function(self)
        if dragBusy() then return end
        if row._cue_row then openAlertsMenu(self, row._cue_row, row.iconBtn) end
    end)

    -- Per-spell settings (section rows only; placeRow shows and anchors them).
    -- The swatch is the widget a BuildMenu "color" entry builds; its callback
    -- fires for every colour-wheel change and for Cancel, as that entry's set does.
    -- The picker stays open across renders, which hand this pooled frame to
    -- other rows, so the callback writes to the row it was OPENED for: the
    -- OnMouseUp hook (run before DF opens the picker) captures it.
    row.colorBtn = framework:CreateColorPickButton(row, nil, nil, function(_, r, g, b, a)
        if dragBusy() then return end
        local data, section, settings = row._cue_colorRow, row._cue_colorSection, row._cue_colorSettings
        if not data or not settings then return end
        -- Cancel on a row with no colour of its own re-sends the fallback the
        -- swatch was showing; that is not a choice, so it writes nothing.
        -- Compared within a colour step: the picker hands back what the
        -- swatch's vertex colour stored, not the profile's exact floats.
        local key = data.key
        local shown = row._cue_colorFallback
        if shown and not private.Options.GetSpellColor(settings, key)
            and math.abs(r - shown[1]) < 0.005 and math.abs(g - shown[2]) < 0.005
            and math.abs(b - shown[3]) < 0.005 and math.abs(a - (shown[4] or 1)) < 0.005 then
            return
        end
        private.Options.SetSpellColor(settings, key, r, g, b, a)
        refreshSection(section)
        -- DF has painted this frame's swatch; if the frame now shows another
        -- row, re-render so it shows that row's colour again.
        if row._cue_row == data then
            row.colorBtn:SetAlpha(1)
        else
            render()
        end
    end, 1)
    row.colorBtn:SetHook("OnMouseUp", function()
        row._cue_colorRow = row._cue_row
        row._cue_colorSection = row._cue_section
        row._cue_colorSettings = sectionSettings(row._cue_section)
        row._cue_colorFallback = row._cue_fallback
    end)
    row.colorBtn:SetTooltip(L["TRACKING_SPELL_COLOR_DESC"])
    row.colorBtn:SetClickFunction(function()
        if dragBusy() then return end
        local section = row._cue_section
        local settings = sectionSettings(section)
        if not settings or not row._cue_row then return end
        private.Options.ClearSpellColor(settings, row._cue_row.key)
        refreshSection(section)
        render()
    end, nil, nil, "right")

    -- The rest of the per-spell settings: one menu (openOptionsMenu).
    row.optionsBtn = framework:CreateButton(row, function() end, 20, 20, L["TRACKING_OPTIONS"], false, false, false, nil, nil)
    row.optionsBtn:SetTemplate(buttonTemplate)
    fitButton(row.optionsBtn)
    row.optionsBtn.widget:SetScript("OnClick", function(self)
        if dragBusy() then return end
        if row._cue_row then openOptionsMenu(self, row._cue_row, row._cue_section) end
    end)

    -- A collapsed spell row's rank (collapseRanks): fixed width, so the
    -- column lines up whatever the rank reads.
    row.rankBtn = framework:CreateButton(row, function() end, 64, 20, "", false, false, false, nil, nil)
    row.rankBtn:SetTemplate(buttonTemplate)
    row.rankBtn:SetTooltip(L["TRACKING_RANK_DESC"])
    row.rankBtn.widget:SetScript("OnClick", function(self)
        if dragBusy() then return end
        if row._cue_rankGroup then
            openRankMenu(self, row._cue_rankGroup, row._cue_row, row._cue_index, row._cue_section)
        end
    end)

    row.name:SetPoint("RIGHT", row.upBtn.widget, "LEFT", -6, 0)

    row.iconBtn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            clearIcon(row._cue_row)
        else
            pickIcon(row._cue_row)
        end
    end)
    row.iconBtn:SetScript("OnEnter", function(self)
        local data = row._cue_row
        if not data or dragRow then return end
        showRowTooltip(self, data)
        if not data.source then
            GameTooltip:AddLine(L["TRACKING_ICON_HINT"], 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    row.iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row:SetScript("OnEnter", function(self)
        if dragRow then return end
        if self._cue_draggable then self.grip:SetColorTexture(1, 0.82, 0, 0.7) end
        if self._cue_row then showRowTooltip(self, self._cue_row) end
    end)
    row:SetScript("OnLeave", function(self)
        self.grip:SetColorTexture(0.4, 0.4, 0.4, 0.5)
        GameTooltip:Hide()
    end)
    row:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and self._cue_row and not dragBusy() then
            openMoveMenu(self, self._cue_row, self._cue_rankMode)
        end
    end)

    row.moveBtn.widget:SetScript("OnClick", function(self)
        if dragBusy() then return end
        if row._cue_row then openMoveMenu(self, row._cue_row, row._cue_rankMode) end
    end)
    row.upBtn.widget:SetScript("OnClick", function()
        if dragBusy() then return end
        if row._cue_upTo then
            private.TrackingModel.Reorder(row._cue_row.sectionId, row._cue_index, row._cue_upTo)
            requestRebuild()
        end
    end)
    row.downBtn.widget:SetScript("OnClick", function()
        if dragBusy() then return end
        if row._cue_downTo then
            private.TrackingModel.Reorder(row._cue_row.sectionId, row._cue_index, row._cue_downTo)
            requestRebuild()
        end
    end)
    -- Remove clears every list ref a stale row carries, icon_overrides
    -- included (TrackingModel.Remove), so no separate ClearIconOverride; on a
    -- CDM tracker's own row it hides the entry from that tracker.
    row.removeBtn.widget:SetScript("OnClick", function()
        if dragBusy() then return end
        if row._cue_row then
            private.TrackingModel.Remove(row._cue_row)
            requestRebuild()
        end
    end)

    rowPool[rowUsed] = row
    return row
end

---@return fontstring label
local function acquireLabel()
    labelUsed = labelUsed + 1
    local label = labelPool[labelUsed]
    if label then return label end
    label = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetJustifyH("LEFT")
    labelPool[labelUsed] = label
    return label
end

---@return table entry  a DF text entry
local function acquireAddEntry()
    addUsed = addUsed + 1
    local entry = addPool[addUsed]
    if entry then return entry end

    entry = framework:CreateTextEntry(scrollChild, function() end, 240, 22, nil, frameName .. "TrackingAddAura" .. addUsed)
    entry.widget:SetMaxLetters(10)
    entry.widget:SetAutoFocus(false)

    -- Worded per bucket by render(): the same pooled box serves both.
    local placeholder = entry.widget:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    placeholder:SetPoint("LEFT", entry.widget, "LEFT", 4, 0)
    entry._cue_placeholder = placeholder
    entry.widget:HookScript("OnTextChanged", function(self)
        placeholder:SetShown(self:GetText() == "")
    end)

    -- Enter only: DF's own func also fires on focus loss, which would add
    -- whatever was typed when the player merely clicked away.
    entry.widget:HookScript("OnEnterPressed", function(self)
        local sectionId = entry._cue_sectionId
        local text = self:GetText()
        local id = tonumber(text)
        self:SetText("")
        -- Nothing typed is nothing to add, as the retired add box had it.
        if not sectionId or text:match("^%s*$") then return end
        if not id or id <= 0 or not C_Spell.GetSpellName(id) then
            private.print(L["CUSTOM_SPELLS_INVALID_ID"])
            return
        end
        -- A cooldown section takes any castable id, spellbook or not
        -- (Hearthstone, an engineering gadget): AddFromSpellbook's own path.
        local model = private.TrackingModel
        local added
        if entry._cue_bucket == "cooldown" then
            added = model.AddFromSpellbook(id, sectionId)
        else
            added = model.AddAuraByID(id, sectionId)
        end
        if added then
            requestRebuild()
        else
            private.print(L["TRACKING_ADD_AURA_EXISTS"])
        end
    end)

    -- `spells` Additional Frames only (render shows it): trinkets,
    -- consumables and racials, which are not spell ids a typed box can take.
    -- A child of the box, so it hides with it.
    local itemBtn = framework:CreateButton(entry.widget, function() end, 20, 22, L["TRACKING_ADD_ITEM"], false, false, false, nil, nil)
    itemBtn:SetTemplate(private.Templates.ButtonTemplate)
    fitButton(itemBtn)
    itemBtn:SetPoint("LEFT", entry.widget, "RIGHT", 6, 0)
    itemBtn:SetTooltip(L["TRACKING_ADD_ITEM_DESC"])
    itemBtn.widget:SetScript("OnClick", function(self)
        if dragBusy() then return end
        if entry._cue_sectionId then openAddItemMenu(self, entry._cue_sectionId) end
    end)
    entry._cue_itemBtn = itemBtn

    addPool[addUsed] = entry
    return entry
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

---Place a label line at `y`, return the next y.
local function placeLabel(y, text, indent, r, g, b)
    local label = acquireLabel()
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", indent, -y - 4)
    label:SetText(text)
    label:SetTextColor(r, g, b)
    label:Show()
    return y + LABEL_HEIGHT
end

---The Remove button's tooltip for `data`: what Remove does to this kind of
---row, or why it is disabled.
---@param data tracking_row
---@param section tracking_section
---@param removable boolean
---@return string
local function removeTooltip(data, section, removable)
    if not removable then return L["TRACKING_REMOVE_NONE_DESC"] end
    if data.kind == "stale" then return L["TRACKING_REMOVE_STALE_DESC"] end
    if data.kind == "custom" then return L["TRACKING_REMOVE_CUSTOM_DESC"] end
    if section.kind == "af" then return L["TRACKING_REMOVE_ASSIGNED_DESC"] end
    return L["TRACKING_REMOVE_CDM_DESC"]
end

---Fill one pooled row from `data` and place it at `y`.
---@param y number
---@param data tracking_row
---@param stripe number  zebra index
---@param index number|nil  position in the section's rows (reorder source)
---@param upTo number|nil  reorder target above, nil = disabled
---@param downTo number|nil  reorder target below, nil = disabled
---@param lockReason string|nil  tooltip for disabled up/down
---@param section tracking_section  the row's section, the pool included
---@param cols table  sectionColumns(section)
---@param group table|nil  collapseRanks' group when `data` stands for a spell's ranks
---@return number nextY
local function placeRow(y, data, stripe, index, upTo, downTo, lockReason, section, cols, group)
    local row = acquireRow()
    row._cue_row = data
    row._cue_rankGroup = group
    row._cue_section = section
    row._cue_index = index
    row._cue_upTo = upTo
    row._cue_downTo = downTo
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", ROW_INDENT, -y)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", -4, 0)

    row.icon:SetTexture(data.texture or 134400)
    row.overrideMark:SetShown(data.hasIconOverride)

    local text = rowLabel(data)
    -- Where the client has spell ranks (WoW Forever), a spell's ranks share
    -- one row whose rank button shows the rank; a stale row keeps its rank
    -- in the name.
    if data.rank and not group then
        text = text .. " |cff888888(" .. data.rank .. ")|r"
    end
    local dim = false
    if data.kind == "stale" then
        text = text .. "  |cff888888[" .. L["ICON_ORDER_UNTRACKED"] .. "]|r"
        dim = true
    elseif data.thisSpec == false then
        text = text .. "  |cff888888[" .. L["TRACKING_BADGE_OTHER_SPEC"] .. "]|r"
        dim = true
    elseif not data.learned then
        text = text .. "  |cff888888[" .. L["TRACKING_BADGE_UNLEARNED"] .. "]|r"
        dim = true
    elseif not data.known then
        -- Learned, but nothing draws it (a lower rank on WoW Forever).
        text = text .. "  |cff888888[" .. L["TRACKING_BADGE_INACTIVE"] .. "]|r"
        dim = true
    end
    if data.inSpellbook and data.kind ~= "spellbook" then
        text = text .. "  |cff88bbff[" .. L["TRACKING_BADGE_SPELLBOOK"] .. "]|r"
    end
    if data.byName then
        local badge = data.byNamePending and L["TRACKING_BADGE_BY_NAME_PENDING"]
            or string.format(L["TRACKING_BADGE_BY_NAME"], data.byNameCount or 1)
        text = text .. "  |cff88bbff[" .. badge .. "]|r"
    end
    if data.kind == "assigned" and data.duplicateOf then
        text = text .. "  |cff888888[" .. L["TRACKING_BADGE_DUPLICATE"] .. "]|r"
    end
    row.name:SetText(text)
    -- A disabled frame's rows dim with it, controls still live.
    if dim or section.disabled then
        row.name:SetTextColor(0.6, 0.6, 0.6)
        row.icon:SetDesaturated(true)
        row.icon:SetAlpha(0.5)
    else
        row.name:SetTextColor(1, 1, 1)
        row.icon:SetDesaturated(false)
        row.icon:SetAlpha(1)
    end

    -- The columns, right to left: Remove and Move to (anchored once, in
    -- acquireRow), Down / Up on section rows, Change icon, Alerts on section
    -- rows, then the per-spell settings.  Which columns a row shows is the
    -- section's (cols); whether each is enabled is the row's.
    local model = private.TrackingModel
    local stale = data.kind == "stale"
    local spellRow = not stale and isSpellRow(data)

    local removable = model.CanRemove(data)
    row.removeBtn:SetEnabled(removable)
    row.removeBtn:SetTooltip(removeTooltip(data, section, removable))
    local hasTargets = #model.GetValidTargets(data) > 0 or #model.GetCopyTargets(data, sections) > 0
    row.moveBtn:SetEnabled(hasTargets)
    row.moveBtn:SetTooltip(not hasTargets and L["TRACKING_NO_TARGETS"] or nil)
    local leftmost = row.moveBtn.widget
    row.upBtn.widget:SetShown(cols.order)
    row.downBtn.widget:SetShown(cols.order)
    if cols.order then
        row.upBtn:SetEnabled(upTo ~= nil)
        row.downBtn:SetEnabled(downTo ~= nil)
        row.upBtn:SetTooltip(lockReason)
        row.downBtn:SetTooltip(lockReason)
        leftmost = row.upBtn.widget
    end
    row.iconPickBtn:SetEnabled(not data.source)
    row.iconPickBtn.widget:ClearAllPoints()
    row.iconPickBtn.widget:SetPoint("RIGHT", leftmost, "LEFT", -6, 0)
    leftmost = row.iconPickBtn.widget

    -- Alerts on every section row, enabled on a spell row: an item's alerts
    -- stay the Cooldown Manager's (`spell_alerts` is keyed by spellID).
    -- No column without the Cooldown Manager (MoP Classic): alerts are built on it.
    local alertsCol = cols.order and private.compat.HasCooldownManager()
    row.alertsBtn.widget:SetShown(alertsCol)
    if alertsCol then
        -- Marked on an item row too: its Cooldown Manager alerts still play.
        row.alertsBtn:SetText(alertsButtonText(private.CDMAlerts.GetSpellAlertTypes(data.key)))
        row.alertsBtn:SetEnabled(spellRow)
        row.alertsBtn:SetTooltip(spellRow and L["TRACKING_ALERTS_DESC"] or L["TRACKING_ALERTS_NONE_DESC"])
        row.alertsBtn.widget:ClearAllPoints()
        row.alertsBtn.widget:SetPoint("RIGHT", leftmost, "LEFT", -6, 0)
        leftmost = row.alertsBtn.widget
    end

    row.optionsBtn.widget:SetShown(cols.options == true)
    if cols.options then
        local spell, restrict, force = rowOptions(data, cols)
        local any = spell or restrict or force
        row.optionsBtn:SetEnabled(any)
        row.optionsBtn:SetTooltip(any and L["TRACKING_OPTIONS_DESC"] or L["TRACKING_OPTIONS_NONE_DESC"])
        row.optionsBtn.widget:ClearAllPoints()
        row.optionsBtn.widget:SetPoint("RIGHT", leftmost, "LEFT", -6, 0)
        leftmost = row.optionsBtn.widget
    end

    local settings = cols.settings
    row.colorBtn.widget:SetShown(cols.color == true)
    if cols.color then
        row.colorBtn:SetEnabled(spellRow)
        if spellRow then
            local color = private.Options.GetSpellColor(settings, data.key)
            row._cue_fallback = settings.bar_fill_color
            local c = color or row._cue_fallback
            row.colorBtn:SetColor(c[1], c[2], c[3], c[4] or 1)
            -- Dimmed while the bar follows the frame's own bar colour.
            row.colorBtn:SetAlpha(color and 1 or 0.4)
        else
            row._cue_fallback = nil
            row.colorBtn:SetColor(0.3, 0.3, 0.3, 1)
            row.colorBtn:SetAlpha(0.3)
        end
        row.colorBtn.widget:ClearAllPoints()
        row.colorBtn.widget:SetPoint("RIGHT", leftmost, "LEFT", -6, 0)
        leftmost = row.colorBtn.widget
    end
    -- Placed on every row of a section that has one, shown only on a
    -- collapsed spell row: a hidden button still anchors the name's end.
    row.rankBtn.widget:SetShown(group ~= nil)
    local rankMode = group and rankModeOf(data, group) or nil
    -- A Spellbook row moved as "Highest" becomes a custom entry that follows
    -- the highest learned rank (openMoveMenu, the drag).
    row._cue_rankMode = (data.kind == "spellbook" and rankMode == "highest") and "highest" or nil
    if cols.rank then
        if group then
            row.rankBtn:SetText(rankMode == "all" and L["TRACKING_RANK_ALL"]
                or rankMode == "highest" and L["TRACKING_RANK_HIGHEST"] or data.rank)
        end
        row.rankBtn.widget:ClearAllPoints()
        row.rankBtn.widget:SetPoint("RIGHT", leftmost, "LEFT", -6, 0)
        leftmost = row.rankBtn.widget
    end

    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row.iconBtn, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", leftmost, "LEFT", -6, 0)

    -- Draggable when a drop could do anything: another section, or a
    -- neighbour this row may trade places with (the Up/Down gate).
    row._cue_draggable = hasTargets or upTo ~= nil or downTo ~= nil
    row.grip:SetShown(row._cue_draggable)

    if stripe % 2 == 0 then
        row.background:SetColorTexture(unpack(private.UIDefaults.zebraStriping.color1))
    else
        row.background:SetColorTexture(unpack(private.UIDefaults.zebraStriping.color2))
    end
    row:Show()
    return y + ROW_HEIGHT
end

---A tracker or Additional Frame section's rows, with up/down targets.  Its
---stale rows close it (TrackingModel), trading places with nothing.
---@return number nextY
local function placeSectionRows(y, section, needle)
    local visible, groupAt = collapseRanks(section.id, section.rows,
        function(row) return rowVisible(row, needle) end, rankPick)
    if #visible == 0 then
        return placeLabel(y, L["ICON_ORDER_EMPTY"], ROW_INDENT + 4, 0.5, 0.5, 0.5)
    end
    local cols = sectionColumns(section)
    local locked = isOrderLocked(section)
    for p = 1, #visible do
        local i = visible[p]
        local data = section.rows[i]
        -- Up/down trade places with the nearest SHOWN neighbour, so a search
        -- or a hidden unlearned row never makes a click land out of sight.
        local upTo, downTo
        if not locked then
            local above, below = visible[p - 1], visible[p + 1]
            if above and canSwap(section, data, section.rows[above]) then upTo = above end
            if below and canSwap(section, data, section.rows[below]) then downTo = below end
        end
        local lockReason = locked and data.kind ~= "stale" and L["TRACKING_ORDER_LOCKED"] or nil
        y = placeRow(y, data, p, i, upTo, downTo, lockReason, section, cols, groupAt[i])
    end
    return y
end

---The pool, sub-grouped by what can be done with each row.
---@return number nextY
local function placePoolRows(y, section, needle)
    -- The stale rows here are the icon overrides no row anywhere answers to
    -- (another class's spell in a shared profile); every other leftover is a
    -- row of the section that saved it.
    local groups = {}
    for g = 1, #POOL_GROUP_LABELS do groups[g] = {} end
    -- Rank groups key on kind and bucket, so none spans two of these.
    local shown, groupAt = collapseRanks(section.id, section.rows,
        function(row) return rowVisible(row, needle) end, rankPick)
    for s = 1, #shown do
        local i = shown[s]
        local list = groups[poolGroupOf(section.rows[i])]
        list[#list + 1] = i
    end
    local cols = sectionColumns(section)
    local any = false
    for g = 1, #groups do
        local rows = groups[g]
        if #rows > 0 then
            any = true
            y = placeLabel(y, L[POOL_GROUP_LABELS[g]], ROW_INDENT, 1, 0.82, 0)
            for r = 1, #rows do
                local i = rows[r]
                y = placeRow(y, section.rows[i], r, nil, nil, nil, nil, section, cols, groupAt[i])
            end
        end
    end
    if not any then
        y = placeLabel(y, L["TRACKING_POOL_EMPTY"], ROW_INDENT + 4, 0.5, 0.5, 0.5)
    end
    return y
end

---Scroll to `focusWant` once the scroll range reaches it.  SetVerticalScroll
---goes through the scrollbar, which clamps to its maximum
---(ScrollFrame_OnVerticalScroll → scrollbar:SetValue), and Blizzard moves that
---maximum only in OnScrollRangeChanged — so a render that just grew the
---content leaves the request here, and the OnScrollRangeChanged hook (Build)
---calls back once the range covers it.  Blizzard floors the range: 1 px slack.
local function applyFocus()
    if not focusWant or not scrollFrame then return end
    if scrollFrame:GetVerticalScrollRange() + 1 < focusWant then return end
    scrollFrame:SetVerticalScroll(focusWant)
    pendingFocus, focusWant = nil, nil
end

---Lay out every section from the last model read.  View-only: filter and
---collapse changes come straight here without re-reading the model.
render = function()
    if not scrollChild or not notReadyLabel then return end
    -- Re-pooling reassigns every row frame, the drag's source included.
    if dragRow then endDrag() end
    for i = 1, headerUsed do headerPool[i]:Hide() end
    for i = 1, rowUsed do rowPool[i]:Hide() end
    for i = 1, labelUsed do labelPool[i]:Hide() end
    for i = 1, addUsed do addPool[i].widget:Hide() end
    headerUsed, rowUsed, labelUsed, addUsed = 0, 0, 0, 0
    wipe(sectionTop)

    notReadyLabel:SetShown(not modelReady)
    if not modelReady then
        scrollChild:SetHeight(1)
        return
    end

    local needle = currentNeedle()
    local y = 0
    for s = 1, #sections do
        local section = sections[s]
        local header = acquireHeader()
        header._cue_section = section
        sectionTop[section.id] = y
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
        header:SetPoint("RIGHT", scrollChild, "RIGHT", -4, 0)

        -- shown/total whenever a search or "Show unlearned" off hides rows.
        local count, shown = #section.rows, 0
        for i = 1, count do
            if rowVisible(section.rows[i], needle) then shown = shown + 1 end
        end
        if shown ~= count then
            header.title:SetText(string.format("%s  |cffaaaaaa(%d/%d)|r", titleById[section.id], shown, count))
        else
            header.title:SetText(string.format("%s  |cffaaaaaa(%d)|r", titleById[section.id], count))
        end
        -- A disabled frame greys out but stays open to edit.
        if section.disabled then
            header.title:SetTextColor(0.5, 0.5, 0.5)
        else
            header.title:SetTextColor(1, 0.82, 0)
        end
        local isCollapsed = collapsed[section.id] == true
        header.chevron:SetText(isCollapsed and "+" or "-")

        local isCdm = section.kind == "cdm"
        header.resetOrder.widget:SetShown(isCdm)
        header.resetMoves.widget:SetShown(isCdm)
        if isCdm then
            header.resetOrder:SetEnabled(private.TrackingModel.HasOrder(section.id))
            header.resetMoves:SetEnabled(private.TrackingModel.HasMoves(section.bucket))
        end
        header:Show()
        y = y + HEADER_HEIGHT

        if not isCollapsed then
            if section.kind == "pool" then
                y = placePoolRows(y, section, needle)
            else
                y = placeSectionRows(y, section, needle)
                if section.bucket then
                    local entry = acquireAddEntry()
                    -- The pooled box follows section order: text typed for
                    -- another section must not follow it here.
                    if entry._cue_sectionId ~= section.id then entry.widget:SetText("") end
                    entry._cue_sectionId = section.id
                    entry._cue_bucket = section.bucket
                    entry._cue_placeholder:SetText(section.bucket == "cooldown"
                        and L["TRACKING_ADD_SPELL"] or L["TRACKING_ADD_AURA"])
                    entry._cue_itemBtn.widget:SetShown(section.kind == "af" and section.frameType == "spells")
                    entry.widget:ClearAllPoints()
                    entry.widget:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", ROW_INDENT, -y - 4)
                    entry.widget:Show()
                    y = y + ADD_LINE_HEIGHT
                end
            end
        end
        y = y + SECTION_GAP
    end
    scrollChild:SetHeight(math.max(1, y))

    -- A section id the model does not have (a frame deleted meanwhile) drops
    -- the request rather than scrolling there on some later render.  The
    -- offset is computed from the height just set, not read back: the range
    -- the scroll is clamped to catches up only in OnScrollRangeChanged, where
    -- applyFocus finishes the job if it cannot yet.
    if pendingFocus then
        local top = sectionTop[pendingFocus]
        if top then
            focusWant = math.min(top, math.max(0, y - scrollFrame:GetHeight()))
            applyFocus()
        else
            pendingFocus = nil
        end
    end
end

---Re-read the model, building it first if nothing else has: with no CDM
---tracker or Additional Frame enabled, OnCDMSpellsChanged rebuilds nothing, and
---this tab's own edits drop the model.  ResolveNow declines before
---LOADING_SCREEN_DISABLED; BuildSections then returns not-ready, and the
---OnCDMSpellsChanged registration brings a rebuild once the data lands.
local function refreshData()
    private.CDMDataSource.ResolveNow()
    local built, ready = private.TrackingModel.BuildSections()
    sections = built
    modelReady = ready and true or false
    wipe(titleById)
    for i = 1, #sections do titleById[sections[i].id] = sectionTitle(sections[i]) end
end

---Re-read the model and re-render.
local function rebuild()
    refreshData()
    render()
end

---Rebuilds coalesce to one per frame (the LibSharedMedia batching idiom,
---patterns.md "Events & callbacks"): BuildSections walks the whole spellbook,
---and SPELLS_CHANGED arrives in storms.
local rebuildPending = false
requestRebuild = function()
    if rebuildPending then return end
    rebuildPending = true
    C_Timer.After(0, function()
        rebuildPending = false
        -- The rendered rows are the drag's hit targets: hold the rebuild
        -- until endDrag re-requests it.
        if dragRow then
            rebuildAfterDrag = true
            return
        end
        if panelFrame and panelFrame:IsVisible() then rebuild() end
    end)
end

---Shared by every listener this tab registers while shown.
local function onDataChanged()
    requestRebuild()
end

---A drag must not commit into a profile other than the one it started on.
local function onProfileChanged()
    endDrag()
    requestRebuild()
end

---True while the listeners below are registered.  SPELL_TEXT_UPDATE is there
---for a row's rank, which reads "" until the spell's data has loaded.
local listening = false

---Register the listeners and rebuild once, if the panel is the selected tab
---and they are not already live.  Called from the panel's OnShow and, since
---a tab switch is not the only way the tab comes back, from the Options
---window's own OnShow (Options.lua CreateOptionsFrame).  Idempotent: both
---can fire for one reopen.
function trackingTab.Attach()
    if listening or not panelFrame or not eventFrame or not panelFrame:IsShown() then return end
    listening = true
    private.Callback.Register("OnCDMSpellsChanged", onDataChanged)
    private.Callback.Register("OnProfileChanged", onProfileChanged)
    -- The Alerts buttons' markers follow the alert model, which lands a
    -- debounce after the edit or Cooldown Manager change that moved it.
    private.Callback.Register("OnAlertModelRebuilt", onDataChanged)
    -- A by-name row's badge goes from "resolving" to its id count.
    private.Callback.Register("OnSpellNamesResolved", onDataChanged)
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterEvent("SPELL_TEXT_UPDATE")
    rebuild()
end

---Drop the listeners.  Called from the panel's OnHide and from the Options
---window's OnHide, so closing the window with this tab selected never
---leaves them registered.  Idempotent.
function trackingTab.Detach()
    -- Before the guard: a drag ends with the panel whatever the listeners do.
    endDrag()
    if not listening or not eventFrame then return end
    listening = false
    private.Callback.Unregister("OnCDMSpellsChanged", onDataChanged)
    private.Callback.Unregister("OnProfileChanged", onProfileChanged)
    private.Callback.Unregister("OnAlertModelRebuilt", onDataChanged)
    private.Callback.Unregister("OnSpellNamesResolved", onDataChanged)
    eventFrame:UnregisterEvent("SPELLS_CHANGED")
    eventFrame:UnregisterEvent("SPELL_TEXT_UPDATE")
    GameTooltip:Hide()
end

---Expand the section `componentName` draws into and scroll it into view —
---the Trackers tab's "Edit spells in the Tracking tab" button, through
---Options.OpenOptionsPanel(TRACKING_TAB_INDEX, componentName).  Takes the
---names the Options panels know a tracker by: a CDM tracker's component name
---(which is also its section id) or "AdditionalFrame_<id>" (section "af:<id>").
---A model that is not ready yet keeps the request for its first ready render.
---@param componentName string
function trackingTab.FocusSection(componentName)
    local afId = componentName:match("^AdditionalFrame_(.+)$")
    local sectionId = afId and ("af:" .. afId) or componentName
    collapsed[sectionId] = false
    pendingFocus = sectionId
    if panelFrame and panelFrame:IsVisible() then render() end
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

---Build the Tracking tab inside `panel`.  Listeners are live only while the
---panel is visible: Attach on show, Detach on hide (see both).
---@param panel frame
function trackingTab.Build(panel)
    panelFrame = panel

    -- The rank menu's writes that take a rank out of another tracker or frame
    -- (confirmRankChange).  `text_arg1` is the whole question; `data` the write.
    StaticPopupDialogs["CLASSUIENHANCED_RANK_CONFIRM"] = {
        text = "%s",
        button1 = YES,
        button2 = NO,
        OnAccept = function(_, swap) swap() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    -- Top bar: search and "Show unlearned".  Blizzard's Cooldown Manager
    -- settings sit in the Options header right above.
    local search = framework:CreateTextEntry(panel, function() end, 220, 22, nil, frameName .. "TrackingSearch")
    search:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -5)
    search.widget:SetMaxLetters(64)
    search.widget:SetAutoFocus(false)
    local searchPlaceholder = search.widget:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    searchPlaceholder:SetPoint("LEFT", search.widget, "LEFT", 4, 0)
    searchPlaceholder:SetText(L["AF_SPELL_FILTER_PLACEHOLDER"])
    search.widget:HookScript("OnTextChanged", function(self)
        local text = self:GetText()
        searchPlaceholder:SetShown(text == "")
        searchText = text
        render()
    end)

    local unlearnedToggle = framework:CreateSwitch(panel, function(_, _, value)
        showUnlearned = value and true or false
        render()
    end, showUnlearned, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        framework:GetTemplate("switch", private.UIDefaults.presets.checkbox))
    unlearnedToggle:SetPoint("LEFT", search.widget, "RIGHT", 16, 0)
    unlearnedToggle:SetAsCheckBox()
    unlearnedToggle:SetTooltip(L["TRACKING_SHOW_UNLEARNED_DESC"])
    local unlearnedLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    unlearnedLabel:SetPoint("LEFT", unlearnedToggle.widget, "RIGHT", 5, 0)
    unlearnedLabel:SetText(L["TRACKING_SHOW_UNLEARNED"])

    -- Which layer Move, Remove, reordering and both Resets write
    -- (TrackingModel writeSpecKey, orderLayerKey).  A client with no spec system has only the all-specs
    -- layer, so the box would change nothing there.
    local allSpecsToggle = framework:CreateSwitch(panel, function(_, _, value)
        allSpecs = value and true or false
        private.TrackingModel.SetAllSpecs(allSpecs)
        render()
    end, allSpecs, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil,
        framework:GetTemplate("switch", private.UIDefaults.presets.checkbox))
    allSpecsToggle:SetPoint("LEFT", unlearnedLabel, "RIGHT", 16, 0)
    allSpecsToggle:SetAsCheckBox()
    allSpecsToggle:SetTooltip(L["TRACKING_ALL_SPECS_DESC"])
    local allSpecsLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    allSpecsLabel:SetPoint("LEFT", allSpecsToggle.widget, "RIGHT", 5, 0)
    allSpecsLabel:SetText(L["TRACKING_ALL_SPECS"])
    if not private.CDMDataSource.GetSpecLayerKey() then
        allSpecsToggle.widget:Hide()
        allSpecsLabel:Hide()
    end

    -- Expand / Collapse all, right-aligned with the scroll box's edge.
    local function setAllCollapsed(value)
        if dragBusy() then return end
        for s = 1, #sections do collapsed[sections[s].id] = value end
        render()
    end
    local buttonTemplate = private.Templates.ButtonTemplate
    local expandAll = framework:CreateButton(panel, function() setAllCollapsed(false) end, 20, 22, L["TRACKING_EXPAND_ALL"], false, false, false, nil, nil)
    expandAll:SetTemplate(buttonTemplate)
    fitButton(expandAll)
    expandAll:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -30, -5)
    local collapseAll = framework:CreateButton(panel, function() setAllCollapsed(true) end, 20, 22, L["TRACKING_COLLAPSE_ALL"], false, false, false, nil, nil)
    collapseAll:SetTemplate(buttonTemplate)
    fitButton(collapseAll)
    collapseAll:SetPoint("RIGHT", expandAll.widget, "LEFT", -4, 0)

    -- The Trackers tab's canvas scroll box; -30 on the right leaves room for
    -- the scroll bar, which sits outside the frame (as on the Colors tab).
    scrollFrame = framework:CreateCanvasScrollBox(panel, nil, frameName .. "TrackingScrollFrame", {
        smooth_scrolling = false,
        smooth_scrolling_speed = 20,
        smooth_scrolling_acceleration_factor = 2,
        smooth_scrolling_acceleration = true,
        use_momentum = true,
        momentum_friction = 6,
        use_drag_scroll = true,
    })
    scrollFrame:SetPoint("TOPLEFT", search.widget, "BOTTOMLEFT", 0, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 5)
    scrollChild = scrollFrame.child
    scrollChild:SetWidth(private.Templates.OptionsPanel.width - 20 - 5 - 30)
    scrollChild:SetHeight(1)
    -- After Blizzard's own handler, which moves the scrollbar's maximum.
    scrollFrame:HookScript("OnScrollRangeChanged", applyFocus)

    notReadyLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notReadyLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, -8)
    notReadyLabel:SetText(L["TRACKING_NOT_READY"])
    notReadyLabel:SetTextColor(0.5, 0.5, 0.5)
    notReadyLabel:Hide()

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", onDataChanged)

    panel:HookScript("OnShow", trackingTab.Attach)
    panel:HookScript("OnHide", trackingTab.Detach)
end

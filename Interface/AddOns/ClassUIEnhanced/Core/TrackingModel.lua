---Tracking model: one data view over everything CUE can track — the four CDM
---trackers, every Additional Frame, the player's spellbook, and profile keys no
---live entry answers to any more — plus the actions that move, reorder, add and
---remove those entries.
---
---Pure data: no frames, no widgets.  The Options "Tracking" tab
---renders `BuildSections()` and calls the actions; tests/trackingmodel_check.lua
---drives the same file under a stub environment.  Full contract in
---Core/TrackingModel.md.
---
---Loads after CDMDataSource/CDMAlerts and BEFORE ComponentManager, the
---components and AdditionalFrameManager, so every `private.X` below is read at
---CALL time, never captured at file load.

local _
---@type string, private
local addonName, private = ...

---@class private : table
---@field TrackingModel trackingmodel

---@class trackingmodel : table
---@field BuildSections fun(): tracking_section[], boolean
---@field GetValidTargets fun(row: tracking_row): string[]
---@field Move fun(row: tracking_row, targetSectionId: string, index: number|nil, ranks: "highest"|nil): boolean  a whole spell-rank family's representative moves every rank
---@field Reorder fun(sectionId: string, fromIndex: number, toIndex: number): boolean
---@field AddFromSpellbook fun(spellID: number, targetSectionId: string): boolean
---@field AddAuraByID fun(spellID: number, targetSectionId: string): boolean
---@field GetCopyTargets fun(row: tracking_row, sections: tracking_section[]|nil): string[], boolean|nil  sections of the other bucket a `cdm`/`custom` row may be copied to; empty, with `true`, once the spell is on any of them
---@field Copy fun(row: tracking_row, targetSectionId: string): boolean  add the row's key there as a custom entry; the row stays
---@field GetAddonSourceChoices fun(targetSectionId: string): tracking_addon_choice[]
---@field AddAddonSource fun(id: number, source: string, targetSectionId: string): boolean
---@field Remove fun(row: tracking_row): boolean
---@field CanRemove fun(row: tracking_row): boolean
---@field SwapRank fun(current: tracking_row, chosen: tracking_row, index: number): boolean  the rank menu: `chosen` takes `current`'s place, `current` goes to Not tracked
---@field CanSwapRank fun(current: tracking_row, chosen: tracking_row): boolean
---@field SetSingleRank fun(chosen: tracking_row, sectionId: string, index: number|nil): boolean  a tracker's rank menu: `chosen` is the only rank of its spell there, the others go to Not tracked
---@field CanSetSingleRank fun(chosen: tracking_row, sectionId: string): boolean
---@field SetFamilyMode fun(row: tracking_row, sectionId: string): boolean  a tracker's rank menu, "All ranks" / "Highest": every rank of the spell comes to the section
---@field CanSetFamilyMode fun(row: tracking_row, sectionId: string): boolean
---@field SetCustomRank fun(row: tracking_row, spellID: number|nil): boolean  a custom cooldown row: that exact rank, or nil for "Highest"
---@field SetRestrictToPlayer fun(row: tracking_row, restricted: boolean): boolean
---@field SetCustomSpec fun(row: tracking_row, on: boolean): boolean  a custom aura row's "This spec": show it on the current spec or not (with "All specs" ticked, on = every spec)
---@field SetCustomByName fun(row: tracking_row, on: boolean): boolean  a custom aura row's "Match by name": every spell id carrying its name, or exactly its id
---@field CanSetCustomByName fun(row: tracking_row, on: boolean): boolean
---@field SetIconOverride fun(row: tracking_row, textureOrSpellID: number|string): boolean
---@field ClearIconOverride fun(row: tracking_row): boolean
---@field SetAllSpecs fun(on: boolean)  the Tracking tab's "All specs" box: category writes, icon-order writes, Reset moves and Reset order use the all-specs layer, and a custom aura is added for every spec
---@field HasMoves fun(bucket: "cooldown"|"aura"): boolean
---@field ResetMoves fun(bucket: "cooldown"|"aura"): boolean
---@field HasOrder fun(sectionId: string): boolean  would ResetOrder(sectionId) clear anything?
---@field ResetOrder fun(sectionId: string): boolean  "Reset to default order": drop this spec's own icon order, or empty the all-specs one with "All specs" ticked or no spec system
---@field CanForceActive fun(row: tracking_row): boolean  a CDM row outside a rank family that is inactive (learned, not drawn) or already forced
---@field SetForceActive fun(row: tracking_row, value: boolean): boolean  "Force active": draw the entry although Blizzard's CDM counts it inactive (CDMDataSource.applyForcedActive)

---@class tracking_row : table
---@field key number  tracker key: base spellID, a sibling entry's linked[1], a synthetic negative item key, an AF addon-source id, or a spellbook ACTIVE id
---@field kind "cdm"|"item"|"assigned"|"spellbook"|"custom"|"stale"
---@field bucket "cooldown"|"aura"|nil  nil for spellbook and stale rows
---@field sectionId string
---@field known boolean
---@field learned boolean  the character has the spell: `known`, or the key (a ranked spell: its name and rank) is in the spellbook.  Not what the tracker draws — that is `known`
---@field family table|nil  CDM rows: the spell-rank family the entry is a rank of (CDMDataSource.GetRankFamily): `{ rep, bucket, whole, highest, members }`.  A whole family's representative row stands for every rank
---@field single boolean|nil  a write covers this rank alone, even when it is a whole family's representative (SetSingleRank)
---@field forced boolean|nil  CDM rows: the entry is flagged "Force active" (`cdm_category_overrides.active[bucket][key]`), drawn or not
---@field name string|nil
---@field rank string|nil  the spell's rank subtext ("Rank 3") where the client has ranks
---@field texture number|string|nil  the icon_overrides texture when one resolves
---@field inSpellbook boolean
---@field hasIconOverride boolean
---@field cooldownID number|nil  CDM rows: the first cooldownID resolving to (key, bucket)
---@field source string|nil  AF addon-source rows: "Trinket"|"Consumable"|"Racial"
---@field listIndex number|nil  position in the host list: assigned_spells (AF cdm/item/assigned rows) or custom_spells (custom rows)
---@field duplicateOf number|nil  custom rows: the key of a row in the same section that already draws this aura; assigned rows: the key of the row an earlier entry already claimed
---@field restrictToPlayer boolean|nil  custom rows: the entry's `restrict_to_player` (nil in the profile reads as true)
---@field thisSpec boolean|nil  custom rows of an aura section: the entry shows on the current spec (CustomSpells.IsOnCurrentSpec)
---@field ranks "highest"|nil  custom rows: the entry's `ranks` (CustomSpells: drawn as the highest learned rank)
---@field byName boolean|nil  custom rows of an aura section: the entry's `by_name` (matches every id carrying its name)
---@field byNameCount number|nil  by-name rows: how many spell ids carry the name, once resolved (profile `aura_name_cache`)
---@field byNamePending boolean|nil  by-name rows: SpellNameScan is still collecting the name's ids
---@field refs table[]|nil  stale rows: { sectionId, list } per profile list naming the key
---@field untracked boolean|nil  section stale rows: the key is no row at all on this spec (another spec's spell)

---@class tracking_section : table
---@field id string  "CooldownTracker"|"UtilitiesTracker"|"BuffTracker"|"BuffTrackerBars"|"af:<id>"|"pool"
---@field kind "cdm"|"af"|"pool"
---@field bucket "cooldown"|"aura"|nil
---@field category number|nil  cdm sections: the CDM category the tracker draws
---@field componentName string|nil
---@field afId string|nil
---@field frameType string|nil
---@field name string|nil  AF sections: the user's label
---@field disabled boolean|nil  AF sections: the frame is switched off.  Its rows stay here and stay editable; meanwhile it routes nothing, so its spells draw in their trackers
---@field rows tracking_row[]

---@class tracking_addon_choice : table
---@field id number  the assigned_spells id: equip slot, consumable category id, or racial spellID
---@field source "Trinket"|"Consumable"|"Racial"
---@field category string|nil  Consumable: ConsumableTracker's category key ("combat", ...)
---@field name string|nil  the equipped trinket's or the racial's name; nil where the UI owns the wording
---@field texture number|string|nil
---@field ownerAfId string|nil  the spells frame whose assigned_spells already holds it, if any

---The four built-in trackers, in section order.  `routeKey` is the
---AdditionalFrameManager routing domain BuildComponentSpellMaps takes.
local CDM_SECTIONS = {
    { id = "CooldownTracker", viewerKey = "CooldownEssential", routeKey = "Essential", bucket = "cooldown" },
    { id = "UtilitiesTracker", viewerKey = "CooldownUtility", routeKey = "Utility", bucket = "cooldown" },
    { id = "BuffTracker", viewerKey = "BuffIcon", routeKey = "BuffIcon", bucket = "aura" },
    { id = "BuffTrackerBars", viewerKey = "BuffBar", routeKey = "BuffBar", bucket = "aura" },
}

local POOL = "pool"

---The per-spell exclude lists a tracker or frame saves (spell ids, one list
---per setting): stale rows, Remove and a CDM move treat them alike.
local EXCLUDE_LISTS = { "pandemic_glow_excludes", "active_swipe_excludes" }

---The per-spell colour maps a tracker or frame saves (spell id -> {r,g,b,a}):
---the bar fill, the icon border and the missing-buff glow.  Stale rows and
---Remove treat them alike.
local COLOR_MAPS = { "spell_colors", "spell_borders", "missing_glow" }

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

---@param sectionId string|nil
---@return table|nil spec  a CDM_SECTIONS row
local function cdmSectionSpec(sectionId)
    for i = 1, #CDM_SECTIONS do
        if CDM_SECTIONS[i].id == sectionId then return CDM_SECTIONS[i] end
    end
    return nil
end

---@param spec table  a CDM_SECTIONS row
---@return number|nil
local function categoryOf(spec)
    return private.Enum.CooldownViewerCategoryIDs[spec.viewerKey]
end

---@param sectionId string|nil
---@return string|nil
local function afIdOf(sectionId)
    return type(sectionId) == "string" and sectionId:match("^af:(.+)$") or nil
end

---@param afId string|nil
---@return additional_frame_profile|nil
local function afSettings(afId)
    local afs = private.profile and private.profile.additional_frames
    return afId and afs and afs[afId] or nil
end

---Which bucket an Additional Frame routes: `spells` frames the cooldown domain,
---`buffs`/`bar` frames the aura domain (AdditionalFrameManager.rebuildSpellRouting).
---@param settings additional_frame_profile
---@return "cooldown"|"aura"|nil
local function afBucket(settings)
    if settings.frame_type == "spells" then return "cooldown" end
    if settings.frame_type == "buffs" or settings.frame_type == "bar" then return "aura" end
    return nil
end

---@param sectionId string
---@return "cooldown"|"aura"|nil
local function sectionBucket(sectionId)
    local spec = cdmSectionSpec(sectionId)
    if spec then return spec.bucket end
    local settings = afSettings(afIdOf(sectionId))
    return settings and afBucket(settings) or nil
end

---The component name CustomSpells and ComponentManager know the section by.
---@param sectionId string
---@return string|nil
local function componentNameFor(sectionId)
    if cdmSectionSpec(sectionId) then return sectionId end
    local afId = afIdOf(sectionId)
    return afId and ("AdditionalFrame_" .. afId) or nil
end

---The settings table holding the section's `custom_spells` (and, for an AF,
---`assigned_spells`; for a CDM tracker, `priority_order`).
---@param sectionId string
---@return table|nil
local function hostSettings(sectionId)
    if cdmSectionSpec(sectionId) then
        local comps = private.profile and private.profile.components
        return comps and comps[sectionId] or nil
    end
    return afSettings(afIdOf(sectionId))
end

---(id, source) of an `assigned_spells` entry: a bare spellID (legacy) or an
---{id, source} pair.  AdditionalFrameManager's own `normalizeEntry` is
---file-local, so this repeats its two-line shape rather than reaching into
---that file.
---@param entry any
---@return number|nil id, string|nil source
local function entryId(entry)
    if type(entry) == "number" then return entry, nil end
    if type(entry) == "table" then return entry[1], entry[2] end
    return nil, nil
end

---Passed to Util.ResolveByBaseOrOverride: the id itself when `set` has it.
---@param id number
---@param set table
---@return number|nil
local function keyIn(id, set)
    if set[id] ~= nil then return id end
    return nil
end

---Passed to Util.ResolveByBaseOrOverride: true when `id` IS `key`.
---@param id number
---@param key number
---@return true|nil
local function idEquals(id, key)
    if id == key then return true end
    return nil
end

---Does `id` name the same CDM entry as `key` (own id, its base, or the base's
---override)?  The equivalence every per-spell lookup in the addon uses.
---@param id number
---@param key number
---@return boolean
local function sameEntry(id, key)
    if private.Util.ResolveByBaseOrOverride(id, idEquals, key) == true then return true end
    -- Any rank of a whole spell-rank family names the family, whose key is its
    -- representative (CDMDataSource.applyRankFamilies).
    local cdm = private.CDMDataSource
    return cdm.GetFamilyRep(id, "cooldown") == key or cdm.GetFamilyRep(id, "aura") == key
end

---ConsumableTracker's category key ("combat", ...) for an AF Consumable
---entry's numeric category id, or nil.
---@param id number
---@return string|nil
local function consumableCategoryOf(id)
    local ct = private.ConsumableTracker
    if not ct then return nil end
    for catKey, catID in pairs(ct.GetCategoryIDs()) do
        if catID == id then return catKey end
    end
    return nil
end

---A consumable category's icon: its first family's, as the retired Additional
---Frames spell list and picker showed it.
---@param catKey string|nil
---@return number|string|nil
local function consumableCategoryIcon(catKey)
    local ct = private.ConsumableTracker
    if not ct or not catKey then return nil end
    local families = ct.GetFamilies()
    for i = 1, #families do
        local family = families[i]
        if family.category == catKey then
            return family.icon or C_Item.GetItemIconByID(family.itemIds[#family.itemIds])
        end
    end
    return nil
end

---A spell's rank ("Rank 3") where the client has spell ranks: Util.SpellRank.
---The subtext is "" until the spell's data has loaded; the Tracking tab
---re-reads on SPELL_TEXT_UPDATE.
---@param spellID number
---@return string|nil
local function rankOf(spellID)
    return private.Util.SpellRank(spellID)
end

---Name, texture and rank for a key.  No localized fallbacks: those are the
---UI's to choose.
---@param key number
---@param source string|nil  an AF addon-source tag
---@return string|nil name, number|string|nil texture, string|nil rank
local function describeKey(key, source)
    if source == "Trinket" then
        local itemID = GetInventoryItemID("player", key)
        return itemID and C_Item.GetItemNameByID(itemID) or nil,
            itemID and C_Item.GetItemIconByID(itemID) or nil
    elseif source == "Consumable" then
        return nil, consumableCategoryIcon(consumableCategoryOf(key))
    end
    local iconSource = private.CDMDataSource.GetIconSource(key)
    if iconSource then
        if iconSource.equipSlot then
            local itemID = GetInventoryItemID("player", iconSource.equipSlot)
            return itemID and C_Item.GetItemNameByID(itemID) or nil,
                (itemID and C_Item.GetItemIconByID(itemID)) or iconSource.icon
        end
        return nil, iconSource.icon
    end
    if key <= 0 then return nil, nil end
    local displayID = private.compat.GetOverrideSpell(key) or key
    return C_Spell.GetSpellName(displayID), C_Spell.GetSpellTexture(displayID), rankOf(displayID)
end

---Is (bucket, key) flagged "Force active" (`cdm_category_overrides.active`)?
---@param bucket "cooldown"|"aura"
---@param key number
---@return boolean
local function isForced(bucket, key)
    local t = private.profile.cdm_category_overrides
    local active = type(t) == "table" and t.active
    local map = type(active) == "table" and active[bucket]
    return type(map) == "table" and map[key] == true
end

---Build one row with the fields every kind carries.
---@return tracking_row
local function newRow(key, kind, bucket, sectionId, known, source)
    local name, texture, rank = describeKey(key, source)
    -- An addon-source id is an equip slot / consumable category, not a spell,
    -- so it has no icon_overrides entry of its own.
    local override = not source and private.Util.ResolveIconOverride(key) or nil
    return {
        key = key,
        kind = kind,
        bucket = bucket,
        sectionId = sectionId,
        known = known and true or false,
        learned = known and true or false,
        name = name,
        rank = rank,
        texture = override or texture,
        hasIconOverride = override ~= nil,
        inSpellbook = false,
        source = source,
    }
end

---@param a tracking_row
---@param b tracking_row
local function byListIndex(a, b)
    return (a.listIndex or 0) < (b.listIndex or 0)
end

---@param a tracking_row
---@param b tracking_row
local function byKey(a, b)
    return a.key < b.key
end

-- ---------------------------------------------------------------------------
-- BuildSections
-- ---------------------------------------------------------------------------

---Every section with its rows, in display order; see Core/TrackingModel.md.
---
---**Never forces CDMDataSource's lazy build.**  Returns `{}, false` until the
---model is resolved (patterns.md "Lazy caches vs init order"): a caller in the
---PLAYER_LOGIN → LOADING_SCREEN_DISABLED window would otherwise cache an empty
---model for the session.  A caller re-asks on OnCDMSpellsChanged.
---@return tracking_section[] sections, boolean ready
local function buildSections()
    local cdm = private.CDMDataSource
    local profile = private.profile
    if not profile or not cdm.IsResolved() then return {}, false end
    local resolve = private.Util.ResolveByBaseOrOverride
    -- BuildComponentSpellMaps' own gate: with it off, a CDM tracker draws only
    -- its custom spells, so its CDM rows belong in the pool.
    local autoFetch = profile.cdm_auto_fetch

    local sections, sectionById = {}, {}
    for i = 1, #CDM_SECTIONS do
        local spec = CDM_SECTIONS[i]
        local s = { id = spec.id, kind = "cdm", bucket = spec.bucket, category = categoryOf(spec),
            componentName = spec.id, rows = {} }
        sections[#sections + 1] = s
        sectionById[s.id] = s
    end
    local sectionForCategory = {}
    for i = 1, #CDM_SECTIONS do
        sectionForCategory[sections[i].category] = sections[i].id
    end
    local afm = private.AdditionalFrameManager
    local afIds = afm and afm.GetAllFrameIds() or {}
    for i = 1, #afIds do
        local settings = afSettings(afIds[i])
        if settings then
            local s = { id = "af:" .. afIds[i], kind = "af", bucket = afBucket(settings),
                componentName = "AdditionalFrame_" .. afIds[i], afId = afIds[i],
                frameType = settings.frame_type, name = settings.name,
                disabled = not settings.enabled, rows = {} }
            sections[#sections + 1] = s
            sectionById[s.id] = s
        end
    end
    local pool = { id = POOL, kind = "pool", rows = {} }

    -- 1. CDM rows, one per (key, bucket).  A key repeats across the two buckets
    --    (Sweeping Strikes is an Essential AND a BuffIcon entry) and each is its
    --    own row; within a bucket the merge shape collapses to the first entry.
    --    Hidden entries (-1/-2, Blizzard's or CUE's) are fetched too: they are
    --    the pool rows a move can bring back.  With cdm_auto_fetch off every
    --    entry is a pool row unless an Additional Frame claims it below: the
    --    trackers draw none of them.
    --    Entries the character does not have (another spec's spell, an untaken
    --    talent, every entry on WoW Forever) are rows too, `known = false`, so
    --    "Show unlearned" can list them and a move can place one ahead of time.
    --    Two passes, known first: a key's row is its KNOWN entry whenever it
    --    has one, and only a known COOLDOWN row takes a spellbook spell in
    --    (cdmRowsByKey): a spellbook spell is a cast, and an aura entry of the
    --    same id tracks the buff, not the spell.
    local cdmRows = {}
    local rowByKey = { cooldown = {}, aura = {} }
    local cdmRowsByKey = {}
    local cats = Enum.CooldownViewerCategory
    local scan = { sections[1].category, sections[2].category, sections[3].category,
        sections[4].category, cats.HiddenActive or -1, cats.HiddenPassive or -2 }
    for pass = 1, 2 do
        local knownPass = pass == 1
        for c = 1, #scan do
            local ids = cdm.GetTrackedCooldownIDs(scan[c], true, nil, not knownPass)
            for i = 1, #ids do
                local id = ids[i]
                -- `drawn`, not Blizzard's isKnown: a row is known when its
                -- tracker draws it, which inside a spell-rank family depends on
                -- where the ranks sit (CDMDataSource.applyRankFamilies).
                local key, _, _, _, known = cdm.GetResolvedEntry(id)
                local display = cdm.GetDisplayCategory(id)
                local isItem = key ~= nil and cdm.GetIconSource(key) ~= nil
                -- An item-backed entry has no bucket of its own (its default is an
                -- item category), so it is filed by where it is displayed.
                local bucket = isItem and cdm.GetCategoryBucket(display)
                    or cdm.GetCategoryBucket(cdm.GetDefaultCategory(id))
                if key and bucket and not rowByKey[bucket][key] and (knownPass or not known) then
                    local row = newRow(key, isItem and "item" or "cdm", bucket,
                        autoFetch and sectionForCategory[display] or POOL, knownPass)
                    row.cooldownID = id
                    if not isItem then
                        row.family = cdm.GetRankFamily(key, bucket)
                        row.forced = isForced(bucket, key)
                    end
                    rowByKey[bucket][key] = row
                    cdmRows[#cdmRows + 1] = row
                    if knownPass and bucket == "cooldown" then
                        local list = cdmRowsByKey[key]
                        if not list then
                            list = {}
                            cdmRowsByKey[key] = list
                        end
                        list[#list + 1] = row
                    end
                end
            end
        end
    end

    --    An entry an Additional Frame routes is drawn by that frame, so the row
    --    lives in its section.  A disabled frame routes nothing
    --    (rebuildSpellRouting), so its entry is still drawn by its tracker:
    --    the row stays there, with the tracker's order, colour and pandemic
    --    controls, and the frame lists a copy.  Enabled frames claim first, so
    --    an entry both hold is the enabled one's row.
    local afRows = {}
    local staleRefs = {}
    local claimed = {}
    local claimOrder = {}
    for pass = 1, 2 do
        for i = 1, #afIds do
            local settings = afSettings(afIds[i])
            if settings and (settings.enabled and true or false) == (pass == 1) then
                claimOrder[#claimOrder + 1] = afIds[i]
            end
        end
    end
    for i = 1, #claimOrder do
        local sid = "af:" .. claimOrder[i]
        local settings = afSettings(claimOrder[i])
        local enabled = settings.enabled
        local bucket = afBucket(settings)
        local assigned = settings.assigned_spells
        if bucket and type(assigned) == "table" then
            for idx = 1, #assigned do
                local id, source = entryId(assigned[idx])
                if type(id) == "number" then
                    if source and afm.IsAddonIconSource(source) then
                        local row = newRow(id, "item", bucket, sid, true, source)
                        row.listIndex = idx
                        afRows[#afRows + 1] = row
                    else
                        -- Any rank of a whole spell-rank family claims the
                        -- family: its representative's row, the key the frame
                        -- draws it under (AdditionalFrameManager.linkedOwner).
                        local rep = cdm.GetFamilyRep(id, bucket)
                        local matched = (rep and rowByKey[bucket][rep] and rep)
                            or resolve(id, keyIn, rowByKey[bucket])
                        local row = matched and rowByKey[bucket][matched]
                        local other = bucket == "cooldown" and "aura" or "cooldown"
                        if row and not claimed[row] then
                            claimed[row] = true
                            local frameRow = row
                            if not enabled then
                                frameRow = {}
                                for k, v in pairs(row) do frameRow[k] = v end
                                afRows[#afRows + 1] = frameRow
                                -- The spellbook fold (step 2) marks it too.
                                local list = cdmRowsByKey[row.key]
                                if list and row.known and bucket == "cooldown" then
                                    list[#list + 1] = frameRow
                                end
                            end
                            frameRow.sectionId = sid
                            frameRow.listIndex = idx
                            -- The family's other ranks go with it: the frame draws
                            -- them all, and left behind they would list as a
                            -- second, undrawn copy of the spell in the tracker.
                            local family = row.family
                            if enabled and family and family.whole and family.rep == row.key then
                                for m = 1, #family.members do
                                    local memberRow = rowByKey[bucket][family.members[m].key]
                                    if memberRow and memberRow ~= row and not claimed[memberRow] then
                                        claimed[memberRow] = true
                                        memberRow.sectionId = sid
                                    end
                                end
                            end
                            -- A spells frame draws only what IsCooldownSpellTracked
                            -- admits (Blizzard's Essential, Utility and
                            -- HiddenActive), so any other entry draws nothing.
                            -- An aura frame draws every id it is given
                            -- (buildAFAuraSpellMap), known to the CDM or not.
                            if bucket == "cooldown" then
                                frameRow.known = cdm.IsCooldownSpellTracked(matched) ~= false
                            else
                                frameRow.known = true
                            end
                        elseif row or resolve(id, keyIn, rowByKey[other]) or bucket == "aura" then
                            -- An entry naming a row an earlier entry claimed, a
                            -- CDM entry of the OTHER bucket (the retired
                            -- Additional Frames picker listed every category for
                            -- every frame type), or on an aura frame any id at
                            -- all: buildAFAuraSpellMap draws what it is given,
                            -- CDM entry or not.  None is a row of its own above,
                            -- and none is stale — the frame still draws it — so
                            -- without this it would be listed nowhere and be
                            -- impossible to remove.
                            local extra = newRow(id, "assigned", bucket, sid, true)
                            extra.listIndex = idx
                            if row then
                                extra.duplicateOf = row.key
                            elseif bucket == "cooldown" then
                                -- buildAFIconSpellMap's own gate; an aura frame
                                -- draws any id (buildAFAuraSpellMap).
                                extra.known = cdm.IsCooldownSpellTracked(id) ~= false
                            end
                            afRows[#afRows + 1] = extra
                        else
                            -- A spells frame's entry no CDM cooldown row answers
                            -- to draws nothing (buildAFIconSpellMap).  Judged
                            -- against this frame's rows only: a spellbook or
                            -- custom row elsewhere does not list THIS entry.
                            staleRefs[#staleRefs + 1] = { key = id, sectionId = sid,
                                list = "assigned_spells", inSection = true, listIndex = idx }
                        end
                    end
                end
            end
        end
    end

    -- 2. Spellbook rows.  A spell whose base (actionID) or active (spellID) id
    --    is a CDM cooldown row folds into that row; anything else becomes a
    --    row keyed by the ACTIVE id — the one actually cast, and the only one a
    --    custom entry can match on a spec that overrides the base (api.md
    --    "Overridden spells: query the ACTIVE id").
    --    Every id walked, folded or not, is also what `learned` reads (step 3b).
    local spellbookRows, spellbookByKey = {}, {}
    local bookIds, bookRanks = {}, {}
    local bank = Enum.SpellBookSpellBank.Player
    for line = 1, private.compat.GetNumSpellBookSkillLines() do
        local lineInfo = private.compat.GetSpellBookSkillLineInfo(line)
        if lineInfo and not lineInfo.offSpecID and not lineInfo.shouldHide then
            local first = lineInfo.itemIndexOffset + 1
            for slot = first, lineInfo.itemIndexOffset + lineInfo.numSpellBookItems do
                local item = private.compat.GetSpellBookItemInfo(slot, bank)
                if item and item.itemType == Enum.SpellBookItemType.Spell
                    and not item.isPassive and not item.isOffSpec then
                    local base, active = item.actionID, item.spellID or item.actionID
                    if base then bookIds[base] = true end
                    if active then
                        bookIds[active] = true
                        local rank = rankOf(active)
                        if rank then bookRanks[(C_Spell.GetSpellName(active) or "") .. "\0" .. rank] = true end
                    end
                    -- A rank of a whole cooldown family is the family's row
                    -- (its representative): only that one is drawn.
                    local rep = (active and cdm.GetFamilyRep(active, "cooldown"))
                        or (base and cdm.GetFamilyRep(base, "cooldown"))
                    local owner = (rep and cdmRowsByKey[rep] and rep)
                        or (base and resolve(base, keyIn, cdmRowsByKey))
                        or (active and resolve(active, keyIn, cdmRowsByKey))
                    if owner then
                        local list = cdmRowsByKey[owner]
                        for r = 1, #list do list[r].inSpellbook = true end
                    elseif active and not spellbookByKey[active] then
                        local row = newRow(active, "spellbook", nil, POOL, true)
                        row.inSpellbook = true
                        spellbookByKey[active] = row
                        spellbookRows[#spellbookRows + 1] = row
                    end
                end
            end
        end
    end

    -- 2b. A ranked spellbook spell's unlearned ranks.  The spellbook lists only
    --     the ranks the character has, and no API lists a spell's others; the
    --     CDM, one entry per rank on WoW Forever, is the one place they are.
    --     So a ranked spellbook spell also lists, as unlearned spellbook rows,
    --     every CDM entry of its name with a rank and no cooldown row: a buff's
    --     cast is its own aura's id there (Mark of the Wild rank 1: 1126 for
    --     both), and where a cooldown row exists, that row is the cast already.
    local rankedNames = {}
    for i = 1, #spellbookRows do
        local row = spellbookRows[i]
        if row.rank and row.name then rankedNames[row.name] = true end
    end
    if next(rankedNames) then
        for i = 1, #cdmRows do
            local key = cdmRows[i].key
            if cdmRows[i].rank and rankedNames[cdmRows[i].name] and not bookIds[key]
                and not spellbookByKey[key] and not rowByKey.cooldown[key] then
                local row = newRow(key, "spellbook", nil, POOL, false)
                spellbookByKey[key] = row
                spellbookRows[#spellbookRows + 1] = row
            end
        end
    end

    -- 3. Custom rows, host by host.  One aura, one key: an entry whose id or
    --    identity owner is already a row key in its own section draws nothing
    --    new (BuildComponentSpellMaps / buildAFAuraSpellMap skip it), so it is
    --    still listed but marked `duplicateOf`.
    local keysBySection = {}
    local function noteKey(row)
        local keys = keysBySection[row.sectionId]
        if not keys then
            keys = {}
            keysBySection[row.sectionId] = keys
        end
        keys[row.key] = true
    end
    -- Only rows the host draws: BuildComponentSpellMaps skips a custom entry
    -- for a key it already draws, and an unknown CDM entry draws nothing, so a
    -- custom entry of that id is the one drawing it (Rejuvenation rank 1 on
    -- WoW Forever, whose condition never reads known).
    for i = 1, #cdmRows do
        if cdmRows[i].known then noteKey(cdmRows[i]) end
    end
    for i = 1, #afRows do
        if afRows[i].known then noteKey(afRows[i]) end
    end

    local customRows = {}
    local foldedSpellbook = {}
    for s = 1, #sections do
        local section = sections[s]
        if section.kind ~= "pool" then
            local settings = hostSettings(section.id)
            local list = settings and settings.custom_spells
            if type(list) == "table" then
                local knownMap = private.CustomSpells.GetSpellMapFor(section.componentName)
                local keys = keysBySection[section.id]
                for idx = 1, #list do
                    local entry = list[idx]
                    local key = type(entry) == "table" and entry.spellID or nil
                    if type(key) == "number" then
                        local row = newRow(key, "custom", section.bucket, section.id, knownMap[key] == true)
                        row.listIndex = idx
                        row.restrictToPlayer = entry.restrict_to_player ~= false
                        if section.bucket == "aura" then
                            row.thisSpec = private.CustomSpells.IsOnCurrentSpec(entry)
                            if entry.by_name then
                                row.byName = true
                                local name = C_Spell.GetSpellName(key)
                                local ids = name and private.profile.aura_name_cache[name]
                                if ids then
                                    local n = 0
                                    for _ in pairs(ids) do n = n + 1 end
                                    row.byNameCount = n
                                end
                                row.byNamePending = name ~= nil and private.SpellNameScan.IsPending(name)
                            end
                        end
                        row.ranks = entry.ranks
                        if keys then
                            if keys[key] then
                                row.duplicateOf = key
                            else
                                local owner = cdm.GetIdentityOwner(key)
                                if owner and keys[owner] then row.duplicateOf = owner end
                            end
                        end
                        -- Only a cooldown entry stands in for the cast; a
                        -- custom aura of the same id leaves the spell listed.
                        if section.bucket == "cooldown" and spellbookByKey[key] then
                            foldedSpellbook[key] = true
                            row.inSpellbook = true
                        end
                        customRows[#customRows + 1] = row
                    end
                end
            end
        end
    end

    -- 3b. `learned`: the character has the spell, whatever the CDM says.
    --     WoW Forever has one entry per rank, whose condition names that rank
    --     and the next — by the look of it, so that only the highest rank the
    --     character has reads known and every lower one unknown (DB2, not yet
    --     seen in a client).  A condition can also simply
    --     be wrong: Rejuvenation rank 1's names spell 744, not 774
    --     (.context/memory/project_forever_support.md).
    --     A ranked spell also matches on name and rank, the same spell under
    --     another id.  `known` stays what the tracker draws, and is read as
    --     final here: a frame's rows get theirs after newRow.
    local function markLearned(rows)
        for i = 1, #rows do
            local row = rows[i]
            row.learned = row.known or bookIds[row.key]
                or (row.rank ~= nil and bookRanks[(row.name or "") .. "\0" .. row.rank]) or false
        end
    end
    markLearned(cdmRows)
    markLearned(afRows)
    markLearned(customRows)

    -- 4. Stale rows: a key a profile list still names that nothing above
    --    answers to.  Surfaced, never migrated or dropped
    --    (.context/memory/project_no_spell_id_automigration.md).  Custom
    --    entries never land here: every one is a row of its own above.
    local liveKeys = {}
    for i = 1, #cdmRows do liveKeys[cdmRows[i].key] = true end
    for i = 1, #customRows do liveKeys[customRows[i].key] = true end
    for i = 1, #spellbookRows do liveKeys[spellbookRows[i].key] = true end
    --    The per-spell settings (the EXCLUDE_LISTS, the COLOR_MAPS) are
    --    saved per tracker / frame and only a row OF THAT SECTION shows their
    --    controls, so each is live only against its own section's rows: an
    --    entry left behind on a section its spell no longer draws in is
    --    stale even while the spell is a row elsewhere.
    local liveBySection = {}
    local function noteLive(rows)
        for i = 1, #rows do
            local row = rows[i]
            if row.sectionId ~= POOL then
                local set = liveBySection[row.sectionId]
                if not set then
                    set = {}
                    liveBySection[row.sectionId] = set
                end
                set[row.key] = true
            end
        end
    end
    noteLive(cdmRows)
    noteLive(afRows)
    noteLive(customRows)
    for s = 1, #sections do
        local sid = sections[s].id
        local settings = hostSettings(sid)
        for l = 1, #EXCLUDE_LISTS do
            local excludes = settings and settings[EXCLUDE_LISTS[l]]
            if type(excludes) == "table" then
                for idx = 1, #excludes do
                    if type(excludes[idx]) == "number" then
                        staleRefs[#staleRefs + 1] = { key = excludes[idx], sectionId = sid,
                            list = EXCLUDE_LISTS[l], inSection = true }
                    end
                end
            end
        end
        for m = 1, #COLOR_MAPS do
            local colors = settings and settings[COLOR_MAPS[m]]
            if type(colors) == "table" then
                for key in pairs(colors) do
                    if type(key) == "number" then
                        staleRefs[#staleRefs + 1] = { key = key, sectionId = sid,
                            list = COLOR_MAPS[m], inSection = true }
                    end
                end
            end
        end
    end
    --    A tracker's icon order: only the list this spec reads (its own, else
    --    the all-specs one).  Another spec's own list is that spec's business.
    for i = 1, #CDM_SECTIONS do
        local order = private.Util.GetTrackerOrder(hostSettings(CDM_SECTIONS[i].id))
        if order then
            for idx = 1, #order do
                if type(order[idx]) == "number" then
                    staleRefs[#staleRefs + 1] = { key = order[idx], sectionId = CDM_SECTIONS[i].id, list = "priority_order" }
                end
            end
        end
    end
    if type(profile.icon_overrides) == "table" then
        for key in pairs(profile.icon_overrides) do
            if type(key) == "number" then
                staleRefs[#staleRefs + 1] = { key = key, list = "icon_overrides" }
            end
        end
    end
    --    A stale row lives in the section its refs name — one row per
    --    (section, key), so Remove there clears only that section's leftovers.
    --    An icon override belongs to no section: it is a pool row of its own,
    --    so removing a section's leftovers never takes it (a profile shared
    --    across characters may still draw it elsewhere).
    local sectionStale, poolStale = {}, {}
    local staleIn = {}
    local noKeys = {}
    for i = 1, #staleRefs do
        local ref = staleRefs[i]
        local live = liveKeys
        if ref.inSection then live = liveBySection[ref.sectionId] or noKeys end
        if not resolve(ref.key, keyIn, live) then
            if ref.sectionId then
                local bySection = staleIn[ref.sectionId]
                if not bySection then
                    bySection = {}
                    staleIn[ref.sectionId] = bySection
                end
                local row = bySection[ref.key]
                if not row then
                    row = newRow(ref.key, "stale", nil, ref.sectionId, false)
                    row.refs = {}
                    -- A row nowhere on this spec (another spec's spell): a
                    -- CDM tracker may hand its placement on (moveStale).
                    row.untracked = not resolve(ref.key, keyIn, liveKeys)
                    bySection[ref.key] = row
                    sectionStale[#sectionStale + 1] = row
                end
                row.refs[#row.refs + 1] = { sectionId = ref.sectionId, list = ref.list }
                row.listIndex = row.listIndex or ref.listIndex
            else
                local row = newRow(ref.key, "stale", nil, POOL, false)
                row.refs = { { list = ref.list } }
                poolStale[#poolStale + 1] = row
            end
        end
    end

    -- Assemble.  CDM sections draw in the tracker's own order: priority_order,
    -- then Blizzard's rank, custom spells last (Util.BuildSpellOrderRank).
    local bySection = {}
    local function collect(rows)
        for i = 1, #rows do
            local row = rows[i]
            local list = bySection[row.sectionId]
            if not list then
                list = {}
                bySection[row.sectionId] = list
            end
            list[#list + 1] = row
        end
    end
    collect(cdmRows)
    collect(afRows)
    collect(customRows)

    for s = 1, #sections do
        local section = sections[s]
        local rows = bySection[section.id] or {}
        if section.kind == "cdm" then
            local keyMap, keys, rowsOfKey = {}, {}, {}
            for i = 1, #rows do
                local key = rows[i].key
                if not keyMap[key] then
                    keyMap[key] = true
                    keys[#keys + 1] = key
                    rowsOfKey[key] = {}
                end
                local list = rowsOfKey[key]
                list[#list + 1] = rows[i]
            end
            private.Util.SortByOrderRank(keys, private.Util.BuildSpellOrderRank(section.id, keyMap))
            for i = 1, #keys do
                local list = rowsOfKey[keys[i]]
                -- The CDM row before any custom entry duplicating it.
                for r = 1, #list do
                    if list[r].kind ~= "custom" then section.rows[#section.rows + 1] = list[r] end
                end
                for r = 1, #list do
                    if list[r].kind == "custom" then section.rows[#section.rows + 1] = list[r] end
                end
            end
        else
            -- assigned_spells order, then the frame's custom spells (which an AF
            -- ranks after every assigned entry).
            local assignedRows, customList = {}, {}
            for i = 1, #rows do
                if rows[i].kind == "custom" then
                    customList[#customList + 1] = rows[i]
                else
                    assignedRows[#assignedRows + 1] = rows[i]
                end
            end
            table.sort(assignedRows, byListIndex)
            table.sort(customList, byListIndex)
            for i = 1, #assignedRows do section.rows[#section.rows + 1] = assignedRows[i] end
            for i = 1, #customList do section.rows[#section.rows + 1] = customList[i] end
        end
    end

    -- Stale rows close each section, after every row it draws.
    table.sort(sectionStale, byKey)
    for i = 1, #sectionStale do
        local section = sectionById[sectionStale[i].sectionId]
        if section then section.rows[#section.rows + 1] = sectionStale[i] end
    end

    local poolCdm = bySection[POOL] or {}
    table.sort(poolCdm, byKey)
    for i = 1, #poolCdm do pool.rows[#pool.rows + 1] = poolCdm[i] end
    table.sort(spellbookRows, byKey)
    for i = 1, #spellbookRows do
        if not foldedSpellbook[spellbookRows[i].key] then
            pool.rows[#pool.rows + 1] = spellbookRows[i]
        end
    end
    table.sort(poolStale, byKey)
    for i = 1, #poolStale do pool.rows[#pool.rows + 1] = poolStale[i] end
    sections[#sections + 1] = pool
    return sections, true
end

---@param sections tracking_section[]
---@param id string
---@return tracking_section|nil
local function findSection(sections, id)
    for i = 1, #sections do
        if sections[i].id == id then return sections[i] end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Legality
-- ---------------------------------------------------------------------------

---Targets of an Additional Frame addon-source row ({id, source} on a `spells`
---frame): every OTHER `spells` frame — the one frame type that draws
---addon-owned icons — that does not already hold an entry with this id, the
---refusal AddAddonSource makes.  Only a row living on a spells frame moves:
---the entry then leaves the one spells frame holding it, so one frame per
---icon (AddAddonSource's other refusal) still holds after the move.
---@param row tracking_row
---@return string[]
local function addonSourceTargets(row)
    local targets = {}
    local own = afSettings(afIdOf(row.sectionId))
    if not own or own.frame_type ~= "spells" then return targets end
    local afm = private.AdditionalFrameManager
    local afIds = afm and afm.GetAllFrameIds() or {}
    for i = 1, #afIds do
        local sid = "af:" .. afIds[i]
        local settings = afSettings(afIds[i])
        if settings and settings.frame_type == "spells" and sid ~= row.sectionId then
            local list = settings.assigned_spells
            local held = false
            if type(list) == "table" then
                for e = 1, #list do
                    if entryId(list[e]) == row.key then held = true end
                end
            end
            if not held then targets[#targets + 1] = sid end
        end
    end
    return targets
end

---Section ids `row` may Move to; never its own section.  See the table in
---Core/TrackingModel.md.  The CDM-section half defers to
---CDMDataSource.IsLegalCategoryMove, the same rule the overlay applies.
---@param row tracking_row
---@return string[]
local function getValidTargets(row)
    local targets = {}
    if type(row) ~= "table" then return targets end
    local kind = row.kind
    local bucket
    -- A cast id is often its own aura's id too (most self-buffs; every rank of
    -- a ranked buff on WoW Forever), so a cooldown-side spell entry may also go
    -- to an aura section, as a custom aura under the same id.  Not the reverse,
    -- and never a CDM row: its aura, if it has one, is a CDM entry of its own.
    local eitherBucket = false
    if kind == "cdm" or kind == "custom" then
        bucket = row.bucket
        eitherBucket = kind == "custom" and bucket == "cooldown"
    elseif kind == "spellbook" then
        bucket = "cooldown"
        eitherBucket = true
    elseif kind == "item" and row.source then
        return addonSourceTargets(row)
    elseif kind == "stale" then
        -- Another spec's spell saved in a CDM tracker: its placement goes to
        -- the bucket's other tracker (moveStale).  Not with cdm_auto_fetch
        -- off, where a tracker draws no CDM entry.
        local spec = row.untracked and cdmSectionSpec(row.sectionId)
        if not spec or not (private.profile and private.profile.cdm_auto_fetch) then return targets end
        for i = 1, #CDM_SECTIONS do
            if CDM_SECTIONS[i].bucket == spec.bucket and CDM_SECTIONS[i].id ~= spec.id then
                targets[#targets + 1] = CDM_SECTIONS[i].id
            end
        end
        return targets
    else
        -- CDM item / assigned: reorder and Remove only.
        return targets
    end
    if not bucket then return targets end
    local cdm = private.CDMDataSource
    -- With cdm_auto_fetch off a CDM tracker draws no CDM entry at all, so it is
    -- no target for one (BuildComponentSpellMaps' gate).
    local autoFetch = private.profile and private.profile.cdm_auto_fetch
    for i = 1, #CDM_SECTIONS do
        local spec = CDM_SECTIONS[i]
        if (spec.bucket == bucket or eitherBucket) and spec.id ~= row.sectionId then
            if kind ~= "cdm" or (autoFetch
                and cdm.IsLegalCategoryMove(cdm.GetDefaultCategory(row.cooldownID), categoryOf(spec))) then
                targets[#targets + 1] = spec.id
            end
        end
    end
    -- Every frame of the bucket, a cooldown entry Blizzard hides included: a
    -- spells frame draws it (IsCooldownSpellTracked admits HiddenActive).
    local afm = private.AdditionalFrameManager
    local afIds = afm and afm.GetAllFrameIds() or {}
    for i = 1, #afIds do
        local sid = "af:" .. afIds[i]
        local settings = afSettings(afIds[i])
        local frameBucket = settings and afBucket(settings)
        if frameBucket and (frameBucket == bucket or eitherBucket) and sid ~= row.sectionId then
            targets[#targets + 1] = sid
        end
    end
    return targets
end

---@param row tracking_row
---@param sectionId string
---@return boolean
local function isValidTarget(row, sectionId)
    local targets = getValidTargets(row)
    for i = 1, #targets do
        if targets[i] == sectionId then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Writers and their refreshes
-- ---------------------------------------------------------------------------

---The Tracking tab's "All specs" box: category and icon-order writes go to the
---all-specs layer instead of the current spec's.  Session-only, like the tab's
---other view toggles.
local allSpecs = false

---One bucket map of one `cdm_category_overrides` layer: the all-specs one
---(`specKey` nil) or `spec[specKey]`.  With `create`, a missing or corrupt
---shape on the way down is repaired; without, nil for anything not a table.
---@param bucket "cooldown"|"aura"
---@param specKey string|nil
---@param create boolean|nil
---@return table<number, number>|nil
local function overrideMap(bucket, specKey, create)
    local p = private.profile
    if type(p.cdm_category_overrides) ~= "table" then
        if not create then return nil end
        p.cdm_category_overrides = { cooldown = {}, aura = {} }
    end
    local t = p.cdm_category_overrides
    if specKey then
        if type(t.spec) ~= "table" then
            if not create then return nil end
            t.spec = {}
        end
        if type(t.spec[specKey]) ~= "table" then
            if not create then return nil end
            t.spec[specKey] = {}
        end
        t = t.spec[specKey]
    end
    if type(t[bucket]) ~= "table" then
        if not create then return nil end
        t[bucket] = {}
    end
    return t[bucket]
end

---The layer a category write for `row` lands in, as a spec key (nil: the
---all-specs layer).  The current spec's, unless the tab's "All specs" box is
---ticked or the row is not learned on this spec — an unlearned entry is
---another spec's, and a move made for this spec would never show.  A client
---with no spec system has only the all-specs layer.
---@param row tracking_row
---@return string|nil
local function writeSpecKey(row)
    if allSpecs or not row.known then return nil end
    return private.CDMDataSource.GetSpecLayerKey()
end

---The `specs` a custom aura gets on arriving at an aura host: the current
---spec, or nil (every spec) with the "All specs" box ticked or on a client
---with no spec system.  CustomSpells.shouldFilterEntry reads it.
---@return table<string, true>|nil
local function newAuraSpecs()
    local key = not allSpecs and private.CDMDataSource.GetSpecLayerKey() or nil
    return key and { [key] = true } or nil
end

---Drop every override for `key` in one bucket map, under whichever equivalent
---id (own, base, the base's override) it was saved — the ids the overlay reads.
---@param map table<number, number>|nil
---@param key number
---@return boolean removed
local function clearCategoryOverride(map, key)
    if not map then return false end
    local removed = false
    local found = private.Util.ResolveByBaseOrOverride(key, keyIn, map)
    while found do
        map[found] = nil
        removed = true
        found = private.Util.ResolveByBaseOrOverride(key, keyIn, map)
    end
    return removed
end

---Drop `key`'s override from `map`.  A spell-rank family's rank clears its
---OWN key only: the identity walk would also reach the family's
---representative through the owner map a whole buff family folds into, and
---each rank is its own CDM entry with its own category.
---@param map table<number, number>|nil
---@param key number
---@param exact boolean
---@return boolean removed
local function clearOverride(map, key, exact)
    if not exact then return clearCategoryOverride(map, key) end
    if map and map[key] ~= nil then
        map[key] = nil
        return true
    end
    return false
end

---The CDM rows a write to `row` covers: every rank of a whole spell-rank family
---when `row` stands for it (its representative, not marked `single`), else
---`row` alone.  Each carries what setCategory and hiddenCategoryFor read.
---@param row tracking_row
---@return tracking_row[]
local function familyRows(row)
    local family = row.family
    if row.single or not (family and family.whole and family.rep == row.key) then return { row } end
    local rows = {}
    for i = 1, #family.members do
        local member = family.members[i]
        rows[i] = { key = member.key, bucket = row.bucket, cooldownID = member.id,
            known = row.known, family = family }
    end
    return rows
end

---Put a CDM row's entry in `category`, in the layer writeSpecKey picks.
---
---Nothing is stored where the layers below already give that category — the
---all-specs one below a spec's, Blizzard's below that — so the entry follows
---them again from here.  Comparing with Blizzard's alone would drop a spec
---move back to Blizzard's category while the all-specs layer holds another.
---An all-specs write also leaves the current spec's layer, which would
---otherwise shadow it here; other specs keep theirs.
---@param row tracking_row
---@param category number
local function setCategory(row, category)
    local cdm = private.CDMDataSource
    local specKey = writeSpecKey(row)
    local exact = row.family ~= nil
    clearOverride(overrideMap(row.bucket, specKey), row.key, exact)
    local current = cdm.GetSpecLayerKey()
    if not specKey and current then
        clearOverride(overrideMap(row.bucket, current), row.key, exact)
    end
    local _, below = cdm.GetResolvedEntry(row.cooldownID)
    if specKey then
        below = cdm.GetLayerCategory(row.cooldownID, overrideMap(row.bucket, nil)) or below
    end
    if category ~= below then
        overrideMap(row.bucket, specKey, true)[row.key] = category
    end
end

---Drop `key`'s override from the all-specs layer and the current spec's.
---@param bucket "cooldown"|"aura"
---@param key number
---@param exact boolean|nil  a spell-rank family's rank (clearOverride)
---@return boolean removed
local function clearBothLayers(bucket, key, exact)
    local removed = clearOverride(overrideMap(bucket, nil), key, exact)
    local current = private.CDMDataSource.GetSpecLayerKey()
    if current and clearOverride(overrideMap(bucket, current), key, exact) then
        removed = true
    end
    return removed
end

---The bucket map Reset moves clears: the all-specs layer when the "All specs"
---box is ticked or there is no spec system, else the current spec's.
---@param bucket "cooldown"|"aura"
---@return table<number, number>|nil
local function resetTargetMap(bucket)
    return overrideMap(bucket, not allSpecs and private.CDMDataSource.GetSpecLayerKey() or nil)
end

---The icon-order layer an order write lands in, as a spec key (nil: the
---all-specs `priority_order`): the current spec's own list, unless the tab's
---"All specs" box is ticked or there is no spec system — resetTargetMap's rule.
---Section-wide, unlike writeSpecKey: an order is one list, not a per-entry value.
---@return string|nil
local function orderLayerKey()
    if allSpecs then return nil end
    return private.CDMDataSource.GetSpecLayerKey()
end

---A tracker's own icon order for `specKey` (`priority_order_spec[specKey]`).
---With `create`, a missing or corrupt shape on the way down is repaired;
---without, nil for anything not a table.
---@param settings table
---@param specKey string|nil
---@param create boolean|nil
---@return number[]|nil
local function specOrder(settings, specKey, create)
    if not specKey then return nil end
    if type(settings.priority_order_spec) ~= "table" then
        if not create then return nil end
        settings.priority_order_spec = {}
    end
    local lists = settings.priority_order_spec
    if type(lists[specKey]) ~= "table" then
        if not create then return nil end
        lists[specKey] = {}
    end
    return lists[specKey]
end

---The keys a CDM tracker's icon order shows, in order: the stored order this
---spec reads (Util.GetTrackerOrder; untracked keys included, so an all-specs
---arrangement survives a spec swap), then every tracked key it does not mention
---in Blizzard's rank.  Also returns the tracked set.
---@param spec table  a CDM_SECTIONS row
---@return number[] keys, table<number, true> tracked
local function sectionOrderKeys(spec)
    local selfMap, targetMap = private.CDMDataSource.BuildComponentSpellMaps(
        categoryOf(spec), spec.routeKey, spec.id, false)
    local tracked = {}
    for key in pairs(selfMap) do tracked[key] = true end
    for key in pairs(targetMap) do tracked[key] = true end
    local order = private.Util.GetTrackerOrder(hostSettings(spec.id))
    local keys, seen = {}, {}
    if order then
        for i = 1, #order do
            local key = order[i]
            if type(key) == "number" and not seen[key] then
                seen[key] = true
                keys[#keys + 1] = key
            end
        end
    end
    local tail = {}
    for key in pairs(tracked) do
        if not seen[key] then tail[#tail + 1] = key end
    end
    private.Util.SortByOrderRank(tail, private.Util.BuildSpellOrderRank(spec.id, tracked))
    for i = 1, #tail do keys[#keys + 1] = tail[i] end
    return keys, tracked
end

---Write the tracker's whole displayed order into one layer and return that
---list: this spec's own (`specKey`) or, with nil, the all-specs
---`priority_order`.  A partial list would leave every key it does not mention
---in Blizzard's order behind it, as the Icon Order panel's first edit knew.
---
---An all-specs write drops this spec's own list first, which would otherwise
---shadow it here; the displayed order is then the all-specs one, so this
---spec's arrangement is never folded into it.  Other specs keep theirs.  A
---spec's own list takes only keys that are a row on this spec (drawn, or a
---CDM entry of this character's set, learned or not): any other key is another
---spec's, and that spec has its own list or reads the all-specs one.
---@param spec table  a CDM_SECTIONS row
---@param specKey string|nil  orderLayerKey()
---@return number[] order  the live list
local function materializeOrder(spec, specKey)
    local settings = hostSettings(spec.id)
    -- A profile with no table for the tracker (imported, hand-edited): the
    -- order has nowhere to live, and the caller's writes go nowhere.
    if not settings then return {} end
    local current = private.CDMDataSource.GetSpecLayerKey()
    if not specKey and current and specOrder(settings, current) then
        settings.priority_order_spec[current] = nil
    end
    -- Read before a new own list exists: until then this spec shows the
    -- all-specs order, and that is what its own list starts from.
    local keys, tracked = sectionOrderKeys(spec)
    local order
    if specKey then
        order = specOrder(settings, specKey, true)
        wipe(order)
        local isEntryKey = private.CDMDataSource.IsEntryKey
        for i = 1, #keys do
            if tracked[keys[i]] or isEntryKey(keys[i]) then order[#order + 1] = keys[i] end
        end
        return order
    end
    order = settings.priority_order
    if type(order) ~= "table" then
        order = {}
        settings.priority_order = order
    end
    wipe(order)
    for i = 1, #keys do order[i] = keys[i] end
    return order
end

---The orders a placement (a move's target, an add) lands in: orderLayerKey()'s
---layer, materialized, where a drop position counts; and, with "All specs"
---ticked while this spec keeps its own order, the all-specs order as well,
---which the placement is appended to (nil when it is empty, which leaves it
---following Blizzard's).  Only arranging with the box ticked (Reorder) drops
---this spec's own order; a placement used to as well, silently discarding the
---spec's arrangement (review 2026-09-30).
---@param spec table  a CDM_SECTIONS row
---@return number[] order, number[]|nil shared
local function placementOrders(spec)
    local layer = orderLayerKey()
    local settings = hostSettings(spec.id)
    local current = private.CDMDataSource.GetSpecLayerKey()
    if not layer and settings and current and specOrder(settings, current) then
        local shared = type(settings.priority_order) == "table" and #settings.priority_order > 0
            and settings.priority_order or nil
        return materializeOrder(spec, current), shared
    end
    return materializeOrder(spec, layer), nil
end

---The orders a move's target edits (placementOrders), or nil when it needs
---none.  A tracker showing no stored order follows Blizzard's, and a move that
---names no drop position (the Move-to menu) leaves it following: materializing
---there would pin Blizzard's current order into the profile, so reordering in
---Blizzard's Cooldown Manager would stop reaching CUE.  Stored means what this
---spec shows: its own order, else the all-specs one.
---@param spec table|nil  a CDM_SECTIONS row
---@param index number|nil  display index of a placed drop
---@return number[]|nil order, number[]|nil shared
local function orderForMove(spec, index)
    if not spec then return nil end
    local settings = hostSettings(spec.id)
    if not settings then return nil end
    local stored = private.Util.GetTrackerOrder(settings)
    if index == nil and (type(stored) ~= "table" or #stored == 0) then return nil end
    return placementOrders(spec)
end

---@param list any[]
---@param value any
---@return number|nil
local function indexOf(list, value)
    for i = 1, #list do
        if list[i] == value then return i end
    end
    return nil
end

---@param order number[]
---@param key number
local function removeFromOrder(order, key)
    for i = #order, 1, -1 do
        if order[i] == key then table.remove(order, i) end
    end
end

---Take `key` out of a tracker's icon orders: the all-specs one and this
---spec's own, or with `everySpec` every spec's own as well.
---@param settings table
---@param key number
---@param everySpec boolean|nil
local function removeFromOrders(settings, key, everySpec)
    if type(settings.priority_order) == "table" then removeFromOrder(settings.priority_order, key) end
    local lists = settings.priority_order_spec
    if type(lists) ~= "table" then return end
    if everySpec then
        for _, list in pairs(lists) do
            if type(list) == "table" then removeFromOrder(list, key) end
        end
        return
    end
    local own = specOrder(settings, private.CDMDataSource.GetSpecLayerKey())
    if own then removeFromOrder(own, key) end
end

---Rename `oldKey` to `newKey` in place, in the all-specs order and every spec's
---own: for an entry that is every spec's (a custom spell's rank).
---@param settings table
---@param oldKey number
---@param newKey number
local function renameInOrders(settings, oldKey, newKey)
    local function rename(order)
        local at = type(order) == "table" and indexOf(order, oldKey)
        if at then order[at] = newKey end
    end
    rename(settings.priority_order)
    if type(settings.priority_order_spec) == "table" then
        for _, list in pairs(settings.priority_order_spec) do rename(list) end
    end
end

---Take `key` out of a move's source tracker, in the orders the move's layer
---writes: this spec's own (the all-specs order keeps it — other specs still
---draw it there, and where this spec reads that order the key is simply no
---longer tracked), or, with "All specs" ticked, the all-specs order and this
---spec's own.  Never materializes: removing needs no arrangement, and a
---materialized source forked this spec off the all-specs order (review
---2026-09-30).
---@param spec table|nil  a CDM_SECTIONS row
---@param key number
---@return boolean touched  a source tracker exists
local function removeFromMoveSource(spec, key)
    local settings = spec and hostSettings(spec.id)
    if not settings then return false end
    if orderLayerKey() then
        local own = specOrder(settings, private.CDMDataSource.GetSpecLayerKey())
        if own then removeFromOrder(own, key) end
    else
        removeFromOrders(settings, key)
    end
    return true
end

---Where a row dropped at display `index` of `rows` goes in `order`: before the
---key currently shown there, or at the end.
---@return number
local function orderPos(order, rows, index)
    local anchor = index and rows and rows[index]
    local pos = anchor and indexOf(order, anchor.key)
    return pos or (#order + 1)
end

---Insert `key` at `pos`, moving it if it is already present.
local function insertIntoOrder(order, key, pos)
    local existing = indexOf(order, key)
    if existing then
        table.remove(order, existing)
        if existing < pos then pos = pos - 1 end
    end
    if pos > #order + 1 then pos = #order + 1 end
    if pos < 1 then pos = 1 end
    table.insert(order, pos, key)
end

---Where a row dropped at display `index` of an AF section goes in its
---`assigned_spells`: the position of the assigned entry shown there, or the end.
---By `listIndex`, never by key: a row that claimed its entry through an
---override or linked id shows a key that is not the stored id.
---@return number
local function assignedPos(list, rows, index)
    local anchor = index and rows and rows[index]
    if anchor and anchor.kind ~= "custom" and anchor.listIndex and list[anchor.listIndex] ~= nil then
        return anchor.listIndex
    end
    return #list + 1
end

---@param list any
---@param spellID number
---@return boolean
local function customHas(list, spellID)
    if type(list) ~= "table" then return false end
    for i = 1, #list do
        if type(list[i]) == "table" and list[i].spellID == spellID then return true end
    end
    return false
end

---Does a by-name entry of `list` other than `except` already carry `name`?
---Both cells would fill from one aura, so a second one is refused.
---@param list table
---@param name string
---@param except table|nil
---@return boolean
local function byNameTaken(list, name, except)
    for i = 1, #list do
        local other = list[i]
        if other ~= except and type(other) == "table" and other.by_name
            and type(other.spellID) == "number" and C_Spell.GetSpellName(other.spellID) == name then
            return true
        end
    end
    return false
end

---Refresh one section's component after a priority_order or custom_spells
---write.
---@param sectionId string
local function refreshComponent(sectionId)
    local name = componentNameFor(sectionId)
    local comp = name and private.ComponentManager.GetComponent(name)
    if comp and comp.Refresh then comp.Refresh() end
end

---A custom_spells list changed: `CustomSpells.Rebuild` then `component.Refresh()`,
---exactly as the retired custom-spell lists did.
---@param sectionId string
local function rebuildCustom(sectionId)
    local name = componentNameFor(sectionId)
    if not name then return end
    private.CustomSpells.Rebuild(name)
    refreshComponent(sectionId)
end

---The bridge that reaches the aura trackers' restyle pass for a PROFILE-level
---key.  Options.lua's `refreshGlobalChrome` is file-local there; these are the
---same four calls (patterns.md "RESTYLE_KEYS only covers a tracker's OWN
---settings" — a bare RefreshAllComponents leaves every aura button untouched).
local function refreshChrome()
    private.fontsDirty = true
    private.ComponentManager.RefreshAllComponents()
    private.fontsDirty = false
    private.Anchor.Refresh()
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

---Append a custom spell to a section's custom_spells, optionally placing it in
---a CDM tracker's order.  Shape and validation match the retired custom-spell
---add box.
---@param spellID number
---@param targetSectionId string
---@param wantBucket "cooldown"|"aura"
---@param index number|nil  display index within the target section
---@param ranks "highest"|nil  a spellbook spell's rank mode (cooldown hosts only)
---@param byName boolean|nil  an aura entry matched by name (#55), unless another by-name entry has the name
---@return boolean
local function addCustom(spellID, targetSectionId, wantBucket, index, ranks, byName)
    if type(spellID) ~= "number" or spellID <= 0 or not C_Spell.GetSpellName(spellID) then return false end
    if sectionBucket(targetSectionId) ~= wantBucket then return false end
    local settings = hostSettings(targetSectionId)
    if not settings then return false end
    if type(settings.custom_spells) ~= "table" then settings.custom_spells = {} end
    if customHas(settings.custom_spells, spellID) then return false end
    local spec = cdmSectionSpec(targetSectionId)
    local order, shared, pos
    if spec and index then
        local sections = buildSections()
        local target = findSection(sections, targetSectionId)
        order, shared = placementOrders(spec)
        pos = orderPos(order, target and target.rows, index)
    end
    if byName then
        local name = wantBucket == "aura" and C_Spell.GetSpellName(spellID)
        byName = name and not byNameTaken(settings.custom_spells, name) or nil
    end
    -- "Highest" only on a cooldown host (an aura entry is one id: #55).  A
    -- typed id arrives without `ranks`: that exact rank.
    settings.custom_spells[#settings.custom_spells + 1] = { spellID = spellID, restrict_to_player = true,
        ranks = (wantBucket == "cooldown" and ranks == "highest") and "highest" or nil,
        specs = wantBucket == "aura" and newAuraSpecs() or nil, by_name = byName }
    if order then insertIntoOrder(order, spellID, pos) end
    if shared then insertIntoOrder(shared, spellID, #shared + 1) end
    rebuildCustom(targetSectionId)
    return true
end

---Move a CDM row between CDM trackers and/or Additional Frames.
---@param row tracking_row
---@param target tracking_section
---@param index number|nil
---@return boolean
local function moveCdm(row, target, index)
    local cdm = private.CDMDataSource
    local afm = private.AdditionalFrameManager
    local bucket = row.bucket
    local refresh, touchedAFs = {}, {}

    -- The target's order is materialized BEFORE the model changes, against
    -- the arrangement the player is looking at.  The source only loses the key.
    local srcSpec = cdmSectionSpec(row.sectionId)
    local dstSpec = cdmSectionSpec(target.id)
    local dstOrder, dstShared = orderForMove(dstSpec, index)
    local dstPos = dstOrder and orderPos(dstOrder, target.rows, index)
    local dstAssigned, dstAssignedPos
    if target.kind == "af" then
        local settings = afSettings(target.afId)
        if type(settings.assigned_spells) ~= "table" then settings.assigned_spells = {} end
        dstAssigned = settings.assigned_spells
        dstAssignedPos = assignedPos(dstAssigned, target.rows, index)
    end

    -- A whole spell-rank family moves as one: every rank's category, one
    -- NotifyUserCategoryChanged below.  The order holds its representative.
    local rows = familyRows(row)

    -- Out of its source tracker's order, or it would linger there as a dimmed
    -- "not tracked" leftover.
    if srcSpec then
        for r = 1, #rows do removeFromMoveSource(srcSpec, rows[r].key) end
        refresh[srcSpec.id] = true
    end
    -- Into a frame, which is every spec's (clearBothLayers below): out of both
    -- orders this spec reads, not only the layer the write went to.
    local srcSettings = srcSpec and target.kind == "af" and hostSettings(srcSpec.id)
    if srcSettings then
        for r = 1, #rows do removeFromOrders(srcSettings, rows[r].key) end
        refresh[srcSpec.id] = true
    end

    -- One frame per spell per routing domain: out of every frame of this
    -- bucket, the target included (re-inserted below at its new position).
    local afIds = afm.GetAllFrameIds()
    for i = 1, #afIds do
        local settings = afSettings(afIds[i])
        if settings and afBucket(settings) == bucket and type(settings.assigned_spells) == "table" then
            local list = settings.assigned_spells
            for e = #list, 1, -1 do
                local id, source = entryId(list[e])
                local named = false
                if type(id) == "number" and not source then
                    for r = 1, #rows do
                        if sameEntry(id, rows[r].key) then named = true end
                    end
                end
                if named then
                    table.remove(list, e)
                    touchedAFs[afIds[i]] = true
                    if list == dstAssigned and e < dstAssignedPos then
                        dstAssignedPos = dstAssignedPos - 1
                    end
                end
            end
        end
    end

    local categoryChanged
    if dstSpec then
        for r = 1, #rows do setCategory(rows[r], target.category) end
        if dstOrder then insertIntoOrder(dstOrder, row.key, dstPos) end
        if dstShared then insertIntoOrder(dstShared, row.key, #dstShared + 1) end
        refresh[dstSpec.id] = true
        categoryChanged = true
    else
        -- Into a frame: its CUE category goes from both layers this spec
        -- reads, so pulling it back out later returns it to Blizzard's
        -- category rather than a stale CUE one.  A frame is every spec's.
        for r = 1, #rows do
            if clearBothLayers(bucket, rows[r].key, rows[r].family ~= nil) then categoryChanged = true end
        end
        if dstAssignedPos > #dstAssigned + 1 then dstAssignedPos = #dstAssigned + 1 end
        table.insert(dstAssigned, dstAssignedPos, row.key)
        touchedAFs[target.afId] = true
    end

    if categoryChanged then cdm.NotifyUserCategoryChanged() end
    for afId in pairs(touchedAFs) do afm.OnSpellAssignmentChanged(afId) end
    for sectionId in pairs(refresh) do refreshComponent(sectionId) end
    return true
end

---Move a custom entry from one host's custom_spells to another's.
---@param row tracking_row
---@param target tracking_section
---@param index number|nil
---@return boolean
local function moveCustom(row, target, index)
    local srcSettings = hostSettings(row.sectionId)
    local list = srcSettings and srcSettings.custom_spells
    local entry = type(list) == "table" and row.listIndex and list[row.listIndex]
    if type(entry) ~= "table" or entry.spellID ~= row.key then return false end
    local dstSettings = hostSettings(target.id)
    if not dstSettings then return false end
    if type(dstSettings.custom_spells) ~= "table" then dstSettings.custom_spells = {} end

    local srcSpec, dstSpec = cdmSectionSpec(row.sectionId), cdmSectionSpec(target.id)
    local dstOrder, dstShared = orderForMove(dstSpec, index)
    local dstPos = dstOrder and orderPos(dstOrder, target.rows, index)

    table.remove(list, row.listIndex)
    -- The entry table itself moves, keeping restrict_to_player and specs.  A
    -- cooldown entry landing on an aura host is added there, so it is stamped
    -- like an add.
    if row.bucket == "cooldown" and target.bucket == "aura" then entry.specs = newAuraSpecs() end
    -- Matching by name is an aura notion; a cooldown host draws the id.
    if target.bucket ~= "aura" then entry.by_name = nil end
    if not customHas(dstSettings.custom_spells, row.key) then
        dstSettings.custom_spells[#dstSettings.custom_spells + 1] = entry
    end
    -- A custom entry duplicating a CDM row of its own key leaves that row
    -- drawn where it was, so the key keeps its place there.
    if row.duplicateOf ~= row.key then removeFromMoveSource(srcSpec, row.key) end
    if dstOrder then insertIntoOrder(dstOrder, row.key, dstPos) end
    if dstShared then insertIntoOrder(dstShared, row.key, #dstShared + 1) end
    rebuildCustom(row.sectionId)
    rebuildCustom(target.id)
    return true
end

---Move an addon-source entry {id, source} from one spells frame's
---assigned_spells to another's, at `index` — the entry table itself moves.
---Validated by listIndex + id + source like Remove.
---@param row tracking_row
---@param target tracking_section
---@param index number|nil
---@return boolean
local function moveAddonSource(row, target, index)
    local srcAfId = afIdOf(row.sectionId)
    local srcSettings = afSettings(srcAfId)
    local list = srcSettings and srcSettings.assigned_spells
    local entry = type(list) == "table" and row.listIndex and list[row.listIndex]
    local id, source = entryId(entry)
    if type(entry) ~= "table" or id ~= row.key or source ~= row.source then return false end
    local dstSettings = afSettings(target.afId)
    if not dstSettings then return false end
    if type(dstSettings.assigned_spells) ~= "table" then dstSettings.assigned_spells = {} end
    local dstList = dstSettings.assigned_spells
    local pos = assignedPos(dstList, target.rows, index)

    table.remove(list, row.listIndex)
    if pos > #dstList + 1 then pos = #dstList + 1 end
    table.insert(dstList, pos, entry)
    -- One notify per touched frame, as moveCdm does.
    local afm = private.AdditionalFrameManager
    afm.OnSpellAssignmentChanged(srcAfId)
    afm.OnSpellAssignmentChanged(target.afId)
    return true
end

---Move a stale row's placement to the other CDM tracker of its bucket: the
---target's category into the all-specs layer, the key's override out of every
---spec's layer (each would shadow it on its spec), and its order place, its
---exclusions and its icon border colour along.  A Buff Bars colour stays: Buff
---Tracker has none; so does a border headed for Buff Bars, which draws none.
---Blizzard's default category for the key is unreadable on this spec, so the
---value is stored as is; the overlay ignores it where the move is illegal
---(CDMDataSource.layerValue).
---@param row tracking_row
---@param target tracking_section
---@param index number|nil
---@return boolean
local function moveStale(row, target, index)
    local srcSpec, dstSpec = cdmSectionSpec(row.sectionId), cdmSectionSpec(target.id)
    local bucket = srcSpec.bucket
    local src, dst = hostSettings(srcSpec.id), hostSettings(dstSpec.id)
    -- Another spec's key moves for every spec, like its category: out of every
    -- order the source keeps, into the target's all-specs order, which the
    -- specs without their own list read.  Never into this spec's own list,
    -- which holds this spec's keys only.  The all-specs order is materialized
    -- only while it is the one shown here; under this spec's own list it is
    -- edited where it stands, and never started as a partial list.
    local dstOrder
    if dst then
        local shared = type(dst.priority_order) == "table" and #dst.priority_order > 0
            and dst.priority_order or nil
        if specOrder(dst, private.CDMDataSource.GetSpecLayerKey()) then
            dstOrder = shared
        elseif shared or index ~= nil then
            dstOrder = materializeOrder(dstSpec, nil)
        end
    end
    local dstPos = dstOrder and orderPos(dstOrder, target.rows, index)

    local layers = private.profile.cdm_category_overrides
    if type(layers) == "table" and type(layers.spec) == "table" then
        for specKey in pairs(layers.spec) do
            clearCategoryOverride(overrideMap(bucket, specKey), row.key)
        end
    end
    local map = overrideMap(bucket, nil, true)
    clearCategoryOverride(map, row.key)
    map[row.key] = target.category

    if src then removeFromOrders(src, row.key, true) end
    if dstOrder then insertIntoOrder(dstOrder, row.key, dstPos) end

    for l = 1, #EXCLUDE_LISTS do
        local key = EXCLUDE_LISTS[l]
        local excludes = src and src[key]
        if type(excludes) == "table" and dst and indexOf(excludes, row.key) then
            removeFromOrder(excludes, row.key)
            -- active_swipe_excludes has no default table: made on first write.
            if type(dst[key]) ~= "table" then dst[key] = {} end
            if not indexOf(dst[key], row.key) then dst[key][#dst[key] + 1] = row.key end
        end
    end
    local border = src and type(src.spell_borders) == "table" and src.spell_borders[row.key]
    if border and dst and dstSpec.id ~= "BuffTrackerBars" then
        src.spell_borders[row.key] = nil
        -- No default table either.
        if type(dst.spell_borders) ~= "table" then dst.spell_borders = {} end
        dst.spell_borders[row.key] = border
    end

    private.CDMDataSource.NotifyUserCategoryChanged()
    refreshComponent(srcSpec.id)
    refreshComponent(dstSpec.id)
    return true
end

---Move a row to another section (see Core/TrackingModel.md for what each kind
---writes).  False when the target is not in GetValidTargets(row), or the model
---is not resolved.
---@param row tracking_row
---@param targetSectionId string
---@param index number|nil  display index within the target section; nil = end
---@param ranks "highest"|nil  a spellbook row moved as its highest learned rank (the Tracking tab's rank pick): the custom entry it becomes follows that rank
---@return boolean
local function move(row, targetSectionId, index, ranks)
    if not isValidTarget(row, targetSectionId) then return false end
    local sections, ready = buildSections()
    if not ready then return false end
    local target = findSection(sections, targetSectionId)
    if not target then return false end
    if row.kind == "cdm" then
        return moveCdm(row, target, index)
    elseif row.kind == "custom" then
        return moveCustom(row, target, index)
    elseif row.kind == "spellbook" then
        return addCustom(row.key, targetSectionId, target.bucket, index, ranks)
    elseif row.kind == "item" and row.source then
        return moveAddonSource(row, target, index)
    elseif row.kind == "stale" then
        return moveStale(row, target, index)
    end
    return false
end

---Reorder within one section: `priority_order` for a CDM tracker (materialized
---first), `assigned_spells` for an Additional Frame.  Indices are positions in
---the section's `rows` as BuildSections returns them.
---@param sectionId string
---@param fromIndex number
---@param toIndex number
---@return boolean
local function reorder(sectionId, fromIndex, toIndex)
    if fromIndex == toIndex then return false end
    local sections, ready = buildSections()
    if not ready then return false end
    local section = findSection(sections, sectionId)
    local rows = section and section.rows
    local moving, anchor = rows and rows[fromIndex], rows and rows[toIndex]
    if not moving or not anchor or moving.key == anchor.key then return false end
    if section.kind == "cdm" then
        local order = materializeOrder(cdmSectionSpec(sectionId), orderLayerKey())
        local fromPos, toPos = indexOf(order, moving.key), indexOf(order, anchor.key)
        if not fromPos or not toPos then return false end
        table.remove(order, fromPos)
        table.insert(order, toPos, moving.key)
        refreshComponent(sectionId)
        return true
    elseif section.kind == "af" then
        -- Custom entries rank after every assigned one on a frame, so only the
        -- assigned block is orderable.
        if moving.kind == "custom" or anchor.kind == "custom" then return false end
        -- A row with no list position (a stale leftover) would pop the list's
        -- last entry instead; the tab refuses the drag, the model must too.
        if not moving.listIndex or not anchor.listIndex then return false end
        local list = afSettings(section.afId).assigned_spells
        local entry = table.remove(list, moving.listIndex)
        table.insert(list, anchor.listIndex, entry)
        private.AdditionalFrameManager.OnSpellAssignmentChanged(section.afId)
        return true
    end
    return false
end

---Add a spellbook spell (by its ACTIVE id), or any typed spell id (an item-cast
---spell such as Hearthstone is in no spellbook), as a custom spell of a cooldown
---section: CooldownTracker, UtilitiesTracker or a `spells` frame.  An Additional
---Frame takes it in `custom_spells` too, not `assigned_spells`: a spells frame
---intersects assigned_spells with IsCooldownSpellTracked, which drops every
---non-CDM id (AdditionalFrameManager.buildAFIconSpellMap).
---@param spellID number
---@param targetSectionId string
---@return boolean
local function addFromSpellbook(spellID, targetSectionId)
    return addCustom(spellID, targetSectionId, "cooldown", nil)
end

---Add a typed aura id as a custom spell of an aura section (BuffTracker,
---BuffTrackerBars, a `buffs`/`bar` frame).  No identity conversion is attempted;
---the id must already be the aura's (Core/README.md "Custom spells").
---@param spellID number
---@param targetSectionId string
---@return boolean
local function addAuraByID(spellID, targetSectionId)
    return addCustom(spellID, targetSectionId, "aura", nil)
end

---Section ids `row` may be COPIED to: every tracker and frame of the other
---bucket -- or none at all once the spell is on any of them, so a spell has one
---copy per bucket.  "On" is any row a section lists for the key (a CDM entry, a
---custom one, a frame's), or a by-name aura row carrying the same name, which
---draws that spell already.  A copy is the entry the typed add box writes
---(addCustom) and leaves the row where it is, so one spell can be tracked as a
---cooldown and as an aura (Sacred Shield).
---@param row tracking_row
---@param sections tracking_section[]|nil  already-built sections (the Tracking tab's); built here when nil
---@return string[] targets
---@return boolean|nil exists  true when the spell is already on the other bucket (the reason `targets` is empty)
local function getCopyTargets(row, sections)
    local targets = {}
    if type(row) ~= "table" or (row.kind ~= "cdm" and row.kind ~= "custom") then return targets end
    if type(row.key) ~= "number" or row.key <= 0 then return targets end
    local want = (row.bucket == "cooldown" and "aura") or (row.bucket == "aura" and "cooldown") or nil
    if not want then return targets end
    sections = sections or buildSections()
    local name = C_Spell.GetSpellName(row.key)
    for i = 1, #sections do
        local s = sections[i]
        if s.kind ~= "pool" and s.bucket == want then
            for r = 1, #s.rows do
                local other = s.rows[r]
                if other.kind ~= "stale" and (other.key == row.key
                    or (other.byName and name and C_Spell.GetSpellName(other.key) == name)) then
                    return {}, true
                end
            end
            targets[#targets + 1] = s.id
        end
    end
    return targets
end

---Copy `row` to a section of the other bucket as a custom entry.  Legality is
---re-derived, as Move's is.  An aura copy matches by name: a cooldown's buff is
---often a different id carrying the same name (Sacred Shield).
---@param row tracking_row
---@param targetSectionId string
---@return boolean
local function copy(row, targetSectionId)
    local targets = getCopyTargets(row)
    for i = 1, #targets do
        if targets[i] == targetSectionId then
            return addCustom(row.key, targetSectionId, sectionBucket(targetSectionId), nil, nil, true)
        end
    end
    return false
end

---The spells frame holding the addon-source entry {id, source}, if any.  Reads
---the profile, enabled or not — the placement rule BuildSections uses.
---@param id number
---@param source string
---@return string|nil afId
local function addonSourceOwner(id, source)
    local afIds = private.AdditionalFrameManager.GetAllFrameIds()
    for i = 1, #afIds do
        local settings = afSettings(afIds[i])
        local list = settings and settings.frame_type == "spells" and settings.assigned_spells
        if type(list) == "table" then
            for e = 1, #list do
                local entry, entrySource = entryId(list[e])
                if entry == id and entrySource == source then return afIds[i] end
            end
        end
    end
    return nil
end

---Is `sectionId` a `spells` Additional Frame — the one frame type that draws
---addon-source icons (AdditionalFrameManager collectAFAppendIcons)?
---@param sectionId string
---@return string|nil afId
local function spellsFrameOf(sectionId)
    local afId = afIdOf(sectionId)
    local settings = afSettings(afId)
    if settings and settings.frame_type == "spells" then return afId end
    return nil
end

---What a `spells` frame may take as an addon-source entry: the two trinket
---slots, every ConsumableTracker category, every racial RacialTracker resolved
---for this character — the retired Additional Frames picker's three item
---groups, in its order.  `ownerAfId` names the frame already holding one (the
---target included); the picker offered those greyed out.  Empty for any other
---section.
---@param targetSectionId string
---@return tracking_addon_choice[]
local function getAddonSourceChoices(targetSectionId)
    local choices = {}
    if not spellsFrameOf(targetSectionId) then return choices end
    local function add(id, source, category)
        local name, texture = describeKey(id, source)
        choices[#choices + 1] = { id = id, source = source, category = category,
            name = name, texture = texture, ownerAfId = addonSourceOwner(id, source) }
    end
    add(13, "Trinket")
    add(14, "Trinket")
    local ct = private.ConsumableTracker
    if ct then
        local order, ids = ct.GetCategoryOrder(), ct.GetCategoryIDs()
        for i = 1, #order do
            if ids[order[i]] then add(ids[order[i]], "Consumable", order[i]) end
        end
    end
    local rt = private.RacialTracker
    local racials = rt and rt.GetResolvedSpellIDs()
    if racials then
        for i = 1, #racials do add(racials[i], "Racial") end
    end
    return choices
end

---Append an addon-source entry `{id, source}` to a `spells` frame's
---`assigned_spells` — the write the retired Additional Frames picker made for
---its Trinket / Consumable / Racial groups.  Refused, as that picker refused
---it, when the frame already holds an entry with this id, or another frame
---already holds this {id, source} (one frame per icon; the picker greyed those
---out rather than moving them).
---@param id number
---@param source string  "Trinket"|"Consumable"|"Racial"
---@param targetSectionId string
---@return boolean
local function addAddonSource(id, source, targetSectionId)
    local afm = private.AdditionalFrameManager
    if type(id) ~= "number" or not afm.IsAddonIconSource(source) then return false end
    local afId = spellsFrameOf(targetSectionId)
    if not afId then return false end
    local settings = afSettings(afId)
    if type(settings.assigned_spells) ~= "table" then settings.assigned_spells = {} end
    local list = settings.assigned_spells
    for i = 1, #list do
        if entryId(list[i]) == id then return false end
    end
    if addonSourceOwner(id, source) then return false end
    list[#list + 1] = { id, source }
    afm.OnSpellAssignmentChanged(afId)
    return true
end

---The hidden category a CDM row of `bucket` is removed to, when its default
---category may go there at all; nil when it may not.
---@param row tracking_row
---@return number|nil
local function hiddenCategoryFor(row)
    local cdm = private.CDMDataSource
    local cats = Enum.CooldownViewerCategory
    local hidden = row.bucket == "cooldown" and (cats.HiddenActive or -1) or (cats.HiddenPassive or -2)
    if not cdm.IsLegalCategoryMove(cdm.GetDefaultCategory(row.cooldownID), hidden) then return nil end
    return hidden
end

---What Remove(row) would do, as a function that does it; nil where Remove
---refuses.  The checks live only here, so CanRemove (the Tracking tab's Remove
---button state) and Remove cannot disagree.  See Core/TrackingModel.md.
---@param row tracking_row
---@return function|nil
local function planRemove(row)
    if type(row) ~= "table" then return nil end
    local kind = row.kind
    if kind == "custom" then
        local settings = hostSettings(row.sectionId)
        local list = settings and settings.custom_spells
        local entry = type(list) == "table" and row.listIndex and list[row.listIndex]
        if type(entry) ~= "table" or entry.spellID ~= row.key then return nil end
        return function()
            table.remove(list, row.listIndex)
            rebuildCustom(row.sectionId)
        end
    end
    local afId = afIdOf(row.sectionId)
    if (kind == "cdm" or kind == "item" or kind == "assigned") and afId and row.listIndex then
        local settings = afSettings(afId)
        local list = settings and settings.assigned_spells
        if type(list) ~= "table" then return nil end
        local id, source = entryId(list[row.listIndex])
        if type(id) ~= "number" then return nil end
        -- An addon-source row names exactly its {id, source}; any other row
        -- never names an addon-source entry.
        local addonSource = private.AdditionalFrameManager.IsAddonIconSource(source)
        if row.source then
            if source ~= row.source then return nil end
        elseif addonSource then
            return nil
        end
        -- A CDM row claims the entry through the base↔override equivalence
        -- (the retired picker saved `overrideSpellID or spellID`), so its key
        -- need not be the stored id.
        if id ~= row.key and not (kind == "cdm" and sameEntry(id, row.key)) then return nil end
        return function()
            table.remove(list, row.listIndex)
            private.AdditionalFrameManager.OnSpellAssignmentChanged(afId)
        end
    end
    if kind == "cdm" and cdmSectionSpec(row.sectionId) then
        -- A whole spell-rank family leaves as one: every rank hidden.
        local rows = familyRows(row)
        local hidden = {}
        for r = 1, #rows do
            hidden[r] = hiddenCategoryFor(rows[r])
            if not hidden[r] then return nil end
        end
        return function()
            for r = 1, #rows do setCategory(rows[r], hidden[r]) end
            private.CDMDataSource.NotifyUserCategoryChanged()
            refreshComponent(row.sectionId)
        end
    end
    if kind ~= "stale" or not row.refs then return nil end
    return function()
        local profile = private.profile
        local chrome, refresh, touchedAFs = false, {}, {}
        for i = 1, #row.refs do
            local ref = row.refs[i]
            if ref.list == "priority_order" then
                -- The list the stale scan read: the one this spec draws.
                local order = private.Util.GetTrackerOrder(hostSettings(ref.sectionId))
                if order then
                    removeFromOrder(order, row.key)
                    refresh[ref.sectionId] = true
                end
            elseif ref.list == "assigned_spells" then
                local refAf = afIdOf(ref.sectionId)
                local settings = afSettings(refAf)
                local list = settings and settings.assigned_spells
                if type(list) == "table" then
                    for e = #list, 1, -1 do
                        local id, source = entryId(list[e])
                        if id == row.key and not source then table.remove(list, e) end
                    end
                    touchedAFs[refAf] = true
                end
            elseif ref.list == "icon_overrides" and type(profile.icon_overrides) == "table" then
                profile.icon_overrides[row.key] = nil
                chrome = true
            elseif ref.list == "pandemic_glow_excludes" or ref.list == "active_swipe_excludes" then
                local settings = hostSettings(ref.sectionId)
                local list = settings and settings[ref.list]
                if type(list) == "table" then
                    for e = #list, 1, -1 do
                        if list[e] == row.key then table.remove(list, e) end
                    end
                    refresh[ref.sectionId] = true
                end
            elseif ref.list == "spell_colors" or ref.list == "spell_borders"
                or ref.list == "missing_glow" then
                local settings = hostSettings(ref.sectionId)
                if settings and type(settings[ref.list]) == "table" then
                    settings[ref.list][row.key] = nil
                    refresh[ref.sectionId] = true
                end
            end
        end
        for id in pairs(touchedAFs) do private.AdditionalFrameManager.OnSpellAssignmentChanged(id) end
        for sectionId in pairs(refresh) do refreshComponent(sectionId) end
        if chrome then refreshChrome() end
    end
end

---Remove a row from wherever it lives; see Core/TrackingModel.md.
---@param row tracking_row
---@return boolean
local function remove(row)
    local plan = planRemove(row)
    if not plan then return false end
    plan()
    return true
end

---Would Remove(row) act?  Nothing is written.
---@param row tracking_row
---@return boolean
local function canRemove(row)
    return planRemove(row) ~= nil
end

---Put `chosen`, another rank of `current`'s spell, where `current` is, and
---send `current` to Not tracked: the Tracking tab's rank menu.  Two writes
---the tab already offers, Remove and Move, in the one order that keeps
---`index` right: `current` leaves first, so `index` then names the row after
---it and the Move lands in its place.  Both are checked before either
---writes.  A frame's CDM entry is also hidden, since leaving a frame alone
---returns it to its tracker; a tracker's CDM row and a custom entry reach
---Not tracked through Remove itself.
---Like planRemove: the swap as a function, nil where it is refused, so
---CanSwapRank and SwapRank cannot disagree.
---@param current tracking_row
---@param chosen tracking_row
---@param index number|nil  current's position in its section's rows
---@return function|nil
local function planSwapRank(current, chosen, index)
    if type(current) ~= "table" or type(chosen) ~= "table" then return nil end
    local sectionId = current.sectionId
    if sectionId == POOL or not isValidTarget(chosen, sectionId) then return nil end
    local out = planRemove(current)
    if not out then return nil end
    local hidden
    if current.kind == "cdm" and afIdOf(sectionId) then
        hidden = hiddenCategoryFor(current)
        if not hidden then return nil end
    elseif current.kind ~= "custom" and not (current.kind == "cdm" and cdmSectionSpec(sectionId)) then
        return nil
    end
    return function()
        out()
        if hidden then
            setCategory(current, hidden)
            private.CDMDataSource.NotifyUserCategoryChanged()
        end
        return move(chosen, sectionId, index)
    end
end

---@param current tracking_row
---@param chosen tracking_row
---@param index number  current's position in its section's rows
---@return boolean
local function swapRank(current, chosen, index)
    local plan = planSwapRank(current, chosen, index)
    if not plan then return false end
    return plan()
end

---Would SwapRank act?  Nothing is written.
---@param current tracking_row
---@param chosen tracking_row
---@return boolean
local function canSwapRank(current, chosen)
    return planSwapRank(current, chosen) ~= nil
end

---A tracker row's rank menu, one rank: `chosen` (a CDM row of a spell-rank
---family) becomes the only rank of its spell in `sectionId`.  Every other rank
---there goes to Not tracked, which splits the family, so `chosen` is drawn on
---its own (CDMDataSource.applyRankFamilies).  A `chosen` from elsewhere comes
---in at `index`; one already here takes the stored order position the spell
---held under its representative.  Nil where refused, like planRemove.
---@param chosen tracking_row
---@param sectionId string  a CDM tracker section
---@param index number|nil
---@return function|nil
local function planSetSingleRank(chosen, sectionId, index)
    if type(chosen) ~= "table" or chosen.kind ~= "cdm" or not chosen.family then return nil end
    local spec = cdmSectionSpec(sectionId)
    if not spec then return nil end
    local cdm = private.CDMDataSource
    local family = chosen.family
    local category = categoryOf(spec)
    -- This rank alone, never the family it may stand for (familyRows).
    local single = {}
    for k, v in pairs(chosen) do single[k] = v end
    single.single = true
    local here = chosen.sectionId == sectionId
    if not here and not isValidTarget(single, sectionId) then return nil end
    local hide = {}
    for i = 1, #family.members do
        local member = family.members[i]
        if member.key ~= chosen.key and cdm.GetDisplayCategory(member.id) == category then
            local r = { key = member.key, bucket = family.bucket, cooldownID = member.id,
                known = chosen.known, family = family }
            local hidden = hiddenCategoryFor(r)
            if not hidden then return nil end
            hide[#hide + 1] = { row = r, category = hidden }
        end
    end
    return function()
        if here then
            local order = private.Util.GetTrackerOrder(hostSettings(sectionId))
            if order and chosen.key ~= family.rep and indexOf(order, family.rep) then
                removeFromOrder(order, chosen.key)
                table.insert(order, indexOf(order, family.rep), chosen.key)
            end
        elseif not move(single, sectionId, index) then
            return false
        end
        for i = 1, #hide do setCategory(hide[i].row, hide[i].category) end
        if #hide > 0 then
            cdm.NotifyUserCategoryChanged()
            refreshComponent(sectionId)
        end
        return true
    end
end

---@param chosen tracking_row
---@param sectionId string
---@param index number|nil
---@return boolean
local function setSingleRank(chosen, sectionId, index)
    local plan = planSetSingleRank(chosen, sectionId, index)
    if not plan then return false end
    return plan()
end

---Would SetSingleRank act?  Nothing is written.
---@param chosen tracking_row
---@param sectionId string
---@return boolean
local function canSetSingleRank(chosen, sectionId)
    return planSetSingleRank(chosen, sectionId) ~= nil
end

---A tracker row's rank menu, "All ranks" (buffs) / "Highest" (cooldowns): every
---rank of `row`'s spell comes to `sectionId`, which makes its family whole, so
---it is drawn as one under its representative (applyRankFamilies).  A rank
---out of Not tracked, another tracker or a frame all come; a frame's entry
---for one goes.  The representative takes the order position `row` held.
---Nil where refused, like planRemove.
---@param row tracking_row  a CDM row of a spell-rank family, in `sectionId`
---@param sectionId string  a CDM tracker section
---@return function|nil
local function planSetFamilyMode(row, sectionId)
    if type(row) ~= "table" or row.kind ~= "cdm" or not row.family then return nil end
    local spec = cdmSectionSpec(sectionId)
    if not spec then return nil end
    local cdm = private.CDMDataSource
    local family = row.family
    local category = categoryOf(spec)
    local incoming = {}
    for i = 1, #family.members do
        local member = family.members[i]
        if cdm.GetDisplayCategory(member.id) ~= category then
            if not cdm.IsLegalCategoryMove(cdm.GetDefaultCategory(member.id), category) then return nil end
            incoming[#incoming + 1] = { key = member.key, bucket = family.bucket, cooldownID = member.id,
                known = row.known, family = family }
        end
    end
    return function()
        -- Out of every frame of the bucket: a frame holding a rank holds the spell.
        local afm = private.AdditionalFrameManager
        local afIds = afm.GetAllFrameIds()
        local touchedAFs = {}
        for i = 1, #afIds do
            local settings = afSettings(afIds[i])
            if settings and afBucket(settings) == family.bucket and type(settings.assigned_spells) == "table" then
                local list = settings.assigned_spells
                for e = #list, 1, -1 do
                    local id, source = entryId(list[e])
                    if type(id) == "number" and not source then
                        for m = 1, #family.members do
                            if sameEntry(id, family.members[m].key) then
                                table.remove(list, e)
                                touchedAFs[afIds[i]] = true
                                break
                            end
                        end
                    end
                end
            end
        end
        for i = 1, #incoming do setCategory(incoming[i], category) end
        -- The family is drawn under its representative: give it `row`'s place.
        local order = private.Util.GetTrackerOrder(hostSettings(sectionId))
        if order and family.rep ~= row.key and indexOf(order, row.key) then
            removeFromOrder(order, family.rep)
            table.insert(order, indexOf(order, row.key), family.rep)
        end
        cdm.NotifyUserCategoryChanged()
        for afId in pairs(touchedAFs) do afm.OnSpellAssignmentChanged(afId) end
        for i = 1, #CDM_SECTIONS do refreshComponent(CDM_SECTIONS[i].id) end
        return true
    end
end

---@param row tracking_row
---@param sectionId string
---@return boolean
local function setFamilyMode(row, sectionId)
    local plan = planSetFamilyMode(row, sectionId)
    if not plan then return false end
    return plan()
end

---Would SetFamilyMode act?  Nothing is written.
---@param row tracking_row
---@param sectionId string
---@return boolean
local function canSetFamilyMode(row, sectionId)
    return planSetFamilyMode(row, sectionId) ~= nil
end

---A custom cooldown row's rank menu: `spellID` pins the entry to that exact
---rank, nil makes it "Highest" (`ranks = "highest"`: CustomSpells draws the
---highest learned rank).  A changed id keeps the entry's place in the
---tracker's order.  Validated by listIndex + key like Remove.
---@param row tracking_row
---@param spellID number|nil
---@return function|nil
local function planSetCustomRank(row, spellID)
    if type(row) ~= "table" or row.kind ~= "custom" or row.bucket ~= "cooldown" then return nil end
    local settings = hostSettings(row.sectionId)
    local list = settings and settings.custom_spells
    local entry = type(list) == "table" and row.listIndex and list[row.listIndex]
    if type(entry) ~= "table" or entry.spellID ~= row.key then return nil end
    if spellID ~= nil then
        if type(spellID) ~= "number" or not C_Spell.GetSpellName(spellID) then return nil end
        if spellID ~= row.key and customHas(list, spellID) then return nil end
    end
    return function()
        if spellID == nil then
            entry.ranks = "highest"
        else
            entry.ranks = nil
            if spellID ~= row.key then
                entry.spellID = spellID
                -- The entry is every spec's, so is its place: rename it in the
                -- all-specs order and in every spec's own (review 2026-09-30).
                renameInOrders(settings, row.key, spellID)
            end
        end
        rebuildCustom(row.sectionId)
        return true
    end
end

---@param row tracking_row
---@param spellID number|nil
---@return boolean
local function setCustomRank(row, spellID)
    local plan = planSetCustomRank(row, spellID)
    if not plan then return false end
    return plan()
end

---Set a custom row's `restrict_to_player` — the retired custom-spell list's
---"Only When Usable" toggle.  Validated by listIndex + key like Remove, and
---refreshed the way every other custom_spells write is (rebuildCustom).
---@param row tracking_row
---@param restricted boolean
---@return boolean
local function setRestrictToPlayer(row, restricted)
    if type(row) ~= "table" or row.kind ~= "custom" then return false end
    local settings = hostSettings(row.sectionId)
    local list = settings and settings.custom_spells
    local entry = type(list) == "table" and row.listIndex and list[row.listIndex]
    if type(entry) ~= "table" or entry.spellID ~= row.key then return false end
    entry.restrict_to_player = restricted and true or false
    rebuildCustom(row.sectionId)
    return true
end

---Show a custom aura row on the current spec or not (the Tracking tab's
---"This spec" box, the entry's `specs`).  On adds the current spec; with the
---"All specs" box ticked it clears `specs` instead, back to every spec.  Off
---on an every-spec entry keeps the class's other specs: nil cannot say
---"all but one", and a custom aura id is a class's own.  Validated by
---listIndex + key like Remove.  False on a client with no spec system.
---@param row tracking_row
---@param on boolean
---@return boolean
local function setCustomSpec(row, on)
    if type(row) ~= "table" or row.kind ~= "custom" or row.bucket ~= "aura" then return false end
    local key = private.CDMDataSource.GetSpecLayerKey()
    if not key then return false end
    local settings = hostSettings(row.sectionId)
    local list = settings and settings.custom_spells
    local entry = type(list) == "table" and row.listIndex and list[row.listIndex]
    if type(entry) ~= "table" or entry.spellID ~= row.key then return false end
    if on then
        if allSpecs then
            entry.specs = nil
        elseif type(entry.specs) == "table" then
            entry.specs[key] = true
        end
    else
        if type(entry.specs) ~= "table" then
            local class = select(2, UnitClass("player"))
            entry.specs = {}
            for i = 1, GetNumSpecializations() do entry.specs[class .. "-" .. i] = true end
        end
        entry.specs[key] = nil
    end
    rebuildCustom(row.sectionId)
    return true
end

---A custom aura row's "Match by name": on, the entry matches every spell id
---carrying its spell's name (`by_name`, CustomSpells.GetAuraIdSet); off, exactly
---its id again.  Turning it on is refused while another by-name entry of the
---same list carries the same name -- both cells would fill from one aura -- and
---while the spell's name cannot be read.  Validated by listIndex + key like
---Remove.
---@param row tracking_row
---@param on boolean
---@return function|nil
local function planSetCustomByName(row, on)
    if type(row) ~= "table" or row.kind ~= "custom" or row.bucket ~= "aura" then return nil end
    local settings = hostSettings(row.sectionId)
    local list = settings and settings.custom_spells
    local entry = type(list) == "table" and row.listIndex and list[row.listIndex]
    if type(entry) ~= "table" or entry.spellID ~= row.key then return nil end
    if on then
        local name = C_Spell.GetSpellName(row.key)
        if not name or byNameTaken(list, name, entry) then return nil end
    end
    return function()
        entry.by_name = on and true or nil
        rebuildCustom(row.sectionId)
        -- The row's alert sounds follow the id set (CDMAlerts
        -- applyAuraRegistrations), which its signature cannot see.
        private.CDMAlerts.RebuildRegistrations()
        return true
    end
end

---@param row tracking_row
---@param on boolean
---@return boolean
local function setCustomByName(row, on)
    local plan = planSetCustomByName(row, on)
    if not plan then return false end
    return plan()
end

---Would SetCustomByName act?  Nothing is written.
---@param row tracking_row
---@param on boolean
---@return boolean
local function canSetCustomByName(row, on)
    return planSetCustomByName(row, on) ~= nil
end

---Set the row's icon override.  Resolve-then-write: an entry that already
---resolves for this key (possibly saved under an override or linked id) is
---replaced where it is, so the reader sees the new texture; otherwise the
---texture is saved under the row's key.
---@param row tracking_row
---@param textureOrSpellID number|string  a fileID or texture path, stored as given
---@return boolean
local function setIconOverride(row, textureOrSpellID)
    -- An addon-source id is a slot or a category, never a spell (newRow).
    if type(row) ~= "table" or type(row.key) ~= "number" or row.source then return false end
    local t = type(textureOrSpellID)
    if t ~= "number" and t ~= "string" then return false end
    local profile = private.profile
    if type(profile.icon_overrides) ~= "table" then profile.icon_overrides = {} end
    local key = private.Util.FindIconOverrideKey(row.key) or row.key
    profile.icon_overrides[key] = textureOrSpellID
    refreshChrome()
    return true
end

---Clear every icon override `Util.ResolveIconOverride(row.key)` could read,
---whichever identity id holds it.
---@param row tracking_row
---@return boolean removed
local function clearIconOverride(row)
    if type(row) ~= "table" or type(row.key) ~= "number" then return false end
    local profile = private.profile
    if type(profile.icon_overrides) ~= "table" then return false end
    local removed = false
    local key = private.Util.FindIconOverrideKey(row.key)
    while key do
        profile.icon_overrides[key] = nil
        removed = true
        key = private.Util.FindIconOverrideKey(row.key)
    end
    if removed then refreshChrome() end
    return removed
end

---May `row` take the "Force active" box?  A CDM row (a frame's claimed one
---too) outside a spell-rank family, the Rank menu's domain, that the character
---has but nothing draws, or that is already forced so it can be cleared.
---@param row tracking_row
---@return boolean
local function canForceActive(row)
    if type(row) ~= "table" or row.kind ~= "cdm" or type(row.key) ~= "number"
        or not row.bucket or row.family then
        return false
    end
    return (row.forced or (row.learned and not row.known)) and true or false
end

---Set or clear "Force active" for `row`'s entry, for every spec.
---@param row tracking_row
---@param value boolean
---@return boolean
local function setForceActive(row, value)
    if not canForceActive(row) then return false end
    local p = private.profile
    -- The shape overrideMap creates.
    if type(p.cdm_category_overrides) ~= "table" then
        p.cdm_category_overrides = { cooldown = {}, aura = {} }
    end
    local t = p.cdm_category_overrides
    if type(t.active) ~= "table" then t.active = {} end
    if type(t.active[row.bucket]) ~= "table" then t.active[row.bucket] = {} end
    t.active[row.bucket][row.key] = value and true or nil
    private.CDMDataSource.NotifyUserCategoryChanged()
    return true
end

---Would ResetMoves(bucket) clear anything?
---@param bucket "cooldown"|"aura"
---@return boolean
local function hasMoves(bucket)
    local map = resetTargetMap(bucket)
    return map ~= nil and next(map) ~= nil
end

---Clear every CUE category move of `bucket` from one layer (resetTargetMap):
---both trackers of the bucket share it.
---@param bucket "cooldown"|"aura"
---@return boolean cleared
local function resetMoves(bucket)
    local map = resetTargetMap(bucket)
    if not map or next(map) == nil then return false end
    wipe(map)
    private.CDMDataSource.NotifyUserCategoryChanged()
    return true
end

---Would ResetOrder(sectionId) clear anything?  This spec's own icon order
---counts while it exists, even empty: it still shadows the all-specs one.
---@param sectionId string
---@return boolean
local function hasOrder(sectionId)
    local settings = cdmSectionSpec(sectionId) and hostSettings(sectionId)
    if not settings then return false end
    local layer = orderLayerKey()
    if layer then return specOrder(settings, layer) ~= nil end
    return type(settings.priority_order) == "table" and #settings.priority_order > 0
end

---"Reset to default order", in one layer (resetTargetMap's rule): drop this
---spec's own icon order, so the tracker follows the all-specs order (or
---Blizzard's when that is empty); with the "All specs" box ticked or no spec
---system, empty the all-specs order.  Specs with their own order keep it.
---@param sectionId string
---@return boolean cleared
local function resetOrder(sectionId)
    if not hasOrder(sectionId) then return false end
    local settings = hostSettings(sectionId)
    local layer = orderLayerKey()
    if layer then
        settings.priority_order_spec[layer] = nil
    else
        wipe(settings.priority_order)
    end
    refreshComponent(sectionId)
    return true
end

---@type trackingmodel
private.TrackingModel = {
    BuildSections = buildSections,
    GetValidTargets = getValidTargets,
    Move = move,
    Reorder = reorder,
    AddFromSpellbook = addFromSpellbook,
    AddAuraByID = addAuraByID,
    GetCopyTargets = getCopyTargets,
    Copy = copy,
    GetAddonSourceChoices = getAddonSourceChoices,
    AddAddonSource = addAddonSource,
    Remove = remove,
    CanRemove = canRemove,
    SwapRank = swapRank,
    CanSwapRank = canSwapRank,
    SetSingleRank = setSingleRank,
    CanSetSingleRank = canSetSingleRank,
    SetFamilyMode = setFamilyMode,
    CanSetFamilyMode = canSetFamilyMode,
    SetCustomRank = setCustomRank,
    SetRestrictToPlayer = setRestrictToPlayer,
    SetCustomSpec = setCustomSpec,
    SetCustomByName = setCustomByName,
    CanSetCustomByName = canSetCustomByName,
    SetIconOverride = setIconOverride,
    ClearIconOverride = clearIconOverride,
    SetAllSpecs = function(on) allSpecs = on and true or false end,
    HasMoves = hasMoves,
    ResetMoves = resetMoves,
    HasOrder = hasOrder,
    ResetOrder = resetOrder,
    CanForceActive = canForceActive,
    SetForceActive = setForceActive,
}

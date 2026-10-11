---CDM (CooldownViewer) as a hidden data source for AuraContainer.
---
---Provides spell ID inclusion maps for AuraContainer candidateFilters.includeSpellIDs
---and fires OnCDMSpellsChanged when CDM configuration changes.
---
---**The addon no longer needs `cooldownViewerEnabled` for data.**
---`needsViewerChildren()` counts no viewer-child reader — every feature that once
---read a viewer child has been re-sourced or given up (see "CDM keep-alive bridge
----- REMOVED" below), so keeping the CDM alive for data would cost Blizzard's
---per-frame refresh for nothing.  The one thing that still writes `"1"` is the
---`cdm_target_sounds` option, which wants Blizzard's own ALERTS: an alert on the
---player's debuff on the target can only come from Blizzard's viewer.
---`needsViewerChildren` stays the single place to re-open the question.
---
---What is left is the OFFER.  `ensureEnabled` still runs on every path that
---could change the answer, works out that the CVar *could* go to "0", and
---**asks instead of writing** — someone running the CDM may be using it for
---something we do not render.
---
---And the offer, once accepted, is honoured **twice over**: one "0" write, and
---then viewer suppression for as long as the session's answer holds.  The second
---is what survives another addon enabling the CDM for its own purposes — we
---concede the CVar rather than fight it on every CVAR_UPDATE, and take the pixels
---instead.
---
---The CVar write is an ACTION taken once — the "0" we wrote stays "0" by itself,
---so nothing re-asserts it.  The ANSWER, though, is persisted
---(`charDB.cdm_hidden`), because suppression is what has to outlive whatever
---turns the CDM back on, and it cannot do that from a session local.  Alongside
---it: `charDB.cdm_never_ask` (silence the prompt) and `charDB.cdm_no_suppress`
---(leave Blizzard's frames alone entirely).
---
---Note the CVar gates ONLY ShouldBeShown.  The data APIs are not gated by it,
---so `cdm_auto_fetch` spell maps and the Tracking tab keep working
---either way; what stops is RefreshData, i.e. the viewer CHILDREN.
---
---Viewer suppression is gated on `suppressing` = `needsViewerChildren() or
---isHidden()`, and both halves earn their place:
---
---  * `needsViewerChildren()` — we forced the CVar to "1", so a viewer whose own
---    setting is "Always" is on screen only because we put it there.  Reached
---    only through `cdm_target_sounds`.
---  * `isHidden()` — the player asked for the CDM off and something turned it
---    back on.  Another addon may want the CVar for its own purposes; we concede
---    the CVar (one write, then never again) and take the pixels instead.
---
---Suppression is alpha and mouse ONLY.  The addon does not touch shown state in
---either direction: `Hide()` on the protected viewers is combat-blocked and
---fights Blizzard EditMode, and forcing them SHOWN is what the visibleSetting
---soft-override used to do — a tainted write that cost the CDM its aura alerts
---(see "The soft-override — REMOVED" below).
---
---Three reasons that USED to be listed here are gone, and none of them should be
---cited again: the Tracking tab reads `GetTrackedCooldownIDs`; Additional
---Frames no longer cross-parent live viewer children (`applyIconLayout` was
---deleted — every frame type renders through its own factory tracker); and
---SecondaryResources' proc scan (`reapFc.findSFIID`) went with the pre-12.1
---fallback whose branches were its only call sites.
---**The soft-override — REMOVED.**  An `IsEditing` post-hook used to nil
---`viewer.visibleSetting` so Blizzard's `ShouldBeShown` fell through to `return
---true` and kept a Hidden/In-Combat viewer alive for us.  `ShouldBeShown` reads
---`self:IsEditing()` and then `self.visibleSetting` **in the same call**, so the
---tainted nil the hook left behind tainted Blizzard's own execution from that
---read onward — including the `SetShown(true)` → `RefreshData()` branch of
---`UpdateShownState`, whose `SetCooldownID` writes then landed tainted on the
---item frames.  Blizzard reads those back from secure code on the UNIT_AURA
---path and hard-errors on `auraInstanceIDToItemFramesMap`
---(`DisallowTaintedAccess`, `CooldownViewerSecure.lua`), sticky until /reload.
---The error lands in `CheckAuraAddedAlertTriggers` — so the override broke
---exactly the Blizzard alerts that `cdm_target_sounds` keeps the viewer alive
---for.  It cannot be "re-nilled more carefully": any addon write to a field
---`ShouldBeShown` reads has the same effect.  A viewer the player set to
---Hidden/In Combat now simply stays hidden, and its Blizzard alerts stop with
---it.
---
---Call Initialize() from Init.lua once all CDM-wrapped components have been
---migrated to AuraContainer (Phases 2+).  In earlier phases this module is
---available but Initialize() is not wired up.

local _
---@type string, private
local addonName, private = ...

---@class cdmdatasource
---@field EnsureEnabled fun()
---@field Initialize fun()
---@field GetTrackedCooldownIDs fun(categoryId: number, includeItemBacked: boolean|nil, useBlizzardCategory: boolean|nil, includeUnknown: boolean|nil): number[] Resolved cooldownIDs for a category, off APIs the cooldownViewerEnabled CVar does not gate. includeItemBacked (default false) also admits 12.1 item-backed entries (nil spellID, synthetic resolvedKey); useBlizzardCategory (default false) filters on Blizzard's effective category instead of CUE's display category; includeUnknown (default false) also admits entries the character does not have — the Tracking tab only
---@field GetIconSource fun(key: number): table|nil How to draw an item-backed CDM entry (potion spell category / trinket equip slot); nil for an ordinary spell
---@field GetResolvedEntry fun(cooldownID: number): number|nil, number|nil, number|nil, boolean|nil, boolean|nil Tracker key, effective category, base spellID, known (resolvedKnown) and drawn (resolvedDrawn: spell-rank families) for a cooldownID; nil while the model is unresolved. A pure PEEK, never triggers the lazy build.
---@field GetDisplayCategory fun(cooldownID: number): number|nil CUE's display category (Blizzard's + cdm_category_overrides); nil while unresolved. A pure PEEK.
---@field GetDefaultCategory fun(cooldownID: number): number|nil The post-HideByDefault DB2 default category, which cdm_category_overrides legality is judged against; nil while unresolved. A pure PEEK.
---@field GetLayerCategory fun(cooldownID: number, map: table|nil): number|nil The category one override layer's bucket map gives the entry on its own; nil when none, or while unresolved. A pure PEEK.
---@field GetSpecLayerKey fun(): string|nil The current spec's cdm_category_overrides.spec key ("CLASS-N"); nil on a client with no spec system
---@field GetCategoryBucket fun(category: any): "cooldown"|"aura"|nil Which cdm_category_overrides sub-map a category belongs to; nil for item categories
---@field IsLegalCategoryMove fun(defaultCategory: number|nil, want: any): boolean May an entry with this default category be moved to `want`? Only within its own bucket
---@field NotifyUserCategoryChanged fun() Invalidate the resolved model now and queue the coalesced OnCDMSpellsChanged; call after writing cdm_category_overrides
---@field BuildComponentSpellMaps fun(categoryId: number, routeKey: string, componentName: string, includeLinked: boolean|nil): table<number, true>, table<number, true>
---@field IsDataAvailable fun(): boolean True while the CDM viewers are actually delivering (the CVar is on right now), not merely while the addon intends them to be
---@field GetAuraIdentitySet fun(spellID: number): table<number, true>|nil
---@field GetIdentityOwner fun(spellID: number): number|nil
---@field GetSpellOrderRanks fun(category: number): table<number, number>|nil Blizzard's CDM display order {[spellID] = rank} WITHIN one category; nil while unresolved or for an empty category
---@field GetOverrideSpellID fun(spellID: number): number|nil The overrideSpellID of the entry whose base spell is spellID
---@field IsResolved fun(): boolean True once the resolved-category model exists; lets early callers skip an identity walk instead of forcing the build
---@field ResolveNow fun(): boolean Build the model if Initialize() has run; for a UI that must show it and has no other builder
---@field GetResolvedSpecKey fun(): string|nil The spec layer key the current model was built with (its category overlay's, and the icon order's); a cached read for a layout pass, nil with no spec system
---@field IsEntryKey fun(spellID: number): boolean Is the id some entry's own row key (not only another entry's linked id)?  A peek: false while unresolved
---@field GetModelStamp fun(): number|nil Which model build is current, nil while unresolved; lets a derived cache notice a rebuild it did not run
---@field IsCooldownSpellTracked fun(key: number): boolean|nil Is this key a CooldownEssential/CooldownUtility/HiddenActive entry the character has, or one the user forced active? nil while the model is unresolved — callers must fail open
---@field GetRankedSpell fun(key: number): number|nil The highest learned rank a whole cooldown spell-rank family's representative is drawn as; nil for any other key. A peek.
---@field GetFamilyRep fun(spellID: number, bucket: "cooldown"|"aura"): number|nil The representative of the WHOLE spell-rank family spellID is in; nil otherwise. A peek.
---@field GetRankFamily fun(key: number, bucket: "cooldown"|"aura"): table|nil The spell-rank family a key belongs to (applyRankFamilies), whole or split. A peek.
---@field GetLinkedIdSet fun(spellID: number): table<number, true>|nil
---@field GetSwapIconSpell fun(spellID: number): number|nil
---@field SyncViewerSuppression fun()
---@field IsSuppressing fun(): boolean True while CUE holds Blizzard's viewers invisible — the hide toggle's real state, whichever of the saved answer or cdm_target_sounds put them there

---CDM viewer keys for all four categories (resolved via Util.GetViewerFrame).
local VIEWER_KEYS_LIST = {
    "CooldownEssential",
    "CooldownUtility",
    "BuffIcon",
    "BuffBar",
}

-- Resolved-set reconstruction -----------------------------------------------
--
-- C_CooldownViewer.GetCooldownViewerCategorySet returns DB2 DEFAULTS ONLY —
-- the user's CDM arrangement (category moves, hides, un-hides of
-- HideByDefault entries) lives Lua-side in CooldownViewerSettings' layout
-- manager, fed from the serialized layout blob.  Reading the raw category set
-- silently drops all of it.  Blizzard's own resolved view
-- (DataProvider:GetOrderedCooldownIDsForCategory) must NOT be called from
-- addon code: its dirty-rebuild path WRITES to the layout manager
-- (WriteCooldownOrderToActiveLayout), tainting the CDM saved-data path.
-- So we reconstruct the resolved set ourselves, mirroring
-- CheckBuildDisplayData: DB2 defaults (+ HideByDefault → hidden) overlaid
-- with the current spec's category overrides decoded from GetLayoutData().
-- Blob format: .context/patterns-cooldownviewer.md "GetLayoutData() blob format".

---Effective category per cooldownID after the HideByDefault flag and the
---user's layout overrides.  Negative values are hidden pseudo-categories
---(Blizzard: HiddenActive = -1, HiddenPassive = -2, assigned Lua-side by
---CooldownViewerSettingsConstants.lua) and never match a query.
local resolvedCategory = nil ---@type table<number, number>|nil
---The category per cooldownID after the HideByDefault flag and BEFORE the
---layout blob's overrides: the DB2 default as Blizzard's own settings start it.
---It is what `cdm_category_overrides` legality is judged against
---(isLegalCategoryMove) — never the overlaid value, so a Blizzard move cannot
---change which of CUE's two buckets an entry belongs to.
local resolvedDefaultCategory = nil ---@type table<number, number>|nil
---CUE's DISPLAY category per cooldownID: `resolvedCategory` (Blizzard's truth)
---with the profile's `cdm_category_overrides` laid over it
---(buildDisplayCategories).  Read by the three consumers that decide what CUE's
---four trackers DRAW — getTrackedSpellMap, the order projection, and
---getTrackedCooldownIDs (by default).  Alert routing (getResolvedEntry, and the
---getTrackedCooldownIDs walk CDMAlerts makes with `useBlizzardCategory`) and
---Additional-Frame membership (isCooldownSpellTracked) stay on
---`resolvedCategory`: the first must
---judge the category Blizzard's own viewer shows, the second must not change
---when a CUE-only move or hide happens.  See
---.context/patterns-cooldownviewer.md "Two effective categories".
local resolvedDisplayCategory = nil ---@type table<number, number>|nil
---The spell id per cooldownID, which is its base spellID EXCEPT for a sibling
---entry — one of several sharing a placeholder base, keyed by its own linked
---aura instead (findSiblingEntryKeys).  This is what the aura trackers key by,
---so it has to be the row id rather than the raw field; nil for an item-backed
---entry, which has no spellID at all.
local resolvedSpellID = nil ---@type table<number, number>|nil
---Blizzard's `isKnown`, except that an aura entry whose spell the character
---has (IsPlayerSpell) is known too: entryKnown.  Placement never changes it,
---so what follows Blizzard's categories (CDMAlerts' walk, Additional Frame
---membership) reads this one.
local resolvedKnown = nil ---@type table<number, boolean>|nil
---What CUE's display path DRAWS: `resolvedKnown`, except inside a spell-rank
---family (applyRankFamilies), where it depends on where the ranks sit.  Read by
---getTrackedSpellMap and getTrackedCooldownIDs' display branch only.
local resolvedDrawn = nil ---@type table<number, boolean>|nil
---The cooldownIDs drawn only because the user ticked "Force active"
---(applyForcedActive), a subset of `resolvedDrawn`.  Additional Frame
---membership (isCooldownSpellTracked) admits them too; alert replay does not.
local resolvedForced = nil ---@type table<number, true>|nil
---Spell-rank families by bucket, then member key (applyRankFamilies).  A key
---can be in one of each: a Forever rank has a cooldown and a buff entry.
---@type { cooldown: table<number, table>, aura: table<number, table> }|nil
local resolvedFamily = nil
---Spells a build requested data for (C_Spell.RequestLoadSpellData): true while
---the request is out, whose SPELL_DATA_LOAD_RESULT rebuilds, since their rank
---may not have read; false once answered, never asked again.
---Survives invalidation on purpose: the request is still out.
---@type table<number, boolean>
local pendingSpellData = {}
local resolvedSelfAura = nil ---@type table<number, boolean>|nil
---The tracker key per cooldownID: `resolvedSpellID` above (the base spellID, or
---a sibling entry's own linked aura), or a synthetic NEGATIVE key for the 12.1
---item-backed entries, which carry no spellID at all.  A negative
---number can never collide with a real spellID, so every downstream map, sort
---and button pool stays keyed by a plain number and needs no other change.
local resolvedKey = nil ---@type table<number, number>|nil
---Keyed by the synthetic key above: how to draw one item-backed entry.  Absent
---for ordinary spells, which is also how a consumer tells the two apart.
local resolvedSource = nil ---@type table<number, table>|nil
---Blizzard's display order.  Keyed by cooldownID: the index of the entry in the
---layout blob's `orderedCooldownIDs`, or ORDER_UNRANKED_BASE + the DB2
---category-set index for entries the blob does not mention (no saved layout at
---all, or a spell added since it was written).  Lower sorts first.
local resolvedOrder = nil ---@type table<number, number>|nil
---The same ranks keyed by SPELL id, which is what the trackers hold, BUCKETED
---BY EFFECTIVE CATEGORY: `[category][key] = rank`.
---
---The bucket is the whole point.  A base spellID repeats across categories --
---live 2026-09-14, a warrior's Sweeping Strikes `260708` is cooldownID `95964`
---in CooldownEssential and `33985` in BuffIcon, Berserking `26297` is `198853`
---and `198854` -- and `orderedCooldownIDs` is ONE flat list spanning every
---category, which Blizzard slices per category in
---GetOrderedCooldownIDsForCategory (CooldownViewerSettingsDataProvider.lua:249).
---A single global {spellID = min(rank)} map therefore let a spell's position in
---the cooldown bar decide its position in the buff bar, or the reverse; no user
---rearranging was needed, one of a pair having a cooldown entry was enough.
---The DB2 fallback had the same flaw, since ORDER_UNRANKED_BASE + i is a
---per-category index and so tied Essential #1 against BuffIcon #1.
---
---Within a bucket the lowest rank still wins: several cooldownIDs can resolve
---to one key inside one category (the Roll the Bones merge shape), and there
---the earliest position is the one Blizzard would draw it at.
local resolvedOrderBySpell = nil ---@type table<number, table<number, number>>|nil
---The set of tracker keys the character actually has in the two COOLDOWN
---categories, built lazily from the tables above and dropped with them, so it
---can never answer from a model that has since been invalidated.  Keyed by
---`resolvedKey` (base spellID, or the synthetic negative key for a 12.1
---item-backed entry), so potions and trinkets are members like any spell.
local cooldownTrackedKeys = nil ---@type table<number, true>|nil

---Blob-ranked entries occupy 1..#orderedCooldownIDs, so unranked ones sort
---after every ranked one while keeping their DB2 order among themselves.
local ORDER_UNRANKED_BASE = 100000
---Blizzard's static per-spell-category potion art, mirroring the file-local
---`spellCategoryMetadataLookup` in `CooldownViewerItemData.lua:405`.  Their
---`GetSpellTexture` returns this BEFORE any dynamic art (`:548`), so a potion
---entry always draws the generic icon and never depends on the player having
---used one this session.
local SPELL_CATEGORY_ICONS = {
    [4] = "Interface/ICONS/INV_POTION_114",
    [30] = "Interface/ICONS/INV_POTION_54",
    [1711] = "Interface/ICONS/Warlock_ Healthstone",
    [2566] = "Interface/ICONS/Warlock_ Bloodstone",
}
---Keyed by SPELL id (not cooldownID): the entry's full aura identity set, only
---for entries where it is wider than the base spell itself -- plus a sibling
---entry, whose set is its links alone and so can be exactly one id (its own key,
---which is what the caller would have filtered on anyway).
local resolvedIdentity = nil ---@type table<number, table<number, true>>|nil
---Keyed by SPELL id: the entry's LINKED aura ids only — no base, no override.
---The icon-swap slots filter on this rather than the full identity set, because
---the swap must key on Blizzard's own condition (a *linked* spell was found),
---not on "any of this entry's auras is up".
local resolvedLinked = nil ---@type table<number, table<number, true>>|nil
---Keyed by SPELL id: `linkedSpellIDs[1]`, the icon the swap displays.
local resolvedSwapIcon = nil ---@type table<number, number>|nil
---Reverse of resolvedIdentity: EVERY member of an entry's identity set (base,
---override, linked) → that entry's base spellID.  The aura-driven consumers pass
---`includeLinked`, so their spell maps hold linked and override ids as
---first-class keys, and anything keyed by the base spellID (an icon override, a
---per-spell setting) has to be reachable from those.  A linked id shared by two
---entries resolves to whichever was walked last — pathological, and both answers
---name a real owner.
local resolvedIdentityOwner = nil ---@type table<number, number>|nil
---Keyed by SPELL id: the entry's `overrideSpellID`, when it has one.
---
---Deliberately NOT part of the identity set for config lookups.  Base↔override
---is 1:1 within one cooldownID, so the two ids name the same thing and must
---behave identically downstream.  Base↔linked is 1:N and is precisely what
---distinguishes talent-swap variants (Outbreak's Virulent vs Dread, which share
---`spellID` and differ only in `linkedSpellIDs`) — walking linked ids in a
---routing or per-spell lookup would make configuring one variant silently
---capture its sibling.  See `.context/patterns-cooldownviewer.md`.
local resolvedOverride = nil ---@type table<number, number>|nil
---Every entry's row key (`resolvedSpellID`'s values).  A spellID can be one
---entry's own spell and another entry's linked id at once -- Mass Entanglement
---`102359` is a Utility entry and a linked id of Entangling Roots `339` -- and
---resolvedIdentityOwner keeps only the last writer, so this is how a caller
---tells an entry's own spell from a linked id.
local resolvedEntryKeys = nil ---@type table<number, true>|nil
---Counts builds, so a cache derived from the model can tell a rebuild it did
---not run from the build it was made against (getModelStamp).
local modelStamp = 0
---Set by initialize() at LOADING_SCREEN_DISABLED, once the client has its CDM
---data.  Declared up here: buildResolvedCategories reads it.
local initialized = false

---Forward declaration: buildResolvedCategories calls this to drop a build made
---before the client had data, and it is defined after that builder.
local invalidateResolvedCategories
---Forward declaration: the coalesced OnCDMSpellsChanged notifier.  It used to be
---a local of `initialize()`; hoisted to file scope so NotifyUserCategoryChanged
---can reuse it rather than re-implement the coalescing.
local fireSpellsChanged

---Decode the current character's CDM layout blob and return the current spec's
---category overrides as {[cooldownID] = category} plus its display order as
---{[cooldownID] = rank}.  Either may be nil independently — a layout can carry
---an order with no category moves — so they are decoded separately rather than
---sharing an early return.  Both nil when there is nothing to overlay: empty
---store (never customized), unknown encoding/save version, or no layout for the
---current spec — all normal states that degrade gracefully to DB2 defaults.
---@return table<number, number>|nil categoryOverrides
---@return table<number, number>|nil orderRanks
local function getLayoutCategoryOverrides()
    local data = C_CooldownViewer.GetLayoutData()
    if type(data) ~= "string" or data == "" then return nil end

    -- Format: "<encodingVersion>|<payload>", encoding version 1 =
    -- Base64(Deflate-raw(CBOR(dataTable))).
    local delim = string.find(data, "|", 1, true)
    if not delim or tonumber(string.sub(data, 1, delim - 1)) ~= 1 then return nil end
    local decoded = C_EncodingUtil.DecodeBase64(string.sub(data, delim + 1))
    if not decoded then return nil end
    local inflated = C_EncodingUtil.DecompressString(decoded, Enum.CompressionMethod.Deflate)
    if not inflated then return nil end
    -- One of the addon's two sanctioned catches (.context/patterns.md, "No
    -- `pcall` on our own code"); the other is CooldownLayoutSync.trySetLayoutData.
    -- Both decode a payload that reaches us already encoded, from an API that
    -- throws on one it cannot parse rather than returning nil. The error is
    -- handed to the standard handler, never swallowed — a blob we cannot read is
    -- reported, then degrades to DB2 defaults like every other "nothing to
    -- overlay" case above.
    local ok, decoded_or_err = pcall(C_EncodingUtil.DeserializeCBOR, inflated)
    if not ok then
        geterrorhandler()(decoded_or_err)
        return nil
    end
    local dataTable = decoded_or_err
    if type(dataTable) ~= "table" then return nil end

    -- dataTable: [1] save version, [2] specTag → active layoutID,
    -- [3] specTag → { layoutID → { [1] order, [2] categoryOverrides, [3] alerts } },
    -- [4] layoutID → name.  v4 (live) and v5 (12.1 PTR) share this shape;
    -- v3 and below keyed layouts by NAME — never overlay those.
    if (tonumber(dataTable[1]) or 0) < 4 then return nil end

    local classID = select(3, UnitClass("player"))
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not classID or not specIndex then return nil end
    local specTag = classID * 10 + specIndex -- CooldownViewerUtil MakeClassAndSpecTag

    -- CBOR round-trips can deliver map keys as text ("133") or number (133) —
    -- Blizzard's own DeserializeCooldownInfo tonumbers for the same reason.
    local layoutsField = dataTable[3]
    if type(layoutsField) ~= "table" then return nil end
    local specLayouts = layoutsField[specTag] or layoutsField[tostring(specTag)]
    if type(specLayouts) ~= "table" then return nil end
    local activeField = dataTable[2]
    local activeLayoutID = type(activeField) == "table" and (activeField[specTag] or activeField[tostring(specTag)]) or nil
    local container = activeLayoutID and (specLayouts[activeLayoutID] or specLayouts[tostring(activeLayoutID)]) or nil
    if type(container) ~= "table" then
        -- No recorded active layout for this spec: with exactly one stored
        -- layout it is unambiguous, otherwise don't guess.
        local onlyID, onlyContainer = next(specLayouts)
        if onlyID ~= nil and next(specLayouts, onlyID) == nil then
            container = onlyContainer
        end
    end
    if type(container) ~= "table" then return nil end

    -- [1] orderedCooldownIDs — the full display order across all categories.
    -- This is the only place Blizzard's user-arranged order is readable:
    -- GetCooldownViewerCategorySet returns DB2 defaults, and the resolved view
    -- (GetOrderedCooldownIDsForCategory) taints the saved-data path.
    local order = nil
    local orderedIds = container[1] or container["1"]
    if type(orderedIds) == "table" then
        order = {}
        for i = 1, #orderedIds do
            local id = tonumber(orderedIds[i])
            if id then order[id] = i end
        end
    end

    local categoryOverrides = container[2] or container["2"]
    if type(categoryOverrides) ~= "table" then return nil, order end
    local map = {}
    for category, cooldownIds in pairs(categoryOverrides) do
        local categoryN = tonumber(category)
        if categoryN and type(cooldownIds) == "table" then
            for i = 1, #cooldownIds do
                local id = tonumber(cooldownIds[i])
                if id then map[id] = categoryN end
            end
        end
    end
    return map, order
end

---Entries that must NOT dedupe onto their shared base spellID:
---{[cooldownID] = the id to key it by instead}, or nil when nothing splits.
---
---A base spellID is not unique across cooldownIDs, and there are two shapes of
---that.  Rogue Roll the Bones is the MERGE shape: two cooldownIDs on `1214909`,
---one with no links and one carrying all four buffs — one spell, one row, and
---the accumulated identity set below is exactly right for it.  Protection
---Paladin is the SPLIT shape: FOUR cooldownIDs all based on the spec aura
---`137028`, each carrying one different linked aura (Consecration `188370`,
---Sacred Weapon `432502`, and the two same-named Holy Bulwarks `432496` /
---`432607`).  Keying those by the base collapsed four tracked buffs into a
---single row named after a passive the player can never see, and — one frame
---per per-spell group — left Blizzard's container sort to pick which of the four
---was on it, which is how Holy Bulwark ended up showing the absorb instead of
---the aura granting it (live 2026-09-13).
---
---The rule is the difference between the two shapes: siblings are entries on one
---base whose link sets are non-empty and DIFFER.  One entry with links plus any
---number without is the merge shape and is left alone.  A sibling is keyed by
---its own `linkedSpellIDs[1]`, which is Blizzard's own priority-1 display source
---(`GetAssociatedAuraSpellPriority`, CooldownViewerItemData.lua:310) and a real
---spellID, so names, icons, order ranks and candidate filters all keep working
---with no new kind of key.
---
---Walks the category sets a second time rather than restructuring the builder
---into two phases: the answer is needed at the FIRST entry of a base and can
---only be known after the last, and this build is cached (login, spec change,
---CDM settings change), so one extra pass over ~60 entries is not a hot path.
---@return table<number, number>|nil siblingKey
local function findSiblingEntryKeys()
    -- Per base: the first link signature seen, and a flat {id, linked[1], ...}
    -- of every entry on it.  `multi` records the bases that saw a second,
    -- different signature — nil in the overwhelmingly common case.
    local firstSig, byBase, multi = {}, {}, nil
    for _, category in pairs(Enum.CooldownViewerCategory) do
        if type(category) == "number" and category >= 0 then
            local cooldownIds = C_CooldownViewer.GetCooldownViewerCategorySet(category, true)
            for i = 1, #cooldownIds do
                local id = cooldownIds[i]
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
                local linked = info and info.linkedSpellIDs
                if info and info.spellID and linked and #linked > 0 then
                    local base = info.spellID
                    -- Compare linked SETS, not arrays.  Two entries on one base
                    -- are siblings only when they can show different auras; the
                    -- array order is Blizzard's and is not stable between
                    -- entries, so an order-sensitive signature splits an entry
                    -- from its identical twin.  Live: a classic-content client
                    -- lists every RANK of a spell in linkedSpellIDs, and the two
                    -- Moonfire entries carry the same ten ranks in different
                    -- order -- so both were keyed under their own linked[1]
                    -- (8925 and 8921 rather than the base 8921 twice), and a
                    -- manually added 8921 no longer collided with the tracked
                    -- one.  Two Moonfire icons on the cooldown bar.
                    local sorted = {}
                    for k = 1, #linked do sorted[k] = linked[k] end
                    table.sort(sorted)
                    local sig = table.concat(sorted, ",")
                    local list = byBase[base]
                    if not list then
                        list = {}
                        byBase[base] = list
                        firstSig[base] = sig
                    elseif firstSig[base] ~= sig then
                        multi = multi or {}
                        multi[base] = true
                    end
                    list[#list + 1] = id
                    list[#list + 1] = linked[1]
                end
            end
        end
    end
    if not multi then return nil end
    local siblingKey = {}
    for base in pairs(multi) do
        local list = byBase[base]
        for i = 1, #list, 2 do
            siblingKey[list[i]] = list[i + 1]
        end
    end
    return siblingKey
end

---Project cooldownID-keyed ranks onto tracker keys, bucketed by effective
---category -- the shape `resolvedOrderBySpell` documents, and the reason it is
---not one flat map.
---
---A standalone pure function so tests/orderbucket_check.lua can drive the real
---code rather than a transcription; inlining it back into
---buildResolvedCategories fails that extraction rather than silently passing.
---@param order table<number, number>  rank keyed by cooldownID
---@param keyByID table<number, number>  tracker key keyed by cooldownID
---@param categoryByID table<number, number>  effective category keyed by cooldownID
---@return table<number, table<number, number>>  [category][key] = rank
local function projectOrderRanksByCategory(order, keyByID, categoryByID)
    local byCategory = {}
    for id, rank in pairs(order) do
        local key = keyByID[id]
        local category = categoryByID[id]
        if key and category then
            local bucket = byCategory[category]
            if not bucket then
                bucket = {}
                byCategory[category] = bucket
            end
            -- Lowest rank wins WITHIN a bucket only: several cooldownIDs can
            -- resolve to one key inside one category (the Roll the Bones merge
            -- shape), and there the earliest position is the one Blizzard draws
            -- it at.  Across categories they are unrelated positions.
            if bucket[key] == nil or rank < bucket[key] then
                bucket[key] = rank
            end
        end
    end
    return byCategory
end

---The category a `HideByDefault` entry starts in, before any layout override.
---Mirrors Blizzard's `cooldownCategoryToHiddenCategoryMapping`
---(CooldownViewerSettingsDataProvider.lua:66): Essential/Utility defaults go to
---HiddenActive (-1), TrackedBuff/TrackedBar defaults to HiddenPassive (-2), and
---the item categories (EquipSlot*/SpecAgnostic*) stay in their own category —
---their own container IS their default hidden place.  Flattening everything to
----1 filed hidden auras under the spell pseudo-category and pulled item entries
---out of the categories Blizzard keeps them in.
---
---The two hidden values are Lua-side additions, not part of the C enum, so the
---numeric fallback covers a client where Blizzard_CooldownViewer has not loaded
---them.  A standalone pure function so tests/orderbucket_check.lua can drive it.
---@param category number  the entry's DB2 default category
---@return number
local function hiddenCategoryFor(category)
    local cats = Enum.CooldownViewerCategory
    if category == cats.Essential or category == cats.Utility then
        return cats.HiddenActive or -1
    end
    if category == cats.TrackedBuff or category == cats.TrackedBar then
        return cats.HiddenPassive or -2
    end
    return category
end

---Which of `cdm_category_overrides`' two sub-maps a category belongs to:
---"cooldown" for Essential/Utility/HiddenActive, "aura" for
---TrackedBuff/TrackedBar/HiddenPassive, nil for anything else (the item
---categories, a non-number from corrupt saved data).
---
---Two buckets because one base spellID can be BOTH a cooldown entry and an
---aura entry (a warrior's Sweeping Strikes `260708` is cooldownID `95964` in
---CooldownEssential and `33985` in BuffIcon — resolvedOrderBySpell's
---declaration), and those must move independently.  Blizzard's own legality
---table (`legalOriginalSourceCategoryToTargetCategory`,
---CooldownViewerSettings.lua) never lets an entry cross between the two either.
---Same numeric fallback for the Lua-side hidden values as hiddenCategoryFor.  A
---standalone pure function so tests/displaycategory_check.lua can drive it.
---@param category any
---@return "cooldown"|"aura"|nil
local function categoryBucket(category)
    if type(category) ~= "number" then return nil end
    local cats = Enum.CooldownViewerCategory
    if category == cats.Essential or category == cats.Utility
        or category == (cats.HiddenActive or -1) then
        return "cooldown"
    end
    if category == cats.TrackedBuff or category == cats.TrackedBar
        or category == (cats.HiddenPassive or -2) then
        return "aura"
    end
    return nil
end

---Is a CDM entry the character's (`resolvedKnown`)?  Blizzard's `isKnown`,
---except that an AURA entry whose spell the character has is known whatever
---isKnown says.  WoW Forever has one entry per rank, and its conditions read
---known only for the highest rank the character has (Rejuvenation rank 1's
---never: it names spell 744).  An aura cell shows only while its aura is up,
---so a lower rank costs nothing and shows a down-ranked cast; a cooldown icon
---always shows, so the cooldown side keeps isKnown (ten Moonfire icons
---otherwise).  .context/memory/project_forever_support.md.
---@param info table  a CooldownViewerCooldown
---@return boolean
local function entryKnown(info)
    if info.isKnown then return true end
    if info.spellID and categoryBucket(info.category) == "aura" then
        return IsPlayerSpell(info.spellID) and true or false
    end
    return false
end

---WoW Forever's spell ranks, as the display path draws them.  Forever's CDM has
---one entry per rank (Moonfire: ten cooldown and ten buff entries), each known
---only while it is the character's highest rank.  Entries with a rank
---(Util.SpellRank) group into a FAMILY by bucket and spell name; its
---representative is the lowest rank's key, stable across rank-ups, so order,
---colours, pandemic excludes and icon overrides survive learning a rank.
---
---  WHOLE (every member in one non-hidden display category, the default):
---  the representative alone is drawn, while any member is learned.  A buff
---  family's ranks fold into the representative's identity set, so its one
---  cell matches whichever rank is up ("All ranks"); a cooldown family is
---  drawn as its highest learned rank (`highest`, GetRankedSpell: "Highest").
---  A buff family's ranks also map to the representative in the owner map, so
---  config, routing and the aura frames resolve any rank to the family; a
---  cooldown family is found by bucket (GetFamilyRep) instead.
---  SPLIT: each member is drawn while learned, both buckets — a lower rank the
---  player placed on its own, which isKnown would hide.
---
---Retail spells carry no rank, so no family forms there.  A pure function of
---its arguments (and three client reads), so tests can extract it.
---@param spellByID table<number, number>  resolvedSpellID
---@param keyByID table<number, number>  resolvedKey
---@param defaultByID table<number, number>  resolvedDefaultCategory
---@param displayByID table<number, number>  resolvedDisplayCategory
---@param knownByID table<number, boolean>  resolvedKnown
---@param identity table<number, table<number, true>>  resolvedIdentity, folded in place
---@param identityOwner table<number, number>  resolvedIdentityOwner, folded in place
---@return table<number, boolean> drawn  per cooldownID
---@return table families  { cooldown = {[key] = family}, aura = {[key] = family} }
---@return table<number, true> uncached  spells whose data is not loaded yet, so their rank may not read; the caller requests them
local function applyRankFamilies(spellByID, keyByID, defaultByID, displayByID, knownByID,
        identity, identityOwner)
    local drawn, families, uncached = {}, { cooldown = {}, aura = {} }, {}
    local groups = {}
    for id, spellID in pairs(spellByID) do
        drawn[id] = knownByID[id] and true or false
        local bucket = categoryBucket(defaultByID[id])
        if bucket and not C_Spell.IsSpellDataCached(spellID) then uncached[spellID] = true end
        local rank = bucket and private.Util.SpellRank(spellID)
        local name = rank and C_Spell.GetSpellName(spellID)
        if name then
            local groupKey = bucket .. "\0" .. name
            local list = groups[groupKey]
            if not list then
                list = { bucket = bucket }
                groups[groupKey] = list
            end
            list[#list + 1] = { id = id, key = keyByID[id], spellID = spellID,
                rank = private.Util.RankNumber(rank) }
        end
    end
    for _, list in pairs(groups) do
        if #list > 1 then
            table.sort(list, function(a, b)
                if a.rank ~= b.rank then return a.rank < b.rank end
                return a.id < b.id
            end)
            local rep = list[1].key
            local category = displayByID[list[1].id]
            local whole = category ~= nil and category >= 0
            local anyLearned, highest = false, nil
            for i = 1, #list do
                local member = list[i]
                member.learned = IsPlayerSpell(member.spellID) and true or false
                if member.learned then
                    anyLearned = true
                    highest = member.spellID
                end
                if displayByID[member.id] ~= category then whole = false end
            end
            local family = { rep = rep, bucket = list.bucket, whole = whole, highest = highest,
                members = list }
            for i = 1, #list do
                local member = list[i]
                families[list.bucket][member.key] = family
                if whole then
                    drawn[member.id] = member.key == rep and anyLearned
                else
                    drawn[member.id] = member.learned
                end
            end
            -- A whole BUFF family folds into the identity set and owner map.
            -- Both are keyed by spell id, which a rank's cooldown and buff
            -- entries share, so folding a cooldown family too would widen a
            -- split buff family's rank-1 cell to every rank, and re-key a buffs
            -- frame's rank to the cooldown family.  Cooldown families are found
            -- by bucket instead (GetFamilyRep).
            if whole then
                if list.bucket == "aura" then
                    local set = identity[rep]
                    if not set then
                        set = {}
                        identity[rep] = set
                    end
                    for i = 1, #list do
                        local member = list[i]
                        set[member.spellID] = true
                        local own = identity[member.key]
                        if own and own ~= set then
                            for sid in pairs(own) do set[sid] = true end
                        end
                    end
                    for sid in pairs(set) do identityOwner[sid] = rep end
                end
            end
        end
    end
    return drawn, families, uncached
end

---"Force active" (TrackingModel.SetForceActive): draw an entry Blizzard's CDM
---counts inactive -- on WoW Forever, a cooldown whose condition reads false
---although the spell is in the spellbook.  Not automatic: on retail isKnown
---false beside IsPlayerSpell true is also Blizzard hiding a replaced spell
---(IsPlayerSpell is override-blind).  `active` is
---`cdm_category_overrides.active`, bucket → tracker key → true, for every spec.
---
---A spell-rank family member is skipped: the Rank menu places its ranks.  A
---cooldown is forced only while the character has the spell: its icon always
---shows, and a profile is shared by characters and specs.  An aura cell shows
---only while its aura is up, so an aura is forced as is.  Writes `drawn` in
---place.  A pure function of its arguments (and IsPlayerSpell), for tests.
---@param spellByID table<number, number>  resolvedSpellID
---@param keyByID table<number, number>  resolvedKey
---@param defaultByID table<number, number>  resolvedDefaultCategory
---@param families table  applyRankFamilies' families
---@param active table|nil  profile.cdm_category_overrides.active, shape unvalidated
---@param drawn table<number, boolean>  resolvedDrawn
---@return table<number, true> forced  per cooldownID
local function applyForcedActive(spellByID, keyByID, defaultByID, families, active, drawn)
    local forced = {}
    if type(active) ~= "table" then return forced end
    for id, spellID in pairs(spellByID) do
        local bucket = categoryBucket(defaultByID[id])
        local map = bucket and active[bucket]
        local key = keyByID[id]
        if type(map) == "table" and key and map[key] == true and not families[bucket][key]
            and (bucket == "aura" or IsPlayerSpell(spellID)) then
            drawn[id] = true
            forced[id] = true
        end
    end
    return forced
end

---May a `cdm_category_overrides` value move an entry whose DEFAULT category
---(post-HideByDefault, pre-layout — `resolvedDefaultCategory`) is
---`defaultCategory` to `want`?  Only within the entry's own bucket.  An item
---category default has no bucket, so an item-backed entry is never a legal
---target.  Pure, for tests/displaycategory_check.lua.
---@param defaultCategory number|nil
---@param want any
---@return boolean
local function isLegalCategoryMove(defaultCategory, want)
    local bucket = categoryBucket(defaultCategory)
    return bucket ~= nil and categoryBucket(want) == bucket
end

---The category one bucket map of one override layer gives an entry, or nil
---when it holds none the entry may take.  The lookup key is the entry's
---tracker key — the same key `priority_order` holds — then the entry's
---`overrideSpellID`, the base↔override equivalence
---`Util.ResolveByBaseOrOverride` applies everywhere else (a value saved under
---the id Blizzard's item frame displays must still find its entry).  Linked ids
---are deliberately not walked: they are what tell talent-swap variants apart.
---Legality is judged from the DEFAULT category, never an overlaid one.
---Pure, for tests/displaycategory_check.lua.
---@param map any  one bucket map, shape unvalidated
---@param key number
---@param alias number|nil  the entry's overrideSpellID
---@param default number|nil  the entry's default category
---@return number|nil
local function layerValue(map, key, alias, default)
    if type(map) ~= "table" then return nil end
    local want = map[key]
    if want == nil and alias then want = map[alias] end
    if want ~= nil and isLegalCategoryMove(default, want) then return want end
    return nil
end

---Lay the profile's `cdm_category_overrides` over Blizzard's effective
---categories, returning CUE's display categories as a NEW table.
---`categoryByID` is never written: it stays Blizzard's truth for alert routing
---and Additional-Frame membership.
---
---Two layers, per bucket: the current spec's (`overrides.spec[specKey]`), then
---the all-specs one (`overrides.cooldown` / `.aura`), each looked up through
---`layerValue`.  The first that gives the entry a legal category wins.  An
---item-backed entry (a key in `sourceByKey`) is skipped outright.  A standalone
---pure function so tests/displaycategory_check.lua drives the real code.
---@param categoryByID table<number, number>  resolvedCategory
---@param defaultByID table<number, number>  resolvedDefaultCategory
---@param keyByID table<number, number>  resolvedKey
---@param sourceByKey table<number, table>  resolvedSource (item-backed marker)
---@param overrideByKey table<number, number>  resolvedOverride
---@param overrides table|nil  profile.cdm_category_overrides, shape unvalidated
---@param specKey string|nil  the current spec's layer (getSpecLayerKey)
---@return table<number, number>
local function buildDisplayCategories(categoryByID, defaultByID, keyByID, sourceByKey,
                                      overrideByKey, overrides, specKey)
    local display = {}
    for id, category in pairs(categoryByID) do
        display[id] = category
    end
    -- Validated on read: saved data can be corrupted by an external editor, so
    -- no table on the way down is trusted to be a table.
    if type(overrides) ~= "table" then return display end
    local specLayer = specKey and type(overrides.spec) == "table" and overrides.spec[specKey]
    if type(specLayer) ~= "table" then specLayer = nil end
    for id in pairs(categoryByID) do
        local key = keyByID[id]
        local default = defaultByID[id]
        local bucket = key and not sourceByKey[key] and categoryBucket(default)
        if bucket then
            local alias = overrideByKey[key]
            local want = (specLayer and layerValue(specLayer[bucket], key, alias, default))
                or layerValue(overrides[bucket], key, alias, default)
            if want ~= nil then display[id] = want end
        end
    end
    return display
end

---The last key getSpecLayerKey resolved, for the transient nil
---`GetSpecialization()` returns after a loading screen
---(Components/PrimaryResources.lua `cachedSpecIndex`).
local lastSpecLayerKey

---The key of the current spec's `cdm_category_overrides.spec` layer —
---`"CLASS-N"`, the shape CooldownLayoutSync's old per-spec keys had — or nil on
---a client with no spec system, which reads and writes the all-specs layer
---only.  `GetNumSpecializations() <= 1` is that test, and Blizzard's own
---(Components/PrimaryResources.lua `getRealSpecIndex`): a client with no specs
---still answers `GetSpecialization()` with 1.
---@return string|nil
local function getSpecLayerKey()
    if GetNumSpecializations() <= 1 then return nil end
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if specIndex and specIndex > 0 then
        lastSpecLayerKey = select(2, UnitClass("player")) .. "-" .. specIndex
    end
    return lastSpecLayerKey
end

---The spec layer key the resolved model was built with (getSpecLayerKey at
---build time), for getResolvedSpecKey.
local resolvedSpecKey

---Build the resolved caches: every cooldownID in every non-hidden runtime
---category (12.1 adds EquipSlot*/SpecAgnostic* beyond the classic 0–3), its
---effective category, spellID, and isKnown.  HideByDefault-flagged entries
---start in their hidden category (hiddenCategoryFor); layout overrides then apply in either direction (hide AND
---un-hide), exactly like Blizzard's CheckBuildDisplayData.
local function buildResolvedCategories()
    resolvedCategory, resolvedSpellID, resolvedKnown, resolvedSelfAura = {}, {}, {}, {}
    resolvedDefaultCategory = {}
    resolvedKey, resolvedSource = {}, {}
    resolvedIdentity, resolvedLinked, resolvedSwapIcon = {}, {}, {}
    resolvedIdentityOwner, resolvedOverride, resolvedEntryKeys = {}, {}, {}
    resolvedOrder, resolvedOrderBySpell = {}, {}
    modelStamp = modelStamp + 1
    -- Which entries must be keyed by their own linked aura instead of by the
    -- base spellID they share with their siblings.  nil for most characters.
    local siblingKey = findSiblingEntryKeys()
    -- "Not ready yet" sentinel, before initialize() only (below): zero ids
    -- across ALL categories then means the client has not populated them.
    local sawAnyCooldownID = false
    for _, category in pairs(Enum.CooldownViewerCategory) do
        -- Negative values are Blizzard's Lua-side hidden pseudo-categories
        -- (added by CooldownViewerSettingsConstants.lua) — not fetchable sets.
        if type(category) == "number" and category >= 0 then
            local cooldownIds = C_CooldownViewer.GetCooldownViewerCategorySet(category, true)
            sawAnyCooldownID = sawAnyCooldownID or #cooldownIds > 0
            for i = 1, #cooldownIds do
                local id = cooldownIds[i]
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
                if info then
                    local effective = info.category
                    if FlagsUtil.IsSet(info.flags, Enum.CooldownSetSpellFlags.HideByDefault) then
                        effective = hiddenCategoryFor(info.category)
                    end
                    resolvedCategory[id] = effective
                    resolvedDefaultCategory[id] = effective
                    -- The id this entry is a ROW under.  Its base spellID,
                    -- except for a sibling entry sharing a placeholder base
                    -- with other entries (findSiblingEntryKeys), which is a row
                    -- of its own under its own linked aura.
                    local entryKey = (siblingKey and siblingKey[id]) or info.spellID
                    resolvedSpellID[id] = entryKey
                    if entryKey then resolvedEntryKeys[entryKey] = true end
                    -- 12.1 item-backed entries: potions and healthstones are
                    -- identified by spellCategoryID, trinkets by equipSlot, and
                    -- BOTH carry a nil spellID (`spellID` is Nilable in
                    -- CooldownViewerDocumentation.lua:132).  Blizzard requires
                    -- none — its own display gate checks category + isKnown +
                    -- isInvisible only (CooldownViewerSettingsDataProvider.lua
                    -- :254) — so keying the trackers by spellID alone dropped
                    -- every potion and trinket the player had arranged into a
                    -- tracked category.  The pre-rework trackers laid out
                    -- Blizzard's own viewer children and so never saw this.
                    local key = entryKey
                    if not key and (info.spellCategoryID or info.equipSlot) then
                        key = -id
                        resolvedSource[key] = {
                            spellCategoryID = info.spellCategoryID,
                            equipSlot = info.equipSlot,
                            icon = info.spellCategoryID
                                and SPELL_CATEGORY_ICONS[info.spellCategoryID] or nil,
                        }
                    end
                    resolvedKey[id] = key
                    resolvedKnown[id] = entryKnown(info)
                    resolvedSelfAura[id] = info.selfAura and true or false
                    -- DB2 fallback rank: the category set is already in
                    -- Blizzard's default display order, so the array index IS
                    -- the order for anyone who never customized the CDM.
                    -- Overwritten below by the blob's order where it has one.
                    resolvedOrder[id] = ORDER_UNRANKED_BASE + i
                    -- Aura identity set, recorded only when it is wider than the
                    -- base spell — the info table is already fetched here, so
                    -- this costs no extra API calls.
                    local linked = info.linkedSpellIDs
                    -- 12.1 item-backed entries carry a nil base spellID while
                    -- still having override/linked ids.  The identity maps are
                    -- keyed BY the base spell, so there is no key to file them
                    -- under — skip them.  Their synthetic key is deliberately
                    -- never handed to an aura consumer (see getTrackedSpellMap),
                    -- so nothing looks them up here; the linked expansion in that
                    -- function is how a trinket's buff auras still reach the aura
                    -- trackers, as real spellIDs.
                    local sibling = siblingKey and siblingKey[id]
                    if entryKey and (info.overrideSpellID or (linked and #linked > 0)) then
                        -- ACCUMULATE, never overwrite.  These maps are keyed by
                        -- SPELL id and a spellID is not unique across entries
                        -- (patterns-cooldownviewer.md) -- live 2026-09-13, Rogue
                        -- Roll the Bones `1214909` is TWO cooldownIDs, one with no
                        -- links and one carrying all four buffs.  A flat write
                        -- makes the survivor a function of walk order, and the
                        -- loser is a strict SUBSET here: if the link-less entry
                        -- lands last, the aura group's candidate filter narrows to
                        -- the base id alone and the tracker matches nothing at all.
                        -- Merging is also what the filter wants on its own terms --
                        -- both entries dedupe to one map key, so one row has to
                        -- match any aura either of them can show.
                        local set = resolvedIdentity[entryKey]
                        if not set then
                            set = {}
                            resolvedIdentity[entryKey] = set
                        end
                        if sibling then
                            -- A sibling's identity is its own linked aura and
                            -- nothing else.  The shared base is a placeholder
                            -- its siblings answer to as well, so admitting it
                            -- would put every one of them back on one aura --
                            -- and a spec aura is permanently on the player,
                            -- which is the worst thing to put in a filter.  Its
                            -- overrideSpellID mirrors the base (live: `137028`
                            -- for all four Protection Paladin entries) and is
                            -- excluded with it.
                            for k = 1, #linked do set[linked[k]] = true end
                        else
                            set[info.spellID] = true
                            if info.overrideSpellID then
                                set[info.overrideSpellID] = true
                            end
                            if linked then
                                for k = 1, #linked do set[linked[k]] = true end
                            end
                        end
                        for id in pairs(set) do
                            resolvedIdentityOwner[id] = entryKey
                        end
                        -- Skipped for a sibling for the same reason: base and
                        -- override are two names for ONE cooldownID, and here
                        -- they would name all of them, so a config saved under
                        -- the base would resolve to every sibling at once.
                        if info.overrideSpellID and not sibling then
                            resolvedOverride[entryKey] = info.overrideSpellID
                        end
                    end
                    -- Linked-only set + swap icon for the icon-swap slots.  Same
                    -- free ride on the already-fetched info table, and merged for
                    -- the same reason as the identity set above -- talent-swap
                    -- variants are mutually exclusive in play, so a wider set
                    -- cannot reveal two swaps at once.  The swap ICON keeps the
                    -- FIRST entry's `linked[1]` rather than the last: it is one
                    -- texture and there is nothing to merge, so the stable answer
                    -- beats the arbitrary one.
                    if entryKey and linked and #linked > 0 then
                        local linkedSet = resolvedLinked[entryKey]
                        if not linkedSet then
                            linkedSet = {}
                            resolvedLinked[entryKey] = linkedSet
                        end
                        for k = 1, #linked do linkedSet[linked[k]] = true end
                        resolvedSwapIcon[entryKey] = resolvedSwapIcon[entryKey]
                            or linked[1]
                    end
                end
            end
        end
    end
    -- Never CACHE a build made before the client had data.  Components enable on
    -- PLAYER_LOGIN (Core/Init.lua) while Initialize() deliberately waits for
    -- LOADING_SCREEN_DISABLED, so anything that lazily builds in that window used
    -- to lock in empty tables: they are non-nil, so every later getTrackedSpellMap
    -- skipped the rebuild and returned an empty map, and nothing invalidates on
    -- LOADING_SCREEN_DISABLED — so all four CDM trackers stayed empty for the whole
    -- session (live 2026-08-20, reached via a routing query; see §I of
    -- .context/migration-parity-gaps.md).  Dropping the caches makes the next call
    -- retry instead, which is the correct behaviour for any early caller.
    -- After initialize() an empty CDM is the truth: WoW Forever has no CDM data
    -- for Shaman, Rogue, Hunter or Paladin, and a model that never resolved kept
    -- the Tracking tab on "not ready" (no spellbook, no custom spells) and
    -- rebuilt on every call.
    if not sawAnyCooldownID and not initialized then
        invalidateResolvedCategories()
        return
    end
    local overrides, order = getLayoutCategoryOverrides()
    if overrides then
        for id, category in pairs(overrides) do
            -- Ignore saved ids no longer in static data — Blizzard prunes the
            -- same way when rebuilding display data.
            if resolvedCategory[id] ~= nil then
                resolvedCategory[id] = category
            end
        end
    end
    if order then
        for id, rank in pairs(order) do
            -- Same pruning rule as the category overlay.
            if resolvedCategory[id] ~= nil then
                resolvedOrder[id] = rank
            end
        end
    end
    -- CUE's own category moves/hides, after Blizzard's: the order projection
    -- below and the tracker maps bucket by what CUE draws.
    resolvedSpecKey = getSpecLayerKey()
    resolvedDisplayCategory = buildDisplayCategories(resolvedCategory,
        resolvedDefaultCategory, resolvedKey, resolvedSource, resolvedOverride,
        private.profile and private.profile.cdm_category_overrides, resolvedSpecKey)
    -- After the display categories: a family's shape is where its ranks sit.
    -- A spell whose data is not loaded may not read its rank yet; its load
    -- (SPELL_DATA_LOAD_RESULT, initialize) rebuilds.
    local uncached
    resolvedDrawn, resolvedFamily, uncached = applyRankFamilies(resolvedSpellID, resolvedKey,
        resolvedDefaultCategory, resolvedDisplayCategory, resolvedKnown, resolvedIdentity,
        resolvedIdentityOwner)
    -- Once per session: a spell its load never caches (spell 0 in Forever's CDM
    -- data) would be asked again by the rebuild its answer starts — a model
    -- rebuild, and a Tracking tab render, every frame.
    for spellID in pairs(uncached) do
        if pendingSpellData[spellID] == nil then
            pendingSpellData[spellID] = true
            C_Spell.RequestLoadSpellData(spellID)
        end
    end
    local overrides = private.profile and private.profile.cdm_category_overrides
    resolvedForced = applyForcedActive(resolvedSpellID, resolvedKey, resolvedDefaultCategory,
        resolvedFamily, type(overrides) == "table" and overrides.active or nil, resolvedDrawn)
    resolvedOrderBySpell = projectOrderRanksByCategory(resolvedOrder, resolvedKey,
        resolvedDisplayCategory)
end

---Drop the resolved caches; the next getTrackedSpellMap rebuilds lazily.
invalidateResolvedCategories = function()
    resolvedCategory, resolvedSpellID, resolvedKnown, resolvedSelfAura = nil, nil, nil, nil
    resolvedDrawn, resolvedFamily, resolvedForced = nil, nil, nil
    resolvedDefaultCategory, resolvedDisplayCategory = nil, nil
    resolvedKey, resolvedSource = nil, nil
    resolvedIdentity, resolvedLinked, resolvedSwapIcon = nil, nil, nil
    resolvedIdentityOwner, resolvedOverride, resolvedEntryKeys = nil, nil, nil
    resolvedOrder, resolvedOrderBySpell = nil, nil
    resolvedSpecKey = nil
    cooldownTrackedKeys = nil
end

---Set while a coalesced OnCDMSpellsChanged is queued for the next frame.
local pendingFire = false

---Invalidate and fire OnCDMSpellsChanged, coalesced to one per frame so a burst
---(SPELLS_CHANGED storms at login/zone change, several settings callbacks)
---costs one rebuild.
fireSpellsChanged = function()
    if pendingFire then return end
    pendingFire = true
    C_Timer.After(0, function()
        pendingFire = false
        invalidateResolvedCategories()
        private.Callback.Trigger("OnCDMSpellsChanged")
    end)
end

---The profile's `cdm_category_overrides` just changed (a Tracking-model move,
---hide, a segment import or a profile switch): drop the resolved model NOW and queue the
---coalesced OnCDMSpellsChanged.
---
---The synchronous invalidation is the half fireSpellsChanged alone does not
---give: its own invalidate waits a frame, and `ImportFullProfile` runs a
---synchronous `FullLayoutRefresh` straight after the segment apply, which would
---otherwise lay out one pass against the pre-import overlay.  The queued fire
---then re-invalidates (one extra lazy rebuild, on a user action) and wakes every
---tracker, CDMAlerts and the Additional Frames.
local function notifyUserCategoryChanged()
    invalidateResolvedCategories()
    fireSpellsChanged()
end

---Build the resolved model on demand, and report whether it is usable.
---
---Returns FALSE while the client has no CDM data yet -- buildResolvedCategories
---deliberately refuses to cache such a build, so the tables stay nil and every
---accessor below must degrade instead of indexing them.  Callers get "nothing
---tracked" for the moment, and the real answer as soon as the data lands.
---@return boolean ready
local function ensureResolved()
    if not resolvedCategory then
        buildResolvedCategories()
    end
    return resolvedCategory ~= nil
end

---Blizzard's CDM display order WITHIN ONE CATEGORY as {[spellID] = rank}, lower
---first.  Sort a tracker's icons by this to match the arrangement the player set
---up in the CooldownViewer settings; entries with no rank (custom spells, which
---the CDM has never heard of) are the caller's problem to place.
---
---The category argument is not optional, and there is no global view on purpose:
---a rank is a position inside a category, and a spellID that appears in two
---categories has two unrelated ones (see resolvedOrderBySpell's declaration).
---
---Returns nil while the resolved model is unavailable, per the lazy-cache rule
---in patterns.md — callers degrade to their own tie-break rather than crash.
---Also nil for a category the character has no entries in, which callers treat
---the same way.  The table is the cached model, rebuilt only on invalidation, so
---this is a lookup and safe to call from a layout pass.  Do not mutate it.
---@param category number  an Enum.CooldownViewerCategory value
---@return table<number, number>|nil
local function getSpellOrderRanks(category)
    if not ensureResolved() then return nil end
    return resolvedOrderBySpell[category]
end

---Return a {[spellID]=true} inclusion map for all LEARNED spells whose
---EFFECTIVE category (DB2 default + HideByDefault + user layout overrides)
---matches.  Pass the result directly to candidateFilters.includeSpellIDs in
---AddAuraGroup.
---
---includeLinked expands each entry to its full identity set — overrideSpellID
---and linkedSpellIDs[*] — because "what's shown" is a set match, not a
---base-spellID match (see patterns-cooldownviewer.md "spellID is not unique"):
---Blizzard's item frames resolve overrides for icon/tooltip and match live
---auras via linkedSpellIDs, so aura-driven consumers (TrackedBuff/TrackedBar
---containers) MUST pass true or they under-match (e.g. DK Outbreak 77575
---whose displayed aura is linked Virulent Plague 191587).  Cooldown-driven
---consumers MUST pass false/nil: linked ids are internal proc auras and would
---fabricate icons keyed to spells with no castable cooldown.
---@param categoryId number  one of private.Enum.CooldownViewerCategoryIDs values (0–3)
---@param includeLinked boolean|nil  also include overrideSpellID + linkedSpellIDs for each tracked entry
---@param wantSelfAura boolean|nil  nil = all entries; true = only selfAura entries (aura on player); false = only target-aura entries
---@return table<number, true>
local function getTrackedSpellMap(categoryId, includeLinked, wantSelfAura)
    local map = {}
    if not ensureResolved() then return map end
    -- CUE's display category: what this tracker draws, CUE moves/hides included.
    for id, category in pairs(resolvedDisplayCategory) do
        if category == categoryId and resolvedDrawn[id]
            and (wantSelfAura == nil or resolvedSelfAura[id] == wantSelfAura) then
            -- The synthetic key for an item-backed entry is offered ONLY to
            -- cooldown-driven consumers.  Aura-driven ones (includeLinked) would
            -- put it in an AuraContainer candidate filter, where it can never
            -- match anything and would still cost a pooled button and — under
            -- the slots engine — a permanently empty visible cell.  They get the
            -- entry's real value from the linked expansion below instead: an
            -- EquipSlotTracked trinket carries its buff auras in linkedSpellIDs.
            local key
            if includeLinked then
                key = resolvedSpellID[id]
            else
                key = resolvedKey[id]
            end
            if key then map[key] = true end
            -- Expand to override/linked ids ONLY for an entry that has no base
            -- spell of its own.  An ordinary entry is one key -- its base -- and
            -- consumers widen the MATCH through GetAuraIdentitySet at the
            -- candidate filter, which is where the widening belongs: a filter
            -- matches a set, a display row is one thing.
            --
            -- Adding the siblings as map keys instead made every entry with an
            -- override or a linked aura render N times: N always-show cells under
            -- slots (one filled, the rest permanently empty), and under per-spell
            -- groups N FILLED icons, because each of those groups widens to the
            -- same identity set and so matches the same live aura.  Live
            -- 2026-09-09; the addon had been absorbing the shape rather than
            -- fixing it -- BuildSpellOrderRank's identity hop exists to make the
            -- duplicates "land adjacent", and the since-retired buildAuraUnitWidgets
            -- collapsed them by GetIdentityOwner so the panel did not list one spell twice.
            --
            -- Item-backed entries (trinkets, potions) keep the expansion and MUST:
            -- `info.spellID` is nil for them, so resolvedIdentity/IdentityOwner
            -- skip them entirely (there is no key to file them under) and their
            -- buff auras reach an aura tracker only as these real spellIDs.
            -- Nothing can collapse them, and nothing needs to.
            if includeLinked and not key then
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(id)
                if info then
                    if info.overrideSpellID then
                        map[info.overrideSpellID] = true
                    end
                    local linked = info.linkedSpellIDs
                    if linked then
                        for i = 1, #linked do
                            map[linked[i]] = true
                        end
                    end
                end
            end
        end
    end
    return map
end

---How to draw an item-backed CDM entry — a potion spell category or a trinket
---equip slot — or nil for an ordinary spell, which is how callers branch.
---
---A pure PEEK: it never triggers the lazy build.  Its callers are per-button
---refresh paths that run only after the owning pass has already resolved the
---model, and an accessor that can construct it from an arbitrary caller is
---exactly the init-order hazard patterns.md warns about.
---@param key number  a key handed out by getTrackedSpellMap
---@return table|nil source  { spellCategoryID?, equipSlot?, icon? }
local function getIconSource(key)
    return resolvedSource and resolvedSource[key] or nil
end

---The tracker key, effective category, and row spell id for one cooldownID,
---for CDMAlerts to map Blizzard's alert config (keyed by cooldownID) onto our
---tracker keys. `spellID` is the same value `getTrackedSpellMap`'s
---`includeLinked` branch keys the aura trackers by (`resolvedSpellID[id]`,
---:492-496 above) — nil for a 12.1 item-backed entry, which has no spellID and
---so cannot appear in an aura tracker's map.
---
---A pure PEEK, like `getIconSource`: it never triggers the lazy build. Its
---caller only ever asks after `getTrackedCooldownIDs` has already resolved the
---model for the same category, so forcing a build here would just be the
---init-order hazard patterns.md warns about, for no benefit.
---@param cooldownID number
---@return number|nil key, number|nil categoryId, number|nil spellID, boolean|nil known, boolean|nil drawn   -- nil while the model is unresolved; `drawn` is resolvedDrawn (spell-rank families)
local function getResolvedEntry(cooldownID)
    if not resolvedKey then return nil end          -- PEEK, never triggers the lazy build
    -- Blizzard's category, NOT CUE's display one: alert routing must judge the
    -- category Blizzard's own viewer shows (resolvedDisplayCategory's declaration).
    return resolvedKey[cooldownID], resolvedCategory[cooldownID], resolvedSpellID[cooldownID],
        resolvedKnown[cooldownID], resolvedDrawn[cooldownID]
end

---CUE's display category for one cooldownID — Blizzard's effective category
---with `cdm_category_overrides` laid over it.  A pure PEEK like
---`getResolvedEntry`: nil while the model is unresolved, never builds it.
---@param cooldownID number
---@return number|nil categoryId
local function getDisplayCategory(cooldownID)
    if not resolvedDisplayCategory then return nil end  -- PEEK, never triggers the lazy build
    return resolvedDisplayCategory[cooldownID]
end

---The DB2 default category for one cooldownID after the HideByDefault flag and
---before any layout or CUE override — what `cdm_category_overrides` legality
---is judged against.  A pure PEEK like `getResolvedEntry`.
---@param cooldownID number
---@return number|nil categoryId
local function getDefaultCategory(cooldownID)
    if not resolvedDefaultCategory then return nil end  -- PEEK, never triggers the lazy build
    return resolvedDefaultCategory[cooldownID]
end

---The category one override layer's bucket map gives a cooldownID on its own
---— what the overlay would take from that map — or nil when it gives none.
---TrackingModel asks it of the all-specs layer to decide whether a spec-layer
---write is needed.  A pure PEEK like `getResolvedEntry`.
---@param cooldownID number
---@param map table|nil  one bucket map of one layer
---@return number|nil categoryId
local function getLayerCategory(cooldownID, map)
    if not resolvedKey then return nil end  -- PEEK, never triggers the lazy build
    local key = resolvedKey[cooldownID]
    if not key or resolvedSource[key] then return nil end
    return layerValue(map, key, resolvedOverride[key], resolvedDefaultCategory[cooldownID])
end

---Resolved cooldownIDs for one category, unordered.
---
---The Options spell pickers used to enumerate `viewer:GetChildren()` to answer
---this, which left three panels empty whenever `needsViewerChildren()` turned
---the CVar off — the state a stock profile is now in for most classes.  The
---resolved model answers the same question (DB2 defaults + HideByDefault + the
---current spec's layout-blob overrides) off APIs the CVar does not gate.
---
---Returns cooldownIDs rather than spellIDs because the callers disagree on
---which id they want: two key by the base `spellID`, the Additional Frame
---picker by `overrideSpellID or spellID`.  One `GetCooldownViewerCooldownInfo`
---per entry at panel-build time settles it at the call site.
---
---`includeItemBacked` (default false) widens the id-presence test from
---`resolvedSpellID[id]` to `resolvedSpellID[id] or resolvedKey[id]`, so an
---item-backed entry (nil `resolvedSpellID`, `.context/api.md` "spellID is
---nil for item entries") is admitted by its synthetic `resolvedKey` (`-id`)
---instead of being dropped.
---
---This only ever matters for an item-backed entry the PLAYER HAS MOVED into
---one of the four classic categories (0-3) via Blizzard's own CDM settings
---drag-and-drop: `resolvedCategory[id]` above is NOT frozen at the raw DB2
---value (`info.category`) an item-backed entry defaults into
---(SpecAgnosticEssential/Tracked, EquipSlotEssential/Tracked — categories
---5/6/7/8) — it is overwritten below by `getLayoutCategoryOverrides()`'s
---per-cooldownID category from the player's layout blob, which is exactly
---how Blizzard persists such a move.  `CooldownViewerSettings.lua`'s
---`legalOriginalSourceCategoryToTargetCategory` table explicitly allows
---EquipSlotEssential/SpecAgnosticEssential -> Essential/Utility and
---EquipSlotTracked/SpecAgnosticTracked -> TrackedBuff/TrackedBar, so this is
---a real, player-reachable arrangement, not corrupted data.  For an
---item-backed entry left in its default category, no TRACKER reaches this
---flag: `category == categoryId` above excludes it first, because none of them
---asks `getTrackedCooldownIDs` for categories 5-8.
---
---`CDMAlerts.lua` does, and is the one caller for which the non-transferred
---case matters. Its `MODEL_CATEGORY_IDS` covers 5-8 so an alert configured on a
---trinket the player never dragged anywhere is still in the model — Blizzard's
---own alert clock never runs for such an entry (no viewer renders those
---categories), while CUE draws the trinket regardless through
---`Components/TrinketTracker.lua`. Note that list is deliberately NOT
---`CDMAlerts.ALERT_CATEGORY_IDS`, which stays 0-3 because it also feeds
---`Util.GetViewerFrame`.
---
---`useBlizzardCategory` (default false) picks which of the two effective
---categories the enumeration filters on (resolvedDisplayCategory's
---declaration).  The default is CUE's display category, so the Tracking tab lists
---what CUE's trackers draw.  CDMAlerts passes true and walks Blizzard's
---`resolvedCategory` instead: alert replay must follow what Blizzard's own
---viewer shows, so a CUE-only move or hide must never add or drop an entry
---from its model.  An entry BLIZZARD hides (-1/-2) is outside CDMAlerts' walk
---either way: its MODEL_CATEGORY_IDS holds no negative category.
---@param categoryId number  a private.Enum.CooldownViewerCategoryIDs value (0–3), or an item category (5–8) from CDMAlerts
---@param includeItemBacked boolean|nil  also admit item-backed entries, keyed by resolvedKey instead of resolvedSpellID; default false. Only ever matters for one the player moved into this categoryId via CDM category-transfer — see above.
---@param useBlizzardCategory boolean|nil  filter on Blizzard's effective category (resolvedCategory) instead of CUE's display category; default false. CDMAlerts only.
---@param includeUnknown boolean|nil  also admit entries the character does not have (`isKnown` false: another spec's spell, an untaken talent, every entry on WoW Forever); default false. The Tracking tab's "Show unlearned" only — nothing that draws or alerts may see them.
---@return number[] cooldownIDs
local function getTrackedCooldownIDs(categoryId, includeItemBacked, useBlizzardCategory, includeUnknown)
    local ids = {}
    if not ensureResolved() then return ids end
    local categories = useBlizzardCategory and resolvedCategory or resolvedDisplayCategory
    -- Blizzard's walk judges known as Blizzard does; the display walk judges it
    -- as CUE draws it (resolvedDrawn: spell-rank families).
    local known = useBlizzardCategory and resolvedKnown or resolvedDrawn
    for id, category in pairs(categories) do
        if category == categoryId and (includeUnknown or known[id])
            and (resolvedSpellID[id] or (includeItemBacked and resolvedKey[id])) then
            ids[#ids + 1] = id
        end
    end
    return ids
end

---Full aura identity set for one tracked spell: the base spellID plus its CDM
---overrideSpellID and linkedSpellIDs.  "What's shown" is a set match, not a
---base-spellID match (patterns-cooldownviewer.md "spellID is not unique"), so an
---AuraContainer candidate filter built from the base ID alone under-matches
---exactly where Blizzard's own item frames would have matched.
---
---Returns nil when the base spell IS the whole identity — a custom spell with no
---CDM entry, or a CDM entry with no override/linked ids — so callers can keep
---their single-ID filter and allocate nothing.  A sibling entry's set is its
---links only, which for the common one-link sibling is a set of one equal to the
---key: not nil, but the same filter either way.
---@param spellID number  the tracker's map key (a CDM base spellID, or a sibling
---  entry's own linked aura)
---@return table<number, true>|nil
local function getAuraIdentitySet(spellID)
    if not ensureResolved() then return nil end
    return resolvedIdentity[spellID]
end

---The base spellID of the CDM entry an id belongs to, for ANY member of that
---entry's identity set (base, `overrideSpellID`, `linkedSpellIDs[*]`).
---
---This is the direction `GetAuraIdentitySet` cannot go.  The aura-driven consumers
---pass `includeLinked`, so a BuffTracker/BuffTrackerBars cell can be keyed by a
---linked aura id — and anything the user configured against the base spell (an
---`icon_overrides` entry; the panel only ever offers `overrideSpellID or spellID`)
---is invisible from there without this map.  Live symptom: an icon override on a
---tracked buff did nothing, because the cell rendering it was keyed by the linked
---aura rather than the base spell (2026-08-17).
---
---Returns nil for a spell that is its own whole identity, or a custom spell with no
---CDM entry — callers treat that as "the id IS the base".
---@param spellID number
---@return number|nil
local function getIdentityOwner(spellID)
    if not ensureResolved() then return nil end
    return resolvedIdentityOwner[spellID]
end

---The `overrideSpellID` of the entry whose BASE spell is `spellID`, or nil.
---
---`Util.ResolveByBaseOrOverride` is the only intended consumer: base and
---override are two names for one cooldownID, so a config entry saved under
---either must be found from the other.  Nothing wider belongs in that lookup —
---see the `resolvedOverride` declaration.
---Has the resolved-category model been built yet?
---
---`Util.ResolveByBaseOrOverride` checks this so an identity walk never *forces*
---the build.  Components enable on PLAYER_LOGIN while `Initialize()` waits for
---LOADING_SCREEN_DISABLED, so a routing query in that window would otherwise
---construct the model against a client that has no CDM data yet.
---@return boolean
local function isResolved()
    return resolvedIdentityOwner ~= nil
end

---Is `spellID` some entry's own row key (see resolvedEntryKeys)?  A peek:
---false while the model is unresolved, never a forced build.
---@param spellID number
---@return boolean
local function isEntryKey(spellID)
    return resolvedEntryKeys ~= nil and resolvedEntryKeys[spellID] == true
end

---The spec layer key the current model was built with: the one its category
---overlay read, and so the icon order's too (Util.GetTrackerOrder).  A cached
---read, cheap enough for a layout pass; nil with no spec system.  While the
---model is unresolved (invalidated on a spec change, not yet rebuilt) it is the
---live key, which the TrackingModel's writers use, so a read in that window
---never picks the previous spec's list.
---@return string|nil
local function getResolvedSpecKey()
    return resolvedSpecKey or getSpecLayerKey()
end

---The build the current model came from, or nil while there is none.  A peek.
---@return number|nil
local function getModelStamp()
    return resolvedIdentityOwner and modelStamp
end

---Is this key a COOLDOWN entry the current character actually has?
---
---An O(1) membership test over the CooldownEssential + CooldownUtility
---categories and HiddenActive (a cooldown entry the player hid in Blizzard's
---Cooldown Manager: a spells frame may still draw it — the Tracking tab moves
---one there), filtered by `isKnown` — the same class/spec gate Blizzard's own
---display path applies.  It exists because `assigned_spells` is PROFILE data:
---a profile outlives a character and a spec change, so it accumulates entries
---for classes and specs the player is not currently on.  The pre-migration
---layout path collected live viewer children and so never had to ask.
---
---A pure PEEK, like `getIconSource`: it consults `isResolved()` and never
---`ensureResolved()`.  Its caller is a per-Refresh path reachable from
---component enable on PLAYER_LOGIN, while `Initialize()` waits for
---LOADING_SCREEN_DISABLED — forcing the build there would cache an empty model
---for the whole session (patterns.md, "Lazy caches vs init order").
---
---Keyed by `resolvedKey`, NOT `resolvedSpellID`: the 12.1 item-backed entries
---(potions, trinkets) carry a nil spellID and live under a synthetic negative
---key, so filtering on the spellID map would drop every one of them.
---
---Each entry's `overrideSpellID` is admitted alongside its base key.  The
---retired Options pickers saved `overrideSpellID or spellID` (that is the id Blizzard's
---own item frame displays, so it is the id the user picked) while `resolvedKey`
---holds the plain base — a base-only set would therefore MISS on every
---overridden spell and drop a spell the character does have.  This is the same
---base↔override equivalence `Util.ResolveByBaseOrOverride` exists for, applied
---once at build time rather than per lookup so the caller stays O(1).
---
---Every raw `linkedSpellIDs` member is admitted too, unlike `resolvedOverride`'s
---own per-spell config/routing lookups (see its declaration): that routing case
---stays base/override-only because walking linked ids THERE would let one
---talent-swap variant's config silently capture its sibling's (DK Outbreak's
---Virulent vs Dread Plague, both `spellID` 77575) — an ambiguous base-keyed
---lookup with two owners.  This is a plain "does the character have this"
---set-membership test, not a routing lookup, and the linked id is unambiguous:
---it only ever reaches `assigned_spells` because the retired Options collision
---picker exposed it as its own dropdown entry for the user to explicitly pick.  Omitting it here left that
---already-unambiguous pick permanently untracked even once its cooldownID went
---`isKnown = true`.
---@param key number  an assigned_spells key (base or override spellID, or the synthetic negative key)
---@return boolean|nil tracked  nil when the resolved model does not exist yet
local function isCooldownSpellTracked(key)
    if not isResolved() then return nil end
    if not cooldownTrackedKeys then
        cooldownTrackedKeys = {}
        local ids = private.Enum.CooldownViewerCategoryIDs
        local hiddenActive = Enum.CooldownViewerCategory.HiddenActive or -1
        -- Blizzard's category, NOT CUE's display one: AF membership must not
        -- change when a CUE-only move or hide happens.  A forced entry is the
        -- user's own "draw this", so a frame holding it draws it too.
        for id, category in pairs(resolvedCategory) do
            if (resolvedKnown[id] or resolvedForced[id]) and (category == ids.CooldownEssential
                or category == ids.CooldownUtility or category == hiddenActive) then
                local k = resolvedKey[id]
                if k then
                    cooldownTrackedKeys[k] = true
                    local override = resolvedOverride[k]
                    if override then cooldownTrackedKeys[override] = true end
                    local linked = resolvedLinked[k]
                    if linked then
                        for linkedID in pairs(linked) do
                            cooldownTrackedKeys[linkedID] = true
                        end
                    end
                end
            end
        end
        -- A spell-rank family's representative is tracked while any rank is:
        -- Blizzard knows only the highest, and a frame holding the family
        -- holds it under the representative (linkedOwner in
        -- AdditionalFrameManager).  Membership, not placement: whole or split.
        for key, family in pairs(resolvedFamily.cooldown) do
            if cooldownTrackedKeys[key] then cooldownTrackedKeys[family.rep] = true end
        end
    end
    return cooldownTrackedKeys[key] == true
end

---The spell a whole COOLDOWN rank family's representative is drawn as: its
---highest learned rank ("Highest", applyRankFamilies), or nil for any other
---key.  A peek: nil while the model is unresolved.
---@param key number
---@return number|nil
local function getRankedSpell(key)
    if not resolvedFamily then return nil end
    local family = resolvedFamily.cooldown[key]
    if family and family.whole and family.rep == key then return family.highest end
    return nil
end

---The representative of the WHOLE rank family `spellID` is a member of, in
---`bucket`; nil when it is in none or the family is split.  An Additional
---Frame naming any rank of a whole family holds the family under this key.
---@param spellID number
---@param bucket "cooldown"|"aura"
---@return number|nil
local function getFamilyRep(spellID, bucket)
    if not resolvedFamily then return nil end
    local family = resolvedFamily[bucket][spellID]
    return family and family.whole and family.rep or nil
end

---The rank family a key belongs to in `bucket`, for the Tracking model:
---`{ rep, bucket, whole, highest, members }` (members: `{ id, key, spellID,
---rank, learned }`, lowest rank first), or nil.  A peek.
---@param key number
---@param bucket "cooldown"|"aura"
---@return table|nil
local function getRankFamily(key, bucket)
    if not resolvedFamily or not bucket then return nil end
    return resolvedFamily[bucket][key]
end

---@param spellID number  a BASE spellID (pass GetIdentityOwner's result)
---@return number|nil
local function getOverrideSpellID(spellID)
    if not ensureResolved() then return nil end
    return resolvedOverride[spellID]
end

---The LINKED aura ids of one tracked spell — no base spell, no override.
---
---This is the icon-swap slots' candidate filter, and it must NOT be the full
---identity set: Blizzard swaps the icon exactly when
---`FindLinkedSpellForCurrentAuras` returns a *linked* spell
---(`CooldownViewerItemData.lua:12`), so a slot filtered on the base or override id
---as well would reveal the swapped icon while only the base aura is up.
---
---Returns nil when the entry has no linked ids — the swap has nothing to show, so
---the caller allocates no slot for it.
---@param spellID number  the tracker's map key (CDM base spellID)
---@return table<number, true>|nil
local function getLinkedIdSet(spellID)
    if not ensureResolved() then return nil end
    return resolvedLinked[spellID]
end

---A static stand-in for the aura an entry displays: `linkedSpellIDs[1]`.  Read
---by the aura trackers' `displaySpellFor`; IconTracker's swap slots bind
---`SetIcon` instead and draw the link that matched.
---
---Blizzard walks `linkedSpellIDs` in order and takes the first entry with a live
---aura, so for the single-link entries (which is nearly all of them — talent-swap
---variants are separate cooldownIDs each carrying one link, see
---patterns-cooldownviewer.md) this is the same choice.  For a multi-link entry it
---is the first link rather than the live one.
---@param spellID number
---@return number|nil
local function getSwapIconSpell(spellID)
    if not ensureResolved() then return nil end
    return resolvedSwapIcon[spellID]
end

---Build a component's merged spell maps: CDM category spells (minus spells
---routed to an Additional Frame, which owns them) plus the component's custom
---spells, split by the CDM entry's selfAura flag — selfMap = auras that land on
---the player, targetMap = auras that land on the player's target (DoTs, ally
---buffs like Prescience).  Custom spells carry no self/target knowledge, so they
---go into BOTH maps — each aura group's filter string decides where the aura can
---actually match.  Shared by all four tracker components.
---The CDM contribution is gated on the cdm_auto_fetch profile toggle; the
---manual (CustomSpells) contribution ALWAYS applies regardless of the toggle.
---@param categoryId number  one of private.Enum.CooldownViewerCategoryIDs values
---@param routeKey string  AdditionalFrameManager routing domain ("Essential"|"Utility"|"BuffIcon"|"BuffBar")
---@param componentName string  component name for CustomSpells.GetSpellMapFor
---@param includeLinked boolean|nil  expand CDM entries to override/linked ids — pass true from aura-driven consumers only (see getTrackedSpellMap)
---@return table<number, true> selfMap, table<number, true> targetMap
local function buildComponentSpellMaps(categoryId, routeKey, componentName, includeLinked)
    local selfMap, targetMap = {}, {}
    if private.profile.cdm_auto_fetch then
        for spellID in pairs(getTrackedSpellMap(categoryId, includeLinked, true)) do
            if not private.AdditionalFrameManager.IsSpellRouted(spellID, routeKey) then
                selfMap[spellID] = true
            end
        end
        for spellID in pairs(getTrackedSpellMap(categoryId, includeLinked, false)) do
            if not private.AdditionalFrameManager.IsSpellRouted(spellID, routeKey) then
                targetMap[spellID] = true
            end
        end
    end
    -- Custom entries go into BOTH maps on purpose: they carry no unit of their
    -- own, and the aura trackers hand the merged map to every container anyway,
    -- letting each container's filter string decide what it admits (the same
    -- "feed both, let the filters discriminate" rule api.md records for the CDM).
    -- A custom spell therefore shows on whichever unit and polarity actually has
    -- it. There is still no focus container, so nothing renders a focus-only
    -- aura -- a third container, or per-group SetUnit once Blizzard ships it.
    --
    -- A custom id that is a different MEMBER of an entry already tracked here --
    -- the aura id of a cast-keyed entry, or its override -- is skipped: that
    -- entry's group filters on the whole identity set and already matches the
    -- aura, so a second key would draw it twice.
    local customMap = private.CustomSpells.GetSpellMapFor(componentName)
    for spellID in pairs(customMap) do
        local owner = getIdentityOwner(spellID)
        if not (owner and (selfMap[owner] or targetMap[owner])) then
            selfMap[spellID] = true
            targetMap[spellID] = true
        end
    end
    return selfMap, targetMap
end

-- CDM keep-alive bridge -- REMOVED ------------------------------------------
--
-- Nothing in the addon reads a CooldownViewer child any more.  The bridge
-- existed because 12.1 made aura data unreadable as Lua values
-- (.context/patterns-secrets.md "12.1 Aura Lockdown") while one field on the
-- suppressed children survived it -- `child.auraInstanceID`, compared against
-- nil for truthiness only.  `rebuildAuraState` walked all four viewers once per
-- rendered frame and `getAuraState(spellID)` answered off that map.
--
-- Its consumers went one at a time and the last two went together:
--
--   suppress_buff_icon_swap  -> GetLinkedIdSet on an engine-shown swap slot,
--                               its icon bound with SetIcon
--   active_glow, pandemic_glow -> regions in the aura button's own subtree
--   SecondaryResources (K5/K6) -> gave the Lua value up rather than re-source it
--   hide_active_swipe OFF    -> the aura takeover is an engine-shown slot
--                               button over the icon now, so the icon's own
--                               swipe never has to yield and nothing asks
--                               whether the aura is up
--   icon_visibility_mode 2/3 -> dropped the "buffing ~= ready" term outright
--                               (Core/IconTracker.lua), the deliberate trade
--                               that closed this file's last CVar dependency
--
-- So `needsViewerChildren()` counts no child reader and `Util.GetViewerChildren`
-- has no caller; the CVar goes UP only for `cdm_target_sounds`, which wants
-- Blizzard's alerts rather than a child.  Restoring any consumer means
-- restoring all of this -- read Core/CDMDataSource.md "CVar ownership" first.

---True when the CDM viewers are actually delivering data right now — i.e. the
---CVar this module asserts is genuinely on, not merely intended to be.
---
---The distinction is load-bearing.  `ensureEnabled` cannot write the CVar in
---combat, so between an external CVar-off mid-pull and the next OnLeaveCombat
---the viewers are dark while the addon still intends CDM to be on.  The
---predecessor flag (`private.cdmEnabled`) was assigned `true` as the first
---statement of `ensureEnabled`, ahead of both the CVar read and the combat
---branch, so it read `true` in exactly that window — which is why every gate
---built on it was blind, and why removing them looked safe.
---
---Every consumer this was built for is gone (see "CDM keep-alive bridge --
---REMOVED" above), so it no longer gates a viewer-child read.  Its two surviving
---call sites are in `Core/Anchoring.lua`, which asks the plainer question the
---name still describes: is Blizzard's CDM on right now?
---@return boolean
local function isDataAvailable()
    return C_CVar.GetCVar("cooldownViewerEnabled") == "1"
end

---Did the player agree to turn Blizzard's Cooldown Manager off?
---
---**Character-scoped and persisted**, alongside `cdm_never_ask` and
---`cdm_no_suppress`.  It used to be a session local, on the reasoning that a
---CVar written to "0" stays "0" by itself so the answer needed no storage.  That
---covers the CVar half and nothing else: `suppressing` is `needsViewerChildren()
---or isHidden()`, and `needsViewerChildren()` was false for every profile, so every session
---after the one the player answered in ran with suppression OFF.  The moment
---anything put the CVar back — another addon, Blizzard's own settings, a CVar
---reset — the viewers came back at full alpha with nothing left to stop them,
---which is what `CDM_SUPPRESS_VIEWERS_TOGGLE` promises to prevent ("keep it
---hidden even if something turns it back on").  A toggle that persists
---cannot be gated on a flag that does not.
---
---Drives TWO things, and it needs both because neither covers the other:
---
---  * the "0" CVar write, taken **once** (`offWritePending`), and
---  * viewer suppression, for as long as the answer holds.
---
---The second is what makes the answer survive someone else.  Another addon may
---enable the CDM for its own purposes at any time; re-writing "0" at it on every
---CVAR_UPDATE is a write war, so the CVar is conceded and the viewers are made
---transparent instead — the player asked for the icons off their screen, not for
---a particular CVar value.  Persisting the answer is what lets us concede the
---CVar for good rather than only until the next reload.
---
---Reads through `private.charDB`, which Init.lua sets before the first
---`ensureEnabled()`; the nil-tolerant read matches `suppressionAllowed`.
---@return boolean
local function isHidden()
    local cdb = private.charDB
    return (cdb and cdb.cdm_hidden) == true
end

---Are the CDM viewers ours to hide right now?  `needsViewerChildren() or isHidden()`,
---written through `setSuppressing` by `ensureEnabled` and `writeCVarAfterCombat`
---each time either re-derives the predicate, read live by the two hooks below and
---by `syncViewerAlpha`.
---
---**This, not `isHidden()` alone, is the suppression gate.** When the predicate is
---true we force the CVar to "1" and force `ShouldBeShown` past the player's own
---"Hidden"/"In Combat" setting, so the viewer is only on screen because we put
---it there — leaving it visible draws Blizzard's icons over ours. When it is
---false we need nothing from the viewer and it goes back to being the player's:
---no override, no clamp, no alpha write.
---
---Gating this on `isHidden()` ALONE was the shipped bug: on any profile that
---genuinely consumed aura state the CVar went to "1", so no prompt could fire
---and nothing was left to hide the viewers — they rendered at full alpha over
---the addon, read as "the CDM re-enabled itself".
---
---It is `needsViewerChildren() or isHidden()`, though, because `isHidden()` has a second
---job the CVar cannot do.  We write "0" exactly ONCE (see `ensureEnabled`); if
---something turns the CDM back on afterwards — another addon that wants it for
---its own purposes, the settings panel, a console command — we do not write
---again, because two addons correcting each other on CVAR_UPDATE is an
---unbounded ping-pong.  Suppression is how the player's answer survives that:
---the CVar goes where the other addon wants it, and Blizzard's icons still stay
---off the screen the player asked to clear.
local suppressing = false

---Suppress one viewer: transparent and click-through, while `suppressing`.  No
---component gate — if we ever force the CVar on again, a disabled tracker must
---NOT hand its viewer back at full alpha, because whichever consumer forced it
---is still reading and Blizzard's icons would be drawn over ours.
---SetAlpha and EnableMouse are unprotected — safe in combat.  Both writes are
---guarded so a re-sync is a no-op.
---@param viewerKey string
---Viewers already carrying the suppression hooks.  Keyed by frame in an addon
---side table — never a field on the viewer, since writing a Lua property onto a
---CooldownViewer frame taints it (patterns.md "Taint Prevention").  Weak keys so
---a viewer going away cannot pin it.
local suppressionInstalled = setmetatable({}, { __mode = "k" })

---Viewers we have actually written alpha 0 onto, so the restore branch only ever
---undoes our own write — `suppressionInstalled` is set by `initialize()` for
---every viewer, suppressing or not, and would make us SetAlpha(1) on a viewer
---Blizzard put at 0.
local alphaSuppressed = setmetatable({}, { __mode = "k" })

---Install the one-time suppression hooks on a viewer.  Idempotent.
---
---Must be reachable from every suppression pass, not just `initialize()`: that
---runs once at LOADING_SCREEN_DISABLED and skips any viewer whose frame does not
---exist yet (`if viewer then`), and nothing repaired it afterwards — so such a
---viewer went the WHOLE session with no alpha clamp and no visibleSetting
---override.  Blizzard's `UpdateSystemSettingOpacity` re-applies the viewer's own
---EditMode opacity on every `UpdateSystem` pass, so without the clamp its icons
---come back over ours and only the occasional syncViewerSuppression pushes them
---down again — a show/hide cycle rather than a one-off.
---@param viewer frame
local function installViewerSuppression(viewer)
    if suppressionInstalled[viewer] then return end
    suppressionInstalled[viewer] = true
    -- Post-hook: the re-entrant SetAlpha(0) hits the alpha == 0 guard and stops.
    -- Reads `suppressing` live rather than closing over its value: hooksecurefunc
    -- has no uninstall, so a clamp that ignored the flag would go on fighting a
    -- player whose profile stopped needing the viewer at all.
    hooksecurefunc(viewer, "SetAlpha", function(self, alpha)
        if suppressing and alpha ~= 0 then self:SetAlpha(0) end
    end)
end

local function syncViewerAlpha(viewerKey)
    local viewer = private.Util.GetViewerFrame(viewerKey)
    if not viewer then return end
    if suppressing then
        -- Self-healing: a viewer that appeared after initialize() gets its hooks here.
        installViewerSuppression(viewer)
        alphaSuppressed[viewer] = true
        if viewer:GetAlpha() ~= 0 then
            viewer:SetAlpha(0)
        end
        if viewer:IsMouseEnabled() then
            viewer:EnableMouse(false)
        end
    elseif alphaSuppressed[viewer] then
        alphaSuppressed[viewer] = nil
        -- We took it away earlier this session; hand it back. Only alpha 0 is
        -- ours to undo — Blizzard's UpdateSystemSettingOpacity re-applies the
        -- viewer's own EditMode opacity on its next pass, and the clamp above no
        -- longer fights it.
        if viewer:GetAlpha() == 0 then
            viewer:SetAlpha(1)
        end
        if not viewer:IsMouseEnabled() then
            viewer:EnableMouse(true)
        end
    end
end

---Sync suppression state for all four CDM viewers: alpha and mouse only.
---Shown state is Blizzard's alone — the addon never drives it.  Do NOT write
---`cooldownViewerEnabled` here either: this function runs from Init.lua's
---CVAR_UPDATE handler, and a CVar write on that path would re-enter it without
---end.
---Set by the popup's "No" button (and by Escape) — a decline for THIS session
---only, so the question can come back on a later login without nagging now.
local declinedThisSession = false

---Ask whether to turn Blizzard's Cooldown Manager off.  Called from exactly one
---place — `ensureEnabled`, at the point it has decided the CVar *could* go to
---"0" — so "nothing needs the CDM any more" is the caller's precondition and is
---not re-derived here.  The popup body lives at the bottom of the file, where
---the three functions its handlers call are already declared (Lua 5.1 upvalues).
---
---Three answers, and only one of them is written to disk:
---
---| answer | effect |
---|---|---|
---| Yes | `charDB.cdm_hidden`, character-scoped and permanent; plus the one "0" write |
---| No | `declinedThisSession`; asked again next login |
---| No, don't ask again | `charDB.cdm_never_ask`, character-scoped and permanent |
---
---Still checks the CVar itself: with the CDM already off there is nothing to
---turn off and the question would be nonsense.  That single condition is what
---stops a "Yes" from becoming a nag — the CVar we wrote to "0" is still "0"
---next login, so `ensureEnabled` finds it already correct and never gets here.
---
---Not in combat: a modal mid-pull is worse than waiting.  Nothing re-arms it
---on leaving combat, and nothing needs to — `ensureEnabled` runs again on the
---next profile change, component toggle or Options edit, and on the next login
---regardless.
local function maybeAskToHide()
    local cdb = private.charDB
    if isHidden() or declinedThisSession then return end
    if not cdb or cdb.cdm_never_ask then return end
    if C_CVar.GetCVar("cooldownViewerEnabled") ~= "1" then return end
    if InCombatLockdown() then return end
    StaticPopup_Show("CLASSUIENHANCED_CDM_HIDE")
end

local function syncViewerSuppression()
    for _, viewerKey in ipairs(VIEWER_KEYS_LIST) do
        syncViewerAlpha(viewerKey)
    end
end

---Set while a corrective CVar write is waiting for combat to end, so repeated
---ensureEnabled calls during one pull register a single OnLeaveCombat callback.
local pendingCVarWrite = false

---Permission for the ONE "0" CVar write, granted by the popup's Yes and spent by
---the write.  Turning the CDM off is an action taken once; see `ensureEnabled`
---for why re-asserting it is a write war rather than a correction.
---
---Starts false every session, so an answer RESTORED from `charDB.cdm_hidden`
---never writes: that write happened in the session the player answered in, and
---firing another one at whatever turned the CDM back on is exactly the war this
---prevents.  Suppression alone honours a restored answer.
local offWritePending = false

---`ensureEnabled`'s previous verdict, so it can see the one transition that hands
---the saved answer back: `cdm_target_sounds` switched off, or a profile without it
---loaded, after it had the CDM on.  Session-local: both happen inside a session.
---@type string?
local lastWant

---Is the addon allowed to suppress Blizzard's viewers at all?
---
---The escape hatch for a case we cannot see from in here: another addon that
---wants the CooldownViewer *visible* for its own purposes, on a character where
---the player also asked us to turn it off.  Suppression is deliberately blunt —
---it overrides the player's own Hidden/In-Combat setting and forces alpha 0 —
---so there has to be a way to say "leave Blizzard's frames alone entirely".
---
---Character-scoped, alongside `cdm_never_ask`, and stored as the OPT-OUT so the
---absent key means the default (suppress).  Character rather than profile
---because it describes this character's addon environment, not a layout: it must
---survive a profile switch and must not travel in an exported profile, where it
---would carry one player's addon set onto another's.
---@return boolean
local function suppressionAllowed()
    local cdb = private.charDB
    return not (cdb and cdb.cdm_no_suppress)
end

---Flip the suppression gate, re-settling the viewers only on an actual change.
---@param on boolean
local function setSuppressing(on)
    on = on and suppressionAllowed()
    if suppressing == on then return end
    suppressing = on
    syncViewerSuppression()
end

-- `SR_CDM_KEYS_BY_CLASS` lived here: the SecondaryResources settings whose proc
-- detection read CDM viewer children, grouped by class because most of them
-- default to `true` and an ungrouped check would have reported "needs CDM" for
-- every player alive.  The table is empty history now — every one of those
-- readouts is engine-driven, in this order:
--
--   Divine Purpose, Lock and Load          -> auraTap.ensureGlow
--   Ignore Pain readout                    -> ipState.ensureTap
--   Ignore Pain pandemic cue               -> native AddPandemicRegion
--   Sweeping Strikes / Teachings / CdG     -> auraTap.ensurePips
--   Devourer reap forecast MoC cap  (K6)   -> dropped for the Reap override
--   Evoker Essence Burst tint       (K5)   -> ebTap, one container per slot
--
-- K5 and K6 were the two the migration could not re-source, because their
-- consumers wanted a plain Lua VALUE and a tap renders a secret rather than
-- handing one back.  Both were closed by giving the value up rather than
-- recovering it: the reap cap lost natural-expiry accuracy, and Essence Burst
-- lost the charging-bar shift.  Each of those costs is documented at its site.
--
-- What this leaves: SecondaryResources can no longer pin the CVar at all, so
-- the aura-consuming icon-tracker settings below — on the two primaries and on
-- every `spells` Additional Frame alike — are the only remaining reason it is
-- ever on.

---Does anything need Blizzard's viewers running?
---
---**Two things do, and both for ALERTS, not data.**
---
---The `cdm_target_sounds` option: an alert on the player's debuff on the target
---has one source only. Blizzard's viewer plays it live off UNIT_AURA, filtered to
---the player's own auras (`CheckAuraAddedAlertTriggers`, CooldownViewer.lua:1862),
---while the addon side has only `AddAuraSound`, which fires for every source.
---
---And an alert CUE cannot replay at all (`CDMAlerts.NeedsBlizzardViewer`):
---text-to-speech on a buff applied/removed, pandemic, charge gained. No option:
---configuring one in Blizzard's settings is the request.
---
---Either way the CDM goes on, suppression keeps it invisible, and CDMAlerts'
---`blizzardOwnsAlerts` sees the viewers shown and stops replaying their sounds.
---
---No data consumer is left: every one is enumerated in "CDM keep-alive bridge --
---REMOVED" above, and the last (`icon_visibility_mode` 2/3's "buffing ~= ready"
---term) was dropped deliberately to close the dependency.  This stays the single
---place to re-open the question: anything that needs a viewer again adds its test
---here, and the CVar plumbing, the suppression path and
---`tests/cvarkeepalive_check.lua` follow it unchanged.
---
---Scope note, and it is narrower than it looks: the CVar gates ONLY
---`CooldownViewerMixin:ShouldBeShown` (`CooldownViewer.lua:1893`). The data
---APIs — `GetCooldownViewerCategorySet` / `GetCooldownViewerCooldownInfo`, and
---the layout blob the category overlay decodes — are not gated by it, so
---`cdm_auto_fetch` spell maps and the Tracking tab keep working
---with the CVar off. What stops is
---`RefreshData`, i.e. the CHILDREN. Only consumers that read a child are at
---stake here, which is why an addon that draws every icon itself can leave the
---CVar alone entirely.
---
---The `not private.profile` fail-safe stays: it costs one comparison and it is
---the guarantee that a half-built or corrupt profile can never be the reason
---Blizzard's CDM gets turned off under someone.
---@return boolean
local function needsViewerChildren()
    local p = private.profile
    if not p or not p.components then return true end
    return p.cdm_target_sounds == true or private.CDMAlerts.NeedsBlizzardViewer()
end

---One-shot OnLeaveCombat writer for the deferred case.
---The trailing OnCDMSpellsChanged is the recovery half, not decoration: while
---the CVar was off, `isDataAvailable` disarmed the aura-slot engine, and
---nothing else re-arms it — the trackers listen to combat transitions and this
---callback only, and their own OnLeaveCombat handler may well have already run
---by the time this one does.  Without the nudge the aura spirals stay off until
---some unrelated event happens to force a layout pass.  The viewers genuinely
---did repopulate, so invalidating the resolved-category cache alongside is
---honest rather than defensive.  Not coalesced: this runs at most once per
---pull (the callback unregisters itself), so there is no burst to batch.
local function writeCVarAfterCombat()
    private.Callback.Unregister("OnLeaveCombat", writeCVarAfterCombat)
    pendingCVarWrite = false
    local want = needsViewerChildren() and "1" or "0"
    setSuppressing(want == "1" or isHidden())
    -- Same gate as ensureEnabled: the "0" write needs a permission granted this
    -- session and spent once.  Re-derived here rather than replayed, because the
    -- predicate and the answer can both have moved during the pull.
    if want == "0" and not offWritePending then want = nil end
    if want and C_CVar.GetCVar("cooldownViewerEnabled") ~= want then
        if want == "0" then offWritePending = false end
        C_CVar.SetCVar("cooldownViewerEnabled", want)
    end
    invalidateResolvedCategories()
    private.Callback.Trigger("OnCDMSpellsChanged")
end

---Bring the `cooldownViewerEnabled` CVar in line with what the profile
---actually needs (`needsViewerChildren`), in either direction.
---
---The addon OWNS this CVar rather than reading it as a preference: while it is
---off `ShouldBeShown` hard-fails, so a feature that reads viewer children
---cannot be made to work by any amount of addon-side effort. The flip side is
---that keeping the CDM alive when nothing reads it costs Blizzard's own
---per-frame refresh for nothing, so when the profile needs no children we turn
---it OFF — the resource-saving half of the original design.
---
---Guard-written (SetCVar always fires CVAR_UPDATE even when unchanged —
---patterns.md); Blizzard's own CVar callback runs UpdateShownState on each
---viewer, so no reload is needed.
---
---**Never writes in combat, in either direction.** Flipping it makes Blizzard
---show/hide the protected viewer frames and re-drives every tracker layout —
---not something to trigger mid-pull. A correction needed during combat is
---deferred to a one-shot OnLeaveCombat, which re-evaluates the predicate at
---that point rather than replaying a stale decision.
---
---Called from Init.lua's OnEnable before components initialize, from the
---CVAR_UPDATE handler so an external change is reconciled, and from every
---setter that can change the predicate's answer.
local function ensureEnabled()
    -- No Cooldown Manager (MoP Classic): no viewers to suppress or feed, and the
    -- CVar exists there but drives nothing.
    if not private.compat.HasCooldownManager() then return end
    local want = needsViewerChildren() and "1" or "0"
    -- `cdm_target_sounds` had the CDM on and no longer does.  A player who chose
    -- Turn It Off gets that answer back as one "0" write, the prompt's own.  Not a
    -- write war: `want` depends on the profile alone, so someone else's
    -- CVAR_UPDATE can never produce this transition.  No answer on record falls
    -- through to the prompt below.
    if want == "0" and lastWant == "1" and isHidden() then offWritePending = true end
    lastWant = want
    -- Settled here rather than left to Init.lua's CVAR_UPDATE handler, because
    -- the branch that decides NOT to write ("0" without consent) fires no
    -- CVAR_UPDATE at all — and that is precisely the transition that has to hand
    -- the viewers back.
    setSuppressing(want == "1" or isHidden())
    -- Turning it ON is never "disabling their CDM" — it only ever makes more of
    -- Blizzard's UI visible, and our own features cannot work without it.
    --
    -- Turning it OFF is the half the player has to ask for, and THIS is the
    -- moment to ask: `want == "0"` is precisely "we could disable the CDM,
    -- because nothing in this profile needs it any more".  Every caller that can
    -- move the predicate reaches here (login, profile change, component
    -- enable/disable, the Options setters), so the question surfaces whenever
    -- the answer becomes available and never when we still need the CDM on.
    if want == "0" and not isHidden() then
        maybeAskToHide()
        return
    end
    -- ONE "0" write, ever.  Honouring "turn it off" is an action taken once, not
    -- a claim to keep re-asserting: another addon may enable the CDM for its own
    -- purposes, and re-correcting it on every CVAR_UPDATE is a write war neither
    -- side can win.  The answer is not lost — `setSuppressing` above keeps the
    -- viewers transparent for as long as the answer holds, whatever the CVar says.
    if want == "0" and not offWritePending then return end
    if C_CVar.GetCVar("cooldownViewerEnabled") == want then return end
    if InCombatLockdown() then
        if not pendingCVarWrite then
            pendingCVarWrite = true
            private.Callback.Register("OnLeaveCombat", writeCVarAfterCombat)
        end
        return
    end
    if want == "0" then offWritePending = false end
    C_CVar.SetCVar("cooldownViewerEnabled", want)
end

---The disable prompt (`maybeAskToHide` shows it).  Defined here rather than beside
---its caller so `ensureEnabled` is a real upvalue by the time OnAccept closes
---over it (patterns.md "Lua 5.1 Upvalue Safety").
---
---Button-to-handler mapping is Blizzard's, verified in
---`Blizzard_StaticPopup/StaticPopup.lua`: button1 → `OnAccept`, button2 →
---`OnCancel`, button3 → `OnAlt` (`:716`), and Escape under `hideOnEscape` calls
---`OnCancel` (`:820`).  Escape therefore lands on the session-only decline,
---which is the harmless answer — the permanent one is behind an explicit third
---button and cannot be reached by accident.
StaticPopupDialogs["CLASSUIENHANCED_CDM_HIDE"] = {
    text = private.L["CDM_HIDE_PROMPT"],
    button1 = private.L["CDM_HIDE_CONFIRM"],
    button2 = private.L["CDM_HIDE_KEEP"],
    button3 = private.L["CDM_HIDE_NEVER"],
    OnAccept = function()
        -- Both first: ensureEnabled reads them for the two halves of the answer —
        -- the one-shot "0" write, and the suppression that keeps honouring it if
        -- something turns the CDM back on later, this session or any other.
        private.charDB.cdm_hidden = true
        offWritePending = true
        ensureEnabled()
    end,
    OnCancel = function()
        declinedThisSession = true
    end,
    OnAlt = function()
        declinedThisSession = true
        private.charDB.cdm_never_ask = true
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

---Initialize CDMDataSource.
---Installs the suppression hooks on all four CDM viewers and settles them
---against `suppressing`, then registers the game events that change the CDM
---data to fire the OnCDMSpellsChanged callback (coalesced to one frame per
---burst).
---Suppression takes no component gate beyond that flag, so there is nothing to
---re-sync on component enable/disable — only the profile path re-settles,
---because a profile switch can rewrite the CDM layout blob.
---Call once from Init.lua after all CDM-wrapped components have been migrated.
local function initialize()
    if initialized then return end
    initialized = true
    -- Install the alpha clamp (which stops
    -- EditModeCooldownViewerSystemMixin:UpdateSystemSettingOpacity from
    -- un-suppressing the viewer on every UpdateSystem pass), then settle
    -- alpha/mouse.  syncViewerAlpha installs the same hook for any viewer that
    -- does not exist yet at this point, so this loop is the fast path rather
    -- than the only chance.
    for _, viewerKey in ipairs(VIEWER_KEYS_LIST) do
        local viewer = private.Util.GetViewerFrame(viewerKey)
        if viewer then
            installViewerSuppression(viewer)
        end
    end
    syncViewerSuppression()

    private.Callback.Register("OnProfileChanged", function()
        -- CooldownLayoutSync may have rewritten the layout blob at the C level,
        -- which no event reports — drop the resolved caches.
        invalidateResolvedCategories()
        syncViewerSuppression()
    end)

    -- fireSpellsChanged (file scope, above) is the coalesced notifier the
    -- registrations below share with NotifyUserCategoryChanged.
    -- Re-evaluate the CVar whenever the predicate's inputs can have moved.
    -- Enable/disable and profile switches change which components count;
    -- the per-setting Options setters call EnsureEnabled directly.  The write
    -- is guard-protected, so a redundant call costs one GetCVar.
    private.Callback.Register("OnProfileChanged", ensureEnabled)
    private.Callback.Register("OnComponentEnable", ensureEnabled)
    private.Callback.Register("OnComponentDisable", ensureEnabled)

    -- OnHide is the point where the settings UI flushes pending edits into the
    -- C-level layout blob (CheckSaveCurrentLayout → WriteData) — the blob our
    -- category overlay decodes.  Edits made while the window is open are not in
    -- the blob yet, so this is the one settings-panel signal worth reading.
    EventRegistry:RegisterCallback("CooldownViewerSettings.OnHide", fireSpellsChanged, private.CDMDataSource)

    -- The game events that change the CDM data, registered directly.  This is
    -- what Blizzard's CooldownViewerSettingsDataProviderMixin listens to
    -- (CooldownViewerSettingsDataProvider.lua:26-43), in its two groups:
    --
    --   * UpdateLayoutForSpecChange: TRAIT_CONFIG_UPDATED,
    --     ACTIVE_PLAYER_SPECIALIZATION_CHANGED, ACTIVE_COMBAT_CONFIG_CHANGED
    --     (loadout switching, the most common respec action),
    --     ACTIVE_TALENT_GROUP_CHANGED.
    --   * RefreshFromExternalUpdate: SPELLS_CHANGED, PLAYER_PVP_TALENT_UPDATE,
    --     COOLDOWN_VIEWER_TABLE_HOTFIXED, PLAYER_EQUIPMENT_CHANGED (equip-slot
    --     entries, i.e. trinkets).
    --
    -- Both groups also reach Blizzard's CooldownViewerSettings.OnDataChanged
    -- (via NotifyListeners / SetHasPendingChanges), which CUE used to listen to
    -- instead.  That relay is conditional -- NotifyListeners runs only `if
    -- layoutManager`, and a spec switch notifies only when the resolved layout
    -- ID actually changes (CooldownViewerSettingsLayoutManager.lua:200-212) --
    -- and it also fires on every uncommitted edit in the settings window, which
    -- the blob does not hold yet.  So the source events are registered here
    -- and the relay is not.
    --
    -- SPELLS_CHANGED matters most on a levelling character: on a classic-content
    -- client every trainer visit and every new RANK of a known spell moves
    -- isKnown with no talent or spec change anywhere near it.
    --
    -- fireSpellsChanged coalesces through a pendingFire flag and C_Timer.After(0),
    -- so a SPELLS_CHANGED storm (zone change, login) or a gear-set swap costs one
    -- rebuild, not one per event.  None carries a unit argument, so plain
    -- RegisterEvent is correct: ACTIVE_PLAYER_SPECIALIZATION_CHANGED, not
    -- PLAYER_SPECIALIZATION_CHANGED, which carries a unitTarget and would need
    -- RegisterUnitEvent(..., "player").
    local spellsChangedEventFrame = CreateFrame("Frame")
    spellsChangedEventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    spellsChangedEventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    spellsChangedEventFrame:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    spellsChangedEventFrame:RegisterEvent("SPELLS_CHANGED")
    -- SPELL_DATA_LOAD_RESULT (registered below): a spell a build asked data for
    -- (applyRankFamilies' uncached), whose rank may read now.  Every other
    -- addon's loads arrive here too; only ours count.
    spellsChangedEventFrame:SetScript("OnEvent", function(_, event, spellID)
        if event == "SPELL_DATA_LOAD_RESULT" then
            if not pendingSpellData[spellID] then return end
            pendingSpellData[spellID] = false
        end
        fireSpellsChanged()
    end)
    -- Checked for existence, not assumed: an unknown event throws in
    -- RegisterEvent, which would abort this function and everything after it
    -- in Init.lua's LOADING_SCREEN_DISABLED callback.  PLAYER_PVP_TALENT_UPDATE
    -- is not proven on WoW Forever; ACTIVE_COMBAT_CONFIG_CHANGED does not exist
    -- on MoP Classic.  An existence check, not a client check
    -- (Blizzard_Console.lua does the same for its optional events).
    for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_PVP_TALENT_UPDATE", "COOLDOWN_VIEWER_TABLE_HOTFIXED",
        "SPELL_DATA_LOAD_RESULT", "ACTIVE_COMBAT_CONFIG_CHANGED" }) do
        if C_EventUtils.IsEventValid(event) then
            spellsChangedEventFrame:RegisterEvent(event)
        end
    end
end

---Build the model now, for a caller that has to show it and that nothing else
---may build for: the Tracking tab on a profile with no CDM tracker or
---Additional Frame enabled, where OnCDMSpellsChanged brings no rebuild.  Before
---initialize() (LOADING_SCREEN_DISABLED) it declines instead of building early
---(patterns.md "Lazy caches vs init order").
---@return boolean ready
local function resolveNow()
    return initialized and ensureResolved()
end

---@type cdmdatasource
private.CDMDataSource = {
    EnsureEnabled = ensureEnabled,
    Initialize = initialize,
    ResolveNow = resolveNow,
    GetSpellOrderRanks = getSpellOrderRanks,
    GetTrackedCooldownIDs = getTrackedCooldownIDs,
    GetIconSource = getIconSource,
    GetResolvedEntry = getResolvedEntry,
    GetDisplayCategory = getDisplayCategory,
    GetDefaultCategory = getDefaultCategory,
    GetLayerCategory = getLayerCategory,
    GetSpecLayerKey = getSpecLayerKey,
    GetResolvedSpecKey = getResolvedSpecKey,
    GetCategoryBucket = categoryBucket,
    IsLegalCategoryMove = isLegalCategoryMove,
    NotifyUserCategoryChanged = notifyUserCategoryChanged,
    BuildComponentSpellMaps = buildComponentSpellMaps,
    IsDataAvailable = isDataAvailable,
    GetAuraIdentitySet = getAuraIdentitySet,
    GetIdentityOwner = getIdentityOwner,
    GetOverrideSpellID = getOverrideSpellID,
    IsResolved = isResolved,
    IsEntryKey = isEntryKey,
    GetModelStamp = getModelStamp,
    IsCooldownSpellTracked = isCooldownSpellTracked,
    GetRankedSpell = getRankedSpell,
    GetFamilyRep = getFamilyRep,
    GetRankFamily = getRankFamily,
    GetLinkedIdSet = getLinkedIdSet,
    GetSwapIconSpell = getSwapIconSpell,
    SyncViewerSuppression = syncViewerSuppression,
    IsSuppressing = function() return suppressing end,
}

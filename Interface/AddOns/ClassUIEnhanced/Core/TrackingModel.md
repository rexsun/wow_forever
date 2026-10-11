# TrackingModel.lua

A pure data layer over everything CUE can track: the four CDM trackers, every Additional
Frame, the player's spellbook, and profile keys no live entry answers to any more. It
builds **sections of rows** and exposes the **actions** that move, reorder, add and remove
them. It creates no frames. The Options "Tracking" tab (`Core/UI/TrackingTab.lua`) is its
caller; `tests/trackingmodel_check.lua` drives the real file under a stub environment.

Loads after `CDMDataSource.lua` / `CDMAlerts.lua` and before `ComponentManager.lua`, the
components and `AdditionalFrameManager.lua`. Every `private.X` is therefore read at **call
time**, never captured at file load.

## Contract: never force the resolve early

`BuildSections()` checks `CDMDataSource.IsResolved()` first and returns `{}, false` while
the model does not exist. It never calls an `ensureResolved`-backed accessor on an
unresolved model — a caller in the `PLAYER_LOGIN` → `LOADING_SCREEN_DISABLED` window would
otherwise cache an empty model for the whole session (`.context/patterns.md`, "Lazy caches
vs init order"). The caller re-asks on `OnCDMSpellsChanged`.

Every action that writes `cdm_category_overrides` (either layer — "Override layers" below) ends in
`CDMDataSource.NotifyUserCategoryChanged()`, which invalidates the model **synchronously**.
Whether a `BuildSections()` in the same frame is ready then depends on whether something
rebuilt the model meanwhile — the component refresh the action runs usually does — so a
caller re-reads a frame later, and on the `OnCDMSpellsChanged` the notify queues.

## Sections

In order:

| id | kind | bucket | holds |
|---|---|---|---|
| `CooldownTracker` | `cdm` | cooldown | CDM entries whose display category is Essential, plus its custom spells |
| `UtilitiesTracker` | `cdm` | cooldown | … Utility |
| `BuffTracker` | `cdm` | aura | … TrackedBuff |
| `BuffTrackerBars` | `cdm` | aura | … TrackedBar |
| `af:<id>` | `af` | cooldown (`spells`) / aura (`buffs`, `bar`) | its `assigned_spells`, then its custom spells; frames in `AdditionalFrameManager.GetAllFrameIds()` order |
| `pool` | `pool` | — | hidden CDM entries, unfolded spellbook spells, icon overrides no row answers to |

A CDM tracker section is ordered the way the tracker draws: `Util.BuildSpellOrderRank`
(the stored order this spec reads, `Util.GetTrackerOrder` — "Icon order layers" below — then
Blizzard's rank), custom spells unranked last. An AF section follows
`assigned_spells` index, custom spells after. Every section then closes with its **stale**
rows, by key. A switched-off frame keeps its section and rows, flagged `disabled`, so its
list stays editable. It routes nothing (`AdditionalFrameManager.rebuildSpellRouting`), so
its spells still draw in their trackers, and the model says so: a CDM entry it holds stays a
row of the tracker drawing it — with that tracker's order, colour and pandemic controls, and
its per-spell settings there not stale — while the frame lists a **copy** of the row at its
`listIndex` (Remove and Move on the copy act on the frame's entry). Enabled frames claim
first, whatever the frame order, so an entry an enabled frame also holds is that frame's
row and the disabled frame's entry is an `assigned` duplicate.

## Row shape

`{ key, kind, bucket, sectionId, known, learned, name, rank, texture, inSpellbook, hasIconOverride }`,
with `family` on a CDM row of a spell-rank family, `forced` on a CDM row (its
`cdm_category_overrides.active[bucket][key]`, drawn or not) and `ranks` on a custom row. Per kind:

| kind | from | extra fields |
|---|---|---|
| `cdm` | a CDM entry (`GetTrackedCooldownIDs(category, true, nil, includeUnknown)` over 0–3 and the two hidden categories), the character's own or not | `cooldownID`; `listIndex` when an AF routes it |
| `item` | an item-backed CDM entry (`GetIconSource` non-nil), or an AF addon-source entry (`{id, "Trinket"\|"Consumable"\|"Racial"}`) | `cooldownID` or `source`, `listIndex` |
| `assigned` | an AF `assigned_spells` entry the frame draws that is no fresh row of the frame's own bucket: a second entry for a row an earlier entry claimed, a CDM entry of the **other** bucket, or on an aura frame any id no CDM row answers to | `listIndex`; `duplicateOf` (the claimed row's key) for the first case |
| `spellbook` | a castable spell with no learned CDM cooldown row | — |
| `custom` | a `custom_spells` entry of a tracker or frame | `listIndex`, `duplicateOf`, `restrictToPlayer` (the entry's `restrict_to_player`; a legacy nil reads as true), `thisSpec` (aura sections: the entry shows on the current spec), `byName` / `byNameCount` / `byNamePending` (aura sections: the entry's `by_name`, how many ids carry the name once `aura_name_cache` holds it, and whether `SpellNameScan` is still collecting it) |
| `stale` | a key only a profile list names | `refs = { {sectionId, list} … }` (an icon override's ref has no `sectionId`); `listIndex` when a frame's `assigned_spells` names it; `untracked` on a section row whose key is no row at all on this spec (another spec's spell) |

`known` is what the host **draws**. For a CDM row that is `GetResolvedEntry`'s `drawn`
(`Core/CDMDataSource.md`, "Known and drawn"): `isKnown`, an aura entry whose spell the
character has, and inside a spell-rank family whatever its placement draws (only a whole
family's representative). On a spells frame it is `IsCooldownSpellTracked`. An aura frame draws every id it
is given, so its rows are always known. A custom entry's is the `CustomSpells` filter. The
duplicate check for custom entries reads only known rows, since an unknown CDM row draws
nothing and the custom entry beside it is the one drawing.

`learned` is whether the character **has** the spell: `known`, or the key is in the
spellbook (every `Spell` item the rule-2 walk reads, folded or not), or, for a ranked row
only, a spellbook spell with the same name and rank. The two differ on WoW Forever's
cooldown entries. Its CDM has one entry per rank, whose condition names that rank and the
next. By the look of the DB2 (build `1.60.1.70009`), only the highest rank the character
has reads `isKnown`, so every lower cooldown rank is learned but not known; aura ranks are
known through the exception above. A condition can also simply be wrong: Rejuvenation rank
1's names spell `744`, not `774`. Unranked rows never match by name, since a name alone is
not one spell on retail. The Tracking tab filters and badges on `learned`; everything that
concerns drawing (the tab's Up/Down gate, the all-specs rule for unlearned rows) stays on
`known`. `learned` is computed last, from the final `known`: a frame's rows get theirs
after they are built.

`name` is nil where the UI owns the wording (consumable categories, empty trinket slots).
`rank` is the spell's subtext (`C_Spell.GetSpellSubtext`, "Rank 3") where it carries a digit —
spell ranks exist on WoW Forever; retail subtexts ("Racial") carry none, so nothing branches
on the client. It reads `""` until the spell's data has loaded; the Tracking tab rebuilds on
`SPELL_TEXT_UPDATE`.
An AF Consumable row's `texture` is its category's first family icon
(`ConsumableTracker.GetFamilies`), as the retired Additional Frames list showed it.
`texture` is the `icon_overrides` texture when one resolves (`Util.ResolveIconOverride`).

### Construction rules

1. **CDM rows** are deduped by **(key, bucket)**, not key: Sweeping Strikes `260708` is an
   Essential entry *and* a BuffIcon entry and must be two rows. The bucket is the
   **default** category's (`GetCategoryBucket(GetDefaultCategory(id))`); an item-backed
   entry has none and is filed by its display category. Several cooldownIDs on one key in
   one bucket (the Roll the Bones merge shape) are one row. An AF entry claims the row
   whose key it names through `Util.ResolveByBaseOrOverride` — the base↔override
   equivalence the pickers need, since they save `overrideSpellID or spellID`. A `spells`
   frame's claimed row is `known = false` when `IsCooldownSpellTracked` says no: that frame
   draws nothing Blizzard does not file under Essential, Utility or HiddenActive.
   **Entries the character does not have** (`isKnown` false: another spec's spell, an untaken
   talent, every entry on WoW Forever, where the Cooldown Manager has no backend) are rows
   too, `known = false`, so the Tracking tab's **Show unlearned** lists them in their
   category's section and a move can place one ahead of time. Two passes, known entries
   first: a key's row is its known entry whenever it has one, and only a known cooldown row
   takes a spellbook spell in (rule 2). A tracker never draws such a row, so it is no Reorder
   position (`sectionOrderKeys` does not hold its key).
   **`cdm_auto_fetch` off**: every CDM row goes to the **pool** unless a frame claims it.
   That is `BuildComponentSpellMaps`' own gate — with it off a tracker draws only its custom
   spells — so a tracker section lists exactly what the tracker draws, and its Up/Down never
   offers a key `sectionOrderKeys` cannot find. The rows stay in the pool rather than
   vanishing because an Additional Frame still draws them (frames ignore the toggle), so
   Move to a frame keeps working.
   **Every AF entry is listed in its frame's section**, since the Tracking tab is the only
   editor of `assigned_spells` (the Additional Frames tab's own list is gone). An entry that
   claims no row becomes, in `assigned_spells` order:
   - an `assigned` row when the frame draws it: its row was claimed by an earlier entry, of
     this frame or another one of the same bucket; its key is a CDM row of the *other* bucket
     only (the retired picker offered every category to every frame type, and a `buffs` frame
     does draw a cooldown entry's linked auras through `buildAFAuraSpellMap`); or the frame
     is a `buffs`/`bar` frame, which draws any id it is given, CDM entry or not. Its key is
     the stored id. `known` is `IsCooldownSpellTracked` on a `spells` frame (the frame's own
     gate), true otherwise.
   - a **stale** row of the frame (rule 4) on a `spells` frame, which draws nothing that is
     no CDM cooldown entry (`buildAFIconSpellMap`). It is judged against the frame's own rows
     only: a spellbook or custom row of the same key elsewhere does not list *this* entry.
   Before this, both shapes could be listed nowhere and so could not be removed.
   **Talent-swap variants are separate rows already.** `CDMDataSource.findSiblingEntryKeys`
   keys each entry of a split shape (entries on one base with differing link sets — DK
   Outbreak's Virulent/Dread, Protection Paladin's four) by its own `linked[1]`, so Move writes
   the variant's own key. An existing entry saved as one of the retired picker's other
   per-linked-id choices claims its owner's row through `ResolveByBaseOrOverride`, and the
   runtime agrees: `AdditionalFrameManager` routes the linked id's owner away from its
   tracker and draws the entry under that owner (`linkedOwner`), so the frame alone draws it.
2. **Spellbook rows**: every `C_SpellBook` skill line that is not off-spec or hidden, every
   `Spell` item that is not passive or off-spec. If its base (`actionID`) or active
   (`spellID`) id resolves to a learned **cooldown** row key, that row gets
   `inSpellbook = true` and no new row is made. Otherwise the row is keyed by the
   **active** id — the one actually cast, and the only one a custom entry can match on a
   spec that overrides the base (`.context/api.md` "Overridden spells: query the ACTIVE
   id"). A spellbook spell is a cast, so an **aura** row of the same id never folds it:
   that row tracks the buff, and folding it hid the spell from every cooldown section
   (Mark of the Wild and Thorns on WoW Forever, whose only CDM entries are buffs;
   2026-09-25). An aura row is never marked `inSpellbook`.
   **A ranked spell's unlearned ranks** (2b) are spellbook rows too, borrowed from the CDM:
   - **Why:** the spellbook lists only the ranks the character has, and no API lists the
     others. The CDM, with one entry per rank on WoW Forever, is the one place they are.
   - **What:** a ranked spellbook spell's name also yields every CDM row of that name with a
     rank, that is not in the spellbook and has no cooldown row. Each becomes an unlearned
     spellbook row (`known = false`), in the pool and in `spellbookByKey`, so a cooldown
     custom entry folds it like any other.
   - **Why a buff's id works:** on Forever a buff's cast is its own aura's id (Mark of the
     Wild rank 1 is `1126` for both, DB2). Where a cooldown row exists, that row is the cast
     already. Spells with no CDM entry at all (Wrath, Healing Touch) still list only the
     learned ranks.
3. **Custom rows**: one per `custom_spells` entry of each tracker and frame. `known` is
   `CustomSpells.GetSpellMapFor` membership: its `restrict_to_player` filter on a cooldown
   host, its spec scope on an aura host — so a custom aura row of an enabled host is known,
   and so learned, exactly on the specs in its `specs` (`thisSpec`,
   `CustomSpells.IsOnCurrentSpec`). An entry
   whose id, or `GetIdentityOwner`, is already a row key in the same section is kept and
   marked `duplicateOf` — the trackers skip it (one aura, one key; `Core/README.md` "Custom
   spells"). A custom entry of a **cooldown** section whose id is also a pool spellbook row
   folds that row away; a custom aura does not (rule 2), so moving a spellbook row onto an
   aura section leaves it listed.
4. **Stale rows**: keys in the icon order a tracker has on this spec (its own list, else the
   all-specs `priority_order`; another spec's own list is never read), a `spells` frame's plain
   `assigned_spells` entry (rule 1), or `icon_overrides`, that resolve to no live row.
   Surfaced only — never migrated or dropped
   (`.context/memory/project_no_spell_id_automigration.md`). A custom entry is never stale:
   it is always a row of its own.
   A stale row lives in the **section that saved it**, one row per (section, key), after
   every row that section draws — so its Remove clears only that section's leftovers. An
   icon override belongs to no section (`icon_overrides` is profile-wide): it is always a
   **pool** row of its own, never a ref of a section's stale row, so removing another
   spec's or class's leftovers from a tracker never deletes an icon another character on a
   shared profile still draws.
   The per-spell settings `pandemic_glow_excludes`, `active_swipe_excludes` (together
   `EXCLUDE_LISTS`), `spell_colors`, `spell_borders` and `missing_glow` (together `COLOR_MAPS`) are checked **per
   section**: an entry is stale when no row *of the tracker or frame that saves it*
   resolves to its key, even if the spell is a row somewhere else. Their controls exist only
   on that section's rows, so an entry left behind when the spell moved, was untracked, or
   belongs to another class in a shared profile would otherwise be invisible and
   unclearable — the retired Trackers-tab lists showed every saved entry. With
   `cdm_auto_fetch` off this makes a tracker's excludes/colours for CDM spells stale too,
   which is accurate: that tracker draws none of them.

## Legality — `GetValidTargets(row)`

Never includes the row's own section.

| row | targets |
|---|---|
| `cdm`, cooldown bucket | `CooldownTracker`, `UtilitiesTracker` (each filtered by `CDMDataSource.IsLegalCategoryMove`), every `spells` frame — an entry Blizzard hides included, which a spells frame draws (`IsCooldownSpellTracked` admits HiddenActive) |
| `cdm`, aura bucket | `BuffTracker`, `BuffTrackerBars`, every `buffs`/`bar` frame |
| `cdm`, `cdm_auto_fetch` off | the frames above only: a tracker draws no CDM entry |
| `item`, an Additional Frame addon-source entry (`row.source`) on a `spells` frame | every **other** `spells` frame that does not already hold an entry with this id — `AddAddonSource`'s refusal. A trinket slot is its own id, so a frame may hold both Trinket 1 and Trinket 2; there is no per-slot exclusivity beyond that. Since the entry leaves the one spells frame holding it, one frame per icon still holds. An addon-source entry left on a non-`spells` frame has none (Remove only) |
| `item` (a CDM item-backed entry), `assigned` | none — reorder only; Remove too on a frame (a tracker's item entry cannot be hidden: item categories never move) |
| `spellbook` | every tracker and every frame. On an aura section it becomes a custom **aura** under the cast id: that is often the aura's id too (most self-buffs, every rank of a ranked buff on WoW Forever), and where it is not the entry simply never shows |
| `custom`, cooldown bucket | every section, aura ones included, for the same reason |
| `custom`, aura bucket | every aura section — never a cooldown one |
| `stale` | in a CDM tracker with `untracked` set and `cdm_auto_fetch` on: the other tracker of that tracker's bucket (`CooldownTracker` ↔ `UtilitiesTracker`, `BuffTracker` ↔ `BuffTrackerBars`). Any other stale row: none — Remove only. A leftover of a spell drawn elsewhere on this spec has none, since writing its category would move that live row |

## Actions

Each writes the profile and runs the same refresh the equivalent Options.lua control runs.

| action | writes | refresh |
|---|---|---|
| `Move(cdm → tracker)` | the target category into one override layer (`setCategory`, "Override layers" below); key out of every same-bucket frame's `assigned_spells`; out of the source tracker's icon order (`removeFromMoveSource`, never materialized), into the target's at `index` (`placementOrders`), both in `orderLayerKey`'s layer ("Icon order layers" below) | `NotifyUserCategoryChanged`, `OnSpellAssignmentChanged` per touched frame, `component.Refresh()` |
| `Move(cdm → frame)` | clears the key's override from the all-specs layer and the current spec's (so pulling it back out returns it to Blizzard's category — a frame is every spec's); out of every other same-bucket frame; inserted into the target's `assigned_spells` at `index`; out of both icon orders the source tracker has on this spec, its own and the all-specs one (`removeFromOrders`), not other specs' | `NotifyUserCategoryChanged` if an override went, `OnSpellAssignmentChanged` |
| `Move(custom → any)` | the entry table moves between `custom_spells` lists (keeping `restrict_to_player` and `specs`; a cooldown entry landing on an aura section is stamped like an add); `priority_order` out/in as above — except that a custom entry duplicating a CDM row of its own key leaves that key's place in the source order, since the CDM row stays drawn there | `CustomSpells.Rebuild` + `component.Refresh()` on both hosts |
| `Move(addon-source item → spells frame)` | the `{id, source}` entry table leaves the source frame's `assigned_spells` (validated by `listIndex` + id + source, like `Remove`) and is inserted into the target's at `index` | `OnSpellAssignmentChanged` once per touched frame (source and target), as `Move(cdm → frame)` does |
| `Move(stale → tracker)` | the target's category into the **all-specs** layer, with the key's override cleared from every spec's layer first (a spec's own value would shadow it there). Stored as is, because Blizzard's default category for a key with no entry on this spec cannot be read; the overlay ignores it on a spec where the move is illegal (`layerValue`). The key leaves every icon order the source keeps, every spec's own included, and joins the target's **all-specs** `priority_order`, which the specs without their own order read — never this spec's own list, which holds this spec's keys only. That order is materialized only while it is the one this spec shows; under this spec's own list it is edited where it stands, and never started as a partial list. Its `pandemic_glow_excludes` and `active_swipe_excludes` entries move too (the target's list is created if it has none), as does its `spell_borders` colour unless the target is Buff Bars, which draws no icon border per spell. A Buff Bars `spell_colors` entry stays behind as a stale row, since Buff Tracker keeps no colours | `NotifyUserCategoryChanged`, `component.Refresh()` on both trackers |
| `Move(spellbook → any)` | `AddFromSpellbook` on a cooldown section, the `AddAuraByID` write on an aura section; placed at `index` in a tracker's order | as below |
| `Reorder(section, from, to)` | tracker: its icon order in `orderLayerKey`'s layer; frame: `assigned_spells` (custom rows are not orderable on a frame — they rank after every assigned entry) | `component.Refresh()` / `OnSpellAssignmentChanged` |
| `AddFromSpellbook(id, section)` | `{ spellID, restrict_to_player = true }` appended to the section's `custom_spells` — a frame's too, **not** `assigned_spells`, which a `spells` frame intersects with `IsCooldownSpellTracked` and would silently drop a non-CDM id. Takes **any** id `C_Spell.GetSpellName` resolves, not only a spellbook one: the Tracking tab's typed add box on cooldown sections calls it for item-cast spells (Hearthstone) too | `CustomSpells.Rebuild` + `component.Refresh()` |
| `Copy(row, section)` / `GetCopyTargets(row)` | a `cdm` or `custom` row's key added to a section of the **other** bucket as a custom entry (`addCustom`, the typed add box's write: an aura copy gets this spec's `specs` and `by_name`, a cooldown copy `restrict_to_player` and an exact id). `by_name` is the default because a cooldown's buff is often a different id with the same name; it is left off when another by-name entry of that list already has the name, `SetCustomByName`'s own refusal (`byNameTaken`); the row stays where it is, so one spell is tracked as a cooldown and as an aura (Sacred Shield). **One copy per type**: targets are every tracker and frame of the other bucket, or none once the spell is on any of them — any non-stale row of the key (a CDM entry in both Blizzard categories counts, an earlier copy, a frame's entry), or a by-name aura row with the same name. `GetCopyTargets(row, sections)` then returns `{}, true`; it reads the caller's built sections (the Tracking tab's) or builds its own, and `Copy` re-derives them fresh. | `CustomSpells.Rebuild` + `component.Refresh()` |
| `AddAuraByID(id, section)` | the same, for an aura section; no identity conversion of the typed id. The entry gets `specs = { [current spec] = true }` (`newAuraSpecs`), or none — every spec — with **All specs** ticked or no spec system | same |
| `GetAddonSourceChoices(section)` | nothing — lists what a `spells` frame may take: trinket slots 13/14, every `ConsumableTracker` category (`GetCategoryOrder` / `GetCategoryIDs`), every `RacialTracker.GetResolvedSpellIDs()` racial, each with `name`/`texture` and `ownerAfId` (the spells frame already holding it, target included). Empty for any other section | — |
| `AddAddonSource(id, source, section)` | `{ id, source }` appended to a `spells` frame's `assigned_spells` — the retired Additional Frames picker's write. Refused when the frame already holds an entry with that id, when another spells frame holds that `{id, source}` (the picker greyed those out; relocating one is `Move`), for an unknown source, or for a non-`spells` section | `OnSpellAssignmentChanged` |
| `Remove(row)` | custom: entry out of `custom_spells`; frame row (`cdm`, `item`, `assigned`): the one entry at `listIndex` out of `assigned_spells`, validated by source (an addon-source row names exactly its `{id, source}`) and key (a `cdm` row through `sameEntry`, since it may have claimed an override or linked id); tracker `cdm` row: -1 (cooldown) / -2 (aura) into one override layer (`setCategory`), where `IsLegalCategoryMove` allows it; stale: the key out of every list its refs name — its own section's icon order (the one this spec reads, where the scan found it), `assigned_spells`, `pandemic_glow_excludes`, `active_swipe_excludes`, `spell_colors` or `spell_borders` (exact key, the one the scan found); a pool stale row's only ref is `icon_overrides`, which it clears | the matching refresh above; `component.Refresh()` per section whose exclude/colour went; `icon_overrides` through the chrome bridge |
| `CanRemove(row)` | nothing — whether `Remove(row)` would act. Both run one `planRemove`, which holds every check, so the Tracking tab's Remove button can never be enabled on a row `Remove` refuses | — |
| `SwapRank(current, chosen, index)` | the Tracking tab's rank menu: `Remove(current)` then `Move(chosen, current.sectionId, index)`, in that order so `index` (current's position) then names the row after it and `chosen` lands in current's place; a frame's `cdm` row is also hidden (-1/-2), since leaving a frame alone hands an entry back to its tracker. `current` must be a tracker's `cdm` row, a custom row or a frame's `cdm` row; both halves are checked before either writes (`planSwapRank`). The place is kept among the rows the tracker **draws**: an unknown row has no order position, so a raw index can shift around it | the two writes' own refreshes |
| `CanSwapRank(current, chosen)` | nothing — whether `SwapRank` would act, through the same `planSwapRank` | — |
| `Move` / `Remove` on a whole family's representative | every rank of the family (`familyRows`): each rank's category, in one batch and one `NotifyUserCategoryChanged`; the order holds the representative; a frame's entry naming any rank goes | as their single-row forms |
| `SetFamilyMode(row, section)` | the rank menu's "All ranks" / "Highest": every rank not in this tracker comes here (Not tracked, another tracker, a frame's entry), which makes the family whole; the representative takes `row`'s place in a stored order | `NotifyUserCategoryChanged`, the touched frames, every tracker |
| `SetSingleRank(chosen, section, index)` | the rank menu's single rank: every other rank in this tracker hidden (Not tracked), `chosen` moved here at `index` if elsewhere; one already here takes the representative's place in a stored order | as `Move` / `Remove` |
| `SetCustomRank(row, id)` | a custom cooldown row: `nil` sets `ranks = "highest"`, an id sets `spellID` and drops `ranks`, keeping the entry's place in the tracker's order | `CustomSpells.Rebuild` + `component.Refresh()` |
| `Move(spellbook → cooldown section, index, "highest")` | the new custom entry carries `ranks = "highest"`. An aura section, and the typed add box, write exact ids | as `AddFromSpellbook` |
| `SetRestrictToPlayer(row, bool)` | custom rows only: the entry's `restrict_to_player` (`true`/`false`), validated by `listIndex` + key like `Remove` | `CustomSpells.Rebuild` + `component.Refresh()` |
| `SetCustomSpec(row, bool)` | custom rows of an aura section only, refused without a spec system: on adds the current spec to `specs` (clears `specs` — every spec — with **All specs** ticked); off removes it, first expanding a nil `specs` to the class's specs (`UnitClass` + `GetNumSpecializations`), since nil cannot say "all but one". Validated like `Remove` | same |
| `SetCustomByName(row, bool)` / `CanSetCustomByName(row, bool)` | custom rows of an aura section only: sets or clears the entry's `by_name` (#55, `Core/README.md` "Custom spells"). Turning it on is refused while another `by_name` entry of the same list has the same spell name, since both cells would fill from one aura, and while the spell's name cannot be read. Validated like `Remove`. `Move` to a cooldown section clears `by_name` | `CustomSpells.Rebuild` + `component.Refresh()`, then `CDMAlerts.RebuildRegistrations()` (the row's aura sounds follow its id set) |
| `CanForceActive(row)` / `SetForceActive(row, bool)` | **Force active**: `cdm_category_overrides.active[bucket][key] = true`, or nil to clear, for every spec (no spec layer). Allowed on a `cdm` row — a frame's claimed one too — outside a spell-rank family, that is inactive (`learned and not known`) or already `forced`, so the box can be cleared. A missing `cdm_category_overrides` is created in `overrideMap`'s shape. Reset moves never touches it: it wipes the move maps only. `CDMDataSource.applyForcedActive` does the drawing | `NotifyUserCategoryChanged` |
| `SetIconOverride(row, tex)` | `icon_overrides` under `Util.FindIconOverrideKey(key)` (the entry a reader already sees) or else the row key. Refused for an addon-source row: its key is a slot or a category, not a spell | chrome bridge |
| `ClearIconOverride(row)` | every id `FindIconOverrideKey` resolves, until none does | chrome bridge |
| `SetAllSpecs(bool)` | nothing in the profile — the Tracking tab's "All specs" box, session-only: which layer `setCategory`, icon-order writes and both Resets use | — |
| `HasMoves(bucket)` / `ResetMoves(bucket)` | Reset moves: wipes the bucket map of one layer — the current spec's, or the all-specs one with "All specs" ticked or no spec system. Both trackers of a bucket share it | `NotifyUserCategoryChanged` when something went |
| `HasOrder(section)` / `ResetOrder(section)` | Reset to default order, same layer rule: drops the current spec's own icon order (it counts while it exists, even empty, since it still shadows the all-specs one), so the tracker follows the all-specs order or Blizzard's; with "All specs" ticked or no spec system, empties the all-specs `priority_order`. Other specs' own orders stay | `component.Refresh()` |

**Override layers.** `cdm_category_overrides` has two, read spec first
(`Core/CDMDataSource.md`, "Two effective categories"): the current spec's,
`spec[GetSpecLayerKey()]`, and the all-specs one, the top-level `cooldown` / `aura` maps.
`setCategory` writes the current spec's layer, except that three cases write the all-specs
one: the "All specs" box, a row with `known = false` (another spec's entry, which a move made
for this spec would never show), and a client with no spec system (`GetSpecLayerKey()` nil).
Rules, each pinned by `tests/trackingmodel_check.lua` T30:

- **Store nothing where the layers below already give the category.** Below a spec layer is
  the all-specs layer's value for the entry (`GetLayerCategory`), else Blizzard's; below the
  all-specs layer is Blizzard's. Comparing with Blizzard's alone — the rule before the layers
  — silently undoes a spec move back to Blizzard's category while the all-specs layer holds
  another.
- **An all-specs write clears the current spec's entry**, which would otherwise shadow it
  here. Other specs' entries stay: a spec's own move wins over the all-specs layer by design.
- **A frame move clears both layers the current spec reads**, not other specs'.

**Icon order layers.** A CDM tracker's icon order has the same two layers as its
categories, per tracker: `priority_order_spec[GetSpecLayerKey()]`, the current spec's own
list, and `priority_order`, the all-specs one. A spec with its own list reads only that; a
spec without one reads the all-specs list; with neither, Blizzard's order.
`Util.GetTrackerOrder(settings)` is the one reader, for the trackers
(`BuildSpellOrderRank`) and this model alike. It takes the spec key the CDM model was built with
(`CDMDataSource.GetResolvedSpecKey`), so the order and the category overlay always agree and a
layout pass pays no spec lookup. While the model is unresolved (invalidated on a spec change,
not yet rebuilt) that key is the live one, which the writers here use, so a read in that window
never picks the previous spec's list. Writes land in `orderLayerKey()`'s layer: the current spec's
own list, or the all-specs one with the "All specs" box ticked or no spec system. Unlike
`writeSpecKey`, this is section-wide: an order is one list, so an unlearned row's placement
goes to this spec's list too (T44).

- **A spec's own list holds this spec's keys only.** Materializing into it keeps a key only
  if it is a row on this spec: drawn by the tracker, or a CDM entry of this character's set,
  learned or not (`CDMDataSource.IsEntryKey`). Another spec's key is dropped; that spec has
  its own list or reads the all-specs one. So another spec's leftover rows appear only where
  the all-specs list is read; once a spec arranges its own order, the unmovable rows of other
  specs' entries are gone from it.
- **An all-specs arrangement drops the current spec's own list first** (`Reorder`, a drag
  within a tracker), which would otherwise shadow it here. The displayed order is then the
  all-specs one, so this spec's own arrangement is never folded into it. Other specs keep
  theirs.
- **An all-specs placement keeps it** (a move's target, an add; `placementOrders`): while
  this spec has its own list, the key lands in that list at the drop position and is
  appended to the all-specs list (when that one is non-empty). Dropping the list there
  silently discarded the spec's arrangement for a Move-to (review 2026-09-30; T44o).
- **A move's source only loses the key, and never materializes** (`removeFromMoveSource`):
  from this spec's own list in the spec layer (the all-specs list keeps it — other specs
  still draw it there), from both with "All specs" ticked. Materializing the source forked
  a spec reading the all-specs order off it (review 2026-09-30; T44n). A move into a frame
  still takes the key out of both lists this spec reads.
- **A per-spec write never touches the all-specs list.** With one shared list, a per-spec
  category move took the key out of it and dropped that spell to the end of the tracker on
  every other spec; now a move on one spec leaves the others' orders as they were.
- No migration: an existing `priority_order` simply becomes the all-specs layer. The
  component export segment copies `priority_order_spec` with every other non-layout key.
- Rank families edit the list this spec reads, in place (a rank family is a WoW Forever
  shape, and Forever has no spec system). A custom-rank rename renames the key in every list,
  the all-specs one and each spec's own, since the custom entry is every spec's.

**Order materialization.** Before any icon-order write, the tracker's whole displayed order
is written into the layer being written — the stored order this spec reads (untracked keys
included, except in a spec's own list, above) then the tracked tail in Blizzard's rank — the
same whole-list write the retired Icon Order list made. A partial list would leave everything
it does not mention in Blizzard's order behind it. Stale keys survive it. **A tracker with no
stored order is left without one** unless the move names a drop `index` (`orderForMove`): the
Move-to menu keeps it following Blizzard's order, and a move's source never materializes (above).
"Stored" is what this spec shows: its own list, else the all-specs one. Writing it there would pin Blizzard's current
order into the profile, and reordering in Blizzard's Cooldown Manager would stop reaching
CUE — which the retired UI never did for a frame assignment. `Reorder` and a drag always
materialize: the player placed the row. A drop `index` is a position in the target section's rows; it
lands before the entry shown there — in a tracker's order by key, in a frame's
`assigned_spells` by that row's `listIndex` (a row that claimed its entry through an
override or linked id shows a key that is not the stored id).

**Spell-rank families** (WoW Forever; `Core/CDMDataSource.md` "Spell-rank families").
A CDM row carries `family`, the table `GetRankFamily` returns.
- **Whole family:** the representative's row is the one drawn (`known`), so the Tracking tab
  shows it, and `Move` / `Remove` / `SetFamilyMode` act on every rank.
- **A rank's own write clears its own key only** (`clearOverride`'s `exact`). The identity
  walk `clearCategoryOverride` uses would also reach the representative, through the owner
  map a whole buff family folds into. Each rank is its own CDM entry with its own category
  (T39f).
- **A frame naming any rank of a whole family** claims the representative's row, and the
  other ranks' rows follow it into the frame's section, as the frame draws them all.
  `sameEntry` treats any rank as naming the family, so `Remove` there takes the entry out.
- **The spellbook walk** folds a learned lower rank of a whole cooldown family into the
  representative's row (`GetFamilyRep`). Cooldown families fold nothing into the owner map
  (`Core/CDMDataSource.md`, "Only buff families fold").
- **Known limit:** a per-spell setting saved on a rank other than the representative before
  the family formed (an `icon_overrides` entry resolves through the identity walk, a colour
  or pandemic exclude does not) applies to that rank only.

**Chrome bridge.** `icon_overrides` is a profile-level key, so no tracker's `RESTYLE_KEYS`
sees it (`.context/patterns.md`). The model runs the four calls of Options.lua's file-local
`refreshGlobalChrome` — `fontsDirty` around `RefreshAllComponents`, then `Anchor.Refresh` —
because a bare `RefreshAllComponents` never reaches an aura button.

## Not in this phase

Move-to for a CDM item-backed entry, and converting a typed aura id through `GetAuraIdentitySet`. Assigning a CDM
entry to a section of the other bucket (the retired picker's cross-category offer) is not a
Move target: a CDM cooldown row's aura, if it has one, is a CDM entry of its own, and an aura
section takes any other id through **Add aura by spell ID** or a spellbook row's Move.
Tracking an aura **by name** — one entry for every rank of a buff, as some unit-frame addons
do — is staged as #55, not built.

# CDMDataSource.lua

Blizzard's CooldownViewer (CDM) as a **data source** for the four migrated trackers.
The addon reads its DB2 data and layout blob — none of which the `cooldownViewerEnabled`
CVar gates — and reads no viewer child at all any more, so the viewers are left exactly
as Blizzard and the player configured them.

## Spell resolution

| Call | Returns |
|---|---|
| `GetTrackedCooldownIDs(categoryId, includeItemBacked, useBlizzardCategory, includeUnknown)` | Resolved cooldownIDs whose category is `categoryId` — by default the **display** category (below), with `useBlizzardCategory` **Blizzard's** effective one — and, by default, only entries drawn (the display walk reads `resolvedDrawn`) or known (Blizzard's walk reads `resolvedKnown`): "Known and drawn" below. `Core/TrackingModel.lua` enumerates the display category with `includeUnknown`, so the Tracking tab's **Show unlearned** can list another spec's spells, untaken talents, and every entry on WoW Forever (where none is known); CDMAlerts walks Blizzard's, known only, to build its model. |
| `GetResolvedEntry(cooldownID)` | `key, categoryId, spellID, known` for one cooldownID — tracker key, **Blizzard's** effective category, base spellID (nil for a 12.1 item-backed entry), known (`resolvedKnown`) and drawn (`resolvedDrawn`: "Known and drawn" below). A pure peek — nil while the model is unresolved, never triggers the lazy build, like `GetIconSource`. |
| `GetDisplayCategory(cooldownID)` | CUE's display category: Blizzard's effective category with `cdm_category_overrides`' two layers laid over it. Pure peek. |
| `GetDefaultCategory(cooldownID)` | The DB2 default after `HideByDefault`, before the layout blob and before CUE — what override legality is judged against. Pure peek. |
| `GetLayerCategory(cooldownID, map)` | The category one layer's bucket map gives the entry on its own (the overlay's own lookup and legality), or nil. `TrackingModel` asks it of the all-specs layer before a spec-layer write. Pure peek. |
| `GetSpecLayerKey()` | The current spec's `cdm_category_overrides.spec` key, `"CLASS-N"`; nil on a client with no spec system (below). |
| `GetResolvedSpecKey()` | The key the current model was built with: the one its category overlay read. `Util.GetTrackerOrder` picks a tracker's per-spec icon order by it, so the order and the overlay agree and a layout pass pays no spec lookup (`Core/TrackingModel.md` "Icon order layers"). |
| `GetCategoryBucket(category)` / `IsLegalCategoryMove(default, want)` | The override legality rule, exposed so `Core/TrackingModel.lua` reuses it rather than restating it. |
| `NotifyUserCategoryChanged()` | Call after writing `cdm_category_overrides`: invalidates the model synchronously, then queues the coalesced `OnCDMSpellsChanged`. |
| `GetSpellOrderRanks(category)` | `{[spellID] = rank}` **within one category**, lower first — Blizzard's CDM display order. `nil` while unresolved, and `nil` for a category with no entries (callers treat both the same way). There is deliberately no global view. |
| `ResolveNow()` | Builds the model on demand and returns whether it is ready — but only once `Initialize()` has run (`LOADING_SCREEN_DISABLED`); before that it returns false without building. After it the model always resolves, even to an empty one: a WoW Forever Shaman, Rogue, Hunter or Paladin has no CDM data at all, and `buildResolvedCategories` treats zero entries as "not loaded yet" only before `Initialize()`. For a UI that must show the model and has no other builder: the Tracking tab, on a profile with no CDM tracker or Additional Frame enabled. |
| `GetIconSource(key)` | How to draw an **item-backed** entry (`{ spellCategoryID?, equipSlot?, icon? }`), or nil for an ordinary spell. A pure peek — never triggers the lazy build. |
| `IsCooldownSpellTracked(key)` | Is this key a `CooldownEssential`/`CooldownUtility`/`HiddenActive` entry the character actually has (`isKnown`), or one the user forced active (`resolvedForced`)? `true`/`false`, or **`nil` while the model is unresolved** — a pure peek, like `GetIconSource`. |
| `GetRankedSpell(key)` | The spell a whole cooldown spell-rank family's representative is drawn as: its highest learned rank. `nil` for any other key. A peek. |
| `GetFamilyRep(spellID, bucket)` | The representative of the **whole** family `spellID` is a rank of, in `bucket`; `nil` otherwise. A peek. |
| `GetRankFamily(key, bucket)` | The family a key belongs to, whole or split: `{ rep, bucket, whole, highest, members }`, members lowest rank first. A peek. |
| `BuildComponentSpellMaps(categoryId, routeKey, componentName, includeLinked)` | `selfMap, targetMap` — CDM spells (minus AF-routed; dropped entirely when `cdm_auto_fetch` is off) merged with the component's custom spells, minus any custom id whose identity owner is already a CDM key here (it would draw the same aura twice — `Core/README.md` "Custom spells"). |

Effective category is reconstructed from DB2 defaults (`GetCooldownViewerCategorySet`
returns defaults **only**, never user arrangement) + the `HideByDefault` flag + the
spec's category overrides decoded from the `GetLayoutData()` blob (format in
`.context/patterns-cooldownviewer.md`). So user hides/moves/un-hides are honored and
Blizzard's tainting `DataProvider:GetOrderedCooldownIDsForCategory` is never called.
A `HideByDefault` entry starts in the category `hiddenCategoryFor` gives it, which mirrors
Blizzard's `cooldownCategoryToHiddenCategoryMapping`
(`CooldownViewerSettingsDataProvider.lua:66`):

| DB2 default category | starts in |
|---|---|
| Essential, Utility | `HiddenActive` (-1) |
| TrackedBuff, TrackedBar | `HiddenPassive` (-2) |
| EquipSlot*/SpecAgnostic* (items) | its own category — that container is where Blizzard keeps a hidden item |

The two hidden values are Lua-side (`CooldownViewerSettingsConstants.lua`), not part of the
C enum, so the lookup falls back to the numbers. The old code sent every entry to a flat
`HiddenSpell or -1`; `HiddenSpell` does not exist on 12.1, so hidden auras landed in the
spell pseudo-category and hidden item entries left their own category. `tests/orderbucket_check.lua`
drives the real function. Negative categories never match a tracker query.

### Two effective categories: Blizzard's and CUE's

The build keeps three category tables per cooldownID:

| table | holds | read by |
|---|---|---|
| `resolvedDefaultCategory` | DB2 default + `HideByDefault` (`hiddenCategoryFor`) | override legality (`GetDefaultCategory`) |
| `resolvedCategory` | the above + the layout blob's overrides — **Blizzard's truth** | `getResolvedEntry` and `getTrackedCooldownIDs(…, useBlizzardCategory = true)` (CDMAlerts), `isCooldownSpellTracked` (Additional-Frame membership) |
| `resolvedDisplayCategory` | the above + `profile.cdm_category_overrides` — **what CUE draws** | `getTrackedSpellMap` (every tracker map), `projectOrderRanksByCategory` (order buckets), `getTrackedCooldownIDs` by default (`TrackingModel`) |

`buildDisplayCategories` produces the third as a **new** table; it never writes
`resolvedCategory`. For each entry it looks up the bucket map under `resolvedKey`, then
under the entry's `overrideSpellID` (the base↔override equivalence
`Util.ResolveByBaseOrOverride` applies everywhere else; linked ids are not walked) —
`layerValue`, once per layer, first legal value wins:

1. the current spec's layer, `cdm_category_overrides.spec[GetSpecLayerKey()][bucket]`;
2. the all-specs layer, `cdm_category_overrides[bucket]`.

`GetSpecLayerKey()` is `"CLASS-N"`, or nil where `GetNumSpecializations() <= 1` (no spec
system — the test `PrimaryResources.getRealSpecIndex` uses), which leaves the all-specs
layer alone. It keeps the last key it resolved across a transient nil
`GetSpecialization()`. A spec switch rebuilds the model through
`ACTIVE_PLAYER_SPECIALIZATION_CHANGED`, so the layer read always follows the spec. The
bucket comes from the **default** category:

| default category | bucket | legal values |
|---|---|---|
| Essential, Utility, HiddenActive | `cooldown` | 0, 1, -1 |
| TrackedBuff, TrackedBar, HiddenPassive | `aura` | 2, 3, -2 |
| any item category (EquipSlot*/SpecAgnostic*) | none | never moved |

An illegal value, a non-table sub-map or a non-number value is ignored — the shape is
validated on read, since saved data can be corrupted externally. Item-backed entries are
also skipped explicitly by key (`resolvedSource`). Two buckets rather than one map because
one base spellID can be a cooldown entry *and* an aura entry (Sweeping Strikes `260708`,
"Display order" below), and the two must move independently.

**Why the two consumers stay on Blizzard's table.** Alert routing (`GetResolvedEntry` →
`CDMAlerts`' `entryCategory`) must judge the category Blizzard's own viewer shows, since
that is what decides whether Blizzard is already playing the alert. Additional-Frame
membership (`IsCooldownSpellTracked`) is a union of Essential + Utility + HiddenActive and must not
change when CUE moves an entry between them or hides it — a spells frame would otherwise
lose a spell the player merely hid from the cooldown bar.

> ⚠️ **`GetTrackedCooldownIDs` has two enumeration modes, and CDMAlerts must use Blizzard's.**
> `performRebuild` enumerates candidates with it *before* asking `GetResolvedEntry` per id, so
> keeping only `GetResolvedEntry` on Blizzard's table is not enough: on the display table an
> entry **CUE has hidden** (-1/-2) is never enumerated at all, and its Blizzard alert stops being
> replayed while Blizzard's own viewer still shows it (the P1 cut shipped exactly that). The
> rebuild therefore passes `useBlizzardCategory = true`, which filters on `resolvedCategory`
> and reproduces the pre-overlay walk exactly: a CUE move or hide changes nothing in the alert
> model. An entry **Blizzard** hides stays out of the alert model in either mode —
> `MODEL_CATEGORY_IDS` holds no negative category, and Blizzard's own viewer plays nothing
> for it either.
>
> | caller | mode | why |
> |---|---|---|
> | `Core/TrackingModel.lua` `buildSections` | display (default) | files each row by `GetDisplayCategory`, and finds CUE-hidden entries by scanning -1/-2 |
> | `Core/CDMAlerts.lua` `performRebuild` | Blizzard (`true`) | alert replay follows Blizzard's viewer |
>
> `tests/displaycategory_check.lua` pins both modes.

The profile's overrides are read at build time, so every writer calls
`NotifyUserCategoryChanged()`. It invalidates **synchronously** — `ImportFullProfile` runs
its `FullLayoutRefresh` straight after the segment apply — and then calls the same
coalesced `fireSpellsChanged` the settings/event registrations use (hoisted out of
`initialize()` to file scope so both share it). A profile switch is a writer too:
`ProfileManager.OnProfileChanged` calls it right after swapping `private.profile`. The
`OnProfileChanged` callback's own invalidation comes too late for the overlay, since it
fires after `FullLayoutRefresh` has laid every tracker out against the old profile's moves.

Cached; invalidated on settings-window `OnHide` (the blob write point), profile change,
`NotifyUserCategoryChanged`, and the game events Blizzard's own data provider listens to,
all registered directly (`CooldownViewerSettingsDataProvider.lua:26-43`): the spec group
`TRAIT_CONFIG_UPDATED`, `ACTIVE_TALENT_GROUP_CHANGED`, `ACTIVE_PLAYER_SPECIALIZATION_CHANGED`,
`ACTIVE_COMBAT_CONFIG_CHANGED`, and the external-update group `SPELLS_CHANGED`,
`PLAYER_EQUIPMENT_CHANGED`, `PLAYER_PVP_TALENT_UPDATE`, `COOLDOWN_VIEWER_TABLE_HOTFIXED`,
plus `SPELL_DATA_LOAD_RESULT` for the spell-rank families (below).
The last four are registered after `SetScript` and each behind
`C_EventUtils.IsEventValid`: an unknown event throws in `RegisterEvent`, which would abort
`initialize` and the rest of Init.lua's `LOADING_SCREEN_DISABLED` callback, and
`PLAYER_PVP_TALENT_UPDATE` is not proven on WoW Forever.

Blizzard relays both groups as `CooldownViewerSettings.OnDataChanged`, which CUE listened
to until 2026-09-22. Not any more: the relay is conditional (`NotifyListeners` runs only
`if layoutManager`, and a spec switch notifies only when the resolved layout ID changes),
and it also fires on every uncommitted edit while the settings window is open, which the
layout blob does not hold until the window closes. Init.lua ran three full layout passes on
each relay (the 44 ms frame in the 2026-09-22 capture); the consumers of
`OnCDMSpellsChanged` already relayout on their own refresh (`IconTracker`'s
`setContainerSize` → `RelayoutSubtree`, the aura trackers' and IconTracker's
`OnComponentStateChange` on a collapse or count change, `AdditionalFrameManager`'s
`applyFilteredLayout`).

**Known and drawn.** Two per-entry flags, and each reader takes the one it needs.

- **`resolvedKnown`** (`entryKnown`) is `isKnown`, except that an aura entry is also
  known when the character has its spell (`IsPlayerSpell(info.spellID)`). Placement never
  changes it. Everything that follows Blizzard's categories reads this one:
  - CDMAlerts' `useBlizzardCategory` walk;
  - `IsCooldownSpellTracked` (Additional Frame membership);
  - `GetResolvedEntry`'s 4th return.
- **`resolvedDrawn`** is what CUE's display path draws: `resolvedKnown`, except inside a
  spell-rank family (below), where it depends on where the ranks sit. It is read by
  `getTrackedSpellMap`, the display branch of `GetTrackedCooldownIDs` and
  `GetResolvedEntry`'s 5th return. The Tracking model's `known` is this one, so its badges
  match what is drawn.
- **`resolvedForced`** is the subset of `resolvedDrawn` drawn only because the user ticked
  **Force active** in the Tracking tab (`applyForcedActive`, after `applyRankFamilies`). It
  reads `cdm_category_overrides.active[bucket][key]`, for every spec, and skips spell-rank
  family members (the Rank button places ranks). A forced **cooldown** is drawn only while
  `IsPlayerSpell` is true, since its icon always shows and a profile is shared across
  characters and specs; a forced **aura** is drawn as is, since its cell shows only while the
  aura is up. It is for an entry Blizzard counts inactive although the character has the
  spell (on WoW Forever, a condition that reads false). Not automatic: on retail `isKnown`
  false beside `IsPlayerSpell` true is also Blizzard hiding a replaced spell, and
  `IsPlayerSpell` is override-blind. `IsCooldownSpellTracked` admits forced entries, so a
  spells frame draws one too; CDMAlerts does not, so Blizzard's alerts never replay for it.

**Why the aura exception.** WoW Forever has one CDM entry per spell rank. Each rank's
condition names that rank and the next, so only the highest rank the character has reads
`isKnown`. Rejuvenation rank 1's condition names spell `744`, not `774`, so it never does.
On retail the exception only changes an aura entry marked unknown whose spell
`IsPlayerSpell` still reports. Blizzard's own viewer would not show that entry, so alert
replay now includes one entry it would leave out. User's call, 2026-09-25
(`.context/memory/project_forever_support.md`).

## Spell-rank families (`applyRankFamilies`)

A pure, extractable function that runs at the end of `buildResolvedCategories`, after the
display categories. It groups entries that have a spellID and a rank (`Util.SpellRank`, a
subtext with a digit) by **bucket and spell name**. The group is a family when it has two
or more ranks. Its **representative** is the lowest rank's key, stable across rank-ups, so
`priority_order`, `spell_colors`, `pandemic_glow_excludes` and `icon_overrides` survive
learning a rank. Retail spells carry no rank, so no family forms there.

| family | drawn | the one cell / icon |
|---|---|---|
| **whole**: every rank in one non-hidden display category (the default) | the representative only, while any rank is learned | a buff family folds every rank into the representative's identity set and owner map, so one cell matches whichever rank is up ("All ranks"). A cooldown family is drawn as its highest learned rank: `GetRankedSpell(rep)`, followed by IconTracker's `displaySpell` ("Highest") |
| **split**: ranks in different categories | each rank while it is learned, cooldowns included (a lower rank placed on its own; `isKnown` would hide it) | one per rank |

**Only buff families fold.** Identity sets and the owner map are keyed by spell id, and a
rank's cooldown and buff entries share it. Folding a cooldown family would widen a split
buff family's rank-1 cell to every rank, and re-key a buffs frame's rank. So cooldown
families are found by bucket instead: `GetFamilyRep(spellID, bucket)` and
`GetRankFamily(key, bucket)`.

**Additional Frames.** A frame naming any rank of a whole family holds the family under
its representative (`AdditionalFrameManager.linkedOwner`). It is routed away from the
tracker, drawn by the frame, and `IsCooldownSpellTracked(rep)` is true while any rank is.
That last rule is membership, not placement: whole or split alike.

**Rank not read yet.** A spell whose data is not cached (`C_Spell.IsSpellDataCached`) may
read no subtext, so it would look unranked. The pass hands those spells back; the build
calls `C_Spell.RequestLoadSpellData` for each and records them in `pendingSpellData`.
`SPELL_DATA_LOAD_RESULT` for one of them fires the coalesced rebuild, and marks it answered:
**each spell is requested once per session.** A spell its load never caches (Forever
1.60.1.70170 ships CDM entries with no loadable spell, spell 0 among them) comes back from
that rebuild still uncached, and re-asking it looped a model rebuild every frame. The Tracking
tab re-rendered on each one, and re-pooling a row mid-press cancels its click and its drag,
so every row control went dead with no error. Every other addon's
loads arrive on that event too, and only ours count. `SPELL_TEXT_UPDATE` was rejected: it
fires on description-text changes, so it would rebuild the model on stat changes.

> ⚠️ **`SPELLS_CHANGED` was once written off as "already covered by the
> `OnDataChanged` hook" and was not registered.** It is the *dominant* invalidation event on
> a classic-content client, not an edge case: on retail a spell arrives with a talent or a
> spec — both covered by the other four — but on a levelling character every trainer visit
> and every new **rank** of a known spell moves `isKnown` with no talent or spec change
> anywhere near it. Left to the relay, the resolved model stayed as it was at login until a
> `/reload`, a spec change, or the player happening to open the CDM settings, so a spell
> learned mid-session never entered the maps. Blizzard register it on their own provider
> (`CooldownViewerSettingsDataProvider.lua:42`); this mirrors that.
>
> `fireSpellsChanged` (file scope) coalesces via a `pendingFire` flag and `C_Timer.After(0)`, so a
> `SPELLS_CHANGED` storm (zone change, login) costs one rebuild rather than one per event —
> which is what makes registering so noisy an event affordable.

**Display order** is reconstructed from the same blob. `layoutContainer[1]`
(`orderedCooldownIDs`) is the player's full arrangement across all categories; entries it
does not mention — every entry when there is no saved layout, or a spell added since it was
written — fall back to `ORDER_UNRANKED_BASE + <DB2 category-set index>`, which sorts them
after the arranged ones while keeping Blizzard's default order among themselves. The ranks
are then projected onto tracker keys by `projectOrderRanksByCategory` — bucketed by the
**display** category, so an entry CUE moved ranks inside the tracker that draws it — and exposed as
`GetSpellOrderRanks(category)`. This is the only readable source for user arrangement: the
category-set API returns DB2 defaults, and Blizzard's resolved view taints the saved-data
path.

> ⚠️ **The projection is bucketed BY CATEGORY, and a flat one is a live bug.** A rank is a
> position *inside* a category, and a base spellID repeats across categories — live
> 2026-09-14, a warrior's Sweeping Strikes `260708` is cooldownID `95964` in
> `CooldownEssential` and `33985` in `BuffIcon`; Berserking `26297` is `198853` and
> `198854`. Because `orderedCooldownIDs` is ONE flat list spanning every category (Blizzard
> slices it per category in `GetOrderedCooldownIDsForCategory`,
> `CooldownViewerSettingsDataProvider.lua:249`), a single `{spellID = min(rank)}` map let a
> spell's place in the cooldown bar set its place in the buff bar, or the reverse. **No user
> rearranging was needed** — one of a pair merely *having* a cooldown entry pulled it ahead
> of a buff-only neighbour. Reported as two buffs in the wrong order, plus "Reset to default
> order" not matching Blizzard's Cooldown Manager, which is the same defect seen with
> `priority_order` cleared.
>
> The DB2 fallback had it too: `ORDER_UNRANKED_BASE + i` is a *per-category* index, so
> Essential #1 and BuffIcon #1 tied.
>
> Lowest-rank-wins survives **inside** a bucket, where several cooldownIDs can still resolve
> to one key (the Roll the Bones merge shape). `Util.BuildSpellOrderRank` picks the bucket
> from `CDM_COMPONENT_VIEWER_KEYS[componentName]` → `Enum.CooldownViewerCategoryIDs` — each
> of the four CDM trackers maps to exactly one category, which is what makes the lookup
> unambiguous. `tests/orderbucket_check.lua` drives the real projection over those four rows.
>
> The general rule this is an instance of: **a by-spell map may not be global unless its
> value is a union.** `resolvedIdentity`/`resolvedLinked` are unions and are fine flat; a
> *position* is not.

**The `selfMap`/`targetMap` split has no consumers left.** It splits on the CDM
entry's `selfAura` flag, which is dead data — Blizzard's own CDM never reads it and
watches every tracked spell on both units. Every caller merges both maps and feeds
the union to both containers; the aura group's filter string decides where a spell
can match. Splitting stranded spells in containers that could not match them (Fire
Breath reports `selfAura = true` but its linked aura is a target DoT). See
`.context/api.md`.

`includeLinked` selects the AURA key for each entry — `resolvedSpellID` (the base spell)
rather than `resolvedKey`. Aura-driven consumers (BuffTracker/BuffTrackerBars) pass true;
cooldown-driven ones (IconTracker) pass nil.

**One key per entry, either way.** It does *not* add `overrideSpellID` / `linkedSpellIDs[*]`
as sibling keys — that made every entry with a wider identity render N times: N always-show
cells under slots (one filled, the rest permanently empty), and N *filled* icons under
per-spell groups, where each of those groups widens to the same identity set and matches the
same live aura. Fixed 2026-09-09; before that the addon absorbed the shape instead
(`BuildSpellOrderRank`'s identity hop made the copies "land adjacent",
`buildAuraUnitWidgets` collapsed them so the panel listed a spell once).

**Consumers widen the MATCH, not the key** — a filter matches a set, a display row is one
thing. `GetAuraIdentitySet` is the widener, and every aura consumer already had a hook for it:
`SyncSpellGroups` takes it as `idSetFor`, both aura trackers' slot `playerIds`/`targetIds` now
return it, `IconTracker`'s aura slots always used it, and `CDMAlerts.applyAuraRegistrations`
expands it to register one `AddAuraSound` per real id (the engine watches for the id that
actually manifests, usually the linked one).

**The one exception is item-backed entries, and it needs no special case.** Their `info.spellID`
is nil, so there is no base key to collapse onto — `resolvedIdentity`/`resolvedIdentityOwner`
skip them entirely and the expansion still runs for them, which is the only way a trinket's
buff auras reach an aura tracker at all.

Custom entries with `unit == "focus"` are silently unsupported (no focus container).
Fires the coalesced `OnCDMSpellsChanged` callback.

## Item-backed entries (potions and trinkets)

`CooldownViewerCooldown.spellID` is **Nilable** (`CooldownViewerDocumentation.lua:132`), and
two 12.1 entry kinds always leave it nil:

| Kind | Identified by | Lives in |
|---|---|---|
| potions, healthstones | `spellCategoryID` (combat `4`, health `30`, healthstone `1711`, demonic `2566`) | `SpecAgnosticEssential` / `SpecAgnosticTracked` |
| trinkets | `equipSlot` (13/14) | `EquipSlotEssential` / `EquipSlotTracked` |

Blizzard requires no spellID — its display gate checks category + `isKnown` + `isInvisible`
only (`CooldownViewerSettingsDataProvider.lua:254`) — so these render in its own viewers and
can be arranged into any tracked category. Keying the resolution by spellID alone dropped
every one of them; the pre-rework trackers laid out Blizzard's viewer children and so never
saw the difference.

They are therefore given a **synthetic negative key** (`-cooldownID`), which cannot collide
with a real spellID, leaving every downstream map, sort and button pool keyed by a plain
number. `GetIconSource` is how a consumer tells the two apart and gets what it needs to draw
one; `Core/IconTracker.md` has the per-kind icon and cooldown queries.

**The synthetic key is offered to cooldown-driven consumers only** (`includeLinked` nil).
An aura-driven consumer would put it in an AuraContainer candidate filter, where it can never
match and would still cost a pooled button — and, under the slots engine, a permanently empty
visible cell. Those consumers get the real value from the linked expansion instead: an
`EquipSlotTracked` trinket carries its buff auras in `linkedSpellIDs`, as real spellIDs.

`GetTrackedCooldownIDs` requires a real spellID unless the caller passes `includeItemBacked`.
The Tracking model does, so potions and trinkets are rows there; it gives them no per-spell
settings, which need a spellID to key on.

## Cooldown membership (`IsCooldownSpellTracked`)

An O(1) "does this character have this cooldown?" test over `CooldownEssential` +
`CooldownUtility` + `HiddenActive`, gated on `isKnown` — the same class/spec gate Blizzard's
own display path applies — or on the user's **Force active** (`resolvedForced`). It exists for `AdditionalFrameManager.buildAFIconSpellMap`, whose
`assigned_spells` is **profile** data and therefore outlives a character and a spec change.
`HiddenActive` is in the set because hiding a cooldown in Blizzard's Cooldown Manager does
not take it from the character: the Tracking tab moves such an entry onto a spells frame,
which draws it from `C_Spell` like any other.

The key set is built lazily and dropped by `invalidateResolvedCategories` alongside the
`resolved*` tables, so it has exactly the model's lifetime and cannot answer from a model
that has since been invalidated. Three things it deliberately admits:

- **`resolvedKey`, not `resolvedSpellID`** — item-backed entries (potions, trinkets) carry a
  nil spellID and live under a synthetic negative key. Filtering on the spellID map would
  drop every one of them.
- **each entry's `overrideSpellID` alongside its base** — the retired Options pickers saved
  `overrideSpellID or spellID` (the id Blizzard's own item frame displays, so the id the user
  picked) while `resolvedKey` holds the plain base. A base-only set would miss on every
  overridden spell. This is the `Util.ResolveByBaseOrOverride` equivalence, paid once at build
  time rather than per lookup.
- **every raw `linkedSpellIDs` member** — unlike `resolvedOverride`'s own per-spell
  config/routing lookups, which stay base/override-only so that one talent-swap variant's
  config cannot silently capture its sibling's (DK Outbreak's Virulent vs Dread Plague, both
  `spellID` 77575). This is a plain "does the character have this" membership test, not a
  routing lookup, and a linked id only ever reaches `assigned_spells` because the Options
  collision dropdown exposed it as its own entry for the user to pick explicitly — already
  unambiguous. Omitting it left that pick permanently untracked even once its cooldownID went
  `isKnown = true`, so `buildAFIconSpellMap` intersected the spell away and it vanished from
  the Additional Frame.

It is a **pure peek** — `isResolved()`, never `ensureResolved()` — because its caller is a
per-`Refresh` path reachable from component enable on `PLAYER_LOGIN`, while `Initialize()`
waits for `LOADING_SCREEN_DISABLED`. Forcing the build there would cache an empty model for
the whole session (`.context/patterns.md`, "Lazy caches vs init order"). Hence the `nil`
return, which callers must treat as **fail open**.

## Identity sets

| Call | Returns |
|---|---|
| `GetAuraIdentitySet(spellID)` | Base + `overrideSpellID` + `linkedSpellIDs[*]`, or nil when the base spell is the whole identity. Widens an AuraContainer slot's candidate filter, which must match on the *set* even where the icon list must not. |
| `GetLinkedIdSet(spellID)` | **Linked ids only** — no base, no override. Drives the icon swap: Blizzard swaps exactly when `FindLinkedSpellForCurrentAuras` returns a *linked* spell, so a slot filtered on the full set would reveal the swapped icon while only the base aura is up. Nil when there are no links, so the caller allocates no slot. |
| `GetSwapIconSpell(spellID)` | `linkedSpellIDs[1]`: the aura trackers' `displaySpellFor` stand-in for the aura an entry displays. Blizzard takes the first *matching* link; these agree for single-link entries, which is nearly all of them. `IconTracker`'s swap slots do not use it: they bind the icon with `SetIcon` and draw the link that matched. |
| `GetIdentityOwner(spellID)` | **Reverse** of `GetAuraIdentitySet`: any member → that entry's base spellID. Aura consumers pass `includeLinked`, so their maps hold linked ids as keys, and anything configured against the base (`icon_overrides`, per-spell settings) is otherwise unreachable from the cell rendering it. |
| `IsEntryKey(spellID)` | Is the id some entry's **own** row key? A spellID can be one entry's own spell and another's linked id at once (Mass Entanglement `102359`: a Utility entry, and a linked id of Entangling Roots `339`), and the owner map keeps only the last writer, so this is how a caller tells the two apart. A peek: false while unresolved. |
| `GetModelStamp()` | Which model build is current, nil while unresolved. A peek; lets a cache derived from the model (Additional Frame routing) notice a rebuild it did not run. |

All filled in the same resolved-category pass, at no extra API cost, and all **accumulated
rather than overwritten**: two cooldownIDs can share one `spellID` (Rogue Roll the Bones
`1214909` is two entries, one with no links and one with all four buffs) and they dedupe to a
single map key, so one row must match any aura either can show. A flat write would pick the
survivor by walk order — and where one set is a strict subset of the other, the narrow winner
leaves the candidate filter matching nothing at all. `GetSwapIconSpell` is the exception and
keeps the **first** `linked[1]`: one texture has nothing to merge, so a stable answer beats an
arbitrary one. See `.context/patterns-cooldownviewer.md` "Identity: spellID is not unique".

**Except when the shared base is a placeholder, and then they must not dedupe at all.**
`findSiblingEntryKeys` runs one extra walk over the category sets before the build and returns
`{[cooldownID] = linkedSpellIDs[1]}` for every **sibling** entry — one of two or more on the same
base whose link sets are non-empty and *differ*. Live: a Lightsmith Protection Paladin has four
TrackedBuff entries all based on the spec aura `137028`, carrying Consecration, Sacred Weapon and
the two same-named Holy Bulwarks one link apiece. Those are four rows, and keying them by the base
made them one, named after a passive. A sibling's `resolvedSpellID` / `resolvedKey` is its own
linked aura, its identity set is its links *only* (the shared base, and the `overrideSpellID` that
mirrors it, are excluded — a spec aura is permanently up, so admitting it would put every sibling
back on one aura), and it writes no `resolvedOverride`, since base↔override must name one
cooldownID and here the base names all of them. One entry with links plus any number without is
the merge shape above and is untouched, which is what keeps Roll the Bones a single row.

> ⚠️ **"Differ" means the link *sets* differ, so the signature sorts before comparing.**
> `linkedSpellIDs` order is Blizzard's and is not stable between two entries on one base, and
> an order-sensitive `table.concat` signature splits an entry from its identical twin — after
> which each is keyed by its own `linked[1]` rather than by the shared base.
>
> Live incident: a classic-content client lists every **rank** of a spell in `linkedSpellIDs`,
> and its two Moonfire entries carry the same ten ranks in different order. They split, one was
> keyed `8925` instead of the base `8921`, and a manually added custom `8921` therefore no longer
> collided with the tracked entry — two Moonfire icons on the cooldown bar, which reads as the
> custom-spell dedupe failing when the dedupe is working correctly on a key that should never
> have existed.
>
> `tests/siblingkeys_check.lua` asserted the opposite until 2026-09-18, justified by "order is
> part of the identity because the two would pick different keys" — a description of the
> key-picking, not a requirement. It now checks that reordered sets do *not* split while
> same-size-but-differing sets still do.

## CVar ownership — `EnsureEnabled()`

Guard-writes `cooldownViewerEnabled` to whatever `needsViewerChildren()` asks for.
The addon drives the CVar rather than reading it as a preference: while it is off
`ShouldBeShown` hard-fails, so a feature reading viewer children cannot be made to
work by any addon-side effort — but keeping the CDM alive when nothing reads it costs
Blizzard's per-frame refresh for nothing.

**Only the ON direction is unconditional**, and two things reach it: the
`cdm_target_sounds` setting, and an alert only Blizzard can play (both below). Turning the
CVar *on* only ever makes more of Blizzard's UI
visible, so it needs no asking; turning it *off* is the half the player has to request.

**The `"0"` write is gated on `offWritePending` alone (see
[Turning the CDM off](#turning-the-cdm-off)) — granted by the prompt's Yes, spent by the
write, and never restored from disk, so it happens at most once per session and not at all
in a session that merely restored the answer.** Honouring "turn it off" is an action taken once, not a claim to keep
re-asserting. If something turns the CDM back on afterwards — another addon that wants it,
the settings panel, a console command — we do not write again, because two addons
correcting each other on `CVAR_UPDATE` is a ping-pong neither wins. The answer is not lost:
[viewer suppression](#viewer-suppression) keeps honouring it whatever the CVar says. Both
gates apply to the deferred `writeCVarAfterCombat` write, re-derived there rather than
replayed, because the predicate and the answer can both have moved during the pull.

Both writers settle `suppressing` through `setSuppressing`, so "the CDM is on and we did
not want it" and "the viewers are ours to hide" can never disagree.

**No Cooldown Manager, no writer.** MoP Classic has the CVar but not the viewers (`private.compat.HasCooldownManager()` false), so `ensureEnabled` returns before either gate: nothing to suppress, feed or ask about.

Scope is narrower than it looks: the CVar gates only `ShouldBeShown`. The data APIs,
the layout blob and the Tracking tab all keep working with it off. What stops is `RefreshData` — the *children*.

**No viewer-child reader is counted any more.** That is the endpoint of a long
migration, not a stub: every consumer that ever read a viewer child has been re-sourced or
given up, so no *data* need turns Blizzard's Cooldown Manager on.

**The one live term is `cdm_target_sounds`, and it wants Blizzard's alerts, not data.** An
alert on the player's debuff on the target has exactly one source: Blizzard's viewer plays it
live off `UNIT_AURA`, filtered to the player's own auras (`CheckAuraAddedAlertTriggers`,
`CooldownViewer.lua:1862`), while the addon side has only `C_UnitAuras.AddAuraSound`, which
fires for every source (`Core/CDMAlerts.md`). With the option on, `ensureEnabled` writes
`"1"`, [viewer suppression](#viewer-suppression) keeps the viewers invisible, and `CDMAlerts`'
`blizzardOwnsAlerts` sees them shown and stops replaying their sounds — every alert in the four
viewer categories is Blizzard's again, pandemic and charge-gained included. Per viewer, though:
one the player set to Hidden / In Combat is not shown, so `blizzardOwnsAlerts` is false for it
and CUE keeps replaying that category (the option's own target alerts are the part that is
lost — nothing else can produce them). The cost is
Blizzard's per-frame refresh, which is what turning the CDM off saves.

**The second term is `CDMAlerts.NeedsBlizzardViewer()`: an alert CUE cannot replay at all.**
That covers Sound or text-to-speech on pandemic or charge gained, and text-to-speech on a buff
applied or removed. It has no option: configuring one in Blizzard's settings is the request, and
`CDMAlerts`' rebuild calls `EnsureEnabled` when the answer changes (`Core/CDMAlerts.md` "Alerts
only Blizzard can play"). The same per-viewer caveat applies: a viewer the player set to Hidden
does not play them.

Switching it off hands the saved answer back. `ensureEnabled` remembers its last verdict
(`lastWant`), and on a `"1"` → `"0"` move grants one `"0"` write when `isHidden()` — the
prompt's own write, restored; with no answer on record it falls through to the prompt. That is
no write war: `want` depends on the profile and the CDM alert config alone, so nobody else's
`CVAR_UPDATE` can produce the transition.

The two settings that used to pin, and why neither does — **do not restore either without
reading this**:

| setting | why it pinned | where it went |
|---|---|---|
| `hide_active_swipe` OFF | the aura duration owned the icon's SPIRAL, so the icon had to be told to *yield* — and the yield came from `GetAuraState`, a viewer-child read per button per refresh | the engine-shown takeover slot button (`restyleSlotButton` / `syncAuraIcons`, `Core/IconTracker.md` "Aura takeover"), whose show/hide *is* the yield |
| `icon_visibility_mode` 2/3 | OR'd `auraActive` into `notReady` — "buffing ≠ ready" | **dropped**, deliberately. It only ever differed from `onCD` for an entry buffed while NOT on cooldown: a GCD-only tracked spell, a charge spender at full charges, or a buff outlasting its own cooldown |

The AF arm went with them. It existed because a `spells` AF hosts the **same factory** —
`getIconTracker` builds a `private.IconTracker.CreateTracker` whose `getSettings` returns
the AF's own profile table — so an AF's copy of either setting reached literally the same
reader. The consumption was *indirect*, which is why it was missed twice: a tracker never
called `GetChildren` on a viewer, it called `GetAuraState` → `rebuildAuraState`, which
did. Checking only for *direct* child reads concluded, wrongly, that an AF was clean.

The AF default table's `hide_active_swipe` was flipped to `true` alongside, matching the
two primaries. All three went back to the 2.13.4 `false` on 2026-09-28, with OFF drawing the
takeover again: an upgraded profile that never touched the setting had inherited "no buff
display at all" (`Core/IconTracker.md` "Aura takeover").

The fail-safe survives: `not private.profile` (or no `components` table) returns `true`,
so a half-built or corrupt profile can never be the reason someone's CDM gets turned off.
`tests/cvarkeepalive_check.lua` asserts every shape that used to pin, plus both fail-safe
cases.

> This predicate asks *"does an AF read aura state off a child?"* — a different question
> from *"does an AF cross-parent a live viewer child?"*, which no AF has done since
> `AdditionalFrameManager`'s pre-migration renderer (`applyIconLayout`) was deleted along
> with its own now-gone per-child alpha gate (`AF_OWNS_VIEWER_CHILDREN`). Justifying this
> CVar gate with a cross-parenting argument is what produced a live regression once; keep
> asking the read question, not the cross-parenting one, even though the cross-parenting
> mechanism no longer exists to compare against.

`SecondaryResources` used to be counted here too, through a `SR_CDM_KEYS_BY_CLASS` table.
It is gone: every readout in that file is engine-driven now, the last two (Evoker Essence
Burst, Demon Hunter reap forecast — parity items K5/K6) closed by giving up the Lua value
their consumers wanted rather than re-sourcing it. See
`.context/migration-parity-gaps.md` §K.

Not counted: `suppress_buff_icon_swap` OFF (the swap moved onto engine-shown swap
slots built from the plain `linkedSpellIDs` table); `pandemic_glow` and `active_glow`
(the former rides native `AddPandemicRegion`, the latter is a border in the button's
own subtree — neither reads a viewer child).

Conservative: anything undecidable returns true, and the per-component test is the
user's `enabled` intent, not the live `GetEnabled()`. On a stock profile the answer is
`false` for every class (`icon_visibility_mode` defaults to 1 everywhere), and adding a
stock `spells` AF leaves it `false` — only a deliberate switch to hide- or fade-when-ready
turns the CDM into a dependency.

Called from `Init.lua`'s `OnEnable` before components initialize, from `CVAR_UPDATE`
(so an external change reconciles either way), from
`OnProfileChanged`/`OnComponentEnable`/`OnComponentDisable`, and from every Options
setter that can move the predicate. **Never writes in combat** in either direction —
the write makes Blizzard show/hide the protected viewers and re-drives tracker layout,
so a mid-pull correction defers to a one-shot `OnLeaveCombat`, which then fires
`OnCDMSpellsChanged` so consumers re-arm.

### `IsDataAvailable()`

Whether the viewers are delivering *right now* (a live CVar read), not whether the
addon intends them to be. The two diverge for exactly the length of that deferral. The
four consumers that would **misbehave** rather than merely degrade read it:

- The `IconTracker` aura-slot engine — an unyielded real-CD swipe would stack under the
  still-drawing aura spiral.
- Both `Anchoring` `cdmAvailable` blocks — `IsCooldownViewerAvailable()` reports false
  when the CVar is off, which must not hide cast/resource bars.
- `Init.lua`'s one-shot Blizzard-position capture — its flag is consumed *inside* the
  readability test, so an unreadable viewer defers the capture rather than burning it.

## Turning the CDM off

A player running Blizzard's Cooldown Manager may be using it for something the addon
does not render, so turning it off is **asked, not assumed**.

**The ask fires exactly where the disable used to happen.** `ensureEnabled` computes
`want`, and `want == "0"` *is* the statement "we could turn the CDM off, because nothing
in this profile needs viewer children any more". That branch calls `maybeAskToHide()` and
returns instead of writing. So the question surfaces the moment the answer becomes
available and never while the CDM is still doing work for us — there is no separate
trigger condition to keep in sync, and every caller that can move the predicate (login,
profile change, component enable/disable, the ~15 Options setters) is already wired up.

**The CVar write is an action; the answer is persisted.** The two used to be one thing —
`hidden` was a session boolean on the reasoning that a CVar written to `"0"` stays `"0"`
across logins, so the answer needed no storage. That is true of the CVar half and of
nothing else. `suppressing` is `needsViewerChildren() or isHidden()` and
`needsViewerChildren()` was `false` for every profile, so a session-local answer meant **every
session after the one the player answered in ran with suppression off** — and the moment
anything put the CVar back (another addon, Blizzard's settings, a CVar reset) the viewers
returned at full alpha with nothing left to stop them. That is exactly what the
*Hide Blizzard's Cooldown Manager* toggle promises to prevent, and a toggle that persists
cannot be gated on a flag that does not. Two live reports.

So the answer lives in `charDB.cdm_hidden`, read through `isHidden()`. The *write* stays a
one-time action: `offWritePending` is granted by `OnAccept` and spent by the write, and it
starts `false` every session, so a **restored** answer never writes — that write happened
in the session the player gave it, and firing another at whatever turned the CDM back on
is the ping-pong the once-ever rule exists to avoid. Suppression alone honours it from
there.

Three fields reach disk, all in `private.charDB` — AceDB's `char` scope, set in
`Init.lua`'s `OnEnable`, character-scoped so they survive profile switches and never
travel in an exported profile: `cdm_hidden`, `cdm_never_ask`, `cdm_no_suppress`.

| answer | button | handler | effect |
|---|---|---|---|
| Turn It Off | 1 | `OnAccept` | `charDB.cdm_hidden`, permanent; `offWritePending`; `ensureEnabled()` |
| Keep It | 2 | `OnCancel` | `declinedThisSession`; asked again next login |
| Keep It, Don't Ask Again | 3 | `OnAlt` | `charDB.cdm_never_ask`, permanent |

Button-to-handler mapping is Blizzard's, from `Blizzard_StaticPopup/StaticPopup.lua`:
button3 → `OnAlt` (`:716`), and Escape under `hideOnEscape` calls `OnCancel` (`:820`).
Escape therefore lands on the session-only decline — the permanent answer is behind an
explicit third button and cannot be reached by accident.

`maybeAskToHide()` does not re-derive its caller's precondition. It adds only the four
things `ensureEnabled` does not know: not already hidden, not declined this session,
not `cdm_never_ask`, and the CVar is genuinely `"1"` right now. Plus out of combat — a
modal mid-pull is worse than waiting, and nothing re-arms it on leaving combat because
nothing needs to.

The dialog table sits at the **bottom** of the file, after `ensureEnabled`, so `OnAccept`
closes over a real upvalue rather than a nil (`patterns.md`, Lua 5.1 upvalue safety).

`OnAccept` saves the answer, grants the one write, and calls `ensureEnabled`. `suppressing`
is already false whenever the prompt can appear — that is the precondition for asking —
so the viewers have been handed back already, and `ensureEnabled`'s `SetCVar` fires its
own `CVAR_UPDATE` for Blizzard to re-resolve `ShouldBeShown`.

Nothing else gates on the answer: viewer suppression rides `suppressing` (below), and spell
resolution, identity sets, the Tracking tab and `GetTrackedCooldownIDs` all run off
data APIs the CVar does not gate.


## Viewer suppression

Holds the four viewers at alpha 0 with the mouse disabled, via a per-viewer `SetAlpha`
clamp. Shown state is Blizzard's alone: the addon calls no `Show()` / `Hide()` /
`UpdateShownState()`, and no longer overrides `visibleSetting` either (see
[The soft-override — removed](#the-soft-override--removed)).

Gated on `suppressing` = **`needsViewerChildren() or isHidden()`**, written only through
`setSuppressing` so a transition re-settles the viewers exactly once. Both halves earn
their place:

| half | meaning | reachable today |
|---|---|---|
| `needsViewerChildren()` | we forced the CVar to `"1"`, so a viewer whose own setting is "Always" is on screen only because we put it there | only with `cdm_target_sounds` |
| `isHidden()` | the player asked for the CDM off, and something turned it back on | **yes** |

Either half is overridden by `charDB.cdm_no_suppress` — see the off switch below.

The second half is the answer to *"another addon enables the CDM for its own purposes"*.
We concede the CVar — one `"0"` write ever, tracked by `offWritePending` — and take the
pixels instead. Re-correcting the CVar on every `CVAR_UPDATE` against an addon that does
the same is an unbounded ping-pong, and it would be arguing about the wrong thing: the
player asked for the icons off their screen, not for a particular CVar value.

**Off switch: `charDB.cdm_no_suppress`.** Suppression is deliberately blunt — it overrides
the player's own Hidden/In-Combat setting *and* forces alpha 0 — so there has to be a way
to say "leave Blizzard's frames alone entirely", for the case this module cannot see from
the inside: another addon that wants the CooldownViewer **visible** for its own purposes,
on a character where the player also asked us to turn it off. `suppressionAllowed()` gates
`setSuppressing`, so the flag can never go true while it is set.

Character-scoped alongside `cdm_never_ask`, and stored as the **opt-out** so an untouched
character has no key at all. Character rather than profile because it describes this
character's addon environment, not a layout: it must survive a profile switch and must not
travel in an exported profile, where it would carry one player's addon set onto another's.
The Options toggle (*CDM* section, column 1) shows ticked only while the viewers really are
hidden — it reads `IsSuppressing()`, the gate itself, because the saved answer and
`cdm_target_sounds` can each put them there. Ticking writes `cdm_hidden` as well as clearing the opt-out, so it works on a
character that never answered the prompt, and it grants no `offWritePending`: it hides, it
does not turn the CDM off. Unticking sets the opt-out and keeps `cdm_hidden`, so the prompt
does not come straight back. Its setter calls `EnsureEnabled()` rather than
`SyncViewerSuppression()` — the latter settles alpha against the current flag, and it is the
flag itself that has to change.

> ⚠️ **It used to read the opt-out alone**, so it showed ticked on every character that had
> never answered *Turn It Off* while nothing was hidden — reported 2026-09-11 as "the checkbox
> is on and the Cooldown Manager is not hidden".

**Gated on `suppressing`, not on [the saved answer](#turning-the-cdm-off).** `suppressing` mirrors
`needsViewerChildren()` and is written by `ensureEnabled` (and `writeCVarAfterCombat`)
every time the predicate is re-derived. True means the viewer is on screen *because we put
it there* — we forced the CVar to `"1"` — so leaving it visible would draw Blizzard's
icons over ours; no component gate narrows that. False means we want nothing from the
viewer, and it goes back to being the player's: the clamp stops firing, and any
alpha 0 *we* wrote is undone (tracked in `alphaSuppressed`, so a viewer Blizzard put at 0
is never touched).

`ensureEnabled` calls `syncViewerSuppression()` itself on a flag change rather than
leaving it to `Init.lua`'s `CVAR_UPDATE` handler: the branch that decides *not* to write
(`"0"` without consent) fires no `CVAR_UPDATE` at all, and that is exactly the transition
that has to hand the viewers back.

The clamp reads the flag live from inside its body — `hooksecurefunc` has no uninstall,
and the predicate flips on any profile change or Options setter.

Reasons formerly given here are false and should not be cited again: Additional Frames
no longer cross-parent a live viewer child at all — the renderer that did
(`applyIconLayout`, and its own per-child alpha writer `applyPerChildAlpha`) has been
deleted, not merely left unreachable — and `SecondaryResources`' proc scan
(`reapFc.findSFIID`) is gone too, deleted with the pre-12.1 fallback whose branches were
its only call sites.

The alpha is **clamped** by a per-viewer `hooksecurefunc(viewer, "SetAlpha")`, not
written once. `EditModeCooldownViewerSystemMixin:UpdateSystemSettingOpacity` re-applies
the EditMode Opacity setting on every `UpdateSystem` pass (layout apply, EditMode
enter/exit, spec or layout switch), while `syncViewerSuppression` runs only at init /
profile change / `CVAR_UPDATE` — without the clamp Blizzard's icons reappear over ours.

The clamp is installed by one **idempotent**
`installViewerSuppression(viewer)`, called from `Initialize()` *and* from every
`syncViewerAlpha` pass. `Initialize()` runs once on `LOADING_SCREEN_DISABLED` and skips
viewers whose frames don't exist yet; before this was self-healing, such a viewer spent
the whole session unclamped. Installed-state lives in a weak-keyed addon side table,
never a field on the viewer — writing Lua properties onto a CooldownViewer frame taints it.

> ⚠️ **Do not call `viewer:Show()` or `viewer:UpdateShownState()` from addon code.**
> Both descend `OnShow → RefreshLayout → RefreshData → SetCooldownID`, tainting every
> field Blizzard stores there (`cooldownInfo`, `validAlertTypes`, `auraSpellID`,
> `auraInstanceID`) because taint is scoped to the executing stack. Blizzard reads those
> back from genuinely secure code on the `UNIT_AURA` path and hard-errors on
> `auraInstanceIDToItemFramesMap`, which is flagged `DisallowTaintedAccess`. Observed as
> ~348 errors per delve run. `cooldownInfo` is sticky, so it does not self-clear.
> See `.context/patterns-cooldownviewer.md`.

`SyncViewerSuppression` handles alpha and mouse only, and must never write
`cooldownViewerEnabled`: it runs from `Init.lua`'s `CVAR_UPDATE` handler, so a CVar write
inside it would re-enter forever.

## The soft-override — removed

An `IsEditing` post-hook used to nil `viewer.visibleSetting` so Blizzard's `ShouldBeShown`
fell through to `return true`, keeping a Hidden/In-Combat viewer alive for us;
`requestSecureViewerReshow` (a redundant `cooldownViewerEnabled` write) existed to make
Blizzard re-resolve `ShouldBeShown` afterwards. Both are gone, and the pair was the taint
source the warning above describes — from Blizzard's own stack rather than ours:

`ShouldBeShown` reads `self:IsEditing()` and then `self.visibleSetting` **in the same
call**, so the tainted nil the hook left behind tainted the execution from that read on,
including `UpdateShownState`'s `SetShown(true)` → `RefreshData()` branch. The
`SetCooldownID` writes underneath landed tainted on the item frames, and the next
`UNIT_AURA` blew up in `CheckAuraAddedAlertTriggers` on `auraInstanceIDToItemFramesMap`
(86 errors in one report, sticky until `/reload`). The reshow poke made it *worse*: it
existed specifically to drive that show cascade.

So the override broke exactly the Blizzard alerts `cdm_target_sounds` keeps the viewer
alive for. There is no careful version — any addon write to a field `ShouldBeShown` reads
does the same thing. A viewer the player set to Hidden / In Combat now stays hidden, and
its Blizzard alerts stop with it. CUE's own trackers are unaffected: no CUE visibility
has followed that setting since the May 2026 clamp removal (`e7c571d`), and its only
reader, `Util.GetViewerVisibleSetting`, serves the one-time `pm.MigrateCDMVisibility`.

## Keep-alive bridge — removed

`GetAuraState(spellID)` → `auraActive` gave the plain-frame trackers the per-spell aura
state they cannot derive from `C_Spell`. 12.1 makes aura data unreadable as Lua values,
but one field on the suppressed children survived — `child.auraInstanceID`, **truthiness
only** (a non-boolean secret may be compared against nil, never passed to an API) — and
`rebuildAuraState` walked all four viewers once per rendered frame off it.

It is gone, with `Util.GetViewerChildren`, because its consumers went one at a time:

| consumer | where it went |
|---|---|
| `suppress_buff_icon_swap` | `GetLinkedIdSet` on an engine-shown swap slot, its icon bound with `SetIcon` |
| `active_glow`, `pandemic_glow` | regions in the aura button's own subtree, engine-driven |
| `SecondaryResources` (parity K5/K6) | gave the Lua value up rather than re-source it |
| `hide_active_swipe` OFF | the aura takeover is an engine-shown slot button over the icon, so the icon's swipe never yields and nothing asks whether the aura is up |
| `icon_visibility_mode` 2/3 | the "buffing ≠ ready" term was **dropped** — the deliberate trade that closed the last dependency |

The technique itself was sound and is worth remembering if a child read is ever needed
again: one `GetTime()`-stamped walk per rendered frame shared by every consumer, never a
walk per button, and a spell with no child degrading to `false`.

`child.cooldownInfo.linkedSpellID` was the bridge's second field and did **not**
survive: Blizzard selects it out of the plain `linkedSpellIDs` table but returns it from
inside a branch conditioned on a secret aura field (`auraData.sourceUnit == "player"`),
so it comes back secret-wrapped whenever auras are secret and the aura is live —
comparing it Lua-errored on a target DoT. The swap is now engine-driven (a `GetLinkedIdSet`
filter and a `SetIcon`-bound texture), reading no viewer child and working in combat.

`GetHideWhenInactive` — the live read of Blizzard's viewer-level "Hide when inactive" that
picked the buff trackers' groups-vs-slots engine — is gone too (2026-09-22). The engine is
`always_show_tracked` alone; `pm.MigrateHideWhenInactive` copies the viewer setting into it
once per profile and stores the reading as `_blizzard_cdm_hide_inactive` (see
`Core/AuraTrackers.md`).

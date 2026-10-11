# AuraBarTracker.lua / AuraIconTracker.lua

The two AuraContainer tracker **factories**. `CreateTracker(config)` builds one fully
independent instance — its own containers, cells and event driver, every piece of state a
local inside the factory function.

- `AuraBarTracker` renders single-line progress bars.
- `AuraIconTracker` renders a grid of icons through `IconTracker.PlaceGrid`.

Two files rather than one parameterized engine because only the shape is shared.

## Consumers

| Consumer | Spells from |
|---|---|
| `Components/BuffTrackerBars.lua` | a CDM category, minus AF-routed |
| `Components/BuffTracker.lua` | a CDM category, minus AF-routed |
| one instance per `bar`/`buffs` Additional Frame (`AdditionalFrameManager.getAuraTracker`) | that frame's `assigned_spells` |

An AF passes `config.parent`, which makes the tracker **hosted** — it fills the container
the AF already owns and the anchor system already positions, rather than becoming a second
top-level frame for the same component name.

## Engine choice

`tracker.IsUsingSlots()` is `always_show_tracked`: the always-show grid. AuraIconTracker's
collapsing chain (below) runs on slots too, but `IsUsingSlots` leaves it out, so the panels treat
it as a compacting engine. Until 2026-09-22 it also ORed in Blizzard's viewer "Hide when inactive"
(`not CDMDataSource.GetHideWhenInactive(viewerKey)`), read live on every Refresh. That is now a
one-time copy, `pm.MigrateHideWhenInactive`, run where `pm.MigrateCDMVisibility` runs (login and
`pm.OnProfileChanged`):

- it reads both viewers first; a missing viewer or a nil reading (Edit Mode has not applied the
  setting yet) defers the whole migration to the next login or profile change;
- a `false` reading sets `always_show_tracked = true` on BuffTracker and every `buffs` frame
  (BuffIcon), or on BuffTrackerBars and every `bar` frame (BuffBar); `true` writes nothing;
- the reading is stored as `_blizzard_cdm_hide_inactive = { BuffIcon = bool, BuffBar = bool }`,
  and its presence is the migrated flag.

The edge cases, decided by the user 2026-09-22:

- **Imports of pre-change exports are kept compatible.** An export taken before
  `profile_export_version = 2` carries `always_show_tracked = false` for every aura tracker whatever
  the exporting player saw, so `finishImport` re-applies the importing profile's stored reading over
  a pre-2 payload, for the applied segments only (`reapplyHideWhenInactive`, `Core/Profile/README.md`).
- **An Additional Frame created after the migration keeps CUE's default** (`always_show_tracked =
  false`, i.e. groups). It is not seeded from the stored reading.
- **A profile shared by characters whose Edit Mode layouts differ is decided by the first to log
  in**, since the migration is one-shot per profile.
- **An Edit Mode layout applied after login** leaves the migration deferred until the next login or
  profile change, rather than the same session.

The `viewerKey` config field went with the live read. Pinned by `tests/cdmdecouple_check.lua`.

## Three containers

Each instance runs three aura groups across **three** containers:

| Container | Unit | Filter |
|---|---|---|
| `<name>_main` | player | `HELPFUL\|PLAYER\|INCLUDE_NAME_PLATE_ONLY` |
| `<name>_target_harmful` | target | `HARMFUL\|PLAYER` |
| `<name>_target_helpful` | target | `HELPFUL\|PLAYER\|INCLUDE_NAME_PLATE_ONLY` |

`SetUnit` is per container, hence three rather than two. The third exists **only** so the
helpful block can be `SetShown(false)`n while the player targets themself, which would
otherwise draw a self-buff twice — every candidate-filter call is combat-restricted, so a
target-change re-filter is not available. On the icon tracker the two target containers are
also disabled while their identity gate fails ("Missing-buff glow" below).

Per-spell `aura_unit` restricts a spell to a subset of the three.

## Slot order

Under **slots** the list index IS the on-screen position. `fillSortedList` takes a `rank`
argument from `Util.BuildSpellOrderRank(name, spellMap)` — the component's stored order for
this spec first (`Util.GetTrackerOrder`: its own list, else the all-specs `priority_order`),
Blizzard's CooldownViewer order behind it — and hands it to `Util.SortByOrderRank`.

`BuildSpellOrderRank` returns **nil** for anything outside `CDM_COMPONENT_VIEWER_KEYS`, so
an aura-mode Additional Frame gets the plain spellID sort this always had: its spells come
from a user-ordered `assigned_spells` array, where a CDM-order sort would be no more correct
than the spellID one. Carrying the AF's own order through is still blocked by the
`table<spellID, true>` map interface, which discards it.

Order reaches the other two engines unevenly:

| Engine | Ordered? |
|---|---|
| slots | yes — `fillSortedList`, and the changed list changes `SyncSlots`' signature so the slots repoint |
| per-spell groups (BuffTracker's compacting default) | yes — the rank is passed to `AuraContainer.SyncSpellGroups`, which writes it into each group's `layoutIndex` |
| plain compacting group (the default) | **no** — Blizzard owns that flow via `AuraContainerSortMethod.Default` and there is no addon-side lever |

The Tracking tab disables Up/Down and drag-reordering on this engine, with a tooltip, so a
player is not left wondering why reordering a row changes nothing.

## Collapsing slot chain — `collapse_layout` [EXPERIMENTAL]

BuffTracker only: Options → Features → *Mix Player and Target Auras*, offered while *Always Show
Tracked Auras* is off (the grid outranks it, and `Refresh` turns the chain off under it). Off by
default. It was a disabled prototype from 2026-09-09 until 2026-10-02, when it came back for
cross-unit order (below). The `buffs` Additional Frames have no key, so no toggle.

The idea: run the slots engine (so the spell behind each button is ours to know), but anchor
the buttons to **each other** from a sizeless never-hidden `chainOrigin`, each carrying
`SetCollapsesLayout(true)`, so a button the engine hides closes its own gap and the rest slide
up. Chrome moves onto the button for the same reason — `cue_slot` cleared, `cue_spellID` set,
both read by `restyleButton` — because a chrome cell would stay drawn in the gap its button
just closed. Live-verified: it compacts, and per-spell cues land on it.

**What it is for: cross-unit Tracking-tab order** (the user's call, 2026-10-01). The groups
engine draws every target spell after the whole player block, since a container holds one unit
and its groups form one contiguous flow block (`.context/patterns-auracontainer.md` "Unit is
container-level"). The chain anchors buttons across all three containers, so `applySlotAnchors`
walks `chainSlots` **spell-major**: for each slot index, its player, target-HARMFUL and
target-HELPFUL buttons, then the next index. Normally one of the three is shown per spell and the
others collapse. Totem icons (`show_totems`) lead the chain from `chainOrigin`, as they lead the
groups run; the anchor signature carries `totemCount`, and `clearSlotEngine` drops the signature
because the groups run re-anchors the icons. Pinned by `tests/chaininterleave_check.lua`.

**What it costs.** Per-spell groups reach compaction *with* identity through Blizzard's own flow
layout, so they also wrap, multi-row and centre. The chain does none of those on its own: one
chain is one line (`max_per_row` / `max_width` cannot wrap it), and its run length is secret, so
centring goes through `pairFrame:ResizeToBoundsRect()` (`applyChainBounds`). Proc glow is off on
it (the glow sits on the chrome cell, which the chain hides). `IsUsingSlots` leaves the chain
out, so the panels hide overflow sizing and proc glow for it, as they do for groups.
`GetComponentSize` still reports the slots grid box.

**Open, needs a client:** centring. The buttons are grandchildren of `pairFrame` (it holds the
containers), and whether `ResizeToBoundsRect` reaches them is unverified. If it does not,
`center` alignment sits off-centre; left/right/top/bottom pin to the wrapper and are unaffected.

`chain_fit` (fit-to-box icon sizing) is not offered in the size-mode dropdowns. It is still
honoured by `iconDims`, `ComputeViewerIconLayout` and both `isFixed` tests, so a profile that
carries it stays correct.

It is also the only answer to our OWN layout shapes on a compacting display: per-line centring
of a partial row, `overflow_icon_size`, the `fixed_width*` modes, content-hugging width.
Blizzard owns the groups flow and the container rect is secret, so none of those can reach that
engine. None of them is wired to the chain today.

Findings worth keeping regardless, all live-verified 2026-09-09 and written up in
`.context/patterns-auracontainer.md` "Collapsing a slot chain":

- `SetCollapsesLayout` genuinely compacts a chain of engine-hidden frames, and is legal on a
  button whose shown state is secret — very likely *because* `GetPoint`/`GetLeft` deliberately
  report uncollapsed geometry, so the display compacts while no readable coordinate moves.
- The chain needs a non-collapsing head, and must not close back onto it (two-point anchoring
  puts the last link on top of the previous one).
- An anchor **target** propagates its forbidden aspects to the dependent: `SetPoint` is
  *refused*, not tainted, and the fix (`DisableUntrustedLayoutScriptsTemplate`) goes on the
  dependent.
- Cross-axis placement is an EDGE, never a midpoint — `placeGrid`'s rule. Centring both axes
  hangs the run half a box low.

## Summons: the CDM row never fills, and a slot row is what replaces it

Both trackers bind auras and only auras. A **summon** — Call Dreadstalkers, Summon Demonic
Tyrant, Charhound, any shaman totem — is a CDM tracked-buff entry that applies **no player
aura**: Blizzard's own buff items read totem data *before* aura data, which is the only reason
their rows fill. Ours therefore draw the chrome (icon, name, backdrop) and never move, in either
engine.

**That row cannot be repaired, and this is settled.** Repairing it needs "is slot N *my* spell",
and nothing supplies identity: `C_Secrets.ShouldTotemSlotBeSecret` is `true` for every *occupied*
slot, so the data is secret in exactly the case that matters. A guarded read that branches on it
was built and reverted the same day, and the `UNIT_SPELLCAST_SUCCEEDED` → `PLAYER_TOTEM_UPDATE`
correlation is rejected on record — read `.context/patterns-cooldownviewer.md` "A tracked buff has
TWO duration sources" and `.context/patterns-secrets.md` "Totem slots" before touching either.

**What ships instead is `show_totems`** (Options → Features → *Track Totems*, default off), on
`AuraBarTracker` (BuffTrackerBars) and, since 2026-09-30, on `AuraIconTracker` (BuffTracker —
see "The icon twin" below). On the bar tracker it is one bar per totem **slot**, trailing the
run after the aura bars. The label is
deliberately "totem", not "summon" — the slot is a totem slot whatever the game happens to put in
it, and a shaman totem is not classically a summon. It works precisely
because it is slot-indexed and therefore never asks which spell is where. `haveTotem`, the name,
the icon and the duration are all secret, and each is piped into an engine sink that accepts a
secret — `SetAlphaFromBoolean`, `SetText`, `SetTexture`, `SetTimerDuration` plus a
`C_DurationUtil` text binding. The binding needs `SetFormatter` after `SetToDefaults`, which
clears it: without a formatter it writes no text, and the rows shipped with no countdown
(Consecration report, 2026-10-08). The rows take the one `SetDurationText` uses, from
`GetDefaultAuraDurationFormatter()`. **Nothing in that block reads, compares or branches on a totem
value**; adding one such test is what breaks it.

The one branch that is allowed — and required — is `if duration then`, on
`GetTotemDuration(slot)`. That return is nil for an empty slot and is not itself secret, so the
test is legal whatever the slot's restriction state; `haveTotem` is then piped into
`SetAlphaFromBoolean`, never tested. `C_Secrets.ShouldTotemSlotBeSecret` plays no part.

Every other gate has cost a live incident:

- **No gate at all** (2026-09-16) pipes an empty slot's duration, which is `nil` (the generated
  docs mark that return `Nilable = false` and are wrong) and `SetTimerDuration` rejects
  outright. Five empty slots on a warlock threw five times inside `Initialize`, and the throw
  unwound through `Init.lua:106` into AceAddon's `EnableAddon` — every component registered after
  BuffTrackerBars never initialized, so the whole addon read as dead.
- **The predicate alone** (2026-09-16) read `false` as empty, so every row blanked whenever
  restrictions were off — out of combat, in town — and the feature looked as if it had never
  worked.
- **`secret or haveTotem`** (2026-09-17) trusted `false` to mean *readable*. A warlock's slot 3
  answered `false` while `GetTotemInfo` returned a secret `haveTotem` in the same call, and the
  poll threw on the boolean test every 0.25 s (1111×).

Three consequences worth knowing before changing it:

- **Both engines, trailing the run** (2026-10-09, the user's call; they led it from 2026-10-08,
  and trailed it before that). Each row sits in a **slot frame**, a child of `pairFrame` created
  with `DisableUntrustedLayoutScriptsTemplate` and flagged `SetCollapsesLayout(true)`. The slot
  frame is the row plus one `bar_spacing` on its leading side, and the row is pinned to its
  trailing edge. The slot frames chain with **no offset**: under groups from the target-helpful
  container's trailing edge (the last link of the aura chain, whose secret extent the engine
  resolves), under slots from the last spell cell, or one spacing back from `pairFrame`'s near
  edge with no spells. That is what makes the display engine-independent, and why neither
  settings panel gates on `IsUsingSlots()`. `layoutTotemCells` therefore runs **after** both
  engines in `Refresh`.

  > ⚠️ **Which frame is templated is the whole trick.** The first build chained plain rows onto
  > `pairFrame`'s trailing edge, and that is refused: `pairFrame` carries
  > `DisableUntrustedLayoutScriptsTemplate`, so a plain dependent throws *"Anchoring disallowed as
  > dependent object would inherit forbidden aspects: UntrustedLayoutScriptExecution"* (live
  > 2026-09-16). The rows were then pinned to the wrapper's far edge (a box-height gap with no
  > aura up, the Consecration report), and then led the run with `pairFrame` anchored onto them
  > (one `bar_spacing` per empty slot left behind, and no following BuffTracker).
  >
  > The slot frames carry the template themselves, so anchoring one onto a container inherits
  > nothing new. The row inside anchors only to its slot frame, as the icon twin's bare totem
  > icons anchor onto `pairFrame`. Not a chain onto `pairFrame`'s own edge: the slot frames are
  > its children, so `resizePair` would grow it from them on every tick.
  >
  > **Emptying the containers is not an escape** — there is no aspect-removal API at all, and
  > `pairFrame`'s copy comes from the template we give it at creation, not from the containers it
  > holds. See `.context/patterns-auracontainer.md` "Anchoring disallowed".
  >
  > Inside `pairFrame`, the rows move with it, so the groups stack follows BuffTracker
  > (`followTarget`) with totem rows on as well.
- **Every slot is placed, occupied or not; an empty one collapses.** Each row is placed out of
  combat because a summon lands mid-fight, and `Refresh` places nothing in combat.
  `Show`/`Hide` and alpha are available then, so the poll `Hide()`s an empty slot's frame (a
  plain fact, `GetTotemDuration` nil) and the chain closes the gap engine-side. The spacing goes
  with it: an anchor offset survives a collapse, but spacing inside the collapsed frame does not.
  All three aura containers collapse too, so a block hidden by self-target suppression leaves no
  hole before the rows. The aura chain's own seams are still anchor offsets (the containers'
  extents are secret, so no spacing can be built into them), so with empty aura blocks the rows
  sit up to two `bar_spacing` past the edge. Under slots the rows come after every spell cell, so an empty slot is no
  longer a gap. Turning the key off in combat hides the rows and keeps `totemCount`, so turning
  it back on can show them again. Turning it on in combat with no rows placed does nothing until
  combat ends.
- **Poll-driven, not event-driven.** `PLAYER_TOTEM_UPDATE` covers spawn and destruction but not
  natural expiry (Blizzard hits the same hole and works around it in
  `CooldownViewerCooldownItemMixin:OnCooldownDone`), and no readable time-left exists to notice.
  A 0.25 s ticker is the whole driver; `OnDisable` cancels it, or a deleted Additional Frame's
  poll outlives the frame.

**Additional Frames have no equivalent** — the key is absent on every `bar` and `buffs` frame, so
`totemRowCount` returns 0 and both panels hide the widget. Every totem display exists only until
Blizzard gives AuraContainers a totem API, at which point identity returns and totem-backed CDM
entries should start working through the existing slot path with no extra rows at all. That is
also why the feature has exactly one key per tracker and no settings of its own — every knob added
here is migration debt for a display whose purpose is to stop existing.

### The icon twin (BuffTracker, 2026-09-30)

The user asked for the icon version on 2026-09-30, reversing the 2026-09-05 call that bars were
the only place a totem display belonged. Same key, same rule — pipe, never branch, `if duration`
the only test — with three differences, each forced by the icon shape:

- **In line, leading the run, before the player buffs** (the user's call, 2026-09-30; a first
  build put them on a separate line beyond the aura block; the bar rows followed on 2026-10-08).
  "Leading" is the flow start: the
  left for a horizontal run aligned left or centre, the right for one aligned right, the top of a
  vertical one.
  - *Groups engine:* `chainTotems` chains the icons from `pairFrame`'s flow origin, each with
    `SetCollapsesLayout(true)`, and `syncContainerLayout` joins the player block onto the last
    one. An empty slot's `Hide()` closes its gap engine-side, so the buffs slide up to the last
    totem shown with no `SetPoint` in combat, and because the icons are children of `pairFrame`,
    `resizePair`'s bounds (and so `center` alignment) cover the whole run. Inferred, not yet
    seen: with no totem up the player block sits one `icon_offset` past the origin.
  - *Slots engine (always-show grid):* `layoutSlotCells` gives the icons the first grid cells,
    so each slot keeps a fixed place and an empty one is a gap, like any always-show slot.
    `placeCell` never greys a totem icon under `desaturate_inactive`.
  - `GetComponentSize` counts the icons as grid cells under slots and keeps the configured box
    under groups. Totems alone still size the box; `IsCollapsed` is false for them, as on the bar
    tracker.
  - *Collapsing slot chain:* `applySlotAnchors` chains the icons from `chainOrigin` through
    `chainTotems`' `head` argument, and the first spell button joins the last one.
- **Event-driven, no poll.** Each icon is a plain frame with a `CooldownFrameTemplate` cooldown
  fed by `SetCooldownFromDurationObject`, so the countdown text is the cooldown's own
  (`timer_font`, `hide_cd_text`, `hide_cd_swipe` and `reverse_swipe` through `restyleButton`, which
  skips `ApplyTooltip` / `ApplyActiveGlow` for a `cue_totem` frame). `PLAYER_TOTEM_UPDATE`,
  registered only while the key is on, re-pipes every slot. Natural expiry, which fires no such
  event, is caught by the cooldown's `OnCooldownDone`, the way Blizzard's
  `CooldownViewerBuffIconItemMixin:OnCooldownDone` catches it. The handler hides an emptied slot,
  re-pipes only `haveTotem` into the alpha of one that still reports a duration, and never
  re-feeds the cooldown, so it cannot restart the one it is reporting on. **Open, needs a
  client (#57):** whether the slot has cleared by the time the swipe ends. Blizzard's own
  comment says *"No external event is dispatched when a totem finishes"* and keeps its own
  expiry time, which addon code cannot read; if the slot lingers, the spent icon stays until
  the next `PLAYER_TOTEM_UPDATE` or out-of-combat Refresh. Not papered over with a poll or a
  deferral (review 2026-09-30). The bar rows have no cooldown to hook, which is why they poll.
- **Restyled only when the aura buttons are**: the font flag, a moved `RESTYLE_KEYS` value, or
  a new icon (`prepareTotemCells`), not on every Refresh. Not registered with
  `AuraContainer.TrackButton`, whose registry also feeds the CDM alert walk.
- **An empty slot is `Hide()`n.** Emptiness is a plain fact (`GetTotemDuration` nil), so it gets a
  real `Hide()`; only `haveTotem` goes through `SetAlphaFromBoolean`, being secret. Nothing is
  re-anchored in combat: the grid keeps the place, the groups chain collapses it engine-side.

`Refresh` bails in combat before the layout, so a `show_totems` toggle made mid-fight applies at
combat end; the pipe itself runs in combat. `OnDisable`'s `UnregisterAllEvents` drops the event
with the rest. Pinned by `tests/totemicons_check.lua`.

## Which spell the icon and name are drawn from

**The entry key is the cast spell; the thing on screen is the aura.** They differ whenever a
CDM entry carries `linkedSpellIDs` — DK Outbreak `77575` displays Virulent Plague `191587` —
and drawing the key gives the cast icon where Blizzard gives the debuff icon.

Blizzard resolves it in `CooldownViewerItemDataMixin:GetSpellTexture`: the aura's own icon
when `PreferAuraDataOverSpellData` holds (a passive entry, or an actively-cast one whose aura
lands on the target — `CooldownViewerItemData.lua:558/1091`), else the dynamic-appearance
branch's `GetLinkedSpell()` (`:571`). The live aura is secret, so `displaySpellFor` in each
tracker stands in `CDMDataSource.GetSwapIconSpell` = `linkedSpellIDs[1]` — a static
approximation, exact for the single-link entries that are nearly all of them. An entry with no link, and the item-backed keys that already *are* aura
ids, fall through unchanged.

Where it has to be applied depends on the engine, and only one of the four paths was ever
right by accident:

| Engine | icon | name |
|---|---|---|
| groups, per-spell (`AuraIconTracker`, always) | `SetIcon` bind — engine writes the live aura | n/a |
| groups, plain (`AuraBarTracker` default) | `SetIcon` bind — engine writes the live aura | `SetSpellName` bind — same |
| slots (`AuraIconTracker`) grid cell | `placeCell` chrome — **ours**, needs the hop | n/a |
| slots (`AuraIconTracker`) collapsing chain | `SetIcon` bind — engine writes the live aura | n/a |
| slots (`AuraBarTracker`) | `restyleBarCell` — **ours**, needs the hop | `C_Spell.GetSpellInfo` — **ours**, needs the hop |

The plain-group row is why the bar tracker looked correct on its default engine while the
icon tracker did not, from the same spell map: a bind delegates the resolution to Blizzard,
an addon-owned texture inherits none of it.

> ⚠️ **The hop is an APPROXIMATION, and a multi-link entry is where it breaks visibly.**
> `linkedSpellIDs[1]` is a guess at which link is live. Rogue Roll the Bones `1214909` carries
> all four of its buffs in one entry, so the hop drew the same icon whichever one was rolled —
> reported as *"no matter which buff is rolled, the icon shown is always the same"*, and
> bisected to the commit that made per-spell groups unconditional (the plain groups it replaced
> were `SetIcon`-bound and had never needed a guess).
>
> **So bind wherever the button's own visibility already IS the aura's.** Blizzard hides an
> aura button when its aura is gone (`ApplyVisibility`), so a bound button never has an
> inactive state to draw a static icon for, and `SetIcon` hands the whole question back to the
> engine — which reads the matched aura's `icon` field and needs no Lua aura read to do it.
> That covers per-spell groups and the collapsing chain. The always-show GRID genuinely cannot
> use it: its cell is drawn while the aura is *down*, so it must name a spell, and one cell per
> link would draw four static Roll the Bones icons instead of one. The grid keeps the hop.
>
> `SetIcon` / `ClearIcon` are plain mixin methods with no combat gate
> (`Blizzard_CustomAuraButton.lua:223/232`), so the choice is re-decidable per restyle rather
> than frozen at acquire — but each ends in `UpdateAllAuras()`, so `restyleButton` gates them
> on a `cue_iconBound` transition.

`icon_overrides` is what the bind costs, and it wins anyway: an override resolves from the
**base** key and takes the texture back with `ClearIcon`, because a user pinning a texture
outranks Blizzard's precedence and the bind would otherwise clobber it on every aura update.
Every per-spell config lookup stays keyed by base.

## Global borders

`icon_border` (both trackers) and `bar_border` (bars) are re-applied from the **restyle**
path, which runs inside `initializeFrame` on acquire and again on every dirty restyle —
buttons are write-locked outside those windows. Where the border lands depends on the
engine, and each engine draws it exactly once:

| Engine | Icon border | Bar border |
|---|---|---|
| groups | the button (it *is* the icon) | `button.cue_Bar` |
| slots | the cell (`placeCell` / `restyleBarCell`) | the cell's `cue_Bg` |

Slot buttons carry `cue_slot = true` so `restyleButton` / `restyleBarButton` skip the pair
the cell already owns — except the icon border under `desaturate_inactive` (next section),
where the button's colour copy would otherwise cover an inside border. The bar overlays are **siblings** of the region they outline, not
children, so `bar_content` show state has to be applied to them separately — from
`iconShownFor` / `barShownFor`, the same settings predicates `applyBarGeometry` writes with.
Never `SetShown(region:IsShown())`: inside an aura button that read is a secret and throws
even at `initializeFrame` time (see `patterns-auracontainer.md`).

**Per-spell icon border colour** (`spell_borders`, #8, icons only — bars wait on #47): the
same two sites pass `Util.GetSpellBorderColor(settings, spell)` as `ApplyIconBorder`'s
colour, which replaces the global one and draws even while `icon_border` is off. The spell
is the one the icon shows: `spellOfButton` (a per-spell group's or chain link's
`cue_spellID`, else the grid slot's `spellList` entry) for a button, `spellList[cue_slotIndex]`
for a cell. A plain group has no button↔spell binding (secret), so it keeps the global
border. Written from the Tracking tab's row menu, whose setter raises `fontsDirty` itself
(`restyleSection`): the map is a table, so the `RESTYLE_KEYS` diff never sees it change.
`IconTracker` passes it from `placeIconButton` on every layout pass and needs no flag.

A border settings change reaches live buttons through the `fontsDirty` bridge
(`Options.refreshGlobalChrome`); without it `RestyleIfDirty` is a no-op and the change would
wait for a profile switch. **Every** profile-level chrome key goes through that one helper
for the same reason — `icon_zoom`, `icon_aspect_ratio` and `icon_overrides` shipped calling
a bare `RefreshAllComponents()` and so did nothing to a live buff icon until a `/reload`,
because the crop and the override texture are both written by `restyleButton`.
Per-tracker *settings* keys do not depend on that flag: each
tracker's `Refresh` also diffs its own `RESTYLE_KEYS` list and marks dirty on any move, so a
setter that forgets `private.fontsDirty` no longer strands the change until a `/reload`.

## Desaturated inactive icons — `desaturate_inactive`

Slots only (Options hides the toggle unless `always_show_tracked` is on), default `false`.
Greys a tracked icon while its aura is not up, including a target-tracked aura with no target.

**No aura is read.** Whether an aura is up is secret, but the engine shows a slot button exactly
while its aura is (`ApplyVisibility`), so the button is made to carry the active state:

| Layer | Owner | Drawn |
|---|---|---|
| cell icon, `SetDesaturated(true)` | `placeCell` / `restyleBarCell` | always — the inactive look |
| full-colour copy of the same texture | slot button (`cue_Icon` on icons, `cue_ActiveIcon` on bars) | only while the engine shows the button |

- **Texture** is copied from the cell's icon every `Refresh` (`applyActiveIcons` on icons,
  `layoutBarCells` on bars), because the spell on an index moves with the list; with the
  setting off the copy is set to `nil`. Both writes skip while `IsAuraAccessBlocked()` — the
  button subtree carries `DenyTaintedAccessWhenAurasAreSecret` — and catch up on the next
  Refresh outside secrecy.
- **Crop:** icons copy the cell's `GetTexCoord()` after `RestyleIfDirty` (which crops every
  button to `icon_size`, wrong for an `overflow_icon_size` cell); bars crop in
  `restyleBarButton` and anchor the copy `SetAllPoints(cell.cue_Icon)`, so
  `icon_size` / `icon_offset_*` need no geometry of their own.
- **Border / `hide_icon`:** the copy sits a frame level above the cell, so with the setting on
  the button also takes `ApplyIconBorder` and (icons) `ApplyIconVisibility`; with it off the
  button's border is hidden again.
- `desaturate_inactive` is in both `RESTYLE_KEYS`, so its setter needs no `fontsDirty`.
- Groups has no inactive state to draw and is unaffected; the disabled chain binds the
  button icon itself and skips `applyActiveIcons`.

## Missing-buff glow — `missing_glow` (icons only)

Per spell, opt-in, own colour: the Tracking tab row menu's **Glow When Missing** checkbox and
**Missing Glow Color** swatch, offered on BuffTracker and `buffs` frames while
`always_show_tracked` is on. `missing_glow[spellID] = {r, g, b, a}`; an entry turns the glow on
(red at first), no default table. Grid only: the chain and groups hide every cell.

**No aura is read — the inverse of `desaturate_inactive`.** The glow is drawn on the cell and
erased while the aura is up, through masks (`.context/patterns-auracontainer.md` "Where a
decoration goes"):

- `cellForSlot` builds the glow with the cell (`GlowEffect.CreateActiveBorder`, four edge
  textures), hidden.
- `initSlotButton` binds a transparent mask to its button (`IconTracker.BindCoveredMask`,
  `AddDispelTypeTexture` with `showAlways`) and adds it to all four edges. The engine shows that
  mask exactly while the button's aura is matched. A cell gets exactly three slot buttons, one per
  container, which is the three-mask cap per texture, and they never move to another cell, so the
  masks are attached once and never removed. Attaching in `initializeFrame`, before the provider
  restricts the button, needs no combat or secrecy gate.
- `placeCell` → `syncMissingGlow` points the glow at the spell now on the index (colour, and
  `cue_MissingTargetOnly` from the same `UnitScopeAllowsSlot` test the player slots use) and
  clears `cue_MissingWant` when the spell has no entry.
- `applyMissingGlowShown` shows it when wanted and, for a spell tracked on the target only,
  while a target exists. The target handler re-runs it for every cell, combat-safe.

**The target containers are disabled, not only hidden, while their identity gate fails**
(`AuraContainer.GateOnIdentity`, armed in `Initialize` and re-armed on every target / faction
edge). A hidden container stops processing and keeps the last target's matches; a mask ignores
its parent's visibility, so a frozen match would keep erasing the glow — a friendly target's HoT
went on erasing a self-buff's glow after the player targeted a boss. `syncSelfTargetSuppression`
still hides them for the layout.

Known limits (the tooltip steers to Track On):

- With Track On at "both" the addon cannot tell a self-buff from a target debuff
  (`selfAura` is dead data, `.context/api.md`), so an untargeted debuff glows. Track On = Target
  fixes it.
- On "both", a friendly target carrying the player's buff erases a self-buff's glow, and while
  the player targets themself the hidden helpful container keeps the previous friendly target's
  matches (that hide is not an identity failure). Track On = Player avoids both.
- A summon applies no aura, so its glow never goes out. `hide_icon` leaves the glow around an
  empty cell.

## CDM visual alerts as a persistent glow

A Visual alert the player configured on `OnAuraApplied` in Blizzard's own Cooldown Manager is
replayed here as a glow that runs for as long as the buff does. `applyCdmAlertGlow` walks every
acquired button through `AuraContainer.ForEachTrackedButton` and hands each one the
`Enum.VisualAlertType` from `CDMAlerts.GetAuraVisualAlert`; `AuraContainer.ApplyCdmAlertGlow`
builds the art in the button's subtree, and the **engine's** own show/hide of that button is the
alert's fire and release. There is no aura-application callback in 12.1 to trigger it from —
this sidesteps needing one. Full reasoning and the four caveats: `Core/CDMAlerts.md`.

The pass only runs from `Refresh`, and the alert model is rebuilt on a debounce *after* the
`OnCDMSpellsChanged` refresh that preceded it — so the tracker also refreshes on
`OnCDMAlertsChanged`, which `CDMAlerts` fires once the new model is in place. Without it the glow
stayed dark until the first out-of-secrecy refresh, usually the end of the next combat.

It needs to know which spell a button holds, so it runs under **slots** (from the cell map) and
under **per-spell groups** (from `cue_spellID`), but not under plain groups, where a button
resolves nil and stays dark. Note that is a *different* restriction from `proc_glow`'s: that one
is slots-only because LibCustomGlow needs an unrestricted cell, while this glow lives in the
button's own subtree like `active_glow`.

The pass is gated on `Util.IsAuraAccessBlocked()` — the overlay is in a subtree carrying
`DenyTaintedAccessWhenAurasAreSecret`, so `SetShown` on it throws inside an encounter. A glow
already running is unaffected by that gate, because this pass is not what shows it.

## Fonts

Both restyle paths apply `timer_font` / `stacks_font` (and the bar's `name_font` /
`duration_font`) through **`Util.ApplyFontProfile`**, never by hand. The profile block is
not just face/size/outline/shadow/colour — it also carries `anchor_point`, `offset_x` and
`offset_y`, and the Options panel builds position widgets for every one of these keys.
`AuraIconTracker.restyleButton` open-coded the first half and dropped the second, so the
Font *position* controls were live-looking and inert on buff icons — the stack count sat
at its creation-time `BOTTOMRIGHT` whatever the dropdown said. One helper, both halves.

`cue_Count` is ours (`button:CreateFontString`) and `cue_Timer` is the Cooldown's own
countdown region; both are anchored to `button`, which is `SetAllPoints` to the chrome cell
under slots, so one parent serves both engines.

## Callback lifecycle

Both factories register their shared-bus callbacks — `OnCDMSpellsChanged`, plus
`OnCDMAlertsChanged` on the icon factory — each calling `tracker.Refresh()`. Neither refreshes on
a combat transition any more: `Refresh` bails in combat, a pull-time call (inside
`PLAYER_REGEN_DISABLED`, before the lockdown) only redrew what was on screen, and the catch-up
on exit is `Core/Anchoring.lua`'s `OnLeaveCombat` pass, which runs `ContentLayout` = `Refresh`.
That pass reaches only a tracker **shown** at combat end, so a spells/alerts change that landed
mid-fight registers a one-shot `catchUpAfterCombat` on `OnLeaveCombat` from `onCallbackRefresh`
— never from `Refresh`'s own combat bail, which every in-combat layout pass hits. Without it a
tracker hidden by a rule or its parent kept the stale map, and under an `out_of_combat` hide
through the whole next fight, since its next reveal is the pull. `unregisterTrackerCallbacks`
drops a pending one, so a deleted Additional Frame does not refresh at combat end. A shown
tracker refreshes twice on that exit; only a fight with such a change pays it.
That pass carries no font pass, so the combat early-return itself keeps a font edited mid-fight:
under `private.fontsDirty` it calls `AuraContainer.MarkDirty`, whose flag survives until
`RestyleIfDirty` can apply it. They are **named**
(`onCallbackRefresh`, wired through `registerTrackerCallbacks` / `unregisterTrackerCallbacks`)
rather than anonymous closures, because `Callback.Unregister` needs the same function
reference back.

They were anonymous, and that was a live crash rather than a tidiness problem. Each
`createTracker` call registers its own set, so one set per `buffs`/`bar` Additional Frame.
`tracker.OnDisable` could not remove them, so a deleted frame's three handlers kept firing
forever and accumulated one set per deletion. Each call reached `getEnabled`, which indexed
`getSettings()` blind — and for a hosted tracker that returns
`private.profile.additional_frames[id]`, nil once the frame is gone. `Callback.Trigger` has
**no pcall**, so the resulting error aborted every handler registered after it on that
dispatch. `getEnabled` now returns `settings and settings.enabled`; every consumer treats it
as a truthy test, so nil is safe where the error was not.

`registerTrackerCallbacks` runs from both `Initialize` and `OnEnable`; `OnDisable`
unregisters. Both are idempotent and guarded by a per-instance `callbacksRegistered` flag, so
the primary trackers — which receive `OnEnable` on every profile switch through
`FullLayoutRefresh` — pay nothing at steady state. **The pairing is the point:** unregistering
without a matching re-register trades a loud bug for a silent one, leaving a re-enabled
tracker permanently deaf to the bus. The same defect class, and the same fix, appear in
`Core/IconTracker.lua`.

The trackers take no part in the CDM aura-event sounds (`C_UnitAuras.AddAuraSound`). Until
2026-09-23 each handed `Core/CDMAlerts.lua` its tracked-spell map through a paired
`registerAlertSpells` / `unregisterAlertSpells`, and only those spells got a sound. CDMAlerts
now registers from Blizzard's alert config directly (`Core/CDMAlerts.md`, "Key resolution needs
two indices"), so the pairing and its teardown row are gone.

## Teardown

`OnDisable` is the whole undo for a discarded instance, and a hosted (Additional Frame)
tracker is discarded on every delete and every profile switch — `activateFrame` builds a
fresh instance table. WoW never garbage-collects a frame, so whatever stays armed keeps
running for the rest of the session. It mirrors `Core/IconTracker.lua`'s `OnDisable`
step for step:

| torn down | restored by | why |
|---|---|---|
| the three shared-bus callbacks | `OnEnable` → `registerTrackerCallbacks` | see above |
| `CustomSpells` registration | `OnEnable` | per-component spell records |
| every `auraEvents` registration | `OnEnable` re-registers **only** `PLAYER_TARGET_CHANGED` and `RegisterUnitEvent("UNIT_FACTION", "target", "player")` | the `OnEvent` closure's else arm calls `applyProcGlow(getSettings())`, which indexes its argument on the first line — a deleted AF's row is gone, so one proc-glow event would error per event forever. The `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW`/`_HIDE` pair is deliberately **not** re-registered here: `Refresh` owns it and re-arms it from the live settings. |
| `pairFrame`'s resize `OnUpdate` | the next groups-mode `syncContainerLayout` (the slots path clears it by design) | `UnregisterAllEvents` does **not** clear a script — the trap `IconTracker` records at its `spellWatcher` teardown. Mostly self-limiting, since an `OnUpdate` does not tick under a hidden ancestor; the in-combat branch below is exactly the window where the wrapper stays shown. |
| all three `AuraContainer`s, via `AuraContainer.Suspend` | **nothing — deliberately** | `AuraContainer.Create` ends in `SetEnabled(true)` and the only other disable path (`setContainerDemand`) is reachable solely from a `Refresh` a torn-down tracker never receives, so every abandoned set keeps parsing on each `UNIT_AURA` for its unit (`ParseAuras` early-returns only on a *disabled* container). Engine-side, so Lua memory sampling and `/cueperf` show nothing; the symptom is frame-time creep only `/reload` clears. `Suspend` **wipes** the demand record rather than writing `false`, so the next sync's `setContainerDemand(..., true)` sees a change and re-enables — adding an `OnEnable` counterpart would be wrong. |

The `wrapper:Hide()` is gated on `not InCombatLockdown()`, and the combat branch registers
the one-shot `deferredDisableHide` on `OnLeaveCombat` instead. Without it the bars/icons stay
on screen after the fight: `Anchor.Refresh` reaches the `skipPositioning` branch, which for a
disabled non-EditMode component calls neither `Show` nor `Hide`, so nothing catches up until
some unrelated full refresh fires. The handler reads the **settings row directly** rather than
`getEnabled()` — by the time it runs, a deleted AF's row is gone and an absent row means "not
enabled", i.e. hide. `tests/deferhide_check.lua` drives that closure, extracted verbatim from
all three factories, through both AF teardown-in-combat paths.

See `Core/AuraContainer.md` and `.context/patterns-auracontainer.md`.

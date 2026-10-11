# TrackingTab.lua

The Options **Tracking** tab (tab 4, `TAB_TRACKING`). It renders
`Core/TrackingModel.lua`'s `BuildSections()` as stacked, collapsible sections: the four
CDM trackers, every Additional Frame, and the untracked pool. Every row action calls a
`TrackingModel` action and re-reads the model; the tab never writes the profile itself,
with the two exceptions in [Header buttons](#header-buttons) and the four per-spell settings
in [Per-spell settings](#per-spell-settings). It replaced the Icon Overrides tab, whose
picker lives on as `Core/UI/IconPicker.lua`, and it is the **only** editor of every CDM
tracker's and every Additional Frame's spells: the Trackers tab's per-spell lists and the
Additional Frames tab's own spell list, item picker, custom-spell, pandemic-exclude,
bar-colour and Per-Spell Track On lists are all gone, each replaced by an **Edit spells in the Tracking tab** button
([Opening on a section](#opening-on-a-section)).

`private.TrackingTab.Build(panel)` is the entry point. `Options.lua` creates the
panel (`CUE_OptionsPanelTrackingPanel`, 980×532) and calls it from `CreateOptionsFrame`,
exactly where it used to call its own `buildIconOverridesTab`, then hooks the window's own
`OnShow` / `OnHide` to `TrackingTab.Attach` / `Detach` ([Rebuilds](#rebuilds)). Every other tab builder is a
file-local function inside `Options.lua`; this one is the first built as its own module,
so that a new tab does not grow a 13k-line file (it touches none of `Options.lua`'s
locals). The TOC loads it after `Options.lua`,
which is enough: `CreateOptionsFrame` is lazy (first `/cue`), so nothing calls `Build`
at load time.

## Layout

- **Top bar**: a search box, a **Show unlearned** checkbox and an **All specs** checkbox
  (`TrackingModel.SetAllSpecs`: Move, Remove and Reset moves use the all-specs override
  layer instead of the current spec's — `Core/TrackingModel.md` "Override layers" — as do
  reordering and Reset to default order for the icon order ("Icon order layers"), and a
  custom aura is added for every spec, or put back on every spec by its **This spec** box). All specs
  is hidden where `CDMDataSource.GetSpecLayerKey()` is nil at build (no spec system: there
  is only the one layer). **Collapse all** / **Expand all** at the right set every current
  section's `collapsed` entry at once (the pool included) and re-render. Blizzard's **Cooldown
  Manager Settings** button is the Options header's own, right above the tab; the tab does
  not repeat it.
- **One DF canvas scroll box** (`CreateCanvasScrollBox`, the Trackers tab's options),
  holding every section in `BuildSections()` order.
- **Section header**: collapse chevron (the header itself also toggles), title, row count
  (`shown/total` whenever a search or **Show unlearned** off hides rows). CDM tracker
  sections add **Reset to default order** and **Reset moves**.
- **Rows** below the header, from one shared pool. Every tracker and frame section with a
  bucket ends in an add-by-ID box: **Add aura by spell ID** on aura sections (BuffTracker,
  BuffTrackerBars, `buffs`/`bar` frames), **Add spell by spell ID** on cooldown sections
  (CooldownTracker, UtilitiesTracker, `spells` frames). A `spells` frame's box has an
  [Add item](#add-item) button beside it.

Section titles: the component display names (`COMP_*`) for trackers; the frame's `name`
for an Additional Frame, its id when unnamed (the Additional Frames tab's own fallback);
`TRACKING_POOL` for the pool. A switched-off frame (`section.disabled`) reads
`<name> (Disabled)` — in the header, the Move-to menu and tooltips alike — with a grey header
and dimmed rows, and stays fully editable. Its spells draw in their trackers until it is
switched back on, so each CDM row it holds is also listed in that tracker's section, with the
tracker's own controls (`Core/TrackingModel.md`).

## View state is session-local

Collapse state (`collapsed`, by section id), the search text, **Show unlearned** and
**All specs** live in module locals and are never written to the profile (All specs is
mirrored into the model's own session flag). The pool starts collapsed; every
other section starts expanded.

- **Search** filters rows by display name or key substring, case-insensitive, from **2**
  typed characters. The icon picker's own search filters from the first character; the
  threshold here is deliberate, since this list re-renders per keystroke.
- **Show unlearned** off hides rows with `learned == false` — not `known == false`: a spell
  the character has but no tracker draws (a lower rank on WoW Forever) is listed, marked
  inactive. On lists Cooldown Manager entries the character does not have — another spec's
  spells, untaken talents, and on WoW Forever every rank not yet learned — dimmed in their
  category's section, where **Move to** can place one ahead of time
  (`Core/TrackingModel.md`). Stale rows are exempt: they are
  leftovers to clean up, not unlearned spells. So are custom rows: the player added them, and
  an unusable one (a cooldown entry its `restrict_to_player` filters) must stay reachable so its **Only
  When Usable** box can be unticked — the retired custom-spell list showed every entry. Such a
  row keeps its `[not learned]` badge and dims. And so is any row the player saved something
  on: every row with a `listIndex` into a frame's `assigned_spells` (the retired Additional
  Frames list showed every entry, and **Remove** here is the only way left to take one out)
  and every row with an icon override (the retired Icon Overrides list showed every one).
  They dim like any unlearned row.

Neither re-reads the model: they call `render()` over the last `BuildSections()` result.

## Row

Left to right: icon button, name with badges, then the controls in **fixed
columns** — right to left **Remove**, **Move to**, **Down** / **Up** (section rows),
**Change icon**, [**Alerts**](#alerts) (section rows), then the
[per-spell settings](#per-spell-settings) (**Options**, then the
colour swatch), then **Rank** where the section has ranked rows. Which columns a row shows
is its **section's** (`sectionColumns`); whether each is enabled is the **row's**. So every
row of a section carries the same set, a control that does not apply is disabled rather than
hidden, and the same kind of button sits in one column down the whole section. A grey
**grip** sits in the row indent left of the icon on every row that can be
[dragged](#drag-and-drop).

| element | behaviour |
|---|---|
| icon | `row.texture` (TrackingModel already resolves an `icon_overrides` texture into it), fallback `134400`. A gold corner mark when `row.hasIconOverride`. **Left-click** opens `IconPicker.Open(panel, …)` → `SetIconOverride(row, texture)`; **right-click** → `ClearIconOverride(row)`. The row is captured when the picker opens, not read when it calls back. Inert on an Additional Frame addon-source row (`row.source`): a slot/category id is not a spell and has no `icon_overrides` entry. |
| Change icon | The icon's two clicks as a button, so an override is not a hidden feature; its tooltip says the icon changes everywhere the spell is shown. Disabled where the icon is inert. |
| Alerts | The spell's alerts menu, see [Alerts](#alerts). On every tracker and frame section row, disabled where the per-spell settings are (an item, a stale row, a `[duplicate]` `assigned` row). Its text leads with a marker per kind of alert the spell has, as Blizzard's settings window marks an item, so a row with alerts stands out. |
| name | `row.name`, then — on a stale row only — `row.rank` grey, in parentheses (every other ranked row shows its rank in the **Rank** column); for an Additional Frame addon-source row the retired Additional Frames list's labels — `TRINKET_SLOT_1`/`_2` for an empty slot, `CONSUMABLE_CAT_<KEY>` for a consumable category (via `ConsumableTracker.GetCategoryIDs`); the retired Icon Order list's item fallbacks (`ICON_ORDER_TRINKET` / `_CONSUMABLE` / `_CATEGORY_<id>`) for CDM item rows; otherwise `[unknown spell <id>]` |
| Rank | where the client has spell ranks (WoW Forever): a spell's ranks share one row, see [Spell ranks](#spell-ranks). A fixed-width button in the leftmost column, shown on the collapsed row, placed (hidden) on every other row of a section that has one so the names end in one line. |
| badges | `[not tracked on this spec]` for stale rows (`ICON_ORDER_UNTRACKED`, the retired Icon Order list's wording), `[not on this spec]` for a custom aura row with `thisSpec == false`, `[not learned]` for `learned == false`, `[inactive]` for a learned row nothing draws (`known == false`; its tooltip says why), `[in spellbook]` for `inSpellbook` (not on spellbook rows themselves), `[duplicate]` on an `assigned` row with `duplicateOf` (a second entry for a spell the frame already lists), `[by name: N]` / `[by name: looking up]` on a by-name custom aura (`byNameCount` / `byNamePending`). Stale, unlearned and inactive rows dim. |
| Up / Down | `TrackingModel.Reorder(sectionId, index, target)`. The target is the nearest **visible** neighbour, so a search or a hidden unlearned row never makes a click land out of sight. Disabled at the ends, where the neighbour is the same key, on an Additional Frame across the custom block (custom rows rank after every assigned entry), on and next to a stale row (stale rows close their section and draw nothing), and in a tracker section next to a row the tracker does not draw — one that is not `known`, or a custom duplicate — since it is not in the order `Reorder` materializes. |
| Move to | `MenuUtil.CreateContextMenu` built from `GetValidTargets(row)`; right-clicking anywhere on the row opens the same menu. Each entry calls `Move(row, targetId)` with no index: the end of the target, or Blizzard's position for it in a tracker that has no stored order, which then keeps following Blizzard's. A [drag](#drag-and-drop) always passes a position (past the last row for the end), so it places the row. Only legal targets are listed, per `GetValidTargets`' contract. Below the Move entries, a **Copy to** block lists `GetCopyTargets(row)` — the other bucket's trackers and frames — each calling `Copy(row, targetId)`: the spell is added there (an aura copy **Match by name** on) and the row stays, so one spell can be on a cooldown tracker and an aura tracker at once. One copy per type: once the spell is on the other bucket the block is a single disabled line, "Already on an aura tracker" / "Already on a cooldown tracker". The tab passes its built `sections` so this costs no extra build per row. The button is enabled when either list has an entry. Disabled, with a tooltip, when there are none (CDM item rows; an Additional Frame item with no other `spells` frame to go to; stale rows other than another spec's spell in a tracker, which can go to the other tracker of its kind). |
| Remove | `TrackingModel.Remove(row)`, enabled by `TrackingModel.CanRemove(row)` — the model's own checks, so the button is never live on a row `Remove` refuses. On a tracker's **CDM** row it hides the entry from that tracker (the override to -1/-2; the row moves to the pool, and **Move to** brings it back; tooltip `TRACKING_REMOVE_CDM_DESC`); on a **custom** row the entry leaves that host's `custom_spells`; on every **Additional Frame** row with a `listIndex` that is not custom — `cdm`, `item`, `assigned` — that one `assigned_spells` entry goes (the retired Additional Frames list's Remove; `TRACKING_REMOVE_ASSIGNED_DESC`); on a **stale** row the key leaves every list its `refs` name — its own section's lists only; an icon override is a pool row of its own, whose Remove clears it. Disabled on spellbook and pool CDM rows and on a tracker's item rows (`TRACKING_REMOVE_NONE_DESC`). |
| tooltip | `SetInventoryItem` for trinket rows, `SetSpellByID` (active id, `GetOverrideSpell`) for spell rows, the label otherwise; plus `In: <section>`; on a `[not on this spec]` row a line pointing at **This spec**; on a stale row one `Saved: <what> (<section>)` line per ref, so a leftover pandemic exclusion or bar colour says what it is |

**Move-to is a context menu, not a DF dropdown**: a plain DF `select` never calls its
top-level `set` (`.context/patterns.md`).

**Order lock.** Up/Down are disabled, with a tooltip, on a **bar** display
(`BuffTrackerBars`, `bar` frames) while its tracker's `IsUsingSlots()` is false — for a
frame that is the instance's `auraTracker` (`AdditionalFrameManager` `getAuraTracker`), not
the plain `instance.component` wrapper, which has no such method; a frame whose tracker is
not built yet is not locked. Under
Blizzard's compacting group the flow is `AuraContainerSortMethod.Default` and no addon order
reaches it (`Components/README.md`, "Icon Order"). It is the same `IsUsingSlots` read the
Options panels' `groupsEngine` gate uses. `BuffTracker` is not locked: its compacting
default is the per-spell groups engine, which does honour order. The retired Icon Order list
had no such gate — it only said so in its description text.

## Spell ranks

WoW Forever's Cooldown Manager has one entry per rank: Moonfire alone is ten ranks, each with
a cooldown and a buff entry. `collapseRanks` shows each list's ranked rows as **one row per
spell**: rows of one name, kind and bucket in one section, or in one pool group, since the
group key holds both. The row sits at the shown rank's own place in the order. It shows:
1. the rank the player picked (session-local `rankPick`, by group key, like **Show unlearned**);
2. else the highest rank the tracker draws, which for a whole family is its representative
   (`Core/CDMDataSource.md`, "Spell-rank families");
3. else the highest learned rank;
4. else the lowest.

**What the row stands for** (`rankModeOf`), which is also the **Rank** button's label:

| label | when |
|---|---|
| **All ranks** | a buff family whole in this tracker: one cell for whichever rank is up |
| **Highest** | a cooldown family whole in this tracker (drawn as the highest learned rank); a custom cooldown entry with `ranks = "highest"`; a Spellbook group not pinned to a rank, the default |
| the rank | anything else: the row stands for that rank |

Both family modes are the default: a family is whole whenever its ranks sit in one tracker,
which is where Blizzard's categories put them.

The **Rank** button opens a context menu. Each rank carries the badge its own row would
carry, and its place when it sits elsewhere: the section's title, or
`Not tracked: <pool group>`. By row:

- **Pool:** the group's own ranks, which only switch which rank the row shows. A Spellbook
  group adds **Highest**: a move or drag then creates a custom entry that follows the
  highest learned rank (`Move(…, "highest")`). Nothing is written until then.
- **Tracker, CDM row of a family:**
  - **All ranks** / **Highest** brings every rank here (`TrackingModel.SetFamilyMode`).
  - A rank makes it the only one here, and the spell's other ranks here go to Not tracked
    (`SetSingleRank`).
  - Taking a rank out of another tracker or frame asks first.
- **Custom cooldown row:** **Highest** or one exact rank, set in place (`SetCustomRank`).
- **Frame, and anything else:** a rank from elsewhere swaps in (`SwapRank`): it takes this
  row's place, and the rank shown goes to Not tracked.

Every confirmation is one dialog, `CLASSUIENHANCED_RANK_CONFIRM` (defined in `Build`). An
entry the model would refuse is listed disabled.

**In family mode the row acts for the whole spell.** Move, drag and Remove act on every rank
through the model (`familyRows`), and Up/Down moves the representative, the drawn key. A row
standing for one rank acts on that rank. Every rank stays its own row in the model. A group is
listed when **any** of its ranks passes the filters, so a learned spell's menu reaches its
unlearned ranks without **Show unlearned**. Stale rows never collapse: each is its own
leftover. Retail subtexts carry no digit, so no retail row has a `rank` and nothing collapses
there.

The header's `shown/total` still counts rows under the filters, one per rank, not collapsed
spells.

## Drag and drop

One controller for the whole tab, after Blizzard's CDM-settings flow
(`CooldownViewerSettingsMixin:BeginOrderChange` / `EndOrderChange` / `CancelOrderChange`),
built only on the tab's own frames.

**Start.** Each pooled row is `RegisterForDrag("LeftButton")` with its `OnDragStart` set
once, when the pool creates the frame; `placeRow` only sets `_cue_draggable` and shows the
grip. A row is draggable when `GetValidTargets` is non-empty or it has an Up/Down target (the
same neighbour gate, so a locked bar section's rows drag only to another section). The hit
rect is widened 10 px left over the grip. The drag cannot start from the icon or a button:
those children take the mouse-down. On start: `GetValidTargets(row)` is read **once** into a
set, the row dims to alpha 0.4 (a pooled row in a scroll child is never physically moved), a
lazily-created 24 px icon (parented to the panel, strata `TOOLTIP`) shows `row.texture`, and
the icon gets its `OnUpdate` and a `GLOBAL_MOUSE_UP` registration. Sound: `UI_CURSOR_PICKUP_OBJECT`.

**Each tick** (the icon's `OnUpdate`, `dragTick`, unwrapped — no `pcall` on our own code,
`.context/patterns.md`: a throw repeats each frame until the mouse-up, which ends the drag
whatever the tick did):

1. The icon is pinned to `GetCursorPosition()` divided by its own effective scale.
2. **Auto-scroll** while the cursor is inside the scroll box and within 24 px of its top or
   bottom edge, 400 px/s — `SetVerticalScroll` clamped to `GetVerticalScrollRange()`, the
   call `FocusSection` uses.
3. **Locate** from what is rendered, never a model read: the cursor (divided by the scroll
   child's effective scale) must be over the scroll box; its offset from the scroll child's
   top picks the section through `sectionTop`; within it, the drop lands before the first
   rendered row whose centre is below the cursor, or at the end. Over an expanded section's
   header it lands before the first row; a collapsed or empty section (Blizzard's
   `SetAsEmptyCategory` case) has no rows, so the drop appends, and so does a drop among the
   stale rows that close a section — as an index past the last row, never nil, so it places
   the row even in a tracker that follows Blizzard's order. Pool onto pool is no target.
4. **Marker**: a 2 px line child of the scroll child, above the target row or below the last
   row / the header. Gold over a legal drop, red (Blizzard's `ERROR_COLOR` values) over an
   illegal one, and the icon tints red with it. Re-anchored and re-tinted only on change.

Legal: another section in the cached target set; or the row's own section when it is not
order-locked and the trade passes `canSwap` (an Additional Frame's custom block). Dropping a
row beside itself does nothing and is legal in any section, locked or not — picking a row up
and putting it back never plays the error sound. The pool is never a target of a section row.

**Drop** (`GLOBAL_MOUSE_UP`, `LeftButton`; sound `UI_CURSOR_DROP_OBJECT`):

| where | does |
|---|---|
| own section | `Reorder(sectionId, fromIndex, toIndex)`, `toIndex` the rendered row the drop trades places with: moving up, the row below the gap; moving down, the row above it — Reorder's remove-then-insert-at-anchor semantics. Beside itself: nothing. Before committing, a fresh `BuildSections()` must still show both keys at those indices |
| another legal section | `Move(row, sectionId, index)`, `index` the `_cue_index` of the row the marker sits above, nil (append) otherwise. `Move` re-checks legality itself |
| illegal section, or a refused action | nothing; `COOLDOWN_LAYOUT_MANAGER_PLACEMENT_ERROR`, Blizzard's own sound for it |
| outside every section | nothing |

`RightButton` cancels. A committed action ends in `requestRebuild()`. `planDrop` reads
everything the drop needs off the rendered frames first, then `endDrag` tears the drag down,
then the commit runs — so a throw in the commit leaves no drag behind, with no `pcall`.

**Why the index check.** A rebuild requested mid-drag (`SPELLS_CHANGED`,
`OnCDMSpellsChanged`) is **held** — the deferred callback sets `rebuildAfterDrag` instead of
re-pooling the rows the drag is hit-testing — and the teardown re-requests it. The view can
therefore be a frame or more behind the model at the drop, and `Reorder` takes indices, so a
stale index could move a different row. `Move` needs no check: its legality is re-derived
from the row, a custom entry is validated by `listIndex` + key (a mismatch refuses), a spellbook
add by `customHas`, a CDM move removes and re-inserts **by key** in every list it touches, and
the target section comes from `Move`'s own fresh `BuildSections()` — so a stale `index` only
shifts the insertion point and can never move a different row. What could have made the view
stale synchronously mid-drag was one of the tab's own controls firing on the drop's mouse-up;
those are all guarded (below).

**Teardown.** `endDrag()` is the one teardown, idempotent and safe before `Build`: clears the
icon's `OnUpdate`, unregisters `GLOBAL_MOUSE_UP`, hides the icon and the marker, restores the
source row's alpha, drops the cached targets and the drop state, and re-requests a held
rebuild. Every exit calls it:

| exit | path |
|---|---|
| drop, committed or refused | `onDragMouseUp` → `planDrop`, `endDrag`, then the commit |
| right-click | `onDragMouseUp` → `endDrag` |
| error in a tick | the next mouse-up, as above |
| tab hidden / Options window closed | `Detach` → `endDrag`, **before** its `listening` guard |
| profile change | `OnProfileChanged` → `onProfileChanged` → `endDrag`, synchronously, so a drag never commits into a profile other than its own |
| any `render()` (search, collapse, `FocusSection`, rebuild) | `endDrag` first: re-pooling reassigns the source row frame |

**At rest nothing runs.** Neither frame exists until the first drag; after it, the icon keeps
only its `OnEvent` script with no event registered and no `OnUpdate`
(`.context/performance.md`, lesson 1).

A drop or a right-button cancel must not also act on what is under the cursor, since the
order of the drag's `GLOBAL_MOUSE_UP` and a control's own `OnClick` / `OnMouseUp` for the same
mouse-up is not known (the drag icon takes no mouse, so the control underneath still gets the
input). **Every** clickable control on a row or header returns early on `dragBusy()` — dragging,
or a drag ended this frame (`GetTime()` stamp): the icon's and **Change icon**'s override
pick/clear, the row's right-click Move-to menu, **Move to**, **Up** / **Down**, **Remove**, the colour swatch's write
callback and right-click clear, **Options**, **Alerts**, the collapse
toggle (chevron and header click share it), **Reset to default order** and **Reset moves**. The
Options menu's checkboxes need no guard: they live in Blizzard's menu frame, which a click
anywhere else closes, so no drag can end on one. Row and icon tooltips are suppressed while
dragging.

## Per-spell settings

Two [columns](#row) on tracker and frame section rows: the **colour swatch**, and an
**Options** button that opens a small menu (`openOptionsMenu`, a `MenuUtil` context menu like
**Move to**) with everything else. The menu's title is the row's name; below it, checkboxes,
then **Track On** as radios. A pick keeps the menu open (Blizzard's default `Refresh`
response), so several settings can be set in one go.

They replaced the Trackers tab's **Glow Spell Filter** and **Per-Spell Bar Colors** lists,
both tabs' **Per-Spell Track On** lists and the retired custom-spell lists' per-entry toggle,
which are gone. Until 2026-09-29 each menu entry was a column of its own; the user asked for
the checkboxes and the unit select to move into a menu behind one button per entry, when the
per-spell **Show Active Buff Duration** box was added.

Neither column is on a pool row. A section shows the **Options** column when it carries any
entry below (`sectionColumns`' `options`). The button is **disabled**, with a tooltip, on a row
none applies to (`rowOptions`), and the menu lists only the entries that apply to the row. The
four per-spell keys (active buff duration, pandemic, border colour, Track On) and the swatch need a spellID
to key a setting by, so they skip an item row (a trinket slot, a consumable category or an
Additional Frame addon-source entry), a stale row and a `[duplicate]` `assigned` row (the row
it duplicates carries the spell's controls). The retired lists also showed saved entries **no
row answers to**; here such an entry is a stale row of its section instead, cleared by its
**Remove**.

| entry | shown when | writes |
|---|---|---|
| **colour swatch** (column) | a bar section (`BuffTrackerBars`, `bar` frames) whose settings carry `bar_fill_color`, and not under the order lock above — under Blizzard's compacting group the button↔spell binding is secret, so a per-spell colour has nothing to key on (the retired Trackers-tab list's `IsUsingSlots` gate, the same condition as the order lock) | `spell_colors`. **Click** opens DF's colour picker (`CreateColorPickButton`, the widget a BuildMenu `color` entry builds); **right-click** clears. Shows the effective colour, dimmed while the row has none of its own and follows `bar_fill_color` |
| **Show Active Buff Duration** | a cooldown section (`section.bucket == "cooldown"`: CooldownTracker, UtilitiesTracker, `spells` frames — every section `IconTracker` draws). Not gated on `hide_active_swipe` being saved: a frame older than that key has none, and the reader treats nil as on | `active_swipe_excludes`. Checked = the buff takeover shows for this spell (`Core/IconTracker.md` "Per spell"); unchecked = excluded. No effect while the display's own Hide Active Buff Duration is on (the tooltip says so) |
| **Pandemic Border Glow** | the section's settings carry `pandemic_glow` at all (`~= nil`) — the retired Trackers-tab list's gate — and not under the order lock: the exclude needs the button's spell, which a bar display on Blizzard's compacting group does not carry (BuffTracker's per-spell groups do; bars wait on #47) | `pandemic_glow_excludes`. Checked = the glow shows for this spell; unchecked = excluded |
| **Border Color** (+ **Clear Border Color** once set) | an icon section: every section but `BuffTrackerBars` and `bar` frames (#8; bars wait on #47). Drawn by `IconTracker.placeIconButton`, `AuraIconTracker.restyleButton` and its grid `placeCell`; a plain group (Blizzard's compacting group without per-spell groups) has no button↔spell binding and keeps the global border | `spell_borders` (`Options.SetSpellBorder` / `ClearSpellBorder`, resolved over base and override like `spell_colors`). A Blizzard menu colour swatch (`CreateColorSwatch`) opening `ColorPickerFrame`, showing the spell's colour or, without one, the global `icon_border` colour; the picker writes on every change and **Cancel** restores what it found. An entry draws the border even while the global icon border is off; size and inside/outside stay global. The write runs `restyleSection` — `refreshSection` with `private.fontsDirty` raised, since the buff trackers draw the border in their restyle and a table-valued key never trips their `RESTYLE_KEYS` diff |
| **Glow When Missing** + **Missing Glow Color** | an aura icon section (`BuffTracker`, `buffs` frames) with `always_show_tracked` on: the glow lives on the slot cells, which only the slots engine has | `missing_glow` (`Options.SetMissingGlow` / `ClearMissingGlow`). The checkbox adds a red entry or clears it; the swatch is always built and greyed while the box is off, because a checkbox click re-initializes the open menu's elements without re-running its generator. The swatch reads the colour on click, so **Cancel** restores it. Writes run `refreshSection`: the glow is applied on the layout pass (`placeCell`), not the restyle. Drawn by `AuraIconTracker` (`Core/AuraTrackers.md` "Missing-buff glow") |
| **Only When Usable** | a **custom** row of a cooldown section | `restrict_to_player`, below |
| **This spec** | a **custom** row of an aura section, where a spec system exists | `specs`, below |
| **Match by name** | a **custom** row of an aura section | `by_name`, below |
| **Force Active** | a row `TrackingModel.CanForceActive` allows | `cdm_category_overrides.active`, below |
| **Track On** radios | an aura section (`section.bucket == "aura"`: `BuffTracker`, `BuffTrackerBars`, `buffs` and `bar` frames). Not under the order lock: both engines honour the scope (`AuraContainer.SplitByUnitScope` for groups, the per-filter test for slots) | `aura_unit`: **Both** / **Player** / **Target**. Both is the default and clears the entry |

The swatch and the three per-spell keys go through the helpers `Options.lua` exports —
`GetSpellColor` / `SetSpellColor` / `ClearSpellColor` / `IsExcluded` / `SetExcluded` (one pair
for both exclude lists, by key) / `GetAuraUnit` / `SetAuraUnit` — never a second copy of the
write. They resolve through `Util.ResolveByBaseOrOverride`, as the readers do
(`AuraBarTracker` `applyBarFill`, `AuraContainer` `syncPandemic`, `IconTracker`
`syncAuraSlots`), so an entry saved under the other id of a base/override pair is replaced or
removed rather than shadowed. `aura_unit`'s reader (`ExpandUnitScope`) looks keys up raw; its
helpers resolve anyway, to find an entry the retired Additional Frames list saved under the id
the user picked rather than under the row's key.

After such a write the menu runs the refresh the retired panel ran: `component.Refresh()` for
a CDM tracker, the Additional Frames tab's `refreshSelectedFrame` sequence
(`instance.component.Refresh()`, `RefreshAllComponents`, `Anchor.Refresh`) for a frame. No
model rebuild: none of the keys is part of `BuildSections()`. Those entries read the profile
each time the menu redraws, so they show the new state at once.

**Only When Usable** is the retired custom-spell lists' per-entry toggle, on custom rows of a
CDM tracker and of an Additional Frame alike. Checked = `restrict_to_player` (the default; a
legacy nil reads checked). It writes through `TrackingModel.SetRestrictToPlayer(row, value)`:
the model owns `custom_spells` and its refresh (`CustomSpells.Rebuild` +
`component.Refresh()`). **Cooldown sections only:** an aura host ignores `restrict_to_player`
(`CustomSpells` `shouldFilterEntry`), since an aura id is often in no spellbook — a poison's
debuff on the target (Amplifying Poison `383414`) read as `[not learned]` and never drew.

On an **aura** section that entry is **This spec** instead: the entry's spec scope (`specs`,
`Core/README.md` "Custom spells"), checked = `row.thisSpec`, written through
`TrackingModel.SetCustomSpec(row, value)`. A custom aura added here is stamped with the current
spec, so on another spec its row reads `[not on this spec]`, dims, and stays listed (custom
rows are exempt from **Show unlearned**) for that spec's box to opt it in. Absent without a
spec system (`GetSpecLayerKey()` nil), where `specs` is never read.

**Match by name** (#55) sits beside it: checked = `row.byName`, written through
`TrackingModel.SetCustomByName(row, value)`. On, the entry matches every spell id carrying its
spell's name (`Core/README.md` "Custom spells"). The first time a name is used,
`SpellNameScan` looks it up over a few seconds, and the row reads `[by name: looking up]` until
then. The box greys out (enabled as a function, so it re-reads after each click) while
`CanSetCustomByName(row, true)` refuses, that is, while another by-name entry of the tracker
has the same name. It is never greyed while on, so it can always be turned off. The tooltip
repeats the description, and the tab listens for `OnSpellNamesResolved` while attached so the
badge turns into the count. The typed add box and spellbook drags still add exact ids: by name
is never a default.

**Force Active** is for a CDM entry Blizzard's Cooldown Manager counts inactive although the
character has the spell (`[inactive]`). Checked = `row.forced`, written through
`TrackingModel.SetForceActive(row, value)` — every spec, no spec layer. A cooldown is drawn
only while the character has the spell; a spell rank never gets the entry (its Rank button
places it). The `[inactive]` tooltip points at it.

Those three read their state off the model's row, a snapshot, so each box keeps its own state
for as long as the menu is open. Each write ends in `requestRebuild()`, since the row's `known`
follows it.

The colour picker calls back for every wheel change and again on **Cancel** with the
colour it opened on. On a row with no colour of its own that is the fallback the swatch was
showing, so a callback matching it (within one colour step) writes nothing — otherwise
opening and cancelling would save the display's own bar colour as a per-spell entry.

The picker is not modal and stays open across renders, which hand the swatch's pooled frame
to other rows. So the swatch's DF `OnMouseUp` hook — run before DF opens the picker —
captures the row, section, settings table and fallback it is opened for
(`_cue_colorRow` …), and the callback writes to those, never to whatever the frame holds by
then. A frame that now shows another row is re-rendered after the write, so its swatch shows
that row's colour again.

## Alerts

The **Alerts** button opens `openAlertsMenu`, a `MenuUtil` context menu over CUE's own
per-spell alert list (`profile.spell_alerts[row.key]`, #3). The model, the merge into the
replay and the playback live in `Core/CDMAlerts.lua` ("CUE's own entries" in
`Core/CDMAlerts.md`); this file only edits the list.

- **What it lists.** CUE's entry for the spell when it has one (source line *Set in
  ClassUIEnhanced*), else the Cooldown Manager's alerts for it as of the last rebuild
  (*From the Cooldown Manager*, `CDMAlerts.GetSpellAlerts`). The Cooldown Manager's alerts
  CUE cannot play (`CDMAlerts.CanPlay` false: Pandemic, Charge Gained, text-to-speech on an
  aura event) are listed apart and greyed under *Played by the Cooldown Manager*, in both
  cases, because Blizzard's viewer plays them whatever the entry says (`NeedsBlizzardViewer`
  reads only the Cooldown Manager's list).
- **First edit copies.** Every change goes through `commit`: copy the shown list, apply the
  edit, `CDMAlerts.SetSpellAlerts(key, list)`. On a pre-filled list that copy is what creates
  CUE's entry; Blizzard's layout is never written. **Reset to Cooldown Manager** (shown with an
  entry) writes nil. Deleting every alert keeps an empty entry, which silences the spell.
- **Per alert**, a submenu: **Play Sample** (`CDMAlerts.PlaySample`, CUE's own players; a
  Visual plays on the row's icon), **When** as radios over the playable events, the sound or
  visual as radios, **Delete**. A sound or visual pick plays it and keeps the menu open
  (`MenuResponse.Refresh`), so the next one can be heard; any other change closes the whole
  menu (`CloseAll`), since a submenu's line text is fixed when the menu is built.
- **Add Alert**: type, then event, then the sound or visual; the pick adds it and plays it.
  Disabled at Blizzard's 3-per-spell cap. An exact duplicate is refused with a chat line.
- **Events.** A CDM row offers its entry's own set (`C_CooldownViewer.GetValidAlertTypes`);
  a custom or spellbook row offers its bucket's pair. Either way only what `CanPlay` allows.
- **Labels come from Blizzard's data, never their label functions** (which build file-local
  caches on first call): event names are their `COOLDOWN_VIEWER_SETTINGS_ALERT_WHEN_*`
  strings, sound names and categories walk `CooldownViewerSoundData` (categories named
  through `Enum.CooldownViewerSoundCategory` and `COOLDOWN_VIEWER_SETTINGS_SOUND_ALERT_CATEGORY_*`),
  visuals walk `VisualAlertData_ForEach`.
- **The known limit is shown, not fixed.** While an entry exists and Blizzard's viewer for the
  spell's category is shown (`CDMAlerts.BlizzardPlaysToo`: a Blizzard-only alert anywhere, or
  Target Debuff Sounds), Blizzard plays the Cooldown Manager's alerts next to CUE's, and a greyed
  orange line says so.
- **Markers.** The button text leads with Blizzard's own type atlases, `common-icon-sound` and
  `common-icon-visual` (the icons `CooldownViewerVisualAlertTarget.lua` puts on an item with
  alerts), one per kind of alert that plays for the spell (`CDMAlerts.GetSpellAlertTypes`: CUE's
  entry or else the Cooldown Manager's list, plus the Blizzard-only ones). Inline atlas markup
  rather than textures, so DF's pressed-text offset keeps working; every button is sized once
  for the text with both markers, so the column keeps one width. An item row is marked too,
  since its Cooldown Manager alerts still play. The model lands a debounce after an edit or a
  Cooldown Manager change, so the tab rebuilds on `OnAlertModelRebuilt` while it is shown.
- **Not on item rows.** `spell_alerts` is keyed by spellID; an item's alerts stay the Cooldown
  Manager's, which CUE keeps replaying. Not on pool rows either.

## Pool

Sub-grouped, because the groups differ in where a row may go and how it got there:

| sub-group | rows |
|---|---|
| Cooldowns | hidden CDM rows of the cooldown bucket (and bucketless item rows) |
| Auras | hidden CDM rows of the aura bucket |
| Spellbook | castable spells with no CDM row. **Add from spellbook is Move to**: TrackingModel's `Move` on a spellbook row is `AddFromSpellbook` on a cooldown section and a custom aura under the cast id on an aura section |
| Saved, but not tracked on this spec | icon overrides no live row answers to, each with **Remove** |

Every other leftover — an icon-order entry (in the order this spec reads: its own, else the
all-specs one, so another spec's own order never shows here), `assigned_spells`, `pandemic_glow_excludes`,
`active_swipe_excludes`, `spell_colors`, `spell_borders` or `missing_glow` entry nothing answers to — is a **stale row of the section that saved it**,
after the rows that section draws, so it sits where the player looks for that tracker or
frame and its **Remove** clears only that section's leftovers. An icon override belongs to no
section, so it is always a row of its own here, even when a section also has a leftover of
its key: a profile shared across characters can still draw it elsewhere. The tooltip lists
each ref so the row says what it holds.

With `cdm_auto_fetch` off the Cooldowns and Auras groups also hold every CDM entry no
Additional Frame claims: the trackers draw none of them (`Core/TrackingModel.md`). The
Saved group is what keeps an override for a spell no row answers to (another class's spell
in a shared profile) manageable now that the Icon Overrides tab is gone. A non-numeric key
is invisible to TrackingModel and so to this list. Right-click on any row's icon clears just
the override it shows (`ClearIconOverride`) and nothing else.

## Add by ID

Each tracker and frame section with a bucket has its own box, so the target needs no picker:
Enter → `tonumber` → `C_Spell.GetSpellName` must resolve → `TrackingModel.AddAuraByID(id,
sectionId)` on an aura section, `TrackingModel.AddFromSpellbook(id, sectionId)` on a cooldown
section. The latter takes any castable id, so an item-cast spell (Hearthstone, an engineering
gadget) that no spellbook row offers can still be added — the retired Trackers-tab box existed
on all four trackers. Such an entry is added restricted, as the old box did, so it shows
dimmed until its **Only When Usable** box is unticked. The pooled box is re-worded per section
(`TRACKING_ADD_AURA` / `TRACKING_ADD_SPELL`). An invalid id prints `CUSTOM_SPELLS_INVALID_ID`,
the custom-spell box's message; a refused add (already in the list) prints
`TRACKING_ADD_AURA_EXISTS` for both buckets — its wording is not aura-specific. The box
acts on **Enter only** — DF's text-entry callback also fires on focus loss, which would add
whatever was typed when the player merely clicked away, so the handler is a
`HookScript("OnEnterPressed")` instead. Enter on an empty box does nothing. The boxes are
pooled in section order, so a render that hands a box to another section (a collapse above
it, a search) clears its text: a half-typed id never follows the box into a section it was
not typed for.

## Add item

A `spells` Additional Frame section's add line carries an **Add item...** button beside the
typed box (the button is a child of the pooled box, shown only for `section.kind == "af"` and
`frameType == "spells"` — the one frame type that draws addon-owned icons). It opens a
`MenuUtil` context menu of `TrackingModel.GetAddonSourceChoices(sectionId)`, grouped under
`SOURCE_TRINKETS` / `SOURCE_CONSUMABLES` / `SOURCE_RACIALS` titles and worded as the retired
Additional Frames picker worded them: `Trinket 1: <item>` or `Trinket 1 (not equipped)`, the
consumable category name, the racial's spell name, each with its icon. A choice a frame
already holds (this one included) is disabled (`SetEnabled(false)` on the element
description) and says `(assigned to <frame>)`, as the picker greyed it out. Picking one calls
`TrackingModel.AddAddonSource(id, source, sectionId)`, which appends `{id, source}` to
`assigned_spells`, then `requestRebuild()`. The click is `dragBusy()`-guarded like every row
control.

These are not spell ids — a slot number, a consumable category, a racial the RacialTracker owns
— so the typed box cannot take them, and they have no pool row: the item rows exist only once
assigned. Once assigned, a row moves straight to another `spells` frame through **Move to** or a
drag (`GetValidTargets` / `Move`, `Core/TrackingModel.md`) — no Remove-then-Add. The greyed-out
menu entry stays: this menu adds, and the move lives on the row. Nothing here is specific to
item rows; the generic `GetValidTargets` gate picks them up.

## Header buttons

Both are handed to the model, and both take the same layer:

- **Reset to default order** — `TrackingModel.ResetOrder(sectionId)`: drops the current
  spec's own icon order, so the tracker follows the all-specs order (or Blizzard's when that
  is empty); with **All specs** ticked, empties the all-specs order. Other specs' own orders
  stay. Enabled by `TrackingModel.HasOrder(sectionId)`.
- **Reset moves** — `TrackingModel.ResetMoves(bucket)`: wipes the bucket map of one override
  layer (the current spec's, or the all-specs one with **All specs** ticked) and notifies.
  The map is per **bucket**, so this resets both trackers of the bucket (cooldowns or
  buffs); the tooltip says so. Disabled while `HasMoves(bucket)` is false.

## Opening on a section

`TrackingTab.FocusSection(componentName)` expands one section and scrolls it into view. Its
caller is `Options.OpenOptionsPanel(TRACKING_TAB_INDEX, componentName)`, and through it the
Trackers tab's **Edit spells in the Tracking tab** button on each CDM tracker and the
Additional Frames tab's button of the same name on each frame. It takes the names the Options
panels use: a CDM tracker's component name, which is its section id too, or
`AdditionalFrame_<id>`, mapped to `af:<id>`.

The request is kept in `pendingFocus` and served by the next render that has the model: a
not-ready model (placeholder) keeps it, and a ready render drops it when the section does
not exist, so a frame deleted meanwhile is never scrolled to later. `render()` records each
header's offset in `sectionTop` and computes the scroll the header needs from the height it
just gave the scroll child — never read back, and never a timer. `SetVerticalScroll` goes
through the scrollbar, which clamps to its maximum (`ScrollFrame_OnVerticalScroll` →
`scrollbar:SetValue`), and Blizzard moves that maximum only in `OnScrollRangeChanged`. So
`applyFocus` scrolls at once when the range already covers the target, and otherwise the
`OnScrollRangeChanged` hook calls it again once Blizzard's own handler has raised the range.
The expanded state is ordinary session-local collapse state.

## Rebuilds

| trigger | does |
|---|---|
| panel `OnShow`, Options window `OnShow` | `Attach`: while the panel is the selected tab and not already listening, registers `OnCDMSpellsChanged`, `OnProfileChanged`, `SPELLS_CHANGED` and `SPELL_TEXT_UPDATE` (a row's rank reads `""` until the spell's data has loaded), then rebuilds once, synchronously |
| panel `OnHide`, Options window `OnHide` | `Detach`: ends any drag, unregisters all four |
| any of the four while shown | `requestRebuild()`; `OnProfileChanged` ends any drag first |
| a drag in progress | the deferred rebuild waits for the drag's teardown ([Drag and drop](#drag-and-drop)) |
| every row / header action | `requestRebuild()` straight after the `TrackingModel` call — no event round-trip |
| per-spell colour, active buff duration, pandemic or Track On write | nothing (the control shows its own state); a colour **clear** calls `render()` to re-draw the swatch |
| Only When Usable, This spec, Match by name, Force Active toggles | `requestRebuild()` — `known` changes with them |
| search, Show unlearned, All specs, collapse | `render()` only (All specs re-reads each header's two Reset buttons' state) |

The window hooks exist because a tab switch (`selectTab`) is not the only way the tab
appears or goes: closing the window (close button, ESC through `UISpecialFrames`,
`CloseOptionsPanel`) and reopening it with Tracking still selected never call the panel's
own `Show` / `Hide`. Both paths may fire for one open or close, so `Attach` and `Detach`
are idempotent behind a `listening` flag — at most one rebuild per reopen.

`requestRebuild` coalesces to one rebuild per frame — a pending flag plus
`C_Timer.After(0)`, the LibSharedMedia batching idiom (`.context/patterns.md`, "Events &
callbacks") — because `BuildSections()` walks the whole spellbook and `SPELLS_CHANGED`
arrives in storms. The deferred callback re-checks `IsVisible()`.

Actions go through the deferred path rather than rebuilding synchronously for a second
reason: a Move, Remove or Reset moves ends in `NotifyUserCategoryChanged`, which invalidates
the CDM model **synchronously** and queues `OnCDMSpellsChanged`, which invalidates it once
more. A same-frame rebuild would build the model only for that to drop it; deferred, the
rebuild lands after the callback and reads the model its consumers just built.

**Builds the model only through `CDMDataSource.ResolveNow()`.** `refreshData` calls it
before `BuildSections()`, because the tab cannot rely on anyone else: with every CDM tracker
disabled and no Additional Frame, `OnCDMSpellsChanged` rebuilds nothing, and the tab's own
edits drop the model, which left it on the placeholder until the player switched tabs.
`ResolveNow` declines before `CDMDataSource.Initialize()` (`LOADING_SCREEN_DISABLED`), so it
never builds early (`.context/patterns.md`, "Lazy caches vs init order"). If it declines,
`BuildSections()` reports not-ready, the tab renders a single `TRACKING_NOT_READY` line, and
it waits for `OnCDMSpellsChanged`. After that the model always resolves, even with no CDM data
at all (a WoW Forever Shaman, Rogue, Hunter or Paladin): the four tracker sections are then
empty, and the spellbook and custom spells work as anywhere else.

## Frames

Everything here is an addon-owned Options frame parented under the panel — the drag icon and
the reorder marker included. Per-row state
(`_cue_row`, `_cue_section`, `_cue_index`, reorder targets, `_cue_draggable`, the swatch's `_cue_fallback` and its captured `_cue_color*` target) is
stored on those frames, the retired Icon Order list's convention, and safe for the same
reason: no CooldownViewer frame, aura button
or protected frame is ever touched.
